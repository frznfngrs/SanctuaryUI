SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.Cookbook = ns.Cookbook or {}
local C = ns.Cookbook

BINDING_NAME_SANCTUARYUICOOKBOOK = "The Cookbook"

-- The Cookbook: the Angler's journal's sister (both are books: Book.lua), about cooking. Its
-- recipe tables are CookingRecipes.lua (generated from the game install), its words
-- CookingData.lua. This file writes the chapters, reads your Cooking skill, your bags and the
-- recipes you know, and keeps a per-character kitchen diary that writes itself.

local Book = ns.Book
local INK, RED, MUTED, GREEN, AMBER, GOLD = Book.INK, Book.RED, Book.MUTED, Book.GREEN, Book.AMBER, Book.GOLD
local Readable, Commas, Fill = Book.Readable, Book.Commas, Book.Fill
local MySide, Enemy, SIDE_NAME = Book.MySide, Book.Enemy, Book.SIDE_NAME
local ORANGE = { 0.72, 0.30, 0.02 }
local YELLOW = { 0.56, 0.45, 0.00 }
local TICK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:13:13:0:-1|t "

C.CHAPTERS = {
	{ key = "diary", title = "The Diary", tip = "Your kitchen diary, written as you cook: firsts, new recipes, milestones, and the tally." },
	{ key = "larder", title = "The Larder", tip = "Here and now: what you can cook from your bags, what each ingredient becomes, what to learn next." },
	{ key = "route", title = "The Road to 300", tip = "Ranks, the levelling route with a pole or a blade, and every trainer." },
	{ key = "recipes", title = "Recipes", tip = "Every dish by skill: what goes in, what it does, where it's learned. Ticks what you know." },
	{ key = "catch", title = "From the Water", tip = "For anglers: what each fish becomes, and what the dish is good for." },
	{ key = "table", title = "The Table", tip = "What to eat: the best food by role, food for the way up, and how Well Fed works." },
	{ key = "pantry", title = "The Pantry", tip = "Every ingredient: what drops it, who sells it, and which dishes want it." },
	{ key = "camp", title = "Camp & Oven", tip = "Campfire kits, Cookie's Feast, the Iron Oven and its dishes, legacy talents." },
	{ key = "tales", title = "Kitchen Tales", tip = "Old stories, and rumours we couldn't confirm. Season to taste." },
}

local COOKING_SKILL = 185
local COOKING_SPELL = 2550

local function Opt()
	return ns.DB().cookbook
end

-- This character's kitchen log and diary.
local function Log()
	local char = ns.db and ns.db.char
	return char and char.cooking
end
C.Log = Log

local function D() return ns.CookingData end

local spec = {
	key = "cooking",
	frameName = "SanctuaryUICookbook",
	title = "The Cookbook",
	art = "cookbook",
	opt = Opt,
	log = Log,
	chapters = C.CHAPTERS,
	home = "larder",
	live = "larder",
	place = { "RIGHT", -110, 0 },
	story = function() return D().STORY end,
	words = {
		search = "Search the Cookbook",
		nothing = "Nothing by \"%s\". Maybe somebody ate it.",
		scope = "Search looks at dishes, ingredients, trainers, recipe sellers, camp items, talents, quests, tall tales and your diary.",
		wet = "This page got burnt: ",
		empty = "Empty. Go cook something. Anything. Toast counts. There is no toast. Improvise.",
		paused = "The diary is paused (Options > Professions > Cookbook).",
		older = "...and %d older entries, stuck together with gravy.",
	},
}
local book = Book.New(spec)
C.book = book
local B, Pick = book.B, book.Pick

---------------------------------------------------------------------------
-- The tables, indexed.

local BY_NAME, BY_SPELL, USES, GHOST, OVEN, CAMP_ITEM
local function Tables()
	if BY_NAME then return end
	local d = D()
	BY_NAME, BY_SPELL, USES, GHOST, OVEN, CAMP_ITEM = {}, {}, {}, {}, {}, {}
	for _, name in ipairs(d.GHOSTS) do GHOST[name] = true end
	for _, name in ipairs(d.OVEN) do OVEN[name] = true end
	for _, name in ipairs(d.CAMP) do CAMP_ITEM[name] = true end
	for _, r in ipairs(d.RECIPES) do
		BY_NAME[r.name], BY_SPELL[r.spell] = r, r
		for _, need in ipairs(r.needs) do
			USES[need[1]] = USES[need[1]] or {}
			table.insert(USES[need[1]], r)
		end
	end
end

local function ItemName(id)
	return D().ITEM[id] or ("item " .. id)
end

-- "2 Lion Meat, Soothing Spices"
local function Needs(r)
	if #r.needs == 0 then return "The tables don't say what goes in yet." end
	local parts = {}
	for _, need in ipairs(r.needs) do
		parts[#parts + 1] = (need[2] > 1 and (need[2] .. " ") or "") .. ItemName(need[1])
	end
	return table.concat(parts, ", ")
end

-- What a dish does, as the page says it.
local function Effect(r)
	local e = D().EFFECTS[r.name]
	if not e then return "" end
	return e[2] or D().KIND_NAME[e[1]] or ""
end

local function Kind(r)
	local e = D().EFFECTS[r.name]
	return e and e[1]
end

---------------------------------------------------------------------------
-- What the client says: your skill, your level, your bags, the recipes you know.

-- rank, cap; nil when you haven't learned to cook (or the client won't say).
function C.Skill()
	return Book.Skill(COOKING_SKILL, COOKING_SPELL, PROFESSIONS_COOKING or "Cooking")
end

local function Level()
	local level = UnitLevel and UnitLevel("player")
	return Readable(level) and level or nil
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

-- Does the spellbook hold this recipe? true, false, or nil when the client can't be asked.
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

local function Knows(r)
	local log = Log()
	if log and log.known[r.spell] then return true end
	return Asked(r.spell) or false
end

-- Can the book tell what you know at all? Not when you cook but nothing reads as known.
local function CanTell()
	local log = Log()
	if log and next(log.known) then return true end
	Tables()
	for _, r in ipairs(D().RECIPES) do
		if Asked(r.spell) then return true end
	end
	return false
end

-- How many of a dish your bags hold the makings for.
local function CanMake(r)
	if #r.needs == 0 then return 0 end
	local n = math.huge
	for _, need in ipairs(r.needs) do
		n = math.min(n, math.floor(Have(need[1]) / need[2]))
	end
	return n
end

-- How much a recipe still teaches: "locked", "orange", "yellow", "green", "grey"; nil when
-- nobody knows its numbers.
local function Difficulty(r, rank)
	if not rank then return end
	if rank < r.skill then return "locked" end
	local yellow, green, grey = r.yellow, r.yellow and math.floor((r.yellow + r.grey) / 2), r.grey
	local guide = D().SKILLUP[r.name]
	if not yellow and guide then yellow, green, grey = guide[1], guide[2], guide[3] end
	if not yellow then return end
	if rank < yellow then return "orange" end
	if rank < green then return "yellow" end
	if rank < grey then return "green" end
	return "grey"
end

local DIFF = {
	locked = { RED, "not yet", 0 }, orange = { ORANGE, "a point every time", 4 }, yellow = { YELLOW, "a point, mostly", 3 },
	green = { GREEN, "a point, sometimes", 2 }, grey = { MUTED, "nothing to learn", 1 },
}

---------------------------------------------------------------------------
-- People and places.

local function Where()
	local zone = GetRealZoneText and GetRealZoneText() or ""
	return Readable(zone) and zone or ""
end

-- "Name, Zone (x, y)"
local function Person(id, bare)
	local n = D().NPC[id]
	if not n then return "someone" end
	local text = n[1]
	if n[2] ~= "" and not bare then text = text .. ", " .. n[2] end
	if n[3] > 0 then text = text .. (" (%.1f, %.1f)"):format(n[3], n[4]) end
	return text
end

-- The people on a list you can deal with (your side's and neutral), those in this zone first.
local function Mine(list)
	local here, out = Where(), {}
	for _, id in ipairs(list or {}) do
		local n = D().NPC[id]
		if n and not Enemy(n[5]) then out[#out + 1] = id end
	end
	table.sort(out, function(a, b)
		local na, nb = D().NPC[a], D().NPC[b]
		local ha, hb = na[2] == here, nb[2] == here
		if ha ~= hb then return ha end
		if na[2] ~= nb[2] then return na[2] < nb[2] end
		return na[1] < nb[1]
	end)
	return out
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

-- { text, side } parts: yours and the neutral ones, joined.
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
	return table.concat(out, "; ")
end

-- Where a recipe is learned, for you.
local function Learn(r)
	local d = D()
	if r.side and Enemy(r.side) then return EnemyLine(r.side, r.name) end
	if d.LEARN[r.name] then return d.LEARN[r.name] end
	local parts = {}
	for _, how in ipairs(r.how) do
		if how == "start" then
			parts[#parts + 1] = "You knew it the day you picked up a pan"
		elseif how == "trainer" then
			parts[#parts + 1] = "Any cooking trainer" .. (r.cost and (" (" .. Coin(r.cost) .. ")") or "")
		elseif how == "vendor" then
			local sellers = Mine(r.vendors)
			if #sellers > 0 then
				local text = "Recipe from " .. Person(sellers[1])
				if #sellers == 2 then
					text = text .. ", or " .. Person(sellers[2])
				elseif #sellers > 2 then
					text = text .. (", and %d more"):format(#sellers - 1)
				end
				if r.favor then
					text = text .. (", for %d Merchant's Favor"):format(r.favor)
					if r.standing then text = text .. " at " .. r.standing end
				end
				parts[#parts + 1] = text
			elseif #(r.vendors or {}) > 0 then
				parts[#parts + 1] = "Sold only to the other side; try the auction house"
			end
		elseif how == "quest" then
			for _, quest in ipairs(r.quests or {}) do
				if not Enemy(quest[3]) then
					parts[#parts + 1] = ("Quest: %s%s"):format(quest[2], quest[4] > 0 and (", from " .. Person(quest[4])) or "")
				end
			end
		elseif how == "drop" then
			if r.drops then
				local who = {}
				for _, id in ipairs(r.drops) do who[#who + 1] = Person(id) end
				parts[#parts + 1] = "Recipe drops from " .. table.concat(who, "; ")
			else
				parts[#parts + 1] = r.world and "The recipe is a world drop" or "The recipe is a drop; from what, nobody's sure"
			end
		elseif how == "world_object" then
			parts[#parts + 1] = "The recipe is found lying about, not dropped"
		end
	end
	if #parts == 0 then return "Where it's learned isn't known yet." end
	return table.concat(parts, ". ") .. "."
end

-- Can you learn it at all (your side, your class, and somebody knows how)?
local function Learnable(r)
	Tables()
	if GHOST[r.name] or (r.side and Enemy(r.side)) then return false end
	local classes = D().CLASS[r.name]
	if classes then
		local _, class = UnitClass("player")
		if not Readable(class) or not classes[class] then return false end
	end
	return #r.how > 0 or D().LEARN[r.name] ~= nil
end

---------------------------------------------------------------------------
-- The diary: dishes cooked, recipes learned, milestones.

local Today = Book.Today

local function OnCooked(r)
	local log = Log()
	if not log then return end
	Tables()
	local lines = D().LINES
	local before = log.total or 0
	local fresh = not log.cooked[r.spell]
	local made = r.makes or 1
	log.cooked[r.spell] = (log.cooked[r.spell] or 0) + made
	log.names[r.item] = r.name
	log.total = before + made
	if r.fish then log.fish = (log.fish or 0) + made end
	local fields = { dish = r.name, item = r.name, zone = Where() ~= "" and Where() or "these parts" }
	if before == 0 then
		book.Write(Fill(lines.first[1], fields))
	elseif fresh then
		local line = lines.special[r.name] or (OVEN[r.name] and lines.oven) or (r.fish and Pick(lines.fish, "fish")) or Pick(lines.dish, "dish")
		book.Write(Fill(line, fields))
	elseif Difficulty(r, (C.Skill())) == "grey" and log.greyDay ~= Today() then
		-- Cooking for the eating: one line a day.
		log.greyDay = Today()
		book.Write(Fill(Pick(lines.grey, "grey"), fields))
	end
	for mark, line in pairs(lines.total) do
		if before < mark and log.total >= mark then book.Write(line) end
	end
	-- A long day at the stove, once.
	if log.batchDay ~= Today() then log.batchDay, log.batch = Today(), 0 end
	local was = log.batch or 0
	log.batch = was + made
	if was < 60 and log.batch >= 60 then
		book.Write(Fill(lines.batch, { n = log.batch }))
	end
	book.Refresh()
end

local function OnCast(unit, _, spellID)
	if unit ~= "player" or not Readable(spellID) then return end
	Tables()
	local r = BY_SPELL[spellID]
	if r then OnCooked(r) end
end

-- New recipes: whatever the spellbook holds that the log doesn't. The first look on a
-- character only remembers; after that each new one gets a line (a few at most at once: a
-- visit to the trainer shouldn't bury the diary).
local function CheckRecipes(announce)
	local log = Log()
	if not log then return end
	Tables()
	local written = 0
	for _, r in ipairs(D().RECIPES) do
		if not log.known[r.spell] and Asked(r.spell) then
			log.known[r.spell] = true
			if log.scanned and announce ~= false and written < 3 and not CAMP_ITEM[r.name] then
				written = written + 1
				book.Write(Fill(Pick(D().LINES.learned, "learned"), { dish = r.name }))
			end
		end
	end
	if next(log.known) then log.scanned = true end
end

-- Skill and rank milestones. The first look on a character only remembers where you are.
local function CheckSkill()
	local log = Log()
	if not log then return end
	local rank, cap = C.Skill()
	if not rank then return end
	local lines = D().LINES
	if not log.started then
		log.started = true
		log.skillSeen, log.rankSeen = rank, cap
		if rank > 1 then
			book.Write(("Opened this cookbook at Cooking %d. The earlier pages were eaten. Not by me."):format(rank))
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

-- A dish's name as a row shows it: ticked when you know it, marked when it's Forever's.
local function DishName(r, tell)
	return ((tell and Knows(r)) and TICK or "") .. r.name .. (r.new and "  |cff9a6a0e(new)|r" or "")
end

function BUILD.diary()
	local log = Log()
	if not log then return end
	Tables()
	B.h("The tally")
	local kinds, best, bestN = 0, nil, 0
	for spell, n in pairs(log.cooked) do
		kinds = kinds + 1
		if n > bestN then best, bestN = spell, n end
	end
	B.kv("Dishes cooked", Commas(log.total))
	B.kv("Kinds", Commas(kinds))
	B.kv("Fish dishes", Commas(log.fish or 0) .. ((log.fish or 0) > 0 and "  (the fish have noticed)" or ""))
	if CanTell() then
		local known, all = 0, 0
		for _, r in ipairs(D().RECIPES) do
			if not GHOST[r.name] then
				all = all + 1
				if Knows(r) then known = known + 1 end
			end
		end
		B.kv("Recipes known", ("%d of %d"):format(known, all))
	end
	if best and BY_SPELL[best] then B.kv("Most cooked", ("%s (%s)"):format(BY_SPELL[best].name, Commas(bestN))) end
	B.entries()
end

local function NextStep(rank, cap)
	local mine = MySide()
	if rank >= cap and cap < 300 then
		for _, r in ipairs(D().RANKS) do
			if r[2] > cap then
				return ("Capped at %d. Next: %s. %s"):format(cap, r[1], r[3]), RED
			end
		end
	elseif cap == 150 and rank >= 125 then
		local who = mine == "H" and "Wulan in Shadowprey Village, Desolace" or mine == "A" and "Shandrina at Mystral Lake, Ashenvale" or "Shandrina in Ashenvale or Wulan in Desolace"
		return ("At 125 you can read the Expert Cookbook (%s). Buy it before you cap."):format(who), MUTED
	elseif cap == 225 and rank >= 200 then
		return "At 225 and level 35, Dirge Quikcleave in Gadgetzan wants 12 Giant Egg, 10 Zesty Clam Meat and 20 Alterac Swiss. Start saving eggs.", MUTED
	end
end

function BUILD.larder()
	Tables()
	local d = D()
	local rank, cap = C.Skill()
	local tell = CanTell()
	local zone = Where()
	B.h("Your kitchen")
	if not rank then
		B.hand("You don't cook yet. Any cooking trainer will show you which end of the pan is hot.")
	else
		B.p(("Cooking %d of %d."):format(rank, cap))
		local step, color = NextStep(rank, cap)
		if step then B.p(step, color, 12.5) end
	end
	if rank and not tell then
		B.note("The book can't see which recipes you know yet, so it lists everything your skill allows. Open your Cooking window once and it should catch up.")
	end

	-- What the bags can become right now.
	local ready = {}
	for _, r in ipairs(d.RECIPES) do
		local n = CanMake(r)
		if rank and n > 0 and not GHOST[r.name] and rank >= r.skill and (not tell or Knows(r)) then
			ready[#ready + 1] = { r, n, Difficulty(r, rank) }
		end
	end
	table.sort(ready, function(a, b)
		local da, db = a[3] and DIFF[a[3]][3] or 2.5, b[3] and DIFF[b[3]][3] or 2.5
		if da ~= db then return da > db end
		if a[1].skill ~= b[1].skill then return a[1].skill > b[1].skill end
		return a[1].name < b[1].name
	end)
	if rank then B.h("Ready to cook") end
	if not rank then
		-- Not a cook: the bags below still say what things could be.
	elseif #ready == 0 then
		B.hand("Nothing in the bags makes a dish you know. Go and bother a boar.")
	else
		B.row({ "Dish", "Makes", "Teaches", "Does" }, { 0.40, 0.11, 0.21, 0.28 }, { head = true })
		for _, entry in ipairs(ready) do
			local r, n, diff = entry[1], entry[2], entry[3]
			local shade = diff and DIFF[diff] or nil
			B.row({ r.name, tostring(n * (r.makes or 1)), shade and shade[2] or "", Effect(r) }, { 0.40, 0.11, 0.21, 0.28 },
				{ item = r.item, colors = { INK, INK, shade and shade[1] or MUTED, MUTED } })
			if OVEN[r.name] then
				B.row({ "", "Needs an Iron Oven at the camp." }, { 0.06, 0.94 }, { colors = { MUTED, AMBER }, cont = true })
			end
		end
		B.note("Cook at any fire: a brazier, a stove, or your own campfire.")
	end

	-- Ingredients in the bags that could be something, if you knew how.
	local raw = {}
	for id, recipes in pairs(USES) do
		local n = Have(id)
		if n > 0 and d.FROM[id] and d.FROM[id].kind ~= "shop" then
			raw[#raw + 1] = { id, n, recipes }
		end
	end
	table.sort(raw, function(a, b) return ItemName(a[1]) < ItemName(b[1]) end)
	if #raw > 0 then
		B.h("In your bags")
		for _, entry in ipairs(raw) do
			local id, n, recipes = entry[1], entry[2], entry[3]
			local shown = 0
			for _, r in ipairs(recipes) do
				if not GHOST[r.name] and not (r.side and Enemy(r.side)) and shown < 3 then
					local status
					if rank and rank < r.skill then
						status = ("at Cooking %d"):format(r.skill)
					elseif tell and not Knows(r) then
						status = Learn(r)
					elseif tell then
						status = "you know it"
					else
						status = ("Cooking %d"):format(r.skill)
					end
					local color = (tell and Knows(r) and (not rank or rank >= r.skill)) and GREEN or MUTED
					B.row({ shown == 0 and ("%s  x%d"):format(ItemName(id), n) or "", r.name, status }, { 0.36, 0.28, 0.36 },
						{ item = shown == 0 and id or nil, colors = { INK, INK, color }, cont = shown > 0, pad = 3 })
					shown = shown + 1
				end
			end
		end
	end

	-- Worth learning: recipes within reach you don't have, the most useful (highest) first.
	if rank and tell then
		local want = {}
		for _, r in ipairs(d.RECIPES) do
			if rank >= r.skill and not Knows(r) and Learnable(r) and not CAMP_ITEM[r.name] and Difficulty(r, rank) ~= "grey" then
				want[#want + 1] = r
			end
		end
		table.sort(want, function(a, b)
			if a.skill ~= b.skill then return a.skill > b.skill end
			return a.name < b.name
		end)
		if #want > 0 then
			B.h("Worth learning now")
			for i = 1, math.min(8, #want) do
				local r = want[i]
				B.row({ r.name, Learn(r) }, { 0.36, 0.64 }, { item = r.item, pad = 3 })
			end
			if #want > 8 then B.note(("...and %d more in Recipes."):format(#want - 8)) end
		end
	end

	-- Who's here.
	local people = {}
	for _, id in ipairs(d.TRAINERS) do
		local n = d.NPC[id]
		if n and n[2] == zone and not Enemy(n[5]) then people[#people + 1] = { Person(id, true), "Teaches cooking." } end
	end
	local sells = {}
	for _, r in ipairs(d.RECIPES) do
		if not (tell and Knows(r)) and not GHOST[r.name] then
			for _, id in ipairs(Mine(r.vendors)) do
				if d.NPC[id][2] == zone then
					sells[id] = sells[id] or {}
					table.insert(sells[id], r.name)
				end
			end
		end
	end
	local ids = {}
	for id in pairs(sells) do ids[#ids + 1] = id end
	table.sort(ids, function(a, b) return d.NPC[a][1] < d.NPC[b][1] end)
	for _, id in ipairs(ids) do
		local list = sells[id]
		local text = "Sells: " .. table.concat(list, ", ", 1, math.min(5, #list)) .. (#list > 5 and (" and %d more"):format(#list - 5) or "")
		people[#people + 1] = { Person(id, true), text .. "." }
	end
	if #people > 0 then
		B.h(zone ~= "" and ("Cooks in " .. zone) or "Cooks here")
		for _, p in ipairs(people) do
			B.row(p, { 0.42, 0.58 }, { pad = 3 })
		end
	end
end

local function TrainerRow(id)
	local n = D().NPC[id]
	local enemy = Enemy(n[5])
	local name = n[1] .. (enemy and (" (%s)"):format(SIDE_NAME[n[5]]) or (n[5] == "N" and " (both)" or ""))
	B.row({ name, n[2], n[3] > 0 and ("%.1f, %.1f"):format(n[3], n[4]) or "" }, { 0.40, 0.42, 0.18 }, { dim = enemy, anchor = "trainer:" .. n[1] })
end

function BUILD.route()
	Opener("route")
	local d = D()
	local mine = MySide()
	B.h("Ranks")
	for i, r in ipairs(d.RANKS) do
		B.row({ ("%s (to %d)"):format(r[1], r[2]), r[3] }, { 0.3, 0.7 }, { item = r.item, anchor = "rank:" .. i })
	end
	B.h("The route")
	B.note("Two roads: one for anglers, one for hunters. They cross whenever you like.")
	for i, step in ipairs(d.ROUTE) do
		if step[2] == step[3] then
			B.row({ step[1], step[2] }, { 0.2, 0.8 }, { colors = { RED, INK }, pad = 2, anchor = "route:" .. i })
		else
			B.row({ step[1], "With a pole: " .. step[2] }, { 0.2, 0.8 }, { colors = { RED, INK }, pad = 2, anchor = "route:" .. i })
			B.row({ "", "With a blade: " .. step[3] }, { 0.2, 0.8 }, { colors = { RED, INK }, pad = 2, cont = true })
		end
		B.row({ "", step[4] }, { 0.2, 0.8 }, { colors = { MUTED, MUTED }, cont = true })
	end
	B.h("Fishing and cooking, one trip")
	for i, line in ipairs(d.TOGETHER) do
		B.row({ tostring(i), line }, { 0.06, 0.94 }, { colors = { RED, INK }, pad = 4 })
	end
	B.row({ "", "The Angler's journal has the waters." }, { 0.06, 0.94 }, {
		colors = { MUTED, GOLD }, tip = "Open the Angler's journal",
		onClick = function() if ns.Journal and ns.Journal.Open then ns.Journal.Open("route") end end,
	})
	B.h("Clamlette Surprise: the shopping list")
	for _, c in ipairs(d.CLAMLETTE) do
		B.row({ ("%d %s"):format(c[2], c[1]), Parts(c[3]) }, { 0.36, 0.64 }, { pad = 4 })
	end
	B.h("Trainers who'll teach you")
	local other = 0
	for _, side in ipairs({ "N", mine or "A", (not mine) and "H" or false }) do
		for _, id in ipairs(d.TRAINERS) do
			if side and d.NPC[id] and d.NPC[id][5] == side then TrainerRow(id) end
		end
	end
	for _, id in ipairs(d.TRAINERS) do
		if d.NPC[id] and Enemy(d.NPC[id][5]) then other = other + 1 end
	end
	if mine and other > 0 then
		B.note(("And %d %s cooks, who'd sooner feed a murloc."):format(other, SIDE_NAME[mine == "H" and "A" or "H"]))
	end
	B.h("Quests")
	for _, quest in ipairs(d.QUESTS) do
		if not Enemy(quest.side) then
			B.row({ quest[1], ("%s, %s. %s"):format(quest[2], quest[3], quest[4]) }, { 0.36, 0.64 }, { anchor = "quest:" .. quest[1] })
		end
	end
end

local BRACKETS = {
	{ 1, 75, "Apprentice (1 to 75)" }, { 76, 150, "Journeyman (76 to 150)" }, { 151, 225, "Expert (151 to 225)" },
	{ 226, 300, "Artisan (226 to 300)" },
}

function BUILD.recipes()
	Opener("recipes")
	Tables()
	local d = D()
	local rank = C.Skill()
	local tell = CanTell()
	if tell then
		local known, all = 0, 0
		for _, r in ipairs(d.RECIPES) do
			if not GHOST[r.name] then
				all = all + 1
				if Knows(r) then known = known + 1 end
			end
		end
		B.note(("Ticked: you know it (%d of %d). Hover a dish for its card, shift-click to link it."):format(known, all))
	else
		B.note("Hover a dish for its card, shift-click to link it.")
	end
	if rank then
		B.note(("You cook at %d. The number's colour is what a dish still teaches: orange always, yellow mostly, green sometimes, grey nothing. Red: not yet."):format(rank))
	end
	local cols = { 0.44, 0.09, 0.47 }
	local function Row(r)
		local diff = Difficulty(r, rank)
		local enemy = r.side and Enemy(r.side)
		B.row({ DishName(r, tell), tostring(r.skill), Needs(r) }, cols,
			{ item = r.item, pad = 2, dim = enemy, colors = { INK, diff and DIFF[diff][1] or INK, MUTED }, anchor = "recipe:" .. r.name })
		local effect = Effect(r)
		local text = (effect ~= "" and (effect .. ". ") or "") .. (OVEN[r.name] and "Iron Oven. " or "") .. Learn(r)
		B.row({ "", text }, { 0.0, 1.0 }, { colors = { MUTED, MUTED }, cont = true, dim = enemy })
	end
	for _, bracket in ipairs(BRACKETS) do
		B.h(bracket[3])
		B.row({ "Dish", "Skill", "Goes in" }, cols, { head = true })
		for _, r in ipairs(d.RECIPES) do
			if r.skill >= bracket[1] and r.skill <= bracket[2] and not GHOST[r.name] and not CAMP_ITEM[r.name] then Row(r) end
		end
	end
	B.h("On nobody's stove", MUTED)
	B.note("In the game's tables, with no known way to learn them. Leftovers from another season, most likely.")
	for _, r in ipairs(d.RECIPES) do
		if GHOST[r.name] then
			B.row({ r.name, tostring(r.skill), Needs(r) }, cols, { item = r.item, dim = true, anchor = "recipe:" .. r.name })
		end
	end
end

function BUILD.catch()
	Opener("catch")
	Tables()
	local d, f = D(), ns.FishingData
	local rank = C.Skill()
	local tell = CanTell()
	B.row({ "", "Where each one bites is in the Angler's journal." }, { 0.0, 1.0 }, {
		colors = { MUTED, GOLD }, tip = "Open the Angler's journal at The Catch",
		onClick = function() if ns.Journal and ns.Journal.Open then ns.Journal.Open("catches") end end,
	})
	if not f then return end
	local cols = { 0.40, 0.34, 0.26 }
	local idle = {}
	B.h("Fish for the pan")
	B.row({ "Catch", "Becomes", "Does" }, cols, { head = true })
	for _, key in ipairs(f.FISH_ORDER) do
		local fish = f.FISH[key]
		local recipes = fish.id and USES[fish.id]
		local shown = 0
		for _, r in ipairs(recipes or {}) do
			if not GHOST[r.name] then
				local diff = Difficulty(r, rank)
				local have = shown == 0 and Have(fish.id) or 0
				B.row({ shown == 0 and (fish.name .. (have > 0 and ("  x%d"):format(have) or "")) or "", ("%s%s (%d)"):format(tell and Knows(r) and TICK or "", r.name, r.skill), Effect(r) },
					cols, { item = shown == 0 and fish.id or nil, pad = 2, cont = shown > 0, colors = { INK, diff and DIFF[diff][1] or INK, MUTED }, anchor = shown == 0 and ("fish:" .. key) or nil })
				B.row({ "", (OVEN[r.name] and "Iron Oven. " or "") .. Learn(r) }, { 0.0, 1.0 }, { colors = { MUTED, MUTED }, cont = true })
				shown = shown + 1
			end
		end
		if shown == 0 and not fish.where:find("quest only") then idle[#idle + 1] = fish end
	end
	B.h("Not for the pot")
	for _, fish in ipairs(idle) do
		B.row({ fish.name, fish.use .. "." }, { 0.42, 0.58 }, { item = fish.id })
	end
	B.h("Eat a fish, catch a fish")
	B.note("These dishes raise your Fishing for 15 minutes. Eat before you cast.")
	for _, r in ipairs(d.RECIPES) do
		if Kind(r) == "fishing" then
			B.row({ DishName(r, tell), Effect(r), ("Cooking %d"):format(r.skill) }, { 0.5, 0.25, 0.25 }, { item = r.item })
		end
	end
end

function BUILD.table()
	Opener("table")
	Tables()
	local d = D()
	local level = Level()
	local tell = CanTell()
	B.h("How eating works")
	for _, line in ipairs(d.WELL_FED) do
		B.row({ "\194\183", line }, { 0.05, 0.95 }, { colors = { RED, INK }, pad = 4 })
	end
	B.h("At level 60")
	B.row({ "For", "Dish", "Why" }, { 0.2, 0.4, 0.4 }, { head = true })
	for i, t in ipairs(d.TABLE) do
		local r = BY_NAME[t[2]]
		local why = t[3] .. (r and OVEN[r.name] and " Iron Oven." or "") .. (r and (" Cooking %d."):format(r.skill) or "")
		B.row({ t[1], r and DishName(r, tell) or t[2], why }, { 0.2, 0.4, 0.4 }, { colors = { RED, INK, MUTED }, anchor = "table:" .. i })
	end
	B.h("No oven at the camp")
	for _, name in ipairs(d.NO_OVEN) do
		local r = BY_NAME[name]
		if r then B.row({ DishName(r, tell), Effect(r), ("Cooking %d"):format(r.skill) }, { 0.5, 0.25, 0.25 }, { item = r.item }) end
	end
	B.h("On the way up")
	if level then B.note(("You're level %d: your shelf is the gold one."):format(level)) end
	for _, shelf in ipairs(d.LEVELING) do
		local mine = level and level >= shelf[1] and level <= shelf[2]
		B.row({ ("Level %d to %d"):format(shelf[1], shelf[2]), table.concat(shelf[3], ", ") }, { 0.24, 0.76 }, { colors = { mine and GOLD or RED, INK } })
	end
	B.note("Numbers are the guides'; a dish's own card (hover it) is the last word.")
end

-- Where an ingredient comes from, in a line. Beasts near your level first.
local function Source(id)
	local d = D()
	local note = d.PANTRY[ItemName(id)]
	if note then return note end
	local from = d.FROM[id]
	if not from then return "Nobody's written down where it comes from." end
	if from.kind == "vendor" then
		local sellers = Mine(from)
		if #sellers == 0 then return "Sold only by the other side's vendors." end
		local who = {}
		for i = 1, math.min(3, #sellers) do who[#who + 1] = Person(sellers[i]) end
		return "Sold by " .. table.concat(who, "; ") .. "."
	elseif from.kind == "drop" then
		local level = Level()
		local picks = {}
		for _, beast in ipairs(from) do picks[#picks + 1] = beast end
		if level then
			table.sort(picks, function(a, b)
				local da, db = math.abs((a[3] + a[4]) / 2 - level), math.abs((b[3] + b[4]) / 2 - level)
				if da ~= db then return da < db end
				return a[1] < b[1]
			end)
		end
		local who = {}
		for i = 1, math.min(3, #picks) do
			local p = picks[i]
			who[#who + 1] = ("%s (%s, %s)"):format(p[1], p[2], p[3] == p[4] and tostring(p[3]) or (p[3] .. "-" .. p[4]))
		end
		local more = (from.n or 0) - #who
		return table.concat(who, "; ") .. (more > 1 and ("; %d more kinds drop it"):format(more) or more == 1 and "; one more kind drops it" or "") .. "."
	end
	return d.KINDS_OF_SOURCE[from.kind] or ""
end

local SHELVES = {
	{ "drop", "Meat, eggs and parts", "Hunted. The beasts nearest your level come first." },
	{ "fish", "From the water" },
	{ "vendor", "From particular shops" },
	{ "shop", "From any shop" },
	{ "object", "Gathered and found" },
}

function BUILD.pantry()
	Opener("pantry")
	Tables()
	local d = D()
	local shelves = {}
	for id in pairs(USES) do
		local kind = d.FROM[id] and d.FROM[id].kind or "object"
		shelves[kind] = shelves[kind] or {}
		table.insert(shelves[kind], id)
	end
	for _, shelf in ipairs(SHELVES) do
		local list = shelves[shelf[1]]
		if list then
			table.sort(list, function(a, b) return ItemName(a) < ItemName(b) end)
			B.h(shelf[2])
			if shelf[3] then B.note(shelf[3]) end
			for _, id in ipairs(list) do
				local dishes = {}
				for _, r in ipairs(USES[id]) do
					if not GHOST[r.name] then dishes[#dishes + 1] = r.name end
				end
				if #dishes > 0 then
					local have = Have(id)
					B.row({ ItemName(id) .. (have > 0 and ("  x%d"):format(have) or ""), Source(id) }, { 0.36, 0.64 },
						{ item = id, pad = 2, anchor = "item:" .. id })
					B.row({ "", "For: " .. table.concat(dishes, ", ", 1, math.min(6, #dishes)) .. (#dishes > 6 and (" and %d more"):format(#dishes - 6) or "") .. "." },
						{ 0.0, 1.0 }, { colors = { MUTED, MUTED }, cont = true })
				end
			end
		end
	end
end

function BUILD.camp()
	Opener("camp")
	Tables()
	local d = D()
	local tell = CanTell()
	for _, rule in ipairs(d.CAMP_RULES) do
		B.row({ "\194\183", rule }, { 0.05, 0.95 }, { colors = { RED, INK }, pad = 4 })
	end
	for _, name in ipairs(d.CAMP) do
		local r = BY_NAME[name]
		if r then
			B.h(("%s (skill %d)"):format(name, r.skill), nil, "recipe:" .. name)
			B.row({ "Makes", (tell and Knows(r) and TICK or "") .. name }, { 0.24, 0.76 }, { item = r.item, colors = { RED, INK } })
			if #r.needs > 0 then B.row({ "Needs", Needs(r) }, { 0.24, 0.76 }, { colors = { RED, INK } }) end
			B.row({ "Does", Effect(r) .. "." }, { 0.24, 0.76 }, { colors = { RED, INK } })
			B.row({ "Learn", Learn(r) }, { 0.24, 0.76 }, { colors = { RED, MUTED } })
		end
	end
	B.h("What the oven cooks")
	for _, name in ipairs(d.OVEN) do
		local r = BY_NAME[name]
		if r then B.row({ DishName(r, tell), Effect(r), ("Cooking %d"):format(r.skill) }, { 0.5, 0.25, 0.25 }, { item = r.item }) end
	end
	B.h("Merchant's Favor")
	B.p(d.FAVOR, INK, 13)
	B.h("Legacy talents")
	for i, t in ipairs(d.TALENTS) do
		B.row({ t[1], t[2] }, { 0.3, 0.7 }, { anchor = "talent:" .. i })
	end
	B.flourish()
	B.hand("Put the oven down, light the fire, cook the good stuff. Everyone at the camp will suddenly be your friend.")
end

function BUILD.tales()
	Opener("tales")
	local d = D()
	B.h("Heard over a stew")
	for i, l in ipairs(d.LEGENDS) do
		if i > 1 then B.flourish(0.3) end
		B.sub(l.title, "legend:" .. i)
		B.hand(l.text, 4)
	end
	B.h("Tall tales", RED)
	B.note("Claims from a single source we couldn't confirm. Kept apart, for the honest.")
	for i, t in ipairs(d.TALL_TALES) do
		B.h(t[1], MUTED, "tale:" .. i)
		B.p(t[2], INK, 13)
	end
	B.gap(6)
	B.note("Recipes, reagents, sellers and drops: AtlasLoot, WhatsTraining and Questie's databases for patch 1.60.1. Effects, routes and camp lore: warcrafttavern.com, wow-professions.com, wow.gg, warcraft.wiki.gg, Wowhead, theforeverguides.com and others (November 2026). Beta-era numbers may still move.")
end

---------------------------------------------------------------------------
-- Search rows, linked names, the footer.

spec.index = function(Add)
	Tables()
	local d = D()
	for _, r in ipairs(d.RECIPES) do
		local chapter = CAMP_ITEM[r.name] and "camp" or "recipes"
		local effect = Effect(r)
		Add(chapter, "recipe:" .. r.name, r.name, ("Cooking %d. %s. %s%s"):format(r.skill, Needs(r), effect ~= "" and (effect .. ". ") or "", Learn(r)), r.item)
	end
	for id in pairs(USES) do
		Add("pantry", "item:" .. id, ItemName(id), Source(id), id)
	end
	for i, r in ipairs(d.RANKS) do Add("route", "rank:" .. i, r[1] .. " Cooking", r[3], r.item) end
	for i, step in ipairs(d.ROUTE) do Add("route", "route:" .. i, "Route " .. step[1], step[2] .. " " .. step[3] .. " " .. step[4]) end
	for _, id in ipairs(d.TRAINERS) do
		local n = d.NPC[id]
		if n and not Enemy(n[5]) then Add("route", "trainer:" .. n[1], n[1] .. " (trainer)", Person(id)) end
	end
	for _, quest in ipairs(d.QUESTS) do
		if not Enemy(quest.side) then Add("route", "quest:" .. quest[1], quest[1] .. " (quest)", ("%s, %s. %s"):format(quest[2], quest[3], quest[4])) end
	end
	for i, t in ipairs(d.TABLE) do Add("table", "table:" .. i, t[1] .. ": " .. t[2], t[3]) end
	for i, t in ipairs(d.TALENTS) do Add("camp", "talent:" .. i, t[1], t[2]) end
	for i, t in ipairs(d.TALL_TALES) do Add("tales", "tale:" .. i, t[1], t[2]) end
	for i, l in ipairs(d.LEGENDS) do Add("tales", "legend:" .. i, "Tale: " .. l.title, l.text) end
end

spec.names = function()
	local list = {}
	for id, name in pairs(D().ITEM) do list[#list + 1] = { name, id } end
	-- The catch too, so a fish reads the same in both books.
	for _, fish in pairs(ns.FishingData and ns.FishingData.FISH or {}) do
		if fish.id then list[#list + 1] = { fish.name, fish.id } end
	end
	return list
end

spec.status = function()
	local rank, cap = C.Skill()
	local log = Log()
	local skill = rank and ("Cooking %d/%d"):format(rank, cap) or "No cooking yet"
	local kinds = 0
	for _ in pairs(log and log.cooked or {}) do kinds = kinds + 1 end
	return skill, ("%s dishes  \194\183  %d kinds"):format(Commas(log and log.total or 0), kinds)
end

spec.onShow = function()
	CheckSkill()
	CheckRecipes()
end
book.build = BUILD

---------------------------------------------------------------------------
-- The doors in.

C.Render, C.Refresh, C.Select, C.Jump, C.Find = book.Render, book.Refresh, book.Select, book.Jump, book.Find
C.Search, C.Toggle, C.Open, C.ResetPosition, C.ApplySettings = book.Search, book.Toggle, book.Open, book.ResetPosition, book.ApplySettings
C.Write = book.Write

function C.PreviewToast()
	local lines = D().LINES.dish
	local log = Log()
	Book.Toast(book, Fill(lines[math.random(#lines)], { dish = "Herb Baked Egg", zone = "Elwynn Forest" }), log and log.dayCount or 1)
end

-- Forget this character's kitchen diary.
function C.Clear()
	local log = Log()
	if not log then return end
	wipe(log.cooked) wipe(log.names) wipe(log.entries) wipe(log.days) wipe(log.known)
	log.total, log.dayCount, log.fish, log.batch = 0, 0, 0, 0
	log.started, log.skillSeen, log.rankSeen, log.scanned, log.decks, log.story, log.greyDay, log.batchDay = nil, nil, nil, nil, nil, nil, nil, nil
	book.Refresh()
end

function C.Init()
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL", "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED",
		"NEW_RECIPE_LEARNED", "SPELLS_CHANGED", "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "ZONE_CHANGED_NEW_AREA" }) do
		pcall(events.RegisterEvent, events, event)
	end
	if not pcall(events.RegisterUnitEvent, events, "UNIT_SPELLCAST_SUCCEEDED", "player") then
		pcall(events.RegisterEvent, events, "UNIT_SPELLCAST_SUCCEEDED")
	end
	local pending = false
	events:SetScript("OnEvent", function(_, event, ...)
		if event == "UNIT_SPELLCAST_SUCCEEDED" then
			ns.Try("cookbook cast", OnCast, ...)
		elseif event == "BAG_UPDATE_DELAYED" or event == "ZONE_CHANGED_NEW_AREA" then
			book.Refresh("larder")
		elseif event == "SKILL_LINES_CHANGED" or event == "CHAT_MSG_SKILL" or event == "PLAYER_ENTERING_WORLD" then
			ns.Try("cookbook skill", CheckSkill)
			if event == "PLAYER_ENTERING_WORLD" then ns.Try("cookbook recipes", CheckRecipes, false) end
			book.Refresh("larder")
		elseif not pending and C_Timer then
			-- Recipes changed: one look, shortly (these events come in bursts).
			pending = true
			C_Timer.After(0.5, function()
				pending = false
				ns.Try("cookbook recipes", CheckRecipes)
				book.Refresh()
			end)
		end
	end)
end
