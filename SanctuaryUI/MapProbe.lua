-- Map probe (/sanctuary map probe). This only writes down what the client lets an addon read
-- about where the player and the group are, what map art exists, what the minimap frame
-- offers, and whether hidden addon messages get through, in each place the player goes and
-- in and out of combat. The minimap work is built on what this finds.
-- Player names are never written, only whether they could be read.
SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI

ns.MapProbe = {}

local PREFIX = "SanctuaryPos"
local FIGHTS = 2 -- fights to record after the command
local PLACES = 10 -- loading screens and indoor/outdoor changes to record
local IN_COMBAT_AT = 4 -- seconds into a fight for the in-combat reading
local ECHO_WAIT = 4 -- seconds to wait for sent messages to come back
local ANSWER_GAP = 2 -- at most one answer to another player's probe this often
local PEEK_SECONDS = 10

local frame = CreateFrame("Frame")
local comm = CreateFrame("Frame")
local fightsLeft, placesLeft = 0, 0
local armed = false
local token = ("%04x"):format(math.random(0, 65535)) -- marks this session's own messages
local sentCount = 0
local pending = {} -- id -> { at, channel }
local lastAnswer = 0
local lastLine = ""
local lastPlace

local function Out(fmt, ...)
	local was = ns.forceLog
	ns.forceLog = true
	ns.Log("map: " .. fmt, ...)
	ns.forceLog = was
	lastLine = fmt
end

local function V(value)
	if value == nil then return "nil" end
	if ns.Secret(value) then return "SECRET" end
	if type(value) == "number" and value ~= math.floor(value) then return ("%.2f"):format(value) end
	return tostring(value)
end

-- For names: readable or not, never the text.
local function R(value)
	if value == nil then return "nil" end
	if ns.Secret(value) then return "SECRET" end
	return "readable"
end

local function FirstLine(err)
	return tostring(err):match("[^\n]*"):sub(1, 110)
end

-- Run fn, report "ok" (with what it returned) or the error's first line.
local function Try(fn, ...)
	local ok, result = pcall(fn, ...)
	if ok then
		return result == nil and "ok" or ("ok -> " .. V(result))
	end
	return "FAILS (" .. FirstLine(result) .. ")"
end

-- Every value a call returned, for the log.
local function All(fn, ...)
	if type(fn) ~= "function" then return "no such function" end
	local got = { pcall(fn, ...) }
	if not got[1] then return "FAILS (" .. FirstLine(got[2]) .. ")" end
	local n = select("#", unpack(got)) -- trailing nils are lost; good enough for a report
	if n <= 1 then return "nothing" end
	local parts = {}
	for i = 2, n do parts[#parts + 1] = V(got[i]) end
	return table.concat(parts, ", ")
end

local function Names(t)
	if type(t) ~= "table" then return "missing" end
	local list = {}
	for name, value in pairs(t) do
		if type(value) == "function" then list[#list + 1] = name end
	end
	table.sort(list)
	return #list > 0 and table.concat(list, " ") or "empty"
end

local function Restrictions()
	local parts = {}
	if C_RestrictedActions and C_RestrictedActions.GetAddOnRestrictionState and Enum.AddOnRestrictionType then
		for name, value in pairs(Enum.AddOnRestrictionType) do
			local ok, state = pcall(C_RestrictedActions.GetAddOnRestrictionState, value)
			parts[#parts + 1] = name .. "=" .. (ok and V(state) or "error")
		end
		table.sort(parts)
	end
	return #parts > 0 and table.concat(parts, " ") or "no C_RestrictedActions"
end

-- World position of a unit as plain numbers, or nil when hidden or secret.
local function Where(unit)
	local ok, a, b, _, map = pcall(UnitPosition, unit)
	if not ok or a == nil or b == nil then return nil end
	if ns.Secret(a) or ns.Secret(b) or ns.Secret(map) then return nil end
	return a, b, map
end

local function Yards(ax, ay, bx, by)
	local dx, dy = ax - bx, ay - by
	return math.sqrt(dx * dx + dy * dy)
end

local function GroupChannel()
	if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and not IsInGroup(LE_PARTY_CATEGORY_HOME) then
		return "INSTANCE_CHAT"
	elseif IsInRaid() then
		return "RAID"
	elseif IsInGroup() then
		return "PARTY"
	end
end

local function GroupUnits()
	local units = {}
	if IsInRaid() then
		for i = 1, math.min(GetNumGroupMembers(), 40) do
			if not UnitIsUnit("raid" .. i, "player") then units[#units + 1] = "raid" .. i end
		end
	else
		for i = 1, 4 do
			if UnitExists("party" .. i) then units[#units + 1] = "party" .. i end
		end
	end
	return units
end

-- ---------------------------------------------------------------------------------------
-- What can be read

local function PositionReport()
	Out("UnitPosition(player): %s", All(UnitPosition, "player"))
	Out("facing: %s, speed: %s, indoors %s, mounted %s, on taxi %s", All(GetPlayerFacing), All(GetUnitSpeed, "player"),
		V(IsIndoors and IsIndoors()), V(IsMounted and IsMounted()), V(UnitOnTaxi and UnitOnTaxi("player")))
	local x, y = Where("player")
	if x then
		Out("  maths on it: subtract %s, compare %s, format %s", Try(function() return x - 1 end),
			Try(function() return x > 0 end), Try(function() return ("%.1f"):format(x) end))
	else
		local ok, a = pcall(UnitPosition, "player")
		if ok and a ~= nil then
			Out("  maths on a hidden position: subtract %s, format %s", Try(function() return a - 1 end),
				Try(function() return ("%.1f"):format(a) end))
		end
	end

	local mapID = C_Map and C_Map.GetBestMapForUnit and select(2, pcall(C_Map.GetBestMapForUnit, "player"))
	Out("best map for player: %s", V(mapID))
	if mapID == nil or ns.Secret(mapID) or type(mapID) ~= "number" then return nil end
	local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
	if ok and pos and pos.GetXY then
		Out("map position: %s", All(pos.GetXY, pos))
		if C_Map.GetWorldPosFromMapPos then
			local ok2, continent, world = pcall(C_Map.GetWorldPosFromMapPos, mapID, pos)
			Out("  as world position: continent %s, %s", ok2 and V(continent) or "FAILS",
				(ok2 and world and world.GetXY) and All(world.GetXY, world) or V(world))
		end
	else
		Out("map position: %s", ok and V(pos) or ("FAILS (" .. FirstLine(pos) .. ")"))
	end
	return mapID
end

local function MapArtReport(mapID)
	local id, depth = mapID, 0
	while id and id > 0 and depth < 4 do
		local ok, info = pcall(C_Map.GetMapInfo, id)
		if not ok or type(info) ~= "table" then
			Out("map %s: info %s", V(id), ok and V(info) or "FAILS")
			break
		end
		local layers = C_Map.GetMapArtLayers and select(2, pcall(C_Map.GetMapArtLayers, id))
		local layerText = "no layers"
		if type(layers) == "table" and layers[1] then
			local l = layers[1]
			layerText = ("%d layers, first %sx%s in %sx%s tiles"):format(#layers, V(l.layerWidth), V(l.layerHeight), V(l.tileWidth), V(l.tileHeight))
		end
		local tiles = C_Map.GetMapArtLayerTextures and select(2, pcall(C_Map.GetMapArtLayerTextures, id, 1))
		local explored = C_MapExplorationInfo and C_MapExplorationInfo.GetExploredMapTextures
			and select(2, pcall(C_MapExplorationInfo.GetExploredMapTextures, id))
		Out("map %s: type %s, parent %s, name %s, %s, %s tiles (first %s), %s explored pieces, world size %s", V(id), V(info.mapType),
			V(info.parentMapID), R(info.name), layerText, type(tiles) == "table" and #tiles or V(tiles),
			type(tiles) == "table" and V(tiles[1]) or "-", type(explored) == "table" and #explored or V(explored),
			All(C_Map.GetMapWorldSize, id))
		if depth == 0 then
			Out("  group id %s, quests on it %s, flight points %s", All(C_Map.GetMapGroupID, id),
				(C_QuestLog and C_QuestLog.GetQuestsOnMap) and Try(function() return #C_QuestLog.GetQuestsOnMap(id) end) or "no such function",
				(C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap) and Try(function() return #C_TaxiMap.GetTaxiNodesForMap(id) end) or "no such function")
			if C_QuestLog and C_QuestLog.GetQuestsOnMap then
				local okQ, quests = pcall(C_QuestLog.GetQuestsOnMap, id)
				local q = okQ and type(quests) == "table" and quests[1]
				if q then Out("  first quest on it: id %s at %s, %s", V(q.questID), V(q.x), V(q.y)) end
			end
		end
		id, depth = info.parentMapID, depth + 1
	end
end

local function GroupReport()
	local units = GroupUnits()
	Out("group: %d others, channel %s", #units, tostring(GroupChannel() or "none"))
	local px, py, pmap = Where("player")
	for i = 1, math.min(#units, 5) do
		local unit = units[i]
		local x, y, map = Where(unit)
		local yards = "-"
		if px and x then yards = (map == pmap) and ("%.1f"):format(Yards(px, py, x, y)) or "other map" end
		Out("  %s: position %s, yards from me %s, visible %s, connected %s, in range %s, distance squared %s, name %s",
			unit:gsub("%d+", "#"), All(UnitPosition, unit), yards, V(UnitIsVisible(unit)), V(UnitIsConnected(unit)),
			All(UnitInRange, unit), All(UnitDistanceSquared, unit), R(UnitName(unit)))
	end
end

local function MinimapReport()
	local mm = Minimap
	if not mm then Out("no Minimap frame"); return end
	local getCVar = C_CVar and C_CVar.GetCVar or GetCVar
	Out("minimap: size %s x %s, scale %s, alpha %s, zoom %s of %s, view radius %s, rotate %s, parent %s, protected %s",
		V(mm:GetWidth()), V(mm:GetHeight()), V(mm:GetScale()), V(mm:GetAlpha()), All(mm.GetZoom, mm), All(mm.GetZoomLevels, mm),
		(C_Minimap and C_Minimap.GetViewRadius) and All(C_Minimap.GetViewRadius) or "no such function",
		V(getCVar and getCVar("rotateMinimap")), V(mm:GetParent() and mm:GetParent():GetName()), V(mm:IsProtected()))
	local has, lacks = {}, {}
	for _, name in ipairs({ "SetMaskTexture", "SetBlipTexture", "SetPlayerTexture", "SetIconTexture", "SetPOIArrowTexture",
		"SetCorpsePOIArrowTexture", "SetStaticPOIArrowTexture", "SetQuestBlobRingAlpha", "SetQuestBlobInsideAlpha",
		"SetTaskBlobRingAlpha", "SetArchBlobRingAlpha", "PingLocation", "GetPingPosition", "SetZoom", "UpdateBlips" }) do
		if type(mm[name]) == "function" then has[#has + 1] = name else lacks[#lacks + 1] = name end
	end
	Out("  methods: %s. Missing: %s", table.concat(has, " "), #lacks > 0 and table.concat(lacks, " ") or "none")
	local cluster = MinimapCluster
	if cluster then
		local parts = {}
		for _, key in ipairs({ "MinimapContainer", "Tracking", "TrackingFrame", "ZoneTextButton", "BorderTop", "IndicatorFrame",
			"InstanceDifficulty", "DielFrame" }) do
			if cluster[key] then parts[#parts + 1] = key end
		end
		Out("  cluster: %s; edit mode system %s", table.concat(parts, " "), V(cluster.system))
	end
end

local function ApiReport()
	Out("C_Minimap: %s", Names(C_Minimap))
	Out("C_VignetteInfo: %s", Names(C_VignetteInfo))
	Out("C_SuperTrack: %s", Names(C_SuperTrack))
	Out("C_Navigation: %s", Names(C_Navigation))
	Out("C_Ping: %s", Names(C_Ping))
	Out("C_DeathInfo: %s", Names(C_DeathInfo))
	Out("C_AreaPoiInfo: %s", Names(C_AreaPoiInfo))
	Out("C_MapExplorationInfo: %s", Names(C_MapExplorationInfo))
	Out("C_Map: %s", Names(C_Map))
	Out("globals: UnitDistanceSquared %s, GetCorpseMapPosition %s, GetMinimapZoneText %s, Minimap_SetPing %s, HereBeDragons %s",
		type(UnitDistanceSquared), type(GetCorpseMapPosition), type(GetMinimapZoneText), type(Minimap_SetPing),
		tostring(LibStub and LibStub("HereBeDragons-2.0", true) ~= nil))
end

local function LiveReport(mapID)
	if C_VignetteInfo and C_VignetteInfo.GetVignettes then
		local ok, list = pcall(C_VignetteInfo.GetVignettes)
		Out("vignettes: %s", ok and (type(list) == "table" and #list or V(list)) or "FAILS")
		if ok and type(list) == "table" and list[1] and mapID and C_VignetteInfo.GetVignettePosition then
			local okP, pos = pcall(C_VignetteInfo.GetVignettePosition, list[1], mapID)
			Out("  first one's position: %s", (okP and pos and pos.GetXY) and All(pos.GetXY, pos) or V(okP and pos or "FAILS"))
		end
	end
	if C_Minimap and C_Minimap.GetNumTrackingTypes then Out("tracking types: %s", All(C_Minimap.GetNumTrackingTypes)) end
	if C_SuperTrack then
		Out("tracked quest %s, tracking anything %s, user waypoint %s", All(C_SuperTrack.GetSuperTrackedQuestID),
			All(C_SuperTrack.IsSuperTrackingAnything), All(C_Map and C_Map.HasUserWaypoint))
	end
	if C_Navigation then
		Out("navigation: distance %s, state %s", All(C_Navigation.GetDistance), All(C_Navigation.GetTargetState))
	end
	if mapID and C_DeathInfo and C_DeathInfo.GetCorpseMapPosition then
		local ok, pos = pcall(C_DeathInfo.GetCorpseMapPosition, mapID)
		Out("corpse position: %s (dead %s)", (ok and pos and pos.GetXY) and All(pos.GetXY, pos) or V(ok and pos or "FAILS"),
			V(UnitIsDeadOrGhost("player")))
	end
	Out("zone text: zone %s, subzone %s, minimap %s, pvp %s", R(GetRealZoneText and GetRealZoneText()), R(GetSubZoneText and GetSubZoneText()),
		R(GetMinimapZoneText and GetMinimapZoneText()), All(C_PvP and C_PvP.GetZonePVPInfo or GetZonePVPInfo))
end

-- ---------------------------------------------------------------------------------------
-- Hidden messages between players

local function ResultName(value)
	if type(value) ~= "number" or ns.Secret(value) then return V(value) end
	for name, v in pairs(Enum and Enum.SendAddonMessageResult or {}) do
		if v == value then return name end
	end
	return tostring(value)
end

-- "x:y:map" for a message, or "?" when the position can't be read.
local function Payload()
	local x, y, map = Where("player")
	if not x then return "?:?:?" end
	return ("%.1f:%.1f:%d"):format(x, y, map or -1)
end

local function Send(kind, id, channel, target)
	local message = ("%s:%s:%s"):format(kind, id, Payload())
	local got = { pcall(C_ChatInfo.SendAddonMessage, PREFIX, message, channel, target) }
	if not got[1] then return "FAILS (" .. FirstLine(got[2]) .. ")" end
	return ResultName(got[2])
end

-- This player's name with the realm on it: the bare name gets "No player named ... is
-- currently playing" on this client.
local function FullName()
	local name, realm = UnitFullName("player")
	if not realm or realm == "" then realm = GetNormalizedRealmName and GetNormalizedRealmName() end
	return (realm and realm ~= "") and (name .. "-" .. realm) or name
end

local whisperDead = false -- a whisper to yourself never came back: stop trying, it prints an error

local function MessageTest(moment)
	local channels = {}
	if whisperDead then
		Out("message to yourself: skipped, the first one never came back")
	else
		channels[1] = { "WHISPER", FullName() }
	end
	local group = GroupChannel()
	if group then channels[#channels + 1] = { group } end
	for _, c in ipairs(channels) do
		sentCount = sentCount + 1
		local id = token .. sentCount
		local result = Send("Q", id, c[1], c[2])
		-- sent: the client took it, so not hearing it back means the channel doesn't deliver
		pending[id] = { at = GetTime(), channel = c[1], moment = moment, answers = 0, sent = result == "Success" }
		Out("message %s on %s: send %s (payload had a position: %s)", id, c[1], result, tostring(Payload() ~= "?:?:?"))
	end
	C_Timer.After(ECHO_WAIT, function()
		for id, p in pairs(pending) do
			if GetTime() - p.at >= ECHO_WAIT - 0.1 then
				if not p.echo then
					Out("message %s on %s (%s): never came back", id, p.channel, p.moment)
					if p.channel == "WHISPER" and p.sent then whisperDead = true end
				end
				if p.channel ~= "WHISPER" then
					Out("message %s on %s: %d answers from other players with the addon", id, p.channel, p.answers)
				end
				pending[id] = nil
			end
		end
	end)
end

-- The group unit a message came from, by name. Nothing about it is written down.
local function UnitOfSender(sender)
	if ns.Secret(sender) or type(sender) ~= "string" then return nil end
	local short = Ambiguate and Ambiguate(sender, "short") or sender:match("^[^-]+")
	for _, unit in ipairs(GroupUnits()) do
		local name = UnitName(unit)
		if name and not ns.Secret(name) and name == short then return unit end
	end
end

local function Heard(message, channel, sender)
	local kind, id, sx, sy, smap = message:match("^(%a):([^:]+):([^:]+):([^:]+):([^:]+)$")
	if not kind then return end
	local mine = id:sub(1, #token) == token
	if kind == "Q" then
		if mine then
			local p = pending[id]
			if p and not p.echo then
				p.echo = true
				Out("message %s on %s: came back after %.2f s, sender %s, in combat %s", id, p.channel, GetTime() - p.at, R(sender),
					tostring(InCombatLockdown()))
			end
		elseif channel ~= "WHISPER" and GetTime() - lastAnswer >= ANSWER_GAP then
			-- Another player's probe: answer with where this player is, to the same group channel.
			lastAnswer = GetTime()
			pcall(C_ChatInfo.SendAddonMessage, PREFIX, ("A:%s:%s"):format(id, Payload()), channel)
		end
	elseif kind == "A" and mine and pending[id] then
		local p = pending[id]
		p.answers = p.answers + 1
		local theirX, theirY, theirMap = tonumber(sx), tonumber(sy), tonumber(smap)
		local px, py, pmap = Where("player")
		local byMessage, byClient = "-", "-"
		if theirX and px then
			byMessage = (theirMap == pmap) and ("%.1f"):format(Yards(px, py, theirX, theirY)) or "other map"
		end
		local unit = UnitOfSender(sender)
		if unit and px then
			local ux, uy, umap = Where(unit)
			if ux then byClient = (umap == pmap) and ("%.1f"):format(Yards(px, py, ux, uy)) or "other map" end
		end
		Out("answer to %s after %.2f s: they could read their position %s, yards by message %s, yards by the client %s, sender matched a unit %s",
			id, GetTime() - p.at, tostring(theirX ~= nil), byMessage, byClient, tostring(unit ~= nil))
	end
end

comm:RegisterEvent("CHAT_MSG_ADDON")
comm:SetScript("OnEvent", function(_, _, prefix, message, channel, sender)
	if ns.Secret(prefix) or prefix ~= PREFIX then return end
	if ns.Secret(message) or ns.Secret(channel) then
		if armed then Out("a message arrived with SECRET contents (message %s, channel %s)", V(message), V(channel)) end
		return
	end
	local ok, err = pcall(Heard, message, channel, sender)
	if not ok and armed then Out("reading a message broke: %s", FirstLine(err)) end
end)
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
	pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
end

-- ---------------------------------------------------------------------------------------

local function Place()
	local inInstance, kind = IsInInstance()
	local _, _, difficulty, _, maxPlayers, _, _, instanceID = GetInstanceInfo()
	return ("instance %s (%s), difficulty %s, max players %s, instance id %s"):format(tostring(inInstance), tostring(kind),
		V(difficulty), V(maxPlayers), V(instanceID))
end

local function Probe(moment, full)
	Out("===== %s =====", moment)
	Out("%s, in combat %s, encounter %s", Place(), tostring(InCombatLockdown()),
		tostring(IsEncounterInProgress and IsEncounterInProgress() or false))
	Out("restrictions: %s", Restrictions())
	local mapID = PositionReport()
	if mapID then
		local ok, err = pcall(MapArtReport, mapID)
		if not ok then Out("map art report broke: %s", FirstLine(err)) end
	end
	for name, fn in pairs({ group = GroupReport, live = LiveReport, minimap = MinimapReport }) do
		local ok, err = pcall(fn, mapID)
		if not ok then Out("%s report broke: %s", name, FirstLine(err)) end
	end
	if full then
		local ok, err = pcall(ApiReport)
		if not ok then Out("api report broke: %s", FirstLine(err)) end
	end
	local ok, err = pcall(MessageTest, moment)
	if not ok then Out("message test broke: %s", FirstLine(err)) end
end

local function SafeProbe(moment, full)
	local ok, err = pcall(Probe, moment, full)
	if not ok then Out("probe broke at '%s': %s", moment, tostring(err)) end
end

local function CheckDone()
	if fightsLeft <= 0 and placesLeft <= 0 and armed then
		armed = false
		frame:UnregisterAllEvents()
		ns.Print("map probe finished. /reload to save the log.")
	end
end

-- A new place: after a loading screen, or stepping indoors or out.
local function NewPlace(why)
	if placesLeft <= 0 then return end
	local now = Place() .. " indoors " .. tostring(IsIndoors and IsIndoors())
	if now == lastPlace then return end
	lastPlace = now
	placesLeft = placesLeft - 1
	SafeProbe(why)
	CheckDone()
end

frame:SetScript("OnEvent", function(_, event, ...)
	if event == "PLAYER_REGEN_DISABLED" then
		if fightsLeft <= 0 then return end
		Out("--- fight starts ---")
		C_Timer.After(IN_COMBAT_AT, function()
			if InCombatLockdown() then SafeProbe(("IN COMBAT, %d s in"):format(IN_COMBAT_AT)) else Out("fight ended before the in-combat reading") end
		end)
	elseif event == "PLAYER_REGEN_ENABLED" then
		if fightsLeft <= 0 then return end
		fightsLeft = fightsLeft - 1
		C_Timer.After(1, function()
			SafeProbe("COMBAT ENDED, 1 s after")
			if fightsLeft > 0 then ns.Print(("map probe: fight recorded, %d more to go."):format(fightsLeft)) end
			CheckDone()
		end)
	elseif event == "PLAYER_ENTERING_WORLD" then
		C_Timer.After(3, function() NewPlace("AFTER A LOADING SCREEN") end)
	elseif event == "ZONE_CHANGED_INDOORS" or event == "ZONE_CHANGED_NEW_AREA" then
		C_Timer.After(1, function() NewPlace(event) end)
	elseif event == "PLAYER_DEAD" or event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
		C_Timer.After(1, function() SafeProbe(event) end)
	elseif event == "ADDON_ACTION_FORBIDDEN" or event == "ADDON_ACTION_BLOCKED" then
		-- The client raises these inside the offending call, so the last line says where.
		local addon, what = ...
		if addon == "SanctuaryUI" then
			local after = lastLine
			Out("%s on %s, right after the line: %s", event, tostring(what), after)
		end
	end
end)

-- /sanctuary map probe: read everything now, then record the next fights and places. Running
-- it again while it records takes one more reading on the spot.
function ns.MapProbe.Run()
	if armed then
		SafeProbe(InCombatLockdown() and "ASKED FOR (in combat)" or "ASKED FOR")
		ns.Print("map probe: read once more here.")
		return
	end
	armed = true
	fightsLeft, placesLeft = FIGHTS, PLACES
	lastPlace = Place() .. " indoors " .. tostring(IsIndoors and IsIndoors())
	for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_INDOORS",
		"ZONE_CHANGED_NEW_AREA", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "ADDON_ACTION_FORBIDDEN", "ADDON_ACTION_BLOCKED" }) do
		local ok, result = pcall(frame.RegisterEvent, frame, event)
		if not ok or result == false then Out("could not register %s: %s", event, tostring(result)) end
	end
	SafeProbe(InCombatLockdown() and "NOW (in combat)" or "NOW (out of combat)", true)
	ns.Print(("map probe: read once now, and recording your next %d fights and each new place you enter (dungeon, building, cave). "
		.. "Type it again anywhere for an extra reading. /reload saves the log."):format(FIGHTS))
end

-- /sanctuary map peek: the minimap doubled and see-through for a few seconds, to see with your
-- own eyes whether its terrain goes transparent here (indoors it may not).
local peeking = false
function ns.MapProbe.Peek()
	if peeking or not Minimap then return end
	if InCombatLockdown() then
		ns.Print("map peek: not in combat.")
		return
	end
	peeking = true
	local alpha, scale = Minimap:GetAlpha(), Minimap:GetScale()
	Out("peek: %s, indoors %s, set alpha %s, set scale %s", Place(), V(IsIndoors and IsIndoors()),
		Try(function() Minimap:SetAlpha(0.4) end), Try(function() Minimap:SetScale(scale * 2) end))
	ns.Print(("map peek: the minimap is doubled and 40%% see-through for %d seconds. Can you see the world through its terrain?"):format(PEEK_SECONDS))
	C_Timer.After(PEEK_SECONDS, function()
		peeking = false
		Out("peek: restore alpha %s, scale %s (in combat %s)", Try(function() Minimap:SetAlpha(alpha) end),
			Try(function() Minimap:SetScale(scale) end), tostring(InCombatLockdown()))
	end)
end

-- /sanctuary map check: why the corner map looks the way it does right here. Written for the
-- places where it goes dark: what the game says about this spot's minimap, and every frame
-- that hangs on it.
local function Describe(frame)
	if not frame then return "missing" end
	local parent = frame.GetParent and frame:GetParent()
	local w, h = frame:GetSize()
	return ("shown %s, visible %s, alpha %s, %s x %s, strata %s, level %s, parent %s"):format(tostring(frame:IsShown()),
		tostring(frame:IsVisible()), V(frame:GetAlpha()), V(w), V(h), tostring(frame.GetFrameStrata and frame:GetFrameStrata()),
		tostring(frame.GetFrameLevel and frame:GetFrameLevel()), tostring(parent and (parent:GetName() or "unnamed")))
end

function ns.MapProbe.Check()
	Out("===== CHECK =====")
	Out("%s, indoors %s, style %s", Place(), V(IsIndoors and IsIndoors()), tostring(ns.DB().map.style))
	Out("zoom %s of %s, view radius %s, hybrid wanted %s, ground textures %s, minimap map id %s, best map %s",
		All(Minimap.GetZoom, Minimap), All(Minimap.GetZoomLevels, Minimap), All(C_Minimap and C_Minimap.GetViewRadius),
		All(C_Minimap and C_Minimap.ShouldUseHybridMinimap), All(C_Minimap and C_Minimap.GetDrawGroundTextures),
		All(C_Minimap and C_Minimap.GetUiMapID), All(C_Map.GetBestMapForUnit, "player"))
	local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
	Out("Blizzard_HybridMinimap loaded: %s", loaded and All(loaded, "Blizzard_HybridMinimap") or "unknown")
	Out("Minimap: %s", Describe(Minimap))
	Out("HybridMinimap: %s", Describe(HybridMinimap))
	if HybridMinimap then
		Out("  its canvas: %s", Describe(HybridMinimap.MapCanvas))
		for i = 1, HybridMinimap:GetNumPoints() do
			local point, rel, relPoint, x, y = HybridMinimap:GetPoint(i)
			Out("  point %d: %s to %s %s, %s, %s", i, tostring(point), tostring(rel and (rel:GetName() or "unnamed")), tostring(relPoint), V(x), V(y))
		end
	end
	Out("MinimapCluster: %s", Describe(MinimapCluster))
	-- The game's minimap frames, two levels down: whatever draws a city's floor plan may be a
	-- neighbour of the Minimap frame rather than part of it.
	local function Family(frame, label, depth)
		if not frame or not frame.GetChildren then return end
		for _, child in ipairs({ frame:GetChildren() }) do
			local key
			for k, v in pairs(frame) do if v == child then key = k break end end
			Out("  %s child %s / %s (%s): %s", label, tostring(child:GetName() or "unnamed"), tostring(key or "-"), child:GetObjectType(), Describe(child))
			if depth > 1 and child ~= Minimap then Family(child, label .. ">", depth - 1) end
		end
	end
	Family(MinimapCluster, "cluster", 2)
	Out("MinimapBackdrop: %s", Describe(MinimapBackdrop))
	local n = 0
	for _, child in ipairs({ Minimap:GetChildren() }) do
		local name = child:GetName()
		-- Pins come by the dozen; name the kinds, not each one.
		if not (name and (name:find("^Questie") or name:find("Pin"))) then
			n = n + 1
			if n <= 30 then Out("  child %s (%s): %s", tostring(name or "unnamed"), child:GetObjectType(), Describe(child)) end
		end
	end
	for _, region in ipairs({ Minimap:GetRegions() }) do
		Out("  region %s (%s): shown %s, alpha %s, layer %s, texture %s", tostring(region:GetName() or "unnamed"), region:GetObjectType(),
			tostring(region:IsShown()), V(region:GetAlpha()), tostring(region.GetDrawLayer and region:GetDrawLayer()),
			tostring(region.GetTexture and region:GetTexture()))
	end
	ns.Print("map check written. /reload to save the log.")
end
