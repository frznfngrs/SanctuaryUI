SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.MiningData = ns.MiningData or {}
local D = ns.MiningData

-- Rock Bottom's book: WoW Forever (1.60.1) mining, in the miner's own words. A memoir that
-- sinks a little lower with every vein.
--
-- MiningNodes.lua (veins, spots, maps) and MiningRecipes.lua (smelts, ranks, people) are
-- generated from the game install and GatherLite by tools/build_mining_data.py. This file is
-- everything a database can't know: what a vein gives and what it's like, the road to 300,
-- the forges, the gems and stone, the kit, the camp, the tales, and the memoir's own lines.
--
-- Sources (November 2026): warcraft.wiki.gg (Forever_mining_techniques and item pages),
-- warcrafttavern.com/forever, wow-professions.com/forever, wow.gg, timesaver.gg, and Wowhead's
-- Forever tooltips. Single-source claims live in TALL_TALES.
--
-- The jokes here are the miner's own. None borrows the Angler's journal's or the Cookbook's.

---------------------------------------------------------------------------
-- The veins: what each gives, a line about it, and where the maps can't help.
-- gives (text), ore { item IDs } (counted as ore in the tally), where (when the maps have no
-- spots, or a word to add), note (the miner's aside).

D.YIELD = {
	copper_vein = { ore = { 2770 }, gives = "Copper Ore and Rough Stone; Malachite, Tigerseye and Shadowgem now and then; Pyrite, rarely.",
		where = "The starting areas also grow Poor Copper Veins: copper for people who've never held a pick, good to 20.",
		note = "The vein everybody starts on and nobody admits to missing." },
	tin_vein = { ore = { 2771 }, gives = "Tin Ore and Coarse Stone; Moss Agate, Shadowgem, Jade and Lesser Moonstone; Pyrite, rarely.",
		note = "Half of every Bronze Bar. Tin's whole career is being the other half." },
	silver_vein = { ore = { 2775 }, gives = "Silver Ore; Moss Agate, Shadowgem and Lesser Moonstone; Pyrite, rarely.",
		note = "Grows alone among the Tin, like a coin in a sofa. You'll walk past forty Tin to find one." },
	incendicite_mineral_vein = { ore = { 3340 }, gives = "Incendicite Ore, for a Wetlands quest; Pyrite, rarely.",
		note = "Twenty-nine of them in one Wetlands cave, warm to the touch. Thelgen Rock: bring a light." },
	lesser_bloodstone_deposit = { ore = { 4278 }, gives = "Lesser Bloodstone Ore, for a Stromgarde quest in the Arathi Highlands.",
		note = "A quest ore with a name like a ballad. The ballad is about errands." },
	iron_deposit = { ore = { 2772 }, gives = "Iron Ore and Heavy Stone; Jade, Lesser Moonstone, Citrine and Aquamarine; Pyrite, rarely.",
		note = "The first vein that feels like work. It's also the first that pays like it." },
	gold_vein = { ore = { 2776 }, gives = "Gold Ore; Jade, Lesser Moonstone and Citrine; Bauxite, rarely.",
		note = "As rare as it should be, and much rarer than you'd like." },
	mithril_deposit = { ore = { 3858 }, gives = "Mithril Ore and Solid Stone; Citrine, Aquamarine, Star Ruby and Black Vitriol; Bauxite, rarely.",
		note = "Light in the hand, heavy on the market. Every engineer in Azeroth wants it yesterday." },
	truesilver_deposit = { ore = { 7911 }, gives = "Truesilver Ore; Citrine, Aquamarine and Star Ruby; Pitchblende, rarely.",
		note = "Grows where Mithril does, but less often, and looks smug about it." },
	dark_iron_deposit = { ore = { 11370 }, gives = "Dark Iron Ore; Black Vitriol, Blood of the Mountain and Black Diamond; Pitchblende, rarely.",
		where = "Inside Blackrock Depths and Molten Core too, where the maps can't follow.",
		note = "Only Searing Gorge and the Burning Steppes, on the doorstep of the people who own it." },
	small_thorium_vein = { ore = { 10620 }, gives = "Thorium Ore and Dense Stone; Star Ruby, Black Vitriol, Blue Sapphire, Large Opal and Azerothian Diamond; Pitchblende, rarely.",
		note = "The workhorse of the high end. Un'Goro's caves are full of it and of things with teeth." },
	rich_thorium_vein = { ore = { 10620 }, gives = "More Thorium Ore and Dense Stone; Star Ruby, Blue Sapphire, Large Opal, Arcane Crystal, Huge Emerald and Azerothian Diamond; Pitchblende, rarely.",
		note = "Slow to come back. When one shows, so do four other miners." },
	heavy_thorium_vein = { ore = { 248815 }, gives = "Heavy Thorium Ore and Dense Stone; Torbernite and Fel Crystal; Pitchblende, rarely.",
		note = "New in Forever. A Rich Thorium Vein in a coat of green fel smoke, in Mount Hyjal near the Scourge. Rare, and you'll smell it first." },
	chunk_of_amber = { ore = { 2770 }, gives = "Copper Ore, a Fossilized Insect and a Tuft of Hair.",
		note = "New in Forever: night elves can learn to mine at home, on Teldrassil. Teaches to 20. The bug inside was here first." },
	large_chunk_of_amber = { ore = { 2770 }, gives = "As a Chunk of Amber, with a little Pyrite.",
		note = "New in Forever, on Teldrassil. Bigger lump, same bug, more resentment." },
	indurium_mineral_vein = { ore = { 5833 }, gives = "Indurium Ore; Bauxite, rarely.",
		where = "Only inside Uldaman, where the maps can't place it." },
	hakkari_thorium_vein = { ore = { 10620 }, gives = "Thorium Ore, Souldarite and gems.",
		where = "Only inside Zul'Gurub, where the maps can't place it." },
	small_obsidian_chunk = { ore = { 22202 }, gives = "Small Obsidian Shards.",
		where = "Ahn'Qiraj: certain monsters leave one when they die. Bring Mining gear past 305.",
		note = "A rock that drops off a monster. Mining's strangest week." },
	large_obsidian_chunk = { ore = { 22203 }, gives = "Large Obsidian Shards.",
		where = "Ahn'Qiraj, the same way: off certain monsters, past 305 with Mining gear." },
	cold_iron_deposit = { ore = { 219401 }, gives = "Cold Iron Ore (\"Ephemeral and unstable.\"), Heavy Stone and gems." },
	fools_gold_vein = { ore = { 219445 }, gives = "Fool's Gold Dust and gems." },
	starsilver_vein = { ore = { 219486 }, gives = "Starsilver Ore (\"Ephemeral and unstable.\")." },
	greater_moonstone_formation = { ore = { 219515 }, gives = "Greater Moonstone." },
}

-- Each vein's code in shared finds (MiningShare.lua: group messages, export strings, and
-- tools/build_mining_data.py's merge). Two letters, never reused: a vein added later gets a new
-- code, so old strings keep their meaning.
D.CODE = {
	copper_vein = "cu", tin_vein = "sn", silver_vein = "ag", iron_deposit = "fe", gold_vein = "au",
	mithril_deposit = "mi", truesilver_deposit = "ts", dark_iron_deposit = "di", small_thorium_vein = "th",
	rich_thorium_vein = "rt", heavy_thorium_vein = "ht", incendicite_mineral_vein = "ic",
	lesser_bloodstone_deposit = "bl", indurium_mineral_vein = "id", hakkari_thorium_vein = "hk",
	small_obsidian_chunk = "so", large_obsidian_chunk = "lo", chunk_of_amber = "am", large_chunk_of_amber = "la",
}

-- Forever's own veins, marked (new) on the page.
D.FOREVER = { heavy_thorium_vein = true, chunk_of_amber = true, large_chunk_of_amber = true }

-- Veins the game's tables and Wowhead list for Forever that came from Season of Discovery's
-- Nightmare Incursions. Nothing says they spawn here. Kept apart on the page and out of the
-- advice; the miner's line about each.
D.GHOST = {
	cold_iron_deposit = "Season of Discovery's, from Duskwood's nightmares. The tables still list it; nobody's swung at one here.",
	fools_gold_vein = "Season of Discovery's, from eastern Ashenvale. If you find one in Forever, the name is about you.",
	starsilver_vein = "Season of Discovery's, from the Hinterlands. A vein made of starlight and paperwork.",
	greater_moonstone_formation = "Season of Discovery's, from northern Feralas. Wowhead's own card says it may not be in Forever.",
}

-- Whose land a zone is, where the Angler's journal doesn't say.
D.ZONE_SIDE = {
	["Thunder Bluff"] = "H", ["Zephras Isle"] = "N", ["Shen'dralas"] = "N", ["Mount Hyjal"] = "N", ["Riverglades"] = "N",
}

---------------------------------------------------------------------------
-- The trade: ranks, the road to 300.

-- name, cap, what it takes. Mining's ranks ask no character level (the trainers' own data).
D.RANKS = {
	{ "Apprentice", 75, "Any mining trainer, 10c. The junior trainers in the starting areas teach only this, and no smelting." },
	{ "Journeyman", 150, "From skill 50, 5s at a full trainer." },
	{ "Expert", 225, "From skill 125, 50s." },
	{ "Artisan", 300, "From skill 200, 5g. You can't pass 225 without it. 300 is Forever's cap." },
}

-- The levelling guide (The Way Down): two roads. Each step: { from, to, A = text, H = text (or
-- N for both sides), need = { { itemID, count } } (counted against your bags), lines = { text, or
-- { text, side = "A"|"H" } for one side only } }. The step you're on is marked on the page.
-- Facts: wow-professions.com/forever/mining-leveling-guide (routes, caves, smelting), its
-- mining-changes and mining-trainers pages, warcrafttavern.com/forever/guides/mining (November
-- 2026). Cave positions are read off those guides' maps: near enough to find the mouth.
D.GUIDE = {
	smelt = {
		title = "The shortcut: smelting to 105",
		upto = 120, -- shown until you're past it
		intro = {
			"Gold instead of time: buy ore at the auction house and smelt your way past the first hundred. Bars often sell for about what the ore cost, so you lose less than it looks.",
			"Smelting runs mostly yellow and green, so bring a few spare ore in case luck is against you.",
		},
		after = "You're past the smelting shortcut. Smelting still pays later: Iron to 135, Gold from 155 to 170, Azerothium from 275.",
		steps = {
			{ 1, 65, N = "Smelt Copper, 120 to 140 times. Keep 70 of the bars: Bronze wants them.",
				need = { { 2770, 140 } } },
			{ 65, 75, N = "Train Journeyman, Smelt Tin and Smelt Bronze. Then smelt 70 Tin Bars, all of them, even after Tin turns grey at 75: Bronze needs every one.",
				need = { { 2771, 70 } } },
			{ 75, 105, N = "Smelt Bronze from your Copper and Tin Bars, 70 times. You'll land between 100 and 110.",
				need = { { 2840, 70 }, { 3576, 70 } } },
			{ 105, 120, N = "Smelt Silver, 35 to 45 times, if Silver Ore is cheap enough. Look at the prices first: this step can cost.",
				need = { { 2775, 45 } },
				lines = { "The last five points to 125 eat about 50 more Silver Ore. From 120, go mining: with +5 from gear you can already take Iron." } },
		},
	},
	mine = {
		title = "The long way down: mining 1 to 300",
		intro = {
			"Veins grow back faster when more people are about, and in Forever the mobs do too: out-level a zone before you strip it, or they'll be back on top of you.",
			"Gear that adds Mining (Pick & Kit) is never needed, but +5 bridges a gap: Iron at 120 instead of 125.",
		},
		steps = {
			{ 1, 65,
				A = "Elwynn Forest: back and forth across the south, from Forest's Edge east to the Duskwood border. Fargodeep Mine (about 39, 81) grows back fast enough to stay inside. Smelt at Goldshire.",
				H = "Durotar: two laps, an S through the hills west of Razor Hill, then the east coast up toward Orgrimmar. Smelt at Razor Hill.",
				lines = {
					{ "Or Dun Morogh: loops round Brewnall Village and the hills west of Kharanos; smelt at Kharanos.", side = "A" },
					{ "Or Teldrassil's two caves, Ban'ethil Barrow Den (about 43, 58) and Fel Rock (about 54, 52): they grow back almost as you watch. The nearest forge is the Warrior's Terrace in Darnassus.", side = "A" },
					{ "Or Mulgore's cave on the west cliffs (about 34, 69): five Copper Veins, back fast enough to stay inside. The forge is at Bael'dun Digsite just north, among hostile dwarves.", side = "H" },
					{ "Or Tirisfal: a loop round Agamand Mills west of Brill, or the quieter hills near the Scarlet Monastery; smelt at Brill.", side = "H" },
					"Zephras Isle suits both sides: a small loop by the lake south of Shen'dar Village. Harvesting Windstones in Thendal Village rewards Mining for Dummies, which teaches you Mining.",
					"Poor Copper Veins in the starting areas, and Teldrassil's amber, teach only to 20. Buy a Mining Pick before you start.",
				} },
			{ 65, 125,
				A = "The Wetlands: Thelgen Rock (about 53, 63) is full of Tin and Incendicite and grows back fast. The mobs are around level 20.",
				H = "Silverpine Forest: the cave south of Ambermill (about 60, 72). Three veins, back in about two minutes: mine, wait, mine. The mobs are 21 to 22.",
				lines = {
					{ "Or Westfall's Gold Coast Quarry (about 31, 45): plenty of Tin inside and out, mobs 13 to 15.", side = "A" },
					{ "Or a lap of the Hillsbrad Foothills round Tarren Mill (busy), the Barrens north of Razorfen Kraul (mobs 22 to 26), Ashenvale, or Stonetalon Peak, where nobody goes and an Iron Deposit sometimes turns up.", side = "H" },
					"Train Journeyman at 50: the junior trainers can't. Smelt leftover Copper and Tin into Bronze first; it stops teaching around 105.",
				} },
			{ 125, 175,
				N = "Iron and Gold. Thousand Needles is the safest, around level 30: loops round the western needles and Freewind Post.",
				lines = {
					"Higher, or mounted: the Arathi Highlands, with four caves, about 35, 44 and 53, 77, Witherbark Village (69, 76), and east of Hammerfall (82, 35). Go to the end of each; at a low level, leave them all.",
					{ "Low-level Alliance in Arathi: swing south of Hammerfall.", side = "A" },
					"Or Desolace: one long route by Thunder Axe Fortress, the Kodo Graveyard and Gelkis, no caves.",
					"Train Expert at 125. Smelting about 20 Iron Ore takes you to 135; from 155, about 22 Gold Ore takes you to 175, a point a bar until 170.",
				} },
			{ 175, 245,
				N = "Mithril, then Truesilver from 230: a loop through the south and middle of the Hinterlands, with a cave at about 58, 40.",
				lines = {
					"The Hinterlands' north, round Seradane, has level 62 elites: leave it until you can.",
					"Or Tanaris: a loop round the Abyssal Sands from Gadgetzan, with four caves (about 35, 43; 34, 48; 55, 69; 54, 76). Below level 60, skip the caves.",
					"Train Artisan at 200: past 225 needs it. From 230, Dark Iron in Searing Gorge and the Burning Steppes is good to about 245.",
				} },
			{ 245, 275,
				N = "Small Thorium: all of Un'Goro Crater, Fire Plume Ridge too. Its caves east of Marshal's Refuge (about 64, 17) and in the south (about 50, 80) hold two or three veins each.",
				lines = {
					"Or the Blasted Lands, from Dreadmaul Hold down to the Dark Portal. Both caves, the Garrison Armory (about 58, 14) and another at about 66, 33, are crowded: be 60, well geared, or stealthy.",
					{ "Alliance can't mine inside the Garrison Armory.", side = "A" },
					"Or Felwood, from the Emerald Sanctuary north to Winterspring's edge. The Irontree cave (about 56, 17) is small, quiet and usually holds two veins. Skip the Jaedenar caves, Shadow Hold worst of all, without stealth.",
				} },
			{ 275, 300,
				N = "Rich Thorium joins the Small: Un'Goro again, or the Eastern Plaguelands by Corin's Crossing and the north. It's rare, so smelt Azerothium between veins (2 Pitchblende and a Coal, from 275).",
				lines = {
					"Tyr's Hand in the Eastern Plaguelands has level 57 to 58 elites: skip it in poor gear.",
					"Or Winterspring, from Frostsaber Rock past Starfall and Everlook, then south. The cave east of Everlook (about 68, 41) is easy; the one south-west (about 57, 50) mostly; the gorge at about 60, 65 has patrolling elites. Leave Darkwhisper Gorge alone.",
					"Or the Burning Steppes, snaking east from Blackrock Mountain; the Dreadmaul Rock caves (about 77, 48 and 83, 39) are full of level 50 mobs.",
					"Guides disagree on Rich Thorium: one mines it from 275, another says it only turns up often enough from 295.",
				} },
			{ 300, 300,
				N = "Heavy Thorium: a rare vein in Mount Hyjal, a Rich Thorium wrapped in green fel smoke. Smelt it at a Molten Foundry, not a forge.",
				lines = { "The Molten Foundry is a camp blueprint (Pick & Kit)." } },
		},
	},
}

D.OTHER_TRAINERS = "And {n} {side} trainers, who would sooner teach a kobold the trade."

---------------------------------------------------------------------------
-- The smelter.

-- Where a smelt is learned, when the tables can't say it well. By the bar's item ID.
D.LEARN = {
	[279960] = "Any mining trainer (1s), or the quest Camping 101: Mining from your starting area's adventurer.",
	[279948] = "Blueprint: Rock Garden, from the Relic Guardian at the end of Excavation Site: Wetlands (about 7%), or from another player.",
	[279952] = "Blueprint: Molten Foundry, from Ambassador Flamelash in Blackrock Depths (about 4%), or from another player.",
	[11371] = "Gloom'rel teaches it in Blackrock Depths' Summoners' Tomb, after The Spectral Chalice (20 Gold Bars, 10 Truesilver Bars, 2 Star Rubies).",
	[17771] = "From the book Goblin's Guide to Elementium, dropped by Master Elemental Shaper Krixix in Blackwing Lair.",
}

-- What a bar is for. By name.
D.SMELT_NOTES = {
	["Copper Bar"] = "Smithing, engineering, and half of Bronze.",
	["Tin Bar"] = "Mostly the other half of Bronze.",
	["Bronze Bar"] = "One Copper Bar and one Tin Bar make two. The cheap road to skill.",
	["Silver Bar"] = "Smiths, and one goes into the Rock Garden.",
	["Iron Bar"] = "The backbone of mid-level smithing. Add Coal for Steel.",
	["Gold Bar"] = "Twenty go into The Spectral Chalice for Dark Iron.",
	["Steel Bar"] = "An Iron Bar and a Coal, both from a supplier if you're in a hurry.",
	["Mithril Bar"] = "Engineers and smiths will buy every one you have.",
	["Truesilver Bar"] = "Ten for The Spectral Chalice, one for the Molten Foundry.",
	["Dark Iron Bar"] = "Eight ore a bar, only at the Black Forge in Blackrock Depths.",
	["Thorium Bar"] = "Five go into the Molten Foundry; the rest into everything a 60 wears.",
	["Azerothium Bar"] = "New in Forever: the Enriched Thorium set, the Legionite Glaive and other smithing, two engineering gadgets and an enchant. Still teaches when nothing else will.",
	["Heavy Thorium Bar"] = "New in Forever. Smelted at a Molten Foundry, not a forge. Some 35 smithing recipes want it, and Transmute: Legionite.",
	["Elementium Bar"] = "The top of smithing. Most miners never see one, and sleep fine.",
}

-- Where to smelt: name, where; side (A, H) when only one side is welcome.
D.FORGES = {
	{ "Goldshire", "Elwynn Forest, by the smith.", side = "A" },
	{ "Kharanos", "Dun Morogh.", side = "A" },
	{ "The Great Forge", "Ironforge. The biggest anvil in the world, and the loudest.", side = "A" },
	{ "Warrior's Terrace", "Darnassus: the nearest forge to Teldrassil's amber.", side = "A" },
	{ "Razor Hill", "Durotar.", side = "H" },
	{ "Bael'dun Digsite", "Mulgore, among the dwarves who shouldn't be digging there.", side = "H" },
	{ "Brill", "Tirisfal Glades.", side = "H" },
	{ "Shen'dar Village", "Zephras Isle, for both sides." },
	{ "Your camp", "A Molten Foundry, for Heavy Thorium." },
	{ "The Black Forge", "Blackrock Depths, for Dark Iron and nothing else." },
}

D.FORGE_HINT = "Smelt at any forge: most towns have one, usually beside a smith who pretends not to watch."

-- Camp objects (blueprints and the Lodestone): what they do. By item ID.
D.CAMP = {
	[279960] = "A stone at your campfire that lends melee attack power to everyone sitting nearby. It doesn't stack with Blessing of Might. Camp features share a one-hour cooldown.",
	[279948] = "Grows a common mining node beside your camp now and then, and does everything a Lodestone does. Place it over a Lodestone to replace it.",
	[279952] = "A forge at your camp for recipes that need one, Heavy Thorium among them, plus the Lodestone's buff. A Tier 3 campfire holds up to ten features.",
}

---------------------------------------------------------------------------
-- Gems, stone, and the rest of what falls out.

D.GEMS = {
	{ id = 774, name = "Malachite", from = "Copper Veins.", use = "Early jewellery and a few engineering trinkets." },
	{ id = 818, name = "Tigerseye", from = "Copper Veins.", use = "Early smithing and jewellery." },
	{ id = 1210, name = "Shadowgem", from = "Copper, Tin and Silver Veins.", use = "Smithing, engineering's goggles, and a rogue's poison or two." },
	{ id = 1206, name = "Moss Agate", from = "Tin and Silver Veins." },
	{ id = 1705, name = "Lesser Moonstone", from = "Tin, Silver, Iron and Gold.", use = "Smithing and engineering in the twenties." },
	{ id = 1529, name = "Jade", from = "Tin, Iron and Gold." },
	{ id = 3864, name = "Citrine", from = "Iron, Gold, Mithril and Truesilver." },
	{ id = 7909, name = "Aquamarine", from = "Iron, Mithril and Truesilver." },
	{ id = 7910, name = "Star Ruby", from = "Mithril, Truesilver and Thorium.", use = "Two go into The Spectral Chalice." },
	{ id = 9262, name = "Black Vitriol", from = "Mithril, Dark Iron and Small Thorium." },
	{ id = 12361, name = "Blue Sapphire", from = "Small and Rich Thorium." },
	{ id = 12799, name = "Large Opal", from = "Small and Rich Thorium." },
	{ id = 12364, name = "Huge Emerald", from = "Rich Thorium." },
	{ id = 12800, name = "Azerothian Diamond", from = "Small and Rich Thorium." },
	{ id = 12363, name = "Arcane Crystal", from = "Rich Thorium (some say Small Thorium too).", use = "Alchemists' Arcanite. Worth more than the vein it came from." },
	{ id = 11754, name = "Black Diamond", from = "Dark Iron." },
	{ id = 11382, name = "Blood of the Mountain", from = "Dark Iron.", use = "The Thorium Brotherhood will take it off your hands, for reputation." },
	{ id = 248820, name = "Torbernite", from = "Heavy Thorium. New in Forever." },
	{ id = 248819, name = "Fel Crystal", from = "Heavy Thorium. New in Forever.", use = "One goes into Transmute: Legionite, with a Heavy Thorium Bar." },
}

D.STONES = {
	{ id = 2835, name = "Rough Stone", from = "Copper Veins.", use = "Sharpening and weightstones, Rough Blasting Powder, and the Lodestone." },
	{ id = 2836, name = "Coarse Stone", from = "Tin Veins.", use = "Coarse sharpening and weightstones, Coarse Blasting Powder." },
	{ id = 2838, name = "Heavy Stone", from = "Iron Deposits.", use = "Heavy grinding, sharpening and weightstones; two go into the Rock Garden." },
	{ id = 7912, name = "Solid Stone", from = "Mithril Deposits.", use = "Solid grinding, sharpening and weightstones, Solid Blasting Powder." },
	{ id = 12365, name = "Dense Stone", from = "Thorium Veins.", use = "Dense grinding, sharpening and weightstones, Dense Blasting Powder; two go into the Molten Foundry." },
}

-- The scarce and the strange.
D.ELEMENTS = {
	{ id = 249391, name = "Pyrite", from = "Copper, Tin, Silver and Iron, scarcely. New in Forever.", use = "Scarce: a few in every thousand swings. Bountiful Harvest finds more." },
	{ id = 249425, name = "Bauxite", from = "Gold and Mithril, scarcely. New in Forever.", use = "Scarce, like Pyrite, a tier up." },
	{ id = 249426, name = "Pitchblende", from = "Truesilver, Dark Iron and Thorium, scarcely. New in Forever.", use = "Two and a Coal make an Azerothium Bar." },
	{ id = 275842, name = "Fossilized Insect", from = "Teldrassil's amber.", use = "Its card says larger ones turn up in Un'Goro. Don't go looking." },
	{ id = 275843, name = "Tuft of Hair", from = "Teldrassil's amber.", use = "Whose, the amber won't say." },
	{ id = 19774, name = "Souldarite", from = "Hakkari Thorium Veins in Zul'Gurub." },
}

-- Extra item names the page should link.
D.ITEMS = {
	[2770] = "Copper Ore", [2771] = "Tin Ore", [2775] = "Silver Ore", [2772] = "Iron Ore", [2776] = "Gold Ore",
	[3858] = "Mithril Ore", [7911] = "Truesilver Ore", [11370] = "Dark Iron Ore", [10620] = "Thorium Ore",
	[248815] = "Heavy Thorium Ore", [3340] = "Incendicite Ore", [4278] = "Lesser Bloodstone Ore", [5833] = "Indurium Ore",
	[22202] = "Small Obsidian Shard", [22203] = "Large Obsidian Shard", [3857] = "Coal", [251290] = "Legionite Bar",
}

---------------------------------------------------------------------------
-- The kit.

D.KIT = {
	{ id = 2901, name = "Mining Pick", text = "Carry it in your bags; you don't wield it. Trade and general goods vendors in every starting area sell one." },
	{ id = 247840, name = "Mining for Dummies", text = "New in Forever: a quest reward in every starting area. +2 Mining (to 15), and it teaches you Mining if you don't know it." },
	{ id = 277115, name = "Apprentice's Mining Pack", text = "New in Forever: a four-slot mining bag from general and trade vendors in the starting areas and capitals." },
	{ id = 259229, name = "Vindael's Spectral Pickaxe", text = "New in Forever: for the quest Spectral Iron Ore in Shen'dralas. Shows Ghostly Iron Deposits, and mines ordinary ones too." },
	{ id = 872, name = "Rockslicer", text = "Reworked in Forever: from Rhahk'Zor in the Deadmines. Thirty charges of opening Copper, Tin, Silver or Iron veins without knowing Mining at all." },
}

D.GEAR = {
	{ id = 5444, name = "Miner's Cape", text = "Reworked in Forever: +2 Mining. Miner Johnson, the Deadmines (about half the time)." },
	{ id = 275028, name = "Twilight Mine Light", text = "New in Forever: a helm with +4 Mining, from the Alliance quest A Miner Problem in the Riverglades." },
	{ id = 9465, name = "Digmaster 5000", text = "Reworked in Forever: +4 Mining, from Mining 175." },
	{ id = 10542, name = "Goblin Mining Helmet", text = "+5 Mining. Engineers make it at 205." },
	{ id = 5199, name = "Smelting Pants", text = "Copper, Tin, Bronze and Silver smelt a quarter faster. Gilnid, the Deadmines." },
	{ name = "Enchant Gloves - Mining", text = "+2 Mining; Advanced Mining gives +5. Ask an enchanter." },
}

D.FIND = {
	"You learn Find Minerals with Mining: veins show as yellow dots on the minimap.",
	"It's off by default, and it switches off when you die. Turn it back on from the tracking button.",
	"Guides disagree on whether it now runs alongside Find Herbs; the spell's own card still says one thing at a time.",
	"Veins grow back faster the more players are about.",
	"Ore stacks to 20 in Forever, not 10.",
}

-- Legacy talents (the Professions tree): name, what it does.
D.TALENTS = {
	{ "Bountiful Harvest", "5 ranks: 20% more Scarce materials (Pyrite, Bauxite, Pitchblende) from Mining, Herbalism and Skinning, per rank." },
	{ "Working Overtime", "5 ranks: 4% more chance of a skill-up in every trade, per rank." },
	{ "Dedicated Study", "Once a day, your lowest trade goes up by one. At 300 in everything, Elemental Essences instead." },
}

---------------------------------------------------------------------------
-- What the book says about the other faction's things.

D.ENEMY = {
	A = { "Alliance land. Mine quickly, mine quietly, mine like you're only borrowing.",
		"Alliance land. The rocks don't care who you are. Everything above them does.",
		"Alliance land. Their dwarves dug half of it hollow. They'll notice a little more missing." },
	H = { "Horde land. The ore's the same colour here. The welcome isn't.",
		"Horde land. Keep your pick where they can see it.",
		"Horde land. The rocks won't mind you. Everything standing on them will." },
}

D.NOT_YET = "You don't mine yet. A trainer sells the knack, a vendor sells the pick, and the starting areas hand out a book called Mining for Dummies. It isn't wrong."
D.BARREN = "Nothing worth a swing here, by the maps. Rocks, plenty. Veins, none. Like most places."
D.INSIDE = "Somewhere the maps don't reach. Veins down here still go in the memoir."

---------------------------------------------------------------------------
-- The tales.

D.LEGENDS = {
	{
		title = "The Thorium Brotherhood",
		text = "Some Dark Iron dwarves walked out of Blackrock and set up shop at Thorium Point in Searing Gorge, which makes them the only dwarves I know who quit by moving next door. They'll trade recipes for Dark Iron Ore and Blood of the Mountain. Their quartermaster, Lokhtos Darkbargainer, keeps his stall in the Grim Guzzler, inside the mountain they left. Imagine the commute.",
	},
	{
		title = "Thaurissan's bad afternoon",
		text = "Losing a war, Thaurissan of the Dark Irons decided the answer was a fire lord. Ragnaros came, the ground split, and Blackrock Mountain, Searing Gorge and the Burning Steppes are what was left over. Every miner who has burnt a thumb on a Dark Iron vein is still paying for that afternoon.",
	},
	{
		title = "Kobolds",
		text = "Kobolds dig in the dark and are terrified of it, which is a hard way to make a living. They choose leaders by the longest candle and make the candles out of earwax. Echo Ridge, Fargodeep, Jasperlode and Jangolode are theirs, and they come at you with mining picks. It's like being mugged by colleagues.",
	},
	{
		title = "The Venture Company",
		text = "Goblins whose plan for any mountain is \"yes\". If it can be dug up, cut down or blown out of a hillside, they have a crew and a shredder on it, and their managers retire by \"terminal command restructuring\". I've seen their mine in Mulgore. The rocks looked tired.",
	},
	{
		title = "What the dwarves woke",
		text = "Dwarves dug too near Uldaman and woke the troggs, who tunnelled straight up into Gnomeregan. The gnomes answered with radiation, and most of the gnomes died of it. Every miner should hear this once: sometimes what you dig up digs back.",
	},
	{
		title = "Gilnid's trousers",
		text = "Down in the Deadmines a goblin called Gilnid runs the Defias smelter in a pair of Smelting Pants. Beat him and they're yours: Copper, Tin, Bronze and Silver smelt a quarter faster. I have never wanted trousers so much in my life.",
	},
	{
		title = "Fel in Hyjal",
		text = "Heavy Thorium grows on Mount Hyjal, wrapped in green fel smoke, a short walk from the Scourge. The rock is heavier, the air is worse and the neighbours are dead. Rock bottom has a basement.",
	},
	{
		title = "The ten hundred words",
		text = "Every starting area hands out a book called Mining for Dummies, which \"explains how to mine using only the ten hundred most common words.\" Hit rock. Rock break. Take rock. Go home. It is the best book on the subject, after this one.",
	},
}

-- Claims from a single source, or where the sources disagree.
D.TALL_TALES = {
	{ "The Lodestone's punch", "How much attack power a Lodestone gives: 90, falling to 60 at the top, says one guide; 12, says another. Its card only shows the sum." },
	{ "Smelting past 185", "One guide says smelting stops teaching at 185. Two others say Azerothium, at 275, still teaches. The book sides with the two." },
	{ "Finding two things at once", "One guide says the tracking spells run together now. Find Minerals' own card still says one at a time." },
	{ "Rethban Ore", "Two guides list Rethban Ore from Copper and Tin. It's an old Redridge quest item; we haven't seen it fall out of a vein." },
	{ "Legacy for miners", "One site says Mining earns legacy points at 150, 225 and 300. The others say only the crafting trades do." },
	{ "The ghost veins", "Cold Iron, Fool's Gold, Starsilver and Greater Moonstone are in the game's tables and on Wowhead's Forever pages, with spots. They grew in Season of Discovery's Nightmare Incursions. Nobody has reported one in Forever." },
}

D.SOURCES = "Veins and their spots: GatherLite's Forever database (Wuild, MIT licence), from Wowhead's coordinates, November 2026. Smelts, ranks and people: WhatsTraining, AtlasLoot and Questie for patch 1.60.1. The rest: warcraft.wiki.gg, warcrafttavern.com, wow-professions.com, wow.gg, timesaver.gg and Wowhead's Forever tooltips. Most guides were written in the beta; numbers may still move."

---------------------------------------------------------------------------
-- The memoir: chapter openers (in the miner's hand) and the lines the book writes itself.

D.OPENERS = {
	seam = { "The ground under my boots. It's never let me down, mostly because it's the bottom." },
	route = { "Three hundred points from here to the bottom. Mind the step at 125. Mind all of them, really." },
	veins = { "Every vein is a rock keeping a secret. I ask nicely, with a pick." },
	smelter = { "Ore goes in, bars come out. I go in, I come out. Only the ore improves." },
	gems = { "Now and then a rock coughs up something shiny. Never for the people who deserve it. For me." },
	kit = { "A pick, a sack and a nose for minerals. My whole estate." },
	tales = { "Things said far underground, where nobody can check." },
}

-- The memoir's own story: the first line of your first, second and third days of mining.
D.STORY = {
	{ "Day one. Bought a pick. The vendor said \"good luck down there.\" I thought \"down\" was a figure of speech." },
	{ "Learned why miners hum. It covers the sound of thinking." },
	{ A = "Ironforge was dug out of a mountain by people with a plan. I stood in the middle of it with a pick and no plan. The mountain didn't notice either.",
		H = "Somebody cut Orgrimmar's walls out of solid rock. They got a city. I got a lump the size of a loaf and a sore back." },
}

-- Auto entries. {vein}, {ore}, {gem}, {bar}, {zone}, {n}, {skill} are filled in.
-- The everyday lines come in three depths, by your Mining skill: surface (below 125) wry,
-- middle (125 to 224) lonely, deep (225 and up) sadder still. Every line is one plain joke:
-- a setup and a twist, never an explanation of the twist.
D.LINES = {
	first = { "First vein: {vein}, {zone}. Hit it until it gave up. It gave up first. Enjoy that while it lasts." },
	opened = "Started this memoir at Mining {skill}. The early chapters were lost in a cave-in. They were mostly about copper.",
	vein = {
		surface = {
			"{vein} in {zone}. My mother said I could be anything. She didn't say how far down.",
			"{vein}. I knocked first. Then I used the pick. Manners only get you so far.",
			"Called dibs on a {vein}. Unopposed. I've never won anything so easily.",
			"{vein} in {zone}, right where the map said. The map has never lied to me. Early days.",
			"{vein}. Took ten swings. My arms took eleven.",
			"A {vein}. I'd tell you how it felt, but my hands are still ringing.",
			"{vein}. Got {ore} and a blister. Only one of them sells.",
			"{vein}, {zone}. The echo said \"nice swing.\" I'll take it.",
			"First {vein}. Swung, missed, swung, hit. Let's not count the first one.",
			"{vein} in {zone}. Treasure, technically.",
			"{vein}. Wrote its name down so I'd remember. Wrote it on a rock. Lost the rock.",
			"{vein}. I'm told miners live long lives. Mostly hunched.",
		},
		middle = {
			"{vein}. I talk to the rocks now. Good listeners. Terrible at writing back.",
			"{vein} in {zone}. Somebody will forge a famous sword from this. Nobody names the miner.",
			"{vein}. My back hurts in new places. I didn't know I had places.",
			"A {vein}. Fresh air, open sky, and I'm facing a wall. By choice. Every day.",
			"{vein}. I've started naming the cracks. Gerald's my favourite. Gerald is a crack.",
			"{vein} in {zone}. Called dibs out of habit. There's never anyone to call it against.",
			"{vein}. The bag sighed when I put it in. Then I sighed. Then we both just sat there.",
			"{vein}. My pick has seen more of the world than my friends have. Mostly because my pick exists.",
			"{vein} in {zone}. Older than the kingdoms. It'll outlast me. It'll outlast my debts, which is saying something.",
			"{vein}. A blacksmith will make something lovely from this and never once think of me.",
			"{vein}. Ten swings to break it, two seconds to loot it, the whole walk home to wonder why.",
			"A {vein}. The weather was lovely today. I saw none of it.",
		},
		deep = {
			"{vein}. Hit rock bottom today. Turns out it's just more rock.",
			"{vein} in {zone}. Another miner got here just after me and said \"oh.\" Longest conversation I've had all week.",
			"{vein}. My knees make the same noise as the ore now.",
			"{vein} in {zone}. Something large stepped right over me. Didn't even stop. That's how small I've got.",
			"{vein}. I've been underground so long my shadow's stopped following me.",
			"{vein}. Cold, dark and nobody about. I'd complain, but it's basically my house.",
			"{vein} in {zone}. I used to dream of adventure. Now I dream of slightly closer veins.",
			"{vein}. The mobs here don't attack me any more. I think they've heard.",
			"{vein}. I've stopped saying \"one more vein.\" It was never one more.",
			"{vein} in {zone}. A gnome asked if I worked here. I said yes. Nobody pays me. I just never left.",
			"{vein}. Hit it so hard the handle rang. First thing that's rung for me in years.",
			"{vein}. Older than the trees, and neither of them has asked my name.",
		},
	},
	-- The first of each kind, by vein key (the depth lines above for the rest).
	special = {
		copper_vein = "Copper Vein. Everyone starts here. Most people leave.",
		tin_vein = "Tin Vein. Half of Bronze, and the half nobody asks for. I mined it anyway, out of solidarity.",
		silver_vein = "A Silver Vein. Told no one. Partly because it's mine, mostly because there's no one.",
		iron_deposit = "Iron Deposit. I talk to the rocks now. Good listeners. Terrible at writing back.",
		gold_vein = "Gold Vein. I'd have shouted, but you need someone to shout to.",
		mithril_deposit = "Mithril. Light, strong and valuable. Three things nobody has ever called me.",
		truesilver_deposit = "Truesilver. Silver that swears it's honest. One of us should be.",
		dark_iron_deposit = "Dark Iron, under Blackrock. The owners came to see who was knocking. I left. I'm good at leaving.",
		small_thorium_vein = "Thorium. It hums. I've started humming back. Neither of us knows the words.",
		rich_thorium_vein = "Rich Thorium. I'm rich now, in ore. In everything else, still broke.",
		heavy_thorium_vein = "Heavy Thorium in Hyjal. Even the undead here look at me and think, rough week.",
		incendicite_mineral_vein = "Incendicite. Warm ore. The warmest thing I've touched in a month.",
		lesser_bloodstone_deposit = "Lesser Bloodstone. Even its name has been told it's lesser. We'd get on.",
		chunk_of_amber = "Chunk of Amber. Old sap with something stuck inside it forever. Relatable.",
		large_chunk_of_amber = "Large Chunk of Amber. A tree cried about something ages ago. I'm selling the tears.",
		small_obsidian_chunk = "Obsidian, off a monster that died and left a rock behind. Goals.",
		large_obsidian_chunk = "A Large Obsidian Chunk. Volcano glass, sharp on every edge. I used to be like that.",
		indurium_mineral_vein = "Indurium in Uldaman, beside a titan's leftovers. They were built to last. I was built to carry stone.",
		hakkari_thorium_vein = "Hakkari Thorium in Zul'Gurub. The priests didn't even try to sacrifice me. Rude.",
		fools_gold_vein = "A Fool's Gold Vein. The name was a warning. I read it as a job title.",
		cold_iron_deposit = "Cold Iron. \"Ephemeral and unstable,\" says the ore. Same.",
		starsilver_vein = "Starsilver. A bit of night sky stuck in a stone. I used to wish on those.",
		greater_moonstone_formation = "A Greater Moonstone Formation. The moon didn't mind. The moon's very far away.",
	},
	gem = {
		surface = {
			"A {gem} fell out of the {vein}. Even the rocks feel sorry for me.",
			"{gem}! Held it up to the light. The light held it right back.",
			"A {gem}. Bit it to check it was real. It was. Now my tooth isn't.",
			"{gem}, {zone}. A rock with a bonus.",
			"A {gem}. Polished it on my sleeve. Made it worse.",
			"{gem}. Gave it a pocket of its own. It's the only thing I own with its own room.",
		},
		middle = {
			"A {gem}. Showed it to the rock it came from. Felt it should know.",
			"{gem}. Did a little dance, alone, in a cave. The echo joined in. Then it stopped.",
			"A {gem}. Told it it's pretty. Somebody ought to hear that.",
			"{gem}. A smith wants it, an enchanter wants it. That's two more people than want me.",
			"A {gem}. I'll sell it to someone who'll love it. That's how it works.",
			"{gem}. Worth more than everything else in the bag. Including the bag. Including, on paper, me.",
		},
		deep = {
			"A {gem}. Prettiest thing I've held in years. Also the only thing I've held in years.",
			"{gem}. Still warm from the mountain. Warmer than me.",
			"A {gem}. I'll sell it on Tuesday. Everything gets sold on Tuesday.",
			"{gem}. Even the {vein} had something better inside it. Good for it.",
			"A {gem}. Looked at it so long I forgot to loot the ore. Best ten minutes of the month.",
			"{gem}. The vendor's going to be so happy. One of us should be.",
		},
	},
	rare = {
		surface = {
			"A {gem}! Every bad swing this year just became an investment.",
			"{gem}! Wrapped it in three socks and a map. Not opening that again.",
			"A {gem}. Sat down right there and admired it. The ore can wait. The ore always waits.",
			"{gem}! The {vein} was holding out on me. I forgive it. Instantly.",
		},
		middle = {
			"A {gem}. Rare as a kind word. I'm keeping my voice down so it doesn't leave.",
			"{gem}. Showed nobody. There's nobody. Showed the rock. The rock knew.",
			"A {gem}. Hid it, checked it, hid it better. This is what happiness looks like now.",
			"{gem}! I'd heard of these. I assumed they happened to other people.",
		},
		deep = {
			"A {gem}. If this book's ever found beside my bones, at least they'll know I had one good day.",
			"{gem}. I waited years for one of these. It's smaller than the years.",
			"A {gem}. Somewhere a mountain is missing its best part. Join the club.",
			"{gem}. My first thought was who to show. I'm still thinking.",
		},
	},
	-- A vein where the book had no spot.
	find = {
		surface = {
			"A {vein} in {zone} that no map has. I'm a cartographer now. Small hat pending.",
			"Uncharted {vein}, {zone}. Named the spot after myself. The spot hasn't agreed.",
			"A {vein} where the maps go quiet. Somewhere a map-maker owes me a drink.",
			"A new spot for {vein}. Explorers get statues. I get dirt under my nails.",
		},
		middle = {
			"A {vein} no map has. Either the maps are wrong or I am. I've a guess which.",
			"{vein} in {zone}, off every chart. Wrote it in this book, which is also off every chart.",
			"An unknown {vein}. The best ones are the ones nobody's looking for. I'd know.",
			"Found a {vein} no map has. Told this book. It's the only one who listens.",
		},
		deep = {
			"A {vein} no map knew. One day someone will walk straight to it and never know I was first.",
			"{vein}, off the map. If you're reading this later: I was here.",
			"A {vein} in {zone} that no map has. Lonely spot. We'll get on.",
			"An uncharted {vein}. Nobody's been here in years. Same as my house.",
		},
	},
	-- Once a day, mining a vein that teaches nothing more.
	grey = {
		surface = {
			"A {vein} for the ore, not the lesson. The lesson moved out.",
			"{vein}: nothing left to learn, plenty left to sell.",
			"{vein} again. A grown miner, picking on rocks half my level.",
			"Back on {vein} for a smith with an order. The trade is mostly errands.",
		},
		middle = {
			"{vein}. Taught me nothing. Hit it anyway. Habit is a vein that never runs out.",
			"Old friend {vein}. We don't talk much any more. I still visit.",
			"{vein} in {zone}. No skill, just coin. Coin doesn't ask how I'm doing.",
			"{vein}. Could do this in my sleep. Lately I have been.",
		},
		deep = {
			"{vein}. Mined it with my eyes shut. Missed twice. Kept them shut.",
			"{vein} in {zone}, for old times' sake. There weren't good old times. Just old times.",
			"{vein}. Nothing left to learn from it. We have that in common.",
			"Back on {vein}. Easy money. Easy is all I've got left.",
		},
	},
	-- Forty stone in a day.
	stone = {
		surface = {
			"{n} stone today. I'm a quarry with legs.",
			"{n} stone. A goblin offered to buy me by the pound.",
			"{n} pieces of stone. Legally I'm a hill now. Sheep have started following me.",
			"{n} stone in the bags. I've built a small hill and I'm walking it home.",
		},
		middle = {
			"{n} stone. The smiths call it sharpening stone. My shoulders have a different word.",
			"Bags: {n} stone. Me: one person. One of us is outnumbered.",
			"{n} stone across {zone}. The wildlife steps aside. Not out of fear.",
			"{n} stone. A goblin offered to buy me by the pound. Lowball. I nearly took it.",
		},
		deep = {
			"{n} stone in my bags. The auctioneer took one look and asked if I was all right.",
			"{n} stone. I could build a wall around myself. I'm told I already have.",
			"{n} stone. Every rock I break makes three smaller rocks. The mountain's winning on numbers.",
			"Hauled {n} stone today. Nobody asked me to. Nobody asks me anything.",
		},
	},
	-- The first bar of each kind (special lines by name for some).
	smelt = {
		surface = {
			"First {bar} out of the forge. It glowed. So did my sleeves.",
			"Smelted my first {bar}. Ore goes in ugly, comes out handsome. There's hope.",
			"{bar}! The forge hissed at me. I hissed back. Mutual respect.",
			"First {bar}. Lost an eyebrow, gained a trade. Fair.",
		},
		middle = {
			"First {bar}. Hot, heavy, and the only thing I've made that didn't need an apology.",
			"Poured a {bar}. Felt proud. Picked it up. Felt heavy. The second one stuck.",
			"{bar}. Alchemists turn lead into gold and nobody believes them. I turn rock into bars and nobody notices.",
			"{bar}! Stacked neatly in my bag. The only neat thing about me.",
		},
		deep = {
			"First {bar}. It glowed for a minute. Same as everything.",
			"{bar}. Stood by the forge admiring it far too long. It was warm.",
			"First {bar}. The forge hissed at me. Most conversation I've had all week.",
			"{bar}. Fire, rock and patience. Two out of three.",
		},
	},
	smeltSpecial = {
		["Bronze Bar"] = "Bronze: copper and tin, married in a furnace. I officiated. I wasn't invited to the reception.",
		["Steel Bar"] = "Steel. Iron, coal and a lot of shouting at a fire. I did the shouting.",
		["Gold Bar"] = "A Gold Bar. Held it for a while. Didn't feel rich. Felt heavy.",
		["Truesilver Bar"] = "A Truesilver Bar. Even molten it looked honest. I had to look away.",
		["Dark Iron Bar"] = "Dark Iron, at the Black Forge, in a mountain that wants me dead. At least it's paying attention.",
		["Thorium Bar"] = "A Thorium Bar. It hums in the bag. We've agreed not to talk about it.",
		["Azerothium Bar"] = "An Azerothium Bar. Named after the whole world. I've been carrying that for years anyway.",
		["Heavy Thorium Bar"] = "Heavy Thorium Bar. Dropped it on my foot to test the name. The name holds.",
		["Elementium Bar"] = "Elementium. A Fiery Core, ten Arcanite and nerve. I was short on nerve.",
	},
	-- A smelt newly in the spellbook.
	learned = {
		surface = {
			"New smelt: {bar}. One more thing to melt. Nothing is safe.",
			"I can smelt {bar} now. The ore doesn't know yet.",
			"Learned {bar}. It's mostly heat. Most tricks are.",
		},
		middle = {
			"Learned {bar}. The list of smelts grows. The list of friends holds steady.",
			"Learned {bar}. Knowledge costs coin. Fire's free.",
			"{bar}: learned it. Will make it. Will burn myself making it.",
		},
		deep = {
			"New smelt: {bar}. One more thing I'm good at that nobody asks about.",
			"{bar}. Another way to turn a mountain into money, and money into rent.",
			"Learned {bar}. Nobody congratulated me, but the forge got warmer, which is close.",
		},
	},
	-- Fifty veins in a day, once.
	batch = "{n} veins in one day. My arms have asked to see someone in charge.",
	-- Veins mined, in all.
	total = {
		[100] = "A hundred veins. I've moved a small mountain, one rock at a time. Nobody saw.",
		[250] = "Two hundred and fifty veins. My pick has a groove where my hand goes. My hand has one where the pick goes.",
		[500] = "Five hundred veins. Somewhere a mountain is noticeably thinner. So am I.",
		[1000] = "A thousand veins. I hear rocks in my sleep. They say clink. It's the only thing anyone says to me.",
		[2500] = "Two and a half thousand veins. Rock bottom is a long way down, and I'm making excellent time.",
		[5000] = "Five thousand veins. They'll name a tunnel after me. \"That one.\"",
	},
	skill = {
		[25] = "Mining 25. I can tell copper from mud now. Usually.",
		[50] = "Mining 50. Promoted from hitting rocks to hitting rocks professionally. Nobody threw a party. I checked.",
		[75] = "Mining 75. The ground's started to look like a menu.",
		[100] = "Mining 100. Three figures. Celebrated by hitting a rock.",
		[125] = "Mining 125. Iron's open. So is a new kind of back pain.",
		[150] = "Mining 150. Halfway down. The view is mostly wall.",
		[175] = "Mining 175. Dwarves nod at me in the street now. It's the pity nod.",
		[200] = "Mining 200. Two hundred points of skill and still a rock between me and everything I want. Several rocks.",
		[225] = "Mining 225. My pick and I have stopped arguing. We just look at each other now.",
		[250] = "Mining 250. Thorium hums when I walk past. Something's finally nervous around me.",
		[275] = "Mining 275. Nearly at the bottom. I'm told it's quiet.",
		[300] = "Mining 300. Top of the trade. Bottom of everything else.",
		other = "Mining {skill}. Deeper.",
	},
	-- A new rank (by its cap).
	rank = {
		[150] = "Journeyman. A title and a heavier pick. Mostly the pick.",
		[225] = "Expert. Experts know which rocks to hit. I still hit all of them.",
		[300] = "Artisan. Artisans make art. I make holes. Same thing, from the right angle. I don't have the right angle.",
	},
}
