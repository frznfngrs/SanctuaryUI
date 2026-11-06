SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.Blizzard = ns.Blizzard or {}

-- Frames this cluster replaces. Bags, chat, and the minimap stay. The micro menu is
-- replaced by the D3 menu buttons in the console.
local FRAME_NAMES = {
	"MainActionBar",
	"StanceBar",
	"StanceBarFrame",
	"PetActionBar",
	"PetActionBarFrame",
	"PossessActionBar",
	"PossessBarFrame",
	"OverrideActionBar",
	"PlayerFrame",
	"TargetFrame",
	"StatusTrackingBarManager",
	"MainStatusTrackingBarContainer",
}

-- Hidden only while the "hide micro menu" option is on.
local MICRO_NAMES = { "MicroMenuContainer", "MicroMenu" }

local function Suppress(frame)
	if not frame or not frame.Show then return end
	if not frame.sanctuaryHooked then
		frame.sanctuaryHooked = true
		hooksecurefunc(frame, "Show", function(self)
			if InCombatLockdown() then return end
			if self.sanctuaryAllow then return end
			self:Hide()
		end)
	end
	if InCombatLockdown() then return end
	frame:Hide()
	frame:SetAlpha(0)
	pcall(frame.EnableMouse, frame, false)
end

function ns.Blizzard.Hide()
	if InCombatLockdown() then return end
	if not ns.Hider then
		ns.Hider = CreateFrame("Frame", "SanctuaryUIHider", UIParent)
		ns.Hider:Hide()
	end
	for i = 1, #FRAME_NAMES do
		local frame = _G[FRAME_NAMES[i]]
		if frame then
			pcall(frame.SetParent, frame, ns.Hider)
			pcall(Suppress, frame)
		end
	end
	for i = 1, 12 do
		pcall(Suppress, _G["ActionButton" .. i])
	end
	ns.Blizzard.MicroMenu(not ns.DB().hideMicroMenu)
	if ns.DB().totems.enabled and _G.TotemFrame then
		pcall(_G.TotemFrame.SetParent, _G.TotemFrame, ns.Hider)
		pcall(Suppress, _G.TotemFrame)
	end
	-- Blizzard's bag buttons, while the SanctuaryUI bag window (which has its own bag slots) is on.
	if ns.DB().bags.enabled then
		for _, name in ipairs({ "BagsBar", "MicroButtonAndBagsBar" }) do
			local frame = _G[name]
			if frame then
				pcall(frame.SetParent, frame, ns.Hider)
				pcall(Suppress, frame)
			end
		end
	end
end

local function Restore(frame, parent)
	if not frame then return end
	frame.sanctuaryAllow = true
	if parent and frame:GetParent() == ns.Hider then
		pcall(frame.SetParent, frame, parent)
	end
	frame:SetAlpha(1)
	pcall(frame.EnableMouse, frame, true)
	frame:Show()
end

-- Show or hide Blizzard's micro menu. Hiding it again after a restore works through the
-- same Show hook, so the flag is the switch.
function ns.Blizzard.MicroMenu(show)
	if InCombatLockdown() then return end
	local container = _G.MicroMenuContainer
	if container or _G.MicroMenu then
		for _, name in ipairs(MICRO_NAMES) do
			local frame = _G[name]
			if frame then
				if show then
					Restore(frame, name == "MicroMenu" and container or UIParent)
				else
					frame.sanctuaryAllow = nil
					pcall(frame.SetParent, frame, ns.Hider)
					pcall(Suppress, frame)
				end
			end
		end
	elseif type(MICRO_BUTTONS) == "table" then
		-- Clients without a micro menu container: the buttons one by one, in place.
		for _, name in ipairs(MICRO_BUTTONS) do
			local frame = _G[name]
			if frame then
				if show then
					Restore(frame)
				else
					frame.sanctuaryAllow = nil
					pcall(Suppress, frame)
				end
			end
		end
	end
end
