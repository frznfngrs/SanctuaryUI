SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.AngelRadiance = ns.AngelRadiance or {}
local A = ns.AngelRadiance

-- Golden light on the console's angel: the wings light up, crests of light run down the feathers
-- root to tip, sparks fall from them, and a glow swells behind the statue. StatueEyes.lua shows
-- it while a buff you choose is on you (the "wings" effect there), or as a preview.
--
-- It is shown by an aura slot, where the client plays the animations and no addon code runs,
-- so everything here is art plus animation groups built once: nothing is drawn frame by frame.
--
-- The wing art is the statue itself relit (tools/blender/angel_radiance.py), drawn over the
-- console with ADD, so it has to sit texel for texel on the angel.

-- angel-radiance.png: 8 x 8 frames filling the sheet, looping. A frame's top left corner and
-- its span in frame.png px (tools/blender/angel_radiance_art.py CELL_X, CELL_Y, CELL).
local FLIP = { rows = 8, cols = 8, frames = 64, seconds = 2.4 }
A.CORNER, A.SPAN = { 1420, 20 }, 192

local FADE_IN = 0.3
-- It arrives brighter than it stays.
local FLARE, FLARE_LENGTH = 0.6, 0.9

-- Sparks shed by the wings, falling. Positions are frame.png px; speeds are px a second.
local MOTES = 18
-- Where they come off: down the near wing's outer feathers, and a few from the far wing.
local SHED = {
	{ 1514, 64 }, { 1526, 72 }, { 1538, 82 }, { 1548, 92 }, { 1554, 104 }, { 1558, 116 },
	{ 1563, 128 }, { 1567, 140 }, { 1572, 152 }, { 1577, 164 }, { 1582, 176 }, { 1587, 188 },
	{ 1540, 120 }, { 1466, 62 },
}
local MOTE_LIFE = { 0.9, 1.7 }
local MOTE_REST = { 0.05, 0.9 } -- dark between one fall and the next
local MOTE_SIZE = { 9, 16 } -- mote.png's bright core is a fifth of this
local MOTE_FALL = { 10, 22 } -- starting speed down
local MOTE_DRIFT = { 3, 13 } -- sideways: outward, off the wing and into the air beside it
local MOTE_GRAVITY = 16
local MOTE_COLOR = { 1, 0.94, 0.72 } -- paler than the wing, or they vanish against it

-- What makes it noticed from the corner of the eye, kept short of garish: a glow behind the
-- statue that swells as each crest leaves the wing roots, and on arrival a shaft of light that
-- lands on the wings while a ring of that glow bursts outward. angel-radiance-fx.png holds the
-- glow (left half) and the shaft (right half). Positions and sizes are frame.png px.
local HALO = { x = 1524, y = 112, size = 300, low = 0.16, high = 0.40, second = 0.30 }
local HALO_COLOR = { 1, 0.74, 0.32 }
local BURST = { length = 0.75, from = 0.7, to = 1.7, peak = 0.9 }
local SHAFT = { x = 1502, foot = 110, width = 84, height = 230, length = 1.0, peak = 0.95 }
local SHAFT_COLOR = { 1, 0.9, 0.62 }

function A.ArtReady()
	return ns.Art.Require("angelRadiance") and ns.Art.Require("angelRadianceFx") and ns.Art.Path("mote") and true or false
end

local function Between(range)
	return range[1] + (range[2] - range[1]) * math.random()
end

local function Group(host, groups, looping)
	local group = host:CreateAnimationGroup()
	if looping then
		group:SetLooping("REPEAT")
	else
		group:SetToFinalAlpha(true)
	end
	groups[#groups + 1] = group
	return group
end

local function Alpha(group, tex, from, to, seconds, order, delay)
	local alpha = group:CreateAnimation("Alpha")
	alpha:SetTarget(tex)
	alpha:SetFromAlpha(from)
	alpha:SetToAlpha(to)
	alpha:SetDuration(seconds)
	alpha:SetOrder(order or 1)
	if delay then alpha:SetStartDelay(delay) end
	return alpha
end

local function Flip(group, tex)
	local flip = group:CreateAnimation("FlipBook")
	flip:SetTarget(tex)
	flip:SetDuration(FLIP.seconds)
	flip:SetOrder(1)
	flip:SetFlipBookRows(FLIP.rows)
	flip:SetFlipBookColumns(FLIP.cols)
	flip:SetFlipBookFrames(FLIP.frames)
end

local function Piece(host, layer, slot, color, left, right)
	local tex = host:CreateTexture(nil, layer)
	tex:SetTexture(ns.Art.Path(slot))
	if left then tex:SetTexCoord(left, right, 0, 1) end
	if color then tex:SetVertexColor(color[1], color[2], color[3]) end
	tex:SetBlendMode("ADD")
	return tex
end

-- Centred on a frame.png spot. The host sits on the wing art's cell.
local function Centre(tex, host, s, x, y, w, h)
	tex:SetSize(w * s, h * s)
	tex:SetPoint("CENTER", host, "TOPLEFT", (x - A.CORNER[1]) * s, -(y - A.CORNER[2]) * s)
end

local function DressFront(host, s, groups)
	local loop = Group(host, groups, true)
	local arrive = Group(host, groups)

	local wings = Piece(host, "ARTWORK", "angelRadiance")
	wings:SetAllPoints(host)
	Flip(loop, wings)
	Alpha(arrive, wings, 0, 1, FADE_IN)
	-- The same light again, dying away: the brightness it arrives with.
	local flare = Piece(host, "ARTWORK", "angelRadiance")
	flare:SetAllPoints(host)
	flare:SetAlpha(0)
	Flip(loop, flare)
	Alpha(arrive, flare, FLARE, 0, FLARE_LENGTH):SetSmoothing("OUT")

	local shaft = Piece(host, "BORDER", "angelRadianceFx", SHAFT_COLOR, 0.5, 1)
	Centre(shaft, host, s, SHAFT.x, SHAFT.foot - SHAFT.height / 2, SHAFT.width, SHAFT.height)
	shaft:SetAlpha(0)
	Alpha(arrive, shaft, SHAFT.peak, 0, SHAFT.length):SetSmoothing("OUT")
	local narrow = arrive:CreateAnimation("Scale")
	narrow:SetTarget(shaft)
	narrow:SetScaleFrom(1.15, 1)
	narrow:SetScaleTo(0.65, 1)
	narrow:SetDuration(SHAFT.length)
	narrow:SetOrder(1)

	-- Each spark falls the same way every time, from its own place and in its own time: with
	-- this many of them, out of step, it does not read as a pattern.
	for i = 1, MOTES do
		local from = SHED[(i - 1) % #SHED + 1]
		local life, rest = Between(MOTE_LIFE), Between(MOTE_REST) + (i - 1) / MOTES * 0.6
		local size = Between(MOTE_SIZE)
		local mote = Piece(host, "OVERLAY", "mote", MOTE_COLOR)
		Centre(mote, host, s, from[1] + math.random() * 6 - 3, from[2] + math.random() * 6 - 3, size, size)
		mote:SetAlpha(0)
		local fall = Group(host, groups, true)
		local move = fall:CreateAnimation("Translation")
		move:SetTarget(mote)
		move:SetOffset(Between(MOTE_DRIFT) * life * s, -(Between(MOTE_FALL) * life + 0.5 * MOTE_GRAVITY * life * life) * s)
		move:SetDuration(life)
		move:SetStartDelay(rest)
		move:SetSmoothing("IN")
		move:SetOrder(1)
		Alpha(fall, mote, 1, 0, life, 1, rest):SetSmoothing("IN")
	end
end

local function DressBehind(host, s, groups)
	local halo = Piece(host, "BACKGROUND", "angelRadianceFx", HALO_COLOR, 0, 0.5)
	Centre(halo, host, s, HALO.x, HALO.y, HALO.size, HALO.size)
	halo:SetAlpha(HALO.low)
	-- The crests leave the roots at the top of the loop and, fainter, halfway through it.
	local swell = Group(host, groups, true)
	Alpha(swell, halo, HALO.high, HALO.low, FLIP.seconds / 2, 1):SetSmoothing("OUT")
	Alpha(swell, halo, HALO.second, HALO.low, FLIP.seconds / 2, 2):SetSmoothing("OUT")

	local burst = Piece(host, "BORDER", "angelRadianceFx", HALO_COLOR, 0, 0.5)
	Centre(burst, host, s, HALO.x, HALO.y, HALO.size, HALO.size)
	burst:SetAlpha(0)
	local arrive = Group(host, groups)
	Alpha(arrive, burst, BURST.peak, 0, BURST.length):SetSmoothing("OUT")
	local grow = arrive:CreateAnimation("Scale")
	grow:SetTarget(burst)
	grow:SetScaleFrom(BURST.from, BURST.from)
	grow:SetScaleTo(BURST.to, BURST.to)
	grow:SetDuration(BURST.length)
	grow:SetSmoothing("OUT")
	grow:SetOrder(1)
end

-- One layer's art and animations on `host`, an aura slot or a preview frame sized to the wing
-- art's cell. s is screen units to a frame.png px. Returns the animation groups to play.
function A.Dress(layer, host, s)
	local groups = {}
	if layer == "front" then
		DressFront(host, s, groups)
	else
		DressBehind(host, s, groups)
	end
	return groups
end
