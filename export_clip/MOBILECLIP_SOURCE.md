# Where the MobileCLIP weights came from

Recorded 2026-10-22, before the search model was switched from OpenAI CLIP ViT-B/32 to Apple MobileCLIP-S2; changed
on 2026-10-23 to the smaller MobileCLIP-S0 (see "Why S0" below). The app ships S0. S1 and S2 are kept here because
the export scripts take any of the three (`--variant`).

## The weights

S0, the model the app ships (retrieved 2026-10-23):

- File: `mobileclip_s0.pt`, https://docs-assets.developer.apple.com/ml-research/datasets/mobileclip/mobileclip_s0.pt
  (`Last-Modified: Tue, 27 Feb 2024 10:33:26 GMT`, 215,934,653 bytes).
- SHA-256: `809b408eff74f8058843e86a1f92967097d42ba782450e85b8f4867b7f0ca0b7`
- The README of apple/ml-mobileclip lists MobileCLIP-S0 as 11.4 M + 42.4 M parameters, 67.8% ImageNet zero-shot.

S1 (`mobileclip_s1.pt`, 340,784,294 bytes, SHA-256 `1270fab6ea23bacbd61cea564bd521a7e875fdb0fcb6d31382bccf4d973b71a6`,
same date and address pattern) was exported only to be measured. S2, the first choice:

- File: `mobileclip_s2.pt` (Apple's original PyTorch checkpoint, not a Hugging Face or open_clip copy).
- Address: https://docs-assets.developer.apple.com/ml-research/datasets/mobileclip/mobileclip_s2.pt
- Retrieved: 2026-10-22. The server reported `Last-Modified: Tue, 27 Feb 2024 10:33:25 GMT`, 398,067,246 bytes.
- SHA-256: `063a87b2a846791bcffafa9f7670ec3968d572a3e7f99e5e4b14348006631d6f`
- The same address is the one given in `get_pretrained_models.sh` and the README of apple/ml-mobileclip at the
  commit below. The README there lists MobileCLIP-S2 as 35.7 M + 63.4 M parameters, 74.4% ImageNet zero-shot.
- The file lives in `export_clip/weights/` on the machine that exported it. It is not in git (`*.pt` is ignored).

## The code and licence

- Repository: https://github.com/apple/ml-mobileclip, commit `341ef058802f0e4e5ab13c02f0cb32a3a94e367b`
  (22 Jul 2024, "License"). Used only to load the checkpoint and export it; none of it is shipped in the app.
- The weights are covered by `LICENSE_weights_data` of that commit (Apple, 2024), copied unchanged to
  `licenses/APPLE_MOBILECLIP_WEIGHTS_LICENSE_2024.txt` (SHA-256 `43ea4923605ea1bbe2e36bcb17d7a7a66f1c8718076df2a7dfe7185f24027ccf`).
- The code licence (`LICENSE`, SHA-256 `be225c17a357def16ede6ecd83cc4e121ff9ea4da2467595a232ab8e2e703509`) and
  `ACKNOWLEDGEMENTS` are copied beside it.
- Apple later replaced the licence on Hugging Face (Feb 2025) and on GitHub (Aug 2025) with a research-only one.
  This project relies on the 2024 text above, which was current when the checkpoint was published, and a lawyer
  confirmed that is acceptable.
- What the 2024 text asks of us: keep Apple's notice with the files when they are redistributed, give no
  endorsement by Apple's name, and keep its disclaimers. The converted ONNX files are a modified redistribution,
  which the text allows ("with or without modifications").

## How the files are made, and what was measured (2026-10-22)

`export_mobileclip.py --variant s0` writes `mobileclip_s0_vision.onnx` (45.6 MB, weights fp32, float32 in and out)
and `mobileclip_s0_text.onnx` (58.7 MB, int8 weights, float32 out): 104.2 MB in all, against 606 MB for the CLIP
ViT-B/32 files. `verify_mobileclip.py` checks them against Apple's PyTorch model.

- Image tower, fp32 against PyTorch fp32 on the 33 sample photos: cosine 1.00000; a batch of six gives the same
  vectors as one at a time. Searching the sample photos with 18 hand-written queries: the right photo first for 15
  (PyTorch 16, old CLIP 14), in the top 3 for 18.
- Text tower: int8 for every layer gave a cosine as low as 0.91 (S2) or 0.88 (S0). Quantizing everything except the
  feed-forward output weights of one transformer layer gives 0.996 or better (mean 0.998) for 3 MB more. The layer
  is `transformer.0` in S1 and S2 and `transformer.1` in S0 (`TEXT_FP32_LAYER` in the export script). Found by
  leaving out one layer at a time and comparing with the fp32 vectors.
- The image tower needed one change to export: Apple's squeeze-and-excite block pools with a kernel taken from the
  input size, which the exporter cannot treat as constant; it is replaced by an average over the whole map (the
  same maths).
- Preprocessing for the app: resize the short side to 256 (bilinear), centre crop 256 x 256, pixels scaled to 0..1,
  no mean/std.
- The app's Dart tokenizer did not match open_clip's (it kept the space before each word as a token of its own, and
  grouped digits); fixed in `lib/tokanizer/clip_tokenizer.dart`. 61 of 62 test texts now give the same 77 tokens.
  The one difference is a combining accent (open_clip normalises it first).

## Why S0, and why fp32 (measured 2026-10-23)

The first build shipped S2 with an fp16 image tower. On a real phone (Vivo I2127) that tower returned NaN for every
photo, although it was exact on a PC: every stored vector was NaN, so every search ranked the same way. The fp32
tower is correct on the phone. NaN vectors are now also refused when an image is embedded and ignored when ranking.

Speed of the image tower on that phone (fp32, batches of four, 256 px, milliseconds per photo; XNNPACK is ONNX
Runtime's CPU kernel set for phones; the old CLIP ViT-B/32 took 280 to 440), and what the models score on Apple's
benchmarks (ImageNet zero-shot / average of 38 datasets; the old model: 63.3 / 52.5):

| | default threads | 2 threads | XNNPACK 8 threads | ImageNet / 38 datasets | download (image + text) |
|---|---|---|---|---|---|
| S0 | 345 | 270 | **258** | 67.8 / 58.1 | 104 MB |
| S1 | 657 | 496 | 486 | 72.6 / 61.3 | 154 MB |
| S2 | 975 | 746 | 648 | 74.4 / 63.7 | 211 MB |

S0 was chosen: as fast as the model it replaces, the smallest download, and clearly more accurate than the old one.
The text tower takes about 60 ms per search for all three. On the 18 test queries the three give the right photo
first 16, 15 and 16 times: too few photos to tell them apart. If S0 turns out not to be accurate enough on real
photos, S1 is the next step (raise `EmbeddingStore.MODEL_ID`, the collections `modelVersion`, and the catalog).
