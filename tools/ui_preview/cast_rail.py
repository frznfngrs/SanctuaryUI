import os, sys
import lupa.lua51 as lupa
REPO = '/home/codym/wow3dui'
SRC = REPO + '/SanctuaryUI'
lua = lupa.LuaRuntime(unpack_returned_tuples=True)
def load(p): lua.execute(f'local f = assert(loadfile("{p}")) f("SanctuaryUI", {{}})')
load(REPO + '/tools/ui_preview/wow.lua')
lua.execute(r'''
local ns = SanctuaryUI
NOW = 100
function GetTime() return NOW end
-- StatusBar, Cooldown, mask pieces the mock lacks
local proto = getmetatable(CreateFrame("Frame"))
local W = {}
for k, v in pairs(proto) do W[k] = v end
local base = proto.__index
proto.__index = function(t, k)
	if k == "RegisterUnitEvent" then return function(self, e) self.ev[e] = true end end
	if k == "SetStatusBarTexture" then return function(self, p) self.sbtex = p; self.fill = self.fill or self:CreateTexture() end end
	if k == "GetStatusBarTexture" then return function(self) self.fill = self.fill or self:CreateTexture(); return self.fill end end
	if k == "SetStatusBarColor" then return function(self, r, g, b, a) self.sbcolor = { r, g, b, a } end end
	if k == "SetMinMaxValues" then return function(self, a, b) self.min, self.max = a, b end end
	if k == "GetMinMaxValues" then return function(self) return self.min, self.max end end
	if k == "SetValue" then return function(self, v) self.value = v end end
	if k == "GetValue" then return function(self) return self.value end end
	if k == "CreateMaskTexture" then return function(self) return self:CreateTexture() end end
	if k == "SetCooldown" then return function(self, s, d) self.cdStart, self.cdDur = s, d end end
	if k == "Clear" then return function(self) self.cdStart = nil end end
	if k == "SetReverse" then return function(self, r) self.reverse = r end end
	if k == "SetFormattedText" then return function(self, f, ...) self.text = string.format(f, ...) end end
	return base(t, k)
end
CAST = nil   -- { name, icon, startMS, endMS, channel }
function UnitCastingInfo(u) if CAST and not CAST.channel then return CAST.name, "", CAST.icon, CAST.startMS, CAST.endMS, false, "guid1", false, 133 end end
function UnitChannelInfo(u) if CAST and CAST.channel then return CAST.name, "", CAST.icon, CAST.startMS, CAST.endMS, false, false, 5143 end end
function C_Timer.After(d, f) TIMERS[#TIMERS + 1] = { NOW + d, f } end
function RunTimers() local l = TIMERS TIMERS = {} for _, t in ipairs(l) do if t[1] <= NOW + 1e-9 then t[2]() else TIMERS[#TIMERS + 1] = t end end end
FAILED, INTERRUPTED = "Failed", "Interrupted"
function ns.Or(v, d) if v == nil then return d end return v end
ns.Fonts = { Set = function(fs, role, size, flags) fs.role, fs.size = role, size end }
ns.LEVEL = { rail = 8, console = 9 }
ns.TEX_W = 1595
PROFILE = { castRail = true, castMedallion = true, castTextSize = 13, levelPlaque = true, castWhere = "rail",
	castBar = { style = "paragon", width = 340, scale = 1, textSize = 12, moved = false, mx = 0, my = 0 } }
function ns.DB() return PROFILE end
ns.Art = { Path = function(s) return "art:" .. s end, Apply = function(t, s) t:SetTexture("art:" .. s) return true end,
	CAST_BARS = {
		paragon = { 0, 0, 792, 98, bar = { 124, 19, 648, 58 }, ring = { 73, 48, 35 } },
		demon = { 0, 104, 278, 75, bar = { 14, 12, 230, 18 } },
	} }
function ns.MakeMover(anchor) local m = CreateFrame("Frame", nil, anchor) m:Hide() return m end
function ns.MovedPoint(_, o) return o.mx, o.my end
function SetPreviewDummy() end
ns.Cluster = CreateFrame("Frame", nil, UIParent)
ns.Cluster.level = 10
local width = 1595 * 1100 / 1416
local height = width * 201 / 1595
local function box(x0, y0, x1, y1)
	return { x = ((x0 + x1) / 2 / 1595 - 0.5) * width, y = (0.5 - (y0 + y1) / 2 / 201) * height,
		w = (x1 - x0) / 1595 * width, h = (y1 - y0) / 201 * height }
end
function ns.Metrics() return { width = width, height = height, baseY = height / 2, rail = box(336, 96, 1259, 104), levelPlaque = box(761, 28, 803, 70) } end
ns.ExperienceBar = CreateFrame("StatusBar", nil, ns.Cluster)
ns.LevelPlaque = CreateFrame("Frame", nil, ns.Cluster)
''')
load(SRC + '/CastRail.lua')
lua.execute(r'''
local ns = SanctuaryUI
local C = ns.CastRail
C.Init()
local holder = _G.SanctuaryUICastRail
local function Step(dt)
	NOW = NOW + dt
	for _, w in ipairs(ALL) do
		if w.shown and w.scripts.OnUpdate then w.scripts.OnUpdate(w, dt) end
	end
end
local function Run(t) local n = math.floor(t / 0.02) for i = 1, n do Step(0.02) end end
FAILS = 0
local function ok(c, m) if not c then FAILS = FAILS + 1 print("FAIL " .. m) else print("ok   " .. m) end end
-- find pieces
local bar, top, still
for _, w in ipairs(ALL) do
	if w.parent == holder and w.kind == "StatusBar" then bar = w end
end
for _, w in ipairs(ALL) do if w.parent == ns.Cluster and w ~= holder and w.kind == "Frame" and w.ev and not next(w.ev) and w ~= ns.LevelPlaque then top = top or w end end
local texts = {}
for _, w in ipairs(ALL) do if w.kind == "FontString" and w.parent == top then texts[#texts + 1] = w end end
local name, time = texts[1], texts[2]
for _, w in ipairs(ALL) do if w.kind == "Texture" and w.parent == holder then still = w end end
STATE = { holder = holder, bar = bar, top = top, name = name, time = time, still = still }
SNAPS = {}
local medal
for _, w in ipairs(ALL) do if w.parent == top and w.kind == "Frame" then medal = w end end
function SNAP(label)
	local p = name.points[1]
	local tp = time.points[1]
	local frac
	if bar.max and bar.value and bar.max > bar.min then frac = (bar.value - bar.min) / (bar.max - bar.min) end
	local icon
	for _, w in ipairs(ALL) do if w.parent == medal and w.kind == "Texture" and w.tex and tostring(w.tex):find("^icon") then icon = w end end
	SNAPS[#SNAPS + 1] = { label = label, alpha = holder.shown and holder.alpha or 0, xp = ns.ExperienceBar.alpha,
		bar = bar.shown and frac or nil, color = bar.sbcolor, still = still.shown and (still.w / holder.w) or nil,
		stillColor = still.vcolor, stillBlend = still.blend, spark = holder.shown and bar.shown,
		name = top.shown and name.text or nil, nameColor = name.color or name.tc, nx = p[4], ny = p[5], size = name.size,
		time = time.shown and time.text or nil, tx = tp[4], ty = tp[5],
		medal = medal.shown and top.shown, cd = medal.cdStart and ((NOW - medal.cdStart) / medal.cdDur) or nil }
end

-- 1. a cast that lands
CAST = { name = "Flash of Light", icon = "icon:fol", startMS = NOW * 1000, endMS = NOW * 1000 + 1500 }
Fire("UNIT_SPELLCAST_START", "player", "guid1", 19750)
ok(holder.shown and top.shown, "cast shows")
Run(0.2)
ok(holder.alpha == 1 and ns.ExperienceBar.alpha == 0, "XP faded out, cast in (" .. tostring(ns.ExperienceBar.alpha) .. ")")
ok(ns.LevelPlaque.alpha == 0, "level medallion handed over")
Run(0.5)
ok(name.text == "Flash of Light", "name " .. tostring(name.text))
ok(time.text == "0.8", "time left " .. tostring(time.text))
ok(bar.min == CAST.startMS and math.abs((bar.value - bar.min) / (bar.max - bar.min) - 0.467) < 0.02, "fill ~47%")
SNAP("A cast running (Flash of Light, 0.8 s left)")
Run(0.79)
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid1", 19750)
Fire("UNIT_SPELLCAST_STOP", "player", "guid1", 19750)
CAST = nil
RunTimers()
ok(still.shown and still.blend ~= "ADD" and not bar.shown, "flare on landing")
SNAP("It lands: the rail flares")
Run(0.6)
ok(not holder.shown and ns.ExperienceBar.alpha == 1 and ns.LevelPlaque.alpha == 1, "XP back after the flare")

-- 2. interrupted at 60%
CAST = { name = "Frostbolt", icon = "icon:fb", startMS = NOW * 1000, endMS = NOW * 1000 + 2500 }
Fire("UNIT_SPELLCAST_START", "player", "guid2", 116)
Run(1.5)
Fire("UNIT_SPELLCAST_FAILED", "player", "guidOther", 2139) -- a second spell refused: ignored
ok(holder.shown and bar.shown, "another spell's FAILED ignored")
Fire("UNIT_SPELLCAST_INTERRUPTED", "player", "guid2", 116)
Fire("UNIT_SPELLCAST_STOP", "player", "guid2", 116)
CAST = nil
RunTimers()
local w = holder.w
ok(still.shown and math.abs(still.w / w - 0.6) < 0.03 and name.text == "Interrupted", "red at 60% (" .. string.format("%.2f", still.w / w) .. ") " .. tostring(name.text))
SNAP("Interrupted at 60%")
Run(0.3)
ok(holder.alpha == 1, "red holds")
Run(0.8)
ok(not holder.shown, "gone after hold + fade")

-- 3. channel
CAST = { name = "Arcane Missiles", icon = "icon:am", startMS = NOW * 1000, endMS = NOW * 1000 + 3000, channel = true }
Fire("UNIT_SPELLCAST_CHANNEL_START", "player", "guid3", 5143)
Run(1.0)
SNAP("A channel draining (Arcane Missiles)")
ok(bar.max - bar.value < bar.max - bar.min and math.abs((bar.value - bar.min) / (bar.max - bar.min) - 0.667) < 0.02, "channel drains (" .. string.format("%.2f", (bar.value - bar.min) / (bar.max - bar.min)) .. ")")
ok(bar.sbcolor and bar.sbcolor[3] == 1 and bar.sbcolor[1] < 0.7, "channel blue")
Run(2.0)
Fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "guid3", 5143)
CAST = nil
Run(0.6)
ok(not holder.shown, "channel quietly gone")

-- 4. pushback
CAST = { name = "Fireball", icon = "icon:f", startMS = NOW * 1000, endMS = NOW * 1000 + 3000 }
Fire("UNIT_SPELLCAST_START", "player", "guid4", 133)
Run(1)
CAST.endMS = CAST.endMS + 500
Fire("UNIT_SPELLCAST_DELAYED", "player", "guid4", 133)
Run(0.02)
ok(bar.max == CAST.endMS, "pushback moves the end")
Fire("UNIT_SPELLCAST_STOP", "player", "guid4", 133) -- stop without success or interrupt
CAST = nil
RunTimers()
Run(0.6)
ok(not holder.shown, "unexplained stop fades quietly")

-- 5. off
PROFILE.castRail = false
C.ApplySettings()
CAST = { name = "Fireball", icon = "icon:f", startMS = NOW * 1000, endMS = NOW * 1000 + 3000 }
Fire("UNIT_SPELLCAST_START", "player", "guid5", 133)
ok(not holder.shown and ns.ExperienceBar.alpha == 1, "option off: nothing")
PROFILE.castRail = true
CAST = nil

-- 6. preview loops
C.SetPreview(true)
local seen = {}
for i = 1, 600 do Step(0.02); RunTimers(); if name.text then seen[name.text] = true end end
for k in pairs(seen) do print("seen " .. k) end
ok(seen["Flash of Light"] and seen["Frostbolt"] and seen["Interrupted"] and seen["Arcane Missiles"], "preview cycles all three")
C.SetPreview(false)
Run(0.1)
ok(not holder.shown, "preview off hides")
-- 7. a bar of its own
local own = _G.SanctuaryUICastBar
PROFILE.castWhere = "bar"
C.ApplySettings()
CAST = { name = "Fireball", icon = "icon:f", startMS = NOW * 1000, endMS = NOW * 1000 + 2000 }
Fire("UNIT_SPELLCAST_START", "player", "guid7", 133)
Run(0.5)
ok(own.shown and not holder.shown, "own bar: the bar shows, the rail doesn't")
ok(ns.ExperienceBar.alpha == 1 and ns.LevelPlaque.alpha == 1, "own bar: the XP and level stay")
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid7", 133)
CAST = nil
Run(0.7)
ok(not own.shown, "own bar: gone after the flare")
-- 8. both
PROFILE.castWhere = "both"
C.ApplySettings()
CAST = { name = "Fireball", icon = "icon:f", startMS = NOW * 1000, endMS = NOW * 1000 + 2000 }
Fire("UNIT_SPELLCAST_START", "player", "guid8", 133)
Run(0.5)
ok(own.shown and holder.shown and ns.ExperienceBar.alpha == 0, "both: bar and rail, XP faded")
Fire("UNIT_SPELLCAST_INTERRUPTED", "player", "guid8", 133)
CAST = nil
Run(1.2)
ok(not own.shown and not holder.shown and ns.ExperienceBar.alpha == 1, "both: gone after the interrupt")
PROFILE.castWhere = "rail"
C.ApplySettings()
print("FAILS " .. FAILS)
''')
for l in lua.globals().PRINTED.values(): print(l)

# ---- render the snapshots over the real console art
import math
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageChops
A = SRC + '/Art/'
frame = Image.open(A + 'frame.png').convert('RGBA')
xpo = Image.open(A + 'xp-orange.png').convert('RGBA')
xpw = Image.open(A + 'xp-white.png').convert('RGBA')
medal = Image.open(A + 'level-medallion.png').convert('RGBA').crop((5, 4, 125, 124))
mote = Image.open(A + 'mote.png').convert('RGBA')
EXO = SRC + '/Media/exocet.ttf'; SANS = SRC + '/Media/d3-sans.ttf'
WIDTH = 1595 * 1100 / 1416; HEIGHT = WIDTH * 201 / 1595; K = 1595 / WIDTH
X0, X1, Y0, Y1 = 336, 1259, 96, 104
CX0, CX1, CY0, CY1 = 300, 1300, 0, 150
S = 2
BG = (120, 150, 175, 255)
def tint(im, c, a=1):
    l = im.convert('L'); al = im.getchannel('A')
    return Image.merge('RGBA', [l.point(lambda v, k=k: v * k) for k in c[:3]] + [al.point(lambda v: v * a)])
def add(canvas, im, pos):
    layer = Image.new('RGBA', canvas.size, (0, 0, 0, 0)); layer.alpha_composite(im, pos)
    rgb = Image.composite(layer.convert('RGB'), Image.new('RGB', canvas.size), layer.getchannel('A'))
    out = ImageChops.add(canvas.convert('RGB'), rgb)
    canvas.paste(Image.merge('RGBA', (*out.split(), canvas.getchannel('A'))))
def sx(x): return (x / WIDTH + 0.5) * 1595
def sy(y): return 201 - y / HEIGHT * 201
def panel(sn):
    W, H = CX1 - CX0, CY1 - CY0
    c = Image.new('RGBA', (W, H), BG)
    rx, ry, rw, rh = X0 - CX0, Y0 - CY0, X1 - X0, Y1 - Y0
    a = sn['alpha']
    xpim = xpo.resize((int(rw * 0.62), rh)); xpim.putalpha(xpim.getchannel('A').point(lambda v: v * sn['xp']))
    c.alpha_composite(xpim, (rx, ry))
    head = None
    if sn['bar'] is not None:
        w = max(1, int(rw * sn['bar'])); col = sn['color']
        c.alpha_composite(tint(xpw.resize((w, rh)), col, a), (rx, ry)); head = rx + w
    if sn['still'] is not None:
        w = rw if sn['stillBlend'] == 'BLEND' and sn['label'].startswith('It lands') else max(1, int(rw * sn['still'])); im = tint(xpw.resize((w, rh)), sn['stillColor'], a)
        if sn['stillBlend'] == 'ADD':
            add(c, im, (rx, ry))
        else:
            c.alpha_composite(im, (rx, ry))
    c.alpha_composite(frame.crop((CX0, CY0, CX1, CY1)))
    if head is not None and sn['spark']:
        hc = sn['color']; sp = tint(mote.resize((int(rh * 7), int(rh * 3.2))), (1, 0.86, 0.6) if hc[2] < 0.5 else hc, 0.95 * a)
        add(c, sp, (int(head - sp.width / 2), int(ry + rh / 2 - sp.height / 2)))
        co = tint(mote.resize((int(rh * 2.6), int(rh * 2))), (1, 1, 0.92), a)
        add(c, co, (int(head - co.width / 2), int(ry + rh / 2 - co.height / 2)))
    mx, my, ms = 761 - CX0, 28 - CY0, 42
    lvl = medal.resize((ms, ms), Image.LANCZOS)
    if sn['medal']:
        disc = lvl.copy()
        inner = int(ms * 0.78)
        ic = Image.new('RGBA', (inner, inner), (90, 60, 20, 255))
        d = ImageDraw.Draw(ic)
        for i in range(12):
            t = i * math.pi / 6; cc = inner / 2
            d.line((cc, cc, cc + math.cos(t) * inner, cc + math.sin(t) * inner), fill=(255, 220, 140, 255), width=2)
        ic = ic.filter(ImageFilter.GaussianBlur(1))
        if sn['cd'] is not None:
            dark = Image.new('RGBA', (inner, inner), (0, 0, 0, 0))
            ImageDraw.Draw(dark).pieslice((0, 0, inner, inner), -90 + 360 * sn['cd'], 270, fill=(0, 0, 0, 153))
            ic.alpha_composite(dark)
        m = Image.new('L', (inner, inner), 0); ImageDraw.Draw(m).ellipse((0, 0, inner - 1, inner - 1), fill=int(255 * a))
        disc.paste(ic, ((ms - inner) // 2, (ms - inner) // 2), m)
        c.alpha_composite(disc, (mx, my))
    c = c.resize((W * S, H * S), Image.LANCZOS)
    d = ImageDraw.Draw(c)
    if not sn['medal']:
        pass
    size = sn['size'] * K * S
    if sn['name']:
        nc = sn['nameColor']; col = tuple(int(v * 255) for v in (nc[1], nc[2], nc[3])) if nc else (250, 220, 150)
        d.text(((sx(sn['nx']) - CX0) * S, (sy(sn['ny']) - CY0) * S), sn['name'], font=ImageFont.truetype(EXO, int(size)), fill=col + (int(255 * a),), anchor='rd', stroke_width=2, stroke_fill=(0, 0, 0))
    if sn['time']:
        d.text(((sx(sn['tx']) - CX0) * S, (sy(sn['ty']) - CY0) * S), sn['time'], font=ImageFont.truetype(SANS, int(size)), fill=(235, 235, 235), anchor='ld', stroke_width=2, stroke_fill=(0, 0, 0))
    return c
snaps = [dict(v.items()) for v in lua.globals().SNAPS.values()]
for sn in snaps:
    for k in ('color', 'stillColor', 'nameColor'):
        if sn.get(k) is not None: sn[k] = [sn[k][i] for i in (1, 2, 3, 4) if sn[k][i] is not None]
    for k in ('bar', 'still', 'cd', 'name', 'time', 'stillBlend', 'medal', 'spark'):
        sn.setdefault(k, None)
# nameColor table is 1-indexed above; normalise to (r,g,b)
for sn in snaps:
    if sn['nameColor']: sn['nameColor'] = [None] + sn['nameColor']
f = ImageFont.truetype(SANS, 26)
ph, pw = (CY1 - CY0) * S, (CX1 - CX0) * S
out = Image.new('RGBA', (pw, 20 + len(snaps) * (ph + 46)), BG); d = ImageDraw.Draw(out); y = 10
for sn in snaps:
    d.text((20, y + 8), sn['label'] + '  (real CastRail.lua state, mock client)', font=f, fill=(20, 25, 35)); y += 46
    out.alpha_composite(panel(sn), (0, y)); y += ph
out.convert('RGB').save(sys.argv[1] if len(sys.argv) > 1 else 'built.png')
print('rendered', len(snaps))
