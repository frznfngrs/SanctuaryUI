SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.FishingData = ns.FishingData or {}
local D = ns.FishingData

-- The angler's journal's book: WoW Forever (1.60.1) fishing, gathered 2026-11-13 from
-- wow-professions.com, warcrafttavern.com, method.gg, wow.gg, warcraft.wiki.gg and Wowhead's
-- Forever database, plus the vanilla tables Forever kept. Things only one doubtful source
-- claims live in TALL_TALES, not in the guide. Item IDs only where a source showed them.
--
-- Zone names are the client's English names (GetRealZoneText / GetSubZoneText).

---------------------------------------------------------------------------
-- Fish and other catches. key -> { id, name, where, use, quip, forever }

D.FISH = {
	smallfish = { id = 6291, name = "Raw Brilliant Smallfish", where = "Inland, starting zones and capitals", use = "Brilliant Smallfish; the Fish Bowl camp object", quip = "Small. Brilliant. Like me at level 1." },
	mackerel = { id = 6303, name = "Raw Slitherskin Mackerel", where = "Starting coasts (Durotar, Darkshore, Teldrassil)", use = "Slitherskin Mackerel", quip = "Slithers. Skins. Mackerels. All three, somehow." },
	longjaw = { id = 6289, name = "Raw Longjaw Mud Snapper", where = "Inland, skill-75 zones and capitals", use = "Longjaw Mud Snapper", quip = "Jaw: long. Personality: muddy." },
	albacore = { id = 6361, name = "Raw Rainbow Fin Albacore", where = "Coast, skill 75-150 zones (Westfall, Darkshore, Wetlands)", use = "Rainbow Fin Albacore", quip = "Tastes like the colour blue." },
	frenzy = { id = 6317, name = "Raw Loch Frenzy", where = "Loch Modan, the loch itself", use = "Loch Frenzy Delight (+3 Fishing)", quip = "Only lives in the dwarves' man-made loch. Won't say how it got there." },
	catfish = { id = 6308, name = "Raw Bristle Whisker Catfish", where = "Inland, capitals and skill-150 zones", use = "Bristle Whisker Catfish (+8 Fishing)", quip = "Has a moustache. Respect the moustache." },
	cod = { id = 6362, name = "Raw Rockscale Cod", where = "Coast, skill 150-225 zones (Wetlands, Hillsbrad, Desolace, Stranglethorn)", use = "Rockscale Cod (+12 Fishing)", quip = "Scales like rock. Bones like regret." },
	sagefish = { id = 21071, name = "Raw Sagefish", where = "Sagefish Schools, inland skill-75/150 waters", use = "Smoked Sagefish (mana regeneration)", quip = "Wise. Not wise enough to avoid a hook." },
	oily = { id = 6358, name = "Oily Blackmouth", where = "Oily Blackmouth Schools on coasts from skill 75", use = "Blackmouth Oil (Alchemy)", quip = "Squeeze it. Alchemists will thank you." },
	firefin = { id = 6359, name = "Firefin Snapper", where = "Firefin Snapper Schools on coasts from skill 75", use = "Fire Oil (Alchemy)", quip = "Hot to the touch. Do not kiss." },
	deviate = { id = 6522, name = "Deviate Fish", where = "The Barrens' oases and Wailing Caverns' pools", use = "Savory Deviate Delight (recipe from Barrens mobs)", quip = "Naralex's nightmares, with fins. Eat it: pirate, ninja or skeleton." },
	whimsyfin = { name = "Whimsyfin", where = "Rivers of the Redridge Mountains (cast from 55)", use = "Savory Whimsyfin Delight: an hour as an ogre or a murloc (recipe drops in Redridge)", quip = "Raw, it makes you dance or nap. Cooked, it makes you a murloc.", forever = true },
	sickly = { id = 6299, name = "Sickly Looking Fish", where = "Undercity's canals, Tirisfal", use = "Very little", quip = "Raised in the Apothecaries' runoff. Looks how I feel after the canals." },
	trout = { id = 8365, name = "Raw Mithril Head Trout", where = "Inland, skill-225 zones (Arathi, Alterac, Dustwallow, Desolace)", use = "Mithril Headed Trout; the Fishing Rack camp object", quip = "Its head is not actually mithril. I checked. With a pick." },
	greatersage = { id = 21153, name = "Raw Greater Sagefish", where = "Greater Sagefish Schools, inland skill-225 waters", use = "Sagefish Delight (mana regeneration)", quip = "The sagefish's older, wiser, tastier cousin." },
	yellowtail = { id = 4603, name = "Raw Spotted Yellowtail", where = "Coast, skill 225-300 (Tanaris, Hinterlands, Stranglethorn)", use = "Spotted Yellowtail", quip = "Spotted. Yellow. Tail. Accurate name, for once." },
	mightfish = { id = 13754, name = "Raw Glossy Mightfish", where = "Coast, skill 225-300 (Stranglethorn, Tanaris, Feralas)", use = "Cooked Glossy Mightfish", quip = "Glossy. Mighty. Moisturised." },
	redgill = { id = 13758, name = "Raw Redgill", where = "Inland, skill 300: Western Plaguelands, Hinterlands, Felwood, Un'Goro, Moonglade", use = "Filet of Redgill (+18 Fishing)", quip = "Red gills. Big appetite. Same, buddy." },
	nightfin = { id = 13759, name = "Raw Nightfin Snapper", where = "Inland high waters, at night (6 PM to 6 AM realm time)", use = "Nightfin Soup (mana regeneration)", quip = "Only bites at night. Goth fish." },
	sunscale = { id = 13760, name = "Raw Sunscale Salmon", where = "Inland high waters, by day (6 AM to 6 PM realm time)", use = "Poached Sunscale Salmon (health regeneration)", quip = "A morning fish. Insufferable about it." },
	bass = { id = 13756, name = "Raw Summer Bass", where = "High coasts in the warm half of the year", use = "Cooking", quip = "Seasonal. Like my motivation." },
	squid = { id = 13755, name = "Winter Squid", where = "High coasts in the cold half of the year", use = "Grilled Squid (Agility)", quip = "Too many arms for a fish. Not complaining." },
	stonescale = { id = 13422, name = "Stonescale Eel", where = "Stonescale Eel Swarms on high coasts (Stranglethorn, Tanaris, Feralas, Azshara)", use = "Stonescale Oil, Elixir of Superior Defense", quip = "Alchemists pay well. Eels bite back." },
	whitescale = { id = 13889, name = "Raw Whitescale Salmon", where = "Inland skill-425 waters (Winterspring, Silithus)", use = "Baked Salmon", quip = "Frost-bitten and proud." },
	lobster = { id = 13888, name = "Darkclaw Lobster", where = "Skill-425 coasts (Azshara's Bay of Storms)", use = "Lobster Stew", quip = "Pinched me twice. Delicious revenge." },
	largemight = { id = 13893, name = "Large Raw Mightfish", where = "Skill-425 coasts (Azshara)", use = "Mightfish Steak", quip = "Like a Glossy Mightfish that skipped leg day never." },
	armorfish = { id = 13890, name = "Plated Armorfish", where = "High coasts (Azshara, Feralas)", use = "Plated Armorfish (new Forever recipe, Cooking 225)", quip = "Wearing more armour than my warrior friend." },
	tastyfish = { id = 19807, name = "Speckled Tastyfish", where = "Stranglethorn pools, only during the Extravaganza", use = "40 win the Extravaganza; Jang buys 5 for coin; rots in 4 hours", quip = "Tasty. Speckled. Worth fighting goblins for." },
	-- Nat Pagle's quest fish: only while on "Nat Pagle, Angler Extreme".
	ahi = { id = 16967, name = "Feralas Ahi", where = "Verdantis River, Feralas (quest only)", use = "Nat Pagle, Angler Extreme", quip = "Lives in a high-skill river. Bring Bright Baubles." },
	striker = { id = 16968, name = "Sar'theris Striker", where = "Sar'theris Strand, Desolace (quest only)", use = "Nat Pagle, Angler Extreme", quip = "Strikes. Missed." },
	sailfin = { id = 16969, name = "Savage Coast Blue Sailfin", where = "Savage Coast, Stranglethorn (quest only)", use = "Nat Pagle, Angler Extreme", quip = "Blue, savage, coastal. My kind of fish." },
	mahimahi = { id = 16970, name = "Misty Reed Mahi Mahi", where = "Misty Reed Strand, Swamp of Sorrows (quest only)", use = "Nat Pagle, Angler Extreme", quip = "So good they named it twice." },
}

-- Items the book names in passing (reagents, blueprints, books): linked wherever they appear.
D.ITEMS = {
	["Blueprint: Fishing Rack"] = 273141,
	["Blueprint: Fishing Hut"] = 273119,
	["Seasonal Fish Steaks"] = 273295,
	["Empty Vial"] = 3371,
	["Crystal Vial"] = 8925,
	["Simple Wood"] = 4470,
	["Bolt of Runecloth"] = 14048,
	["Extravagant Extravaganza Coin"] = 274026,
	["Expert Fishing - The Bass and You"] = 16083,
	["Expert Fishing"] = 16083,
	["Artisan Fishing - The Way of the Lure"] = 16082,
}

-- The order fish appear in the catalog: by the skill their waters need.
D.FISH_ORDER = {
	"smallfish", "mackerel", "longjaw", "frenzy", "sickly", "deviate", "albacore", "sagefish", "oily", "firefin",
	"catfish", "whimsyfin", "cod", "trout", "greatersage", "yellowtail", "mightfish", "stonescale", "armorfish",
	"redgill", "nightfin", "sunscale", "bass", "squid", "whitescale", "lobster", "largemight",
	"tastyfish", "ahi", "striker", "sailfin", "mahimahi",
}

-- Things the water gives that aren't fish.
D.OTHER_CATCHES = {
	{ name = "Floating Wreckage", text = "Coastal and lake pools. Forever's wreckage gives fish, cloth bolts, leathers, sometimes a 14-slot bag." },
	{ name = "Schools", text = "Schools of fish crowd coasts, lakes and rivers. Land the bobber inside the ring. Each one gives a few casts." },
	{ name = "Footlockers and trunks", text = "Locked boxes from wreckage and open water, their loot matching the zone. Rogues, or a blacksmith's key, open them." },
	{ name = "Bloated fish", text = "With a camp buff and a lure, open water now and then gives uncommon or rare \"bloated\" fish with valuables inside." },
	{ name = "Patch of Elemental Water", text = "High coasts (Azshara's bays, Silithus): Elemental Water, a little of Neptulon the Tidehunter leaking into the world. He's said to keep count." },
	{ name = "Junk", text = "Boots, bones, rusty things. The river's way of saying no." },
}

---------------------------------------------------------------------------
-- Waters. Each zone's skill is the one at which nothing gets away there. 95 below it nothing
-- bites at all (Redridge: 150, so it opens at 55). Lures and poles count toward both.

D.ESCAPE_GAP = 95

-- What usually bites in a zone of each band: inland, coast, pools.
D.BANDS = {
	[25] = { inland = { "smallfish", "longjaw" }, coast = { "mackerel" } },
	[75] = { inland = { "longjaw", "smallfish", "catfish" }, coast = { "mackerel", "albacore" }, pools = { "oily", "firefin", "sagefish" } },
	[150] = { inland = { "catfish", "longjaw" }, coast = { "albacore", "cod" }, pools = { "sagefish", "oily", "firefin" } },
	[225] = { inland = { "trout", "catfish" }, coast = { "cod", "yellowtail", "mightfish" }, pools = { "greatersage", "firefin", "oily" } },
	[300] = { inland = { "redgill", "nightfin", "sunscale" }, coast = { "yellowtail", "mightfish", "bass", "squid" }, pools = { "stonescale" } },
	[425] = { inland = { "whitescale", "redgill", "nightfin", "sunscale" }, coast = { "lobster", "largemight", "armorfish", "bass", "squid" }, pools = { "stonescale" } },
}

-- name, skill, coast?, extra fish keys, note (for everyone).
--   side: whose land it is (A or H): the other faction is a guest there, and the guards know.
--   hub: the friendly town for each side (A, H; N for a neutral one both can use).
--   A, H: notes only that faction needs (its trainer, its vendors, its quest).
D.ZONES = {
	{ "Elwynn Forest", 25, false, nil, "Crystal Lake, east of Goldshire. Half of Stormwind caught its first fish here; the other half bought one at the inn and said they did.", side = "A", hub = { A = "Goldshire" }, A = "Lee Brown teaches by the shore." },
	{ "Dun Morogh", 25, false, nil, "Iceflow Lake. Bring a coat.", side = "A", hub = { A = "Kharanos" }, A = "Paxton Ganter teaches at the lake." },
	{ "Teldrassil", 25, true, nil, "Lake Al'Ameth, south of Dolanaar.", side = "A", hub = { A = "Dolanaar" }, A = "Astaia in Darnassus trains; Narret Shadowgrove in Dolanaar sells the pole." },
	{ "Mulgore", 25, false, nil, "Stonebull Lake by Bloodhoof Village. The best Horde start.", side = "H", hub = { H = "Bloodhoof Village" }, H = "Uthan Stillwater teaches; Harn Longcast sells the pole and recipes." },
	{ "Durotar", 25, true, nil, "The coast south of Sen'jin Village. Thrall named this land for his father, Durotan: red rock, sharks offshore, mostly mackerel.", side = "H", hub = { H = "Sen'jin Village" }, H = "Lau'Tiki teaches on the shore." },
	{ "Tirisfal Glades", 25, true, { "sickly" }, "Brightwater Lake, east of Brill.", side = "H", hub = { H = "Brill" }, H = "Clyde Kellen teaches at the lake." },
	{ "Zephras Isle", 25, true, nil, "Any lake or river by Shen'dar Village or Valanaar. Both factions welcome.", hub = { N = "Shen'dar Village, Valanaar" } },
	{ "Stormwind City", 75, false, nil, "The canals. Fish get away until 75.", side = "A", A = "Arnold Leland trains in the Trade District." },
	{ "Ironforge", 75, false, nil, "The Forlorn Cavern pools.", side = "A", A = "Grimnur Stonebrand trains there." },
	{ "Darnassus", 75, false, nil, "Temple Gardens' water.", side = "A", A = "Astaia trains in the Temple Gardens." },
	{ "Orgrimmar", 75, false, nil, "The pond in the Valley of Honor.", side = "H", H = "Lumak trains by the pond." },
	{ "Thunder Bluff", 75, false, nil, "The pond by the auction house.", side = "H", H = "Kah Mistrunner trains on the Middle Rise." },
	{ "Undercity", 75, false, { "sickly" }, "The canals under Lordaeron's ruins run green with whatever the Royal Apothecary Society poured in last. A third of the catch is junk. So is the smell.", side = "H", H = "Armand Cromwell trains in the Magic Quarter." },
	{ "Westfall", 75, true, nil, "Coast for albacore, schools of oily blackmouth and firefin.", side = "A", hub = { A = "Sentinel Hill" }, H = "The southern coast, past the Deadmines, is the quiet end." },
	{ "Loch Modan", 75, false, { "frenzy", "sagefish" }, "The loch is the dwarves' doing: they built the Stonewrought Dam to make it. Loch Frenzy live nowhere else, and haven't forgiven the dam.", side = "A", hub = { A = "Thelsamar" }, A = "Warg Deepwater teaches in Thelsamar.", H = "Fish the far shore from Thelsamar's guards." },
	{ "Darkshore", 75, true, nil, "Long coast.", side = "A", hub = { A = "Auberdine" }, A = "Gubber Blump's family pole quest starts in Auberdine.", H = "Night elf coast: no friendly roof for miles." },
	{ "Silverpine Forest", 75, true, nil, "Lakes and the western coast.", side = "H", hub = { H = "The Sepulcher" } },
	{ "The Barrens", 75, true, { "deviate", "sagefish" }, "Oasis pools give Deviate Fish: the druid Naralex has been dreaming badly in the Wailing Caverns below for years, and it leaked into the water. Ratchet's boat goes to Booty Bay.", hub = { H = "The Crossroads", N = "Ratchet" }, A = "Ratchet is neutral: your way to Booty Bay too." },
	{ "Blackfathom Deeps", 75, false, nil, "A night elf temple to Elune, sunk in the Sundering. Its murloc lord, Gelihast, drops Blueprint: Fishing Rack." },
	{ "Wailing Caverns", 75, false, { "deviate" }, "Deviate Fish in the cave pools, right under Naralex's nightmare." },
	{ "The Deadmines", 75, false, nil, nil },
	{ "Redridge Mountains", 150, false, { "whimsyfin", "sagefish" }, "Lake Everstill. Nothing bites below 55. Whimsyfin in the rivers. Lakeshire's bridge has been rebuilt more times than its guards admit.", side = "A", hub = { A = "Lakeshire" }, A = "Matthew Hooper teaches in Lakeshire.", H = "Lakeshire is Alliance; the lake's east shore is quieter." },
	{ "Duskwood", 150, false, nil, "The Rotted One drops Flesh Eating Worms (not worth farming).", side = "A", hub = { A = "Darkshire" } },
	{ "Wetlands", 150, true, nil, "Good coast for cod and schools. Menethil Harbor is slowly sinking into the marsh; its keep already stands with its feet in the water.", side = "A", hub = { A = "Menethil Harbor" }, A = "Harold Riggs teaches in Menethil Harbor." },
	{ "Hillsbrad Foothills", 150, true, nil, "Murlocs here drop the glove enchant.", hub = { A = "Southshore", H = "Tarren Mill" }, A = "Donald Rabonne teaches in Southshore; Hunter Moore on the island.", H = "Southshore is the enemy's; fish the rivers near Tarren Mill." },
	{ "Ashenvale", 150, true, nil, "Mystral Lake; Shandrina sells Nightcrawlers.", hub = { A = "Astranaar", H = "Splintertree Post" }, H = "Kil'Hiwana teaches at Zoram Strand." },
	{ "Stonetalon Mountains", 150, false, nil, "Open water to 205.", hub = { A = "Stonetalon Peak", H = "Sun Rock Retreat" }, H = "Kulwia at Sun Rock Retreat sells Nightcrawlers." },
	{ "Dustwallow Marsh", 225, true, nil, "Inland with Bright Baubles from 150. Nat Pagle, the greatest angler in Azeroth by his own account, camps on Tidefury Cove, a short swim from Theramore.", hub = { A = "Theramore Isle", H = "Brackenwall Village" } },
	{ "Desolace", 225, true, { "striker" }, "Sar'theris Strand for Nat Pagle. Shellfish Traps off the south-west coast hide the Big Iron pole.", hub = { A = "Nijel's Point", H = "Shadowprey Village" }, H = "Lui'Mala teaches in Shadowprey; Wulan sells the Expert Cookbook." },
	{ "Arathi Highlands", 225, true, { "greatersage" }, "Inland trout, Faldir's Cove on the coast.", hub = { A = "Refuge Pointe", H = "Hammerfall" } },
	{ "Alterac Mountains", 225, false, { "greatersage" }, "Trout in the lakes. Nobody's home; everyone's hostile." },
	{ "Stranglethorn Vale", 225, true, { "stonescale", "sailfin", "tastyfish" }, "Booty Bay: Expert book, trainer, recipes, and the Sunday Extravaganza. The Steamwheedle goblins keep it neutral; the shark hanging over the harbour reminds everyone.", hub = { N = "Booty Bay", H = "Grom'gol" } },
	{ "Swamp of Sorrows", 225, true, { "mahimahi" }, "Misty Reed Strand for Nat Pagle.", hub = { H = "Stonard" } },
	{ "Thousand Needles", 225, false, nil, "The Shimmering Flats were a lake once; now goblins race on the salt. Fish the canyons instead.", hub = { H = "Freewind Post", N = "Mirage Raceway" } },
	{ "Scarlet Monastery", 225, false, nil, nil },
	{ "Riverglades", nil, true, nil, "Its skill band isn't pinned down yet: start careful, watch the escapes.", hub = { N = "Powderfuse Port" }, A = "Krix teaches at Powderfuse Port (goblin, open to all).", H = "Krix teaches at Powderfuse Port (goblin, open to all)." },
	{ "Feralas", 300, true, { "ahi", "stonescale", "armorfish" }, "Any inland water to 300 (not Jademir Lake).", hub = { A = "Feathermoon Stronghold", H = "Camp Mojache" }, A = "Vivianna sells Nightcrawlers, Bright Baubles and Baked Salmon; Brannock trains.", H = "Sheendra Tallgrass sells Nightcrawlers, Bright Baubles and Baked Salmon." },
	{ "The Hinterlands", 300, true, nil, nil, hub = { A = "Aerie Peak", H = "Revantusk Village" }, H = "Katoom the Angler trains and gives \"Snapjaws, Mon!\" for Nat Pagle's pole." },
	{ "Tanaris", 300, true, { "stonescale" }, "Steamwheedle Port's Gikkix sells Nightfin Soup and Poached Sunscale Salmon recipes.", hub = { N = "Gadgetzan, Steamwheedle Port" } },
	{ "Western Plaguelands", 300, false, nil, "Darrowmere Lake for Redgill.", hub = { A = "Chillwind Camp" } },
	{ "Felwood", 300, false, nil, "Redgill, if you don't mind the sludge.", hub = { A = "Talonbranch Glade", H = "Bloodvenom Post", N = "Emerald Sanctuary" } },
	{ "Un'Goro Crater", 300, false, nil, "Redgill under the dinosaurs' noses.", hub = { N = "Marshal's Refuge" } },
	{ "Azshara", 300, true, { "stonescale", "armorfish" }, "Zin-Azshari, the night elves' old capital, sank off this coast in the Sundering, and its Highborne became the naga. The Bay of Storms (425) is the real prize.", hub = { A = "Talrendis Point", H = "Valormok" } },
	{ "Moonglade", 300, false, nil, "Lake Elune'ara, sacred to the Cenarion Circle. They allow fishing. They'd prefer you didn't make a face about the fish.", hub = { N = "Nighthaven" } },
	{ "Jaguero Isle", 300, true, nil, nil },
	{ "Maraudon", 300, false, nil, nil },
	{ "Sunken Temple", 300, false, nil, nil },
	{ "Winterspring", 425, false, nil, "Whitescale Salmon. Lure up: 300 skill alone won't do.", hub = { N = "Everlook" } },
	{ "Silithus", 425, true, nil, "Coast, and patches of Elemental Water: a little of Neptulon, the Lord of the Tides, leaking into the world.", hub = { N = "Cenarion Hold" } },
	{ "Eastern Plaguelands", 425, false, nil, nil, hub = { N = "Light's Hope Chapel" } },
	{ "Burning Steppes", 425, false, nil, nil, hub = { A = "Morgan's Vigil", H = "Flame Crest" } },
	{ "Deadwind Pass", 425, false, nil, nil },
	{ "Zul'Gurub", 425, true, nil, "The Gurubashi kept a hydra in one of these pools. Ask about Gahz'ranka at the inn (Tales & Lore)." },
	{ "Stratholme", 425, false, nil, nil },
	{ "Scholomance", 425, false, nil, nil },
	-- Sub-zones with a band of their own (GetSubZoneText).
	{ "Bay of Storms", 425, true, nil, "Azshara's hardest water, over the drowned streets of Zin-Azshari.", sub = true },
	{ "Hetaera's Clutch", 425, true, nil, nil, sub = true },
	{ "Scalebeard's Cave", 425, true, nil, nil, sub = true },
	{ "Jademir Lake", 425, false, nil, "Feralas' trap for the unwary: 425, not 300.", sub = true },
	{ "Verdantis River", 300, false, { "ahi" }, "Feralas Ahi, for Nat Pagle.", sub = true },
	{ "Sar'theris Strand", 225, true, { "striker" }, "Sar'theris Striker, for Nat Pagle.", sub = true },
	{ "Savage Coast", 225, true, { "sailfin" }, "Savage Coast Blue Sailfin, for Nat Pagle.", sub = true },
	{ "Misty Reed Strand", 225, true, { "mahimahi" }, "Misty Reed Mahi Mahi, for Nat Pagle.", sub = true },
	{ "Booty Bay", 225, true, { "tastyfish" }, "Old Man Heming (Expert book) and Myizz Luckycatch (trainer) under the hanging shark. Neutral: the Steamwheedle Cartel only cares about your gold.", sub = true },
}

D.ZONE_BY_NAME = {}
for _, z in ipairs(D.ZONES) do
	D.ZONE_BY_NAME[z[1]] = z
end

---------------------------------------------------------------------------
-- Trainers. name, zone, place, x, y, side (A, H or N for both)

D.TRAINERS = {
	{ "Fenn Fairweather", "Zephras Isle", "Shen'dar Village", 45.0, 48.4, "N" },
	{ "Baelann Swiftcurrent", "Zephras Isle", "Valanaar", 63.2, 75.7, "N" },
	{ "Myizz Luckycatch", "Stranglethorn Vale", "Booty Bay, under the shark", 27.5, 77.1, "N" },
	{ "Krix", "Riverglades", "Powderfuse Port", 79.2, 54.8, "N" },
	{ "Lee Brown", "Elwynn Forest", "Crystal Lake by Goldshire", 47.6, 62.3, "A" },
	{ "Paxton Ganter", "Dun Morogh", "Iceflow Lake", 35.6, 40.4, "A" },
	{ "Androl Oakhand", "Teldrassil", "Rut'theran Village", 55.8, 93.5, "A" },
	{ "Astaia", "Darnassus", "Temple Gardens", 47.6, 56.6, "A" },
	{ "Arnold Leland", "Stormwind City", "Trade District", 55.1, 69.6, "A" },
	{ "Grimnur Stonebrand", "Ironforge", "The Forlorn Cavern", 48.4, 6.4, "A" },
	{ "Warg Deepwater", "Loch Modan", "Thelsamar", 40.6, 39.6, "A" },
	{ "Matthew Hooper", "Redridge Mountains", "Lakeshire", 26.8, 50.4, "A" },
	{ "Harold Riggs", "Wetlands", "Menethil Harbor", 8.2, 58.5, "A" },
	{ "Donald Rabonne", "Hillsbrad Foothills", "Southshore", 50.4, 61.0, "A" },
	{ "Hunter Moore", "Hillsbrad Foothills", "the island off the coast", 54.0, 80.4, "A" },
	{ "Brannock", "Feralas", "Feathermoon Stronghold", 32.2, 41.5, "A" },
	{ "Uthan Stillwater", "Mulgore", "Stonebull Lake, Bloodhoof Village", 44.6, 60.6, "H" },
	{ "Lau'Tiki", "Durotar", "Sen'jin Village coast", 53.2, 81.6, "H" },
	{ "Clyde Kellen", "Tirisfal Glades", "Brightwater Lake", 67.2, 51.0, "H" },
	{ "Lumak", "Orgrimmar", "Valley of Honor", 69.8, 29.4, "H" },
	{ "Kah Mistrunner", "Thunder Bluff", "Middle Rise", 56.1, 46.7, "H" },
	{ "Armand Cromwell", "Undercity", "The Magic Quarter", 80.9, 31.1, "H" },
	{ "Kil'Hiwana", "Ashenvale", "Zoram Strand", 10.8, 33.6, "H" },
	{ "Lui'Mala", "Desolace", "Shadowprey Village", 22.6, 72.6, "H" },
	{ "Katoom the Angler", "The Hinterlands", "Revantusk Village", 80.3, 81.4, "H" },
}

-- Ranks: cap, what opens it.
D.RANKS = {
	{ "Apprentice", 75, "Any fishing trainer. No level needed." },
	{ "Journeyman", 150, "Any fishing trainer, at Fishing 50 and level 10." },
	{ "Expert", 225, "The book Expert Fishing - The Bass and You (1 gold, tradeable) from Old Man Heming in Booty Bay (27.4, 77.0), at Fishing 125 and level 20. He's fished that bay since before the goblins charged docking fees; ask about the one that got away if your afternoon is free.", item = 16083 },
	{ "Artisan", 300, "The quest Nat Pagle, Angler Extreme from Nat Pagle at Tidefury Cove, Dustwallow Marsh (58.6, 60.0), at Fishing 225 and level 35; it rewards Artisan Fishing - The Way of the Lure. He fishes with an ale in one hand; nobody has seen the other let go of the pole.", item = 16082 },
}

---------------------------------------------------------------------------
-- The road from 1 to 300. skill range, Alliance, Horde, tip.

D.ROUTE = {
	{ "1-75", "Elwynn's Crystal Lake, Dun Morogh's Iceflow Lake or Teldrassil's Lake Al'Ameth", "Mulgore's Stonebull Lake, Durotar's coast or Tirisfal's Brightwater Lake", "Both: Zephras Isle. A Shiny Bauble (+25) makes the first casts sure. Learn Journeyman at 50 (level 10)." },
	{ "75-130", "Stormwind's canals (or Westfall, Loch Modan, Darkshore)", "Thunder Bluff's pond, Orgrimmar's Valley of Honor, or the Undercity canals (or the Barrens, Silverpine)", "Capitals stop losing fish at 75. Expect smallfish, mud snappers and catfish." },
	{ "125", "Booty Bay", "Booty Bay (boat from Ratchet)", "Buy Expert Fishing from Old Man Heming, and Bright Baubles while you're there." },
	{ "130-205", "Redridge's Lake Everstill, Duskwood, Wetlands, Ashenvale's Mystral Lake", "Stonetalon (Nightcrawlers from Kulwia), Ashenvale's Mystral Lake", "Nightcrawlers (+50) on the pole the whole way." },
	{ "205-225", "Dustwallow Marsh, inland", "Dustwallow Marsh, inland", "Bright Baubles (+75) from 150. Buy Nightcrawlers in Ratchet first: nobody in Dustwallow sells them. Don't fish the ocean." },
	{ "225", "Nat Pagle, Tidefury Cove", "Nat Pagle, Tidefury Cove", "Level 35 for Artisan. Four fish, four zones. Save an Aquadynamic Fish Attractor for the Feralas Ahi." },
	{ "225-300", "Feralas from Feathermoon (Vivianna sells lures and Baked Salmon)", "Feralas from Camp Mojache (Sheendra Tallgrass, same)", "Any inland Feralas water but Jademir Lake. Or Felwood, the Hinterlands, Tanaris, Un'Goro, Western Plaguelands. Lure always on." },
	{ "300+", "Winterspring, Azshara's Bay of Storms, Silithus", "Winterspring, Azshara's Bay of Storms, Silithus", "425 waters: Arcanite pole (+35) and an Attractor (+100) on 300 make 435. Nothing gets away." },
}

---------------------------------------------------------------------------
-- Tackle. name, item, +skill, needs, source

D.POLES = {
	{ "Fishing Pole", 6256, 0, 1, "Fishing and trade supply vendors, for copper." },
	{ "Blump Family Fishing Pole", 12225, 3, 1, "\"The Family and the Fishing Pole\", Gubber Blump in Auberdine, Darkshore.", side = "A" },
	{ "Strong Fishing Pole", 6365, 5, 10, "Vendors." },
	{ "Ravaged Fishing Pole", 285094, 15, 50, "New in Forever. Where it comes from isn't known yet." },
	{ "Big Iron Fishing Pole", 6367, 20, 100, "About 1% from Shellfish Traps in the sea off south-west Desolace. Tradeable." },
	{ "Nat Pagle's Extreme Angler FC-5000", 19022, 25, 100, "\"Snapjaws, Mon!\" from Katoom the Angler, Revantusk Village, the Hinterlands.", side = "H" },
	{ "Arcanite Fishing Pole", 19970, 35, 300, "Win the Stranglethorn Fishing Extravaganza." },
}

-- name, item, +skill, needs, source (lures last 10 minutes; the Attractor 5)
D.LURES = {
	{ "Shiny Bauble", 6529, 25, 1, "Pole vendors everywhere." },
	{ "Nightcrawlers", 6530, 50, 50, { { "Kilxx in Ratchet, Shandrina at Mystral Lake (Ashenvale); undead sometimes drop them", "N" }, { "Vivianna at Feathermoon (Feralas)", "A" }, { "Kulwia at Sun Rock Retreat (Stonetalon), Sheendra Tallgrass at Camp Mojache (Feralas)", "H" } } },
	{ "Aquadynamic Fish Lens", 6811, 50, 50, "Engineers, and Fishing Rack camps." },
	{ "Bright Baubles", 6532, 75, 100, { { "Old Man Heming in Booty Bay, Fishing Rack camps", "N" }, { "Vivianna at Feathermoon", "A" }, { "Sheendra Tallgrass at Camp Mojache", "H" } } },
	{ "Flesh Eating Worm", 7307, 75, 100, "The Rotted One, Duskwood. Not worth hunting." },
	{ "Aquadynamic Fish Attractor", 6533, 100, 100, "Engineers and some suppliers. Lasts 5 minutes. Hoard them." },
}

-- name, item, +skill, source
D.GEAR = {
	{ "Lucky Fishing Hat", 19972, 5, "Keefer's Angelfish, a rare Extravaganza catch, turned in to the Fishbot 5000." },
	{ "Nat Pagle's Extreme Anglin' Boots", 19969, 5, "Brownell's Blue Striped Racer, same deal." },
	{ "High Test Eternium Fishing Line", 19971, 5, "Dezian Queenfish, same deal. Goes on the pole." },
	{ "Enchant Gloves - Fishing", nil, 2, "Enchanters; the formula drops from Hillsbrad's murlocs." },
	{ "Surfer Shoes", 276274, 0, "Walk on water. One Extravaganza coin from Jang." },
	{ "Hook of the Master Angler", 19979, 0, "Trinket: turns you into a fish (breathe underwater, swim fast). One coin from Jang." },
	{ "Chef's Knife", 273636, 0, "New in Forever: prepares Unique Fish. Cooking and trade vendors in most towns." },
}

-- Food with a Fishing skill buff (15 min). name, item, +skill, level
D.FOOD = {
	{ "Loch Frenzy Delight", 6316, 3, 5 },
	{ "Fillet of Frenzy", 5476, 5, 5 },
	{ "Bristle Whisker Catfish", 4593, 8, 15 },
	{ "Rockscale Cod", 4594, 12, 25 },
	{ "Filet of Redgill", 13930, 18, 35 },
	{ "Spinefin Halibut", 8957, 18, 45 },
}

-- Legacy talents (the Professions tree). name, text
D.TALENTS = {
	{ "Luremaster", "With a lure on, 25% (rank 2: 50%) chance to catch an extra fish. Needs 5 points in the tree." },
	{ "Working Overtime", "Up to 20% more skill-ups from every trade skill, fishing included." },
	{ "Dedicated Study", "+1 to your lowest trade skill, daily-ish (23 h cooldown). At 300 in all five: Elemental Essences instead." },
}

---------------------------------------------------------------------------
-- Camp: Bait & Tackle. name, item, skill, reagents, buff, blueprint

D.CAMP = {
	{ "Fish Bowl", 279967, 20, "1 Raw Brilliant Smallfish, 1 Empty Vial", "+8% to all stats for everyone sitting near (not with Blessing of Kings).", "Taught by every fishing trainer, or the quest Camping 101: Fishing in the starting zones." },
	{ "Fishing Rack", 279965, 140, "2 Simple Wood, 1 Crystal Vial, 2 Raw Mithril Head Trout", "Uncommon fish for an hour, and lures. Includes the Fish Bowl's buff.", "Blueprint: Fishing Rack (273141) from Gelihast, Blackfathom Deeps." },
	{ "Fishing Hut", 279966, 300, "5 Simple Wood, 2 Bolt of Runecloth, 1 Seasonal Fish Steaks", "Rare fish for an hour, and lures. Includes the Fish Bowl's buff.", "Blueprint: Fishing Hut (273119). Where it drops isn't known yet." },
}

D.CAMP_RULES = {
	"Learning Fishing teaches Bait & Tackle too: a crafting menu, materials on the right, Create or Create All.",
	"Camp objects need a campfire beside them, and share one 1-hour camping cooldown.",
	"A higher tier can be put down over a lower one at the same camp, cooldown or not.",
	"Blueprints are looted or bought from other players.",
}

---------------------------------------------------------------------------
-- The Stranglethorn Fishing Extravaganza.

D.EXTRAVAGANZA = {
	when = "Sundays, 2 to 4 PM (region time: Pacific for the Americas, CEST for Europe). Turn-ins stay open to 5.",
	how = "Catch 40 Speckled Tastyfish from the pools along Stranglethorn's coast and hand them to Riggle Bassbait in Booty Bay, who has run this race longer than anyone there admits to remembering.",
	win = "The first 50 to turn in win (it used to be one per realm): the Arcanite Fishing Pole (+35) and an Extravagant Extravaganza Coin.",
	casual = "Not fast enough? Jang pays coin for every 5 Tastyfish. They rot after 4 hours, so don't hoard them.",
	rare = "Rare catches during the event go to the Fishbot 5000 (nobody knows who built it, and nobody asks Riggle): Keefer's Angelfish for the Lucky Fishing Hat, Brownell's Blue Striped Racer for Nat Pagle's Anglin' Boots, Dezian Queenfish for the Eternium line.",
	coin = {
		{ "Hook of the Master Angler", 19979, "Trinket: become a fish. Breathe water, swim fast." },
		{ "Surfer Shoes", 276274, "Walk on water. The fish find it deeply unfair." },
		{ "Master Angler's Fishing Hat", nil, "Cosmetic. Pure swagger." },
		{ "Empty Fish Bucket", nil, "Cosmetic off-hand. Empty. Like your bags after the race." },
		{ "Bitter Baitling", nil, "A pet. It's bitter. It knows what you did to its family." },
	},
}

-- Nat Pagle's Artisan quest fish: key list for the catalog and Here & Now.
D.NAT_PAGLE = { "ahi", "striker", "sailfin", "mahimahi" }

-- Other fishing quests. name, giver, place, reward
D.QUESTS = {
	{ "Nat Pagle, Angler Extreme", "Nat Pagle", "Tidefury Cove, Dustwallow Marsh", "Artisan Fishing (level 35, Fishing 225)." },
	{ "Snapjaws, Mon!", "Katoom the Angler", "Revantusk Village, the Hinterlands", "Nat Pagle's Extreme Angler FC-5000 (+25).", side = "H" },
	{ "The Family and the Fishing Pole", "Gubber Blump", "Auberdine, Darkshore", "Blump Family Fishing Pole (+3).", side = "A" },
	{ "Camping 101: Fishing", "starting-zone camp teachers", "every starting zone", "The Fish Bowl camp recipe." },
}

-- Cooking recipes worth knowing about for your catch: name, then { where, side } for each seller.
D.RECIPES = {
	{ "Brilliant Smallfish, Longjaw Mud Snapper", { { "Nyalah Brightfire, Valanaar (Zephras Isle)", "N" }, { "Tharynn Bouden, Goldshire; Nyoma, Dolanaar; Gretta Ganter, Dun Morogh", "A" }, { "Harn Longcast, Bloodhoof Village; Martine Tramblay, Tirisfal; Lizbeth Cromwell, Undercity", "H" } } },
	{ "Slitherskin Mackerel", { { "Zansoa, Sen'jin Village", "H" } } },
	{ "Bristle Whisker Catfish", { { "Catherine Leland, Stormwind", "A" }, { "Naal Mistrunner, Thunder Bluff; Ronald Burch, Undercity", "H" } } },
	{ "Mithril Head Trout, Filet of Redgill", { { "Kelsey Yance, Booty Bay", "N" } } },
	{ "Nightfin Soup, Poached Sunscale Salmon", { { "Gikkix, Steamwheedle Port, Tanaris", "N" } } },
	{ "Baked Salmon", { { "Vivianna, Feathermoon Stronghold", "A" }, { "Sheendra Tallgrass, Camp Mojache", "H" } } },
	{ "Savory Whimsyfin Delight", { { "Drops from Redridge's mobs", "N" } } },
	{ "Savory Deviate Delight", { { "Drops from the Barrens' pirates and mobs", "N" } } },
}

---------------------------------------------------------------------------
-- Tall tales: claims from a single source we couldn't confirm. Kept apart, for the honest.

-- What the journal says about the other faction's things.
D.ENEMY = {
	A = { "Alliance only. Bribe a gnome.", "Alliance only. Ask a dwarf. Bring ale.", "Alliance only. Look wistful near Stormwind." },
	H = { "Horde only. Ask an orc nicely. From a distance.", "Horde only. Tauren are friendly. Their guards aren't.", "Horde only. The Forsaken would sell it to you. Then you." },
	land = {
		A = "Alliance land. The guards have opinions about you.",
		H = "Horde land. The guards have axes about you.",
	},
}

D.TALL_TALES = {
	{ "A Mount Hyjal with Lightning Eels", "One beta write-up lists new zones (Mount Hyjal, Shenrolis, Doran) with Lightning Eels in Hyjal's water. Nobody else mentions them." },
	{ "Lefay's Ring of Precise Spell Power", "Said to sit in a bloated fish's belly. Said by one person. Probably after the inn." },
	{ "The Riverglades band", "One guide puts the Riverglades at skill 135-205. It also called Old Man Heming a Horde trainer, so." },
	{ "\"Secret\" Bait and the Wide-Brimmed Fishing Hat", "Listed in a database as +25 for 10 minutes. Where they come from: a secret, apparently." },
	{ "Angler's Mantle, Primitive Fishing Pole", "Seen in item lists (a cosmetic mantle, a polearm you can fish with?). No source yet." },
	{ "Luremaster rank 2", "One source says the 50% rank is unconfirmed. The talent page shows two ranks." },
}

---------------------------------------------------------------------------
-- Lore. Most of it lives inside the book's own lines (zone notes, fish, the people). These are
-- what the diary says the first time you catch something in a place with a story...

D.ZONE_LINES = {
	["Loch Modan"] = "First fish from Loch Modan. The dwarves built this lake on purpose. Respect.",
	["The Barrens"] = "First fish from the Barrens' waters. A druid's been having nightmares under this oasis for years. The fish taste like it.",
	["Wailing Caverns"] = "First fish from the Wailing Caverns. Naralex is still asleep. I fished quietly.",
	["Azshara"] = "First fish from Azshara. An empire drowned here. The fish seem fine with it.",
	["Dustwallow Marsh"] = "Fished Dustwallow. Waved at Nat Pagle. He waved his ale back.",
	["Stranglethorn Vale"] = "First fish from Stranglethorn. A goblin charged me for the view.",
	["Moonglade"] = "Fished Moonglade's holy lake. A druid watched the whole time. I said sorry to each fish.",
	["Undercity"] = "First fish from the Undercity canals. It glowed. I'm told that's normal here.",
	["Redridge Mountains"] = "First fish from Lake Everstill. The bridge held. The murlocs watched.",
	["Blackfathom Deeps"] = "Fished a sunken temple. Felt rude. Kept the fish anyway.",
}

-- ...and the old legends, as the diary tells them in Tales & Lore: stories heard at the inn.
D.LEGENDS = {
	{
		title = "Gahz'ranka",
		text = "Heard at the Booty Bay inn: in Zul'Gurub the Gurubashi trolls kept a great hydra, Gahz'ranka, in a churning pool. Cast in with a Mudskunk Lure and you don't catch a fish, you catch a raid boss. I've decided I'm happy with mackerel.",
	},
	{
		title = "The Maelstrom",
		text = "An old sailor told me that where the Well of Eternity sank ten thousand years ago, the Maelstrom still spins in the middle of the Great Sea. Sailors steer around it. Anglers dream about what's in it. Nobody's come back to say.",
	},
	{
		title = "Neptulon's count",
		text = "A shaman in Ratchet swore every patch of Elemental Water belongs to Neptulon the Tidehunter, Lord of the Tides, and that he keeps count of what's taken. I've bottled six. I sleep with a lantern on now.",
	},
}

---------------------------------------------------------------------------
-- The diary: chapter openers (in the angler's hand) and the lines the journal writes itself.

D.OPENERS = {
	diary = {
		"Day 1. The trainer handed me a stick with string on it and called it a profession. I have slain demons. How hard can a fish be?",
		"Day 2. Very hard.",
	},
	-- One more line, by faction.
	diaryA = { "Day 3. A night elf told me fish have feelings. I ate mine anyway. It felt fine about it." },
	diaryH = { "Day 3. Asked an orc for fishing tips. He hit the lake with an axe. Annoyingly, it worked." },
	now = { "Where am I, what bites here, and will it laugh at me? Let's find out." },
	route = { "A fishing pole is a stick with ambitions. So am I. Here's how we both grow." },
	waters = { "Every pond in Azeroth has a bouncer, usually a murloc. Below its number, the fish wave, laugh, and leave." },
	catches = { "Everything I've pulled out of the water, roughly in order of how much it smelled." },
	tackle = { "A lure is a lie you tell a fish. Tell bigger lies." },
	camp = { "Learned Bait & Tackle. Turns out camping is just fishing with furniture." },
	extravaganza = { "Every Sunday, grown adults race for forty Speckled Tastyfish in Stranglethorn. I've been to Hell. Hell was calmer." },
	tales = { "Stories from the Booty Bay inn, and a few from further off. I was sober for some of them." },
}

-- Auto entries. {fish}, {item}, {zone}, {n}, {skill} are filled in.
D.LINES = {
	first = { "First catch ever: a {fish}, in {zone}. I named it. Then I ate it. We grew close." },
	species = {
		"Met a {fish} in {zone}. It looked at me like I owed it gold.",
		"{fish}. New to me, old to the river. Into the bag.",
		"Caught a {fish}. Showed it to a guard. He did not care.",
		"A {fish}! The tavern will hear about this whether it wants to or not.",
		"{fish}, {zone}. Fought like a cornered imp. Lost like one too.",
		"A {fish}. I'd tell you to stay awhile and listen, but it's stopped talking.",
		"{fish}. I've stared down the Lord of Terror. This was scarier, briefly.",
		"New page for the {fish}. The page smells like it now. So do I.",
	},
	special = {
		[6522] = "Deviate Fish. Eat it and become a pirate, a ninja or a skeleton. Lunch is a gamble.",
		[6299] = "A Sickly Looking Fish. We have that in common after the Undercity canals.",
		[19807] = "Speckled Tastyfish. The race is on. The goblins are taking bets. Not on me.",
		[13422] = "Stonescale Eel. Bit me twice. Alchemists will pay for both bites.",
		[6317] = "Raw Loch Frenzy. Lives only in Loch Modan. Now lives in my bag.",
	},
	whimsyfin = "Caught a Whimsyfin. The cook says it turns you into an ogre or a murloc. I asked which. He said yes.",
	total = {
		[10] = "Ten fish. The bag smells like a decision I made.",
		[50] = "Fifty fish. Children follow me through town now. So do cats.",
		[100] = "One hundred fish. I dream in bobbers.",
		[250] = "Two hundred and fifty. The fish have a word for me now. It isn't nice.",
		[500] = "Five hundred. Murlocs nod at me with respect. Mrgllgl.",
		[1000] = "A thousand fish. Somewhere a lake is filing a complaint.",
		[2500] = "2,500 fish. I am no longer a hero who fishes. I am a fisher who sometimes heroes.",
	},
	skill = {
		[50] = "Fishing 50. Ready for Journeyman, says the trainer. \"Journey\" is a strong word for standing still.",
		[75] = "Fishing 75. The capitals stop laughing at me.",
		[125] = "Fishing 125. Old Man Heming in Booty Bay sells the next book. Mind the sharks. And the goblins.",
		[150] = "Fishing 150. Redridge stopped laughing at me too.",
		[225] = "Fishing 225. Nat Pagle wants four fish from four corners of the world. He could just ask nicely.",
		[300] = "Fishing 300. There's nothing left to learn. Only more fish.",
		other = "Fishing {skill}. The pole feels lighter. Or the fish got dumber. Probably the fish.",
	},
	rank = {
		[150] = "Journeyman! I can now fail at fishing in more places.",
		[225] = "Expert. The Bass and You was mostly pictures. Good pictures.",
		[300] = "Artisan. Nat Pagle shook my hand. It was damp.",
	},
	treasure = {
		"Pulled up a {item}. Somebody's luggage. Finders keepers, drowners weepers.",
		"A {item}! Locked. Of course it's locked. Everything good in this world is locked.",
	},
	junk = {
		"Caught: {item}. Not a fish. The river is mocking me again.",
		"{item}. Someone in {zone} throws trash in the water. I eat from this water.",
		"{item}. I'll tell the tavern it was a fish. A very square fish.",
	},
	escapes = "Ten fish got away in {zone}. They're writing a diary about me now.",
	-- Finds of uncommon quality or better, by rarity (2 uncommon .. 5 legendary).
	rare = {
		[2] = {
			"Huh. A {item}. Not bad. Not framing it. Yet.",
			"A {item}, uncommon. The fish didn't know what it had.",
			"Pulled up a {item}. Green means good. I checked.",
		},
		[3] = {
			"Hold my pole. A {item}. In {zone}. Out of the WATER.",
			"A {item}! I shouted. A gnome dropped his wrench.",
			"{item}. Blue. Rare. Mine. I'm telling everyone, twice.",
		},
		[4] = {
			"I'm framing this. A {item}, from {zone}. Purple. From a LAKE.",
			"{item}. My hands are shaking. So is the pole. So is the lake.",
			"A {item}. Somewhere a raid group is crying. Good.",
		},
		[5] = {
			"{item}. Legendary. From the water. I've stopped believing in nothing and started believing in everything.",
		},
	},
	-- Named rare catches, matched by name (some aren't of rare quality, they're just rare).
	named = {
		["Keefer's Angelfish"] = "Keefer's Angelfish! The Fishbot 5000 trades it for the Lucky Fishing Hat. The hat is lucky. The angelfish, less so.",
		["Brownell's Blue Striped Racer"] = "Brownell's Blue Striped Racer. Fast. Not fast enough. The Fishbot 5000 pays for it in boots.",
		["Dezian Queenfish"] = "A Dezian Queenfish. Royalty. The Fishbot 5000 will trade her for fishing line, which feels disrespectful.",
		["Rockhide Strongfish"] = "A Rockhide Strongfish. You can equip it as a mace. I have equipped it as a mace.",
	},
	bloated = "A {item}. Something rattles inside. Opening it now, in the name of science.",
	sunday = "Sunday in Stranglethorn. Forty Tastyfish or bust.",
}
