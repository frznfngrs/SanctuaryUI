SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.Menu = ns.Menu or {}

-- Item the portal socket uses; Options can point it at another hearth item.
local function Hearth()
	return tonumber(ns.DB().hearthItem) or 6948
end

-- The five D3 menu buttons, left to right. On Forever (a modern client) several micro
-- buttons open their panel from mouse-down handlers, so clicking them does nothing; these
-- call the same toggle functions ElvUI uses on this client instead.
local function ToggleSpells()
	if PlayerSpellsUtil and PlayerSpellsUtil.ToggleSpellBookFrame then
		PlayerSpellsUtil.ToggleSpellBookFrame()
	elseif ToggleSpellBook then
		ToggleSpellBook(BOOKTYPE_SPELL or "spell")
	elseif SpellBookFrame then
		ToggleFrame(SpellBookFrame)
	end
end

local function ToggleTalents()
	if PlayerSpellsUtil and PlayerSpellsUtil.ToggleClassTalentFrame then
		PlayerSpellsUtil.ToggleClassTalentFrame()
	elseif ToggleTalentFrame then
		ToggleTalentFrame()
	end
end

local function ToggleProfessions()
	if ToggleProfessionsBook then
		ToggleProfessionsBook()
	elseif PlayerSpellsUtil and PlayerSpellsUtil.ToggleProfessionsBook then
		PlayerSpellsUtil.ToggleProfessionsBook()
	elseif ToggleSpellBook and BOOKTYPE_PROFESSION then
		ToggleSpellBook(BOOKTYPE_PROFESSION)
	end
end

-- Press one of Blizzard's (hidden) micro buttons the way the mouse does. On Forever several
-- act from their mouse-down handler, so a plain :Click() does nothing.
local function PressMicro(name)
	local button = _G[name]
	if not button then return end
	local down, up = button:GetScript("OnMouseDown"), button:GetScript("OnMouseUp")
	if down or up then
		if down then down(button, "LeftButton") end
		if up then up(button, "LeftButton") end
	else
		button:Click()
	end
end

local function TogglePvP()
	if TogglePVPUI then
		TogglePVPUI()
	elseif TogglePVPFrame then
		TogglePVPFrame()
	elseif PVPFrame then
		ToggleFrame(PVPFrame)
	else
		PressMicro("PVPMicroButton")
	end
end

-- Forever's group finder has its own toggle (ElvUI uses it here).
local function ToggleGroupFinder()
	if ToggleGroupFinderFrame then
		ToggleGroupFinderFrame()
	elseif PVEFrame_ToggleFrame then
		PVEFrame_ToggleFrame()
	elseif ToggleLFDParentFrame then
		ToggleLFDParentFrame()
	elseif ToggleLFGParentFrame then
		ToggleLFGParentFrame()
	else
		PressMicro("LFDMicroButton")
	end
end

-- The panels behind the flyout button (D3 tab plates, menu-tabs.png), left to right. Panels
-- this client lacks are left out.
local FLYOUT = {
	{
		key = "spellbook",
		label = SPELLBOOK or "Spellbook", -- Professions has its own button
		binding = "TOGGLESPELLBOOK",
		toggle = ToggleSpells,
		available = function() return PlayerSpellsUtil or ToggleSpellBook or SpellBookFrame end,
	},
	{
		key = "professions",
		label = PROFESSIONS_BUTTON or TRADE_SKILLS or "Professions",
		binding = "TOGGLEPROFESSIONBOOK",
		toggle = ToggleProfessions,
		available = function()
			return ToggleProfessionsBook or (PlayerSpellsUtil and PlayerSpellsUtil.ToggleProfessionsBook) or (ToggleSpellBook and BOOKTYPE_PROFESSION)
		end,
	},
	{
		key = "collections",
		label = COLLECTIONS or "Collections",
		binding = "TOGGLECOLLECTIONS",
		toggle = function() ToggleCollectionsJournal() end,
		available = function() return ToggleCollectionsJournal end,
	},
	{
		-- Forever's Legacy system takes the achievements button's place.
		key = "legacy",
		label = LEGACY_BUTTON or "Legacy",
		toggle = function() ToggleLegacySystemUI() end,
		available = function() return ToggleLegacySystemUI end,
	},
	{
		key = "achievements",
		label = ACHIEVEMENTS or "Achievements",
		binding = "TOGGLEACHIEVEMENT",
		toggle = function() ToggleAchievementFrame() end,
		available = function() return ToggleAchievementFrame and not ToggleLegacySystemUI end,
	},
	{
		key = "groupfinder",
		label = LFG_TITLE or DUNGEONS_BUTTON or "Group Finder",
		binding = "TOGGLEGROUPFINDER",
		toggle = ToggleGroupFinder,
		available = function()
			return ToggleGroupFinderFrame or PVEFrame_ToggleFrame or ToggleLFDParentFrame or ToggleLFGParentFrame or _G.LFDMicroButton
		end,
	},
	{
		key = "pvp",
		label = PLAYER_V_PLAYER or PVP or "Player vs. Player",
		binding = "TOGGLECHARACTER4",
		toggle = TogglePvP,
		available = function() return TogglePVPUI or TogglePVPFrame or PVPFrame or _G.PVPMicroButton end,
	},
	{
		key = "currency",
		label = CURRENCY or "Currency",
		binding = "TOGGLECURRENCY",
		toggle = function() ToggleCharacter("TokenFrame") end,
		available = function() return _G.TokenFrame or (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyListSize) end,
	},
	{
		key = "reputation",
		label = REPUTATION or "Reputation",
		binding = "TOGGLECHARACTER2",
		toggle = function() ToggleCharacter("ReputationFrame") end,
		available = function() return _G.ReputationFrame or ToggleCharacter end,
	},
}

-- The menu buttons. cell picks the plate art when it differs from the key: Character wears the
-- figure (the "spellbook" plate); the flyout button has its own tome plate.
local ENTRIES = {
	{
		key = "character",
		cell = "spellbook",
		label = CHARACTER_BUTTON or "Character",
		binding = "TOGGLECHARACTER0",
		toggle = function() ToggleCharacter("PaperDollFrame") end,
	},
	{
		key = "flyout",
		label = "Spellbook & Panels",
		flyout = true,
	},
	{
		key = "talents",
		label = TALENTS_BUTTON or "Talents",
		binding = "TOGGLETALENTS",
		toggle = ToggleTalents,
	},
	{
		-- D3's shield is the clan button: left opens friends, right opens the guild.
		key = "social",
		label = SOCIAL_BUTTON or "Social",
		binding = "TOGGLESOCIAL",
		toggle = function() ToggleFriendsFrame() end,
		right = function() if ToggleGuildFrame then ToggleGuildFrame() end end,
		rightLabel = GUILD or "Guild",
	},
	{
		key = "quests",
		label = QUESTLOG_BUTTON or "Quest Log",
		binding = "TOGGLEQUESTLOG",
		toggle = function() ToggleQuestLog() end,
	},
	{
		key = "bags",
		label = BAGSLOT or "Bags",
		binding = "OPENALLBAGS",
		toggle = function() ToggleAllBags() end,
	},
}

-- Sheet positions (BottomBar_GameRes): five cells across the black panel, then the lock slot.
-- Six plates across the widened black panel (x 1056-1244).
local PANEL_X, PANEL_Y, PITCH = 1056, 111, 188 / 6
local CELL_W, CELL_H = 40, 66
-- The portal sprite drawn at native size, centred in the old lock slot (x 1010-1051). Its plate
-- spans the same cell rows as the menu plates (3-65), so it sits on the menu row (PANEL_Y);
-- it is wider than they are, as in D3.
local HEARTH_CELL = { 1030.5 - CELL_W / 2, PANEL_Y, CELL_W, CELL_H }

local function AddBindingLine(binding)
	local key = binding and GetBindingKey(binding)
	if key then
		GameTooltip:AddLine(GetBindingText and GetBindingText(key) or key, 0.86, 0.72, 0.42)
	end
end


-- D3 buttons switch plates by state: muted at rest, bright on hover, smaller when pressed.
-- A disabled button (the portal without a hearthstone) shows the grey plate.
local function ShowState(button)
	local state = "normal"
	if button.sanctuaryDisabled then
		state = "disabled"
	elseif button.sanctuaryDown then
		state = "pressed"
	elseif button.sanctuaryOver then
		state = "hover"
	end
	if button.Art and ns.Art.Path("menu") then
		button.Art:SetTexCoord(ns.Art.MenuTexCoord(button.sanctuaryCell, state))
	end
end

local function Art(button, cell)
	local art = button:CreateTexture(nil, "ARTWORK")
	art:SetAllPoints()
	if not ns.Art.Apply(art, "menu") then
		art:SetColorTexture(0.35, 0.18, 0.05, 1)
	end
	button.Art = art
	button.sanctuaryCell = cell
	ShowState(button)
	button:HookScript("OnEnter", function(self) self.sanctuaryOver = true; ShowState(self) end)
	button:HookScript("OnLeave", function(self) self.sanctuaryOver = false; self.sanctuaryDown = false; ShowState(self) end)
	button:HookScript("OnMouseDown", function(self) self.sanctuaryDown = true; ShowState(self) end)
	button:HookScript("OnMouseUp", function(self) self.sanctuaryDown = false; ShowState(self) end)
end

local function Run(entry, fn)
	local ok, err = ns.Try("menu " .. entry.label, fn)
	if not ok and not entry.warned then
		entry.warned = true
		ns.Print(("%s button failed: %s"):format(entry.label, tostring(err)))
	end
end

local ToggleFlyout

local function MakeMenuButton(parent, entry)
	local button = CreateFrame("Button", "SanctuaryUIMenu_" .. entry.key, parent)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:SetScript("OnClick", function(_, mouseButton)
		if entry.flyout then
			ToggleFlyout()
		elseif mouseButton == "RightButton" and entry.right then
			Run(entry, entry.right)
		else
			Run(entry, entry.toggle)
		end
	end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(entry.label)
		AddBindingLine(entry.binding)
		if entry.flyout then
			local names = {}
			for _, item in ipairs(ns.Menu.flyoutItems or {}) do
				names[#names + 1] = item.entry.label
			end
			GameTooltip:AddLine(table.concat(names, ", "), 0.7, 0.7, 0.7, true)
		end
		if entry.right then
			GameTooltip:AddLine("Right-click: " .. entry.rightLabel, 0.7, 0.7, 0.7)
		end
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	-- After SetScript: it replaces handlers, including hooks added before it.
	Art(button, entry.cell or entry.key)
	return button
end

---------------------------------------------------------------------------
-- Flyout: a row of the same D3 menu plates (menu-flyout.png, gold icons) on a dark panel above
-- the flyout button, on the menu's own pitch. Plates switch by state like the menu buttons:
-- muted at rest, bright on hover, smaller pressed. Click areas meet edge to edge.

local function FlyoutState(button)
	local state = "normal"
	if button.sanctuaryDown then
		state = "pressed"
	elseif button.sanctuaryOver then
		state = "hover"
	end
	if ns.Art.Path("menuFlyout") then
		button.Art:SetTexCoord(ns.Art.FlyoutTexCoord(button.entry.key, state))
	end
end

local function MakeFlyoutButton(flyout, entry)
	local button = CreateFrame("Button", "SanctuaryUIMenuFlyout_" .. entry.key, flyout)
	button.entry = entry
	button:RegisterForClicks("LeftButtonUp")
	button.Art = button:CreateTexture(nil, "ARTWORK")
	button.Art:SetAllPoints()
	if not ns.Art.Apply(button.Art, "menuFlyout") then
		button.Art:SetColorTexture(0.35, 0.18, 0.05, 1)
	end
	button:SetScript("OnEnter", function(self)
		self.sanctuaryOver = true
		FlyoutState(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(entry.label)
		AddBindingLine(entry.binding)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function(self)
		self.sanctuaryOver, self.sanctuaryDown = false, false
		FlyoutState(self)
		GameTooltip_Hide()
	end)
	button:SetScript("OnMouseDown", function(self) self.sanctuaryDown = true; FlyoutState(self) end)
	button:SetScript("OnMouseUp", function(self) self.sanctuaryDown = false; FlyoutState(self) end)
	button:SetScript("OnClick", function()
		flyout:Hide()
		Run(entry, entry.toggle)
	end)
	FlyoutState(button)
	return button
end

local function MakeFlyout(parent)
	local flyout = CreateFrame("Frame", "SanctuaryUIMenuFlyout", parent)
	flyout:SetFrameStrata("DIALOG")
	flyout:SetClampedToScreen(true)
	flyout:EnableMouse(true) -- the panel itself takes clicks, so none fall through between plates
	flyout:Hide()
	-- The dark panel behind the plates, edged like the console's.
	local edge = flyout:CreateTexture(nil, "BACKGROUND", nil, -1)
	edge:SetAllPoints()
	edge:SetColorTexture(0.42, 0.32, 0.17, 0.95)
	local back = flyout:CreateTexture(nil, "BACKGROUND")
	back:SetPoint("TOPLEFT", 1, -1)
	back:SetPoint("BOTTOMRIGHT", -1, 1)
	back:SetColorTexture(0.02, 0.015, 0.01, 0.94)
	-- Escape closes it, like a panel.
	tinsert(UISpecialFrames, flyout:GetName())
	ns.Menu.flyoutItems = {}
	for _, entry in ipairs(FLYOUT) do
		if entry.available() then
			ns.Menu.flyoutItems[#ns.Menu.flyoutItems + 1] = MakeFlyoutButton(flyout, entry)
		end
	end
	-- A click anywhere else closes it.
	flyout:SetScript("OnShow", function(self)
		for _, button in ipairs(ns.Menu.flyoutItems) do
			button.sanctuaryOver, button.sanctuaryDown = false, false
			FlyoutState(button)
		end
		pcall(self.RegisterEvent, self, "GLOBAL_MOUSE_DOWN")
	end)
	flyout:SetScript("OnHide", function(self)
		pcall(self.UnregisterEvent, self, "GLOBAL_MOUSE_DOWN")
	end)
	flyout:SetScript("OnEvent", function(self)
		local button = ns.Menu.flyoutButton
		if self:IsMouseOver() or (button and button:IsMouseOver()) then return end
		self:Hide()
	end)
	return flyout
end

ToggleFlyout = function()
	local flyout = ns.Menu.flyout
	if not flyout then return end
	-- No panel available on this client: the button is just the spellbook.
	if #ns.Menu.flyoutItems == 0 then
		ToggleSpells()
		return
	end
	flyout:SetShown(not flyout:IsShown())
	GameTooltip_Hide()
end

local FLYOUT_PAD = 3 -- panel margin around the plates, sheet px
local FLYOUT_PER_ROW = 6 -- longer flyouts wrap upward into more rows

local function LayoutFlyout(scale)
	local flyout, button = ns.Menu.flyout, ns.Menu.flyoutButton
	if not flyout or not button then return end
	local items = ns.Menu.flyoutItems
	-- Cells are 40 wide on a 31.3 pitch (the plates' transparent margins overlap, as in the
	-- console); each click area is trimmed to the pitch so neighbours meet with no gap.
	local w, h, pitch = CELL_W * scale, CELL_H * scale, PITCH * scale
	local margin = (CELL_W - PITCH) / 2 * scale
	local pad = FLYOUT_PAD * scale
	local cols = math.min(FLYOUT_PER_ROW, math.max(1, #items))
	local rows = math.max(1, math.ceil(#items / FLYOUT_PER_ROW))
	flyout:SetSize(pitch * cols + 2 * pad, h * rows + 2 * pad)
	flyout:ClearAllPoints()
	flyout:SetPoint("BOTTOM", button, "TOP", 0, 3 * scale)
	for i, item in ipairs(items) do
		local row, col = math.floor((i - 1) / FLYOUT_PER_ROW), (i - 1) % FLYOUT_PER_ROW
		item:SetSize(w, h)
		item:ClearAllPoints()
		item:SetPoint("TOPLEFT", flyout, "TOPLEFT", pad - margin + col * pitch, -(pad + row * h))
		item:SetHitRectInsets(margin, margin, 0, 0)
		FlyoutState(item)
	end
end

-- LibKeyBound hover-binding for buttons that are not LibActionButton buttons.
-- The binding lives in Bindings.xml; override bindings route it to the button.
function ns.Menu.KeyBindable(button, binding, label)
	button.GetActionName = function() return label end
	button.GetBindings = function()
		local keys = {}
		for k = 1, select("#", GetBindingKey(binding)) do
			keys[#keys + 1] = GetBindingText and GetBindingText((select(k, GetBindingKey(binding)))) or select(k, GetBindingKey(binding))
		end
		return table.concat(keys, ", ")
	end
	button.GetHotkey = function()
		local key = GetBindingKey(binding)
		local KeyBound = LibStub("LibKeyBound-1.0", true)
		return key and KeyBound and KeyBound:ToShortKey(key) or key
	end
	button.SetKey = function(_, key)
		SetBinding(key, binding)
	end
	button.ClearBindings = function()
		while GetBindingKey(binding) do
			SetBinding(GetBindingKey(binding), nil)
		end
	end
	button:HookScript("OnEnter", function(self)
		local KeyBound = LibStub("LibKeyBound-1.0", true)
		if KeyBound then
			KeyBound:Set(self)
		end
	end)
end

local function HearthCount()
	if C_Item and C_Item.GetItemCount then
		return C_Item.GetItemCount(Hearth()) or 0
	end
	return GetItemCount and GetItemCount(Hearth()) or 0
end

local function HearthCooldown()
	if C_Container and C_Container.GetItemCooldown then
		return C_Container.GetItemCooldown(Hearth())
	end
	if GetItemCooldown then
		return GetItemCooldown(Hearth())
	end
end

function ns.Menu.UpdateHearth()
	local hearth = ns.HearthButton
	if not hearth then return end
	local have = HearthCount() > 0
	hearth.sanctuaryDisabled = not have
	ShowState(hearth)
	local start, duration, enable = HearthCooldown()
	if start and duration then
		pcall(CooldownFrame_Set, hearth.cooldown, start, duration, enable)
	end
end

local function MakeHearth(parent)
	local hearth = CreateFrame("Button", "SanctuaryUIHearthButton", parent, "SecureActionButtonTemplate")
	hearth:RegisterForClicks("AnyUp", "AnyDown")
	hearth:SetAttribute("type", "item")
	hearth:SetAttribute("item", "item:" .. Hearth())
	hearth.cooldown = CreateFrame("Cooldown", "SanctuaryUIHearthCooldown", hearth, "CooldownFrameTemplate")
	hearth.cooldown:SetAllPoints()
	hearth:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		if GameTooltip.SetItemByID then
			GameTooltip:SetItemByID(Hearth())
		else
			GameTooltip:SetText("Hearthstone")
		end
		AddBindingLine("SANCTUARYUIHEARTH")
		GameTooltip:Show()
	end)
	hearth:SetScript("OnLeave", GameTooltip_Hide)
	-- After SetScript: it replaces handlers, including hooks added before it.
	Art(hearth, "hearth")
	return hearth
end

function ns.Menu.ReassignBindings()
	local hearth = ns.HearthButton
	if not hearth or InCombatLockdown() then return end
	ClearOverrideBindings(hearth)
	for k = 1, select("#", GetBindingKey("SANCTUARYUIHEARTH")) do
		local key = select(k, GetBindingKey("SANCTUARYUIHEARTH"))
		if key and key ~= "" then
			SetOverrideBindingClick(hearth, false, key, hearth:GetName(), "LeftButton")
		end
	end
end

function ns.Menu.Layout(metrics, base)
	local cluster = ns.Cluster
	if not cluster or not ns.Menu.buttons then return end
	local scale = metrics.scale
	local level = cluster:GetFrameLevel() + ns.LEVEL.menu
	local function place(button, x0, y0, w, h)
		local x = (x0 + w / 2) * scale - metrics.width / 2
		local y = metrics.height / 2 - (y0 + h / 2) * scale
		button:SetSize(w * scale, h * scale)
		button:ClearAllPoints()
		button:SetPoint("CENTER", cluster, "BOTTOM", x, base + y)
		button:SetFrameLevel(level)
	end
	for i, button in ipairs(ns.Menu.buttons) do
		local cx = PANEL_X + PITCH / 2 + (i - 1) * PITCH
		place(button, cx - CELL_W / 2, PANEL_Y, CELL_W, CELL_H)
		button:SetHitRectInsets(CELL_W * scale * 0.18, CELL_W * scale * 0.18, 0, 0)
	end
	local c = HEARTH_CELL
	place(ns.HearthButton, c[1], c[2], c[3], c[4])
	LayoutFlyout(scale)
end

function ns.Menu.ApplySettings()
	local hearth = ns.HearthButton
	if not hearth or InCombatLockdown() then return end
	hearth:SetAttribute("item", "item:" .. Hearth())
	ns.Menu.UpdateHearth()
end

function ns.Menu.Init()
	local parent = ns.Cluster
	ns.Menu.buttons = {}
	for i, entry in ipairs(ENTRIES) do
		ns.Menu.buttons[i] = MakeMenuButton(parent, entry)
		if entry.flyout then
			ns.Menu.flyoutButton = ns.Menu.buttons[i]
		end
	end
	ns.Menu.flyout = MakeFlyout(parent)
	ns.HearthButton = MakeHearth(parent)
	ns.Menu.KeyBindable(ns.HearthButton, "SANCTUARYUIHEARTH", "Hearthstone")

	local events = CreateFrame("Frame", nil, ns.HearthButton)
	events:RegisterEvent("BAG_UPDATE_COOLDOWN")
	events:RegisterEvent("BAG_UPDATE_DELAYED")
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:RegisterEvent("UPDATE_BINDINGS")
	events:SetScript("OnEvent", function(_, event)
		if event == "UPDATE_BINDINGS" or event == "PLAYER_ENTERING_WORLD" then
			ns.Menu.ReassignBindings()
		end
		ns.Menu.UpdateHearth()
	end)
	ns.Menu.UpdateHearth()
end
