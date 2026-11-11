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
local SOCKET_GAP = 4
local HEADER = 34 -- room for the name and the time above the map
local PLAQUE_H = 40
local RING = 128 / 100 -- the globe's art over its glass (tools/blender/minimap_ring.py)
local DRAWER_COLS = 4
local DRAWER_CELL = 34
local MARKER = 16
local MAX_MARKERS = 12
local MAX_DOTS = 70
local ROUND_MASK_ID = 186178 -- the client's own round mask, if ours is missing
local SQUARE_MASK_ID = 130937

local holder, mapBox, art, pinLayer, header, sockets, drawer, hidden
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

-- Zoom one step and back: makes the game draw the map afresh. See Map.UpdateAlpha for why.
local function Nudge()
	local zoom = Minimap:GetZoom()
	local top = (Minimap.GetZoomLevels and Minimap:GetZoomLevels() or 6) - 1
	Minimap:SetZoom(zoom > 0 and zoom - 1 or math.min(top, zoom + 1))
	Minimap:SetZoom(zoom)
end

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
	-- Other addons place their buttons by this.
	GetMinimapShape = function() return shape end
	taken = true
	return true
end

-- ---------------------------------------------------------------------------------------
-- Sockets: mail, tracking, calendar, the drawer

local function MakeSocket(key, cell, tip)
	local b = CreateFrame("Button", nil, holder)
	b:SetSize(SOCKET, SOCKET)
	b.sanctuarySocket = true
	local back = b:CreateTexture(nil, "BACKGROUND")
	local inset = ns.Art.SOCKET_INSET
	local fw, fh = SOCKET / (1 - inset.left - inset.right), SOCKET / (1 - inset.top - inset.bottom)
	back:SetPoint("TOPLEFT", -fw * inset.left, fh * inset.top)
	back:SetPoint("BOTTOMRIGHT", fw * inset.right, -fh * inset.bottom)
	if ns.Art.Apply(back, "socket") then
		back:SetTexCoord(unpack(ns.Art.SOCKET_TEXCOORD))
	else
		back:SetColorTexture(0.05, 0.05, 0.05, 0.9)
	end
	b.glyph = b:CreateTexture(nil, "ARTWORK")
	b.glyph:SetPoint("CENTER")
	b.glyph:SetSize(SOCKET - 8, SOCKET - 8)
	P.SetCell(b.glyph, cell)
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
	mapBox = CreateFrame("Frame", nil, holder)

	-- Above the map itself, under the things other addons pin on it.
	art = CreateFrame("Frame", nil, holder)
	art:SetFrameLevel(4)
	art:EnableMouse(false)
	art.tex = art:CreateTexture(nil, "ARTWORK")
	art.plaque = art:CreateTexture(nil, "BACKGROUND")

	pinLayer = CreateFrame("Frame", nil, holder)
	pinLayer:SetFrameLevel(40)
	pinLayer:EnableMouse(false)
	pinLayer:SetAllPoints(mapBox)
	dots = P.DotPool(pinLayer, "ARTWORK")
	for i = 1, MAX_MARKERS do
		markers[i] = P.MakeMarker(pinLayer, MARKER)
		markers[i]:Hide()
	end

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
	local more = MakeSocket("more", "more", function(tip)
		tip:AddLine("Addon buttons", 1, 0.82, 0.4)
	end)
	more:HookScript("OnEnter", OpenDrawer)
	more:SetScript("OnClick", function()
		if drawer:IsShown() then drawer:Hide() else OpenDrawer() end
	end)

	drawer = CreateFrame("Frame", nil, holder)
	drawer:SetFrameStrata("MEDIUM")
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

local function PlaceSockets(anchorFrame, point, relPoint, x, y, centred)
	local opt = Opt()
	local order = { "mail", "track", "calendar", "more" }
	local shown = {}
	for _, key in ipairs(order) do
		local b = sockets[key]
		local want = opt.sockets
		if key == "mail" then want = want and HasMail() end
		if key == "track" then want = want and b.blizzard ~= nil end
		if key == "more" then want = want and opt.drawer and (drawer.count or 0) > 0 end
		b:SetShown(want and true or false)
		if want then shown[#shown + 1] = b end
	end
	local width = #shown * SOCKET + math.max(0, #shown - 1) * SOCKET_GAP
	for i, b in ipairs(shown) do
		b:ClearAllPoints()
		local offset
		if centred then
			offset = -width / 2 + (i - 1) * (SOCKET + SOCKET_GAP)
			b:SetPoint("TOPLEFT", anchorFrame, relPoint, x + offset, y)
		else
			-- Right-aligned: the last socket ends at the anchor.
			offset = -(#shown - i) * (SOCKET + SOCKET_GAP)
			b:SetPoint(point, anchorFrame, relPoint, x + offset, y)
		end
	end
	sockets.mail.lit = HasMail()
	sockets.mail:Tint(false)
end

function Map.Layout()
	if not holder then return end
	local opt = Opt()
	local style = opt.style
	if style == "blizzard" or not taken then
		holder:SetShown(false)
		return
	end
	holder:SetShown(not Map.lent)
	local size = opt.size
	holder:SetScale(opt.scale)
	local showHead = opt.zone or opt.clock
	local socketRow = opt.sockets and (SOCKET + 8) or 0

	art.tex:ClearAllPoints()
	art.plaque:Hide()
	header.zone:ClearAllPoints()
	header.time:ClearAllPoints()
	mapBox:ClearAllPoints()
	mapBox:SetSize(size, size)

	if style == "globe" then
		shape = "ROUND"
		local full = size * RING
		local pad = (full - size) / 2
		local below = (showHead and (PLAQUE_H - 6) or 0) + socketRow
		holder:SetSize(full, full + below)
		mapBox:SetPoint("TOP", holder, "TOP", 0, -pad)
		art.tex:SetPoint("CENTER", mapBox, "CENTER")
		art.tex:SetSize(full, full)
		art.tex:SetTexture(ns.Art.Require("mapRing"))
		art.tex:Show()
		if showHead then
			art.plaque:SetTexture(ns.Art.Require("mapPlaque"))
			art.plaque:ClearAllPoints()
			art.plaque:SetSize(math.min(full, 210), PLAQUE_H)
			art.plaque:SetPoint("TOP", mapBox, "BOTTOM", 0, -pad + 8)
			art.plaque:Show()
			header.zone:SetPoint("CENTER", art.plaque, "CENTER", 0, opt.clock and 6 or 0)
			header.time:SetPoint("CENTER", art.plaque, "CENTER", 0, opt.zone and -8 or 0)
			header.zone:SetJustifyH("CENTER")
			header.zone:SetWidth(math.min(full, 210) - 20)
		end
		PlaceSockets(mapBox, "TOPLEFT", "BOTTOM", 0, -pad - (showHead and (PLAQUE_H - 6) or 0) - 6, true)
	else
		shape = style == "parchment" and "SQUARE" or "ROUND"
		local above = showHead and HEADER or 0
		holder:SetSize(size, above + size + socketRow)
		mapBox:SetPoint("TOP", holder, "TOP", 0, -above)
		if style == "parchment" then
			art.tex:SetAllPoints(mapBox)
			art.tex:SetTexture(ns.Art.Require("mapParchment"))
			art.tex:Show()
			header.zone:SetPoint("BOTTOMRIGHT", mapBox, "TOPRIGHT", -4, opt.clock and 17 or 4)
			header.time:SetPoint("BOTTOMRIGHT", mapBox, "TOPRIGHT", -4, 3)
			header.zone:SetJustifyH("RIGHT")
			PlaceSockets(mapBox, "TOPRIGHT", "BOTTOMRIGHT", 0, -6, false)
		else
			art.tex:Hide()
			header.zone:SetPoint("BOTTOM", mapBox, "TOP", 0, opt.clock and 15 or 2)
			header.time:SetPoint("BOTTOM", mapBox, "TOP", 0, 1)
			header.zone:SetJustifyH("CENTER")
			PlaceSockets(mapBox, "TOPLEFT", "BOTTOM", 0, -4, true)
		end
		header.zone:SetWidth(size + 60)
	end
	header.zone:SetShown(opt.zone)
	header.time:SetShown(opt.clock)

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
		if set.size ~= size then
			set.size = size
			Minimap:SetSize(size, size)
		end
		if set.mask ~= mask then
			set.mask = mask
			Minimap:SetMaskTexture(mask)
		end
		Map.UpdateAlpha()
		AnchorMinimap()
	end
	Map.UpdateText()
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
	if alpha == 1 and not Map.nudging then
		Map.nudging = true -- the nudge fires the zoom event that brings us back here
		Nudge()
		Map.nudging = nil
	end
end

function Map.UpdateAlpha()
	if not taken or Map.lent then return end
	Map.SetMapAlpha(Opt().opacity)
end

function Map.UpdateText()
	if not header then return end
	local zone = GetMinimapZoneText and GetMinimapZoneText() or ""
	if ns.Secret(zone) then zone = "" end
	header.zone:SetText(zone:upper())
	local now = GameTime_GetTime and GameTime_GetTime(false) or date("%H:%M")
	local area = GetRealZoneText and GetRealZoneText() or ""
	if ns.Secret(area) then area = "" end
	if Opt().zone and area ~= "" and area ~= zone then
		header.time:SetText(area .. "   " .. now)
	else
		header.time:SetText(now)
	end
end

-- ---------------------------------------------------------------------------------------
-- Markers and the trail, a few times a second

local function HidePins()
	for i = 1, MAX_MARKERS do markers[i]:Hide() end
	dots:Done()
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
	if opt.markers then
		local list, count = P.Targets(north, west, instance)
		for i = 1, count do
			local t = list[i]
			local east, up = P.Offset(t, north, west)
			local yards = math.sqrt(east * east + up * up)
			east, up = east * k, up * k
			if turn then east, up = Rotated(east, up, facing) end
			local reach = square and math.max(math.abs(east), math.abs(up)) or math.sqrt(east * east + up * up)
			local limit = half - (square and 9 or 7)
			local onRim = reach > limit
			-- Inside the map the game (or Questie) draws party dots and quests itself.
			if (onRim or t.kind == "corpse" or t.kind == "flag") and used < MAX_MARKERS and yards > 1 then
				used = used + 1
				local m = markers[used]
				P.DressMarker(m, t, onRim)
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
			end
		end
	end
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
		-- The borderless style keeps its sockets out of sight until the mouse comes near.
		local hide = Style() == "fade" and not holder:IsMouseOver() and not drawer:IsShown()
		for _, b in pairs(sockets) do b:SetAlpha(hide and 0 or 1) end
	end
end

-- ---------------------------------------------------------------------------------------

function Map.UpdateMovers(unlocked)
	if not Map.mover then return end
	Map.mover:SetShown(unlocked and taken and Style() ~= "blizzard" and not Map.lent)
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
