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
-- The same pool drives the big globes, the split halves and the small secondary globes;
-- the small ones zoom into the tiles (opts.zoom) so the pattern keeps its size on screen.

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
	return ("liquid animated: %d pools, %d visible, driver %s, %d ticks, base u %.2f"):format(
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

local function Lighter(r, g, b, k)
	return math.min(1, r * (1 - k) + k), math.min(1, g * (1 - k) + k), math.min(1, b * (1 - k) + k)
end

-- A pool is a plain table holding its frames. Frames keep their own widget metatable.
local Pool = {}
Pool.__index = Pool

function Pool:SetColor(r, g, b)
	self.color = { r, g, b }
	self.base:SetVertexColor(r, g, b, 1)
	self.swirl:SetVertexColor(r, g, b, LAYERS.swirl.alpha)
	local sr, sg, sb = Lighter(r, g, b, 0.5)
	if self.streaks then self.streaks:SetVertexColor(sr, sg, sb, LAYERS.streaks.alpha) end
	local wr, wg, wb = Lighter(r, g, b, 0.35)
	for _, w in ipairs(self.wisps) do
		w:SetVertexColor(wr, wg, wb, 0)
	end
	local hr, hg, hb = Lighter(r, g, b, 0.45)
	self.surfaceColor = { hr, hg, hb }
	for _, slice in ipairs(self.slices) do
		slice.glow:SetVertexColor(hr, hg, hb, 0.9)
		if slice.shimmer then slice.shimmer:SetVertexColor(hr, hg, hb, 0.55) end
	end
	if self.rim then self.rim:SetVertexColor(Lighter(r, g, b, 0.3)) end
	local mr, mg, mb = Lighter(r, g, b, 0.6)
	for _, mote in ipairs(self.motes) do
		mote.tex:SetVertexColor(mr, mg, mb, 0)
	end
	if self.ghostTex then
		local gr, gg, gb = Lighter(r, g, b, 0.3)
		self.ghostTex:SetVertexColor(gr, gg, gb, GHOST_ALPHA)
		self.ghostColor = { gr, gg, gb }
	end
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
	self:PlaceSurface(true)
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
	local ripple = RIPPLE * (ns.DB().liquidAnimate and 1 or 0)
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
	local function Wave(px)
		local x = (gx + px) / h * 2 - 1
		return (tilt * x + bob + ripple * (math.sin(x * 7.2 + t * 1.9 + phase * 9) + 0.6 * math.sin(-x * 11.5 + t * 2.7))) * h
	end
	local yl = Wave(0)
	for i, slice in ipairs(self.slices) do
		local yr = Wave(slice.x + slice.w)
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

-- New value. Secret values go straight to the bar (with the client's own easing if it has
-- one); anything else springs there.
function Pool:SetTarget(value, maxValue)
	local bar = self.bar
	if Secret(value, maxValue) then
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

function Pool:Physics(dt)
	local bar = self.bar
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

	local m = LAYERS.base
	local breathe = 1 + m.breathe * math.sin(t * m.breatheRate + phase * 7)
	Affine(self.base, phase + t * m.du * zoom, phase * 0.7 + t * m.dv * zoom, m.span * zoom * 0.5 * breathe, t * m.spin + phase * 6)
	if self.ghostTex and self.ghost then
		Affine(self.ghostTex, phase + t * m.du * zoom, phase * 0.7 + t * m.dv * zoom, m.span * zoom * 0.5 * breathe, t * m.spin + phase * 6)
	end
	m = LAYERS.swirl
	breathe = 1 + m.breathe * math.sin(t * m.breatheRate + phase * 3)
	Affine(self.swirl, phase + 0.37 + t * m.du * zoom, 0.5 + t * m.dv * zoom, m.span * zoom * 0.5 * breathe, t * m.spin + phase * 2)
	if self.streaks then
		m = LAYERS.streaks
		local u = phase + 0.71 + t * m.du * zoom
		local v = phase + math.sin(t * m.swayRate + phase * 40) * m.sway
		Affine(self.streaks, u, v, m.span * zoom * 0.5, 0)
	end

	-- Wisps: two copies half a cycle apart. Each fades in, drifts and turns, fades out, and is
	-- reseeded somewhere new while invisible, so the pattern never visibly repeats or slides.
	local wr, wg, wb = Lighter(self.color[1], self.color[2], self.color[3], 0.35)
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

	-- Heartbeat and flare light the rim and swirl.
	local beat = self:Heartbeat(realTime)
	local flare = self.flare or 0
	if self.rim then
		local r, g, b = Lighter(self.color[1], self.color[2], self.color[3], 0.3)
		self.rim:SetVertexColor(r, g, b, Clamp(0.42 + 0.55 * beat + 0.35 * flare, 0, 1))
	end
	self.swirl:SetVertexColor(self.color[1], self.color[2], self.color[3], Clamp(LAYERS.swirl.alpha + 0.3 * beat, 0, 1))
	if self.surfaceShown ~= false then
		local c = self.surfaceColor
		local glow = Clamp(0.85 + 0.15 * beat + 0.4 * flare, 0, 1)
		local cr, cg, cb = Lighter(c[1], c[2], c[3], 0.5 * flare)
		for _, slice in ipairs(self.slices) do
			slice.glow:SetVertexColor(cr, cg, cb, glow)
		end
	end

	self:Motes(t, dt)
	self.clock = t
	self:PlaceSurface(false, t)
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
		local r, g, b = Lighter(c[1], c[2], c[3], 0.6)
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
	local circle = Mask(surface, globe)
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
	pool:Size()
	globe:HookScript("OnSizeChanged", function() pool:Size() end)
	bar:HookScript("OnSizeChanged", function() pool:Size() end)
	bar:HookScript("OnValueChanged", function() pool:UpdateSurface() end)
	pools[#pools + 1] = pool
	byBar[bar] = pool
	return pool
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
	-- The driver reads the settings every frame; nothing to rebuild.
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
		for i = 1, #pools do
			local pool = pools[i]
			pool:Physics(dt)
			if pool.frame:IsVisible() then
				pool:Animate(clock, now, dt)
			end
		end
	end)
	ns.Liquid.driver = driver
end
