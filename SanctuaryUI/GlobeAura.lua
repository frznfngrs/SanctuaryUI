SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.GlobeAura = ns.GlobeAura or {}

-- Light on the globes while a buff in WatchEffects.lua is up (Watch.lua says which). Each globe
-- shows up to three effects of each look at once, strongest first: more radiances ring outward
-- in their own colours, more shells nest, more surges turn against each other. Each effect's
-- strength (WatchEffects.lua) scales its brightness. In a buff's last seconds every look blinks,
-- quicker and deeper as it runs out.
--
--   radiate  light radiating from behind the globe (seals, Last Stand, Lightning Shield)
--     corona   a bright band hugging the rim over a wide halo, breathing
--     rays     two sets of god rays turning slowly against each other, so they shimmer
--     wisps    licks of flame off the rim in two phases, each drifting out as it fades
--     hot      a tighter, paler copy of the corona: the white-hot edge of D3's fire FX
--     sparks   motes rising off the top of the rim
--     catch    the light wrapping round onto the globe's glass
--     storm    (Lightning Shield) static crackling all round the rim, arcs flashing and
--              crawling along it, and bolts striking out off it in a stutter of strobes with a
--              hot spot where they leave the rim; spending the charges discharges it in a burst
--     moments  lit: a shockwave ring swells off the rim and the rays flare; recast: a smaller
--              ring; last seconds: the glow sinks and flickers; judged away: the light bursts
--              outward and is gone; otherwise it fades
--
--   shell    a crystal shield over the glass, D3's Diamond Skin (Divine Shield, Power Word:
--            Shield, Ice Barrier, Shield Wall, Evasion)
--     halo     the corona, faint, behind the globe
--     rim      fresnel: clear in the middle, bright toward the edge
--     facets   the crystal's seams, turning slowly, flashing when the shield takes a hit
--     sheen    a glint band sweeping across every few seconds
--     moments  formed: it swells into place with a ring; broken: it shatters, shards flying
--              off and a ring thrown outward; otherwise it fades
--     Damage shields hang on the game's absorb amount (Watch.AbsorbMode "live"): drawn inside
--     a clip frame whose top rides an invisible status bar fed the hidden amount, clamped to
--     0..1, so the shell shows exactly while any absorb holds and is gone the moment it breaks.
--
--   surge    light pouring into the globe (Evocation, Innervate, Bloodrage, drinking)
--     spiral   arms of light curling in, shrinking toward the rim in two crossfading phases
--     ring     a ring closing in on the rim, again and again
--     bloom    the glass lit from inside, and motes spiralling in
--
--   flare    a one-off burst (Life Tap, potions): a ring and a flash, out from the globe or
--            in to it
--
-- Behind-the-globe layers sit under the globe stack and the console art, so the gargoyle and
-- angel stand in silhouette against them; glass layers sit with the glass, under the console
-- art; shards fly over the console. All white art drawn ADD and tinted here
-- (tools/build_hud_art.py globe_aura, globe_shell, globe_surge).

local SCALE = 2 -- behind-the-globe art, of the globe's diameter (AURA_SCALE in build_hud_art.py)
local SHELL = 1.03 -- the shell, of the globe's diameter
local MOTES, SURGE_MOTES, SHARDS = 7, 10, 14
local GUTTER = 6 -- seconds left when a look starts to blink out
local STACK = 3 -- effects of one look on one globe at once
-- How far each further effect of a look sits outward, of its size.
local RANK_SCALE = { radiate = 0.14, shell = 0.06, surge = 0.12 }
local HIT = 0.45 -- seconds a shield's hit ripple runs

-- sat: the wide layers. hot: the rim, the flashes, the sparks.
local TINTS = {
	holy = { sat = { 1.0, 0.62, 0.14 }, hot = { 1.0, 0.88, 0.55 } },
	holyShield = { sat = { 1.0, 0.78, 0.32 }, hot = { 1.0, 0.95, 0.78 } },
	arcane = { sat = { 0.16, 0.42, 1.0 }, hot = { 0.62, 0.84, 1.0 } },
	arcaneViolet = { sat = { 0.55, 0.35, 1.0 }, hot = { 0.85, 0.75, 1.0 } },
	frost = { sat = { 0.35, 0.72, 1.0 }, hot = { 0.86, 0.96, 1.0 } },
	fire = { sat = { 1.0, 0.35, 0.08 }, hot = { 1.0, 0.75, 0.4 } },
	shadow = { sat = { 0.62, 0.28, 1.0 }, hot = { 0.88, 0.74, 1.0 } },
	nature = { sat = { 0.35, 0.9, 0.3 }, hot = { 0.8, 1.0, 0.7 } },
	innervate = { sat = { 0.25, 0.95, 0.8 }, hot = { 0.75, 1.0, 0.95 } },
	bark = { sat = { 0.62, 0.42, 0.2 }, hot = { 0.95, 0.8, 0.55 } },
	steel = { sat = { 0.65, 0.72, 0.82 }, hot = { 0.95, 0.97, 1.0 } },
	blood = { sat = { 0.9, 0.08, 0.05 }, hot = { 1.0, 0.55, 0.4 } },
	rage = { sat = { 1.0, 0.3, 0.05 }, hot = { 1.0, 0.7, 0.35 } },
	smoke = { sat = { 0.55, 0.55, 0.6 }, hot = { 0.9, 0.9, 0.95 } },
	storm = { sat = { 0.3, 0.6, 1.0 }, hot = { 0.85, 0.95, 1.0 } },
	energy = { sat = { 1.0, 0.8, 0.25 }, hot = { 1.0, 0.95, 0.7 } },
	amber = { sat = { 1.0, 0.6, 0.15 }, hot = { 1.0, 0.88, 0.6 } },
	water = { sat = { 0.2, 0.6, 1.0 }, hot = { 0.7, 0.9, 1.0 } },
	hearth = { sat = { 1.0, 0.55, 0.25 }, hot = { 1.0, 0.85, 0.6 } },
	vital = { sat = { 1.0, 0.2, 0.12 }, hot = { 1.0, 0.7, 0.55 } },
	fel = { sat = { 0.4, 1.0, 0.25 }, hot = { 0.85, 1.0, 0.7 } },
}
ns.GlobeAura.TINTS = TINTS

-- How long each ending takes to fade, by Watch.lua's reason.
local FADE = { consumed = 0.35, expired = 0.9, died = 1.2, replaced = 0.4, gate = 0.5, gone = 0.5, broken = 0.12, spent = 0.5, ended = 0.6 }
local FADE_IN = 0.35
local IGNITE, REKINDLE, RELEASE, SHATTER, FLARE = 0.8, 0.5, 0.55, 0.9, 0.75

local MANA = Enum and Enum.PowerType and Enum.PowerType.Mana or 0
local LOOKS = { "radiate", "shell", "surge" }

local globes = {} -- "health" / "resource" -> { frame = the globe, radiate, shell, surge, flares }
local driver
local preview

local function Opt()
	return ns.DB().globeAuras
end

local function Smoothstep(x)
	x = math.max(0, math.min(1, x))
	return x * x * (3 - 2 * x)
end

local function Out(t) return 1 - (1 - t) ^ 3 end

local function Hash(n)
	local x = math.sin(n * 12.9898 + 78.233) * 43758.5453
	return x - math.floor(x)
end

-- Texcoords turned by angle about the middle; the art is clamped to clear, so the corners
-- that swing outside it stay empty.
local function Spin(tex, angle)
	if not tex then return end
	local c, s = math.cos(angle) * 0.5, math.sin(angle) * 0.5
	local function P(dx, dy) return 0.5 + dx * c - dy * s, 0.5 + dx * s + dy * c end
	local ulx, uly = P(-1, -1)
	local llx, lly = P(-1, 1)
	local urx, ury = P(1, -1)
	local lrx, lry = P(1, 1)
	tex:SetTexCoord(ulx, uly, llx, lly, urx, ury, lrx, lry)
end

local function Sprite(frame, slot, sublevel)
	local path = ns.Art.Path(slot)
	if not path then return nil end
	local tex = frame:CreateTexture(nil, "ARTWORK", nil, sublevel)
	tex:SetTexture(path, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	tex:SetBlendMode("ADD")
	tex:SetPoint("CENTER")
	if tex.SetSnapToPixelGrid then
		tex:SetSnapToPixelGrid(false)
		tex:SetTexelSnappingBias(0)
	end
	tex:SetAlpha(0)
	return tex
end

local function Paint(tex, color, alpha)
	if not tex then return end
	tex:SetVertexColor(color[1], color[2], color[3])
	tex:SetAlpha(math.max(0, math.min(1, alpha)))
end

local function Size(tex, size)
	if tex then tex:SetSize(size, size) end
end

local function Lerp(color, to, k)
	for i = 1, 3 do
		color[i] = color[i] + (to[i] - color[i]) * k
	end
end

-- A frame for one depth of a look; Layout sets its level (aura, glass or shards).
local function Layer(parent)
	local frame = CreateFrame("Frame", nil, parent)
	frame:EnableMouse(false)
	return frame
end

---------------------------------------------------------------------------
-- What an instance shares: which effect it shows, its level (eased 0..1) and colours.

local function NewInstance(look)
	local tint = TINTS.holy
	return {
		look = look, level = 0, target = 0, fade = 0.5, rank = 0, scale = 1, scaleTo = 1,
		sat = { unpack(tint.sat) }, hotColor = { unpack(tint.hot) }, satTo = tint.sat, hotTo = tint.hot,
	}
end

-- Level and colour for this frame; false once dark and staying dark.
local function Ease(inst, now, dt, busy)
	if inst.target > inst.level then
		inst.level = math.min(inst.target, inst.level + dt / FADE_IN)
	elseif inst.target < inst.level then
		inst.level = math.max(inst.target, inst.level - dt / inst.fade)
	end
	-- (Just lit, the level is still 0 on the first frame.)
	if inst.level <= 0 and inst.target <= 0 and not busy then return false end
	local k = math.min(1, dt * 6)
	Lerp(inst.sat, inst.satTo, k)
	Lerp(inst.hotColor, inst.hotTo, k)
	inst.scale = inst.scale + (inst.scaleTo - inst.scale) * math.min(1, dt * 4)
	return true
end

local function Strength(inst)
	local effect = inst.effect or inst.lastEffect
	return effect and effect.strength or 1
end

-- Last seconds: a blink that quickens (1.2 to 5 a second) and deepens as the buff runs out.
-- Returns the brightness factor and how far into the gutter (0..1).
local function Gutter(inst, now, dt)
	local st = inst.effect and inst.st
	local g = 0
	if st and st.up and st.expires then g = Smoothstep(1 - (st.expires - now) / GUTTER) end
	if g <= 0 then
		inst.gphase = 0
		return 1, 0
	end
	inst.gphase = (inst.gphase or 0) + dt * 2 * math.pi * (1.2 + 3.8 * g)
	local bright = 0.5 + 0.5 * math.cos(inst.gphase)
	return 1 - g * (0.25 + 0.65 * (1 - bright)), g
end

---------------------------------------------------------------------------
-- Radiate.

local function BuildRadiate(g)
	local r = NewInstance("radiate")
	local frame = Layer(ns.Cluster, "aura")
	frame:Hide()
	r.frame = frame
	r.corona = Sprite(frame, "auraCorona", 0)
	r.raysA = Sprite(frame, "auraRaysA", 1)
	r.raysB = Sprite(frame, "auraRaysB", 2)
	r.raysC = Sprite(frame, "auraRaysB", 2) -- extra rays for effects stronger than 1
	r.wisps = { Sprite(frame, "auraWispsA", 3), Sprite(frame, "auraWispsB", 3) }
	r.hot = Sprite(frame, "auraCorona", 4)
	r.burst = Sprite(frame, "auraRing", 5)
	r.burstHot = Sprite(frame, "auraRing", 6)
	r.motes = {}
	for i = 1, MOTES do
		local tex = Sprite(frame, "mote", 7)
		if tex then r.motes[i] = { tex = tex, cycle = -1 } end
	end
	-- The catch light rides on the glass, above the liquid and under the console art.
	local catch = Layer(ns.Cluster, "glass")
	catch:Hide()
	r.catchFrame = catch
	if ns.Art.Path("globeRim") then
		local rim = catch:CreateTexture(nil, "ARTWORK")
		rim:SetTexture(ns.Art.Path("globeRim"))
		-- globe-rim.png is brightest at the bottom; flipped, the light comes over the top.
		rim:SetTexCoord(0, 1, 1, 0)
		rim:SetBlendMode("ADD")
		rim:SetAllPoints()
		r.catch = rim
	end
	-- Storm: all behind the globe, so the globe and the console cut it off like the rest.
	r.static = { Sprite(frame, "stormStatic", 4), Sprite(frame, "stormStatic", 4) }
	r.arcs = {}
	for k, letter in ipairs({ "A", "B", "C", "D", "E", "F" }) do
		r.arcs[k] = Sprite(frame, "stormArcs" .. letter, 5)
	end
	r.bolts, r.roots = {}, {}
	for k, letter in ipairs({ "A", "B", "C", "D" }) do
		r.bolts[k] = Sprite(frame, "stormBolt" .. letter, 6)
		r.roots[k] = Sprite(frame, "mote", 7)
	end
	r.frames = { frame, catch }
	r.ok = r.corona ~= nil
	return r
end

-- A flicker for one flash: on, a gap, on again, then a fade; zero outside the first `width` of
-- its cycle. phase: 0..1 through the cycle.
local function Flicker(phase, width)
	local t = phase / width
	if t >= 1 then return 0 end
	if t < 0.25 then return 1 end
	if t < 0.4 then return 0.25 end
	if t < 0.6 then return 0.9 end
	return 0.9 * (1 - (t - 0.6) / 0.4)
end

-- A bolt's strobe: two or three hard flashes, then a fading afterimage; zero outside the first
-- `width` of its cycle. Also returns which flash it is in, so each can jump a little.
local function Strobe(phase, width)
	local t = phase / width
	if t >= 1 then return 0, 0 end
	if t < 0.1 then return 1, 1 end
	if t < 0.17 then return 0.15, 1 end
	if t < 0.27 then return 1, 2 end
	if t < 0.33 then return 0.2, 2 end
	if t < 0.42 then return 0.85, 3 end
	return 0.55 * (1 - (t - 0.42) / 0.58) ^ 2, 3
end

local function HideStorm(a)
	for _, list in ipairs({ a.static, a.arcs, a.bolts, a.roots }) do
		for _, tex in ipairs(list) do tex:SetAlpha(0) end
	end
	a.strike = 0
end

-- Lightning for a storm radiance. Every flash picks its texture's turn and whether it fires
-- from a hash of its cycle, so it is random to the eye but costs nothing to keep. Calm (a long
-- buff settled), the static stays and arcs and bolts come only now and then.
local function AnimateStorm(g, a, now, base, sat, hot)
	local size = g.size * SCALE * a.scale
	local r = g.size / 2
	local calm = a.calm or 0
	local strike = 0
	-- Static: two copies of the rim crackle, each turned anew every 50 ms.
	for k, tex in ipairs(a.static) do
		local tick = math.floor(now * 20) + k * 31
		Size(tex, size * (1 + 0.01 * k))
		Spin(tex, Hash(tick) * 6.283)
		Paint(tex, k == 1 and sat or hot, (0.45 - 0.2 * calm) * (0.5 + 0.5 * Hash(tick + 7)) * base)
	end
	-- Arcs: six, each on its own beat, crawling a short way along the rim while they flash.
	for k, tex in ipairs(a.arcs) do
		local period = 0.17 + 0.045 * k
		local t = now / period + k * 0.37
		local cycle = math.floor(t)
		local phase = t - cycle
		local fire = Hash(cycle * 3 + k) > 0.35 + 0.5 * calm and Flicker(phase, 0.55) or 0
		local crawl = (Hash(cycle * 13 + k) > 0.5 and 1 or -1) * phase * period * 2.2
		Size(tex, size * (1 + 0.02 * (Hash(cycle + k) - 0.5)))
		Spin(tex, Hash(cycle * 7 + k) * 6.283 + crawl)
		Paint(tex, k % 3 == 0 and hot or sat, 1.3 * fire * base)
		strike = math.max(strike, fire * 0.35)
	end
	-- Bolts: now and then one strikes out off the upper rim in a stutter of strobes, jumping a
	-- little between them, with a hot spot where it leaves the rim.
	for k, tex in ipairs(a.bolts) do
		local period = 0.5 + 0.21 * k
		local t = now / period + k * 0.61
		local cycle = math.floor(t)
		local fire, flash = 0, 0
		if Hash(cycle * 5 + k * 13) > 0.4 + 0.5 * calm then fire, flash = Strobe(t - cycle, 0.45) end
		local root = a.roots[k]
		if fire > 0 then
			local angle = math.rad(25 + 130 * Hash(cycle * 11 + k)) + (Hash(cycle * 19 + flash) - 0.5) * 0.08
			local length = r * (0.8 + 0.7 * Hash(cycle * 17 + k))
			local dist = r * 0.98 + length * 0.5
			tex:ClearAllPoints()
			tex:SetPoint("CENTER", a.frame, "CENTER", math.cos(angle) * dist, math.sin(angle) * dist)
			Size(tex, length * 1.05)
			-- The art strikes upward; turned so it strikes out along the radius.
			Spin(tex, angle - math.pi / 2)
			root:ClearAllPoints()
			root:SetPoint("CENTER", a.frame, "CENTER", math.cos(angle) * r * 1.0, math.sin(angle) * r * 1.0)
			Size(root, r * 0.55)
		end
		Paint(tex, hot, 1.4 * fire * base)
		Paint(root, hot, 1.2 * fire * base)
		strike = math.max(strike, fire)
	end
	a.strike = strike
end

local function AnimateRadiate(g, a, now, dt)
	local releasing = a.release and now - a.release < RELEASE
	if not a.ok or not Ease(a, now, dt, releasing) then
		a.frame:Hide()
		a.catchFrame:Hide()
		return false
	end
	local opt = Opt()
	a.frame:Show()
	a.catchFrame:SetShown(opt.catch and a.catch ~= nil)
	local e = Smoothstep(a.level)
	local intensity = tonumber(opt.intensity) or 1
	local size = g.size * SCALE * a.scale
	-- Last seconds: the glow blinks out and the rays draw in.
	local flicker, gutter = Gutter(a, now, dt)
	local breath = 0.86 + 0.14 * math.sin(now * 2 * math.pi / 2.8)
	-- A lightning strike (last frame's) lights the whole glow up for a blink.
	local struck = 1 + 0.6 * (a.strike or 0)
	local base = e * intensity * flicker * Strength(a)
	local turn = a.rank * 1.7 -- stacked radiances don't line their rays up
	-- A long buff calms 8 to 10 s after lighting (recasting lights it again), and wakes for its
	-- last seconds so the ending still shows.
	local calm = 0
	local effect = a.effect or a.lastEffect
	if effect and effect.long and opt.settleLong then
		calm = Smoothstep((now - (a.litAt or now) - 8) / 2) * (1 - Smoothstep(gutter * 2.5))
	end
	a.calm = calm

	-- Flashes: a shockwave ring leaves the rim. Lighting and rekindling swell it gently while
	-- the rays flare; a release throws it (and the rays) outward as the light goes.
	local flash, flashSize, flashAlpha = 0, 1, 0
	if a.ignite and now - a.ignite < IGNITE then
		local t = (now - a.ignite) / IGNITE
		flash = (1 - t) ^ 2
		flashSize, flashAlpha = 1 + 0.55 * Out(t), (1 - t) ^ 1.5
	elseif a.rekindle and now - a.rekindle < REKINDLE then
		local t = (now - a.rekindle) / REKINDLE
		flash = 0.5 * (1 - t) ^ 2
		flashSize, flashAlpha = 1 + 0.3 * Out(t), 0.6 * (1 - t) ^ 1.5
	end
	local blow = 0
	if releasing then
		local t = (now - a.release) / RELEASE
		blow = Out(t)
		flash = 1.5 * (1 - t) ^ 2
		flashSize, flashAlpha = 1 + 1.0 * blow, 1.3 * (1 - t) ^ 1.2
	end

	local sat, hot = a.sat, a.hotColor
	Size(a.corona, size * (1 + 0.015 * math.sin(now * 2.2) + 0.15 * blow))
	Paint(a.corona, sat, 0.85 * breath * base * struck * (1 - 0.5 * calm))
	local rayScale = (1 + 0.5 * blow) * (1 - 0.18 * gutter)
	if opt.rays then
		Size(a.raysA, size * rayScale)
		Spin(a.raysA, now * 0.05 + turn)
		Paint(a.raysA, sat, 0.85 * base * (1 - 0.85 * calm) * (0.85 + 0.15 * math.sin(now * 0.9)) * (1 + 1.2 * flash))
		Size(a.raysB, size * 1.04 * rayScale)
		Spin(a.raysB, 1.3 - now * 0.035 - turn)
		Paint(a.raysB, hot, 0.4 * base * (1 - 0.85 * calm) * (0.8 + 0.2 * math.sin(now * 1.3 + 1)) * (1 + flash))
		-- Strength past 1 can't brighten what is already at full: it adds a further, longer set
		-- of rays turning its own way instead.
		local boost = math.max(0, Strength(a) - 1)
		Size(a.raysC, size * 1.12 * rayScale)
		Spin(a.raysC, 2.6 + now * 0.07 + turn)
		Paint(a.raysC, sat, 1.1 * boost * e * intensity * flicker * (0.85 + 0.15 * math.sin(now * 1.1 + 2)) * (1 + flash))
	else
		Paint(a.raysA, sat, 0)
		Paint(a.raysB, hot, 0)
		Paint(a.raysC, sat, 0)
	end
	-- Wisps: two phases half a cycle apart, each growing outward while it fades in and out,
	-- reseeded (a new turn) while invisible, so the flames never repeat in place.
	for i, tex in ipairs(a.wisps) do
		if tex then
			local t = now / 3 + (i - 1) * 0.5
			local cycle = math.floor(t)
			local p = t - cycle
			Size(tex, size * (1 + 0.06 * p + 0.2 * blow))
			Spin(tex, Hash(cycle * 2 + i) * 6.283 + now * 0.04)
			Paint(tex, sat, 0.75 * math.sin(p * math.pi) * base * (1 - 0.7 * calm))
		end
	end
	Size(a.hot, size * 0.9)
	-- (hot and wisps already take Strength through base)
	Paint(a.hot, hot, 0.55 * breath * base * (1 + 0.6 * flash) * struck * (1 - 0.5 * calm))
	-- The ring's body in the deep colour, its leading edge white-hot just inside it.
	Size(a.burst, size * flashSize)
	Paint(a.burst, sat, flashAlpha * intensity)
	Size(a.burstHot, size * flashSize * 0.99)
	Paint(a.burstHot, hot, 0.7 * flashAlpha * intensity)
	if a.catch then
		a.catch:SetVertexColor(hot[1], hot[2], hot[3])
		a.catch:SetAlpha(math.min(1, 0.35 * breath * base * (1 - 0.6 * calm)))
	end

	-- Sparks: rise off the upper rim (the lower half is behind the console), drift out and up,
	-- sway and fade. Each lives one cycle of its own length, then starts somewhere new.
	local r = g.size / 2
	for i, mote in ipairs(a.motes) do
		if opt.sparks and base > 0 and calm < 0.5 then
			local life = 1.6 + Hash(i * 7.1) * 1.0
			local t = now / life + Hash(i * 3.3)
			local cycle = math.floor(t)
			local p = t - cycle
			if cycle ~= mote.cycle then
				mote.cycle = cycle
				local seed = cycle * 13 + i * 101
				mote.angle = math.rad(20 + 140 * Hash(seed))
				mote.out = 0.3 + 0.3 * Hash(seed + 1)
				mote.size = (0.08 + 0.06 * Hash(seed + 2)) * r
				mote.sway = (Hash(seed + 3) - 0.5) * 0.3
				mote.peak = 0.5 + 0.5 * Hash(seed + 4)
			end
			local dist = r * (1.02 + mote.out * p)
			local x = math.cos(mote.angle) * dist + math.sin(p * 6.28 + i) * mote.sway * r * 0.3
			local y = math.sin(mote.angle) * dist + 0.25 * r * p
			mote.tex:ClearAllPoints()
			mote.tex:SetPoint("CENTER", a.frame, "CENTER", x, y)
			Size(mote.tex, mote.size * (1 - 0.4 * p))
			local fade = p < 0.2 and p / 0.2 or (1 - p) / 0.8
			Paint(mote.tex, hot, mote.peak * fade * base)
		else
			Paint(mote.tex, hot, 0)
		end
	end
	if effect and effect.storm and base > 0 then
		AnimateStorm(g, a, now, base, sat, hot)
	else
		HideStorm(a)
	end
	return true
end

---------------------------------------------------------------------------
-- Shell.

local function BuildShell(g)
	local s = NewInstance("shell")
	-- The gate: everything but the shatter lives in a clip frame whose top follows the fill of
	-- an invisible 0..1 status bar. Fed the hidden absorb amount it is full while any absorb
	-- holds and empty at none; fed 1 it is always full.
	local bar = CreateFrame("StatusBar", nil, ns.Cluster)
	bar:SetOrientation("VERTICAL")
	bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	bar:SetStatusBarColor(0, 0, 0, 0)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(1)
	bar:EnableMouse(false)
	s.bar = bar
	local clip = CreateFrame("Frame", nil, ns.Cluster)
	clip:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT")
	clip:SetPoint("TOPRIGHT", bar:GetStatusBarTexture(), "TOPRIGHT")
	if clip.SetClipsChildren then clip:SetClipsChildren(true) end
	clip:EnableMouse(false)
	s.clip = clip
	local behind = Layer(clip, "aura")
	behind:SetAllPoints(bar)
	local front = Layer(clip, "glass")
	front:SetAllPoints(bar)
	s.halo = Sprite(behind, "auraCorona", 0)
	s.rim = Sprite(front, "shellRim", 0)
	s.facets = Sprite(front, "shellFacets", 1)
	s.sheen = Sprite(front, "shellSheen", 2)
	s.formRing = Sprite(behind, "auraRing", 1)
	-- A hit: a ripple spreads across the shell from where it struck, kept inside the glass.
	s.ripple = Sprite(front, "auraRing", 3)
	s.rippleHot = Sprite(front, "auraRing", 4)
	s.impact = Sprite(front, "mote", 5) -- the white-hot spot where the blow landed
	if s.sheen and front.CreateMaskTexture and ns.Art.Path("globeMask") then
		local mask = front:CreateMaskTexture()
		mask:SetTexture(ns.Art.Path("globeMask"), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		mask:SetPoint("CENTER")
		for _, tex in ipairs({ s.sheen, s.ripple, s.rippleHot, s.impact }) do
			if tex then tex:AddMaskTexture(mask) end
		end
		s.mask = mask
	end
	-- The shatter flies free of the gate: when an absorb breaks, the gate has already shut.
	local shatterBehind = Layer(ns.Cluster, "aura")
	local shards = Layer(ns.Cluster, "shards")
	s.ring = Sprite(shatterBehind, "auraRing", 0)
	s.ringHot = Sprite(shatterBehind, "auraRing", 1)
	s.shards = {}
	for i = 1, SHARDS do
		local tex = Sprite(shards, i % 2 == 0 and "shellShardA" or "shellShardB", 0)
		local hot = Sprite(shards, i % 2 == 0 and "shellShardA" or "shellShardB", 1)
		if tex then s.shards[i] = { tex = tex, hot = hot } end
	end
	s.frames = { bar, clip, behind, front, shatterBehind, shards }
	s.levelFrames = { behind = behind, front = front, shatterBehind = shatterBehind, shards = shards }
	s.ok = s.rim ~= nil
	return s
end

-- Feed the gate: the game's absorb amount for damage shields when it reports them, else full.
local function FeedGate(s)
	local effect = s.effect or s.lastEffect
	local gated = effect and (effect.absorb or effect.kind == "absorb")
	if gated and ns.Watch.AbsorbMode() == "live" and UnitGetTotalAbsorbs then
		local ok, amount = pcall(UnitGetTotalAbsorbs, "player")
		if ok and amount ~= nil and pcall(s.bar.SetValue, s.bar, amount) then return end
	end
	s.bar:SetValue(1)
end

local function AnimateShell(g, s, now, dt)
	local shattering = s.shatter and now - s.shatter < SHATTER
	if not s.ok or not Ease(s, now, dt, shattering) then
		s.clip:Hide()
		s.levelFrames.shatterBehind:Hide()
		s.levelFrames.shards:Hide()
		return false
	end
	s.clip:Show()
	local opt = Opt()
	local e = Smoothstep(s.level)
	local intensity = tonumber(opt.intensity) or 1
	local size = g.size * SHELL * s.scale
	local sat, hot = s.sat, s.hotColor
	local flicker = Gutter(s, now, dt)
	-- Forming: it swells into place with a ring off the rim and a flash in the facets.
	local form = 0
	if s.ignite and now - s.ignite < IGNITE then
		form = 1 - (now - s.ignite) / IGNITE
	end
	-- A hit: the crystal flares and gives a little, and a ripple runs out from the blow.
	local hit, hitT = 0, nil
	if s.hit and now - s.hit < HIT then
		hitT = (now - s.hit) / HIT
		hit = (1 - hitT) ^ 2
	end
	local swell = (1 - 0.08 * form ^ 2) * (1 - 0.035 * hit)
	local breath = 0.9 + 0.1 * math.sin(now * 2 * math.pi / 3.2)
	local base = e * intensity * Strength(s) * flicker
	Size(s.halo, g.size * SCALE * 0.96 * s.scale)
	Paint(s.halo, sat, 0.7 * breath * base * (1 + 0.8 * hit))
	Size(s.rim, size * swell)
	Paint(s.rim, sat, base * (1 + 0.5 * form + hit))
	Size(s.facets, size * swell)
	Spin(s.facets, now * 0.03 + s.rank * 0.9)
	Paint(s.facets, hot, 0.65 * base * (0.85 + 0.15 * math.sin(now * 1.7)) * (1 + 1.5 * form + 2.5 * hit))
	if hitT then
		local r = size / 2
		local x, y = math.cos(s.hitAngle) * r * 0.5, math.sin(s.hitAngle) * r * 0.5
		-- The ripple's ring sits at a quarter of its sprite: grown to 2.6x the shell it has
		-- crossed the whole globe from the blow.
		local spread = size * (0.2 + 2.4 * Out(hitT))
		for _, tex in ipairs({ s.ripple, s.rippleHot, s.impact }) do
			tex:ClearAllPoints()
			tex:SetPoint("CENTER", s.levelFrames.front, "CENTER", x, y)
		end
		Size(s.ripple, spread)
		Paint(s.ripple, sat, 1.6 * (1 - hitT) ^ 1.2 * intensity)
		Size(s.rippleHot, spread * 0.92) -- a second ring just behind the first
		Paint(s.rippleHot, hot, 1.3 * (1 - hitT) ^ 1.2 * intensity)
		Size(s.impact, size * (0.35 + 0.25 * hitT))
		Paint(s.impact, hot, 1.5 * (1 - hitT) ^ 2.5 * intensity)
	else
		Paint(s.ripple, sat, 0)
		Paint(s.rippleHot, hot, 0)
		Paint(s.impact, hot, 0)
	end
	-- The sheen sweeps from top left to bottom right every 3 s, under the globe mask.
	if s.sheen then
		local p = (now % 3) / 3
		local off = (p - 0.5) * size * 0.8
		Size(s.sheen, size * 1.6)
		s.sheen:ClearAllPoints()
		s.sheen:SetPoint("CENTER", s.levelFrames.front, "CENTER", off, -off)
		if s.mask then s.mask:SetSize(size, size) end
		Paint(s.sheen, hot, 0.55 * base * math.sin(p * math.pi))
	end
	Size(s.formRing, g.size * SCALE * s.scale * (1 + 0.4 * Out(1 - form)))
	Paint(s.formRing, hot, form > 0 and 0.8 * form ^ 1.5 * intensity or 0)

	-- Shatter: shards thrown off the upper half, tumbling and falling, a ring blown outward.
	local shown = shattering and true or false
	s.levelFrames.shatterBehind:SetShown(shown)
	s.levelFrames.shards:SetShown(shown)
	if shattering then
		local t = (now - s.shatter) / SHATTER
		local ringSize = g.size * SCALE * (1 + 0.5 * Out(t))
		Size(s.ring, ringSize)
		Paint(s.ring, s.shatterSat, 1.2 * (1 - t) * intensity)
		Size(s.ringHot, ringSize * 0.99)
		Paint(s.ringHot, s.shatterHot, 0.8 * (1 - t) * intensity)
		local r = g.size / 2
		for i, shard in ipairs(s.shards) do
			local seed = s.shatterSeed + i * 17
			local angle = i <= 10 and math.rad(15 + 150 * Hash(seed)) or Hash(seed) * 6.283
			local speed = 0.7 + 0.6 * Hash(seed + 1)
			local dist = r * (0.95 + 1.1 * speed * Out(t))
			local x = math.cos(angle) * dist
			local y = math.sin(angle) * dist - r * 0.6 * t * t
			local sz = r * (0.28 + 0.24 * Hash(seed + 2)) * (1 - 0.3 * t)
			local spin = Hash(seed + 3) * 6.283 + (Hash(seed + 4) - 0.5) * 8 * t
			local alpha = (1 - t) ^ 0.7 * intensity
			for _, tex in ipairs({ shard.tex, shard.hot }) do
				tex:ClearAllPoints()
				tex:SetPoint("CENTER", s.levelFrames.shards, "CENTER", x, y)
				Size(tex, sz)
				Spin(tex, spin)
			end
			Paint(shard.tex, s.shatterSat, 1.6 * alpha)
			Paint(shard.hot, s.shatterHot, 0.8 * alpha)
		end
	end
	return true
end

---------------------------------------------------------------------------
-- Surge.

local function BuildSurge(g)
	local u = NewInstance("surge")
	local behind = Layer(ns.Cluster, "aura")
	local front = Layer(ns.Cluster, "glass")
	behind:Hide()
	front:Hide()
	u.behind, u.front = behind, front
	u.spirals = { Sprite(behind, "auraSpiral", 0), Sprite(behind, "auraSpiral", 0) }
	u.corona = Sprite(behind, "auraCorona", 1)
	u.ring = Sprite(behind, "auraRing", 2)
	u.ignite = nil
	if ns.Art.Path("globeRim") then
		u.bloomLow = front:CreateTexture(nil, "ARTWORK", nil, 0)
		u.bloomTop = front:CreateTexture(nil, "ARTWORK", nil, 0)
		for i, tex in ipairs({ u.bloomLow, u.bloomTop }) do
			tex:SetTexture(ns.Art.Path("globeRim"))
			tex:SetBlendMode("ADD")
			tex:SetAllPoints()
			if i == 2 then tex:SetTexCoord(0, 1, 1, 0) end
			tex:SetAlpha(0)
		end
	end
	u.motes = {}
	for i = 1, SURGE_MOTES do
		local tex = Sprite(front, "mote", 1)
		if tex then u.motes[i] = tex end
	end
	u.frames = { behind, front }
	u.ok = u.spirals[1] ~= nil
	return u
end

local function AnimateSurge(g, u, now, dt)
	if not u.ok or not Ease(u, now, dt, false) then
		u.behind:Hide()
		u.front:Hide()
		return false
	end
	u.behind:Show()
	u.front:Show()
	local opt = Opt()
	local e = Smoothstep(u.level)
	local intensity = tonumber(opt.intensity) or 1
	local base = e * intensity * Strength(u) * Gutter(u, now, dt)
	local size = g.size * SCALE * u.scale
	local sat, hot = u.sat, u.hotColor
	local turn = u.rank % 2 == 0 and -1 or 1 -- stacked surges turn against each other
	local rush = 0
	if u.ignite and now - u.ignite < IGNITE then rush = 1 - (now - u.ignite) / IGNITE end
	-- Two spiral phases, each shrinking toward the rim while it turns, crossfading.
	for i, tex in ipairs(u.spirals) do
		local p = (now / 1.6 + (i - 1) * 0.5) % 1
		Size(tex, size * (1.35 - 0.35 * p))
		Spin(tex, turn * now * 0.9 - (i - 1) * 3 - u.rank)
		Paint(tex, sat, 0.75 * math.sin(p * math.pi) * base * (1 + rush))
	end
	Size(u.corona, size * 0.95)
	Paint(u.corona, sat, 0.5 * base)
	local p = (now / 1.1) % 1
	Size(u.ring, size * (1.5 - 0.5 * p))
	Paint(u.ring, hot, 0.6 * p * base)
	local breath = 0.8 + 0.2 * math.sin(now * 2 * math.pi / 1.6)
	if u.bloomLow then
		u.bloomLow:SetVertexColor(hot[1], hot[2], hot[3])
		u.bloomLow:SetAlpha(math.min(1, 0.45 * breath * base * (1 + rush)))
		u.bloomTop:SetVertexColor(hot[1], hot[2], hot[3])
		u.bloomTop:SetAlpha(math.min(1, 0.35 * breath * base * (1 + rush)))
	end
	-- Motes spiral in from beyond the rim and fade as they reach the middle.
	local r = g.size / 2
	for i, tex in ipairs(u.motes) do
		local q = (now * 0.7 + i / SURGE_MOTES) % 1
		local angle = i * 2.39 + u.rank + q * 2.2 * -turn
		local dist = r * 2 * (1 - 0.55 * q) * 0.9
		tex:ClearAllPoints()
		tex:SetPoint("CENTER", u.front, "CENTER", math.cos(angle) * dist, math.sin(angle) * dist)
		Size(tex, r * (0.2 + 0.12 * (1 - q)))
		Paint(tex, hot, math.sin(q * math.pi) * 0.9 * base)
	end
	return true
end

---------------------------------------------------------------------------
-- Flares: one-off bursts, a few at a time per globe.

local function BuildFlare(g)
	local f = { started = nil }
	local behind = Layer(ns.Cluster, "aura")
	local front = Layer(ns.Cluster, "glass")
	behind:Hide()
	front:Hide()
	f.behind, f.front = behind, front
	f.corona = Sprite(behind, "auraCorona", 0)
	f.ring = Sprite(behind, "auraRing", 1)
	f.ringHot = Sprite(behind, "auraRing", 2)
	if ns.Art.Path("globeRim") then
		f.bloomLow = front:CreateTexture(nil, "ARTWORK")
		f.bloomTop = front:CreateTexture(nil, "ARTWORK")
		for i, tex in ipairs({ f.bloomLow, f.bloomTop }) do
			tex:SetTexture(ns.Art.Path("globeRim"))
			tex:SetBlendMode("ADD")
			tex:SetAllPoints()
			if i == 2 then tex:SetTexCoord(0, 1, 1, 0) end
			tex:SetAlpha(0)
		end
	end
	f.frames = { behind, front }
	f.ok = f.ring ~= nil
	return f
end

local function AnimateFlare(g, f, now)
	if not f.ok or not f.started or now - f.started >= FLARE then
		f.behind:Hide()
		f.front:Hide()
		f.started = nil
		return false
	end
	f.behind:Show()
	f.front:Show()
	local t = (now - f.started) / FLARE
	local intensity = tonumber(Opt().intensity) or 1
	local size = g.size * SCALE
	local tint = TINTS[f.tint] or TINTS.holy
	local sat, hot = tint.sat, tint.hot
	local ringScale, glow, bloom
	if f.dir == "in" then
		-- Drawn in: the ring closes on the rim, the glass fills with light as it arrives.
		ringScale = 1.7 - 0.7 * Out(t)
		glow = math.sin(t * math.pi)
		bloom = Smoothstep(t * 1.6) * (1 - t) ^ 0.8 * 1.4
	else
		-- Out: the ring leaves the rim, the glass flashes first and fades.
		ringScale = 1 + 0.7 * Out(t)
		glow = (1 - t) ^ 2
		bloom = (1 - t) ^ 2 * 1.2
	end
	Size(f.corona, size * (0.95 + 0.1 * glow))
	Paint(f.corona, sat, 0.9 * glow * intensity)
	Size(f.ring, size * ringScale)
	Paint(f.ring, sat, 1.1 * math.sin(math.min(1, t * 1.2) * math.pi) * intensity)
	Size(f.ringHot, size * ringScale * 0.99)
	Paint(f.ringHot, hot, 0.7 * math.sin(math.min(1, t * 1.2) * math.pi) * intensity)
	if f.bloomLow then
		f.bloomLow:SetVertexColor(hot[1], hot[2], hot[3])
		f.bloomLow:SetAlpha(math.min(1, 0.6 * bloom * intensity))
		f.bloomTop:SetVertexColor(hot[1], hot[2], hot[3])
		f.bloomTop:SetAlpha(math.min(1, 0.5 * bloom * intensity))
	end
	return true
end

---------------------------------------------------------------------------
-- Globes and their layout.

local function LevelOf(kind)
	local base = ns.Cluster:GetFrameLevel()
	if kind == "aura" then return base + ns.LEVEL.aura end
	if kind == "glass" then return base + ns.LEVEL.glass end
	return base + ns.LEVEL.console + 1 -- shards fly over the console art
end

-- Where an effect's globe is: health, or the resource globe for power, and for mana while it
-- holds mana (or the split globe's mana half; anything while testing).
local function GlobeFor(kind)
	if kind == "health" then return globes.health end
	if kind == "power" then return globes.resource end
	if ns.Watch.Testing and ns.Watch.Testing() then return globes.resource end
	local powerType = UnitPowerType("player")
	if powerType == MANA or (ns.Globes.IsSplit and ns.Globes.IsSplit()) then
		return globes.resource
	end
end

local function Place(frame, g, size)
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", g.frame, "CENTER")
	frame:SetSize(size, size)
end

function ns.GlobeAura.Layout()
	if not ns.Cluster then return end
	for _, g in pairs(globes) do
		g.size = g.frame:GetWidth()
		local big = g.size * SCALE
		for _, r in ipairs(g.looks.radiate) do
			Place(r.frame, g, big)
			r.frame:SetFrameLevel(LevelOf("aura"))
			r.catchFrame:ClearAllPoints()
			r.catchFrame:SetAllPoints(g.frame)
			r.catchFrame:SetFrameLevel(LevelOf("glass"))
		end
		for _, sh in ipairs(g.looks.shell) do
			Place(sh.bar, g, big)
			sh.bar:SetFrameLevel(LevelOf("aura"))
			sh.clip:SetFrameLevel(LevelOf("aura"))
			for name, frame in pairs(sh.levelFrames) do
				if name == "shatterBehind" or name == "shards" then Place(frame, g, big) end
				frame:SetFrameLevel(LevelOf(name == "front" and "glass" or name == "shards" and "shards" or "aura"))
			end
		end
		for _, u in ipairs(g.looks.surge) do
			Place(u.behind, g, big)
			u.behind:SetFrameLevel(LevelOf("aura"))
			-- Surge motes start out beyond the glass, so their layer is the big square too.
			Place(u.front, g, big)
			u.front:SetFrameLevel(LevelOf("glass"))
			if u.bloomLow then
				for _, tex in ipairs({ u.bloomLow, u.bloomTop }) do
					tex:ClearAllPoints()
					tex:SetAllPoints(g.frame)
				end
			end
		end
		for _, f in ipairs(g.flares) do
			Place(f.behind, g, big)
			f.behind:SetFrameLevel(LevelOf("aura"))
			f.front:ClearAllPoints()
			f.front:SetAllPoints(g.frame)
			f.front:SetFrameLevel(LevelOf("glass"))
		end
	end
end

---------------------------------------------------------------------------
-- Which effect each look on each globe shows, and the moment it changes.

local function Enabled(effect)
	local opt = Opt()
	return opt.enabled and opt.effects[effect.key]
end

-- The effects one look on one globe shows: up, enabled, strongest first, at most STACK.
local function Choose(g, look)
	local list = {}
	local knownShield = false
	for _, effect in ipairs(ns.Watch.EFFECTS) do
		if #list >= STACK then break end
		if effect.look == look and Enabled(effect) and GlobeFor(effect.globe) == g then
			local st = ns.Watch.State(effect.key)
			-- The shield from anyone follows the same absorb as a known shield: one is enough.
			local redundant = effect.kind == "absorb" and knownShield
			if st and st.up and not redundant then
				list[#list + 1] = { effect = effect, st = st }
				if effect.absorb then knownShield = true end
			end
		end
	end
	return list
end

local function Wake()
	if not driver then return end
	driver:SetScript("OnUpdate", ns.GlobeAura.Step)
end

local function Shatter(inst, was, now)
	local tint = TINTS[was.tint] or TINTS.holy
	inst.shatter, inst.shatterSeed = now, math.floor(now * 7) % 97
	inst.shatterSat, inst.shatterHot = tint.sat, tint.hot
	inst.level = 0
end

-- effect, st: what the instance shows now (nil: nothing). reason: why it changed.
local function Show(inst, effect, st, reason)
	local now = GetTime()
	-- A shield that broke shatters, whatever (if anything) takes its place.
	if inst.look == "shell" and reason == "broken" and inst.effect and inst.effect ~= effect then
		Shatter(inst, inst.effect, now)
	end
	if effect then
		local tint = TINTS[effect.tint] or TINTS.holy
		inst.satTo, inst.hotTo = tint.sat, tint.hot
		if inst.effect ~= effect then
			if inst.level <= 0.01 then
				-- From dark the colour starts where it ends.
				inst.sat = { unpack(tint.sat) }
				inst.hotColor = { unpack(tint.hot) }
			end
			inst.effect = effect
			inst.litAt = now
			if reason == "cast" or reason == "refreshed" then inst.ignite = now end
		elseif reason == "refreshed" then
			inst.rekindle = now
			inst.litAt = now
			if inst.look ~= "radiate" then inst.ignite = now end
		end
		inst.st = st
		inst.target = 1
		inst.release = nil
		inst.lastEffect = effect
	elseif inst.effect then
		inst.effect, inst.target = nil, 0
		inst.fade = FADE[reason] or 0.5
		-- Judged away, or a storm's charges spent: the light bursts outward as it goes.
		if inst.look == "radiate" and (reason == "consumed" or reason == "spent") then inst.release = now end
	end
	if inst.look == "shell" then FeedGate(inst) end
	Wake()
end

-- Hand one look's effects on one globe to its instances. changed: the effect key the reason
-- belongs to (nil: nothing happened to any one effect; whatever is new just lights).
local function Refresh(g, look, reason, changed)
	local insts = g.looks[look]
	local list = Choose(g, look)
	local rankOf = {}
	for rank, item in ipairs(list) do rankOf[item.effect] = rank end
	-- Let go of what is no longer shown (its own ending, or pushed out by stronger ones).
	for _, inst in ipairs(insts) do
		if inst.effect and not rankOf[inst.effect] then
			Show(inst, nil, nil, changed == inst.effect.key and reason or "gone")
		end
	end
	for rank, item in ipairs(list) do
		local effect, st = item.effect, item.st
		local inst
		for _, candidate in ipairs(insts) do
			if candidate.effect == effect then inst = candidate end
		end
		local scale = 1 + RANK_SCALE[look] * (rank - 1)
		if inst then
			if changed == effect.key then Show(inst, effect, st, reason) end
		else
			-- A free instance: a dark one if there is one, else the dimmest still fading out.
			for _, candidate in ipairs(insts) do
				if not candidate.effect and (not inst or candidate.level < inst.level) then inst = candidate end
			end
			if inst then
				if inst.level <= 0.01 then inst.scale = scale end
				Show(inst, effect, st, changed == effect.key and reason or "reading")
			end
		end
		if inst then
			inst.rank, inst.scaleTo = rank - 1, scale
		end
	end
end

local function Evaluate(reason)
	for _, g in pairs(globes) do
		for _, look in ipairs(LOOKS) do
			Refresh(g, look, reason)
		end
	end
end

local function PlayFlare(part)
	local g = GlobeFor(part.globe)
	if not g then return end
	local slot
	for _, f in ipairs(g.flares) do
		if not f.started then slot = f break end
	end
	-- All busy: the oldest makes way.
	if not slot then
		slot = g.flares[1]
		for _, f in ipairs(g.flares) do
			if f.started < slot.started then slot = f end
		end
	end
	slot.started, slot.tint, slot.dir = GetTime(), part.tint, part.dir
	Wake()
end

---------------------------------------------------------------------------
-- Preview: a showcase played through test mode, so it runs the same path as real casts.

local SHOWCASE = {
	{ 0.0, "lightning shield" }, { 0.6, "innervate" }, { 2.2, "power word: shield" }, { 4.4, "hit" },
	{ 6.5, "break" }, { 8.0, "life tap" }, { 9.0, "arcane power" }, { 10.5, "divine shield" },
	{ 12.0, "spend" }, { 13.0, "fade" }, { 19.5, "clear" },
}
local SHOWCASE_LOOP = 21

local function PreviewStep(now)
	local t = now - preview.start
	local cycle = math.floor(t / SHOWCASE_LOOP)
	t = t - cycle * SHOWCASE_LOOP
	for i, step in ipairs(SHOWCASE) do
		local key = cycle * 100 + i
		if t >= step[1] and not preview.done[key] then
			preview.done[key] = true
			if step[2] == "hit" then
				ns.GlobeAura.Hit()
			else
				ns.Watch.Test(step[2])
			end
		end
	end
end

function ns.GlobeAura.SetPreview(on)
	if on then
		ns.Watch.SetTest(true)
		ns.Watch.Test("clear")
		preview = { start = GetTime(), done = {} }
		Wake()
	elseif preview then
		preview = nil
		ns.Watch.SetTest(false)
	end
	ns.GlobeAura.preview = preview ~= nil
end

-- Test mode (Watch.lua) going off ends the showcase too.
function ns.GlobeAura.OnTest(on)
	if not on and preview then
		preview = nil
		ns.GlobeAura.preview = false
	end
	Evaluate("reading")
end

-- The shell takes a hit: a ripple runs out from the blow and the crystal flares. From
-- UNIT_ABSORB_AMOUNT_CHANGED (or the showcase and test mode). False if no shield is up.
function ns.GlobeAura.Hit()
	local any = false
	local angle = math.rad(30 + 120 * Hash(GetTime() * 3.7))
	for _, g in pairs(globes) do
		for _, sh in ipairs(g.looks.shell) do
			if sh.effect then
				sh.hit, sh.hitAngle = GetTime(), angle
				any = true
			end
			FeedGate(sh)
		end
	end
	Wake()
	return any
end

-- What each look on each globe shows: { health = { radiate = { key, level }, ... }, resource = ... }.
function ns.GlobeAura.Inspect()
	local out = {}
	for name, g in pairs(globes) do
		out[name] = {}
		for _, look in ipairs(LOOKS) do
			-- The first lit instance (the strongest), plus every lit key in rank order.
			local first, keys, shatter = nil, {}, nil
			for _, inst in ipairs(g.looks[look]) do
				if inst.effect then keys[inst.rank + 1] = inst.effect.key end
				if inst.shatter then shatter = inst.shatter end
			end
			for _, inst in ipairs(g.looks[look]) do
				if inst.effect and inst.rank == 0 then first = inst end
			end
			out[name][look] = { key = first and first.effect.key, level = first and first.level or 0, shatter = shatter, keys = keys,
				calm = first and first.calm or 0 }
		end
		local flares = 0
		for _, f in ipairs(g.flares) do if f.started then flares = flares + 1 end end
		out[name].flares = flares
	end
	return out
end

local last
function ns.GlobeAura.Step()
	local now = GetTime()
	local dt = last and math.max(0, math.min(0.1, now - last)) or 0
	last = now
	if preview then PreviewStep(now) end
	local busy = preview ~= nil
	for _, g in pairs(globes) do
		for _, inst in ipairs(g.looks.radiate) do
			if AnimateRadiate(g, inst, now, dt) then busy = true end
		end
		for _, inst in ipairs(g.looks.shell) do
			if AnimateShell(g, inst, now, dt) then busy = true end
		end
		for _, inst in ipairs(g.looks.surge) do
			if AnimateSurge(g, inst, now, dt) then busy = true end
		end
		for _, f in ipairs(g.flares) do
			if AnimateFlare(g, f, now) then busy = true end
		end
	end
	if not busy then
		last = nil
		driver:SetScript("OnUpdate", nil)
	end
end

function ns.GlobeAura.ApplySettings()
	if not driver then return end
	Evaluate(nil)
	Wake()
end

local function BuildGlobe(frame)
	local g = { frame = frame, size = frame:GetWidth() }
	g.looks = { radiate = {}, shell = {}, surge = {} }
	for i = 1, STACK do
		g.looks.radiate[i] = BuildRadiate(g)
		g.looks.shell[i] = BuildShell(g)
		g.looks.surge[i] = BuildSurge(g)
	end
	g.flares = { BuildFlare(g), BuildFlare(g), BuildFlare(g) }
	return g
end

function ns.GlobeAura.Init()
	if not ns.HealthGlobe or not ns.ResourceGlobe or not ns.Watch or not ns.Watch.OnChange then return end
	globes.health = BuildGlobe(ns.HealthGlobe)
	globes.resource = BuildGlobe(ns.ResourceGlobe)
	ns.GlobeAura.Layout()
	driver = CreateFrame("Frame", nil, ns.Cluster)
	for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "UPDATE_SHAPESHIFT_FORM" }) do
		pcall(driver.RegisterEvent, driver, event)
	end
	pcall(driver.RegisterUnitEvent, driver, "UNIT_DISPLAYPOWER", "player")
	pcall(driver.RegisterUnitEvent, driver, "UNIT_ABSORB_AMOUNT_CHANGED", "player")
	driver:SetScript("OnEvent", function(_, event)
		if event == "UNIT_ABSORB_AMOUNT_CHANGED" then
			ns.GlobeAura.Hit()
		else
			Evaluate("reading")
		end
	end)
	-- Size follows the globes (console scale, layout).
	for _, globe in ipairs({ ns.HealthGlobe, ns.ResourceGlobe }) do
		globe:HookScript("OnSizeChanged", ns.GlobeAura.Layout)
	end
	ns.Watch.OnChange(function(key, _, reason)
		local effect = ns.Watch.Effect(key)
		if not effect then return end
		if reason == "flare" then
			if Enabled(effect) then
				for _, part in ipairs(effect.flare or {}) do PlayFlare(part) end
			end
			return
		end
		local g = GlobeFor(effect.globe)
		if g and g.looks[effect.look] then Refresh(g, effect.look, reason, key) end
	end)
	Evaluate("reading")
end
