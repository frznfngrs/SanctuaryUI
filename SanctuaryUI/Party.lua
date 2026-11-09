SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.Party = ns.Party or {}
local P = ns.Party

-- Party frames: your four party members (and their pets), stacked under your portrait at the
-- top left, in one of two looks (PartyStyles.lua): Globes, each member a small health globe of
-- the player's own liquid, or Slab, a thin slab of D3 stone. Or None, which leaves Blizzard's
-- party frames (or another addon's) alone. They hide in a raid, where Blizzard's raid frames
-- take over.
--
-- Every member is a secure unit button (left-click targets, right-click opens the unit menu,
-- Clique click-casts on it), shown and hidden by RegisterUnitWatch, so joins and leaves work in
-- combat; their places and sizes change only out of combat.
--
-- This client hides much of another unit's data from addons in combat (health, auras, range
-- may come back secret). Secret values go straight to widgets that take them: StatusBars,
-- SetFormattedText, SetAlphaFromBoolean, and the client's own aura containers, which find and
-- draw a member's debuffs, your buffs on them, and whether one is a debuff you can dispel.

local MAX = 4
local GAP = { globes = 4, slab = 6 } -- between members
local RANGE_ALPHA = 0.45
local RANGE_EVERY = 0.2 -- seconds between range checks (there is no event for it)
local READY_LINGER = 6 -- seconds the ready check's answers stay up after it ends
local DISPEL_PULSE, DISPEL_PULSE_LOW = 0.55, 0.3 -- the dispel halo's pulse: seconds each way, and how far it dims
local AURA_SIZE = { globes = 18, slab = 20 }
local AURA_GAP = 2
local DRIVER = "[group:raid] hide; [group:party] show; hide"

local function Opt()
	return ns.DB().party
end

local function Secret(value)
	return issecretvalue and issecretvalue(value) or false
end

local function Readable(value)
	return value ~= nil and not Secret(value)
end

-- A flag that may be secret, as a plain boolean (secret counts as false).
local function Bool(value)
	if Secret(value) then return false end
	return value and true or false
end

function P.Style()
	local style = Opt().style
	if style == "globes" or style == "slab" then return style end
	return nil
end

---------------------------------------------------------------------------
-- Test mode (Options > Party > Preview, and while frames are unlocked): stand-in members drawn
-- from you, each showing different states, so the look can be judged and placed out of a group.

local PREVIEW = {
	{ name = "Thrall", class = "SHAMAN", level = 60, health = 0.92, power = 0.7, powerToken = "MANA", leader = true, role = "TANK", threat = 3, ready = "ready",
		cast = { name = "Chain Heal", icon = "Interface\\Icons\\Spell_Nature_HealingWaveGreater", seconds = 2.5 } },
	{ name = "Jaina", class = "MAGE", level = 58, health = 0.48, heal = 0.18, absorb = 0.1, power = 0.42, powerToken = "MANA", role = "HEALER", mark = 1, dispel = true,
		cast = { name = "Blizzard", icon = "Interface\\Icons\\Spell_Frost_IceStorm", seconds = 4, channel = true } },
	{ name = "Grom", class = "WARRIOR", level = 60, health = 0, power = 0, powerToken = "RAGE", state = "dead", role = "DAMAGER", target = true },
	{ name = "Sylvanas", class = "HUNTER", level = 42, health = 0.76, power = 0.9, powerToken = "MANA", far = true, ready = "waiting", role = "DAMAGER" },
}
local PREVIEW_PET = { name = "Wolf", health = 0.8 }

function P.Previewing()
	return (P.preview or not ns.DB().locked) and true or false
end

-- The stand-in's data when this button is previewing (its unit isn't there), else nil.
local function PV(b)
	if not P.Previewing() or UnitExists(b.unit) then return nil end
	if b.isPet then return b.index == 1 and PREVIEW_PET or nil end
	return PREVIEW[b.index]
end

-- The unit a button reads: its own, or you (your pet) while it stands in.
local function U(b)
	if PV(b) then
		if b.isPet then return UnitExists("pet") and "pet" or "player" end
		return "player"
	end
	return b.unit
end

---------------------------------------------------------------------------
-- Colours

local function HealthColor()
	local c = ns.Globes and ns.Globes.HEALTH_COLOR or { 0.86, 0.07, 0.05 }
	return c[1], c[2], c[3]
end

local function PowerColorOf(token, powerType)
	local colors = ns.Globes and ns.Globes.POWER_COLORS
	local c = Readable(token) and colors and colors[token]
	if c then return c[1], c[2], c[3] end
	local info = PowerBarColor and ((Readable(token) and PowerBarColor[token]) or (Readable(powerType) and PowerBarColor[powerType]))
	if info and info.r then return info.r, info.g, info.b end
	return 0.18, 0.36, 1.0
end

-- Dispel types, as the client names them, and the colours their frames and halo take.
local DISPEL_COLORS = {
	None = { 0.8, 0.1, 0.08 }, -- D3's own debuff red
	Magic = { 0.2, 0.6, 1.0 },
	Curse = { 0.6, 0.0, 1.0 },
	Disease = { 0.6, 0.4, 0.0 },
	Poison = { 0.0, 0.6, 0.0 },
	Bleed = { 0.6, 0.0, 0.1 },
}

local function ColorMap()
	local map = {}
	for key, c in pairs(DISPEL_COLORS) do
		map[key] = CreateColor and CreateColor(c[1], c[2], c[3]) or { r = c[1], g = c[2], b = c[3] }
	end
	return map
end

---------------------------------------------------------------------------
-- What you can dispel, from the spells you know (rank IDs of this client's era). Read from the
-- spellbook only: no CVar flipping to reveal hidden ranks (an addon's SetCVar taints).

local DISPELS = {
	PRIEST = { Magic = { 527, 988 }, Disease = { 528, 552 } },
	PALADIN = { Magic = { 4987 }, Poison = { 1152, 4987 }, Disease = { 1152, 4987 } },
	DRUID = { Curse = { 2782 }, Poison = { 8946, 2893 } },
	SHAMAN = { Poison = { 526 }, Disease = { 2870 } },
	MAGE = { Curse = { 475 } },
	WARLOCK = { Magic = { 19505, 19731, 19734, 19736, pet = true } }, -- the felhunter's Devour Magic
}

local function Known(id, pet)
	local checks = {
		function() return IsPlayerSpell and not pet and IsPlayerSpell(id) end,
		function() return IsSpellKnown and IsSpellKnown(id, pet or nil) end,
		function() return C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(id, pet and Enum.SpellBookSpellBank.Pet or nil) end,
		function() return C_SpellBook and C_SpellBook.IsSpellInSpellBook and C_SpellBook.IsSpellInSpellBook(id, pet and 1 or nil, true) end,
	}
	for _, check in ipairs(checks) do
		local ok, known = pcall(check)
		if ok and Readable(known) and known then return true end
	end
	return false
end

local function MyDispelTypes()
	local _, class = UnitClass("player")
	local list, any = {}, false
	for kind, ids in pairs(DISPELS[class] or {}) do
		for _, id in ipairs(ids) do
			if Known(id, ids.pet) then
				list[kind] = true
				any = true
				break
			end
		end
	end
	return list, any
end

---------------------------------------------------------------------------
-- Health text (the target plate's formats, cut down): percent, hitpoints or missing.

local function Num(value)
	local f = AbbreviateNumbers or AbbreviateLargeNumbers
	if f then
		local ok, text = pcall(f, value)
		if ok and type(text) ~= "nil" then return text end
	end
	return value
end

local curves = {}
local function Curve(key, points)
	if curves[key] == nil then
		curves[key] = false
		if C_CurveUtil and C_CurveUtil.CreateCurve then
			local ok, curve = pcall(C_CurveUtil.CreateCurve)
			if ok and curve then
				for _, p in ipairs(points) do pcall(curve.AddPoint, curve, p[1], p[2]) end
				curves[key] = curve
			end
		end
	end
	return curves[key] or nil
end
local FULL_POINTS = { { 0, 1 }, { 0.9995, 1 }, { 1, 0 } }

-- Returns true and the percent (0-100, maybe secret), or false.
local function HealthPercent(unit, health, maxHealth)
	if UnitHealthPercent then
		local curve = CurveConstants and CurveConstants.ScaleTo100
		local ok, pct = pcall(UnitHealthPercent, unit, true, curve)
		if ok and type(pct) ~= "nil" then
			if curve then return true, pct end
			local ok2, scaled = pcall(function() return pct * 100 end)
			if ok2 then return true, scaled end
		end
	end
	if Readable(health) and Readable(maxHealth) and maxHealth > 0 then
		return true, health / maxHealth * 100
	end
	return false
end

local function SetHealthText(fs, unit, health, maxHealth, pv)
	local mode = Opt().healthText or "percent"
	fs:SetAlpha(1)
	if mode == "none" then
		fs:SetText("")
		return
	end
	if pv then
		if mode == "percent" then
			fs:SetFormattedText("%d%%", math.floor(pv.health * 100 + 0.5))
		elseif mode == "current" then
			fs:SetText(Num(math.floor(pv.health * 24800)))
		else
			fs:SetText(pv.health < 1 and ("-" .. Num(math.floor((1 - pv.health) * 24800))) or "")
		end
		return
	end
	local ok = false
	if mode == "percent" then
		local has, pct = HealthPercent(unit, health, maxHealth)
		ok = has and pcall(fs.SetFormattedText, fs, "%.0f%%", pct)
	elseif mode == "current" then
		ok = pcall(fs.SetFormattedText, fs, "%s", Num(ns.Or(health, 0)))
	elseif mode == "missing" then
		local missing
		if Readable(health) and Readable(maxHealth) then
			missing = math.max(0, maxHealth - health)
		elseif UnitHealthMissing then
			local got, value = pcall(UnitHealthMissing, unit, true)
			if got then missing = value end
		end
		ok = type(missing) ~= "nil" and pcall(fs.SetFormattedText, fs, "-%s", Num(missing))
		-- Nothing to show at full health.
		if Readable(health) and Readable(maxHealth) then
			fs:SetAlpha(health >= maxHealth and 0 or 1)
		else
			local curve = UnitHealthPercent and Curve("full", FULL_POINTS)
			local got, alpha = false, nil
			if curve then got, alpha = pcall(UnitHealthPercent, unit, true, curve) end
			if not (got and type(alpha) ~= "nil" and pcall(fs.SetAlpha, fs, alpha)) then fs:SetAlpha(1) end
		end
	end
	if not ok then fs:SetText("") end
end

---------------------------------------------------------------------------
-- Updates. Each takes a button and draws into its active view (b.v).

local function Fill(bar, value, maxValue)
	if Readable(maxValue) then
		bar:SetMinMaxValues(0, maxValue > 0 and maxValue or 1)
	else
		pcall(bar.SetMinMaxValues, bar, 0, ns.Or(maxValue, 1))
	end
	if not pcall(bar.SetValue, bar, ns.Or(value, 0)) then bar:SetValue(0) end
end

-- dead | ghost | offline, or nil.
local function State(b, unit, pv)
	if pv then return pv.state end
	local connected = UnitIsConnected(unit)
	if Readable(connected) and not connected then return "offline" end
	local ghost = UnitIsGhost(unit)
	if Readable(ghost) and ghost then return "ghost" end
	local dead = UnitIsDead(unit)
	if Readable(dead) and dead then return "dead" end
	return nil
end

local STATE_TEXT = { dead = DEAD or "Dead", ghost = "Ghost", offline = PLAYER_OFFLINE or "Offline" }

local function UpdateHealth(b)
	local v = b.v
	if not v then return end
	local unit, pv = U(b), PV(b)
	if not pv and not UnitExists(unit) then return end
	local health, maxHealth
	if pv then
		maxHealth = 1000
		health = math.floor(pv.health * maxHealth + 0.5)
	else
		health, maxHealth = UnitHealth(unit), UnitHealthMax(unit)
	end
	local state = State(b, unit, pv)
	b.state = state

	local r, g, bl = HealthColor()
	if state == "offline" then r, g, bl = 0.32, 0.32, 0.32 end
	if state == "dead" or state == "ghost" then health = 0 end
	if v.pool then
		v.pool:SetColor(r, g, bl)
		ns.Liquid.SetValue(v.health, health, maxHealth)
	else
		v.health:SetStatusBarColor(r, g, bl, 1)
		if v.liquid then
			v.liquid.color = { math.min(1, r + 0.35), math.min(1, g + 0.3), math.min(1, bl + 0.25) }
		end
		Fill(v.health, health, maxHealth)
	end

	-- Incoming heals and shields, as the globes pour them.
	local amount, shield, clamped = 0, 0, false
	if pv then
		amount, shield = (pv.heal or 0) * maxHealth, (pv.absorb or 0) * maxHealth
	elseif not state and Opt().healPrediction ~= false then
		amount, shield, clamped = ns.IncomingHeals(unit, health, maxHealth)
	end
	if v.pool and v.pool.bands then
		v.pool:SetBand("heal", ns.Or(amount, 0), maxHealth)
		v.pool:SetBand("absorb", ns.Or(shield, 0), maxHealth)
		v.pool:SetShield(clamped)
	elseif v.heal then
		local top = ns.Or(maxHealth, 1)
		for _, pair in ipairs({ { v.heal, amount }, { v.absorb, shield } }) do
			pcall(pair[1].SetMinMaxValues, pair[1], 0, top)
			if not pcall(pair[1].SetValue, pair[1], ns.Or(pair[2], 0)) then pair[1]:SetValue(0) end
		end
		local over = v.overShield
		if Secret(clamped) then
			if not (over.SetAlphaFromBoolean and pcall(over.SetAlphaFromBoolean, over, clamped, 1, 0)) then over:SetAlpha(0) end
		else
			over:SetAlpha(clamped and 1 or 0)
		end
	end

	if v.status then v.status:SetText(state and STATE_TEXT[state] or "") end
	if v.pct then
		if state then
			v.pct:SetText("")
		else
			SetHealthText(v.pct, unit, health, maxHealth, pv)
		end
	end
end

local function UpdatePower(b)
	local v = b.v
	if not v or not v.power then return end
	local unit, pv = U(b), PV(b)
	if pv then
		v.power:SetStatusBarColor(PowerColorOf(pv.powerToken))
		Fill(v.power, pv.power * 100, 100)
		return
	end
	if not UnitExists(unit) then return end
	local powerType, token = UnitPowerType(unit)
	v.power:SetStatusBarColor(PowerColorOf(token, powerType))
	if b.state then
		Fill(v.power, 0, 1)
	else
		Fill(v.power, UnitPower(unit), UnitPowerMax(unit))
	end
end

-- The portrait: the moving 3D bust in the slab's square socket when the unit is in view, else
-- the round 2D one (always, in the globes' round medallion). Greyed while dead or offline.
local function UpdatePortrait(b)
	local v = b.v
	if not v or not v.face then return end -- a globe pet has none
	local unit, pv = U(b), PV(b)
	if not UnitExists(unit) then return end
	local state = b.state
	local visible = UnitIsVisible(unit)
	if v.model and Opt().portrait3d ~= false and not state and Bool(visible) then
		v.model:SetUnit(unit)
		pcall(v.model.SetPortraitZoom, v.model, 1)
		v.model:Show()
		v.face:Hide()
		return
	end
	if v.model then v.model:Hide() end
	SetPortraitTexture(v.face, unit)
	if v.style == "slab" then
		v.face:SetTexCoord(0.15, 0.85, 0.15, 0.85)
	else
		v.face:SetTexCoord(0.06, 0.94, 0.06, 0.94)
	end
	v.face:SetDesaturated(state and true or false)
	local k = state and 0.6 or 1
	v.face:SetVertexColor(k, k, k)
	v.face:Show()
end

local CREAM = { 0.95, 0.9, 0.8 }

-- A member's class colour ({ r, g, b }, the numbers possibly secret), or nil for a pet.
local function ClassColor(b)
	if b.isPet then return nil end
	local pv, class = PV(b), nil
	if pv then
		class = pv.class
	else
		if not UnitExists(b.unit) then return nil end
		_, class = UnitClass(b.unit)
	end
	if Readable(class) then return RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] end
	if Secret(class) and C_ClassColor and C_ClassColor.GetClassColor then
		local ok, color = pcall(C_ClassColor.GetClassColor, class)
		if ok then return color end
	end
	return nil
end

local function UpdateName(b)
	local v = b.v
	if not v or not v.name then return end
	local unit, pv = U(b), PV(b)
	if not pv and not UnitExists(unit) then return end
	local name = pv and pv.name or UnitName(unit)
	if not pcall(v.name.SetText, v.name, name or "") then v.name:SetText("") end
	local c = ClassColor(b)
	if c then
		if not pcall(v.name.SetTextColor, v.name, c.r, c.g, c.b) then v.name:SetTextColor(CREAM[1], CREAM[2], CREAM[3]) end
	else
		v.name:SetTextColor(CREAM[1], CREAM[2], CREAM[3])
	end
end

-- The level badge. A hidden level still goes to the badge; level 0 or less means unknown.
local function UpdateLevel(b)
	local v = b.v
	if not v or not v.level then return end
	local pv = PV(b)
	local level = pv and pv.level or UnitLevel(b.unit)
	if Secret(level) then
		v.levelBox:SetShown(pcall(v.level.SetFormattedText, v.level, "%d", level))
	elseif level and level > 0 then
		v.level:SetText(level)
		v.levelBox:Show()
	else
		v.levelBox:Hide()
	end
end

-- Role icons in UI-LFG-ICON-PORTRAITROLES, for clients without GetTexCoordsForRoleSmallCircle.
local ROLE_COORDS = {
	TANK = { 0, 19 / 64, 22 / 64, 41 / 64 },
	HEALER = { 20 / 64, 39 / 64, 1 / 64, 20 / 64 },
	DAMAGER = { 20 / 64, 39 / 64, 22 / 64, 41 / 64 },
}

local READY_TEXTURES = {
	ready = READY_CHECK_READY_TEXTURE or "Interface\\RaidFrame\\ReadyCheck-Ready",
	notready = READY_CHECK_NOT_READY_TEXTURE or "Interface\\RaidFrame\\ReadyCheck-NotReady",
	waiting = READY_CHECK_WAITING_TEXTURE or "Interface\\RaidFrame\\ReadyCheck-Waiting",
}

local function UpdateReady(b)
	local v = b.v
	if not v or not v.ready then return end
	local pv = PV(b)
	local status = b.readyHold
	if not status then
		if pv then
			status = pv.ready
		elseif GetReadyCheckStatus then
			status = GetReadyCheckStatus(b.unit)
		end
	end
	local path = Readable(status) and READY_TEXTURES[status]
	if path then
		v.ready:SetTexture(path)
		v.ready:Show()
	else
		v.ready:Hide()
	end
end

local function UpdateIcons(b)
	local v = b.v
	if not v or not v.leader then return end
	local unit, pv = U(b), PV(b)
	if not pv and not UnitExists(unit) then return end
	local leader
	if pv then leader = pv.leader else leader = Bool(UnitIsGroupLeader and UnitIsGroupLeader(unit)) end
	v.leader:SetShown(leader and true or false)

	local role = pv and pv.role
	if not pv and UnitGroupRolesAssigned then role = UnitGroupRolesAssigned(unit) end
	local coords = Readable(role) and ROLE_COORDS[role]
	if coords then
		if GetTexCoordsForRoleSmallCircle then
			local ok, l, r, t, bt = pcall(GetTexCoordsForRoleSmallCircle, role)
			if ok and l then coords = { l, r, t, bt } end
		end
		v.role:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
		v.role:Show()
	else
		v.role:Hide()
	end

	local index = pv and pv.mark
	if not pv and GetRaidTargetIndex then index = GetRaidTargetIndex(unit) end
	if Readable(index) and SetRaidTargetIconTexture then
		SetRaidTargetIconTexture(v.mark, index)
		v.mark:Show()
	else
		v.mark:Hide()
	end
	UpdateReady(b)
end

-- The frame's colour: gold metal and a gold halo on your target, as D3 marks the selected party
-- member; everyone else's metal in their class colour.
local function UpdateTarget(b)
	local v = b.v
	if not v then return end
	local pv = PV(b)
	local gold
	if pv then gold = pv.target else gold = Bool(UnitIsUnit("target", b.unit)) end
	ns.PartyStyles.SetMetal(v, gold and true or false, ClassColor(b))
	if v.select then v.select:SetAlpha(gold and 1 or 0) end
end

---------------------------------------------------------------------------
-- Cast bars. As on the target plate: times can be secret for other units, so the client runs
-- the bar from a duration object where it has one, and a stop event ends it.

local function ReadCast(unit, channel)
	local name, _, texture, startMS, endMS, _, _, _, empowered
	if channel then
		name, _, texture, startMS, endMS, _, _, _, empowered = UnitChannelInfo(unit)
	else
		name, _, texture, startMS, endMS = UnitCastingInfo(unit)
	end
	return name, texture, startMS, endMS, empowered
end

local function StopCast(cast)
	cast:Hide()
	cast.startMS, cast.endMS, cast.timer, cast.demo = nil, nil, nil, nil
end

-- Runs the bar for what has no duration object, and the preview's stand-in.
local function CastOnUpdate(cast)
	if cast.demo then
		local t = (GetTime() / cast.demo.seconds) % 1
		cast.bar:SetValue(cast.demo.channel and 1 - t or t)
		return
	end
	if cast.timer then
		local d = cast.bar.GetTimerDuration and cast.bar:GetTimerDuration()
		local left = d and d.GetRemainingDuration and d:GetRemainingDuration()
		if left and not Secret(left) and left <= 0 then StopCast(cast) end
		return
	end
	if not cast.startMS or not cast.endMS then return end
	local now = GetTime() * 1000
	cast.bar:SetValue(cast.channel and (cast.endMS - (now - cast.startMS)) or now)
	if now >= cast.endMS then StopCast(cast) end
end

-- channel nil: whatever the member is doing, a cast or a channel.
local function StartCast(b, channel)
	local v = b.v
	local cast = v and v.cast
	if not cast then return end
	if not cast.hooked then
		cast.hooked = true
		cast:SetScript("OnUpdate", CastOnUpdate)
	end
	local pv = PV(b)
	if pv then
		StopCast(cast)
		if pv.cast then
			cast.demo = pv.cast
			cast.spellName:SetText(pv.cast.name)
			if cast.icon then cast.icon:SetTexture(pv.cast.icon) end
			cast.bar:SetMinMaxValues(0, 1)
			cast:Show()
		end
		return
	end
	local unit = b.unit
	cast.demo = nil
	if not UnitCastingInfo or not UnitExists(unit) then
		StopCast(cast)
		return
	end
	local isChannel = channel and true or false
	local name, texture, startMS, endMS, empowered = ReadCast(unit, isChannel)
	-- A secret name is still a cast (secrets are never nil).
	if not Secret(name) and not name and channel == nil then
		isChannel = true
		name, texture, startMS, endMS, empowered = ReadCast(unit, true)
	end
	if not Secret(name) and not name then
		StopCast(cast)
		return
	end
	cast.channel = isChannel
	if not pcall(cast.spellName.SetText, cast.spellName, name) then cast.spellName:SetText("") end
	if cast.icon then cast.icon:SetTexture(ns.Or(texture, 136243)) end -- a cog for a spell with no icon

	local bar, duration = cast.bar, nil
	if isChannel then
		if empowered and not Secret(empowered) and UnitEmpoweredChannelDuration then
			duration = UnitEmpoweredChannelDuration(unit)
		else
			duration = UnitChannelDuration and UnitChannelDuration(unit)
		end
	else
		duration = UnitCastingDuration and UnitCastingDuration(unit)
	end
	if duration ~= nil and bar.SetTimerDuration then
		local directions = Enum and Enum.StatusBarTimerDirection
		local direction = directions and (isChannel and directions.RemainingTime or directions.ElapsedTime)
		local smoothing = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate
		bar:SetTimerDuration(duration, smoothing, direction)
		cast.timer, cast.startMS, cast.endMS = true, nil, nil
	elseif Readable(startMS) and Readable(endMS) then
		cast.timer, cast.startMS, cast.endMS = nil, startMS, endMS
		bar:SetMinMaxValues(startMS, endMS)
		bar:SetValue(isChannel and (endMS - (GetTime() * 1000 - startMS)) or GetTime() * 1000)
	else
		-- Nothing to time it by: full until the stop event.
		cast.timer, cast.startMS, cast.endMS = nil, nil, nil
		bar:SetMinMaxValues(0, 1)
		bar:SetValue(1)
	end
	cast:Show()
end

-- The halo: red when the member has aggro (orange as they near it). In preview, the member with
-- a dispellable debuff shows the dispel halo's blue here, since the real one is the client's.
local function UpdateThreat(b)
	local v = b.v
	if not v or not v.glow then return end
	local pv = PV(b)
	if pv and pv.dispel then
		local c = DISPEL_COLORS.Magic
		v.glow:SetVertexColor(c[1], c[2], c[3])
		v.glow:SetAlpha(0.9)
		return
	end
	local status
	if pv then status = pv.threat
	elseif Opt().threat ~= false and UnitThreatSituation then status = UnitThreatSituation(b.unit) end
	if not Readable(status) or status < 1 then
		v.glow:SetAlpha(0)
		return
	end
	local r, g, bl = 1, 0.1, 0.05
	if GetThreatStatusColor then
		local ok, cr, cg, cb = pcall(GetThreatStatusColor, status)
		if ok and Readable(cr) then r, g, bl = cr, cg, cb end
	end
	v.glow:SetVertexColor(r, g, bl)
	v.glow:SetAlpha(status >= 2 and 0.95 or 0.5)
end

local function UpdateRange(b)
	if not b:IsShown() then return end
	if Opt().rangeFade == false then
		b:SetAlpha(1)
		return
	end
	local pv = PV(b)
	if pv then
		b:SetAlpha(pv.far and RANGE_ALPHA or 1)
		return
	end
	if b.state == "offline" then
		b:SetAlpha(RANGE_ALPHA)
		return
	end
	if not UnitInRange then return end
	local inRange, checked = UnitInRange(b.unit)
	if Secret(inRange) then
		if not (b.SetAlphaFromBoolean and pcall(b.SetAlphaFromBoolean, b, inRange, 1, RANGE_ALPHA)) then b:SetAlpha(1) end
		return
	end
	if Secret(checked) then checked = true end
	b:SetAlpha((checked and not inRange) and RANGE_ALPHA or 1)
end

function P.UpdateButton(b)
	if not b.v then return end
	local pv = PV(b)
	if not pv and not UnitExists(b.unit) then return end
	UpdateHealth(b) -- first: it works out dead / offline for the rest
	UpdateName(b)
	UpdateLevel(b)
	UpdatePortrait(b)
	UpdatePower(b)
	UpdateIcons(b)
	UpdateTarget(b)
	UpdateThreat(b)
	UpdateRange(b)
	StartCast(b)
end

function P.UpdateAll()
	for _, b in ipairs(P.all or {}) do
		if b:IsShown() then P.UpdateButton(b) end
	end
end

---------------------------------------------------------------------------
-- Auras, through the client's aura containers (the target plate explains why): a member's
-- debuffs in D3's debuff frame tinted by dispel type, your buffs on them (HoTs, shields) in its
-- gold buff frame, and an aura slot that holds the halo while a debuff you can dispel is on them.

local function HasTemplate(name)
	if not (C_XMLUtil and C_XMLUtil.GetTemplateInfo) then return false end
	local ok, info = pcall(C_XMLUtil.GetTemplateInfo, name)
	return ok and info ~= nil
end

local HAS_CONTAINERS = HasTemplate("CustomAuraContainerTemplate")
local PRESERVE = (Enum and Enum.CustomAuraButtonDispelTypeTextureStyle and Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset)
	or (DispelTypeTextureStyle and DispelTypeTextureStyle.PreserveAsset) or 3

local function AuraSize()
	return AURA_SIZE[P.Style() or "globes"]
end

local function ShowFrame(button, kind)
	local A = ns.Art.PARTY.aura
	local frame = button:CreateTexture(nil, "OVERLAY")
	frame:SetAllPoints()
	if ns.Art.Apply(frame, "partyAura") then
		local rect = A[kind]
		frame:SetTexCoord(rect[1] / A.atlas[1], (rect[1] + rect[3]) / A.atlas[1], rect[2] / A.atlas[2], (rect[2] + rect[4]) / A.atlas[2])
	else
		frame:SetColorTexture(0, 0, 0, 0)
	end
	return frame
end

-- Called by the client for each aura button it makes, before it locks the button. The icon sits
-- inside D3's frame; the debuff frame is tinted by the aura's dispel type, by the client.
local function DressAura(button, kind)
	local size = AuraSize()
	button:SetSize(size, size)
	local inset = size * ns.Art.PARTY.aura.inset
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOPLEFT", inset, -inset)
	icon:SetPoint("BOTTOMRIGHT", -inset, inset)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	button:SetIcon(icon)

	local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	cooldown:SetAllPoints(icon)
	cooldown:SetReverse(true)
	cooldown:EnableMouse(false)
	if cooldown.SetDrawEdge then cooldown:SetDrawEdge(false) end
	if cooldown.SetDrawBling then cooldown:SetDrawBling(false) end
	if cooldown.SetHideCountdownNumbers then cooldown:SetHideCountdownNumbers(true) end
	button:SetDurationCooldown(cooldown)

	local over = CreateFrame("Frame", nil, button)
	over:SetAllPoints()
	over:EnableMouse(false)
	over:SetFrameLevel(cooldown:GetFrameLevel() + 1)
	local frame = ShowFrame(over, kind)
	if kind == "debuff" then
		local c = DISPEL_COLORS.None
		frame:SetVertexColor(c[1], c[2], c[3])
		if button.AddDispelTypeTexture then
			pcall(button.AddDispelTypeTexture, button, frame, {
				style = PRESERVE, showWhenHarmful = true, showWithoutDispelType = true, customDispelColorMap = ColorMap(),
			})
		end
	end
	local count = over:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	count:SetPoint("BOTTOMRIGHT", 1, 1)
	button:SetApplicationCount(count)
	if button.SetTooltipAnchorPoint then button:SetTooltipAnchorPoint("ANCHOR_BOTTOMRIGHT", 0, 0) end
end

local function GroupLayout(size)
	return {
		elementSpacing = AURA_GAP, lineSpacing = AURA_GAP, groupLineSpacing = AURA_GAP, forceNewLine = false,
		elementWidth = size, elementHeight = size,
	}
end

local function Flow(box, count, size)
	local dirs = AnchorUtil and AnchorUtil.FlowDirection or { Left = -1, Right = 1, Up = 1, Down = -1 }
	box:SetFlowLayoutAnchorPoint("TOPLEFT")
	box:SetFlowLayoutGrowthDirection(dirs.Right, dirs.Down)
	box:SetFlowLayoutMaximumLineSize(math.max(1, count) * (size + AURA_GAP))
end

local function SortArgs()
	return AuraContainerSortMethod and AuraContainerSortMethod.Default or 0,
		AuraContainerSortDirection and AuraContainerSortDirection.Normal or 0
end

-- The halo, in the client's aura slot: the active style's halo art drawn twice for strength, in
-- the debuff's colour, pulsing. The client shows it and runs the pulse, so it works in combat.
local function DressDispel(b, slot)
	slot:EnableMouse(false)
	b.dispelSlot = slot
	b.dispelTex = {}
	if b.v then -- else ConfigureAuras places it, once the button has a view
		slot:ClearAllPoints()
		slot:SetAllPoints(b.v.glowBox)
	end
	local pulse = slot:CreateAnimationGroup()
	pulse:SetLooping("BOUNCE")
	for i = 1, 2 do
		local glow = slot:CreateTexture(nil, "OVERLAY")
		glow:SetAllPoints()
		glow:SetBlendMode("ADD")
		b.dispelTex[i] = glow
		if slot.AddDispelTypeTexture then
			pcall(slot.AddDispelTypeTexture, slot, glow, {
				style = PRESERVE, showWhenHarmful = true, showWithoutDispelType = false, customDispelColorMap = ColorMap(),
			})
		end
		local fade = pulse:CreateAnimation("Alpha")
		fade:SetTarget(glow)
		fade:SetFromAlpha(1)
		fade:SetToAlpha(DISPEL_PULSE_LOW)
		fade:SetDuration(DISPEL_PULSE)
	end
	if b.v then P.DispelArt(b) end
	if slot.AddAuraShownAnimation then pcall(slot.AddAuraShownAnimation, slot, pulse) end
end

function P.DispelArt(b)
	local v = b.v
	if not (b.dispelTex and v and v.glowRect) then return end
	local g = v.glowRect
	for _, tex in ipairs(b.dispelTex) do
		if ns.Art.Apply(tex, g.slot) then
			tex:SetTexCoord(ns.Art.PartyCoord(g.style, g.rect))
			tex:SetBlendMode("ADD")
		end
	end
end

local function MakeAuras(b)
	if not HAS_CONTAINERS then return end
	local method, direction = SortArgs()
	local ok, err = pcall(function()
		local debuffs = CreateFrame("AuraContainer", nil, b, "CustomAuraContainerTemplate")
		debuffs:SetSize(1, 1)
		debuffs:AddAuraGroup("debuffs", "HARMFUL", {
			maxFrameCount = Opt().maxDebuffs or 4, sortMethod = method, sortDirection = direction,
			initializeFrame = function(button) DressAura(button, "debuff") end, layout = GroupLayout(AuraSize()),
		})
		debuffs:SetUnit(b.unit)
		debuffs:SetEnabled(true)
		local buffs = CreateFrame("AuraContainer", nil, b, "CustomAuraContainerTemplate")
		buffs:SetSize(1, 1)
		buffs:AddAuraGroup("mine", "HELPFUL|PLAYER", {
			maxFrameCount = Opt().maxBuffs or 3, sortMethod = method, sortDirection = direction,
			initializeFrame = function(button) DressAura(button, "buff") end, layout = GroupLayout(AuraSize()),
		})
		buffs:SetUnit(b.unit)
		buffs:SetEnabled(true)
		b.debuffBox, b.buffBox = debuffs, buffs
	end)
	if not ok and ns.LogError then ns.LogError("party", "aura containers: " .. tostring(err)) end

	local okD, errD = pcall(function()
		local box = CreateFrame("AuraContainer", nil, b, "CustomAuraContainerTemplate")
		local types = MyDispelTypes()
		box:AddAuraSlot("dispel", "HARMFUL", {
			candidateFilters = { includeDispelTypes = types },
			initializeFrame = function(slot) DressDispel(b, slot) end,
		})
		box:SetUnit(b.unit)
		box:SetEnabled(true)
		b.dispelBox = box
	end)
	if not okD and ns.LogError then ns.LogError("party", "dispel slot: " .. tostring(errD)) end
end

-- Filters, counts, sizes and places: out of combat only (the buttons are locked in it).
local function ConfigureAuras(b)
	if InCombatLockdown() then return end
	local opt, v = Opt(), b.v
	if not v then return end
	local size = AuraSize()
	local pv = PV(b)
	-- Previewing, your own buffs stand in for the debuffs on two of the members.
	local unit = pv and "player" or b.unit
	local standIn = pv and (b.index == 2 or b.index == 4)
	if b.debuffBox then
		local box, max = b.debuffBox, math.min(8, opt.maxDebuffs or 4)
		local on = opt.debuffs ~= false and (not pv or standIn)
		pcall(function()
			box:SetAuraGroupEnabled("debuffs", on)
			box:SetAuraGroupMaxFrameCount("debuffs", on and max or 0)
			box:SetAuraGroupFilterString("debuffs", standIn and "HELPFUL" or "HARMFUL")
			box:SetAuraGroupLayout("debuffs", GroupLayout(size))
			for i = 1, box:GetAuraGroupFrameCount("debuffs") do
				local button = box:GetAuraGroupFrame("debuffs", i)
				if button then button:SetSize(size, size) end
			end
			Flow(box, max, size)
			box:ClearAllPoints()
			box:SetPoint(v.debuffAt[1], b, "TOPLEFT", v.debuffAt[2], v.debuffAt[3])
			box:SetUnit(unit)
			box:SetShown(on)
			box:UpdateAllAuras()
		end)
	end
	if b.buffBox then
		local box, max = b.buffBox, math.min(6, opt.maxBuffs or 3)
		local on = opt.buffs ~= false and not pv
		pcall(function()
			box:SetAuraGroupEnabled("mine", on)
			box:SetAuraGroupMaxFrameCount("mine", on and max or 0)
			box:SetAuraGroupLayout("mine", GroupLayout(size))
			for i = 1, box:GetAuraGroupFrameCount("mine") do
				local button = box:GetAuraGroupFrame("mine", i)
				if button then button:SetSize(size, size) end
			end
			Flow(box, max, size)
			box:ClearAllPoints()
			box:SetPoint(v.buffAt[1], b, "TOPLEFT", v.buffAt[2], v.buffAt[3])
			box:SetUnit(unit)
			box:SetShown(on)
			box:UpdateAllAuras()
		end)
	end
	if b.dispelBox then
		local types, any = MyDispelTypes()
		local on = opt.dispelGlow ~= false and any and not pv
		pcall(function()
			b.dispelBox:SetAuraSlotCandidateFilters("dispel", { includeDispelTypes = types })
			b.dispelBox:SetAuraSlotEnabled("dispel", on)
			b.dispelBox:ClearAllPoints()
			b.dispelBox:SetAllPoints(v.glowBox)
			if b.dispelSlot then
				b.dispelSlot:ClearAllPoints()
				b.dispelSlot:SetAllPoints(v.glowBox) -- not the container: its size is secret
			end
			b.dispelBox:SetUnit(b.unit)
			b.dispelBox:SetShown(on)
			b.dispelBox:UpdateAllAuras()
		end)
		P.DispelArt(b)
	end
end

-- A roster change in combat: have the client read the (maybe new) units.
local function RefreshAuras(b)
	for _, box in ipairs({ b.debuffBox, b.buffBox, b.dispelBox }) do
		if box and box:IsShown() then pcall(box.UpdateAllAuras, box) end
	end
end

---------------------------------------------------------------------------
-- Buttons and layout

local function ShowTooltip(self)
	if GameTooltip:IsForbidden() then return end
	if GameTooltip_SetDefaultAnchor then
		GameTooltip_SetDefaultAnchor(GameTooltip, self)
	else
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
	end
	GameTooltip:SetUnit(U(self))
	GameTooltip:Show()
end

local function MakeButton(parent, unit, name, index, isPet)
	local b = CreateFrame("Button", name, parent, "SecureUnitButtonTemplate")
	b.unit, b.index, b.isPet = unit, index, isPet
	b.views = {}
	b:SetAttribute("unit", unit)
	b:SetAttribute("*type1", "target")
	b:SetAttribute("*type2", "togglemenu")
	b:RegisterForClicks("AnyUp")
	b:SetScript("OnEnter", ShowTooltip)
	b:SetScript("OnLeave", GameTooltip_Hide)
	b:HookScript("OnShow", function(self) P.UpdateButton(self) end)
	b:SetSize(10, 10)
	b:Hide()
	-- Clique (and other click-casting addons) pick up frames listed here.
	ClickCastFrames = ClickCastFrames or {}
	ClickCastFrames[b] = true
	return b
end

-- Show one style's view on a button, building it the first time.
local function Activate(b, style)
	if not b.views[style] then
		b.views[style] = ns.PartyStyles.Build(style, b, b.isPet)
	end
	for key, view in pairs(b.views) do
		view.root:SetShown(key == style)
	end
	local v = b.views[style]
	b.v = v
	v.SetLevels(b:GetFrameLevel() + 1)
	b:SetSize(v.size[1], v.size[2])
	if v.stone then
		v.stone:SetAlpha(math.max(0.2, math.min(1, Opt().stone or 1)))
	end
end

local function Place()
	local anchor, opt = P.anchor, Opt()
	anchor:ClearAllPoints()
	if opt.moved then
		anchor:SetPoint("CENTER", UIParent, "BOTTOMLEFT", opt.mx, opt.my)
		return
	end
	-- Under your portrait (and its pet's), as D3 stacks its party under you.
	local portraits = ns.Portraits and ns.Portraits.anchor
	if portraits and ns.DB().portraits.enabled and portraits:IsShown() then
		anchor:SetPoint("TOPLEFT", portraits, "BOTTOMLEFT", 0, -10)
	else
		anchor:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -120)
	end
end

function P.Layout()
	local anchor = P.anchor
	if not anchor then return end
	if InCombatLockdown() then
		P.pending = true
		return
	end
	P.pending = nil
	local opt, style = Opt(), P.Style()
	if not style then
		UnregisterStateDriver(anchor, "visibility")
		anchor:Hide()
		for _, b in ipairs(P.all) do
			UnregisterUnitWatch(b)
			b:Hide()
		end
		return
	end

	anchor:SetScale(ns.Art.D3Scale(opt.scale))
	for _, b in ipairs(P.all) do Activate(b, style) end

	local G, L = ns.Art.PARTY.globes, ns.Art.PARTY.slab
	local previewing = P.Previewing()
	local gap = GAP[style] + (tonumber(opt.spacing) or 0)
	local y, width = 0, 0
	for i, b in ipairs(P.members) do
		local v = b.v
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, -y)
		local pet = P.pets[i]
		pet:ClearAllPoints()
		local below = 0 -- how far the pet hangs below its owner
		if style == "globes" then
			pet:SetPoint("CENTER", v.art, "CENTER", G.pet.at[1], -G.pet.at[2])
			local _, padT = 0, v.size[2] - G.bezel.size[2]
			below = math.max(0, padT + G.bezel.size[2] / 2 + G.pet.at[2] + G.pet.size[2] / 2 - v.size[2])
		else
			pet:SetPoint("TOPLEFT", b, "BOTTOMLEFT", L.pet.indent, -L.pet.gap)
			below = L.pet.gap + L.pet.size[2]
		end
		y = y + v.size[2] + (opt.pets and below or 0) + gap
		width = math.max(width, v.size[1] + 120)

		if previewing then
			UnregisterUnitWatch(b)
			b:Show()
		else
			RegisterUnitWatch(b)
		end
		if not opt.pets then
			UnregisterUnitWatch(pet)
			pet:Hide()
		elseif previewing and not UnitExists(pet.unit) then
			UnregisterUnitWatch(pet)
			pet:SetShown(i == 1)
		else
			RegisterUnitWatch(pet)
		end
		ConfigureAuras(b)
	end
	anchor:SetSize(width, math.max(1, y - gap))
	Place()
	if previewing then
		UnregisterStateDriver(anchor, "visibility")
		anchor:Show()
	else
		RegisterStateDriver(anchor, "visibility", DRIVER)
	end
	P.UpdateAll()
end

function P.SetPreview(on)
	if InCombatLockdown() then
		ns.Print("cannot preview in combat")
		return
	end
	P.preview = on and true or nil
	P.Layout()
end

function P.ApplySettings()
	P.Layout()
end

function P.ResetPosition()
	local opt = Opt()
	opt.moved, opt.mx, opt.my = false, 0, 0
	ns.Refresh()
end

---------------------------------------------------------------------------
-- Events

local UNIT_EVENTS = {
	UNIT_HEALTH = "health", UNIT_MAXHEALTH = "health", UNIT_HEAL_PREDICTION = "health",
	UNIT_ABSORB_AMOUNT_CHANGED = "health", UNIT_HEAL_ABSORB_AMOUNT_CHANGED = "health",
	UNIT_CONNECTION = "all", UNIT_FLAGS = "all", UNIT_NAME_UPDATE = "all", UNIT_LEVEL = "all",
	UNIT_PHASE = "all", INCOMING_RESURRECT_CHANGED = "all",
	UNIT_POWER_UPDATE = "power", UNIT_MAXPOWER = "power", UNIT_DISPLAYPOWER = "power",
	UNIT_THREAT_SITUATION_UPDATE = "threat", UNIT_THREAT_LIST_UPDATE = "threat",
	UNIT_PORTRAIT_UPDATE = "portrait", UNIT_MODEL_CHANGED = "portrait",
	UNIT_SPELLCAST_START = "cast", UNIT_SPELLCAST_DELAYED = "cast",
	UNIT_SPELLCAST_CHANNEL_START = "channel", UNIT_SPELLCAST_CHANNEL_UPDATE = "channel",
	UNIT_SPELLCAST_EMPOWER_START = "channel", UNIT_SPELLCAST_EMPOWER_UPDATE = "channel",
	UNIT_SPELLCAST_STOP = "caststop", UNIT_SPELLCAST_CHANNEL_STOP = "caststop",
	UNIT_SPELLCAST_EMPOWER_STOP = "caststop", UNIT_SPELLCAST_INTERRUPTED = "caststop",
	UNIT_SPELLCAST_FAILED = "castcheck", -- a failed attempt can leave another cast running
}

local GROUP_EVENTS = {
	"GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED", "PARTY_LEADER_CHANGED",
	"RAID_TARGET_UPDATE", "READY_CHECK", "READY_CHECK_CONFIRM", "READY_CHECK_FINISHED",
	"PLAYER_ROLES_ASSIGNED", "PLAYER_REGEN_ENABLED", "SPELLS_CHANGED", "UNIT_PET",
}

local function OnUnitEvent(kind, b)
	if not b:IsShown() then return end
	if kind == "health" then
		UpdateHealth(b)
	elseif kind == "power" then
		UpdatePower(b)
	elseif kind == "threat" then
		UpdateThreat(b)
	elseif kind == "portrait" then
		UpdatePortrait(b)
	elseif kind == "cast" then
		StartCast(b, false)
	elseif kind == "channel" then
		StartCast(b, true)
	elseif kind == "castcheck" then
		StartCast(b)
	elseif kind == "caststop" then
		if b.v and b.v.cast then StopCast(b.v.cast) end
	else
		P.UpdateButton(b)
	end
end

local function OnEvent(_, event, unit)
	if not P.Style() then return end
	local kind = UNIT_EVENTS[event]
	if kind then
		local b = P.byUnit[unit]
		if b then OnUnitEvent(kind, b) end
		return
	end
	if event == "PLAYER_TARGET_CHANGED" then
		for _, b in ipairs(P.all) do
			if b:IsShown() then UpdateTarget(b) end
		end
	elseif event == "READY_CHECK" or event == "READY_CHECK_CONFIRM" then
		for _, b in ipairs(P.members) do b.readyHold = nil UpdateReady(b) end
	elseif event == "READY_CHECK_FINISHED" then
		-- Keep the answers up a while; anyone still thinking counts as not ready.
		for _, b in ipairs(P.members) do
			local status = GetReadyCheckStatus and GetReadyCheckStatus(b.unit)
			if Readable(status) then b.readyHold = status == "waiting" and "notready" or status end
			UpdateReady(b)
		end
		C_Timer.After(READY_LINGER, function()
			for _, b in ipairs(P.members) do b.readyHold = nil UpdateReady(b) end
		end)
	elseif event == "UNIT_PET" then
		local owner = P.byUnit[unit]
		if owner and owner.pet and owner.pet:IsShown() then P.UpdateButton(owner.pet) end
		if unit == "player" and not InCombatLockdown() then
			for _, b in ipairs(P.members) do ConfigureAuras(b) end -- a warlock's felhunter dispels
		end
	elseif event == "SPELLS_CHANGED" then
		if not InCombatLockdown() then
			for _, b in ipairs(P.members) do ConfigureAuras(b) end
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		if P.pending then P.Layout() end
	elseif event == "GROUP_ROSTER_UPDATE" then
		for _, b in ipairs(P.members) do RefreshAuras(b) end
		P.UpdateAll()
	else
		P.UpdateAll()
	end
end

-- Range has no event: checked a few times a second. The slab's groove liquid moves here too,
-- on the globes' clock (paused and sped up with them).
local function OnUpdate(_, elapsed)
	if not P.anchor:IsVisible() then return end
	P.rangeClock = (P.rangeClock or 0) + elapsed
	if P.rangeClock >= RANGE_EVERY then
		P.rangeClock = 0
		for _, b in ipairs(P.all) do UpdateRange(b) end
	end
	if P.Style() == "slab" then
		local db = ns.DB()
		if db.liquidAnimate ~= false then
			P.liquidClock = (P.liquidClock or 0) + elapsed * (tonumber(db.liquidSpeed) or 1)
		end
		ns.PartyStyles.AnimateGrooves(P.liquidClock or 0)
	end
	-- The stand-in for the client's pulsing dispel halo, which only a real debuff can show.
	if P.Previewing() then
		local t = (GetTime() / DISPEL_PULSE) % 2
		local k = 1 - (1 - DISPEL_PULSE_LOW) * (t < 1 and t or 2 - t)
		for _, b in ipairs(P.members) do
			local pv = PV(b)
			if pv and pv.dispel and b.v and b.v.glow then b.v.glow:SetAlpha(k) end
		end
	end
end

-- One line for /sanctuary check: what the dispel halo will light for on this character.
function P.DispelStatus()
	local types, any = MyDispelTypes()
	if not any then return "party dispel halo: nothing your class can remove has been learned" end
	local list = {}
	for kind in pairs(types) do list[#list + 1] = kind end
	table.sort(list)
	return "party dispel halo: lights for " .. table.concat(list, ", ")
end

function P.Init()
	local anchor = CreateFrame("Frame", "SanctuaryUIParty", UIParent, "SecureHandlerStateTemplate")
	anchor:SetFrameStrata("LOW")
	anchor:SetSize(200, 300)
	P.anchor = anchor
	P.members, P.pets, P.all, P.byUnit = {}, {}, {}, {}
	for i = 1, MAX do
		local b = MakeButton(anchor, "party" .. i, "SanctuaryUIParty" .. i, i, false)
		local pet = MakeButton(anchor, "partypet" .. i, "SanctuaryUIPartyPet" .. i, i, true)
		b.pet = pet
		P.members[i], P.pets[i] = b, pet
		P.all[#P.all + 1] = b
		P.all[#P.all + 1] = pet
		P.byUnit[b.unit], P.byUnit[pet.unit] = b, pet
		MakeAuras(b)
	end
	P.mover = ns.MakeMover(anchor, "Party", Opt, "Reset its position in /sanctuary > Party.")

	local events = CreateFrame("Frame", nil, UIParent)
	for _, event in ipairs(GROUP_EVENTS) do pcall(events.RegisterEvent, events, event) end
	for event in pairs(UNIT_EVENTS) do pcall(events.RegisterEvent, events, event) end
	events:SetScript("OnEvent", OnEvent)
	events:SetScript("OnUpdate", OnUpdate)
	P.events = events

	P.Layout()
end
