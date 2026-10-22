"""Exports Apple's MobileCLIP-S2 to the two ONNX files the app loads.

  mobileclip_s2_vision.onnx   image tower, weights in fp16, float32 in and out
  mobileclip_s2_text.onnx     text tower, weights in int8 (dynamic quantization), float32 out

The two files have the same interface as the CLIP ViT-B/32 ones they replace: input `pixel_values` (batch, 3, 256,
256) -> `image_embeds` (batch, 512), input `input_ids` (batch, 77, int64) -> `text_embeds` (batch, 512), both already
L2-normalised. Only the image size (256, pixels scaled to 0..1, no mean/std) is different.

Where the weights come from, and under what licence: see MOBILECLIP_S2_SOURCE.md. The checkpoint is Apple's own
2024 `mobileclip_s2.pt`; Apple's code (commit 341ef05) is only used to load it and is not shipped.

Usage (from this folder):
  python export_mobileclip_s2.py --code <folder holding Apple's `mobileclip` package> \
      --checkpoint weights/mobileclip_s2.pt --out out_mobileclip_s2
"""
import argparse
import os
import sys
import time

import numpy as np
import onnx
import torch
import torch.nn.functional as F
from onnx import TensorProto, helper


def mobile_compatible_sdpa(query, key, value, attn_mask=None, dropout_p=0.0, is_causal=False, **_):
    # Same patch as the CLIP ViT-B/32 exports: the fused attention op does not export to ONNX on every path.
    scale = query.size(-1) ** -0.5
    attn = torch.matmul(query, key.transpose(-2, -1)) * scale
    if attn_mask is not None:
        attn = attn + attn_mask
    attn = F.softmax(attn, dim=-1)
    return torch.matmul(attn, value)


def prepare_torch():
    F.scaled_dot_product_attention = mobile_compatible_sdpa
    torch.backends.mha.set_fastpath_enabled(False)
    try:
        from timm.layers import set_fused_attn

        set_fused_attn(False)
    except Exception:  # older timm
        pass


def load_model(code_dir: str, checkpoint: str):
    """Apple's model, loaded from the 2024 checkpoint and folded into its inference form."""
    sys.path.insert(0, code_dir)
    import mobileclip
    from mobileclip.modules.common import mobileone
    from mobileclip.modules.common.mobileone import reparameterize_model

    def squeeze_excite(self, inputs):
        # Apple's version pools with a kernel taken from the input's own size, which the exporter cannot treat as
        # constant. Averaging over the whole map is the same thing, written so that it exports.
        x = F.adaptive_avg_pool2d(inputs, 1)
        x = torch.sigmoid(self.expand(F.relu(self.reduce(x))))
        return inputs * x

    mobileone.SEBlock.forward = squeeze_excite

    model, _, preprocess = mobileclip.create_model_and_transforms(
        "mobileclip_s2", pretrained=None, reparameterize=False
    )
    # weights_only: the checkpoint is a download, so it is read as plain tensors and nothing else.
    state = torch.load(checkpoint, map_location="cpu", weights_only=True)
    model.load_state_dict(state)
    model.eval()
    # Without this the image tower keeps its training-time branches: bigger, slower and not what Apple measured.
    model = reparameterize_model(model)
    return model.eval(), preprocess


class VisionWrapper(torch.nn.Module):
    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, x):
        return self.model.encode_image(x, normalize=False)


class TextWrapper(torch.nn.Module):
    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, tokens):
        return self.model.encode_text(tokens, normalize=False)


def add_l2_normalize(model: onnx.ModelProto, source: str, target: str) -> None:
    """Appends x / ||x|| (in float32) and makes it the model's only output, called [target]."""
    graph = model.graph
    norm = target + "_norm"
    graph.node.append(helper.make_node("ReduceL2", [source], [norm], axes=[-1], keepdims=1))
    graph.node.append(helper.make_node("Div", [source, norm], [target]))
    while len(graph.output):
        graph.output.pop()
    graph.output.append(
        helper.make_tensor_value_info(target, TensorProto.FLOAT, ["batch", 512])
    )


def export_vision(model, out_dir: str) -> str:
    from onnxconverter_common import float16

    work = os.path.join(out_dir, "work")
    os.makedirs(work, exist_ok=True)
    raw = os.path.join(work, "vision_fp32.onnx")
    example = torch.randn(1, 3, 256, 256)
    with torch.no_grad():
        torch.onnx.export(
            VisionWrapper(model).eval(),
            example,
            raw,
            input_names=["pixel_values"],
            output_names=["image_features"],
            # The batch axis must stay dynamic: one photo, a scan's small batches, and every frame of a video.
            dynamic_axes={"pixel_values": {0: "batch"}, "image_features": {0: "batch"}},
            opset_version=17,
            do_constant_folding=True,
        )
    fp32 = onnx.load(raw)
    # Weights and maths in fp16; the cast nodes at the ends keep the interface float32.
    fp16 = float16.convert_float_to_float16(fp32, keep_io_types=True)
    add_l2_normalize(fp16, "image_features", "image_embeds")
    target = os.path.join(out_dir, "mobileclip_s2_vision.onnx")
    onnx.save(fp16, target)
    return target


def export_text(model, out_dir: str) -> str:
    from onnxruntime.quantization import QuantType, quantize_dynamic
    from onnxruntime.quantization.shape_inference import quant_pre_process

    work = os.path.join(out_dir, "work")
    os.makedirs(work, exist_ok=True)
    raw = os.path.join(work, "text_fp32.onnx")
    example = torch.zeros((1, 77), dtype=torch.long)
    example[0, 0], example[0, 1], example[0, 2] = 49406, 723, 49407
    with torch.no_grad():
        torch.onnx.export(
            TextWrapper(model).eval(),
            example,
            raw,
            input_names=["input_ids"],
            output_names=["text_features"],
            dynamic_axes={"input_ids": {0: "batch"}, "text_features": {0: "batch"}},
            opset_version=17,
            do_constant_folding=True,
        )
    with_norm = os.path.join(work, "text_fp32_norm.onnx")
    m = onnx.load(raw)
    add_l2_normalize(m, "text_features", "text_embeds")
    onnx.save(m, with_norm)
    prepared = os.path.join(work, "text_fp32_prepared.onnx")
    quant_pre_process(with_norm, prepared)
    target = os.path.join(out_dir, "mobileclip_s2_text.onnx")
    quantize_dynamic(
        prepared,
        target,
        weight_type=QuantType.QInt8,
        per_channel=True,
        # The 49408 x 512 token table is a third of the model: it is quantized too.
        op_types_to_quantize=["MatMul", "Gather"],
        # The one layer int8 cannot take: with it quantized the vectors of the same sentence drift to a cosine of
        # 0.91 (mean 0.976) from the fp32 model; with it left in full precision they stay at 0.996 or better (mean
        # 0.998), for 3.4 MB more. Found by trying every group of layers (see the notes in MOBILECLIP_S2_SOURCE.md).
        nodes_to_exclude=["/text_encoder/transformer.0/pre_norm_ffn/pre_norm_ffn.4/MatMul"],
    )
    return target


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--code", required=True, help="folder that contains Apple's `mobileclip` package")
    parser.add_argument("--checkpoint", default="weights/mobileclip_s2.pt")
    parser.add_argument("--out", default="out_mobileclip_s2")
    args = parser.parse_args()

    torch.backends.mkldnn.enabled = False
    torch.backends.mkl.enabled = False
    prepare_torch()
    os.makedirs(args.out, exist_ok=True)

    print("Loading MobileCLIP-S2 from the 2024 checkpoint...")
    model, _ = load_model(args.code, args.checkpoint)

    t = time.time()
    print("Exporting the image tower (fp16)...")
    vision = export_vision(model, args.out)
    print(f"  {vision}  {os.path.getsize(vision) / 1e6:.1f} MB  ({time.time() - t:.0f} s)")

    t = time.time()
    print("Exporting the text tower (int8)...")
    text = export_text(model, args.out)
    print(f"  {text}  {os.path.getsize(text) / 1e6:.1f} MB  ({time.time() - t:.0f} s)")

    total = os.path.getsize(vision) + os.path.getsize(text)
    print(f"\nTotal download: {total / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
