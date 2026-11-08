SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.Art = ns.Art or {}

-- Party frame art: the contract between the art build (tools/blender/party_*.py, run by
-- tools/build_hud_art.py party) and Party.lua. The art is rendered at 2x: an atlas rect in
-- pixels is twice its size in UI units. Every place below is in UI units at scale 1, measured
-- from the cell's top-left corner, x right and y DOWN (as an image is read).
--
-- Rects are { x, y, w, h } in atlas pixels; circles are { cx, cy, d } in units.

ns.Art.slots.partyGlobes = { file = "party-globes.png" }
ns.Art.slots.partyCrescent = { file = "party-crescent.png" } -- the resource groove's fill, a whole file (StatusBar texture)
ns.Art.slots.partySlab = { file = "party-slab.png" }
ns.Art.slots.partyAura = { file = "party-aura.png" }

ns.Art.PARTY = {
	-- Concept 1, the default: a small health globe in a forged iron bezel, the resource a
	-- crescent groove cut into the bezel's right side, the portrait in a medallion on its
	-- upper-left shoulder, the pet a small globe bolted to its lower left, under it.
	globes = {
		atlas = { 512, 512 },
		bezel = {
			size = { 76, 76 },
			iron = { 0, 0, 152, 152 },
			gold = { 152, 0, 152, 152 },
			globe = { 38, 38, 52 }, -- the liquid's circle
			resource = { 63.5, 17.5, 10, 41 }, -- bounding box of the crescent groove's inside (party-crescent.png fills it, bottom-up)
		},
		medallion = {
			size = { 40, 40 },
			iron = { 304, 0, 80, 80 },
			gold = { 384, 0, 80, 80 },
			hole = { 20, 20, 30 }, -- round 2D portrait
			at = { -26, -22 }, -- its centre from the bezel's centre (x right, y down)
		},
		pet = {
			size = { 44, 44 },
			iron = { 304, 80, 88, 88 },
			gold = { 392, 80, 88, 88 },
			globe = { 22, 22, 30 },
			at = { -28, 30 }, -- its centre from the bezel's centre
		},
		-- Soft white halos drawn ADD and tinted: threat red, a debuff you can dispel by its type.
		glow = { size = { 96, 96 }, rect = { 0, 160, 192, 192 } }, -- centred on the bezel
		petGlow = { size = { 56, 56 }, rect = { 200, 160, 112, 112 } }, -- centred on the pet
	},

	-- Concept 2 (the Slim slab): a thin slab of D3 stone per member, iron corner caps, the
	-- portrait in a square socket at the left, health and resource as grooves. The stone is its
	-- own layer so its opacity can go down to the Ghost look; the metal stays solid.
	slab = {
		atlas = { 512, 1024 },
		member = {
			size = { 220, 44 },
			stone = { 0, 0, 440, 88 },
			iron = { 0, 88, 440, 88 }, -- caps, socket rim and groove lips; transparent elsewhere
			gold = { 0, 176, 440, 88 },
			socket = { 5, 4, 36, 36 }, -- the portrait's opening (x, y, w, h in units)
			health = { 50, 6, 164, 20 }, -- the health groove's inside
			power = { 50, 31, 164, 6 }, -- the resource groove's inside
		},
		pet = {
			size = { 150, 24 },
			stone = { 0, 264, 300, 48 },
			iron = { 0, 312, 300, 48 },
			gold = { 0, 360, 300, 48 },
			socket = { 3, 3, 18, 18 },
			health = { 26, 5, 118, 14 },
			gap = 2, -- below its owner's slab
			indent = 24, -- from its owner's left edge
		},
		glow = { size = { 240, 64 }, rect = { 0, 408, 480, 128 } }, -- centred on the member slab
		petGlow = { size = { 165, 39 }, rect = { 0, 536, 330, 78 } },
	},

	-- Aura frames: D3's buff frame (gold, your buffs) and its debuff frame made neutral grey so
	-- the client can tint it by dispel type. inset: the icon's share of the frame on each side.
	aura = {
		atlas = { 128, 64 },
		debuff = { 0, 0, 64, 64 },
		buff = { 64, 0, 64, 64 },
		inset = 4 / 64,
	},
}

-- Texcoords of an atlas rect.
function ns.Art.PartyCoord(style, rect)
	local atlas = ns.Art.PARTY[style].atlas
	return rect[1] / atlas[1], (rect[1] + rect[3]) / atlas[1], rect[2] / atlas[2], (rect[2] + rect[4]) / atlas[2]
end
