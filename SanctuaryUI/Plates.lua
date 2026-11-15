SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.Plates = ns.Plates or {}
local P = ns.Plates

-- Enemy nameplates in D3's look (Options > Unit frames > Nameplates). Mockups: mockups/plates-a-pull.png
-- (look A, framed: D3's silver frame for monsters, the gold frame for elites, the scroll banner for
-- bosses) and plates-b-thin.png (look B, D3's bare bar). Friendly plates stay Blizzard's: in
-- instances the game forbids touching them anyway.
--
-- Built the way Plater's build for this client does it (see the 2026-11-15 notes in memory):
-- our frame is a child of the game's plate, the game's own UnitFrame is hidden from a Show hook
-- (never by writing to it), and every unit value that can be secret in combat goes straight into
-- a widget: health into StatusBars, the percent through a curve, the cast through a duration
-- object, "is it casting at me" through SetAlphaFromBoolean. Nothing here compares a secret.
--
-- Plates are pooled by the game; ours ride along, keyed by the game's plate frame in `objs`.

local TRAIL_HOLD = 0.45 -- the pale chunk of lost health holds this long, then drains
local INTERRUPT_HOLD = 0.9
local GOLD = { 0.98, 0.84, 0.48 }
local NAME_COLORS = {
	normal = { 0.92, 0.9, 0.86 },
	elite = { 0.45, 0.58, 1 },
	rare = { 1, 0.94, 0.31 },
	boss = { 1, 0.6, 0.18 },
}
local FRIEND_NAME = { 0.96, 0.88, 0.64 } -- townsfolk: D3's soft gold
local FRIEND_FILL = { 0.32, 0.78, 0.3 }
local FILL = {
	neutral = { 0.95, 0.78, 0.2 },
	tapped = { 0.55, 0.55, 0.55 },
	hostile = { 0.86, 0.16, 0.1 },
}
local THREAT = {
	aggro = { 1, 0.15, 0.05 }, -- you have it (not tanking)
	warn = { 1, 0.55, 0.05 }, -- about to pull, or (as the tank) loose on someone else
}
local ROUND_MASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"

local Secret = ns.Secret
local function Plain(v) return v ~= nil and not Secret(v) end

local function Opt() return ns.DB().plates end

local objs = {} -- game plate frame -> our plate
local byUnit = {} -- "nameplateN" -> our plate
local hooked = {} -- the game's UnitFrames we hook
local active = false
local preview = { plates = {} }
P.objs, P.byUnit = objs, byUnit

---------------------------------------------------------------------------
-- Who else draws nameplates

local OTHER_PLATES = { "Plater", "Kui_Nameplates", "TidyPlates_ThreatPlates", "NeatPlates" }

function P.Conflict()
	local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
	if not loaded then return nil end
	for _, name in ipairs(OTHER_PLATES) do
		local ok, on = pcall(loaded, name)
		if ok and on then return name end
	end
	-- ElvUI only with its own nameplates on.
	local ok, on = pcall(loaded, "ElvUI")
	if ok and on and type(ElvUI) == "table" then
		local E = ElvUI[1]
		local ok2, enabled = pcall(function() return E.private.nameplates.enable end)
		if ok2 and enabled then return "ElvUI nameplates" end
	end
	return nil
end

function P.Enabled()
	return Opt().enabled ~= false and not P.Conflict()
end

---------------------------------------------------------------------------
-- Curves (the client evaluates them on secret health)

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

-- 1 below the execute line, 0 above it.
local function ExecuteCurve()
	local at = (Opt().executeAt or 20) / 100
	return Curve("execute" .. at, { { 0, 1 }, { at, 1 }, { at + 0.0005, 0 }, { 1, 0 } })
end

local function Ease()
	return Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
end

local function SetBar(bar, value, ease)
	if not (ease and pcall(bar.SetValue, bar, value, ease)) then pcall(bar.SetValue, bar, value) end
end

local function Bool(region, value, onTrue, onFalse)
	if region.SetAlphaFromBoolean and pcall(region.SetAlphaFromBoolean, region, value, onTrue, onFalse) then return end
	if Secret(value) then
		region:SetAlpha(onFalse)
	else
		region:SetAlpha(value and onTrue or onFalse)
	end
end

---------------------------------------------------------------------------
-- Building a plate

-- Outline names to the client's flags; with none, a drop shadow keeps text readable.
local OUTLINES = { outline = "OUTLINE", thick = "THICKOUTLINE", none = "" }
local function Style(fs, role, size, outline, choice)
	ns.Fonts.Set(fs, role, size, OUTLINES[outline or "outline"] or "OUTLINE", choice)
	if outline == "none" then
		fs:SetShadowColor(0, 0, 0, 1)
		fs:SetShadowOffset(1, -1)
	else
		fs:SetShadowOffset(0, 0)
	end
end

local function Fonts(p)
	local o = Opt()
	if p.friend then
		-- Friendly plates have their own (Options > Nameplates > Friendly).
		Style(p.name, "title", o.friendlyNameSize or 10, o.friendlyOutline, o.friendlyFont)
		Style(p.guild, "body", o.friendlyGuildSize or 8, o.friendlyOutline, o.friendlyGuildFont)
		return
	end
	local nameSize = o.nameSize or 10
	local textSize = o.textSize or 9
	Style(p.name, "title", nameSize, o.nameOutline, o.nameFont)
	Style(p.level, "body", textSize, o.textOutline, o.textFont)
	Style(p.pct, "body", textSize, o.textOutline, o.textFont)
	Style(p.cast.text, "body", textSize, o.textOutline, o.textFont)
	Style(p.cast.who, "title", textSize - 1, o.textOutline, o.nameFont)
	Style(p.cast.you, "title", textSize - 1, o.textOutline, o.nameFont)
	Style(p.guild, "body", textSize - 1, o.textOutline, o.textFont)
end

local function Glow(parent, layer, color)
	local t = parent:CreateTexture(nil, layer or "BACKGROUND")
	t:SetTexture(ns.Art.Path("mote") or "Interface\\Buttons\\WHITE8X8")
	t:SetBlendMode("ADD")
	if color then t:SetVertexColor(color[1], color[2], color[3]) end
	t:SetAlpha(0)
	return t
end

local function Diamond(parent, size)
	local d = parent:CreateTexture(nil, "OVERLAY", nil, 2)
	d:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
	d:SetSize(size, size)
	if d.SetRotation then pcall(d.SetRotation, d, math.pi / 4) end
	local edge = parent:CreateTexture(nil, "OVERLAY", nil, 1)
	edge:SetColorTexture(0.2, 0.12, 0.03, 1)
	edge:SetSize(size + 2, size + 2)
	if edge.SetRotation then pcall(edge.SetRotation, edge, math.pi / 4) end
	edge:SetPoint("CENTER", d, "CENTER")
	d.edge = edge
	return d
end

local function MakeBar(parent, level, art)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetStatusBarTexture(ns.Art.Path(art) or "Interface\\Buttons\\WHITE8X8")
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(1)
	bar:SetFrameLevel(parent:GetFrameLevel() + level)
	return bar
end

local function NewPlate(parent)
	local p = {}
	local root = CreateFrame("Frame", nil, parent)
	root:SetSize(1, 1)
	root:EnableMouse(false)
	p.root = root

	-- Under the bar: threat and target light, the dark slot.
	p.threat = Glow(root, "BACKGROUND")
	p.targetGlow = Glow(root, "BACKGROUND", GOLD)
	p.slot = root:CreateTexture(nil, "BACKGROUND", nil, 1)
	p.slot:SetColorTexture(0.03, 0.02, 0.02, 0.92)
	p.thinEdge = root:CreateTexture(nil, "BACKGROUND", nil, 0)
	p.thinEdge:SetColorTexture(0.33, 0.25, 0.17, 1)

	-- Bars: the pale trail, the fill, the molten execute fill over it.
	p.trail = MakeBar(root, 1, "xpWhite")
	p.trail:SetStatusBarColor(1, 0.93, 0.8, 0.85)
	p.health = MakeBar(root, 2, "unitFill")
	p.execute = MakeBar(root, 3, "xpWhite")
	p.execute:SetStatusBarColor(1, 0.45, 0.12, 1)
	p.execute:SetAlpha(0)

	-- Over the bars: the hit flash, the frame art, then texts and marks.
	local over = CreateFrame("Frame", nil, root)
	over:SetFrameLevel(root:GetFrameLevel() + 5)
	over:SetAllPoints(root)
	p.over = over
	p.flash = over:CreateTexture(nil, "ARTWORK", nil, -1)
	p.flash:SetColorTexture(1, 0.95, 0.85, 1)
	p.flash:SetBlendMode("ADD")
	p.flash:SetAlpha(0)
	p.art = CreateFrame("Frame", nil, over)
	p.art:SetFrameLevel(over:GetFrameLevel())
	p.tick = over:CreateTexture(nil, "OVERLAY")
	p.tick:SetColorTexture(1, 0.87, 0.63, 0.55)
	p.tick:SetWidth(1)

	p.name = over:CreateFontString(nil, "OVERLAY")
	p.name:SetShadowOffset(0, 0)
	p.level = over:CreateFontString(nil, "OVERLAY")
	p.level:SetShadowOffset(0, 0)
	p.guild = over:CreateFontString(nil, "OVERLAY")
	p.guild:SetShadowOffset(0, 0)
	p.guild:SetTextColor(0.78, 0.74, 0.66)
	p.guild:SetJustifyH("CENTER") -- title over level and faction, both centred under the name
	p.pct = over:CreateFontString(nil, "OVERLAY")
	p.pct:SetShadowOffset(0, 0)
	p.pct:SetTextColor(0.95, 0.92, 0.86)
	p.raid = over:CreateTexture(nil, "OVERLAY")
	p.raid:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
	p.raid:Hide()
	p.soft = over:CreateTexture(nil, "OVERLAY", nil, 2) -- the soft-target icon (P.UpdateSoftTargets)
	p.soft:Hide()
	p.quest = over:CreateTexture(nil, "OVERLAY")
	p.quest:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
	p.quest:Hide()
	p.left = Diamond(over, 5)
	p.right = Diamond(over, 5)

	-- The cast bar under the frame.
	local cast = CreateFrame("Frame", nil, root)
	cast:SetFrameLevel(root:GetFrameLevel() + 6)
	cast:Hide()
	cast.bg = cast:CreateTexture(nil, "BACKGROUND")
	cast.bg:SetColorTexture(0.03, 0.02, 0.02, 0.92)
	cast.bar = MakeBar(cast, 1, "xpWhite")
	cast.bar:SetStatusBarColor(1, 0.6, 0.16, 1)
	cast.grey = MakeBar(cast, 2, "xpWhite") -- the same timer in grey, shown when it can't be interrupted
	cast.grey:SetStatusBarColor(0.6, 0.6, 0.6, 1)
	cast.grey:SetAlpha(0)
	cast.art = CreateFrame("Frame", nil, cast)
	cast.art:SetFrameLevel(cast:GetFrameLevel() + 3)
	cast.spark = Glow(cast.art, "OVERLAY", { 1, 0.9, 0.65 })
	cast.spark:SetPoint("CENTER", cast.bar:GetStatusBarTexture(), "RIGHT")
	cast.icon = cast.art:CreateTexture(nil, "OVERLAY")
	cast.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	cast.lock = cast.art:CreateTexture(nil, "OVERLAY")
	cast.lock:SetTexture("Interface\\PetBattles\\PetBattle-LockIcon")
	cast.lock:SetAlpha(0)
	cast.text = cast.art:CreateFontString(nil, "OVERLAY")
	cast.text:SetShadowOffset(0, 0)
	cast.text:SetTextColor(0.94, 0.9, 0.82)
	cast.who = cast.art:CreateFontString(nil, "OVERLAY")
	cast.who:SetShadowOffset(0, 0)
	cast.who:SetTextColor(0.85, 0.8, 0.7)
	cast.you = cast.art:CreateFontString(nil, "OVERLAY")
	cast.you:SetShadowOffset(0, 0)
	cast.you:SetTextColor(1, 0.27, 0.2)
	cast.you:SetAlpha(0)
	p.cast = cast

	-- A fade for the hit flash.
	local flashAnim = p.flash:CreateAnimationGroup()
	local a = flashAnim:CreateAnimation("Alpha")
	a:SetFromAlpha(0.55)
	a:SetToAlpha(0)
	a:SetDuration(0.22)
	flashAnim:SetScript("OnFinished", function() p.flash:SetAlpha(0) end)
	p.flashAnim = flashAnim

	Fonts(p)
	cast.you:SetText("» " .. (YOU or "You"):upper()) -- after Fonts: the game refuses text before a font
	return p
end

---------------------------------------------------------------------------
-- Layout: the frame for a rank in a look, and everything placed around its bar

local function Rank(p)
	return p.rank or "normal"
end

-- A friend (outside instances): the name in D3's font, a guild line under it, and a thin health
-- strip between them that shows only while they're hurt or fighting.
local function FriendLayout(p)
	local o = Opt()
	local root = p.root
	local width = (o.width or 130) * 0.9
	local size = o.nameSize or 10
	root:SetSize(width, size + 10)
	p.art:Hide()
	p.thinEdge:Hide()
	p.tick:Hide()
	p.trail:Hide()
	p.execute:Hide()
	p.flash:SetAlpha(0)
	p.threat:SetAlpha(0)
	p.pct:SetText("")
	p.level:SetText("")
	p.quest:Hide()
	p.cast:Hide()
	p.name:ClearAllPoints()
	p.name:SetPoint("CENTER", root, "CENTER", 0, 3)
	local sw, sh = width * 0.55, math.max(2, math.floor((o.barHeight or 9) * 0.33 + 0.5))
	for _, region in ipairs({ p.slot, p.health }) do
		region:ClearAllPoints()
		region:SetPoint("TOP", p.name, "BOTTOM", 0, -2)
		region:SetSize(sw, sh)
	end
	p.guild:ClearAllPoints()
	p.guild:SetPoint("TOP", p.name, "BOTTOM", 0, -(sh + 4))
	p.guild:Show()
	-- (Sizes are worked out, never read back: the game won't let addons measure nameplates.)
	p.bar = { (width - sw) / 2, (size + 10) / 2 - 3, sw, sh }
	p.targetGlow:ClearAllPoints()
	p.targetGlow:SetPoint("TOPLEFT", p.name, "TOPLEFT", -size * 1.5, size)
	p.targetGlow:SetPoint("BOTTOMRIGHT", p.name, "BOTTOMRIGHT", size * 1.5, -size)
	p.left:ClearAllPoints()
	p.left:SetPoint("RIGHT", p.name, "LEFT", -4, 0)
	p.right:ClearAllPoints()
	p.right:SetPoint("LEFT", p.name, "RIGHT", 4, 0)
	p.raid:SetSize(size + 6, size + 6)
	p.raid:ClearAllPoints()
	p.raid:SetPoint("BOTTOM", p.name, "TOP", 0, 2)
	Fonts(p)
end

local function Layout(p)
	if p.friend then return FriendLayout(p) end
	p.art:Show()
	p.trail:Show()
	p.execute:Show()
	p.guild:Hide()
	p.slot:SetAlpha(1)
	p.health:SetAlpha(1)
	local o = Opt()
	local look = o.look or "framed"
	local rank = Rank(p)
	local barH = o.barHeight or 9
	local width = o.width or 130
	local root, art = p.root, p.art
	local bx, by, bw, bh -- the bar inside root, from root's top left
	local rootW -- the whole frame's width

	if look == "thin" then
		for _, t in ipairs(art.slices or {}) do t:Hide() end
		bw, bh = width * 0.82, barH
		rootW = bw + 3
		root:SetSize(rootW, bh + 3)
		bx, by = 1.5, 1.5
		p.thinEdge:ClearAllPoints()
		p.thinEdge:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
		p.thinEdge:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
		-- Rank still shows: dark iron for monsters, gold for elites and rares, molten gold for bosses.
		local edge = (rank == "boss" and { 0.95, 0.6, 0.15 }) or ((rank == "elite" or rank == "rare") and { 0.78, 0.6, 0.25 }) or { 0.3, 0.24, 0.18 }
		p.thinEdge:SetColorTexture(edge[1], edge[2], edge[3], 1)
		p.thinEdge:Show()
		p.tick:Hide()
	else
		p.thinEdge:Hide()
		local piece = rank == "boss" and "boss" or (rank == "elite" or rank == "rare") and "elite" or "normal"
		local r = ns.Art.UNIT[piece]
		local k = barH / r.bar[4]
		local scaleW = piece == "boss" and 1.35 or piece == "elite" and 1.12 or 1
		art:ClearAllPoints()
		art:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
		local extra = ns.Art.DrawSliced(art, piece, width * scaleW, k)
		rootW = r[3] * k + extra
		root:SetSize(rootW, r[4] * k) -- what DrawSliced drew; never read back from a plate
		bx, by = r.bar[1] * k, r.bar[2] * k
		bw, bh = r.bar[3] * k + extra, r.bar[4] * k
		p.tick:SetShown(o.execute ~= false and o.executeTick == true and rank ~= "boss")
	end
	p.bar = { bx, by, bw, bh }
	for _, region in ipairs({ p.slot, p.trail, p.health, p.execute, p.flash }) do
		region:ClearAllPoints()
		region:SetPoint("TOPLEFT", root, "TOPLEFT", bx, -by)
		region:SetSize(bw, bh)
	end
	p.tick:ClearAllPoints()
	p.tick:SetPoint("TOPLEFT", root, "TOPLEFT", bx + bw * (o.executeAt or 20) / 100, -by)
	p.tick:SetHeight(bh)

	-- Light: the threat glow hugs the bar, the target's spreads wider.
	p.threat:ClearAllPoints()
	p.threat:SetPoint("TOPLEFT", root, "TOPLEFT", bx - bh * 1.6, -by + bh * 1.4)
	p.threat:SetPoint("BOTTOMRIGHT", root, "TOPLEFT", bx + bw + bh * 1.6, -by - bh * 2.4)
	p.targetGlow:ClearAllPoints()
	p.targetGlow:SetPoint("TOPLEFT", root, "TOPLEFT", bx - bh * 3, -by + bh * 2.4)
	p.targetGlow:SetPoint("BOTTOMRIGHT", root, "TOPLEFT", bx + bw + bh * 3, -by - bh * 3.4)
	local mid = -(by + bh / 2)
	p.left:ClearAllPoints()
	p.left:SetPoint("CENTER", root, "TOPLEFT", -3, mid)
	p.right:ClearAllPoints()
	p.right:SetPoint("CENTER", root, "TOPRIGHT", 3, mid)

	-- Texts: the name over the frame, level and marks beside it.
	local nameSize = o.nameSize or 10
	p.name:ClearAllPoints()
	p.level:ClearAllPoints()
	if o.namePos == "inside" then
		-- On the bar: the level at its left, then the name in what's left, cut short with "..."
		-- before the health percent.
		local levelW = o.showLevel ~= false and (o.textSize or 9) * 1.6 or 0
		p.level:SetPoint("LEFT", root, "TOPLEFT", bx + 3, mid)
		p.name:SetPoint("LEFT", root, "TOPLEFT", bx + 3 + levelW + (levelW > 0 and 3 or 0), mid)
		p.nameRoom = bw - 8 - levelW
		p.nameFitW = nil
		P.FitName(p)
		p.name:SetJustifyH("LEFT")
		p.name:SetWordWrap(false)
	else
		-- Over the frame, laid out against it (the game won't let an addon measure the name): the
		-- level at the row's left end, the quest mark at its right end, the name centred between
		-- them and cut short with "..." when it's longer than the room.
		local levelW = o.showLevel ~= false and (o.textSize or 9) * 1.8 or 0
		local questW = o.quest ~= false and nameSize + 6 or 0
		local edge = math.max(levelW, questW)
		p.name:SetPoint("BOTTOM", root, "TOP", 0, 1)
		p.nameRoom = nil
		local row = rootW * 1.35 -- the name's row may reach a little past the frame's ends
		p.nameFitW = math.max(20, row - 2 * edge)
		p.name:SetWidth(p.nameFitW)
		p.name:SetWordWrap(false)
		p.name:SetJustifyH("CENTER")
		p.level:SetPoint("LEFT", p.name, "LEFT", -edge, 0)
	end
	p.raid:SetSize(nameSize + 6, nameSize + 6)
	p.raid:ClearAllPoints()
	if o.namePos == "inside" then
		p.raid:SetPoint("BOTTOM", root, "TOP", 0, 1)
	else
		p.raid:SetPoint("RIGHT", p.level, "LEFT", -3, 0)
	end
	p.quest:SetSize(nameSize + 4, nameSize + 4)
	p.quest:ClearAllPoints()
	if o.namePos == "inside" then
		p.quest:SetPoint("BOTTOMRIGHT", root, "TOPRIGHT", 0, 1)
	else
		p.quest:SetPoint("RIGHT", p.name, "RIGHT", math.max(o.showLevel ~= false and (o.textSize or 9) * 1.8 or 0, nameSize + 6), 0)
	end
	p.pct:ClearAllPoints()
	if o.healthTextPos == "center" and o.namePos ~= "inside" then
		p.pct:SetPoint("CENTER", root, "TOPLEFT", bx + bw / 2, mid)
	else
		p.pct:SetPoint("RIGHT", root, "TOPLEFT", bx + bw - 3, mid)
	end

	-- The cast bar: D3's thin progress bar, nine tenths of the health bar's width.
	local cast = p.cast
	local cw = bw * 0.92
	local cr = ns.Art.UNIT.cast
	local ck = math.max(0.4, barH * 0.75 * (o.castScale or 1) / cr.bar[4])
	local castH
	cast:ClearAllPoints()
	cast:SetPoint("TOP", root, "TOPLEFT", bx + bw / 2, -(by + bh + (look == "thin" and 4 or bh * 0.45)))
	if look == "thin" then
		for _, t in ipairs(cast.art.slices or {}) do t:Hide() end
		castH = barH * 0.7 * (o.castScale or 1)
		cast:SetSize(cw, castH)
		cast.bg:SetAllPoints(cast)
		for _, b in ipairs({ cast.bar, cast.grey }) do
			b:ClearAllPoints()
			b:SetAllPoints(cast)
		end
	else
		cast.art:ClearAllPoints()
		cast.art:SetPoint("TOPLEFT", cast, "TOPLEFT", 0, 0)
		local extra = ns.Art.DrawSliced(cast.art, "cast", cw, ck)
		cast:SetSize(cr[3] * ck + extra, cr[4] * ck)
		castH = cr[4] * ck
		for _, region in ipairs({ cast.bg, cast.bar, cast.grey }) do
			region:ClearAllPoints()
			region:SetPoint("TOPLEFT", cast, "TOPLEFT", cr.bar[1] * ck, -cr.bar[2] * ck)
			region:SetSize(cr.bar[3] * ck + extra, cr.bar[4] * ck)
		end
	end
	cast.spark:SetSize(barH * 1.6, barH * 1.6)
	cast.lock:SetSize(barH * 1.1, barH * 1.1)
	cast.lock:ClearAllPoints()
	cast.lock:SetPoint("LEFT", cast, "RIGHT", 1, 0)
	local iconSize = castH + (o.castIcon ~= false and barH * 0.6 or 0)
	cast.icon:SetSize(iconSize, iconSize)
	cast.icon:ClearAllPoints()
	cast.icon:SetPoint("RIGHT", cast, "LEFT", -2, 0)
	cast.icon:SetShown(o.castIcon ~= false)
	cast.text:ClearAllPoints()
	cast.text:SetPoint("TOP", cast, "BOTTOM", 0, -1)
	cast.who:ClearAllPoints()
	cast.who:SetPoint("LEFT", cast.text, "RIGHT", 4, 0)
	cast.you:ClearAllPoints()
	cast.you:SetPoint("LEFT", cast.text, "RIGHT", 4, 0)

	-- Your debuffs above the name.
	if p.auras then
		p.auras:ClearAllPoints()
		if o.namePos == "inside" then
			p.auras:SetPoint("BOTTOM", root, "TOP", 0, 3)
		else
			p.auras:SetPoint("BOTTOM", p.name, "TOP", 0, 3)
		end
	end
	Fonts(p)
end

---------------------------------------------------------------------------
-- Reading a unit

local function Ask(fn, ...)
	if not fn then return nil end
	local ok, v = pcall(fn, ...)
	if ok and Plain(v) then return v end
	return nil
end

local function Classification(unit)
	local c = UnitClassification(unit)
	if not Plain(c) then return "normal" end
	local level = UnitLevel(unit)
	if c == "worldboss" or Ask(UnitIsBossMob, unit) or (Plain(level) and level == -1 and (c == "elite" or c == "rareelite")) then return "boss" end
	if c == "rare" or c == "rareelite" then return "rare" end
	if c == "elite" then return "elite" end
	return "normal"
end

local function IsEnemy(unit)
	local reaction = UnitReaction(unit, "player")
	if Plain(reaction) then return reaction <= 4 end
	local ok, attack = pcall(UnitCanAttack, "player", unit)
	return ok and Plain(attack) and attack or false
end

---------------------------------------------------------------------------
-- Updates (real units)

local function UpdateName(p)
	local unit = p.unit
	local o = Opt()
	local name = UnitName(unit)
	if not pcall(p.name.SetText, p.name, name) then p.name:SetText("") end
	P.FitNameFont(p, name)
	local c = P.NameColor(p.rank, Ask(UnitReaction, unit, "player"))
	if Ask(UnitIsPlayer, unit) then
		local _, class = UnitClass(unit)
		local cc = Plain(class) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
		if cc then c = { cc.r, cc.g, cc.b } end
	end
	p.name:SetTextColor(c[1], c[2], c[3])
	-- Level, coloured by how hard it is for you; ?? in red past reach.
	local level = UnitLevel(unit)
	if o.showLevel == false or not Plain(level) then
		p.level:SetText("")
	elseif level < 0 then
		p.level:SetText("??")
		p.level:SetTextColor(1, 0.25, 0.15)
	else
		p.level:SetText(level)
		local dc = GetCreatureDifficultyColor and GetCreatureDifficultyColor(level)
		if dc then p.level:SetTextColor(dc.r, dc.g, dc.b) else p.level:SetTextColor(1, 0.82, 0.25) end
	end
end

local function UpdateFill(p)
	local unit = p.unit
	local tex = ns.Art.Path("unitFill")
	local tint
	if Ask(UnitIsTapDenied, unit) then
		tint = FILL.tapped
	elseif Ask(UnitIsPlayer, unit) and Opt().classFill ~= false then
		local _, class = UnitClass(unit)
		local cc = Plain(class) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
		if cc then tint = { cc.r, cc.g, cc.b } end
	elseif Ask(UnitReaction, unit, "player") == 4 then
		tint = FILL.neutral
	else
		local mode = Opt().healthColor or "d3"
		if mode == "custom" then
			tint = Opt().healthRGB or { 0.8, 0.1, 0.1 }
		elseif mode == "reaction" then
			tint = FILL.hostile
		end
	end
	if tint then
		p.health:SetStatusBarTexture(ns.Art.Path("unitFillWhite") or tex or "Interface\\Buttons\\WHITE8X8")
		p.health:SetStatusBarColor(tint[1], tint[2], tint[3], 1)
	else
		p.health:SetStatusBarTexture(tex or "Interface\\Buttons\\WHITE8X8")
		p.health:SetStatusBarColor(1, 1, 1, 1)
	end
end

-- An enemy's name colour: by rank (D3: elite blue, rare yellow, boss orange), by reaction
-- (hostile red, neutral yellow), or plain white.
function P.NameColor(rank, reaction)
	local mode = Opt().nameColor or "rank"
	if mode == "white" then return { 0.95, 0.93, 0.9 } end
	if mode == "reaction" then
		return reaction == 4 and { 1, 0.85, 0.25 } or { 1, 0.32, 0.25 }
	end
	return NAME_COLORS[rank] or NAME_COLORS.normal
end

local function ShowPercent(p)
	local mode = Opt().healthText or "target"
	return mode == "all" or (mode == "target" and p.isTarget)
end

-- A name on the bar takes the room the level and (where it shows) the percent leave it.
function P.FitName(p)
	if not p.nameRoom then return end
	local pctW = ShowPercent(p) and (Opt().textSize or 9) * 2.8 or 0
	p.name:SetWidth(math.max(10, p.nameRoom - pctW))
	p.nameFitInside = math.max(10, p.nameRoom - pctW)
end

-- A long name shrinks to fit its room (down to 72%) before it's cut short with "...". Sized from
-- the name's length, not by measuring the plate, which the game doesn't allow; Exocet runs about
-- two thirds of its size per letter, other faces a little less. A secret name keeps the size.
function P.FitNameFont(p, name)
	if p.friend then return end
	local o = Opt()
	local size = o.nameSize or 10
	local room = p.nameRoom and p.nameFitInside or p.nameFitW
	if room and name ~= nil and not Secret(name) and type(name) == "string" and #name > 0 then
		local per = ((o.nameFont or "d3") == "d3" and 0.66 or 0.56) * size
		local need = #name * per
		if need > room then size = math.max(size * 0.72, size * room / need) end
	end
	ns.Fonts.Set(p.name, "title", size, OUTLINES[o.nameOutline or "outline"] or "OUTLINE", o.nameFont)
end

local function UpdatePercent(p)
	if not p.unit or p.friend then return end -- the preview writes its own; friends show none
	if not ShowPercent(p) then
		p.pct:SetText("")
		return
	end
	local curve = CurveConstants and CurveConstants.ScaleTo100
	if UnitHealthPercent and curve then
		local ok, pct = pcall(UnitHealthPercent, p.unit, true, curve)
		if ok and pct ~= nil and pcall(p.pct.SetFormattedText, p.pct, "%d%%", pct) then return end
	end
	local h, m = UnitHealth(p.unit), UnitHealthMax(p.unit)
	if Plain(h) and Plain(m) and m > 0 then
		p.pct:SetFormattedText("%d%%", h / m * 100)
	else
		p.pct:SetText("")
	end
end

local function UpdateExecute(p)
	local o = Opt()
	if o.execute == false then
		p.execute:SetAlpha(0)
		return
	end
	local curve = UnitHealthPercent and ExecuteCurve()
	if curve then
		local ok, a = pcall(UnitHealthPercent, p.unit, true, curve)
		if ok and a ~= nil and pcall(p.execute.SetAlpha, p.execute, a) then return end
	end
	local h, m = UnitHealth(p.unit), UnitHealthMax(p.unit)
	if Plain(h) and Plain(m) and m > 0 then
		p.execute:SetAlpha(h / m * 100 <= (o.executeAt or 20) and 1 or 0)
	else
		p.execute:SetAlpha(0)
	end
end

local function QueueTrail(p)
	if p.trailQueued then return end
	p.trailQueued = true
	C_Timer.After(TRAIL_HOLD, function()
		p.trailQueued = nil
		if p.unit and p.trailPending ~= nil then SetBar(p.trail, p.trailPending, Ease()) end
	end)
end

local function UpdateHealth(p, snap)
	local unit = p.unit
	local h, m = UnitHealth(unit), UnitHealthMax(unit)
	local top = ns.Or(m, 1)
	for _, bar in ipairs({ p.health, p.execute, p.trail }) do pcall(bar.SetMinMaxValues, bar, 0, top) end
	local value = ns.Or(h, 0)
	SetBar(p.health, value, not snap and Ease())
	SetBar(p.execute, value, not snap and Ease())
	p.trailPending = value
	if snap or Opt().trail == false then
		SetBar(p.trail, value)
	else
		QueueTrail(p)
	end
	if not snap and Opt().hitFlash ~= false then
		p.flashAnim:Stop()
		p.flashAnim:Play()
	end
	UpdatePercent(p)
	UpdateExecute(p)
end

local function UpdateRaid(p)
	if Opt().raidIcon == false then
		p.raid:Hide()
		return
	end
	local index = GetRaidTargetIndex(p.unit)
	if index == nil then
		p.raid:Hide()
		return
	end
	-- May be secret: the client sets the texture from it all the same.
	if SetRaidTargetIconTexture and pcall(SetRaidTargetIconTexture, p.raid, index) then
		p.raid:Show()
	else
		p.raid:Hide()
	end
end

-- Quest mobs, from the unit's tooltip: an objective still open. Out of combat (lines can be
-- secret in it), so a plate that appears mid-fight keeps what it had.
local function UpdateQuest(p)
	if p.friend or p.questie or Opt().quest == false or not (C_TooltipInfo and C_TooltipInfo.GetUnit) then
		p.quest:Hide()
		return
	end
	if InCombatLockdown() and p.questKnown then return end
	local ok, data = pcall(C_TooltipInfo.GetUnit, p.unit)
	local found = false
	local types = Enum and Enum.TooltipDataLineType
	if ok and data and data.lines and not Secret(data.lines) then
		for _, line in ipairs(data.lines) do
			local t = line.type
			if Plain(t) and types and t == types.QuestObjective then
				local text = line.leftText
				if Plain(text) then
					local have, need = text:match("(%d+)/(%d+)")
					if not (have and need and tonumber(have) >= tonumber(need)) and not line.completed then
						found = true
						break
					end
				end
			end
		end
		p.questKnown = true
	end
	p.quest:SetShown(found)
end

local function IsTank()
	return ns.Threat and ns.Threat.IsTank and ns.Threat.IsTank() or false
end

local function UpdateThreat(p)
	if p.friend then return end
	local o = Opt()
	local status = o.threat ~= false and Ask(UnitThreatSituation, "player", p.unit)
	local color
	if status then
		local inCombat = Ask(UnitAffectingCombat, p.unit)
		if IsTank() then
			-- In a fight and not on you: loose.
			if inCombat and status < 2 then color = THREAT.warn end
		elseif status >= 2 then
			color = THREAT.aggro
		elseif status == 1 then
			color = THREAT.warn
		end
	end
	if color then
		p.threat:SetVertexColor(color[1], color[2], color[3])
		p.threat:SetAlpha(0.95)
	else
		p.threat:SetAlpha(0)
	end
end

local function ApplyTarget(p)
	local o = Opt()
	local on = p.isTarget and o.targetMark ~= false
	p.targetGlow:SetAlpha(on and 0.55 or 0)
	p.left:SetShown(on)
	p.left.edge:SetShown(on)
	p.right:SetShown(on)
	p.right.edge:SetShown(on)
	local scale = (o.scale or 1) * (p.isTarget and (o.targetScale or 1.15) or 1)
	p.root:SetScale(scale)
	local dim = o.othersAlpha or 1
	p.root:SetAlpha((P.hasTarget and not p.isTarget) and dim or 1)
	p.root:SetFrameStrata(p.isTarget and "MEDIUM" or "LOW")
	P.FitName(p)
	UpdatePercent(p)
end

---------------------------------------------------------------------------
-- Casts

local function StopCast(p)
	local cast = p.cast
	if cast.holdUntil and GetTime() < cast.holdUntil then return end
	cast:Hide()
	cast.holdUntil = nil
end

local function ReadCast(unit, channel)
	local name, texture, startMS, endMS, notInterruptible, spellID
	if channel then
		name, _, texture, startMS, endMS, _, notInterruptible, spellID = UnitChannelInfo(unit)
	else
		name, _, texture, startMS, endMS, _, _, notInterruptible, spellID = UnitCastingInfo(unit)
	end
	return name, startMS, endMS, notInterruptible, texture
end

local function StartCast(p, channel)
	local o = Opt()
	local cast, unit = p.cast, p.unit
	if o.cast == false then
		cast:Hide()
		return
	end
	local name, startMS, endMS, notInterruptible, texture = ReadCast(unit, channel)
	if not Secret(name) and not name then
		if channel == nil then
			channel = true
			name, startMS, endMS, notInterruptible, texture = ReadCast(unit, true)
		end
		if not Secret(name) and not name then
			cast.holdUntil = nil
			cast:Hide()
			return
		end
	end
	cast.holdUntil = nil
	cast.channel = channel and true or false
	if not pcall(cast.icon.SetTexture, cast.icon, ns.Or(texture, 136243)) then cast.icon:SetTexture(136243) end
	if not pcall(cast.text.SetText, cast.text, name) then cast.text:SetText("") end
	cast.text:SetTextColor(0.94, 0.9, 0.82)
	cast.bar:SetStatusBarColor(1, 0.6, 0.16, 1)
	Bool(cast.grey, notInterruptible, 1, 0)
	Bool(cast.lock, notInterruptible, 1, 0)

	-- Who it's at: "» YOU" in red when it's you, else their name.
	local mine = UnitIsUnit(unit .. "target", "player")
	if o.castTarget ~= false then
		Bool(cast.you, mine, 1, 0)
		local who = UnitSpellTargetName and Ask(UnitSpellTargetName, unit)
		if who == nil and UnitSpellTargetName then
			local ok, secretWho = pcall(UnitSpellTargetName, unit)
			if ok then who = secretWho end
		end
		if who ~= nil and pcall(function() cast.who:SetText("» " .. who) end) then
			Bool(cast.who, mine, 0, 1)
		else
			cast.who:SetText("")
		end
	else
		cast.you:SetAlpha(0)
		cast.who:SetText("")
	end

	-- The client runs the bar from a duration object, filling a cast and draining a channel.
	local duration
	if channel then
		duration = UnitChannelDuration and UnitChannelDuration(unit)
	else
		duration = UnitCastingDuration and UnitCastingDuration(unit)
	end
	local bars = { cast.bar, cast.grey }
	if duration ~= nil and cast.bar.SetTimerDuration then
		local directions = Enum and Enum.StatusBarTimerDirection
		local direction = directions and (channel and directions.RemainingTime or directions.ElapsedTime)
		local smoothing = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate
		for _, b in ipairs(bars) do b:SetTimerDuration(duration, smoothing, direction) end
		cast.startMS, cast.endMS = nil, nil
	elseif Plain(startMS) and Plain(endMS) then
		cast.startMS, cast.endMS = startMS, endMS
		for _, b in ipairs(bars) do b:SetMinMaxValues(startMS, endMS) end
	else
		cast.startMS, cast.endMS = nil, nil
		for _, b in ipairs(bars) do
			b:SetMinMaxValues(0, 1)
			b:SetValue(1)
		end
	end
	cast.spark:SetAlpha(0.9)
	cast:Show()
end

-- "Interrupted by Name" in red, held a moment.
local function Interrupted(p, by)
	local cast = p.cast
	if not cast:IsShown() then return end
	local text = INTERRUPTED or "Interrupted"
	if Opt().interrupter ~= false and by ~= nil and GetPlayerInfoByGUID then
		local ok, _, class, _, _, _, name = pcall(GetPlayerInfoByGUID, by)
		if ok and name ~= nil then
			local cc = Plain(class) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
			local okJoin, joined = pcall(function()
				if cc then return ("%s |c%s%s|r"):format(text, cc.colorStr or "ffffffff", name) end
				return text .. " " .. name
			end)
			if okJoin then text = joined end
		end
	end
	if not pcall(cast.text.SetText, cast.text, text) then cast.text:SetText(INTERRUPTED or "Interrupted") end
	cast.text:SetTextColor(1, 0.3, 0.22)
	cast.who:SetText("")
	cast.you:SetAlpha(0)
	cast.bar:SetStatusBarColor(0.85, 0.15, 0.1, 1)
	cast.grey:SetAlpha(0)
	cast.spark:SetAlpha(0)
	cast.startMS, cast.endMS = nil, nil
	-- Stop the timer where it stands: a plain value from here on.
	local ok, v = pcall(cast.bar.GetValue, cast.bar)
	local ok2, low, high = pcall(cast.bar.GetMinMaxValues, cast.bar)
	if ok and ok2 and Plain(v) and Plain(low) and Plain(high) then
		cast.bar:SetMinMaxValues(low, high)
		cast.bar:SetValue(v)
	else
		cast.bar:SetMinMaxValues(0, 1)
		cast.bar:SetValue(1)
	end
	cast.holdUntil = GetTime() + INTERRUPT_HOLD
	C_Timer.After(INTERRUPT_HOLD + 0.05, function()
		if cast.holdUntil and GetTime() >= cast.holdUntil then
			cast.holdUntil = nil
			cast:Hide()
		end
	end)
end

---------------------------------------------------------------------------
-- Your debuffs (the client's aura container: it reads and sorts them, even in combat)

local function HasTemplate(name)
	if not (C_XMLUtil and C_XMLUtil.GetTemplateInfo) then return false end
	local ok, info = pcall(C_XMLUtil.GetTemplateInfo, name)
	return ok and info ~= nil
end
local HAS_CONTAINERS = HasTemplate("CustomAuraContainerTemplate")
local containerPool = {}

-- One font object per icon size, for the debuff countdowns.
local countdownFonts = {}
function P.CountdownFont(size)
	local key = math.floor(size + 0.5)
	if countdownFonts[key] == nil then
		local name = "SanctuaryUIPlateCountdown" .. key
		local ok, font = pcall(CreateFont, name)
		if ok and font then
			font:SetFont(ns.Fonts.Path("body"), math.max(7, math.floor(size * 0.55 + 0.5)), "OUTLINE")
			countdownFonts[key] = name
		else
			countdownFonts[key] = false
		end
	end
	return countdownFonts[key] or nil
end

local function DressAura(button)
	local size = Opt().auraSize or 16
	button:SetSize(size, size)
	local edge = button:CreateTexture(nil, "BACKGROUND")
	edge:SetPoint("TOPLEFT", -1, 1)
	edge:SetPoint("BOTTOMRIGHT", 1, -1)
	edge:SetColorTexture(0.12, 0.06, 0.02, 1)
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	button:SetIcon(icon)
	local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	cooldown:SetAllPoints()
	cooldown:SetReverse(true)
	cooldown:EnableMouse(false)
	if cooldown.SetDrawEdge then cooldown:SetDrawEdge(false) end
	if cooldown.SetDrawBling then cooldown:SetDrawBling(false) end
	-- The client's countdown numbers (they need the cooldown-numbers setting on), in a small font
	-- sized to the icon: the game's own is far too big for these and the numbers run together.
	if cooldown.SetHideCountdownNumbers then cooldown:SetHideCountdownNumbers(false) end
	if cooldown.SetCountdownFont then
		local font = P.CountdownFont(size)
		if font then pcall(cooldown.SetCountdownFont, cooldown, font) end
	end
	button:SetDurationCooldown(cooldown)
	local count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	count:SetPoint("BOTTOMRIGHT", 2, -1)
	button:SetApplicationCount(count)
	if button.SetTooltipAnchorPoint then button:SetTooltipAnchorPoint("ANCHOR_BOTTOMRIGHT", 0, 0) end
end

local function NewContainer()
	if not HAS_CONTAINERS then return nil end
	local ok, box = pcall(function()
		local b = CreateFrame("AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
		b:SetSize(1, 1)
		local o = Opt()
		local size = o.auraSize or 16
		b:AddAuraGroup("mine", "HARMFUL", {
			maxFrameCount = o.maxAuras or 4,
			sortMethod = AuraContainerSortMethod and AuraContainerSortMethod.Expiration or 0,
			sortDirection = AuraContainerSortDirection and AuraContainerSortDirection.Normal or 0,
			candidateFilters = { isFromPlayerOrPlayerPet = true },
			initializeFrame = DressAura,
			layout = { elementSpacing = 2, lineSpacing = 2, groupLineSpacing = 2, forceNewLine = false, elementWidth = size, elementHeight = size },
		})
		return b
	end)
	if not ok then
		if ns.LogError then ns.LogError("plates", "aura container: " .. tostring(box)) end
		return nil
	end
	return box
end

-- Behind the loading screen: containers are slow to build (Plater saw a 1-2 s freeze).
function P.FillPool(n)
	if not HAS_CONTAINERS or InCombatLockdown() then return end
	while #containerPool < n do
		local box = NewContainer()
		if not box then return end
		box:Hide()
		containerPool[#containerPool + 1] = box
	end
end

local function TakeContainer(p)
	if p.auras or Opt().auras == false then return end
	local box = table.remove(containerPool)
	if not box and not InCombatLockdown() then box = NewContainer() end
	if not box then return end
	box:SetParent(p.over)
	p.auras = box
	box:ClearAllPoints()
	if Opt().namePos == "inside" then
		box:SetPoint("BOTTOM", p.root, "TOP", 0, 3)
	else
		box:SetPoint("BOTTOM", p.name, "TOP", 0, 3)
	end
end

local function SetAuraUnit(p, unit)
	local box = p.auras
	if not box then return end
	if unit and Opt().auras ~= false then
		pcall(box.SetUnit, box, unit)
		pcall(box.SetEnabled, box, true)
		box:Show()
	else
		pcall(box.SetEnabled, box, false)
		box:Hide()
	end
end

---------------------------------------------------------------------------
-- Death: embers burst where the plate was

local bursts = {}
-- anchor: where it bursts. Pinned to the plate rather than measured: the game won't let an
-- addon measure nameplates ("Can't measure restricted regions"); a removed plate stays put.
local function Burst(anchor, scale)
	if not anchor then return end
	local b
	for _, f in ipairs(bursts) do
		if not f:IsShown() then b = f break end
	end
	if not b then
		b = CreateFrame("Frame", nil, UIParent)
		b:SetFrameStrata("LOW")
		b:SetSize(1, 1)
		b.flash = Glow(b, "ARTWORK", { 1, 0.35, 0.12 })
		b.sparks = {}
		for i = 1, 10 do
			b.sparks[i] = Glow(b, "OVERLAY", { 1, 0.6 + (i % 3) * 0.12, 0.25 })
		end
		b:SetScript("OnUpdate", function(self, elapsed)
			self.t = self.t + elapsed
			local t = self.t / 0.6
			if t >= 1 then
				self:Hide()
				return
			end
			local s = self.s
			self.flash:SetSize(70 * s * (0.6 + t), 26 * s * (0.6 + t))
			self.flash:SetAlpha((1 - t) * 0.9)
			for i, spark in ipairs(self.sparks) do
				local ang = (i / #self.sparks) * math.pi * 2 + i
				local r = (18 + 40 * t) * s * (0.7 + (i % 4) * 0.12)
				spark:ClearAllPoints()
				spark:SetPoint("CENTER", self, "CENTER", math.cos(ang) * r, math.sin(ang) * r * 0.55 + 10 * t * s)
				spark:SetSize(7 * s * (1 - t * 0.6), 7 * s * (1 - t * 0.6))
				spark:SetAlpha(1 - t)
			end
		end)
		b.flash:SetPoint("CENTER")
		bursts[#bursts + 1] = b
	end
	b.t, b.s = 0, scale or 1
	b:ClearAllPoints()
	b:SetPoint("CENTER", anchor, "CENTER")
	b:Show()
end

local function BurstAt(p)
	if Opt().deathBurst == false then return end
	Burst(p.root, Opt().scale or 1)
end

---------------------------------------------------------------------------
-- The game's own plate frame

local function Owned(unitFrame)
	local plate = unitFrame and unitFrame:GetParent()
	local p = plate and objs[plate]
	return p and p.unit ~= nil
end

-- Hide the game's UnitFrame while ours shows on its plate (from the Show hook and on unit add).
local function HideBlizzard(unitFrame)
	if not unitFrame then return end
	if not active or not Owned(unitFrame) then
		if unitFrame:GetAlpha() == 0 then pcall(unitFrame.SetAlpha, unitFrame, 1) end
		return
	end
	if unitFrame.IsProtected and unitFrame:IsProtected() then
		pcall(unitFrame.SetAlpha, unitFrame, 0)
	else
		unitFrame:Hide()
	end
end

local function Hook(plate)
	local uf = plate.UnitFrame
	if uf and not hooked[uf] then
		hooked[uf] = true
		hooksecurefunc(uf, "Show", HideBlizzard)
	end
end

-- 1 while hurt, 0 at full health (evaluated by the client on secret health).
local function HurtCurve()
	return Curve("hurt", { { 0, 1 }, { 0.9995, 1 }, { 1, 0 } })
end

local function FriendStrip(p)
	local unit = p.unit
	local alpha = 0
	local mode = Opt().friendlyStrip or "hurt"
	if mode == "always" or mode == "never" then
		alpha = mode == "always" and 1 or 0
	elseif Ask(UnitAffectingCombat, unit) then
		alpha = 1
	else
		local curve = UnitHealthPercent and HurtCurve()
		if curve then
			local ok, a = pcall(UnitHealthPercent, unit, true, curve)
			if ok and a ~= nil and pcall(p.health.SetAlpha, p.health, a) then
				pcall(p.slot.SetAlpha, p.slot, a)
				return
			end
		end
		local h, m = UnitHealth(unit), UnitHealthMax(unit)
		if Plain(h) and Plain(m) and h < m then alpha = 1 end
	end
	p.health:SetAlpha(alpha)
	p.slot:SetAlpha(alpha)
end

local function FriendHealth(p)
	local unit = p.unit
	local h, m = UnitHealth(unit), UnitHealthMax(unit)
	pcall(p.health.SetMinMaxValues, p.health, 0, ns.Or(m, 1))
	SetBar(p.health, ns.Or(h, 0), Ease())
	FriendStrip(p)
end

local function UpdateFriend(p)
	local unit = p.unit
	if not pcall(p.name.SetText, p.name, UnitName(unit)) then p.name:SetText("") end
	local c = FRIEND_NAME
	local fill = FRIEND_FILL
	local isPlayer = Ask(UnitIsPlayer, unit)
	if isPlayer then
		local _, class = UnitClass(unit)
		local cc = Plain(class) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
		if cc then c, fill = { cc.r, cc.g, cc.b }, { cc.r, cc.g, cc.b } end
	end
	if not isPlayer and Opt().friendlyColor == "white" then c = { 0.95, 0.93, 0.9 } end
	if not isPlayer and Opt().friendlyColor == "green" then c = { 0.45, 0.9, 0.4 } end
	p.name:SetTextColor(c[1], c[2], c[3])
	p.health:SetStatusBarTexture(ns.Art.Path("unitFillWhite") or "Interface\\Buttons\\WHITE8X8")
	p.health:SetStatusBarColor(fill[1], fill[2], fill[3], 1)
	-- A player's guild, small, under the name.
	-- An NPC's title (<Warrior Trainer>, <Innkeeper>) in the same place.
	local guild
	if isPlayer then
		guild = Opt().friendlyGuild ~= false and GetGuildInfo and GetGuildInfo(unit)
	else
		-- An NPC: its title (<Warrior Trainer>), then its level and faction (Level 20 · Darnassus),
		-- as its tooltip has them, each on its own line.
		local title, faction = P.NPCInfo(unit)
		local lines = {}
		if title and Opt().friendlyTitle ~= false then lines[#lines + 1] = "<" .. title .. ">" end
		if Opt().friendlyDetails ~= false then
			local level = Ask(UnitLevel, unit)
			local parts = {}
			if level and level > 0 then parts[#parts + 1] = (LEVEL or "Level") .. " " .. level end
			if faction then parts[#parts + 1] = faction end
			if #parts > 0 then lines[#lines + 1] = table.concat(parts, " · ") end
		end
		p.guild:SetText(table.concat(lines, "\n"))
		FriendHealth(p)
		return
	end
	if not (guild and pcall(function() p.guild:SetText("<" .. guild .. ">") end)) then p.guild:SetText("") end
	FriendHealth(p)
end

-- An NPC's title and faction from its tooltip: the title is the second line when it isn't the
-- level line ("Level 30 Humanoid"); the faction is the first line after the level line that isn't
-- PvP (Darnassus, Stormwind). Read out of combat (tooltip lines can be secret in it); kept per
-- name, since the same guard or trainer comes back on every plate.
local infos = {}
local LEVEL_WORD = (LEVEL or "Level"):lower()
local function Text(line)
	local text = line and line.leftText
	if Plain(text) and type(text) == "string" and text ~= "" then return text end
end
function P.NPCInfo(unit)
	local name = UnitName(unit)
	local key = Plain(name) and name or nil
	local known = key and infos[key]
	if known then return known.title, known.faction end
	if InCombatLockdown() or not (C_TooltipInfo and C_TooltipInfo.GetUnit) then return nil end
	local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
	if not ok or not data or Secret(data.lines) or type(data.lines) ~= "table" then return nil end
	local lines = data.lines
	local title, faction
	local levelAt
	for i = 2, #lines do
		local text = Text(lines[i])
		if text and text:lower():find("^" .. LEVEL_WORD .. "[%s%d%?]") then
			levelAt = i
			break
		end
	end
	local second = Text(lines[2])
	if second and levelAt and levelAt > 2 then title = second:gsub("^<(.*)>$", "%1") end
	if levelAt then
		local types = Enum and Enum.TooltipDataLineType
		for i = levelAt + 1, #lines do
			local text = Text(lines[i])
			local t = lines[i].type
			local questLine = types and Plain(t) and (t == types.QuestObjective or t == types.QuestTitle or t == types.QuestPlayer)
			if text and not questLine and text ~= (PVP or "PvP") and not text:find("%d") then
				faction = text
				break
			end
		end
	end
	if key then infos[key] = { title = title, faction = faction } end
	return title, faction
end

-- The game's soft-target icon (the sword over the enemy your action key would hit, the bag over a
-- corpse to loot) sits on the game's own plate, which is protected here: we can only fade that
-- plate, not move its pieces, and the icon ignores its parent's fade. So the game's icon is faded
-- too, and ours is drawn beside the level (above the name on a friend). Which plate it belongs on
-- comes from GetNamePlateForUnit("softenemy"/"softfriend"/"softinteract"): a frame, never secret.
local SOFT = {
	{ token = "softenemy", cvar = "SoftTargetIconEnemy" },
	{ token = "softfriend", cvar = "SoftTargetIconFriend" },
	{ token = "softinteract", cvar = "SoftTargetIconInteract" },
}

local function FadeSoftTarget(plate, owned)
	local uf = plate.UnitFrame
	local soft = uf and uf.SoftTargetFrame
	if soft then pcall(soft.SetAlpha, soft, owned and 0 or 1) end
end

local function PlaceSoft(p)
	local icon = p.soft
	icon:ClearAllPoints()
	if p.friend or Opt().namePos == "inside" then
		icon:SetPoint("BOTTOM", p.friend and p.name or p.root, "TOP", 0, 2)
	else
		icon:SetPoint("RIGHT", p.level, "LEFT", -2, 0)
	end
	local size = (Opt().nameSize or 10) + 8
	icon:SetSize(size, size)
end

function P.UpdateSoftTargets()
	for _, p in pairs(byUnit) do p.soft:Hide() end
	if Opt().softIcon == false or not C_NamePlate or not SetUnitCursorTexture then return end
	local cvarOn = (C_CVar and C_CVar.GetCVarBool) or GetCVarBool
	for _, s in ipairs(SOFT) do
		local on = true
		if cvarOn then
			local ok, v = pcall(cvarOn, s.cvar)
			if ok and v == false then on = false end
		end
		local plate = on and C_NamePlate.GetNamePlateForUnit(s.token)
		local p = plate and objs[plate]
		if p and p.unit and not p.soft:IsShown() then
			local ok, has = pcall(SetUnitCursorTexture, p.soft, s.token, nil, nil, true)
			if ok and has then
				PlaceSoft(p)
				p.soft:Show()
			end
		end
	end
end

-- Questie's quest icons (a sword for mobs to kill, a bag for mobs that drop quest items) are its own
-- frames, children of the game's plate, pinned at Questie's offset from that plate's left edge: off
-- in space beside ours. They move onto our plate, at the end of the name row where our "!" goes
-- (which then steps aside: Questie's says more). Their LEFT point is the one replaced, the point
-- Questie itself sets, so the two never pull against each other.
local function QuestieFrames(plate)
	local list = {}
	local ok, children = pcall(function() return { plate:GetChildren() } end)
	if not ok then return list end
	for _, c in ipairs(children) do
		if type(c) == "table" and rawget(c, "Icon") and rawget(c, "lastIcon") ~= nil then list[#list + 1] = c end
	end
	return list
end

function P.AdoptQuestie(p)
	if not p or not p.unit or not p.plate then return end
	local any = false
	if Opt().questieIcons ~= false then
		local size = (Opt().nameSize or 10) + 6
		for _, f in ipairs(QuestieFrames(p.plate)) do
			if f:IsShown() then
				any = true
				pcall(f.SetPoint, f, "LEFT", p.quest, "LEFT", 0, 0)
				pcall(f.SetSize, f, size, size)
			end
		end
	end
	p.questie = any
	if any then p.quest:Hide() end
end

local function AdoptAllQuestie()
	for _, p in pairs(byUnit) do P.AdoptQuestie(p) end
end

-- /sanctuary plates soft: what the game says about each soft target, its plate and both icons.
function P.SoftReport()
	local function b(v)
		if v == nil then return "nil" end
		if Secret(v) then return "secret" end
		return tostring(v)
	end
	local function call(obj, method, ...)
		if type(obj) ~= "table" or not obj[method] then return "-" end
		local ok, v = pcall(obj[method], obj, ...)
		return ok and b(v) or "err"
	end
	local cvarOn = (C_CVar and C_CVar.GetCVarBool) or GetCVarBool
	for _, s in ipairs(SOFT) do
		local exists = UnitExists(s.token)
		local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit(s.token)
		local forbidden = C_NamePlate and C_NamePlate.GetNamePlateForUnit(s.token, true)
		local p = plate and objs[plate]
		local uf = plate and plate.UnitFrame
		local sf = uf and uf.SoftTargetFrame
		local cv = cvarOn and select(2, pcall(cvarOn, s.cvar))
		ns.Print(("%s: exists %s, cvar %s, plate %s%s, ours %s (unit %s)"):format(s.token, b(exists), b(cv),
			plate and "yes" or "no", (not plate and forbidden) and " (forbidden one)" or "", p and "yes" or "no", p and b(p.unit) or "-"))
		if uf then
			ns.Print(("  game plate: shown %s, alpha %s, protected %s"):format(call(uf, "IsShown"), call(uf, "GetAlpha"), call(uf, "IsProtected")))
		end
		if sf then
			ns.Print(("  game icon frame: shown %s, alpha %s, ignores parent alpha %s, icon shown %s"):format(call(sf, "IsShown"), call(sf, "GetAlpha"),
				call(sf, "IsIgnoringParentAlpha"), call(sf.Icon, "IsShown")))
		end
		if p then
			ns.Print(("  our icon: shown %s, texture %s"):format(call(p.soft, "IsShown"), call(p.soft, "GetTexture")))
		end
	end
end

local function Setup(plate)
	if objs[plate] then return objs[plate] end
	local p = NewPlate(plate)
	p.plate = plate
	p.root:SetPoint("CENTER", plate, "CENTER", 0, 0)
	-- What the game stacks plates by and where they take clicks: our frame, not its own.
	local stack = CreateFrame("Frame", nil, p.root)
	stack:SetAllPoints(p.root)
	local t = stack:CreateTexture()
	t:SetColorTexture(0, 0, 0, 0)
	t:SetAllPoints()
	p.stack = stack
	if plate.SetStackingBoundsFrame then pcall(plate.SetStackingBoundsFrame, plate, stack) end
	p.root:Hide()
	objs[plate] = p
	Layout(p)
	return p
end

local function Refresh(p)
	if p.friend then
		UpdateFriend(p)
		UpdateRaid(p)
		ApplyTarget(p)
		return
	end
	UpdateName(p)
	UpdateFill(p)
	UpdateHealth(p, true)
	UpdateRaid(p)
	UpdateQuest(p)
	UpdateThreat(p)
	ApplyTarget(p)
	StartCast(p, nil)
end

local function TargetPlate()
	local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit("target")
	return plate
end

local function Added(unit)
	if not active then return end
	local plate = C_NamePlate.GetNamePlateForUnit(unit)
	if not plate then return end -- forbidden (a friend in an instance)
	Hook(plate)
	local p = Setup(plate)
	local enemy = IsEnemy(unit)
	if not enemy and Opt().friendly == "off" then
		p.unit = nil
		p.root:Hide()
		HideBlizzard(plate.UnitFrame)
		FadeSoftTarget(plate, false)
		return
	end
	p.unit = unit
	p.friend = not enemy
	byUnit[unit] = p
	p.rank = enemy and Classification(unit) or "normal"
	p.questKnown = nil
	p.isTarget = TargetPlate() == plate
	if enemy then TakeContainer(p) end
	Layout(p)
	SetAuraUnit(p, enemy and unit or nil)
	p.root:Show()
	Refresh(p)
	HideBlizzard(plate.UnitFrame)
	FadeSoftTarget(plate, true)
	P.UpdateSoftTargets()
	-- Questie makes its icon on the same event, before or after us: adopt it next frame.
	p.questie = nil
	C_Timer.After(0, function()
		if p.unit == unit then P.AdoptQuestie(p) end
	end)
	if plate.CanChangeHitTestPoints and plate:CanChangeHitTestPoints() then
		pcall(plate.SetAllHitTestPoints, plate, p.stack)
	end
end

local function Removed(unit, quiet)
	local p = byUnit[unit]
	if not p then return end
	if not quiet and not p.friend and Ask(UnitIsDead, unit) then BurstAt(p) end
	byUnit[unit] = nil
	p.unit = nil
	p.soft:Hide()
	p.cast.holdUntil = nil
	p.cast:Hide()
	SetAuraUnit(p, nil)
	p.root:Hide()
end

local function TargetChanged()
	local plate = TargetPlate()
	P.hasTarget = UnitExists("target") and true or false
	for _, p in pairs(byUnit) do
		p.isTarget = plate ~= nil and p.plate == plate
		ApplyTarget(p)
	end
end

---------------------------------------------------------------------------
-- Events

local driver = CreateFrame("Frame")
local UNIT_EVENTS = {
	UNIT_HEALTH = function(p) UpdateHealth(p) end,
	UNIT_MAXHEALTH = function(p) UpdateHealth(p, true) end,
	UNIT_NAME_UPDATE = function(p) UpdateName(p) end,
	UNIT_LEVEL = function(p) UpdateName(p) end,
	UNIT_FACTION = function(p) UpdateFill(p) UpdateThreat(p) end,
	UNIT_THREAT_LIST_UPDATE = function(p) UpdateThreat(p) end,
	UNIT_SPELLCAST_START = function(p) StartCast(p, false) end,
	UNIT_SPELLCAST_CHANNEL_START = function(p) StartCast(p, true) end,
	UNIT_SPELLCAST_DELAYED = function(p) StartCast(p, false) end,
	UNIT_SPELLCAST_CHANNEL_UPDATE = function(p) StartCast(p, true) end,
	UNIT_SPELLCAST_INTERRUPTIBLE = function(p) StartCast(p, p.cast.channel) end,
	UNIT_SPELLCAST_NOT_INTERRUPTIBLE = function(p) StartCast(p, p.cast.channel) end,
	UNIT_SPELLCAST_STOP = function(p) StopCast(p) end,
	UNIT_SPELLCAST_FAILED = function(p) StopCast(p) end,
	UNIT_SPELLCAST_CHANNEL_STOP = function(p) StopCast(p) end,
	UNIT_SPELLCAST_INTERRUPTED = function(p, _, _, _, by) Interrupted(p, by) end, -- unit, castGUID, spellID, interruptedBy
}

-- The few that matter on a friend's plate.
local FRIEND_EVENTS = {
	UNIT_HEALTH = function(p) FriendHealth(p) end,
	UNIT_MAXHEALTH = function(p) FriendHealth(p) end,
	UNIT_FLAGS = function(p) FriendStrip(p) end,
	UNIT_NAME_UPDATE = function(p) UpdateFriend(p) end,
}

local function OnEvent(_, event, unit, ...)
	if event == "NAME_PLATE_UNIT_ADDED" then
		Added(unit)
	elseif event == "NAME_PLATE_UNIT_REMOVED" then
		Removed(unit)
	elseif event == "PLAYER_TARGET_CHANGED" then
		TargetChanged()
	elseif event == "PLAYER_SOFT_ENEMY_CHANGED" or event == "PLAYER_SOFT_FRIEND_CHANGED" or event == "PLAYER_SOFT_INTERACT_CHANGED" then
		P.UpdateSoftTargets()
	elseif event == "RAID_TARGET_UPDATE" then
		for _, p in pairs(byUnit) do UpdateRaid(p) end
	elseif event == "QUEST_LOG_UPDATE" then
		for _, p in pairs(byUnit) do
			p.questKnown = nil
			UpdateQuest(p)
		end
		C_Timer.After(0.3, AdoptAllQuestie) -- after Questie has redrawn its icons
	elseif event == "UNIT_THREAT_SITUATION_UPDATE" or event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
		for _, p in pairs(byUnit) do UpdateThreat(p) end
		if event == "PLAYER_REGEN_ENABLED" then P.FillPool(Opt().pool or 20) end
	elseif event == "PLAYER_ENTERING_WORLD" then
		P.FillPool(Opt().pool or 20)
	else
		local p = unit and byUnit[unit]
		local fn = p and (p.friend and FRIEND_EVENTS or UNIT_EVENTS)[event]
		if fn then fn(p, unit, ...) end
	end
end

-- The cast spark rides the fill; a plain-timed cast (no duration object) runs here too.
local function OnUpdate()
	local now = GetTime() * 1000
	for _, p in pairs(byUnit) do
		local cast = p.cast
		if cast:IsShown() and cast.startMS and cast.endMS and not cast.holdUntil then
			local v = cast.channel and (cast.endMS - (now - cast.startMS)) or now
			cast.bar:SetValue(v)
			cast.grey:SetValue(v)
			if now >= cast.endMS then cast:Hide() end
		end
	end
end

function P.Init()
	if P.inited then return end
	P.inited = true
	if not C_NamePlate or not C_NamePlate.GetNamePlateForUnit then return end
	local conflict = P.Conflict()
	if conflict and Opt().enabled ~= false then
		ns.Print(("SanctuaryUI nameplates stay off while %s is on (turn one of them off)."):format(conflict))
	end
	active = P.Enabled()
	if not active then return end
	P.hasTarget = UnitExists("target") and true or false
	for _, e in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_TARGET_CHANGED",
		"RAID_TARGET_UPDATE", "QUEST_LOG_UPDATE", "UNIT_THREAT_SITUATION_UPDATE", "PLAYER_REGEN_ENABLED",
		"PLAYER_REGEN_DISABLED", "PLAYER_ENTERING_WORLD" }) do
		pcall(driver.RegisterEvent, driver, e)
	end
	for e in pairs(UNIT_EVENTS) do pcall(driver.RegisterEvent, driver, e) end
	pcall(driver.RegisterEvent, driver, "UNIT_FLAGS")
	for _, e in ipairs({ "PLAYER_SOFT_ENEMY_CHANGED", "PLAYER_SOFT_FRIEND_CHANGED", "PLAYER_SOFT_INTERACT_CHANGED" }) do
		pcall(driver.RegisterEvent, driver, e)
	end
	driver:SetScript("OnEvent", OnEvent)
	driver:SetScript("OnUpdate", OnUpdate)
	P.FillPool(Opt().pool or 20)
	-- Questie redraws its icons through these (called on its module table, so they can be hooked).
	if QuestieLoader and QuestieLoader.ImportModule then
		local ok, QN = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieNameplate")
		if ok and type(QN) == "table" then
			for _, method in ipairs({ "UpdateNameplate", "RedrawIcons" }) do
				if type(QN[method]) == "function" then hooksecurefunc(QN, method, AdoptAllQuestie) end
			end
		end
	end
	-- Plates already up (a reload).
	for _, plate in ipairs(C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates() or {}) do
		local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
		if unit and not Secret(unit) then Added(unit) end
	end
end

---------------------------------------------------------------------------
-- Settings

StaticPopupDialogs["SANCTUARYUI_PLATES_RELOAD"] = {
	text = "Turning SanctuaryUI's nameplates on or off needs a reload.",
	button1 = "Reload now",
	button2 = "Later",
	OnAccept = function() ReloadUI() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

function P.ApplySettings()
	if not P.inited then return end
	if P.Enabled() ~= active then
		StaticPopup_Show("SANCTUARYUI_PLATES_RELOAD")
		return
	end
	for _, p in pairs(objs) do Layout(p) end
	local live = {}
	for unit in pairs(byUnit) do live[#live + 1] = unit end
	for _, unit in ipairs(live) do
		Removed(unit, true)
		Added(unit)
	end
	for _, p in ipairs(preview.plates) do Layout(p) end
	if P.preview then P.DrawPreview() end
end

---------------------------------------------------------------------------
-- Preview: a made-up pull in the middle of the screen, looping

local PACK = {
	{ name = "Defias Pillager", level = 18, rank = "normal", x = -230, y = 70, hp = 0.82, cast = { "Fireball", 2.2, you = true, icon = "Interface\\Icons\\Spell_Fire_FlameBolt" } },
	{ name = "Defias Overseer", level = 19, rank = "normal", x = 0, y = 95, hp = 0.64, target = true, raid = 8 },
	{ name = "Young Stranglethorn Tiger", level = 31, rank = "normal", x = 230, y = 70, hp = 0.55, quest = true, threat = "aggro" },
	{ name = "Defias Taskmaster", level = 19, rank = "normal", x = -230, y = -10, hp = 0.16 },
	{ name = "Defias Evoker", level = 19, rank = "normal", x = 0, y = -10, hp = 0.9, cast = { "Shadow Bolt", 3, locked = true, icon = "Interface\\Icons\\Spell_Shadow_ShadowBolt" } },
	{ name = "Defias Watchman", level = 18, rank = "normal", x = 230, y = -10, hp = 0.7, threat = "warn" },
	{ name = "Sneed", level = 20, rank = "elite", x = -150, y = -90, hp = 0.73 },
	{ name = "Foreman Thistlenettle", level = -1, rank = "rare", x = 150, y = -90, hp = 0.55 },
	{ name = "Edwin VanCleef", level = -1, rank = "boss", x = 0, y = -165, hp = 0.62 },
	{ name = "Wu Shen", friend = true, guild = "Warrior Trainer", detail = "Level 60 · Stormwind", x = -380, y = -165, hp = 1 },
	{ name = "Brakka", friend = true, class = "WARRIOR", guild = "The Rethiadians", x = 380, y = -165, hp = 0.6 },
}

local holder
local function PreviewTick(_, elapsed)
	preview.t = (preview.t or 0) + elapsed
	for i, p in ipairs(preview.plates) do
		local d = PACK[i]
		if not d.friend then
		-- A hit every ~1.6 s, staggered; back to full once empty.
		p.demoT = (p.demoT or i * 0.37) + elapsed
		if p.demoT > 1.6 then
			p.demoT = 0
			p.demoHP = p.demoHP - 0.07
			if p.demoHP <= 0.02 then
				BurstAt(p)
				p.demoHP = 1
			end
			p.health:SetValue(p.demoHP)
			p.execute:SetValue(p.demoHP)
			p.execute:SetAlpha((Opt().execute ~= false and p.demoHP * 100 <= (Opt().executeAt or 20)) and 1 or 0)
			if Opt().hitFlash ~= false then
				p.flashAnim:Stop()
				p.flashAnim:Play()
			end
			if ShowPercent(p) then p.pct:SetFormattedText("%d%%", p.demoHP * 100) end
			if Opt().trail == false or p.demoHP == 1 then
				p.trail:SetValue(p.demoHP)
			else
				C_Timer.After(TRAIL_HOLD, function()
					if P.preview then p.trail:SetValue(p.demoHP) end
				end)
			end
		end
		-- Casts loop.
		if d.cast and Opt().cast ~= false then
			local length = d.cast[2]
			local t = (preview.t + i) % (length + 1.2)
			local cast = p.cast
			if t < length then
				if not cast:IsShown() then
					cast.text:SetText(d.cast[1])
					cast.icon:SetTexture(d.cast.icon)
					cast.text:SetTextColor(0.94, 0.9, 0.82)
					cast.bar:SetStatusBarColor(1, 0.6, 0.16, 1)
					cast.grey:SetAlpha(d.cast.locked and 1 or 0)
					cast.lock:SetAlpha(d.cast.locked and 1 or 0)
					local castTarget = Opt().castTarget ~= false
					cast.you:SetAlpha((castTarget and d.cast.you) and 1 or 0)
					cast.who:SetText((castTarget and not d.cast.you) and "» Brakka" or "")
					cast.who:SetAlpha(1)
					cast.spark:SetAlpha(0.9)
					cast:Show()
				end
				cast.bar:SetValue(t / length)
				cast.grey:SetValue(t / length)
			else
				cast:Hide()
			end
		else
			p.cast:Hide()
		end
		end
	end
end

function P.DrawPreview()
	if not holder then
		holder = CreateFrame("Frame", "SanctuaryUIPlatesPreview", UIParent)
		holder:SetSize(1, 1)
		holder:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
		holder:SetFrameStrata("MEDIUM")
		holder:SetScript("OnUpdate", PreviewTick)
	end
	for i, d in ipairs(PACK) do
		local p = preview.plates[i]
		if not p then
			p = NewPlate(holder)
			preview.plates[i] = p
		end
		p.rank = d.rank
		p.friend = d.friend or false
		p.isTarget = d.target or false
		Layout(p)
		p.root:ClearAllPoints()
		p.root:SetPoint("CENTER", holder, "CENTER", d.x, d.y)
		if d.friend then
			p.name:SetText(d.name)
			local cc = d.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[d.class]
			local c = cc and { cc.r, cc.g, cc.b } or FRIEND_NAME
			p.name:SetTextColor(c[1], c[2], c[3])
			local sub = {}
			if d.guild then sub[#sub + 1] = "<" .. d.guild .. ">" end
			if d.detail and Opt().friendlyDetails ~= false then sub[#sub + 1] = d.detail end
			p.guild:SetText(table.concat(sub, "\n"))
			p.health:SetStatusBarTexture(ns.Art.Path("unitFillWhite") or "Interface\\Buttons\\WHITE8X8")
			local f = cc and c or FRIEND_FILL
			p.health:SetStatusBarColor(f[1], f[2], f[3], 1)
			p.health:SetMinMaxValues(0, 1)
			p.health:SetValue(d.hp)
			p.health:SetAlpha(d.hp < 1 and 1 or 0)
			p.slot:SetAlpha(d.hp < 1 and 1 or 0)
			p.raid:Hide()
			ApplyTarget(p)
			p.root:Show()
		else
		p.name:SetText(d.name)
		P.FitNameFont(p, d.name)
		local c = P.NameColor(d.rank, 2)
		p.name:SetTextColor(c[1], c[2], c[3])
		if Opt().showLevel == false then
			p.level:SetText("")
		elseif d.level < 0 then
			p.level:SetText("??")
			p.level:SetTextColor(1, 0.25, 0.15)
		else
			p.level:SetText(d.level)
			p.level:SetTextColor(1, 0.82, 0.25)
		end
		p.demoHP = d.hp
		for _, bar in ipairs({ p.health, p.trail, p.execute }) do
			bar:SetMinMaxValues(0, 1)
			bar:SetValue(d.hp)
		end
		local mode = Opt().healthColor or "d3"
		local tint = (mode == "custom" and (Opt().healthRGB or { 0.8, 0.1, 0.1 })) or (mode == "reaction" and FILL.hostile) or nil
		if tint then
			p.health:SetStatusBarTexture(ns.Art.Path("unitFillWhite") or "Interface\\Buttons\\WHITE8X8")
			p.health:SetStatusBarColor(tint[1], tint[2], tint[3], 1)
		else
			p.health:SetStatusBarTexture(ns.Art.Path("unitFill") or "Interface\\Buttons\\WHITE8X8")
			p.health:SetStatusBarColor(1, 1, 1, 1)
		end
		p.execute:SetAlpha((Opt().execute ~= false and d.hp * 100 <= (Opt().executeAt or 20)) and 1 or 0)
		if d.raid and Opt().raidIcon ~= false and SetRaidTargetIconTexture then
			SetRaidTargetIconTexture(p.raid, d.raid)
			p.raid:Show()
		else
			p.raid:Hide()
		end
		p.quest:SetShown(d.quest and Opt().quest ~= false or false)
		local color = Opt().threat ~= false and d.threat and THREAT[d.threat]
		if color then
			p.threat:SetVertexColor(color[1], color[2], color[3])
			p.threat:SetAlpha(0.95)
		else
			p.threat:SetAlpha(0)
		end
		P.hasTarget = true
		ApplyTarget(p)
		if ShowPercent(p) then p.pct:SetFormattedText("%d%%", d.hp * 100) else p.pct:SetText("") end
		p.cast:Hide()
		p.root:Show()
		end
	end
	holder:Show()
end

function P.SetPreview(on)
	P.preview = on and true or nil
	if on then
		P.DrawPreview()
	elseif holder then
		holder:Hide()
		P.hasTarget = UnitExists("target") and true or false
	end
	ns.Print(on and "nameplate preview on (/sanctuary plates again to turn off)" or "nameplate preview off")
end
