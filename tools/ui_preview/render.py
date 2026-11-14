"""Offline preview of SanctuaryUI frames: the real Lua runs in lupa against wow.lua (a recording
WoW API stand-in), then the frames it set up are laid out and drawn with the addon's own art and
fonts, and any two pieces of text that overlap are reported.

Run: PYTHONPATH=<dir with lupa + pillow> python tools/ui_preview/render.py [out_dir]
Shots: the Run Report's six pages (its Preview), the run-complete banner, and the final-boss
flow (a run completes when the journal's last boss dies, its banner shows once).
"""
import math
import os
import re
import sys

import resource

# Never more than 3 GB: a runaway (a loop that grows a table, a huge image) fails here with a
# MemoryError instead of taking all of WSL's memory down with it.
resource.setrlimit(resource.RLIMIT_AS, (3 << 30, 3 << 30))

import lupa.lua51 as lupa
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.normpath(os.path.join(HERE, "..", "..", "SanctuaryUI"))
ART = SRC + "/Art/"
FONTS = {"title": SRC + "/Media/exocet.ttf", "body": SRC + "/Media/d3-serif.ttf"}
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "shots")

lua = lupa.LuaRuntime(unpack_returned_tuples=True)


def measure(role, size, text):
    f = ImageFont.truetype(FONTS.get(role, FONTS["body"]), max(4, int(round(size * 4))))
    return f.getlength(text) / 4


lua.globals().MEASURE = measure


def load(path):
    lua.execute(f'local f = assert(loadfile("{path}")) f("SanctuaryUI", {{}})')


load(HERE + "/wow.lua")
for f in ("Settings", "Art", "Meter", "MeterHistory", "MeterGlory", "RunReport"):
    load(f"{SRC}/{f}.lua")
lua.execute('''
local ns = SanctuaryUI
PROFILE = ns.DEFAULTS.profile
function ns.DB() return PROFILE end
ns.db = { char = { meter = {} }, profile = PROFILE }
ns.Art.ready = nil
if ns.Art.Probe then ns.Art.Probe() end
ns.Meter.Supported = function() return true end
''')


def T(o, k):
    try:
        return o[k]
    except Exception:
        return None


font_cache, img_cache, TEXT = {}, {}, []


def font(role, px):
    key = (role, int(round(px)))
    if key not in font_cache:
        font_cache[key] = ImageFont.truetype(FONTS.get(role, FONTS["body"]), max(4, int(round(px))))
    return font_cache[key]


def strip(t):
    return re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", t or "")


def art(path):
    if path not in img_cache:
        f = ART + path.replace("\\", "/").split("/")[-1]
        img_cache[path] = Image.open(f).convert("RGBA") if "SanctuaryUI" in path and os.path.exists(f) else None
    return img_cache[path]


def own_scale(o):
    s, w = 1.0, o if T(o, "kind") not in ("Texture", "FontString") else T(o, "parent")
    while w is not None:
        s *= (T(w, "scale") or 1)
        w = T(w, "parent")
    return s


class Layout:
    def __init__(self):
        self.cache = {}

    def rect(self, o):
        idx = T(o, "idx")
        if idx in self.cache:
            return self.cache[idx]
        if T(o, "name") == "UIParent":
            return (0.0, 0.0, 1920.0, 1080.0)
        self.cache[idx] = (0, 0, 0, 0)
        s = own_scale(o)
        pts = T(o, "points")
        L = R = B = Tp = CX = CY = None
        for i in range(1, (len(pts) if pts is not None else 0) + 1):
            p = pts[i]
            point, rel, rp, x, y = p[1], p[2], p[3], p[4] or 0, p[5] or 0
            rr = self.rect(rel) if rel is not None else (0, 0, 1920, 1080)
            ax = rr[0] if "LEFT" in rp else rr[2] if "RIGHT" in rp else (rr[0] + rr[2]) / 2
            ay = rr[3] if "TOP" in rp else rr[1] if "BOTTOM" in rp else (rr[1] + rr[3]) / 2
            ax, ay = ax + x * s, ay + y * s
            if "LEFT" in point: L = ax
            elif "RIGHT" in point: R = ax
            else: CX = ax
            if "TOP" in point: Tp = ay
            elif "BOTTOM" in point: B = ay
            else: CY = ay
        w, h = (T(o, "w") or 0) * s, (T(o, "h") or 0) * s
        if T(o, "kind") == "Texture" and T(o, "tex") is not None:
            im = art(str(T(o, "tex")))  # as the game: no size set takes the file's
            if im is not None:
                w, h = w or im.size[0] * s, h or im.size[1] * s
        if T(o, "kind") == "FontString":
            size = (T(o, "size") or 12) * s
            w = w or font(T(o, "font") or "body", size).getlength(strip(T(o, "text")))
            h = h or size * 1.15
        if L is not None and R is not None: pass
        elif L is not None: R = L + w
        elif R is not None: L = R - w
        elif CX is not None: L, R = CX - w / 2, CX + w / 2
        else: L, R = 0, w
        if Tp is not None and B is not None: pass
        elif Tp is not None: B = Tp - h
        elif B is not None: Tp = B + h
        elif CY is not None: B, Tp = CY - h / 2, CY + h / 2
        else: B, Tp = 0, h
        self.cache[idx] = (L, B, R, Tp)
        return self.cache[idx]


def visible(o):
    while o is not None:
        if not T(o, "shown"):
            return False
        o = T(o, "parent")
    return True


def level(o):
    chain, w = [], (o if T(o, "kind") not in ("Texture", "FontString") else T(o, "parent"))
    while w is not None:
        chain.append(w)
        w = T(w, "parent")
    lv = 0
    for w in reversed(chain):
        lv = T(w, "level") if T(w, "level") is not None else lv + 1
    return lv


def draw(out, root_name, K=2.0, pad=50):
    allv = lua.eval("ALL")
    objs = [allv[i] for i in range(1, len(allv) + 1)]
    lay = Layout()
    root = next(o for o in objs if T(o, "name") == root_name)
    items = []
    for o in objs:
        if T(o, "kind") not in ("Texture", "FontString") or not visible(o):
            continue
        if T(o, "layer") == 4 or T(o, "blend") == "ADD":
            continue
        w, under = o, False
        while w is not None:
            if T(w, "name") == root_name:
                under = True
                break
            w = T(w, "parent")
        if under:
            items.append(o)
    rr = lay.rect(root)
    rects = [lay.rect(o) for o in items]
    minx = min([rr[0]] + [r[0] for r in rects]); maxx = max([rr[2]] + [r[2] for r in rects])
    miny = min([rr[1]] + [r[1] for r in rects]); maxy = max([rr[3]] + [r[3] for r in rects])
    size = (int((maxx - minx) * K) + 2 * pad, int((maxy - miny) * K) + 2 * pad)
    if size[0] * size[1] > 40_000_000:
        raise RuntimeError(f"{root_name}: a {size[0]}x{size[1]} image; something is laid out far off (check the anchors)")
    img = Image.new("RGBA", size, (34, 31, 28, 255))

    def px(x, y):
        return (x - minx) * K + pad, (maxy - y) * K + pad

    order = sorted(range(len(items)), key=lambda i: (level(items[i]), T(items[i], "layer") or 0, T(items[i], "sub") or 0, T(items[i], "idx")))
    d = ImageDraw.Draw(img)
    for i in order:
        o, r = items[i], rects[i]
        x0, y0 = px(r[0], r[3]); x1, y1 = px(r[2], r[1])
        if T(o, "kind") == "Texture":
            w, h = int(math.ceil(x1) - math.floor(x0)), int(math.ceil(y1) - math.floor(y0))
            x0, y0 = math.floor(x0), math.floor(y0)
            if w <= 0 or h <= 0:
                continue
            vc = T(o, "vcolor")
            m = (vc[1], vc[2], vc[3], vc[4] or 1) if vc is not None else (1, 1, 1, 1)
            ct = T(o, "colorTex")
            if ct is not None:
                col = tuple(int(255 * max(0, min(1, ct[j] * m[j - 1]))) for j in (1, 2, 3)) + (int(255 * ct[4] * m[3] * (T(o, "alpha") or 1)),)
                img.alpha_composite(Image.new("RGBA", (w, h), col), (x0, y0))
                continue
            tex = T(o, "tex")
            if tex is None:
                continue
            im = art(str(tex))
            if im is None:
                if "icon" in str(tex) or str(tex).isdigit():
                    img.alpha_composite(Image.new("RGBA", (w, h), (70, 62, 52, 255)), (x0, y0))
                continue
            c = T(o, "coords")
            if c is not None:
                W0, H0 = im.size
                xa, xb = sorted((c[1] * W0, c[2] * W0))
                piece = im.crop((int(round(xa)), int(round(c[3] * H0)), max(int(round(xa)) + 1, int(round(xb))), max(int(round(c[3] * H0)) + 1, int(round(c[4] * H0)))))
                if c[2] < c[1]:
                    piece = piece.transpose(Image.FLIP_LEFT_RIGHT)
            else:
                piece = im
            if w * h > 40_000_000:
                raise RuntimeError(f"a {w}x{h} texture")
            piece = piece.resize((w, h), Image.LANCZOS)
            if vc is not None:
                ch = piece.split()
                piece = Image.merge("RGBA", [ch[j].point(lambda v, k=m[j]: min(255, v * k)) for j in range(3)] + [ch[3].point(lambda v, k=m[3]: v * k)])
            img.alpha_composite(piece, (x0, y0))
        else:
            text = T(o, "text")
            if not text:
                continue
            size = (T(o, "size") or 12) * own_scale(o) * K
            f = font(T(o, "font") or "body", size)
            col = T(o, "color")
            base = tuple(int(255 * col[j]) for j in (1, 2, 3)) if col is not None else (255, 255, 255)
            has_w, boxw = (T(o, "w") or 0) > 0, x1 - x0
            lines = [str(text)]
            if has_w and T(o, "wrap"):
                lines, cur = [], ""
                for wd in str(text).split(" "):
                    trial = (cur + " " + wd).strip()
                    if f.getlength(strip(trial)) > boxw and cur:
                        lines.append(cur)
                        cur = wd
                    else:
                        cur = trial
                lines.append(cur)
            elif has_w and f.getlength(strip(str(text))) > boxw + 1:
                t = strip(str(text))
                while t and f.getlength(t + "...") > boxw:
                    t = t[:-1]
                lines = [t + "..."]
            j = T(o, "justify") or "LEFT"
            lh = size * 1.2
            top = y0 if (has_w and T(o, "wrap")) else (y0 + y1) / 2 - lh * (len(lines) - 1) / 2
            for li, line in enumerate(lines):
                runs, cur = [], base
                for part in re.split(r"(\|c[0-9a-fA-F]{8}|\|r)", line):
                    if part.startswith("|c"):
                        cur = tuple(int(part[4 + 2 * q:6 + 2 * q], 16) for q in range(3))
                    elif part == "|r":
                        cur = base
                    elif part:
                        runs.append((part, cur))
                total = sum(f.getlength(p) for p, _ in runs)
                tx = x1 - total if j == "RIGHT" else x0 + (boxw - total) / 2 if j == "CENTER" else x0
                ty = top + lh * li + (lh / 2 if (has_w and T(o, "wrap")) else 0)
                TEXT.append((tx, ty - size * 0.45, tx + total, ty + size * 0.45, strip(line)))
                for p, c in runs:
                    d.text((tx + 2, ty + 2), p, font=f, fill=(0, 0, 0, 255), anchor="lm")
                    d.text((tx, ty), p, font=f, fill=c + (255,), anchor="lm")
                    tx += f.getlength(p)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    img.convert("RGB").save(out)
    hits = [(a[4], b[4]) for i, a in enumerate(TEXT) for b in TEXT[i + 1:]
            if a[0] < b[2] - 3 and b[0] < a[2] - 3 and a[1] < b[3] - 3 and b[1] < a[3] - 3]
    TEXT.clear()
    if hits:
        print("COLLISIONS in", os.path.basename(out))
        for a, b in hits[:10]:
            print("   ", repr(a[:50]), "x", repr(b[:50]))
    return out


def errors():
    e, p = lua.eval("ERRORS"), lua.eval("PRINTED")
    return [e[i] for i in range(1, len(e) + 1)], [p[i] for i in range(1, len(p) + 1)]


def final_boss_flow():
    """A run completes when the journal's last boss dies: the banner shows then, with its chime,
    and not again on leaving. Unlocking frames shows it to be moved."""
    lua.execute(r'''
local ns = SanctuaryUI
local H, L = ns.MeterHistory, ns.Meter.Lib
ns.db.char.meter = {}
H.Init()
ns.MeterGlory.Init()
local FIGHT, sid = nil, 0
L.Available = function() return true end
L.Sessions = function() return { { sessionID = sid, name = FIGHT.name } } end
L.Duration = function() return FIGHT.dur end
L.Fetch = function(_, t)
	if t ~= 0 then return { combatSources = {} } end
	return { combatSources = {
		{ name = "Forearms", sourceGUID = "G-Forearms", classFilename = "WARRIOR", isLocalPlayer = true, totalAmount = FIGHT.dur * 300, amountPerSecond = 300 },
		{ name = "Mirelle", sourceGUID = "G-Mirelle", classFilename = "MAGE", isLocalPlayer = false, totalAmount = FIGHT.dur * 250, amountPerSecond = 250 },
	} }
end
L.FetchSource = function(_, t, guid)
	if t ~= 0 then return { combatSpells = {} } end
	if guid == "G-Mirelle" then return { combatSpells = { { spellID = 529, totalAmount = 900 }, { spellID = 403, totalAmount = 100 } } } end
	return { combatSpells = { { spellID = 6603, totalAmount = 1000 } } }
end
local function Fight(name, dur, id, boss)
	sid = sid + 1
	FIGHT = { name = name, dur = dur }
	if boss then Fire("ENCOUNTER_END", id, boss, 1, 5, 1) end
	return assert(H.Record(), "recorded " .. name)
end
INSTANCE = "party"
Fire("PLAYER_ENTERING_WORLD", true, false)
SOUNDS = {}
Fight("Defias Miner", 20)
Fight("Rhahk'Zor", 50, 1443, "Rhahk'Zor")
local r = H.LatestRun()
assert(not (SanctuaryUIRunBanner and SanctuaryUIRunBanner:IsShown()) and not r.complete, "not the last boss: no banner")
Fight("Mr. Smite", 90, 1446, "Mr. Smite")
assert(r.complete, "the journal's last boss completes the run")
assert(SanctuaryUIRunBanner:IsShown(), "banner at the final boss")
assert(#SOUNDS == 1, "one chime")
local lb = r.players.Mirelle.sp.d["Lightning Bolt"]
assert(lb and lb.v == 3000 and lb.n == 3, "ranks folded by name")
RunTimers()
Fire("PLAYER_REGEN_DISABLED")
assert(not SanctuaryUIRunBanner:IsShown(), "the next pull puts it away")
local stopped = r.t1
INSTANCE = nil
Fire("PLAYER_ENTERING_WORLD", false, false)
assert(r.done and r.t1 == stopped and not SanctuaryUIRunBanner:IsShown() and #SOUNDS == 1, "leaving: no second banner, clock stays stopped")
-- Unlocked frames: the banner shows, held through a pull, to be moved; locked again it goes.
ns.Meter.UpdateMovers = ns.Meter.UpdateMovers
ns.RunReport.UpdateMovers(true)
assert(SanctuaryUIRunBanner:IsShown(), "shown while unlocked")
Fire("PLAYER_REGEN_DISABLED")
assert(SanctuaryUIRunBanner:IsShown(), "held while unlocked")
ns.RunReport.UpdateMovers(false)
assert(not SanctuaryUIRunBanner:IsShown(), "gone when locked")
''')
    print("final boss flow ok")


if __name__ == "__main__":
    # The banner, as the preview shows it.
    lua.execute("SanctuaryUI.RunReport.PreviewBanner()")
    draw(OUT + "/banner.png", "SanctuaryUIRunBannerHolder", K=1.6)
    lua.execute("SanctuaryUIRunBanner:Hide()")
    # The report's pages.
    lua.execute("SanctuaryUI.RunReport.Preview()")
    for pg in ("summary", "pulls", "bosses", "players", "dangers", "past"):
        lua.execute(f'for _, w in ipairs(ALL) do if w.key == "{pg}" and w.art and w.scripts.OnClick then w.scripts.OnClick(w) end end')
        draw(f"{OUT}/{pg}.png", "SanctuaryUIRunReport")
    lua.execute("SanctuaryUIRunReport:Hide()")
    final_boss_flow()
    errs, printed = errors()
    print("errors:", len(errs), errs[:5])
    print("sounds:", list(lua.eval("SOUNDS").values()))
