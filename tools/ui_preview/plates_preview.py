"""Offline check of the nameplates (Plates.lua): the real Lua in lupa against wow.lua plus a few
nameplate stand-ins. Draws the preview pull in both looks with the real art, then runs a mock pull
through the real event path (plates added, a cast at you, an interrupt, target change, a friend,
a death) and asserts what each plate shows.

Run: PYTHONPATH=~/.cache/sanctuary-preview-py ~/.venv/bin/python tools/ui_preview/plates_preview.py [out_dir]
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
	SetFormattedText = function(self, f, ...) self.text = string.format(f, ...) end,
	-- As the game: a FontString takes no text before it has a font.
	SetText = function(self, t)
		if self.kind == "FontString" and not self.font then error("FontString:SetText(): Font not set", 2) end
		return old(self, "SetText")(self, t)
	end,
	SetAlphaFromBoolean = function(self, b, t, f) self.alpha = b and t or f end,
	GetAlpha = function(self) return self.alpha or 1 end,
	IsShown = function(self) return self.shown end,
	GetChildren = function(self)
		local list = {}
		for _, w in ipairs(ALL) do if w.parent == self and w.kind ~= "Texture" and w.kind ~= "FontString" then list[#list + 1] = w end end
		return unpack(list)
	end,
	RegisterUnitEvent = function(self, e) self.ev[e] = true end,
	GetParent = function(self) return self.parent end,
	SetParent = function(self, p) self.parent = p end,
	GetEffectiveScale = function(self) local s, w = 1, self while w do s = s * (w.scale or 1) w = w.parent end return s end,
	GetCenter = function(self)
		local w = self
		while w do
			if w.isNamePlate then error("Frame:GetCenter(): Can't measure restricted regions", 2) end
			w = w.parent
		end
		return 960, 540
	end,
}
proto.__index = function(t, k)
	if extra[k] then return extra[k] end
	return old(t, k)
end
ns.Fonts = ns.Fonts or {}
ns.Fonts.Set = function(fs, role, size) fs:SetFont(role, size) end
ns.Fonts.Path = function(role) return role end
ns.Secret = function() return false end
ns.Or = function(v, d) if v == nil then return d end return v end
ns.LogError = function(_, m) print("LOGERR " .. m) end
PROFILE.plates = PROFILE.plates
function SetRaidTargetIconTexture(t, i) t.tex = "raid" .. i end
function UnitExists(u) return UNITS[u] ~= nil end
YOU, INTERRUPTED = "You", "Interrupted"
''')
load(SRC + "/Plates.lua")


def shot(name, look):
    lua.execute(f'''
    PROFILE.plates.look = "{look}"
    local P = SanctuaryUI.Plates
    for _, p in ipairs(P.objs) do end
    P.preview = true
    P.DrawPreview()
    local tick = _G.SanctuaryUIPlatesPreview.scripts.OnUpdate
    for i = 1, 60 do tick(nil, 0.02) end
    -- What the game wouldn't draw: frames and textures at alpha 0.
    HIDDEN = {{}}
    for _, w in ipairs(ALL) do
        if w.shown and w.alpha == 0 then w.shown = false HIDDEN[#HIDDEN + 1] = w end
    end
    ''')
    draw(os.path.join(OUT, name), "SanctuaryUIPlatesPreview", K=2.0)
    lua.execute("for _, w in ipairs(HIDDEN) do w.shown = true end")
    print("wrote", name)


shot("plates-framed.png", "framed")
shot("plates-thin.png", "thin")
lua.execute('''
local o = PROFILE.plates
o.namePos, o.healthColor, o.healthRGB, o.barHeight, o.nameOutline, o.nameColor = "inside", "custom", { 0.55, 0.1, 0.7 }, 14, "none", "reaction"
''')
shot("plates-options.png", "framed")
lua.execute('''
local o = PROFILE.plates
o.namePos, o.healthColor, o.barHeight, o.nameOutline, o.nameColor = "above", "d3", 9, "outline", "rank"
''')

# ---- the real event path, against stand-in units and plates
lua.execute(r'''
local ns = SanctuaryUI
local P = ns.Plates
PROFILE.plates.look = "framed"
_G.SanctuaryUIPlatesPreview:Hide()
P.preview = nil
UNITS = {
	nameplate1 = { name = "Defias Pillager", level = 18, c = "normal", hp = 800, max = 1000, reaction = 2 },
	nameplate2 = { name = "Sneed", level = 20, c = "elite", hp = 3000, max = 4000, reaction = 2 },
	nameplate3 = { name = "Stormwind Guard", level = 55, c = "elite", hp = 5000, max = 5000, reaction = 5 },
	player = {},
}
TARGET = nil
local plates = {}
local function PlateFor(u)
	if not UNITS[u] or u == "player" then return nil end
	local plate = plates[u]
	if not plate then
		plate = CreateFrame("Frame", nil, UIParent)
		plate.isNamePlate = true
		plate.UnitFrame = CreateFrame("Frame", nil, plate)
		plate.UnitFrame.SoftTargetFrame = CreateFrame("Frame", nil, plate.UnitFrame)
		plate.namePlateUnitToken = u
		plates[u] = plate
	end
	return plate
end
function SetUnitCursorTexture(t, token) t.tex = "cursor:" .. token return true end
C_NamePlate = {
	GetNamePlateForUnit = function(u)
		if u == "target" then return TARGET and plates[TARGET] end
		if u == "softenemy" then return SOFTENEMY and plates[SOFTENEMY] end
		if u == "softfriend" or u == "softinteract" then return nil end
		return PlateFor(u)
	end,
	GetNamePlates = function() return {} end,
}
function UnitName(u) return UNITS[u] and UNITS[u].name end
function UnitLevel(u) return UNITS[u] and UNITS[u].level end
function UnitClassification(u) return UNITS[u] and UNITS[u].c end
function UnitReaction(u) return UNITS[u] and UNITS[u].reaction end
function UnitHealth(u) return UNITS[u] and UNITS[u].hp end
function UnitHealthMax(u) return UNITS[u] and UNITS[u].max end
function UnitIsPlayer() return false end
function UnitIsTapDenied() return false end
function UnitIsDead(u) return UNITS[u] and UNITS[u].dead or false end
function UnitThreatSituation(_, u) return UNITS[u] and UNITS[u].threat or nil end
function UnitAffectingCombat(u) return u ~= "nameplate3" end
function GetGuildInfo() return nil end
function GetRaidTargetIndex() return nil end
function UnitIsUnit(a, b) return a == "nameplate1target" and b == "player" end
function UnitSpellTargetName(u) return u == "nameplate2" and "Brakka" or "Tester" end
CASTS = {}
function UnitCastingInfo(u) local c = CASTS[u] if c then return c.name, "", 136243, 1000, 3000, false, "g", c.locked or false, 133 end end
function UnitChannelInfo() end
function GetPlayerInfoByGUID(g) if g == "Player-1" then return "Warrior", "WARRIOR", "Human", "Human", 0, "Kickz", "" end end
function GetTime() return 100 end
C_TooltipInfo = { GetUnit = function(u)
	if u == "nameplate1" then return { lines = { { type = 8, leftText = "Defias Pillager slain: 3/10" } } } end
	if u == "nameplate3" then return { lines = { { leftText = "Stormwind Guard" }, { leftText = "Warrior Trainer" }, { leftText = "Level 55 Humanoid" } } } end
	if u == "nameplate4" then return { lines = { { leftText = "Caretaker Kalvan" }, { leftText = "Level 20" }, { leftText = "Darnassus" }, { leftText = "PvP" } } } end
	return { lines = {} }
end }
Enum = Enum or {}
Enum.TooltipDataLineType = { QuestObjective = 8 }
FAILS = 0
local function ok(c, m) if not c then FAILS = FAILS + 1 print("FAIL " .. m) else print("ok   " .. m) end end

P.inited = nil
P.Init()
Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
Fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
Fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
local p1, p2 = P.byUnit.nameplate1, P.byUnit.nameplate2
ok(p1 and p1.root.shown and p1.name.text == "Defias Pillager", "enemy plate shows its name")
ok(not plates.nameplate1.UnitFrame.shown, "the game's own plate hidden")
local p3 = P.byUnit.nameplate3
ok(p3 and p3.friend and p3.name.text == "Stormwind Guard" and not plates.nameplate3.UnitFrame.shown, "a friend: our name-only plate")
ok(p3.guild.text == "<Warrior Trainer>\nLevel 55" and not p3.art.shown and p3.cast.shown == false, "friend NPC: its title under the name, no frame, no cast bar (" .. tostring(p3.guild.text) .. ")")
UNITS.nameplate4 = { name = "Caretaker Kalvan", level = 20, c = "normal", hp = 1, max = 1, reaction = 5 }
Fire("NAME_PLATE_UNIT_ADDED", "nameplate4")
ok(P.byUnit.nameplate4.guild.text == "Level 20 · Darnassus", "an NPC with no title: level and faction (" .. tostring(P.byUnit.nameplate4.guild.text) .. ")")
PROFILE.plates.friendlyDetails = false
Fire("NAME_PLATE_UNIT_REMOVED", "nameplate4")
Fire("NAME_PLATE_UNIT_ADDED", "nameplate4")
ok(P.byUnit.nameplate4.guild.text == "", "level and faction off: nothing")
PROFILE.plates.friendlyDetails = true
ok(p3.health.alpha == 0, "friend at full health, out of combat: no strip")
UNITS.nameplate3.hp = 2500
Fire("UNIT_HEALTH", "nameplate3")
ok(p3.health.alpha == 1, "friend hurt: the strip shows")
ok(p2.rank == "elite" and math.abs(p2.name.color[3] - 1) < 0.01, "elite: blue name")
ok(p1.health.value == 800 and p1.health.max == 1000, "health set")
local soft = plates.nameplate1.UnitFrame.SoftTargetFrame
ok(soft.alpha == 0, "the game's soft-target icon faded on our plate")
SOFTENEMY = "nameplate1"
Fire("PLAYER_SOFT_ENEMY_CHANGED")
ok(p1.soft.shown and p1.soft.points[1][2] == p1.level and p1.soft.tex == "cursor:softenemy", "our soft-target icon beside the level")
P.SoftReport() -- runs without erroring
SOFTENEMY = nil
Fire("PLAYER_SOFT_ENEMY_CHANGED")
ok(not p1.soft.shown, "and gone when the soft target moves off")
ok(p1.quest.shown and not p2.quest.shown, "quest mob marked")
-- Questie's icon on nameplate2: a child of the game's plate, pinned at Questie's offset
local qf = CreateFrame("Frame", nil, plates.nameplate2)
qf.Icon, qf.lastIcon = qf:CreateTexture(), "bag"
qf:SetPoint("LEFT", -16, -10)
Fire("NAME_PLATE_UNIT_REMOVED", "nameplate2")
Fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
p2 = P.byUnit.nameplate2
RunTimers()
ok(qf.points[1][1] == "LEFT" and qf.points[1][2] == p2.quest and #qf.points == 1, "Questie's icon moved to the end of our name row")
ok(p2.questie and not p2.quest.shown, "our ! steps aside for it")
-- a cast at you
CASTS.nameplate1 = { name = "Fireball" }
Fire("UNIT_SPELLCAST_START", "nameplate1", "g1", 133)
ok(p1.cast.shown and p1.cast.text.text == "Fireball" and p1.cast.you.alpha == 1 and p1.cast.who.alpha == 0, "cast at you: » YOU")
CASTS.nameplate2 = { name = "Frost Armor", locked = true }
Fire("UNIT_SPELLCAST_START", "nameplate2", "g2", 168)
ok(p2.cast.you.alpha == 0 and p2.cast.who.text == "» Brakka" and p2.cast.who.alpha == 1, "cast at someone else: their name")
ok(p2.cast.lock.alpha == 1 and p2.cast.grey.alpha == 1, "can't be interrupted: lock and grey")
Fire("UNIT_SPELLCAST_INTERRUPTED", "nameplate1", "g1", 133, "Player-1")
ok(p1.cast.shown and (p1.cast.text.text or ""):find("Kickz"), "interrupted by Kickz: " .. tostring(p1.cast.text.text))
Fire("UNIT_SPELLCAST_STOP", "nameplate1", "g1", 133)
ok(p1.cast.shown, "held after the stop event")
-- damage
UNITS.nameplate1.hp = 150
Fire("UNIT_HEALTH", "nameplate1")
ok(p1.health.value == 150 and p1.trail.value == 800, "hit: the trail holds")
RunTimers()
ok(p1.trail.value == 150, "then drains")
ok(p1.execute.alpha == 1, "15%: execute")
-- threat
UNITS.nameplate2.threat = 3
Fire("UNIT_THREAT_LIST_UPDATE", "nameplate2")
ok(p2.threat.alpha > 0.5 and p2.threat.vcolor[1] == 1 and p2.threat.vcolor[2] < 0.3, "aggro on you: red")
-- target
TARGET = "nameplate2"
UNITS.target = UNITS.nameplate2
Fire("PLAYER_TARGET_CHANGED")
ok(p2.isTarget and p2.root.scale > 1.1 and p2.left.shown and p2.pct.text == "75%", "target: bigger, marked, percent " .. tostring(p2.pct.text))
ok(not p1.isTarget and p1.root.scale == 1 and p1.pct.text == "", "others plain")
-- death
UNITS.nameplate1.dead = true
Fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
ok(P.byUnit.nameplate1 == nil and not p1.root.shown, "removed")
local burst = false
for _, w in ipairs(ALL) do if w.scripts.OnUpdate and w.t ~= nil and w.shown then burst = true end end
ok(burst, "death burst")
-- with friendly plates set to the game's own, the plate comes back as the game's
PROFILE.plates.friendly = "off"
UNITS.nameplate1 = { name = "Guard", level = 55, c = "elite", hp = 1, max = 1, reaction = 5 }
Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
plates.nameplate1.UnitFrame:Show()
ok(P.byUnit.nameplate1 == nil and plates.nameplate1.UnitFrame.shown and plates.nameplate1.UnitFrame:GetAlpha() == 1, "friendly off: the game's plate")
PROFILE.plates.friendly = "names"
print("FAILS " .. FAILS)
''')
for l in lua.globals().PRINTED.values():
    if l.startswith(("ok", "FAIL", "LOGERR")):
        print(l)
