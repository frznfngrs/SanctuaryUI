SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.Auras = ns.Auras or {}

-- Buffs and debuffs above the skill bar, D3 style: icons in stone sockets, a gold countdown
-- strip under each timed one, debuffs in red-stained sockets above the buffs.
--
-- The icons are Blizzard's own BuffFrame and DebuffFrame, dressed. In combat
-- this client won't let an addon read the player's auras at all ("Auras cannot be accessed
-- when secret while tainted"), but Blizzard's frames, running untainted, still can. So they
-- must stay untainted: we never write a field their code reads and never call into their
-- update code. We only add our own textures and frames to their buttons, and read (never
-- write) what their buttons show.
--
-- Where they sit, icon size, icons per row, the limit and wrap direction are all Edit Mode's
-- (drag them there). Wrap "Up" gives the D3 look when placed just above the bars. The one
-- exception is the debuffs' place once they're dragged by their own mover (#49, below).

local BAR_H = 4
local BAR_WARN = 10 -- seconds: the strip turns red
local BASE_ICON = 30 -- Blizzard's aura icon size

local function Opt()
	return ns.DB().auras
end

local function Secret(value)
	return issecretvalue and issecretvalue(value)
end

local function Readable(value)
	return not Secret(value) and value ~= nil
end

local function Frames()
	return _G.BuffFrame, _G.DebuffFrame
end

---------------------------------------------------------------------------
-- Dressing one Blizzard aura button. Our state lives in this table, not on their buttons.

local skins = {}

local function PlaceDuration(button)
	local skin = skins[button]
	if not skin or not button.Duration or not button.Icon then return end
	local opt = Opt()
	button.Duration:ClearAllPoints()
	button.Duration:SetPoint("TOP", button.Icon, "BOTTOM", 0, opt.bars and -(BAR_H + 5) or -1)
	button.Duration:SetAlpha(opt.duration and 1 or 0)
end

local function Skin(button, harmful)
	if skins[button] then return skins[button] end
	local icon = button.Icon
	if not icon then return end
	local skin = {}
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	-- The stone socket behind the icon (same art and fit as the hotbar sockets).
	local socket = button:CreateTexture(nil, "BACKGROUND", nil, -7)
	if ns.Art.Apply(socket, "socket") then
		socket:SetTexCoord(unpack(ns.Art.SOCKET_TEXCOORD))
	else
		socket:SetColorTexture(0.05, 0.05, 0.05, 0.9)
	end
	local inset = ns.Art.SOCKET_INSET
	local w, h = icon:GetSize()
	w, h = (w and w > 0) and w or BASE_ICON, (h and h > 0) and h or BASE_ICON
	local fw = w / (1 - inset.left - inset.right)
	local fh = h / (1 - inset.top - inset.bottom)
	socket:SetPoint("TOPLEFT", icon, "TOPLEFT", -fw * inset.left, fh * inset.top)
	socket:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", fw * inset.right, -fh * inset.bottom)
	if harmful then
		socket:SetVertexColor(1, 0.35, 0.3)
	end
	-- Blizzard's square borders fight the socket. They are shown and hidden by Blizzard, so
	-- they go away by alpha, which their code never touches.
	for _, key in ipairs({ "DebuffBorder", "TempEnchantBorder" }) do
		if button[key] then button[key]:SetAlpha(0) end
	end
	-- Countdown strip: the XP rail's strip, in gold, running down under the icon.
	local bar = CreateFrame("StatusBar", nil, button)
	bar:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -3)
	bar:SetPoint("TOPRIGHT", icon, "BOTTOMRIGHT", 0, -3)
	bar:SetHeight(BAR_H)
	bar:SetStatusBarTexture(ns.Art.Path("xpWhite") or "Interface\\Buttons\\WHITE8X8")
	bar:SetMinMaxValues(0, 1)
	local back = bar:CreateTexture(nil, "BACKGROUND")
	back:SetPoint("TOPLEFT", -1, 1)
	back:SetPoint("BOTTOMRIGHT", 1, -1)
	back:SetColorTexture(0.03, 0.02, 0.02, 0.85)
	bar:Hide()
	skin.socket, skin.bar, skin.harmful = socket, bar, harmful
	skins[button] = skin
	PlaceDuration(button)
	return skin
end

-- On: socket, cropped icon, Blizzard's borders hidden. Off: Blizzard's look back.
local function Dress(button, skin, on)
	skin.socket:SetShown(on)
	if not on then skin.bar:Hide() end
	button.Icon:SetTexCoord(on and 0.08 or 0, on and 0.92 or 1, on and 0.08 or 0, on and 0.92 or 1)
	for _, key in ipairs({ "DebuffBorder", "TempEnchantBorder" }) do
		if button[key] then button[key]:SetAlpha(on and 0 or 1) end
	end
	if button.Duration then
		if on then
			PlaceDuration(button)
		else
			button.Duration:SetAlpha(1)
			button.Duration:ClearAllPoints()
			button.Duration:SetPoint("TOP", button.Icon, "BOTTOM")
		end
	end
end

local function SkinFrame(frame, harmful)
	if not frame or type(frame.auraFrames) ~= "table" then return end
	for _, button in ipairs(frame.auraFrames) do
		if not button.isAuraAnchor then
			Skin(button, harmful)
		end
	end
end

-- Temporary weapon enchants come as time left only; the full length is the longest seen.
local enchantLength, enchantLeft = {}, {}

local function UpdateBars()
	local opt = Opt()
	for button, skin in pairs(skins) do
		local bar = skin.bar
		local left, total, hidden
		if opt.enabled and opt.bars and button:IsVisible() and not button.isExample then
			local info = button.buttonInfo
			left = button.timeLeft
			if type(info) == "table" and not Secret(info) and Secret(left) and Secret(info.duration) then
				-- In combat Blizzard's numbers are secret to us, but a status bar takes them as
				-- they are: it drains right, it just can't turn red (that needs a comparison).
				hidden = pcall(function()
					bar:SetMinMaxValues(0, info.duration)
					bar:SetValue(left)
				end)
			elseif type(info) == "table" and not Secret(info) and Readable(left) then
				total = info.duration
				local kind = info.auraType
				if Readable(kind) and kind == "TempEnchant" then
					local id = info.ID
					local key = Readable(id) and id or 0
					-- Time jumping up is a new enchant, which may be shorter than the last one.
					local last = enchantLeft[key]
					if not enchantLength[key] or left > enchantLength[key] or (last and left > last + 1) then
						enchantLength[key] = left
					end
					enchantLeft[key] = left
					total = enchantLength[key]
				end
			end
		end
		if hidden then
			bar:SetStatusBarColor(skin.harmful and 0.85 or 0.95, skin.harmful and 0.35 or 0.75, skin.harmful and 0.25 or 0.3, 1)
			bar:Show()
		elseif Readable(left) and Readable(total) and total > 0 then
			bar:SetMinMaxValues(0, 1)
			bar:SetValue(math.max(0, math.min(1, left / total)))
			if left <= BAR_WARN then
				bar:SetStatusBarColor(0.95, 0.22, 0.12, 1)
			elseif skin.harmful then
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

---------------------------------------------------------------------------

local hooked = {}

-- A layout change (Edit Mode settings) re-anchors each button's duration text; ours sits
-- under the strip.
local function Hook(frame)
	if not frame or hooked[frame] then return end
	hooked[frame] = true
	local container = frame.AuraContainer
	if container and container.UpdateGridLayout then
		hooksecurefunc(container, "UpdateGridLayout", function()
			if not Opt().enabled then return end
			for button in pairs(skins) do
				PlaceDuration(button)
			end
		end)
	end
end

---------------------------------------------------------------------------
-- The debuffs' own mover (#49): a bigger minimap can cover them where Edit Mode put them.
--
-- Until their mover is dragged nothing here touches DebuffFrame: Edit Mode places it, exactly
-- as before. Once dragged, DebuffFrame is anchored by Edit Mode's own corner (the one its icons
-- grow away from) to a holder frame of ours, and the mover drags the holder. Only ever out of
-- combat: anything asked for in combat waits for PLAYER_REGEN_ENABLED. That is all we do to
-- Blizzard's frame, ClearAllPoints and SetPoint; no field of theirs is written and none of
-- their layout code is called (handing it back re-applies the anchor Edit Mode last set,
-- read with GetPoint, rather than calling ApplySystemAnchor ourselves). Our hooks are
-- hooksecurefunc post-hooks, which run after Blizzard's code and leave it untainted.

local holder -- our stand-in for the debuffs' box; their mover drags it
local editPoints -- DebuffFrame's anchor as Edit Mode last set it: { point, rel, relPoint, x, y } each
local owned -- DebuffFrame is anchored to the holder
local pendingPlace -- a placement waiting for the end of combat
local editDragging -- Edit Mode is dragging the Debuff Frame

local function Pos()
	return Opt().debuffPos
end

-- Turned off, the buffs are Blizzard's again, place included.
local function Held()
	local opt = Opt()
	return opt.enabled and opt.debuffPos.moved and true or false
end

-- DebuffFrame's anchor points, or nil while it hangs on our holder (not Edit Mode's then).
local function ReadPoints(frame)
	local points = {}
	for i = 1, frame:GetNumPoints() do
		local point, rel, relPoint, x, y = frame:GetPoint(i)
		if rel == holder then return nil end
		points[i] = { point, rel, relPoint, x, y }
	end
	return #points > 0 and points or nil
end

-- The corner Edit Mode anchors it by: the icons grow away from it, so it stays put.
local function Corner()
	local first = editPoints and editPoints[1]
	return first and first[1] or "TOPRIGHT"
end

-- DebuffFrame's size in the holder's units, never too small to grab with no debuffs up.
local function DebuffBox(frame)
	local w, h = frame:GetSize()
	local k = frame:GetEffectiveScale() / holder:GetEffectiveScale()
	w, h = (w or 0) * k, (h or 0) * k
	return math.max(w, BASE_ICON * 3), math.max(h, BASE_ICON)
end

local function PlaceHolder(frame)
	local opt = Pos()
	holder:ClearAllPoints()
	if opt.moved then
		if not (opt.w and opt.h) then
			-- Just dropped: the box as it was dragged, so what you saw is where it stays.
			local w, h = holder:GetSize()
			if not w or w < 1 or not h or h < 1 then w, h = DebuffBox(frame) end
			opt.w, opt.h = w, h
		end
		holder:SetSize(opt.w, opt.h)
		local x, y = ns.MovedPoint(holder, opt)
		holder:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
	else
		-- Over the debuffs where Edit Mode has them, so the mover starts there.
		holder:SetSize(DebuffBox(frame))
		local corner = Corner()
		holder:SetPoint(corner, frame, corner)
	end
end

-- Hang DebuffFrame on the holder (the holder must not hang on it by now).
local function Take(frame)
	if not owned then editPoints = ReadPoints(frame) or editPoints end
	local corner = Corner()
	frame:ClearAllPoints()
	frame:SetPoint(corner, holder, corner)
	owned = true
end

-- Back where Edit Mode last put it. Never left hanging on the holder (which is about to hang
-- on it): with no anchor of Edit Mode's known, it stays where it is on the screen.
local function GiveBack(frame)
	owned = nil
	if editPoints then
		frame:ClearAllPoints()
		for _, p in ipairs(editPoints) do
			frame:SetPoint(p[1], p[2], p[3], p[4], p[5])
		end
	elseif not ReadPoints(frame) then
		local left, top = frame:GetLeft(), frame:GetTop()
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left or 0, top or 0)
	end
end

-- Apply the saved place (or Edit Mode's). Waits for the end of combat.
function ns.Auras.PlaceDebuffs()
	local _, frame = Frames()
	if not frame or not holder then return end
	if InCombatLockdown() then
		pendingPlace = true
		return
	end
	pendingPlace = nil
	if Held() then
		if not owned then editPoints = ReadPoints(frame) or editPoints end
		PlaceHolder(frame)
		Take(frame)
	else
		if owned then GiveBack(frame) end
		PlaceHolder(frame)
	end
end

function ns.Auras.ResetDebuffPosition()
	local opt = Pos()
	opt.moved, opt.mx, opt.my, opt.w, opt.h = false, 0, 0, nil, nil
	ns.Refresh()
end

local function InitDebuffMover()
	local _, frame = Frames()
	if not frame or not ns.MakeMover then return end
	holder = CreateFrame("Frame", "SanctuaryUIDebuffHolder", UIParent)
	holder:SetSize(BASE_ICON * 3, BASE_ICON)
	holder:EnableMouse(false)
	editPoints = ReadPoints(frame)
	PlaceHolder(frame)

	local mover = ns.MakeMover(holder, "Debuffs", Pos, "Reset its position in /sanctuary > Your buffs.")
	ns.Auras.mover = mover
	-- Shown when frames unlock: over the debuffs as they are now.
	mover:HookScript("OnShow", function()
		if not InCombatLockdown() and not owned and not Pos().moved then PlaceHolder(frame) end
	end)
	-- Picked up: the debuffs ride along with the drag (released, the mover saves the spot).
	mover:HookScript("OnDragStart", function()
		if InCombatLockdown() or owned or not Opt().enabled then return end
		local x, y = holder:GetCenter()
		if not x then return end
		editPoints = ReadPoints(frame) or editPoints
		holder:ClearAllPoints()
		holder:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
		Take(frame)
	end)

	-- Edit Mode re-anchors it (login, layout change, its own reset): note where, then put it
	-- back on the holder while it's ours.
	if type(frame.ApplySystemAnchor) == "function" then
		hooksecurefunc(frame, "ApplySystemAnchor", function(self)
			editPoints = ReadPoints(self) or editPoints
			owned = nil
			if Held() and not editDragging then ns.Auras.PlaceDebuffs() end
		end)
	end
	-- Dragged in Edit Mode: Edit Mode has it again, and our saved place goes.
	if type(frame.OnDragStart) == "function" and type(frame.OnDragStop) == "function" then
		hooksecurefunc(frame, "OnDragStart", function()
			editDragging = true
		end)
		hooksecurefunc(frame, "OnDragStop", function(self)
			editDragging = nil
			local opt = Pos()
			owned = nil
			editPoints = ReadPoints(self) or editPoints
			if opt.moved then
				opt.moved, opt.mx, opt.my, opt.w, opt.h = false, 0, 0, nil, nil
				ns.Print("debuffs: placed by Edit Mode again (their SanctuaryUI position is reset)")
			end
			if not InCombatLockdown() then PlaceHolder(self) end
		end)
	end
end

function ns.Auras.Update()
	if not Opt().enabled then return end
	local buffs, debuffs = Frames()
	SkinFrame(buffs, false)
	SkinFrame(debuffs, true)
	UpdateBars()
end

function ns.Auras.UpdateTimes()
	UpdateBars()
end

-- Position and size are Edit Mode's; only the duration text placement is ours.
function ns.Auras.Layout()
	if not Opt().enabled then return end
	for button in pairs(skins) do
		PlaceDuration(button)
	end
end

function ns.Auras.ApplySettings()
	if not ns.Auras.frame then return end
	ns.Auras.PlaceDebuffs()
	local enabled = Opt().enabled
	for button, skin in pairs(skins) do
		Dress(button, skin, enabled)
	end
	if enabled then
		ns.Auras.Update()
	end
end

-- /sanctuary auras: whether the player's buffs can be read right now, and what Blizzard's
-- buff frame is showing.
function ns.Auras.Report()
	local UA = C_UnitAuras or {}
	local function kind(value)
		if Secret(value) then return "secret" end
		return value == nil and "nil" or tostring(value)
	end
	ns.Print(("auras report: combat %s"):format(tostring(InCombatLockdown())))
	if UA.GetAuraSlots then
		local ok, a = pcall(UA.GetAuraSlots, "player", "HELPFUL")
		ns.Print(("slots: ok %s, %s"):format(tostring(ok), ok and kind(a) or tostring(a)))
	end
	local list, how = ns.ReadAuras("player", "HELPFUL")
	ns.Print(("addon read: %d buffs via %s"):format(#list, how))
	-- Routes other addons use, each tried on its own.
	if UA.GetUnitAuraInstanceIDs then
		local ok, ids = pcall(UA.GetUnitAuraInstanceIDs, "player", "HELPFUL")
		local n = ok and type(ids) == "table" and not Secret(ids) and #ids or -1
		ns.Print(("instance IDs: ok %s, count %d%s"):format(tostring(ok), n, ok and "" or (", " .. tostring(ids))))
	end
	local probe = ns.Auras.lastEvent
	ns.Print("last UNIT_AURA in combat: " .. (probe or "none seen"))
	if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
		local plate = C_NamePlate.GetNamePlateForUnit("player")
		local token = plate and (plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit))
		if token and UA.GetUnitAuras then
			local ok, auras = pcall(UA.GetUnitAuras, token, "HELPFUL")
			ns.Print(("player nameplate %s: ok %s, %s"):format(tostring(token), tostring(ok),
				ok and (type(auras) == "table" and not Secret(auras) and (#auras .. " buffs") or kind(auras)) or tostring(auras)))
		else
			ns.Print("player nameplate: none (personal resource display off?)")
		end
	end
	-- What Blizzard's own buttons hold, and what the instance-ID calls give for them.
	local blizzBuffs = Frames()
	if blizzBuffs then
		local n = 0
		for _, button in ipairs(blizzBuffs.auraFrames or {}) do
			if button:IsShown() and not button.isAuraAnchor and n < 6 then
				n = n + 1
				local info = button.buttonInfo
				local id = type(info) == "table" and not Secret(info) and info.auraInstanceID
				local data, timer, left = "-", "-", "-"
				if Readable(id) then
					local ok, aura = pcall(UA.GetAuraDataByAuraInstanceID, "player", id)
					data = not ok and ("err " .. tostring(aura)) or type(aura) ~= "table" and kind(aura)
						or ("spell %s, duration %s"):format(kind(aura.spellId), kind(aura.duration))
					if UA.GetAuraDuration then
						local ok2, object = pcall(UA.GetAuraDuration, "player", id)
						timer = not ok2 and ("err " .. tostring(object)) or object == nil and "none" or "object"
						if ok2 and object then
							local ok3, r = pcall(object.GetRemainingDuration, object)
							left = ok3 and kind(r) or "err"
						end
					end
				end
				local icon = button.Icon and button.Icon:GetTexture()
				ns.Print(("blizz buff %d: instance %s, texture %s, timeLeft %s, data %s, duration object %s (left %s)"):format(
					n, type(info) == "table" and not Secret(info) and kind(info.auraInstanceID) or kind(info),
					kind(icon), kind(button.timeLeft), data, timer, left))
			end
		end
	end
	local buffs, debuffs = Frames()
	for _, pair in ipairs({ { "BuffFrame", buffs }, { "DebuffFrame", debuffs } }) do
		local name, frame = pair[1], pair[2]
		if frame then
			local shown, timed = 0, 0
			for _, button in ipairs(frame.auraFrames or {}) do
				if button:IsShown() and not button.isAuraAnchor then
					shown = shown + 1
					if Readable(button.timeLeft) then timed = timed + 1 end
				end
			end
			local point, rel = frame:GetPoint(1)
			ns.Print(("%s: %d icons shown (%d with readable time), visible %s, scale %.2f, anchored %s to %s"):format(
				name, shown, timed, tostring(frame:IsVisible()), frame:GetScale(), tostring(point),
				rel and rel.GetName and tostring(rel:GetName()) or "?"))
		else
			ns.Print(name .. ": missing")
		end
	end
	ns.Print(("debuff position: %s%s"):format(Pos().moved and "SanctuaryUI mover" or "Edit Mode",
		pendingPlace and " (waiting for the end of combat)" or ""))
end

function ns.Auras.Init()
	-- Drives the countdown strips and dresses new buttons; Blizzard's frames do the rest.
	local frame = CreateFrame("Frame", "SanctuaryUIAuras", UIParent)
	ns.Auras.frame = frame

	local buffs, debuffs = Frames()
	Hook(buffs)
	Hook(debuffs)
	InitDebuffMover()

	local wait = 0
	frame:SetScript("OnUpdate", function(_, elapsed)
		wait = wait - elapsed
		if wait > 0 then return end
		wait = 0.1 -- smooth countdown strips
		UpdateBars()
	end)

	frame:RegisterUnitEvent("UNIT_AURA", "player")
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	frame:RegisterEvent("PLAYER_REGEN_ENABLED")
	frame:SetScript("OnEvent", function(_, event, _, info)
		if event == "PLAYER_REGEN_ENABLED" then
			if pendingPlace then ns.Auras.PlaceDebuffs() end
			return
		end
		-- Probe for /sanctuary auras: can the event's own aura data be read in combat?
		if event == "UNIT_AURA" and InCombatLockdown() then
			pcall(function()
				if Secret(info) then
					ns.Auras.lastEvent = "payload secret"
					return
				end
				if type(info) ~= "table" then
					ns.Auras.lastEvent = "payload " .. type(info)
					return
				end
				local added = info.addedAuras
				local first = type(added) == "table" and not Secret(added) and added[1]
				ns.Auras.lastEvent = ("full %s, added %s%s"):format(
					Secret(info.isFullUpdate) and "secret" or tostring(info.isFullUpdate),
					Secret(added) and "secret" or type(added) == "table" and #added or "none",
					type(first) == "table" and not Secret(first) and (", first: instance %s, spell %s, duration %s"):format(
						Secret(first.auraInstanceID) and "secret" or tostring(first.auraInstanceID),
						Secret(first.spellId) and "secret" or tostring(first.spellId),
						Secret(first.duration) and "secret" or tostring(first.duration)) or "")
			end)
		end
		ns.Auras.Update()
	end)
	ns.Auras.ApplySettings()
end
