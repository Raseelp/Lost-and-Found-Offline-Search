"""Checks the two exported MobileCLIP-S2 files against Apple's PyTorch model, and against the CLIP ViT-B/32 files
they replace, on the tour's sample photos.

  1. The ONNX image tower (fp16) against PyTorch (fp32): cosine similarity of each photo's vector; a batch of
     several gives the same vectors as one at a time.
  2. The ONNX text tower (int8) against PyTorch (fp32), and the length of every vector (must be 1).
  3. The tokens the app's tokenizer produces against the ones Apple's model was trained with (read from a file the
     Dart side writes: see tokens_from_dart.json), when that file is there.
  4. Searching the sample photos with a few hand-written queries: where the right photo ranks, for PyTorch,
     for the exported files and for the old CLIP files.

Usage (from this folder):
  python verify_mobileclip_s2.py --code <folder holding Apple's `mobileclip` package>
"""
import argparse
import glob
import json
import os
import sys

import numpy as np
import onnxruntime as ort
import open_clip
import torch
from PIL import Image

import export_mobileclip_s2 as export

PHOTOS = os.path.join(os.path.dirname(__file__), "..", "assets", "tour", "photos")

# Query -> photos that are right for it (file names without .jpg).
QUERIES = {
    "a dog on a beach": ["dog_beach"],
    "a puppy": ["puppy"],
    "a cat": ["cat"],
    "a birthday cake": ["cake", "apple_cake"],
    "friends at the beach": ["friends_beach"],
    "the Taj Mahal": ["tajmahal"],
    "a boat on the water": ["houseboat", "kayak"],
    "a sunset": ["sunset"],
    "hiking in the mountains": ["hike", "snow_hike"],
    "someone riding a bike": ["cycling"],
    "a person running": ["running"],
    "people dancing": ["dance"],
    "a football stadium": ["pro_sansiro", "pro_fans", "supercup"],
    "a kayak": ["kayak"],
    "snow": ["snow_hike"],
    "a party": ["party"],
    "an old red stone tower": ["qutub"],
    "friends walking together": ["friends_walk"],
}


def cosine(a, b):
    a, b = a.reshape(-1), b.reshape(-1)
    return float(np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b)))


def rank_of(scores, names, right):
    order = [names[i] for i in np.argsort(-scores)]
    return min(order.index(r) for r in right) + 1


def old_clip_pixels(img: Image.Image) -> np.ndarray:
    """What the app feeds the old CLIP model: shorter side to 224, centre crop, CLIP mean/std."""
    w, h = img.size
    s = 224 / min(w, h)
    img = img.resize((max(224, round(w * s)), max(224, round(h * s))), Image.BICUBIC)
    left, top = (img.width - 224) // 2, (img.height - 224) // 2
    img = img.crop((left, top, left + 224, top + 224))
    x = np.asarray(img, dtype=np.float32) / 255.0
    mean = np.array([0.48145466, 0.4578275, 0.40821073], dtype=np.float32)
    std = np.array([0.26862954, 0.26130258, 0.27577711], dtype=np.float32)
    return ((x - mean) / std).transpose(2, 0, 1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--code", required=True)
    ap.add_argument("--checkpoint", default="weights/mobileclip_s2.pt")
    ap.add_argument("--out", default="out_mobileclip_s2")
    args = ap.parse_args()

    torch.backends.mkldnn.enabled = False
    torch.backends.mkl.enabled = False
    export.prepare_torch()
    model, preprocess = export.load_model(args.code, args.checkpoint)
    tokenizer = open_clip.get_tokenizer("ViT-B-16")  # the tokenizer Apple's config names

    vision = ort.InferenceSession(os.path.join(args.out, "mobileclip_s2_vision.onnx"), providers=["CPUExecutionProvider"])
    text = ort.InferenceSession(os.path.join(args.out, "mobileclip_s2_text.onnx"), providers=["CPUExecutionProvider"])
    print("vision inputs", [(i.name, i.type, i.shape) for i in vision.get_inputs()], "outputs", [(o.name, o.type, o.shape) for o in vision.get_outputs()])
    print("text   inputs", [(i.name, i.type, i.shape) for i in text.get_inputs()], "outputs", [(o.name, o.type, o.shape) for o in text.get_outputs()])

    paths = sorted(glob.glob(os.path.join(PHOTOS, "*.jpg")))
    names = [os.path.basename(p)[:-4] for p in paths]
    images = [Image.open(p).convert("RGB") for p in paths]
    print(f"\n{len(images)} sample photos")

    # ---- 1. image tower
    pixels = torch.stack([preprocess(im) for im in images])  # Apple's own resize + crop, 0..1
    with torch.no_grad():
        ref_img = torch.nn.functional.normalize(model.encode_image(pixels), dim=-1).numpy()
    px = pixels.numpy().astype(np.float32)
    onnx_img = np.concatenate([vision.run(None, {"pixel_values": px[i : i + 1]})[0] for i in range(len(px))])
    batched = np.concatenate([vision.run(None, {"pixel_values": px[i : i + 6]})[0] for i in range(0, len(px), 6)])
    cos = [cosine(a, b) for a, b in zip(ref_img, onnx_img)]
    cos_b = [cosine(a, b) for a, b in zip(onnx_img, batched)]
    print(f"\nIMAGE  fp16 ONNX vs PyTorch fp32: cosine min {min(cos):.5f}  mean {np.mean(cos):.5f}")
    print(f"IMAGE  batch of 6 vs one at a time: cosine min {min(cos_b):.6f}")
    print(f"IMAGE  vector lengths: {np.linalg.norm(onnx_img, axis=1).min():.5f} .. {np.linalg.norm(onnx_img, axis=1).max():.5f}")

    # ---- 2. text tower
    qs = list(QUERIES)
    tokens = tokenizer(qs).to(torch.long)
    with torch.no_grad():
        ref_txt = torch.nn.functional.normalize(model.encode_text(tokens), dim=-1).numpy()
    onnx_txt = np.concatenate([text.run(None, {"input_ids": tokens[i : i + 1].numpy()})[0] for i in range(len(qs))])
    cos_t = [cosine(a, b) for a, b in zip(ref_txt, onnx_txt)]
    print(f"\nTEXT   int8 ONNX vs PyTorch fp32: cosine min {min(cos_t):.5f}  mean {np.mean(cos_t):.5f}")
    print(f"TEXT   vector lengths: {np.linalg.norm(onnx_txt, axis=1).min():.5f} .. {np.linalg.norm(onnx_txt, axis=1).max():.5f}")

    # ---- 3. tokens from the app's own tokenizer, if they were written
    dart = os.path.join(os.path.dirname(__file__), "tokens_from_dart.json")
    if os.path.exists(dart):
        theirs = json.load(open(dart, encoding="utf-8"))
        bad = [t for t, ids in theirs.items() if ids != tokenizer([t])[0].tolist()]
        print(f"\nTOKENS the app tokenizer vs open_clip: {len(theirs) - len(bad)} of {len(theirs)} texts the same")
        for t in bad:
            print("   different:", ascii(t[:60]))

    # ---- 4. searching the sample photos
    old_v = os.path.join(os.path.dirname(__file__), "clip_vision.onnx")
    old_t = os.path.join(os.path.dirname(__file__), "clip_text.onnx")
    old = None
    if os.path.exists(old_v) and os.path.exists(old_t):
        old = (
            ort.InferenceSession(old_v, providers=["CPUExecutionProvider"]),
            ort.InferenceSession(old_t, providers=["CPUExecutionProvider"]),
        )
        old_img = np.concatenate([old[0].run(None, {"pixel_values": old_clip_pixels(im)[None]})[0] for im in images])
        old_tokens = open_clip.get_tokenizer("ViT-B-32")(qs).numpy()
        old_txt = np.concatenate([old[1].run(None, {"input_ids": old_tokens[i : i + 1]})[0] for i in range(len(qs))])

    app_tokens = None
    if os.path.exists(dart):
        theirs = json.load(open(dart, encoding="utf-8"))
        if all(q in theirs for q in qs):
            app_tokens = np.array([theirs[q] for q in qs], dtype=np.int64)
            app_txt = np.concatenate([text.run(None, {"input_ids": app_tokens[i : i + 1]})[0] for i in range(len(qs))])
            app_old = (
                np.concatenate([old[1].run(None, {"input_ids": app_tokens[i : i + 1]})[0] for i in range(len(qs))])
                if old
                else None
            )
    print(f"\n{'query':32s} {'PyTorch':>8s} {'exported':>9s} {'old CLIP':>9s}   (rank of the right photo; 1 is best)")
    top1 = {"torch": 0, "onnx": 0, "old": 0}
    top3 = {"torch": 0, "onnx": 0, "old": 0}
    for i, q in enumerate(qs):
        r_t = rank_of(ref_img @ ref_txt[i], names, QUERIES[q])
        r_o = rank_of(onnx_img @ onnx_txt[i], names, QUERIES[q])
        r_c = rank_of(old_img @ old_txt[i], names, QUERIES[q]) if old else 0
        for key, r in (("torch", r_t), ("onnx", r_o), ("old", r_c)):
            top1[key] += r == 1
            top3[key] += r <= 3
        print(f"{q:32s} {r_t:8d} {r_o:9d} {r_c:9d}")
    n = len(qs)
    if app_tokens is not None:
        a1 = a3 = o1 = o3 = 0
        for i, q in enumerate(qs):
            ra = rank_of(onnx_img @ app_txt[i], names, QUERIES[q])
            ro = rank_of(old_img @ app_old[i], names, QUERIES[q]) if old else 0
            a1 += ra == 1
            a3 += ra <= 3
            o1 += ro == 1
            o3 += ro <= 3
        print("\nWith the tokens the app produces today (not open_clip's):")
        print(f"  exported MobileCLIP: first {a1}/{n}, top 3 {a3}/{n}      old CLIP: first {o1}/{n}, top 3 {o3}/{n}")
    print(f"\nright photo first:   PyTorch {top1['torch']}/{n}   exported {top1['onnx']}/{n}   old CLIP {top1['old']}/{n}")
    print(f"right photo in top 3: PyTorch {top3['torch']}/{n}   exported {top3['onnx']}/{n}   old CLIP {top3['old']}/{n}")


if __name__ == "__main__":
    main()
