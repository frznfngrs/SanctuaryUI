SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.PowerTrace = ns.PowerTrace or {}
local P = ns.PowerTrace

-- /sanctuary power [spell|off]: what the resource globe showed against what the game let you
-- spend, for a minute and a half (#8, #19). Two guesses about this client's energy have gone
-- opposite ways: read on every UNIT_POWER_FREQUENT, the globe ran ahead (Claw at about 47
-- shown); read on UNIT_POWER_UPDATE alone, it lags (Claw goes off below 40 shown) and moves
-- in chunks. So this writes down, into the log, each server update (its value and the time
-- since the last), how often the client counted in between, and for every cast and every "not
-- enough energy" the globe's number, the client's own number and the spell's cost. With a
-- spell named, also the moments it turns usable or not for want of power, and its cost
-- (talents like Ferocity included) at the start.

local DURATION = 90
local run
local frame

local GetPowerCost = C_Spell and C_Spell.GetSpellPowerCost or GetSpellPowerCost
local GetSpellName = (C_Spell and C_Spell.GetSpellName) or function(id)
	return GetSpellInfo and (GetSpellInfo(id)) or nil
end
local IsSpellUsable = (C_Spell and C_Spell.IsSpellUsable) or IsUsableSpell

local function Secret(value)
	return issecretvalue and issecretvalue(value) or false
end

local function Plain(value)
	return value ~= nil and not Secret(value) and value or nil
end

local function Show(value)
	if value == nil then return "nil" end
	if Secret(value) then return "secret" end
	return tostring(value)
end

local function Line(fmt, ...)
	local ok, text = pcall(string.format, fmt, ...)
	text = ("%6.2f %s"):format(GetTime() - run.start, ok and text or tostring(fmt))
	local was = ns.forceLog
	ns.forceLog = true
	ns.Log("power: %s", text)
	ns.forceLog = was
end

-- The globe's number and the client's own, for the pool the globe shows.
local function Values()
	local powerType = UnitPowerType("player")
	local shown
	if ns.Globes and ns.Globes.ShownPower then shown = ns.Globes.ShownPower() end
	local client = UnitPower("player", Plain(powerType))
	return Plain(shown), Plain(client), Plain(powerType)
end

-- What a spell costs in the pool you have up now.
local function CostOf(spell, powerType)
	if spell == nil or Secret(spell) or not GetPowerCost or powerType == nil then return nil end
	local ok, costs = pcall(GetPowerCost, spell)
	if not ok or type(costs) ~= "table" then return nil end
	for _, info in ipairs(costs) do
		local okInfo, kind, cost = pcall(function() return info.type, info.cost end)
		if okInfo and Plain(kind) == powerType then return Plain(cost) end
	end
	return nil
end

local function NameOf(spellID)
	if spellID == nil or Secret(spellID) then return "?" end
	local ok, name = pcall(GetSpellName, spellID)
	return ok and Plain(name) or tostring(spellID)
end

-- The named spell: usable, or held back by power alone.
local function CheckUsable(why)
	if not run.spell or not IsSpellUsable then return end
	local ok, usable, noPower = pcall(IsSpellUsable, run.spell)
	if not ok then return end
	usable, noPower = Plain(usable), Plain(noPower)
	local state = usable and "usable" or (noPower and "short" or "other")
	if state == run.usable then return end
	local shown, client, powerType = Values()
	local cost = CostOf(run.spell, powerType)
	Line("%s %s (%s): globe %s, client %s, cost %s", run.spellName, state, why, Show(shown), Show(client), Show(cost))
	if run.usable == "short" and state == "usable" and shown and cost then
		run.flips[#run.flips + 1] = shown - cost
	end
	run.usable = state
end

local function OnEvent(_, event, ...)
	if not run then return end
	if event == "UNIT_POWER_FREQUENT" then
		run.frequent = run.frequent + 1
		CheckUsable("counted")
	elseif event == "UNIT_POWER_UPDATE" then
		local _, token = ...
		local shown, client = Values()
		local now = GetTime()
		local gap = run.lastUpdate and now - run.lastUpdate or 0
		local step = client and run.lastValue and client - run.lastValue
		Line("update %s: client %s, globe %s, %+d, %.2f s since the last, %d counts between",
			Show(token), Show(client), Show(shown), step or 0, gap, run.frequent)
		if step and step > 0 and run.lastUpdate then
			run.gaps[#run.gaps + 1], run.steps[#run.steps + 1] = gap, step
		end
		run.lastUpdate, run.lastValue, run.frequent = now, client, 0
		CheckUsable("update")
	elseif event == "UNIT_SPELLCAST_SENT" then
		local _, _, castGUID, spellID = ...
		local shown, client, powerType = Values()
		if castGUID ~= nil and not Secret(castGUID) then
			run.sent[castGUID] = { shown = shown, client = client, cost = CostOf(spellID, powerType) }
		end
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" or event == "UNIT_SPELLCAST_FAILED" then
		local _, castGUID, spellID = ...
		local key = castGUID ~= nil and not Secret(castGUID) and castGUID or nil
		local sent = key and run.sent[key]
		if key then run.sent[key] = nil end
		local shown, client, powerType = Values()
		local cost = CostOf(spellID, powerType)
		if sent then shown, client, cost = sent.shown, sent.client, sent.cost or cost end
		if not cost or cost <= 0 then return end
		local ok = event == "UNIT_SPELLCAST_SUCCEEDED"
		Line("%s %s: globe %s, client %s, cost %s", ok and "cast" or "failed", NameOf(spellID), Show(shown), Show(client), Show(cost))
		if ok and shown then
			run.casts = run.casts + 1
			if shown < cost then
				run.below = run.below + 1
				run.belowBy = math.max(run.belowBy, cost - shown)
			end
		end
	elseif event == "UI_ERROR_MESSAGE" then
		local _, message = ...
		if message == nil or Secret(message) then return end
		local short = message == _G.ERR_OUT_OF_ENERGY or message == _G.ERR_OUT_OF_RAGE
			or message == _G.ERR_OUT_OF_MANA or message == _G.ERR_OUT_OF_FOCUS
			or message == _G.ERR_OUT_OF_POWER_DISPLAY
		if not short then return end
		local shown, client, powerType = Values()
		local cost = run.spell and CostOf(run.spell, powerType)
		Line("not enough (%s): globe %s, client %s%s", message, Show(shown), Show(client),
			cost and (", " .. run.spellName .. " costs " .. cost) or "")
		run.short = run.short + 1
		if shown and cost and shown >= cost then run.shortAbove = run.shortAbove + 1 end
	elseif event == "SPELL_UPDATE_USABLE" or event == "ACTIONBAR_UPDATE_USABLE" then
		CheckUsable("usable event")
	end
end

local EVENTS = { "SPELL_UPDATE_USABLE", "ACTIONBAR_UPDATE_USABLE", "UI_ERROR_MESSAGE" }
local UNIT_EVENTS = { "UNIT_POWER_FREQUENT", "UNIT_POWER_UPDATE", "UNIT_SPELLCAST_SENT",
	"UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED" }

local function Average(list)
	if #list == 0 then return nil end
	local sum = 0
	for _, v in ipairs(list) do sum = sum + v end
	return sum / #list
end

function P.Stop(quiet)
	if not run then return end
	if frame then frame:UnregisterAllEvents() end
	local r = run
	run = nil
	local parts = { ("%d cast(s) with a cost"):format(r.casts) }
	if r.casts > 0 then
		parts[#parts + 1] = r.below > 0 and ("the globe showed less than the cost on %d (by up to %d)"):format(r.below, r.belowBy)
			or "the globe never showed less than the cost"
	end
	parts[#parts + 1] = r.spellName and ("%d \"not enough\" (%d with the globe at or over %s's cost)"):format(r.short, r.shortAbove, r.spellName)
		or ("%d \"not enough\""):format(r.short)
	local gap, step = Average(r.gaps), Average(r.steps)
	if gap then parts[#parts + 1] = ("regen came every %.1f s, +%.0f on average"):format(gap, step) end
	local flip = Average(r.flips)
	if flip then parts[#parts + 1] = ("%s turned usable with the globe %+.0f from its cost"):format(r.spellName, flip) end
	local text = table.concat(parts, "; ")
	local was = ns.forceLog
	ns.forceLog = true
	ns.Log("power: summary: %s", text)
	ns.forceLog = was
	if not quiet then
		ns.Print("Power trace done: " .. text .. ". /sanctuary log has the details; please send them with the summary.")
	end
end

function P.Start(spell)
	if run then P.Stop(true) end
	frame = frame or CreateFrame("Frame")
	frame:SetScript("OnEvent", OnEvent)
	run = {
		start = GetTime(), frequent = 0, sent = {}, gaps = {}, steps = {}, flips = {},
		casts = 0, below = 0, belowBy = 0, short = 0, shortAbove = 0,
	}
	local token = run
	if spell and spell ~= "" then
		run.spell = tonumber(spell) or spell
		run.spellName = type(run.spell) == "number" and NameOf(run.spell) or spell
	end
	for _, event in ipairs(EVENTS) do frame:RegisterEvent(event) end
	for _, event in ipairs(UNIT_EVENTS) do frame:RegisterUnitEvent(event, "player") end
	local shown, client, powerType = Values()
	local _, class = UnitClass("player")
	local form = GetShapeshiftForm and Plain(GetShapeshiftForm()) or 0
	Line("start: %s level %s, form %s, power type %s, globe %s, client %s, max %s%s", Show(class), Show(UnitLevel("player")),
		Show(form), Show(powerType), Show(shown), Show(client), Show(UnitPowerMax("player", powerType)),
		run.spell and (", " .. run.spellName .. " costs " .. Show(CostOf(run.spell, powerType))) or "")
	CheckUsable("start")
	C_Timer.After(DURATION, function()
		if run == token then P.Stop() end
	end)
	ns.Print(("Tracing your %s for %d s. Fight as usual%s; /sanctuary power off stops early."):format(
		powerType == (Enum and Enum.PowerType and Enum.PowerType.Energy) and "energy" or "power", DURATION,
		run.spell and (" and use " .. run.spellName .. " as soon as it lights up") or ""))
end

function P.Command(rest)
	rest = rest or ""
	if rest:lower() == "off" or rest:lower() == "stop" then
		if run then P.Stop() else ns.Print("No power trace running.") end
		return
	end
	P.Start(rest)
end
