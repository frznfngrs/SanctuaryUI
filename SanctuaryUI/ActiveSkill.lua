SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.ActiveSkill = ns.ActiveSkill or {}

-- D3's "skill is active" dressing on a hotbar socket. While a skill's effect is up, the socket
-- burns with bottomBar_buttonFX_frameGlow_continuous, and a tab on the socket holds a bar that
-- drains until the effect ends. D3 ships a green and an amber fill for every slot; amber is
-- used for everything here.
--
-- The continuous glow in D3 is a particle emitter, not a static frame: it keeps spawning
-- copies of the square frame glow that live about 0.8 s, fade in over the first third and out
-- over the rest, each a little different in size and strength, so overlapping copies flicker
-- like fire (bottomBar_buttonFX_frameGlow_continuous.prt). That is redone here with a few
-- staggered sprites per socket, over a breathing gold rim on the socket edge.
--
-- A skill counts as active when one of these matches the button's spell:
--   a buff the player cast (by spell ID, then by name), a channel, or a totem.
-- Buffs with no duration (tracking, auras, aspects) are ignored unless turned on in the
-- options, and tracking (Find Minerals and the like) never counts. Buffs longer than
-- the configured limit are ignored, so 30-minute buffs don't keep a socket lit.

local LIFE = 0.8
local SPRITES = 4
local PEAK = 0.6
-- The gold rim on the socket edge (socket-hover.png, the art for hover and checked) burns
-- under the flicker so an active socket reads at a glance, breathing between these alphas.
local RIM_LOW, RIM_HIGH, RIM_PERIOD = 0.6, 0.95, 1.6
-- socket-hover.png maps the button to its inner 96 of 128 px.
local RIM_OUTSET = 16 / 96
local FLASH = 0.25

-- frameGlow's bright rim spans 0.453 of the texture; this puts it on the icon's edge.
local GLOW_OUTSET = (1 / 0.453 - 1) / 2

-- skill-timer.png (tools/build_hud_art.py), in sheet pixels of the 68 px wide socket.
local ATLAS_W, ATLAS_H = 128, 32
local TAB_W, TAB_H = 59, 11
local FILL_W, FILL_H = 55, 9
local FILL_X, FILL_Y = 2, 1
local SOCKET_W = 68
-- The tab sits inside the socket, along the icon's top or bottom edge (an option), so it
-- never reaches the rows or the plaques around the sockets. At the top it is flipped so its
-- rim faces down into the icon.
local TAB_INSET = 2

-- Tracking shows up as a buff with no duration but isn't a skill being "up".
local TRACKING = {
	[2580] = true, -- Find Minerals
	[2383] = true, -- Find Herbs
	[2481] = true, -- Find Treasure
	[43308] = true, -- Find Fish
	[1494] = true, -- Track Beasts
	[19878] = true, -- Track Demons
	[19879] = true, -- Track Dragonkin
	[19880] = true, -- Track Elementals
	[19882] = true, -- Track Giants
	[19885] = true, -- Track Hidden
	[19883] = true, -- Track Humanoids
	[5225] = true, -- Track Humanoids (druid)
	[19884] = true, -- Track Undead
	[5500] = true, -- Sense Demons
	[5502] = true, -- Sense Undead
}

local function IsTracking(id, name)
	if TRACKING[id] then return true end
	-- Other ranks and locales: anything the minimap tracking menu lists.
	if name and C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingInfo then
		for i = 1, C_Minimap.GetNumTrackingTypes() do
			local info = C_Minimap.GetTrackingInfo(i)
			local trackName = type(info) == "table" and info.name or info
			if trackName == name then return true end
		end
	end
	return false
end

local active = {}
local dirty = true
-- Buttons update many times a second in combat; a rescan is cheap but needn't run every frame.
local RESCAN_EVERY = 0.1

local function Opt()
	return ns.DB().buttons
end

local function Secret(value)
	return issecretvalue and issecretvalue(value)
end

local GetSpellName = (C_Spell and C_Spell.GetSpellName) or function(id)
	return (GetSpellInfo(id))
end

---------------------------------------------------------------------------
-- What is up right now, gathered once per rescan.

local auraBySpell, auraByName = {}, {}
-- When the player last cast each spell (by ID and by name).
local casts = {}
-- The last scan was refused (in combat this client hides the player's auras from addons
-- entirely). What was read before stays, minus what has run out, and casts refresh it.
local refused = false

local UA = C_UnitAuras or {}

local function Readable(value)
	return not Secret(value) and value ~= nil
end

-- Buff lengths learned while buffs are readable, by spell ID and name; saved across sessions.
local function Lengths()
	local global = ns.db and ns.db.global
	if not global then return {} end
	global.buffLengths = global.buffLengths or {}
	return global.buffLengths
end

local function Length(id, name)
	local lengths = Lengths()
	return lengths[id] or (name and lengths[name])
end

-- One aura as the resolver wants it: plain timing, or hidden with what we can still ask.
local function Entry(aura, id, name)
	local auraID = aura.auraInstanceID
	if not Readable(auraID) then auraID = nil end
	if Secret(aura.duration) or Secret(aura.expirationTime) then
		return { hidden = true, auraID = auraID }
	end
	local entry = { duration = aura.duration or 0, expires = aura.expirationTime or 0, auraID = auraID }
	local lengths = Lengths()
	if id then lengths[id] = entry.duration end
	if name then lengths[name] = entry.duration end
	return entry
end

local function Put(entry, id, name)
	if id then auraBySpell[id] = entry end
	if name then auraByName[name] = entry end
end

local function ScanAuras()
	local list, _, denied = ns.ReadAuras("player", "HELPFUL|PLAYER")
	refused = denied
	if denied then
		-- Keep the last real reading and the casts since; drop what has run out.
		local now = GetTime()
		for _, map in ipairs({ auraBySpell, auraByName }) do
			for key, entry in pairs(map) do
				if not entry.hidden and entry.duration > 0 and entry.expires <= now then
					map[key] = nil
				end
			end
		end
		return
	end
	wipe(auraBySpell)
	wipe(auraByName)
	for _, aura in ipairs(list) do
		local id, name = aura.spellId, aura.name
		if Secret(id) then id = nil end
		if Secret(name) then name = nil end
		if id or name then
			Put(Entry(aura, id, name), id, name)
		end
	end
end

-- A cast while buffs can't be read: if we know how long this spell's buff lasts, it is up
-- from now for that long. A buff cancelled or dispelled early stays lit until then; the
-- first readable scan after combat puts it right.
local function Predict(spellID, name, now, length)
	length = length or Length(spellID, name)
	if not length then return end
	Put({ duration = length, expires = now + length, predicted = true }, spellID, name)
	return true
end

-- Buffs only ever cast in combat (Bloodthirst, Sweeping Strikes, Death Wish) are never
-- readable, so their length is never learned. Two things we can still see stand in:
-- Blizzard's buff frame (untainted, it shows them) gains an icon right around the cast,
-- which says the cast put a buff on you, and the spell's own text says how long it lasts.
-- Target debuffs (Rend, Hamstring) add no icon there, so they don't light.
local BUFF_WINDOW = 0.6 -- seconds between a cast and a new buff icon, either way round
local DescribedLength = ns.DescribedLength
local BuffIcons = ns.BuffIcons

local iconCount, iconGained = 0, -math.huge
-- A cast that may have put a buff on you, waiting for its icon: { id, name, time, length }.
local pending

local function Confirm(cast, now)
	pending = nil
	if Predict(cast.id, cast.name, cast.time, cast.length) then
		dirty = true
		ns.Log("active: %s made a buff (new icon), predicted %ss from its text", tostring(cast.name), tostring(cast.length))
	end
end

-- Called often: notes when a buff icon appears, and settles a waiting cast.
local function WatchIcons(now)
	local count = BuffIcons()
	if count > iconCount then iconGained = now end
	iconCount = count
	if pending then
		if iconGained >= pending.time - BUFF_WINDOW then
			Confirm(pending, now)
		elseif now - pending.time > BUFF_WINDOW then
			pending = nil
		end
	end
end

-- A cast while buffs are hidden: refresh a buff we already show for it, or use the length we
-- learned, or wait for its icon and go by its text.
local function OnCast(spellID, name, now)
	local entry = auraBySpell[spellID] or (name and auraByName[name])
	if entry and not entry.hidden and entry.duration > 0 and entry.expires > now then
		return Predict(spellID, name, now, entry.duration)
	end
	if Predict(spellID, name, now) then return true end
	local length = DescribedLength(spellID)
	if length and length > 0 then
		pending = { id = spellID, name = name, time = now, length = length }
		WatchIcons(now)
	end
end

-- Timing for a buff whose fields are hidden (clients that list auras but hide their values).
-- Returns start, duration (0: no timer), or a duration object for the engine to run; false
-- when the buff shouldn't light the socket.
local function HiddenTiming(aura, id, name)
	local now = GetTime()
	local length = Length(id, name)
	if length then
		if length <= 0 then
			return Opt().activeEndless and 0 or false, 0
		end
		if length > (Opt().activeMax or 60) then return false end
		local cast = casts[id] or (name and casts[name])
		if cast and cast + length > now then
			return cast, length
		end
	end
	-- The client's duration object; none means the buff has no duration.
	if aura.auraID and UA.GetAuraDuration then
		local ok, object = pcall(UA.GetAuraDuration, "player", aura.auraID)
		if ok then
			if type(object) == "nil" then
				return Opt().activeEndless and 0 or false, 0
			end
			local got, left, total = pcall(function() return object:GetRemainingDuration(), object:GetTotalDuration() end)
			if got and Readable(left) and Readable(total) then
				if total > (Opt().activeMax or 60) then return false end
				return now + left - total, total
			end
			return 0, 0, object
		end
	end
	-- Nothing to time it by: glow alone.
	return 0, 0
end

local function Channel()
	if not UnitChannelInfo then return end
	local name, _, _, startMS, endMS, _, _, spellID = UnitChannelInfo("player")
	if Secret(name) or Secret(startMS) or Secret(endMS) or not name then return end
	return name, spellID, startMS / 1000, (endMS - startMS) / 1000
end

local function Totem(name, icon)
	if not GetTotemInfo then return end
	for slot = 1, (MAX_TOTEMS or 4) do
		local have, totemName, start, duration, totemIcon = GetTotemInfo(slot)
		-- Secret first: in combat these can all be secret, and even a truth test on one throws.
		-- Hidden, there's no timer to give the button, so it shows no totem time.
		if not Secret(have) and not Secret(duration) and not Secret(totemName) and not Secret(start)
			and have and duration and duration > 0 then
			-- Totem names carry a rank ("Searing Totem III"); the icon is the surer match.
			local iconMatch = icon and not Secret(totemIcon) and totemIcon == icon
			if iconMatch or (name and totemName and totemName:find(name, 1, true) == 1) then
				return start, duration
			end
		end
	end
end

-- Returns active, start, duration for one button. A duration of 0 means "on, no timer";
-- a fourth value is a duration object the engine runs the timer from (timing hidden), and a
-- fifth is true for channels and totems, which always glow whatever their length.
local function Resolve(button, channel)
	if not button.GetSpellId then return false end
	local ok, id = pcall(button.GetSpellId, button)
	if not ok or Secret(id) or not id then return false end
	local name = GetSpellName(id)
	if Secret(name) then name = nil end
	if channel and (channel[2] == id or channel[1] == name) then
		return true, channel[3], channel[4], nil, true
	end
	local icon = button.icon and button.icon:GetTexture()
	local tStart, tDuration = Totem(name, icon)
	if tStart then
		return true, tStart, tDuration, nil, true
	end
	local aura = auraBySpell[id] or (name and auraByName[name])
	if aura and not IsTracking(id, name) then
		if aura.hidden then
			local start, duration, timer = HiddenTiming(aura, id, name)
			if not start then return false end
			return true, start, duration, timer
		end
		if aura.duration <= 0 then
			if Opt().activeEndless then
				return true, 0, 0
			end
			return false
		end
		if aura.duration <= (Opt().activeMax or 60) then
			return true, aura.expires - aura.duration, aura.duration
		end
	end
	return false
end

---------------------------------------------------------------------------
-- Art on one socket, made the first time the socket lights up.

local function Build(button)
	if button.sanctuaryActive then return button.sanctuaryActive end
	local fx = {}
	local ring = button.sanctuaryRingFrame
	local level = (ring and ring:GetFrameLevel() or button:GetFrameLevel() + 6) - 1

	-- The glow sits under the ring frame, which carries the key and count text.
	local glow = CreateFrame("Frame", nil, button)
	glow:SetAllPoints()
	-- Below the tab, so the rim never draws over the timer bar.
	glow:SetFrameLevel(level - 1)
	glow:Hide()
	fx.glow = glow
	local rim = glow:CreateTexture(nil, "ARTWORK")
	if ns.Art.Apply(rim, "socketHover") then
		rim:SetBlendMode("ADD")
		rim:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
		rim:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
		fx.rim = rim
	else
		rim:Hide()
	end
	fx.sprites = {}
	for i = 1, SPRITES do
		local tex = glow:CreateTexture(nil, "OVERLAY")
		if not ns.Art.Apply(tex, "buttonGlow") then
			tex:SetColorTexture(1, 0.55, 0.15, 0.2)
		end
		tex:SetBlendMode("ADD")
		tex:SetAlpha(0)
		fx.sprites[i] = { tex = tex, offset = (i - 1) / SPRITES, cycle = -1, peak = PEAK, size = 1 }
	end

	local tab = CreateFrame("Frame", nil, button)
	tab:SetFrameLevel(level)
	tab:Hide()
	fx.tab = tab
	local back = tab:CreateTexture(nil, "ARTWORK")
	back:SetAllPoints()
	local fill = tab:CreateTexture(nil, "OVERLAY")
	if ns.Art.Apply(back, "skillTimer") then
		ns.Art.Apply(fill, "skillTimer")
		fx.art = true
	else
		back:SetColorTexture(0, 0, 0, 0.9)
	end
	fx.back, fx.fill = back, fill

	-- Hidden timings: the engine drains an invisible status bar from the aura's duration
	-- object, and a clip frame that ends where that bar's fill ends crops a full-length copy
	-- of the fill art. Same look as the texcoord crop, without reading the secret numbers.
	local timerBar = CreateFrame("StatusBar", nil, tab)
	if timerBar.SetTimerDuration and timerBar.SetClipsChildren then
		timerBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
		timerBar:SetStatusBarColor(0, 0, 0, 0)
		timerBar:SetMinMaxValues(0, 1)
		local clip = CreateFrame("Frame", nil, tab)
		clip:SetPoint("TOPLEFT", timerBar, "TOPLEFT")
		clip:SetPoint("BOTTOMRIGHT", timerBar:GetStatusBarTexture(), "BOTTOMRIGHT")
		clip:SetClipsChildren(true)
		local inner = CreateFrame("Frame", nil, clip)
		inner:SetAllPoints(timerBar)
		local clipFill = inner:CreateTexture(nil, "OVERLAY")
		clipFill:SetAllPoints()
		if fx.art then
			ns.Art.Apply(clipFill, "skillTimer")
			clipFill:SetTexCoord(0, FILL_W / ATLAS_W, 16 / ATLAS_H, (16 + FILL_H) / ATLAS_H)
		else
			clipFill:SetColorTexture(0.85, 0.75, 0.2, 1)
		end
		for _, frame in ipairs({ timerBar, clip, inner }) do
			frame:SetFrameLevel(level)
		end
		timerBar:Hide()
		clip:Hide()
		fx.timerBar, fx.clip = timerBar, clip
	end
	button.sanctuaryActive = fx
	return fx
end

-- Sizes follow the button, which the rows and the console scale freely.
local function Fit(button, fx)
	local w, h = button:GetSize()
	if not w or w <= 0 then return end
	local top = Opt().activeTimerPos ~= "bottom"
	if fx.w == w and fx.h == h and fx.top == top then return end
	fx.w, fx.h, fx.top = w, h, top
	local s = w / SOCKET_W
	fx.scale = s
	fx.ow, fx.oh = w * GLOW_OUTSET, h * GLOW_OUTSET
	if fx.rim then
		fx.rim:ClearAllPoints()
		fx.rim:SetPoint("TOPLEFT", button, "TOPLEFT", -w * RIM_OUTSET, h * RIM_OUTSET)
		fx.rim:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", w * RIM_OUTSET, -h * RIM_OUTSET)
	end
	fx.tab:SetSize(TAB_W * s, TAB_H * s)
	fx.tab:ClearAllPoints()
	if top then
		fx.tab:SetPoint("TOP", button, "TOP", 0, -TAB_INSET * s)
	else
		fx.tab:SetPoint("BOTTOM", button, "BOTTOM", 0, TAB_INSET * s)
	end
	if fx.art then
		local x = button.sanctuaryGoldSocket and 64 or 0
		local y0, y1 = 0, TAB_H / ATLAS_H
		if top then y0, y1 = y1, y0 end
		fx.back:SetTexCoord(x / ATLAS_W, (x + TAB_W) / ATLAS_W, y0, y1)
	end
	fx.fill:SetHeight(FILL_H * s)
	fx.fill:ClearAllPoints()
	fx.fill:SetPoint("TOPLEFT", fx.tab, "TOPLEFT", FILL_X * s, -FILL_Y * s)
	if fx.timerBar then
		fx.timerBar:SetSize(FILL_W * s, FILL_H * s)
		fx.timerBar:ClearAllPoints()
		fx.timerBar:SetPoint("TOPLEFT", fx.tab, "TOPLEFT", FILL_X * s, -FILL_Y * s)
	end
	for i = 1, SPRITES do
		fx.sprites[i].cycle = -1
	end
end

local function PlaceSprite(button, fx, sprite)
	local grow = sprite.size
	local tex = sprite.tex
	local ow = fx.ow + fx.w * (grow - 1) / 2
	local oh = fx.oh + fx.h * (grow - 1) / 2
	tex:ClearAllPoints()
	tex:SetPoint("TOPLEFT", button, "TOPLEFT", -ow, oh)
	tex:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", ow, -oh)
end

local function Animate(button, fx, now)
	Fit(button, fx)
	if fx.glow:IsShown() then
		local flash = 0
		local since = now - (fx.lit or now)
		if since < FLASH then
			flash = 1 - since / FLASH
		end
		if fx.rim then
			local breath = 0.5 + 0.5 * math.sin(now * 2 * math.pi / RIM_PERIOD)
			fx.rim:SetAlpha(math.min(1, RIM_LOW + (RIM_HIGH - RIM_LOW) * breath + flash * 0.3))
		end
		for i = 1, SPRITES do
			local sprite = fx.sprites[i]
			local t = now / LIFE + sprite.offset
			local cycle = math.floor(t)
			t = t - cycle
			if cycle ~= sprite.cycle then
				-- A new particle: its own strength and size, like the emitter's spread.
				sprite.cycle = cycle
				sprite.peak = PEAK * (0.7 + 0.3 * math.random())
				sprite.size = 0.97 + 0.08 * math.random()
				PlaceSprite(button, fx, sprite)
			end
			local a = t < 1 / 3 and t * 3 or (1 - t) * 1.5
			sprite.tex:SetAlpha(math.min(1, sprite.peak * a + flash * 0.5))
		end
	end
	if fx.tab:IsShown() and not fx.timer then
		local left = fx.duration > 0 and (fx.start + fx.duration - now) / fx.duration or 0
		if left <= 0 then
			-- Ran out between aura events; the next rescan settles it.
			fx.fill:Hide()
			dirty = true
		else
			left = math.min(1, left)
			fx.fill:Show()
			fx.fill:SetWidth(math.max(0.01, FILL_W * fx.scale * left))
			if fx.art then
				fx.fill:SetTexCoord(0, FILL_W * left / ATLAS_W, 16 / ATLAS_H, (16 + FILL_H) / ATLAS_H)
			end
		end
	end
end

-- The engine's timer, when the buff's timing is hidden. False if this client can't.
local function RunTimer(fx, timer)
	if not timer or not fx.timerBar then return false end
	if fx.timer == timer then return true end
	local directions = Enum and Enum.StatusBarTimerDirection
	local smoothing = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate
	if not pcall(fx.timerBar.SetTimerDuration, fx.timerBar, timer, smoothing, directions and directions.RemainingTime) then
		return false
	end
	fx.timer = timer
	return true
end

local function Light(button, start, duration, timer, always)
	local opt = Opt()
	local fx = Build(button)
	if not fx.glow:IsShown() and not fx.tab:IsShown() then
		fx.lit = GetTime()
	end
	fx.start, fx.duration = start, duration
	if not fx.art then
		fx.fill:SetColorTexture(0.85, 0.75, 0.2, 1)
	end
	local engine = RunTimer(fx, timer)
	if not engine then fx.timer = nil end
	if fx.timerBar then
		fx.timerBar:SetShown(engine)
		fx.clip:SetShown(engine)
	end
	if engine then fx.fill:Hide() end
	-- Long buffs keep just the timer tab; the glow is for short effects, and for anything with
	-- no timer to show (no duration, or the timer turned off), where it is the only sign.
	local timed = opt.activeTimer and (duration > 0 or engine)
	local long = not always and duration > (opt.activeGlowMax or 30)
	fx.glow:SetShown(opt.activeGlow and not (timed and long))
	fx.tab:SetShown(timed)
	active[button] = fx.glow:IsShown() or fx.tab:IsShown() or nil
end

local function Douse(button)
	local fx = button.sanctuaryActive
	if fx then
		fx.glow:Hide()
		fx.tab:Hide()
		fx.timer = nil
	end
	active[button] = nil
end

---------------------------------------------------------------------------

function ns.ActiveSkill.Rescan()
	dirty = false
	local opt = Opt()
	local enabled = opt.activeGlow or opt.activeTimer
	if enabled then
		ScanAuras()
	end
	local name, spellID, start, duration = Channel()
	local channel = name and { name, spellID, start, duration }
	ns.ActionBar.ForEachButton(function(button)
		local on, s, d, timer, always
		if enabled then
			on, s, d, timer, always = Resolve(button, channel)
		end
		if on then
			Light(button, s, d, timer, always)
		else
			Douse(button)
		end
	end)
end

-- /sanctuary active: what each button with a spell sees, to tell a hidden aura from no match.
function ns.ActiveSkill.Report()
	ScanAuras()
	local list, how = ns.ReadAuras("player", "HELPFUL|PLAYER")
	local learned = 0
	for _ in pairs(Lengths()) do learned = learned + 1 end
	ns.Print(("active report: combat %s, buffs %s (%d via %s), %d buff lengths learned"):format(
		tostring(InCombatLockdown()), refused and "hidden: using last reading and casts" or "readable",
		#list, how, learned))
	local name, spellID = Channel()
	local lines = 0
	ns.ActionBar.ForEachButton(function(button)
		if not button.GetSpellId or not button:IsVisible() then return end
		local ok, id = pcall(button.GetSpellId, button)
		if not ok or id == nil then return end
		if Secret(id) then
			ns.Print(button:GetName() .. ": spell ID hidden")
			return
		end
		local spell = GetSpellName(id) or "?"
		local aura = auraBySpell[id] or auraByName[spell]
		local what
		local length = Length(id, spell)
		if aura and aura.predicted then
			what = ("buff predicted from cast, %.1fs of %ss"):format(math.max(0, aura.expires - GetTime()), tostring(aura.duration))
		elseif aura and aura.hidden then
			local start, duration, timer = HiddenTiming(aura, id, spell)
			local how = not start and "filtered out" or timer and "engine timer"
				or duration > 0 and ("%.1fs left"):format(start + duration - GetTime()) or "no timer"
			what = ("buff up, timing hidden (%s)"):format(how)
		elseif aura then
			what = ("buff up, %.1fs of %.0fs"):format(math.max(0, aura.expires - GetTime()), aura.duration)
		elseif name and (spellID == id or name == spell) then
			what = "channelling"
		else
			local described = DescribedLength(id)
			what = "no buff" .. (length and (", lasts %ss"):format(tostring(length))
				or described and (", text says %ss"):format(tostring(described)) or "")
		end
		local fx = button.sanctuaryActive
		local lit = fx and (fx.glow:IsShown() or fx.tab:IsShown())
		local limit = Opt().activeMax or 60
		local why = ""
		if not lit and aura and not aura.hidden and aura.duration > limit then
			why = (" (longer than the %ds limit in Buttons > Longest buff to show)"):format(limit)
		end
		ns.Print(("%s (%d): %s, %s%s"):format(spell, id, what, lit and "lit" or "dark", why))
		lines = lines + 1
	end)
	if lines == 0 then ns.Print("no spells on the visible bars") end
end

-- Watch.lua knows a buff ended early that only a reading could show (a seal judged away or
-- replaced by another): drop what we predicted or kept from before combat, so its socket goes
-- dark now rather than when the old timer runs out. A current reading is left alone.
function ns.ActiveSkill.Forget(name)
	if not name then return end
	local dropped = false
	for key, entry in pairs(auraBySpell) do
		if (entry.predicted or refused) and GetSpellName(key) == name then
			auraBySpell[key] = nil
			dropped = true
		end
	end
	local entry = auraByName[name]
	if entry and (entry.predicted or refused) then
		auraByName[name] = nil
		dropped = true
	end
	if dropped then
		dirty = true
		ns.Log("active: forgot %s (ended early)", name)
	end
end

function ns.ActiveSkill.ApplySettings()
	dirty = true
end

function ns.ActiveSkill.Init()
	if not ns.ActionBar.ForEachButton then return end
	-- The gold pair under the console keeps its gold tab.
	local primary = ns.ActionBar.primary or {}
	for _, i in ipairs({ 6, 7 }) do
		if primary[i] then primary[i].sanctuaryGoldSocket = true end
	end

	local driver = CreateFrame("Frame", nil, ns.Cluster)
	local events = {
		"PLAYER_ENTERING_WORLD", "PLAYER_TOTEM_UPDATE", "SPELLS_CHANGED",
		"ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR",
		"UPDATE_SHAPESHIFT_FORM", "ACTIONBAR_UPDATE_STATE",
	}
	for _, event in ipairs(events) do
		pcall(driver.RegisterEvent, driver, event)
	end
	for _, event in ipairs({ "UNIT_AURA", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_CHANNEL_UPDATE" }) do
		pcall(driver.RegisterUnitEvent, driver, event, "player")
	end
	driver:SetScript("OnEvent", function(_, event, _, _, spellID)
		if event == "UNIT_SPELLCAST_SUCCEEDED" then
			if Readable(spellID) then
				local now = GetTime()
				local name = GetSpellName(spellID)
				if not Readable(name) then name = nil end
				casts[spellID] = now
				if name then casts[name] = now end
				local predicted = (refused or InCombatLockdown()) and OnCast(spellID, name, now)
				ns.Log("active: cast %s (%s)%s", tostring(name), tostring(spellID),
					predicted and (", predicted %ss"):format(tostring(Length(spellID, name))) or "")
			else
				ns.Log("active: cast with a %s spell ID", Secret(spellID) and "secret" or "missing")
			end
		end
		dirty = true
	end)
	-- Paging swaps a button's action without an event of its own.
	local LAB = LibStub("LibActionButton-1.0")
	LAB.RegisterCallback(ns.ActiveSkill, "OnButtonUpdate", function() dirty = true end)
	LAB.RegisterCallback(ns.ActiveSkill, "OnButtonContentsChanged", function() dirty = true end)

	local nextScan = 0
	driver:SetScript("OnUpdate", function()
		local now = GetTime()
		WatchIcons(now)
		if dirty and now >= nextScan then
			nextScan = now + RESCAN_EVERY
			ns.ActiveSkill.Rescan()
		end
		if next(active) then
			for button, _ in pairs(active) do
				Animate(button, button.sanctuaryActive, now)
			end
		end
	end)
end
