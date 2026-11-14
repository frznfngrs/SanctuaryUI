SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.Threat = ns.Threat or {}
local T = ns.Threat

-- Threat: who is closest to pulling your enemy, on the damage meter's forged rails, plus a
-- warning when you take aggro (or, as the tank, lose it) and the enemies loose on your group.
--
-- What this client lets an addon read, as far as the addons made for it show (Plater, ElvUI):
--   UnitThreatSituation's status (0 below the tank, 1 above the tank but not yet pulled,
--   2 tanking but not securely, 3 tanking) looks plain in combat: Plater compares it.
--   UnitDetailedThreatSituation's percentages look secret: ElvUI checks them before use. A
--   secret percent can still fill a StatusBar and be formatted into text; it can't be sorted.
-- Nothing here assumes either: each reading is checked, the rails sort by what can be read,
-- and /sanctuary threat probe writes down what this client really hides.

local HALF = 0.5 -- drawn in the damage meter's 2x art pixels, like Meter.lua
local STUD = 56
local HEAD = 66 -- title strip and the gap under it
local RAIL_H = 40
local RAIL_GAP = 2
local CAP = 40
local NAME_W = 165
local LOOSE_H = 34 -- one loose enemy's line
local INTERVAL = 0.2
local REPEAT = 3 -- seconds before the same warning can show again
local GOLD = { 0.91, 0.78, 0.48 }
local CREAM = { 0.89, 0.84, 0.75 }
local IRON = { 0.62, 0.52, 0.42 }
local RED = { 1, 0.24, 0.16 }
local AMBER = { 1, 0.62, 0.22 }

-- Stances and forms that tank, by spell ID: Defensive Stance, Bear Form, Dire Bear Form.
local TANK_FORMS = { [71] = true, [5487] = true, [9634] = true }
local RIGHTEOUS_FURY = 25780

local SECRET = {} -- a reading the client hid

local PREVIEW_MOB = "Bandit Captain"
local PREVIEW = {
	{ name = "Osgood", class = "PALADIN", status = 3, pct = 100 },
	{ name = "Mirelle", class = "MAGE", status = 1, pct = 94 },
	{ name = "You", mine = true, status = 0, pct = 81 },
	{ name = "Thalric", class = "HUNTER", status = 0, pct = 57 },
	{ name = "Zinnia", class = "SHAMAN", status = 0, pct = 22 },
}
local PREVIEW_LOOSE = {
	{ mob = "Bandit Archer", name = "Zinnia", class = "SHAMAN" },
	{ mob = "War Hound", name = "Thalric", class = "HUNTER" },
}

local function Opt()
	return ns.DB().threat
end

local Secret = function(value) return ns.Secret(value) end

local function Lib()
	return ns.Meter and ns.Meter.Lib
end

-- A function's first return when it can be read, else nil.
local function Ask(fn, ...)
	if not fn then return nil end
	local ok, value = pcall(fn, ...)
	if not ok or value == nil or Secret(value) then return nil end
	return value
end

-- nil: not on the enemy's threat list. SECRET: hidden. Otherwise 0-3.
local function Status(unit, mob)
	if not UnitThreatSituation then return nil end
	local ok, s
	if mob then ok, s = pcall(UnitThreatSituation, unit, mob) else ok, s = pcall(UnitThreatSituation, unit) end
	if not ok or s == nil then return nil end
	if Secret(s) then return SECRET end
	return s
end

local holder, canvas, warn
local rows, looseLines = {}, {}
local inCombat = false
local since = 0
local names, classes = {}, {} -- unit -> plain name and class, kept from out of combat
local furyUp = false -- Righteous Fury, read out of combat (auras are locked in it)

---------------------------------------------------------------------------
-- Who's who

local function GroupUnits()
	local list = {}
	local pets = Opt().pets
	if IsInRaid and IsInRaid() then
		for i = 1, (GetNumGroupMembers and GetNumGroupMembers() or 0) do
			list[#list + 1] = "raid" .. i
			if pets then list[#list + 1] = "raidpet" .. i end
		end
	else
		list[1] = "player"
		if pets then list[2] = "pet" end
		for i = 1, 4 do
			list[#list + 1] = "party" .. i
			if pets then list[#list + 1] = "partypet" .. i end
		end
	end
	return list
end

local function Exists(unit)
	return Ask(UnitExists, unit) and true or false
end

local function IsMe(unit)
	if unit == "player" then return true end
	return Ask(UnitIsUnit, unit, "player") and true or false
end

local function IsPet(unit)
	return unit:find("pet", 1, true) ~= nil
end

-- A name and class for a group member: the client's now, or the last plain one seen.
local function Who(unit)
	local name = UnitName and UnitName(unit)
	if name == nil or Secret(name) then name = names[unit] or name end
	local class
	if not IsPet(unit) then
		local ok, _, token = pcall(UnitClass, unit)
		if ok and token ~= nil and not Secret(token) then class = token else class = classes[unit] end
	end
	local L = Lib()
	if L and not IsPet(unit) then name = L.ShortName(name, true) end
	return name, class
end

local function Remember()
	for _, unit in ipairs(GroupUnits()) do
		local name = UnitName and UnitName(unit)
		names[unit] = (name ~= nil and not Secret(name)) and name or nil
		local ok, _, token = pcall(UnitClass, unit)
		classes[unit] = (ok and token ~= nil and not Secret(token)) and token or nil
	end
end

local function ReadFury()
	if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID and not InCombatLockdown() then
		local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, RIGHTEOUS_FURY)
		if ok and not Secret(aura) then furyUp = aura ~= nil end
	end
end

local function TankUnit(unit)
	if Ask(UnitGroupRolesAssigned, unit) == "TANK" then return true end
	if GetPartyAssignment and Ask(GetPartyAssignment, "MAINTANK", unit) then return true end
	return false
end

-- Are you the tank? The option, else your group role, stance or form, or Righteous Fury.
function T.IsTank()
	local how = Opt().tank
	if how == "tank" then return true end
	if how == "dps" then return false end
	if TankUnit("player") then return true end
	local form = GetShapeshiftForm and Ask(GetShapeshiftForm)
	if form and form > 0 and GetShapeshiftFormInfo then
		local ok, _, _, _, spellID = pcall(GetShapeshiftFormInfo, form)
		if ok and spellID ~= nil and not Secret(spellID) and TANK_FORMS[spellID] then return true end
	end
	return furyUp
end

local function Attackable(unit)
	if not Exists(unit) then return false end
	if not Ask(UnitCanAttack, "player", unit) then return false end
	return not Ask(UnitIsDead, unit)
end

-- The enemy the rails follow: your target, else your target's target (a healer clicking the
-- tank sees the tank's enemy), else your focus.
local function MobUnit()
	for _, unit in ipairs({ "target", "targettarget", "focus" }) do
		if Attackable(unit) then return unit end
	end
end

---------------------------------------------------------------------------
-- Readings

-- Everyone in the group on mob's threat list: unit, name, class, status, pct (maybe secret), mine.
local function Gather(mob)
	local list = {}
	for i, unit in ipairs(GroupUnits()) do
		if Exists(unit) then
			local status = Status(unit, mob)
			local pct
			if UnitDetailedThreatSituation then
				local ok, _, dstatus, scaled = pcall(UnitDetailedThreatSituation, unit, mob)
				if ok then
					pct = scaled
					if status == nil and dstatus ~= nil then status = Secret(dstatus) and SECRET or dstatus end
				end
			end
			if status ~= nil or pct ~= nil then
				local name, class = Who(unit)
				list[#list + 1] = { unit = unit, name = name, class = class, status = status, pct = pct, mine = IsMe(unit), order = i }
			end
		end
	end
	-- Sorted by threat when every percent can be read, by status when those can, else by party order.
	local byPct, byStatus = true, true
	for _, e in ipairs(list) do
		if e.pct == nil or Secret(e.pct) then byPct = false end
		if type(e.status) ~= "number" then byStatus = false end
	end
	table.sort(list, function(a, b)
		if byPct and a.pct ~= b.pct then return a.pct > b.pct end
		if byStatus and a.status ~= b.status then return a.status > b.status end
		return a.order < b.order
	end)
	list.sorted = byPct -- place numbers only for a true ranking
	return list
end

-- Enemies in a fight with the group that someone other than a tank holds (nameplates only).
local function Loose()
	local list = {}
	local group = GroupUnits()
	for i = 1, 40 do
		local plate = "nameplate" .. i
		if Exists(plate) and Attackable(plate) and Ask(UnitAffectingCombat, plate) then
			local mine = Status("player", plate)
			if mine ~= SECRET and (mine == nil or mine < 2) then
				for _, unit in ipairs(group) do
					if not IsMe(unit) and Exists(unit) then
						local s = Status(unit, plate)
						if type(s) == "number" and s >= 2 then
							if not TankUnit(unit) then
								local name, class = Who(unit)
								list[#list + 1] = { plate = plate, name = name, class = class }
							end
							break
						end
					end
				end
			end
		end
	end
	return list
end

---------------------------------------------------------------------------
-- Art (the damage meter's rails, from the same parts sheet)

local function Coords(tex, x, y, w, h, size)
	tex:SetTexCoord(x / size, (x + w) / size, y / size, (y + h) / size)
end

local function BodyFont()
	return ns.Fonts.Path("body", Opt().font)
end

local function TitleFont()
	return ns.Fonts.Path("title", Opt().titleFont)
end

local function Text(parent, font, size, color, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFont(font, size, "")
	fs:SetShadowColor(0, 0, 0, 1)
	fs:SetShadowOffset(2, -2)
	fs:SetTextColor(color[1], color[2], color[3])
	fs:SetJustifyH(justify or "LEFT")
	fs:SetWordWrap(false)
	return fs
end

local function ClassColor(class)
	if class ~= nil and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] then
		local c = RAID_CLASS_COLORS[class]
		return c.r, c.g, c.b
	end
	return 0.62, 0.56, 0.46
end

-- 0 iron, 2 gold (holds aggro), 3 molten (above the tank: about to pull).
local function DressRail(row, kind)
	if row.railKind == kind then return end
	row.railKind = kind
	local y = 562 + kind * 52
	Coords(row.railL, 4, y, CAP, 46, 1024)
	Coords(row.railM, 4 + CAP, y, 502 - 2 * CAP, 46, 1024)
	Coords(row.railR, 506 - CAP, y, CAP, 46, 1024)
	local c = kind == 0 and IRON or { 1, 1, 1 }
	for _, t in ipairs({ row.railL, row.railM, row.railR }) do t:SetVertexColor(c[1], c[2], c[3]) end
	Coords(row.stud, kind * 48, 768, 48, 48, 1024)
	if kind == 0 then
		row.stud:SetVertexColor(IRON[1] * 1.2, IRON[2] * 1.2, IRON[3] * 1.2)
		row.rank:SetTextColor(CREAM[1], CREAM[2], CREAM[3])
	elseif kind == 3 then
		row.stud:SetVertexColor(1, 1, 1)
		row.rank:SetTextColor(1, 0.78, 0.42)
	else
		row.stud:SetVertexColor(1, 1, 1)
		row.rank:SetTextColor(0.12, 0.08, 0.03)
	end
end

local function RailH()
	return math.max(24, Opt().railHeight or RAIL_H)
end

local function Pitch()
	return RailH() + RAIL_GAP
end

local function SizeRow(row)
	local h = RailH()
	local k = h / 50
	local f = k * (Opt().textScale or 1)
	row:SetHeight(h)
	local stud = math.min(h - 6, STUD - 10)
	row.stud:SetSize(stud, stud)
	local capW = CAP * h / 46
	row.railL:SetSize(capW, h)
	row.railR:SetSize(capW, h)
	row.bar:ClearAllPoints()
	row.bar:SetPoint("TOPLEFT", row, "TOPLEFT", STUD + 26 * k, -h * 0.3)
	row.bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -26 * k, h * 0.3)
	row.rank:SetFont(BodyFont(), math.max(10, 21 * f), "")
	row.pct:SetFont(BodyFont(), math.max(10, 21 * f), "")
	row.name:SetFont(BodyFont(), math.max(10, 22 * f), "")
	row.pct:SetWidth(110 * f)
	row.nameW = NAME_W * f
end

local function MakeRow(i)
	local row = CreateFrame("Frame", nil, canvas)
	local parts = ns.Art.Require("targetStyleParts")
	row.stud = row:CreateTexture(nil, "ARTWORK")
	row.stud:SetPoint("LEFT", row, "LEFT", 8, 0)
	row.mine = row:CreateTexture(nil, "OVERLAY")
	row.mine:SetSize(14, 18)
	row.mine:SetPoint("RIGHT", row.stud, "LEFT", 4, 0)
	row.mine:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
	row.mine:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
	row.mine:Hide()
	row.railL = row:CreateTexture(nil, "BORDER")
	row.railM = row:CreateTexture(nil, "BORDER")
	row.railR = row:CreateTexture(nil, "BORDER")
	row.railL:SetPoint("LEFT", row, "LEFT", STUD, 0)
	row.railR:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	row.railM:SetPoint("TOPLEFT", row.railL, "TOPRIGHT")
	row.railM:SetPoint("BOTTOMRIGHT", row.railR, "BOTTOMLEFT")
	for _, t in ipairs({ row.railL, row.railM, row.railR, row.stud }) do
		if parts then t:SetTexture(parts) else t:SetColorTexture(0.12, 0.1, 0.08, 0.9) end
	end
	row.bar = CreateFrame("StatusBar", nil, row)
	row.bar:SetStatusBarTexture(ns.Art.Path("unitFillWhite") or "Interface\\Buttons\\WHITE8X8")
	row.bar:SetMinMaxValues(0, 100)
	row.bar:SetValue(0)
	if not parts then
		local bg = row.bar:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0.02, 0.02, 0.02, 0.9)
	end
	local over = CreateFrame("Frame", nil, row.bar)
	over:SetAllPoints(row)
	over:SetFrameLevel(row.bar:GetFrameLevel() + 2)
	row.rank = Text(over, BodyFont(), 21, CREAM, "CENTER")
	row.rank:SetPoint("CENTER", row.stud, "CENTER", 0, 0)
	row.pct = Text(over, BodyFont(), 21, CREAM, "RIGHT")
	row.pct:SetPoint("RIGHT", row.bar, "RIGHT", -8, 0)
	row.name = Text(over, BodyFont(), 22, CREAM, "LEFT")
	row.railKind = nil
	DressRail(row, 0)
	SizeRow(row)
	rows[i] = row
	return row
end

local STATUS_WORDS = { [3] = "aggro", [2] = "aggro", [1] = "above tank" }

-- e: name, class, status (number, SECRET or nil), pct (maybe secret), mine.
local function FillRow(row, e, rank)
	row.bar:SetMinMaxValues(0, 100)
	local filled = false
	if e.pct ~= nil then filled = pcall(row.bar.SetValue, row.bar, e.pct) end
	if not filled then
		-- No percent at all: fill by what the status says.
		local s = type(e.status) == "number" and e.status or 0
		row.bar:SetValue(s >= 2 and 100 or (s == 1 and 90 or 0))
	end
	local r, g, b = ClassColor(e.class)
	row.bar:SetStatusBarColor(r * 0.82, g * 0.82, b * 0.82)

	row.name:ClearAllPoints()
	row.name:SetPoint("LEFT", row.bar, "LEFT", 10, 0)
	if Secret(e.name) then
		-- A secret "First Last" can't be cut; too narrow for both, one line high, it shows the first.
		row.name:SetWidth(row.nameW or NAME_W)
		row.name:SetWordWrap(true)
		if row.name.SetMaxLines then row.name:SetMaxLines(1) end
	else
		row.name:SetWordWrap(false)
		row.name:SetPoint("RIGHT", row.pct, "LEFT", -8, 0)
	end
	row.name:SetText(e.name or "")
	local c = e.mine and GOLD or CREAM
	row.name:SetTextColor(c[1], c[2], c[3])
	row.mine:SetShown(e.mine and true or false)

	local text
	if e.pct ~= nil then
		local ok, s = pcall(string.format, "%.0f%%", e.pct)
		if ok then text = s end
	end
	if text == nil then text = type(e.status) == "number" and STATUS_WORDS[e.status] or "" end
	row.pct:SetText(text)

	local s = e.status
	DressRail(row, (type(s) == "number" and s >= 2) and 2 or (s == 1 and 3 or 0))
	row.stud:SetShown(Opt().ranks)
	row.rank:SetText((Opt().ranks and rank) and rank or "")
	row:Show()
end

local function LooseLine(i)
	local line = looseLines[i]
	if line then return line end
	line = CreateFrame("Frame", nil, canvas)
	line.mark = line:CreateTexture(nil, "ARTWORK")
	line.mark:SetSize(22, 22)
	line.mark:SetPoint("LEFT", line, "LEFT", STUD + 8, 0)
	line.mark:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew")
	line.mob = Text(line, BodyFont(), 20, { 1, 0.5, 0.38 })
	line.mob:SetPoint("LEFT", line.mark, "RIGHT", 8, 0)
	line.on = Text(line, BodyFont(), 20, CREAM, "RIGHT")
	line.on:SetPoint("RIGHT", line, "RIGHT", -20, 0)
	line.mob:SetPoint("RIGHT", line.on, "LEFT", -10, 0)
	looseLines[i] = line
	return line
end

---------------------------------------------------------------------------
-- The frame

local function Previewing()
	return T.preview or (holder and holder.unlocked)
end

local function InGroup()
	return IsInGroup and IsInGroup() and true or false
end

-- The loose list's room: only for a tank (or the preview) with it turned on.
local function LooseRoom()
	local opt = Opt()
	if not opt.loose then return 0 end
	if not Previewing() and not (InGroup() and T.IsTank()) then return 0 end
	return opt.looseRows
end

local function Wanted()
	local opt = Opt()
	if not opt.enabled then return false end
	if Previewing() then return true end
	local show = opt.show
	if show == "always" then return true end
	if show == "combat" then return inCombat end
	if show == "group" then return InGroup() end
	return inCombat and InGroup()
end

local function PreviewData()
	local t = GetTime and GetTime() or 0
	local list = {}
	for i, p in ipairs(PREVIEW) do
		local pct = p.pct
		if p.status < 2 then pct = math.max(4, math.min(99, pct + 4 * math.sin(t * 0.9 + i * 1.7))) end
		local name, class = p.name, p.class
		if p.mine then
			name = Who("player")
			local _, token = UnitClass("player")
			class = token
		end
		list[i] = { name = name, class = class, status = p.status, pct = pct, mine = p.mine }
	end
	list.sorted = true
	local loose = {}
	for i, l in ipairs(PREVIEW_LOOSE) do loose[i] = { mob = l.mob, name = l.name, class = l.class } end
	return list, loose
end

function T.Draw(list, loose, mobName, mob)
	if not holder or not holder:IsShown() then return end
	local opt = Opt()
	holder.sub:SetText(mobName or "")
	local n = math.min(#list, opt.rows)
	-- You always get a rail: when the list runs past you, the last one is yours.
	local shown = {}
	for i = 1, n do shown[i] = list[i] end
	if n > 0 then
		local mineAt
		for i, e in ipairs(list) do if e.mine then mineAt = i break end end
		if mineAt and mineAt > n then shown[n] = list[mineAt] end
	end
	for i = 1, n do
		local row = rows[i] or MakeRow(i)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, -(HEAD + (i - 1) * Pitch()))
		row:SetPoint("RIGHT", canvas, "RIGHT", 0, 0)
		local rank = list.sorted and (shown[i] == list[i] and i or nil) or nil
		FillRow(row, shown[i], rank)
	end
	for i = n + 1, #rows do rows[i]:Hide() end

	if n == 0 then
		holder.empty:SetText(mob and "Nobody has threat on it yet." or "No enemy targeted.")
		holder.empty:Show()
	else
		holder.empty:Hide()
	end

	local room = LooseRoom()
	local top = HEAD + math.max(n, 1) * Pitch() + 6
	holder.looseHead:SetShown(room > 0 and #loose > 0)
	holder.looseHead:ClearAllPoints()
	holder.looseHead:SetPoint("TOPLEFT", canvas, "TOPLEFT", STUD + 8, -top)
	if room > 0 and #loose > 0 then
		holder.looseHead:SetText(("Loose: %d"):format(#loose))
		top = top + 28
	end
	for i = 1, math.max(#looseLines, room) do
		if i <= room and loose[i] then
			local line = LooseLine(i)
			line:ClearAllPoints()
			line:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, -(top + (i - 1) * LOOSE_H))
			line:SetPoint("RIGHT", canvas, "RIGHT", 0, 0)
			line:SetHeight(LOOSE_H)
			local l = loose[i]
			if l.plate then
				line.mob:SetText(UnitName(l.plate) or "")
			else
				line.mob:SetText(l.mob or "")
			end
			local ok, on = pcall(string.format, "on %s", l.name or "?")
			line.on:SetText(ok and on or "")
			local r, g, b = ClassColor(l.class)
			line.on:SetTextColor(r, g, b)
			line:Show()
		elseif looseLines[i] then
			looseLines[i]:Hide()
		end
	end
end

-- Size, fonts and place: the rails, then the warning line.
function T.Layout()
	if not holder then return end
	local opt = Opt()
	local style = ns.Meter.STYLES[opt.style] and opt.style or "glass"
	local width = math.max(300, opt.width)
	local room = LooseRoom()
	local h = HEAD + opt.rows * Pitch() + (room > 0 and (34 + room * LOOSE_H) or 0) + 10
	holder.title:SetFont(TitleFont(), 28, "")
	holder.sub:SetFont(BodyFont(), 21, "")
	holder.empty:SetFont(BodyFont(), 21, "")
	holder.looseHead:SetFont(TitleFont(), 20, "")
	for _, row in ipairs(rows) do SizeRow(row) end
	for _, line in ipairs(looseLines) do
		line.mob:SetFont(BodyFont(), 20, "")
		line.on:SetFont(BodyFont(), 20, "")
	end
	holder:SetScale(ns.Art.D3Scale(opt.scale))
	holder:SetSize((STUD + width) * HALF, h * HALF)
	canvas:SetSize(STUD + width, h)
	holder:ClearAllPoints()
	if opt.moved then
		holder:SetPoint("CENTER", UIParent, "BOTTOMLEFT", ns.MovedPoint(holder, opt))
	else
		-- Right edge, over the damage meter's default spot.
		holder:SetPoint("BOTTOMRIGHT", UIParent, "RIGHT", -60, -60)
	end

	local glass = style ~= "plaque"
	holder.head:SetSize(width, 52)
	holder.headEdge:SetShown(glass)
	holder.headLine:SetShown(glass)
	local L = Lib()
	if glass and L then
		L.LayGlass(holder.head, holder.glass, width - 8)
	else
		for _, t in ipairs(holder.glass) do t:Hide() end
	end
	for _, t in ipairs(holder.plaque) do t:SetShown(not glass) end
	holder.panel:SetShown(style == "shadow")
	holder.panel:SetAlpha(opt.panelAlpha)
	holder.panel:SetHeight(h)
	holder.empty:ClearAllPoints()
	holder.empty:SetPoint("TOPLEFT", canvas, "TOPLEFT", STUD + 16, -(HEAD + 8))

	if warn then
		warn:SetScale(ns.Art.D3Scale(opt.warnScale))
		warn.text:SetFont(TitleFont(), 40, "OUTLINE")
		warn.sub:SetFont(BodyFont(), 22, "")
		warn:ClearAllPoints()
		local pos = opt.warnPos
		if pos.moved then
			warn:SetPoint("CENTER", UIParent, "BOTTOMLEFT", ns.MovedPoint(warn, pos))
		else
			warn:SetPoint("CENTER", UIParent, "CENTER", 0, 170)
		end
	end
	T.UpdateShown()
end

function T.UpdateShown()
	if not holder then return end
	local want = Wanted()
	if want ~= holder:IsShown() then holder:SetShown(want) end
end

local function Build()
	holder = CreateFrame("Frame", "SanctuaryUIThreat", UIParent)
	holder:SetFrameStrata("LOW")
	holder:Hide()
	holder.glass, holder.plaque = {}, {}
	canvas = CreateFrame("Frame", nil, holder)
	canvas:SetScale(HALF)
	canvas:SetPoint("TOPLEFT")

	-- Glass and shadow: the bag window's dark body behind everything.
	local panel = CreateFrame("Frame", nil, canvas)
	panel:SetPoint("TOPLEFT", canvas, "TOPLEFT", STUD - 8, 0)
	panel:SetPoint("RIGHT", canvas, "RIGHT", 8, 0)
	panel:SetFrameLevel(canvas:GetFrameLevel())
	local edge = panel:CreateTexture(nil, "BACKGROUND", nil, -8)
	edge:SetAllPoints()
	edge:SetColorTexture(0.03, 0.027, 0.023, 1)
	local line = panel:CreateTexture(nil, "BACKGROUND", nil, -7)
	line:SetPoint("TOPLEFT", 3, -3)
	line:SetPoint("BOTTOMRIGHT", -3, 3)
	line:SetColorTexture(0.29, 0.24, 0.16, 1)
	local body = panel:CreateTexture(nil, "BACKGROUND", nil, -6)
	body:SetPoint("TOPLEFT", 4, -4)
	body:SetPoint("BOTTOMRIGHT", -4, 4)
	local bag = ns.Art.Path("bagFrame")
	if bag then
		body:SetTexture(bag)
		Coords(body, 14, 170, 560, 270, 1024)
	else
		body:SetColorTexture(0.05, 0.05, 0.05, 1)
	end
	holder.panel = panel

	local head = CreateFrame("Button", nil, canvas)
	head:SetFrameLevel(canvas:GetFrameLevel() + 2)
	head:SetPoint("TOPLEFT", canvas, "TOPLEFT", STUD, -6)
	holder.head = head
	holder.headEdge = head:CreateTexture(nil, "BACKGROUND")
	holder.headEdge:SetAllPoints()
	holder.headEdge:SetColorTexture(0.04, 0.03, 0.024, 1)
	holder.headLine = head:CreateTexture(nil, "BORDER")
	holder.headLine:SetPoint("TOPLEFT", 3, -3)
	holder.headLine:SetPoint("BOTTOMRIGHT", -3, 3)
	holder.headLine:SetColorTexture(0.59, 0.44, 0.19, 1)
	local button = ns.Art.Path("d3Button")
	for i, cut in ipairs({ { 0, 24 }, { 24, 72 }, { 96, 24 } }) do
		local t = head:CreateTexture(nil, "ARTWORK")
		if button then
			t:SetTexture(button)
			t:SetTexCoord(cut[1] / 128, (cut[1] + cut[2]) / 128, 0, 52 / 64)
		else
			t:SetColorTexture(0.3, 0.05, 0.03, 1)
		end
		holder.plaque[i] = t
	end
	holder.plaque[1]:SetPoint("TOPLEFT")
	holder.plaque[1]:SetPoint("BOTTOMLEFT")
	holder.plaque[1]:SetWidth(24)
	holder.plaque[3]:SetPoint("TOPRIGHT")
	holder.plaque[3]:SetPoint("BOTTOMRIGHT")
	holder.plaque[3]:SetWidth(24)
	holder.plaque[2]:SetPoint("TOPLEFT", holder.plaque[1], "TOPRIGHT")
	holder.plaque[2]:SetPoint("BOTTOMRIGHT", holder.plaque[3], "BOTTOMLEFT")

	local over = CreateFrame("Frame", nil, head)
	over:SetAllPoints()
	over:SetFrameLevel(head:GetFrameLevel() + 1)
	holder.title = Text(over, TitleFont(), 28, GOLD)
	holder.title:SetPoint("LEFT", head, "LEFT", 18, -1)
	holder.title:SetText("Threat")
	local gear = CreateFrame("Button", nil, over)
	gear:SetSize(30, 30)
	gear:SetPoint("RIGHT", head, "RIGHT", -12, 0)
	gear.icon = gear:CreateTexture(nil, "ARTWORK")
	gear.icon:SetAllPoints()
	gear.icon:SetTexture("Interface\\WorldMap\\Gear_64Grey")
	gear.icon:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
	gear:SetScript("OnEnter", function(self)
		self.icon:SetVertexColor(1, 1, 1)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Threat options")
		GameTooltip:Show()
	end)
	gear:SetScript("OnLeave", function(self)
		self.icon:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
		GameTooltip_Hide()
	end)
	gear:SetScript("OnClick", function() ns.Options.Open("threat") end)
	holder.sub = Text(over, BodyFont(), 21, CREAM)
	holder.sub:SetPoint("LEFT", holder.title, "RIGHT", 24, -1)
	holder.sub:SetPoint("RIGHT", gear, "LEFT", -12, 0)
	head:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Threat")
		GameTooltip:AddLine("Your target's threat list, or your target's target when you have a friend targeted.", 1, 1, 1, true)
		GameTooltip:AddLine("Gold rail: holds aggro. Molten rail: above the tank, about to pull. 100% pulls it.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	head:SetScript("OnLeave", GameTooltip_Hide)

	holder.empty = Text(canvas, BodyFont(), 21, CREAM)
	holder.empty:SetAlpha(0.7)
	holder.looseHead = Text(canvas, TitleFont(), 20, { 1, 0.5, 0.38 })
	holder.looseHead:Hide()

	-- The warning line: big red letters above the console, like D3's own alerts.
	warn = CreateFrame("Frame", "SanctuaryUIThreatWarning", UIParent)
	warn:SetFrameStrata("HIGH")
	warn:SetSize(640, 90)
	warn:EnableMouse(false)
	warn:SetAlpha(0)
	warn.text = Text(warn, TitleFont(), 40, RED, "CENTER")
	warn.text:SetPoint("TOP", warn, "TOP", 0, -6)
	warn.sub = Text(warn, BodyFont(), 22, CREAM, "CENTER")
	warn.sub:SetPoint("TOP", warn.text, "BOTTOM", 0, -6)
	local anim = warn:CreateAnimationGroup()
	local fadeIn = anim:CreateAnimation("Alpha")
	fadeIn:SetFromAlpha(0)
	fadeIn:SetToAlpha(1)
	fadeIn:SetDuration(0.12)
	fadeIn:SetOrder(1)
	local fadeOut = anim:CreateAnimation("Alpha")
	fadeOut:SetFromAlpha(1)
	fadeOut:SetToAlpha(0)
	fadeOut:SetStartDelay(1.8)
	fadeOut:SetDuration(0.7)
	fadeOut:SetOrder(2)
	anim:SetScript("OnFinished", function() if not warn.unlocked then warn:SetAlpha(0) end end)
	warn.anim = anim
end

---------------------------------------------------------------------------
-- Warnings

local WARNINGS = {
	high = { "Threat high", "You are above the tank. Ease off.", AMBER },
	aggro = { "You have aggro", nil, RED },
	lost = { "Lost aggro", nil, RED },
	loose = { "Loose enemy", nil, AMBER },
}
local lastShown = {}
local myLast, mobLast, looseLast = 0, nil, 0

function T.Warn(kind, sub, force)
	local w = WARNINGS[kind]
	if not w or not warn then return end
	local now = GetTime()
	if not force and lastShown[kind] and now - lastShown[kind] < REPEAT then return end
	lastShown[kind] = now
	warn.text:SetText(w[1])
	warn.text:SetTextColor(w[3][1], w[3][2], w[3][3])
	warn.sub:SetText(sub or w[2] or "")
	warn.anim:Stop()
	warn:SetAlpha(1)
	warn.anim:Play()
	if Opt().warnSound and PlaySound then
		local kit = SOUNDKIT and SOUNDKIT.RAID_WARNING
		if not (kit and pcall(PlaySound, kit, "SFX")) then pcall(PlaySound, 8959, "SFX") end
	end
end

local function ResetWarnings()
	myLast, mobLast, looseLast = 0, nil, 0
end

-- In a dungeon or raid: where a group fights the same enemies. Out in the world a group often
-- quests apart, and every solo pull would be "aggro".
local function InDungeon()
	if not IsInInstance then return false end
	local ok, inside, kind = pcall(IsInInstance)
	if not ok or Secret(inside) or Secret(kind) then return false end
	return inside and (kind == "party" or kind == "raid") or false
end

local function CheckWarnings(mob, loose)
	local opt = Opt()
	if not opt.warn or not inCombat or not InGroup() or (opt.warnInstance and not InDungeon()) then
		ResetWarnings()
		return
	end
	if T.IsTank() then
		myLast = 0
		if opt.warnLost and mob then
			local s = Status("player", mob)
			if type(s) == "number" then
				if mobLast and mobLast >= 2 and s < 2 then T.Warn("lost", UnitName(mob)) end
				mobLast = s
			end
		end
		if opt.warnLoose then
			if #loose > looseLast and loose[1] then T.Warn("loose", UnitName(loose[#loose].plate)) end
			looseLast = #loose
		end
	else
		mobLast, looseLast = nil, 0
		local s = Status("player")
		if type(s) == "number" then
			if s >= 2 and myLast < 2 and opt.warnAggro then
				local on = mob and Status("player", mob)
				T.Warn("aggro", (type(on) == "number" and on >= 2) and UnitName(mob) or nil)
			elseif s == 1 and myLast < 1 and opt.warnHigh then
				T.Warn("high")
			end
			myLast = s
		end
	end
end

-- Show each warning in turn, for placing and judging them.
function T.TestWarnings()
	if not warn then return end
	local order = { { "high" }, { "aggro", PREVIEW_MOB }, { "lost", PREVIEW_MOB }, { "loose", "Bandit Archer" } }
	for i, w in ipairs(order) do
		C_Timer.After((i - 1) * 2.8, function() T.Warn(w[1], w[2], true) end)
	end
end

---------------------------------------------------------------------------
-- What this client hides, written to the log once per session and place

local logged = {}

local function Kind(value)
	if value == nil then return "nil" end
	if Secret(value) then return "SECRET" end
	return type(value)
end

local function Readings(mob)
	local where = (IsInInstance and select(2, IsInInstance())) or "?"
	if Secret(where) then where = "?" end
	local parts = {}
	local _, dstatus, scaled, raw, value
	if UnitDetailedThreatSituation then
		local ok
		ok, _, dstatus, scaled, raw, value = pcall(UnitDetailedThreatSituation, "player", mob)
		if not ok then parts[#parts + 1] = "detailed FAILS" end
	end
	local ok, s = pcall(UnitThreatSituation, "player", mob)
	local okAll, sAll = pcall(UnitThreatSituation, "player")
	parts[#parts + 1] = ("status %s, any-mob status %s, detailed status %s, percent %s, raw %s, value %s"):format(
		ok and Kind(s) or "FAILS", okAll and Kind(sAll) or "FAILS", Kind(dstatus), Kind(scaled), Kind(raw), Kind(value))
	if not T.probeBar then
		T.probeBar = CreateFrame("StatusBar", nil, UIParent)
		T.probeBar:SetSize(1, 1)
		T.probeBar:Hide()
	end
	local probeBar = T.probeBar
	if scaled ~= nil and Secret(scaled) then
		parts[#parts + 1] = "bar " .. (pcall(probeBar.SetValue, probeBar, scaled) and "draws it" or "REFUSES it")
		parts[#parts + 1] = "format " .. (pcall(string.format, "%.0f%%", scaled) and "ok" or "FAILS")
	end
	local plates, readable = 0, 0
	for i = 1, 40 do
		if Exists("nameplate" .. i) then
			plates = plates + 1
			local ps = Status("player", "nameplate" .. i)
			if ps ~= SECRET then readable = readable + 1 end
		end
	end
	parts[#parts + 1] = ("nameplates %d (%d with a readable status)"):format(plates, readable)
	local name = UnitName("party1")
	if name == nil then name = UnitName("player") end
	parts[#parts + 1] = "unit names " .. Kind(name)
	return where, table.concat(parts, "; ")
end

local function LogOnce(mob)
	local where = (IsInInstance and select(2, IsInInstance())) or "?"
	if Secret(where) then where = "?" end
	if logged[where] then return end
	logged[where] = true
	local w, text = Readings(mob)
	local was = ns.forceLog
	ns.forceLog = true
	ns.Log("threat readings in combat (%s): %s", w, text)
	ns.forceLog = was
end

-- /sanctuary threat probe: now, and three seconds into the next three fights, in chat and the log.
local probeFights = 0
local function ProbeOut(label)
	local mob = MobUnit()
	if not mob then
		ns.Print("threat probe (" .. label .. "): no enemy targeted")
		return
	end
	local where, text = Readings(mob)
	ns.Print(("threat probe (%s, %s): %s"):format(label, where, text))
	local was = ns.forceLog
	ns.forceLog = true
	ns.Log("threat probe (%s, %s): %s", label, where, text)
	ns.forceLog = was
end

function T.Probe()
	probeFights = 3
	ProbeOut(inCombat and "in combat" or "out of combat")
	ns.Print("threat probe: I'll write the readings again 3 seconds into each of your next 3 fights. Target an enemy while you fight.")
end

---------------------------------------------------------------------------
-- The loop

local function Tick()
	local opt = Opt()
	if not opt.enabled then return end
	if Previewing() then
		local list, loose = PreviewData()
		T.Draw(list, loose, PREVIEW_MOB, true)
		return
	end
	local shown = holder:IsShown()
	if not shown and not (opt.warn and inCombat and InGroup()) then return end
	local mob = MobUnit()
	local list = mob and Gather(mob) or {}
	local loose = (opt.loose and InGroup() and T.IsTank()) and Loose() or {}
	if inCombat and mob and #list > 0 then LogOnce(mob) end
	if shown then T.Draw(list, loose, mob and UnitName(mob) or nil, mob) end
	CheckWarnings(mob, loose)
end

function T.UpdateMovers(unlocked)
	if not holder then return end
	local show = unlocked and Opt().enabled and true or false
	holder.unlocked = show
	T.mover:SetShown(show)
	warn.unlocked = show and Opt().warn or false
	T.warnMover:SetShown(warn.unlocked)
	if warn.unlocked then
		warn.anim:Stop()
		warn.text:SetText(WARNINGS.aggro[1])
		warn.text:SetTextColor(RED[1], RED[2], RED[3])
		warn.sub:SetText(PREVIEW_MOB)
		warn:SetAlpha(1)
	else
		warn:SetAlpha(0)
	end
	T.Layout()
end

function T.ResetPosition()
	local opt = Opt()
	opt.moved, opt.mx, opt.my = false, 0, 0
	ns.Refresh()
end

function T.ResetWarnPosition()
	local pos = Opt().warnPos
	pos.moved, pos.mx, pos.my = false, 0, 0
	ns.Refresh()
end

-- Session-only: a made-up pull on the rails, to judge and place them without a group.
function T.SetPreview(on)
	T.preview = on and true or nil
	T.Layout()
	Tick()
end

function T.ApplySettings()
	if holder then T.Layout() end
end

function T.Init()
	Build()
	T.mover = ns.MakeMover(holder, "Threat", Opt, "Reset its position in /sanctuary > Threat.")
	T.warnMover = ns.MakeMover(warn, "Threat warning", function() return Opt().warnPos end, "Reset its position in /sanctuary > Threat > Warnings.")
	T.warnMover:Hide()

	local events = CreateFrame("Frame")
	for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE",
		"PLAYER_TARGET_CHANGED", "UNIT_PET", "UNIT_AURA", "UPDATE_SHAPESHIFT_FORM", "PLAYER_ROLES_ASSIGNED" }) do
		pcall(events.RegisterEvent, events, event)
	end
	events:SetScript("OnEvent", function(_, event, unit)
		if event == "PLAYER_REGEN_DISABLED" then
			inCombat = true
			ResetWarnings()
			if probeFights > 0 then
				probeFights = probeFights - 1
				C_Timer.After(3, function() if inCombat then ProbeOut("3 s into a fight") end end)
			end
		elseif event == "PLAYER_REGEN_ENABLED" then
			inCombat = false
			ResetWarnings()
			Remember()
		elseif event == "PLAYER_ENTERING_WORLD" then
			local affecting = UnitAffectingCombat and UnitAffectingCombat("player")
			inCombat = not Secret(affecting) and affecting and true or false
			if not inCombat then Remember() end
		elseif event == "PLAYER_TARGET_CHANGED" then
			mobLast = nil
			return
		elseif event == "UNIT_AURA" then
			if unit ~= "player" or inCombat then return end
			local was = furyUp
			ReadFury()
			if furyUp == was then return end
		elseif not inCombat then
			Remember()
		end
		-- Role, group or form changed: the loose list may come or go.
		T.Layout()
	end)

	local driver = CreateFrame("Frame")
	driver:SetScript("OnUpdate", function(_, elapsed)
		since = since + elapsed
		if since < INTERVAL then return end
		since = 0
		local ok, err = pcall(Tick)
		if not ok and not T.failed then
			T.failed = true
			ns.Log("threat tick failed: %s", tostring(err))
		end
	end)
	Remember()
	ReadFury()
	T.Layout()
end
