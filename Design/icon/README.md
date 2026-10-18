# App icon

`AppIcon.icon` is a macOS 26 Icon Composer document, written by `build.py`.
Edit the constants at the top of `build.py`, not the `.icon`, and rebuild:

```sh
./build.py --icon     # needs uv, librsvg, and Xcode's Icon Composer for ictool
open work/icon.html   # Default, Dark, Tinted and Clear renditions from ictool
open work/index.html  # flat previews of every waveform candidate
```

The composition is `wave-fix-cartridge-401` from `../icon-explore`, rebuilt
by hand: the cartridge is measured from the photographs in `../icon-explore/ref/`,
with the details that make it read as a MiniDisc rather than a CD, a record or
a floppy (tall shutter pane, label wrapped round the right edge, clear hub
with a small spindle, dark frame, stepped corner, INSERT THIS END arrow).

Layers, top to bottom: the waveform (with its glow pre-rendered as a PNG,
since Icon Composer ignores SVG filters), the label, the shell (the glass
group: Collection Blue at 40% so the disc shows through in every appearance)
and the disc. The ground is a night-blue gradient, with a darker one for dark
mode so the system doesn't swap it for grey.

## The waveform

`grain-quiet`: two Hann-windowed sines, the second at 55% as it passes into
the shell, with a flat gap between them like a track mark. A windowed
sinusoid is also the basis function of the MDCT that ATRAC encodes with.

Real audio was tried and set aside. `waveforms.json` keeps candidates derived
from Hyphae's "Spore" (`--audio` regenerates them): its three strongest
partials beat because they aren't harmonic, and it has no clean onsets at any
zoom. At Dock sizes only a waveform's envelope survives, so the envelope has
to be simple. Spore's full-track overview is better used where there's room
for it, like an About window or the DMG background.

## In the app

`--icon` also writes `App/Assets.xcassets/Cartridge.imageset`: the cartridge
alone (disc, shell, label), with no waveform and no ground, cropped to the
shell, as a vector SVG. It's for the app's own UI, starting with the
empty state. The shell stays translucent, so it takes on the window's colour
in light and dark mode.
