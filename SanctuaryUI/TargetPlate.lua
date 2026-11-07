SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.TargetPlate = ns.TargetPlate or {}

-- The target plate, D3's monster health bar at the top of the screen: the name inside the bar, the frame
-- by rank (silver for ordinary monsters, gold for elites and rares, the gold banner for bosses),
-- name colours by rank as D3 does (champion blue, rare yellow, boss orange), a cast bar in a
-- small silver frame and every debuff on the target underneath, yours bright and the rest dim.
--
-- Drawn at D3's own size (ns.Art.D3Scale) so the art is never blown up; the scale and width
-- options go from there. Width stretches the frame between its ornaments. Health drains
-- smoothly with a pale trail behind it, as D3's bars do. An optional portrait of the target
-- sits left of the bar in one of D3's hero portrait frames, chosen by the target's rank.
--
-- The plate is a secure unit button: left-click targets, right-click opens the unit menu.
-- RegisterUnitWatch shows and hides it, also in combat; its size and place change only out of
-- combat (Layout runs from Refresh). Everything drawn on it is plain and updates freely.

local MAX_AURAS = 24 -- of each kind
-- Every rank's bar is centred on the same line (the boss banner's), and the lines under it sit
-- at fixed places, so nothing secure (the target-of-target button) hangs off a frame that
-- changes size in combat, and the plate doesn't jump between ranks.
local BAR_Y = 34.5 -- bar centre, below the plate's top
local SUB_Y = BAR_Y + 22 -- level / rank line (just under the normal and elite frames)
local PLATE_H = 88
local RING_OVERLAP = 6 -- how far the portrait's frame tucks under the bar frame's left end
-- Target of target: a small copy of the ordinary monster bar with its portrait ring, right of
-- the target's frame.
local TOT_K = 0.6 -- its size against the target bar's
local TOT_GAP = 6 -- between the target's frame and the ToT's portrait ring
-- Friendly fill tint: a deep forest green (the old 0.25, 0.7, 0.3 read lime on the bar's art).
local FRIEND_GREEN = { 0.13, 0.45, 0.16 }
local SMOOTH = 10 -- health catch-up rate (per second, exponential)
local TRAIL_HOLD, TRAIL_RATE = 0.45, 3 -- the pale damage trail: pause, then drain

local NAME_COLORS = {
	normal = { 0.95, 0.9, 0.8 },
	elite = { 0.45, 0.6, 1.0 }, -- champion blue
	rare = { 1.0, 0.86, 0.25 }, -- rare yellow
	boss = { 1.0, 0.55, 0.15 }, -- unique / boss orange
	-- The name sits in the bar, so on the green (friendly), amber (neutral) and grey (tapped)
	-- fills it stays a pale cream: the bar colour already says which it is.
	friend = { 0.98, 0.95, 0.88 },
	neutral = { 0.98, 0.95, 0.88 },
	tapped = { 0.88, 0.88, 0.88 },
}

local RANK_LABEL = {
	elite = ELITE or "Elite",
	rare = "Rare",
	rareelite = "Rare Elite",
	worldboss = BOSS or "Boss",
}

local function Opt()
	return ns.DB().target
end

-- Test mode (Options > Target > Preview): with no target, the plate shows a stand-in monster
-- drawn from your own unit, cycling normal, elite and boss frames with its health dropping, so
-- the look can be judged in game.
local PREVIEW_RANKS = { "normal", "elite", "boss" }
local PREVIEW_NAMES = { normal = "Risen Ghoul", elite = "Bonecrusher the Vile", boss = "The Butcher" }
local PREVIEW_CLASS = { normal = "normal", elite = "rareelite", boss = "worldboss" }
local preview = { rank = 1, clock = 0, health = 1 }

local function Previewing()
	return ns.TargetPlate.preview and not UnitExists("target")
end

-- The unit the plate reads: the target, or you while previewing.
local function U()
	return Previewing() and "player" or "target"
end

local function Secret(value)
	return issecretvalue and issecretvalue(value)
end

---------------------------------------------------------------------------
-- Cast bar

local function StopCast(cast)
	cast:Hide()
	cast.startMS, cast.endMS, cast.timer = nil, nil, nil
end

-- Modern returns: UnitCastingInfo name, text, texture, start, end, tradeskill, castID,
-- notInterruptible, spellID; UnitChannelInfo name, text, texture, start, end, tradeskill,
-- notInterruptible, spellID, isEmpowered. Times (and the interrupt flag) can be secret for
-- other units.
local function ReadCast(unit, channel)
	local name, _, texture, startMS, endMS, _, notInterruptible, spellID, empowered
	if channel then
		name, _, texture, startMS, endMS, _, notInterruptible, spellID, empowered = UnitChannelInfo(unit)
	else
		name, _, texture, startMS, endMS, _, _, notInterruptible, spellID = UnitCastingInfo(unit)
	end
	return name, texture, startMS, endMS, notInterruptible, empowered
end

-- The lock and grey wash over a cast that can't be interrupted. The flag may be secret, so it
-- goes straight to SetAlphaFromBoolean where the client has it (as oUF does here).
local function SetShield(cast, notInterruptible)
	for _, region in ipairs({ cast.shield, cast.lock }) do
		if region.SetAlphaFromBoolean then
			if Secret(notInterruptible) then
				region:SetAlphaFromBoolean(notInterruptible, 1, 0)
			else
				region:SetAlphaFromBoolean(notInterruptible or false, 1, 0)
			end
		else
			region:SetShown(not Secret(notInterruptible) and notInterruptible and true or false)
		end
	end
end

local function StartCast(cast, channel)
	if not Opt().cast then
		StopCast(cast)
		return
	end
	local unit = U()
	local name, texture, startMS, endMS, notInterruptible, empowered = ReadCast(unit, channel)
	-- A secret name is still a cast (secrets are never nil).
	if not Secret(name) and not name then
		if not channel then
			name, texture, startMS, endMS, notInterruptible, empowered = ReadCast(unit, true)
			channel = true
		end
		if not Secret(name) and not name then
			StopCast(cast)
			return
		end
	end
	cast.channel = channel
	cast.spellName:SetText(name)
	cast.icon:SetTexture(ns.Or(texture, 136243)) -- a cog when the spell has no icon
	SetShield(cast, notInterruptible)

	-- The client runs the bar from a duration object (works with secret times): filling as a
	-- cast goes, draining as a channel goes. Clients without one get times and an OnUpdate.
	local bar = cast.bar
	local duration
	if channel then
		if empowered and not Secret(empowered) and UnitEmpoweredChannelDuration then
			duration = UnitEmpoweredChannelDuration(unit)
		else
			duration = UnitChannelDuration and UnitChannelDuration(unit)
		end
	else
		duration = UnitCastingDuration and UnitCastingDuration(unit)
	end
	if type(duration) ~= "nil" and bar.SetTimerDuration then
		local directions = Enum and Enum.StatusBarTimerDirection
		local direction = directions and (channel and directions.RemainingTime or directions.ElapsedTime)
		local smoothing = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate
		bar:SetTimerDuration(duration, smoothing, direction)
		cast.timer = true
		cast.startMS, cast.endMS = nil, nil
	elseif not Secret(startMS) and not Secret(endMS) and startMS and endMS then
		cast.timer = nil
		cast.startMS, cast.endMS = startMS, endMS
		bar:SetMinMaxValues(startMS, endMS)
		bar:SetValue(channel and (endMS - (GetTime() * 1000 - startMS)) or GetTime() * 1000)
	else
		-- Nothing to time it by: show it full until the stop event.
		cast.timer, cast.startMS, cast.endMS = nil, nil, nil
		bar:SetMinMaxValues(0, 1)
		bar:SetValue(1)
	end
	cast:Show()
end

---------------------------------------------------------------------------
-- Rank, frame and colours

local function Rank()
	if Previewing() then
		local rank = PREVIEW_RANKS[preview.rank]
		return rank, rank == "elite" and "rare" or rank, PREVIEW_CLASS[rank]
	end
	local c = UnitClassification(U())
	if Secret(c) then c = "normal" end
	local level = UnitLevel(U())
	local bossMob = UnitIsBossMob and UnitIsBossMob(U())
	if Secret(bossMob) then bossMob = false end
	local isPlayer = UnitIsPlayer(U())
	if Secret(isPlayer) then isPlayer = true end
	local boss = c == "worldboss" or bossMob == true
		or (not Secret(level) and level and level == -1 and not isPlayer)
	if boss then return "boss", "boss", c end
	if c == "rare" or c == "rareelite" then return "elite", "rare", c end
	if c == "elite" then return "elite", "elite", c end
	return "normal", "normal", c
end

local LayoutTexts -- the bar's texts follow the frame (below)

-- Draw the rank's frame at the chosen width and fit the health bar (and its trail) to the slot.
local function SetPiece(plate, rank)
	if plate.rank == rank then return end
	plate.rank = rank
	local piece = ns.Art.UNIT[rank]
	local width = piece[3] * (Opt().width or 1)
	local extra = ns.Art.DrawSliced(plate.FrameBox, rank, width, 1)
	local bar = piece.bar
	plate.FrameBox:ClearAllPoints()
	plate.FrameBox:SetPoint("TOP", plate, "TOP", 0, -(BAR_Y - (bar[2] + bar[4] / 2)))
	for _, b in ipairs({ plate.Health, plate.Trail }) do
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", plate.FrameBox, "TOPLEFT", bar[1], -bar[2])
		b:SetSize(bar[3] + extra, bar[4])
	end
	plate.barW, plate.barH = bar[3] + extra, bar[4]
	-- Clicks only on the frame drawn for this rank (and its rank line), not the room the boss
	-- banner needs: the plate sits above the console, and its empty margins would block the
	-- console's buttons. A secure button: out of combat only; in combat it keeps the last size.
	if not InCombatLockdown() then
		local side = (ns.Art.UNIT.boss[3] - piece[3]) * (Opt().width or 1) / 2
		local bottom = math.max(0, PLATE_H - math.max(piece[4], SUB_Y + 8))
		plate:SetHitRectInsets(side, side, 0, bottom)
		plate.hitStale = nil
	else
		plate.hitStale = true
	end
	if plate.HealBand then
		plate.HealBand:SetWidth(plate.barW)
		plate.AbsorbBand:SetWidth(plate.barW)
	end
	if plate.edgeGlow then
		plate.edgeGlow.bloom:SetHeight(bar[4])
		plate.edgeGlow.core:SetHeight(bar[4])
	end
	LayoutTexts(plate)
	-- The target of target follows this frame's right end, on the bar's line.
	plate.ToTArt:ClearAllPoints()
	plate.ToTArt:SetPoint("LEFT", plate.Health, "RIGHT", (piece[3] - bar[1] - bar[3]) + TOT_GAP, 0)
	if plate.liquid then
		for _, layer in ipairs(plate.liquid.layers) do
			layer:SetSize(plate.barW, plate.barH)
		end
		plate.spark:SetHeight(plate.barH * 1.8)
	end
	-- The portrait's D3 frame follows the rank too; its hole sits on the bar's line.
	local ring = ns.Art.TARGET_RING[rank] or ns.Art.TARGET_RING.normal
	plate.Portrait:ClearAllPoints()
	plate.Portrait:SetPoint("CENTER", plate.FrameBox, "TOPLEFT", -(ring.reach - RING_OVERLAP), -(bar[2] + bar[4] / 2))
	if plate.Portrait.ringArt then
		plate.Portrait.ring:SetTexCoord(ns.Art.TargetRingTexCoord(rank))
	end
	local badge = plate.Portrait.badge
	badge:ClearAllPoints()
	badge:SetPoint("CENTER", plate.Portrait, "CENTER", 0, -(ring.badge or 50))
	badge:SetKind(ring.plate or "silver")
end

-- A StatusBar owns its fill's texcoords, so each fill is a whole file: red, or white to tint.
local function SetFillColor(plate, red, r, g, b)
	local path = ns.Art.Path(red and "unitFill" or "unitFillWhite")
	if path and plate.fillPath ~= path then
		plate.fillPath = path
		plate.Health:SetStatusBarTexture(path)
	elseif not path then
		plate.Health:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
		if red then r, g, b, red = 0.72, 0.1, 0.08, false end
	end
	if red then
		plate.Health:SetStatusBarColor(1, 1, 1, 1)
		r, g, b = 1, 0.32, 0.22
	else
		plate.Health:SetStatusBarColor(r, g, b, 1)
	end
	plate.liquidColor = { r, g, b }
	if plate.edgeGlow then
		-- Red bars burn orange-red; tinted ones glow in their own colour.
		if red then
			plate.edgeGlow.bloom:SetVertexColor(1, 0.26, 0.06)
		else
			plate.edgeGlow.bloom:SetVertexColor(math.min(1, r * 1.3), math.min(1, g * 1.3), math.min(1, b * 1.3))
		end
	end
end

---------------------------------------------------------------------------
-- Text on the bar (Options > Target > Text): the name, the level and the health text, each
-- placed, sized and set in its own font. Enemy health is usually secret in combat, so the
-- numbers go through the client's secret-aware helpers (AbbreviateNumbers, BreakUpLargeNumbers,
-- UnitHealthPercent with a curve) and straight into the font string; we never read them.

local TEXT_FONTS = {
	d3 = ns.FONT,
	wow = STANDARD_TEXT_FONT,
	narrow = "Fonts\\ARIALN.TTF",
}

-- A number in the chosen style: short (2.48 M), full (2,480,000) or raw (2480000).
local function Num(value)
	local style = Opt().healthNumbers or "short"
	local f
	if style == "short" then
		f = AbbreviateNumbers or AbbreviateLargeNumbers
	elseif style == "full" then
		f = BreakUpLargeNumbers
	end
	if f then
		-- Never tests the result: a secret value can't be compared or used as a condition.
		local ok, text = pcall(f, value)
		if ok and type(text) ~= "nil" then return text end
	end
	return value
end

-- Curves the client evaluates on the (maybe secret) health fraction, for alphas we can't
-- compute ourselves: the edge glow (off when empty or full) and the health text's "hide at
-- full health" (off only when full).
local curves = {}
local function Curve(key, points)
	if curves[key] == nil then
		curves[key] = false
		if C_CurveUtil and C_CurveUtil.CreateCurve then
			local ok, curve = pcall(C_CurveUtil.CreateCurve)
			if ok and curve then
				for _, p in ipairs(points) do
					pcall(curve.AddPoint, curve, p[1], p[2])
				end
				curves[key] = curve
			end
		end
	end
	return curves[key] or nil
end
local GLOW_POINTS = { { 0, 0 }, { 0.004, 1 }, { 0.996, 1 }, { 1, 0 } }
local FULL_POINTS = { { 0, 1 }, { 0.9995, 1 }, { 1, 0 } }

-- Alpha for a region from the target's health through a curve; falls back to `default`.
local function CurveAlpha(region, key, points, default)
	local curve = UnitHealthPercent and Curve(key, points)
	if curve then
		local ok, alpha = pcall(UnitHealthPercent, U(), true, curve)
		if ok and type(alpha) ~= "nil" and pcall(region.SetAlpha, region, alpha) then return end
	end
	region:SetAlpha(default)
end

-- Returns true and the percent (0-100, maybe secret), or false.
local function HealthPercent(unit, health, maxHealth)
	if Previewing() then
		return true, preview.health * 100
	end
	if UnitHealthPercent then
		local curve = CurveConstants and CurveConstants.ScaleTo100
		local ok, pct = pcall(UnitHealthPercent, unit, true, curve)
		if ok and type(pct) ~= "nil" then
			-- Without the curve the client hands back 0-1.
			if curve then return true, pct end
			local ok2, scaled = pcall(function() return pct * 100 end)
			if ok2 then return true, scaled end
		end
	end
	if not Secret(health) and not Secret(maxHealth) and maxHealth and maxHealth > 0 then
		return true, (health or 0) / maxHealth * 100
	end
	return false
end

-- Missing health (maybe secret), or nil.
local function HealthMissing(health, maxHealth)
	if not Secret(health) and not Secret(maxHealth) and health and maxHealth then
		return math.max(0, maxHealth - health)
	end
	if UnitHealthMissing then
		local ok, missing = pcall(UnitHealthMissing, U(), true)
		if ok and type(missing) ~= "nil" then return missing end
	end
end

local function SetHealthText(plate, health, maxHealth)
	local opt = Opt()
	local fs, mode = plate.Percent, opt.healthText or "percent"
	if mode == "none" then
		fs:SetText("")
		return
	end
	if Previewing() then
		-- The stand-in monster: a made-up pool so the number formats can be judged.
		health, maxHealth = math.floor(preview.health * 2480000 + 0.5), 2480000
	end
	local cur, top = Num(ns.Or(health, 0)), Num(ns.Or(maxHealth, 0))
	local hasPct, pct = false, nil
	if mode == "percent" or mode == "both" or mode == "pctcur" or mode == "maxpct" then
		hasPct, pct = HealthPercent(U(), health, maxHealth)
	end
	local ok = false
	if mode == "percent" then
		ok = hasPct and pcall(fs.SetFormattedText, fs, "%.0f%%", pct)
	elseif mode == "current" then
		ok = pcall(fs.SetFormattedText, fs, "%s", cur)
	elseif mode == "both" then
		ok = hasPct and pcall(fs.SetFormattedText, fs, "%s  |  %.0f%%", cur, pct)
		ok = ok or pcall(fs.SetFormattedText, fs, "%s", cur)
	elseif mode == "pctcur" then
		ok = hasPct and pcall(fs.SetFormattedText, fs, "%.0f%%  |  %s", pct, cur)
		ok = ok or pcall(fs.SetFormattedText, fs, "%s", cur)
	elseif mode == "max" then
		ok = pcall(fs.SetFormattedText, fs, "%s / %s", cur, top)
	elseif mode == "maxpct" then
		ok = hasPct and pcall(fs.SetFormattedText, fs, "%s / %s  |  %.0f%%", cur, top, pct)
		ok = ok or pcall(fs.SetFormattedText, fs, "%s / %s", cur, top)
	elseif mode == "missing" then
		local missing = HealthMissing(health, maxHealth)
		ok = type(missing) ~= "nil" and pcall(fs.SetFormattedText, fs, "-%s", Num(missing))
	end
	if not ok then fs:SetText("") end
	-- Missing health always hides at full ("-0"); the rest when asked.
	if mode == "missing" or opt.healthHideFull then
		if not Secret(health) and not Secret(maxHealth) and health and maxHealth then
			fs:SetAlpha(health >= maxHealth and 0 or 1)
		else
			CurveAlpha(fs, "full", FULL_POINTS, 1)
		end
	else
		fs:SetAlpha(1)
	end
end

-- Place one text: inside the bar (left, centre, right) or over / under the frame, nudged.
-- The name, the one long text, gets a width so it trims instead of running over the ends.
local function PlaceText(plate, fs, prefix, isName, pos)
	local opt = Opt()
	pos = pos or opt[prefix .. "Pos"] or "center"
	local x, y = opt[prefix .. "X"] or 0, opt[prefix .. "Y"] or 0
	local size = opt[prefix .. "Size"] or 10
	local font = TEXT_FONTS[opt[prefix .. "Font"]] or STANDARD_TEXT_FONT
	fs:SetFont(font, size, "OUTLINE")
	if not fs:GetFont() then
		fs:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
	end
	local bar, w = plate.Health, plate.barW or 250
	if isName then y = y + 1 end -- Exocet sits a hair low
	fs:ClearAllPoints()
	if pos == "left" then
		fs:SetPoint("LEFT", bar, "LEFT", 5 + x, y)
		fs:SetJustifyH("LEFT")
	elseif pos == "right" then
		fs:SetPoint("RIGHT", bar, "RIGHT", -5 + x, y)
		fs:SetJustifyH("RIGHT")
	elseif pos == "above" then
		fs:SetPoint("BOTTOM", plate.FrameBox, "TOP", x, 2 + y)
		fs:SetJustifyH("CENTER")
	elseif pos == "below" then
		fs:SetPoint("TOP", plate.FrameBox, "BOTTOM", x, -2 + y)
		fs:SetJustifyH("CENTER")
	else
		fs:SetPoint("CENTER", bar, "CENTER", x, y)
		fs:SetJustifyH("CENTER")
	end
	if isName then
		local inside = pos ~= "above" and pos ~= "below"
		fs:SetWidth(inside and math.max(40, w - (pos == "center" and 68 or 40)) or w + 60)
	end
end

function LayoutTexts(plate)
	local opt = Opt()
	PlaceText(plate, plate.Name, "name", true)
	PlaceText(plate, plate.Percent, "health")
	plate.Name:SetShown(opt.nameShow ~= false)
	-- The level: on the portrait's plaque, or (no portrait, or asked) as text on the bar.
	local badge = plate.Portrait.badge
	local onBadge = (opt.levelPos or "badge") == "badge" and opt.portrait and plate.Portrait.ringArt
	plate.levelOnBadge = onBadge and true or nil
	if onBadge then
		local font = TEXT_FONTS[opt.levelFont] or STANDARD_TEXT_FONT
		badge.text:SetFont(font, opt.levelSize or 10, "OUTLINE")
		if not badge.text:GetFont() then badge.text:SetFont(STANDARD_TEXT_FONT, opt.levelSize or 10, "OUTLINE") end
		badge.text:ClearAllPoints()
		badge.text:SetPoint("CENTER", badge, "CENTER", opt.levelX or 0, 1 + (opt.levelY or 0))
		plate.Level:Hide()
	else
		PlaceText(plate, plate.Level, "level", false, opt.levelPos == "badge" and "left" or nil)
		plate.Level:SetShown(opt.levelShow ~= false)
	end
	badge:SetShown(onBadge and opt.levelShow ~= false or false)
end

-- The ember at the fill's leading edge (Options > Target > Edge glow), dark when the bar is
-- empty or full. frac: the shown fraction, or nil when health is secret.
local function UpdateGlow(plate, frac)
	local glow = plate.edgeGlow
	if not glow then return end
	if Opt().edgeGlow == false then
		glow.frame:Hide()
		return
	end
	glow.frame:Show()
	if frac then
		glow.frame:SetAlpha((frac > 0.004 and frac < 0.996) and 1 or 0)
	else
		CurveAlpha(glow.frame, "glow", GLOW_POINTS, 1)
	end
end

-- Health: the bar eases toward the real value; a pale trail holds where health was and then
-- drains after it. Both run on fractions. With secret health (enemies in combat) the client
-- eases the bar itself, and the trail is the same secret value replayed TRAIL_HOLD later: we
-- can hold a secret and hand it on, we just can't read it.

local function Ease()
	return Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
end

local function SecretValue(bar, value, ease)
	if not (ease and pcall(bar.SetValue, bar, value, ease)) then
		pcall(bar.SetValue, bar, value)
	end
end

-- One pending replay at a time: it sends the latest health, so steady damage drains the trail
-- in steps every TRAIL_HOLD instead of never.
local function QueueSecretTrail(plate)
	if plate.trailQueued then return end
	plate.trailQueued = true
	C_Timer.After(TRAIL_HOLD, function()
		plate.trailQueued = nil
		if plate.secret then
			SecretValue(plate.Trail, plate.trailPending, Ease())
		end
	end)
end

-- Heal prediction on the target, for healers: incoming heals in green, then damage shields in
-- silver, running on from the fill's end, and a silver glow at the bar's end when the shield is
-- bigger than the missing health. The bands are their own StatusBars, a bar wide, in raw health
-- (secret or not), so the client sizes them either way; it also eases them.
local PREVIEW_HEAL, PREVIEW_ABSORB = 0.12, 0.08

local function SetPrediction(plate, health, maxHealth)
	local heal, absorb = plate.HealBand, plate.AbsorbBand
	if not heal then return end
	local amount, shield, clamped = 0, 0, false
	if Opt().healPrediction ~= false then
		if Previewing() then
			-- The stand-in's falling health, with a heal on the way and a shield on top.
			local missing = 1 - preview.health
			amount = math.min(PREVIEW_HEAL, missing)
			shield = math.min(PREVIEW_ABSORB, missing - amount)
			clamped = PREVIEW_ABSORB > missing - amount
			maxHealth = 1
		else
			amount, shield, clamped = ns.IncomingHeals(U(), health, maxHealth)
		end
	end
	local top = ns.Or(maxHealth, 1)
	pcall(heal.SetMinMaxValues, heal, 0, top)
	pcall(absorb.SetMinMaxValues, absorb, 0, top)
	SecretValue(heal, ns.Or(amount, 0), Ease())
	SecretValue(absorb, ns.Or(shield, 0), Ease())
	local glow = plate.OverShield
	if Secret(clamped) then
		if not (glow.SetAlphaFromBoolean and pcall(glow.SetAlphaFromBoolean, glow, clamped, 1, 0)) then
			glow:SetAlpha(0)
		end
	else
		glow:SetAlpha(clamped and 1 or 0)
	end
end

local function SetHealth(plate, snap)
	local health, maxHealth = UnitHealth(U()), UnitHealthMax(U())
	if Previewing() then
		health, maxHealth = preview.health, 1
	end
	if Secret(health) or Secret(maxHealth) then
		local entering = not plate.secret
		plate.secret = true
		local value, top = ns.Or(health, 0), ns.Or(maxHealth, 1)
		pcall(plate.Health.SetMinMaxValues, plate.Health, 0, top)
		pcall(plate.Trail.SetMinMaxValues, plate.Trail, 0, top)
		-- The client can ease a bar to a value it won't show us.
		SecretValue(plate.Health, value, not snap and Ease())
		plate.trailPending = value
		if snap or entering then
			SecretValue(plate.Trail, value)
		else
			QueueSecretTrail(plate)
		end
		plate.Trail:Show()
		SetHealthText(plate, health, maxHealth)
		UpdateGlow(plate, nil)
		SetPrediction(plate, health, maxHealth)
		return
	end
	if plate.secret then
		plate.secret = nil
		plate.trailPending = nil
		plate.Health:SetMinMaxValues(0, 1)
		plate.Trail:SetMinMaxValues(0, 1)
		snap = true
	end
	local frac = (maxHealth and maxHealth > 0) and math.max(0, math.min(1, (health or 0) / maxHealth)) or 0
	plate.goal = frac
	if snap or not plate.shown then
		plate.shown = frac
		plate.trail = frac
		plate.Health:SetValue(frac)
		plate.Trail:SetValue(frac)
	elseif frac < (plate.trail or frac) then
		plate.trailHold = TRAIL_HOLD
	end
	if frac > (plate.trail or 0) then
		plate.trail = frac
		plate.Trail:SetValue(frac)
	end
	plate.Trail:Show()
	SetHealthText(plate, health, maxHealth)
	SetPrediction(plate, health, maxHealth)
end

-- Previewing: a hit every 1.2 s, back to full when empty, the next rank every full cycle.
local function PreviewTick(plate, elapsed)
	if not Previewing() then return end
	preview.clock = preview.clock + elapsed
	if preview.clock < 1.2 then return end
	preview.clock = 0
	preview.health = preview.health - 0.17
	if preview.health <= 0 then
		preview.health = 1
		preview.rank = preview.rank % #PREVIEW_RANKS + 1
		ns.TargetPlate.Update(true)
	else
		SetHealth(plate)
	end
end

-- The liquid in the bar, like the globes': a slow drifting layer and faster streaks (both
-- additive, tinted with the fill), clipped to the filled part, and a spark at the edge.
-- speed: texture widths per second, the globes' own drift rates (Liquid.lua LAYERS du).
-- scale: screen pixels per texture pixel; large, so the pattern reads as soft liquid.
local LIQUID = {
	{ slot = "liquidTile", speed = 0.018, alpha = 0.22, scale = 2.2, sway = 0.006 },
	{ slot = "liquidTile", speed = -0.012, alpha = 0.12, scale = 1.5, sway = 0.008 },
	{ slot = "liquidStreaks", speed = 0.034, alpha = 0.16, scale = 1.6, sway = 0 },
}

local function AnimateLiquid(plate, elapsed, fraction)
	local liquid = plate.liquid
	if not liquid then return end
	local on = Opt().liquid ~= false
	liquid.clip:SetShown(on)
	if not on then
		plate.spark:Hide()
		return
	end
	local w, h = plate.barW or 1, plate.barH or 1
	-- Follows the globes' liquid settings: paused with them, and at their speed.
	local db = ns.DB()
	if db.liquidAnimate ~= false then
		liquid.t = liquid.t + elapsed * (tonumber(db.liquidSpeed) or 1)
	end
	local t = liquid.t
	local c = plate.liquidColor or { 1, 0.32, 0.22 }
	for i, layer in ipairs(liquid.layers) do
		local spec = LIQUID[i]
		local su, sv = w / (256 * spec.scale), h / (256 * spec.scale)
		-- REPEAT wraps; keeping the coordinates positive (as the globes do) avoids clamping.
		local u = (t * spec.speed) % 1 + 1.5
		local v = (0.3 * i + spec.sway * math.sin(t * 0.25 + i)) % 1 + 1.5
		layer:SetTexCoord(u, u + su, v, v + sv)
		layer:SetVertexColor(c[1], c[2], c[3], spec.alpha)
	end
	-- Secret health: no fraction to test, so the spark stays lit at the edge. The edge glow,
	-- when on, takes its place.
	if plate.edgeGlow and Opt().edgeGlow ~= false then
		plate.spark:Hide()
	elseif not fraction or (fraction > 0.003 and fraction < 0.997) then
		plate.spark:Show()
		plate.spark:SetVertexColor(math.min(1, c[1] + 0.4), math.min(1, c[2] + 0.4), math.min(1, c[3] + 0.4), 0.9)
	else
		plate.spark:Hide()
	end
end

local function Animate(plate, elapsed)
	if plate.secret or not plate.goal then
		AnimateLiquid(plate, elapsed, nil)
		return
	end
	local shown, goal = plate.shown or plate.goal, plate.goal
	if math.abs(goal - shown) > 0.0005 then
		shown = shown + (goal - shown) * math.min(1, elapsed * SMOOTH)
	else
		shown = goal
	end
	plate.shown = shown
	plate.Health:SetValue(shown)
	AnimateLiquid(plate, elapsed, shown)
	UpdateGlow(plate, shown)
	local trail = plate.trail or shown
	if trail > shown then
		if (plate.trailHold or 0) > 0 then
			plate.trailHold = plate.trailHold - elapsed
		else
			trail = math.max(shown, trail - math.max(0.002, (trail - shown) * elapsed * TRAIL_RATE))
			plate.trail = trail
			plate.Trail:SetValue(trail)
		end
	end
end

---------------------------------------------------------------------------
-- Auras: every debuff on the target (yours first and bright, the rest dimmed), and its buffs
-- if wanted, on a line of their own. Above or below the bar, aligned left, centre or right,
-- growing either way, each set on its own; options in Settings (target.aura*, target.buff*). The icons are plain frames, so they
-- can move in combat.

local function ShowAuraTooltip(self)
	if (type(self.auraID) == "nil" and not self.index) or GameTooltip:IsForbidden() then return end
	GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
	local helpful = self.filter == "HELPFUL"
	local byID = helpful and GameTooltip.SetUnitBuffByAuraInstanceID or GameTooltip.SetUnitDebuffByAuraInstanceID
	if type(self.auraID) ~= "nil" and byID then
		pcall(byID, GameTooltip, U(), self.auraID, self.filter)
	elseif self.index then
		pcall(GameTooltip.SetUnitAura, GameTooltip, U(), self.index, self.filter or "HARMFUL")
	end
	GameTooltip:Show()
end

local function MakeAura(parent, name)
	local button = CreateFrame("Frame", name, parent)
	button:EnableMouse(true)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetAllPoints()
	button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	button.cooldown:SetAllPoints()
	button.cooldown:SetReverse(true)
	if button.cooldown.SetDrawEdge then button.cooldown:SetDrawEdge(false) end
	if button.cooldown.SetHideCountdownNumbers then button.cooldown:SetHideCountdownNumbers(true) end
	button.count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	button.count:SetPoint("BOTTOMRIGHT", 1, 1)
	button.sanctuarySocket = true
	ns.Art.AttachRing(button)
	button:SetScript("OnEnter", ShowAuraTooltip)
	button:SetScript("OnLeave", GameTooltip_Hide)
	button:Hide()
	return button
end

-- On Midnight-era clients a target's auras can be secret in combat: an addon may not read them
-- by index (GetAuraDataByIndex throws), and their fields can't be compared. So the list comes
-- from GetUnitAuras, and "is it mine", the timer and the stack count are asked of the client by
-- aura instance ID, the way oUF and Plater do it; their answers go straight to the widgets.
local UA = C_UnitAuras or {}

local function Readable(value)
	return not Secret(value) and value ~= nil
end

local function Mine(aura, unit)
	local source = aura.sourceUnit
	if Readable(source) then
		return source == "player" or source == "pet" or source == "vehicle"
	end
	local id = aura.auraInstanceID
	if type(id) ~= "nil" and UA.IsAuraFilteredOutByInstanceID then
		local ok, out = pcall(UA.IsAuraFilteredOutByInstanceID, unit, id, "HARMFUL|PLAYER")
		if ok and Readable(out) then return not out end
	end
	local fromPlayer = aura.isFromPlayerOrPlayerPet
	return Readable(fromPlayer) and fromPlayer or false
end

-- bright: drawn at full colour (buffs, and your own debuffs); the rest are greyed.
local function PaintAura(button, aura, filter, bright)
	if not aura then
		button.index, button.auraID = nil, nil
		button:Hide()
		return
	end
	local unit = U()
	button.index, button.filter = aura.index, filter
	button.auraID = aura.auraInstanceID
	pcall(button.icon.SetTexture, button.icon, aura.icon)
	button.icon:SetDesaturated(not bright)
	button:SetAlpha(bright and 1 or 0.6)
	if button.sanctuarySocketTex then
		if filter == "HELPFUL" then
			button.sanctuarySocketTex:SetVertexColor(1, 1, 1)
		elseif bright then
			button.sanctuarySocketTex:SetVertexColor(1, 0.85, 0.5)
		else
			button.sanctuarySocketTex:SetVertexColor(0.55, 0.5, 0.45)
		end
	end
	-- Stacks: read them when we may, else the client writes the count (blank under 2).
	local stacks = aura.applications
	if Readable(stacks) then
		button.count:SetText(stacks > 1 and stacks or "")
	elseif type(button.auraID) ~= "nil" and UA.GetAuraApplicationDisplayCount then
		if not pcall(function() button.count:SetText(UA.GetAuraApplicationDisplayCount(unit, button.auraID, 2, 999)) end) then
			button.count:SetText("")
		end
	else
		button.count:SetText("")
	end
	-- The timer sweep: from the plain numbers when readable, else the client's duration object.
	local duration, expiration = aura.duration, aura.expirationTime
	local swept = false
	if Readable(duration) and Readable(expiration) then
		if duration > 0 then
			button.cooldown:SetCooldown(expiration - duration, duration)
			swept = true
		end
	elseif type(button.auraID) ~= "nil" and UA.GetAuraDuration and button.cooldown.SetCooldownFromDurationObject then
		local ok, object = pcall(UA.GetAuraDuration, unit, button.auraID)
		swept = ok and type(object) ~= "nil" and pcall(button.cooldown.SetCooldownFromDurationObject, button.cooldown, object)
	end
	if not swept then button.cooldown:Clear() end
	button:Show()
end

-- Every aura of one kind on the unit, in the client's order.
local function ReadAuras(unit, filter)
	if UA.GetUnitAuras then
		local ok, list = pcall(UA.GetUnitAuras, unit, filter)
		if ok and type(list) == "table" then return list end
	end
	-- Older clients: by index, stopping quietly if the client refuses.
	local list = {}
	if not UA.GetAuraDataByIndex then return list end
	for index = 1, 40 do
		local ok, aura = pcall(UA.GetAuraDataByIndex, unit, index, filter)
		if not ok or not aura then break end
		aura.index = index
		list[#list + 1] = aura
	end
	return list
end

local function Collect(filter, max)
	local list = {}
	if max <= 0 then return list end
	-- Previewing, your buffs stand in for the monster's debuffs (and buffs).
	local unit = U()
	local real = Previewing() and "HELPFUL" or filter
	local mine, others = {}, {}
	for _, aura in ipairs(ReadAuras(unit, real)) do
		if filter == "HARMFUL" and Mine(aura, unit) then mine[#mine + 1] = aura else others[#others + 1] = aura end
	end
	-- Your debuffs first, so they never drop off the end.
	for _, aura in ipairs(mine) do list[#list + 1] = aura end
	for _, aura in ipairs(others) do list[#list + 1] = aura end
	for i = max + 1, #list do list[i] = nil end
	return list
end

-- Debuffs and buffs each have their own layout: side, alignment, growth, icon size, icons per
-- line, spacing and nudge (target.aura* / debuffSize for debuffs, target.buff* for buffs).
local function AuraSpec(opt, kind)
	if kind == "debuff" then
		return {
			pos = opt.auraPos or "below", align = opt.auraAlign or "center", grow = opt.auraGrow or "right",
			size = opt.debuffSize or 26, cols = math.max(1, opt.auraPerLine or 12),
			gap = opt.auraSpacing or 4, x = opt.auraX or 0, y = opt.auraY or 0,
		}
	end
	return {
		pos = opt.buffPos or "below", align = opt.buffAlign or "center", grow = opt.buffGrow or "right",
		size = opt.buffSize or 26, cols = math.max(1, opt.buffPerLine or 12),
		gap = opt.buffSpacing or 4, x = opt.buffX or 0, y = opt.buffY or 0,
	}
end

-- Where the rank line ends: the first place below the bar that's free.
local function BelowBase(plate)
	return SUB_Y + ((plate.Sub:GetText() or "") ~= "" and 14 or 0) + 2
end

-- Place a block's start line: under the rank line (below) or on the frame's top (above),
-- `away` pixels further from the bar. A line as wide as the bar, centred like it (every frame
-- is centred on the plate), so left / right alignment follows the bar's ends.
local function PlaceRef(plate, ref, pos, away)
	ref:ClearAllPoints()
	ref:SetSize(plate.barW or 252, 1)
	if pos == "above" then
		ref:SetPoint("BOTTOM", plate.FrameBox, "TOP", 0, 3 + away)
	else
		ref:SetPoint("TOP", plate, "TOP", 0, -(BelowBase(plate) + away))
	end
end

-- Lay out the shown icons line by line; returns the height they take.
local function PlaceAuras(buttons, count, spec, ref)
	local size, gap, cols = spec.size, spec.gap, spec.cols
	local above = spec.pos == "above"
	local vpoint = above and "BOTTOM" or "TOP"
	local pitch = size + gap + 2
	for i = 1, count do
		local button = buttons[i]
		button:SetSize(size, size)
		button:ClearAllPoints()
		local line, col = math.floor((i - 1) / cols), (i - 1) % cols
		local y = line * pitch * (above and 1 or -1)
		if spec.align == "center" then
			local inLine = math.min(cols, count - line * cols)
			local x = (col - (inLine - 1) / 2) * (size + gap)
			button:SetPoint(vpoint, ref, vpoint, spec.x + x, y)
		else
			local edge = spec.align == "left" and "LEFT" or "RIGHT"
			local dir = spec.grow == "left" and -1 or 1
			local point = vpoint .. (dir > 0 and "LEFT" or "RIGHT")
			button:SetPoint(point, ref, vpoint .. edge, spec.x + dir * col * (size + gap), y)
		end
	end
	return count > 0 and math.ceil(count / cols) * pitch or 0
end

local function UpdateAuraIcons(plate)
	local opt = Opt()
	local debuffs = opt.debuffs and Collect("HARMFUL", math.min(MAX_AURAS, opt.maxDebuffs or 16)) or {}
	local buffs = opt.buffs and Collect("HELPFUL", math.min(MAX_AURAS, opt.maxBuffs or 8)) or {}
	for i = 1, MAX_AURAS do
		local aura = debuffs[i]
		PaintAura(plate.debuffs[i], aura, "HARMFUL", aura and (Previewing() or Mine(aura, U())))
		PaintAura(plate.buffs[i], buffs[i], "HELPFUL", true)
	end
	-- Nudge up is positive; `away` counts from the bar outwards.
	local d, b = AuraSpec(opt, "debuff"), AuraSpec(opt, "buff")
	local dAway = d.pos == "above" and d.y or -d.y
	PlaceRef(plate, plate.auraRef, d.pos, dAway)
	local dH = PlaceAuras(plate.debuffs, #debuffs, d, plate.auraRef)
	-- On the same side as the debuffs, buffs start on the line after them.
	local bAway = b.pos == "above" and b.y or -b.y
	if b.pos == d.pos then bAway = bAway + dAway + dH end
	PlaceRef(plate, plate.buffRef, b.pos, bAway)
	local bH = PlaceAuras(plate.buffs, #buffs, b, plate.buffRef)
	-- The cast bar goes under whatever aura lines are below, else under the rank line.
	local castY = SUB_Y + ((plate.Sub:GetText() or "") ~= "" and 16 or 2)
	if d.pos ~= "above" and dH > 0 then
		castY = math.max(castY, BelowBase(plate) + dAway + dH + 2)
	end
	if b.pos ~= "above" and bH > 0 then
		castY = math.max(castY, BelowBase(plate) + bAway + bH + 2)
	end
	plate.Cast:ClearAllPoints()
	plate.Cast:SetPoint("TOP", plate, "TOP", 0, -castY)
end

---------------------------------------------------------------------------
-- Aura containers. On clients with the restricted aura API (this one) a target's auras can't
-- be read by an addon at all in combat: every read above throws, and the rows come up empty.
-- Blizzard's answer is the AuraContainer widget (Plater and ElvUI use it too): the client
-- finds, sorts and fills the icons itself, and the addon only supplies the look. We never
-- learn how many there are, so the container sizes itself and the cast bar hangs off it.
--
-- Debuffs: "mine" (bright) and "others" (dimmed) groups on one line, yours first. Buffs on the
-- debuffs' side are a third group starting on a new line, else their own container.

local function HasTemplate(name)
	if not (C_XMLUtil and C_XMLUtil.GetTemplateInfo) then return false end
	local ok, info = pcall(C_XMLUtil.GetTemplateInfo, name)
	return ok and info ~= nil
end

local HAS_CONTAINERS = HasTemplate("CustomAuraContainerTemplate")
local NO_LAYOUT_SCRIPTS = HasTemplate("DisableUntrustedLayoutScriptsTemplate") and "DisableUntrustedLayoutScriptsTemplate" or nil

-- Socket tints: your debuffs gold, the others' grey, buffs plain.
local AURA_LOOK = {
	mine = { socket = { 1, 0.85, 0.5 }, alpha = 1 },
	others = { socket = { 0.55, 0.5, 0.45 }, alpha = 0.6, grey = true },
	buffs = { socket = { 1, 1, 1 }, alpha = 1 },
}

-- Size an aura button and fit its stone socket around it (no OnSizeChanged hook: aura buttons
-- don't run addon layout scripts).
local function SizeAuraButton(button, size)
	button:SetSize(size, size)
	local socket = button.sanctuarySocketTex
	if socket then
		local inset = ns.Art.SOCKET_INSET
		local fw = size / (1 - inset.left - inset.right)
		local fh = size / (1 - inset.top - inset.bottom)
		socket:ClearAllPoints()
		socket:SetPoint("TOPLEFT", button, "TOPLEFT", -fw * inset.left, fh * inset.top)
		socket:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", fw * inset.right, -fh * inset.bottom)
	end
end

-- Called by the client for each button it makes, before it locks the button down. Everything
-- about the look is set here: afterwards the button can't be touched while auras are secret.
local function DressAuraButton(button, look, size)
	local style = AURA_LOOK[look]
	local socket = button:CreateTexture(nil, "BACKGROUND", nil, -7)
	if ns.Art.Apply(socket, "socket") then
		socket:SetTexCoord(unpack(ns.Art.SOCKET_TEXCOORD))
	else
		socket:SetColorTexture(0.05, 0.05, 0.05, 0.9)
	end
	socket:SetVertexColor(style.socket[1], style.socket[2], style.socket[3])
	button.sanctuarySocketTex = socket

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	icon:SetDesaturated(style.grey or false)
	button:SetIcon(icon)

	local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	cooldown:SetAllPoints()
	cooldown:SetReverse(true)
	cooldown:EnableMouse(false)
	if cooldown.SetDrawEdge then cooldown:SetDrawEdge(false) end
	if cooldown.SetDrawBling then cooldown:SetDrawBling(false) end
	if cooldown.SetHideCountdownNumbers then cooldown:SetHideCountdownNumbers(true) end
	button:SetDurationCooldown(cooldown)

	-- The stack count above the sweep.
	local over = CreateFrame("Frame", nil, button)
	over:SetAllPoints()
	over:EnableMouse(false)
	over:SetFrameLevel(cooldown:GetFrameLevel() + 1)
	local count = over:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	count:SetPoint("BOTTOMRIGHT", 1, 1)
	button:SetApplicationCount(count)

	if button.SetTooltipAnchorPoint then button:SetTooltipAnchorPoint("ANCHOR_BOTTOMRIGHT", 0, 0) end
	button:SetAlpha(style.alpha)
	SizeAuraButton(button, size)
end

-- Layout per group: spacing between icons, between lines, and the icon size.
local function GroupLayout(spec, newLine)
	return {
		elementSpacing = spec.gap, lineSpacing = spec.gap + 2,
		groupLineSpacing = spec.gap + 2, forceNewLine = newLine or false,
		elementWidth = spec.size, elementHeight = spec.size,
	}
end

-- The groups each container holds, in display order. size() reads the current setting, so
-- buttons made later (more than the first batch of auras) come out at the right size.
local DEBUFF_GROUPS = {
	{ key = "mine", filter = "HARMFUL", look = "mine", candidates = { isFromPlayerOrPlayerPet = true } },
	{ key = "others", filter = "HARMFUL", look = "others", candidates = { isFromPlayerOrPlayerPet = false } },
	{ key = "buffs", filter = "HELPFUL", look = "buffs", newLine = true, kind = "buff" },
}
local BUFF_GROUPS = {
	{ key = "buffs", filter = "HELPFUL", look = "buffs", kind = "buff" },
}

local function MakeBox(plate, name, groups)
	local box = CreateFrame("AuraContainer", name, plate, "CustomAuraContainerTemplate")
	box:SetSize(1, 1)
	for _, group in ipairs(groups) do
		local kind = group.kind or "debuff"
		local look = group.look
		local opt = Opt()
		local spec = AuraSpec(opt, kind)
		-- A start (ConfigureBoxes sets the real one) in case the first update is in combat.
		local max = kind == "buff" and (opt.maxBuffs or 8) or (opt.maxDebuffs or 16)
		if group.newLine then max = 0 end
		box:AddAuraGroup(group.key, group.filter, {
			maxFrameCount = math.min(MAX_AURAS, max),
			sortMethod = AuraContainerSortMethod and AuraContainerSortMethod.Default or 0,
			sortDirection = AuraContainerSortDirection and AuraContainerSortDirection.Normal or 0,
			candidateFilters = group.candidates,
			initializeFrame = function(button)
				DressAuraButton(button, look, AuraSpec(Opt(), kind).size)
			end,
			layout = GroupLayout(spec, group.newLine),
		})
	end
	box:SetUnit("target")
	box:SetEnabled(true)
	return box
end

-- Builds the containers once. False when this client has none (or refuses), so the plain
-- icons are used instead.
local function MakeBoxes(plate)
	if not HAS_CONTAINERS then return false end
	local ok, debuffBox, buffBox = pcall(function()
		return MakeBox(plate, "SanctuaryUITargetDebuffs", DEBUFF_GROUPS), MakeBox(plate, "SanctuaryUITargetBuffs", BUFF_GROUPS)
	end)
	if not ok then
		if ns.LogError then ns.LogError("target", "aura containers: " .. tostring(debuffBox)) end
		return false
	end
	plate.debuffBox, plate.buffBox = debuffBox, buffBox
	return true
end

-- Flow: icons grow away from the anchored edge, lines away from the bar.
local function FlowBox(box, spec, cols)
	local above = spec.pos == "above"
	local dirs = AnchorUtil and AnchorUtil.FlowDirection or { Left = -1, Right = 1, Up = 1, Down = -1 }
	box:SetFlowLayoutAnchorPoint((above and "BOTTOM" or "TOP") .. (spec.grow == "left" and "RIGHT" or "LEFT"))
	box:SetFlowLayoutGrowthDirection(spec.grow == "left" and dirs.Left or dirs.Right, above and dirs.Up or dirs.Down)
	box:SetFlowLayoutMaximumLineSize(cols * spec.size + (cols - 1) * spec.gap)
end

-- Filters, counts, sizes and flow: only when a setting changed, and only out of combat (the
-- buttons can't be resized while auras are secret).
local function ConfigureBoxes(plate, opt, d, b, same)
	local preview = Previewing() and true or false
	local key = table.concat({
		tostring(opt.debuffs), tostring(opt.buffs), tostring(same), tostring(preview),
		opt.maxDebuffs or 16, opt.maxBuffs or 8,
		d.pos, d.align, d.grow, d.size, d.cols, d.gap, b.pos, b.align, b.grow, b.size, b.cols, b.gap,
	}, ":")
	if plate.boxKey == key or InCombatLockdown() then return end
	plate.boxKey = key
	local maxD = math.min(MAX_AURAS, opt.maxDebuffs or 16)
	local maxB = math.min(MAX_AURAS, opt.maxBuffs or 8)
	-- Previewing (no target): your own buffs stand in for the debuffs, as before.
	local unit = preview and "player" or "target"
	local function Set(box, group, enabled, max, filter, spec)
		box:SetAuraGroupEnabled(group.key, enabled)
		box:SetAuraGroupMaxFrameCount(group.key, enabled and max or 0)
		box:SetAuraGroupFilterString(group.key, filter)
		box:SetAuraGroupLayout(group.key, GroupLayout(spec, group.newLine))
		for i = 1, box:GetAuraGroupFrameCount(group.key) do
			local button = box:GetAuraGroupFrame(group.key, i)
			if button then SizeAuraButton(button, spec.size) end
		end
	end
	local db = plate.debuffBox
	for _, group in ipairs(DEBUFF_GROUPS) do
		if group.key == "buffs" then
			Set(db, group, same, maxB, "HELPFUL", b)
		else
			Set(db, group, opt.debuffs and true or false, maxD, preview and "HELPFUL" or "HARMFUL", d)
		end
	end
	Set(plate.buffBox, BUFF_GROUPS[1], (opt.buffs and not same) and true or false, maxB, "HELPFUL", b)
	-- The debuffs' flow sets the shared line's width when buffs join them.
	FlowBox(db, d, d.cols)
	FlowBox(plate.buffBox, b, b.cols)
	db:SetUnit(unit)
	plate.buffBox:SetUnit(unit)
end

-- Anchor a container to its start line. Centred, it sizes itself and is pinned by its middle.
-- Left or right, it is a band as wide as the bar starting at the bar's end, the icons flowing
-- from the band's edge. Either way its centre is known (the client keeps its size secret), so
-- this returns that centre's offset from the plate's, for the cast bar to hang under it.
local function AnchorBox(box, spec, ref, width)
	local vpoint = spec.pos == "above" and "BOTTOM" or "TOP"
	box:ClearAllPoints()
	if spec.align == "center" then
		box:SetPoint(vpoint, ref, vpoint, spec.x, 0)
		return spec.x
	end
	local edge = vpoint .. (spec.align == "left" and "LEFT" or "RIGHT")
	local from = spec.grow == "left" and spec.x - width or spec.x
	box:SetPoint(vpoint .. "LEFT", ref, edge, from, 0)
	box:SetPoint(vpoint .. "RIGHT", ref, edge, from + width, 0)
	return (spec.align == "left" and -width / 2 or width / 2) + from + width / 2
end

local function UpdateBoxes(plate)
	local opt = Opt()
	local d, b = AuraSpec(opt, "debuff"), AuraSpec(opt, "buff")
	local same = (opt.debuffs and opt.buffs and b.pos == d.pos) and true or false
	ConfigureBoxes(plate, opt, d, b, same)

	local width = plate.barW or 252
	local dAway = d.pos == "above" and d.y or -d.y
	PlaceRef(plate, plate.auraRef, d.pos, dAway)
	local dMid = AnchorBox(plate.debuffBox, d, plate.auraRef, width)
	local bAway = b.pos == "above" and b.y or -b.y
	PlaceRef(plate, plate.buffRef, b.pos, bAway)
	local bMid = AnchorBox(plate.buffBox, b, plate.buffRef, width)
	plate.debuffBox:SetShown(opt.debuffs or same)
	plate.buffBox:SetShown(opt.buffs and not same)
	-- A target change: have the client read the new unit.
	plate.debuffBox:UpdateAllAuras()
	plate.buffBox:UpdateAllAuras()

	-- The cast bar hangs under whichever container is below the bar (it may anchor to one:
	-- it was made without layout scripts), else under the rank line.
	local under, mid
	if (opt.debuffs or same) and d.pos ~= "above" then
		under, mid = plate.debuffBox, dMid
	elseif opt.buffs and not same and b.pos ~= "above" then
		under, mid = plate.buffBox, bMid
	end
	plate.Cast:ClearAllPoints()
	if not (under and plate.castAnchorable and pcall(plate.Cast.SetPoint, plate.Cast, "TOP", under, "BOTTOM", -mid, -4)) then
		plate.Cast:ClearAllPoints()
		plate.Cast:SetPoint("TOP", plate, "TOP", 0, -(SUB_Y + ((plate.Sub:GetText() or "") ~= "" and 16 or 2)))
	end
end

local function UpdateAuras(plate)
	if plate.debuffBox then
		local ok, err = pcall(UpdateBoxes, plate)
		if not ok and ns.LogError then ns.LogError("target", "aura containers: " .. tostring(err)) end
	else
		UpdateAuraIcons(plate)
	end
end

---------------------------------------------------------------------------

-- A unit's moving 3D portrait, square, behind the D3 frame, which hides its corners; out of
-- view (no model to draw) its round 2D portrait instead, masked into the hole.
local function ShowPortrait(portrait, unit)
	local visible = UnitIsVisible(unit)
	if not Secret(visible) and visible then
		portrait.model:SetUnit(unit)
		pcall(portrait.model.SetPortraitZoom, portrait.model, 1)
		portrait.model:Show()
		portrait.face:Hide()
	else
		portrait.model:Hide()
		SetPortraitTexture(portrait.face, unit)
		portrait.face:Show()
	end
end

local function UpdatePortrait(plate)
	local portrait = plate.Portrait
	if not Opt().portrait or not UnitExists(U()) then
		portrait:Hide()
		return
	end
	portrait:Show()
	ShowPortrait(portrait, U())
end

-- The ToT bar's fill: red for enemies, green for friends, amber for neutrals, grey if tapped,
-- as the target bar colours them.
local function ToTFill(bar, red, r, g, b)
	local path = ns.Art.Path(red and "unitFill" or "unitFillWhite")
	if path then
		if bar.fillPath ~= path then
			bar.fillPath = path
			bar:SetStatusBarTexture(path)
		end
		if red then r, g, b = 1, 1, 1 end
	else
		bar.fillPath = nil
		bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
		if red then r, g, b = 0.72, 0.1, 0.08 end
	end
	bar:SetStatusBarColor(r, g, b, 1)
end

-- The button shows and hides itself (RegisterUnitWatch, also in combat); this keeps what it
-- shows current. Polled (the client sends no events for targettarget); full also redraws the
-- portrait, which otherwise only changes when the unit does (its model would restart).
local function UpdateToT(plate, full)
	local art = plate.ToTArt
	local unit = "targettarget"
	if not UnitExists(unit) then
		plate.totGUID = nil
		return
	end
	local isYou = UnitIsUnit(unit, "player")
	if Secret(isYou) then isYou = false end
	local friendly = UnitIsFriend("player", unit)
	if Secret(friendly) then friendly = false end
	local reaction = UnitReaction("player", unit)
	if Secret(reaction) then reaction = nil end
	local tapped = UnitIsTapDenied and UnitIsTapDenied(unit)
	if Secret(tapped) then tapped = false end
	local color
	if tapped then
		color = NAME_COLORS.tapped
		ToTFill(art.Health, false, 0.45, 0.45, 0.45)
	elseif friendly then
		color = NAME_COLORS.friend
		ToTFill(art.Health, false, unpack(FRIEND_GREEN))
	elseif reaction and reaction == 4 then
		color = NAME_COLORS.neutral
		ToTFill(art.Health, false, 0.85, 0.62, 0.18)
	else
		color = NAME_COLORS.normal
		ToTFill(art.Health, true)
	end
	-- On you: your name in warning red, so a tank sees it at a glance.
	if isYou then
		art.Name:SetText(YOU or "You")
		art.Name:SetTextColor(1, 0.38, 0.25)
	else
		if not pcall(art.Name.SetText, art.Name, ns.Or(UnitName(unit), "")) then art.Name:SetText("") end
		art.Name:SetTextColor(color[1], color[2], color[3])
	end
	-- Health may be secret: the bar takes it as is.
	local health, maxHealth = UnitHealth(unit), UnitHealthMax(unit)
	pcall(art.Health.SetMinMaxValues, art.Health, 0, ns.Or(maxHealth, 1))
	pcall(art.Health.SetValue, art.Health, ns.Or(health, 0))
	local guid = UnitGUID(unit)
	if Secret(guid) then guid = nil end
	if art.portraitShown and (full or (guid and guid ~= plate.totGUID)) then
		plate.totGUID = guid
		ShowPortrait(art.Portrait, unit)
	end
end

-- snap: a new target, so the bar jumps to its health instead of draining to it.
function ns.TargetPlate.Update(snap)
	local plate = ns.TargetPlate.frame
	if not plate or not Opt().enabled or not UnitExists(U()) then return end

	local rank, colorKey, classification = Rank()
	SetPiece(plate, rank)

	local friendly = UnitIsFriend("player", U())
	if Secret(friendly) then friendly = false end
	friendly = friendly and not Previewing()
	local reaction = UnitReaction("player", U())
	if Secret(reaction) then reaction = nil end
	local tapped = UnitIsTapDenied and UnitIsTapDenied(U())
	if Secret(tapped) then tapped = false end
	local nameColor
	if tapped then
		nameColor = NAME_COLORS.tapped
		SetFillColor(plate, false, 0.45, 0.45, 0.45)
	elseif friendly then
		nameColor = NAME_COLORS.friend
		SetFillColor(plate, false, unpack(FRIEND_GREEN))
	elseif reaction and reaction == 4 then
		nameColor = NAME_COLORS.neutral
		SetFillColor(plate, false, 0.85, 0.62, 0.18)
	else
		nameColor = NAME_COLORS[colorKey]
		SetFillColor(plate, true)
	end
	if Previewing() then
		plate.Name:SetText(PREVIEW_NAMES[rank] or "")
	elseif not pcall(plate.Name.SetText, plate.Name, ns.Or(UnitName(U()), "")) then
		plate.Name:SetText("")
	end
	plate.Name:SetTextColor(nameColor[1], nameColor[2], nameColor[3])

	local level = UnitLevel(U())
	if not Secret(level) and level then
		plate.Level:SetText(level == -1 and "??" or level)
	else
		plate.Level:SetText("")
	end
	-- Level colour: plain cream, or by difficulty (grey, green, yellow, orange, red; skull red).
	local lr, lg, lb = 0.95, 0.9, 0.8
	if Opt().levelColor == "difficulty" and not Secret(level) and level then
		if level == -1 then
			lr, lg, lb = 1, 0.1, 0.1
		else
			local f = GetCreatureDifficultyColor or GetQuestDifficultyColor
			local ok, c = pcall(f, level)
			if ok and type(c) == "table" and c.r then lr, lg, lb = c.r, c.g, c.b end
		end
	end
	plate.Level:SetTextColor(lr, lg, lb)
	local badge = plate.Portrait.badge
	badge.text:SetText(plate.Level:GetText() or "")
	badge.text:SetTextColor(lr, lg, lb)
	plate.Sub:SetText(RANK_LABEL[classification] or "")

	SetHealth(plate, snap)
	UpdateToT(plate, true)
	UpdatePortrait(plate)
	UpdateAuras(plate)
	StartCast(plate.Cast, false)
end

function ns.TargetPlate.Layout()
	local plate = ns.TargetPlate.frame
	if not plate then return end
	if InCombatLockdown() then
		ns.TargetPlate.pending = true
		return
	end
	ns.TargetPlate.pending = nil
	local opt = Opt()
	plate:SetScale(ns.Art.D3Scale(opt.scale))
	-- Wide enough for the widest frame (the boss banner) at this width, plus the portrait.
	local width = ns.Art.UNIT.boss[3] * (opt.width or 1)
	plate:SetSize(width, PLATE_H)
	plate:ClearAllPoints()
	if opt.moved then
		plate:SetPoint("CENTER", UIParent, "BOTTOMLEFT", opt.mx, opt.my)
	else
		plate:SetPoint("TOP", UIParent, "TOP", 0, -12)
	end
	plate.rank = nil -- redraw the frame at the new width
	-- Target of target click area: from the narrowest frame's right end (normal) to the end of
	-- the ToT bar hung off the widest's (the boss banner), on the bar's line.
	local w = opt.width or 1
	local art = plate.ToTArt
	local showPortrait = opt.totPortrait ~= false
	if art.portraitShown ~= showPortrait then
		art.SetPortraitShown(showPortrait)
		plate.totGUID = nil -- back on: draw the current unit's portrait
	end
	local from = ns.Art.UNIT.normal[3] * w / 2
	local to = ns.Art.UNIT.boss[3] * w / 2 + TOT_GAP + art.width
	plate.ToT:ClearAllPoints()
	plate.ToT:SetPoint("LEFT", plate, "TOP", from, -BAR_Y)
	plate.ToT:SetSize(to - from, art.height)
	local font = TEXT_FONTS[opt.nameFont] or ns.FONT or STANDARD_TEXT_FONT
	local size = math.max(8, math.floor((opt.nameSize or 13) * 0.8 + 0.5))
	art.Name:SetFont(font, size, "OUTLINE")
	if not art.Name:GetFont() then art.Name:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE") end
	if opt.enabled and opt.tot ~= false then
		RegisterUnitWatch(plate.ToT)
	else
		UnregisterUnitWatch(plate.ToT)
		plate.ToT:Hide()
	end
	if opt.enabled and ns.TargetPlate.preview then
		-- Previewing: shown whether or not there is a target.
		UnregisterUnitWatch(plate)
		plate:Show()
	elseif opt.enabled then
		RegisterUnitWatch(plate)
	else
		UnregisterUnitWatch(plate)
		plate:Hide()
	end
end

function ns.TargetPlate.SetPreview(on)
	if InCombatLockdown() then
		ns.Print("cannot preview in combat")
		return
	end
	ns.TargetPlate.preview = on and true or nil
	preview.rank, preview.clock, preview.health = 1, 0, 1
	ns.TargetPlate.Layout()
	ns.TargetPlate.Update(true)
end

function ns.TargetPlate.ApplySettings()
	ns.TargetPlate.Layout()
	ns.TargetPlate.Update()
end

function ns.TargetPlate.ResetPosition()
	local opt = Opt()
	opt.moved, opt.mx, opt.my = false, 0, 0
	ns.Refresh()
end

-- Hovering the target or its target: the unit's tooltip where Blizzard puts unit tooltips (as
-- the portraits do), and a warm wash over that bar.
local function ShowUnitTooltip(owner, unit, hover)
	if hover then hover:Show() end
	if not UnitExists(unit) or GameTooltip:IsForbidden() then return end
	if GameTooltip_SetDefaultAnchor then
		GameTooltip_SetDefaultAnchor(GameTooltip, owner)
	else
		GameTooltip:SetOwner(owner, "ANCHOR_BOTTOMRIGHT")
	end
	GameTooltip:SetUnit(unit)
	GameTooltip:AddLine("Right-click for options", 0.6, 0.6, 0.6)
	GameTooltip:Show()
end

local function HideUnitTooltip(hover)
	if hover then hover:Hide() end
	GameTooltip_Hide()
end

-- D3's hero portrait frame around a unit's portrait, at k times D3's size. A model can only be
-- clipped square, so it is a square a little wider than the 39 px hole; the frame's solid band
-- hides its corners and the hole reads round (measured: up to 48 px stays hidden under all
-- three frames).
local function MakeRing(parent, k)
	local cell, hole = ns.Art.TARGET_RING_CELL * k, ns.Art.TARGET_RING_HOLE * k
	local MODEL = 46 * k
	local portrait = CreateFrame("Frame", nil, parent)
	portrait:SetSize(cell, cell)
	portrait:SetFrameLevel(parent:GetFrameLevel() + 4)
	-- The hole: a pixel wider than D3's 39 px all round, so the face runs under the rim.
	local disc = CreateFrame("Frame", nil, portrait)
	disc:SetSize(hole + 2 * k, hole + 2 * k)
	disc:SetPoint("CENTER")
	-- A dark disc behind, so a portrait still loading never shows the plate through the hole.
	portrait.back = portrait:CreateTexture(nil, "BACKGROUND")
	portrait.back:SetSize(MODEL, MODEL)
	portrait.back:SetPoint("CENTER")
	portrait.back:SetColorTexture(0.03, 0.02, 0.02, 1)
	-- Out of view: the round 2D portrait.
	portrait.face = portrait:CreateTexture(nil, "ARTWORK")
	portrait.face:SetAllPoints(disc)
	ns.Art.MaskCircle(portrait.face, disc)
	portrait.face:Hide()
	portrait.model = CreateFrame("PlayerModel", nil, portrait)
	portrait.model:SetSize(MODEL, MODEL)
	portrait.model:SetPoint("CENTER")
	portrait.model:SetFrameLevel(portrait:GetFrameLevel() + 1)
	-- The frame art on its own layer, above the model.
	local over = CreateFrame("Frame", nil, portrait)
	over:SetAllPoints()
	over:SetFrameLevel(portrait:GetFrameLevel() + 2)
	portrait.over = over
	portrait.ring = over:CreateTexture(nil, "OVERLAY")
	portrait.ring:SetAllPoints()
	portrait.ringArt = ns.Art.Apply(portrait.ring, "targetRings")
	if portrait.ringArt then
		portrait.ring:SetTexCoord(ns.Art.TargetRingTexCoord("normal"))
	else
		-- No art: the model in a plain dark square frame.
		portrait.ring:ClearAllPoints()
		portrait.ring:SetSize(MODEL + 6 * k, MODEL + 6 * k)
		portrait.ring:SetPoint("CENTER")
		portrait.ring:SetDrawLayer("BACKGROUND", -1)
		portrait.ring:SetColorTexture(0.1, 0.08, 0.06, 1)
		portrait.ring:SetParent(portrait)
	end
	return portrait
end

-- The target of target, drawn: the ordinary monster bar (silver frame, health, name inside)
-- at TOT_K with the portrait ring at its left end, as the target bar wears it. Its left edge
-- is the ring's; SetPiece hangs it off the target frame's right end.
local function MakeToTArt(plate, parent)
	local k = TOT_K
	local piece = ns.Art.UNIT.normal
	local bar = piece.bar
	local reach = ns.Art.TARGET_RING.normal.reach
	local art = CreateFrame("Frame", nil, parent)
	art:SetFrameLevel(parent:GetFrameLevel() + 1)
	art:EnableMouse(false)
	-- The frame box: its top sits so the bar's middle is on the art's middle line.
	local box = CreateFrame("Frame", nil, art)
	box:SetSize(piece[3] * k, piece[4] * k)
	box:SetFrameLevel(art:GetFrameLevel() + 5)
	-- With its portrait (Target > Target of target portrait) the ring leads and the frame
	-- follows it; without, the frame starts where the ring did and the art is just the bar.
	function art.SetPortraitShown(show)
		show = show and true or false
		local frameLeft = show and (2 * reach - RING_OVERLAP) * k or 0
		art.width = frameLeft + piece[3] * k
		art.height = show and 2 * reach * k or piece[4] * k
		art:SetSize(art.width, art.height)
		box:ClearAllPoints()
		box:SetPoint("TOPLEFT", art, "LEFT", frameLeft, (bar[2] + bar[4] / 2) * k)
		if art.Portrait then art.Portrait:SetShown(show) end
		art.portraitShown = show
	end
	art.SetPortraitShown(true)
	ns.Art.DrawSliced(box, "normal", piece[3] * k, k)
	art.FrameBox = box
	local health = CreateFrame("StatusBar", nil, art)
	health:SetFrameLevel(art:GetFrameLevel() + 2)
	health:SetPoint("TOPLEFT", box, "TOPLEFT", bar[1] * k, -bar[2] * k)
	health:SetSize(bar[3] * k, bar[4] * k)
	health:SetMinMaxValues(0, 1)
	health:SetValue(1)
	art.Health = health
	ToTFill(health, true)
	local well = art:CreateTexture(nil, "BACKGROUND")
	well:SetAllPoints(health)
	if not ns.Art.Apply(well, "unitWell") then
		well:SetColorTexture(0.05, 0.04, 0.04, 0.95)
	end
	local glass = CreateFrame("Frame", nil, art)
	glass:SetAllPoints(health)
	glass:SetFrameLevel(art:GetFrameLevel() + 4)
	local gloss = glass:CreateTexture(nil, "OVERLAY")
	gloss:SetAllPoints()
	if not ns.Art.Apply(gloss, "unitGloss") then gloss:Hide() end
	-- Hover: a warm wash over the bar while the mouse is on the button.
	art.Hover = glass:CreateTexture(nil, "OVERLAY", nil, 1)
	art.Hover:SetAllPoints()
	art.Hover:SetColorTexture(1, 0.7, 0.3, 0.22)
	art.Hover:SetBlendMode("ADD")
	art.Hover:Hide()
	art.Name = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	art.Name:SetPoint("CENTER", health, "CENTER", 0, 0)
	art.Name:SetWidth(bar[3] * k - 6)
	art.Name:SetWordWrap(false)
	art.Name:SetShadowColor(0, 0, 0, 0.85)
	art.Name:SetShadowOffset(1, -1)
	art.Portrait = MakeRing(art, k)
	art.Portrait:SetPoint("CENTER", art, "LEFT", reach * k, 0)
	art.Portrait:SetShown(art.portraitShown)
	return art
end

function ns.TargetPlate.Init()
	local plate = CreateFrame("Button", "SanctuaryUITargetPlate", UIParent, "SecureUnitButtonTemplate")
	plate:SetSize(ns.Art.UNIT.boss[3], PLATE_H)
	-- In the console's strata and above its stack, so that moved down near the console it still
	-- gets the mouse (its aura tooltips) and draws over it. Its pieces take their levels from
	-- the plate's, so this comes first. The bag window is top-level and still rises over it.
	plate:SetFrameStrata("MEDIUM")
	plate:SetFrameLevel((ns.Cluster and ns.Cluster:GetFrameLevel() or 1) + ns.LEVEL.target)
	plate:SetAttribute("unit", "target")
	plate:SetAttribute("*type1", "target")
	plate:SetAttribute("*type2", "togglemenu")
	plate:RegisterForClicks("AnyUp")
	plate:EnableMouse(true)
	plate:SetScript("OnEnter", function(self) ShowUnitTooltip(self, "target", self.Hover) end)
	plate:SetScript("OnLeave", function(self) HideUnitTooltip(self.Hover) end)
	-- The frame keeps Update and Layout: it lives in a field of the module table.
	ns.TargetPlate.frame = plate

	-- The frame art (sliced, so it can stretch) sits over the health bar, which fills its slot;
	-- the pale trail runs under the health bar.
	plate.FrameBox = CreateFrame("Frame", nil, plate)
	plate.FrameBox:SetPoint("TOP", plate, "TOP", 0, 0)
	plate.FrameBox:SetFrameLevel(plate:GetFrameLevel() + 5)

	plate.Trail = CreateFrame("StatusBar", nil, plate)
	plate.Trail:SetFrameLevel(plate:GetFrameLevel() + 1)
	plate.Trail:SetStatusBarTexture(ns.Art.Path("unitFillWhite") or "Interface\\Buttons\\WHITE8X8")
	plate.Trail:SetStatusBarColor(1, 0.82, 0.5, 0.92) -- the hit, a warm flash draining away
	plate.Trail:SetMinMaxValues(0, 1)
	-- The empty well: D3's dark strip under the whole bar, so missing health is shaded. It
	-- belongs to the plate, not the trail, so it stays whatever the trail does.
	plate.Well = plate:CreateTexture(nil, "BACKGROUND")
	plate.Well:SetAllPoints(plate.Trail)
	if not ns.Art.Apply(plate.Well, "unitWell") then
		plate.Well:SetColorTexture(0.05, 0.04, 0.04, 0.95)
	end

	plate.Health = CreateFrame("StatusBar", nil, plate)
	plate.Health:SetFrameLevel(plate:GetFrameLevel() + 2)
	plate.Health:SetStatusBarTexture(ns.Art.Path("unitFill") or "Interface\\Buttons\\WHITE8X8")
	plate.Health:SetMinMaxValues(0, 1)

	-- Liquid over the fill (see AnimateLiquid), where the client can clip.
	local liquidOK = ns.Art.Path("liquidTile") and plate.Health.SetClipsChildren
	if liquidOK then
		-- The clip's right edge rides the fill texture, which the bar sizes itself (also from
		-- secret values), so the liquid always covers exactly the filled part.
		local fill = plate.Health:GetStatusBarTexture()
		local clip = CreateFrame("Frame", nil, plate.Health)
		clip:SetPoint("TOPLEFT")
		clip:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
		clip:SetClipsChildren(true)
		local layers = {}
		for i, spec in ipairs(LIQUID) do
			local layer = clip:CreateTexture(nil, "ARTWORK", nil, i)
			layer:SetPoint("TOPLEFT", plate.Health, "TOPLEFT")
			layer:SetSize(10, 10)
			layer:SetTexture(ns.Art.Path(spec.slot) or ns.Art.Path("liquidTile"), "REPEAT", "REPEAT")
			layer:SetBlendMode("ADD")
			layers[i] = layer
		end
		plate.liquid = { clip = clip, layers = layers, t = 0 }
		plate.spark = plate.Health:CreateTexture(nil, "OVERLAY")
		plate.spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
		plate.spark:SetBlendMode("ADD")
		plate.spark:SetWidth(14)
		plate.spark:SetPoint("CENTER", fill, "RIGHT", 0, 0)
		plate.spark:Hide()
	end

	-- The ember at the leading edge (see UpdateGlow): a red bloom trailing back into the fill
	-- and a thin hot core on the edge, both ADD, riding the fill texture's right end (which the
	-- client sizes, also from secret values) and clipped to the bar.
	local glowPath = ns.Art.Path("unitGlow")
	if glowPath and plate.Health.SetClipsChildren then
		local fill = plate.Health:GetStatusBarTexture()
		local edge = CreateFrame("Frame", nil, plate.Health)
		edge:SetAllPoints(plate.Health)
		edge:SetClipsChildren(true)
		edge:SetFrameLevel(plate.Health:GetFrameLevel() + 1)
		local function Sprite(u, sub)
			local tex = edge:CreateTexture(nil, "OVERLAY", nil, sub)
			tex:SetTexture(glowPath)
			tex:SetTexCoord(u, u + 18 / 64, 0, 1)
			tex:SetBlendMode("ADD")
			tex:SetSize(18, 16)
			-- The sprite's edge column is 4 px from its right side.
			tex:SetPoint("RIGHT", fill, "RIGHT", 4, 0)
			return tex
		end
		local bloom, core = Sprite(0, 1), Sprite(0.5, 2)
		bloom:SetVertexColor(1, 0.26, 0.06)
		core:SetVertexColor(1, 0.92, 0.58)
		plate.edgeGlow = { frame = edge, bloom = bloom, core = core }
	end

	-- Heal prediction (see SetPrediction): beside the fill, over the trail and well, clipped to
	-- the bar. The heal rides the fill's right end, the shield the heal's.
	local predict = CreateFrame("Frame", nil, plate.Health)
	predict:SetAllPoints(plate.Health)
	if predict.SetClipsChildren then predict:SetClipsChildren(true) end
	predict:SetFrameLevel(plate.Health:GetFrameLevel())
	local function Band(after, r, g, b, a)
		local band = CreateFrame("StatusBar", nil, predict)
		band:SetFrameLevel(plate.Health:GetFrameLevel())
		band:SetStatusBarTexture(ns.Art.Path("unitFillWhite") or "Interface\\Buttons\\WHITE8X8")
		band:SetStatusBarColor(r, g, b, a)
		band:SetMinMaxValues(0, 1)
		band:SetValue(0)
		band:SetPoint("TOPLEFT", after, "TOPRIGHT")
		band:SetPoint("BOTTOMLEFT", after, "BOTTOMRIGHT")
		band:SetWidth(10) -- the bar's width, set by SetPiece
		return band
	end
	-- The globes' colours: green heal, silver shield.
	plate.HealBand = Band(plate.Health:GetStatusBarTexture(), 0.42, 1.0, 0.36, 0.6)
	plate.AbsorbBand = Band(plate.HealBand:GetStatusBarTexture(), 0.8, 0.88, 1.0, 0.6)
	local over = predict:CreateTexture(nil, "OVERLAY")
	over:SetTexture("Interface\\RaidFrame\\Shield-Overshield")
	over:SetBlendMode("ADD")
	over:SetVertexColor(0.75, 0.87, 1.0, 0.95)
	over:SetPoint("TOPRIGHT", plate.Health, "TOPRIGHT", 0, 0)
	over:SetPoint("BOTTOMRIGHT", plate.Health, "BOTTOMRIGHT", 0, 0)
	over:SetWidth(14)
	over:SetAlpha(0)
	plate.OverShield = over

	-- Glass over the whole bar (well, trail, fill and liquid), under the frame and the text: an
	-- inner shadow below the frame's lips and a soft highlight band, so it reads as a tube.
	local glass = CreateFrame("Frame", nil, plate)
	glass:SetAllPoints(plate.Health)
	glass:SetFrameLevel(plate:GetFrameLevel() + 4)
	plate.Gloss = glass:CreateTexture(nil, "OVERLAY")
	plate.Gloss:SetAllPoints()
	if not ns.Art.Apply(plate.Gloss, "unitGloss") then
		plate.Gloss:Hide()
	end
	-- Hover: the same warm wash the target of target gets.
	plate.Hover = glass:CreateTexture(nil, "OVERLAY", nil, 1)
	plate.Hover:SetAllPoints()
	plate.Hover:SetColorTexture(1, 0.7, 0.3, 0.22)
	plate.Hover:SetBlendMode("ADD")
	plate.Hover:Hide()

	-- The name inside the bar, as D3 writes it; the level at the left end and the health text at
	-- the right by default. LayoutTexts places, sizes and fonts them from the options: numbers
	-- default to the game font (Exocet's digits space out), all outlined and shadowed.
	plate.Percent = plate.FrameBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	plate.Percent:SetTextColor(0.95, 0.9, 0.8)
	plate.Level = plate.FrameBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	plate.Name = plate.FrameBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	plate.Name:SetWordWrap(false)
	for _, fs in ipairs({ plate.Percent, plate.Level, plate.Name }) do
		fs:SetShadowColor(0, 0, 0, 0.85)
		fs:SetShadowOffset(1, -1)
	end

	-- Level and rank under the frame (where D3 lists an elite's affixes), and who it is after.
	-- The rank (Elite, Rare...) under the bar, where D3 lists an elite's affixes.
	plate.Sub = plate:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	plate.Sub:SetPoint("TOP", plate, "TOP", 0, -SUB_Y)
	plate.Sub:SetTextColor(0.75, 0.7, 0.6)

	-- Target of target: a secure unit button of its own (left-click targets, right-click opens
	-- its menu), right of the frame on the bar's line. RegisterUnitWatch shows it, also in combat.
	local tot = CreateFrame("Button", "SanctuaryUITargetTarget", plate, "SecureUnitButtonTemplate")
	tot:SetSize(10, 22) -- placed by Layout

	tot:SetFrameStrata("MEDIUM")
	tot:EnableMouse(true)
	tot:SetAttribute("unit", "targettarget")
	tot:SetAttribute("*type1", "target")
	tot:SetAttribute("*type2", "togglemenu")
	tot:RegisterForClicks("AnyUp")
	-- The drawn bar is a plain child (so it shows and hides with the button) that follows the
	-- rank's frame end; the button is a fixed click area over everywhere it can be, since a
	-- secure button can't move in combat.
	plate.ToTArt = MakeToTArt(plate, tot)
	tot:SetScript("OnEnter", function(self) ShowUnitTooltip(self, "targettarget", plate.ToTArt.Hover) end)
	tot:SetScript("OnLeave", function() HideUnitTooltip(plate.ToTArt.Hover) end)
	tot:HookScript("OnShow", function() UpdateToT(plate, true) end)
	plate.ToT = tot -- shown by RegisterUnitWatch (Layout)

	-- The optional target portrait: the target's moving WoW portrait in one of D3's hero
	-- portrait frames (silver for normal, gold for elite and rare, the winged demon for bosses).
	local portrait = MakeRing(plate, 1)
	local over = portrait.over
	-- The level plaque under the frame (LayoutTexts shows it), above the ring's art.
	portrait.badge = ns.Art.LevelBadge(over, 60, 15, "silver")
	portrait.badge:SetFrameLevel(over:GetFrameLevel() + 1)
	portrait.badge:Hide()
	portrait:Hide()
	plate.Portrait = portrait

	SetPiece(plate, "normal")

	-- Cast bar: D3's thin progress bar (its orange glow fill), the spell's icon at its left
	-- and the spell name under it; a lock and grey wash when it can't be interrupted.
	-- Made without layout scripts, so it may hang under an aura container (see UpdateBoxes).
	local cast = CreateFrame("Frame", nil, plate, NO_LAYOUT_SCRIPTS)
	plate.castAnchorable = NO_LAYOUT_SCRIPTS ~= nil
	local piece = ns.Art.UNIT.cast
	cast:SetSize(piece[3], piece[4])
	cast:SetPoint("TOP", plate, "TOP", 0, -(SUB_Y + 16)) -- moved under the auras by UpdateAuras
	cast.bar = CreateFrame("StatusBar", nil, cast)
	cast.bar:SetPoint("TOPLEFT", piece.bar[1], -piece.bar[2])
	cast.bar:SetSize(piece.bar[3], piece.bar[4])
	cast.bar:SetStatusBarTexture(ns.Art.Path("castFill") or "Interface\\Buttons\\WHITE8X8")
	if not ns.Art.Path("castFill") then
		cast.bar:SetStatusBarColor(1, 0.45, 0.1, 1)
	end
	local castBg = cast.bar:CreateTexture(nil, "BACKGROUND")
	castBg:SetAllPoints()
	castBg:SetColorTexture(0.02, 0.015, 0.01, 0.95)
	local castArt = CreateFrame("Frame", nil, cast)
	castArt:SetAllPoints()
	castArt:SetFrameLevel(cast.bar:GetFrameLevel() + 2)
	ns.Art.DrawSliced(castArt, "cast", piece[3], 1)
	cast.shield = cast.bar:CreateTexture(nil, "OVERLAY")
	cast.shield:SetAllPoints()
	cast.shield:SetColorTexture(0.45, 0.45, 0.5, 0.7)
	cast.shield:SetAlpha(0)
	cast.icon = castArt:CreateTexture(nil, "OVERLAY")
	cast.icon:SetSize(20, 20)
	cast.icon:SetPoint("RIGHT", cast, "LEFT", -4, -4)
	cast.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	cast.lock = castArt:CreateTexture(nil, "OVERLAY", nil, 2)
	cast.lock:SetSize(14, 16)
	cast.lock:SetPoint("CENTER", cast.icon, "BOTTOMRIGHT", -1, 2)
	cast.lock:SetTexture("Interface\\PetBattles\\PetBattle-LockIcon")
	cast.lock:SetAlpha(0)
	cast.spellName = castArt:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	cast.spellName:SetPoint("TOP", cast, "BOTTOM", 0, -1)
	cast.spellName:SetWidth(piece[3])
	cast.spellName:SetWordWrap(false)
	cast.spellName:SetTextColor(1, 0.82, 0.55)
	cast:Hide()
	cast:SetScript("OnUpdate", function(self)
		if self.timer then
			-- Stop events end it; this only catches a cast whose end the client knows.
			local d = self.bar.GetTimerDuration and self.bar:GetTimerDuration()
			local left = d and d.GetRemainingDuration and d:GetRemainingDuration()
			if left and not Secret(left) and left <= 0 then
				StopCast(self)
			end
			return
		end
		if not self.startMS or not self.endMS then return end
		local now = GetTime() * 1000
		if self.channel then
			self.bar:SetValue(self.endMS - (now - self.startMS))
		else
			self.bar:SetValue(now)
		end
		if now >= self.endMS then
			StopCast(self)
		end
	end)
	plate.Cast = cast

	-- Aura rows hang off thin lines placed by PlaceRef; the cast bar goes under them.
	plate.auraRef = CreateFrame("Frame", nil, plate)
	plate.auraRef:SetSize(1, 1)
	plate.buffRef = CreateFrame("Frame", nil, plate)
	plate.buffRef:SetSize(1, 1)
	plate.debuffs, plate.buffs = {}, {}
	for i = 1, MAX_AURAS do
		plate.debuffs[i] = MakeAura(plate, "SanctuaryUITargetDebuff" .. i)
		plate.buffs[i] = MakeAura(plate, "SanctuaryUITargetBuff" .. i)
	end
	-- Where the client has aura containers they replace these icons (see MakeBoxes).
	MakeBoxes(plate)

	ns.TargetPlate.mover = ns.MakeMover(plate, "Target", Opt, "Reset its position in /sanctuary > Target.")

	-- Every frame, on a plain child frame (so it runs while the plate shows, as the globes'
	-- driver does): health easing, the bar's liquid, the preview, and the target of target
	-- (no unit events) polled. Real time from GetTime, capped across loading screens.
	local driver = CreateFrame("Frame", nil, plate)
	local last, elapsedToT = nil, 0
	driver:SetScript("OnUpdate", function()
		local now = GetTime()
		local elapsed = last and math.min(0.1, math.max(0, now - last)) or 0
		last = now
		PreviewTick(plate, elapsed)
		Animate(plate, elapsed)
		elapsedToT = elapsedToT + elapsed
		if elapsedToT < 0.2 then return end
		elapsedToT = 0
		UpdateToT(plate)
	end)
	plate.driver = driver
	plate:HookScript("OnShow", function() ns.TargetPlate.Update(true) end)

	local events = CreateFrame("Frame", nil, UIParent)
	events:RegisterEvent("PLAYER_TARGET_CHANGED")
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:RegisterEvent("PLAYER_REGEN_ENABLED")
	events:RegisterEvent("UI_SCALE_CHANGED")
	events:RegisterEvent("DISPLAY_SIZE_CHANGED")
	events:RegisterUnitEvent("UNIT_HEALTH", "target")
	events:RegisterUnitEvent("UNIT_MAXHEALTH", "target")
	events:RegisterUnitEvent("UNIT_HEAL_PREDICTION", "target")
	events:RegisterUnitEvent("UNIT_ABSORB_AMOUNT_CHANGED", "target")
	events:RegisterUnitEvent("UNIT_AURA", "target")
	events:RegisterUnitEvent("UNIT_NAME_UPDATE", "target")
	events:RegisterUnitEvent("UNIT_FACTION", "target")
	events:RegisterUnitEvent("UNIT_LEVEL", "target")
	events:RegisterUnitEvent("UNIT_MODEL_CHANGED", "target")
	events:RegisterUnitEvent("UNIT_PORTRAIT_UPDATE", "target")
	pcall(events.RegisterUnitEvent, events, "UNIT_CLASSIFICATION_CHANGED", "target")
	events:RegisterUnitEvent("UNIT_TARGET", "target")
	events:RegisterUnitEvent("UNIT_SPELLCAST_START", "target")
	events:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "target")
	events:RegisterUnitEvent("UNIT_SPELLCAST_DELAYED", "target")
	events:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "target")
	events:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "target")
	events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "target")
	events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "target")
	events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", "target")
	pcall(events.RegisterUnitEvent, events, "UNIT_SPELLCAST_EMPOWER_START", "target")
	pcall(events.RegisterUnitEvent, events, "UNIT_SPELLCAST_EMPOWER_UPDATE", "target")
	pcall(events.RegisterUnitEvent, events, "UNIT_SPELLCAST_EMPOWER_STOP", "target")
	pcall(events.RegisterUnitEvent, events, "UNIT_SPELLCAST_INTERRUPTIBLE", "target")
	pcall(events.RegisterUnitEvent, events, "UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "target")
	events:SetScript("OnEvent", function(_, event)
		if event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
			ns.TargetPlate.Layout()
			return
		end
		if not Opt().enabled then return end
		if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_DELAYED" then
			StartCast(plate.Cast, false)
		elseif event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" or event == "UNIT_SPELLCAST_EMPOWER_START" or event == "UNIT_SPELLCAST_EMPOWER_UPDATE" then
			StartCast(plate.Cast, true)
		elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_CHANNEL_STOP" or event == "UNIT_SPELLCAST_EMPOWER_STOP" then
			StopCast(plate.Cast)
		elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" or event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
			SetShield(plate.Cast, event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE")
		elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
			SetHealth(plate)
		elseif event == "UNIT_HEAL_PREDICTION" or event == "UNIT_ABSORB_AMOUNT_CHANGED" then
			SetPrediction(plate, UnitHealth(U()), UnitHealthMax(U()))
		elseif event == "UNIT_AURA" then
			-- The containers watch auras themselves.
			if not plate.debuffBox then UpdateAuraIcons(plate) end
		elseif event == "UNIT_MODEL_CHANGED" or event == "UNIT_PORTRAIT_UPDATE" then
			UpdatePortrait(plate)
		elseif event == "PLAYER_REGEN_ENABLED" then
			if ns.TargetPlate.pending then ns.TargetPlate.Layout() end
			-- The rank changed in combat: fit the click area to its frame now.
			if plate.hitStale then
				plate.rank = nil
				ns.TargetPlate.Update()
			end
			-- Aura settings changed in combat wait for now.
			if plate.debuffBox then UpdateAuras(plate) end
		else
			ns.TargetPlate.Update(event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_ENTERING_WORLD")
		end
	end)

	plate:Hide()
	ns.TargetPlate.Layout()
end
