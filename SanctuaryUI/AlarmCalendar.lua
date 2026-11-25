SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.AlarmCalendar = ns.AlarmCalendar or {}
local C = ns.AlarmCalendar
local A = ns.Alarm

-- The alarm clock on the game's calendar (Blizzard_Calendar, the retail one in Forever): each
-- day square lists that day's Outlook meetings and alarms as small rows above Blizzard's own
-- events, the day's tooltip lists them too, and clicking one (or the + on a day) opens a panel
-- beside the calendar to silence or remove them, or set an alarm on that day.
--
-- Nothing is written to the game's calendar itself: its events live on Blizzard's servers, and
-- meeting titles stay on this PC. Only Blizzard functions are hooked (hooksecurefunc) and its
-- fields read; the rows, the + and the panel are SanctuaryUI's own frames.

local ROW_H, ROW_GAP = 11, 1
local DAY_W, DAY_H = 91, 91
local DATE_BOTTOM = 24 -- the date label's frame ends this far below the day's top
local BLIZZ_X, BLIZZ_Y, BLIZZ_GAP = 4, 3, 3 -- where Blizzard's event rows sit
local BLIZZ_SMALL, BLIZZ_BIG, BLIZZ_MAX = 12, 24, 4
local BIG_H = 22 -- a big row: title over time
local TICKS = 7 -- bars by the date on a day too full for rows
local TIP_LABEL = 52 -- longer meeting titles are cut in the tooltip
local PANEL_W, HEADER, PAD, ITEM_H = 300, 30, 12, 38

local MEETING = { 0.55, 0.78, 1.0 }
local ALARM = { 1.0, 0.64, 0.28 }
local SILENT = { 0.55, 0.52, 0.48 }
local GREY = { 0.6, 0.56, 0.5 }

local hooked, marks, cache = false, {}, {}
local plus, plusDay, panel, panelDate

local DAYS = 42 -- six weeks of day squares

local function Opt() return ns.DB().alarm end

-- Blizzard keeps its list of day squares local; each is also a global by name.
local function DayButton(index) return _G["CalendarDayButton" .. index] end
local function Enabled()
	local opt = Opt()
	return opt.enabled and opt.calendar ~= false
end

local function TitleFont() return ns.Fonts.Path("title") end
local function BodyFont() return ns.Fonts.Path("body") end

local function Now() return time() end

-- The calendar's small font, so our rows read like Blizzard's.
local function SmallText(parent, color, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	if fs.SetFontObject and GameFontNormalSmall then
		fs:SetFontObject(GameFontNormalSmall)
	else
		fs:SetFont(BodyFont(), 10, "")
	end
	fs:SetTextColor(color[1], color[2], color[3])
	fs:SetJustifyH(justify or "LEFT")
	fs:SetWordWrap(false)
	return fs
end

local function Clock(at)
	local t = date("*t", at)
	return A.FormatTime(t.hour, t.min)
end

local function Today()
	return A.DayKey(date("*t", Now()))
end

local function Key(year, month, day)
	return ("%04d-%02d-%02d"):format(year, month, day)
end

-- The year, month and day a day square shows (its month is relative to the one viewed).
local function DateOf(dayButton)
	if not dayButton or not dayButton.day then return nil end
	local ok, info = pcall(C_Calendar.GetMonthInfo, dayButton.monthOffset or 0)
	if not ok or type(info) ~= "table" then return nil end
	return info.year, info.month, dayButton.day
end

---------------------------------------------------------------------------
-- The rows on a day

local function ItemColor(item)
	if not item.rings then return SILENT end
	return item.kind == "meeting" and MEETING or ALARM
end

-- One of ours on a day: a small row (title, time on the right) like Blizzard's when several
-- share the day, or a big one (title, time below) when there are one or two, as Blizzard does.
local function Row(holder, dayButton)
	local r = CreateFrame("Button", nil, holder)
	r.stripe = r:CreateTexture(nil, "ARTWORK")
	r.stripe:SetPoint("TOPLEFT", 0, -1)
	r.stripe:SetPoint("BOTTOMLEFT", 0, 1)
	r.stripe:SetWidth(2)
	r.time = SmallText(r, { 1, 1, 1 }, "RIGHT")
	r.title = SmallText(r, MEETING)
	local hl = r:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 0.85, 0.5, 0.12)
	r:SetScript("OnEnter", function() if CalendarDayButton_OnEnter then CalendarDayButton_OnEnter(dayButton) end end)
	r:SetScript("OnLeave", function() GameTooltip:Hide() end)
	r:SetScript("OnClick", function(self) C.Open(dayButton, self.item) end)
	return r
end

local ROW_W = DAY_W - 2 * BLIZZ_X

local function FillRow(r, item, big, text, color)
	r:SetSize(ROW_W, big and BIG_H or ROW_H)
	r.item = item
	r.stripe:SetColorTexture(color[1], color[2], color[3], 0.9)
	r.title:SetTextColor(color[1], color[2], color[3])
	r.title:SetText(text)
	r.time:SetText(item and text == item.label and Clock(item.at) or "")
	r.title:ClearAllPoints()
	r.time:ClearAllPoints()
	if big then
		r.title:SetPoint("TOPLEFT", r, "TOPLEFT", 4, 0)
		r.title:SetWidth(ROW_W - 4)
		r.time:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 4, 0)
		r.time:SetJustifyH("LEFT")
	else
		r.time:SetPoint("RIGHT", r, "RIGHT", 0, 0)
		r.time:SetJustifyH("RIGHT")
		r.title:SetPoint("LEFT", r, "LEFT", 4, 0)
		r.title:SetWidth(math.max(10, ROW_W - 4 - (r.time:GetText() ~= "" and r.time:GetStringWidth() + 3 or 0)))
	end
end

local function Marks(index, dayButton)
	local m = marks[index]
	if m then return m end
	m = CreateFrame("Frame", nil, dayButton)
	m:SetAllPoints(dayButton)
	m.rows = {}
	-- the calendar's own shade behind event rows, for days with only ours
	m.shade = m:CreateTexture(nil, "ARTWORK")
	m.shade:SetTexture("Interface\\Calendar\\CalendarEventBackground")
	m.shade:SetPoint("BOTTOM", dayButton, "BOTTOM")
	m.shade:SetWidth(DAY_W)
	-- A day too full for rows: a little bar per item by the date, in the rows' colours.
	m.ticks = CreateFrame("Button", nil, m)
	m.ticks:SetPoint("TOPLEFT", dayButton, "TOPLEFT", 29, -8)
	m.ticks:SetHeight(12)
	m.ticks.bars = {}
	for i = 1, TICKS do
		local t = m.ticks:CreateTexture(nil, "ARTWORK")
		t:SetSize(3, 10)
		t:SetPoint("LEFT", m.ticks, "LEFT", (i - 1) * 5, 0)
		m.ticks.bars[i] = t
	end
	m.ticks.more = SmallText(m.ticks, GREY)
	m.ticks:SetScript("OnEnter", function() if CalendarDayButton_OnEnter then CalendarDayButton_OnEnter(dayButton) end end)
	m.ticks:SetScript("OnLeave", function() GameTooltip:Hide() end)
	m.ticks:SetScript("OnClick", function() C.Open(dayButton) end)
	marks[index] = m
	return m
end

-- How tall Blizzard's own event rows stand on this day.
local function BlizzardHeight(dayButton)
	local n = tonumber(dayButton.numViewableEvents) or 0
	if n <= 0 then return 0 end
	local h = n <= 2 and BLIZZ_BIG or BLIZZ_SMALL
	n = math.min(n, BLIZZ_MAX)
	return BLIZZ_Y + n * h + (n - 1) * BLIZZ_GAP
end

local function DrawTicks(m, items, dark)
	local n = #items
	local bars = n > TICKS and TICKS - 1 or n
	for i, t in ipairs(m.ticks.bars) do
		if i <= bars then
			local c = ItemColor(items[i])
			t:SetColorTexture(c[1], c[2], c[3], 1)
			t:Show()
		else
			t:Hide()
		end
	end
	m.ticks.more:ClearAllPoints()
	m.ticks.more:SetPoint("LEFT", m.ticks, "LEFT", bars * 5 + 1, 0)
	m.ticks.more:SetText(n > bars and ("+" .. (n - bars)) or "")
	m.ticks:SetWidth(bars * 5 + (n > bars and 14 or 0))
	m.ticks:SetAlpha(dark and 0.6 or 1)
	m.ticks:Show()
end

local function DrawDay(index, day, monthOffset)
	local dayButton = DayButton(index)
	if not dayButton then return end
	local items = {}
	if Enabled() then
		local ok, info = pcall(C_Calendar.GetMonthInfo, monthOffset or 0)
		if ok and type(info) == "table" and day then
			items = A.DayItems(info.year, info.month, day)
		end
	end
	cache[index] = items
	local m = marks[index]
	if #items == 0 and not m then return end
	m = Marks(index, dayButton)
	for _, r in ipairs(m.rows) do r:Hide() end
	m.ticks:Hide()
	m.shade:Hide()
	if #items == 0 then return end

	local used = BlizzardHeight(dayButton)
	local bottom = used > 0 and used + BLIZZ_GAP or BLIZZ_Y
	local room = DAY_H - DATE_BOTTOM - bottom + ROW_GAP -- what's free above Blizzard's rows
	local n = #items
	local big = n <= 2 and n * (BIG_H + ROW_GAP) <= room
	local fit = math.floor(room / (ROW_H + ROW_GAP))
	if not big and n > fit and fit < 2 then
		DrawTicks(m, items, dayButton.dark)
		return
	end
	local shown = (big or n <= fit) and n or fit - 1
	local total = shown + (shown < n and 1 or 0)
	local step = (big and BIG_H or ROW_H) + ROW_GAP
	-- Soonest at the top, as the calendar stacks its own; ours stand above Blizzard's.
	for i = 1, total do
		local r = m.rows[i] or Row(m, dayButton)
		m.rows[i] = r
		if i <= shown then
			FillRow(r, items[i], big, items[i].label, ItemColor(items[i]))
		else
			FillRow(r, items[i], false, ("+%d more"):format(n - shown), GREY)
		end
		r:ClearAllPoints()
		r:SetPoint("BOTTOMLEFT", dayButton, "BOTTOMLEFT", BLIZZ_X, bottom + (total - i) * step)
		r:SetAlpha(dayButton.dark and 0.6 or 1)
		r:Show()
	end
	if used == 0 then
		m.shade:SetHeight(math.min(bottom + total * step + 40, DAY_H - 5))
		m.shade:Show()
	end
end

function C.Refresh()
	if not hooked then return end
	for i = 1, DAYS do
		local b = DayButton(i)
		if b and b.day then DrawDay(i, b.day, b.monthOffset) end
	end
	if panel and panel:IsShown() then C.Fill() end
end

---------------------------------------------------------------------------
-- The tooltip and the + on a day

local function Tooltip(dayButton)
	if not Enabled() then return end
	local items = cache[dayButton:GetID()]
	if not items or #items == 0 then return end
	local tip = GameTooltip
	if not (tip:IsShown() and tip:GetOwner() == dayButton) then
		tip:SetOwner(dayButton, "ANCHOR_RIGHT")
		tip:ClearLines()
		local y, mo, d = DateOf(dayButton)
		if y then
			tip:AddLine(date("%A, %B %d", time({ year = y, month = mo, day = d, hour = 12 })):gsub(" 0", " "), 1, 1, 1)
		end
	end
	local y, mo, d = DateOf(dayButton)
	for _, item in ipairs(items) do
		tip:AddLine(" ")
		local c = ItemColor(item)
		local when = Clock(item.at)
		if item.kind == "meeting" and item.finish and item.finish > item.at then when = when .. " - " .. Clock(item.finish) end
		local label = item.label
		if #label > TIP_LABEL then label = label:sub(1, TIP_LABEL - 3) .. "..." end
		tip:AddDoubleLine(label, when, c[1], c[2], c[3], 1, 1, 1)
		local note = item.kind == "meeting" and item.location or ""
		if item.kind == "alarm" then note = item.alarm.rep == "once" and "Alarm" or ((A.REPEATS[item.alarm.rep] or "") .. " alarm") end
		if not item.rings then note = (note ~= "" and note .. ", " or "") .. (item.kind == "meeting" and "won't ring" or "off") end
		if note ~= "" then tip:AddLine(note, GREY[1], GREY[2], GREY[3]) end
	end
	tip:AddLine(" ")
	local future = y and Key(y, mo, d) >= Today()
	tip:AddLine(future and "Click one to manage it; the + sets an alarm." or "Click one to manage it.", 0.5, 0.5, 0.5)
	tip:Show()
end

local function ShowPlus(dayButton)
	if not Enabled() or not plus then return end
	local y, mo, d = DateOf(dayButton)
	if not y or Key(y, mo, d) < Today() then plus:Hide() return end
	plusDay = dayButton
	plus:SetParent(dayButton)
	plus:ClearAllPoints()
	local more = _G[dayButton:GetName() .. "MoreEventsButton"]
	plus:SetPoint("TOPRIGHT", dayButton, "TOPRIGHT", (more and more:IsShown()) and -21 or -5, -5)
	plus:SetFrameLevel(dayButton:GetFrameLevel() + 5)
	plus:Show()
end

local function BuildPlus()
	plus = CreateFrame("Button", nil, CalendarFrame)
	plus:SetSize(14, 14)
	plus:Hide()
	local back = plus:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(0.42, 0.33, 0.18, 1)
	local fill = plus:CreateTexture(nil, "BORDER")
	fill:SetPoint("TOPLEFT", 1, -1)
	fill:SetPoint("BOTTOMRIGHT", -1, 1)
	fill:SetColorTexture(0.06, 0.05, 0.04, 0.95)
	plus.label = A.Text(plus, TitleFont(), 12, A.GOLD, "CENTER")
	plus.label:SetPoint("CENTER", 0, 0)
	plus.label:SetText("+")
	plus:SetScript("OnEnter", function(self)
		self.label:SetTextColor(1, 1, 1)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Set an alarm on this day", 1, 1, 1)
		GameTooltip:Show()
	end)
	plus:SetScript("OnLeave", function(self)
		self.label:SetTextColor(A.GOLD[1], A.GOLD[2], A.GOLD[3])
		GameTooltip:Hide()
	end)
	plus:SetScript("OnClick", function() if plusDay then C.Open(plusDay, nil, true) end end)
	-- gone once the mouse leaves its day
	plus:SetScript("OnUpdate", function(self)
		if not (plusDay and (plusDay:IsMouseOver() or self:IsMouseOver())) then self:Hide() end
	end)
end

---------------------------------------------------------------------------
-- The day panel, beside the calendar (or beside Blizzard's event window when that's open)

local function Box(parent, w)
	local b = CreateFrame("EditBox", nil, parent)
	b:SetSize(w, 20)
	b:SetAutoFocus(false)
	b:SetFont(BodyFont(), 11, "")
	b:SetTextColor(A.CREAM[1], A.CREAM[2], A.CREAM[3])
	b:SetTextInsets(6, 6, 0, 0)
	local edge = b:CreateTexture(nil, "BACKGROUND", nil, -2)
	edge:SetAllPoints()
	edge:SetColorTexture(0.42, 0.33, 0.18, 1)
	local fill = b:CreateTexture(nil, "BACKGROUND", nil, -1)
	fill:SetPoint("TOPLEFT", 1, -1)
	fill:SetPoint("BOTTOMRIGHT", -1, 1)
	fill:SetColorTexture(0.03, 0.027, 0.023, 1)
	b.hint = A.Text(b, BodyFont(), 10, GREY)
	b.hint:SetPoint("LEFT", b, "LEFT", 6, 0)
	b:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	b:SetScript("OnTextChanged", function(self) self.hint:SetShown(self:GetText() == "") end)
	b:SetScript("OnEditFocusGained", function(self) self.hint:Hide() end)
	b:SetScript("OnEditFocusLost", function(self) self.hint:SetShown(self:GetText() == "") end)
	return b
end

local function Place()
	panel:ClearAllPoints()
	local ev = CalendarFrame.eventFrame
	if ev and ev:IsShown() then
		panel:SetPoint("TOPLEFT", ev, "TOPRIGHT", 4, 0)
	else
		panel:SetPoint("TOPLEFT", CalendarFrame, "TOPRIGHT", 0, -24)
	end
end

local function BuildPanel()
	panel = CreateFrame("Frame", "SanctuaryUIAlarmDay", CalendarFrame)
	panel:SetToplevel(true)
	panel:SetClampedToScreen(true)
	panel:EnableMouse(true)
	panel:SetSize(PANEL_W, 200)
	panel:Hide()

	local edge = panel:CreateTexture(nil, "BACKGROUND", nil, -8)
	edge:SetAllPoints()
	edge:SetColorTexture(0.03, 0.027, 0.023, 0.97)
	local line = panel:CreateTexture(nil, "BACKGROUND", nil, -7)
	line:SetPoint("TOPLEFT", 2, -2)
	line:SetPoint("BOTTOMRIGHT", -2, 2)
	line:SetColorTexture(0.42, 0.33, 0.18, 1)
	local body = panel:CreateTexture(nil, "BACKGROUND", nil, -6)
	body:SetPoint("TOPLEFT", 3, -3)
	body:SetPoint("BOTTOMRIGHT", -3, 3)
	local bag = ns.Art.Path("bagFrame")
	if bag then
		body:SetTexture(bag)
		body:SetTexCoord(14 / 1024, 574 / 1024, 170 / 1024, 440 / 1024)
	else
		body:SetColorTexture(0.06, 0.055, 0.05, 1)
	end

	local head = CreateFrame("Frame", nil, panel)
	head:SetPoint("TOPLEFT", panel, "TOPLEFT", 3, -3)
	head:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -3, -3)
	head:SetHeight(HEADER)
	local glassEdge = head:CreateTexture(nil, "BACKGROUND")
	glassEdge:SetAllPoints()
	glassEdge:SetColorTexture(0.04, 0.03, 0.024, 1)
	panel.glass = {}
	local L = ns.Meter and ns.Meter.Lib
	if L and L.LayGlass then L.LayGlass(head, panel.glass, PANEL_W - 14, HEADER - 8) end
	panel.title = A.Text(head, TitleFont(), 12, A.GOLD)
	panel.title:SetPoint("LEFT", head, "LEFT", 10, -1)
	local close = CreateFrame("Button", nil, head)
	close:SetSize(22, 22)
	close:SetPoint("RIGHT", head, "RIGHT", -4, -1)
	close.label = A.Text(close, TitleFont(), 14, A.GOLD, "CENTER")
	close.label:SetPoint("CENTER", 0, 0)
	close.label:SetText("x")
	close:SetScript("OnEnter", function(self) self.label:SetTextColor(1, 1, 1) end)
	close:SetScript("OnLeave", function(self) self.label:SetTextColor(A.GOLD[1], A.GOLD[2], A.GOLD[3]) end)
	close:SetScript("OnClick", function() panel:Hide() end)

	panel.items = {}
	panel.empty = A.Text(panel, BodyFont(), 10, GREY)
	panel.empty:SetText("Nothing on this day.")

	panel.rule = panel:CreateTexture(nil, "ARTWORK")
	panel.rule:SetHeight(1)
	panel.rule:SetColorTexture(0.42, 0.33, 0.18, 0.8)

	-- New alarm on this day
	panel.newHead = A.Text(panel, TitleFont(), 11, A.GOLD)
	panel.newHead:SetText("New alarm")
	panel.time = Box(panel, 76)
	panel.time.hint:SetText("9:30am")
	panel.rep = A.Plate(panel, 96, 20, A.REPEATS.once, 8)
	panel.repKey = "once"
	panel.rep:SetScript("OnClick", function(self)
		local order = A.REPEAT_ORDER
		for i, k in ipairs(order) do
			if k == panel.repKey then panel.repKey = order[i % #order + 1] break end
		end
		self.label:SetText(A.REPEATS[panel.repKey])
	end)
	panel.add = A.Plate(panel, 76, 20, "Add", 8)
	panel.label = Box(panel, PANEL_W - 2 * PAD)
	panel.label.hint:SetText("What it's for")
	panel.note = A.Text(panel, BodyFont(), 9, GREY)
	panel.note:SetWidth(PANEL_W - 2 * PAD)
	panel.note:SetWordWrap(true)
	local function Add() C.AddFromPanel() end
	panel.add:SetScript("OnClick", Add)
	panel.time:SetScript("OnEnterPressed", Add)
	panel.label:SetScript("OnEnterPressed", Add)
	panel.time:SetScript("OnTabPressed", function() panel.label:SetFocus() end)
	panel.label:SetScript("OnTabPressed", function() panel.time:SetFocus() end)

	panel:SetScript("OnHide", function()
		panel.time:ClearFocus()
		panel.label:ClearFocus()
	end)
end

local function ItemLine(i)
	local f = panel.items[i]
	if f then return f end
	f = CreateFrame("Frame", nil, panel)
	f:SetSize(PANEL_W - 2 * PAD, ITEM_H)
	f.stripe = f:CreateTexture(nil, "ARTWORK")
	f.stripe:SetPoint("TOPLEFT", 0, -2)
	f.stripe:SetPoint("BOTTOMLEFT", 0, 2)
	f.stripe:SetWidth(3)
	f.when = A.Text(f, TitleFont(), 11, A.GOLD)
	f.when:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -3)
	f.kind = A.Text(f, BodyFont(), 9, GREY)
	f.kind:SetPoint("LEFT", f.when, "RIGHT", 8, 0)
	f.label = A.Text(f, BodyFont(), 10, A.CREAM)
	f.label:SetPoint("TOPLEFT", f.when, "BOTTOMLEFT", 0, -3)
	f.label:SetWordWrap(false)
	f.toggle = A.Plate(f, 58, 18, "Rings", 8)
	f.toggle:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -2)
	f.remove = A.Plate(f, 58, 18, "Remove", 8)
	f.remove:SetPoint("TOPRIGHT", f.toggle, "BOTTOMRIGHT", 0, -1)
	f.label:SetWidth(PANEL_W - 2 * PAD - 10 - 64)
	f.toggle:SetScript("OnClick", function()
		local item = f.item
		if not item then return end
		if item.kind == "meeting" then
			A.SetMeetingRings(item.at, item.subject, not item.rings)
		else
			A.SetOn(item.alarm, not item.alarm.on)
		end
	end)
	f.remove:SetScript("OnClick", function() if f.item and f.item.alarm then A.Remove(f.item.alarm) end end)
	f.hl = f:CreateTexture(nil, "BORDER")
	f.hl:SetAllPoints()
	f.hl:SetColorTexture(1, 0.8, 0.45, 0.07)
	panel.items[i] = f
	return f
end

function C.Fill()
	if not panel or not panelDate then return end
	local y, mo, d = panelDate[1], panelDate[2], panelDate[3]
	local noon = time({ year = y, month = mo, day = d, hour = 12 })
	panel.title:SetText((date("%A, %B %d", noon):gsub(" 0", " ")))
	local items = A.DayItems(y, mo, d)
	local top = HEADER + 3 + 10
	for _, f in ipairs(panel.items) do f:Hide() end
	for i, item in ipairs(items) do
		local f = ItemLine(i)
		f.item = item
		local c = ItemColor(item)
		f.stripe:SetColorTexture(c[1], c[2], c[3], 1)
		local when = Clock(item.at)
		if item.kind == "meeting" and item.finish and item.finish > item.at then when = when .. " - " .. Clock(item.finish) end
		f.when:SetText(when)
		f.when:SetTextColor(item.rings and A.GOLD[1] or SILENT[1], item.rings and A.GOLD[2] or SILENT[2], item.rings and A.GOLD[3] or SILENT[3])
		local kind
		if item.kind == "meeting" then
			kind = "Outlook"
		else
			kind = A.REPEATS[item.alarm.rep] or ""
			if item.alarm.rep ~= "once" then kind = kind .. " alarm" else kind = "Alarm" end
		end
		f.kind:SetText(kind)
		local text = item.label
		if item.location and item.location ~= "" then text = text .. "  |cff9a8f7f" .. item.location .. "|r" end
		f.label:SetText(text)
		f.toggle.label:SetText(item.rings and (item.kind == "meeting" and "Rings" or "On") or (item.kind == "meeting" and "Silent" or "Off"))
		f.remove:SetShown(item.kind == "alarm")
		f.hl:SetShown(panel.focus and (panel.focus == item.alarm or (item.kind == "meeting" and panel.focus.at == item.at
			and panel.focus.subject == item.subject)) or false)
		f:ClearAllPoints()
		f:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -top)
		f:Show()
		top = top + ITEM_H + 4
	end
	panel.empty:ClearAllPoints()
	panel.empty:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -top)
	panel.empty:SetShown(#items == 0)
	if #items == 0 then top = top + 18 end

	local future = Key(y, mo, d) >= Today()
	for _, w in ipairs({ panel.rule, panel.newHead, panel.time, panel.rep, panel.add, panel.label }) do w:SetShown(future) end
	if future then
		top = top + 4
		panel.rule:ClearAllPoints()
		panel.rule:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -top)
		panel.rule:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, -top)
		top = top + 10
		panel.newHead:ClearAllPoints()
		panel.newHead:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -top)
		top = top + 20
		panel.time:ClearAllPoints()
		panel.time:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -top)
		panel.rep:ClearAllPoints()
		panel.rep:SetPoint("LEFT", panel.time, "RIGHT", 8, 0)
		panel.add:ClearAllPoints()
		panel.add:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, -top)
		top = top + 26
		panel.label:ClearAllPoints()
		panel.label:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -top)
		top = top + 26
	end
	local note = panel.message
	if not note and #items > 0 then
		local status = A.CalendarStatus()
		local hasMeeting
		for _, item in ipairs(items) do if item.kind == "meeting" then hasMeeting = true end end
		if hasMeeting and status then note = "Outlook " .. status .. "." end
		if hasMeeting and not Opt().meetings then note = "Outlook meetings don't ring: turned off in Options > Alarm clock." end
	end
	panel.note:SetText(note or "")
	panel.note:SetTextColor(panel.messageBad and A.RED[1] or GREY[1], panel.messageBad and A.RED[2] or GREY[2],
		panel.messageBad and A.RED[3] or GREY[3])
	panel.note:ClearAllPoints()
	panel.note:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -(top + 2))
	panel.note:SetShown(note ~= nil)
	if note then top = top + 4 + math.ceil(panel.note:GetStringHeight()) end
	panel:SetHeight(top + PAD)
end

function C.AddFromPanel()
	if not panelDate then return end
	local h, m = A.ParseTime(panel.time:GetText())
	if not h then
		panel.message, panel.messageBad = "Type a time like 9:30am or 14:30.", true
		C.Fill()
		return
	end
	local y, mo, d = panelDate[1], panelDate[2], panelDate[3]
	local day = Key(y, mo, d)
	local at = time({ year = y, month = mo, day = d, hour = h, min = m, sec = 0 })
	if panel.repKey == "once" and at <= Now() then
		panel.message, panel.messageBad = "That time has passed.", true
		C.Fill()
		return
	end
	local label = (panel.label:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local a = A.Add(h, m, label, panel.repKey, panel.repKey == "once" and day or nil)
	panel.focus = a
	panel.message, panel.messageBad = A.Confirm(a):gsub("^a", "A"), false
	panel.time:SetText("")
	panel.label:SetText("")
	panel.time:ClearFocus()
	panel.label:ClearFocus()
	C.Fill()
end

-- Open the panel on a day square's date, with one of its items picked out, or typing a new alarm.
function C.Open(dayButton, item, typing)
	local y, mo, d = DateOf(dayButton)
	if not y then return end
	if not panel then BuildPanel() end
	panelDate = { y, mo, d }
	panel.focus = item and (item.alarm or item) or nil
	panel.message, panel.messageBad = nil, false
	Place()
	panel:Show()
	C.Fill()
	if typing then panel.time:SetFocus() end
	if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then
		pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	end
end

---------------------------------------------------------------------------

local function Hook()
	if hooked or not CalendarFrame or not CalendarFrame_UpdateDayEvents then return end
	hooked = true
	hooksecurefunc("CalendarFrame_UpdateDayEvents", function(index, day, monthOffset)
		ns.Try("calendar marks", DrawDay, index, day, monthOffset)
	end)
	hooksecurefunc("CalendarDayButton_OnEnter", function(dayButton)
		ns.Try("calendar tooltip", Tooltip, dayButton)
		ShowPlus(dayButton)
	end)
	if CalendarFrame_ShowEventFrame then
		hooksecurefunc("CalendarFrame_ShowEventFrame", function()
			if panel and panel:IsShown() then Place() end
		end)
	end
	BuildPlus()
	A.onCalendarChange = C.Refresh
	if CalendarFrame:IsShown() then C.Refresh() end
end

function C.ApplySettings()
	if not hooked then return end
	if not Enabled() and panel then panel:Hide() end
	C.Refresh()
end

function C.Init()
	local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
	if loaded and loaded("Blizzard_Calendar") then
		Hook()
		return
	end
	local f = CreateFrame("Frame")
	f:RegisterEvent("ADDON_LOADED")
	f:SetScript("OnEvent", function(self, _, name)
		if name == "Blizzard_Calendar" then
			self:UnregisterEvent("ADDON_LOADED")
			ns.Try("calendar hook", Hook)
		end
	end)
end
