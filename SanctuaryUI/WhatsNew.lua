SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.WhatsNew = ns.WhatsNew or {}
local N = ns.WhatsNew

-- What's new: after an update, a small D3 window lists what the release brought, once per
-- account (the last version shown is kept in the global saved variables). /sanctuary news
-- shows it again. Each release adds its notes to NOTES below, under the .toc's version.

local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
local MINE = getMeta and getMeta("SanctuaryUI", "Version") or "?"

-- version -> list of { heading, text, button label, action }. Newest first in LATEST.
local NOTES = {
	["0.25.0"] = {
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
}
local LATEST = "0.25.0"

local GOLD = { 0.91, 0.78, 0.48 }
local CREAM = { 0.89, 0.84, 0.75 }
local WIDTH = 560
local PAD = 24
local HEADER = 52

local frame
local items = {}
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
	frame.title = Text(head, TitleFont(), 22, GOLD)
	frame.title:SetPoint("LEFT", head, "LEFT", 18, -1)
	frame.title:SetText("What's new")
	frame.version = Text(head, BodyFont(), 15, CREAM, "RIGHT")
	frame.version:SetPoint("RIGHT", head, "RIGHT", -18, -1)

	frame.ok = Plate(frame, 170, 40, "Got it", 16)
	frame.ok:SetPoint("BOTTOM", frame, "BOTTOM", 0, 16)
	frame.ok:SetScript("OnClick", function() frame:Hide() end)

	frame:SetScript("OnHide", function()
		local global = Global()
		if global and shownVersion then global.newsSeen = shownVersion end
	end)
end

local function Item(i)
	local it = items[i]
	if it then return it end
	it = {}
	it.heading = Text(frame, TitleFont(), 17, GOLD)
	it.text = Text(frame, BodyFont(), 14, CREAM)
	it.text:SetWordWrap(true)
	it.text:SetSpacing(2)
	it.button = Plate(frame, 104, 28, "", 12)
	items[i] = it
	return it
end

-- Lay the notes for version out and size the window around them.
local function Fill(version)
	local notes = NOTES[version] or {}
	frame.version:SetText("SanctuaryUI " .. version)
	local y = HEADER + 18
	for i, note in ipairs(notes) do
		local it = Item(i)
		it.heading:SetFont(TitleFont(), 17, "")
		it.text:SetFont(BodyFont(), 14, "")
		it.heading:ClearAllPoints()
		it.heading:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
		it.heading:SetText(note[1])
		it.heading:Show()
		it.button:ClearAllPoints()
		if note[3] then
			it.button.label:SetText(note[3])
			it.button:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -(y - 5))
			it.button:SetScript("OnClick", function() pcall(note[4]) end)
			it.button:Show()
		else
			it.button:Hide()
		end
		y = y + 26
		it.text:ClearAllPoints()
		it.text:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
		it.text:SetWidth(WIDTH - 2 * PAD)
		it.text:SetText(note[2])
		it.text:Show()
		y = y + math.ceil(it.text:GetStringHeight()) + 20
	end
	for i = #notes + 1, #items do
		items[i].heading:Hide()
		items[i].text:Hide()
		items[i].button:Hide()
	end
	frame:SetSize(WIDTH, y + 64)
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

-- Show the notes for version (default: this copy's, else the latest there are).
function N.Show(version)
	if not frame then Build() end
	version = version or (NOTES[MINE] and MINE) or LATEST
	if not NOTES[version] then return false end
	shownVersion = version
	Fill(version)
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

-- After logging in on a version with notes not yet shown: a few seconds in, out of combat.
local function Due()
	local global = Global()
	return Opt().enabled and NOTES[MINE] ~= nil and global ~= nil and global.newsSeen ~= MINE
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
		N.Show(MINE)
	end
	waiter:SetScript("OnEvent", function(self)
		self:UnregisterEvent("PLAYER_REGEN_ENABLED")
		C_Timer.After(2, Try)
	end)
	C_Timer.After(6, Try)
end
