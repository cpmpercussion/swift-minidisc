# Visual identity

The app moves music onto MiniDisc, a format whose best-loved physical form is
the translucent coloured disc of the late 1990s. The identity takes its look
from those objects, specifically the discs we own and photographed
(`icon-explore/ref/`), rather than from a borrowed retro style.

## Palette

From `icon-explore/palette.json`, sampled from the photographs:

| Role      | Name            | Hex       |
|-----------|-----------------|-----------|
| Primary   | Collection Blue | `#0259f9` |
| Shadow    | Deep Blue       | `#0137e0` |
| Ground    | Night Blue      | `#0b1e5a` |
| Highlight | Glint Blue      | `#4e91de` |
| Accent    | Collection Red  | `#c7242c` |
| Ink       | Shell Black     | `#0c152e` |
| Neutral   | Cartridge Grey  | `#444d5a` |
| Light     | Label Silver    | `#b3b5bc` |

Blue leads. Red is used sparingly for the thing that is happening (recording,
transfer, the waveform), the way a REC light is.

## Motifs

- A translucent shell with the disc and hub visible through it.
- The audio waveform, as on the "shock absorbing" mark.
- Registration crosshairs and thin technical rules.
- Monospaced, label-like type, as on the Color Collection label.

## Rules

- No Sony wordmark, no MiniDisc logo, no readable text in the icon.
- The visible round disc and hub must keep it from reading as a floppy disk or
  a Save icon. Check every candidate against one at 32 px.
- Test at 16, 32 and 64 px and in a Dock row before choosing.

## Icon format

macOS 26 Liquid Glass, authored in Icon Composer (ships with Xcode). Icon
Composer takes flat layers and applies the glass itself: translucency,
specular edges, and the light, dark, tinted and clear appearances. So a
generated image is a concept, not the asset. A keeper is rebuilt as a few flat
SVG layers (ground, shell, disc, hub, accent) and the system supplies the
gloss that the Y2K look wants. Older macOS gets the flattened fallback that
Xcode generates from the `.icon` file.
