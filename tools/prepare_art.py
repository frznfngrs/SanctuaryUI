#!/usr/bin/env python3
"""Pull Diablo III HUD textures out of a local CASC install and write PNGs.

WoW Forever on this machine already draws addon PNGs (Questie calls SetTexture
on Interface\\AddOns\\Questie\\Icons\\*.png), so the pipeline emits PNG rather
than BLP. SanctuaryUI probes each file with SetTexture at login.

Usage:
  python3 tools/prepare_art.py
  python3 tools/prepare_art.py --game "/mnt/d/games/Diablo III" --casc /tmp/casc-bin
"""

from __future__ import annotations

import argparse
import json
import math
import struct
import subprocess
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("Pillow is required: pip install pillow", file=sys.stderr)
    raise

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = Path(__file__).resolve().parent / "manifest.json"
ART_DIR = ROOT / "SanctuaryUI" / "Art"
SRC_DIR = ROOT / "art-src"
REPORT = Path(__file__).resolve().parent / "art-report.txt"

# File layout from the Diablo III texture SNO (SNO header + Textures struct).
SNO_HEADER = 16
PIXEL_FORMATS = {
    0: "A8R8G8B8",
    4: "A1R5G5B5",
    7: "L8",
    9: "DXT1",
    10: "DXT1",
    11: "DXT3",
    12: "DXT5",
}


def next_pow2(value: int) -> int:
    size = 1
    while size < value:
        size *= 2
    return size


def parse_tex(data: bytes) -> dict:
    if len(data) < 64 or struct.unpack_from("<I", data, 0)[0] != 0xDEADBEEF:
        raise ValueError("not a Diablo III SNO texture")
    base = SNO_HEADER
    pixel_format, width, height, faces = struct.unpack_from("<4i", data, base + 16)
    mips = struct.unpack_from("<i", data, base + 36)[0]
    # First SerializeData entry is mip 0 of face 0. Offsets are from the SNO header end.
    offset, length = struct.unpack_from("<II", data, base + 40)
    payload = data[SNO_HEADER + offset : SNO_HEADER + offset + length]
    name = PIXEL_FORMATS.get(pixel_format, f"unknown-{pixel_format}")
    image = decode_pixels(name, width, height, payload)
    return {
        "format": name,
        "format_id": pixel_format,
        "width": width,
        "height": height,
        "faces": faces,
        "mips": mips,
        "image": image,
    }


def decode_pixels(fmt: str, width: int, height: int, payload: bytes) -> Image.Image:
    if fmt == "A8R8G8B8":
        raw = bytearray(width * height * 4)
        for i in range(width * height):
            b, g, r, a = payload[i * 4 : i * 4 + 4]
            raw[i * 4 : i * 4 + 4] = bytes((r, g, b, a))
        return Image.frombytes("RGBA", (width, height), bytes(raw))
    if fmt == "L8":
        return Image.frombytes("L", (width, height), payload[: width * height]).convert("RGBA")
    if fmt == "A1R5G5B5":
        raw = bytearray(width * height * 4)
        for i in range(width * height):
            pix = struct.unpack_from("<H", payload, i * 2)[0]
            a = 255 if pix & 0x8000 else 0
            r = ((pix >> 10) & 31) * 255 // 31
            g = ((pix >> 5) & 31) * 255 // 31
            b = (pix & 31) * 255 // 31
            raw[i * 4 : i * 4 + 4] = bytes((r, g, b, a))
        return Image.frombytes("RGBA", (width, height), bytes(raw))
    if fmt in ("DXT1", "DXT3", "DXT5"):
        return decode_dxt(fmt, width, height, payload)
    raise ValueError(f"unsupported texture format {fmt}")


def _rgb565(value: int) -> tuple[int, int, int]:
    r = ((value >> 11) & 31) * 255 // 31
    g = ((value >> 5) & 63) * 255 // 63
    b = (value & 31) * 255 // 31
    return r, g, b


def decode_dxt(fmt: str, width: int, height: int, payload: bytes) -> Image.Image:
    bw = max(1, (width + 3) // 4)
    bh = max(1, (height + 3) // 4)
    blocks = bw * bh
    if fmt == "DXT1":
        colors = payload[: blocks * 4]
        indices = payload[blocks * 4 : blocks * 8]
        alpha0 = alpha_idx = None
    elif fmt == "DXT3":
        alpha0 = payload[: blocks * 8]
        colors = payload[blocks * 8 : blocks * 12]
        indices = payload[blocks * 12 : blocks * 16]
        alpha_idx = None
    else:
        alpha0 = payload[: blocks * 2]
        alpha_idx = payload[blocks * 2 : blocks * 8]
        colors = payload[blocks * 8 : blocks * 12]
        indices = payload[blocks * 12 : blocks * 16]
    raw = bytearray(width * height * 4)
    for by in range(bh):
        for bx in range(bw):
            block = by * bw + bx
            c0 = struct.unpack_from("<H", colors, block * 4)[0]
            c1 = struct.unpack_from("<H", colors, block * 4 + 2)[0]
            palette = [_rgb565(c0) + (255,), _rgb565(c1) + (255,)]
            if c0 > c1 or fmt != "DXT1":
                palette.append(tuple((2 * palette[0][i] + palette[1][i]) // 3 for i in range(3)) + (255,))
                palette.append(tuple((palette[0][i] + 2 * palette[1][i]) // 3 for i in range(3)) + (255,))
            else:
                palette.append(tuple((palette[0][i] + palette[1][i]) // 2 for i in range(3)) + (255,))
                palette.append((0, 0, 0, 0))
            lookup = struct.unpack_from("<I", indices, block * 4)[0]
            alphas = [(255,)] * 16
            if fmt == "DXT3":
                chunk = struct.unpack_from("<Q", alpha0, block * 8)[0]
                alphas = []
                for i in range(16):
                    a = (chunk >> (i * 4)) & 0xF
                    alphas.append((a * 255 // 15,))
            elif fmt == "DXT5":
                a0 = alpha0[block * 2]
                a1 = alpha0[block * 2 + 1]
                aval = [a0, a1]
                if a0 > a1:
                    aval.extend(((6 - i) * a0 + (1 + i) * a1) // 7 for i in range(6))
                else:
                    aval.extend(((4 - i) * a0 + (1 + i) * a1) // 5 for i in range(4))
                    aval.extend((0, 255))
                bits = int.from_bytes(alpha_idx[block * 6 : block * 6 + 6], "little")
                alphas = []
                for i in range(16):
                    alphas.append((aval[(bits >> (i * 3)) & 7],))
            for py in range(4):
                for px in range(4):
                    x = bx * 4 + px
                    y = by * 4 + py
                    if x >= width or y >= height:
                        continue
                    idx = (lookup >> ((py * 4 + px) * 2)) & 3
                    r, g, b, a = palette[idx]
                    if fmt != "DXT1":
                        a = alphas[py * 4 + px][0]
                    off = (y * width + x) * 4
                    raw[off : off + 4] = bytes((r, g, b, a))
    return Image.frombytes("RGBA", (width, height), bytes(raw))


def upscale(image: Image.Image, target: int) -> Image.Image:
    long_edge = max(image.size)
    if long_edge >= target:
        return image
    scale = target / long_edge
    size = (next_pow2(round(image.width * scale)), next_pow2(round(image.height * scale)))
    return image.resize(size, Image.Resampling.LANCZOS)


def find_casc(explicit: str | None) -> Path:
    candidates = [Path(explicit)] if explicit else []
    candidates.extend([ROOT / "tools" / "casc", Path("/tmp/casc-bin")])
    for path in candidates:
        if path and path.is_file():
            return path
    raise SystemExit("CASC tool not found. Build github.com/jybp/casc/cmd/casc and pass --casc.")


def list_files(casc: Path, game: Path) -> list[str]:
    cache = SRC_DIR / "filelist.txt"
    if cache.is_file() and cache.stat().st_size > 0:
        return cache.read_text(encoding="utf-8", errors="replace").splitlines()
    SRC_DIR.mkdir(parents=True, exist_ok=True)
    # The casc binary lists when stdin is a terminal and extracts otherwise.
    tty = open("/dev/tty", "rb")
    proc = subprocess.run([str(casc), "-dir", str(game)], stdin=tty, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    tty.close()
    if proc.returncode != 0:
        raise SystemExit(proc.stderr.decode("utf-8", "replace") or "casc list failed")
    text = proc.stdout.decode("utf-8", "replace")
    cache.write_text(text, encoding="utf-8")
    return text.splitlines()


def score(name: str, hints: list[str]) -> int:
    lower = name.lower().replace("\\", "/")
    if not lower.endswith(".tex"):
        return 0
    if any(skip in lower for skip in ("irradiance", "/actor/", "normal", "_spec", "icon_")):
        return 0
    best = 0
    stem = lower.rsplit("/", 1)[-1]
    ui_bonus = 30 if "/ui/" in lower or "console" in stem or stem.startswith("x1_ui") else 0
    for hint in hints:
        if hint in stem:
            best = max(best, 100 - abs(len(stem) - len(hint)) + ui_bonus)
        elif hint in lower:
            best = max(best, 40 + ui_bonus)
    return best


def extract_one(casc: Path, game: Path, name: str, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    proc = subprocess.run(
        [str(casc), "-dir", str(game), "-o", str(dest.parent)],
        input=(name + "\n").encode("utf-8"),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    produced = dest.parent / Path(name).name
    if not produced.is_file():
        raise SystemExit(f"failed to extract {name}: {proc.stderr.decode('utf-8', 'replace')}")
    if produced != dest:
        produced.replace(dest)


# Known HUD sheets from the 2.8.0.99920 CASC list. Cells are cropped, then
# upscaled when the cell's long edge is under the slot target.
KNOWN = {
    "globeLiquid": {
        "source": "Base/Textures/2DUI_HealthGlobe_Classic.tex",
        "cached": "2DUI_HealthGlobe_Classic.tex",
        "crop": (0, 0, 96, 96),
        "luminance": True,
        "target": 512,
        "file": "globe-liquid.png",
    },
}


def bake_cached() -> None:
    spike = SRC_DIR / "spike"
    ART_DIR.mkdir(parents=True, exist_ok=True)
    lines = [
        "format: png",
        "reason: Questie on this Forever client loads Interface textures from PNG via SetTexture (Questie/Icons and MinimapIcon). SanctuaryUI probes each Art slot with SetTexture at login; /sanctuary check prints the count.",
        "upscale: Lanczos to the slot target when the cropped cell's long edge is smaller. Sheets larger than the target are cropped first, not shrunk.",
        "",
    ]
    for slot, info in KNOWN.items():
        raw_path = spike / info["cached"]
        if not raw_path.is_file():
            lines.append(f"{slot}: missing {raw_path}")
            continue
        parsed = parse_tex(raw_path.read_bytes())
        image = parsed["image"]
        crop = info.get("crop")
        if crop:
            image = image.crop(crop)
        if info.get("luminance"):
            image = to_luminance(image)
        before = image.size
        image = upscale(image, int(info["target"]))
        out = ART_DIR / info["file"]
        image.save(out)
        lines.append(
            f"{slot}: {info['source']} {parsed['format']} {parsed['width']}x{parsed['height']} "
            f"crop {crop} cell {before[0]}x{before[1]} -> {image.width}x{image.height} {out.name}"
        )
        print(lines[-1])
    bake_console(lines)
    lines.append("")
    lines.append("2DUIButtons.tex is DXT5 1024x512 of menu panels, not the skill sockets.")
    lines.append("2DUIBottomBar_Classic.tex is DXT3 1024x128 and is not the globe frame.")
    lines.append("bottomBar_buttonFX_frameGlow.tex is a square orange glow, not a socket ring.")
    lines.append("2DUI_ResourceGlobe_Classic.tex matches the health sheet (2048x512, 96px cells) in blue. The shipped liquid is the health sheet converted to luminance so power color can tint it.")
    lines.append("trough, xp, and pip stay on flat-color fallbacks. The console skill sockets are square stone panels, and stretching that strip to the circular row would squash it.")
    REPORT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"wrote {REPORT}")


def strip_corner_gold(image: Image.Image) -> None:
    pixels = image.load()
    width, height = image.size
    center = width / 2
    for y in range(int(height * 0.68), height):
        for x in range(width):
            if abs(x - center) < width * 0.22:
                continue
            red, green, blue, alpha = pixels[x, y]
            if alpha > 180 and red > 170 and green > 130 and blue < 120 and red > blue + 40:
                pixels[x, y] = (0, 0, 0, 0)


def bake_console(lines: list[str]) -> None:
    raw_path = SRC_DIR / "spike2" / "BottomBar_GameRes_Classic.tex"
    if not raw_path.is_file():
        lines.append(f"console: missing {raw_path}")
        return
    parsed = parse_tex(raw_path.read_bytes())
    image = parsed["image"]
    pixels = image.load()
    width, height = image.size

    def centered(cx: float, cy: float, half: int, reject) -> Image.Image:
        size = half * 2
        out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        out_px = out.load()
        for y in range(size):
            sy = int(round(cy - half + y))
            for x in range(size):
                sx = int(round(cx - half + x))
                if not (0 <= sx < width and 0 <= sy < height) or reject(sx, sy):
                    continue
                red, green, blue, alpha = pixels[sx, sy]
                edge = x < 36 or y < 36 or x >= size - 36 or y >= size - 36
                if edge and alpha > 180 and red > 170 and green > 130 and blue < 110:
                    continue
                out_px[x, y] = (red, green, blue, alpha)
        strip_corner_gold(out)
        return out

    left = upscale(centered(243.5, 96.8, 128, lambda sx, sy: sx >= 328), 512)
    right = upscale(centered(1180.0, 98.0, 128, lambda sx, sy: sx <= 1112), 512)
    left.save(ART_DIR / "globe-frame.png")
    right.save(ART_DIR / "globe-frame-resource.png")
    lines.append(
        "globeFrame: BottomBar_GameRes_Classic.tex A8R8G8B8 1416x200 "
        "left bezel, glass hole centered, 256 crop -> 512 globe-frame.png"
    )
    lines.append(
        "globeFrameResource: same sheet, right bezel -> 512 globe-frame-resource.png. "
        "Hole is about 0.53 of the texture, so the globe frame is outset 16 and the liquid inset is 23."
    )
    print(lines[-2])
    print(lines[-1])

    half = 92
    cx, cy = 243.5, 96.8
    ring = Image.new("RGBA", (half * 2, half * 2), (0, 0, 0, 0))
    ring_px = ring.load()

    def sample(sx: float, sy: float):
        radius = math.hypot(sx - cx, sy - cy)
        if radius < 64 or radius > 88:
            return None
        ix, iy = int(round(sx)), int(round(sy))
        if 0 <= ix < width and 0 <= iy < height and pixels[ix, iy][3] > 24:
            return pixels[ix, iy]
        return None

    for y in range(half * 2):
        for x in range(half * 2):
            sx = cx - half + x
            sy = cy - half + y
            radius = math.hypot(sx - cx, sy - cy)
            angle = math.degrees(math.atan2(sy - cy, sx - cx))
            if radius < 64 or radius > 88:
                continue
            pix = None if 70 < angle < 110 else sample(sx, sy)
            if pix is None and 60 < angle < 120:
                pix = sample(cx - (sx - cx), cy - (sy - cy))
            if pix:
                ring_px[x, y] = pix
    ring = upscale(ring, 256)
    ring.save(ART_DIR / "button-ring.png")
    ring.save(ART_DIR / "button-ring-small.png")
    lines.append(
        "buttonRing: circular metal bezel from the health globe, horn gap closed from the opposite arc, "
        f"{half * 2} -> {ring.width} button-ring.png and button-ring-small.png"
    )
    print(lines[-1])


def to_luminance(image: Image.Image) -> Image.Image:
    image = image.convert("RGBA")
    pixels = image.load()
    for y in range(image.height):
        for x in range(image.width):
            r, g, b, _a = pixels[x, y]
            lum = max(r, g, b)
            if lum < 18:
                pixels[x, y] = (0, 0, 0, 0)
            else:
                pixels[x, y] = (lum, lum, lum, 255)
    return image


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--game", default="/mnt/d/games/Diablo III")
    parser.add_argument("--casc", default=None)
    parser.add_argument("--bake", action="store_true", help="bake Art PNGs from textures already extracted under art-src/spike")
    args = parser.parse_args()
    if args.bake:
        bake_cached()
        return
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    casc = find_casc(args.casc)
    names = list_files(casc, Path(args.game))
    ART_DIR.mkdir(parents=True, exist_ok=True)
    lines = [
        "format: png",
        "reason: Questie on this Forever client loads Interface textures from PNG via SetTexture.",
        "SanctuaryUI probes each Art slot at login; /sanctuary check prints how many loaded.",
        "upscale: Lanczos up to the slot target when the long edge is smaller. Larger sources are kept.",
        "",
    ]
    for slot, info in manifest.items():
        ranked = sorted(((score(name, info["hints"]), name) for name in names), reverse=True)
        best_score, best_name = ranked[0] if ranked else (0, "")
        if best_score <= 0:
            lines.append(f"{slot}: no texture matched hints {info['hints']}")
            continue
        raw_path = SRC_DIR / slot / Path(best_name).name
        extract_one(casc, Path(args.game), best_name, raw_path)
        parsed = parse_tex(raw_path.read_bytes())
        image = upscale(parsed["image"], int(info["target"]))
        out = ART_DIR / info["file"]
        image.save(out)
        lines.append(
            f"{slot}: {best_name} {parsed['format']} {parsed['width']}x{parsed['height']} "
            f"-> {image.width}x{image.height} {out.name}"
        )
        print(lines[-1])
    REPORT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"wrote {REPORT}")


if __name__ == "__main__":
    main()
