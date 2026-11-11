-- The overlay map: a see-through map across the middle of the screen, centred on you, that
-- you play through. Hold its key to look and let go to put it away (or tap to toggle).
--
-- Two ways to draw it, the player's choice:
--   ink   the zone's own map art, drawn here: ghosted over the world, the whole zone in reach,
--         ground you have explored brighter than the rest
--   live  the real minimap, enlarged and faded: shows what the minimap shows (nodes, people)
-- Inside a dungeon the client gives no zone map and no position, so ink falls back to live.
--
-- Everything is mouse-transparent and nothing here is protected, so it opens in combat.
SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI

ns.MapOverlay = {}
local O = ns.MapOverlay
local P = ns.MapPins

BINDING_NAME_SANCTUARYUIMAP = "Overlay map"

local MAX_MARKERS = 14
local MAX_DOTS = 160
local MARKER = 20

local frame, canvas, mask, pinLayer, arrow, title, note
local tiles, pieces = {}, {} -- base art and explored art textures
local markers, lines, dots = {}, {}, nil
local shownMap -- the map the canvas holds
local cal -- that map's world edges: north0, north1, west0, west1, and its art size
local mode -- "ink" or "live" while open
local lent -- what the minimap looked like before the live overlay borrowed it

local function Opt()
	return ns.DB().map.overlay
end

local function Viewport()
	return UIParent:GetHeight() * Opt().size
end

-- ---------------------------------------------------------------------------------------
-- Ink: the zone's art

local function Texture(pool, index, layer)
	local t = pool[index]
	if not t then
		t = canvas:CreateTexture(nil, "ARTWORK", nil, layer)
		t:AddMaskTexture(mask)
		pool[index] = t
	end
	return t
end

local function Look(texture, strength)
	local opt = Opt()
	if opt.look == "painted" then
		texture:SetDesaturated(false)
		texture:SetBlendMode("BLEND")
		texture:SetVertexColor(1, 1, 1, opt.opacity * strength)
	else
		-- Ghosted: grey, tinted like old paper and added to the world, so dark paint vanishes
		-- and only the light of the map lies over the ground.
		texture:SetDesaturated(true)
		texture:SetBlendMode("ADD")
		texture:SetVertexColor(0.86, 0.78, 0.60, opt.opacity * strength)
	end
end

local function Restyle()
	for _, t in ipairs(tiles) do if t:IsShown() then Look(t, t.strength) end end
	for _, t in ipairs(pieces) do if t:IsShown() then Look(t, t.strength) end end
end

-- Lay a map's art on the canvas. Returns false when this place has no map to draw.
local function LoadMap(mapID)
	if mapID == shownMap then return cal ~= nil end
	shownMap, cal = mapID, nil
	for _, t in ipairs(tiles) do t:Hide() end
	for _, t in ipairs(pieces) do t:Hide() end
	if not mapID then return false end
	local okL, layers = pcall(C_Map.GetMapArtLayers, mapID)
	local okT, files = pcall(C_Map.GetMapArtLayerTextures, mapID, 1)
	local layer = okL and type(layers) == "table" and layers[1]
	if not layer or not okT or type(files) ~= "table" or #files == 0 then return false end
	local n0, w0 = P.WorldOf(mapID, 0, 0)
	local n1, w1 = P.WorldOf(mapID, 1, 1)
	if not n0 or not n1 or n0 == n1 or w0 == w1 then return false end
	local W, H, tw, th = layer.layerWidth, layer.layerHeight, layer.tileWidth, layer.tileHeight
	local cols, rows = math.ceil(W / tw), math.ceil(H / th)
	canvas:SetSize(W, H)

	-- Unexplored ground shows in the base art; the explored pieces lie over it. In the ghost
	-- look both add up, so explored ground reads brighter.
	local explored = C_MapExplorationInfo and C_MapExplorationInfo.GetExploredMapTextures
		and select(2, pcall(C_MapExplorationInfo.GetExploredMapTextures, mapID))
	local hasPieces = type(explored) == "table" and #explored > 0
	local index = 0
	for row = 1, rows do
		for col = 1, cols do
			index = index + 1
			local file = files[index]
			if file then
				local t = Texture(tiles, index, 0)
				t:SetTexture(file)
				t:SetTexCoord(0, 1, 0, 1)
				t:SetSize(tw, th)
				t:ClearAllPoints()
				t:SetPoint("TOPLEFT", canvas, "TOPLEFT", (col - 1) * tw, -(row - 1) * th)
				t.strength = hasPieces and 0.5 or 1
				t:Show()
			end
		end
	end
	local used = 0
	if hasPieces then
		for _, info in ipairs(explored) do
			local wide, tall = math.ceil(info.textureWidth / tw), math.ceil(info.textureHeight / th)
			for j = 1, tall do
				local ph, fh = th, th
				if j == tall then
					ph = info.textureHeight % th
					if ph == 0 then ph = th end
					fh = 16
					while fh < ph do fh = fh * 2 end
				end
				for k = 1, wide do
					local pw, fw = tw, tw
					if k == wide then
						pw = info.textureWidth % tw
						if pw == 0 then pw = tw end
						fw = 16
						while fw < pw do fw = fw * 2 end
					end
					local file = info.fileDataIDs and info.fileDataIDs[(j - 1) * wide + k]
					if file then
						used = used + 1
						local t = Texture(pieces, used, 1)
						t:SetTexture(file)
						t:SetTexCoord(0, pw / fw, 0, ph / fh)
						t:SetSize(pw, ph)
						t:ClearAllPoints()
						t:SetPoint("TOPLEFT", canvas, "TOPLEFT", info.offsetX + (k - 1) * tw, -(info.offsetY + (j - 1) * th))
						t.strength = 0.75
						t:Show()
					end
				end
			end
		end
	end
	cal = { n0 = n0, n1 = n1, w0 = w0, w1 = w1, W = W, H = H }
	Restyle()
	return true
end

-- ---------------------------------------------------------------------------------------
-- Live: the real minimap, borrowed

local function Borrow()
	if lent or not Minimap then return end
	lent = { parent = Minimap:GetParent(), w = Minimap:GetWidth(), h = Minimap:GetHeight(), alpha = Minimap:GetAlpha(),
		zoom = Minimap:GetZoom(), strata = Minimap:GetFrameStrata(), level = Minimap:GetFrameLevel(),
		mouse = Minimap:IsMouseEnabled(), points = {} }
	for i = 1, Minimap:GetNumPoints() do lent.points[i] = { Minimap:GetPoint(i) } end
	ns.Map.lent = true
	if ns.Map.holder then ns.Map.holder:Hide() end
	local size = Viewport()
	Minimap:SetParent(frame)
	Minimap:SetFrameStrata("BACKGROUND")
	Minimap:SetFrameLevel(1)
	Minimap:ClearAllPoints()
	Minimap:SetPoint("CENTER", frame, "CENTER")
	Minimap:SetSize(size, size)
	Minimap:SetMaskTexture(ns.Map.MaskFor("fade"))
	Minimap:EnableMouse(false)
	ns.Map.SetMapAlpha(Opt().opacity) -- solid in a city's interior: see Map.UpdateAlpha
end

local function GiveBack()
	if not lent then return end
	local was = lent
	lent = nil
	Minimap:SetParent(was.parent)
	Minimap:SetFrameStrata(was.strata)
	Minimap:SetFrameLevel(was.level)
	Minimap:EnableMouse(was.mouse)
	Minimap:SetAlpha(was.alpha)
	Minimap:SetSize(was.w, was.h)
	ns.Map.lent = nil
	if ns.Map.Active() then
		ns.Map.applied = nil -- the overlay changed the size and mask behind its back
		ns.Map.Layout() -- puts the mask, size and anchor back for the style in use
	else
		Minimap:ClearAllPoints()
		for _, p in ipairs(was.points) do Minimap:SetPoint(unpack(p)) end
		Minimap:SetMaskTexture(ns.Map.MaskFor("globe"))
	end
end

-- ---------------------------------------------------------------------------------------
-- Pins

local function Line(index)
	local l = lines[index]
	if not l then
		l = pinLayer:CreateLine(nil, "BACKGROUND")
		l:SetThickness(3)
		lines[index] = l
	end
	return l
end

local function HidePins()
	for i = 1, MAX_MARKERS do markers[i]:Hide() end
	for _, l in ipairs(lines) do l:Hide() end
	dots:Done()
	arrow:Hide()
end

local function Rotated(east, north, facing)
	local c, s = math.cos(facing), math.sin(facing)
	return east * c + north * s, -east * s + north * c
end

-- k: screen units per yard. turn: the live map rotates with the player.
local function DrawPins(north, west, instance, facing, k, turn)
	local opt = Opt()
	local mapOpt = ns.DB().map
	local half = Viewport() / 2
	local limit = half * 0.80 -- the fade starts about here

	arrow:SetShown(mode == "ink") -- the live minimap draws its own
	arrow:SetRotation(facing)

	if mapOpt.trail then
		local trail = P.trail
		local n = #trail / 2
		local first = math.max(1, n - MAX_DOTS + 1)
		for i = first, n do
			local east, up = -(trail[i * 2] - west) * k, (trail[i * 2 - 1] - north) * k
			if turn then east, up = Rotated(east, up, facing) end
			local far = east * east + up * up
			if far < limit * limit and far > 144 then
				local dot = dots:Get()
				dot:SetSize(6, 6)
				dot:SetPoint("CENTER", pinLayer, "CENTER", east, up)
				dot:SetVertexColor(1, 0.91, 0.67, 0.2 + 0.7 * ((i - first + 1) / (n - first + 1)))
			end
		end
	end
	dots:Done()

	local list, count = P.Targets(north, west, instance)
	local used, usedLines = 0, 0
	for i = 1, count do
		if used >= MAX_MARKERS then break end
		local t = list[i]
		local east, up = P.Offset(t, north, west)
		local yards = math.sqrt(east * east + up * up)
		east, up = east * k, up * k
		if turn then east, up = Rotated(east, up, facing) end
		local reach = math.sqrt(east * east + up * up)
		local onRim = reach > limit
		if yards > 1 then
			used = used + 1
			local m = markers[used]
			P.DressMarker(m, t, onRim)
			if onRim then
				local f = limit / reach
				east, up = east * f, up * f
				m.icon:SetRotation(math.atan2(-east, up))
			else
				m.icon:SetRotation(0)
			end
			m:ClearAllPoints()
			m:SetPoint("CENTER", pinLayer, "CENTER", east, up)
			m.name:ClearAllPoints()
			m.text:ClearAllPoints()
			if opt.names and t.name then
				m.name:SetPoint("LEFT", m, "RIGHT", 4, 6)
				m.name:SetText(t.name)
				m.name:Show()
				m.text:SetPoint("LEFT", m, "RIGHT", 4, -7)
			else
				m.name:Hide()
				m.text:SetPoint("LEFT", m, "RIGHT", 4, 0)
			end
			m.text:SetText(P.Yards(yards))
			if t.kind == "party" and mapOpt.rangeYards > 0 and yards <= mapOpt.rangeYards then
				m.text:SetTextColor(0.45, 1, 0.45) -- within your reach
			else
				m.text:SetTextColor(0.91, 0.87, 0.77)
			end
			m:Show()
			-- A thread to a group member who has fallen behind.
			if t.kind == "party" and opt.tether > 0 and yards >= opt.tether then
				usedLines = usedLines + 1
				local l = Line(usedLines)
				l:SetStartPoint("CENTER", pinLayer, 0, 0)
				l:SetEndPoint("CENTER", pinLayer, east, up)
				l:SetColorTexture(t.color[1], t.color[2], t.color[3], 0.75)
				l:Show()
			end
		end
	end
	for i = used + 1, MAX_MARKERS do markers[i]:Hide() end
	for i = usedLines + 1, #lines do lines[i]:Hide() end
end

-- ---------------------------------------------------------------------------------------

local function Draw()
	local opt = Opt()
	local north, west, instance, facing = P.Here()
	local size = Viewport()
	local want = opt.mode
	local mapID = north and P.MapID()
	if want == "ink" and not (north and LoadMap(mapID)) then want = "live" end

	if want ~= mode then
		mode = want
		canvas:SetShown(mode == "ink")
		if mode == "live" then Borrow() else GiveBack() end
		note:SetShown(mode == "live" and opt.mode == "ink")
	end

	local zone = GetRealZoneText and GetRealZoneText() or ""
	title:SetText(ns.Secret(zone) and "" or zone:upper())

	if mode == "ink" then
		local k = size / opt.reach -- screen units per yard
		local worldWide = math.abs(cal.w1 - cal.w0)
		canvas:SetScale(k * worldWide / cal.W)
		local x = (cal.w0 - west) / (cal.w0 - cal.w1)
		local y = (cal.n0 - north) / (cal.n0 - cal.n1)
		canvas:ClearAllPoints()
		canvas:SetPoint("TOPLEFT", frame, "CENTER", -x * cal.W, y * cal.H)
		DrawPins(north, west, instance, facing, k, false)
	elseif north and C_Minimap and C_Minimap.GetViewRadius then
		local radius = C_Minimap.GetViewRadius()
		if radius and not ns.Secret(radius) and radius > 0 then
			DrawPins(north, west, instance, facing, (size / 2) / radius, GetCVar("rotateMinimap") == "1")
		else
			HidePins()
		end
	else
		HidePins() -- a dungeon: the minimap alone
	end
	if lent then ns.Map.SetMapAlpha(opt.opacity) end -- walking into or out of a city's interior
end

local function OnUpdate(self, elapsed)
	self.wait = (self.wait or 0) + elapsed
	if self.wait < 0.03 then return end
	self.wait = 0
	local ok, err = pcall(Draw)
	if not ok then
		HidePins()
		if not self.failed then
			self.failed = true
			if ns.LogError then ns.LogError("map overlay", tostring(err)) end
		end
	end
end

local function Build()
	frame = CreateFrame("Frame", "SanctuaryUIMapOverlay", UIParent)
	frame:SetFrameStrata("BACKGROUND")
	frame:SetFrameLevel(0)
	frame:EnableMouse(false)
	frame:Hide()

	canvas = CreateFrame("Frame", nil, frame)
	canvas:EnableMouse(false)
	mask = canvas:CreateMaskTexture()
	mask:SetTexture(ns.Art.Require("mapMaskFade") or "Interface\\CharacterFrame\\TempPortraitAlphaMask",
		"CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(frame)

	pinLayer = CreateFrame("Frame", nil, frame)
	pinLayer:SetFrameLevel(20)
	pinLayer:SetAllPoints(frame)
	pinLayer:EnableMouse(false)
	dots = P.DotPool(pinLayer, "ARTWORK")
	for i = 1, MAX_MARKERS do
		markers[i] = P.MakeMarker(pinLayer, MARKER)
		ns.Fonts.Set(markers[i].name, "body", 13, "OUTLINE")
		ns.Fonts.Set(markers[i].text, "body", 12, "OUTLINE")
		markers[i]:Hide()
	end
	arrow = pinLayer:CreateTexture(nil, "OVERLAY")
	arrow:SetSize(30, 30)
	arrow:SetPoint("CENTER")
	P.SetCell(arrow, "arrow")
	arrow:SetVertexColor(1, 0.96, 0.86)

	title = pinLayer:CreateFontString(nil, "OVERLAY")
	ns.Fonts.Set(title, "title", 22, "OUTLINE")
	title:SetTextColor(0.87, 0.75, 0.47)
	title:SetPoint("TOP", frame, "TOP", 0, -6)
	note = pinLayer:CreateFontString(nil, "OVERLAY")
	ns.Fonts.Set(note, "body", 12, "OUTLINE")
	note:SetTextColor(0.75, 0.72, 0.66)
	note:SetPoint("TOP", title, "BOTTOM", 0, -4)
	note:SetText("No zone map here: showing the minimap")
	note:Hide()

	frame:SetScript("OnUpdate", OnUpdate)
	frame:SetScript("OnHide", function()
		GiveBack()
		mode = nil
	end)
end

function O.Shown()
	return frame ~= nil and frame:IsShown()
end

function O.Show()
	if not frame then Build() end
	local size = Viewport()
	frame:SetSize(size, size)
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, Opt().offsetY)
	mode = nil
	frame.failed = nil
	canvas:Hide()
	frame:Show()
end

function O.Hide()
	if frame then frame:Hide() end
end

function O.Toggle()
	if O.Shown() then O.Hide() else O.Show() end
end

-- The key (Bindings.xml, run on press and on release).
function O.Key(keystate)
	if not ns.DB().map.overlay.enabled then return end
	if Opt().hold then
		if keystate == "down" then O.Show() else O.Hide() end
	elseif keystate == "down" then
		O.Toggle()
	end
end

function O.ApplySettings()
	if not frame then return end
	if not Opt().enabled then
		O.Hide()
		return
	end
	if frame:IsShown() then
		-- Size, reach and look take hold at once, so the options can be tuned with it open.
		local size = Viewport()
		frame:SetSize(size, size)
		frame:ClearAllPoints()
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, Opt().offsetY)
		Restyle()
		if lent then
			Minimap:SetSize(size, size)
			ns.Map.SetMapAlpha(Opt().opacity)
		end
	end
end
