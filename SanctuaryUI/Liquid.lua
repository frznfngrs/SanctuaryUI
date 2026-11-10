SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.Liquid = ns.Liquid or {}

-- Moving globe liquid, built the way D3 layers it, with the motion D4 adds on top.
--
-- The fill stays a StatusBar so secret health and power values still work. Its texture is
-- invisible and acts as a guide: a clip frame spans from the bar's bottom to the guide's top,
-- and the liquid layers inside it are the full globe size, so the pattern never squashes as
-- the level changes. The surface rides the guide too, cut into thin slices so it can wave.
--
-- Layers, back to front, all under one circle mask:
--   base     D3's liquid tile, slowly turning and drifting, breathing in scale
--   swirl    the same tile, larger and counter-turning, added on top (the churn)
--   wisps    curling filaments in two phases that crossfade, so the pattern evolves rather
--            than slides (the flow-map trick, done with texcoords)
--   streaks  D3's streaks drifting sideways
--   motes    a few soft lights rising through the liquid and fading under the surface
--   rim      inner rim light, brightest at the bottom; pulses with the heartbeat
-- then the fixed sphere shade, then the surface: glow and shimmer strips per slice.
--
-- Motion, all on one OnUpdate driver that runs every frame:
--   * the level follows a critically damped spring: it eases in and out, and a new value
--     mid-glide carries the velocity on instead of restarting
--   * a drop leaves a pale ghost of the lost liquid that holds, then drains (D4)
--   * a jump kicks two damped oscillators: the surface tilts side to side and bobs, and the
--     resting surface keeps a faint travelling ripple
--   * a gain flares the surface for a moment
--   * health below 35% beats: the rim and swirl pulse, faster as health falls
--   * health below half grows restless, all the way down to 10%: the liquid turns faster (to
--     2.6x), sloshes on its own (bigger and more often), the ripple roughens, and a fast churn
--     of deep red fades in over it, darkening the liquid. With health hidden in combat only the churn can follow it (the client
--     feeds the hidden value through a curve into its alpha), and every change of health
--     sloshes it
-- The same pool drives the big globes, the split halves and the small secondary globes;
-- the small ones zoom into the tiles (opts.zoom) so the pattern keeps its size on screen.
--
-- The rendered style (options: Liquid style) replaces base, swirl, churn, wisps and streaks
-- with a looping Blender render stepped as a flipbook: body sheets tinted and added onto solid
-- black, light sheets added on top, each drawn twice and crossfaded so it runs smoothly between
-- frames. A second, boiling loop fades in at low health on the same curve as the churn. Level,
-- mask, shade, rim, motes, surface, bands, ghost and physics are the same in both styles.

local SURFACE_H = 0.16 -- surface strip height, of the globe
local SURFACE_PAD = 0.06 -- room above the line in each slice for the wave, of the globe
local SLICES = 16 -- surface slices across a full globe; adjacent slices differ < 1 px at full tilt

local LEVEL_OMEGA = 11 -- level spring, rad/s: about 0.45 s to settle, no overshoot
local GHOST_HOLD = 0.4 -- seconds the lost liquid hangs before it drains
local GHOST_OMEGA = 6
local GHOST_ALPHA = 0.45 -- at the start of the drain; fades to nothing as it reaches the liquid

-- Surface oscillators: tilt (fraction of globe height per unit of x) and bob (fraction of
-- height). Natural frequency in Hz and damping ratio. A kick's peak swing saturates toward
-- TILT_PEAK / BOB_PEAK, so a huge hit sloshes hard without slamming into a limit.
local TILT_HZ, TILT_ZETA = 1.25, 0.22
local BOB_HZ, BOB_ZETA = 2.1, 0.26
local TILT_PEAK, BOB_PEAK = 0.05, 0.024
local TILT_MAX, BOB_MAX = 0.09, 0.045
local RIPPLE = 0.0055 -- resting ripple amplitude, of the globe height

local FLARE_DECAY = 3.2
local PULSE_BELOW = 0.35
-- Low health restlessness: from URGE_FROM of health down to URGE_FULL.
local URGE_FROM, URGE_FULL = 0.5, 0.1
local URGE_SPIN = 1.6 -- extra turning speed at full urgency (2.6x)
local URGE_RIPPLE = 2.5 -- extra resting ripple at full urgency
-- Fury (GlobeAura.lua DRAW.fury sets pool.fury and pool.furyAt each frame it shows): the
-- liquid whipped up, however full the globe is.
local FURY_SPIN = 3.4 -- extra turning speed at full fury
local FURY_HOLD, FURY_DECAY = 0.25, 3 -- seconds unrefreshed before it lets go, and how fast
local CHURN = { span = 1.25, spin = -0.32, du = 0.07, dv = -0.035, alpha = 0.5 } -- the fast churn layer

-- Texcoord motion per layer. span: texture widths across the globe. spin: rad/s. du, dv: drift
-- in texture widths per second. breathe: relative scale swing and its rate. Opposing spins
-- between base and swirl read as the slow churn of the D3 globe.
local LAYERS = {
	base = { span = 1.0, spin = 0.045, du = 0.018, dv = 0.006, breathe = 0.035, breatheRate = 0.31 },
	swirl = { span = 1.5, spin = -0.085, du = -0.03, dv = 0.012, breathe = 0.05, breatheRate = 0.23, alpha = 0.28 },
	streaks = { span = 1.0, spin = 0, du = 0.085, dv = 0, sway = 0.018, swayRate = 0.6, alpha = 0.26 },
}
local WISPS = { span = 1.15, period = 6.5, travel = 0.16, spin = 0.05, alpha = 0.24 }
local SHIMMER_DU, GLOW_DU = 0.07, -0.025
local MOTE = { size = 0.035, rise = 0.075, wobble = 0.018, alpha = 0.55 }

-- The rendered style. Sheets from tools/build_hud_art.py rendered_liquid: cols x rows cells,
-- the loop reads left to right from the top. FLIP_EDGE keeps bilinear off the next cell.
local FLIP = {
	calm = { body = "liquidCalmBody", light = "liquidCalmLight", frames = 48, cols = 8, rows = 8, seconds = 5 },
	agitated = { body = "liquidAgitatedBody", light = "liquidAgitatedLight", frames = 32, cols = 8, rows = 4, seconds = 2.8 },
}
local FLIP_EDGE = 0.5 / 256 -- of a cell
local FLIP_MIN_ZOOM = 0.7 -- small globes crop into a cell no further than this: more would magnify the motion
local FLIP_LIGHT, FLIP_HOT = 0.7, 0.55 -- the light layer's strength and how far its colour heats
local FLIP_AGIT_TINT = { 1, 0.7, 0.6 } -- of the liquid colour: the boil stays red, a little deeper
local FLIP_AGIT_LIGHT, FLIP_AGIT_HOT = 0.55, 0.4

local pools = {}
local byBar = {}

function ns.Liquid.Supported()
	if ns.Liquid.supported == nil then
		local probe = UIParent:CreateTexture()
		local missing = {}
		if not UIParent.CreateMaskTexture then missing[#missing + 1] = "CreateMaskTexture" end
		if not probe.AddMaskTexture then missing[#missing + 1] = "AddMaskTexture" end
		if not UIParent.SetClipsChildren then missing[#missing + 1] = "SetClipsChildren" end
		if not ns.Art.Path("liquidTile") then missing[#missing + 1] = "liquid-tile.png" end
		if not ns.Art.Path("globeMask") then missing[#missing + 1] = "globe-mask.png" end
		probe:Hide()
		ns.Liquid.missing = missing
		ns.Liquid.supported = #missing == 0
	end
	return ns.Liquid.supported
end

-- One line for /sanctuary check: is the liquid animating, and if not, why not.
function ns.Liquid.Status()
	if not ns.Liquid.Supported() then
		return "liquid static, client lacks " .. table.concat(ns.Liquid.missing or {}, ", ")
	end
	local visible = 0
	for i = 1, #pools do
		if pools[i].frame:IsVisible() then visible = visible + 1 end
	end
	local base = pools[1] and pools[1].base
	local u = base and select(1, base:GetTexCoord()) or 0
	return ("liquid animated (%s): %d pools, %d visible, driver %s, %d ticks, base u %.2f"):format(
		pools[1] and pools[1].flipOn and "rendered" or "classic",
		#pools, visible, ns.Liquid.driver and "on" or "off", ns.Liquid.ticks or 0, u)
end

local function Secret(...)
	if not issecretvalue then return false end
	for i = 1, select("#", ...) do
		if issecretvalue((select(i, ...))) then return true end
	end
	return false
end

local function Clamp(x, lo, hi)
	if x < lo then return lo elseif x > hi then return hi end
	return x
end

-- Stable pseudo-random 0..1 from a number, for reseeding a layer while it is invisible.
local function Hash(n)
	local x = math.sin(n * 12.9898 + 78.233) * 43758.5453
	return x - math.floor(x)
end

-- Moving textures render between pixels instead of stepping from one to the next.
local function Smooth(tex)
	if tex.SetSnapToPixelGrid then
		tex:SetSnapToPixelGrid(false)
		tex:SetTexelSnappingBias(0)
	end
end

local function Mask(frame, globe, slot)
	local mask = frame:CreateMaskTexture()
	mask:SetAllPoints(globe)
	mask:SetTexture(ns.Art.Path(slot or "globeMask"), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	return mask
end

local function Layer(frame, globe, mask, slot, sublevel, blend)
	if not ns.Art.Path(slot) then return nil end
	local tex = frame:CreateTexture(nil, "ARTWORK", nil, sublevel)
	tex:SetAllPoints(globe)
	tex:SetTexture(ns.Art.Path(slot), "REPEAT", "REPEAT")
	if blend then
		tex:SetBlendMode(blend)
	end
	tex:AddMaskTexture(mask)
	Smooth(tex)
	return tex
end

-- Map the texture onto the globe turned by angle about (cu, cv), half a span each side.
-- REPEAT wraps the coordinates; the +1.5 keeps every corner positive.
local function Affine(tex, cu, cv, half, angle)
	cu, cv = cu % 1 + 1.5, cv % 1 + 1.5
	local c, s = math.cos(angle) * half, math.sin(angle) * half
	tex:SetTexCoord(cu - c + s, cv - s - c, cu - c - s, cv - s + c, cu + c + s, cv + s - c, cu + c - s, cv + s + c)
end

-- Highlights that keep their hue: the strong channel climbs toward full and the brighter ones
-- lean to ember orange, as D3's health globe glints, instead of mixing toward white (which
-- turns red pink).
local function Hotter(r, g, b, k)
	return math.min(1, r + (1 - r) * k), math.min(1, g * (1 + 0.6 * k) + 0.3 * k), math.min(1, b * (1 + 0.4 * k) + 0.05 * k)
end

local function Lighter(r, g, b, k)
	return math.min(1, r * (1 - k) + k), math.min(1, g * (1 - k) + k), math.min(1, b * (1 - k) + k)
end

-- A pool is a plain table holding its frames. Frames keep their own widget metatable.
local Pool = {}
Pool.__index = Pool

-- The health globe's highlights keep their red; the others lighten toward white as before.
function Pool:Light(r, g, b, k)
	if self.pulse then return Hotter(r, g, b, k) end
	return Lighter(r, g, b, k)
end

function Pool:SetColor(r, g, b)
	self.color = { r, g, b }
	self.base:SetVertexColor(r, g, b, 1)
	self.swirl:SetVertexColor(r, g, b, LAYERS.swirl.alpha)
	-- The churn darkens: deep red laid over the liquid, not light added to it.
	if self.churn then self.churn:SetVertexColor(r * 0.3, g * 0.2, b * 0.2) end
	local sr, sg, sb = self:Light(r, g, b, 0.5)
	if self.streaks then self.streaks:SetVertexColor(sr, sg, sb, LAYERS.streaks.alpha) end
	local wr, wg, wb = self:Light(r, g, b, 0.35)
	for _, w in ipairs(self.wisps) do
		w:SetVertexColor(wr, wg, wb, 0)
	end
	local hr, hg, hb = self:Light(r, g, b, 0.45)
	self.surfaceColor = { hr, hg, hb }
	for _, slice in ipairs(self.slices) do
		slice.glow:SetVertexColor(hr, hg, hb, 0.9)
		if slice.shimmer then slice.shimmer:SetVertexColor(hr, hg, hb, 0.55) end
	end
	if self.rim then self.rim:SetVertexColor(self:Light(r, g, b, 0.3)) end
	local mr, mg, mb = self:Light(r, g, b, 0.6)
	for _, mote in ipairs(self.motes) do
		mote.tex:SetVertexColor(mr, mg, mb, 0)
	end
	if self.ghostTex then
		local gr, gg, gb = self:Light(r, g, b, 0.3)
		self.ghostTex:SetVertexColor(gr, gg, gb, GHOST_ALPHA)
		self.ghostColor = { gr, gg, gb }
	end
	self:BandColors()
end

local function Fill(self)
	local bar = self.bar
	local minValue, maxValue = bar:GetMinMaxValues()
	local value = bar:GetValue()
	if Secret(value, minValue, maxValue) then return nil end
	local span = (maxValue or 1) - (minValue or 0)
	return span > 0 and Clamp(((value or 0) - (minValue or 0)) / span, 0, 1) or 0
end

-- Hide the surface when the globe is empty or full, unless it is still sloshing. With a secret
-- value the level is unknown, so the surface stays up; the circle mask still clips it.
function Pool:UpdateSurface()
	local fill = Fill(self)
	self.fill = fill
	local show = fill == nil or (fill > 0.015 and fill < 0.985) or (fill > 0 and fill < 1 and (self.energy or 0) > 0.002)
	if show ~= self.surfaceShown then
		self.surfaceShown = show
		self.surface:SetShown(show)
	end
end

function Pool:Size()
	local h = self.globe:GetHeight()
	local w = self.bar:GetWidth()
	if not h or h <= 0 or not w or w <= 0 then return end
	self.height, self.width = h, w
	if self.ghostCap then self.ghostCap:SetHeight(h * SURFACE_H * 0.6) end
	local n = #self.slices
	local sw = w / n
	for i, slice in ipairs(self.slices) do
		slice.glow:SetSize(sw, h * (SURFACE_H + 2 * SURFACE_PAD)) -- unsnapped, neighbours meet exactly
		slice.x = (i - 1) * sw
		slice.w = sw
	end
	for _, mote in ipairs(self.motes) do
		local s = h * MOTE.size * mote.scale
		mote.tex:SetSize(s, s)
	end
	self:SizeBands()
	self:PlaceSurface(true)
end

-- The surface's height at px across the globe. (Not a closure: this runs per pool, per frame.)
local function SurfaceWave(px, gx, h, tilt, bob, ripple, t, phase)
	local x = (gx + px) / h * 2 - 1
	return (tilt * x + bob + ripple * (math.sin(x * 7.2 + t * 1.9 + phase * 9) + 0.6 * math.sin(-x * 11.5 + t * 2.7))) * h
end

-- Surface slices: top edge on the level, plus the wave. Called every frame while visible.
function Pool:PlaceSurface(force, t)
	local h = self.height
	if not h or (self.surfaceShown == false and not force) then return end
	t = t or self.clock or 0
	-- Slice centres across the globe, -1..1, for the tilt; a half bar sits to one side.
	local barLeft, globeLeft = self.bar:GetLeft(), self.globe:GetLeft()
	local gx = barLeft and globeLeft and (barLeft - globeLeft) or 0
	local tilt, bob = self.tilt or 0, self.bob or 0
	local ripple = RIPPLE * (ns.DB().liquidAnimate and 1 or 0) * (1 + URGE_RIPPLE * (self.urge or 0))
	local u0 = (t * SHIMMER_DU * self.zoom + self.phase) % 1
	local g0 = (t * GLOW_DU * self.zoom + self.phase * 3) % 1
	local n = #self.slices
	local guide = self.guide
	local phase = self.phase
	-- The wave is sampled at slice edges. Each slice is a flat quad padded above the line;
	-- its texcoords are sheared so the line runs from the left edge's height to the right
	-- edge's, so neighbours join into one unbroken surface. v outside 0..1 is transparent.
	local sh = SURFACE_H * h
	local pad = SURFACE_PAD * h
	local q = sh + 2 * pad
	local yl = SurfaceWave(0, gx, h, tilt, bob, ripple, t, phase)
	for i, slice in ipairs(self.slices) do
		local yr = SurfaceWave(slice.x + slice.w, gx, h, tilt, bob, ripple, t, phase)
		local mid = (yl + yr) * 0.5
		slice.glow:SetPoint("TOPLEFT", guide, "TOPLEFT", slice.x, 1 + mid + pad)
		-- Depth of the line below the quad top at each edge, in texture heights.
		local dl, dr = (pad + mid - yl) / sh, (pad + mid - yr) / sh
		local bot = q / sh
		local a, b = (i - 1) / n * self.zoom, i / n * self.zoom
		slice.glow:SetTexCoord(g0 + a, -dl, g0 + a, bot - dl, g0 + b, -dr, g0 + b, bot - dr)
		if slice.shimmer then
			slice.shimmer:SetTexCoord(u0 + a, -dl, u0 + a, bot - dl, u0 + b, -dr, u0 + b, bot - dr)
		end
		yl = yr
	end
	if force then self:UpdateSurface() end
end

-- A different unit now drives this pool: no glide or damage ghost from the last one's level.
function Pool:Forget()
	self.target, self.level, self.vel, self.ghost, self.started = nil, nil, 0, nil, nil
	if self.ghostBar then self.ghostBar:Hide() end
end

-- New value. Secret values go straight to the bar (with the client's own easing if it has
-- one); anything else springs there.
function Pool:SetTarget(value, maxValue)
	local bar = self.bar
	if Secret(value, maxValue) then
		-- Hidden: no level to spring to or size to read, but a change of health still sloshes.
		if self.pulse and self.hidden then self:Kick(-0.035) end
		self.hidden = true
		self.target, self.level, self.vel, self.ghost = nil, nil, 0, nil
		if self.ghostBar then self.ghostBar:Hide() end
		if maxValue ~= nil then pcall(bar.SetMinMaxValues, bar, 0, maxValue) end
		local ease = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
		local shown = ns.Or(value, 0)
		if not (ease and pcall(bar.SetValue, bar, shown, ease)) and not pcall(bar.SetValue, bar, shown) then
			bar:SetValue(0)
		end
		return
	end
	self.hidden = nil
	value, maxValue = value or 0, maxValue or 1
	local _, oldMax = bar:GetMinMaxValues()
	if Secret(oldMax) or oldMax ~= maxValue then
		bar:SetMinMaxValues(0, maxValue)
		if self.ghostBar then self.ghostBar:SetMinMaxValues(0, maxValue) end
	end
	self.max = maxValue
	if not self.level or not self.started then
		-- First value (or coming from a secret one): no glide from zero.
		self.level, self.vel, self.started = value, 0, true
		self.target = nil
		bar:SetValue(value)
		return
	end
	if value == (self.target or self.level) then return end
	local from = self.target or self.level
	if maxValue > 0 then
		local jump = (value - from) / maxValue
		self:Kick(jump)
		if jump < 0 and self.ghostBar then
			-- Damage: the ghost starts where the liquid is now and waits.
			self.ghost = math.max(self.ghost or 0, self.level)
			self.ghostVel = 0
			self.ghostSpan = self.ghost - value
			self.ghostHold = GHOST_HOLD
			self.ghostBar:SetValue(self.ghost)
			self.ghostBar:Show()
		elseif jump > 0.04 then
			self.flare = math.min(1, (self.flare or 0) + jump * 3)
		end
	end
	self.target = value
end

-- A level change disturbs the surface. Tilt alternates direction so repeated hits rock it.
function Pool:Kick(jump)
	local size = math.abs(jump)
	if size < 0.015 then return end
	local swing = 1 - math.exp(-size * 6)
	self.kicks = (self.kicks or 0) + 1
	local dir = (self.kicks % 2 == 0) and 1 or -1
	dir = dir * (0.75 + 0.25 * Hash(self.kicks + self.phase * 100))
	-- An undamped oscillator kicked with velocity v peaks at v / omega.
	self.tiltVel = (self.tiltVel or 0) + dir * TILT_PEAK * swing * 2 * math.pi * TILT_HZ
	self.bobVel = (self.bobVel or 0) + (jump < 0 and -1 or 1) * BOB_PEAK * swing * 2 * math.pi * BOB_HZ
end

-- Exact step of a critically damped spring toward target: stable at any frame time.
local function Spring(x, v, target, omega, dt)
	local x0 = x - target
	local e = math.exp(-omega * dt)
	local k = v + omega * x0
	return target + (x0 + k * dt) * e, (v - omega * k * dt) * e
end

-- Damped oscillator, semi-implicit Euler in small steps.
local function Oscillate(x, v, hz, zeta, dt)
	local w = 2 * math.pi * hz
	local steps = math.max(1, math.ceil(dt / (1 / 240)))
	local h = dt / steps
	for _ = 1, steps do
		v = v + (-w * w * x - 2 * zeta * w * v) * h
		x = x + v * h
	end
	return x, v
end

-- How restless low health makes the liquid, 0..1, eased so it never jumps. Needs the fill
-- (readable health); hidden, it eases back to 0 and the churn layer takes over.
function Pool:Urgency(dt)
	local target = 0
	local fill = self.fill
	if self.pulse and ns.DB().lowHealthAgitate ~= false and fill and fill > 0 then
		local x = Clamp((URGE_FROM - fill) / (URGE_FROM - URGE_FULL), 0, 1)
		target = x * x * (3 - 2 * x)
	end
	self.urge = (self.urge or 0) + (target - (self.urge or 0)) * math.min(1, dt * 1.5)
	if self.urge < 0.001 and target == 0 then self.urge = 0 end
	return self.urge
end

function Pool:Physics(dt)
	local bar = self.bar
	-- Restless at low health: the liquid sloshes on its own, harder and more often the lower.
	local urge = math.max(self.urge or 0, self.fury or 0)
	if urge > 0.05 and ns.DB().liquidAnimate then
		self.restless = (self.restless or 0) - dt
		if self.restless <= 0 then
			self.slosh = (self.slosh or 0) + 1
			local size = 0.02 + 0.07 * urge * (0.6 + 0.4 * Hash(self.slosh + self.phase * 50))
			self:Kick(Hash(self.slosh * 1.7) < 0.5 and -size or size)
			self.restless = (1.5 - 1.05 * urge) * (0.7 + 0.6 * Hash(self.slosh * 3.1))
		end
	else
		self.restless = nil
	end
	if self.target and self.level then
		local level, vel = Spring(self.level, self.vel or 0, self.target, LEVEL_OMEGA, dt)
		local max = self.max or 1
		if math.abs(level - self.target) <= max * 0.0005 and math.abs(vel) <= max * 0.005 then
			level, vel, self.target = self.target, 0, nil
		end
		self.level, self.vel = level, vel
		bar:SetValue(level)
	end

	if self.ghost then
		if self.ghostHold > 0 then
			self.ghostHold = self.ghostHold - dt
		else
			self.ghost, self.ghostVel = Spring(self.ghost, self.ghostVel or 0, self.level or 0, GHOST_OMEGA, dt)
		end
		local max = self.max or 1
		if not self.level or self.ghost - self.level <= max * 0.002 then
			self.ghost = nil
			self.ghostBar:Hide()
		else
			self.ghostBar:SetValue(self.ghost)
			-- Fade with the drain: full while it hangs, gone as it meets the liquid.
			local left = (self.ghost - self.level) / math.max(1e-9, self.ghostSpan or (self.ghost - self.level))
			local c = self.ghostColor
			if c then
				local a = GHOST_ALPHA * Clamp(left, 0, 1) ^ 0.7
				self.ghostTex:SetVertexColor(c[1], c[2], c[3], a)
				self.ghostCap:SetVertexColor(c[1], c[2], c[3], a * 0.8)
			end
		end
	end

	if self.tiltVel or self.bobVel then
		self.tilt, self.tiltVel = Oscillate(self.tilt or 0, self.tiltVel or 0, TILT_HZ, TILT_ZETA, dt)
		self.bob, self.bobVel = Oscillate(self.bob or 0, self.bobVel or 0, BOB_HZ, BOB_ZETA, dt)
		self.tilt = Clamp(self.tilt, -TILT_MAX, TILT_MAX)
		self.bob = Clamp(self.bob, -BOB_MAX, BOB_MAX)
		self.energy = math.abs(self.tilt) + math.abs(self.bob) + (math.abs(self.tiltVel) + math.abs(self.bobVel)) * 0.05
		if self.energy < 0.0002 then
			self.tilt, self.bob, self.tiltVel, self.bobVel, self.energy = 0, 0, nil, nil, 0
			self:UpdateSurface()
		end
	end

	if self.bands then self:BandPhysics(dt) end

	if self.flare then
		self.flare = self.flare * math.exp(-dt * FLARE_DECAY)
		if self.flare < 0.01 then self.flare = nil end
	end
end

-- Low health heartbeat: two beats (lub-dub) per cycle; quicker as the globe empties.
function Pool:Heartbeat(realTime)
	if not self.pulse or not ns.DB().lowHealthPulse then return 0 end
	local fill = self.fill
	if not fill or fill >= PULSE_BELOW or fill <= 0 then
		self.beatPhase = nil
		return 0
	end
	local strength = (PULSE_BELOW - fill) / PULSE_BELOW
	local bpm = 66 + 54 * strength
	local last = self.beatClock or realTime
	self.beatPhase = ((self.beatPhase or 0) + (realTime - last) * bpm / 60) % 1
	self.beatClock = realTime
	local p = self.beatPhase
	local beat = math.exp(-((p - 0.06) / 0.05) ^ 2) + 0.55 * math.exp(-((p - 0.24) / 0.06) ^ 2)
	return (0.35 + 0.65 * strength) * beat
end

function Pool:Animate(t, realTime, dt)
	local zoom = self.zoom
	local phase = self.phase

	local flip = self.flipOn
	local m = LAYERS.base
	local breathe = 1 + m.breathe * math.sin(t * m.breatheRate + phase * 7)
	if not flip then
		Affine(self.base, phase + t * m.du * zoom, phase * 0.7 + t * m.dv * zoom, m.span * zoom * 0.5 * breathe, t * m.spin + phase * 6)
	end
	if self.bands then
		self:BandAnimate(realTime, phase + t * m.du * zoom, phase * 0.7 + t * m.dv * zoom, m.span * zoom * 0.5 * breathe, t * m.spin + phase * 6)
	end
	if self.ghostTex and self.ghost then
		Affine(self.ghostTex, phase + t * m.du * zoom, phase * 0.7 + t * m.dv * zoom, m.span * zoom * 0.5 * breathe, t * m.spin + phase * 6)
	end
	if not flip then
		m = LAYERS.swirl
		breathe = 1 + m.breathe * math.sin(t * m.breatheRate + phase * 3)
		Affine(self.swirl, phase + 0.37 + t * m.du * zoom, 0.5 + t * m.dv * zoom, m.span * zoom * 0.5 * breathe, t * m.spin + phase * 2)
		if self.churn then self:Churn(t) end
		if self.streaks then
			m = LAYERS.streaks
			local u = phase + 0.71 + t * m.du * zoom
			local v = phase + math.sin(t * m.swayRate + phase * 40) * m.sway
			Affine(self.streaks, u, v, m.span * zoom * 0.5, 0)
		end

		-- Wisps: two copies half a cycle apart. Each fades in, drifts and turns, fades out, and is
		-- reseeded somewhere new while invisible, so the pattern never visibly repeats or slides.
		local wr, wg, wb = self:Light(self.color[1], self.color[2], self.color[3], 0.35)
		for k, w in ipairs(self.wisps) do
			local cyc = t / WISPS.period + phase + (k - 1) * 0.5
			local n = math.floor(cyc)
			local p = cyc - n
			local seed = n * 2 + k + phase * 13
			local dir = Hash(seed + 0.5) * math.pi * 2
			local travel = (p - 0.5) * WISPS.travel * zoom
			local a = math.sin(p * math.pi)
			w:SetVertexColor(wr, wg, wb, a * a * WISPS.alpha)
			Affine(w, Hash(seed) + math.cos(dir) * travel, Hash(seed + 1.7) + math.sin(dir) * travel,
				WISPS.span * zoom * 0.5, Hash(seed + 3.1) * 6.283 + (p - 0.5) * WISPS.spin * WISPS.period)
		end
	end

	-- Heartbeat and flare light the rim and swirl.
	local beat = self:Heartbeat(realTime)
	local flare = self.flare or 0
	if self.rim then
		local r, g, b = self:Light(self.color[1], self.color[2], self.color[3], 0.3)
		self.rim:SetVertexColor(r, g, b, Clamp(0.42 + 0.55 * beat + 0.35 * flare, 0, 1))
	end
	if flip then
		self:Flipbook(t, dt, beat, flare)
	else
		self.swirl:SetVertexColor(self.color[1], self.color[2], self.color[3], Clamp(LAYERS.swirl.alpha + 0.3 * beat, 0, 1))
	end
	if self.surfaceShown ~= false then
		local c = self.surfaceColor
		local glow = Clamp(0.85 + 0.15 * beat + 0.4 * flare, 0, 1)
		local cr, cg, cb = self:Light(c[1], c[2], c[3], 0.5 * flare)
		for _, slice in ipairs(self.slices) do
			slice.glow:SetVertexColor(cr, cg, cb, glow)
		end
	end

	self:Motes(t, dt)
	self.clock = t
	self:PlaceSurface(false, t)
end

-- The churn: the liquid tile again in deep red, laid over the liquid (not added to it) and
-- turning fast against the swirl, faded in as health falls: low health roils and darkens.
-- With readable health its alpha is the urgency; with hidden health the client puts the
-- health fraction through a curve and straight into the alpha, so we never read it.
local churnCurves = {}
local function ChurnCurve(strength)
	strength = strength or 1
	if churnCurves[strength] == nil then
		churnCurves[strength] = false
		if C_CurveUtil and C_CurveUtil.CreateCurve then
			local ok, curve = pcall(C_CurveUtil.CreateCurve)
			if ok and curve then
				-- Health fraction -> alpha: none above half, `strength` at 10% and below.
				for _, p in ipairs({ { 0, 1 }, { URGE_FULL, 1 }, { 0.3, 0.5 }, { URGE_FROM, 0 }, { 1, 0 } }) do
					pcall(curve.AddPoint, curve, p[1], p[2] * strength)
				end
				churnCurves[strength] = curve
			end
		end
	end
	return churnCurves[strength] or nil
end

function Pool:Churn(t)
	local churn = self.churn
	local m = CHURN
	Affine(churn, self.phase + 0.53 + t * m.du * self.zoom, 0.21 + t * m.dv * self.zoom, m.span * self.zoom * 0.5, t * m.spin + self.phase * 4)
	if ns.DB().lowHealthAgitate == false then
		churn:SetAlpha(0)
	elseif self.fill then
		churn:SetAlpha(m.alpha * (self.urge or 0))
	else
		-- The curve carries the churn's strength: a vertex alpha here would overwrite the
		-- hidden value, since a texture's vertex alpha and SetAlpha are one value in this client.
		local curve = UnitHealthPercent and ChurnCurve(m.alpha)
		local ok, alpha = false, nil
		if curve then ok, alpha = pcall(UnitHealthPercent, "player", true, curve) end
		if not (ok and alpha ~= nil and pcall(churn.SetAlpha, churn, alpha)) then churn:SetAlpha(0) end
	end
end

-- Whether the rendered style's art loaded. The sheets are only ever looked at from here.
local function FlipReady()
	if ns.Liquid.flipReady == nil then
		local ready = true
		for _, spec in pairs(FLIP) do
			if not (ns.Art.Require(spec.body) and ns.Art.Require(spec.light)) then ready = false end
		end
		ns.Liquid.flipReady = ready
	end
	return ns.Liquid.flipReady
end

local function FlipTexture(frame, globe, mask, slot, sublevel, blend, made)
	local tex = frame:CreateTexture(nil, "ARTWORK", nil, sublevel)
	made[#made + 1] = tex
	if not tex:SetTexture(ns.Art.Path(slot), "CLAMP", "CLAMP") then return nil end
	tex:SetAllPoints(globe)
	if blend then tex:SetBlendMode(blend) end
	tex:AddMaskTexture(mask)
	Smooth(tex)
	return tex
end

-- The solid black the bodies add onto. The bodies are ADD so that their weights always sum to 1;
-- this is what makes them cover whatever is behind, at any alpha. Two "over" layers would not:
-- under a parent alpha (the party's range fade) their combined coverage rises with the blend
-- and drops back at every frame step, which flashes about ten times a second.
local function FlipBacking(pool, sublevel, made)
	local tex = pool.frame:CreateTexture(nil, "ARTWORK", nil, sublevel)
	made[#made + 1] = tex
	tex:SetColorTexture(0, 0, 0, 1)
	tex:SetAllPoints(pool.globe)
	tex:AddMaskTexture(pool.mask)
	return tex
end

-- One loop on consecutive sublevels from `sub`: the backing, two bodies, two lights.
local function FlipSet(pool, spec, sub, made)
	local function Tex(slot, level, blend)
		return FlipTexture(pool.frame, pool.globe, pool.mask, slot, level, blend, made)
	end
	local set = {
		spec = spec,
		backing = FlipBacking(pool, sub, made),
		bodyA = Tex(spec.body, sub + 1, "ADD"), bodyB = Tex(spec.body, sub + 1, "ADD"),
		lightA = Tex(spec.light, sub + 2, "ADD"), lightB = Tex(spec.light, sub + 2, "ADD"),
	}
	if set.bodyA and set.bodyB and set.lightA and set.lightB then return set end
end

-- Builds the textures the first time this pool needs them; false means stay classic.
function Pool:BuildFlip()
	if self.flip then return true end
	if self.flipFailed or not FlipReady() then return false end
	local made = {}
	local ok, calm, agit = pcall(function()
		-- Under the classic layers' sublevels; the motes and rim stay above both styles.
		return FlipSet(self, FLIP.calm, -8, made), self.churn and FlipSet(self, FLIP.agitated, -5, made) or nil
	end)
	if not ok or not calm or (self.churn and not agit) then
		self.flipFailed = true
		for _, tex in ipairs(made) do tex:Hide() end
		if ns.Log then ns.Log("liquid: rendered style failed to load, using classic") end
		return false
	end
	self.flip = { calm = calm, agit = agit, made = made }
	return true
end

-- Switch this pool to the chosen style.
function Pool:ApplyStyle()
	local on = ns.DB().liquidStyle == "rendered" and self:BuildFlip() or false
	if on == (self.flipOn or false) then return end
	self.flipOn = on
	for _, key in ipairs({ "base", "swirl", "churn", "streaks" }) do
		if self[key] then self[key]:SetShown(not on) end
	end
	for _, w in ipairs(self.wisps) do w:SetShown(not on) end
	if self.flip then
		for _, tex in ipairs(self.flip.made) do tex:SetShown(on) end
		self.flip.calm.i = nil
		if self.flip.agit then self.flip.agit.i = nil end
	end
end

local function FlipHot(r, g, b, k)
	if r > b then return Hotter(r, g, b, k) end
	return Lighter(r, g, b, k)
end

local function FlipCell(tex, spec, i, inset)
	local row = math.floor(i / spec.cols)
	local col = i - row * spec.cols
	tex:SetTexCoord((col + inset) / spec.cols, (col + 1 - inset) / spec.cols, (row + inset) / spec.rows, (row + 1 - inset) / spec.rows)
end

-- Point a loop's textures at its current pair of frames; returns how far between them it is.
local function FlipStep(set, clock, inset)
	local spec = set.spec
	local pos = (clock / spec.seconds) % 1 * spec.frames
	local i = math.floor(pos)
	if i ~= set.i then
		set.i = i
		local j = (i + 1) % spec.frames
		FlipCell(set.bodyA, spec, i, inset)
		FlipCell(set.bodyB, spec, j, inset)
		FlipCell(set.lightA, spec, i, inset)
		FlipCell(set.lightB, spec, j, inset)
	end
	return pos - i
end

-- How much of the low-health loop shows: readable urgency when health can be read, else the
-- client's curve applied to the hidden health. May be a secret; never compare it.
function Pool:UrgeAlpha()
	if ns.DB().lowHealthAgitate == false then return 0 end
	if self.fill then return self.urge or 0 end
	local curve = UnitHealthPercent and ChurnCurve()
	if curve then
		local ok, alpha = pcall(UnitHealthPercent, "player", true, curve)
		if ok and alpha ~= nil then return alpha end
	end
	return 0
end

-- The calm loop's textures crossfade with vertex alpha; a small pool zooms into each cell, up
-- to FLIP_MIN_ZOOM, so the pattern keeps some size on screen. Readable or hidden, the boil
-- fades on the region alpha alone, the way the churn does, so the same maths runs in and out
-- of combat.
function Pool:Flipbook(t, dt, beat, flare)
	local flip, c = self.flip, self.color
	local r, g, b = c[1], c[2], c[3]
	local inset = math.max(FLIP_EDGE, (1 - math.max(self.zoom, FLIP_MIN_ZOOM)) * 0.5)
	local calm = flip.calm
	local f = FlipStep(calm, t + self.phase * calm.spec.seconds, inset)
	calm.bodyA:SetVertexColor(r, g, b, 1 - f)
	calm.bodyB:SetVertexColor(r, g, b, f)
	local hr, hg, hb = FlipHot(r, g, b, FLIP_HOT)
	local light = Clamp(FLIP_LIGHT + 0.3 * beat + 0.35 * flare, 0, 1)
	calm.lightA:SetVertexColor(hr, hg, hb, (1 - f) * light)
	calm.lightB:SetVertexColor(hr, hg, hb, f * light)

	local agit = flip.agit
	if not agit then return end
	local db = ns.DB()
	-- On its own clock: the boil is already fast, so low health must not speed it up as well.
	self.agitClock = (self.agitClock or 0) + (db.liquidAnimate and dt * (tonumber(db.liquidSpeed) or 1) or 0)
	f = FlipStep(agit, self.agitClock + self.phase * agit.spec.seconds, inset)
	-- The crossfade weights go in the colour, never in the alpha: the alpha is the boil's own
	-- strength, set last, and the game can treat a texture's vertex alpha and SetAlpha as one
	-- value. Passing weights as alpha would overwrite the strength and show the boil at full
	-- health. These layers are ADD, so scaling their colour is the same as scaling their alpha.
	local tr, tg, tb = r * FLIP_AGIT_TINT[1], g * FLIP_AGIT_TINT[2], b * FLIP_AGIT_TINT[3]
	agit.bodyA:SetVertexColor(tr * (1 - f), tg * (1 - f), tb * (1 - f))
	agit.bodyB:SetVertexColor(tr * f, tg * f, tb * f)
	local ar, ag, ab = FlipHot(r, g, b, FLIP_AGIT_HOT)
	ar, ag, ab = ar * FLIP_AGIT_LIGHT, ag * FLIP_AGIT_LIGHT, ab * FLIP_AGIT_LIGHT
	agit.lightA:SetVertexColor(ar * (1 - f), ag * (1 - f), ab * (1 - f))
	agit.lightB:SetVertexColor(ar * f, ag * f, ab * f)
	local alpha = self:UrgeAlpha()
	agit.all = agit.all or { agit.backing, agit.bodyA, agit.bodyB, agit.lightA, agit.lightB }
	for _, tex in ipairs(agit.all) do
		if not pcall(tex.SetAlpha, tex, alpha) then tex:SetAlpha(0) end
	end
end

-- Motes rise from the bottom of the liquid, sway, and fade before they reach the surface.
function Pool:Motes(t, dt)
	local n = #self.motes
	if n == 0 then return end
	local h = self.height
	if not h then return end
	local animate = ns.DB().liquidAnimate
	local top = self.fill or 1
	for i, mote in ipairs(self.motes) do
		if animate then
			mote.y = mote.y + dt * MOTE.rise * mote.speed
		end
		if mote.y > top - 0.02 or mote.y > 0.98 then
			mote.seed = mote.seed + n
			mote.y = 0.02 + 0.1 * Hash(mote.seed)
			mote.speed = 0.6 + 0.8 * Hash(mote.seed + 0.3)
			mote.x = (Hash(mote.seed + 0.6) * 2 - 1)
			mote.born = mote.y
		end
		local cy = mote.y * 2 - 1
		local chord = math.sqrt(math.max(0, 1 - cy * cy)) * 0.82
		local x = mote.x * chord + math.sin(t * 1.3 + mote.seed * 2.1) * MOTE.wobble * 2
		local fadeIn = Clamp((mote.y - mote.born) / 0.08, 0, 1)
		local fadeOut = Clamp((top - mote.y) / 0.12, 0, 1)
		local twinkle = 0.75 + 0.25 * math.sin(t * 3.1 + mote.seed * 5.3)
		local tex = mote.tex
		tex:SetPoint("CENTER", self.globe, "BOTTOMLEFT", (x + 1) * 0.5 * h, mote.y * h)
		local c = self.color
		local r, g, b = self:Light(c[1], c[2], c[3], 0.6)
		tex:SetVertexColor(r, g, b, MOTE.alpha * fadeIn * fadeOut * twinkle * mote.bright)
	end
end

-- bar: the fill StatusBar (whole globe, half, or a small pip). globe: the circle it fills.
-- opts.zoom < 1 zooms into the tiles for small globes; opts.slices, opts.motes size the
-- surface and the motes; opts.ghost leaves a damage ghost; opts.pulse beats at low value.
function ns.Liquid.Attach(globe, bar, opts)
	if not ns.Liquid.Supported() then return nil end
	opts = opts or {}
	bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	bar:SetStatusBarColor(1, 1, 1, 0)
	local guide = bar:GetStatusBarTexture()

	local pool = setmetatable({
		globe = globe, bar = bar, guide = guide, zoom = opts.zoom or 1, pulse = opts.pulse,
		phase = (#pools * 0.29) % 1, color = { 1, 1, 1 }, wisps = {}, slices = {}, motes = {},
	}, Pool)

	-- Damage ghost: its own invisible bar and clip, under the liquid, so it only shows between
	-- the old level and the new one.
	if opts.ghost then
		local ghostBar = CreateFrame("StatusBar", nil, bar)
		ghostBar:SetAllPoints(bar)
		ghostBar:SetOrientation("VERTICAL")
		ghostBar:SetMinMaxValues(0, 1)
		ghostBar:SetValue(0)
		ghostBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
		ghostBar:SetStatusBarColor(1, 1, 1, 0)
		local ghostClip = CreateFrame("Frame", nil, ghostBar)
		ghostClip:SetClipsChildren(true)
		ghostClip:SetPoint("TOPLEFT", ghostBar:GetStatusBarTexture(), "TOPLEFT")
		ghostClip:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT")
		local ghostFrame = CreateFrame("Frame", nil, ghostClip)
		ghostFrame:SetAllPoints(globe)
		local ghostMask = Mask(ghostFrame, globe)
		pool.ghostTex = Layer(ghostFrame, globe, ghostMask, "liquidTile", 0)
		-- A faint glow on the ghost's top edge, so it ends softly instead of on a hard cut.
		local cap = ghostBar:CreateTexture(nil, "OVERLAY")
		cap:SetTexture(ns.Art.Path("surfaceGlow") or ns.Art.Path("hotline"))
		cap:SetBlendMode("ADD")
		cap:SetPoint("TOPLEFT", ghostBar:GetStatusBarTexture(), "TOPLEFT", 0, 1)
		cap:SetPoint("TOPRIGHT", ghostBar:GetStatusBarTexture(), "TOPRIGHT", 0, 1)
		cap:SetHeight(1)
		cap:AddMaskTexture(Mask(ghostBar, globe))
		Smooth(cap)
		pool.ghostCap = cap
		ghostBar:Hide()
		pool.ghostBar, pool.ghostClip, pool.ghostFrame = ghostBar, ghostClip, ghostFrame
	end

	local clip = CreateFrame("Frame", nil, bar)
	clip:SetClipsChildren(true)
	clip:SetPoint("TOPLEFT", guide, "TOPLEFT")
	clip:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT")

	local frame = CreateFrame("Frame", nil, clip)
	frame:SetAllPoints(globe)
	pool.frame, pool.clip = frame, clip
	pool.mask = Mask(frame, globe)
	local mask = pool.mask
	pool.base = Layer(frame, globe, mask, "liquidTile", 0)
	pool.swirl = Layer(frame, globe, mask, "liquidTile", 1, "ADD")
	if opts.pulse then
		pool.churn = Layer(frame, globe, mask, "liquidTile", 1)
		if pool.churn then pool.churn:SetAlpha(0) end
	end
	if ns.Art.Path("liquidWisps") then
		for k = 1, 2 do
			pool.wisps[k] = Layer(frame, globe, mask, "liquidWisps", 2, "ADD")
		end
	end
	pool.streaks = Layer(frame, globe, mask, "liquidStreaks", 3, "ADD")
	if ns.Art.Path("mote") then
		for i = 1, opts.motes or 0 do
			local tex = frame:CreateTexture(nil, "ARTWORK", nil, 4)
			tex:SetTexture(ns.Art.Path("mote"))
			tex:SetBlendMode("ADD")
			tex:AddMaskTexture(mask)
			Smooth(tex)
			local seed = i * 7 + pool.phase * 50
			pool.motes[i] = {
				tex = tex, seed = seed, y = Hash(seed) * 0.8, born = 0, x = Hash(seed + 0.6) * 2 - 1,
				speed = 0.6 + 0.8 * Hash(seed + 0.3), scale = 0.7 + 0.6 * Hash(seed + 0.9),
				bright = 0.6 + 0.4 * Hash(seed + 1.2),
			}
		end
	end
	if ns.Art.Path("globeRim") then
		local rim = frame:CreateTexture(nil, "ARTWORK", nil, 5)
		rim:SetAllPoints(globe)
		rim:SetTexture(ns.Art.Path("globeRim"))
		rim:SetBlendMode("ADD")
		rim:AddMaskTexture(mask)
		pool.rim = rim
	end

	-- The surface rides the liquid level: thin slices of glow with D3's surface texture
	-- scrolling inside, each lifted by the wave. A child of the bar so it hides with it.
	local surface = CreateFrame("Frame", nil, bar)
	surface:SetAllPoints(globe)
	-- Faded over the bottom of the globe, so an empty (or secret) level never leaves the glow
	-- on the bottom edge, where it would ripple below the glass.
	local circle = Mask(surface, globe, ns.Art.Path("surfaceMask") and "surfaceMask" or nil)
	local glowPath = ns.Art.Path("surfaceGlow") or ns.Art.Path("hotline")
	local shimmerPath = ns.Art.Path("surfaceShimmer")
	for i = 1, opts.slices or SLICES do
		local glow = surface:CreateTexture(nil, "OVERLAY")
		glow:SetTexture(glowPath, "REPEAT", "CLAMPTOBLACKADDITIVE")
		glow:SetBlendMode("ADD")
		glow:AddMaskTexture(circle)
		Smooth(glow)
		local slice = { glow = glow }
		if shimmerPath then
			local shimmer = surface:CreateTexture(nil, "OVERLAY", nil, 1)
			shimmer:SetTexture(shimmerPath, "REPEAT", "CLAMPTOBLACKADDITIVE")
			shimmer:SetBlendMode("ADD")
			shimmer:SetAllPoints(glow)
			shimmer:AddMaskTexture(circle)
			Smooth(shimmer)
			slice.shimmer = shimmer
		end
		pool.slices[i] = slice
	end
	pool.surface = surface

	pool:SetColor(1, 1, 1)
	pool:ApplyStyle()
	pool:Size()
	globe:HookScript("OnSizeChanged", function() pool:Size() end)
	bar:HookScript("OnSizeChanged", function() pool:Size() end)
	bar:HookScript("OnValueChanged", function() pool:UpdateSurface() end)
	pools[#pools + 1] = pool
	byBar[bar] = pool
	return pool
end

-- Prediction bands, ridden on the fill guide so they follow the animated level:
--   heal    incoming heals, a pale green liquid poured on top of the level
--   absorb  damage shields, pale silver liquid on top of the heal (what fits in missing
--           health; the rest lights the shield glow, see Pool:SetShield)
--   cost  the cast's power cost, the top of the liquid lit from the level down to where it
--         will settle
-- Each is an invisible StatusBar one globe tall with the same range as the fill, so the
-- client sizes it even from secret values. Its fill texture bounds a clip; inside, the liquid
-- tile at full globe size under the circle mask, so the pattern lines up with the liquid
-- below. A zero band clips to nothing, edge glow and all.
local BAND = {
	heal = { color = { 0.42, 1.0, 0.36 }, alpha = 0.55, edge = 0.75 },
	absorb = { color = { 0.8, 0.88, 1.0 }, alpha = 0.5, edge = 0.85 },
	cost = { alpha = 0.32, edge = 0.6 },
}
local BAND_EDGE = 0.07 -- edge glow height, of the globe
local BAND_BREATHE = 2.2 -- rad/s

function ns.Liquid.Band(pool, kind)
	if not pool or not BAND[kind] then return nil end
	pool.bands = pool.bands or {}
	if pool.bands[kind] then return pool.bands[kind] end
	local bar, globe, guide = pool.bar, pool.globe, pool.guide
	local spec = BAND[kind]

	local pb = CreateFrame("StatusBar", nil, bar)
	pb:SetOrientation("VERTICAL")
	pb:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	pb:SetStatusBarColor(1, 1, 1, 0)
	pb:SetMinMaxValues(0, 1)
	pb:SetValue(0)
	if kind == "heal" or kind == "absorb" then
		-- The shield stacks on the heal when there is one.
		local below = kind == "absorb" and pool.bands.heal and pool.bands.heal.bar:GetStatusBarTexture() or guide
		pb:SetPoint("BOTTOMLEFT", below, "TOPLEFT")
		pb:SetPoint("BOTTOMRIGHT", below, "TOPRIGHT")
	else
		-- Fills down from the level.
		pb:SetReverseFill(true)
		pb:SetPoint("TOPLEFT", guide, "TOPLEFT")
		pb:SetPoint("TOPRIGHT", guide, "TOPRIGHT")
	end
	local fill = pb:GetStatusBarTexture()

	local clip = CreateFrame("Frame", nil, pb)
	clip:SetClipsChildren(true)
	clip:SetPoint("TOPLEFT", fill, "TOPLEFT")
	clip:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
	local frame = CreateFrame("Frame", nil, clip)
	frame:SetAllPoints(globe)
	local mask = Mask(frame, globe)
	-- Heal is new liquid, laid on; cost lights the liquid already there.
	local blend = kind == "cost" and "ADD" or nil
	local tex = Layer(frame, globe, mask, "liquidTile", 0, blend)
	if not tex then
		tex = frame:CreateTexture(nil, "ARTWORK")
		tex:SetAllPoints(globe)
		tex:SetColorTexture(1, 1, 1, 1)
		if blend then tex:SetBlendMode(blend) end
		tex:AddMaskTexture(mask)
	end
	-- The edge that means something: the heal's top (where health will be), the cost's bottom
	-- (where the resource will be). Inside the clip, so it only shows on a real band.
	local edge = frame:CreateTexture(nil, "ARTWORK", nil, 2)
	edge:SetTexture(ns.Art.Path("surfaceGlow") or ns.Art.Path("hotline") or "Interface\\Buttons\\WHITE8X8")
	edge:SetBlendMode("ADD")
	if kind ~= "cost" then
		edge:SetPoint("TOPLEFT", fill, "TOPLEFT", 0, 1)
		edge:SetPoint("TOPRIGHT", fill, "TOPRIGHT", 0, 1)
	else
		edge:SetPoint("BOTTOMLEFT", fill, "BOTTOMLEFT", 0, -1)
		edge:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 0, -1)
		edge:SetTexCoord(0, 1, 1, 0) -- glow faces up, into the band
	end
	edge:SetHeight(1)
	edge:AddMaskTexture(mask)
	Smooth(tex)
	Smooth(edge)
	pb:Hide()

	local band = { kind = kind, bar = pb, clip = clip, frame = frame, tex = tex, edge = edge, spec = spec, vel = 0 }
	pool.bands[kind] = band
	pool:SizeBands()
	pool:SetColor(unpack(pool.color))
	return band
end

function Pool:SizeBands()
	if not self.bands then return end
	local h = self.height or self.globe:GetHeight()
	if not h or h <= 0 then return end
	for _, band in pairs(self.bands) do
		band.bar:SetHeight(h)
		band.edge:SetHeight(math.max(1, h * BAND_EDGE))
	end
end

function Pool:BandColors()
	if not self.bands then return end
	local c = self.color
	for kind, band in pairs(self.bands) do
		local r, g, b
		if band.spec.color then
			r, g, b = band.spec.color[1], band.spec.color[2], band.spec.color[3]
		else
			r, g, b = Lighter(c[1], c[2], c[3], 0.55)
		end
		band.rgb = { r, g, b }
		band.edgeRgb = { Lighter(r, g, b, 0.4) }
	end
end

-- value nil or 0 clears the band. Readable values spring like the level, with the same
-- stiffness, so a heal landing fills the band from below instead of the band vanishing first,
-- and a cast going off drains the cost from the top. Secret values go straight to the bar.
function Pool:SetBand(kind, value, maxValue)
	local band = self.bands and self.bands[kind]
	if not band then return end
	local pb = band.bar
	if maxValue ~= nil then
		pcall(pb.SetMinMaxValues, pb, 0, maxValue)
	end
	if Secret(value) then
		band.target, band.shown, band.vel = nil, nil, 0
		local ease = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
		if not (ease and pcall(pb.SetValue, pb, value, ease)) and not pcall(pb.SetValue, pb, value) then
			pb:SetValue(0)
		end
		pb:Show()
		return
	end
	value = math.max(0, tonumber(value) or 0)
	if not band.shown then
		-- Coming from nothing or a secret value: grow from zero.
		band.shown, band.vel = 0, 0
		pb:SetValue(0)
	end
	band.target = value
	if value > 0 then pb:Show() end
end

function Pool:BandPhysics(dt)
	for _, band in pairs(self.bands) do
		if band.target and band.shown then
			local shown, vel = Spring(band.shown, band.vel or 0, band.target, LEVEL_OMEGA, dt)
			if math.abs(shown - band.target) < 0.5 and math.abs(vel) < 2 then
				shown, vel = band.target, 0
			end
			band.shown, band.vel = shown, vel
			band.bar:SetValue(shown)
			if shown <= 0 and band.target <= 0 then
				band.bar:Hide()
				band.target = nil
			end
		end
	end
end

-- Breathes gently, and the texture moves with the liquid's base layer.
function Pool:BandAnimate(realTime, cu, cv, half, angle)
	for _, band in pairs(self.bands) do
		if band.bar:IsShown() then
			local spec, c, e = band.spec, band.rgb, band.edgeRgb
			local breathe = 0.82 + 0.18 * math.sin(realTime * BAND_BREATHE + self.phase * 5)
			band.tex:SetVertexColor(c[1], c[2], c[3], spec.alpha * breathe)
			band.edge:SetVertexColor(e[1], e[2], e[3], spec.edge * breathe)
			if half then Affine(band.tex, cu, cv, half, angle) end
		end
	end
end

-- Shield glow: more shield than the globe has room for (always so at full health). The
-- globe's inner rim light in silver, flipped to be brightest at the top, over a fainter full
-- ring, with a highlight slowly sweeping round: a bubble over the liquid. The client gates it
-- from a secret boolean through SetAlphaFromBoolean; a readable one fades in and out.
local SHIELD_COLOR = { 0.72, 0.84, 1.0 }
local SHIELD_FADE = 4 -- per second
local SHIELD_SWEEP = 0.35 -- rad/s

function ns.Liquid.Shield(pool)
	if not pool or pool.shield or not ns.Art.Path("globeRim") then return pool and pool.shield end
	local globe = pool.globe
	local frame = CreateFrame("Frame", nil, globe)
	frame:SetAllPoints(globe)
	local layers = {}
	for i, spec in ipairs({ { flip = true, alpha = 0.85 }, { alpha = 0.35 }, { sweep = true, alpha = 0.5 } }) do
		local tex = frame:CreateTexture(nil, "ARTWORK", nil, i)
		tex:SetAllPoints(globe)
		tex:SetTexture(ns.Art.Path("globeRim"))
		tex:SetBlendMode("ADD")
		if spec.flip then tex:SetTexCoord(0, 1, 1, 0) end
		Smooth(tex)
		tex:SetAlpha(0)
		layers[i] = { tex = tex, spec = spec }
	end
	pool.shield = frame
	pool.shieldLayers = layers
	pool.shieldAlpha, pool.shieldTarget = 0, 0
	return frame
end

-- clamped: the calculator's "more shield than room" flag, nil or false for none.
function Pool:SetShield(clamped)
	if not self.shield then return end
	if Secret(clamped) then
		self.shieldSecret = true
		for _, layer in ipairs(self.shieldLayers) do
			-- Colour first, alpha last, and no colour calls until the next flag: a texture's
			-- vertex alpha and SetAlpha are one value, so a later colour would undo this.
			local c, k = SHIELD_COLOR, layer.spec.alpha
			layer.tex:SetVertexColor(c[1] * k, c[2] * k, c[3] * k)
			if not (layer.tex.SetAlphaFromBoolean and pcall(layer.tex.SetAlphaFromBoolean, layer.tex, clamped, 1, 0)) then
				layer.tex:SetAlpha(0)
			end
		end
		return
	end
	if self.shieldSecret then
		-- Back from a secret flag: take over the alpha again from where it can be known.
		self.shieldSecret = nil
		self.shieldAlpha = clamped and 1 or 0
	end
	self.shieldTarget = clamped and 1 or 0
end

function Pool:ShieldAnimate(realTime, dt)
	local target, alpha = self.shieldTarget or 0, self.shieldAlpha or 0
	if not self.shieldSecret and alpha ~= target then
		alpha = target > alpha and math.min(target, alpha + dt * SHIELD_FADE) or math.max(target, alpha - dt * SHIELD_FADE)
		self.shieldAlpha = alpha
	end
	if not self.shieldSecret and alpha <= 0 and target <= 0 then
		if self.shieldShown ~= false then
			self.shieldShown = false
			for _, layer in ipairs(self.shieldLayers) do layer.tex:SetAlpha(0) end
		end
		return
	end
	self.shieldShown = true
	local c = SHIELD_COLOR
	local breathe = 0.85 + 0.15 * math.sin(realTime * 1.6 + self.phase * 3)
	for _, layer in ipairs(self.shieldLayers) do
		local tex, spec = layer.tex, layer.spec
		if not self.shieldSecret then
			-- ADD layers: strength goes in the colour so the alpha is left to the fade.
			local k = spec.alpha * breathe
			tex:SetVertexColor(c[1] * k, c[2] * k, c[3] * k)
			tex:SetAlpha(alpha * alpha * (3 - 2 * alpha))
		end
		if spec.sweep then tex:SetRotation(realTime * SHIELD_SWEEP + self.phase * 6) end
	end
end

-- For effects drawn against the level (GlobeAura.lua): the fill guide, whose top is the level
-- (anchor to it, never read it: it can be secret), and the frame inside the clip at that level.
function Pool:Anchors()
	return self.guide, self.frame
end

-- Set a bar's value through its pool (glide) if it has one.
function ns.Liquid.SetValue(bar, value, maxValue)
	local pool = byBar[bar]
	if pool then
		pool:SetTarget(value, maxValue)
		return true
	end
	return false
end

-- base is the cluster level; the stack sits between the fill guide and the glass. The ghost
-- shares the clip level, under the liquid frame.
function Pool:SetLevels(base, offset)
	offset = offset or 0
	if self.ghostBar then
		self.ghostBar:SetFrameLevel(base + ns.LEVEL.liquid + offset)
		self.ghostClip:SetFrameLevel(base + ns.LEVEL.clip + offset)
		self.ghostFrame:SetFrameLevel(base + ns.LEVEL.clip + offset)
	end
	self.clip:SetFrameLevel(base + ns.LEVEL.clip + offset)
	self.frame:SetFrameLevel(base + ns.LEVEL.pool + offset)
	self.surface:SetFrameLevel(base + ns.LEVEL.surface + offset)
	-- Heal and shield sit above the level beside the ghost; cost lights the top of the liquid, so it
	-- goes over the liquid layers (ADD, so its order against the surface glow doesn't matter).
	for kind, band in pairs(self.bands or {}) do
		local level = base + (kind == "cost" and ns.LEVEL.surface or ns.LEVEL.clip) + offset
		band.bar:SetFrameLevel(base + ns.LEVEL.liquid + offset)
		band.clip:SetFrameLevel(level)
		band.frame:SetFrameLevel(level)
	end
	if self.shield then
		self.shield:SetFrameLevel(base + ns.LEVEL.surface + offset)
	end
	if ns.Pollution and ns.HealthGlobe and self == ns.HealthGlobe.pool then ns.Pollution.ApplyLevels() end
end

-- Fixed sphere shading over the liquid, so the volume stays put while the liquid moves.
function ns.Liquid.Shade(globe)
	if not ns.Liquid.Supported() or not ns.Art.Path("globeShade") then return nil end
	local frame = CreateFrame("Frame", nil, globe)
	frame:SetAllPoints()
	local shade = frame:CreateTexture(nil, "ARTWORK")
	shade:SetAllPoints()
	ns.Art.Apply(shade, "globeShade")
	frame.tex = shade
	return frame
end

function ns.Liquid.ApplySettings()
	-- The driver reads the settings every frame; only the style has textures to swap.
	for i = 1, #pools do
		pools[i]:ApplyStyle()
	end
end

-- Every frame: smooth motion needs it. Physics runs on real time, so the level, ghost and
-- slosh keep working with the swirl paused; the texture motion runs on the swirl clock.
function ns.Liquid.Start()
	if ns.Liquid.driver or #pools == 0 then return end
	local driver = CreateFrame("Frame", nil, UIParent)
	local clock, lastReal = 0, nil
	driver:SetScript("OnUpdate", function()
		local now = GetTime()
		local db = ns.DB()
		local dt = lastReal and Clamp(now - lastReal, 0, 0.1) or 0
		if db.liquidAnimate then
			clock = clock + dt * (tonumber(db.liquidSpeed) or 1)
		end
		lastReal = now
		ns.Liquid.ticks = (ns.Liquid.ticks or 0) + 1
		local speed = tonumber(db.liquidSpeed) or 1
		for i = 1, #pools do
			local pool = pools[i]
			-- Each pool runs its own clock so low health can speed one up without a jump.
			local fury = pool.fury or 0
			if fury > 0 and now - (pool.furyAt or 0) > FURY_HOLD then
				fury = fury * math.exp(-dt * FURY_DECAY)
				pool.fury = fury > 0.01 and fury or nil
			end
			local rate = 1 + URGE_SPIN * pool:Urgency(dt) + FURY_SPIN * fury
			pool.t = (pool.t or clock) + (db.liquidAnimate and dt * speed * rate or 0)
			pool:Physics(dt)
			if pool.frame:IsVisible() then
				pool:Animate(pool.t, now, dt)
			end
			if pool.shield then pool:ShieldAnimate(now, dt) end
		end
	end)
	ns.Liquid.driver = driver
end
