SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.ProcGlow = ns.ProcGlow or {}

-- Lights a socket the moment a skill that only works under a condition becomes available:
-- Overpower after a dodge, Revenge after a block, Execute on a target in range of it.
--
-- This client sends no proc events for these. What it does tell addons, in combat too, is
-- whether an action is usable, so the skills below are watched for that turning true. A skill
-- that is merely short of rage reads as unusable, so it lights when it can really be pressed.
--
-- The look: a one-off reveal (the icon flashes and a ring of light bursts off the socket), then
-- two sparks chase around the edge over a quick pulse until the skill is used or lapses.
-- It is ice blue and it moves, where ActiveSkill.lua's burn is amber and stays in place, so a
-- skill you can press now never reads as a skill that is already running.

-- English name to rank 1 ID, read back as a name so every rank and locale matches.
local REACTIVE = {
	["Overpower"] = 7384,
	["Revenge"] = 6572,
	["Execute"] = 5308,
	["Victory Rush"] = 34428,
	["Riposte"] = 14251,
	["Counterattack"] = 19306,
	["Mongoose Bite"] = 1495,
	["Hammer of Wrath"] = 24275,
}

local CHECK_EVERY = 0.05
local TEST_LENGTH = 6

local REVEAL = 0.55
local FLASH_PEAK = 1
local WAVE_FROM, WAVE_TO, WAVE_PEAK = 0.95, 1.32, 1
local FADE = 0.2

local RIM_LOW, RIM_HIGH, RIM_PERIOD = 0.6, 1, 0.7
-- A soft halo breathes with the rim while the skill is available.
local HALO_LOW, HALO_HIGH = 0.35, 0.8
-- socket-hover.png maps the button to its inner 96 of 128 px.
local RIM_OUTSET = 16 / 96
-- frameGlow's bright rim spans 0.453 of the texture; this puts it on the icon's edge.
local GLOW_OUTSET = (1 / 0.453 - 1) / 2

local SPARKS = 2
local TRAIL = 8
local LAP = 1.15 -- seconds for a spark to go round
local TRAIL_STEP = 0.02 -- of a lap, between one trail mote and the next
local HEAD_SIZE, TAIL_SIZE = 0.44, 0.14 -- of the button's width
local SPARK_COLOR = { 0.8, 0.93, 1 }
-- The rim and glow art is gold and orange, so it is desaturated before these go on.
local RIM_COLOR = { 0.55, 0.82, 1 }
local GLOW_COLOR = { 0.4, 0.68, 1 }
local FLASH_COLOR = { 0.65, 0.85, 1 }

local GetSpellName = (C_Spell and C_Spell.GetSpellName) or function(id)
	return (GetSpellInfo(id))
end

local names = {} -- every name a reactive skill goes by
local watched = {} -- button -> true: the sockets holding one
local lit = {} -- button -> its effect, while it shows or fades
local dirty = true
local testUntil

local function Secret(value)
	return ns.Secret(value)
end

local function Tint(texture, color)
	texture:SetDesaturated(true)
	texture:SetVertexColor(color[1], color[2], color[3])
end

local function Enabled()
	return ns.DB().buttons.procGlow
end

---------------------------------------------------------------------------
-- Art on one socket, made the first time it lights.

local function Build(button)
	if button.sanctuaryProc then return button.sanctuaryProc end
	local ring = button.sanctuaryRingFrame
	local frame = CreateFrame("Frame", nil, button)
	frame:SetAllPoints()
	-- Under the ring frame, which carries the key and count text; over the cooldown swipe.
	frame:SetFrameLevel((ring and ring:GetFrameLevel() or button:GetFrameLevel() + 6) - 1)
	frame:Hide()
	local fx = { frame = frame, sparks = {} }

	local rim = frame:CreateTexture(nil, "ARTWORK")
	if ns.Art.Apply(rim, "socketHover") then
		rim:SetBlendMode("ADD")
		Tint(rim, RIM_COLOR)
		fx.rim = rim
	else
		rim:Hide()
	end

	local halo = frame:CreateTexture(nil, "BORDER")
	if ns.Art.Apply(halo, "buttonGlow") then
		halo:SetBlendMode("ADD")
		Tint(halo, GLOW_COLOR)
		fx.halo = halo
	else
		halo:Hide()
	end

	-- A copy of the icon, added over itself, is the flash.
	local flash = frame:CreateTexture(nil, "ARTWORK", nil, 1)
	flash:SetAllPoints(button)
	flash:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	flash:SetBlendMode("ADD")
	flash:SetVertexColor(FLASH_COLOR[1], FLASH_COLOR[2], FLASH_COLOR[3])
	flash:SetAlpha(0)
	fx.flash = flash

	local wave = frame:CreateTexture(nil, "OVERLAY")
	if ns.Art.Apply(wave, "buttonGlow") then
		Tint(wave, GLOW_COLOR)
	else
		wave:SetColorTexture(GLOW_COLOR[1], GLOW_COLOR[2], GLOW_COLOR[3], 0.3)
	end
	wave:SetBlendMode("ADD")
	wave:SetAlpha(0)
	fx.wave = wave

	for i = 1, SPARKS * TRAIL do
		local mote = frame:CreateTexture(nil, "OVERLAY", nil, 1)
		if ns.Art.Apply(mote, "mote") then
			mote:SetVertexColor(SPARK_COLOR[1], SPARK_COLOR[2], SPARK_COLOR[3])
		else
			mote:SetColorTexture(SPARK_COLOR[1], SPARK_COLOR[2], SPARK_COLOR[3])
		end
		mote:SetBlendMode("ADD")
		fx.sparks[i] = mote
	end

	button.sanctuaryProc = fx
	return fx
end

-- Sizes follow the button, which the rows and the console scale freely.
local function Fit(button, fx)
	local w, h = button:GetSize()
	if not w or w <= 0 or (fx.w == w and fx.h == h) then return end
	fx.w, fx.h = w, h
	if fx.rim then
		fx.rim:ClearAllPoints()
		fx.rim:SetPoint("TOPLEFT", button, "TOPLEFT", -w * RIM_OUTSET, h * RIM_OUTSET)
		fx.rim:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", w * RIM_OUTSET, -h * RIM_OUTSET)
	end
	if fx.halo then
		fx.halo:ClearAllPoints()
		fx.halo:SetPoint("TOPLEFT", button, "TOPLEFT", -w * GLOW_OUTSET, h * GLOW_OUTSET)
		fx.halo:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", w * GLOW_OUTSET, -h * GLOW_OUTSET)
	end
	for i = 1, TRAIL do
		local size = w * (HEAD_SIZE + (TAIL_SIZE - HEAD_SIZE) * (i - 1) / (TRAIL - 1))
		for spark = 0, SPARKS - 1 do
			fx.sparks[spark * TRAIL + i]:SetSize(size, size)
		end
	end
end

-- Where a spark is along the socket's edge: position is laps from the top left, clockwise.
local function OnEdge(position, w, h)
	local along = (position % 1) * 2 * (w + h)
	if along < w then return along, 0 end
	along = along - w
	if along < h then return w, along end
	along = along - h
	if along < w then return w - along, h end
	return 0, h - (along - w)
end

local function Animate(button, fx, now)
	Fit(button, fx)
	if not fx.w then return end

	local since = now - fx.start
	if since < REVEAL then
		local t = since / REVEAL
		local left = 1 - t
		fx.flash:SetAlpha(FLASH_PEAK * left * left)
		local eased = 1 - left * left
		local scale = (WAVE_FROM + (WAVE_TO - WAVE_FROM) * eased) * (1 + 2 * GLOW_OUTSET)
		local ow, oh = fx.w * (scale - 1) / 2, fx.h * (scale - 1) / 2
		fx.wave:ClearAllPoints()
		fx.wave:SetPoint("TOPLEFT", button, "TOPLEFT", -ow, oh)
		fx.wave:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", ow, -oh)
		fx.wave:SetAlpha(WAVE_PEAK * left * left)
	elseif not fx.revealed then
		fx.revealed = true
		fx.flash:SetAlpha(0)
		fx.wave:SetAlpha(0)
	end

	local breath = 0.5 + 0.5 * math.sin(now * 2 * math.pi / RIM_PERIOD)
	if fx.rim then
		fx.rim:SetAlpha(RIM_LOW + (RIM_HIGH - RIM_LOW) * breath)
	end
	if fx.halo then
		fx.halo:SetAlpha(HALO_LOW + (HALO_HIGH - HALO_LOW) * breath)
	end

	local head = now / LAP
	for spark = 0, SPARKS - 1 do
		for i = 1, TRAIL do
			local mote = fx.sparks[spark * TRAIL + i]
			local x, y = OnEdge(head + spark / SPARKS - (i - 1) * TRAIL_STEP, fx.w, fx.h)
			mote:ClearAllPoints()
			mote:SetPoint("CENTER", button, "TOPLEFT", x, -y)
			local fall = 1 - (i - 1) / TRAIL
			mote:SetAlpha(fall * fall)
		end
	end

	if fx.fading then
		local left = 1 - (now - fx.fading) / FADE
		if left <= 0 then
			fx.frame:Hide()
			fx.fading = nil
			lit[button] = nil
		else
			fx.frame:SetAlpha(left)
		end
	end
end

local function Light(button, now)
	local fx = button.sanctuaryProc
	if fx and lit[button] then
		-- Came back while fading: carry on, without a second reveal.
		if fx.fading then
			fx.fading = nil
			fx.frame:SetAlpha(1)
		end
		return
	end
	fx = Build(button)
	fx.start, fx.revealed, fx.fading = now, nil, nil
	local icon = button.icon and button.icon:GetTexture()
	if icon and not Secret(icon) then
		fx.flash:SetTexture(icon)
		fx.flash:Show()
	else
		fx.flash:Hide()
	end
	fx.frame:SetAlpha(1)
	fx.frame:Show()
	lit[button] = fx
	Animate(button, fx, now)
end

local function Fade(button, now)
	local fx = lit[button]
	if fx and not fx.fading then fx.fading = now end
end

local function Douse(button)
	local fx = lit[button]
	if fx then
		fx.frame:Hide()
		fx.fading = nil
		lit[button] = nil
	end
end

---------------------------------------------------------------------------

local function HoldsReactive(button)
	if not button.GetSpellId then return false end
	local ok, id = pcall(button.GetSpellId, button)
	if not ok or Secret(id) or not id then return false end
	if testUntil then return true end
	local name = GetSpellName(id)
	return name and not Secret(name) and names[name] or false
end

local function Rescan()
	dirty = false
	local enabled = Enabled() or testUntil
	ns.ActionBar.ForEachButton(function(button)
		if enabled and ns.ActionBar.IsLive(button) and HoldsReactive(button) then
			watched[button] = true
		else
			watched[button] = nil
			Douse(button)
		end
	end)
end

local function Ready(button)
	if testUntil then return true end
	local ok, usable = pcall(button.IsUsable, button)
	return ok and not Secret(usable) and usable or false
end

-- /sanctuary proc: every skill on the bars plays it for a few seconds, no dodge needed.
function ns.ProcGlow.Test()
	testUntil = GetTime() + TEST_LENGTH
	for button in pairs(lit) do Douse(button) end
	dirty = true
	ns.Print(("proc highlight on every skill for %d seconds"):format(TEST_LENGTH))
end

function ns.ProcGlow.ApplySettings()
	dirty = true
end

function ns.ProcGlow.Init()
	if not ns.ActionBar.ForEachButton then return end
	for english, id in pairs(REACTIVE) do
		names[english] = true
		local name = GetSpellName(id)
		if name and not Secret(name) then names[name] = true end
	end

	local driver = CreateFrame("Frame", nil, ns.Cluster)
	for _, event in ipairs({
		"PLAYER_ENTERING_WORLD", "SPELLS_CHANGED", "ACTIONBAR_SLOT_CHANGED",
		"ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR", "UPDATE_SHAPESHIFT_FORM",
	}) do
		pcall(driver.RegisterEvent, driver, event)
	end
	driver:SetScript("OnEvent", function() dirty = true end)
	-- Paging swaps a button's action without an event of its own.
	local LAB = LibStub("LibActionButton-1.0")
	LAB.RegisterCallback(ns.ProcGlow, "OnButtonUpdate", function() dirty = true end)
	LAB.RegisterCallback(ns.ProcGlow, "OnButtonContentsChanged", function() dirty = true end)

	local nextCheck = 0
	driver:SetScript("OnUpdate", function()
		local now = GetTime()
		if testUntil and now >= testUntil then
			testUntil = nil
			dirty = true
		end
		if now >= nextCheck then
			nextCheck = now + CHECK_EVERY
			if dirty then Rescan() end
			for button in pairs(watched) do
				if Ready(button) then
					Light(button, now)
				else
					Fade(button, now)
				end
			end
		end
		for button, fx in pairs(lit) do
			Animate(button, fx, now)
		end
	end)
end
