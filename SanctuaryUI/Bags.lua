SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.Bags = ns.Bags or {}
local W = ns.InvWindow

-- The bag window: D3's inventory (coin-sack medallion), built by InventoryWindow.lua.
-- Blizzard's bag frames are disabled; their toggle functions are hooked so the B key,
-- vendors, the mailbox and the menu's bag button all open this window. Blizzard's bag bar
-- is hidden too (Blizzard.lua), so the slot row here is where bags get equipped.

local BAGS = {}
for bag = 0, NUM_BAG_SLOTS or 4 do
	BAGS[#BAGS + 1] = bag
end
-- The reagent bag (bag 5 on modern clients) sits after the four bag slots.
local REAGENT_BAG = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag
if REAGENT_BAG then
	BAGS[#BAGS + 1] = REAGENT_BAG
end

local BACKPACK_ICON = 133633 -- Interface\Icons\INV_Misc_Bag_08

local function Opt()
	return ns.DB().bags
end

---------------------------------------------------------------------------
-- Bag slots: the backpack, the four equippable bag slots and the reagent bag slot.

local function InvSlot(bag)
	if C_Container and C_Container.ContainerIDToInventoryID then
		return C_Container.ContainerIDToInventoryID(bag)
	end
	return ContainerIDToInventoryID and ContainerIDToInventoryID(bag)
end

function ns.Bags.SlotButton(parent, name)
	local button = CreateFrame("Button", name, parent)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetAllPoints()
	button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	button.sanctuary, button.sanctuarySquare, button.sanctuarySocket = true, true, true
	ns.Art.AttachRing(button)
	ns.Art.GoldLights(button)
	ns.Art.FitGoldLights(button)
	button:HookScript("OnSizeChanged", ns.Art.FitGoldLights)
	button:SetScript("OnLeave", GameTooltip_Hide)
	return button
end

local function DropOn(button)
	if button.bag == 0 then
		PutItemInBackpack()
	elseif button.inv then
		PutItemInBag(button.inv)
	end
end

local function SlotRow(win)
	local list = {}
	for _, bag in ipairs(BAGS) do
		-- The keyring's items are in the grid, but it has no slot to equip a bag in.
		if bag ~= W.keyring then
			local button = ns.Bags.SlotButton(win.frame, "SanctuaryUIBagSlot" .. bag)
			button.bag, button.sanctuaryBag = bag, bag
			button.inv = bag > 0 and InvSlot(bag) or nil
			button:SetScript("OnClick", function(self)
				if GetCursorInfo() then DropOn(self) end
			end)
			button:SetScript("OnReceiveDrag", DropOn)
			button:SetScript("OnDragStart", function(self)
				if self.inv then PickupBagFromSlot(self.inv) end
			end)
			button:SetScript("OnEnter", function(self)
				if GameTooltip:IsForbidden() then return end
				GameTooltip:SetOwner(self, "ANCHOR_TOP")
				if self.bag == 0 then
					GameTooltip:SetText(BACKPACK_TOOLTIP or "Backpack")
				elseif not self.inv or not GameTooltip:SetInventoryItem("player", self.inv) then
					GameTooltip:SetText(EQUIP_CONTAINER or "Equip Container", 1, 1, 1)
				end
				GameTooltip:Show()
			end)
			list[#list + 1] = button
		end
	end
	return list
end

local function UpdateRow(win)
	for _, button in ipairs(win.frame.rowButtons) do
		local texture = button.bag == 0 and BACKPACK_ICON or (button.inv and GetInventoryItemTexture("player", button.inv))
		button.icon:SetTexture(texture)
		button.icon:SetShown(texture ~= nil)
	end
end

---------------------------------------------------------------------------
-- Selling junk at a vendor

local function MerchantOpen()
	return MerchantFrame and MerchantFrame:IsShown()
end

-- Grey items that sell for something.
local function JunkSlots()
	local list = {}
	for _, bag in ipairs(BAGS) do
		for slot = 1, W.NumSlots(bag) do
			local info = W.Info(bag, slot)
			if info and info.quality == 0 and not info.hasNoValue and not info.isLocked then
				list[#list + 1] = { bag, slot }
			end
		end
	end
	return list
end

-- Blizzard's own SellAllJunkItems where the client has it (it respects the buyback limit);
-- otherwise one item every 0.15 s while the vendor stays open.
function ns.Bags.SellJunk()
	if not MerchantOpen() then return end
	local merchant = C_MerchantFrame
	if merchant and merchant.SellAllJunkItems and (not merchant.IsSellAllJunkEnabled or merchant.IsSellAllJunkEnabled()) then
		merchant.SellAllJunkItems()
		return
	end
	local queue = JunkSlots()
	if #queue == 0 then return end
	local seller = ns.Bags.seller or CreateFrame("Frame")
	ns.Bags.seller = seller
	local wait, i = 0, 0
	seller:SetScript("OnUpdate", function(self, elapsed)
		wait = wait - elapsed
		if wait > 0 then return end
		wait = 0.15
		i = i + 1
		local entry = queue[i]
		if not entry or not MerchantOpen() then
			self:SetScript("OnUpdate", nil)
			return
		end
		if C_Container and C_Container.UseContainerItem then
			C_Container.UseContainerItem(entry[1], entry[2])
		elseif UseContainerItem then
			UseContainerItem(entry[1], entry[2])
		end
	end)
end

local function MerchantChanged(open)
	local frame = ns.Bags.frame
	if not frame then return end
	-- Always there; live only at a vendor.
	frame.junk:SetAlpha(open and 1 or 0.45)
	frame.junk:SetEnabled(open)
	if open and Opt().autoSellJunk then
		ns.Bags.SellJunk()
	end
end

---------------------------------------------------------------------------
-- Open / close, mirroring Blizzard's bag state

function ns.Bags.Open()
	if ns.Bags.win and Opt().enabled then
		ns.Bags.win:Open()
	end
end

function ns.Bags.Close()
	if ns.Bags.win then
		ns.Bags.win:Close()
	end
end

-- The bank opens this window itself, without Blizzard's bookkeeping (its OnShow is disabled),
-- and closes it again only if it was the one that opened it.
function ns.Bags.OpenForBank()
	if not ns.Bags.win or not Opt().enabled then return end
	if not ns.Bags.win:IsShown() then ns.Bags.byBank = true end
	ns.Bags.Open()
end

function ns.Bags.CloseForBank()
	if ns.Bags.byBank then
		ns.Bags.byBank = nil
		ns.Bags.Close()
	end
end

function ns.Bags.Toggle()
	if ns.Bags.win and ns.Bags.win:IsShown() then
		ns.Bags.Close()
	else
		ns.Bags.Open()
	end
end

local function BlizzardBagsOpen()
	if IsAnyBagOpen then return IsAnyBagOpen() end
	return IsBagOpen and IsBagOpen(0)
end

-- After Blizzard's toggles run, follow whether it thinks any bag is open. Blizzard can decline
-- a close (a vendor leaving when you had opened the bags yourself), so its state decides.
local function Follow()
	if not Opt().enabled then return end
	if ns.Bags.byBank then
		-- Open only for the bank, so Blizzard thought the bags were shut: any toggle means close.
		ns.Bags.byBank = nil
		ns.Bags.Close()
		if BlizzardBagsOpen() then CloseAllBags() end
		return
	end
	if BlizzardBagsOpen() then
		ns.Bags.Open()
	else
		ns.Bags.Close()
	end
end

function ns.Bags.DisableFrame(frame, noRight)
	if not frame then return end
	frame:SetScript("OnShow", nil)
	frame:SetScript("OnHide", nil)
	frame:UnregisterAllEvents()
	frame:ClearAllPoints()
	-- Blizzard's anchoring code reads GetRight on these; with no points it would be nil.
	if noRight then
		frame.GetRight = function() return 0 end
	end
	-- Blizzard re-anchors open bags; keep them anchorless so they never draw.
	hooksecurefunc(frame, "SetPoint", frame.ClearAllPoints)
end

local function DisableBlizzard()
	for i = 1, NUM_CONTAINER_FRAMES or 13 do
		ns.Bags.DisableFrame(_G["ContainerFrame" .. i])
	end
	local combined = _G.ContainerFrameCombinedBags
	if combined then
		ns.Bags.DisableFrame(combined)
		-- Keeps Blizzard's item layout from erroring when a vendor opens before a bag changes.
		combined:RegisterEvent("BAG_CONTAINER_UPDATE")
	end
end

---------------------------------------------------------------------------

function ns.Bags.Update()
	if ns.Bags.win then ns.Bags.win:Update() end
end

function ns.Bags.Layout()
	if ns.Bags.win then ns.Bags.win:Layout() end
end

function ns.Bags.ApplySettings()
	if not ns.Bags.win then return end
	if not Opt().enabled then
		ns.Bags.Close()
		return
	end
	ns.Bags.win:Layout()
	ns.Bags.win:Update()
end

function ns.Bags.Init()
	if not Opt().enabled then return end
	-- Blizzard's bag frames are disabled, so the keyring has to be listed here where the client has one.
	local keyring = Enum and Enum.BagIndex and Enum.BagIndex.Keyring
	if keyring and C_ActionBar and C_ActionBar.ShouldShowKeyring and C_ActionBar.ShouldShowKeyring() then
		BAGS[#BAGS + 1] = keyring
		W.keyring = keyring
	end
	local win = W.New({
		name = "SanctuaryUIBags",
		key = "bags",
		art = "bagFrame",
		containers = function() return BAGS end,
		template = function() return "ContainerFrameItemButtonTemplate" end,
		slotRow = SlotRow,
		updateRow = UpdateRow,
		onClose = function() CloseAllBags() end,
		onShow = function() PlaySound(SOUNDKIT and SOUNDKIT.IG_BACKPACK_OPEN or 862) end,
		onHide = function()
			ns.Bags.byBank = nil
			PlaySound(SOUNDKIT and SOUNDKIT.IG_BACKPACK_CLOSE or 863)
		end,
		footer = {
			{
				key = "sort",
				label = "Sort",
				onClick = function()
					if C_Container and C_Container.SortBags and not InCombatLockdown() then
						C_Container.SortBags()
					end
				end,
				setup = function(button)
					button:SetShown(C_Container and C_Container.SortBags and true or false)
				end,
			},
			{
				key = "junk",
				label = "Sell Junk",
				width = 96,
				onClick = function() ns.Bags.SellJunk() end,
				setup = function(button)
					button:SetScript("OnEnter", function(self)
						GameTooltip:SetOwner(self, "ANCHOR_TOP")
						GameTooltip:SetText("Sell Junk")
						if MerchantOpen() then
							GameTooltip:AddLine("Sell every grey item to this vendor.", 1, 1, 1, true)
						else
							GameTooltip:AddLine("Visit a vendor to sell your grey items.", 1, 1, 1, true)
						end
						GameTooltip:Show()
					end)
					button:SetScript("OnLeave", GameTooltip_Hide)
					button:SetAlpha(0.45)
					button:SetEnabled(false)
				end,
			},
		},
	})
	ns.Bags.win = win
	ns.Bags.frame = win.frame

	DisableBlizzard()
	hooksecurefunc("ToggleBag", Follow)
	hooksecurefunc("ToggleBackpack", Follow)
	hooksecurefunc("ToggleAllBags", Follow)
	hooksecurefunc("OpenAllBags", function() if Opt().enabled then ns.Bags.Open() end end)
	hooksecurefunc("CloseAllBags", Follow)
	if OpenBackpack then
		hooksecurefunc("OpenBackpack", function() if Opt().enabled then ns.Bags.Open() end end)
	end
	if CloseBackpack then
		hooksecurefunc("CloseBackpack", Follow)
	end

	local events = CreateFrame("Frame", nil, win.frame)
	for _, event in ipairs({ "BAG_UPDATE_DELAYED", "BAG_CONTAINER_UPDATE", "ITEM_LOCK_CHANGED", "BAG_UPDATE_COOLDOWN", "PLAYER_MONEY", "BAG_NEW_ITEMS_UPDATED", "QUEST_ACCEPTED", "QUEST_REMOVED", "PLAYER_REGEN_ENABLED", "MERCHANT_SHOW", "MERCHANT_CLOSED", "INVENTORY_SEARCH_UPDATE" }) do
		pcall(events.RegisterEvent, events, event)
	end
	events:SetScript("OnEvent", function(_, event)
		if event == "MERCHANT_SHOW" or event == "MERCHANT_CLOSED" then
			MerchantChanged(event == "MERCHANT_SHOW")
			return
		end
		if event == "BAG_CONTAINER_UPDATE" or (event == "PLAYER_REGEN_ENABLED" and win.pendingLayout) then
			win:Refresh()
		end
		win:Update()
	end)
end
