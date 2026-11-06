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
	if not Store().enabled then return end
	local ok, text = pcall(string.format, tostring(fmt), ...)
	if not ok or select("#", ...) == 0 then
		text = tostring(fmt)
		for i = 1, select("#", ...) do text = text .. " " .. tostring((select(i, ...))) end
	end
	Append(Plain(text))
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
				return
			end
		end
		errors[#errors + 1] = {
			key = key,
			kind = kind,
			message = message,
			stack = stack,
			count = 1,
			first = date("%Y-%m-%d %H:%M:%S"),
			last = date("%Y-%m-%d %H:%M:%S"),
			session = log.session,
		}
		while #errors > MAX_ERRORS do table.remove(errors, 1) end
		if log.enabled then Append("ERROR " .. kind .. ": " .. message) end
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
		if locals and locals ~= "" then
			stack = (stack or "") .. "\nLocals:\n" .. locals
		end
		ns.LogError("lua", message, stack)
		if previous then return previous(message, ...) end
	end)
end

-- Header written when a session starts with debug on, or when debug is switched on.
local function Header()
	local lines = {}
	local function add(fmt, ...)
		local ok, text = pcall(string.format, fmt, ...)
		lines[#lines + 1] = ok and text or fmt
	end
	local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
	local version = getMeta and getMeta("SanctuaryUI", "Version") or "?"
	local build, buildNum, buildDate, toc = GetBuildInfo()
	add("SanctuaryUI %s, client %s (%s, %s), interface %s", version, tostring(build), tostring(buildNum), tostring(buildDate), tostring(toc))
	if UnitName then
		local _, class = UnitClass("player")
		local realm = GetRealmName and GetRealmName() or "?"
		add("player level %s %s on %s", tostring(UnitLevel("player")), tostring(class), realm)
	end
	local w, h
	if GetPhysicalScreenSize then w, h = GetPhysicalScreenSize() end
	add("screen %sx%s, UIParent scale %.3f, uiScale cvar %s, useUiScale %s",
		tostring(w), tostring(h), UIParent:GetEffectiveScale(),
		tostring(GetCVar and GetCVar("uiScale")), tostring(GetCVar and GetCVar("useUiScale")))
	local num = (C_AddOns and C_AddOns.GetNumAddOns) or GetNumAddOns
	local info = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
	local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
	if num and info and loaded then
		local names = {}
		for i = 1, num() do
			local name = info(i)
			if name and loaded(name) then names[#names + 1] = name end
		end
		add("loaded addons (%d): %s", #names, table.concat(names, ", "))
	end
	for _, line in ipairs(lines) do Append(line) end
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

local function BuildWindow()
	local f = CreateFrame("Frame", "SanctuaryUILogFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	f:SetSize(720, 480)
	f:SetPoint("CENTER")
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
	tinsert(UISpecialFrames, f:GetName())

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 14, -12)
	title:SetText("SanctuaryUI log. Ctrl+A, then Ctrl+C, and paste it to the developer.")

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)

	local scroll = CreateFrame("ScrollFrame", "SanctuaryUILogScroll", f, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 14, -34)
	scroll:SetPoint("BOTTOMRIGHT", -34, 44)

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

	local function MakeButton(label, x, onClick)
		local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		b:SetSize(110, 22)
		b:SetPoint("BOTTOMLEFT", x, 14)
		b:SetText(label)
		b:SetScript("OnClick", onClick)
		return b
	end
	MakeButton("Select all", 14, function()
		edit:SetFocus()
		edit:HighlightText()
	end)
	MakeButton("Refresh", 130, function() ns.ShowLog() end)
	MakeButton("Clear", 246, function()
		ns.ClearLog()
		ns.ShowLog()
	end)
	f.toggle = MakeButton("", 362, function()
		ns.SetLogEnabled(not ns.LogEnabled())
		ns.ShowLog()
	end)
	f.toggle:SetWidth(130)
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

-- Events --------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_ACTION_BLOCKED")
events:RegisterEvent("ADDON_ACTION_FORBIDDEN")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_LOGOUT")
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
	elseif event == "PLAYER_LOGOUT" then
		ns.Log("logout")
	end
end)

Store()
log.session = (log.session or 0) + 1
if log.enabled then Append(("=== session %d, UI loaded ==="):format(log.session)) end
