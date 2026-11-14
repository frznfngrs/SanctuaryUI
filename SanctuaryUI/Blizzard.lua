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
-- visibility and grid events would show and hide it and its buttons in combat. Given back, it
-- gets the same events again (EditModeActionBar_OnLoad and ActionBar_OnLoad register these).
local multiSilenced = {}
local function MultiEvents(frame)
	local events = { "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED" }
	for _, key in ipairs({ "showGridEventName", "hideGridEventName" }) do
		local event = rawget(frame, key)
		if type(event) == "string" then events[#events + 1] = event end
	end
	return events
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

local function Unwanted(frame)
	if type(frame) ~= "table" then return false end
	local name = FrameName(frame)
	if name and (name:match("^ExtraActionButton%d") or name == "GamepadMainActionBarFramePageUnitLeftClassAction") then
		return false
	end
	if HiddenByUs(frame) then return true end
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
	local total = 0
	for _, name in ipairs(DISPATCHERS) do
		local owner = _G[name]
		if owner then
			total = total + PruneDispatcher(owner)
			if not rawget(owner, "sanctuaryHooked") and type(owner.RegisterFrame) == "function" then
				owner.sanctuaryHooked = true
				hooksecurefunc(owner, "RegisterFrame", function(self, frame)
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
	return ("Blizzard bar events: controller %s, %d button(s) taken out of the shared loops%s"):format(
		ns.Blizzard.controllerQuiet and "quiet" or "running", ns.Blizzard.prunedCount or 0,
		GamepadActive() and ", gamepad active" or "")
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
	WatchHelpTips()
	ns.Blizzard.CloseOrphanTips()
	ns.Blizzard.PruneDispatchers()
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
					for _, event in ipairs(MultiEvents(frame)) do pcall(frame.RegisterEvent, frame, event) end
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
				frame.sanctuaryAllow = nil
				pcall(frame.SetParent, frame, ns.Hider)
				pcall(Suppress, frame)
			elseif frame:GetParent() == ns.Hider then
				Restore(frame, UIParent)
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
