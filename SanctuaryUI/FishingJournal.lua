SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.Journal = ns.Journal or {}
local J = ns.Journal

BINDING_NAME_SANCTUARYUIFISHING = "Angler's journal"

-- The angler's journal: a book (Book.lua: the D3 window, the parchment page, the red side tabs,
-- search, the diary and its pop-up) about fishing. The book itself is FishingData.lua; this file
-- writes its chapters, reads where you stand and what you fish, and keeps a per-character diary
-- that writes itself on firsts and milestones. The Cookbook (Cookbook.lua) is its sister.

-- Book.lua arrived with the Cookbook. The game only finds files that existed when it started, so
-- on a /reload straight after that update the engine isn't there yet: say so, and stand down
-- until the restart rather than break the fishing tools.
if not ns.Book then
	local function Restart()
		print("|cffd8b86aSanctuaryUI:|r the journal was updated. Exit the game and start it again to load it (a /reload can't see new files).")
	end
	J.CHAPTERS = {}
	J.Toggle, J.Open, J.Search, J.PrintHeard = Restart, Restart, Restart, Restart
	setmetatable(J, { __index = function() return function() end end })
	return
end

local Book = ns.Book
local INK, RED, MUTED, GREEN, AMBER, GOLD = Book.INK, Book.RED, Book.MUTED, Book.GREEN, Book.AMBER, Book.GOLD
local Readable, Commas, Fill, Clock = Book.Readable, Book.Commas, Book.Fill, Book.Clock
local MySide, Enemy, SIDE_NAME = Book.MySide, Book.Enemy, Book.SIDE_NAME

J.CHAPTERS = {
	{ key = "diary", title = "The Diary", tip = "Your diary, written as you fish: firsts, milestones, and the tally." },
	{ key = "now", title = "Here & Now", tip = "Where you stand: will this water bite, what lives in it, what to do next." },
	{ key = "route", title = "The Road to 300", tip = "Ranks, the levelling route for both factions, and every trainer." },
	{ key = "waters", title = "Waters", tip = "Every zone by the skill its fish need." },
	{ key = "catches", title = "The Catch", tip = "What to catch where, and what it's for. Ticks what you've caught." },
	{ key = "tackle", title = "Tackle", tip = "Poles, lures, hats, fishing food, legacy talents." },
	{ key = "camp", title = "Camp", tip = "Bait & Tackle: the Fish Bowl, Fishing Rack and Fishing Hut." },
	{ key = "extravaganza", title = "The Extravaganza", tip = "Stranglethorn's Sunday fishing race, its prizes, Nat Pagle and the other fishing quests." },
	{ key = "tales", title = "Tales & Lore", tip = "Azeroth's fishing lore and old legends, and rumours we couldn't confirm. Fish responsibly." },
}

local function Opt()
	return ns.DB().journal
end

-- This character's catch log and diary.
local function Log()
	local char = ns.db and ns.db.char
	return char and char.fishing
end
J.Log = Log

local function D() return ns.FishingData end

-- The book. Its chapters (BUILD), search rows (Index) and footer (Status) are set further down.
local spec = {
	key = "fishing",
	frameName = "SanctuaryUIFishingJournal",
	title = "Angler's journal",
	art = "journal",
	opt = Opt,
	log = Log,
	chapters = J.CHAPTERS,
	home = "now",
	live = "now",
	story = function() return D().STORY end,
	words = {
		search = "Search the journal",
		nothing = "Nothing by \"%s\". Maybe it got away.",
		scope = "Search looks at fish, zones, trainers, poles, lures, gear, food, camp objects, quests, prizes, recipes, tall tales and your diary.",
		wet = "This page got wet: ",
		empty = "Empty. Go catch something. Anything. A boot counts. Sort of.",
		paused = "The diary is paused (Options > Professions > Fishing journal).",
		older = "...and %d older entries, pressed between the pages.",
	},
}
local book = Book.New(spec)
J.book = book
local B, Pick = book.B, book.Pick
J.Write, J.Linkify, J.MySide, J.anchors = book.Write, book.Linkify, MySide, book.anchors

---------------------------------------------------------------------------
-- What the client says: your fishing skill, where you are, the time, your lure.

local FISHING_SKILL = 356

local function FishingName()
	local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(7620)
	if not Readable(name) and GetSpellInfo then name = GetSpellInfo(7620) end
	return (Readable(name) and type(name) == "string") and name or (PROFESSIONS_FISHING or "Fishing")
end

-- rank, cap, bonus (pole, lure, food); nil when you haven't learned it (or the client won't say).
function J.Skill()
	return Book.Skill(FISHING_SKILL, 7620, PROFESSIONS_FISHING or "Fishing")
end

-- The zone's entry in the book (a sub-zone with its own band first), and the names.
function J.Where()
	local zone = GetRealZoneText and GetRealZoneText() or (GetZoneText and GetZoneText()) or ""
	local sub = GetSubZoneText and GetSubZoneText() or ""
	if not Readable(zone) then zone = "" end
	if not Readable(sub) then sub = "" end
	local book = D().ZONE_BY_NAME
	local entry = (sub ~= "" and book[sub] and book[sub].sub and book[sub]) or book[zone]
	return entry, zone, sub
end

local function IsNight(hour)
	return hour >= 18 or hour < 6
end

local function IsWinter(month)
	return month and (month >= 10 or month <= 3)
end

-- Fish that won't bite right now: night/day and season.
local function Asleep(key, hour, month)
	if key == "nightfin" then return not IsNight(hour), "bites at night" end
	if key == "sunscale" then return IsNight(hour), "bites by day" end
	if month then
		if key == "squid" then return not IsWinter(month), "cold months" end
		if key == "bass" then return IsWinter(month), "warm months" end
	end
	return false
end

local POLE_IDS
local function PoleIDs()
	if not POLE_IDS then
		POLE_IDS = {}
		for _, pole in ipairs(D().POLES) do POLE_IDS[pole[2]] = true end
	end
	return POLE_IDS
end

-- Minutes left on the lure on your pole, or nil.
function J.Lure()
	if not GetWeaponEnchantInfo or not GetInventoryItemID then return end
	local item = GetInventoryItemID("player", 16)
	if not Readable(item) or not PoleIDs()[item] then return end
	local ok, has, expires = pcall(GetWeaponEnchantInfo)
	if not ok or not Readable(has) or not has or not Readable(expires) then return end
	return math.max(1, math.ceil((expires or 0) / 60000))
end
---------------------------------------------------------------------------
-- The diary: catches, milestones, entries.

local FISH_BY_ID
local function FishByID()
	if not FISH_BY_ID then
		FISH_BY_ID = {}
		for key, fish in pairs(D().FISH) do
			if fish.id then FISH_BY_ID[fish.id] = key end
		end
	end
	return FISH_BY_ID
end

local Today = Book.Today

-- Field notes, for keeping the book honest (tools/fishing_audit.py reads them from the saved
-- variables): per zone (and sub-zone with a band of its own), the skill you fished with when
-- something bit and when it got away; and items the book doesn't know.
local function Field(zone)
	local log = Log()
	if not log or zone == "" then return end
	local field = log.field
	field.zones[zone] = field.zones[zone] or { catches = 0, escapes = 0 }
	return field.zones[zone]
end

local function NoteSkill(kind)
	local entry, zone, sub = J.Where()
	local rank, _, bonus = J.Skill()
	if not rank then return end
	local eff = rank + (bonus or 0)
	-- The sub-zone when it's a band of its own, so Jademir Lake doesn't muddy Feralas.
	local key = (entry and entry.sub and entry[1]) or zone
	local z = Field(key)
	if not z then return end
	if kind == "catch" then
		z.catches = z.catches + 1
		z.minCatch = math.min(z.minCatch or eff, eff)
		z.maxCatch = math.max(z.maxCatch or eff, eff)
	else
		z.escapes = z.escapes + 1
		z.minEscape = math.min(z.minEscape or eff, eff)
		z.maxEscape = math.max(z.maxEscape or eff, eff)
	end
end

local TREASURE = { "Footlocker", "Trunk", "Crate", "Chest", "Lockbox", "Strongbox" }

local function IsTreasure(name)
	for _, word in ipairs(TREASURE) do
		if name:find(word) then return true end
	end
	return false
end

-- One loot slot from a fishing bobber.
local function Record(id, name, count, quality, zone)
	local log = Log()
	if not log then return end
	local lines = D().LINES
	local fields = { fish = name, item = name, zone = zone ~= "" and zone or "these parts" }
	if IsTreasure(name) then
		log.treasure = (log.treasure or 0) + 1
		J.Write(Fill(Pick(lines.treasure, "treasure"), fields))
		return
	end
	if quality == 0 and not FishByID()[id] then
		log.junk = (log.junk or 0) + 1
		local key = zone .. "|" .. Today()
		if not log.junkDays[key] then
			log.junkDays[key] = true
			J.Write(Fill(Pick(lines.junk, "junk"), fields))
		end
		return
	end
	local before = log.total or 0
	local fresh = not log.catches[id]
	local newZone = zone ~= "" and not log.zones[zone]
	log.catches[id] = (log.catches[id] or 0) + count
	log.names[id] = name
	if quality then log.quality[id] = quality end
	if not FishByID()[id] then
		local u = log.field.unknown[id] or { name = name, q = quality, zones = {} }
		u.zones[zone] = (u.zones[zone] or 0) + count
		log.field.unknown[id] = u
	end
	log.total = before + count
	if zone ~= "" then
		log.zones[zone] = log.zones[zone] or {}
		log.zones[zone][id] = (log.zones[zone][id] or 0) + count
	end
	-- A rare find: anything uncommon or better, the Extravaganza's rare fish, a bloated fish.
	-- Rare and up get a line every time; uncommon once per item a day, so an hour at a
	-- Fishing Rack doesn't flood the diary.
	local named = lines.named[name]
	local bloated = name:find("Bloated") ~= nil
	local rarity = (quality and quality >= 2) and math.min(quality, 5) or ((named or bloated) and 3) or nil
	if rarity then
		log.rare = (log.rare or 0) + count
		local trophies = log.trophies
		trophies[#trophies + 1] = { id = id, name = name, q = rarity, t = time(), zone = zone }
		while #trophies > 200 do table.remove(trophies, 1) end
		local key = id .. "|" .. Today()
		if rarity >= 3 or named or bloated or not log.rareDays[key] then
			log.rareDays[key] = true
			local line = named or (bloated and lines.bloated) or Pick(lines.rare[rarity], "rare" .. rarity)
			J.Write(Fill(line, fields), rarity)
		end
	elseif before == 0 then
		J.Write(Fill(lines.first[1], fields))
	elseif fresh then
		local line = lines.special[id] or (name:find("Whimsyfin") and lines.whimsyfin) or Pick(lines.species, "species")
		J.Write(Fill(line, fields))
	end
	for mark, line in pairs(lines.total) do
		if before < mark and log.total >= mark then J.Write(line) end
	end
	-- A first catch somewhere with a story: the diary remembers the story.
	if newZone and before > 0 and D().ZONE_LINES[zone] then
		J.Write(D().ZONE_LINES[zone])
	end
	-- The Extravaganza, once per Sunday afternoon in Stranglethorn.
	local hour, _, weekday = Clock()
	if weekday == 1 and hour >= 13 and hour < 17 and zone == "Stranglethorn Vale" and log.sunday ~= Today() then
		log.sunday = Today()
		J.Write(lines.sunday)
	end
end

local function OnLoot()
	if not IsFishingLoot or not IsFishingLoot() then return end
	NoteSkill("catch")
	local _, zone = J.Where()
	local items = {}
	for i = 1, (GetNumLootItems and GetNumLootItems() or 0) do
		local link = GetLootSlotLink and GetLootSlotLink(i)
		local _, name, count, _, quality = GetLootSlotInfo(i)
		if Readable(link) and Readable(name) and type(link) == "string" then
			local id = tonumber(link:match("item:(%d+)"))
			if id then
				count = Readable(count) and count or 1
				Record(id, name, count, Readable(quality) and quality or 1, zone)
				items[#items + 1] = { id = id, count = count }
			end
		end
	end
	J.Refresh()
	-- The fishing tools (Fishing.lua): the session's tally, then the loot itself.
	if ns.Fishing and ns.Fishing.OnCatch then ns.Try("fishing catch", ns.Fishing.OnCatch, items) end
	if ns.Fishing and ns.Fishing.AutoLoot then ns.Try("fishing loot", ns.Fishing.AutoLoot) end
end

-- Skill and rank milestones. The first look on a character only remembers where you are.
local function CheckSkill()
	local log = Log()
	if not log then return end
	local rank, cap = J.Skill()
	if not rank then return end
	local lines = D().LINES
	if not log.started then
		log.started = true
		log.skillSeen, log.rankSeen = rank, cap
		if rank > 1 then
			J.Write(("Opened this journal at Fishing %d. The earlier diaries were lost at sea."):format(rank))
		end
		return
	end
	if rank > (log.skillSeen or 0) then
		for mark = 25, 300, 25 do
			if (log.skillSeen or 0) < mark and rank >= mark then
				J.Write(Fill(lines.skill[mark] or lines.skill.other, { skill = mark }))
			end
		end
		log.skillSeen = rank
	end
	if cap > (log.rankSeen or 0) then
		if lines.rank[cap] and (log.rankSeen or 0) > 0 then J.Write(lines.rank[cap]) end
		log.rankSeen = cap
	end
end

local escapes = {} -- this session, by zone

-- What the game says while you fish. The escape line ("Your fish got away!") may come as a red
-- error, a yellow notice or a system line depending on the client, so all three are heard and
-- the last few kept for /sanctuary fish log. Only lines heard while a Fishing cast runs (or just
-- after) count, so another "escaped" elsewhere doesn't.
local fishingUntil = 0
local heard = {} -- { at, event, text }, newest last
local lastEscape = 0

local function Fishing()
	return GetTime() < fishingUntil
end

local function OnCast(event, unit, _, spellID)
	if unit ~= "player" or not Readable(spellID) then return end
	local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
	if not Readable(name) and GetSpellInfo then name = GetSpellInfo(spellID) end
	if name ~= FishingName() then return end
	if event == "UNIT_SPELLCAST_CHANNEL_START" then
		fishingUntil = GetTime() + 40
	else
		fishingUntil = GetTime() + 3
	end
end

local function IsLine(message, key, fallback)
	if message == _G[key] then return true end
	local lower = message:lower()
	for _, word in ipairs(fallback) do
		if lower:find(word, 1, true) then return true end
	end
	return false
end

local function OnMessage(event, ...)
	local a, b = ...
	-- UI_*_MESSAGE: (type, text); CHAT_MSG_SYSTEM: (text, sender, ...).
	local message = event == "CHAT_MSG_SYSTEM" and a or (type(b) == "string" and b or a)
	if not Readable(message) or type(message) ~= "string" then return end
	local lower = message:lower()
	if not Fishing() and not lower:find("fish", 1, true) then return end
	heard[#heard + 1] = { at = GetTime(), event = event, text = message }
	while #heard > 12 do table.remove(heard, 1) end
	local log = Log()
	if not log then return end
	if IsLine(message, "ERR_FISH_ESCAPED", { "got away", "escaped" }) then
		-- One escape, however many channels repeat it.
		if GetTime() - lastEscape < 1 then return end
		lastEscape = GetTime()
		log.escapes = (log.escapes or 0) + 1
		NoteSkill("escape")
		if ns.Fishing and ns.Fishing.OnEscape then ns.Try("fishing escape", ns.Fishing.OnEscape) end
		local _, zone = J.Where()
		escapes[zone] = (escapes[zone] or 0) + 1
		if escapes[zone] == 10 then
			J.Write(Fill(D().LINES.escapes, { zone = zone }))
		end
		J.Refresh()
	elseif IsLine(message, "ERR_FISH_NOT_HOOKED", { "no fish are hooked", "not hooked" }) then
		log.missed = (log.missed or 0) + 1
	end
end

-- /sanctuary fish log: what the game said while you fished.
function J.PrintHeard()
	ns.Print(("Angler's journal: %d escapes counted on this character; this session %s."):format(Log() and Log().escapes or 0, Fishing() and "fishing now" or "not fishing"))
	if #heard == 0 then
		ns.Print("Nothing heard while fishing yet. Cast, let one get away, then try again.")
	end
	for _, h in ipairs(heard) do
		ns.Print(("  %.0fs ago, %s: %s"):format(GetTime() - h.at, h.event, h.text))
	end
end
---------------------------------------------------------------------------
-- Factions. Your side reads first and plain; the other side's things are faded and say so.

-- A line about the other side's thing, the same one each time for the same name.
local function EnemyLine(side, name)
	local list = D().ENEMY[side]
	local n = 0
	for i = 1, #name do n = n + name:byte(i) end
	return list[n % #list + 1]
end

-- { text, side } parts: yours and the neutral ones, joined. With no faction known, all of
-- them, each labelled.
local function Parts(list)
	if type(list) == "string" then return list end
	local mine, out = MySide(), {}
	for _, part in ipairs(list) do
		if not mine then
			out[#out + 1] = part[2] == "N" and part[1] or ("%s (%s)"):format(part[1], SIDE_NAME[part[2]])
		elseif part[2] == "N" or part[2] == mine then
			out[#out + 1] = part[1]
		end
	end
	if #out == 0 then
		local side = list[1] and list[1][2]
		return side and EnemyLine(side, list[1][1]) or ""
	end
	return table.concat(out, "; ")
end

-- A zone's notes for you: everyone's, then your side's.
local function ZoneNote(z)
	local mine = MySide()
	local parts = {}
	if z[5] then parts[#parts + 1] = z[5] end
	if mine and z[mine] then parts[#parts + 1] = z[mine] end
	if not mine then
		if z.A then parts[#parts + 1] = "Alliance: " .. z.A end
		if z.H then parts[#parts + 1] = "Horde: " .. z.H end
	end
	return table.concat(parts, " ")
end

-- Where you can stay in a zone: your faction's town, or a neutral one.
local function ZoneHub(z)
	local hub = z.hub
	if not hub then return end
	local mine = MySide()
	local list = {}
	if mine and hub[mine] then list[#list + 1] = hub[mine] end
	if hub.N then list[#list + 1] = hub.N .. " (neutral)" end
	if not mine then
		if hub.A then list[#list + 1] = hub.A .. " (Alliance)" end
		if hub.H then list[#list + 1] = hub.H .. " (Horde)" end
	end
	return #list > 0 and table.concat(list, ", ") or nil
end

local function Opener(key)
	B.opener(D().OPENERS, key)
end

---------------------------------------------------------------------------
-- Chapters.

local BUILD = {}
local BAND_NAMES = {
	[25] = "The kiddie pools (25)",
	[75] = "Canals and easy coasts (75)",
	[150] = "Lakes with opinions (150)",
	[225] = "Marsh, jungle and strand (225)",
	[300] = "The serious waters (300)",
	[425] = "Here be lobsters (425)",
}

local function Effective()
	local rank, cap, bonus = J.Skill()
	if not rank then return end
	return rank + (bonus or 0), rank, cap, bonus or 0
end

local function Caught(id)
	local log = Log()
	return log and id and log.catches[id] or 0
end

---------------------------------------------------------------------------
-- Where to fish: for your skill, and for each fish.

local function Hex(c)
	return ("ff%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255)
end

-- How a water treats your skill: "open" (nothing gets away), "some" (some get away), "shut"
-- (nothing bites yet); nil with no skill or no band.
local function Reach(band, eff)
	if not band or not eff then return end
	if eff >= band then return "open" end
	if eff >= band - D().ESCAPE_GAP then return "some" end
	return "shut"
end
J.Reach = Reach
local REACH_COLOR = { open = GREEN, some = AMBER, shut = MUTED }

local function Has(list, key)
	for _, k in ipairs(list or {}) do
		if k == key then return true end
	end
end

-- Where a fish bites, as { z = zone entry, how = "spot" | "water" | "school" }: spot where the
-- book names it, water where its band's inland or coastal fish include it, school where its
-- band's schools may turn up (lakes and rivers for sagefish, the coast for the rest). Named
-- spots first, then by skill.
function J.WhereFish(key)
	local d, out, seen = D(), {}, {}
	local function Put(z, how)
		if not seen[z[1]] then
			seen[z[1]] = true
			out[#out + 1] = { z = z, how = how }
		end
	end
	for _, z in ipairs(d.ZONES) do
		if Has(z[4], key) then Put(z, "spot") end
	end
	for _, z in ipairs(d.ZONES) do
		local band = z[2] and d.BANDS[z[2]]
		if band and not z.sub and not d.DUNGEONS[z[1]] then
			if Has(band.inland, key) or (z[3] and Has(band.coast, key)) then
				Put(z, "water")
			elseif Has(band.pools, key) and not d.CAPITALS[z[1]] then
				if (d.SCHOOL_WATER[key] or "coast") == "inland" or z[3] then Put(z, "school") end
			end
		end
	end
	local rank = { spot = 1, water = 2, school = 3 }
	table.sort(out, function(a, b)
		if rank[a.how] ~= rank[b.how] then return rank[a.how] < rank[b.how] end
		if (a.z[2] or 999) ~= (b.z[2] or 999) then return (a.z[2] or 999) < (b.z[2] or 999) end
		return a.z[1] < b.z[1]
	end)
	return out
end

-- The waters for your skill: best = the highest band where nothing gets away, next = the band
-- above it, where some still do. Your side's and neutral zones only, no dungeons or sub-zones;
-- the other side's land only when nothing else is left. Each a list of zone entries.
function J.BestWaters(eff)
	local d = D()
	local function Fits(z, enemyOK)
		return z[2] and not z.sub and not d.DUNGEONS[z[1]] and (enemyOK or not (z.side and Enemy(z.side)))
	end
	local bestBand, nextBand
	for _, z in ipairs(d.ZONES) do
		if Fits(z, false) then
			if z[2] <= eff and (not bestBand or z[2] > bestBand) then bestBand = z[2] end
			if z[2] > eff and (not nextBand or z[2] < nextBand) then nextBand = z[2] end
		end
	end
	local best, nxt = {}, {}
	for _, z in ipairs(d.ZONES) do
		if Fits(z, false) and z[2] == bestBand then best[#best + 1] = z end
		if Fits(z, false) and z[2] == nextBand and Reach(z[2], eff) == "some" then nxt[#nxt + 1] = z end
	end
	return best, bestBand, nxt, nextBand
end

-- Zone names in one line, each coloured by how its water treats your skill.
local function ZoneLine(list, eff)
	local parts = {}
	for _, w in ipairs(list) do
		local z = w.z or w
		local reach = Reach(z[2], eff)
		local enemy = z.side and Enemy(z.side)
		local name = z[1] .. (enemy and (" (%s)"):format(SIDE_NAME[z.side]) or "")
		local c = enemy and MUTED or (reach and REACH_COLOR[reach]) or INK
		parts[#parts + 1] = ("|c%s%s|r"):format(Hex(c), name)
	end
	return table.concat(parts, ", ")
end

-- The "Where to fish now" block: Here & Now and Waters.
local function WhereNow(eff)
	B.h("Where to fish now")
	local best, bestBand, nxt, nextBand = J.BestWaters(eff)
	local _, here = J.Where()
	local function Row(z, reason)
		local hub = ZoneHub(z)
		B.row({ z[1] .. (z[1] == here and "  (you)" or ""), reason .. (reason ~= "" and hub and " " or "") .. (hub and ("Stay: " .. hub .. ".") or "") },
			{ 0.36, 0.64 }, { colors = { z[1] == here and GOLD or INK, MUTED } })
	end
	-- A zone's first sentence: usually where its water is. The rest is in Waters.
	local function Brief(z)
		local note = z[5] or ""
		return note:match("^(.-[%.!?])%s") or note
	end
	if #best > 0 then
		B.p(("Nothing gets away here at %d (they open at %d):"):format(eff, bestBand), GREEN, 12.5)
		for _, z in ipairs(best) do Row(z, Brief(z)) end
	end
	if #nxt > 0 then
		B.p(("Next, at %d (some get away until then, you're %d short):"):format(nextBand, nextBand - eff), AMBER, 12.5)
		for _, z in ipairs(nxt) do Row(z, Brief(z)) end
	end
	if #best == 0 and #nxt == 0 then
		B.p("Nothing on your side of the map bites for you yet. Any starting lake will.", MUTED, 12.5)
		return
	end
	local list = {}
	for _, z in ipairs(best) do list[#list + 1] = { z = z } end
	for _, z in ipairs(nxt) do list[#list + 1] = { z = z } end
	B.row({ "", "Show these on the world map" }, { 0.0, 1.0 }, {
		colors = { MUTED, GOLD }, tip = "Opens the world map with these zones lit up: green, nothing gets away; amber, some do.",
		onClick = function() J.ShowOnMap("Where to fish at " .. eff, list) end,
	})
end

function BUILD.diary()
	local log = Log()
	if not log then return end
	B.h("The tally")
	local species = 0
	for _ in pairs(log.catches) do species = species + 1 end
	B.kv("Fish caught", Commas(log.total))
	B.kv("Kinds", Commas(species))
	B.kv("Got away", Commas(log.escapes or 0) .. ((log.escapes or 0) > 0 and "  (they talk about you)" or ""))
	B.kv("Treasure", Commas(log.treasure or 0))
	B.kv("Rare finds", Commas(log.rare or 0) .. ((log.rare or 0) > 0 and "  (see Trophies)" or ""))
	B.kv("Junk", Commas(log.junk or 0) .. ((log.junk or 0) > 9 and "  (a collector)" or ""))
	local best, bestN = nil, 0
	for id, n in pairs(log.catches) do
		if n > bestN then best, bestN = id, n end
	end
	if best then B.kv("Most caught", ("%s (%s)"):format(log.names[best] or ("item " .. best), Commas(bestN))) end
	B.h("Trophies")
	local trophies = log.trophies
	if #trophies == 0 then
		B.hand("No trophies yet. The water is saving them for later.")
	else
		for i = #trophies, math.max(1, #trophies - 29), -1 do
			local t = trophies[i]
			B.row({ t.name, t.zone ~= "" and t.zone or "somewhere wet", date("%d %b, %H:%M", t.t) },
				{ 0.44, 0.34, 0.22 }, { item = t.id, colors = { INK, MUTED, MUTED } })
		end
		if #trophies > 30 then
			B.note(("...and %d older trophies on the wall."):format(#trophies - 30))
		end
	end
	B.entries()
end

-- Trainers in a zone: yours and neutral ones first, the other side's after.
local function Trainers(where)
	local list = {}
	for _, t in ipairs(D().TRAINERS) do
		if t[2] == where then list[#list + 1] = t end
	end
	table.sort(list, function(a, b)
		local ea, eb = Enemy(a[6]), Enemy(b[6])
		if ea ~= eb then return eb end
		return a[1] < b[1]
	end)
	return list
end

local function TrainerRow(t, withZone)
	local where = withZone and ("%s, %s"):format(t[3], t[2]) or t[3]
	local enemy = Enemy(t[6])
	local name = t[1] .. (enemy and (" (%s)"):format(SIDE_NAME[t[6]]) or (t[6] == "N" and " (both)" or ""))
	B.row({ name, where, ("%.1f, %.1f"):format(t[4], t[5]) }, { 0.38, 0.44, 0.18 }, { dim = enemy, anchor = "trainer:" .. t[1] })
end

function BUILD.now()
	local entry, zone, sub = J.Where()
	local eff, rank, cap, bonus = Effective()
	local hour, minute, weekday, month = Clock()
	local mine = MySide()
	B.h(sub ~= "" and sub ~= zone and (zone .. ": " .. sub) or (zone ~= "" and zone or "Somewhere wet"))
	-- Whose land, and where you can sleep.
	local home = entry and entry.side or (D().ZONE_BY_NAME[zone] and D().ZONE_BY_NAME[zone].side)
	if home and Enemy(home) then
		B.p(D().ENEMY.land[home], RED, 13)
	end
	local zoneEntry = D().ZONE_BY_NAME[zone]
	local hub = zoneEntry and ZoneHub(zoneEntry)
	if hub then B.p("Friendly roof: " .. hub .. ".", MUTED, 12.5) end
	if not rank then
		B.hand("You don't fish yet. Any fishing trainer will sell you the secret: stand still, look hopeful.")
	else
		local line = ("Fishing %d of %d"):format(rank, cap)
		if bonus > 0 then line = line .. (", +%d from pole, lure and food: %d in all"):format(bonus, eff) end
		B.p(line .. ".")
	end
	local band = entry and entry[2]
	if not entry then
		B.p("This water isn't in the book. Fish it, and your own catches below become the book.", MUTED)
	elseif not band then
		B.p("This water's skill isn't pinned down yet. Watch how often they get away.", AMBER)
	elseif rank then
		local floor = band - D().ESCAPE_GAP
		if eff >= band + 50 then
			B.p(("Nothing gets away here (%d). You've outgrown this pond."):format(band), GREEN)
		elseif eff >= band then
			B.p(("Nothing gets away here (%d). Every bite is yours."):format(band), GREEN)
		elseif eff >= floor then
			B.p(("Some will get away until %d: you're %d short."):format(band, band - eff), AMBER)
		else
			B.p(("Nothing bites below %d here. The fish can smell your inexperience."):format(floor), RED)
		end
	end
	if rank then
		local lure = J.Lure()
		if lure then
			B.p(("Lure on the pole: %d min left."):format(lure), GREEN, 12.5)
		elseif band and eff < band then
			local best
			for _, l in ipairs(D().LURES) do
				if l[4] <= rank and (not best or l[3] > best[3]) then best = l end
			end
			if best then
				B.p(("No lure on. Best you can use: %s (+%d), from %s."):format(best[1], best[3], Parts(best[5])), MUTED, 12.5)
			end
		end
		-- Next step on the road.
		if rank >= cap and cap < 300 then
			for _, r in ipairs(D().RANKS) do
				if r[2] > cap then
					local how = r[3]
					if r[2] == 150 then how = "Any fishing trainer of your side, or a neutral one, at Fishing 50 and level 10." end
					B.p(("Capped at %d. Next: %s. %s"):format(cap, r[1], how), RED, 12.5)
					break
				end
			end
		elseif cap == 150 and rank >= 125 then
			B.p(("At 125 you can read Expert Fishing (Old Man Heming, Booty Bay%s). Buy it before you cap."):format(mine == "H" and ": boat from Ratchet or Grom'gol" or mine == "A" and ": ride down from Duskwood or boat from Ratchet" or ""), MUTED, 12.5)
		end
	end
	if entry then
		local note = ZoneNote(entry)
		if note ~= "" then B.note(note) end
	end

	if eff then WhereNow(eff) end

	-- What bites.
	if entry and band then
		B.h("Biting here")
		local seen, list = {}, {}
		local function Add(keys, kind)
			for _, key in ipairs(keys or {}) do
				if not seen[key] then
					seen[key] = true
					list[#list + 1] = { key, kind }
				end
			end
		end
		local bands = D().BANDS[band] or {}
		Add(entry[4], "local")
		Add(bands.inland, "inland")
		if entry[3] then Add(bands.coast, "coast") end
		Add(bands.pools, "schools")
		for _, pair in ipairs(list) do
			local key, kind = pair[1], pair[2]
			local fish = D().FISH[key]
			local asleep, when = Asleep(key, hour, month)
			local n = Caught(fish.id)
			local status = kind
			if fish.where:find("quest only") then
				status = "only on Nat Pagle's quest"
			elseif key == "tastyfish" then
				status = "only during the Extravaganza"
			end
			if when then status = status .. ", " .. when end
			if asleep then status = status .. " (not now)" end
			if n > 0 then status = status .. (", caught %s"):format(Commas(n)) end
			B.row({ fish.name, status }, { 0.55, 0.45 }, { item = fish.id, colors = { asleep and MUTED or INK, MUTED } })
		end
		B.note(("Realm time %02d:%02d: %s."):format(hour, minute, IsNight(hour) and "night, Nightfin bite and Sunscale sleep" or "day, Sunscale bite and Nightfin sleep"))
	end

	-- Your own record here.
	local log = Log()
	local caught = log and zone ~= "" and log.zones[zone]
	if caught and next(caught) then
		B.h("Your catches here")
		local rows = {}
		for id, n in pairs(caught) do rows[#rows + 1] = { id, n } end
		table.sort(rows, function(a, b) return a[2] > b[2] end)
		for _, r in ipairs(rows) do
			B.row({ log.names[r[1]] or ("item " .. r[1]), Commas(r[2]) }, { 0.75, 0.25 }, { item = r[1] })
		end
	end
	if escapes[zone] and escapes[zone] > 0 then
		B.note(("Got away here this session: %d."):format(escapes[zone]))
	end

	local trainers = Trainers(zone)
	if #trainers > 0 then
		B.h("Trainers here")
		local yours = 0
		for _, t in ipairs(trainers) do
			TrainerRow(t)
			if not Enemy(t[6]) then yours = yours + 1 end
		end
		if yours == 0 then
			B.note("None of them will teach you. They might not let you finish the question.")
		end
	end
	if weekday == 1 and hour >= 13 and hour < 17 then
		B.h("It's Sunday afternoon", GOLD)
		B.p("The Stranglethorn Extravaganza runs 2 to 4 PM region time. Booty Bay is neutral: both factions race. Forty Tastyfish. Go.", GOLD)
	end
end

function BUILD.route()
	Opener("route")
	local mine = MySide()
	B.h("Ranks")
	for i, r in ipairs(D().RANKS) do
		B.row({ ("%s (to %d)"):format(r[1], r[2]), r[3] }, { 0.3, 0.7 }, { item = r.item, anchor = "rank:" .. i })
	end
	B.h(mine and ("The route, %s"):format(SIDE_NAME[mine]) or "The route")
	for _, step in ipairs(D().ROUTE) do
		if mine then
			B.row({ step[1], mine == "H" and step[3] or step[2] }, { 0.2, 0.8 }, { colors = { RED, INK }, pad = 2 })
		else
			B.row({ step[1], "Alliance: " .. step[2] }, { 0.2, 0.8 }, { colors = { RED, INK }, pad = 2 })
			B.row({ "", "Horde: " .. step[3] }, { 0.2, 0.8 }, { colors = { RED, INK }, pad = 2, cont = true })
		end
		B.row({ "", step[4] }, { 0.2, 0.8 }, { colors = { MUTED, MUTED }, cont = true })
	end
	B.h("Trainers who'll teach you")
	for _, t in ipairs(D().TRAINERS) do
		if t[6] == "N" then TrainerRow(t, true) end
	end
	for _, t in ipairs(D().TRAINERS) do
		if t[6] == mine or not mine and t[6] ~= "N" then TrainerRow(t, true) end
	end
	if mine then
		local other, n = mine == "H" and "A" or "H", 0
		for _, t in ipairs(D().TRAINERS) do
			if t[6] == other then n = n + 1 end
		end
		B.note(("And %d %s trainers, who'd sooner teach a murloc."):format(n, SIDE_NAME[other]))
	end
end

function BUILD.waters()
	Opener("waters")
	local eff, rank = Effective()
	local _, here = J.Where()
	B.note(("A zone's number is where nothing gets away; %d below it, nothing bites. Lures and poles count."):format(D().ESCAPE_GAP))
	if rank then
		B.note(("You fish at %d. Green: all yours. Ink: some escape. Grey: not yet. Faded: the other faction's land."):format(eff))
	end
	if eff then WhereNow(eff) end
	local function Zone(z, band)
		local color = INK
		if rank and band then
			color = eff >= band and GREEN or (eff >= band - D().ESCAPE_GAP and INK or MUTED)
		end
		local enemy = z.side and Enemy(z.side)
		local name = z[1] .. (z.sub and " *" or "") .. (enemy and (" (%s)"):format(SIDE_NAME[z.side]) or "") .. (z[1] == here and "  (you)" or "")
		local note = ZoneNote(z)
		local hub = ZoneHub(z)
		if hub then note = (note ~= "" and note .. " " or "") .. "Stay: " .. hub .. "." end
		B.row({ name, note }, { 0.36, 0.64 }, { colors = { z[1] == here and GOLD or color, MUTED }, dim = enemy and z[1] ~= here, anchor = "zone:" .. z[1] })
	end
	for _, band in ipairs({ 25, 75, 150, 225, 300, 425 }) do
		B.h(BAND_NAMES[band])
		for _, z in ipairs(D().ZONES) do
			if z[2] == band then Zone(z, band) end
		end
	end
	B.h("Not yet charted")
	for _, z in ipairs(D().ZONES) do
		if not z[2] then Zone(z) end
	end
	B.note("* a part of a zone with its own number.")
end

function BUILD.catches()
	Opener("catches")
	local log = Log()
	local have, total = 0, 0
	for _, key in ipairs(D().FISH_ORDER) do
		local fish = D().FISH[key]
		total = total + 1
		if Caught(fish.id) > 0 then have = have + 1 end
	end
	B.note(("Ticked: caught on this character (%d of %d). Hover a fish for its card, shift-click to link it. Zones: green, nothing gets away for you; amber, some do; grey, not yet; faded, the other side's land."):format(have, total))
	B.h("Fish")
	for _, key in ipairs(D().FISH_ORDER) do
		local fish = D().FISH[key]
		local n = Caught(fish.id)
		local name = (n > 0 and "|TInterface\\RaidFrame\\ReadyCheck-Ready:13:13:0:-1|t " or "") .. fish.name .. (fish.forever and "  |cff9a6a0e(new)|r" or "")
		B.row({ name, fish.where }, { 0.42, 0.58 }, { item = fish.id, pad = 2, colors = { INK, MUTED }, anchor = "fish:" .. key })
		B.row({ "", fish.use .. ". " .. fish.quip }, { 0.0, 1.0 }, { colors = { MUTED, MUTED }, cont = true })
		local where = J.WhereFish(key)
		if #where > 0 then
			local spots, waters, schools = {}, {}, {}
			for _, w in ipairs(where) do
				local list = w.how == "spot" and spots or w.how == "water" and waters or schools
				list[#list + 1] = w
			end
			local eff = Effective()
			local lines = {}
			if #spots > 0 then lines[#lines + 1] = "Known for it: " .. ZoneLine(spots, eff) end
			if #waters > 0 then lines[#lines + 1] = (#spots > 0 and "Also in: " or "Bites in: ") .. ZoneLine(waters, eff) end
			if #schools > 0 then lines[#lines + 1] = "Schools may turn up in: " .. ZoneLine(schools, eff) end
			B.row({ "", table.concat(lines, "\n") }, { 0.0, 1.0 }, { colors = { MUTED, INK }, cont = true })
			B.row({ "", "Show where it bites on the world map" }, { 0.0, 1.0 }, {
				colors = { MUTED, GOLD }, cont = true,
				tip = "Opens the world map with these zones lit up: green, nothing gets away for you; amber, some do; grey, not yet.",
				onClick = function() J.ShowOnMap(fish.name, where, fish.id) end,
			})
		end
	end
	B.h("Not fish, still caught")
	for i, o in ipairs(D().OTHER_CATCHES) do
		B.row({ o.name, o.text }, { 0.32, 0.68 }, { anchor = "other:" .. i })
	end
	B.h("Cook it")
	B.row({ "", "What each fish becomes, and what the dish is good for, is in the Cookbook." }, { 0.0, 1.0 }, {
		colors = { MUTED, GOLD }, tip = "Open the Cookbook at From the Water",
		onClick = function() if ns.Cookbook and ns.Cookbook.Open then ns.Cookbook.Open("catch") end end,
	})
	for i, r in ipairs(D().RECIPES) do
		local own = Parts(r[2])
		local enemy = true
		for _, part in ipairs(r[2]) do
			if not Enemy(part[2]) then enemy = false end
		end
		B.row({ r[1], own }, { 0.42, 0.58 }, { dim = enemy, anchor = "recipe:" .. i })
	end
	if log and next(log.catches) then
		local extra = {}
		local known = FishByID()
		for id, n in pairs(log.catches) do
			if not known[id] then extra[#extra + 1] = { id, n } end
		end
		if #extra > 0 then
			table.sort(extra, function(a, b) return a[2] > b[2] end)
			B.h("Also in your nets")
			for _, r in ipairs(extra) do
				B.row({ log.names[r[1]] or ("item " .. r[1]), Commas(r[2]) }, { 0.75, 0.25 }, { item = r[1] })
			end
		end
	end
end

function BUILD.tackle()
	Opener("tackle")
	B.note("Your skill plus every bonus is what the water sees: an Arcanite pole and an Attractor take 300 to 435.")
	local cols = { 0.36, 0.07, 0.1, 0.47 }
	B.h("Poles")
	B.row({ "Pole", "+", "Needs", "Where" }, cols, { head = true })
	for i, p in ipairs(D().POLES) do
		local enemy = Enemy(p.side)
		local where = enemy and (EnemyLine(p.side, p[1]) .. " (" .. p[5] .. ")") or p[5]
		if p.side and not MySide() then where = SIDE_NAME[p.side] .. ": " .. where end
		B.row({ p[1], p[3] > 0 and tostring(p[3]) or "", tostring(p[4]), where }, cols, { item = p[2], dim = enemy, anchor = "pole:" .. i })
	end
	B.h("Lures (10 min)")
	B.row({ "Lure", "+", "Needs", "Where" }, cols, { head = true })
	for i, l in ipairs(D().LURES) do
		B.row({ l[1], tostring(l[3]), tostring(l[4]), Parts(l[5]) }, cols, { item = l[2], anchor = "lure:" .. i })
	end
	B.h("Worn and carried")
	for i, g in ipairs(D().GEAR) do
		B.row({ g[1], g[3] > 0 and ("+" .. g[3]) or "", g[4] }, { 0.36, 0.07, 0.57 }, { item = g[2], anchor = "gear:" .. i })
	end
	B.h("Fishing food (15 min)")
	B.row({ "Food", "+", "Level", "" }, { 0.5, 0.1, 0.12, 0.28 }, { head = true })
	for i, f in ipairs(D().FOOD) do
		B.row({ f[1], tostring(f[3]), tostring(f[4]), "" }, { 0.5, 0.1, 0.12, 0.28 }, { item = f[2], anchor = "food:" .. i })
	end
	B.note("Forever made these fish dishes into fishing food. Eat before you cast.")
	B.h("Legacy talents")
	for i, t in ipairs(D().TALENTS) do
		B.row({ t[1], t[2] }, { 0.3, 0.7 }, { anchor = "talent:" .. i })
	end
end

function BUILD.camp()
	Opener("camp")
	for _, rule in ipairs(D().CAMP_RULES) do
		B.row({ "\194\183", rule }, { 0.05, 0.95 }, { colors = { RED, INK } })
	end
	for i, c in ipairs(D().CAMP) do
		B.h(("%s (skill %d)"):format(c[1], c[3]), nil, "camp:" .. i)
		B.row({ "Makes", c[1] }, { 0.24, 0.76 }, { item = c[2], colors = { RED, INK } })
		B.row({ "Needs", c[4] }, { 0.24, 0.76 }, { colors = { RED, INK } })
		B.row({ "Does", c[5] }, { 0.24, 0.76 }, { colors = { RED, INK } })
		B.row({ "Learn", c[6] }, { 0.24, 0.76 }, { colors = { RED, MUTED } })
	end
	B.flourish()
	B.hand("Put the Rack down, light the fire, cast. Feel the uncommon fish arrive. Feel nothing else; it's cold.")
end

local function NextSunday()
	local hour, _, weekday = Clock()
	if not weekday then return end
	if weekday == 1 and hour >= 14 and hour < 16 then return "on now (if your realm keeps region time)" end
	if weekday == 1 and hour < 14 then return "today, 2 PM" end
	local days = (8 - weekday) % 7
	return days == 1 and "tomorrow, 2 PM" or ("in %d days, Sunday 2 PM"):format(days)
end

function BUILD.extravaganza()
	Opener("extravaganza")
	local E = D().EXTRAVAGANZA
	local mine = MySide()
	local nextOne = NextSunday()
	if nextOne then B.p("Next one: " .. nextOne .. ".", GOLD) end
	B.kv("When", E.when)
	B.kv("Getting there", mine == "H" and "Zeppelin to Grom'gol, then ride south; or the boat from Ratchet." or mine == "A" and "Ride south from Duskwood through Stranglethorn, or the boat from Ratchet." or "Booty Bay, at Stranglethorn's southern tip. Neutral town.")
	B.kv("How", E.how)
	B.kv("Winning", E.win)
	B.kv("Losing", E.casual)
	B.kv("Rare fish", E.rare)
	B.kv("Etiquette", "Booty Bay is neutral, the pools along the coast are not. Expect company of the other colour.")
	B.h("Jang's prizes (one coin each)")
	for i, c in ipairs(E.coin) do
		B.row({ c[1], c[3] }, { 0.4, 0.6 }, { item = c[2], anchor = "coin:" .. i })
	end
	B.h("Fishing quests")
	-- Yours and everyone's first, then the other side's, each in the book's order.
	local quests = {}
	for pass = 1, 2 do
		for _, q in ipairs(D().QUESTS) do
			if (pass == 2) == Enemy(q.side) then quests[#quests + 1] = q end
		end
	end
	for _, q in ipairs(quests) do
		local enemy = Enemy(q.side)
		local text = ("%s, %s. %s"):format(q[2], q[3], q[4])
		if enemy then
			text = EnemyLine(q.side, q[1]) .. " " .. text
		elseif q.side and not mine then
			text = SIDE_NAME[q.side] .. ": " .. text
		end
		B.row({ q[1], text }, { 0.36, 0.64 }, { dim = enemy, anchor = "quest:" .. q[1] })
	end
	B.h("Nat Pagle's four fish")
	for _, key in ipairs(D().NAT_PAGLE) do
		local fish = D().FISH[key]
		B.row({ fish.name, fish.where }, { 0.45, 0.55 }, { item = fish.id, anchor = "nat:" .. key })
	end
end

function BUILD.tales()
	Opener("tales")
	-- The old legends, as diary entries: stories told at the inn.
	B.h("Old legends")
	for i, l in ipairs(D().LEGENDS) do
		if i > 1 then B.flourish(0.3) end
		B.sub(l.title, "legend:" .. i)
		B.hand(l.text, 4)
	end
	B.h("Tall tales", RED)
	B.note("Claims from a single source we couldn't confirm. Kept apart, for the honest.")
	for i, t in ipairs(D().TALL_TALES) do
		B.h(t[1], MUTED, "tale:" .. i)
		B.p(t[2], INK, 13)
	end
	B.gap(6)
	B.note("Sources: wow-professions.com, warcrafttavern.com, method.gg, wow.gg, warcraft.wiki.gg, Wowhead's Forever database (November 2026, patch 1.60.1). Beta-era numbers may still move.")
end
---------------------------------------------------------------------------
-- Search: every row the book can find, with the chapter and the row (anchor) it lives on. The
-- engine adds the chapters themselves and the diary's entries.

local function Index(Add)
	local d = D()
	for _, key in ipairs(d.FISH_ORDER) do
		local f = d.FISH[key]
		local zones = {}
		for _, w in ipairs(J.WhereFish(key)) do zones[#zones + 1] = w.z[1] end
		Add("catches", "fish:" .. key, f.name, ("%s. %s. %s. %s"):format(f.where, f.use, f.quip, table.concat(zones, ", ")), f.id)
	end
	for i, o in ipairs(d.OTHER_CATCHES) do Add("catches", "other:" .. i, o.name, o.text) end
	for i, r in ipairs(d.RECIPES) do Add("catches", "recipe:" .. i, r[1], Parts(r[2])) end
	for _, z in ipairs(d.ZONES) do
		Add("waters", "zone:" .. z[1], z[1], ZoneNote(z) .. " " .. (ZoneHub(z) or "") .. (z[2] and (" skill " .. z[2]) or ""))
	end
	for i, r in ipairs(d.RANKS) do Add("route", "rank:" .. i, r[1] .. " Fishing", r[3], r.item) end
	local mine = MySide()
	for _, t in ipairs(d.TRAINERS) do
		if t[6] == "N" or not mine or t[6] == mine then
			Add("route", "trainer:" .. t[1], t[1] .. " (trainer)", ("%s, %s (%.1f, %.1f)"):format(t[3], t[2], t[4], t[5]))
		end
	end
	for i, p in ipairs(d.POLES) do Add("tackle", "pole:" .. i, p[1], ("+%d Fishing, needs %d. %s"):format(p[3], p[4], p[5]), p[2]) end
	for i, l in ipairs(d.LURES) do Add("tackle", "lure:" .. i, l[1], ("+%d Fishing, needs %d. %s"):format(l[3], l[4], Parts(l[5])), l[2]) end
	for i, g in ipairs(d.GEAR) do Add("tackle", "gear:" .. i, g[1], g[4], g[2]) end
	for i, f in ipairs(d.FOOD) do Add("tackle", "food:" .. i, f[1], ("+%d Fishing for 15 min, level %d"):format(f[3], f[4]), f[2]) end
	for i, t in ipairs(d.TALENTS) do Add("tackle", "talent:" .. i, t[1], t[2]) end
	for i, c in ipairs(d.CAMP) do Add("camp", "camp:" .. i, c[1], ("Skill %d. %s %s %s"):format(c[3], c[5], c[4], c[6]), c[2]) end
	local E = d.EXTRAVAGANZA
	Add("extravaganza", nil, "Stranglethorn Fishing Extravaganza", E.when .. " " .. E.how .. " " .. E.win)
	for i, c in ipairs(E.coin) do Add("extravaganza", "coin:" .. i, c[1], c[3], c[2]) end
	for _, q in ipairs(d.QUESTS) do Add("extravaganza", "quest:" .. q[1], q[1] .. " (quest)", ("%s, %s. %s"):format(q[2], q[3], q[4])) end
	for i, t in ipairs(d.TALL_TALES) do Add("tales", "tale:" .. i, t[1], t[2]) end
	for i, l in ipairs(d.LEGENDS) do Add("tales", "legend:" .. i, "Legend: " .. l.title, l.text) end
end
spec.index = Index


-- Item names the page links: everything the book names that has an ID.
spec.names = function()
	local d, list = D(), {}
	local function Add(name, id)
		-- "Fishing Pole" alone is too common a phrase (a quest is named after one).
		if name and id and name ~= "Fishing Pole" then list[#list + 1] = { name, id } end
	end
	for _, f in pairs(d.FISH) do Add(f.name, f.id) end
	for _, rows in ipairs({ d.POLES, d.LURES, d.FOOD, d.GEAR }) do
		for _, r in ipairs(rows) do Add(r[1], r[2]) end
	end
	for _, c in ipairs(d.CAMP) do Add(c[1], c[2]) end
	for _, c in ipairs(d.EXTRAVAGANZA.coin) do Add(c[1], c[2]) end
	for name, id in pairs(d.ITEMS) do Add(name, id) end
	return list
end

---------------------------------------------------------------------------
-- The window's footer, and the doors in.

local function Status()
	local rank, cap, bonus = J.Skill()
	local log = Log()
	local species = 0
	for _ in pairs(log and log.catches or {}) do species = species + 1 end
	-- Two lines on the footer's right: your rank, large; the tally under it.
	local skill = rank and ("Fishing %d/%d%s"):format(rank, cap, bonus > 0 and (" (+%d)"):format(bonus) or "") or "No fishing yet"
	return skill, ("%s fish  \194\183  %d kinds"):format(Commas(log and log.total or 0), species)
end
spec.status = Status
spec.onShow = CheckSkill
book.build = BUILD

J.Render, J.Refresh, J.Select, J.Jump, J.Find = book.Render, book.Refresh, book.Select, book.Jump, book.Find
J.SetQuery, J.Search, J.Toggle, J.Open = book.SetQuery, book.Search, book.Toggle, book.Open
J.ResetPosition = book.ResetPosition
J.PlaceToast, J.ResetToastPosition, J.BuildToast = Book.PlaceToast, Book.ResetToastPosition, Book.BuildToast

function J.Toast(text, day, quality)
	Book.Toast(book, text, day, quality)
end

function J.PreviewToast()
	local lines = D().LINES.species
	local log = Log()
	J.Toast(Fill(lines[math.random(#lines)], { fish = "Raw Brilliant Smallfish", zone = "Elwynn Forest" }), log and log.dayCount or 1)
end

function J.ApplySettings()
	Book.PlaceToast()
	book.ApplySettings()
end

function J.Init()
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "LOOT_OPENED", "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL", "UI_ERROR_MESSAGE",
		"UI_INFO_MESSAGE", "CHAT_MSG_SYSTEM", "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED_INDOORS",
		"PLAYER_ENTERING_WORLD" }) do
		pcall(events.RegisterEvent, events, event)
	end
	for _, event in ipairs({ "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP" }) do
		if not pcall(events.RegisterUnitEvent, events, event, "player") then
			pcall(events.RegisterEvent, events, event)
		end
	end
	events:SetScript("OnEvent", function(_, event, ...)
		if event == "LOOT_OPENED" then
			ns.Try("journal loot", OnLoot)
		elseif event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
			ns.Try("journal cast", OnCast, event, ...)
		elseif event == "UI_ERROR_MESSAGE" or event == "UI_INFO_MESSAGE" or event == "CHAT_MSG_SYSTEM" then
			ns.Try("journal message", OnMessage, event, ...)
		elseif event == "SKILL_LINES_CHANGED" or event == "CHAT_MSG_SKILL" or event == "PLAYER_ENTERING_WORLD" then
			ns.Try("journal skill", CheckSkill)
			J.Refresh("now")
		else
			J.Refresh("now")
		end
	end)
end

---------------------------------------------------------------------------
-- The world map: "Show on the world map" lights up the zones a list names, coloured by how
-- their water treats your skill, with a pin in each whose tooltip says what bites there. A
-- banner over the map names the list, offers the other continent, and clears it. The zones'
-- shapes are the game's own hover highlights (C_Map.GetMapHighlightInfoAtPosition), found at a
-- point the map says lies inside the zone; a map that can't do that still gets the pins.
do
	local want -- { title, list = { { z, how } }, icon }
	local overlay, banner, hooked
	local pins, lights = {}, {}
	local placed = {} -- this map's zones: { x, y, lit, mapID, waters, reach, enemy }
	local idByName
	local FISH_ICON = "Interface\\Icons\\Trade_Fishing"
	local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
	local MAP_COLOR = { open = { 0.35, 1, 0.3 }, some = { 1, 0.72, 0.18 }, shut = { 0.62, 0.62, 0.62 } }
	local REACH_RANK = { open = 3, some = 2, shut = 1 }
	local CONTINENT = Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2
	local ZONE = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
	-- Points to try, nearest the middle of a zone's box first, for one inside the zone.
	local PROBES = {}
	for i = 0, 6 do
		for j = 0, 6 do PROBES[#PROBES + 1] = { 0.2 + i * 0.1, 0.2 + j * 0.1 } end
	end
	table.sort(PROBES, function(a, b)
		return (a[1] - 0.5) ^ 2 + (a[2] - 0.5) ^ 2 < (b[1] - 0.5) ^ 2 + (b[2] - 0.5) ^ 2
	end)

	local function MapIDs()
		if idByName then return idByName end
		idByName = {}
		local roots = { 946, C_Map.GetFallbackWorldMapID and C_Map.GetFallbackWorldMapID() or 947 }
		for _, root in ipairs(roots) do
			local ok, kids = pcall(C_Map.GetMapChildrenInfo, root, nil, true)
			for _, m in ipairs(ok and kids or {}) do
				local prev = idByName[m.name]
				if not prev or (m.mapType == ZONE and prev.mapType ~= ZONE) then idByName[m.name] = m end
			end
		end
		return idByName
	end

	local function ContinentOf(mapID)
		for _ = 1, 8 do
			local info = mapID and C_Map.GetMapInfo(mapID)
			if not info then return end
			if info.mapType == CONTINENT then return info.mapID end
			if info.mapType < CONTINENT then return end
			mapID = info.parentMapID
		end
	end

	-- A water's map: its own, or the zone it lies within.
	local function Resolve(name)
		local ids = MapIDs()
		local m = ids[name]
		if m and ContinentOf(m.mapID) then return m end
		local outer = D().WITHIN[name]
		m = outer and ids[outer]
		if m and ContinentOf(m.mapID) then return m end
	end

	local function Within(mapID, zoneID)
		for _ = 1, 6 do
			if not mapID then return false end
			if mapID == zoneID then return true end
			local info = C_Map.GetMapInfo(mapID)
			mapID = info and info.parentMapID
		end
		return false
	end

	-- Where to put a zone on the map shown: a point inside it (and so its highlight), or the
	-- middle of its box.
	local located = {} -- "zone:shown" -> { x, y, lit } or false
	local function Locate(zoneID, shownID)
		local key = zoneID .. ":" .. shownID
		local hit = located[key]
		if hit ~= nil then
			if hit then return hit[1], hit[2], hit[3] end
			return
		end
		located[key] = false
		local ok, left, right, top, bottom = pcall(C_Map.GetMapRectOnMap, zoneID, shownID)
		if not ok or not left or not right or right <= left or bottom <= top then return end
		hit = { (left + right) / 2, (top + bottom) / 2, false }
		for _, p in ipairs(PROBES) do
			local x, y = left + (right - left) * p[1], top + (bottom - top) * p[2]
			local at = C_Map.GetMapInfoAtPosition(shownID, x, y)
			if at and Within(at.mapID, zoneID) then
				hit = { x, y, true }
				break
			end
		end
		located[key] = hit
		return hit[1], hit[2], hit[3]
	end

	local function Canvas()
		return WorldMapFrame and WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas()
	end

	local function Light(i, shownID, g, color, alpha)
		local canvas = Canvas()
		local ok, fileID, atlasID, px, py, tx, ty, sx, sy = pcall(C_Map.GetMapHighlightInfoAtPosition, shownID, g.x, g.y)
		if not ok or not ((fileID and fileID > 0) or atlasID) then return end
		local t = lights[i]
		if not t then
			t = overlay:CreateTexture(nil, "OVERLAY")
			t:SetBlendMode("ADD")
			lights[i] = t
		end
		local w, h = canvas:GetWidth(), canvas:GetHeight()
		t:ClearAllPoints()
		t:SetTexCoord(0, px, 0, py)
		if atlasID then
			t:SetAtlas(atlasID, true, "TRILINEAR")
			t:SetPoint("CENTER", overlay, "CENTER", ((sx + 0.5 * tx) - 0.5) * w, -((sy + 0.5 * ty) - 0.5) * h)
		else
			if tx <= 0 or ty <= 0 then return end
			t:SetTexture(fileID, nil, nil, "LINEAR")
			t:SetSize(tx * w, ty * h)
			t:SetPoint("TOPLEFT", overlay, "TOPLEFT", sx * w, -sy * h)
		end
		t:SetVertexColor(color[1], color[2], color[3], alpha)
		t:Show()
	end

	local function PinTooltip(pin)
		local g = pin.g
		local eff = Effective()
		local c = MAP_COLOR[g.reach] or MAP_COLOR.shut
		GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
		GameTooltip:SetText(g.name .. (g.enemy and (" (%s land)"):format(SIDE_NAME[g.enemy]) or ""), c[1], c[2], c[3])
		for _, w in ipairs(g.waters) do
			local z = w.z
			local label = z[1] ~= g.name and (z[1] .. ": ") or ""
			local reach = Reach(z[2], eff)
			local how = w.how == "spot" and ("Known for " .. want.title .. ".") or w.how == "school" and "Schools may turn up." or w.how == "water" and "In its waters." or nil
			local skill
			if not z[2] then
				skill = "Skill not pinned down yet."
			elseif reach == "open" then
				skill = ("Opens at %d: nothing gets away for you."):format(z[2])
			elseif reach == "some" then
				skill = ("Opens at %d: some get away, you're %d short."):format(z[2], z[2] - eff)
			elseif reach == "shut" then
				skill = ("Nothing bites below %d."):format(z[2] - D().ESCAPE_GAP)
			else
				skill = ("Fishing %d."):format(z[2])
			end
			GameTooltip:AddLine(label .. (how and (how .. " ") or "") .. skill, 1, 0.82, 0.45, true)
			local note = ZoneNote(z)
			if note ~= "" then GameTooltip:AddLine(note, 0.9, 0.86, 0.78, true) end
			local hub = ZoneHub(z)
			if hub then GameTooltip:AddLine("Stay: " .. hub .. ".", 0.75, 0.72, 0.65, true) end
		end
		GameTooltip:AddLine("Click to zoom in.", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end

	local function Pin(i)
		local pin = pins[i]
		if pin then return pin end
		pin = CreateFrame("Button", nil, overlay)
		pin:SetSize(26, 26)
		pin.disc = pin:CreateTexture(nil, "ARTWORK")
		pin.disc:SetAllPoints()
		pin.disc:SetTexture("Interface\\Buttons\\WHITE8x8")
		pin.disc:SetMask(MASK)
		pin.icon = pin:CreateTexture(nil, "OVERLAY")
		pin.icon:SetPoint("CENTER")
		pin.icon:SetSize(20, 20)
		pin.icon:SetMask(MASK)
		pin:SetScript("OnEnter", PinTooltip)
		pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
		pin:SetScript("OnClick", function(self) WorldMapFrame:SetMapID(self.g.mapID) end)
		pins[i] = pin
		return pin
	end

	-- Pins keep their size on screen as the map zooms: placed again when the canvas changes.
	local lastW, lastH, lastScale
	local function Place()
		local canvas = Canvas()
		if not canvas then return end
		local w, h, scale = canvas:GetWidth(), canvas:GetHeight(), canvas:GetScale()
		lastW, lastH, lastScale = w, h, scale
		local k = 1 / math.max(scale, 0.05)
		for i, g in ipairs(placed) do
			local pin = pins[i]
			pin:SetScale(k)
			pin:ClearAllPoints()
			pin:SetPoint("CENTER", overlay, "TOPLEFT", g.x * w / k, -g.y * h / k)
		end
	end

	local Draw
	local function Banner()
		if banner then return banner end
		local parent = WorldMapFrame.ScrollContainer or WorldMapFrame
		banner = CreateFrame("Frame", nil, parent)
		banner:SetFrameLevel(parent:GetFrameLevel() + 2500)
		banner:SetPoint("TOP", parent, "TOP", 0, -6)
		banner:SetHeight(26)
		local bg = banner:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0.05, 0.03, 0.02, 0.82)
		local edge = banner:CreateTexture(nil, "BORDER")
		edge:SetPoint("BOTTOMLEFT")
		edge:SetPoint("BOTTOMRIGHT")
		edge:SetHeight(1)
		edge:SetColorTexture(0.62, 0.42, 0.06, 0.9)
		banner.text = banner:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		banner.text:SetPoint("LEFT", 10, 0)
		banner.other = CreateFrame("Button", nil, banner)
		banner.other:SetPoint("LEFT", banner.text, "RIGHT", 12, 0)
		banner.other.text = banner.other:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		banner.other.text:SetPoint("LEFT")
		banner.other:SetScript("OnClick", function(self) if self.mapID then WorldMapFrame:SetMapID(self.mapID) end end)
		banner.other:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 0.82, 0.3) end)
		banner.other:SetScript("OnLeave", function(self) self.text:SetTextColor(1, 1, 1) end)
		banner.close = CreateFrame("Button", nil, banner, "UIPanelCloseButton")
		banner.close:SetSize(22, 22)
		banner.close:SetPoint("RIGHT", -2, 0)
		banner.close:SetScript("OnClick", function() J.ClearMap() end)
		return banner
	end

	local function UpdateBanner(shownID)
		local b = Banner()
		b.text:SetText(("|cffd8b86aAngler's journal:|r %s   |cff66ff55green|r nothing gets away   |cffffb82eamber|r some do"):format(want.title))
		local here = ContinentOf(shownID)
		local counts, best, bestN = {}, nil, 0
		for _, w in ipairs(want.list) do
			local m = Resolve(w.z[1])
			local c = m and ContinentOf(m.mapID)
			if c and c ~= here then
				counts[c] = (counts[c] or 0) + 1
				if counts[c] > bestN then best, bestN = c, counts[c] end
			end
		end
		if best then
			local info = C_Map.GetMapInfo(best)
			b.other.mapID = best
			b.other.text:SetText(("Also on %s (%d) >"):format(info and info.name or "another continent", bestN))
			b.other:SetSize(b.other.text:GetStringWidth() + 4, 20)
			b.other:Show()
		else
			b.other:Hide()
		end
		local width = 10 + b.text:GetStringWidth() + (best and (12 + b.other:GetWidth()) or 0) + 34
		b:SetWidth(width)
		b:Show()
	end

	Draw = function()
		for _, pin in ipairs(pins) do pin:Hide() end
		for _, t in ipairs(lights) do t:Hide() end
		wipe(placed)
		if not want or not WorldMapFrame or not WorldMapFrame:IsShown() then
			if banner then banner:Hide() end
			if overlay then overlay:Hide() end
			return
		end
		local canvas = Canvas()
		local shownID = WorldMapFrame:GetMapID()
		local info = shownID and C_Map.GetMapInfo(shownID)
		if not canvas or not info then return end
		if not overlay then
			overlay = CreateFrame("Frame", nil, canvas)
			overlay:SetAllPoints(canvas)
			overlay:SetScript("OnUpdate", function()
				local c = Canvas()
				if c and (c:GetWidth() ~= lastW or c:GetHeight() ~= lastH or c:GetScale() ~= lastScale) then Place() end
			end)
		end
		overlay:SetFrameLevel(canvas:GetFrameLevel() + 1500)
		overlay:Show()
		UpdateBanner(shownID)
		if info.mapType > CONTINENT then return end -- a zone's own map: the banner only
		local eff = Effective()
		local byID = {}
		for _, w in ipairs(want.list) do
			local m = Resolve(w.z[1])
			if m then
				local g = byID[m.mapID]
				if not g then
					local x, y, lit = Locate(m.mapID, shownID)
					if x then
						g = { x = x, y = y, lit = lit, mapID = m.mapID, name = m.name, waters = {} }
						byID[m.mapID] = g
						placed[#placed + 1] = g
					end
				end
				if g then
					g.waters[#g.waters + 1] = w
					local reach = Reach(w.z[2], eff) or "shut"
					if not g.reach or REACH_RANK[reach] > REACH_RANK[g.reach] then g.reach = reach end
					local side = w.z.side
					if side and Enemy(side) then g.enemy = g.enemy or side else g.friendly = true end
				end
			end
		end
		for i, g in ipairs(placed) do
			if g.friendly then g.enemy = nil end
			local c = MAP_COLOR[g.reach] or MAP_COLOR.shut
			if g.lit and info.mapType == CONTINENT then Light(i, shownID, g, c, g.enemy and 0.3 or 0.55) end
			local pin = Pin(i)
			pin.g = g
			pin.disc:SetVertexColor(c[1] * 0.8, c[2] * 0.8, c[3] * 0.8, 1)
			pin.icon:SetTexture(want.icon)
			pin.icon:SetDesaturated(g.reach == "shut" or g.enemy and true or false)
			pin:SetAlpha(g.enemy and 0.6 or 1)
			pin:SetFrameLevel(overlay:GetFrameLevel() + 10 + i)
			pin:Show()
		end
		Place()
	end

	local function Hook()
		if hooked or not WorldMapFrame then return end
		hooked = true
		hooksecurefunc(WorldMapFrame, "OnMapChanged", Draw)
		WorldMapFrame:HookScript("OnShow", Draw)
	end

	function J.ShowOnMap(title, list, itemID)
		if not C_Map or not C_Map.GetMapRectOnMap then
			ns.Print("This client's map can't be marked.")
			return
		end
		if InCombatLockdown() then
			ns.Print("The map waits until the fight's over.")
			return
		end
		if not WorldMapFrame and C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_WorldMap") end
		if not WorldMapFrame then return end
		Hook()
		local icon = itemID and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID)
		want = { title = title, list = list, icon = icon or FISH_ICON }
		-- Your continent if the list has a zone there, else the one with most.
		local counts, best, bestN = {}, nil, 0
		for _, w in ipairs(list) do
			local m = Resolve(w.z[1])
			local c = m and ContinentOf(m.mapID)
			if c then
				counts[c] = (counts[c] or 0) + 1
				if counts[c] > bestN then best, bestN = c, counts[c] end
			end
		end
		local here = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
		here = Readable(here) and here and ContinentOf(here)
		local target = (here and counts[here]) and here or best
		if not target then
			want = nil
			ns.Print("The world map doesn't know these waters.")
			return
		end
		if not WorldMapFrame:IsShown() then
			if OpenWorldMap then OpenWorldMap(target) else ShowUIPanel(WorldMapFrame) end
		end
		if WorldMapFrame:GetMapID() ~= target then
			WorldMapFrame:SetMapID(target) -- draws, through the OnMapChanged hook
		else
			Draw()
		end
	end

	function J.ClearMap()
		want = nil
		Draw()
	end
end
