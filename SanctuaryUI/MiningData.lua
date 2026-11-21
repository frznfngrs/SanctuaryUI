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

-- name, cap, what it takes.
D.RANKS = {
	{ "Apprentice", 75, "Any mining trainer. The junior trainers in the starting areas teach only this, and no smelting." },
	{ "Journeyman", 150, "From skill 50 and level 10, 5s at a trainer." },
	{ "Expert", 225, "From skill 125 and level 20, 50s." },
	{ "Artisan", 300, "From skill 200 and level 35, 5g. You can't pass 225 without it. 300 is Forever's cap." },
}

-- skill band, then A, H (or N for both) and a note.
D.ROUTE = {
	{ "1-65",
		A = "Copper in Elwynn (smelt at Goldshire) or Dun Morogh (smelt at Kharanos; the caves grow back fast). Night elves can start on Teldrassil's amber, to 20; the nearest forge is the Warrior's Terrace in Darnassus.",
		H = "Copper in Durotar: one cave holds five veins and grows back fast (smelt at Razor Hill). Or Mulgore's loop and cave (forge at Bael'dun Digsite), or Tirisfal (Brill).",
		note = "Poor Copper Veins in every starting area teach to 20. Zephras Isle works for both sides; smelt at Shen'dar Village." },
	{ "65-125",
		A = "Tin and Silver. The Wetlands, by a distance: Tin outside, Incendicite in Thelgen Rock. Westfall and Redridge will do.",
		H = "Tin and Silver. Silverpine's cave (three veins, back in about two minutes) or Hillsbrad; the Barrens, Ashenvale and Stonetalon too.",
		note = "Journeyman at 50. The mobs come back fast in Forever, so out-level them first." },
	{ "125-175",
		N = "Iron and Gold. Thousand Needles is the safest; Arathi (south of Hammerfall), Desolace, Stranglethorn, Alterac and Hillsbrad.",
		note = "Expert at 125. Smelting Iron to 135, and Gold from 155 to 170, saves walking." },
	{ "175-245",
		N = "Mithril, then Truesilver from 230: the Hinterlands, Tanaris, the Badlands, Searing Gorge, Feralas. Dark Iron from 230 in Searing Gorge and the Burning Steppes.",
		note = "Artisan at 200." },
	{ "245-275",
		A = "Small Thorium: Un'Goro's caves, Felwood's Jaedenar cave, the Blasted Lands (not inside the Garrison Armory mine: Alliance can't mine there), Winterspring, the Plaguelands, Silithus.",
		H = "Small Thorium: Un'Goro's caves, the Blasted Lands, Felwood's Jaedenar cave, Winterspring, the Plaguelands, Silithus." },
	{ "275-300",
		N = "Rich Thorium in Un'Goro, the Eastern Plaguelands, Winterspring and the Burning Steppes. It's rare, so smelt Azerothium (from 275) between veins.",
		note = "At 300, Heavy Thorium in Mount Hyjal." },
	{ "Shortcut",
		N = "To about 105 without a swing: buy some 140 Copper Ore and 70 Tin Ore and smelt the lot.",
		note = "From 120, +5 Mining gear lets you start on Iron early." },
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

D.NOT_YET = "You don't mine yet. A trainer sells the knack and a vendor sells the pick, and in the starting areas a quest hands you a book called Mining for Dummies. It's not wrong."
D.BARREN = "Nothing worth a swing here, by the maps. Rocks, plenty. Veins, none."
D.INSIDE = "Somewhere the maps don't reach. Veins down here still go in the memoir; the book just can't say where you were."

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
	seam = { "The ground under my boots, and what it owes me." },
	route = { "Three hundred points between me and the bottom. Here's the staircase. Mind the step at 125." },
	veins = { "Every vein is a rock keeping a secret. I'm the one who asks rudely, with a pick." },
	smelter = { "Ore goes in, bars come out, and my eyebrows go somewhere else entirely." },
	gems = { "Now and then a rock coughs up something shiny to make up for the other ninety-nine." },
	kit = { "A pick, a sack and a nose for minerals: the full extent of my estate." },
	tales = { "Things said a long way underground, where nobody can check." },
}

-- The memoir's own story: the first line of your first, second and third days of mining.
D.STORY = {
	{ "Every memoir starts somewhere high. Mine starts in a field, holding a pick, facing a rock that has been there since before the Titans and has no plans to leave." },
	{ "Learned why miners hum. It's so you can't hear the rock laughing." },
	{ A = "Ironforge is a city carved out of a mountain by people who mined it hollow. I stood in the middle of the greatest dig in the world, holding my pick, feeling small.",
		H = "Orgrimmar's walls are cut from Durotar's own red rock. Somebody mined all of that. I mined a lump the size of a loaf and needed a sit down." },
}

-- Auto entries. {vein}, {ore}, {gem}, {bar}, {zone}, {n}, {skill} are filled in.
D.LINES = {
	first = { "First vein: {vein}, {zone}. Hit it until it gave up. We both learned something about stubbornness." },
	opened = "Started this memoir at Mining {skill}. The early chapters were lost in a cave-in. They were mostly about copper.",
	vein = {
		"{vein} in {zone}. New rock, same arms.",
		"First {vein}. I knocked politely. Then I knocked with a pick.",
		"Met a {vein}. It had waited a thousand years for someone to come along. It got me. Disappointment on both sides.",
		"{vein}. I'd tell you how it felt, but my hands are still ringing.",
		"A {vein} in {zone}, right where the map said. The map and I are getting on well.",
		"{vein}! Wrote its name down so I'd remember. Wrote it on a rock. Lost the rock.",
		"First {vein}. Swung, missed, swung, hit. Memoirs leave out the miss. I've left in the miss.",
		"Struck a {vein} in {zone}. The world's least exciting treasure chest, and I loved it.",
		"A {vein}. The trick is to hit where it's weakest. It's weakest wherever I'm not aiming.",
		"{vein}. Took it home in pieces. That's how rocks prefer to travel.",
		"New to the collection: {vein}. The collection lives in my bags. My bags have complaints.",
		"{vein}, {zone}. The echo said \"nice swing\" three times. Most praise I've had all week.",
		"First {vein}. It was here before the kingdoms. Now some of it is in my backpack. History is rough.",
		"{vein}. Put my ear to it first. It said nothing. Rocks: dreadful talkers, marvellous listeners.",
		"Found a {vein} in {zone}. Got {ore}. Got a blister. Only one of those sells.",
		"{vein}. Every swing a little deeper, a little closer to rock bottom. We've been over this.",
		"A {vein}. Fresh air, open sky, and here I am staring at a wall. Classic me.",
		"First {vein}: harder than the last, richer than the last. A life lesson? No. Geology.",
		"{vein} in {zone}. Called dibs out loud. Nobody else was there. Still counts.",
		"{vein}. I'm getting better at this. The rock isn't getting worse at it, which hardly seems fair.",
		"A {vein}. It glittered under my light. Then I broke it. That's mining, mostly.",
		"{vein}. Deeper vein, finer ore, longer walk back. An iron law. Sometimes literally iron.",
		"Met a {vein}. Mountains don't give gifts. They give quotas.",
		"{vein}. Somewhere a blacksmith shivered and didn't know why.",
		"First {vein}. Ten swings to break, two seconds to loot, an hour to stop trembling.",
		"{vein} in {zone}. I've started naming the cracks. This one's Gerald.",
		"{vein}. Into the bag it goes. The bag sighs. We carry on.",
		"A {vein}. I swung like I meant it. The rock took it personally. Good.",
		"Brand new: {vein}. A miner remembers the first of everything. I'll remember this one as heavy.",
		"{vein}. Rang like a bell when I hit it. My elbow rang too, in a lower key.",
		"First {vein}, {zone}. Sat on it afterwards to rest. It didn't mind. Rocks are good like that.",
		"{vein}. If you'd told me as a child I'd spend my days hitting the ground, I'd have said \"great\". Children are idiots.",
		"Struck my first {vein}. It struck back, through the handle, into my teeth. Fair.",
		"{vein}. I'd swear it was smaller when I started. Or I was bigger. One of us has changed.",
		"Met a {vein} in {zone}. Didn't catch its age. Older than the trees, younger than the grudge it holds now.",
	},
	-- The first of each kind, by vein key (the generic lines above for the rest).
	special = {
		copper_vein = "Copper Vein. The ore everyone starts on and nobody admits to missing. I'll miss it.",
		tin_vein = "First Tin Vein. Every Tin Vein is a Silver Vein's understudy. I clapped anyway.",
		silver_vein = "A Silver Vein. Told no one. Told this book, which is like telling no one, but with pages.",
		iron_deposit = "Iron Deposit. Heavier ore, heavier pick, heavier sighs. Character building, they say. My character is mostly back pain.",
		gold_vein = "A Gold Vein! I wanted to shout. Didn't. Every rogue for a mile has ears like a bat.",
		mithril_deposit = "Mithril. Light as a promise, hard as a debt. The dwarves sing about it, mostly off key.",
		truesilver_deposit = "Truesilver. Silver that swears it's telling the truth. I believed it. I'm a soft touch for shiny.",
		dark_iron_deposit = "Dark Iron, under Blackrock. The owners came to see who was knocking. I left by the window. Mountains don't have windows. I made one.",
		small_thorium_vein = "Thorium. Ore that hums faintly, as if it knows something. I've stopped humming back.",
		rich_thorium_vein = "Rich Thorium. Rich is right. I'm not, yet, but the rock is, and we're negotiating.",
		heavy_thorium_vein = "Heavy Thorium, smoking green in Hyjal. Every name in this trade is honest, and this one most of all. My knees agree.",
		incendicite_mineral_vein = "Incendicite. Warm ore that wants to be a fire when it grows up. Kept it away from my beard.",
		lesser_bloodstone_deposit = "Lesser Bloodstone. A dramatic name for an errand. I was dramatic about it too.",
		chunk_of_amber = "Chunk of Amber. Old sap, set hard, with Copper inside. Like finding a coin in a cake.",
		large_chunk_of_amber = "A Large Chunk of Amber. A tree wept over something a long time ago. I'm profiting from it now.",
		small_obsidian_chunk = "Obsidian, from a monster that dropped dead and left a rock behind. Strangest week of my career.",
		large_obsidian_chunk = "A Large Obsidian Chunk. Volcano glass, sharp as gossip. Handled it like gossip: carefully, then all at once.",
		indurium_mineral_vein = "Indurium, in Uldaman. Mined it next to a titan's leftovers. They didn't stir. I didn't linger.",
		hakkari_thorium_vein = "Hakkari Thorium in Zul'Gurub, while a blood god's priests looked on. Mined faster than I ever have.",
		fools_gold_vein = "A Fool's Gold Vein. The name was a warning. I took it as a dare. The vein won the dare.",
		cold_iron_deposit = "Cold Iron. \"Ephemeral and unstable,\" says the ore. Wrote that on my own card too.",
		starsilver_vein = "Starsilver. A scrap of night sky stuck in a stone. Mined it anyway. Sorry, sky.",
		greater_moonstone_formation = "A Greater Moonstone Formation. Hit it gently. Then properly. The moon didn't mind.",
	},
	gem = {
		"A {gem} fell out of the {vein}. I didn't know rocks could tip.",
		"{gem}! Held it up to the light. The light held it right back.",
		"Out of the {vein}: a {gem}. The rock was hiding the good stuff. I respect that, and I'm taking it.",
		"A {gem}, {zone}. Bit it to see if it was real. Never do that. It was real.",
		"Found a {gem} in a lump of {vein}. A pearl in an oyster, if the oyster were a hill.",
		"{gem}! Did a little dance. In a cave. Alone. The echo made it a party.",
		"A {gem}. Told it it's pretty. Somebody should.",
		"{gem}. A smith wants it, an enchanter wants it, and right now I want it most.",
		"A {gem}! Worth more than everything else in the bag together. The bag knows. The bag is sulking.",
		"{gem}, {zone}. Most rocks are just rocks. This one was a rock with a bonus.",
		"A {gem}, still warm from the mountain. Probably from my hands. Let me have this.",
		"{gem}. If the miners' guild asks, I found it fair and square. There's no miners' guild. There should be.",
		"A {gem} tumbled out, and the {vein} looked lighter afterwards. Emotionally.",
		"{gem}. Polished it on my sleeve. My sleeve was filthier than the gem. Net loss of shine.",
		"{gem}! I've been hitting rocks for this exact moment. The other moments were rehearsal.",
		"A {gem}. Pocketed it, patted the pocket, patted it again. I'll be patting it all day.",
		"{gem}, out of a {vein} in {zone}. Small, bright and entirely mine. Like my one good idea.",
		"A {gem}. Looked at it so long I forgot to loot the ore. Went back for the ore. Priorities.",
	},
	rare = {
		"A {gem}. Blue sky on a grey day. Sat down where I was and admired it for a while.",
		"{gem}! The {vein} was holding out on me all along. I forgive it. Completely. Immediately.",
		"{gem}, out of the {vein} in {zone}. Wrapped it in three socks and a map. I may never unwrap it.",
		"A {gem}. Rare as a quiet tavern. I'm keeping my voice down about it.",
		"{gem}. If this book is ever found beside my bones, at least they'll know I had one good day.",
		"A {gem}! Every bad swing this year just became an investment.",
		"{gem}. Showed nobody. Showed myself, twice. Very impressed both times.",
		"A {gem} from a {vein}. Somewhere a mountain is missing its best tooth.",
		"{gem}. I've heard of these. I didn't believe in them. I believe now. I believe in everything now.",
		"A {gem} in {zone}. Hid it, then checked it was still there, then hid it better. Repeat until morning.",
	},
	-- A vein where the book had no spot.
	find = {
		"Found a {vein} in {zone} that no map has. Wrote it down. I'm a cartographer now. Small hat pending.",
		"A {vein} where no map says one grows. Either the maps are wrong or I am. Both are on the table.",
		"Uncharted {vein}, {zone}. Named the spot after myself. The spot hasn't agreed.",
		"{vein}, off the map. Every map was blank once. This corner's mine now.",
		"A {vein} in a place nobody marked. The mountain kept a secret, and I've written it in a book. Sorry, mountain.",
		"Off-the-map {vein} in {zone}. If you're reading this later: you're welcome.",
		"A new spot for {vein}. Explorers get statues. Miners get dirt under their nails. I'll take the dirt.",
		"A {vein} where the maps go quiet. Somewhere, a map-maker owes me a drink.",
		"Struck a {vein} in {zone} that no book had. This book has it now. Ha.",
		"An unknown {vein}. The best ones are the ones nobody's looking for.",
		"Found a {vein} off every chart. Kept the spot to myself, then wrote it here. I'm hopeless with secrets.",
		"A {vein} no map knew. One day someone will walk straight to it and never know I was first. I'll know.",
	},
	-- Once a day, mining a vein that teaches nothing more.
	grey = {
		"Mined a {vein} for the ore, not the lesson. The lesson moved out a while ago.",
		"{vein}. Taught me nothing. Hit it anyway. Habit is a vein too.",
		"{vein} in {zone}. No skill, just coin. Coin's fine. Coin's great, actually.",
		"Old friend {vein}. We don't talk much any more. I still visit.",
		"{vein}. Too easy now. Mined it with my eyes half shut and missed twice. Eyes open from now on.",
		"Back on {vein} for a smith with an order. The trade is mostly errands, it turns out.",
		"{vein}: nothing left to learn, plenty left to sell.",
		"{vein} again. A grown miner, picking on rocks half my level.",
		"{vein}. I could do this in my sleep. Lately I do; the dreams go clink.",
		"{vein} in {zone}, for old times' sake and new bags' worth.",
	},
	-- Forty stone in a day.
	stone = {
		"{n} lumps of stone today. I don't carry my bags any more. I'm a quarry with legs.",
		"Bags: {n} stone. Me: one person. One of us is outnumbered.",
		"{n} stone. A goblin offered to buy me by the pound.",
		"Carrying {n} stone. Rock bottom isn't a place. It's my backpack.",
		"{n} stones in the bag. I've built a small hill and I'm taking it for a walk.",
		"{n} stone. The smiths call it sharpening stone. My shoulders call it other things.",
		"{n} pieces of stone. Legally I am now a hill. Sheep have started following me.",
		"Hauling {n} stone across {zone}. The wildlife steps aside. Not from fear. From pity.",
		"{n} stone. I could build a wall. I could build a wall around myself and have a lie down.",
		"{n} stone. Every rock I break makes three smaller rocks. This is how mountains win.",
	},
	-- The first bar of each kind (special lines by name for some).
	smelt = {
		"First {bar} out of the forge. It glowed. So did my sleeves, briefly.",
		"Smelted my first {bar}. Ore goes in ugly and comes out handsome. There's hope for me.",
		"{bar}! The forge hissed. I hissed back. Mutual respect.",
		"First {bar}. Hot, heavy, and the only thing I've made that doesn't need an apology.",
		"Poured a {bar}. Weighed it in my hand: proud. Weighed it again: heavy. Less proud.",
		"{bar}, my first. Lost an eyebrow, gained a trade. Seems fair.",
		"Turned rock into {bar}. Alchemists turn lead into gold and nobody believes them. I turn rock into bars and nobody's impressed. Same struggle.",
		"{bar}. Fire, rock and patience. I brought two of the three.",
		"First {bar}. Every bar starts as a rock somebody was rude to. That somebody was me.",
		"Made a {bar}. Stood by the forge admiring it too long. Now I smell like a forge. Worth it.",
		"{bar}! Stacked it neatly in my bag. The bag has never been neat. It doesn't know what to do with itself.",
	},
	smeltSpecial = {
		["Bronze Bar"] = "Bronze: copper and tin, married in a furnace. I officiated. Lovely ceremony, very hot.",
		["Steel Bar"] = "Steel. Iron, coal, and a great deal of shouting at the fire. I did the shouting.",
		["Gold Bar"] = "A Gold Bar. Held it a long while. Didn't feel rich. Felt heavy. Rich people must just be strong.",
		["Truesilver Bar"] = "A Truesilver Bar. Even molten it looked honest.",
		["Dark Iron Bar"] = "Dark Iron, at the Black Forge, in a mountain that wants me dead. My favourite kind of workshop.",
		["Thorium Bar"] = "A Thorium Bar. It hums in the bag. We've agreed not to discuss it.",
		["Azerothium Bar"] = "An Azerothium Bar. A bar named after the whole world. No pressure.",
		["Heavy Thorium Bar"] = "Heavy Thorium Bar, out of my own foundry. Dropped it on my foot to test the name. The name holds.",
		["Elementium Bar"] = "Elementium. A Fiery Core, ten Arcanite and nerve. I was short on the nerve.",
	},
	-- A smelt newly in the spellbook.
	learned = {
		"New smelt: {bar}. One more thing to melt. Nothing is safe.",
		"Learned {bar}. My list of smelts gets longer. My eyebrows get shorter.",
		"I can smelt {bar} now. The ore doesn't know yet. It'll find out.",
		"Learned {bar}. Knowledge costs coin. Fire is free.",
		"{bar}: learned it. Haven't made it. Will make it. Will burn myself making it.",
		"Learned the trick of {bar}. It's mostly heat. Most tricks are mostly heat.",
		"{bar}. Another way to turn a mountain into money.",
	},
	-- Fifty veins in a day, once.
	batch = "{n} veins in one day. My arms have applied for independence.",
	-- Veins mined, in all.
	total = {
		[100] = "A hundred veins. Stack them up and you'd have a mountain, which is where they came from. Circle of life.",
		[250] = "Two hundred and fifty veins. My pick has a groove where my hand goes. My hand has one where the pick goes.",
		[500] = "Five hundred veins. Somewhere a mountain is noticeably thinner.",
		[1000] = "A thousand veins. I hear rocks in my sleep. They say clink. Only ever clink.",
		[2500] = "Two and a half thousand veins. Rock bottom is a long way down, and I'm making excellent time.",
		[5000] = "Five thousand veins. They'll name a tunnel after me. Probably \"that one\".",
	},
	skill = {
		[25] = "Mining 25. I can tell copper from mud now. Usually.",
		[50] = "Mining 50. Promoted from hitting rocks to hitting rocks professionally.",
		[75] = "Mining 75. The ground has started to look like a menu.",
		[100] = "Mining 100. Three figures. Celebrated by hitting a rock. What else.",
		[125] = "Mining 125. Iron's open. So is a new kind of back pain.",
		[150] = "Mining 150. Halfway down. The view is mostly wall.",
		[175] = "Mining 175. Mithril's in reach. Dwarves have started nodding at me in the street.",
		[200] = "Mining 200. Two hundred points of skill, and still a rock between me and everything I want.",
		[225] = "Mining 225. My pick and I have stopped arguing. We just look at each other now.",
		[250] = "Mining 250. Thorium hums when I walk past. I think it's nervous.",
		[275] = "Mining 275. Nearly there. \"There\" being the very bottom. Can't wait.",
		[300] = "Mining 300. Rock bottom. Turns out it's rather nice. Quiet. Full of ore.",
		other = "Mining {skill}. Deeper.",
	},
	-- A new rank (by its cap).
	rank = {
		[150] = "Journeyman. The trade has given me a title and a heavier pick. Mostly the pick.",
		[225] = "Expert. Experts know which rocks to hit. I still hit all of them, just more knowledgeably.",
		[300] = "Artisan. Artisans make art. I make holes. From the right angle, same thing.",
	},
}
