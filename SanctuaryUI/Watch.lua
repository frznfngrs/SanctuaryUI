SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.Watch = ns.Watch or {}

-- Knows whether the buffs in WatchEffects.lua are up on you, in combat too, for GlobeAura.lua
-- to show. In combat this client won't let an addon read your buffs at all, so each one is
-- followed from what is still visible:
--
--   reading   out of combat: the buff itself, with its real timing. Always wins.
--   casting   your casts are readable in combat. A cast puts its buff up for its length
--             (learned from readings, else the spell's text, else the default) and ends the
--             rest of its group (a paladin holds one seal at a time).
--   landing   a spell you can cast on others (Power Word: Shield, Innervate) only counts
--             when it lands on you: the cast was aimed at you, or Blizzard's buff frame (which
--             still sees your buffs) gains an icon with it.
--   channels  up from the channel's start to its stop.
--   judging   Judgement unleashes the seal. Whether that also ends it is found out: the buff
--             frame losing an icon right at the cast says it went; a reading after combat that
--             still shows the old seal says it stays. What has been seen is saved.
--   the gate  Judgement can't be cast without a seal, so whether it is usable says whether a
--             seal is up; trusted only once it has agreed with real readings a few times.
--   absorbs   the game says whether you hold any absorb only as a hidden number, which a
--             status bar can still show (GlobeAura.lua's shields use that). Whether this client
--             reports absorbs at all is learned: an absorb event right after your own shield
--             cast proves it.
--   breaking  a buff icon going with an absorb event is a shield breaking; going with a hit
--             (and nothing else explaining it) is a charge buff (Lightning Shield) spent.
--   timing    a buff with no newer word ends when its time runs out; death ends them all.
--
-- What can't be seen: a buff cancelled by hand or purged in combat stays lit until its time
-- would have run out. The first reading after combat puts it right.

local DATA = ns.WatchData
local EFFECTS, GROUPS, CONSUMERS = DATA.EFFECTS, DATA.GROUPS, DATA.CONSUMERS
ns.Watch.EFFECTS = EFFECTS

local CONSUME_WINDOW = 0.6 -- seconds after Judgement for the buff frame to drop an icon
local LAND_WINDOW = 0.6 -- seconds after a cast for its buff icon to appear on you
local HIT_WINDOW = 0.3 -- an icon lost this close to a hit or an absorb change goes with it
local ABSORB_PROBE = 1.5 -- seconds after your shield cast for the game's absorb event
local GATE_SETTLE = 0.2 -- a closed gate must hold this long before it ends anything
local GATE_TRUST = 3 -- agreements with readings, none against, before the gate is used
local GATE_TRUST_LOOSE = 12 -- or this many, with at most 1 in 20 against
local SCAN_EVERY = 0.1
local GRACE = 1 -- seconds a cast's buff may take to show in a reading before "gone" counts

-- Test mode (ns.Watch.SetTest): you play the casts from the options or /sanctuary aura, on
-- any class. Your real buffs, casts and the gate are ignored while it is on, nothing is
-- learned or saved, and Judgement always ends the seal. The real state returns when it ends.
local test

local GetSpellName = (C_Spell and C_Spell.GetSpellName) or function(id)
	return (GetSpellInfo(id))
end

local function Secret(value)
	return ns.Secret(value)
end

local function Readable(value)
	return not Secret(value) and value ~= nil
end

local function Store()
	local global = ns.db and ns.db.global
	if not global then return { consume = {}, gate = {}, absorb = {} } end
	global.watch = global.watch or {}
	local store = global.watch
	store.consume = store.consume or {}
	store.gate = store.gate or {}
	store.absorb = store.absorb or {}
	return store
end

-- Buff lengths shared with ActiveSkill.lua (learned from readings, saved per account).
local function Lengths()
	local global = ns.db and ns.db.global
	if not global then return {} end
	global.buffLengths = global.buffLengths or {}
	return global.buffLengths
end

-- Effects with a state (flares are only moments).
local function Kept(effect)
	return effect.look ~= "flare"
end

---------------------------------------------------------------------------
-- Names. Spell IDs differ by rank; names don't, so casts and readings match on names.

local effectByName, effectByID = {}, {}
local groupByName, groupByID = {}, {}
local consumerByName, consumerByID = {}, {}
local groupNames = {} -- group -> set of names, for ActiveSkill.Forget

-- Readings can show several effects under one name (Food & Drink), so names map to lists.
local function Index(def, byName, byID, value, names, multi)
	local function put(map, key)
		if multi then
			map[key] = map[key] or {}
			table.insert(map[key], value)
		else
			map[key] = value
		end
	end
	for _, id in ipairs(def.spells or {}) do
		put(byID, id)
		local name = GetSpellName(id)
		if Readable(name) then
			put(byName, name)
			if names then names[name] = true end
		end
	end
	for _, name in ipairs(def.names or {}) do
		put(byName, name)
		if names then names[name] = true end
	end
end

local function BuildNames()
	wipe(effectByName); wipe(effectByID)
	wipe(groupByName); wipe(groupByID)
	wipe(consumerByName); wipe(consumerByID)
	wipe(groupNames)
	for _, effect in ipairs(EFFECTS) do
		Index(effect, effectByName, effectByID, effect, nil, true)
	end
	for key, group in pairs(GROUPS) do
		groupNames[key] = {}
		Index(group, groupByName, groupByID, key, groupNames[key])
	end
	for key, consumer in pairs(CONSUMERS) do
		consumer.key = key
		Index(consumer, consumerByName, consumerByID, consumer)
	end
end

local function Lookup(byID, byName, id, name)
	return (id and byID[id]) or (name and byName[name])
end

-- The effects a spell ID or name stands for (a list; usually one).
local function EffectsOf(id, name)
	return (id and effectByID[id]) or (name and effectByName[name]) or {}
end

---------------------------------------------------------------------------
-- State. One entry per kept effect: up, start, expires (nil: no timer known), length, source
-- ("reading", "cast", "channel", "test"), since (when it last went up or down), and castAt: when
-- your own cast (or a test cast) put it up, which readings don't change. Nil for a buff you only
-- ever read (someone else's), and for anything that was up before a reload.

local state = {}
local listeners = {}
local readable = false -- the last scan could read your buffs
local groupUp = {} -- group -> { aura } when a reading showed one of its members (tracked or not)
local groupCast = {} -- group -> { name, at, expires } for the last member cast, tracked or not

for _, effect in ipairs(EFFECTS) do
	if Kept(effect) then state[effect.key] = { up = false, since = 0 } end
end

function ns.Watch.State(key)
	return state[key]
end

local byKey = {}
for _, effect in ipairs(EFFECTS) do byKey[effect.key] = effect end

function ns.Watch.Effect(key)
	return byKey[key]
end

-- fn(key, state, reason). Reasons: reading, cast, refreshed, channel, gone, expired,
-- replaced, consumed, gate, died, broken, spent, ended, and flare (state nil: play the
-- effect's flare once).
function ns.Watch.OnChange(fn)
	listeners[#listeners + 1] = fn
end

local function Notify(key, reason)
	for _, fn in ipairs(listeners) do
		local ok, err = pcall(fn, key, state[key], reason)
		if not ok then ns.Log("watch: listener failed: %s", tostring(err)) end
	end
end

local function Flare(effect)
	if not effect.flare then return end
	ns.Log("watch: %s flares", effect.key)
	Notify(effect.key, "flare")
end

local function Up(effect, start, expires, length, source, reason)
	local st = state[effect.key]
	if not st then return end
	local was = st.up
	local moved = not was or math.abs((st.expires or 0) - (expires or 0)) > 0.25 or st.source ~= source
	st.up, st.start, st.expires, st.length, st.source = true, start, expires, length, source
	if source ~= "reading" then st.castAt = start end
	if not was then st.since = GetTime() end
	if moved then
		ns.Log("watch: %s up (%s, %s)", effect.key, reason,
			expires and ("%.1fs left"):format(expires - GetTime()) or "no timer")
		Notify(effect.key, was and reason == "cast" and "refreshed" or reason)
	end
end

-- Endings that only we could see: tell ActiveSkill.lua so the socket glow goes too.
local EARLY = { consumed = true, replaced = true, gate = true, broken = true, spent = true, died = true }

local function ForgetSkill(effect)
	if not (ns.ActiveSkill and ns.ActiveSkill.Forget) then return end
	for _, id in ipairs(effect.spells or {}) do
		local name = GetSpellName(id)
		if Readable(name) then ns.ActiveSkill.Forget(name) end
	end
	for _, name in ipairs(effect.names or {}) do ns.ActiveSkill.Forget(name) end
end

local function Down(effect, reason)
	local st = state[effect.key]
	if not st or not st.up then return end
	st.up, st.start, st.expires, st.length, st.source, st.castAt = false, nil, nil, nil, nil, nil
	st.since = GetTime()
	ns.Log("watch: %s down (%s)", effect.key, reason)
	if EARLY[reason] then ForgetSkill(effect) end
	Notify(effect.key, reason)
end

-- Every member of a group but the one just cast (keepName) ends, tracked or not:
-- ActiveSkill.lua may be lighting an untracked one's socket.
local function EndGroup(group, keepName, reason)
	for _, effect in ipairs(EFFECTS) do
		if effect.group == group then
			local keep = false
			if keepName then
				for _, e in ipairs(EffectsOf(nil, keepName)) do
					if e == effect then keep = true end
				end
			end
			if not keep then Down(effect, reason) end
		end
	end
	if ns.ActiveSkill and ns.ActiveSkill.Forget and groupNames[group] then
		for name in pairs(groupNames[group]) do
			if name ~= keepName then ns.ActiveSkill.Forget(name) end
		end
	end
end

local function LengthOf(effect, id, name)
	if test then return tonumber(ns.DB().globeAuras.testLength) or effect.length or 30, "test" end
	local lengths = Lengths()
	local learned = (id and lengths[id]) or (name and lengths[name])
	if learned and learned > 0 then return learned, "learned" end
	local described = id and ns.DescribedLength(id)
	if described and described > 0 then return described, "spell text" end
	return effect.length or 30, "default"
end

---------------------------------------------------------------------------
-- The gate: is Judgement usable? Open means a seal is up, closed means none, nil means
-- it can't say (not known, out of mana, hidden).

local IsSpellUsable = (C_Spell and C_Spell.IsSpellUsable) or IsUsableSpell
local IsKnown = IsPlayerSpell or IsSpellKnown

local function Gate(consumer)
	if not consumer.gate or not IsSpellUsable then return end
	if IsKnown then
		local ok, known = pcall(IsKnown, consumer.gate)
		if not ok or not Readable(known) or not known then return end
	end
	local ok, usable, noPower = pcall(IsSpellUsable, consumer.gate)
	if not ok or Secret(usable) or Secret(noPower) then return end
	if usable then return "open" end
	if noPower then return end
	return "closed"
end

local function GateTrusted(consumer)
	local g = Store().gate[consumer.key]
	if not g then return false end
	local agree, against = g.agree or 0, g.against or 0
	if against == 0 then return agree >= GATE_TRUST end
	return agree >= GATE_TRUST_LOOSE and against * 20 <= agree
end

-- While buffs are readable: does the gate say what the reading says? A pair is counted once
-- it has held for CALIBRATE_HOLD (the buff and the usability update a frame or two apart,
-- which would otherwise count against), and once per change, so standing still doesn't pile
-- up agreements.
local CALIBRATE_HOLD = 0.5
local lastSample, candidate, candidateAt = {}, {}, {}
local function Calibrate(now)
	for key, consumer in pairs(CONSUMERS) do
		local gate = Gate(consumer)
		local up = groupUp[consumer.group] and true or false
		local pair = gate and (gate .. tostring(up))
		if pair ~= candidate[key] then
			candidate[key], candidateAt[key] = pair, now
		elseif pair and now - candidateAt[key] >= CALIBRATE_HOLD and lastSample[key] ~= pair then
			lastSample[key] = pair
			local g = Store().gate[key] or {}
			Store().gate[key] = g
			if (gate == "open") == up then
				g.agree = (g.agree or 0) + 1
			else
				g.against = (g.against or 0) + 1
				ns.Log("watch: gate %s said %s but a reading shows %s", key, gate, up and "a seal" or "no seal")
			end
		end
	end
end

---------------------------------------------------------------------------
-- Absorbs: does this client report them? Learned from your own shield casts.

local absorbProbe -- when your shield landed, waiting for the absorb event
local lastAbsorbEvent, lastHit = -math.huge, -math.huge

local function AbsorbWorks()
	return (Store().absorb.works or 0) > 0
end

-- "test": test mode, shields always held. "live": the game's absorb amount gates the shields.
-- "off": it hasn't shown it reports absorbs; shields follow their timers.
function ns.Watch.AbsorbMode()
	if test then return "test" end
	return AbsorbWorks() and "live" or "off"
end

local function ProbeAbsorb(now)
	if test then return end
	absorbProbe = now
end

local function SettleProbe(now, event)
	if not absorbProbe then return end
	local a = Store().absorb
	if event then
		a.works = (a.works or 0) + 1
		ns.Log("watch: the game reports absorbs (%d seen)", a.works)
		absorbProbe = nil
	elseif now - absorbProbe > ABSORB_PROBE then
		a.miss = (a.miss or 0) + 1
		ns.Log("watch: no absorb event after a shield (%d missed)", a.miss)
		absorbProbe = nil
	end
end

---------------------------------------------------------------------------
-- Readings.

-- After a Judgement in combat: was it right to end the seal or keep it? Settled by the first
-- reading after it. { consumer, group, at, ended, expires (what the seal had left) }.
local lastConsume

local function Learn(consumer, consumed, how)
	if test then return end
	local c = Store().consume[consumer.key] or {}
	Store().consume[consumer.key] = c
	if consumed then c.yes = (c.yes or 0) + 1 else c.no = (c.no or 0) + 1 end
	ns.Log("watch: %s %s the seal (%s; seen %d yes, %d no)", consumer.key, consumed and "ends" or "keeps", how, c.yes or 0, c.no or 0)
end

-- Ends the seal unless readings have shown otherwise more often. Assumed until then: in the
-- classic rules Judgement spends the seal.
local function Consumes(consumer)
	local c = Store().consume[consumer.key] or {}
	return (c.yes or 0) + 1 > (c.no or 0)
end

local lastJudgement -- when a consumer was last cast
local dirty = true -- a scan is due

-- Effects readings decide: everything kept except channels (their events decide) and the
-- shield from anyone (the absorb gate decides).
local function Read(effect)
	return Kept(effect) and effect.kind ~= "channel" and effect.kind ~= "absorb"
end

local function Scan()
	if test then
		readable = false
		return false
	end
	local list, _, denied = ns.ReadAuras("player", "HELPFUL")
	if denied then
		readable = false
		return false
	end
	readable = true
	local now = GetTime()
	local seen = {}
	wipe(groupUp)
	for _, aura in ipairs(list) do
		local id, name = aura.spellId, aura.name
		if not Readable(id) then id = nil end
		if not Readable(name) then name = nil end
		local group = Lookup(groupByID, groupByName, id, name)
		if group then
			groupUp[group] = { aura = aura }
		end
		for _, effect in ipairs(EffectsOf(id, name)) do
			seen[effect] = { aura = aura, id = id, name = name }
		end
	end
	for _, effect in ipairs(EFFECTS) do
		if Read(effect) then
			local hit = seen[effect]
			if hit then
				local aura = hit.aura
				local duration, expires = aura.duration, aura.expirationTime
				if Readable(duration) and Readable(expires) and duration > 0 then
					local lengths = Lengths()
					if hit.id then lengths[hit.id] = duration end
					if hit.name then lengths[hit.name] = duration end
					Up(effect, expires - duration, expires, duration, "reading", "reading")
				else
					-- Up with no timer we can read (eating, drinking): keep a cast's timing if any.
					local st = state[effect.key]
					Up(effect, st.start or now, st.up and st.expires or nil, st.length, "reading", "reading")
				end
			else
				local st = state[effect.key]
				-- A cast's buff can reach the reading a moment after the cast event.
				if not (st.up and st.source == "cast" and now - (st.start or 0) < GRACE) then
					-- Gone right after a Judgement: it was spent.
					local judged = effect.group and lastJudgement and now - lastJudgement < GRACE
					Down(effect, judged and "consumed" or "gone")
				end
			end
		end
	end
	-- A seal we saw cast but a reading doesn't show is over (cancelled, ran out).
	for group, cast in pairs(groupCast) do
		if not groupUp[group] and now - cast.at > GRACE then groupCast[group] = nil end
	end
	-- Settle the last Judgement: a seal from before it still up means it doesn't end seals.
	if lastConsume then
		local seal = groupUp[lastConsume.group]
		local aura = seal and seal.aura
		local start = aura and Readable(aura.expirationTime) and Readable(aura.duration) and aura.expirationTime - aura.duration
		if start and start < lastConsume.at - 0.5 then
			Learn(lastConsume.consumer, false, "the seal was still up after combat")
		elseif not seal and not lastConsume.ended and lastConsume.expires and lastConsume.expires > now then
			Learn(lastConsume.consumer, true, "the seal was gone after combat")
		end
		lastConsume = nil
	end
	return true
end

---------------------------------------------------------------------------
-- In combat.

local pending -- a Judgement waiting for the buff frame: { consumer, at, icons }
local landing = {} -- casts at someone that may be you: { effect, id, name, at, icons }
local sentTarget = {} -- castGUID -> the target name UNIT_SPELLCAST_SENT gave (false: hidden)
local sentCount = 0 -- entries, so casts that never went off don't pile up
local playerName

local function SealExpires(group)
	local latest
	for _, effect in ipairs(EFFECTS) do
		local st = state[effect.key]
		if effect.group == group and st and st.up and st.expires then
			latest = math.max(latest or 0, st.expires)
		end
	end
	local cast = groupCast[group]
	if cast and cast.expires then latest = math.max(latest or 0, cast.expires) end
	return latest
end

-- Was a seal up when the Judgement went out? Without one there is nothing to end or learn.
local function SealUp(group)
	if groupCast[group] then return true end
	for _, effect in ipairs(EFFECTS) do
		local st = state[effect.key]
		if effect.group == group and st and st.up then return true end
	end
	return false
end

local function Settle(now, final)
	local consumer, at = pending.consumer, pending.at
	local group = consumer.group
	if final and Scan() then
		-- Out of combat a reading says it outright, and Scan has already ended or kept the
		-- seal. Learn from it: the seal from before the Judgement still up means it stays.
		pending = nil
		local seal = groupUp[group]
		local aura = seal and seal.aura
		local start = aura and Readable(aura.expirationTime) and Readable(aura.duration) and aura.expirationTime - aura.duration
		if not seal then
			Learn(consumer, true, "a reading")
		elseif start and start < at - 0.05 then
			Learn(consumer, false, "a reading")
		end
		return
	end
	local ended, how
	if test then
		ended, how = true, "test"
	elseif ns.BuffIcons() < pending.icons then
		ended, how = true, "an icon went"
		Learn(consumer, true, how)
	elseif GateTrusted(consumer) and Gate(consumer) == "closed" then
		ended, how = true, "the gate closed"
		Learn(consumer, true, how)
	elseif not final then
		return
	else
		ended, how = Consumes(consumer), "what has been seen before"
	end
	pending = nil
	lastConsume = { consumer = consumer, group = group, at = at, ended = ended, expires = SealExpires(group) }
	if ended then
		ns.Log("watch: %s ended the seal (%s)", consumer.key, how)
		groupCast[group] = nil
		EndGroup(group, nil, "consumed")
	else
		ns.Log("watch: %s left the seal up (%s)", consumer.key, how)
	end
end

-- An effect's buff is on you from `at`: light it, play its flare, and for a shield, watch for
-- the game's absorb event.
local function Land(effect, id, name, at)
	if Kept(effect) then
		local length, from = LengthOf(effect, id, name)
		ns.Log("watch: %s on you, %ss (%s)", effect.key, tostring(length), from)
		Up(effect, at, at + length, length, test and "test" or "cast", "cast")
		if effect.absorb then ProbeAbsorb(at) end
	end
	Flare(effect)
end

-- Is the cast with this GUID aimed at you? true, false, or nil when the client won't say.
local function AimedAtYou(castGUID)
	local target = castGUID and sentTarget[castGUID]
	if castGUID then sentTarget[castGUID] = nil end
	if not target then return nil end
	if target == "" then return nil end
	playerName = playerName or UnitName("player")
	return target == playerName
end

local function OnCast(spellID, now, castGUID)
	local name = GetSpellName(spellID)
	if not Readable(name) then name = nil end
	local group = Lookup(groupByID, groupByName, spellID, name)
	if group then
		EndGroup(group, name, "replaced")
		local length
		for _, effect in ipairs(EffectsOf(spellID, name)) do length = LengthOf(effect, spellID, name) end
		length = length or ns.DescribedLength(spellID)
		groupCast[group] = { name = name, at = now, expires = length and now + length }
	end
	local aimed = AimedAtYou(castGUID)
	for _, effect in ipairs(EffectsOf(spellID, name)) do
		-- Channels start on their own event; readings and the absorb gate aren't casts.
		if effect.kind ~= "channel" and effect.kind ~= "reading" and effect.kind ~= "absorb" then
			if effect.target ~= "any" or aimed == true or test then
				Land(effect, spellID, name, now)
			elseif aimed == nil and Kept(effect) then
				-- Can't tell where it went: it is yours if a buff icon turns up with it. A direct
				-- heal leaves no buff, so it stays silent rather than guess.
				table.insert(landing, { effect = effect, id = spellID, name = name, at = now, icons = ns.BuffIcons() })
			end
		end
	end
	local consumer = Lookup(consumerByID, consumerByName, spellID, name)
	if consumer then
		lastJudgement = now
		if pending then Settle(now, true) end
		if SealUp(consumer.group) then
			pending = { consumer = consumer, at = now, icons = ns.BuffIcons() }
		end
	end
end

local function WatchLanding(now, icons)
	for i = #landing, 1, -1 do
		local cast = landing[i]
		if icons > cast.icons then
			table.remove(landing, i)
			ns.Log("watch: %s landed on you (a buff icon came with it)", cast.effect.key)
			Land(cast.effect, cast.id, cast.name, cast.at)
		elseif now - cast.at > LAND_WINDOW then
			table.remove(landing, i)
		end
	end
end

local function OnChannel(event, spellID, now)
	if event == "UNIT_SPELLCAST_CHANNEL_STOP" then
		for _, effect in ipairs(EFFECTS) do
			if effect.kind == "channel" then Down(effect, "ended") end
		end
		return
	end
	if not Readable(spellID) then return end
	local name = GetSpellName(spellID)
	if not Readable(name) then name = nil end
	for _, effect in ipairs(EffectsOf(spellID, name)) do
		if effect.kind == "channel" then
			local length = LengthOf(effect, spellID, name)
			local start, expires = now, now + length
			if UnitChannelInfo and not test then
				local ok, _, _, _, startMS, endMS = pcall(UnitChannelInfo, "player")
				if ok and Readable(startMS) and Readable(endMS) and endMS > startMS then
					start, expires = startMS / 1000, endMS / 1000
				end
			end
			Up(effect, start, expires, expires - start, "channel", event == "UNIT_SPELLCAST_CHANNEL_START" and "cast" or "channel")
		end
	end
end

-- A buff icon went. If nothing we know explains it, and it came with an absorb change or a
-- hit, a shield broke or a charge buff was spent.
local function IconLost(now)
	if readable or test then return end
	if pending then return end -- Judgement's own window
	for _, effect in ipairs(EFFECTS) do
		local st = state[effect.key]
		if st and st.up and st.expires and math.abs(st.expires - now) < 0.5 then return end
	end
	if now - lastAbsorbEvent <= HIT_WINDOW then
		for _, effect in ipairs(EFFECTS) do
			local st = state[effect.key]
			if effect.absorb and st and st.up then
				Down(effect, "broken")
				return
			end
		end
	end
	if now - lastHit <= HIT_WINDOW then
		for _, effect in ipairs(EFFECTS) do
			local st = state[effect.key]
			if effect.fragile and st and st.up then
				Down(effect, "spent")
				return
			end
		end
	end
end

-- A trusted gate closing ends the group outright (a seal that ran out early, was cancelled or
-- purged, or was judged away).
local gateClosedAt = {}
local function WatchGate(now)
	if test then return end
	for key, consumer in pairs(CONSUMERS) do
		local any = false
		for _, effect in ipairs(EFFECTS) do
			local st = state[effect.key]
			if effect.group == consumer.group and st and st.up then any = true end
		end
		if any and GateTrusted(consumer) and Gate(consumer) == "closed" then
			gateClosedAt[key] = gateClosedAt[key] or now
			if now - gateClosedAt[key] >= GATE_SETTLE then
				gateClosedAt[key] = nil
				groupCast[consumer.group] = nil
				EndGroup(consumer.group, nil, "gate")
			end
		else
			gateClosedAt[key] = nil
		end
	end
end

local function Expire(now)
	for _, effect in ipairs(EFFECTS) do
		local st = state[effect.key]
		if st and st.up and st.expires and now >= st.expires then
			Down(effect, "expired")
		end
	end
	for group, cast in pairs(groupCast) do
		if cast.expires and now >= cast.expires then groupCast[group] = nil end
	end
end

-- The shield from anyone is up whenever the absorb gate is live; the gate shows or hides it.
local function UpdateAbsorb()
	local effect = byKey.absorb
	if not effect then return end
	if not test and AbsorbWorks() then
		Up(effect, GetTime(), nil, nil, "reading", "reading")
	elseif not test then
		Down(effect, "gone")
	end
end

---------------------------------------------------------------------------

function ns.Watch.Report()
	Scan()
	local now = GetTime()
	local _, class = UnitClass("player")
	ns.Print(("watch report: combat %s, buffs %s%s"):format(tostring(InCombatLockdown()),
		readable and "readable" or "hidden (following casts)", test and ", TEST MODE" or ""))
	for _, effect in ipairs(EFFECTS) do
		local st = state[effect.key]
		if st and (effect.class == class or effect.class == "ANY" or st.up) then
			local id = effect.spells and effect.spells[1]
			local length, from = LengthOf(effect, id, id and GetSpellName(id))
			ns.Print(("%s: %s%s; lasts %ss (%s)"):format(effect.label, st.up and ("up, from " .. tostring(st.source)) or "down",
				st.up and st.expires and (", %.1fs left"):format(st.expires - now) or "", tostring(length), from))
		end
	end
	for key, consumer in pairs(CONSUMERS) do
		if Gate(consumer) or (Store().consume[key]) then
			local c = Store().consume[key] or {}
			local g = Store().gate[key] or {}
			ns.Print(("%s: ends the seal %s (seen %d yes, %d no); gate %s, %s (%d agree, %d against)"):format(key,
				Consumes(consumer) and "yes" or "no", c.yes or 0, c.no or 0, tostring(Gate(consumer) or "silent"),
				GateTrusted(consumer) and "trusted" or "not trusted yet", g.agree or 0, g.against or 0))
		end
	end
	local a = Store().absorb
	ns.Print(("absorbs: %s (%d events after shields, %d missed)"):format(
		AbsorbWorks() and "reported, shields follow them" or "not seen yet, shields follow their timers", a.works or 0, a.miss or 0))
end

---------------------------------------------------------------------------
-- Test mode.

local function Reset(reason)
	pending, lastConsume = nil, nil
	wipe(groupCast)
	wipe(landing)
	for _, effect in ipairs(EFFECTS) do Down(effect, reason) end
end

function ns.Watch.Testing()
	return test ~= nil
end

function ns.Watch.SetTest(on)
	if (test ~= nil) == (on and true or false) then return end
	Reset("gone")
	test = on and {} or nil
	readable = false
	dirty = true -- off: the next scan brings the real state back
	ns.Log("watch: test mode %s", on and "on" or "off")
	if not on then UpdateAbsorb() end
	if ns.GlobeAura and ns.GlobeAura.OnTest then ns.GlobeAura.OnTest(on) end
end

local function FirstUp(test)
	for _, effect in ipairs(EFFECTS) do
		local st = state[effect.key]
		if st and st.up and test(effect) then return effect end
	end
end

-- What test mode can play: an effect's key or a word of its name ("light", "shield wall"), or
-- judge, break (a shield shatters), spend (a charge buff runs out), fade (to the last
-- seconds), clear, die. Turns test mode on. False if unknown.
local ACTIONS = { judge = true, judgement = true, ["break"] = true, spend = true, fade = true, clear = true, die = true }

function ns.Watch.Find(action)
	action = (action or ""):lower()
	if action == "" then return end
	for _, e in ipairs(EFFECTS) do
		if e.key:lower() == action then return e end
	end
	for _, e in ipairs(EFFECTS) do
		if e.label:lower():find(action, 1, true) then return e end
	end
end

function ns.Watch.Test(action)
	action = (action or ""):lower()
	local now = GetTime()
	local effect = not ACTIONS[action] and ns.Watch.Find(action)
	if not effect and not ACTIONS[action] then return false end
	ns.Watch.SetTest(true)
	if effect then
		if effect.kind == "absorb" then
			Up(effect, now, nil, nil, "test", "cast")
		elseif effect.kind == "channel" then
			local length = LengthOf(effect)
			Up(effect, now, now + length, length, "test", "cast")
		elseif effect.group then
			OnCast(effect.spells[1], now)
		else
			Land(effect, effect.spells and effect.spells[1], effect.names and effect.names[1], now)
		end
	elseif action == "judge" or action == "judgement" then
		OnCast(CONSUMERS.judgement.spells[1], now)
		if not pending then ns.Print("test: no seal up for Judgement to spend") end
	elseif action == "break" then
		local shield = FirstUp(function(e) return e.look == "shell" end)
		if shield then Down(shield, "broken") else ns.Print("test: no shield up to break") end
	elseif action == "spend" then
		local buff = FirstUp(function(e) return e.fragile end)
		if buff then Down(buff, "spent") else ns.Print("test: no charge buff up to spend") end
	elseif action == "fade" then
		for _, e in ipairs(EFFECTS) do
			local st = state[e.key]
			if st and st.up then Up(e, st.start, now + 6.5, st.length, st.source, "reading") end
		end
	elseif action == "clear" then
		Reset("gone")
	elseif action == "die" then
		Reset("died")
	end
	return true
end

function ns.Watch.Init()
	BuildNames()
	playerName = UnitName("player")
	local driver = CreateFrame("Frame", nil, UIParent)
	ns.Watch.driver = driver
	for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "PLAYER_DEAD",
		"PLAYER_ALIVE", "PLAYER_UNGHOST", "SPELLS_CHANGED", "SPELL_UPDATE_USABLE" }) do
		pcall(driver.RegisterEvent, driver, event)
	end
	for _, event in ipairs({ "UNIT_AURA", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_CHANNEL_START",
		"UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_HEALTH" }) do
		pcall(driver.RegisterUnitEvent, driver, event, "player")
	end
	local gateDirty = false
	driver:SetScript("OnEvent", function(_, event, _, a2, a3, a4)
		if test and event ~= "SPELLS_CHANGED" then return end
		local now = GetTime()
		if event == "UNIT_SPELLCAST_SUCCEEDED" then
			-- unit, castGUID, spellID
			if Readable(a3) then OnCast(a3, now, Readable(a2) and a2 or nil) end
			dirty = true
		elseif event == "UNIT_SPELLCAST_SENT" then
			-- unit, target, castGUID, spellID
			if Readable(a3) then
				sentCount = sentCount + 1
				if sentCount > 64 then wipe(sentTarget); sentCount = 1 end
				sentTarget[a3] = Readable(a2) and a2 or false
			end
		elseif event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_CHANNEL_STOP" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
			OnChannel(event, a3, now)
		elseif event == "UNIT_ABSORB_AMOUNT_CHANGED" then
			lastAbsorbEvent = now
			SettleProbe(now, true)
			UpdateAbsorb()
		elseif event == "UNIT_HEALTH" then
			lastHit = now
		elseif event == "PLAYER_DEAD" then
			for group in pairs(GROUPS) do groupCast[group] = nil end
			for _, effect in ipairs(EFFECTS) do
				if effect.kind ~= "absorb" then Down(effect, "died") end
			end
			pending = nil
			wipe(landing)
		elseif event == "SPELLS_CHANGED" then
			BuildNames()
			dirty = true
		elseif event == "SPELL_UPDATE_USABLE" then
			gateDirty = true
		else
			dirty = true
		end
	end)
	local nextScan, nextGate, icons = 0, 0, ns.BuffIcons()
	driver:SetScript("OnUpdate", function()
		local now = GetTime()
		if test then
			if pending then Settle(now, now - pending.at >= CONSUME_WINDOW) end
			Expire(now)
			return
		end
		-- The buff frame's icon count: casts landing, Judgement, shields breaking, charges spent.
		local count = ns.BuffIcons()
		if count < icons then IconLost(now) end
		icons = count
		if #landing > 0 then WatchLanding(now, count) end
		if pending then Settle(now, now - pending.at >= CONSUME_WINDOW) end
		SettleProbe(now, false)
		if dirty and now >= nextScan then
			dirty = false
			nextScan = now + SCAN_EVERY
			Scan()
		end
		-- Readable, the readings end buffs on time themselves (UNIT_AURA on removal).
		if not readable then Expire(now) end
		if gateDirty or now >= nextGate then
			gateDirty = false
			nextGate = now + 0.25
			if readable then Calibrate(now) else WatchGate(now) end
		end
	end)
	UpdateAbsorb()
end
