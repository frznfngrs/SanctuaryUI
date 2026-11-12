-- Totems on the ally ring. The client gives addons no position for a totem, but a totem stays
-- where it was dropped. So when one of your totem casts succeeds (its spell ID is readable in
-- combat) we keep the spot you stood on (your own position is readable outdoors, in combat
-- too) and pin the totem's icon there, its time running out on the icon and its reach
-- outlined in the element's colour. Allies inside the outline are within its reach; the icon
-- greys once you are out of it. A pin goes when its slot empties (the totem ran out, was
-- killed, dismissed or replaced).
--
-- Other shamans: the client hides which spell a group member cast, even out of combat
-- (TotemProbe.lua found that), so their totems can't be read. Instead each SanctuaryUI shaman
-- tells the group, over hidden addon messages, where their totems went down and when they
-- went. Shamans without the addon don't show.
--
-- Where the client hides positions (dungeons) nothing can be pinned, and battlegrounds refuse
-- addon messages. Pins are kept in memory only, so a reload forgets totems already down.
SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI

ns.RingTotems = {}
local T = ns.RingTotems

local PREFIX = "SanctTotem"
local SEGMENTS = 40 -- of each of your reach outlines
local OTHER_SEGMENTS = 24 -- of a group member's
local MAX_OTHERS = 16 -- group members' totems drawn, nearest first
local ICON = 22
local OTHER_ICON = 18
local GRACE = 1.5 -- seconds after the cast before an empty slot counts: it fills a moment later
local FALLBACK_REACH = 20 -- yards, when the spell's text doesn't say
local FALLBACK_TIME = 120 -- seconds, likewise
local NO_REACH = { [6495] = true } -- Sentry Totem: nothing in an area
local RESEND_DELAY = 2 -- after the group changes, tell newcomers what is down
local SWIPE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
-- By element, in Totem.lua's order: earth, fire, water, air.
local COLORS = { { 0.55, 0.85, 0.35 }, { 1, 0.5, 0.15 }, { 0.35, 0.65, 1 }, { 0.85, 0.9, 1 } }

-- Yours: [element] = { spellID, key, icon, north, west, instance, at, reach, duration }
local pins = {}
-- A group member's, by their name: [sender] = { [element] = { key, icon, north, west, instance, reach, start, total } }
local others = {}
-- Widgets 1-4 are yours, by element; 5 on are group members', made when first needed.
local widgets = {}
local layer, ringFrame

local GetSpellTexture = (C_Spell and C_Spell.GetSpellTexture) or GetSpellTexture or function() end
local GetDescription = (C_Spell and C_Spell.GetSpellDescription) or GetSpellDescription or function() end

local function Opt()
	return ns.DB().allyRing
end

local function Plain(value)
	return value ~= nil and not ns.Secret(value)
end

---------------------------------------------------------------------------
-- What a totem spell says about itself: "party members within 20 yards", "for 2 min".

local textCache = {}
local function TextOf(spellID)
	local cached = textCache[spellID]
	if cached then return cached end
	local ok, text = pcall(GetDescription, spellID)
	if ok and Plain(text) and text ~= "" then
		textCache[spellID] = text
		return text
	end
end

local function ReachOf(spellID, key)
	if NO_REACH[key] then return 0 end
	local text = TextOf(spellID)
	return text and tonumber(text:match("(%d+) yards?")) or FALLBACK_REACH
end

local function DurationOf(spellID)
	local text = TextOf(spellID)
	if text then
		local n, unit = text:match("for (%d+) (%a+)")
		n = tonumber(n)
		if n and unit:find("^min") then return n * 60 end
		if n and unit:find("^sec") then return n end
	end
	return FALLBACK_TIME
end

---------------------------------------------------------------------------
-- Telling the group

local function GroupChannel()
	if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and not IsInGroup(LE_PARTY_CATEGORY_HOME) then
		return "INSTANCE_CHAT"
	elseif IsInRaid() then
		return "RAID"
	elseif IsInGroup() then
		return "PARTY"
	end
end

local function Send(text)
	if not Opt().shareTotems then return end
	local channel = GroupChannel()
	if not channel or not C_ChatInfo or not C_ChatInfo.SendAddonMessage then return end
	-- Refused in battlegrounds and during loading screens; nothing to be done there.
	local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, text, channel)
	if not ok then ns.Log("ring totems: send failed, %s", tostring(result)) end
end

local function Remaining(pin)
	return math.max(0, pin.duration - (GetTime() - pin.at))
end

local function SendDown(i)
	local pin = pins[i]
	if not pin then return end
	Send(("D1:%d:%d:%.1f:%.1f:%d:%d:%d:%d"):format(i, pin.key, pin.north, pin.west, pin.instance or 0,
		pin.reach, Remaining(pin) + 0.5, pin.duration))
end

local function SendGone(i)
	Send(("X1:%d"):format(i))
end

---------------------------------------------------------------------------
-- Your pins

local function Changed()
	if ns.AllyRing and ns.AllyRing.Refresh then ns.AllyRing.Refresh() end
end

local function Sweep(i)
	local w = widgets[i]
	if w and pins[i] and not w.fakeAt then
		ns.Totem.Sweep(w.cooldown, ns.Totem.SlotOf(i))
	end
end

-- The client's own start and duration, once the slot has the totem and they're not hidden.
local function Learn(i)
	local pin = pins[i]
	if not pin or not GetTotemInfo then return end
	local _, _, start, duration = GetTotemInfo(ns.Totem.SlotOf(i))
	if Plain(start) and Plain(duration) and duration > 0 then
		pin.at, pin.duration = start, duration
	end
end

-- Drop pins whose slot has emptied, and group members' that have run out.
local function Prune()
	local now, gone = GetTime(), false
	for i = 1, 4 do
		local pin = pins[i]
		if pin and now - pin.at > GRACE and not ns.Totem.SlotDown(ns.Totem.SlotOf(i)) then
			pins[i] = nil
			SendGone(i)
			gone = true
		end
	end
	for sender, set in pairs(others) do
		local any = false
		for i = 1, 4 do
			local pin = set[i]
			if pin and now > pin.start + pin.total + 1 then set[i] = nil end
			if set[i] then any = true end
		end
		if not any then others[sender] = nil end
	end
	if gone then Changed() end
end

function T.Any()
	for i = 1, 4 do
		if pins[i] then return true end
	end
	return false
end

local function OnCast(spellID)
	local i, key = ns.Totem.ElementOfSpell(spellID)
	if not i then return end
	local north, west, instance = ns.MapPins.Here()
	if not north then
		-- Dropped where we can't place it: it still replaces the old one.
		if pins[i] then
			pins[i] = nil
			SendGone(i)
			Changed()
		end
		return
	end
	pins[i] = {
		spellID = spellID, key = key, icon = GetSpellTexture(spellID),
		north = north, west = west, instance = instance, at = GetTime(),
		reach = ReachOf(spellID, key), duration = DurationOf(spellID),
	}
	local w = widgets[i]
	if w and not w.fakeAt then w.icon:SetTexture(pins[i].icon) end
	Sweep(i)
	SendDown(i)
	Changed()
end

---------------------------------------------------------------------------
-- Group members' pins

local function Me(sender)
	local name = UnitName("player")
	return Plain(name) and (sender == name or (Ambiguate and Ambiguate(sender, "none") == name))
end

-- Is this sender in the group? Names only, and never written down.
local function InGroup(sender)
	local short = Ambiguate and Ambiguate(sender, "none") or sender
	local raid = IsInRaid()
	for n = 1, raid and 40 or 4 do
		local unit = (raid and "raid" or "party") .. n
		if UnitExists(unit) then
			local name, realm = UnitName(unit)
			if Plain(name) then
				local full = (Plain(realm) and realm ~= "") and (name .. "-" .. realm) or name
				if full == short or full == sender then return true end
			end
		end
	end
	return false
end

local function Heard(text, sender)
	if not Plain(text) or not Plain(sender) or Me(sender) then return end
	local kind, rest = text:match("^(%u)1:(.*)$")
	if kind == "D" then
		local i, key, north, west, instance, reach, remaining, total = rest:match(
			"^(%d):(%d+):([-%d.]+):([-%d.]+):(%d+):(%d+):(%d+):(%d+)$")
		i = tonumber(i)
		if not i or i < 1 or i > 4 then return end
		total = tonumber(total)
		local set = others[sender] or {}
		others[sender] = set
		set[i] = {
			key = tonumber(key), icon = GetSpellTexture(tonumber(key)),
			north = tonumber(north), west = tonumber(west), instance = tonumber(instance),
			reach = tonumber(reach), total = total, start = GetTime() - (total - tonumber(remaining)),
		}
	elseif kind == "X" then
		local i = tonumber(rest:match("^(%d)$"))
		if i and others[sender] then others[sender][i] = nil end
	end
end

-- After the group changes: forget those who left, and tell newcomers what is down.
local resendQueued = false
local function OnRoster()
	for sender in pairs(others) do
		if not IsInGroup() or not InGroup(sender) then others[sender] = nil end
	end
	if resendQueued or not T.Any() or not IsInGroup() then return end
	resendQueued = true
	C_Timer.After(RESEND_DELAY, function()
		resendQueued = false
		for i = 1, 4 do SendDown(i) end
	end)
end

---------------------------------------------------------------------------
-- Drawing

local function MakeWidget(i, size, segments, lineAlpha)
	local w = { segments = segments, lines = {}, lineAlpha = lineAlpha }
	for k = 1, segments do
		local l = layer:CreateLine(nil, "BACKGROUND")
		l:SetThickness(segments == SEGMENTS and 1.5 or 1)
		l:Hide()
		w.lines[k] = l
	end
	local holder = CreateFrame("Frame", nil, layer)
	holder:SetSize(size, size)
	holder:SetFrameLevel(layer:GetFrameLevel() + (i <= 4 and 2 or 1)) -- yours over theirs
	holder:EnableMouse(false)
	w.rim = holder:CreateTexture(nil, "BACKGROUND")
	w.rim:SetPoint("CENTER")
	w.rim:SetSize(size + 7, size + 7)
	ns.MapPins.SetCell(w.rim, "pip")
	w.icon = holder:CreateTexture(nil, "ARTWORK")
	w.icon:SetAllPoints()
	w.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	ns.Art.MaskCircle(w.icon, holder)
	w.cooldown = CreateFrame("Cooldown", nil, holder, "CooldownFrameTemplate")
	w.cooldown:SetAllPoints()
	pcall(w.cooldown.SetSwipeTexture, w.cooldown, SWIPE)
	pcall(w.cooldown.SetUseCircularEdge, w.cooldown, true)
	pcall(w.cooldown.SetDrawEdge, w.cooldown, false)
	pcall(w.cooldown.SetHideCountdownNumbers, w.cooldown, true)
	w.cooldown:SetReverse(true)
	holder:Hide()
	w.holder = holder
	widgets[i] = w
	return w
end

-- Colour a widget for an element, once per change.
local function Tint(w, element)
	if w.element == element then return end
	w.element = element
	local color = COLORS[element]
	w.rim:SetVertexColor(color[1], color[2], color[3])
	for k = 1, w.segments do
		w.lines[k]:SetColorTexture(color[1], color[2], color[3], w.lineAlpha)
	end
end

local function Build(frame)
	ringFrame = frame
	layer = CreateFrame("Frame", nil, frame)
	layer:SetAllPoints()
	layer:SetFrameLevel(frame:GetFrameLevel() + 1) -- under the ally pips (+4) and the target's halo
	layer:EnableMouse(false)
	for i = 1, 4 do
		local w = MakeWidget(i, ICON, SEGMENTS, 0.45)
		Tint(w, i)
		if pins[i] then
			w.icon:SetTexture(pins[i].icon)
			Sweep(i)
		end
	end
end

local function HideOne(w)
	w.holder:Hide()
	for k = 1, w.segments do w.lines[k]:Hide() end
end

function T.Hide()
	if not layer then return end
	for _, w in pairs(widgets) do HideOne(w) end
end

-- Ring space: a spot east/north of you (yards, north-up) turned so you face up, its distance
-- squeezed the way the ally pips' is.
local function ToRing(east, north, c, s, radiusFor)
	local x, y = east * c + north * s, -east * s + north * c
	local d = math.sqrt(x * x + y * y)
	if d < 0.01 then return 0, radiusFor(0) end
	local r = radiusFor(d)
	return x / d * r, y / d * r
end

local function Place(w, east, up, reach, c, s, radiusFor, outline)
	local x, y = ToRing(east, up, c, s, radiusFor)
	w.holder:ClearAllPoints()
	w.holder:SetPoint("CENTER", ringFrame, "CENTER", x, y)
	-- Out of its reach yourself: grey and dimmed, the way an unlit totem socket looks.
	local away = reach > 0 and math.sqrt(east * east + up * up) > reach
	w.icon:SetDesaturated(away)
	w.holder:SetAlpha(away and 0.6 or 1)
	w.holder:Show()
	local lines, segments = w.lines, w.segments
	if outline and reach > 0 then
		local px, py
		for k = 0, segments do
			local a = k / segments * 2 * math.pi
			local qx, qy = ToRing(east + math.cos(a) * reach, up + math.sin(a) * reach, c, s, radiusFor)
			if k > 0 then
				local l = lines[k]
				l:SetStartPoint("CENTER", ringFrame, px, py)
				l:SetEndPoint("CENTER", ringFrame, qx, qy)
				l:Show()
			end
			px, py = qx, qy
		end
	else
		for k = 1, segments do lines[k]:Hide() end
	end
end

-- Preview stand-ins on a looping minute: your earth ahead and to the right and fire behind,
-- and a group member's Windfury off to the left.
local FAKE = { [1] = { 9, 15, 20, 8071 }, [2] = { -16, -11, 8, 1535 } }
local FAKE_OTHER = { -24, 6, 20, 8512, 4 }
local fakeStart

local function FakeSweep(w, key)
	if w.fakeAt ~= fakeStart then
		w.fakeAt = fakeStart
		w.ident = nil
		w.icon:SetTexture(GetSpellTexture(key))
		pcall(CooldownFrame_Set, w.cooldown, fakeStart, 60, true)
	end
end

local function EndFake(w)
	if not w.fakeAt then return false end
	w.fakeAt = nil
	w.cooldown:Clear()
	return true
end

-- Group members' totems near you, nearest first, into widgets 5 on.
local near = {}
local function DrawOthers(north, west, instance, c, s, radiusFor, outline, preview)
	local n = 0
	if preview then
		n = 1
		near[1] = near[1] or {}
		local f = near[1]
		f.east, f.up, f.reach, f.key, f.element, f.fake = FAKE_OTHER[1], FAKE_OTHER[2], FAKE_OTHER[3], FAKE_OTHER[4], FAKE_OTHER[5], true
	elseif north then
		local sight = Opt().maxYards
		for sender, set in pairs(others) do
			for i = 1, 4 do
				local pin = set[i]
				if pin and pin.instance == instance then
					local east, up = -(pin.west - west), pin.north - north
					local yards = math.sqrt(east * east + up * up)
					if yards <= sight + pin.reach then
						n = n + 1
						local f = near[n] or {}
						near[n] = f
						f.east, f.up, f.reach, f.key, f.element, f.fake = east, up, pin.reach, pin.key, i, nil
						f.yards, f.pin, f.ident = yards, pin, sender .. i .. pin.start
					end
				end
			end
		end
		for k = n + 1, #near do near[k].yards = math.huge end
		table.sort(near, function(a, b) return (a.yards or math.huge) < (b.yards or math.huge) end)
	end
	n = math.min(n, MAX_OTHERS)
	for k = 1, n do
		local f = near[k]
		local w = widgets[4 + k] or MakeWidget(4 + k, OTHER_ICON, OTHER_SEGMENTS, 0.28)
		Tint(w, f.element)
		if f.fake then
			FakeSweep(w, f.key)
		else
			EndFake(w)
			if w.ident ~= f.ident then
				w.ident = f.ident
				w.icon:SetTexture(f.pin.icon)
				pcall(CooldownFrame_Set, w.cooldown, f.pin.start, f.pin.total, true)
			end
		end
		Place(w, f.east, f.up, f.reach, c, s, radiusFor, outline)
	end
	for k = 4 + n + 1, #widgets do HideOne(widgets[k]) end
end

-- Called from the ally ring's Draw. north/west/instance: where you are (nil in a preview
-- without a position); c, s: your facing's cosine and sine; radiusFor: yards to ring units.
function T.Draw(frame, north, west, instance, c, s, radiusFor, preview)
	local opt = Opt()
	if not opt.totems and not opt.groupTotems then
		T.Hide()
		return
	end
	if not layer then Build(frame) end
	if preview then
		local now = GetTime()
		if not fakeStart or now - fakeStart > 60 then fakeStart = now end
	else
		Prune()
		fakeStart = nil
	end
	local mine = opt.totems and (not preview or ns.Totem.Knows())
	for i = 1, 4 do
		local w = widgets[i]
		local east, up, reach
		if mine and preview and FAKE[i] then
			FakeSweep(w, FAKE[i][4])
			east, up, reach = FAKE[i][1], FAKE[i][2], FAKE[i][3]
		else
			if EndFake(w) and pins[i] then
				w.icon:SetTexture(pins[i].icon)
				Sweep(i)
			end
			local pin = pins[i]
			if mine and pin and north and pin.instance == instance then
				east, up, reach = -(pin.west - west), pin.north - north, pin.reach
			end
		end
		if east then
			Place(w, east, up, reach, c, s, radiusFor, opt.totemReach)
		else
			HideOne(w)
		end
	end
	if opt.groupTotems then
		DrawOthers(north, west, instance, c, s, radiusFor, opt.totemReach, preview)
	else
		for k = 5, #widgets do HideOne(widgets[k]) end
	end
end

function T.Init()
	if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
		C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
	end
	local events = CreateFrame("Frame")
	pcall(events.RegisterUnitEvent, events, "UNIT_SPELLCAST_SUCCEEDED", "player")
	for _, event in ipairs({ "PLAYER_TOTEM_UPDATE", "CHAT_MSG_ADDON", "GROUP_ROSTER_UPDATE" }) do
		pcall(events.RegisterEvent, events, event)
	end
	events:SetScript("OnEvent", function(_, event, a, b, c, d)
		if event == "UNIT_SPELLCAST_SUCCEEDED" then
			if Plain(c) then OnCast(c) end
		elseif event == "CHAT_MSG_ADDON" then
			-- prefix, text, channel, sender
			if Plain(a) and a == PREFIX then
				local ok, err = pcall(Heard, b, d)
				if not ok then ns.Log("ring totems: bad message, %s", tostring(err)) end
			end
		elseif event == "GROUP_ROSTER_UPDATE" then
			OnRoster()
		else
			for i = 1, 4 do
				Learn(i)
				Sweep(i)
			end
			Prune()
		end
	end)
end
