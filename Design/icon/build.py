#!/usr/bin/env -S uv run -q --with numpy python
# SPDX-License-Identifier: Apache-2.0
"""Build the app icon's layers as SVG, and previews of each waveform candidate.

    ./build.py --audio path/to/01-spore.wav   # re-derive waveforms.json from the recording
    ./build.py                                # layers + previews from waveforms.json
    open work/index.html

The composition is wave-fix-cartridge-401 from icon-explore, rebuilt with the
cartridge measured from ref/blue-front.jpg instead of the model's guess. Each
layer is a separate SVG because Icon Composer wants flat layers and adds the
glass itself. work/ holds flat composites (with an SVG glow standing in for
whatever Icon Composer does) at 1024, 64, 32 and 16 px.

waveforms.json is committed so the audio isn't needed to rebuild.
"""
import argparse, json, pathlib, subprocess
import numpy as np

HERE = pathlib.Path(__file__).resolve().parent
WORK = HERE / "work"
S = 1024

# Palette, from Design/icon-explore/palette.json.
NIGHT, BLUE, DEEP, GLINT = "#0b1e5a", "#0259f9", "#0137e0", "#4e91de"
RED, INK, SILVER = "#c7242c", "#0c152e", "#b3b5bc"
NEON = "#ff3b4a"  # the red line's core; Collection Red is its glow

# Cartridge, measured from the photographs (ref/blue-front.jpg, and the full
# DSCF6650 for detail). All positions are fractions of the shell, so H scales
# the whole thing. The details are the ones that say MiniDisc rather than CD,
# record or floppy: the tall shutter pane through the hub, the label wrapped
# round the right edge, a clear hub with a small spindle, the dark frame, the
# stepped corner and the INSERT THIS END arrow.
H = 640
W = round(H * 72 / 68)      # 72 x 68 mm
CX, CY = 560, 512           # shell centre: right of middle, leaving room for the wave
X0, Y0 = CX - W / 2, CY - H / 2
CORNER = 34                 # top-left and bottom-left
CORNER_TR = 12              # the top-right corner is nearly square
STEP_W, STEP_H = 0.09, 0.06  # the notch stepped out of the bottom-right corner
FRAME = 16                  # dark rim of the shell

HX, HY = X0 + 0.479 * W, Y0 + 0.494 * H  # hub, a touch left of centre
DISC_R = 0.452 * H
RING_R, RING_IN = 0.200 * H, 0.130 * H   # the dark printed ring
HUB_R, HOLE_R = 0.086 * H, 0.014 * H     # clear centre boss and spindle hole

SHUTTER = (0.049, 0.12, 0.579, 0.92)     # x0, y0, x1, y1 as fractions of the shell
LABEL = (0.607, 0.356, 1.012, 0.638)     # runs just past the edge, as the sticker wraps round
LABEL_LINES = 3                          # stand-ins for its monospaced text

# Waveform band: from near the left edge to just short of the hub ring.
WX0, WX1 = 64, HX - RING_R - 18
WAMP = 118                  # half-height
LINE = 13                   # stroke at 1024; ~0.8 px at 64
BAR, GAP = 10, 7


def fx(f):
    return X0 + f * W


def fy(f):
    return Y0 + f * H


def outline():
    """The shell's outline: rounded on the left, nearly square top-right, a
    step cut out of the bottom-right."""
    x1, y1 = X0 + W, Y0 + H
    sx, sy = x1 - STEP_W * W, y1 - STEP_H * H
    r, q = CORNER, CORNER_TR
    return (f"M{X0 + r},{Y0} H{x1 - q} Q{x1},{Y0} {x1},{Y0 + q} V{sy} H{sx} V{y1} H{X0 + r} "
            f"Q{X0},{y1} {X0},{y1 - r} V{Y0 + r} Q{X0},{Y0} {X0 + r},{Y0} Z")


def disc_svg():
    return (f'<circle cx="{HX}" cy="{HY}" r="{DISC_R}" fill="{BLUE}"/>'
            f'<circle cx="{HX}" cy="{HY}" r="{(RING_R + RING_IN) / 2}" fill="none" stroke="{INK}" stroke-width="{RING_R - RING_IN}"/>'
            f'<circle cx="{HX}" cy="{HY}" r="{HUB_R}" fill="none" stroke="{GLINT}" stroke-width="4" opacity=".8"/>'
            f'<circle cx="{HX}" cy="{HY}" r="{HOLE_R}" fill="{INK}"/>')


def shell_body_svg(alpha=".55", fill=DEEP):
    return f'<path d="{outline()}" fill="{fill}" fill-opacity="{alpha}"/>'


def shell_detail_svg():
    x0, y0, x1, y1 = SHUTTER
    ax, ay = fx(0.497), fy(0.035)
    return (f'<rect x="{fx(x0)}" y="{fy(y0)}" width="{(x1 - x0) * W}" height="{(y1 - y0) * H}" rx="8" '
            f'fill="{GLINT}" fill-opacity=".12" stroke="{GLINT}" stroke-width="4" stroke-opacity=".75"/>'
            f'<polygon points="{ax},{ay} {ax - 15},{ay + 44} {ax + 15},{ay + 44}" fill="none" '
            f'stroke="{GLINT}" stroke-width="4" stroke-linejoin="round" opacity=".8"/>'
            f'<path d="{outline()}" fill="none" stroke="{INK}" stroke-width="{FRAME}" stroke-linejoin="round"/>')


def shell_svg():
    return shell_body_svg() + shell_detail_svg()


def label_svg():
    x0, y0, x1, y1 = LABEL
    w, h = (x1 - x0) * W, (y1 - y0) * H
    lines = "".join(f'<rect x="{fx(x0) + 0.12 * w}" y="{fy(y0) + h * (0.3 + 0.18 * i)}" width="{w * (0.7 if i else 0.25)}" '
                    f'height="{h * 0.06}" rx="3" fill="{GLINT}" opacity=".8"/>' for i in range(LABEL_LINES))
    return f'<rect x="{fx(x0)}" y="{fy(y0)}" width="{w}" height="{h}" rx="16" fill="{INK}"/>' + lines


def ground_svg():
    return (f'<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1">'
            f'<stop offset="0" stop-color="#06123a"/><stop offset="1" stop-color="{NIGHT}"/></linearGradient></defs>'
            f'<rect width="{S}" height="{S}" fill="url(#g)"/>')


# --- waveforms ---------------------------------------------------------------
# Each candidate is a list of y offsets in [-1, 1] sampled across the band,
# drawn either as a line or as mirrored bars.

def hann(n):
    return 0.5 - 0.5 * np.cos(2 * np.pi * np.arange(n) / (n - 1))


def packets(fn, n=600, split=(0.0, 0.46, 0.56, 1.0), levels=(1, 1)):
    """Two wave packets with a flat gap between: sound, track mark, sound."""
    y = np.zeros(n)
    a, b, c, d = (int(s * n) for s in split)
    y[a:b] = levels[0] * fn(b - a, 0)
    y[c:d] = levels[1] * fn(d - c, 1)
    return y


def grain(n, k, cycles=(6, 7)):
    t = np.linspace(0, 1, n)
    return hann(n) * np.sin(2 * np.pi * cycles[k] * t)


def decode(path, sr=44100):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-ac", "1", "-ar", str(sr),
                          "-f", "f32le", "-"], capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32).astype(float), sr


def from_audio(path):
    x, sr = decode(path)
    out = {}

    # Envelope: the whole piece as peak bars, like a track overview.
    nb = int((WX1 - WX0) // (BAR + GAP))
    peaks = np.array([np.abs(c).max() for c in np.array_split(x, nb)])
    out["spore-overview"] = {"kind": "bars", "y": (peaks / peaks.max()).round(3).tolist(),
                             "note": f"peak level of all {len(x) / sr:.0f} s of Spore in {nb} bars"}

    # Partials: a 100 ms window at the loudest second, reduced to its three
    # strongest partials and resynthesised under a Hann window -- the way a
    # transform codec like ATRAC keeps what matters and drops the rest.
    rms = np.array([np.sqrt((c ** 2).mean()) for c in np.array_split(x, len(x) // sr)])
    t0 = int(rms.argmax()) * sr
    win = x[t0:t0 + sr // 10] * hann(sr // 10)
    spec = np.abs(np.fft.rfft(win, 1 << 16))
    freqs = np.fft.rfftfreq(1 << 16, 1 / sr)
    spec[freqs < 40] = 0
    picks = []
    for i in np.argsort(spec)[::-1]:
        if all(abs(freqs[i] - f) > 15 for f, _ in picks):
            picks.append((freqs[i], spec[i]))
        if len(picks) == 3:
            break
    f0 = min(f for f, _ in picks)

    def resynth(n, k):
        cyc = (6, 7)[k]  # show about this many periods of the lowest partial
        t = np.linspace(0, cyc / f0, n)
        y = sum(a * np.sin(2 * np.pi * f * t + p) for (f, a), p in zip(picks, (0, 1.1, 2.3)))
        return hann(n) * y / np.abs(y).max()

    out["spore-partials"] = {"kind": "line", "y": packets(resynth).round(4).tolist(),
                             "note": "Spore at %d s, three partials: %s Hz" % (t0 // sr, ", ".join(f"{f:.0f}" for f, _ in picks))}

    # Envelope of a 2 s phrase on a plain sine: the record's shape, a synth's tone.
    seg = x[t0 - sr:t0 + sr]
    env = np.array([np.abs(c).max() for c in np.array_split(seg, 600)])
    env = np.convolve(env, hann(41) / hann(41).sum(), "same")
    env /= env.max()
    car = np.sin(2 * np.pi * 13 * np.linspace(0, 1, 600))
    out["spore-envelope-sine"] = {"kind": "line", "y": (env * car).round(4).tolist(),
                                  "note": f"2 s of Spore around {t0 // sr} s as an envelope on a 13-cycle sine"}

    # The whole piece's arc, heavily smoothed, on a plain sine. Spore has no
    # clean onsets at any zoom, but its ten-minute shape -- fade in, a mass, a
    # dip near 300 s, a long second body -- is two packets, as in 401.
    env = np.array([np.abs(c).max() for c in np.array_split(x, 600)])
    k = hann(61) / hann(61).sum()
    env = np.convolve(np.pad(env, 30, mode="edge"), k, "valid")[:600]
    env = np.clip((env - env.min()) / (env.max() - env.min()), 0, 1) ** 1.6  # deepen the dip
    env *= hann(600) ** 0.15                                                  # land on zero at both ends
    car = np.sin(2 * np.pi * 15 * np.linspace(0, 1, 600))
    out["spore-arc-line"] = {"kind": "line", "y": (env * car).round(4).tolist(),
                             "note": f"all {len(x) / sr:.0f} s of Spore, smoothed, as the envelope of a 15-cycle sine"}
    out["spore-arc-bars"] = {"kind": "bars", "y": np.array([c.max() for c in np.array_split(env, nb)]).round(3).tolist(),
                             "note": f"the same arc as {nb} peak bars"}
    return out


def synthetic():
    return {
        "grain-line": {"kind": "line", "y": packets(grain).round(4).tolist(),
                       "note": "two Hann-windowed sines, 6 and 7 cycles"},
        "grain-bars": {"kind": "bars", "y": None, "note": "the same grains as peak bars (401's look)"},
        "grain-quiet": {"kind": "line", "y": packets(grain, levels=(1, 0.55)).round(4).tolist(),
                        "note": "the inner grain at 55%"},
        "grain-fade": {"kind": "line", "y": packets(grain, split=(0.0, 0.5, 0.58, 1.0), levels=(1, 0.4)).round(4).tolist(),
                       "note": "a longer outer grain, the inner one at 40%"},
        "grain-tail": {"kind": "line", "y": packets(lambda n, k: grain(n, k, (6, 9)), split=(0.0, 0.48, 0.54, 1.0),
                                                    levels=(1, 0.5)).round(4).tolist(),
                       "note": "the inner grain at 50% and finer, 9 cycles"},
    }


def wave_svg(c):
    ys = np.array(c["y"])
    if c["kind"] == "line":
        xs = np.linspace(WX0, WX1, len(ys))
        pts = " ".join(f"{x:.1f},{CY - y * WAMP:.1f}" for x, y in zip(xs, ys))
        line = f'<polyline points="{pts}" fill="none" stroke-linejoin="round" stroke-linecap="round"'
        return (f'{line} stroke="{RED}" stroke-width="{LINE * 3}" filter="url(#glow)" opacity=".9"/>'
                f'{line} stroke="{NEON}" stroke-width="{LINE}"/>')
    bars = []
    for i, y in enumerate(ys):
        x = WX0 + i * (BAR + GAP)
        h = max(abs(y) * WAMP, BAR / 2)
        bars.append(f'<rect x="{x}" y="{CY - h:.1f}" width="{BAR}" height="{2 * h:.1f}" rx="{BAR / 2}"/>')
    g = "".join(bars)
    return (f'<g fill="{RED}" filter="url(#glow)" opacity=".9">{g}</g>'
            f'<g fill="{NEON}">{g}</g>')


def wave_core_svg(c):
    ys = np.array(c["y"])
    xs = np.linspace(WX0, WX1, len(ys))
    pts = " ".join(f"{x:.1f},{CY - y * WAMP:.1f}" for x, y in zip(xs, ys))
    return (f'<polyline points="{pts}" fill="none" stroke="{NEON}" stroke-width="{LINE}" '
            f'stroke-linejoin="round" stroke-linecap="round"/>')


def wave_glow_svg(c):
    ys = np.array(c["y"])
    xs = np.linspace(WX0, WX1, len(ys))
    pts = " ".join(f"{x:.1f},{CY - y * WAMP:.1f}" for x, y in zip(xs, ys))
    return (f'<polyline points="{pts}" fill="none" stroke="{RED}" stroke-width="{LINE * 3}" '
            f'stroke-linejoin="round" stroke-linecap="round" filter="url(#glow)"/>')


def grain_bars():
    nb = int((WX1 - WX0) // (BAR + GAP))
    y = packets(grain, n=nb * 8)
    return np.abs(y).reshape(nb, 8).max(1).round(3).tolist()


GLOW = '<defs><filter id="glow" x="-20%" y="-50%" width="140%" height="200%"><feGaussianBlur stdDeviation="12"/></filter></defs>'


def doc(body):
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {S} {S}" width="{S}" height="{S}">{body}</svg>'


# --- Icon Composer -----------------------------------------------------------
# AppIcon.icon is a folder: icon.json plus the layer images in Assets/. Icon
# Composer supplies the glass, so the layers here are opaque and flat; the
# shell body is the glass group, and its translucency lets the disc through.

WAVE = "grain-quiet"
# Clear blue plastic, as on the real disc: a light shell over a vivid disc.
# Of the variants tried (Night Blue solid, Deep Blue solid, Glint at 35%,
# Night at 50%) this kept the disc legible in the tinted and clear modes too.
SHELL_FILL, SHELL_OPACITY, SHELL_TRANSLUCENCY = BLUE, 0.4, 0.6
ICTOOL = "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
RENDITIONS = ["Default", "Dark", "TintedLight", "TintedDark", "ClearLight", "ClearDark"]


def color(hexstr, a=1.0):
    r, g, b = (int(hexstr[i:i + 2], 16) / 255 for i in (1, 3, 5))
    return f"srgb:{r:.5f},{g:.5f},{b:.5f},{a:.5f}"


def layer(name, **kw):
    return {"image-name": f"{name}.svg", "name": name, **kw}


def ground(top, bottom):
    return {"linear-gradient": [color(top), color(bottom)],
            "orientation": {"start": {"x": 0.5, "y": 0}, "stop": {"x": 0.5, "y": 1}}}


def icon_json():
    return {
        # Dark mode would otherwise swap the navy for system grey.
        "fill-specializations": [{"value": ground("#06123a", NIGHT)},
                                 {"appearance": "dark", "value": ground("#030a22", "#081648")}],
        "groups": [
            {"name": "Waveform", "layers": [layer("wave", glass=False),
                                            {"image-name": "wave-glow.png", "name": "wave-glow", "glass": False}],
             "shadow": {"kind": "layer-color", "opacity": 0.6}, "specular": False},
            {"name": "Label", "layers": [layer("label", glass=False)],
             "shadow": {"kind": "neutral", "opacity": 0.3}},
            {"name": "Shell", "layers": [layer("shell-detail", glass=False), layer("shell-body", glass=True, opacity=SHELL_OPACITY)],
             "translucency": {"enabled": True, "value": SHELL_TRANSLUCENCY},
             "shadow": {"kind": "neutral", "opacity": 0.5}, "specular": True},
            {"name": "Disc", "layers": [layer("disc", glass=False)],
             "shadow": {"kind": "neutral", "opacity": 0.3}},
        ],
        "supported-platforms": {"squares": ["macOS"]},
    }


def write_icon(waves):
    bundle = HERE.parent.parent / "App" / "AppIcon.icon"  # where the app target picks it up
    assets = bundle / "Assets"
    assets.mkdir(parents=True, exist_ok=True)
    parts = {"disc": disc_svg(), "shell-body": shell_body_svg("1", SHELL_FILL), "shell-detail": shell_detail_svg(),
             "label": label_svg(), "wave": wave_core_svg(waves[WAVE])}
    for name, body in parts.items():
        (assets / f"{name}.svg").write_text(doc(body))
    # Icon Composer ignores SVG filters, so the glow goes in pre-rendered.
    glow = WORK / "wave-glow.svg"
    glow.write_text(doc(GLOW + wave_glow_svg(waves[WAVE])))
    subprocess.run(["rsvg-convert", "-w", str(S), "-h", str(S), str(glow), "-o", str(assets / "wave-glow.png")], check=True)
    (bundle / "icon.json").write_text(json.dumps(icon_json(), indent=2) + "\n")
    # The README's header image.
    readme = HERE.parent.parent / "docs" / "assets" / "icon-512.png"
    readme.parent.mkdir(exist_ok=True)
    subprocess.run([ICTOOL, str(bundle), "--export-image", "--output-file", str(readme), "--platform", "macOS",
                    "--rendition", "Default", "--width", "256", "--height", "256", "--scale", "2"], check=True)
    cards = []
    for r in RENDITIONS:
        out = WORK / f"icon-{r}.png"
        subprocess.run([ICTOOL, str(bundle), "--export-image", "--output-file", str(out), "--platform", "macOS",
                        "--rendition", r, "--width", "512", "--height", "512", "--scale", "2"], check=True)
        cards.append(f'<figure><img class=big src="icon-{r}.png"><figcaption><b>{r}</b></figcaption></figure>')
    (WORK / "icon.html").write_text(
        "<!doctype html><meta charset=utf-8><title>AppIcon.icon</title><style>"
        "body{background:#8a8a8f;color:#111;font:13px system-ui;margin:2rem}"
        "main{display:grid;grid-template-columns:repeat(3,1fr);gap:2rem}figure{margin:0}.big{width:100%}"
        "</style><main>" + "".join(cards) + "</main>")
    print(f"open {WORK / 'icon.html'}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--audio", help="recording to derive the audio waveforms from")
    ap.add_argument("--icon", action="store_true", help=f"also write AppIcon.icon with the {WAVE} waveform and render it with ictool")
    a = ap.parse_args()

    store = HERE / "waveforms.json"
    waves = json.loads(store.read_text()) if store.exists() else {}
    waves.update(synthetic())
    waves["grain-bars"]["y"] = grain_bars()
    if a.audio:
        waves.update(from_audio(a.audio))
    store.write_text(json.dumps(waves, indent=1))

    WORK.mkdir(exist_ok=True)
    # Bottom to top, as Icon Composer stacks them: the disc sits inside the
    # shell, so the shell is the glass over it.
    layers = {"0-ground": ground_svg(), "1-disc": disc_svg(), "2-shell": shell_svg(), "3-label": label_svg()}

    cards = []
    for name, c in waves.items():
        # Flat stand-in for the glass: the shell is a translucent fill over the disc.
        comp = doc(GLOW + "".join(layers.values()) + wave_svg(c))
        svg = WORK / f"{name}.svg"
        svg.write_text(comp)
        for px in (1024, 64, 32, 16):
            subprocess.run(["rsvg-convert", "-w", str(px), "-h", str(px), str(svg), "-o", str(WORK / f"{name}-{px}.png")], check=True)
        cards.append(f'<figure><img class=big src="{name}-1024.png"><figcaption><b>{name}</b> · {c["note"]}</figcaption>'
                     f'<div class=s><img src="{name}-64.png"><img src="{name}-32.png"><img src="{name}-16.png"></div></figure>')
    (WORK / "index.html").write_text(
        "<!doctype html><meta charset=utf-8><title>Icon layers</title><style>"
        "body{background:#1b1b1d;color:#ddd;font:13px system-ui;margin:2rem}"
        "main{display:grid;grid-template-columns:repeat(auto-fill,minmax(320px,1fr));gap:2rem}"
        "figure{margin:0}.big{width:100%;border-radius:22%}.s{display:flex;gap:12px;align-items:end;margin-top:8px}"
        ".s img{border-radius:22%;image-rendering:auto}</style><main>" + "".join(cards) + "</main>")
    print(f"open {WORK / 'index.html'}")
    if a.icon:
        write_icon(waves)


if __name__ == "__main__":
    main()
