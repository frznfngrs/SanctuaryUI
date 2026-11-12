SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI

-- Debug log for testers. WoW addons can only write to disk through SavedVariables, so
-- everything goes into SanctuaryUILog, which the client saves on /reload, logout or exit.
--
-- Two parts:
--   errors: every Lua error (any addon) and blocked or forbidden action. These are always
--     recorded and merged by message, so an error in an OnUpdate shows once with a count.
--     This does the jobs of BugSack and taintLog, which don't work on this client.
--   lines: a timestamped trace. Recorded only while "/sanctuary debug on" is set.
--
-- This file loads first in the TOC (before the libraries), so it catches load-time errors
-- from everything after it. LoadSavedVariablesFirst makes SanctuaryUILog readable here.

local MAX_LINES = 2000
local MAX_ERRORS = 100
local MAX_SHOWN_LINES = 1000

-- Bug reports open a prefilled GitHub issue. GitHub refuses very long URLs, so the report is
-- trimmed to fit under MAX_URL once encoded.
local ISSUE_URL = "https://github.com/frznfngrs/SanctuaryUI/issues/new"
local MAX_URL = 6000
local MAX_REPORT_MESSAGE = 500
local MAX_REPORT_STACK = 1200
local REPORT_STACK_LINES = 8
local PROMPT_DELAY = 3

local log

local function Store()
	if not log then
		SanctuaryUILog = type(SanctuaryUILog) == "table" and SanctuaryUILog or {}
		log = SanctuaryUILog
		log.lines = type(log.lines) == "table" and log.lines or {}
		log.errors = type(log.errors) == "table" and log.errors or {}
	end
	return log
end

-- Remove color codes, textures and links so the copied log is plain text.
local function Plain(text)
	text = tostring(text)
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	text = text:gsub("|T.-|t", ""):gsub("|A.-|a", "")
	text = text:gsub("|H.-|h(.-)|h", "%1")
	text = text:gsub("|n", "\n")
	return text
end

local function Stamp()
	local t = GetTime and GetTime() or 0
	return ("%s %9.3f"):format(date("%H:%M:%S"), t)
end

local function Append(text)
	local lines = Store().lines
	lines[#lines + 1] = Stamp() .. "  " .. text
	-- Trim in chunks so we don't shift the whole table on every line.
	if #lines > MAX_LINES + 200 then
		local keep, from = {}, #lines - MAX_LINES + 1
		for i = from, #lines do keep[#keep + 1] = lines[i] end
		log.lines = keep
	end
end

function ns.LogEnabled()
	return Store().enabled and true or false
end

-- ns.Log("fmt %s", ...) or ns.Log(anything). Does nothing unless debug is on.
function ns.Log(fmt, ...)
	if not Store().enabled and not ns.forceLog then return end
	local ok, text = pcall(string.format, tostring(fmt), ...)
	if not ok or select("#", ...) == 0 then
		text = tostring(fmt)
		for i = 1, select("#", ...) do text = text .. " " .. tostring((select(i, ...))) end
	end
	Append(Plain(text))
end

local function AddonVersion()
	local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
	return getMeta and getMeta("SanctuaryUI", "Version") or "?"
end

-- The global handler appends local variables to the stack. They can hold player names and
-- chat text, so they stay in the local log and never go into a report.
local function WithoutLocals(stack)
	if not stack then return "" end
	local at = stack:find("\nLocals:\n", 1, true)
	return at and stack:sub(1, at - 1) or stack
end

-- Errors the addon logged itself use their own kinds. "lua", "taint" and "warning" come from
-- the game and can belong to any addon, so those need SanctuaryUI named in them.
local function IsOurs(e)
	if e.kind ~= "lua" and e.kind ~= "taint" and e.kind ~= "warning" then return true end
	if (e.message or ""):find("SanctuaryUI", 1, true) then return true end
	return WithoutLocals(e.stack):find("SanctuaryUI", 1, true) ~= nil
end

local function IsReportable(e)
	return e.kind ~= "warning" and IsOurs(e)
end

-- Never build UI inside the error handler: wait, then let ns.PromptReport decide.
local promptScheduled, promptWaiting = false, false

local function SchedulePrompt()
	if promptScheduled or not C_Timer then return end
	promptScheduled = true
	C_Timer.After(PROMPT_DELAY, function()
		promptScheduled = false
		ns.PromptReport()
	end)
end

local function Noticed(e)
	e.version = AddonVersion()
	if e.asked ~= e.version and IsReportable(e) then SchedulePrompt() end
end

local inHandler = false

-- Record an error. Same message and same first stack line merge into one entry.
function ns.LogError(kind, message, stack)
	if inHandler then return end
	inHandler = true
	local ok = pcall(function()
		local errors = Store().errors
		message = Plain(message or "?")
		stack = stack and Plain(stack) or nil
		local key = kind .. "\0" .. message
		for _, e in ipairs(errors) do
			if e.key == key then
				e.count = (e.count or 1) + 1
				e.last = date("%Y-%m-%d %H:%M:%S")
				Noticed(e)
				return
			end
		end
		local entry = {
			key = key,
			kind = kind,
			message = message,
			stack = stack,
			count = 1,
			first = date("%Y-%m-%d %H:%M:%S"),
			last = date("%Y-%m-%d %H:%M:%S"),
			session = log.session,
		}
		errors[#errors + 1] = entry
		while #errors > MAX_ERRORS do table.remove(errors, 1) end
		if log.enabled then Append("ERROR " .. kind .. ": " .. message) end
		Noticed(entry)
	end)
	inHandler = false
	return ok
end

-- pcall that keeps the stack. Use for any call whose failure we want in the log.
function ns.Try(label, fn, ...)
	if not fn then return true end
	local stack
	local ok, err = xpcall(fn, function(e)
		stack = debugstack and debugstack(2) or nil
		return e
	end, ...)
	if not ok then
		ns.LogError("SanctuaryUI", label .. ": " .. tostring(err), stack)
	end
	return ok, err
end

-- Global error handler. Chain to whatever was there so the game's own error popup (and any
-- other addon's handler) keeps working.
do
	local previous = geterrorhandler and geterrorhandler()
	seterrorhandler(function(message, ...)
		local stack = debugstack and debugstack(3) or nil
		local locals
		if debuglocals then
			local ok, l = pcall(debuglocals, 3)
			if ok then locals = l end
		end
		-- Locals can hold secret values; even comparing one throws (error [9], 2026-11-11).
		if locals and not (issecretvalue and issecretvalue(locals)) and locals ~= "" then
			stack = (stack or "") .. "\nLocals:\n" .. locals
		end
		ns.LogError("lua", message, stack)
		if previous then return previous(message, ...) end
	end)
end

-- Facts about this client and UI: a list of lines, then the loaded addons as one line.
-- anonymous leaves out the realm, for reports that leave the player's machine.
local function Environment(anonymous)
	local lines = {}
	local function add(fmt, ...)
		local ok, text = pcall(string.format, fmt, ...)
		lines[#lines + 1] = ok and text or fmt
	end
	local build, buildNum, buildDate, toc = GetBuildInfo()
	add("SanctuaryUI %s, client %s (%s, %s), interface %s", AddonVersion(), tostring(build), tostring(buildNum), tostring(buildDate), tostring(toc))
	if UnitName then
		local _, class = UnitClass("player")
		if anonymous then
			add("player level %s %s", tostring(UnitLevel("player")), tostring(class))
		else
			local realm = GetRealmName and GetRealmName() or "?"
			add("player level %s %s on %s", tostring(UnitLevel("player")), tostring(class), realm)
		end
	end
	local w, h
	if GetPhysicalScreenSize then w, h = GetPhysicalScreenSize() end
	add("screen %sx%s, UIParent scale %.3f, uiScale cvar %s, useUiScale %s",
		tostring(w), tostring(h), UIParent:GetEffectiveScale(),
		tostring(GetCVar and GetCVar("uiScale")), tostring(GetCVar and GetCVar("useUiScale")))
	local num = (C_AddOns and C_AddOns.GetNumAddOns) or GetNumAddOns
	local info = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
	local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
	local addons
	if num and info and loaded then
		local names = {}
		for i = 1, num() do
			local name = info(i)
			if name and loaded(name) then names[#names + 1] = name end
		end
		addons = ("loaded addons (%d): %s"):format(#names, table.concat(names, ", "))
	end
	return lines, addons
end

-- Header written when a session starts with debug on, or when debug is switched on.
local function Header()
	local lines, addons = Environment()
	for _, line in ipairs(lines) do Append(line) end
	if addons then Append(addons) end
end

function ns.SetLogEnabled(on)
	Store().enabled = on and true or nil
	if on then
		Append("=== debug on ===")
		pcall(Header)
	else
		Append("=== debug off ===")
	end
end

function ns.ClearLog()
	local enabled = Store().enabled
	wipe(log.lines)
	wipe(log.errors)
	if enabled then
		Append("=== log cleared ===")
		pcall(Header)
	end
end

-- Plain-text report: errors first, then the newest trace lines.
function ns.LogReport()
	Store()
	local out = {}
	out[#out + 1] = "SanctuaryUI debug log, made " .. date("%Y-%m-%d %H:%M:%S")
	out[#out + 1] = ("debug trace is %s"):format(log.enabled and "ON" or "off (/sanctuary debug on)")
	out[#out + 1] = ""
	out[#out + 1] = ("---- %d error(s) ----"):format(#log.errors)
	for i, e in ipairs(log.errors) do
		out[#out + 1] = ("[%d] %s x%d  first %s  last %s"):format(i, e.kind or "?", e.count or 1, e.first or "?", e.last or "?")
		out[#out + 1] = e.message or "?"
		if e.stack and e.stack ~= "" then out[#out + 1] = e.stack end
		out[#out + 1] = ""
	end
	local lines = log.lines
	local from = math.max(1, #lines - MAX_SHOWN_LINES + 1)
	out[#out + 1] = ("---- trace, last %d of %d line(s) ----"):format(#lines - from + 1, #lines)
	for i = from, #lines do out[#out + 1] = lines[i] end
	return table.concat(out, "\n")
end

-- Copy window ---------------------------------------------------------------------------

local window

local function MakePanel(name, width, height)
	local f = CreateFrame("Frame", name, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	f:SetSize(width, height)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetClampedToScreen(true)
	if f.SetBackdrop then
		f:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		})
		f:SetBackdropColor(0.05, 0.04, 0.03, 0.95)
		f:SetBackdropBorderColor(0.85, 0.72, 0.42, 1)
	end
	return f
end

local function PanelButton(f, label, x, width, onClick)
	local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	b:SetSize(width, 22)
	b:SetPoint("BOTTOMLEFT", x, 14)
	b:SetText(label)
	b:SetScript("OnClick", onClick)
	return b
end

-- A scrolling read-only text area showing f.report.
local function AddReportText(f, scrollName, bottom)
	local scroll = CreateFrame("ScrollFrame", scrollName, f, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 14, -34)
	scroll:SetPoint("BOTTOMRIGHT", -34, bottom)

	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetFontObject(ChatFontNormal)
	edit:SetWidth(660)
	edit:SetMaxLetters(0)
	edit:SetScript("OnEscapePressed", function() f:Hide() end)
	-- Read-only: put the report back if the tester types into it.
	edit:SetScript("OnTextChanged", function(self, userInput)
		if userInput and f.report then
			self:SetText(f.report)
			self:HighlightText()
		end
	end)
	scroll:SetScrollChild(edit)
	scroll:SetScript("OnMouseDown", function() edit:SetFocus() end)
	f.edit = edit
	return edit
end

local function BuildWindow()
	local f = MakePanel("SanctuaryUILogFrame", 720, 480)
	f:SetPoint("CENTER")
	tinsert(UISpecialFrames, f:GetName())

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 14, -12)
	title:SetText("SanctuaryUI log. Ctrl+A, then Ctrl+C, and paste it to the developer.")

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)

	local edit = AddReportText(f, "SanctuaryUILogScroll", 44)

	PanelButton(f, "Select all", 14, 110, function()
		edit:SetFocus()
		edit:HighlightText()
	end)
	PanelButton(f, "Refresh", 130, 110, function() ns.ShowLog() end)
	PanelButton(f, "Clear", 246, 110, function()
		ns.ClearLog()
		ns.ShowLog()
	end)
	f.toggle = PanelButton(f, "", 362, 130, function()
		ns.SetLogEnabled(not ns.LogEnabled())
		ns.ShowLog()
	end)
	PanelButton(f, "Report", 498, 110, function() ns.ShowReport() end)
	return f
end

function ns.ShowLog()
	window = window or BuildWindow()
	window.report = ns.LogReport()
	window.edit:SetText(window.report)
	window.toggle:SetText(ns.LogEnabled() and "Turn trace off" or "Turn trace on")
	window:Show()
	window.edit:SetFocus()
	window.edit:SetCursorPosition(0)
	window.edit:HighlightText()
end

-- Bug report ----------------------------------------------------------------------------
--
-- Addons can't reach the network, so a report is a link the player pastes into a browser.
-- It covers only this addon's errors on the installed version, without local variables or
-- the character and realm names, and the window shows exactly what the link contains.

-- This addon's errors seen on the installed version, newest first.
local function ReportEntries()
	local found, version = {}, AddonVersion()
	for _, e in ipairs(Store().errors) do
		if e.version == version and IsReportable(e) then found[#found + 1] = e end
	end
	table.sort(found, function(a, b) return a.last > b.last end)
	return found
end

-- Each distinct error asks once per addon version, so a dismissed one doesn't come back.
local function MarkAsked()
	for _, e in ipairs(ReportEntries()) do e.asked = e.version end
end

local function Encode(text)
	return (text:gsub("[^%w%-_%.~]", function(c) return ("%%%02X"):format(c:byte()) end))
end

local function Redact(text, name)
	if not name or name == "" then return text end
	-- High bytes count as letters, so a name may start or end with an accented character.
	return (text:gsub("%f[%w\128-\255]" .. name:gsub("%p", "%%%0") .. "%f[^%w\128-\255]", "<hidden>"))
end

local function Clean(text)
	text = text:gsub("```", "'''") -- would close the report's code block
	text = Redact(text, UnitName("player"))
	return Redact(text, GetRealmName())
end

local function FirstLines(text, count)
	local out = {}
	for line in (text .. "\n"):gmatch("(.-)\n") do
		if line ~= "" then
			out[#out + 1] = line
			if #out >= count then break end
		end
	end
	return table.concat(out, "\n")
end

-- Returns the report text and the issue link holding that same text.
local function BuildReport(entries)
	local title = Clean(("[%s] %s"):format(AddonVersion(), FirstLines(entries[1].message or "?", 1):sub(1, 80)))
	local base = ISSUE_URL .. "?title=" .. Encode(title) .. "&body="
	local used = #base + 120 -- room for the fences and the "not shown" note
	local parts = { "```\n" }
	local function Add(text)
		text = Clean(text) .. "\n"
		local size = #Encode(text)
		if used + size > MAX_URL then return false end
		used = used + size
		parts[#parts + 1] = text
		return true
	end

	local lines, addons = Environment(true)
	for _, line in ipairs(lines) do Add(line) end
	Add("")
	local shown = 0
	for i, e in ipairs(entries) do
		local chunk = ("[%d] %s x%d  first %s  last %s\n%s\n"):format(i, e.kind or "?", e.count or 1,
			e.first or "?", e.last or "?", (e.message or "?"):sub(1, MAX_REPORT_MESSAGE))
		local stack = FirstLines(WithoutLocals(e.stack), REPORT_STACK_LINES):sub(1, MAX_REPORT_STACK)
		if stack ~= "" then chunk = chunk .. stack .. "\n" end
		if not Add(chunk) then break end
		shown = i
	end
	if shown < #entries then
		parts[#parts + 1] = ("%d more not shown\n"):format(#entries - shown)
	end
	if addons then Add(addons) end
	parts[#parts + 1] = "```\n"

	local body = table.concat(parts)
	return body, base .. Encode(body)
end

local reportWindow, toast

local function BuildReportWindow()
	local f = MakePanel("SanctuaryUIReportFrame", 720, 480)
	f:SetPoint("CENTER")
	tinsert(UISpecialFrames, f:GetName())

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 14, -12)
	title:SetText("Press Ctrl+C on the link, paste it into a browser, and submit. Nothing is sent until then.")

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)

	local edit = AddReportText(f, "SanctuaryUIReportScroll", 78)

	local link = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
	link:SetPoint("BOTTOMLEFT", 20, 46)
	link:SetPoint("BOTTOMRIGHT", -20, 46)
	link:SetHeight(22)
	link:SetAutoFocus(false)
	link:SetMaxLetters(0)
	link:SetScript("OnEscapePressed", function() f:Hide() end)
	link:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
	link:SetScript("OnTextChanged", function(self, userInput)
		if userInput and f.link then
			self:SetText(f.link)
			self:HighlightText()
		end
	end)
	f.linkBox = link

	PanelButton(f, "Select link", 14, 110, function()
		link:SetFocus()
		link:HighlightText()
	end)
	PanelButton(f, "Select report", 130, 110, function()
		edit:SetFocus()
		edit:HighlightText()
	end)
	return f
end

function ns.ShowReport()
	local entries = ReportEntries()
	if #entries == 0 then
		ns.Print("no SanctuaryUI errors recorded on this version, so there is nothing to report")
		return
	end
	MarkAsked()
	if toast then toast:Hide() end
	reportWindow = reportWindow or BuildReportWindow()
	reportWindow.report, reportWindow.link = BuildReport(entries)
	reportWindow.edit:SetText(reportWindow.report)
	reportWindow.edit:SetCursorPosition(0)
	reportWindow.linkBox:SetText(reportWindow.link)
	reportWindow:Show()
	reportWindow.linkBox:SetFocus()
	reportWindow.linkBox:SetCursorPosition(0)
	reportWindow.linkBox:HighlightText()
end

function ns.SetReportPrompt(on)
	Store().noPrompt = (not on) or nil
	ns.Print(on and "SanctuaryUI will offer to report its errors"
		or "SanctuaryUI won't offer to report errors. /sanctuary report still makes one, and /sanctuary report on brings the offer back")
end

local function BuildToast()
	local f = MakePanel("SanctuaryUIReportToast", 430, 78)
	f:SetPoint("TOP", UIParent, "TOP", 0, -130)

	local text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	text:SetPoint("TOP", 0, -14)
	text:SetText("SanctuaryUI hit an error. A report helps get it fixed.")

	PanelButton(f, "Report", 14, 130, function() ns.ShowReport() end)
	PanelButton(f, "Not now", 150, 130, function()
		MarkAsked()
		f:Hide()
	end)
	PanelButton(f, "Don't ask again", 286, 130, function()
		ns.SetReportPrompt(false)
		f:Hide()
	end)
	return f
end

-- Show the offer if an unasked error is waiting. Combat and the loading screen postpone it.
function ns.PromptReport()
	promptWaiting = false
	if Store().noPrompt then return end
	local unasked = false
	for _, e in ipairs(ReportEntries()) do
		if e.asked ~= e.version then unasked = true break end
	end
	if not unasked then return end
	if InCombatLockdown() or not IsLoggedIn() then
		promptWaiting = true
		return
	end
	toast = toast or BuildToast()
	toast:Show()
end

-- Feature request -----------------------------------------------------------------------
--
-- The link opens .github/ISSUE_TEMPLATE/feature_request.yml, and the form applies the
-- enhancement label. A label in the link itself only works for people with triage rights.
-- The link's idea and version parameters are that form's field ids.

local requestWindow

local function Trim(text)
	return (text:match("^%s*(.-)%s*$"))
end

local function RequestLink(title, idea)
	return ISSUE_URL .. "?template=feature_request.yml&title=" .. Encode("[Feature] " .. title)
		.. "&idea=" .. Encode(idea) .. "&version=" .. Encode(AddonVersion())
end

local function AddLabel(f, text, y)
	local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetPoint("TOPLEFT", 16, y)
	label:SetText(text)
	return label
end

local function BuildRequestWindow()
	local f = MakePanel("SanctuaryUIRequestFrame", 560, 400)
	f:SetPoint("CENTER")
	tinsert(UISpecialFrames, f:GetName())

	AddLabel(f, "Suggest a feature. Nothing is sent until you submit it on GitHub.", -12)
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)

	local titleBox, ideaBox, linkBox, status

	-- Build the link as they type, so it can never be out of date.
	local function Refresh()
		local title, idea = Trim(titleBox:GetText()), Trim(ideaBox:GetText())
		local link, message = "", "Add a title and your idea to get a link."
		if title ~= "" and idea ~= "" then
			local url = RequestLink(title, idea)
			if #url > MAX_URL then
				message = "That's too long for a link. Please shorten it."
			else
				link, message = url, "Press Select link, then Ctrl+C, and paste it into a browser."
			end
		end
		f.link = link
		linkBox:SetText(link)
		status:SetText(message)
	end

	AddLabel(f, "Title", -38)
	titleBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
	titleBox:SetPoint("TOPLEFT", 22, -56)
	titleBox:SetPoint("TOPRIGHT", -20, -56)
	titleBox:SetHeight(22)
	titleBox:SetAutoFocus(false)
	titleBox:SetMaxLetters(80)
	titleBox:SetScript("OnEscapePressed", function() f:Hide() end)
	titleBox:SetScript("OnTextChanged", Refresh)

	AddLabel(f, "What would you like, and why?", -86)
	local holder = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
	holder:SetPoint("TOPLEFT", 14, -104)
	holder:SetPoint("BOTTOMRIGHT", -14, 100)
	if holder.SetBackdrop then
		holder:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		holder:SetBackdropColor(0, 0, 0, 0.5)
		holder:SetBackdropBorderColor(0.5, 0.42, 0.25, 1)
	end

	local scroll = CreateFrame("ScrollFrame", "SanctuaryUIRequestScroll", holder, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 8, -8)
	scroll:SetPoint("BOTTOMRIGHT", -28, 8)
	scroll:EnableMouse(true)

	ideaBox = CreateFrame("EditBox", nil, scroll)
	ideaBox:SetMultiLine(true)
	ideaBox:SetAutoFocus(false)
	ideaBox:SetFontObject(ChatFontNormal)
	ideaBox:SetWidth(480)
	ideaBox:SetHeight(180)
	ideaBox:SetMaxLetters(2000)
	ideaBox:SetScript("OnEscapePressed", function() f:Hide() end)
	ideaBox:SetScript("OnTextChanged", Refresh)
	-- Keep the line being typed in view. y is negative, measured down from the top.
	ideaBox:SetScript("OnCursorChanged", function(_, _, y, _, height)
		local top, view, size = -y, scroll:GetVerticalScroll(), scroll:GetHeight()
		if top < view then
			scroll:SetVerticalScroll(math.max(0, top))
		elseif top + height > view + size then
			scroll:SetVerticalScroll(math.max(0, top + height - size))
		end
	end)
	scroll:SetScrollChild(ideaBox)
	scroll:SetScript("OnMouseDown", function() ideaBox:SetFocus() end)

	titleBox:SetScript("OnTabPressed", function() ideaBox:SetFocus() end)
	titleBox:SetScript("OnEnterPressed", function() ideaBox:SetFocus() end)
	ideaBox:SetScript("OnTabPressed", function() titleBox:SetFocus() end)

	status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	status:SetPoint("BOTTOMLEFT", 18, 76)

	linkBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
	linkBox:SetPoint("BOTTOMLEFT", 20, 46)
	linkBox:SetPoint("BOTTOMRIGHT", -20, 46)
	linkBox:SetHeight(22)
	linkBox:SetAutoFocus(false)
	linkBox:SetMaxLetters(0)
	linkBox:SetScript("OnEscapePressed", function() f:Hide() end)
	linkBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
	linkBox:SetScript("OnTextChanged", function(self, userInput)
		if userInput then
			self:SetText(f.link or "")
			self:HighlightText()
		end
	end)

	PanelButton(f, "Select link", 14, 110, function()
		if f.link and f.link ~= "" then
			linkBox:SetFocus()
			linkBox:HighlightText()
		end
	end)
	PanelButton(f, "Clear", 130, 110, function()
		titleBox:SetText("")
		ideaBox:SetText("")
		titleBox:SetFocus()
	end)

	f.titleBox, f.ideaBox, f.Refresh = titleBox, ideaBox, Refresh
	return f
end

function ns.ShowRequest()
	requestWindow = requestWindow or BuildRequestWindow()
	requestWindow.Refresh()
	requestWindow:Show()
	requestWindow.titleBox:SetFocus()
end

-- Events --------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_ACTION_BLOCKED")
events:RegisterEvent("ADDON_ACTION_FORBIDDEN")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_LOGOUT")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
pcall(events.RegisterEvent, events, "MACRO_ACTION_BLOCKED")
pcall(events.RegisterEvent, events, "LUA_WARNING")
events:SetScript("OnEvent", function(_, event, a, b)
	if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" or event == "MACRO_ACTION_BLOCKED" then
		local combat = InCombatLockdown and InCombatLockdown() and " (in combat)" or ""
		ns.LogError("taint", ("%s: %s called %s%s"):format(event, tostring(a), tostring(b), combat))
	elseif event == "LUA_WARNING" then
		ns.LogError("warning", tostring(b or a))
	elseif event == "PLAYER_LOGIN" then
		if log.enabled then pcall(Header) end
		if promptWaiting then SchedulePrompt() end
	elseif event == "PLAYER_REGEN_DISABLED" then
		if toast and toast:IsShown() then
			toast:Hide()
			promptWaiting = true
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		if promptWaiting then SchedulePrompt() end
	elseif event == "PLAYER_LOGOUT" then
		ns.Log("logout")
	end
end)

Store()
log.session = (log.session or 0) + 1
if log.enabled then Append(("=== session %d, UI loaded ==="):format(log.session)) end
