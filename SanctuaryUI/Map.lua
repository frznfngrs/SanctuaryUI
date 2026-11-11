-- The corner map: Blizzard's own minimap frame in a SanctuaryUI setting. Three styles:
--   parchment  Diablo III's torn sheet, square, a little see-through
--   globe      the map under glass in a forged ring, as a third globe
--   fade       no border at all: the map's edge feathers out into the world
-- and "blizzard", which leaves the minimap exactly as the game has it.
--
-- The Minimap frame is moved into our holder, and its old home (MinimapCluster, an Edit Mode
-- system) is hidden by its parent, never with :Hide() (see the Edit Mode taint notes in
-- Blizzard.lua). Around the map: the zone's name and the time, sockets for mail, tracking and
-- the calendar, a drawer that gathers other addons' minimap buttons, markers on the rim for
-- things that lie off the map (with their distance), and the trail you have walked.
SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI

ns.Map = {}
local Map = ns.Map
local P = ns.MapPins

local SOCKET = 26
local PLAQUE_H = 40
local RING = 128 / 100 -- the globe's art over its glass (tools/blender/minimap_ring.py)
local DRAWER_COLS = 4
local DRAWER_CELL = 34
local MARKER = 16
local MAX_MARKERS = 12
local MAX_DOTS = 70
local ROUND_MASK_ID = 186178 -- the client's own round mask, if ours is missing
local SQUARE_MASK_ID = 130937

local holder, outer, mapBox, art, pinLayer, header, bar, sockets, drawer, hidden
local markers, dots = {}, nil
local taken = false
local shape = "ROUND"
local placing = false

local function Opt()
	return ns.DB().map
end

function Map.Active()
	return taken
end

local function Style()
	return Opt().style
end

-- ---------------------------------------------------------------------------------------
-- Taking the minimap over

local function Park(frame)
	if frame and frame.SetParent then frame:SetParent(hidden) end
end

local function AnchorMinimap()
	if Map.lent then return end -- the overlay has it
	placing = true
	Minimap:ClearAllPoints()
	Minimap:SetPoint("CENTER", mapBox, "CENTER", 0, 0)
	placing = false
end

-- Zoom one step and back: makes the game draw the map afresh. Needed after the map changes
-- size (without it the enlarged overlay showed blips on no terrain) and after its opacity is
-- raised in a city (Map.UpdateAlpha). Only ever with the opacity already right for the
-- place: a redraw at less than full opacity is what blacks out a city's floor plan.
local function Nudge()
	if Map.nudging then return end
	Map.nudging = true -- the zoom event this fires must not start another, or move the zoom
	local zoom = Minimap:GetZoom()
	local top = (Minimap.GetZoomLevels and Minimap:GetZoomLevels() or 6) - 1
	Minimap:SetZoom(zoom > 0 and zoom - 1 or math.min(top, zoom + 1))
	Minimap:SetZoom(zoom)
	Map.nudging = nil
end
Map.Nudge = Nudge

local function TakeOver()
	if taken or not Minimap or not MinimapCluster then return false end
	if InCombatLockdown() then return false end
	hidden = hidden or CreateFrame("Frame", nil, UIParent)
	hidden:Hide()

	-- Blizzard's tracking button keeps working from inside our socket (its menu is the game's).
	local tracking = MinimapCluster.Tracking
	local button = tracking and tracking.Button
	if button and sockets.track then
		button:SetParent(sockets.track)
		button:ClearAllPoints()
		button:SetAllPoints(sockets.track)
		button:SetAlpha(0)
		button:SetFrameLevel(sockets.track:GetFrameLevel() + 2)
		sockets.track.blizzard = button
	end

	Minimap:SetParent(mapBox)
	Minimap:SetFrameStrata("LOW")
	Minimap:SetFrameLevel(2)
	hooksecurefunc(Minimap, "SetPoint", function()
		if not placing and taken then AnchorMinimap() end
	end)
	-- The cluster stays where Edit Mode put it, so frames anchored to it keep their place.
	MinimapCluster:SetParent(hidden)
	MinimapCluster:EnableMouse(false)

	Park(Minimap.ZoomIn or MinimapZoomIn)
	Park(Minimap.ZoomOut or MinimapZoomOut)
	for _, name in ipairs({ "MinimapCompassTexture", "MinimapCompassTextureUnderlay", "MinimapBorder", "MinimapNorthTag" }) do
		local piece = _G[name]
		if piece and piece.SetAlpha then piece:SetAlpha(0) end
	end
	for _, method in ipairs({ "SetArchBlobRingAlpha", "SetArchBlobRingScalar", "SetQuestBlobRingAlpha", "SetQuestBlobRingScalar" }) do
		if Minimap[method] then pcall(Minimap[method], Minimap, 0) end
	end
	if not Minimap:GetScript("OnMouseWheel") then
		Minimap:EnableMouseWheel(true)
		Minimap:SetScript("OnMouseWheel", function(self, delta)
			local zoom, top = self:GetZoom(), (self.GetZoomLevels and self:GetZoomLevels() or 6) - 1
			self:SetZoom(math.max(0, math.min(top, zoom + (delta > 0 and 1 or -1))))
		end)
	end
	Minimap:HookScript("OnMouseWheel", function()
		-- After the game's own handler has zoomed. Through Map: LearnZoom is defined further down.
		C_Timer.After(0, function() Map.LearnZoom() end)
	end)
	-- Other addons place their buttons by this.
	GetMinimapShape = function() return shape end
	taken = true
	return true
end

-- ---------------------------------------------------------------------------------------
-- Sockets: mail, tracking, calendar, the drawer

local function MakeSocket(key, cell, tip)
	local b = CreateFrame("Button", nil, bar)
	b.sanctuarySocket = true
	local back = b:CreateTexture(nil, "BACKGROUND")
	if ns.Art.Apply(back, "socket") then
		back:SetTexCoord(unpack(ns.Art.SOCKET_TEXCOORD))
	else
		back:SetColorTexture(0.05, 0.05, 0.05, 0.9)
	end
	b.glyph = b:CreateTexture(nil, "ARTWORK")
	b.glyph:SetPoint("CENTER")
	function b:Resize(size)
		self:SetSize(size, size)
		-- The stone's art runs a little past the socket's face.
		local inset = ns.Art.SOCKET_INSET
		local fw, fh = size / (1 - inset.left - inset.right), size / (1 - inset.top - inset.bottom)
		back:ClearAllPoints()
		back:SetPoint("TOPLEFT", -fw * inset.left, fh * inset.top)
		back:SetPoint("BOTTOMRIGHT", fw * inset.right, -fh * inset.bottom)
		self.glyph:SetSize(size * 0.7, size * 0.7)
	end
	b:Resize(SOCKET)
	if cell then P.SetCell(b.glyph, cell) else b.glyph:Hide() end
	b.glyph:SetVertexColor(0.84, 0.75, 0.54)
	-- lit: the glyph in bright gold, for a socket with something waiting (mail).
	function b:Tint(hover)
		if hover then
			self.glyph:SetVertexColor(1, 0.93, 0.72)
		elseif self.lit then
			self.glyph:SetVertexColor(1, 0.80, 0.25)
		else
			self.glyph:SetVertexColor(0.84, 0.75, 0.54)
		end
	end
	b:SetScript("OnEnter", function(self)
		self:Tint(true)
		if tip then
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
			tip(GameTooltip)
			GameTooltip:Show()
		end
	end)
	b:SetScript("OnLeave", function(self)
		self:Tint(false)
		GameTooltip_Hide()
	end)
	sockets[key] = b
	return b
end

local function HasMail()
	return HasNewMail and HasNewMail() and true or false
end

local function MailTip(tip)
	tip:AddLine("You have mail", 1, 0.82, 0.4)
	if GetLatestThreeSenders then
		for _, sender in ipairs({ GetLatestThreeSenders() }) do
			if sender and not ns.Secret(sender) then tip:AddLine(sender, 1, 1, 1) end
		end
	end
end

local function CalendarTip(tip)
	tip:AddLine(date("%A, %d %B"), 1, 0.82, 0.4)
	tip:AddLine("|cffffffffClick|r calendar", 0.8, 0.8, 0.8)
	tip:AddLine("|cffffffffRight-click|r stopwatch and alarm", 0.8, 0.8, 0.8)
end

-- The drawer: every LibDBIcon button, off the map's rim and into one panel.
local adopted = {}

local function LayoutDrawer()
	if not drawer then return end
	local shown = {}
	for button in pairs(adopted) do
		if button:IsShown() then shown[#shown + 1] = button end
	end
	table.sort(shown, function(a, b) return (a:GetName() or "") < (b:GetName() or "") end)
	local cols = math.min(DRAWER_COLS, math.max(1, #shown))
	local rows = math.max(1, math.ceil(#shown / DRAWER_COLS))
	drawer:SetSize(cols * DRAWER_CELL + 10, rows * DRAWER_CELL + 10)
	placing = true
	for i, button in ipairs(shown) do
		local col, row = (i - 1) % DRAWER_COLS, math.floor((i - 1) / DRAWER_COLS)
		button:ClearAllPoints()
		-- Filled from the right, under the drawer's socket.
		button:SetPoint("CENTER", drawer, "TOPRIGHT", -5 - (col + 0.5) * DRAWER_CELL, -5 - (row + 0.5) * DRAWER_CELL)
	end
	placing = false
	local had = drawer.count or 0
	drawer.count = #shown
	-- The drawer's socket comes and goes with its first button.
	if (had > 0) ~= (#shown > 0) and taken then Map.Layout() end
end

local function Adopt(button)
	if not button or adopted[button] or not drawer then return end
	adopted[button] = true
	button:SetParent(drawer)
	button:SetFrameLevel(drawer:GetFrameLevel() + 2)
	-- No dragging round a rim it is no longer on.
	button:SetScript("OnDragStart", nil)
	button:SetScript("OnDragStop", nil)
	hooksecurefunc(button, "SetPoint", function()
		if not placing then LayoutDrawer() end
	end)
	button:HookScript("OnShow", function() if not placing then LayoutDrawer() end end)
	button:HookScript("OnHide", function() if not placing then LayoutDrawer() end end)
end

-- Buttons other addons hang on the minimap without the usual library. Told apart from map
-- pins (Questie, HandyNotes, gathering addons) and the game's own pieces by name and shape.
local NOT_BUTTONS = { "^Questie", "^HandyNotes", "^GatherMate", "^Gatherer", "^GatherLite", "^TomTom", "^HBD", "^HereBeDragons",
	"^Minimap", "^MiniMap", "^GameTime", "^TimeManager", "^QueueStatus", "^ExpansionLanding", "^Garrison", "^LibDBIcon",
	"^SanctuaryUI", "^ElvUI", "^Spy_", "^ZGV", "^Dugi", "^Archy", "Pin%d*$", "Node%d*$", "Note%d*$", "POI" }

local function LooksLikeButton(frame)
	if adopted[frame] or not frame.IsObjectType or not frame:IsObjectType("Button") then return false end
	local name = frame:GetName()
	if not name then return false end
	for _, pattern in ipairs(NOT_BUTTONS) do
		if name:find(pattern) then return false end
	end
	local w, h = frame:GetSize()
	if not w or w < 18 or w > 48 or math.abs(w - h) > 6 then return false end
	return frame:GetScript("OnClick") ~= nil or frame:GetScript("OnMouseUp") ~= nil or frame:GetScript("OnMouseDown") ~= nil
end

local function CollectLoose(parent)
	if not parent or not parent.GetChildren then return end
	for _, child in ipairs({ parent:GetChildren() }) do
		if LooksLikeButton(child) then Adopt(child) end
	end
end

local function Collect()
	if not taken or not Opt().drawer then return end
	CollectLoose(Minimap)
	CollectLoose(MinimapBackdrop)
	local lib = LibStub and LibStub("LibDBIcon-1.0", true)
	if not lib then
		LayoutDrawer()
		return
	end
	for _, button in pairs(lib.objects or {}) do Adopt(button) end
	if not Map.listening and lib.RegisterCallback then
		Map.listening = true
		lib.RegisterCallback(Map, "LibDBIcon_IconCreated", function(_, button)
			if taken and Opt().drawer then
				Adopt(button)
				LayoutDrawer()
			end
		end)
	end
	LayoutDrawer()
end

local function OverDrawer()
	return drawer:IsMouseOver() or sockets.more:IsMouseOver()
end

local function OpenDrawer()
	if (drawer.count or 0) == 0 then return end
	drawer:Show()
	drawer.leftAt = nil
end

-- ---------------------------------------------------------------------------------------
-- Building

local function Text(parent, role, size)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	ns.Fonts.Set(fs, role, size, "OUTLINE")
	fs:SetShadowColor(0, 0, 0, 1)
	fs:SetShadowOffset(1, -1)
	return fs
end

local function Build()
	holder = CreateFrame("Frame", "SanctuaryUIMap", UIParent)
	holder:SetFrameStrata("LOW")
	holder:SetClampedToScreen(true)
	outer = CreateFrame("Frame", nil, holder) -- the map with its frame art: what things sit around
	mapBox = CreateFrame("Frame", nil, holder)
	bar = CreateFrame("Frame", nil, holder) -- the buttons
	bar:SetFrameLevel(44)

	-- Above the map itself, under the things other addons pin on it.
	art = CreateFrame("Frame", nil, holder)
	art:SetFrameLevel(4)
	art:EnableMouse(false)
	art.tex = art:CreateTexture(nil, "ARTWORK")
	art.plaque = art:CreateTexture(nil, "BACKGROUND")
	-- The death view: a cold wash over the map, cut to the map's own shape.
	art.ghost = art:CreateTexture(nil, "BORDER")
	art.ghost:SetColorTexture(0.45, 0.58, 0.80, 0.34)
	art.ghost:Hide()
	art.ghostMask = art:CreateMaskTexture()
	art.ghost:AddMaskTexture(art.ghostMask)

	pinLayer = CreateFrame("Frame", nil, holder)
	-- Over everything the Minimap frame draws. The game puts its own arrow for a party member
	-- on the map's edge and it cannot be turned off on this client; ours, in the member's
	-- class colour, is simply drawn over it. (A dark stud to hide the game's arrow was tried
	-- on 2026-11-11 and the user preferred it without.)
	pinLayer:SetFrameStrata("MEDIUM")
	pinLayer:SetFrameLevel(40)
	pinLayer:EnableMouse(false)
	pinLayer:SetAllPoints(mapBox)
	dots = P.DotPool(pinLayer, "ARTWORK")
	for i = 1, MAX_MARKERS do
		markers[i] = P.MakeMarker(pinLayer, MARKER)
		markers[i]:Hide()
	end
	pinLayer.corpseLine = pinLayer:CreateLine(nil, "BACKGROUND")
	pinLayer.corpseLine:SetThickness(2)
	pinLayer.corpseLine:SetColorTexture(1, 0.81, 0.33, 0.85)
	pinLayer.corpseLine:Hide()

	header = CreateFrame("Frame", nil, holder)
	header:SetFrameLevel(42)
	header:EnableMouse(false)
	header.zone = Text(header, "title", 13)
	header.zone:SetTextColor(0.87, 0.75, 0.47)
	header.time = Text(header, "body", 11)
	header.time:SetTextColor(0.91, 0.87, 0.77)

	sockets = {}
	MakeSocket("mail", "mail", MailTip)
	MakeSocket("track", "track")
	local calendar = MakeSocket("calendar", "calendar", CalendarTip)
	calendar:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	calendar:SetScript("OnClick", function(_, button)
		if button == "RightButton" then
			if ToggleTimeManager then ToggleTimeManager() elseif TimeManager_Toggle then TimeManager_Toggle() end
		elseif ToggleCalendar then
			ToggleCalendar()
		elseif GameTimeFrame then
			GameTimeFrame:Click()
		end
	end)
	MakeSocket("queue") -- the game's queue eye sits in it: see SeatQueue
	local more = MakeSocket("more", "more", function(tip)
		tip:AddLine("Addon buttons", 1, 0.82, 0.4)
	end)
	more:HookScript("OnEnter", OpenDrawer)
	more:SetScript("OnClick", function()
		if drawer:IsShown() then drawer:Hide() else OpenDrawer() end
	end)

	drawer = CreateFrame("Frame", nil, holder)
	drawer:SetFrameStrata("MEDIUM")
	drawer:SetClampedToScreen(true)
	drawer:SetPoint("TOPRIGHT", more, "BOTTOMRIGHT", 4, -4)
	drawer:EnableMouse(true)
	drawer.back = drawer:CreateTexture(nil, "BACKGROUND")
	drawer.back:SetAllPoints()
	local plaque = ns.Art.Require("mapPlaque")
	if plaque then drawer.back:SetTexture(plaque) else drawer.back:SetColorTexture(0.07, 0.06, 0.06, 0.92) end
	drawer:Hide()
	drawer:SetScript("OnUpdate", function(self)
		if OverDrawer() then
			self.leftAt = nil
		else
			self.leftAt = self.leftAt or GetTime()
			if GetTime() - self.leftAt > 0.6 then self:Hide() end
		end
	end)

	Map.holder = holder
	Map.mover = ns.MakeMover(holder, "Minimap", Opt, "Reset its position in /sanctuary > Minimap.")
	Map.barMover = ns.MakeMover(bar, "Minimap buttons", function() return Opt().buttons end,
		"Shown while the buttons are set to \"Anywhere\". Reset in /sanctuary > Minimap > Buttons.")
end

-- ---------------------------------------------------------------------------------------
-- Layout for the style in use

local function MaskFor(style)
	if style == "parchment" then
		return ns.Art.Require("mapMaskTorn") or SQUARE_MASK_ID
	elseif style == "fade" then
		return ns.Art.Require("mapMaskFade") or ns.Art.Require("mapMaskRound") or ROUND_MASK_ID
	end
	return ns.Art.Require("mapMaskRound") or ROUND_MASK_ID
end
Map.MaskFor = MaskFor

-- "style" in a setting means: whatever suits the style in use.
local function HeaderPlace(opt, style)
	if opt.headerPlace ~= "style" then return opt.headerPlace end
	return style == "globe" and "below" or "above"
end

local function HeaderAlign(opt, style)
	if opt.headerAlign ~= "style" then return opt.headerAlign end
	return style == "parchment" and "right" or "center"
end

local function ButtonAlign(b, style)
	if b.align ~= "style" then return b.align end
	return style == "parchment" and "end" or "center"
end

-- The game's queue button (the eye, while you are queued for a battleground or a dungeon). It
-- normally sits on Blizzard's micro menu; with that hidden it is left floating in the middle
-- of the screen. It gets a seat among the minimap's buttons, and goes back where the game had
-- it when that seat is turned off.
local queue = {}

-- Which frame that is differs between clients. Once one is seated it stays the one; until
-- then, whichever is showing wins.
local QUEUE_NAMES = { "QueueStatusButton", "MiniMapLFGFrame", "LFGMinimapFrame", "MiniMapBattlefieldFrame" }

local function QueueButton()
	if queue.button then return queue.button end
	local first
	for _, name in ipairs(QUEUE_NAMES) do
		local frame = _G[name]
		if frame and frame.IsShown then
			first = first or frame
			if frame:IsShown() then return frame end
		end
	end
	return first
end

local function QueueWanted()
	local b = Opt().buttons
	return taken and b.queue and b.show ~= "never" and Style() ~= "blizzard"
end

local function QueueShowing()
	local button = queue.seated and QueueButton()
	return button and button:IsShown() and true or false
end

local function CentreQueue()
	local button, seat = QueueButton(), sockets.queue
	placing = true
	local w = button:GetWidth()
	button:SetScale((w and w > 0) and (seat:GetWidth() * 1.15 / w) or 1)
	button:ClearAllPoints()
	button:SetPoint("CENTER", seat, "CENTER")
	placing = false
end

local function SeatQueue()
	local button = QueueButton()
	if not button or not sockets or not sockets.queue then return end
	-- A different one has come up than the one first found (nothing was queued at login).
	if queue.seated and queue.home and queue.homeOf ~= button then return end
	if QueueWanted() then
		if not queue.seated then
			if queue.homeOf ~= button then queue.home, queue.homeOf, queue.hooked = nil, button, nil end
			if InCombatLockdown() and button.IsProtected and button:IsProtected() then return end
			queue.home = queue.home or { parent = button:GetParent(), scale = button:GetScale(), strata = button:GetFrameStrata(), points = {} }
			if #queue.home.points == 0 then
				for i = 1, button:GetNumPoints() do queue.home.points[i] = { button:GetPoint(i) } end
			end
			queue.seated = true
			queue.button = button
			button:SetParent(sockets.queue)
			button:SetFrameLevel(sockets.queue:GetFrameLevel() + 2)
			if not queue.hooked then
				queue.hooked = true
				hooksecurefunc(button, "SetPoint", function()
					if queue.seated and not placing then CentreQueue() end
				end)
				-- The bar makes room for it, and closes up after it.
				local function Relayout()
					C_Timer.After(0, function() if queue.seated and taken then Map.Layout() end end)
				end
				button:HookScript("OnShow", Relayout)
				button:HookScript("OnHide", Relayout)
			end
		end
		CentreQueue()
	elseif queue.seated then
		queue.seated = nil
		queue.button = nil
		local home = queue.home
		placing = true
		button:SetParent(home.parent)
		button:SetFrameStrata(home.strata)
		button:SetScale(home.scale)
		button:ClearAllPoints()
		for _, p in ipairs(home.points) do button:SetPoint(unpack(p)) end
		placing = false
	end
end

-- The buttons that are on right now, in order.
local function ShownSockets()
	local opt = Opt()
	local b = opt.buttons
	local list = {}
	local on = b.show ~= "never"
	local want = {
		mail = on and b.mail and HasMail(),
		track = on and b.tracking and sockets.track.blizzard ~= nil,
		calendar = on and b.calendar,
		queue = QueueShowing(),
		more = on and opt.drawer and (drawer.count or 0) > 0,
	}
	for _, key in ipairs({ "mail", "track", "calendar", "queue", "more" }) do
		local socket = sockets[key]
		socket:SetShown(want[key] and true or false)
		if want[key] then list[#list + 1] = socket end
	end
	return list
end

-- Line the buttons up inside their bar. Returns the bar's size.
local function FillBar(list, vertical)
	local b = Opt().buttons
	local size, gap = b.size, b.gap
	local long = #list * size + math.max(0, #list - 1) * gap
	for i, socket in ipairs(list) do
		socket:Resize(size)
		socket:ClearAllPoints()
		local at = (i - 1) * (size + gap)
		if vertical then
			socket:SetPoint("TOP", bar, "TOP", 0, -at)
		else
			socket:SetPoint("LEFT", bar, "LEFT", at, 0)
		end
	end
	local w, h = vertical and size or math.max(long, 1), vertical and math.max(long, 1) or size
	bar:SetSize(w, h)
	if queue.seated then CentreQueue() end -- at the size just set
	sockets.mail.lit = HasMail()
	sockets.mail:Tint(false)
	return w, h
end

local ALONG = { start = "LEFT", center = "", ["end"] = "RIGHT" } -- a row's place along the map's edge
local DOWN = { start = "TOP", center = "", ["end"] = "BOTTOM" } -- a column's

function Map.Layout()
	if not holder then return end
	local opt = Opt()
	local style = opt.style
	if style == "blizzard" or not taken then
		holder:SetShown(false)
		return
	end
	if opt.sockets == false then -- the old on/off switch
		opt.buttons.show, opt.sockets = "never", nil
	end
	holder:SetShown(not Map.lent)
	holder:SetScale(opt.scale)
	local b = opt.buttons
	local size = opt.size
	local pad = style == "globe" and (size * RING - size) / 2 or 0
	local full = size + pad * 2
	shape = style == "parchment" and "SQUARE" or "ROUND"

	-- The name and the time
	local hs = opt.headerScale
	-- The second line carries the time and, in an instance, its difficulty.
	local second = opt.clock or opt.difficulty
	local showHead = opt.zone or second
	local headPlace = HeaderPlace(opt, style)
	local headAlign = HeaderAlign(opt, style)
	local plaque = style == "globe" and headPlace == "below" and showHead
	local line1, line2 = 15 * hs, 13 * hs
	local headH = 0
	if showHead then
		headH = (opt.zone and line1 or 0) + (second and line2 or 0) + 4
		if plaque then headH = math.max(PLAQUE_H, headH + 14) - 6 end
	end

	-- The buttons
	SeatQueue()
	local list = ShownSockets()
	local side = b.side
	local vertical = side == "left" or side == "right" or (side == "free" and b.vertical)
	local barW, barH = FillBar(list, vertical)
	local hasBar = #list > 0
	bar:SetShown(hasBar)
	local barRow = hasBar and (side == "above" or side == "below") and (barH + 8) or 0

	local top = (headPlace == "above" and headH or 0) + (side == "above" and barRow or 0)
	local bottom = (headPlace == "below" and headH or 0) + (side == "below" and barRow or 0)
	holder:SetSize(full, top + full + bottom)
	outer:ClearAllPoints()
	outer:SetSize(full, full)
	outer:SetPoint("TOP", holder, "TOP", 0, -top)
	mapBox:ClearAllPoints()
	mapBox:SetSize(size, size)
	mapBox:SetPoint("CENTER", outer, "CENTER")

	-- Frame art
	art.tex:ClearAllPoints()
	if style == "globe" then
		art.tex:SetAllPoints(outer)
		art.tex:SetTexture(ns.Art.Require("mapRing"))
		art.tex:Show()
	elseif style == "parchment" then
		art.tex:SetAllPoints(mapBox)
		art.tex:SetTexture(ns.Art.Require("mapParchment"))
		art.tex:Show()
	else
		art.tex:Hide()
	end

	art.ghost:ClearAllPoints()
	art.ghost:SetAllPoints(mapBox)
	art.ghostMask:ClearAllPoints()
	art.ghostMask:SetAllPoints(mapBox)
	art.ghostMask:SetTexture(MaskFor(style), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")

	-- Place the name and the time
	local zone, time = header.zone, header.time
	ns.Fonts.Set(zone, "title", 13 * hs, "OUTLINE")
	ns.Fonts.Set(time, "body", 11 * hs, "OUTLINE")
	zone:ClearAllPoints()
	time:ClearAllPoints()
	zone:SetWidth(0)
	time:SetWidth(0)
	art.plaque:Hide()
	if plaque then
		local pw = math.min(full, math.max(210, 210 * hs))
		art.plaque:SetTexture(ns.Art.Require("mapPlaque"))
		art.plaque:ClearAllPoints()
		art.plaque:SetSize(pw, headH + 6)
		art.plaque:SetPoint("TOP", outer, "BOTTOM", 0, 8)
		art.plaque:Show()
		zone:SetPoint("CENTER", art.plaque, "CENTER", 0, second and line2 / 2 or 0)
		time:SetPoint("CENTER", art.plaque, "CENTER", 0, opt.zone and -line1 / 2 or 0)
		zone:SetJustifyH("CENTER")
		time:SetJustifyH("CENTER")
	else
		-- Anchored by the edge they are aligned to, so no width or justifying is needed.
		local edge = headAlign == "left" and "LEFT" or headAlign == "right" and "RIGHT" or ""
		local inset = headAlign == "left" and 4 or headAlign == "right" and -4 or 0
		if headPlace == "above" then
			time:SetPoint("BOTTOM" .. edge, outer, "TOP" .. edge, inset, 3)
			zone:SetPoint("BOTTOM" .. edge, outer, "TOP" .. edge, inset, 3 + (second and line2 or 0))
		else
			zone:SetPoint("TOP" .. edge, outer, "BOTTOM" .. edge, inset, -3)
			time:SetPoint("TOP" .. edge, outer, "BOTTOM" .. edge, inset, -3 - (opt.zone and line1 or 0))
		end
		local justify = headAlign == "left" and "LEFT" or headAlign == "right" and "RIGHT" or "CENTER"
		zone:SetJustifyH(justify)
		time:SetJustifyH(justify)
	end
	zone:SetShown(opt.zone)
	time:SetShown(second and true or false)

	-- Place the buttons
	bar:ClearAllPoints()
	bar:SetScale(1)
	if side == "free" then
		if b.moved then
			bar:SetPoint("CENTER", UIParent, "BOTTOMLEFT", ns.MovedPoint(bar, b))
		else
			bar:SetPoint("TOP", outer, "BOTTOM", 0, -(headPlace == "below" and headH or 0) - 6)
		end
	elseif side == "left" or side == "right" then
		local edge = DOWN[ButtonAlign(b, style)]
		local mine = side == "left" and "RIGHT" or "LEFT"
		local theirs = side == "left" and "LEFT" or "RIGHT"
		bar:SetPoint(edge .. mine, outer, edge .. theirs, (side == "left" and -6 or 6) + b.x, b.y)
	else
		local edge = ALONG[ButtonAlign(b, style)]
		if side == "above" then
			bar:SetPoint("BOTTOM" .. edge, outer, "TOP" .. edge, b.x, (headPlace == "above" and headH or 0) + 6 + b.y)
		else
			bar:SetPoint("TOP" .. edge, outer, "BOTTOM" .. edge, b.x, -(headPlace == "below" and headH or 0) - 6 + b.y)
		end
	end

	holder:ClearAllPoints()
	if opt.moved then
		holder:SetPoint("CENTER", UIParent, "BOTTOMLEFT", ns.MovedPoint(holder, opt))
	else
		holder:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -22, -22)
	end

	if not Map.lent then
		-- Only when they change: a refresh for some other setting leaves the map alone.
		local mask = MaskFor(style)
		local set = Map.applied or {}
		Map.applied = set
		local resized = set.size ~= size
		if resized then
			set.size = size
			Minimap:SetSize(size, size)
		end
		if set.mask ~= mask then
			set.mask = mask
			Minimap:SetMaskTexture(mask)
		end
		Map.UpdateAlpha()
		AnchorMinimap()
		if resized then Nudge() end -- after the opacity is right for this place
	end
	-- A font string keeps its old alignment until its text changes.
	zone:SetText("")
	time:SetText("")
	Map.UpdateText()
	Map.UpdateMovers(not ns.DB().locked and not InCombatLockdown())
end

-- The game has two sets of zoom levels: the open world's, and a tighter one for buildings and
-- for city districts built as interiors (Ironforge, Stormwind's districts but not its canals).
-- In the second the map is a floor plan on black. The view radius at the current zoom says
-- which set is in use.
local INTERIOR_RADIUS = { 150, 120, 90, 60, 40, 25 }

function Map.Interior()
	if IsIndoors and IsIndoors() then return true end
	if not (C_Minimap and C_Minimap.GetViewRadius) then return false end
	local radius = C_Minimap.GetViewRadius()
	local want = INTERIOR_RADIUS[(Minimap:GetZoom() or 0) + 1]
	if not radius or ns.Secret(radius) or not want then return false end
	return math.abs(radius - want) < 1
end

-- The map's opacity. In the open world it is the player's setting. In interior mode it must
-- be exactly 1: at anything less, the game draws the floor plan as solid black the next time
-- it draws it (on entering the city, on a zoom change, at login). Found in game on
-- 2026-11-11 by adding our changes to the game's minimap one at a time and forcing a redraw
-- after each: mask and size were harmless, opacity alone did it. A plan already drawn black
-- stays black, so after raising the opacity the map is nudged to draw afresh.
-- Returns the opacity in force, for the overlay.
function Map.OpacityHere(wanted)
	return Map.Interior() and 1 or wanted
end

function Map.SetMapAlpha(wanted)
	local alpha = Map.OpacityHere(wanted)
	local was = Minimap:GetAlpha()
	if math.abs(was - alpha) < 0.001 then return end
	Minimap:SetAlpha(alpha)
	if alpha == 1 then Nudge() end
end

function Map.UpdateAlpha()
	if not taken or Map.lent then return end
	Map.SetMapAlpha(Opt().opacity)
end

-- Self-adjusting zoom. The map keeps a zoom for each way of getting about and changes to it
-- when that changes: riding or on a flight path (wide), inside a building (tight), in a city
-- built as an interior, and on foot. Zooming by hand with the wheel teaches it: the new zoom
-- becomes the one remembered for the state you are in.
local function ZoomState()
	if (UnitOnTaxi and UnitOnTaxi("player")) or (IsMounted and IsMounted()) then return "mounted" end
	if IsIndoors and IsIndoors() then return "indoors" end
	if Map.Interior() then return "city" end
	return "foot"
end

local function TopZoom()
	return (Minimap.GetZoomLevels and Minimap:GetZoomLevels() or 6) - 1
end

function Map.UpdateZoom(force)
	if not taken or Map.lent or Map.nudging then return end
	local opt = Opt()
	if not opt.autoZoom then
		Map.zoomState = nil
		return
	end
	local state = ZoomState()
	if state == Map.zoomState and not force then return end
	Map.zoomState = state
	local want = opt.zoom[state]
	if want < 0 then
		-- Never set: the zoom you have now is the one you like here.
		opt.zoom[state] = Minimap:GetZoom()
		return
	end
	want = math.max(0, math.min(TopZoom(), want))
	if Minimap:GetZoom() ~= want then Minimap:SetZoom(want) end
end

-- After the wheel: remember what the player chose for this state.
function Map.LearnZoom()
	local opt = Opt()
	if not taken or not opt.autoZoom or Map.lent then return end
	opt.zoom[ZoomState()] = Minimap:GetZoom()
	local registry = LibStub("AceConfigRegistry-3.0", true)
	if registry then registry:NotifyChange("SanctuaryUI") end
end

function Map.UpdateText()
	if not header then return end
	local zone = GetMinimapZoneText and GetMinimapZoneText() or ""
	if ns.Secret(zone) then zone = "" end
	header.zone:SetText(zone:upper())
	local opt = Opt()
	local parts = {}
	local area = GetRealZoneText and GetRealZoneText() or ""
	if ns.Secret(area) then area = "" end
	if opt.zone and area ~= "" and area ~= zone then parts[#parts + 1] = area end
	-- Inside an instance: its difficulty and size, where Blizzard's minimap flies a flag.
	if opt.difficulty and IsInInstance() then
		local _, _, _, difficulty, players = GetInstanceInfo()
		local flag = (difficulty and not ns.Secret(difficulty) and difficulty ~= "") and difficulty or nil
		if players and not ns.Secret(players) and players > 0 then
			flag = (flag and (flag .. ", ") or "") .. players .. " players"
		end
		if flag then parts[#parts + 1] = "|cffe0c070" .. flag .. "|r" end
	end
	if opt.clock then parts[#parts + 1] = GameTime_GetTime and GameTime_GetTime(false) or date("%H:%M") end
	header.time:SetText(table.concat(parts, "   "))
end

-- ---------------------------------------------------------------------------------------
-- Markers and the trail, a few times a second

local function HidePins()
	for i = 1, MAX_MARKERS do markers[i]:Hide() end
	dots:Done()
	pinLayer.corpseLine:Hide()
end

local function Rotated(east, north, facing)
	-- With "rotate minimap" on, the map turns so that the way you face is up.
	local c, s = math.cos(facing), math.sin(facing)
	return east * c + north * s, -east * s + north * c
end

local labelX, labelY = {}, {} -- where this pass has put distance labels

local function DrawPins()
	local opt = Opt()
	local north, west, instance, facing = P.Here()
	if not north or not (C_Minimap and C_Minimap.GetViewRadius) then
		HidePins()
		return
	end
	local radius = C_Minimap.GetViewRadius()
	if not radius or ns.Secret(radius) or radius <= 0 then
		HidePins()
		return
	end
	local half = Minimap:GetWidth() / 2
	local k = half / radius
	local turn = GetCVar and GetCVar("rotateMinimap") == "1"
	local square = shape == "SQUARE"

	-- The trail
	if opt.trail then
		local trail = P.trail
		local n = #trail / 2
		local first = math.max(1, n - MAX_DOTS + 1)
		for i = first, n do
			local east, up = -(trail[i * 2] - west) * k, (trail[i * 2 - 1] - north) * k
			if turn then east, up = Rotated(east, up, facing) end
			local inside
			if square then
				inside = math.abs(east) < half - 6 and math.abs(up) < half - 6
			else
				inside = east * east + up * up < (half - 8) * (half - 8)
			end
			-- Not under the player's own arrow.
			if inside and east * east + up * up > 64 then
				local dot = dots:Get()
				dot:SetSize(5, 5)
				dot:SetPoint("CENTER", pinLayer, "CENTER", east, up)
				dot:SetVertexColor(1, 0.91, 0.67, 0.15 + 0.7 * ((i - first + 1) / (n - first + 1)))
			end
		end
	end
	dots:Done()

	-- Things off the map, on its rim with their distance
	local used, labels = 0, 0
	local dead = opt.deathView and UnitIsDeadOrGhost("player")
	local corpseLine = false
	art.ghost:SetShown(dead and true or false)
	if opt.markers or dead then
		local list, count = P.Targets(north, west, instance)
		for i = 1, count do
			local t = list[i]
			-- With the rim markers off, the death view still shows the way to the corpse.
			if not opt.markers and t.kind ~= "corpse" then t = nil end
			local east, up = 0, 0
			if t then east, up = P.Offset(t, north, west) end
			local yards = math.sqrt(east * east + up * up)
			east, up = east * k, up * k
			if turn then east, up = Rotated(east, up, facing) end
			local reach = square and math.max(math.abs(east), math.abs(up)) or math.sqrt(east * east + up * up)
			local limit = half - (square and 9 or 7)
			local onRim = reach > limit
			-- Inside the map the game (or Questie) draws party dots and quests itself.
			if t and (onRim or t.kind == "corpse" or t.kind == "flag" or t.kind == "ping") and used < MAX_MARKERS and yards > 1 then
				used = used + 1
				local m = markers[used]
				P.DressMarker(m, t, onRim)
				P.Pulse(m, t.kind == "ping")
				m.name:Hide()
				if onRim then
					local f = limit / reach
					east, up = east * f, up * f
					m.icon:SetRotation(math.atan2(-east, up))
					local len = math.sqrt(east * east + up * up)
					-- The distance sits just inside the marker. Two things at nearly the same
					-- bearing would print over each other, so a label steps further in, one
					-- line at a time, until it is clear of those already placed.
					local lx, ly = east - east / len * 22, up - up / len * 14
					local step = up > 0 and -11 or 11
					local clear = false
					while not clear do
						clear = true
						for j = 1, labels do
							if math.abs(lx - labelX[j]) < 46 and math.abs(ly - labelY[j]) < 10 then
								ly = labelY[j] + step
								clear = false
							end
						end
					end
					labels = labels + 1
					labelX[labels], labelY[labels] = lx, ly
					m.text:ClearAllPoints()
					m.text:SetPoint("CENTER", pinLayer, "CENTER", lx, ly)
					m.text:SetText(P.Yards(yards))
					if t.kind == "party" and opt.rangeYards > 0 and yards <= opt.rangeYards then
						m.text:SetTextColor(0.45, 1, 0.45) -- within your reach
					end
					m.text:SetShown(opt.markerYards)
				else
					m.icon:SetRotation(0)
					m.text:Hide()
				end
				m:ClearAllPoints()
				m:SetPoint("CENTER", pinLayer, "CENTER", east, up)
				m:Show()
				if dead and t.kind == "corpse" then
					-- The death view's gold line home, and the distance even when it is near.
					corpseLine = true
					pinLayer.corpseLine:SetStartPoint("CENTER", pinLayer, 0, 0)
					pinLayer.corpseLine:SetEndPoint("CENTER", pinLayer, east, up)
					if not onRim then
						m.text:ClearAllPoints()
						m.text:SetPoint("TOP", m, "BOTTOM", 0, -1)
						m.text:SetText(P.Yards(yards))
						m.text:SetTextColor(1, 0.81, 0.33)
						m.text:Show()
					end
				end
			end
		end
	end
	pinLayer.corpseLine:SetShown(corpseLine)
	for i = used + 1, MAX_MARKERS do markers[i]:Hide() end
end

local function OnUpdate(self, elapsed)
	self.pinWait = (self.pinWait or 0) + elapsed
	if self.pinWait >= 0.07 then
		self.pinWait = 0
		local ok, err = pcall(DrawPins)
		if not ok then
			HidePins()
			if not self.pinError then
				self.pinError = true
				if ns.LogError then ns.LogError("map pins", tostring(err)) end
			end
		end
	end
	self.textWait = (self.textWait or 0) + elapsed
	if self.textWait >= 1 then
		self.textWait = 0
		Map.UpdateText()
		Map.UpdateAlpha() -- catches the switch into and out of a city's interior
		Map.UpdateZoom() -- and mounting up, stepping indoors
	end
	-- Buttons set to show on mouseover: there, but unseen, until the mouse is on the map or
	-- on them. While frames are unlocked they stay up so they can be placed.
	self.hoverWait = (self.hoverWait or 0) + elapsed
	if self.hoverWait >= 0.1 then
		self.hoverWait = 0
		local hide = Opt().buttons.show == "hover" and ns.DB().locked
			and not (holder:IsMouseOver() or bar:IsMouseOver() or drawer:IsShown() or QueueShowing())
		local alpha = bar:GetAlpha()
		local want = hide and 0 or 1
		if alpha ~= want then
			-- A short fade either way.
			bar:SetAlpha(math.max(0, math.min(1, alpha + (want > alpha and 0.34 or -0.34))))
		end
	end
end

-- ---------------------------------------------------------------------------------------

function Map.UpdateMovers(unlocked)
	if not Map.mover then return end
	local on = unlocked and taken and Style() ~= "blizzard" and not Map.lent
	Map.mover:SetShown(on and true or false)
	if Map.barMover then
		Map.barMover:SetShown(on and Opt().buttons.side == "free" and bar:IsShown() and true or false)
	end
end

function Map.ResetButtons()
	local b = Opt().buttons
	b.moved, b.mx, b.my, b.x, b.y = false, 0, 0, 0, 0
	ns.Refresh()
end

function Map.ResetPosition()
	local opt = Opt()
	opt.moved, opt.mx, opt.my = false, 0, 0
	ns.Refresh()
end

StaticPopupDialogs["SANCTUARYUI_MAP_RELOAD"] = {
	text = "Giving the minimap back to the game needs a reload.",
	button1 = "Reload now",
	button2 = "Later",
	OnAccept = function() ReloadUI() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

function Map.ApplySettings()
	if not holder then return end
	local style = Style()
	if style ~= "blizzard" and not taken then
		if TakeOver() then
			Collect()
		else
			Map.waiting = true -- in combat: PLAYER_REGEN_ENABLED tries again
		end
	elseif style == "blizzard" and taken and not Map.askedReload then
		Map.askedReload = true
		StaticPopup_Show("SANCTUARYUI_MAP_RELOAD")
	end
	if taken and Opt().drawer then Collect() end
	Map.Layout()
	Map.UpdateZoom(true)
end

function Map.Init()
	if not Minimap or holder then return end
	Build()
	P.Init()
	holder:SetScript("OnUpdate", OnUpdate)
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "PLAYER_REGEN_ENABLED", "UPDATE_PENDING_MAIL", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED",
		"ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "MINIMAP_UPDATE_ZOOM" }) do
		events:RegisterEvent(event)
	end
	events:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_REGEN_ENABLED" then
			if Map.waiting then
				Map.waiting = nil
				Map.ApplySettings()
			end
		elseif event == "UPDATE_PENDING_MAIL" or event == "PLAYER_ENTERING_WORLD" then
			-- Other addons' buttons may have arrived since the last look.
			if taken then
				Collect()
				Map.Layout()
			end
		else
			Map.UpdateText()
			Map.UpdateAlpha()
		end
	end)
	-- Addons that make their button late, after the first look.
	for _, wait in ipairs({ 2, 8 }) do
		C_Timer.After(wait, function()
			if taken then
				Collect()
				Map.UpdateAlpha()
			end
		end)
	end
end
