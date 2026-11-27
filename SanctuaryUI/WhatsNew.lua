SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.WhatsNew = ns.WhatsNew or {}
local N = ns.WhatsNew

-- What's new: after an update, a small D3 window lists what the releases you missed brought,
-- newest first on a timeline, once per account (the newest version shown is kept in the global
-- saved variables). /sanctuary news shows the timeline again, /sanctuary news 0.30.0 one
-- release. Each feature release adds an entry at the top of RELEASES; only the newest KEEP are
-- shown, so the oldest entry can go when one is added.

local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
local MINE = getMeta and getMeta("SanctuaryUI", "Version") or "?"

-- Newest first: { version, date, notes = { { heading, text, button label, action }, ... } }.
local RELEASES = {
	{
		version = "0.37.0", date = "27 November 2026",
		notes = {
			{ "Percentage on the XP rail",
				"Your experience (or reputation) can show as a percentage over the rail, with the numbers too if you like. XP & Reputation > Text on the rail.",
				"Options", function() ns.Options.Open("rail") end },
		},
	},
	{
		version = "0.36.0", date = "27 November 2026",
		notes = {
			{ "Class colours on the target frame",
				"The target and focus health bars can take a player's class colour or one of your own. Frame > Colours.",
				"Options", function() ns.Options.Open("target") end },
			{ "Colour every text",
				"Name, health and level text each pick a colour: class, rank, cream or custom. Text tab.",
				"Options", function() ns.Options.Open("target") end },
		},
	},
	{
		version = "0.35.0", date = "25 November 2026",
		notes = {
			{ "Alarm clock",
				"Set alarms for real-world times: /alarm 14:30 Standup, /alarm in 15 Tea. A window rings at the top of the screen with snooze, and the taskbar icon flashes.",
				"Options", function() ns.Options.Open("alarms") end },
			{ "On the game calendar",
				"Your alarms, and your Outlook meetings if you set up the sync helper, show on the game's calendar days. Click one to change it or add a new alarm." },
		},
	},
	{
		version = "0.34.0", date = "24 November 2026",
		notes = {
			{ "First Aid on the health globe",
				"Bandage yourself and green crosses rise through your health globe, brightening with each tick. Any skill can use the Crosses look.",
				"Options", function() ns.Options.Open("globeAuras") end },
		},
	},
	{
		version = "0.33.0", date = "21 November 2026",
		notes = {
			{ "The books beside your professions",
				"Mining, Cooking and Fishing open their book beside the profession window, which wears the book's stone.",
				"Options", function() ns.Options.Open("mining") end },
			{ "Real levelling guides",
				"Rock Bottom and the Cookbook guide you step by step to 300, marking the step you're on.",
				"Options", function() ns.Options.Open("cookbook") end },
			{ "Slimmer books, quieter memoir",
				"Slim headers on all three books, dimmed outgrown veins, and at most one memoir line per vein.",
				"Options", function() ns.Options.Open("mining") end },
		},
	},
	{
		version = "0.32.0", date = "21 November 2026",
		notes = {
			{ "Rock Bottom: A Miner's Memoir",
				"A mining book: where to dig, every vein, smelts, gems and a memoir that writes itself. /sanctuary mine.",
				"Options", function() ns.Options.Open("mining") end },
			{ "Veins on your maps",
				"Known vein spots on the world map and minimap, ringed in what they still teach you.",
				"Options", function() ns.Options.Open("mining") end },
			{ "Share what you find",
				"New veins you mine reach your group and guild, and theirs reach you, in blue.",
				"Options", function() ns.Options.Open("mining") end },
		},
	},
	{
		version = "0.31.2", date = "18 November 2026",
		notes = {
			{ "Enemy totems, small",
				"Enemy totems show an icon, name and a short bar in their element's colour. Nameplates > Totems.",
				"Options", function() ns.Options.Open("plates") end },
		},
	},
	{
		version = "0.31.1", date = "18 November 2026",
		notes = {
			{ "Enemy players in their class colour",
				"Enemy players' health bars and names show their class colour.",
				"Options", function() ns.Options.Open("plates") end },
		},
	},
	{
		version = "0.31.0", date = "16 November 2026",
		notes = {
			{ "The target's cast, in its health bar",
				"Target and focus casts run along the top of the health bar, grey with a lock when they can't be interrupted.",
				"Options", function() ns.Options.Open("target") end },
			{ "Items and people in the books",
				"Item names show their quality colour; Alliance and Horde names wear their crest.",
				"Journal", function() ns.Journal.Open("now") end },
			{ "Pie menus keep their macros",
				"Rings no longer swap your macros for the first unnamed one.",
				"Options", function() ns.Options.Open("pie") end },
		},
	},
	{
		version = "0.30.0", date = "15 November 2026",
		notes = {
			{ "Search the options",
				"A search box at the top of the options finds any setting as you type. /sanctuary search <words>.",
				"Search", function() ns.Options.Search("") end },
		},
	},
	{
		version = "0.29.1", date = "15 November 2026",
		notes = {
			{ "Threat on the nameplates",
				"In a group, enemy health bars turn gold as you near pulling them and orange when they're on you (reversed for tanks).",
				"Options", function() ns.Options.Open("plates") end },
		},
	},
}
N.RELEASES = RELEASES -- for tools/ui_preview/news_preview.py
local BY_VERSION = {}
for _, r in ipairs(RELEASES) do BY_VERSION[r.version] = r end
-- A first look (nothing seen yet on this account): only this many of the newest releases.
local FIRST_LOOK = 3
local KEEP = 10 -- releases on the timeline
N.KEEP = KEEP

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
local WIDTH = 400
local PAD = 18
local HEADER = 34
-- Text sizes: the header's title and version, a release's version on the timeline, each note's
-- heading and text, the buttons.
local TITLE, VERSION, VERSION_MARK, HEADING, BODY, BUTTON, OK = 14, 9, 12, 10, 9, 8, 10
local LINE_GAP = 2 -- between a note's lines
local ITEM_GAP = 12 -- between notes; a faint rule sits in its middle
local RELEASE_GAP = 16 -- between releases on the timeline
local MARK = 14 -- the timeline's line runs this far in from PAD; notes start past it
local INDENT = 2 * MARK -- notes' left edge, from PAD
local HEAD_GAP = 6 -- under a release's version, and under a note's heading
local OK_W, OK_H, OK_BELOW = 104, 26, 10 -- the Got it button, and its gap from the bottom
local FOOT = OK_H + 2 * OK_BELOW -- under the timeline, for the button
local MAX_BODY = 380 -- taller than this, the timeline scrolls
local STEP = 40 -- a mouse wheel notch

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
	frame.title:SetPoint("LEFT", head, "LEFT", 12, -1)
	frame.title:SetText("What's new")
	frame.version = Text(head, BodyFont(), VERSION, CREAM, "RIGHT")
	frame.version:SetPoint("RIGHT", head, "RIGHT", -12, -1)

	-- The timeline scrolls inside the window when it is taller than MAX_BODY.
	local scroll = CreateFrame("ScrollFrame", nil, frame)
	scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -HEADER - 3)
	scroll:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -HEADER - 3)
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
	track:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -7, -4)
	track:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", -7, 4)
	track:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.12)
	local thumb = frame:CreateTexture(nil, "OVERLAY")
	thumb:SetWidth(2)
	thumb:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.6)
	frame.track, frame.thumb = track, thumb

	frame.ok = Plate(frame, OK_W, OK_H, "Got it", OK)
	frame.ok:SetPoint("BOTTOM", frame, "BOTTOM", 0, OK_BELOW)
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
	thumb:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -7, -4 - (span - size) * at)
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
	it.button = Plate(parent, 64, 18, "", BUTTON)
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
	m.dot:SetSize(7, 7)
	m.dot:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
	if m.dot.SetRotation then pcall(m.dot.SetRotation, m.dot, math.pi / 4) end -- as Book.lua's diamonds
	m.version = Text(parent, TitleFont(), VERSION_MARK, GOLD)
	m.date = Text(parent, BodyFont(), BODY, CREAM)
	m.date:SetAlpha(0.65)
	m.new = Text(parent, TitleFont(), BODY, { 1, 0.45, 0.25 })
	m.line = parent:CreateTexture(nil, "ARTWORK")
	m.line:SetWidth(1)
	m.line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.3)
	marks[i] = m
	return m
end

-- Lay out the releases (newest first) and size the window around them.
local function Fill(list, newSet)
	local content = frame.content
	local first, last = list[1], list[#list]
	if #list == 1 then
		frame.version:SetText("SanctuaryUI " .. first.version)
	else
		frame.version:SetText(("SanctuaryUI %s to %s"):format(last.version, first.version))
	end
	local textW = WIDTH - 2 * PAD - INDENT - 8
	local lineX = PAD + MARK / 2
	local y = 14
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
		m.date:SetPoint("BOTTOMLEFT", m.version, "BOTTOMRIGHT", 8, 1)
		m.date:SetText(release.date or "")
		-- Releases this account hasn't seen yet are marked.
		m.new:SetFont(TitleFont(), BODY, "")
		m.new:ClearAllPoints()
		m.new:SetPoint("LEFT", m.date, "RIGHT", 8, 0)
		m.new:SetText(newSet and newSet[release.version] and "NEW" or "")
		m.new:Show()
		local top = y + VERSION_MARK * 0.55 + 6
		y = y + VERSION_MARK + HEAD_GAP + 2
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
			y = y + HEADING + HEAD_GAP
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
		for _, piece in ipairs({ marks[i].dot, marks[i].version, marks[i].date, marks[i].line, marks[i].new }) do piece:Hide() end
	end
	local full = y - RELEASE_GAP + 8
	content:SetSize(WIDTH, full)
	local view = math.min(full, MAX_BODY)
	frame.scroll:SetHeight(view)
	frame.scroll:SetVerticalScroll(0)
	frame:SetSize(WIDTH, HEADER + 3 + view + FOOT)
	N.UpdateThumb()
	for _, t in ipairs(frame.glass) do t:Hide() end
	local L = ns.Meter and ns.Meter.Lib
	if L and L.LayGlass then L.LayGlass(frame.head, frame.glass, WIDTH - 14, HEADER - 8) end
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

-- The newest KEEP releases up to this copy's version, newest first: the timeline.
local function Timeline()
	local list = {}
	for _, r in ipairs(RELEASES) do
		if #list >= KEEP then break end
		if MINE == "?" or not Newer(r.version, MINE) then list[#list + 1] = r end
	end
	return list
end

-- Show one release's notes (version), or the whole timeline (nil, or "missed" after an update).
-- The timeline is always the last KEEP releases, newest first, with the releases this account
-- hasn't seen yet marked NEW: a new release is added on top, never in place of the older ones.
function N.Show(version)
	if not frame then Build() end
	local list, newSet
	if version and version ~= "missed" then
		list = BY_VERSION[version] and { BY_VERSION[version] }
	else
		list = Timeline()
		newSet = {}
		for _, r in ipairs(Missed()) do newSet[r.version] = true end
	end
	if not list or #list == 0 then return false end
	shownVersion = list[1].version
	Fill(list, newSet)
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
