# Licensing

This isn't legal advice. It's our working position, written down so it can be checked and corrected.

## Layers

| Layer | Licence |
|---|---|
| Source written for this repo | MIT ([LICENSE](../LICENSE)) |
| netmd-js, netmd-exploits (bundled JS), Keystone (`assembler.wasm`) | GPL-2.0 |
| libatrac3 from kai-h/atrac-encoder (LP2/LP4 encoder) | MIT |
| The distributed app (`.app` / `.dmg`) as a whole | **GPL-2.0** |

## Why the app is GPL-2.0 even though our code is MIT

The app ships netmd-js and netmd-exploits inside its bundle and runs them in-process. We treat that as one combined work. MIT is GPL-compatible, so the combination can be distributed under the GPL-2.0. The MIT licence on our own files stays, and anyone can reuse those files on MIT terms, apart from the GPL components.

GPL obligations for each binary release:

- State that the binary is licensed under GPL-2.0, and include the licence text in the app.
- Link the exact source tag, including pinned submodules and build scripts, so anyone can reproduce the bundle.
- Don't add any restrictions on top (no DRM, no extra EULA terms).

## Mac App Store

Not viable while GPL code is bundled. App Store terms add usage restrictions that conflict with GPL §6 (the precedent is VLC's removal in 2011). Developer ID signing and notarisation are fine: they don't restrict what users can do with the software.

## Things we won't do

- Copy GPL code into MIT-labelled files.
- Ship any component without crediting it in the About window and in [ACKNOWLEDGEMENTS.md](../ACKNOWLEDGEMENTS.md).
- Include Sony binaries, firmware or keys beyond what the upstream projects already publish.
