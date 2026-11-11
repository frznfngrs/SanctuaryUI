-- Damage meter probe (/sanctuary meter probe). This only writes down what the client's
-- C_DamageMeter lets an addon read, out of combat, a few seconds into a fight, the moment it
-- ends, and once the secret values drop. Meter.lua is built on what this found.
-- Player names and GUIDs are never written, only whether they could be read.
SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI

ns.MeterProbe = {}

local FIGHTS = 3 -- fights to record after the command
local IN_COMBAT_AT = 4 -- seconds into a fight for the in-combat reading
local DROP_STEP, DROP_LIMIT = 0.5, 30 -- how often and how long to wait for secrets to drop
local SOURCES_SHOWN = 3

local frame = CreateFrame("Frame")
local bar, text -- hidden widgets for the display tests
local fightsLeft = 0
local updates, firstUpdateSecret = 0, nil
local cleuOn, cleuSeen = false, 0
local lastRank
local dropTicker
local lastLine = "" -- the last line written, to place a blocked action

local function Out(fmt, ...)
	local was = ns.forceLog
	ns.forceLog = true
	ns.Log("meter: " .. fmt, ...)
	ns.forceLog = was
	lastLine = fmt
end

-- A value for the log: its text, or that it is secret.
local function V(value)
	if value == nil then return "nil" end
	if ns.Secret(value) then return "SECRET" end
	return tostring(value)
end

-- For names and GUIDs: readable or not, never the text.
local function R(value)
	if value == nil then return "nil" end
	if ns.Secret(value) then return "SECRET" end
	return "readable"
end

local function SecretTable(t)
	return issecrettable and issecrettable(t) or false
end

-- Run fn, report "ok" (with what it returned) or the error's first line.
local function Try(fn, ...)
	local ok, result = pcall(fn, ...)
	if ok then
		return result == nil and "ok" or ("ok -> " .. V(result))
	end
	return "FAILS (" .. tostring(result):match("[^\n]*"):sub(1, 110) .. ")"
end

local function Types()
	local list = {}
	for name, value in pairs(Enum and Enum.DamageMeterType or {}) do
		list[#list + 1] = { name = name, value = value }
	end
	table.sort(list, function(a, b) return a.value < b.value end)
	return list
end

-- Where the local player sits in a session's list, or why that can't be told.
local function MyRank(sources)
	for i = 1, #sources do
		local mine = sources[i].isLocalPlayer
		if ns.Secret(mine) then return nil, "isLocalPlayer is SECRET" end
		if mine then return i end
	end
	return nil, "not in the list"
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

-- Can the numbers be drawn, formatted, added up and compared?
local function DisplayTests(session, source)
	if not bar then
		bar = CreateFrame("StatusBar", nil, UIParent)
		bar:SetSize(1, 1)
		bar:Hide()
		text = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	end
	local total, top, sum = source.totalAmount, session.maxAmount, session.totalAmount
	Out("  draw: bar range %s, bar value %s", Try(function() bar:SetMinMaxValues(0, top) end), Try(function() bar:SetValue(total) end))
	Out("  text: AbbreviateLargeNumbers %s, format %%d %s, SetText %s",
		Try(function() return AbbreviateLargeNumbers(total) end),
		Try(function() return string.format("%d", total) end),
		Try(function() text:SetText(AbbreviateLargeNumbers(total)) end))
	Out("  maths: share of total %s, compare with top %s, per second %s",
		Try(function() return total / sum end),
		Try(function() return total >= top end),
		Try(function() return source.amountPerSecond + 0 end))
	Out("  name: SetText %s, format %s",
		Try(function() text:SetText(source.name) end),
		Try(function() local s = string.format("%d. %s", 1, source.name); return ns.Secret(s) and s or "built" end))
end

local function SpellReport(label, getter, sessionKey, typeValue, guid, creatureID)
	local ok, data = pcall(getter, sessionKey, typeValue, guid, creatureID)
	if not ok then
		Out("  spells of %s: FAILS (%s)", label, tostring(data):match("[^\n]*"):sub(1, 110))
		return
	end
	if type(data) ~= "table" then
		Out("  spells of %s: returned %s", label, V(data))
		return
	end
	local spells = data.combatSpells
	if type(spells) ~= "table" or SecretTable(spells) then
		Out("  spells of %s: list %s", label, SecretTable(spells) and "SECRET table" or V(spells))
		return
	end
	Out("  spells of %s: %d spells, total %s, max %s", label, #spells, V(data.totalAmount), V(data.maxAmount))
	local spell = spells[1]
	if spell then
		local d = spell.combatSpellDetails
		Out("    top spell: id %s, total %s, per second %s, overkill %s, avoidable %s, deadly %s, creature name %s",
			V(spell.spellID), V(spell.totalAmount), V(spell.amountPerSecond), V(spell.overkillAmount),
			V(spell.isAvoidable), V(spell.isDeadly), R(spell.creatureName))
		if type(d) == "table" then
			Out("    its target: name %s, class %s, amount %s, pet %s, mob %s, kind %s",
				R(d.unitName), V(d.unitClassFilename), V(d.amount), V(d.isPet), V(d.isMob), V(d.classification))
		else
			Out("    its target details: %s", V(d))
		end
	end
end

-- One session (overall, current, or a past fight by ID), every meter type.
local function SessionReport(label, getSession, getSource, key)
	for _, t in ipairs(Types()) do
		local ok, session = pcall(getSession, key, t.value)
		if not ok then
			Out("%s %s: FAILS (%s)", label, t.name, tostring(session):match("[^\n]*"):sub(1, 110))
		elseif type(session) ~= "table" then
			Out("%s %s: returned %s", label, t.name, V(session))
		else
			local sources = session.combatSources
			if type(sources) ~= "table" or SecretTable(sources) then
				Out("%s %s: source list %s", label, t.name, SecretTable(sources) and "SECRET table" or V(sources))
			else
				local rank, why = MyRank(sources)
				Out("%s %s: %d sources, total %s, max %s, duration %s, my rank %s", label, t.name, #sources,
					V(session.totalAmount), V(session.maxAmount), V(session.durationSeconds), rank and tostring(rank) or why)
				-- Full detail for damage only: the other types have the same shape.
				if t.name == "DamageDone" and #sources > 0 then
					for i = 1, math.min(#sources, SOURCES_SHOWN) do
						local s = sources[i]
						Out("  #%d: name %s, guid %s, creature %s, class %s, spec icon %s, total %s, per second %s, mine %s, kind %s, display %s, faction %s, death recap %s, death time %s",
							i, R(s.name), R(s.sourceGUID), V(s.sourceCreatureID), V(s.classFilename), V(s.specIconID),
							V(s.totalAmount), V(s.amountPerSecond), V(s.isLocalPlayer), V(s.classification),
							V(s.sourceDisplayType), V(s.factionGroup), V(s.deathRecapID), V(s.deathTimeSeconds))
					end
					local ok2, err = pcall(DisplayTests, session, sources[1])
					if not ok2 then Out("  display tests broke: %s", tostring(err)) end
					local top = sources[1]
					SpellReport("the top source (its own GUID)", getSource, key, t.value, top.sourceGUID, top.sourceCreatureID)
					SpellReport("me (UnitGUID)", getSource, key, t.value, UnitGUID("player"), nil)
				end
			end
		end
	end
end

local function Probe(moment)
	Out("===== %s =====", moment)
	if not C_DamageMeter then
		Out("C_DamageMeter does not exist on this client")
		return
	end
	local okA, available, reason = pcall(C_DamageMeter.IsDamageMeterAvailable)
	local getCVar = C_CVar and C_CVar.GetCVar or GetCVar
	Out("available %s (%s), damageMeterEnabled %s, in combat %s, encounter %s", okA and V(available) or "error", V(reason),
		V(getCVar and getCVar("damageMeterEnabled")), tostring(InCombatLockdown()),
		tostring(IsEncounterInProgress and IsEncounterInProgress() or false))
	Out("restrictions: %s", Restrictions())
	Out("combat log: restricted %s (its event is not asked for)",
		(C_CombatLog and C_CombatLog.IsCombatLogRestricted) and Try(C_CombatLog.IsCombatLogRestricted) or "no such function")

	local okS, sessions = pcall(C_DamageMeter.GetAvailableCombatSessions)
	local lastID
	if okS and type(sessions) == "table" then
		Out("%d past sessions", #sessions)
		for i = math.max(1, #sessions - 2), #sessions do
			local s = sessions[i]
			Out("  session id %s, name %s, duration %s", V(s.sessionID), R(s.name), V(s.durationSeconds))
			if not ns.Secret(s.sessionID) then lastID = s.sessionID end
		end
	else
		Out("session list: %s", okS and V(sessions) or tostring(sessions))
	end
	for name, value in pairs(Enum.DamageMeterSessionType or {}) do
		Out("duration of %s: %s", name, Try(C_DamageMeter.GetSessionDurationSeconds, value))
	end

	local st = Enum.DamageMeterSessionType or {}
	SessionReport("current", C_DamageMeter.GetCombatSessionFromType, C_DamageMeter.GetCombatSessionSourceFromType, st.Current or 1)
	SessionReport("overall", C_DamageMeter.GetCombatSessionFromType, C_DamageMeter.GetCombatSessionSourceFromType, st.Overall or 0)
	if lastID then
		SessionReport("session " .. tostring(lastID), C_DamageMeter.GetCombatSessionFromID, C_DamageMeter.GetCombatSessionSourceFromID, lastID)
	end
end

local function SafeProbe(moment)
	local ok, err = pcall(Probe, moment)
	if not ok then Out("probe broke at '%s': %s", moment, tostring(err)) end
end

-- True while the current fight's damage still has secret numbers in it.
local function StillSecret()
	local ok, session = pcall(C_DamageMeter.GetCombatSessionFromType, (Enum.DamageMeterSessionType or {}).Current or 1, Enum.DamageMeterType.DamageDone)
	if not ok or type(session) ~= "table" then return true end
	if ns.Secret(session.totalAmount) or SecretTable(session.combatSources) then return true end
	for _, s in ipairs(session.combatSources or {}) do
		if ns.Secret(s.totalAmount) or ns.Secret(s.name) or ns.Secret(s.sourceGUID) then return true end
	end
	return false
end

-- Each time the meter updates: is my place in the damage list readable, and did it change?
local function TrackRank()
	local ok, session = pcall(C_DamageMeter.GetCombatSessionFromType, (Enum.DamageMeterSessionType or {}).Current or 1, Enum.DamageMeterType.DamageDone)
	if not ok or type(session) ~= "table" or type(session.combatSources) ~= "table" or SecretTable(session.combatSources) then return end
	local okR, rank, why = pcall(MyRank, session.combatSources)
	local now = okR and (rank and (rank .. " of " .. #session.combatSources) or why) or "error"
	if now ~= lastRank then
		lastRank = now
		Out("rank change (in combat %s): %s", tostring(InCombatLockdown()), now)
	end
end

local function Finish()
	fightsLeft = fightsLeft - 1
	if fightsLeft <= 0 then
		frame:UnregisterAllEvents()
		cleuOn = false
		ns.Print("meter probe finished. /reload to save the log.")
	else
		ns.Print(("meter probe: fight recorded, %d more to go (or /reload now)."):format(fightsLeft))
	end
end

frame:SetScript("OnEvent", function(_, event, ...)
	if event == "PLAYER_REGEN_DISABLED" then
		updates, firstUpdateSecret, lastRank = 0, nil, nil
		if dropTicker then dropTicker:Cancel(); dropTicker = nil end
		Out("--- fight starts ---")
		C_Timer.After(IN_COMBAT_AT, function()
			if InCombatLockdown() then SafeProbe(("IN COMBAT, %d s in"):format(IN_COMBAT_AT)) else Out("fight ended before the in-combat reading") end
		end)
	elseif event == "PLAYER_REGEN_ENABLED" then
		Out("--- fight ends: %d meter updates during it, update payload %s, %d combat log events ---", updates, V(firstUpdateSecret), cleuSeen)
		SafeProbe("COMBAT JUST ENDED")
		local waited = 0
		dropTicker = C_Timer.NewTicker(DROP_STEP, function(ticker)
			waited = waited + DROP_STEP
			local secret = StillSecret()
			if secret and waited < DROP_LIMIT and not InCombatLockdown() then return end
			ticker:Cancel()
			dropTicker = nil
			if InCombatLockdown() then
				Out("back in combat before the secrets dropped (%.1f s)", waited)
				return
			end
			Out(secret and "secrets still there after %.1f s" or "secrets dropped %.1f s after combat", waited)
			SafeProbe("AFTER THE WAIT")
			Finish()
		end)
	elseif event == "DAMAGE_METER_COMBAT_SESSION_UPDATED" then
		updates = updates + 1
		if firstUpdateSecret == nil then
			local meterType, sessionID = ...
			firstUpdateSecret = ("type %s id %s"):format(V(meterType), V(sessionID))
		end
		pcall(TrackRank)
	elseif event == "DAMAGE_METER_CURRENT_SESSION_UPDATED" or event == "DAMAGE_METER_RESET" then
		Out("event %s (in combat %s)", event, tostring(InCombatLockdown()))
	elseif event == "ADDON_ACTION_FORBIDDEN" or event == "ADDON_ACTION_BLOCKED" then
		-- The client raises these inside the offending call, so the last line says where.
		local addon, what = ...
		if addon == "SanctuaryUI" then
			local after = lastLine
			Out("%s on %s, right after the line: %s", event, tostring(what), after)
		end
	elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
		cleuSeen = cleuSeen + 1
		if cleuSeen == 1 and CombatLogGetCurrentEventInfo then
			local got = { pcall(CombatLogGetCurrentEventInfo) }
			if got[1] then
				local secret = 0
				for i = 2, #got do if ns.Secret(got[i]) then secret = secret + 1 end end
				Out("combat log event: %d values, %d secret, subevent %s", #got - 1, secret, V(got[3]))
			else
				Out("combat log event: reading it FAILS (%s)", tostring(got[2]):match("[^\n]*"):sub(1, 110))
			end
		end
	end
end)

-- /sanctuary meter: read everything now, then record the next few fights.
function ns.MeterProbe.Run()
	fightsLeft = FIGHTS
	cleuSeen = 0
	for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "DAMAGE_METER_COMBAT_SESSION_UPDATED",
		"DAMAGE_METER_CURRENT_SESSION_UPDATED", "DAMAGE_METER_RESET", "ADDON_ACTION_FORBIDDEN", "ADDON_ACTION_BLOCKED" }) do
		-- Not COMBAT_LOG_EVENT_UNFILTERED: asking for it is itself a blocked action on this
		-- client (the "blocked from an action only available to the Blizzard UI" popup).
		local ok, result = pcall(frame.RegisterEvent, frame, event)
		if not ok or result == false then Out("could not register %s: %s", event, tostring(result)) end
	end
	SafeProbe(InCombatLockdown() and "NOW (in combat)" or "NOW (out of combat)")
	ns.Print(("meter probe: read once now, and recording your next %d fights. A message says when it is done."):format(FIGHTS))
end
