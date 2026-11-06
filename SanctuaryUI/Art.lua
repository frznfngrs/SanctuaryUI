SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI

ns.Art = ns.Art or {}

local ROOT = "Interface\\AddOns\\SanctuaryUI\\Art\\"

-- Slots the prep script fills. Missing files fall back to flat color and game chrome.
ns.Art.slots = {
	frame = { file = "frame.png" },
	glass = { file = "glass.png" },
	liquid = { file = "liquid.png" },
	hotline = { file = "hotline.png" },
	xpOrange = { file = "xp-orange.png" },
	xpGold = { file = "xp-gold.png" },
	xpBlue = { file = "xp-blue.png" },
	xpWhite = { file = "xp-white.png" },
	menu = { file = "menu.png" },
	buttonGlow = { file = "button-glow.png" },
	socket = { file = "socket.png" },
	socketHover = { file = "socket-hover.png" },
	socketPress = { file = "socket-press.png" },
	blade = { file = "blade.png" },
	bagFrame = { file = "bag-frame.png" },
	bankFrame = { file = "bank-frame.png" },
	pips = { file = "pips.png" },
	pipHorn = { file = "pip-horn.png" },
	pipSockets = { file = "pip-sockets.png" },
	liquidShimmer = { file = "liquid-shimmer.png" },
	bagCells = { file = "bag-cells.png" },
	d3Button = { file = "d3-button.png" },
	liquidLeft = { file = "liquid-left.png" },
	liquidRight = { file = "liquid-right.png" },
	liquidTile = { file = "liquid-tile.png" },
	liquidStreaks = { file = "liquid-streaks.png" },
	liquidWisps = { file = "liquid-wisps.png" },
	globeRim = { file = "globe-rim.png" },
	surfaceGlow = { file = "surface-glow.png" },
	surfaceShimmer = { file = "surface-shimmer.png" },
	mote = { file = "mote.png" },
	globeShade = { file = "globe-shade.png" },
	globeMask = { file = "globe-mask.png" },
	skillTimer = { file = "skill-timer.png" },
}

-- socket.png holds a 76x80 crop in a 128x128 PNG. The stone interior starts 4px in from the left and 7px down.
ns.Art.SOCKET_TEXCOORD = { 0, 76 / 128, 0, 80 / 128 }
ns.Art.SOCKET_INSET = { left = 4 / 76, right = 4 / 76, top = 7 / 80, bottom = 6 / 80 }

-- menu.png: seven 40x66 columns in a 512x256 atlas, one row per state. The third row is the
-- pressed plate for menu buttons and the disabled (grey) portal for the hearth.
ns.Art.MENU_CELLS = { character = 0, spellbook = 1, talents = 2, social = 3, quests = 4, hearth = 5, bags = 6 }
ns.Art.MENU_STATES = { normal = 0, hover = 1, pressed = 2, disabled = 2 }
function ns.Art.MenuTexCoord(name, state)
	local i = ns.Art.MENU_CELLS[name] or 0
	local row = ns.Art.MENU_STATES[state or "normal"] or 0
	return i * 40 / 512, (i + 1) * 40 / 512, row * 66 / 256, (row + 1) * 66 / 256
end

local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

function ns.Art.Path(slot)
	local info = ns.Art.slots[slot]
	local ready = ns.Art.ready and ns.Art.ready[slot]
	if info and ready then
		return ROOT .. info.file
	end
end

function ns.Art.Probe()
	local probe = ns.Art.probe
	if not probe then
		probe = UIParent:CreateTexture(nil, "BACKGROUND")
		probe:Hide()
		ns.Art.probe = probe
	end
	local ready = {}
	local loaded, total = 0, 0
	for slot, info in pairs(ns.Art.slots) do
		total = total + 1
		local path = ROOT .. info.file
		local ok = probe:SetTexture(path)
		if ok then
			ready[slot] = true
			loaded = loaded + 1
		else
			ready[slot] = false
		end
	end
	probe:SetTexture(nil)
	ns.Art.ready = ready
	ns.Art.loadedCount = loaded
	ns.Art.totalCount = total
	return loaded, total
end

function ns.Art.Apply(texture, slot, color)
	if not texture then return false end
	local path = ns.Art.Path(slot)
	if path and texture:SetTexture(path) then
		texture:SetVertexColor(1, 1, 1, 1)
		return true
	end
	local r, g, b, a = 0, 0, 0, 0
	if color then
		r, g, b, a = color[1], color[2], color[3], color[4] or 1
	end
	texture:SetColorTexture(r, g, b, a)
	return false
end

local function EnsureMask(texture, anchor)
	if not texture or texture.sanctuaryMasked then return end
	if not texture.AddMaskTexture then return end
	anchor = anchor or texture:GetParent() or texture
	if not anchor.CreateMaskTexture then return end
	local mask = anchor:CreateMaskTexture()
	mask:SetAllPoints(anchor)
	mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	local ok = pcall(texture.AddMaskTexture, texture, mask)
	if ok then
		texture.sanctuaryMasked = true
		texture.sanctuaryMask = mask
	end
end

function ns.Art.MaskCircle(texture, anchor)
	EnsureMask(texture, anchor)
end

-- Stone socket behind the icon and the D3 hover glow above it. Replaces the old metal ring.
function ns.Art.AttachRing(parent)
	if parent.sanctuaryRingFrame then
		return parent.sanctuaryRingFrame
	end
	if parent.sanctuarySocket and not parent.sanctuarySocketTex then
		local socket = parent:CreateTexture(nil, "BACKGROUND", nil, -7)
		local inset = ns.Art.SOCKET_INSET
		local function Outset()
			local w, h = parent:GetSize()
			local fw = w / (1 - inset.left - inset.right)
			local fh = h / (1 - inset.top - inset.bottom)
			socket:ClearAllPoints()
			socket:SetPoint("TOPLEFT", parent, "TOPLEFT", -fw * inset.left, fh * inset.top)
			socket:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", fw * inset.right, -fh * inset.bottom)
		end
		if ns.Art.Apply(socket, "socket") then
			socket:SetTexCoord(unpack(ns.Art.SOCKET_TEXCOORD))
		else
			socket:SetColorTexture(0.05, 0.05, 0.05, 0.9)
		end
		Outset()
		parent:HookScript("OnSizeChanged", Outset)
		parent.sanctuarySocketTex = socket
	end
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetAllPoints()
	frame:EnableMouse(false)
	local cooldown = parent.cooldown or parent.Cooldown
	local level = parent:GetFrameLevel() + 6
	if cooldown and cooldown.GetFrameLevel then
		level = cooldown:GetFrameLevel() + 3
	end
	frame:SetFrameLevel(level)
	parent.sanctuaryRingFrame = frame

	-- bottomBar_buttonFX_frameGlow: the glow D3 draws on hover and press. The art is a square
	-- frame with a soft halo, so it is drawn larger than the socket.
	local glow = frame:CreateTexture(nil, "OVERLAY", nil, 1)
	glow:SetPoint("TOPLEFT", -0.45 * 40, 0.45 * 40)
	glow:SetPoint("BOTTOMRIGHT", 0.45 * 40, -0.45 * 40)
	local function SizeGlow()
		local w, h = parent:GetSize()
		glow:ClearAllPoints()
		glow:SetPoint("TOPLEFT", -w * 0.45, h * 0.45)
		glow:SetPoint("BOTTOMRIGHT", w * 0.45, -h * 0.45)
	end
	if ns.Art.Apply(glow, "buttonGlow") then
		glow:SetBlendMode("ADD")
	else
		glow:SetColorTexture(1, 0.78, 0.35, 0.25)
		glow:SetBlendMode("ADD")
	end
	SizeGlow()
	parent:HookScript("OnSizeChanged", SizeGlow)
	glow:Hide()
	parent.sanctuaryGlow = glow
	return frame
end

-- Template art that fights the stone sockets. The highlight, pushed, checked, flash and proc
-- textures stay: they are WoW's own gold glow and the engine keeps their state right, even
-- for presses that happen inside the secure keybind path.
local SQUARE_LIGHTS = {
	"NewActionTexture",
	"Border",
}

-- Gold press and hover light for buttons that are not built from the action button template.
local GOLD_HOVER = "UI-HUD-ActionBar-IconFrame-Mouseover"
local GOLD_DOWN = "UI-HUD-ActionBar-IconFrame-Down"

-- Hover, press and checked use the engine's own button states (so presses through the secure
-- keybind path can never leave a light on) but our art: a gold rim on the socket edge.
-- socket-hover/press.png map the button to their inner 96 of 128 px; LibActionButton resets
-- the template textures' size on every update, so this runs again after each one.
local RIM_OUTSET = 16 / 96
-- Template lights we keep (auto-attack flash, proc highlight), refit in Blizzard's own
-- proportion: ~5.5% past the icon on each side.
local TEMPLATE_LIGHTS = { "Flash", "SpellHighlightTexture" }
local TEMPLATE_OUTSET = 2.5 / 45

local function Fit(button, tex, outset)
	if not tex then return end
	local w, h = button:GetSize()
	tex:ClearAllPoints()
	tex:SetPoint("TOPLEFT", button, "TOPLEFT", -w * outset, h * outset)
	tex:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", w * outset, -h * outset)
end

local function Rim(button, tex, slot, alpha)
	if not tex then return end
	if ns.Art.Path(slot) then
		tex:SetTexture(ns.Art.Path(slot))
		tex:SetTexCoord(0, 1, 0, 1)
		tex:SetBlendMode("ADD")
		tex:SetVertexColor(1, 1, 1, alpha)
		Fit(button, tex, RIM_OUTSET)
	else
		Fit(button, tex, TEMPLATE_OUTSET)
	end
end

local function FitGoldLights(button)
	local w = button:GetSize()
	if not w or w <= 0 then return end
	Rim(button, button.GetHighlightTexture and button:GetHighlightTexture() or button.HighlightTexture, "socketHover", 1)
	Rim(button, button.GetPushedTexture and button:GetPushedTexture() or button.PushedTexture, "socketPress", 1)
	-- Checked marks an active ability (auto attack, a channel): steady and dimmer than hover.
	Rim(button, button.GetCheckedTexture and button:GetCheckedTexture() or button.CheckedTexture, "socketHover", 0.65)
	for i = 1, #TEMPLATE_LIGHTS do
		Fit(button, button[TEMPLATE_LIGHTS[i]], TEMPLATE_OUTSET)
	end
end
ns.Art.FitGoldLights = FitGoldLights

function ns.Art.GoldLights(button)
	if button.sanctuaryGold or not button.SetHighlightAtlas then return false end
	local ok = pcall(button.SetHighlightAtlas, button, GOLD_HOVER, "ADD")
	if not ok then return false end
	if button.SetPushedAtlas then
		pcall(button.SetPushedAtlas, button, GOLD_DOWN)
	end
	button.sanctuaryGold = true
	return true
end

local function HideSquareLight(button, texture)
	if not texture or texture.sanctuarySquaredOff then return end
	texture.sanctuarySquaredOff = true
	texture:SetAlpha(0)
end

local function SyncPressLight(button)
	local glow = button.sanctuaryGlow
	if not glow then return end
	local pushed = button.GetButtonState and button:GetButtonState() == "PUSHED"
	local checked = button.GetChecked and button:GetChecked()
	local over = button.sanctuaryOver
	local on = pushed or checked or over
	glow:SetShown(on)
end

function ns.Art.ReskinActionButton(_, button)
	if not button.sanctuary then return end
	local icon = button.icon
	if icon then
		if button.sanctuarySquare then
			icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		else
			EnsureMask(icon)
			icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		end
		icon:ClearAllPoints()
		icon:SetAllPoints()
	end
	if button.SetPushedTextOffset then
		button:SetPushedTextOffset(0, 0)
	end
	if button.NormalTexture then
		button.NormalTexture:SetAlpha(0)
	end
	if button.SlotBackground then
		button.SlotBackground:Hide()
	end
	if button.FloatingBG then
		button.FloatingBG:Hide()
	end
	for i = 1, #SQUARE_LIGHTS do
		HideSquareLight(button, button[SQUARE_LIGHTS[i]])
	end
	-- Template buttons (LibActionButton) already carry WoW's gold lights; others get them here.
	local native = button.GetHighlightTexture and button:GetHighlightTexture() ~= nil
	if not native then
		native = ns.Art.GoldLights(button)
	end
	local ring = ns.Art.AttachRing(button)
	local cooldown = button.cooldown
	if cooldown then
		if cooldown.SetUseCircularEdge then
			cooldown:SetUseCircularEdge(not button.sanctuarySquare)
		end
		if ring and ring:GetFrameLevel() <= cooldown:GetFrameLevel() then
			ring:SetFrameLevel(cooldown:GetFrameLevel() + 3)
		end
	end
	local textParent = ring or button
	if button.HotKey and button.HotKey:GetParent() ~= textParent then
		button.HotKey:SetParent(textParent)
	end
	if button.Count and button.Count:GetParent() ~= textParent then
		button.Count:SetParent(textParent)
	end
	if native then
		FitGoldLights(button)
		if not button.sanctuaryFitHooked then
			button.sanctuaryFitHooked = true
			button:HookScript("OnSizeChanged", FitGoldLights)
		end
		-- The gold template lights handle hover, press and checked; no D3 glow on top.
		if button.sanctuaryGlow then
			button.sanctuaryGlow:Hide()
		end
		return
	end
	if not button.sanctuaryPressHooked then
		button.sanctuaryPressHooked = true
		button:HookScript("OnEnter", function(self)
			self.sanctuaryOver = true
			SyncPressLight(self)
		end)
		button:HookScript("OnLeave", function(self)
			self.sanctuaryOver = false
			SyncPressLight(self)
		end)
		if button.SetChecked then
			hooksecurefunc(button, "SetChecked", SyncPressLight)
		end
		if button.SetButtonState then
			hooksecurefunc(button, "SetButtonState", SyncPressLight)
		end
	end
	SyncPressLight(button)
end
