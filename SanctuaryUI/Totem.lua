SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.Totem = ns.Totem or {}

-- The totem bar: one socket per element, earth, fire, water, air, in the order Wrath's totem
-- bar used. Forever has no Blizzard totem bar (its shamans are vanilla's), so this is built
-- from secure spell buttons and the totem API, in the look of the combo point pips.
--
-- Two modes:
--   bar      each socket casts the totem picked for its element. Right-click a socket to
--            dismiss its totem. Shift + right-click fans out the element's known totems:
--            left-click one to put it in the socket, right-click to cast it without changing
--            the socket.
--   tracker  sockets only show totems that are down, and don't cast; right-click dismisses.
-- Keybinds: Key Bindings > AddOns > SanctuaryUI, or hover-binding.

local MAX_ENTRIES = 8

-- Rank 1 spell IDs; the name comes from the client, so other locales match too. The English
-- name is a fallback for IDs the client doesn't know.
local ELEMENTS = {
	{ key = "earth", label = "Earth", slot = EARTH_TOTEM_SLOT or 2, totems = {
		{ 8071, "Stoneskin Totem" },
		{ 8075, "Strength of Earth Totem" },
		{ 2484, "Earthbind Totem" },
		{ 5730, "Stoneclaw Totem" },
		{ 8143, "Tremor Totem" },
	} },
	{ key = "fire", label = "Fire", slot = FIRE_TOTEM_SLOT or 1, totems = {
		{ 3599, "Searing Totem" },
		{ 1535, "Fire Nova Totem" },
		{ 8190, "Magma Totem" },
		{ 8227, "Flametongue Totem" },
		{ 8181, "Frost Resistance Totem" },
	} },
	{ key = "water", label = "Water", slot = WATER_TOTEM_SLOT or 3, totems = {
		{ 5394, "Healing Stream Totem" },
		{ 5675, "Mana Spring Totem" },
		{ 16190, "Mana Tide Totem" },
		{ 8166, "Poison Cleansing Totem" },
		{ 8170, "Disease Cleansing Totem" },
		{ 8184, "Fire Resistance Totem" },
	} },
	{ key = "air", label = "Air", slot = AIR_TOTEM_SLOT or 4, totems = {
		{ 8512, "Windfury Totem" },
		{ 8835, "Grace of Air Totem" },
		{ 8177, "Grounding Totem" },
		{ 10595, "Nature Resistance Totem" },
		{ 15107, "Windwall Totem" },
		{ 25908, "Tranquil Air Totem" },
		{ 6495, "Sentry Totem" },
	} },
}
ns.Totem.ELEMENTS = ELEMENTS

for i, element in ipairs(ELEMENTS) do
	_G["BINDING_NAME_SANCTUARYUITOTEM" .. i] = element.label .. " totem"
end

local GetSpellName = (C_Spell and C_Spell.GetSpellName) or function(id)
	return GetSpellInfo and (GetSpellInfo(id)) or nil
end
local GetSpellTexture = (C_Spell and C_Spell.GetSpellTexture) or GetSpellTexture or function() end

local function Opt()
	return ns.DB().totems
end

local function Secret(value)
	return issecretvalue and issecretvalue(value)
end

---------------------------------------------------------------------------
-- Which totems the player knows, highest rank of each.

-- known[i] = list of { key, id, name, icon } for ELEMENTS[i], in the table's order.
local known = { {}, {}, {}, {} }
local keyById = {}

local function SpellbookByName()
	local found = {}
	-- Ranks are listed lowest first, so the last one seen is the highest.
	if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and Enum and Enum.SpellBookSpellBank then
		local bank = Enum.SpellBookSpellBank.Player
		for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
			local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
			if info then
				for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
					local item = C_SpellBook.GetSpellBookItemInfo(i, bank)
					if item and item.spellID and item.name and not item.isPassive
						and (not Enum.SpellBookItemType or item.itemType == Enum.SpellBookItemType.Spell) then
						found[item.name] = item.spellID
					end
				end
			end
		end
	elseif GetNumSpellTabs then
		local book = BOOKTYPE_SPELL or "spell"
		for tab = 1, GetNumSpellTabs() do
			local _, _, offset, count = GetSpellTabInfo(tab)
			for i = offset + 1, offset + count do
				local kind, id = GetSpellBookItemInfo(i, book)
				local name = GetSpellBookItemName(i, book)
				if kind == "SPELL" and id and name then
					found[name] = id
				end
			end
		end
	end
	return found
end

local function Scan()
	local book = SpellbookByName()
	wipe(keyById)
	for i, element in ipairs(ELEMENTS) do
		local list = known[i]
		wipe(list)
		for _, totem in ipairs(element.totems) do
			local name = GetSpellName(totem[1]) or totem[2]
			local id = book[name] or (ns.Totem.preview and totem[1])
			if id then
				list[#list + 1] = { key = totem[1], id = id, name = name, icon = GetSpellTexture(id) or GetSpellTexture(totem[1]) }
				keyById[id] = totem[1]
			end
		end
	end
end

local function Chosen(i)
	local list = known[i]
	local want = Opt().chosen[ELEMENTS[i].key]
	for _, totem in ipairs(list) do
		if totem.key == want then return totem end
	end
	return list[1]
end

-- The element a totem that is down belongs to: its name starts with the totem's name
-- ("Searing Totem III"), or failing that its icon matches.
local function ElementOf(name, icon)
	for i, element in ipairs(ELEMENTS) do
		for _, totem in ipairs(element.totems) do
			local base = GetSpellName(totem[1]) or totem[2]
			-- Secret first: even a truth test on a secret value throws.
			if not Secret(name) and name and name:find(base, 1, true) == 1 then
				return i
			end
			if not Secret(icon) and icon and icon == GetSpellTexture(totem[1]) then
				return i
			end
		end
	end
end

-- The totem slot of each element. The client's constants are the starting guess; a totem
-- seen in another slot corrects it.
local function SlotFor(i)
	return Opt().slots[ELEMENTS[i].key] or ELEMENTS[i].slot
end

-- What is down, by element: slot, name, start, duration, icon.
local down = {}

-- Is a totem down in this slot? In combat this client can make all of GetTotemInfo secret,
-- and any test on a secret value throws, so check Secret before touching anything. With `have`
-- hidden, the only sign left is the client's duration object (what TotemSweep runs on).
local hiddenSeen = {}

local function SlotHas(slot, have, name)
	if not Secret(have) then
		return have and (Secret(name) or (name ~= nil and name ~= "")) or false
	end
	local object = GetTotemDuration and GetTotemDuration(slot)
	local present = type(object) ~= "nil"
	if hiddenSeen[slot] ~= present then
		hiddenSeen[slot] = present
		ns.Log("totem slot %d: info secret, duration object %s", slot, present and type(object) or "none")
	end
	return present
end

-- Preview: earth and fire totems down on timers that loop, water and air not.
local PREVIEW_DOWN = { [1] = 45, [2] = 20 }
local previewSince = 0

local function PreviewDown(i)
	local duration = PREVIEW_DOWN[i]
	local totem = known[i][1]
	if not duration or not totem then return end
	local now = GetTime()
	return {
		slot = SlotFor(i),
		name = totem.name,
		start = now - (now - previewSince) % duration,
		duration = duration,
		icon = totem.icon,
		spellID = totem.id,
	}
end

local function ScanDown()
	wipe(down)
	if ns.Totem.preview then
		for i = 1, #ELEMENTS do
			down[i] = PreviewDown(i)
		end
		return
	end
	if not GetTotemInfo then return end
	local learned = false
	for slot = 1, (MAX_TOTEMS or 4) do
		local have, name, start, duration, icon = GetTotemInfo(slot)
		if SlotHas(slot, have, name) then
			local i = ElementOf(name, icon)
			if i then
				local old = SlotFor(i)
				if old ~= slot then
					-- Swap, so no two elements share a slot.
					for k = 1, #ELEMENTS do
						if k ~= i and SlotFor(k) == slot then
							Opt().slots[ELEMENTS[k].key] = old
						end
					end
					Opt().slots[ELEMENTS[i].key] = slot
					learned = true
				end
			else
				-- Unknown totem (or a secret name): trust the slot constants.
				for k = 1, #ELEMENTS do
					if SlotFor(k) == slot then i = k end
				end
			end
			if i then
				down[i] = { slot = slot, name = name, start = start, duration = duration, icon = icon }
			end
		end
	end
	if learned then
		-- The dismiss slot is a secure attribute; it moves out of combat.
		ns.Totem.pending = true
		if not InCombatLockdown() then
			ns.Totem.Configure()
		end
	end
end

---------------------------------------------------------------------------
-- Sockets, built like the combo point pips (Globes.lua): the totem's icon cut round, a Kanai's
-- Cube rim in the element's colour, and D3's horned skull ring behind, turned so the skull
-- meets the globe. A totem that is down is lit, with a round sweep running out its time; a
-- socket without one is grey, like an empty pip.

local HORN_SCALE = 128 / 42 -- pip-horn.png is 128 px with a 42 px hole
local RIM_SCALE = 1.28 -- pip-sockets.png rim, of the icon
local PIP_OFFSET = 0.9 -- centre beyond the globe's rim, of a socket's size (as the pips)
local PIP_GAP = 1.66 -- centre spacing, of a socket's size (as the pips)
local ICON_OF_SOCKET = 0.72 -- icon diameter, of a main-bar socket at the bar's scale
local FAN_SIZE = 0.78 -- picker icons, of a socket
local FAN_OUT = 1.55 -- picker arc beyond the sockets, of a socket's size
local FAN_GAP = 1.45 -- picker spacing, of a picker icon
-- pip-sockets.png cells: 0 black, 1 orange, 2 green, 3 red, 4 blue.
local RIM_CELL = { earth = 2, fire = 1, water = 4, air = 0 }
local GLOW_CELL = 6 -- pips.png: soft round glow
local SWIPE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local function Cell(index, cells)
	return index / cells, (index + 1) / cells, 0, 1
end

local function Hotkey(button, i)
	local key = GetBindingKey("SANCTUARYUITOTEM" .. i)
	local KeyBound = LibStub("LibKeyBound-1.0", true)
	button.HotKey:SetText(key and ns.DB().buttons.hotkeys and (KeyBound and KeyBound:ToShortKey(key) or key) or "")
end

-- A round socket: icon, sweep, element rim and hover glow. The horn, which overlaps its
-- neighbours, is made by the caller on a lower frame.
local function Socket(parent, name, element)
	local button = CreateFrame("Button", name, parent, "SecureActionButtonTemplate")
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetAllPoints()
	-- Past the icon's painted border, as the hotbar does, then cut round.
	button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	ns.Art.MaskCircle(button.icon, button)
	local hover = button:CreateTexture(nil, "HIGHLIGHT")
	hover:SetPoint("TOPLEFT", -4, 4)
	hover:SetPoint("BOTTOMRIGHT", 4, -4)
	if ns.Art.Apply(hover, "pips") then
		hover:SetTexCoord(Cell(GLOW_CELL, 8))
		hover:SetVertexColor(1, 0.9, 0.7, 0.55)
	else
		hover:SetColorTexture(1, 0.85, 0.5, 0.2)
	end
	hover:SetBlendMode("ADD")
	button.cooldown = CreateFrame("Cooldown", name .. "Cooldown", button, "CooldownFrameTemplate")
	button.cooldown:SetAllPoints()
	pcall(button.cooldown.SetSwipeTexture, button.cooldown, SWIPE)
	pcall(button.cooldown.SetUseCircularEdge, button.cooldown, true)
	pcall(button.cooldown.SetDrawEdge, button.cooldown, false)
	-- Rim and key text above the sweep.
	local top = CreateFrame("Frame", nil, button)
	top:SetAllPoints()
	top:SetFrameLevel(button.cooldown:GetFrameLevel() + 2)
	local rim = top:CreateTexture(nil, "OVERLAY")
	rim:SetPoint("CENTER")
	if ns.Art.Apply(rim, "pipSockets") then
		rim:SetTexCoord(Cell(RIM_CELL[element.key], 8))
	else
		rim:SetColorTexture(0, 0, 0, 0)
	end
	button.rim, button.top = rim, top
	button:HookScript("OnSizeChanged", function(self, w)
		self.rim:SetSize(w * RIM_SCALE, w * RIM_SCALE)
	end)
	return button
end

local function Horn(parent)
	local frame = CreateFrame("Frame", nil, parent)
	frame:EnableMouse(false)
	local tex = frame:CreateTexture(nil, "BACKGROUND")
	tex:SetAllPoints()
	if not ns.Art.Apply(tex, "pipHorn") then
		tex:SetColorTexture(0, 0, 0, 0)
	end
	frame.tex = tex
	return frame
end

local function SlotTooltip(self)
	if GameTooltip:IsForbidden() then return end
	local info = down[self.element]
	local tracker = Opt().mode == "tracker"
	if tracker and not info then return end
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	local chosen = Chosen(self.element)
	if info and info.spellID then
		GameTooltip:SetSpellByID(info.spellID)
		GameTooltip:AddLine("Preview", 0.86, 0.72, 0.42)
	elseif info and GameTooltip.SetTotem then
		GameTooltip:SetTotem(info.slot)
	elseif chosen then
		GameTooltip:SetSpellByID(chosen.id)
	else
		GameTooltip:SetText(ELEMENTS[self.element].label .. " totem")
	end
	if not tracker and #known[self.element] > 1 then
		GameTooltip:AddLine("Shift + right-click: choose this socket's totem.", 0.7, 0.7, 0.7, true)
	end
	if info then
		GameTooltip:AddLine("Right-click: dismiss.", 0.7, 0.7, 0.7, true)
	end
	GameTooltip:Show()
end

local function EntryTooltip(self)
	if GameTooltip:IsForbidden() or not self.spellID then return end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetSpellByID(self.spellID)
	GameTooltip:AddLine("Left-click: put in the socket. Right-click: cast.", 0.7, 0.7, 0.7, true)
	GameTooltip:Show()
end

-- Shift + right-click on a socket opens its picker (closing the others) instead of acting;
-- plain right-click falls through to dismiss. Restricted code, so it works in combat.
-- The buttons take both the down and the up click (cast-on-key-down acts on the down one), so
-- the picker toggles on the up click only and swallows the down one.
local FAN = [[
	if button == "RightButton" and self:GetAttribute("fan") and IsShiftKeyDown() then
		if down then return false end
		local flyout = self:GetFrameRef("flyout")
		local open = not flyout:IsShown()
		for i = 1, 4 do
			local other = self:GetFrameRef("flyout" .. i)
			if other then other:Hide() end
		end
		if open then flyout:Show() end
		return false
	end
]]

-- Left-click on a picker entry puts its totem in the socket instead of casting it.
-- Right-click casts on whichever click the template acts on; the picker closes on the up click,
-- after either.
local PICK = [[
	if button == "LeftButton" then
		if not down then
			self:GetFrameRef("socket"):SetAttribute("spell", self:GetAttribute("spell2"))
			self:GetParent():Hide()
		end
		return false
	end
	if not down then self:GetParent():Hide() end
]]

local function MakeElement(bar, i)
	local element = ELEMENTS[i]
	local slot = Socket(bar, "SanctuaryUITotem" .. i, element)
	slot.element = i
	slot.horn = Horn(bar.horns)
	slot:RegisterForClicks("AnyUp", "AnyDown")
	slot.HotKey = slot.top:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	slot.HotKey:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
	slot.HotKey:SetTextColor(0.86, 0.72, 0.42)
	slot.HotKey:SetPoint("CENTER", slot, "BOTTOM", 0, 1)
	slot:SetScript("OnEnter", SlotTooltip)
	slot:SetScript("OnLeave", GameTooltip_Hide)
	ns.Menu.KeyBindable(slot, "SANCTUARYUITOTEM" .. i, element.label .. " totem")
	bar:WrapScript(slot, "OnClick", FAN)
	-- A pick from the picker lands here (also in combat): remember it and redraw.
	slot:HookScript("OnAttributeChanged", function(self, name, value)
		if name ~= "spell" then return end
		local key = keyById[tonumber(value) or value]
		if key then Opt().chosen[element.key] = key end
		ns.Totem.Update()
	end)

	local flyout = CreateFrame("Frame", "SanctuaryUITotemFlyout" .. i, bar, "SecureFrameTemplate")
	flyout:Hide()
	flyout.entries = {}
	for j = 1, MAX_ENTRIES do
		local entry = Socket(flyout, ("SanctuaryUITotemFlyout%dEntry%d"):format(i, j), element)
		entry:RegisterForClicks("AnyUp", "AnyDown")
		SecureHandlerSetFrameRef(entry, "socket", slot)
		bar:WrapScript(entry, "OnClick", PICK)
		entry:SetScript("OnEnter", EntryTooltip)
		entry:SetScript("OnLeave", GameTooltip_Hide)
		flyout.entries[j] = entry
	end
	SecureHandlerSetFrameRef(slot, "flyout", flyout)
	slot.flyout = flyout
	return slot
end

---------------------------------------------------------------------------

function ns.Totem.HasTotems()
	if not Opt().enabled then return false end
	if ns.Totem.preview then return true end
	for i = 1, #ELEMENTS do
		if #known[i] > 0 then return true end
	end
	return false
end

-- Spells, slots, sockets shown: secure, so only out of combat.
function ns.Totem.Configure()
	local bar = ns.Totem.bar
	if not bar then return end
	if InCombatLockdown() then
		ns.Totem.pending = true
		return
	end
	ns.Totem.pending = nil
	Scan()
	local opt = Opt()
	local tracker = opt.mode == "tracker"
	local preview = ns.Totem.preview
	for i = 1, #ELEMENTS do
		local slot = bar.slots[i]
		local list = known[i]
		local chosen = Chosen(i)
		slot:SetAttribute("type1", (not tracker and not preview and chosen) and "spell" or nil)
		slot:SetAttribute("spell", chosen and chosen.id or nil)
		-- Right-click dismisses (Shift falls back to it too). Bar: the FAN snippet takes Shift +
		-- right-click for the picker before it gets here.
		slot:SetAttribute("type2", not preview and "destroytotem" or nil)
		slot:SetAttribute("shift-type2", nil)
		slot:SetAttribute("totem-slot", SlotFor(i))
		slot:SetAttribute("fan", (not tracker and #list > 1) or nil)
		slot:SetShown(#list > 0)
		slot.horn:SetShown(#list > 0)
		slot.flyout:Hide()
		for j = 1, MAX_ENTRIES do
			local entry = slot.flyout.entries[j]
			local totem = list[j]
			if totem then
				entry:SetAttribute("type2", not preview and "spell" or nil)
				entry:SetAttribute("spell2", totem.id)
				entry.spellID = totem.id
				entry.icon:SetTexture(totem.icon)
				entry:Show()
			else
				entry:SetAttribute("spell2", nil)
				entry.spellID = nil
				entry:Hide()
			end
		end
		for k = 1, #ELEMENTS do
			SecureHandlerSetFrameRef(slot, "flyout" .. k, bar.slots[k].flyout)
		end
	end
	if ns.Totem.HasTotems() then
		RegisterStateDriver(bar, "visibility", "[petbattle][vehicleui][overridebar][possessbar] hide; show")
	else
		UnregisterStateDriver(bar, "visibility")
		bar:Hide()
	end
	ns.Totem.ReassignBindings()
end

function ns.Totem.ReassignBindings()
	local bar = ns.Totem.bar
	if not bar or InCombatLockdown() then return end
	ClearOverrideBindings(bar)
	for i = 1, #ELEMENTS do
		local slot = bar.slots[i]
		local binding = "SANCTUARYUITOTEM" .. i
		for k = 1, select("#", GetBindingKey(binding)) do
			local key = select(k, GetBindingKey(binding))
			if key and key ~= "" then
				SetOverrideBindingClick(bar, false, key, slot:GetName(), "LeftButton")
			end
		end
		Hotkey(slot, i)
	end
end

local function SpellCooldown(cooldown, id)
	cooldown:SetReverse(false)
	if not id then
		cooldown:Clear()
		return
	end
	if C_Spell and C_Spell.GetSpellCooldown then
		local info = C_Spell.GetSpellCooldown(id)
		if info then
			pcall(CooldownFrame_Set, cooldown, info.startTime, info.duration, info.isEnabled)
		end
	elseif GetSpellCooldown then
		local start, duration, enabled, modRate = GetSpellCooldown(id)
		pcall(CooldownFrame_Set, cooldown, start, duration, enabled, false, modRate)
	end
end

-- The totem's time: the lit part of the icon shrinks as it runs out.
local function TotemSweep(cooldown, info)
	cooldown:SetReverse(true)
	if Secret(info.start) or Secret(info.duration) then
		-- Durations hidden from addons: the engine can still run the sweep.
		local duration = GetTotemDuration and GetTotemDuration(info.slot)
		if duration and cooldown.SetCooldownFromDurationObject then
			cooldown:SetCooldownFromDurationObject(duration)
		else
			cooldown:Clear()
		end
	elseif info.duration and info.duration > 0 then
		pcall(CooldownFrame_Set, cooldown, info.start, info.duration, true)
	else
		cooldown:Clear()
	end
end

-- Icons, sweeps, which totems are down: safe any time.
function ns.Totem.Update()
	local bar = ns.Totem.bar
	if not bar then return end
	ScanDown()
	local tracker = Opt().mode == "tracker"
	for i = 1, #ELEMENTS do
		local slot = bar.slots[i]
		local info = down[i]
		local chosen = Chosen(i)
		local icon = info and not Secret(info.icon) and info.icon or (chosen and chosen.icon)
		slot.icon:SetTexture(icon)
		-- Lit while down; grey like an empty pip otherwise.
		slot.icon:SetDesaturated(not info)
		local shade = info and 1 or 0.55
		if not info and chosen and IsUsableSpell then
			local usable = IsUsableSpell(chosen.id)
			if not Secret(usable) and not usable then shade = 0.35 end
		end
		slot.icon:SetVertexColor(shade, shade, shade)
		if info then
			TotemSweep(slot.cooldown, info)
		else
			SpellCooldown(slot.cooldown, (not tracker) and chosen and chosen.id)
		end
		-- Tracker sockets stay where they are (secure frames don't move in combat) but only
		-- show while their totem is down.
		local alpha = (tracker and not info) and 0 or 1
		slot:SetAlpha(alpha)
		slot.horn:SetAlpha(alpha)
		for j = 1, MAX_ENTRIES do
			local entry = slot.flyout.entries[j]
			if entry.spellID then
				SpellCooldown(entry.cooldown, entry.spellID)
			end
		end
	end
end

---------------------------------------------------------------------------
-- Layout

-- Attached to a globe, the sockets ring its rim the way the combo point pips ring the
-- resource globe: centred on an angle (90 = straight up), each picker fanning out beyond.
function ns.Totem.Attached()
	local attach = Opt().attach
	return (attach == "health" or attach == "resource") and attach or nil
end

local function Place(frame, bar, x, y, size)
	frame:SetSize(size, size)
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", bar, "CENTER", x, y)
end

-- One socket and its horn. rotation turns the skull (0 = skull down).
local function PlaceSocket(slot, bar, x, y, size, rotation)
	Place(slot, bar, x, y, size)
	Place(slot.horn, bar, x, y, size * HORN_SCALE)
	slot.horn.tex:SetRotation(rotation)
end

-- Grows a box around the points placed so far; the picker's box is its mouseover area.
local function Bounds()
	local b = {}
	function b.add(x, y, r)
		b.x0 = math.min(b.x0 or x - r, x - r)
		b.x1 = math.max(b.x1 or x + r, x + r)
		b.y0 = math.min(b.y0 or y - r, y - r)
		b.y1 = math.max(b.y1 or y + r, y + r)
	end
	function b.apply(frame, bar)
		if not b.x0 then return end
		frame:SetSize(b.x1 - b.x0, b.y1 - b.y0)
		frame:ClearAllPoints()
		frame:SetPoint("CENTER", bar, "CENTER", (b.x0 + b.x1) / 2, (b.y0 + b.y1) / 2)
	end
	return b
end

local function LayoutRing(bar, shown, metrics, attach, size)
	local opt = Opt()
	local globe = metrics[attach]
	-- The bar covers the globe; it takes no mouse, so the globe's own tooltip still works.
	bar:SetSize(globe.size, globe.size)
	bar:ClearAllPoints()
	bar:SetPoint("CENTER", ns.Cluster, "BOTTOM", globe.x, metrics.baseY + globe.y)
	local radius = globe.size / 2 + size * PIP_OFFSET + opt.ringGap
	local step = 2 * math.asin(math.min(1, (size * PIP_GAP + opt.spacing - 4) / (2 * radius)))
	local centre = math.rad(attach == "health" and opt.arcHealth or opt.arcResource)
	local fs = size * FAN_SIZE
	local fr = radius + size * FAN_OUT
	local fstep = 2 * math.asin(math.min(1, fs * FAN_GAP / (2 * fr)))
	local ring = Bounds()
	for n, slot in ipairs(shown) do
		local angle = centre + ((#shown + 1) / 2 - n) * step
		PlaceSocket(slot, bar, math.cos(angle) * radius, math.sin(angle) * radius, size, angle - math.pi / 2)
		ring.add(math.cos(angle) * radius, math.sin(angle) * radius, size * RIM_SCALE / 2 + 2)
		-- The picker: an outer arc of smaller sockets, centred on this one.
		local entries = #known[slot.element]
		local box = Bounds()
		for j = 1, MAX_ENTRIES do
			local b = angle + ((entries + 1) / 2 - j) * fstep
			local x, y = math.cos(b) * fr, math.sin(b) * fr
			Place(slot.flyout.entries[j], bar, x, y, fs)
			if j <= entries then box.add(x, y, fs * RIM_SCALE / 2) end
		end
		box.apply(slot.flyout, bar)
	end
	if bar.ringMover then ring.apply(bar.ringMover, bar) end
end

local function LayoutRow(bar, shown, size)
	local opt = Opt()
	local up = opt.flyout ~= "down"
	local pitch = size * PIP_GAP + opt.spacing - 4
	local count = math.max(1, #shown)
	local span = (count - 1) * pitch
	local frameSize = size * RIM_SCALE
	if opt.vertical then
		bar:SetSize(frameSize, span + frameSize)
	else
		bar:SetSize(span + frameSize, frameSize)
	end
	local fs = size * FAN_SIZE
	local fpitch = fs * FAN_GAP
	for n, slot in ipairs(shown) do
		local x, y = 0, 0
		if opt.vertical then
			y = span / 2 - (n - 1) * pitch
		else
			x = -span / 2 + (n - 1) * pitch
		end
		PlaceSocket(slot, bar, x, y, size, up and 0 or math.pi)
		-- The picker: a column of smaller sockets above (or below) this one.
		local entries = #known[slot.element]
		local box = Bounds()
		local dir = up and 1 or -1
		for j = 1, MAX_ENTRIES do
			local ey = y + dir * (size * 0.5 + size * 0.55 + fs * 0.5 + (j - 1) * fpitch)
			Place(slot.flyout.entries[j], bar, x, ey, fs)
			if j <= entries then box.add(x, ey, fs * RIM_SCALE / 2) end
		end
		box.apply(slot.flyout, bar)
	end
end

function ns.Totem.Layout()
	local bar = ns.Totem.bar
	local cluster = ns.Cluster
	local metrics = ns.Metrics and ns.Metrics()
	if not bar or not cluster or not metrics then return end
	if InCombatLockdown() then
		ns.Totem.pending = true
		return
	end
	local opt = Opt()
	local size = metrics.slots[1].w * opt.scale * ICON_OF_SOCKET
	local shown = {}
	for i = 1, #ELEMENTS do
		if bar.slots[i]:IsShown() then shown[#shown + 1] = bar.slots[i] end
	end
	local attach = ns.Totem.Attached()
	if attach then
		LayoutRing(bar, shown, metrics, attach, size)
	else
		LayoutRow(bar, shown, size)
		bar:ClearAllPoints()
		if opt.moved then
			bar:SetPoint("CENTER", UIParent, "BOTTOMLEFT", opt.mx, opt.my)
		else
			-- Centred above the resource globe, mirroring the stance bar over the health globe.
			local globe = metrics.resource
			bar:SetPoint("BOTTOM", cluster, "BOTTOM", globe.x, metrics.baseY + globe.y + globe.size / 2 + size * 0.6)
		end
	end
	-- Horns under the sockets, sockets over the console art, pickers over everything.
	local level = cluster:GetFrameLevel() + ns.LEVEL.buttons
	bar:SetFrameLevel(level)
	bar.horns:SetFrameLevel(level)
	for i = 1, #ELEMENTS do
		local slot = bar.slots[i]
		slot.horn:SetFrameLevel(level)
		slot:SetFrameLevel(level + 2)
		slot.top:SetFrameLevel(level + 5)
		slot.flyout:SetFrameLevel(level + 8)
	end
	bar.alpha, bar.mouseover = opt.alpha, opt.mouseover
	bar:SetAlpha(opt.mouseover and 0 or opt.alpha)
end

function ns.Totem.ApplySettings()
	if not ns.Totem.bar then return end
	ns.Totem.Configure()
	ns.Totem.Layout()
	ns.Totem.Update()
end

-- Session-only: shows the bar with every totem and two fake ones down, for checking the
-- look on any character. Nothing casts while it is on.
function ns.Totem.SetPreview(on)
	if InCombatLockdown() then
		ns.Print("cannot change the totem preview in combat")
		return
	end
	ns.Totem.preview = on and true or nil
	previewSince = GetTime()
	ns.Refresh()
	ns.ActionBar.UpdateMovers()
	ns.Print(on and "totem bar preview on (/sanctuary test to turn off)" or "totem bar preview off")
end

---------------------------------------------------------------------------
-- While frames are unlocked, a ring attached to a globe gets a handle over its sockets:
-- dragging it slides the ring around the rim, following the cursor's angle from the globe.

local atan2 = math.atan2 or math.atan

local function ArcKey()
	return ns.Totem.Attached() == "health" and "arcHealth" or "arcResource"
end

local function CursorAngle(bar)
	local x, y = GetCursorPosition()
	local scale = bar:GetEffectiveScale()
	local cx, cy = bar:GetCenter()
	if not cx then return 0 end
	return math.deg(atan2(y / scale - cy, x / scale - cx))
end

local function StopSlide(mover)
	if not mover.grab then return end
	mover.grab = nil
	mover:SetScript("OnUpdate", nil)
	local registry = LibStub("AceConfigRegistry-3.0", true)
	if registry then registry:NotifyChange("SanctuaryUI") end
end

local function RingMover(bar)
	local mover = CreateFrame("Frame", nil, bar)
	mover:SetFrameStrata("DIALOG")
	mover:EnableMouse(true)
	mover:RegisterForDrag("LeftButton")
	local edge = mover:CreateTexture(nil, "BACKGROUND")
	edge:SetPoint("TOPLEFT", -1, 1)
	edge:SetPoint("BOTTOMRIGHT", 1, -1)
	edge:SetColorTexture(0.86, 0.72, 0.42, 0.8)
	local bg = mover:CreateTexture(nil, "BORDER")
	bg:SetAllPoints()
	bg:SetColorTexture(0.08, 0.05, 0.03, 0.6)
	local text = mover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	text:SetPoint("CENTER")
	text:SetText("Totems")
	mover:SetScript("OnDragStart", function(self)
		if InCombatLockdown() or not ns.Totem.Attached() then return end
		local opt = Opt()
		-- Keep the grab point under the cursor: slide by the change in angle.
		self.grab = CursorAngle(bar) - opt[ArcKey()]
		self:SetScript("OnUpdate", function()
			if InCombatLockdown() then
				StopSlide(self)
				return
			end
			local angle = math.floor((CursorAngle(bar) - self.grab) % 360 + 0.5) % 360
			if angle ~= opt[ArcKey()] then
				opt[ArcKey()] = angle
				ns.Totem.Layout()
			end
		end)
	end)
	mover:SetScript("OnDragStop", StopSlide)
	mover:SetScript("OnMouseUp", function(self, button)
		StopSlide(self)
		if button == "RightButton" then
			ns.SetLocked(true)
		end
	end)
	mover:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Totems")
		GameTooltip:AddLine("Drag to slide the totems around the globe. Right-click to lock all frames.", 1, 1, 1, true)
		GameTooltip:AddLine("Fine-tune it in /sanctuary > Totem bar.", 0.7, 0.7, 0.7, true)
		GameTooltip:Show()
	end)
	mover:SetScript("OnLeave", GameTooltip_Hide)
	mover:Hide()
	return mover
end

-- The free row drags like the hotbars; a ring slides along its globe.
function ns.Totem.UpdateMovers(unlocked)
	local bar = ns.Totem.bar
	if not bar then return end
	local has = unlocked and ns.Totem.HasTotems()
	local attached = ns.Totem.Attached()
	ns.Totem.mover:SetShown(has and not attached)
	bar.ringMover:SetShown(has and attached and true or false)
	if not bar.ringMover:IsShown() then
		StopSlide(bar.ringMover)
	end
end

function ns.Totem.ResetPosition()
	local opt = Opt()
	opt.moved, opt.mx, opt.my = false, 0, 0
	ns.Refresh()
end

function ns.Totem.Init()
	local bar = CreateFrame("Frame", "SanctuaryUITotemBar", ns.Cluster, "SecureHandlerStateTemplate")
	bar.horns = CreateFrame("Frame", nil, bar)
	bar.horns:SetAllPoints()
	bar.slots = {}
	for i = 1, #ELEMENTS do
		bar.slots[i] = MakeElement(bar, i)
	end
	ns.Totem.bar = bar
	ns.Totem.mover = ns.MakeMover(bar, "Totems", Opt, "Reset its position in /sanctuary > Totem bar.")
	bar.ringMover = RingMover(bar)

	-- Mouseover-only: invisible until the mouse is over a socket or an open picker. The
	-- preview's fake timers restart here too.
	local wait = 0
	bar:SetScript("OnUpdate", function(self, elapsed)
		wait = wait - elapsed
		if wait > 0 then return end
		wait = 0.1
		if ns.Totem.preview then
			for i = 1, #ELEMENTS do
				local info = down[i]
				if info and info.start + info.duration <= GetTime() then
					ns.Totem.Update()
					break
				end
			end
		end
		if not self.mouseover then return end
		local over = false
		for i = 1, #ELEMENTS do
			local slot = self.slots[i]
			if (slot:IsVisible() and slot:IsMouseOver()) or (slot.flyout:IsVisible() and slot.flyout:IsMouseOver()) then
				over = true
				break
			end
		end
		self:SetAlpha(over and self.alpha or 0)
	end)

	local events = CreateFrame("Frame", nil, ns.Cluster)
	for _, event in ipairs({ "PLAYER_TOTEM_UPDATE", "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_USABLE", "PLAYER_ENTERING_WORLD", "UPDATE_BINDINGS", "PLAYER_REGEN_ENABLED" }) do
		pcall(events.RegisterEvent, events, event)
	end
	events:SetScript("OnEvent", function(_, event)
		if event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_TAB" or event == "PLAYER_ENTERING_WORLD" or (event == "PLAYER_REGEN_ENABLED" and ns.Totem.pending) then
			ns.Totem.Configure()
			ns.Totem.Layout()
			ns.ActionBar.UpdateMovers()
		elseif event == "UPDATE_BINDINGS" then
			ns.Totem.ReassignBindings()
		end
		ns.Totem.Update()
	end)
	ns.Totem.Configure()
	ns.Totem.Update()
end
