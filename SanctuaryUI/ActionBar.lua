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
local LayoutPieces -- the console art in one sheet or three pieces (below)

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

-- Keybind text size. Stance and totem sockets are smaller and take one point less.
function ns.ActionBar.HotkeySize(smaller)
	local size = ns.DB().buttons.hotkeySize or 11
	return smaller and math.max(6, size - 1) or size
end

-- Font for the keybind text the addon draws itself (stance and totem sockets).
function ns.ActionBar.StyleHotkey(fontString)
	fontString:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", ns.ActionBar.HotkeySize(true), "OUTLINE")
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
				font = { font = false, size = ns.ActionBar.HotkeySize(), flags = "OUTLINE" },
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
	-- In the console a bar fills its whole row of twelve sockets: every socket there takes a
	-- spell. Its own button count is kept for when it leaves the console.
	local count = math.max(1, math.min(ROW_MAX, opt.count))
	if ns.ActionBar.DockIndex(n) then
		count = ROW_MAX
	end
	return {
		paged = false,
		firstAction = (page - 1) * 12 + 1,
		count = count,
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

-- Pages a docked bar may take over, in order of preference: page 2 first (bar 2's own in
-- Bartender), then those Blizzard's bars use, then the stance pages last.
local FREE_PAGES = { 2, 10, 6, 5, 3, 4, 13, 14, 15, 7, 8, 9 }

-- A page no other bar shows and the main bar doesn't page to, for bar n.
local function FreePage(n)
	local db = ns.DB()
	local used = {}
	for _, id in ipairs(ROW_IDS) do
		local opt = db.rows[id]
		if id ~= n and opt.enabled and tonumber(opt.source) then
			used[tonumber(opt.source)] = true
		end
	end
	for _, mod in ipairs({ "ctrl", "alt", "shift" }) do
		local page = tonumber(db.paging[mod]) or 0
		if page > 0 then used[page] = true end
	end
	if db.paging.stances then
		local _, class = UnitClass("player")
		for _, form in ipairs(CLASS_PAGES[class] or {}) do
			used[form.page] = true
		end
	end
	for _, page in ipairs(FREE_PAGES) do
		if not used[page] then return page end
	end
	return 2
end

-- A bar in the console has twelve sockets, but "Main bar 10-12" holds three actions, which
-- left nine dead sockets. A bar set into the console on that source moves to a free page, and
-- takes the three spells with it (into the page's first sockets, where those are empty); its
-- keys follow through the usual binding move. Returns the page, or nil if nothing changed.
function ns.ActionBar.LeaveMainSource(n)
	local opt = ns.DB().rows[n]
	if opt.source ~= "main" then return end
	local count = math.max(1, math.min(12 - PRIMARY, opt.count))
	local page = FreePage(n)
	opt.source = page
	opt.count = ROW_MAX -- a full page bar, in the console or out of it
	if not InCombatLockdown() and not GetCursorInfo() then
		for i = 1, count do
			local from, to = PRIMARY + i, (page - 1) * 12 + i
			if HasAction(from) and not HasAction(to) then
				PickupAction(from)
				PlaceAction(to)
				ClearCursor()
			end
		end
	end
	return page
end

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

-- The console art as one sheet, or with the globes scaled separately, three pieces: the bar
-- on the console frame and each globe's statue in its pod (Core.lua PlacePods). Each pod then
-- takes the mouse over its piece, as the cluster does over the bar.
function LayoutPieces(metrics, lifted)
	local split = metrics.split
	local trough = ns.Trough
	local s = metrics.scale
	trough:ClearAllPoints()
	if split then
		trough:SetPoint("BOTTOMLEFT", ns.ConsoleFrame, "BOTTOMLEFT", ns.SEAM_L * s, 0)
		trough:SetSize((ns.SEAM_R - ns.SEAM_L) * s, metrics.height)
	else
		trough:SetAllPoints()
	end
	local file = lifted and "consoleBase" or "frame"
	local hasArt = ns.Art.Path(file) ~= nil
	if hasArt then
		if split then ns.CropBar(trough) else trough:SetTexCoord(unpack(ns.FRAME_TEXCOORD)) end
	end
	local level = ns.Cluster:GetFrameLevel()
	for side, pod in pairs(ns.Pods) do
		local art = pod.art
		if not art then
			art = CreateFrame("Frame", nil, pod)
			art:EnableMouse(false)
			art.tex = art:CreateTexture(nil, "ARTWORK")
			art.tex:SetAllPoints()
			pod.art = art
			pod:RegisterForDrag("LeftButton")
			pod:SetScript("OnDragStart", function() ns.ActionBar.DragConsole() end)
			pod:SetScript("OnDragStop", function() ns.Snap.StopDrag() end)
		end
		if art.file ~= file and hasArt then
			ns.Art.Apply(art.tex, file)
			art.file = file
		end
		ns.CropPiece(art.tex, side)
		ns.PlacePiece(art, pod, side, metrics)
		art:SetFrameLevel(level + ns.LEVEL.console)
		art:SetShown(split and hasArt)
		pod:SetFrameLevel(level)
		pod:EnableMouse(split)
		local x0 = (side == "health" and 0 or ns.SEAM_R) * s
		local x1 = (side == "health" and ns.SEAM_L or ns.TEX_W) * s
		pod:SetHitRectInsets(x0, metrics.width - x1, 0, 0)
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
		-- Its wings reach out over the globes; with the globes scaled separately they would miss
		-- them, so the band stops at the seams.
		local x0, x1 = TIER_X, TIER_X + TIER_W
		if metrics.split then x0, x1 = ns.SEAM_L, ns.SEAM_R end
		frame.tier:SetTexCoord((x0 - TIER_X) / 2048, (x1 - TIER_X) / 2048, y0 / 512, (y0 + h) / 512)
		frame.tier:SetSize((x1 - x0) * s, h * s)
		frame.tier:ClearAllPoints()
		frame.tier:SetPoint("TOPLEFT", frame, "TOPLEFT", x0 * s, metrics.lift)
	end
	LayoutPieces(metrics, lifted)
end

function ns.ActionBar.Layout()
	local cluster = ns.Cluster
	local metrics = ns.Metrics and ns.Metrics()
	if not cluster or not ns.ActionBar.primary or not metrics then return end
	local base = metrics.baseY
	local clusterH = metrics.height + 80 + metrics.lift
	cluster:SetSize(metrics.width + 40, clusterH)
	-- The console's outline in cluster units, about its bottom centre: the globes' pieces
	-- reach further out (and up) or less with the globes scaled separately.
	local ratio = metrics.globeRatio
	local half = metrics.width / 2
	local span = {
		left = metrics.seamL - (half + metrics.seamL) * ratio,
		right = metrics.seamR + (half - metrics.seamR) * ratio,
		top = metrics.height * math.max(1, ratio),
	}
	ns.ActionBar.span = span
	-- Clamp to the console art, not the padded cluster: it may touch the screen's edges.
	cluster:SetClampRectInsets(20 + (-half - span.left), -20 + (span.right - half), -80, 0)
	-- Only the console art (with its docked tiers) takes the mouse, so clicks on it never fall
	-- through to the world. The padding around it lets the mouse through to whatever is placed
	-- there, such as a target bar moved down over the console. Scaled separately, the globes'
	-- pods take the mouse over their own pieces.
	local artTop = base + metrics.height / 2 + metrics.lift
	local artBottom = base - metrics.height / 2
	local sideL, sideR = 20, 20
	if metrics.split then
		sideL, sideR = 20 + metrics.seamL + half, 20 + half - metrics.seamR
	end
	cluster:SetHitRectInsets(sideL, sideR, math.max(0, clusterH - artTop), math.max(0, artBottom))

	if ns.ConsoleFrame then
		ns.ConsoleFrame:SetSize(metrics.width, metrics.height)
		ns.ConsoleFrame:ClearAllPoints()
		ns.ConsoleFrame:SetPoint("CENTER", cluster, "BOTTOM", 0, base)
		ns.ConsoleFrame:SetFrameLevel(cluster:GetFrameLevel() + ns.LEVEL.console)
		LayoutTiers(metrics)
	end
	local above = cluster:GetFrameLevel() + ns.LEVEL.buttons
	-- The bar headers span the whole cluster and are only parents for their buttons: they must
	-- never take the mouse (one did, and swallowed hover and clicks over everything above the
	-- console, the target bar included).
	local function Header(header)
		header:SetFrameLevel(above)
		header:EnableMouse(false)
	end
	if ns.PrimaryHeader then Header(ns.PrimaryHeader) end
	if ns.ActionBar.rows then
		for _, row in pairs(ns.ActionBar.rows) do
			Header(row.header)
		end
	end
	if ns.PetHeader then Header(ns.PetHeader) end
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
	ns.ActionBar.consoleTop = consoleTop
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
				-- The mover covers the stone sockets too, so bars snap stone to stone.
				local inset = ns.Art.SOCKET_INSET
				local ox = bw * inset.left / (1 - inset.left - inset.right)
				local ot = bh * inset.top / (1 - inset.top - inset.bottom)
				local ob = bh * inset.bottom / (1 - inset.top - inset.bottom)
				row.mover:ClearAllPoints()
				row.mover:SetPoint("TOPLEFT", anchor, "TOPLEFT", -ox, ot)
				row.mover:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", ox, -ob)
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

-- A mover's gold edge brightens while the drag has caught on something.
function ns.MoverLit(mover, lit)
	if mover.edge then
		if lit then
			mover.edge:SetColorTexture(1, 0.9, 0.55, 1)
		else
			mover.edge:SetColorTexture(0.86, 0.72, 0.42, 0.8)
		end
	end
end

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
	mover.edge = edge
	local function Save()
		local x, y = anchor:GetCenter()
		if x then
			local o = opt()
			o.moved, o.mx, o.my = true, x, y
		end
		ns.Refresh()
	end
	mover:SetScript("OnDragStart", function()
		if InCombatLockdown() then return end
		GameTooltip_Hide()
		ns.Snap.StartDrag(anchor, function() return ns.Snap.Rect(mover) end, Save, function(snapped)
			ns.MoverLit(mover, snapped)
		end)
	end)
	mover:SetScript("OnDragStop", ns.Snap.StopDrag)
	ns.Snap.RegisterMover(mover, anchor)
	mover:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(label)
		GameTooltip:AddLine(ns.Snap.Enabled() and "Drag to move: it snaps to other frames and the screen edges (hold Shift to place freely). Right-click to lock all frames." or "Drag to move. Right-click to lock all frames.", 1, 1, 1, true)
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
	panel:SetSize(340, 112)
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
	local function Notify()
		local registry = LibStub("AceConfigRegistry-3.0", true)
		if registry then registry:NotifyChange("SanctuaryUI") end
	end
	local function Check(name, label, y, get, set)
		local check = CreateFrame("CheckButton", name, panel, "UICheckButtonTemplate")
		check:SetSize(24, 24)
		check:SetPoint("TOPLEFT", 12, y)
		local checkText = check.Text or _G[name .. "Text"]
		if checkText then checkText:SetText(label) end
		check:SetScript("OnShow", function(self) self:SetChecked(get()) end)
		check:SetScript("OnClick", function(self)
			set(self:GetChecked() and true or false)
			Notify()
		end)
		return check
	end
	-- Bartender4's "Bar Snapping" box, and Edit Mode's grid with its spacing.
	panel.snap = Check("SanctuaryUISnapping", "Bar snapping (hold Shift to place freely)", -30,
		ns.Snap.Enabled, function(on) ns.DB().snapping = on end)
	panel.grid = Check("SanctuaryUIShowGrid", "Show grid", -54,
		function() return ns.DB().grid and true or false end,
		function(on)
			ns.DB().grid = on
			ns.ActionBar.UpdateMovers()
		end)

	local slider = CreateFrame("Slider", "SanctuaryUIGridSpacing", panel)
	slider:SetOrientation("HORIZONTAL")
	slider:SetSize(120, 16)
	slider:SetPoint("TOPLEFT", 150, -58)
	slider:SetHitRectInsets(0, 0, -4, -4)
	local track = slider:CreateTexture(nil, "BACKGROUND")
	track:SetPoint("LEFT")
	track:SetPoint("RIGHT")
	track:SetHeight(4)
	track:SetColorTexture(0.86, 0.72, 0.42, 0.45)
	slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
	slider:SetMinMaxValues(ns.Snap.GRID_MIN, ns.Snap.GRID_MAX)
	slider:SetValueStep(5)
	if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
	local value = slider:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	value:SetPoint("LEFT", slider, "RIGHT", 8, 0)
	slider:SetScript("OnValueChanged", function(_, v, userInput)
		v = math.floor(v / 5 + 0.5) * 5
		value:SetText(v)
		if userInput then
			ns.DB().gridSize = v
			ns.Snap.UpdateGrid()
			Notify()
		end
	end)
	slider:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Grid spacing")
		GameTooltip:AddLine("Distance between grid lines, counted out from the screen's centre.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	slider:SetScript("OnLeave", GameTooltip_Hide)
	panel.spacing = slider

	-- Keep the panel in step with the options window.
	function panel.Sync()
		panel.snap:SetChecked(ns.Snap.Enabled())
		panel.grid:SetChecked(ns.DB().grid and true or false)
		slider:SetValue(ns.Snap.GridSize())
		value:SetText(ns.Snap.GridSize())
		local on = ns.DB().grid and true or false
		slider:SetAlpha(on and 1 or 0.4)
		slider:EnableMouse(on)
	end
	panel:Hide()
	ns.UnlockPanel = panel
	return panel
end

-- The console's box for snapping, in screen pixels: the art from its bottom edge up to the top
-- of the centre ornament (or level plaque), where the bars stack.
function ns.ActionBar.ConsoleBox()
	local frame, cluster, span = ns.ConsoleFrame, ns.Cluster, ns.ActionBar.span
	if not frame or not frame:IsVisible() or not ns.ActionBar.consoleTop or not span then return end
	local left, right, bottom = cluster:GetLeft(), cluster:GetRight(), cluster:GetBottom()
	if not left or not bottom then return end
	local centre, s = (left + right) / 2, cluster:GetEffectiveScale()
	return (centre + span.left) * s, bottom * s, (centre + span.right) * s, (bottom + ns.ActionBar.consoleTop) * s
end

-- Drag the console (its mover, or the console itself while unlocked), snapping its box.
function ns.ActionBar.DragConsole(highlight)
	if ns.DB().locked or InCombatLockdown() then return end
	GameTooltip_Hide()
	ns.Snap.StartDrag(ns.Cluster, ns.ActionBar.ConsoleBox, ns.SavePosition, highlight)
end

-- The console's own mover: most of the console is buttons and globes, so this gives the
-- whole piece something to grab while unlocked.
local function ConsoleMover()
	if ns.ConsoleMover then return ns.ConsoleMover end
	local mover = CreateFrame("Frame", "SanctuaryUIConsoleMover", ns.Cluster)
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
	mover.edge = edge
	mover:SetScript("OnDragStart", function()
		ns.ActionBar.DragConsole(function(snapped) ns.MoverLit(mover, snapped) end)
	end)
	mover:SetScript("OnDragStop", ns.Snap.StopDrag)
	mover:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" then
			ns.SetLocked(true)
		end
	end)
	mover:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Console")
		GameTooltip:AddLine("Drag to move the globes, bars and menu" .. (ns.Snap.Enabled() and ": it snaps to other frames and the screen edges (hold Shift to place freely)" or "") .. ". Right-click to lock all frames.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	mover:SetScript("OnLeave", GameTooltip_Hide)
	mover:Hide()
	ns.ConsoleMover = mover
	ns.Snap.Register(ns.Cluster, ns.ActionBar.ConsoleBox)
	return mover
end

function ns.ActionBar.UpdateMovers()
	if not ns.ActionBar.rows then return end
	local unlocked = not ns.DB().locked and not InCombatLockdown()
	UnlockPanel():SetShown(unlocked)
	ns.UnlockPanel.Sync()
	ns.Snap.UpdateGrid()
	if ns.ConsoleFrame then
		local mover, span = ConsoleMover(), ns.ActionBar.span
		-- Over the whole console art, out to the globes' statues at whatever their scale.
		if span then
			mover:ClearAllPoints()
			mover:SetPoint("BOTTOMLEFT", ns.Cluster, "BOTTOM", span.left, 0)
			mover:SetPoint("TOPRIGHT", ns.Cluster, "BOTTOM", span.right, span.top)
		end
		mover:SetShown(unlocked)
	end
	if ns.TargetPlate and ns.TargetPlate.mover then
		ns.TargetPlate.mover:SetShown(unlocked and ns.DB().target.enabled)
	end
	if ns.Portraits and ns.Portraits.mover then
		ns.Portraits.mover:SetShown(unlocked and ns.DB().portraits.enabled)
	end
	if ns.Party and ns.Party.mover then
		ns.Party.mover:SetShown(unlocked and ns.Party.Style() and true or false)
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

---------------------------------------------------------------------------
-- Cooldown numbers. This client hides cooldown timing from addons in combat, so the Cooldown
-- frame counts down by itself; a rule formatter (C_StringUtil, as ElvUI and Plater use here)
-- shapes its text: tenths of a second below buttons.cooldownTenths seconds, whole seconds,
-- then m:ss, minutes and hours.

local countdown -- the shared formatter and the setting it was built for

local function CountdownFormatter()
	local create = C_StringUtil and C_StringUtil.CreateNumericRuleFormatter
	if not create then return end
	local tenths = math.max(0, math.min(60, tonumber(ns.DB().buttons.cooldownTenths) or 0))
	if countdown and countdown.tenths == tenths then return countdown.formatter end
	local rounding = Enum and Enum.NumericRuleFormatRounding
	local up = rounding and rounding.Up or 1
	local points = {}
	if tenths > 0 then
		points[#points + 1] = { threshold = 0, step = 0.1, format = "%.1f", rounding = up }
	end
	if tenths < 60 then
		points[#points + 1] = { threshold = tenths, step = 1, format = "%d", rounding = up }
	end
	points[#points + 1] = { threshold = 60, format = "%d:%02d", components = { { div = 60 }, { mod = 60 } } }
	points[#points + 1] = { threshold = 600, format = "%dm", components = { { div = 60, step = 1 } } }
	points[#points + 1] = { threshold = 3600, format = "%dh", components = { { div = 3600, step = 1 } } }
	-- A new formatter each time: one already handed to cooldowns is left as it is.
	local formatter = create()
	local ok, err = pcall(formatter.SetBreakpoints, formatter, points)
	if not ok then
		ns.Log("cooldown formatter refused: %s", tostring(err))
		formatter = nil
	end
	countdown = { tenths = tenths, formatter = formatter }
	return formatter
end

local function CountdownText(cooldown)
	if cooldown.GetCountdownFontString then
		local ok, text = pcall(cooldown.GetCountdownFontString, cooldown)
		if ok and text then return text end
	end
	for _, region in ipairs({ cooldown:GetRegions() }) do
		if region.GetObjectType and region:GetObjectType() == "FontString" then return region end
	end
end

-- Whether buttons that aren't LibActionButton's (pet, stance, portal) show numbers.
local function CountdownShown()
	local mode = ns.DB().buttons.cooldownNumbers
	if mode == "show" then return true end
	if mode == "hide" then return false end
	local GetCVarBool = C_CVar and C_CVar.GetCVarBool or GetCVarBool
	return GetCVarBool and GetCVarBool("countdownForCooldowns") and true or false
end

-- One button's countdown: the formatter and white numbers sized to the button (the client
-- leaves the global cooldown without numbers itself). show nil leaves showing them to
-- LibActionButton, which follows the Cooldown numbers setting.
local function StyleCountdown(button, show)
	local cooldown = button and button.cooldown
	if not cooldown then return end
	if show ~= nil and cooldown.SetHideCountdownNumbers then
		cooldown:SetHideCountdownNumbers(not show)
	end
	local formatter = CountdownFormatter()
	if formatter and cooldown.SetCountdownFormatter then
		pcall(cooldown.SetCountdownFormatter, cooldown, formatter)
	end
	local text = CountdownText(cooldown)
	local side = math.min(button:GetWidth() or 0, button:GetHeight() or 0)
	if text and side > 0 then
		-- "12.3" fits across a socket at this size (and "59:59" across the narrow portal).
		local size = math.max(9, math.floor(side * 0.34 + 0.5))
		if text.sanctuarySize ~= size then
			text:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, "OUTLINE")
			text.sanctuarySize = size
		end
		text:SetTextColor(1, 1, 1)
		text:SetShadowOffset(1, -1)
		text:ClearAllPoints()
		text:SetPoint("CENTER", button, "CENTER", 0, 0)
	end
end

-- Every hotbar button's countdown, after its size or the settings change.
function ns.ActionBar.StyleCountdowns()
	if not ns.ActionBar.primary then return end
	-- The client only draws cooldown numbers with Blizzard's "Show numbers for cooldowns" on,
	-- whatever a cooldown is told (ElvUI turns it on too), so Show asks to turn it on. Asked once a
	-- session: setting it means a reload (see ns.AskCVarReload).
	if ns.DB().buttons.cooldownNumbers == "show" and not ns.ActionBar.countdownAsked then
		local GetCVarBool = C_CVar and C_CVar.GetCVarBool or GetCVarBool
		if GetCVarBool and not GetCVarBool("countdownForCooldowns") and not InCombatLockdown() then
			ns.ActionBar.countdownAsked = true
			ns.Log("cooldown numbers: countdownForCooldowns is off, asking")
			ns.AskCVarReload("countdownForCooldowns", "1", "SanctuaryUI shows cooldown numbers on your buttons, and the game only draws them with Blizzard's \"Show Numbers for Cooldowns\" on. Turn it on?\n\n(To keep it off, set Action Bars > Cooldown numbers to Hide or Blizzard setting.)")
		end
	end
	ns.ActionBar.ForEachButton(function(button) StyleCountdown(button, nil) end)
	local show = CountdownShown()
	for _, button in ipairs(ns.ActionBar.pets or {}) do StyleCountdown(button, show) end
	local stance = ns.Stance and ns.Stance.bar
	for _, button in ipairs(stance and stance.buttons or {}) do StyleCountdown(button, show) end
	StyleCountdown(ns.HearthButton, show)
end

-- /sanctuary cooldowns: what the main bar's cooldowns are set to show, for the log.
function ns.ActionBar.CountdownReport()
	local GetCVarBool = C_CVar and C_CVar.GetCVarBool or GetCVarBool
	ns.Print(("cooldown numbers: setting %s, tenths below %s s, Blizzard option %s, formatter API %s"):format(
		tostring(ns.DB().buttons.cooldownNumbers), tostring(ns.DB().buttons.cooldownTenths),
		tostring(GetCVarBool and GetCVarBool("countdownForCooldowns")),
		tostring(C_StringUtil and C_StringUtil.CreateNumericRuleFormatter ~= nil)))
	for i, button in ipairs(ns.ActionBar.primary or {}) do
		local cd = button.cooldown
		if cd then
			local text = CountdownText(cd)
			local function call(obj, method)
				if not obj or not obj[method] then return "n/a" end
				local ok, value = pcall(obj[method], obj)
				if not ok then return "error" end
				if ns.Secret(value) then return "secret" end
				return tostring(value)
			end
			local font, size = "n/a", "n/a"
			if text and text.GetFont then
				local ok, f, sz = pcall(text.GetFont, text)
				if ok then font, size = tostring(f), tostring(sz) end
			end
			ns.Print(("socket %d: cooldown shown %s visible %s, numbers hidden %s, text %s shown %s visible %s says '%s' size %s alpha %s, button %sx%s"):format(
				i, call(cd, "IsShown"), call(cd, "IsVisible"), call(cd, "GetHideCountdownNumbers"),
				text and "yes" or "none", call(text, "IsShown"), call(text, "IsVisible"), call(text, "GetText"),
				size, call(text, "GetAlpha"), call(button, "GetWidth"), call(button, "GetHeight")))
		end
	end
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
	-- The lock is the buttons' own "buttonlock" attribute. Blizzard's lockActionBars is left
	-- alone: writing it taints Blizzard's settings (see ns.AskCVarReload).
	ns.ActionBar.ForEachButton(ApplyLock)
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
	-- Profiles saved with a "Main bar 10-12" bar in the console: move it to a page, and let the
	-- binding move carry its keys from the bindings it answered to.
	for _, n in ipairs(ROW_IDS) do
		if ns.DB().rows[n].docked and ns.DB().rows[n].source == "main" then
			ns.ActionBar.rows[n].bound = RowActions(n)
			ns.ActionBar.LeaveMainSource(n)
		end
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
