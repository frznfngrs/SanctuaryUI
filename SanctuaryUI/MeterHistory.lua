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
--
-- Runs (a visit to one dungeon or raid, for RunReport.lua) are kept apart in m.runs, so trimming
-- fights never takes one apart. One run: id, name (the instance), kind, diff, t0/t1 (door to
-- door), done, old (built from saved fights before runs were kept: no abilities or death times),
-- pulls = { t, dur, name, boss, kill, size, sid, epoch, gd (group damage), my (your dps), rank,
-- top/topc (who led), k (deaths), dp = name -> dps, and for bosses p (the players, as a fight's)
-- with best (your record after it) and nb (a new record) },
-- players = name -> { n, c, me, the fight tallies added up, sec (seconds fought), pulls,
-- sp = tally -> spellID -> { v, n (pulls it was used in), o (overkill), dl (killing blows),
-- av (avoidable), from (who it came from, for damage taken) } }, order (names, first seen first),
-- deaths = { pull, n, c, at (seconds into the pull), recap, by (killing spell), o, from }.

local H = ns.MeterHistory
local KEEP_DEFAULT, KEEP_MAX = 50, 250 -- fights kept per character (the "Fights kept" option)
local MIN_SECONDS = 5 -- shorter than this is not a fight worth keeping
local RECORD_SECONDS = 30 -- a personal best needs a fight at least this long, unless it is a boss
local STREAK_SECONDS = 15
local MY_ABILITIES = 12
H.MY_ABILITIES = MY_ABILITIES
local RUNS_DEFAULT, RUNS_MAX = 20, 50 -- runs kept per character (the "Runs kept" option)
local TALLY = { "d", "h", "t", "i", "x", "a", "b", "k" }

-- Everything the run report shows of each player, read for fights in a dungeon or raid: the
-- tally, its short key, and how many abilities to keep (killing blows are always kept).
local DEEP = {
	{ "DamageDone", "d", 16 }, { "HealingDone", "h", 16 }, { "DamageTaken", "t", 14 },
	{ "AvoidableDamageTaken", "a", 12 }, { "Absorbs", "b", 8 }, { "Interrupts", "i", 8 }, { "Dispels", "x", 8 },
}

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
	m.fights, m.bests, m.runs = m.fights or {}, m.bests or {}, m.runs or {}
	m.streak, m.epoch, m.run = m.streak or 0, m.epoch or 0, m.run or 0
	m.rivalWins, m.rivalLosses = m.rivalWins or 0, m.rivalLosses or 0
	return m
end
H.Store = Store

-- An encounter that ended during the fight being recorded, and how long after its end
-- (seconds) the fight may still be saved under it.
local encounter
-- The final boss died and its fight is still to be saved (see "The final boss" below).
local pendingFinal
local ENCOUNTER_WINDOW = 30

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
	local died = {}
	for _, s in ipairs(deaths and deaths.combatSources or {}) do
		if Secret(s.name) or Secret(s.sourceGUID) then return nil end
		local p = byKey[Key(s) or false]
		if p then
			p.k = (p.k or 0) + 1
			died[#died + 1] = {
				p = p,
				at = not Secret(s.deathTimeSeconds) and s.deathTimeSeconds or nil,
				recap = not Secret(s.deathRecapID) and s.deathRecapID ~= 0 and s.deathRecapID or nil,
			}
		end
	end
	table.sort(list, function(a, b) return (a.d or 0) > (b.d or 0) end)
	table.sort(died, function(a, b) return (a.at or 0) < (b.at or 0) end)
	return list, died
end

-- One player's abilities for every tally the run report shows, read right after a fight in a
-- dungeon or raid: short key -> { { id, v, o, dl, av, from } }, largest first. Nil while
-- anything is still secret.
local function Deep(guid)
	local L = ns.Meter.Lib
	if not guid then return nil end
	local out = {}
	for _, kind in ipairs(DEEP) do
		local data = L.FetchSource("current", Enum.DamageMeterType[kind[1]], guid, nil)
		local list = {}
		for _, spell in ipairs(data and data.combatSpells or {}) do
			if Secret(spell.totalAmount) or Secret(spell.spellID) then return nil end
			local e = { id = spell.spellID, v = spell.totalAmount }
			local over = spell.overkillAmount
			if over ~= nil and not Secret(over) and over > 0 then e.o = over end
			if spell.isDeadly ~= nil and not Secret(spell.isDeadly) and spell.isDeadly then e.dl = true end
			if spell.isAvoidable ~= nil and not Secret(spell.isAvoidable) and spell.isAvoidable then e.av = true end
			local d = spell.combatSpellDetails
			local other = type(d) == "table" and d.unitName or nil
			if (kind[2] == "t" or kind[2] == "a") and other ~= nil and not Secret(other) and other ~= "" then e.from = other end
			list[#list + 1] = e
		end
		-- Ranks of one ability (each its own spell ID) become one line, kept by name.
		local byName, merged = {}, {}
		for _, e in ipairs(list) do
			local ok, name = pcall(ns.Meter.Lib.GetSpellName, e.id)
			e.key = ok and name ~= nil and not Secret(name) and name ~= "" and name or e.id
			local into = byName[e.key]
			if into then
				if e.v > into.v then into.id, into.from = e.id, e.from or into.from end
				into.v = into.v + e.v
				if e.o then into.o = (into.o or 0) + e.o end
				into.dl = into.dl or e.dl
				into.av = into.av or e.av
			else
				byName[e.key] = e
				merged[#merged + 1] = e
			end
		end
		list = merged
		table.sort(list, function(a, b) return a.v > b.v end)
		local kept = {}
		for i, e in ipairs(list) do
			if i <= kind[3] or e.dl then kept[#kept + 1] = e end
		end
		if #kept > 0 then out[kind[2]] = kept end
	end
	return out
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
	local players, died = Snapshot()
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
		t = time(), dur = dur, sid = sid, epoch = m.epoch,
		-- Not a fight outside while the run is held for the way back in.
		run = m.inRun and IsInInstance and IsInInstance() and m.run or nil,
		name = last and not Secret(last.name) and last.name ~= "" and last.name or nil,
		zone = GetRealZoneText and GetRealZoneText() or nil,
		size = #players, p = players,
	}
	-- Only an encounter that ended about when this fight did: one ended after a wipe (you died
	-- and left combat first, then the boss reset) would otherwise name the next trash pull.
	if encounter and GetTime() - encounter.at < ENCOUNTER_WINDOW then
		fight.boss, fight.kill = encounter.name, encounter.kill
	end
	encounter = nil
	fight.mine = MyAbilities(me.guid)
	-- In a dungeon or raid, everyone's abilities too, for the run report.
	local deep
	if fight.run then
		deep = {}
		for _, p in ipairs(players) do
			local ok, spells = pcall(Deep, p.guid)
			if ok and spells then deep[p.n] = spells end
		end
	end
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
	if fight.run then
		local ok, err = pcall(H.AddToRun, m, fight, rank, outcome, deep, died)
		if not ok then ns.Log("meter run: %s", tostring(err)) end
	end
	return fight, outcome
end

---------------------------------------------------------------------------
-- Runs

function H.Runs()
	local m = Store()
	return m and m.runs or {}
end

function H.RunById(id)
	local m = Store()
	if not m or id == nil then return nil end
	for i = #m.runs, 1, -1 do
		if m.runs[i].id == id then return m.runs[i] end
	end
end

-- The run going on now, else the last one.
function H.LatestRun()
	local m = Store()
	return m and m.runs[#m.runs] or nil
end

function H.TrimRuns()
	local m = Store()
	if not m then return end
	local keep = math.max(1, math.min(RUNS_MAX, tonumber(ns.DB().meter.runsKeep) or RUNS_DEFAULT))
	while #m.runs > keep do table.remove(m.runs, 1) end
end

local function NewRun(m, fight)
	local name, kind, diff
	if GetInstanceInfo then
		local ok, n, k, _, d = pcall(GetInstanceInfo)
		if ok then name, kind, diff = n, k, d end
	end
	if name == nil or Secret(name) or name == "" then name = fight.zone end
	if kind ~= nil and Secret(kind) then kind = nil end
	if diff ~= nil and (Secret(diff) or diff == "") then diff = nil end
	local r = {
		id = fight.run, name = name or "Dungeon", kind = kind, diff = diff,
		t0 = (m.runStart and m.runStartId == fight.run) and m.runStart or (fight.t - (fight.dur or 0)),
		t1 = fight.t, pulls = {}, players = {}, order = {}, deaths = {},
	}
	m.runs[#m.runs + 1] = r
	H.TrimRuns()
	return r
end

local function Totals(r, p)
	local a = r.players[p.n]
	if not a then
		a = { n = p.n, c = p.c, sec = 0, pulls = 0, sp = {} }
		r.players[p.n] = a
		r.order[#r.order + 1] = p.n
	end
	if p.me then a.me = true end
	return a
end

-- Add a fight just saved to its run: the pull, everyone's totals and abilities, the deaths.
function H.AddToRun(m, fight, rank, outcome, deep, died)
	local r = H.RunById(fight.run) or NewRun(m, fight)
	local players = fight.p
	local group = 0
	for _, p in ipairs(players) do group = group + (p.d or 0) end
	local pull = {
		t = fight.t, dur = fight.dur, name = fight.name, boss = fight.boss, kill = fight.kill, size = fight.size,
		sid = fight.sid, epoch = fight.epoch, gd = group, my = outcome and outcome.dps, rank = rank,
		top = players[1] and players[1].n, topc = players[1] and players[1].c, k = 0, dp = {},
	}
	for _, p in ipairs(players) do
		pull.dp[p.n] = p.dps or (fight.dur > 0 and (p.d or 0) / fight.dur) or 0
		pull.k = pull.k + (p.k or 0)
		local a = Totals(r, p)
		for _, k in ipairs(TALLY) do a[k] = (a[k] or 0) + (p[k] or 0) end
		a.sec, a.pulls = a.sec + (fight.dur or 0), a.pulls + 1
		for short, list in pairs(deep and deep[p.n] or {}) do
			r.deep = true
			local into = a.sp[short] or {}
			a.sp[short] = into
			for _, e in ipairs(list) do
				-- Kept by name (ranks together); id is the rank that did the most in one pull.
				local k = e.key or e.id
				local t = into[k]
				if not t then
					t = { v = 0, n = 0 }
					into[k] = t
				end
				if e.v > (t.best or 0) then t.id, t.best = e.id, e.v end
				t.v, t.n = t.v + e.v, t.n + 1
				if e.o then t.o = (t.o or 0) + e.o end
				if e.dl then t.dl = (t.dl or 0) + 1 end
				if e.av then t.av = true end
				if e.from then t.from = e.from end
			end
		end
	end
	if fight.boss then
		pull.p = {}
		for i, p in ipairs(players) do
			local copy = {}
			for k, v in pairs(p) do copy[k] = v end
			pull.p[i] = copy
		end
		pull.best = (H.BestFor(fight))
		pull.nb = outcome and outcome.best ~= nil or nil
	end
	r.pulls[#r.pulls + 1] = pull
	r.t1 = fight.t

	-- Deaths, each with the blow that killed: the game marks the killing abilities in a player's
	-- damage taken (one per death, in no promised order), so a player's deaths take them in turn.
	local taken = {}
	for _, d in ipairs(died or {}) do
		local n = d.p.n
		local spells = deep and deep[n] and deep[n].t
		local by, over, from
		if spells then
			local want, seen = (taken[n] or 0), 0
			for _, e in ipairs(spells) do
				if e.dl then
					if seen == want then
						by, over, from = e.id, e.o, e.from
						break
					end
					seen = seen + 1
				end
			end
			taken[n] = want + 1
		end
		r.deaths[#r.deaths + 1] = { pull = #r.pulls, n = n, c = d.p.c, at = d.at, recap = d.recap, by = by, o = over, from = from }
	end
	if pendingFinal and pendingFinal.run == r.id and fight.boss then H.CompleteRun() end
	if ns.RunReport and ns.RunReport.Changed then ns.RunReport.Changed(r) end
end

-- Runs from fights saved before runs were kept: totals and pulls, no abilities or death times.
local function Backfill(m)
	if m.runsBuilt then return end
	m.runsBuilt = true
	if #m.runs > 0 then return end
	local byId = {}
	for _, f in ipairs(m.fights) do
		if f.run and f.p then
			local r = byId[f.run]
			if not r then
				r = { id = f.run, name = f.zone or "Dungeon", t0 = f.t - (f.dur or 0), pulls = {}, players = {}, order = {},
					deaths = {}, done = true, old = true }
				byId[f.run] = r
				m.runs[#m.runs + 1] = r
			end
			local rank, group = 1, 0
			for i, p in ipairs(f.p) do
				group = group + (p.d or 0)
				if p.me then rank = i end
			end
			local pull = { t = f.t, dur = f.dur, name = f.name, boss = f.boss, kill = f.kill, size = f.size, sid = f.sid,
				epoch = f.epoch, gd = group, my = H.MyDps(f), rank = rank, top = f.p[1] and f.p[1].n, topc = f.p[1] and f.p[1].c,
				k = 0, dp = {} }
			for _, p in ipairs(f.p) do
				pull.dp[p.n] = p.dps or ((f.dur or 0) > 0 and (p.d or 0) / f.dur) or 0
				pull.k = pull.k + (p.k or 0)
				local a = Totals(r, p)
				for _, k in ipairs(TALLY) do a[k] = (a[k] or 0) + (p[k] or 0) end
				a.sec, a.pulls = a.sec + (f.dur or 0), a.pulls + 1
			end
			if f.boss then pull.p = f.p end
			r.pulls[#r.pulls + 1] = pull
			r.t1 = f.t
		end
	end
	if m.inRun and byId[m.run] then byId[m.run].done = nil end
	H.TrimRuns()
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
	local record = type(run) == "table" and run or H.RunById(run)
	if record then
		-- The run's own record: whole however many fights have been trimmed since.
		for _, pull in ipairs(record.pulls) do
			if (pull.size or 0) > 1 then
				fights = fights + 1
				if pull.rank == 1 then topped = topped + 1 end
			end
		end
		for _, n in ipairs(record.order) do order[#order + 1] = record.players[n] end
	end
	for _, f in ipairs(record and {} or m.fights) do
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
	return H.AwardsFrom(order), fights, topped
end

-- Who led each tally among a list of players' totals.
function H.AwardsFrom(order)
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
	return awards
end

function H.Clear()
	local m = Store()
	if not m then return end
	m.fights, m.bests, m.streak, m.rivalWins, m.rivalLosses = {}, {}, 0, 0, 0
	m.runs = {}
end

function H.ResetRival()
	local m = Store()
	if m then m.rivalWins, m.rivalLosses = 0, 0 end
end

---------------------------------------------------------------------------
-- The final boss: the run is complete when it dies, without waiting to leave.
--
-- Two ways to know it. DungeonJournal (ForeverDungeonJournal, if installed) keeps every
-- dungeon's boss list and calls FDJ.RunLogSummary the moment the last required boss is dead,
-- so that call is the surest sign. Otherwise the game's Encounter Journal: the boss killed is
-- the last encounter it lists for this dungeon. Either way the run is marked complete once that
-- boss's fight has been saved (or a few seconds later if it never is), and the "Run complete"
-- banner comes up (MeterGlory.RunComplete).

local FINAL_WAIT = 8 -- seconds to wait for the final boss's fight to be saved
local journalFinal = {} -- map ID -> { id = dungeonEncounterID, name } or false

-- The last encounter the Encounter Journal lists for where you are, or nil.
local function JournalFinal()
	if not (EJ_GetInstanceForMap and EJ_GetEncounterInfoByIndex and C_Map and C_Map.GetBestMapForUnit) then return nil end
	local okM, map = pcall(C_Map.GetBestMapForUnit, "player")
	if not okM or map == nil or Secret(map) then return nil end
	if journalFinal[map] == nil then
		local last = false
		local okI, journal = pcall(EJ_GetInstanceForMap, map)
		if okI and journal and not Secret(journal) and journal ~= 0 then
			for i = 1, 40 do
				local ok, name, _, _, _, _, _, encounterID = pcall(EJ_GetEncounterInfoByIndex, i, journal)
				if not ok or name == nil or Secret(name) then break end
				last = { name = name, id = not Secret(encounterID) and encounterID or nil }
			end
		end
		journalFinal[map] = last
		-- Which dungeons the game's journal knows: if it knows them all, DungeonJournal's signal
		-- is never needed (the journal's fires first, at the kill).
		if last then
			ns.Log("run: the game's journal lists this dungeon (map %s); its final boss is %s (%s)", tostring(map), last.name, tostring(last.id))
		else
			ns.Log("run: the game's journal has no boss list for map %s (journal instance %s)", tostring(map), tostring(okI and journal))
		end
	end
	return journalFinal[map] or nil
end
H.JournalFinal = JournalFinal

function H.CompleteRun()
	local p = pendingFinal
	if not p then return end
	pendingFinal = nil
	local r = H.RunById(p.run)
	if not r or r.complete then return end
	r.complete, r.t1 = true, math.max(r.t1 or 0, p.t)
	ns.Log("run: complete (%s)", p.why)
	if ns.MeterGlory and ns.MeterGlory.RunComplete then
		local ok, err = pcall(ns.MeterGlory.RunComplete, r.id)
		if not ok then ns.Log("run complete: %s", tostring(err)) end
	end
	if ns.RunReport and ns.RunReport.Changed then ns.RunReport.Changed(r) end
end

-- The final boss just died (why: what said so; name: the boss, when known).
function H.FinalBossDown(why, name)
	local m = Store()
	if not m or not m.inRun then return end
	local r = H.RunById(m.run)
	if (r and r.complete) or (pendingFinal and pendingFinal.run == m.run) then return end
	ns.Log("run: final boss down: %s", tostring(why))
	pendingFinal = { run = m.run, name = name, why = why, t = time() }
	C_Timer.After(FINAL_WAIT, H.CompleteRun)
end

-- A boss killed (ENCOUNTER_END success, or BOSS_KILL): is it the journal's last?
local function BossKilled(encounterID, name)
	local final = JournalFinal()
	if not final then return end
	if (encounterID and final.id and encounterID == final.id) or (name and name == final.name) then
		H.FinalBossDown("the journal's last boss, " .. tostring(name), name)
	end
end

-- DungeonJournal's "run complete": FDJ.RunLogSummary is called once, two seconds after the
-- kill that leaves no required boss standing.
local hookedJournal = false
local function HookDungeonJournal()
	local fdj = _G.ForeverDungeonJournal_NS
	if hookedJournal or type(fdj) ~= "table" or type(fdj.RunLogSummary) ~= "function" or not hooksecurefunc then return end
	hookedJournal = true
	hooksecurefunc(fdj, "RunLogSummary", function(run)
		if type(run) ~= "table" or not run.completed then return end
		local now = (GetServerTime and GetServerTime()) or time()
		if type(run.finalKill) == "number" and math.abs(now - run.finalKill) > 120 then return end
		H.FinalBossDown("DungeonJournal: every boss is down")
	end)
end

function H.Init()
	local store = Store()
	if store then pcall(Backfill, store) end
	HookDungeonJournal()
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "ENCOUNTER_START", "ENCOUNTER_END", "BOSS_KILL", "DAMAGE_METER_RESET", "PLAYER_ENTERING_WORLD", "ADDON_LOADED" }) do
		pcall(events.RegisterEvent, events, event)
	end
	events:SetScript("OnEvent", function(_, event, ...)
		local m = Store()
		if not m then return end
		if event == "ENCOUNTER_START" then
			encounter = nil
		elseif event == "ENCOUNTER_END" then
			local encounterID, name, _, _, success = ...
			if name ~= nil and not Secret(name) then
				-- kill is false on a wipe (so it never sets a best), nil when the client hides it.
				local kill
				if success ~= nil and not Secret(success) then kill = success == 1 or success == true end
				encounter = { name = name, kill = kill, at = GetTime() }
				if kill and m.inRun then
					local ok, err = pcall(BossKilled, not Secret(encounterID) and encounterID or nil, name)
					if not ok then ns.Log("run final boss: %s", tostring(err)) end
				end
			end
		elseif event == "BOSS_KILL" then
			local encounterID, name = ...
			if m.inRun and name ~= nil and not Secret(name) then
				pcall(BossKilled, not Secret(encounterID) and encounterID or nil, name)
			end
		elseif event == "ADDON_LOADED" then
			HookDungeonJournal()
		elseif event == "DAMAGE_METER_RESET" then
			m.epoch = m.epoch + 1
		elseif event == "PLAYER_ENTERING_WORLD" then
			local isInitialLogin = ...
			-- The client numbers its fights afresh each login, with no reset event: a new epoch,
			-- or today's fight 2 would be matched to yesterday's saved fight 2.
			if isInitialLogin == true then m.epoch = m.epoch + 1 end
			-- Runs: a visit to one dungeon or raid, kept by its instance ID (saved as inRun, so a
			-- /reload inside doesn't start a new one). Leaving dead (released to the graveyard
			-- after a wipe) holds the run for the way back in; entering the same instance carries
			-- on. Leaving alive, or entering another instance, ends it (MeterGlory's awards).
			local inside, kind = false, nil
			if IsInInstance then inside, kind = IsInInstance() end
			inside = inside and (kind == "party" or kind == "raid") or false
			local id = inside and GetInstanceInfo and select(8, GetInstanceInfo()) or nil
			if Secret(id) then id = nil end
			id = id or (inside and true) or nil
			local was = m.inRun
			-- true: a run saved before runs kept their instance (or the client wouldn't say).
			local same = was ~= nil and inside and (was == true or id == true or was == id)
			if was ~= nil and not same and (inside or not UnitIsDeadOrGhost("player")) then
				local ended = H.RunById(m.run)
				if ended then
					ended.done = true
					-- A completed run's clock stopped at the final boss.
					if not ended.complete then ended.t1 = time() end
				end
				pendingFinal = nil
				if ns.MeterGlory and ns.MeterGlory.RunEnded then pcall(ns.MeterGlory.RunEnded, m.run) end
				was = nil
				m.inRun = nil
			end
			if inside then
				pcall(JournalFinal)
				if was == nil then
					m.run = m.run + 1
					m.runStart, m.runStartId = time(), m.run -- door to door starts at the door
				end
				m.inRun = id
			end
		end
	end)
end
