local ns = SanctuaryUI

-- Pie menus: hold a ring's key and it opens at the mouse; move toward a skill and release the
-- key to use it. Release in the middle (or just tap the key) and nothing happens.
--
-- It has to work in combat, so a ring is a hidden secure button bound to the key (a CLICK
-- binding, set on the options page), clicked on key down and key up:
--   down  the pre-click snippet reads the mouse (GetMousePosition, the only way to in combat),
--         moves the shared ring frame there and shows it. The click itself does nothing.
--   up    the snippet picks the slice the mouse moved toward and puts that slice's spell, item
--         or macro on the button; the same click then performs it. "useOnKeyDown" = false
--         makes the action fire on key up whatever the Cast on key down setting says.
-- Everything drawn (icons, the gold socket, the hub's text) is ordinary code that only reads
-- the cursor, so it runs in combat too. Slices can only be changed out of combat.
--
-- Art: tools/blender/pie_menu.py and tools/build_pie_art.py. Sizes here are their contract.

ns.Pie = {}

local MAX_RINGS, MAX_SLICES = 6, 8
ns.Pie.MAX_RINGS, ns.Pie.MAX_SLICES = MAX_RINGS, MAX_SLICES

-- Ring units (UIParent units at scale 1).
local RADIUS = 112 -- the sockets' centres
local DEAD = 32 -- the mouse has to move this far from the centre to pick a slice
local BAND, HUB, SOCKET, STUD = 256, 160, 80, 16 -- texture boxes
local FACE = 51 -- an icon's diameter inside its socket
local BEAM, BACK, GLOW, POINTER = 360, 380, 112, 24
local POINTER_AT = 69
local HOT_SCALE = 1.2
local SWIPE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

local GetSpellName = (C_Spell and C_Spell.GetSpellName) or function(id)
	return GetSpellInfo and (GetSpellInfo(id)) or nil
end
local GetSpellTexture = (C_Spell and C_Spell.GetSpellTexture) or GetSpellTexture or function() end
local IsSpellUsable = (C_Spell and C_Spell.IsSpellUsable) or IsUsableSpell

local header, screen, ring, live, editor
local buttons = {}

local function Opt()
	return ns.DB().pie
end

-- A ring's saved table: { name = "...", slices = { { kind = "spell"|"item"|"macro", id = n, name = "..." } } }
function ns.Pie.Ring(n)
	local rings = Opt().rings
	if type(rings[n]) ~= "table" then rings[n] = {} end
	local r = rings[n]
	if type(r.slices) ~= "table" then r.slices = {} end
	return r
end

function ns.Pie.RingName(n)
	local name = ns.Pie.Ring(n).name
	return (name and name ~= "") and name or ("Ring " .. n)
end

-- The direction of slice i of n: the first is straight up, the rest follow clockwise.
local function Angle(i, n)
	return math.rad(90 - (i - 1) * 360 / n)
end

---------------------------------------------------------------------------
-- What a slice is

local function MacroSpell(name)
	if not GetMacroSpell then return end
	local ok, id = pcall(GetMacroSpell, name)
	return ok and id or nil
end

-- name, icon
local function Info(slice)
	if slice.kind == "spell" then
		return GetSpellName(slice.id) or slice.name or "?", GetSpellTexture(slice.id) or QUESTION
	elseif slice.kind == "item" then
		local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(slice.id)
		local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(slice.id)
		if not icon and GetItemIcon then icon = GetItemIcon(slice.id) end
		return name or slice.name or "?", icon or QUESTION
	elseif slice.kind == "macro" then
		local name, icon = GetMacroInfo(slice.name)
		return slice.name or "?", name and icon or QUESTION
	end
	return "?", QUESTION
end

-- The secure button's "type" and that type's attribute value.
local function Action(slice)
	if slice.kind == "spell" then
		-- By name, so a new rank is used as soon as it is learned; by ID if the name is unknown.
		return "spell", GetSpellName(slice.id) or slice.id
	elseif slice.kind == "item" then
		return "item", "item:" .. slice.id
	elseif slice.kind == "macro" then
		return "macro", slice.name
	end
end

local function SetCooldown(cooldown, slice)
	local spell = slice.kind == "spell" and slice.id or slice.kind == "macro" and MacroSpell(slice.name)
	if spell then
		if C_Spell and C_Spell.GetSpellCooldown then
			local ok, info = pcall(C_Spell.GetSpellCooldown, spell)
			if ok and info then
				pcall(CooldownFrame_Set, cooldown, info.startTime, info.duration, info.isEnabled)
				return
			end
		elseif GetSpellCooldown then
			local start, duration, enabled, modRate = GetSpellCooldown(spell)
			pcall(CooldownFrame_Set, cooldown, start, duration, enabled, false, modRate)
			return
		end
	elseif slice.kind == "item" then
		local get = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
		if get then
			local ok, start, duration, enable = pcall(get, slice.id)
			if ok and (ns.Secret(start) or start) then
				pcall(CooldownFrame_Set, cooldown, start, duration, enable)
				return
			end
		end
	end
	cooldown:Clear()
end

-- false when the client says the skill can't be used now; nil when it won't say (in combat
-- the answer may be hidden) or for things it has no answer for.
local function Usable(slice)
	local spell = slice.kind == "spell" and slice.id or slice.kind == "macro" and MacroSpell(slice.name)
	if not spell or not IsSpellUsable then return end
	local ok, usable = pcall(IsSpellUsable, spell)
	if not ok or ns.Secret(usable) then return end
	return usable and true or false
end

---------------------------------------------------------------------------
-- The ring as drawn: used by the live ring and by the editor

local function Tex(parent, layer, slot, size, blend)
	local t = parent:CreateTexture(nil, layer)
	local path = ns.Art.Require(slot)
	if path then t:SetTexture(path) else t:SetColorTexture(0, 0, 0, 0) end
	t:SetSize(size, size)
	t:SetPoint("CENTER")
	if blend then t:SetBlendMode(blend) end
	return t
end

local function NewSocket(display, i)
	local s = CreateFrame("Button", nil, display)
	s:SetSize(SOCKET, SOCKET)
	s:SetFrameLevel(display:GetFrameLevel() + 2)
	s:EnableMouse(false)
	s.index = i
	s.glow = Tex(s, "BACKGROUND", "pieGlow", GLOW, "ADD")
	s.glow:Hide()
	local face = CreateFrame("Frame", nil, s)
	face:SetSize(FACE, FACE)
	face:SetPoint("CENTER")
	s.icon = face:CreateTexture(nil, "ARTWORK")
	s.icon:SetAllPoints()
	s.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	ns.Art.MaskCircle(s.icon, face)
	s.plus = face:CreateFontString(nil, "OVERLAY")
	s.plus:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 26, "OUTLINE")
	s.plus:SetPoint("CENTER", 0, 1)
	s.plus:SetText("+")
	s.plus:SetTextColor(0.85, 0.72, 0.42, 0.8)
	s.plus:Hide()
	s.cooldown = CreateFrame("Cooldown", nil, face, "CooldownFrameTemplate")
	s.cooldown:SetAllPoints()
	pcall(s.cooldown.SetSwipeTexture, s.cooldown, SWIPE)
	pcall(s.cooldown.SetUseCircularEdge, s.cooldown, true)
	pcall(s.cooldown.SetDrawEdge, s.cooldown, false)
	local top = CreateFrame("Frame", nil, s)
	top:SetAllPoints()
	top:SetFrameLevel(s.cooldown:GetFrameLevel() + 2)
	s.rim = Tex(top, "OVERLAY", "pieSockets", SOCKET)
	s.scale = 1
	return s
end

local function NewDisplay(parent)
	local d = CreateFrame("Frame", nil, parent)
	d:SetSize(BAND, BAND)
	d:SetPoint("CENTER")
	d.back = Tex(d, "BACKGROUND", "pieBack", BACK)
	d.band = Tex(d, "BORDER", "pieBand", BAND)
	d.beam = Tex(d, "ARTWORK", "pieBeam", BEAM, "ADD")
	d.beam:Hide()
	d.studs, d.sockets = {}, {}
	for i = 1, MAX_SLICES do
		local stud = Tex(d, "OVERLAY", "pieStud", STUD)
		stud:Hide()
		d.studs[i] = stud
		d.sockets[i] = NewSocket(d, i)
	end
	local hub = CreateFrame("Frame", nil, d)
	hub:SetSize(HUB, HUB)
	hub:SetPoint("CENTER")
	hub:SetFrameLevel(d:GetFrameLevel() + 10)
	d.hub = hub
	Tex(hub, "ARTWORK", "pieHub", HUB)
	d.pointer = Tex(hub, "OVERLAY", "piePointer", POINTER)
	d.pointer:Hide()
	d.title = hub:CreateFontString(nil, "OVERLAY")
	d.title:SetPoint("CENTER", 0, 7)
	d.title:SetWidth(90)
	d.title:SetJustifyH("CENTER")
	if d.title.SetMaxLines then d.title:SetMaxLines(2) end
	d.title:SetTextColor(0.93, 0.78, 0.47)
	d.sub = hub:CreateFontString(nil, "OVERLAY")
	d.sub:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 9, "")
	d.sub:SetPoint("TOP", d.title, "BOTTOM", 0, -4)
	d.sub:SetWidth(90)
	d.sub:SetTextColor(0.78, 0.74, 0.66)
	return d
end

local function Title(d, text)
	text = text or ""
	-- Exocet is wide: a dozen letters fill the glass at 10.
	local size = #text > 12 and 9 or #text > 8 and 10 or 12.5
	if not d.title:SetFont(ns.FONT, size, "") then
		d.title:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, "")
	end
	d.title:SetText(text)
end

local function Place(region, parent, radius, angle, scale)
	scale = scale or 1
	region:ClearAllPoints()
	region:SetPoint("CENTER", parent, "CENTER", radius * math.cos(angle) / scale, radius * math.sin(angle) / scale)
end

-- Show ring n's slices on a display. extra adds the editor's empty "+" socket.
local function Fill(d, n, extra)
	local slices = ns.Pie.Ring(n).slices
	local count = math.min(#slices, MAX_SLICES)
	local shown = count
	if extra and count < MAX_SLICES then shown = count + 1 end
	d.ringIndex, d.count, d.shown, d.hover = n, count, shown, nil
	d.names = d.names or {}
	for i = 1, MAX_SLICES do
		local s, stud = d.sockets[i], d.studs[i]
		if i <= shown then
			local slice = slices[i]
			s.slice = i <= count and slice or nil
			if s.slice then
				local name, icon = Info(slice)
				d.names[i] = name
				s.icon:SetTexture(icon)
				s.icon:Show()
				s.plus:Hide()
				local usable = Usable(slice)
				if s.icon.SetDesaturated then s.icon:SetDesaturated(usable == false) end
				s.dim = usable == false and 0.5 or 1
				SetCooldown(s.cooldown, slice)
			else
				d.names[i] = nil
				s.icon:Hide()
				s.plus:Show()
				s.cooldown:Clear()
				s.dim = 1
			end
			s.scale = 1
			s:SetScale(1)
			Place(s, d, RADIUS, Angle(i, shown))
			s:Show()
			if shown > 1 then
				Place(stud, d, RADIUS, Angle(i, shown) - math.pi / shown)
				stud:Show()
			else
				stud:Hide()
			end
		else
			s.slice = nil
			s:Hide()
			stud:Hide()
		end
	end
	d.painted = false
end

-- Light the hovered socket (d.hover, nil for none) and write the hub.
local function Paint(d, idle, action)
	local hover = d.hover
	for i = 1, d.shown or 0 do
		local s = d.sockets[i]
		local hot = i == hover
		s.rim:SetTexCoord(hot and 0.5 or 0, hot and 1 or 0.5, 0, 1)
		s.glow:SetShown(hot)
		local v = (hover and not hot) and 0.72 or 1
		v = v * (s.dim or 1)
		s.icon:SetVertexColor(v, v, v)
		s.target = hot and HOT_SCALE or 1
	end
	if hover then
		local a = Angle(hover, d.shown)
		d.beam:SetRotation(a - math.pi / 2)
		d.beam:Show()
		d.pointer:SetRotation(a - math.pi / 2)
		Place(d.pointer, d.hub, POINTER_AT, a)
		d.pointer:Show()
		Title(d, d.names[hover] or "Empty")
		d.sub:SetText(action or "")
	else
		d.beam:Hide()
		d.pointer:Hide()
		Title(d, ns.Pie.RingName(d.ringIndex))
		d.sub:SetText(idle or "")
	end
	d.painted = true
end

-- Ease each socket toward its size.
local function Grow(d, elapsed)
	local k = math.min(1, elapsed * 16)
	for i = 1, d.shown or 0 do
		local s = d.sockets[i]
		local target = s.target or 1
		if s.scale ~= target then
			local v = s.scale + (target - s.scale) * k
			if math.abs(v - target) < 0.004 then v = target end
			s.scale = v
			s:SetScale(v)
			Place(s, d, RADIUS, Angle(i, d.shown), v)
		end
	end
end

---------------------------------------------------------------------------
-- The live ring

local PRE = [[
	local ring = self:GetFrameRef("ring")
	local screen = self:GetFrameRef("screen")
	local x, y = screen:GetMousePosition()
	local w, h = screen:GetWidth(), screen:GetHeight()
	if down then
		self:SetAttribute("type", nil)
		if x then
			local s = self:GetAttribute("pieScale") or 1
			self:SetAttribute("pieX", x * w)
			self:SetAttribute("pieY", y * h)
			ring:Hide()
			ring:ClearAllPoints()
			ring:SetPoint("CENTER", screen, "BOTTOMLEFT", x * w / s, y * h / s)
			ring:SetAttribute("pieOpen", self:GetAttribute("pieRing"))
			ring:Show()
		else
			self:SetAttribute("pieX", nil)
		end
	else
		ring:Hide()
		local pick
		local ox, oy = self:GetAttribute("pieX"), self:GetAttribute("pieY")
		local n = self:GetAttribute("pieCount") or 0
		if x and ox and n > 0 then
			local dx, dy = x * w - ox, y * h - oy
			if dx * dx + dy * dy >= self:GetAttribute("pieDead") then
				local best
				for i = 1, n do
					local dot = dx * self:GetAttribute("pieUX" .. i) + dy * self:GetAttribute("pieUY" .. i)
					if not best or dot > best then
						best, pick = dot, i
					end
				end
			end
		end
		self:SetAttribute("pieX", nil)
		local kind = pick and self:GetAttribute("pieType" .. pick)
		if kind then
			self:SetAttribute("type", kind)
			self:SetAttribute(kind, self:GetAttribute("pieValue" .. pick))
		else
			self:SetAttribute("type", nil)
		end
	end
]]

-- The slice the cursor points at, exactly as the snippet will choose it on release.
local function LiveHover(d)
	local count = d.count or 0
	if count == 0 then return nil end
	local cx, cy = ring:GetCenter()
	if not cx then return nil end
	local scale = ring:GetEffectiveScale()
	local mx, my = GetCursorPosition()
	local dx, dy = mx / scale - cx, my / scale - cy
	if dx * dx + dy * dy < DEAD * DEAD then return nil end
	local best, pick
	for i = 1, count do
		local a = Angle(i, count)
		local dot = dx * math.cos(a) + dy * math.sin(a)
		if not best or dot > best then best, pick = dot, i end
	end
	return pick
end

local function LiveIdle(d)
	return (d.count or 0) > 0 and "Release to cancel" or "Empty: /sanctuary pie"
end

local function BuildLive()
	live = NewDisplay(ring)
	ring:HookScript("OnShow", function()
		local n = tonumber(ring:GetAttribute("pieOpen")) or 1
		Fill(live, n)
		live.hover = LiveHover(live)
		Paint(live, LiveIdle(live), "Release to use")
	end)
	live:SetScript("OnUpdate", function(self, elapsed)
		local hover = LiveHover(self)
		if hover ~= self.hover or not self.painted then
			self.hover = hover
			Paint(self, LiveIdle(self), "Release to use")
		end
		Grow(self, elapsed)
	end)
end

-- Put the saved rings on the secure buttons. Out of combat only.
function ns.Pie.Apply()
	if not ring or InCombatLockdown() then return end
	local scale = Opt().scale or 1
	ring:SetScale(scale)
	for n = 1, MAX_RINGS do
		local b = buttons[n]
		local slices = ns.Pie.Ring(n).slices
		local count = math.min(#slices, MAX_SLICES)
		b:SetAttribute("pieCount", count)
		b:SetAttribute("pieScale", scale)
		b:SetAttribute("pieDead", (DEAD * scale) ^ 2)
		for i = 1, count do
			local a = Angle(i, count)
			local kind, value = Action(slices[i])
			b:SetAttribute("pieUX" .. i, math.cos(a))
			b:SetAttribute("pieUY" .. i, math.sin(a))
			b:SetAttribute("pieType" .. i, kind)
			b:SetAttribute("pieValue" .. i, value)
		end
	end
	if editor then editor:SetScale(scale) end
end

---------------------------------------------------------------------------
-- The editor: the ring in the middle of the screen, its sockets taking drops

local function Changed()
	ns.Pie.Apply()
	if editor and editor:IsShown() then
		Fill(editor.display, editor.ringIndex, true)
		Paint(editor.display, editor.display.count .. " of " .. MAX_SLICES, "")
	end
	local registry = LibStub("AceConfigRegistry-3.0", true)
	if registry then registry:NotifyChange("SanctuaryUI") end
end

-- What the cursor holds, as a slice; nil (and a message) for things a ring can't use.
local function FromCursor()
	local kind, a, _, c = GetCursorInfo()
	if kind == "spell" then
		local id = c or a
		if id then return { kind = "spell", id = id, name = GetSpellName(id) } end
	elseif kind == "item" then
		local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(a)
		return { kind = "item", id = a, name = name }
	elseif kind == "macro" then
		local name = GetMacroInfo(a)
		if name then return { kind = "macro", name = name } end
	elseif kind then
		ns.Print("a ring takes spells, items and macros; put anything else in a macro")
	end
end

local function Pickup(slice)
	if slice.kind == "spell" then
		local pick = (C_Spell and C_Spell.PickupSpell) or PickupSpell
		if pick then pcall(pick, slice.id) end
	elseif slice.kind == "item" then
		local pick = (C_Item and C_Item.PickupItem) or PickupItem
		if pick then pcall(pick, slice.id) end
	elseif slice.kind == "macro" then
		if PickupMacro then pcall(PickupMacro, slice.name) end
	end
end

local function Drop(socket)
	if InCombatLockdown() then return end
	local slice = FromCursor()
	if not slice then return end
	ClearCursor()
	local slices = ns.Pie.Ring(editor.ringIndex).slices
	local old = slices[socket.index]
	slices[math.min(socket.index, #slices + 1)] = slice
	Changed()
	if old then Pickup(old) end -- swapped onto the cursor, as on an action bar
end

local function Remove(socket, pickup)
	if InCombatLockdown() or not socket.slice then return end
	local slices = ns.Pie.Ring(editor.ringIndex).slices
	local old = table.remove(slices, socket.index)
	Changed()
	if pickup and old then Pickup(old) end
end

local function SocketTooltip(self)
	local d = editor.display
	d.hover = self.index
	Paint(d, "", self.slice and "Right-click removes" or "Drop a skill here")
	local slice = self.slice
	if not slice then return end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	if slice.kind == "spell" and GameTooltip.SetSpellByID then
		GameTooltip:SetSpellByID(slice.id)
	elseif slice.kind == "item" and GameTooltip.SetItemByID then
		GameTooltip:SetItemByID(slice.id)
	else
		GameTooltip:SetText((Info(slice)))
	end
	GameTooltip:AddLine("Drag to move it. Right-click to remove it.", 0.7, 0.7, 0.7)
	GameTooltip:Show()
end

local function BuildEditor()
	editor = CreateFrame("Frame", "SanctuaryUIPieEditor", UIParent)
	editor:SetSize(BACK, BACK + 110)
	editor:SetPoint("CENTER", 0, 30)
	editor:SetFrameStrata("DIALOG")
	editor:EnableMouse(true)
	editor:SetMovable(true)
	editor:SetClampedToScreen(true)
	editor:RegisterForDrag("LeftButton")
	editor:SetScript("OnDragStart", editor.StartMoving)
	editor:SetScript("OnDragStop", editor.StopMovingOrSizing)
	editor:Hide()
	tinsert(UISpecialFrames, "SanctuaryUIPieEditor")
	local shade = editor:CreateTexture(nil, "BACKGROUND")
	shade:SetAllPoints()
	shade:SetColorTexture(0, 0, 0, 0.55)

	editor.heading = editor:CreateFontString(nil, "OVERLAY")
	if not editor.heading:SetFont(ns.FONT, 16, "") then
		editor.heading:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 16, "")
	end
	editor.heading:SetPoint("TOP", 0, -14)
	editor.heading:SetTextColor(0.93, 0.78, 0.47)
	local help = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	help:SetPoint("BOTTOM", 0, 44)
	help:SetWidth(BACK - 30)
	help:SetText("Drag spells, items or macros from your spellbook, bags or macro window onto the ring. Drag one off, or right-click it, to remove it. The first skill sits at the top; the rest follow clockwise.")
	local done = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
	done:SetSize(110, 22)
	done:SetPoint("BOTTOM", 0, 14)
	done:SetText("Done")
	done:SetScript("OnClick", function() editor:Hide() end)

	local d = NewDisplay(editor)
	d:ClearAllPoints()
	d:SetPoint("CENTER", 0, 22)
	d.back:Hide()
	editor.display = d
	for _, s in ipairs(d.sockets) do
		s:EnableMouse(true)
		s:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		s:RegisterForDrag("LeftButton")
		s:SetScript("OnReceiveDrag", Drop)
		s:SetScript("OnClick", function(self, button)
			if GetCursorInfo() then
				Drop(self)
			elseif button == "RightButton" then
				Remove(self)
			end
		end)
		s:SetScript("OnDragStart", function(self) Remove(self, true) end)
		s:SetScript("OnEnter", SocketTooltip)
		s:SetScript("OnLeave", function()
			GameTooltip:Hide()
			d.hover = nil
			Paint(d, d.count .. " of " .. MAX_SLICES, "")
		end)
	end
	d:SetScript("OnUpdate", Grow)

	-- Slices can't change in combat, so the editor steps aside.
	editor:RegisterEvent("PLAYER_REGEN_DISABLED")
	editor:SetScript("OnEvent", function(self)
		if self:IsShown() then
			self:Hide()
			ns.Print("ring editor closed for combat")
		end
	end)
end

function ns.Pie.Edit(n)
	n = tonumber(n)
	if not n or n < 1 or n > MAX_RINGS or n % 1 ~= 0 then
		ns.Print(("rings are numbered 1 to %d"):format(MAX_RINGS))
		return
	end
	if InCombatLockdown() then
		ns.Print("rings can't be changed in combat")
		return
	end
	if not ring then return end
	if not editor then BuildEditor() end
	editor.ringIndex = n
	editor:SetScale(Opt().scale or 1)
	editor.heading:SetText(ns.Pie.RingName(n))
	Fill(editor.display, n, true)
	Paint(editor.display, editor.display.count .. " of " .. MAX_SLICES, "")
	editor:Show()
end

-- "Hearthstone, Charge, Rend" for the options page.
function ns.Pie.Describe(n)
	local names = {}
	for i, slice in ipairs(ns.Pie.Ring(n).slices) do
		names[i] = (Info(slice))
	end
	if #names == 0 then return "No skills yet." end
	return table.concat(names, ", ")
end

function ns.Pie.ButtonName(n)
	return "SanctuaryUIPieRing" .. n
end

function ns.Pie.ApplySettings()
	ns.Pie.Apply()
	if editor and editor:IsShown() then
		editor.heading:SetText(ns.Pie.RingName(editor.ringIndex))
		Paint(editor.display, editor.display.count .. " of " .. MAX_SLICES, "")
	end
end

function ns.Pie.Init()
	if ring then return end
	header = CreateFrame("Frame", "SanctuaryUIPieHeader", UIParent, "SecureHandlerBaseTemplate")
	screen = CreateFrame("Frame", "SanctuaryUIPieScreen", UIParent, "SecureFrameTemplate")
	screen:SetAllPoints(UIParent)
	ring = CreateFrame("Frame", "SanctuaryUIPie", UIParent, "SecureFrameTemplate")
	ring:SetSize(BAND, BAND)
	ring:SetFrameStrata("FULLSCREEN_DIALOG")
	ring:SetPoint("CENTER")
	ring:Hide()
	for n = 1, MAX_RINGS do
		local b = CreateFrame("Button", ns.Pie.ButtonName(n), UIParent, "SecureActionButtonTemplate")
		b:RegisterForClicks("AnyUp", "AnyDown")
		b:SetAttribute("useOnKeyDown", false)
		b:SetAttribute("pieRing", n)
		SecureHandlerSetFrameRef(b, "ring", ring)
		SecureHandlerSetFrameRef(b, "screen", screen)
		header:WrapScript(b, "OnClick", PRE)
		buttons[n] = b
	end
	BuildLive()
	ns.Pie.Apply()
	-- A macro renamed or a spell learned in combat: bring the buttons up to date after it.
	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_REGEN_ENABLED")
	events:RegisterEvent("UPDATE_MACROS")
	events:RegisterEvent("SPELLS_CHANGED")
	events:SetScript("OnEvent", function() ns.Pie.Apply() end)
end
