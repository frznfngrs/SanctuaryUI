SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.Trinket = ns.Trinket or {}

-- Trinkets, the TrinketMenu way: two sockets for your equipped trinkets (click or keybind to
-- use them, in combat too), and hovering one opens a menu of the trinkets in your bags.
--   Left-click a trinket in the menu: equip it as trinket 1. Right-click: as trinket 2.
--   In combat the game won't change trinkets, so the swap waits (its icon sits in the corner
--   of the socket) and goes on the moment combat ends.
--   Alt + left / right-click: add it to (or take it off) trinket 1's / 2's auto-swap list.
-- Auto-swap, out of combat: once a socket's trinket is on a cooldown longer than the 30 s an
-- equip costs, the first trinket on its list that's ready goes on; a ready trinket higher on
-- the list replaces a lower one. A trinket you pick yourself stays until you've used it, and
-- one whose effect is on you stays until it fades.
-- Item cooldowns aren't secret on this client, so the sweeps and the queue work in combat.

local SLOTS = { INVSLOT_TRINKET1 or 13, INVSLOT_TRINKET2 or 14 }
local READY_WINDOW = 30 -- seconds: equipping a trinket puts it on this long a cooldown
local MAX_ENTRIES = 40
local RETRY = 0.5 -- seconds between tries of a swap the game refused (casting, a moment late)

for i = 1, 2 do
	_G["BINDING_NAME_SANCTUARYUITRINKET" .. i] = "Use trinket " .. i
end

local function Opt()
	return ns.DB().trinkets
end

-- Auto-swap lists are your own trinkets, so they're kept per character.
local function Char(i)
	local char = ns.db and ns.db.char
	local t = char and char.trinkets
	return t and t[i]
end

local function Secret(value)
	return issecretvalue and issecretvalue(value)
end

local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetItemCooldown = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
local GetItemSpell = (C_Item and C_Item.GetItemSpell) or GetItemSpell
local EquipItemByName = (C_Item and C_Item.EquipItemByName) or EquipItemByName
local NumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

local function BagItem(bag, slot)
	if C_Container and C_Container.GetContainerItemInfo then
		local info = C_Container.GetContainerItemInfo(bag, slot)
		if type(info) == "table" then
			return info.itemID, info.hyperlink, info.iconFileID, info.quality
		end
		return
	end
	if GetContainerItemInfo then
		local icon, _, _, quality, _, _, link = GetContainerItemInfo(bag, slot)
		local id = GetContainerItemID and GetContainerItemID(bag, slot)
		return id, link, icon, quality
	end
end

local function IsTrinket(itemID)
	if not itemID or not GetItemInfoInstant then return false end
	local _, _, _, equipLoc = GetItemInfoInstant(itemID)
	return equipLoc == "INVTYPE_TRINKET"
end

local function Equipped(i)
	local id = GetInventoryItemID("player", SLOTS[i])
	if Secret(id) then return nil end
	return id
end

-- Seconds left on an item's cooldown (0 when ready), and its full length.
local function CooldownLeft(itemID)
	if not itemID or not GetItemCooldown then return 0, 0 end
	local start, duration, enable = GetItemCooldown(itemID)
	if Secret(start) or Secret(duration) or not start or not duration then return 0, 0 end
	if enable == 0 or enable == false or duration <= 0 then return 0, 0 end
	return math.max(0, start + duration - GetTime()), duration
end

local function NameOf(link)
	return type(link) == "string" and link:match("|h%[(.-)%]|h") or ""
end

---------------------------------------------------------------------------
-- The trinkets in your bags.

local menuItems = {} -- { bag, slot, itemID, link, icon, quality, name }

local function ScanBags()
	wipe(menuItems)
	if not NumSlots then return end
	for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
		for slot = 1, (NumSlots(bag) or 0) do
			local id, link, icon, quality = BagItem(bag, slot)
			if id and not Secret(id) and IsTrinket(id) then
				menuItems[#menuItems + 1] = {
					bag = bag, slot = slot, itemID = id, link = link, icon = icon,
					quality = (not Secret(quality) and quality) or 1, name = NameOf(link),
				}
			end
		end
	end
	-- Best first, then by name, so the menu doesn't reshuffle as bags change.
	table.sort(menuItems, function(a, b)
		if a.quality ~= b.quality then return a.quality > b.quality end
		if a.name ~= b.name then return a.name < b.name end
		return a.itemID < b.itemID
	end)
end

local function InBags(itemID)
	for _, item in ipairs(menuItems) do
		if item.itemID == itemID then return item end
	end
end

---------------------------------------------------------------------------
-- Swaps: now when the game allows it, else queued for the end of combat.

local queued = {} -- by socket: { itemID, link, icon }
local held = {} -- by socket: itemID you picked yourself (auto-swap leaves it until used)
local lastTry = 0

local function CanSwap()
	if InCombatLockdown() then return false end
	if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return false end
	return true
end

local function Equip(item, i)
	if not EquipItemByName then return false end
	lastTry = GetTime()
	return pcall(EquipItemByName, item.link or item.itemID, SLOTS[i])
end

-- Queued swaps go on; each stays queued until the slot really holds it.
local function FlushQueue()
	if not CanSwap() then return end
	for i = 1, 2 do
		local q = queued[i]
		if q then
			if Equipped(i) == q.itemID then
				queued[i] = nil
				held[i] = q.itemID
			elseif InBags(q.itemID) or Equipped(3 - i) == q.itemID then
				Equip(q, i)
			else
				-- Gone from the bags (sold, banked): nothing to put on.
				queued[i] = nil
			end
		end
	end
end

function ns.Trinket.Pick(i, item)
	if not item then return end
	if Equipped(i) == item.itemID then
		queued[i] = nil
	elseif CanSwap() then
		queued[i] = nil
		held[i] = item.itemID
		Equip(item, i)
	else
		queued[i] = { itemID = item.itemID, link = item.link, icon = item.icon }
	end
	ns.Trinket.Update()
end

---------------------------------------------------------------------------
-- Auto-swap

local function OnList(i, itemID)
	local c = Char(i)
	if not c then return end
	for n, id in ipairs(c.list) do
		if id == itemID then return n end
	end
end

function ns.Trinket.ToggleListed(i, itemID)
	local c = Char(i)
	if not c or not itemID then return end
	local n = OnList(i, itemID)
	if n then
		table.remove(c.list, n)
	else
		c.list[#c.list + 1] = itemID
		c.auto = true
	end
	ns.Trinket.Update()
	local registry = LibStub("AceConfigRegistry-3.0", true)
	if registry then registry:NotifyChange("SanctuaryUI") end
end

-- Is the trinket's own effect (its use buff) on you? Only asked out of combat, where buffs
-- can be read.
local function EffectUp(itemID)
	if not GetItemSpell or not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return false end
	local _, spellID = GetItemSpell(itemID)
	if not spellID or Secret(spellID) then return false end
	local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
	return ok and aura ~= nil and not Secret(aura)
end

local function AutoSwap(i)
	local c = Char(i)
	if not c or not c.auto or #c.list == 0 or queued[i] then return end
	local current = Equipped(i)
	local currentLeft = CooldownLeft(current)
	if held[i] and held[i] == current then
		-- Yours until you've used it.
		if currentLeft <= READY_WINDOW then return end
		held[i] = nil
	end
	held[i] = nil
	if current and EffectUp(current) then return end
	local rank = current and OnList(i, current)
	local currentReady = current and currentLeft <= READY_WINDOW
	for n, id in ipairs(c.list) do
		if rank and n >= rank and currentReady then return end -- what's on is as good, and ready
		if id ~= current then
			local item = InBags(id)
			if item and CooldownLeft(id) <= READY_WINDOW then
				Equip(item, i)
				return
			end
		end
	end
end

local function RunAuto()
	if not CanSwap() or GetTime() - lastTry < RETRY then return end
	if UnitCastingInfo and UnitCastingInfo("player") ~= nil then return end
	if UnitChannelInfo and UnitChannelInfo("player") ~= nil then return end
	FlushQueue()
	if GetTime() - lastTry < RETRY then return end
	for i = 1, 2 do
		AutoSwap(i)
		if GetTime() - lastTry < RETRY then return end
	end
end

---------------------------------------------------------------------------
-- Sockets: square D3 sockets like the stance bar's, secure so they use the trinket in combat.

local bar, menu

local function Hotkey(button, i)
	local key = GetBindingKey("SANCTUARYUITRINKET" .. i)
	local KeyBound = LibStub("LibKeyBound-1.0", true)
	button.HotKey:SetText(key and ns.DB().buttons.hotkeys and (KeyBound and KeyBound:ToShortKey(key) or key) or "")
end

local function EmptyIcon(i)
	local _, icon = GetInventorySlotInfo(i == 1 and "Trinket0Slot" or "Trinket1Slot")
	return icon
end

local function Flash(button)
	if not button.flash then return end
	button.flash.anim:Stop()
	button.flash.anim:Play()
end

local function MakeFlash(button)
	local flash = button.ring and button.ring:CreateTexture(nil, "OVERLAY", nil, 7) or button:CreateTexture(nil, "OVERLAY", nil, 7)
	flash:SetPoint("TOPLEFT", button, "TOPLEFT", -6, 6)
	flash:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 6, -6)
	if not ns.Art.Apply(flash, "buttonGlow") then
		flash:SetColorTexture(1, 0.85, 0.5, 0.35)
	end
	flash:SetBlendMode("ADD")
	flash:SetAlpha(0)
	local anim = flash:CreateAnimationGroup()
	for k = 0, 1 do
		local up = anim:CreateAnimation("Alpha")
		up:SetFromAlpha(0)
		up:SetToAlpha(1)
		up:SetDuration(0.18)
		up:SetOrder(k * 2 + 1)
		local down = anim:CreateAnimation("Alpha")
		down:SetFromAlpha(1)
		down:SetToAlpha(0)
		down:SetDuration(0.42)
		down:SetOrder(k * 2 + 2)
	end
	flash.anim = anim
	button.flash = flash
end

local function SocketTooltip(self)
	if GameTooltip:IsForbidden() then return end
	local i = self.index
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	if not GameTooltip:SetInventoryItem("player", SLOTS[i]) then
		GameTooltip:SetText("Trinket " .. i)
	end
	local q = queued[i]
	if q then
		GameTooltip:AddLine(("%s goes on when combat ends."):format(q.link or "Your pick"), 1, 0.82, 0.3, true)
	end
	local c = Char(i)
	if c and c.auto and #c.list > 0 then
		GameTooltip:AddLine(("Auto-swap: %d trinket%s listed."):format(#c.list, #c.list == 1 and "" or "s"), 0.86, 0.72, 0.42)
	end
	if Opt().menu ~= "off" then
		if #menuItems == 0 then
			GameTooltip:AddLine("No other trinkets in your bags.", 0.7, 0.7, 0.7, true)
		elseif Opt().menu == "shift" then
			GameTooltip:AddLine("Hold Shift for the trinkets in your bags.", 0.7, 0.7, 0.7, true)
		end
	end
	GameTooltip:Show()
end

local function MakeSocket(parent, i)
	local button = CreateFrame("Button", "SanctuaryUITrinket" .. i, parent, "SecureActionButtonTemplate")
	button.index = i
	button:RegisterForClicks("AnyUp", "AnyDown")
	button:SetAttribute("type", "macro")
	button:SetAttribute("macrotext", "/use " .. SLOTS[i])
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetAllPoints()
	button.cooldown = CreateFrame("Cooldown", button:GetName() .. "Cooldown", button, "CooldownFrameTemplate")
	button.cooldown:SetAllPoints()
	button.HotKey = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	ns.ActionBar.StyleHotkey(button.HotKey)
	button.HotKey:SetTextColor(0.86, 0.72, 0.42)
	button.HotKey:SetPoint("BOTTOM", 0, 2)
	button.sanctuary, button.sanctuarySquare, button.sanctuarySocket = true, true, true
	ns.Art.ReskinActionButton(nil, button)
	button.ring = button.sanctuaryRingFrame
	-- The swap waiting for the end of combat: its icon in the top corner, in a gold frame.
	local top = CreateFrame("Frame", nil, button)
	top:SetAllPoints()
	top:SetFrameLevel(button.cooldown:GetFrameLevel() + 6)
	local qFrame = top:CreateTexture(nil, "OVERLAY", nil, 1)
	qFrame:SetColorTexture(0.86, 0.72, 0.42, 1)
	local qIcon = top:CreateTexture(nil, "OVERLAY", nil, 2)
	qIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	qIcon:SetPoint("TOPRIGHT", button, "TOPRIGHT", 3, 3)
	qFrame:SetPoint("TOPLEFT", qIcon, "TOPLEFT", -1, 1)
	qFrame:SetPoint("BOTTOMRIGHT", qIcon, "BOTTOMRIGHT", 1, -1)
	button.queuedIcon, button.queuedFrame = qIcon, qFrame
	button:HookScript("OnSizeChanged", function(self, w)
		self.queuedIcon:SetSize(w * 0.42, w * 0.42)
	end)
	MakeFlash(button)
	button.cooldown:SetScript("OnCooldownDone", function()
		-- Ready again after a real cooldown (not the second or so of a shared one).
		if (button.cdLength or 0) > 2 and Opt().notify then
			Flash(button)
			if Opt().notifyChat then
				local link = GetInventoryItemLink("player", SLOTS[i])
				if link and not Secret(link) then ns.Print(link .. " is ready.") end
			end
		end
		button.cdLength = nil
	end)
	button:SetScript("OnEnter", function(self)
		SocketTooltip(self)
		ns.Trinket.HoverSocket(self)
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	ns.Menu.KeyBindable(button, "SANCTUARYUITRINKET" .. i, "Trinket " .. i)
	return button
end

---------------------------------------------------------------------------
-- The menu: a grid of your bag trinkets beside the sockets. Plain (not secure) buttons, since
-- all they do is equip or queue, which works the same in combat.

local function EntryTooltip(self)
	if GameTooltip:IsForbidden() or not self.item then return end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	local item = self.item
	if not (GameTooltip.SetBagItem and GameTooltip:SetBagItem(item.bag, item.slot)) then
		GameTooltip:SetHyperlink(item.link)
	end
	GameTooltip:AddLine("Left-click: equip as trinket 1. Right-click: as trinket 2.", 0.7, 0.7, 0.7, true)
	GameTooltip:AddLine("Alt-click: add to or take off that trinket's auto-swap list.", 0.7, 0.7, 0.7, true)
	if InCombatLockdown() then
		GameTooltip:AddLine("In combat: it goes on when combat ends.", 1, 0.82, 0.3, true)
	end
	GameTooltip:Show()
end

local function Badge(parent, point, x, y)
	local text = parent:CreateFontString(nil, "OVERLAY")
	text:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
	text:SetTextColor(1, 0.82, 0.3)
	text:SetPoint(point, parent, point, x, y)
	return text
end

local function MakeEntry(j)
	local button = CreateFrame("Button", "SanctuaryUITrinketMenu" .. j, menu)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetAllPoints()
	button.cooldown = CreateFrame("Cooldown", button:GetName() .. "Cooldown", button, "CooldownFrameTemplate")
	button.cooldown:SetAllPoints()
	if button.cooldown.SetHideCountdownNumbers then button.cooldown:SetHideCountdownNumbers(true) end
	button.sanctuary, button.sanctuarySquare, button.sanctuarySocket = true, true, true
	ns.Art.ReskinActionButton(nil, button)
	local top = CreateFrame("Frame", nil, button)
	top:SetAllPoints()
	top:SetFrameLevel(button.cooldown:GetFrameLevel() + 6)
	-- Its place on trinket 1's list top left, on trinket 2's top right.
	button.rank1 = Badge(top, "TOPLEFT", 3, -2)
	button.rank2 = Badge(top, "TOPRIGHT", -3, -2)
	button:SetScript("OnClick", function(self, mouse)
		local item = self.item
		if not item then return end
		if IsModifiedClick and IsModifiedClick("CHATLINK") and HandleModifiedItemClick then
			HandleModifiedItemClick(item.link)
			return
		end
		local i = mouse == "RightButton" and 2 or 1
		if IsAltKeyDown() then
			ns.Trinket.ToggleListed(i, item.itemID)
			EntryTooltip(self)
			return
		end
		ns.Trinket.Pick(i, item)
		menu:Hide()
	end)
	button:SetScript("OnEnter", EntryTooltip)
	button:SetScript("OnLeave", GameTooltip_Hide)
	return button
end

local function FillEntries()
	for j = 1, MAX_ENTRIES do
		local item = menuItems[j]
		local button = menu.entries[j]
		if item and not button then
			button = MakeEntry(j)
			menu.entries[j] = button
		end
		if button then
			button.item = item
			if item then
				button.icon:SetTexture(item.icon)
				local left, length = CooldownLeft(item.itemID)
				if left > 0 then
					pcall(CooldownFrame_Set, button.cooldown, GetTime() + left - length, length, 1)
				else
					button.cooldown:Clear()
				end
				local r1, r2 = OnList(1, item.itemID), OnList(2, item.itemID)
				button.rank1:SetText(r1 and Char(1).auto and r1 or "")
				button.rank2:SetText(r2 and Char(2).auto and r2 or "")
				button:Show()
			else
				button:Hide()
			end
		end
	end
end

-- Lay the grid out beside the bar: lines of perLine going away from it in the chosen direction.
local function LayoutMenu()
	local opt = Opt()
	local size = bar.size * opt.menuScale
	local gap = math.max(2, opt.spacing)
	local per = math.max(1, opt.menuPerLine)
	local count = math.max(1, math.min(#menuItems, MAX_ENTRIES))
	local across = math.min(count, per)
	local lines = math.ceil(count / per)
	local dir = opt.menuDir
	local sideways = dir == "left" or dir == "right"
	local w = (sideways and lines or across) * (size + gap) - gap
	local h = (sideways and across or lines) * (size + gap) - gap
	menu:SetSize(w, h)
	menu:ClearAllPoints()
	local away = gap + 4
	if dir == "down" then
		menu:SetPoint("TOP", bar, "BOTTOM", 0, -away)
	elseif dir == "left" then
		menu:SetPoint("RIGHT", bar, "LEFT", -away, 0)
	elseif dir == "right" then
		menu:SetPoint("LEFT", bar, "RIGHT", away, 0)
	else
		menu:SetPoint("BOTTOM", bar, "TOP", 0, away)
	end
	for j, button in pairs(menu.entries) do
		local along, line = (j - 1) % per, math.floor((j - 1) / per)
		local a, l = along * (size + gap), line * (size + gap) -- line 0 hugs the bar
		button:ClearAllPoints()
		if dir == "down" then
			button:SetPoint("TOPLEFT", menu, "TOPLEFT", a, -l)
		elseif dir == "left" then
			button:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -l, -a)
		elseif dir == "right" then
			button:SetPoint("TOPLEFT", menu, "TOPLEFT", l, -a)
		else
			button:SetPoint("BOTTOMLEFT", menu, "BOTTOMLEFT", a, l)
		end
		button:SetSize(size, size)
	end
end

local function OpenMenu()
	if not menu or #menuItems == 0 then return end
	FillEntries()
	LayoutMenu()
	menu.linger = 0
	menu:Show()
end

function ns.Trinket.HoverSocket()
	local mode = Opt().menu
	if mode == "hover" or (mode == "shift" and IsShiftKeyDown()) then
		OpenMenu()
	end
end

---------------------------------------------------------------------------

local function SetSocket(button, i)
	local id = Equipped(i)
	local icon = GetInventoryItemTexture("player", SLOTS[i])
	if Secret(icon) then icon = nil end
	button.icon:SetTexture(icon or EmptyIcon(i))
	button.icon:SetDesaturated(not id)
	button.icon:SetVertexColor(id and 1 or 0.6, id and 1 or 0.6, id and 1 or 0.6)
	local start, duration, enable = GetInventoryItemCooldown("player", SLOTS[i])
	if Secret(start) or Secret(duration) then
		pcall(CooldownFrame_Set, button.cooldown, start, duration, enable)
	elseif start and duration and duration > 0 and (enable == 1 or enable == true) then
		button.cdLength = duration
		CooldownFrame_Set(button.cooldown, start, duration, 1)
	else
		button.cooldown:Clear()
	end
	local q = queued[i]
	button.queuedIcon:SetShown(q ~= nil)
	button.queuedFrame:SetShown(q ~= nil)
	if q then button.queuedIcon:SetTexture(q.icon) end
end

-- Icons, cooldowns, the queued swaps and the open menu: safe any time.
function ns.Trinket.Update()
	if not bar then return end
	for i = 1, 2 do
		SetSocket(bar.buttons[i], i)
	end
	if menu and menu:IsShown() then
		FillEntries()
		if #menuItems == 0 then menu:Hide() else LayoutMenu() end
	end
end

function ns.Trinket.Enabled()
	return Opt().enabled
end

local function Configure()
	if InCombatLockdown() then
		ns.Trinket.pending = true
		return
	end
	ns.Trinket.pending = nil
	if Opt().enabled then
		RegisterStateDriver(bar, "visibility", "[petbattle][vehicleui][overridebar][possessbar] hide; show")
	else
		UnregisterStateDriver(bar, "visibility")
		bar:Hide()
	end
	ns.Trinket.ReassignBindings()
end

function ns.Trinket.ReassignBindings()
	if not bar or InCombatLockdown() then return end
	ClearOverrideBindings(bar)
	for i = 1, 2 do
		local button = bar.buttons[i]
		local binding = "SANCTUARYUITRINKET" .. i
		if Opt().enabled then
			for k = 1, select("#", GetBindingKey(binding)) do
				local key = select(k, GetBindingKey(binding))
				if key and key ~= "" then
					SetOverrideBindingClick(bar, false, key, button:GetName(), "LeftButton")
				end
			end
		end
		Hotkey(button, i)
	end
end

function ns.Trinket.Layout()
	local cluster = ns.Cluster
	local metrics = ns.Metrics and ns.Metrics()
	if not bar or not cluster or not metrics then return end
	if InCombatLockdown() then
		ns.Trinket.pending = true
		return
	end
	local opt = Opt()
	local bw = metrics.slots[1].w * opt.scale
	local bh = metrics.slots[1].h * opt.scale
	local gap = opt.spacing
	bar.size = math.min(bw, bh)
	if opt.vertical then
		bar:SetSize(bw, bh * 2 + gap)
	else
		bar:SetSize(bw * 2 + gap, bh)
	end
	for i = 1, 2 do
		local button = bar.buttons[i]
		button:SetSize(bw, bh)
		button:ClearAllPoints()
		if i == 1 then
			button:SetPoint("TOPLEFT", bar, "TOPLEFT")
		elseif opt.vertical then
			button:SetPoint("TOP", bar.buttons[1], "BOTTOM", 0, -gap)
		else
			button:SetPoint("LEFT", bar.buttons[1], "RIGHT", gap, 0)
		end
	end
	bar:ClearAllPoints()
	if opt.moved then
		bar:SetPoint("CENTER", UIParent, "BOTTOMLEFT", ns.MovedPoint(bar, opt))
	else
		-- Beside the console, past the angel holding the resource globe.
		local span = ns.ActionBar and ns.ActionBar.span
		local right = span and span.right or (metrics.resource.x + metrics.resource.size)
		bar:SetPoint("BOTTOMLEFT", cluster, "BOTTOM", right + 8, 12)
	end
	local level = cluster:GetFrameLevel() + ns.LEVEL.buttons
	bar:SetFrameLevel(level)
	menu:SetFrameLevel(level + 10)
	bar.alpha, bar.mouseover = opt.alpha, opt.mouseover
	bar:SetAlpha(opt.mouseover and 0 or opt.alpha)
	if menu:IsShown() then LayoutMenu() end
end

function ns.Trinket.Buttons()
	return bar and bar.buttons or {}
end

function ns.Trinket.ApplySettings()
	if not bar then return end
	for _, button in ipairs(bar.buttons) do
		ns.ActionBar.StyleHotkey(button.HotKey)
	end
	Configure()
	ns.Trinket.Layout()
	ns.Trinket.Update()
end

function ns.Trinket.UpdateMovers(unlocked)
	if not ns.Trinket.mover then return end
	ns.Trinket.mover:SetShown(unlocked and Opt().enabled and true or false)
end

function ns.Trinket.ResetPosition()
	local opt = Opt()
	opt.moved, opt.mx, opt.my = false, 0, 0
	ns.Refresh()
end

-- The auto-swap list of trinket i, for the options page: { itemID, name, icon }.
function ns.Trinket.List(i)
	local c = Char(i)
	local out = {}
	if not c then return out end
	for n, id in ipairs(c.list) do
		local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(id)
		if not icon and GetItemInfoInstant then
			icon = select(5, GetItemInfoInstant(id))
		end
		out[n] = { itemID = id, name = name or ("item " .. id), icon = icon }
	end
	return out
end

function ns.Trinket.MoveListed(i, n, delta)
	local c = Char(i)
	if not c or not c.list[n] then return end
	local to = n + delta
	if to < 1 or to > #c.list then return end
	c.list[n], c.list[to] = c.list[to], c.list[n]
	ns.Trinket.Update()
end

function ns.Trinket.RemoveListed(i, n)
	local c = Char(i)
	if not c or not c.list[n] then return end
	table.remove(c.list, n)
	ns.Trinket.Update()
end

function ns.Trinket.Init()
	bar = CreateFrame("Frame", "SanctuaryUITrinketBar", ns.Cluster, "SecureHandlerStateTemplate")
	bar.size = 40
	bar.buttons = {}
	for i = 1, 2 do
		bar.buttons[i] = MakeSocket(bar, i)
	end
	ns.Trinket.bar = bar
	ns.Trinket.mover = ns.MakeMover(bar, "Trinkets", Opt, "Reset its position in /sanctuary > Trinkets.")

	-- Not secure, and parented to the bar so it shares its scale. It closes a moment after the
	-- mouse leaves both it and the sockets.
	menu = CreateFrame("Frame", "SanctuaryUITrinketMenu", bar)
	menu:Hide()
	menu:EnableMouse(false)
	menu.entries = {}
	menu:SetScript("OnUpdate", function(self, elapsed)
		local over = self:IsMouseOver(8, -8, -8, 8)
		for _, button in ipairs(bar.buttons) do
			if button:IsMouseOver(4, -4, -4, 4) then over = true end
		end
		if over then
			self.linger = 0
		else
			self.linger = (self.linger or 0) + elapsed
			if self.linger > 0.35 then self:Hide() end
		end
	end)

	-- Mouseover-only bar; auto-swap and queued swaps on a slow tick out of combat; Shift opens
	-- the menu over a socket in Shift mode.
	local wait, tick = 0, 0
	bar:SetScript("OnUpdate", function(self, elapsed)
		tick = tick + elapsed
		if tick >= 1 then
			tick = 0
			RunAuto()
		end
		if not self.mouseover then return end
		wait = wait - elapsed
		if wait > 0 then return end
		wait = 0.1
		local over = menu:IsShown()
		for _, button in ipairs(self.buttons) do
			if button:IsVisible() and button:IsMouseOver() then over = true end
		end
		self:SetAlpha(over and self.alpha or 0)
	end)

	local events, scanSoon = CreateFrame("Frame"), nil
	for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED",
		"BAG_UPDATE_COOLDOWN", "ACTIONBAR_UPDATE_COOLDOWN", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
		"UPDATE_BINDINGS", "MODIFIER_STATE_CHANGED", "GET_ITEM_INFO_RECEIVED" }) do
		pcall(events.RegisterEvent, events, event)
	end
	events:SetScript("OnEvent", function(_, event, key, down)
		if event == "MODIFIER_STATE_CHANGED" then
			if Opt().menu == "shift" and (key == "LSHIFT" or key == "RSHIFT") and down == 1 then
				for _, button in ipairs(bar.buttons) do
					if button:IsVisible() and button:IsMouseOver() then OpenMenu() end
				end
			end
			return
		end
		if event == "UPDATE_BINDINGS" then
			ns.Trinket.ReassignBindings()
			return
		end
		if event == "GET_ITEM_INFO_RECEIVED" then
			-- Names arriving from the server (many at login): one rescan for the lot.
			if not scanSoon then
				scanSoon = true
				C_Timer.After(0.5, function()
					scanSoon = nil
					ScanBags()
					ns.Trinket.Update()
				end)
			end
			return
		end
		if event == "PLAYER_ENTERING_WORLD" or event == "BAG_UPDATE_DELAYED" or event == "PLAYER_EQUIPMENT_CHANGED" then
			ScanBags()
		end
		if event == "PLAYER_EQUIPMENT_CHANGED" then
			for i = 1, 2 do
				if queued[i] and Equipped(i) == queued[i].itemID then
					queued[i] = nil
					held[i] = Equipped(i)
				end
			end
		end
		if event == "PLAYER_REGEN_ENABLED" then
			if ns.Trinket.pending then
				Configure()
				ns.Trinket.Layout()
			end
			lastTry = 0
			RunAuto()
		end
		ns.Trinket.Update()
	end)
	ScanBags()
	Configure()
	ns.Trinket.Update()
end
