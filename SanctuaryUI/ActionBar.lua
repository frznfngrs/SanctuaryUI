SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.ActionBar = ns.ActionBar or {}

local PRIMARY = 9
local ROW_MAX = 12
local PAGES = 18
local PETS = 10
-- Top of the console's centre ornament in the sheet; rows start above it.
local CONSOLE_TOP_Y = 58
local LayoutTiers -- the console's art for docked rows (below)

-- Rows stacked above the console, bottom to top.
local ROW_IDS = { 2, 3, 4, 5, 6, 7, 8, 9 }
ns.ActionBar.ROW_IDS = ROW_IDS

-- Blizzard binding names for each action bar page, so binds set in Key Bindings carry over.
-- Pages without one (2, 7-12) bind through CLICK bindings set by hover-binding.
local BINDING_BY_PAGE = {
	[3] = "MULTIACTIONBAR3BUTTON%d", -- right bar
	[4] = "MULTIACTIONBAR4BUTTON%d", -- right bar 2
	[5] = "MULTIACTIONBAR2BUTTON%d", -- bottom right
	[6] = "MULTIACTIONBAR1BUTTON%d", -- bottom left
	[13] = "MULTIACTIONBAR5BUTTON%d",
	[14] = "MULTIACTIONBAR6BUTTON%d",
	[15] = "MULTIACTIONBAR7BUTTON%d",
}
ns.ActionBar.PAGE_NAMES = {
	[1] = "Page 1 (main bar)",
	[2] = "Page 2",
	[3] = "Page 3 (right bar)",
	[4] = "Page 4 (right bar 2)",
	[5] = "Page 5 (bottom right)",
	[6] = "Page 6 (bottom left)",
	[7] = "Page 7",
	[8] = "Page 8",
	[9] = "Page 9",
	[10] = "Page 10",
	[13] = "Page 13 (bar 5)",
	[14] = "Page 14 (bar 6)",
	[15] = "Page 15 (bar 7)",
}

-- Stance and form pages, matching Bartender4's Forever defaults for bar 1.
local CLASS_PAGES = {
	DRUID = {
		{ key = "prowl", label = "Cat Form, prowling", cond = "[bonusbar:1,stealth:1]", page = 8 },
		{ key = "cat", label = "Cat Form", cond = "[bonusbar:1]", page = 7 },
		{ key = "bear", label = "Bear Form", cond = "[bonusbar:3]", page = 9 },
	},
	ROGUE = {
		{ key = "stealth", label = "Stealth", cond = "[bonusbar:1]", page = 7 },
	},
	WARRIOR = {
		{ key = "battle", label = "Battle Stance", cond = "[bonusbar:1]", page = 7 },
		{ key = "defensive", label = "Defensive Stance", cond = "[bonusbar:2]", page = 8 },
		{ key = "berserker", label = "Berserker Stance", cond = "[bonusbar:3]", page = 9 },
	},
}
ns.ActionBar.CLASS_PAGES = CLASS_PAGES

-- Every main-bar socket prints its key inside the plaque under it (8.5 sheet px below the
-- socket edge), where D3 drew the mouse icon on the gold pair. 1100 / 1416 is the console scale.
local PLAQUE_OFFSET = -8.5 * 1100 / 1416
ns.ActionBar.PLAQUE_OFFSET = PLAQUE_OFFSET
local SOCKET_H = 67 * 1100 / 1416 -- a console socket's height, in console units

-- Console skill icons as a share of their socket (Bars > Main bar > Icon size): smaller icons
-- sit centred in the socket with its stone around them, independent of the console's scale.
local function IconSize()
	local k = tonumber(ns.DB().iconSize) or 1
	return math.max(0.6, math.min(1, k))
end
ns.ActionBar.IconSize = IconSize

-- Size a button inside a console socket; the socket stays the click area.
local function FitSocket(button, slot)
	local k = IconSize()
	local w, h = slot.w * k, slot.h * k
	local px, py = (slot.w - w) / 2, (slot.h - h) / 2
	button:SetSize(w, h)
	button:SetHitRectInsets(-px, -px, -py, -py)
end

local function ButtonConfig(binding, onPlaque)
	local opt = ns.DB().buttons
	local hotkeyPosition = {
		anchor = "BOTTOM",
		relAnchor = "BOTTOM",
		offsetX = 0,
		offsetY = 3,
	}
	if onPlaque then
		-- From the button's bottom edge, which rises off the socket's as the icon shrinks.
		local offsetY = PLAQUE_OFFSET - SOCKET_H * (1 - IconSize()) / 2
		hotkeyPosition = { anchor = "CENTER", relAnchor = "BOTTOM", offsetX = 0, offsetY = offsetY }
	end
	local cooldownCount
	if opt.cooldownNumbers == "show" then
		cooldownCount = true
	elseif opt.cooldownNumbers == "hide" then
		cooldownCount = false
	end
	return {
		outOfRangeColoring = opt.range,
		tooltip = opt.tooltips,
		showGrid = opt.grid,
		cooldownCount = cooldownCount,
		hideElements = {
			macro = not opt.macroNames,
			hotkey = not opt.hotkeys,
			equipped = false,
			border = true,
			borderIfEmpty = true,
		},
		keyBoundTarget = binding or false,
		keyBoundClickButton = "Keybind",
		flyoutDirection = "UP",
		actionButtonUI = true,
		assistedHighlight = true,
		colors = {
			range = { 0.85, 0.15, 0.12 },
			mana = { 0.35, 0.45, 0.85 },
		},
		text = {
			hotkey = {
				font = { font = false, size = 11, flags = "OUTLINE" },
				color = { 0.86, 0.72, 0.42 },
				position = hotkeyPosition,
				justifyH = "CENTER",
			},
			count = {
				font = { font = false, size = 12, flags = "OUTLINE" },
				color = { 1, 1, 1 },
				position = {
					anchor = "BOTTOMRIGHT",
					relAnchor = "BOTTOMRIGHT",
					offsetX = -1,
					offsetY = 1,
				},
				justifyH = "RIGHT",
			},
			macro = {
				font = { font = false, size = 10, flags = "OUTLINE" },
				color = { 1, 1, 1 },
				position = { anchor = "BOTTOM", relAnchor = "BOTTOM", offsetX = 0, offsetY = 12 },
				justifyH = "CENTER",
			},
		},
	}
end

-- The main bar's page driver, built from the paging settings. A custom conditional replaces it.
function ns.ActionBar.PageDriver()
	local paging = ns.DB().paging
	local custom = paging.custom and strtrim(paging.custom) or ""
	if custom ~= "" then
		return custom
	end
	local parts = {}
	if paging.possess then
		parts[#parts + 1] = "[overridebar][possessbar][shapeshift]possess;[bonusbar:5]dragon"
	end
	for _, mod in ipairs({ "ctrl", "alt", "shift" }) do
		local page = tonumber(paging[mod]) or 0
		if page > 0 then
			parts[#parts + 1] = ("[mod:%s]%d"):format(mod, page)
		end
	end
	if paging.barPaging then
		parts[#parts + 1] = "[bar:2]2;[bar:3]3;[bar:4]4;[bar:5]5;[bar:6]6"
	end
	if paging.stances then
		local _, class = UnitClass("player")
		local map = CLASS_PAGES[class]
		if map then
			for i = 1, #map do
				if paging.forms[class .. "." .. map[i].key] then
					parts[#parts + 1] = map[i].cond .. map[i].page
				end
			end
		end
	end
	parts[#parts + 1] = "0"
	return table.concat(parts, ";")
end

-- What a row shows: actions, binding names, paging. Source "main" is actions 10-12 of the
-- main bar, paged with it; a number is a fixed action bar page.
function ns.ActionBar.RowSpec(n)
	local opt = ns.DB().rows[n]
	if opt.source == "main" then
		return {
			paged = true,
			firstAction = PRIMARY + 1,
			count = math.max(1, math.min(12 - PRIMARY, opt.count)),
			binding = "ACTIONBUTTON%d",
			bindingOffset = PRIMARY,
		}
	end
	local page = tonumber(opt.source) or 2
	return {
		paged = false,
		firstAction = (page - 1) * 12 + 1,
		count = math.max(1, math.min(ROW_MAX, opt.count)),
		binding = BINDING_BY_PAGE[page],
		bindingOffset = 0,
	}
end

-- Which console row (1 = just above the main sockets) a bar is docked in, or nil.
local function DockIndex(n)
	for j, id in ipairs(ns.DockedRows()) do
		if id == n then return j end
	end
end
ns.ActionBar.DockIndex = DockIndex

local function Visibility(opt)
	local base = "[petbattle][overridebar][possessbar][vehicleui] hide;"
	if opt.visibility == "combat" then
		return base .. " [combat] show; hide"
	elseif opt.visibility == "nocombat" then
		return base .. " [combat] hide; show"
	elseif opt.visibility == "custom" and opt.custom and strtrim(opt.custom) ~= "" then
		return opt.custom
	end
	return base .. " show"
end

local function BindKeys(owner, bindingFormat, buttons, clickButton, offset)
	if InCombatLockdown() or not owner then return end
	ClearOverrideBindings(owner)
	if not bindingFormat then return end
	clickButton = clickButton or "Keybind"
	for i = 1, #buttons do
		local binding = bindingFormat:format((offset or 0) + i)
		local name = buttons[i]:GetName()
		for k = 1, select("#", GetBindingKey(binding)) do
			local key = select(k, GetBindingKey(binding))
			if key and key ~= "" then
				SetOverrideBindingClick(owner, false, key, name, clickButton)
			end
		end
	end
end

function ns.ActionBar.ReassignBindings()
	if InCombatLockdown() then return end
	BindKeys(ns.PrimaryHeader, "ACTIONBUTTON%d", ns.ActionBar.primary or {}, "Keybind")
	if ns.ActionBar.rows then
		for _, n in ipairs(ROW_IDS) do
			local row = ns.ActionBar.rows[n]
			if row then
				local spec = ns.ActionBar.RowSpec(n)
				local active = {}
				for i = 1, spec.count do
					active[i] = row.buttons[i]
				end
				BindKeys(row.header, ns.DB().rows[n].enabled and spec.binding, active, "Keybind", spec.bindingOffset)
			end
		end
	end
	BindKeys(ns.PetHeader, "BONUSACTIONBUTTON%d", ns.ActionBar.pets or {}, "LeftButton")
	if ns.ActionBar.primary then
		for i = 1, #ns.ActionBar.primary do
			ns.ActionBar.primary[i]:UpdateAction()
		end
	end
end

-- The console's art for docked rows: with none, the whole frame as D3 drew it; with some, the
-- frame without its rail band and, over it, the band lifted above that many rows of sockets,
-- walled in out to the globes (one piece of art per height).
local TIER_X, TIER_W, CREST_H = 200, 1200, 108
local TIER_ATLAS_Y = { 0, 208 }
function LayoutTiers(metrics)
	local frame = ns.ConsoleFrame
	local tiers = math.min(metrics.tiers, #TIER_ATLAS_Y)
	local s = metrics.scale
	local lifted = tiers > 0 and ns.Art.Path("consoleBase") and ns.Art.Path("consoleTiers") and true or false
	if ns.Trough.lifted ~= lifted and ns.Art.Path("frame") then
		ns.Art.Apply(ns.Trough, lifted and "consoleBase" or "frame")
		ns.Trough:SetTexCoord(unpack(ns.FRAME_TEXCOORD))
		ns.Trough.lifted = lifted
	end
	if not frame.tier then
		frame.tier = frame:CreateTexture(nil, "ARTWORK", nil, 1)
		ns.Art.Apply(frame.tier, "consoleTiers")
	end
	frame.tier:SetShown(lifted)
	if lifted then
		local h = CREST_H + ns.TIER_H * tiers
		local y0 = TIER_ATLAS_Y[tiers]
		frame.tier:SetTexCoord(0, TIER_W / 2048, y0 / 512, (y0 + h) / 512)
		frame.tier:SetSize(TIER_W * s, h * s)
		frame.tier:ClearAllPoints()
		frame.tier:SetPoint("TOPLEFT", frame, "TOPLEFT", TIER_X * s, metrics.lift)
	end
end

function ns.ActionBar.Layout()
	local cluster = ns.Cluster
	local metrics = ns.Metrics and ns.Metrics()
	if not cluster or not ns.ActionBar.primary or not metrics then return end
	local base = metrics.baseY
	cluster:SetSize(metrics.width + 40, metrics.height + 80 + metrics.lift)
	-- Clamp to the console art, not the padded cluster: it may touch the screen's edges.
	cluster:SetClampRectInsets(20, -20, -80, 0)

	if ns.ConsoleFrame then
		ns.ConsoleFrame:SetSize(metrics.width, metrics.height)
		ns.ConsoleFrame:ClearAllPoints()
		ns.ConsoleFrame:SetPoint("CENTER", cluster, "BOTTOM", 0, base)
		ns.ConsoleFrame:SetFrameLevel(cluster:GetFrameLevel() + ns.LEVEL.console)
		LayoutTiers(metrics)
	end
	local above = cluster:GetFrameLevel() + ns.LEVEL.buttons
	if ns.PrimaryHeader then ns.PrimaryHeader:SetFrameLevel(above) end
	if ns.ActionBar.rows then
		for _, row in pairs(ns.ActionBar.rows) do
			row.header:SetFrameLevel(above)
		end
	end
	if ns.PetHeader then ns.PetHeader:SetFrameLevel(above) end
	if ns.LeaveButton then ns.LeaveButton:SetFrameLevel(above + 2) end

	for i = 1, PRIMARY do
		local slot = metrics.slots[i]
		local button = ns.ActionBar.primary[i]
		FitSocket(button, slot)
		button:ClearAllPoints()
		button:SetPoint("CENTER", cluster, "BOTTOM", slot.x, base + slot.y)
	end

	-- Bars stack from the top of the centre ornament, or of your level's plaque over it.
	local top = ns.DB().levelPlaque ~= false and metrics.levelPlaque and 28 or CONSOLE_TOP_Y
	local consoleTop = base + metrics.height / 2 - top * metrics.scale + metrics.lift
	local rowY = consoleTop + 6
	if ns.ActionBar.rows then
		for _, n in ipairs(ROW_IDS) do
			local row = ns.ActionBar.rows[n]
			local opt = ns.DB().rows[n]
			local dock = row and opt.enabled and DockIndex(n)
			if row and row.buttons[1].sanctuarySocketTex then
				-- Docked buttons sit in the console's own sockets.
				for i = 1, ROW_MAX do
					local tex = row.buttons[i].sanctuarySocketTex
					if tex then tex:SetShown(not dock) end
				end
			end
			if dock then
				local sockets = metrics.dock[dock]
				local anchor = row.anchor
				anchor:ClearAllPoints()
				anchor:SetPoint("TOPLEFT", cluster, "BOTTOM", sockets[1].x - sockets[1].w / 2, base + sockets[1].y + sockets[1].h / 2)
				anchor:SetPoint("BOTTOMRIGHT", cluster, "BOTTOM", sockets[12].x + sockets[12].w / 2, base + sockets[12].y - sockets[12].h / 2)
				for i = 1, ns.ActionBar.RowSpec(n).count do
					local slot, button = sockets[i], row.buttons[i]
					FitSocket(button, slot)
					button:ClearAllPoints()
					button:SetPoint("CENTER", cluster, "BOTTOM", slot.x, base + slot.y)
				end
			elseif row and opt.enabled then
				local spec = ns.ActionBar.RowSpec(n)
				local bw = metrics.slots[1].w * opt.scale
				local bh = metrics.slots[1].h * opt.scale
				local gap = opt.spacing
				local cols = math.max(1, math.min(spec.count, opt.perLine or 12))
				local lines = math.ceil(spec.count / cols)
				-- The stone socket draws past the button, more above and below than at the sides.
				local lineGap = gap + bh * 0.16
				local width = cols * bw + (cols - 1) * gap
				local height = lines * bh + (lines - 1) * lineGap
				local anchor = row.anchor
				anchor:SetSize(width, height)
				anchor:ClearAllPoints()
				if opt.moved then
					anchor:SetPoint("CENTER", UIParent, "BOTTOMLEFT", opt.mx, opt.my)
				else
					anchor:SetPoint("BOTTOM", cluster, "BOTTOM", 0, rowY)
					rowY = rowY + height + bh * 0.2 + math.max(4, gap)
				end
				for i = 1, spec.count do
					local button = row.buttons[i]
					local col = (i - 1) % cols
					local line = math.floor((i - 1) / cols)
					button:SetSize(bw, bh)
					button:SetHitRectInsets(0, 0, 0, 0)
					button:ClearAllPoints()
					button:SetPoint("CENTER", anchor, "TOPLEFT", col * (bw + gap) + bw / 2, -(line * (bh + lineGap) + bh / 2))
				end
			end
		end
	end
	ns.ActionBar.UpdateMovers()
	ns.ActionBar.topY = rowY
	local extraY = rowY

	if ns.Menu and ns.Menu.Layout then
		ns.Menu.Layout(metrics, base)
	end
	if ns.LeaveButton then
		ns.LeaveButton:SetSize(28, 28)
		ns.LeaveButton:ClearAllPoints()
		ns.LeaveButton:SetPoint("CENTER", cluster, "BOTTOM", metrics.resource.x + metrics.resource.size * 0.72, base + metrics.resource.y)
	end

	local petSize, petGap = 28, 4
	local petWidth = PETS * petSize + (PETS - 1) * petGap
	local petLeft = -petWidth / 2 + petSize / 2
	for i = 1, PETS do
		local button = ns.ActionBar.pets[i]
		button:SetSize(petSize, petSize)
		button:ClearAllPoints()
		button:SetPoint("CENTER", cluster, "BOTTOM", petLeft + (i - 1) * (petSize + petGap), extraY + petSize / 2 + 4)
	end

	if ns.ExtraActionHost then
		ns.ExtraActionHost:SetSize(68, 68)
		ns.ExtraActionHost:ClearAllPoints()
		ns.ExtraActionHost:SetPoint("CENTER", cluster, "BOTTOM", 0, extraY + petSize + 46)
	end
end

function ns.ActionBar.RowEnabled(n)
	local rows = ns.DB().rows
	return rows[n] and rows[n].enabled or false
end

---------------------------------------------------------------------------
-- Keybinds follow a bar's buttons. A button's keys sit on its binding: a Blizzard name
-- (MULTIACTIONBAR3BUTTON1) or, for pages without one, a CLICK binding on the button itself.
-- When a bar changes page its keys move to the new binding. When a button goes unused (bar
-- disabled or shortened) its CLICK keys are put aside, since they would still click the
-- hidden button, and come back when the button is used again.

local function ClickAction(button)
	return ("CLICK %s:Keybind"):format(button:GetName())
end

local function KeysOf(action)
	return { GetBindingKey(action) }
end

-- The binding each row button will answer to after this apply, or nil when unused.
local function RowActions(n)
	local row = ns.ActionBar.rows[n]
	local spec = ns.ActionBar.RowSpec(n)
	local actions = {}
	if ns.DB().rows[n].enabled then
		for i = 1, spec.count do
			actions[i] = spec.binding and spec.binding:format(spec.bindingOffset + i) or ClickAction(row.buttons[i])
		end
	end
	return actions
end

local function StashedKeys(n)
	local char = ns.db and ns.db.char
	if not char then return {} end
	char.rowKeys = char.rowKeys or {}
	char.rowKeys[n] = char.rowKeys[n] or {}
	return char.rowKeys[n]
end

local function MoveRowBindings()
	local rows = ns.ActionBar.rows
	if not rows or InCombatLockdown() then return end
	local new, used = {}, {}
	for i = 1, PRIMARY do
		used["ACTIONBUTTON" .. i] = true
	end
	for _, n in ipairs(ROW_IDS) do
		new[n] = RowActions(n)
		for _, action in pairs(new[n]) do
			used[action] = true
		end
	end
	local changed = false
	local function Bind(keys, action)
		for _, key in ipairs(keys) do
			SetBinding(key, action)
			changed = true
		end
	end
	for _, n in ipairs(ROW_IDS) do
		local row = rows[n]
		local stash = StashedKeys(n)
		for i = 1, ROW_MAX do
			local button = row.buttons[i]
			local click = ClickAction(button)
			local action = new[n][i]
			local old = row.bound and row.bound[i]
			if action then
				-- Keys left on the button's own CLICK binding, and on the binding it answered to
				-- before (unless another button still answers to that one).
				if action ~= click then
					Bind(KeysOf(click), action)
				end
				if old and old ~= action and old ~= click and not used[old] then
					Bind(KeysOf(old), action)
				end
				if stash[i] then
					for _, key in ipairs(stash[i]) do
						local current = GetBindingAction(key)
						if not current or current == "" then
							Bind({ key }, action)
						end
					end
					stash[i] = nil
				end
			else
				local keys = KeysOf(click)
				if #keys > 0 then
					stash[i] = stash[i] or {}
					for _, key in ipairs(keys) do
						tinsert(stash[i], key)
						SetBinding(key, nil)
					end
					changed = true
				end
			end
		end
		row.bound = new[n]
	end
	if changed then
		local set = GetCurrentBindingSet and GetCurrentBindingSet() or 1
		if SaveBindings then
			SaveBindings(set)
		elseif AttemptToSaveBindings then
			AttemptToSaveBindings(set)
		end
	end
end

-- Point a row's buttons at its source: actions, paging, binding names, button count.
local function ApplyRow(n)
	local row = ns.ActionBar.rows[n]
	local opt = ns.DB().rows[n]
	local spec = ns.ActionBar.RowSpec(n)
	local header = row.header
	for i = 1, ROW_MAX do
		local button = row.buttons[i]
		if i <= spec.count then
			local action = spec.firstAction + i - 1
			button:SetParent(header)
			button:SetState(0, "action", action)
			for page = 1, PAGES do
				-- Fixed rows hold the same action on every page, so paging cannot move them.
				button:SetState(page, "action", spec.paged and ((page - 1) * 12 + action) or action)
			end
			local binding = spec.binding and spec.binding:format(spec.bindingOffset + i)
			button:UpdateConfig(ButtonConfig(binding, DockIndex(n) ~= nil))
			button:Show()
		else
			button:SetParent(row.spare)
		end
	end
	if spec.paged then
		RegisterStateDriver(header, "page", ns.ActionBar.PageDriver())
	else
		UnregisterStateDriver(header, "page")
		header:SetAttribute("state-page", "0")
	end
	if opt.enabled then
		RegisterStateDriver(header, "visibility", Visibility(opt))
	else
		UnregisterStateDriver(header, "visibility")
		header:Hide()
	end
	row.alpha = opt.alpha
	row.mouseover = opt.mouseover
	header:SetAlpha(opt.mouseover and 0 or opt.alpha)
end

---------------------------------------------------------------------------
-- Movers: with frames unlocked, each enabled row shows a labelled box that drags the row.

-- A labelled box that drags a frame while frames are unlocked. opt holds the position:
-- moved, mx, my (the frame's centre, UIParent coordinates at the frame's scale).
function ns.MakeMover(anchor, label, opt, hint)
	local mover = CreateFrame("Frame", nil, anchor)
	mover:SetAllPoints()
	mover:SetFrameStrata("DIALOG")
	mover:EnableMouse(true)
	mover:RegisterForDrag("LeftButton")
	mover:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" then
			ns.SetLocked(true)
		end
	end)
	local edge = mover:CreateTexture(nil, "BACKGROUND")
	edge:SetPoint("TOPLEFT", -1, 1)
	edge:SetPoint("BOTTOMRIGHT", 1, -1)
	edge:SetColorTexture(0.86, 0.72, 0.42, 0.8)
	local bg = mover:CreateTexture(nil, "BORDER")
	bg:SetAllPoints()
	bg:SetColorTexture(0.08, 0.05, 0.03, 0.85)
	local text = mover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	text:SetPoint("CENTER")
	text:SetText(label)
	mover:SetScript("OnDragStart", function()
		if InCombatLockdown() then return end
		anchor:SetMovable(true)
		anchor:StartMoving()
	end)
	mover:SetScript("OnDragStop", function()
		anchor:StopMovingOrSizing()
		-- Our profile holds the position, not WoW's layout cache.
		anchor:SetUserPlaced(false)
		local x, y = anchor:GetCenter()
		if x then
			local o = opt()
			o.moved, o.mx, o.my = true, x, y
		end
		ns.Refresh()
	end)
	mover:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(label)
		GameTooltip:AddLine("Drag to move. Right-click to lock all frames.", 1, 1, 1, true)
		if hint then
			GameTooltip:AddLine(hint, 0.7, 0.7, 0.7, true)
		end
		GameTooltip:Show()
	end)
	mover:SetScript("OnLeave", GameTooltip_Hide)
	mover:Hide()
	return mover
end

local function MakeMover(n, row)
	return ns.MakeMover(row.anchor, "Bar " .. n, function() return ns.DB().rows[n] end, "Reset its position in /sanctuary > Bars.")
end

-- While frames are unlocked, a panel at the top of the screen says so and locks them again.
local function UnlockPanel()
	if ns.UnlockPanel then return ns.UnlockPanel end
	local panel = CreateFrame("Frame", "SanctuaryUIUnlockPanel", UIParent)
	panel:SetSize(340, 64)
	panel:SetPoint("TOP", UIParent, "TOP", 0, -120)
	panel:SetFrameStrata("DIALOG")
	panel:EnableMouse(true)
	local edge = panel:CreateTexture(nil, "BACKGROUND")
	edge:SetAllPoints()
	edge:SetColorTexture(0.86, 0.72, 0.42, 0.85)
	local bg = panel:CreateTexture(nil, "BORDER")
	bg:SetPoint("TOPLEFT", 1, -1)
	bg:SetPoint("BOTTOMRIGHT", -1, 1)
	bg:SetColorTexture(0.06, 0.04, 0.03, 0.95)
	local text = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	text:SetPoint("TOP", 0, -10)
	text:SetText("SanctuaryUI frames unlocked: drag the console or a bar")
	local lock = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	lock:SetSize(110, 22)
	lock:SetPoint("BOTTOM", 0, 9)
	lock:SetText("Lock")
	lock:SetScript("OnClick", function() ns.SetLocked(true) end)
	panel:Hide()
	ns.UnlockPanel = panel
	return panel
end

-- The console's own mover: most of the console is buttons and globes, so this gives the
-- whole piece something to grab while unlocked.
local function ConsoleMover()
	if ns.ConsoleMover then return ns.ConsoleMover end
	local mover = CreateFrame("Frame", "SanctuaryUIConsoleMover", ns.Cluster)
	mover:SetAllPoints(ns.ConsoleFrame)
	mover:SetFrameStrata("DIALOG")
	mover:EnableMouse(true)
	mover:RegisterForDrag("LeftButton")
	local edge = mover:CreateTexture(nil, "BACKGROUND")
	edge:SetPoint("TOPLEFT", -1, 1)
	edge:SetPoint("BOTTOMRIGHT", 1, -1)
	edge:SetColorTexture(0.86, 0.72, 0.42, 0.8)
	local bg = mover:CreateTexture(nil, "BORDER")
	bg:SetAllPoints()
	bg:SetColorTexture(0.08, 0.05, 0.03, 0.45)
	local label = mover:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	label:SetPoint("CENTER")
	label:SetText("Console")
	mover:SetScript("OnDragStart", function()
		if InCombatLockdown() then return end
		ns.Cluster:StartMoving()
	end)
	mover:SetScript("OnDragStop", function()
		ns.Cluster:StopMovingOrSizing()
		ns.Cluster:SetUserPlaced(false)
		ns.SavePosition()
	end)
	mover:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" then
			ns.SetLocked(true)
		end
	end)
	mover:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Console")
		GameTooltip:AddLine("Drag to move the globes, bars and menu. Right-click to lock all frames.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	mover:SetScript("OnLeave", GameTooltip_Hide)
	mover:Hide()
	ns.ConsoleMover = mover
	return mover
end

function ns.ActionBar.UpdateMovers()
	if not ns.ActionBar.rows then return end
	local unlocked = not ns.DB().locked and not InCombatLockdown()
	UnlockPanel():SetShown(unlocked)
	if ns.ConsoleFrame then
		ConsoleMover():SetShown(unlocked)
	end
	if ns.TargetPlate and ns.TargetPlate.mover then
		ns.TargetPlate.mover:SetShown(unlocked and ns.DB().target.enabled)
	end
	if ns.Portraits and ns.Portraits.mover then
		ns.Portraits.mover:SetShown(unlocked and ns.DB().portraits.enabled)
	end
	if ns.Auras and ns.Auras.mover then
		ns.Auras.mover:SetShown(unlocked and ns.DB().auras.enabled)
	end
	if ns.Stance and ns.Stance.mover then
		ns.Stance.mover:SetShown(unlocked and ns.Stance.HasForms())
	end
	if ns.Totem and ns.Totem.UpdateMovers then
		ns.Totem.UpdateMovers(unlocked)
	end
	for _, n in ipairs(ROW_IDS) do
		local row = ns.ActionBar.rows[n]
		row.mover:SetShown(unlocked and ns.DB().rows[n].enabled and not DockIndex(n))
	end
end

function ns.ActionBar.ResetRowPosition(n)
	local opt = ns.DB().rows[n]
	opt.moved, opt.mx, opt.my = false, 0, 0
	ns.Refresh()
end

-- Mouseover rows stay invisible until the mouse is over one of their buttons.
local function UpdateMouseover()
	for _, n in ipairs(ROW_IDS) do
		local row = ns.ActionBar.rows[n]
		if row and row.mouseover and row.header:IsShown() then
			local over = false
			for i = 1, ROW_MAX do
				local button = row.buttons[i]
				if button:IsVisible() and button:IsMouseOver() then
					over = true
					break
				end
			end
			row.header:SetAlpha(over and row.alpha or 0)
		end
	end
end

-- Button lock, the way Bartender4 does it: LibActionButton reads "buttonlock" (locked buttons
-- still pick up with the pickup modifier, Shift by default), and "unlockedpreventdrag" stops
-- cast-on-key-down from firing on a mouse press so an unlocked button can be dragged.
local function ApplyLock(button)
	local locked = ns.DB().buttons.lock and true or nil
	button:SetAttribute("buttonlock", locked)
	button:SetAttribute("unlockedpreventdrag", true)
end

function ns.ActionBar.ForEachButton(fn)
	for i = 1, #(ns.ActionBar.primary or {}) do
		fn(ns.ActionBar.primary[i])
	end
	for _, row in pairs(ns.ActionBar.rows or {}) do
		for i = 1, #row.buttons do
			fn(row.buttons[i])
		end
	end
end

function ns.ActionBar.ApplySettings()
	if InCombatLockdown() or not ns.ActionBar.primary then return end
	ns.ActionBar.ForEachButton(ApplyLock)
	-- Keep Blizzard's own setting in step, for anything else that reads it.
	local SetCVar = C_CVar and C_CVar.SetCVar or SetCVar
	if SetCVar then
		pcall(SetCVar, "lockActionBars", ns.DB().buttons.lock and "1" or "0")
	end
	for i = 1, PRIMARY do
		ns.ActionBar.primary[i]:UpdateConfig(ButtonConfig("ACTIONBUTTON" .. i, true))
	end
	RegisterStateDriver(ns.PrimaryHeader, "page", ns.ActionBar.PageDriver())
	MoveRowBindings()
	for _, n in ipairs(ROW_IDS) do
		ApplyRow(n)
	end
	if ns.PetHeader then
		RegisterStateDriver(ns.PetHeader, "visibility", ns.DB().pets and "[pet,nopetbattle,novehicleui] show; hide" or "hide")
	end
	ns.ActionBar.ReassignBindings()
end

-- Kept for the slash command: toggling a row is a settings change.
function ns.ActionBar.ApplyRows()
	if not ns.ActionBar.rows or InCombatLockdown() then return end
	MoveRowBindings()
	for _, n in ipairs(ROW_IDS) do
		ApplyRow(n)
	end
	ns.ActionBar.ReassignBindings()
	-- During Init the pet bar does not exist yet; Core runs the first layout after every module.
	if ns.ActionBar.ready then
		ns.Layout()
	end
end

local function UpdatePets()
	for i = 1, PETS do
		local button = ns.ActionBar.pets[i]
		if not button then return end
		local ok, name, texture, isToken, isActive = pcall(GetPetActionInfo, i)
		if not ok then
			button.icon:Hide()
		else
		if isToken and texture then
			texture = _G[texture]
		end
		if texture then
			button.icon:SetTexture(texture)
			button.icon:Show()
			button.icon:SetDesaturated(false)
			if isActive then
				button.icon:SetVertexColor(1, 1, 1)
			else
				button.icon:SetVertexColor(0.75, 0.75, 0.75)
			end
		else
			button.icon:Hide()
		end
		local start, duration, enable = GetPetActionCooldown(i)
		if button.cooldown and (ns.Secret(start) or ns.Secret(duration) or (start and duration)) then
			pcall(CooldownFrame_Set, button.cooldown, start, duration, enable)
		end
		if not name then
			button.icon:Hide()
		end
		end
	end
end

local function AdoptExtraAction()
	local host = ns.ExtraActionHost
	local button = ExtraActionButton1
	if not host or not button or InCombatLockdown() then return end
	button:SetParent(host)
	button:ClearAllPoints()
	button:SetPoint("CENTER")
	button:SetSize(64, 64)
	if button.style then
		button.style:Hide()
	end
	if button.icon then
		ns.Art.MaskCircle(button.icon)
	end
	ns.Art.AttachRing(button, "buttonRing")
end

function ns.ActionBar.Init()
	local cluster = ns.Cluster
	local LAB = LibStub("LibActionButton-1.0")
	LAB.RegisterCallback(ns, "OnButtonUpdate", function(_, button)
		ns.Art.ReskinActionButton(_, button)
	end)

	ns.ConsoleFrame = CreateFrame("Frame", "SanctuaryUIConsole", cluster)
	ns.ConsoleFrame:EnableMouse(false)
	ns.Trough = ns.ConsoleFrame:CreateTexture(nil, "ARTWORK")
	ns.Trough:SetAllPoints()
	if ns.Art.Apply(ns.Trough, "frame") then
		ns.Trough:SetTexCoord(unpack(ns.FRAME_TEXCOORD))
	else
		ns.Trough:SetColorTexture(0.08, 0.06, 0.04, 0.55)
	end

	local primary = CreateFrame("Frame", "SanctuaryUIPrimary", cluster, "SecureHandlerStateTemplate")
	primary:SetAllPoints(cluster)
	ns.PrimaryHeader = primary
	local onPage = [[
		if newstate == "possess" or newstate == "dragon" then
			if HasVehicleActionBar() then
				newstate = GetVehicleBarIndex()
			elseif HasOverrideActionBar() then
				newstate = GetOverrideBarIndex()
			elseif HasTempShapeshiftActionBar() then
				newstate = GetTempShapeshiftBarIndex()
			elseif HasBonusActionBar() then
				newstate = GetBonusBarIndex()
			else
				newstate = 12
			end
		end
		self:SetAttribute("state", newstate)
		control:ChildUpdate("state", newstate)
	]]
	primary:SetAttribute("_onstate-page", onPage)

	ns.ActionBar.primary = {}
	for i = 1, PRIMARY do
		local button = LAB:CreateButton(i, "SanctuaryUIButton" .. i, primary, ButtonConfig("ACTIONBUTTON" .. i, true))
		button.sanctuary = true
		button.sanctuarySquare = true
		for page = 1, PAGES do
			button:SetState(page, "action", (page - 1) * 12 + i)
		end
		button:SetState(0, "action", i)
		ns.ActionBar.primary[i] = button
		ns.Art.ReskinActionButton(nil, button)
	end
	RegisterStateDriver(primary, "page", ns.ActionBar.PageDriver())

	-- Every row gets twelve buttons up front; ApplyRow points them at the row's source and
	-- parks the unused ones on a hidden frame.
	ns.ActionBar.rows = {}
	for _, n in ipairs(ROW_IDS) do
		local header = CreateFrame("Frame", "SanctuaryUIRow" .. n, cluster, "SecureHandlerStateTemplate")
		header:SetAllPoints(cluster)
		header:SetAttribute("_onstate-page", onPage)
		local spare = CreateFrame("Frame", nil, header)
		spare:Hide()
		local buttons = {}
		for i = 1, ROW_MAX do
			local button = LAB:CreateButton(n * 100 + i, ("SanctuaryUIRow%dButton%d"):format(n, i), header, ButtonConfig(nil))
			button.sanctuary = true
			button.sanctuarySquare = true
			button.sanctuarySocket = true
			buttons[i] = button
			ns.Art.ReskinActionButton(nil, button)
		end
		-- Buttons hang off a plain anchor: stacked above the console, or wherever it was dragged.
		local anchor = CreateFrame("Frame", "SanctuaryUIRow" .. n .. "Anchor", cluster)
		local row = { header = header, buttons = buttons, spare = spare, anchor = anchor }
		row.mover = MakeMover(n, row)
		ns.ActionBar.rows[n] = row
	end
	ns.ActionBar.ApplyRows()

	local fader = CreateFrame("Frame", nil, cluster)
	local wait = 0
	fader:SetScript("OnUpdate", function(_, elapsed)
		wait = wait - elapsed
		if wait > 0 then return end
		wait = 0.1
		UpdateMouseover()
	end)

	local leave = CreateFrame("Button", "SanctuaryUILeaveVehicle", cluster, "SecureActionButtonTemplate")
	leave:SetAttribute("type", "macro")
	leave:SetAttribute("macrotext", "/leavevehicle")
	leave:RegisterForClicks("AnyUp", "AnyDown")
	leave.icon = leave:CreateTexture(nil, "ARTWORK")
	leave.icon:SetAllPoints()
	if not leave.icon:SetTexture("Interface\\Vehicles\\UI-Vehicles-Button-Exit-Up") and leave.icon.SetAtlas then
		leave.icon:SetAtlas("transmog-icon-revert")
	end
	ns.Art.MaskCircle(leave.icon)
	ns.Art.AttachRing(leave, "buttonRingSmall")
	leave:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(LEAVE_VEHICLE or "Leave Vehicle")
		GameTooltip:Show()
	end)
	leave:SetScript("OnLeave", GameTooltip_Hide)
	ns.LeaveButton = leave
	RegisterStateDriver(leave, "visibility", "[vehicleui][overridebar][possessbar] show; hide")

	local pets = CreateFrame("Frame", "SanctuaryUIPetBar", cluster, "SecureHandlerStateTemplate")
	pets:SetAllPoints(cluster)
	ns.PetHeader = pets
	ns.ActionBar.pets = {}
	for i = 1, PETS do
		local button = CreateFrame("CheckButton", "SanctuaryUIPetButton" .. i, pets, "SecureActionButtonTemplate")
		button:SetAttribute("type", "pet")
		button:SetAttribute("action", i)
		button:SetID(i)
		button:RegisterForClicks("AnyUp", "AnyDown")
		button:RegisterForDrag("LeftButton")
		button.icon = button:CreateTexture(nil, "ARTWORK")
		button.icon:SetAllPoints()
		ns.Art.MaskCircle(button.icon)
		button.cooldown = CreateFrame("Cooldown", button:GetName() .. "Cooldown", button, "CooldownFrameTemplate")
		button.cooldown:SetAllPoints()
		ns.Art.AttachRing(button, "buttonRingSmall")
		button:SetScript("OnDragStart", function(self)
			if InCombatLockdown() then return end
			PickupPetAction(self:GetID())
		end)
		button:SetScript("OnReceiveDrag", function(self)
			if InCombatLockdown() then return end
			PickupPetAction(self:GetID())
			UpdatePets()
		end)
		button:SetScript("OnEnter", function(self)
			if GameTooltip:IsForbidden() then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			pcall(GameTooltip.SetPetAction, GameTooltip, self:GetID())
			GameTooltip:Show()
		end)
		button:SetScript("OnLeave", GameTooltip_Hide)
		ns.ActionBar.pets[i] = button
	end
	RegisterStateDriver(pets, "visibility", ns.DB().pets and "[pet,nopetbattle,novehicleui] show; hide" or "hide")

	local petEvents = CreateFrame("Frame", nil, pets)
	petEvents:RegisterEvent("PET_BAR_UPDATE")
	petEvents:RegisterEvent("PET_BAR_UPDATE_COOLDOWN")
	petEvents:RegisterEvent("PET_BAR_UPDATE_USABLE")
	petEvents:RegisterEvent("UNIT_PET")
	petEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
	petEvents:SetScript("OnEvent", UpdatePets)

	ns.ExtraActionHost = CreateFrame("Frame", "SanctuaryUIExtraAction", cluster, "SecureHandlerStateTemplate")
	if not pcall(RegisterStateDriver, ns.ExtraActionHost, "visibility", "[extrabar] show; hide") then
		ns.ExtraActionHost:Hide()
	end
	AdoptExtraAction()

	local watcher = CreateFrame("Frame")
	watcher:RegisterEvent("UPDATE_BINDINGS")
	watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
	watcher:RegisterEvent("UPDATE_EXTRA_ACTIONBAR")
	watcher:SetScript("OnEvent", function(_, event)
		if event == "UPDATE_EXTRA_ACTIONBAR" or event == "PLAYER_ENTERING_WORLD" then
			if not InCombatLockdown() then
				AdoptExtraAction()
			end
		end
		if event == "UPDATE_BINDINGS" or event == "PLAYER_ENTERING_WORLD" then
			ns.ActionBar.ReassignBindings()
		end
	end)

	ns.ActionBar.ReassignBindings()
	UpdatePets()
	ns.ActionBar.ready = true
end
