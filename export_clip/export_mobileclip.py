"""Exports one of Apple's MobileCLIP models (S0 by default, which is what the app ships) to the two ONNX files the
app loads.

  mobileclip_<variant>_vision.onnx   image tower, weights in fp32, float32 in and out
  mobileclip_<variant>_text.onnx     text tower, weights in int8 (dynamic quantization), float32 out

The image tower stays in fp32 on purpose: an fp16 copy of the S2 one gave NaN on a real phone (the numbers inside
overflow in half precision), although it was fine on a PC. See MOBILECLIP_SOURCE.md.

The two files have the same interface as the CLIP ViT-B/32 ones they replace: input `pixel_values` (batch, 3, 256,
256) -> `image_embeds` (batch, 512), input `input_ids` (batch, 77, int64) -> `text_embeds` (batch, 512), both already
L2-normalised. Only the image size (256, pixels scaled to 0..1, no mean/std) is different.

Where the weights come from, and under what licence: see MOBILECLIP_SOURCE.md. The checkpoint is Apple's own
2024 `mobileclip_<variant>.pt`; Apple's code (commit 341ef05) is only used to load it and is not shipped.

Usage (from this folder):
  python export_mobileclip.py --code <folder holding Apple's `mobileclip` package> --variant s0 \
      --checkpoint weights/mobileclip_s0.pt --out out_mobileclip_s0
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


# The one layer of the text tower that int8 cannot take (the feed-forward output weights of one transformer layer):
# with it quantized the vectors of the same sentence drift to a cosine of 0.91 (S2) or 0.95 (S0) from the fp32 model;
# with it left in full precision they stay at 0.996 or better (mean 0.998), for 3 MB more. Found by leaving out one
# layer at a time (see MOBILECLIP_SOURCE.md). S0's text tower is shallower, so its layer has another number.
TEXT_FP32_LAYER = {
    "s0": "/text_encoder/transformer.1/pre_norm_ffn/pre_norm_ffn.4/MatMul",
    "s1": "/text_encoder/transformer.0/pre_norm_ffn/pre_norm_ffn.4/MatMul",
    "s2": "/text_encoder/transformer.0/pre_norm_ffn/pre_norm_ffn.4/MatMul",
}


def prepare_torch():
    F.scaled_dot_product_attention = mobile_compatible_sdpa
    torch.backends.mha.set_fastpath_enabled(False)
    try:
        from timm.layers import set_fused_attn

        set_fused_attn(False)
    except Exception:  # older timm
        pass


def load_model(code_dir: str, checkpoint: str, variant: str):
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
        f"mobileclip_{variant}", pretrained=None, reparameterize=False
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


def export_vision(model, out_dir: str, variant: str) -> str:
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
    add_l2_normalize(fp32, "image_features", "image_embeds")
    target = os.path.join(out_dir, f"mobileclip_{variant}_vision.onnx")
    onnx.save(fp32, target)
    return target


def export_text(model, out_dir: str, variant: str) -> str:
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
    target = os.path.join(out_dir, f"mobileclip_{variant}_text.onnx")
    quantize_dynamic(
        prepared,
        target,
        weight_type=QuantType.QInt8,
        per_channel=True,
        # The 49408 x 512 token table is a third of the model: it is quantized too.
        op_types_to_quantize=["MatMul", "Gather"],
        # The one layer int8 cannot take: see TEXT_FP32_LAYER.
        nodes_to_exclude=[TEXT_FP32_LAYER[variant]],
    )
    return target


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--code", required=True, help="folder that contains Apple's `mobileclip` package")
    parser.add_argument("--variant", default="s0", choices=sorted(TEXT_FP32_LAYER))
    parser.add_argument("--checkpoint", default=None, help="default: weights/mobileclip_<variant>.pt")
    parser.add_argument("--out", default=None, help="default: out_mobileclip_<variant>")
    args = parser.parse_args()
    args.checkpoint = args.checkpoint or f"weights/mobileclip_{args.variant}.pt"
    args.out = args.out or f"out_mobileclip_{args.variant}"

    torch.backends.mkldnn.enabled = False
    torch.backends.mkl.enabled = False
    prepare_torch()
    os.makedirs(args.out, exist_ok=True)

    print(f"Loading MobileCLIP-{args.variant.upper()} from the 2024 checkpoint...")
    model, _ = load_model(args.code, args.checkpoint, args.variant)

    t = time.time()
    print("Exporting the image tower (fp32)...")
    vision = export_vision(model, args.out, args.variant)
    print(f"  {vision}  {os.path.getsize(vision) / 1e6:.1f} MB  ({time.time() - t:.0f} s)")

    t = time.time()
    print("Exporting the text tower (int8)...")
    text = export_text(model, args.out, args.variant)
    print(f"  {text}  {os.path.getsize(text) / 1e6:.1f} MB  ({time.time() - t:.0f} s)")

    total = os.path.getsize(vision) + os.path.getsize(text)
    print(f"\nTotal download: {total / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
