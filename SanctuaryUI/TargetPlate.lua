SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI

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
--
-- Options > Target > Style swaps D3's bar for one of our own rendered frames (ns.Art.TARGET_STYLES):
-- a portrait socket, a health bar and a resource bar. SetStylePiece and ApplyStyle do that part; the
-- health, text and aura code below is shared. Those frames draw under the bars, D3's over them.


-- The focus frame (Options > Focus) is the same plate for the focus unit: Build runs this whole
-- file once per unit, filling a module table M from a config (CFG: unit, settings key, global
-- name prefix, the event for a new unit, its label and its default place). Everything below is
-- per plate; the body is not indented.
local function Build(M, CFG)
local UNIT, KEY = CFG.unit, CFG.key
local MAX_AURAS = 24 -- of each kind
-- Every rank's bar is centred on the same line (the boss banner's), and the lines under it sit
-- at fixed places, so nothing secure (the target-of-target button) hangs off a frame that
-- changes size in combat, and the plate doesn't jump between ranks.
local BAR_Y = 34.5 -- bar centre, below the plate's top
local SUB_Y = BAR_Y + 22 -- level / rank line (just under the normal and elite frames)
local PLATE_H = 88
local POWER_STRIP = 4 -- the resource's height along the bottom of D3's health bar
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
	return ns.DB()[KEY]
end

-- The rendered style in use at the Width and Height options, or nil for D3's monster bar.
local lastStyle = {}
local function Style()
	local opt = Opt()
	local name, w, h = opt.style or "d3", opt.width or 1, opt.height or 1
	local c = lastStyle
	if c.name ~= name or c.w ~= w or c.h ~= h then
		c.name, c.w, c.h = name, w, h
		c.style = ns.Art.TargetStyleSized(name, w, h)
	end
	return c.style
end

-- Pixels the Height option adds to D3's bar, the same on every rank so the plate doesn't jump
-- between them. The frame's top stays put and everything under the bar moves down.
local BAR_BASE_H = 18
local function BarExtra()
	if Style() then return 0 end
	return math.floor(BAR_BASE_H * ((Opt().height or 1) - 1) + 0.5)
end

local function BarLine() -- the bar's centre, below the plate's top
	return BAR_Y + BarExtra() / 2
end

local function SubY() -- the rank line, under the bar
	return SUB_Y + BarExtra()
end

-- Test mode (Options > Target > Preview): with no target, the plate shows a stand-in monster
-- drawn from your own unit, cycling the normal, elite, rare and boss frames with its health
-- dropping, so the look can be judged in game.
local PREVIEW_RANKS = { "normal", "elite", "rare", "boss" }
local PREVIEW_NAMES = { normal = "Risen Ghoul", elite = "Bonecrusher the Vile", rare = "Ashmaw the Hungry", boss = "The Butcher" }
local PREVIEW_CLASS = { normal = "normal", elite = "elite", rare = "rareelite", boss = "worldboss" }
local preview = { rank = 1, clock = 0, health = 1 }

-- The stand-in shows when asked for in options, and while frames are unlocked, so the plate
-- can be seen and placed with no target (as the party frames do).
local function Showcase()
	return (M.preview or not ns.DB().locked) and true or false
end

local function Previewing()
	return Showcase() and not UnitExists(UNIT)
end

-- The unit the plate reads: the target, or you while previewing.
local function U()
	return Previewing() and "player" or UNIT
end

local function Secret(value)
	return issecretvalue and issecretvalue(value)
end

-- Is the target a player? Unreadable counts as no. In the preview, the normal rank stands in for
-- one (drawn from you), so class colours and emblems can be judged.
local function IsPlayerTarget()
	if Previewing() then return PREVIEW_RANKS[preview.rank] == "normal" end
	local isPlayer = UnitIsPlayer(U())
	return not Secret(isPlayer) and isPlayer or false
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
		if rank == "rare" then return "elite", "rare", PREVIEW_CLASS.rare end
		return rank, rank, PREVIEW_CLASS[rank]
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

-- Class icon, faction emblem and raid marker: around a portrait, or (D3's bar with its portrait
-- off) in a row left of the frame on the bar's line.
local MARK_SIZE = { class = 20, faction = 24, raid = 20 }
local D3_MARKS = { class = { -28, 24 }, faction = { 28, 24 }, raid = { 0, 36 } }
local MARK_ROW = { class = 0, faction = 1, raid = 2 }

local function LayoutMarks(plate)
	local style, showPortrait = Style(), Opt().portrait
	for key, size in pairs(MARK_SIZE) do
		local mark = plate.Marks[key]
		mark:ClearAllPoints()
		mark:SetSize(size, size)
		if style then
			mark:SetPoint("CENTER", plate, "TOPLEFT", style.marks[key][1], -style.marks[key][2])
		elseif showPortrait then
			mark:SetPoint("CENTER", plate.Portrait, "CENTER", D3_MARKS[key][1], D3_MARKS[key][2])
		else
			mark:SetPoint("RIGHT", plate.FrameBox, "TOPLEFT", -4 - MARK_ROW[key] * 24, -(BarLine() - (plate.frameTop or 0)))
		end
	end
end

-- What rides on the health bar, sized to it.
local function FitBars(plate, w, h)
	plate.barW, plate.barH = w, h
	if plate.HealBand then
		plate.HealBand:SetWidth(w)
		plate.AbsorbBand:SetWidth(w)
	end
	if plate.edgeGlow then
		plate.edgeGlow.bloom:SetHeight(h)
		plate.edgeGlow.core:SetHeight(h)
	end
	if plate.liquid then
		for _, layer in ipairs(plate.liquid.layers) do
			layer:SetSize(w, h)
		end
		plate.spark:SetHeight(h * 1.8)
	end
end

-- A rendered frame: one piece of art per rank at fixed places, so a rank change only swaps art.
-- Width and Height stretch it in slices (ns.Art.DrawTargetStyle).
local function SetStylePiece(plate, rank, colorKey, style)
	local art = colorKey == "rare" and "rare" or rank
	local key = style.key .. art
	if plate.rank == key then return end
	plate.rank = key
	plate.StyleArt.tex:Hide()
	ns.Art.DrawTargetStyle(plate.StyleArt, style, art)
	local parts = ns.Art.Require("targetStyleParts")
	if parts then
		plate.StyleBadge.tex:SetTexture(parts)
		plate.StyleBadge.tex:SetTexCoord(ns.Art.TargetPartTexCoord("badge", art))
		plate.Cast.rail:SetTexture(parts)
		plate.Cast.rail:SetTexCoord(ns.Art.TargetPartTexCoord("rail", art))
		if style.portrait.round then
			plate.Portrait.ring:SetTexture(parts)
			plate.Portrait.ring:SetTexCoord(ns.Art.TargetPartTexCoord("ring", art))
		end
	end
	-- FrameBox is invisible here; texts and side columns measure from it.
	local box = plate.FrameBox
	box:ClearAllPoints()
	box:SetPoint("TOPLEFT", plate, "TOPLEFT", 0, 0)
	box:SetSize(style.size[1], style.size[2])
	plate.frameTop = 0
	local bar, w, h = style.bar, style.bar[3] - style.bar[1], style.bar[4] - style.bar[2]
	for _, b in ipairs({ plate.Health, plate.Trail }) do
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", plate, "TOPLEFT", bar[1], -bar[2])
		b:SetSize(w, h)
	end
	local power = style.power
	plate.Power:ClearAllPoints()
	plate.Power:SetPoint("TOPLEFT", plate, "TOPLEFT", power[1], -power[2])
	plate.Power:SetSize(power[3] - power[1], power[4] - power[2])
	FitBars(plate, w, h)
	LayoutTexts(plate)
	plate.ToTArt:ClearAllPoints()
	local grown = (plate.ToTArt.height - ns.Art.TARGET_TOT_STYLE.size[2]) / 2 -- as Layout places the button
	plate.ToTArt:SetPoint("TOPLEFT", plate, "TOPLEFT", style.tot[1], -(style.tot[2] - grown))
	LayoutMarks(plate)
end

-- Draw the rank's frame at the chosen width and fit the health bar (and its trail) to the slot.
-- The width D3's frame is drawn at for a rank (Options > Target > Width by rank).
local SAME_FRAME_W, SAME_BAR_W = 380, 300
local function D3FrameWidth(rank)
	local piece, w = ns.Art.UNIT[rank], Opt().width or 1
	local mode = Opt().rankWidth or "frame"
	if mode == "frame" then return SAME_FRAME_W * w end
	if mode == "bar" then return piece[3] + SAME_BAR_W * w - piece.bar[3] end
	return piece[3] * w
end

-- The narrowest and widest the frame can be drawn across the ranks.
local function D3WidthRange()
	local least, most = math.huge, 0
	for _, rank in ipairs({ "normal", "elite", "boss" }) do
		local w = D3FrameWidth(rank)
		least, most = math.min(least, w), math.max(most, w)
	end
	return least, most
end

local function SetPiece(plate, rank, colorKey)
	local style = Style()
	if style then
		SetStylePiece(plate, rank, colorKey, style)
		return
	end
	if plate.rank == rank then return end
	plate.rank = rank
	local piece = ns.Art.UNIT[rank]
	local width = D3FrameWidth(rank)
	local taller = BarExtra()
	local extra = ns.Art.DrawSliced(plate.FrameBox, rank, width, 1, taller)
	local bar = piece.bar
	plate.FrameBox:ClearAllPoints()
	plate.FrameBox:SetPoint("TOP", plate, "TOP", 0, -(BAR_Y - (bar[2] + bar[4] / 2)))
	plate.frameTop = BAR_Y - (bar[2] + bar[4] / 2)
	for _, b in ipairs({ plate.Health, plate.Trail }) do
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", plate.FrameBox, "TOPLEFT", bar[1], -bar[2])
		b:SetSize(bar[3] + extra, bar[4] + taller)
	end
	FitBars(plate, bar[3] + extra, bar[4] + taller)
	-- D3's frames have no groove for a resource: it runs along the bottom of the health bar.
	plate.Power:ClearAllPoints()
	plate.Power:SetPoint("BOTTOMLEFT", plate.Health, "BOTTOMLEFT", 0, 0)
	plate.Power:SetSize(bar[3] + extra, math.max(3, POWER_STRIP + math.floor(taller / 6 + 0.5)))
	-- Clicks only on the frame drawn for this rank (and its rank line), not the room the boss
	-- banner needs: the plate sits above the console, and its empty margins would block the
	-- console's buttons. A secure button: out of combat only; in combat it keeps the last size.
	if not InCombatLockdown() then
		local _, widest = D3WidthRange()
		local side = math.max(0, (widest - plate.FrameBox:GetWidth()) / 2)
		local bottom = math.max(0, PLATE_H + taller - math.max(piece[4] + taller, SubY() + 8))
		plate:SetHitRectInsets(side, side, 0, bottom)
		plate.hitStale = nil
	else
		plate.hitStale = true
	end
	LayoutTexts(plate)
	-- The target of target follows this frame's right end, on the bar's line.
	plate.ToTArt:ClearAllPoints()
	plate.ToTArt:SetPoint("LEFT", plate.Health, "RIGHT", (piece[3] - bar[1] - bar[3]) + TOT_GAP, 0)
	-- The portrait's D3 frame follows the rank too; its hole sits on the bar's line.
	local ring = ns.Art.TARGET_RING[rank] or ns.Art.TARGET_RING.normal
	plate.Portrait:ClearAllPoints()
	plate.Portrait:SetPoint("CENTER", plate.FrameBox, "TOPLEFT", -(ring.reach - RING_OVERLAP), -(bar[2] + (bar[4] + taller) / 2))
	if plate.Portrait.ringArt then
		plate.Portrait.ring:SetTexCoord(ns.Art.TargetRingTexCoord(rank))
	end
	local badge = plate.Portrait.badge
	badge:ClearAllPoints()
	badge:SetPoint("CENTER", plate.Portrait, "CENTER", 0, -(ring.badge or 50))
	badge:SetKind(ring.plate or "silver")
	LayoutMarks(plate)
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

-- The soft dark glow behind the bars' text. Text can't be blurred, so a ring of faint dark copies
-- sits under it. The copies are told the same things as the text (hooks, values passed straight
-- on, so a secret name or number works) and anchored like it, never to it. Their alpha is their
-- frame's, leaving each copy's own free to follow the text's, which may be secret.
local GLOW_COPIES, GLOW_RADIUS, GLOW_ALPHA = 8, 2, 0.3

local function AddTextGlow(fs, parent)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetAllPoints()
	frame:SetFrameLevel(parent:GetFrameLevel() + 4) -- over the bar, under the frame's art
	frame:SetAlpha(GLOW_ALPHA)
	fs.glowFrame = frame
	local copies = {}
	for i = 1, GLOW_COPIES do
		local copy = frame:CreateFontString(nil, "OVERLAY")
		copy:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
		copy:SetTextColor(0, 0, 0, 1)
		copy:SetShadowOffset(0, 0)
		local angle = 2 * math.pi * i / GLOW_COPIES
		copy.dx, copy.dy = GLOW_RADIUS * math.cos(angle), GLOW_RADIUS * math.sin(angle)
		copies[i] = copy
	end
	local function Mirror(method)
		hooksecurefunc(fs, method, function(_, ...)
			for _, copy in ipairs(copies) do
				pcall(copy[method], copy, ...)
			end
		end)
	end
	for _, method in ipairs({ "SetText", "SetFormattedText", "SetWidth", "SetJustifyH", "SetWordWrap", "SetAlpha", "ClearAllPoints", "Show", "Hide", "SetShown" }) do
		Mirror(method)
	end
	hooksecurefunc(fs, "SetFont", function(_, font, size)
		for _, copy in ipairs(copies) do
			copy:SetFont(font, size, "OUTLINE")
		end
	end)
	hooksecurefunc(fs, "SetPoint", function(_, point, relative, relativePoint, x, y)
		if type(relative) ~= "table" then return end
		for _, copy in ipairs(copies) do
			copy:SetPoint(point, relative, relativePoint, (x or 0) + copy.dx, (y or 0) + copy.dy)
		end
	end)
end

-- On, the glow replaces the text's drop shadow, which would pull it down and right.
local function SetTextGlow(fs, on)
	fs.glowFrame:SetShown(on)
	if on then
		fs:SetShadowOffset(0, 0)
	else
		fs:SetShadowOffset(1, -1)
	end
end

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
	local style = Style()
	if isName and pos == "center" and style and style.nameAt then
		-- A style with a name tab: "centre" means on the tab, leaving the bar to the health.
		fs:SetPoint("CENTER", plate, "TOPLEFT", style.nameAt[1] + x, -style.nameAt[2] + y)
		fs:SetJustifyH("CENTER")
		fs:SetWidth(150)
		return
	end
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
	for _, fs in ipairs({ plate.Percent, plate.Level, plate.Name }) do
		SetTextGlow(fs, opt.textGlow ~= false)
	end
	PlaceText(plate, plate.Name, "name", true)
	PlaceText(plate, plate.Percent, "health")
	plate.Name:SetShown(opt.nameShow ~= false)
	local style = Style()
	local stud = plate.StyleBadge
	stud:SetShown(false)
	if style then
		-- The level on the frame's own stud, or (asked) as text on the bar.
		plate.Portrait.badge:Hide()
		local onStud = (opt.levelPos or "badge") == "badge"
		plate.levelOnBadge = onStud and true or nil
		if onStud then
			local font = TEXT_FONTS[opt.levelFont] or STANDARD_TEXT_FONT
			stud.text:SetFont(font, opt.levelSize or 10, "OUTLINE")
			if not stud.text:GetFont() then stud.text:SetFont(STANDARD_TEXT_FONT, opt.levelSize or 10, "OUTLINE") end
			stud.text:ClearAllPoints()
			stud.text:SetPoint("CENTER", stud, "CENTER", opt.levelX or 0, opt.levelY or 0)
			stud:ClearAllPoints()
			stud:SetPoint("CENTER", plate, "TOPLEFT", style.badge[1], -style.badge[2])
			stud:SetShown(opt.levelShow ~= false)
			plate.Level:Hide()
		else
			PlaceText(plate, plate.Level, "level")
			plate.Level:SetShown(opt.levelShow ~= false)
		end
		return
	end
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
		M.Update(true)
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

local function IsSide(spec)
	return spec.pos == "left" or spec.pos == "right"
end

-- Where the rank line ends: the first place below the bar that's free.
local function BelowBase(plate)
	return SubY() + ((plate.Sub:GetText() or "") ~= "" and 14 or 0) + 2
end

-- Columns beside the frame start from its top, middle or bottom (align left / centre / right).
local function PlaceSideRef(plate, ref, spec, away)
	local style = Style()
	local opt = Opt()
	local box = plate.FrameBox
	local top, mid, bottom
	if style then
		top, mid, bottom = 0, style.size[2] / 2, style.size[2]
	else
		local line, reach = BarLine(), 22 + BarExtra() / 2
		top, mid, bottom = line - reach, line, line + reach
	end
	-- From the top on the right, start under the target of target, which sits there.
	if spec.pos == "right" and spec.align == "left" and opt.tot ~= false then
		top = style and style.tot[2] + 19 + plate.ToTArt.height / 2 or (BarLine() + plate.ToTArt.height / 2 + 2)
	end
	local y = top
	if spec.align == "center" then
		y = mid
	elseif spec.align == "right" then
		y = bottom
	end
	y = y + away
	local gap = 6
	if spec.pos == "right" then
		ref:SetPoint("TOPLEFT", box, "TOPRIGHT", gap, -(y - (plate.frameTop or 0)))
	else
		-- Left of the frame, or left of D3's portrait ring where that's shown.
		if not style and opt.portrait then
			gap = gap + 2 * ns.Art.TARGET_RING.normal.reach - RING_OVERLAP
		elseif not style and (opt.classIcon ~= false or opt.factionIcon ~= false or opt.raidIcon ~= false) then
			gap = gap + 76 -- clear of the marks' row
		end
		ref:SetPoint("TOPRIGHT", box, "TOPLEFT", -gap, -(y - (plate.frameTop or 0)))
	end
end

-- Place a block's start line: under the rank line (below) or on the frame's top (above),
-- `away` pixels further from the bar. A line as wide as the bar, so left / right alignment
-- follows the bar's ends. Columns beside the frame get a point instead.
local function PlaceRef(plate, ref, spec, away)
	ref:ClearAllPoints()
	if IsSide(spec) then
		ref:SetSize(1, 1)
		PlaceSideRef(plate, ref, spec, away)
		return
	end
	ref:SetSize(plate.barW or 252, 1)
	local style = Style()
	if style and spec.pos == "above" then
		ref:SetPoint("BOTTOMLEFT", plate, "TOPLEFT", style.bar[1], -style.aboveY + away)
	elseif style then
		ref:SetPoint("TOPLEFT", plate, "TOPLEFT", style.bar[1], -(style.belowY + away))
	elseif spec.pos == "above" then
		ref:SetPoint("BOTTOM", plate.FrameBox, "TOP", 0, 3 + away)
	else
		ref:SetPoint("TOP", plate, "TOP", 0, -(BelowBase(plate) + away))
	end
end

-- Debuffs and buffs share one flow only when they are laid out alike.
local function SameFlow(d, b)
	if b.pos ~= d.pos or b.align ~= d.align then return false end
	-- Grow means nothing on a centred line or a side column (the option is greyed out there).
	return IsSide(d) or d.align == "center" or b.grow == d.grow
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
		if IsSide(spec) then
			local point = spec.pos == "right" and "TOPLEFT" or "TOPRIGHT"
			local dir = spec.pos == "right" and 1 or -1
			button:SetPoint(point, ref, point, spec.x + dir * line * pitch, -col * (size + gap))
		elseif spec.align == "center" then
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

-- A rendered style's cast bar: in its groove, else on a rail above the frame, riding over any
-- aura lines that are up there. `over` is the aura container above the frame, if there is one.
local function PlaceStyleCast(plate, style, over, overMid)
	local cast = plate.Cast
	cast:ClearAllPoints()
	if style.castGroove then
		cast:SetPoint("TOPLEFT", plate, "TOPLEFT", style.castGroove[1], -style.castGroove[2])
	elseif not (over and plate.castAnchorable and pcall(cast.SetPoint, cast, "BOTTOM", over, "TOP", -(overMid or 0), 4)) then
		cast:ClearAllPoints()
		cast:SetPoint("BOTTOMLEFT", plate, "TOPLEFT", style.bar[1], -style.castBottom)
	end
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
	PlaceRef(plate, plate.auraRef, d, dAway)
	local dH = PlaceAuras(plate.debuffs, #debuffs, d, plate.auraRef)
	-- Laid out like the debuffs, buffs start on the line after them.
	local bAway = b.pos == "above" and b.y or -b.y
	if SameFlow(d, b) and not IsSide(b) then bAway = bAway + dAway + dH end
	PlaceRef(plate, plate.buffRef, b, bAway)
	local bH = PlaceAuras(plate.buffs, #buffs, b, plate.buffRef)
	local style = Style()
	if style then
		PlaceStyleCast(plate, style, nil)
		return
	end
	-- The cast bar goes under whatever aura lines are below, else under the rank line.
	local castY = SubY() + ((plate.Sub:GetText() or "") ~= "" and 16 or 2)
	if d.pos == "below" and dH > 0 then
		castY = math.max(castY, BelowBase(plate) + dAway + dH + 2)
	end
	if b.pos == "below" and bH > 0 then
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
	box:SetUnit(UNIT)
	box:SetEnabled(true)
	return box
end

-- Builds the containers once. False when this client has none (or refuses), so the plain
-- icons are used instead.
local function MakeBoxes(plate)
	if not HAS_CONTAINERS then return false end
	local ok, debuffBox, buffBox = pcall(function()
		return MakeBox(plate, CFG.prefix .. "Debuffs", DEBUFF_GROUPS), MakeBox(plate, CFG.prefix .. "Buffs", BUFF_GROUPS)
	end)
	if not ok then
		if ns.LogError then ns.LogError(KEY, "aura containers: " .. tostring(debuffBox)) end
		return false
	end
	plate.debuffBox, plate.buffBox = debuffBox, buffBox
	return true
end

-- Flow: icons grow away from the anchored edge, lines away from the bar.
local function FlowBox(box, spec, cols)
	local above = spec.pos == "above"
	local dirs = AnchorUtil and AnchorUtil.FlowDirection or { Left = -1, Right = 1, Up = 1, Down = -1 }
	local axes = AnchorUtil and AnchorUtil.FlowLayoutAxis or { Horizontal = 0, Vertical = 1 }
	local side = IsSide(spec)
	if box.SetFlowLayoutAxis then
		box:SetFlowLayoutAxis(side and axes.Vertical or axes.Horizontal)
	end
	if side then
		-- Columns: running down (or up from the bottom), new ones away from the frame.
		local up = spec.align == "right"
		box:SetFlowLayoutAnchorPoint((up and "BOTTOM" or "TOP") .. (spec.pos == "right" and "LEFT" or "RIGHT"))
		box:SetFlowLayoutGrowthDirection(spec.pos == "right" and dirs.Right or dirs.Left, up and dirs.Up or dirs.Down)
	else
		box:SetFlowLayoutAnchorPoint((above and "BOTTOM" or "TOP") .. (spec.grow == "left" and "RIGHT" or "LEFT"))
		box:SetFlowLayoutGrowthDirection(spec.grow == "left" and dirs.Left or dirs.Right, above and dirs.Up or dirs.Down)
	end
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
	local unit = preview and "player" or UNIT
	local function Set(box, group, enabled, max, filter, spec)
		box:SetAuraGroupEnabled(group.key, enabled)
		box:SetAuraGroupMaxFrameCount(group.key, enabled and max or 0)
		box:SetAuraGroupFilterString(group.key, filter)
		box:SetAuraGroupLayout(group.key, GroupLayout(spec, group.newLine))
		box.sanctuarySizes = box.sanctuarySizes or {}
		ns.ResizeAuraButtons(box, group.key, spec.size, function(button)
			SizeAuraButton(button, spec.size)
		end, box.sanctuarySizes)
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
	box:ClearAllPoints()
	if IsSide(spec) then
		-- Pinned by its top, middle or bottom edge on the frame's side; the client sizes it.
		local v = spec.align == "right" and "BOTTOM" or (spec.align == "center" and "" or "TOP")
		local h = spec.pos == "right" and "LEFT" or "RIGHT"
		box:SetPoint(v .. h, ref, v .. h, spec.x, 0)
		return 0
	end
	local vpoint = spec.pos == "above" and "BOTTOM" or "TOP"
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
	local same = (opt.debuffs and opt.buffs and SameFlow(d, b)) and true or false
	ConfigureBoxes(plate, opt, d, b, same)

	local width = plate.barW or 252
	local dAway = d.pos == "above" and d.y or -d.y
	PlaceRef(plate, plate.auraRef, d, dAway)
	local dMid = AnchorBox(plate.debuffBox, d, plate.auraRef, width)
	local bAway = b.pos == "above" and b.y or -b.y
	PlaceRef(plate, plate.buffRef, b, bAway)
	local bMid = AnchorBox(plate.buffBox, b, plate.buffRef, width)
	plate.debuffBox:SetShown(opt.debuffs or same)
	plate.buffBox:SetShown(opt.buffs and not same)
	-- A target change: have the client read the new unit.
	plate.debuffBox:UpdateAllAuras()
	plate.buffBox:UpdateAllAuras()

	local style = Style()
	if style then
		-- A rail rides over whichever aura lines are above the frame.
		local over, overMid
		if (opt.debuffs or same) and d.pos == "above" then
			over, overMid = plate.debuffBox, dMid
		elseif opt.buffs and not same and b.pos == "above" then
			over, overMid = plate.buffBox, bMid
		end
		PlaceStyleCast(plate, style, over, overMid)
		return
	end

	-- The cast bar hangs under whichever container is below the bar (it may anchor to one:
	-- it was made without layout scripts), else under the rank line.
	local under, mid
	if (opt.debuffs or same) and d.pos == "below" then
		under, mid = plate.debuffBox, dMid
	elseif opt.buffs and not same and b.pos == "below" then
		under, mid = plate.buffBox, bMid
	end
	plate.Cast:ClearAllPoints()
	if not (under and plate.castAnchorable and pcall(plate.Cast.SetPoint, plate.Cast, "TOP", under, "BOTTOM", -mid, -4)) then
		plate.Cast:ClearAllPoints()
		plate.Cast:SetPoint("TOP", plate, "TOP", 0, -(SubY() + ((plate.Sub:GetText() or "") ~= "" and 16 or 2)))
	end
end

local function UpdateAuras(plate)
	if plate.debuffBox then
		local ok, err = pcall(UpdateBoxes, plate)
		if not ok and ns.LogError then ns.LogError(KEY, "aura containers: " .. tostring(err)) end
	else
		UpdateAuraIcons(plate)
	end
end

---------------------------------------------------------------------------

-- A unit's moving 3D portrait, square, behind the D3 frame, which hides its corners; out of
-- view (no model to draw) its round 2D portrait instead, masked into the hole.
-- When the client can't build a model for a unit, SetUnit leaves the model showing whatever it
-- had (a warlock's pet came up as the cat-form druid targeted before it). So a new unit clears
-- the model first, and this watches it load: nothing after a second, and the flat portrait shows
-- under the empty model; a model that turns up later (slow to load) takes over again.
local MODEL_WAIT, MODEL_GIVE_UP = 1, 10 -- seconds
local function WatchModel(portrait, unit)
	local model = portrait.model
	if not (model.GetModelFileID and C_Timer) then return end
	portrait.modelTicket = (portrait.modelTicket or 0) + 1
	local ticket, waited = portrait.modelTicket, 0
	local function Check()
		if portrait.modelTicket ~= ticket or not model:IsShown() then return end -- moved on
		local file = model:GetModelFileID()
		if Secret(file) or (file and file ~= 0) then
			portrait.fallback = nil
			portrait.face:Hide()
			return
		end
		if waited >= MODEL_WAIT and not portrait.fallback then
			portrait.fallback = true
			SetPortraitTexture(portrait.face, unit)
			portrait.face:Show()
		end
		if waited >= MODEL_GIVE_UP then return end
		local step = waited < MODEL_WAIT and 0.1 or 0.5
		waited = waited + step
		C_Timer.After(step, Check)
	end
	C_Timer.After(0.1, Check)
end

local function ShowPortrait(portrait, unit, force)
	local visible = UnitIsVisible(unit)
	if not Secret(visible) and visible then
		-- Setting the unit restarts the model's idle, so only for a different unit or a new model.
		local guid = UnitGUID(unit)
		if Secret(guid) then guid = nil end
		local fresh = force or (guid and guid ~= portrait.modelGUID) or not portrait.model:IsShown()
		if fresh or not guid then
			portrait.modelGUID = guid
			if fresh then
				portrait.fallback = nil
				if portrait.model.ClearModel then portrait.model:ClearModel() end
			end
			portrait.model:SetUnit(unit)
			pcall(portrait.model.SetPortraitZoom, portrait.model, 1)
			if fresh then WatchModel(portrait, unit) end
		end
		portrait.model:Show()
		portrait.face:SetShown(portrait.fallback and true or false)
	else
		portrait.fallback = nil
		portrait.model:Hide()
		SetPortraitTexture(portrait.face, unit)
		portrait.face:Show()
	end
end

local function UpdatePortrait(plate, force)
	local portrait = plate.Portrait
	if not (Opt().portrait or Style()) or not UnitExists(U()) then
		portrait:Hide()
		return
	end
	portrait:Show()
	ShowPortrait(portrait, U(), force)
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
	local unit = UNIT .. "target"
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
		if not pcall(art.Name.SetText, art.Name, ns.Or(ns.UnitDisplayName(unit, Opt().surnames ~= false), "")) then art.Name:SetText("") end
		art.Name:SetTextColor(color[1], color[2], color[3])
	end
	-- Health may be secret: the bar takes it as is.
	local health, maxHealth = UnitHealth(unit), UnitHealthMax(unit)
	pcall(art.Health.SetMinMaxValues, art.Health, 0, ns.Or(maxHealth, 1))
	pcall(art.Health.SetValue, art.Health, ns.Or(health, 0))
	local guid = UnitGUID(unit)
	if Secret(guid) then guid = nil end
	if (art.portraitShown or art.styled) and (full or (guid and guid ~= plate.totGUID)) then
		plate.totGUID = guid
		ShowPortrait(art.Portrait, unit)
	end
end

-- The dark track behind D3's resource strip shows only while there is power, so a monster with
-- no resource keeps a clean health bar. Power can be secret: then the client answers via a curve.
local TRACK_POINTS = { { 0, 0 }, { 0.001, 1 }, { 1, 1 } }

local function SetPowerTrack(track, unit, power)
	if not Secret(power) then
		track:SetAlpha((power or 0) > 0 and 1 or 0)
		return
	end
	local curve = UnitPowerPercent and Curve("powerTrack", TRACK_POINTS)
	if curve then
		local ok, alpha = pcall(UnitPowerPercent, unit, nil, true, curve)
		if ok and type(alpha) ~= "nil" and pcall(track.SetAlpha, track, alpha) then return end
	end
	track:SetAlpha(0)
end

-- The target's resource: a groove in the rendered styles, a strip in D3's bar. The bar takes
-- secret values as is.
local function UpdatePower(plate)
	local bar = plate.Power
	if not bar:IsShown() then return end
	local unit = U()
	local powerType, token = UnitPowerType(unit)
	local colors = ns.Globes and ns.Globes.POWER_COLORS
	local c = not Secret(token) and token and colors and colors[token]
	local r, g, b = 0.18, 0.36, 1.0
	if c then
		r, g, b = c[1], c[2], c[3]
	elseif PowerBarColor then
		local info = (not Secret(token) and PowerBarColor[token]) or (not Secret(powerType) and PowerBarColor[powerType])
		if info and info.r then r, g, b = info.r, info.g, info.b end
	end
	bar:SetStatusBarColor(r, g, b, 1)
	pcall(bar.SetMinMaxValues, bar, 0, ns.Or(UnitPowerMax(unit), 1))
	local power = UnitPower(unit)
	if not pcall(bar.SetValue, bar, ns.Or(power, 0)) then bar:SetValue(0) end
	SetPowerTrack(bar.track, unit, power)
end

-- A player's class colour, or nil when it's off or can't be read.
local function ClassNameColor()
	if Opt().classColor == false or not IsPlayerTarget() then return nil end
	local _, class = UnitClass(U())
	if not Secret(class) then
		return RAID_CLASS_COLORS and class and RAID_CLASS_COLORS[class]
	end
	if C_ClassColor and C_ClassColor.GetClassColor then
		local ok, color = pcall(C_ClassColor.GetClassColor, class)
		if ok then return color end
	end
end

-- The class icon, faction emblem and raid marker. Each hides when off or unreadable.
local function UpdateMarks(plate)
	local opt, unit, marks = Opt(), U(), plate.Marks
	local player = IsPlayerTarget()
	local coords
	if player and opt.classIcon ~= false and CLASS_ICON_TCOORDS then
		local _, class = UnitClass(unit)
		if not Secret(class) and class then coords = CLASS_ICON_TCOORDS[class] end
	end
	if coords then marks.class:SetTexCoord(unpack(coords)) end
	marks.class:SetShown(coords and true or false)
	local faction
	if player and opt.factionIcon ~= false then
		local group = UnitFactionGroup(unit)
		if not Secret(group) and (group == "Alliance" or group == "Horde") then faction = group end
	end
	if faction then
		marks.faction:SetTexture("Interface\\TargetingFrame\\UI-PVP-" .. faction)
		marks.faction:SetTexCoord(0, 0.65625, 0, 0.65625)
	end
	marks.faction:SetShown(faction and true or false)
	local index
	if opt.raidIcon ~= false then
		if Previewing() then
			index = PREVIEW_RANKS[preview.rank] == "normal" and 8 or nil
		elseif GetRaidTargetIndex then
			index = GetRaidTargetIndex(unit)
			if Secret(index) then index = nil end
		end
	end
	if index and SetRaidTargetIconTexture then
		SetRaidTargetIconTexture(marks.raid, index)
		marks.raid:Show()
	else
		marks.raid:Hide()
	end
end

-- snap: a new target, so the bar jumps to its health instead of draining to it.
function M.Update(snap)
	local plate = M.frame
	if not plate or not Opt().enabled or not UnitExists(U()) then return end

	local rank, colorKey, classification = Rank()
	SetPiece(plate, rank, colorKey)

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
	local classColor = ClassNameColor()
	if classColor then nameColor = { classColor.r, classColor.g, classColor.b } end
	if Previewing() then
		plate.Name:SetText(PREVIEW_NAMES[PREVIEW_RANKS[preview.rank]] or "")
	elseif not pcall(plate.Name.SetText, plate.Name, ns.Or(ns.UnitDisplayName(U(), Opt().surnames ~= false), "")) then
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
	plate.StyleBadge.text:SetText(plate.Level:GetText() or "")
	plate.StyleBadge.text:SetTextColor(lr, lg, lb)
	plate.Sub:SetText(RANK_LABEL[classification] or "")

	SetHealth(plate, snap)
	UpdatePower(plate)
	UpdateToT(plate, true)
	UpdatePortrait(plate, snap)
	UpdateMarks(plate)
	UpdateAuras(plate)
	StartCast(plate.Cast, false)
end

-- Sizes a portrait and what's in it; D3's sizes are kept on the portrait by MakeRing.
-- tall: a socket the Height option made taller than it is wide (the model fills it).
local function SizePortrait(portrait, frame, model, disc, tall)
	portrait:SetSize(frame, tall or frame)
	portrait.back:SetSize(model, tall or model)
	portrait.model:SetSize(model, tall or model)
	portrait.disc:SetSize(disc, disc)
end

-- The cast bar's look: the rendered rail or groove (spell inside the bar), or D3's thin bar.
local function StyleCast(cast, style)
	for _, slice in ipairs(cast.art.slices or {}) do
		slice:SetShown(not style)
	end
	cast.rail:SetShown(style and not style.castGroove and true or false)
	local name, icon, lock, bar = cast.spellName, cast.icon, cast.lock, cast.bar
	icon:ClearAllPoints()
	bar:ClearAllPoints()
	name:ClearAllPoints()
	if not style then
		local piece = ns.Art.UNIT.cast
		ns.Art.DrawSliced(cast.art, "cast", piece[3], 1)
		cast:SetSize(piece[3], piece[4])
		bar:SetPoint("TOPLEFT", piece.bar[1], -piece.bar[2])
		bar:SetSize(piece.bar[3], piece.bar[4])
		icon:SetSize(20, 20)
		icon:SetPoint("RIGHT", cast, "LEFT", -4, -4)
		lock:SetSize(14, 16)
		name:SetPoint("TOP", cast, "BOTTOM", 0, -1)
		name:SetWidth(piece[3])
		name:SetJustifyH("CENTER")
		return
	end
	local x0, y0, x1, y1
	local groove = style.castGroove
	if groove then
		x0, y0, x1, y1 = 0, 0, groove[3] - groove[1], groove[4] - groove[2]
		cast:SetSize(x1, y1)
	else
		x0, y0, x1, y1 = 4, 3.5, 232, 14.5
		cast:SetSize(236, 18)
	end
	local h = y1 - y0
	icon:SetSize(h, h)
	icon:SetPoint("TOPLEFT", cast, "TOPLEFT", x0, -y0)
	bar:SetPoint("TOPLEFT", cast, "TOPLEFT", x0 + h, -y0)
	bar:SetSize(x1 - x0 - h, h)
	lock:SetSize(h, h + 2)
	name:SetPoint("LEFT", bar, "LEFT", 3, 0)
	name:SetWidth(x1 - x0 - h - 6)
	name:SetJustifyH("LEFT")
end

-- Switch between D3's frame and a rendered one: what's shown and the portrait's and cast's shape.
local function ApplyStyle(plate)
	local style = Style()
	local key = style and style.key or "d3"
	plate.Power:SetShown(Opt().power ~= false)
	plate.Power.track:SetShown(not style)
	if plate.styleKey == key then return end
	plate.styleKey = key
	plate.rank = nil
	for _, slice in ipairs(plate.FrameBox.slices or {}) do
		slice:SetShown(not style)
	end
	plate.StyleArt:SetShown(style and true or false)
	plate.Well:SetShown(not style)
	plate.Sub:SetShown(not style)
	StyleCast(plate.Cast, style)
	local portrait = plate.Portrait
	local d3 = portrait.d3
	local ring = portrait.ring
	if not style then
		SizePortrait(portrait, d3.frame, d3.model, d3.disc)
		ring:ClearAllPoints()
		ring:SetAllPoints()
		ring:Show()
		if portrait.ringArt then ns.Art.Apply(ring, "targetRings") end
		return
	end
	local p = style.portrait
	local cx, cy, size
	if p.round then
		cx, cy, size = p.cx, p.cy, p.model
		SizePortrait(portrait, size, size, p.hole * 2 + 2)
	else
		cx, cy, size = (p[1] + p[3]) / 2, (p[2] + p[4]) / 2, p[3] - p[1]
		SizePortrait(portrait, size, size, size, p[4] - p[2])
	end
	portrait:ClearAllPoints()
	portrait:SetPoint("CENTER", plate, "TOPLEFT", cx, -cy)
	ring:SetShown(p.round and true or false)
	ring:ClearAllPoints()
	ring:SetPoint("CENTER", portrait.over, "CENTER", 0, 0)
	ring:SetSize(140, 140)
end

function M.Layout()
	local plate = M.frame
	if not plate then return end
	if InCombatLockdown() then
		M.pending = true
		return
	end
	M.pending = nil
	local opt = Opt()
	plate:SetScale(ns.Art.D3Scale(opt.scale))
	local style = Style()
	ApplyStyle(plate)
	-- Room for a cast rail above the frame, so its default place doesn't run off the screen.
	local room = 0
	if style then
		plate:SetSize(style.size[1], style.size[2])
		plate:SetHitRectInsets(0, 0, 0, 0)
		plate.hitStale = nil
		if style.castBottom then room = math.max(0, 18 - style.castBottom) end
	else
		-- Wide enough for the widest frame (the boss banner) at this width, plus the portrait.
		local _, widest = D3WidthRange()
		plate:SetSize(widest, PLATE_H + BarExtra())
		plate.Sub:ClearAllPoints()
		plate.Sub:SetPoint("TOP", plate, "TOP", 0, -SubY())
	end
	plate:ClearAllPoints()
	if opt.moved then
		plate:SetPoint("CENTER", UIParent, "BOTTOMLEFT", ns.MovedPoint(plate, opt))
	else
		CFG.place(plate, room)
	end
	plate.rank = nil -- redraw the frame at the new width
	-- Target of target click area: from the narrowest frame's right end (normal) to the end of
	-- the ToT bar hung off the widest's (the boss banner), on the bar's line.
	local w = opt.width or 1
	local art = plate.ToTArt
	art.SetStyled(style and true or false, opt.totWidth or 1, opt.totHeight or 1)
	if not style then
		art.Resize(opt.totWidth or 1, math.floor(BAR_BASE_H * TOT_K * ((opt.totHeight or 1) - 1) + 0.5))
	end
	local showPortrait = opt.totPortrait ~= false
	if art.portraitShown ~= showPortrait then
		art.SetPortraitShown(showPortrait)
		plate.totGUID = nil -- back on: draw the current unit's portrait
	end
	plate.ToT:ClearAllPoints()
	if style then
		-- A taller ToT grows about the middle it has at its own height.
		local grown = (art.height - ns.Art.TARGET_TOT_STYLE.size[2]) / 2
		plate.ToT:SetPoint("TOPLEFT", plate, "TOPLEFT", style.tot[1], -(style.tot[2] - grown))
		plate.ToT:SetSize(art.width, art.height)
	else
		local least, most = D3WidthRange()
		local from, to = least / 2, most / 2 + TOT_GAP + art.width
		plate.ToT:SetPoint("LEFT", plate, "TOP", from, -BarLine())
		plate.ToT:SetSize(to - from, art.height)
	end
	local font = TEXT_FONTS[opt.nameFont] or ns.FONT or STANDARD_TEXT_FONT
	local size = math.max(8, math.floor((opt.nameSize or 13) * 0.8 + 0.5))
	art.Name:SetFont(font, size, "OUTLINE")
	if not art.Name:GetFont() then art.Name:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE") end
	SetTextGlow(art.Name, opt.textGlow ~= false)
	if opt.enabled and opt.tot ~= false then
		RegisterUnitWatch(plate.ToT)
	else
		UnregisterUnitWatch(plate.ToT)
		plate.ToT:Hide()
	end
	if opt.enabled and Showcase() then
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

-- Update stops when there is no target, but the aura containers can only be set up out of
-- combat: left to the first target, a first target in combat would get the wrong layout.
local function ConfigureWithoutTarget()
	local plate = M.frame
	if plate and plate.debuffBox and Opt().enabled and not UnitExists(U()) then
		UpdateAuras(plate)
	end
end

function M.SetPreview(on)
	if InCombatLockdown() then
		ns.Print("cannot preview in combat")
		return
	end
	M.preview = on and true or nil
	preview.rank, preview.clock, preview.health = 1, 0, 1
	M.Layout()
	M.Update(true)
	ConfigureWithoutTarget()
end

function M.ApplySettings()
	M.Layout()
	M.Update()
	ConfigureWithoutTarget()
end

function M.ResetPosition()
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
	portrait.disc = disc
	portrait.d3 = { frame = cell, model = MODEL, disc = hole + 2 * k }
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

local function SizePortraitSmall(portrait, frame, model, disc)
	portrait:SetSize(frame, frame)
	portrait.back:SetSize(model, model)
	portrait.model:SetSize(model, model)
	portrait.disc:SetSize(disc, disc)
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
	art.extra, art.extraW, art.widthScale = 0, 0, 1 -- what its Width and Height options add
	-- The frame box: its top sits so the bar's middle is on the art's middle line.
	local box = CreateFrame("Frame", nil, art)
	box:SetSize(piece[3] * k, piece[4] * k)
	box:SetFrameLevel(art:GetFrameLevel() + 5)
	-- With its portrait (Target > Target of target portrait) the ring leads and the frame
	-- follows it; without, the frame starts where the ring did and the art is just the bar.
	function art.SetPortraitShown(show)
		show = show and true or false
		art.portraitShown = show
		if art.styled then return end -- the rendered frame has its own socket
		local frameLeft = show and (2 * reach - RING_OVERLAP) * k or 0
		art.width = frameLeft + piece[3] * k + art.extraW
		local barHeight = piece[4] * k + art.extra
		art.height = show and math.max(2 * reach * k, barHeight) or barHeight
		art:SetSize(art.width, art.height)
		box:ClearAllPoints()
		box:SetPoint("TOPLEFT", art, "LEFT", frameLeft, (bar[2] + bar[4] / 2) * k + art.extra / 2)
		if art.Portrait then art.Portrait:SetShown(show) end
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
	-- On its own frame, over the box: the rendered styles hide the box but keep the name.
	local nameLayer = CreateFrame("Frame", nil, art)
	nameLayer:SetAllPoints()
	nameLayer:SetFrameLevel(box:GetFrameLevel() + 1)
	art.Name = nameLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	AddTextGlow(art.Name, art)
	art.Name:SetPoint("CENTER", health, "CENTER", 0, 0)
	art.Name:SetWidth(bar[3] * k - 6)
	art.Name:SetWordWrap(false)
	art.Name:SetShadowColor(0, 0, 0, 0.85)
	art.Name:SetShadowOffset(1, -1)
	art.Portrait = MakeRing(art, k)
	art.Portrait:SetPoint("CENTER", art, "LEFT", reach * k, 0)
	art.Portrait:SetShown(art.portraitShown)
	-- The rendered styles' small frame: a socket with its own bar, in place of D3's. Its Width
	-- and Height stretch it in slices (ns.Art.TARGET_TOT_STYLE, ns.Art.DrawTargetStyle).
	local styleArt = CreateFrame("Frame", nil, art)
	styleArt:SetAllPoints()
	styleArt:SetFrameLevel(art:GetFrameLevel())
	styleArt:Hide()
	art.styledKey = false
	function art.SetStyled(on, widthScale, heightScale)
		local tot = on and ns.Art.TargetStyleSized(ns.Art.TARGET_TOT_STYLE, widthScale, heightScale)
		local key = tot and tot.key or false
		if art.styledKey == key then return end
		art.styledKey = key
		art.styled = on
		box:SetShown(not on)
		well:SetShown(not on)
		styleArt:SetShown(on)
		health:ClearAllPoints()
		art.Name:ClearAllPoints()
		local portrait = art.Portrait
		portrait:ClearAllPoints()
		if on then
			ns.Art.DrawTargetStyle(styleArt, tot, "normal")
			local b = tot.bar
			art.width, art.height = tot.size[1], tot.size[2]
			art:SetSize(art.width, art.height)
			health:SetPoint("TOPLEFT", art, "TOPLEFT", b[1], -b[2])
			health:SetSize(b[3] - b[1], b[4] - b[2])
			art.Name:SetPoint("BOTTOMLEFT", health, "TOPLEFT", 1, 0)
			art.Name:SetWidth(b[3] - b[1])
			art.Name:SetJustifyH("LEFT")
			portrait.ring:Hide()
			SizePortraitSmall(portrait, 30, 22, 23)
			portrait:SetPoint("CENTER", art, "TOPLEFT", tot.portrait.cx, -tot.portrait.cy)
			portrait:Show()
		else
			health:SetPoint("TOPLEFT", box, "TOPLEFT", bar[1] * k, -bar[2] * k)
			health:SetSize(bar[3] * k + art.extraW, bar[4] * k + art.extra)
			art.Name:SetPoint("CENTER", health, "CENTER", 0, 0)
			art.Name:SetWidth(bar[3] * k + art.extraW - 6)
			art.Name:SetJustifyH("CENTER")
			portrait.ring:Show()
			local d3 = portrait.d3
			SizePortraitSmall(portrait, d3.frame, d3.model, d3.disc)
			portrait:SetPoint("CENTER", art, "LEFT", reach * k, 0)
			art.SetPortraitShown(art.portraitShown)
		end
	end
	art.styled = false
	-- The Width and Height options: the frame stretches between its ornaments and along the band
	-- level with the bar, as the target's does.
	function art.Resize(widthScale, extra)
		if art.widthScale == widthScale and art.extra == extra then return end
		art.widthScale, art.extra = widthScale, extra
		art.extraW = ns.Art.DrawSliced(box, "normal", piece[3] * k * widthScale, k, extra)
		health:SetSize(bar[3] * k + art.extraW, bar[4] * k + extra)
		art.Name:SetWidth(bar[3] * k + art.extraW - 6)
		art.SetPortraitShown(art.portraitShown)
	end
	return art
end

function M.Init()
	local plate = CreateFrame("Button", CFG.prefix .. "Plate", UIParent, "SecureUnitButtonTemplate")
	plate:SetSize(ns.Art.UNIT.boss[3], PLATE_H)
	-- In the console's strata and above its stack, so that moved down near the console it still
	-- gets the mouse (its aura tooltips) and draws over it. Its pieces take their levels from
	-- the plate's, so this comes first. The bag window is top-level and still rises over it.
	plate:SetFrameStrata("MEDIUM")
	plate:SetFrameLevel((ns.Cluster and ns.Cluster:GetFrameLevel() or 1) + ns.LEVEL.target)
	plate:SetAttribute("unit", UNIT)
	plate:SetAttribute("*type1", "target")
	plate:SetAttribute("*type2", "togglemenu")
	plate:RegisterForClicks("AnyUp")
	plate:EnableMouse(true)
	plate:SetScript("OnEnter", function(self) ShowUnitTooltip(self, UNIT, self.Hover) end)
	plate:SetScript("OnLeave", function(self) HideUnitTooltip(self.Hover) end)
	-- The frame keeps Update and Layout: it lives in a field of the module table.
	M.frame = plate

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
	AddTextGlow(plate.Percent, plate)
	AddTextGlow(plate.Level, plate)
	AddTextGlow(plate.Name, plate)
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
	local tot = CreateFrame("Button", CFG.prefix .. "Target", plate, "SecureUnitButtonTemplate")
	tot:SetSize(10, 22) -- placed by Layout

	tot:SetFrameStrata("MEDIUM")
	tot:EnableMouse(true)
	tot:SetAttribute("unit", UNIT .. "target")
	tot:SetAttribute("*type1", "target")
	tot:SetAttribute("*type2", "togglemenu")
	tot:RegisterForClicks("AnyUp")
	-- The drawn bar is a plain child (so it shows and hides with the button) that follows the
	-- rank's frame end; the button is a fixed click area over everywhere it can be, since a
	-- secure button can't move in combat.
	plate.ToTArt = MakeToTArt(plate, tot)
	tot:SetScript("OnEnter", function(self) ShowUnitTooltip(self, UNIT .. "target", plate.ToTArt.Hover) end)
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

	-- A rendered style's frame: under the bars, so it's the groove they sit in.
	local styleArt = CreateFrame("Frame", nil, plate)
	styleArt:SetFrameLevel(plate:GetFrameLevel())
	styleArt:SetAllPoints()
	styleArt.tex = styleArt:CreateTexture(nil, "ARTWORK")
	styleArt:Hide()
	plate.StyleArt = styleArt
	-- Class icon, faction emblem and raid marker, above the portrait's frame.
	local marks = CreateFrame("Frame", nil, plate)
	marks:SetAllPoints()
	marks:SetFrameLevel(plate:GetFrameLevel() + 9)
	marks.class = marks:CreateTexture(nil, "OVERLAY")
	marks.class:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
	marks.faction = marks:CreateTexture(nil, "OVERLAY")
	marks.raid = marks:CreateTexture(nil, "OVERLAY", nil, 1)
	marks.raid:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
	marks.class:Hide()
	marks.faction:Hide()
	marks.raid:Hide()
	plate.Marks = marks
	-- Its resource bar, and the stud the level sits on.
	local power = CreateFrame("StatusBar", nil, plate)
	power:SetFrameLevel(plate:GetFrameLevel() + 3) -- over the health fill, for D3's strip
	power:SetStatusBarTexture(ns.Art.Path("unitFillWhite") or "Interface\\Buttons\\WHITE8X8")
	power:SetMinMaxValues(0, 1)
	-- D3's strip: a dark track, a pixel taller so it parts the strip from the health above.
	power.track = power:CreateTexture(nil, "BACKGROUND")
	power.track:SetPoint("TOPLEFT", power, "TOPLEFT", 0, 1)
	power.track:SetPoint("BOTTOMRIGHT", power, "BOTTOMRIGHT", 0, 0)
	power.track:SetColorTexture(0.02, 0.02, 0.03, 1)
	power:Hide()
	plate.Power = power
	local stud = CreateFrame("Frame", nil, plate)
	stud:SetFrameLevel(plate:GetFrameLevel() + 8)
	stud:SetSize(24, 24)
	stud.tex = stud:CreateTexture(nil, "ARTWORK")
	stud.tex:SetAllPoints()
	stud.text = stud:CreateFontString(nil, "OVERLAY")
	stud.text:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
	stud:Hide()
	plate.StyleBadge = stud

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
	cast.art = castArt
	-- The rendered styles' rail, under the bar (the bar is a child frame).
	cast.rail = cast:CreateTexture(nil, "ARTWORK")
	cast.rail:SetPoint("TOPLEFT", cast, "TOPLEFT", -10, 4)
	cast.rail:SetSize(256, 26)
	cast.rail:Hide()
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
	SetPiece(plate, "normal", "normal")

	-- Aura rows hang off thin lines placed by PlaceRef; the cast bar goes under them.
	plate.auraRef = CreateFrame("Frame", nil, plate)
	plate.auraRef:SetSize(1, 1)
	plate.buffRef = CreateFrame("Frame", nil, plate)
	plate.buffRef:SetSize(1, 1)
	plate.debuffs, plate.buffs = {}, {}
	for i = 1, MAX_AURAS do
		plate.debuffs[i] = MakeAura(plate, CFG.prefix .. "Debuff" .. i)
		plate.buffs[i] = MakeAura(plate, CFG.prefix .. "Buff" .. i)
	end
	-- Where the client has aura containers they replace these icons (see MakeBoxes).
	MakeBoxes(plate)

	-- On UIParent, not the plate: the plate hides by its unit watch, and the mover must still
	-- show to be dragged. In DIALOG strata, over the plate (which takes the mouse) and its art.
	M.mover = ns.MakeMover(plate, CFG.label, Opt, "Reset its position in /sanctuary > " .. CFG.label .. ".", UIParent)

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
	plate:HookScript("OnShow", function() M.Update(true) end)

	local events = CreateFrame("Frame", nil, UIParent)
	pcall(events.RegisterEvent, events, CFG.changed) -- a client without a focus has no such event
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:RegisterEvent("PLAYER_REGEN_ENABLED")
	events:RegisterEvent("RAID_TARGET_UPDATE")
	events:RegisterEvent("UI_SCALE_CHANGED")
	events:RegisterEvent("DISPLAY_SIZE_CHANGED")
	events:RegisterUnitEvent("UNIT_HEALTH", UNIT)
	events:RegisterUnitEvent("UNIT_MAXHEALTH", UNIT)
	events:RegisterUnitEvent("UNIT_POWER_UPDATE", UNIT)
	events:RegisterUnitEvent("UNIT_MAXPOWER", UNIT)
	events:RegisterUnitEvent("UNIT_DISPLAYPOWER", UNIT)
	events:RegisterUnitEvent("UNIT_HEAL_PREDICTION", UNIT)
	events:RegisterUnitEvent("UNIT_ABSORB_AMOUNT_CHANGED", UNIT)
	events:RegisterUnitEvent("UNIT_AURA", UNIT)
	events:RegisterUnitEvent("UNIT_NAME_UPDATE", UNIT)
	events:RegisterUnitEvent("UNIT_FACTION", UNIT)
	events:RegisterUnitEvent("UNIT_LEVEL", UNIT)
	events:RegisterUnitEvent("UNIT_MODEL_CHANGED", UNIT)
	events:RegisterUnitEvent("UNIT_PORTRAIT_UPDATE", UNIT)
	pcall(events.RegisterUnitEvent, events, "UNIT_CLASSIFICATION_CHANGED", UNIT)
	events:RegisterUnitEvent("UNIT_TARGET", UNIT)
	events:RegisterUnitEvent("UNIT_SPELLCAST_START", UNIT)
	events:RegisterUnitEvent("UNIT_SPELLCAST_STOP", UNIT)
	events:RegisterUnitEvent("UNIT_SPELLCAST_DELAYED", UNIT)
	events:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", UNIT)
	events:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", UNIT)
	events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", UNIT)
	events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", UNIT)
	events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", UNIT)
	pcall(events.RegisterUnitEvent, events, "UNIT_SPELLCAST_EMPOWER_START", UNIT)
	pcall(events.RegisterUnitEvent, events, "UNIT_SPELLCAST_EMPOWER_UPDATE", UNIT)
	pcall(events.RegisterUnitEvent, events, "UNIT_SPELLCAST_EMPOWER_STOP", UNIT)
	pcall(events.RegisterUnitEvent, events, "UNIT_SPELLCAST_INTERRUPTIBLE", UNIT)
	pcall(events.RegisterUnitEvent, events, "UNIT_SPELLCAST_NOT_INTERRUPTIBLE", UNIT)
	events:SetScript("OnEvent", function(_, event)
		if event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
			M.Layout()
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
		elseif event == "RAID_TARGET_UPDATE" then
			if UnitExists(U()) then UpdateMarks(plate) end
		elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER" then
			UpdatePower(plate)
		elseif event == "UNIT_HEAL_PREDICTION" or event == "UNIT_ABSORB_AMOUNT_CHANGED" then
			SetPrediction(plate, UnitHealth(U()), UnitHealthMax(U()))
		elseif event == "UNIT_AURA" then
			-- The containers watch auras themselves.
			if not plate.debuffBox then UpdateAuraIcons(plate) end
		elseif event == "UNIT_MODEL_CHANGED" or event == "UNIT_PORTRAIT_UPDATE" then
			UpdatePortrait(plate, true)
		elseif event == "UNIT_TARGET" then
			UpdateToT(plate)
		elseif event == "PLAYER_REGEN_ENABLED" then
			if M.pending then M.Layout() end
			-- The rank changed in combat: fit the click area to its frame now.
			if plate.hitStale then
				plate.rank = nil
				M.Update()
			end
			-- Aura settings changed in combat wait for now.
			if plate.debuffBox then UpdateAuras(plate) end
		else
			M.Update(event == CFG.changed or event == "PLAYER_ENTERING_WORLD")
			if event == "PLAYER_ENTERING_WORLD" then ConfigureWithoutTarget() end
		end
	end)

	plate:Hide()
	M.Layout()
end
end -- Build

ns.TargetPlate = ns.TargetPlate or {}
Build(ns.TargetPlate, {
	unit = "target", key = "target", prefix = "SanctuaryUITarget", changed = "PLAYER_TARGET_CHANGED",
	label = "Target",
	place = function(plate, room) plate:SetPoint("TOP", UIParent, "TOP", 0, -12 - room) end,
})

-- The focus: left of the target frame and lower, out of the way of it and of the portraits.
ns.FocusPlate = ns.FocusPlate or {}
Build(ns.FocusPlate, {
	unit = "focus", key = "focus", prefix = "SanctuaryUIFocus", changed = "PLAYER_FOCUS_CHANGED",
	label = "Focus",
	place = function(plate) plate:SetPoint("TOP", UIParent, "TOP", -480, -260) end,
})
