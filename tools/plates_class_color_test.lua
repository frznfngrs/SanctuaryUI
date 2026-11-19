-- Run from the repo root: lua5.1 tools/plates_class_color_test.lua
-- Enemy player nameplates: health (and the name) use the class colour even when
-- UnitClass hands back a secret class token, which this client does in combat.
local SECRET = {}
SanctuaryUI = {}
function SanctuaryUI.Secret(v) return v == SECRET end
local plates = {
	classFill = true,
	healthColor = "d3",
	threatFill = false,
	showLevel = false,
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
SanctuaryUI.Fonts = { Set = function() end }
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
function UnitClass(unit)
	local u = units[unit]
	return u and u.className, u and u.class
end
function UnitReaction() return 2 end
function UnitName(unit) return units[unit] and units[unit].name end
function UnitLevel() return 60 end

RAID_CLASS_COLORS = {
	WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
}
local MAGE = { r = 0.41, g = 0.80, b = 0.94 }
C_ClassColor = {
	GetClassColor = function(class)
		if class == SECRET then return MAGE end
	end,
}

local f = assert(io.open(arg[1] or "SanctuaryUI/Plates.lua"))
local src = f:read("*a")
f:close()
src = src .. "\nP._t = { UpdateFill = UpdateFill, UpdateName = UpdateName }\n"
assert(loadstring(src, "Plates.lua"))()
local T = SanctuaryUI.Plates._t

local fails = 0
local function check(label, got, want)
	local ok = got == want
	if not ok then fails = fails + 1 end
	print((ok and "ok   " or "FAIL ") .. label .. "  got " .. tostring(got) .. " want " .. tostring(want))
end

local function bar()
	local b = {}
	function b:SetStatusBarTexture(tex) self.tex = tex end
	function b:SetStatusBarColor(r, g, b_, a) self.r, self.g, self.b, self.a = r, g, b_, a end
	return b
end

local function text()
	local t = {}
	function t:SetText() end
	function t:SetTextColor(r, g, b) self.r, self.g, self.b = r, g, b end
	return t
end

local function plate(unit)
	return {
		unit = unit,
		rank = "normal",
		health = bar(),
		name = text(),
		level = text(),
	}
end

units.nameplate1 = { player = true, class = SECRET, className = "Mage", name = "Jaina" }
local enemy = plate("nameplate1")
T.UpdateFill(enemy)
check("secret class: white fill texture", enemy.health.tex, "WHITE")
check("secret class: health r", enemy.health.r, MAGE.r)
check("secret class: health g", enemy.health.g, MAGE.g)
check("secret class: health b", enemy.health.b, MAGE.b)
T.UpdateName(enemy)
check("secret class: name r", enemy.name.r, MAGE.r)
check("secret class: name g", enemy.name.g, MAGE.g)
check("secret class: name b", enemy.name.b, MAGE.b)

units.nameplate2 = { player = true, class = "WARRIOR", className = "Warrior", name = "Varian" }
local plain = plate("nameplate2")
T.UpdateFill(plain)
check("plain class: health r", plain.health.r, 0.78)
check("plain class: white fill texture", plain.health.tex, "WHITE")

plates.classFill = false
local off = plate("nameplate1")
T.UpdateFill(off)
check("class colours off: red texture", off.health.tex, "RED")
plates.classFill = true

units.nameplate3 = { player = false, class = "WARRIOR", name = "Wolf" }
local npc = plate("nameplate3")
T.UpdateFill(npc)
check("npc: red texture", npc.health.tex, "RED")

if fails > 0 then
	print(fails .. " failed")
	os.exit(1)
end
print("all passed")
