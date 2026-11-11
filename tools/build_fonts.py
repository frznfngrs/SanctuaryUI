#!/usr/bin/env python3
"""Cut Diablo III's fonts out of their .fnt containers into SanctuaryUI/Media.

The .fnt files come from D3's CASC (Base/Font/*.fnt, see tools/extract_d3.sh) and sit in
art-src/fonts. Each holds a TrueType font after a 216-byte header. Serif and SansSerif carry
CJK too (19 MB and 7 MB), so they are subset to Latin, Greek, Cyrillic and common symbols.

Needs fontTools: python3 -m venv /tmp/ft && /tmp/ft/bin/pip install fonttools
Run: /tmp/ft/bin/python tools/build_fonts.py
"""
import struct
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "art-src" / "fonts"
OUT = ROOT / "SanctuaryUI" / "Media"
HEADER = 216
FONTS = {"Serif.fnt": "d3-serif.ttf", "SansSerif.fnt": "d3-sans.ttf", "Script.fnt": "d3-script.ttf"}
UNICODES = "U+0020-024F,U+0370-03FF,U+0400-04FF,U+1E00-1EFF,U+2000-206F,U+20A0-20CF,U+2100-214F,U+2190-21FF,U+2200-22FF,U+25A0-25FF,U+2600-26FF"


def carve(data):
    """The sfnt inside a .fnt, cut at the end of its last table."""
    font = data[HEADER:]
    count = struct.unpack(">H", font[4:6])[0]
    end = 0
    for i in range(count):
        _, _, offset, length = struct.unpack(">4sIII", font[12 + 16 * i:28 + 16 * i])
        end = max(end, offset + length)
    return font[:(end + 3) & ~3]


def main():
    for src, dst in FONTS.items():
        raw = OUT / (dst + ".full")
        raw.write_bytes(carve((SRC / src).read_bytes()))
        options = subset.Options()
        options.layout_features = ["*"]
        options.name_IDs = ["*"]
        options.glyph_names = True
        font = TTFont(raw)
        subsetter = subset.Subsetter(options)
        subsetter.populate(unicodes=subset.parse_unicodes(UNICODES))
        subsetter.subset(font)
        font.save(OUT / dst)
        raw.unlink()
        print(dst, (OUT / dst).stat().st_size)


if __name__ == "__main__":
    main()
