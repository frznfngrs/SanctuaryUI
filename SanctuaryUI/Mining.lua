SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.Mining = ns.Mining or {}
local M = ns.Mining

BINDING_NAME_SANCTUARYUIMINING = "Rock Bottom"

-- Rock Bottom: A Miner's Memoir, the third of the books (Book.lua), about mining. Its node table
-- is MiningNodes.lua and its smelts and people MiningRecipes.lua (both generated from the game
-- install and GatherLite's Forever database), its words MiningData.lua. This file writes the
-- chapters, reads your Mining skill and bags, and keeps a per-character memoir that writes
-- itself: veins mined, what fell out of them, veins where the maps had no spot, smelting.

local Book = ns.Book
local INK, RED, MUTED, GREEN, AMBER, GOLD = Book.INK, Book.RED, Book.MUTED, Book.GREEN, Book.AMBER, Book.GOLD
local Readable, Commas = Book.Readable, Book.Commas

-- Book.Fill, then "a Iron Deposit" becomes "an Iron Deposit" (names go into lines that say "a").
local function Fill(text, fields)
	return (Book.Fill(text, fields):gsub("%f[%w]([Aa]) ([AEIO]%l)", "%1n %2"))
end
local MySide, Enemy, SIDE_NAME = Book.MySide, Book.Enemy, Book.SIDE_NAME
local ORANGE = { 0.72, 0.30, 0.02 }
local YELLOW = { 0.56, 0.45, 0.00 }
local TICK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:13:13:0:-1|t "
local NEW = "  |cff9a6a0e(new)|r"

M.CHAPTERS = {
	{ key = "diary", title = "The Memoir", tip = "Your memoir, written as you mine: firsts, gems, veins the maps didn't know, milestones, and the tally." },
	{ key = "seam", title = "The Seam", tip = "Here and now: your skill, what grows in this zone, where to dig next, and what your bags can smelt." },
	{ key = "route", title = "The Way Down", tip = "Ranks, the road to 300 for your side, and every trainer and supplier." },
	{ key = "veins", title = "Veins & Deposits", tip = "Every node: the skill it wants, its colours, what it gives, and where it grows thickest." },
	{ key = "smelter", title = "The Smelter", tip = "Every smelt: what goes in, where it's learned, what the bar is for, and where the forges are." },
	{ key = "gems", title = "Gems & Stone", tip = "The gems that fall out of the rock, and what all that stone is for." },
	{ key = "kit", title = "Pick & Kit", tip = "Picks, Find Minerals, gear that helps, the camp blueprints, legacy talents." },
	{ key = "tales", title = "Down the Pit", tip = "Old stories from under the mountains, and rumours we couldn't confirm." },
}

local MINING_SKILL = 186
local MINING_SPELL = 2575
local FIND_GAP = 0.006 -- a vein further than this (a fraction of the map) from every known spot is a find
local MAX_FINDS = 500
local MAX_TROPHIES = 60

local function Opt()
	return ns.DB().mining
end

-- This character's mining log and memoir.
local function Log()
	local char = ns.db and ns.db.char
	return char and char.mining
end
M.Log = Log

local function D() return ns.MiningData end

local spec = {
	key = "mining",
	frameName = "SanctuaryUIRockBottom",
	title = "Rock Bottom",
	art = "rockbottom",
	opt = Opt,
	log = Log,
	chapters = M.CHAPTERS,
	home = "seam",
	live = "seam",
	place = { "CENTER", 0, 0 },
	story = function() return D().STORY end,
	words = {
		search = "Search Rock Bottom",
		nothing = "Nothing by \"%s\". Try digging somewhere else.",
		scope = "Search looks at veins, zones, smelts, gems, stone, trainers and suppliers, the kit, tall tales and your memoir.",
		wet = "This page caved in: ",
		empty = "Nothing yet. Somewhere out there a rock is waiting to be hit. Go and hit it.",
		paused = "The memoir is paused (Options > Professions > Rock Bottom).",
		older = "...and %d older entries, under the rubble.",
	},
}
local book = Book.New(spec)
M.book = book
local B, Pick = book.B, book.Pick

---------------------------------------------------------------------------
-- The tables, indexed.

local BY_KEY, BY_NAME, COUNT, ZONE_MAP, BY_SPELL, SMELTS_FOR, GEM, STONE, ORE
local function Tables()
	if BY_KEY then return end
	local d = D()
	BY_KEY, BY_NAME, COUNT, ZONE_MAP, BY_SPELL, SMELTS_FOR, GEM, STONE, ORE = {}, {}, {}, {}, {}, {}, {}, {}, {}
	for _, v in ipairs(d.VEINS) do
		BY_KEY[v.key], BY_NAME[v.name] = v, v
		for _, name in ipairs(v.also or {}) do BY_NAME[name] = v end
		COUNT[v.key] = {}
		for map, s in pairs(d.SPOTS[v.key] or {}) do COUNT[v.key][map] = math.floor(#s / 6) end
	end
	for map, name in pairs(d.MAPS) do ZONE_MAP[name] = map end
	for _, s in ipairs(d.SMELTS) do
		BY_SPELL[s.spell] = s
		for _, need in ipairs(s.needs) do
			SMELTS_FOR[need[1]] = SMELTS_FOR[need[1]] or {}
			table.insert(SMELTS_FOR[need[1]], s)
		end
	end
	for _, g in ipairs(d.GEMS or {}) do GEM[g.id] = g end
	for _, s in ipairs(d.STONES or {}) do STONE[s.id] = s end
	for _, y in pairs(d.YIELD or {}) do
		for _, id in ipairs(y.ore or {}) do ORE[id] = true end
	end
end

-- The spots a vein has on a map, unpacked the first time they're asked for.
local SPOTS = {}
function M.Spots(key, map)
	local s = D().SPOTS[key] and D().SPOTS[key][map]
	if not s then return {} end
	local id = key .. "@" .. map
	if SPOTS[id] then return SPOTS[id] end
	local out = {}
	for i = 1, #s - 5, 6 do
		out[#out + 1] = { tonumber(s:sub(i, i + 2)) / 1000, tonumber(s:sub(i + 3, i + 5)) / 1000 }
	end
	SPOTS[id] = out
	return out
end

local function ItemName(id)
	local log = Log()
	local d = D()
	return d.ITEM[id] or (GEM[id] and GEM[id].name) or (STONE[id] and STONE[id].name) or (d.ITEMS and d.ITEMS[id])
		or (log and log.names[id]) or ("item " .. id)
end

-- "2 Iron Ore, Coal"
local function Needs(s)
	if #s.needs == 0 then return "The tables don't say what goes in yet." end
	local parts = {}
	for _, need in ipairs(s.needs) do
		parts[#parts + 1] = (need[2] > 1 and (need[2] .. " ") or "") .. ItemName(need[1])
	end
	return table.concat(parts, ", ")
end

---------------------------------------------------------------------------
-- What the client says: your skill, your bags, the smelts you know, where you stand.

-- rank, cap; nil when you haven't learned to mine (or the client won't say).
function M.Skill()
	return Book.Skill(MINING_SKILL, MINING_SPELL, PROFESSIONS_MINING or "Mining")
end

local function Have(id)
	local count
	if C_Item and C_Item.GetItemCount then
		local ok, n = pcall(C_Item.GetItemCount, id)
		if ok then count = n end
	end
	if count == nil and GetItemCount then count = GetItemCount(id) end
	return Readable(count) and count or 0
end

-- Does the spellbook hold this smelt? true, false, or nil when the client can't be asked.
local function Asked(spell)
	if C_SpellBook and C_SpellBook.IsSpellKnown and Enum and Enum.SpellBookSpellBank then
		local ok, known = pcall(C_SpellBook.IsSpellKnown, spell, Enum.SpellBookSpellBank.Player)
		if ok and Readable(known) then return known and true or false end
	end
	for _, name in ipairs({ "IsPlayerSpell", "IsSpellKnown" }) do
		local fn = _G[name]
		if fn then
			local ok, known = pcall(fn, spell)
			if ok and Readable(known) then return known and true or false end
		end
	end
end

local function Knows(s)
	local log = Log()
	if log and log.known[s.spell] then return true end
	return Asked(s.spell) or false
end

-- Can the book tell which smelts you know? Not when none reads as known.
local function CanTell()
	local log = Log()
	if log and next(log.known) then return true end
	for _, s in ipairs(D().SMELTS) do
		if Asked(s.spell) then return true end
	end
	return false
end

local function Where()
	local zone = GetRealZoneText and GetRealZoneText() or ""
	return Readable(zone) and zone or ""
end

local function Indoors()
	if not IsInInstance then return false end
	local ok, inside = pcall(IsInInstance)
	return ok and Readable(inside) and inside or false
end

-- The zone map you're on (one of the book's), and where on it: map, x, y. x and y are nil when
-- the client won't place you; map is nil off the book's maps (instances, cities without veins).
local function Here()
	local d = D()
	if not C_Map or not C_Map.GetBestMapForUnit or Indoors() then
		return ZONE_MAP and ZONE_MAP[Where()]
	end
	local ok, map = pcall(C_Map.GetBestMapForUnit, "player")
	if not ok or not Readable(map) then return ZONE_MAP and ZONE_MAP[Where()] end
	local hops = 0
	while map and map > 0 and not d.MAPS[map] and hops < 6 do
		local info = C_Map.GetMapInfo and C_Map.GetMapInfo(map)
		map = info and info.parentMapID
		hops = hops + 1
	end
	if not map or not d.MAPS[map] then return ZONE_MAP and ZONE_MAP[Where()] end
	local x, y
	if C_Map.GetPlayerMapPosition then
		local ok2, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
		if ok2 and pos and pos.GetXY then x, y = pos:GetXY() end
	end
	if not Readable(x) or not Readable(y) or (x == 0 and y == 0) then x, y = nil, nil end
	return map, x, y
end
M.Here = Here

-- Whose land a zone is: "A", "H", or "N" (contested and neutral). The angler's book knows most;
-- MiningData.lua the rest.
local function ZoneSide(name)
	local own = D().ZONE_SIDE and D().ZONE_SIDE[name]
	if own then return own end
	local fish = ns.FishingData and ns.FishingData.ZONE_BY_NAME and ns.FishingData.ZONE_BY_NAME[name]
	return fish and fish.side or "N"
end

local function Coin(copper)
	if copper >= 10000 then return ("%dg"):format(copper / 10000) end
	if copper >= 100 then return ("%ds"):format(copper / 100) end
	return ("%dc"):format(copper)
end

-- A line about the other side's thing, the same one each time for the same name.
local function EnemyLine(side, name)
	local list = D().ENEMY[side]
	local n = 0
	for i = 1, #name do n = n + name:byte(i) end
	return list[n % #list + 1]
end

-- How much a vein still teaches you: "locked", "orange", "yellow", "green", "grey", or "open"
-- (you can mine it; nobody has published its colours). nil with no skill.
local function Colour(v, rank)
	if not rank then return end
	if rank < v.skill then return "locked" end
	if not v.yellow then return "open" end
	if rank < v.yellow then return "orange" end
	if rank < v.green then return "yellow" end
	if rank < v.grey then return "green" end
	return "grey"
end
M.Colour = Colour

-- A smelt's colour, the same way (grey when known numbers say so).
local function SmeltColour(s, rank)
	if not rank then return end
	if rank < s.skill then return "locked" end
	if not s.yellow then return end
	local green = math.floor((s.yellow + s.grey) / 2)
	if rank < s.yellow then return "orange" end
	if rank < green then return "yellow" end
	if rank < s.grey then return "green" end
	return "grey"
end

local DIFF = {
	locked = { RED, "not yet", 0 }, orange = { ORANGE, "a point every time", 5 }, yellow = { YELLOW, "a point, mostly", 4 },
	open = { AMBER, "yours to mine", 3 }, green = { GREEN, "a point, sometimes", 2 }, grey = { MUTED, "nothing to learn", 1 },
}
-- How much a vein of each colour is worth to the way up, for picking zones.
local WORTH = { orange = 3, yellow = 2, open = 1.5, green = 0.5 }

-- The zones a vein grows in, thickest first: { { map, name, n } }.
local function Zones(key)
	Tables()
	local out = {}
	for map, n in pairs(COUNT[key] or {}) do
		out[#out + 1] = { map, D().MAPS[map], n }
	end
	table.sort(out, function(a, b)
		if a[3] ~= b[3] then return a[3] > b[3] end
		return a[2] < b[2]
	end)
	return out
end
M.Zones = Zones

-- Where your skill is best spent: zones scored by the veins that still teach you, your side's
-- and neutral land first. { { map, name, score, veins = { { v, n, colour } } } }.
local function BestZones(rank)
	Tables()
	local d = D()
	local zones = {}
	for _, v in ipairs(d.VEINS) do
		local colour = not d.GHOST[v.key] and Colour(v, rank)
		local worth = colour and WORTH[colour]
		if worth then
			for map, n in pairs(COUNT[v.key]) do
				local z = zones[map]
				if not z then
					z = { map, d.MAPS[map], 0, veins = {} }
					zones[map] = z
				end
				z[3] = z[3] + n * worth
				z.veins[#z.veins + 1] = { v, n, colour }
			end
		end
	end
	local list = {}
	for _, z in pairs(zones) do
		z.enemy = Enemy(ZoneSide(z[2]))
		table.sort(z.veins, function(a, b)
			local wa, wb = WORTH[a[3]] * a[2], WORTH[b[3]] * b[2]
			if wa ~= wb then return wa > wb end
			return a[1].name < b[1].name
		end)
		list[#list + 1] = z
	end
	table.sort(list, function(a, b)
		if a.enemy ~= b.enemy then return not a.enemy end
		if a[3] ~= b[3] then return a[3] > b[3] end
		return a[2] < b[2]
	end)
	return list
end
M.BestZones = BestZones

-- "Name, Zone (x, y)"
local function Person(id, bare)
	local n = D().NPC[id]
	if not n then return "someone" end
	local text = n[1]
	if n[2] ~= "" and not bare then text = text .. ", " .. n[2] end
	if n[3] > 0 then text = text .. (" (%.1f, %.1f)"):format(n[3], n[4]) end
	return text
end

-- People of a kind, yours and neutral first, those in this zone first of all.
local function People(kind)
	local d, here, out = D(), Where(), {}
	for id, n in pairs(d.NPC) do
		if n[7] == kind then out[#out + 1] = id end
	end
	table.sort(out, function(a, b)
		local na, nb = d.NPC[a], d.NPC[b]
		local ea, eb = Enemy(na[5]), Enemy(nb[5])
		if ea ~= eb then return not ea end
		local ha, hb = na[2] == here, nb[2] == here
		if ha ~= hb then return ha end
		if na[2] ~= nb[2] then return na[2] < nb[2] end
		return na[1] < nb[1]
	end)
	return out
end

-- How a smelt is learned, for you.
local function Learn(s)
	local d = D()
	if d.LEARN and d.LEARN[s.item] then return d.LEARN[s.item] end
	local parts = {}
	if s.auto then parts[#parts + 1] = "You know it the day you learn to mine" end
	for _, how in ipairs(s.how) do
		if how == "trainer" then
			parts[#parts + 1] = "Any mining trainer" .. (s.cost and (" (" .. Coin(s.cost) .. ")") or "")
		elseif how == "quest" then
			parts[#parts + 1] = "A quest from your home town's junior mining trainer"
		elseif how == "drop" then
			parts[#parts + 1] = s.teach and ("Taught by " .. ItemName(s.teach) .. ", a drop") or "Taught by a drop"
		end
	end
	if #parts == 0 then return "Where it's learned isn't known yet." end
	return table.concat(parts, ". ") .. "."
end

---------------------------------------------------------------------------
-- The memoir: veins mined, what fell out, finds, smelting, milestones.

local Today = Book.Today

-- Is a spot further than FIND_GAP from every spot the book knows for this vein on this map?
local function Unknown(key, map, x, y)
	for _, p in ipairs(M.Spots(key, map)) do
		if math.abs(p[1] - x) < FIND_GAP and math.abs(p[2] - y) < FIND_GAP then return false end
	end
	-- Your own finds count as known: the same vein twice isn't two finds.
	local log = Log()
	for _, f in ipairs(log and log.finds or {}) do
		if f[1] == key and f[2] == map and math.abs(f[3] - x) < FIND_GAP and math.abs(f[4] - y) < FIND_GAP then return false end
	end
	return true
end

local function Quality(id, fallback)
	if C_Item and C_Item.GetItemQualityByID then
		local ok, q = pcall(C_Item.GetItemQualityByID, id)
		if ok and Readable(q) and type(q) == "number" then return q end
	end
	return Readable(fallback) and type(fallback) == "number" and fallback or 1
end

-- One vein mined: vein (a D.VEINS row, or { key = "other:Name", name = "Name" } for one the
-- book doesn't know), loot { { id, name, n, q } }, map/x/y where it stood (nil if unknown).
local function OnMined(vein, loot, map, x, y)
	local log = Log()
	if not log then return end
	Tables()
	local lines = D().LINES
	local zone = Where() ~= "" and Where() or "these parts"
	local before = log.total or 0
	local fresh = not log.veins[vein.key]
	log.veins[vein.key] = (log.veins[vein.key] or 0) + 1
	log.total = before + 1
	log.zones[zone] = (log.zones[zone] or 0) + 1
	local fields = { vein = vein.name, zone = zone }
	local stone, ore, gems = 0, 0, {}
	for _, item in ipairs(loot) do
		local id, n = item[1], item[2]
		log.items[id] = (log.items[id] or 0) + n
		if item[3] then log.names[id] = item[3] end
		log.quality[id] = item[4]
		if STONE[id] then stone = stone + n end
		if ORE[id] then
			ore = ore + n
			fields.ore = fields.ore or item[3]
		end
		if GEM[id] or (item[4] or 1) >= 2 then gems[#gems + 1] = item end
	end
	fields.ore = fields.ore or "ore"
	-- The first vein ever, then each new kind.
	if before == 0 then
		book.Write(Fill(lines.first[1], fields))
	elseif fresh then
		book.Write(Fill(lines.special[vein.key] or Pick(lines.vein, "vein"), fields))
	end
	-- Gems: every one is a line, rarer ones louder.
	for _, item in ipairs(gems) do
		local q = item[4] or 2
		fields.gem = item[3] or ItemName(item[1])
		local deck = q >= 3 and "rare" or "gem"
		book.Write(Fill(Pick(q >= 3 and lines.rare or lines.gem, deck), fields), q)
		log.trophies[#log.trophies + 1] = { item[1], fields.gem, q, time(), zone }
		while #log.trophies > MAX_TROPHIES do table.remove(log.trophies, 1) end
	end
	-- A vein the maps don't have.
	if map and x and not vein.key:find("^other:") and Unknown(vein.key, map, x, y) then
		log.finds[#log.finds + 1] = { vein.key, map, math.floor(x * 1000 + 0.5) / 1000, math.floor(y * 1000 + 0.5) / 1000, time() }
		while #log.finds > MAX_FINDS do table.remove(log.finds, 1) end
		if ns.MiningMap and ns.MiningMap.Forget then ns.MiningMap.Forget(map) end
		if ns.MiningShare and ns.MiningShare.Shout then ns.MiningShare.Shout(log.finds[#log.finds]) end
		if log.findDay ~= Today() then
			log.findDay = Today()
			book.Write(Fill(Pick(lines.find, "find"), fields))
		end
	end
	-- Mining for the habit: one line a day once a vein teaches you nothing.
	local colour = BY_KEY[vein.key] and Colour(vein, (M.Skill()))
	if colour == "grey" and not fresh and log.greyDay ~= Today() then
		log.greyDay = Today()
		book.Write(Fill(Pick(lines.grey, "grey"), fields))
	end
	-- Stone piling up: once a day, past forty.
	if log.stoneDay ~= Today() then log.stoneDay, log.stoneToday = Today(), 0 end
	local was = log.stoneToday or 0
	log.stoneToday = was + stone
	if was < 40 and log.stoneToday >= 40 then
		book.Write(Fill(Pick(lines.stone, "stone"), { n = log.stoneToday, zone = zone }))
	end
	for mark, line in pairs(lines.total) do
		if before < mark and log.total >= mark then book.Write(line) end
	end
	-- A long day underground, once.
	if log.batchDay ~= Today() then log.batchDay, log.batch = Today(), 0 end
	local had = log.batch or 0
	log.batch = had + 1
	if had < 50 and log.batch >= 50 then
		book.Write(Fill(lines.batch, { n = log.batch, zone = zone }))
	end
	book.Refresh()
end

local function OnSmelted(s)
	local log = Log()
	if not log then return end
	local made = s.makes or 1
	local fresh = not log.smelted[s.spell]
	log.smelted[s.spell] = (log.smelted[s.spell] or 0) + made
	log.bars = (log.bars or 0) + made
	if fresh then
		local name = ItemName(s.item)
		local lines = D().LINES
		book.Write(Fill(lines.smeltSpecial[name] or Pick(lines.smelt, "smelt"), { bar = name }))
	end
	book.Refresh()
end

-- A Mining cast in flight: the vein's name comes with UNIT_SPELLCAST_SENT, the loot with
-- LOOT_OPENED just after it succeeds.
local cast = {}
local MINING_NAME

local function IsMining(spellID)
	if not Readable(spellID) then return false end
	if not MINING_NAME then
		MINING_NAME = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(MINING_SPELL)) or (GetSpellInfo and GetSpellInfo(MINING_SPELL)) or "Mining"
		if not Readable(MINING_NAME) then MINING_NAME = "Mining" end
	end
	local name = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)) or (GetSpellInfo and GetSpellInfo(spellID))
	return Readable(name) and name == MINING_NAME
end

local function Finish(loot)
	local c = cast
	cast = {}
	if c.vein then OnMined(c.vein, loot or {}, c.map, c.x, c.y) end
end

local function ReadLoot()
	local loot = {}
	local n = GetNumLootItems and GetNumLootItems() or 0
	if not Readable(n) then return loot end
	for i = 1, n do
		local link = GetLootSlotLink and GetLootSlotLink(i)
		local id = Readable(link) and type(link) == "string" and tonumber(link:match("item:(%d+)"))
		if id then
			local _, name, count, _, quality = GetLootSlotInfo(i)
			if type(quality) ~= "number" then
				-- Older order: texture, name, count, quality.
				local _, _, _, q = GetLootSlotInfo(i)
				quality = q
			end
			count = Readable(count) and tonumber(count) or 1
			loot[#loot + 1] = { id, count, Readable(name) and name or nil, Quality(id, quality) }
		end
	end
	return loot
end

local function OnEvent(event, unit, a, b, c)
	if event == "UNIT_SPELLCAST_SENT" then
		if unit ~= "player" then return end
		local target, guid, spellID = a, b, c
		if not Readable(target) or not Readable(guid) or not IsMining(spellID) then return end
		Tables()
		local vein = BY_NAME[target] or { key = "other:" .. target, name = target }
		local map, x, y = Here()
		cast = { vein = vein, guid = guid, spell = spellID, map = map, x = x, y = y }
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		if unit ~= "player" or not Readable(b) then return end
		local guid, spellID = a, b
		Tables()
		if BY_SPELL[spellID] then OnSmelted(BY_SPELL[spellID]) end
		if cast.guid and Readable(guid) and guid == cast.guid then
			cast.done = GetTime()
			-- The loot window usually follows at once; if it never does, count the vein anyway.
			local mine = cast
			C_Timer.After(1.5, function()
				if cast == mine then Finish({}) end
			end)
		end
	elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
		if unit ~= "player" or not cast.guid then return end
		if Readable(a) and a == cast.guid then cast = {} end
	elseif event == "LOOT_OPENED" then
		if cast.done and GetTime() - cast.done < 1.5 then Finish(ReadLoot()) end
	end
end

-- New smelts: whatever the spellbook holds that the log doesn't. The first look only remembers.
local function CheckSmelts(announce)
	local log = Log()
	if not log then return end
	local written = 0
	for _, s in ipairs(D().SMELTS) do
		if not log.known[s.spell] and Asked(s.spell) then
			log.known[s.spell] = true
			if log.scanned and announce ~= false and written < 2 then
				written = written + 1
				book.Write(Fill(Pick(D().LINES.learned, "learned"), { bar = ItemName(s.item) }))
			end
		end
	end
	if next(log.known) then log.scanned = true end
end

-- Skill and rank milestones. The first look on a character only remembers where you are.
local function CheckSkill()
	local log = Log()
	if not log then return end
	local rank, cap = M.Skill()
	if not rank then return end
	local lines = D().LINES
	if not log.started then
		log.started = true
		log.skillSeen, log.rankSeen = rank, cap
		if rank > 1 then
			book.Write(Fill(lines.opened, { skill = rank }))
		end
		return
	end
	if rank > (log.skillSeen or 0) then
		for mark = 25, 300, 25 do
			if (log.skillSeen or 0) < mark and rank >= mark then
				book.Write(Fill(lines.skill[mark] or lines.skill.other, { skill = mark }))
			end
		end
		log.skillSeen = rank
	end
	if cap > (log.rankSeen or 0) then
		if lines.rank[cap] and (log.rankSeen or 0) > 0 then book.Write(lines.rank[cap]) end
		log.rankSeen = cap
	end
end

---------------------------------------------------------------------------
-- Chapters.

local BUILD = {}

local function Opener(key)
	B.opener(D().OPENERS, key)
end

local function VeinName(v)
	return v.name .. (D().FOREVER and D().FOREVER[v.key] and NEW or "")
end

local function SmeltName(s, tell)
	return ((tell and Knows(s)) and TICK or "") .. ItemName(s.item) .. ((s.spell > 400000) and NEW or "")
end

local function MapLink(title, key, map)
	if not (ns.MiningMap and ns.MiningMap.Show) then return end
	B.row({ "", title }, { 0.0, 1.0 }, {
		colors = { MUTED, GOLD }, tip = "Open the world map with the veins drawn on it",
		onClick = function() ns.MiningMap.Show(key, map) end,
	})
end

function BUILD.diary()
	local log = Log()
	if not log then return end
	Tables()
	B.h("The tally")
	local kinds, best, bestN = 0, nil, 0
	for key, n in pairs(log.veins) do
		kinds = kinds + 1
		if n > bestN then best, bestN = key, n end
	end
	local zone, zoneN = nil, 0
	for z, n in pairs(log.zones) do
		if n > zoneN then zone, zoneN = z, n end
	end
	local ore, gems, stone = 0, 0, 0
	for id, n in pairs(log.items) do
		if ORE[id] then ore = ore + n end
		if STONE[id] then stone = stone + n end
		if GEM[id] then gems = gems + n end
	end
	B.kv("Veins mined", Commas(log.total))
	B.kv("Kinds", Commas(kinds))
	B.kv("Ore", Commas(ore))
	B.kv("Stone", Commas(stone) .. (stone >= 500 and "  (enough for a small keep)" or ""))
	B.kv("Gems", Commas(gems))
	if (log.bars or 0) > 0 then B.kv("Bars smelted", Commas(log.bars)) end
	if #log.finds > 0 then B.kv("Veins the maps didn't know", Commas(#log.finds)) end
	if best then
		local v = BY_KEY[best]
		B.kv("Most mined", ("%s (%s)"):format(v and v.name or best:gsub("^other:", ""), Commas(bestN)))
	end
	if zone then B.kv("Favourite hole", ("%s (%s)"):format(zone, Commas(zoneN))) end
	if #log.trophies > 0 then
		B.h("Out of the rock")
		for i = #log.trophies, math.max(1, #log.trophies - 9), -1 do
			local t = log.trophies[i]
			B.row({ t[2], t[5] or "", date("%d %b", t[4]) }, { 0.46, 0.36, 0.18 }, { item = t[1], colors = { INK, MUTED, MUTED } })
		end
	end
	B.entries()
end

local function NextStep(rank, cap)
	local d = D()
	if rank >= cap and cap < 300 then
		for _, r in ipairs(d.RANKS) do
			if r[2] > cap then
				return ("Capped at %d. Next: %s. %s"):format(cap, r[1], r[3]), RED
			end
		end
	end
	Tables()
	-- The next vein to open up.
	local soon
	for _, v in ipairs(d.VEINS) do
		if v.skill > rank and v.points > 40 and not d.GHOST[v.key] and (not soon or v.skill < soon.skill) then soon = v end
	end
	if soon then
		return ("At %d: %s."):format(soon.skill, soon.name), MUTED
	end
end

function BUILD.seam()
	Tables()
	local d = D()
	local rank, cap = M.Skill()
	local map, x = Here()
	local zone = map and d.MAPS[map] or Where()
	B.h("Your pick")
	if not rank then
		B.hand(d.NOT_YET)
	else
		B.p(("Mining %d of %d."):format(rank, cap))
		local step, color = NextStep(rank, cap)
		if step then B.p(step, color, 12.5) end
	end

	-- What grows here.
	if map then
		local here = {}
		for _, v in ipairs(d.VEINS) do
			local n = COUNT[v.key][map]
			if n and not d.GHOST[v.key] then here[#here + 1] = { v, n } end
		end
		table.sort(here, function(a, b)
			if a[1].skill ~= b[1].skill then return a[1].skill < b[1].skill end
			return a[1].name < b[1].name
		end)
		B.h("In " .. zone)
		if #here == 0 then
			B.hand(d.BARREN)
		else
			B.row({ "Vein", "Spots", "For you" }, { 0.46, 0.14, 0.40 }, { head = true })
			for _, e in ipairs(here) do
				local colour = Colour(e[1], rank)
				local shade = colour and DIFF[colour]
				B.row({ VeinName(e[1]), tostring(e[2]), shade and shade[2] or ("Mining " .. e[1].skill) }, { 0.46, 0.14, 0.40 },
					{ colors = { INK, MUTED, shade and shade[1] or MUTED }, onClick = function() book.Jump("veins", "vein:" .. e[1].key) end, tip = "Read about it in Veins & Deposits" })
			end
			MapLink("Show this zone's veins on the world map", nil, map)
		end
		if Enemy(ZoneSide(zone)) then B.note(EnemyLine(ZoneSide(zone), zone)) end
	elseif Indoors() then
		B.h("Underground")
		B.hand(d.INSIDE)
	end

	-- Where to go.
	if rank then
		local best = BestZones(rank)
		if #best > 0 then
			B.h("Where to dig next")
			B.note("Zones scored by the veins that still teach you: orange counts most, then yellow, then green. Spots are the known ones.")
			for i = 1, math.min(4, #best) do
				local z = best[i]
				local parts = {}
				for j = 1, math.min(3, #z.veins) do
					local e = z.veins[j]
					parts[#parts + 1] = ("%s (%d)"):format(e[1].name, e[2])
				end
				B.row({ z[2] .. (z.enemy and (" (" .. SIDE_NAME[ZoneSide(z[2])] .. ")") or ""), table.concat(parts, ", ") }, { 0.34, 0.66 },
					{ colors = { i == 1 and GOLD or RED, INK }, dim = z.enemy, pad = 3,
						onClick = ns.MiningMap and ns.MiningMap.Show and function() ns.MiningMap.Show(nil, z[1]) end or nil,
						tip = ns.MiningMap and ns.MiningMap.Show and "Show its veins on the world map" or nil })
			end
		end
	end

	-- What the bags can become.
	local tell = CanTell()
	local ready = {}
	for _, s in ipairs(d.SMELTS) do
		if #s.needs > 0 and (not rank or rank >= s.skill) and (not tell or Knows(s)) and not (d.CAMP and d.CAMP[s.item]) then
			local n = math.huge
			for _, need in ipairs(s.needs) do n = math.min(n, math.floor(Have(need[1]) / need[2])) end
			if n > 0 then ready[#ready + 1] = { s, n } end
		end
	end
	if #ready > 0 then
		B.h("Ready to smelt")
		B.row({ "Bar", "Makes", "Teaches" }, { 0.46, 0.14, 0.40 }, { head = true })
		for _, e in ipairs(ready) do
			local colour = SmeltColour(e[1], rank)
			local shade = colour and DIFF[colour]
			B.row({ ItemName(e[1].item), tostring(e[2] * (e[1].makes or 1)), shade and shade[2] or "" }, { 0.46, 0.14, 0.40 },
				{ item = e[1].item, colors = { INK, INK, shade and shade[1] or MUTED } })
		end
		B.note(d.FORGE_HINT)
	end

	-- Gems and stone in the bags, and what they're for.
	local loose = {}
	for _, g in ipairs(d.GEMS or {}) do
		local n = Have(g.id)
		if n > 0 then loose[#loose + 1] = { g, n } end
	end
	for _, s in ipairs(d.STONES or {}) do
		local n = Have(s.id)
		if n > 0 then loose[#loose + 1] = { s, n } end
	end
	if #loose > 0 then
		B.h("In your bags")
		for _, e in ipairs(loose) do
			B.row({ ("%s  x%d"):format(e[1].name, e[2]), e[1].use or "" }, { 0.40, 0.60 }, { item = e[1].id, pad = 3 })
		end
	end

	-- Who's here.
	local people = {}
	for id, n in pairs(d.NPC) do
		if n[2] == zone and not Enemy(n[5]) then people[#people + 1] = id end
	end
	table.sort(people, function(a, b) return d.NPC[a][1] < d.NPC[b][1] end)
	if #people > 0 then
		B.h("Miners in " .. zone)
		for _, id in ipairs(people) do
			B.row({ Person(id, true), d.NPC[id][6] }, { 0.50, 0.50 }, { pad = 3 })
		end
	end
end

local function PersonRow(id)
	local n = D().NPC[id]
	local enemy = Enemy(n[5])
	local name = n[1] .. (enemy and (" (%s)"):format(SIDE_NAME[n[5]]) or (n[5] == "N" and " (both)" or ""))
	B.row({ name, n[2], n[3] > 0 and ("%.1f, %.1f"):format(n[3], n[4]) or "" }, { 0.40, 0.42, 0.18 }, { dim = enemy, anchor = "npc:" .. n[1] })
end

function BUILD.route()
	Opener("route")
	local d = D()
	local mine = MySide()
	B.h("Ranks")
	for i, r in ipairs(d.RANKS) do
		B.row({ ("%s (to %d)"):format(r[1], r[2]), r[3] }, { 0.3, 0.7 }, { anchor = "rank:" .. i })
	end
	B.h("The road to 300")
	if not mine then B.note("Both sides' roads, until the book can tell which you're on.") end
	for i, step in ipairs(d.ROUTE) do
		local text = mine and (step[mine] or step.N) or (step.N or step.A)
		B.row({ step[1], text }, { 0.18, 0.82 }, { colors = { RED, INK }, pad = 2, anchor = "route:" .. i })
		if not mine and step.H and step.H ~= step.A then
			B.row({ "", "Horde: " .. step.H }, { 0.18, 0.82 }, { colors = { RED, INK }, cont = true })
		end
		if step.note then B.row({ "", step.note }, { 0.18, 0.82 }, { colors = { MUTED, MUTED }, cont = true }) end
	end
	B.h("Trainers")
	local other = 0
	for _, id in ipairs(People("trainer")) do
		if Enemy(d.NPC[id][5]) then other = other + 1 else PersonRow(id) end
	end
	if mine and other > 0 then
		B.note(Fill(d.OTHER_TRAINERS, { n = other, side = SIDE_NAME[mine == "H" and "A" or "H"] }))
	end
	B.h("Picks, flux and coal")
	for _, id in ipairs(People("supplies")) do
		if not Enemy(D().NPC[id][5]) then PersonRow(id) end
	end
end

local BRACKETS = {
	{ 1, 74, "Apprentice veins (1 to 74)" }, { 75, 149, "Journeyman veins (75 to 149)" }, { 150, 224, "Expert veins (150 to 224)" },
	{ 225, 400, "Artisan veins (225 and up)" },
}

function BUILD.veins()
	Opener("veins")
	Tables()
	local d = D()
	local rank = M.Skill()
	if rank then
		B.note(("You mine at %d. A vein's number is coloured by what it still teaches: orange always, yellow mostly, green sometimes, grey nothing. Red: not yet."):format(rank))
	end
	local list = {}
	for _, v in ipairs(d.VEINS) do
		if not d.GHOST[v.key] and (v.points > 0 or (d.YIELD[v.key] and d.YIELD[v.key].where)) then list[#list + 1] = v end
	end
	table.sort(list, function(a, b)
		if a.skill ~= b.skill then return a.skill < b.skill end
		return a.name < b.name
	end)
	for _, bracket in ipairs(BRACKETS) do
		B.h(bracket[3])
		for _, v in ipairs(list) do
			if v.skill >= bracket[1] and v.skill <= bracket[2] then
				local colour = Colour(v, rank)
				local y = d.YIELD[v.key] or {}
				B.sub(VeinName(v), "vein:" .. v.key, colour and DIFF[colour][1] or nil)
				local skill = ("Mining %d"):format(v.skill)
				if v.yellow then skill = skill .. ("; yellow at %d, green at %d, grey at %d"):format(v.yellow, v.green, v.grey) end
				B.row({ "Skill", skill .. "." }, { 0.18, 0.82 }, { colors = { RED, colour and DIFF[colour][1] or INK } })
				if y.gives then B.row({ "Gives", y.gives }, { 0.18, 0.82 }, { colors = { RED, INK } }) end
				local zones = Zones(v.key)
				local parts = {}
				for i = 1, math.min(5, #zones) do
					local z = zones[i]
					local side = ZoneSide(z[2])
					parts[#parts + 1] = ("%s (%d)"):format(z[2], z[3]) .. (Enemy(side) and (" " .. SIDE_NAME[side]) or "")
				end
				local where = #parts > 0 and (table.concat(parts, ", ") .. (#zones > 5 and (", and %d more zones"):format(#zones - 5) or "") .. ".") or y.where
				if y.where and #parts > 0 then where = where .. " " .. y.where end
				if where then B.row({ "Where", where }, { 0.18, 0.82 }, { colors = { RED, INK } }) end
				if y.note then B.row({ "", y.note }, { 0.18, 0.82 }, { colors = { MUTED, MUTED }, cont = true }) end
				if #zones > 0 then MapLink("Show every " .. v.name .. " on the world map", v.key, zones[1][1]) end
			end
		end
	end
	B.h("Ghost veins", MUTED)
	B.note("In the game's tables and on Wowhead's Forever pages, with spots, but they grew in Season of Discovery's Nightmare Incursions. Nothing says they spawn here, so the book leaves them out of its advice and off the maps.")
	for _, v in ipairs(d.VEINS) do
		if d.GHOST[v.key] then
			local y = d.YIELD[v.key] or {}
			B.row({ v.name, ("Mining %d. %s"):format(v.skill, y.gives or "") }, { 0.36, 0.64 }, { dim = true, anchor = "vein:" .. v.key })
			B.row({ "", d.GHOST[v.key] }, { 0.0, 1.0 }, { colors = { MUTED, MUTED }, cont = true, dim = true })
		end
	end
	local spots = 0
	for _, v in ipairs(d.VEINS) do
		if not d.GHOST[v.key] then spots = spots + v.points end
	end
	B.note(("%s spots in all, from GatherLite's Forever database (Wowhead's coordinates). Numbers are known spots, not live nodes: a vein grows back somewhere in its cluster, rarely the same rock twice."):format(Commas(spots)))
end

local SMELT_BRACKETS = {
	{ 1, 74, "Apprentice" }, { 75, 149, "Journeyman" }, { 150, 224, "Expert" }, { 225, 400, "Artisan" },
}

function BUILD.smelter()
	Opener("smelter")
	Tables()
	local d = D()
	local rank = M.Skill()
	local tell = CanTell()
	if tell then
		local known, all = 0, 0
		for _, s in ipairs(d.SMELTS) do
			if not (d.CAMP and d.CAMP[s.item]) then
				all = all + 1
				if Knows(s) then known = known + 1 end
			end
		end
		B.note(("Ticked: you know it (%d of %d). Hover a bar for its card, shift-click to link it."):format(known, all))
	end
	local cols = { 0.40, 0.10, 0.50 }
	for _, bracket in ipairs(SMELT_BRACKETS) do
		local any = false
		for _, s in ipairs(d.SMELTS) do
			if s.skill >= bracket[1] and s.skill <= bracket[2] and not (d.CAMP and d.CAMP[s.item]) then
				if not any then
					B.h(bracket[3])
					B.row({ "Bar", "Skill", "Goes in" }, cols, { head = true })
					any = true
				end
				local colour = SmeltColour(s, rank)
				B.row({ SmeltName(s, tell), tostring(s.skill), Needs(s) }, cols,
					{ item = s.item, pad = 2, colors = { INK, colour and DIFF[colour][1] or INK, MUTED }, anchor = "smelt:" .. s.spell })
				local note = d.SMELT_NOTES and d.SMELT_NOTES[ItemName(s.item)]
				B.row({ "", (note and (note .. " ") or "") .. Learn(s) }, { 0.0, 1.0 }, { colors = { MUTED, MUTED }, cont = true })
			end
		end
	end
	if d.FORGES then
		B.h("Where the forges are")
		for i, f in ipairs(d.FORGES) do
			local enemy = f.side and Enemy(f.side)
			B.row({ f[1], f[2] }, { 0.36, 0.64 }, { dim = enemy, anchor = "forge:" .. i })
		end
	end
end

function BUILD.gems()
	Opener("gems")
	Tables()
	local d = D()
	B.h("Gems")
	B.note("They fall out of veins now and then, more often from the richer ones. Hover for the card.")
	for i, g in ipairs(d.GEMS or {}) do
		local n = Have(g.id)
		B.row({ g.name .. (n > 0 and ("  x%d"):format(n) or ""), g.from }, { 0.36, 0.64 }, { item = g.id, pad = 2, anchor = "gem:" .. i })
		if g.use then B.row({ "", g.use }, { 0.0, 1.0 }, { colors = { MUTED, MUTED }, cont = true }) end
	end
	B.h("Stone")
	for i, s in ipairs(d.STONES or {}) do
		local n = Have(s.id)
		B.row({ s.name .. (n > 0 and ("  x%d"):format(n) or ""), s.from }, { 0.36, 0.64 }, { item = s.id, pad = 2, anchor = "stone:" .. i })
		if s.use then B.row({ "", s.use }, { 0.0, 1.0 }, { colors = { MUTED, MUTED }, cont = true }) end
	end
	if d.ELEMENTS then
		B.h("Stranger things")
		for i, e in ipairs(d.ELEMENTS) do
			B.row({ e.name, e.from }, { 0.36, 0.64 }, { item = e.id, pad = 2, anchor = "element:" .. i })
			if e.use then B.row({ "", e.use }, { 0.0, 1.0 }, { colors = { MUTED, MUTED }, cont = true }) end
		end
	end
end

function BUILD.kit()
	Opener("kit")
	Tables()
	local d = D()
	local tell = CanTell()
	B.h("Tools")
	for i, k in ipairs(d.KIT or {}) do
		local n = k.id and Have(k.id) or 0
		B.row({ k.name .. (n > 0 and "  (in your bags)" or ""), k.text }, { 0.36, 0.64 }, { item = k.id, pad = 3, anchor = "kit:" .. i })
	end
	if d.FIND then
		B.h("Find Minerals")
		for _, line in ipairs(d.FIND) do
			B.row({ "\194\183", line }, { 0.05, 0.95 }, { colors = { RED, INK }, pad = 4 })
		end
	end
	if d.GEAR and #d.GEAR > 0 then
		B.h("Gear that helps")
		for i, g in ipairs(d.GEAR) do
			B.row({ g.name, g.text }, { 0.36, 0.64 }, { item = g.id, pad = 3, anchor = "gear:" .. i })
		end
	end
	B.h("Camp blueprints")
	for _, s in ipairs(d.SMELTS) do
		if d.CAMP and d.CAMP[s.item] then
			B.sub(ItemName(s.item) .. ((tell and Knows(s)) and "  (you know it)" or ""), "camp:" .. s.item)
			B.row({ "Needs", Needs(s) }, { 0.20, 0.80 }, { colors = { RED, INK } })
			B.row({ "Learn", Learn(s) }, { 0.20, 0.80 }, { colors = { RED, MUTED } })
			B.row({ "Does", d.CAMP[s.item] }, { 0.20, 0.80 }, { colors = { RED, INK } })
		end
	end
	if d.TALENTS and #d.TALENTS > 0 then
		B.h("Legacy talents")
		for i, t in ipairs(d.TALENTS) do
			B.row({ t[1], t[2] }, { 0.3, 0.7 }, { anchor = "talent:" .. i })
		end
	end
end

function BUILD.tales()
	Opener("tales")
	local d = D()
	B.h("Told in the dark")
	for i, l in ipairs(d.LEGENDS) do
		if i > 1 then B.flourish(0.3) end
		B.sub(l.title, "legend:" .. i)
		B.hand(l.text, 4)
	end
	if d.TALL_TALES and #d.TALL_TALES > 0 then
		B.h("Tall tales", RED)
		B.note("Claims from a single source we couldn't confirm. Kept apart, for the honest.")
		for i, t in ipairs(d.TALL_TALES) do
			B.h(t[1], MUTED, "tale:" .. i)
			B.p(t[2], INK, 13)
		end
	end
	B.gap(6)
	B.note(d.SOURCES)
end

---------------------------------------------------------------------------
-- Search rows, linked names, the footer.

spec.index = function(Add)
	Tables()
	local d = D()
	for _, v in ipairs(d.VEINS) do
		local y = d.YIELD[v.key] or {}
		local zones = Zones(v.key)
		local names = {}
		for i = 1, math.min(8, #zones) do names[#names + 1] = zones[i][2] end
		Add("veins", "vein:" .. v.key, v.name, ("Mining %d. %s %s"):format(v.skill, y.gives or "", table.concat(names, ", ")))
	end
	for _, s in ipairs(d.SMELTS) do
		if d.CAMP and d.CAMP[s.item] then
			Add("kit", "camp:" .. s.item, ItemName(s.item), Needs(s) .. ". " .. d.CAMP[s.item], s.item)
		else
			Add("smelter", "smelt:" .. s.spell, ItemName(s.item), ("Mining %d. %s. %s"):format(s.skill, Needs(s), Learn(s)), s.item)
		end
	end
	for i, g in ipairs(d.GEMS or {}) do Add("gems", "gem:" .. i, g.name, g.from .. " " .. (g.use or ""), g.id) end
	for i, s in ipairs(d.STONES or {}) do Add("gems", "stone:" .. i, s.name, s.from .. " " .. (s.use or ""), s.id) end
	for i, e in ipairs(d.ELEMENTS or {}) do Add("gems", "element:" .. i, e.name, e.from .. " " .. (e.use or ""), e.id) end
	for i, r in ipairs(d.RANKS) do Add("route", "rank:" .. i, r[1] .. " Mining", r[3]) end
	for i, step in ipairs(d.ROUTE) do
		Add("route", "route:" .. i, "Route " .. step[1], (step.A or "") .. " " .. (step.H or "") .. " " .. (step.N or "") .. " " .. (step.note or ""))
	end
	for id, n in pairs(d.NPC) do
		if not Enemy(n[5]) then
			local chapter = (n[7] == "trainer" or n[7] == "supplies") and "route" or "tales"
			Add(chapter, "npc:" .. n[1], n[1] .. " (" .. n[6] .. ")", Person(id))
		end
	end
	for i, k in ipairs(d.KIT or {}) do Add("kit", "kit:" .. i, k.name, k.text, k.id) end
	for i, g in ipairs(d.GEAR or {}) do Add("kit", "gear:" .. i, g.name, g.text, g.id) end
	for i, t in ipairs(d.TALENTS or {}) do Add("kit", "talent:" .. i, t[1], t[2]) end
	for i, f in ipairs(d.FORGES or {}) do Add("smelter", "forge:" .. i, f[1] .. " (forge)", f[2]) end
	for i, t in ipairs(d.TALL_TALES or {}) do Add("tales", "tale:" .. i, t[1], t[2]) end
	for i, l in ipairs(d.LEGENDS) do Add("tales", "legend:" .. i, "Tale: " .. l.title, l.text) end
end

spec.names = function()
	Tables()
	local d = D()
	local list = {}
	for id, name in pairs(d.ITEM) do list[#list + 1] = { name, id } end
	for _, g in ipairs(d.GEMS or {}) do list[#list + 1] = { g.name, g.id } end
	for _, s in ipairs(d.STONES or {}) do list[#list + 1] = { s.name, s.id } end
	for _, e in ipairs(d.ELEMENTS or {}) do if e.id then list[#list + 1] = { e.name, e.id } end end
	for _, k in ipairs(d.KIT or {}) do if k.id then list[#list + 1] = { k.name, k.id } end end
	for _, g in ipairs(d.GEAR or {}) do if g.id then list[#list + 1] = { g.name, g.id } end end
	for id, name in pairs(d.ITEMS or {}) do list[#list + 1] = { name, id } end
	return list
end

spec.status = function()
	local rank, cap = M.Skill()
	local log = Log()
	local skill = rank and ("Mining %d/%d"):format(rank, cap) or "No pick yet"
	local kinds = 0
	for _ in pairs(log and log.veins or {}) do kinds = kinds + 1 end
	return skill, ("%s veins  \194\183  %d kinds"):format(Commas(log and log.total or 0), kinds)
end

spec.onShow = function()
	CheckSkill()
	CheckSmelts()
end
book.build = BUILD

---------------------------------------------------------------------------
-- The doors in.

M.Render, M.Refresh, M.Select, M.Jump, M.Find = book.Render, book.Refresh, book.Select, book.Jump, book.Find
M.Search, M.Toggle, M.Open, M.ResetPosition, M.ApplySettings = book.Search, book.Toggle, book.Open, book.ResetPosition, book.ApplySettings
M.Write = book.Write
M.OnMined, M.OnEvent = OnMined, OnEvent -- for the offline tests

-- For the map pins (MiningMap.lua).
M.DIFF, M.ZoneSide = DIFF, ZoneSide
function M.Vein(key)
	Tables()
	return BY_KEY[key]
end
function M.OreIcon(key)
	local y = D().YIELD[key]
	local id = y and y.ore and y.ore[1]
	local icon = id and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
	return icon or "Interface\\Icons\\INV_Ore_Copper_01"
end

function M.PreviewToast()
	local lines = D().LINES.vein
	local log = Log()
	Book.Toast(book, Fill(lines[math.random(#lines)], { vein = "Tin Vein", ore = "Tin Ore", zone = "Redridge Mountains" }), log and log.dayCount or 1)
end

-- Forget this character's memoir.
function M.Clear()
	local log = Log()
	if not log then return end
	for _, key in ipairs({ "veins", "items", "names", "quality", "zones", "smelted", "known", "trophies", "finds", "entries", "days" }) do
		wipe(log[key])
	end
	log.total, log.dayCount, log.bars = 0, 0, 0
	for _, key in ipairs({ "started", "skillSeen", "rankSeen", "scanned", "decks", "story", "greyDay", "batchDay", "batch",
		"stoneDay", "stoneToday", "findDay" }) do
		log[key] = nil
	end
	book.Refresh()
end

function M.Init()
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL", "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED",
		"NEW_RECIPE_LEARNED", "SPELLS_CHANGED", "TRADE_SKILL_SHOW", "ZONE_CHANGED_NEW_AREA", "LOOT_OPENED" }) do
		pcall(events.RegisterEvent, events, event)
	end
	for _, event in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED" }) do
		if not pcall(events.RegisterUnitEvent, events, event, "player") then
			pcall(events.RegisterEvent, events, event)
		end
	end
	local pending = false
	events:SetScript("OnEvent", function(_, event, ...)
		if event:find("^UNIT_SPELLCAST") or event == "LOOT_OPENED" then
			ns.Try("rock bottom " .. event:lower(), OnEvent, event, ...)
		elseif event == "BAG_UPDATE_DELAYED" or event == "ZONE_CHANGED_NEW_AREA" then
			book.Refresh("seam")
		elseif event == "SKILL_LINES_CHANGED" or event == "CHAT_MSG_SKILL" or event == "PLAYER_ENTERING_WORLD" then
			ns.Try("rock bottom skill", CheckSkill)
			if event == "PLAYER_ENTERING_WORLD" then ns.Try("rock bottom smelts", CheckSmelts, false) end
			book.Refresh("seam")
		elseif not pending and C_Timer then
			pending = true
			C_Timer.After(0.5, function()
				pending = false
				ns.Try("rock bottom smelts", CheckSmelts)
				book.Refresh()
			end)
		end
	end)
end
