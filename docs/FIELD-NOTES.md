# Field notes

These notes record what we learned by running the MiniDisc community's software and hardware in a setting they weren't built for: netmd-js inside JavaScriptCore, driven from Swift, on macOS. Each entry covers what happened, why it happened (or our best guess), and what it means for the app.

netmd-js, netmd-exploits and Web MiniDisc were written for their authors' own purposes, mostly the browser and Node. None of the issues below are bugs in them. They're the kind of knowledge you only get by doing, and the notes are kept so the next person (or agent) porting this stack doesn't have to rediscover it. Where something is a hypothesis rather than an observation, it's marked as one.

Hardware so far: MZ-N910 (firmware `S1.400`, Type-S). Playback checks on an MDS-JE440.

---

## Device behaviour

### Recording a track is two phases on the unit, and the TOC is a third

*Observed 2026-10-18, MZ-N910.*

1. **Data streams in.** The REC light blinks while bulk data arrives. This part is fast: 66 KB in 0.36 s, and a 10 MB LP2 track in a few seconds.
2. **"Saving data" with a countdown, after each track.** The unit finishes writing that track's audio to disc. netmd-js is waiting for the reply to its send-track command at this point. On the host, it shows up as a long run of empty reply-length polls: 20–30 s after a short track sent in its own session.
3. **"TOC EDIT", later and separately.** The unit keeps the disc's table of contents (UTOC) changes in RAM and only writes them to the disc when you press stop, eject, or the unit otherwise ends the session. Until then, the new tracks exist only in RAM.

Reviews of earlier NetMD portables describe "DATA SAVE/TOC EDIT" as one step after every track: 2–15 s of DATA SAVE plus about 6 s of TOC EDIT on the MZ-N1, and about 8 s per typical track on the MZ-N10 ([minidisc.org MZ-N1 review](https://www.minidisc.org/brian_youn/mzn1/page3.html), [MZ-N10 review](https://www.minidisc.org/brian_youn/mzn10/page7.shtml)). The N10 reviewer wished Sony would do a single TOC edit after all the tracks. On the N910, which is a later Type-S unit, that's what we saw: one TOC EDIT, on stop, after a 4-track upload. *Hypothesis:* later firmware defers the UTOC write until the session ends. Check this on the N505 and NH700.

**For the app:**
- Show "Saving on device…" as its own progress phase, not as a stalled transfer bar.
- Tell the user to press stop or eject, or explain that unplugging writes the TOC, before they consider the disc finished.
- Never do anything that discards the cached TOC (see the next entry).

### A USB reset throws away the unwritten TOC

*Observed.* netmd-js's `NetMD.finalize()` calls `device.reset()` before closing. Our first test upload listed fine, then vanished on the next connection, and the disc's free space went back to what it was before. With the reset removed (release the interface, close), uploads persist. Web MiniDisc never calls `finalize()`.

*Why (inferred):* the port reset re-enumerates the unit before it writes the cached UTOC (see above). The audio blocks may be physically on the disc, but nothing references them.

**For the app:** never reset the device at the end of a session. netmd-exploits' "Force TOC Flushing" exists for the opposite case, when you want the TOC written now.

### Per-track latency is on the device, and one session for all tracks is much faster

*Observed.* Each single-track upload in its own session took 35–46 s whatever its length: 4 s and 15 s tracks took about the same. A 4-track, 42-minute album in **one** `MDSession` took 124 s in total, about 24 s per 10 MB track (about 20× realtime).

Capping netmd-js's reply poll interval at 100 ms didn't speed things up (52 s against 35–46 s). netmd-js polls at 10 ms × 2ⁱ with no cap, so a single wait can overshoot by as much as the wait itself took. That looked like the cause, but polling more often was, if anything, slower. Keep the upstream behaviour.

**For the app:** always batch uploads into one session (prepare → init → N × `downloadTrack` → close → release), as Web MiniDisc does.

### LP2/LP4 uploads take raw ATRAC3 frames

netmd-js's `MDTrack` takes the ATRAC3 frames with no container. `.at3`/RIFF and OMA headers have to be stripped. netmd-js's README says this, but it's easy to miss. netmd-js's `FrameSize` for LP2 is 192 bytes, while an LP2 stereo frame is 384 bytes; it pads the data to a multiple of 192, so whole 384-byte frames are fine. ATRACKit's streaming encoder outputs raw frames directly.

### An empty unit rejects TOC reads

*Observed.* With no disc in the N910, `listContent` fails with `Rejected - 0a1806 02201801…`. That's the disc-title read (descriptor `1801`), the first query it makes. Check `getDeviceStatus(...).discPresent` first and show "insert a disc" instead of an error.

### Shift-JIS titles: half-width and full-width

Japanese-market discs carry both a half-width title (ASCII and half-width katakana, e.g. `ﾀｲﾑ ﾘﾐｯﾄ`) and a full-width title (`タイム・リミット`). `listContent` returns both (`title`, `fullWidthTitle`). The app should show the full-width title when there is one.

---

## Running netmd-js in JavaScriptCore

### macOS lets us claim the NetMD interface

*Observed.* We feared the system composite driver would own the device. In practice, `IOUSBHostInterface` on the vendor interface works without root, capture mode or entitlements (outside the sandbox). NetMD traffic is all interface-level vendor requests plus two bulk endpoints (0x81 in, 0x02 out).

### JavaScriptCore needs `allow-jit`

Without `com.apple.security.cs.allow-jit`, an in-process `JSContext` is interpreter-only. netmd-js's WebAssembly DES then encrypts 4 MB in 31 s instead of 1 s. Notarised Developer ID apps may use this entitlement.

### WebAssembly loading finishes through the main run loop

A command-line host must call `RunLoop.main.run()`; with `dispatchMain()` it hangs. A SwiftUI app already runs this loop.

### `Buffer`: missing, then duplicated

1. **Missing.** netmd-js decodes titles with jconv, which uses Node's global `Buffer`. Web MiniDisc gets it from webpack 4's automatic polyfills. JavaScriptCore has none, so listing a disc failed in `ensureBuffer`. Fix: esbuild injects the `buffer` package.
2. **Duplicated.** We installed `buffer@6` for that fix, but netmd-js depends on its own `buffer@5`. With two `Buffer` classes, jconv's `buf instanceof Buffer` check failed. jconv then fell back to `new Buffer(buf.toString(), 'UTF8')`, which decodes the Shift-JIS bytes as UTF-8 and mangles every double-byte character. Encoding still worked, so titles we *wrote* would have been correct, but every Japanese title we *read* was garbled.

   **Signature, worth knowing:** each Japanese character shows up as `・ｽ` followed by a stray ASCII letter (`・ｽv・ｽ・ｽ…`). The lead byte becomes U+FFFD; its UTF-8 bytes `EF BF BD` read back as Shift-JIS give `・ｽ`; the trail byte survives as ASCII. We first assumed this was a badly written second-hand disc. It wasn't. With one shared `buffer@5.7.1`, the same disc reads `Ｗａｉｔ　＆　Ｓｅｅ～リスク～`.

   **For the app:** keep the bundle's `buffer` version equal to netmd-js's so npm dedupes them, and keep a Shift-JIS round-trip self-test in the runtime.

---

## SwiftUI

### Hosted views may not see `@Environment` objects

*Observed.* The app crashed with an `EnvironmentValues.subscript` assertion when an accessibility query (`entire contents` of the window via System Events) forced layout of a toolbar item that read `@Environment(DiscStore.self)`. Toolbar content is hosted outside the window's view tree. Fixing only the toolbar wasn't enough: the same query crashed it again in another view (table cells are hosted too). The app now passes the store to every view explicitly and doesn't use `@Environment` for it.

### A busy main thread throttles the upload

*Observed 2026-10-18, MZ-N910, first app burn.* Two LP2 tracks (about 40 minutes of audio) went over slower than real time. The same netmd-js code had sent a 42-minute LP2 album in 124 s from `netmd-cli`. The app sat at about 90–95% CPU. Two 3-second `sample`s showed the main thread re-laying-out the window over and over: `NSWindow layoutIfNeeded` → SwiftUI root geometry → sizing the queue's segmented `Picker` (`SystemSegmentedControl`) through a nested hosting graph, with much of the time in `ObservationTracking.cancel`. Only 6–11 of about 2,200 samples were USB promise callbacks. Hiding the app didn't help (still about 90%).

*Why:* all JavaScript runs on the main thread (`NetMDRuntime`), and every USB completion and `setTimeout` settles there. Each step of the transfer waits behind a layout pass. *Hypothesis:* the indeterminate spinner in the toolbar drives the per-frame window layout; the segmented picker makes each pass expensive.

**For the app:** don't animate anything during a transfer that forces window layout, and keep the transfer off the UI's thread. The sturdy fix is running the JSContext on its own thread, so nothing the UI does can stall the device.

*Fixed.* `NetMDClient` now runs the JSContext on its own thread with its own run loop, and the toolbar shows static labels instead of spinners. Idle CPU went from about 90% to 0%. Side A (about 20 minutes, 24-bit) burned as LP2 in about 1:50 from clicking Burn: about 40 s encoding (Debug build), about 35 s sending, about 30 s saving on the unit.

### Quitting mid-transfer leaves the unit stuck in PC→MD

*Observed, MZ-N910.* After the app was quit during a slow transfer, the REC light kept blinking and the unit ignored stop and eject. Unplugging USB ended it: "PC→MD" for a moment, then "TOC EDIT" for a while. The disc kept its original 13 tracks plus the first uploaded track (Side B, complete), which had finished saving before the quit; the track being sent was lost. Afterwards the unit didn't enumerate on USB until it had been power-cycled and replugged.

**For the app:** a Cancel that ends the session properly, and a warning before quitting during a transfer. Tell the user that unplugging is the way out if the app goes away mid-transfer.

### Bulk writes must not time out

*Observed.* The next burn, onto the same disc straight after that recovery, failed on its first bulk write: `endpoint 0x02: status 0xe00002d6 (timeout): 128 bytes transferred` after our 5 s IOUSBHost timeout. Nothing was written; the disc was unchanged. WebUSB has no transfer timeout, so netmd-js never expects one. *Hypothesis:* the unit was still busy after the aborted session and held off the data for more than 5 s.

**For the app:** bulk OUT transfers now have no timeout (`USBDeviceHandle.bulkOutTimeout = 0`). Unplugging still ends a hung transfer.

## Audio pipeline

### iCloud Drive files may be placeholders

The test album in `~/Documents` was "dataless" (iCloud placeholders, about 490 MB). The first read blocked for minutes while it downloaded. **For the app:** detect placeholders, trigger and show the download (`NSFileCoordinator`, ubiquitous item status) before encoding, rather than appearing to hang.

### Dither only when reducing bit depth

Sources are often 24-bit (the test album was 24-bit ALAC). `AVAudioConverter.dither` should be on for >16-bit or float sources and off for 16-bit sources, which must pass through bit-exact. A test caught dither being applied to 16-bit WAV input.

### Gapless: one encoder, marks slightly early

Encoding an album through one streaming encoder makes the joins seamless (confirmed by listening on an MDS-JE440). Track marks land 50–73 ms early because of the encoder's look-ahead (documented by atrac-encoder).

---

## Encoder provenance checks

- Upstream's own byte-exact test harness (`ThirdParty/atrac-encoder/tests/run_tests.py --bin`) runs against our SwiftPM build through an at3tool-compatible CLI: 124/124 match. Run it whenever the submodule is bumped.
- Next: byte-compare against Sony's at3tool (Charles's Docker image) on real music, not just synthetic vectors.
