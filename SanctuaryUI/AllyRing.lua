-- The ally ring: your group around your character, in your field of view. Each ally within
-- sight of the ring is a pip in their class colour, at their true bearing from the way you
-- face (up is ahead of you), nearer the middle the nearer they are, with the distance in
-- yards under it. A faint circle marks "within reach" (the Minimap page's setting): an ally
-- inside it is in range, and their number turns green. Made for PvP, where knowing who is
-- close enough to help, or to be helped, matters at a glance.
--
-- It reads the same positions as the maps (MapPins.lua), so it works wherever the client
-- gives them: the open world, in combat too. Where it hides them (dungeons) the ring rests.
-- Totems are pinned on it too, yours and those group members' SanctuaryUI tells us of (RingTotems.lua).
SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI

ns.AllyRing = {}
local R = ns.AllyRing
local P = ns.MapPins

local MAX_PIPS = 12
local SEGMENTS = 72 -- of the reach circle
local PIP = 18
local DEAD = { 0.5, 0.5, 0.5 }
local WHITE = { 1, 1, 1 }

local frame
local pips, circle = {}, {}
local found = {} -- reused: { yards, east, north, color, name, dead }
local colors = {}

local function Opt()
	return ns.DB().allyRing
end

local function Plain(value)
	return value ~= nil and not ns.Secret(value)
end

local function ClassColor(unit)
	local c = colors[unit]
	if c then return c end
	local _, class = UnitClass(unit)
	if Plain(class) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] then
		local rc = RAID_CLASS_COLORS[class]
		c = { rc.r, rc.g, rc.b }
		colors[unit] = c
		return c
	end
	return WHITE
end

-- Should the ring be up right now?
local function Wanted()
	local opt = Opt()
	if R.preview then return true end
	if not opt.enabled then return false end
	if R.unlocked then return true end -- frames unlocked: up, to be placed
	-- Alone, your own totems on the ring (RingTotems.lua) still bring it up.
	if not IsInGroup() and not (opt.totems and ns.RingTotems.Any()) then return false end
	if opt.show == "group" then return true end
	if opt.show == "combat" then return InCombatLockdown() and true or false end
	-- "pvp": flagged, or in a battleground or arena
	local _, kind = IsInInstance()
	if kind == "pvp" or kind == "arena" then return true end
	local flagged = UnitIsPVP and UnitIsPVP("player")
	return Plain(flagged) and flagged and true or false
end

local function Note(i, yards, east, north, color, name, dead)
	local f = found[i]
	if not f then
		f = {}
		found[i] = f
	end
	f.yards, f.east, f.north, f.color, f.name, f.dead = yards, east, north, color, name, dead
end

-- Allies within the ring's sight, nearest first. Returns how many.
local function Gather(north, west, instance)
	local opt = Opt()
	local n = 0
	if R.preview or (R.unlocked and not IsInGroup()) then
		-- Four stand-ins that drift, to place and size the ring without a group.
		local t = GetTime()
		local fake = { { 14, 0.5, { 0.96, 0.55, 0.73 }, "Paladin" }, { 31, 2.2, { 0.25, 0.78, 0.92 }, "Mage" },
			{ 47, 4.0, { 1, 0.96, 0.41 }, "Rogue" }, { 66, 5.3, { 0.67, 0.83, 0.45 }, "Hunter" } }
		for i, f in ipairs(fake) do
			local yards = f[1] + 6 * math.sin(t * 0.5 + i)
			local a = f[2] + t * 0.08 * (i % 2 == 0 and 1 or -1)
			n = n + 1
			Note(n, yards, math.sin(a) * yards, math.cos(a) * yards, f[3], f[4], false)
		end
		return n
	end
	local raid = IsInRaid()
	local count = raid and math.min(GetNumGroupMembers(), 40) or 4
	for i = 1, count do
		local unit = (raid and "raid" or "party") .. i
		if UnitExists(unit) and not UnitIsUnit(unit, "player") then
			local un, uw, _, uinst = UnitPosition(unit)
			if Plain(un) and Plain(uw) and uinst == instance then
				local east, up = -(uw - west), un - north
				local yards = math.sqrt(east * east + up * up)
				if yards <= opt.maxYards then
					local dead = UnitIsDeadOrGhost(unit)
					local name = UnitName(unit)
					n = n + 1
					Note(n, yards, east, up, ClassColor(unit), Plain(name) and name or nil, Plain(dead) and dead)
				end
			end
		end
	end
	for i = n + 1, #found do found[i].yards = math.huge end
	table.sort(found, function(a, b) return a.yards < b.yards end)
	return n
end

-- The scale with no clear middle: true to you in the middle. Totems always use it, so the
-- middle (and your dot, when shown) sits inside a totem's circle exactly when you are in its
-- reach. Drawn with the clear middle, a totem at your feet sat 70 units out and its circle
-- missed you; the user found this way better in game (2026-11-12).
local function TrueRadius(yards)
	local opt = Opt()
	return (opt.radius - opt.inner) * math.min(1, yards / opt.maxYards)
end

-- How far from the middle an ally (or the reach circle, or the target's halo) sits, in screen
-- units. With your dot shown, the true scale, so everything on the ring measures from you the
-- same way (asked for 2026-11-12); without it, pushed out by the clear middle so the nearest
-- allies don't cover your character.
local function RadiusFor(yards)
	local opt = Opt()
	if opt.selfDot then return TrueRadius(yards) end
	return opt.inner + (opt.radius - opt.inner) * math.min(1, yards / opt.maxYards)
end

-- Small dots by a pip, one per element whose totem reaches that spot (by true distance).
local MARK = 6
local function MakeMarks(pip)
	pip.marks = {}
	for i = 1, 4 do
		local m = pip:CreateTexture(nil, "OVERLAY")
		m:SetSize(MARK, MARK)
		P.SetCell(m, "dot")
		local color = ns.RingTotems.COLORS[i]
		m:SetVertexColor(color[1], color[2], color[3])
		m:Hide()
		pip.marks[i] = m
	end
end

local function ShowMarks(pip, east, north)
	local cov = ns.RingTotems.Covering(east, north)
	local count = 0
	if cov then
		for i = 1, 4 do if cov[i] then count = count + 1 end end
	end
	local j = 0
	for i = 1, 4 do
		local m = pip.marks[i]
		if cov and cov[i] then
			j = j + 1
			m:ClearAllPoints()
			m:SetPoint("CENTER", pip, "RIGHT", MARK / 2 + 1, (count - 1) * (MARK + 1) / 2 - (j - 1) * (MARK + 1))
			m:Show()
		else
			m:Hide()
		end
	end
end

local function DrawCircle()
	local opt = Opt()
	local reach = ns.DB().map.rangeYards
	local show = opt.circle and reach > 0 and reach < opt.maxYards
	local r = RadiusFor(reach)
	for i = 1, SEGMENTS do
		local l = circle[i]
		if show then
			local a0, a1 = (i - 1) / SEGMENTS * 2 * math.pi, i / SEGMENTS * 2 * math.pi
			l:SetStartPoint("CENTER", frame, math.cos(a0) * r, math.sin(a0) * r)
			l:SetEndPoint("CENTER", frame, math.cos(a1) * r, math.sin(a1) * r)
			-- Dashed: every other piece.
			l:SetShown(i % 2 == 0)
		else
			l:Hide()
		end
	end
end

local function Draw()
	local opt = Opt()
	local north, west, instance, facing = P.Here()
	if not north and not (R.preview or R.unlocked) then
		frame.rest:Show() -- no positions here (a dungeon): nothing to show
		for i = 1, MAX_PIPS do pips[i]:Hide() end
		for i = 1, SEGMENTS do circle[i]:Hide() end
		frame.target:Hide()
		frame.me:Hide()
		ns.RingTotems.Hide()
		return
	end
	frame.rest:Hide()
	facing = facing or 0
	local n = Gather(north, west, instance)
	local reach = ns.DB().map.rangeYards
	local c, s = math.cos(facing), math.sin(facing)
	-- Totems first: the pips ask which totems reach them.
	ns.RingTotems.Draw(frame, north, west, instance, c, s, TrueRadius,
		R.preview or (R.unlocked and not IsInGroup()))
	if opt.selfDot then
		local color = ClassColor("player")
		frame.me.icon:SetVertexColor(color[1], color[2], color[3])
		ShowMarks(frame.me, 0, 0)
		frame.me:Show()
	else
		frame.me:Hide()
	end
	for i = 1, MAX_PIPS do
		local pip = pips[i]
		local f = i <= n and found[i]
		if f then
			-- Turned so that the way you face is up.
			local east, up = f.east * c + f.north * s, -f.east * s + f.north * c
			local len = math.max(0.01, f.yards)
			local r = RadiusFor(f.yards)
			local color = f.dead and DEAD or f.color
			pip.icon:SetVertexColor(color[1], color[2], color[3])
			pip:ClearAllPoints()
			pip:SetPoint("CENTER", frame, "CENTER", east / len * r, up / len * r)
			pip.text:SetText(P.Yards(f.yards))
			ShowMarks(pip, f.east, f.north)
			if f.dead then
				pip.text:SetTextColor(0.6, 0.6, 0.6)
			elseif reach > 0 and f.yards <= reach then
				pip.text:SetTextColor(0.45, 1, 0.45)
			else
				pip.text:SetTextColor(0.91, 0.87, 0.77)
			end
			if opt.names and f.name then
				pip.name:SetText(f.name)
				pip.name:SetTextColor(color[1], color[2], color[3])
				pip.name:Show()
			else
				pip.name:Hide()
			end
			pip:Show()
		else
			pip:Hide()
		end
	end
	DrawCircle()

	-- The group member you have targeted: a pale gold halo round their pip. Only group members
	-- can be marked; the client gives no position for anyone else (an enemy, a stranger).
	local dot = frame.target
	local te, tu
	if opt.target then
		if R.preview or (R.unlocked and not IsInGroup()) then
			if n > 0 then te, tu = found[1].east, found[1].north end
		elseif north and UnitExists("target") then
			local me = UnitIsUnit("target", "player")
			local tn, tw, _, tinst = UnitPosition("target")
			if Plain(tn) and Plain(tw) and tinst == instance and not (Plain(me) and me) then
				te, tu = -(tw - west), tn - north
			end
		end
	end
	-- Beyond the ring's sight their pip is not drawn, so neither is the halo.
	if te and math.sqrt(te * te + tu * tu) > opt.maxYards then te = nil end
	if te then
		local yards = math.sqrt(te * te + tu * tu)
		local east, up = te * c + tu * s, -te * s + tu * c
		local len = math.max(0.01, yards)
		local r = RadiusFor(yards)
		dot:ClearAllPoints()
		dot:SetPoint("CENTER", frame, "CENTER", east / len * r, up / len * r)
		dot:Show()
	else
		dot:Hide()
	end
end

local function Place()
	local opt = Opt()
	frame:SetScale(opt.scale)
	frame:SetAlpha(opt.opacity)
	frame:SetSize(opt.radius * 2, opt.radius * 2)
	frame:ClearAllPoints()
	if opt.moved then
		frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", ns.MovedPoint(frame, opt))
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, opt.offsetY / opt.scale)
	end
end

local function OnUpdate(self, elapsed)
	self.wait = (self.wait or 0) + elapsed
	if self.wait < 0.05 then return end
	self.wait = 0
	local ok, err = pcall(Draw)
	if not ok and not self.failed then
		self.failed = true
		if ns.LogError then ns.LogError("ally ring", tostring(err)) end
	end
end

local function Build()
	frame = CreateFrame("Frame", "SanctuaryUIAllyRing", UIParent)
	frame:SetFrameStrata("BACKGROUND")
	frame:SetFrameLevel(5)
	frame:EnableMouse(false)
	frame:Hide()
	for i = 1, SEGMENTS do
		local l = frame:CreateLine(nil, "BACKGROUND")
		l:SetThickness(1.5)
		l:SetColorTexture(0.87, 0.75, 0.47, 0.45)
		circle[i] = l
	end
	for i = 1, MAX_PIPS do
		local pip = CreateFrame("Frame", nil, frame)
		pip:SetSize(PIP, PIP)
		pip:SetFrameLevel(frame:GetFrameLevel() + 4) -- over the target's halo
		pip:EnableMouse(false)
		pip.icon = pip:CreateTexture(nil, "ARTWORK")
		pip.icon:SetAllPoints()
		P.SetCell(pip.icon, "pip")
		pip.text = pip:CreateFontString(nil, "OVERLAY")
		ns.Fonts.Set(pip.text, "body", 13, "OUTLINE")
		pip.text:SetPoint("TOP", pip, "BOTTOM", 0, -1)
		pip.name = pip:CreateFontString(nil, "OVERLAY")
		ns.Fonts.Set(pip.name, "body", 11, "OUTLINE")
		pip.name:SetPoint("BOTTOM", pip, "TOP", 0, 1)
		MakeMarks(pip)
		pip:Hide()
		pips[i] = pip
	end
	local dot = CreateFrame("Frame", nil, frame)
	dot:SetSize(PIP + 12, PIP + 12)
	dot:EnableMouse(false)
	dot.icon = dot:CreateTexture(nil, "BACKGROUND") -- under the pips, which are frames above it
	dot.icon:SetAllPoints()
	P.SetCell(dot.icon, "pip")
	dot.icon:SetVertexColor(1, 0.86, 0.45, 0.95)
	dot:Hide()
	frame.target = dot
	-- You, in the middle (optional): a pip in your class colour, over the totems.
	local me = CreateFrame("Frame", nil, frame)
	me:SetSize(PIP - 4, PIP - 4)
	me:SetPoint("CENTER")
	me:SetFrameLevel(frame:GetFrameLevel() + 4)
	me:EnableMouse(false)
	me.icon = me:CreateTexture(nil, "ARTWORK")
	me.icon:SetAllPoints()
	P.SetCell(me.icon, "pip")
	MakeMarks(me)
	me:Hide()
	frame.me = me
	-- Nothing to say when positions are hidden: an empty frame, kept for the check above.
	frame.rest = CreateFrame("Frame", nil, frame)
	frame.rest:Hide()
	frame:SetScript("OnUpdate", OnUpdate)
end

local function Refresh()
	if not frame then return end
	local want = Wanted()
	if want and not frame:IsShown() then
		Place()
		frame.failed = nil
	end
	frame:SetShown(want)
end

R.Refresh = Refresh

function R.ApplySettings()
	if not frame then return end
	Place()
	Refresh()
end

function R.UpdateMovers(unlocked)
	if not frame then return end
	R.unlocked = unlocked and Opt().enabled and true or nil
	R.mover:SetShown(R.unlocked and true or false)
	Refresh()
end

function R.ResetPosition()
	local opt = Opt()
	opt.moved, opt.mx, opt.my, opt.offsetY = false, 0, 0, 0
	ns.Refresh()
end

-- Session-only: four drifting stand-ins, to place and size the ring.
function R.SetPreview(on)
	R.preview = on and true or nil
	Refresh()
end

function R.Init()
	if frame then return end
	Build()
	Place()
	-- The ring is mostly empty space, so its mover is a handle at its middle, not the whole
	-- ring; and it lives on the screen, since the ring itself is usually hidden.
	R.mover = ns.MakeMover(frame, "Ally ring", Opt, "Reset its position in /sanctuary > Ally ring.", UIParent)
	R.mover:ClearAllPoints()
	R.mover:SetPoint("CENTER", frame, "CENTER")
	R.mover:SetSize(150, 44)
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
		"PLAYER_FLAGS_CHANGED", "UNIT_FACTION", "ZONE_CHANGED_NEW_AREA" }) do
		pcall(events.RegisterEvent, events, event)
	end
	events:SetScript("OnEvent", function(_, event)
		if event == "GROUP_ROSTER_UPDATE" then wipe(colors) end
		Refresh()
	end)
	ns.RingTotems.Init()
	Refresh()
end
