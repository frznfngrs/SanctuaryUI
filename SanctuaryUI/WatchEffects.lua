SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI

-- The buffs Watch.lua follows and how GlobeAura.lua shows each. Read by both; nothing here runs.
--
-- Fields:
--   key, label, desc  name in the options and /sanctuary aura; desc says what you see
--   class             whose it is (options and test mode group by it); "ANY" for everyone
--   spells, names     rank 1 IDs, read back as names so every rank and locale matches, and the
--                     English names for a client that can't name an ID
--   look              radiate: light behind the globe. shell: a crystal shield over the glass.
--                     surge: light drawn into the globe. flare: a one-off burst (no state)
--   globe             health, mana (only while a globe holds mana) or power (the resource
--                     globe, whatever it holds)
--   tint              GlobeAura.lua's colour
--   length            seconds, if neither a reading nor the spell's text has said
--   group             one of a group at a time: casting any member ends the others
--   target            "any" for spells you can cast on others: they only light when they
--                     land on you (the cast's target is you, or a buff icon appears with it)
--   kind              buff (default), channel (up while you channel it) or reading (only
--                     ever seen in readings: eating and drinking, out of combat anyway)
--   absorb            a damage shield: shown only while the game says you hold an absorb,
--                     so it goes the moment it breaks
--   fragile           spends charges: ends when a buff icon goes with a hit and nothing
--                     else explains it
--   charges           a fragile buff's charges: physical hits count them down, and once they're
--                     gone any buff icon going ends it
--   strength          how bright, against the others (1 if not set): raised where a colour sits
--                     close to its globe's or the look is quiet by nature
--   long              a buff kept up for minutes (Inner Fire, Lightning Shield): after lighting
--                     it settles to a quiet glow, so it doesn't burn all session
--   storm             radiance only: lightning too (static and arcs on the rim, bolts striking out)
--   surge             with look = "surge", how the power enters by default: "pour" (a column of
--                     light falling into the liquid, for filling up over time), "inhale" (streaks
--                     rushing in to the glass, for a short violent surge), "upwell" (plumes rising
--                     through the liquid, for quiet healing), or "swirl", "fury" (rage: the liquid
--                     whipped into a whirlpool, and on the health globe the gargoyle wakes), or a healing look: "vines",
--                     "halo", "bloom", "veil", "rain", "pulse" or "embers". Players can change any
--                     skill in the options (GlobeAura.lua LookOf)
--   tally             with look = "radiate", shows as Slashes by default: that many claw slashes
--                     (4 at most) burnt into the globe's glass over a low Radiance, one burning
--                     off with each swing of yours that lands (Reckless.lua). Players can set any
--                     buff to Slashes; one that says nothing here gets four
--   flare             a burst played at the cast (and, for look = "flare", all it does):
--                     a list of { globe, tint, dir = "out" | "in" }
--   shell             with look = "shell", what it shows by default: "aegis" (runed gold plates round the
--                     rim), "rime" (frost grown in from the rim), "hex" (a lattice on the sphere) or
--                     "bulwark" (iron plates round the rim). Unset: the Crystal shell
--   shellBreak        how a shield that can break does: "shockwave", "dissolve", "crumble" or "melt".
--                     Unset: "shatter". Players can change either (GlobeAura.lua LookOf, BreakOf)
--   heal              with look = "flare", how its "in" parts play by default: "mend" (a dome of
--                     light off the surface), "benediction" (a beam striking the surface) or
--                     "mound" (shown as Surge: the liquid heaves up). Unset: "burst", the ring and
--                     flash. Players can change any flare skill in the options
--   hot               healing over time: follows the options' shared colour and brightness
--   tick              healing over time: seconds between ticks, for the Pulse look. Unknown on a
--                     buff you didn't cast (or with no tick here): Pulse shows a plain cadence
--
-- Within one look on one globe the first listed wins, so the strongest effects come first.

ns.WatchData = {}

ns.WatchData.EFFECTS = {
	-- Shells: invulnerability first, then the big walls, then absorbs.
	{ key = "divineShield", class = "PALADIN", spells = { 642 }, names = { "Divine Shield" }, look = "shell", globe = "health", tint = "holyShield", length = 10, strength = 1.3, shell = "aegis", shellBreak = "dissolve",
		label = "Divine Shield", desc = "a band of runed gold plates turning round the health globe's rim" },
	{ key = "iceBlock", class = "MAGE", spells = { 11958 }, names = { "Ice Block" }, look = "shell", globe = "health", tint = "frost", length = 10, strength = 1.3, shell = "rime", shellBreak = "melt",
		label = "Ice Block", desc = "frost growing in from the health globe's rim" },
	{ key = "divineProtection", class = "PALADIN", spells = { 498 }, names = { "Divine Protection" }, look = "shell", globe = "health", tint = "holyShield", length = 6, strength = 1.3, shell = "aegis", shellBreak = "dissolve",
		label = "Divine Protection", desc = "a band of runed gold plates turning round the health globe's rim" },
	{ key = "blessingOfProtection", class = "PALADIN", spells = { 1022 }, names = { "Blessing of Protection" }, look = "shell", globe = "health", tint = "holyShield", length = 6, strength = 1.5, target = "any", shell = "aegis", shellBreak = "dissolve",
		label = "Blessing of Protection", desc = "a band of runed gold plates turning round the health globe's rim, when it is on you" },
	{ key = "shieldWall", class = "WARRIOR", spells = { 871 }, names = { "Shield Wall" }, look = "shell", globe = "health", tint = "steel", length = 10, strength = 1.7, shell = "bulwark", shellBreak = "crumble",
		label = "Shield Wall", desc = "overlapping steel plates round the health globe's rim" },
	{ key = "evasion", class = "ROGUE", spells = { 5277 }, names = { "Evasion" }, look = "shell", globe = "health", tint = "smoke", length = 15, strength = 1.6,
		label = "Evasion", desc = "a smoke-grey shell over the health globe" },
	{ key = "barkskin", class = "DRUID", spells = { 22812 }, names = { "Barkskin" }, look = "shell", globe = "health", tint = "bark", length = 15, strength = 1.5,
		label = "Barkskin", desc = "a bark-brown shell over the health globe" },
	{ key = "powerWordShield", class = "PRIEST", spells = { 17 }, names = { "Power Word: Shield" }, look = "shell", globe = "health", tint = "holyShield", length = 30, target = "any", absorb = true, shell = "aegis", shellBreak = "dissolve",
		label = "Power Word: Shield", desc = "a band of runed gold plates round the health globe that burns away when the shield breaks" },
	{ key = "iceBarrier", class = "MAGE", spells = { 11426 }, names = { "Ice Barrier" }, look = "shell", globe = "health", tint = "frost", length = 60, absorb = true, shell = "rime", shellBreak = "melt",
		label = "Ice Barrier", desc = "frost growing in from the health globe's rim that slumps and melts off when it breaks" },
	{ key = "shadowWard", class = "WARLOCK", spells = { 6229 }, names = { "Shadow Ward" }, look = "shell", globe = "health", tint = "shadow", length = 30, absorb = true, shell = "hex", shellBreak = "shockwave",
		label = "Shadow Ward", desc = "a violet hex lattice over the health globe that blows out in a shockwave when it breaks" },
	{ key = "fireWard", class = "MAGE", spells = { 543 }, names = { "Fire Ward" }, look = "shell", globe = "health", tint = "fire", length = 30, absorb = true, shell = "hex", shellBreak = "shockwave",
		label = "Fire Ward", desc = "a fiery hex lattice over the health globe that blows out in a shockwave when it breaks" },
	{ key = "frostWard", class = "MAGE", spells = { 6143 }, names = { "Frost Ward" }, look = "shell", globe = "health", tint = "frost", length = 30, absorb = true, shell = "rime", shellBreak = "melt",
		label = "Frost Ward", desc = "frost growing in from the health globe's rim that slumps and melts off when it breaks" },
	{ key = "manaShield", class = "MAGE", spells = { 1463 }, names = { "Mana Shield" }, look = "shell", globe = "mana", tint = "arcaneViolet", length = 60, absorb = true, shell = "hex", shellBreak = "shockwave",
		label = "Mana Shield", desc = "an arcane hex lattice over the mana globe that blows out in a shockwave when it breaks" },

	-- Radiance.
	{ key = "sealOfLight", class = "PALADIN", spells = { 20165 }, names = { "Seal of Light" }, look = "radiate", group = "seal", globe = "health", tint = "holy", length = 30,
		label = "Seal of Light", desc = "gold light radiates from behind the health globe" },
	{ key = "sealOfWisdom", class = "PALADIN", spells = { 20166 }, names = { "Seal of Wisdom" }, look = "radiate", group = "seal", globe = "mana", tint = "arcane", length = 30,
		label = "Seal of Wisdom", desc = "blue light radiates from behind the mana globe" },
	{ key = "lastStand", class = "WARRIOR", spells = { 12975, 12976 }, names = { "Last Stand" }, look = "radiate", globe = "health", tint = "blood", length = 20, strength = 1.3,
		label = "Last Stand", desc = "crimson light radiates from behind the health globe" },
	{ key = "deathWish", class = "WARRIOR", spells = { 12292 }, names = { "Death Wish" }, look = "radiate", globe = "power", tint = "blood", length = 30, strength = 1.3,
		label = "Death Wish", desc = "crimson light radiates from behind the rage globe" },
	{ key = "recklessness", class = "WARRIOR", spells = { 1719 }, names = { "Recklessness" }, look = "radiate", globe = "power", tint = "rage", length = 15, strength = 1.6,
		label = "Recklessness", desc = "fiery light radiates from behind the rage globe" },
	{ key = "berserkerRage", class = "WARRIOR", spells = { 18499 }, names = { "Berserker Rage" }, look = "surge", surge = "fury", globe = "health", tint = "rage", length = 10, strength = 1.4,
		label = "Berserker Rage", desc = "the health globe churns violently round a whirlpool and the gargoyle wakes: heat beats over it, its horns turn deep red and it breathes fire" },
	{ key = "adrenalineRush", class = "ROGUE", spells = { 13750 }, names = { "Adrenaline Rush" }, look = "radiate", globe = "power", tint = "energy", length = 15,
		label = "Adrenaline Rush", desc = "gold light radiates from behind the energy globe" },
	{ key = "bladeFlurry", class = "ROGUE", spells = { 13877 }, names = { "Blade Flurry" }, look = "radiate", globe = "power", tint = "steel", length = 15, strength = 1.4,
		label = "Blade Flurry", desc = "steel light radiates from behind the energy globe" },
	{ key = "tigersFury", class = "DRUID", spells = { 5217 }, names = { "Tiger's Fury" }, look = "radiate", globe = "power", tint = "energy", length = 6, strength = 1.2,
		label = "Tiger's Fury", desc = "gold light radiates from behind the energy globe" },
	{ key = "arcanePower", class = "MAGE", spells = { 12042 }, names = { "Arcane Power" }, look = "radiate", globe = "mana", tint = "arcaneViolet", length = 15,
		label = "Arcane Power", desc = "arcane light radiates from behind the mana globe" },
	{ key = "rapidFire", class = "HUNTER", spells = { 3045 }, names = { "Rapid Fire" }, look = "radiate", globe = "power", tint = "amber", length = 15, strength = 1.2,
		label = "Rapid Fire", desc = "amber light radiates from behind the resource globe" },
	{ key = "innerFire", class = "PRIEST", spells = { 588 }, names = { "Inner Fire" }, look = "radiate", globe = "health", tint = "holy", length = 600, fragile = true, long = true,
		label = "Inner Fire", desc = "gold light radiates from behind the health globe until its charges are spent (off at first: a 10-minute buff)" },
	{ key = "lightningShield", class = "SHAMAN", spells = { 324 }, names = { "Lightning Shield" }, look = "radiate", globe = "health", tint = "storm", length = 600, fragile = true, charges = 3, storm = true, long = true,
		label = "Lightning Shield", desc = "crackling blue light radiates from behind the health globe until its charges are spent" },

	-- Surges.
	{ key = "evocation", class = "MAGE", spells = { 12051 }, names = { "Evocation" }, look = "surge", surge = "pour", globe = "mana", tint = "arcane", length = 8, kind = "channel",
		label = "Evocation", desc = "a column of light pouring from the ring into the mana globe while you channel" },
	{ key = "innervate", class = "DRUID", spells = { 29166 }, names = { "Innervate" }, look = "surge", surge = "inhale", globe = "mana", tint = "innervate", length = 20, target = "any",
		label = "Innervate", desc = "streaks of light rushing in to the mana globe, when it is on you" },
	{ key = "manaTide", class = "SHAMAN", spells = { 16190 }, names = { "Mana Tide Totem" }, look = "surge", surge = "rain", globe = "mana", tint = "water", length = 12, tick = 3,
		noAura = true, -- the totem pulses mana and puts no buff on you: its timer ends it
		label = "Mana Tide Totem", desc = "drops fall through the glass and ripple on the mana globe's surface" },
	{ key = "bloodrage", class = "WARRIOR", spells = { 2687 }, names = { "Bloodrage" }, look = "surge", surge = "inhale", globe = "health", tint = "blood", length = 10, strength = 1.2,
		flare = { { globe = "power", tint = "rage", dir = "in" } },
		label = "Bloodrage", desc = "streaks of blood rushing in to the health globe it costs, and the rage globe draws the rage in" },
	-- Slashes: the cast's flares and a low glow from GlobeAura.lua, the tally from Reckless.lua.
	{ key = "recklessSwings", class = "WARRIOR", names = { "Reckless Swings" }, look = "radiate", tally = 4, globe = "power", tint = "rage", length = 8, strength = 0.8,
		flare = { { globe = "health", tint = "blood", dir = "out" }, { globe = "power", tint = "rage", dir = "in" } },
		label = "Reckless Swings", desc = "blood bursts from the health globe it costs; four ember claw slashes burn into the rage globe, and each swing that lands burns one off as its rage comes in" },
	{ key = "frenziedRegeneration", class = "DRUID", spells = { 22842 }, names = { "Frenzied Regeneration" }, look = "surge", surge = "veil", hot = true, globe = "health", tint = "nature", length = 10, tick = 1,
		label = "Frenzied Regeneration", desc = "curtains of green light rising off the top of the health globe" },
	{ key = "renew", class = "PRIEST", spells = { 139 }, names = { "Renew" }, look = "surge", surge = "halo", hot = true, globe = "health", tint = "holy", length = 15, tick = 3, target = "any",
		label = "Renew", desc = "a halo of gold light over the health globe, when it is on you" },
	{ key = "rejuvenation", class = "DRUID", spells = { 774 }, names = { "Rejuvenation" }, look = "surge", surge = "bloom", hot = true, globe = "health", tint = "nature", length = 12, tick = 3, target = "any",
		label = "Rejuvenation", desc = "glowing leaves drift up off the health globe, when it is on you" },
	{ key = "regrowth", class = "DRUID", spells = { 8936 }, names = { "Regrowth" }, look = "surge", surge = "vines", hot = true, globe = "health", tint = "nature", length = 21, tick = 3, target = "any",
		flare = { { globe = "health", tint = "nature", dir = "in" } },
		label = "Regrowth", desc = "vines climb the health globe's glass while it runs, when it is on you" },
	{ key = "food", class = "ANY", names = { "Food", "Food & Drink", "Refreshment" }, spells = {}, look = "surge", surge = "pour", globe = "health", tint = "hearth", length = 30, kind = "reading",
		label = "Eating", desc = "a column of warm light pouring into the health globe while you eat" },
	{ key = "drink", class = "ANY", names = { "Drink", "Food & Drink", "Refreshment" }, spells = {}, look = "surge", surge = "pour", globe = "mana", tint = "water", length = 30, kind = "reading",
		label = "Drinking", desc = "a column of light pouring into the mana globe while you drink" },

	-- Flares: instant, nothing to keep up.
	{ key = "lifeTap", class = "WARLOCK", spells = { 1454 }, names = { "Life Tap" }, look = "flare",
		flare = { { globe = "health", tint = "blood", dir = "out" }, { globe = "mana", tint = "shadow", dir = "in" } },
		label = "Life Tap", desc = "the health globe bursts and the mana globe draws it in" },
	{ key = "darkPact", class = "WARLOCK", spells = { 18220 }, names = { "Dark Pact" }, look = "flare",
		flare = { { globe = "mana", tint = "shadow", dir = "in" } },
		label = "Dark Pact", desc = "the mana globe draws in violet light" },
	{ key = "layOnHands", class = "PALADIN", spells = { 633 }, names = { "Lay on Hands" }, look = "flare", heal = "benediction", target = "any",
		flare = { { globe = "health", tint = "holy", dir = "in" } },
		label = "Lay on Hands", desc = "a beam of gold light strikes the health globe, when it is on you" },
	-- Your direct heals, when they land on you (target = "any": your cast aimed at you, never a
	-- heal on someone else). Heals leave no buff to confirm with, so when the client hides a cast's
	-- target (in combat) Watch.lua goes by who it could have gone to: see GuessAim there.
	{ key = "flashOfLight", class = "PALADIN", spells = { 19750 }, names = { "Flash of Light" }, look = "flare", heal = "mend", target = "any",
		flare = { { globe = "health", tint = "holy", dir = "in" } },
		label = "Flash of Light", desc = "a dome of gold light swells off the health globe's surface, when it is on you" },
	{ key = "holyLight", class = "PALADIN", spells = { 635 }, names = { "Holy Light" }, look = "flare", heal = "mend", target = "any",
		flare = { { globe = "health", tint = "holy", dir = "in" } },
		label = "Holy Light", desc = "a dome of gold light swells off the health globe's surface, when it is on you" },
	{ key = "flashHeal", class = "PRIEST", spells = { 2061 }, names = { "Flash Heal" }, look = "flare", heal = "mend", target = "any",
		flare = { { globe = "health", tint = "holy", dir = "in" } },
		label = "Flash Heal", desc = "a dome of gold light swells off the health globe's surface, when it is on you" },
	{ key = "lesserHeal", class = "PRIEST", spells = { 2050 }, names = { "Lesser Heal" }, look = "flare", heal = "mend", target = "any",
		flare = { { globe = "health", tint = "holy", dir = "in" } },
		label = "Lesser Heal", desc = "a dome of gold light swells off the health globe's surface, when it is on you" },
	{ key = "heal", class = "PRIEST", spells = { 2054 }, names = { "Heal" }, look = "flare", heal = "mend", target = "any",
		flare = { { globe = "health", tint = "holy", dir = "in" } },
		label = "Heal", desc = "a dome of gold light swells off the health globe's surface, when it is on you" },
	{ key = "greaterHeal", class = "PRIEST", spells = { 2060 }, names = { "Greater Heal" }, look = "flare", heal = "benediction", target = "any",
		flare = { { globe = "health", tint = "holy", dir = "in" } },
		label = "Greater Heal", desc = "a beam of gold light strikes the health globe, when it is on you" },
	{ key = "lesserHealingWave", class = "SHAMAN", spells = { 8004 }, names = { "Lesser Healing Wave" }, look = "flare", heal = "mend", target = "any",
		flare = { { globe = "health", tint = "water", dir = "in" } },
		label = "Lesser Healing Wave", desc = "a dome of pale light swells off the health globe's surface, when it is on you" },
	{ key = "healingWave", class = "SHAMAN", spells = { 331 }, names = { "Healing Wave" }, look = "flare", heal = "benediction", target = "any",
		flare = { { globe = "health", tint = "water", dir = "in" } },
		label = "Healing Wave", desc = "a beam of pale light strikes the health globe, when it is on you" },
	{ key = "healingTouch", class = "DRUID", spells = { 5185 }, names = { "Healing Touch" }, look = "flare", heal = "benediction", target = "any",
		flare = { { globe = "health", tint = "nature", dir = "in" } },
		label = "Healing Touch", desc = "a beam of green light strikes the health globe, when it is on you" },
	{ key = "healingPotion", class = "ANY", spells = { 439, 440, 441, 2024, 4042, 17534 }, names = { "Healing Potion" }, look = "flare",
		flare = { { globe = "health", tint = "vital", dir = "in" } },
		label = "Healing potion", desc = "red light floods into the health globe" },
	{ key = "healthstone", class = "ANY", spells = { 6262, 6263, 5720, 5723, 11732 },
		names = { "Minor Healthstone", "Lesser Healthstone", "Healthstone", "Greater Healthstone", "Major Healthstone" }, look = "flare",
		flare = { { globe = "health", tint = "fel", dir = "in" } },
		label = "Healthstone", desc = "fel-green light floods into the health globe" },
	{ key = "manaPotion", class = "ANY", spells = { 437, 438, 2023, 11903, 17531 }, names = { "Restore Mana" }, look = "flare",
		flare = { { globe = "mana", tint = "arcane", dir = "in" } },
		label = "Mana potion", desc = "blue light floods into the mana globe" },

	-- Shields from anyone (a priest's shield, a voidwalker's Sacrifice): only while the game says
	-- you hold an absorb, so only once it has shown it reports them. Last, so a known shield's
	-- own colour wins.
	{ key = "absorb", class = "ANY", spells = {}, names = {}, look = "shell", globe = "health", tint = "holyShield", kind = "absorb",
		label = "Any other shield", desc = "a pale crystal shell over the health globe while any other shield holds" },
}

-- Every seal, tracked or not: casting any of them ends the others. IDs no client has are
-- skipped; the English names cover a client that can't name an ID.
ns.WatchData.GROUPS = {
	seal = {
		spells = { 20154, 21084, 21082, 20164, 20165, 20166, 20375, 31801, 31892, 53720, 348704 },
		names = { "Seal of Righteousness", "Seal of the Crusader", "Seal of Justice", "Seal of Light", "Seal of Wisdom",
			"Seal of Command", "Seal of Vengeance", "Seal of Blood", "Seal of the Martyr", "Seal of Corruption" },
	},
}

-- Spells that unleash a group, and the one whose usability is the gate.
ns.WatchData.CONSUMERS = {
	judgement = { spells = { 20271, 53407, 53408 }, names = { "Judgement", "Judgement of Light", "Judgement of Wisdom", "Judgement of Justice" },
		group = "seal", gate = 20271 },
}

-- What a skill can be set to show (GlobeAura.lua LookOf), for the options: the names, and the
-- order the choices are listed in. A buff picks from LOOK_ORDER, a one-off flare from FLARE_ORDER.
ns.WatchData.LOOK_NAMES = {
	radiate = "Radiance", tally = "Slashes", shell = "Crystal shell", aegis = "Aegis", rime = "Rime", hex = "Hex ward", bulwark = "Bulwark", frozen = "Frozen", pour = "Pour", inhale = "Inhale", upwell = "Upwell", swirl = "Swirl", fury = "Fury",
	vines = "Vines", halo = "Halo", bloom = "Bloom", veil = "Veil", rain = "Rain", pulse = "Pulse", embers = "Embers",
	burst = "Burst", mend = "Mend", benediction = "Benediction", mound = "Surge",
}
ns.WatchData.LOOK_ORDER = { "radiate", "tally", "shell", "aegis", "rime", "hex", "bulwark", "frozen", "pour", "inhale", "upwell", "swirl", "fury", "vines", "halo", "bloom", "veil", "rain", "pulse", "embers" }
ns.WatchData.FLARE_ORDER = { "burst", "mend", "benediction", "mound" }
-- How a shield breaks, for the options. Only skills that can really break get the choice.
ns.WatchData.BREAK_NAMES = { shatter = "Shatter", shockwave = "Shockwave", dissolve = "Dissolve", crumble = "Crumble", melt = "Melt" }
ns.WatchData.BREAK_ORDER = { "shatter", "shockwave", "dissolve", "crumble", "melt" }

-- Option and test-mode order of the classes.
ns.WatchData.CLASSES = { "WARRIOR", "SHAMAN", "PALADIN", "PRIEST", "MAGE", "WARLOCK", "DRUID", "ROGUE", "HUNTER", "ANY" }
ns.WatchData.CLASS_NAMES = {
	WARRIOR = "Warrior", SHAMAN = "Shaman", PALADIN = "Paladin", PRIEST = "Priest", MAGE = "Mage", WARLOCK = "Warlock",
	DRUID = "Druid", ROGUE = "Rogue", HUNTER = "Hunter", ANY = "Everyone",
}
