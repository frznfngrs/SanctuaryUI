SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.CastRail = ns.CastRail or {}
local C = ns.CastRail

-- Your casts (Options > Combat > Cast bar), shown on the console's XP rail, on a bar of their
-- own, or both. One cast drives every view the same way:
--   rail (mockups/cast-rail-a.png, cast-louder-rail.png): the XP fill fades and a molten fill runs
--     through the rail's ten segments with a spark and a trail at its head and an ember haze past
--     the rail's lips; the spell's name and the time left sit either side of the skull on dark
--     plates; the level medallion turns into the spell's icon with a clockwise sweep.
--   bar (mockups/cast-own-bar.png): D3's Paragon bar (the icon sweeping in its spiked ring) or its
--     ram-skull boss bar, filled with D3's lava; movable and sizable.
-- A cast that lands flares white-gold; one interrupted turns red where it stopped; channels drain
-- in a cold blue. Blizzard's own cast bar is switched off while this is on (Blizzard.lua CastBar).
--
-- Your own cast is read like the party frames read theirs (Party.lua): plain start and end times
-- when the client gives them, else the client runs the bar from a duration object.

local FILL = { 1, 0.67, 0.24 } -- molten amber
local CHANNEL = { 0.59, 0.75, 1 } -- cold blue
local RED = { 0.9, 0.18, 0.12 }
local FLASH = { 1, 0.92, 0.67 }
local GOLD = { 0.98, 0.86, 0.59 }
local NAME_RIGHT, TIME_LEFT = 700, 866 -- sheet px: the name ends left of the skull's crest, the time starts right of it
local FADE_IN, FADE_OUT = 0.12, 0.35
local HOLD_FLASH, HOLD_FAILED = 0.12, 0.6
local ICON_SHARE = 0.78 -- the medallion's red disc, of its width
local ROUND_MASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local WHITE = "Interface\\Buttons\\WHITE8X8"

local Secret = ns.Secret
local function Readable(v) return v ~= nil and not Secret(v) and type(v) == "number" end

local rail, own -- the views
local driver
-- phase: nil (idle), "cast", "flash", "failed". cur: what's running.
local phase, cur
local alpha, phaseAt = 0, 0 -- the takeover's alpha (the rail's XP and level fade by 1 - alpha); when the phase began

local function Opt() return ns.DB() end
local function BarOpt() return ns.DB().castBar end
local function On() return Opt().castRail ~= false end
local function MedalOn() return Opt().castMedallion ~= false end
local function Where() return Opt().castWhere or "rail" end
local function RailOn() local w = Where() return w == "rail" or w == "both" end
local function BarOn() local w = Where() return w == "bar" or w == "both" end

-- The views a cast shows on now.
local function Views()
	local list = {}
	if rail and RailOn() then list[#list + 1] = rail end
	if own and BarOn() then list[#list + 1] = own end
	return list
end

---------------------------------------------------------------------------
-- Reading your cast

local function ReadCast(channel)
	if channel then
		if not UnitChannelInfo then return end
		local name, _, texture, startMS, endMS, _, _, spellID = UnitChannelInfo("player")
		return name, texture, startMS, endMS, spellID
	end
	if not UnitCastingInfo then return end
	local name, _, texture, startMS, endMS, _, _, _, spellID = UnitCastingInfo("player")
	return name, texture, startMS, endMS, spellID
end

-- Does an event's castGUID belong to the cast showing? strict: an unreadable one doesn't.
local function Matches(guid, strict)
	if not cur then return false end
	if guid == nil or Secret(guid) or cur.guid == nil or Secret(cur.guid) then return not strict end
	return guid == cur.guid
end

---------------------------------------------------------------------------
-- Drawing

local function Paint(tex, c, a)
	tex:SetVertexColor(c[1], c[2], c[3], a or 1)
end

local function Glow(parent, layer, sub)
	local t = parent:CreateTexture(nil, layer or "OVERLAY", nil, sub)
	t:SetTexture(ns.Art.Path("mote") or WHITE)
	t:SetBlendMode("ADD")
	return t
end

-- How far the bar has run, 0-1, when that can be read.
local function Progress()
	if not cur then return end
	if cur.startMS and cur.endMS then
		local now = GetTime() * 1000
		local span = math.max(1, cur.endMS - cur.startMS)
		local p = (now - cur.startMS) / span
		p = math.max(0, math.min(1, p))
		return cur.channel and 1 - p or p
	end
	local v = Views()[1]
	if not v then return end
	local bar = v.bar
	local ok, value = pcall(bar.GetValue, bar)
	local ok2, low, high = pcall(bar.GetMinMaxValues, bar)
	if ok and ok2 and Readable(value) and Readable(low) and Readable(high) and high > low then
		return math.max(0, math.min(1, (value - low) / (high - low)))
	end
end

local function SetTimeText(fs)
	if not cur then return end
	if cur.startMS and cur.endMS then
		local left = math.max(0, (cur.endMS - GetTime() * 1000) / 1000)
		fs:SetFormattedText("%.1f", left)
		return
	end
	local d = cur.duration
	if d and d.GetRemainingDuration then
		local ok, left = pcall(d.GetRemainingDuration, d)
		if ok and left ~= nil and pcall(fs.SetFormattedText, fs, "%.1f", left) then return end
	end
	fs:SetText("")
end

local function ApplyAlpha(a)
	alpha = a
	for _, v in ipairs({ rail, own }) do
		if v then
			for _, f in ipairs(v.fades) do f:SetAlpha(a) end
		end
	end
	local rest = RailOn() and 1 - a or 1
	if ns.ExperienceBar then ns.ExperienceBar:SetAlpha(rest) end
	if ns.LevelPlaque then ns.LevelPlaque:SetAlpha((RailOn() and MedalOn()) and rest or 1) end
end

local function HideAll()
	for _, v in ipairs({ rail, own }) do
		if v then
			for _, f in ipairs(v.frames) do f:Hide() end
		end
	end
end

local function Idle()
	phase, cur = nil, nil
	HideAll()
	ApplyAlpha(0)
	if own and C.unlocked then own.frame:Show() end -- placed while frames are unlocked
end

local function OnUpdate(_, elapsed)
	local now = GetTime()
	local since = now - phaseAt
	if phase == "cast" then
		if alpha < 1 then ApplyAlpha(math.min(1, alpha + elapsed / FADE_IN)) end
		local t = now * 1000
		for _, v in ipairs(Views()) do
			if cur.startMS and cur.endMS then
				v.bar:SetValue(cur.channel and (cur.endMS - (t - cur.startMS)) or t)
			end
			SetTimeText(v.time)
			-- A pulse in the spark, as D3's bars breathe.
			v.core:SetAlpha(0.75 + 0.25 * math.sin(now * 14))
		end
		if cur.demo and cur.endMS and t >= cur.endMS then C.Finish(cur.demo.ends) end
	elseif phase == "flash" or phase == "failed" then
		local hold = phase == "flash" and HOLD_FLASH or HOLD_FAILED
		if since > hold then
			local a = 1 - (since - hold) / FADE_OUT
			if a <= 0 then
				Idle()
				if C.preview then C.NextDemo() end
				return
			end
			ApplyAlpha(math.min(alpha, a))
		end
	elseif C.preview and C.demoAt and now >= C.demoAt then
		C.demoAt = nil
		C.StartDemo()
	end
end

local function ShowView(v, name, texture, channel)
	v.SetFill(channel)
	v.bar:Show()
	v.still:Hide()
	if v.bloom then v.bloom:Hide() end
	Paint(v.spark, channel and CHANNEL or { 1, 0.86, 0.6 }, 0.95)
	v.spark:Show()
	v.core:Show()
	if v.trail then
		Paint(v.trail, channel and CHANNEL or { 1, 0.63, 0.24 }, 0.8)
		v.trail:SetShown(v.trailOn())
	end
	if v.haze then
		Paint(v.haze, channel and CHANNEL or { 1, 0.47, 0.08 }, 0.55)
		v.haze:SetShown(Opt().castHaze ~= false)
	end
	if not pcall(v.name.SetText, v.name, name) then v.name:SetText("") end
	v.name:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	v.time:Show()
	local medal = v.medal
	if medal then
		medal:SetShown(v.medalOn())
		medal.icon:SetVertexColor(1, 1, 1)
		if not pcall(medal.icon.SetTexture, medal.icon, ns.Or(texture, 136243)) then medal.icon:SetTexture(136243) end
		medal.cd:SetReverse(channel and true or false)
	end
	for _, f in ipairs(v.frames) do f:Show() end
end

local function ShowCast(name, texture, channel)
	HideAll()
	for _, v in ipairs(Views()) do ShowView(v, name, texture, channel) end
end

-- Time each view's bar, its medallion's sweep and the time text from the cast as the client
-- gives it.
local function TimeCast(startMS, endMS)
	local channel = cur.channel
	local views = Views()
	if Readable(startMS) and Readable(endMS) and endMS > startMS then
		cur.startMS, cur.endMS, cur.duration = startMS, endMS, nil
		for _, v in ipairs(views) do
			v.bar:SetMinMaxValues(startMS, endMS)
			if v.medal then v.medal.cd:SetCooldown(startMS / 1000, (endMS - startMS) / 1000) end
		end
		return
	end
	cur.startMS, cur.endMS = nil, nil
	local duration
	if channel then
		duration = UnitChannelDuration and UnitChannelDuration("player")
	else
		duration = UnitCastingDuration and UnitCastingDuration("player")
	end
	cur.duration = duration
	for _, v in ipairs(views) do
		local bar = v.bar
		if duration ~= nil and bar.SetTimerDuration then
			local directions = Enum and Enum.StatusBarTimerDirection
			local direction = directions and (channel and directions.RemainingTime or directions.ElapsedTime)
			local smoothing = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate
			bar:SetTimerDuration(duration, smoothing, direction)
			if v.medal and v.medal.cd.SetCooldownFromDurationObject then
				pcall(v.medal.cd.SetCooldownFromDurationObject, v.medal.cd, duration)
			end
		else
			-- Nothing to time it by: full until the stop event.
			bar:SetMinMaxValues(0, 1)
			bar:SetValue(1)
			if v.medal then v.medal.cd:Clear() end
		end
	end
end

function C.Start(channel, guid)
	if not rail or not On() then return end
	local name, texture, startMS, endMS = ReadCast(channel)
	if not Secret(name) and not name then return end
	cur = { channel = channel, guid = guid }
	if phase ~= "cast" then phaseAt = GetTime() end
	phase = "cast"
	ShowCast(name, texture, channel)
	TimeCast(startMS, endMS)
end

-- Pushback, or a channel's new end.
function C.Update()
	if phase ~= "cast" or not cur or cur.demo then return end
	local _, _, startMS, endMS = ReadCast(cur.channel)
	TimeCast(startMS, endMS)
end

-- how: "flash" (it landed), "interrupted", "failed", or "quiet" (a channel ran out, or was let go).
function C.Finish(how)
	if phase ~= "cast" or not cur then return end
	local p = (how == "interrupted" or how == "failed") and (Progress() or 1) or nil
	for _, v in ipairs(Views()) do
		local still = v.still
		if p then
			-- Frozen where the fill stood (a channel's fill is what was left of it).
			still:ClearAllPoints()
			still:SetPoint("TOPLEFT", v.slot, "TOPLEFT")
			still:SetPoint("BOTTOMLEFT", v.slot, "BOTTOMLEFT")
			still:SetWidth(math.max(1, v.slotW * p))
			Paint(still, RED)
			still:Show()
			v.bar:Hide()
			v.name:SetText(how == "failed" and (FAILED or "Failed") or (INTERRUPTED or "Interrupted"))
			v.name:SetTextColor(0.92, 0.27, 0.2)
			if v.medal then v.medal.icon:SetVertexColor(1, 0.35, 0.3) end
		elseif how == "flash" then
			still:ClearAllPoints()
			still:SetAllPoints(v.slot)
			Paint(still, FLASH)
			still:Show()
			if v.bloom then v.bloom:Show() end -- and a soft glow spilling over the edges
			v.bar:Hide()
		else
			still:Hide()
		end
		v.spark:Hide()
		v.core:Hide()
		if v.trail then v.trail:Hide() end
		if v.haze then v.haze:Hide() end
		v.time:Hide()
		if v.medal then v.medal.cd:Clear() end
	end
	phase = p and "failed" or "flash" -- "quiet" fades the same way, without the flare
	phaseAt = GetTime()
end

---------------------------------------------------------------------------
-- Preview: a cast that lands, one interrupted, and a channel, looping.

local DEMOS = {
	{ name = "Flash of Light", icon = "Interface\\Icons\\Spell_Holy_FlashHeal", seconds = 1.5, ends = "flash" },
	{ name = "Frostbolt", icon = "Interface\\Icons\\Spell_Frost_FrostBolt02", seconds = 2.5, ends = "interrupted", cut = 0.6 },
	{ name = "Arcane Missiles", icon = "Interface\\Icons\\Spell_Nature_StarFall", seconds = 3, channel = true, ends = "quiet" },
}
local demoIndex = 0

function C.StartDemo()
	if not rail then return end
	demoIndex = demoIndex % #DEMOS + 1
	local d = DEMOS[demoIndex]
	local now = GetTime() * 1000
	local length = d.seconds * 1000
	cur = { channel = d.channel, demo = d, startMS = now, endMS = now + length }
	phase, phaseAt = "cast", GetTime()
	ShowCast(d.name, d.icon, d.channel)
	for _, v in ipairs(Views()) do
		v.bar:SetMinMaxValues(now, now + length)
		if v.medal then v.medal.cd:SetCooldown(now / 1000, d.seconds) end
	end
	if d.cut then
		-- Interrupted part way.
		C_Timer.After(d.seconds * d.cut, function()
			if cur and cur.demo == d and phase == "cast" then C.Finish("interrupted") end
		end)
	end
end

function C.NextDemo()
	C.demoAt = GetTime() + 0.8
end

function C.SetPreview(on)
	C.preview = on and true or nil
	if not rail then return end
	if on then
		demoIndex = 0
		C.StartDemo()
	else
		C.demoAt = nil
		if not cur or cur.demo then Idle() end
	end
	ns.Print(on and "cast bar preview on (/sanctuary cast again to turn off)" or "cast bar preview off")
end

---------------------------------------------------------------------------
-- The rail view

local function RailFonts()
	local size = Opt().castTextSize or 13
	ns.Fonts.Set(rail.name, "title", size, "OUTLINE")
	ns.Fonts.Set(rail.time, "body", size, "OUTLINE")
	local plates = Opt().castPlates ~= false
	rail.namePlate:SetShown(plates)
	rail.timePlate:SetShown(plates)
end

local function LayoutRail()
	local cluster = ns.Cluster
	local metrics = ns.Metrics and ns.Metrics()
	if not rail or not cluster or not metrics then return end
	local r = metrics.rail
	local base = cluster:GetFrameLevel()
	local holder, top = rail.holder, rail.top
	holder:SetSize(r.w, r.h)
	holder:ClearAllPoints()
	holder:SetPoint("CENTER", cluster, "BOTTOM", r.x, metrics.baseY + r.y)
	holder:SetFrameLevel(base + ns.LEVEL.rail)
	rail.bar:SetAllPoints(holder)
	rail.bar:SetFrameLevel(base + ns.LEVEL.rail)
	rail.slotW = r.w
	top:SetAllPoints(cluster)
	top:SetFrameLevel(base + ns.LEVEL.console + 1)

	local h = r.h
	rail.bloom:SetSize(r.w * 1.04, h * 5)
	rail.spark:SetSize(h * 7, h * 3.2)
	rail.core:SetSize(h * 2.6, h * 2)
	rail.trail:SetSize(h * 22, h * 2)
	-- The haze runs from the rail's start to the fill's head, bleeding past the rail's lips.
	rail.haze:ClearAllPoints()
	rail.haze:SetPoint("TOPLEFT", holder, "TOPLEFT", -h, h * 1.6)
	rail.haze:SetPoint("BOTTOMRIGHT", rail.bar:GetStatusBarTexture(), "BOTTOMRIGHT", h, -h * 1.6)

	local scale = metrics.width / ns.TEX_W
	local function X(tx) return (tx / ns.TEX_W - 0.5) * metrics.width end
	local railTop = metrics.baseY + r.y + r.h / 2 + 3 * scale
	RailFonts()
	rail.name:ClearAllPoints()
	rail.name:SetPoint("BOTTOMRIGHT", cluster, "BOTTOM", X(NAME_RIGHT), railTop)
	rail.time:ClearAllPoints()
	rail.time:SetPoint("BOTTOMLEFT", cluster, "BOTTOM", X(TIME_LEFT), railTop)

	local spot = metrics.levelPlaque
	local medal = rail.medal
	if medal and spot then
		medal:SetSize(spot.w, spot.h)
		medal:ClearAllPoints()
		medal:SetPoint("CENTER", cluster, "BOTTOM", spot.x, metrics.baseY + spot.y)
		local inner = spot.w * ICON_SHARE
		medal.icon:SetSize(inner, inner)
		medal.mask:SetSize(inner, inner)
		medal.cd:SetSize(inner, inner)
	end
end

-- A dark plate behind a text, following its size (a FontString sizes itself to its text).
local function Plate(parent, fs)
	local t = parent:CreateTexture(nil, "OVERLAY", nil, -1)
	t:SetColorTexture(0.04, 0.025, 0.015, 0.68)
	t:SetPoint("TOPLEFT", fs, "TOPLEFT", -6, 3)
	t:SetPoint("BOTTOMRIGHT", fs, "BOTTOMRIGHT", 6, -3)
	return t
end

local function Medal(parent, art)
	local medal = CreateFrame("Frame", nil, parent)
	if art then
		medal.art = medal:CreateTexture(nil, "ARTWORK")
		medal.art:SetAllPoints()
		if ns.Art.Apply(medal.art, "levelMedallion") then
			medal.art:SetTexCoord(5 / 128, 125 / 128, 4 / 128, 124 / 128) -- as Experience.lua crops it
		else
			medal.art:SetColorTexture(0.25, 0.03, 0.03, 0.9)
		end
	end
	medal.icon = medal:CreateTexture(nil, "ARTWORK", nil, 1)
	medal.icon:SetPoint("CENTER", medal, "CENTER", 0, 0)
	medal.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	medal.mask = medal:CreateMaskTexture()
	medal.mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	medal.mask:SetPoint("CENTER", medal.icon, "CENTER")
	medal.icon:AddMaskTexture(medal.mask)
	medal.cd = CreateFrame("Cooldown", nil, medal, "CooldownFrameTemplate")
	medal.cd:SetPoint("CENTER", medal.icon, "CENTER")
	medal.cd:SetSwipeTexture(ROUND_MASK)
	medal.cd:SetSwipeColor(0, 0, 0, 0.6)
	medal.cd:SetDrawEdge(false)
	medal.cd:SetDrawBling(false)
	medal.cd:SetHideCountdownNumbers(true)
	if medal.cd.SetUseCircularEdge then medal.cd:SetUseCircularEdge(true) end
	return medal
end

local function BuildRail()
	local cluster = ns.Cluster
	local v = {}
	local holder = CreateFrame("Frame", "SanctuaryUICastRail", cluster)
	holder:Hide()
	v.holder, v.slot = holder, holder
	local bar = CreateFrame("StatusBar", nil, holder)
	bar:SetStatusBarTexture(ns.Art.Path("xpWhite") or WHITE)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0)
	v.bar = bar
	v.still = holder:CreateTexture(nil, "ARTWORK")
	v.still:SetTexture(ns.Art.Path("xpWhite") or WHITE)
	v.still:Hide()

	local top = CreateFrame("Frame", nil, cluster)
	top:Hide()
	v.top = top
	-- Over the console art, so the light spills past the rail's lips.
	v.haze = Glow(top, "OVERLAY", -2)
	v.trail = Glow(top, "OVERLAY", -1)
	v.trail:SetPoint("RIGHT", bar:GetStatusBarTexture(), "RIGHT", 6, 0)
	v.spark = Glow(top, "OVERLAY")
	v.spark:SetPoint("CENTER", bar:GetStatusBarTexture(), "RIGHT")
	v.core = Glow(top, "OVERLAY", 1)
	v.core:SetVertexColor(1, 1, 0.92)
	v.core:SetPoint("CENTER", bar:GetStatusBarTexture(), "RIGHT")
	v.bloom = Glow(top, "OVERLAY")
	v.bloom:SetVertexColor(1, 0.8, 0.45, 0.8)
	v.bloom:SetPoint("CENTER", holder, "CENTER")
	v.bloom:Hide()

	v.name = top:CreateFontString(nil, "OVERLAY")
	ns.Fonts.Set(v.name, "title", 13, "OUTLINE")
	v.name:SetJustifyH("RIGHT")
	v.name:SetShadowOffset(0, 0)
	v.time = top:CreateFontString(nil, "OVERLAY")
	ns.Fonts.Set(v.time, "body", 13, "OUTLINE")
	v.time:SetJustifyH("LEFT")
	v.time:SetTextColor(0.92, 0.92, 0.92)
	v.time:SetShadowOffset(0, 0)
	v.namePlate = Plate(top, v.name)
	v.timePlate = Plate(top, v.time)

	-- The level medallion's double, wearing the spell's icon on its red disc.
	v.medal = Medal(top, true)
	v.medalOn = MedalOn
	v.trailOn = function() return Opt().castHaze ~= false end

	function v.SetFill(channel)
		local fill = channel and CHANNEL or FILL
		bar:SetStatusBarColor(fill[1], fill[2], fill[3], 1)
	end
	v.frames, v.fades = { holder, top }, { holder, top }
	holder:SetScript("OnHide", function()
		-- Hidden with its parent (the console hidden): the rail gets its XP back.
		if not phase then ApplyAlpha(0) end
	end)
	return v
end

---------------------------------------------------------------------------
-- The bar of its own

local function BarFonts()
	local size = BarOpt().textSize or 12
	ns.Fonts.Set(own.name, "title", size, "OUTLINE")
	ns.Fonts.Set(own.time, "body", size, "OUTLINE")
end

local function LayoutBar()
	if not own then return end
	local o = BarOpt()
	local style = o.style == "demon" and "demon" or "paragon"
	local g = ns.Art.CAST_BARS[style]
	local width = o.width or (style == "demon" and 300 or 340)
	local k = width / g[3]
	local f = own.frame
	f:SetScale(o.scale or 1)
	f:SetSize(width, g[4] * k)
	f:ClearAllPoints()
	if o.moved then
		f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", ns.MovedPoint(f, o))
	else
		-- Centred above the console, clear of a docked bar.
		local cluster, metrics = ns.Cluster, ns.Metrics and ns.Metrics()
		if cluster and metrics then
			local r = metrics.rail
			local k2 = cluster:GetEffectiveScale() / f:GetEffectiveScale()
			f:SetPoint("BOTTOM", cluster, "BOTTOM", 0, (metrics.baseY + r.y + r.h / 2 + 70) * k2)
		else
			f:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 260)
		end
	end
	own.art:SetTexCoord(g[1] / 1024, (g[1] + g[3]) / 1024, g[2] / 256, (g[2] + g[4]) / 256)
	local b = g.bar
	local sx, sy, sw, sh = b[1] * k, b[2] * k, b[3] * k, b[4] * k
	own.slotW = sw
	local slot = own.slot
	slot:ClearAllPoints()
	slot:SetPoint("TOPLEFT", f, "TOPLEFT", sx, -sy)
	slot:SetSize(sw, sh)
	own.bar:ClearAllPoints()
	own.bar:SetAllPoints(slot)
	own.spark:SetSize(sh * 3.4, sh * 2.2)
	own.core:SetSize(sh * 1.4, sh * 1.2)
	own.trail:SetSize(sh * 8, sh * 1.1)
	own.bloom:SetSize(sw * 1.05, sh * 3)
	BarFonts()
	own.name:ClearAllPoints()
	own.time:ClearAllPoints()
	own.time:SetPoint("RIGHT", slot, "RIGHT", -6, 0)
	local medal = own.medal
	if style == "paragon" then
		-- The name on the lava, the icon sweeping in the spiked ring.
		own.name:SetPoint("LEFT", slot, "LEFT", 8, 0)
		local ring = g.ring
		local d = ring[3] * 2 * k
		medal:ClearAllPoints()
		medal:SetPoint("CENTER", f, "TOPLEFT", ring[1] * k, -ring[2] * k)
		medal:SetSize(d, d)
		medal.icon:SetSize(d, d)
		medal.mask:SetSize(d, d)
		medal.cd:SetSize(d, d)
	else
		own.name:SetPoint("BOTTOM", slot, "TOP", 0, 3)
	end
	own.style = style
end

local function BuildBar()
	local v = {}
	local f = CreateFrame("Frame", "SanctuaryUICastBar", UIParent)
	f:SetFrameStrata("MEDIUM")
	f:SetClampedToScreen(true)
	f:Hide()
	v.frame = f
	-- Under the art: a dark slot and the lava fill; the art's opened slot shows them.
	local slot = CreateFrame("Frame", nil, f)
	slot:SetFrameLevel(f:GetFrameLevel()) -- the dark slot under the lava, never over it
	v.slot = slot
	local bg = slot:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.04, 0.02, 0.015, 0.95)
	local bar = CreateFrame("StatusBar", nil, f)
	bar:SetFrameLevel(f:GetFrameLevel() + 2)
	-- A texture before anything is pinned to it: GetStatusBarTexture is nil until then, and a
	-- point on nil lands on the screen's edge (the spark glowed at the far right).
	bar:SetStatusBarTexture(ns.Art.Path("castLava") or ns.Art.Path("xpWhite") or WHITE)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0)
	v.bar = bar
	v.still = bar:CreateTexture(nil, "OVERLAY")
	v.still:SetTexture(ns.Art.Path("xpWhite") or WHITE)
	v.still:Hide()
	local over = CreateFrame("Frame", nil, f)
	over:SetAllPoints(f)
	over:SetFrameLevel(f:GetFrameLevel() + 4)
	v.art = over:CreateTexture(nil, "ARTWORK")
	v.art:SetAllPoints(f)
	if not ns.Art.Apply(v.art, "castBars") then v.art:SetColorTexture(0.08, 0.06, 0.05, 0.9) end
	v.trail = Glow(over, "OVERLAY", -1)
	v.trail:SetPoint("RIGHT", bar:GetStatusBarTexture(), "RIGHT", 4, 0)
	v.spark = Glow(over, "OVERLAY")
	v.spark:SetPoint("CENTER", bar:GetStatusBarTexture(), "RIGHT")
	v.core = Glow(over, "OVERLAY", 1)
	v.core:SetVertexColor(1, 1, 0.92)
	v.core:SetPoint("CENTER", bar:GetStatusBarTexture(), "RIGHT")
	v.bloom = Glow(over, "OVERLAY")
	v.bloom:SetVertexColor(1, 0.8, 0.45, 0.8)
	v.bloom:SetPoint("CENTER", slot, "CENTER")
	v.bloom:Hide()
	v.name = over:CreateFontString(nil, "OVERLAY")
	ns.Fonts.Set(v.name, "title", 12, "OUTLINE")
	v.name:SetShadowOffset(0, 0)
	v.time = over:CreateFontString(nil, "OVERLAY")
	ns.Fonts.Set(v.time, "body", 12, "OUTLINE")
	v.time:SetTextColor(0.95, 0.93, 0.88)
	v.time:SetShadowOffset(0, 0)
	v.medal = Medal(over, false)
	v.medal:SetFrameLevel(over:GetFrameLevel() + 1)
	v.medalOn = function() return own.style == "paragon" end
	v.trailOn = function() return true end

	function v.SetFill(channel)
		if channel then
			bar:SetStatusBarTexture(ns.Art.Path("xpWhite") or WHITE)
			bar:SetStatusBarColor(CHANNEL[1], CHANNEL[2], CHANNEL[3], 1)
		else
			bar:SetStatusBarTexture(ns.Art.Path("castLava") or ns.Art.Path("xpWhite") or WHITE)
			bar:SetStatusBarColor(1, 1, 1, 1)
		end
	end
	v.frames, v.fades = { f }, { f }
	v.mover = ns.MakeMover(f, "Cast bar", BarOpt, "Reset its position in /sanctuary > Cast bar.", UIParent)
	return v
end

-- Frames unlocked: the bar shows (empty) where it is, to be placed.
function C.UpdateMovers(unlocked)
	C.unlocked = unlocked and BarOn() and On() or nil
	if not own then return end
	own.mover:SetShown(C.unlocked and true or false)
	if C.unlocked then
		own.frame:Show()
		own.frame:SetAlpha(1)
	elseif not phase then
		own.frame:Hide()
	end
end

function C.ResetBar()
	local o = BarOpt()
	o.moved, o.mx, o.my = false, 0, 0
	LayoutBar()
end

---------------------------------------------------------------------------
-- Layout and settings

function C.Layout()
	LayoutRail()
	LayoutBar()
end

function C.ApplySettings()
	if not rail then return end
	if not On() then
		if C.preview then C.SetPreview(false) end
		Idle()
	end
	HideAll()
	if phase then
		-- Mid-cast: the views in use now carry on.
		for _, v in ipairs(Views()) do
			for _, f in ipairs(v.frames) do f:Show() end
		end
	end
	ApplyAlpha(phase and alpha or 0)
	C.Layout()
	if own and C.unlocked then own.frame:Show() end
end

---------------------------------------------------------------------------

function C.Init()
	if not ns.Cluster or rail then return end
	rail = BuildRail()
	own = BuildBar()
	C.Layout()
	ApplyAlpha(0)
	driver = CreateFrame("Frame", nil, UIParent)
	driver:SetScript("OnUpdate", OnUpdate)

	local events = CreateFrame("Frame", nil, UIParent)
	for _, event in ipairs({
		"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_SUCCEEDED",
		"UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_DELAYED",
		"UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP",
	}) do
		pcall(events.RegisterUnitEvent, events, event, "player")
	end
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:SetScript("OnEvent", function(_, event, _, guid)
		if C.preview then return end
		if event == "UNIT_SPELLCAST_START" then
			C.Start(false, guid)
		elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
			C.Start(true, guid)
		elseif event == "UNIT_SPELLCAST_DELAYED" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
			C.Update()
		elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
			if cur and not cur.channel and Matches(guid, true) then C.Finish("flash") end
		elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
			if Matches(guid, false) then C.Finish("interrupted") end
		elseif event == "UNIT_SPELLCAST_FAILED" then
			-- Also fires for a second spell refused while this one runs: only this cast's own.
			if Matches(guid, true) then C.Finish("failed") end
		elseif event == "UNIT_SPELLCAST_STOP" then
			-- Usually after SUCCEEDED or INTERRUPTED has said how it ended. If neither has by
			-- the next frame, it ended without saying: let it go quietly.
			if cur and not cur.channel and Matches(guid, false) then
				local was = cur
				C_Timer.After(0, function()
					if cur == was and phase == "cast" then C.Finish("quiet") end
				end)
			end
		elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
			if cur and cur.channel then C.Finish("quiet") end
		elseif event == "PLAYER_ENTERING_WORLD" then
			-- A cast going on through a reload.
			if UnitCastingInfo and UnitCastingInfo("player") ~= nil then
				C.Start(false)
			elseif UnitChannelInfo and UnitChannelInfo("player") ~= nil then
				C.Start(true)
			end
		end
	end)
end
