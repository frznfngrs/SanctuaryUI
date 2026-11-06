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
	"StatusTrackingBarManager",
	"MainStatusTrackingBarContainer",
}

-- Hidden where they are, never moved to the hider: Blizzard code calls methods on their
-- parent (MainStatusTrackingBarContainer:GetStatusTrackingManager() is its GetParent(), and
-- Edit Mode calls CheckForLayoutChange on it). Their parent is hidden, which is enough.
local KEEP_PARENT = {
	MainStatusTrackingBarContainer = true,
}

-- Hidden only while the SanctuaryUI part that replaces them is on (portraits, target plate).
local REPLACED_BY = {
	PlayerFrame = function(db) return db.portraits.enabled end,
	TargetFrame = function(db) return db.target.enabled end,
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
		local name = FRAME_NAMES[i]
		local frame = _G[name]
		if frame then
			if not KEEP_PARENT[name] then
				pcall(frame.SetParent, frame, ns.Hider)
			end
			pcall(Suppress, frame)
		end
	end
	ns.Blizzard.Replaced()
	for i = 1, 12 do
		pcall(Suppress, _G["ActionButton" .. i])
	end
	ns.Blizzard.MicroMenu(not ns.DB().hideMicroMenu)
	-- Blizzard's buff frames are never hidden now: SanctuaryUI's buffs are those frames,
	-- moved and dressed (Auras.lua), since only Blizzard can read your buffs in combat.
	ns.Blizzard.Auras(true)
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

-- Blizzard's buff, debuff and weapon enchant frames. Only ever shown now (see Hide); hiding
-- stays for clients where something else wants them gone.
local AURA_NAMES = { "BuffFrame", "DebuffFrame", "TemporaryEnchantFrame" }

function ns.Blizzard.Auras(show)
	if InCombatLockdown() then return end
	for _, name in ipairs(AURA_NAMES) do
		local frame = _G[name]
		if frame then
			if show then
				if frame:GetParent() == ns.Hider then
					Restore(frame, UIParent)
				end
			else
				frame.sanctuaryAllow = nil
				pcall(frame.SetParent, frame, ns.Hider)
				pcall(Suppress, frame)
			end
		end
	end
end

function ns.Blizzard.Replaced()
	if InCombatLockdown() then return end
	local db = ns.DB()
	for name, replaced in pairs(REPLACED_BY) do
		local frame = _G[name]
		if frame then
			if replaced(db) then
				frame.sanctuaryAllow = nil
				pcall(frame.SetParent, frame, ns.Hider)
				pcall(Suppress, frame)
			elseif frame:GetParent() == ns.Hider then
				Restore(frame, UIParent)
			end
		end
	end
end
