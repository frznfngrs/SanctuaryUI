SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.CastRail = ns.CastRail or {}
local C = ns.CastRail

-- Your casts on the console's XP rail (Options > XP & casting > Casts). While you cast, the XP
-- fill fades out and a molten fill runs left to right through the rail's ten segments, a spark
-- at its head; the spell's name sits left of the centre skull and the time left right of it.
-- The level medallion turns into the spell's icon with a clockwise sweep. A cast that lands
-- flares the whole rail white-gold; one interrupted turns red where it stopped. Channels drain
-- right to left in a cold blue. Blizzard's own cast bar is switched off while this is on
-- (Blizzard.lua CastBar). Mockup: mockups/cast-rail-a.png (A) and cast-rail-bcd.png (C).
--
-- Your own cast is read like the party frames read theirs (Party.lua): plain start and end
-- times when the client gives them, else the client runs the bar from a duration object.

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

local Secret = ns.Secret
local function Readable(v) return v ~= nil and not Secret(v) and type(v) == "number" end

local holder, top, bar, still, bloom, spark, core, nameText, timeText, medal
-- phase: nil (idle), "cast", "flash", "failed". cur: what's running.
local phase, cur
local alpha, phaseAt = 0, 0 -- the takeover's alpha (the rail and level fade by 1 - alpha); when the phase began

local function Opt() return ns.DB() end
local function On() return Opt().castRail ~= false end
local function MedalOn() return Opt().castMedallion ~= false end

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
	local ok, value = pcall(bar.GetValue, bar)
	local ok2, low, high = pcall(bar.GetMinMaxValues, bar)
	if ok and ok2 and Readable(value) and Readable(low) and Readable(high) and high > low then
		return math.max(0, math.min(1, (value - low) / (high - low)))
	end
end

local function SetTimeText()
	if not cur then return end
	if cur.startMS and cur.endMS then
		local left = math.max(0, (cur.endMS - GetTime() * 1000) / 1000)
		timeText:SetFormattedText("%.1f", left)
		return
	end
	local d = cur.duration
	if d and d.GetRemainingDuration then
		local ok, left = pcall(d.GetRemainingDuration, d)
		if ok and left ~= nil and pcall(timeText.SetFormattedText, timeText, "%.1f", left) then return end
	end
	timeText:SetText("")
end

local function ApplyAlpha(a)
	alpha = a
	holder:SetAlpha(a)
	top:SetAlpha(a)
	local rest = 1 - a
	if ns.ExperienceBar then ns.ExperienceBar:SetAlpha(rest) end
	if ns.LevelPlaque then ns.LevelPlaque:SetAlpha(MedalOn() and rest or 1) end
end

local function Idle()
	phase, cur = nil, nil
	holder:Hide()
	top:Hide()
	ApplyAlpha(0)
end

local function OnUpdate(_, elapsed)
	local now = GetTime()
	local since = now - phaseAt
	if phase == "cast" then
		if alpha < 1 then ApplyAlpha(math.min(1, alpha + elapsed / FADE_IN)) end
		if cur.startMS and cur.endMS then
			local t = now * 1000
			bar:SetValue(cur.channel and (cur.endMS - (t - cur.startMS)) or t)
			if cur.demo and t >= cur.endMS then C.Finish(cur.demo.ends) end
		end
		SetTimeText()
		-- A pulse in the spark, as D3's bars breathe.
		core:SetAlpha(0.75 + 0.25 * math.sin(now * 14))
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

local function ShowCast(name, texture, channel)
	local fill = channel and CHANNEL or FILL
	bar:SetStatusBarColor(fill[1], fill[2], fill[3], 1)
	bar:Show()
	still:Hide()
	bloom:Hide()
	Paint(spark, channel and CHANNEL or { 1, 0.86, 0.6 }, 0.95)
	spark:Show()
	core:Show()
	if not pcall(nameText.SetText, nameText, name) then nameText:SetText("") end
	nameText:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	timeText:Show()
	if medal then
		medal:SetShown(MedalOn())
		medal.icon:SetVertexColor(1, 1, 1)
		if not pcall(medal.icon.SetTexture, medal.icon, ns.Or(texture, 136243)) then medal.icon:SetTexture(136243) end
		medal.cd:SetReverse(channel and true or false)
	end
	holder:Show()
	top:Show()
end

-- Time the bar, the medallion's sweep and the time text from the cast as the client gives it.
local function TimeCast(startMS, endMS)
	local channel = cur.channel
	if Readable(startMS) and Readable(endMS) and endMS > startMS then
		cur.startMS, cur.endMS, cur.duration = startMS, endMS, nil
		bar:SetMinMaxValues(startMS, endMS)
		if medal then medal.cd:SetCooldown(startMS / 1000, (endMS - startMS) / 1000) end
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
	if duration ~= nil and bar.SetTimerDuration then
		local directions = Enum and Enum.StatusBarTimerDirection
		local direction = directions and (channel and directions.RemainingTime or directions.ElapsedTime)
		local smoothing = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate
		bar:SetTimerDuration(duration, smoothing, direction)
		if medal and medal.cd.SetCooldownFromDurationObject then
			pcall(medal.cd.SetCooldownFromDurationObject, medal.cd, duration)
		end
	else
		-- Nothing to time it by: full until the stop event.
		bar:SetMinMaxValues(0, 1)
		bar:SetValue(1)
		if medal then medal.cd:Clear() end
	end
end

function C.Start(channel, guid)
	if not holder or not On() then return end
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
	local w = holder:GetWidth()
	if how == "interrupted" or how == "failed" then
		local p = Progress() or 1
		-- Frozen where the fill stood (a channel's fill is what was left of it).
		still:ClearAllPoints()
		still:SetPoint("TOPLEFT", holder, "TOPLEFT")
		still:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT")
		still:SetWidth(math.max(1, w * p))
		Paint(still, RED)
		still:SetBlendMode("BLEND")
		still:Show()
		bar:Hide()
		nameText:SetText(how == "failed" and (FAILED or "Failed") or (INTERRUPTED or "Interrupted"))
		nameText:SetTextColor(0.92, 0.27, 0.2)
		if medal then medal.icon:SetVertexColor(1, 0.35, 0.3) end
		phase = "failed"
	elseif how == "flash" then
		still:ClearAllPoints()
		still:SetAllPoints(holder)
		Paint(still, FLASH)
		still:SetBlendMode("BLEND") -- solid: added light washes out over a bright world behind the rail
		still:Show()
		bloom:Show() -- and a soft glow spilling over the rail's lips
		bar:Hide()
		phase = "flash"
	else
		phase = "flash" -- the same fade, without the flare
		still:Hide()
	end
	spark:Hide()
	core:Hide()
	timeText:Hide()
	if medal then medal.cd:Clear() end
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
	if not holder then return end
	demoIndex = demoIndex % #DEMOS + 1
	local d = DEMOS[demoIndex]
	local now = GetTime() * 1000
	local length = d.seconds * 1000
	cur = { channel = d.channel, demo = d, startMS = now, endMS = now + length }
	phase, phaseAt = "cast", GetTime()
	ShowCast(d.name, d.icon, d.channel)
	bar:SetMinMaxValues(now, now + length)
	if medal then medal.cd:SetCooldown(now / 1000, d.seconds) end
	if d.cut then
		-- Interrupted part way.
		C_Timer.After(d.seconds * d.cut, function()
			if cur and cur.demo == d and phase == "cast" then C.Finish("interrupted") end
		end)
	end
end

function C.NextDemo()
	C.demoAt = GetTime() + 0.8
	holder:Show() -- runs the OnUpdate that starts the next one
	holder:SetAlpha(0)
end

function C.SetPreview(on)
	C.preview = on and true or nil
	if not holder then return end
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
-- Layout and settings

function C.Layout()
	local cluster = ns.Cluster
	local metrics = ns.Metrics and ns.Metrics()
	if not holder or not cluster or not metrics then return end
	local rail = metrics.rail
	local base = cluster:GetFrameLevel()
	holder:SetSize(rail.w, rail.h)
	holder:ClearAllPoints()
	holder:SetPoint("CENTER", cluster, "BOTTOM", rail.x, metrics.baseY + rail.y)
	holder:SetFrameLevel(base + ns.LEVEL.rail)
	bar:SetAllPoints(holder)
	bar:SetFrameLevel(base + ns.LEVEL.rail)
	top:SetAllPoints(cluster)
	top:SetFrameLevel(base + ns.LEVEL.console + 1)

	local h = rail.h
	bloom:SetSize(rail.w * 1.04, h * 5)
	spark:SetSize(h * 7, h * 3.2)
	core:SetSize(h * 2.6, h * 2)

	local scale = metrics.width / ns.TEX_W
	local function X(tx) return (tx / ns.TEX_W - 0.5) * metrics.width end
	local railTop = metrics.baseY + rail.y + rail.h / 2 + 2 * scale
	local size = Opt().castTextSize or 11
	ns.Fonts.Set(nameText, "title", size, "OUTLINE")
	ns.Fonts.Set(timeText, "body", size, "OUTLINE")
	nameText:ClearAllPoints()
	nameText:SetPoint("BOTTOMRIGHT", cluster, "BOTTOM", X(NAME_RIGHT), railTop)
	timeText:ClearAllPoints()
	timeText:SetPoint("BOTTOMLEFT", cluster, "BOTTOM", X(TIME_LEFT), railTop)

	local spot = metrics.levelPlaque
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

function C.ApplySettings()
	if not holder then return end
	if not On() then
		if C.preview then C.SetPreview(false) end
		Idle()
	end
	C.Layout()
end

---------------------------------------------------------------------------

local function Build()
	local cluster = ns.Cluster
	holder = CreateFrame("Frame", "SanctuaryUICastRail", cluster)
	holder:Hide()
	bar = CreateFrame("StatusBar", nil, holder)
	bar:SetStatusBarTexture(ns.Art.Path("xpWhite") or "Interface\\Buttons\\WHITE8X8")
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0)
	still = holder:CreateTexture(nil, "ARTWORK")
	still:SetTexture(ns.Art.Path("xpWhite") or "Interface\\Buttons\\WHITE8X8")
	still:Hide()

	top = CreateFrame("Frame", nil, cluster)
	top:Hide()
	-- The spark rides the fill's head, over the console art so it glows past the rail's lips.
	local mote = ns.Art.Path("mote") or "Interface\\Buttons\\WHITE8X8"
	spark = top:CreateTexture(nil, "OVERLAY")
	spark:SetTexture(mote)
	spark:SetBlendMode("ADD")
	spark:SetPoint("CENTER", bar:GetStatusBarTexture(), "RIGHT")
	core = top:CreateTexture(nil, "OVERLAY", nil, 1)
	core:SetTexture(mote)
	core:SetBlendMode("ADD")
	core:SetVertexColor(1, 1, 0.92)
	core:SetPoint("CENTER", bar:GetStatusBarTexture(), "RIGHT")

	bloom = top:CreateTexture(nil, "OVERLAY")
	bloom:SetTexture(mote)
	bloom:SetBlendMode("ADD")
	bloom:SetVertexColor(1, 0.8, 0.45, 0.8)
	bloom:SetPoint("CENTER", holder, "CENTER")
	bloom:Hide()

	nameText = top:CreateFontString(nil, "OVERLAY")
	ns.Fonts.Set(nameText, "title", 11, "OUTLINE")
	nameText:SetJustifyH("RIGHT")
	nameText:SetShadowOffset(0, 0)
	timeText = top:CreateFontString(nil, "OVERLAY")
	ns.Fonts.Set(timeText, "body", 11, "OUTLINE")
	timeText:SetJustifyH("LEFT")
	timeText:SetTextColor(0.92, 0.92, 0.92)
	timeText:SetShadowOffset(0, 0)

	-- The level medallion's double, wearing the spell's icon on its red disc.
	medal = CreateFrame("Frame", nil, top)
	medal.art = medal:CreateTexture(nil, "ARTWORK")
	medal.art:SetAllPoints()
	if ns.Art.Apply(medal.art, "levelMedallion") then
		medal.art:SetTexCoord(5 / 128, 125 / 128, 4 / 128, 124 / 128) -- as Experience.lua crops it
	else
		medal.art:SetColorTexture(0.25, 0.03, 0.03, 0.9)
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

	holder:SetScript("OnUpdate", OnUpdate)
	holder:SetScript("OnHide", function()
		-- Hidden with its parent (the console hidden): the rail gets its XP back.
		if not phase then ApplyAlpha(0) end
	end)
end

function C.Init()
	if not ns.Cluster or holder then return end
	Build()
	C.Layout()
	ApplyAlpha(0)

	local events = CreateFrame("Frame", nil, ns.Cluster)
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
