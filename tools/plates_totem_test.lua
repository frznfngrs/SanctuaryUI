-- Run from the repo root: lua5.1 tools/plates_totem_test.lua
-- Enemy totems are their own small plate (icon, name, element-coloured bar), not a player plate.
local SECRET = {}
SanctuaryUI = {}
function SanctuaryUI.Secret(v) return v == SECRET end
local plates = {
	classFill = true,
	healthColor = "d3",
	threatFill = false,
	showLevel = false,
	showTotems = true,
	nameSize = 10,
	nameFont = "d3",
	nameOutline = "outline",
}
SanctuaryUI.DB = function() return { plates = plates } end
SanctuaryUI.Art = {
	Path = function(slot)
		if slot == "unitFill" then return "RED" end
		if slot == "unitFillWhite" then return "WHITE" end
	end,
}
SanctuaryUI.Fonts = { Set = function(fs, _, size) fs.fontSize = size end }
SanctuaryUI.Totem = { ELEMENTS = {
	{ totems = { { 8071, "Stoneskin Totem" } } },
	{ totems = { { 3599, "Searing Totem" } } },
	{ totems = { { 5394, "Healing Stream Totem" } } },
	{ totems = { { 8177, "Grounding Totem" } } },
} }
StaticPopupDialogs = {}
function CreateFrame()
	local f = {}
	function f:SetScript() end
	function f:RegisterEvent() end
	function f:SetSize() end
	function f:SetPoint() end
	function f:Hide() end
	function f:Show() end
	return f
end

local units = {}
function UnitIsPlayer(unit) return units[unit] and units[unit].player end
function UnitIsTapDenied() return false end
function UnitCreatureType(unit) return units[unit] and units[unit].creature end
function UnitClass(unit)
	local u = units[unit]
	return u and u.className, u and u.class
end
function UnitReaction() return 2 end
function UnitName(unit) return units[unit] and units[unit].name end
function UnitLevel() return 60 end

RAID_CLASS_COLORS = { SHAMAN = { r = 0, g = 0.44, b = 0.87 } }
C_ClassColor = { GetClassColor = function() end }

local f = assert(io.open(arg[1] or "SanctuaryUI/Plates.lua"))
local src = f:read("*a")
f:close()
src = src .. "\nP._t = { UpdateFill = UpdateFill, UpdateName = UpdateName, Layout = Layout, IsTotem = P.IsTotem, TotemOf = P.TotemOf, MarkTotem = MarkTotem }\n"
assert(loadstring(src, "Plates.lua"))()
local T = SanctuaryUI.Plates._t

local fails = 0
local function check(label, got, want)
	local ok = got == want
	if not ok then fails = fails + 1 end
	print((ok and "ok   " or "FAIL ") .. label .. "  got " .. tostring(got) .. " want " .. tostring(want))
end

local function widget()
	local w = { shown = true }
	setmetatable(w, { __index = function(self, key)
		return function(s, a, b, c)
			if key == "SetSize" then s.w, s.h = a, b
			elseif key == "SetWidth" then s.w = a
			elseif key == "Hide" then s.shown = false
			elseif key == "Show" then s.shown = true
			elseif key == "SetTexture" then s.tex = a
			elseif key == "SetStatusBarTexture" then s.barTex = a
			elseif key == "SetStatusBarColor" then s.r, s.g, s.b = a, b, c
			elseif key == "SetText" then s.text = a
			end
		end
	end })
	return w
end

local function plate(unit)
	local cast = widget()
	local icon = widget()
	icon.shown = false
	local left, right = widget(), widget()
	left.edge, right.edge = widget(), widget()
	return {
		unit = unit,
		rank = "normal",
		root = widget(),
		health = widget(),
		name = widget(),
		level = widget(),
		slot = widget(),
		trail = widget(),
		execute = widget(),
		flash = widget(),
		art = widget(),
		thinEdge = widget(),
		tick = widget(),
		threat = widget(),
		pct = widget(),
		quest = widget(),
		guild = widget(),
		raid = widget(),
		cast = cast,
		icon = icon,
		left = left,
		right = right,
	}
end

local info = T.TotemOf("Searing Totem III")
check("ranked searing totem is fire", info and info.element, 2)
check("creature type Totem", T.IsTotem("nameplate1", SECRET), false) -- name secret, type unset
units.nameplate1 = { creature = "Totem", name = SECRET, player = true, class = "SHAMAN" }
check("secret name, creature type Totem", T.IsTotem("nameplate1", SECRET), true)
check("a player name is not a totem", T.IsTotem("nameplate2", "Varian"), false)

units.searing = { player = true, class = "SHAMAN", className = "Shaman", name = "Searing Totem III", creature = "Totem" }
local enemy = plate("searing")
T.MarkTotem(enemy)
check("marked as a totem", enemy.totem, true)
check("totem plate width", enemy.root.w, 72)
check("totem icon shown", enemy.icon.shown, true)
check("totem name size", enemy.name.fontSize, 9)
T.UpdateFill(enemy)
check("totem bar uses the white fill", enemy.health.barTex, "WHITE")
check("totem bar is fire, not shaman", enemy.health.r, 1)
check("totem bar fire g", enemy.health.g, 0.5)
check("totem bar fire b", enemy.health.b, 0.15)
T.UpdateName(enemy)
check("totem name is not shaman blue", enemy.name.r ~= 0, true)

plates.showTotems = false
local hidden = plate("searing")
T.MarkTotem(hidden)
check("show totems off hides the plate", hidden.root.shown, false)
plates.showTotems = true

units.player = { player = true, class = "SHAMAN", name = "Varian" }
local shaman = plate("player")
T.MarkTotem(shaman)
check("player is not marked a totem", shaman.totem or false, false)
T.UpdateFill(shaman)
check("player health stays class coloured", shaman.health.r, 0)

if fails > 0 then
	print(fails .. " failed")
	os.exit(1)
end
print("all passed")
