# Plan

## Users

MiniDisc enthusiasts on macOS (see [r/minidisc](https://www.reddit.com/r/minidisc/)). Mainly the author. The audience is small, so the measure of success is "I use it to make discs", not downloads.

## Principles

1. **Native interface is the value-add.** The protocol and codec work comes from upstream. If we need a protocol fix, we send it upstream.
2. **Credit loudly.** The About window, README and release notes name the upstream projects and their licences.
3. **No feature creep.** Every feature has to help get audio onto a disc. When in doubt, leave it out and point people to Web MiniDisc Pro.
4. **Open from day one.** Public repo, public issues, no closed parts.

Counter-example to avoid: a recent closed-source "native macOS NetMD app" announced on r/minidisc had obvious feature bloat, likely contained GPL code it didn't disclose, and was aimed at a commercial release. The community reaction was hostile. We do the opposite on every point.

## Scope

### v0.1: usable for real discs

- Detect a connected NetMD device. Show model and disc state.
- Show disc contents: disc title, tracks, groups, durations, encoding mode, time remaining.
- Edit titles (disc, tracks, groups), reorder, delete, group/ungroup.
- Add files by drag and drop from Finder: anything Core Audio can decode (WAV, AIFF, ALAC, AAC, MP3, FLAC). Pre-fill titles from file metadata.
- Upload modes:
  - **SP**: send PCM, and the device encodes it (standard NetMD).
  - **LP2 / LP4**: encode ATRAC3 locally with `libatrac3` (kai-h/atrac-encoder), then send it.
- Show a capacity estimate before burning, transfer progress, and allow cancel.

### v0.2: advanced NetMD modes

- **Gapless album upload** in LP2/LP4, using the atrac-encoder streaming API (one continuous encode, split at track marks).
- **Sony Type-R extras via netmd-exploits**, gated per device and clearly marked experimental:
  - True ATRAC1 SP upload (encoded locally with atracdenc instead of the deck's realtime encoder).
  - Track download/ripping from disc.
  - Whatever else netmd-exploits supports and Web MiniDisc Pro exposes, matching its safety warnings.

### Later, maybe

- Hi-MD (himd-js), only if NetMD is solid.

### Out of scope

CD ripping, metadata lookups, streaming services, playlists or library management, accounts, cloud features, plugins.

## Architecture

```
SwiftUI views
    │
DiscStore (@Observable, Swift)  ── AVFoundation: decode files → 44.1 kHz 16-bit PCM
    │                                 │
NetMDService (Swift)               Encoder (Swift wrapper)
    │                                 ├─ libatrac3 (C, MIT): LP2 / LP4
JavaScriptCore runtime              └─ atracdenc (C++, LGPL-2.1): ATRAC1 SP, v0.2
    ├─ netmd-js       (bundled, GPL-2.0)
    ├─ netmd-exploits (bundled, GPL-2.0)
    └─ WebUSB shim  ──►  Swift USB layer (IOUSBHost / IOKit)
```

### Why host netmd-js rather than port it

The NetMD logic (secure session, encryption, the per-device exploit catalogue) is subtle, and the code is still actively maintained. Here are the options:

- **Recommended: run the upstream JS in JavaScriptCore**, behind a small WebUSB-shaped shim (`controlTransferIn/Out`, `transferIn/Out`, `claimInterface`, …) implemented in Swift. Upstream updates come in by bumping a pinned version. We don't fork or re-implement anything, and every protocol line stays upstream's.
- Port netmd-js to Swift. This is a derivative work (still GPL), it's a lot of effort, and it drifts from upstream. It's exactly the "further technical work" we said we wouldn't do.
- Wrap linux-minidisc's C `libnetmd`. It's less maintained and doesn't cover the exploits.

WKWebView isn't an option: WebKit doesn't implement WebUSB.

### Audio pipeline

Decode with AVFoundation (`AVAudioFile` / `AVAudioConverter`) to 44.1 kHz stereo Int16. SP sends that PCM as is. LP2/LP4 send it through `libatrac3`'s streaming encoder. There's no ffmpeg dependency.

### Packaging

- Xcode project for the app. SwiftPM packages for `NetMDKit` (JSC host + USB) and `ATRACKit` (C encoders).
- Upstream code is pinned as git submodules under `ThirdParty/`. The JS is bundled with esbuild at build time, and the bundle and its `LICENSE` ship in the app's resources.
- `libatrac3` has to be built with `-ffp-contract=off` (its output is byte-exact only without FMA contraction). Set this per target, and add a test against its golden vectors.

## Distribution

- Developer ID signed, hardened runtime, notarised, stapled `.dmg`, built by GitHub Actions on tagged releases.
- Entitlements: USB device access. JIT probably isn't needed (USB speed is the bottleneck), so check whether JSC runs acceptably without `allow-jit`.
- Each release states: "This binary is GPL-2.0. Source: <tag>." Third-party licence texts ship inside the app.
- No Mac App Store build (see [LICENSING.md](LICENSING.md)).

## Milestones

0. **Spikes** (decide go/no-go):
   - Run netmd-js in JSContext with the Swift WebUSB shim, list tracks on a real deck.
   - Build `libatrac3` in SwiftPM, encode a WAV, check the output matches the golden vectors.
   - Upload one LP2 track end to end.
1. Read-only disc browser.
2. Title editing and track management.
3. Upload SP/LP2/LP4 → **v0.1**.
4. Gapless, exploits, ATRAC1 SP → **v0.2**.
5. Signing/notarisation pipeline (can run in parallel from milestone 1).

## Open questions

- netmd-js / netmd-exploits declare `GPL-2.0` without `-only` / `-or-later`. Check the file headers, or ask the authors, which version terms apply.
- Ask the netmd-js / Web MiniDisc maintainers early whether they're happy with this project. Being a good neighbour matters more than shipping.
- atrac-encoder is very new (a handful of stars, Oct 2026) and was reconstructed by analysing Sony's `at3tool`. Read its provenance notes and keep atracdenc (LGPL) as a fallback LP2 encoder.
- Which test hardware is available? (Sony Type-R decks/portables are the target for the exploit features.)
- Minimum macOS version: probably 14 (for `@Observable`).
