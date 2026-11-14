-- A WoW API stand-in that records enough to lay out and draw frames offline (render.py).
ERRORS, PRINTED, ALL = {}, {}, {}
local W = {}
W.__index = function(t, k)
	local m = W[k]
	if m then return m end
	if type(k) == "string" and k:match("^%u") then return function() end end
end
local LAYERS = { BACKGROUND = 0, BORDER = 1, ARTWORK = 2, OVERLAY = 3, HIGHLIGHT = 4 }
local function new(kind, parent, name)
	local w = setmetatable({ kind = kind, parent = parent, shown = true, w = 0, h = 0, scale = 1, scripts = {}, points = {},
		name = name, idx = #ALL + 1, alpha = 1, ev = {} }, W)
	ALL[#ALL + 1] = w
	return w
end
function W:SetSize(w, h) self.w, self.h = w, h end
function W:SetWidth(w) self.w = w end
function W:SetHeight(h) self.h = h end
function W:GetWidth() return self.w end
function W:GetHeight() return self.h end
function W:Show() local was = self.shown self.shown = true if not was and self.scripts.OnShow then self.scripts.OnShow(self) end end
function W:Hide() local was = self.shown self.shown = false if was and self.scripts.OnHide then self.scripts.OnHide(self) end end
function W:IsShown() return self.shown end
function W:SetShown(v) if v then self:Show() else self:Hide() end end
function W:SetText(t, extra)
	if extra ~= nil then ERRORS[#ERRORS + 1] = "SetText with a second argument: " .. tostring(t) end
	self.text = t ~= nil and tostring(t) or nil
end
function W:GetText() return self.text end
function W:SetFont(path, size) self.font, self.size = path, size return true end
function W:GetFont() return self.font, self.size end
function W:SetTextColor(r, g, b, a)
	if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then ERRORS[#ERRORS + 1] = "SetTextColor bad" end
	self.color = { r, g, b, a or 1 }
end
function W:SetJustifyH(j) self.justify = j end
function W:SetWordWrap(v) self.wrap = v end
function W:GetStringWidth()
	local plain = (self.text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	if MEASURE then return MEASURE(self.font or "body", self.size or 12, plain) end
	return #plain * (self.size or 12) * 0.5
end
function W:GetStringHeight() return (self.size or 12) * 1.2 end
function W:SetPoint(p, a, b, c, d)
	local rel, rp, x, y
	if type(a) == "number" or a == nil then rel, rp, x, y = self.parent, p, a or 0, b or 0
	elseif type(b) == "number" or b == nil then rel, rp, x, y = a, p, b or 0, c or 0
	else rel, rp, x, y = a, b, c or 0, d or 0 end
	for i, pt in ipairs(self.points) do if pt[1] == p then table.remove(self.points, i) break end end
	self.points[#self.points + 1] = { p, rel, rp, x, y }
end
function W:SetAllPoints(rel)
	rel = rel or self.parent
	self.points = { { "TOPLEFT", rel, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", rel, "BOTTOMRIGHT", 0, 0 } }
end
function W:GetPoint(i) local p = self.points[i or 1] if p then return p[1], p[2], p[3], p[4], p[5] end end
function W:ClearAllPoints() self.points = {} end
function W:SetScale(s) self.scale = s end
function W:GetScale() return self.scale end
function W:GetEffectiveScale() local s, w = 1, self while w do s = s * (w.scale or 1) w = w.parent end return s end
function W:SetAlpha(a) self.alpha = a end
function W:SetScript(k, f) self.scripts[k] = f end
function W:GetScript(k) return self.scripts[k] end
function W:HookScript(k, f) local old = self.scripts[k] self.scripts[k] = function(...) if old then old(...) end f(...) end end
function W:CreateTexture(name, layer, template, sub)
	local t = new("Texture", self, name)
	t.layer, t.sub = LAYERS[layer or "ARTWORK"] or 2, sub or 0
	return t
end
function W:CreateFontString(name, layer)
	local t = new("FontString", self, name)
	t.layer, t.sub = LAYERS[layer or "OVERLAY"] or 3, 0
	return t
end
function W:CreateAnimationGroup() return new("AnimGroup", self) end
function W:CreateAnimation() return new("Anim", self) end
function W:SetFrameLevel(l) self.level = l end
function W:GetFrameLevel()
	if self.level then return self.level end
	local p = self.parent
	return p and p.GetFrameLevel and (p:GetFrameLevel() + 1) or 0
end
function W:GetName() return self.name end
function W:SetTexture(path) self.tex, self.colorTex, self.coords = path, nil, nil return path ~= nil end
function W:SetColorTexture(r, g, b, a) self.colorTex, self.tex = { r, g, b, a or 1 }, nil end
function W:SetTexCoord(l, r, t, b) self.coords = { l, r, t, b } end
function W:SetVertexColor(r, g, b, a) self.vcolor = { r, g, b, a or 1 } end
function W:SetBlendMode(m) self.blend = m end
function W:RegisterEvent(e) self.ev[e] = true end
function W:GetTop() return 500 end
function W:GetLeft() return 0 end
function W:GetCenter() return 960, 540 end
function CreateFrame(kind, name, parent)
	local w = new(kind, parent or UIParent, name)
	if name then _G[name] = w end
	return w
end
UIParent = new("Frame", nil, "UIParent")
UIParent.parent = nil
UIParent.w, UIParent.h = 1920, 1080
GameTooltip = new("GameTooltip")
function GameTooltip_Hide() end
UISpecialFrames = {}
tinsert, wipe = table.insert, function(t) for k in pairs(t) do t[k] = nil end return t end
date, time = os.date, os.time
function GetTime() return os.clock() end
function GetServerTime() return os.time() end
TIMERS = {}
C_Timer = { After = function(_, f) TIMERS[#TIMERS + 1] = f end }
function RunTimers() local l = TIMERS TIMERS = {} for _, f in ipairs(l) do f() end end
function hooksecurefunc(t, k, f) local old = t[k] t[k] = function(...) local r = { old(...) } f(...) return unpack(r) end end
function Fire(e, ...) for _, w in ipairs(ALL) do if w.ev[e] and w.scripts.OnEvent then w.scripts.OnEvent(w, e, ...) end end end
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
function InCombatLockdown() return false end
RAID_CLASS_COLORS = {
	HUNTER = { r = 0.67, g = 0.83, b = 0.45 }, WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, MAGE = { r = 0.25, g = 0.78, b = 0.92 },
	PALADIN = { r = 0.96, g = 0.55, b = 0.73 }, SHAMAN = { r = 0.0, g = 0.44, b = 0.87 },
}
LOCALIZED_CLASS_NAMES_MALE = { HUNTER = "Hunter", WARRIOR = "Warrior", MAGE = "Mage", PALADIN = "Paladin", SHAMAN = "Shaman" }
SPELLS = { [6603] = "Melee", [133] = "Fireball", [403] = "Lightning Bolt", [529] = "Lightning Bolt" }
C_Spell = { GetSpellName = function(id) return SPELLS[id] end, GetSpellTexture = function(id) return SPELLS[id] and ("icon:" .. id) end }
function GetSpellTexture(id) return C_Spell.GetSpellTexture(id) end
-- Capped: a loop that prints the log it is reading would otherwise grow it without end.
function print(...)
	if #PRINTED >= 2000 then return end
	local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end
	PRINTED[#PRINTED + 1] = table.concat(t, " ")
end
function BreakUpLargeNumbers(n) local s = tostring(n) local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse() return (out:gsub("^,", "")) end
function Ambiguate(n) return n end
function UnitGUID() return "G-Forearms" end
function UnitIsDeadOrGhost() return false end
INSTANCE = nil
function IsInInstance() return INSTANCE ~= nil, INSTANCE end
function GetInstanceInfo() return "The Deadmines", "party", 1, "Normal", 5, 0, false, 36 end
function GetRealZoneText() return "The Deadmines" end
C_Map = { GetBestMapForUnit = function() return 291 end }
function EJ_GetInstanceForMap(m) return m == 291 and 63 or 0 end
ENCOUNTERS = { { "Rhahk'Zor", 1443 }, { "Sneed", 1444 }, { "Mr. Smite", 1446 } }
function EJ_GetEncounterInfoByIndex(i, j) local e = j == 63 and ENCOUNTERS[i] if e then return e[1], "", 0, 0, "", 63, e[2], 36 end end
Enum = { DamageMeterType = { DamageDone = 0, HealingDone = 1, Absorbs = 2, DamageTaken = 3, AvoidableDamageTaken = 4, Interrupts = 5, Dispels = 6, Deaths = 7, EnemyDamageTaken = 8 } }
SOUNDS = {}
function PlaySound(id) SOUNDS[#SOUNDS + 1] = id end
SOUNDKIT = { UI_SCENARIO_ENDING = 31754 }
StaticPopupDialogs = {}
function StaticPopup_Show() end
function IsShiftKeyDown() return false end
function OpenDeathRecapUI() end

SanctuaryUI = {}
local ns = SanctuaryUI
function ns.Secret() return false end
function ns.Print(m) print(m) end
function ns.Log(fmt, ...) if #PRINTED >= 2000 then return end local ok, s = pcall(string.format, fmt, ...) PRINTED[#PRINTED + 1] = "log: " .. (ok and s or fmt) end
function ns.Try(label, fn, ...) return pcall(fn, ...) end
ns.Fonts = { Path = function(role) return role == "title" and "title" or "body" end, Set = function(fs, role, size) fs.size = size end }
