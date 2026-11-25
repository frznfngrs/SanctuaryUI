SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.Alarm = ns.Alarm or {}
local A = ns.Alarm

-- Alarm clock: alarms at a time of day, once, every day or on weekdays, kept for the whole
-- account (ns.db.global.alarms) so every character rings. When one is due a D3 window opens at
-- the top of the screen with the time and what it's for, the sound repeats until it is dismissed
-- or snoozed, and the game's taskbar icon flashes. A heads-up can come some minutes before.
-- Times are the computer's own clock (date/time), not the realm's.
--
-- An alarm: { id, h, m, rep = "once" | "daily" | "weekdays", day = "YYYY-MM-DD" (once only),
--   label, on, done = the occurrence it last rang for, warned = the one it last warned for,
--   snooze = when a snoozed ring comes back }.
--
-- /sanctuary alarm (or /alarm): 14:30 Standup, 2:30pm weekdays Standup, in 15 Tea, list,
-- remove <n>, clear, test. Options > Setup > Alarm clock. Meetings from Outlook ring too (below).

local GRACE = 15 * 60 -- an alarm missed by up to this much (logged out, loading) still rings, late
local TICK = 2
local SNOOZE = 5 * 60
local RING_EVERY = 4 -- seconds between the sound's repeats while the window is up
local RING_FOR = 120 -- and how long it keeps repeating
local WIDTH, HEADER, PAD = 340, 30, 16

local GOLD = { 0.91, 0.78, 0.48 }
local CREAM = { 0.89, 0.84, 0.75 }
local RED = { 1, 0.45, 0.25 }

-- The sounds to pick from (SOUNDKIT names, with their IDs for clients without the table).
A.SOUNDS = {
	clock = { "ALARM_CLOCK_WARNING_3", 12889, "Alarm clock" },
	raid = { "RAID_WARNING", 8959, "Raid warning" },
	ready = { "READY_CHECK", 8960, "Ready check" },
	none = { nil, nil, "None" },
}
A.SOUND_ORDER = { "clock", "raid", "ready", "none" }
A.REPEATS = { once = "Once", daily = "Every day", weekdays = "Weekdays" }
A.REPEAT_ORDER = { "once", "daily", "weekdays" }

local frame, ticker
local queue = {} -- rings waiting behind the one shown: { alarm, kind = "ring" | "warn", at }
local current -- the one shown
local ringStarted, lastRing

local function Opt() return ns.DB().alarm end
local function List()
	local global = ns.db and ns.db.global
	if not global then return {} end
	global.alarms = global.alarms or {}
	return global.alarms
end
A.List = List

local function Now() return time() end

local function Military()
	local get = C_CVar and C_CVar.GetCVarBool or GetCVarBool
	local ok, v = pcall(get, "timeMgrUseMilitaryTime")
	return ok and v or false
end

-- "14:30" or "2:30 PM", as the game's clock is set.
function A.FormatTime(h, m)
	if Military() then return ("%02d:%02d"):format(h, m) end
	local suffix = h >= 12 and "PM" or "AM"
	local h12 = h % 12
	if h12 == 0 then h12 = 12 end
	return ("%d:%02d %s"):format(h12, m, suffix)
end

local function DayKey(t) return ("%04d-%02d-%02d"):format(t.year, t.month, t.day) end

-- The epoch time of h:m on the day of t (a date table).
local function At(t, h, m)
	return time({ year = t.year, month = t.month, day = t.day, hour = h, min = m, sec = 0 })
end

-- The occurrence an alarm is about now: today's (or, for a one-off, its own day's), or nil
-- when it doesn't ring today. Returns its time and a key naming it.
local function Occurrence(a, now)
	if a.rep == "meeting" then return a.at, "meeting" end
	if a.rep == "once" then
		local y, mo, d = (a.day or ""):match("^(%d+)-(%d+)-(%d+)$")
		if not y then return nil end
		local at = At({ year = tonumber(y), month = tonumber(mo), day = tonumber(d) }, a.h, a.m)
		return at, a.day
	end
	local t = date("*t", now)
	if a.rep == "weekdays" and (t.wday == 1 or t.wday == 7) then return nil end
	return At(t, a.h, a.m), DayKey(t)
end

-- When it next rings, after now (for the list): epoch time, or nil when it never will again.
function A.NextRing(a, now)
	now = now or Now()
	if not a.on then return nil end
	if a.snooze and a.snooze > now then return a.snooze end
	if a.rep == "once" then
		local at, key = Occurrence(a, now)
		if at and a.done ~= key and at + GRACE > now then return at end
		return nil
	end
	for i = 0, 7 do
		local t = date("*t", now + i * 86400)
		if not (a.rep == "weekdays" and (t.wday == 1 or t.wday == 7)) then
			local at = At(t, a.h, a.m)
			if at > now or (i == 0 and a.done ~= DayKey(t) and at + GRACE > now) then return at end
		end
	end
	return nil
end

-- "in 25 min", "in 3 h 10 min", "tomorrow 9:00 AM", "Mon 9:00 AM".
function A.Describe(a, now)
	now = now or Now()
	local nextAt = A.NextRing(a, now)
	if not nextAt then return a.on and "done" or "off" end
	local mins = math.floor((nextAt - now) / 60 + 0.5)
	if mins < 1 then return "now" end
	if mins < 60 then return ("in %d min"):format(mins) end
	if mins < 12 * 60 then return ("in %d h %d min"):format(math.floor(mins / 60), mins % 60) end
	local t, today = date("*t", nextAt), date("*t", now)
	local clock = A.FormatTime(t.hour, t.min)
	if DayKey(t) == DayKey(today) then return "today " .. clock end
	if DayKey(t) == DayKey(date("*t", now + 86400)) then return "tomorrow " .. clock end
	return date("%a", nextAt) .. " " .. clock
end

---------------------------------------------------------------------------
-- The window

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

-- D3's red button plate in three slices, with a label (as WhatsNew.lua's).
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

A.Text, A.Plate, A.GOLD, A.CREAM, A.RED, A.DayKey = Text, Plate, GOLD, CREAM, RED, DayKey

local function Build()
	frame = CreateFrame("Frame", "SanctuaryUIAlarm", UIParent)
	frame:SetFrameStrata("FULLSCREEN_DIALOG")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:SetSize(WIDTH, 150)
	frame:Hide()

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

	local head = CreateFrame("Frame", nil, frame)
	head:SetPoint("TOPLEFT", frame, "TOPLEFT", 3, -3)
	head:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -3, -3)
	head:SetHeight(HEADER)
	local glassEdge = head:CreateTexture(nil, "BACKGROUND")
	glassEdge:SetAllPoints()
	glassEdge:SetColorTexture(0.04, 0.03, 0.024, 1)
	frame.glass = {}
	local L = ns.Meter and ns.Meter.Lib
	if L and L.LayGlass then L.LayGlass(head, frame.glass, WIDTH - 14, HEADER - 8) end
	frame.title = Text(head, TitleFont(), 13, GOLD)
	frame.title:SetPoint("LEFT", head, "LEFT", 12, -1)
	frame.more = Text(head, BodyFont(), 9, CREAM, "RIGHT")
	frame.more:SetPoint("RIGHT", head, "RIGHT", -12, -1)

	frame.clock = Text(frame, TitleFont(), 26, GOLD)
	frame.clock:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(HEADER + 14))
	frame.when = Text(frame, BodyFont(), 10, RED)
	frame.when:SetPoint("BOTTOMLEFT", frame.clock, "BOTTOMRIGHT", 10, 4)
	frame.label = Text(frame, BodyFont(), 12, CREAM)
	frame.label:SetPoint("TOPLEFT", frame.clock, "BOTTOMLEFT", 0, -8)
	frame.label:SetWidth(WIDTH - 2 * PAD)
	frame.label:SetWordWrap(true)

	frame.snooze = Plate(frame, 110, 24, "Snooze 5 min", 9)
	frame.dismiss = Plate(frame, 110, 24, "Dismiss", 9)
	frame.dismiss:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, 12)
	frame.snooze:SetPoint("RIGHT", frame.dismiss, "LEFT", -8, 0)
	frame.snooze:SetScript("OnClick", function() A.Snooze() end)
	frame.dismiss:SetScript("OnClick", function() A.Dismiss() end)

	-- The window's light pulses while it rings.
	frame.pulse = frame:CreateTexture(nil, "BORDER")
	frame.pulse:SetPoint("TOPLEFT", 3, -3)
	frame.pulse:SetPoint("BOTTOMRIGHT", -3, 3)
	frame.pulse:SetColorTexture(1, 0.4, 0.15, 1)
	frame.pulse:SetBlendMode("ADD")
	frame.pulse:SetAlpha(0)
	frame:SetScript("OnUpdate", function(_, elapsed)
		if not current or current.kind ~= "ring" then
			frame.pulse:SetAlpha(0)
			return
		end
		local t = GetTime()
		frame.pulse:SetAlpha(0.05 + 0.05 * math.sin(t * 5))
	end)
end

local function PlayRing(kind)
	local key = Opt().sound
	local s = A.SOUNDS[key] or A.SOUNDS.clock
	if not s[2] then return end
	local id = (SOUNDKIT and s[1] and SOUNDKIT[s[1]]) or s[2]
	if kind == "warn" then id = (SOUNDKIT and SOUNDKIT.READY_CHECK) or 8960 end
	if PlaySound then pcall(PlaySound, id, "Master") end
end

local function Flash()
	if Opt().flash and FlashClientIcon then pcall(FlashClientIcon) end
end

-- What the window says for a ring or heads-up.
local function Fill(item)
	local a, now = item.alarm, Now()
	local preview = item.kind == "preview"
	frame.title:SetText(item.kind == "warn" and "Coming up" or a.rep == "meeting" and "Meeting" or "Alarm")
	frame.clock:SetText(A.FormatTime(a.h, a.m))
	local when
	if item.kind == "warn" then
		when = ("in %d min"):format(math.max(1, math.floor((item.at - now) / 60 + 0.5)))
	elseif preview then
		when = "preview"
	else
		local late = math.floor((now - item.at) / 60)
		when = late >= 1 and ("%d min ago"):format(late) or "now"
	end
	frame.when:SetText(when)
	local text = a.label and a.label ~= "" and a.label or "Alarm"
	if a.location and a.location ~= "" then text = text .. "\n|cffb3a78f" .. a.location .. "|r" end
	frame.label:SetText(text)
	frame.snooze:SetShown(item.kind == "ring")
	frame.dismiss.label:SetText(item.kind == "warn" and "OK" or "Dismiss")
	frame.more:SetText(#queue > 0 and ("+%d more"):format(#queue) or "")
	local h = HEADER + 14 + 26 + 8 + math.ceil(frame.label:GetStringHeight()) + 14 + 24 + 12
	frame:SetSize(WIDTH, h)
end

function A.Layout()
	if not frame then return end
	local opt = Opt()
	frame:SetScale(ns.Art.D3Scale(opt.scale) * 1080 / 768)
	frame:ClearAllPoints()
	if opt.moved then
		frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", ns.MovedPoint(frame, opt))
	else
		frame:SetPoint("TOP", UIParent, "TOP", 0, -120)
	end
end

local function ShowNext()
	current = table.remove(queue, 1)
	if not current then
		if frame and not A.unlocked then frame:Hide() end
		return
	end
	if not frame then Build() end
	A.Layout()
	Fill(current)
	frame:Show()
	frame:Raise()
	ringStarted, lastRing = GetTime(), GetTime()
	PlayRing(current.kind)
	Flash()
end

local function Enqueue(item)
	if current and current.kind == "preview" then current = nil end
	queue[#queue + 1] = item
	if not current then ShowNext() elseif frame then frame.more:SetText(("+%d more"):format(#queue)) end
end

function A.Dismiss()
	if current and current.kind == "ring" then
		local a = current.alarm
		a.snooze = nil
		if a.rep == "once" then a.on = false end
	end
	current = nil
	ShowNext()
	A.Changed()
end

function A.Snooze()
	if current and current.kind == "ring" then
		current.alarm.snooze = Now() + SNOOZE
		ns.Print(("alarm snoozed until %s."):format(date(Military() and "%H:%M" or "%I:%M %p", current.alarm.snooze)))
	end
	current = nil
	ShowNext()
	A.Changed()
end

---------------------------------------------------------------------------
-- The clock

-- One alarm (or meeting) against the clock: ring it, warn of it, or bring a snooze back.
local function Consider(a, now, lead)
	if not a.on then return end
	if a.snooze then
		if now >= a.snooze then
			a.snooze = nil
			Enqueue({ alarm = a, kind = "ring", at = now })
			ns.Print(("alarm: %s"):format(a.label ~= "" and a.label or A.FormatTime(a.h, a.m)))
		end
		return
	end
	local at, key = Occurrence(a, now)
	if not at then return end
	if now >= at and a.done ~= key then
		a.done = key
		if now - at <= GRACE then
			Enqueue({ alarm = a, kind = "ring", at = at })
			ns.Print(("%s %s: %s"):format(a.rep == "meeting" and "meeting" or "alarm", A.FormatTime(a.h, a.m), a.label ~= "" and a.label or "time's up"))
		elseif a.rep == "once" then
			a.on = false -- long past: missed while away
		end
		A.Changed()
	elseif lead > 0 and now < at and now >= at - lead and a.warned ~= key and a.done ~= key then
		a.warned = key
		Enqueue({ alarm = a, kind = "warn", at = at })
	end
end

---------------------------------------------------------------------------
-- Meetings: SanctuaryUI_Calendar, an addon tools/outlook/outlook_sync.ps1 writes from Outlook
-- on this PC (only in the game's AddOns folder, never in this repo), sets SanctuaryUICalendar =
-- { updated = epoch, events = { { start, finish, subject, location }, ... } }. It is read as
-- the game loaded it (login or /reload). Each meeting rings at its start like a one-off alarm;
-- what has rung or been snoozed is kept in global.alarmMeetings by start and subject.

local MEETING_AHEAD = 2 * 86400 -- meetings further off than this aren't followed yet

local function Calendar()
	local cal = rawget(_G, "SanctuaryUICalendar")
	if type(cal) ~= "table" or type(cal.events) ~= "table" then return nil end
	return cal
end

-- The meetings still to come (or ringing), soonest first: { start, subject, location }.
function A.Meetings(now)
	now = now or Now()
	local out = {}
	local cal = Calendar()
	if not cal then return out end
	for _, e in ipairs(cal.events) do
		if type(e) == "table" and type(e.start) == "number" and e.start + GRACE > now then
			out[#out + 1] = { start = e.start, subject = type(e.subject) == "string" and e.subject or "",
				location = type(e.location) == "string" and e.location or "" }
		end
	end
	table.sort(out, function(x, y) return x.start < y.start end)
	return out
end

-- "synced 3 min ago", or why there are no meetings.
function A.CalendarStatus(now)
	now = now or Now()
	local cal = Calendar()
	if not cal then return nil end
	local age = math.floor((now - (tonumber(cal.updated) or 0)) / 60)
	if age < 1 then return "synced just now" end
	if age < 120 then return ("synced %d min ago"):format(age) end
	return ("synced %d h ago"):format(math.floor(age / 60))
end

local function MeetingState()
	local global = ns.db and ns.db.global
	if not global then return {} end
	global.alarmMeetings = global.alarmMeetings or {}
	return global.alarmMeetings
end

-- Whether a meeting rings: on unless turned off (from the game calendar's day panel).
function A.MeetingRings(start, subject)
	local a = MeetingState()[start .. "|" .. (subject or "")]
	return not (a and a.on == false)
end

function A.SetMeetingRings(start, subject, on)
	local state = MeetingState()
	local key = start .. "|" .. (subject or "")
	local a = state[key]
	if not a then
		local t = date("*t", start)
		a = { h = t.hour, m = t.min, at = start, rep = "meeting", on = true }
		state[key] = a
	end
	a.on = on and true or false
	if not on and current and current.alarm == a then current = nil ShowNext() end
	A.Changed()
end

-- What is on one day of the computer's calendar, by time: Outlook meetings (all of that day's,
-- rung or not) and the alarms that ring that day (a repeating one from today on).
-- { kind = "meeting" | "alarm", at, finish, label, location, rings, alarm, subject }
function A.DayItems(year, month, day, now)
	now = now or Now()
	local out = {}
	local first = time({ year = year, month = month, day = day, hour = 0, min = 0, sec = 0 })
	local t = date("*t", first)
	local key = DayKey(t)
	local after = time({ year = year, month = month, day = day + 1, hour = 0, min = 0, sec = 0 })
	local cal = Calendar()
	if cal then
		for _, e in ipairs(cal.events) do
			if type(e) == "table" and type(e.start) == "number" and e.start >= first and e.start < after then
				local subject = type(e.subject) == "string" and e.subject or ""
				out[#out + 1] = { kind = "meeting", at = e.start, finish = tonumber(e.finish), subject = subject,
					label = subject ~= "" and subject or "Meeting",
					location = type(e.location) == "string" and e.location or "",
					rings = Opt().meetings and A.MeetingRings(e.start, subject) }
			end
		end
	end
	local today = DayKey(date("*t", now))
	for _, a in ipairs(List()) do
		local on
		if a.rep == "once" then on = a.day == key
		elseif a.rep == "daily" then on = key >= today
		elseif a.rep == "weekdays" then on = key >= today and t.wday ~= 1 and t.wday ~= 7 end
		if on then
			out[#out + 1] = { kind = "alarm", at = At(t, a.h, a.m), label = a.label ~= "" and a.label or "Alarm",
				alarm = a, rings = a.on and true or false }
		end
	end
	table.sort(out, function(x, y)
		if x.at ~= y.at then return x.at < y.at end
		return x.kind < y.kind
	end)
	return out
end

local function CheckMeetings(now, lead)
	local state = MeetingState()
	for key, a in pairs(state) do
		if type(a) ~= "table" or (a.at or 0) < now - 2 * 86400 then state[key] = nil end
	end
	for _, e in ipairs(A.Meetings(now)) do
		if e.start <= now + MEETING_AHEAD then
			local key = e.start .. "|" .. e.subject
			local a = state[key]
			if not a then
				local t = date("*t", e.start)
				a = { h = t.hour, m = t.min, at = e.start, rep = "meeting", on = true }
				state[key] = a
			end
			a.label = e.subject ~= "" and e.subject or "Meeting"
			a.location = e.location
			Consider(a, now, lead)
		end
	end
end

local function Check()
	local opt = Opt()
	if not opt.enabled then return end
	local now = Now()
	local lead = (tonumber(opt.lead) or 0) * 60
	for _, a in ipairs(List()) do Consider(a, now, lead) end
	if opt.meetings then CheckMeetings(now, lead) end
	-- The ring repeats while the window is up.
	if current and current.kind == "ring" and opt.repeatSound and ringStarted then
		local t = GetTime()
		if t - ringStarted < RING_FOR and t - lastRing >= RING_EVERY then
			lastRing = t
			PlayRing("ring")
		end
	end
end

---------------------------------------------------------------------------
-- Editing

local function NewId()
	local most = 0
	for _, a in ipairs(List()) do most = math.max(most, a.id or 0) end
	return most + 1
end

-- An alarm from a time of day: today if it's still ahead, else tomorrow (one-offs), or on the
-- day given ("YYYY-MM-DD", from the game calendar).
function A.Add(h, m, label, rep, day)
	rep = A.REPEATS[rep] and rep or "once"
	local now = Now()
	local a = { id = NewId(), h = h, m = m, label = label or "", rep = rep, on = true }
	if rep == "once" and day then
		a.day = day
	elseif rep == "once" then
		local t = date("*t", now)
		if At(t, h, m) <= now then t = date("*t", now + 86400) end
		a.day = DayKey(t)
	else
		-- Today's has passed: don't ring for it the moment it's made.
		local at, key = Occurrence(a, now)
		if at and at <= now then a.done = key end
	end
	local list = List()
	list[#list + 1] = a
	table.sort(list, function(x, y) return x.h * 60 + x.m < y.h * 60 + y.m end)
	A.Changed()
	return a
end

function A.Remove(a)
	local list = List()
	for i = #list, 1, -1 do
		if list[i] == a then table.remove(list, i) end
	end
	if current and current.alarm == a then current = nil ShowNext() end
	for i = #queue, 1, -1 do if queue[i].alarm == a then table.remove(queue, i) end end
	A.Changed()
end

-- Turn one on again: a one-off moves to the next time that time of day comes round.
function A.SetOn(a, on)
	a.on = on and true or false
	a.snooze = nil
	if on and a.rep == "once" and not A.NextRing(a) then
		local now = Now()
		local t = date("*t", now)
		if At(t, a.h, a.m) <= now then t = date("*t", now + 86400) end
		a.day, a.done = DayKey(t), nil
	end
	A.Changed()
end

-- Tell the options window (and the game calendar's marks) the list changed.
function A.Changed()
	if A.onChange then pcall(A.onChange) end
	if A.onCalendarChange then pcall(A.onCalendarChange) end
end

-- "14:30", "1430", "9", "2:30pm", "2pm", "2.30 pm". Returns h, m or nil.
function A.ParseTime(text)
	text = (text or ""):lower():gsub("%s+", "")
	local h, m, suffix = text:match("^(%d%d?)[:%.]?(%d%d)([ap]?)m?$")
	if not h then
		h, suffix = text:match("^(%d%d?)([ap]?)m?$")
		m = "0"
	end
	if not h then return nil end
	h, m = tonumber(h), tonumber(m)
	if suffix == "p" and h < 12 then h = h + 12 end
	if suffix == "a" and h == 12 then h = 0 end
	if h > 23 or m > 59 then return nil end
	return h, m
end

-- "alarm set for 9:30 AM (weekdays): Standup, in 25 min."
function A.Confirm(a)
	return ("alarm set for %s (%s)%s, %s."):format(A.FormatTime(a.h, a.m), (A.REPEATS[a.rep] or a.rep):lower(),
		a.label ~= "" and (": " .. a.label) or "", A.Describe(a))
end

local function Usage()
	ns.Print("alarms: /alarm 14:30 Standup, /alarm 9:30am weekdays Standup, /alarm 6pm daily Raid, /alarm in 15 Tea, /alarm list, /alarm remove <n>, /alarm clear, /alarm test.")
end

-- "Today 2:30 PM", "Tue 9:00 AM": when a meeting starts.
function A.MeetingTime(start, now)
	now = now or Now()
	local t = date("*t", start)
	local day = DayKey(t) == DayKey(date("*t", now)) and "Today" or DayKey(t) == DayKey(date("*t", now + 86400)) and "Tomorrow"
		or date("%a", start)
	return day .. " " .. A.FormatTime(t.hour, t.min)
end

local function PrintList()
	local list = List()
	if #list == 0 then ns.Print("no alarms. /alarm 14:30 Standup sets one.") end
	for i, a in ipairs(list) do
		ns.Print(("%d. %s %s%s, %s"):format(i, A.FormatTime(a.h, a.m), A.REPEATS[a.rep] or a.rep,
			a.label ~= "" and (": " .. a.label) or "", A.Describe(a)))
	end
	local status = A.CalendarStatus()
	if status then
		local meetings = A.Meetings()
		ns.Print(("Outlook meetings (%s): %d coming up%s"):format(status, #meetings, Opt().meetings and "" or ", not ringing (turned off)"))
		for i = 1, math.min(5, #meetings) do
			local e = meetings[i]
			ns.Print(("  %s  %s"):format(A.MeetingTime(e.start), e.subject))
		end
	end
end

function A.Slash(rest)
	rest = (rest or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local word, tail = rest:match("^(%S*)%s*(.*)$")
	word = (word or ""):lower()
	if word == "" or word == "help" then
		Usage()
		PrintList()
	elseif word == "list" then
		PrintList()
	elseif word == "test" then
		A.Test()
	elseif word == "clear" then
		local list = List()
		for i = #list, 1, -1 do list[i] = nil end
		queue = {}
		if current then current = nil ShowNext() end
		A.Changed()
		ns.Print("all alarms removed.")
	elseif word == "remove" or word == "delete" or word == "del" then
		local n = tonumber(tail)
		local a = n and List()[n]
		if not a then ns.Print("no alarm " .. tostring(tail) .. ". /alarm list numbers them.") return end
		A.Remove(a)
		ns.Print(("removed the %s alarm."):format(A.FormatTime(a.h, a.m)))
	elseif word == "in" then
		-- "in 15 Tea", "in 15m Tea", "in 15 min Tea"
		local mins, label = tail:match("^(%d+)%s*(.*)$")
		mins = tonumber(mins)
		local unit, after = (label or ""):match("^(%a+)%s*(.*)$")
		if unit and (unit:lower() == "m" or unit:lower():match("^mins?$") or unit:lower():match("^minutes?$")) then label = after end
		if not mins or mins < 1 then Usage() return end
		local t = date("*t", Now() + mins * 60)
		local a = A.Add(t.hour, t.min, label, "once")
		a.day = DayKey(t)
		ns.Print(("alarm set for %s%s, in %d min."):format(A.FormatTime(a.h, a.m), label ~= "" and (": " .. label) or "", mins))
	else
		-- A time, maybe "2:30 pm" in two words, then an optional repeat, then the label.
		local h, m = A.ParseTime(word)
		local after = tail
		if not h then
			local two, more = tail:match("^(%a%a?)%s*(.*)$")
			if two and (two:lower() == "am" or two:lower() == "pm") then
				h, m = A.ParseTime(word .. two)
				after = more
			end
		end
		if not h then Usage() return end
		local rep = "once"
		local first, more = after:match("^(%S+)%s*(.*)$")
		local key = first and first:lower()
		if key == "daily" or key == "everyday" or key == "every-day" then rep, after = "daily", more
		elseif key == "weekdays" or key == "weekday" then rep, after = "weekdays", more end
		local a = A.Add(h, m, after, rep)
		ns.Print(A.Confirm(a))
	end
end

---------------------------------------------------------------------------

-- The window as it rings, with a made-up alarm, sound and all (Options' Test).
function A.Test()
	if not frame then Build() end
	local t = date("*t", Now())
	Enqueue({ alarm = { h = t.hour, m = t.min, label = "Test alarm: this is how it rings", rep = "once" }, kind = "ring", at = Now() })
end

-- While frames are unlocked: a stand-in window to place, with its mover.
function A.UpdateMovers(unlocked)
	if not A.mover then return end
	local show = unlocked and Opt().enabled and true or false
	A.unlocked = show
	A.mover:SetShown(show)
	if show then
		if not current then
			Fill({ alarm = { h = 14, m = 30, label = "Where alarms ring", rep = "once" }, kind = "preview", at = Now() })
			A.Layout()
			frame:Show()
		end
	elseif not current then
		frame:Hide()
	end
end

function A.ResetPosition()
	local opt = Opt()
	opt.moved, opt.mx, opt.my = false, 0, 0
	ns.Refresh()
end

function A.ApplySettings()
	A.Layout()
end

function A.Init()
	Build()
	A.Layout()
	A.mover = ns.MakeMover(frame, "Alarm", Opt, "Reset its position in /sanctuary > Alarm clock.", UIParent)
	A.mover:Hide()
	SLASH_SANCTUARYALARM1 = "/alarm"
	SlashCmdList.SANCTUARYALARM = A.Slash
	ticker = C_Timer.NewTicker(TICK, function() ns.Try("alarm", Check) end)
	Check()
end
