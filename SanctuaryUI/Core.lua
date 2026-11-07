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

-- `value or default` that is safe on secrets: a secret comes back as is (for widgets to take).
function ns.Or(value, default)
	if ns.Secret(value) then return value end
	if value == nil or value == false then return default end
	return value
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

-- How long a spell's effect lasts, from its text: "This effect lasts 8 sec." / "Lasts 2 min."
-- first, else the last duration in the text. Nil when the text is hidden or names none.
function ns.DescribedLength(spellID)
	if not GetDescription then return end
	local ok, text = pcall(GetDescription, spellID)
	if not ok or ns.Secret(text) or type(text) ~= "string" then return end
	text = text:lower()
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

local function ClampScale(value)
	value = tonumber(value) or 1
	if value < 0.5 then value = 0.5 end
	if value > 1.8 then value = 1.8 end
	return value
end

-- The globes' size against the console's: 1 unless they are scaled separately (General >
-- Globe scale), when they keep their own scale whatever the console's.
function ns.GlobeRatio()
	local db = ns.DB()
	if not db.globesSeparate then return 1 end
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
}

-- Bars docked in the console (Options > Bars > Bar n > In the console): each fills a row of
-- twelve sockets between the globes, and the rail band (XP rail, ornaments, centre skull)
-- lifts to sit on top of them. Enabled docked bars in bar order, at most DOCK_MAX.
ns.DOCK_MAX = 2
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

function ns.ApplyPosition()
	local db = ns.DB()
	local cluster = ns.Cluster
	if not cluster then return end
	cluster:ClearAllPoints()
	cluster:SetPoint(db.point or "BOTTOM", UIParent, db.rel or "BOTTOM", db.x or 0, db.y or 0)
	ApplyScale()
end

function ns.SavePosition()
	local cluster = ns.Cluster
	if not cluster then return end
	local point, _, rel, x, y = cluster:GetPoint(1)
	local db = ns.DB()
	db.point = point or "BOTTOM"
	db.rel = rel or "BOTTOM"
	db.x = x or 0
	db.y = y or 0
	db.movedConsole = true
end

function ns.Layout()
	if ns.Globes and ns.Globes.Layout then ns.Globes.Layout() end
	if ns.GlobeAura and ns.GlobeAura.Layout then ns.GlobeAura.Layout() end
	if ns.ActionBar and ns.ActionBar.Layout then ns.ActionBar.Layout() end
	if ns.Auras and ns.Auras.Layout then ns.Auras.Layout() end
	if ns.Experience and ns.Experience.Layout then ns.Experience.Layout() end
	if ns.Stance and ns.Stance.Layout then ns.Stance.Layout() end
	if ns.Totem and ns.Totem.Layout then ns.Totem.Layout() end
	if ns.TargetPlate and ns.TargetPlate.Layout then ns.TargetPlate.Layout() end
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
	end
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

local function Slash(msg)
	local cmd, rest = (msg or ""):match("^(%S*)%s*(.-)$")
	cmd = (cmd or ""):lower()
	local db = ns.DB()
	if cmd == "" or cmd == "config" or cmd == "options" then
		if ns.Options and ns.Options.Open then
			ns.Options.Open()
		end
	elseif cmd == "help" then
		ns.Print("/sanctuary opens options. Commands: lock, unlock, grid [on|off|<spacing>], snap on|off, scale <n>, globes <n>|off, bar 2-9 on|off, bind, minimap, test, rail auto|xp|rep, numbers on|combat|hover|off, reset, check, cooldowns, active, auras, watch, aura (test globe auras), health <percent>|off (preview the health globe), debug on|off, log")
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
	elseif cmd == "lock" then
		ns.SetLocked(true)
	elseif cmd == "unlock" then
		ns.SetLocked(false)
	elseif cmd == "scale" then
		local value = tonumber(rest)
		if not value then
			ns.Print(("scale is %.2f"):format(db.scale or 1))
		elseif InCombatLockdown() then
			ns.Print("cannot change scale in combat")
		else
			db.scale = value
			ns.Refresh()
			ns.Print(("scale set to %.2f"):format(db.scale))
		end
	elseif cmd == "globes" then
		-- globes <n>: scale the globes on their own; globes off: back with the console's scale.
		local arg = rest:lower()
		local value = tonumber(arg)
		if arg == "" then
			ns.Print(db.globesSeparate and ("globe scale is %.2f"):format(db.globeScale or 1) or "globes follow the console scale")
		elseif InCombatLockdown() then
			ns.Print("cannot change scale in combat")
		elseif value or arg == "on" then
			db.globesSeparate = true
			if value then db.globeScale = value end
			ns.Refresh()
			ns.Print(("globe scale set to %.2f"):format(db.globeScale))
		elseif arg == "off" then
			db.globesSeparate = false
			ns.Refresh()
			ns.Print("globes follow the console scale")
		else
			ns.Print("globes <scale>|on|off")
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
			db.point, db.rel, db.x, db.y, db.scale = "BOTTOM", "BOTTOM", 0, 0, 1
			db.globesSeparate, db.globeScale = false, 1
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
	elseif cmd == "test" then
		if ns.Totem and ns.Totem.SetPreview then
			ns.Totem.SetPreview(not ns.Totem.preview)
		end
	elseif cmd == "aura" then
		-- Globe aura test mode, for any class: /sanctuary aura <buff name> | break | spend | hit
		-- | judge | fade | clear | die | showcase | on | off
		local action = rest:lower()
		local MOMENTS = "break, spend, hit, judge, fade, clear, die, showcase, off"
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
	elseif cmd == "log" then
		ns.ShowLog()
	elseif cmd == "debug" then
		local arg = rest:lower()
		local on
		if arg == "on" then on = true elseif arg == "off" then on = false else on = not ns.LogEnabled() end
		ns.SetLogEnabled(on)
		ns.Print(on and "debug trace on. Reproduce the problem, then /sanctuary log to copy it, or /reload and send WTF\\Account\\<account>\\SavedVariables\\SanctuaryUI.lua"
			or "debug trace off. Errors are still recorded. /sanctuary log shows them")
	elseif cmd == "check" then
		ns.Check()
	elseif cmd == "cooldowns" then
		-- Run while a skill on the main bar is cooling down.
		ns.forceLog = true
		local ok, err = pcall(ns.ActionBar.CountdownReport)
		ns.forceLog = nil
		if not ok then ns.Print("report failed: " .. tostring(err)) end
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
		Safe("watch", ns.Watch and ns.Watch.Init)
		Safe("globe auras", ns.GlobeAura and ns.GlobeAura.Init)
		Safe("menu", ns.Menu and ns.Menu.Init)
		Safe("bags", ns.Bags and ns.Bags.Init)
		Safe("bank", ns.Bank and ns.Bank.Init)
		Safe("stance", ns.Stance and ns.Stance.Init)
		Safe("totems", ns.Totem and ns.Totem.Init)
		Safe("auras", ns.Auras and ns.Auras.Init)
		Safe("target plate", ns.TargetPlate and ns.TargetPlate.Init)
		Safe("portraits", ns.Portraits and ns.Portraits.Init)
		Safe("experience", ns.Experience and ns.Experience.Init)
		Safe("layout", ns.Layout)
		Safe("position", ns.ApplyPosition)
		Safe("options", ns.Options and ns.Options.Init)
		Safe("minimap", ns.Minimap and ns.Minimap.Init)
		Safe("settings", ns.Refresh)
		WarnBartender()
		local loaded, total = ns.Art.loadedCount or 0, ns.Art.totalCount or 0
		ns.Print(("loaded. Art %d/%d. /sanctuary for options."):format(loaded, total))
	elseif event == "PLAYER_REGEN_ENABLED" then
		ns.Log("combat ended, applying deferred work%s", ns.pendingRefresh and " (refresh pending)" or "")
		if ns.Blizzard and ns.Blizzard.Hide then ns.Blizzard.Hide() end
		if ns.ActionBar and ns.ActionBar.ReassignBindings then ns.ActionBar.ReassignBindings() end
		if ns.Menu and ns.Menu.ReassignBindings then ns.Menu.ReassignBindings() end
		if ns.Stance and ns.Stance.ReassignBindings then ns.Stance.ReassignBindings() end
		if ns.pendingRefresh then ns.Refresh() end
	end
end)

SLASH_SANCTUARYUI1 = "/sanctuary"
SLASH_SANCTUARYUI2 = "/sanc"
SlashCmdList.SANCTUARYUI = Slash
