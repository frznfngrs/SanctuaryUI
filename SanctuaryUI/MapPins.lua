-- What the maps mark: where you are, the things worth pointing at (group members, quests, your
-- corpse, a waypoint you set) and the trail you have walked. Map.lua draws them on the corner
-- map and MapOverlay.lua on the overlay.
--
-- What the client allows (the /sanctuary map probe): in the open world your position, your
-- facing and each group member's position are plain numbers, in combat too. Inside a dungeon
-- all of them are nil, so nothing here can be drawn there and Here() returns nil.
SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI

ns.MapPins = {}
local P = ns.MapPins

-- Cells of map-pins.png, 8 x 2 of 64 px (tools/build_minimap_art.py).
local CELLS = { arrow = 0, wedge = 1, pip = 2, diamond = 3, dot = 4, corpse = 5, mail = 6, track = 7,
	calendar = 8, more = 9, flag = 10, north = 11 }

local STEP = 5 -- yards between trail points
local JUMP = 250 -- a move this long in one step is a teleport: the trail starts over
local QUEST_GAP = 2 -- seconds between rebuilds of the quest list
local MAX_QUESTS = 6

P.GOLD = { 1, 0.81, 0.33 }
P.PALE = { 0.91, 0.87, 0.77 }
local WHITE = { 1, 1, 1 }
local GREY = { 0.75, 0.75, 0.78 }

local function Opt()
	return ns.DB().map
end

function P.SetCell(texture, name)
	local path = ns.Art.Require("mapPins")
	local cell = CELLS[name] or 0
	if path then
		texture:SetTexture(path)
		local col, row = cell % 8, math.floor(cell / 8)
		texture:SetTexCoord(col / 8, (col + 1) / 8, row / 2, (row + 1) / 2)
	else
		texture:SetColorTexture(1, 1, 1, 1)
	end
end

local function Plain(value)
	return value ~= nil and not ns.Secret(value)
end

-- Where the player is: north, west (the client's world axes, in yards), the instance and the
-- facing in radians, counter-clockwise from north. Nil where the client hides it.
function P.Here()
	local north, west, _, instance = UnitPosition("player")
	if not Plain(north) or not Plain(west) then return nil end
	local facing = GetPlayerFacing()
	if not Plain(facing) then facing = 0 end
	return north, west, instance, facing
end

-- A target's place on a north-up map centred on the player, in yards: east, north.
function P.Offset(target, north, west)
	return -(target.west - west), target.north - north
end

-- ---------------------------------------------------------------------------------------
-- Targets

local targets = {} -- reused: { kind, north, west, color, name }
local used = 0
local quests = {} -- the quest part, rebuilt on a timer
local questsAt, questsMap = 0, nil

local function Add(kind, north, west, color, name)
	used = used + 1
	local t = targets[used]
	if not t then
		t = {}
		targets[used] = t
	end
	t.kind, t.north, t.west, t.color, t.name = kind, north, west, color, name
end

-- A spot on a zone map (0 to 1 across and down) as world yards.
local function WorldOf(mapID, x, y)
	if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
	local ok, _, world = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
	if not ok or not world or not world.GetXY then return nil end
	local north, west = world:GetXY()
	if not Plain(north) or not Plain(west) then return nil end
	return north, west
end
P.WorldOf = WorldOf

function P.MapID()
	if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
	local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
	if ok and Plain(mapID) then return mapID end
end

local function RebuildQuests(mapID, north, west)
	wipe(quests)
	if not (C_QuestLog and C_QuestLog.GetQuestsOnMap) then return end
	local ok, list = pcall(C_QuestLog.GetQuestsOnMap, mapID)
	if not ok or type(list) ~= "table" then return end
	for _, q in ipairs(list) do
		if Plain(q.x) and Plain(q.y) and Plain(q.questID) then
			local qn, qw = WorldOf(mapID, q.x, q.y)
			if qn then
				local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(q.questID)
				local dn, dw = qn - north, qw - west
				quests[#quests + 1] = { north = qn, west = qw, name = Plain(title) and title or nil, far = dn * dn + dw * dw }
			end
		end
	end
	table.sort(quests, function(a, b) return a.far < b.far end)
	for i = #quests, MAX_QUESTS + 1, -1 do quests[i] = nil end
end

local function ClassColor(unit)
	local _, class = UnitClass(unit)
	if Plain(class) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] then
		local c = RAID_CLASS_COLORS[class]
		return { c.r, c.g, c.b }
	end
	return WHITE
end

local colors = {} -- unit -> its class colour, so a table isn't made every pass

-- Everything worth pointing at from where the player stands. Returns the list and its length;
-- the list is reused, so read it before the next call.
-- In a raid: only the few nearest, so a battleground does not bury the map in arrows.
local RAID_UNITS = {}
for i = 1, 40 do RAID_UNITS[i] = "raid" .. i end
local nearUnit, nearFar, nearNorth, nearWest = {}, {}, {}, {}

local function AddNearestRaiders(north, west, instance, keep)
	local n = 0
	for i = 1, math.min(GetNumGroupMembers(), 40) do
		local unit = RAID_UNITS[i]
		if UnitExists(unit) and not UnitIsUnit(unit, "player") then
			local un, uw, _, uinst = UnitPosition(unit)
			if Plain(un) and Plain(uw) and uinst == instance then
				local dn, dw = un - north, uw - west
				local far = dn * dn + dw * dw
				-- Kept in order, nearest first, never more than `keep`.
				if n < keep or far < nearFar[n] then
					local at = math.min(n + 1, keep)
					while at > 1 and nearFar[at - 1] > far do
						nearUnit[at], nearFar[at], nearNorth[at], nearWest[at] = nearUnit[at - 1], nearFar[at - 1], nearNorth[at - 1], nearWest[at - 1]
						at = at - 1
					end
					nearUnit[at], nearFar[at], nearNorth[at], nearWest[at] = unit, far, un, uw
					if n < keep then n = n + 1 end
				end
			end
		end
	end
	for i = 1, n do
		local unit = nearUnit[i]
		colors[unit] = colors[unit] or ClassColor(unit)
		local name = UnitName(unit)
		Add("party", nearNorth[i], nearWest[i], colors[unit], Plain(name) and name or nil)
	end
end

-- Minimap pings: where someone clicked their minimap, kept for a few seconds. This client
-- has no MINIMAP_PING event (registering it fails), so the minimap is asked where its last
-- ping landed, a few times a second, and a change in that is a new ping. It does not say who
-- pinged. Confirmed working in game on 2026-11-11.
local PING_LIFE = 6
local PING_COLOR = { 1, 0.95, 0.6 }
local pings = {} -- by key: { north, west, untilTime, name }
local lastPingX, lastPingY
local pingQuietUntil = 0

-- Where a spot on the minimap is in the world. x and y: parts of the minimap's width from its
-- middle, right and up. Nil where the client hides positions.
local function PingWorld(x, y)
	local north, west, _, facing = P.Here()
	if not north or not (C_Minimap and C_Minimap.GetViewRadius) then return nil end
	local radius = C_Minimap.GetViewRadius()
	if not Plain(radius) then return nil end
	local east, up = x * 2 * radius, y * 2 * radius
	if GetCVar("rotateMinimap") == "1" then
		-- The map was turned so that facing is up: turn the click back to north-up.
		local c, s = math.cos(facing), math.sin(facing)
		east, up = east * c - up * s, east * s + up * c
	end
	return north + up, west - east
end

local lastPingNorth, lastPingWest -- where the minimap's last ping is in the world

local function PollPing()
	local opt = Opt()
	if not opt or not opt.pings or not Minimap or not Minimap.GetPingPosition then return end
	local x, y = Minimap:GetPingPosition()
	if not Plain(x) or not Plain(y) then return end
	if x == lastPingX and y == lastPingY then return end
	local first = lastPingX == nil
	lastPingX, lastPingY = x, y
	-- The reading is in parts of the minimap's width (Blizzard's own ping code scales it by the
	-- width), and a fresh ping is a click inside the map, so it reads half a width or less. A
	-- bigger reading is the last ping falling behind as you travel, never a new one. (It used
	-- to be taken for pixels and shrunk, which put a ping just behind you every few seconds
	-- while flying: found in game on 2026-11-12.) It is still placed in the world, so that
	-- flying back to it later is not taken for a new ping.
	local outside = x * x + y * y > 0.6 * 0.6
	local north, west = PingWorld(x, y)
	if not north then return end
	-- The reading is where the last ping lies from you, so it changes as you walk, turn or
	-- zoom while the ping itself stays put. Only a spot somewhere else in the world is a
	-- new ping. (Walking used to raise one: found in game on 2026-11-11.)
	local same = lastPingNorth and math.abs(north - lastPingNorth) < 8 and math.abs(west - lastPingWest) < 8
	lastPingNorth, lastPingWest = north, west
	if first or same or outside then return end -- whatever it held at login is not a ping either
	local now = GetTime()
	if now < pingQuietUntil then return end
	pingQuietUntil = now + 1.5
	local ping = pings.ping or {}
	pings.ping = ping
	ping.north, ping.west, ping.untilTime, ping.name = north, west, now + PING_LIFE, "Ping"
end
P.PollPing = PollPing

-- A stand-in ping 60 yards ahead and to the right, to see what one looks like.
function P.TestPing()
	local north, west, _, facing = P.Here()
	if not north then return false end
	local a = facing - 0.6
	pings.test = { north = north + math.cos(a) * 60, west = west + math.sin(a) * 60, untilTime = GetTime() + PING_LIFE, name = "Test ping" }
	return true
end

function P.Targets(north, west, instance)
	used = 0
	local opt = Opt()
	if opt.pings then
		local now = GetTime()
		for _, ping in pairs(pings) do
			if ping.untilTime > now then Add("ping", ping.north, ping.west, PING_COLOR, ping.name) end
		end
	end
	if opt.party and IsInRaid() then
		if opt.raidCount > 0 then AddNearestRaiders(north, west, instance, opt.raidCount) end
	elseif opt.party and IsInGroup() then
		for i = 1, 4 do
			local unit = "party" .. i
			if UnitExists(unit) then
				local un, uw, _, uinst = UnitPosition(unit)
				if Plain(un) and Plain(uw) and uinst == instance then
					colors[unit] = colors[unit] or ClassColor(unit)
					local name = UnitName(unit)
					Add("party", un, uw, colors[unit], Plain(name) and name or nil)
				end
			end
		end
	end
	local mapID = P.MapID()
	if mapID then
		if opt.quests then
			local now = GetTime()
			if mapID ~= questsMap or now - questsAt > QUEST_GAP then
				questsMap, questsAt = mapID, now
				RebuildQuests(mapID, north, west)
			end
			for _, q in ipairs(quests) do Add("quest", q.north, q.west, P.GOLD, q.name) end
		end
		if UnitIsDeadOrGhost("player") and C_DeathInfo and C_DeathInfo.GetCorpseMapPosition then
			local ok, pos = pcall(C_DeathInfo.GetCorpseMapPosition, mapID)
			if ok and pos and pos.GetXY then
				local x, y = pos:GetXY()
				if Plain(x) and Plain(y) then
					local cn, cw = WorldOf(mapID, x, y)
					if cn then Add("corpse", cn, cw, GREY, "Your corpse") end
				end
			end
		end
		if C_Map.GetUserWaypointPositionForMap and C_Map.HasUserWaypoint and C_Map.HasUserWaypoint() then
			local ok, pos = pcall(C_Map.GetUserWaypointPositionForMap, mapID)
			if ok and pos and pos.GetXY then
				local x, y = pos:GetXY()
				if Plain(x) and Plain(y) then
					local fn, fw = WorldOf(mapID, x, y)
					if fn then Add("flag", fn, fw, P.PALE, "Waypoint") end
				end
			end
		end
	end
	return targets, used
end

-- A group change can change who a unit is.
local events = CreateFrame("Frame")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("QUEST_LOG_UPDATE")
events:SetScript("OnEvent", function(_, event)
	if event == "GROUP_ROSTER_UPDATE" then
		wipe(colors)
	else
		questsAt = 0
	end
end)


-- ---------------------------------------------------------------------------------------
-- The trail: where the player has walked, newest last

local trail = {} -- { north, west } pairs flattened: trail[2i-1], trail[2i]
local trailInstance
P.trail = trail

function P.TrailCount()
	return #trail / 2
end

local function Record()
	local opt = Opt()
	if not opt or not opt.trail or opt.style == nil then return end
	local north, west, instance = P.Here()
	if not north then return end
	if UnitOnTaxi and UnitOnTaxi("player") then return end
	local n = #trail
	if instance ~= trailInstance then
		wipe(trail)
		trailInstance, n = instance, 0
	end
	if n >= 2 then
		local dn, dw = north - trail[n - 1], west - trail[n]
		local moved = dn * dn + dw * dw
		if moved < STEP * STEP then return end
		if moved > JUMP * JUMP then
			wipe(trail)
			n = 0
		end
	end
	trail[n + 1], trail[n + 2] = north, west
	local keep = math.max(2, math.floor((opt.trailLength or 300) / STEP)) * 2
	local over = #trail - keep
	if over > 0 then
		-- Drop the oldest in one pass rather than a tremove per point.
		for i = 1, keep do trail[i] = trail[i + over] end
		for i = #trail, keep + 1, -1 do trail[i] = nil end
	end
end

function P.Init()
	if P.ticker then return end
	P.ticker = C_Timer.NewTicker(0.25, function()
		local ok, err = pcall(Record)
		if not ok and ns.LogError then ns.LogError("map trail", tostring(err)) end
		ok, err = pcall(PollPing)
		if not ok and ns.LogError then ns.LogError("map ping", tostring(err)) end
	end)
end

-- ---------------------------------------------------------------------------------------
-- Drawing helpers shared by both maps

-- A pool of small textures on a frame, for trail dots.
function P.DotPool(parent, layer)
	local pool = { parent = parent, layer = layer or "ARTWORK", used = 0 }
	function pool:Get()
		self.used = self.used + 1
		local dot = self[self.used]
		if not dot then
			dot = self.parent:CreateTexture(nil, self.layer)
			P.SetCell(dot, "dot")
			self[self.used] = dot
		end
		dot:Show()
		return dot
	end
	function pool:Done()
		for i = self.used + 1, #self do self[i]:Hide() end
		self.used = 0
	end
	return pool
end

-- A marker: an icon, and a line or two of text beside it.
function P.MakeMarker(parent, size)
	local m = CreateFrame("Frame", nil, parent)
	m:SetSize(size, size)
	m:EnableMouse(false)
	m.icon = m:CreateTexture(nil, "OVERLAY")
	m.icon:SetAllPoints()
	m.text = m:CreateFontString(nil, "OVERLAY")
	ns.Fonts.Set(m.text, "body", 10, "OUTLINE")
	m.text:SetShadowColor(0, 0, 0, 1)
	m.text:SetShadowOffset(1, -1)
	m.name = m:CreateFontString(nil, "OVERLAY")
	ns.Fonts.Set(m.name, "body", 11, "OUTLINE")
	m.name:SetShadowColor(0, 0, 0, 1)
	m.name:SetShadowOffset(1, -1)
	return m
end

local ICON_OF = { party = "pip", quest = "diamond", corpse = "corpse", flag = "flag", ping = "pip" }

-- Dress a marker for a target: its own icon inside the map, the wedge when it sits on the rim.
function P.DressMarker(m, target, onRim)
	local cell = onRim and "wedge" or ICON_OF[target.kind] or "pip"
	if m.cell ~= cell then
		m.cell = cell
		P.SetCell(m.icon, cell)
	end
	local c = target.color or WHITE
	m.icon:SetVertexColor(c[1], c[2], c[3])
	m.text:SetTextColor(c[1], c[2], c[3])
	m.name:SetTextColor(c[1], c[2], c[3])
end

-- A ping's ripple: a ring of light that swells from the marker and fades, over and over.
function P.Pulse(m, on)
	if not on then
		if m.pulse then m.pulse:Hide() end
		return
	end
	if not m.pulse then
		m.pulse = m:CreateTexture(nil, "ARTWORK")
		m.pulse:SetPoint("CENTER")
		P.SetCell(m.pulse, "pip")
		m.pulse:SetBlendMode("ADD")
	end
	local phase = (GetTime() * 1.3) % 1
	local size = m:GetWidth() * (1 + 3.2 * phase)
	m.pulse:SetSize(size, size)
	m.pulse:SetVertexColor(1, 0.92, 0.55, 0.85 * (1 - phase))
	m.pulse:Show()
end

function P.Yards(yards)
	return ("%d yd"):format(yards + 0.5)
end
