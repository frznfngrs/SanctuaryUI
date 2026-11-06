SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.TargetPlate = ns.TargetPlate or {}

local function Secret(value)
	return issecretvalue and issecretvalue(value)
end

local function Fill(bar, value, maxValue)
	if maxValue ~= nil and not Secret(maxValue) then
		bar:SetMinMaxValues(0, maxValue)
	else
		pcall(bar.SetMinMaxValues, bar, 0, maxValue or 1)
	end
	if not pcall(bar.SetValue, bar, value or 0) then
		bar:SetValue(0)
	end
end

local function StopCast(cast)
	cast:Hide()
	cast.startMS = nil
	cast.endMS = nil
end

local function ReadCast(unit, channel)
	local name, _, texture, startMS, endMS, _, notInterruptible, spellID
	if channel then
		name, _, texture, startMS, endMS, _, notInterruptible, spellID = UnitChannelInfo(unit)
	else
		name, _, texture, startMS, endMS, _, _, notInterruptible, spellID = UnitCastingInfo(unit)
	end
	return name, texture, startMS, endMS, notInterruptible, spellID
end

local function StartCast(cast, channel)
	local name, texture, startMS, endMS, notInterruptible = ReadCast("target", channel)
	if not name then
		if not channel then
			name, texture, startMS, endMS, notInterruptible = ReadCast("target", true)
			channel = name and true or false
		end
		if not name then
			StopCast(cast)
			return
		end
	end
	cast:Show()
	cast.channel = channel
	cast.startMS = startMS
	cast.endMS = endMS
	cast.spellName:SetText(name)
	if texture then
		cast.icon:SetTexture(texture)
		cast.icon:Show()
	else
		cast.icon:Hide()
	end
	local shielded = notInterruptible and not Secret(notInterruptible) and notInterruptible
	if shielded then
		cast:SetStatusBarColor(0.55, 0.52, 0.48, 1)
	elseif channel then
		cast:SetStatusBarColor(0.35, 0.7, 0.4, 1)
	else
		cast:SetStatusBarColor(0.86, 0.72, 0.42, 1)
	end
	if startMS and endMS and not Secret(startMS) and not Secret(endMS) then
		cast:SetMinMaxValues(startMS, endMS)
		cast:SetValue(GetTime() * 1000)
	else
		pcall(function()
			cast:SetMinMaxValues(startMS, endMS)
			cast:SetValue(GetTime() * 1000)
		end)
	end
end

-- Target of target: unit events don't fire for "targettarget", so its bar is polled.
local function UpdateToT(plate)
	if UnitExists("targettarget") then
		plate.ToT:Show()
		plate.ToT.Name:SetText(UnitName("targettarget") or "")
		Fill(plate.ToT, UnitHealth("targettarget"), UnitHealthMax("targettarget"))
	else
		plate.ToT:Hide()
	end
end

function ns.TargetPlate.Update()
	local plate = ns.TargetPlate.frame
	if not plate then return end
	if not UnitExists("target") then
		plate:Hide()
		return
	end
	plate:Show()
	local name = UnitName("target") or ""
	plate.Name:SetText(name)
	local reaction = UnitReaction("player", "target")
	local friendly = UnitIsFriend("player", "target")
	if friendly then
		plate.Name:SetTextColor(0.55, 0.85, 0.45)
		plate.Health:SetStatusBarColor(0.2, 0.55, 0.25, 1)
	elseif reaction and not Secret(reaction) and reaction < 4 then
		plate.Name:SetTextColor(0.9, 0.25, 0.2)
		plate.Health:SetStatusBarColor(0.72, 0.1, 0.08, 1)
	else
		plate.Name:SetTextColor(0.95, 0.85, 0.55)
		plate.Health:SetStatusBarColor(0.72, 0.45, 0.12, 1)
	end
	Fill(plate.Health, UnitHealth("target"), UnitHealthMax("target"))

	UpdateToT(plate)
	StartCast(plate.Cast, false)
end

function ns.TargetPlate.Layout()
	local plate = ns.TargetPlate.frame
	if not plate then return end
	plate:ClearAllPoints()
	plate:SetPoint("TOP", UIParent, "TOP", 0, -12)
end

function ns.TargetPlate.Init()
	local plate = CreateFrame("Frame", "SanctuaryUITargetPlate", UIParent)
	plate:SetSize(420, 78)
	-- The frame lives in a field: the module table keeps Update and Layout.
	ns.TargetPlate.frame = plate

	local bg = plate:CreateTexture(nil, "BACKGROUND")
	bg:SetPoint("TOPLEFT", 40, -18)
	bg:SetPoint("BOTTOMRIGHT", -40, 28)
	bg:SetColorTexture(0.05, 0.04, 0.03, 0.82)

	plate.Name = plate:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	plate.Name:SetPoint("TOP", 0, -2)
	plate.Name:SetWidth(400)
	plate.Name:SetWordWrap(false)
	plate.Name:SetJustifyH("CENTER")

	plate.Health = CreateFrame("StatusBar", nil, plate)
	plate.Health:SetSize(340, 16)
	plate.Health:SetPoint("TOP", plate.Name, "BOTTOM", 0, -4)
	plate.Health:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	plate.Health:SetStatusBarColor(0.72, 0.1, 0.08, 1)
	local healthBg = plate.Health:CreateTexture(nil, "BACKGROUND")
	healthBg:SetAllPoints()
	healthBg:SetColorTexture(0.12, 0.05, 0.04, 0.9)

	plate.Cast = CreateFrame("StatusBar", nil, plate)
	plate.Cast:SetSize(340, 12)
	plate.Cast:SetPoint("TOP", plate.Health, "BOTTOM", 0, -3)
	plate.Cast:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	plate.Cast:SetStatusBarColor(0.86, 0.72, 0.42, 1)
	local castBg = plate.Cast:CreateTexture(nil, "BACKGROUND")
	castBg:SetAllPoints()
	castBg:SetColorTexture(0.08, 0.07, 0.05, 0.9)
	plate.Cast.icon = plate.Cast:CreateTexture(nil, "ARTWORK")
	plate.Cast.icon:SetSize(16, 16)
	plate.Cast.icon:SetPoint("RIGHT", plate.Cast, "LEFT", -3, 0)
	ns.Art.MaskCircle(plate.Cast.icon)
	plate.Cast.spellName = plate.Cast:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	plate.Cast.spellName:SetPoint("CENTER")
	plate.Cast.spellName:SetWidth(320)
	plate.Cast.spellName:SetWordWrap(false)
	plate.Cast:Hide()
	plate.Cast:SetScript("OnUpdate", function(self)
		if not self.startMS or not self.endMS then return end
		if Secret(self.endMS) then return end
		local now = GetTime() * 1000
		if not Secret(self.startMS) then
			self:SetValue(now)
			if now >= self.endMS then
				StopCast(self)
			end
		end
	end)

	plate.ToT = CreateFrame("StatusBar", nil, plate)
	plate.ToT:SetSize(180, 8)
	plate.ToT:SetPoint("TOP", plate.Cast, "BOTTOM", 0, -4)
	plate.ToT:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	plate.ToT:SetStatusBarColor(0.55, 0.12, 0.1, 1)
	local totBg = plate.ToT:CreateTexture(nil, "BACKGROUND")
	totBg:SetAllPoints()
	totBg:SetColorTexture(0.08, 0.05, 0.04, 0.85)
	plate.ToT.Name = plate.ToT:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	plate.ToT.Name:SetPoint("BOTTOM", plate.ToT, "TOP", 0, 1)
	plate.ToT.Name:SetWidth(180)
	plate.ToT.Name:SetWordWrap(false)
	plate.ToT:Hide()

	local events = CreateFrame("Frame", nil, plate)
	events:RegisterEvent("PLAYER_TARGET_CHANGED")
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:RegisterUnitEvent("UNIT_HEALTH", "target")
	events:RegisterUnitEvent("UNIT_MAXHEALTH", "target")
	events:RegisterUnitEvent("UNIT_TARGET", "target")
	events:RegisterUnitEvent("UNIT_SPELLCAST_START", "target")
	events:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "target")
	events:RegisterUnitEvent("UNIT_SPELLCAST_DELAYED", "target")
	events:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "target")
	events:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "target")
	events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "target")
	events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "target")
	events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", "target")
	pcall(events.RegisterUnitEvent, events, "UNIT_SPELLCAST_EMPOWER_START", "target")
	pcall(events.RegisterUnitEvent, events, "UNIT_SPELLCAST_EMPOWER_UPDATE", "target")
	pcall(events.RegisterUnitEvent, events, "UNIT_SPELLCAST_EMPOWER_STOP", "target")
	events:SetScript("OnEvent", function(_, event)
		if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_DELAYED" then
			StartCast(plate.Cast, false)
		elseif event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" or event == "UNIT_SPELLCAST_EMPOWER_START" or event == "UNIT_SPELLCAST_EMPOWER_UPDATE" then
			StartCast(plate.Cast, true)
		elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_CHANNEL_STOP" or event == "UNIT_SPELLCAST_EMPOWER_STOP" then
			StopCast(plate.Cast)
		else
			ns.TargetPlate.Update()
		end
	end)

	local elapsedToT = 0
	plate:SetScript("OnUpdate", function(self, elapsed)
		elapsedToT = elapsedToT + elapsed
		if elapsedToT < 0.2 then return end
		elapsedToT = 0
		UpdateToT(self)
	end)

	plate:Hide()
end
