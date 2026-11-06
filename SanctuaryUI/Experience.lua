SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.Experience = ns.Experience or {}

-- The rail is the channel above the skill sockets. Its fill draws under the console art,
-- so the frame's own dividers cut it into D3's ten segments.

local function Secret(...)
	if not issecretvalue then return false end
	for i = 1, select("#", ...) do
		if issecretvalue((select(i, ...))) then
			return true
		end
	end
	return false
end

local function AtMaxLevel()
	local level = UnitLevel("player")
	if level == nil or Secret(level) then
		return false
	end
	local cap = GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion() or (GetMaxPlayerLevel and GetMaxPlayerLevel())
	if not cap then return false end
	return level >= cap
end

-- name, standing label, value into the current standing, size of the standing
local function WatchedFaction()
	if C_Reputation and C_Reputation.GetWatchedFactionData then
		local data = C_Reputation.GetWatchedFactionData()
		if data and data.name then
			local low = data.currentReactionThreshold or 0
			local high = data.nextReactionThreshold or low
			local value = data.currentStanding or low
			local label = _G["FACTION_STANDING_LABEL" .. (data.reaction or 0)]
			return data.name, label, value - low, math.max(1, high - low)
		end
	end
	if GetWatchedFactionInfo then
		local name, standing, low, high, value = GetWatchedFactionInfo()
		if name then
			return name, _G["FACTION_STANDING_LABEL" .. (standing or 0)], (value or 0) - (low or 0), math.max(1, (high or 1) - (low or 0))
		end
	end
end

local function Mode()
	local mode = ns.DB().railMode or "auto"
	if mode == "auto" then
		return AtMaxLevel() and "rep" or "xp"
	end
	return mode
end

local function SetFill(bar, slot)
	local path = ns.Art.Path(slot)
	if path then
		bar:SetStatusBarTexture(path)
	else
		bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	end
end

function ns.Experience.Update()
	local bar = ns.ExperienceBar
	if not bar then return end
	local rested = bar.Rested
	local mode = Mode()
	bar.mode = mode

	if mode == "rep" then
		local name, _, value, size = WatchedFaction()
		if not name or Secret(value, size) then
			bar:Hide()
			return
		end
		bar:Show()
		rested:Hide()
		SetFill(bar, "xpWhite")
		local r, g, b = 0.95, 0.75, 0.3
		if ns.Globes and ns.Globes.ResourceColor then
			r, g, b = ns.Globes.ResourceColor()
		end
		bar:SetStatusBarColor(r, g, b, 1)
		bar:SetMinMaxValues(0, size)
		bar:SetValue(value)
		return
	end

	if AtMaxLevel() then
		bar:Hide()
		return
	end
	local xp, maxXP = UnitXP("player"), UnitXPMax("player")
	if Secret(xp, maxXP) or not xp or not maxXP then
		bar:Hide()
		return
	end
	bar:Show()
	SetFill(bar, "xpOrange")
	bar:SetStatusBarColor(1, 1, 1, 1)
	bar:SetMinMaxValues(0, maxXP)
	bar:SetValue(xp)
	local bonus = GetXPExhaustion and GetXPExhaustion()
	if Secret(bonus) then bonus = nil end
	if bonus and bonus > 0 and ns.DB().railRested then
		rested:SetMinMaxValues(0, maxXP)
		rested:SetValue(math.min(maxXP, xp + bonus))
		rested:Show()
	else
		rested:Hide()
	end
	bar.rested = bonus and bonus > 0 and bonus or nil
end

function ns.Experience.Layout()
	local cluster = ns.Cluster
	local bar = ns.ExperienceBar
	local metrics = ns.Metrics and ns.Metrics()
	if not cluster or not bar or not metrics then return end
	local rail = metrics.rail
	bar:SetSize(rail.w, rail.h)
	bar:ClearAllPoints()
	bar:SetPoint("CENTER", cluster, "BOTTOM", rail.x, metrics.baseY + rail.y)
	-- Above the liquid, below the glass and console art.
	bar.Rested:SetFrameLevel(cluster:GetFrameLevel() + ns.LEVEL.railRested)
	bar:SetFrameLevel(cluster:GetFrameLevel() + ns.LEVEL.rail)
end

local function ShowTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	if self.mode == "rep" then
		local name, label, value, size = WatchedFaction()
		if not name or Secret(value, size) then return end
		GameTooltip:SetText(name)
		GameTooltip:AddLine(("%s  %d / %d"):format(label or "", value, size), 1, 1, 1)
	else
		local xp, maxXP = UnitXP("player"), UnitXPMax("player")
		if Secret(xp, maxXP) or not xp or not maxXP then return end
		GameTooltip:SetText(("Experience  %d / %d"):format(xp, maxXP))
		if self.rested then
			GameTooltip:AddLine(("Rested  %d"):format(self.rested), 0.45, 0.65, 0.95)
		end
	end
	GameTooltip:Show()
end

function ns.Experience.Init()
	local bar = CreateFrame("StatusBar", "SanctuaryUIExperience", ns.Cluster)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0)
	SetFill(bar, "xpOrange")

	local rested = CreateFrame("StatusBar", nil, bar)
	rested:SetAllPoints(bar)
	rested:SetMinMaxValues(0, 1)
	rested:SetValue(0)
	SetFill(rested, "xpBlue")
	rested:SetStatusBarColor(1, 1, 1, 0.55)
	rested:Hide()
	bar.Rested = rested

	bar:EnableMouse(true)
	bar:SetScript("OnEnter", ShowTooltip)
	bar:SetScript("OnLeave", GameTooltip_Hide)
	ns.ExperienceBar = bar

	local events = CreateFrame("Frame", nil, bar)
	events:RegisterEvent("PLAYER_XP_UPDATE")
	events:RegisterEvent("PLAYER_LEVEL_UP")
	events:RegisterEvent("UPDATE_EXHAUSTION")
	events:RegisterEvent("UPDATE_FACTION")
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:SetScript("OnEvent", ns.Experience.Update)
	ns.Experience.Update()
end
