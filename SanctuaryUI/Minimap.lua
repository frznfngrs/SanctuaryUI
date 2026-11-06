-- SanctuaryUI
-- Minimap button. A LibDataBroker launcher shown by LibDBIcon, so it can be dragged around
-- the minimap and picked up by button-bag addons. The D3 frame in the icon art replaces
-- WoW's round tracking border and backdrop.
local ns = SanctuaryUI
ns.Minimap = ns.Minimap or {}

local NAME = "SanctuaryUI"
local ICON = "Interface\\AddOns\\SanctuaryUI\\Art\\icon"
-- The icon art includes its frame, whose wings and banner reach past the ring other buttons
-- draw, so it is drawn below the 31 px button size to sit level with them.
local SIZE = 28

local function OnClick(_, button)
	if button == "RightButton" then
		if InCombatLockdown() then
			ns.Print("cannot unlock frames in combat")
			return
		end
		ns.SetLocked(not ns.DB().locked)
	elseif ns.Options and ns.Options.Open then
		ns.Options.Open()
	end
end

local function OnTooltipShow(tip)
	tip:AddLine("SanctuaryUI", 0.85, 0.72, 0.42)
	tip:AddLine(("|cffffffffLeft-click|r options"), 0.8, 0.8, 0.8)
	tip:AddLine(("|cffffffffRight-click|r %s frames"):format(ns.DB().locked and "unlock" or "lock"), 0.8, 0.8, 0.8)
	tip:AddLine("|cffffffffDrag|r to move", 0.8, 0.8, 0.8)
end

function ns.Minimap.Init()
	local LDB = LibStub("LibDataBroker-1.1", true)
	local DBIcon = LibStub("LibDBIcon-1.0", true)
	if not LDB or not DBIcon or ns.Minimap.object then return end

	ns.Minimap.object = LDB:NewDataObject(NAME, {
		type = "launcher",
		text = NAME,
		icon = ICON,
		iconCoords = { 0, 1, 0, 1 },
		OnClick = OnClick,
		OnTooltipShow = OnTooltipShow,
	})
	DBIcon:Register(NAME, ns.Minimap.object, ns.db.global.minimap)

	-- Older LibDBIcon copies (another addon may load one first) lack these; keep their look then.
	if DBIcon.RemoveButtonBorder and DBIcon.RemoveButtonBackground and DBIcon.SetButtonIcon then
		DBIcon:RemoveButtonBorder(NAME)
		DBIcon:RemoveButtonBackground(NAME)
		DBIcon:SetButtonIcon(NAME, ICON, SIZE, "CENTER", 0, 0)
	end
end

function ns.Minimap.SetShown(show)
	local DBIcon = LibStub("LibDBIcon-1.0", true)
	ns.db.global.minimap.hide = not show
	if DBIcon then
		if show then DBIcon:Show(NAME) else DBIcon:Hide(NAME) end
	end
	local registry = LibStub("AceConfigRegistry-3.0", true)
	if registry then registry:NotifyChange(NAME) end
end
