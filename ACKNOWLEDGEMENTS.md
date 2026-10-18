# Acknowledgements

swift-minidisc is a native interface on top of other people's work. Thank you to:

| Project | Authors | Licence | Used for |
|---|---|---|---|
| [netmd-js](https://github.com/cybercase/netmd-js) | cybercase and contributors | GPL-2.0 | NetMD protocol |
| [netmd-exploits](https://github.com/asivery/netmd-exploits) | asivery and contributors | GPL-2.0 | Advanced features on Sony Type-R, Type-S and Hi-MD units |
| [Web MiniDisc Pro](https://github.com/asivery/webminidisc) | asivery, cybercase and contributors | GPL-2.0 | Reference interface and behaviour |
| [atrac-encoder](https://github.com/kai-h/atrac-encoder) | kai-h | MIT | ATRAC3 LP2/LP4 encoding |
| [Keystone](https://github.com/keystone-engine/keystone) (WebAssembly build shipped in netmd-exploits) | Keystone Engine contributors | GPL-2.0 | Assembling netmd-exploits' ARM payloads |
| [linux-minidisc](https://github.com/glaubitz/linux-minidisc) | linux-minidisc contributors | GPL-2.0 | Protocol groundwork the above builds on |

Not currently shipped, but part of the same ecosystem:

- [atracdenc](https://github.com/dcherednik/atracdenc) (dcherednik and contributors, LGPL-2.1): the open ATRAC1/ATRAC3/ATRAC3+ encoder Web MiniDisc Pro uses. It's the only open ATRAC1 encoder, so it's the candidate if we add true ATRAC1 SP upload on Type-S units (see docs/PLAN.md).

Full licence texts will live in `ThirdParty/<project>/LICENSE` and ship inside the app bundle.

If you contributed to one of these projects and should be named here, please open an issue.
