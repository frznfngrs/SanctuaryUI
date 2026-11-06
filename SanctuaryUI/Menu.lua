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

local ENTRIES = {
	{
		key = "character",
		label = CHARACTER_BUTTON or "Character",
		binding = "TOGGLECHARACTER0",
		toggle = function() ToggleCharacter("PaperDollFrame") end,
	},
	{
		key = "spellbook",
		label = SPELLBOOK_ABILITIES_BUTTON or "Spellbook & Abilities",
		binding = "TOGGLESPELLBOOK",
		toggle = ToggleSpells,
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
	local ok, err = pcall(fn)
	if not ok and not entry.warned then
		entry.warned = true
		ns.Print(("%s button failed: %s"):format(entry.label, tostring(err)))
	end
end

local function MakeMenuButton(parent, entry)
	local button = CreateFrame("Button", "SanctuaryUIMenu_" .. entry.key, parent)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:SetScript("OnClick", function(_, mouseButton)
		if mouseButton == "RightButton" and entry.right then
			Run(entry, entry.right)
		else
			Run(entry, entry.toggle)
		end
	end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(entry.label)
		AddBindingLine(entry.binding)
		if entry.right then
			GameTooltip:AddLine("Right-click: " .. entry.rightLabel, 0.7, 0.7, 0.7)
		end
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	-- After SetScript: it replaces handlers, including hooks added before it.
	Art(button, entry.key)
	return button
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
	end
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
