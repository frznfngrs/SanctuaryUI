SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.MeterHistory = ns.MeterHistory or {}

-- Saved fights. The client forgets all but its last 30 and nothing survives a reset, so each
-- fight is written down the moment its numbers can be read (half a second after combat, see
-- Meter.lua), per character. Records, streaks, the rival's tally and the run awards
-- (MeterGlory.lua) and the analysis window's older fights (MeterAnalysis.lua) all read from here.
--
-- One fight: t (time()), dur, name, zone, sid + epoch (which of the client's sessions it was),
-- run (the instance visit), boss + kill when an encounter ended in it, size (players in it),
-- p = players { n name, c class, me, d damage, dps, h healing, t taken, i interrupts, x dispels,
-- a avoidable damage, b absorbs, k deaths }, largest damage first, and mine = your top abilities { id, v }.

local H = ns.MeterHistory
local KEEP_DEFAULT, KEEP_MAX = 50, 250 -- fights kept per character (the "Fights kept" option)
local MIN_SECONDS = 5 -- shorter than this is not a fight worth keeping
local RECORD_SECONDS = 30 -- a personal best needs a fight at least this long, unless it is a boss
local STREAK_SECONDS = 15
local MY_ABILITIES = 12

local KINDS = {
	{ "DamageDone", "d" }, { "HealingDone", "h" }, { "DamageTaken", "t" }, { "Interrupts", "i" },
	{ "Dispels", "x" }, { "AvoidableDamageTaken", "a" }, { "Absorbs", "b" },
}

local function Secret(value) return ns.Secret(value) end

local function Store()
	local char = ns.db and ns.db.char
	if not char then return nil end
	char.meter = char.meter or {}
	local m = char.meter
	m.fights, m.bests = m.fights or {}, m.bests or {}
	m.streak, m.epoch, m.run = m.streak or 0, m.epoch or 0, m.run or 0
	m.rivalWins, m.rivalLosses = m.rivalWins or 0, m.rivalLosses or 0
	return m
end
H.Store = Store

-- An encounter that ended during the fight being recorded.
local encounter

local function Key(s)
	return s.sourceGUID or (s.sourceCreatureID and ("c" .. s.sourceCreatureID)) or s.name
end

-- Everyone in the current fight with their totals, or nil while anything is secret.
local function Snapshot()
	local L = ns.Meter.Lib
	local byKey, list = {}, {}
	for _, kind in ipairs(KINDS) do
		local session = L.Fetch("current", Enum.DamageMeterType[kind[1]])
		for _, s in ipairs(session and session.combatSources or {}) do
			if Secret(s.totalAmount) or Secret(s.name) or Secret(s.sourceGUID) or Secret(s.sourceCreatureID) then return nil end
			-- Players only: pets and guardians are already counted under their owners.
			if L.IsPlayerClass(s.classFilename) then
				local key = Key(s)
				local p = key and byKey[key]
				if key and not p then
					p = { n = s.name, c = s.classFilename, me = (not Secret(s.isLocalPlayer) and s.isLocalPlayer) and true or nil, guid = s.sourceGUID }
					byKey[key] = p
					list[#list + 1] = p
				end
				if p then
					p[kind[2]] = s.totalAmount
					if kind[2] == "d" and not Secret(s.amountPerSecond) then p.dps = s.amountPerSecond end
				end
			end
		end
	end
	local deaths = L.Fetch("current", Enum.DamageMeterType.Deaths)
	for _, s in ipairs(deaths and deaths.combatSources or {}) do
		if Secret(s.name) or Secret(s.sourceGUID) then return nil end
		local p = byKey[Key(s) or false]
		if p then p.k = (p.k or 0) + 1 end
	end
	table.sort(list, function(a, b) return (a.d or 0) > (b.d or 0) end)
	return list
end

local function MyAbilities(guid)
	local L = ns.Meter.Lib
	local data = L.FetchSource("current", Enum.DamageMeterType.DamageDone, guid or UnitGUID("player"), nil)
	if not data then return nil end
	local list = {}
	for _, spell in ipairs(data.combatSpells) do
		if Secret(spell.totalAmount) or Secret(spell.spellID) then return nil end
		list[#list + 1] = { id = spell.spellID, v = spell.totalAmount }
	end
	table.sort(list, function(a, b) return a.v > b.v end)
	for i = #list, MY_ABILITIES + 1, -1 do list[i] = nil end
	return list
end

local function Find(players, test)
	for i, p in ipairs(players) do
		if test(p) then return p, i end
	end
end

-- Does a saved name belong to the rival typed in the options? Full name or first name, any case.
local function IsRival(name, rival)
	if not rival or rival == "" or not name then return false end
	name, rival = name:lower(), rival:lower():match("^%s*(.-)%s*$")
	if rival == "" then return false end
	return name == rival or name:match("^(%S+)") == rival
end
H.IsRival = IsRival

-- What a record is measured against: the boss by name, or else solo and group fights apart.
local function BestKey(fight)
	if fight.boss then return "boss:" .. fight.boss, fight.boss end
	if (fight.dur or 0) < RECORD_SECONDS then return nil end
	if fight.size > 1 then return "group", "a group fight" end
	return "solo", "a solo fight"
end
H.BestKey = BestKey

-- Write the fight that just ended. Returns the record and what it meant:
--   outcome.rank, outcome.size, outcome.lead (the other name: second place when you won, first
--   when you didn't), outcome.margin (share ahead or behind), outcome.best { dps, was, label },
--   outcome.bestStands { dps, label }, outcome.streak, outcome.rival { name, won, wins, losses }.
-- Nil when there was nothing new to save.
function H.Record()
	local m = Store()
	local L = ns.Meter and ns.Meter.Lib
	if not m or not L or not L.Available() then return nil end
	if ns.DB().meter.history == false then return nil end
	local players = Snapshot()
	if not players then return nil end
	local me, rank = Find(players, function(p) return p.me end)
	if not me or ((me.d or 0) == 0 and (me.h or 0) == 0) then return nil end
	local dur = L.Duration("current")
	if dur == nil or Secret(dur) or dur < MIN_SECONDS then return nil end

	-- Which of the client's sessions this is. The same one twice (combat that dealt no damage
	-- leaves the last fight as "current") is not a new fight.
	local sessions = L.Sessions()
	local last = sessions[#sessions]
	local sid = last and not Secret(last.sessionID) and last.sessionID or nil
	local newest = m.fights[#m.fights]
	if newest and sid and newest.sid == sid and newest.epoch == m.epoch then return nil end
	if newest and sid and newest.epoch == m.epoch and newest.sid and sid < newest.sid then
		m.epoch = m.epoch + 1 -- the client's numbering started over
	end

	local fight = {
		t = time(), dur = dur, sid = sid, epoch = m.epoch, run = m.inRun and m.run or nil,
		name = last and not Secret(last.name) and last.name ~= "" and last.name or nil,
		zone = GetRealZoneText and GetRealZoneText() or nil,
		size = #players, p = players,
	}
	if encounter then
		fight.boss, fight.kill = encounter.name, encounter.kill
		encounter = nil
	end
	fight.mine = MyAbilities(me.guid)
	for _, p in ipairs(players) do p.guid = nil end
	m.fights[#m.fights + 1] = fight
	H.Trim()

	local outcome = { rank = rank, size = fight.size, dps = me.dps }
	if fight.size > 1 and (me.d or 0) > 0 then
		local other = players[rank == 1 and 2 or 1]
		outcome.lead = other.n
		outcome.leadClass = other.c
		if rank == 1 then
			outcome.margin = (other.d or 0) > 0 and (me.d / other.d - 1) or nil
		else
			outcome.margin = 1 - me.d / other.d
		end
	end

	-- Personal best: your damage per second against the same boss, or the same kind of fight.
	local key, label = BestKey(fight)
	if key and me.dps and me.dps > 0 and (fight.kill ~= false) then
		local best = m.bests[key]
		if not best then
			m.bests[key] = { dps = me.dps, t = fight.t, n = 1 }
		else
			best.n = (best.n or 1) + 1
			-- Open-world fights need a few tries behind them before a best means anything.
			local seasoned = fight.boss or best.n > 3
			if me.dps > best.dps * 1.01 then
				if seasoned then outcome.best = { dps = me.dps, was = best.dps, label = label } end
				best.dps, best.t = me.dps, fight.t
			else
				outcome.bestStands = { dps = best.dps, label = label }
			end
		end
	end

	-- Streak: group fights of some length where you finished on top.
	if fight.size > 1 and dur >= STREAK_SECONDS then
		m.streak = rank == 1 and (m.streak + 1) or 0
	end
	outcome.streak = m.streak

	local rivalName = ns.DB().meter.rival
	local rival = Find(players, function(p) return not p.me and IsRival(p.n, rivalName) end)
	if rival and dur >= STREAK_SECONDS then
		local won = (me.d or 0) > (rival.d or 0)
		if won then m.rivalWins = m.rivalWins + 1 else m.rivalLosses = m.rivalLosses + 1 end
		outcome.rival = { name = rival.n, class = rival.c, won = won, wins = m.rivalWins, losses = m.rivalLosses }
	end
	return fight, outcome
end

---------------------------------------------------------------------------
-- Reading it back

-- Drop the oldest fights beyond the number kept. Bests, the streak and the rival's tally stay.
function H.Trim()
	local m = Store()
	if not m then return end
	local keep = math.max(1, math.min(KEEP_MAX, tonumber(ns.DB().meter.historyKeep) or KEEP_DEFAULT))
	while #m.fights > keep do table.remove(m.fights, 1) end
end

function H.Fights()
	local m = Store()
	return m and m.fights or {}
end

-- Saved fights the client no longer has, newest first (MeterAnalysis lists them under its own).
function H.Older()
	local m = Store()
	if not m then return {} end
	local live = {}
	for _, s in ipairs(ns.Meter.Lib.Sessions()) do
		if not Secret(s.sessionID) then live[s.sessionID] = true end
	end
	local list = {}
	for i = #m.fights, 1, -1 do
		local f = m.fights[i]
		if not (f.epoch == m.epoch and f.sid and live[f.sid]) then list[#list + 1] = f end
	end
	return list
end

-- The saved record of one of the analysis window's fights: "current", a session ID, or a
-- saved fight itself. Nil for "overall" and for fights that were never saved.
function H.RecordFor(seg)
	local m = Store()
	if not m then return nil end
	if type(seg) == "table" then return seg end
	local sid = seg
	if seg == "current" then
		local sessions = ns.Meter.Lib.Sessions()
		local last = sessions[#sessions]
		sid = last and not Secret(last.sessionID) and last.sessionID or nil
	end
	if type(sid) ~= "number" then return nil end
	for i = #m.fights, 1, -1 do
		local f = m.fights[i]
		if f.sid == sid and f.epoch == m.epoch then return f end
	end
end

-- The other way: what to ask the client for (its session ID) while it still has the fight,
-- else the record itself.
function H.SegFor(fight)
	local m = Store()
	if m and fight.sid and fight.epoch == m.epoch then
		for _, s in ipairs(ns.Meter.Lib.Sessions()) do
			if not Secret(s.sessionID) and s.sessionID == fight.sid then return fight.sid end
		end
	end
	return fight
end

local function MyDps(fight)
	for _, p in ipairs(fight.p) do
		if p.me then return p.dps or (fight.dur and fight.dur > 0 and (p.d or 0) / fight.dur) or 0 end
	end
	return 0
end
H.MyDps = MyDps

-- The same boss; failing a boss, the same named enemy in the same company (solo or group).
local function SameFight(a, b)
	if a.boss or b.boss then return a.boss == b.boss end
	return a.name ~= nil and a.name == b.name and (a.size > 1) == (b.size > 1)
end

-- Earlier attempts at the same fight: your best one and your last one (either may be nil).
function H.Earlier(fight)
	local m = Store()
	if not m then return nil end
	local best, last
	for _, f in ipairs(m.fights) do
		if f == fight then break end
		if SameFight(f, fight) and f.mine then
			last = f
			if not best or MyDps(f) > MyDps(best) then best = f end
		end
	end
	return best, last
end

-- Your damage per second over the last saved fights, oldest first.
function H.Trend(count)
	local m = Store()
	local list = {}
	if not m then return list end
	for i = math.max(1, #m.fights - count + 1), #m.fights do
		local f = m.fights[i]
		list[#list + 1] = { fight = f, dps = MyDps(f), group = f.size > 1 }
	end
	return list
end

function H.BestFor(fight)
	local m = Store()
	local key, label = BestKey(fight)
	local best = m and key and m.bests[key]
	if best then return best.dps, label, best.t end
end

-- Awards for one instance visit: who led each tally across its fights. Nil with too little to go on.
function H.Awards(run)
	local m = Store()
	if not m then return nil end
	run = run or m.run
	local totals, order, fights, topped = {}, {}, 0, 0
	for _, f in ipairs(m.fights) do
		if f.run == run and f.size > 1 then
			fights = fights + 1
			if f.p[1] and f.p[1].me then topped = topped + 1 end
			for _, p in ipairs(f.p) do
				local t = totals[p.n]
				if not t then
					t = { n = p.n, c = p.c, me = p.me }
					totals[p.n] = t
					order[#order + 1] = t
				end
				for _, k in ipairs({ "d", "h", "t", "i", "x", "a", "k" }) do
					t[k] = (t[k] or 0) + (p[k] or 0)
				end
			end
		end
	end
	if fights < 3 or #order < 2 then return nil end
	local function Most(k)
		local top
		for _, t in ipairs(order) do
			if (t[k] or 0) > 0 and (not top or t[k] > top[k]) then top = t end
		end
		return top
	end
	local awards = {}
	for _, a in ipairs({
		{ "d", "Most damage" }, { "h", "Most healing" }, { "i", "Most interrupts" }, { "x", "Most dispels" },
		{ "t", "Took the most damage" }, { "a", "Stood in the most avoidable damage" }, { "k", "Died the most" },
	}) do
		local top = Most(a[1])
		if top then awards[#awards + 1] = { title = a[2], name = top.n, class = top.c, me = top.me, value = top[a[1]], count = a[1] == "i" or a[1] == "x" or a[1] == "k" } end
	end
	return awards, fights, topped
end

function H.Clear()
	local m = Store()
	if not m then return end
	m.fights, m.bests, m.streak, m.rivalWins, m.rivalLosses = {}, {}, 0, 0, 0
end

function H.ResetRival()
	local m = Store()
	if m then m.rivalWins, m.rivalLosses = 0, 0 end
end

function H.Init()
	Store()
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "ENCOUNTER_START", "ENCOUNTER_END", "DAMAGE_METER_RESET", "PLAYER_ENTERING_WORLD" }) do
		pcall(events.RegisterEvent, events, event)
	end
	events:SetScript("OnEvent", function(_, event, ...)
		local m = Store()
		if not m then return end
		if event == "ENCOUNTER_START" then
			encounter = nil
		elseif event == "ENCOUNTER_END" then
			local _, name, _, _, success = ...
			if name ~= nil and not Secret(name) then
				encounter = { name = name, kill = not Secret(success) and (success == 1 or success == true) or nil }
			end
		elseif event == "DAMAGE_METER_RESET" then
			m.epoch = m.epoch + 1
		elseif event == "PLAYER_ENTERING_WORLD" then
			-- A new instance visit starts a new run; leaving one ends it (MeterGlory hands out the awards).
			local inside, kind = false, nil
			if IsInInstance then inside, kind = IsInInstance() end
			inside = inside and (kind == "party" or kind == "raid") or false
			local was = m.inRun -- saved, so a /reload inside the instance doesn't start a new run
			if inside and not was then m.run = m.run + 1 end
			m.inRun = inside or nil
			if was and not inside and ns.MeterGlory and ns.MeterGlory.RunEnded then
				pcall(ns.MeterGlory.RunEnded, m.run)
			end
		end
	end)
end
