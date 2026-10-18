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

**Passed on real hardware (MZ-N910, firmware `S1.400`).** The Swift backend claims the NetMD interface with no driver conflicts, opens the device, lists the disc (title, 8 SP tracks, durations, free space) and reads the device code through netmd-js's factory interface. The Type-S code `S1.400` means every netmd-exploits feature is available on this unit, including ATRAC1 upload, SP faster upload and track download.

One fix was needed: jconv, which netmd-js uses for Shift-JIS titles, expects Node's global `Buffer`. Web MiniDisc gets it from webpack 4's polyfills. The bundle now injects the `buffer` package (MIT). Details are in `docs/NETMD-JSC.md`. Run it with `make cli`.

- netmd-js 4.4.1 and netmd-exploits 0.5.12, unmodified, are bundled by esbuild and load in a plain JSContext in about 150 ms. Both WebAssembly modules work: the DES known-answer test passes and Keystone loads.
- netmd-js's device discovery goes through a small WebUSB shim to a Swift USB backend and reports "No NetMD device found" cleanly.
- `allow-jit` is required: encrypting 4 MB takes 1.0 s with it and 31 s without.
- WebAssembly loading finishes through the main run loop, so a command-line host must call `RunLoop.main.run()`. A SwiftUI app already runs it.
- Claiming the NetMD interface while macOS holds the device works: no capture mode or root needed.

## C. End-to-end LP2 upload: done, passed

On the MZ-N910: a 15 s file was decoded with Core Audio, encoded to LP2 with ATRACKit, uploaded through netmd-js, listed as LP2 with the right length, persisted across sessions, and was then erased. Details are in `docs/NETMD-JSC.md`. Two findings shape the app:

- Never send netmd-js's `finalize()` USB reset. It throws away TOC changes the unit hasn't written yet.
- Each track costs ~35–45 s of device-side latency on this portable, however short it is. The data transfer itself takes well under a second. Progress UI should show "waiting for device", not a stuck bar.

Not yet done: listening to an uploaded track on the portable and on the JE440/PC3 after the unit writes its TOC to disc (unplug or stop).
