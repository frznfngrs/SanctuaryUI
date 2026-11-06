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

function ns.Print(msg)
	print("|cffd8b86aSanctuaryUI:|r " .. msg)
end

local function ApplyScale()
	local db = ns.DB()
	local scale = tonumber(db.scale) or 1
	if scale < 0.5 then scale = 0.5 end
	if scale > 1.8 then scale = 1.8 end
	db.scale = scale
	if ns.Cluster then
		ns.Cluster:SetScale(scale)
	end
	if ns.TargetPlate and ns.TargetPlate.frame then
		ns.TargetPlate.frame:SetScale(scale)
	end
end

-- BottomBar_GameRes.tex (1416x201) widened by two socket columns and one menu plate to
-- 1595x201, inside a 2048x256 PNG (tools/build_hud_art.py). These are pixel positions in the
-- widened sheet. CONSOLE_W keeps the original on-screen scale (1100 / 1416).
local TEX_W, TEX_H = 1595, 201
local CONSOLE_W = 1595 * 1100 / 1416

ns.FRAME_TEXCOORD = { 0, TEX_W / 2048, 0, TEX_H / 256 }

-- Frame levels above the cluster, back to front. The liquid stack must stay under the glass
-- and the console art; buttons, menu and numbers sit above the art.
ns.LEVEL = {
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
	return {
		width = width,
		height = height,
		scale = scale,
		-- The console art sits on the cluster's bottom edge.
		baseY = height / 2,
		health = { x = hx, y = hy, size = globe },
		resource = { x = rx, y = ry, size = globe },
		slots = sockets,
		hearth = box(1010, 110, 1051, 179),
		menu = box(1056, 110, 1244, 178),
		rail = box(336, 96, 1259, 104),
		socketArt = box(336, 104, 412, 184),
	}
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
	if ns.ActionBar and ns.ActionBar.Layout then ns.ActionBar.Layout() end
	if ns.Auras and ns.Auras.Layout then ns.Auras.Layout() end
	if ns.Experience and ns.Experience.Layout then ns.Experience.Layout() end
	if ns.Stance and ns.Stance.Layout then ns.Stance.Layout() end
	if ns.Totem and ns.Totem.Layout then ns.Totem.Layout() end
	if ns.TargetPlate and ns.TargetPlate.Layout then ns.TargetPlate.Layout() end
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
		ns.Print("/sanctuary opens options. Commands: lock, unlock, scale <n>, bar 2-9 on|off, bind, minimap, test, rail auto|xp|rep, numbers on|combat|hover|off, reset, check, active")
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
			ApplyScale()
			ns.Print(("scale set to %.2f"):format(db.scale))
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
			ns.ApplyPosition()
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
	elseif cmd == "check" then
		ns.Check()
	elseif cmd == "active" then
		if ns.ActiveSkill and ns.ActiveSkill.Report then
			ns.ActiveSkill.Report()
		end
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
		ns.Cluster:SetScript("OnDragStart", function(self)
			if ns.DB().locked or InCombatLockdown() then return end
			self:StartMoving()
		end)
		ns.Cluster:SetScript("OnDragStop", function(self)
			self:StopMovingOrSizing()
			ns.SavePosition()
		end)
		RegisterStateDriver(ns.Cluster, "visibility", "[petbattle] hide; show")

		local function Safe(label, fn)
			if not fn then return end
			local ok, err = pcall(fn)
			if not ok then
				ns.Print(label .. " failed: " .. tostring(err))
			end
		end
		ns.Art.Probe()
		Safe("blizzard", ns.Blizzard and ns.Blizzard.Hide)
		Safe("globes", ns.Globes and ns.Globes.Init)
		Safe("action bar", ns.ActionBar and ns.ActionBar.Init)
		Safe("active skills", ns.ActiveSkill and ns.ActiveSkill.Init)
		Safe("menu", ns.Menu and ns.Menu.Init)
		Safe("bags", ns.Bags and ns.Bags.Init)
		Safe("bank", ns.Bank and ns.Bank.Init)
		Safe("stance", ns.Stance and ns.Stance.Init)
		Safe("totems", ns.Totem and ns.Totem.Init)
		Safe("auras", ns.Auras and ns.Auras.Init)
		Safe("target plate", ns.TargetPlate and ns.TargetPlate.Init)
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
