SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.Watch = ns.Watch or {}

-- Knows whether a few chosen buffs on you are up, in combat too, for effects that show them
-- (GlobeAura.lua lights a globe from behind). In combat this client won't let an addon read
-- your buffs at all, so each buff is followed from what is still visible:
--
--   reading   out of combat: the buff itself, with its real timing. Always wins.
--   casting   your casts are readable in combat. A seal cast puts that seal up for its
--             length (learned from readings, else its spell text, else the default below)
--             and ends any other seal, since a paladin holds one seal at a time.
--   judging   Judgement unleashes the seal. Whether that also ends it depends on the game's
--             rules, so it is found out: Blizzard's buff frame losing an icon right at the
--             cast says the seal went; a reading after combat that still shows the old seal
--             says it stays. What has been seen is saved and used when the icon count can't
--             tell (the frame was full).
--   the gate  Judgement can't be cast without a seal, so whether it is usable says whether a
--             seal is up. That is only trusted after it has agreed with real readings a few
--             times, so a client where it means something else never misleads us.
--   timing    a buff with no newer word ends when its time runs out; death ends them all.
--
-- What can't be seen: a seal cancelled by hand or purged by an enemy in combat stays lit
-- until its time runs out (30 seconds at most for seals). The first reading after combat
-- puts it right.

local EFFECTS = {
	-- spells: rank 1 IDs, read back as names so every rank and locale matches.
	-- globe: "health" or "mana". tint: GlobeAura.lua's colours. length: seconds, if neither a
	-- reading nor the spell text has said.
	{ key = "sealOfLight", spells = { 20165 }, names = { "Seal of Light" }, group = "seal", globe = "health", tint = "holy", length = 30,
		label = "Seal of Light", desc = "Gold light radiates from behind the health globe." },
	{ key = "sealOfWisdom", spells = { 20166 }, names = { "Seal of Wisdom" }, group = "seal", globe = "mana", tint = "arcane", length = 30,
		label = "Seal of Wisdom", desc = "Blue light radiates from behind the mana globe." },
}
ns.Watch.EFFECTS = EFFECTS

-- Every seal, tracked or not: casting any of them ends the others. IDs no client has are
-- skipped; the English names cover a client that can't name an ID.
local GROUPS = {
	seal = {
		spells = { 20154, 21084, 21082, 20164, 20165, 20166, 20375, 31801, 31892, 53720, 348704 },
		names = { "Seal of Righteousness", "Seal of the Crusader", "Seal of Justice", "Seal of Light", "Seal of Wisdom",
			"Seal of Command", "Seal of Vengeance", "Seal of Blood", "Seal of the Martyr", "Seal of Corruption" },
	},
}

-- Spells that unleash a group, and the one whose usability is the gate.
local CONSUMERS = {
	judgement = { spells = { 20271, 53407, 53408 }, names = { "Judgement", "Judgement of Light", "Judgement of Wisdom", "Judgement of Justice" },
		group = "seal", gate = 20271 },
}

local CONSUME_WINDOW = 0.6 -- seconds after the cast for the buff frame to drop an icon
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
	if not global then return { consume = {}, gate = {} } end
	global.watch = global.watch or {}
	local store = global.watch
	store.consume = store.consume or {}
	store.gate = store.gate or {}
	return store
end

-- Buff lengths shared with ActiveSkill.lua (learned from readings, saved per account).
local function Lengths()
	local global = ns.db and ns.db.global
	if not global then return {} end
	global.buffLengths = global.buffLengths or {}
	return global.buffLengths
end

---------------------------------------------------------------------------
-- Names. Spell IDs differ by rank; names don't, so casts and readings match on names.

local effectByName, effectByID = {}, {}
local groupByName, groupByID = {}, {}
local consumerByName, consumerByID = {}, {}
local groupNames = {} -- group -> list of names, for ActiveSkill.Forget

local function Index(def, byName, byID, value, names)
	for _, id in ipairs(def.spells or {}) do
		byID[id] = value
		local name = GetSpellName(id)
		if Readable(name) then
			byName[name] = value
			if names then names[name] = true end
		end
	end
	for _, name in ipairs(def.names or {}) do
		byName[name] = value
		if names then names[name] = true end
	end
end

local function BuildNames()
	wipe(effectByName); wipe(effectByID)
	wipe(groupByName); wipe(groupByID)
	wipe(consumerByName); wipe(consumerByID)
	wipe(groupNames)
	for _, effect in ipairs(EFFECTS) do
		Index(effect, effectByName, effectByID, effect)
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

---------------------------------------------------------------------------
-- State. One entry per effect: up, start, expires (nil: no timer known), length, source
-- ("reading" or "cast"), and since (when it last went up or down).

local state = {}
local listeners = {}
local readable = false -- the last scan could read your buffs
local groupUp = {} -- group -> { aura } when a reading showed one of its members (tracked or not)
local groupCast = {} -- group -> { name, at, expires } for the last member cast, tracked or not

for _, effect in ipairs(EFFECTS) do
	state[effect.key] = { up = false, since = 0 }
end

function ns.Watch.State(key)
	return state[key]
end

function ns.Watch.Effect(key)
	for _, effect in ipairs(EFFECTS) do
		if effect.key == key then return effect end
	end
end

-- fn(key, state, reason). Reasons: reading, cast, refreshed, gone, expired, replaced,
-- consumed, gate, died.
function ns.Watch.OnChange(fn)
	listeners[#listeners + 1] = fn
end

local function Notify(key, reason)
	for _, fn in ipairs(listeners) do
		local ok, err = pcall(fn, key, state[key], reason)
		if not ok then ns.Log("watch: listener failed: %s", tostring(err)) end
	end
end

local function Up(effect, start, expires, length, source, reason)
	local st = state[effect.key]
	local was = st.up
	local moved = not was or math.abs((st.expires or 0) - (expires or 0)) > 0.25 or st.source ~= source
	st.up, st.start, st.expires, st.length, st.source = true, start, expires, length, source
	if not was then st.since = GetTime() end
	if moved then
		ns.Log("watch: %s up (%s, %s)", effect.key, reason,
			expires and ("%.1fs left"):format(expires - GetTime()) or "no timer")
		Notify(effect.key, was and reason == "cast" and "refreshed" or reason)
	end
end

local function Down(effect, reason)
	local st = state[effect.key]
	if not st.up then return end
	st.up, st.start, st.expires, st.length, st.source = false, nil, nil, nil, nil
	st.since = GetTime()
	ns.Log("watch: %s down (%s)", effect.key, reason)
	Notify(effect.key, reason)
end

-- Every member of a group but the one just cast (keepName) ends, tracked or not:
-- ActiveSkill.lua may be lighting an untracked one's socket.
local function EndGroup(group, keepName, reason)
	for _, effect in ipairs(EFFECTS) do
		if effect.group == group and not (keepName and effectByName[keepName] == effect) then
			Down(effect, reason)
		end
	end
	if ns.ActiveSkill and ns.ActiveSkill.Forget and groupNames[group] then
		for name in pairs(groupNames[group]) do
			if name ~= keepName then ns.ActiveSkill.Forget(name) end
		end
	end
end

local function LengthOf(effect, id, name)
	if test then return tonumber(ns.DB().globeAuras.testLength) or effect.length, "test" end
	local lengths = Lengths()
	local learned = (id and lengths[id]) or (name and lengths[name])
	if learned and learned > 0 then return learned, "learned" end
	local described = id and ns.DescribedLength(id)
	if described and described > 0 then return described, "spell text" end
	return effect.length, "default"
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
		local effect = Lookup(effectByID, effectByName, id, name)
		if effect then
			seen[effect] = { aura = aura, id = id, name = name }
		end
	end
	for _, effect in ipairs(EFFECTS) do
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
				-- Up with no timer we can read: keep a cast's timing if there is one.
				local st = state[effect.key]
				Up(effect, st.start or now, st.up and st.expires or nil, st.length, "reading", "reading")
			end
		else
			local st = state[effect.key]
			-- A cast's buff can reach the reading a moment after the cast event.
			if not (st.up and st.source == "cast" and now - (st.start or 0) < GRACE) then
				-- Gone right after a Judgement: it was spent.
				local judged = lastJudgement and now - lastJudgement < GRACE
				Down(effect, judged and effect.group and "consumed" or "gone")
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

local function SealExpires(group)
	local latest
	for _, effect in ipairs(EFFECTS) do
		local st = state[effect.key]
		if effect.group == group and st.up and st.expires then
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
		if effect.group == group and state[effect.key].up then return true end
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

local function OnCast(spellID, now)
	local name = GetSpellName(spellID)
	if not Readable(name) then name = nil end
	local group = Lookup(groupByID, groupByName, spellID, name)
	local effect = Lookup(effectByID, effectByName, spellID, name)
	if group then
		EndGroup(group, name, "replaced")
		local length = effect and LengthOf(effect, spellID, name) or ns.DescribedLength(spellID)
		groupCast[group] = { name = name, at = now, expires = length and now + length }
	end
	if effect then
		local length, from = LengthOf(effect, spellID, name)
		ns.Log("watch: cast %s, %ss (%s)", tostring(name), tostring(length), from)
		Up(effect, now, now + length, length, "cast", "cast")
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

-- A trusted gate closing ends the group outright (a seal that ran out early, was cancelled or
-- purged, or was judged away).
local gateClosedAt = {}
local function WatchGate(now)
	if test then return end
	for key, consumer in pairs(CONSUMERS) do
		local any = false
		for _, effect in ipairs(EFFECTS) do
			if effect.group == consumer.group and state[effect.key].up then any = true end
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
		if st.up and st.expires and now >= st.expires then
			Down(effect, "expired")
		end
	end
	for group, cast in pairs(groupCast) do
		if cast.expires and now >= cast.expires then groupCast[group] = nil end
	end
end

---------------------------------------------------------------------------

function ns.Watch.Report()
	Scan()
	local now = GetTime()
	ns.Print(("watch report: combat %s, buffs %s"):format(tostring(InCombatLockdown()),
		readable and "readable" or "hidden (following casts)"))
	for _, effect in ipairs(EFFECTS) do
		local st = state[effect.key]
		local length, from = LengthOf(effect, effect.spells[1], GetSpellName(effect.spells[1]))
		ns.Print(("%s: %s%s; lasts %ss (%s)"):format(effect.label, st.up and ("up, from " .. tostring(st.source)) or "down",
			st.up and st.expires and (", %.1fs left"):format(st.expires - now) or "", tostring(length), from))
	end
	for key, consumer in pairs(CONSUMERS) do
		local c = Store().consume[key] or {}
		local g = Store().gate[key] or {}
		ns.Print(("%s: ends the seal %s (seen %d yes, %d no); gate %s, %s (%d agree, %d against)"):format(key,
			Consumes(consumer) and "yes" or "no", c.yes or 0, c.no or 0, tostring(Gate(consumer) or "silent"),
			GateTrusted(consumer) and "trusted" or "not trusted yet", g.agree or 0, g.against or 0))
	end
end

---------------------------------------------------------------------------
-- Test mode.

local function Reset(reason)
	pending, lastConsume = nil, nil
	wipe(groupCast)
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
	if ns.GlobeAura and ns.GlobeAura.OnTest then ns.GlobeAura.OnTest(on) end
end

-- What test mode can play: an effect's key or a word of its name ("light", "wisdom"), or
-- "judge", "fade" (to its last seconds), "clear", "die". Turns test mode on. False if unknown.
function ns.Watch.Test(action)
	action = (action or ""):lower()
	local now = GetTime()
	local effect
	for _, e in ipairs(EFFECTS) do
		if e.key:lower() == action or (action ~= "" and e.label:lower():find(action, 1, true)) then
			effect = e
			break
		end
	end
	if not effect and action ~= "judge" and action ~= "judgement" and action ~= "fade" and action ~= "clear" and action ~= "die" then
		return false
	end
	ns.Watch.SetTest(true)
	if effect then
		OnCast(effect.spells[1], now)
	elseif action == "judge" or action == "judgement" then
		OnCast(CONSUMERS.judgement.spells[1], now)
		if not pending then ns.Print("test: no seal up for Judgement to spend") end
	elseif action == "fade" then
		for _, e in ipairs(EFFECTS) do
			local st = state[e.key]
			if st.up then Up(e, st.start, now + 6.5, st.length, st.source, "reading") end
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
	local driver = CreateFrame("Frame", nil, UIParent)
	ns.Watch.driver = driver
	for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "PLAYER_DEAD",
		"PLAYER_ALIVE", "PLAYER_UNGHOST", "SPELLS_CHANGED", "SPELL_UPDATE_USABLE" }) do
		pcall(driver.RegisterEvent, driver, event)
	end
	for _, event in ipairs({ "UNIT_AURA", "UNIT_SPELLCAST_SUCCEEDED" }) do
		pcall(driver.RegisterUnitEvent, driver, event, "player")
	end
	local gateDirty = false
	driver:SetScript("OnEvent", function(_, event, _, _, spellID)
		if test and event ~= "SPELLS_CHANGED" then return end
		if event == "UNIT_SPELLCAST_SUCCEEDED" then
			if Readable(spellID) then OnCast(spellID, GetTime()) end
			dirty = true
		elseif event == "PLAYER_DEAD" then
			for group in pairs(GROUPS) do groupCast[group] = nil end
			for _, effect in ipairs(EFFECTS) do Down(effect, "died") end
			pending = nil
		elseif event == "SPELLS_CHANGED" then
			BuildNames()
			dirty = true
		elseif event == "SPELL_UPDATE_USABLE" then
			gateDirty = true
		else
			dirty = true
		end
	end)
	local nextScan, nextGate = 0, 0
	driver:SetScript("OnUpdate", function()
		local now = GetTime()
		if pending then
			if now - pending.at >= CONSUME_WINDOW then
				Settle(now, true)
			else
				Settle(now, false)
			end
		end
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
end
