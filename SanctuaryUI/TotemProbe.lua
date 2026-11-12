-- Totem probe (/sanctuary map totems). Writes down what the client lets an addon read when a
-- group member casts, to learn whether another shaman's totems could be pinned on the ally
-- ring without them running SanctuaryUI: their cast's spell ID (is it a totem?) and their
-- position at that moment, in and out of combat. Your own totem casts are recorded too, to
-- check the ring's own pins. Player names are never written, only whether they could be read.
-- Records until the command is typed again or the UI reloads; /reload saves the log and writes
-- a summary line.
SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI

ns.TotemProbe = {}

local OTHER_PER_UNIT = 3 -- non-totem casts written per unit, in and out of combat each
local frame = CreateFrame("Frame")
local armed = false
local counts = {} -- "unit|combat|kind" -> count
local seen = { casts = 0, totems = 0, ids = 0, positions = 0, events = 0, secretUnit = 0 }
local otherUnits = {} -- unit kinds we skip (target, nameplate...): counted, written once each
local Summary -- below

local function Out(fmt, ...)
	local was = ns.forceLog
	ns.forceLog = true
	ns.Log("totems: " .. fmt, ...)
	ns.forceLog = was
end

local function V(value)
	if value == nil then return "nil" end
	if ns.Secret(value) then return "SECRET" end
	if type(value) == "number" and value ~= math.floor(value) then return ("%.1f"):format(value) end
	return tostring(value)
end

local function R(value)
	if value == nil then return "nil" end
	if ns.Secret(value) then return "SECRET" end
	return "readable"
end

local function Plain(value)
	return value ~= nil and not ns.Secret(value)
end

local function Restrictions()
	local parts = {}
	if C_RestrictedActions and C_RestrictedActions.GetAddOnRestrictionState and Enum.AddOnRestrictionType then
		for name, value in pairs(Enum.AddOnRestrictionType) do
			local ok, state = pcall(C_RestrictedActions.GetAddOnRestrictionState, value)
			if ok and Plain(state) and state ~= 0 then parts[#parts + 1] = name .. "=" .. tostring(state) end
		end
		table.sort(parts)
	end
	return #parts > 0 and table.concat(parts, " ") or "none"
end

local function Kind(unit)
	if not Plain(unit) then return nil end
	if unit == "player" then return "player" end
	if unit:match("^party%d$") or unit:match("^raid%d+$") then return "group" end
end

local function Where(unit)
	local ok, a, b, _, map = pcall(UnitPosition, unit)
	if not ok or not Plain(a) or not Plain(b) then return nil end
	return a, b, map
end

local function OnCast(unit, castGUID, spellID)
	seen.events = seen.events + 1
	if not Plain(unit) then
		-- A hidden unit token: can't tell whose cast it was. Written the first few times.
		seen.secretUnit = seen.secretUnit + 1
		if seen.secretUnit <= OTHER_PER_UNIT then
			Out("cast with a SECRET unit token (%s): spellID %s", InCombatLockdown() and "combat" or "calm", V(spellID))
		end
		return
	end
	local kind = Kind(unit)
	if not kind then
		local base = unit:gsub("%d+$", "")
		if not otherUnits[base] then
			otherUnits[base] = true
			Out("casts also come in for %s units (not recorded): spellID %s", base, V(spellID))
		end
		return
	end
	local combat = InCombatLockdown() and "combat" or "calm"
	local element, idOK = nil, Plain(spellID)
	if idOK then element = ns.Totem.ElementOfSpell(spellID) end
	if kind == "player" and not element then return end -- your own non-totem casts are known
	if kind == "group" then
		seen.casts = seen.casts + 1
		if idOK then seen.ids = seen.ids + 1 end
		if element then seen.totems = seen.totems + 1 end
	end
	local key = unit .. "|" .. combat .. "|" .. (element and "totem" or "other")
	counts[key] = (counts[key] or 0) + 1
	if not element and counts[key] > OTHER_PER_UNIT then return end

	local name
	if idOK then
		local ok, n = pcall(C_Spell and C_Spell.GetSpellName or GetSpellInfo, spellID)
		name = ok and n or nil
	end
	local _, class = UnitClass(unit)
	local north, west, map = Where(unit)
	if kind == "group" and north then seen.positions = seen.positions + 1 end
	local yards = "-"
	if kind == "group" and north then
		local pn, pw = Where("player")
		if pn then yards = ("%.1f"):format(math.sqrt((north - pn) ^ 2 + (west - pw) ^ 2)) end
	end
	local _, instanceType = IsInInstance()
	Out("%s %s cast (%s): spellID %s, name %s, totem %s, class %s, castGUID %s, position %s (map %s, %s yd from you), "
		.. "UnitIsVisible %s, %s, restrictions %s",
		kind == "player" and "you" or unit, combat, V(instanceType), V(spellID), Plain(name) and name or R(name),
		element and ns.Totem.ELEMENTS[element].key or "no", V(class), R(castGUID),
		north and "readable" or "nil", V(map), yards, V(UnitIsVisible(unit)),
		Plain(UnitIsDeadOrGhost(unit)) and (UnitIsDeadOrGhost(unit) and "dead" or "alive") or "dead?",
		Restrictions())
end

frame:SetScript("OnEvent", function(_, event, unit, castGUID, spellID)
	if event == "UNIT_SPELLCAST_SUCCEEDED" then
		local ok, err = pcall(OnCast, unit, castGUID, spellID)
		if not ok then Out("error reading a cast: %s", tostring(err):match("[^\n]*")) end
	elseif event == "PLAYER_LOGOUT" then
		Out("logout: %s", Summary())
	elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
		Out("%s", event == "PLAYER_REGEN_DISABLED" and "-- combat starts" or "-- combat ends")
	end
end)

Summary = function()
	return ("%d cast events in all, %d with a hidden unit; %d group casts seen, spell ID readable on %d, %d were totems, caster position readable on %d"):format(
		seen.events, seen.secretUnit, seen.casts, seen.ids, seen.totems, seen.positions)
end

-- Where each group member is from you when the probe starts: casts only arrive for members
-- the client can see, so a far one sends nothing.
local function GroupNow()
	for i = 1, 4 do
		local unit = "party" .. i
		if UnitExists(unit) then
			local north, west = Where(unit)
			local pn, pw = Where("player")
			local yards = (north and pn) and ("%.0f yd"):format(math.sqrt((north - pn) ^ 2 + (west - pw) ^ 2)) or "unknown"
			local _, class = UnitClass(unit)
			Out("%s: class %s, %s away, visible %s, connected %s", unit, V(class), yards, V(UnitIsVisible(unit)), V(UnitIsConnected(unit)))
		end
	end
end

function ns.TotemProbe.Run()
	if armed then
		armed = false
		frame:UnregisterAllEvents()
		Out("stopped: %s", Summary())
		ns.Print("totem probe off: " .. Summary() .. ". /reload saves the log.")
		return
	end
	armed = true
	wipe(counts)
	for k in pairs(seen) do seen[k] = 0 end
	wipe(otherUnits)
	for _, event in ipairs({ "UNIT_SPELLCAST_SUCCEEDED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_LOGOUT" }) do
		local ok, result = pcall(frame.RegisterEvent, frame, event)
		if not ok or result == false then Out("could not register %s: %s", event, tostring(result)) end
	end
	local _, instanceType = IsInInstance()
	Out("started: in group %s, raid %s, instance %s, combat %s, restrictions %s", V(IsInGroup()), V(IsInRaid()),
		V(instanceType), V(InCombatLockdown()), Restrictions())
	GroupNow()
	ns.Print("totem probe on: recording group members' casts (and your own totems), in and out of combat. "
		.. "Best with a shaman in your group dropping totems, out of combat then in a fight. "
		.. "Stand near them: casts only arrive for members you can see. /reload when done (that also writes a summary).")
end
