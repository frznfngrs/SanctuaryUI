SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.MiningMap = ns.MiningMap or {}
local MM = ns.MiningMap

-- Rock Bottom's pins: the veins the book knows (MiningNodes.lua) and the ones you found
-- yourself, on the world map and the minimap.
--
-- World map: a zone's map gets a pin on every known spot of the veins you want (by default
-- the ones that still teach you), ringed in the vein's skill colour; a continent gets one pin
-- per zone with the count, which zooms in on a click. "Show on the world map" in the book
-- focuses one vein (every zone, a banner to clear it).
--
-- Minimap: the same veins within the minimap's reach, placed by world position (yards) like
-- the ally ring and the corner map's markers, turning with "rotate minimap". Pins close to you
-- fade, so the game's own Find Minerals dot shows through: a faded pin with no yellow dot on it
-- is a vein somebody got to first.
--
-- Positions come from C_Map.GetWorldPosFromMapPos (cached per map) and UnitPosition, which
-- this client gives in the open world only; inside instances the minimap pins stand down.

local Book = ns.Book
local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local WHITE = "Interface\\Buttons\\WHITE8x8"
local CONTINENT = Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2
local MAX_MINI = 80
local TICK = 0.1

local RING = {
	orange = { 1, 0.5, 0.15 }, yellow = { 1, 0.86, 0.2 }, green = { 0.35, 0.9, 0.3 }, grey = { 0.62, 0.62, 0.62 },
	open = { 0.95, 0.72, 0.32 }, locked = { 0.85, 0.2, 0.15 }, find = { 1, 0.82, 0.33 }, heard = { 0.45, 0.72, 1 },
}

local function Opt() return ns.DB().mining.pins end
local function D() return ns.MiningData end
local function M() return ns.Mining end

local function Readable(v) return v ~= nil and not ns.Secret(v) end

local focus -- a vein key the book asked to show, or nil
local peek -- the book asked for a zone's veins while world map pins are off

-- Should this vein have pins? rank is your Mining skill (nil if you don't mine).
local function Wanted(v, rank)
	if focus then return v.key == focus end
	if D().GHOST[v.key] then return false end
	local mode = Opt().show
	if mode == "all" then return true end
	if not rank then return false end
	local colour = M().Colour(v, rank)
	if colour == "locked" then return false end
	if mode == "mine" then return true end
	return colour ~= "grey"
end

local function RingOf(v, rank)
	local colour = rank and M().Colour(v, rank)
	return RING[colour] or RING.open, colour
end

-- The pin tooltip: the vein, what it is to you, where the spot came from, what it gives.
local function Tip(owner, v, rank, extra)
	local ring, colour = RingOf(v, rank)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetText(v.name, ring[1], ring[2], ring[3])
	local diff = colour and M().DIFF[colour]
	GameTooltip:AddLine(("Mining %d%s"):format(v.skill, diff and (": " .. diff[2]) or ""), 1, 0.82, 0.45)
	if extra then GameTooltip:AddLine(extra, 0.9, 0.86, 0.78, true) end
	local y = D().YIELD[v.key]
	if y and y.gives then GameTooltip:AddLine(y.gives, 0.75, 0.72, 0.65, true) end
end

-- A round pin: a disc in the ring colour with the ore's icon inside.
local function MakePin(parent)
	local pin = CreateFrame("Button", nil, parent)
	pin.disc = pin:CreateTexture(nil, "ARTWORK")
	pin.disc:SetAllPoints()
	pin.disc:SetTexture(WHITE)
	pin.disc:SetMask(MASK)
	pin.icon = pin:CreateTexture(nil, "OVERLAY")
	pin.icon:SetPoint("TOPLEFT", 1.5, -1.5)
	pin.icon:SetPoint("BOTTOMRIGHT", -1.5, 1.5)
	pin.icon:SetMask(MASK)
	pin.count = pin:CreateFontString(nil, "OVERLAY")
	ns.Fonts.Set(pin.count, "body", 11, "OUTLINE")
	pin.count:SetPoint("TOP", pin, "BOTTOM", 0, -1)
	pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return pin
end

-- find: true for your own finds (gold), "heard" for other miners' (blue).
local function Dress(pin, v, rank, size, find)
	local ring = find == "heard" and RING.heard or find and RING.find or RingOf(v, rank)
	pin:SetSize(size, size)
	pin.disc:SetVertexColor(ring[1], ring[2], ring[3], 1)
	pin.icon:SetTexture(M().OreIcon(v.key))
	pin.count:SetText("")
end

---------------------------------------------------------------------------
-- The world map.

local overlay, banner, hooked
local pins, used = {}, 0
local placed = {} -- this draw's pins: { x, y } on the canvas, 0-1

local function Canvas()
	return WorldMapFrame and WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas()
end

local function Pin()
	used = used + 1
	local pin = pins[used]
	if not pin then
		pin = MakePin(overlay)
		pins[used] = pin
	end
	pin:SetScript("OnEnter", function(self) if self.tip then self.tip(self) end end)
	pin:SetScript("OnClick", nil)
	pin:Show()
	return pin
end

-- Pins keep their size on screen as the map zooms: placed again when the canvas changes.
local lastW, lastH, lastScale
local function Place()
	local canvas = Canvas()
	if not canvas then return end
	local w, h, scale = canvas:GetWidth(), canvas:GetHeight(), canvas:GetScale()
	lastW, lastH, lastScale = w, h, scale
	local k = 1 / math.max(scale, 0.05)
	for i = 1, used do
		local pin, at = pins[i], placed[i]
		pin:SetScale(k)
		pin:ClearAllPoints()
		pin:SetPoint("CENTER", overlay, "TOPLEFT", at[1] * w / k, -at[2] * h / k)
	end
end

local function ContinentOf(mapID)
	for _ = 1, 8 do
		local info = mapID and C_Map.GetMapInfo(mapID)
		if not info then return end
		if info.mapType == CONTINENT then return info.mapID end
		if info.mapType < CONTINENT then return end
		mapID = info.parentMapID
	end
end

local function Log()
	return M().Log and M().Log()
end

-- Other miners' finds, when they're to be shown.
local function HeardList()
	local share = ns.DB().mining.share
	if not (share and share.show and ns.MiningShare) then return {} end
	return ns.MiningShare.Heard()
end

local function HeardLine(h)
	local n = h.n or 1
	return n > 1 and ("Found by %d other miners; the maps didn't have it."):format(n) or "Another miner found it; the maps didn't have it."
end

local Draw

local function Banner()
	if banner then return banner end
	local parent = WorldMapFrame.ScrollContainer or WorldMapFrame
	banner = CreateFrame("Frame", nil, parent)
	banner:SetFrameLevel(parent:GetFrameLevel() + 2500)
	banner:SetPoint("TOP", parent, "TOP", 0, -6)
	banner:SetHeight(26)
	local bg = banner:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.05, 0.03, 0.02, 0.82)
	local edge = banner:CreateTexture(nil, "BORDER")
	edge:SetPoint("BOTTOMLEFT")
	edge:SetPoint("BOTTOMRIGHT")
	edge:SetHeight(1)
	edge:SetColorTexture(0.62, 0.42, 0.06, 0.9)
	banner.text = banner:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	banner.text:SetPoint("LEFT", 10, 0)
	banner.close = CreateFrame("Button", nil, banner, "UIPanelCloseButton")
	banner.close:SetSize(22, 22)
	banner.close:SetPoint("RIGHT", -2, 0)
	banner.close:SetScript("OnClick", function() MM.Clear() end)
	return banner
end

-- A zone's own map: a pin on each spot.
local function DrawZone(shownID, rank)
	local d = D()
	local size = Opt().worldSize
	local zone = d.MAPS[shownID]
	for _, v in ipairs(d.VEINS) do
		if Wanted(v, rank) then
			for _, spot in ipairs(M().Spots(v.key, shownID)) do
				local pin = Pin()
				Dress(pin, v, rank, size)
				placed[used] = spot
				pin.tip = function(self)
					Tip(self, v, rank, "Known spot in " .. zone .. ".")
					GameTooltip:Show()
				end
				pin:SetScript("OnClick", function() M().Open("veins") M().Jump("veins", "vein:" .. v.key) end)
			end
		end
	end
	-- Your own finds, ringed in gold.
	local log = Log()
	if Opt().finds and log then
		for _, f in ipairs(log.finds) do
			local v = f[2] == shownID and M().Vein(f[1])
			if v and (Wanted(v, rank) or not focus) then
				local pin = Pin()
				Dress(pin, v, rank, size + 2, true)
				placed[used] = { f[3], f[4] }
				pin.tip = function(self)
					Tip(self, v, rank, ("Your find, %s. The maps didn't have it."):format(date("%d %b", f[5])))
					GameTooltip:Show()
				end
			end
		end
	end
	-- Other miners' finds, ringed in blue.
	for _, h in ipairs(HeardList()) do
		local v = h[2] == shownID and M().Vein(h[1])
		if v and (Wanted(v, rank) or not focus) then
			local pin = Pin()
			Dress(pin, v, rank, size + 2, "heard")
			placed[used] = { h[3], h[4] }
			pin.tip = function(self)
				Tip(self, v, rank, HeardLine(h))
				GameTooltip:Show()
			end
		end
	end
end

-- A continent: one pin per zone, at the middle of its spots, with the count.
local function DrawContinent(shownID, rank)
	local d = D()
	for map, zone in pairs(d.MAPS) do
		local ok, left, right, top, bottom = pcall(C_Map.GetMapRectOnMap, map, shownID)
		if ok and left and right and right > left and bottom > top then
			local n, sx, sy, kinds, best = 0, 0, 0, {}, nil
			for _, v in ipairs(d.VEINS) do
				if Wanted(v, rank) then
					local spots = M().Spots(v.key, map)
					if #spots > 0 then
						kinds[#kinds + 1] = { v, #spots }
						if not best or #spots > best[2] then best = { v, #spots } end
						for _, s in ipairs(spots) do
							n, sx, sy = n + 1, sx + s[1], sy + s[2]
						end
					end
				end
			end
			if n > 0 then
				local pin = Pin()
				Dress(pin, best[1], rank, Opt().worldSize + 8)
				pin.count:SetText(tostring(n))
				placed[used] = { left + (right - left) * sx / n, top + (bottom - top) * sy / n }
				table.sort(kinds, function(a, b) return a[2] > b[2] end)
				pin.tip = function(self)
					GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
					GameTooltip:SetText(zone, 1, 0.82, 0.33)
					for _, e in ipairs(kinds) do
						local ring = RingOf(e[1], rank)
						GameTooltip:AddDoubleLine(e[1].name, tostring(e[2]), ring[1], ring[2], ring[3], 0.9, 0.86, 0.78)
					end
					GameTooltip:AddLine("Click to see every spot.", 0.6, 0.6, 0.6)
					GameTooltip:Show()
				end
				pin:SetScript("OnClick", function() WorldMapFrame:SetMapID(map) end)
			end
		end
	end
end

Draw = function()
	for i = 1, used do pins[i]:Hide() end
	used = 0
	wipe(placed)
	local on = Opt().world or focus or peek
	if not on or not WorldMapFrame or not WorldMapFrame:IsShown() then
		if banner then banner:Hide() end
		if overlay then overlay:Hide() end
		return
	end
	local canvas = Canvas()
	local shownID = WorldMapFrame:GetMapID()
	local info = shownID and C_Map.GetMapInfo(shownID)
	if not canvas or not info then return end
	if not overlay then
		overlay = CreateFrame("Frame", nil, canvas)
		overlay:SetAllPoints(canvas)
		overlay:SetScript("OnUpdate", function()
			local c = Canvas()
			if c and (c:GetWidth() ~= lastW or c:GetHeight() ~= lastH or c:GetScale() ~= lastScale) then Place() end
		end)
	end
	overlay:SetFrameLevel(canvas:GetFrameLevel() + 1400)
	overlay:Show()
	local rank = M().Skill()
	if focus then
		local v = M().Vein(focus)
		local b = Banner()
		b.text:SetText(("|cffd8b86aRock Bottom:|r every %s the maps know"):format(v and v.name or "vein"))
		b:SetWidth(10 + b.text:GetStringWidth() + 34)
		b:Show()
	elseif banner then
		banner:Hide()
	end
	if D().MAPS[shownID] then
		DrawZone(shownID, rank)
	elseif info.mapType == CONTINENT then
		DrawContinent(shownID, rank)
	end
	for i = 1, used do pins[i]:SetFrameLevel(overlay:GetFrameLevel() + 2 + (i % 400)) end
	Place()
end

local function Hook()
	if hooked or not WorldMapFrame then return end
	hooked = true
	hooksecurefunc(WorldMapFrame, "OnMapChanged", function() ns.Try("rock bottom map", Draw) end)
	WorldMapFrame:HookScript("OnShow", function() ns.Try("rock bottom map", Draw) end)
	-- A focus lasts while the map is open.
	WorldMapFrame:HookScript("OnHide", function() focus, peek = nil, nil end)
end

-- "Show on the world map" from the book: key focuses one vein (nil for whatever the settings
-- show), map is where to open (a zone, or nil for the continent you're on).
function MM.Show(key, map)
	if InCombatLockdown() then
		ns.Print("The map waits until the fight's over.")
		return
	end
	if not WorldMapFrame and C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_WorldMap") end
	if not WorldMapFrame then return end
	Hook()
	focus, peek = key, not key
	local target = map
	if key and not map then
		local zones = M().Zones(key)
		target = zones[1] and zones[1][1]
	end
	if not target then
		local here = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
		target = Readable(here) and here and ContinentOf(here) or nil
	end
	if not WorldMapFrame:IsShown() then
		if OpenWorldMap then OpenWorldMap(target) else ShowUIPanel(WorldMapFrame) end
	end
	if target and WorldMapFrame:GetMapID() ~= target then
		WorldMapFrame:SetMapID(target) -- draws, through the OnMapChanged hook
	else
		Draw()
	end
end

function MM.Clear()
	focus, peek = nil, nil
	Draw()
end

function MM.Redraw()
	if WorldMapFrame and WorldMapFrame:IsShown() then ns.Try("rock bottom map", Draw) end
end

---------------------------------------------------------------------------
-- The minimap.

local mini, miniPins, miniUsed = nil, {}, 0
local WORLD = {} -- map -> { { key, north, west, find } }, the spots in world yards
local BOX = {} -- map -> { continent, north1, north2, west1, west2 }, its corners in world yards
local elapsed, lastNorth, lastWest, lastFacing, lastRadius, lastKey = 0, nil, nil, nil, nil, nil

local function ToWorld(map, x, y)
	local ok, cont, pos = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x, y))
	if not ok or not pos or not pos.GetXY then return end
	local north, west = pos:GetXY()
	if Readable(north) and Readable(west) then return north, west, cont end
end

-- A map's extent in world yards, from two corners: cheap, so every map can be asked.
local function Box(map)
	local b = BOX[map]
	if b ~= nil then return b end
	BOX[map] = false
	if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return false end
	local n1, w1, cont = ToWorld(map, 0, 0)
	local n2, w2 = ToWorld(map, 1, 1)
	if not n1 or not n2 then return false end
	b = { cont, math.min(n1, n2), math.max(n1, n2), math.min(w1, w2), math.max(w1, w2) }
	BOX[map] = b
	return b
end

-- Every spot on a map, in world yards (north, west), worked out the first time you're near it.
local function World(map)
	local w = WORLD[map]
	if w then return w end
	local list = {}
	local function Add(key, x, y, find)
		local north, west = ToWorld(map, x, y)
		if north then list[#list + 1] = { key, north, west, find } end
	end
	for _, v in ipairs(D().VEINS) do
		if not D().GHOST[v.key] then
			for _, s in ipairs(M().Spots(v.key, map)) do Add(v.key, s[1], s[2]) end
		end
	end
	local log = Log()
	for _, f in ipairs(log and log.finds or {}) do
		if f[2] == map then Add(f[1], f[3], f[4], true) end
	end
	for _, h in ipairs(HeardList()) do
		if h[2] == map then Add(h[1], h[3], h[4], "heard") end
	end
	WORLD[map] = list
	return list
end

-- A new find goes onto the minimap at once.
function MM.Forget(map)
	if map then WORLD[map] = nil else wipe(WORLD) end
	lastKey = nil
	MM.Redraw()
end

local function MiniPin()
	miniUsed = miniUsed + 1
	local pin = miniPins[miniUsed]
	if not pin then
		pin = MakePin(mini)
		pin:SetScript("OnEnter", function(self)
			if not self.v then return end
			local whose = self.find == "heard" and "Another miner's find, " or self.find and "Your find, " or "Known spot, "
			Tip(self, self.v, self.rank, whose .. Book.Commas(self.yards) .. " yards away.")
			GameTooltip:Show()
		end)
		miniPins[miniUsed] = pin
	end
	pin:Show()
	return pin
end

local function Rotated(east, north, facing)
	local c, s = math.cos(facing), math.sin(facing)
	return east * c + north * s, -east * s + north * c
end

local function HideMini()
	for i = 1, #miniPins do miniPins[i]:Hide() end
	miniUsed = 0
end

local function DrawMini()
	local opt = Opt()
	if not opt.minimap or not Minimap or not Minimap:IsVisible() then return HideMini() end
	local north, west, _, instance = UnitPosition("player")
	if not Readable(north) or not Readable(west) then return HideMini() end
	if not (C_Minimap and C_Minimap.GetViewRadius) then return HideMini() end
	local radius = C_Minimap.GetViewRadius()
	if not Readable(radius) or radius <= 0 then return HideMini() end
	local facing = GetPlayerFacing and GetPlayerFacing() or 0
	if not Readable(facing) then facing = 0 end
	local turn = GetCVar and GetCVar("rotateMinimap") == "1"
	-- Only when something moved: you, the way you face (if the map turns), the zoom.
	local key = ("%d:%d:%.2f:%d:%s"):format(north, west, turn and facing or 0, radius, opt.show)
	if key == lastKey then return end
	lastKey = key
	miniUsed = 0
	local half = Minimap:GetWidth() / 2
	local k = half / radius
	local square = GetMinimapShape and GetMinimapShape() == "SQUARE"
	local size = opt.miniSize
	local edge = half - size / 2 - 1
	local rank = M().Skill()
	local near2 = opt.nearYards * opt.nearYards
	local reach = radius * 1.45
	local found = {}
	for map in pairs(D().MAPS) do
		local box = Box(map)
		if box and (instance == nil or box[1] == nil or box[1] == instance)
			and north > box[2] - reach and north < box[3] + reach and west > box[4] - reach and west < box[5] + reach then
			for _, s in ipairs(World(map)) do
				local dn, dw = s[2] - north, s[3] - west
				if dn > -reach and dn < reach and dw > -reach and dw < reach then
					local v = M().Vein(s[1])
					if v and (Wanted(v, rank) or (s[4] and opt.finds)) then
						found[#found + 1] = { v, -dw, dn, s[4] }
					end
				end
			end
		end
	end
	-- Nearest first, so a busy map keeps the ones that matter.
	table.sort(found, function(a, b) return a[2] * a[2] + a[3] * a[3] < b[2] * b[2] + b[3] * b[3] end)
	for _, f in ipairs(found) do
		if miniUsed >= MAX_MINI then break end
		local east, up = f[2] * k, f[3] * k
		if turn then east, up = Rotated(east, up, facing) end
		local inside
		if square then
			inside = math.abs(east) < edge and math.abs(up) < edge
		else
			inside = east * east + up * up < edge * edge
		end
		if inside then
			local d2 = f[2] * f[2] + f[3] * f[3]
			if not (opt.near == "hide" and d2 < near2) then
				local pin = MiniPin()
				Dress(pin, f[1], rank, size, f[4])
				pin.v, pin.rank, pin.find, pin.yards = f[1], rank, f[4], math.sqrt(d2)
				local faded = opt.near == "fade" and d2 < near2
				pin:SetAlpha(faded and 0.3 or 1)
				-- A faded pin lets the mouse through to the game's own dot under it.
				pin:EnableMouse(not faded)
				pin:ClearAllPoints()
				pin:SetPoint("CENTER", mini, "CENTER", east, up)
			end
		end
	end
	for i = miniUsed + 1, #miniPins do miniPins[i]:Hide() end
end

local function BuildMini()
	if mini or not Minimap then return end
	mini = CreateFrame("Frame", nil, Minimap)
	mini:SetAllPoints(Minimap)
	mini:SetFrameLevel(Minimap:GetFrameLevel() + 4)
	mini:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed < TICK then return end
		elapsed = 0
		ns.Try("rock bottom minimap", DrawMini)
	end)
end

function MM.ApplySettings()
	lastKey = nil
	wipe(WORLD) -- which finds show may have changed
	if mini then mini:SetShown(Opt().minimap) end
	if not Opt().minimap then HideMini() end
	MM.Redraw()
end

function MM.Init()
	BuildMini()
	if WorldMapFrame then Hook() end
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "ADDON_LOADED", "SKILL_LINES_CHANGED", "PLAYER_ENTERING_WORLD" }) do
		pcall(events.RegisterEvent, events, event)
	end
	events:SetScript("OnEvent", function(_, event, name)
		if event == "ADDON_LOADED" then
			if name == "Blizzard_WorldMap" then Hook() end
			return
		end
		-- A skill-up can change which veins still teach you.
		lastKey = nil
		MM.Redraw()
	end)
	MM.ApplySettings()
end
