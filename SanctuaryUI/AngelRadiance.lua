SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.AngelRadiance = ns.AngelRadiance or {}

-- Golden light on the console's angel: the wings light up, crests of light run down the feathers
-- root to tip, and sparks fall from them. A proc visual; what sets it off is not decided yet, so for now it has only
-- Show / Hide for a caller to use and /sanctuary radiance to look at it.
--
-- The art is the statue itself relit (tools/blender/angel_radiance.py), drawn over the console
-- with ADD, so it has to sit texel for texel on the angel: the cell's place in frame.png is below.

-- angel-radiance.png: 5 x 5 cells of 384 px in 2048 x 2048, 24 frames, looping.
local SPEC = { w = 2048, h = 2048, cell = 384, cols = 5, frames = 24, seconds = 2.4 }
-- A cell's top left corner and its span in frame.png px (tools/blender/angel_radiance_art.py
-- CELL_X, CELL_Y, CELL): the light is drawn at twice the console's texel density.
local CELL_X, CELL_Y, CELL_SPAN = 1420, 20, 192

local FADE_IN, FADE_OUT = 0.3, 0.7
-- It arrives brighter than it stays.
local FLARE, FLARE_LENGTH = 0.6, 0.9
local TEST_LENGTH = 8

-- Sparks shed by the wings, falling. They move every frame, which a flipbook could not do
-- without ghosting. Positions are frame.png px; speeds are px a second.
local MOTES = 18
-- Where they come off: down the near wing's outer feathers, and a few from the far wing.
local SHED = {
	{ 1514, 64 }, { 1526, 72 }, { 1538, 82 }, { 1548, 92 }, { 1554, 104 }, { 1558, 116 },
	{ 1563, 128 }, { 1567, 140 }, { 1572, 152 }, { 1577, 164 }, { 1582, 176 }, { 1587, 188 },
	{ 1540, 120 }, { 1466, 62 },
}
local MOTE_LIFE = { 0.9, 1.7 }
local MOTE_SIZE = { 9, 16 } -- mote.png's bright core is a fifth of this
local MOTE_FALL = { 10, 22 } -- starting speed down
local MOTE_DRIFT = { 3, 13 } -- sideways: outward, off the wing and into the air beside it
local MOTE_GRAVITY = 16
local MOTE_COLOR = { 1, 0.94, 0.72 } -- paler than the wing, or they vanish against it

-- What makes it noticed from the corner of the eye, kept short of garish: a glow behind the
-- statue that swells as each crest leaves the wing roots, and on arrival a shaft of light that
-- lands on the wings while a ring of that glow bursts outward. angel-radiance-fx.png holds the
-- glow (left half) and the shaft (right half). Positions and sizes are frame.png px.
local HALO = { x = 1524, y = 112, size = 300, low = 0.16, high = 0.40 }
local HALO_COLOR = { 1, 0.74, 0.32 }
local BURST = { length = 0.75, from = 0.7, to = 1.7, peak = 0.9 }
local SHAFT = { x = 1502, foot = 110, width = 84, height = 230, length = 1.0, peak = 0.95 }
local SHAFT_COLOR = { 1, 0.9, 0.62 }

local fx
local shown, since, fadeFrom, fadeStart, hideAt

local function Cell(tex, i)
	local row = math.floor(i / SPEC.cols)
	local col = i - row * SPEC.cols
	local du, dv = 0.5 / SPEC.w, 0.5 / SPEC.h
	tex:SetTexCoord(col * SPEC.cell / SPEC.w + du, (col + 1) * SPEC.cell / SPEC.w - du,
		row * SPEC.cell / SPEC.h + dv, (row + 1) * SPEC.cell / SPEC.h - dv)
end

-- Over the angel, in its pod, so it follows the globes' own scale.
local function Place()
	local metrics = ns.Metrics and ns.Metrics()
	local pod = ns.Pods and ns.Pods.resource
	if not (metrics and pod) then return false end
	local s = metrics.scale
	fx.frame:SetParent(pod)
	fx.frame:SetSize(CELL_SPAN * s, CELL_SPAN * s)
	fx.frame:ClearAllPoints()
	fx.frame:SetPoint("TOPLEFT", pod, "BOTTOM", CELL_X * s - metrics.width / 2,
		metrics.baseY + metrics.height / 2 - CELL_Y * s)
	fx.frame:SetFrameLevel(ns.Cluster:GetFrameLevel() + ns.LEVEL.console + 1)
	-- The glow goes behind the globe and the console, so the statue stands dark against it.
	fx.behind:SetParent(pod)
	fx.behind:SetAllPoints(fx.frame)
	fx.behind:SetFrameLevel(ns.Cluster:GetFrameLevel() + ns.LEVEL.aura)
	fx.scale = s
	return true
end

local function Between(range)
	return range[1] + (range[2] - range[1]) * math.random()
end

local function Shed(mote, now, delay)
	local from = SHED[math.random(#SHED)]
	mote.born = now + (delay or 0)
	mote.life = Between(MOTE_LIFE)
	mote.x, mote.y = from[1] + math.random() * 6 - 3, from[2] + math.random() * 6 - 3
	mote.vx, mote.vy = Between(MOTE_DRIFT), Between(MOTE_FALL)
	mote.size = Between(MOTE_SIZE)
end

local function DrawMotes(now, level)
	local s = fx.scale
	for _, mote in ipairs(fx.motes) do
		local age = now - mote.born
		if age >= mote.life then
			-- None are shed once the light is going out.
			if shown then
				Shed(mote, now, math.random() * 0.4)
			end
			age = -1
		end
		if age < 0 then
			mote.tex:SetAlpha(0)
		else
			local t = age / mote.life
			local x = mote.x + mote.vx * age
			local y = mote.y + mote.vy * age + 0.5 * MOTE_GRAVITY * age * age
			local size = mote.size * (1 - 0.5 * t) * s
			mote.tex:SetSize(size, size)
			mote.tex:ClearAllPoints()
			mote.tex:SetPoint("CENTER", fx.frame, "TOPLEFT", (x - CELL_X) * s, -(y - CELL_Y) * s)
			-- Quick to appear, slow to die.
			mote.tex:SetAlpha(level * math.min(1, t * 8) * (1 - t * t))
		end
	end
end

local function Centre(tex, x, y, w, h)
	local s = fx.scale
	tex:SetSize(w * s, h * s)
	tex:ClearAllPoints()
	tex:SetPoint("CENTER", fx.frame, "TOPLEFT", (x - CELL_X) * s, -(y - CELL_Y) * s)
end

local function DrawAttention(now, level, phase)
	if not fx.halo then return end
	-- The crests leave the roots at the top of the loop and, fainter, halfway through it.
	local first, second = 1 - phase, 1 - (phase + 0.5) % 1
	local swell = math.max(first * first * first, 0.6 * second * second * second)
	Centre(fx.halo, HALO.x, HALO.y, HALO.size, HALO.size)
	fx.halo:SetAlpha(level * (HALO.low + (HALO.high - HALO.low) * swell))

	-- The arrival does not wait for the fade in: it is the part meant to be caught.
	local strength = shown and 1 or level
	local t = (now - since) / BURST.length
	if t < 1 then
		local size = HALO.size * (BURST.from + (BURST.to - BURST.from) * (1 - (1 - t) * (1 - t)))
		Centre(fx.burst, HALO.x, HALO.y, size, size)
		fx.burst:SetAlpha(strength * BURST.peak * math.min(1, t * 10) * (1 - t) * (1 - t))
	else
		fx.burst:SetAlpha(0)
	end
	t = (now - since) / SHAFT.length
	if t < 1 then
		Centre(fx.shaft, SHAFT.x, SHAFT.foot - SHAFT.height / 2, SHAFT.width * (1.15 - 0.5 * t), SHAFT.height)
		fx.shaft:SetAlpha(strength * SHAFT.peak * math.min(1, t * 12) * (1 - t) * (1 - t))
	else
		fx.shaft:SetAlpha(0)
	end
end

local function Draw(now)
	local level
	if shown then
		level = math.min(1, (now - fadeStart) / FADE_IN)
		level = fadeFrom + (1 - fadeFrom) * level
	else
		level = fadeFrom * (1 - (now - fadeStart) / FADE_OUT)
		if level <= 0 then
			fx.frame:Hide()
			fx.behind:Hide()
			return
		end
	end
	fx.level = level
	local flare = math.max(0, 1 - (now - since) / FLARE_LENGTH)
	local bright = 1 + FLARE * flare * flare

	local phase = ((now - since) / SPEC.seconds) % 1
	local pos = phase * SPEC.frames
	local i = math.floor(pos)
	local f = pos - i
	if i ~= fx.i then
		fx.i = i
		Cell(fx.a, i)
		Cell(fx.b, (i + 1) % SPEC.frames)
	end
	-- Crossfade weights in the colour (with ADD that is the same as alpha), strength in the alpha.
	local a, b = (1 - f) * bright, f * bright
	fx.a:SetVertexColor(a, a, a)
	fx.b:SetVertexColor(b, b, b)
	fx.a:SetAlpha(level)
	fx.b:SetAlpha(level)
	DrawMotes(now, level)
	DrawAttention(now, level, phase)
end

local function Build()
	if fx then return true end
	if not (ns.Cluster and ns.Art.Require("angelRadiance")) then return false end
	local frame = CreateFrame("Frame", nil, ns.Cluster)
	frame:EnableMouse(false)
	frame:Hide()
	local behind = CreateFrame("Frame", nil, ns.Cluster)
	behind:EnableMouse(false)
	behind:Hide()
	fx = { frame = frame, behind = behind, level = 0 }
	for _, key in ipairs({ "a", "b" }) do
		local tex = frame:CreateTexture(nil, "ARTWORK")
		tex:SetAllPoints()
		if not ns.Art.Apply(tex, "angelRadiance") then
			fx = nil
			return false
		end
		tex:SetBlendMode("ADD")
		fx[key] = tex
	end
	fx.motes = {}
	for i = 1, MOTES do
		local tex = frame:CreateTexture(nil, "OVERLAY")
		if ns.Art.Apply(tex, "mote") then
			tex:SetVertexColor(MOTE_COLOR[1], MOTE_COLOR[2], MOTE_COLOR[3])
		else
			tex:SetColorTexture(MOTE_COLOR[1], MOTE_COLOR[2], MOTE_COLOR[3])
		end
		tex:SetBlendMode("ADD")
		tex:SetAlpha(0)
		fx.motes[i] = { tex = tex, born = 0, life = 0 }
	end
	-- Without its art the effect still plays, just without these.
	if ns.Art.Require("angelRadianceFx") then
		local function Piece(parent, layer, left, right, color)
			local tex = parent:CreateTexture(nil, layer)
			ns.Art.Apply(tex, "angelRadianceFx")
			tex:SetTexCoord(left, right, 0, 1)
			tex:SetVertexColor(color[1], color[2], color[3])
			tex:SetBlendMode("ADD")
			tex:SetAlpha(0)
			return tex
		end
		fx.halo = Piece(behind, "BACKGROUND", 0, 0.5, HALO_COLOR)
		fx.burst = Piece(behind, "BORDER", 0, 0.5, HALO_COLOR)
		fx.shaft = Piece(frame, "BORDER", 0.5, 1, SHAFT_COLOR)
	end
	local nextPlace = 0
	frame:SetScript("OnUpdate", function()
		local now = GetTime()
		if hideAt and now >= hideAt then
			ns.AngelRadiance.Hide()
		end
		-- The console can be rescaled while this shows.
		if now >= nextPlace then
			nextPlace = now + 0.5
			Place()
		end
		Draw(now)
	end)
	return true
end

-- Lights the wings until Hide, or for `seconds` if given.
function ns.AngelRadiance.Show(seconds)
	if not Build() or not Place() then return end
	local now = GetTime()
	hideAt = seconds and now + seconds or nil
	if shown then return end
	shown = true
	fadeFrom = fx.frame:IsShown() and fx.level or 0
	fadeStart = now
	if not fx.frame:IsShown() then
		since = now
		fx.i = nil
		-- The first sparks come off as the flare lands, then steadily.
		for i, mote in ipairs(fx.motes) do
			Shed(mote, now, 0.15 + (i - 1) / MOTES * MOTE_LIFE[2])
		end
	end
	fx.frame:Show()
	fx.behind:Show()
	Draw(now)
end

function ns.AngelRadiance.Hide()
	hideAt = nil
	if not (fx and shown) then return end
	shown = false
	fadeFrom, fadeStart = fx.level, GetTime()
end

-- /sanctuary radiance: on for a few seconds, or off again.
function ns.AngelRadiance.Test()
	if shown then
		ns.AngelRadiance.Hide()
		return
	end
	ns.AngelRadiance.Show(TEST_LENGTH)
	if shown then
		ns.Print(("angel radiance for %d seconds"):format(TEST_LENGTH))
	else
		ns.Print("angel radiance art is missing")
	end
end
