"""Offline look at the cast bar of its own (CastRail.lua): the real Lua in lupa against wow.lua,
drawn with render.py, mid-cast in both looks (Paragon and Demon).

Run: PYTHONPATH=~/.cache/sanctuary-preview-py ~/.venv/bin/python tools/ui_preview/castbar_preview.py [out_dir]
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "shots")
sys.argv = [sys.argv[0], OUT]
src = open(os.path.join(HERE, "render.py")).read()
exec(compile(src[:src.index("def errors():")], "render.py", "exec"))
os.makedirs(OUT, exist_ok=True)

lua.execute(r'''
local ns = SanctuaryUI
local proto = getmetatable(UIParent)
local old = proto.__index
local function Fit(self)
	local f = self.fill
	if not f then return end
	local lo, hi, v = self.min or 0, self.max or 1, self.value or 0
	local frac = (hi > lo) and math.max(0, math.min(1, (v - lo) / (hi - lo))) or 0
	f.points = { { "TOPLEFT", self, "TOPLEFT", 0, 0 } }
	f.w, f.h = math.max(0.01, (self.w or 0) * frac), self.h or 0
end
local extra = {
	SetStatusBarTexture = function(self, p) self.fill = self.fill or self:CreateTexture(nil, "ARTWORK") self.fill.tex = p Fit(self) end,
	-- As the game: no fill texture until SetStatusBarTexture has given it one.
	GetStatusBarTexture = function(self) return self.fill end,
	SetStatusBarColor = function(self, r, g, b, a) if self.fill then self.fill.vcolor = { r, g, b, a or 1 } end end,
	SetMinMaxValues = function(self, a, b) self.min, self.max = a, b Fit(self) end,
	GetMinMaxValues = function(self) return self.min, self.max end,
	SetValue = function(self, v) self.value = v Fit(self) end,
	GetValue = function(self) return self.value end,
	SetSize = function(self, w, h) self.w, self.h = w, h Fit(self) end,
	SetAllPoints = function(self, rel) rel = rel or self.parent self.points = { { "TOPLEFT", rel, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", rel, "BOTTOMRIGHT", 0, 0 } } if rel and rel.w then self.w, self.h = rel.w, rel.h end Fit(self) end,
	SetFormattedText = function(self, f, ...) self.text = string.format(f, ...) end,
	CreateMaskTexture = function(self) return self:CreateTexture() end,
	AddMaskTexture = function() end,
	SetCooldown = function() end,
	IsShown = function(self) return self.shown end,
	GetEffectiveScale = function() return 1 end,
}
proto.__index = function(t, k)
	if extra[k] then return extra[k] end
	return old(t, k)
end
ns.Fonts = ns.Fonts or {}
ns.Fonts.Set = function(fs, role, size) fs:SetFont(role, size) end
ns.Secret = function() return false end
ns.Or = function(v, d) if v == nil then return d end return v end
function ns.MakeMover(anchor) local m = CreateFrame("Frame", nil, anchor) m:Hide() return m end
function ns.MovedPoint(_, o) return o.mx, o.my end
ns.Cluster = CreateFrame("Frame", "SanctuaryUICluster", UIParent)
ns.Cluster:SetSize(1100, 140)
ns.Cluster:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 0)
ns.LEVEL = { rail = 8, console = 9 }
ns.TEX_W = 1595
local width = 1595 * 1100 / 1416
local height = width * 201 / 1595
local function box(x0, y0, x1, y1)
	return { x = ((x0 + x1) / 2 / 1595 - 0.5) * width, y = (0.5 - (y0 + y1) / 2 / 201) * height,
		w = (x1 - x0) / 1595 * width, h = (y1 - y0) / 201 * height }
end
function ns.Metrics() return { width = width, height = height, baseY = height / 2, rail = box(336, 96, 1259, 104), levelPlaque = box(761, 28, 803, 70) } end
ns.ExperienceBar = CreateFrame("StatusBar", nil, ns.Cluster)
ns.LevelPlaque = CreateFrame("Frame", nil, ns.Cluster)
NOW = 100
function GetTime() return NOW end
function C_Timer.After() end
''')
load(SRC + "/CastRail.lua")
lua.execute('''
PROFILE.castWhere = "bar"
SanctuaryUI.CastRail.Init()
''')


def shot(name, style):
    lua.execute(f'''
    PROFILE.castBar.style = "{style}"
    local C = SanctuaryUI.CastRail
    C.ApplySettings()
    C.preview = nil
    C.SetPreview(true)
    for i = 1, 40 do NOW = NOW + 0.02 for _, w in ipairs(ALL) do if w.shown and w.scripts.OnUpdate then w.scripts.OnUpdate(w, 0.02) end end end
    ''')
    draw(os.path.join(OUT, name), "SanctuaryUICastBar", K=2.0)
    print("wrote", name)


shot("castbar-paragon.png", "paragon")
shot("castbar-demon.png", "demon")

# Every glow pinned to something: a point on nil lands on the screen's edge in the game.
lua.execute('''
local bad = 0
for _, w in ipairs(ALL) do
	local p = w.points and w.points[1]
	local inside = false
	local o = w
	while o do if o.name == "SanctuaryUICastBar" then inside = true break end o = o.parent end
	if inside and w.kind == "Texture" and p and p[2] == nil then bad = bad + 1 end
end
assert(bad == 0, bad .. " cast bar textures pinned to nothing")
''')
print("pins ok")

