SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.MiningShare = ns.MiningShare or {}
local S = ns.MiningShare

-- Rock Bottom's shared finds: veins mined where the maps had no spot, passed between miners.
--
--   Live: a new find goes to your party or raid and your guild a few seconds after you mine it
--   (prefix SanctMine, "F1:" then up to nine finds). On login (guild) and on joining a group,
--   your latest finds go out once, so a friend who wasn't there still hears of them. What
--   others tell you is kept account-wide (db.global.miningHeard) and pinned on the maps in blue.
--
--   Strings: Export makes one line of all your finds ("RB1:", the finds, a checksum) to paste to
--   a friend, who imports it, or onto GitHub (the mining finds issue form), where
--   tools/build_mining_data.py merges them into the spots every copy ships with.
--
-- A find is "fe.1417.512.233": the vein's code (MiningData.lua D.CODE), the uiMapID, x and y in
-- thousandths of the map. A find is only taken when that vein already grows on that map, so a
-- stray or made-up message can't put Thorium in Elwynn.

local PREFIX = "SanctMine"
local PER_MESSAGE = 9 -- finds per message, well under the 255-byte limit
local MAX_HEARD = 3000
local GAP = 0.006 -- the same spot, as the book counts it
local FLUSH = 3 -- seconds a new find waits, so a run of finds goes out together
local SYNC_FINDS = 18 -- your latest finds, sent on login and on joining a group
local SYNC_EVERY = 600 -- at most this often per channel
local HEARD_PER_MINUTE = 40 -- from one sender, after which they're ignored for the minute

S.ISSUE_URL = "https://github.com/frznfngrs/SanctuaryUI/issues/new?template=mining-finds.yml"

local function Opt() return ns.DB().mining.share end
local function D() return ns.MiningData end
local function M() return ns.Mining end

local function Readable(v) return v ~= nil and not ns.Secret(v) end

local function Heard()
	local g = ns.db and ns.db.global
	if not g then return {} end
	g.miningHeard = g.miningHeard or {}
	return g.miningHeard
end
S.Heard = Heard

local KEY -- code -> vein key
local function Codes()
	if KEY then return KEY end
	KEY = {}
	for key, code in pairs(D().CODE) do KEY[code] = key end
	return KEY
end

---------------------------------------------------------------------------
-- Finds as text.

local function Round(v) return math.floor(v * 1000 + 0.5) end

function S.Encode(key, map, x, y)
	local code = D().CODE[key]
	if not code then return end
	return ("%s.%d.%d.%d"):format(code, map, math.min(999, Round(x)), math.min(999, Round(y)))
end

-- key, map, x, y; or nil and why.
function S.Decode(part)
	local code, map, x, y = part:match("^(%l%l)%.(%d+)%.(%d+)%.(%d+)$")
	if not code then return nil, "not a find" end
	local key = Codes()[code]
	map, x, y = tonumber(map), tonumber(x), tonumber(y)
	if not key then return nil, "unknown vein" end
	if D().GHOST[key] then return nil, "ghost vein" end
	if not D().MAPS[map] then return nil, "unknown map" end
	if x > 999 or y > 999 then return nil, "off the map" end
	if not (D().SPOTS[key] and D().SPOTS[key][map]) then return nil, "doesn't grow there" end
	return key, map, x / 1000, y / 1000
end

-- A little sum over the text, so a string cut short in a paste is noticed.
local function Sum(text)
	local a, b = 1, 0
	for i = 1, #text do
		a = (a + text:byte(i)) % 65521
		b = (b + a) % 65521
	end
	return ("%04x"):format((b * 65536 + a) % 65536)
end
S.Sum = Sum

---------------------------------------------------------------------------
-- Keeping what's heard.

local function Close(a, b) return math.abs(a - b) < GAP end

-- Add a find told by someone (source: a name, or "import"). Returns "new", "again" (another
-- miner confirms one we had), "known" (the maps or your own finds have it) or "same" (the same
-- source again).
function S.Add(key, map, x, y, source)
	for _, p in ipairs(M().Spots(key, map)) do
		if Close(p[1], x) and Close(p[2], y) then return "known" end
	end
	local log = M().Log and M().Log()
	for _, f in ipairs(log and log.finds or {}) do
		if f[1] == key and f[2] == map and Close(f[3], x) and Close(f[4], y) then return "known" end
	end
	local heard = Heard()
	for _, h in ipairs(heard) do
		if h[1] == key and h[2] == map and Close(h[3], x) and Close(h[4], y) then
			h.who = h.who or {}
			if h.who[source] then return "same" end
			-- Remember up to three tellers; past that only the count grows.
			local names = 0
			for _ in pairs(h.who) do names = names + 1 end
			if names < 3 then h.who[source] = true end
			h.n = (h.n or 1) + 1
			return "again"
		end
	end
	heard[#heard + 1] = { key, map, x, y, t = time(), n = 1, who = { [source] = true } }
	while #heard > MAX_HEARD do table.remove(heard, 1) end
	return "new"
end

---------------------------------------------------------------------------
-- Talking.

local function GroupChannel()
	if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and not IsInGroup(LE_PARTY_CATEGORY_HOME) then
		return "INSTANCE_CHAT"
	elseif IsInRaid() then
		return "RAID"
	elseif IsInGroup() then
		return "PARTY"
	end
end

local function Channels()
	local out = {}
	local opt = Opt()
	local group = opt.group and GroupChannel()
	if group then out[#out + 1] = group end
	if opt.guild and IsInGuild and IsInGuild() then out[#out + 1] = "GUILD" end
	return out
end

local function Send(parts, channels)
	if #parts == 0 or not C_ChatInfo or not C_ChatInfo.SendAddonMessage then return 0 end
	local sent = 0
	for i = 1, #parts, PER_MESSAGE do
		local text = "F1:" .. table.concat(parts, ";", i, math.min(#parts, i + PER_MESSAGE - 1))
		for _, channel in ipairs(channels) do
			local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, text, channel)
			ns.Log("rock bottom: told %s %d finds (%s)", channel, math.min(PER_MESSAGE, #parts - i + 1), tostring(ok and result or "refused"))
			if ok then sent = sent + 1 end
		end
	end
	return sent
end

local queue, flushing = {}, false

local function Flush()
	flushing = false
	local parts = queue
	queue = {}
	Send(parts, Channels())
end

-- A new find of yours: out to the group and guild shortly.
function S.Shout(find)
	if not find then return end
	local part = S.Encode(find[1], find[2], find[3], find[4])
	if not part or #Channels() == 0 then return end
	queue[#queue + 1] = part
	if not flushing and C_Timer then
		flushing = true
		C_Timer.After(FLUSH, function() ns.Try("rock bottom share", Flush) end)
	end
end

-- Your latest finds, once in a while, to a channel that may not have heard them.
local lastSync = {}
local function Sync(channel)
	if not channel or (lastSync[channel] and GetTime() - lastSync[channel] < SYNC_EVERY) then return end
	local log = M().Log and M().Log()
	local finds = log and log.finds or {}
	if #finds == 0 then return end
	lastSync[channel] = GetTime()
	local parts = {}
	for i = #finds, math.max(1, #finds - SYNC_FINDS + 1), -1 do
		local part = S.Encode(finds[i][1], finds[i][2], finds[i][3], finds[i][4])
		if part then parts[#parts + 1] = part end
	end
	Send(parts, { channel })
end

local heardFrom = {} -- sender -> { minute, count }

local function OnMessage(text, channel, sender)
	if not Opt().hear or type(text) ~= "string" or text:sub(1, 3) ~= "F1:" then return end
	sender = Readable(sender) and sender or "?"
	local minute = math.floor(GetTime() / 60)
	local rate = heardFrom[sender]
	if not rate or rate[1] ~= minute then
		rate = { minute, 0 }
		heardFrom[sender] = rate
	end
	local added, maps = 0, {}
	for part in text:sub(4):gmatch("[^;]+") do
		rate[2] = rate[2] + 1
		if rate[2] > HEARD_PER_MINUTE then break end
		local key, map, x, y = S.Decode(part)
		if key then
			local what = S.Add(key, map, x, y, sender)
			if what == "new" or what == "again" then
				added = added + 1
				maps[map] = true
			end
		end
	end
	if added > 0 then
		ns.Log("rock bottom: heard %d finds on %s", added, tostring(channel))
		if ns.MiningMap and ns.MiningMap.Forget then
			for map in pairs(maps) do ns.MiningMap.Forget(map) end
		end
	end
end

---------------------------------------------------------------------------
-- Strings.

-- All your finds as one line: text, count (nil and why when there are none).
function S.Export()
	local log = M().Log and M().Log()
	local parts = {}
	for _, f in ipairs(log and log.finds or {}) do
		local part = S.Encode(f[1], f[2], f[3], f[4])
		if part then parts[#parts + 1] = part end
	end
	if #parts == 0 then return nil, "No finds yet: a find is a vein you mined where the maps had no spot." end
	local body = table.concat(parts, ";")
	return "RB1:" .. body .. ":" .. Sum(body), #parts
end

-- Take in a pasted string (or several). Returns a summary table, or nil and why.
function S.Import(text)
	if type(text) ~= "string" then return nil, "Nothing pasted." end
	local result = { new = 0, again = 0, known = 0, bad = 0, strings = 0 }
	local maps = {}
	for body, sum in text:gmatch("RB1:([%l%d%.;]*):(%x%x%x%x)") do
		if Sum(body) ~= sum:lower() then return nil, "That string is damaged (its checksum doesn't match). Copy it again, all of it." end
		result.strings = result.strings + 1
		for part in body:gmatch("[^;]+") do
			local key, map, x, y = S.Decode(part)
			if key then
				local what = S.Add(key, map, x, y, "import")
				if what == "same" then what = "known" end
				result[what] = result[what] + 1
				maps[map] = true
			else
				result.bad = result.bad + 1
			end
		end
	end
	if result.strings == 0 then return nil, "That isn't a Rock Bottom finds string. They start with RB1:." end
	if ns.MiningMap and ns.MiningMap.Forget then
		for map in pairs(maps) do ns.MiningMap.Forget(map) end
	end
	return result
end

-- Forget what others told you.
function S.ClearHeard()
	wipe(Heard())
	if ns.MiningMap and ns.MiningMap.Forget then ns.MiningMap.Forget() end
end

---------------------------------------------------------------------------

function S.Init()
	if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
		pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
	end
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "CHAT_MSG_ADDON", "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD" }) do
		pcall(events.RegisterEvent, events, event)
	end
	local grouped = false
	events:SetScript("OnEvent", function(_, event, a, b, c, d)
		if event == "CHAT_MSG_ADDON" then
			-- prefix, text, channel, sender
			if Readable(a) and a == PREFIX then ns.Try("rock bottom heard", OnMessage, b, c, d) end
		elseif event == "GROUP_ROSTER_UPDATE" then
			local now = GroupChannel()
			if now and not grouped and Opt().group then
				C_Timer.After(5, function() ns.Try("rock bottom sync", Sync, GroupChannel()) end)
			end
			grouped = now ~= nil
		elseif event == "PLAYER_ENTERING_WORLD" then
			grouped = GroupChannel() ~= nil
			if Opt().guild and C_Timer then
				C_Timer.After(30, function()
					if IsInGuild and IsInGuild() then ns.Try("rock bottom sync", Sync, "GUILD") end
				end)
			end
		end
	end)
end
