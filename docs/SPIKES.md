# Spikes

## A. libatrac3 in SwiftPM: done, passed

- `CATRAC3` compiles kai-h/atrac-encoder's `src/*.c` unmodified from the submodule, through one-line shim files. No `unsafeFlags` needed: upstream's `internal.h` sets `#pragma STDC FP_CONTRACT OFF` for clang.
- `ATRACKit` wraps it: a streaming `ATRAC3Encoder` (LP2/LP4, gapless across `write` calls), whole-file `ATRAC3File.encode/decode`, and `AudioFileDecoder` (AVFoundation → 44.1 kHz stereo Int16, resampling as needed).
- `atrac3-swift` is an at3tool-compatible CLI. Upstream's own test harness passes against it:
  `python3 ThirdParty/atrac-encoder/tests/run_tests.py --bin .build/release/atrac3-swift` → **124/124 outputs match**, RIFF checks ok. So our build is byte-identical to Sony's at3tool.
- `swift test`: the streaming encoder fed in awkward block sizes is byte-identical to the whole-file encode (LP2 and LP4), and an AAC 48 kHz file decodes and encodes.
- Speed (release build, Apple silicon): a 5-minute AAC file to LP2 in about 2 s, to LP4 in about 1.2 s, including decoding. That's roughly 150–250× realtime.

Still open: NetMD upload wants raw frames plus netmd-js's own wire format. Check which ATRAC3 framing netmd-js expects for LP2/LP4 (`.at3` header stripped?) once spike B is in.

## B. netmd-js in JavaScriptCore

See `Spikes/NetMDJSC/README.md`.

## C. End-to-end LP2 upload

Needs a NetMD deck connected.
