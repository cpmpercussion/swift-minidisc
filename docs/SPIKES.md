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

**Passed, up to device discovery.** No deck was connected, so no USB traffic has run yet. Details are in `Spikes/NetMDJSC/README.md`. Run it with `Spikes/NetMDJSC/run.sh`.

- netmd-js 4.4.1 and netmd-exploits 0.5.12, unmodified, are bundled by esbuild and load in a plain JSContext in about 150 ms. Both WebAssembly modules work: the DES known-answer test passes and Keystone loads.
- netmd-js's device discovery goes through a small WebUSB shim to a Swift USB backend and reports "No NetMD device found" cleanly.
- `allow-jit` is required: encrypting 4 MB takes 1.0 s with it and 31 s without.
- WebAssembly loading finishes through the main run loop, so a command-line host must call `RunLoop.main.run()`. A SwiftUI app already runs it.
- Main risk: whether we can claim the NetMD interface while macOS holds the device. Check this first on hardware.

## C. End-to-end LP2 upload

Needs a NetMD deck connected.
