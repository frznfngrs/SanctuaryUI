SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.Pollution = ns.Pollution or {}
local P = ns.Pollution

-- Debuffs polluting the health globe: while you carry a debuff of a type, that type's colour
-- bleeds into the liquid, and a cleanse clears it.
--
-- In combat the client hides your auras from addons, so nothing here reads one. Each type is an
-- aura slot in one of the client's own containers, filtered by dispel type. The client shows
-- and hides the slot, and starts the animations handed to AddAuraShownAnimation, so no addon
-- code runs while it is up. That has two costs: all motion is client-run animation (a stepped
-- flipbook, no frame blending), and the slot just vanishes when the debuff goes, so a cleanse
-- is instant. The slot sits inside the liquid's clip frame, so the pollution follows the level
-- without knowing it.
--
-- One slot per type, so types stack. Slots are created in ORDER and later ones draw on top: the
-- dark curse lowest, then the solid disease and poison, with magic's thin threads last.

local KINDS = {
	poison = { label = "Poison", types = { Poison = true }, mix = "pollutionPoisonMix", glow = "pollutionPoisonGlow", seconds = 3.6 },
	disease = { label = "Disease", types = { Disease = true }, mix = "pollutionDiseaseMix", seconds = 3.6 },
	curse = { label = "Curse", types = { Curse = true }, mix = "pollutionCurseMix", glow = "pollutionCurseGlow", seconds = 3.6 },
	magic = { label = "Magic", types = { Magic = true }, mix = "pollutionMagicMix", glow = "pollutionMagicGlow", seconds = 5 },
}
local ORDER = { "curse", "disease", "poison", "magic" }
local FLIP = { rows = 6, cols = 6, frames = 36 }
local FADE_IN = 1.2

local function HealthPool()
	local globe = ns.HealthGlobe
	return globe and globe.pool, globe
end

local function ArtReady(kind)
	return ns.Art.Require(kind.mix) and (not kind.glow or ns.Art.Require(kind.glow)) and ns.Art.Path("globeMask") and true or false
end

local function NoteError(where, err)
	P.lastError = where .. ": " .. tostring(err)
	if ns.LogError then ns.LogError("pollution", P.lastError) end
end

-- The art and its animations on `host`, a slot or the preview frame. Returns the two groups.
local function Dress(host, kind, globe)
	local mask = host:CreateMaskTexture()
	mask:SetTexture(ns.Art.Path("globeMask"), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(globe)
	local function Layer(slot, sublevel, blend)
		local tex = host:CreateTexture(nil, "ARTWORK", nil, sublevel)
		tex:SetTexture(ns.Art.Path(slot))
		tex:SetAllPoints(globe)
		tex:SetBlendMode(blend)
		tex:AddMaskTexture(mask)
		return tex
	end
	local layers = { Layer(kind.mix, 0, "BLEND") }
	if kind.glow then layers[2] = Layer(kind.glow, 1, "ADD") end
	local loop = host:CreateAnimationGroup()
	loop:SetLooping("REPEAT")
	local fade = host:CreateAnimationGroup()
	fade:SetToFinalAlpha(true)
	for _, tex in ipairs(layers) do
		local flip = loop:CreateAnimation("FlipBook")
		flip:SetTarget(tex)
		flip:SetDuration(kind.seconds)
		flip:SetOrder(1)
		flip:SetFlipBookRows(FLIP.rows)
		flip:SetFlipBookColumns(FLIP.cols)
		flip:SetFlipBookFrames(FLIP.frames)
		local alpha = fade:CreateAnimation("Alpha")
		alpha:SetTarget(tex)
		alpha:SetDuration(FADE_IN)
		alpha:SetFromAlpha(0)
		alpha:SetToAlpha(1)
	end
	return loop, fade
end

-- Above the liquid layers, level with the fixed sphere shade, under the surface line.
local function PlaceLevel(frame, level)
	if frame and level then pcall(frame.SetFrameLevel, frame, level) end
end

function P.ApplyLevels()
	if InCombatLockdown() then
		P.levelsPending = true
		return
	end
	local pool = HealthPool()
	if not pool then return end
	local level = pool.frame:GetFrameLevel() + 1
	PlaceLevel(P.box, level)
	for _, slot in pairs(P.slots or {}) do PlaceLevel(slot, level) end
	for _, shown in pairs(P.previews or {}) do PlaceLevel(shown.host, level) end
end

local function InitSlot(slot, kind, globe)
	local ok, err = pcall(function()
		slot:EnableMouse(false)
		slot:ClearAllPoints()
		slot:SetAllPoints(globe)
		local loop, fade = Dress(slot, kind, globe)
		slot:AddAuraShownAnimation(loop)
		slot:AddAuraShownAnimation(fade)
	end)
	if ok then
		P.dressed = (P.dressed or 0) + 1
	else
		NoteError("slot", err)
	end
end

local function Build()
	if P.box or P.failed then return P.box ~= nil end
	local pool, globe = HealthPool()
	if not pool then return false end
	P.slots = {}
	local ok, err = pcall(function()
		local box = CreateFrame("AuraContainer", nil, pool.frame, "CustomAuraContainerTemplate")
		box:SetAllPoints(globe)
		for _, key in ipairs(ORDER) do
			local kind = KINDS[key]
			if ArtReady(kind) then
				box:AddAuraSlot(key, "HARMFUL", {
					candidateFilters = { includeDispelTypes = kind.types },
					initializeFrame = function(slot)
						P.slots[key] = slot
						InitSlot(slot, kind, globe)
					end,
				})
			else
				NoteError("art", key .. " sheets did not load")
			end
		end
		box:SetUnit("player")
		P.box = box
	end)
	if not ok then
		P.failed = true
		NoteError("build", err)
		return false
	end
	P.ApplyLevels()
	return true
end

function P.ApplySettings()
	if InCombatLockdown() then
		P.pending = true
		return
	end
	P.pending = nil
	local on = ns.DB().pollution == true
	if on then Build() end
	if P.box then
		pcall(P.box.SetEnabled, P.box, on)
		P.box:SetShown(on)
	end
end

-- Stand-in for checking the look without a debuff: the same art and animations on an ordinary
-- frame, one per type, built the first time it is asked for. key nil turns it off.
function P.Preview(key)
	for _, shown in pairs(P.previews or {}) do
		shown.loop:Stop()
		shown.fade:Stop()
		shown.host:Hide()
	end
	P.previewKey = nil
	if not key then return true end
	local kind = KINDS[key]
	if not kind then return false, "unknown type" end
	local pool, globe = HealthPool()
	if not pool then return false, "no liquid on the health globe" end
	if not ArtReady(kind) then return false, "art did not load" end
	P.previews = P.previews or {}
	local shown = P.previews[key]
	if not shown then
		local host = CreateFrame("Frame", nil, pool.frame)
		host:SetAllPoints(globe)
		host:EnableMouse(false)
		local ok, loop, fade = pcall(Dress, host, kind, globe)
		if not ok then
			host:Hide()
			NoteError("preview", loop)
			return false, tostring(loop)
		end
		shown = { host = host, loop = loop, fade = fade }
		P.previews[key] = shown
		P.ApplyLevels()
	end
	shown.host:Show()
	shown.loop:Play()
	shown.fade:Play()
	P.previewKey = key
	return true
end

-- One line for /sanctuary check.
function P.Status()
	local state
	if P.failed then
		state = "failed"
	elseif P.box then
		state = ("%d of %d slots ready"):format(P.dressed or 0, #ORDER)
	else
		state = "not built"
	end
	return ("pollution: %s, %s%s"):format(ns.DB().pollution and "on" or "off", state, P.lastError and (" (" .. P.lastError .. ")") or "")
end

function P.Init()
	local watcher = CreateFrame("Frame")
	watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
	watcher:SetScript("OnEvent", function()
		if P.pending then P.ApplySettings() end
		if P.levelsPending then
			P.levelsPending = nil
			P.ApplyLevels()
		end
	end)
	P.ApplySettings()
end
