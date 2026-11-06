SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.Auras = ns.Auras or {}

-- Buffs and debuffs the way D3 shows them: small square icons above the skill bar, a clock
-- sweep running down, stacks in the corner, no big countdown numbers. A small duration line
-- under each icon (optional), debuffs on their own line in red-stained sockets. Movable,
-- sized and wrapped from the options like the hotbar rows.
--
-- The icons are plain frames, so they show, hide and update freely in combat. Right-click
-- cancel is a separate layer of secure "cancelaura" buttons laid over the buffs out of
-- combat only (positioned with the same grid, not anchored to the icons, so the icons never
-- become protected). Buff order shifts in a fight, so the layer hides when combat starts
-- rather than risk cancelling the wrong buff.

local MAX_BUFFS, MAX_DEBUFFS = 24, 12
local BAR_H = 4
local BAR_WARN = 10 -- seconds: the bar turns red

local function Opt()
	return ns.DB().auras
end

local function Secret(value)
	return issecretvalue and issecretvalue(value)
end

local function FormatTime(seconds)
	if seconds >= 3600 then
		return ("%dh"):format(math.floor(seconds / 3600 + 0.5))
	elseif seconds >= 60 then
		return ("%dm"):format(math.floor(seconds / 60 + 0.5))
	end
	return ("%d"):format(math.floor(seconds + 0.5))
end

local function ShowTooltip(owner, icon)
	if GameTooltip:IsForbidden() then return end
	if icon.enchantSlot then
		GameTooltip:SetOwner(owner, "ANCHOR_BOTTOMLEFT")
		GameTooltip:SetInventoryItem("player", icon.enchantSlot)
		GameTooltip:Show()
		return
	end
	if type(icon.auraID) == "nil" and not icon.index then return end
	GameTooltip:SetOwner(owner, "ANCHOR_BOTTOMLEFT")
	local filter = icon.harmful and "HARMFUL" or "HELPFUL"
	local byID = icon.harmful and GameTooltip.SetUnitDebuffByAuraInstanceID or GameTooltip.SetUnitBuffByAuraInstanceID
	if type(icon.auraID) ~= "nil" and byID then
		pcall(byID, GameTooltip, "player", icon.auraID, filter)
	elseif icon.index then
		pcall(GameTooltip.SetUnitAura, GameTooltip, "player", icon.index, filter)
	end
	if not icon.harmful and not InCombatLockdown() then
		GameTooltip:AddLine("Right-click to cancel", 0.6, 0.6, 0.6)
	end
	GameTooltip:Show()
end

local function MakeIcon(parent, name, harmful)
	local button = CreateFrame("Frame", name, parent)
	button:EnableMouse(true)
	button.harmful = harmful
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetAllPoints()
	button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	button.cooldown:SetAllPoints()
	button.cooldown:SetReverse(true)
	if button.cooldown.SetDrawEdge then button.cooldown:SetDrawEdge(false) end
	if button.cooldown.SetHideCountdownNumbers then button.cooldown:SetHideCountdownNumbers(true) end
	button.count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	button.count:SetPoint("BOTTOMRIGHT", 1, 1)
	-- Countdown bar: the XP rail's strip, in gold, running down under the icon.
	local bar = CreateFrame("StatusBar", nil, button)
	bar:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -3)
	bar:SetPoint("TOPRIGHT", button, "BOTTOMRIGHT", 0, -3)
	bar:SetHeight(BAR_H)
	bar:SetStatusBarTexture(ns.Art.Path("xpWhite") or "Interface\\Buttons\\WHITE8X8")
	bar:SetMinMaxValues(0, 1)
	local barBg = bar:CreateTexture(nil, "BACKGROUND")
	barBg:SetPoint("TOPLEFT", -1, 1)
	barBg:SetPoint("BOTTOMRIGHT", 1, -1)
	barBg:SetColorTexture(0.03, 0.02, 0.02, 0.85)
	bar:Hide()
	button.bar = bar
	button.time = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	button.time:SetPoint("TOP", bar, "BOTTOM", 0, -2)
	button.time:SetTextColor(0.9, 0.82, 0.62)
	button.sanctuarySocket = true
	ns.Art.AttachRing(button)
	if harmful and button.sanctuarySocketTex then
		button.sanctuarySocketTex:SetVertexColor(1, 0.35, 0.3)
	end
	button:SetScript("OnEnter", function(self) ShowTooltip(self, self) end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	button:Hide()
	return button
end

-- Every aura of one kind on the player, in the client's order. Same approach as TargetPlate:
-- GetUnitAuras first; GetAuraDataByIndex can throw when auras are secret, so the fallback is
-- pcall'd and stops quietly when the client refuses.
local function ReadAuras(unit, filter)
	local UA = C_UnitAuras
	if not UA then return {} end
	if UA.GetUnitAuras then
		local ok, list = pcall(UA.GetUnitAuras, unit, filter)
		if ok and type(list) == "table" then return list end
	end
	local list = {}
	if not UA.GetAuraDataByIndex then return list end
	for index = 1, 40 do
		local ok, aura = pcall(UA.GetAuraDataByIndex, unit, index, filter)
		if not ok or not aura then break end
		aura.index = index
		list[#list + 1] = aura
	end
	return list
end

local function Collect(filter, maxCount)
	local list = ReadAuras("player", filter)
	for i = maxCount + 1, #list do list[i] = nil end
	return list
end

-- Temporary weapon enchants (poisons, oils, shaman imbues) are not auras; they lead the buff
-- line the way Blizzard's frame shows them. Durations come only as time left, so the full
-- length is the longest time left seen for that enchant.
local enchantLength = {}

local function WeaponEnchants()
	local list = {}
	if not GetWeaponEnchantInfo then return list end
	local info = { GetWeaponEnchantInfo() }
	local now = GetTime()
	for k, slot in ipairs({ 16, 17, 18 }) do
		local base = (k - 1) * 4
		local has, msLeft, charges, id = info[base + 1], info[base + 2], info[base + 3], info[base + 4]
		if not Secret(has) and not Secret(msLeft) and has and msLeft then
			local left = msLeft / 1000
			local key = slot .. ":" .. tostring(id)
			if not enchantLength[key] or left > enchantLength[key] then
				enchantLength[key] = left
			end
			list[#list + 1] = {
				enchantSlot = slot,
				icon = GetInventoryItemTexture("player", slot),
				applications = charges,
				duration = enchantLength[key],
				expirationTime = now + left,
			}
		end
	end
	return list
end

-- What the enchants are, so the poll below only repaints when one comes or goes.
local function EnchantSignature()
	if not GetWeaponEnchantInfo then return "" end
	local info = { GetWeaponEnchantInfo() }
	local parts = {}
	for k = 0, 2 do
		local has, id = info[k * 4 + 1], info[k * 4 + 4]
		if Secret(has) or Secret(id) then return "secret" end
		parts[#parts + 1] = tostring(has and id or false)
	end
	return table.concat(parts, ",")
end

local function MakeCancel(parent, icon)
	local cancel = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
	cancel:RegisterForClicks("RightButtonUp")
	cancel:SetAttribute("type2", "cancelaura")
	cancel:SetAttribute("unit", "player")
	cancel:SetScript("OnEnter", function(self) ShowTooltip(self, icon) end)
	cancel:SetScript("OnLeave", GameTooltip_Hide)
	cancel:Hide()
	return cancel
end

-- Out of combat only: one cancel button over each buff that is up.
local function SyncCancels()
	local frame = ns.Auras.frame
	if not frame or InCombatLockdown() then return end
	for i = 1, MAX_BUFFS do
		local icon, cancel = frame.buffs[i], frame.cancels[i]
		local name = icon:IsShown() and icon.name
		if name and not Secret(name) then
			cancel:SetAttribute("spell", name)
			cancel:Show()
		else
			cancel:Hide()
		end
	end
end

local function Paint(button, aura)
	if not aura then
		button.index, button.auraID, button.expires, button.name, button.enchantSlot = nil, nil, nil, nil, nil
		button:Hide()
		button.time:SetText("")
		return
	end
	button.index, button.name, button.enchantSlot = aura.index, aura.name, aura.enchantSlot
	button.auraID = aura.auraInstanceID
	button:Show()
	button.icon:SetTexture(aura.icon)
	local stacks = aura.applications
	if stacks and not Secret(stacks) and stacks > 1 then
		button.count:SetText(stacks)
	else
		button.count:SetText("")
	end
	local duration, expiration = aura.duration, aura.expirationTime
	if duration and expiration and not Secret(duration) and not Secret(expiration) and duration > 0 then
		button.cooldown:SetCooldown(expiration - duration, duration)
		button.expires, button.duration = expiration, duration
	else
		button.cooldown:Clear()
		button.expires, button.duration = nil, nil
	end
end

function ns.Auras.Update()
	local frame = ns.Auras.frame
	if not frame then return end
	local opt = Opt()
	if not opt.enabled then
		frame:Hide()
		return
	end
	frame:Show()
	local buffs = WeaponEnchants()
	for _, aura in ipairs(Collect("HELPFUL", opt.maxBuffs)) do
		buffs[#buffs + 1] = aura
	end
	frame.enchants = EnchantSignature()
	local debuffs = Collect("HARMFUL", opt.maxDebuffs)
	for i = 1, MAX_BUFFS do
		Paint(frame.buffs[i], i <= opt.maxBuffs and buffs[i] or nil)
	end
	for i = 1, MAX_DEBUFFS do
		Paint(frame.debuffs[i], i <= opt.maxDebuffs and debuffs[i] or nil)
	end
	SyncCancels()
	ns.Auras.UpdateTimes()
end

function ns.Auras.UpdateTimes()
	local frame = ns.Auras.frame
	if not frame then return end
	local opt = Opt()
	local show, bars = opt.duration, opt.bars
	local now = GetTime()
	local function each(list)
		for i = 1, #list do
			local button = list[i]
			local left = button.expires and math.max(0, button.expires - now)
			if left and show then
				button.time:SetText(FormatTime(left))
			else
				button.time:SetText("")
			end
			local bar = button.bar
			if left and bars and button.duration then
				bar:SetValue(left / button.duration)
				if left <= BAR_WARN then
					bar:SetStatusBarColor(0.95, 0.22, 0.12, 1)
				elseif button.harmful then
					bar:SetStatusBarColor(0.85, 0.35, 0.25, 1)
				else
					bar:SetStatusBarColor(0.95, 0.75, 0.3, 1)
				end
				bar:Show()
			else
				bar:Hide()
			end
		end
	end
	each(frame.buffs)
	each(frame.debuffs)
end

-- Place icons (and, for buffs, their cancel buttons) on a grid in the aura frame.
local function Grid(frame, list, cancels, count, size, gap, cols, lineH, top)
	for i = 1, #list do
		local col = (i - 1) % cols
		local line = math.floor((i - 1) / cols)
		local x, y = col * (size + gap), -(top + line * lineH)
		local icon = list[i]
		icon:SetSize(size, size)
		icon:ClearAllPoints()
		icon:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
		local cancel = cancels and cancels[i]
		if cancel then
			cancel:SetSize(size, size)
			cancel:ClearAllPoints()
			cancel:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
		end
	end
	return math.ceil(count / cols)
end

-- Debuffs on top, buffs below them, nearest the skill bar as in D3.
function ns.Auras.Layout()
	local frame = ns.Auras.frame
	local cluster = ns.Cluster
	if not frame or not cluster then return end
	if InCombatLockdown() then
		ns.Auras.pending = true
		return
	end
	ns.Auras.pending = nil
	local opt = Opt()
	local size, gap = opt.size, opt.spacing
	local cols = math.max(1, opt.perLine)
	local lineH = size + gap + (opt.bars and BAR_H + 4 or 0) + (opt.duration and 13 or 4)
	local debuffLines = Grid(frame, frame.debuffs, nil, opt.maxDebuffs, size, gap, cols, lineH, 0)
	local buffLines = Grid(frame, frame.buffs, frame.cancels, opt.maxBuffs, size, gap, cols, lineH, debuffLines * lineH)
	local width = math.min(cols, math.max(opt.maxBuffs, opt.maxDebuffs)) * (size + gap) - gap
	frame:SetSize(width, math.max(size, (debuffLines + buffLines) * lineH - gap))
	frame:ClearAllPoints()
	if opt.moved then
		frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", opt.mx, opt.my)
	else
		local top = ns.ActionBar and ns.ActionBar.topY or 150
		frame:SetPoint("BOTTOM", cluster, "BOTTOM", 0, top + 8)
	end
	frame:SetFrameLevel(cluster:GetFrameLevel() + ns.LEVEL.buttons)
end

function ns.Auras.ApplySettings()
	if not ns.Auras.frame then return end
	ns.Auras.Layout()
	ns.Auras.Update()
	ns.ActionBar.UpdateMovers()
end

function ns.Auras.ResetPosition()
	local opt = Opt()
	opt.moved, opt.mx, opt.my = false, 0, 0
	ns.Refresh()
end

function ns.Auras.Init()
	local frame = CreateFrame("Frame", "SanctuaryUIAuras", ns.Cluster)
	frame.buffs, frame.debuffs = {}, {}
	for i = 1, MAX_BUFFS do
		frame.buffs[i] = MakeIcon(frame, "SanctuaryUIBuff" .. i, false)
	end
	for i = 1, MAX_DEBUFFS do
		frame.debuffs[i] = MakeIcon(frame, "SanctuaryUIDebuff" .. i, true)
	end
	-- The cancel layer: secure, over the buffs, out of combat only.
	frame.cancelLayer = CreateFrame("Frame", nil, frame)
	frame.cancelLayer:SetAllPoints()
	frame.cancels = {}
	for i = 1, MAX_BUFFS do
		frame.cancels[i] = MakeCancel(frame.cancelLayer, frame.buffs[i])
	end
	ns.Auras.frame = frame
	ns.Auras.mover = ns.MakeMover(frame, "Buffs", Opt, "Reset its position in /sanctuary > Buffs.")

	local wait, enchantWait = 0, 0
	frame:SetScript("OnUpdate", function(_, elapsed)
		-- Weapon enchants fire no aura event when they run out.
		enchantWait = enchantWait - elapsed
		if enchantWait <= 0 then
			enchantWait = 0.5
			if EnchantSignature() ~= frame.enchants then
				ns.Auras.Update()
			end
		end
		wait = wait - elapsed
		if wait > 0 then return end
		wait = 0.1 -- smooth countdown bars
		ns.Auras.UpdateTimes()
	end)

	local events = CreateFrame("Frame", nil, frame)
	events:RegisterUnitEvent("UNIT_AURA", "player")
	events:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:RegisterEvent("PLAYER_REGEN_DISABLED")
	events:RegisterEvent("PLAYER_REGEN_ENABLED")
	events:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_REGEN_DISABLED" then
			-- Last chance before lockdown: put the cancel layer away (buff order will shift).
			frame.cancelLayer:Hide()
			return
		end
		if event == "PLAYER_REGEN_ENABLED" then
			frame.cancelLayer:Show()
		end
		if event == "PLAYER_REGEN_ENABLED" and ns.Auras.pending then
			ns.Auras.Layout()
		end
		ns.Auras.Update()
	end)
	ns.Auras.Layout()
	ns.Auras.Update()
end
