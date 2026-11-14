SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.Book = ns.Book or {}
local Book = ns.Book

-- The books' shared engine: the Angler's journal (FishingJournal.lua) and the Cookbook
-- (Cookbook.lua) are both made here, so they look, read, search and write their diaries alike.
--
-- A book is a D3 window (the inventory's header with the book's own medallion, the stone body)
-- holding a parchment page, with D3's red side tabs for chapters and a search box in the footer.
-- Each chapter is a function that adds blocks top to bottom (book.B); widgets are pooled. Item
-- names on a page become links in their rarity's colour. Each book keeps a per-character diary
-- that writes itself; a new line slides in on one shared pop-up (D3's "new lore" notice).
--
-- Art: journal.png (tools/build_journal_art.py): the page 640x640 at 0,160, the pop-up's two
-- cells, and the journal's own header and tabs. A book names the atlas holding its header
-- (600x155 at 0,0) and tabs (64x96 cells from y 800, three per chapter: resting, hover,
-- selected). The body and footer stone come from bag-frame.png like the bag window's.
--
--   local book = ns.Book.New({
--     key = "fishing",               -- names its frames' error labels
--     frameName = "SanctuaryUI...",  -- the window's global name
--     title = "Angler's journal",    -- chat lines, the pop-up, tooltips
--     art = "journal",               -- the atlas with its header and tabs
--     opt = function() ... end,      -- its settings: scale, point, x, y, moved, chapter, diary, chat, toast
--     log = function() ... end,      -- this character's log: entries, days, dayCount (+ decks, story)
--     chapters = { { key, title, tip }, ... },
--     build = { [key] = function() ... end },   -- the chapters
--     home = "now",                  -- the chapter it first opens on
--     live = "now",                  -- a chapter redrawn every few seconds while open
--     names = function() return { { name, itemID }, ... } end,   -- item names to link on the page
--     index = function(Add) ... end, -- search rows: Add(chapter, anchor, name, text, item)
--     status = function() return line1, line2 end,                -- the footer's right
--     story = function() return list end,   -- the diary's own opening lines, one per day
--     onShow = function() ... end,
--     words = { search, nothing, scope, wet, empty, paused, older },
--   })
--
-- Settings both books share (the page's fonts and text size, the pop-up) live in the journal's
-- options, so the two can't drift apart.

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
local TAB_STEP_MIN = 44 -- more chapters than fit: the tabs overlap rather than hang below the stone
local TAB_TUCK = 8 -- the straight edge of the tab art, tucked under the frame's border
local MARGIN = { x = 34, top = 30, bottom = 30 } -- the text area inside the page

local INK = { 0.20, 0.12, 0.05 }
local RED = { 0.50, 0.08, 0.03 }
local MUTED = { 0.40, 0.30, 0.19 }
local GREEN = { 0.12, 0.36, 0.08 }
local AMBER = { 0.58, 0.34, 0.03 }
local GOLD = { 0.62, 0.42, 0.06 }
Book.INK, Book.RED, Book.MUTED, Book.GREEN, Book.AMBER, Book.GOLD = INK, RED, MUTED, GREEN, AMBER, GOLD

-- Item rarities on parchment (darkened, so common white reads as ink) and their words.
local QUALITY_INK = {
	[0] = { 0.42, 0.40, 0.37 }, [1] = INK, [2] = { 0.10, 0.44, 0.02 }, [3] = { 0.00, 0.32, 0.68 },
	[4] = { 0.47, 0.16, 0.72 }, [5] = { 0.76, 0.38, 0.00 }, [6] = { 0.62, 0.48, 0.20 }, [7] = { 0.00, 0.50, 0.70 },
}
local RARITY = { [2] = "Uncommon", [3] = "Rare", [4] = "Epic", [5] = "Legendary" }
Book.QUALITY_INK, Book.RARITY = QUALITY_INK, RARITY

-- A rarity's colour in the game's own shades (dark backgrounds).
local QUALITY_RGB = { [2] = { 0.12, 1, 0 }, [3] = { 0, 0.44, 0.87 }, [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 } }
local function QualityRGB(q)
	if C_Item and C_Item.GetItemQualityColor then
		local ok, r, g, b = pcall(C_Item.GetItemQualityColor, q)
		if ok and type(r) == "number" then return { r, g, b } end
	end
	return QUALITY_RGB[q] or { 1, 1, 1 }
end

Book.books = Book.books or {} -- every book made, in order

-- The settings the books share.
local function Shared()
	return ns.DB().journal
end
Book.Shared = Shared

local function Readable(v)
	return v ~= nil and not ns.Secret(v)
end
Book.Readable = Readable

function Book.Commas(n)
	local s = tostring(math.floor(n or 0))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

function Book.Fill(text, fields)
	return (text:gsub("{(%w+)}", function(key) return fields[key] ~= nil and tostring(fields[key]) or "" end))
end

function Book.Today()
	return date("%Y-%m-%d")
end

-- Your faction, as the books write it: "A", "H", or nil when the client won't say.
function Book.MySide()
	local faction = UnitFactionGroup and UnitFactionGroup("player")
	if not Readable(faction) then return end
	return faction == "Alliance" and "A" or faction == "Horde" and "H" or nil
end

Book.SIDE_NAME = { A = "Alliance", H = "Horde", N = "both" }

-- Is this the other faction's (A or H, not yours, and you have one)?
function Book.Enemy(side)
	local mine = Book.MySide()
	return mine ~= nil and (side == "A" or side == "H") and side ~= mine
end

-- Realm clock: hour, minute; calendar: weekday (1 = Sunday), month.
function Book.Clock()
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

-- A trade skill by its skill line and its spell: rank, cap, bonus; nil when you haven't
-- learned it (or the client won't say).
function Book.Skill(line, spell, fallback)
	local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spell)
	if not Readable(name) and GetSpellInfo then name = GetSpellInfo(spell) end
	if not Readable(name) or type(name) ~= "string" then name = fallback end
	local function Plain(rank, cap, bonus)
		if not Readable(rank) or not Readable(cap) then return end
		return rank, cap, Readable(bonus) and bonus or 0
	end
	if GetProfessions and GetProfessionInfo then
		local ok, a, b, c, d, e = pcall(GetProfessions)
		if ok then
			for _, index in pairs({ a, b, c, d, e }) do
				local ok2, pname, _, rank, cap, _, _, pline, bonus = pcall(GetProfessionInfo, index)
				if ok2 and (pline == line or pname == name) then
					return Plain(rank, cap, bonus)
				end
			end
		end
	end
	if C_SkillInfo and C_SkillInfo.GetNumSkillLines and C_SkillInfo.GetSkillLineInfo then
		local ok, count = pcall(C_SkillInfo.GetNumSkillLines)
		for i = 1, ok and count or 0 do
			local ok2, info = pcall(C_SkillInfo.GetSkillLineInfo, i)
			if ok2 and type(info) == "table" and not info.isHeader and (info.skillID == line or info.name == name) then
				return Plain(info.rank, info.maxRank, (info.modifier or 0) + (info.tempPoints or 0))
			end
		end
	end
	if GetNumSkillLines and GetSkillLineInfo then
		for i = 1, GetNumSkillLines() do
			local sname, header, _, rank, temp, bonus, cap = GetSkillLineInfo(i)
			if not header and sname == name then
				return Plain(rank, cap, (bonus or 0) + (temp or 0))
			end
		end
	end
end

local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

local function Hex(c)
	return ("%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255)
end

local function ItemIcon(id)
	local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
	if not icon and GetItemIcon then icon = GetItemIcon(id) end
	return icon
end

local MAX_ENTRIES = 300

---------------------------------------------------------------------------
-- A book.

function Book.New(spec)
	local book = { spec = spec, key = spec.key, title = spec.title, chapters = spec.chapters, build = spec.build or {} }
	Book.books[#Book.books + 1] = book
	local words = spec.words or {}
	local frame, scroll, child
	local anchors = {} -- search anchor -> { top, h } on the page drawn last
	book.anchors = anchors
	local pools = { text = {}, row = {}, icon = {}, rule = {}, band = {}, diamond = {} }
	local used = { text = 0, row = 0, icon = 0, rule = 0, band = 0, diamond = 0 }
	local cursor, width = 0, 0
	local fontRetry = false
	local B = {}
	book.B = B

	local function Opt() return spec.opt() end
	local function Log() return spec.log and spec.log() end
	book.Opt, book.Log = Opt, Log

	-----------------------------------------------------------------------
	-- The diary: entries, the day count, lines dealt from decks.

	-- A random line from list. With a deck name, the lines come out like cards from a shuffled
	-- deck kept in the saved log: none twice until all have been used. A first deck, or one
	-- reshuffled because lines were added, skips lines the diary already holds; no deck opens
	-- with the line just used.
	function book.Pick(list, name)
		local log = name and Log()
		if not log or #list < 2 then return list[math.random(#list)] end
		log.decks = log.decks or {}
		local deck = log.decks[name]
		if not deck or #deck == 0 or deck.size ~= #list then
			local seen = {}
			if not deck or deck.size ~= #list then
				for _, e in ipairs(log.entries or {}) do seen[#seen + 1] = e.text end
			end
			local fresh, all = {}, {}
			for i, line in ipairs(list) do
				local pattern = "^" .. line:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"):gsub("{%w+}", ".-") .. "$"
				local used2 = false
				for _, text in ipairs(seen) do
					if text:find(pattern) then used2 = true break end
				end
				if i ~= (deck and deck.last) then
					all[#all + 1] = i
					if not used2 then fresh[#fresh + 1] = i end
				end
			end
			deck = #fresh > 0 and fresh or all
			deck.size = #list
			log.decks[name] = deck
		end
		local i = table.remove(deck, math.random(#deck))
		deck.last = i
		return list[i]
	end

	-- The diary's day number: days you did the book's thing, counted.
	local function DayNumber(log)
		local today = Book.Today()
		if not log.days[today] then
			log.days[today] = true
			log.dayCount = (log.dayCount or 0) + 1
		end
		return log.dayCount
	end

	-- The diary's story (spec.story): day n's line goes in just ahead of the first entry of day
	-- n, once, so the setup sits under Day 1 and the punchline under Day 2. A day with no
	-- entries yet waits; a day already trimmed off the front of the diary is skipped.
	function book.Story(log)
		local story = spec.story and spec.story()
		if not story or not log.entries then return end
		log.story = log.story or {}
		local entries = log.entries
		local oldest = entries[1] and entries[1].day or math.huge
		for n, lines in ipairs(story) do
			if not log.story[n] then
				local at
				for i, e in ipairs(entries) do
					if e.day == n then at = i break end
				end
				if at then
					local text = lines[1] or lines[Book.MySide() or ""]
					if text then
						table.insert(entries, at, { t = entries[at].t, day = n, text = text, story = true })
					end
					log.story[n] = true
				elseif n < oldest or (log.dayCount or 0) > n then
					log.story[n] = true
				end
			end
		end
	end

	-- quality: the find's rarity when the line is about a rare find (2 uncommon and up).
	function book.Write(text, quality)
		local log = Log()
		if not log or not Opt().diary then return end
		local entries = log.entries
		local day = DayNumber(log)
		entries[#entries + 1] = { t = time(), day = day, text = text, q = quality }
		book.Story(log)
		while #entries > MAX_ENTRIES do table.remove(entries, 1) end
		if Opt().chat then
			print(("|cffd8b86a%s:|r |cffe6dfd0%s|r"):format(spec.title, text))
		end
		if Opt().toast then Book.Toast(book, text, day, quality) end
		book.Refresh("diary")
	end

	-----------------------------------------------------------------------
	-- The page: a small layout engine.

	local function Face(fs, which, size)
		local opt = Shared()
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

	-- A row's tooltip: its item's card, and/or a line saying what a click does.
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
			local _, link = GetInfo(row.itemID)
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
	-- rarity's colour. Names come from the book (spec.names) and from the log (log.names). An
	-- item the client hasn't loaded yet is asked for, and the page redrawn when it arrives.
	local asked = {} -- item IDs requested from the client

	local function Quality(id)
		local q = C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(id)
		if q == nil and GetInfo then q = select(3, GetInfo(id)) end
		if q == nil then
			-- What the loot window said when you got it.
			local log = Log()
			q = log and log.quality and log.quality[id]
			if q then return q end
			if not asked[id] then
				asked[id] = true
				book.waiting = true
				if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
			end
			return
		end
		return Readable(q) and q or nil
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

	-- The book's names, longest first (so "Raw Rockscale Cod" wins over "Rockscale Cod"), and
	-- filed under their first word: a text only tries the names its own capitalised words start.
	local NAMES, BY_WORD, LOOSE
	local function Names()
		if NAMES then return NAMES end
		local seen, list = {}, {}
		for _, pair in ipairs(spec.names and spec.names() or {}) do
			if pair[1] and pair[2] and not seen[pair[1]] then
				seen[pair[1]] = true
				list[#list + 1] = pair
			end
		end
		table.sort(list, function(a, b)
			if #a[1] ~= #b[1] then return #a[1] > #b[1] end
			return a[1] < b[1]
		end)
		BY_WORD, LOOSE = {}, {}
		for rank, pair in ipairs(list) do
			pair.rank = rank
			local word = pair[1]:match("^%u[%a']*")
			if word then
				BY_WORD[word] = BY_WORD[word] or {}
				table.insert(BY_WORD[word], pair)
			else
				LOOSE[#LOOSE + 1] = pair
			end
		end
		NAMES = list
		return list
	end

	-- text with every item name it holds coloured, and linked unless dark (a frame that can't
	-- take hyperlinks).
	function Linkify(text, dark)
		if type(text) ~= "string" or not text:find("%u") then return text end
		Names()
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
		local tried, candidates = {}, {}
		for word in text:gmatch("%u[%a']*") do
			if not tried[word] then
				tried[word] = true
				for _, pair in ipairs(BY_WORD[word] or {}) do candidates[#candidates + 1] = pair end
			end
		end
		for _, pair in ipairs(LOOSE) do candidates[#candidates + 1] = pair end
		table.sort(candidates, function(a, b) return a.rank < b.rank end)
		for _, n in ipairs(candidates) do Try(n[1], n[2]) end
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
	book.Linkify = Linkify

	-- The blocks. Every heading is ruled; table rows alternate a faint band and are parted by a
	-- hairline, so a page reads as rows rather than one run of text. A row with o.cont belongs
	-- to the item above it (the same band, no line between).
	local stripe = 0 -- rows since the last heading

	local function Line(y, x, w, color, alpha)
		local t = Take("rule", function() return child:CreateTexture(nil, "ARTWORK") end)
		t:SetColorTexture(color[1], color[2], color[3], alpha)
		t:ClearAllPoints()
		t:SetPoint("TOPLEFT", child, "TOPLEFT", x, -y)
		t:SetSize(math.max(1, w), 1)
	end

	local function Band(top, h, color, alpha)
		local t = Take("band", function() return child:CreateTexture(nil, "BACKGROUND") end)
		if color then
			t:SetColorTexture(color[1], color[2], color[3], alpha or 0.12)
		else
			t:SetColorTexture(0.45, 0.28, 0.10, 0.08)
		end
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

	-- A small heading with no rule: a tale's title, a recipe's name inside a section.
	function B.sub(text, anchor, color)
		local _, h = Text("title", 10.5, color or RED, text:upper(), 0, width)
		if anchor then anchors[anchor] = { top = cursor, h = h } end
		cursor = cursor + h + 3
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

	-- A line of columns. cols: texts; fr: their width shares. o.item: an item for icon and
	-- tooltip (first column); o.head: column headings; o.color / o.colors: ink; o.cont: belongs
	-- to the row above; o.dim: the other faction's (faded); o.onClick, o.tip: a row that goes
	-- somewhere; o.anchor: a name search results can jump to.
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

	-- A chapter's opening words, in the diary's hand: openers[key], then your side's
	-- (openers[key .. "A"] or "H"), then the flourish.
	function B.opener(openers, key)
		for _, line in ipairs(openers[key] or {}) do
			B.hand(line)
		end
		local side = Book.MySide()
		for _, line in ipairs(side and openers[key .. side] or {}) do
			B.hand(line)
		end
		B.flourish()
	end

	-- The diary's entries: newest first, under one heading per day; a hairline between a day's
	-- entries. The day's story line, if it has one, opens the day under its heading.
	function B.entries()
		local log = Log()
		if not log then return end
		book.Story(log)
		B.h("Entries")
		if not Opt().diary then
			B.note(words.paused or "The diary is paused.")
		end
		local entries = log.entries
		if #entries == 0 then
			B.hand(words.empty or "Empty.")
			return
		end
		local order, i = {}, #entries
		while i >= 1 do
			local day, first = entries[i].day, #order + 1
			while i >= 1 and entries[i].day == day do
				if entries[i].story then
					table.insert(order, first, i)
				else
					order[#order + 1] = i
				end
				i = i - 1
			end
		end
		local shown, lastDay = 0, nil
		for _, at in ipairs(order) do
			local e = entries[at]
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
			if not e.story then
				Text(q and "title" or "page", q and 9.5 or 11, q or MUTED, q and RARITY[e.q] or date("%H:%M", e.t), 0, 42)
			end
			local _, h = Text("hand", 15, INK, e.text, 44, width - 44)
			if q then
				-- A rare find's entry: a faint wash of its rarity behind it, its time under the word.
				Text("page", 10.5, MUTED, date("%H:%M", e.t), 0, 42, nil, 13)
				Band(cursor - 3, h + 6, q, 0.12)
			end
			anchors["entry:" .. at] = { top = cursor, h = h }
			cursor = cursor + h + 9
			shown = shown + 1
			if shown >= 80 then
				B.note((words.older or "...and %d older entries, pressed between the pages."):format(#entries - shown))
				break
			end
		end
	end

	-----------------------------------------------------------------------
	-- Search: every row the book can find, with the chapter and the row (anchor) it lives on.

	local function Index()
		local out = {}
		local function Add(chapter, anchor, name, text, item)
			out[#out + 1] = { chapter = chapter, anchor = anchor, name = name, text = text or "", item = item, n = #out }
		end
		for _, c in ipairs(book.chapters) do Add(c.key, nil, c.title, c.tip) end
		if spec.index then spec.index(Add) end
		local log = Log()
		for i, e in ipairs(log and log.entries or {}) do
			Add("diary", "entry:" .. i, ("Day %d, %s"):format(e.day or 1, date("%d %b %H:%M", e.t)), e.text)
		end
		return out
	end

	-- Rows matching every word of the query, best first: the whole query in the name, then
	-- every word in the name, then anywhere.
	function book.Find(query)
		local list = {}
		for word in query:lower():gmatch("%S+") do list[#list + 1] = word end
		if #list == 0 then return {} end
		local found = {}
		for _, row in ipairs(Index()) do
			local name, all = row.name:lower(), (row.name .. " " .. row.text):lower()
			local ok, inName = true, true
			for _, word in ipairs(list) do
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
		return found, list
	end

	-- A piece of the text around the first word that matched.
	local function Snippet(text, list)
		local lower, at = text:lower(), nil
		for _, word in ipairs(list) do
			at = lower:find(word, 1, true)
			if at then break end
		end
		if not at or #text <= 110 then return text end
		local from = math.max(1, at - 40)
		local piece = text:sub(from, from + 109)
		return (from > 1 and "..." or "") .. piece .. (from + 109 < #text and "..." or "")
	end

	-- Open a chapter at one of its rows, and light the row for a moment.
	function book.Jump(chapter, anchor)
		book.jump = anchor
		book.Select(chapter)
	end

	local function BuildSearch()
		local query = book.query or ""
		local found, list = book.Find(query)
		if #found == 0 then
			B.hand((words.nothing or "Nothing by \"%s\"."):format(query))
			if words.scope then B.note(words.scope) end
			return
		end
		B.note(("%d found for \"%s\". Click one to open its page; Enter opens the first."):format(#found, query))
		book.first = found[1]
		local shown = 0
		for _, c in ipairs(book.chapters) do
			local any = false
			for _, row in ipairs(found) do
				if row.chapter == c.key and shown < 80 then
					if not any then
						B.h(c.title)
						any = true
					end
					shown = shown + 1
					local r = row
					B.row({ r.name, Snippet(r.text, list) }, { 0.36, 0.64 }, {
						item = r.item, tip = "Open in " .. c.title,
						onClick = function() book.Jump(r.chapter, r.anchor) end,
					})
				end
			end
		end
	end

	-- The search box's text changed.
	function book.SetQuery(text)
		text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
		if #text >= 2 then
			if book.chapter ~= "search" then book.before = book.chapter end
			book.query, book.chapter, book.first = text, "search", nil
			if scroll then scroll:SetVerticalScroll(0) end
			book.Render()
		elseif book.chapter == "search" then
			book.query = nil
			book.chapter = book.before or Opt().chapter or spec.home
			book.Render()
		end
	end

	-- Open the book on a search.
	function book.Search(text)
		if not frame or not frame:IsShown() then book.Toggle() end
		frame.search:SetText(text)
		book.SetQuery(text)
	end

	-----------------------------------------------------------------------
	-- The window.

	local function TabCoord(index, state)
		local i = (index - 1) * 3 + state -- state 0 resting, 1 hover, 2 selected
		local col, row = i % TAB.per, math.floor(i / TAB.per)
		local x, y = col * TAB.w, TAB.y + row * TAB.h
		return x / ATLAS, (x + TAB.w) / ATLAS, y / ATLAS, (y + TAB.h) / ATLAS
	end

	local function TabState(tab)
		local state = (book.chapter == tab.key) and 2 or (tab.over and 1 or 0)
		if tab.art.sanctuaryArt then tab.art:SetTexCoord(TabCoord(tab.index, state)) end
		tab:SetFrameLevel(frame:GetFrameLevel() + (state == 2 and 3 or (tab.over and 2 or 1)))
	end

	local function UpdateTabs()
		for _, tab in ipairs(frame.tabs) do TabState(tab) end
	end

	function book.Render()
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
		for _, c in ipairs(book.chapters) do
			if c.key == book.chapter then chapter = c end
		end
		if book.chapter == "search" then chapter = { key = "search", title = "Search" } end
		chapter = chapter or book.chapters[1]
		B.title(chapter.title)
		local ok, err = ns.Try(spec.key .. " " .. chapter.key, chapter.key == "search" and BuildSearch or book.build[chapter.key])
		if not ok then B.p((words.wet or "This page got wet: ") .. tostring(err), RED) end
		cursor = cursor + 10
		child:SetHeight(math.max(1, cursor))
		if spec.status then
			local ok2, line1, line2 = pcall(spec.status)
			frame.status:SetText(ok2 and line1 or "")
			frame.status2:SetText(ok2 and line2 or "")
		end
		-- Arriving from a search result: bring its row up and light it.
		local spot = book.jump and anchors[book.jump]
		book.jump = nil
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
		book.UpdateScroll()
		UpdateTabs()
		-- A face that wasn't ready yet (Fonts.lua preloads them): one more pass shortly.
		if fontRetry and not book.retried and C_Timer then
			book.retried = true
			C_Timer.After(1, book.Render)
		end
	end

	-- Redraw if the window shows that chapter (or any, when none is named).
	function book.Refresh(key)
		if frame and frame:IsShown() and (not key or key == book.chapter) then
			book.Render()
		end
	end

	function book.Shown()
		return frame ~= nil and frame:IsShown()
	end

	function book.UpdateScroll()
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

	function book.Select(key)
		book.chapter = key
		Opt().chapter = key
		book.query = nil
		if frame and frame.search and (frame.search:GetText() or "") ~= "" then
			frame.search:SetText("")
			frame.search:ClearFocus()
		end
		if scroll then scroll:SetVerticalScroll(0) end
		book.Render()
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
		-- The tabs run down the right edge; a book with many chapters closes them up to fit.
		local count = #frame.tabs
		local step = TAB_STEP
		if count > 1 then
			step = math.max(TAB_STEP_MIN, math.min(TAB_STEP, (BODY_H + footerH - 6 - TAB_SIZE[2]) / (count - 1)))
		end
		for i, tab in ipairs(frame.tabs) do
			tab:ClearAllPoints()
			tab:SetPoint("TOPLEFT", frame, "TOPRIGHT", -TAB_TUCK, -(headerH + 2 + (i - 1) * step))
			tab:SetSize(TAB_SIZE[1], TAB_SIZE[2])
		end
		frame:SetScale(opt.scale or 1)
		frame:ClearAllPoints()
		local home = spec.place or { "LEFT", 60, 0 }
		frame:SetPoint(opt.point or home[1], UIParent, opt.point or home[1], opt.x or home[2], opt.y or home[3])
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
		-- The book's own atlas (header, tabs); the journal's when it hasn't loaded (a new file
		-- needs a client restart), so the window still stands.
		local own = spec.art or "journal"
		if own ~= "journal" then ns.Art.Require(own) end
		if not ns.Art.Path(own) then own = "journal" end
		frame = CreateFrame("Frame", spec.frameName, UIParent)
		book.frame = frame
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

		local headerArt = ns.Art.Path(own) and own or "bagFrame"
		frame.art = {
			header = Piece(headerArt, 0, 0, ART_W, HEADER_H, "ARTWORK"),
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
		book.child = child
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
			book.UpdateScroll()
		end)
		scroll:SetScript("OnSizeChanged", function() book.Render() end)
		local thumb = frame:CreateTexture(nil, "ARTWORK")
		thumb:SetColorTexture(RED[1], RED[2], RED[3], 0.45)
		thumb:SetWidth(3)
		frame.thumb = thumb

		-- The light on a row reached from a search.
		frame.flash = child:CreateTexture(nil, "BACKGROUND", nil, 2)
		frame.flash:SetColorTexture(0.95, 0.68, 0.18, 0.35)
		frame.flash:Hide()

		-- Search: Blizzard's box (magnifier, clear button, hint) on a D3 plate, like the bags'.
		local search = CreateFrame("EditBox", spec.frameName .. "Search", frame, "SearchBoxTemplate")
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
		if search.Instructions then search.Instructions:SetText(words.search or "Search") end
		if ns.Fonts and ns.Fonts.Set then
			ns.Fonts.Set(search, "body", 14, "")
			if search.Instructions then ns.Fonts.Set(search.Instructions, "body", 14, "") end
		end
		search:HookScript("OnTextChanged", function(self)
			book.SetQuery(self:GetText())
		end)
		search:SetScript("OnEnterPressed", function(self)
			self:ClearFocus()
			local first = book.first
			if book.chapter == "search" and first then book.Jump(first.chapter, first.anchor) end
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
		for i, c in ipairs(book.chapters) do
			local tab = CreateFrame("Button", nil, frame)
			tab.key, tab.index = c.key, i
			tab.art = tab:CreateTexture(nil, "ARTWORK")
			tab.art:SetAllPoints()
			if ns.Art.Apply(tab.art, own) then
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
			tab:SetScript("OnClick", function() book.Select(c.key) end)
			frame.tabs[i] = tab
		end

		frame:SetScript("OnShow", function()
			if spec.onShow then ns.Try(spec.key .. " show", spec.onShow) end
			book.Render()
		end)
		-- The live chapter follows the clock, your bags, your lure while it's open.
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
				if spec.live and book.chapter == spec.live then book.Render() end
			end
		end)
		Layout()
	end

	function book.Toggle(key)
		if not frame then Build() end
		if key then
			book.chapter = key
		end
		if frame:IsShown() and not key then
			frame:Hide()
		else
			Layout()
			if frame:IsShown() then book.Render() else frame:Show() end
		end
	end

	function book.Open(key)
		if frame and frame:IsShown() and key then
			book.Select(key)
		else
			book.Toggle(key or book.chapter)
		end
	end

	function book.ApplySettings()
		if frame then
			Layout()
			book.Refresh()
		end
	end

	function book.ResetPosition()
		local opt = Opt()
		local home = spec.place or { "LEFT", 60, 0 }
		opt.point, opt.x, opt.y, opt.moved = home[1], home[2], home[3], false
		book.ApplySettings()
	end

	-- Call once the settings have loaded.
	function book.Start()
		book.chapter = Opt().chapter or spec.home
	end

	return book
end

---------------------------------------------------------------------------
-- The pop-up: D3's "new lore" notice (journal.png) for each new diary line, shared by the
-- books. It glows as it arrives, rests, and fades; hovering holds it, a click opens that
-- book's diary, right-click dismisses. It hangs from a fixed holder, which carries the mover
-- while frames are unlocked.

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

function Book.BuildToast()
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
		GameTooltip:SetText(self.book and self.book.title or "Diary", 1, 0.82, 0.45)
		GameTooltip:AddLine("Click to open the diary. Right-click to dismiss.", 0.9, 0.86, 0.78, true)
		GameTooltip:Show()
	end)
	toast:SetScript("OnLeave", function(self)
		self.over = false
		GameTooltip_Hide()
	end)
	toast:SetScript("OnClick", function(self, button)
		if button == "LeftButton" and self.book then
			self.book.Open("diary")
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
		holder.mover = ns.MakeMover(holder, "Diary pop-up", function() return Shared().toastPos end,
			"Reset its position in /sanctuary > Fishing journal.")
	end
	Book.PlaceToast()
end

ShowNext = function()
	local item = table.remove(queue, 1)
	if not item then return end
	local opt = Shared()
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
	toast.book = item.book
	ns.Fonts.Set(toast.title, "title", q and 12 or 11, "")
	if q then
		toast.title:SetText(("%s find  \194\183  day %d"):format(RARITY[q], item.day or 1):upper())
		toast.title:SetTextColor(rgb[1] * 0.6 + 0.4, rgb[2] * 0.6 + 0.4, rgb[3] * 0.6 + 0.4)
	else
		toast.title:SetText(("%s  \194\183  day %d"):format(item.book and item.book.title or "Diary", item.day or 1):upper())
		toast.title:SetTextColor(1, 0.78, 0.38)
	end
	local path = ns.Fonts.Path("body", opt.diaryFont)
	if not path or toast.body:SetFont(path, 14, "") == false then
		toast.body:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 13, "")
	end
	toast.body:SetText(item.book and item.book.Linkify(item.text, true) or item.text)
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
function Book.Toast(book, text, day, quality)
	if not holder then Book.BuildToast() end
	queue[#queue + 1] = { book = book, text = text, day = day, q = quality }
	while #queue > 5 do table.remove(queue, 1) end
	if not toast:IsShown() then ShowNext() end
end

function Book.PlaceToast()
	if not holder then return end
	local opt = Shared()
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

function Book.ResetToastPosition()
	Shared().toastPos.moved = false
	Book.PlaceToast()
end

-- Settings changed: the pop-up's place and every open book.
function Book.ApplySettings()
	Book.PlaceToast()
	for _, book in ipairs(Book.books) do book.ApplySettings() end
end

function Book.Init()
	for _, book in ipairs(Book.books) do book.Start() end
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "GET_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT", "PLAYER_ENTERING_WORLD" }) do
		pcall(events.RegisterEvent, events, event)
	end
	local soon = false
	events:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_ENTERING_WORLD" then
			ns.Try("book pop-up", Book.BuildToast)
			return
		end
		-- Names waiting on their rarity: one redraw once they've come in.
		if soon or not C_Timer then return end
		local waiting = false
		for _, book in ipairs(Book.books) do waiting = waiting or book.waiting end
		if not waiting then return end
		soon = true
		C_Timer.After(0.3, function()
			soon = false
			for _, book in ipairs(Book.books) do
				if book.waiting then
					book.waiting = false
					book.Refresh()
				end
			end
		end)
	end)
end
