SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.StatueEyes = ns.StatueEyes or {}
local S = ns.StatueEyes

-- The console statues' eyes glow, wisps of light streaming off them, while a buff you choose is
-- on you: the angel's blue under Blessing of Wisdom and the gargoyle's red under Blessing of
-- Might unless you name other buffs in the options (a name, a spell ID, or several with commas).
--
-- In combat the client hides your buffs from addons, so nothing here reads one to decide. Each
-- statue is an aura slot in one of the client's own containers, filtered to the chosen spell
-- IDs (a filter the client allows for buffs on yourself). The client shows and hides the slot
-- and runs the animations handed to it, so the glow is exact in combat too. The costs, as in
-- Pollution.lua: the motion is a client-run flipbook, the glow goes out at once when the buff
-- ends, and a change of settings made in combat waits for it to end.
--
-- The filter wants spell IDs and a buff has one per rank, so a name is looked up once by
-- walking the client's spell IDs, a little each frame, and the answer kept per account until
-- the game is patched. A buff seen on you under a wanted name adds its ID too.

-- The golden light on the angel's wings (AngelRadiance.lua) is a third effect here, shown the
-- same way: it has no buff until you name one.

-- corner, span: the art's top left in frame.png px and the px it covers
-- (tools/build_statue_eyes.py STATUES). layers: a slot each; "behind" draws under the console.
local STATUES = {
	angel = { label = "Angel", pod = "resource", corner = { 1410, 90 }, span = 32, layers = { "front" }, body = "eyesAngelBody", core = "eyesAngelCore" },
	gargoyle = { label = "Gargoyle", pod = "health", corner = { 170, 102 }, span = 32, layers = { "front" }, body = "eyesGargoyleBody", core = "eyesGargoyleCore" },
	wings = { label = "Angel's wings", pod = "resource", corner = ns.AngelRadiance.CORNER, span = ns.AngelRadiance.SPAN, layers = { "front", "behind" }, wings = true },
}
local ORDER = { "angel", "gargoyle", "wings" }
S.ORDER = ORDER
local FLIP = { rows = 8, cols = 8, frames = 64, seconds = 2.4 }
local FADE_IN = 0.6
local PALE = 0.7 -- how far the hot centre is taken from the colour toward white

local SCAN_MAX = 1500000 -- spell IDs walked when looking a name up (past the newest the game has)
local SCAN_BUDGET = 3 -- ms a frame
local LEARN_EVERY = 1

local built = {} -- key -> { box, slots = { layer -> slot }, textures }
local previews = {}
local pending -- settings changed in combat
local scan -- { at, names = { lower -> list } }
local learnDue

local GetSpellName = (C_Spell and C_Spell.GetSpellName) or function(id)
	return (GetSpellInfo(id))
end

local function Config(key)
	local db = ns.DB()
	return db.statueEyes and db.statueEyes[key]
end

local function NoteError(where, err)
	S.lastError = where .. ": " .. tostring(err)
	if ns.LogError then ns.LogError("statue eyes", S.lastError) end
end

---------------------------------------------------------------------------
-- Names to spell IDs.

local function Cache()
	local global = ns.db and ns.db.global
	if not global then return {} end
	local build = (GetBuildInfo and select(2, GetBuildInfo())) or "?"
	if not global.spellIDs or global.spellIDs.build ~= build then
		global.spellIDs = { build = build, names = {} }
	end
	return global.spellIDs.names
end

local function Trim(text)
	return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- The names and IDs typed into a box: { ids = set, names = { lower, ... } }.
local function Parse(text)
	local wanted = { ids = {}, names = {} }
	for token in tostring(text or ""):gmatch("[^,;]+") do
		token = Trim(token)
		local id = tonumber(token)
		if id then
			wanted.ids[math.floor(id)] = true
		elseif token ~= "" then
			wanted.names[#wanted.names + 1] = token:lower()
		end
	end
	return wanted
end

local StartScan

-- The spell IDs to show for, and how many names are still being looked up or matched nothing.
local function Resolve(text)
	local wanted = Parse(text)
	local cache = Cache()
	local ids, looking, unknown = wanted.ids, 0, 0
	for _, name in ipairs(wanted.names) do
		local known = cache[name]
		if known then
			if #known == 0 then unknown = unknown + 1 end
			for _, id in ipairs(known) do ids[id] = true end
		else
			looking = looking + 1
			StartScan(name)
		end
	end
	return ids, looking, unknown
end

local scanner
function StartScan(name)
	if scan and scan.names[name] then return end
	if scan and scan.at == 1 then
		scan.names[name] = {}
		return
	elseif scan then
		-- A name asked for mid-walk waits for the next walk, so it sees every ID.
		scan.after = scan.after or {}
		scan.after[name] = true
		return
	end
	scan = { at = 1, names = { [name] = {} } }
	if not scanner then
		scanner = CreateFrame("Frame")
		scanner:SetScript("OnUpdate", function()
			if not scan then
				scanner:Hide()
				return
			end
			local stop = debugprofilestop() + SCAN_BUDGET
			local id, names = scan.at, scan.names
			while id <= SCAN_MAX do
				for _ = 1, 400 do
					local found = GetSpellName(id)
					if found and not ns.Secret(found) then
						local list = names[found:lower()]
						if list then list[#list + 1] = id end
					end
					id = id + 1
				end
				if debugprofilestop() > stop then break end
			end
			scan.at = id
			if id > SCAN_MAX then
				local cache = Cache()
				for name, list in pairs(names) do cache[name] = list end
				local after = scan.after
				scan = nil
				for name in pairs(after or {}) do StartScan(name) end
				S.ApplySettings()
				S.NotifyOptions()
			end
		end)
	end
	scanner:Show()
end

function S.NotifyOptions()
	local registry = LibStub and LibStub("AceConfigRegistry-3.0", true)
	if registry then pcall(registry.NotifyChange, registry, "SanctuaryUI") end
end

-- A buff on you under a wanted name whose ID the walk did not find (out of combat only).
local function Learn()
	if InCombatLockdown() or not ns.ReadAuras then return end
	local wantedNames
	for _, key in ipairs(ORDER) do
		local cfg = Config(key)
		if cfg and cfg.enabled then
			for _, name in ipairs(Parse(cfg.spells).names) do
				wantedNames = wantedNames or {}
				wantedNames[name] = true
			end
		end
	end
	if not wantedNames then return end
	local list, _, denied = ns.ReadAuras("player", "HELPFUL")
	if denied or not list then return end
	local cache, changed = Cache(), false
	for _, aura in ipairs(list) do
		local id, name = aura.spellId, aura.name
		if id ~= nil and name ~= nil and not ns.Secret(id) and not ns.Secret(name) then
			local known = cache[name:lower()]
			if known and wantedNames[name:lower()] then
				local have = false
				for _, other in ipairs(known) do
					if other == id then have = true break end
				end
				if not have then
					known[#known + 1] = id
					changed = true
				end
			end
		end
	end
	if changed then S.ApplySettings() end
end

---------------------------------------------------------------------------
-- The glow.

local function ArtReady(statue)
	if statue.wings then return ns.AngelRadiance.ArtReady() end
	return ns.Art.Require(statue.body) and ns.Art.Require(statue.core) and true or false
end

local function Colours(key)
	local cfg = Config(key)
	local c = (cfg and cfg.color) or { 1, 1, 1 }
	local r, g, b = c[1] or 1, c[2] or 1, c[3] or 1
	return r, g, b, r + (1 - r) * PALE, g + (1 - g) * PALE, b + (1 - b) * PALE
end

-- The eyes take the colour chosen in the options; the wings' gold is in their art.
local function Tint(textures, key)
	if not textures then return end
	local r, g, b, pr, pg, pb = Colours(key)
	textures.body:SetVertexColor(r, g, b)
	textures.core:SetVertexColor(pr, pg, pb)
end

-- Over the statue, in its pod, so it follows the globes' own scale.
local function Place(frame, statue, layer)
	local metrics = ns.Metrics and ns.Metrics()
	local pod = ns.Pods and ns.Pods[statue.pod]
	if not (metrics and pod) then return false end
	local s = metrics.scale
	frame:ClearAllPoints()
	frame:SetSize(statue.span * s, statue.span * s)
	frame:SetPoint("TOPLEFT", pod, "BOTTOM", statue.corner[1] * s - metrics.width / 2,
		metrics.baseY + metrics.height / 2 - statue.corner[2] * s)
	local level = layer == "behind" and ns.LEVEL.aura or ns.LEVEL.console + 1
	pcall(frame.SetFrameLevel, frame, ns.Cluster:GetFrameLevel() + level)
	return true
end

-- A layer's art and animations on `host`, a slot or a preview frame already placed. Returns
-- the animation groups, and the eyes' textures.
local function Dress(host, statue, layer)
	if statue.wings then
		return ns.AngelRadiance.Dress(layer, host, ns.Metrics().scale)
	end
	local textures = {}
	local loop = host:CreateAnimationGroup()
	loop:SetLooping("REPEAT")
	local fade = host:CreateAnimationGroup()
	fade:SetToFinalAlpha(true)
	for sublevel, part in ipairs({ "body", "core" }) do
		local tex = host:CreateTexture(nil, "ARTWORK", nil, sublevel)
		tex:SetTexture(ns.Art.Path(statue[part]))
		tex:SetAllPoints(host)
		tex:SetBlendMode("ADD")
		textures[part] = tex
		local flip = loop:CreateAnimation("FlipBook")
		flip:SetTarget(tex)
		flip:SetDuration(FLIP.seconds)
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
	return { loop, fade }, textures
end

local function Build(key, ids)
	local statue = STATUES[key]
	local pod = ns.Pods and ns.Pods[statue.pod]
	if not pod then return false end
	if not ArtReady(statue) then
		NoteError("art", key .. " sheets did not load")
		return false
	end
	local made = { slots = {} }
	local ok, err = pcall(function()
		local box = CreateFrame("AuraContainer", nil, pod, "CustomAuraContainerTemplate")
		Place(box, statue)
		for _, layer in ipairs(statue.layers) do
			box:AddAuraSlot(layer, "HELPFUL", {
				candidateFilters = { includeSpellIDs = ids },
				initializeFrame = function(slot)
					made.slots[layer] = slot
					local dressed, why = pcall(function()
						slot:EnableMouse(false)
						Place(slot, statue, layer)
						local groups, textures = Dress(slot, statue, layer)
						if textures then
							made.textures = textures
							Tint(textures, key)
						end
						for _, group in ipairs(groups) do slot:AddAuraShownAnimation(group) end
					end)
					if not dressed then NoteError("slot", why) end
				end,
			})
		end
		box:SetUnit("player")
		made.box = box
	end)
	if not ok then
		NoteError("build", err)
		return false
	end
	built[key] = made
	return true
end

local failed = {}

local function Apply(key)
	local statue, cfg = STATUES[key], Config(key)
	if not cfg then return end
	local ids = Resolve(cfg.spells)
	local on = cfg.enabled == true and next(ids) ~= nil
	local made = built[key]
	if on and not made and not failed[key] then
		if Build(key, ids) then
			made = built[key]
		else
			failed[key] = true
		end
	elseif made then
		for _, layer in ipairs(statue.layers) do
			pcall(made.box.SetAuraSlotCandidateFilters, made.box, layer, { includeSpellIDs = ids })
		end
	end
	if not made then return end
	pcall(made.box.SetEnabled, made.box, on)
	made.box:SetShown(on)
	Place(made.box, statue)
	for layer, slot in pairs(made.slots) do pcall(Place, slot, statue, layer) end
	pcall(Tint, made.textures, key)
end

local function StopPreview(shown)
	for _, group in ipairs(shown.groups) do group:Stop() end
	for _, host in ipairs(shown.hosts) do host:Hide() end
	shown.on = false
end

function S.ApplySettings()
	if InCombatLockdown() then
		pending = true
		return
	end
	pending = nil
	for _, key in ipairs(ORDER) do Apply(key) end
	for key, shown in pairs(previews) do
		for i, host in ipairs(shown.hosts) do Place(host, STATUES[key], STATUES[key].layers[i]) end
		Tint(shown.textures, key)
	end
end

-- What a statue's box is doing, for the options.
function S.Describe(key)
	local cfg = Config(key)
	if not cfg then return "" end
	local ids, looking, unknown = Resolve(cfg.spells)
	local count = 0
	for _ in pairs(ids) do count = count + 1 end
	if looking > 0 then
		return "Looking the spell up..."
	elseif count == 0 then
		return (cfg.spells or "") == "" and "No buff chosen." or "No spell has that name on this client. Check the spelling, or use its spell ID."
	end
	local text = ("Watching for %d spell ID%s (one per rank)."):format(count, count == 1 and "" or "s")
	if unknown > 0 then text = text .. " One of the names matched nothing." end
	if failed[key] then text = text .. " The glow could not be built: " .. tostring(S.lastError) end
	return text
end

-- The look without the buff: the same art and animations on an ordinary frame. key nil or
-- "off" turns every preview off; a statue's key toggles it.
function S.Preview(key)
	if not key or key == "off" then
		for _, shown in pairs(previews) do StopPreview(shown) end
		return true
	end
	local statue = STATUES[key]
	if not statue then return false, "angel, gargoyle or wings" end
	local shown = previews[key]
	if shown and shown.on then
		StopPreview(shown)
		return true, false
	end
	if not shown then
		local pod = ns.Pods and ns.Pods[statue.pod]
		if not pod then return false, "the console is not up" end
		if not ArtReady(statue) then return false, "art did not load" end
		shown = { hosts = {}, groups = {} }
		for i, layer in ipairs(statue.layers) do
			local host = CreateFrame("Frame", nil, pod)
			host:EnableMouse(false)
			shown.hosts[i] = host
			Place(host, statue, layer)
			local ok, groups, textures = pcall(Dress, host, statue, layer)
			if not ok then
				StopPreview(shown)
				NoteError("preview", groups)
				return false, tostring(groups)
			end
			for _, group in ipairs(groups) do shown.groups[#shown.groups + 1] = group end
			shown.textures = textures or shown.textures
		end
		previews[key] = shown
	end
	for i, host in ipairs(shown.hosts) do
		Place(host, statue, statue.layers[i])
		host:Show()
	end
	Tint(shown.textures, key)
	for _, group in ipairs(shown.groups) do group:Play() end
	shown.on = true
	return true, true
end

function S.Previewing(key)
	local shown = previews[key]
	return shown ~= nil and shown.on == true
end

-- One line for /sanctuary check.
function S.Status()
	local parts = {}
	for _, key in ipairs(ORDER) do
		local cfg = Config(key)
		parts[#parts + 1] = ("%s %s%s"):format(key, cfg and cfg.enabled and "on" or "off",
			built[key] and (next(built[key].slots) and ", slot ready" or ", no slot") or "")
	end
	return "statue eyes: " .. table.concat(parts, "; ") .. (S.lastError and (" (" .. S.lastError .. ")") or "")
end

function S.Init()
	local watcher = CreateFrame("Frame")
	watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
	watcher:RegisterUnitEvent("UNIT_AURA", "player")
	watcher:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_REGEN_ENABLED" and pending then S.ApplySettings() end
		learnDue = true
	end)
	local wait = 0
	watcher:SetScript("OnUpdate", function(_, elapsed)
		wait = wait + elapsed
		if wait < LEARN_EVERY then return end
		wait = 0
		if learnDue then
			learnDue = nil
			Learn()
		end
	end)
	S.ApplySettings()
end
