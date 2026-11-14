SanctuaryUI = SanctuaryUI or {}
SANCTUARYUI = "SanctuaryUI"
local ns = SanctuaryUI

BINDING_HEADER_SANCTUARYUI = "SanctuaryUI"
BINDING_NAME_SANCTUARYUIHEARTH = "Hearthstone"

function ns.SetLocked(locked)
	ns.DB().locked = locked
	ns.Refresh()
	ns.Print(locked and "frames locked" or "frames unlocked: drag the console or a bar's mover")
	local registry = LibStub("AceConfigRegistry-3.0", true)
	if registry then
		registry:NotifyChange("SanctuaryUI")
	end
end

-- Secret values (this client hides some unit, aura, cast, cooldown and totem data from addons
-- in combat) throw on any truth test, comparison or arithmetic, so `x and ...`, `not x` and
-- `x or default` all fail on them. Check ns.Secret first. A secret is never nil.
function ns.Secret(value)
	return issecretvalue and issecretvalue(value) or false
end

-- Incoming heals and damage shields on a unit, through the client's calculator: heals clamp to
-- missing health, shields to what's left after them, and clamped says the shield is bigger than
-- that room. In combat they come back secret, for StatusBars to take as they are. Older
-- clients: the plain totals, clamped here when readable. Globes (player) and target plate.
local healCalc
function ns.IncomingHeals(unit, health, maxHealth)
	if healCalc == nil then
		healCalc = false
		if CreateUnitHealPredictionCalculator and UnitGetDetailedHealPrediction then
			local ok, calc = pcall(CreateUnitHealPredictionCalculator)
			if ok and calc then
				local clamp = Enum and Enum.UnitIncomingHealClampMode and Enum.UnitIncomingHealClampMode.MissingHealth
				if clamp then pcall(calc.SetIncomingHealClampMode, calc, clamp) end
				-- Shields: what fits in the missing health left after the heals.
				clamp = Enum and Enum.UnitDamageAbsorbClampMode and Enum.UnitDamageAbsorbClampMode.MissingHealth
				if clamp then pcall(calc.SetDamageAbsorbClampMode, calc, clamp) end
				pcall(calc.SetIncomingHealOverflowPercent, calc, 1)
				healCalc = calc
			end
		end
	end
	if healCalc and pcall(UnitGetDetailedHealPrediction, unit, "player", healCalc) then
		local ok, amount = pcall(healCalc.GetIncomingHeals, healCalc)
		local okAbsorb, absorb, clamped = pcall(healCalc.GetDamageAbsorbs, healCalc)
		if ok then
			if not okAbsorb then absorb, clamped = 0, false end
			return amount, absorb, clamped
		end
	end
	local amount = UnitGetIncomingHeals and UnitGetIncomingHeals(unit)
	local absorb = UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit)
	local clamped = false
	if health and maxHealth and not (ns.Secret(health) or ns.Secret(maxHealth) or ns.Secret(amount) or ns.Secret(absorb)) then
		local missing = math.max(0, maxHealth - health)
		amount = math.min(amount or 0, missing)
		clamped = (absorb or 0) > missing - amount
		absorb = math.min(absorb or 0, missing - amount)
	end
	return amount, absorb, clamped
end

-- The heal-over-time part of a heal you're casting (Regrowth: "Heals a friendly target for 93
-- to 107 and another 98 over 21 sec."). The client predicts only the direct heal, so this is
-- the rest, from the spell's text (English clients). Ticks yet to come from HoTs already up
-- are not counted: their auras say neither the amount nor how much is left.
local castHot = {} -- spellID -> HoT total, or false for none
local sentTarget -- the target name UNIT_SPELLCAST_SENT gave the cast going now (nil: hidden)
local GetDescriptionText = (C_Spell and C_Spell.GetSpellDescription) or GetSpellDescription

local function HotTotal(spellID)
	local known = castHot[spellID]
	if known ~= nil then return known end
	if not GetDescriptionText then return false end
	local ok, text = pcall(GetDescriptionText, spellID)
	-- The text can come back empty before the spell's data has loaded: don't remember that.
	if not ok or ns.Secret(text) or type(text) ~= "string" or text == "" then return false end
	local amount = text:lower():match("another (%d[%d,]*) over %d")
	amount = amount and tonumber((amount:gsub(",", ""))) or false
	castHot[spellID] = amount
	return amount
end

-- The spell you're casting, if it has a HoT part: its total.
local function CastingHot()
	if not UnitCastingInfo then return end
	local ok, spellID = pcall(function() return select(9, UnitCastingInfo("player")) end)
	if not ok or spellID == nil or ns.Secret(spellID) then return end
	return HotTotal(spellID) or nil
end

-- Is your cast landing on unit? The client's own prediction from you says so; hidden (in
-- combat), the name the cast was sent at.
local function CastAt(unit)
	if UnitGetIncomingHeals then
		local ok, mine = pcall(UnitGetIncomingHeals, unit, "player")
		if ok and not ns.Secret(mine) then return (mine or 0) > 0 end
	end
	if not sentTarget or not UnitName then return false end
	local ok, name = pcall(UnitName, unit)
	if not ok or name == nil or ns.Secret(name) then return false end
	return name == sentTarget or name == sentTarget:match("^([^%-]+)")
end

-- The HoT still to come on unit from your cast, fitted (when readable) into the missing health
-- left after the heals; the shield, which the client fitted in before the HoT, gives it room.
-- Takes and returns IncomingHeals' heal, shield and clamped; the HoT comes back readable, 0
-- when there is none.
function ns.IncomingHot(unit, health, maxHealth, heal, absorb, clamped)
	local hot = CastingHot()
	if not hot or hot <= 0 or not CastAt(unit) then return 0, absorb, clamped end
	if health and maxHealth and heal and not (ns.Secret(health) or ns.Secret(maxHealth) or ns.Secret(heal)) then
		local room = math.max(0, maxHealth - health - heal)
		hot = math.min(hot, room)
		if absorb and not ns.Secret(absorb) and absorb > room - hot then
			absorb, clamped = math.max(0, room - hot), true
		end
	end
	return hot, absorb, clamped
end

-- Frames showing heal prediction register here to be redrawn when your cast starts or ends:
-- the client's prediction event can come before the cast info that says a HoT is on its way.
local hotWatchers = {}
function ns.OnHotChanged(fn)
	hotWatchers[#hotWatchers + 1] = fn
end

do
	local queued = false
	local function Redraw()
		queued = false
		for i = 1, #hotWatchers do pcall(hotWatchers[i]) end
	end
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP",
		"UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED" }) do
		pcall(events.RegisterUnitEvent, events, event, "player")
	end
	pcall(events.RegisterEvent, events, "SPELLS_CHANGED")
	events:SetScript("OnEvent", function(_, event, _, target)
		if event == "UNIT_SPELLCAST_SENT" then
			-- unit, target, castGUID, spellID
			sentTarget = (target ~= nil and not ns.Secret(target) and target ~= "") and target or nil
			return
		elseif event == "SPELLS_CHANGED" then
			wipe(castHot) -- new ranks and talents change the numbers
			return
		end
		-- Next frame, once the cast info has settled; one redraw for a burst of events.
		if not queued and C_Timer then
			queued = true
			C_Timer.After(0, Redraw)
		end
	end)
end

-- `value or default` that is safe on secrets: a secret comes back as is (for widgets to take).
function ns.Or(value, default)
	if ns.Secret(value) then return value end
	if value == nil or value == false then return default end
	return value
end

-- A unit's name to show. Characters on Forever have a surname, and there UnitName's second
-- return is that surname (elsewhere it's the realm), joined with the client's own separator as
-- Plater does. withSurname false gives the first name alone. A secret name can't be joined, so
-- it comes back as the client gave it.
local IS_FOREVER = WOW_PROJECT_CAMELOT ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT
local SURNAME_SEP = Constants and Constants.CharacterNameSeparatorConsts
	and Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR or " "
function ns.UnitDisplayName(unit, withSurname)
	local first, second = UnitName(unit)
	if not IS_FOREVER or withSurname == false or ns.Secret(first) or ns.Secret(second) then
		return first
	end
	if type(first) == "string" and type(second) == "string" and second ~= "" then
		return first .. SURNAME_SEP .. second
	end
	return first
end

-- Every aura of one kind (filter) on a unit, in the client's order, which way it was read, and
-- whether the client refused every way (in combat it refuses addons the player's auras
-- outright, so an empty list then means "can't tell", not "no buffs").
-- In combat this client hides aura data: GetAuraDataByIndex refuses hidden auras outright
-- (and a loop over it used to stop at the first one), so slots come first, as oUF does on
-- this client. Each read is pcall'd and skipped on refusal; an entry that is itself secret
-- can't be looked into and is skipped too. Fields of the entries kept may still be secret.
function ns.ReadAuras(unit, filter)
	local UA = C_UnitAuras
	local list = {}
	if not UA then return list, "none" end
	local function keep(aura, index)
		if type(aura) == "table" and not ns.Secret(aura) then
			aura.index = index
			list[#list + 1] = aura
		end
	end
	if UA.GetAuraSlots and UA.GetAuraDataBySlot then
		local position = 0
		local function take(token, ...)
			for i = 1, select("#", ...) do
				position = position + 1
				local ok, aura = pcall(UA.GetAuraDataBySlot, unit, (select(i, ...)))
				if ok then keep(aura, position) end
			end
			return token
		end
		local ok, token = pcall(function() return take(UA.GetAuraSlots(unit, filter)) end)
		local pages = 0
		while ok and token ~= nil and not ns.Secret(token) and pages < 20 do
			pages = pages + 1
			ok, token = pcall(function() return take(UA.GetAuraSlots(unit, filter, nil, token)) end)
		end
		if ok then return list, "slots", false end
		wipe(list)
	end
	if UA.GetUnitAuras then
		local ok, auras = pcall(UA.GetUnitAuras, unit, filter)
		if ok and type(auras) == "table" and not ns.Secret(auras) then
			for i, aura in ipairs(auras) do keep(aura, i) end
			return list, "GetUnitAuras", false
		end
	end
	local refused = true
	if UA.GetAuraDataByIndex then
		for index = 1, 40 do
			local ok, aura = pcall(UA.GetAuraDataByIndex, unit, index, filter)
			if ok then refused = false end
			if ok and aura == nil then break end
			if ok then keep(aura, index) end
		end
	end
	return list, "index", refused
end

local GetDescription = (C_Spell and C_Spell.GetSpellDescription) or GetSpellDescription
local UNITS = { sec = 1, secs = 1, second = 1, seconds = 1, min = 60, mins = 60, minute = 60, minutes = 60, hour = 3600, hours = 3600 }

-- A spell's description in lower case; nil when it is hidden or there is none.
local function SpellText(spellID)
	if not GetDescription then return end
	local ok, text = pcall(GetDescription, spellID)
	if not ok or ns.Secret(text) or type(text) ~= "string" then return end
	return text:lower()
end

-- Does this spell only do something to enemies, so it can't have put a buff on you? Asks the
-- client, then the spell's text: the client may not count untargeted attacks (Thunder Clap,
-- Demoralizing Shout) as harmful. Bloodthirst is an attack that also buffs you.
local BLOODTHIRST = 23881

function ns.OnlyHitsEnemies(spellID)
	local getName = C_Spell and C_Spell.GetSpellName
	if spellID == BLOODTHIRST then return false end
	if getName then
		local name, base = getName(spellID), getName(BLOODTHIRST)
		if not ns.Secret(name) and name ~= nil and name == base then return false end
	end
	if C_Spell and C_Spell.IsSpellHarmful then
		local ok, harmful = pcall(C_Spell.IsSpellHarmful, spellID)
		if ok and not ns.Secret(harmful) and harmful then return true end
	end
	local text = SpellText(spellID)
	if not text or text:find("your next", 1, true) then return false end
	return (text:find("enem", 1, true) or text:find("target", 1, true)) and true or false
end

-- How long a spell's effect lasts, from its text: "This effect lasts 8 sec." / "Lasts 2 min."
-- first, else the last duration in the text. Nil when the text is hidden or names none.
function ns.DescribedLength(spellID)
	local text = SpellText(spellID)
	if not text then return end
	local n, unit = text:match("lasts (%d+%.?%d*) (%a+)")
	if n and UNITS[unit] then return tonumber(n) * UNITS[unit] end
	local last
	for num, u in text:gmatch("(%d+%.?%d*) (%a+)") do
		if UNITS[u] then last = tonumber(num) * UNITS[u] end
	end
	return last
end

-- Icons Blizzard's buff frame is showing. It runs untainted and sees buffs in combat, so its
-- count going up or down is the one sign of a buff coming or going that addons still get.
function ns.BuffIcons()
	local frame = _G.BuffFrame
	if not frame or type(frame.auraFrames) ~= "table" then return 0 end
	local count = 0
	for _, button in ipairs(frame.auraFrames) do
		if not button.isAuraAnchor and button:IsShown() then count = count + 1 end
	end
	return count
end

function ns.Print(msg)
	print("|cffd8b86aSanctuaryUI:|r " .. msg)
	ns.Log("print: %s", msg)
end

-- Resize the buttons an aura container already made for one of its groups. Once the client has
-- shown an aura on a button, addon code may no longer touch it ("forbidden object"), so those are
-- skipped (and any other refusal caught) instead of aborting the caller's setup. sizer(button)
-- does the resize. When a button is stuck at its old size and the size really changed, say once
-- that a reload finishes the job. `last` is the caller's record of sizes applied, per group.
function ns.ResizeAuraButtons(box, group, size, sizer, last)
	local stuck = false
	for i = 1, box:GetAuraGroupFrameCount(group) do
		local button = box:GetAuraGroupFrame(group, i)
		if button then
			if (button.IsForbidden and button:IsForbidden()) or not pcall(sizer, button) then
				stuck = true
			end
		end
	end
	local changed = last and last[group] ~= nil and last[group] ~= size
	if last then last[group] = size end
	if stuck and changed and not ns.auraResizeSaid then
		ns.auraResizeSaid = true
		ns.Print("Aura icons already in use keep their old size until you /reload.")
	end
end

-- Changing a Blizzard CVar from addon code taints Blizzard's copy of it: the CVAR_UPDATE
-- handlers run tainted and store the new value (CVarCallbackRegistry's cache, the Settings
-- values), and every Blizzard frame that reads it afterwards runs tainted too. Its action
-- buttons then fail on secret cooldowns, its bars are blocked in combat, and Edit Mode taints
-- the party frames. A reload clears those caches and the CVar keeps its new value, so a CVar is
-- only ever changed right before a reload, after asking.
local pendingCVar
-- (Only a new key in StaticPopupDialogs: reassigning the global itself would taint it.)
StaticPopupDialogs.SANCTUARYUI_CVAR_RELOAD = {
	text = "%s",
	button1 = "Change and reload",
	button2 = "Not now",
	OnAccept = function()
		local changes = pendingCVar
		pendingCVar = nil
		if not changes or InCombatLockdown() then return end
		local SetCVar = C_CVar and C_CVar.SetCVar or SetCVar
		for _, change in ipairs(changes) do
			pcall(SetCVar, change[1], change[2])
			ns.Log("cvar %s = %s", change[1], tostring(change[2]))
		end
		ns.Log("reloading for the cvars")
		ReloadUI()
	end,
	OnCancel = function() pendingCVar = nil end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

-- Ask to set a Blizzard CVar and reload. Nothing happens in combat or if it already has the value.
-- Several at once: ns.AskCVarReload({ { cvar, value }, ... }, why).
function ns.AskCVarReload(cvar, value, why)
	local list = cvar
	if type(cvar) ~= "table" then
		list = { { cvar, value } }
	else
		why = value
	end
	local GetCVar = C_CVar and C_CVar.GetCVar or GetCVar
	local changes = {}
	for _, change in ipairs(list) do
		if not (GetCVar and GetCVar(change[1]) == tostring(change[2])) then
			changes[#changes + 1] = { change[1], tostring(change[2]) }
		end
	end
	if #changes == 0 then return end
	if InCombatLockdown() then
		ns.Print("cannot change Blizzard settings in combat")
		return
	end
	pendingCVar = changes
	StaticPopup_Show("SANCTUARYUI_CVAR_RELOAD", why .. "\n\nChanging a Blizzard setting needs a reload, or Blizzard's own frames start throwing errors.")
end

local function ClampScale(value)
	value = tonumber(value) or 1
	if value < 0.5 then value = 0.5 end
	if value > 1.8 then value = 1.8 end
	return value
end

-- Bar scale and globe scale used to be one Scale, with the globes optionally on their own. A
-- profile from then whose globes followed the console gives them its scale, so nothing moves.
local function SplitScales(db)
	if db.scalesSplit then return end
	if not db.globesSeparate then db.globeScale = db.scale end
	db.scalesSplit = true
end

-- The globes' size against the bars' (General > Bar scale, Globe scale). The cluster takes the
-- bar scale; the globes' pods this ratio on top of it.
function ns.GlobeRatio()
	local db = ns.DB()
	SplitScales(db)
	return ClampScale(db.globeScale) / ClampScale(db.scale)
end

-- Each globe and its statue is a pod: a console-sized frame in the cluster, scaled by the
-- globe ratio about the seam where it meets the bar, so the globe's piece of the console art
-- stays bolted to the bar's end, bottoms level. Inside a pod, ns.Metrics().pods positions
-- mean what ns.Metrics() positions mean in the cluster.
local function PlacePods()
	if not ns.Pods then return end
	local metrics = ns.Metrics()
	local ratio = metrics.globeRatio
	for side, pod in pairs(ns.Pods) do
		pod:SetScale(ratio)
		pod:SetSize(metrics.width, metrics.height)
		pod:ClearAllPoints()
		pod:SetPoint("BOTTOM", ns.Cluster, "BOTTOM", metrics.pods[side].seam * (1 - ratio) / ratio, 0)
	end
end

local function ApplyScale()
	local db = ns.DB()
	SplitScales(db)
	db.scale = ClampScale(db.scale)
	db.globeScale = ClampScale(db.globeScale)
	if ns.Cluster then
		ns.Cluster:SetScale(db.scale)
	end
	PlacePods()
end

-- BottomBar_GameRes.tex (1416x201) widened by two socket columns and one menu plate to
-- 1595x201, inside a 2048x256 PNG (tools/build_hud_art.py). These are pixel positions in the
-- widened sheet. CONSOLE_W keeps the original on-screen scale (1100 / 1416).
local TEX_W, TEX_H = 1595, 201
local CONSOLE_W = 1595 * 1100 / 1416
ns.TEX_W = TEX_W

-- Where the globes' pieces of the console art meet the bar, in sheet px: just past the outer
-- edge of each globe's ring. Left of SEAM_L and right of SEAM_R scale with the globes.
ns.SEAM_L, ns.SEAM_R = 330, 1265

ns.FRAME_TEXCOORD = { 0, TEX_W / 2048, 0, TEX_H / 256 }

-- Frame levels above the cluster, back to front. The liquid stack must stay under the glass
-- and the console art; buttons, menu and numbers sit above the art.
ns.LEVEL = {
	aura = 0, -- light behind a globe (GlobeAura.lua): the globe and the console art cover it
	globe = 1, -- dark well
	liquid = 2, -- fill StatusBars (the invisible guide)
	clip = 3, -- clips the scrolling layers at the liquid level
	pool = 4, -- scrolling liquid layers
	shade = 5, -- fixed sphere shading
	surface = 6, -- surface band
	glass = 7,
	railRested = 7,
	rail = 8,
	console = 9,
	blade = 10,
	buttons = 12,
	menu = 14,
	chrome = 18, -- globe numbers
	pips = 20,
	-- The target plate, when dragged near the console: above the whole console stack (pips and
	-- their surfaces reach about +28), or the console takes the mouse from its aura icons.
	target = 50,
}

-- Bars docked in the console (Options > Bars 2-9 > Bar n > In the console): each fills a row of
-- twelve sockets between the globes, and the rail band (XP rail, ornaments, centre skull)
-- lifts to sit on top of them. Enabled docked bars in bar order, at most DOCK_MAX.
ns.DOCK_MAX = 3
ns.TIER_H = 93 -- sheet px of one docked row
function ns.DockedRows()
	local list = {}
	local ids = ns.ActionBar and ns.ActionBar.ROW_IDS
	if not ids or not ns.db then return list end
	local rows = ns.DB().rows
	for _, n in ipairs(ids) do
		local opt = rows[n]
		if opt.enabled and opt.docked and #list < ns.DOCK_MAX then
			list[#list + 1] = n
		end
	end
	return list
end

function ns.Metrics()
	local width = CONSOLE_W
	local height = width * TEX_H / TEX_W
	local function at(tx, ty)
		return (tx / TEX_W - 0.5) * width, (0.5 - ty / TEX_H) * height
	end
	local function box(x0, y0, x1, y1)
		local x, y = at((x0 + x1) / 2, (y0 + y1) / 2)
		return {
			x = x,
			y = y,
			w = (x1 - x0) / TEX_W * width,
			h = (y1 - y0) / TEX_H * height,
		}
	end
	-- Nine stone sockets, all skills; the gold pair is 6 and 7.
	local sockets = {}
	local centres = { 373.5, 447.5, 521.5, 595.5, 669.5, 746, 819, 893.5, 967.5 }
	for i = 1, #centres do
		sockets[i] = box(centres[i] - 34, 111, centres[i] + 34, 178)
	end
	local globe = 160 / TEX_W * width
	local hx, hy = at(243.5, 99)
	local rx, ry = at(1354.5, 99)
	local scale = width / TEX_W
	-- Docked rows: twelve sockets each on the console's 74 px period, one TIER_H above another.
	local tiers = #ns.DockedRows()
	local lift = tiers * ns.TIER_H * scale
	local dock = {}
	for j = 1, tiers do
		dock[j] = {}
		for i = 1, 12 do
			local cx = 373.5 + 74 * (i - 1)
			dock[j][i] = box(cx - 34, 111 - ns.TIER_H * j, cx + 34, 178 - ns.TIER_H * j)
		end
	end
	-- Globe spots in pod units (see PlacePods), and where they land on the console.
	local ratio = ns.GlobeRatio()
	local base = height / 2
	local seamL = (ns.SEAM_L / TEX_W - 0.5) * width
	local seamR = (ns.SEAM_R / TEX_W - 0.5) * width
	local pods = {
		health = { x = hx, y = hy, size = globe, seam = seamL },
		resource = { x = rx, y = ry, size = globe, seam = seamR },
	}
	local function onConsole(spot)
		return {
			x = spot.seam + (spot.x - spot.seam) * ratio,
			y = (base + spot.y) * ratio - base,
			size = spot.size * ratio,
		}
	end
	local rail = box(336, 96, 1259, 104)
	rail.y = rail.y + lift
	-- Your level, in a medallion resting on the centre skull.
	local plaque = box(761, 28, 803, 70)
	plaque.y = plaque.y + lift
	return {
		tiers = tiers,
		lift = lift,
		dock = dock,
		width = width,
		height = height,
		scale = scale,
		-- The console art sits on the cluster's bottom edge.
		baseY = base,
		globeRatio = ratio,
		split = ratio ~= 1,
		seamL = seamL,
		seamR = seamR,
		pods = pods,
		-- Where the globes are on the console, in cluster units.
		health = onConsole(pods.health),
		resource = onConsole(pods.resource),
		slots = sockets,
		hearth = box(1010, 110, 1051, 179),
		menu = box(1056, 110, 1244, 178),
		rail = rail,
		levelPlaque = plaque,
		socketArt = box(336, 104, 412, 184),
	}
end

-- A globe's piece of a console-sheet texture (frame, glass): left of SEAM_L for health, right
-- of SEAM_R for resource. PlacePiece puts a frame over that piece, in its pod.
local function PieceSpan(side)
	if side == "health" then return 0, ns.SEAM_L end
	return ns.SEAM_R, TEX_W
end

function ns.CropPiece(tex, side)
	local x0, x1 = PieceSpan(side)
	tex:SetTexCoord(x0 / 2048, x1 / 2048, 0, TEX_H / 256)
end

function ns.PlacePiece(frame, pod, side, metrics)
	local x0, x1 = PieceSpan(side)
	local scale = metrics.scale
	frame:SetSize((x1 - x0) * scale, metrics.height)
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", pod, "BOTTOM", (x0 + x1) / 2 * scale - metrics.width / 2, metrics.baseY)
end

-- The bar's piece of the sheet, between the seams.
function ns.CropBar(tex)
	tex:SetTexCoord(ns.SEAM_L / 2048, ns.SEAM_R / 2048, 0, TEX_H / 256)
end

-- The console's place is its bottom centre, in screen (UIParent) units from the screen's bottom
-- centre (db.posUI), so changing the bar scale grows it up and out from there. Earlier profiles
-- kept the anchor a drag left (its centre from the screen's bottom-left, in the console's own
-- scaled units), which slid it toward that corner as the scale changed; they convert once.
local function Anchor(cluster, db)
	local s = ClampScale(db.scale)
	cluster:ClearAllPoints()
	cluster:SetPoint("BOTTOM", UIParent, "BOTTOM", (db.x or 0) / s, (db.y or 0) / s)
end

-- Record where the console is now, in that form, and anchor it so.
function ns.SavePosition()
	local cluster = ns.Cluster
	if not cluster then return end
	local left, bottom, width = cluster:GetLeft(), cluster:GetBottom(), cluster:GetWidth()
	if not left then return end
	local db = ns.DB()
	local s = cluster:GetScale()
	db.point, db.rel = "BOTTOM", "BOTTOM"
	db.x = (left + width / 2) * s - UIParent:GetWidth() / 2
	db.y = bottom * s
	db.posUI = true
	db.movedConsole = true
	Anchor(cluster, db)
end

function ns.ApplyPosition()
	local db = ns.DB()
	local cluster = ns.Cluster
	if not cluster then return end
	if db.posUI then
		Anchor(cluster, db)
		ApplyScale()
		return
	end
	-- An earlier profile: its own anchor at the scale it has now, then converted from where
	-- that puts the console.
	if (db.point or "BOTTOM") == "BOTTOM" and (db.rel or "BOTTOM") == "BOTTOM" then
		local s = ClampScale(db.scale)
		db.x, db.y, db.posUI = (db.x or 0) * s, (db.y or 0) * s, true
		Anchor(cluster, db)
		ApplyScale()
		return
	end
	cluster:ClearAllPoints()
	cluster:SetPoint(db.point or "BOTTOM", UIParent, db.rel or "BOTTOM", db.x or 0, db.y or 0)
	ApplyScale()
	ns.SavePosition()
end

function ns.Layout()
	if ns.Globes and ns.Globes.Layout then ns.Globes.Layout() end
	if ns.GlobeAura and ns.GlobeAura.Layout then ns.GlobeAura.Layout() end
	if ns.ActionBar and ns.ActionBar.Layout then ns.ActionBar.Layout() end
	if ns.Auras and ns.Auras.Layout then ns.Auras.Layout() end
	if ns.Experience and ns.Experience.Layout then ns.Experience.Layout() end
	if ns.Stance and ns.Stance.Layout then ns.Stance.Layout() end
	if ns.Totem and ns.Totem.Layout then ns.Totem.Layout() end
	if ns.Trinket and ns.Trinket.Layout then ns.Trinket.Layout() end
	if ns.Swing and ns.Swing.Layout then ns.Swing.Layout() end
	if ns.Meter and ns.Meter.Layout then ns.Meter.Layout() end
	if ns.TargetPlate and ns.TargetPlate.Layout then ns.TargetPlate.Layout() end
	if ns.FocusPlate and ns.FocusPlate.Layout then ns.FocusPlate.Layout() end
	if ns.Portraits and ns.Portraits.Layout then ns.Portraits.Layout() end
end

function ns.Check()
	local loaded, total = ns.Art.Probe()
	ns.Print(("art %d/%d slots from SanctuaryUI\\Art, scale %.2f, rail %s, lock %s"):format(
		loaded,
		total,
		ns.DB().scale or 1,
		ns.DB().railMode or "auto",
		ns.DB().locked and "on" or "off"
	))
	if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Bartender4") then
		ns.Print("Bartender4 is loaded. Hide its bar 1, pet bar, and stance bar, or disable it. Both want ACTIONBUTTON1-12.")
	end
	if ns.Liquid and ns.Liquid.Status then
		ns.Print(ns.Liquid.Status())
		if ns.Pollution then ns.Print(ns.Pollution.Status()) end
		if ns.Freeze then ns.Print(ns.Freeze.Status()) end
		if ns.Reckless then ns.Print(ns.Reckless.Status()) end
		if ns.StatueEyes then ns.Print(ns.StatueEyes.Status()) end
		if ns.Party and ns.Party.DispelStatus then ns.Print(ns.Party.DispelStatus()) end
	end
	if ns.Blizzard and ns.Blizzard.DispatchStatus then ns.Print(ns.Blizzard.DispatchStatus()) end
	local key = GetBindingKey("ACTIONBUTTON1")
	ns.Print("ACTIONBUTTON1 is bound to " .. (key or "nothing"))
	if ns.ActionBar and ns.ActionBar.primary then
		local rows = {}
		for _, n in ipairs(ns.ActionBar.ROW_IDS) do
			rows[#rows + 1] = ("bar %d %s"):format(n, ns.ActionBar.RowEnabled(n) and "on" or "off")
		end
		ns.Print(("%d main sockets, %s"):format(#ns.ActionBar.primary, table.concat(rows, ", ")))
	end
end

-- A preview a command turns on keeps running after the options window closes.
local function KeepPreview(key)
	if ns.Options and ns.Options.KeepPreview then ns.Options.KeepPreview(key) end
end

local function Slash(msg)
	local cmd, rest = (msg or ""):match("^(%S*)%s*(.-)$")
	cmd = (cmd or ""):lower()
	local db = ns.DB()
	if cmd == "" or cmd == "config" or cmd == "options" then
		if ns.Options and ns.Options.Open then
			ns.Options.Open()
		end
	elseif cmd == "help" then
		ns.Print("/sanctuary opens options. Commands: lock, unlock, grid [on|off|<spacing>], snap on|off, scale <n> (bars), globes <n>|match, bar 2-9 on|off, bind, pie [1-6] (pie menus), trinkets, swing (preview the swing timer), fish [chapter|log|outfit|outfit remember|words] (the angler's journal; log: what the game said while you fished; outfit: fishing gear on or off; anything else searches it), cook [chapter|words] (the Cookbook; anything else searches it), minimap, ring (preview the ally ring; totems: each totem's reach against your distance), map (overlay map; probe|peek for what the client allows; totems to probe group casts), test, rail auto|xp|rep, numbers on|combat|hover|off, reset, check, cooldowns, active, auras, watch, meter [analysis|run [test|banner]|glory|awards|test|reset|probe] (damage meter; run: the Run Report), proc (preview the proc highlight), aura (test globe auras), health <percent>|off (preview the health globe), predict (heal, shield and spell cost demo), power [spell|off] (trace the resource globe against your casts), debug on|off, log, report [on|off], request (suggest a feature), updates [on|off] (new version notices over the realm channel)")
	elseif cmd == "grid" then
		-- grid: toggle; grid on|off; grid <spacing>. The grid only shows while frames are
		-- unlocked, so showing it unlocks them.
		local arg = rest:lower()
		local size = tonumber(arg)
		if size then
			db.gridSize = math.max(ns.Snap.GRID_MIN, math.min(ns.Snap.GRID_MAX, math.floor(size / 5 + 0.5) * 5))
			db.grid = true
		elseif arg == "on" or arg == "show" then
			db.grid = true
		elseif arg == "off" or arg == "hide" then
			db.grid = false
		else
			db.grid = not db.grid
		end
		ns.Print(db.grid and ("grid shown, spacing %d"):format(ns.Snap.GridSize()) or "grid hidden")
		if db.grid and db.locked then
			ns.SetLocked(false)
		else
			ns.Refresh()
		end
	elseif cmd == "snap" then
		local arg = rest:lower()
		if arg == "on" then
			db.snapping = true
		elseif arg == "off" then
			db.snapping = false
		else
			db.snapping = not ns.Snap.Enabled()
		end
		ns.Print(db.snapping and "bar snapping on (hold Shift while dragging to place freely)" or "bar snapping off")
		ns.Refresh()
	elseif cmd == "fish" or cmd == "fishing" or cmd == "journal" then
		-- fish [chapter]: the angler's journal, on a chapter by its key or title's first word.
		local want = rest:lower()
		if want == "log" then ns.Journal.PrintHeard() return end
		if want == "clicks" then ns.Fishing.PrintTrace() return end
		if want == "outfit" then ns.Fishing.ToggleOutfit() return end
		if want == "outfit remember" then ns.Fishing.RememberOutfit() return end
		local key
		for _, c in ipairs(ns.Journal.CHAPTERS) do
			if want ~= "" and (c.key == want or c.title:lower():find(want, 1, true)) then key = c.key break end
		end
		if key then
			ns.Journal.Open(key)
		elseif want ~= "" then
			ns.Journal.Search(rest)
		else
			ns.Journal.Toggle()
		end
	elseif cmd == "cook" or cmd == "cooking" or cmd == "cookbook" then
		-- cook [chapter]: the Cookbook, on a chapter by its key or title's first word; anything
		-- else searches it.
		if not ns.Cookbook then
			ns.Print("The Cookbook is new: exit the game and start it again to load it (a /reload can't see new files).")
			return
		end
		local want = rest:lower()
		local key
		for _, c in ipairs(ns.Cookbook.CHAPTERS) do
			if want ~= "" and (c.key == want or c.title:lower():find(want, 1, true)) then key = c.key break end
		end
		if key then
			ns.Cookbook.Open(key)
		elseif want ~= "" then
			ns.Cookbook.Search(rest)
		else
			ns.Cookbook.Toggle()
		end
	elseif cmd == "lock" then
		ns.SetLocked(true)
	elseif cmd == "unlock" then
		ns.SetLocked(false)
	elseif cmd == "scale" then
		-- scale <n>: the bars (the globes keep theirs; "globes match" sizes them to the bars).
		local value = tonumber(rest)
		ns.GlobeRatio() -- converts an old profile's scales first
		if not value then
			ns.Print(("bar scale is %.2f, globe scale %.2f"):format(db.scale or 1, db.globeScale or 1))
			-- What the frames really have, against UIParent: the console, a globe pod, the globe.
			local ui = UIParent:GetEffectiveScale()
			local function On(frame)
				return frame and ("%.3f"):format(frame:GetEffectiveScale() / ui) or "-"
			end
			local pod = ns.Pods and ns.Pods.health
			ns.Print(("on screen: console %s, pod %s (own %s), globe %s, globe art %s"):format(
				On(ns.Cluster), On(pod), pod and ("%.3f"):format(pod:GetScale()) or "-",
				On(ns.HealthGlobe), On(pod and pod.art)))
		elseif InCombatLockdown() then
			ns.Print("cannot change scale in combat")
		else
			db.scale = value
			ns.Refresh()
			ns.Print(("bar scale set to %.2f"):format(db.scale))
		end
	elseif cmd == "globes" then
		-- globes <n>: the globes' scale; globes match: the same as the bars'.
		local arg = rest:lower()
		local value = tonumber(arg)
		ns.GlobeRatio()
		if arg == "" then
			ns.Print(("globe scale is %.2f"):format(db.globeScale or 1))
		elseif InCombatLockdown() then
			ns.Print("cannot change scale in combat")
		elseif value or arg == "match" or arg == "off" then
			db.globeScale = value or db.scale
			ns.Refresh()
			ns.Print(("globe scale set to %.2f"):format(db.globeScale))
		else
			ns.Print("globes <scale>|match")
		end
	elseif cmd == "bar" or cmd == "row" then -- "row" kept from before the rename
		local n, on = rest:lower():match("^(%d)%s+(%a+)$")
		n = tonumber(n)
		if not n or not ns.ActionBar.rows or not ns.ActionBar.rows[n] or (on ~= "on" and on ~= "off") then
			ns.Print("bar 2-9 on|off")
		elseif InCombatLockdown() then
			ns.Print("cannot change bars in combat")
		else
			db.rows[n].enabled = (on == "on")
			ns.ActionBar.ApplyRows()
			ns.Print(("bar %d %s"):format(n, on))
		end
	elseif cmd == "bind" then
		local KeyBound = LibStub("LibKeyBound-1.0", true)
		if not KeyBound then
			ns.Print("LibKeyBound is missing")
		elseif InCombatLockdown() then
			ns.Print("cannot bind keys in combat")
		else
			KeyBound:Toggle()
		end
	elseif cmd == "numbers" then
		local mode = rest:lower()
		if mode == "on" or mode == "combat" or mode == "hover" or mode == "off" then
			db.numbers = mode
			if ns.Globes and ns.Globes.ApplyNumbers then ns.Globes.ApplyNumbers() end
			ns.Print("globe numbers " .. mode)
		else
			ns.Print("numbers on|combat|hover|off")
		end
	elseif cmd == "rail" then
		local mode = rest:lower()
		if mode == "auto" or mode == "xp" or mode == "rep" then
			db.railMode = mode
			if ns.Experience then ns.Experience.Update() end
			ns.Print("rail shows " .. (mode == "auto" and "XP, then reputation at max level" or mode))
		else
			ns.Print("rail auto|xp|rep")
		end
	elseif cmd == "reset" then
		if InCombatLockdown() then
			ns.Print("cannot reset in combat")
		else
			db.point, db.rel, db.x, db.y, db.scale, db.posUI = "BOTTOM", "BOTTOM", 0, 0, 1, true
			db.globeScale = 1
			ns.Refresh()
			ns.Print("position and scale reset")
		end
	elseif cmd == "mouse" then
		-- Hover the thing, press Enter, type this: lists every frame under the cursor.
		local foci = GetMouseFoci and GetMouseFoci() or { GetMouseFocus and GetMouseFocus() }
		if not foci or #foci == 0 then
			ns.Print("nothing under the mouse")
		end
		for i, frame in ipairs(foci) do
			local name = frame.GetName and frame:GetName() or tostring(frame)
			local parent = frame.GetParent and frame:GetParent()
			local pname = parent and parent.GetName and parent:GetName() or "?"
			ns.Print(("%d. %s (parent %s, strata %s, level %s, mouse %s)"):format(i, tostring(name), tostring(pname),
				frame.GetFrameStrata and frame:GetFrameStrata() or "?", frame.GetFrameLevel and frame:GetFrameLevel() or "?",
				frame.IsMouseEnabled and tostring(frame:IsMouseEnabled()) or "?"))
		end
	elseif cmd == "minimap" then
		if ns.Minimap then
			ns.Minimap.SetShown(ns.db.global.minimap.hide)
		end
	elseif cmd == "ring" and rest:lower() == "totems" then
		-- Each totem's reach against how far you really are, and whether you have its buff.
		local ok, err = pcall(ns.RingTotems.Report)
		if not ok then ns.Print("ring totems: " .. tostring(err)) end
	elseif cmd == "ring" then
		-- The ally ring with four stand-ins, to place and size it without a group.
		ns.AllyRing.SetPreview(not ns.AllyRing.preview)
		ns.Print(ns.AllyRing.preview and "ally ring preview on (/sanctuary ring again to turn off)" or "ally ring preview off")
	elseif cmd == "map" then
		-- What the client lets us read about positions, map art and hidden messages (MapProbe.lua).
		local sub = rest:lower()
		if sub == "totems" then
			-- What the client lets us read when a group member casts (TotemProbe.lua).
			local ok, err = pcall(ns.TotemProbe.Run)
			if not ok then ns.Print("totem probe failed: " .. tostring(err)) end
		elseif sub == "ping" then
			ns.Print(ns.MapPins.TestPing() and "a test ping, ahead and to your right, for a few seconds" or "no position here, so no ping")
		elseif sub == "probe" or sub == "peek" or sub == "check" then
			local ok, err = pcall(sub == "peek" and ns.MapProbe.Peek or sub == "check" and ns.MapProbe.Check or ns.MapProbe.Run)
			if not ok then ns.Print("map probe failed: " .. tostring(err)) end
		elseif ns.DB().map.overlay.enabled then
			ns.MapOverlay.Toggle()
		else
			ns.Print("the overlay map is turned off in /sanctuary > Overlay map")
		end
	elseif cmd == "test" then
		if ns.Totem and ns.Totem.SetPreview then
			KeepPreview("totem")
			ns.Totem.SetPreview(not ns.Totem.preview)
		end
	elseif cmd == "aura" then
		-- Globe aura test mode, for any class: /sanctuary aura <buff name> | break | spend | hit
		-- | judge | fade | clear | die | showcase | on | off
		local action = rest:lower()
		local MOMENTS = "break, spend, hit, judge, fade, clear, die, showcase, off"
		KeepPreview("auras") -- test mode on from chat stays on with the options window closed
		if action == "off" then
			ns.GlobeAura.SetPreview(false)
			ns.Watch.SetTest(false)
			ns.Print("aura test off")
		elseif action == "on" then
			ns.Watch.SetTest(true)
			ns.Print("aura test on: /sanctuary aura <buff name>, or " .. MOMENTS)
		elseif action == "showcase" then
			ns.GlobeAura.SetPreview(not ns.GlobeAura.preview)
		elseif action == "hit" then
			if not ns.GlobeAura.Hit() then ns.Print("no shield up to take the hit") end
		elseif not (ns.Watch and ns.Watch.Test and ns.Watch.Test(action)) then
			local _, class = UnitClass("player")
			local names = {}
			for _, effect in ipairs(ns.Watch.EFFECTS) do
				if effect.class == class or effect.class == "ANY" then names[#names + 1] = effect.label:lower() end
			end
			ns.Print("aura <buff name> (yours: " .. table.concat(names, ", ") .. "; any class works), or " .. MOMENTS)
		end
	elseif cmd == "health" then
		-- Preview the health globe at a level: /sanctuary health 20 | off
		local value = tonumber((rest:gsub("%%", "")))
		if value then
			ns.Globes.PreviewHealth(value)
			ns.Print(("health globe previewing %d%% (/sanctuary health off for your real health)"):format(value))
		else
			ns.Globes.PreviewHealth(nil)
			ns.Print("health globe shows your health")
		end
	elseif cmd == "pollute" then
		-- /sanctuary pollute [poison|curse|magic|disease|off]: the look, without needing the debuff.
		local key = (rest or ""):lower()
		if key == "" then key = "poison" end
		if key == "off" then key = nil end
		local ok, why = ns.Pollution.Preview(key)
		ns.Print(ok and (key and ("Previewing " .. key .. " in the health globe. /sanctuary pollute off to stop.") or "Pollution preview off.") or ("Pollution preview failed: " .. tostring(why)))
	elseif cmd == "freeze" then
		-- /sanctuary freeze [hold|off]: ice over the health globe, without needing the debuff.
		local mode = (rest or ""):lower()
		local ok, why = ns.Freeze.Preview(mode ~= "" and mode or nil)
		if not ok then
			ns.Print("Freeze preview failed: " .. tostring(why))
		elseif mode == "off" then
			ns.Print("Freeze preview off.")
		elseif mode == "hold" then
			ns.Print("The health globe is frozen. /sanctuary freeze off breaks the ice.")
		else
			ns.Print("Freezing the health globe; the ice breaks in a few seconds. /sanctuary freeze hold keeps it.")
		end
	elseif cmd == "power" then
		-- /sanctuary power [spell|off]: the resource globe against what you could spend (#19).
		ns.PowerTrace.Command(rest)
	elseif cmd == "predict" then
		-- Heal, shield and spell cost demo on preview levels: lands at 2.5 s, full health at 5 s,
		-- real values at 8 s.
		ns.Globes.PredictDemo()
		ns.Print("prediction demo: incoming heal, shield and spell cost; they land at 2.5 s, health tops up at 5 s")
	elseif cmd == "log" then
		ns.ShowLog()
	elseif cmd == "report" then
		local arg = rest:lower()
		if arg == "on" or arg == "off" then
			ns.SetReportPrompt(arg == "on")
		else
			ns.ShowReport()
		end
	elseif cmd == "request" or cmd == "suggest" then
		ns.ShowRequest()
	elseif cmd == "debug" then
		local arg = rest:lower()
		local on
		if arg == "on" then on = true elseif arg == "off" then on = false else on = not ns.LogEnabled() end
		ns.SetLogEnabled(on)
		ns.Print(on and "debug trace on. Reproduce the problem, then /sanctuary log to copy it, or /reload and send WTF\\Account\\<account>\\SavedVariables\\SanctuaryUI.lua"
			or "debug trace off. Errors are still recorded. /sanctuary log shows them")
	elseif cmd == "check" then
		ns.Check()
	elseif cmd == "updates" or cmd == "update" then
		-- updates [on|off]: the realm channel copies use to tell each other about new versions.
		local arg = rest:lower()
		if ns.UpdateChannel then ns.UpdateChannel(arg == "on" or (arg ~= "off" and nil)) end
	elseif cmd == "pie" or cmd == "ring" then
		-- "/sanctuary pie 2" edits ring 2; alone, it opens the rings' options page.
		if rest ~= "" then
			ns.Pie.Edit(rest)
		elseif ns.Options and ns.Options.Open then
			ns.Options.Open("pie")
		end
	elseif cmd == "swing" then
		if ns.Swing and ns.Swing.SetPreview then
			KeepPreview("swing")
			ns.Swing.SetPreview(not ns.Swing.preview)
		end
	elseif cmd == "trinket" or cmd == "trinkets" then
		if ns.Options and ns.Options.Open then ns.Options.Open("trinkets") end
	elseif cmd == "proc" then
		if ns.ProcGlow and ns.ProcGlow.Test then ns.ProcGlow.Test() end
	elseif cmd == "radiance" then
		-- The golden light on the angel's wings, without needing its buff. Again to stop.
		KeepPreview("eyes:wings")
		local ok, on = ns.StatueEyes.Preview("wings")
		ns.Print(ok and (on and "Wing light preview on. /sanctuary radiance again to stop." or "Wing light preview off.") or ("Wing light preview failed: " .. tostring(on)))
	elseif cmd == "eyes" then
		-- /sanctuary eyes [angel|gargoyle|wings|off]: the statues' glows, without needing the buff.
		local key = (rest or ""):lower()
		local keys = key == "" and { "angel", "gargoyle" } or { key }
		for _, one in ipairs(keys) do
			KeepPreview("eyes:" .. one)
			local ok, why = ns.StatueEyes.Preview(one)
			if not ok then ns.Print("Eye glow preview failed: " .. tostring(why)) end
		end
		ns.Print("Eye glow preview toggled. /sanctuary eyes off to stop.")
	elseif cmd == "cooldowns" then
		-- Run while a skill on the main bar is cooling down.
		ns.forceLog = true
		local ok, err = pcall(ns.ActionBar.CountdownReport)
		ns.forceLog = nil
		if not ok then ns.Print("report failed: " .. tostring(err)) end
	elseif cmd == "threat" then
		local sub = rest:lower()
		if not ns.Threat or not ns.Threat.Draw then
			ns.Print("threat loads after a full restart of the game (a new file).")
		elseif sub == "probe" then
			local ok, err = pcall(ns.Threat.Probe)
			if not ok then ns.Print("threat probe failed: " .. tostring(err)) end
		elseif sub == "test" or sub == "preview" then
			KeepPreview("threat")
			ns.Threat.SetPreview(not ns.Threat.preview)
			ns.Print(ns.Threat.preview and "threat preview on (/sanctuary threat test again to turn off)" or "threat preview off")
		elseif sub == "warn" or sub == "warnings" then
			ns.Threat.TestWarnings()
		elseif ns.Options and ns.Options.Open then
			ns.Options.Open("threat")
		end
	elseif cmd == "meter" then
		local sub = rest:lower()
		if sub == "probe" then
			-- What the client's damage meter data lets us read: now, and over the next few fights.
			local ok, err = pcall(ns.MeterProbe.Run)
			if not ok then ns.Print("meter probe failed: " .. tostring(err)) end
		elseif sub == "analysis" or sub == "analyze" or sub == "details" then
			ns.MeterAnalysis.Open()
		elseif (sub == "run" or sub == "report" or sub:match("^run ") or sub:match("^report ")) and not ns.RunReport then
			ns.Print("the run report loads after a full restart of the game (a new file).")
		elseif sub == "run" or sub == "report" then
			ns.RunReport.Open()
		elseif sub == "run test" or sub == "run preview" or sub == "report test" then
			ns.RunReport.Preview()
		elseif sub == "run banner" then
			ns.RunReport.PreviewBanner()
		elseif sub == "glory" or sub == "surprises" then
			ns.MeterGlory.Test()
		elseif sub == "awards" then
			ns.MeterGlory.Awards()
		elseif sub == "reset" or sub == "clear" then
			ns.Meter.Reset()
		elseif sub == "test" or sub == "preview" then
			KeepPreview("meter")
			ns.Meter.SetPreview(not ns.Meter.preview)
			ns.Print(ns.Meter.preview and "damage meter preview on (/sanctuary meter test again to turn off)" or "damage meter preview off")
		elseif ns.Options and ns.Options.Open then
			ns.Options.Open("meter")
		end
	elseif cmd == "active" or cmd == "auras" or cmd == "watch" then
		-- Reports go into the log even with debug off, so /reload hands them over whole.
		ns.forceLog = true
		local ok, err = pcall(function()
			if cmd == "active" then
				if ns.ActiveSkill and ns.ActiveSkill.Report then ns.ActiveSkill.Report() end
			elseif cmd == "watch" then
				if ns.Watch and ns.Watch.Report then ns.Watch.Report() end
			elseif ns.Auras and ns.Auras.Report then
				ns.Auras.Report()
			end
		end)
		ns.forceLog = nil
		if not ok then ns.Print("report failed: " .. tostring(err)) end
		ns.Print("report saved to the log (/reload writes it to SavedVariables)")
	else
		ns.Print("unknown command. /sanctuary help")
	end
end

local function WarnBartender()
	local loaded = false
	if C_AddOns and C_AddOns.IsAddOnLoaded then
		loaded = C_AddOns.IsAddOnLoaded("Bartender4")
	elseif IsAddOnLoaded then
		loaded = IsAddOnLoaded("Bartender4")
	end
	if loaded then
		ns.Print("Bartender4 is also loaded. Hide its bar 1, pet bar, and stance bar, or disable Bartender4. SanctuaryUI uses ACTIONBUTTON1-12.")
	end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("PLAYER_REGEN_ENABLED")
loader:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		ns.InitDB()
		SANCTUARYUI = "SanctuaryUI"
		ns.Cluster = CreateFrame("Frame", "SanctuaryUICluster", UIParent, "SecureHandlerStateTemplate")
		ns.Cluster:SetSize(720, 250)
		-- Its scale from the start: bars moved off it keep their place by it (ns.MovedPoint).
		ns.Cluster:SetScale(ClampScale(ns.DB().scale))
		ns.Cluster:SetMovable(true)
		ns.Cluster:SetClampedToScreen(true)
		ns.Cluster:EnableMouse(true)
		ns.Cluster:RegisterForDrag("LeftButton")
		ns.Cluster:SetScript("OnDragStart", function()
			if ns.ActionBar and ns.ActionBar.DragConsole then
				ns.ActionBar.DragConsole()
			end
		end)
		ns.Cluster:SetScript("OnDragStop", function()
			ns.Snap.StopDrag()
		end)
		RegisterStateDriver(ns.Cluster, "visibility", "[petbattle] hide; show")
		ns.Pods = {
			health = CreateFrame("Frame", "SanctuaryUIHealthPod", ns.Cluster),
			resource = CreateFrame("Frame", "SanctuaryUIResourcePod", ns.Cluster),
		}
		for _, pod in pairs(ns.Pods) do
			pod:EnableMouse(false)
		end

		local function Safe(label, fn)
			if not fn then return end
			ns.Log("init %s", label)
			local ok, err = ns.Try("init " .. label, fn)
			if not ok then
				ns.Print(label .. " failed: " .. tostring(err))
			end
		end
		ns.Art.Probe()
		Safe("blizzard", ns.Blizzard and ns.Blizzard.Hide)
		Safe("globes", ns.Globes and ns.Globes.Init)
		Safe("action bar", ns.ActionBar and ns.ActionBar.Init)
		Safe("active skills", ns.ActiveSkill and ns.ActiveSkill.Init)
		Safe("proc highlight", ns.ProcGlow and ns.ProcGlow.Init)
		Safe("watch", ns.Watch and ns.Watch.Init)
		Safe("globe auras", ns.GlobeAura and ns.GlobeAura.Init)
		Safe("menu", ns.Menu and ns.Menu.Init)
		Safe("bags", ns.Bags and ns.Bags.Init)
		Safe("bank", ns.Bank and ns.Bank.Init)
		Safe("stance", ns.Stance and ns.Stance.Init)
		Safe("totems", ns.Totem and ns.Totem.Init)
		Safe("trinkets", ns.Trinket and ns.Trinket.Init)
		Safe("swing timer", ns.Swing and ns.Swing.Init)
		Safe("damage meter", ns.Meter and ns.Meter.Init)
		Safe("meter history", ns.MeterHistory and ns.MeterHistory.Init)
		Safe("meter glory", ns.MeterGlory and ns.MeterGlory.Init)
		Safe("threat", ns.Threat and ns.Threat.Init)
		Safe("pie menus", ns.Pie and ns.Pie.Init)
		Safe("map", ns.Map and ns.Map.Init)
		Safe("ally ring", ns.AllyRing and ns.AllyRing.Init)
		Safe("auras", ns.Auras and ns.Auras.Init)
		Safe("target plate", ns.TargetPlate and ns.TargetPlate.Init)
		Safe("focus plate", ns.FocusPlate and ns.FocusPlate.Init)
		Safe("portraits", ns.Portraits and ns.Portraits.Init)
		Safe("party", ns.Party and ns.Party.Init)
		Safe("pollution", ns.Pollution and ns.Pollution.Init)
		Safe("freeze", ns.Freeze and ns.Freeze.Init)
		Safe("reckless", ns.Reckless and ns.Reckless.Init)
		Safe("statue eyes", ns.StatueEyes and ns.StatueEyes.Init)
		Safe("experience", ns.Experience and ns.Experience.Init)
		Safe("books", ns.Book and ns.Book.Init)
		Safe("fishing journal", ns.Journal and ns.Journal.Init)
		Safe("cookbook", ns.Cookbook and ns.Cookbook.Init)
		Safe("fishing tools", ns.Fishing and ns.Fishing.Init)
		Safe("layout", ns.Layout)
		Safe("position", ns.ApplyPosition)
		Safe("options", ns.Options and ns.Options.Init)
		Safe("minimap", ns.Minimap and ns.Minimap.Init)
		Safe("settings", ns.Refresh)
		WarnBartender()
		local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
		local version = getMeta and getMeta("SanctuaryUI", "Version") or "?"
		ns.Print(("version %s loaded. /sanctuary for options."):format(version))
		-- Only worth a line when something is missing: new art needs a client restart, not a /reload.
		local loaded, total = ns.Art.loadedCount or 0, ns.Art.totalCount or 0
		if loaded < total then
			ns.Print(("%d of %d art files didn't load. Restart the game client to pick up new art."):format(total - loaded, total))
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		ns.Log("combat ended, applying deferred work%s", ns.pendingRefresh and " (refresh pending)" or "")
		if ns.Blizzard and ns.Blizzard.Hide then ns.Blizzard.Hide() end
		if ns.ActionBar and ns.ActionBar.ReassignBindings then ns.ActionBar.ReassignBindings() end
		if ns.Menu and ns.Menu.ReassignBindings then ns.Menu.ReassignBindings() end
		if ns.Stance and ns.Stance.ReassignBindings then ns.Stance.ReassignBindings() end
		if ns.Totem and ns.Totem.ReassignBindings then ns.Totem.ReassignBindings() end
		if ns.Trinket and ns.Trinket.ReassignBindings then ns.Trinket.ReassignBindings() end
		if ns.ActionBar and ns.ActionBar.FlushSpellMoves then ns.ActionBar.FlushSpellMoves() end
		if ns.pendingRefresh then ns.Refresh() end
	end
end)

SLASH_SANCTUARYUI1 = "/sanctuary"
SLASH_SANCTUARYUI2 = "/sanc"
SlashCmdList.SANCTUARYUI = Slash
