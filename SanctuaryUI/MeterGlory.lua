SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.MeterGlory = ns.MeterGlory or {}

-- The damage meter's competitive side, on your own screen only: nothing is said to the group.
--
--   In a fight (rank is the one thing the game leaves readable in combat, see Meter.lua):
--     taking the lead in damage lights the console angel's eyes, flashes your rail and says so;
--     losing it puts the eyes out and wakes the gargoyle's for a moment.
--   When a fight ends and its numbers open up (MeterHistory.lua has just saved it):
--     a banner for finishing on top, for a streak of fights on top, and for a personal best;
--     your rail turns molten while a streak of three or more stands;
--     the rival named in the options gets a running tally under the list.
--   Leaving a dungeon or raid: a "Run complete" line with a button for the Run Report
--     (RunReport.lua), and the awards in chat if asked for.

local G = ns.MeterGlory
local SETTLE = 6 -- seconds into a fight before the lead counts
local STEADY = 3 -- polls in a row (half a second each) before a change of lead is believed
local QUIET = 8 -- seconds between lead banners
local TOP_SECONDS = 15 -- a fight this long can be "won"
local SOUND = { lead = 878, lost = 847, top = 619, record = 888 }

local banner, queue, showing = nil, {}, false
local inCombat, started = false, 0
local leading, pending, lastToast = nil, 0, 0
local litByUs = {}
local sincePoll = 0

local function Opt()
	return ns.DB().meter
end

local function Secret(value) return ns.Secret(value) end

local function On(key)
	local opt = Opt()
	return opt.enabled and opt.glory and opt[key] and true or false
end

---------------------------------------------------------------------------
-- The banner: a small gold line (and sometimes a smaller one under a thin rule) that sits
-- against the meter, with a pulse on the meter's title strip. Nothing in the middle of the screen.

local function Play(id)
	if id and On("glorySounds") and PlaySound then pcall(PlaySound, id, "SFX") end
end

local function Next()
	local item = table.remove(queue, 1)
	if not item then
		showing = false
		banner:Hide()
		return
	end
	showing = true
	local L = ns.Meter.Lib
	-- Against the meter: above it, or below when it sits at the top of the screen.
	local holder = ns.Meter.Holder and ns.Meter.Holder()
	banner:ClearAllPoints()
	if holder then
		banner:SetScale(holder:GetScale() * (Opt().gloryScale or 1))
		local place = Opt().gloryPlace
		if place ~= "above" and place ~= "below" then
			local top, screen = holder:GetTop(), UIParent:GetTop()
			local room = top and screen and (screen / holder:GetScale() - top) or 100
			place = room < 60 and "below" or "above"
		end
		if place == "below" then
			banner:SetPoint("TOP", holder, "BOTTOM", 14, -4)
		else
			banner:SetPoint("BOTTOM", holder, "TOP", 14, 2)
		end
	else
		banner:SetPoint("TOP", UIParent, "TOP", 0, -170)
	end
	banner.title:SetFont(L.TitleFont(), item.small and 14 or 17, "")
	banner.title:SetText(item.title)
	banner.sub:SetFont(L.BodyFont(), 11, "")
	banner.sub:SetText(item.sub or "")
	banner.rule:SetShown(item.sub ~= nil and item.sub ~= "")
	banner.hold:SetDuration(item.small and 1.8 or 3.4)
	if not item.small and ns.Meter.FlashHead then ns.Meter.FlashHead() end
	banner:SetAlpha(0)
	banner:Show()
	banner.anim:Stop()
	banner.anim:Play()
	Play(item.sound)
end

local function BuildBanner()
	local L = ns.Meter.Lib
	banner = CreateFrame("Frame", "SanctuaryUIMeterBanner", UIParent)
	banner:SetFrameStrata("MEDIUM")
	banner:SetSize(300, 44)
	banner:EnableMouse(false)
	banner:Hide()
	banner.title = L.Text(banner, L.TitleFont(), 17, L.GOLD, "CENTER")
	banner.title:SetShadowOffset(1, -1)
	banner.title:SetPoint("TOP", 0, -2)
	local rule = banner:CreateTexture(nil, "ARTWORK")
	rule:SetSize(200, 6)
	rule:SetPoint("TOP", banner.title, "BOTTOM", 0, -1)
	banner.rule = rule
	local hot = ns.Art.Path("hotline")
	if hot then rule:SetTexture(hot) else rule:SetColorTexture(L.GOLD[1], L.GOLD[2], L.GOLD[3], 0.6) end
	banner.sub = L.Text(banner, L.BodyFont(), 11, L.CREAM, "CENTER")
	banner.sub:SetShadowOffset(1, -1)
	banner.sub:SetPoint("TOP", rule, "BOTTOM", 0, -1)
	banner.anim = banner:CreateAnimationGroup()
	local fadeIn = banner.anim:CreateAnimation("Alpha")
	fadeIn:SetFromAlpha(0)
	fadeIn:SetToAlpha(1)
	fadeIn:SetDuration(0.25)
	fadeIn:SetOrder(1)
	banner.hold = banner.anim:CreateAnimation("Alpha")
	banner.hold:SetFromAlpha(1)
	banner.hold:SetToAlpha(1)
	banner.hold:SetDuration(3.2)
	banner.hold:SetOrder(2)
	local fadeOut = banner.anim:CreateAnimation("Alpha")
	fadeOut:SetFromAlpha(1)
	fadeOut:SetToAlpha(0)
	fadeOut:SetDuration(0.8)
	fadeOut:SetOrder(3)
	banner.anim:SetScript("OnFinished", Next)
end

-- title and sub may be secret strings (a name in combat): they are only ever drawn.
function G.Banner(title, sub, sound, small)
	if not banner then BuildBanner() end
	queue[#queue + 1] = { title = title, sub = sub, sound = sound, small = small }
	if not showing then Next() end
end

---------------------------------------------------------------------------
-- The statues' eyes (StatueEyes.lua's preview frames, which run in combat). Only eyes this
-- file lit are put out again, so a preview the player started stays.

local function Eyes(key, on)
	local S = ns.StatueEyes
	if not S or not S.Preview or not S.Previewing or not On("gloryStatues") and on then return end
	if on and not S.Previewing(key) then
		if pcall(S.Preview, key) then litByUs[key] = true end
	elseif not on and litByUs[key] then
		litByUs[key] = nil
		if S.Previewing(key) then pcall(S.Preview, key) end
	end
end

local function EyesOut()
	Eyes("angel", false)
	Eyes("gargoyle", false)
end

---------------------------------------------------------------------------
-- In the fight: who leads

-- Your place among the players in the current fight, how many there are, and the leader.
local function Standing()
	local L = ns.Meter.Lib
	local session = L.Available() and L.Fetch("current", Enum.DamageMeterType.DamageDone)
	if not session then return nil end
	local place, count, leader
	for _, s in ipairs(session.combatSources) do
		if L.IsPlayerClass(s.classFilename) then
			count = (count or 0) + 1
			leader = leader or s
			if not Secret(s.isLocalPlayer) and s.isLocalPlayer then place = count end
		end
	end
	return place, count or 0, leader
end

local function Poll()
	if not On("gloryLead") or GetTime() - started < SETTLE then return end
	if Opt().gloryGroupOnly ~= false and not (IsInGroup and IsInGroup()) then return end
	local place, count, leader = Standing()
	if not place or count < 2 then return end
	local lead = place == 1
	if leading == nil then
		-- The first look only sets the scene.
		leading = lead
		Eyes("angel", lead)
		return
	end
	if lead == leading then
		pending = 0
		return
	end
	pending = pending + 1
	if pending < STEADY then return end
	leading, pending = lead, 0
	local loud = GetTime() - lastToast >= QUIET
	if loud then lastToast = GetTime() end
	if lead then
		Eyes("gargoyle", false)
		Eyes("angel", true)
		if ns.Meter.FlashMine then ns.Meter.FlashMine() end
		if loud then G.Banner("You take the lead", nil, SOUND.lead, true) end
	else
		Eyes("angel", false)
		Eyes("gargoyle", true)
		C_Timer.After(4, function() if not leading then Eyes("gargoyle", false) end end)
		if loud then
			-- The leader's name is secret in combat; it can still be put into a line and drawn.
			local ok, line = pcall(string.format, "%s takes the lead", leader and leader.name)
			G.Banner(ok and line or "You lost the lead", nil, SOUND.lost, true)
		end
	end
end

---------------------------------------------------------------------------
-- The fight is over and saved

local function Name(name, class)
	local L = ns.Meter.Lib
	return L.ShortName(name, class == nil or L.IsPlayerClass(class)) or "?"
end

function G.OnFire()
	local opt = Opt()
	if not (opt.glory and opt.gloryStreakRail ~= false) then return false end
	local m = ns.MeterHistory and ns.MeterHistory.Store()
	return m ~= nil and (m.streak or 0) >= 3
end

-- Returns what to add to the verdict line under the meter.
function G.FightEnded(fight, outcome)
	EyesOut()
	leading = nil
	if not Opt().glory or not outcome then return nil end
	local L = ns.Meter.Lib
	local won = outcome.size > 1 and outcome.rank == 1 and (fight.dur or 0) >= TOP_SECONDS
	if On("gloryBanners") then
		if won then
			local streak = outcome.streak or 0
			if streak == 3 or (streak >= 5 and streak % 5 == 0) then
				G.Banner("On a streak", ("%d fights in a row on top"):format(streak), SOUND.record)
			else
				local sub = outcome.margin and outcome.lead and ("%d%% ahead of %s"):format(outcome.margin * 100 + 0.5, Name(outcome.lead, outcome.leadClass)) or nil
				G.Banner("Top damage", sub, SOUND.top)
			end
		end
		if outcome.best then
			G.Banner("New record", ("%s damage per second in %s (was %s)"):format(L.Short(outcome.best.dps), outcome.best.label, L.Short(outcome.best.was)), SOUND.record)
		end
	end
	local extra = {}
	if outcome.best then
		extra[#extra + 1] = ("New record: %s dps."):format(L.Short(outcome.best.dps))
	elseif outcome.bestStands then
		extra[#extra + 1] = ("Your best in %s: %s dps."):format(outcome.bestStands.label, L.Short(outcome.bestStands.dps))
	end
	if outcome.rival then
		local r = outcome.rival
		extra[#extra + 1] = ("%s %s (%d-%d)."):format(r.won and "You beat" or "You lost to", Name(r.name, r.class), r.wins, r.losses)
	end
	if ns.Meter.Redraw then ns.Meter.Redraw() end -- the molten rail comes and goes with the streak
	return table.concat(extra, " ")
end

---------------------------------------------------------------------------
-- The run is over

function G.Awards(run, quiet)
	local awards, fights, topped = ns.MeterHistory.Awards(run)
	if not awards then
		if not quiet then ns.Print("no awards yet: they need at least three group fights inside a dungeon or raid.") end
		return
	end
	local L = ns.Meter.Lib
	ns.Print(("run awards, over %d fights (only you see these):"):format(fights))
	for _, a in ipairs(awards) do
		local value = a.count and tostring(a.value) or L.Short(a.value)
		ns.Print(("  %s: %s%s|r (%s)"):format(a.title, a.me and "|cffe8c77a" or "|cffffffff", Name(a.name, a.class), value))
	end
	if On("gloryBanners") and Opt().runBanner == false then
		G.Banner("Run complete", ("You topped %d of %d fights. The awards are in chat."):format(topped, fights), SOUND.top)
	end
end

function G.RunEnded(run)
	local opt = Opt()
	if opt.enabled and opt.runBanner ~= false and ns.RunReport and ns.RunReport.RunEnded then
		local ok, err = pcall(ns.RunReport.RunEnded, run)
		if not ok then ns.Log("run banner: %s", tostring(err)) end
	end
	if opt.glory and opt.gloryAwards then G.Awards(run, true) end
end

-- /sanctuary meter glory: every surprise once, with made-up names, to see and hear them.
function G.Test()
	local opt = Opt()
	if not (opt.enabled and opt.glory) then
		ns.Print("turn on the damage meter and its competition options first.")
		return
	end
	G.Banner("You take the lead", nil, SOUND.lead, true)
	if ns.Meter.FlashMine then ns.Meter.FlashMine() end
	Eyes("angel", true)
	C_Timer.After(3, function()
		Eyes("angel", false)
		Eyes("gargoyle", true)
		C_Timer.After(4, function() Eyes("gargoyle", false) end)
	end)
	G.Banner("Thalric takes the lead", nil, SOUND.lost, true)
	G.Banner("Top damage", "12% ahead of Thalric", SOUND.top)
	G.Banner("On a streak", "3 fights in a row on top", SOUND.record)
	G.Banner("New record", "1,284 damage per second in a group fight (was 1,190)", SOUND.record)
end

function G.Init()
	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_REGEN_DISABLED")
	events:RegisterEvent("PLAYER_REGEN_ENABLED")
	events:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_REGEN_DISABLED" then
			inCombat, started, leading, pending = true, GetTime(), nil, 0
		else
			inCombat = false
			-- The eyes go out with the fight even if nothing gets saved from it.
			C_Timer.After(1.5, function() if not inCombat then EyesOut() end end)
		end
	end)
	events:SetScript("OnUpdate", function(_, elapsed)
		if not inCombat then return end
		sincePoll = sincePoll + elapsed
		if sincePoll < 0.5 then return end
		sincePoll = 0
		local ok, err = pcall(Poll)
		if not ok and ns.Log then ns.Log("meter glory poll: %s", tostring(err)) end
	end)
end
