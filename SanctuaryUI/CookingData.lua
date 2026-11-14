SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.CookingData = ns.CookingData or {}
local D = ns.CookingData

-- The Cookbook's book: WoW Forever (1.60.1) cooking, in the cook's own words.
--
-- The recipe tables themselves (every dish's spell, skill, reagents, who sells or drops its
-- recipe, where each ingredient comes from) are CookingRecipes.lua, generated from the game
-- install by tools/build_cookbook_data.py. This file is everything a database can't know: what a
-- dish does in Forever, the road to 300, what to eat, the camp, the stories and the jokes. It was
-- gathered 2026-11-13 from the guides listed in tools/cooking-sources.md. Things only one doubtful
-- source claims live in TALL_TALES, not in the guide.
--
-- Dishes are keyed by their English name, as CookingRecipes.lua spells it.

---------------------------------------------------------------------------
-- What a dish does. Forever gave most old food one plain stat instead of Stamina and Spirit;
-- the guides list the old dishes by meat rather than one by one, so an old dish says its stat
-- and leaves the number to its card (hover it). kind: str, agi, sta, int, spi, ap (attack
-- power), sd (spell damage), heal, crit, armor, fishing, special, camp; text: what the page says.

D.KIND_NAME = {
	str = "Strength", agi = "Agility", sta = "Stamina", int = "Intellect", spi = "Spirit", ap = "Attack Power",
	sd = "Spell Damage", heal = "Healing", crit = "Crit", armor = "Armor", fishing = "Fishing", special = "Odd ones",
	camp = "Camp",
}

D.EFFECTS = {
	-- Boar, bear, pork, venison: Strength.
	["Roasted Boar Meat"] = { "str" }, ["Beer Basted Boar Ribs"] = { "str" }, ["Smoked Bear Meat"] = { "str" },
	["Goretusk Liver Pie"] = { "str" }, ["Dry Pork Ribs"] = { "str" }, ["Succulent Pork Ribs"] = { "str" },
	["Big Bear Steak"] = { "str" }, ["Lean Venison"] = { "str", "+5 Strength" },
	["Bear Brisket"] = { "str", "+10 Strength" }, ["Plain Ol' Paletusk"] = { "str", "+10 Strength" },
	["Savory Stag Sliders"] = { "str", "+15 Strength" }, ["Steaming Stag Steak"] = { "str", "+20 Strength" },
	["Bear Bruscitti"] = { "str", "+20 Strength" }, ["Smoked Desert Dumplings"] = { "str", "+20 Strength" },
	-- Wolf, coyote, crocolisk, cat: Agility.
	["Charred Wolf Meat"] = { "agi" }, ["Spiced Wolf Meat"] = { "agi" }, ["Coyote Steak"] = { "agi" },
	["Crocolisk Steak"] = { "agi" }, ["Seasoned Wolf Kabob"] = { "agi" }, ["Crocolisk Gumbo"] = { "agi" },
	["Hot Lion Chops"] = { "agi" }, ["Lean Wolf Steak"] = { "agi", "+5 Agility" }, ["Tasty Lion Steak"] = { "agi" },
	["Heavy Crocolisk Stew"] = { "agi" }, ["Hot Wolf Ribs"] = { "agi" }, ["Tender Wolf Steak"] = { "agi", "+15 Agility" },
	["Swiftstrike Steak"] = { "agi", "+20 Agility" }, ["Flank au Poivre"] = { "agi", "+20 Agility" },
	-- Bat, strider, crab, raptor, buzzard: Intellect.
	["Crispy Bat Wing"] = { "int" }, ["Strider Stew"] = { "int" }, ["Crab Cake"] = { "int" }, ["Cooked Crab Claw"] = { "int" },
	["Redridge Goulash"] = { "int" }, ["Roast Raptor"] = { "int" }, ["Barbecued Buzzard Wing"] = { "int" },
	["Spiced Chili Crab"] = { "int" }, ["Runn Tum Tuber Surprise"] = { "int" },
	["Tasty Raptor Bites"] = { "int", "+1 Intellect" }, ["Pincer Bites"] = { "int", "+1 Intellect" },
	["Twice-Spiced Raptor Slice"] = { "int", "+3 Intellect" }, ["Raging Raptor Ribs"] = { "int", "+10 Intellect" },
	["Raptor Rouladen"] = { "int", "+15 Intellect" }, ["Bat Hachee"] = { "int", "+20 Intellect" },
	["Prehistoric Pulled Raptor"] = { "int", "+20 Intellect" }, ["Soaring Pamplona"] = { "int", "+20 Intellect" },
	-- Eggs, spider, clam, turtle, kodo: Stamina.
	["Herb Baked Egg"] = { "sta" }, ["Kaldorei Spider Kabob"] = { "sta" }, ["Roasted Kodo Meat"] = { "sta" },
	["Boiled Clams"] = { "sta" }, ["Gooey Spider Cake"] = { "sta" }, ["Curiously Tasty Omelet"] = { "sta" },
	["Giant Clam Scorcho"] = { "sta" }, ["Soothing Turtle Bisque"] = { "sta" }, ["Heavy Kodo Stew"] = { "sta" },
	["Monster Omelet"] = { "sta" }, ["Spider Sausage"] = { "sta", "+15 Stamina" },
	["Skywall Souffle"] = { "sta", "+1 Stamina" }, ["Breakfast Omelette"] = { "sta", "+3 Stamina" },
	["Giant Scrambled Eggs"] = { "sta", "+10 Stamina" }, ["Savory Turtle Stew"] = { "sta", "+20 Stamina" },
	["Dirge's Kickin' Chimaerok Chops"] = { "sta", "+25 Stamina" },
	["Goblin Deviled Clams"] = { "sta", "+6 Stamina and Spirit, as it ever was" },
	-- Fish: attack power or spell damage, mostly.
	["Brilliant Smallfish"] = { "ap", "+6 Attack Power" }, ["Slitherskin Mackerel"] = { "ap", "+6 Attack Power" },
	["Longjaw Mud Snapper"] = { "ap" }, ["Mithril Head Trout"] = { "ap" }, ["Cooked Glossy Mightfish"] = { "ap" },
	["Poached Sunscale Salmon"] = { "ap", "+40 Attack Power" }, ["Mightfish Steak"] = { "ap", "+40 Attack Power" },
	["Rainbow Fin Albacore"] = { "sd" }, ["Smoked Sagefish"] = { "sd" }, ["Sagefish Delight"] = { "sd" },
	["Briny Seafood Stew"] = { "sd", "+14 Spell Damage" }, ["Nightfin Soup"] = { "sd", "+22 Spell Damage" },
	["Baked Salmon"] = { "sd", "+28 Spell Damage" }, ["Lobster Stew"] = { "sd" },
	["Grilled Squid"] = { "crit", "+1% crit" }, ["Hot Smoked Bass"] = { "crit", "+1% crit" },
	["Plated Armorfish"] = { "armor", "+150 Armor" },
	-- Fish that make you fish better (15 minutes).
	["Loch Frenzy Delight"] = { "fishing", "+3 Fishing" }, ["Fillet of Frenzy"] = { "fishing", "+5 Fishing" },
	["Bristle Whisker Catfish"] = { "fishing", "+8 Fishing" }, ["Rockscale Cod"] = { "fishing", "+12 Fishing" },
	["Filet of Redgill"] = { "fishing", "+18 Fishing" }, ["Spinefin Halibut"] = { "fishing", "+18 Fishing" },
	-- Teas: healing, and they refill your mana.
	["Peace Tea"] = { "heal", "+2 Healing" }, ["Royal Tea"] = { "heal", "+7 Healing" }, ["Root Tea"] = { "heal", "+11 Healing" },
	["Triage Tea"] = { "heal", "+22 Healing" }, ["Sunny Tea"] = { "heal", "+33 Healing" }, ["Sage's Tea"] = { "heal", "+44 Healing" },
	-- Smoothies: Spirit, and they refill your mana.
	["Venomous Smoothie"] = { "spi", "+1 Spirit" }, ["Slimy Smoothie"] = { "spi", "+3 Spirit" }, ["Mrrggl Smrrthle"] = { "spi", "+5 Spirit" },
	["Calcified Smoothie"] = { "spi", "+10 Spirit" }, ["Spicy Smoothie"] = { "spi", "+15 Spirit" }, ["Wicked Smoothie"] = { "spi", "+20 Spirit" },
	-- The odd ones.
	["Westfall Stew"] = { "special", "Run 15% faster, in Westfall only" },
	["Thistle Tea"] = { "special", "100 energy, now. Rogues know" },
	["Goldthorn Tea"] = { "special", "+15 Herbalism for 15 minutes" },
	["Dragonbreath Chili"] = { "special", "You breathe fire now and then for 10 minutes" },
	["Savory Deviate Delight"] = { "special", "An hour as a pirate or a ninja" },
	["Savory Whimsyfin Delight"] = { "special", "An hour as an orc pirate or an orc ninja; it holds in a fight" },
	["Sweetpaw Jam"] = { "special", "Run 15% faster, on Mount Hyjal only" },
	["Clam Linguine"] = { "special", "Health, and by one account nothing else" },
	-- Camp.
	["Basic Campfire Kit"] = { "camp", "A campfire in your bag: room for 3 camp features" },
	["Journeyman Campfire Kit"] = { "camp", "A campfire with room for 5 camp features" },
	["Expert Campfire Kit"] = { "camp", "A campfire with room for 10 camp features" },
	["Cookie's Feast"] = { "camp", "Stamina food for everyone at the camp" },
	["Iron Oven"] = { "camp", "A station at your camp: the best dishes need one" },
}

-- Dishes that need an Iron Oven at the camp (D.CAMP).
D.OVEN = {
	"Grilled Squid", "Hot Smoked Bass", "Poached Sunscale Salmon", "Baked Salmon", "Lobster Stew", "Mightfish Steak",
	"Dirge's Kickin' Chimaerok Chops", "Smoked Desert Dumplings", "Bat Hachee", "Bear Bruscitti", "Clam Linguine",
	"Flank au Poivre", "Prehistoric Pulled Raptor", "Savory Turtle Stew", "Soaring Pamplona", "Steaming Stag Steak",
	"Swiftstrike Steak", "Sweetpaw Jam",
}

-- In the client's tables, on nobody's stove: no guide has found where these are learned, and
-- they look like leftovers from another season. The Recipes chapter keeps them apart.
D.GHOSTS = {
	"Sunrise Omelette", "Prowler Steak", "Filet o' Flank", "Specklefin Feast", "Grand Lobster Banquet", "Darkclaw Bisque",
	"Smoked Redgill",
}

-- How a recipe is learned, where the tables don't say or a guide says more.
D.LEARN = {
	["Royal Tea"] = "The recipe drops from Windshear Geomancers in Stonetalon. Rarely. Very rarely.",
	["Bear Brisket"] = "The recipe drops from Ashenvale Bears, about one bear in seven hundred.",
	["Giant Scrambled Eggs"] = "The recipe drops from the Lost One Cook in the Swamp of Sorrows.",
	["Savory Whimsyfin Delight"] = "A world drop in Redridge: Great Goretusks, a Black Dragon Whelp. Not bound, so the auction house may know.",
	["Cookie's Feast"] = "Blueprint from Cookie, the murloc cook of the Deadmines.",
	["Journeyman Campfire Kit"] = "Blueprint from Lord Serpentis in the Wailing Caverns.",
	["Expert Campfire Kit"] = "Nobody has found the blueprint yet.",
	["Iron Oven"] = "Nobody is sure where the blueprint drops (see Kitchen Tales).",
	["Sweetpaw Jam"] = "Dala Fairmaw sells the recipe on Mount Hyjal.",
	["Basic Campfire Kit"] = "Any cooking trainer, or the Camping 101 quest where you started. 1 Simple Wood, with Flint and Tinder in your bag.",
	["Spinefin Halibut"] = "Trainers teach it. What goes in it, the tables don't say yet.",
	["Dirge's Kickin' Chimaerok Chops"] = "From the Scepter of the Shifting Sands chain. Dirge doesn't hand it out.",
	["Thistle Tea"] = "A rogue's recipe: a class quest reward, or Smudge Thunderwood at Ravenholdt.",
	["Gingerbread Cookie"] = "Winter Veil only: the Smokywood Pastures goblins in the capitals sell the recipe.",
	["Egg Nog"] = "Winter Veil only: the Smokywood Pastures goblins in the capitals sell the recipe.",
}

-- Recipes only some classes can learn.
D.CLASS = {
	["Thistle Tea"] = { ROGUE = true },
}

-- When Forever's new recipes turn yellow, green and grey, as the guides give it (the tables
-- only know when they can be learned). name -> { yellow, green, grey }
D.SKILLUP = {
	["Peace Tea"] = { 30, 38, 45 }, ["Royal Tea"] = { 105, 115, 125 }, ["Root Tea"] = { 155, 170, 185 },
	["Triage Tea"] = { 195, 215, 235 }, ["Sunny Tea"] = { 220, 235, 250 }, ["Sage's Tea"] = { 260, 275, 290 },
	["Venomous Smoothie"] = { 30, 38, 45 }, ["Slimy Smoothie"] = { 105, 113, 120 }, ["Mrrggl Smrrthle"] = { 135, 140, 145 },
	["Calcified Smoothie"] = { 185, 190, 195 }, ["Spicy Smoothie"] = { 215, 220, 225 }, ["Wicked Smoothie"] = { 255, 263, 270 },
	["Skywall Souffle"] = { 30, 38, 45 }, ["Tasty Raptor Bites"] = { 35, 55, 75 }, ["Pincer Bites"] = { 40, 48, 55 },
	["Breakfast Omelette"] = { 80, 88, 95 }, ["Twice-Spiced Raptor Slice"] = { 115, 133, 150 },
	["Savory Whimsyfin Delight"] = { 125, 145, 165 }, ["Bear Brisket"] = { 200, 210, 220 },
	["Giant Scrambled Eggs"] = { 195, 208, 220 }, ["Raging Raptor Ribs"] = { 280, 295, 310 },
	["Plain Ol' Paletusk"] = { 200, 215, 230 }, ["Briny Seafood Stew"] = { 220, 230, 240 },
	["Spinefin Halibut"] = { 215, 218, 220 }, ["Plated Armorfish"] = { 245, 250, 255 }, ["Raptor Rouladen"] = { 230, 238, 245 },
	["Savory Stag Sliders"] = { 230, 238, 245 }, ["Bat Hachee"] = { 280, 295, 310 }, ["Bear Bruscitti"] = { 280, 295, 310 },
	["Clam Linguine"] = { 280, 295, 310 }, ["Flank au Poivre"] = { 285, 300, 315 }, ["Prehistoric Pulled Raptor"] = { 280, 295, 310 },
	["Savory Turtle Stew"] = { 280, 295, 310 }, ["Soaring Pamplona"] = { 280, 295, 310 }, ["Steaming Stag Steak"] = { 280, 295, 310 },
	["Swiftstrike Steak"] = { 280, 295, 310 }, ["Sweetpaw Jam"] = { 280, 283, 285 },
}

---------------------------------------------------------------------------
-- Ranks: name, cap, what opens it.

D.RANKS = {
	{ "Apprentice", 75, "Any cooking trainer. No level needed." },
	{ "Journeyman", 150, "Any cooking trainer, at Cooking 50." },
	{ "Expert", 225, "The Expert Cookbook (about a gold, tradeable), readable at Cooking 125. Shandrina sells it at Mystral Lake, Ashenvale (49.6, 67.0) to the Alliance; Wulan in Shadowprey Village, Desolace (26.2, 69.8) to the Horde. The other side's copy turns up on the auction house.", item = 16072 },
	{ "Artisan", 300, "The quest Clamlette Surprise from Dirge Quikcleave in the Gadgetzan inn, Tanaris (52.6, 28.1), at Cooking 225 and level 35. Bring 12 Giant Egg, 10 Zesty Clam Meat and 20 Alterac Swiss. He is a goblin butcher with opinions about cheese; don't argue." },
}

-- The Artisan quest's shopping list.
D.CLAMLETTE = {
	{ "Giant Egg", 12, "Rocs in Tanaris." },
	{ "Zesty Clam Meat", 10, "Big-mouth Clams, off Steeljaw Snappers and Surf Gliders on Tanaris' coast." },
	{ "Alterac Swiss", 20, { { "Ben Trias in Stormwind's Trade District", "A" }, { "Innkeeper Sikewa in Shadowprey Village", "H" } } },
}

-- The road from 1 to 300: skill range, with a pole (fish), with a blade (meat), tip.
D.ROUTE = {
	{ "1-50", "Brilliant Smallfish, or Slitherskin Mackerel on a coast: about 55.", "Roasted Boar Meat or Charred Wolf Meat (you know them already), or Herb Baked Egg.", "Buy spices from a cooking supplier, never the auction house." },
	{ "50-100", "Longjaw Mud Snapper or Rainbow Fin Albacore: about 55.", "Coyote Steak or Boiled Clams, both from the trainer.", "Learn Journeyman at 50." },
	{ "100-175", "Bristle Whisker Catfish. It turns green at 160: about 90 gets you there, or switch.", "Dry Pork Ribs to 130, then Curiously Tasty Omelet or Goblin Deviled Clams.", "The Expert Cookbook can be read at 125. Buy it before you cap at 150." },
	{ "175-225", "Mithril Head Trout or Rockscale Cod: about 55.", "Roast Raptor, or Forever's Plain Ol' Paletusk (185) and Spider Sausage (200).", "Kelsey Yance in Booty Bay sells the Trout and Redgill recipes." },
	{ "225", "Clamlette Surprise.", "Clamlette Surprise.", "Level 35. Dirge, Gadgetzan. Eggs, clams, cheese." },
	{ "225-250", "Spotted Yellowtail or Filet of Redgill.", "Monster Omelet or Tender Wolf Steak.", "Gikkix at Steamwheedle Port sells Yellowtail, Nightfin Soup and Poached Sunscale Salmon." },
	{ "250-300", "Nightfin Soup, or keep cooking Yellowtail to 290 or so.", "Tender Wolf Steak and Monster Omelet to 285, Runn Tum Tuber Surprise after.", "Older guides end on Poached Sunscale Salmon or Mightfish Steak. Both need an Iron Oven now." },
}

-- Fishing and cooking together, as one trip.
D.TOGETHER = {
	"Fish your starting lake to 75 and cook everything: Smallfish, then Longjaw.",
	"Fish a capital's water to 130. The Catfish there carry Cooking past 100.",
	"Open water with Nightcrawlers to 205. Cook Catfish to 175.",
	"Dustwallow inland to 255: Mithril Head Trout to 225. Keep the leftovers.",
	"Do both Artisan quests: Nat Pagle for the pole, Dirge for the pan.",
	"Feralas to 300. Redgill and the leftover Trout to 250, then Nightfin Soup.",
}

---------------------------------------------------------------------------
-- The table: what to eat. role, dish, why.

D.TABLE = {
	{ "Tank", "Dirge's Kickin' Chimaerok Chops", "+25 Stamina." },
	{ "Tank", "Savory Turtle Stew", "+20 Stamina." },
	{ "Tank", "Plated Armorfish", "+150 Armor, and no oven." },
	{ "Strength", "Smoked Desert Dumplings", "+20 Strength." },
	{ "Strength", "Steaming Stag Steak", "+20 Strength. Bear Bruscitti does the same." },
	{ "Attack Power", "Poached Sunscale Salmon", "+40 Attack Power. Mightfish Steak does the same." },
	{ "Agility", "Swiftstrike Steak", "+20 Agility. Flank au Poivre does the same." },
	{ "Crit", "Grilled Squid", "+1% crit. Hot Smoked Bass in summer." },
	{ "Caster", "Baked Salmon", "+28 Spell Damage." },
	{ "Caster", "Nightfin Soup", "+22 Spell Damage, and no oven." },
	{ "Caster", "Prehistoric Pulled Raptor", "+20 Intellect. Soaring Pamplona and Bat Hachee too." },
	{ "Healer", "Sage's Tea", "+44 Healing." },
	{ "Healer", "Wicked Smoothie", "+20 Spirit." },
	{ "Rogue", "Thistle Tea", "100 energy when it matters." },
}

-- No oven at the camp: the best of the rest.
D.NO_OVEN = { "Tender Wolf Steak", "Savory Stag Sliders", "Raptor Rouladen", "Spider Sausage", "Sunny Tea", "Spicy Smoothie", "Nightfin Soup" }

-- What to eat on the way up: from level, to level, dishes.
D.LEVELING = {
	{ 1, 4, { "Roasted Boar Meat", "Spiced Wolf Meat", "Herb Baked Egg", "Crispy Bat Wing", "Brilliant Smallfish", "Slitherskin Mackerel", "Peace Tea", "Venomous Smoothie" } },
	{ 5, 14, { "Breakfast Omelette", "Twice-Spiced Raptor Slice", "Royal Tea", "Slimy Smoothie", "Westfall Stew" } },
	{ 15, 24, { "Lean Venison", "Lean Wolf Steak", "Roast Raptor", "Bristle Whisker Catfish", "Root Tea", "Mrrggl Smrrthle" } },
	{ 25, 34, { "Bear Brisket", "Plain Ol' Paletusk", "Giant Scrambled Eggs", "Raging Raptor Ribs", "Briny Seafood Stew", "Triage Tea", "Calcified Smoothie" } },
	{ 35, 44, { "Savory Stag Sliders", "Tender Wolf Steak", "Raptor Rouladen", "Spider Sausage", "Nightfin Soup", "Grilled Squid", "Sunny Tea", "Spicy Smoothie" } },
	{ 45, 60, { "Steaming Stag Steak", "Swiftstrike Steak", "Savory Turtle Stew", "Prehistoric Pulled Raptor", "Mightfish Steak", "Baked Salmon", "Sage's Tea", "Wicked Smoothie" } },
}

-- How eating works in Forever.
D.WELL_FED = {
	"Sit and eat for ten seconds and you're Well Fed for fifteen minutes.",
	"Forever's new dishes also give 5% more experience from kills while Well Fed. Guides disagree on whether the old dishes do.",
	"Most old food gives one plain stat now, by the meat: boar and bear for Strength, wolf and cat for Agility, raptor and crab for Intellect, eggs and spiders for Stamina.",
	"Teas (Healing) and smoothies (Spirit) refill your mana as they go down.",
	"Raw meat stacks to 20 now, some of it to 45. Twelve old recipes bind when picked up, so buy the meat, not the dish's recipe, on the auction house.",
}

---------------------------------------------------------------------------
-- Camp. name, skill to learn, what it's for; reagents and blueprints come from the tables
-- and D.LEARN.

D.CAMP = { "Basic Campfire Kit", "Journeyman Campfire Kit", "Expert Campfire Kit", "Cookie's Feast", "Iron Oven" }

D.CAMP_RULES = {
	"A campfire is a cooking fire. Somebody puts one down; everyone near it may add one camp feature from their own trade.",
	"Sit by the fire for about a minute for the camp's benefits, for an hour.",
	"Your camp features share one 1-hour cooldown. Kits are bag items: craft a few and carry them.",
	"An Iron Oven at a camp serves everyone at that fire. Nobody has found one standing in the wild.",
	"The first camp recipes come from trainers or Camping 101; the rest from Blueprints, which can be traded.",
}

-- Legacy talents. name, text
D.TALENTS = {
	{ "Master Chef", "Professions tree: 10% a rank (five ranks) to cook an extra portion. At 50%, half your fish feed two." },
	{ "Gourmand", "Resourcefulness tree: food buffs last a third longer per rank. Three ranks turn 15 minutes into 30." },
	{ "Working Overtime", "Professions tree: 4% a rank more skill-ups from every trade skill, cooking included." },
	{ "Dedicated Study", "Professions tree: +1 to your lowest trade skill, once a day or so (23 h cooldown)." },
	{ "Performance Bonus", "Professions tree: a chance of double Merchant's Favor from crate turn-ins. Favor buys the smoothie recipes." },
	{ "Field Guide", "Adventure tree: your camp features come off cooldown sooner." },
}

-- Merchant's Favor: the smoothies' price.
D.FAVOR = "Smoothie recipes cost Merchant's Favor, earned by handing filled supply crates in at trade camps. Kalsey Sanden at Three Corners, Redridge sells them to the Alliance; Aza'bek at the Crossroads to the Horde. The later ones want standing with their trading company too."

-- Cooking quests the tables don't hold. name, giver, place, reward, side
D.QUESTS = {
	{ "Clamlette Surprise", "Dirge Quikcleave", "Gadgetzan, Tanaris", "Artisan Cooking (level 35, Cooking 225)." },
	{ "I Know A Guy...", "Daryl Riknussun", "Ironforge", "Sends you to Dirge. Optional.", side = "A" },
	{ "To Gadgetzan You Go!", "Zamja", "Orgrimmar", "Sends you to Dirge. Optional.", side = "H" },
	{ "Camping 101: Cooking", "the cook where you started", "every starting zone", "Your first campfire." },
}

---------------------------------------------------------------------------
-- Ingredients the tables can't place, and a word on the ones they can. item name -> note.

D.PANTRY = {
	["Zesty Clam Meat"] = "Big-mouth Clams, from Steeljaw Snappers and Surf Gliders on Tanaris' coast.",
	["Tangy Clam Meat"] = "Thick-shelled Clams, from the murlocs and sea creatures of Stranglethorn, Arathi and Dustwallow.",
	["Clam Meat"] = "Small Barnacled Clams, off almost anything that lives by the sea at low level.",
	["Giant Clam Meat"] = "Giant Clams on Stranglethorn's sea floor, and the snappers near them.",
	["Hyjal Berries"] = "Mount Hyjal. Ask the bears. From a distance.",
	["Holy Salts"] = "Nobody has found any. Possibly holy. Possibly not real.",
	["Exquisite Spices"] = "Nobody has found any.",
	["Deviate Fish"] = "Fished from the Barrens' oases and the Wailing Caverns.",
	["Whimsyfin"] = "Fished from Whimsyfin pools in Redridge's rivers, east of Lake Everstill.",
	["Plated Armorfish"] = "Fished from high coasts: Azshara, Feralas.",
	["Runn Tum Tuber"] = "Dug up in Dire Maul. The ogres don't share.",
	["Swiftthistle"] = "Found in Mageroyal and Briarthorn by herbalists, now and then.",
	["Goldthorn"] = "An herb: Arathi, Stranglethorn, the Badlands.",
	["Peacebloom"] = "An herb, in every starting zone. Pick it, or ask an herbalist.",
	["Mageroyal"] = "An herb: the Barrens, Westfall, Loch Modan, Darkshore, Silverpine.",
	["Liferoot"] = "An herb, by water: Wetlands, Hillsbrad, Stranglethorn.",
	["Fadeleaf"] = "An herb: Stranglethorn, Swamp of Sorrows, Arathi.",
	["Sungrass"] = "An herb: Felwood, Feralas, the Hinterlands, the Plaguelands.",
	["Mountain Silversage"] = "An herb, up high: Winterspring, Un'Goro, the Plaguelands.",
	["Wicked Claw"] = "Owlbeasts, bears and their like in the Hinterlands, Felwood and Winterspring.",
	["Stormwind Seasoning Herbs"] = "Felicia Gump sells them by the Stormwind canals.",
	["Mild Spices"] = "Cooking suppliers and trade vendors, for copper.",
	["Hot Spices"] = "Cooking suppliers and trade vendors.",
	["Soothing Spices"] = "Cooking suppliers and trade vendors.",
	["Simple Flour"] = "Cooking suppliers and bakers.",
}

D.KINDS_OF_SOURCE = {
	fish = "Fished. The Angler's journal knows where.",
	shop = "Innkeepers and trade vendors, nearly everywhere.",
	object = "Gathered: an herb, a clam, a crate.",
}

---------------------------------------------------------------------------
-- What the Cookbook says about the other faction's things.

D.ENEMY = {
	A = { "Alliance only. Dwarves guard recipes like ale.", "Alliance only. Try looking hungry in Stormwind.", "Alliance only. A gnome wrote it down. Very small handwriting." },
	H = { "Horde only. Orcs don't write recipes down. They shout them.", "Horde only. The tauren would share. The guards wouldn't.", "Horde only. A Forsaken cook has it. Don't ask what else he cooks." },
}

---------------------------------------------------------------------------
-- Tall tales: claims from a single source we couldn't confirm. Kept apart, for the honest.

D.TALL_TALES = {
	{ "The Iron Oven's blueprint", "One guide says Quartermaster Zigris in Lower Blackrock Spire drops it. Three others say nobody knows. Zigris isn't taking questions." },
	{ "The Happy Camper", "A vendor outside Ironforge and Orgrimmar selling camp blueprints for silver, Cookie's Feast and the Journeyman Campfire among them. The wiki says test realms only. One site swears it's live." },
	{ "Sunrise Omelette, Prowler Steak, Filet o' Flank", "In the client's tables, needing Holy Salts nobody can find. They read like leftovers from another season. One boosting site lists them as the best food in the game. It also sells boosts." },
	{ "The feasts", "Specklefin Feast and Grand Lobster Banquet: twelve fish each, food for forty. Listed, never seen cooked." },
	{ "Cookie's Stirring Rod", "Said to make you cook a quarter faster while you hold it. Said once." },
	{ "Root Tea", "One list says the recipe drops from Torn Fin Oracles in Hillsbrad. Another says a trainer teaches it. The murlocs aren't saying." },
	{ "Raptor Rouladen", "One list has the recipe dropping from Bloodfen Lashtails in Dustwallow." },
	{ "A Taste of the Sea", "A quest said to teach Briny Seafood Stew. Nobody names who gives it." },
	{ "The trainers' secret menu", "One site says trainers teach the last three teas and all ten oven dishes. No other guide agrees, and no trainer has admitted it." },
	{ "Seasonal Fish Steaks", "One guide says the Chef's Knife (Fishing 275) cuts Winter Squid or Summer Bass into steaks for the Fishing Hut. No recipe in this book uses them." },
	{ "Experience from old food", "Some say every cooked dish gives the 5% kill experience, some say only the new ones. Eat and watch your bar." },
	{ "Critter Cookie, Cleansing Stew", "Names seen in recipe lists with no effect, no source and no cook who'll own up to them." },
}

-- Old stories, as the diary tells them in Kitchen Tales: heard over somebody's stew.
D.LEGENDS = {
	{
		title = "Cookie",
		text = "The Defias kept a murloc as ship's cook in the Deadmines. He hits intruders with a rolling pin and his stew heals him when he's losing, which is more than I can say for mine. His feast recipe went missing when he did.",
	},
	{
		title = "Dirge's chops",
		text = "Dirge Quikcleave of Gadgetzan cooks one dish he won't sell: chimaerok tenderloin, Deeprock Salt and a measure of Goblin Rocket Fuel. People have crossed a continent and fought a dragon's brood for the recipe. The rocket fuel is for flavour, he says.",
	},
	{
		title = "Mystery Meat",
		text = "Asked a butcher in Booty Bay what Mystery Meat is. He said it comes from many animals. I asked which. He said that's the mystery, and went back to sharpening something.",
	},
	{
		title = "Naralex's kitchen",
		text = "The Deviate Fish in the Barrens come from a druid's bad dreams. Season one mildly and you spend an hour as a pirate or a ninja. A cook in Ratchet says that makes it the only dish that's also a career change.",
	},
}

---------------------------------------------------------------------------
-- The diary: chapter openers (in the cook's hand) and the lines the Cookbook writes itself.

D.OPENERS = {
	larder = { "What's in the bags, what it could be, and whether it's still moving. Let's look." },
	route = { "Cooking is setting things on fire on purpose. I have experience. Here's how it becomes a trade." },
	recipes = { "Every dish I know of, in the order the trainer said I'd be ready. The trainer was optimistic." },
	catch = { "The angler in me catches it. The cook in me asks what took so long." },
	table = { "You are what you eat. Today I am forty attack power and a little fishy." },
	pantry = { "Every stew starts with something that didn't want to be in it. Here's where they all live." },
	camp = { "A campfire, a pan, a kodo steak. Sanctuary never had it this good. Sanctuary mostly had corpses." },
	tales = { "Stories heard over other people's cooking. I was chewing for some of them." },
}

-- The diary's own story: the first line of your first, second and third days at the stove.
D.STORY = {
	{ "The trainer gave me a pan and said, \"Anyone can cook.\" I've closed the gates of Hell. How hard can an egg be?" },
	{ "The egg won." },
	{ A = "A dwarf tried my stew and said it needed ale. He says that about everything. He was right.",
		H = "An orc tried my stew and called it \"food.\" I'm told that's high praise. He ate the bowl too." },
}

-- Auto entries. {dish}, {item}, {zone}, {n}, {skill} are filled in.
D.LINES = {
	first = { "First thing I ever cooked: {dish}. Nobody died. Putting that on the sign." },
	dish = {
		"Cooked {dish} for the first time. It looks like the picture, if the picture was drawn in the dark.",
		"{dish}. New to me. The smoke was a surprise to everyone.",
		"First {dish}. A guard asked what the smell was. I said dinner. He said he hoped not.",
		"{dish}! Fresh meat! Sorry. Old habit. Different butcher.",
		"Made {dish}. Tasted it. Stayed awhile. Listened to my stomach. It had notes.",
		"{dish}, first try. Edible. I've set the bar where I can reach it.",
		"New dish: {dish}. The recipe said \"to taste.\" Whose? It didn't say.",
		"{dish}. I followed the recipe exactly, except the parts I didn't.",
		"First {dish}. It's supposed to be that colour. I've decided.",
		"{dish}. The fire did most of the work. I'm taking the credit.",
		"Cooked {dish}. A cat appeared from nowhere. Cats know.",
		"{dish}. Not burnt. Caramelised. There's a difference and it's my word against the pan's.",
		"First {dish}. I've fought things made of fire. Never fed one before.",
		"{dish}. The trainer said it would be easy. The trainer says a lot of things, with both eyebrows.",
		"A {dish}. I made it. From parts. Like the Butcher, but with seasoning.",
		"{dish}, {zone}. The locals gathered. Some to eat. Some to watch.",
		"New recipe, new dish: {dish}. New stain, too.",
		"{dish}. It bubbled in a way I didn't like, then in a way I did.",
		"First {dish}. I gave some to a dog. The dog is fine. Dogs are always fine.",
		"{dish}. Smells like victory. Victory smells a bit like onions.",
		"Made {dish}. Ate {dish}. A short story with a happy ending.",
		"{dish}. I'd share, but I'm not going to.",
		"{dish}, first batch. The second will be better. The second is always better. Nobody tells you about the first.",
		"Cooked {dish} in {zone}. Something in the bushes came closer. I ate faster.",
		"{dish}. Three ingredients. I counted four in the pan. Not asking.",
		"First {dish}. My armour smells of it now. So will the next dungeon.",
		"{dish}. The hard part was not eating the ingredients first.",
		"A {dish}. I was told to let it rest. It's resting. I'm watching it rest.",
		"{dish}. Somewhere an innkeeper felt a chill and raised his prices.",
		"New on the menu: {dish}. The menu is me, shouting what I've got.",
		"{dish}. It didn't stick to the pan. The pan and I are both surprised.",
		"First {dish}. I salted it over my shoulder for luck. Hit a gnome. Sorry, gnome.",
		"{dish}. Deckard would have had a story about it. A long one. It'd have gone cold.",
		"Cooked {dish}. Well Fed, it says. Well. Fed, anyway.",
		"{dish}. Looks wrong. Tastes right. I've had friends like that.",
		"{dish}. I'm no chef. But for a moment there, over the fire, neither was anyone else.",
	},
	fish = {
		"{dish}. Caught it this morning, cooked it tonight. It never saw either coming.",
		"First {dish}. The fish and I have come a long way together. Further for the fish.",
		"{dish}. From the water to the fire. A varied life, briefly.",
		"Cooked {dish}. The angler in me is proud. The fish abstains.",
		"{dish}. It looked at me the whole time. I should have started with the head.",
		"New fish dish: {dish}. The bag smells better already. Slightly.",
		"{dish}. Scaled it with a dagger that has killed demons. The dagger feels this is beneath it.",
		"First {dish}. Bones: several. Regrets: none.",
		"{dish}. A murloc watched me cook it. We both know what he was thinking.",
		"{dish}. Fresh from {zone}. Well. From my bag. It's been in there a while.",
		"Cooked {dish}. Nat Pagle says he never cooks his. Nat Pagle doesn't look well.",
		"{dish}. The cat from earlier is back. It brought friends.",
	},
	learned = {
		"Learned to make {dish}. The recipe is mostly stains. I'll work around them.",
		"New recipe: {dish}. I read it twice. Then right way up.",
		"{dish}, now in the book. The book is getting heavy. So am I.",
		"Learned {dish}. The cook who taught me winced the whole time. Encouraging.",
		"New recipe: {dish}. One more thing I can ruin with confidence.",
		"I know how to make {dish} now. Knowing and doing are neighbours. They don't always talk.",
		"{dish}: learned. Whoever wrote this recipe had lovely handwriting and no sense of quantities.",
		"Picked up {dish}. Another page. Another reason to go and bother wildlife.",
		"Learned {dish}. \"A pinch,\" it says. I have gauntlets. My pinch is a handful.",
		"New recipe: {dish}. The last cook to make it retired. Nobody says why.",
		"{dish} is mine to cook. Azeroth has been warned.",
		"Learned {dish}. The ingredients list reads like a hunting licence.",
		"New in the book: {dish}. I'd say I can't wait. I can. I have to find the meat first.",
		"{dish}. Learned it in a minute. I'll be getting it wrong for weeks.",
	},
	special = {
		["Savory Deviate Delight"] = "Savory Deviate Delight. Ate one. I'm a pirate now. The stew is unsupervised.",
		["Savory Whimsyfin Delight"] = "Savory Whimsyfin Delight. An hour as an orc ninja. The pan has never been so well guarded.",
		["Dragonbreath Chili"] = "Dragonbreath Chili. I breathed fire on a guard by accident. Then again, less by accident.",
		["Goblin Deviled Clams"] = "Goblin Deviled Clams. The goblin said the recipe was free. Then charged me for the clams. And the plate.",
		["Westfall Stew"] = "Westfall Stew. Vulture, murloc eye, boar snout. The farmers say it's all they had. I believe them.",
		["Mystery Stew"] = "Mystery Stew. Mystery Meat and dwarven stout. The mystery is why it's good.",
		["Carrion Surprise"] = "Carrion Surprise. The surprise is the carrion. They put it in the name and it still got me.",
		["Thistle Tea"] = "Thistle Tea. Drank it. Could not stand still. Stabbed several things for no reason.",
		["Dig Rat Stew"] = "Dig Rat Stew. It's rat. It's stew. I respect a dish that doesn't pretend.",
		["Monster Omelet"] = "Monster Omelet. One egg. It needed two of us to turn it.",
		["Dirge's Kickin' Chimaerok Chops"] = "Dirge's Kickin' Chimaerok Chops. Rocket fuel in the marinade. My eyebrows will grow back.",
		["Cookie's Feast"] = "Laid out Cookie's Feast. A murloc's recipe. Everyone ate. Nobody asked what was in it. Wise.",
		["Iron Oven"] = "Built an Iron Oven. Ten sacks of flour and it's made of iron. I don't understand ovens.",
		["Mrrggl Smrrthle"] = "Mrrggl Smrrthle. I can't say it. I can make it. The murlocs can do neither, which seems unfair.",
		["Roasted Boar Meat"] = "Roasted Boar Meat. Boar, fire, done. The first recipe anyone ever had.",
		["Herb Baked Egg"] = "Herb Baked Egg. One egg, some herbs. I won this time.",
	},
	total = {
		[10] = "Ten dishes cooked. My hands smell of spices and something else. Mostly something else.",
		[50] = "Fifty dishes. Dogs follow me through town. Guards too, for different reasons.",
		[100] = "A hundred dishes. I dream about onions. There are no onions in this world. That's the dream.",
		[250] = "Two hundred and fifty dishes. Innkeepers have stopped waving.",
		[500] = "Five hundred. I can tell meat by sound now. Don't ask what sound.",
		[1000] = "A thousand dishes. Somewhere a boar tells its children about me.",
		[2500] = "2,500 dishes. I am no longer a hero who cooks. I'm a cook the world keeps interrupting.",
	},
	skill = {
		[50] = "Cooking 50. Journeyman, says the trainer. The journey so far: from raw to slightly less raw.",
		[75] = "Cooking 75. I can burn things in three different ways now, all on purpose.",
		[125] = "Cooking 125. Time for the Expert Cookbook. A book. About cooking. Imagine.",
		[150] = "Cooking 150. Half way. The half with fewer boars in it is ahead, I'm told.",
		[225] = "Cooking 225. A goblin in Gadgetzan wants eggs, clams and cheese. I've had stranger quests. Not many.",
		[300] = "Cooking 300. Nothing left to learn but restraint.",
		other = "Cooking {skill}. The pan feels lighter. Or my arm got used to it. Probably the arm.",
	},
	rank = {
		[150] = "Journeyman cook! I can now disappoint at a professional level.",
		[225] = "Expert. The Cookbook was mostly gravy stains. Good stains. I learned a lot from them.",
		[300] = "Artisan. Dirge shook my hand, then counted his fingers. Goblins.",
	},
	grey = {
		"Cooked {dish}. Learned nothing. Ate well. Some days that's the whole lesson.",
		"{dish} again. My hands did it without me. I was thinking about fish.",
		"{dish}. I could make this asleep. I may have.",
		"More {dish}. The skill doesn't move. The stomach does.",
		"{dish}, for the eating, not the learning.",
		"{dish}. Nothing left to learn from it. It still has things to teach my belt.",
	},
	oven = "Cooked {dish} in an Iron Oven. Everything else I've made was practice.",
	batch = "Cooked {n} dishes today. The fire is tired. I'm tired. The bags are full of lunch.",
}
