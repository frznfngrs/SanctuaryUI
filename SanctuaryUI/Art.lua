SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI

ns.Art = ns.Art or {}

local ROOT = "Interface\\AddOns\\SanctuaryUI\\Art\\"
-- D3's title face, for names on the plates and globes.
ns.FONT = "Interface\\AddOns\\SanctuaryUI\\Media\\exocet.ttf"

-- Slots the prep script fills. Missing files fall back to flat color and game chrome.
ns.Art.slots = {
	frame = { file = "frame.png" },
	glass = { file = "glass.png" },
	liquid = { file = "liquid.png" },
	hotline = { file = "hotline.png" },
	xpOrange = { file = "xp-orange.png" },
	xpGold = { file = "xp-gold.png" },
	xpBlue = { file = "xp-blue.png" },
	xpWhite = { file = "xp-white.png" },
	menu = { file = "menu.png" },
	buttonGlow = { file = "button-glow.png" },
	socket = { file = "socket.png" },
	socketHover = { file = "socket-hover.png" },
	socketPress = { file = "socket-press.png" },
	blade = { file = "blade.png" },
	bagFrame = { file = "bag-frame.png" },
	bankFrame = { file = "bank-frame.png" },
	pips = { file = "pips.png" },
	pipHorn = { file = "pip-horn.png" },
	targetRings = { file = "target-rings.png" },
	-- The rendered target styles (ns.Art.TARGET_STYLES): lazy, only the style in use loads.
	targetStyleLintel = { file = "target-style-lintel.png", lazy = true },
	targetStyleSlim = { file = "target-style-slim.png", lazy = true },
	targetStyleBracket = { file = "target-style-bracket.png", lazy = true },
	targetStyleTablet = { file = "target-style-tablet.png", lazy = true },
	targetStyleParts = { file = "target-style-parts.png", lazy = true },
	pipSockets = { file = "pip-sockets.png" },
	liquidShimmer = { file = "liquid-shimmer.png" },
	bagCells = { file = "bag-cells.png" },
	d3Button = { file = "d3-button.png" },
	liquidLeft = { file = "liquid-left.png" },
	liquidRight = { file = "liquid-right.png" },
	liquidTile = { file = "liquid-tile.png" },
	liquidStreaks = { file = "liquid-streaks.png" },
	liquidWisps = { file = "liquid-wisps.png" },
	-- Rendered liquid (Liquid.lua FLIP): big sheets, so lazy: Probe skips them and only
	-- ns.Art.Require, when that style is on, ever touches them.
	liquidCalmBody = { file = "liquid-calm-body.png", lazy = true },
	liquidCalmLight = { file = "liquid-calm-light.png", lazy = true },
	liquidAgitatedBody = { file = "liquid-agitated-body.png", lazy = true },
	liquidAgitatedLight = { file = "liquid-agitated-light.png", lazy = true },
	-- Surge styles (GlobeAura.lua SURGE_ART): lazy too, loaded only for styles in use.
	surgeInhaleRays = { file = "surge-inhale-rays.png", lazy = true },
	surgeStreak = { file = "surge-streak.png", lazy = true },
	surgePourColumn = { file = "surge-pour-column.png", lazy = true },
	surgePourUnder = { file = "surge-pour-under.png", lazy = true },
	surgeUpwellBody = { file = "surge-upwell-body.png", lazy = true },
	surgeUpwellCore = { file = "surge-upwell-core.png", lazy = true },
	-- The rendered shield break (GlobeAura.lua BREAK): lazy the same way.
	shellShatter = { file = "shell-shatter.png", lazy = true },
	shellHit = { file = "shell-hit.png", lazy = true },
	pollutionPoisonMix = { file = "pollution-poison-mix.png", lazy = true },
	pollutionPoisonGlow = { file = "pollution-poison-glow.png", lazy = true },
	pollutionDiseaseMix = { file = "pollution-disease-mix.png", lazy = true },
	pollutionCurseMix = { file = "pollution-curse-mix.png", lazy = true },
	pollutionCurseGlow = { file = "pollution-curse-glow.png", lazy = true },
	pollutionMagicMix = { file = "pollution-magic-mix.png", lazy = true },
	pollutionMagicGlow = { file = "pollution-magic-glow.png", lazy = true },
	globeRim = { file = "globe-rim.png" },
	surfaceGlow = { file = "surface-glow.png" },
	surfaceShimmer = { file = "surface-shimmer.png" },
	mote = { file = "mote.png" },
	globeShade = { file = "globe-shade.png" },
	globeMask = { file = "globe-mask.png" },
	skillTimer = { file = "skill-timer.png" },
	menuFlyout = { file = "menu-flyout.png" },
	unitFrames = { file = "unit-frames.png" },
	unitFill = { file = "unit-fill.png" },
	unitFillWhite = { file = "unit-fill-white.png" },
	unitWell = { file = "unit-well.png" },
	unitGloss = { file = "unit-gloss.png" },
	unitGlow = { file = "unit-glow.png" }, -- bloom 0-18, core 32-50 of 64x32
	consoleBase = { file = "console-base.png" }, -- frame.png without the rail band
	consoleTiers = { file = "console-tiers.png" }, -- the band lifted over 1-2 rows (sheet x 200..1400, atlas y 0/208 of 512)
	levelMedallion = { file = "level-medallion.png" }, -- ring and red disc, 120 px across of 128
	levelPlates = { file = "level-plates.png" }, -- 98x25 plaques at y 0/32/64/96 of 128x128
	castFill = { file = "cast-fill.png" },
	-- globe auras (GlobeAura.lua): white, ADD, drawn 2x the globe and tinted
	auraCorona = { file = "aura-corona.png" },
	auraRaysA = { file = "aura-rays-a.png" },
	auraRaysB = { file = "aura-rays-b.png" },
	auraWispsA = { file = "aura-wisps-a.png" },
	auraWispsB = { file = "aura-wisps-b.png" },
	auraRing = { file = "aura-ring.png" },
	auraSpiral = { file = "aura-spiral.png" },
	auraTopWeight = { file = "aura-topweight.png" }, -- mask: a swirl's light kept over the globe
	shellRim = { file = "shell-rim.png" },
	shellFacets = { file = "shell-facets.png" },
	shellSheen = { file = "shell-sheen.png" },
	shellShardA = { file = "shell-shard-a.png" },
	shellShardB = { file = "shell-shard-b.png" },
	stormBoltA = { file = "storm-bolt-a.png" },
	stormBoltB = { file = "storm-bolt-b.png" },
	stormBoltC = { file = "storm-bolt-c.png" },
	stormBoltD = { file = "storm-bolt-d.png" },
	stormArcsA = { file = "storm-arcs-a.png" },
	stormArcsB = { file = "storm-arcs-b.png" },
	stormArcsC = { file = "storm-arcs-c.png" },
	stormArcsD = { file = "storm-arcs-d.png" },
	stormArcsE = { file = "storm-arcs-e.png" },
	stormArcsF = { file = "storm-arcs-f.png" },
	stormStatic = { file = "storm-static.png" },
	-- Rendered lightning (GlobeAura.lua STORM): lazy, for those who can have it.
	stormFlipCore = { file = "storm-flip-core.png", lazy = true },
	stormFlipGlow = { file = "storm-flip-glow.png", lazy = true },
}

-- socket.png holds a 76x80 crop in a 128x128 PNG. The stone interior starts 4px in from the left and 7px down.
ns.Art.SOCKET_TEXCOORD = { 0, 76 / 128, 0, 80 / 128 }
ns.Art.SOCKET_INSET = { left = 4 / 76, right = 4 / 76, top = 7 / 80, bottom = 6 / 80 }

-- menu.png: eight 40x66 columns in a 512x256 atlas, one row per state. The third row is the
-- pressed plate for menu buttons and the disabled (grey) portal for the hearth.
ns.Art.MENU_CELLS = { character = 0, spellbook = 1, talents = 2, social = 3, quests = 4, hearth = 5, bags = 6, flyout = 7 }
ns.Art.MENU_STATES = { normal = 0, hover = 1, pressed = 2, disabled = 2 }
function ns.Art.MenuTexCoord(name, state)
	local i = ns.Art.MENU_CELLS[name] or 0
	local row = ns.Art.MENU_STATES[state or "normal"] or 0
	return i * 40 / 512, (i + 1) * 40 / 512, row * 66 / 256, (row + 1) * 66 / 256
end

-- menu-flyout.png: the flyout's menu plates with gold icons, laid out like menu.png (40x66
-- columns, rows normal / hover / pressed).
ns.Art.FLYOUT_CELLS = {
	spellbook = 0, professions = 1, collections = 2, achievements = 3, groupfinder = 4, pvp = 5,
	legacy = 6, currency = 7, reputation = 8,
}
function ns.Art.FlyoutTexCoord(name, state)
	local i = ns.Art.FLYOUT_CELLS[name] or 0
	local row = ns.Art.MENU_STATES[state or "normal"] or 0
	return i * 40 / 512, (i + 1) * 40 / 512, row * 66 / 256, (row + 1) * 66 / 256
end

-- unit-frames.png (1024x256): D3 enemy health frames and party frames. x, y, w, h in the atlas;
-- bar = the frame's dark bar slot, relative to the piece; well = the party portrait well.
ns.Art.UNIT = {
	boss = { 0, 0, 491, 87, bar = { 76, 25, 339, 19 } },
	elite = { 500, 0, 425, 47, bar = { 43, 17, 339, 17 } },
	normal = { 0, 92, 294, 41, bar = { 21, 11, 252, 18 } },
	party = { 0, 140, 106, 52, bar = { 18, 29, 70, 10 }, well = { 17, 3, 72, 24 } },
	partyGold = { 110, 140, 106, 52, bar = { 18, 29, 70, 10 }, well = { 17, 3, 72, 24 } },
	cast = { 0, 200, 296, 14, bar = { 3, 2, 290, 10 } }, -- D3's thin progress bar
}
-- target-rings.png (512x128): D3's hero portrait frames, one 128 px cell per target rank, each
-- centred on its 39 px round hole. reach: how far the art runs right of the hole's centre.
ns.Art.TARGET_RING = {
	-- plate / badge: the level plaque's metal and its centre below the hole's (under the skull,
	-- the banner, the demon's chin)
	normal = { cell = 0, reach = 45, plate = "silver", badge = 50 }, -- silver laurel, ram skull
	elite = { cell = 1, reach = 47, plate = "gold", badge = 50 }, -- gold laurel, red banner
	boss = { cell = 2, reach = 47, plate = "dark", badge = 58 }, -- winged demon
}
ns.Art.TARGET_RING_CELL, ns.Art.TARGET_RING_HOLE = 128, 39

function ns.Art.TargetRingTexCoord(rank)
	local cell = (ns.Art.TARGET_RING[rank] or ns.Art.TARGET_RING.normal).cell
	return cell * 128 / 512, (cell + 1) * 128 / 512, 0, 1
end

-- Our own target frames (Options > Target > Style), rendered by tools/blender/target_styles.py
-- and packed by tools/build_target_styles.py: an atlas per style with a row per rank, 2 art px per
-- UI unit. Rects are x0, y0, x1, y1 from the frame's top left; art is the render's x, y, w, h.
-- A style has a portrait socket (a rect, or round with a model square its ring hides), health and
-- power grooves and either a cast groove or a cast rail above the frame (castBottom: the rail's
-- bottom edge). belowY / aboveY: where aura lines start under and over the frame. marks: centres
-- of the class icon, faction emblem and raid marker, around the portrait socket.
ns.Art.TARGET_STYLE_RANK = { normal = 0, rare = 1, elite = 2, boss = 3 }
ns.Art.TARGET_STYLES = {
	lintel = {
		slot = "targetStyleLintel", size = { 340, 72 }, art = { -34, -34, 408, 116 },
		portrait = { 8, 8, 64, 64 }, badge = { 8, 62 }, bar = { 76, 10, 330, 36 }, power = { 76, 41, 330, 47 },
		castGroove = { 76, 51, 330, 65 }, tot = { 346, 18 }, belowY = 77, aboveY = -6,
		marks = { class = { 10, 10 }, faction = { 62, 10 }, raid = { 36, 6 } },
	},
	slim = {
		slot = "targetStyleSlim", size = { 300, 54 }, art = { -34, -34, 368, 98 },
		portrait = { 6, 6, 48, 48 }, badge = { 7, 46 }, bar = { 56, 7, 292, 33 }, power = { 56, 38, 292, 45 },
		castBottom = -6, tot = { 306, 12 }, belowY = 60, aboveY = -2,
		marks = { class = { 8, 8 }, faction = { 46, 8 }, raid = { 27, 5 } },
	},
	bracket = {
		slot = "targetStyleBracket", size = { 334, 68 }, art = { -34, -34, 402, 112 },
		portrait = { round = true, cx = 34, cy = 34, hole = 26.5, model = 50 }, badge = { 34, 63 },
		bar = { 74, 21, 310, 45 }, power = { 74, 48, 296, 53 },
		castBottom = 10, tot = { 344, 20 }, belowY = 64, aboveY = 12,
		marks = { class = { 12, 12 }, faction = { 56, 12 }, raid = { 34, 2 } },
	},
	tablet = {
		slot = "targetStyleTablet", size = { 330, 66 }, art = { -34, -34, 398, 122 },
		portrait = { 10, 8, 62, 60 }, badge = { 11, 58 }, bar = { 76, 20, 322, 46 }, power = { 76, 50, 322, 56 },
		nameAt = { 164, 9 }, castBottom = -6, tot = { 342, 24 }, belowY = 70, aboveY = 0,
		marks = { class = { 12, 10 }, faction = { 60, 10 }, raid = { 36, 6 } },
	},
}

function ns.Art.TargetStyleTexCoord(style, rank)
	local row = ns.Art.TARGET_STYLE_RANK[rank] or 0
	local w, h = style.art[3] * 2, style.art[4] * 2
	return 0, w / 1024, row * h / 1024, (row + 1) * h / 1024
end

-- target-style-parts.png (1024x1024): the Bracket's ring, the cast rail, the level stud and the
-- target of target's frame. Returns left, right, top, bottom.
function ns.Art.TargetPartTexCoord(part, rank)
	local i = ns.Art.TARGET_STYLE_RANK[rank] or 0
	local x, y, w, h
	if part == "ring" then
		x, y, w, h = i % 3 * 280, math.floor(i / 3) * 280, 280, 280
	elseif part == "rail" then
		x, y, w, h = 0, 560 + i * 52, 512, 52
	elseif part == "badge" then
		x, y, w, h = i * 48, 768, 48, 48
	else
		x, y, w, h = 560, 560, 240, 76 -- the target of target's frame
	end
	return x / 1024, (x + w) / 1024, y / 1024, (y + h) / 1024
end

-- D3's level plaque, the small plate under a hero's portrait, in four metals.
ns.Art.LEVEL_PLATE = { bronze = 0, silver = 1, gold = 2, dark = 3 }

function ns.Art.LevelPlateTexCoord(kind)
	local i = ns.Art.LEVEL_PLATE[kind] or 1
	return 0, 98 / 128, i * 32 / 128, (i * 32 + 25) / 128
end

-- A level badge: the plaque (98x25 art, drawn at w x h) with the number centred on it.
-- badge:SetKind(kind) changes the metal; badge.text is the number's font string.
function ns.Art.LevelBadge(parent, w, h, kind, fontSize)
	local badge = CreateFrame("Frame", nil, parent)
	badge:SetSize(w, h)
	badge.plate = badge:CreateTexture(nil, "ARTWORK")
	badge.plate:SetAllPoints()
	local art = ns.Art.Apply(badge.plate, "levelPlates")
	if not art then
		badge.plate:SetColorTexture(0.04, 0.03, 0.03, 0.9)
	end
	function badge:SetKind(k)
		if art then self.plate:SetTexCoord(ns.Art.LevelPlateTexCoord(k)) end
	end
	badge:SetKind(kind)
	badge.text = badge:CreateFontString(nil, "OVERLAY")
	badge.text:SetFont(STANDARD_TEXT_FONT, fontSize or 10, "OUTLINE")
	badge.text:SetShadowColor(0, 0, 0, 0.85)
	badge.text:SetShadowOffset(1, -1)
	-- The plaque's dark slot sits a hair above its middle (the bottom rim is thicker).
	badge.text:SetPoint("CENTER", badge, "CENTER", 0, h * 0.04)
	badge.text:SetTextColor(0.95, 0.9, 0.8)
	return badge
end

function ns.Art.UnitTexCoord(name)
	local r = ns.Art.UNIT[name]
	return r[1] / 1024, (r[1] + r[3]) / 1024, r[2] / 256, (r[2] + r[4]) / 256
end

-- Columns of each frame that must not stretch (end caps and ornaments, in piece pixels). The
-- spans between them stretch evenly when a frame is drawn wider than the art.
ns.Art.UNIT_FIXED = {
	normal = { { 0, 24 }, { 128, 166 }, { 270, 294 } },
	elite = { { 0, 58 }, { 118, 136 }, { 194, 231 }, { 291, 309 }, { 368, 425 } },
	boss = { { 0, 102 }, { 155, 166 }, { 240, 251 }, { 324, 335 }, { 388, 491 } },
	cast = { { 0, 6 }, { 290, 296 } },
}

-- Draw a unit frame piece across `box` (a Frame) at `width` UI units, k UI units per piece
-- pixel vertically and for the fixed parts. Textures come from (and stay in) box.slices.
-- Returns the extra width added to the stretch spans, so callers can widen the bar slot.
function ns.Art.DrawSliced(box, name, width, k, extraHeight)
	local r = ns.Art.UNIT[name]
	local fixed = ns.Art.UNIT_FIXED[name] or { { 0, r[3] } }
	local segments = {}
	local x, stretchTotal = 0, 0
	for _, f in ipairs(fixed) do
		if f[1] > x then
			segments[#segments + 1] = { x, f[1], true }
			stretchTotal = stretchTotal + (f[1] - x)
		end
		segments[#segments + 1] = { f[1], f[2], false }
		x = f[2]
	end
	if x < r[3] then
		segments[#segments + 1] = { x, r[3], true }
		stretchTotal = stretchTotal + (r[3] - x)
	end
	-- Narrower than the art comes out of the stretch spans too, keeping some of them.
	local extra = math.max(-stretchTotal * k * 0.8, width - r[3] * k)
	-- extraHeight goes to the band of the art level with the bar, so the lips and ornaments above
	-- and below it keep their size. Without any, the piece is one row.
	extraHeight = extraHeight or 0
	local rows = { { 0, r[4], 0 } }
	if extraHeight ~= 0 and r.bar then
		local top, bottom = r.bar[2], r.bar[2] + r.bar[4]
		rows = { { 0, top, 0 }, { top, bottom, extraHeight }, { bottom, r[4], 0 } }
	end
	box.slices = box.slices or {}
	local left, count = 0, 0
	local path = ns.Art.Path("unitFrames")
	for _, seg in ipairs(segments) do
		local srcW = seg[2] - seg[1]
		local w = srcW * k
		if seg[3] and stretchTotal > 0 then
			w = w + extra * srcW / stretchTotal
		end
		local y = 0
		for _, row in ipairs(rows) do
			count = count + 1
			local tex = box.slices[count]
			if not tex then
				tex = box:CreateTexture(nil, "ARTWORK")
				box.slices[count] = tex
			end
			if path then
				tex:SetTexture(path)
				tex:SetTexCoord((r[1] + seg[1]) / 1024, (r[1] + seg[2]) / 1024, (r[2] + row[1]) / 256, (r[2] + row[2]) / 256)
			else
				tex:SetColorTexture(0.05, 0.04, 0.03, 0.82)
			end
			local h = math.max(1, (row[2] - row[1]) * k + row[3])
			tex:ClearAllPoints()
			tex:SetPoint("TOPLEFT", box, "TOPLEFT", left, -y)
			tex:SetSize(w, h)
			tex:Show()
			y = y + h
		end
		left = left + w
	end
	for i = count + 1, #box.slices do
		box.slices[i]:Hide()
	end
	box:SetSize(left, r[4] * k + extraHeight)
	return extra
end

-- D3 draws its UI for a 1080-line screen and scales it with the resolution. This frame scale
-- makes one art pixel one pixel at 1080p (and the same share of the screen at any size), so
-- the art is never blown up past D3's own look. user multiplies it.
function ns.Art.D3Scale(user)
	local parent = UIParent:GetEffectiveScale()
	if not parent or parent <= 0 then parent = 1 end
	return (user or 1) * (768 / 1080) / parent
end

local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

function ns.Art.Path(slot)
	local info = ns.Art.slots[slot]
	local ready = ns.Art.ready and ns.Art.ready[slot]
	if info and ready then
		return ROOT .. info.file
	end
end

function ns.Art.Probe()
	local probe = ns.Art.probe
	if not probe then
		probe = UIParent:CreateTexture(nil, "BACKGROUND")
		probe:Hide()
		ns.Art.probe = probe
	end
	local ready = {}
	local loaded, total = 0, 0
	for slot, info in pairs(ns.Art.slots) do
		if info.lazy then
			ready[slot] = ns.Art.ready and ns.Art.ready[slot] -- still unknown unless required
		else
			total = total + 1
			local path = ROOT .. info.file
			local ok = probe:SetTexture(path)
			if ok then
				ready[slot] = true
				loaded = loaded + 1
			else
				ready[slot] = false
			end
		end
	end
	probe:SetTexture(nil)
	ns.Art.ready = ready
	ns.Art.loadedCount = loaded
	ns.Art.totalCount = total
	return loaded, total
end

-- A lazy slot's path, checked the first time something actually wants it.
function ns.Art.Require(slot)
	local info = ns.Art.slots[slot]
	if not info then return nil end
	ns.Art.ready = ns.Art.ready or {}
	if ns.Art.ready[slot] == nil then
		local probe = ns.Art.probe
		if not probe then
			probe = UIParent:CreateTexture(nil, "BACKGROUND")
			probe:Hide()
			ns.Art.probe = probe
		end
		ns.Art.ready[slot] = probe:SetTexture(ROOT .. info.file) and true or false
		probe:SetTexture(nil)
	end
	return ns.Art.Path(slot)
end

function ns.Art.Apply(texture, slot, color)
	if not texture then return false end
	local path = ns.Art.Path(slot)
	if path and texture:SetTexture(path) then
		texture:SetVertexColor(1, 1, 1, 1)
		return true
	end
	local r, g, b, a = 0, 0, 0, 0
	if color then
		r, g, b, a = color[1], color[2], color[3], color[4] or 1
	end
	texture:SetColorTexture(r, g, b, a)
	return false
end

local function EnsureMask(texture, anchor)
	if not texture or texture.sanctuaryMasked then return end
	if not texture.AddMaskTexture then return end
	anchor = anchor or texture:GetParent() or texture
	if not anchor.CreateMaskTexture then return end
	local mask = anchor:CreateMaskTexture()
	mask:SetAllPoints(anchor)
	mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	local ok = pcall(texture.AddMaskTexture, texture, mask)
	if ok then
		texture.sanctuaryMasked = true
		texture.sanctuaryMask = mask
	end
end

function ns.Art.MaskCircle(texture, anchor)
	EnsureMask(texture, anchor)
end

-- Stone socket behind the icon and the D3 hover glow above it. Replaces the old metal ring.
function ns.Art.AttachRing(parent)
	if parent.sanctuaryRingFrame then
		return parent.sanctuaryRingFrame
	end
	if parent.sanctuarySocket and not parent.sanctuarySocketTex then
		local socket = parent:CreateTexture(nil, "BACKGROUND", nil, -7)
		local inset = ns.Art.SOCKET_INSET
		local function Outset()
			local w, h = parent:GetSize()
			local fw = w / (1 - inset.left - inset.right)
			local fh = h / (1 - inset.top - inset.bottom)
			socket:ClearAllPoints()
			socket:SetPoint("TOPLEFT", parent, "TOPLEFT", -fw * inset.left, fh * inset.top)
			socket:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", fw * inset.right, -fh * inset.bottom)
		end
		if ns.Art.Apply(socket, "socket") then
			socket:SetTexCoord(unpack(ns.Art.SOCKET_TEXCOORD))
		else
			socket:SetColorTexture(0.05, 0.05, 0.05, 0.9)
		end
		Outset()
		parent:HookScript("OnSizeChanged", Outset)
		parent.sanctuarySocketTex = socket
	end
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetAllPoints()
	frame:EnableMouse(false)
	local cooldown = parent.cooldown or parent.Cooldown
	local level = parent:GetFrameLevel() + 6
	if cooldown and cooldown.GetFrameLevel then
		level = cooldown:GetFrameLevel() + 3
	end
	frame:SetFrameLevel(level)
	parent.sanctuaryRingFrame = frame

	-- bottomBar_buttonFX_frameGlow: the glow D3 draws on hover and press. The art is a square
	-- frame with a soft halo, so it is drawn larger than the socket.
	local glow = frame:CreateTexture(nil, "OVERLAY", nil, 1)
	glow:SetPoint("TOPLEFT", -0.45 * 40, 0.45 * 40)
	glow:SetPoint("BOTTOMRIGHT", 0.45 * 40, -0.45 * 40)
	local function SizeGlow()
		local w, h = parent:GetSize()
		glow:ClearAllPoints()
		glow:SetPoint("TOPLEFT", -w * 0.45, h * 0.45)
		glow:SetPoint("BOTTOMRIGHT", w * 0.45, -h * 0.45)
	end
	if ns.Art.Apply(glow, "buttonGlow") then
		glow:SetBlendMode("ADD")
	else
		glow:SetColorTexture(1, 0.78, 0.35, 0.25)
		glow:SetBlendMode("ADD")
	end
	SizeGlow()
	parent:HookScript("OnSizeChanged", SizeGlow)
	glow:Hide()
	parent.sanctuaryGlow = glow
	return frame
end

-- Template art that fights the stone sockets. The highlight, pushed, checked, flash and proc
-- textures stay: they are WoW's own gold glow and the engine keeps their state right, even
-- for presses that happen inside the secure keybind path.
local SQUARE_LIGHTS = {
	"NewActionTexture",
	"Border",
}

-- Gold press and hover light for buttons that are not built from the action button template.
local GOLD_HOVER = "UI-HUD-ActionBar-IconFrame-Mouseover"
local GOLD_DOWN = "UI-HUD-ActionBar-IconFrame-Down"

-- Hover, press and checked use the engine's own button states (so presses through the secure
-- keybind path can never leave a light on) but our art: a gold rim on the socket edge.
-- socket-hover/press.png map the button to their inner 96 of 128 px; LibActionButton resets
-- the template textures' size on every update, so this runs again after each one.
local RIM_OUTSET = 16 / 96
-- Template lights we keep (auto-attack flash, proc highlight), refit in Blizzard's own
-- proportion: ~5.5% past the icon on each side.
local TEMPLATE_LIGHTS = { "Flash", "SpellHighlightTexture" }
local TEMPLATE_OUTSET = 2.5 / 45

local function Fit(button, tex, outset)
	if not tex then return end
	local w, h = button:GetSize()
	tex:ClearAllPoints()
	tex:SetPoint("TOPLEFT", button, "TOPLEFT", -w * outset, h * outset)
	tex:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", w * outset, -h * outset)
end

local function Rim(button, tex, slot, alpha)
	if not tex then return end
	if ns.Art.Path(slot) then
		tex:SetTexture(ns.Art.Path(slot))
		tex:SetTexCoord(0, 1, 0, 1)
		tex:SetBlendMode("ADD")
		tex:SetVertexColor(1, 1, 1, alpha)
		Fit(button, tex, RIM_OUTSET)
	else
		Fit(button, tex, TEMPLATE_OUTSET)
	end
end

local function FitGoldLights(button)
	local w = button:GetSize()
	if not w or w <= 0 then return end
	Rim(button, button.GetHighlightTexture and button:GetHighlightTexture() or button.HighlightTexture, "socketHover", 1)
	Rim(button, button.GetPushedTexture and button:GetPushedTexture() or button.PushedTexture, "socketPress", 1)
	-- Checked marks an active ability (auto attack, a channel): steady and dimmer than hover,
	-- unless the button asks for more (the stance bar's active form).
	Rim(button, button.GetCheckedTexture and button:GetCheckedTexture() or button.CheckedTexture, "socketHover", button.sanctuaryCheckedAlpha or 0.65)
	for i = 1, #TEMPLATE_LIGHTS do
		Fit(button, button[TEMPLATE_LIGHTS[i]], TEMPLATE_OUTSET)
	end
end
ns.Art.FitGoldLights = FitGoldLights

function ns.Art.GoldLights(button)
	if button.sanctuaryGold or not button.SetHighlightAtlas then return false end
	local ok = pcall(button.SetHighlightAtlas, button, GOLD_HOVER, "ADD")
	if not ok then return false end
	if button.SetPushedAtlas then
		pcall(button.SetPushedAtlas, button, GOLD_DOWN)
	end
	button.sanctuaryGold = true
	return true
end

local function HideSquareLight(button, texture)
	if not texture or texture.sanctuarySquaredOff then return end
	texture.sanctuarySquaredOff = true
	texture:SetAlpha(0)
end

local function SyncPressLight(button)
	local glow = button.sanctuaryGlow
	if not glow then return end
	local pushed = button.GetButtonState and button:GetButtonState() == "PUSHED"
	local checked = button.GetChecked and button:GetChecked()
	local over = button.sanctuaryOver
	local on = pushed or checked or over
	glow:SetShown(on)
end

function ns.Art.ReskinActionButton(_, button)
	if not button.sanctuary then return end
	local icon = button.icon
	if icon then
		if button.sanctuarySquare then
			icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		else
			EnsureMask(icon)
			icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		end
		icon:ClearAllPoints()
		icon:SetAllPoints()
	end
	if button.SetPushedTextOffset then
		button:SetPushedTextOffset(0, 0)
	end
	if button.NormalTexture then
		button.NormalTexture:SetAlpha(0)
	end
	if button.SlotBackground then
		button.SlotBackground:Hide()
	end
	if button.FloatingBG then
		button.FloatingBG:Hide()
	end
	for i = 1, #SQUARE_LIGHTS do
		HideSquareLight(button, button[SQUARE_LIGHTS[i]])
	end
	-- Template buttons (LibActionButton) already carry WoW's gold lights; others get them here.
	local native = button.GetHighlightTexture and button:GetHighlightTexture() ~= nil
	if not native then
		native = ns.Art.GoldLights(button)
	end
	local ring = ns.Art.AttachRing(button)
	local cooldown = button.cooldown
	if cooldown then
		if cooldown.SetUseCircularEdge then
			cooldown:SetUseCircularEdge(not button.sanctuarySquare)
		end
		if ring and ring:GetFrameLevel() <= cooldown:GetFrameLevel() then
			ring:SetFrameLevel(cooldown:GetFrameLevel() + 3)
		end
	end
	local textParent = ring or button
	if button.HotKey and button.HotKey:GetParent() ~= textParent then
		button.HotKey:SetParent(textParent)
	end
	if button.Count and button.Count:GetParent() ~= textParent then
		button.Count:SetParent(textParent)
	end
	if native then
		FitGoldLights(button)
		if not button.sanctuaryFitHooked then
			button.sanctuaryFitHooked = true
			button:HookScript("OnSizeChanged", FitGoldLights)
		end
		-- The gold template lights handle hover, press and checked; no D3 glow on top.
		if button.sanctuaryGlow then
			button.sanctuaryGlow:Hide()
		end
		return
	end
	if not button.sanctuaryPressHooked then
		button.sanctuaryPressHooked = true
		button:HookScript("OnEnter", function(self)
			self.sanctuaryOver = true
			SyncPressLight(self)
		end)
		button:HookScript("OnLeave", function(self)
			self.sanctuaryOver = false
			SyncPressLight(self)
		end)
		if button.SetChecked then
			hooksecurefunc(button, "SetChecked", SyncPressLight)
		end
		if button.SetButtonState then
			hooksecurefunc(button, "SetButtonState", SyncPressLight)
		end
	end
	SyncPressLight(button)
end
