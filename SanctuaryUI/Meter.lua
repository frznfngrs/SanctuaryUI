SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.Meter = ns.Meter or {}

-- Damage meter: forged rails, one per player, under a title strip.
--
-- Forever has no combat log for addons (asking for its event is a blocked action). The client
-- keeps the tallies itself and hands them over through C_DamageMeter. What MeterProbe.lua found:
--   In combat every amount, name and GUID is secret. They can be drawn (StatusBar values,
--   SetText, AbbreviateLargeNumbers, string.format) but never compared or added up. The list
--   comes sorted, and isLocalPlayer and classFilename stay plain, so rank and class are known.
--   Half a second after combat everything is plain: shares, margins and per-ability breakdowns
--   are worked out then.
-- All sizes below are in the mockup's pixels (mockups/damage-meter-rails.png, drawn at 2x); the
-- holder's half-scale canvas brings them to the screen.

local HALF = 0.5 -- the mockups are 2x
local STUD = 56 -- the rank stud's column, left of the rails
local HEAD0 = 66 -- title strip and the gap under it
local LABELS = 26 -- the column headings under the strip
local NAME_W = 165 -- room for a first name: a secret "First Last" wraps at the space and loses its second line
local RAIL_H = 50 -- the mockup's rail; the Rail height option scales the row from it
local RAIL_GAP = 2
local CAP = 40 -- art pixels of a rail's pointed end
local FOOT = 66 -- the verdict, up to two lines
local INTERVAL = 0.25 -- the client reports up to ~20 times a second; this is how often we redraw
local GOLD = { 0.91, 0.78, 0.48 }
local CREAM = { 0.89, 0.84, 0.75 }
local IRON = { 0.62, 0.52, 0.42 } -- the iron rail blackened, warm like the D3 window's frame

-- key: Enum.DamageMeterType's name. rate: the client also gives a per-second figure worth showing.
local VIEWS = {
	{ key = "DamageDone", label = "Damage", rate = true },
	{ key = "Dps", label = "DPS", rate = true },
	{ key = "HealingDone", label = "Healing", rate = true },
	{ key = "Hps", label = "HPS", rate = true },
	{ key = "Absorbs", label = "Absorbs" },
	{ key = "Interrupts", label = "Interrupts" },
	{ key = "Dispels", label = "Dispels" },
	{ key = "DamageTaken", label = "Damage taken", rate = true },
	{ key = "AvoidableDamageTaken", label = "Avoidable damage" },
	{ key = "Deaths", label = "Deaths" },
	{ key = "EnemyDamageTaken", label = "Enemy damage taken", enemies = true },
}
ns.Meter.VIEWS = VIEWS
local viewByKey = {}
for _, v in ipairs(VIEWS) do viewByKey[v.key] = v end

ns.Meter.STYLES = { glass = "Red glass header", shadow = "Glass and shadow", plaque = "Red plaque" }
ns.Meter.STYLE_ORDER = { "glass", "shadow", "plaque" }

-- A made-up fight for the preview and for placing the frame: five players, and for each view who
-- did how much ({ player, amount }, largest first), so changing the view changes the rails.
local PREVIEW_PLAYERS = {
	{ name = "Thalric", class = "HUNTER" },
	{ name = "You", class = "WARRIOR", mine = true },
	{ name = "Mirelle", class = "MAGE" },
	{ name = "Osgood", class = "PALADIN" },
	{ name = "Zinnia", class = "SHAMAN" },
}
local PREVIEW_ENEMIES = { "Bandit Captain", "Bandit Archer", "War Hound", "Bandit Thug" }
local PREVIEW_SECONDS = 170
local PREVIEW = {
	DamageDone = { { 1, 218300 }, { 2, 187700 }, { 3, 155000 }, { 4, 83000 }, { 5, 37100 } },
	HealingDone = { { 5, 96400 }, { 4, 71200 }, { 2, 9800 }, { 1, 4100 } },
	Absorbs = { { 4, 18200 }, { 5, 6100 } },
	Interrupts = { { 2, 4 }, { 5, 2 }, { 3, 1 } },
	Dispels = { { 5, 3 }, { 4, 2 } },
	DamageTaken = { { 2, 141000 }, { 4, 38000 }, { 1, 22500 }, { 3, 19800 }, { 5, 12100 } },
	AvoidableDamageTaken = { { 3, 9400 }, { 1, 6200 }, { 2, 1800 } },
	Deaths = { { 3, 1 }, { 5, 1 } },
	EnemyDamageTaken = { { 1, 262000 }, { 2, 171000 }, { 3, 149000 }, { 4, 99100 } },
}
PREVIEW.Dps, PREVIEW.Hps = PREVIEW.DamageDone, PREVIEW.HealingDone

local function Opt()
	return ns.DB().meter
end

local function RailH()
	return math.max(24, Opt().railHeight or RAIL_H)
end

local function Pitch()
	return RailH() + RAIL_GAP
end

-- Where the first rail starts.
local function Head()
	return HEAD0 + (Opt().headers and LABELS or 0)
end

local Secret = function(value) return ns.Secret(value) end

local function SecretTable(t)
	return issecrettable and issecrettable(t) or false
end

local holder, canvas -- canvas: the holder's child at half scale, where everything is drawn
local rows = {}
local inCombat = false
local dirty, sinceDraw, sinceClock = true, 0, 0
local offset = 0 -- rows scrolled past
local segment = "current" -- "current" | "overall" | a past fight's session ID
local detail -- the player whose abilities are listed, or nil for the list of players
local verdict -- the line under the list after a fight
local unlockTicker

---------------------------------------------------------------------------
-- The client's data

local function API()
	return C_DamageMeter
end

function ns.Meter.Supported()
	return API() ~= nil and Enum and Enum.DamageMeterType ~= nil
end

local function Available()
	if not ns.Meter.Supported() then return false end
	local ok, available = pcall(API().IsDamageMeterAvailable)
	return ok and not Secret(available) and available and true or false
end

local function SessionType(which)
	local st = Enum.DamageMeterSessionType or {}
	return which == "overall" and (st.Overall or 0) or (st.Current or 1)
end

-- The session on show for one meter type, or nil.
local function Fetch(seg, typeValue)
	local ok, session
	if type(seg) == "number" then
		ok, session = pcall(API().GetCombatSessionFromID, seg, typeValue)
	else
		ok, session = pcall(API().GetCombatSessionFromType, SessionType(seg), typeValue)
	end
	if not ok or type(session) ~= "table" then return nil end
	local sources = session.combatSources
	if type(sources) ~= "table" or SecretTable(sources) then return nil end
	return session
end

local function FetchSource(seg, typeValue, guid, creatureID)
	local ok, data
	if type(seg) == "number" then
		ok, data = pcall(API().GetCombatSessionSourceFromID, seg, typeValue, guid, creatureID)
	else
		ok, data = pcall(API().GetCombatSessionSourceFromType, SessionType(seg), typeValue, guid, creatureID)
	end
	if not ok or type(data) ~= "table" or type(data.combatSpells) ~= "table" or SecretTable(data.combatSpells) then return nil end
	return data
end

local function Sessions()
	local ok, list = pcall(API().GetAvailableCombatSessions)
	return ok and type(list) == "table" and list or {}
end

local function Duration(seg)
	if type(seg) == "number" then
		for _, s in ipairs(Sessions()) do
			if not Secret(s.sessionID) and s.sessionID == seg then return s.durationSeconds end
		end
		return nil
	end
	local ok, seconds = pcall(API().GetSessionDurationSeconds, SessionType(seg))
	return ok and seconds or nil
end

local function View()
	return viewByKey[Opt().view] or VIEWS[1]
end

local function TypeValue(view)
	return Enum.DamageMeterType[view.key]
end

---------------------------------------------------------------------------
-- Text

-- Plain numbers: 9,412 / 218.3K / 1.25M.
local function Short(value)
	if value >= 1e6 then return ("%.2fM"):format(value / 1e6) end
	if value >= 1e4 then return ("%.1fK"):format(value / 1e3) end
	local whole = math.floor(value + 0.5)
	return BreakUpLargeNumbers and BreakUpLargeNumbers(whole) or tostring(whole)
end

-- A number for a font string: ours when it can be read, the client's own shortening when secret.
local function Num(value)
	if value == nil then return "" end
	if not Secret(value) then return Short(value) end
	local ok, text = pcall(AbbreviateLargeNumbers, value)
	if ok then return text end
	ok, text = pcall(string.format, "%d", value)
	return ok and text or ""
end

local function Clock(seconds)
	if seconds == nil or Secret(seconds) then return "" end
	seconds = math.floor(seconds)
	if seconds >= 3600 then return ("%d:%02d:%02d"):format(seconds / 3600, seconds % 3600 / 60, seconds % 60) end
	return ("%d:%02d"):format(seconds / 60, seconds % 60)
end

-- Characters on Forever have a first and a last name, joined by the client's separator.
local SURNAME_SEP = Constants and Constants.CharacterNameSeparatorConsts
	and Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR or " "

local function IsPlayerClass(class)
	return class ~= nil and not Secret(class) and RAID_CLASS_COLORS ~= nil and RAID_CLASS_COLORS[class] ~= nil
end

-- A name's first letter (a whole UTF-8 character).
local function Initial(word)
	return word:match("^[%z\1-\127\194-\244][\128-\191]*") or ""
end

-- A name for a rail. Players lose their last name unless the option keeps it; creatures keep
-- every word. A secret name comes back as it is (FillRow narrows the text instead).
local function ShortName(name, player)
	if name == nil or Secret(name) then return name end
	if Ambiguate then name = Ambiguate(name, "short") or name end
	local how = Opt().names
	if player and how ~= "full" then
		local at = name:find(SURNAME_SEP, 2, true)
		if at then
			local first, last = name:sub(1, at - 1), name:sub(at + #SURNAME_SEP)
			if how == "firstInitial" and last ~= "" then
				name = first .. " " .. Initial(last) .. "."
			elseif how == "initialLast" and last ~= "" then
				name = Initial(first) .. ". " .. last
			else
				name = first
			end
		end
	end
	return name
end

local function ClassColor(class, enemy)
	if class ~= nil and not Secret(class) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] then
		local c = RAID_CLASS_COLORS[class]
		return c.r, c.g, c.b
	end
	if enemy then return 0.72, 0.24, 0.2 end
	return 0.62, 0.56, 0.46
end

local ORDINAL = { "First", "Second", "Third", "Fourth", "Fifth", "Sixth", "Seventh", "Eighth", "Ninth", "Tenth" }

---------------------------------------------------------------------------
-- Art

local function Coords(tex, x, y, w, h, size, sizeY)
	tex:SetTexCoord(x / size, (x + w) / size, y / (sizeY or size), (y + h) / (sizeY or size))
end

local function Parts()
	return ns.Art.Require("targetStyleParts")
end

-- A rail's three slices from the parts sheet: 0 iron, 2 gold, 3 molten (your rail on a streak).
local function DressRail(row, kind)
	if row.railKind == kind then return end
	row.railKind = kind
	local y = 562 + kind * 52
	Coords(row.railL, 4, y, CAP, 46, 1024)
	Coords(row.railM, 4 + CAP, y, 502 - 2 * CAP, 46, 1024)
	Coords(row.railR, 506 - CAP, y, CAP, 46, 1024)
	local c = kind == 0 and IRON or { 1, 1, 1 }
	for _, t in ipairs({ row.railL, row.railM, row.railR }) do t:SetVertexColor(c[1], c[2], c[3]) end
	Coords(row.stud, kind * 48, 768, 48, 48, 1024)
	if kind == 0 then
		row.stud:SetVertexColor(IRON[1] * 1.2, IRON[2] * 1.2, IRON[3] * 1.2)
		row.rank:SetTextColor(CREAM[1], CREAM[2], CREAM[3])
	elseif kind == 3 then
		row.stud:SetVertexColor(1, 1, 1)
		row.rank:SetTextColor(1, 0.78, 0.42)
	else
		row.stud:SetVertexColor(1, 1, 1)
		row.rank:SetTextColor(0.12, 0.08, 0.03)
	end
end

local function Text(parent, font, size, color, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFont(font, size, "")
	fs:SetShadowColor(0, 0, 0, 1)
	fs:SetShadowOffset(2, -2)
	fs:SetTextColor(color[1], color[2], color[3])
	fs:SetJustifyH(justify or "LEFT")
	fs:SetWordWrap(false)
	return fs
end

-- The meter's own fonts: one for the rails (names and numbers), one for the title strip. Any
-- face from Options > Fonts' list; "wow" and "d3" (the defaults) follow the addon's body and
-- title fonts there.
local function BodyFont()
	return ns.Fonts.Path("body", Opt().font)
end

local function TitleFont()
	return ns.Fonts.Path("title", Opt().titleFont)
end

---------------------------------------------------------------------------
-- Rows

local OpenDetail, CloseDetail -- below

-- Everything in a row that follows the Rail height and Text size options.
local function SizeRow(row)
	local h = RailH()
	local k = h / RAIL_H
	local f = k * (Opt().textScale or 1)
	row:SetHeight(h)
	local stud = math.min(h - 8, STUD - 10)
	row.stud:SetSize(stud, stud)
	row.icon:SetSize(stud - 4, stud - 4)
	local capW = CAP * h / 46
	row.railL:SetSize(capW, h)
	row.railR:SetSize(capW, h)
	row.bar:ClearAllPoints()
	row.bar:SetPoint("TOPLEFT", row, "TOPLEFT", STUD + 26 * k, -h * 0.3)
	row.bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -26 * k, h * 0.3)
	for _, fs in ipairs({ row.rank, row.pct, row.total, row.rate }) do fs:SetFont(BodyFont(), math.max(10, 21 * f), "") end
	row.name:SetFont(BodyFont(), math.max(10, 22 * f), "")
	row.pct:SetWidth(62 * f)
	row.total:SetWidth(96 * f)
	row.rate:SetWidth(82 * f)
	row.nameW = NAME_W * f
end

local function MakeRow(i)
	local row = CreateFrame("Button", nil, canvas)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	local parts = Parts()

	row.stud = row:CreateTexture(nil, "ARTWORK")
	row.stud:SetPoint("LEFT", row, "LEFT", 8, 0)
	row.icon = row:CreateTexture(nil, "ARTWORK", nil, 1)
	row.icon:SetPoint("CENTER", row.stud, "CENTER")
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	row.icon:Hide()
	row.mine = row:CreateTexture(nil, "OVERLAY")
	row.mine:SetSize(14, 18)
	row.mine:SetPoint("RIGHT", row.stud, "LEFT", 4, 0)
	row.mine:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
	row.mine:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
	row.mine:Hide()

	row.railL = row:CreateTexture(nil, "BORDER")
	row.railM = row:CreateTexture(nil, "BORDER")
	row.railR = row:CreateTexture(nil, "BORDER")
	row.railL:SetPoint("LEFT", row, "LEFT", STUD, 0)
	row.railR:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	row.railM:SetPoint("TOPLEFT", row.railL, "TOPRIGHT")
	row.railM:SetPoint("BOTTOMRIGHT", row.railR, "BOTTOMLEFT")
	for _, t in ipairs({ row.railL, row.railM, row.railR, row.stud }) do
		if parts then t:SetTexture(parts) else t:SetColorTexture(0.12, 0.1, 0.08, 0.9) end
	end

	row.bar = CreateFrame("StatusBar", nil, row)
	row.bar:SetStatusBarTexture(ns.Art.Path("unitFillWhite") or "Interface\\Buttons\\WHITE8X8")
	row.bar:SetMinMaxValues(0, 1)
	row.bar:SetValue(0)
	if not parts then
		local bg = row.bar:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0.02, 0.02, 0.02, 0.9)
	end

	local over = CreateFrame("Frame", nil, row.bar)
	over:SetAllPoints(row)
	over:SetFrameLevel(row.bar:GetFrameLevel() + 2)
	row.rank = Text(over, BodyFont(), 21, CREAM, "CENTER")
	row.rank:SetPoint("CENTER", row.stud, "CENTER", 0, 0)
	row.pct = Text(over, BodyFont(), 21, CREAM, "RIGHT")
	row.pct:SetPoint("RIGHT", row.bar, "RIGHT", -8, 0)
	row.total = Text(over, BodyFont(), 21, CREAM, "RIGHT")
	row.rate = Text(over, BodyFont(), 21, CREAM, "RIGHT")
	row.rate:SetPoint("RIGHT", row.total, "LEFT", -10, 0)
	row.name = Text(over, BodyFont(), 22, CREAM, "LEFT")
	row.name:SetPoint("LEFT", row.bar, "LEFT", 10, 0)

	row.railKind = nil
	DressRail(row, 0)
	SizeRow(row)

	row:SetScript("OnClick", function(self, button)
		if button == "RightButton" then
			if detail then CloseDetail() else ns.Meter.SegmentMenu(self) end
		elseif self.source and not detail then
			OpenDetail(self.source)
		end
	end)
	row:SetScript("OnMouseWheel", function(_, delta) ns.Meter.Scroll(-delta) end)
	row:EnableMouseWheel(true)
	rows[i] = row
	return row
end

-- Which of rate / total / share a row shows, right to left.
local function Columns(row, showRate, showPct, firstOnly)
	row.pct:SetShown(showPct)
	row.rate:SetShown(showRate)
	row.total:ClearAllPoints()
	if showPct then
		row.total:SetPoint("RIGHT", row.pct, "LEFT", -10, 0)
	else
		row.total:SetPoint("RIGHT", row.bar, "RIGHT", -8, 0)
	end
	row.name:ClearAllPoints()
	row.name:SetPoint("LEFT", row.bar, "LEFT", 10, 0)
	if firstOnly then
		-- A secret full name can't be cut, but it can be wrapped: too narrow for both names, one
		-- line high, so only the first name shows.
		row.name:SetWidth(row.nameW or NAME_W)
		row.name:SetWordWrap(true)
		if row.name.SetMaxLines then row.name:SetMaxLines(1) end
	else
		row.name:SetWordWrap(false)
		row.name:SetPoint("RIGHT", showRate and row.rate or row.total, "LEFT", -8, 0)
	end
end

-- entry: name, class, total, top, sum, rate, rank, mine, gold, enemy, icon. Amounts may be secret.
local function FillRow(row, entry, view)
	row.bar:SetMinMaxValues(0, entry.top)
	row.bar:SetValue(entry.total)
	local r, g, b = ClassColor(entry.class, entry.enemy)
	row.bar:SetStatusBarColor(r * 0.82, g * 0.82, b * 0.82)
	row.name:SetText(entry.name)
	local c = entry.mine and GOLD or CREAM
	row.name:SetTextColor(c[1], c[2], c[3])
	row.mine:SetShown(entry.mine and true or false)

	local plain = not Secret(entry.total) and not Secret(entry.sum)
	local showPct = plain and entry.sum ~= nil and entry.sum > 0
	local showRate = view.rate and entry.rate ~= nil
	Columns(row, showRate, showPct, entry.player and Secret(entry.name) and Opt().names ~= "full")
	row.total:SetText(Num(entry.total))
	if showRate then row.rate:SetText(Num(entry.rate)) end
	if showPct then row.pct:SetFormattedText("%d%%", entry.total / entry.sum * 100 + 0.5) end

	local onFire = entry.mine and ns.MeterGlory and ns.MeterGlory.OnFire()
	DressRail(row, onFire and 3 or (entry.gold and 2 or 0))
	row.isMine = entry.mine and true or false
	if entry.icon then
		row.icon:SetTexture(entry.icon)
		row.icon:Show()
		row.stud:Hide()
		row.rank:SetText("")
	else
		row.icon:Hide()
		row.stud:SetShown(Opt().ranks)
		row.rank:SetText(Opt().ranks and entry.rank or "")
	end
	row.source = entry.source
	row:Show()
end

---------------------------------------------------------------------------
-- The list of players

local function Previewing()
	return ns.Meter.preview or (holder and holder.unlocked)
end

local function MyIndex(sources)
	for i = 1, #sources do
		local mine = sources[i].isLocalPlayer
		if not Secret(mine) and mine then return i end
	end
end

local function SourceEntry(s, i, session, view)
	local mine = not Secret(s.isLocalPlayer) and s.isLocalPlayer or false
	local player = IsPlayerClass(s.classFilename)
	local name = ShortName(s.name, player)
	-- Your own name is always readable, even while the list's copy is secret.
	if mine and Secret(name) and UnitName then
		local own = UnitName("player")
		if own and not Secret(own) then
			local full = ns.UnitDisplayName and ns.UnitDisplayName("player", true)
			name = (full and not Secret(full)) and ShortName(full, true) or own
		end
	end
	local entry = {
		name = name, player = player, class = s.classFilename, total = s.totalAmount, top = session.maxAmount,
		sum = session.totalAmount, rate = s.amountPerSecond, rank = i, mine = mine, enemy = view.enemies,
		gold = i == 1 and Opt().goldLeader and not view.enemies,
	}
	-- Abilities can be listed once the GUID can be read (out of combat).
	if not Secret(s.sourceGUID) and not Secret(s.name) and (s.sourceGUID ~= nil or s.sourceCreatureID ~= nil) then
		entry.source = { guid = s.sourceGUID, creatureID = s.sourceCreatureID, name = entry.name, class = s.classFilename }
	end
	return entry
end

-- The entries to draw, top down, and how many the list holds in all.
local function ListEntries(view)
	local max = Opt().rows
	local entries = {}
	if Previewing() and not inCombat then
		local list = PREVIEW[view.key] or PREVIEW.DamageDone
		local sum = 0
		for _, item in ipairs(list) do sum = sum + item[2] end
		for i, item in ipairs(list) do
			if i > max then break end
			local who = PREVIEW_PLAYERS[item[1]]
			local entry = { total = item[2], top = list[1][2], sum = sum, rate = item[2] / PREVIEW_SECONDS, rank = i }
			if view.enemies then
				entry.name, entry.enemy = PREVIEW_ENEMIES[item[1]], true
			else
				entry.name = who.mine and UnitName and UnitName("player") or who.name
				entry.class = who.mine and select(2, UnitClass("player")) or who.class
				entry.mine, entry.player = who.mine, true
				entry.gold = i == 1 and Opt().goldLeader
			end
			entries[i] = entry
		end
		return entries, #list
	end
	local session = Fetch(segment, TypeValue(view))
	if not session then return entries, 0 end
	local sources = session.combatSources
	local n = #sources
	offset = math.max(0, math.min(offset, n - max))
	local last = math.min(n, offset + max)
	for i = offset + 1, last do
		entries[#entries + 1] = SourceEntry(sources[i], i, session, view)
	end
	-- You, on the last rail, when the list has run past you.
	if Opt().pinSelf and #entries > 0 then
		local mine = MyIndex(sources)
		if mine and (mine > last or mine <= offset) then
			entries[#entries] = SourceEntry(sources[mine], mine, session, view)
		end
	end
	return entries, n
end

---------------------------------------------------------------------------
-- One player's abilities (plain data only, so out of combat)

local GetSpellName = (C_Spell and C_Spell.GetSpellName) or function(id) return GetSpellInfo and (GetSpellInfo(id)) end
local GetSpellTexture = (C_Spell and C_Spell.GetSpellTexture) or GetSpellTexture

local function DetailEntries(view)
	local data = FetchSource(detail.segment, TypeValue(view), detail.guid, detail.creatureID)
	if not data or Secret(data.totalAmount) then return nil end
	local spells = {}
	for _, spell in ipairs(data.combatSpells) do
		if Secret(spell.totalAmount) or Secret(spell.spellID) then return nil end
		spells[#spells + 1] = spell
	end
	table.sort(spells, function(a, b) return a.totalAmount > b.totalAmount end)
	local max = Opt().rows
	offset = math.max(0, math.min(offset, #spells - max))
	local top = spells[1] and spells[1].totalAmount or 0
	local entries = {}
	for i = offset + 1, math.min(#spells, offset + max) do
		local spell = spells[i]
		local name = GetSpellName(spell.spellID) or ("Spell " .. tostring(spell.spellID))
		local pet = spell.creatureName
		if pet ~= nil and not Secret(pet) and pet ~= "" then name = name .. " (" .. pet .. ")" end
		entries[#entries + 1] = { name = name, class = detail.class, total = spell.totalAmount, top = top, sum = data.totalAmount,
			rate = spell.amountPerSecond, rank = i, enemy = view.enemies, icon = GetSpellTexture and GetSpellTexture(spell.spellID) or 134400 }
	end
	return entries, #spells
end

OpenDetail = function(source)
	if inCombat then
		ns.Print("abilities open when the fight ends: the game hides them from addons in combat.")
		return
	end
	detail = { guid = source.guid, creatureID = source.creatureID, name = source.name, class = source.class, segment = segment }
	offset = 0
	ns.Meter.Draw()
end

CloseDetail = function()
	if not detail then return end
	detail = nil
	offset = 0
	ns.Meter.Draw()
end

---------------------------------------------------------------------------
-- Drawing

local function SegmentLabel()
	if segment == "current" then return "Current fight" end
	if segment == "overall" then return "Overall" end
	for _, s in ipairs(Sessions()) do
		if not Secret(s.sessionID) and s.sessionID == segment then
			return (not Secret(s.name) and s.name ~= "" and s.name) or ("Fight " .. segment)
		end
	end
	return "Fight " .. tostring(segment)
end

local function DrawClock()
	if not holder then return end
	if Previewing() and not inCombat then
		holder.clock:SetText("1:42")
	else
		holder.clock:SetText(Clock(Duration(detail and detail.segment or segment)))
	end
end

function ns.Meter.Draw()
	if not holder or not holder:IsShown() then return end
	dirty, sinceDraw = false, 0
	local view = View()
	local entries, total
	if detail then
		entries, total = DetailEntries(view)
		if not entries then
			detail = nil
		end
	end
	if not detail then entries, total = ListEntries(view) end

	if detail then
		holder.title:SetText(detail.name or "")
		holder.sub:SetText(view.label .. " by ability")
	else
		holder.title:SetText(view.label)
		holder.sub:SetText(SegmentLabel())
	end
	DrawClock()

	for i = 1, math.max(#rows, #entries) do
		local row = rows[i] or MakeRow(i)
		if entries[i] then
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, -(Head() + (i - 1) * Pitch()))
			row:SetPoint("RIGHT", canvas, "RIGHT", 0, 0)
			FillRow(row, entries[i], view)
		else
			row:Hide()
		end
	end
	holder.empty:SetShown(#entries == 0)
	holder.empty:ClearAllPoints()
	holder.empty:SetPoint("TOPLEFT", canvas, "TOPLEFT", STUD + 12, -(Head() + 12))
	holder.shown = #entries

	-- Column headings, over whichever columns the first rail shows.
	local first = rows[1]
	for key, label in pairs(holder.labels) do
		local column = first and first[key]
		local show = Opt().headers and #entries > 0 and column and column:IsShown()
		label:SetShown(show and true or false)
		if show then
			label:ClearAllPoints()
			label:SetPoint("RIGHT", column, "RIGHT", 0, RailH() / 2 + LABELS / 2 + 2)
		end
	end

	-- The verdict sits under the last rail; the panel (Glass and shadow) ends under both.
	local showVerdict = verdict and Opt().verdict and not detail and segment == "current" and not inCombat and #entries > 0
	holder.verdict:SetShown(showVerdict and true or false)
	if showVerdict then
		holder.verdict:SetWidth(math.max(360, Opt().width) - 16)
		holder.verdict:SetWordWrap(true)
		holder.verdict:SetText(verdict)
		holder.verdict:ClearAllPoints()
		holder.verdict:SetPoint("TOPLEFT", canvas, "TOPLEFT", STUD + 8, -(Head() + #entries * Pitch() + 8))
	end
	local bodyH = Head() + math.max(1, #entries) * Pitch() + (showVerdict and FOOT or 4)
	holder.panel:SetHeight(bodyH)
end

function ns.Meter.Scroll(by)
	offset = math.max(0, offset + by)
	ns.Meter.Draw()
end

---------------------------------------------------------------------------
-- The verdict: where you placed, and by how much. Only once the numbers are plain.

local function Judge()
	verdict = nil
	if not Available() then return end
	local session = Fetch("current", Enum.DamageMeterType.DamageDone)
	if not session or Secret(session.totalAmount) then return end
	local sources = session.combatSources
	local mine = MyIndex(sources)
	if not mine or #sources < 2 then return end
	for _, s in ipairs(sources) do
		if Secret(s.totalAmount) or Secret(s.name) then return end
	end
	local me = sources[mine].totalAmount
	if mine == 1 then
		local second = sources[2]
		if second.totalAmount > 0 then
			verdict = ("Top damage, %d%% ahead of %s."):format((me / second.totalAmount - 1) * 100 + 0.5, ShortName(second.name, IsPlayerClass(second.classFilename)))
		else
			verdict = "Top damage."
		end
	else
		local lead = sources[1]
		if lead.totalAmount > 0 then
			verdict = ("%s of %d, %d%% behind %s."):format(ORDINAL[mine] or ("Place " .. mine), #sources,
				(1 - me / lead.totalAmount) * 100 + 0.5, ShortName(lead.name, IsPlayerClass(lead.classFilename)))
		end
	end
end

-- After a fight: wait for the secrets to drop (about half a second), then judge and redraw.
local function WaitForPlain()
	if unlockTicker then unlockTicker:Cancel() end
	local tries = 0
	unlockTicker = C_Timer.NewTicker(0.25, function(ticker)
		tries = tries + 1
		if inCombat then
			ticker:Cancel()
			unlockTicker = nil
			return
		end
		local session = Available() and Fetch("current", Enum.DamageMeterType.DamageDone)
		local plain = session and not Secret(session.totalAmount)
		if plain or tries >= 40 then
			ticker:Cancel()
			unlockTicker = nil
			if plain then
				pcall(Judge)
				-- Save the fight, then let the records, streaks and rival have their say.
				if ns.MeterHistory then
					local ok, record, outcome = pcall(ns.MeterHistory.Record)
					if ok and record and ns.MeterGlory then
						local ok2, extra = pcall(ns.MeterGlory.FightEnded, record, outcome)
						if ok2 and extra and extra ~= "" then verdict = (verdict and (verdict .. " ") or "") .. extra end
						if not ok2 and ns.Log then ns.Log("meter glory: %s", tostring(extra)) end
					elseif not ok and ns.Log then
						ns.Log("meter history: %s", tostring(record))
					end
				end
			end
			ns.Meter.Draw()
		end
	end)
end

---------------------------------------------------------------------------
-- Menus

local function Menu(owner, build)
	if MenuUtil and MenuUtil.CreateContextMenu then
		MenuUtil.CreateContextMenu(owner, build)
		return true
	end
end

function ns.Meter.SetView(key)
	if not viewByKey[key] then return end
	Opt().view = key
	offset = 0
	ns.Meter.Draw()
end

function ns.Meter.SetSegment(seg)
	segment = seg
	offset = 0
	detail = nil
	ns.Meter.Draw()
end

function ns.Meter.ViewMenu(owner)
	local shown = Menu(owner, function(_, root)
		root:CreateTitle("Show")
		for _, v in ipairs(VIEWS) do
			root:CreateRadio(v.label, function() return Opt().view == v.key end, function() ns.Meter.SetView(v.key) end)
		end
		root:CreateDivider()
		root:CreateButton("Open analysis", function() ns.MeterAnalysis.Open(segment) end)
	end)
	if not shown then
		-- No menu on this client: step to the next view.
		local at = 1
		for i, v in ipairs(VIEWS) do if v.key == Opt().view then at = i end end
		ns.Meter.SetView(VIEWS[at % #VIEWS + 1].key)
	end
end

function ns.Meter.SegmentMenu(owner)
	local shown = Menu(owner, function(_, root)
		root:CreateTitle("Fight")
		root:CreateRadio("Current fight", function() return segment == "current" end, function() ns.Meter.SetSegment("current") end)
		root:CreateRadio("Overall", function() return segment == "overall" end, function() ns.Meter.SetSegment("overall") end)
		local list = Sessions()
		for i = #list, math.max(1, #list - 11), -1 do
			local s = list[i]
			if not Secret(s.sessionID) then
				local name = (not Secret(s.name) and s.name ~= "" and s.name) or ("Fight " .. s.sessionID)
				local length = Clock(s.durationSeconds)
				local id = s.sessionID
				root:CreateRadio(length ~= "" and (name .. "  " .. length) or name, function() return segment == id end, function() ns.Meter.SetSegment(id) end)
			end
		end
		root:CreateDivider()
		root:CreateButton("Open analysis", function() ns.MeterAnalysis.Open(segment) end)
		root:CreateButton("Clear all fights", function() ns.Meter.Reset() end)
	end)
	if not shown then
		ns.Meter.SetSegment(segment == "current" and "overall" or "current")
	end
end

-- quiet: no line in chat (the automatic clear when your group changes).
local function Clear(quiet)
	local ok = pcall(API().ResetAllCombatSessions)
	verdict, detail = nil, nil
	segment = "current"
	offset = 0
	ns.Meter.Draw()
	if not quiet then
		ns.Print(ok and "damage meter cleared." or "the game refused to clear the damage meter.")
	end
	return ok
end

function ns.Meter.Reset()
	if not ns.Meter.Supported() then return end
	Clear(false)
end

-- Anything left over from before: the overall session has a player in it.
local function HasFights()
	local session = Fetch("overall", TypeValue(VIEWS[1]))
	return session ~= nil and #session.combatSources > 0
end

-- Clearing when your group changes. Joining or leaving a group leaves the last fight (and its
-- verdict) on show with players no longer with you, so Opt().groupReset clears it:
-- never | ask | always. Never in combat: the clear waits for the fight to end.
StaticPopupDialogs.SANCTUARYUI_METER_GROUP_RESET = {
	text = "Your group changed. Clear the damage meter?\n\nSaved fights and records stay.",
	button1 = "Clear",
	button2 = "Keep",
	OnAccept = function() Clear(false) end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

local grouped -- in a group when last looked; nil until the first look after login
local groupResetPending = false

local function Ask()
	StaticPopup_Show("SANCTUARYUI_METER_GROUP_RESET")
end

local function GroupReset()
	groupResetPending = false
	if not ns.Meter.Supported() or not HasFights() then return end
	local mode = Opt().groupReset
	if mode == "ask" then
		Ask()
	elseif mode == "always" then
		Clear(true)
		-- If the game would not clear it unasked, ask: the button press lets it through.
		C_Timer.After(1, function()
			if HasFights() then Ask() end
		end)
	end
end

local function GroupChanged()
	local now = (IsInGroup and IsInGroup()) and true or false
	local was = grouped
	grouped = now
	if was == nil or was == now then return end
	if (Opt().groupReset or "never") == "never" then return end
	if inCombat then
		groupResetPending = true
	else
		GroupReset()
	end
end

---------------------------------------------------------------------------
-- Layout and styles

local function Wanted()
	local opt = Opt()
	if not opt.enabled then return false end
	if Previewing() then return true end
	if not Available() then return false end
	if opt.show == "combat" then return inCombat end
	if opt.show == "group" then return (IsInGroup and IsInGroup()) and true or false end
	return true
end

function ns.Meter.UpdateShown()
	if not holder then return end
	local want = Wanted()
	if want ~= holder:IsShown() then
		holder:SetShown(want)
		if want then ns.Meter.Draw() end
	end
end

-- The red glass strip: slices of the bag window's banner, every other one mirrored.
local function LayGlass(host, list, width)
	local TILE = 180
	local n = math.ceil(width / TILE)
	local path = ns.Art.Path("bagFrame")
	for i = 1, math.max(n, #list) do
		local t = list[i]
		if i > n then
			t:Hide()
		else
			if not t then
				t = host:CreateTexture(nil, "ARTWORK")
				list[i] = t
			end
			local w = math.min(TILE, width - (i - 1) * TILE)
			t:ClearAllPoints()
			t:SetPoint("TOPLEFT", host, "TOPLEFT", 4 + (i - 1) * TILE, -4)
			t:SetSize(w, 44)
			if path then
				t:SetTexture(path)
				local x0, x1 = 50, 50 + w
				if i % 2 == 0 then x0, x1 = 230, 230 - w end
				t:SetTexCoord(x0 / 1024, x1 / 1024, 52 / 1024, 96 / 1024)
			else
				t:SetColorTexture(0.35, 0.05, 0.03, 1)
			end
			t:Show()
		end
	end
end

function ns.Meter.Layout()
	if not holder then return end
	local opt = Opt()
	local style = ns.Meter.STYLES[opt.style] and opt.style or "glass"
	local width = math.max(360, opt.width)
	local w, h = STUD + width, Head() + opt.rows * Pitch() + FOOT
	holder.title:SetFont(TitleFont(), 28, "")
	holder.clock:SetFont(TitleFont(), 28, "")
	for _, fs in ipairs({ holder.sub, holder.empty, holder.verdict }) do fs:SetFont(BodyFont(), 21, "") end
	for _, label in pairs(holder.labels) do label:SetFont(BodyFont(), 17, "") end
	for _, row in ipairs(rows) do SizeRow(row) end
	holder:SetScale(ns.Art.D3Scale(opt.scale))
	holder:SetSize(w * HALF, h * HALF)
	canvas:SetSize(w, h)
	holder:ClearAllPoints()
	if opt.moved then
		holder:SetPoint("CENTER", UIParent, "BOTTOMLEFT", ns.MovedPoint(holder, opt))
	else
		-- Right edge, above the middle of the screen's lower half: clear of the console.
		holder:SetPoint("RIGHT", UIParent, "RIGHT", -60, -180)
	end

	local glass = style ~= "plaque"
	holder.head:ClearAllPoints()
	holder.head:SetPoint("TOPLEFT", canvas, "TOPLEFT", STUD, -6)
	holder.head:SetSize(width, 52)
	holder.headEdge:SetShown(glass)
	holder.headLine:SetShown(glass)
	if glass then
		LayGlass(holder.head, holder.glass, width - 8)
	else
		for _, t in ipairs(holder.glass) do t:Hide() end
	end
	for _, t in ipairs(holder.plaque) do t:SetShown(not glass) end

	local panel = style == "shadow"
	holder.panel:SetShown(panel)
	holder.panel:SetAlpha(opt.panelAlpha)

	ns.Meter.UpdateShown()
	ns.Meter.Draw()
end

local function Build()
	holder = CreateFrame("Frame", "SanctuaryUIMeter", UIParent)
	holder:SetFrameStrata("LOW")
	holder:Hide()
	holder.glass, holder.plaque = {}, {}
	canvas = CreateFrame("Frame", nil, holder)
	canvas:SetScale(HALF)
	canvas:SetPoint("TOPLEFT")

	-- Glass and shadow: the bag window's dark body behind everything.
	local panel = CreateFrame("Frame", nil, canvas)
	panel:SetPoint("TOPLEFT", canvas, "TOPLEFT", STUD - 8, 0)
	panel:SetPoint("RIGHT", canvas, "RIGHT", 8, 0)
	panel:SetHeight(100)
	panel:SetFrameLevel(canvas:GetFrameLevel())
	local edge = panel:CreateTexture(nil, "BACKGROUND", nil, -8)
	edge:SetAllPoints()
	edge:SetColorTexture(0.03, 0.027, 0.023, 1)
	local line = panel:CreateTexture(nil, "BACKGROUND", nil, -7)
	line:SetPoint("TOPLEFT", 3, -3)
	line:SetPoint("BOTTOMRIGHT", -3, 3)
	line:SetColorTexture(0.29, 0.24, 0.16, 1)
	local body = panel:CreateTexture(nil, "BACKGROUND", nil, -6)
	body:SetPoint("TOPLEFT", 4, -4)
	body:SetPoint("BOTTOMRIGHT", -4, 4)
	local bag = ns.Art.Path("bagFrame")
	if bag then
		body:SetTexture(bag)
		Coords(body, 14, 170, 560, 270, 1024)
	else
		body:SetColorTexture(0.05, 0.05, 0.05, 1)
	end
	holder.panel = panel

	-- The title strip. Left click: what to show. Right click: which fight.
	local head = CreateFrame("Button", nil, canvas)
	head:SetFrameLevel(canvas:GetFrameLevel() + 2)
	head:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	holder.head = head
	holder.headEdge = head:CreateTexture(nil, "BACKGROUND")
	holder.headEdge:SetAllPoints()
	holder.headEdge:SetColorTexture(0.04, 0.03, 0.024, 1)
	holder.headLine = head:CreateTexture(nil, "BORDER")
	holder.headLine:SetPoint("TOPLEFT", 3, -3)
	holder.headLine:SetPoint("BOTTOMRIGHT", -3, 3)
	holder.headLine:SetColorTexture(0.59, 0.44, 0.19, 1)
	local button = ns.Art.Path("d3Button")
	for i, cut in ipairs({ { 0, 24 }, { 24, 72 }, { 96, 24 } }) do
		local t = head:CreateTexture(nil, "ARTWORK")
		if button then
			t:SetTexture(button)
			t:SetTexCoord(cut[1] / 128, (cut[1] + cut[2]) / 128, 0, 52 / 64)
		else
			t:SetColorTexture(0.3, 0.05, 0.03, 1)
		end
		holder.plaque[i] = t
	end
	holder.plaque[1]:SetPoint("TOPLEFT")
	holder.plaque[1]:SetPoint("BOTTOMLEFT")
	holder.plaque[1]:SetWidth(24)
	holder.plaque[3]:SetPoint("TOPRIGHT")
	holder.plaque[3]:SetPoint("BOTTOMRIGHT")
	holder.plaque[3]:SetWidth(24)
	holder.plaque[2]:SetPoint("TOPLEFT", holder.plaque[1], "TOPRIGHT")
	holder.plaque[2]:SetPoint("BOTTOMRIGHT", holder.plaque[3], "BOTTOMLEFT")

	local over = CreateFrame("Frame", nil, head)
	over:SetAllPoints()
	over:SetFrameLevel(head:GetFrameLevel() + 1)
	holder.title = Text(over, TitleFont(), 28, GOLD)
	holder.title:SetPoint("LEFT", head, "LEFT", 18, -1)
	holder.clock = Text(over, TitleFont(), 28, GOLD, "RIGHT")
	-- The analysis window's button, at the strip's right end; the clock sits left of it.
	local open = CreateFrame("Button", nil, over)
	open:SetSize(34, 34)
	open:SetPoint("RIGHT", head, "RIGHT", -12, 0)
	open.icon = open:CreateTexture(nil, "ARTWORK")
	open.icon:SetAllPoints()
	open.icon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
	open.icon:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
	open:SetScript("OnEnter", function(self)
		self.icon:SetVertexColor(1, 1, 1)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Analysis")
		GameTooltip:AddLine("Every fight, everyone in it, and each player's abilities. Out of combat only.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	open:SetScript("OnLeave", function(self)
		self.icon:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
		GameTooltip_Hide()
	end)
	open:SetScript("OnClick", function()
		if ns.MeterAnalysis.Toggle and ns.MeterAnalysis.IsOpen and ns.MeterAnalysis.IsOpen() then
			ns.MeterAnalysis.Toggle()
		else
			ns.MeterAnalysis.Open(segment)
		end
	end)
	holder.open = open
	-- The meter's page in the options, left of the analysis button.
	local gear = CreateFrame("Button", nil, over)
	gear:SetSize(30, 30)
	gear:SetPoint("RIGHT", open, "LEFT", -6, 0)
	gear.icon = gear:CreateTexture(nil, "ARTWORK")
	gear.icon:SetAllPoints()
	gear.icon:SetTexture("Interface\\WorldMap\\Gear_64Grey")
	gear.icon:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
	gear:SetScript("OnEnter", function(self)
		self.icon:SetVertexColor(1, 1, 1)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Damage meter options")
		GameTooltip:Show()
	end)
	gear:SetScript("OnLeave", function(self)
		self.icon:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
		GameTooltip_Hide()
	end)
	gear:SetScript("OnClick", function() ns.Options.Open("meter") end)
	holder.gear = gear
	holder.clock:SetPoint("RIGHT", gear, "LEFT", -10, -1)
	holder.sub = Text(over, BodyFont(), 21, CREAM)
	holder.sub:SetPoint("LEFT", holder.title, "RIGHT", 24, -1)
	holder.sub:SetPoint("RIGHT", holder.clock, "LEFT", -12, 0)

	head:SetScript("OnClick", function(self, mouse)
		if IsShiftKeyDown and IsShiftKeyDown() then
			ns.MeterAnalysis.Open(segment)
		elseif detail then
			CloseDetail()
		elseif mouse == "RightButton" then
			ns.Meter.SegmentMenu(self)
		else
			ns.Meter.ViewMenu(self)
		end
	end)
	head:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Damage meter")
		if detail then
			GameTooltip:AddLine("Click to go back to the list.", 1, 1, 1)
		else
			GameTooltip:AddLine("Left click: what to show.", 1, 1, 1)
			GameTooltip:AddLine("Right click: which fight.", 1, 1, 1)
			GameTooltip:AddLine("Click a player after a fight for their abilities.", 1, 1, 1)
			GameTooltip:AddLine("Shift-click here for the full analysis.", 1, 1, 1)
		end
		GameTooltip:Show()
	end)
	head:SetScript("OnLeave", GameTooltip_Hide)

	holder.empty = Text(canvas, BodyFont(), 21, CREAM)
	holder.labels = {}
	for key, word in pairs({ rate = "per sec", total = "total", pct = "share" }) do
		local label = Text(canvas, BodyFont(), 17, GOLD, "RIGHT")
		label:SetText(word)
		label:SetAlpha(0.85)
		label:Hide()
		holder.labels[key] = label
	end
	holder.empty:SetText("Nothing recorded yet.")
	holder.empty:SetAlpha(0.7)
	holder.verdict = Text(canvas, BodyFont(), 21, CREAM)

	holder:SetScript("OnUpdate", function(_, elapsed)
		sinceDraw = sinceDraw + elapsed
		sinceClock = sinceClock + elapsed
		if dirty and sinceDraw >= INTERVAL then
			ns.Meter.Draw()
		elseif sinceClock >= 0.5 then
			sinceClock = 0
			DrawClock()
		end
	end)
end

-- A gold flash across your own rail (taking the lead).
function ns.Meter.FlashMine()
	for _, row in ipairs(rows) do
		if row:IsShown() and row.isMine then
			if not row.flash then
				row.flash = row.bar:CreateTexture(nil, "OVERLAY")
				row.flash:SetAllPoints(row)
				row.flash:SetColorTexture(1, 0.82, 0.4, 1)
				row.flash:SetBlendMode("ADD")
				row.flash:SetAlpha(0)
				row.flashAnim = row.flash:CreateAnimationGroup()
				local a = row.flashAnim:CreateAnimation("Alpha")
				a:SetFromAlpha(0.7)
				a:SetToAlpha(0)
				a:SetDuration(0.9)
			end
			row.flashAnim:Stop()
			row.flashAnim:Play()
		end
	end
end

function ns.Meter.Redraw()
	dirty = true
end

-- For MeterGlory.lua, whose lines sit against the meter.
function ns.Meter.Holder()
	return holder
end

-- A gold pulse on the title strip.
function ns.Meter.FlashHead()
	if not holder or not holder:IsShown() then return end
	local head = holder.head
	if not head.flash then
		head.flash = head:CreateTexture(nil, "OVERLAY")
		head.flash:SetAllPoints()
		head.flash:SetColorTexture(1, 0.82, 0.4, 1)
		head.flash:SetBlendMode("ADD")
		head.flash:SetAlpha(0)
		head.flashAnim = head.flash:CreateAnimationGroup()
		local a = head.flashAnim:CreateAnimation("Alpha")
		a:SetFromAlpha(0.55)
		a:SetToAlpha(0)
		a:SetDuration(1.2)
	end
	head.flashAnim:Stop()
	head.flashAnim:Play()
end

-- For MeterAnalysis.lua: the same data, text and art helpers.
ns.Meter.Lib = {
	Fetch = Fetch, FetchSource = FetchSource, Sessions = Sessions, Duration = Duration, Short = Short, Clock = Clock,
	ShortName = ShortName, ClassColor = ClassColor, IsPlayerClass = IsPlayerClass, Text = Text, Coords = Coords,
	BodyFont = BodyFont, TitleFont = TitleFont, LayGlass = LayGlass, Available = Available, MyIndex = MyIndex,
	GetSpellName = function(id) return GetSpellName(id) end,
	GetSpellTexture = function(id) return GetSpellTexture and GetSpellTexture(id) end,
	GOLD = GOLD, CREAM = CREAM,
}

function ns.Meter.UpdateMovers(unlocked)
	if not holder then return end
	local show = unlocked and Opt().enabled and true or false
	holder.unlocked = show
	ns.Meter.mover:SetShown(show)
	ns.Meter.UpdateShown()
	ns.Meter.Draw()
end

function ns.Meter.ResetPosition()
	local opt = Opt()
	opt.moved, opt.mx, opt.my = false, 0, 0
	ns.Refresh()
end

-- Session-only: the mockup's fight on the rails, to judge a style without a fight.
function ns.Meter.SetPreview(on)
	ns.Meter.preview = on and true or nil
	detail = nil
	ns.Meter.UpdateShown()
	ns.Meter.Draw()
end

function ns.Meter.ApplySettings()
	if not holder then return end
	ns.Meter.Layout()
end

function ns.Meter.Init()
	Build()
	ns.Meter.mover = ns.MakeMover(holder, "Damage meter", Opt, "Reset its position in /sanctuary > Damage meter.")
	local saved = Opt().segment
	segment = saved == "overall" and "overall" or "current"

	local events = CreateFrame("Frame")
	for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE",
		"DAMAGE_METER_COMBAT_SESSION_UPDATED", "DAMAGE_METER_CURRENT_SESSION_UPDATED", "DAMAGE_METER_RESET" }) do
		pcall(events.RegisterEvent, events, event)
	end
	events:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_REGEN_DISABLED" then
			inCombat = true
			verdict = nil
			detail = nil
			offset = 0
			if unlockTicker then unlockTicker:Cancel() unlockTicker = nil end
			-- A past fight on show gives way to the one starting.
			if type(segment) == "number" then segment = "current" end
			ns.Meter.UpdateShown()
			dirty = true
		elseif event == "PLAYER_REGEN_ENABLED" then
			inCombat = false
			ns.Meter.UpdateShown()
			dirty = true
			WaitForPlain()
			if groupResetPending then GroupReset() end
		elseif event == "PLAYER_ENTERING_WORLD" then
			local affecting = UnitAffectingCombat and UnitAffectingCombat("player")
			inCombat = not Secret(affecting) and affecting and true or false
			ns.Meter.UpdateShown()
			dirty = true
			GroupChanged()
		elseif event == "GROUP_ROSTER_UPDATE" then
			ns.Meter.UpdateShown()
			GroupChanged()
		else
			if event == "DAMAGE_METER_RESET" then
				verdict, detail = nil, nil
				if type(segment) == "number" then segment = "current" end
			end
			dirty = true
		end
	end)
	ns.Meter.Layout()
end
