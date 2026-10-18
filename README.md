# swift-minidisc

A native macOS (SwiftUI) app for putting your existing audio files onto MiniDisc over NetMD.

**Status:** idea / planning. Nothing works yet. See [docs/PLAN.md](docs/PLAN.md).

## What this is (and isn't)

The hard work of talking to MiniDisc hardware has already been done, in the open, by the MiniDisc community: [netmd-js](https://github.com/cybercase/netmd-js), [netmd-exploits](https://github.com/asivery/netmd-exploits), [Web MiniDisc Pro](https://github.com/asivery/webminidisc), [linux-minidisc](https://github.com/glaubitz/linux-minidisc), [atracdenc](https://github.com/dcherednik/atracdenc) and [atrac-encoder](https://github.com/kai-h/atrac-encoder). This project builds on that work. It doesn't replace it.

The only thing this project adds is a **native Mac interface**: drag files from Finder, decode them with Core Audio, encode on-device, and burn them to disc, with no browser and no WebUSB.

If you want the most capable MiniDisc tool today, use [Web MiniDisc Pro](https://web.minidisc.wiki). It's the reference this app follows.

## Goals

- Support the most advanced NetMD modes available: SP, LP2 and LP4 uploads, gapless album transfers, and the Sony Type-R extras unlocked by netmd-exploits.
- Stay small: a focused tool that burns discs well.
- Stay open: all source public, all upstream licences credited clearly.
- Signed and notarised `.dmg` releases.

## Non-goals

- Commercial release, paid tiers, accounts, telemetry.
- Mac App Store distribution (the GPL components rule it out, see [docs/LICENSING.md](docs/LICENSING.md)).
- New reverse engineering or protocol work. Improvements of that kind belong upstream.

## Licensing in one paragraph

Code written for this repository is MIT licensed ([LICENSE](LICENSE)). Third-party components keep their own licences ([ACKNOWLEDGEMENTS.md](ACKNOWLEDGEMENTS.md)). Because the NetMD protocol libraries are GPL-2.0, **the built app as distributed is a GPL-2.0 work**, and its complete corresponding source is this repository at the matching release tag. Details: [docs/LICENSING.md](docs/LICENSING.md).

## A note on authorship

Much of this project's code is written with AI assistance (Claude Code). It's a personal project, built for my own use, for learning and for fun, and shared in case other MiniDisc people on macOS find it useful.
