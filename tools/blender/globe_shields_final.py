"""Still of the shipped shield looks and breaks, composited from the real sheets in SanctuaryUI/Art
with the numbers GlobeAura.lua draws them with (a check on the art, not a capture from the client).
Each look pairs with its default break; the first row is the Crystal shell and Shatter for reference.

    python globe_shields_final.py OUT.png
"""
import os
import re
import sys
import tempfile

sys.path.insert(0, os.path.dirname(__file__))
import globe_shields_compare as gsc  # noqa: E402

ROOT = os.path.join(os.path.dirname(__file__), "..", "..", "SanctuaryUI")
ART = os.path.join(ROOT, "Art")
PAIRS = {"aegis": "dissolve", "rime": "melt", "hex": "shockwave", "bulwark": "crumble"}


def lua_numbers():
    src = open(os.path.join(ROOT, "GlobeAura.lua"), encoding="utf-8").read()
    looks = {name: dict(zip(("tk", "idle", "halo"), map(float, m))) for name, *m in
             re.findall(r"(aegis|rime|hex|bulwark) = \{ tk = ([\d.]+), idle = ([\d.]+), halo = ([\d.]+),", src)}
    breaks = {name: dict(zip(("gain", "tk"), map(float, m))) for name, *m in
              re.findall(r"(dissolve|melt|shockwave|crumble) = \{ slot = \"\w+\", frames = \d+, cols = \d+, cell = \d+, sheet = \d+, seconds = [\d.]+, gain = ([\d.]+), tk = ([\d.]+) \}", src)}
    if set(looks) != set(PAIRS) or set(breaks) != set(PAIRS.values()):
        raise SystemExit("couldn't read the Lua's numbers")
    return looks, breaks


def main():
    looks, breaks = lua_numbers()
    for spec in gsc.OPTIONS:
        look = looks[spec["key"]]
        brk = breaks[PAIRS[spec["key"]]]
        spec.update(tk=look["tk"], idle=look["idle"], halo=look["halo"], brk=PAIRS[spec["key"]], brk_gain=brk["gain"], brk_tk=brk["tk"])
    with tempfile.TemporaryDirectory() as tmp:
        for name in gsc.SPECS:
            os.symlink(os.path.abspath(os.path.join(ART, f"shield-{name.replace('_', '-')}.png")), os.path.join(tmp, name + ".png"))
        gsc.still(tmp, sys.argv[1])


if __name__ == "__main__":
    main()
