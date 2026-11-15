SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.WhatsNew = ns.WhatsNew or {}
local N = ns.WhatsNew

-- What's new: after an update, a small D3 window lists what the releases you missed brought,
-- newest first on a timeline, once per account (the newest version shown is kept in the global
-- saved variables). /sanctuary news shows the whole timeline again, /sanctuary news 0.26.0 one
-- release. Each feature release adds an entry at the top of RELEASES.

local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
local MINE = getMeta and getMeta("SanctuaryUI", "Version") or "?"

-- Newest first: { version, date, notes = { { heading, text, button label, action }, ... } }.
local RELEASES = {
	{
		version = "0.28.0", date = "15 November 2026",
		notes = {
			{
				"Diablo III nameplates",
				"Enemies wear D3's own frames: silver for monsters, gold for elites (blue names) and rares (yellow), the scroll banner for bosses. Lost health drains away pale behind each hit, the bar turns molten in execute range, and your target grows with a gold glow. Cast bars say who the spell is aimed at, with a red » YOU when it's you, and who interrupted it. Your debuffs sit above the name, quest mobs get a gold !, and enemies burst into embers as they die. Friends outside dungeons are just their names. Turn Plater off to use them. Options > Unit frames > Nameplates; /sanctuary plates shows a made-up pull.",
				"Options", function() ns.Options.Open("plates") end,
			},
			{
				"Where to fish",
				"The angler's journal now says where to fish now: the best zones for your skill and the next ones, on Here & Now and Waters. Every fish has a Where line, coloured by your skill, zone names find their fish in search, and Show on the world map lights those zones on the real map.",
				"Journal", function() ns.Journal.Open("waters") end,
			},
		},
	},
	{
		version = "0.27.0", date = "14 November 2026",
		notes = {
			{
				"Share your setup",
				"Turn your profile into one line of text and paste it to a friend or onto another account, then import theirs as a new profile or over your own. Only the settings you've changed go in; keybindings and your notes and history stay with you. Options > Setup > Import / Export.",
				"Options", function() ns.Options.Open("share") end,
			},
		},
	},
	{
		version = "0.26.0", date = "14 November 2026",
		notes = {
			{
				"Your casts on the rail",
				"While you cast, the XP rail above your skills becomes your cast bar: a molten fill runs along it, the spell's name and the time left sit either side of the skull, and the level medallion shows the spell's icon. A cast that lands flares the rail gold, an interrupted one turns red, channels drain in blue. Blizzard's cast bar is off while this is on. Options > XP, Rep & Casts; /sanctuary cast shows a preview.",
				"Options", function() ns.Options.Open("rail") end,
			},
		},
	},
	{
		version = "0.25.0", date = "14 November 2026",
		notes = {
			{
				"Threat",
				"Who is closest to pulling your enemy, on the damage meter's rails: a gold rail holds aggro, a molten one is above the tank and about to pull. Target a friend (the tank) to watch their enemy. Big letters warn you when you take aggro, or as the tank when you lose it, and a tank sees the enemies loose on the group and who they are on. Options > Combat > Threat; /sanctuary threat test shows a made-up pull.",
				"Options", function() ns.Options.Open("threat") end,
			},
			{
				"Saved fights remember everyone",
				"Dungeon and raid fights the damage meter saves now keep every player's abilities and deaths, so the analysis window shows them long after the game has forgotten the fight. Opened from the Run Report, the analysis window comes in front of it.",
				"Analysis", function() ns.MeterAnalysis.Open() end,
			},
			{
				"Frozen globe",
				"The ice on your health globe follows a frost debuff through the whole fight: it melts when the debuff runs out and holds when a caster renews it.",
			},
		},
	},
	{
		version = "0.24.0", date = "13 November 2026",
		notes = {
			{
				"The Run Report",
				"When a dungeon or raid is done, a banner at the top of the screen offers a report of the run: a summary, every pull with its damage, the bosses, each player, what hurt the group most and your past runs. It never opens by itself. /sanctuary meter run test shows one for a made-up Deadmines run.",
				"Options", function() ns.Options.Open("meter") end,
			},
		},
	},
	{
		version = "0.23.0", date = "13 November 2026",
		notes = {
			{
				"The Cookbook",
				"A sister to the angler's journal: what your bags can cook right now, what each ingredient becomes, which recipes to learn and where, the route to 300, what's worth eating, and a diary that writes itself as you cook. /sanctuary cook, or the cauldron in the menu.",
				"Options", function() ns.Options.Open("cookbook") end,
			},
		},
	},
	{
		version = "0.22.0", date = "13 November 2026",
		notes = {
			{
				"One key to fish",
				"The Fishing key casts and, when the bobber splashes, hooks the catch. A fishing outfit swaps your pole and gear in and your weapons back when you're done or attacked, and the splash got louder. Options > Professions > Fishing tools.",
				"Options", function() ns.Options.Open("fishingTools") end,
			},
		},
	},
	{
		version = "0.21.0", date = "13 November 2026",
		notes = {
			{
				"The angler's journal",
				"A complete fishing guide in a D3 book: where to fish for your skill, what bites where, lures and gear, trainers and the route to 300, with a diary that writes itself as you fish and a pop-up for rare catches. /sanctuary fish, or the gold fish in the menu.",
				"Options", function() ns.Options.Open("fishing") end,
			},
		},
	},
}
N.RELEASES = RELEASES -- for tools/ui_preview/news_preview.py
local BY_VERSION = {}
for _, r in ipairs(RELEASES) do BY_VERSION[r.version] = r end
-- A first look (nothing seen yet on this account): only this many of the newest releases.
local FIRST_LOOK = 3

-- True when version a is newer than b (0.27.0 > 0.26.10 > 0.26.9), as VersionCheck.lua compares.
local function Newer(a, b)
	if type(a) ~= "string" or type(b) ~= "string" then return false end
	local pa, pb = {}, {}
	for n in a:gmatch("%d+") do pa[#pa + 1] = tonumber(n) end
	for n in b:gmatch("%d+") do pb[#pb + 1] = tonumber(n) end
	for i = 1, math.max(#pa, #pb) do
		local x, y = pa[i] or 0, pb[i] or 0
		if x ~= y then return x > y end
	end
	return false
end

local GOLD = { 0.91, 0.78, 0.48 }
local CREAM = { 0.89, 0.84, 0.75 }
local WIDTH = 500
local PAD = 32
local HEADER = 50
-- Text sizes: the header's title and version, a release's version on the timeline, each note's
-- heading and text, the buttons.
local TITLE, VERSION, VERSION_MARK, HEADING, BODY, BUTTON, OK = 18, 11, 15, 13, 10, 9, 12
local LINE_GAP = 4 -- between a note's lines
local ITEM_GAP = 30 -- between notes; a faint rule sits in its middle
local RELEASE_GAP = 30 -- between releases on the timeline
local MARK = 22 -- the timeline's line runs this far in from PAD; notes start past it
local INDENT = 2 * MARK -- notes' left edge, from PAD
local MAX_BODY = 560 -- taller than this, the timeline scrolls
local STEP = 48 -- a mouse wheel notch

local frame
local items, marks = {}, {}
local shownVersion

local function Opt()
	return ns.DB().news
end

local function Global()
	return ns.db and ns.db.global
end

local function TitleFont() return ns.Fonts.Path("title") end
local function BodyFont() return ns.Fonts.Path("body") end

local function Text(parent, font, size, color, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFont(font, size, "")
	fs:SetShadowColor(0, 0, 0, 1)
	fs:SetShadowOffset(1, -1)
	fs:SetTextColor(color[1], color[2], color[3])
	fs:SetJustifyH(justify or "LEFT")
	return fs
end

-- D3's red button plate in three slices, with a label.
local function Plate(parent, w, h, label, size)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(w, h)
	local art = ns.Art.Path("d3Button")
	local parts = {}
	for i, cut in ipairs({ { 0, 24 }, { 24, 72 }, { 96, 24 } }) do
		local t = b:CreateTexture(nil, "ARTWORK")
		if art then
			t:SetTexture(art)
			t:SetTexCoord(cut[1] / 128, (cut[1] + cut[2]) / 128, 0, 52 / 64)
		else
			t:SetColorTexture(0.3, 0.05, 0.03, 1)
		end
		parts[i] = t
	end
	local cap = math.floor(h * 24 / 52 + 0.5)
	parts[1]:SetPoint("TOPLEFT") parts[1]:SetPoint("BOTTOMLEFT") parts[1]:SetWidth(cap)
	parts[3]:SetPoint("TOPRIGHT") parts[3]:SetPoint("BOTTOMRIGHT") parts[3]:SetWidth(cap)
	parts[2]:SetPoint("TOPLEFT", parts[1], "TOPRIGHT")
	parts[2]:SetPoint("BOTTOMRIGHT", parts[3], "BOTTOMLEFT")
	b.label = Text(b, TitleFont(), size, GOLD, "CENTER")
	b.label:SetPoint("CENTER", b, "CENTER", 0, -1)
	b.label:SetText(label)
	b:SetScript("OnEnter", function(self) self.label:SetTextColor(1, 1, 1) end)
	b:SetScript("OnLeave", function(self) self.label:SetTextColor(GOLD[1], GOLD[2], GOLD[3]) end)
	return b
end

local function Build()
	frame = CreateFrame("Frame", "SanctuaryUIWhatsNew", UIParent)
	frame:SetFrameStrata("DIALOG")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:Hide()
	tinsert(UISpecialFrames, "SanctuaryUIWhatsNew") -- Escape closes it

	-- The bag window's dark body inside a thin gold line, as the meter's shadow panel.
	local edge = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
	edge:SetAllPoints()
	edge:SetColorTexture(0.03, 0.027, 0.023, 0.97)
	local line = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
	line:SetPoint("TOPLEFT", 2, -2)
	line:SetPoint("BOTTOMRIGHT", -2, 2)
	line:SetColorTexture(0.42, 0.33, 0.18, 1)
	local body = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
	body:SetPoint("TOPLEFT", 3, -3)
	body:SetPoint("BOTTOMRIGHT", -3, 3)
	local bag = ns.Art.Path("bagFrame")
	if bag then
		body:SetTexture(bag)
		body:SetTexCoord(14 / 1024, 574 / 1024, 170 / 1024, 440 / 1024)
	else
		body:SetColorTexture(0.06, 0.055, 0.05, 1)
	end

	-- The header: red glass, the title and the version. Drag it to move the window.
	local head = CreateFrame("Frame", nil, frame)
	head:SetPoint("TOPLEFT", frame, "TOPLEFT", 3, -3)
	head:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -3, -3)
	head:SetHeight(HEADER)
	head:EnableMouse(true)
	head:RegisterForDrag("LeftButton")
	head:SetScript("OnDragStart", function() frame:StartMoving() end)
	head:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		frame:SetUserPlaced(false)
		local x, y = frame:GetCenter()
		local px, py = UIParent:GetCenter()
		local k = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
		if x and px then Opt().offset = { x * k - px, y * k - py } end
	end)
	local glassEdge = head:CreateTexture(nil, "BACKGROUND")
	glassEdge:SetAllPoints()
	glassEdge:SetColorTexture(0.04, 0.03, 0.024, 1)
	frame.glass = {}
	frame.head = head
	frame.title = Text(head, TitleFont(), TITLE, GOLD)
	frame.title:SetPoint("LEFT", head, "LEFT", 18, -1)
	frame.title:SetText("What's new")
	frame.version = Text(head, BodyFont(), VERSION, CREAM, "RIGHT")
	frame.version:SetPoint("RIGHT", head, "RIGHT", -18, -1)

	-- The timeline scrolls inside the window when it is taller than MAX_BODY.
	local scroll = CreateFrame("ScrollFrame", nil, frame)
	scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -HEADER - 6)
	scroll:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -HEADER - 6)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(WIDTH, 1)
	scroll:SetScrollChild(content)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local most = math.max(0, (content:GetHeight() or 0) - (self:GetHeight() or 0))
		local y = math.max(0, math.min(most, (self:GetVerticalScroll() or 0) - delta * STEP))
		self:SetVerticalScroll(y)
		N.UpdateThumb()
	end)
	frame.scroll, frame.content = scroll, content
	-- A thin gold thumb on the right while it scrolls.
	local track = frame:CreateTexture(nil, "ARTWORK")
	track:SetWidth(2)
	track:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -12, -4)
	track:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", -12, 4)
	track:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.12)
	local thumb = frame:CreateTexture(nil, "OVERLAY")
	thumb:SetWidth(2)
	thumb:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.6)
	frame.track, frame.thumb = track, thumb

	frame.ok = Plate(frame, 140, 34, "Got it", OK)
	frame.ok:SetPoint("BOTTOM", frame, "BOTTOM", 0, 20)
	frame.ok:SetScript("OnClick", function() frame:Hide() end)

	frame:SetScript("OnHide", function()
		local global = Global()
		if global and shownVersion and (global.newsSeen == nil or Newer(shownVersion, global.newsSeen)) then
			global.newsSeen = shownVersion
		end
	end)
end

function N.UpdateThumb()
	local scroll, content, thumb, track = frame.scroll, frame.content, frame.thumb, frame.track
	local view, full = scroll:GetHeight() or 0, content:GetHeight() or 0
	if full <= view + 1 then
		thumb:Hide()
		track:Hide()
		return
	end
	local span = view - 8
	local size = math.max(24, span * view / full)
	local at = (scroll:GetVerticalScroll() or 0) / (full - view)
	thumb:SetHeight(size)
	thumb:ClearAllPoints()
	thumb:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -12, -4 - (span - size) * at)
	thumb:Show()
	track:Show()
end

local function Item(i)
	local it = items[i]
	if it then return it end
	local parent = frame.content
	it = {}
	it.heading = Text(parent, TitleFont(), HEADING, GOLD)
	it.text = Text(parent, BodyFont(), BODY, CREAM)
	it.text:SetWordWrap(true)
	it.text:SetSpacing(LINE_GAP)
	it.button = Plate(parent, 84, 22, "", BUTTON)
	it.rule = parent:CreateTexture(nil, "ARTWORK")
	it.rule:SetHeight(1)
	it.rule:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.18)
	items[i] = it
	return it
end

-- A release's place on the timeline: a gold diamond on the line, its version and date.
local function Mark(i)
	local m = marks[i]
	if m then return m end
	local parent = frame.content
	m = {}
	m.dot = parent:CreateTexture(nil, "OVERLAY")
	m.dot:SetSize(9, 9)
	m.dot:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
	if m.dot.SetRotation then pcall(m.dot.SetRotation, m.dot, math.pi / 4) end -- as Book.lua's diamonds
	m.version = Text(parent, TitleFont(), VERSION_MARK, GOLD)
	m.date = Text(parent, BodyFont(), BODY, CREAM)
	m.date:SetAlpha(0.65)
	m.line = parent:CreateTexture(nil, "ARTWORK")
	m.line:SetWidth(1)
	m.line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.3)
	marks[i] = m
	return m
end

-- Lay out the releases (newest first) and size the window around them.
local function Fill(list)
	local content = frame.content
	local first, last = list[1], list[#list]
	if #list == 1 then
		frame.version:SetText("SanctuaryUI " .. first.version)
	else
		frame.version:SetText(("SanctuaryUI %s to %s"):format(last.version, first.version))
	end
	local textW = WIDTH - 2 * PAD - INDENT - 8
	local lineX = PAD + MARK / 2
	local y = 18
	local n = 0
	for r, release in ipairs(list) do
		local m = Mark(r)
		m.version:SetFont(TitleFont(), VERSION_MARK, "")
		m.date:SetFont(BodyFont(), BODY, "")
		m.dot:ClearAllPoints()
		m.dot:SetPoint("CENTER", content, "TOPLEFT", lineX, -(y + VERSION_MARK * 0.55))
		m.version:ClearAllPoints()
		m.version:SetPoint("TOPLEFT", content, "TOPLEFT", PAD + MARK, -y)
		m.version:SetText(release.version)
		m.date:ClearAllPoints()
		m.date:SetPoint("BOTTOMLEFT", m.version, "BOTTOMRIGHT", 10, 1)
		m.date:SetText(release.date or "")
		local top = y + VERSION_MARK * 0.55 + 8
		y = y + VERSION_MARK + 18
		for i, note in ipairs(release.notes) do
			n = n + 1
			local it = Item(n)
			it.heading:SetFont(TitleFont(), HEADING, "")
			it.text:SetFont(BodyFont(), BODY, "")
			it.button.label:SetFont(TitleFont(), BUTTON, "")
			it.rule:ClearAllPoints()
			if i > 1 then
				it.rule:SetPoint("TOPLEFT", content, "TOPLEFT", PAD + INDENT, -(y - ITEM_GAP / 2))
				it.rule:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD, -(y - ITEM_GAP / 2))
				it.rule:Show()
			else
				it.rule:Hide()
			end
			it.heading:ClearAllPoints()
			it.heading:SetPoint("TOPLEFT", content, "TOPLEFT", PAD + INDENT, -y)
			it.heading:SetText(note[1])
			it.heading:Show()
			it.button:ClearAllPoints()
			if note[3] then
				-- On the heading's line, its middle level with the heading's.
				it.button.label:SetText(note[3])
				it.button:SetPoint("RIGHT", content, "TOPRIGHT", -PAD, -(y + HEADING * 0.55))
				it.button:SetScript("OnClick", function() pcall(note[4]) end)
				it.button:Show()
			else
				it.button:Hide()
			end
			y = y + HEADING + 12
			it.text:ClearAllPoints()
			it.text:SetPoint("TOPLEFT", content, "TOPLEFT", PAD + INDENT, -y)
			it.text:SetWidth(textW)
			it.text:SetText(note[2])
			it.text:Show()
			y = y + math.ceil(it.text:GetStringHeight())
			if i < #release.notes then y = y + ITEM_GAP end
		end
		-- The line runs from under this release's diamond to the next one's.
		m.line:ClearAllPoints()
		if r < #list then
			m.line:SetPoint("TOP", content, "TOPLEFT", lineX, -top)
			m.line:SetHeight(y + RELEASE_GAP - top + 2)
			m.line:Show()
		else
			m.line:Hide()
		end
		for _, piece in ipairs({ m.dot, m.version, m.date }) do piece:Show() end
		y = y + RELEASE_GAP
	end
	for i = n + 1, #items do
		items[i].heading:Hide()
		items[i].text:Hide()
		items[i].button:Hide()
		items[i].rule:Hide()
	end
	for i = #list + 1, #marks do
		for _, piece in ipairs({ marks[i].dot, marks[i].version, marks[i].date, marks[i].line }) do piece:Hide() end
	end
	local full = y - RELEASE_GAP + 24
	content:SetSize(WIDTH, full)
	local view = math.min(full, MAX_BODY)
	frame.scroll:SetHeight(view)
	frame.scroll:SetVerticalScroll(0)
	frame:SetSize(WIDTH, HEADER + 6 + view + 66)
	N.UpdateThumb()
	for _, t in ipairs(frame.glass) do t:Hide() end
	local L = ns.Meter and ns.Meter.Lib
	if L and L.LayGlass then L.LayGlass(frame.head, frame.glass, WIDTH - 14) end
end

local function Place()
	frame:SetScale(ns.Art.D3Scale(Opt().scale) * 1080 / 768)
	frame:ClearAllPoints()
	local off = Opt().offset
	if type(off) == "table" and off[1] then
		local k = UIParent:GetEffectiveScale() / frame:GetEffectiveScale()
		frame:SetPoint("CENTER", UIParent, "CENTER", off[1] * k, off[2] * k)
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
	end
end

-- The releases newer than the one last shown on this account, up to this copy's version.
-- Nothing seen yet: the newest few.
local function Missed()
	local global = Global()
	local seen = global and global.newsSeen
	local list = {}
	for _, r in ipairs(RELEASES) do
		local installed = MINE == "?" or not Newer(r.version, MINE)
		if installed and (seen == nil or Newer(r.version, seen)) then list[#list + 1] = r end
	end
	if seen == nil then
		while #list > FIRST_LOOK do table.remove(list) end
	end
	return list
end

-- Show one release's notes (version), the releases missed ("missed"), or the whole timeline (nil).
function N.Show(version)
	if not frame then Build() end
	local list
	if version == "missed" then
		list = Missed()
	elseif version then
		list = BY_VERSION[version] and { BY_VERSION[version] }
	else
		list = RELEASES
	end
	if not list or #list == 0 then return false end
	shownVersion = list[1].version
	Fill(list)
	Place()
	frame:Show()
	frame:Raise()
	return true
end

function N.Hide()
	if frame then frame:Hide() end
end

function N.ApplySettings()
	if frame and frame:IsShown() then Place() end
end

-- After logging in with releases not yet shown on this account: a few seconds in, out of combat.
local function Due()
	if not Opt().enabled or not Global() then return false end
	return #Missed() > 0
end

function N.Init()
	if not Due() then return end
	local waiter = CreateFrame("Frame")
	local function Try()
		if not Due() then return end
		if InCombatLockdown() then
			waiter:RegisterEvent("PLAYER_REGEN_ENABLED")
			return
		end
		N.Show("missed")
	end
	waiter:SetScript("OnEvent", function(self)
		self:UnregisterEvent("PLAYER_REGEN_ENABLED")
		C_Timer.After(2, Try)
	end)
	C_Timer.After(6, Try)
end
