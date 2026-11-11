SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.Portraits = ns.Portraits or {}

-- D3's party portraits, top left: your pet, and (optionally) you above it. Your own portrait
-- carries no health bar (the globe is your health); its bar slot holds your level on D3's plaque. Each is the D3 party frame (a dark
-- well with a bust above a small health bar), drawn gold while that unit is your target, as D3
-- marks the selected party member. They replace what hiding Blizzard's player frame took away:
-- the unit menu on right-click (leave group, loot, raid markers), the leader, combat, resting
-- and raid marker icons, and the pet's health (and happiness, where the client has it).
--
-- The portraits are secure unit buttons (left-click targets, right-click opens the menu). They
-- sit on a plain anchor that moves with the mover; the pet's shows and hides by RegisterUnitWatch.

local PIECE = "party"
local SIZE_K = 1.0 -- piece pixels to UI units before the user's scale
local MODEL_H = 58 -- bust height in piece pixels, rising out of the well above the bar
local PET_K = 0.8 -- the pet's portrait, relative to yours
local GAP = 10

local function Opt()
	return ns.DB().portraits
end

-- Test mode (Options > Portraits > Preview): both portraits show, the pet's drawn from you
-- when you have no pet, so they can be judged in game.
local function Shown(button)
	if ns.Portraits.preview and button.unit == "pet" and not UnitExists("pet") then
		return "player"
	end
	return button.unit
end

local function Secret(value)
	return issecretvalue and issecretvalue(value)
end

local function Fill(bar, value, maxValue)
	if maxValue ~= nil and not Secret(maxValue) then
		bar:SetMinMaxValues(0, maxValue)
	else
		pcall(bar.SetMinMaxValues, bar, 0, ns.Or(maxValue, 1))
	end
	if not pcall(bar.SetValue, bar, ns.Or(value, 0)) then
		bar:SetValue(0)
	end
end

local function ShowTooltip(self)
	if GameTooltip:IsForbidden() then return end
	if GameTooltip_SetDefaultAnchor then
		GameTooltip_SetDefaultAnchor(GameTooltip, self)
	else
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
	end
	GameTooltip:SetUnit(self.unit)
	GameTooltip:AddLine("Right-click for options", 0.6, 0.6, 0.6)
	GameTooltip:Show()
end

local function MakePortrait(parent, unit, name, k, withHealth)
	local piece = ns.Art.UNIT[PIECE]
	local w, h = piece[3] * k, piece[4] * k
	local top = (MODEL_H - piece.bar[2]) * k -- how far the bust rises above the piece

	local button = CreateFrame("Button", name, parent, "SecureUnitButtonTemplate")
	button.unit = unit
	button.k = k
	button:SetSize(w, h + top)
	button:SetAttribute("unit", unit)
	button:SetAttribute("*type1", "target")
	button:SetAttribute("*type2", "togglemenu")
	button:RegisterForClicks("AnyUp")
	button:SetScript("OnEnter", ShowTooltip)
	button:SetScript("OnLeave", GameTooltip_Hide)

	-- The well's dark gradient continues up behind the bust.
	local well = piece.well
	local back = button:CreateTexture(nil, "BACKGROUND")
	back:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", well[1] * k, (piece[4] - well[2] - well[4]) * k)
	back:SetSize(well[3] * k, top + well[4] * k * 0.4)
	back:SetColorTexture(0, 0, 0, 1)
	if back.SetGradient and CreateColor then
		pcall(back.SetGradient, back, "VERTICAL", CreateColor(0, 0, 0, 0.9), CreateColor(0, 0, 0, 0))
	end

	-- The bust: a 3D portrait, falling back to the flat portrait texture.
	local model = CreateFrame("PlayerModel", nil, button)
	model:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", well[1] * k, (piece[4] - piece.bar[2]) * k)
	model:SetSize(well[3] * k, MODEL_H * k)
	button.model = model
	local flat = button:CreateTexture(nil, "ARTWORK")
	flat:SetSize(well[3] * k * 0.8, well[3] * k * 0.8)
	flat:SetPoint("BOTTOM", model, "BOTTOM", 0, 2)
	flat:Hide()
	button.flat = flat

	-- Health in the frame's bar slot, the frame art above it.
	local health = CreateFrame("StatusBar", nil, button)
	health:SetPoint("TOPLEFT", button, "BOTTOMLEFT", piece.bar[1] * k, (piece[4] - piece.bar[2]) * k)
	health:SetSize(piece.bar[3] * k, piece.bar[4] * k)
	-- A StatusBar owns its fill's texcoords, so the fill is a whole file, not an atlas piece.
	health:SetStatusBarTexture(ns.Art.Path("unitFillWhite") or "Interface\\Buttons\\WHITE8X8")
	health:SetStatusBarColor(0.2, 0.72, 0.18, 1) -- D3 party green
	local healthBg = health:CreateTexture(nil, "BACKGROUND")
	healthBg:SetAllPoints()
	healthBg:SetColorTexture(0.03, 0.02, 0.02, 0.9)
	button.health = health
	if not withHealth then
		-- Just the dark slot (for the level), no fill.
		health:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
		health:SetStatusBarColor(0, 0, 0, 0)
		button.noHealth = true
	end

	local art = CreateFrame("Frame", nil, button)
	art:SetAllPoints()
	art:SetFrameLevel(health:GetFrameLevel() + 2)
	local frame = art:CreateTexture(nil, "ARTWORK")
	frame:SetPoint("BOTTOMLEFT")
	frame:SetSize(w, h)
	if ns.Art.Apply(frame, "unitFrames") then
		frame:SetTexCoord(ns.Art.UnitTexCoord(PIECE))
	else
		frame:SetColorTexture(0, 0, 0, 0)
	end
	button.frame = frame

	-- Status icons around the bust.
	local icon = 14 * k
	button.leader = art:CreateTexture(nil, "OVERLAY")
	button.leader:SetSize(icon, icon)
	button.leader:SetPoint("TOPLEFT", model, "TOPLEFT", -icon * 0.3, 0)
	button.leader:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
	button.leader:Hide()

	button.state = art:CreateTexture(nil, "OVERLAY")
	button.state:SetSize(icon * 1.3, icon * 1.3)
	button.state:SetPoint("TOPRIGHT", model, "TOPRIGHT", icon * 0.4, icon * 0.2)
	button.state:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
	button.state:Hide()

	button.raid = art:CreateTexture(nil, "OVERLAY")
	button.raid:SetSize(icon * 1.2, icon * 1.2)
	button.raid:SetPoint("BOTTOM", model, "TOP", 0, -icon * 0.4)
	button.raid:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
	button.raid:Hide()

	button.happiness = art:CreateTexture(nil, "OVERLAY")
	button.happiness:SetSize(icon * 1.2, icon * 1.2)
	button.happiness:SetPoint("LEFT", frame, "RIGHT", -2 * k, -h * 0.15)
	button.happiness:SetTexture("Interface\\PetPaperDollFrame\\UI-PetHappiness")
	button.happiness:Hide()

	if withHealth then
		button.level = art:CreateFontString(nil, "OVERLAY")
		ns.Fonts.Set(button.level, "body", math.floor(10 * k + 0.5), "OUTLINE")
		button.level:SetPoint("CENTER", health, "CENTER", 0, 0)
		button.level:SetTextColor(0.95, 0.88, 0.7)
	else
		-- Your portrait: no health, so the bar slot holds D3's level plaque instead, bronze
		-- like the frame and gold with it while you're your own target.
		healthBg:Hide()
		button.badge = ns.Art.LevelBadge(art, 76 * k, 19 * k, "bronze", math.floor(10 * k + 0.5))
		button.badge:SetPoint("CENTER", health, "CENTER", 0, 0)
		button.badge:SetFrameLevel(art:GetFrameLevel() + 1)
		button.level = button.badge.text
	end

	return button
end

-- The 3D bust. Models load after SetUnit returns, so there is nothing to check here; the flat
-- portrait (a round render on black) is only for units out of view, cropped to its middle.
local function UpdateModel(button)
	local unit = Shown(button)
	if not UnitExists(unit) then return end
	local model = button.model
	local visible = UnitIsVisible(unit)
	if not Secret(visible) and visible then
		model:SetUnit(unit)
		pcall(model.SetPortraitZoom, model, 1)
		model:Show()
		button.flat:Hide()
	else
		model:Hide()
		SetPortraitTexture(button.flat, unit)
		button.flat:SetTexCoord(0.15, 0.85, 0.15, 0.85)
		button.flat:Show()
	end
end

local function UpdateHealth(button)
	local unit = Shown(button)
	if button.noHealth or not UnitExists(unit) then return end
	Fill(button.health, UnitHealth(unit), UnitHealthMax(unit))
	local dead = UnitIsDeadOrGhost(unit)
	if Secret(dead) then dead = false end
	button.health:SetStatusBarColor(dead and 0.4 or 0.2, dead and 0.4 or 0.72, dead and 0.4 or 0.18, 1)
end

local function UpdateIcons(button)
	local unit = Shown(button)
	if not UnitExists(unit) then return end
	-- Gold frame while this unit is your target.
	local targeted = UnitIsUnit("target", unit)
	if Secret(targeted) then targeted = false end
	if ns.Art.Path("unitFrames") then
		button.frame:SetTexCoord(ns.Art.UnitTexCoord(targeted and "partyGold" or PIECE))
	end
	if button.badge then
		button.badge:SetKind(targeted and "gold" or "bronze")
	end

	local leader = UnitIsGroupLeader and UnitIsGroupLeader(unit)
	if Secret(leader) then leader = false end
	button.leader:SetShown(leader and true or false)

	if button.unit == "player" then
		if UnitAffectingCombat("player") then
			button.state:SetTexCoord(0.5, 1, 0, 0.5)
			button.state:Show()
		elseif IsResting() then
			button.state:SetTexCoord(0, 0.5, 0, 0.421875)
			button.state:Show()
		else
			button.state:Hide()
		end
	else
		button.state:Hide()
	end

	local index = GetRaidTargetIndex and GetRaidTargetIndex(unit)
	if not Secret(index) and index and SetRaidTargetIconTexture then
		SetRaidTargetIconTexture(button.raid, index)
		button.raid:Show()
	else
		button.raid:Hide()
	end

	local happiness = button.unit == "pet" and unit == "pet" and GetPetHappiness and GetPetHappiness()
	if not Secret(happiness) and happiness then
		-- UI-PetHappiness: unhappy, content, happy left to right.
		local x = ({ 0.375, 0.1875, 0 })[happiness] or 0
		button.happiness:SetTexCoord(x, x + 0.1875, 0, 0.359375)
		button.happiness:Show()
	else
		button.happiness:Hide()
	end

	local level = UnitLevel(unit)
	if not Secret(level) and level and level > 0 then
		button.level:SetText(level)
	else
		button.level:SetText("")
	end
end

local function UpdateAll()
	for _, button in ipairs(ns.Portraits.buttons or {}) do
		if UnitExists(Shown(button)) then
			UpdateModel(button)
			UpdateHealth(button)
			UpdateIcons(button)
		end
	end
end
ns.Portraits.Update = UpdateAll

function ns.Portraits.Layout()
	local anchor = ns.Portraits.anchor
	if not anchor then return end
	if InCombatLockdown() then
		ns.Portraits.pending = true
		return
	end
	ns.Portraits.pending = nil
	local opt = Opt()
	local player, pet = ns.Portraits.player, ns.Portraits.pet
	local showPlayer = opt.player or ns.Portraits.preview
	anchor:SetScale(ns.Art.D3Scale(opt.scale))
	anchor:SetSize(player:GetWidth(), player:GetHeight() + GAP + pet:GetHeight())
	anchor:ClearAllPoints()
	if opt.moved then
		anchor:SetPoint("CENTER", UIParent, "BOTTOMLEFT", ns.MovedPoint(anchor, opt))
	else
		anchor:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -16)
	end
	player:ClearAllPoints()
	player:SetPoint("TOPLEFT", anchor, "TOPLEFT")
	pet:ClearAllPoints()
	if showPlayer then
		pet:SetPoint("TOPLEFT", player, "BOTTOMLEFT", 0, -GAP)
	else
		-- Without your portrait the pet takes the top spot.
		pet:SetPoint("TOPLEFT", anchor, "TOPLEFT")
	end

	if opt.enabled then
		anchor:Show()
		player:SetShown(showPlayer and true or false)
		if ns.Portraits.preview then
			UnregisterUnitWatch(pet)
			pet:Show()
		elseif opt.pet then
			RegisterUnitWatch(pet)
		else
			UnregisterUnitWatch(pet)
			pet:Hide()
		end
	else
		UnregisterUnitWatch(pet)
		anchor:Hide()
	end
end

function ns.Portraits.SetPreview(on)
	if InCombatLockdown() then
		ns.Print("cannot preview in combat")
		return
	end
	ns.Portraits.preview = on and true or nil
	ns.Portraits.Layout()
	UpdateAll()
end

function ns.Portraits.ApplySettings()
	ns.Portraits.Layout()
	UpdateAll()
end

function ns.Portraits.ResetPosition()
	local opt = Opt()
	opt.moved, opt.mx, opt.my = false, 0, 0
	ns.Refresh()
end

function ns.Portraits.Init()
	local anchor = CreateFrame("Frame", "SanctuaryUIPortraits", UIParent)
	anchor:SetFrameStrata("LOW")
	ns.Portraits.anchor = anchor
	ns.Portraits.player = MakePortrait(anchor, "player", "SanctuaryUIPlayerPortrait", SIZE_K, false)
	ns.Portraits.pet = MakePortrait(anchor, "pet", "SanctuaryUIPetPortrait", SIZE_K * PET_K, true)
	ns.Portraits.buttons = { ns.Portraits.player, ns.Portraits.pet }
	ns.Portraits.pet:HookScript("OnShow", function(self)
		UpdateModel(self)
		UpdateHealth(self)
		UpdateIcons(self)
	end)
	ns.Portraits.mover = ns.MakeMover(anchor, "Portraits", Opt, "Reset its position in /sanctuary > Portraits.")

	local events = CreateFrame("Frame", nil, UIParent)
	for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED", "GROUP_ROSTER_UPDATE", "PARTY_LEADER_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_UPDATE_RESTING", "RAID_TARGET_UPDATE", "PLAYER_LEVEL_UP" }) do
		pcall(events.RegisterEvent, events, event)
	end
	events:RegisterUnitEvent("UNIT_PET", "player")
	events:RegisterUnitEvent("UNIT_HEALTH", "player", "pet")
	events:RegisterUnitEvent("UNIT_MAXHEALTH", "player", "pet")
	events:RegisterUnitEvent("UNIT_MODEL_CHANGED", "player", "pet")
	events:RegisterUnitEvent("UNIT_PORTRAIT_UPDATE", "player", "pet")
	pcall(events.RegisterUnitEvent, events, "UNIT_HAPPINESS", "pet")
	events:SetScript("OnEvent", function(_, event, unit)
		if not Opt().enabled then return end
		if event == "PLAYER_REGEN_ENABLED" and ns.Portraits.pending then
			ns.Portraits.Layout()
		end
		local button = unit == "pet" and ns.Portraits.pet or (unit == "player" and ns.Portraits.player) or nil
		if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
			if button then UpdateHealth(button) end
		elseif event == "UNIT_MODEL_CHANGED" or event == "UNIT_PORTRAIT_UPDATE" then
			if button then UpdateModel(button) end
		elseif event == "UNIT_PET" then
			UpdateModel(ns.Portraits.pet)
			UpdateHealth(ns.Portraits.pet)
			UpdateIcons(ns.Portraits.pet)
		elseif event == "PLAYER_ENTERING_WORLD" then
			UpdateAll()
		else
			for _, b in ipairs(ns.Portraits.buttons) do
				UpdateIcons(b)
			end
		end
	end)

	ns.Portraits.Layout()
	UpdateAll()
end
