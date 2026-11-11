#!/usr/bin/env python3
"""Fetch the open-licence fonts SanctuaryUI bundles and write them to SanctuaryUI/Media/Fonts.

Every font is SIL Open Font License, from github.com/google/fonts; each family's OFL.txt goes to
Media/Fonts/licenses. Fonts with a Reserved Font Name are copied untouched (the OFL forbids a
modified copy keeping that name). The rest are frozen at one weight if variable (WoW wants static
fonts) and cut to Latin, Greek and Cyrillic.

Needs fontTools: python3 -m venv /tmp/ft && /tmp/ft/bin/pip install fonttools
Run: /tmp/ft/bin/python tools/build_ofl_fonts.py <empty download dir>
"""
import sys, shutil, urllib.parse, urllib.request
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools import subset
from fontTools.varLib import instancer
DL = Path(sys.argv[1])
OUT = Path(__file__).resolve().parent.parent / "SanctuaryUI" / "Media" / "Fonts"
RAW = "https://raw.githubusercontent.com/google/fonts/main/ofl/"
U = "U+0020-024F,U+0370-03FF,U+0400-04FF,U+1E00-1EFF,U+2000-206F,U+20A0-20CF,U+2100-214F,U+2190-21FF,U+2200-22FF,U+25A0-25FF"
# (dir, source file, out name, weight for variable fonts or None, modify?)  RFN fonts ship untouched.
JOBS = [
 ("cinzel", "Cinzel[wght].ttf", "Cinzel", 500, True),
 ("cinzel", "Cinzel[wght].ttf", "CinzelBold", 700, True),
 ("cinzeldecorative", "CinzelDecorative-Bold.ttf", "CinzelDecorative-Bold", None, False),
 ("marcellussc", "MarcellusSC-Regular.ttf", "MarcellusSC-Regular", None, False),
 ("imfellenglishsc", "IMFeENsc28P.ttf", "IMFellEnglishSC", None, True),
 ("uncialantiqua", "UncialAntiqua-Regular.ttf", "UncialAntiqua-Regular", None, False),
 ("unifrakturcook", "UnifrakturCook-Bold.ttf", "UnifrakturCook-Bold", None, False),
 ("grenzegotisch", "GrenzeGotisch[wght].ttf", "GrenzeGotisch", 500, True),
 ("newrocker", "NewRocker-Regular.ttf", "NewRocker-Regular", None, False),
 ("medievalsharp", "MedievalSharp.ttf", "MedievalSharp", None, False),
 ("almendrasc", "AlmendraSC-Regular.ttf", "AlmendraSC-Regular", None, False),
 ("metamorphous", "Metamorphous-Regular.ttf", "Metamorphous-Regular", None, False),
 ("eaglelake", "EagleLake-Regular.ttf", "EagleLake-Regular", None, False),
 ("fondamento", "Fondamento-Regular.ttf", "Fondamento-Regular", None, False),
 ("alegreya", "Alegreya[wght].ttf", "Alegreya", 500, True),
 ("ebgaramond", "EBGaramond[wght].ttf", "EBGaramond", 500, True),
 ("cormorantgaramond", "CormorantGaramond[wght].ttf", "CormorantGaramond", 600, True),
 ("alegreyasans", "AlegreyaSans-Medium.ttf", "AlegreyaSans", None, True),
 ("oswald", "Oswald[wght].ttf", "Oswald", 500, True),
 ("robotocondensed", "RobotoCondensed[wght].ttf", "RobotoCondensed", 500, True),
 ("barlowcondensed", "BarlowCondensed-SemiBold.ttf", "BarlowCondensed", None, True),
 ("firasanscondensed", "FiraSansCondensed-Medium.ttf", "FiraSansCondensed", None, True),
 ("teko", "Teko[wght].ttf", "Teko", 500, True),
 ("rajdhani", "Rajdhani-SemiBold.ttf", "Rajdhani", None, True),
]
(OUT / "licenses").mkdir(parents=True, exist_ok=True)
for d, src, _, _, _ in JOBS:
    for f in (src, "OFL.txt"):
        dst = DL / d / f
        if not dst.exists():
            dst.parent.mkdir(parents=True, exist_ok=True)
            urllib.request.urlretrieve(RAW + d + "/" + urllib.parse.quote(f), dst)
for d, src, name, wght, modify in JOBS:
    path, dst = DL / d / src, OUT / (name + ".ttf")
    if not modify:
        shutil.copyfile(path, dst)
    else:
        font = TTFont(path)
        if wght is not None:
            try:
                font = instancer.instantiateVariableFont(font, {"wght": wght}, updateFontNames=True)
            except Exception:
                font = instancer.instantiateVariableFont(font, {"wght": wght})
        opts = subset.Options(); opts.layout_features = ["*"]; opts.name_IDs = ["*"]; opts.glyph_names = True
        sub = subset.Subsetter(opts); sub.populate(unicodes=subset.parse_unicodes(U)); sub.subset(font)
        font.save(dst)
    assert "fvar" not in TTFont(dst), name
    shutil.copyfile(DL / d / "OFL.txt", OUT / "licenses" / f"{d}-OFL.txt")
    print(f"{dst.stat().st_size:>8} {name}")
