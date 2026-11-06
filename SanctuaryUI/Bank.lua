SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.Bank = ns.Bank or {}
local W = ns.InvWindow

-- The bank window: D3's stash (treasure-chest medallion), built by InventoryWindow.lua like
-- the bag window.
--
-- Forever's bank is the modern tabbed bank: tab 1 is the base bank and tabs 2-9 are bank
-- bags of any size, held in the Characterbanktab container (slots 2-9). Bank slots use
-- BankItemButtonTemplate with bankTabID / containerSlotID fields, as ElvUI does here.
-- Blizzard's bank frame is disabled but kept shown (anchorless, so it never draws): hiding
-- it would end the bank session. Closing our window closes the bank.

local BagIndex = Enum and Enum.BagIndex or {}
local CHARACTERBANK_TYPE = Enum and Enum.BankType and Enum.BankType.Character or 0
local TAB_CONTAINER = BagIndex.Characterbanktab
local MODERN = BagIndex.CharacterBankTab_1 ~= nil

local TABS = {}
for i = 1, 9 do
	local id = BagIndex["CharacterBankTab_" .. i]
	if id then
		TABS[#TABS + 1] = id
	end
end
-- Older clients: the classic bank container plus bank bags.
local CLASSIC = { BANK_CONTAINER or -1 }
for bag = (NUM_BAG_SLOTS or 4) + 1, (NUM_BAG_SLOTS or 4) + (NUM_BANKBAGSLOTS or 7) do
	CLASSIC[#CLASSIC + 1] = bag
end

local BANK_ICON = "Interface\\Icons\\INV_Box_02" -- a chest, on the base bank slot

local function Opt()
	return ns.DB().bank
end

-- Tabs that exist and have slots.
local function Containers()
	if not MODERN then
		return CLASSIC
	end
	local list = {}
	for _, id in ipairs(TABS) do
		if W.NumSlots(id) > 0 then
			list[#list + 1] = id
		end
	end
	return list
end

local function Template(bag)
	if MODERN then
		return "BankItemButtonTemplate"
	end
	return bag == (BANK_CONTAINER or -1) and "BankItemButtonGenericTemplate" or "ContainerFrameItemButtonTemplate"
end

local function InitSlot(button, bag, slot)
	if MODERN then
		button.bankTabID, button.containerSlotID = bag, slot
	end
end

---------------------------------------------------------------------------
-- Bank bag slots (modern bank): slot 1 is the base bank, 2-9 hold bank bags.

local function Purchased()
	if C_Bank and C_Bank.FetchNumPurchasedBankTabs then
		return C_Bank.FetchNumPurchasedBankTabs(CHARACTERBANK_TYPE) or 0
	end
	return 0
end

local function PickupTab(button)
	if button.slotID > 1 and TAB_CONTAINER then
		local pickup = C_Container and C_Container.PickupContainerItem or PickupContainerItem
		pickup(TAB_CONTAINER, button.slotID)
	end
end

local function SlotRow(win)
	if not MODERN or not TAB_CONTAINER then
		return {}
	end
	local list = {}
	for slotID = 1, #TABS do
		local button = ns.Bags.SlotButton(win.frame, "SanctuaryUIBankSlot" .. slotID)
		button.slotID = slotID
		button:SetScript("OnClick", function(self)
			if GetCursorInfo() then PickupTab(self) end
		end)
		button:SetScript("OnReceiveDrag", PickupTab)
		button:SetScript("OnDragStart", PickupTab)
		button:SetScript("OnEnter", function(self)
			if GameTooltip:IsForbidden() then return end
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			if self.slotID == 1 then
				GameTooltip:SetText(BANK or "Bank")
			elseif self.hasBag then
				GameTooltip:SetBagItem(TAB_CONTAINER, self.slotID)
			else
				GameTooltip:SetText(self.purchased and (BANK_BAG or "Bank Bag") or (BANK_BAG_PURCHASE or "Purchasable Bank Slot"), 1, 1, 1)
			end
			GameTooltip:Show()
		end)
		list[#list + 1] = button
	end
	return list
end

local function UpdateRow(win)
	local purchased = Purchased()
	for _, button in ipairs(win.frame.rowButtons) do
		local texture
		if button.slotID == 1 then
			texture = BANK_ICON
			button.purchased, button.hasBag = true, false
		else
			local info = W.Info(TAB_CONTAINER, button.slotID)
			texture = info and info.iconFileID
			button.purchased = button.slotID <= purchased
			button.hasBag = texture ~= nil
		end
		button.icon:SetTexture(texture)
		button.icon:SetShown(texture ~= nil)
		-- Slots not bought yet are stained red, like Blizzard's.
		if button.sanctuarySocketTex then
			if button.purchased then
				button.sanctuarySocketTex:SetVertexColor(1, 1, 1)
			else
				button.sanctuarySocketTex:SetVertexColor(1, 0.3, 0.25)
			end
		end
	end
	-- Buy Slot only while there is one to buy.
	local buy = win.frame.buy
	if buy and not InCombatLockdown() then
		local can = C_Bank and C_Bank.CanPurchaseBankTab and C_Bank.CanPurchaseBankTab(CHARACTERBANK_TYPE)
		buy:SetShown(can and buy.target ~= nil and true or false)
	end
end

---------------------------------------------------------------------------
-- Footer: Buy Slot clicks Blizzard's own purchase button (secure), as ElvUI does.

local function PurchaseButton()
	local panel = _G.BankPanel
	local prompt = panel and panel.PurchasePrompt
	local cost = prompt and prompt.TabCostFrame
	return cost and cost.PurchaseButton
end

local function MakeBuy(frame)
	local button = CreateFrame("Button", "SanctuaryUIBankBuy", frame, "SecureActionButtonTemplate")
	local plate = button:CreateTexture(nil, "BACKGROUND")
	plate:SetAllPoints()
	if ns.Art.Apply(plate, "d3Button") then
		plate:SetTexCoord(0, 120 / 128, 0, 52 / 64)
	end
	local hover = button:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints()
	hover:SetColorTexture(1, 0.7, 0.3, 0.15)
	local text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	text:SetPoint("CENTER", 0, 1)
	text:SetText("Buy Slot")
	button.sanctuaryWidth = 84
	local target = PurchaseButton()
	button.target = target
	if target then
		button:SetAttribute("type", "click")
		button:SetAttribute("clickbutton", target)
		button:RegisterForClicks("AnyUp", "AnyDown")
	end
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(BANKSLOTPURCHASE or "Purchase a bank slot")
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	button:Hide()
	return button
end

---------------------------------------------------------------------------
-- Open / close with the bank session

local function CloseBank()
	if C_Bank and C_Bank.CloseBankFrame then
		C_Bank.CloseBankFrame()
	elseif CloseBankFrame then
		CloseBankFrame()
	end
end

-- The Buy Slot button is secure, which makes the whole window protected: it can only show
-- or hide out of combat. A change asked for in combat waits for PLAYER_REGEN_ENABLED.
local function SetWindowShown(shown)
	local win = ns.Bank.win
	if not win then return end
	if InCombatLockdown() then
		if shown and ns.Bank.pendingShown == nil then
			ns.Print("the bank window will open when combat ends")
		end
		ns.Bank.pendingShown = shown
		return
	end
	ns.Bank.pendingShown = nil
	if shown then
		win:Refresh()
		win:Open()
	else
		win:Close()
	end
end

local function Opened()
	local win = ns.Bank.win
	if not win or not Opt().enabled then return end
	ns.Bank.open = true
	-- Keep Blizzard's (invisible) bank frame shown: hiding it ends the session.
	if BankFrame and not BankFrame:IsShown() then
		BankFrame:Show()
	end
	local target = win.frame.buy and win.frame.buy.target
	if target then
		target:SetAttribute("overrideBankType", CHARACTERBANK_TYPE)
	end
	SetWindowShown(true)
	ns.Bags.Open()
end

local function Closed()
	ns.Bank.open = false
	SetWindowShown(false)
	if BankFrame and BankFrame:IsShown() then
		BankFrame:Hide()
	end
	local target = ns.Bank.win and ns.Bank.win.frame.buy and ns.Bank.win.frame.buy.target
	if target then
		target:SetAttribute("overrideBankType", nil)
	end
end

---------------------------------------------------------------------------

function ns.Bank.ApplySettings()
	local win = ns.Bank.win
	if not win then return end
	if not Opt().enabled then
		SetWindowShown(false)
		return
	end
	win:Layout()
	win:Update()
end

function ns.Bank.Init()
	if not Opt().enabled or not ns.DB().bags.enabled then return end
	local win = W.New({
		name = "SanctuaryUIBank",
		key = "bank",
		art = "bankFrame",
		containers = Containers,
		template = Template,
		initSlot = InitSlot,
		slotRow = SlotRow,
		updateRow = UpdateRow,
		onClose = function() CloseBank() end,
		onShow = function() PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPEN or 850) end,
		onHide = function()
			PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_CLOSE or 851)
			-- Escape or the X: end the bank session too.
			if ns.Bank.open then
				CloseBank()
			end
		end,
		footer = {
			{
				key = "sort",
				label = "Sort",
				onClick = function()
					if C_Container and C_Container.SortBankBags and not InCombatLockdown() then
						C_Container.SortBankBags()
					end
				end,
				setup = function(button)
					button:SetShown(C_Container and C_Container.SortBankBags and true or false)
				end,
			},
			{
				key = "deposit",
				label = "Deposit",
				onClick = function()
					if C_Bank and C_Bank.AutoDepositItemsIntoBank then
						C_Bank.AutoDepositItemsIntoBank(CHARACTERBANK_TYPE)
					end
				end,
				setup = function(button)
					button:SetShown(C_Bank and C_Bank.AutoDepositItemsIntoBank and true or false)
					button:SetScript("OnEnter", function(self)
						GameTooltip:SetOwner(self, "ANCHOR_TOP")
						GameTooltip:SetText("Deposit")
						GameTooltip:AddLine("Move items from your bags into the bank.", 1, 1, 1, true)
						GameTooltip:Show()
					end)
					button:SetScript("OnLeave", GameTooltip_Hide)
				end,
			},
			{ key = "buy", make = MakeBuy },
		},
	})
	ns.Bank.win = win

	if BankFrame then
		ns.Bags.DisableFrame(BankFrame, true)
	end

	local events = CreateFrame("Frame", nil, win.frame)
	for _, event in ipairs({ "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "BAG_UPDATE_DELAYED", "BAG_CONTAINER_UPDATE", "PLAYERBANKSLOTS_CHANGED", "BANK_TABS_CHANGED", "BANK_TAB_SETTINGS_UPDATED", "ITEM_LOCK_CHANGED", "INVENTORY_SEARCH_UPDATE", "PLAYER_MONEY", "PLAYER_REGEN_ENABLED" }) do
		pcall(events.RegisterEvent, events, event)
	end
	events:SetScript("OnEvent", function(_, event)
		if event == "BANKFRAME_OPENED" then
			Opened()
		elseif event == "BANKFRAME_CLOSED" then
			Closed()
		elseif event == "PLAYER_REGEN_ENABLED" and ns.Bank.pendingShown ~= nil then
			SetWindowShown(ns.Bank.pendingShown and ns.Bank.open)
		elseif event == "BAG_CONTAINER_UPDATE" or event == "BANK_TABS_CHANGED" or (event == "PLAYER_REGEN_ENABLED" and win.pendingLayout) then
			win:Refresh()
		else
			win:Update()
		end
	end)
end
