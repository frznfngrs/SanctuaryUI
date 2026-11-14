SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.Freeze = ns.Freeze or {}
local F = ns.Freeze

-- Frozen: while a freezing debuff is on you, ice crystallises over the health globe and the
-- liquid under it stops dead. When the debuff goes, the crust bursts off and the liquid lurches
-- back into motion.
--
-- The look, back to front:
--   frost     inside the liquid's clip, so it follows the level: a cold dark cast with rime and
--             fracture lines, turning the stopped liquid to frozen blood rather than pink
--   crust     over the glass, under the console art: the rendered ice (tools/blender/
--             globe_freeze.py). It grows in as a flipbook (blades from the rim, then the plates
--             rim to centre), then holds as one sharp still
--   glints    three lights' worth of facet highlights faded in turn, so light seems to travel
--             over the crystal while everything else is still; and the cracks, which flash as
--             the crust locks and again as it breaks
--   shards    over the console art: the crust's own plates flying off, as a flipbook
-- The health number draws above all of it (ns.LEVEL.chrome), and the crust's art is thinned to
-- a window in the middle (tools/build_freeze_art.py), so the level and the number stay readable:
-- the user asked for that on 2026-11-12.
-- The stopping is Liquid.lua's: it reads pool.frozen (0..1) and scales its clocks by it.
--
-- It is also a globe aura look, "Frozen", listed with the others in Options > Globe auras >
-- Skills: a skill set to it ices the globe while its buff is up (see SkillSource below).
--
-- Unlike Pollution.lua this is ordinary addon code on an OnUpdate, so it can ease and react,
-- but it has to know a freeze is on, and in combat the client hides your debuffs. What it can
-- learn, in order of trust:
--   * out of combat, your debuffs are readable: matched by spell ID and by name (FROST_IDS,
--     FROST_WORDS)
--   * in combat, the loss-of-control list (roots, stuns: Frost Nova, Freezing Trap). If the
--     client lets the spell be read it is matched the same way. If it is secret, nothing says
--     which spell took control, and the globe freezes only with "Any loss of control" on
--   * a debuff seen before combat started is followed through the fight (Follow below): it
--     ends when Blizzard's debuff frame loses an icon at its end time, and if none goes then,
--     it was renewed (a mob chain-casting Frostbolt) and the ice holds until an icon goes
-- Slows that only chill (Frostbolt, Cone of Cold) and first land mid-fight are therefore not
-- seen until combat ends. F.Status() and the log say which path answered.

local GROW = 0.85 -- seconds for the crust to close
local LOCK_FLASH = 0.55 -- the cracks' flash as it locks
local SHATTER = 0.9
local MELT = 0.3 -- a crust that never closed just fades
local SHATTER_SPAN = 1.7 -- the shatter cell's width, in globes (globe_freeze.py HALF_SHATTER)
local BOOK = { cols = 5, cell = 409, sheet = 2048, frames = 25 }
local GLINT_RATE = 0.55 -- rad/s: one light every four seconds or so
local GLINT_GAIN = 0.75
local PREVIEW = 6
local RENEW_WINDOW = 0.5 -- seconds: an icon going this close to a frost debuff's end is it ending

-- Frost spells that land on players. IDs are exact in any language; names are for everything
-- else (creature spells, ranks missed here), and only work where the name can be read.
local FROST_IDS = {}
for _, id in ipairs({
	122, 865, 6131, 10230, -- Frost Nova
	116, 205, 837, 7322, 8406, 8407, 8408, 10179, 10180, 10181, 25304, -- Frostbolt
	120, 8492, 10159, 10160, 10161, -- Cone of Cold
	12484, 12485, 12486, -- Blizzard's chill
	6136, 7321, 12494, 12579, -- Chilled, Frostbite, Winter's Chill
	8056, 8058, 10472, 10473, -- Frost Shock
	3355, 14308, 14309, 13810, -- Freezing Trap, Frost Trap
	8034, 8037, 10458, 16352, 16353, -- Frostbrand Attack
}) do FROST_IDS[id] = true end
-- Whole words or word starts only: "ice" must not match "Justice". Not "hypothermia": that is
-- Ice Block's lockout, and would keep the globe iced after the block breaks.
local FROST_WORDS = { "%f[%a]frost", "%f[%a]freez", "%f[%a]frozen", "%f[%a]chill", "%f[%a]ice%f[%A]", "%f[%a]icy%f[%A]", "%f[%a]glacial", "%f[%a]winter" }

local function Secret(x)
	return issecretvalue and issecretvalue(x) or false
end

local function Smooth(x)
	x = math.max(0, math.min(1, x))
	return x * x * (3 - 2 * x)
end

local function IsFrost(spellID, name)
	if spellID ~= nil and not Secret(spellID) and FROST_IDS[spellID] then return true end
	if type(name) == "string" and not Secret(name) then
		local lower = name:lower()
		for _, word in ipairs(FROST_WORDS) do
			if lower:find(word) then return true end
		end
	end
	return false
end

---------------------------------------------------------------------------
-- The frames.

local ART = { "freezeIce", "freezeGrow", "freezeShatter", "freezeGlint", "freezeLiquid" }

local function ArtReady()
	if F.artReady == nil then
		local ready = ns.Art.Path("globeMask") and true or false
		for _, slot in ipairs(ART) do
			if not ns.Art.Require(slot) then ready = false end
		end
		F.artReady = ready
	end
	return F.artReady
end

local function Unsnap(tex)
	if tex.SetSnapToPixelGrid then
		tex:SetSnapToPixelGrid(false)
		tex:SetTexelSnappingBias(0)
	end
end

local function Cell(tex, i)
	local row = math.floor(i / BOOK.cols)
	local col = i - row * BOOK.cols
	local inset = 0.5 / BOOK.sheet
	tex:SetTexCoord(col * BOOK.cell / BOOK.sheet + inset, (col + 1) * BOOK.cell / BOOK.sheet - inset,
		row * BOOK.cell / BOOK.sheet + inset, (row + 1) * BOOK.cell / BOOK.sheet - inset)
end

-- Colour first, alpha last: on this client a texture's vertex alpha and SetAlpha are one value.
local function Show(tex, alpha, r, g, b)
	if r then tex:SetVertexColor(r, g, b) end
	tex:SetAlpha(math.max(0, math.min(1, alpha)))
end

local function Build()
	if F.built then return true end
	if F.failed then return false end
	local globe = ns.HealthGlobe
	local pool = globe and globe.pool
	if not pool or not ArtReady() then return false end
	local ok, err = pcall(function()
		local function Masked(frame)
			local mask = frame:CreateMaskTexture()
			mask:SetTexture(ns.Art.Path("globeMask"), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
			mask:SetAllPoints(globe)
			return mask
		end
		local function Tex(frame, slot, sublevel, blend, mask)
			local tex = frame:CreateTexture(nil, "ARTWORK", nil, sublevel)
			tex:SetTexture(ns.Art.Path(slot), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
			tex:SetAllPoints(globe)
			tex:SetBlendMode(blend)
			if mask then tex:AddMaskTexture(mask) end
			Unsnap(tex)
			tex:SetAlpha(0)
			return tex
		end

		-- In the liquid's clip, so the frost ends at the level.
		local inner = CreateFrame("Frame", nil, pool.frame)
		inner:SetAllPoints(globe)
		inner:EnableMouse(false)
		F.frost = Tex(inner, "freezeLiquid", 0, "BLEND", Masked(inner))

		-- Over the glass: the ice covers the glass's highlight, as a crust on it would.
		local over = CreateFrame("Frame", nil, globe:GetParent())
		over:SetAllPoints(globe)
		over:EnableMouse(false)
		local mask = Masked(over)
		F.ice = Tex(over, "freezeIce", 1, "BLEND", mask)
		F.grow = Tex(over, "freezeGrow", 0, "BLEND", mask)
		F.glints = {}
		for i = 1, 4 do
			local tex = Tex(over, "freezeGlint", 2, "ADD", mask)
			local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
			local inset = 0.5 / 1024
			tex:SetTexCoord(col * 0.5 + inset, col * 0.5 + 0.5 - inset, row * 0.5 + inset, row * 0.5 + 0.5 - inset)
			F.glints[i] = tex
		end
		F.cracks = F.glints[4]
		F.glints[4] = nil

		-- Over the console art: the pieces fly out past the rim.
		local shards = CreateFrame("Frame", nil, globe:GetParent())
		shards:SetAllPoints(globe)
		shards:EnableMouse(false)
		local burst = shards:CreateTexture(nil, "ARTWORK")
		burst:SetTexture(ns.Art.Path("freezeShatter"), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		burst:SetPoint("CENTER", globe, "CENTER")
		Unsnap(burst)
		burst:SetAlpha(0)
		F.burst = burst
		F.inner, F.over, F.shards = inner, over, shards
		inner:Hide()
		over:Hide()
		shards:Hide()
	end)
	if not ok then
		F.failed = true
		F.lastError = tostring(err)
		if ns.LogError then ns.LogError("freeze", F.lastError) end
		return false
	end
	F.built = true
	F.ApplyLevels()
	return true
end

function F.ApplyLevels()
	if not F.built or not ns.Cluster then return end
	local pool = ns.HealthGlobe and ns.HealthGlobe.pool
	local base = ns.Cluster:GetFrameLevel()
	-- Above Pollution's slots in the liquid; between the glass and the console art; over the art.
	if pool then pcall(F.inner.SetFrameLevel, F.inner, pool.frame:GetFrameLevel() + 2) end
	pcall(F.over.SetFrameLevel, F.over, base + ns.LEVEL.rail)
	pcall(F.shards.SetFrameLevel, F.shards, base + ns.LEVEL.console + 1)
end

---------------------------------------------------------------------------
-- The animation. F.phase: nil (off), "grow", "hold", "melt", "shatter".

local driver

local function Pool()
	return ns.HealthGlobe and ns.HealthGlobe.pool
end

local function SetFrozen(amount)
	local pool = Pool()
	if pool then pool.frozen = amount > 0.001 and amount or nil end
end

local function Stop()
	F.phase = nil
	SetFrozen(0)
	if F.built then
		F.inner:Hide()
		F.over:Hide()
		F.shards:Hide()
	end
	if driver then driver:Hide() end
end

local function Glints(now, gain)
	for i, tex in ipairs(F.glints) do
		local s = math.sin(now * GLINT_RATE + i * 2.094)
		Show(tex, s > 0 and s * s * s * GLINT_GAIN * gain or 0, 0.82, 0.94, 1)
	end
end

local function Step(_, dt)
	local now = GetTime()
	local t = now - (F.phaseAt or now)
	local phase = F.phase
	if phase == "grow" then
		local p = math.min(1, t / GROW)
		F.cover = p
		Cell(F.grow, math.min(BOOK.frames - 1, math.floor(p * BOOK.frames)))
		Show(F.grow, 1)
		Show(F.ice, 0)
		Show(F.frost, Smooth(p / 0.8))
		Show(F.cracks, 0)
		Glints(now, p * p)
		-- The liquid slows as the ice closes over it, and is still just before it locks.
		SetFrozen(Smooth(p / 0.85))
		if p >= 1 then
			F.phase, F.phaseAt = "hold", now
		end
	elseif phase == "hold" then
		F.cover = 1
		-- The flipbook's last cell hands over to the sharp still.
		local hand = math.min(1, t / 0.12)
		Show(F.ice, 1)
		Show(F.grow, 1 - hand)
		Show(F.frost, 1)
		local flash = math.max(0, 1 - t / LOCK_FLASH)
		Show(F.cracks, flash * flash + 0.07 + 0.04 * math.sin(now * 0.9), 0.8, 0.93, 1)
		Glints(now, 1 + 1.6 * flash)
		SetFrozen(1)
	elseif phase == "melt" then
		local p = math.min(1, t / MELT)
		local k = (1 - p) * (F.meltFrom or 1)
		Show(F.grow, k)
		Show(F.ice, 0)
		Show(F.frost, k)
		Show(F.cracks, 0)
		Glints(now, 0)
		SetFrozen(k)
		if p >= 1 then Stop() end
	elseif phase == "shatter" then
		local p = math.min(1, t / SHATTER)
		Cell(F.burst, math.min(BOOK.frames - 1, math.floor(p * BOOK.frames)))
		Show(F.burst, 1)
		Show(F.ice, 0)
		Show(F.grow, 0)
		-- The cracks light as it goes, then nothing is left on the glass.
		local flash = math.max(0, 1 - t / 0.22)
		Show(F.cracks, flash, 0.86, 0.95, 1)
		Glints(now, 2.2 * flash)
		Show(F.frost, 1 - Smooth(t / 0.35))
		SetFrozen(1 - Smooth(t / 0.45))
		if p >= 1 then Stop() end
	else
		Stop()
	end
end

local function Begin(phase)
	F.phase, F.phaseAt = phase, GetTime()
	if not driver then
		driver = CreateFrame("Frame")
		driver:SetScript("OnUpdate", Step)
	end
	local size = ns.HealthGlobe:GetWidth() * SHATTER_SPAN
	F.burst:SetSize(size, size)
	F.inner:Show()
	F.over:Show()
	F.shards:SetShown(phase == "shatter")
	if phase ~= "shatter" then Show(F.burst, 0) end
	driver:Show()
	Step(driver, 0)
end

-- on: is a freeze on you. Safe to call every time something is learned.
function F.Set(on, why)
	on = on and true or false
	if on == (F.on or false) then return end
	F.on = on
	if ns.Log then ns.Log("freeze: %s (%s)", on and "frozen" or "thawed", tostring(why)) end
	if on then
		if not Build() then return end
		Begin("grow")
	elseif F.phase == "hold" or (F.phase == "grow" and (F.cover or 0) > 0.6) then
		Begin("shatter")
		-- Let go: the liquid lurches as it comes free.
		local pool = Pool()
		if pool and pool.Kick then pool:Kick(0.09) end
	elseif F.phase == "grow" then
		F.meltFrom = 1
		Begin("melt")
	end
end

---------------------------------------------------------------------------
-- Knowing. Three sources, each a flag with an optional end time; any one freezes the globe.

local sources = {} -- name -> { untilTime = number or nil }

local function Resolve()
	local now = GetTime()
	local debuffs = ns.DB().freeze
	local on, why = F.preview and true or false, F.preview and "preview" or F.endWhy or "nothing left"
	for name, src in pairs(sources) do
		if src.untilTime and src.untilTime <= now then
			sources[name] = nil
			if not on then why = tostring(src.why or name) .. " ran out" end
		elseif src.skill or debuffs then
			-- The debuff setting gates what is learned about debuffs, not a skill set to Frozen.
			on, why = true, src.why or name
		end
	end
	F.Set(on, why)
	if not on then F.endWhy = nil end
end

-- Frozen as a globe aura look: a skill set to it in Options > Globe auras > Skills (Ice Block,
-- say) ices the health globe while it is up. Watch.lua follows the skill; GlobeAura.lua's
-- LookOf answers "frozen" and draws nothing itself.
local function SkillWanted(effect)
	local opt = ns.DB().globeAuras
	if not (opt and opt.enabled and opt.effects and opt.effects[effect.key]) then return false end
	return ns.GlobeAura and ns.GlobeAura.LookOf and ns.GlobeAura.LookOf(effect) == "frozen" or false
end

local function SkillSource(effect)
	local st = ns.Watch.State and ns.Watch.State(effect.key)
	local name = "skill:" .. effect.key
	if st and st.up and SkillWanted(effect) then
		sources[name] = { skill = true, untilTime = st.expires, why = effect.label or effect.key }
	else
		sources[name] = nil
	end
end

local function SkillSources()
	if not (ns.Watch and ns.Watch.EFFECTS and ns.Watch.State) then return end
	for _, effect in ipairs(ns.Watch.EFFECTS) do
		if effect.look ~= "flare" then SkillSource(effect) end
	end
end

-- Your debuffs, where the client lets them be read (out of combat). true/false, or nil when
-- they can't be read at all; then the latest end time, a name, and the frost debuff's full
-- length (what a renewal would give it again).
local function ScanAuras()
	if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
	local found, untilTime, label, length
	for i = 1, 40 do
		local ok, data = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HARMFUL")
		if not ok then return nil end
		if data == nil then break end
		local id, name = data.spellId, data.name
		if Secret(id) and Secret(name) then return nil end
		if IsFrost(id, name) then
			found = true
			label = not Secret(name) and name or tostring(id)
			local ends, duration = data.expirationTime, data.duration
			if ends ~= nil and not Secret(ends) and ends > 0 then
				if not untilTime or ends > untilTime then
					untilTime = ends
					length = duration ~= nil and not Secret(duration) and duration > 0 and duration or nil
				end
			else
				untilTime, length = nil, nil
				break
			end
		end
	end
	return found or false, untilTime, label, length
end

-- In combat the debuffs above can't be read, but Blizzard's debuff frame still shows them, and
-- how many icons it has can be counted. So the frost debuff last read (held) is followed by its
-- icons: one going within RENEW_WINDOW of its end time is it running out. If none goes, it
-- was renewed (Frostbolt again), and the ice holds: its new end is guessed from the latest
-- aura change since the last application, and the first icon to go after that ends it. With
-- no debuff icons at all it is certainly gone (dispelled). The count is only trusted once it
-- has shown at least one icon while the frost was on, else the end time alone decides.
local held -- { ends, length, base (when it was last applied), label, trust, extended, extendedAt }
local icons, lostAt, auraEventAt = 0, -math.huge, nil

local function Hold(untilTime, length, label)
	if not untilTime then
		held = nil
		return
	end
	icons, lostAt = ns.DebuffIcons(), -math.huge
	held = { ends = untilTime, length = length, base = length and (untilTime - length) or GetTime(), label = label,
		trust = icons > 0 }
end

local function Drop(why)
	if ns.Log then ns.Log("freeze: %s ended in combat (%s)", tostring(held and held.label), why) end
	held = nil
	sources.aura = nil
	F.endWhy = why
end

local function Follow(now)
	if not (held and sources.aura and F.auraPath == "hidden") then return end
	local count = ns.DebuffIcons()
	if count < icons then lostAt = now end
	icons = count
	if count > 0 then held.trust = true end
	if not held.trust then
		if now >= held.ends then Drop("ran out") end
		return
	end
	if count == 0 then return Drop("no debuffs left") end
	if held.extended and lostAt > held.extendedAt then return Drop("an icon went after a renewal") end
	if now < held.ends - RENEW_WINDOW then return end
	if lostAt >= held.ends - RENEW_WINDOW then return Drop("ran out") end
	if now < held.ends + RENEW_WINDOW then return end
	-- Nothing went when it should have, so it was renewed, after its last application and no
	-- later than the latest aura change.
	local at = auraEventAt
	if not (held.length and at and at > held.base + 0.05) then return Drop("ran out") end
	held.base, held.ends = at, math.max(at + held.length, now + RENEW_WINDOW)
	held.extended, held.extendedAt = true, now
	F.renewed = (F.renewed or 0) + 1
	if ns.Log then ns.Log("freeze: %s was renewed in combat, holding (about %.1fs)", tostring(held.label), held.ends - now) end
end

-- Roots and stuns on you. Returns frost (a readable frost spell), unknown (something has
-- control and the client won't say what), and the longest time left it would give.
local function ScanControl()
	local L = C_LossOfControl
	if not (L and L.GetActiveLossOfControlDataCount and L.GetActiveLossOfControlData) then return false, false end
	local ok, count = pcall(L.GetActiveLossOfControlDataCount)
	if not ok or type(count) ~= "number" or Secret(count) then return false, false end
	local frost, unknown, left
	for i = 1, count do
		local got, data = pcall(L.GetActiveLossOfControlData, i)
		if got and data ~= nil then
			local id, text = data.spellID, data.displayText
			if Secret(id) and Secret(text) then
				unknown = true
				-- What the client does still say about it, kept for /sanctuary check and logged
				-- once per kind: the type (ROOT, STUN...) if readable, and the priority and
				-- display type, which the client documents as never secret. If these tell a
				-- root from a stun, roots alone could ice the globe.
				local function Say(v)
					if v == nil then return "nil" end
					if Secret(v) then return "secret" end
					return tostring(v)
				end
				local seen = ("type %s, priority %s, display %s"):format(Say(data.locType), Say(data.priority), Say(data.displayType))
				F.controlSeen = F.controlSeen or {}
				if not F.controlSeen[seen] then
					F.controlSeen[seen] = true
					F.controlLast = seen
					if ns.Log then ns.Log("freeze: hidden loss of control: %s", seen) end
				end
			else
				local name
				if not Secret(id) and id and C_Spell and C_Spell.GetSpellName then
					local okName, spell = pcall(C_Spell.GetSpellName, id)
					if okName then name = spell end
				end
				if IsFrost(id, name) then
					frost = true
					local remain = data.timeRemaining
					if remain ~= nil and not Secret(remain) then left = math.max(left or 0, remain) end
				end
			end
		elseif not got then
			unknown = true
		end
	end
	return frost or false, unknown or false, left
end

local function Learn(event)
	local now = GetTime()
	local found, untilTime, label, length = ScanAuras()
	if found ~= nil then
		F.auraPath = "readable"
		if not found and sources.aura then F.endWhy = tostring(sources.aura.why) .. " gone" end
		sources.aura = found and { untilTime = untilTime, why = label } or nil
		auraEventAt = nil
		if found then Hold(untilTime, length, label) else held = nil end
	else
		-- Hidden (combat): what was seen before is followed (Follow); without an end time it
		-- can't be trusted to still be there.
		F.auraPath = "hidden"
		if event == "UNIT_AURA" then auraEventAt = now end
		if held and sources.aura then
			sources.aura.untilTime = nil
		else
			held, sources.aura = nil, nil
		end
	end
	local frost, unknown, left = ScanControl()
	if frost then
		F.controlPath = "readable"
		sources.control = { untilTime = left and (now + left) or nil, why = "loss of control" }
	elseif unknown then
		F.controlPath = "secret"
		sources.control = ns.DB().freezeAnyControl and { why = "loss of control (spell hidden)" } or nil
		if not F.loggedSecret and ns.Log then
			F.loggedSecret = true
			ns.Log("freeze: the client hides which spell took control of you in combat (%s)", tostring(event))
		end
	else
		sources.control = nil
	end
	Resolve()
end

---------------------------------------------------------------------------

-- /sanctuary freeze [hold|off]: the whole look without the debuff. Plain: freezes, holds a few
-- seconds, then breaks.
function F.Preview(mode)
	if mode == "off" then
		F.preview = nil
		Resolve()
		return true
	end
	if not Build() then
		return false, F.lastError or (ArtReady() and "no liquid on the health globe" or "art did not load")
	end
	F.previewToken = (F.previewToken or 0) + 1
	local token = F.previewToken
	if F.on then
		-- Already frozen: show the freeze again from the start.
		F.on = false
		Stop()
	end
	F.preview = true
	Resolve()
	if mode ~= "hold" then
		C_Timer.After(PREVIEW, function()
			if F.previewToken == token then
				F.preview = nil
				Resolve()
			end
		end)
	end
	return true
end

function F.ApplySettings()
	SkillSources()
	if ns.DB().freeze then
		Learn("settings")
	else
		sources.aura, sources.control, held = nil, nil, nil
		Resolve()
	end
end

-- One line for /sanctuary check.
function F.Status()
	local path = F.auraPath or "unread"
	if held and path == "hidden" then
		path = path .. (held.trust and (", following %s by its icon%s"):format(tostring(held.label), held.extended and ", renewed" or "")
			or ", waiting for the debuff frame")
	end
	if F.renewed then path = path .. (", %d renewal%s seen"):format(F.renewed, F.renewed == 1 and "" or "s") end
	return ("freeze: %s, %s, debuffs %s, loss of control %s%s"):format(ns.DB().freeze and "on" or "off",
		F.failed and "failed" or F.built and (F.phase or "idle") or "not built", path,
		(F.controlPath or "none seen") .. (F.controlLast and (" [" .. F.controlLast .. "]") or ""), F.lastError and (" (" .. F.lastError .. ")") or "")
end

function F.Init()
	local watcher = CreateFrame("Frame")
	watcher:RegisterUnitEvent("UNIT_AURA", "player")
	watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
	watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
	watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
	watcher:RegisterEvent("PLAYER_DEAD")
	for _, event in ipairs({ "LOSS_OF_CONTROL_ADDED", "LOSS_OF_CONTROL_UPDATE", "PLAYER_CONTROL_GAINED" }) do
		pcall(watcher.RegisterEvent, watcher, event)
	end
	watcher:SetScript("OnEvent", function(_, event)
		if not ns.DB().freeze then return end
		Learn(event)
	end)
	-- End times pass without an event.
	local since = 0
	watcher:SetScript("OnUpdate", function(_, dt)
		since = since + dt
		if since < 0.1 then return end
		since = 0
		if next(sources) then
			Follow(GetTime())
			Resolve()
		end
	end)
	if ns.Watch and ns.Watch.OnChange then
		ns.Watch.OnChange(function(key)
			local effect = ns.Watch.Effect and ns.Watch.Effect(key)
			if effect and effect.look ~= "flare" then
				SkillSource(effect)
				Resolve()
			end
		end)
	end
	F.ApplySettings()
end
