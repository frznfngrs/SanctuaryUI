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
--   view.heal/.hot/.absorb prediction StatusBars riding the fill (slab; globes use pool bands)
--   view.overShield      a glow for "more shield than room"
--   view.power           the resource StatusBar, or nil (pets)
--   view.name, .pct, .status   font strings (some nil)
--   view.nameOnBar       true when the name sits on the health fill
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
--   view.midY            the body's middle line from the top (globes; else half the height)
--   view.bodyW           the body's width, without the name to its right (globes; else size[1])
--   view.shiftable       what S.Shift moves right of the body (globes: name, cast bar)
--   view.isTarget        a member's target (S.BuildTarget): the pet frame plus name and marker
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
	ns.Fonts.Set(fs, d3 and "title" or "body", size, "OUTLINE")
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

-- With the portrait taken off: an empty frame where the socket was, at the frame's left end, so
-- the leader, role, marker, ready check and level badge keep their places around it.
local function StandIn(view, root, x, y, w, h)
	local socket = CreateFrame("Frame", nil, root)
	socket:SetSize(w, h)
	socket:SetPoint("TOPLEFT", root, "TOPLEFT", x, -y)
	socket:EnableMouse(false)
	view.socket = socket
	view.noPortrait = true
	return socket
end

-- A halo spec squeezed W units narrower, for a frame without its portrait.
local function Narrower(spec, W)
	if not W or W <= 0 then return spec end
	return { size = { spec.size[1] - W, spec.size[2] }, rect = spec.rect }
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
-- at: { x, w, h } to place it in part of the parent (a cut slab's halves), else all of it.
local function Metal(view, parent, slot, style, cell, sublevel, at)
	local tex = Piece(parent, "ARTWORK", slot, style, cell.iron, sublevel or 0)
	local tint = Piece(parent, "ARTWORK", slot, style, cell.iron, (sublevel or 0) + 1)
	for _, t in ipairs({ tex, tint }) do
		if at then
			t:SetPoint("TOPLEFT", parent, "TOPLEFT", at[1], 0)
			t:SetSize(at[2], at[3])
		else
			t:SetAllPoints()
		end
	end
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
		ns.Liquid.Band(view.pool, "hot")
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

function S.BuildGlobes(button, isPet, noPortrait)
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
	if not isPet and not noPortrait then
		local m = G.medallion
		padL = math.max(0, -(cell.size[1] / 2 + m.at[1] - m.size[1] / 2))
		padT = math.max(0, -(cell.size[2] / 2 + m.at[2] - m.size[2] / 2))
	end
	art:SetPoint("TOPLEFT", root, "TOPLEFT", padL, -padT)
	view.size = isPet and { cell.size[1], cell.size[2] } or { padL + cell.size[1] + 112, padT + cell.size[2] }
	view.midY = padT + cell.size[2] / 2 -- the bezel's middle, where a target frame lines up
	view.bodyW = padL + cell.size[1] -- the bezel's right edge; the name and auras run on from it

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

		-- The portrait medallion over the upper-left shoulder; without the portrait, an empty
		-- stand-in on the bezel's shoulder that the leader, role and level icons sit around.
		local m = G.medallion
		local medal = CreateFrame("Frame", nil, root)
		view.medal = medal
		local face
		if noPortrait then
			view.noPortrait = true
			medal:SetSize(22, 22)
			medal:SetPoint("CENTER", art, "TOPLEFT", 9, -9)
		else
			medal:SetSize(m.size[1], m.size[2])
			medal:SetPoint("CENTER", art, "CENTER", m.at[1], -m.at[2])
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
			face = Tex(holder, "ARTWORK")
			face:SetAllPoints()
			ns.Art.MaskCircle(face, holder)
			view.face = face
			Metal(view, medal, "partyGlobes", "globes", m, 1)
		end

		-- Health text in the globe, the name and the level to the right of the bezel.
		view.pct = Font(top, 12, false)
		view.pct:SetPoint("CENTER", globe, "CENTER", 0, -1)
		view.status = Font(top, 9, true)
		view.status:SetPoint("CENTER", globe, "CENTER", 0, -1)
		view.name = Font(top, 12, true)
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
		view.ready:SetPoint("CENTER", face or globe, "CENTER")
		-- Under the medallion, left of the globe's text (health, Dead, Offline) and above the pet.
		local badge = LevelBadge(view, top, 16)
		badge:SetPoint("CENTER", medal, "BOTTOM", -1, -1)
		if noPortrait then
			-- No medallion: the level on the bezel's upper-left rim, the crown just outside it and
			-- the role at the bezel's left side, all clear of the pet bolted on at the lower left.
			badge:ClearAllPoints()
			badge:SetPoint("CENTER", art, "TOPLEFT", 12, -12)
			view.leader:ClearAllPoints()
			view.leader:SetPoint("CENTER", art, "TOPLEFT", 0, 1)
			view.role:ClearAllPoints()
			view.role:SetPoint("CENTER", art, "TOPLEFT", -1, -34)
		end

		-- The cast bar, between the name and the debuffs.
		view.cast = CastBar(root, 92, 7, 11)
		-- The name and cast bar move right (Party.lua) when the member's target sits between.
		view.shiftable = { { view.name, art, 2, -10 }, { view.cast, art, 15, -22 } }
		S.Shift(view, 0)

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

-- Without the portrait the slab loses its socket: the right end cap (its studs and the grooves'
-- end rim), mirrored, closes its left end, and the slab picks up again where the grooves' insides
-- begin, so the cap's rim is their left rim too. cap: the end cap's width (from the grooves' end
-- to the cell's edge); from: where the slab picks up (units, from the cell's left).
local SLAB_CUT = { member = { cap = 6, from = 50 }, pet = { cap = 6, from = 26 } }

-- A slab layer (stone, iron, gold) as its mirrored end cap plus the rest from `from`: atlas rects
-- for the two parts and where they go.
local function SlabParts(rect, cut, h)
	local x, y, w, hh = rect[1], rect[2], rect[3], rect[4]
	return {
		{ { x + w, y, -cut.cap * 2, hh }, 0, cut.cap },
		{ { x + cut.from * 2, y, w - cut.from * 2, hh }, cut.cap, w / 2 - cut.from },
	}
end

function S.BuildSlab(button, isPet, noPortrait)
	local L = ns.Art.PARTY.slab
	local cell = isPet and L.pet or L.member
	local view = { style = "slab", metal = {} }
	local root = CreateFrame("Frame", nil, button)
	root:SetAllPoints()
	root:EnableMouse(false)
	view.root = root
	local cut = noPortrait and SLAB_CUT[isPet and "pet" or "member"]
	local W = cut and cut.from - cut.cap or 0 -- how much narrower it gets
	view.size = { cell.size[1] - W, cell.size[2] }

	if cut then
		local parts = {}
		for i, part in ipairs(SlabParts(cell.stone, cut)) do
			local t = Piece(root, "BACKGROUND", "partySlab", "slab", part[1])
			t:SetPoint("TOPLEFT", root, "TOPLEFT", part[2], 0)
			t:SetSize(part[3], cell.size[2])
			parts[i] = t
		end
		-- The opacity setting reaches both halves.
		view.stone = { SetAlpha = function(_, a) for _, t in ipairs(parts) do t:SetAlpha(a) end end }
	else
		local stone = Piece(root, "BACKGROUND", "partySlab", "slab", cell.stone)
		stone:SetAllPoints()
		view.stone = stone
	end

	-- The portrait in its socket: the 3D bust (square, so it fits uncropped), or the 2D one.
	local s = cell.socket
	local socket
	if cut then
		socket = StandIn(view, root, 0, 0, cut.cap, cell.size[2])
	else
		socket = CreateFrame("Frame", nil, root)
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
	end

	local h = cell.health
	if W > 0 then h = { h[1] - W, h[2], h[3], h[4] } end
	local health = Groove(root, h)
	health:SetPoint("TOPLEFT", root, "TOPLEFT", h[1], -h[2])
	local gback = Tex(health, "BACKGROUND")
	gback:SetAllPoints()
	gback:SetColorTexture(0.03, 0.015, 0.012, 0.9)
	view.health = health
	view.liquid = GrooveLiquid(health, h[3], h[4])
	view.heal = Band(health, health:GetStatusBarTexture(), 0.42, 1.0, 0.36, 0.6)
	view.hot = Band(health, view.heal:GetStatusBarTexture(), 0.72, 1.0, 0.6, 0.45)
	view.absorb = Band(health, view.hot:GetStatusBarTexture(), 0.8, 0.88, 1.0, 0.6)
	view.heal:SetWidth(h[3])
	view.hot:SetWidth(h[3])
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
		if W > 0 then p = { p[1] - W, p[2], p[3], p[4] } end
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
	if cut then
		local iron, gold = SlabParts(cell.iron, cut), SlabParts(cell.gold, cut)
		for i = 1, 2 do
			Metal(view, art, "partySlab", "slab", { iron = iron[i][1], gold = gold[i][1] }, 0,
				{ iron[i][2], iron[i][3], cell.size[2] })
		end
	else
		Metal(view, art, "partySlab", "slab", cell)
	end

	local top = CreateFrame("Frame", nil, root)
	top:SetAllPoints()
	top:EnableMouse(false)
	view.top = top
	local size = isPet and 9 or 12
	view.name = Font(top, size, true)
	view.name:SetPoint("LEFT", health, "LEFT", 4, 0.5)
	view.nameOnBar = true -- cream there when the fill is in the class colour (Party.lua UpdateName)
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
		view.cast:SetPoint("TOPLEFT", root, "TOPLEFT", g[1] - W, -g[2])

		-- Auras outside the slab, to its right: debuffs, then your buffs under them.
		view.debuffAt = { "TOPLEFT", view.size[1] + 4, -1 }
		view.buffAt = { "TOPLEFT", view.size[1] + 4, -23 }
		Halos(view, root, "slab", Narrower(L.glow, W), root)
	else
		Halos(view, root, "slab", Narrower(L.petGlow, W), root)
	end

	view.SetLevels = function(base)
		socket:SetFrameLevel(base + 1)
		if view.model then view.model:SetFrameLevel(base + 2) end
		health:SetFrameLevel(base + 1)
		if view.liquid then view.liquid.clip:SetFrameLevel(base + 2) end
		view.heal:SetFrameLevel(base + 2)
		view.hot:SetFrameLevel(base + 2)
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

---------------------------------------------------------------------------
-- The target frame's looks (ns.Art.PARTY.styled): Lintel, Slim Lintel, Forged Bracket and Tablet
-- (ns.Art.TARGET_STYLES, drawn by ns.Art.DrawTargetStyle) and D3's monster bar. The art, the
-- portrait and the grooves live in `root`, scaled down from the target's size, in the art's own
-- units; text, icons and the cast bar live in `top`, which undoes that scale, so they keep the
-- Slab's sizes. Your target gets the art's gold row (the monster bar: its gold laurel ring).

local STYLED = { lintel = true, slim = true, bracket = true, tablet = true, d3 = true }
S.STYLED = STYLED

-- A view's root at `scale` of the art's units, w x h of them, and its unscaled top layer.
local function StyledRoot(view, button, scale, w, h)
	local root = CreateFrame("Frame", nil, button)
	root:SetScale(scale)
	root:SetSize(w, h)
	root:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
	root:EnableMouse(false)
	view.root = root
	view.size = { w * scale, h * scale }
	local top = CreateFrame("Frame", nil, root)
	top:SetScale(1 / scale)
	top:SetAllPoints(root)
	top:EnableMouse(false)
	view.top = top
	return root, top
end

-- The threat halo, the gold one for your target and the dispel halo's box, over the art's whole
-- rect (x, y, w, h in root units), from party-styled.png.
local function StyledHalos(view, root, key, x, y, w, h)
	local rect = ns.Art.PARTY.styled.halos[key]
	local glow = Piece(root, "BACKGROUND", "partyStyled", "styled", rect, -8)
	glow:SetSize(w, h)
	glow:SetPoint("TOPLEFT", root, "TOPLEFT", x, -y)
	glow:SetBlendMode("ADD")
	glow:SetAlpha(0)
	view.glow = glow
	local chosen = Piece(root, "BACKGROUND", "partyStyled", "styled", rect, -7)
	chosen:SetSize(w * 1.06, h * 1.06)
	chosen:SetPoint("CENTER", glow, "CENTER")
	chosen:SetBlendMode("ADD")
	chosen:SetVertexColor(1, 0.74, 0.22)
	chosen:SetAlpha(0)
	view.select = chosen
	local box = CreateFrame("Frame", nil, root)
	box:SetSize(w, h)
	box:SetPoint("TOPLEFT", root, "TOPLEFT", x, -y)
	box:EnableMouse(false)
	view.glowBox = box
	view.glowRect = { slot = "partyStyled", style = "styled", rect = rect }
end

-- The health groove at x, y, w, h (root units): the fill, its liquid, heal and shield bands.
local function StyledHealth(view, root, x, y, w, h, well)
	local health = Groove(root, { x, y, w, h })
	health:SetPoint("TOPLEFT", root, "TOPLEFT", x, -y)
	local back = Tex(health, "BACKGROUND")
	back:SetAllPoints()
	if not (well and ns.Art.Apply(back, well)) then back:SetColorTexture(0.03, 0.015, 0.012, 0.9) end
	view.health = health
	view.liquid = GrooveLiquid(health, w, h)
	view.heal = Band(health, health:GetStatusBarTexture(), 0.42, 1.0, 0.36, 0.6)
	view.hot = Band(health, view.heal:GetStatusBarTexture(), 0.72, 1.0, 0.6, 0.45)
	view.absorb = Band(health, view.hot:GetStatusBarTexture(), 0.8, 0.88, 1.0, 0.6)
	view.heal:SetWidth(w)
	view.hot:SetWidth(w)
	view.absorb:SetWidth(w)
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
	return health
end

local function StyledPower(view, root, x, y, w, h)
	local power = Groove(root, { x, y, w, h })
	power:SetPoint("TOPLEFT", root, "TOPLEFT", x, -y)
	local back = Tex(power, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(0.03, 0.02, 0.015, 0.9)
	view.power = power
	return power
end

-- The portrait: a square socket (x0, y0, x1, y1), or round (cx, cy and the hole's diameter),
-- with a 3D bust for members (`model`, its square side for a round socket).
local function StyledSocket(view, root, p, isPet, modelSide)
	local socket = CreateFrame("Frame", nil, root)
	local back = Tex(socket, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(0.02, 0.015, 0.012, 1)
	view.face = Tex(socket, "ARTWORK")
	view.face:SetAllPoints()
	if p.round then
		socket:SetSize(p.hole, p.hole)
		socket:SetPoint("CENTER", root, "TOPLEFT", p.cx, -p.cy)
		ns.Art.MaskCircle(back, socket)
		ns.Art.MaskCircle(view.face, socket)
	else
		socket:SetSize(p[3] - p[1], p[4] - p[2])
		socket:SetPoint("TOPLEFT", root, "TOPLEFT", p[1], -p[2])
		view.squareFace = true
	end
	if not isPet then
		view.model = CreateFrame("PlayerModel", nil, root)
		if p.round then
			view.model:SetSize(modelSide, modelSide)
			view.model:SetPoint("CENTER", socket, "CENTER")
		else
			view.model:SetAllPoints(socket)
		end
	end
	view.socket = socket
	return socket
end

-- Name, health text and status in the health groove; leader, role, marker, ready check and the
-- level badge round the portrait.
local function StyledText(view, top, health, socket, isPet, nameWidth)
	view.name = Font(top, isPet and 9 or 12, true)
	view.name:SetJustifyH("LEFT")
	view.status = Font(top, isPet and 8 or 10, true)
	if isPet then
		view.name:SetPoint("BOTTOMLEFT", health, "TOPLEFT", 1, 1)
		view.name:SetWidth(nameWidth)
		view.status:SetPoint("BOTTOMRIGHT", health, "TOPRIGHT", 0, 1)
		return
	end
	view.name:SetPoint("LEFT", health, "LEFT", 4, 0.5)
	view.name:SetWidth(nameWidth)
	view.nameOnBar = true
	view.status:SetPoint("RIGHT", health, "RIGHT", -4, 0.5)
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
end

-- Frame levels, back to front: halos (the root's own), art, portrait and grooves, the model
-- and the grooves' liquid and bands, a frame drawn over them (bracket ring, D3's bar), text.
local function StyledLevels(view, parts)
	return function(base)
		if parts.art then parts.art:SetFrameLevel(base + 1) end
		view.socket:SetFrameLevel(base + 2)
		view.health:SetFrameLevel(base + 2)
		if view.power then view.power:SetFrameLevel(parts.powerOver and base + 3 or base + 2) end
		if view.model then view.model:SetFrameLevel(base + 3) end
		if view.liquid then view.liquid.clip:SetFrameLevel(base + 3) end
		view.heal:SetFrameLevel(base + 3)
		view.hot:SetFrameLevel(base + 3)
		view.absorb:SetFrameLevel(base + 3)
		if parts.over then parts.over:SetFrameLevel(base + 4) end
		if parts.frameBox then parts.frameBox:SetFrameLevel(base + 4) end
		if view.cast then
			view.cast:SetFrameLevel(base + 5)
			view.cast.bar:SetFrameLevel(base + 5)
			view.cast.over:SetFrameLevel(base + 6)
		end
		view.top:SetFrameLevel(base + 6)
		if view.levelBox then view.levelBox:SetFrameLevel(base + 7) end
	end
end

-- Lintel, Slim Lintel, Forged Bracket or Tablet for a member; pets get the target of target frame.
local function BuildRendered(name, button, noPortrait)
	local C = ns.Art.PARTY.styled
	local st = ns.Art.TargetStyleSized(name, 1, 1)
	local roundPortrait = st.portrait.round
	-- Without the portrait: the socket (the Bracket's ring) cut out of the art.
	local cutStyle = noPortrait and ns.Art.TargetStyleCut(st)
	if cutStyle then st = cutStyle end
	local view = { style = name, metal = {} }
	local k = C.scale
	local root, top = StyledRoot(view, button, k, st.size[1], st.size[2])
	local art = CreateFrame("Frame", nil, root)
	art:SetAllPoints(root)
	art:EnableMouse(false)
	view.art = art
	ns.Art.DrawTargetStyle(art, st, "normal")

	local p = st.portrait
	local socket
	local over
	if cutStyle then
		socket = StandIn(view, root, 0, 0, 12, st.size[2])
	else
		local round = p.round and { round = true, cx = p.cx, cy = p.cy, hole = p.hole * 2 + 2 } or p
		socket = StyledSocket(view, root, round, false, p.round and p.model)
		if p.round then
			-- The Bracket's ring, over the bust so its corners hide.
			over = CreateFrame("Frame", nil, root)
			over:SetSize(140, 140)
			over:SetPoint("CENTER", socket, "CENTER")
			over:EnableMouse(false)
			view.ring = over:CreateTexture(nil, "OVERLAY")
			view.ring:SetAllPoints()
			if ns.Art.Apply(view.ring, "targetStyleParts") then
				view.ring:SetTexCoord(ns.Art.TargetPartTexCoord("ring", "normal"))
			end
		end
	end
	local b = st.bar
	local health = StyledHealth(view, root, b[1], b[2], b[3] - b[1], b[4] - b[2])
	local pw = st.power
	local power = StyledPower(view, root, pw[1], pw[2], pw[3] - pw[1], pw[4] - pw[2])
	StyledText(view, top, health, socket, false, (b[3] - b[1]) * k - 44)
	-- The cast bar: in the style's cast groove, else over the resource groove.
	local g = st.castGroove or st.power
	view.cast = CastBar(top, (g[3] - g[1]) * k, (g[4] - g[2]) * k)
	view.cast:SetPoint("TOPLEFT", root, "TOPLEFT", g[1] * k, -g[2] * k)
	view.debuffAt = { "TOPLEFT", view.size[1] + 4, -1 }
	view.buffAt = { "TOPLEFT", view.size[1] + 4, -23 }
	-- A cut-out ring would leave its bump in the halo: the Slim's plain bar halo instead.
	local haloKey = (cutStyle and roundPortrait) and "slim" or name
	StyledHalos(view, root, haloKey, st.art[1], st.art[2], st.art[3], st.art[4])

	view.SetMetal = function(gold)
		gold = gold and true or false
		if view.gold == gold then return end
		view.gold = gold
		local rank = gold and "elite" or "normal"
		ns.Art.DrawTargetStyle(art, st, rank)
		if view.ring and ns.Art.Path("targetStyleParts") then
			view.ring:SetTexCoord(ns.Art.TargetPartTexCoord("ring", rank))
		end
	end
	view.SetLevels = StyledLevels(view, { art = art, over = over })
	return view
end

-- D3's monster bar for a member: the hero portrait ring, the bar frame drawn over its fill, the
-- resource a strip along the fill's foot.
local function BuildMonsterBar(button, noPortrait)
	local C = ns.Art.PARTY.styled
	local L = C.d3
	local view = { style = "d3", metal = {} }
	local k = C.d3scale
	local piece = ns.Art.UNIT.normal
	-- Without the portrait the ring goes, and the bar frame moves to the top left corner.
	local fx, fy = L.frame[1], L.frame[2]
	local w, h = L.size[1], L.size[2]
	if noPortrait then fx, fy, w, h = 0, 0, piece[3], piece[4] + 11 end
	local root, top = StyledRoot(view, button, k, w, h)
	local over = CreateFrame("Frame", nil, root)
	over:SetAllPoints(root)
	over:EnableMouse(false)
	local socket
	if noPortrait then
		socket = StandIn(view, root, 0, 0, 24, piece[4])
	else
		local hole = ns.Art.TARGET_RING_HOLE + 2
		socket = StyledSocket(view, root, { round = true, cx = L.ring[1], cy = L.ring[2], hole = hole }, false, 46)
		local cell = ns.Art.TARGET_RING_CELL
		view.ring = over:CreateTexture(nil, "OVERLAY")
		view.ring:SetSize(cell, cell)
		view.ring:SetPoint("CENTER", socket, "CENTER")
		if ns.Art.Apply(view.ring, "targetRings") then
			view.ring:SetTexCoord(ns.Art.TargetRingTexCoord("normal"))
		end
	end
	local box = CreateFrame("Frame", nil, over)
	box:SetSize(piece[3], piece[4])
	box:SetPoint("TOPLEFT", root, "TOPLEFT", fx, -fy)
	box:EnableMouse(false)
	ns.Art.DrawSliced(box, "normal", piece[3], 1)
	view.art = box
	local bar = piece.bar
	local x, y = fx + bar[1], fy + bar[2]
	local health = StyledHealth(view, root, x, y, bar[3], bar[4], "unitWell")
	StyledPower(view, root, x, y + bar[4] - 4, bar[3], 4)
	StyledText(view, top, health, socket, false, bar[3] * k - 44)
	-- The cast bar under the frame.
	view.cast = CastBar(top, bar[3] * k, 7 * k)
	view.cast:SetPoint("TOPLEFT", root, "TOPLEFT", x * k, -(fy + piece[4] + 2) * k)
	view.debuffAt = { "TOPLEFT", view.size[1] + 4, -1 }
	view.buffAt = { "TOPLEFT", view.size[1] + 4, -23 }
	local bx = L.box
	if noPortrait then
		StyledHalos(view, root, "slim", -14, -14, piece[3] + 28, piece[4] + 28)
	else
		StyledHalos(view, root, "d3", bx[1], bx[2], bx[3], bx[4])
	end

	view.SetMetal = function(gold)
		gold = gold and true or false
		if view.gold == gold then return end
		view.gold = gold
		if view.ring and ns.Art.Path("targetRings") then
			view.ring:SetTexCoord(ns.Art.TargetRingTexCoord(gold and "elite" or "normal"))
		end
	end
	view.SetLevels = StyledLevels(view, { over = over, frameBox = box, powerOver = true })
	return view
end

-- A pet in any of these looks: the rendered styles' target of target frame, a small ring and bar.
local function BuildStyledPet(name, button, noPortrait)
	local C = ns.Art.PARTY.styled
	local st = ns.Art.TargetStyleSized(ns.Art.TARGET_TOT_STYLE, 1, 1)
	local cutStyle = noPortrait and ns.Art.TargetStyleCut(st)
	if cutStyle then st = cutStyle end
	local view = { style = name, metal = {} }
	local k = C.pet.scale
	local root, top = StyledRoot(view, button, k, st.size[1], st.size[2])
	local art = CreateFrame("Frame", nil, root)
	art:SetAllPoints(root)
	art:EnableMouse(false)
	view.art = art
	ns.Art.DrawTargetStyle(art, st, "normal")
	local p = st.portrait
	local socket
	if cutStyle then
		socket = StandIn(view, root, 0, 0, 8, st.size[2])
	else
		socket = StyledSocket(view, root, { round = true, cx = p.cx, cy = p.cy, hole = 23 }, true)
	end
	local b = st.bar
	local health = StyledHealth(view, root, b[1], b[2], b[3] - b[1], b[4] - b[2])
	StyledText(view, top, health, socket, true, (b[3] - b[1]) * k - 24)
	StyledHalos(view, root, cutStyle and "slim" or "tot", st.art[1], st.art[2], st.art[3], st.art[4])
	view.SetLevels = StyledLevels(view, { art = art })
	return view
end

function S.BuildStyled(style, button, isPet, noPortrait)
	if isPet then return BuildStyledPet(style, button, noPortrait) end
	if style == "d3" then return BuildMonsterBar(button, noPortrait) end
	return BuildRendered(style, button, noPortrait)
end

-- The frame's metal: gold on your target; else iron in the class colour (c), or plain iron when
-- there's none (pets). c's numbers may be secret, so a client that refuses them gets plain iron.
-- The target styles' art is drawn whole, so they only swap to their gold row.
function S.SetMetal(view, gold, c)
	if view.SetMetal then return view.SetMetal(gold, c) end
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

-- noPortrait: the frame without its portrait (Options > Party), narrower where the art allows.
function S.Build(style, button, isPet, noPortrait)
	if button.isTarget then return S.BuildTarget(style, button, noPortrait) end
	return S.BuildFrame(style, button, isPet, noPortrait)
end

-- Moves what runs right of a globe member's bezel (name, cast bar) by dx, for a target frame
-- placed straight after it. The auras move with Party.lua's own shift.
function S.Shift(view, dx)
	for _, item in ipairs(view.shiftable or {}) do
		item[1]:ClearAllPoints()
		item[1]:SetPoint("TOPLEFT", item[2], "TOPRIGHT", item[3] + dx, item[4])
	end
end

-- A member's target: the style's pet frame, plus its raid marker and, on the globes (whose pet
-- has no name), the name to the right of the globe.
function S.BuildTarget(style, button, noPortrait)
	local view = S.BuildFrame(style, button, true, noPortrait)
	view.isTarget = true
	local top = view.top
	if not view.name then
		view.name = Font(top, 10, true)
		view.name:SetPoint("LEFT", view.art, "RIGHT", 2, 0)
		view.name:SetWidth(96)
		view.name:SetJustifyH("LEFT")
		view.size = { view.size[1] + 98, view.size[2] }
	end
	view.mark = Tex(top, "OVERLAY", 2)
	view.mark:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
	view.mark:SetSize(14, 14)
	view.mark:SetPoint("CENTER", view.socket or view.art, "TOPLEFT", 2, -2)
	view.mark:Hide()
	return view
end

function S.BuildFrame(style, button, isPet, noPortrait)
	-- "ring": the small ring and bar that the target looks give pets, picked for a target alone.
	if STYLED[style] or style == "ring" then return S.BuildStyled(style, button, isPet, noPortrait) end
	if style == "slab" then return S.BuildSlab(button, isPet, noPortrait) end
	return S.BuildGlobes(button, isPet, noPortrait)
end
