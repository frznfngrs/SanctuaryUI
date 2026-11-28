SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.Blizzard = ns.Blizzard or {}

-- Frames this cluster replaces. Bags, chat, and the minimap stay. The micro menu is
-- replaced by the D3 menu buttons in the console. Names a client doesn't have are skipped.
local FRAME_NAMES = {
	"MainActionBar",
	"MainMenuBar", -- the main bar's older name
	"StanceBar",
	"StanceBarFrame",
	"ShapeshiftBarFrame",
	-- The form bar older bar code slides over the main bar in a form or stealth.
	"BonusActionBarFrame",
	"PetActionBar",
	"PetActionBarFrame",
	"PossessActionBar",
	"PossessBarFrame",
	"OverrideActionBar",
	"StatusTrackingBarManager",
	"MainStatusTrackingBarContainer",
}

-- Hidden where they are, never moved to the hider: Blizzard code calls methods on their
-- parent (MainStatusTrackingBarContainer:GetStatusTrackingManager() is its GetParent(), and
-- Edit Mode calls CheckForLayoutChange on it). Their parent is hidden, which is enough.
local KEEP_PARENT = {
	MainStatusTrackingBarContainer = true,
}

-- Of those, the ones whose own event handlers are stopped too (ElvUI's build for this client does
-- the same). Hidden, they still ran on every pet, page, combat and experience change: showing
-- and hiding their buttons, re-anchoring the bar stack. In combat that is protected work, and
-- once anything on the way is tainted, every one of those calls is blocked and reported against
-- SanctuaryUI; a hunter tester got them by the hundred (#17, #18). With no events, none of their
-- code runs. Their methods stay, for Blizzard code that calls them. Pet autocast still works:
-- it is the pet button's own click.
local SILENCED = {
	MainActionBar = true,
	MainMenuBar = true,
	StanceBar = true,
	PetActionBar = true,
	PossessActionBar = true,
	OverrideActionBar = true,
	StatusTrackingBarManager = true,
}

local function Silence(frame)
	if frame and frame.UnregisterAllEvents then pcall(frame.UnregisterAllEvents, frame) end
end

-- Hidden only while the SanctuaryUI part that replaces them is on (portraits, target plate).
local function PartyStyled(db)
	-- Any of our looks (globes, slab, the target styles); "none" leaves Blizzard's frames up.
	return db.party and db.party.style ~= nil and db.party.style ~= "none" or false
end

local REPLACED_BY = {
	PlayerFrame = function(db) return db.portraits.enabled end,
	TargetFrame = function(db) return db.target.enabled end,
	-- Blizzard's party frames while a SanctuaryUI party style is on; with None they are left
	-- alone for Blizzard or another addon. The raid-style party frames (CompactPartyFrame) are
	-- PartyFrame's child, so they go with it. Raids keep Blizzard's raid frames either way.
	PartyFrame = PartyStyled,
}

-- Blizzard's other action bars, by the page each shows. A SanctuaryUI row on the same page
-- uses the same keys, so the bar showing (Edit Mode's "In Combat" or "Out of Combat"
-- visibility, a settings change) put a copy of that row on screen (#10). Each is hidden only
-- while an enabled row shows its page: with no row there, it is the player's own bar to use.
local MULTI_BARS = {
	MultiBarBottomLeft = 6,
	MultiBarBottomRight = 5,
	MultiBarRight = 3,
	MultiBarLeft = 4,
	MultiBar5 = 13,
	MultiBar6 = 14,
	MultiBar7 = 15,
}
local multiParent = {}

-- A Blizzard bar hidden under a row's page is silenced too (see SILENCED): its combat
-- visibility events would show and hide it and its buttons in combat. Given back, it gets
-- them again (EditModeActionBar_OnLoad registers these).
local multiSilenced = {}
local MULTI_EVENTS = { "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED" }

-- The drag grid events (ACTIONBAR_SHOWGRID/HIDEGRID) never reach a Blizzard bar, even one
-- left to the player. They fire inside whatever put something on the cursor, and with
-- SanctuaryUI that is often addon code: our bag and bank slots (the slot template's OnClick
-- and OnDragStart are mixin methods, written tainted when an addon makes the button, as in
-- every bag addon), our bars' drags, the pet bar, the fishing weapon swap. The bar's
-- handler then runs tainted. In combat each button's SetShown is blocked (a right-click on a
-- bag item: a hundred blocked calls). Out of combat it is quieter and worse: the bar's
-- showAllButtons, its shown-button list and Edit Mode's bar layout are rewritten tainted, and
-- Blizzard's own code that reads them in combat is blocked later. From a tainted path the
-- grid never showed anyway: ActionButton's SetShowGrid sets the showgrid attribute only when
-- issecure(). Lost: a spell dragged from the spellbook no longer lights a Blizzard bar's empty
-- slots. Blizzard's "Always Show Buttons" setting still shows them (that path is not an event).
local function SilenceGrid(frame)
	for _, key in ipairs({ "showGridEventName", "hideGridEventName" }) do
		local event = rawget(frame, key)
		if type(event) == "string" then pcall(frame.UnregisterEvent, frame, event) end
	end
end

-- The pages enabled SanctuaryUI rows show, their form pages included.
local function RowPages(db)
	local pages = {}
	for _, n in ipairs(ns.ActionBar and ns.ActionBar.ROW_IDS or {}) do
		local row = db.rows[n]
		if row and row.enabled then
			if type(row.source) == "number" then pages[row.source] = true end
			if row.followForms and row.formPages then
				for _, page in pairs(row.formPages) do
					if type(page) == "number" then pages[page] = true end
				end
			end
		end
	end
	return pages
end

-- Hidden only while the "hide micro menu" option is on.
local MICRO_NAMES = { "MicroMenuContainer", "MicroMenu" }

-- Edit Mode systems (the action bars, PlayerFrame, TargetFrame, the micro menu, the bags bar)
-- replace Hide/SetShown with Lua overrides that write their own state: isShownExternal on the
-- action bars, Edit Mode's snapped frames (re-anchoring other frames) on all of them. Called
-- from here, those writes are tainted, and Blizzard's code that later reads them runs tainted:
-- in combat that blocks the stance bar, the action bars and the party frames. So hide through
-- the frame's own C Hide (HideBase, kept by the override) and never run the override.
local function RawHide(frame)
	local hide = rawget(frame, "HideBase") or frame.Hide
	hide(frame)
end

local function Suppress(frame)
	if not frame or not frame.Show then return end
	if not frame.sanctuaryHooked then
		frame.sanctuaryHooked = true
		hooksecurefunc(frame, "Show", function(self)
			if InCombatLockdown() then return end
			if self.sanctuaryAllow then return end
			RawHide(self)
		end)
	end
	if InCombatLockdown() then return end
	RawHide(frame)
	frame:SetAlpha(0)
	pcall(frame.EnableMouse, frame, false)
end

-- Blizzard help tips that point at a frame SanctuaryUI hides (the backpack button, for the
-- reagent bag tutorial; a micro button) have nothing on screen to point at, and the step that
-- would close them (opening Blizzard's bags) never comes, so they hang over the HUD (#15).
-- Closed as soon as they open.
local function HiddenByUs(region)
	local hider = ns.Hider
	for _ = 1, 20 do
		if not region or not hider then return false end
		if region == hider then return true end
		if rawget(region, "sanctuaryHooked") and not rawget(region, "sanctuaryAllow") then return true end
		region = region.GetParent and region:GetParent()
	end
	return false
end

function ns.Blizzard.CloseOrphanTips()
	local pool = HelpTip and HelpTip.framePool
	if not pool or not pool.EnumerateActive then return end
	local orphans = {}
	for tip in pool:EnumerateActive() do
		if tip.info and HiddenByUs(tip.relativeRegion) then orphans[#orphans + 1] = tip end
	end
	for _, tip in ipairs(orphans) do
		pcall(tip.Close, tip)
	end
end

local function WatchHelpTips()
	if ns.Blizzard.tipsWatched or not HelpTip or type(HelpTip.Show) ~= "function" then return end
	ns.Blizzard.tipsWatched = true
	hooksecurefunc(HelpTip, "Show", function(_, parent, _, region)
		if HiddenByUs(region or parent) then ns.Blizzard.CloseOrphanTips() end
	end)
end

-- Blizzard's shared action bar dispatchers (#20-#22). Silencing the hidden bars (SILENCED) was
-- not enough: a druid tester still got hundreds of blocked calls per form shift in combat,
-- Blizzard's gamepad bars among them, which SanctuaryUI never touches. Those come through
-- three frames every bar shares: ActionBarController (paging, stance, possess and override
-- bars on every form or page change), ActionBarButtonEventsFrame and ActionBarActionEventsFrame
-- (one event loop over every action button in the game). Once one step of such a loop is
-- tainted, every later button in it is blocked too. ElvUI's build for this client shuts all
-- three down; here the controller goes (it only drives bars SanctuaryUI hides), and the button
-- loops lose the buttons of hidden bars and the unused gamepad bars, so Blizzard bars the player
-- still uses keep updating. The extra action button and the gamepad class button stay, as in
-- ElvUI (the latter errors without its PLAYER_ENTERING_WORLD).
local DISPATCHERS = { "ActionBarButtonEventsFrame", "ActionBarActionEventsFrame" }
local dispatchPruned = false

local function GamepadActive()
	local types = Enum and Enum.InputDeviceInterfaceType
	local style = C_InputInterfaceStyle and C_InputInterfaceStyle.GetCurrentStyle
	if not types or not style then return false end
	local ok, current = pcall(style)
	return ok and current ~= nil and current == types.Gamepad
end

local function FrameName(frame)
	if type(frame) ~= "table" or type(frame.GetName) ~= "function" then return nil end
	local ok, name = pcall(frame.GetName, frame)
	return ok and type(name) == "string" and name or nil
end

-- Pruning writes into Blizzard's loop tables (frames[key] = nil), and every button the loop
-- reaches after an emptied entry runs tainted. A Blizzard bar left in the loop behind those
-- entries then had all its buttons and slots blocked in combat whenever every slot refreshed
-- at once (releasing at a graveyard, 2026-11-27: the bottom-right bar, turned off in
-- Settings but still in the loop, right after the main bar's twelve emptied entries). So a
-- Blizzard bar turned off in Settings leaves the loops with the hidden ones, and while one is
-- turned on with no row over its page, nothing is pruned at all. Bar toggles in Settings
-- order: bottom left, bottom right, right, left, bars 5-7. Unknown (not mirrored from the
-- server yet) counts as on; the next call (after each combat) decides again.
local TOGGLE_ORDER = { "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft",
	"MultiBar5", "MultiBar6", "MultiBar7" }
local offBars = {}

-- Returns the first bar that is on with no row over its page ("unknown" if the toggles
-- aren't known yet), and fills offBars with the bars turned off.
local function KeptBlizzardBar()
	wipe(offBars)
	if type(GetActionBarToggles) ~= "function" then return nil end
	local toggles = { pcall(GetActionBarToggles) }
	if not toggles[1] or toggles[2] == nil then return "unknown" end
	local pages = RowPages(ns.DB())
	local kept
	for i, name in ipairs(TOGGLE_ORDER) do
		local on = toggles[i + 1]
		if not on or on == 0 then
			offBars[name] = true
		elseif not kept and _G[name] and not pages[MULTI_BARS[name]] then
			kept = name
		end
	end
	return kept
end

local function Unwanted(frame)
	if type(frame) ~= "table" then return false end
	local name = FrameName(frame)
	if name and (name:match("^ExtraActionButton%d") or name == "GamepadMainActionBarFramePageUnitLeftClassAction") then
		return false
	end
	if HiddenByUs(frame) then return true end
	local bar = name and name:match("^(MultiBar.-)Button%d+$")
	if bar and offBars[bar] then return true end
	return name ~= nil and name:match("^Gamepad") ~= nil and not GamepadActive()
end

-- Entries are frames in a list or keyed by the frame; either way, the unwanted ones go.
local function PruneDispatcher(owner, only)
	local frames = owner and rawget(owner, "frames")
	if type(frames) ~= "table" then return 0 end
	local count = 0
	for key, value in pairs(frames) do
		local frame = type(value) == "table" and value or (type(key) == "table" and key or nil)
		if frame and (only == nil or frame == only) and Unwanted(frame) then
			frames[key] = nil
			count = count + 1
		end
	end
	return count
end

function ns.Blizzard.PruneDispatchers()
	local kept = KeptBlizzardBar()
	ns.Blizzard.pruneKept = kept
	if kept then return 0 end
	local total = 0
	for _, name in ipairs(DISPATCHERS) do
		local owner = _G[name]
		if owner then
			total = total + PruneDispatcher(owner)
			if not rawget(owner, "sanctuaryHooked") and type(owner.RegisterFrame) == "function" then
				owner.sanctuaryHooked = true
				hooksecurefunc(owner, "RegisterFrame", function(self, frame)
					if KeptBlizzardBar() then return end
					PruneDispatcher(self, frame)
				end)
			end
		end
	end
	if total > 0 then dispatchPruned = true end
	ns.Blizzard.prunedCount = (ns.Blizzard.prunedCount or 0) + total
	return total
end

-- For /sanctuary check.
function ns.Blizzard.DispatchStatus()
	local kept = ns.Blizzard.pruneKept
	return ("Blizzard bar events: controller %s, %d button(s) taken out of the shared loops%s%s"):format(
		ns.Blizzard.controllerQuiet and "quiet" or "running", ns.Blizzard.prunedCount or 0,
		GamepadActive() and ", gamepad active" or "",
		kept and (" (none taken now: %s is on)"):format(kept == "unknown" and "bar state unknown" or kept) or "")
end

-- The controller only pages and shows the main, stance, possess and override bars, which are
-- hidden for good. Kept: SETTINGS_LOADED (the page controller needs it to start) and
-- UPDATE_EXTRA_ACTIONBAR (the extra action button), as in ElvUI. Left alone with a gamepad,
-- whose crossbar it drives.
local function QuietController()
	local controller = _G.ActionBarController
	if ns.Blizzard.controllerQuiet or not controller or GamepadActive() then return end
	ns.Blizzard.controllerQuiet = true
	pcall(controller.UnregisterAllEvents, controller)
	pcall(controller.RegisterEvent, controller, "SETTINGS_LOADED")
	pcall(controller.RegisterEvent, controller, "UPDATE_EXTRA_ACTIONBAR")
end

function ns.Blizzard.Hide()
	if InCombatLockdown() then return end
	if not ns.Hider then
		ns.Hider = CreateFrame("Frame", "SanctuaryUIHider", UIParent)
		ns.Hider:Hide()
	end
	QuietController()
	for i = 1, #FRAME_NAMES do
		local name = FRAME_NAMES[i]
		local frame = _G[name]
		if frame then
			if not KEEP_PARENT[name] then
				pcall(frame.SetParent, frame, ns.Hider)
			end
			pcall(Suppress, frame)
			if SILENCED[name] then Silence(frame) end
		end
	end
	ns.Blizzard.Replaced()
	for i = 1, 12 do
		pcall(Suppress, _G["ActionButton" .. i])
	end
	ns.Blizzard.MicroMenu(not ns.DB().hideMicroMenu)
	-- Blizzard's buff frames are never hidden now: SanctuaryUI's buffs are those frames,
	-- moved and dressed (Auras.lua), since only Blizzard can read your buffs in combat.
	ns.Blizzard.Auras(true)
	local totemFrame = _G.TotemFrame
	if totemFrame and ns.DB().totems.enabled then
		if totemFrame:GetParent() ~= ns.Hider then ns.Blizzard.totemParent = totemFrame:GetParent() end
		totemFrame.sanctuaryAllow = nil
		pcall(totemFrame.SetParent, totemFrame, ns.Hider)
		pcall(Suppress, totemFrame)
	elseif totemFrame then
		ns.Blizzard.RestoreTotemFrame()
	end
	-- Blizzard's bag buttons, while the SanctuaryUI bag window (which has its own bag slots) is on.
	if ns.DB().bags.enabled then
		for _, name in ipairs({ "BagsBar", "MicroButtonAndBagsBar" }) do
			local frame = _G[name]
			if frame then
				pcall(frame.SetParent, frame, ns.Hider)
				pcall(Suppress, frame)
			end
		end
	end
	ns.Blizzard.CastBar()
	WatchHelpTips()
	ns.Blizzard.CloseOrphanTips()
	ns.Blizzard.PruneDispatchers()
end

-- Blizzard's player cast bar, while your casts run on the console's rail (CastRail.lua). Hidden
-- through the C Hide and silenced, as ElvUI's build for this client does: an Edit Mode frame,
-- and with no events its own code never shows it in combat. Silenced, it can't be given back
-- without a reload (its events come from its Lua SetUnit, tainted if called from here).
local CAST_BARS = { "PlayerCastingBarFrame", "CastingBarFrame" }
local castBarSilenced = false

StaticPopupDialogs["SANCTUARYUI_CASTBAR_RELOAD"] = {
	text = "Giving Blizzard's cast bar back needs a reload.",
	button1 = "Reload now",
	button2 = "Later",
	OnAccept = function() ReloadUI() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

function ns.Blizzard.CastBar()
	if InCombatLockdown() then return end
	-- Only with CastRail.lua loaded (a new file needs a client restart, not just a reload).
	if ns.DB().castRail ~= false and ns.CastRail and ns.CastRail.Init then
		for _, name in ipairs(CAST_BARS) do
			local frame = _G[name]
			if frame then
				frame.sanctuaryAllow = nil
				pcall(Suppress, frame)
				Silence(frame)
				castBarSilenced = true
			end
		end
	elseif castBarSilenced then
		castBarSilenced = false
		StaticPopup_Show("SANCTUARYUI_CASTBAR_RELOAD")
	end
end

local function Restore(frame, parent)
	if not frame then return end
	frame.sanctuaryAllow = true
	if parent and frame:GetParent() == ns.Hider then
		pcall(frame.SetParent, frame, parent)
	end
	frame:SetAlpha(1)
	pcall(frame.EnableMouse, frame, true)
	-- The C Show, as RawHide uses the C Hide: an Edit Mode frame's Lua override would run tainted.
	local show = rawget(frame, "ShowBase") or frame.Show
	show(frame)
end

-- Blizzard's party frames aren't given back mid-session: they come back after a reload. Putting
-- PartyFrame back under UIParent and showing it from here runs its OnShow, and the OnShow of every
-- shown frame under it, in SanctuaryUI's taint: PartyFrameMixin:OnShow, and CompactUnitFrame_OnShow
-- on the raid-style members, which stores each member's range (outOfRange) from secret values.
-- Blizzard's code then reads those and runs tainted for the rest of the session: the members' own
-- updates test outOfRange, and Edit Mode's exit (ResetPartyFrames) compares a secret health colour
-- (#32, #33). Until the reload it stays hidden, as the Show hook still applies.
local RELOAD_TO_RESTORE = { PartyFrame = true }
local reloadAsked = {}

StaticPopupDialogs["SANCTUARYUI_PARTY_RELOAD"] = {
	text = "Blizzard's party frames come back after a reload. Until then, you won't see any party frames.",
	button1 = "Reload now",
	button2 = "Reload later",
	OnAccept = function() ReloadUI() end,
	-- Reload later, and Escape: never reloads, leaves a reminder in chat.
	OnCancel = function()
		print("SanctuaryUI: Party frames are hidden until you /reload.")
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

-- Never pops in combat: waits for combat to end. Only shows if the reload is still pending.
local partyPopupWaiter
local function AskPartyReload()
	if InCombatLockdown() then
		if not partyPopupWaiter then
			partyPopupWaiter = CreateFrame("Frame")
			partyPopupWaiter:SetScript("OnEvent", function(self)
				self:UnregisterEvent("PLAYER_REGEN_ENABLED")
				if reloadAsked.PartyFrame then
					StaticPopup_Show("SANCTUARYUI_PARTY_RELOAD")
				end
			end)
		end
		partyPopupWaiter:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	StaticPopup_Show("SANCTUARYUI_PARTY_RELOAD")
end

-- Totems turned off again: Blizzard's frame goes back where it was. Not shown here, because
-- it shows itself only while a totem is down, on its next update.
function ns.Blizzard.RestoreTotemFrame()
	local frame = _G.TotemFrame
	if not frame or not ns.Hider or frame:GetParent() ~= ns.Hider then return end
	frame.sanctuaryAllow = true
	pcall(frame.SetParent, frame, ns.Blizzard.totemParent or UIParent)
	frame:SetAlpha(1)
	pcall(frame.EnableMouse, frame, true)
end

-- Show or hide Blizzard's micro menu. Hiding it again after a restore works through the
-- same Show hook, so the flag is the switch.
function ns.Blizzard.MicroMenu(show)
	if InCombatLockdown() then return end
	local container = _G.MicroMenuContainer
	if container or _G.MicroMenu then
		for _, name in ipairs(MICRO_NAMES) do
			local frame = _G[name]
			if frame then
				if show then
					Restore(frame, name == "MicroMenu" and container or UIParent)
				else
					frame.sanctuaryAllow = nil
					pcall(frame.SetParent, frame, ns.Hider)
					pcall(Suppress, frame)
				end
			end
		end
	elseif type(MICRO_BUTTONS) == "table" then
		-- Clients without a micro menu container: the buttons one by one, in place.
		for _, name in ipairs(MICRO_BUTTONS) do
			local frame = _G[name]
			if frame then
				if show then
					Restore(frame)
				else
					frame.sanctuaryAllow = nil
					pcall(Suppress, frame)
				end
			end
		end
	end
end

-- Blizzard's buff, debuff and weapon enchant frames. Only ever shown now (see Hide); hiding
-- stays for clients where something else wants them gone.
local AURA_NAMES = { "BuffFrame", "DebuffFrame", "TemporaryEnchantFrame" }

function ns.Blizzard.Auras(show)
	if InCombatLockdown() then return end
	for _, name in ipairs(AURA_NAMES) do
		local frame = _G[name]
		if frame then
			if show then
				if frame:GetParent() == ns.Hider then
					Restore(frame, UIParent)
				end
			else
				frame.sanctuaryAllow = nil
				pcall(frame.SetParent, frame, ns.Hider)
				pcall(Suppress, frame)
			end
		end
	end
end

function ns.Blizzard.Replaced()
	if InCombatLockdown() then return end
	local db = ns.DB()
	local pages = RowPages(db)
	local hidMulti, gaveBack = false, {}
	for name, page in pairs(MULTI_BARS) do
		local frame = _G[name]
		if frame then
			SilenceGrid(frame)
			if pages[page] then
				if frame:GetParent() ~= ns.Hider then multiParent[name] = frame:GetParent() end
				frame.sanctuaryAllow = nil
				pcall(frame.SetParent, frame, ns.Hider)
				pcall(Suppress, frame)
				if not multiSilenced[name] then
					-- All its events, as ElvUI does: only the combat and grid ones (0.19.2)
					-- still left it showing and hiding buttons in combat (#20).
					multiSilenced[name] = true
					Silence(frame)
					hidMulti = true
				end
			elseif frame:GetParent() == ns.Hider then
				if multiSilenced[name] then
					multiSilenced[name] = nil
					for _, event in ipairs(MULTI_EVENTS) do pcall(frame.RegisterEvent, frame, event) end
					-- Its buttons left the shared event loops while hidden (PruneDispatchers),
					-- and putting them back from here would taint those loops: a reload does it.
					if dispatchPruned then gaveBack[#gaveBack + 1] = name end
				end
				-- Given back as Blizzard left it: shown only if its own state says so (the
				-- Show override isn't called from here, see RawHide). A bar with combat
				-- visibility sorts itself out on the next change of combat.
				frame.sanctuaryAllow = true
				pcall(frame.SetParent, frame, multiParent[name] or UIParent)
				frame:SetAlpha(1)
				pcall(frame.EnableMouse, frame, true)
				local visibility = rawget(frame, "visibility")
				if rawget(frame, "isShownExternal") and (visibility == nil or visibility == "Always") then
					local show = rawget(frame, "ShowBase") or frame.Show
					show(frame)
				end
			end
		end
	end
	for name, replaced in pairs(REPLACED_BY) do
		local frame = _G[name]
		if frame then
			if replaced(db) then
				if reloadAsked[name] then
					-- Back to a SanctuaryUI style before reloading: nothing pending any more.
					reloadAsked[name] = nil
					StaticPopup_Hide("SANCTUARYUI_PARTY_RELOAD")
				end
				frame.sanctuaryAllow = nil
				pcall(frame.SetParent, frame, ns.Hider)
				pcall(Suppress, frame)
			elseif frame:GetParent() == ns.Hider then
				if RELOAD_TO_RESTORE[name] then
					if not reloadAsked[name] then
						reloadAsked[name] = true
						AskPartyReload()
					end
				else
					Restore(frame, UIParent)
				end
			end
		end
	end
	if hidMulti then ns.Blizzard.PruneDispatchers() end
	if #gaveBack > 0 then
		table.sort(gaveBack)
		ns.Print(("Blizzard's %s %s back. /reload to have its buttons update again."):format(
			table.concat(gaveBack, ", "), #gaveBack == 1 and "bar is" or "bars are"))
	end
end
