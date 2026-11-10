SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.PartyStyles = ns.PartyStyles or {}
local S = ns.PartyStyles

-- The two looks of the party frames, built on a member's (or pet's) secure button. Party.lua
-- only talks to the view a builder returns:
--
--   view.root            everything drawn, a child of the button (shown for the active style)
--   view.health          the health StatusBar (vertical in a globe, horizontal in a groove)
--   view.pool            its Liquid pool (globes), or nil
--   view.heal/.absorb    prediction StatusBars riding the fill (slab; globes use pool bands)
--   view.overShield      a glow for "more shield than room"
--   view.power           the resource StatusBar, or nil (pets)
--   view.name, .pct, .status   font strings (some nil)
--   view.level, .levelBox  the level number and the badge it sits in (members only)
--   view.cast            { bar, icon, spellName }, a frame shown while the member casts (members only)
--   view.face            the 2D portrait texture; view.model the 3D one (slab), or nil
--   view.leader, .role, .mark, .ready  icon textures
--   view.glow            the threat halo (ADD, tinted by Party.lua)
--   view.glowBox         a frame where the dispel halo goes (Party.lua's aura slot fills it)
--   view.glowRect        that halo's atlas rect and file slot, for the slot's texture
--   view.select          a gold halo while this is your target
--   view.metal           { { tex, iron, gold, tint } } the frame's metal: gold on your target, else
--                        the member's class colour (tint is a copy added on top: iron is dark,
--                        so multiplying alone would barely show)
--   view.stone           the slab's stone (its alpha is the opacity setting)
--   view.debuffAt/buffAt { point, x, y } where the aura containers start, from the button
--   view.size            { w, h } the button's size in this style
--
-- Sizes are UI units at scale 1 (the anchor carries the scale); the art is 2x.

local FILL = "Interface\\Buttons\\WHITE8X8"

local function Coord(style, rect)
	return ns.Art.PartyCoord(style, rect)
end

local function Tex(parent, layer, sublevel)
	local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sublevel or 0)
	if t.SetSnapToPixelGrid then
		t:SetSnapToPixelGrid(false)
		t:SetTexelSnappingBias(0)
	end
	return t
end

-- A piece of a party atlas, or nothing when the art is missing.
local function Piece(parent, layer, slot, style, rect, sublevel)
	local t = Tex(parent, layer, sublevel)
	if ns.Art.Apply(t, slot) then
		t:SetTexCoord(Coord(style, rect))
	else
		t:SetColorTexture(0, 0, 0, 0)
	end
	return t
end

local function Font(parent, size, d3)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFont(d3 and ns.FONT or STANDARD_TEXT_FONT, size, "OUTLINE")
	if not fs:GetFont() then fs:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE") end
	fs:SetShadowColor(0, 0, 0, 0.85)
	fs:SetShadowOffset(1, -1)
	fs:SetWordWrap(false)
	return fs
end

-- Leader, role, raid marker and ready check: WoW's own icons (they read at a glance).
local function Icons(view, parent)
	view.leader = Tex(parent, "OVERLAY", 2)
	view.leader:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
	view.role = Tex(parent, "OVERLAY", 2)
	view.role:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")
	view.mark = Tex(parent, "OVERLAY", 2)
	view.mark:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
	view.ready = Tex(parent, "OVERLAY", 3)
	for _, t in ipairs({ view.leader, view.role, view.mark, view.ready }) do t:Hide() end
end

-- The threat halo (ours) and the box the dispel halo's aura slot is pinned to.
local function Halos(view, root, style, spec, around)
	local glow = Piece(root, "BACKGROUND", "party" .. (style == "globes" and "Globes" or "Slab"), style, spec.rect, -8)
	glow:SetSize(spec.size[1], spec.size[2])
	glow:SetPoint("CENTER", around, "CENTER")
	glow:SetBlendMode("ADD")
	glow:SetAlpha(0)
	view.glow = glow
	local chosen = Piece(root, "BACKGROUND", "party" .. (style == "globes" and "Globes" or "Slab"), style, spec.rect, -7)
	chosen:SetSize(spec.size[1] * 1.06, spec.size[2] * 1.06)
	chosen:SetPoint("CENTER", around, "CENTER")
	chosen:SetBlendMode("ADD")
	chosen:SetVertexColor(1, 0.74, 0.22)
	chosen:SetAlpha(0)
	view.select = chosen
	local box = CreateFrame("Frame", nil, root)
	box:SetSize(spec.size[1], spec.size[2])
	box:SetPoint("CENTER", around, "CENTER")
	box:EnableMouse(false)
	view.glowBox = box
	view.glowRect = { slot = style == "globes" and "partyGlobes" or "partySlab", style = style, rect = spec.rect }
end

-- A piece of the frame's metal: the iron, and an added copy of it for the class colour.
local function Metal(view, parent, slot, style, cell, sublevel)
	local tex = Piece(parent, "ARTWORK", slot, style, cell.iron, sublevel or 0)
	tex:SetAllPoints()
	local tint = Piece(parent, "ARTWORK", slot, style, cell.iron, (sublevel or 0) + 1)
	tint:SetAllPoints()
	tint:SetBlendMode("ADD")
	tint:Hide()
	view.metal[#view.metal + 1] = { tex = tex, iron = cell.iron, gold = cell.gold, tint = tint }
end

-- The level, in a small round badge. `size` is the badge's diameter.
local function LevelBadge(view, parent, size)
	local box = CreateFrame("Frame", nil, parent)
	box:SetSize(size, size)
	box:EnableMouse(false)
	local rim = Tex(box, "BACKGROUND")
	rim:SetAllPoints()
	rim:SetColorTexture(0.42, 0.34, 0.2, 1)
	ns.Art.MaskCircle(rim, box)
	local holder = CreateFrame("Frame", nil, box)
	holder:SetSize(size - 2, size - 2)
	holder:SetPoint("CENTER")
	local back = Tex(holder, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(0.04, 0.03, 0.025, 1)
	ns.Art.MaskCircle(back, holder)
	local text = Font(holder, 9, false)
	text:SetPoint("CENTER", holder, "CENTER", 0, 0)
	text:SetTextColor(0.95, 0.88, 0.7)
	view.level, view.levelBox = text, box
	box:Hide()
	return box
end

-- The cast bar: D3's orange fill over a dark groove, the spell's name across it.
local function CastBar(root, width, height, iconSize)
	local cast = CreateFrame("Frame", nil, root)
	cast:SetSize(width, height)
	cast:EnableMouse(false)
	cast.bar = CreateFrame("StatusBar", nil, cast)
	cast.bar:SetAllPoints()
	cast.bar:SetStatusBarTexture(ns.Art.Path("castFill") or FILL)
	if not ns.Art.Path("castFill") then cast.bar:SetStatusBarColor(1, 0.45, 0.1, 1) end
	cast.bar:SetMinMaxValues(0, 1)
	cast.bar:SetValue(0)
	local back = Tex(cast.bar, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(0.02, 0.015, 0.01, 0.95)
	-- Its own frame, so the name can sit above the slab's metal.
	cast.over = CreateFrame("Frame", nil, cast)
	cast.over:SetAllPoints()
	cast.over:EnableMouse(false)
	cast.spellName = Font(cast.over, 8, false)
	cast.spellName:SetPoint("CENTER", cast.over, "CENTER", 0, 0)
	cast.spellName:SetWidth(width - 4)
	cast.spellName:SetTextColor(1, 0.9, 0.72)
	if iconSize then
		cast.icon = Tex(cast.over, "OVERLAY")
		cast.icon:SetSize(iconSize, iconSize)
		cast.icon:SetPoint("RIGHT", cast, "LEFT", -2, 0)
		cast.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	end
	cast:Hide()
	return cast
end

---------------------------------------------------------------------------
-- Globes

-- A small globe of the player's liquid: well, the fill (Liquid pool when the client can clip),
-- heal and shield bands, the fixed shade. Returns the globe frame.
local function MiniGlobe(view, parent, d, zoom)
	local globe = CreateFrame("Frame", nil, parent)
	globe:SetSize(d, d)
	local well = Tex(globe, "BACKGROUND")
	well:SetAllPoints()
	if ns.Art.Apply(well, "liquid") then
		well:SetVertexColor(0.06, 0.03, 0.025, 1)
	else
		well:SetColorTexture(0.05, 0.03, 0.03, 1)
		ns.Art.MaskCircle(well, globe)
	end
	local bar = CreateFrame("StatusBar", nil, globe)
	bar:SetAllPoints()
	bar:SetOrientation("VERTICAL")
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(1)
	view.health = bar
	view.pool = ns.Liquid and ns.Liquid.Attach(globe, bar, { zoom = zoom, slices = 6, motes = 0, ghost = true })
	if view.pool then
		ns.Liquid.Band(view.pool, "heal")
		ns.Liquid.Band(view.pool, "absorb")
		ns.Liquid.Shield(view.pool)
	else
		bar:SetStatusBarTexture(FILL)
		local tex = bar:GetStatusBarTexture()
		if tex then ns.Art.MaskCircle(tex, bar) end
	end
	view.shade = ns.Liquid and ns.Liquid.Shade(globe)
	view.globe = globe
	return globe
end

-- Frame levels inside a globe view, from the root's: the liquid stack (Liquid's own offsets),
-- the metal, the resource fill in its groove, the medallion, then the texts and icons.
local function GlobeLevels(view, base)
	view.globe:SetFrameLevel(base + ns.LEVEL.globe)
	view.health:SetFrameLevel(base + ns.LEVEL.liquid)
	if view.pool then view.pool:SetLevels(base) end
	if view.shade then view.shade:SetFrameLevel(base + ns.LEVEL.shade) end
	view.art:SetFrameLevel(base + ns.LEVEL.surface + 1)
	-- The crescent groove is cut into the bezel with a dark floor: its fill lies on top.
	if view.power then view.power:SetFrameLevel(base + ns.LEVEL.surface + 2) end
	if view.medal then view.medal:SetFrameLevel(base + ns.LEVEL.surface + 3) end
	view.top:SetFrameLevel(base + ns.LEVEL.surface + 5)
	if view.levelBox then view.levelBox:SetFrameLevel(base + ns.LEVEL.surface + 6) end
	if view.cast then
		view.cast:SetFrameLevel(base + ns.LEVEL.surface + 5)
		view.cast.bar:SetFrameLevel(base + ns.LEVEL.surface + 5)
		view.cast.over:SetFrameLevel(base + ns.LEVEL.surface + 6)
	end
end

function S.BuildGlobes(button, isPet)
	local G = ns.Art.PARTY.globes
	local view = { style = "globes", metal = {} }
	local root = CreateFrame("Frame", nil, button)
	root:SetAllPoints()
	root:EnableMouse(false)
	view.root = root

	local cell = isPet and G.pet or G.bezel
	-- The art frame is the bezel (or the pet's), placed in the button: a member's leaves room
	-- for the medallion over its upper-left shoulder, and its name and auras run to the right.
	local art = CreateFrame("Frame", nil, root)
	art:SetSize(cell.size[1], cell.size[2])
	view.art = art
	local padL, padT = 0, 0
	if not isPet then
		local m = G.medallion
		padL = math.max(0, -(cell.size[1] / 2 + m.at[1] - m.size[1] / 2))
		padT = math.max(0, -(cell.size[2] / 2 + m.at[2] - m.size[2] / 2))
	end
	art:SetPoint("TOPLEFT", root, "TOPLEFT", padL, -padT)
	view.size = isPet and { cell.size[1], cell.size[2] } or { padL + cell.size[1] + 112, padT + cell.size[2] }

	local g = cell.globe
	local globe = MiniGlobe(view, root, g[3], isPet and 0.3 or 0.45)
	globe:SetPoint("CENTER", art, "TOPLEFT", g[1], -g[2])

	Metal(view, art, "partyGlobes", "globes", cell)

	-- Texts and icons above everything.
	local top = CreateFrame("Frame", nil, root)
	top:SetAllPoints()
	top:EnableMouse(false)
	view.top = top

	if not isPet then
		-- The resource: the crescent groove, filling bottom-up.
		local r = cell.resource
		local power = CreateFrame("StatusBar", nil, root)
		power:SetSize(r[3], r[4])
		power:SetPoint("TOPLEFT", art, "TOPLEFT", r[1], -r[2])
		power:SetOrientation("VERTICAL")
		power:SetStatusBarTexture(ns.Art.Path("partyCrescent") or FILL)
		power:SetMinMaxValues(0, 1)
		power:SetValue(0)
		local groove = Tex(power, "BACKGROUND")
		groove:SetAllPoints()
		groove:SetColorTexture(0, 0, 0, 0)
		view.power = power

		-- The portrait medallion over the upper-left shoulder.
		local m = G.medallion
		local medal = CreateFrame("Frame", nil, root)
		medal:SetSize(m.size[1], m.size[2])
		medal:SetPoint("CENTER", art, "CENTER", m.at[1], -m.at[2])
		view.medal = medal
		-- The round 2D portrait, a hair wider than the hole so it runs under the rim. MaskCircle
		-- masks to the anchor's box, so the face gets a holder the hole's size.
		local hole = m.hole
		local holder = CreateFrame("Frame", nil, medal)
		holder:SetSize(hole[3] + 1, hole[3] + 1)
		holder:SetPoint("CENTER", medal, "TOPLEFT", hole[1], -hole[2])
		local back = Tex(holder, "BACKGROUND")
		back:SetAllPoints()
		back:SetColorTexture(0.03, 0.02, 0.02, 1)
		ns.Art.MaskCircle(back, holder)
		local face = Tex(holder, "ARTWORK")
		face:SetAllPoints()
		ns.Art.MaskCircle(face, holder)
		view.face = face
		Metal(view, medal, "partyGlobes", "globes", m, 1)

		-- Health text in the globe, the name and the level to the right of the bezel.
		view.pct = Font(top, 12, false)
		view.pct:SetPoint("CENTER", globe, "CENTER", 0, -1)
		view.status = Font(top, 9, true)
		view.status:SetPoint("CENTER", globe, "CENTER", 0, -1)
		view.name = Font(top, 12, true)
		view.name:SetPoint("TOPLEFT", art, "TOPRIGHT", 2, -10)
		view.name:SetWidth(150) -- room for a first and last name
		view.name:SetJustifyH("LEFT")

		Icons(view, top)
		local icon = 15
		view.leader:SetSize(icon, icon)
		view.leader:SetPoint("BOTTOMLEFT", medal, "TOPLEFT", -2, -6)
		view.role:SetSize(icon, icon)
		view.role:SetPoint("BOTTOMLEFT", medal, "BOTTOMLEFT", -4, -2)
		view.mark:SetSize(icon + 2, icon + 2)
		view.mark:SetPoint("BOTTOM", art, "TOP", 6, -6)
		view.ready:SetSize(22, 22)
		view.ready:SetPoint("CENTER", face, "CENTER")
		-- Under the medallion, left of the globe's text (health, Dead, Offline) and above the pet.
		LevelBadge(view, top, 16):SetPoint("CENTER", medal, "BOTTOM", -1, -1)

		-- The cast bar, between the name and the debuffs.
		view.cast = CastBar(root, 92, 7, 11)
		view.cast:SetPoint("TOPLEFT", art, "TOPRIGHT", 15, -22)

		-- Auras: debuffs under the name, your buffs under them, clear of the pet if it hangs right.
		local clear = G.pet.at[1] > 0 and math.max(0, G.pet.at[1] + G.pet.size[1] / 2 - cell.size[1] / 2) + 4 or 4
		view.debuffAt = { "TOPLEFT", padL + cell.size[1] + clear, -(padT + 30) }
		view.buffAt = { "TOPLEFT", padL + cell.size[1] + clear, -(padT + 52) }

		Halos(view, root, "globes", G.glow, art)
	else
		view.status = Font(top, 7, true)
		view.status:SetPoint("CENTER", globe, "CENTER", 0, 0)
		Halos(view, root, "globes", G.petGlow, art)
	end

	-- Shield overflow: the pool's own silver bubble does it on a globe.
	view.SetLevels = function(base) GlobeLevels(view, base) end
	return view
end

---------------------------------------------------------------------------
-- Slab

-- The globes' liquid moving in a groove (as the target bar does it): two tile layers drifting
-- inside a clip that ends where the fill ends.
local GROOVE_LIQUID = {
	{ slot = "liquidTile", speed = 0.018, alpha = 0.26, scale = 1.6, sway = 0.006 },
	{ slot = "liquidStreaks", speed = 0.034, alpha = 0.16, scale = 1.2, sway = 0 },
}

local grooves = {}

local function GrooveLiquid(bar, w, h)
	if not (ns.Art.Path("liquidTile") and bar.SetClipsChildren) then return nil end
	local fill = bar:GetStatusBarTexture()
	local clip = CreateFrame("Frame", nil, bar)
	clip:SetPoint("TOPLEFT")
	clip:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
	clip:SetClipsChildren(true)
	local layers = {}
	for i, spec in ipairs(GROOVE_LIQUID) do
		local layer = clip:CreateTexture(nil, "ARTWORK", nil, i)
		layer:SetPoint("TOPLEFT", bar, "TOPLEFT")
		layer:SetSize(w, h)
		layer:SetTexture(ns.Art.Path(spec.slot) or ns.Art.Path("liquidTile"), "REPEAT", "REPEAT")
		layer:SetBlendMode("ADD")
		layers[i] = layer
	end
	local liquid = { clip = clip, layers = layers, w = w, h = h, bar = bar, color = { 1, 0.3, 0.2 } }
	grooves[#grooves + 1] = liquid
	return liquid
end

-- Called by Party.lua's driver: moves every visible groove's liquid with the globes' clock.
function S.AnimateGrooves(t)
	for _, liquid in ipairs(grooves) do
		if liquid.bar:IsVisible() then
			local c = liquid.color
			for i, layer in ipairs(liquid.layers) do
				local spec = GROOVE_LIQUID[i]
				local su, sv = liquid.w / (256 * spec.scale), liquid.h / (256 * spec.scale)
				local u = (t * spec.speed + 0.37 * i) % 1 + 1.5
				local v = (0.3 * i + spec.sway * math.sin(t * 0.25 + i)) % 1 + 1.5
				layer:SetTexCoord(u, u + su, v, v + sv)
				layer:SetVertexColor(c[1], c[2], c[3], spec.alpha)
			end
		end
	end
end

local function Groove(parent, rect, w, h)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetSize(rect[3], rect[4])
	bar:SetStatusBarTexture(ns.Art.Path("unitFillWhite") or FILL)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(1)
	return bar
end

local function Band(parent, after, r, g, b, a)
	local band = CreateFrame("StatusBar", nil, parent)
	band:SetStatusBarTexture(ns.Art.Path("unitFillWhite") or FILL)
	band:SetStatusBarColor(r, g, b, a)
	band:SetMinMaxValues(0, 1)
	band:SetValue(0)
	band:SetPoint("TOPLEFT", after, "TOPRIGHT")
	band:SetPoint("BOTTOMLEFT", after, "BOTTOMRIGHT")
	return band
end

function S.BuildSlab(button, isPet)
	local L = ns.Art.PARTY.slab
	local cell = isPet and L.pet or L.member
	local view = { style = "slab", metal = {} }
	local root = CreateFrame("Frame", nil, button)
	root:SetAllPoints()
	root:EnableMouse(false)
	view.root = root
	view.size = { cell.size[1], cell.size[2] }

	local stone = Piece(root, "BACKGROUND", "partySlab", "slab", cell.stone)
	stone:SetAllPoints()
	view.stone = stone

	-- The portrait in its socket: the 3D bust (square, so it fits uncropped), or the 2D one.
	local s = cell.socket
	local socket = CreateFrame("Frame", nil, root)
	socket:SetSize(s[3], s[4])
	socket:SetPoint("TOPLEFT", root, "TOPLEFT", s[1], -s[2])
	local back = Tex(socket, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(0.02, 0.015, 0.012, 1)
	view.face = Tex(socket, "ARTWORK")
	view.face:SetAllPoints()
	if not isPet then
		view.model = CreateFrame("PlayerModel", nil, socket)
		view.model:SetAllPoints()
	end
	view.socket = socket

	local h = cell.health
	local health = Groove(root, h)
	health:SetPoint("TOPLEFT", root, "TOPLEFT", h[1], -h[2])
	local gback = Tex(health, "BACKGROUND")
	gback:SetAllPoints()
	gback:SetColorTexture(0.03, 0.015, 0.012, 0.9)
	view.health = health
	view.liquid = GrooveLiquid(health, h[3], h[4])
	view.heal = Band(health, health:GetStatusBarTexture(), 0.42, 1.0, 0.36, 0.6)
	view.absorb = Band(health, view.heal:GetStatusBarTexture(), 0.8, 0.88, 1.0, 0.6)
	view.heal:SetWidth(h[3])
	view.absorb:SetWidth(h[3])
	-- The bands may run past the groove's end; clip them to it.
	if health.SetClipsChildren then health:SetClipsChildren(true) end
	local over = Tex(health, "OVERLAY", 2)
	over:SetTexture("Interface\\RaidFrame\\Shield-Overshield")
	over:SetBlendMode("ADD")
	over:SetVertexColor(0.75, 0.87, 1.0, 0.95)
	over:SetPoint("TOPRIGHT")
	over:SetPoint("BOTTOMRIGHT")
	over:SetWidth(12)
	over:SetAlpha(0)
	view.overShield = over

	if not isPet then
		local p = cell.power
		local power = Groove(root, p)
		power:SetPoint("TOPLEFT", root, "TOPLEFT", p[1], -p[2])
		local pback = Tex(power, "BACKGROUND")
		pback:SetAllPoints()
		pback:SetColorTexture(0.03, 0.02, 0.015, 0.9)
		view.power = power
	end

	local art = CreateFrame("Frame", nil, root)
	art:SetAllPoints()
	art:EnableMouse(false)
	view.art = art
	Metal(view, art, "partySlab", "slab", cell)

	local top = CreateFrame("Frame", nil, root)
	top:SetAllPoints()
	top:EnableMouse(false)
	view.top = top
	local size = isPet and 9 or 12
	view.name = Font(top, size, true)
	view.name:SetPoint("LEFT", health, "LEFT", 4, 0.5)
	view.name:SetJustifyH("LEFT")
	view.name:SetWidth(h[3] - (isPet and 34 or 44))
	view.status = Font(top, isPet and 8 or 10, true)
	view.status:SetPoint("RIGHT", health, "RIGHT", -4, 0.5)
	if not isPet then
		view.pct = Font(top, 12, false)
		view.pct:SetPoint("RIGHT", health, "RIGHT", -4, 0)

		Icons(view, top)
		local icon = 14
		view.leader:SetSize(icon, icon)
		view.leader:SetPoint("TOPLEFT", socket, "TOPLEFT", -5, 7)
		view.role:SetSize(icon, icon)
		view.role:SetPoint("BOTTOMRIGHT", socket, "BOTTOMRIGHT", 4, -4)
		view.mark:SetSize(icon + 2, icon + 2)
		view.mark:SetPoint("TOPRIGHT", socket, "TOPRIGHT", 6, 7)
		view.ready:SetSize(24, 24)
		view.ready:SetPoint("CENTER", socket, "CENTER")
		LevelBadge(view, top, 16):SetPoint("CENTER", socket, "BOTTOMLEFT", 1, 1)

		-- The cast bar lies over the resource groove while a member casts.
		local g = cell.power
		view.cast = CastBar(root, g[3], g[4])
		view.cast:SetPoint("TOPLEFT", root, "TOPLEFT", g[1], -g[2])

		-- Auras outside the slab, to its right: debuffs, then your buffs under them.
		view.debuffAt = { "TOPLEFT", cell.size[1] + 4, -1 }
		view.buffAt = { "TOPLEFT", cell.size[1] + 4, -23 }
		Halos(view, root, "slab", L.glow, root)
	else
		Halos(view, root, "slab", L.petGlow, root)
	end

	view.SetLevels = function(base)
		socket:SetFrameLevel(base + 1)
		if view.model then view.model:SetFrameLevel(base + 2) end
		health:SetFrameLevel(base + 1)
		if view.liquid then view.liquid.clip:SetFrameLevel(base + 2) end
		view.heal:SetFrameLevel(base + 2)
		view.absorb:SetFrameLevel(base + 2)
		if view.power then view.power:SetFrameLevel(base + 1) end
		art:SetFrameLevel(base + 5)
		top:SetFrameLevel(base + 6)
		if view.levelBox then view.levelBox:SetFrameLevel(base + 7) end
		if view.cast then
			view.cast:SetFrameLevel(base + 3)
			view.cast.bar:SetFrameLevel(base + 3)
			view.cast.over:SetFrameLevel(base + 6) -- the name runs past the groove, over the metal
		end
	end
	return view
end

-- The frame's metal: gold on your target; else iron in the class colour (c), or plain iron when
-- there's none (pets). c's numbers may be secret, so a client that refuses them gets plain iron.
function S.SetMetal(view, gold, c)
	local hasArt = ns.Art.Path(view.style == "globes" and "partyGlobes" or "partySlab")
	for _, m in ipairs(view.metal) do
		if hasArt then m.tex:SetTexCoord(Coord(view.style, gold and m.gold or m.iron)) end
		local tinted = hasArt and not gold and c
			and pcall(m.tex.SetVertexColor, m.tex, c.r, c.g, c.b)
			and pcall(m.tint.SetVertexColor, m.tint, c.r, c.g, c.b)
		if not tinted then m.tex:SetVertexColor(1, 1, 1) end
		m.tint:SetShown(tinted and true or false)
	end
end

function S.Build(style, button, isPet)
	if style == "slab" then return S.BuildSlab(button, isPet) end
	return S.BuildGlobes(button, isPet)
end
