# Icon exploration

A prompt-engineering loop for the MiniDisc app icon, run against
[Replicate](https://replicate.com). It is the Currawong icon process with a
different aesthetic: late-90s translucent plastic and Y2K futurism instead of a
mid-century screen print. Nothing here ships. A keeper gets rebuilt as layers
for a macOS 26 Liquid Glass icon (see `../IDENTITY.md`).

```sh
# token in REPLICATE_API_TOKEN or ~/.config/replicate/api_token
./explore.py --dry-run                   # read the resolved prompts
./explore.py -n 2                        # every variant, two seeds each
./explore.py -v clear-portrait -n 4 --seed 7
./explore.py --model black-forest-labs/flux-1.1-pro -v clear-portrait -n 2   # once a prompt is close
./explore.py --remap collection out/<run>/clear-*.png   # snap to exact palette hexes
open out/<run>/index.html
```

- `prompts.json` is the thing you edit. Three `styles`, one per direction
  under test (`clear` translucent plastic, `techno` flat 90s graphic,
  `chrome` Y2K render), one `subject`, and variants that each name a style
  and change one idea. `{palette}` is filled from the named scheme in
  `palette.json`.
- `palette.json` is sampled from photographs of our own discs: a Sony Color
  Collection 74 in blue and in red, and a grey 60. Blue is the primary,
  red the accent.
- Models describe colours approximately, so `--remap` quantises a finished
  image to a scheme's exact hexes with ImageMagick.
- `ref/` holds 1024 px copies of the author's photographs (originals are
  Fujifilm `DSCF66xx`). Kontext variants use them as image-to-image
  references. Unlike Currawong's CC BY-SA bird, these are ours, so a shipped
  icon may descend from them directly. They show Sony and MiniDisc marks;
  every prompt removes them, and a keeper is checked for any that survive.
- `out/` is git-ignored.

The default model is FLUX schnell, about a cent and a couple of seconds per
image. Kontext Pro variants (anything with an `image`) cost about four cents.

## The keeper

`out/` is ignored except for the chain the icon descends from, force-added:
`clear-waveform-19263` (text-only, schnell) and `wave-fix-cartridge-401`, a
Kontext edit of it that corrected the cartridge. `../icon/build.py` rebuilds
401's composition by hand with the cartridge measured from `ref/`.
