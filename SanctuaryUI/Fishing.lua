SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.Fishing = ns.Fishing or {}
local F = ns.Fishing

-- Fishing tools, alongside the angler's journal (FishingJournal.lua):
--   * double right-click the water to cast (with a pole on, out of combat, not mounted,
--     swimming or flying); with no lure on the pole, that click puts the best lure you
--     carry on first
--   * catches looted for you
--   * a session panel on D3's lore plate: your skill, the lure's time, this session's catches,
--     fish an hour, got-aways and skill-ups, the catches to the next point, and on Sunday
--     afternoons in Stranglethorn the Extravaganza (Tastyfish count, the race's time, the
--     oldest fish's rot)
--   * a warning as the lure runs out
--   * the console fades back while you fish, and comes back at once in combat or under the mouse
--
-- Casting and lures are protected: a secure button does them, reached through an override
-- binding on the second right-click (set out of combat only, cleared after the click).

_G["BINDING_NAME_CLICK SanctuaryUIFishingCast:LeftButton"] = "Cast Fishing (or put on a lure)"

local ATLAS = 1024
local PLATE = { x = 640, y = 360, w = 366, h = 86, edge = 18 } -- journal.png, nine-sliced
local PANEL_W = 270
local PAD = { x = 16, top = 13, bottom = 13 }
local DOUBLE_CLICK = 0.4 -- seconds between the two right-clicks
local ACTIVE_AFTER = 8 -- seconds after a cast ends that you still count as fishing (fade)
local SESSION_IDLE = 15 * 60 -- a cast after this long starts a new session
local PANEL_LINGER = 3 * 60 -- the panel stays this long after the last cast
local LURE_WARN = 60
local TASTYFISH = 19807
local TASTY_ROT = 4 * 3600

local function Opt()
	return ns.DB().fishing
end

local function Readable(v)
	return v ~= nil and not ns.Secret(v)
end

local function D() return ns.FishingData end

---------------------------------------------------------------------------
-- What's going on: the pole, the lure, the channel, the session.

local GetInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local ItemCount = (C_Item and C_Item.GetItemCount) or GetItemCount

local POLE_IDS
local function PoleEquipped()
	local id = GetInventoryItemID and GetInventoryItemID("player", 16)
	if not Readable(id) or not id then return false end
	if GetInstant then
		local _, _, _, _, _, classID, subclassID = GetInstant(id)
		if classID then return classID == 2 and subclassID == 20 end
	end
	if not POLE_IDS then
		POLE_IDS = {}
		for _, p in ipairs(D().POLES) do POLE_IDS[p[2]] = true end
	end
	return POLE_IDS[id] or false
end
F.PoleEquipped = PoleEquipped

local function FishingName()
	local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(7620)
	if not Readable(name) and GetSpellInfo then name = GetSpellInfo(7620) end
	return (Readable(name) and type(name) == "string") and name or (PROFESSIONS_FISHING or "Fishing")
end

-- Seconds left on the lure on your pole, or nil.
local function LureLeft()
	if not PoleEquipped() or not GetWeaponEnchantInfo then return end
	local ok, has, expires = pcall(GetWeaponEnchantInfo)
	if not ok or not Readable(has) or not has or not Readable(expires) then return end
	return (expires or 0) / 1000
end
F.LureLeft = LureLeft

-- The best lure in your bags for your skill: its row in the book.
local function BestLure()
	local rank = ns.Journal and ns.Journal.Skill and ns.Journal.Skill()
	local best
	for _, l in ipairs(D().LURES) do
		local count = ItemCount and ItemCount(l[2]) or 0
		if Readable(count) and count > 0 and (not rank or l[4] <= rank) and (not best or l[3] > best[3]) then
			best = l
		end
	end
	return best
end

local channeling = false
local lastCast = 0 -- GetTime() a Fishing channel last ended (or now, while one runs)
local session -- { start, catches, escapes, skillups, rank, sinceSkill, lastPoint, tasty = { times } }
local lureName -- the lure our button put on last

local function Active()
	return channeling or (GetTime() - lastCast) < ACTIVE_AFTER
end
F.Active = Active

local function Skill()
	if ns.Journal and ns.Journal.Skill then return ns.Journal.Skill() end
end

local function NewSession()
	local rank = Skill()
	session = { start = GetTime(), catches = 0, escapes = 0, skillups = 0, rank = rank, sinceSkill = 0, tasty = {} }
end

---------------------------------------------------------------------------
-- A short trace of the casting path, kept even with debug off: /sanctuary fish clicks prints
-- it, and it lands in the saved log (SanctuaryUILog) on /reload.

local trace = {}
local function Trace(fmt, ...)
	local ok, text = pcall(string.format, fmt, ...)
	text = ("%.1f %s"):format(GetTime(), ok and text or tostring(fmt))
	trace[#trace + 1] = text
	while #trace > 40 do table.remove(trace, 1) end
	ns.forceLog = true
	ns.Log("fishing: %s", text)
	ns.forceLog = nil
end

function F.PrintTrace()
	ns.Print(("Fishing casting trace (%d lines, newest last):"):format(#trace))
	if #trace == 0 then ns.Print("  nothing yet: put a pole on and double right-click the water.") end
	for _, line in ipairs(trace) do ns.Print("  " .. line) end
end

---------------------------------------------------------------------------
-- Double right-click to cast, through a secure button.

local castButton, owner
local lastPress = 0
local armed = false

local function Disarm()
	armed = false
	if owner and not InCombatLockdown() then ClearOverrideBindings(owner) end
end

-- Can a double right-click cast now? false and why, when not.
local function Ready()
	local opt = Opt()
	if not opt.doubleClick then return false, "double-click is off" end
	if InCombatLockdown() then return false, "in combat" end
	if not PoleEquipped() then return false, "no fishing pole on" end
	if channeling then return false, "already fishing (the click goes to the bobber)" end
	if IsMounted and IsMounted() then return false, "mounted" end
	if IsSwimming and IsSwimming() then return false, "swimming" end
	if IsFlying and IsFlying() then return false, "flying" end
	if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return false, "dead" end
	if GetCursorInfo and GetCursorInfo() then return false, "holding something on the cursor" end
	return true
end

-- Point the button at a lure (when the pole has none and you carry one) or at the cast.
local function Configure()
	if InCombatLockdown() then return end
	local lure = Opt().autoLure and PoleEquipped() and not LureLeft() and BestLure()
	if lure then
		castButton:SetAttribute("type", "macro")
		castButton:SetAttribute("macrotext", ("/use item:%d\n/use 16"):format(lure[2]))
		castButton.lure = lure[1]
	else
		castButton:SetAttribute("type", "spell")
		castButton:SetAttribute("spell", FishingName())
		castButton.lure = nil
	end
end

-- The first right-press binds the right button to the cast for a moment; a second press in
-- that moment is the double-click and casts. (On this client a binding set during a press
-- doesn't catch that press's release, so the binding has to be in place before the second
-- press starts.) No second press in time: the right button goes back to the game at once.
local armedAt, secondAt = 0, 0

local function Arm(now)
	if InCombatLockdown() then return end
	Configure()
	SetOverrideBindingClick(owner, true, "BUTTON2", castButton:GetName(), "LeftButton")
	armed, armedAt, secondAt = true, now, 0
	C_Timer.After(DOUBLE_CLICK + 0.05, function()
		if armed and armedAt == now and secondAt < armedAt then Disarm() end
	end)
	-- A second press came but no click followed (dragged off the world): let go anyway.
	C_Timer.After(2, function()
		if armed and armedAt == now then
			Trace("no click followed the double-click: disarmed")
			Disarm()
		end
	end)
end

-- A right-button press over the world, from either source (they can both see one press).
local function RightPress(source)
	local now = GetTime()
	if now - lastPress < 0.03 then return end
	lastPress = now
	if armed and now - armedAt <= DOUBLE_CLICK then
		secondAt = now
		Trace("%s right-press: second of a double-click, %s on release", source, castButton.lure and ("putting on " .. castButton.lure) or "casting")
		return
	end
	local ready, why = Ready()
	if not ready then
		if PoleEquipped() then Trace("%s right-press, not casting: %s", source, why) end
		return
	end
	Arm(now)
end

local function OnWorldMouseDown(_, button)
	if button == "RightButton" then RightPress("world") end
end

-- The mouse is over the 3D world, not a frame.
local function OverWorld()
	local foci = GetMouseFoci and GetMouseFoci() or { GetMouseFocus and GetMouseFocus() }
	local focus = foci and foci[1]
	return focus == nil or focus == WorldFrame
end

local function BuildCasting()
	owner = CreateFrame("Frame", "SanctuaryUIFishingOwner", UIParent)
	castButton = CreateFrame("Button", "SanctuaryUIFishingCast", UIParent, "SecureActionButtonTemplate")
	castButton:Hide()
	castButton:RegisterForClicks("AnyUp", "AnyDown")
	-- The press that armed us has already gone down: act on the release.
	castButton:SetAttribute("useOnKeyDown", false)
	castButton:SetAttribute("type", "spell")
	castButton:SetAttribute("spell", FishingName())
	-- Lure or cast, decided at the click (the key binding comes here too).
	castButton:SetScript("PreClick", function(self, button, down)
		if not down then Configure() end
	end)
	castButton:SetScript("PostClick", function(self, button, down)
		Trace("button clicked (%s, %s): %s", tostring(button), down and "down" or "up", self.lure and ("put on " .. self.lure) or "cast")
		if self.lure and not down then lureName = self.lure end
		if not down then Disarm() end
	end)
	if WorldFrame and WorldFrame.HookScript then
		WorldFrame:HookScript("OnMouseDown", OnWorldMouseDown)
	end
	-- The client's own mouse-down event, in case the world frame doesn't hear presses.
	local global = CreateFrame("Frame")
	if pcall(global.RegisterEvent, global, "GLOBAL_MOUSE_DOWN") then
		global:SetScript("OnEvent", function(_, _, button)
			if button == "RightButton" and OverWorld() then RightPress("global") end
		end)
	end
end

---------------------------------------------------------------------------
-- Auto-loot: the journal reads the loot first (FishingJournal.lua OnLoot), then this takes it.

function F.AutoLoot()
	if not Opt().autoLoot or not GetNumLootItems or not LootSlot then return end
	if GetCVarBool and GetCVarBool("autoLootDefault") ~= IsModifiedClick("AUTOLOOTTOGGLE") then return end -- the game loots already
	for i = GetNumLootItems(), 1, -1 do
		pcall(LootSlot, i)
	end
end

---------------------------------------------------------------------------
-- The session: the journal tells us what it saw.

function F.OnCatch(items)
	if not session then NewSession() end
	session.catches = session.catches + 1
	session.sinceSkill = session.sinceSkill + 1
	for _, item in ipairs(items or {}) do
		if item.id == TASTYFISH then
			for _ = 1, item.count or 1 do table.insert(session.tasty, GetTime()) end
		end
	end
	F.Refresh()
end

function F.OnEscape()
	if not session then NewSession() end
	session.escapes = session.escapes + 1
	F.Refresh()
end

local function OnSkill()
	if not session then return end
	local rank = Skill()
	if rank and session.rank and rank > session.rank then
		session.skillups = session.skillups + (rank - session.rank)
		session.lastPoint = session.sinceSkill
		session.sinceSkill = 0
	end
	session.rank = rank or session.rank
	F.Refresh()
end

-- Catches per skill point at a rank: one until 75, then one more for every 25 points (the
-- classic rule of thumb; Forever's exact curve isn't published).
local function PerPoint(rank)
	if not rank or rank < 75 then return 1 end
	return math.ceil((rank - 75) / 25) + 1
end

---------------------------------------------------------------------------
-- The panel.

local holder, panel
local lines = {}
local LINE_KEYS = { "title", "skill", "lure", "session", "next", "derby1", "derby2" }

local function Clock(seconds)
	seconds = math.max(0, math.floor(seconds))
	if seconds >= 3600 then
		return ("%d:%02d:%02d"):format(seconds / 3600, (seconds % 3600) / 60, seconds % 60)
	end
	return ("%d:%02d"):format(seconds / 60, seconds % 60)
end

local function Slice(parent, x0, x1, y0, y1)
	local t = parent:CreateTexture(nil, "BACKGROUND")
	if ns.Art.Apply(t, "journal") then
		t:SetTexCoord((PLATE.x + x0) / ATLAS, (PLATE.x + x1) / ATLAS, (PLATE.y + y0) / ATLAS, (PLATE.y + y1) / ATLAS)
	else
		t:SetColorTexture(0.08, 0.03, 0.02, 0.9)
	end
	return t
end

-- Nine pieces: fixed corners, stretched edges and middle.
local function BuildPlate(frame)
	local e, w, h = PLATE.edge, PLATE.w, PLATE.h
	local cols = { { 0, e }, { e, w - e }, { w - e, w } }
	local rows = { { 0, e }, { e, h - e }, { h - e, h } }
	local p = {}
	for r = 1, 3 do
		for c = 1, 3 do
			p[(r - 1) * 3 + c] = Slice(frame, cols[c][1], cols[c][2], rows[r][1], rows[r][2])
		end
	end
	p[1]:SetPoint("TOPLEFT"); p[1]:SetSize(e, e)
	p[3]:SetPoint("TOPRIGHT"); p[3]:SetSize(e, e)
	p[7]:SetPoint("BOTTOMLEFT"); p[7]:SetSize(e, e)
	p[9]:SetPoint("BOTTOMRIGHT"); p[9]:SetSize(e, e)
	p[2]:SetPoint("TOPLEFT", p[1], "TOPRIGHT"); p[2]:SetPoint("BOTTOMRIGHT", p[3], "BOTTOMLEFT")
	p[8]:SetPoint("TOPLEFT", p[7], "TOPRIGHT"); p[8]:SetPoint("BOTTOMRIGHT", p[9], "BOTTOMLEFT")
	p[4]:SetPoint("TOPLEFT", p[1], "BOTTOMLEFT"); p[4]:SetPoint("BOTTOMRIGHT", p[7], "TOPRIGHT")
	p[6]:SetPoint("TOPLEFT", p[3], "BOTTOMLEFT"); p[6]:SetPoint("BOTTOMRIGHT", p[9], "TOPRIGHT")
	p[5]:SetPoint("TOPLEFT", p[1], "BOTTOMRIGHT"); p[5]:SetPoint("BOTTOMRIGHT", p[9], "TOPLEFT")
end

local function BuildPanel()
	holder = CreateFrame("Frame", "SanctuaryUIFishingPanelHolder", UIParent)
	holder:SetSize(PANEL_W, 120)
	holder:SetFrameStrata("MEDIUM")
	panel = CreateFrame("Frame", "SanctuaryUIFishingPanel", holder)
	panel:SetPoint("TOP", holder, "TOP")
	panel:SetSize(PANEL_W, 120)
	panel:EnableMouse(false)
	BuildPlate(panel)
	for i, key in ipairs(LINE_KEYS) do
		local fs = panel:CreateFontString(nil, "OVERLAY")
		fs:SetJustifyH("LEFT")
		fs:SetWordWrap(true)
		fs:SetShadowColor(0, 0, 0, 0.9)
		fs:SetShadowOffset(1, -1)
		local title = key == "title" or key == "derby1"
		ns.Fonts.Set(fs, title and "title" or "body", title and 12 or 12, "")
		fs:SetTextColor(title and 1 or 0.92, title and 0.78 or 0.86, title and 0.38 or 0.74)
		lines[key] = fs
	end
	-- The lure's time as a thin gold bar under its line.
	panel.lureBack = panel:CreateTexture(nil, "ARTWORK")
	panel.lureBack:SetColorTexture(0, 0, 0, 0.55)
	panel.lureBar = panel:CreateTexture(nil, "ARTWORK", nil, 1)
	panel.lureBar:SetColorTexture(1, 0.72, 0.25, 0.9)
	panel:Hide()
	if ns.MakeMover then
		holder.mover = ns.MakeMover(holder, "Fishing panel", function() return Opt().panelPos end,
			"Reset its position in /sanctuary > Fishing tools.")
	end
end

local function Sunday(zone)
	if not Opt().extravaganza then return false end
	local hour, weekday = 12, nil
	if GetGameTime then hour = GetGameTime() end
	if C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime then
		local ok, t = pcall(C_DateAndTime.GetCurrentCalendarTime)
		if ok and type(t) == "table" then weekday = t.weekday end
	end
	return weekday == 1 and Readable(hour) and hour >= 13 and hour < 17 and zone == "Stranglethorn Vale", hour
end

local function Show(key, text)
	local fs = lines[key]
	if text then
		fs:SetText(text)
		fs:Show()
	else
		fs:Hide()
	end
end

function F.Refresh()
	if not panel then return end
	local opt = Opt()
	local now = GetTime()
	local showing = opt.panel and (F.preview or (session and (Active() or now - lastCast < PANEL_LINGER) and PoleEquipped()))
	if not showing then
		panel:Hide()
		return
	end
	local s = session or { start = now - 600, catches = 12, escapes = 1, skillups = 2, sinceSkill = 3, lastPoint = 4, tasty = {} }
	local zone = GetRealZoneText and GetRealZoneText() or ""
	if not Readable(zone) then zone = "" end
	Show("title", ("Fishing  \194\183  %s"):format(zone ~= "" and zone or "somewhere wet"):upper())
	local rank, cap, bonus = Skill()
	if rank then
		Show("skill", ("Skill %d of %d%s"):format(rank, cap, (bonus or 0) > 0 and ("  (+%d, %d in all)"):format(bonus, rank + bonus) or ""))
	else
		Show("skill", "You haven't learned Fishing yet.")
	end
	local left = LureLeft()
	if left then
		Show("lure", ("%s  %s"):format(lureName or "Lure", Clock(left)))
	elseif F.preview and not session then
		Show("lure", "Bright Baubles  7:12")
		left = 432
	else
		local best = opt.autoLure and BestLure()
		Show("lure", best and ("No lure. Double-click puts on %s."):format(best[1]) or "No lure on the pole.")
	end
	local minutes = math.max(1, (now - s.start) / 60)
	Show("session", ("This session: %d fish, %d an hour, %d got away%s"):format(s.catches, s.catches * 60 / minutes, s.escapes,
		s.skillups > 0 and (", +%d skill"):format(s.skillups) or ""))
	if rank and rank < (cap or 300) then
		local per = PerPoint(rank)
		Show("next", ("Next skill point: about %d catch%s%s"):format(math.max(1, per - s.sinceSkill), per - s.sinceSkill == 1 and "" or "es",
			s.lastPoint and (" (last took %d)"):format(s.lastPoint) or ""))
	elseif rank then
		Show("next", "Skill capped. Find the next rank (the journal's Route).")
	else
		Show("next", nil)
	end
	local sunday, hour = Sunday(zone)
	if sunday or F.preview then
		local count = ItemCount and ItemCount(TASTYFISH) or 0
		if not Readable(count) then count = 0 end
		Show("derby1", ("Extravaganza  \194\183  Tastyfish %d/40"):format(F.preview and not sunday and 17 or count):upper())
		local minute = GetGameTime and select(2, GetGameTime()) or 0
		local race = (16 - (hour or 16)) * 3600 - (minute or 0) * 60
		local oldest = s.tasty[1] and (TASTY_ROT - (now - s.tasty[1]))
		Show("derby2", ("%s%s"):format(race > 0 and ("Race ends in about %s"):format(Clock(race)) or "The race is over; Jang still buys",
			oldest and ("  \194\183  oldest rots in %s"):format(Clock(oldest)) or ""))
	else
		Show("derby1", nil)
		Show("derby2", nil)
	end

	-- Lay the shown lines down the plate.
	local y = -PAD.top
	for _, key in ipairs(LINE_KEYS) do
		local fs = lines[key]
		if fs:IsShown() then
			if key == "derby1" then y = y - 5 end
			fs:ClearAllPoints()
			fs:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD.x, y)
			fs:SetWidth(PANEL_W - 2 * PAD.x)
			y = y - (fs:GetStringHeight() or 13) - 3
			if key == "lure" then
				panel.lureBack:ClearAllPoints()
				panel.lureBack:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD.x, y - 1)
				panel.lureBack:SetSize(PANEL_W - 2 * PAD.x, 3)
				local frac = left and math.min(1, left / 600) or 0
				panel.lureBar:ClearAllPoints()
				panel.lureBar:SetPoint("TOPLEFT", panel.lureBack, "TOPLEFT")
				panel.lureBar:SetSize(math.max(0.01, (PANEL_W - 2 * PAD.x) * frac), 3)
				panel.lureBar:SetColorTexture(left and left < LURE_WARN and 1 or 1, left and left < LURE_WARN and 0.3 or 0.72, 0.2, 0.9)
				panel.lureBack:SetShown(left ~= nil)
				panel.lureBar:SetShown(left ~= nil)
				y = y - 7
			end
		end
	end
	panel:SetSize(PANEL_W, -y + PAD.bottom)
	holder:SetSize(PANEL_W, -y + PAD.bottom) -- the mover covers the panel as it is
	panel:Show()
end

function F.Place()
	if not holder then return end
	local opt = Opt()
	holder:SetScale(opt.panelScale or 1)
	holder:ClearAllPoints()
	local pos = opt.panelPos
	if pos.moved and ns.MovedPoint then
		holder:SetPoint("CENTER", UIParent, "BOTTOMLEFT", ns.MovedPoint(holder, pos))
	else
		holder:SetPoint("BOTTOM", UIParent, "BOTTOM", -320, 250)
	end
	if holder.mover then holder.mover:SetShown(not ns.DB().locked) end
end

function F.SetPreview(on)
	F.preview = on and true or nil
	F.Refresh()
end

function F.ResetPosition()
	Opt().panelPos.moved = false
	F.Place()
end

---------------------------------------------------------------------------
-- Fishing mode: the console fades back while you fish.

local fadeNow = 1

local function FadeTarget()
	local opt = Opt()
	if not opt.fade or not ns.Cluster then return 1 end
	if InCombatLockdown() or not Active() then return 1 end
	if ns.Cluster:IsMouseOver() then return 1 end
	return opt.fadeAlpha or 0.25
end

local function StepFade(dt)
	if not ns.Cluster then return end
	local target = FadeTarget()
	if math.abs(fadeNow - target) < 0.01 then
		if fadeNow ~= target then
			fadeNow = target
			ns.Cluster:SetAlpha(fadeNow)
		end
		return
	end
	-- Back up fast (danger), down slowly.
	local speed = target > fadeNow and 4 or 1.2
	fadeNow = fadeNow + math.max(-dt * speed, math.min(dt * speed, target - fadeNow))
	ns.Cluster:SetAlpha(fadeNow)
end

---------------------------------------------------------------------------
-- Lure warning.

local warned = false

local function CheckLure()
	local left = LureLeft()
	if not left or left > LURE_WARN + 1 then
		if left then warned = false end
		return
	end
	if Opt().lureWarn and not warned and (Active() or (session and GetTime() - lastCast < 60)) then
		warned = true
		if UIErrorsFrame then UIErrorsFrame:AddMessage("Your lure fades in a minute.", 1, 0.78, 0.38) end
		if PlaySound then pcall(PlaySound, (SOUNDKIT and SOUNDKIT.ALARM_CLOCK_WARNING_3) or 12889, "SFX") end
	end
end

---------------------------------------------------------------------------

function F.ApplySettings()
	F.Place()
	F.Refresh()
	if not Opt().fade and ns.Cluster and fadeNow ~= 1 then
		fadeNow = 1
		ns.Cluster:SetAlpha(1)
	end
	if not Opt().doubleClick then Disarm() end
end

function F.Init()
	ns.Art.Require("journal")
	BuildCasting()
	BuildPanel()
	F.Place()
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_FAILED" }) do
		if not pcall(events.RegisterUnitEvent, events, event, "player") then pcall(events.RegisterEvent, events, event) end
	end
	for _, event in ipairs({ "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
		"UNIT_INVENTORY_CHANGED", "ZONE_CHANGED_NEW_AREA" }) do
		pcall(events.RegisterEvent, events, event)
	end
	events:SetScript("OnEvent", function(_, event, unit, _, spellID)
		if event == "UNIT_SPELLCAST_FAILED" then
			if unit == "player" and Readable(spellID) then
				local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
				if name == FishingName() then Trace("the cast failed") end
			end
			return
		end
		if event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
			if unit ~= "player" or not Readable(spellID) then return end
			local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
			if not Readable(name) and GetSpellInfo then name = GetSpellInfo(spellID) end
			if name ~= FishingName() then return end
			if event == "UNIT_SPELLCAST_CHANNEL_START" then
				if not session or GetTime() - lastCast > SESSION_IDLE then NewSession() end
				if armed or GetTime() - lastPress < 2 then Trace("cast started") end
				channeling = true
			else
				channeling = false
			end
			lastCast = GetTime()
			F.Refresh()
		elseif event == "SKILL_LINES_CHANGED" or event == "CHAT_MSG_SKILL" then
			OnSkill()
		elseif event == "PLAYER_REGEN_DISABLED" then
			-- In combat: the console back at once, and no binding left on the right button.
			armed = false
			if ns.Cluster then
				fadeNow = 1
				ns.Cluster:SetAlpha(1)
			end
		else
			F.Refresh()
		end
	end)
	-- The panel's clocks, the fade and the lure warning.
	local tick = 0
	events:SetScript("OnUpdate", function(_, dt)
		StepFade(dt)
		tick = tick + dt
		if tick >= 1 then
			tick = 0
			CheckLure()
			if panel:IsShown() or session then F.Refresh() end
		end
	end)
end
