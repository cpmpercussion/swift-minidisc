# Spike B: netmd-js in JavaScriptCore

Runs the upstream [netmd-js](https://github.com/cybercase/netmd-js) 4.4.1 and [netmd-exploits](https://github.com/asivery/netmd-exploits) 0.5.12 unmodified inside a `JSContext`. A WebUSB-shaped `navigator.usb` is backed by Swift and IOUSBHost.

Licence: this spike bundles GPL-2.0 code, so the built product is GPL-2.0. The Swift and JS glue written here is MIT, like the rest of the repo.

```sh
./run.sh               # npm install + bundle, swift build -c release, sign, run
./run.sh --list-usb    # also list every USB device the Swift backend can see
./run.sh --fake-device # pretend a (non-existent) MZ-N707 is attached, to test error paths
```

## Result (2026-10-18, macOS 26, Xcode 27.1, no deck attached)

```
Runtime loaded in 104 ms
netmd-js: 47 known device IDs; netmd-exploits: 27 exports
DES (wasm) known-answer test: ok
Keystone assembler (wasm): loaded ok
Encrypted 4.0 MB for upload in 1041 ms
No NetMD device found.
```

- **Works:**
  - The bundle loads and evaluates in a plain `JSContext`.
  - Both WebAssembly dependencies run: crypto-js-wasm DES/3DES (netmd-js secure session and upload encryption) and keystone (netmd-exploits ARM assembler).
  - `openNewDevice(navigator.usb)` goes through the shim to `USBBackend.enumerate()` (IOKit). With nothing attached it returns `null`, which we report as "No NetMD device found".
  - `--fake-device` shows a Swift `USBError` reaching netmd-js as a rejected Promise (`NetworkError: USB device 1 is no longer attached`), so errors don't hang anything.
- **Not tested:** any real USB I/O. No deck or other USB device was attached; `system_profiler SPUSBDataType` is empty.

## Findings

### 1. JavaScriptCore needs `com.apple.security.cs.allow-jit`

Without the entitlement, JSC in a third-party process runs interpreter-only. This happens even when the binary isn't hardened. It's slow:

| Build | JS loop 1e8 | Encrypt 4 MB for upload |
|---|---|---|
| Node 26 (V8) | 160 ms | 1.1 s |
| JSC, no entitlement (with or without hardened runtime) | 3.2 s | **31 s** |
| JSC, hardened runtime + `allow-jit` | 0.25 s | **1.0 s** |

A 4 MB buffer is about one 4-minute LP2 track. That makes `allow-jit` effectively required. It's a standard hardened-runtime entitlement and is allowed for Developer ID notarised apps, so this isn't a distribution blocker. See `NetMDJSC.entitlements`.

### 2. Spin the main CFRunLoop, not `dispatchMain()`

JSC completes async work like `WebAssembly.instantiate` through the run loop of the thread that owns the context. Under `dispatchMain()` the first `loadWasm()` never resolves. In a SwiftUI app the main run loop is already spinning, so this only matters for CLI and test harnesses.

### 3. WebUSB surface netmd-js uses

Everything is in `netmd.ts` and `netmd-commands.ts`:

- `navigator.usb.getDevices()`, `requestDevice({ filters })`
- `USBDevice`: `vendorId`, `productId`, `manufacturerName`, `productName`, `opened`
- `open()`, `close()`, `reset()`, `selectConfiguration(1)`, `claimInterface(0)`, `releaseInterface(0)`
- `controlTransferIn` / `controlTransferOut` with `requestType: 'vendor'`, `recipient: 'interface'`. Requests are 0x01 (reply length), 0x80/0x81 (command/reply) and 0xff (factory).
- `transferIn(1, n)` (bulk IN 0x81, track download) and `transferOut(2, data)` (bulk OUT 0x02, upload)

netmd-exploits doesn't touch USB directly; it goes through netmd-js's factory commands.

There's no chooser in a native app, so in the shim every attached device that matches a filter counts as paired. `requestDevice` picks the first match.

### 4. Polyfills

- **Swift:** `setTimeout`/`clearTimeout` (`DispatchQueue.main`), `crypto.getRandomValues` (`arc4random_buf` straight into the typed array), `console.*`, and the `__usbHost` bridge.
- **JS** (`js/shims/prelude.js`, injected by esbuild): `atob`/`btoa` (crypto-js-wasm unpacks its wasm with `atob`), `TextEncoder`/`TextDecoder` (UTF-8 only), `queueMicrotask`, `self`/`window` aliases.
- **Module aliases:**
  - `util` → `inspect` shim (debug logging only)
  - `fs`/`path` → stubs
  - `browser-or-node` → `isBrowser: true`, so netmd-exploits takes `Assembler.setWASMArrayBuffer`, which the host calls with the bundled `assembler.wasm`

Byte buffers cross the bridge through the JSC C typed-array API (`JSObjectMakeTypedArray` / `JSObjectGetTypedArrayBytesPtr`), not one element at a time. The shim copies every outgoing `BufferSource` into a fresh zero-offset `Uint8Array` so Swift can read it directly.

### 5. Threading

All JS runs on the main thread. Each USB operation runs synchronously on a serial `usbQueue` and settles its Promise back on main, so the UI stays responsive. netmd-js already serialises its own calls.

## Files

| Path | What |
|---|---|
| `package.json`, `js/build.mjs` | Pin netmd-js 4.4.1 / netmd-exploits 0.5.12 from npm; esbuild them to one IIFE |
| `js/entry.js` | Exposes `globalThis.NetMDBundle = { netmd, exploits, Crypto }` |
| `js/shims/*` | Prelude polyfills and module aliases |
| `Sources/NetMDJSC/Resources/webusb-shim.js` | `navigator.usb` / `USBDevice` over `__usbHost` |
| `Sources/NetMDJSC/NetMDRuntime.swift` | JSContext host: polyfills, `__usbHost`, typed-array bridging |
| `Sources/NetMDJSC/USBBackend.swift` | IOUSBHost enumeration, open, configure, claim, control and bulk transfers |
| `Sources/netmd-jsc-spike/main.swift` | Self-tests and the list-disc scenario |
| `NetMDJSC.entitlements`, `run.sh` | Hardened runtime + `allow-jit` signing |

The bundle comes from the npm packages pinned at the same versions as the `ThirdParty/` submodules. The submodules aren't modified.

## Risks and what to test with a deck attached

1. **Device ownership.** This is the main unknown. If macOS's composite driver already owns the `IOUSBHostDevice`, opening it ourselves may fail. The handle tolerates that: all NetMD control traffic is interface-recipient and goes through the claimed `IOUSBHostInterface`. `reset()` and any `selectConfiguration` that isn't a no-op do need the device object, though. If claiming the interface also fails, the fallbacks are `IOUSBHostObjectInitOptions.deviceCapture` (needs root or an entitlement) or the older `IOUSBDeviceInterface` plug-in API, which is what Chrome's WebUSB uses on macOS.
2. Run `./run.sh` with a deck attached and check that it lists the disc. Then rename a track, upload one SP track, and with the atrac-encoder spike, upload an LP2 track.
3. Bulk transfer chunking: netmd-js reads in 64 KiB chunks and the timeout is 5 s. Check that long uploads don't time out, and adjust `USBDeviceHandle.timeout` for bulk if they do.
4. `finalize()` calls `reset()` first. Check that a reset doesn't re-enumerate the device under a new registry ID while we hold the handle.
5. Exploit-based features (factory mode, ATRAC1 SP upload, ripping) on a Type-R device. They load fine here, but none of their code paths have run.
6. Licensing: `assembler.wasm` is keystone-engine, also GPL-2.0. Add it to ACKNOWLEDGEMENTS.
7. Sandboxing: the plan is Developer ID without the App Sandbox. If we sandbox later, add `com.apple.security.device.usb`.

## Hardware results (MZ-N910, firmware S1.400, 2026-10-18)

- Open, list disc, read device code: works. The Swift backend claims the NetMD interface with no driver conflict.
- **LP2 upload works end to end**: file → Core Audio → ATRACKit (libatrac3) → raw ATRAC3 frames (no `.at3` header) → netmd-js `MDTrack`/`download`. The track lists as LP2 with the expected length, and it's still there in a fresh session. Erasing works (`--erase-track N --expect-title T` refuses to erase if the title doesn't match).
- **Don't call `netMd.finalize()`.** Its USB `reset()` makes the unit discard TOC changes it hasn't written to disc yet: the first upload vanished on the next connection. Web MiniDisc never calls it either. Release the interface and close.
- **Upload time is fixed per-track latency on the device.** With `NETMD_TRACE=1`, the 66 KB of bulk data for a 4 s track went out in 0.36 s (about 1 ms per 1 KB packet), and packet encryption costs about 0.25 ms per KB. After that, the unit takes ~20–30 s to acknowledge the track and ~10–20 s to acknowledge the commit. Capping netmd-js's doubling reply poll at 100 ms (`--poll-cap-ms 100`) didn't help: 52 s versus 35–46 s with the default. So keep the upstream polling and design the UI around ~40 s per track on this unit. Still to measure: a full-length track, gapless album upload, and the other two portables.
