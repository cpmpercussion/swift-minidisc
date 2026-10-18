# swift-minidisc

A native macOS (SwiftUI) app for putting your existing audio files onto MiniDisc over NetMD.

**Status:** early. A first SwiftUI app lists a disc, renames, erases and burns dropped files as SP, or as gapless LP2/LP4, tested on an MZ-N910. See [docs/PLAN.md](docs/PLAN.md), [docs/SPIKES.md](docs/SPIKES.md), and [docs/FIELD-NOTES.md](docs/FIELD-NOTES.md) for what we've learned about running this stack natively and how the hardware behaves in practice.

## What this is (and isn't)

The hard work of talking to MiniDisc hardware has already been done, in the open, by the MiniDisc community: [netmd-js](https://github.com/cybercase/netmd-js), [netmd-exploits](https://github.com/asivery/netmd-exploits), [Web MiniDisc Pro](https://github.com/asivery/webminidisc), [linux-minidisc](https://github.com/glaubitz/linux-minidisc) and [atrac-encoder](https://github.com/kai-h/atrac-encoder). This project builds on that work. It doesn't replace it.

The only thing this project adds is a **native Mac interface**: drag files from Finder, decode them with Core Audio, encode on-device, and burn them to disc, with no browser and no WebUSB.

## Why now

Until recently, good LP2/LP4 encoding meant running Sony's own `at3tool`, usually in a Docker container or on a remote server. The open-source alternative, [atracdenc](https://github.com/dcherednik/atracdenc), is noticeably worse for ATRAC3, though it remains the only open ATRAC1 (SP) encoder. [atrac-encoder](https://github.com/kai-h/atrac-encoder) (MIT, 2026) changes that: it's an open C encoder whose output is byte-identical to Sony's. With it, a self-contained Mac app can burn reference-quality LP2/LP4 with nothing else installed.

If you want the most capable MiniDisc tool today, use [Web MiniDisc Pro](https://web.minidisc.wiki). It's the reference this app follows.

## Goals

- Support the most advanced NetMD modes available: SP, LP2 and LP4 uploads, gapless album transfers, and the extras netmd-exploits unlocks on Sony Type-R, Type-S and Hi-MD units.
- Stay small: a focused tool that burns discs well.
- Stay open: all source public, all upstream licences credited clearly.
- Signed and notarised `.dmg` releases.

## Non-goals

- Commercial release, paid tiers, accounts, telemetry.
- Mac App Store distribution (the GPL components rule it out, see [docs/LICENSING.md](docs/LICENSING.md)).
- New reverse engineering or protocol work. Improvements of that kind belong upstream.

## Building

Needs Xcode, [XcodeGen](https://github.com/yonaskolb/XcodeGen) and Node (for bundling netmd-js). After cloning:

```sh
git submodule update --init
make run      # bundle JS, generate MiniDisc.xcodeproj, build and open the app
make test     # Swift tests + upstream's byte-exact encoder tests
```

`make cli ARGS=...` runs the command-line hardware test tool ([docs/NETMD-JSC.md](docs/NETMD-JSC.md)).

## Licensing in one paragraph

Code written for this repository is MIT licensed ([LICENSE](LICENSE)). Third-party components keep their own licences ([ACKNOWLEDGEMENTS.md](ACKNOWLEDGEMENTS.md)). Because the NetMD protocol libraries are GPL-2.0, **the built app as distributed is a GPL-2.0 work**, and its complete corresponding source is this repository at the matching release tag. Details: [docs/LICENSING.md](docs/LICENSING.md).

## A note on authorship

Much of this project's code is written with AI assistance (Claude Code). It's a personal project, built for my own use, for learning and for fun, and shared in case other MiniDisc people on macOS find it useful.
