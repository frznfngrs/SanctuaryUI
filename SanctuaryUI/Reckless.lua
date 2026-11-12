SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.Reckless = ns.Reckless or {}
local R = ns.Reckless

-- Slashes, a globe aura look (listed with the others in Options > Globe auras > Skills): a tally
-- of ember claw slashes burnt into a globe's glass while a buff is up. They rake in one after
-- another as it lands, and each swing of yours that lands burns one off: it flares white-hot,
-- throws sparks down its line and the globe's rim pulses. What is left blinks in the last
-- seconds and gutters out with the buff.
--
-- Made for Reckless Swings (warrior: costs health, the next 4 melee attacks make extra rage,
-- 8 s), whose default it is: `tally = 4` in WatchEffects.lua. Any buff can be set to it.
--
-- GlobeAura.lua's LookOf names the look ("radiate" with the style "tally": the quiet Radiance
-- behind the globe is part of it, and GlobeAura draws that and the cast's flares). This file
-- draws the slashes and follows the skill through Watch.lua's state, so its toggle, its look
-- choice, its Preview button and test mode all work as for any other look.
--
-- Swings come from PLAYER_SWING, which fires as each one lands (SwingTimer.lua uses it too).
-- A preview has no swings, so in test mode the marks burn off on a timer.

local WHITE = { 1.0, 0.95, 0.82 }
local FALLBACK = { sat = { 1.0, 0.3, 0.05 }, hot = { 1.0, 0.7, 0.35 } }
local MARKS = 4 -- cells on the sheet (tools/build_reckless_art.py)
local ARRIVE, STAGGER = 0.16, 0.07 -- each slash's strike, and the gap to the next
local BURN = 0.45 -- a spent slash burning off
local FADE = 0.4 -- unspent ones guttering out at the end
local BLINK_LAST = 2 -- seconds
local SPARKS = 5 -- per spent slash
local SPARK_LIFE = 0.5
local TEST_EVERY, TEST_FIRST = 1.25, 0.9 -- previews: a mark burns off this often
-- The stroke's direction on screen, x right and y up (build_reckless_art.py ALONG).
local DIR_X, DIR_Y = -0.3987, -0.9171
local SPACING = 0.150
local CENTRE_X = -0.05 -- the tally sits left of the middle, clear of the angel (build_reckless_art.py)
local LENGTHS = { 0.50, 0.66, 0.62, 0.46 }

local function Smooth(x)
	x = math.max(0, math.min(1, x))
	return x * x * (3 - 2 * x)
end

local function Hash(n)
	local x = math.sin(n * 12.9898 + 78.233) * 43758.5453
	return x - math.floor(x)
end

-- Colour first, alpha last: on this client a texture's vertex alpha and SetAlpha are one value.
local function Paint(tex, c, alpha)
	tex:SetVertexColor(c[1], c[2], c[3])
	tex:SetAlpha(math.max(0, math.min(1, alpha)))
end

-- The effect's globe, as GlobeAura.lua picks it: health, else the resource globe.
local function GlobeOf(effect)
	return effect.globe == "health" and ns.HealthGlobe or ns.ResourceGlobe
end

-- Does this effect show as Slashes right now, and may it show at all.
local function Wanted(effect)
	local opt = ns.DB().globeAuras
	if not (opt and opt.enabled and opt.effects and opt.effects[effect.key]) then return false end
	if not (ns.GlobeAura and ns.GlobeAura.LookOf) then return false end
	local _, style = ns.GlobeAura.LookOf(effect)
	return style == "tally"
end

local sets = {} -- globe -> its frame and textures, built the first time a tally shows there

local function Build(globe)
	if sets[globe] then return sets[globe] end
	if R.failed then return nil end
	if not globe or not ns.Art.Require("recklessMarks") or not ns.Art.Path("globeMask") then return nil end
	local set = { marks = {}, sparks = {} }
	local ok, err = pcall(function()
		local frame = CreateFrame("Frame", nil, globe:GetParent())
		frame:SetAllPoints(globe)
		frame:EnableMouse(false)
		local mask = frame:CreateMaskTexture()
		mask:SetTexture(ns.Art.Path("globeMask"), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		mask:SetAllPoints(globe)
		local function Tex(slot, sublevel, masked)
			local tex = frame:CreateTexture(nil, "ARTWORK", nil, sublevel)
			tex:SetTexture(ns.Art.Path(slot), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
			tex:SetBlendMode("ADD")
			tex:SetPoint("CENTER", globe, "CENTER")
			if masked then tex:AddMaskTexture(mask) end
			if tex.SetSnapToPixelGrid then
				tex:SetSnapToPixelGrid(false)
				tex:SetTexelSnappingBias(0)
			end
			tex:SetAlpha(0)
			return tex
		end
		local inset = 0.5 / 2048
		for i = 1, MARKS do
			local glow, core = Tex("recklessMarks", 0, true), Tex("recklessMarks", 1, true)
			local l, r = (i - 1) / MARKS + inset, i / MARKS - inset
			glow:SetTexCoord(l, r, inset * 2, 0.5 - inset * 2)
			core:SetTexCoord(l, r, 0.5 + inset * 2, 1 - inset * 2)
			set.marks[i] = { glow = glow, core = core }
		end
		if ns.Art.Path("globeRim") then set.rim = Tex("globeRim", 2, false) end
		if ns.Art.Path("mote") then
			for i = 1, SPARKS * 2 do set.sparks[i] = { tex = Tex("mote", 3, false), born = -10 } end
		end
		frame:Hide()
		set.frame, set.globe = frame, globe
	end)
	if not ok then
		R.failed = true
		R.lastError = tostring(err)
		if ns.LogError then ns.LogError("reckless", R.lastError) end
		return nil
	end
	sets[globe] = set
	R.built = true
	return set
end

---------------------------------------------------------------------------

local driver
local run -- { key, spec, start, expires, left, marks = { state, at }, test }

local function Stop()
	run = nil
	for _, set in pairs(sets) do set.frame:Hide() end
	if driver then driver:Hide() end
end

-- Sparks thrown down the slash's line from where it tapers.
local function Throw(i, now)
	local size = run.set.globe:GetWidth()
	local across = (i - (MARKS + 1) / 2) * SPACING
	-- Perpendicular to the stroke, screen coordinates (y up).
	local px, py = -DIR_Y, DIR_X
	local used = 0
	for n, spark in ipairs(run.set.sparks) do
		if now - spark.born > SPARK_LIFE and used < SPARKS then
			used = used + 1
			local seed = now * 7.1 + n * 3.7 + i
			local along = (Hash(seed) - 0.35) * LENGTHS[i] * 0.8
			spark.born = now
			spark.x = (CENTRE_X + px * across + DIR_X * along) * size
			spark.y = (py * across + DIR_Y * along) * size
			local speed = (0.5 + 0.9 * Hash(seed + 1)) * size
			local lean = (Hash(seed + 2) - 0.5) * 0.9
			spark.vx = (DIR_X + px * lean) * speed
			spark.vy = (DIR_Y + py * lean) * speed
			spark.size = (0.035 + 0.035 * Hash(seed + 3)) * size
		end
	end
end

local function Spend(now)
	if not run or run.left <= 0 then return end
	local i = run.count - run.left + 1
	run.left = run.left - 1
	local mark = run.marks[i]
	if mark and mark.state ~= "burn" then
		mark.state, mark.at = "burn", now
		run.pulseAt = now
		Throw(i, now)
	end
end

local function Step()
	if not run then return Stop() end
	local now = GetTime()
	local set = run.set
	local globe = set.globe
	local size = globe:GetWidth()
	local tint = run.tint
	if run.test and run.left > 0 and now >= run.nextTest then
		run.nextTest = now + TEST_EVERY
		Spend(now)
	end
	local left = run.expires and (run.expires - now) or nil
	local blink = 1
	if left and left < BLINK_LAST and not run.ending then
		blink = 0.45 + 0.55 * (0.5 + 0.5 * math.sin(now * 2 * math.pi * 4))
	end
	local alive = false
	for i = 1, MARKS do
		local tex, mark = set.marks[i], run.marks[i]
		local glow, core, scale = 0, 0, 1
		local coreColor = tint.hot
		if mark then
			local t = now - mark.at
			if mark.state == "in" then
				if t >= 0 then
					local p = math.min(1, t / ARRIVE)
					-- Strikes in oversize and white, and settles into the glass.
					scale = 1.22 - 0.22 * Smooth(p)
					glow, core = 1.3 - 0.4 * p, 1.6 - 0.6 * p
					if p < 0.6 then coreColor = WHITE end
					if p >= 1 then mark.state = "idle" end
				end
				alive = true
			elseif mark.state == "idle" then
				-- Embers: each slash flickers on its own.
				local flicker = 0.82 + 0.12 * math.sin(now * 5.3 + i * 1.9) + 0.06 * math.sin(now * 13.1 + i * 4.3)
				glow, core = 0.9 * flicker * blink, 1.0 * flicker * blink
				alive = true
			elseif mark.state == "burn" then
				local p = math.min(1, t / BURN)
				scale = 1 + 0.16 * Smooth(p)
				local flash = math.max(0, 1 - p / 0.35)
				glow = (1 - p) * (1 - p) * 1.2 + flash * 0.6
				core = (1 - p) ^ 3 * 1.6 + flash
				coreColor = WHITE
				if p >= 1 then mark.state = "gone" else alive = true end
			elseif mark.state == "fade" then
				local p = math.min(1, t / FADE)
				glow, core = (1 - p) * 0.7 * (mark.from or 1), (1 - p) ^ 2 * 0.6 * (mark.from or 1)
				if p >= 1 then mark.state = "gone" else alive = true end
			end
		end
		tex.glow:SetSize(size * scale, size * scale)
		tex.core:SetSize(size * scale, size * scale)
		Paint(tex.glow, tint.sat, glow)
		Paint(tex.core, coreColor, core)
	end
	-- The rim takes the rage in as a slash burns off.
	if set.rim then
		local p = run.pulseAt and (now - run.pulseAt) / 0.4 or 1
		set.rim:SetSize(size * (1.06 - 0.06 * Smooth(p)), size * (1.06 - 0.06 * Smooth(p)))
		Paint(set.rim, tint.hot, p < 1 and (1 - p) * (1 - p) * 0.9 or 0)
		if p < 1 then alive = true end
	end
	for _, spark in ipairs(set.sparks) do
		local t = now - spark.born
		if t < SPARK_LIFE then
			alive = true
			local p = t / SPARK_LIFE
			spark.tex:ClearAllPoints()
			spark.tex:SetPoint("CENTER", globe, "CENTER", spark.x + spark.vx * t, spark.y + spark.vy * t - 1.4 * size * t * t)
			spark.tex:SetSize(spark.size * (1 - 0.5 * p), spark.size * (1 - 0.5 * p))
			Paint(spark.tex, p < 0.3 and WHITE or tint.hot, (1 - p) ^ 1.5)
		else
			spark.tex:SetAlpha(0)
		end
	end
	if not alive then Stop() end
end

local function Start(effect, st)
	local set = Build(GlobeOf(effect))
	if not set then return end
	if run and run.set ~= set then run.set.frame:Hide() end
	local now = GetTime()
	local tints = ns.GlobeAura and ns.GlobeAura.TINTS
	local count = math.max(1, math.min(MARKS, tonumber(effect.tally) or MARKS))
	run = { key = effect.key, set = set, tint = tints and tints[effect.tint] or FALLBACK, count = count, start = now,
		expires = st and st.expires or nil, left = count, marks = {},
		test = ns.Watch.Testing and ns.Watch.Testing() or false, nextTest = now + TEST_FIRST }
	for i = 1, count do
		run.marks[i] = { state = "in", at = now + (i - 1) * STAGGER }
	end
	if ns.Cluster then pcall(set.frame.SetFrameLevel, set.frame, ns.Cluster:GetFrameLevel() + ns.LEVEL.rail) end
	if not driver then
		driver = CreateFrame("Frame")
		driver:SetScript("OnUpdate", Step)
	end
	set.frame:Show()
	driver:Show()
end

-- The buff went (timed out, spent, died, or the preview ended): what is left gutters out.
local function Finish()
	if not run or run.ending then return end
	run.ending = true
	run.left = 0
	local now = GetTime()
	for _, mark in ipairs(run.marks) do
		if mark.state == "idle" or mark.state == "in" then
			mark.state, mark.at, mark.from = "fade", now, 1
		end
	end
end

local function OnWatch(key, st, reason)
	local effect = ns.Watch.Effect and ns.Watch.Effect(key)
	if not effect then return end
	if st and st.up and Wanted(effect) then
		if not run or run.ending or run.key ~= key or reason == "refreshed" or reason == "cast" then
			Start(effect, st)
		else
			run.expires = st.expires or run.expires
		end
	elseif run and run.key == key then
		Finish()
	end
end

-- The look or the toggle changed under a tally that is up.
function R.ApplySettings()
	if not run or run.ending then return end
	local effect = ns.Watch.Effect and ns.Watch.Effect(run.key)
	if not effect or not Wanted(effect) then Finish() end
end

-- One line for /sanctuary check.
function R.Status()
	return ("reckless: %s%s"):format(R.failed and "failed" or R.built and (run and (run.left .. " marks left") or "idle") or "not built",
		R.lastError and (" (" .. R.lastError .. ")") or "")
end

function R.Init()
	if not (ns.Watch and ns.Watch.OnChange) then return end
	ns.Watch.OnChange(OnWatch)
	local events = CreateFrame("Frame")
	pcall(events.RegisterEvent, events, "PLAYER_SWING")
	events:SetScript("OnEvent", function()
		if run and not run.test and not run.ending then Spend(GetTime()) end
	end)
end
