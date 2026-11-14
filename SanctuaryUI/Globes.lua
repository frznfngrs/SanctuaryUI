SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.Globes = ns.Globes or {}

local GLOBE = 136
local WELL_PAD = 5 / 160 -- the well's reach past the liquid, of the globe's diameter
local PIP_MAX = 6
local HOTLINE_H = 0.16

-- Liquid colors sampled from the D3 class globes. liquid.png is luminance, so these set the hue.
local HEALTH_COLOR = { 0.86, 0.07, 0.05 }
local POWER_COLORS = {
	MANA = { 0.18, 0.36, 1.0 }, -- Witch Doctor mana
	RAGE = { 1.0, 0.52, 0.06 }, -- Barbarian fury
	ENERGY = { 1.0, 0.85, 0.42 }, -- Monk spirit
	FOCUS = { 0.95, 0.6, 0.25 },
	RUNIC_POWER = { 0.2, 0.85, 0.8 }, -- Necromancer essence
}

-- Secondary resources by class. The modern client reports a combo point maximum for every
-- class (vehicles use them), so the class decides whether the small globes show at all.
-- Druids only build combo points in cat form, which runs on energy.
local SECONDARY = {
	ROGUE = { "ComboPoints" },
	DRUID = { "ComboPoints", needs = "ENERGY" },
	PALADIN = { "HolyPower" },
	WARLOCK = { "SoulShards" },
	MONK = { "Chi" },
	MAGE = { "ArcaneCharges" },
	EVOKER = { "Essence" },
	DEATHKNIGHT = { "Runes" },
}

-- Shared with the party globes, so a member's liquid is yours.
ns.Globes.HEALTH_COLOR = HEALTH_COLOR
ns.Globes.POWER_COLORS = POWER_COLORS

local function Secret(value)
	return issecretvalue and issecretvalue(value)
end

local function PowerColor()
	local powerType, token = UnitPowerType("player")
	local color = token and POWER_COLORS[token]
	if color then
		return color[1], color[2], color[3]
	end
	color = PowerBarColor and (PowerBarColor[token] or PowerBarColor[powerType] or PowerBarColor["MANA"])
	if color then
		return color.r or color[1] or 0.2, color.g or color[2] or 0.45, color.b or color[3] or 0.9
	end
	return 0.18, 0.36, 1.0
end

function ns.Globes.ResourceColor()
	return PowerColor()
end

-- Globe numbers: the title font (D3's Exocet by default) with an outline and a soft shadow so
-- the thin face reads over moving liquid.
local VALUE_SIZE, MAX_SIZE, HALF_SIZE = 22, 11, 15

local function StyleNumber(fontString, size, r, g, b)
	ns.Fonts.Set(fontString, "title", size, "OUTLINE")
	fontString:SetShadowColor(0, 0, 0, 0.85)
	fontString:SetShadowOffset(1.5, -1.5)
	fontString:SetTextColor(r, g, b)
end

local function SetMax(fontString, value)
	if not fontString then return end
	local text = value
	if value ~= nil and not Secret(value) and AbbreviateLargeNumbers then
		local ok, short = pcall(AbbreviateLargeNumbers, value)
		if ok then text = short end
	end
	if not pcall(fontString.SetFormattedText, fontString, "/ %s", text) then
		fontString:SetText("")
	end
end

local function SetNumber(fontString, value)
	if not fontString then return end
	if value == nil or Secret(value) then
		local ok = pcall(fontString.SetText, fontString, value)
		if not ok then
			fontString:SetText("")
		end
		return
	end
	if AbbreviateLargeNumbers then
		local ok = pcall(fontString.SetText, fontString, AbbreviateLargeNumbers(value))
		if ok then return end
	end
	fontString:SetText(tostring(value))
end

local function Fill(bar, value, maxValue)
	-- Animated globes glide to the new level.
	if ns.Liquid and ns.Liquid.SetValue(bar, value, maxValue) then
		return
	end
	if maxValue ~= nil and not Secret(maxValue) then
		bar:SetMinMaxValues(0, maxValue)
	elseif maxValue ~= nil then
		pcall(bar.SetMinMaxValues, bar, 0, maxValue)
	end
	if not pcall(bar.SetValue, bar, ns.Or(value, 0)) then
		bar:SetValue(0)
	end
end

-- Draw order, back to front: dark well, liquid, surface band (globe frames), then the
-- ADD glass and the console art (cluster frames above), then the number.
local function MakeGlobe(name, parent, tint)
	local globe = CreateFrame("Frame", name, parent)
	globe:SetSize(GLOBE, GLOBE)
	globe.tint = tint

	local well = globe:CreateTexture(nil, "BACKGROUND")
	well:SetAllPoints()
	if ns.Art.Apply(well, "liquid") then
		well:SetVertexColor(0.07, 0.035, 0.03, 1)
	else
		well:SetColorTexture(0.04, 0.02, 0.02, 1)
		ns.Art.MaskCircle(well)
	end
	globe.Well = well

	local liquid = CreateFrame("StatusBar", nil, globe)
	liquid:SetAllPoints()
	liquid:SetOrientation("VERTICAL")
	liquid:SetMinMaxValues(0, 1)
	liquid:SetValue(1)
	globe.Liquid = liquid

	local surface = CreateFrame("Frame", nil, liquid)
	surface:SetAllPoints(globe)
	local hotline = surface:CreateTexture(nil, "OVERLAY")
	hotline:SetBlendMode("ADD")
	hotline:Hide()
	globe.Hotline = hotline

	local chrome = CreateFrame("Frame", nil, globe)
	chrome:SetAllPoints()
	globe.Chrome = chrome

	local number = chrome:CreateFontString(nil, "OVERLAY")
	StyleNumber(number, VALUE_SIZE, 1, 0.94, 0.8)
	number:SetPoint("CENTER", globe, "CENTER", 0, 4)
	globe.Number = number
	local maxText = chrome:CreateFontString(nil, "OVERLAY")
	StyleNumber(maxText, MAX_SIZE, 0.82, 0.68, 0.42)
	maxText:SetPoint("TOP", number, "BOTTOM", 0, -1)
	globe.Max = maxText

	-- Hover mode shows the numbers only under the mouse, like D3. Motion only, so a drag
	-- still reaches the console.
	if globe.SetMouseMotionEnabled then
		globe:SetMouseMotionEnabled(true)
		if globe.SetMouseClickEnabled then
			globe:SetMouseClickEnabled(false)
		end
	end
	globe:SetScript("OnEnter", function(self)
		self.hovered = true
		ns.Globes.ApplyNumbers()
	end)
	globe:SetScript("OnLeave", function(self)
		self.hovered = false
		ns.Globes.ApplyNumbers()
	end)

	liquid:HookScript("OnValueChanged", function()
		ns.Globes.PlaceSurface(globe)
	end)
	globe:HookScript("OnSizeChanged", function()
		ns.Globes.PlaceSurface(globe)
	end)
	return globe
end

-- The surface band sits on the liquid level and spans the chord of the circle there.
function ns.Globes.PlaceSurface(globe)
	local hotline = globe.Hotline
	if not hotline then return end
	if globe.pool then
		hotline:Hide()
		globe.pool:UpdateSurface()
		return
	end
	local liquid = globe.Liquid
	local minValue, maxValue = liquid:GetMinMaxValues()
	local value = liquid:GetValue()
	if not ns.Art.Path("hotline") or (issecretvalue and (issecretvalue(value) or issecretvalue(maxValue))) then
		hotline:Hide()
		return
	end
	local span = (maxValue or 1) - (minValue or 0)
	local fill = span > 0 and ((value or 0) - (minValue or 0)) / span or 0
	local size = globe:GetHeight()
	if fill <= 0.02 or fill >= 0.98 or size <= 0 then
		hotline:Hide()
		return
	end
	local radius = size / 2
	local y = fill * size - radius
	local chord = 2 * math.sqrt(math.max(0, radius * radius - y * y))
	hotline:ClearAllPoints()
	hotline:SetSize(chord, size * HOTLINE_H)
	hotline:SetPoint("TOP", globe, "CENTER", 0, y + 1)
	hotline:Show()
end

-- Split globe (Demon Hunter console): a blade down the middle, the active resource on the
-- left and mana on the right. Used whenever the active power is not mana but the player has
-- a mana pool, which on Forever means a druid in bear or cat form.
local MANA = Enum and Enum.PowerType and Enum.PowerType.Mana or 0
local BLADE_X0, BLADE_W, BLADE_H = 1329, 64, 201

local function MakeHalf(globe, side)
	local half = {}
	local bar = CreateFrame("StatusBar", nil, globe)
	bar:SetOrientation("VERTICAL")
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(1)
	bar:Hide()
	half.bar = bar
	local surface = CreateFrame("Frame", nil, bar)
	surface:SetAllPoints(globe)
	local hotline = surface:CreateTexture(nil, "OVERLAY")
	hotline:SetBlendMode("ADD")
	hotline:Hide()
	half.hotline = hotline
	local number = globe.Chrome:CreateFontString(nil, "OVERLAY")
	StyleNumber(number, HALF_SIZE, 1, 0.94, 0.8)
	number:Hide()
	half.number = number
	half.side = side
	bar:HookScript("OnValueChanged", function()
		ns.Globes.PlaceHalfSurface(globe, half)
	end)
	return half
end

function ns.Globes.PlaceHalfSurface(globe, half)
	local bar, hotline = half.bar, half.hotline
	if half.pool then
		hotline:Hide()
		half.pool:UpdateSurface()
		return
	end
	local minValue, maxValue = bar:GetMinMaxValues()
	local value = bar:GetValue()
	if not bar:IsShown() or not ns.Art.Path("hotline") or (issecretvalue and (issecretvalue(value) or issecretvalue(maxValue))) then
		hotline:Hide()
		return
	end
	local span = (maxValue or 1) - (minValue or 0)
	local fill = span > 0 and ((value or 0) - (minValue or 0)) / span or 0
	local size = globe:GetHeight()
	if fill <= 0.02 or fill >= 0.98 or size <= 0 then
		hotline:Hide()
		return
	end
	local radius = size / 2
	local y = fill * size - radius
	local halfChord = math.sqrt(math.max(0, radius * radius - y * y))
	hotline:ClearAllPoints()
	hotline:SetSize(halfChord, size * HOTLINE_H)
	if half.side == "left" then
		hotline:SetTexCoord(0, 0.5, 0, 1)
		hotline:SetPoint("TOPRIGHT", globe, "CENTER", 0, y + 1)
	else
		hotline:SetTexCoord(0.5, 1, 0, 1)
		hotline:SetPoint("TOPLEFT", globe, "CENTER", 0, y + 1)
	end
	hotline:Show()
end

local function HotlineColor(r, g, b)
	return math.min(1, r * 0.6 + 0.45), math.min(1, g * 0.6 + 0.45), math.min(1, b * 0.6 + 0.45), 0.9
end

local function TintHalf(half, color)
	if half.pool then
		local c = half.pool.color
		if not (c and c[1] == color[1] and c[2] == color[2] and c[3] == color[3]) then
			half.pool:SetColor(color[1], color[2], color[3])
		end
		return
	end
	local tex = half.bar:GetStatusBarTexture()
	if tex then
		tex:SetVertexColor(color[1], color[2], color[3], 1)
	end
	half.hotline:SetVertexColor(HotlineColor(color[1], color[2], color[3]))
end

function ns.Globes.IsSplit()
	local powerType = UnitPowerType("player")
	if powerType == nil or powerType == MANA then
		return false
	end
	local maxMana = UnitPowerMax("player", MANA)
	if issecretvalue and issecretvalue(maxMana) then
		return ns.Globes.hadMana or false -- hidden in combat: stay as it was
	end
	ns.Globes.hadMana = maxMana ~= nil and maxMana > 0
	return ns.Globes.hadMana
end

local function Tint(globe, r, g, b)
	-- Runs on every power tick; a new colour is the rare case.
	local tint = globe.tint
	if tint and tint[1] == r and tint[2] == g and tint[3] == b then return end
	globe.tint = { r, g, b }
	if globe.pool then
		globe.pool:SetColor(r, g, b)
		return
	end
	local tex = globe.Liquid:GetStatusBarTexture()
	if tex then
		tex:SetVertexColor(r, g, b, 1)
	end
	if globe.Hotline then
		globe.Hotline:SetVertexColor(HotlineColor(r, g, b))
	end
end

-- Secondary resource (combo points, holy power, ...): small liquid globes set in D3 socket
-- rings along the top-left of the resource globe's metal rim, clear of the angel. Each fills
-- by its share of the value, so a point pours in rather than popping on.
-- Each small globe sits in D3's horned skull ring (pip-horn.png), turned so the skull meets
-- the resource globe's rim, with a Kanai's Cube socket rim round the liquid.
local PIP_SIZE = 0.15 -- liquid diameter, of the resource globe
local HORN_SCALE = 128 / 42 -- pip-horn.png is 128 px with a 42 px hole
local PIP_OFFSET = 0.9 -- centre beyond the rim, of a pip's size: the skull just meets the rim
local PIP_GAP = 1.66 -- centre spacing, of a pip's size: frames (about 2x the pip) just touch
local PIP_ARC_CENTER = 104 -- degrees, 90 = straight up; leans left, away from the angel
local SOCKET_SCALE = 1.28 -- socket rim, of a pip's size
local PIP_COLORS = {
	ComboPoints = { 1.0, 0.32, 0.08 },
	HolyPower = { 1.0, 0.82, 0.35 },
	Chi = { 0.3, 0.95, 0.65 },
	SoulShards = { 0.7, 0.35, 1.0 },
	ArcaneCharges = { 0.35, 0.6, 1.0 },
	Essence = { 0.3, 0.9, 0.85 },
	Runes = { 0.55, 0.75, 1.0 },
}
-- pip-sockets.png cells: 0 black, 1 orange, 2 green, 3 red, 4 blue.
local PIP_SOCKET = {
	ComboPoints = 3,
	HolyPower = 1,
	Chi = 2,
	SoulShards = 0,
	ArcaneCharges = 4,
	Essence = 2,
	Runes = 4,
}
local PIP_GLOW = 6 -- pips.png cell: soft round glow, for the glint

local function PipCoord(index)
	return index * 64 / 512, (index + 1) * 64 / 512, 0, 1
end

local function PipGeometry(count, size)
	local rim = (ns.ResourceGlobe and ns.ResourceGlobe:GetWidth() or GLOBE) / 2
	local radius = rim + size * PIP_OFFSET
	local step = 2 * math.asin(math.min(1, size * PIP_GAP / (2 * radius)))
	return rim, radius, step
end

local function PipAngle(index, count, step)
	return math.rad(PIP_ARC_CENTER) + ((count + 1) / 2 - index) * step
end

local function MakePip(parent)
	local pip = CreateFrame("Frame", nil, parent)
	pip:SetSize(20, 20)

	-- The horned frame, behind the liquid; square so it can rotate without stretching. A child
	-- of the pip so it always shows and hides with it; Layout puts its level under the liquid.
	local hornFrame = CreateFrame("Frame", nil, pip)
	hornFrame:SetPoint("CENTER", pip, "CENTER")
	local horn = hornFrame:CreateTexture(nil, "ARTWORK")
	horn:SetAllPoints()
	if not ns.Art.Apply(horn, "pipHorn") then
		horn:SetColorTexture(0, 0, 0, 0)
	end
	pip.horn, pip.hornFrame = horn, hornFrame

	local well = pip:CreateTexture(nil, "BACKGROUND")
	well:SetAllPoints()
	if ns.Art.Apply(well, "liquid") then
		well:SetVertexColor(0.06, 0.03, 0.025, 1)
	else
		well:SetColorTexture(0.05, 0.03, 0.03, 1)
		ns.Art.MaskCircle(well, pip)
	end
	local bar = CreateFrame("StatusBar", nil, pip)
	bar:SetAllPoints()
	bar:SetOrientation("VERTICAL")
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0)
	pip.bar = bar
	pip.pool = ns.Liquid and ns.Liquid.Attach(pip, bar, { zoom = 0.4, slices = 4 })
	if not pip.pool then
		bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
		local tex = bar:GetStatusBarTexture()
		if tex then ns.Art.MaskCircle(tex, bar) end
	end
	pip.shade = ns.Liquid and ns.Liquid.Shade(pip)

	-- Socket rim and glint above the liquid.
	local top = CreateFrame("Frame", nil, pip)
	top:SetAllPoints()
	local socket = top:CreateTexture(nil, "ARTWORK")
	socket:SetPoint("CENTER")
	if not ns.Art.Apply(socket, "pipSockets") then
		socket:SetColorTexture(0, 0, 0, 0)
	end
	pip.socket = socket
	local glint = top:CreateTexture(nil, "OVERLAY")
	glint:SetPoint("CENTER", pip, "CENTER", -3, 3.5)
	if ns.Art.Apply(glint, "pips") then
		glint:SetTexCoord(PipCoord(PIP_GLOW))
		glint:SetBlendMode("ADD")
		glint:SetVertexColor(1, 1, 1, 0.7)
	end
	pip.glint = glint
	pip.top = top

	pip:Hide()
	return pip
end

local function TintPip(pip, color)
	if pip.pool then
		pip.pool:SetColor(color[1], color[2], color[3])
	else
		pip.bar:SetStatusBarColor(color[1], color[2], color[3], 1)
	end
end

-- Each pip's share of the value: 0 empty, 1 full, partial while a point builds.
local function FillPip(pip, index, value)
	if value ~= nil and not Secret(value) then
		local share = math.max(0, math.min(1, value - (index - 1)))
		if not (ns.Liquid and ns.Liquid.SetValue(pip.bar, share, 1)) then
			pip.bar:SetMinMaxValues(0, 1)
			pip.bar:SetValue(share)
		end
		return
	end
	-- Secret value: the bar can still compare it against this pip's range.
	pcall(pip.bar.SetMinMaxValues, pip.bar, index - 1, index)
	if not pcall(pip.bar.SetValue, pip.bar, ns.Or(value, 0)) then
		pip.bar:SetValue(index - 1)
	end
end

local function SecondaryPower()
	local primary, primaryToken = UnitPowerType("player")
	local _, class = UnitClass("player")
	local list = SECONDARY[class]
	if not list or (list.needs and list.needs ~= primaryToken) then
		return
	end
	for i = 1, #list do
		local token = list[i]
		local powerType = Enum and Enum.PowerType and Enum.PowerType[token]
		if powerType and powerType ~= primary then
			local maxValue = UnitPowerMax("player", powerType)
			if not Secret(maxValue) and maxValue and maxValue > 0 then
				local mod = 1
				if UnitPowerDisplayMod then
					local displayMod = UnitPowerDisplayMod(powerType)
					-- The display mod scales raw (unmodified) values: 50 raw soul shard
					-- fragments / 10 = 5 shards. The default return is already in shards.
					if not Secret(displayMod) and displayMod and displayMod > 1 then
						local raw = UnitPowerMax("player", powerType, true)
						if not Secret(raw) and raw and raw / displayMod >= 1 then
							mod = displayMod
							maxValue = raw / displayMod
						end
					end
				end
				if maxValue >= 1 and maxValue <= PIP_MAX then
					return powerType, maxValue, mod
				end
			end
		end
	end
end

function ns.Globes.UpdatePips()
	local globe = ns.ResourceGlobe
	if not globe or not globe.Pips then return end
	local powerType, maxValue, mod = SecondaryPower()
	mod = mod or 1
	local value, color
	if powerType then
		value = UnitPower("player", powerType, mod > 1)
		if not Secret(value) and value and mod > 1 then
			value = value / mod
		end
		for token, c in pairs(PIP_COLORS) do
			if Enum and Enum.PowerType and Enum.PowerType[token] == powerType then
				color = c
			end
		end
	end
	local token = "ComboPoints"
	for name in pairs(PIP_COLORS) do
		if powerType and Enum and Enum.PowerType and Enum.PowerType[name] == powerType then
			token = name
		end
	end
	color = color or PIP_COLORS.ComboPoints
	local size = globe:GetWidth() * PIP_SIZE
	local rim, radius, step = PipGeometry(maxValue or 0, size)
	for i = 1, PIP_MAX do
		local pip = globe.Pips[i]
		if powerType and i <= maxValue then
			local angle = PipAngle(i, maxValue, step)
			local cx, cy = math.cos(angle), math.sin(angle)
			pip:SetSize(size, size)
			pip:ClearAllPoints()
			pip:SetPoint("CENTER", globe, "CENTER", cx * radius, cy * radius)
			-- The skull hangs below the ring in the art (270 degrees); turn it to face the
			-- resource globe's centre.
			local frameSize = size * HORN_SCALE
			pip.hornFrame:SetSize(frameSize, frameSize)
			pip.horn:SetRotation(angle - math.pi / 2)
			pip.socket:SetSize(size * SOCKET_SCALE, size * SOCKET_SCALE)
			pip.socket:SetTexCoord(PipCoord(PIP_SOCKET[token] or 3))
			pip.glint:SetSize(size * 0.32, size * 0.32)
			TintPip(pip, color)
			pip:Show()
			FillPip(pip, i, value)
		else
			pip:Hide()
		end
	end
end

function ns.Globes.ApplySettings()
	local size = tonumber(ns.DB().numberSize) or VALUE_SIZE
	for _, globe in ipairs({ ns.HealthGlobe, ns.ResourceGlobe }) do
		if globe then
			StyleNumber(globe.Number, size, 1, 0.94, 0.8)
			StyleNumber(globe.Max, math.max(8, math.floor(size / 2 + 0.5)), 0.82, 0.68, 0.42)
			if globe.Halves then
				for _, half in pairs(globe.Halves) do
					StyleNumber(half.number, math.max(9, math.floor(size * 0.7 + 0.5)), 1, 0.94, 0.8)
				end
			end
		end
	end
	if ns.Liquid and ns.Liquid.ApplySettings then
		ns.Liquid.ApplySettings()
	end
	ns.Globes.ApplyNumbers()
	-- The prediction toggles.
	ns.Globes.UpdateHealPrediction()
	ns.Globes.UpdatePower()
end

-- Number fades: quick in, slower out, and a short wait after combat before they go.
local FADE_IN, FADE_OUT, COMBAT_LINGER = 0.18, 0.6, 1.5
local fader
local inCombat = false
local lingerUntil = 0

local function SetNumberAlpha(globe, alpha)
	globe.Number:SetAlpha(alpha)
	globe.Max:SetAlpha(alpha)
	if globe.Halves then
		for _, half in pairs(globe.Halves) do
			half.number:SetAlpha(alpha)
		end
	end
end

-- Ease each globe's number alpha toward its target; the driver stops once all have arrived.
local function FadeStep(_, elapsed)
	local busy = false
	local now = GetTime()
	for _, globe in ipairs({ ns.HealthGlobe, ns.ResourceGlobe }) do
		if globe then
			local target = globe.numberTarget or 1
			-- Just left combat: hold until the linger ends, then fade.
			if target == 0 and globe.numberLinger and now < lingerUntil then
				target = 1
				busy = true
			end
			local alpha = globe.numberAlpha or target
			if alpha ~= target then
				local step = elapsed / (target > alpha and FADE_IN or FADE_OUT)
				alpha = target > alpha and math.min(target, alpha + step) or math.max(target, alpha - step)
				globe.numberAlpha = alpha
				busy = true
			end
			-- Smoothstep so the fade starts and ends gently.
			SetNumberAlpha(globe, alpha * alpha * (3 - 2 * alpha))
		end
	end
	if not busy then
		fader:SetScript("OnUpdate", nil)
	end
end

-- numbers: "on" always, "combat" in combat or under the mouse, "hover" under the mouse, "off"
-- never. Which strings exist (split halves, the max) is set by Show; whether they are seen
-- is an alpha that fades.
function ns.Globes.ApplyNumbers()
	local db = ns.DB()
	local mode = db.numbers or "on"
	if not fader then
		fader = CreateFrame("Frame")
	end
	for _, globe in ipairs({ ns.HealthGlobe, ns.ResourceGlobe }) do
		if globe then
			local enabled = mode ~= "off"
			globe.Number:SetShown(enabled and not globe.split)
			globe.Max:SetShown(enabled and not globe.split and db.numbersMax)
			if globe.Halves then
				for _, half in pairs(globe.Halves) do
					half.number:SetShown(enabled and globe.split or false)
				end
			end
			local visible = mode == "on" or globe.hovered or (mode == "combat" and inCombat)
			globe.numberLinger = mode == "combat"
			globe.numberTarget = visible and 1 or 0
			if globe.numberAlpha == nil then
				-- First time: start where we belong, no fade at login.
				globe.numberAlpha = globe.numberTarget
				SetNumberAlpha(globe, globe.numberAlpha)
			end
		end
	end
	fader:SetScript("OnUpdate", FadeStep)
end

function ns.Globes.SetCombat(state)
	if inCombat and not state then
		lingerUntil = GetTime() + COMBAT_LINGER
	end
	inCombat = state
	ns.Globes.ApplyNumbers()
end

-- /sanctuary health <percent>: show the health globe at that level (to see low health
-- without being there); nil shows your real health.
function ns.Globes.PreviewHealth(percent)
	ns.Globes.healthPreview = percent and math.max(0, math.min(100, percent)) / 100 or nil
	ns.Globes.UpdateHealth()
end

function ns.Globes.UpdateHealPrediction(health, maxHealth)
	local pool = ns.HealthGlobe and ns.HealthGlobe.pool
	if not pool or not pool.bands then return end
	local db = ns.DB()
	local demo = ns.Globes.demo
	local heal, absorb, clamped, hot = nil, nil, nil, 0
	if demo then
		-- Same clamping as the client: heal into missing health, then the shield into the rest.
		maxHealth = 1000
		local missing = maxHealth - math.floor((ns.Globes.healthPreview or 1) * maxHealth + 0.5)
		heal = math.min(demo.heal * maxHealth, missing)
		hot = math.min((demo.hot or 0) * maxHealth, missing - heal)
		absorb = math.min(demo.absorb * maxHealth, missing - heal - hot)
		clamped = demo.absorb * maxHealth > missing - heal - hot
	elseif ns.Globes.healthPreview then
		heal, absorb, clamped = 0, 0, false
	else
		health = health or UnitHealth("player")
		maxHealth = maxHealth or UnitHealthMax("player")
		heal, absorb, clamped = ns.IncomingHeals("player", health, maxHealth)
		hot, absorb, clamped = ns.IncomingHot("player", health, maxHealth, heal, absorb, clamped)
	end
	if not db.healPrediction and not demo then heal, hot = 0, 0 end
	if not db.absorbPrediction and not demo then absorb, clamped = 0, false end
	pool:SetBand("heal", heal, maxHealth)
	pool:SetBand("hot", hot, maxHealth)
	pool:SetBand("absorb", absorb, maxHealth)
	pool:SetShield(clamped)
end

-- Power cost of the spell being cast, by power type, from cast start until the cast ends. An
-- end event while a cast is still going (an instant fired off the GCD, a spam press that
-- failed) belongs to another spell and leaves it, as Blizzard's player frame does.
local castCost
local GetPowerCost = C_Spell and C_Spell.GetSpellPowerCost or GetSpellPowerCost

local function StillCasting()
	if not UnitCastingInfo then return false end
	local ok, still = pcall(function()
		return select(9, UnitCastingInfo("player")) ~= nil
	end)
	return ok and still
end

function ns.Globes.CastStarted(spellID)
	castCost = nil
	if spellID == nil or Secret(spellID) or not GetPowerCost then return end
	local ok, costs = pcall(GetPowerCost, spellID)
	if not ok or type(costs) ~= "table" then return end
	-- Spells listing several costs carry one per spec or form; hasRequiredAura picks the live one.
	local checkAura = #costs > 1
	for _, info in ipairs(costs) do
		local okType, kind = pcall(function()
			if checkAura and not info.hasRequiredAura then return nil end
			return info.type
		end)
		if okType and kind ~= nil and not Secret(kind) then
			castCost = castCost or {}
			if castCost[kind] == nil then castCost[kind] = info.cost end
		end
	end
end

function ns.Globes.CastEnded()
	if castCost and not StillCasting() then
		castCost = nil
	end
end

local function CostFor(powerType)
	if ns.Globes.demo then return ns.Globes.demo.cost * 1000 end
	if not castCost or powerType == nil or Secret(powerType) or not ns.DB().costPrediction then return 0 end
	return castCost[powerType] or 0
end

function ns.Globes.UpdateHealth()
	local globe = ns.HealthGlobe
	if not globe then return end
	Tint(globe, HEALTH_COLOR[1], HEALTH_COLOR[2], HEALTH_COLOR[3])
	local health, maxHealth = UnitHealth("player"), UnitHealthMax("player")
	if ns.Globes.healthPreview then
		maxHealth = 1000
		health = math.floor(ns.Globes.healthPreview * maxHealth + 0.5)
	end
	Fill(globe.Liquid, health, maxHealth)
	ns.Globes.UpdateHealPrediction(health, maxHealth)
	SetNumber(globe.Number, health)
	SetMax(globe.Max, maxHealth)
	ns.Globes.ApplyNumbers()
	ns.Globes.PlaceSurface(globe)
end

-- What the server last said you have, by power type. Forever is a modern client on vanilla
-- rules: between the server's updates the client counts regen up smoothly on its own (and
-- UNIT_POWER_FREQUENT fires for it), but the server only pays energy and mana in 2 s ticks.
-- Read on those events, the globe could run up to a tick ahead of what you can spend (#8: a
-- 40 energy Claw needing about 47 shown). So the value is read on UNIT_POWER_UPDATE, the
-- server's word, and kept for everything else that redraws the globe (the party and target
-- frames already listen to that event alone).
-- (A secret can't be compared, even with nil, so whether one is kept is its own table.)
local serverPower, kept = {}, {}
-- UNIT_POWER_UPDATE's token -> its Enum.PowerType key, for the pools a globe shows.
local TOKEN_TYPE = { MANA = "Mana", RAGE = "Rage", ENERGY = "Energy", FOCUS = "Focus", RUNIC_POWER = "RunicPower" }

local function ReadPower(powerType)
	serverPower[powerType], kept[powerType] = UnitPower("player", powerType), true
end

local function CurrentPower(powerType)
	if not kept[powerType] then ReadPower(powerType) end
	return serverPower[powerType]
end

function ns.Globes.ReadServerPower()
	wipe(serverPower)
	wipe(kept)
end

-- The active resource, or the /sanctuary predict demo's level out of 1000.
local function Power()
	local preview = ns.Globes.powerPreview
	if preview then return math.floor(preview * 1000 + 0.5), 1000 end
	local powerType = UnitPowerType("player")
	if Secret(powerType) or powerType == nil then
		return UnitPower("player"), UnitPowerMax("player")
	end
	return CurrentPower(powerType), UnitPowerMax("player", powerType)
end

-- For /sanctuary power (PowerTrace.lua): the number the resource globe shows now.
function ns.Globes.ShownPower()
	local powerType = UnitPowerType("player")
	if powerType == nil or Secret(powerType) then return nil end
	return CurrentPower(powerType)
end

-- /sanctuary predict: a heal on its way (with a HoT part), a shield and a spell being cast, on
-- preview levels; then the heal and cast land, then health tops up so the shield overflows into
-- its glow, then the globes go back to your real values. Each run replaces the last.
function ns.Globes.PredictDemo()
	local G = ns.Globes
	local run = {}
	G.demoRun = run
	local function Step(heal, absorb, cost, health, power, hot)
		if G.demoRun ~= run then return end
		G.demo = heal and { heal = heal, absorb = absorb, cost = cost, hot = hot } or nil
		G.healthPreview, G.powerPreview = health, power
		G.UpdateHealth()
		G.UpdatePower()
	end
	-- 40% health, 30% incoming with 10% more over time and a 15% shield; 80% resource, a 25% cast.
	Step(0.3, 0.15, 0.25, 0.4, 0.8, 0.1)
	C_Timer.After(2.5, function() Step(0, 0.15, 0, 0.7, 0.55) end) -- heal and cast land
	C_Timer.After(5, function() Step(0, 0.15, 0, 1, 0.55) end) -- topped up: the shield overflows
	C_Timer.After(8, function() Step(nil, nil, nil, nil, nil) end)
end

function ns.Globes.UpdatePower()
	local globe = ns.ResourceGlobe
	if not globe then return end
	local r, g, b = PowerColor()
	local split = globe.Halves and ns.Globes.IsSplit()
	globe.Liquid:SetShown(not split)
	globe.split = split
	if ns.Globes.Blade then
		ns.Globes.Blade:SetShown(split and ns.Art.Path("blade") ~= nil)
	end
	if globe.Halves then
		for _, half in pairs(globe.Halves) do
			half.bar:SetShown(split)
		end
	end
	if split then
		local left, right = globe.Halves.left, globe.Halves.right
		TintHalf(left, { r, g, b })
		TintHalf(right, POWER_COLORS.MANA)
		local power, maxPower = Power()
		Fill(left.bar, power, maxPower)
		Fill(right.bar, CurrentPower(MANA), UnitPowerMax("player", MANA))
		if left.pool and left.pool.bands then
			left.pool:SetBand("cost", CostFor(UnitPowerType("player")), maxPower)
		end
		if right.pool and right.pool.bands then
			right.pool:SetBand("cost", CostFor(MANA), UnitPowerMax("player", MANA))
		end
		SetNumber(left.number, power)
		SetNumber(right.number, CurrentPower(MANA))
		globe.Hotline:Hide()
		ns.Globes.PlaceHalfSurface(globe, left)
		ns.Globes.PlaceHalfSurface(globe, right)
	else
		Tint(globe, r, g, b)
		local power, maxPower = Power()
		Fill(globe.Liquid, power, maxPower)
		if globe.pool and globe.pool.bands then
			globe.pool:SetBand("cost", CostFor(UnitPowerType("player")), maxPower)
		end
		SetNumber(globe.Number, power)
		SetMax(globe.Max, maxPower)
		ns.Globes.PlaceSurface(globe)
	end
	ns.Globes.ApplyNumbers()
	ns.Globes.UpdatePips()
	-- The rail wears the resource colour; only a change of colour needs it redrawn.
	if ns.Experience and ns.Experience.Update and ns.Globes.ResourceColor then
		local r, g, b = ns.Globes.ResourceColor()
		if r ~= ns.Globes.railR or g ~= ns.Globes.railG or b ~= ns.Globes.railB then
			ns.Globes.railR, ns.Globes.railG, ns.Globes.railB = r, g, b
			ns.Experience.Update()
		end
	end
end

function ns.Globes.Layout()
	local cluster = ns.Cluster
	local metrics = ns.Metrics and ns.Metrics()
	if not cluster or not ns.HealthGlobe or not metrics then return end
	local base = metrics.baseY
	local level = cluster:GetFrameLevel()
	local pods, spots = ns.Pods, metrics.pods
	local function place(globe, side)
		local spot = spots[side]
		globe:SetSize(spot.size, spot.size)
		globe:ClearAllPoints()
		globe:SetPoint("CENTER", pods[side], "BOTTOM", spot.x, base + spot.y)
		globe:SetFrameLevel(level + ns.LEVEL.globe)
		-- The dark well reaches 5 px (of the 160 px globe) past the liquid, under the console's
		-- ring: the ring's soft inner edge sits outside the globe along the bottom, and without
		-- this the game world shows through it. Any further would poke past the ring.
		local pad = spot.size * WELL_PAD
		globe.Well:ClearAllPoints()
		globe.Well:SetPoint("TOPLEFT", globe, "TOPLEFT", -pad, pad)
		globe.Well:SetPoint("BOTTOMRIGHT", globe, "BOTTOMRIGHT", pad, -pad)
		globe.Liquid:SetFrameLevel(level + ns.LEVEL.liquid)
		globe.Chrome:SetFrameLevel(level + ns.LEVEL.chrome)
		if globe.pool then
			globe.pool:SetLevels(level)
		end
		if globe.Shade then
			globe.Shade:SetFrameLevel(level + ns.LEVEL.shade)
		end
	end
	place(ns.HealthGlobe, "health")
	place(ns.ResourceGlobe, "resource")

	-- The health globe's click button: on the globe's circle (anchored to its pod, like the
	-- globe), above the art. Unlocked, clicks go through to drag the console.
	local click = ns.Globes.click
	if click and not InCombatLockdown() then
		local spot = spots.health
		click:SetSize(spot.size * 0.86, spot.size * 0.86)
		click:ClearAllPoints()
		click:SetPoint("CENTER", pods.health, "BOTTOM", spot.x, base + spot.y)
		click:SetFrameLevel(level + ns.LEVEL.chrome + 1)
		click:EnableMouse(ns.DB().locked and true or false)
	end

	local resource = ns.ResourceGlobe
	if resource.Halves then
		-- The halves are the globe's children, so they take its own size (pod units); the
		-- console-unit size already has the globe scale in it and would apply it twice.
		local size = spots.resource.size
		for side, half in pairs(resource.Halves) do
			half.bar:ClearAllPoints()
			half.bar:SetSize(size / 2, size)
			if side == "left" then
				half.bar:SetPoint("LEFT", resource, "LEFT")
				half.number:SetPoint("CENTER", resource, "CENTER", -size / 4, 0)
			else
				half.bar:SetPoint("RIGHT", resource, "RIGHT")
				half.number:SetPoint("CENTER", resource, "CENTER", size / 4, 0)
			end
			half.bar:SetFrameLevel(level + ns.LEVEL.liquid)
			if half.pool then
				half.pool:SetLevels(level)
			end
		end
	end
	-- The blade belongs to the console art, so it draws at the console's level, above the glass.
	local blade = ns.Globes.Blade
	if not blade then
		blade = CreateFrame("Frame", "SanctuaryUIBlade", pods.resource)
		blade:EnableMouse(false)
		blade.tex = blade:CreateTexture(nil, "ARTWORK")
		blade.tex:SetAllPoints()
		blade:Hide()
		ns.Globes.Blade = blade
	end
	local scale = metrics.scale
	blade:SetSize(BLADE_W * scale, BLADE_H * scale)
	blade:ClearAllPoints()
	blade:SetPoint("CENTER", pods.resource, "BOTTOM", (BLADE_X0 + BLADE_W / 2) * scale - metrics.width / 2, base)
	blade:SetFrameLevel(level + ns.LEVEL.blade)

	-- Glass sits between the liquid and the console art, over the whole console, in ADD.
	local glass = ns.GlassFrame
	if not glass then
		glass = CreateFrame("Frame", "SanctuaryUIGlass", cluster)
		glass:EnableMouse(false)
		glass.tex = glass:CreateTexture(nil, "ARTWORK")
		glass.tex:SetAllPoints()
		glass.tex:SetBlendMode("ADD")
		ns.GlassFrame = glass
	end
	glass:SetSize(metrics.width, metrics.height)
	glass:ClearAllPoints()
	glass:SetPoint("CENTER", cluster, "BOTTOM", 0, base)
	glass:SetFrameLevel(level + ns.LEVEL.glass)
	-- Scaled separately, each globe takes its own piece of the glass (only the globes have any).
	glass.split = metrics.split
	for side, pod in pairs(pods) do
		local piece = pod.glass
		if not piece then
			piece = CreateFrame("Frame", nil, pod)
			piece:EnableMouse(false)
			piece.tex = piece:CreateTexture(nil, "ARTWORK")
			piece.tex:SetAllPoints()
			pod.glass = piece
		end
		ns.PlacePiece(piece, pod, side, metrics)
		piece:SetFrameLevel(level + ns.LEVEL.glass)
	end
	ns.Globes.ShowGlass()

	-- Pips sit on the rim, above the console art: their own liquid stack starts at pips.
	if ns.ResourceGlobe.Pips then
		for i = 1, #ns.ResourceGlobe.Pips do
			local pip = ns.ResourceGlobe.Pips[i]
			pip:SetFrameLevel(level + ns.LEVEL.pips)
			pip.bar:SetFrameLevel(level + ns.LEVEL.pips + 1)
			if pip.pool then
				pip.pool:SetLevels(level, ns.LEVEL.pips)
			end
			if pip.shade then
				pip.shade:SetFrameLevel(level + ns.LEVEL.pips + ns.LEVEL.shade)
			end
			pip.top:SetFrameLevel(level + ns.LEVEL.pips + ns.LEVEL.surface + 2)
			-- Horned frames under the liquid, over the console art.
			pip.hornFrame:SetFrameLevel(level + ns.LEVEL.pips - 1)
		end
	end
	ns.Globes.PlaceSurface(ns.HealthGlobe)
	ns.Globes.PlaceSurface(ns.ResourceGlobe)
end

function ns.Globes.RefreshArt()
	local function Paint(globe)
		if not globe then return end
		local path = ns.Art.Path("liquid")
		if globe.pool then
			-- Animated: the StatusBar texture is the invisible guide the pool is anchored to.
		elseif path then
			globe.Liquid:SetStatusBarTexture(path)
		else
			globe.Liquid:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
			local tex = globe.Liquid:GetStatusBarTexture()
			if tex then
				tex.sanctuaryMasked = nil
				ns.Art.MaskCircle(tex, globe.Liquid)
			end
		end
		if not ns.Art.Apply(globe.Hotline, "hotline") then
			globe.Hotline:SetColorTexture(0, 0, 0, 0)
		end
		globe.Hotline:SetBlendMode("ADD")
	end
	Paint(ns.HealthGlobe)
	Paint(ns.ResourceGlobe)
	local halves = ns.ResourceGlobe and ns.ResourceGlobe.Halves
	if halves then
		for side, half in pairs(halves) do
			local path = ns.Art.Path(side == "left" and "liquidLeft" or "liquidRight")
			if not half.pool then
				half.bar:SetStatusBarTexture(path or "Interface\\Buttons\\WHITE8X8")
			end
			if not ns.Art.Apply(half.hotline, "hotline") then
				half.hotline:SetColorTexture(0, 0, 0, 0)
			end
			half.hotline:SetBlendMode("ADD")
		end
	end
	if ns.Globes.Blade and ns.Art.Apply(ns.Globes.Blade.tex, "blade") then
		ns.Globes.Blade.tex:SetTexCoord(0, 1, 0, BLADE_H / 256)
	end
	ns.Globes.ShowGlass()
	ns.Globes.UpdateHealth()
	ns.Globes.UpdatePower()
end

-- The glass over the whole console, or with the globes scaled separately, a piece in each pod.
function ns.Globes.ShowGlass()
	local glass = ns.GlassFrame
	if not glass then return end
	local path = ns.Art.Path("glass")
	local split = glass.split and true or false
	if path and ns.Art.Apply(glass.tex, "glass") then
		glass.tex:SetTexCoord(unpack(ns.FRAME_TEXCOORD))
		glass.tex:SetBlendMode("ADD")
	end
	glass:SetShown(path ~= nil and not split)
	for side, pod in pairs(ns.Pods or {}) do
		local piece = pod.glass
		if piece then
			if path and ns.Art.Apply(piece.tex, "glass") then
				ns.CropPiece(piece.tex, side)
				piece.tex:SetBlendMode("ADD")
			end
			piece:SetShown(path ~= nil and split)
		end
	end
end

function ns.Globes.Init()
	local parent = ns.Cluster
	ns.HealthGlobe = MakeGlobe("SanctuaryUIHealthGlobe", ns.Pods.health, { 0.72, 0.08, 0.08 })
	ns.ResourceGlobe = MakeGlobe("SanctuaryUIResourceGlobe", ns.Pods.resource, { 0.15, 0.4, 0.85 })

	-- Click your health globe to target yourself; right-click for your unit menu (leave group,
	-- loot, raid markers). It covers the globe, so it passes hover on for the numbers.
	local click = CreateFrame("Button", "SanctuaryUIHealthClick", ns.Pods.health, "SecureUnitButtonTemplate")
	click:SetAttribute("unit", "player")
	click:SetAttribute("*type1", "target")
	click:SetAttribute("*type2", "togglemenu")
	click:RegisterForClicks("AnyUp")
	click:SetScript("OnEnter", function()
		ns.HealthGlobe.hovered = true
		ns.Globes.ApplyNumbers()
	end)
	click:SetScript("OnLeave", function()
		ns.HealthGlobe.hovered = false
		ns.Globes.ApplyNumbers()
	end)
	ns.Globes.click = click

	ns.ResourceGlobe.Halves = {
		left = MakeHalf(ns.ResourceGlobe, "left"),
		right = MakeHalf(ns.ResourceGlobe, "right"),
	}

	-- Scrolling liquid where the client supports masks and clipping; otherwise the static
	-- baked-circle liquid stays.
	if ns.Liquid and ns.Liquid.Supported() then
		-- Health leaves a damage ghost and beats when low; both big globes carry motes.
		ns.HealthGlobe.pool = ns.Liquid.Attach(ns.HealthGlobe, ns.HealthGlobe.Liquid, { motes = 7, ghost = true, pulse = true })
		ns.ResourceGlobe.pool = ns.Liquid.Attach(ns.ResourceGlobe, ns.ResourceGlobe.Liquid, { motes = 7 })
		for _, globe in ipairs({ ns.HealthGlobe, ns.ResourceGlobe }) do
			globe.Shade = ns.Liquid.Shade(globe)
		end
		for _, half in pairs(ns.ResourceGlobe.Halves) do
			half.pool = ns.Liquid.Attach(ns.ResourceGlobe, half.bar, { motes = 4, slices = 8 })
		end
		-- Incoming heals on the health globe, the cast's cost on the resource globe.
		ns.Liquid.Band(ns.HealthGlobe.pool, "heal")
		ns.Liquid.Band(ns.HealthGlobe.pool, "hot")
		ns.Liquid.Band(ns.HealthGlobe.pool, "absorb")
		ns.Liquid.Shield(ns.HealthGlobe.pool)
		ns.Liquid.Band(ns.ResourceGlobe.pool, "cost")
		for _, half in pairs(ns.ResourceGlobe.Halves) do
			ns.Liquid.Band(half.pool, "cost")
		end
	end

	ns.ResourceGlobe.Pips = {}
	for i = 1, PIP_MAX do
		ns.ResourceGlobe.Pips[i] = MakePip(ns.ResourceGlobe)
	end

	ns.Globes.Layout()
	ns.Globes.RefreshArt()
	if ns.Liquid then
		ns.Liquid.Start()
	end

	local events = CreateFrame("Frame", nil, parent)
	events:RegisterUnitEvent("UNIT_HEALTH", "player")
	events:RegisterUnitEvent("UNIT_MAXHEALTH", "player")
	events:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
	events:RegisterUnitEvent("UNIT_MAXPOWER", "player")
	events:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
	events:RegisterEvent("RUNE_POWER_UPDATE")
	events:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
	events:RegisterEvent("PLAYER_REGEN_DISABLED")
	events:RegisterEvent("PLAYER_REGEN_ENABLED")
	events:RegisterUnitEvent("UNIT_HEAL_PREDICTION", "player")
	events:RegisterUnitEvent("UNIT_ABSORB_AMOUNT_CHANGED", "player")
	for _, event in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
		"UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_SUCCEEDED" }) do
		events:RegisterUnitEvent(event, "player")
	end
	events:SetScript("OnEvent", function(_, event, _, arg2, spellID)
		if event == "UNIT_HEAL_PREDICTION" or event == "UNIT_ABSORB_AMOUNT_CHANGED" then
			ns.Globes.UpdateHealPrediction()
		elseif event == "UNIT_SPELLCAST_START" then
			ns.Globes.CastStarted(spellID)
			ns.Globes.UpdatePower()
		elseif event:find("^UNIT_SPELLCAST_") then
			ns.Globes.CastEnded()
			ns.Globes.UpdatePower()
		elseif event == "PLAYER_REGEN_DISABLED" then
			ns.Globes.SetCombat(true)
		elseif event == "PLAYER_REGEN_ENABLED" then
			ns.Globes.SetCombat(false)
		elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
			ns.Globes.UpdateHealth()
		elseif event == "UNIT_POWER_UPDATE" then
			-- unit, power token. Not the health globe: with hidden health, its update reads as a
			-- change and sloshes.
			-- (Combo points and the like come here too; the pips read those themselves.)
			local key = arg2 ~= nil and not Secret(arg2) and TOKEN_TYPE[arg2]
			local powerType = key and Enum and Enum.PowerType and Enum.PowerType[key]
			if powerType then ReadPower(powerType) end
			ns.Globes.UpdatePower()
		elseif event == "UNIT_MAXPOWER" then
			ns.Globes.UpdatePower()
		else
			-- Entering the world or a new pool (a form that changes it): read afresh. Other form,
			-- stance and spec events redraw from what the server last said; wiping it there
			-- showed the client's running guess again (stealth, a rogue's or druid's form event).
			if event == "PLAYER_ENTERING_WORLD" or event == "UNIT_DISPLAYPOWER" then
				ns.Globes.ReadServerPower()
			end
			ns.Globes.UpdateHealth()
			ns.Globes.UpdatePower()
		end
	end)
	if ns.OnHotChanged then ns.OnHotChanged(function() ns.Globes.UpdateHealPrediction() end) end
	ns.Globes.SetCombat(UnitAffectingCombat and UnitAffectingCombat("player") or false)
	ns.Globes.UpdateHealth()
	ns.Globes.UpdatePower()
end
