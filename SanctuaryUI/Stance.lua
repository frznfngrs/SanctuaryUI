SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.Stance = ns.Stance or {}

-- Stances, forms, auras, stealth, presences: whatever GetShapeshiftFormInfo lists. Secure
-- spell buttons (they work in combat) in the same D3 sockets and gold rims as the hotbar
-- rows. Sits above the health globe by default and drags like a row while unlocked.
-- Blizzard's SHAPESHIFTBUTTON keybinds carry over; hover-binding works too.

local MAX = 10

local function Opt()
	return ns.DB().stance
end

local function NumForms()
	return GetNumShapeshiftForms and GetNumShapeshiftForms() or 0
end

function ns.Stance.HasForms()
	return Opt().enabled and NumForms() > 0
end

local function Hotkey(button, i)
	local key = GetBindingKey("SHAPESHIFTBUTTON" .. i)
	local KeyBound = LibStub("LibKeyBound-1.0", true)
	button.HotKey:SetText(key and ns.DB().buttons.hotkeys and (KeyBound and KeyBound:ToShortKey(key) or key) or "")
end

local function MakeButton(parent, i)
	local button = CreateFrame("CheckButton", "SanctuaryUIStanceButton" .. i, parent, "SecureActionButtonTemplate")
	button:RegisterForClicks("AnyUp", "AnyDown")
	button:SetID(i)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetAllPoints()
	button.cooldown = CreateFrame("Cooldown", button:GetName() .. "Cooldown", button, "CooldownFrameTemplate")
	button.cooldown:SetAllPoints()
	button.HotKey = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	ns.ActionBar.StyleHotkey(button.HotKey)
	button.HotKey:SetTextColor(0.86, 0.72, 0.42)
	button.HotKey:SetPoint("BOTTOM", 0, 2)
	button.sanctuary, button.sanctuarySquare, button.sanctuarySocket = true, true, true
	-- A plain CheckButton has no checked texture, so SetChecked showed nothing. The reskin turns
	-- this one into the gold socket rim; full strength, since it is the only mark of the form.
	button:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight")
	button.sanctuaryCheckedAlpha = 1
	ns.Art.ReskinActionButton(nil, button)
	button:SetScript("OnEnter", function(self)
		if GameTooltip:IsForbidden() then return end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		if GameTooltip.SetShapeshift then
			GameTooltip:SetShapeshift(self:GetID())
		end
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	ns.Menu.KeyBindable(button, "SHAPESHIFTBUTTON" .. i, "Stance " .. i)
	-- Clicking never toggles the check: it shows the active form, set from Update.
	button:HookScript("PostClick", function(self) ns.Stance.Update() end)
	return button
end

-- Actions and visibility: secure, so only out of combat.
local function Configure()
	local bar = ns.Stance.bar
	if InCombatLockdown() then
		ns.Stance.pending = true
		return
	end
	ns.Stance.pending = nil
	local count = math.min(MAX, NumForms())
	for i = 1, MAX do
		local button = bar.buttons[i]
		if i <= count then
			local _, _, _, spellID = GetShapeshiftFormInfo(i)
			button:SetAttribute("type", "spell")
			button:SetAttribute("spell", spellID)
			button:Show()
		else
			button:SetAttribute("type", nil)
			button:Hide()
		end
	end
	if Opt().enabled and count > 0 then
		RegisterStateDriver(bar, "visibility", "[petbattle][vehicleui][overridebar][possessbar] hide; show")
	else
		UnregisterStateDriver(bar, "visibility")
		bar:Hide()
	end
	ns.Stance.ReassignBindings()
end

function ns.Stance.ReassignBindings()
	local bar = ns.Stance.bar
	if not bar or InCombatLockdown() then return end
	ClearOverrideBindings(bar)
	for i = 1, MAX do
		local button = bar.buttons[i]
		for k = 1, select("#", GetBindingKey("SHAPESHIFTBUTTON" .. i)) do
			local key = select(k, GetBindingKey("SHAPESHIFTBUTTON" .. i))
			if key and key ~= "" then
				SetOverrideBindingClick(bar, false, key, button:GetName(), "LeftButton")
			end
		end
		Hotkey(button, i)
	end
end

-- The active form. GetShapeshiftFormInfo's flag can come back secret in combat; the current
-- form's index answers instead, and failing that the button takes the secret flag itself.
local function SetActive(button, i, active, current)
	if not ns.Secret(active) then
		button:SetChecked(active and true or false)
	elseif current then
		button:SetChecked(current == i)
	elseif not pcall(button.SetChecked, button, active) then
		button:SetChecked(false)
	end
end

-- Icons, active form, usable, cooldowns: safe any time.
function ns.Stance.Update()
	local bar = ns.Stance.bar
	if not bar then return end
	local current = GetShapeshiftForm and GetShapeshiftForm()
	if current ~= nil and ns.Secret(current) then current = nil end
	for i = 1, math.min(MAX, NumForms()) do
		local button = bar.buttons[i]
		local icon, active, castable = GetShapeshiftFormInfo(i)
		if ns.Secret(castable) then castable = true end
		button.icon:SetTexture(icon)
		button.icon:SetDesaturated(not castable)
		button.icon:SetVertexColor(castable and 1 or 0.6, castable and 1 or 0.6, castable and 1 or 0.6)
		SetActive(button, i, active, current)
		if GetShapeshiftFormCooldown then
			local start, duration, enable = GetShapeshiftFormCooldown(i)
			pcall(CooldownFrame_Set, button.cooldown, start, duration, enable)
		end
	end
end

function ns.Stance.Layout()
	local bar = ns.Stance.bar
	local cluster = ns.Cluster
	local metrics = ns.Metrics and ns.Metrics()
	if not bar or not cluster or not metrics then return end
	if InCombatLockdown() then
		ns.Stance.pending = true
		return
	end
	local opt = Opt()
	local count = math.max(1, math.min(MAX, NumForms()))
	local bw = metrics.slots[1].w * opt.scale
	local bh = metrics.slots[1].h * opt.scale
	local gap = opt.spacing
	local cols = math.max(1, math.min(count, opt.perLine))
	local lines = math.ceil(count / cols)
	local lineGap = gap + bh * 0.16
	local width = cols * bw + (cols - 1) * gap
	local height = lines * bh + (lines - 1) * lineGap
	bar:SetSize(width, height)
	bar:ClearAllPoints()
	if opt.moved then
		bar:SetPoint("CENTER", UIParent, "BOTTOMLEFT", ns.MovedPoint(bar, opt))
	else
		-- Centred above the health globe, clear of the demon's horns.
		local globe = metrics.health
		bar:SetPoint("BOTTOM", cluster, "BOTTOM", globe.x, metrics.baseY + globe.y + globe.size / 2 + bh * 0.3)
	end
	for i = 1, MAX do
		local button = bar.buttons[i]
		local col = (i - 1) % cols
		local line = math.floor((i - 1) / cols)
		button:SetSize(bw, bh)
		button:ClearAllPoints()
		button:SetPoint("CENTER", bar, "TOPLEFT", col * (bw + gap) + bw / 2, -(line * (bh + lineGap) + bh / 2))
	end
	bar:SetFrameLevel(cluster:GetFrameLevel() + ns.LEVEL.buttons)
	bar.alpha, bar.mouseover = opt.alpha, opt.mouseover
	bar:SetAlpha(opt.mouseover and 0 or opt.alpha)
end

function ns.Stance.ApplySettings()
	if not ns.Stance.bar then return end
	for _, button in ipairs(ns.Stance.bar.buttons) do
		ns.ActionBar.StyleHotkey(button.HotKey)
	end
	Configure()
	ns.Stance.Layout()
	ns.Stance.Update()
end

function ns.Stance.Init()
	local bar = CreateFrame("Frame", "SanctuaryUIStanceBar", ns.Cluster, "SecureHandlerStateTemplate")
	bar.buttons = {}
	for i = 1, MAX do
		bar.buttons[i] = MakeButton(bar, i)
	end
	ns.Stance.bar = bar
	ns.Stance.mover = ns.MakeMover(bar, "Stances", Opt, "Reset its position in /sanctuary > Stance & pet bars.")

	-- Mouseover-only: invisible until the mouse is over a stance button.
	local wait = 0
	bar:SetScript("OnUpdate", function(self, elapsed)
		if not self.mouseover then return end
		wait = wait - elapsed
		if wait > 0 then return end
		wait = 0.1
		local over = false
		for i = 1, MAX do
			local button = self.buttons[i]
			if button:IsVisible() and button:IsMouseOver() then
				over = true
				break
			end
		end
		self:SetAlpha(over and self.alpha or 0)
	end)

	local events = CreateFrame("Frame", nil, ns.Cluster)
	for _, event in ipairs({ "UPDATE_SHAPESHIFT_FORMS", "UPDATE_SHAPESHIFT_FORM", "UPDATE_SHAPESHIFT_USABLE", "UPDATE_SHAPESHIFT_COOLDOWN", "ACTIONBAR_UPDATE_COOLDOWN", "SPELL_UPDATE_USABLE", "PLAYER_ENTERING_WORLD", "UPDATE_BINDINGS", "PLAYER_REGEN_ENABLED" }) do
		pcall(events.RegisterEvent, events, event)
	end
	events:SetScript("OnEvent", function(_, event)
		if event == "UPDATE_SHAPESHIFT_FORMS" or event == "PLAYER_ENTERING_WORLD" or (event == "PLAYER_REGEN_ENABLED" and ns.Stance.pending) then
			Configure()
			ns.Stance.Layout()
			ns.ActionBar.UpdateMovers()
		elseif event == "UPDATE_BINDINGS" then
			ns.Stance.ReassignBindings()
		end
		ns.Stance.Update()
	end)
	Configure()
	ns.Stance.Update()
end

function ns.Stance.ResetPosition()
	local opt = Opt()
	opt.moved, opt.mx, opt.my = false, 0, 0
	ns.Refresh()
end
