SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.Swing = ns.Swing or {}

-- Weapon swing timers: a bar per weapon (main hand, off hand, ranged) that fills while the next
-- auto attack winds up, in the D3 progress bar the target frame's cast bar uses.
--
-- Forever has no combat log for addons, but it does tell the UI about your own swings:
-- PLAYER_SWING (swingDuration, swingType) fires as each swing lands, with the time to the next
-- one, and C_SwingTimer reports whether your target is in reach (Blizzard_SwingTimer runs on the
-- same two). Neither is secret. A haste change mid-swing (UNIT_ATTACK_SPEED) stretches or
-- shortens what's left of it, as WeaponSwingTimer does, while the attack speed is readable.

local TYPES = (Enum and Enum.PlayerSwingType) or { MainHand = 0, OffHand = 1, Ranged = 2 }

-- tint: the colour of the cast fill's grey copy; main hand keeps D3's own orange.
local BARS = {
	{ key = "mainHand", swingType = TYPES.MainHand, slot = INVSLOT_MAINHAND or 16, slotName = "MainHandSlot", label = "Main hand" },
	{ key = "offHand", swingType = TYPES.OffHand, slot = INVSLOT_OFFHAND or 17, slotName = "SecondaryHandSlot", label = "Off hand", tint = { 1, 0.8, 0.4 } },
	{ key = "ranged", swingType = TYPES.Ranged, slot = INVSLOT_RANGED or 18, slotName = "RangedSlot", label = "Ranged", tint = { 0.6, 1, 0.45 } },
}
ns.Swing.BARS = BARS

-- Skills that start the main-hand swing over without the client sending a swing for it: the
-- "next melee" attacks (Heroic Strike, Cleave, Maul, Raptor Strike) and Slam, as WeaponSwingTimer
-- lists them, plus Shield Bash, seen resetting it on Forever. Rank 1 IDs; every rank matches by
-- name. Options > Swing timer adds more by name or ID.
local RESETS = {
	WARRIOR = { 78, 845, 1464, 72 },
	DRUID = { 6807 },
	HUNTER = { 2973 },
}
ns.Swing.RESETS = RESETS

-- Preview swing lengths, looping.
local PREVIEW = { mainHand = 2.6, offHand = 1.9, ranged = 3.0 }

local OUT_OF_RANGE_ALPHA = 0.4
local ICON_GAP = 4

local function Opt()
	return ns.DB().swing
end

local function Secret(value)
	return issecretvalue and issecretvalue(value)
end

local byType = {}
for _, info in ipairs(BARS) do byType[info.swingType] = info end

---------------------------------------------------------------------------
-- What's equipped. UnitAttackSpeed is secret while unit stats are restricted; the last
-- readable answer stands in.

local speeds = { mainHand = 2, offHand = nil, ranged = nil }

local function ReadSpeeds()
	if not UnitAttackSpeed then return end
	local mh, oh, ranged = UnitAttackSpeed("player")
	if not Secret(mh) then speeds.mainHand = mh end
	if not Secret(oh) then speeds.offHand = oh end
	if not Secret(ranged) then speeds.ranged = ranged end
	-- Clients without a ranged speed there: an item in the ranged slot is the answer.
	if ranged == nil and GetInventoryItemID then
		local id = GetInventoryItemID("player", INVSLOT_RANGED or 18)
		speeds.ranged = (Secret(id) or id ~= nil) and 1 or nil
	end
end

local function HasWeapon(info)
	if info.key == "mainHand" then return true end -- fists swing too
	local speed = speeds[info.key]
	return speed ~= nil and speed > 0
end

---------------------------------------------------------------------------
-- State

local holder
local inCombat = false
-- by key: start, duration (the swing running), speed (attack speed it started at),
-- swung (a swing seen this fight), outOfRange
local state = { mainHand = {}, offHand = {}, ranged = {} }

local function Active(s, now)
	return s.start ~= nil and now < s.start + s.duration
end

local function Unlocked()
	return not ns.DB().locked and not InCombatLockdown()
end

local function Previewing()
	return ns.Swing.preview or (holder and holder.unlocked)
end

local function Wanted(info)
	local opt = Opt()
	if not opt.enabled or not opt[info.key] then return false end
	if Previewing() then return true end
	if not HasWeapon(info) then return false end
	local s = state[info.key]
	local active = Active(s, GetTime())
	if opt.show == "always" then return true end
	if opt.show == "swinging" then return active end
	-- In combat: once this weapon has swung, so casters who never melee see nothing.
	return active or (inCombat and s.swung) or false
end

---------------------------------------------------------------------------
-- Bars

local function MakeBar(parent, info)
	local piece = ns.Art.UNIT.cast
	local bar = CreateFrame("Frame", nil, parent)
	bar:EnableMouse(false)
	bar.info = info
	bar.fill = CreateFrame("StatusBar", nil, bar)
	bar.fill:SetMinMaxValues(0, 1)
	bar.fill:SetValue(0)
	local white = info.tint and ns.Art.Path("castFillWhite")
	local fillPath = white or ns.Art.Path("castFill")
	bar.fill:SetStatusBarTexture(fillPath or "Interface\\Buttons\\WHITE8X8")
	local tex = bar.fill:GetStatusBarTexture()
	if not fillPath then
		local c = info.tint or { 1, 0.45, 0.1 }
		bar.fill:SetStatusBarColor(c[1], c[2], c[3], 1)
	elseif info.tint then
		-- The grey copy takes the tint at full strength; before a client restart has loaded it,
		-- the orange greyed in the client stands in (duller).
		if not white then tex:SetDesaturated(true) end
		bar.fill:SetStatusBarColor(info.tint[1], info.tint[2], info.tint[3], 1)
	end
	local bg = bar.fill:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.02, 0.015, 0.01, 0.95)

	-- The ember on the leading edge while the swing winds up (as the target's health bar).
	local glowPath = ns.Art.Path("unitGlow")
	if glowPath then
		local edge = CreateFrame("Frame", nil, bar.fill)
		edge:SetAllPoints(bar.fill)
		if edge.SetClipsChildren then edge:SetClipsChildren(true) end
		edge:SetFrameLevel(bar.fill:GetFrameLevel() + 1)
		local function Sprite(u, sub)
			local t = edge:CreateTexture(nil, "OVERLAY", nil, sub)
			t:SetTexture(glowPath)
			t:SetTexCoord(u, u + 18 / 64, 0, 1)
			t:SetBlendMode("ADD")
			t:SetSize(18, piece.bar[4] + 4)
			t:SetPoint("RIGHT", tex, "RIGHT", 4, 0)
			return t
		end
		local bloom, core = Sprite(0, 1), Sprite(0.5, 2)
		local c = info.tint or { 1, 0.42, 0.1 }
		bloom:SetVertexColor(c[1], c[2] * 0.6, c[3] * 0.4)
		core:SetVertexColor(1, 0.92, 0.62)
		bar.edge = edge
	end

	bar.art = CreateFrame("Frame", nil, bar)
	bar.art:SetPoint("TOPLEFT")
	bar.art:SetFrameLevel(bar.fill:GetFrameLevel() + 3)

	-- The weapon's icon at the bar's left, in a dark frame.
	bar.iconFrame = CreateFrame("Frame", nil, bar)
	bar.iconFrame:SetFrameLevel(bar.art:GetFrameLevel())
	local border = bar.iconFrame:CreateTexture(nil, "BACKGROUND")
	border:SetPoint("TOPLEFT", -1, 1)
	border:SetPoint("BOTTOMRIGHT", 1, -1)
	border:SetColorTexture(0, 0, 0, 0.9)
	bar.icon = bar.iconFrame:CreateTexture(nil, "ARTWORK")
	bar.icon:SetAllPoints()
	bar.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	bar.time = bar.art:CreateFontString(nil, "OVERLAY")
	bar.time:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
	bar.time:SetPoint("RIGHT", bar.fill, "RIGHT", -3, 0)
	bar.time:SetTextColor(1, 0.92, 0.78)
	return bar
end

local function SetIcon(bar)
	local icon = GetInventoryItemTexture and GetInventoryItemTexture("player", bar.info.slot)
	if Secret(icon) or not icon then
		-- No weapon (fists): the empty slot's own art.
		icon = GetInventorySlotInfo and select(2, GetInventorySlotInfo(bar.info.slotName))
	end
	bar.icon:SetTexture(icon or 136243)
end

-- Fill, ember, time and range dimming for one bar.
local function Draw(bar, now)
	local info = bar.info
	local s = state[info.key]
	local opt = Opt()
	local start, duration = s.start, s.duration
	if Previewing() and not Active(s, now) then
		local length = PREVIEW[info.key]
		start, duration = now - (now - (holder.previewSince or now)) % length, length
	end
	local running = start ~= nil and now < start + duration
	local progress = running and math.min(1, math.max(0, (now - start) / duration)) or 1
	bar.fill:SetValue(progress)
	if bar.edge then bar.edge:SetShown(running and progress > 0.02) end
	if running and opt.time then
		bar.time:SetFormattedText("%.1f", start + duration - now)
	else
		bar.time:SetText("")
	end
	-- Out of reach shows once the swing in hand is done (Blizzard waits the same way).
	local far = opt.rangeFade and s.outOfRange and not running and not Previewing()
	bar:SetAlpha(far and OUT_OF_RANGE_ALPHA or 1)
	if far then
		bar.icon:SetVertexColor(1, 0.35, 0.3)
	else
		bar.icon:SetVertexColor(1, 1, 1)
	end
end

---------------------------------------------------------------------------
-- Layout: the bars stacked, main hand on top. Not secure, so it can change in combat as bars
-- come and go; the holder keeps the size of every enabled bar so its mover stays put.

local function Pitch(opt)
	return ns.Art.UNIT.cast[4] + opt.spacing
end

function ns.Swing.Layout()
	if not holder then return end
	local opt = Opt()
	local piece = ns.Art.UNIT.cast
	local width = math.max(80, opt.width)
	local iconSize = opt.icons and (piece[4] + math.max(2, math.min(opt.spacing, 8))) or 0
	local iconSpace = opt.icons and (iconSize + ICON_GAP) or 0
	holder:SetScale(ns.Art.D3Scale(opt.scale))
	local enabled = 0
	for _, bar in ipairs(holder.bars) do
		if opt[bar.info.key] then enabled = enabled + 1 end
		local extra = ns.Art.DrawSliced(bar.art, "cast", width, 1)
		bar:SetSize(bar.art:GetWidth(), piece[4])
		bar.fill:ClearAllPoints()
		bar.fill:SetPoint("TOPLEFT", bar, "TOPLEFT", piece.bar[1], -piece.bar[2])
		bar.fill:SetSize(piece.bar[3] + extra, piece.bar[4])
		bar.iconFrame:SetSize(math.max(1, iconSize), math.max(1, iconSize))
		bar.iconFrame:ClearAllPoints()
		bar.iconFrame:SetPoint("RIGHT", bar, "LEFT", -ICON_GAP, 0)
		bar.iconFrame:SetShown(opt.icons)
	end
	local barW = holder.bars[1]:GetWidth()
	local pitch = Pitch(opt)
	holder:SetSize(barW + iconSpace, math.max(1, enabled) * pitch - opt.spacing)
	holder.iconSpace = iconSpace
	holder:ClearAllPoints()
	if opt.moved then
		holder:SetPoint("CENTER", UIParent, "BOTTOMLEFT", ns.MovedPoint(holder, opt))
	else
		-- Under your character, where the eye already is in a fight.
		holder:SetPoint("CENTER", UIParent, "CENTER", 0, -150)
	end
	ns.Swing.Stack()
end

-- Shown bars from the top down; the rest hide.
function ns.Swing.Stack()
	if not holder then return end
	local opt = Opt()
	local pitch = Pitch(opt)
	local n = 0
	for _, bar in ipairs(holder.bars) do
		if Wanted(bar.info) then
			bar:ClearAllPoints()
			bar:SetPoint("TOPLEFT", holder, "TOPLEFT", holder.iconSpace or 0, -n * pitch)
			n = n + 1
			if not bar:IsShown() then
				SetIcon(bar)
				bar:Show()
			end
		else
			bar:Hide()
		end
	end
	holder.any = n > 0
end

---------------------------------------------------------------------------
-- Range checks, only for the weapons with a bar.

local rangeOn = {}

local function UpdateRangeChecks()
	local api = C_SwingTimer
	if not api or not api.EnableRangeCheck then return end
	local opt = Opt()
	for _, info in ipairs(BARS) do
		local want = (opt.enabled and opt[info.key] and opt.rangeFade and HasWeapon(info)) and true or false
		if rangeOn[info.key] ~= want then
			if pcall(api.EnableRangeCheck, info.swingType, want) then
				rangeOn[info.key] = want
			end
		end
	end
end

local function RefreshRange()
	local api = C_SwingTimer
	for _, info in ipairs(BARS) do
		local s = state[info.key]
		s.outOfRange = nil
		if rangeOn[info.key] and api and api.IsTargetWithinSwingRange then
			local ok, inRange = pcall(api.IsTargetWithinSwingRange, info.swingType)
			-- Nil means no check could be made, never out of range.
			if ok and not Secret(inRange) and inRange == false then s.outOfRange = true end
		end
	end
end

---------------------------------------------------------------------------
-- Swing resets

local GetSpellName = (C_Spell and C_Spell.GetSpellName) or function(id)
	return GetSpellInfo and (GetSpellInfo(id)) or nil
end

local resetIDs, resetNames = {}, {}

local function AddReset(id)
	resetIDs[id] = true
	local name = GetSpellName(id)
	if name and not Secret(name) then resetNames[name:lower()] = true end
end

-- The class's own list and the names or IDs typed in the options, commas between.
local function BuildResets()
	wipe(resetIDs)
	wipe(resetNames)
	local _, class = UnitClass("player")
	for _, id in ipairs(RESETS[class] or {}) do AddReset(id) end
	for token in (Opt().resets or ""):gmatch("[^,]+") do
		token = token:match("^%s*(.-)%s*$")
		local id = tonumber(token)
		if id then
			AddReset(id)
		elseif token ~= "" then
			resetNames[token:lower()] = true
		end
	end
end

local function IsReset(spellID)
	if spellID == nil or Secret(spellID) then return false end
	if resetIDs[spellID] then return true end
	local name = GetSpellName(spellID)
	return name ~= nil and not Secret(name) and resetNames[name:lower()] or false
end

-- The main hand starts a full swing now, at the speed it has now.
local function ResetMainHand()
	ReadSpeeds()
	local s = state.mainHand
	local speed = speeds.mainHand
	if not speed or speed <= 0 then speed = s.duration end
	if not speed or speed <= 0 then return end
	s.start, s.duration, s.speed = GetTime(), speed, speeds.mainHand
	s.swung = true
	s.outOfRange = nil
	ns.Swing.Stack()
end

---------------------------------------------------------------------------
-- Events

local function OnSwing(duration, swingType)
	local info = byType[swingType]
	if not info or Secret(duration) or Secret(swingType) or not duration or duration <= 0 then return end
	local s = state[info.key]
	s.start, s.duration = GetTime(), duration
	s.speed = speeds[info.key]
	s.swung = true
	-- A swing means the target is in reach, whatever the last range report said.
	s.outOfRange = nil
	ns.Swing.Stack()
end

-- Haste mid-swing: what's left of it scales with the new speed.
local function OnSpeed()
	local old = { mainHand = speeds.mainHand, offHand = speeds.offHand, ranged = speeds.ranged }
	ReadSpeeds()
	local now = GetTime()
	for _, info in ipairs(BARS) do
		local s = state[info.key]
		local was, speed = s.speed or old[info.key], speeds[info.key]
		if Active(s, now) and was and speed and was > 0 and speed > 0 and was ~= speed then
			local left = (s.start + s.duration - now) * speed / was
			local done = now - s.start
			s.duration = done + left
			s.speed = speed
		end
	end
	UpdateRangeChecks()
	ns.Swing.Stack()
end

local function OnEquip()
	ReadSpeeds()
	for _, info in ipairs(BARS) do
		-- A weapon taken off ends its swing.
		if not HasWeapon(info) then
			state[info.key].start = nil
			state[info.key].swung = nil
		end
	end
	UpdateRangeChecks()
	if holder then
		for _, bar in ipairs(holder.bars) do SetIcon(bar) end
	end
	ns.Swing.Stack()
end

function ns.Swing.UpdateMovers(unlocked)
	if not holder then return end
	local show = unlocked and Opt().enabled and true or false
	holder.unlocked = show
	if show then holder.previewSince = holder.previewSince or GetTime() end
	ns.Swing.mover:SetShown(show)
	ns.Swing.Stack()
end

function ns.Swing.ResetPosition()
	local opt = Opt()
	opt.moved, opt.mx, opt.my = false, 0, 0
	ns.Refresh()
end

-- Session-only: every enabled bar on looping fake swings.
function ns.Swing.SetPreview(on)
	ns.Swing.preview = on and true or nil
	if holder then holder.previewSince = GetTime() end
	ns.Swing.Stack()
	ns.Print(on and "swing timer preview on (/sanctuary swing again to turn off)" or "swing timer preview off")
end

function ns.Swing.ApplySettings()
	if not holder then return end
	BuildResets()
	UpdateRangeChecks()
	ns.Swing.Layout()
end

function ns.Swing.Supported()
	return C_SwingTimer ~= nil
end

function ns.Swing.Init()
	holder = CreateFrame("Frame", "SanctuaryUISwingTimer", UIParent)
	holder:SetFrameStrata("MEDIUM")
	holder:EnableMouse(false)
	holder.bars = {}
	for i, info in ipairs(BARS) do
		holder.bars[i] = MakeBar(holder, info)
		holder.bars[i]:Hide()
	end
	ns.Swing.holder = holder
	ns.Swing.mover = ns.MakeMover(holder, "Swing timer", Opt, "Reset its position in /sanctuary > Swing timer.")
	ReadSpeeds()

	holder:SetScript("OnUpdate", function(self)
		if not self.any then return end
		local now = GetTime()
		local restack = false
		for _, bar in ipairs(self.bars) do
			if bar:IsShown() then
				Draw(bar, now)
				-- A bar kept only by its running swing (after the fight, or "while swinging") goes
				-- when that swing is done.
				if not Wanted(bar.info) then restack = true end
			end
		end
		if restack then ns.Swing.Stack() end
	end)

	local events = CreateFrame("Frame")
	local list = {
		"PLAYER_SWING", "PLAYER_SWING_RANGE_UPDATE", "PLAYER_TARGET_CHANGED", "PLAYER_REGEN_DISABLED",
		"PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "PLAYER_EQUIPMENT_CHANGED",
	}
	for _, event in ipairs(list) do
		pcall(events.RegisterEvent, events, event)
	end
	pcall(events.RegisterUnitEvent, events, "UNIT_ATTACK_SPEED", "player")
	pcall(events.RegisterUnitEvent, events, "UNIT_INVENTORY_CHANGED", "player")
	pcall(events.RegisterUnitEvent, events, "UNIT_SPELLCAST_SUCCEEDED", "player")
	events:SetScript("OnEvent", function(_, event, ...)
		if event == "PLAYER_SWING" then
			OnSwing(...)
		elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
			local unit, _, spellID = ...
			if unit == "player" and Opt().enabled and IsReset(spellID) then ResetMainHand() end
		elseif event == "PLAYER_SWING_RANGE_UPDATE" then
			local swingType, isInRange, checksRange = ...
			local info = byType[swingType]
			if info and not Secret(isInRange) and not Secret(checksRange) then
				state[info.key].outOfRange = (checksRange and not isInRange) or nil
			end
		elseif event == "PLAYER_TARGET_CHANGED" then
			RefreshRange()
		elseif event == "PLAYER_REGEN_DISABLED" then
			inCombat = true
			ns.Swing.Stack()
		elseif event == "PLAYER_REGEN_ENABLED" then
			inCombat = false
			for _, s in pairs(state) do s.swung = nil end
			ns.Swing.Stack()
		elseif event == "UNIT_ATTACK_SPEED" then
			OnSpeed()
		else
			OnEquip()
			if event == "PLAYER_ENTERING_WORLD" then
				BuildResets()
				local affecting = UnitAffectingCombat and UnitAffectingCombat("player")
				inCombat = not Secret(affecting) and affecting and true or false
				RefreshRange()
			end
		end
	end)
	UpdateRangeChecks()
	ns.Swing.Layout()
end
