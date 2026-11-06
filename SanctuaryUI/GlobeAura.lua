SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.GlobeAura = ns.GlobeAura or {}

-- Light radiating from behind a globe while a buff is up (Watch.lua says which): gold behind
-- the health globe for Seal of Light, blue behind the mana globe for Seal of Wisdom.
--
-- It sits under the whole globe stack and the console art, so the globe and its metal ring
-- cover the middle and the gargoyle and angel stand in silhouette against it. Layers, all
-- ADD, white art tinted here (tools/build_hud_art.py globe_aura):
--   corona   a bright band hugging the rim over a wide halo, breathing
--   rays     two sets of god rays turning slowly against each other, so they shimmer
--   wisps    licks of flame off the rim in two phases, each drifting out as it fades
--   hot      a tighter, paler copy of the corona: the white-hot edge D3's fire FX have
--   sparks   motes rising off the top of the rim
--   catch    the light wrapping round onto the globe's glass, a faint rim at the top
--
-- Moments:
--   ignite   a cast: a flash ring swells off the rim and the rays flare
--   rekindle a recast while up: a smaller flash
--   gutter   the last seconds before it runs out: the glow sinks and flickers
--   release  judged away: the light bursts outward and is gone in a third of a second
--   fade     ran out, replaced, gone: a soft fade

local SCALE = 2 -- art size, of the globe's diameter (AURA_SCALE in build_hud_art.py)
local MOTES = 7
local GUTTER = 6 -- seconds left when the gutter starts

-- sat: the wide layers. hot: the rim, the flash, the sparks.
local TINTS = {
	holy = { sat = { 1.0, 0.62, 0.14 }, hot = { 1.0, 0.88, 0.55 } },
	arcane = { sat = { 0.16, 0.42, 1.0 }, hot = { 0.62, 0.84, 1.0 } },
}

-- How long each ending takes to fade, by Watch.lua's reason.
local FADE = { consumed = 0.35, expired = 0.9, died = 1.2, replaced = 0.4, gate = 0.5, gone = 0.5 }
local FADE_IN = 0.35
local IGNITE, REKINDLE, RELEASE = 0.8, 0.5, 0.55

local MANA = Enum and Enum.PowerType and Enum.PowerType.Mana or 0

local auras = {} -- "health" / "mana" -> aura
local driver
local preview

local function Opt()
	return ns.DB().globeAuras
end

local function Smoothstep(x)
	x = math.max(0, math.min(1, x))
	return x * x * (3 - 2 * x)
end

local function Hash(n)
	local x = math.sin(n * 12.9898 + 78.233) * 43758.5453
	return x - math.floor(x)
end

-- Texcoords turned by angle about the middle; the art is clamped to clear, so the corners
-- that swing outside it stay empty.
local function Spin(tex, angle)
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

---------------------------------------------------------------------------

local function Build(kind)
	local cluster = ns.Cluster
	local a = { kind = kind, level = 0, target = 0, fade = 0.5 }
	local frame = CreateFrame("Frame", nil, cluster)
	frame:EnableMouse(false)
	frame:Hide()
	a.frame = frame
	a.corona = Sprite(frame, "auraCorona", 0)
	a.raysA = Sprite(frame, "auraRaysA", 1)
	a.raysB = Sprite(frame, "auraRaysB", 2)
	a.wisps = { Sprite(frame, "auraWispsA", 3), Sprite(frame, "auraWispsB", 3) }
	a.hot = Sprite(frame, "auraCorona", 4)
	a.burst = Sprite(frame, "auraRing", 5)
	a.burstHot = Sprite(frame, "auraRing", 6)
	a.motes = {}
	for i = 1, MOTES do
		local tex = Sprite(frame, "mote", 7)
		if tex then a.motes[i] = { tex = tex, cycle = -1 } end
	end
	-- The catch light rides on the glass, above the liquid and under the console art.
	local catch = CreateFrame("Frame", nil, cluster)
	catch:EnableMouse(false)
	catch:Hide()
	a.catchFrame = catch
	local rim = catch:CreateTexture(nil, "ARTWORK")
	if ns.Art.Path("globeRim") then
		rim:SetTexture(ns.Art.Path("globeRim"))
		-- globe-rim.png is brightest at the bottom; flipped, the light comes over the top.
		rim:SetTexCoord(0, 1, 1, 0)
		rim:SetBlendMode("ADD")
		rim:SetAllPoints()
		a.catch = rim
	else
		rim:Hide()
	end
	local tint = TINTS.holy
	a.sat = { unpack(tint.sat) }
	a.hotColor = { unpack(tint.hot) }
	a.satTo, a.hotTo = tint.sat, tint.hot
	a.ok = a.corona ~= nil
	return a
end

local function GlobeOf(kind)
	if kind == "health" then return ns.HealthGlobe end
	-- Testing, the resource globe stands in for mana whatever it holds.
	if ns.Watch.Testing and ns.Watch.Testing() then return ns.ResourceGlobe end
	local powerType = UnitPowerType("player")
	if powerType == MANA or (ns.Globes.IsSplit and ns.Globes.IsSplit()) then
		return ns.ResourceGlobe
	end
end

function ns.GlobeAura.Layout()
	local cluster = ns.Cluster
	if not cluster then return end
	local level = cluster:GetFrameLevel()
	for kind, a in pairs(auras) do
		local globe = ns.HealthGlobe
		if kind == "mana" then globe = ns.ResourceGlobe end
		if globe then
			local size = globe:GetWidth() * SCALE
			a.size, a.radius = size, globe:GetWidth() / 2
			a.frame:ClearAllPoints()
			a.frame:SetPoint("CENTER", globe, "CENTER")
			a.frame:SetSize(size, size)
			a.frame:SetFrameLevel(level + ns.LEVEL.aura)
			a.catchFrame:ClearAllPoints()
			a.catchFrame:SetAllPoints(globe)
			a.catchFrame:SetFrameLevel(level + ns.LEVEL.glass)
		end
	end
end

---------------------------------------------------------------------------
-- Which effect each globe shows, and the moment it changes.

local function Choose(kind)
	local opt = Opt()
	if not opt.enabled or not GlobeOf(kind) then return end
	for _, effect in ipairs(ns.Watch.EFFECTS) do
		if effect.globe == kind and opt.effects[effect.key] then
			local st = ns.Watch.State(effect.key)
			if st and st.up then return effect, st end
		end
	end
end

local function Wake()
	if not driver then return end
	driver:SetScript("OnUpdate", ns.GlobeAura.Step)
end

-- effect, st: what the globe shows now (nil: nothing). reason: why it changed.
local function Show(a, effect, st, reason)
	local now = GetTime()
	if effect then
		local tint = TINTS[effect.tint] or TINTS.holy
		a.satTo, a.hotTo = tint.sat, tint.hot
		if a.effect ~= effect then
			if a.level <= 0.01 then
				-- From dark the colour starts where it ends.
				a.sat = { unpack(tint.sat) }
				a.hotColor = { unpack(tint.hot) }
			end
			a.effect = effect
			if reason == "cast" or reason == "refreshed" then a.ignite = now end
		elseif reason == "refreshed" then
			a.rekindle = now
		end
		a.st = st
		a.target = 1
		a.release = nil
	elseif a.effect then
		a.effect, a.target = nil, 0
		a.fade = FADE[reason] or 0.5
		if reason == "consumed" then a.release = now end
	end
	Wake()
end

local function Evaluate(reason)
	if preview then return end
	for kind, a in pairs(auras) do
		local effect, st = Choose(kind)
		if effect ~= a.effect or (effect and reason) then
			Show(a, effect, st, reason)
		end
	end
end

---------------------------------------------------------------------------
-- Every frame while any aura is lit or fading.

local function Lerp(color, to, k)
	for i = 1, 3 do
		color[i] = color[i] + (to[i] - color[i]) * k
	end
end

local function Animate(a, now, dt)
	if not a.ok then return false end
	local opt = Opt()
	-- Level: eases up on lighting, down at the ending's own pace.
	if a.target > a.level then
		a.level = math.min(a.target, a.level + dt / FADE_IN)
	elseif a.target < a.level then
		a.level = math.max(a.target, a.level - dt / a.fade)
	end
	local releasing = a.release and now - a.release < RELEASE
	-- Dark and staying dark. (Just lit, the level is still 0 on the first frame.)
	if a.level <= 0 and a.target <= 0 and not releasing then
		a.frame:Hide()
		a.catchFrame:Hide()
		return false
	end
	a.frame:Show()
	a.catchFrame:SetShown(opt.catch and a.catch ~= nil)
	local k = math.min(1, dt * 6)
	Lerp(a.sat, a.satTo, k)
	Lerp(a.hotColor, a.hotTo, k)

	local e = Smoothstep(a.level)
	local intensity = tonumber(opt.intensity) or 1
	local size = a.size or 270
	-- Gutter: in the last seconds the glow sinks and flickers, faster as it ends.
	local gutter = 0
	local st = a.effect and a.st
	if st and st.up and st.expires then
		gutter = Smoothstep(1 - (st.expires - now) / GUTTER)
	end
	local period = 2.8 - 1.8 * gutter
	local breath = 0.86 + 0.14 * math.sin(now * 2 * math.pi / period)
	local flicker = 1 - gutter * (0.25 + 0.2 * math.sin(now * 13.7) * math.sin(now * 7.3 + 1))
	local base = e * intensity * flicker

	-- Flashes: a shockwave ring leaves the rim. Ignite and rekindle swell it gently while the
	-- rays flare; a release throws it (and the rays) outward as the light goes.
	local flash, flashSize, flashAlpha = 0, 1, 0
	local function Out(t) return 1 - (1 - t) ^ 3 end
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
	Paint(a.corona, sat, 0.85 * breath * base)
	local rayScale = 1 + 0.5 * blow
	if opt.rays then
		Size(a.raysA, size * rayScale)
		Spin(a.raysA, now * 0.05)
		Paint(a.raysA, sat, 0.85 * base * (0.85 + 0.15 * math.sin(now * 0.9)) * (1 + 1.2 * flash))
		Size(a.raysB, size * 1.04 * rayScale)
		Spin(a.raysB, 1.3 - now * 0.035)
		Paint(a.raysB, hot, 0.4 * base * (0.8 + 0.2 * math.sin(now * 1.3 + 1)) * (1 + flash))
	else
		Paint(a.raysA, sat, 0)
		Paint(a.raysB, hot, 0)
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
			Paint(tex, sat, 0.75 * math.sin(p * math.pi) * base)
		end
	end
	Size(a.hot, size * 0.9)
	Paint(a.hot, hot, 0.55 * breath * base * (1 + 0.6 * flash))
	-- The ring's body in the deep colour, its leading edge white-hot just inside it.
	Size(a.burst, size * flashSize)
	Paint(a.burst, sat, flashAlpha * intensity)
	Size(a.burstHot, size * flashSize * 0.99)
	Paint(a.burstHot, hot, 0.7 * flashAlpha * intensity)
	if a.catch then
		a.catch:SetVertexColor(hot[1], hot[2], hot[3])
		a.catch:SetAlpha(math.min(1, 0.35 * breath * base))
	end

	-- Sparks: rise off the upper rim (the lower half is behind the console), drift out and up,
	-- sway and fade. Each lives one cycle of its own length, then starts somewhere new.
	local r = a.radius or size / (2 * SCALE)
	for i, mote in ipairs(a.motes) do
		if opt.sparks and base > 0 then
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
	return true
end

---------------------------------------------------------------------------
-- Preview: a stand-in loop to judge the look on any class. Health: lit by a cast, gutters
-- and is judged away; mana: lit, rekindled, then runs out.

local LOOP = 12
local function PreviewStep(now)
	local t = (now - preview.start) % LOOP
	local cycle = math.floor((now - preview.start) / LOOP)
	local health, mana = auras.health, auras.mana
	local light, wisdom = ns.Watch.Effect("sealOfLight"), ns.Watch.Effect("sealOfWisdom")
	local loopStart = preview.start + cycle * LOOP
	local function at(key, when, fn)
		if t >= when and preview[key] ~= cycle then
			preview[key] = cycle
			fn()
		end
	end
	at("h1", 0, function() Show(health, light, { up = true, expires = loopStart + 10 }, "cast") end)
	at("h2", 10, function() Show(health, nil, nil, "consumed") end)
	at("m1", 0.6, function() Show(mana, wisdom, { up = true, expires = loopStart + 0.6 + 9 }, "cast") end)
	at("m2", 4, function() Show(mana, wisdom, { up = true, expires = loopStart + 10.5 }, "refreshed") end)
	at("m3", 10.5, function() Show(mana, nil, nil, "expired") end)
end

-- Test mode (Watch.lua) and the loop both drive the globes; only one at a time.
function ns.GlobeAura.OnTest(on)
	if on and preview then ns.GlobeAura.SetPreview(false) end
	Evaluate("reading")
end

function ns.GlobeAura.SetPreview(on)
	if on and ns.Watch.Testing and ns.Watch.Testing() then ns.Watch.SetTest(false) end
	if on then
		preview = { start = GetTime() }
		for _, a in pairs(auras) do
			a.effect, a.target = nil, 0
		end
		Wake()
	else
		preview = nil
		for _, a in pairs(auras) do
			a.effect, a.target, a.fade = nil, 0, 0.4
		end
		Evaluate("reading")
	end
	ns.GlobeAura.preview = preview ~= nil
end

local last
function ns.GlobeAura.Step()
	local now = GetTime()
	local dt = last and math.max(0, math.min(0.1, now - last)) or 0
	last = now
	if preview then PreviewStep(now) end
	local busy = preview ~= nil
	for _, a in pairs(auras) do
		if Animate(a, now, dt) then busy = true end
	end
	if not busy then
		last = nil
		driver:SetScript("OnUpdate", nil)
	end
end

function ns.GlobeAura.ApplySettings()
	if not driver then return end
	if not preview then
		for kind, a in pairs(auras) do
			local effect, st = Choose(kind)
			if effect ~= a.effect then Show(a, effect, st, "reading") end
		end
	end
	Wake()
end

function ns.GlobeAura.Init()
	if not ns.HealthGlobe or not ns.Watch or not ns.Watch.OnChange then return end
	auras.health = Build("health")
	auras.mana = Build("mana")
	ns.GlobeAura.Layout()
	driver = CreateFrame("Frame", nil, ns.Cluster)
	for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "UPDATE_SHAPESHIFT_FORM" }) do
		pcall(driver.RegisterEvent, driver, event)
	end
	pcall(driver.RegisterUnitEvent, driver, "UNIT_DISPLAYPOWER", "player")
	driver:SetScript("OnEvent", function() Evaluate("reading") end)
	-- Size follows the globes (console scale, layout).
	for _, globe in ipairs({ ns.HealthGlobe, ns.ResourceGlobe }) do
		globe:HookScript("OnSizeChanged", ns.GlobeAura.Layout)
	end
	ns.Watch.OnChange(function(key, _, reason)
		local effect = ns.Watch.Effect(key)
		local a = effect and auras[effect.globe]
		if not a or preview then return end
		local chosen, st = Choose(effect.globe)
		-- The globe's own effect changed, or a better one took over or let go.
		if chosen ~= a.effect or chosen == effect then
			Show(a, chosen, st, reason)
		end
	end)
	Evaluate("reading")
end
