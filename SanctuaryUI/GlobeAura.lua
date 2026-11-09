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
--              Rendered (the default, STORM): one looping flipbook of branching arcs just
--              outside the console's ring and over the top of the glass, and a discharge that
--              flings bolts off the whole rim; settled, a short run of it now and then
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
--     looks    (WatchEffects.lua shell, or the options) besides the Crystal shell, each one flipbook
--              on the glass with its own hit: aegis, rime, hex ward, bulwark (SHIELD_LOOKS)
--     breaks   (shellBreak, or the options) besides the Shatter, each one flipbook over the console:
--              shockwave, dissolve, crumble, melt (SHIELD_BREAKS). Any break goes with any look
--     Damage shields hang on the game's absorb amount (Watch.AbsorbMode "live"): drawn inside
--     a clip frame whose top rides an invisible status bar fed the hidden amount, clamped to
--     0..1, so the shell shows exactly while any absorb holds and is gone the moment it breaks.
--
--   surge    power entering the globe, in one of four styles (each skill has a default in
--            WatchEffects.lua, and the options can set any skill to any look; LookOf decides):
--     pour     a column of light falling from the ring into the liquid, splashing on the surface
--              and sending shafts down through it. Calms after a few seconds on long effects
--     inhale   rays running inward behind the globe, streaks rushing in and flashing on the glass
--     upwell   plumes rising through the liquid, the surface lit from under
--     swirl    the rest of this list
--     Pour and upwell ride the level: drawn inside the liquid's clip, or anchored to its fill
--     guide, so hidden health and mana still work and no value is ever read. Rendered as
--     flipbooks crossfaded on their colour (Liquid.lua's rule: the alpha stays the strength);
--     what moves fast is sprites moved every frame, so it can't ghost.
--     spiral   arms of light curling in, shrinking toward the rim in two crossfading phases
--     ring     a ring closing in on the rim, again and again
--     weight   the spiral, its glow and ring sit under a fixed mask, full over the top and
--              fading down the sides: the console hides one side of a globe and the gargoyle
--              or angel the other low corner, and an even ring would show as a lopsided wedge
--     bloom    the glass lit from inside, and motes spiralling in
--     Healing looks (surge styles too; the options list them with the rest):
--     vines    two vines climbing the glass from the sides as the buff runs, meeting at the crown
--     halo     a ring of light over the crown, its back arc behind the glass and its front on it
--     bloom    (leaves) glowing leaves tumbling up off the rim
--     veil     aurora curtains rising off the top of the rim
--     rain     drops falling through the glass and rippling on the surface
--     pulse    a wave of light rising through the liquid each tick, the surface flashing to it
--     embers   slow sparks rising from the bottom of the glass, with their trails
--     Vines and pulse time themselves from your own cast and the buff's length and tick period
--     (the state's castAt), restarting when it is recast; with no cast to go on (someone else's
--     buff, up since before a reload) vines are fully grown and pulse keeps a plain cadence.
--
--   flare    a one-off burst (Life Tap, potions): a ring and a flash, out from the globe or
--            in to it. An effect's "in" parts can instead play a heal (LookOf's second value):
--     mend        a dome of light swelling off the surface, sparks lifting from it
--     benediction a short beam striking the surface, a ring spreading on it and one off the rim
--     mound       (shown as Surge) the liquid heaving up over the surface and slumping back
--     All three ride the fill guide, so nothing reads a level.
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
-- The rendered shield break: one-shot flipbooks stepped frame by frame (a blend would double up
-- fast shards). White art, the luminance in the alpha, drawn ADD and tinted here. size: of the
-- globe's diameter. The hit's blow is painted upper left; texcoords mirror it toward the blow.
local BREAK = {
	shatter = { slot = "shellShatter", frames = 25, cols = 5, cell = 409, sheet = 2048, size = 2.1 },
	hit = { slot = "shellHit", frames = 16, cols = 4, cell = 256, sheet = 1024, size = 1.09 },
}
local BREAK_WARM = 2.5 -- seconds the sheets are kept drawing at login, so the first break doesn't hitch

-- Shield looks besides the Crystal shell and breaks besides the Shatter (tools/blender/
-- globe_shields*.py, packed by rendered_shields in tools/build_hud_art.py). White art, the
-- luminance in the alpha, drawn ADD and tinted here. A look: an idle loop crossfaded like the
-- surge sheets (the colour weighted, the alpha the strength) and a stepped hit; both sized
-- SHIELD_SIZE, gated with the shell. tk: where its colour sits between the tint's two. idle, halo:
-- gains, graded for how long these stay up (globe_shields_compare.py OPTIONS). The hits' blow is
-- painted upper right; texcoords mirror it toward the blow.
local SHIELD_SIZE = 1.08
local SHIELD_FORM = 0.35 -- seconds a look takes to swell into place
local SHIELD_HIT_TK = 0.75 -- the hit's colour, between the tint's two
local SHIELD_BREAK_SIZE = 2.1
local SHIELD_LOOKS = {
	aegis = { tk = 0.55, idle = 0.72, halo = 0.42,
		loop = { slot = "shieldAegis", w = 2048, h = 2048, cw = 256, ch = 256, cols = 8, frames = 64, seconds = 8, row = 0 },
		hit = { slot = "shieldAegisHit", frames = 16, cols = 4, cell = 256, sheet = 1024 } },
	rime = { tk = 0.5, idle = 1.0, halo = 0.18,
		loop = { slot = "shieldRime", w = 2048, h = 1024, cw = 256, ch = 256, cols = 8, frames = 32, seconds = 5, row = 0 },
		hit = { slot = "shieldRimeHit", frames = 16, cols = 4, cell = 256, sheet = 1024 } },
	hex = { tk = 0.45, idle = 1.0, halo = 0,
		loop = { slot = "shieldHex", w = 2048, h = 1024, cw = 256, ch = 256, cols = 8, frames = 32, seconds = 6, row = 0 },
		hit = { slot = "shieldHexHit", frames = 16, cols = 4, cell = 256, sheet = 1024 } },
	bulwark = { tk = 0.6, idle = 0.8, halo = 0,
		loop = { slot = "shieldBulwark", w = 2048, h = 1024, cw = 256, ch = 256, cols = 8, frames = 32, seconds = 5, row = 0 },
		hit = { slot = "shieldBulwarkHit", frames = 16, cols = 4, cell = 256, sheet = 1024 } },
}
-- Breaks fly free of the gate, over the console: one-shot flipbooks stepped frame by frame, with
-- no blending. tk and gain: its colour and strength. Named after their sheets.
local SHIELD_BREAKS = {
	dissolve = { slot = "shieldDissolve", frames = 25, cols = 5, cell = 409, sheet = 2048, seconds = 1.3, gain = 1.0, tk = 0.5 },
	melt = { slot = "shieldMelt", frames = 25, cols = 5, cell = 409, sheet = 2048, seconds = 1.5, gain = 1.2, tk = 0.5 },
	shockwave = { slot = "shieldShockwave", frames = 16, cols = 4, cell = 256, sheet = 1024, seconds = 0.7, gain = 1.0, tk = 0.55 },
	crumble = { slot = "shieldCrumble", frames = 25, cols = 5, cell = 409, sheet = 2048, seconds = 1.2, gain = 1.05, tk = 0.6 },
}
local SHIELD_SLOTS = {}
for name, look in pairs(SHIELD_LOOKS) do SHIELD_SLOTS[name] = { look.loop.slot, look.hit.slot } end
for name, spec in pairs(SHIELD_BREAKS) do SHIELD_SLOTS[name] = { spec.slot } end

-- The surge styles' flipbooks. White art, the luminance in the alpha, ADD. row: where this
-- layer starts on its sheet. A style's other pieces are sprites. Sized for the 180 px globe.
local SURGE_ART = {
	inhaleRays = { slot = "surgeInhaleRays", w = 2048, h = 1024, cw = 256, ch = 256, cols = 8, frames = 32, seconds = 3.6, row = 0 },
	pourCol = { slot = "surgePourColumn", w = 2048, h = 1024, cw = 128, ch = 256, cols = 16, frames = 32, seconds = 3, row = 0 },
	pourGlow = { slot = "surgePourColumn", w = 2048, h = 1024, cw = 128, ch = 256, cols = 16, frames = 32, seconds = 3, row = 2 },
	pourUnder = { slot = "surgePourUnder", w = 2048, h = 512, cw = 256, ch = 128, cols = 8, frames = 32, seconds = 3, row = 0 },
	upwellBody = { slot = "surgeUpwellBody", w = 2048, h = 1024, cw = 256, ch = 256, cols = 8, frames = 32, seconds = 3, row = 0 },
	upwellCore = { slot = "surgeUpwellCore", w = 2048, h = 1024, cw = 256, ch = 256, cols = 8, frames = 32, seconds = 3, row = 0 },
}
local STYLE_SLOTS = {
	inhale = { "surgeInhaleRays", "surgeStreak" },
	pour = { "surgePourColumn", "surgePourUnder" },
	upwell = { "surgeUpwellBody", "surgeUpwellCore" },
}
-- Healing looks and one-off heals: flipbooks here, single sheets by slot name below.
local HEAL_ART = {
	vines = { slot = "healVines", w = 1024, h = 1024, cw = 256, ch = 256, cols = 4, frames = 16, row = 0 },
	leaf = { slot = "healLeaf", w = 512, h = 512, cw = 128, ch = 128, cols = 4, frames = 16, row = 0 },
	veil = { slot = "healVeil", w = 2048, h = 512, cw = 256, ch = 128, cols = 8, frames = 32, seconds = 7.5, row = 0 },
	moundBody = { slot = "healMound", w = 2048, h = 512, cw = 256, ch = 128, cols = 8, frames = 16, row = 0 },
	moundEdge = { slot = "healMound", w = 2048, h = 512, cw = 256, ch = 128, cols = 8, frames = 16, row = 2 },
}
STYLE_SLOTS.vines = { "healVines" }
STYLE_SLOTS.halo = { "healHalo" }
STYLE_SLOTS.bloom = { "healLeaf" }
STYLE_SLOTS.veil = { "healVeil" }
STYLE_SLOTS.rain = { "healRings", "healDrop" }
STYLE_SLOTS.pulse = { "healRings", "healDome" }
STYLE_SLOTS.embers = { "healDrop" }
-- The one-off heals; if a sheet won't load the skill plays the plain burst.
local HEAL_SLOTS = { mend = { "healDome" }, benediction = { "healBeam", "healRings" }, mound = { "healMound" } }
local HEAL_SECONDS = { mend = 1.25, benediction = 1.15, mound = 1.15 }
local RIDES_LEVEL = { pour = true, upwell = true, rain = true, pulse = true }
local KICKS_POOL = { pour = true, upwell = true } -- lighting one sets the liquid rocking
local NEW_STYLE = { vines = true, halo = true, bloom = true, veil = true, rain = true, pulse = true, embers = true }
local STREAKS = 24 -- inhale: streaks rushing in
local STREAK_CYCLE = 3 -- seconds for one
local STREAK_SPAN = 0.78 -- of the sprite's height, the streak's length in the art
local DROPS = 14 -- pour: droplets thrown up where it lands
local UPWELL_MOTES = 10
local RANK_WEIGHT = { 1, 0.6, 0.4 } -- several surges of a style on one globe: the strongest leads
local RANK_WIDTH = { 1, 0.75, 0.55 } -- and further columns pour thinner down the same line
local SETTLE_FROM, SETTLE_OVER = 4, 2 -- long effects: seconds until a pour starts to calm, and how long it takes
local SETTLE_LENGTH = 15 -- of at least this many seconds

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

-- Point a flipbook sprite at its frame (0-based). A half-texel inset keeps out the next cell.
local function BreakCell(tex, spec, i, flipU, flipV)
	local row = math.floor(i / spec.cols)
	local col = i - row * spec.cols
	local inset = 0.5 / spec.sheet
	local l, r = col * spec.cell / spec.sheet + inset, (col + 1) * spec.cell / spec.sheet - inset
	local t, b = row * spec.cell / spec.sheet + inset, (row + 1) * spec.cell / spec.sheet - inset
	if flipU then l, r = r, l end
	if flipV then t, b = b, t end
	tex:SetTexCoord(l, r, t, b)
end

-- What a skill shows: its look, and the surge style or flare heal it uses. Everything that
-- draws goes through here; what is about the game (is it a real shield) uses effect.look.
local function LookOf(effect)
	local looks = Opt().looks
	local choice = looks and looks[effect.key]
	if effect.look == "flare" then
		if choice == "burst" or (choice and HEAL_SLOTS[choice]) then return "flare", choice end
		return "flare", effect.heal or "burst"
	end
	if choice == "radiate" or choice == "shell" then return choice end
	if choice and SHIELD_LOOKS[choice] then return "shell", choice end
	if choice == "swirl" or (choice and STYLE_SLOTS[choice]) then return "surge", choice end
	if effect.look == "surge" then return "surge", effect.surge or "swirl" end
	if effect.look == "shell" then return "shell", effect.shell end
	return effect.look
end
ns.GlobeAura.LookOf = LookOf

-- How a shield breaks: the skill's choice, else its default, else the Shatter.
local function BreakOf(effect)
	local breaks = Opt().breaks
	local choice = breaks and breaks[effect.key]
	if choice == "shatter" or (choice and SHIELD_BREAKS[choice]) then return choice end
	return effect.shellBreak or "shatter"
end
ns.GlobeAura.BreakOf = BreakOf

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
	local strength = effect and effect.strength or 1
	if effect and effect.hot then
		strength = strength * (tonumber(Opt().hotStrength) or 1)
	end
	return strength
end

-- The colour an effect shows: its own, or the options' shared one for healing over time.
local function TintOf(effect)
	local chosen = effect.hot and Opt().hotTint
	return chosen and TINTS[chosen] and chosen or effect.tint
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

-- Rendered lightning: one flipbook of the whole picture round the globe, never turned, so an
-- arc can sit just outside the console's ring instead of under it. A loop, then a discharge.
-- Stepped with no blending: lightning strobes. The core takes the hot colour and the glow the
-- saturated one, behind the globe and, under the globe's mask, again on the glass. Nothing
-- crosses the loop's wrap, so it can be mirrored there to hide the repeat.
-- tools/blender/globe_storm.py draws it (build step rendered_storm checks these lists).
local STORM = {
	core = { slot = "stormFlipCore", cols = 7, cell = 292, sheet = 2048 },
	glow = { slot = "stormFlipGlow", cols = 7, cell = 146, sheet = 1024 },
	span = 1.75, -- the picture's width, of the globe's diameter
	loop = 38, fps = 18, discharge = 11, dischargeFps = 20,
	settleEvery = 1.15, settleRun = 4, settleStrength = 0.55, -- a flicker about every 1.6 s
	glass = { glow = 0.65, core = 0.75, dischargeGlow = 0.7, dischargeCore = 0.95 },
}
local STORM_BIRTHS = { 0, 1, 3, 6, 9, 10, 12, 14, 16, 17, 19, 21, 23, 24, 25, 28, 29, 31, 33, 36 } -- arcs start here
local STORM_STRIKES = { 2, 11, 18, 25, 30 } -- a bolt strikes: the whole glow lights for a blink
local stormStrikeAt = {}
for _, i in ipairs(STORM_STRIKES) do stormStrikeAt[i] = true end
local EnsureStorm -- builds an instance's flipbook; set once the frame levels are defined

local function BuildRadiate(g)
	local r = NewInstance("radiate")
	local frame = Layer(g.parent, "aura")
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
	local catch = Layer(g.parent, "glass")
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

-- Which picture a storm shows now: its cell, whether mirrored, and how strong. Nil: none now.
local function StormFrame(a, now, calm, releasing)
	if releasing then
		local i = math.floor((now - a.release) * STORM.dischargeFps)
		if i >= STORM.discharge then return nil end
		return STORM.loop + i, false, 1
	end
	-- Casting it: the same burst of bolts thrown off the rim as it lights.
	if a.ignite then
		local i = math.floor((now - a.ignite) * STORM.dischargeFps)
		if i >= 0 and i < STORM.discharge then return STORM.loop + i, false, 1 end
	end
	local gain = 1 - calm
	if gain > 0.02 then
		local f = now * STORM.fps
		local wraps = math.floor(f / STORM.loop)
		return math.floor(f - wraps * STORM.loop), Hash(wraps * 1.7 + a.rank * 3) > 0.5, gain
	end
	-- Settled: most of the time nothing, and now and then a short run of the loop.
	local t = now / STORM.settleEvery
	local cycle = math.floor(t)
	if Hash(cycle * 3.7 + a.rank) < 0.3 then return nil end
	local step = math.floor((t - cycle) * STORM.settleEvery * STORM.fps)
	if step >= STORM.settleRun then return nil end
	local start = STORM_BIRTHS[1 + math.floor(Hash(cycle * 11.3) * #STORM_BIRTHS)]
	return (start + step) % STORM.loop, Hash(cycle * 5.1) > 0.5, STORM.settleStrength
end

local function HideFlip(a)
	local s = a.storm
	if s and s.lit then
		s.lit, s.i = false, nil
		for _, tex in ipairs(s.all) do tex:SetAlpha(0) end
		s.front:Hide()
	end
end

local function AnimateStormFlip(g, a, s, now, base, releasing, sat, hot)
	local i, mirror, strength = StormFrame(a, now, a.calm or 0, releasing)
	if not i then
		HideFlip(a)
		return
	end
	if i ~= s.i or mirror ~= s.mirror then
		s.i, s.mirror = i, mirror
		BreakCell(s.glow, STORM.glow, i, mirror)
		BreakCell(s.core, STORM.core, i, mirror)
		BreakCell(s.frontGlow, STORM.glow, i, mirror)
		BreakCell(s.frontCore, STORM.core, i, mirror)
	end
	local size = g.size * STORM.span
	if s.size ~= size then
		s.size = size
		for _, tex in ipairs(s.all) do Size(tex, size) end
	end
	s.lit = true
	s.front:Show()
	-- A burst goes at full: the light has nearly faded by the end of a release, and has barely
	-- risen at the start of a cast.
	local charged = i >= STORM.loop
	local k = strength * (charged and (tonumber(Opt().intensity) or 1) * Strength(a) or base)
	Paint(s.glow, sat, k)
	Paint(s.core, hot, k)
	Paint(s.frontGlow, sat, (charged and STORM.glass.dischargeGlow or STORM.glass.glow) * k)
	Paint(s.frontCore, hot, (charged and STORM.glass.dischargeCore or STORM.glass.core) * k)
	a.strike = stormStrikeAt[i] and not charged and strength or 0
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
		HideFlip(a)
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
	local storm = effect and effect.storm and (base > 0 or releasing) and EnsureStorm(g, a)
	if storm then
		HideStorm(a)
		AnimateStormFlip(g, a, storm, now, base, releasing, sat, hot)
	else
		HideFlip(a)
		if effect and effect.storm and base > 0 then
			AnimateStorm(g, a, now, base, sat, hot)
		else
			HideStorm(a)
		end
	end
	return true
end

---------------------------------------------------------------------------
-- Shell.

local DrawShieldLook -- draws a look on its shell; set once the flipbook helpers are defined
local shieldArt = {} -- look or break -> whether its sheets loaded (ShieldArt); once only

local function BuildShell(g)
	local s = NewInstance("shell")
	-- The gate: everything but the shatter lives in a clip frame whose top follows the fill of
	-- an invisible 0..1 status bar. Fed the hidden absorb amount it is full while any absorb
	-- holds and empty at none; fed 1 it is always full.
	local bar = CreateFrame("StatusBar", nil, g.parent)
	bar:SetOrientation("VERTICAL")
	bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	bar:SetStatusBarColor(0, 0, 0, 0)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(1)
	bar:EnableMouse(false)
	s.bar = bar
	local clip = CreateFrame("Frame", nil, g.parent)
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
	local shatterBehind = Layer(g.parent, "aura")
	local shards = Layer(g.parent, "shards")
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

local function ShieldArt(name)
	if shieldArt[name] == nil then
		local ok = true
		for _, slot in ipairs(SHIELD_SLOTS[name]) do
			if not ns.Art.Require(slot) then ok = false end
		end
		if not ok and ns.Log then ns.Log("globe auras: " .. name .. " art failed to load, falling back") end
		shieldArt[name] = ok
	end
	return shieldArt[name]
end

-- What this shell draws: a look's name, or nil for the Crystal shell (its default, and the
-- fallback if a look's sheets won't load).
local function ActiveShieldLook(s)
	local effect = s.effect or s.lastEffect
	if not effect then return nil end
	local look, style = LookOf(effect)
	if look ~= "shell" or not SHIELD_LOOKS[style] or not ShieldArt(style) then return nil end
	return style
end

-- The rendered looks are graded at their own gains, so a skill's strength stays out of them;
-- the shared healing brightness still applies.
local function ShieldStrength(s)
	local effect = s.effect or s.lastEffect
	return effect and effect.hot and (tonumber(Opt().hotStrength) or 1) or 1
end

local function HideShieldLook(s)
	local r = s.drawnLook and s.shieldLooks[s.drawnLook]
	if r then
		r.idle.a:SetAlpha(0)
		r.idle.b:SetAlpha(0)
		r.hit:SetAlpha(0)
	end
	s.drawnLook = nil
end

local function ClearCrystal(s)
	for _, tex in ipairs({ s.rim, s.facets, s.sheen, s.ripple, s.rippleHot, s.impact, s.formRing }) do tex:SetAlpha(0) end
	if s.fx then s.fx.hit:SetAlpha(0) end
end

local function AnimateShell(g, s, now, dt)
	local shattering = s.shatter and now - s.shatter < (s.shatterSeconds or SHATTER)
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
	local shieldLook = ActiveShieldLook(s)
	s.style = shieldLook or "shell"
	if shieldLook then
		DrawShieldLook(g, s, shieldLook, now, e * intensity * ShieldStrength(s) * flicker, intensity, sat, hot, hit, hitT)
	else
		if s.drawnLook then HideShieldLook(s) end
		Size(s.halo, g.size * SCALE * 0.96 * s.scale)
		Paint(s.halo, sat, 0.7 * breath * base * (1 + 0.8 * hit))
		Size(s.rim, size * swell)
		Paint(s.rim, sat, base * (1 + 0.5 * form + hit))
		Size(s.facets, size * swell)
		Spin(s.facets, now * 0.03 + s.rank * 0.9)
		Paint(s.facets, hot, 0.65 * base * (0.85 + 0.15 * math.sin(now * 1.7)) * (1 + 1.5 * form + 2.5 * hit))
		if hitT and s.fx then
			-- Light running along the crystal's seams, mirrored toward the blow.
			local spec = BREAK.hit
			local i = math.min(spec.frames - 1, math.floor(hitT * spec.frames))
			BreakCell(s.fx.hit, spec, i, math.cos(s.hitAngle) > 0, math.sin(s.hitAngle) < 0)
			Size(s.fx.hit, g.size * spec.size * s.scale * swell)
			Paint(s.fx.hit, hot, 1.15 * intensity)
			Paint(s.ripple, sat, 0)
			Paint(s.rippleHot, hot, 0)
			Paint(s.impact, hot, 0)
		elseif hitT then
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
			if s.fx then Paint(s.fx.hit, hot, 0) end
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
	end

	-- Shatter: shards thrown off the upper half, tumbling and falling, a ring blown outward.
	local shown = shattering and true or false
	s.levelFrames.shatterBehind:SetShown(shown)
	s.levelFrames.shards:SetShown(shown)
	if shattering and s.breakFx then
		-- A chosen break: one flipbook of the dome coming apart, stepped; no ring of its own.
		local fx = s.breakFx
		local spec = fx.spec
		local t = (now - s.shatter) / spec.seconds
		BreakCell(fx.tex, spec, math.min(spec.frames - 1, math.floor(t * spec.frames)))
		Size(fx.tex, g.size * SHIELD_BREAK_SIZE)
		Paint(fx.tex, s.shatterMix, spec.gain * intensity)
	elseif shattering and s.fx then
		-- The dome you were looking at, cracking along its seams and flying apart; a dimmer ring.
		local t = (now - s.shatter) / SHATTER
		local spec = BREAK.shatter
		BreakCell(s.fx.shatter, spec, math.min(spec.frames - 1, math.floor(t * spec.frames)))
		Size(s.fx.shatter, g.size * spec.size)
		Paint(s.fx.shatter, s.shatterMix, intensity)
		local ringSize = g.size * SCALE * (1 + 0.5 * Out(t))
		Size(s.ring, ringSize)
		Paint(s.ring, s.shatterSat, 0.7 * (1 - t) ^ 1.5 * intensity)
		Size(s.ringHot, ringSize * 0.99)
		Paint(s.ringHot, s.shatterHot, 0.25 * (1 - t) ^ 1.5 * intensity)
	elseif shattering then
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

local function LevelOf(kind)
	local base = ns.Cluster:GetFrameLevel()
	if kind == "aura" then return base + ns.LEVEL.aura end
	if kind == "glass" then return base + ns.LEVEL.glass end
	return base + ns.LEVEL.console + 1 -- shards fly over the console art
end

-- Where an effect's globe is: health, or the resource globe for power, and for mana while it
-- holds mana (or the split globe's mana half; anything while testing).
local function ClipTo(tex, target)
	tex:ClearAllPoints()
	tex:SetAllPoints(target)
end

local function GlobeMask(frame, globe)
	local mask = frame:CreateMaskTexture()
	mask:SetTexture(ns.Art.Path("globeMask"), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(globe)
	return mask
end

-- Two textures of one flipbook layer, on one sublevel.
local function Pair(frame, spec, sublevel)
	return { a = Sprite(frame, spec.slot, sublevel), b = Sprite(frame, spec.slot, sublevel), spec = spec }
end

local function PairCall(p, method, ...)
	p.a[method](p.a, ...)
	p.b[method](p.b, ...)
end

local function Cell(tex, spec, i)
	local row = math.floor(i / spec.cols)
	local col = i - row * spec.cols
	row = row + spec.row
	local du, dv = 0.5 / spec.w, 0.5 / spec.h
	tex:SetTexCoord(col * spec.cw / spec.w + du, (col + 1) * spec.cw / spec.w - du,
		row * spec.ch / spec.h + dv, (row + 1) * spec.ch / spec.h - dv)
end

-- Draw a layer: the crossfade weights go in the colour (ADD, so that's the same as alpha), the
-- strength in the alpha, set last (one value on a texture, see Liquid.lua Flipbook).
local function DrawPair(p, clock, color, strength)
	local spec = p.spec
	local pos = (clock / spec.seconds) % 1 * spec.frames
	local i = math.floor(pos)
	local f = pos - i
	if i ~= p.i then
		p.i = i
		Cell(p.a, spec, i)
		Cell(p.b, spec, (i + 1) % spec.frames)
	end
	local r, g, b = color[1], color[2], color[3]
	p.a:SetVertexColor(r * (1 - f), g * (1 - f), b * (1 - f))
	p.b:SetVertexColor(r * f, g * f, b * f)
	local k = math.max(0, math.min(1, strength))
	p.a:SetAlpha(k)
	p.b:SetAlpha(k)
end

local function Mix(sat, hot, a, b)
	return { math.min(1, sat[1] * a + hot[1] * b), math.min(1, sat[2] * a + hot[2] * b), math.min(1, sat[3] * a + hot[3] * b) }
end

local function Stretch(tex, w, h)
	if tex then tex:SetSize(w, h) end
end

local BUILD = {}

function BUILD.inhale(g, u)
	local s = { parts = {}, sheets = {} }
	s.rays = Pair(u.behind, SURGE_ART.inhaleRays, 3)
	s.sheets[1] = s.rays
	local mask = u.weight
	if mask then PairCall(s.rays, "AddMaskTexture", mask) end
	s.parts[#s.parts + 1] = s.rays.a
	s.parts[#s.parts + 1] = s.rays.b
	s.front = GlobeMask(u.front, g.frame)
	s.streaks, s.flashes = {}, {}
	for k = 1, STREAKS do
		local tex = Sprite(u.behind, "surgeStreak", 4)
		if mask then tex:AddMaskTexture(mask) end
		local flash = Sprite(u.front, "mote", 2)
		flash:AddMaskTexture(s.front)
		s.streaks[k], s.flashes[k] = tex, flash
		s.parts[#s.parts + 1] = tex
		s.parts[#s.parts + 1] = flash
	end
	s.streakSheet = s.streaks
	return s
end

function BUILD.pour(g, u)
	local guide, inside = g.frame.pool:Anchors()
	local s = { parts = {}, sheets = {} }
	-- The column stops at the level: a clip frame whose bottom is the fill guide's top. Its own
	-- top is the globe's, under the console's ring, so it comes down from the ring.
	local clip = Layer(g.parent)
	if clip.SetClipsChildren then clip:SetClipsChildren(true) end
	clip:SetPoint("TOPLEFT", g.frame, "TOPLEFT")
	clip:SetPoint("BOTTOMRIGHT", guide, "TOPRIGHT")
	s.glow = Pair(clip, SURGE_ART.pourGlow, 0)
	s.col = Pair(clip, SURGE_ART.pourCol, 1)
	for _, p in ipairs({ s.glow, s.col }) do
		for _, tex in ipairs({ p.a, p.b }) do
			tex:ClearAllPoints()
			tex:SetPoint("TOP", g.frame, "TOP")
		end
	end
	-- In the liquid: shafts and rings hanging from the surface, clipped with the liquid.
	local liquid = Layer(inside)
	liquid:SetAllPoints(g.frame)
	local liquidMask = GlobeMask(liquid, g.frame)
	s.under = Pair(liquid, SURGE_ART.pourUnder, 0)
	PairCall(s.under, "AddMaskTexture", liquidMask)
	for _, tex in ipairs({ s.under.a, s.under.b }) do
		tex:ClearAllPoints()
	end
	-- Over the surface, riding it: the crown, the lit line, the droplets.
	local over = Layer(g.parent)
	over:SetAllPoints(g.frame)
	local mask = GlobeMask(over, g.frame)
	s.lit = Sprite(over, "mote", 0)
	s.crown = Sprite(over, "mote", 1)
	s.drops = {}
	for k = 1, DROPS do s.drops[k] = Sprite(over, "mote", 2) end
	for _, tex in ipairs({ s.lit, s.crown, unpack(s.drops) }) do tex:AddMaskTexture(mask) end
	s.guide = guide
	s.frames, s.glass, s.liquid = { clip, liquid, over }, { clip, over }, liquid
	s.sheets = { s.col, s.glow, s.under }
	return s
end

function BUILD.upwell(g, u)
	local guide, inside = g.frame.pool:Anchors()
	local s = { parts = {}, sheets = {} }
	local liquid = Layer(inside)
	liquid:SetAllPoints(g.frame)
	local mask = GlobeMask(liquid, g.frame)
	s.body = Pair(liquid, SURGE_ART.upwellBody, 0)
	s.core = Pair(liquid, SURGE_ART.upwellCore, 1)
	for _, p in ipairs({ s.body, s.core }) do
		PairCall(p, "AddMaskTexture", mask)
		ClipTo(p.a, g.frame)
		ClipTo(p.b, g.frame)
	end
	s.motes = {}
	for k = 1, UPWELL_MOTES do
		s.motes[k] = Sprite(liquid, "mote", 2)
		s.motes[k]:AddMaskTexture(mask)
	end
	local crest = Layer(g.parent)
	crest:SetAllPoints(g.frame)
	local crestMask = GlobeMask(crest, g.frame)
	s.crestS = Sprite(crest, "mote", 0)
	s.crestH = Sprite(crest, "mote", 1)
	s.crestS:AddMaskTexture(crestMask)
	s.crestH:AddMaskTexture(crestMask)
	for _, tex in ipairs({ s.crestS, s.crestH }) do
		tex:ClearAllPoints()
		tex:SetPoint("CENTER", guide, "TOP")
	end
	s.guide = guide
	s.frames, s.glass, s.liquid = { liquid, crest }, { crest }, liquid
	s.sheets = { s.body, s.core }
	return s
end

local styleArt = {} -- style -> whether its sheets loaded; once only

local function StyleArt(name)
	if styleArt[name] == nil then
		local ok = true
		for _, slot in ipairs(STYLE_SLOTS[name]) do
			if not ns.Art.Require(slot) then ok = false end
		end
		if not ok and ns.Log then ns.Log("globe auras: " .. name .. " art failed to load, using swirl") end
		styleArt[name] = ok
	end
	return styleArt[name]
end

-- Can this globe draw this style right now? Falling back is always to swirl. A split globe has
-- two levels side by side, so nothing can ride "the" level.
local function CanDraw(g, name)
	if name == "swirl" then return true end
	if not STYLE_SLOTS[name] or not StyleArt(name) then return false end
	if RIDES_LEVEL[name] then
		local pool = g.frame.pool
		if not (pool and pool.Anchors) then return false end
		if g.frame == ns.ResourceGlobe and ns.Globes.IsSplit and ns.Globes.IsSplit() then return false end
	end
	return true
end

local function ActiveStyle(g, u)
	local effect = u.effect or u.lastEffect
	if not effect then return u.style or "swirl" end
	local look, style = LookOf(effect)
	if look ~= "surge" then style = u.style or "swirl" end
	return CanDraw(g, style) and style or "swirl"
end

local function Reattach(s)
	for _, p in ipairs(s.sheets) do
		local path = ns.Art.Path(p.spec.slot)
		for _, tex in ipairs({ p.a, p.b }) do
			tex:SetTexture(path, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		end
		p.i = nil
	end
	if s.streakSheet then
		local path = ns.Art.Path("surgeStreak")
		for _, tex in ipairs(s.streakSheet) do tex:SetTexture(path, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE") end
	end
	for _, own in ipairs(s.bound or {}) do
		own[1]:SetTexture(ns.Art.Path(own[2]), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	end
	s.released = nil
end

local function Release(s)
	for _, p in ipairs(s.sheets) do
		p.a:SetTexture(nil)
		p.b:SetTexture(nil)
	end
	if s.streakSheet then
		for _, tex in ipairs(s.streakSheet) do tex:SetTexture(nil) end
	end
	for _, own in ipairs(s.bound or {}) do own[1]:SetTexture(nil) end
	s.released = true
end

-- One shield look's sprites on one shell instance, built the first time it shows.
local function EnsureShieldLook(s, name)
	s.shieldLooks = s.shieldLooks or {}
	local r = s.shieldLooks[name]
	if not r then
		local look = SHIELD_LOOKS[name]
		local idle = Pair(s.levelFrames.front, look.loop, 0)
		local hit = Sprite(s.levelFrames.front, look.hit.slot, 6)
		r = { idle = idle, hit = hit, sheets = { idle }, bound = { { hit, look.hit.slot } } }
		s.shieldLooks[name] = r
	elseif r.released then
		Reattach(r)
	end
	return r
end

-- One break's sprite on one shell instance; nil if its sheet won't load (the caller shatters).
local function EnsureShieldBreak(s, name)
	s.shieldBreaks = s.shieldBreaks or {}
	local b = s.shieldBreaks[name]
	if not b then
		local spec = SHIELD_BREAKS[name]
		local tex = Sprite(s.levelFrames.shards, spec.slot, 3)
		if not tex then return nil end
		b = { spec = spec, tex = tex, sheets = {}, bound = { { tex, spec.slot } } }
		s.shieldBreaks[name] = b
	elseif b.released then
		Reattach(b)
	end
	return b
end

local function Blend(into, sat, hot, k)
	for i = 1, 3 do into[i] = sat[i] + (hot[i] - sat[i]) * k end
end

-- The look: its loop, the halo behind the globe (the Crystal shell's sprite, at the look's own
-- gain), and a hit stepped and mirrored toward the blow. base: strength, for the idle and halo.
-- Painted as the crossfaded surge sheets are: colour with three arguments, the alpha last.
DrawShieldLook = function(g, s, name, now, base, intensity, sat, hot, hit, hitT)
	local look = SHIELD_LOOKS[name]
	local r = EnsureShieldLook(s, name)
	if s.drawnLook ~= name then
		if s.drawnLook then HideShieldLook(s) else ClearCrystal(s) end
		s.drawnLook = name
	end
	local form = 0
	if s.ignite and now - s.ignite < SHIELD_FORM then form = 1 - (now - s.ignite) / SHIELD_FORM end
	local swell = (1 - 0.05 * form ^ 2) * (1 - 0.015 * hit)
	local size = g.size * SHIELD_SIZE * s.scale
	Size(r.idle.a, size * swell)
	Size(r.idle.b, size * swell)
	s.lookColor = s.lookColor or {}
	Blend(s.lookColor, sat, hot, look.tk)
	DrawPair(r.idle, now, s.lookColor, look.idle * base * (1 + 0.35 * hit + 0.6 * form))
	Size(s.halo, g.size * SCALE * 0.96 * s.scale)
	Paint(s.halo, sat, look.halo * (0.9 + 0.1 * math.sin(now * 2 * math.pi / 3.2)) * base * (1 + 0.7 * hit))
	if hitT then
		local spec = look.hit
		local i = math.min(spec.frames - 1, math.floor(hitT * spec.frames))
		BreakCell(r.hit, spec, i, math.cos(s.hitAngle) < 0, math.sin(s.hitAngle) < 0)
		Size(r.hit, size)
		s.hitColor = s.hitColor or {}
		Blend(s.hitColor, sat, hot, SHIELD_HIT_TK)
		Paint(r.hit, s.hitColor, intensity)
	else
		Paint(r.hit, hot, 0)
	end
end

local function StyleLevels(s)
	for _, frame in ipairs(s.glass or {}) do frame:SetFrameLevel(LevelOf("glass")) end
end

local function EnsureStyle(g, u, name)
	u.styles = u.styles or {}
	local s = u.styles[name]
	if not s then
		s = BUILD[name](g, u)
		u.styles[name] = s
		StyleLevels(s)
	elseif s.released then
		Reattach(s)
	end
	return s
end

local function ShowStyle(g, u, name)
	if u.shownStyle == name then return end
	u.shownStyle = name
	for key, s in pairs(u.styles or {}) do
		local on = key == name
		for _, frame in ipairs(s.frames or {}) do frame:SetShown(on) end
		for _, tex in ipairs(s.parts) do tex:SetShown(on) end
	end
end

local function HideStyles(u)
	if not u.shownStyle then return end
	u.shownStyle = nil
	for _, s in pairs(u.styles or {}) do
		for _, frame in ipairs(s.frames or {}) do frame:Hide() end
		for _, tex in ipairs(s.parts) do tex:Hide() end
	end
end

-- Above the liquid's own layers, inside its clip; the pool's level can change with the layout.
local function FollowLiquid(g, s)
	if not s.liquid then return end
	local level = g.frame.pool.frame:GetFrameLevel() + 1
	if s.level ~= level then
		s.level = level
		s.liquid:SetFrameLevel(level)
	end
end

local DRAW = {}

function DRAW.inhale(g, u, s, now, base, sat, hot, rush)
	local size = g.size * SCALE * u.scale
	local k = base * (RANK_WEIGHT[u.rank + 1] or 0.4)
	local clock = now + u.rank * 1.3
	if s.size ~= size then
		s.size = size
		PairCall(s.rays, "SetSize", size * 1.02, size * 1.02)
	end
	DrawPair(s.rays, clock, sat, 1.15 * k * (1 + 0.5 * rush))
	-- Streaks falling in, quickening toward the glass; where each lands, a flash.
	local r = g.size / 2
	for i, tex in ipairs(s.streaks) do
		local lives = 1 + (i % 2)
		local q = (clock / STREAK_CYCLE * lives + Hash(i * 3.1)) % 1
		local a0 = math.rad(14 + 152 * Hash(i * 7.7))
		local curl = (Hash(i * 5.3) - 0.5) * 0.5
		local speed = 0.8 + 0.5 * Hash(i * 2.9)
		local travel = q / 0.88
		local flash = s.flashes[i]
		if travel < 1 then
			local function At(p)
				local d = 2.15 - 1.15 * p ^ 2.2
				local a = a0 + curl * (d - 1) ^ 2
				return math.cos(a) * d * r, math.sin(a) * d * r
			end
			local hx, hy = At(travel)
			local tx, ty = At(math.max(0, travel - 0.2 * speed))
			local dx, dy = tx - hx, ty - hy
			local length = math.max(1, math.sqrt(dx * dx + dy * dy))
			tex:ClearAllPoints()
			tex:SetPoint("CENTER", u.behind, "CENTER", (hx + tx) / 2, (hy + ty) / 2)
			Size(tex, length / STREAK_SPAN)
			Spin(tex, math.atan2(dy, dx) - math.pi / 2)
			Paint(tex, hot, math.min(1, travel / 0.25) * (0.65 + 0.35 * speed) * k * 1.2)
			flash:SetAlpha(0)
		else
			tex:SetAlpha(0)
			local x, y = math.cos(a0) * 0.97 * r, math.sin(a0) * 0.97 * r
			flash:ClearAllPoints()
			flash:SetPoint("CENTER", u.front, "CENTER", x, y)
			Size(flash, r * 0.55)
			Paint(flash, hot, math.exp(-(travel - 1) / 0.055) * 0.95 * k)
		end
	end
end

function DRAW.pour(g, u, s, now, base, sat, hot, rush, calm)
	local size = g.size
	local rank = u.rank
	local k = base * (RANK_WEIGHT[rank + 1] or 0.4)
	local clock = now + rank * 1.7
	if s.size ~= size or s.rank ~= rank then
		s.size, s.rank = size, rank
		local w = size * 0.5 * (RANK_WIDTH[rank + 1] or 0.55)
		PairCall(s.col, "SetSize", w, size)
		PairCall(s.glow, "SetSize", w, size)
		PairCall(s.under, "SetSize", size * 1.2, size * 0.6)
		for _, tex in ipairs({ s.under.a, s.under.b }) do
			tex:ClearAllPoints()
			tex:SetPoint("TOP", s.guide, "TOP", 0, size * 0.05)
		end
		s.lit:ClearAllPoints()
		s.lit:SetPoint("CENTER", s.guide, "TOP")
		Stretch(s.lit, size * 0.85, size * 0.07)
		s.crown:ClearAllPoints()
		s.crown:SetPoint("CENTER", s.guide, "TOP", 0, size * 0.04)
		Stretch(s.crown, size * 0.24, size * 0.2)
	end
	DrawPair(s.glow, clock, sat, 1.25 * k * (1 - 0.55 * calm))
	DrawPair(s.col, clock, hot, 1.2 * k * (1 - 0.5 * calm))
	DrawPair(s.under, clock, Mix(sat, hot, 0.8, 0.4), 1.05 * k * (1 - 0.65 * calm))
	Paint(s.lit, hot, 0.95 * k * (1 - 0.4 * calm))
	Paint(s.crown, hot, (0.75 + 0.25 * math.sin(clock * 6.283)) * 0.9 * k * (1 - 0.4 * calm))
	for i, tex in ipairs(s.drops) do
		local lives = 1 + (i % 2)
		local q = (clock / 3 * lives + Hash(i * 4.3)) % 1
		local vx = (Hash(i * 6.1) - 0.5) * 0.9
		local vy = 0.32 + 0.5 * Hash(i * 2.7)
		local x, y = vx * q * 0.75, vy * q - 0.83 * q * q
		if y < -0.005 or calm > 0.98 then
			tex:SetAlpha(0)
		else
			tex:ClearAllPoints()
			tex:SetPoint("CENTER", s.guide, "TOP", x * size, y * size)
			Size(tex, size * (0.035 + 0.025 * Hash(i * 9.1)))
			Paint(tex, hot, (1 - q) ^ 0.7 * 0.95 * k * (1 + rush) * (1 - calm))
		end
	end
end

function DRAW.upwell(g, u, s, now, base, sat, hot, rush)
	local size = g.size
	local rank = u.rank
	local k = base * (RANK_WEIGHT[rank + 1] or 0.4)
	local clock = now + rank * 1.1
	if s.size ~= size then
		s.size = size
		Stretch(s.crestS, size * 1.15, size * 0.2)
		Stretch(s.crestH, size * 0.6, size * 0.06)
	end
	DrawPair(s.body, clock, Mix(sat, hot, 0.85, 0.25), 0.7 * k * (1 + 0.4 * rush))
	DrawPair(s.core, clock, hot, 0.55 * k)
	-- Motes rising from the bottom, thickest low, where the liquid is when you most need this.
	for i, tex in ipairs(s.motes) do
		local lives = 1 + (i % 3 == 0 and 1 or 0)
		local q = (clock / 3 * lives + Hash(i * 5.7)) % 1
		local spread = 0.14 + 0.5 * q
		local x = (Hash(i * 3.3) - 0.5) * 2 * spread + math.sin(q * 6.3 + i) * 0.03
		local y = 0.03 + 0.9 * q ^ 1.5
		tex:ClearAllPoints()
		tex:SetPoint("CENTER", g.frame, "BOTTOM", x * size * 0.5, y * size)
		Size(tex, size * (0.03 + 0.03 * Hash(i * 2.1)))
		Paint(tex, hot, math.min(1, q / 0.15) * (1 - Smoothstep((q - 0.7) / 0.3)) * (0.55 + 0.45 * Hash(i * 8.7)) * k)
	end
	local pulse = 0.78 + 0.22 * math.sin(clock * 2 * math.pi * 2 / 3)
	Paint(s.crestS, sat, pulse * k)
	Paint(s.crestH, hot, pulse * 1.15 * k)
end

---------------------------------------------------------------------------
-- The healing looks, each a surge style: lit, tinted, stacked, settled and blinked out by
-- AnimateSurge with the rest. What lands on the surface is anchored to the pool's fill guide,
-- so the level is never read. Sized for the 180 px globe.

-- A sprite a style owns: it shows and hides with the style and lets go of its sheet when released.
local function Own(s, frame, slot, sublevel)
	local tex = Sprite(frame, slot, sublevel)
	if not tex then return nil end
	s.parts[#s.parts + 1] = tex
	if ns.Art.slots[slot].lazy then s.bound[#s.bound + 1] = { tex, slot } end
	return tex
end

local function OwnPair(s, frame, spec, sublevel)
	local p = Pair(frame, spec, sublevel)
	s.sheets[#s.sheets + 1] = p
	s.parts[#s.parts + 1] = p.a
	s.parts[#s.parts + 1] = p.b
	return p
end

-- A flipbook layer at a position in frames that doesn't wrap (growth). As DrawPair: the crossfade
-- in the colour, the strength in the alpha set last.
local function DrawStage(p, pos, color, strength)
	local spec = p.spec
	local last = spec.frames - 1
	pos = math.max(0, math.min(last, pos))
	local i = math.floor(pos)
	local f = pos - i
	if i ~= p.i then
		p.i = i
		Cell(p.a, spec, i)
		Cell(p.b, spec, math.min(i + 1, last))
	end
	local r, g, b = color[1], color[2], color[3]
	p.a:SetVertexColor(r * (1 - f), g * (1 - f), b * (1 - f))
	p.b:SetVertexColor(r * f, g * f, b * f)
	local k = math.max(0, math.min(1, strength))
	p.a:SetAlpha(k)
	p.b:SetAlpha(k)
end

-- Texcoords for one flipbook cell, turned by angle about the cell's middle. The art keeps to the
-- middle 70% of its cell, so turning stays inside (tools/blender/globe_heal_art.py LEAF_KEEP).
local CELL_TURN = 0.354
local function SpinCell(tex, spec, i, angle)
	local row = math.floor(i / spec.cols)
	local col = i - row * spec.cols
	local cu, cv = (col + 0.5) * spec.cw / spec.w, (row + spec.row + 0.5) * spec.ch / spec.h
	local h = CELL_TURN * spec.cw / spec.w
	local c, sn = math.cos(angle) * h, math.sin(angle) * h
	local function P(dx, dy) return cu + dx * c - dy * sn, cv + dx * sn + dy * c end
	local ulx, uly = P(-1, -1)
	local llx, lly = P(-1, 1)
	local urx, ury = P(1, -1)
	local lrx, lry = P(1, 1)
	tex:SetTexCoord(ulx, uly, llx, lly, urx, ury, lrx, lry)
end

local function DrawSpun(p, pos, angle, color, strength)
	local spec = p.spec
	pos = (pos % 1) * spec.frames
	local i = math.floor(pos)
	local f = pos - i
	SpinCell(p.a, spec, i, angle)
	SpinCell(p.b, spec, (i + 1) % spec.frames, angle)
	local r, g, b = color[1], color[2], color[3]
	p.a:SetVertexColor(r * (1 - f), g * (1 - f), b * (1 - f))
	p.b:SetVertexColor(r * f, g * f, b * f)
	local k = math.max(0, math.min(1, strength))
	p.a:SetAlpha(k)
	p.b:SetAlpha(k)
end

-- When this look was cast, and how long it runs, for looks that time themselves from your own
-- cast (Watch.lua castAt). Nil: no cast to go on, or the instance is fading out. A skill's Preview
-- shows the whole life of a long buff in its few seconds.
local PREVIEW_LENGTH = 9
local function TimedBy(inst)
	local effect, st = inst.effect, inst.st
	if not (effect and st and st.castAt and st.length and st.length > 0) then return nil end
	local length = st.length
	if ns.GlobeAura.previewKey == effect.key then length = math.min(length, PREVIEW_LENGTH) end
	return st.castAt, length
end

-- Vines.
local VINE_SPAN = 0.85 -- of the buff's length to grow to the crown, then a quiet wreath
local VINE_RETRACT = 0.35 -- seconds to draw back when recast
local function VineTip(q, side)
	local sgn = side == 0 and -1 or 1
	local th = (math.rad(74 - 69 * q) + math.rad(2.2) * math.sin(q * 11 + side * 1.7) * (1 - q) ^ 0.3) * sgn
	local rad = 0.858 + 0.016 * math.sin(q * 15 + side * 2.1)
	return math.sin(th) * rad, math.cos(th) * rad
end

local function VineGrowth(u, s, now, dt)
	-- Fading out: stays as it is.
	if u.effect then
		local from, length = TimedBy(u)
		local target = from and math.max(0, math.min(1, (now - from) / (length * VINE_SPAN))) or 1
		if s.effect ~= u.effect or not s.grow then
			s.effect, s.grow = u.effect, target
		elseif target >= s.grow then
			s.grow = target
		else
			s.grow = math.max(target, s.grow - (dt or 0) / VINE_RETRACT)
		end
	end
	return s.grow or 1
end

function BUILD.vines(g, u)
	local s = { parts = {}, sheets = {}, bound = {} }
	s.mask = GlobeMask(u.front, g.frame)
	s.vine = OwnPair(s, u.front, HEAL_ART.vines, 3)
	PairCall(s.vine, "AddMaskTexture", s.mask)
	s.tips = {}
	for side = 1, 2 do
		local tex = Own(s, u.front, "mote", 4)
		tex:AddMaskTexture(s.mask)
		s.tips[side] = tex
	end
	return s
end

function DRAW.vines(g, u, s, now, base, sat, hot, rush, calm, dt)
	local size = g.size
	local k = base * (RANK_WEIGHT[u.rank + 1] or 0.4) * (1 - 0.3 * calm)
	if s.size ~= size then
		s.size = size
		PairCall(s.vine, "SetSize", size, size)
	end
	local grow = VineGrowth(u, s, now, dt)
	DrawStage(s.vine, grow * (HEAL_ART.vines.frames - 1), Mix(sat, hot, 0.62, 0.51), k)
	-- The bud of light at the growing tip, gone once it has reached the crown.
	local bud = 1 - Smoothstep((grow - 0.9) / 0.1)
	for side, tex in ipairs(s.tips) do
		local x, y = VineTip(math.min(0.995, grow), side - 1)
		tex:ClearAllPoints()
		tex:SetPoint("CENTER", u.front, "CENTER", x * size / 2, y * size / 2)
		Size(tex, size * 0.13)
		Paint(tex, hot, 0.85 * (0.75 + 0.25 * math.sin(now * 2.8)) * bud * k)
	end
end

-- Halo: the ring of one sprite, its back arc behind the globe and its front arc on the glass.
function BUILD.halo(g, u)
	local s = { parts = {}, sheets = {}, bound = {} }
	s.backGlow = Own(s, u.behind, "healHalo", 5)
	s.backCore = Own(s, u.behind, "healHalo", 6)
	s.backGlow:SetTexCoord(0, 1, 0.5, 0.75)
	s.backCore:SetTexCoord(0, 1, 0, 0.25)
	s.mask = GlobeMask(u.front, g.frame)
	s.glass = Own(s, u.front, "auraCorona", 0)
	s.glass:AddMaskTexture(s.mask)
	s.frontGlow = Own(s, u.front, "healHalo", 1)
	s.frontCore = Own(s, u.front, "healHalo", 2)
	s.frontGlow:SetTexCoord(0, 1, 0.75, 1)
	s.frontCore:SetTexCoord(0, 1, 0.25, 0.5)
	s.glints = {}
	for k = 1, 2 do s.glints[k] = Own(s, u.front, "mote", 3) end
	s.motes = {}
	for k = 1, 5 do
		local tex = Own(s, u.front, "mote", 4)
		tex:AddMaskTexture(s.mask)
		s.motes[k] = tex
	end
	return s
end

function DRAW.halo(g, u, s, now, base, sat, hot, rush, calm)
	local size = g.size
	local r = size / 2
	local clock = now + u.rank * 1.3
	local k = base * (RANK_WEIGHT[u.rank + 1] or 0.4) * (1 - 0.35 * calm)
	local breath = 0.88 + 0.12 * math.sin(clock * 2 * math.pi / 4.2)
	local w = 2.8 * r * u.scale
	local h = w / 2
	local y = 1.09 * r
	if s.size ~= w then
		s.size = w
		for _, tex in ipairs({ s.backGlow, s.backCore }) do
			Stretch(tex, w, h / 2)
			tex:ClearAllPoints()
			tex:SetPoint("CENTER", u.behind, "CENTER", 0, y + h / 4)
		end
		for _, tex in ipairs({ s.frontGlow, s.frontCore }) do
			Stretch(tex, w, h / 2)
			tex:ClearAllPoints()
			tex:SetPoint("CENTER", u.front, "CENTER", 0, y - h / 4)
		end
		Size(s.glass, size * 1.1)
		s.glass:ClearAllPoints()
		s.glass:SetPoint("CENTER", u.front, "CENTER", 0, r * 0.97)
	end
	local lit = breath * k * (1 + 0.35 * rush)
	Paint(s.backGlow, sat, 0.62 * lit)
	Paint(s.backCore, hot, 0.7 * lit)
	Paint(s.glass, sat, 0.22 * breath * k)
	Paint(s.frontGlow, sat, 0.78 * lit)
	Paint(s.frontCore, hot, 0.95 * lit)
	-- Two glints walking the ring, in no hurry; brighter on its front half.
	for i, tex in ipairs(s.glints) do
		local a = clock * 0.5 * (i == 1 and 1 or -1) + (i - 1) * math.pi * 0.8
		tex:ClearAllPoints()
		tex:SetPoint("CENTER", u.front, "CENTER", math.cos(a) * w * 0.31, y - math.sin(a) * w * 0.0961)
		Size(tex, r * 0.42)
		Paint(tex, hot, 0.7 * (0.5 + 0.5 * math.max(0, math.sin(a))) * k)
	end
	-- Motes of its light drifting down onto the glass, spread evenly over the top.
	for i, tex in ipairs(s.motes) do
		local q = (clock / 7.5 + i / 5) % 1
		local x = (Hash(i * 3.7) - 0.5) * r * 0.8 + math.sin(q * 5 + i) * r * 0.05
		tex:ClearAllPoints()
		tex:SetPoint("CENTER", u.front, "CENTER", x, r * 0.82 - q * r * 0.72)
		Size(tex, r * (0.1 + 0.05 * Hash(i * 7.1)))
		Paint(tex, hot, 0.55 * Smoothstep(q / 0.2) * (1 - Smoothstep((q - 0.45) / 0.55)) * k)
	end
end

-- Bloom: leaves off the top of the rim, each with its own soft glow behind it.
local BLOOM_LEAVES = 12
local BLOOM_PERIOD = 9.5

function BUILD.bloom(g, u)
	local s = { parts = {}, sheets = {}, bound = {} }
	s.leaves = {}
	for i = 1, BLOOM_LEAVES do
		s.leaves[i] = { glow = Own(s, u.behind, "mote", 4), leaf = OwnPair(s, u.behind, HEAL_ART.leaf, 5) }
		PairCall(s.leaves[i].leaf, "ClearAllPoints")
	end
	return s
end

function DRAW.bloom(g, u, s, now, base, sat, hot, rush, calm)
	local r = g.size / 2
	local clock = now + u.rank * 1.3
	local k = base * (RANK_WEIGHT[u.rank + 1] or 0.4) * (1 - 0.4 * calm)
	local tint = Mix(sat, hot, 0.9, 0.22)
	for j = 0, BLOOM_LEAVES - 1 do
		local item = s.leaves[j + 1]
		local q = (clock / BLOOM_PERIOD + j / BLOOM_LEAVES + Hash(j * 5.3) * 0.08) % 1
		-- Rim positions spread evenly over the top, mirrored in pairs, so it can't lean.
		local a0 = math.rad(40 + 100 * (math.floor(j / 2) + 0.5) / (BLOOM_LEAVES / 2))
		if j % 2 == 0 then a0 = math.pi - a0 end
		local d0 = r * (0.96 + 0.03 * Hash(j * 2.2))
		-- Rises up and away, slower the further out, swaying.
		local rise = 1 - (1 - q) ^ 1.6
		local x = math.cos(a0) * d0 + math.cos(a0) * rise * r * 0.42 + math.sin(q * 4.2 + j * 2.1) * r * 0.09 * (1 + q)
		local y = math.sin(a0) * d0 + (0.42 + 0.46 * Hash(j * 3.3)) * rise * r * 1.05
		local fade = Smoothstep(q / 0.14) * (1 - Smoothstep((q - 0.52) / 0.48))
		local sz = r * (0.27 + 0.13 * Hash(j * 9.9)) * (0.85 + 0.15 * q)
		item.glow:ClearAllPoints()
		item.glow:SetPoint("CENTER", u.behind, "CENTER", x, y)
		Size(item.glow, sz * 1.7)
		Paint(item.glow, sat, 0.34 * fade * k)
		local leaf = item.leaf
		PairCall(leaf, "ClearAllPoints")
		PairCall(leaf, "SetPoint", "CENTER", u.behind, "CENTER", x, y)
		PairCall(leaf, "SetSize", sz, sz)
		local pos = clock / (2.8 + 1.5 * Hash(j * 1.1)) + Hash(j)
		DrawSpun(leaf, pos, q * 2.6 + Hash(j * 4.4) * 6.28, tint, 0.8 * fade * k)
	end
end

-- Veil: one loop over the top of the rim, under the top-weighted mask.
function BUILD.veil(g, u)
	local s = { parts = {}, sheets = {}, bound = {} }
	s.veil = OwnPair(s, u.behind, HEAL_ART.veil, 4)
	if u.weight then PairCall(s.veil, "AddMaskTexture", u.weight) end
	return s
end

function DRAW.veil(g, u, s, now, base, sat, hot, rush, calm)
	local r = g.size / 2
	local clock = now + u.rank * 1.3
	local k = base * (RANK_WEIGHT[u.rank + 1] or 0.4) * (1 - 0.4 * calm)
	local breath = 0.9 + 0.1 * math.sin(clock * 2 * math.pi / 5)
	local w, h = 3.4 * r, 1.7 * r
	if s.size ~= r then
		s.size = r
		PairCall(s.veil, "SetSize", w, h)
		for _, tex in ipairs({ s.veil.a, s.veil.b }) do
			tex:ClearAllPoints()
			tex:SetPoint("CENTER", u.behind, "CENTER", 0, h / 2)
		end
	end
	DrawPair(s.veil, clock, Mix(sat, hot, 1, 0.32), breath * k)
end

-- Rain: a few drops falling to the fill guide, each with its ripple where it lands.
local RAIN_LANES = { -0.62, 0.18, -0.25, 0.62, 0.42, -0.5, 0.05, -0.08 }
local RAIN_PERIOD, RAIN_FALL = 5.2, 0.36

function BUILD.rain(g, u)
	local guide = g.frame.pool:Anchors()
	local s = { parts = {}, sheets = {}, bound = {}, guide = guide }
	local over = Layer(g.parent)
	over:SetAllPoints(g.frame)
	local mask = GlobeMask(over, g.frame)
	local function Masked(slot, sublevel)
		local tex = Own(s, over, slot, sublevel)
		tex:AddMaskTexture(mask)
		return tex
	end
	s.line = Masked("mote", 0)
	s.lanes = {}
	for i = 1, #RAIN_LANES do
		local lane = { drop = Masked("healDrop", 3), glow = Masked("mote", 2), band = Masked("healRings", 1),
			ring = Masked("healRings", 2), echo = Masked("healRings", 2), splash = Masked("mote", 3) }
		lane.ring:SetTexCoord(0, 1, 0.008, 0.492)
		lane.echo:SetTexCoord(0, 1, 0.008, 0.492)
		lane.band:SetTexCoord(0, 1, 0.508, 0.992)
		s.lanes[i] = lane
	end
	s.frames, s.glass = { over }, { over }
	return s
end

function DRAW.rain(g, u, s, now, base, sat, hot, rush, calm)
	local size = g.size
	local clock = now + u.rank * 1.7
	local k = base * (RANK_WEIGHT[u.rank + 1] or 0.4) * (1 - 0.45 * calm)
	if s.size ~= size then
		s.size = size
		s.line:ClearAllPoints()
		s.line:SetPoint("CENTER", s.guide, "TOP")
		Stretch(s.line, size, size * 0.08)
	end
	-- Kept faint: a saturated glow on the liquid tints it (blue over red reads pink).
	Paint(s.line, sat, 0.1 * k)
	for i, lane in ipairs(s.lanes) do
		local q = (clock / RAIN_PERIOD + (i - 1) / #RAIN_LANES + Hash((i - 1) * 4.1) * 0.05) % 1
		local x = RAIN_LANES[i] * size * 0.34
		local parts = { lane.drop, lane.glow, lane.band, lane.ring, lane.echo, lane.splash }
		if q < RAIN_FALL then
			local f = q / RAIN_FALL
			local y = size * 0.58 * (1 - f ^ 1.45)
			local a = Smoothstep(f / 0.3) * k
			lane.drop:ClearAllPoints()
			lane.drop:SetPoint("CENTER", s.guide, "TOP", x, y + size * 0.035)
			Stretch(lane.drop, size * 0.04, size * 0.08)
			Paint(lane.drop, hot, 0.95 * a)
			lane.glow:ClearAllPoints()
			lane.glow:SetPoint("CENTER", s.guide, "TOP", x, y)
			Size(lane.glow, size * 0.1)
			Paint(lane.glow, sat, 0.45 * a)
			for _, tex in ipairs({ lane.band, lane.ring, lane.echo, lane.splash }) do tex:SetAlpha(0) end
		else
			local rq = (q - RAIN_FALL) / (1 - RAIN_FALL)
			local w = size * (0.08 + 0.72 * (1 - (1 - rq) ^ 2.2))
			local a = (1 - rq) ^ 1.6 * k
			for _, tex in ipairs({ lane.band, lane.ring, lane.echo, lane.splash }) do
				tex:ClearAllPoints()
				tex:SetPoint("CENTER", s.guide, "TOP", x, 0)
			end
			Stretch(lane.band, w, w * 0.25)
			Paint(lane.band, sat, 0.22 * a)
			Stretch(lane.ring, w, w * 0.25)
			Paint(lane.ring, hot, 0.62 * a)
			if rq > 0.12 then
				Stretch(lane.echo, w * 0.55, w * 0.1375)
				Paint(lane.echo, hot, 0.34 * (1 - rq) ^ 2 * k)
			else
				lane.echo:SetAlpha(0)
			end
			if rq < 0.25 then
				Size(lane.splash, size * 0.14)
				Paint(lane.splash, hot, 0.8 * (1 - rq / 0.25) ^ 1.4 * k)
			else
				lane.splash:SetAlpha(0)
			end
			lane.drop:SetAlpha(0)
			lane.glow:SetAlpha(0)
		end
	end
end

-- Pulse: the beat. Rising 0..1 while a wave climbs to the surface, flashing 0..1 after it lands,
-- and how strong: from your own cast and the skill's tick period, or a plain slow cadence.
local PULSE_RISE, PULSE_FLASH, PULSE_PLAIN = 1.15, 0.9, 4.5
local function PulseBeat(u, now)
	local effect = u.effect
	local from, length = TimedBy(u)
	if from and effect and effect.tick then
		local period = effect.tick
		local rise = math.min(PULSE_RISE, period * 0.55)
		local flash = math.min(PULSE_FLASH, period * 0.45)
		local elapsed = now - from
		local ticks = math.floor(length / period + 0.001)
		local done = math.floor(elapsed / period)
		local since = elapsed - done * period
		local rising, flashing
		if done + 1 <= ticks and period - since <= rise then rising = 1 - (period - since) / rise end
		if done >= 1 and done <= ticks and since < flash then flashing = since / flash end
		return rising, flashing, 1
	end
	local clock = now + u.rank * 1.7
	local since = clock % PULSE_PLAIN
	local rising = since > PULSE_PLAIN - PULSE_RISE and (since - (PULSE_PLAIN - PULSE_RISE)) / PULSE_RISE or nil
	local flashing = since < PULSE_FLASH and since / PULSE_FLASH or nil
	return rising, flashing, 0.6
end

function BUILD.pulse(g, u)
	local guide, inside = g.frame.pool:Anchors()
	local s = { parts = {}, sheets = {}, bound = {}, guide = guide }
	-- Inside the liquid's clip: the wave, wide and soft, so it reads as light moving, not a ring.
	local liquid = Layer(inside)
	liquid:SetAllPoints(g.frame)
	local liquidMask = GlobeMask(liquid, g.frame)
	s.waveWide = Own(s, liquid, "mote", 0)
	s.waveCrest = Own(s, liquid, "mote", 1)
	s.waveWide:AddMaskTexture(liquidMask)
	s.waveCrest:AddMaskTexture(liquidMask)
	-- Over the surface: its answer, riding the fill guide.
	local over = Layer(g.parent)
	over:SetAllPoints(g.frame)
	local mask = GlobeMask(over, g.frame)
	local function Masked(slot, sublevel)
		local tex = Own(s, over, slot, sublevel)
		tex:AddMaskTexture(mask)
		tex:ClearAllPoints()
		tex:SetPoint("CENTER", guide, "TOP")
		return tex
	end
	s.flash = Masked("mote", 0)
	s.flashHot = Masked("mote", 1)
	s.ripple = Masked("healRings", 2)
	s.rippleHot = Masked("healRings", 3)
	s.ripple:SetTexCoord(0, 1, 0.508, 0.992)
	s.rippleHot:SetTexCoord(0, 1, 0.008, 0.492)
	s.dome = Masked("healDome", 2)
	s.frames, s.glass, s.liquid = { liquid, over }, { over }, liquid
	return s
end

function DRAW.pulse(g, u, s, now, base, sat, hot, rush, calm)
	local size = g.size
	local rising, flashing, soft = PulseBeat(u, now)
	local k = base * (RANK_WEIGHT[u.rank + 1] or 0.4) * (1 - 0.3 * calm) * soft
	if rising then
		local fade = Smoothstep(rising / 0.25)
		local y = -size * 0.62 * (1 - rising)
		for _, tex in ipairs({ s.waveWide, s.waveCrest }) do
			tex:ClearAllPoints()
			tex:SetPoint("CENTER", s.guide, "TOP", 0, y)
		end
		Stretch(s.waveWide, size * 1.35, size * 0.42)
		Paint(s.waveWide, sat, 0.75 * fade * k)
		Stretch(s.waveCrest, size * 1.1, size * 0.16)
		Paint(s.waveCrest, hot, 0.55 * fade * k)
	else
		s.waveWide:SetAlpha(0)
		s.waveCrest:SetAlpha(0)
	end
	if flashing then
		local ca = (1 - flashing) ^ 1.4
		local ww = size * (0.55 + 0.45 * flashing)
		Stretch(s.flash, ww, ww * 0.09)
		Paint(s.flash, sat, 0.9 * ca * k)
		Stretch(s.flashHot, ww * 0.65, ww * 0.65 * 0.04)
		Paint(s.flashHot, hot, 1.1 * ca * k)
		Size(s.dome, size * 0.8)
		s.dome:ClearAllPoints()
		s.dome:SetPoint("CENTER", s.guide, "TOP", 0, size * 0.05)
		Paint(s.dome, sat, 0.42 * ca * (1 - flashing) * k)
		-- A ripple spreading from the middle, in place of the thin ring's rise.
		local rw = size * (0.25 + 0.7 * (1 - (1 - flashing) ^ 2))
		Stretch(s.ripple, rw, rw * 0.25)
		Paint(s.ripple, sat, 0.4 * ca * k)
		Stretch(s.rippleHot, rw * 0.98, rw * 0.245)
		Paint(s.rippleHot, hot, 0.65 * ca * k)
		if u.bloomTop then
			u.bloomTop:SetVertexColor(hot[1], hot[2], hot[3])
			u.bloomTop:SetAlpha(math.min(1, (0.1 + 0.28 * ca) * k))
		end
	else
		s.flash:SetAlpha(0)
		s.flashHot:SetAlpha(0)
		s.dome:SetAlpha(0)
		s.ripple:SetAlpha(0)
		s.rippleHot:SetAlpha(0)
	end
end

-- Embers: slow sparks with a trail, rising through the glass.
local EMBER_LANES = { -0.15, 0.3, -0.5, 0.05, 0.62, -0.32, 0.45, -0.7, 0.18, -0.05, 0.75, -0.6, 0 }

function BUILD.embers(g, u)
	local s = { parts = {}, sheets = {}, bound = {} }
	s.mask = GlobeMask(u.front, g.frame)
	s.embers = {}
	for i = 1, #EMBER_LANES do
		local tail = Own(s, u.front, "healDrop", 2)
		local glow = Own(s, u.front, "mote", 1)
		local core = Own(s, u.front, "mote", 3)
		tail:AddMaskTexture(s.mask)
		glow:AddMaskTexture(s.mask)
		core:AddMaskTexture(s.mask)
		-- The drop's art falls with its tail above it; flipped, the spark rises trailing.
		tail:SetTexCoord(0, 1, 1, 0)
		s.embers[i] = { tail = tail, glow = glow, core = core }
	end
	return s
end

function DRAW.embers(g, u, s, now, base, sat, hot, rush, calm)
	local size = g.size
	local r = size / 2
	local clock = now + u.rank * 1.3
	local k = base * (RANK_WEIGHT[u.rank + 1] or 0.4) * (1 - 0.35 * calm)
	for i, ember in ipairs(s.embers) do
		local speed = 1 + (i % 3 == 0 and 0.35 or 0)
		local q = (clock * speed / 10 + Hash(i * 5.7)) % 1
		local y = -r * 0.86 + q * r * 1.74
		local chord = math.sqrt(math.max(0.03, 1 - (y / r) ^ 2))
		local x = EMBER_LANES[i] * 0.72 * r * chord + math.sin(q * 9 + i * 1.9) * r * 0.06
		-- Each one gutters on its own and dies somewhere on the way up.
		local die = 0.55 + 0.4 * Hash(i * 2.9)
		local fade = Smoothstep(q / 0.14) * (1 - Smoothstep((q - die) / (1 - die)))
		local gutter = 0.72 + 0.28 * math.sin(clock * (1.1 + Hash(i)) * 3 + i) * math.sin(clock * 5 + i * 3)
		local sz = size * (0.07 + 0.04 * Hash(i * 2.1))
		local lit = fade * gutter * k
		ember.tail:ClearAllPoints()
		ember.tail:SetPoint("CENTER", u.front, "CENTER", x, y - sz * 1.15)
		Stretch(ember.tail, sz * 0.4, sz * 3.1)
		Paint(ember.tail, Mix(sat, hot, 0.6, 0.4), 0.7 * lit)
		ember.glow:ClearAllPoints()
		ember.glow:SetPoint("CENTER", u.front, "CENTER", x, y)
		Size(ember.glow, sz * 3)
		Paint(ember.glow, sat, 0.34 * lit)
		ember.core:ClearAllPoints()
		ember.core:SetPoint("CENTER", u.front, "CENTER", x, y)
		Size(ember.core, sz * 1.05)
		Paint(ember.core, hot, 0.9 * lit)
	end
end

-- What each style keeps of the swirl's shared light: corona size and strength, glass bloom.
local STYLE_LIGHT = {
	inhale = { corona = 0.98, glow = 0.42, top = 0.42 },
	pour = { corona = 0.7, glow = 0.22, top = 0.22 },
	upwell = { corona = 0.9, glow = 0.34, top = 0.4 },
	-- Healing looks: quiet, and quieter still when a long buff settles.
	vines = { corona = 0.7, glow = 0.14, top = 0.1, settle = 0.4 },
	halo = { corona = 0.9, glow = 0, top = 0.22, settle = 0.4 },
	bloom = { corona = 0.775, glow = 0.22, top = 0.22, settle = 0.4 },
	veil = { corona = 0.65, glow = 0.2, top = 0.3, settle = 0.4 },
	rain = { corona = 0.8, glow = 0, top = 0.14, settle = 0.5 },
	pulse = { corona = 0.8, glow = 0, top = 0.1, settle = 0.4 },
	embers = { corona = 0.8, glow = 0, top = 0.14, settle = 0.4 },
}

local function BuildSurge(g)
	local u = NewInstance("surge")
	local behind = Layer(g.parent, "aura")
	local front = Layer(g.parent, "glass")
	behind:Hide()
	front:Hide()
	u.behind, u.front = behind, front
	u.spirals = { Sprite(behind, "auraSpiral", 0), Sprite(behind, "auraSpiral", 0) }
	u.corona = Sprite(behind, "auraCorona", 1)
	u.ring = Sprite(behind, "auraRing", 2)
	if behind.CreateMaskTexture and ns.Art.Path("auraTopWeight") then
		local mask = behind:CreateMaskTexture()
		mask:SetTexture(ns.Art.Path("auraTopWeight"), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		mask:SetPoint("CENTER")
		for _, tex in ipairs({ u.spirals[1], u.spirals[2], u.corona, u.ring }) do
			if tex then tex:AddMaskTexture(mask) end
		end
		u.weight = mask
	end
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

local function ClearSwirl(u)
	if u.swirlClear then return end
	u.swirlClear = true
	local c = u.sat
	Paint(u.spirals[1], c, 0)
	Paint(u.spirals[2], c, 0)
	Paint(u.ring, c, 0)
	for _, tex in ipairs(u.motes) do Paint(tex, c, 0) end
end

local function AnimateSurge(g, u, now, dt)
	if not u.ok or not Ease(u, now, dt, false) then
		u.behind:Hide()
		u.front:Hide()
		HideStyles(u)
		return false
	end
	u.behind:Show()
	u.front:Show()
	local opt = Opt()
	local e = Smoothstep(u.level)
	local intensity = tonumber(opt.intensity) or 1
	local flicker, gutter = Gutter(u, now, dt)
	local base = e * intensity * Strength(u) * flicker
	local size = g.size * SCALE * u.scale
	local sat, hot = u.sat, u.hotColor
	local turn = u.rank % 2 == 0 and -1 or 1 -- stacked surges turn against each other
	local rush = 0
	if u.ignite and now - u.ignite < IGNITE then rush = 1 - (now - u.ignite) / IGNITE end
	if u.weight then u.weight:SetSize(size * 1.35, size * 1.35) end
	local style = ActiveStyle(g, u)
	u.style = style
	if style ~= "swirl" then
		ClearSwirl(u)
		local s = EnsureStyle(g, u, style)
		ShowStyle(g, u, style)
		FollowLiquid(g, s)
		-- A long effect settles after its first seconds, and wakes for its last.
		local calm = 0
		local effect, st = u.effect, u.st
		local length = st and st.length or effect and effect.length or 0
		if effect and length >= SETTLE_LENGTH and opt.settleLong then
			calm = Smoothstep((now - (u.litAt or now) - SETTLE_FROM) / SETTLE_OVER) * (1 - Smoothstep(gutter * 2.5))
		end
		u.calm = calm
		local light = STYLE_LIGHT[style]
		Size(u.corona, size * light.corona)
		local breath = 0.86 + 0.14 * math.sin(now * 2 * math.pi / 2.2)
		Paint(u.corona, sat, light.glow * breath * base * (1 - (light.settle or 0) * calm))
		if u.bloomLow then
			u.bloomLow:SetAlpha(0)
			u.bloomTop:SetVertexColor(hot[1], hot[2], hot[3])
			u.bloomTop:SetAlpha(math.min(1, light.top * breath * base * (1 + rush) * (1 - (light.settle or 0) * calm)))
		end
		if KICKS_POOL[style] and u.ignite and u.kicked ~= u.ignite then
			u.kicked = u.ignite
			g.frame.pool:Kick(0.06)
		end
		DRAW[style](g, u, s, now, base, sat, hot, rush, calm, dt)
		return true
	end
	HideStyles(u)
	u.swirlClear = nil
	u.calm = 0
	-- Two spiral phases, each shrinking toward the rim while it turns, crossfading.
	for i, tex in ipairs(u.spirals) do
		local p = (now / 1.6 + (i - 1) * 0.5) % 1
		Size(tex, size * (1.18 - 0.18 * p))
		Spin(tex, turn * now * 0.9 - (i - 1) * 3 - u.rank)
		Paint(tex, sat, 0.75 * math.sin(p * math.pi) * base * (1 + rush))
	end
	Size(u.corona, size * 0.95)
	Paint(u.corona, sat, 0.5 * base)
	local p = (now / 1.1) % 1
	Size(u.ring, size * (1.3 - 0.3 * p))
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
		local dist = r * 1.55 * (1 - 0.5 * q)
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
	local behind = Layer(g.parent, "aura")
	local front = Layer(g.parent, "glass")
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
-- One-off heals: what a flare skill's "in" parts play instead of the burst (LookOf's second
-- value). One of each per globe, built when first wanted; a recast restarts it. Everything on
-- the surface is anchored to the fill guide; the level is never read.

local HEAL_BUILD, HEAL_DRAW = {}, {}

local healArt = {} -- heal -> whether its sheets loaded; once only

local function HealArt(name)
	if healArt[name] == nil then
		local ok = true
		for _, slot in ipairs(HEAL_SLOTS[name]) do
			if not ns.Art.Require(slot) then ok = false end
		end
		if not ok and ns.Log then ns.Log("globe auras: " .. name .. " art failed to load, using burst") end
		healArt[name] = ok
	end
	return healArt[name]
end

local function CanDrawHeal(g, name)
	if not HEAL_SLOTS[name] or not HealArt(name) then return false end
	local pool = g.frame.pool
	if not (pool and pool.Anchors) then return false end
	-- A split globe has two levels side by side, so nothing can ride "the" level.
	if g.frame == ns.ResourceGlobe and ns.Globes.IsSplit and ns.Globes.IsSplit() then return false end
	return true
end

local function HealLevels(g, h)
	h.behind:SetFrameLevel(LevelOf("aura"))
	h.over:SetFrameLevel(LevelOf("glass"))
	h.liquid:SetFrameLevel(g.frame.pool.frame:GetFrameLevel() + 1)
end

local function NewHeal(g)
	local h = { parts = {}, sheets = {}, bound = {} }
	local guide, inside = g.frame.pool:Anchors()
	h.guide = guide
	h.behind = Layer(g.parent)
	h.behind:SetAllPoints(g.frame)
	h.over = Layer(g.parent)
	h.over:SetAllPoints(g.frame)
	h.overMask = GlobeMask(h.over, g.frame)
	h.liquid = Layer(inside)
	h.liquid:SetAllPoints(g.frame)
	h.liquidMask = GlobeMask(h.liquid, g.frame)
	if ns.Art.Path("auraTopWeight") then
		h.weight = h.behind:CreateMaskTexture()
		h.weight:SetTexture(ns.Art.Path("auraTopWeight"), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		h.weight:SetPoint("CENTER")
	end
	if ns.Art.Path("globeRim") then
		h.bloom = h.over:CreateTexture(nil, "ARTWORK", nil, 0)
		h.bloom:SetTexture(ns.Art.Path("globeRim"))
		h.bloom:SetBlendMode("ADD")
		h.bloom:SetAllPoints()
		h.bloom:SetTexCoord(0, 1, 1, 0)
		h.bloom:SetAlpha(0)
	end
	h.frames = { h.behind, h.over, h.liquid }
	for _, frame in ipairs(h.frames) do frame:Hide() end
	return h
end

-- A heal sprite: masked to the globe if over, and to the top-weighted mask behind.
local function HealOver(h, slot, sublevel)
	local tex = Own(h, h.over, slot, sublevel)
	tex:AddMaskTexture(h.overMask)
	return tex
end

local function HealBehind(h, slot, sublevel)
	local tex = Own(h, h.behind, slot, sublevel)
	if h.weight then tex:AddMaskTexture(h.weight) end
	return tex
end

local function HealLiquid(h, slot, sublevel)
	local tex = Own(h, h.liquid, slot, sublevel)
	tex:AddMaskTexture(h.liquidMask)
	return tex
end

local function HealBloom(h, hot, alpha)
	if h.bloom then
		h.bloom:SetVertexColor(hot[1], hot[2], hot[3])
		h.bloom:SetAlpha(math.max(0, math.min(1, alpha)))
	end
end

local function OnSurface(tex, guide, x, y)
	tex:ClearAllPoints()
	tex:SetPoint("CENTER", guide, "TOP", x or 0, y or 0)
end

local MEND_MOTES = 8

function HEAL_BUILD.mend(g, h)
	h.corona = HealBehind(h, "auraCorona", 0)
	h.domeSat = HealOver(h, "healDome", 1)
	h.domeHot = HealOver(h, "healDome", 2)
	h.line = HealOver(h, "mote", 3)
	h.under = HealLiquid(h, "healDome", 0)
	h.under:SetTexCoord(0, 1, 1, 0)
	h.motes = {}
	for i = 1, MEND_MOTES do h.motes[i] = HealOver(h, "mote", 4) end
end

function HEAL_DRAW.mend(g, h, t, k, sat, hot)
	local size = g.size
	local q = math.min(1, t / HEAL_SECONDS.mend)
	local glow = math.sin(math.min(1, q / 0.32) * math.pi * 0.5) * (1 - Smoothstep((q - 0.25) / 0.75))
	local dome = size * (0.55 + 0.9 * (1 - (1 - q) ^ 2))
	Size(h.corona, size * 1.45)
	Paint(h.corona, sat, 0.5 * glow * k)
	for _, tex in ipairs({ h.domeSat, h.domeHot, h.line, h.under }) do OnSurface(tex, h.guide) end
	Size(h.domeSat, dome)
	Paint(h.domeSat, sat, 0.95 * glow * k)
	Size(h.domeHot, dome * 0.72)
	Paint(h.domeHot, hot, 0.7 * glow * k)
	Stretch(h.line, size * 1.05, size * 0.0735)
	Paint(h.line, hot, 0.85 * glow * k)
	Size(h.under, dome * 0.55)
	Paint(h.under, sat, 0.42 * glow * k)
	HealBloom(h, hot, 0.42 * glow * k)
	for i, tex in ipairs(h.motes) do
		local mq = q * 1.25 - Hash(i * 3.1) * 0.25
		if mq > 0 and mq < 1 then
			local x = (Hash(i * 6.7) - 0.5) * size * 0.7
			local y = size * (0.08 + 0.46 * (1 - (1 - mq) ^ 2)) * (0.6 + 0.8 * Hash(i * 2.3))
			OnSurface(tex, h.guide, x, y)
			Size(tex, size * 0.07)
			Paint(tex, hot, (1 - mq) ^ 1.2 * 0.9 * k)
		else
			tex:SetAlpha(0)
		end
	end
end

function HEAL_BUILD.benediction(g, h)
	h.corona = HealBehind(h, "auraCorona", 0)
	h.ring = HealBehind(h, "auraRing", 1)
	h.ringHot = HealBehind(h, "auraRing", 2)
	h.beamGlow = Own(h, h.over, "healBeam", 1)
	h.beamCore = Own(h, h.over, "healBeam", 2)
	h.beamGlow:SetTexCoord(0.5, 1, 0, 1)
	h.beamCore:SetTexCoord(0, 0.5, 0, 1)
	h.spot = HealOver(h, "mote", 3)
	h.rippleBand = HealOver(h, "healRings", 3)
	h.rippleCore = HealOver(h, "healRings", 4)
	h.rippleBand:SetTexCoord(0, 1, 0.508, 0.992)
	h.rippleCore:SetTexCoord(0, 1, 0.008, 0.492)
end

function HEAL_DRAW.benediction(g, h, t, k, sat, hot)
	local size = g.size
	local r = size / 2
	local q = math.min(1, t / HEAL_SECONDS.benediction)
	local beam = Smoothstep(q / 0.1) * (1 - Smoothstep((q - 0.32) / 0.4))
	local ringQ = math.min(1, t / 1)
	local ringAlpha = math.sin(math.min(1, ringQ * 1.2) * math.pi) * (1 - ringQ) ^ 0.3
	local big = size * SCALE
	if h.weight then h.weight:SetSize(big * 1.35, big * 1.35) end
	Size(h.ring, big * (1.05 + 0.32 * Out(ringQ)))
	Paint(h.ring, sat, 1.05 * ringAlpha * k)
	Size(h.ringHot, big * (1.04 + 0.3 * Out(ringQ)))
	Paint(h.ringHot, hot, 0.7 * ringAlpha * k)
	Size(h.corona, size * 1.5)
	Paint(h.corona, sat, 0.42 * beam * k)
	-- The beam runs from above the crown down to the level: its bottom is the fill guide's top.
	if h.beamSize ~= size then
		h.beamSize = size
		for _, tex in ipairs({ h.beamGlow, h.beamCore }) do
			tex:ClearAllPoints()
			tex:SetPoint("TOP", g.frame, "TOP", 0, r * 0.85)
			tex:SetPoint("BOTTOM", h.guide, "TOP")
		end
		h.beamGlow:SetWidth(size * 0.72)
		h.beamCore:SetWidth(size * 0.5)
	end
	Paint(h.beamGlow, sat, 0.95 * beam * k)
	Paint(h.beamCore, hot, 0.72 * beam * k)
	-- Where it lands.
	local spot = 1 - Smoothstep((q - 0.05) / 0.5)
	OnSurface(h.spot, h.guide)
	Size(h.spot, size * 0.4)
	Paint(h.spot, hot, spot * beam * k)
	local rq = math.min(1, t / 0.75)
	local w = size * (0.12 + 0.9 * (1 - (1 - rq) ^ 2.4))
	OnSurface(h.rippleBand, h.guide)
	Stretch(h.rippleBand, w, w * 0.25)
	Paint(h.rippleBand, sat, 0.7 * (1 - rq) ^ 1.2 * k)
	OnSurface(h.rippleCore, h.guide)
	Stretch(h.rippleCore, w, w * 0.25)
	Paint(h.rippleCore, hot, (1 - rq) ^ 1.3 * k)
	HealBloom(h, hot, 0.32 * beam * k)
end

local MOUND_U = 0.42 -- the swell's art runs this much of the globe above the surface
local MOUND_BELOW = 0.12 -- and this much of that below it, covering the surface's own wave

-- The swell's shape over its life, as in the art (globe_heal_art.py gen_mound).
local function MoundRise(q)
	return math.sin(math.min(1, q / 0.7) * math.pi * 0.5) ^ 0.75 * (1 - Smoothstep((q - 0.55) / 0.45))
end

function HEAL_BUILD.mound(g, h)
	-- One opaque layer in the liquid's colour, stepped frame by frame: two "over" layers must
	-- never crossfade, it flashes under any parent alpha.
	h.body = HealOver(h, "healMound", 0)
	h.body:SetBlendMode("BLEND")
	h.edge = HealOver(h, "healMound", 1)
	h.glow = HealLiquid(h, "mote", 0)
	h.corona = HealOver(h, "auraCorona", 2)
end

function HEAL_DRAW.mound(g, h, t, k, sat, hot)
	local size = g.size
	local q = math.min(0.999, t / HEAL_SECONDS.mound)
	local u = size * MOUND_U
	local frames = HEAL_ART.moundBody.frames
	local i = math.floor(q * frames)
	-- Between stepped frames the height keeps moving, so the rise doesn't stutter.
	local at, here = MoundRise((i + 0.5) / frames), MoundRise(q)
	local keep = at > 0.02 and math.max(0.8, math.min(1.25, here / at)) or 1
	if i ~= h.cell then
		h.cell = i
		Cell(h.body, HEAL_ART.moundBody, i)
		Cell(h.edge, HEAL_ART.moundEdge, i)
	end
	for _, tex in ipairs({ h.body, h.edge }) do
		tex:ClearAllPoints()
		tex:SetPoint("BOTTOM", h.guide, "TOP", 0, -MOUND_BELOW * u)
		Stretch(tex, size * 1.15, u * (1 + MOUND_BELOW) * keep)
	end
	local c = g.frame.pool.color or { 1, 1, 1 }
	Paint(h.body, c, k)
	Paint(h.edge, Mix(sat, hot, 0.8, 0.3), 0.42 * k)
	local rise = math.sin(math.min(1, q / 0.45) * math.pi * 0.5)
	local fall = 1 - Smoothstep((q - 0.3) / 0.7)
	HealBloom(h, hot, 0.26 * rise * fall * k)
	OnSurface(h.corona, h.guide, 0, u * 0.3)
	Size(h.corona, size * 0.9)
	Paint(h.corona, sat, 0.12 * rise * fall * k)
	OnSurface(h.glow, h.guide)
	Stretch(h.glow, size * 1.05 * 0.85, size * 1.05 * 0.5)
	Paint(h.glow, sat, 0.22 * rise * (1 - Smoothstep((q - 0.25) / 0.6)) * k)
end

local function EnsureHeal(g, name)
	local h = g.heals[name]
	if not h then
		h = NewHeal(g)
		HEAL_BUILD[name](g, h)
		g.heals[name] = h
		HealLevels(g, h)
	elseif h.released then
		Reattach(h)
		h.cell = nil
	end
	return h
end

local function AnimateHeals(g, now)
	local busy = false
	for name, h in pairs(g.heals) do
		if h.started and now - h.started < HEAL_SECONDS[name] then
			busy = true
			for _, frame in ipairs(h.frames) do frame:Show() end
			local tint = TINTS[h.tint] or TINTS.holy
			local k = (tonumber(Opt().intensity) or 1) * (h.strength or 1)
			if h.weight then h.weight:SetSize(g.size * SCALE * 1.35, g.size * SCALE * 1.35) end
			HEAL_DRAW[name](g, h, now - h.started, k, tint.sat, tint.hot)
		elseif h.started then
			h.started = nil
			for _, frame in ipairs(h.frames) do frame:Hide() end
		end
	end
	return busy
end

---------------------------------------------------------------------------
-- Globes and their layout.

local function GlobeFor(kind)
	if kind == "health" then return globes.health end
	if kind == "power" then return globes.resource end
	if ns.Watch.Testing and ns.Watch.Testing() then return globes.resource end
	local powerType = UnitPowerType("player")
	if powerType == MANA or (ns.Globes.IsSplit and ns.Globes.IsSplit()) then
		return globes.resource
	end
end

-- The rendered lightning's textures on one instance, built the first time it strikes (the
-- sheets are already on the GPU, see PrepareStorm). Nil: use the drawn static and bolts.
EnsureStorm = function(g, a)
	local opt = Opt()
	if opt.renderedStorm == false then return nil end
	local s = a.storm
	if s and s.loaded then return s end
	if not (ns.Art.Require(STORM.core.slot) and ns.Art.Require(STORM.glow.slot) and ns.Art.Path("globeMask")) then
		return nil
	end
	if s then
		s.loaded = true
		s.glow:SetTexture(ns.Art.Path(STORM.glow.slot), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		s.frontGlow:SetTexture(ns.Art.Path(STORM.glow.slot), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		s.core:SetTexture(ns.Art.Path(STORM.core.slot), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		s.frontCore:SetTexture(ns.Art.Path(STORM.core.slot), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		return s
	end
	local front = Layer(g.parent)
	front:SetAllPoints(g.frame)
	front:SetFrameLevel(LevelOf("glass"))
	front:Hide()
	local mask = front:CreateMaskTexture()
	mask:SetTexture(ns.Art.Path("globeMask"), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(front)
	s = {
		front = front, loaded = true, lit = false,
		glow = Sprite(a.frame, STORM.glow.slot, 4), core = Sprite(a.frame, STORM.core.slot, 5),
		frontGlow = Sprite(front, STORM.glow.slot, 0), frontCore = Sprite(front, STORM.core.slot, 1),
	}
	if not (s.glow and s.core and s.frontGlow and s.frontCore) then return nil end
	s.all = { s.glow, s.core, s.frontGlow, s.frontCore }
	s.frontGlow:AddMaskTexture(mask)
	s.frontCore:AddMaskTexture(mask)
	a.storm = s
	return s
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
			if r.storm then r.storm.front:SetFrameLevel(LevelOf("glass")) end
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
			for _, style in pairs(u.styles or {}) do
				StyleLevels(style)
				style.size = nil -- sized again on its next frame
			end
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
		for _, h in pairs(g.heals) do HealLevels(g, h) end
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
		if LookOf(effect) == look and Enabled(effect) and GlobeFor(effect.globe) == g then
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
	local tint = TINTS[TintOf(was)] or TINTS.holy
	inst.shatter, inst.shatterSeed = now, math.floor(now * 7) % 97
	inst.shatterSat, inst.shatterHot = tint.sat, tint.hot
	-- A shield break of its own, if the skill has one and its sheet loaded; else the Shatter.
	local name = BreakOf(was)
	local spec = SHIELD_BREAKS[name]
	local fx = spec and ShieldArt(name) and EnsureShieldBreak(inst, name) or nil
	inst.breakFx, inst.breakName = fx, fx and name or "shatter"
	inst.shatterSeconds = fx and spec.seconds or SHATTER
	-- Whatever the last break left painted stays out of this one.
	if inst.fx then inst.fx.shatter:SetAlpha(0) end
	for _, tex in ipairs({ inst.ring, inst.ringHot }) do tex:SetAlpha(0) end
	for _, shard in ipairs(inst.shards) do
		shard.tex:SetAlpha(0)
		shard.hot:SetAlpha(0)
	end
	for _, b in pairs(inst.shieldBreaks or {}) do b.tex:SetAlpha(0) end
	local k = fx and spec.tk or 0.65 -- the rendered shards sit between the tint's two colours
	inst.shatterMix = {
		tint.sat[1] + (tint.hot[1] - tint.sat[1]) * k,
		tint.sat[2] + (tint.hot[2] - tint.sat[2]) * k,
		tint.sat[3] + (tint.hot[3] - tint.sat[3]) * k,
	}
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
		local tint = TINTS[TintOf(effect)] or TINTS.holy
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
			if changed == effect.key then
				Show(inst, effect, st, reason)
			else
				-- Settings can change the colour of something already lit.
				local tint = TINTS[TintOf(effect)] or TINTS.holy
				inst.satTo, inst.hotTo = tint.sat, tint.hot
			end
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

local function PlayFlare(part, tint, style, strength)
	local g = GlobeFor(part.globe)
	if not g then return end
	-- A heal takes the place of an "in" burst; going out, or if it can't draw here, the burst.
	if style and style ~= "burst" and part.dir == "in" and CanDrawHeal(g, style) then
		local h = EnsureHeal(g, style)
		h.started, h.tint, h.strength = GetTime(), tint or part.tint, strength
		Wake()
		return
	end
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
	slot.started, slot.tint, slot.dir = GetTime(), tint or part.tint, part.dir
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

-- One skill's preview (the options' Preview buttons): its whole life, on its own, through test
-- mode, ending the way that skill really ends. Then the real buffs come back by themselves.
local skillRun

-- What happens after the cast, in seconds from it, and when the preview is over. Only real
-- damage shields break (Watch.lua IconLost), so a skill merely dressed as a shell runs out.
local function SkillScript(effect)
	if effect.look == "flare" then return {}, 3 end
	-- Before a short test buff runs out on its own, or there is nothing left to end.
	local ending = math.min(5, (tonumber(Opt().testLength) or 30) - 0.5)
	if effect.absorb or effect.kind == "absorb" then return { { math.min(2.5, ending - 1), "hit" }, { ending, "break" } }, 7 end
	if effect.fragile then return { { ending, "spend" } }, 7 end
	if effect.group then return { { ending, "judge" } }, 7 end
	return { { 4, "fade" } }, 11.5 -- "fade" leaves 6.5 seconds: the blink, then out
end

local function ForgetSkillRun()
	skillRun = nil
	ns.GlobeAura.previewKey = nil
end

local function StopSkillRun()
	local keepTest = skillRun.keepTest
	ForgetSkillRun()
	if keepTest then
		ns.Watch.Test("clear")
	else
		ns.Watch.SetTest(false)
	end
end

local function SkillStep(now)
	-- Test mode hides the real buffs, and combat can't read them back: never linger into it.
	if InCombatLockdown() or now >= skillRun.stop then
		StopSkillRun()
		return
	end
	local t = now - skillRun.start
	for i, step in ipairs(skillRun.steps) do
		if t >= step[1] and not skillRun.done[i] then
			skillRun.done[i] = true
			if step[2] == "hit" then
				ns.GlobeAura.Hit()
			else
				ns.Watch.Test(step[2])
			end
		end
	end
end

-- Plays one skill by its effect key. Clicking again, or for another skill, starts over.
function ns.GlobeAura.PreviewSkill(key)
	local effect = ns.Watch.Effect(key)
	if not effect then return false end
	if InCombatLockdown() then
		ns.Print("previews wait until you are out of combat")
		return false
	end
	if preview then ns.GlobeAura.SetPreview(false) end
	-- Test mode left on by hand stays on afterwards.
	local keepTest
	if skillRun then
		keepTest = skillRun.keepTest
	else
		keepTest = ns.Watch.Testing()
	end
	ForgetSkillRun()
	ns.Watch.SetTest(true)
	ns.Watch.Test("clear")
	ns.Watch.Test(key)
	local now = GetTime()
	local steps, seconds = SkillScript(effect)
	skillRun = { start = now, stop = now + seconds, steps = steps, done = {}, keepTest = keepTest }
	ns.GlobeAura.previewKey = key
	Wake()
	return true
end

function ns.GlobeAura.SetPreview(on)
	if on then
		ForgetSkillRun()
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

-- Test mode (Watch.lua) going off ends the showcase and any skill's preview too.
function ns.GlobeAura.OnTest(on)
	if not on then
		ForgetSkillRun()
		if preview then
			preview = nil
			ns.GlobeAura.preview = false
		end
	end
	Evaluate("reading")
end

-- The anyone's-shield shell stays lit once absorbs are proven, gated to nothing while there is
-- no shield. With a readable zero there is nothing to draw, so it needn't keep the driver
-- running; the next absorb event wakes it (Hit). In combat the amount is secret: it animates.
local function ShellResting(s, now)
	local st = s.st
	if not s.effect or s.effect.kind ~= "absorb" or not st or st.source ~= "reading" then return false end
	if s.level ~= s.target or (s.shatter and now - s.shatter < (s.shatterSeconds or SHATTER)) then return false end
	local ok, amount = pcall(UnitGetTotalAbsorbs, "player")
	return ok and not ns.Secret(amount) and amount ~= nil and amount <= 0
end

-- The shell takes a hit: a ripple runs out from the blow and the crystal flares. From
-- UNIT_ABSORB_AMOUNT_CHANGED (or the showcase and test mode). False if no shield is up.
function ns.GlobeAura.Hit()
	local any = false
	local now = GetTime()
	local angle = math.rad(30 + 120 * Hash(now * 3.7))
	for _, g in pairs(globes) do
		for _, sh in ipairs(g.looks.shell) do
			if sh.effect then
				-- The event that comes with gaining the shield is not a blow.
				if not (sh.ignite and now - sh.ignite < IGNITE) then
					sh.hit, sh.hitAngle = now, angle
				end
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
			local first, keys, shatter, breakName = nil, {}, nil, nil
			for _, inst in ipairs(g.looks[look]) do
				if inst.effect then keys[inst.rank + 1] = inst.effect.key end
				if inst.shatter then shatter, breakName = inst.shatter, inst.breakName end
			end
			for _, inst in ipairs(g.looks[look]) do
				if inst.effect and inst.rank == 0 then first = inst end
			end
			out[name][look] = { key = first and first.effect.key, level = first and first.level or 0, shatter = shatter, keys = keys,
				calm = first and first.calm or 0, style = first and first.style, breakName = breakName }
		end
		local flares = 0
		for _, f in ipairs(g.flares) do if f.started then flares = flares + 1 end end
		out[name].flares = flares
		local heals = {}
		for heal, h in pairs(g.heals) do if h.started then heals[heal] = true end end
		out[name].heals = heals
	end
	return out
end

local last
function ns.GlobeAura.Step()
	local now = GetTime()
	local dt = last and math.max(0, math.min(0.1, now - last)) or 0
	last = now
	if preview then PreviewStep(now) end
	if skillRun then SkillStep(now) end
	local busy = preview ~= nil or skillRun ~= nil
	for _, g in pairs(globes) do
		for _, inst in ipairs(g.looks.radiate) do
			if AnimateRadiate(g, inst, now, dt) then busy = true end
		end
		for _, inst in ipairs(g.looks.shell) do
			if AnimateShell(g, inst, now, dt) and not ShellResting(inst, now) then busy = true end
		end
		for _, inst in ipairs(g.looks.surge) do
			if AnimateSurge(g, inst, now, dt) then busy = true end
		end
		for _, f in ipairs(g.flares) do
			if AnimateFlare(g, f, now) then busy = true end
		end
		if AnimateHeals(g, now) then busy = true end
	end
	if not busy then
		last = nil
		driver:SetScript("OnUpdate", nil)
	end
end

-- Draw the sheets for a moment on a one-pixel holder, nearly invisible, so the client has them
-- on the GPU before the first shield breaks; a break can't wait for a 2048 texture to load.
local warm
local function WarmBreak()
	if not warm then
		warm = CreateFrame("Frame", nil, UIParent)
		warm:SetFrameStrata("BACKGROUND")
		warm:SetSize(1, 1)
		warm:SetPoint("CENTER")
		warm:EnableMouse(false)
		warm.tex = {}
		for name in pairs(BREAK) do
			local tex = warm:CreateTexture(nil, "BACKGROUND")
			tex:SetBlendMode("ADD")
			tex:SetAllPoints()
			tex:SetAlpha(0.01)
			warm.tex[name] = tex
		end
	end
	for name, spec in pairs(BREAK) do warm.tex[name]:SetTexture(ns.Art.Path(spec.slot)) end
	warm:Show()
	if C_Timer and C_Timer.After then
		C_Timer.After(BREAK_WARM, function() warm:Hide() end)
	else
		warm:Hide()
	end
end

-- The rendered break: built only while its option is on, and given up (back to the drawn
-- shards and ripple) if a sheet won't load. Nothing touches the sheets while it's off.
local function PrepareBreak()
	local opt = Opt()
	local want = opt.enabled and opt.renderedBreak ~= false
	local ready = want and ns.Art.Require(BREAK.shatter.slot) and ns.Art.Require(BREAK.hit.slot) and true or false
	for _, g in pairs(globes) do
		for _, s in ipairs(g.looks.shell) do
			if ready and not s.fx then
				local made = s.breakMade
				if made then
					for name, spec in pairs(BREAK) do
						made[name]:SetTexture(ns.Art.Path(spec.slot), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
					end
				else
					made = {
						shatter = Sprite(s.levelFrames.shards, BREAK.shatter.slot, 2),
						hit = Sprite(s.levelFrames.front, BREAK.hit.slot, 6),
					}
					s.breakMade = made
				end
				s.fx = made
				-- Whatever the drawn shards last showed stays out of the rendered break.
				for _, shard in ipairs(s.shards) do
					shard.tex:SetAlpha(0)
					shard.hot:SetAlpha(0)
				end
			elseif not ready and s.fx then
				s.fx.shatter:SetTexture(nil)
				s.fx.hit:SetTexture(nil)
				s.fx = nil
			end
		end
	end
	if ready and not ns.GlobeAura.breakWarm then
		ns.GlobeAura.breakWarm = true
		WarmBreak()
	elseif not ready and warm then
		ns.GlobeAura.breakWarm = nil
		for _, tex in pairs(warm.tex) do tex:SetTexture(nil) end
		warm:Hide()
	end
end

-- Load the sheets of every surge style a skill you can have uses (and let go of the others),
-- and build it on its globes now, so its first use doesn't wait for a 2048 texture.
local warmStyles
local function WarmSheets(slots)
	if not warmStyles then
		warmStyles = CreateFrame("Frame", nil, UIParent)
		warmStyles:SetFrameStrata("BACKGROUND")
		warmStyles:SetSize(1, 1)
		warmStyles:SetPoint("CENTER")
		warmStyles:EnableMouse(false)
		warmStyles.tex = {}
		warmStyles.slotOf = {}
	end
	for i, slot in ipairs(slots) do
		local tex = warmStyles.tex[i]
		if not tex then
			tex = warmStyles:CreateTexture(nil, "BACKGROUND")
			tex:SetBlendMode("ADD")
			tex:SetAllPoints()
			tex:SetAlpha(0.01)
			warmStyles.tex[i] = tex
		end
		tex:SetTexture(ns.Art.Path(slot))
		warmStyles.slotOf[i] = slot
	end
	warmStyles:Show()
	if C_Timer and C_Timer.After then
		C_Timer.After(BREAK_WARM, function() warmStyles:Hide() end)
	else
		warmStyles:Hide()
	end
end

-- Let go of warmed-up copies of sheets nothing uses any more.
local function ForgetWarm(slots)
	if not warmStyles then return end
	for i, tex in pairs(warmStyles.tex) do
		for _, slot in ipairs(slots) do
			if warmStyles.slotOf[i] == slot then
				tex:SetTexture(nil)
				warmStyles.slotOf[i] = nil
			end
		end
	end
end

-- Rendered lightning, for characters who can have a storm effect showing as a radiance: the
-- sheets to warm now, if they aren't yet. Test mode loads them on first use instead. Let go of
-- them when nothing wants them, unless a storm is on the globe right now.
local stormWarmed
local function PrepareStorm()
	local _, class = UnitClass("player")
	local wanted = Opt().renderedStorm ~= false
	if wanted then
		wanted = false
		for _, effect in ipairs(ns.Watch.EFFECTS) do
			if effect.storm and Enabled(effect) and (effect.class == class or effect.class == "ANY") and LookOf(effect) == "radiate" then
				wanted = true
				break
			end
		end
	end
	if wanted then
		if not stormWarmed and ns.Art.Require(STORM.core.slot) and ns.Art.Require(STORM.glow.slot) then
			stormWarmed = true
			return { STORM.core.slot, STORM.glow.slot }
		end
		return {}
	end
	local showing = false
	for _, g in pairs(globes) do
		for _, a in ipairs(g.looks.radiate) do
			local effect = a.effect or a.lastEffect
			if a.level > 0 and effect and effect.storm and Opt().renderedStorm ~= false then showing = true end
		end
	end
	if showing then return {} end
	stormWarmed = nil
	for _, g in pairs(globes) do
		for _, a in ipairs(g.looks.radiate) do
			if a.storm and a.storm.loaded then
				HideFlip(a)
				a.storm.loaded = false
				for _, tex in ipairs(a.storm.all) do tex:SetTexture(nil) end
			end
		end
	end
	if warmStyles then
		for i, tex in pairs(warmStyles.tex) do
			local slot = warmStyles.slotOf[i]
			if slot == STORM.core.slot or slot == STORM.glow.slot then
				tex:SetTexture(nil)
				warmStyles.slotOf[i] = nil
			end
		end
	end
	return {}
end

local warmed = {}
local function PrepareStyles()
	local want = {}
	local _, class = UnitClass("player")
	for _, effect in ipairs(ns.Watch.EFFECTS) do
		if Enabled(effect) and (effect.class == class or effect.class == "ANY") then
			local look, style = LookOf(effect)
			local g = look == "surge" and style ~= "swirl" and GlobeFor(effect.globe)
			if g and CanDraw(g, style) then
				want[style] = want[style] or {}
				want[style][g] = true
			end
		end
	end
	local slots = {}
	for style, onGlobes in pairs(want) do
		for g in pairs(onGlobes) do
			for i, u in ipairs(g.looks.surge) do
				-- The healing looks have many sprites; a second or third of one builds when it first shows.
				if i == 1 or not NEW_STYLE[style] then EnsureStyle(g, u, style) end
			end
		end
		if not warmed[style] then
			warmed[style] = true
			for _, slot in ipairs(STYLE_SLOTS[style]) do slots[#slots + 1] = slot end
		end
	end
	-- The same for one-off heals.
	local healWant = {}
	for _, effect in ipairs(ns.Watch.EFFECTS) do
		if effect.look == "flare" and Enabled(effect) and (effect.class == class or effect.class == "ANY") then
			local _, heal = LookOf(effect)
			if heal ~= "burst" then
				for _, part in ipairs(effect.flare or {}) do
					local g = part.dir == "in" and GlobeFor(part.globe)
					if g and CanDrawHeal(g, heal) then
						healWant[heal] = healWant[heal] or {}
						healWant[heal][g] = true
					end
				end
			end
		end
	end
	for heal, onGlobes in pairs(healWant) do
		for g in pairs(onGlobes) do EnsureHeal(g, heal) end
		if not warmed[heal] then
			warmed[heal] = true
			for _, slot in ipairs(HEAL_SLOTS[heal]) do slots[#slots + 1] = slot end
		end
	end
	-- The same for shield looks and breaks. A break is only wanted by a shield that can really break.
	local shieldWant = {}
	local function WantShield(name, g)
		if SHIELD_SLOTS[name] and ShieldArt(name) then
			shieldWant[name] = shieldWant[name] or {}
			shieldWant[name][g] = true
		end
	end
	for _, effect in ipairs(ns.Watch.EFFECTS) do
		if Enabled(effect) and (effect.class == class or effect.class == "ANY") then
			local look, style = LookOf(effect)
			local g = look == "shell" and GlobeFor(effect.globe)
			if g then
				if style then WantShield(style, g) end
				if effect.absorb or effect.kind == "absorb" then WantShield(BreakOf(effect), g) end
			end
		end
	end
	for name, onGlobes in pairs(shieldWant) do
		for g in pairs(onGlobes) do
			for i, s in ipairs(g.looks.shell) do
				if SHIELD_BREAKS[name] then
					EnsureShieldBreak(s, name)
				elseif i == 1 then -- a second or third of the look builds when it first shows
					EnsureShieldLook(s, name)
				end
			end
		end
		if not warmed[name] then
			warmed[name] = true
			for _, slot in ipairs(SHIELD_SLOTS[name]) do slots[#slots + 1] = slot end
		end
	end
	for _, slot in ipairs(PrepareStorm()) do slots[#slots + 1] = slot end
	if #slots > 0 then WarmSheets(slots) end
	-- What no skill uses any more is released, unless something is showing it right now.
	for _, g in pairs(globes) do
		for _, u in ipairs(g.looks.surge) do
			for style, s in pairs(u.styles or {}) do
				if not (want[style] and want[style][g]) and u.shownStyle ~= style and not s.released then
					Release(s)
					warmed[style] = nil
				end
			end
		end
		for heal, h in pairs(g.heals) do
			if not (healWant[heal] and healWant[heal][g]) and not h.started and not h.released then
				Release(h)
				warmed[heal] = nil
			end
		end
		-- Shield art nothing wants: let go of it, unless it is on the glass or mid-break now.
		for _, s in ipairs(g.looks.shell) do
			for name, r in pairs(s.shieldLooks or {}) do
				local showing = s.drawnLook == name and s.level > 0
				if not (shieldWant[name] and shieldWant[name][g]) and not showing and not r.released then
					Release(r)
				end
			end
			for name, b in pairs(s.shieldBreaks or {}) do
				local breaking = s.breakName == name and s.shatter and GetTime() - s.shatter < (s.shatterSeconds or SHATTER)
				if not (shieldWant[name] and shieldWant[name][g]) and not breaking and not b.released then
					Release(b)
				end
			end
		end
	end
	for name, slots in pairs(SHIELD_SLOTS) do
		if not shieldWant[name] and warmed[name] then
			warmed[name] = nil
			ForgetWarm(slots)
		end
	end
end

function ns.GlobeAura.ApplySettings()
	if not driver then return end
	PrepareBreak()
	PrepareStyles()
	Evaluate(nil)
	Wake()
end

local function BuildGlobe(frame)
	-- Its looks live in the globe's pod, so they scale with it (Core.lua PlacePods).
	local g = { frame = frame, parent = frame:GetParent(), size = frame:GetWidth() }
	g.looks = { radiate = {}, shell = {}, surge = {} }
	for i = 1, STACK do
		g.looks.radiate[i] = BuildRadiate(g)
		g.looks.shell[i] = BuildShell(g)
		g.looks.surge[i] = BuildSurge(g)
	end
	g.flares = { BuildFlare(g), BuildFlare(g), BuildFlare(g) }
	g.heals = {}
	return g
end

function ns.GlobeAura.Init()
	if not ns.HealthGlobe or not ns.ResourceGlobe or not ns.Watch or not ns.Watch.OnChange then return end
	globes.health = BuildGlobe(ns.HealthGlobe)
	globes.resource = BuildGlobe(ns.ResourceGlobe)
	ns.GlobeAura.Layout()
	PrepareBreak()
	PrepareStyles()
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
				local tint = effect.hot and TintOf(effect) or nil
				local style
				if effect.look == "flare" then
					local _, chosen = LookOf(effect)
					style = chosen
				end
				for _, part in ipairs(effect.flare or {}) do PlayFlare(part, tint, style, effect.strength) end
			end
			return
		end
		local g = GlobeFor(effect.globe)
		local look = LookOf(effect)
		if g and g.looks[look] then Refresh(g, look, reason, key) end
	end)
	Evaluate("reading")
end
