SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.Journal = ns.Journal or {}
local J = ns.Journal

BINDING_NAME_SANCTUARYUIFISHING = "Angler's journal"

-- The angler's journal: a D3 window (the inventory's header with a fish in its medallion, the
-- stone body) holding a parchment page, with D3's red side tabs for chapters. The book itself
-- is FishingData.lua; this file draws it, reads where you stand and what you fish, and keeps a
-- per-character diary that writes itself on firsts and milestones.
--
-- Art: journal.png (tools/build_journal_art.py): header 600x155 at 0,0, the page 640x640 at
-- 0,160, tabs 64x96 from y 800 (three per chapter: resting, hover, selected). The body and
-- footer stone come from bag-frame.png like the bag window's.

local ATLAS = 1024
local ART_W = 600
local HEADER_H = 155
local BODY = { y = 155, h = 300 }
local FOOTER = { y = 455, h = 207 }
local SIDE = 14
local FOOTER_SQUASH = 0.40
local CLOSE = { x = 555, y = 8, w = 35, h = 35 }
local PAGE = { y = 160, size = 640 }
local TAB = { w = 64, h = 96, y = 800, per = 16 }

local WIDTH = 540 -- the window, before the user's scale
local BODY_H = 480
local TAB_SIZE = { 42, 63 }
local TAB_STEP = 60
local TAB_TUCK = 8 -- the straight edge of the tab art, tucked under the frame's border
local MARGIN = { x = 34, top = 30, bottom = 30 } -- the text area inside the page

local INK = { 0.20, 0.12, 0.05 }
local RED = { 0.50, 0.08, 0.03 }
local MUTED = { 0.40, 0.30, 0.19 }
local GREEN = { 0.12, 0.36, 0.08 }
local AMBER = { 0.58, 0.34, 0.03 }
local GOLD = { 0.62, 0.42, 0.06 }

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

local function Readable(v)
	return v ~= nil and not ns.Secret(v)
end

local function Commas(n)
	local s = tostring(math.floor(n or 0))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function Pick(list)
	return list[math.random(#list)]
end

local function Fill(text, fields)
	return (text:gsub("{(%w+)}", function(key) return fields[key] ~= nil and tostring(fields[key]) or "" end))
end

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
	local fname = FishingName()
	local function Plain(rank, cap, bonus)
		if not Readable(rank) or not Readable(cap) then return end
		return rank, cap, Readable(bonus) and bonus or 0
	end
	if GetProfessions and GetProfessionInfo then
		local ok, a, b, c, d, e = pcall(GetProfessions)
		if ok then
			for _, index in pairs({ a, b, c, d, e }) do
				local ok2, name, _, rank, cap, _, _, line, bonus = pcall(GetProfessionInfo, index)
				if ok2 and (line == FISHING_SKILL or name == fname) then
					return Plain(rank, cap, bonus)
				end
			end
		end
	end
	if C_SkillInfo and C_SkillInfo.GetNumSkillLines and C_SkillInfo.GetSkillLineInfo then
		local ok, count = pcall(C_SkillInfo.GetNumSkillLines)
		for i = 1, ok and count or 0 do
			local ok2, info = pcall(C_SkillInfo.GetSkillLineInfo, i)
			if ok2 and type(info) == "table" and not info.isHeader and (info.skillID == FISHING_SKILL or info.name == fname) then
				return Plain(info.rank, info.maxRank, (info.modifier or 0) + (info.tempPoints or 0))
			end
		end
	end
	if GetNumSkillLines and GetSkillLineInfo then
		for i = 1, GetNumSkillLines() do
			local name, header, _, rank, temp, bonus, cap = GetSkillLineInfo(i)
			if not header and name == fname then
				return Plain(rank, cap, (bonus or 0) + (temp or 0))
			end
		end
	end
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

-- Realm clock: hour, minute; calendar: weekday (1 = Sunday), month.
local function Clock()
	local hour, minute = 12, 0
	if GetGameTime then
		local h, m = GetGameTime()
		if Readable(h) then hour, minute = h, m or 0 end
	end
	local weekday, month
	if C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime then
		local ok, t = pcall(C_DateAndTime.GetCurrentCalendarTime)
		if ok and type(t) == "table" then weekday, month = t.weekday, t.month end
	end
	return hour, minute, weekday, month
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

local function Today()
	return date("%Y-%m-%d")
end

-- The diary's day number: days you fished, counted.
local function DayNumber(log)
	local today = Today()
	if not log.days[today] then
		log.days[today] = true
		log.dayCount = (log.dayCount or 0) + 1
	end
	return log.dayCount
end

local MAX_ENTRIES = 300

-- quality: the find's rarity when the line is about a rare find (2 uncommon and up).
function J.Write(text, quality)
	local log = Log()
	if not log or not Opt().diary then return end
	local entries = log.entries
	local day = DayNumber(log)
	entries[#entries + 1] = { t = time(), day = day, text = text, q = quality }
	while #entries > MAX_ENTRIES do table.remove(entries, 1) end
	if Opt().chat then
		print("|cffd8b86aAngler's journal:|r |cffe6dfd0" .. text .. "|r")
	end
	if Opt().toast and J.Toast then J.Toast(text, day, quality) end
	J.Refresh("diary")
end

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
		J.Write(Fill(Pick(lines.treasure), fields))
		return
	end
	if quality == 0 and not FishByID()[id] then
		log.junk = (log.junk or 0) + 1
		local key = zone .. "|" .. Today()
		if not log.junkDays[key] then
			log.junkDays[key] = true
			J.Write(Fill(Pick(lines.junk), fields))
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
			local line = named or (bloated and lines.bloated) or Pick(lines.rare[rarity])
			J.Write(Fill(line, fields), rarity)
		end
	elseif before == 0 then
		J.Write(Fill(lines.first[1], fields))
	elseif fresh then
		local line = lines.special[id] or (name:find("Whimsyfin") and lines.whimsyfin) or Pick(lines.species)
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
-- The page: a small layout engine. Builders add blocks top to bottom; widgets are pooled.

local frame, scroll, child
local anchors = {} -- search anchor -> { top, h } on the page drawn last
J.anchors = anchors
local pools = { text = {}, row = {}, icon = {}, rule = {}, band = {}, diamond = {} }
local used = { text = 0, row = 0, icon = 0, rule = 0, band = 0, diamond = 0 }
local cursor, width = 0, 0
local fontRetry = false

local function Face(fs, which, size)
	local opt = Opt()
	local key = which == "hand" and opt.diaryFont or which == "title" and "exocet" or opt.pageFont
	local path = ns.Fonts and ns.Fonts.Path and ns.Fonts.Path("body", key) or STANDARD_TEXT_FONT
	size = size * (opt.textScale or 1)
	if not path or fs:SetFont(path, size, "") == false or not fs:GetFont() then
		fs:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, "")
		fontRetry = true
	end
end

local function Take(kind, make)
	used[kind] = used[kind] + 1
	local widget = pools[kind][used[kind]]
	if not widget then
		widget = make()
		pools[kind][used[kind]] = widget
	end
	widget:Show()
	return widget
end

local Linkify -- item names to links (defined with the rows, below)

local function Text(which, size, color, text, x, w, justify, dy)
	local fs = Take("text", function()
		local s = child:CreateFontString(nil, "OVERLAY")
		s:SetWordWrap(true)
		s:SetNonSpaceWrap(false)
		return s
	end)
	Face(fs, which, size)
	fs:SetAlpha(1)
	fs:SetTextColor(color[1], color[2], color[3], 1)
	fs:SetJustifyH(justify or "LEFT")
	fs:SetJustifyV("TOP")
	fs:SetSpacing(which == "hand" and 3 or 2)
	fs:ClearAllPoints()
	fs:SetPoint("TOPLEFT", child, "TOPLEFT", x, -(cursor + (dy or 0)))
	fs:SetWidth(w)
	fs:SetText(which == "title" and text or Linkify(text))
	return fs, fs:GetStringHeight() or size
end

-- A row's tooltip: its item's card, and/or a line saying what a click does (search results).
local function RowTooltip(row)
	if not row.itemID and not row.tip then return end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	if row.itemID and GameTooltip.SetItemByID then
		GameTooltip:SetItemByID(row.itemID)
		if row.tip then GameTooltip:AddLine(row.tip, 1, 0.82, 0.45, true) end
		GameTooltip:AddLine("Shift-click to link it.", 0.6, 0.6, 0.6)
	else
		GameTooltip:SetText(row.tip or "", 1, 0.82, 0.45, 1, true)
	end
	GameTooltip:Show()
end

local function RowClick(row)
	if row.itemID and IsModifiedClick and IsModifiedClick("CHATLINK") then
		local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
		local _, link = getInfo(row.itemID)
		if link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
		return
	end
	if row.onClick then row.onClick() end
end

local function RowFrame()
	return Take("row", function()
		local row = CreateFrame("Button", nil, child)
		row:RegisterForClicks("LeftButtonUp")
		local hl = row:CreateTexture(nil, "BACKGROUND")
		hl:SetAllPoints()
		hl:SetColorTexture(0.35, 0.2, 0.05, 0.10)
		row:SetHighlightTexture(hl)
		row:SetScript("OnEnter", RowTooltip)
		row:SetScript("OnLeave", GameTooltip_Hide)
		row:SetScript("OnClick", RowClick)
		return row
	end)
end

-- Item names on the page: linked (hover for the card, shift-click to link) and in their
-- rarity's colour, darkened for parchment so common white reads as ink. Names come from the book
-- and from what you've caught. An item the client hasn't loaded yet is asked for, and the page
-- redrawn when it arrives.
local QUALITY_INK = {
	[0] = { 0.42, 0.40, 0.37 }, [1] = INK, [2] = { 0.10, 0.44, 0.02 }, [3] = { 0.00, 0.32, 0.68 },
	[4] = { 0.47, 0.16, 0.72 }, [5] = { 0.76, 0.38, 0.00 }, [6] = { 0.62, 0.48, 0.20 }, [7] = { 0.00, 0.50, 0.70 },
}
local RARITY = { [2] = "Uncommon", [3] = "Rare", [4] = "Epic", [5] = "Legendary" }

-- A rarity's colour in the game's own shades (dark backgrounds).
local QUALITY_RGB = { [2] = { 0.12, 1, 0 }, [3] = { 0, 0.44, 0.87 }, [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 } }
local function QualityRGB(q)
	if C_Item and C_Item.GetItemQualityColor then
		local ok, r, g, b = pcall(C_Item.GetItemQualityColor, q)
		if ok and type(r) == "number" then return { r, g, b } end
	end
	return QUALITY_RGB[q] or { 1, 1, 1 }
end

local asked = {} -- item IDs requested from the client
local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

local function Quality(id)
	local q = C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(id)
	if q == nil and GetInfo then q = select(3, GetInfo(id)) end
	if q == nil then
		-- What the loot window said when you caught it.
		local log = Log()
		q = log and log.quality and log.quality[id]
		if q then return q end
		if not asked[id] then
			asked[id] = true
			J.waiting = true
			if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
		end
		return
	end
	return Readable(q) and q or nil
end

local function Hex(c)
	return ("%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255)
end

-- The colour for an item: on the page (parchment), or the game's own (dark backgrounds).
local function ItemHex(id, dark)
	local q = Quality(id)
	if dark then
		if q and C_Item and C_Item.GetItemQualityColor then
			local ok, r, g, b = pcall(C_Item.GetItemQualityColor, q)
			if ok and r then return Hex({ r, g, b }) end
		end
		return q == 1 and "ffffff" or "f0d9a8"
	end
	return Hex(q and QUALITY_INK[q] or INK)
end

local NAMES -- { name, id }, longest first
local function Names()
	if NAMES then return NAMES end
	local d, seen, list = D(), {}, {}
	local function Add(name, id)
		-- "Fishing Pole" alone is too common a phrase (a quest is named after one).
		if name and id and not seen[name] and name ~= "Fishing Pole" then
			seen[name] = true
			list[#list + 1] = { name, id }
		end
	end
	for _, f in pairs(d.FISH) do Add(f.name, f.id) end
	for _, rows in ipairs({ d.POLES, d.LURES, d.FOOD, d.GEAR }) do
		for _, r in ipairs(rows) do Add(r[1], r[2]) end
	end
	for _, c in ipairs(d.CAMP) do Add(c[1], c[2]) end
	for _, c in ipairs(d.EXTRAVAGANZA.coin) do Add(c[1], c[2]) end
	for name, id in pairs(d.ITEMS) do Add(name, id) end
	table.sort(list, function(a, b) return #a[1] > #b[1] end)
	NAMES = list
	return list
end

-- text with every item name it holds coloured, and linked unless dark (a frame that can't
-- take hyperlinks).
function Linkify(text, dark)
	if type(text) ~= "string" or not text:find("%u") then return text end
	local hits = {}
	local function Free(a, b)
		for _, h in ipairs(hits) do
			if a <= h[2] and b >= h[1] then return false end
		end
		return true
	end
	local function Try(name, id)
		local from = 1
		while true do
			local a, b = text:find(name, from, true)
			if not a then return end
			local before, after = text:sub(a - 1, a - 1), text:sub(b + 1, b + 1)
			if not before:find("[%w]") and not after:find("[%w]") and Free(a, b) then
				hits[#hits + 1] = { a, b, id }
			end
			from = b + 1
		end
	end
	for _, n in ipairs(Names()) do Try(n[1], n[2]) end
	local log = Log()
	for id, name in pairs(log and log.names or {}) do
		if type(name) == "string" and #name > 3 then Try(name, id) end
	end
	if #hits == 0 then return text end
	table.sort(hits, function(x, y) return x[1] < y[1] end)
	local out, at = {}, 1
	for _, h in ipairs(hits) do
		out[#out + 1] = text:sub(at, h[1] - 1)
		local name = text:sub(h[1], h[2])
		if dark then
			out[#out + 1] = ("|cff%s%s|r"):format(ItemHex(h[3], true), name)
		else
			out[#out + 1] = ("|cff%s|Hitem:%d|h%s|h|r"):format(ItemHex(h[3]), h[3], name)
		end
		at = h[2] + 1
	end
	out[#out + 1] = text:sub(at)
	return table.concat(out)
end
J.Linkify = Linkify

local function ItemIcon(id)
	local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
	if not icon and GetItemIcon then icon = GetItemIcon(id) end
	return icon
end

-- The blocks. Every heading is ruled; table rows alternate a faint band and are parted by a
-- hairline, so a page reads as rows rather than one run of text. A row with o.cont belongs to
-- the item above it (the same band, no line between).
local B = {}
local stripe = 0 -- rows since the last heading

local function Line(y, x, w, color, alpha)
	local t = Take("rule", function() return child:CreateTexture(nil, "ARTWORK") end)
	t:SetColorTexture(color[1], color[2], color[3], alpha)
	t:ClearAllPoints()
	t:SetPoint("TOPLEFT", child, "TOPLEFT", x, -y)
	t:SetSize(math.max(1, w), 1)
end

local function Band(top, h)
	local t = Take("band", function() return child:CreateTexture(nil, "BACKGROUND") end)
	t:SetColorTexture(0.45, 0.28, 0.10, 0.08)
	t:ClearAllPoints()
	t:SetPoint("TOPLEFT", child, "TOPLEFT", -4, -top)
	t:SetSize(width + 8, math.max(1, h))
end

-- A small square on its point, for the flourish.
local function Diamond(y, size)
	local t = Take("diamond", function() return child:CreateTexture(nil, "ARTWORK") end)
	t:SetColorTexture(RED[1], RED[2], RED[3], 0.65)
	t:ClearAllPoints()
	t:SetPoint("CENTER", child, "TOPLEFT", width / 2, -y)
	t:SetSize(size, size)
	if t.SetRotation then pcall(t.SetRotation, t, math.pi / 4) end
end

function B.gap(px)
	cursor = cursor + (px or 8)
end

function B.rule()
	Line(cursor, width * 0.15, width * 0.7, RED, 0.35)
	cursor = cursor + 8
end

-- A line, a diamond, a line: after a chapter's opening words and between diary entries.
function B.flourish(span)
	span = span or 0.5
	local y = cursor + 5
	local half = width * span / 2
	Line(y, width / 2 - half, half - 8, RED, 0.4)
	Line(y, width / 2 + 8, half - 8, RED, 0.4)
	Diamond(y + 0.5, 5)
	cursor = cursor + 14
end

function B.title(text)
	local _, h = Text("title", 19, RED, text:upper(), 0, width, "CENTER")
	cursor = cursor + h + 4
	B.rule()
end

function B.h(text, color, anchor)
	color = color or RED
	cursor = cursor + 12
	local _, h = Text("title", 13.5, color, text:upper(), 0, width)
	if anchor then anchors[anchor] = { top = cursor, h = h } end
	cursor = cursor + h + 1
	Line(cursor, 0, width, color, 0.45)
	cursor = cursor + 7
	stripe = 0
end

function B.hand(text, indent, color)
	indent = indent or 8
	local _, h = Text("hand", 15, color or INK, text, indent, width - indent)
	cursor = cursor + h + 6
end

function B.p(text, color, size)
	local _, h = Text("page", size or 13.5, color or INK, text, 0, width)
	cursor = cursor + h + 5
end

function B.note(text)
	B.p(text, MUTED, 12.5)
end

-- A line of columns. cols: texts; fr: their width shares. o.item: an item for icon and tooltip
-- (first column); o.head: column headings; o.color / o.colors: ink; o.cont: belongs to the row
-- above; o.dim: the other faction's (faded).
function B.row(cols, fr, o)
	o = o or {}
	if not o.head and not o.cont then stripe = stripe + 1 end
	local top = cursor
	local x, h = 0, 0
	local icon = o.item and ItemIcon(o.item)
	for i, text in ipairs(cols) do
		local w = width * fr[i]
		if w <= 0 then text = nil end
		local cx, cw = x, w - 8
		if i == 1 and o.item then cx, cw = x + 20, w - 28 end
		local color = (o.colors and o.colors[i]) or o.color or (i == 1 and not o.head and INK) or (o.head and RED) or MUTED
		if o.dim then color = MUTED end
		local which = o.head and "title" or "page"
		local size = o.head and 10.5 or (i == 1 and 13 or 12.5)
		if text and text ~= "" then
			local fs, th = Text(which, size, color, text, cx, cw)
			if o.dim then fs:SetAlpha(0.7) else fs:SetAlpha(1) end
			h = math.max(h, th)
		end
		x = x + w
	end
	if icon then
		local t = Take("icon", function() return child:CreateTexture(nil, "ARTWORK") end)
		t:SetTexture(icon)
		t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		t:SetDesaturated(o.dim and true or false)
		t:ClearAllPoints()
		t:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(top - 1))
		t:SetSize(16, 16)
		h = math.max(h, 16)
	end
	if o.anchor then anchors[o.anchor] = { top = top, h = h } end
	if o.item or o.onClick then
		local row = RowFrame()
		row.itemID, row.onClick, row.tip = o.item, o.onClick, o.tip
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", child, "TOPLEFT", -2, -(top - 2))
		-- A plain item row covers its name only: the other columns' links stay hoverable.
		row:SetSize((o.onClick and width or width * fr[1]) + 4, h + 4)
	end
	local pad = o.pad or 7
	if o.head then
		Line(top + h + 2, 0, width, RED, 0.3)
		stripe = 0
	else
		if stripe % 2 == 0 then Band(top - 3, h + pad) end
		if not o.cont and stripe > 1 then Line(top - 3, 0, width, INK, 0.13) end
	end
	cursor = top + h + pad
end

-- A label and its value on one line.
function B.kv(label, value, color)
	B.row({ label, value }, { 0.3, 0.7 }, { colors = { RED, color or INK } })
end

---------------------------------------------------------------------------
-- Factions. Your side reads first and plain; the other side's things are faded and say so.

local function MySide()
	local faction = UnitFactionGroup and UnitFactionGroup("player")
	if not Readable(faction) then return end
	return faction == "Alliance" and "A" or faction == "Horde" and "H" or nil
end
J.MySide = MySide

local SIDE_NAME = { A = "Alliance", H = "Horde", N = "both" }

-- Is this the other faction's (A or H, not yours, and you have one)?
local function Enemy(side)
	local mine = MySide()
	return mine ~= nil and (side == "A" or side == "H") and side ~= mine
end

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

function B.opener(key)
	for _, line in ipairs(D().OPENERS[key] or {}) do
		B.hand(line)
	end
	local side = MySide()
	for _, line in ipairs(side and D().OPENERS[key .. side] or {}) do
		B.hand(line)
	end
	B.flourish()
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

function BUILD.diary()
	B.opener("diary")
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
	B.h("Entries")
	if not Opt().diary then
		B.note("The diary is paused (Options > Professions > Fishing journal).")
	end
	local entries = log.entries
	if #entries == 0 then
		B.hand("Empty. Go catch something. Anything. A boot counts. Sort of.")
		return
	end
	-- Newest first, under one heading per fishing day; a hairline between a day's entries.
	local shown, lastDay = 0, nil
	for i = #entries, 1, -1 do
		local e = entries[i]
		if e.day ~= lastDay then
			if lastDay then B.flourish(0.5) end
			cursor = cursor + 2
			local _, h = Text("title", 12.5, RED, ("Day %d"):format(e.day or 1):upper(), 0, width * 0.4)
			Text("page", 11.5, MUTED, date("%A, %d %B %Y", e.t), width * 0.35, width * 0.65, "RIGHT")
			cursor = cursor + h + 1
			Line(cursor, 0, width, RED, 0.35)
			cursor = cursor + 7
			lastDay = e.day
		else
			Line(cursor - 4, 44, width - 44, INK, 0.12)
		end
		local q = e.q and QUALITY_INK[e.q]
		Text(q and "title" or "page", q and 9.5 or 11, q or MUTED, q and RARITY[e.q] or date("%H:%M", e.t), 0, 42)
		local _, h = Text("hand", 15, INK, e.text, 44, width - 44)
		if q then
			-- A rare find's entry: a faint wash of its rarity behind it, and its time under the word.
			Text("page", 10.5, MUTED, date("%H:%M", e.t), 0, 42, nil, 13)
			local t = Take("band", function() return child:CreateTexture(nil, "BACKGROUND") end)
			t:SetColorTexture(q[1], q[2], q[3], 0.12)
			t:ClearAllPoints()
			t:SetPoint("TOPLEFT", child, "TOPLEFT", -4, -(cursor - 3))
			t:SetSize(width + 8, h + 6)
		end
		anchors["entry:" .. i] = { top = cursor, h = h }
		cursor = cursor + h + 9
		shown = shown + 1
		if shown >= 80 then
			B.note(("...and %d older entries, pressed between the pages."):format(#entries - shown))
			break
		end
	end
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
	B.opener("route")
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
	B.opener("waters")
	local eff, rank = Effective()
	local _, here = J.Where()
	B.note(("A zone's number is where nothing gets away; %d below it, nothing bites. Lures and poles count."):format(D().ESCAPE_GAP))
	if rank then
		B.note(("You fish at %d. Green: all yours. Ink: some escape. Grey: not yet. Faded: the other faction's land."):format(eff))
	end
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
	B.opener("catches")
	local log = Log()
	local have, total = 0, 0
	for _, key in ipairs(D().FISH_ORDER) do
		local fish = D().FISH[key]
		total = total + 1
		if Caught(fish.id) > 0 then have = have + 1 end
	end
	B.note(("Ticked: caught on this character (%d of %d). Hover a fish for its card, shift-click to link it."):format(have, total))
	B.h("Fish")
	for _, key in ipairs(D().FISH_ORDER) do
		local fish = D().FISH[key]
		local n = Caught(fish.id)
		local name = (n > 0 and "|TInterface\\RaidFrame\\ReadyCheck-Ready:13:13:0:-1|t " or "") .. fish.name .. (fish.forever and "  |cff9a6a0e(new)|r" or "")
		B.row({ name, fish.where }, { 0.42, 0.58 }, { item = fish.id, pad = 2, colors = { INK, MUTED }, anchor = "fish:" .. key })
		B.row({ "", fish.use .. ". " .. fish.quip }, { 0.0, 1.0 }, { colors = { MUTED, MUTED }, cont = true })
	end
	B.h("Not fish, still caught")
	for i, o in ipairs(D().OTHER_CATCHES) do
		B.row({ o.name, o.text }, { 0.32, 0.68 }, { anchor = "other:" .. i })
	end
	B.h("Cook it")
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
	B.opener("tackle")
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
	B.opener("camp")
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
	B.opener("extravaganza")
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
	B.opener("tales")
	-- The old legends, as diary entries: stories told at the inn.
	B.h("Old legends")
	for i, l in ipairs(D().LEGENDS) do
		if i > 1 then B.flourish(0.3) end
		local _, h = Text("title", 10.5, RED, l.title:upper(), 0, width)
		anchors["legend:" .. i] = { top = cursor, h = h }
		cursor = cursor + h + 3
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
-- Search: every row the book can find, with the chapter and the row (anchor) it lives on.

local function Index()
	local d, out = D(), {}
	local function Add(chapter, anchor, name, text, item)
		out[#out + 1] = { chapter = chapter, anchor = anchor, name = name, text = text or "", item = item, n = #out }
	end
	for _, c in ipairs(J.CHAPTERS) do Add(c.key, nil, c.title, c.tip) end
	for _, key in ipairs(d.FISH_ORDER) do
		local f = d.FISH[key]
		Add("catches", "fish:" .. key, f.name, ("%s. %s. %s"):format(f.where, f.use, f.quip), f.id)
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
	local log = Log()
	for i, e in ipairs(log and log.entries or {}) do
		Add("diary", "entry:" .. i, ("Day %d, %s"):format(e.day or 1, date("%d %b %H:%M", e.t)), e.text)
	end
	return out
end

local CHAPTER_ORDER = {}
for i, c in ipairs(J.CHAPTERS) do CHAPTER_ORDER[c.key] = i end

-- Rows matching every word of the query, best first: the whole query in the name, then every
-- word in the name, then anywhere.
function J.Find(query)
	local words = {}
	for word in query:lower():gmatch("%S+") do words[#words + 1] = word end
	if #words == 0 then return {} end
	local found = {}
	for _, row in ipairs(Index()) do
		local name, all = row.name:lower(), (row.name .. " " .. row.text):lower()
		local ok, inName = true, true
		for _, word in ipairs(words) do
			if not all:find(word, 1, true) then ok = false break end
			if not name:find(word, 1, true) then inName = false end
		end
		if ok then
			row.score = name:find(query:lower(), 1, true) and 3 or (inName and 2 or 1)
			found[#found + 1] = row
		end
	end
	table.sort(found, function(a, b)
		if a.score ~= b.score then return a.score > b.score end
		return a.n < b.n
	end)
	return found, words
end

-- A piece of the text around the first word that matched.
local function Snippet(text, words)
	local lower, at = text:lower(), nil
	for _, word in ipairs(words) do
		at = lower:find(word, 1, true)
		if at then break end
	end
	if not at or #text <= 110 then return text end
	local from = math.max(1, at - 40)
	local piece = text:sub(from, from + 109)
	return (from > 1 and "..." or "") .. piece .. (from + 109 < #text and "..." or "")
end

-- Open a chapter at one of its rows, and light the row for a moment.
function J.Jump(chapter, anchor)
	J.jump = anchor
	J.Select(chapter)
end

function BUILD.search()
	local query = J.query or ""
	local found, words = J.Find(query)
	if #found == 0 then
		B.hand(("Nothing by \"%s\". Maybe it got away."):format(query))
		B.note("Search looks at fish, zones, trainers, poles, lures, gear, food, camp objects, quests, prizes, recipes, tall tales and your diary.")
		return
	end
	B.note(("%d found for \"%s\". Click one to open its page; Enter opens the first."):format(#found, query))
	J.first = found[1]
	local shown = 0
	for _, c in ipairs(J.CHAPTERS) do
		local any = false
		for _, row in ipairs(found) do
			if row.chapter == c.key and shown < 80 then
				if not any then
					B.h(c.title)
					any = true
				end
				shown = shown + 1
				local r = row
				B.row({ r.name, Snippet(r.text, words) }, { 0.36, 0.64 }, {
					item = r.item, tip = "Open in " .. c.title,
					onClick = function() J.Jump(r.chapter, r.anchor) end,
				})
			end
		end
	end
end

-- The search box's text changed.
function J.SetQuery(text)
	text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if #text >= 2 then
		if J.chapter ~= "search" then J.before = J.chapter end
		J.query, J.chapter, J.first = text, "search", nil
		if scroll then scroll:SetVerticalScroll(0) end
		J.Render()
	elseif J.chapter == "search" then
		J.query = nil
		J.chapter = J.before or Opt().chapter or "now"
		J.Render()
	end
end

-- /sanctuary fish <words>: open the journal on a search.
function J.Search(text)
	if not frame or not frame:IsShown() then J.Toggle() end
	frame.search:SetText(text)
	J.SetQuery(text)
end

---------------------------------------------------------------------------
-- The window.

local function TabCoord(index, state)
	local i = (index - 1) * 3 + state -- state 0 resting, 1 hover, 2 selected
	local col, row = i % TAB.per, math.floor(i / TAB.per)
	local x, y = col * TAB.w, TAB.y + row * TAB.h
	return x / ATLAS, (x + TAB.w) / ATLAS, y / ATLAS, (y + TAB.h) / ATLAS
end

local function TabState(tab)
	local state = (J.chapter == tab.key) and 2 or (tab.over and 1 or 0)
	if tab.art.sanctuaryArt then tab.art:SetTexCoord(TabCoord(tab.index, state)) end
	tab:SetFrameLevel(frame:GetFrameLevel() + (state == 2 and 3 or 1))
end

local function UpdateTabs()
	for _, tab in ipairs(frame.tabs) do TabState(tab) end
end

local function Status()
	local rank, cap, bonus = J.Skill()
	local log = Log()
	local species = 0
	for _ in pairs(log and log.catches or {}) do species = species + 1 end
	-- Two lines on the footer's right: your rank, large; the tally under it.
	local skill = rank and ("Fishing %d/%d%s"):format(rank, cap, bonus > 0 and (" (+%d)"):format(bonus) or "") or "No fishing yet"
	return skill, ("%s fish  \194\183  %d kinds"):format(Commas(log and log.total or 0), species)
end

function J.Render()
	if not frame or not frame:IsShown() then return end
	for kind, list in pairs(pools) do
		for i = 1, used[kind] do list[i]:Hide() end
		used[kind] = 0
	end
	width = math.max(100, scroll:GetWidth())
	child:SetWidth(width)
	cursor = 0
	fontRetry = false
	wipe(anchors)
	frame.flash:Hide()
	local chapter
	for _, c in ipairs(J.CHAPTERS) do
		if c.key == J.chapter then chapter = c end
	end
	if J.chapter == "search" then chapter = { key = "search", title = "Search" } end
	chapter = chapter or J.CHAPTERS[1]
	B.title(chapter.title)
	local ok, err = ns.Try("journal " .. chapter.key, BUILD[chapter.key])
	if not ok then B.p("This page got wet: " .. tostring(err), RED) end
	cursor = cursor + 10
	child:SetHeight(math.max(1, cursor))
	local skill, tally = Status()
	frame.status:SetText(skill)
	frame.status2:SetText(tally)
	-- Arriving from a search result: bring its row up and light it.
	local spot = J.jump and anchors[J.jump]
	J.jump = nil
	if spot then
		local range = math.max(0, cursor - scroll:GetHeight())
		scroll:SetVerticalScroll(math.max(0, math.min(range, spot.top - 40)))
		frame.flash:ClearAllPoints()
		frame.flash:SetPoint("TOPLEFT", child, "TOPLEFT", -4, -(spot.top - 4))
		frame.flash:SetSize(width + 8, spot.h + 8)
		frame.flash:SetAlpha(1)
		frame.flash:Show()
		frame.flashT = 0
	end
	J.UpdateScroll()
	UpdateTabs()
	-- A face that wasn't ready yet (Fonts.lua preloads them): one more pass shortly.
	if fontRetry and not J.retried and C_Timer then
		J.retried = true
		C_Timer.After(1, J.Render)
	end
end

-- Redraw if the window shows that chapter (or any, when none is named).
function J.Refresh(key)
	if frame and frame:IsShown() and (not key or key == J.chapter) then
		J.Render()
	end
end

function J.UpdateScroll()
	local range = math.max(0, child:GetHeight() - scroll:GetHeight())
	local now = math.min(scroll:GetVerticalScroll() or 0, range)
	scroll:SetVerticalScroll(now)
	local thumb = frame.thumb
	if range <= 1 then
		thumb:Hide()
		return
	end
	local track = scroll:GetHeight()
	local size = math.max(24, track * track / (track + range))
	thumb:SetHeight(size)
	thumb:ClearAllPoints()
	thumb:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 8, -(track - size) * now / range)
	thumb:Show()
end

function J.Select(key)
	J.chapter = key
	Opt().chapter = key
	J.query = nil
	if frame and frame.search and (frame.search:GetText() or "") ~= "" then
		frame.search:SetText("")
		frame.search:ClearFocus()
	end
	if scroll then scroll:SetVerticalScroll(0) end
	J.Render()
end

local function Layout()
	local opt = Opt()
	local k = WIDTH / ART_W
	local side = SIDE * k
	local headerH = HEADER_H * k
	local footerH = FOOTER.h * k * FOOTER_SQUASH
	local height = headerH + BODY_H + footerH
	frame:SetSize(WIDTH, height)
	local art = frame.art
	art.header:SetSize(WIDTH, headerH)
	art.bodyL:SetSize(side, BODY_H)
	art.bodyR:SetSize(side, BODY_H)
	art.bodyM:ClearAllPoints()
	art.bodyM:SetPoint("TOPLEFT", side, -headerH)
	art.bodyM:SetPoint("BOTTOMRIGHT", art.bodyR, "BOTTOMLEFT")
	art.footer:SetSize(WIDTH, footerH)
	art.bodyL:SetPoint("TOPLEFT", 0, -headerH)
	art.bodyR:SetPoint("TOPRIGHT", 0, -headerH)
	frame.close:ClearAllPoints()
	frame.close:SetPoint("TOPLEFT", CLOSE.x * k, -CLOSE.y * k)
	frame.close:SetSize(CLOSE.w * k, CLOSE.h * k)
	-- The page fills the body, its torn edge on the stone.
	frame.page:ClearAllPoints()
	frame.page:SetPoint("TOPLEFT", side + 2, -(headerH - 4))
	frame.page:SetPoint("BOTTOMRIGHT", -(side + 2), footerH - 6)
	local pw = WIDTH - 2 * (side + 2)
	local ph = BODY_H + 10
	local mx = MARGIN.x * pw / PAGE.size
	scroll:ClearAllPoints()
	scroll:SetPoint("TOPLEFT", frame.page, "TOPLEFT", mx, -MARGIN.top * ph / PAGE.size)
	scroll:SetPoint("BOTTOMRIGHT", frame.page, "BOTTOMRIGHT", -mx - 6, MARGIN.bottom * ph / PAGE.size)
	frame.search:ClearAllPoints()
	frame.search:SetPoint("LEFT", art.footer, "LEFT", side + 36, 2)
	frame.search:SetSize(190, 26)
	frame.status:ClearAllPoints()
	frame.status:SetPoint("BOTTOMRIGHT", art.footer, "RIGHT", -(side + 16), 3)
	frame.status:SetWidth(WIDTH - 2 * side - 30 - 225)
	frame.status:SetJustifyH("RIGHT")
	frame.status:SetHeight(17)
	frame.status2:ClearAllPoints()
	frame.status2:SetPoint("TOPRIGHT", frame.status, "BOTTOMRIGHT", 0, -3)
	frame.status2:SetWidth(WIDTH - 2 * side - 30 - 225)
	frame.status2:SetJustifyH("RIGHT")
	frame.status2:SetHeight(14)
	for i, tab in ipairs(frame.tabs) do
		tab:ClearAllPoints()
		tab:SetPoint("TOPLEFT", frame, "TOPRIGHT", -TAB_TUCK, -(headerH + 2 + (i - 1) * TAB_STEP))
		tab:SetSize(TAB_SIZE[1], TAB_SIZE[2])
	end
	frame:SetScale(opt.scale or 1)
	frame:ClearAllPoints()
	frame:SetPoint(opt.point or "LEFT", UIParent, opt.point or "LEFT", opt.x or 60, opt.y or 0)
end

local function Piece(slot, x0, y0, x1, y1, layer, sub)
	local tex = frame:CreateTexture(nil, layer or "BACKGROUND", nil, sub)
	if ns.Art.Apply(tex, slot) then
		tex:SetTexCoord(x0 / ATLAS, x1 / ATLAS, y0 / ATLAS, y1 / ATLAS)
		tex.sanctuaryArt = true
	else
		tex:SetColorTexture(0.06, 0.05, 0.04, 0.96)
	end
	return tex
end

local function Build()
	ns.Art.Require("journal")
	frame = CreateFrame("Frame", "SanctuaryUIFishingJournal", UIParent)
	frame:SetFrameStrata("MEDIUM")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		self:SetUserPlaced(false)
		local opt = Opt()
		local point, _, _, x, y = self:GetPoint(1)
		opt.point, opt.x, opt.y, opt.moved = point or "LEFT", x or 0, y or 0, true
	end)
	frame:Hide()
	tinsert(UISpecialFrames, frame:GetName())

	local journalArt = ns.Art.Path("journal") and "journal" or "bagFrame"
	frame.art = {
		header = Piece(journalArt, 0, 0, ART_W, HEADER_H, "ARTWORK"),
		bodyL = Piece("bagFrame", 0, BODY.y, SIDE, BODY.y + BODY.h),
		bodyM = Piece("bagFrame", SIDE, BODY.y, ART_W - SIDE, BODY.y + BODY.h),
		bodyR = Piece("bagFrame", ART_W - SIDE, BODY.y, ART_W, BODY.y + BODY.h),
		footer = Piece("bagFrame", 0, FOOTER.y, ART_W, FOOTER.y + FOOTER.h),
	}
	frame.art.header:SetPoint("TOPLEFT")
	frame.art.footer:SetPoint("BOTTOMLEFT")
	frame.page = frame:CreateTexture(nil, "BORDER")
	if ns.Art.Apply(frame.page, "journal") then
		frame.page:SetTexCoord(0, PAGE.size / ATLAS, PAGE.y / ATLAS, (PAGE.y + PAGE.size) / ATLAS)
	else
		frame.page:SetColorTexture(0.80, 0.70, 0.52, 1)
	end

	local close = CreateFrame("Button", nil, frame)
	local glow = close:CreateTexture(nil, "HIGHLIGHT")
	glow:SetAllPoints()
	glow:SetColorTexture(1, 0.6, 0.3, 0.25)
	glow:SetBlendMode("ADD")
	close:SetScript("OnClick", function() frame:Hide() end)
	frame.close = close

	scroll = CreateFrame("ScrollFrame", nil, frame)
	scroll:EnableMouseWheel(true)
	child = CreateFrame("Frame", nil, scroll)
	child:SetSize(400, 10)
	scroll:SetScrollChild(child)
	-- Links in the text: hover for the item's card, shift-click to put it in chat. The page
	-- takes the mouse for them, so it passes drags to the window and the wheel to the scroll.
	pcall(child.SetHyperlinksEnabled, child, true)
	child:EnableMouse(true)
	child:EnableMouseWheel(true)
	child:RegisterForDrag("LeftButton")
	child:SetScript("OnDragStart", function() frame:StartMoving() end)
	child:SetScript("OnDragStop", function() frame:GetScript("OnDragStop")(frame) end)
	child:SetScript("OnMouseWheel", function(_, delta) scroll:GetScript("OnMouseWheel")(scroll, delta) end)
	child:SetScript("OnHyperlinkEnter", function(self, link)
		GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
		if pcall(GameTooltip.SetHyperlink, GameTooltip, link) then
			GameTooltip:AddLine("Shift-click to link it.", 0.6, 0.6, 0.6)
			GameTooltip:Show()
		end
	end)
	child:SetScript("OnHyperlinkLeave", GameTooltip_Hide)
	child:SetScript("OnHyperlinkClick", function(_, link)
		local id = type(link) == "string" and tonumber(link:match("item:(%d+)"))
		if id and IsModifiedClick and IsModifiedClick("CHATLINK") then
			local _, full = GetInfo(id)
			if full and ChatEdit_InsertLink then ChatEdit_InsertLink(full) end
		end
	end)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local range = math.max(0, child:GetHeight() - self:GetHeight())
		self:SetVerticalScroll(math.max(0, math.min(range, (self:GetVerticalScroll() or 0) - delta * 48)))
		J.UpdateScroll()
	end)
	scroll:SetScript("OnSizeChanged", function() J.Render() end)
	local thumb = frame:CreateTexture(nil, "ARTWORK")
	thumb:SetColorTexture(RED[1], RED[2], RED[3], 0.45)
	thumb:SetWidth(3)
	frame.thumb = thumb

	-- The light on a row reached from a search.
	frame.flash = child:CreateTexture(nil, "BACKGROUND", nil, 2)
	frame.flash:SetColorTexture(0.95, 0.68, 0.18, 0.35)
	frame.flash:Hide()

	-- Search: Blizzard's box (magnifier, clear button, hint) on a D3 plate, like the bags'.
	local search = CreateFrame("EditBox", "SanctuaryUIFishingJournalSearch", frame, "SearchBoxTemplate")
	search:SetAutoFocus(false)
	for _, key in ipairs({ "Left", "Middle", "Right", "Mid" }) do
		if search[key] then search[key]:SetAlpha(0) end
	end
	local plate = search:CreateTexture(nil, "BACKGROUND", nil, -1)
	plate:SetPoint("TOPLEFT", -22, 5)
	plate:SetPoint("BOTTOMRIGHT", 6, -5)
	if ns.Art.Apply(plate, "d3Button") then
		plate:SetTexCoord(0, 120 / 128, 0, 52 / 64)
	else
		plate:SetColorTexture(0.1, 0.05, 0.04, 0.9)
	end
	if search.Instructions then search.Instructions:SetText("Search the journal") end
	if ns.Fonts and ns.Fonts.Set then
		ns.Fonts.Set(search, "body", 14, "")
		if search.Instructions then ns.Fonts.Set(search.Instructions, "body", 14, "") end
	end
	search:HookScript("OnTextChanged", function(self)
		J.SetQuery(self:GetText())
	end)
	search:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		local first = J.first
		if J.chapter == "search" and first then J.Jump(first.chapter, first.anchor) end
	end)
	search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	frame.search = search

	frame.status = frame:CreateFontString(nil, "OVERLAY")
	if ns.Fonts and ns.Fonts.Set then
		ns.Fonts.Set(frame.status, "title", 14, "OUTLINE")
	else
		frame.status:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
	end
	frame.status:SetTextColor(0.98, 0.84, 0.54)
	frame.status:SetShadowColor(0, 0, 0, 0.9)
	frame.status:SetShadowOffset(1, -1)
	frame.status2 = frame:CreateFontString(nil, "OVERLAY")
	if ns.Fonts and ns.Fonts.Set then
		ns.Fonts.Set(frame.status2, "title", 12, "OUTLINE")
	else
		frame.status2:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
	end
	frame.status2:SetTextColor(0.86, 0.74, 0.55)
	frame.status2:SetShadowColor(0, 0, 0, 0.9)
	frame.status2:SetShadowOffset(1, -1)

	frame.tabs = {}
	for i, c in ipairs(J.CHAPTERS) do
		local tab = CreateFrame("Button", nil, frame)
		tab.key, tab.index = c.key, i
		tab.art = tab:CreateTexture(nil, "ARTWORK")
		tab.art:SetAllPoints()
		if ns.Art.Apply(tab.art, "journal") then
			tab.art.sanctuaryArt = true
		else
			tab.art:SetColorTexture(0.4, 0.05, 0.03, 0.9)
		end
		tab:SetScript("OnEnter", function(self)
			self.over = true
			TabState(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(c.title, 1, 0.82, 0.45)
			GameTooltip:AddLine(c.tip, 0.9, 0.86, 0.78, true)
			GameTooltip:Show()
		end)
		tab:SetScript("OnLeave", function(self)
			self.over = false
			TabState(self)
			GameTooltip_Hide()
		end)
		tab:SetScript("OnClick", function() J.Select(c.key) end)
		frame.tabs[i] = tab
	end

	frame:SetScript("OnShow", function()
		CheckSkill()
		J.Render()
	end)
	-- Here & Now follows the clock and your lure while it's open.
	local elapsed = 0
	frame:SetScript("OnUpdate", function(_, dt)
		if frame.flash:IsShown() then
			frame.flashT = (frame.flashT or 0) + dt
			local k = frame.flashT / 2.5
			if k >= 1 then frame.flash:Hide() else frame.flash:SetAlpha(1 - k * k) end
		end
		elapsed = elapsed + dt
		if elapsed > 5 then
			elapsed = 0
			if J.chapter == "now" then J.Render() end
		end
	end)
	Layout()
end

function J.Toggle(key)
	if not frame then Build() end
	if key then
		J.chapter = key
	end
	if frame:IsShown() and not key then
		frame:Hide()
	else
		Layout()
		if frame:IsShown() then J.Render() else frame:Show() end
	end
end

function J.Open(key)
	if frame and frame:IsShown() and key then
		J.Select(key)
	else
		J.Toggle(key or J.chapter)
	end
end

---------------------------------------------------------------------------
-- The pop-up: D3's "new lore" notice (journal.png) for each new diary line. It glows as it
-- arrives, rests, and fades; hovering holds it, a click opens the diary, right-click dismisses.
-- It hangs from a fixed holder, which carries the mover while frames are unlocked.

local TOAST = { w = 195, h = 88, left = 64, right = 56, bright = { 640, 160 }, resting = { 640, 260 } }
local TOAST_W = 400 -- at scale 1
local TOAST_PAD = { left = 70, right = 26, top = 15, bottom = 16 }
local holder, toast
local queue = {}

local function Slices(parent, key, layer, sub)
	local x0, y0 = TOAST[key][1], TOAST[key][2]
	local parts = {}
	for i, span in ipairs({ { 0, TOAST.left }, { TOAST.left, TOAST.w - TOAST.right }, { TOAST.w - TOAST.right, TOAST.w } }) do
		local t = parent:CreateTexture(nil, layer, nil, sub)
		if ns.Art.Apply(t, "journal") then
			t:SetTexCoord((x0 + span[1]) / ATLAS, (x0 + span[2]) / ATLAS, y0 / ATLAS, (y0 + TOAST.h) / ATLAS)
		else
			t:SetColorTexture(0.08, 0.04, 0.03, 0.92)
		end
		parts[i] = t
	end
	parts[1]:SetPoint("TOPLEFT")
	parts[1]:SetPoint("BOTTOMLEFT")
	parts[1]:SetWidth(TOAST.left)
	parts[3]:SetPoint("TOPRIGHT")
	parts[3]:SetPoint("BOTTOMRIGHT")
	parts[3]:SetWidth(TOAST.right)
	parts[2]:SetPoint("TOPLEFT", parts[1], "TOPRIGHT")
	parts[2]:SetPoint("BOTTOMRIGHT", parts[3], "BOTTOMLEFT")
	return parts
end

local function SetGlow(alpha)
	for _, t in ipairs(toast.bright) do t:SetAlpha(alpha) end
end

local ShowNext

local function Dismiss()
	toast.phase, toast.t = "out", 0
end

function J.BuildToast()
	if holder then return end
	ns.Art.Require("journal")
	holder = CreateFrame("Frame", "SanctuaryUIJournalToastHolder", UIParent)
	holder:SetSize(TOAST_W, TOAST.h)
	holder:SetFrameStrata("HIGH")
	toast = CreateFrame("Button", "SanctuaryUIJournalToast", holder)
	toast:SetSize(TOAST_W, TOAST.h)
	toast:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	toast.resting = Slices(toast, "resting", "BACKGROUND", 0)
	toast.bright = Slices(toast, "bright", "BACKGROUND", 1)
	toast.title = toast:CreateFontString(nil, "OVERLAY")
	toast.title:SetPoint("TOPLEFT", TOAST_PAD.left, -TOAST_PAD.top)
	toast.title:SetPoint("RIGHT", -TOAST_PAD.right, 0)
	toast.title:SetJustifyH("LEFT")
	toast.title:SetHeight(14)
	toast.title:SetTextColor(1, 0.78, 0.38)
	toast.body = toast:CreateFontString(nil, "OVERLAY")
	toast.body:SetPoint("TOPLEFT", toast.title, "BOTTOMLEFT", 0, -3)
	toast.body:SetWidth(TOAST_W - TOAST_PAD.left - TOAST_PAD.right)
	toast.body:SetJustifyH("LEFT")
	toast.body:SetJustifyV("TOP")
	toast.body:SetWordWrap(true)
	toast.body:SetSpacing(2)
	toast.body:SetTextColor(0.93, 0.87, 0.74)
	toast:SetScript("OnEnter", function(self)
		self.over = true
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Angler's journal", 1, 0.82, 0.45)
		GameTooltip:AddLine("Click to open the diary. Right-click to dismiss.", 0.9, 0.86, 0.78, true)
		GameTooltip:Show()
	end)
	toast:SetScript("OnLeave", function(self)
		self.over = false
		GameTooltip_Hide()
	end)
	toast:SetScript("OnClick", function(self, button)
		if button == "LeftButton" then
			J.Open("diary")
		end
		wipe(queue)
		Dismiss()
	end)
	toast:SetScript("OnUpdate", function(self, dt)
		self.t = self.t + dt
		local t = self.t
		if self.phase == "in" then
			local k = math.min(1, t / 0.3)
			self:SetAlpha(k)
			self:SetPoint("CENTER", holder, "CENTER", 0, -14 * (1 - k) * (1 - k))
			SetGlow(1)
			if k >= 1 then self.phase, self.t = "hold", 0 end
		elseif self.phase == "hold" then
			local rest = self.rare and (0.45 + 0.25 * math.sin(t * 3)) or 0
			SetGlow(self.over and 1 or math.max(rest, 1 - t / 1.4))
			if self.over then
				self.t = math.min(t, 1.4)
			elseif t >= self.hold then
				self.phase, self.t = "out", 0
			end
		elseif self.phase == "out" then
			if self.over then
				self.phase, self.t = "hold", 1.4
				self:SetAlpha(1)
				return
			end
			local k = math.min(1, t / 0.6)
			self:SetAlpha(1 - k)
			if k >= 1 then
				self:Hide()
				ShowNext()
			end
		end
	end)
	toast:Hide()
	if ns.MakeMover then
		holder.mover = ns.MakeMover(holder, "Diary pop-up", function() return Opt().toastPos end,
			"Reset its position in /sanctuary > Fishing journal.")
	end
	J.PlaceToast()
end

ShowNext = function()
	local item = table.remove(queue, 1)
	if not item then return end
	local opt = Opt()
	-- A rare find glows in its rarity's colour, says so, and takes longer to fade.
	local q = item.q and item.q >= 2 and item.q or nil
	local rgb = q and QualityRGB(q)
	for _, t in ipairs(toast.bright) do
		t:SetDesaturated(q and true or false)
		if rgb then
			t:SetVertexColor(math.min(1, rgb[1] * 1.3 + 0.15), math.min(1, rgb[2] * 1.3 + 0.15), math.min(1, rgb[3] * 1.3 + 0.15), 1)
		else
			t:SetVertexColor(1, 1, 1, 1)
		end
	end
	toast.rare = q
	ns.Fonts.Set(toast.title, "title", q and 12 or 11, "")
	if q then
		toast.title:SetText(("%s find  \194\183  day %d"):format(RARITY[q], item.day or 1):upper())
		toast.title:SetTextColor(rgb[1] * 0.6 + 0.4, rgb[2] * 0.6 + 0.4, rgb[3] * 0.6 + 0.4)
	else
		toast.title:SetText(("Angler's journal  \194\183  day %d"):format(item.day or 1):upper())
		toast.title:SetTextColor(1, 0.78, 0.38)
	end
	local path = ns.Fonts.Path("body", opt.diaryFont)
	if not path or toast.body:SetFont(path, 14, "") == false then
		toast.body:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 13, "")
	end
	toast.body:SetText(Linkify(item.text, true))
	local h = math.max(TOAST.h, TOAST_PAD.top + (toast.title:GetStringHeight() or 12) + 3 + (toast.body:GetStringHeight() or 14) + TOAST_PAD.bottom)
	toast:SetSize(TOAST_W, h)
	toast.phase, toast.t, toast.over = "in", 0, false
	-- Long lines stay longer; a waiting queue moves things along.
	toast.hold = math.max(3, (opt.toastTime or 7) + #item.text / 60 - (#queue > 0 and 3 or 0)) + (q and q >= 3 and 3 or 0)
	toast:SetAlpha(0)
	toast:Show()
	if opt.toastSound and PlaySound then
		pcall(PlaySound, (SOUNDKIT and SOUNDKIT.IG_ABILITY_PAGE_TURN) or 836, "SFX")
		-- Rare and better: the loot fanfare too.
		if q and q >= 3 then
			pcall(PlaySound, (SOUNDKIT and SOUNDKIT.UI_EPICLOOT_TOAST) or 31578, "SFX")
		end
	end
end

-- A diary line to show. More than a handful waiting: the oldest go.
function J.Toast(text, day, quality)
	if not holder then J.BuildToast() end
	queue[#queue + 1] = { text = text, day = day, q = quality }
	while #queue > 5 do table.remove(queue, 1) end
	if not toast:IsShown() then ShowNext() end
end

function J.PreviewToast()
	local lines = D().LINES.species
	local log = Log()
	J.Toast(Fill(lines[math.random(#lines)], { fish = "Raw Brilliant Smallfish", zone = "Elwynn Forest" }), log and log.dayCount or 1)
end

function J.PlaceToast()
	if not holder then return end
	local opt = Opt()
	holder:SetScale(opt.toastScale or 1)
	holder:ClearAllPoints()
	local pos = opt.toastPos
	if pos.moved and ns.MovedPoint then
		holder:SetPoint("CENTER", UIParent, "BOTTOMLEFT", ns.MovedPoint(holder, pos))
	else
		holder:SetPoint("BOTTOM", UIParent, "BOTTOM", 300, 260)
	end
	if holder.mover then holder.mover:SetShown(not ns.DB().locked) end
end

function J.ResetToastPosition()
	Opt().toastPos.moved = false
	J.PlaceToast()
end

function J.ApplySettings()
	J.PlaceToast()
	if frame then
		Layout()
		J.Refresh()
	end
end

function J.ResetPosition()
	local opt = Opt()
	opt.point, opt.x, opt.y, opt.moved = "LEFT", 60, 0, false
	J.ApplySettings()
end

function J.Init()
	J.chapter = Opt().chapter or "now"
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "LOOT_OPENED", "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL", "UI_ERROR_MESSAGE",
		"UI_INFO_MESSAGE", "CHAT_MSG_SYSTEM", "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED_INDOORS",
		"PLAYER_ENTERING_WORLD" }) do
		pcall(events.RegisterEvent, events, event)
	end
	for _, event in ipairs({ "GET_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT" }) do
		pcall(events.RegisterEvent, events, event)
	end
	for _, event in ipairs({ "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP" }) do
		if not pcall(events.RegisterUnitEvent, events, event, "player") then
			pcall(events.RegisterEvent, events, event)
		end
	end
	events:SetScript("OnEvent", function(_, event, ...)
		if event == "GET_ITEM_INFO_RECEIVED" or event == "ITEM_DATA_LOAD_RESULT" then
			-- Names waiting on their rarity: one redraw once they've come in.
			if J.waiting and not J.redrawSoon and C_Timer then
				J.redrawSoon = true
				C_Timer.After(0.3, function()
					J.redrawSoon, J.waiting = false, false
					J.Refresh()
				end)
			end
		elseif event == "LOOT_OPENED" then
			ns.Try("journal loot", OnLoot)
		elseif event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
			ns.Try("journal cast", OnCast, event, ...)
		elseif event == "UI_ERROR_MESSAGE" or event == "UI_INFO_MESSAGE" or event == "CHAT_MSG_SYSTEM" then
			ns.Try("journal message", OnMessage, event, ...)
		elseif event == "SKILL_LINES_CHANGED" or event == "CHAT_MSG_SKILL" or event == "PLAYER_ENTERING_WORLD" then
			ns.Try("journal skill", CheckSkill)
			if event == "PLAYER_ENTERING_WORLD" then ns.Try("journal pop-up", J.BuildToast) end
			J.Refresh("now")
		else
			J.Refresh("now")
		end
	end)
end
