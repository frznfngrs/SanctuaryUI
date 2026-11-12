SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI

-- Update notices. An addon can't reach the internet, so it learns about new releases from other
-- players: each copy says the newest version it knows of over the hidden addon channel to the
-- group and guild, and answers anyone who knows of an older one. Hearing a newer version prints a
-- line in chat (once per version), and it is remembered so the next login reminds you until you've
-- updated. Passing on what it heard, not just its own version, lets news hop from one group or
-- guild to the next through copies that haven't updated yet; few players run SanctuaryUI, so
-- waiting to meet someone who has updated reached almost nobody.
--
-- To reach everyone on the realm, not just group and guild, each copy also joins a temporary chat
-- channel a little after login (after General and Trade, so their numbers don't move) and says its
-- version there once. Nothing but addon messages goes over it, so it shows nothing in chat; its
-- join notices are filtered out. /sanctuary updates off leaves it.

local PREFIX = "SanctuaryUI"
local SEND_DELAY = 10  -- seconds after login or a group change, as other addons do
local REPLY_GAP = 30   -- at most one answer to older copies per channel this often
local CHANNEL = "SanctuaryUI"  -- the realm-wide chat channel
local JOIN_DELAY = 20  -- seconds after login: the client's own channels join first
local REPLY_SPREAD = 8 -- answers wait 2 to 2+this seconds; the first one stops the rest

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

-- A troll could say "99.0", and passing news on would spread it to everyone for good. A real
-- release never jumps more than one major version, so anything further is ignored.
local function Plausible(version)
	local p, m = Parts(version), Parts(MINE)
	return p and m and #version <= 20 and p[1] <= m[1] + 1
end

local told  -- the version last printed this session

local function Global()
	return ns.db and ns.db.global
end

-- The newest version this copy knows of: its own, or one heard since.
local function Newest()
	local global = Global()
	local heard = global and global.newestVersion
	if heard and Newer(heard, MINE) and Plausible(heard) then return heard end
	return MINE
end

local function Tell(version)
	if told and not Newer(version, told) then return end
	told = version
	ns.Print(("version %s is out (you have %s). Update it in WowUp."):format(version, MINE))
end

local function Heard(version)
	if not Newer(version, MINE) or not Plausible(version) then return end
	local global = Global()
	if global and not Newer(global.newestVersion, version) then
		global.newestVersion = version
	end
	Tell(version)
end

-- The channel's number while joined, or nil.
local function ChannelID()
	local ok, id = pcall(GetChannelName, CHANNEL)
	if ok and type(id) == "number" and id > 0 then return id end
end

local function ChannelEnabled()
	local global = Global()
	return not (global and global.updateChannel == false)
end

local function Send(channel)
	if InCombatLockdown() then return end
	local target
	if channel == "CHANNEL" then
		target = ChannelID()
		if not target then return end
	end
	-- The client refuses addon messages in some places (restricted instances); that's fine.
	local newest = Newest()
	local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, newest, channel, target)
	ns.Log("version: said %s to %s (%s, %s)", newest, channel, tostring(ok), tostring(result))
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

-- Answers to older copies wait a random moment and are dropped if another copy says the same
-- version first, so one login on a busy channel draws one or two answers, not one from everyone.
local lastReply, pending = {}, {}
local function Reply(channel)
	local now = GetTime()
	if pending[channel] or (lastReply[channel] and now - lastReply[channel] < REPLY_GAP) then return end
	pending[channel] = true
	C_Timer.After(2 + math.random() * REPLY_SPREAD, function()
		if not pending[channel] then return end
		pending[channel] = nil
		lastReply[channel] = GetTime()
		Send(channel)
	end)
end

-- Join and leave notices for the channel ("Joined Channel: [5. SanctuaryUI]") stay out of chat.
local function IsOurs(text)
	return type(text) == "string" and not ns.Secret(text)
		and (text:lower() == CHANNEL:lower() or text:lower():match("^%d+%. " .. CHANNEL:lower() .. "$"))
end
local function NoticeFilter(_, _, _, _, _, channelString, _, _, _, _, channelName)
	if IsOurs(channelName) or IsOurs(channelString) then return true end
end
local addFilter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
if addFilter then
	for _, event in ipairs({ "CHAT_MSG_CHANNEL_NOTICE", "CHAT_MSG_CHANNEL_NOTICE_USER" }) do
		pcall(addFilter, event, NoticeFilter)
	end
end

local function JoinChannel(announce)
	if not ChannelEnabled() then return end
	if ChannelID() then
		if announce then Send("CHANNEL") end
		return
	end
	if InCombatLockdown() then
		C_Timer.After(30, function() JoinChannel(announce) end)
		return
	end
	local ok, err = pcall(JoinTemporaryChannel, CHANNEL)
	ns.Log("version: joining channel (%s, %s)", tostring(ok), tostring(err))
	C_Timer.After(5, function()
		local id = ChannelID()
		ns.Log("version: channel is %s", tostring(id))
		if id then Send("CHANNEL") end  -- a fresh join always says hello
	end)
end

-- /sanctuary updates on|off: whether to use the realm channel. Off leaves it now.
function ns.UpdateChannel(on)
	local global = Global()
	if on == nil then
		local id = ChannelID()
		ns.Print(("update notices over the realm channel are %s%s. You have %s; newest heard: %s.")
			:format(ChannelEnabled() and "on" or "off", id and (" (channel " .. id .. ")") or ", not joined",
				MINE, Newest()))
		return
	end
	if global then global.updateChannel = on and nil or false end
	if on then
		JoinChannel(true)
	elseif ChannelID() then
		pcall(LeaveChannelByName, CHANNEL)
	end
	ns.Print("update notices over the realm channel " .. (on and "on." or "off."))
end

local groupSize = 0
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("CHAT_MSG_ADDON")
events:SetScript("OnEvent", function(_, event, prefix, message, channel)
	if event == "CHAT_MSG_ADDON" then
		if ns.Secret(prefix) or ns.Secret(message) or ns.Secret(channel) or prefix ~= PREFIX then return end
		if Newer(message, MINE) then
			ns.Log("version: heard %s on %s", message, tostring(channel))
			Heard(message)
		end
		local newest = Newest()
		if Newer(newest, message) then
			Reply(channel)
		elseif Parts(message) then
			pending[channel] = nil  -- someone already said what this copy would, or newer
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
				if Newest() ~= MINE then
					Tell(global.newestVersion)
				else
					global.newestVersion = nil  -- updated since, or not believable
				end
			end
			groupSize = GetNumGroupMembers()
			Queue()  -- not on every loading screen: that would spam the guild channel
			-- The channel outlives a reload, so only a login says hello there again.
			C_Timer.After(isLogin and JOIN_DELAY or 1, function() JoinChannel(isLogin) end)
		end
	end
end)

C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
