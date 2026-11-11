local _, ns = ...

-- Update notices. An addon can't reach the internet, so it learns about new releases from other
-- players: each copy says its version over the hidden addon channel to the group and guild, and
-- answers anyone running an older one. Hearing a newer version prints a line in chat once, and
-- the version is remembered so the next login reminds you until you've updated.

local PREFIX = "SanctuaryUI"
local SEND_DELAY = 10  -- seconds after login or a group change, as other addons do
local REPLY_GAP = 30   -- at most one answer to older copies per channel this often

local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
local MINE = getMeta and getMeta("SanctuaryUI", "Version") or "0"

-- Split "0.13.1" into numbers; nil for anything that isn't a dotted version.
local function Parts(version)
	if type(version) ~= "string" or not version:match("^%d+[%.%d]*$") then return end
	local parts = {}
	for n in version:gmatch("%d+") do parts[#parts + 1] = tonumber(n) end
	return parts
end

-- True when version a is newer than b (0.13.1 > 0.13 > 0.12.9; 0.3.1.1 > 0.3.1).
local function Newer(a, b)
	local pa, pb = Parts(a), Parts(b)
	if not pa or not pb then return false end
	for i = 1, math.max(#pa, #pb) do
		local x, y = pa[i] or 0, pb[i] or 0
		if x ~= y then return x > y end
	end
	return false
end
ns.VersionNewer = Newer

local told = false

local function Global()
	return ns.db and ns.db.global
end

local function Tell(version)
	if told then return end
	told = true
	ns.Print(("version %s is out (you have %s). Update it in WowUp."):format(version, MINE))
end

local function Heard(version)
	if not Newer(version, MINE) then return end
	local global = Global()
	if global and not Newer(global.newestVersion, version) then
		global.newestVersion = version
	end
	Tell(version)
end

local function Send(channel)
	if InCombatLockdown() then return end
	-- The client refuses addon messages in some places (restricted instances); that's fine.
	pcall(C_ChatInfo.SendAddonMessage, PREFIX, MINE, channel)
end

local function GroupChannel()
	if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and not IsInGroup(LE_PARTY_CATEGORY_HOME) then
		return "INSTANCE_CHAT"
	elseif IsInRaid() then
		return "RAID"
	elseif IsInGroup() then
		return "PARTY"
	end
end

local waiting = false
local function Announce()
	waiting = false
	local group = GroupChannel()
	if group then Send(group) end
	if IsInGuild() then Send("GUILD") end
end

local function Queue()
	if waiting then return end
	waiting = true
	C_Timer.After(SEND_DELAY, Announce)
end

local lastReply = {}
local function Reply(channel)
	local now = GetTime()
	if lastReply[channel] and now - lastReply[channel] < REPLY_GAP then return end
	lastReply[channel] = now
	Send(channel)
end

local groupSize = 0
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("CHAT_MSG_ADDON")
events:SetScript("OnEvent", function(_, event, prefix, message, channel)
	if event == "CHAT_MSG_ADDON" then
		if ns.Secret(prefix) or ns.Secret(message) or prefix ~= PREFIX then return end
		if Newer(message, MINE) then
			Heard(message)
		elseif Newer(MINE, message) and not ns.Secret(channel) then
			Reply(channel)
		end
	elseif event == "GROUP_ROSTER_UPDATE" then
		local size = GetNumGroupMembers()
		if size > 1 and size > groupSize then Queue() end
		groupSize = size
	elseif event == "PLAYER_ENTERING_WORLD" then
		local isLogin, isReload = prefix, message
		if isLogin or isReload then
			local global = Global()
			if global and global.newestVersion then
				if Newer(global.newestVersion, MINE) then
					Tell(global.newestVersion)
				else
					global.newestVersion = nil  -- updated since
				end
			end
			groupSize = GetNumGroupMembers()
			Queue()  -- not on every loading screen: that would spam the guild channel
		end
	end
end)

C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
