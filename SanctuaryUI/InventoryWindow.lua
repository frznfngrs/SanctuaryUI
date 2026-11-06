SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.InvWindow = ns.InvWindow or {}
local W = ns.InvWindow

-- The D3 inventory window, shared by the bags and the bank: stained-glass header with a
-- medallion, dark stone body, stone footer. Items sit on D3's quality cells, combined or one
-- bag per section under a divider, with a slot row and a search box along the top.
--
-- A window is built from a definition:
--   name        frame name
--   key         settings table in the profile ("bags" or "bank")
--   art         art slot for the frame atlas ("bagFrame" or "bankFrame")
--   containers  function() -> list of container IDs, in display order
--   template    function(bag) -> item button template
--   initSlot    optional function(button, bag, slot), after the button is made
--   slotRow     function(window) -> list of buttons for the top row (bag slots)
--   updateRow   function(window), refreshes them
--   footer      list of { label, width, onClick, setup } text buttons, left to right
--   onClose     function(window), when the close X or Escape closes it

-- bag-frame.png / bank-frame.png: header 600x155 at y 0, body 600x300 at y 155, footer
-- 600x207 at y 455.
local ART_W = 600
local HEADER = { y = 0, h = 155 }
local BODY = { y = 155, h = 300 }
local FOOTER = { y = 455, h = 207 }
local FOOTER_SQUASH = 0.55 -- the stone plate is tall in D3; ours holds one line
local SIDE = 14 -- side border width in the art
local ATLAS = 1024
local CLOSE = { x = 555, y = 8, w = 35, h = 35 } -- close X in the header art

-- bag-cells.png: 64 px cells. Quality -> cell; poor and common sit on the empty stone.
local CELL = { empty = 0, [2] = 1, [3] = 2, [4] = 3, [5] = 4, [6] = 5, [7] = 5, newItem = 6 }

local function CellCoord(index)
	return index * 64 / 512, (index + 1) * 64 / 512, 0, 1
end

function W.Info(bag, slot)
	if C_Container and C_Container.GetContainerItemInfo then
		return C_Container.GetContainerItemInfo(bag, slot)
	end
end

function W.NumSlots(bag)
	if C_Container and C_Container.GetContainerNumSlots then
		return C_Container.GetContainerNumSlots(bag) or 0
	end
	return GetContainerNumSlots and GetContainerNumSlots(bag) or 0
end

-- One search for every window: the client's item search is global anyway.
W.search = ""
W.windows = {}

---------------------------------------------------------------------------
-- Frame art

local function BuildArt(frame, slot)
	local function piece(part, x0, x1)
		local tex = frame:CreateTexture(nil, "BACKGROUND")
		if ns.Art.Apply(tex, slot) then
			tex:SetTexCoord(x0 / ATLAS, x1 / ATLAS, part.y / ATLAS, (part.y + part.h) / ATLAS)
		else
			tex:SetColorTexture(0.06, 0.05, 0.04, 0.95)
		end
		return tex
	end
	-- Body: side borders fixed, middle stretched both ways (plain dark stone).
	frame.art = {
		header = piece(HEADER, 0, ART_W),
		bodyL = piece(BODY, 0, SIDE),
		bodyM = piece(BODY, SIDE, ART_W - SIDE),
		bodyR = piece(BODY, ART_W - SIDE, ART_W),
		footer = piece(FOOTER, 0, ART_W),
	}
end

---------------------------------------------------------------------------
-- Item slots

local function MakeSlot(win, holder, bag, slot)
	local name = ("%sB%dS%d"):format(win.def.name, bag < 0 and 100 - bag or bag, slot)
	local button = CreateFrame("ItemButton", name, holder, win.def.template(bag))
	button:SetID(slot)
	-- Plain fields: reading these back through the template's mixin taints.
	button.BagID, button.SlotID = bag, slot
	if win.def.initSlot then
		win.def.initSlot(button, bag, slot)
	end

	local cell = button:CreateTexture(nil, "BACKGROUND", nil, -7)
	cell:SetPoint("TOPLEFT", -2, 2)
	cell:SetPoint("BOTTOMRIGHT", 2, -2)
	if not ns.Art.Apply(cell, "bagCells") then
		cell:SetColorTexture(0.05, 0.05, 0.04, 0.9)
	end
	button.sanctuaryCell = cell

	local fresh = button:CreateTexture(nil, "OVERLAY", nil, 6)
	fresh:SetPoint("TOPLEFT", -2, 2)
	fresh:SetPoint("BOTTOMRIGHT", 2, -2)
	if ns.Art.Apply(fresh, "bagCells") then
		fresh:SetTexCoord(CellCoord(CELL.newItem))
		fresh:SetBlendMode("ADD")
	end
	fresh:Hide()
	button.sanctuaryNew = fresh

	-- The template's square border, slot art and quality border give way to the D3 cells.
	local normal = button:GetNormalTexture()
	if normal then normal:SetAlpha(0) end
	if button.IconBorder then button.IconBorder:SetAlpha(0) end
	if button.NewItemTexture then button.NewItemTexture:SetAlpha(0) end
	if button.BattlepayItemTexture then button.BattlepayItemTexture:Hide() end
	-- The modern template's empty-slot art (the wing emblem) sits over our stone cell; our
	-- search fade replaces its search overlay.
	for _, key in ipairs({ "ItemSlotBackground", "SlotBackground", "BackgroundTexture", "searchOverlay" }) do
		local region = button[key]
		if region then
			region:SetAlpha(0)
		end
	end
	-- And by name, in case this client calls that layer something else.
	local ours = { [button.icon or 0] = true, [cell] = true, [fresh] = true }
	for _, region in ipairs({ button:GetRegions() }) do
		if not ours[region] and region.GetObjectType and region:GetObjectType() == "Texture" then
			local atlas = region.GetAtlas and region:GetAtlas()
			local file = region.GetTexture and region:GetTexture()
			local text = ((type(atlas) == "string" and atlas or "") .. " " .. (type(file) == "string" and file or "")):lower()
			if text:find("emptyslot") or text:find("item%-slot") or text:find("itemslot") then
				region:SetAlpha(0)
			end
		end
	end
	if button.icon then
		button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	end
	ns.Art.FitGoldLights(button)
	button:HookScript("OnSizeChanged", ns.Art.FitGoldLights)
	return button
end

local function UpdateSlot(win, button)
	local bag, slot = button.BagID, button.SlotID
	local info = W.Info(bag, slot)
	local texture = info and info.iconFileID
	SetItemButtonTexture(button, texture)
	SetItemButtonCount(button, info and info.stackCount or 0)
	SetItemButtonDesaturated(button, info and info.isLocked)

	local quality = info and info.quality
	local index = CELL.empty
	if win:Opt().quality ~= false and quality and CELL[quality] then
		index = CELL[quality]
	end
	button.sanctuaryCell:SetTexCoord(CellCoord(index))

	local isNew = C_NewItems and C_NewItems.IsNewItem and texture and C_NewItems.IsNewItem(bag, slot)
	button.sanctuaryNew:SetShown(isNew and true or false)

	local cooldown = button.Cooldown or _G[button:GetName() .. "Cooldown"]
	if cooldown then
		if texture and C_Container and C_Container.GetContainerItemCooldown then
			local start, duration, enable = C_Container.GetContainerItemCooldown(bag, slot)
			pcall(CooldownFrame_Set, cooldown, start, duration, enable)
		else
			cooldown:Hide()
		end
	end

	local quest = button.IconQuestTexture or _G[button:GetName() .. "IconQuestTexture"]
	if quest then
		local questInfo = C_Container and C_Container.GetContainerItemQuestInfo and texture and C_Container.GetContainerItemQuestInfo(bag, slot)
		quest:SetShown(questInfo and (questInfo.isQuestItem or questInfo.questID) and true or false)
	end
	button.hasItem = texture ~= nil

	-- Search: the client's own item search marks non-matches (isFiltered); without it,
	-- match the item name. Non-matches fade back.
	local filtered = false
	local search = W.search
	if search ~= "" and texture then
		if C_Container and C_Container.SetItemSearch then
			filtered = info.isFiltered and true or false
		else
			local name = info.hyperlink and info.hyperlink:match("%[(.-)%]")
			filtered = not (name and name:lower():find(search:lower(), 1, true))
		end
	elseif search ~= "" then
		filtered = true
	end
	button:SetAlpha(filtered and 0.25 or 1)
end

---------------------------------------------------------------------------
-- The window object

local Window = {}
Window.__index = Window

function Window:Opt()
	return ns.DB()[self.def.key]
end

local function Divider(frame, index)
	frame.dividers = frame.dividers or {}
	local line = frame.dividers[index]
	if not line then
		line = frame:CreateTexture(nil, "ARTWORK")
		line:SetColorTexture(0.62, 0.48, 0.24, 0.75)
		frame.dividers[index] = line
	end
	return line
end

function Window:Holder(bag)
	local frame = self.frame
	local holder = frame.holders[bag]
	if not holder then
		holder = CreateFrame("Frame", nil, frame)
		holder:SetID(bag)
		holder:SetAllPoints()
		holder.slots = {}
		frame.holders[bag] = holder
	end
	return holder
end

function Window:Layout()
	local frame = self.frame
	if InCombatLockdown() then
		self.pendingLayout = true
		return
	end
	self.pendingLayout = nil
	local opt = self:Opt()
	local size, gap = opt.slotSize, opt.spacing
	local cols = math.max(4, opt.columns)
	local inner = cols * size + (cols - 1) * gap

	-- The art scales with the slot grid so the header keeps D3's proportions.
	local k = (inner + 24) / (ART_W - 2 * SIDE)
	local side = SIDE * k
	local headerH = HEADER.h * k
	local footerH = FOOTER.h * k * FOOTER_SQUASH
	local padX = side + 12
	local top = headerH + 8

	-- Slot row first (bag slots), then the items under them.
	local rowSize = math.floor(size * 0.8)
	local rowButtons = frame.rowButtons
	for i, button in ipairs(rowButtons) do
		button:SetShown(opt.bagSlots)
		button:SetSize(rowSize, rowSize)
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", frame, "TOPLEFT", padX + (i - 1) * (rowSize + gap + 2), -top)
	end
	-- The search box takes the rest of that line (or the line alone).
	local searchLeft = opt.bagSlots and (padX + #rowButtons * (rowSize + gap + 2) + 6) or padX
	local searchH = math.max(22, math.floor(rowSize * 0.75))
	frame.searchBox:ClearAllPoints()
	frame.searchBox:SetPoint("TOPLEFT", frame, "TOPLEFT", searchLeft + 18, -(top + (rowSize - searchH) / 2))
	frame.searchBox:SetPoint("RIGHT", frame, "RIGHT", -padX, 0)
	frame.searchBox:SetHeight(searchH)
	top = top + math.max(opt.bagSlots and rowSize or 0, searchH) + gap + 8

	local col, row, dividerCount, placed = 0, 0, 0, 0
	local shownBags = {}
	for _, bag in ipairs(self.def.containers()) do
		shownBags[bag] = true
		local holder = self:Holder(bag)
		local count = W.NumSlots(bag)
		if opt.dividers and placed > 0 and count > 0 then
			if col > 0 then
				col, row = 0, row + 1
			end
			dividerCount = dividerCount + 1
			local line = Divider(frame, dividerCount)
			local y = top + row * (size + gap) + 3
			line:ClearAllPoints()
			line:SetPoint("TOPLEFT", frame, "TOPLEFT", padX, -y)
			line:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -padX, -y)
			line:SetHeight(1)
			line:Show()
			row = row + 0.25
		end
		for slot = 1, math.max(count, #holder.slots) do
			local button = holder.slots[slot]
			if slot <= count then
				if not button then
					button = MakeSlot(self, holder, bag, slot)
					holder.slots[slot] = button
				end
				button:SetSize(size, size)
				button:ClearAllPoints()
				button:SetPoint("TOPLEFT", frame, "TOPLEFT", padX + col * (size + gap), -(top + row * (size + gap)))
				button:Show()
				placed = placed + 1
				col = col + 1
				if col >= cols then
					col, row = 0, row + 1
				end
			elseif button then
				button:Hide()
			end
		end
	end
	-- Containers no longer listed (a bank tab that went away) hide their slots.
	for bag, holder in pairs(frame.holders) do
		if not shownBags[bag] then
			for _, button in ipairs(holder.slots) do
				button:Hide()
			end
		end
	end
	if frame.dividers then
		for i = dividerCount + 1, #frame.dividers do
			frame.dividers[i]:Hide()
		end
	end
	local rows = row + (col > 0 and 1 or 0)
	local gridH = math.max(size, rows * (size + gap) - gap)
	-- Everything between the header and the footer: the slot / search line plus the grid.
	local bodyH = (top - headerH) + gridH + 12
	local width = inner + 2 * padX
	frame:SetSize(width, headerH + bodyH + footerH)

	local art = frame.art
	art.header:ClearAllPoints()
	art.header:SetPoint("TOPLEFT")
	art.header:SetSize(width, headerH)
	art.bodyL:ClearAllPoints()
	art.bodyL:SetPoint("TOPLEFT", 0, -headerH)
	art.bodyL:SetSize(side, bodyH)
	art.bodyR:ClearAllPoints()
	art.bodyR:SetPoint("TOPRIGHT", 0, -headerH)
	art.bodyR:SetSize(side, bodyH)
	art.bodyM:ClearAllPoints()
	art.bodyM:SetPoint("TOPLEFT", side, -headerH)
	art.bodyM:SetPoint("BOTTOMRIGHT", art.bodyR, "BOTTOMLEFT")
	art.footer:ClearAllPoints()
	art.footer:SetPoint("BOTTOMLEFT")
	art.footer:SetSize(width, footerH)

	frame.close:ClearAllPoints()
	frame.close:SetPoint("TOPLEFT", CLOSE.x * width / ART_W, -CLOSE.y * k)
	frame.close:SetSize(CLOSE.w * k, CLOSE.h * k)

	frame.money:ClearAllPoints()
	frame.money:SetPoint("RIGHT", art.footer, "RIGHT", -side - 14, 8)
	frame.free:ClearAllPoints()
	frame.free:SetPoint("TOPRIGHT", frame.money, "BOTTOMRIGHT", 0, -3)
	local buttonH = math.max(22, footerH * 0.42)
	local anchor
	for _, button in ipairs(frame.footerButtons) do
		button:ClearAllPoints()
		if anchor then
			button:SetPoint("LEFT", anchor, "RIGHT", 6, 0)
		else
			-- The footer art's left-middle, anchored to the frame: protected buttons (bank
			-- Buy Slot) cannot anchor to textures.
			button:SetPoint("LEFT", frame, "BOTTOMLEFT", side + 12, footerH / 2)
		end
		button:SetSize(button.sanctuaryWidth, buttonH)
		if button:IsShown() then
			anchor = button
		end
	end

	frame:SetScale(opt.scale)
	frame:ClearAllPoints()
	frame:SetPoint(opt.point, UIParent, opt.point, opt.x, opt.y)
	self.laidOut = true
end

function Window:Update()
	local frame = self.frame
	if not frame:IsShown() then return end
	local free, total = 0, 0
	for _, bag in ipairs(self.def.containers()) do
		local holder = frame.holders[bag]
		if holder then
			for _, button in ipairs(holder.slots) do
				if button:IsShown() then
					UpdateSlot(self, button)
				end
			end
		end
		total = total + W.NumSlots(bag)
		if C_Container and C_Container.GetContainerNumFreeSlots then
			free = free + (C_Container.GetContainerNumFreeSlots(bag) or 0)
		end
	end
	if self.def.updateRow then
		self.def.updateRow(self)
	end
	frame.money:SetText(GetMoneyString and GetMoneyString(GetMoney(), true) or tostring(GetMoney()))
	frame.free:SetFormattedText("%d / %d", total - free, total)
end

function Window:Open()
	if self.pendingLayout or not self.laidOut then
		self:Layout()
	end
	self.frame:Show()
	self:Update()
end

function Window:Close()
	self.frame:Hide()
end

function Window:IsShown()
	return self.frame:IsShown()
end

-- After a container appears or changes size.
function Window:Refresh()
	if self.frame:IsShown() then
		self:Layout()
		self:Update()
	else
		self.laidOut = false
	end
end

---------------------------------------------------------------------------

function W.TextButton(parent, label, onClick, width)
	local button = CreateFrame("Button", nil, parent)
	local plate = button:CreateTexture(nil, "BACKGROUND")
	plate:SetAllPoints()
	if ns.Art.Apply(plate, "d3Button") then
		plate:SetTexCoord(0, 120 / 128, 0, 52 / 64)
	else
		plate:SetColorTexture(0.2, 0.06, 0.04, 0.9)
	end
	local hover = button:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints()
	hover:SetColorTexture(1, 0.7, 0.3, 0.15)
	local text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	text:SetPoint("CENTER", 0, 1)
	text:SetText(label)
	button.text = text
	button.sanctuaryWidth = width or 84
	if onClick then
		button:SetScript("OnClick", onClick)
	end
	return button
end

-- Every window's search box shows the same text.
local function SetSearch(text, from)
	W.search = text or ""
	if C_Container and C_Container.SetItemSearch then
		C_Container.SetItemSearch(W.search)
	end
	for _, win in ipairs(W.windows) do
		local box = win.frame.searchBox
		if box ~= from and (box:GetText() or "") ~= W.search then
			box:SetText(W.search)
		end
		win:Update()
	end
end

function W.New(def)
	local win = setmetatable({ def = def }, Window)
	local frame = CreateFrame("Frame", def.name, UIParent)
	frame:SetFrameStrata("MEDIUM")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		self:SetUserPlaced(false)
		local opt = win:Opt()
		local point, _, _, x, y = self:GetPoint(1)
		opt.point, opt.x, opt.y = point or opt.point, x or 0, y or 0
	end)
	frame:Hide()
	tinsert(UISpecialFrames, def.name)
	BuildArt(frame, def.art)
	frame.holders = {}
	win.frame = frame

	frame.rowButtons = def.slotRow and def.slotRow(win) or {}

	-- Search: Blizzard's search box (magnifier, clear button, placeholder) in a D3 plate.
	local search = CreateFrame("EditBox", def.name .. "Search", frame, "SearchBoxTemplate")
	search:SetAutoFocus(false)
	for _, key in ipairs({ "Left", "Middle", "Right", "Mid" }) do
		if search[key] then search[key]:SetAlpha(0) end
	end
	local plate = search:CreateTexture(nil, "BACKGROUND", nil, -1)
	plate:SetPoint("TOPLEFT", -22, 5)
	plate:SetPoint("BOTTOMRIGHT", 6, -5)
	if ns.Art.Apply(plate, "d3Button") then
		plate:SetTexCoord(0, 120 / 128, 0, 52 / 64)
	else
		plate:SetColorTexture(0.1, 0.05, 0.04, 0.9)
	end
	search:HookScript("OnTextChanged", function(self, userInput)
		local text = self:GetText() or ""
		if text ~= W.search then
			SetSearch(text, self)
		end
	end)
	search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	frame.searchBox = search

	local close = CreateFrame("Button", nil, frame)
	local closeHover = close:CreateTexture(nil, "HIGHLIGHT")
	closeHover:SetAllPoints()
	closeHover:SetColorTexture(1, 0.6, 0.2, 0.3)
	close:SetScript("OnClick", function()
		if def.onClose then def.onClose(win) else win:Close() end
	end)
	frame.close = close

	frame.money = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.free = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.free:SetTextColor(0.75, 0.66, 0.5)
	frame.footerButtons = {}
	for _, spec in ipairs(def.footer or {}) do
		local button = spec.make and spec.make(frame) or W.TextButton(frame, spec.label, spec.onClick, spec.width)
		button.sanctuaryWidth = button.sanctuaryWidth or spec.width or 84
		if spec.setup then spec.setup(button) end
		frame.footerButtons[#frame.footerButtons + 1] = button
		frame[spec.key or spec.label] = button
	end

	frame:SetScript("OnShow", function()
		win:Update()
		if def.onShow then def.onShow(win) end
	end)
	frame:SetScript("OnHide", function()
		if def.onHide then def.onHide(win) end
	end)
	W.windows[#W.windows + 1] = win
	return win
end
