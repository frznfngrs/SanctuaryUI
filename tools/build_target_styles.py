#!/usr/bin/env python3
"""Pack the target frame style renders (tools/blender/target_styles.py) into SanctuaryUI/Art.

  blender -b --factory-startup -P tools/blender/target_styles.py -- <work> [samples]
  python3 tools/build_target_styles.py <work>

Needs Pillow. Writes target-style-{lintel,slim,bracket,tablet}.png and target-style-parts.png;
the layout here is the contract with ns.Art.TARGET_STYLES in SanctuaryUI/Art.lua.
"""
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "SanctuaryUI" / "Art"
RANKS = ("normal", "rare", "elite", "boss")
FRAMES = ("lintel", "slim", "bracket", "tablet")


def main(work: Path) -> None:
    for name in FRAMES:
        atlas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
        y = 0
        for rank in RANKS:
            piece = Image.open(work / f"{name}-{rank}.png").convert("RGBA")
            atlas.paste(piece, (0, y))
            y += piece.height
        atlas.save(OUT / f"target-style-{name}.png", optimize=True)

    parts = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    for i, rank in enumerate(RANKS):
        parts.paste(Image.open(work / f"bracket_ring-{rank}.png"), (i % 3 * 280, i // 3 * 280))
        parts.paste(Image.open(work / f"castrail-{rank}.png"), (0, 560 + i * 52))
        parts.paste(Image.open(work / f"badge-{rank}.png"), (i * 48, 768))
    parts.paste(Image.open(work / "tot-normal.png"), (560, 560))
    parts.save(OUT / "target-style-parts.png", optimize=True)


if __name__ == "__main__":
    main(Path(sys.argv[1]))
