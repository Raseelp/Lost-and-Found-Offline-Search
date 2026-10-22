# Where the MobileCLIP-S2 weights came from

Recorded 2026-10-22, before the search model was switched from OpenAI CLIP ViT-B/32 to Apple MobileCLIP-S2.

## The weights

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

`export_mobileclip_s2.py` writes `mobileclip_s2_vision.onnx` (71.8 MB, weights fp16, float32 in and out) and
`mobileclip_s2_text.onnx` (67.5 MB, int8 weights, float32 out): 139.3 MB in all, against 606 MB for the CLIP
ViT-B/32 files. `verify_mobileclip_s2.py` checks them against Apple's PyTorch model.

- Image tower, fp16 against PyTorch fp32 on the 33 sample photos: cosine 0.9999 or better; a batch of six gives
  the same vectors as one at a time.
- Text tower: int8 for every layer gave a cosine as low as 0.91 (mean 0.976). Quantizing everything except the
  feed-forward output weights of the first transformer layer gives 0.996 or better (mean 0.998) for 3.4 MB more.
  Keeping the whole text tower in fp16 would be exact but 127 MB.
- The image tower needed one change to export: Apple's squeeze-and-excite block pools with a kernel taken from the
  input size, which the exporter cannot treat as constant; it is replaced by an average over the whole map (the
  same maths).
- Preprocessing for the app: resize the short side to 256 (bilinear), centre crop 256 x 256, pixels scaled to 0..1,
  no mean/std.
- The app's Dart tokenizer did not match open_clip's (it kept the space before each word as a token of its own, and
  grouped digits); fixed in `lib/tokanizer/clip_tokenizer.dart`. 61 of 62 test texts now give the same 77 tokens.
  The one difference is a combining accent (open_clip normalises it first).
