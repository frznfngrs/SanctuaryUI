SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.MeterAnalysis = ns.MeterAnalysis or {}

-- The damage meter's analysis window. Out of combat only: in combat the game keeps every number
-- secret from addons (Meter.lua), so the window closes when a fight starts.
--
--   Left: the fights (the client's own, then our saved ones, dated), and under them your damage
--   per second over the last saved fights.
--   Middle: everyone in the chosen fight, every tally side by side with shares of the group,
--   sortable by any column, under a line of group totals. Or the enemies the group hit.
--   Right: the chosen player's abilities for one tally (with overkill, avoidable hits and
--   killing blows marked), their deaths, and for your own damage a comparison with your best or
--   last earlier attempt at the same fight.
--
-- The client's tallies (C_DamageMeter) cover its last 30 fights in full; older ones come from
-- MeterHistory.lua's saved records (totals for everyone, abilities for your damage only).
-- No hit counts, crit rates, timelines or per-target splits: the game gives addons none.
-- Sizes are in the meter mockups' pixels, drawn on a half-scale canvas like Meter.lua.

local A = ns.MeterAnalysis
local L -- ns.Meter.Lib, set when the window is first built

-- The window's shape is the player's: its size (drag the corner) and the widths of the fights
-- and table panes (drag the lines between them) are saved in the meter's "analysis" setting, and
-- Layout() works everything else out from those four numbers.
local W, H = 2200, 1080
local HALF = 0.5
local BASE_SCALE = 1.25 -- what the Window scale option calls 100%: the mockup size read too small in game
local TABLE_W = 1010 -- the width the table's columns are written for; they spread in proportion to the pane
local LIMIT = { minW = 1500, minH = 700, maxW = 3800, maxH = 2100, left = 220, mid = 700, right = 420 }
local LEFT = { x = 24, w = 360, top = 130, pitch = 42, rows = 16 }
local MID = { x = 410, w = 1010, top = 152, pitch = 44, rows = 20 }
local RIGHT = { x = 1446, w = 730, top = 164, pitch = 46, rows = 19 }
local CHART = { top = 850, h = 170, bars = 30 }
local LINE = { 0.29, 0.24, 0.16 }

-- The middle table's columns, left to right after the name. u: its share of the width (the
-- name takes a fifth of the pane, these split the rest), so every column has its own lane
-- with a gap before it at any pane width. share: a percentage of the group's total of
-- another column. Layout fills in right (the lane's right edge) and w (the text's room).
local COLUMNS = {
	{ key = "DamageDone", label = "Damage", u = 1.15, tip = { "Damage", "All the damage this player dealt in the fight, pets and guardians included." } },
	{ key = "damageShare", label = "Dmg %", u = 0.95, share = "DamageDone", tip = { "Damage share", "This player's part of the whole group's damage in the fight." } },
	{ key = "dps", label = "DPS", u = 0.95, tip = { "Damage per second", "This player's damage per second over the fight, as the game works it out." } },
	{ key = "HealingDone", label = "Healing", u = 1.15, tip = { "Healing", "Healing this player did, as the game counts it (its tally is healing and absorbs together)." } },
	{ key = "healingShare", label = "Heal %", u = 0.95, share = "HealingDone", tip = { "Healing share", "This player's part of the whole group's healing in the fight." } },
	{ key = "Absorbs", label = "Absorb", u = 1.0, tip = { "Absorbs", "Damage soaked up by this player's shields, such as Power Word: Shield." } },
	{ key = "DamageTaken", label = "Taken", u = 1.05, tip = { "Damage taken", "All the damage this player took." } },
	{ key = "AvoidableDamageTaken", label = "Avoid", u = 1.0, tip = { "Avoidable damage", "Damage taken from attacks the game marks as avoidable: things to step out of or interrupt. Lower is better. Empty where the game marks nothing." } },
	{ key = "Interrupts", label = "Int", u = 0.6, tip = { "Interrupts", "How many enemy casts this player interrupted." } },
	{ key = "Dispels", label = "Disp", u = 0.6, tip = { "Dispels", "How many effects this player dispelled or cleansed." } },
	{ key = "Deaths", label = "Died", u = 0.7, tip = { "Deaths", "How many times this player died in the fight. The Deaths tab on the right has the times and recaps." } },
}
local NAME_SHARE, GUTTER = 0.2, 16
local TABS = {
	{ key = "DamageDone", label = "Damage", tip = { "Damage", "This player's abilities by damage dealt: total, share of their own damage, and per second. Overkill is marked where a hit did more than the enemy had left." } },
	{ key = "HealingDone", label = "Healing", tip = { "Healing", "This player's abilities by healing done, absorbs included." } },
	{ key = "DamageTaken", label = "Taken", tip = { "Damage taken", "What hit this player, largest first, with who it came from. Avoidable hits and killing blows are marked." } },
	{ key = "AvoidableDamageTaken", label = "Avoid", tip = { "Avoidable damage", "Only the hits the game marks as avoidable, largest first: what to move out of next time." } },
	{ key = "Absorbs", label = "Absorbs", tip = { "Absorbs", "This player's shields by damage soaked up." } },
	{ key = "Interrupts", label = "Int", tip = { "Interrupts", "This player's interrupts, as the game lists them." } },
	{ key = "Dispels", label = "Disp", tip = { "Dispels", "This player's dispels and cleanses, as the game lists them." } },
	{ key = "Deaths", label = "Deaths", tip = { "Deaths", "Each death with its time into the fight. Click one for the game's recap of the last hits." } },
}
-- What a saved player record calls each tally (MeterHistory.lua).
local SAVED_KEYS = { DamageDone = "d", HealingDone = "h", DamageTaken = "t", Interrupts = "i", Dispels = "x",
	AvoidableDamageTaken = "a", Absorbs = "b", Deaths = "k", dps = "dps" }

local frame, canvas
local Shape, Layout -- below
local layingOut = false
local fightRows, listRows, detailRows, bars = {}, {}, {}, {}
local seg = "current"
local mode = "players" -- players | enemies
local selected -- the chosen row's key
local tab = "DamageDone"
local sortKey = "DamageDone"
local compare = "off" -- off | best | last
local scroll = { fights = 0, list = 0, detail = 0 }

local function Secret(value) return ns.Secret(value) end

---------------------------------------------------------------------------
-- Data (plain numbers only; nil when anything is still secret)

local function Key(s)
	return s.sourceGUID or (s.sourceCreatureID and ("c" .. s.sourceCreatureID)) or s.name
end

local function Readable(s)
	return not (Secret(s.totalAmount) or Secret(s.name) or Secret(s.sourceGUID) or Secret(s.sourceCreatureID))
end

-- A saved fight (MeterHistory.lua) is its own record, a table; the client's fights are
-- "current", "overall" or a session ID.
local function Saved(fight)
	return type(fight) == "table"
end

-- Everyone in a fight, one record each with a total per tally.
local function Players(fight)
	local byKey, list = {}, {}
	if Saved(fight) then
		for i, p in ipairs(fight.p) do
			local row = { key = p.n, name = L.ShortName(p.n, true), class = p.c, mine = p.me }
			for kind, short in pairs(SAVED_KEYS) do row[kind] = p[short] end
			list[i] = row
		end
		return list
	end
	for _, kind in ipairs({ "DamageDone", "HealingDone", "Absorbs", "DamageTaken", "AvoidableDamageTaken", "Interrupts", "Dispels", "Deaths" }) do
		local session = L.Fetch(fight, Enum.DamageMeterType[kind])
		for _, s in ipairs(session and session.combatSources or {}) do
			if not Readable(s) then return nil end
			local player = L.IsPlayerClass(s.classFilename)
			local key = Key(s)
			local p = key and byKey[key]
			-- Deaths lists everything that died; only those already in the fight, or players, count.
			if key and not p and (kind ~= "Deaths" or player) then
				p = { key = key, name = L.ShortName(s.name, player), class = s.classFilename, guid = s.sourceGUID,
					creatureID = s.sourceCreatureID, mine = not Secret(s.isLocalPlayer) and s.isLocalPlayer or false }
				byKey[key] = p
				list[#list + 1] = p
			end
			if p then
				if kind == "Deaths" then
					p.Deaths = (p.Deaths or 0) + 1
					p.deathList = p.deathList or {}
					p.deathList[#p.deathList + 1] = {
						at = not Secret(s.deathTimeSeconds) and s.deathTimeSeconds or nil,
						recap = not Secret(s.deathRecapID) and s.deathRecapID ~= 0 and s.deathRecapID or nil,
					}
				else
					p[kind] = s.totalAmount
					if kind == "DamageDone" and not Secret(s.amountPerSecond) then p.dps = s.amountPerSecond end
				end
			end
		end
	end
	return list
end

-- What the players hit.
local function Enemies(fight)
	local list = {}
	if Saved(fight) then return list end
	local session = L.Fetch(fight, Enum.DamageMeterType.EnemyDamageTaken)
	for _, s in ipairs(session and session.combatSources or {}) do
		if not Readable(s) then return nil end
		list[#list + 1] = { key = Key(s), name = L.ShortName(s.name, false), guid = s.sourceGUID, creatureID = s.sourceCreatureID,
			enemy = true, DamageDone = s.totalAmount }
	end
	return list
end

-- One source's abilities for a tally, largest first: id, name, icon, total, per second.
local function Abilities(fight, who, kind)
	if Saved(fight) then
		-- Saved fights keep one thing per ability: your own damage.
		if not (who.mine and kind == "DamageDone" and fight.mine) then return nil end
		local list = {}
		for i, a in ipairs(fight.mine) do
			list[i] = { id = a.id, name = L.GetSpellName(a.id) or ("Spell " .. tostring(a.id)), icon = L.GetSpellTexture(a.id) or 134400, total = a.v }
		end
		return list, who.DamageDone
	end
	local data = L.FetchSource(fight, Enum.DamageMeterType[kind], who.guid, who.creatureID)
	if not data or Secret(data.totalAmount) then return nil end
	local list = {}
	for _, spell in ipairs(data.combatSpells) do
		if Secret(spell.totalAmount) or Secret(spell.spellID) then return nil end
		local name = L.GetSpellName(spell.spellID) or ("Spell " .. tostring(spell.spellID))
		local pet = spell.creatureName
		if pet ~= nil and not Secret(pet) and pet ~= "" then name = name .. " (" .. pet .. ")" end
		-- Tallies of what was done to someone name the other side of the hit.
		local d = spell.combatSpellDetails
		local other
		if type(d) == "table" then other = d.unitName end
		if kind ~= "DamageDone" and kind ~= "HealingDone" and other ~= nil and not Secret(other) and other ~= "" then
			name = name .. "  |cffa8a296" .. L.ShortName(other, L.IsPlayerClass(d.unitClassFilename)) .. "|r"
		end
		if not Secret(spell.isDeadly) and spell.isDeadly then name = name .. "  |cffff5040killing blow|r" end
		if not Secret(spell.isAvoidable) and spell.isAvoidable and kind ~= "AvoidableDamageTaken" then name = name .. "  |cffffb040avoidable|r" end
		local over = spell.overkillAmount
		if over ~= nil and not Secret(over) and over > 0 then name = name .. "  |cff9a9488overkill " .. L.Short(over) .. "|r" end
		list[#list + 1] = { id = spell.spellID, name = name, icon = L.GetSpellTexture(spell.spellID) or 134400, total = spell.totalAmount,
			rate = not Secret(spell.amountPerSecond) and spell.amountPerSecond or nil }
	end
	table.sort(list, function(a, b) return a.total > b.total end)
	return list, data.totalAmount
end

-- The Deaths tab: each death with its time, then whatever the client lists against them.
local function DeathRows(fight, who)
	local list = {}
	if Saved(fight) then
		if (who.Deaths or 0) > 0 then
			list[1] = { name = ("Died %d time%s. Saved fights keep the count only."):format(who.Deaths, who.Deaths == 1 and "" or "s"), icon = 237274, plain = true }
		end
		return list
	end
	for i, death in ipairs(who.deathList or {}) do
		list[#list + 1] = { name = (death.at and ("Died at " .. L.Clock(death.at)) or ("Death " .. i)) .. (death.recap and "  |cffe8c77aclick for the recap|r" or ""),
			icon = 237274, recap = death.recap, plain = true }
	end
	if #list > 0 then
		for _, a in ipairs(Abilities(fight, who, "Deaths") or {}) do list[#list + 1] = a end
	end
	return list
end

local function Fights()
	local list = { { key = "current", name = "Current fight" }, { key = "overall", name = "Overall" } }
	local sessions = L.Sessions()
	for i = #sessions, 1, -1 do
		local s = sessions[i]
		if not Secret(s.sessionID) then
			list[#list + 1] = { key = s.sessionID, name = (not Secret(s.name) and s.name ~= "" and s.name) or ("Fight " .. s.sessionID),
				length = L.Clock(s.durationSeconds) }
		end
	end
	list[1].length, list[2].length = L.Clock(L.Duration("current")), L.Clock(L.Duration("overall"))
	-- Then the fights only we still have, dated.
	for _, f in ipairs(ns.MeterHistory and ns.MeterHistory.Older() or {}) do
		local what = f.boss or f.name or f.zone or "Fight"
		list[#list + 1] = { key = f, name = (date and date("%b %d %H:%M  ", f.t) or "") .. what, length = L.Clock(f.dur) }
	end
	return list
end

local function FightLength(fight)
	if Saved(fight) then return fight.dur end
	local seconds = L.Duration(fight)
	if seconds ~= nil and not Secret(seconds) then return seconds end
end

---------------------------------------------------------------------------
-- Widgets

local function Mark(row)
	row.pick = row:CreateTexture(nil, "BACKGROUND")
	row.pick:SetAllPoints()
	row.pick:SetColorTexture(L.GOLD[1], L.GOLD[2], L.GOLD[3], 0.16)
	row.pick:Hide()
	local hover = row:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints()
	hover:SetColorTexture(1, 1, 1, 0.06)
end

local function Label(parent, size, color, justify)
	return L.Text(parent, L.BodyFont(), size or 21, color or L.CREAM, justify)
end

-- What a heading, tab or switch means, on hover.
local function Tip(button, title, text, more)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(title)
		GameTooltip:AddLine(text, 1, 1, 1, true)
		if more then GameTooltip:AddLine(more, 0.7, 0.7, 0.7, true) end
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
end

-- A word you can click: gold while it is the one chosen.
local function TextButton(parent, word, onClick, size, justify)
	size = size or 22
	local b = CreateFrame("Button", nil, parent)
	b.text = Label(b, size, L.CREAM, justify)
	b.text:SetPoint(justify == "RIGHT" and "RIGHT" or "LEFT")
	b.text:SetText(word)
	-- As wide as its word in whatever font the meter uses.
	local wide = b.text.GetStringWidth and b.text:GetStringWidth()
	b:SetSize(math.max(30, (wide and wide > 0 and wide or #word * size * 0.58) + 12), size + 10)
	b:SetScript("OnClick", onClick)
	b.SetChosen = function(self, on)
		local c = on and L.GOLD or L.CREAM
		self.text:SetTextColor(c[1], c[2], c[3])
		self.text:SetAlpha(on and 1 or 0.7)
	end
	return b
end

local function Region(col, key)
	local r = CreateFrame("Frame", nil, canvas)
	r:SetPoint("TOPLEFT", canvas, "TOPLEFT", col.x, -col.top)
	r:SetSize(col.w, col.rows * col.pitch)
	r:EnableMouseWheel(true)
	r:SetScript("OnMouseWheel", function(_, delta)
		scroll[key] = math.max(0, scroll[key] - delta * 3)
		A.Refresh()
	end)
	return r
end

-- Rows span their pane, whatever its width.
local function Row(region, col, i)
	local row = CreateFrame("Button", nil, region)
	row:SetPoint("TOPLEFT", region, "TOPLEFT", 0, -(i - 1) * col.pitch)
	row:SetPoint("RIGHT", region, "RIGHT", 0, 0)
	row:SetHeight(col.pitch - 2)
	Mark(row)
	return row
end

local function Pick(fight)
	seg, scroll.list, scroll.detail = fight, 0, 0
	A.Refresh()
end

local function FightRow(i)
	local row = Row(frame.left, LEFT, i)
	row.name = Label(row, 21)
	row.name:SetPoint("LEFT", 10, 0)
	row.length = Label(row, 20, L.CREAM, "RIGHT")
	row.length:SetPoint("RIGHT", -10, 0)
	row.length:SetAlpha(0.75)
	row.name:SetPoint("RIGHT", row.length, "LEFT", -8, 0)
	row:SetScript("OnClick", function(self) Pick(self.key) end)
	fightRows[i] = row
	return row
end

-- Give each column its lane for the pane's width.
local function Lanes()
	local name = math.max(150, MID.w * NAME_SHARE)
	local units = 0
	for _, col in ipairs(COLUMNS) do units = units + col.u end
	local unit = (MID.w - name - 8) / units
	local x = name
	for _, col in ipairs(COLUMNS) do
		x = x + col.u * unit
		col.right, col.w = x, math.max(20, col.u * unit - GUTTER)
	end
	MID.name = name
end

local function SpreadRow(row)
	if not COLUMNS[1].right then Lanes() end
	row.name:ClearAllPoints()
	row.name:SetPoint("LEFT", 12, 0)
	row.name:SetPoint("RIGHT", row, "LEFT", MID.name, 0)
	for _, col in ipairs(COLUMNS) do
		local cell = row.cells[col.key]
		cell:ClearAllPoints()
		cell:SetPoint("RIGHT", row, "LEFT", col.right, 0)
		cell:SetWidth(col.w)
	end
end

local function ListRow(i)
	local row = Row(frame.mid, MID, i)
	row.bar = CreateFrame("StatusBar", nil, row)
	row.bar:SetPoint("TOPLEFT", 0, -4)
	row.bar:SetPoint("BOTTOMRIGHT", 0, 4)
	row.bar:SetStatusBarTexture(ns.Art.Path("unitFillWhite") or "Interface\\Buttons\\WHITE8X8")
	row.bar:SetMinMaxValues(0, 1)
	row.bar:SetFrameLevel(row:GetFrameLevel())
	row.bar:EnableMouse(false)
	local over = CreateFrame("Frame", nil, row)
	over:SetAllPoints()
	over:SetFrameLevel(row:GetFrameLevel() + 2)
	row.name = Label(over, 21)
	row.cells = {}
	for _, col in ipairs(COLUMNS) do
		local cell = Label(over, 19, L.CREAM, "RIGHT")
		if col.share then cell:SetAlpha(0.7) end
		row.cells[col.key] = cell
	end
	SpreadRow(row)
	row:SetScript("OnClick", function(self)
		selected, scroll.detail = self.key, 0
		A.Refresh()
	end)
	listRows[i] = row
	return row
end

local function DetailRow(i)
	local row = Row(frame.right, RIGHT, i)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(38, 38)
	row.icon:SetPoint("LEFT", 2, 0)
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	row.bar = CreateFrame("StatusBar", nil, row)
	row.bar:SetPoint("TOPLEFT", 46, -4)
	row.bar:SetPoint("BOTTOMRIGHT", 0, 4)
	row.bar:SetStatusBarTexture(ns.Art.Path("unitFillWhite") or "Interface\\Buttons\\WHITE8X8")
	row.bar:SetMinMaxValues(0, 1)
	row.bar:EnableMouse(false)
	local over = CreateFrame("Frame", nil, row.bar)
	over:SetAllPoints()
	over:SetFrameLevel(row.bar:GetFrameLevel() + 1)
	row.rate = Label(over, 20, L.CREAM, "RIGHT")
	row.rate:SetPoint("RIGHT", -8, 0)
	row.rate:SetWidth(104)
	row.pct = Label(over, 20, L.CREAM, "RIGHT")
	row.pct:SetPoint("RIGHT", row.rate, "LEFT", -6, 0)
	row.pct:SetWidth(66)
	row.total = Label(over, 20, L.CREAM, "RIGHT")
	row.total:SetPoint("RIGHT", row.pct, "LEFT", -6, 0)
	row.total:SetWidth(100)
	row.name = Label(over, 21)
	row.name:SetPoint("LEFT", 8, 0)
	row.name:SetPoint("RIGHT", row.total, "LEFT", -8, 0)
	row:SetScript("OnClick", function(self)
		if self.recap and OpenDeathRecapUI then pcall(OpenDeathRecapUI, self.recap) end
	end)
	detailRows[i] = row
	return row
end

---------------------------------------------------------------------------
-- Drawing

local function Number(value)
	if value == nil or value == 0 then return "" end
	return L.Short(value)
end

local function DrawFights(fights)
	scroll.fights = math.max(0, math.min(scroll.fights, #fights - LEFT.rows))
	local title = "Current fight"
	for i = 1, math.max(LEFT.rows, #fightRows) do
		local row = fightRows[i] or FightRow(i)
		local f = i <= LEFT.rows and fights[i + scroll.fights]
		if f then
			row.key = f.key
			row.name:SetText(f.name)
			row.length:SetText(f.length or "")
			row.pick:SetShown(f.key == seg)
			row:Show()
		else
			row:Hide()
		end
	end
	for _, f in ipairs(fights) do
		if f.key == seg then title = f.name end
	end
	return title
end

local function Sum(list, key)
	local sum = 0
	for _, p in ipairs(list) do sum = sum + (p[key] or 0) end
	return sum
end

local function DrawList(list)
	-- Shares of the group's totals, then the chosen column's order.
	for _, col in ipairs(COLUMNS) do
		if col.share then
			local sum = Sum(list, col.share)
			for _, p in ipairs(list) do
				p[col.key] = sum > 0 and (p[col.share] or 0) > 0 and (p[col.share] / sum * 100) or nil
			end
		end
	end
	local key = mode == "enemies" and "DamageDone" or sortKey
	table.sort(list, function(a, b)
		local x, y = a[key] or 0, b[key] or 0
		if x ~= y then return x > y end
		return (a.DamageDone or 0) > (b.DamageDone or 0)
	end)
	scroll.list = math.max(0, math.min(scroll.list, #list - MID.rows))
	local top = 0
	for _, p in ipairs(list) do top = math.max(top, p[key] or 0) end
	for i = 1, math.max(MID.rows, #listRows) do
		local row = listRows[i] or ListRow(i)
		local p = i <= MID.rows and list[i + scroll.list]
		if p then
			row.key = p.key
			row.name:SetText(p.name)
			local c = p.mine and L.GOLD or L.CREAM
			row.name:SetTextColor(c[1], c[2], c[3])
			local r, g, b = L.ClassColor(p.class, p.enemy)
			row.bar:SetStatusBarColor(r * 0.7, g * 0.7, b * 0.7, 0.55)
			row.bar:SetValue(top > 0 and (p[key] or 0) / top or 0)
			for _, col in ipairs(COLUMNS) do
				local value = p[col.key]
				if col.share then
					row.cells[col.key]:SetText(value and ("%d%%"):format(value + 0.5) or "")
				else
					row.cells[col.key]:SetText(Number(value))
				end
			end
			row.pick:SetShown(p.key == selected)
			row:Show()
		else
			row:Hide()
		end
	end

	-- The line of totals over the table.
	local length = FightLength(seg)
	local parts = {}
	if mode == "enemies" then
		parts[#parts + 1] = ("%d enemies"):format(#list)
		parts[#parts + 1] = L.Short(Sum(list, "DamageDone")) .. " taken"
	elseif #list > 0 then
		parts[#parts + 1] = #list == 1 and "1 player" or ("%d players"):format(#list)
		local damage, healing = Sum(list, "DamageDone"), Sum(list, "HealingDone")
		parts[#parts + 1] = L.Short(damage) .. " damage"
		if length and length > 0 and damage > 0 then parts[#parts + 1] = L.Short(damage / length) .. " dps" end
		if healing > 0 then parts[#parts + 1] = L.Short(healing) .. " healing" end
		local deaths = Sum(list, "Deaths")
		if deaths > 0 then parts[#parts + 1] = deaths == 1 and "1 death" or (deaths .. " deaths") end
	end
	if length then parts[#parts + 1] = L.Clock(length) end
	frame.summary:SetText(table.concat(parts, "   |cff8a8478-|r   "))
end

-- Your damage against an earlier attempt at the same fight: the record to compare with, and
-- how long each fight ran. Nil when there is nothing to compare.
local function Comparison(who)
	frame.compare:Hide()
	if not (who and who.mine and tab == "DamageDone" and mode == "players" and ns.MeterHistory) then return nil end
	local record = ns.MeterHistory.RecordFor(seg)
	if not record then return nil end
	local best, last = ns.MeterHistory.Earlier(record)
	if not best and not last then return nil end
	frame.compare:Show()
	frame.compare.text:SetText("Compare: " .. compare)
	frame.compare:SetChosen(compare ~= "off")
	local other = compare == "best" and best or compare == "last" and last or nil
	if not other or not other.mine or not other.dur or other.dur <= 0 or not record.dur or record.dur <= 0 then return nil end
	local was = {}
	for _, a in ipairs(other.mine) do was[a.id] = a.v / other.dur end
	-- Saved fights keep only the top abilities: one missing from a full list may have been used.
	return { was = was, now = record.dur, other = other, record = record, full = #other.mine >= (ns.MeterHistory.MY_ABILITIES or 12) }
end

local function DrawDetail(who)
	local kind = mode == "enemies" and "EnemyDamageTaken" or tab
	local list, sum
	if who then
		if kind == "Deaths" then
			list = DeathRows(seg, who)
		else
			list, sum = Abilities(seg, who, kind)
		end
	end
	list = list or {}
	local versus = Comparison(who)
	scroll.detail = math.max(0, math.min(scroll.detail, #list - RIGHT.rows))
	local top = 0
	for _, a in ipairs(list) do top = math.max(top, a.total or 0) end
	local r, g, b = 0.62, 0.56, 0.46
	if who then r, g, b = L.ClassColor(who.class, who.enemy) end
	for i = 1, math.max(RIGHT.rows, #detailRows) do
		local row = detailRows[i] or DetailRow(i)
		local a = i <= RIGHT.rows and list[i + scroll.detail]
		if a then
			row.icon:SetTexture(a.icon)
			row.name:SetText(a.name)
			row.recap = a.recap
			row:EnableMouse(a.recap ~= nil)
			if a.plain then
				row.total:SetText("")
				row.pct:SetText("")
				row.rate:SetText("")
				row.bar:SetValue(0)
			else
				row.total:SetText(L.Short(a.total))
				if sum and sum > 0 then
					row.pct:SetFormattedText("%d%%", a.total / sum * 100 + 0.5)
				else
					row.pct:SetText("")
				end
				if versus then
					-- Per second now against per second then, ability by ability.
					local was = versus.was[a.id]
					if was then
						local delta = a.total / versus.now - was
						row.rate:SetText((delta >= 0 and "|cff60d060+" or "|cffff6050-") .. L.Short(math.abs(delta)) .. "/s|r")
					elseif versus.full then
						row.rate:SetText("")
					else
						row.rate:SetText("|cff60d060new|r")
					end
				else
					row.rate:SetText(a.rate and (L.Short(a.rate) .. "/s") or "")
				end
				row.bar:SetStatusBarColor(r * 0.75, g * 0.75, b * 0.75, 0.8)
				row.bar:SetValue(top > 0 and a.total / top or 0)
			end
			row:Show()
		else
			row:Hide()
		end
	end
	frame.who:SetText(who and who.name or "")
	frame.who:SetTextColor(r, g, b)
	frame.none:SetShown(who ~= nil and #list == 0)
	frame.none:SetText((Saved(seg) and kind ~= "Deaths") and "Saved fights keep abilities for your own damage only." or "Nothing recorded.")
	for _, t in ipairs(frame.tabs) do
		t:SetShown(mode == "players")
		t:SetChosen(t.key == tab)
	end
	frame.enemyNote:SetShown(mode == "enemies" and who ~= nil)

	-- Bottom right: the comparison in words, or your standing best for this kind of fight.
	local line = ""
	if versus then
		local history = ns.MeterHistory
		line = ("Against your %s try%s: %s dps then, %s now"):format(compare, date and date(", %b %d", versus.other.t) or "",
			L.Short(history.MyDps(versus.other)), L.Short(history.MyDps(versus.record)))
	elseif ns.MeterHistory then
		local record = ns.MeterHistory.RecordFor(seg)
		local dps, label
		if record then dps, label = ns.MeterHistory.BestFor(record) end
		if dps then line = ("Your best in %s: %s damage per second"):format(label, L.Short(dps)) end
	end
	frame.best:SetText(line)
end

-- Your damage per second over the last saved fights: gold for group fights, iron for solo.
local function DrawChart()
	local history = ns.MeterHistory
	local trend = history and history.Trend(CHART.bars) or {}
	local top = 0
	for _, t in ipairs(trend) do top = math.max(top, t.dps) end
	local shown = history and history.RecordFor(seg)
	local slot = LEFT.w / CHART.bars
	for i = 1, math.max(#bars, #trend) do
		local bar = bars[i]
		local t = trend[i]
		if not t then
			bar:Hide()
		else
			if not bar then
				bar = CreateFrame("Button", nil, frame.chart)
				bar.fill = bar:CreateTexture(nil, "ARTWORK")
				bar.fill:SetPoint("BOTTOMLEFT")
				bar.fill:SetPoint("BOTTOMRIGHT")
				bar:SetScript("OnEnter", function(self)
					local f = self.fight
					GameTooltip:SetOwner(self, "ANCHOR_TOP")
					GameTooltip:SetText(f.boss or f.name or f.zone or "Fight")
					GameTooltip:AddLine(("%s damage per second, %s%s"):format(L.Short(self.dps), L.Clock(f.dur), date and date(", %b %d %H:%M", f.t) or ""), 1, 1, 1)
					GameTooltip:AddLine(f.size > 1 and (f.size .. " players") or "Solo", 0.7, 0.7, 0.7)
					GameTooltip:Show()
				end)
				bar:SetScript("OnLeave", GameTooltip_Hide)
				bar:SetScript("OnClick", function(self) Pick(ns.MeterHistory.SegFor(self.fight)) end)
				bars[i] = bar
			end
			bar.fight, bar.dps = t.fight, t.dps
			bar:ClearAllPoints()
			bar:SetPoint("BOTTOMLEFT", frame.chart, "BOTTOMLEFT", (i - 1) * slot, 0)
			bar:SetSize(slot - 2, CHART.h)
			bar.fill:SetHeight(math.max(2, top > 0 and (t.dps / top * CHART.h) or 2))
			local lit = t.fight == shown
			if t.group then
				bar.fill:SetColorTexture(L.GOLD[1], L.GOLD[2], L.GOLD[3], lit and 1 or 0.6)
			else
				bar.fill:SetColorTexture(0.6, 0.54, 0.46, lit and 1 or 0.55)
			end
			bar:Show()
		end
	end
	frame.chartTitle:SetText(#trend > 0 and ("Your DPS, last %d saved fights (top %s)"):format(#trend, L.Short(top)) or "Your DPS over saved fights appears here.")
end

function A.Refresh()
	if not frame or not frame:IsShown() then return end
	if InCombatLockdown() then
		frame:Hide()
		return
	end
	local title = DrawFights(Fights())
	frame.sub:SetText(title)
	frame.players:SetChosen(mode == "players")
	frame.enemies:SetChosen(mode == "enemies")
	for _, h in ipairs(frame.heads) do
		h:SetShown(mode == "players" or h.key == "DamageDone")
		h:SetChosen(mode == "players" and h.key == sortKey)
	end
	frame.heads[1].text:SetText(mode == "players" and "Damage" or "Taken")

	local list
	if mode == "enemies" then list = Enemies(seg) else list = Players(seg) end
	frame.wait:SetShown(list == nil)
	if list == nil then
		-- Just out of combat: the numbers open up within a second.
		list = {}
		C_Timer.After(0.5, A.Refresh)
	end
	frame.empty:SetShown(#list == 0 and not frame.wait:IsShown())

	-- Keep the chosen row if it is in this fight; otherwise you, otherwise the top row.
	local who, mine
	for _, p in ipairs(list) do
		if p.key == selected then who = p end
		if p.mine then mine = p end
	end
	who = who or mine
	if not who then
		table.sort(list, function(a, b) return (a.DamageDone or 0) > (b.DamageDone or 0) end)
		who = list[1]
	end
	selected = who and who.key or nil
	DrawList(list)
	DrawDetail(who)
	DrawChart()
end

---------------------------------------------------------------------------
-- Layout: everything placed from the window's size and the two pane widths

Shape = function()
	local m = ns.DB().meter
	if type(m.analysis) ~= "table" then m.analysis = {} end
	return m.analysis
end

local function Clamp(value, low, high)
	return math.max(low, math.min(math.max(low, high), tonumber(value) or low))
end

local function Place(widget, point, x, y, relPoint)
	widget:ClearAllPoints()
	widget:SetPoint(point, canvas, relPoint or "TOPLEFT", x, y)
end

-- The dark body, tiled from the bag window's art to exactly the window's size: whole tiles,
-- every other one mirrored so the seams don't show, the last row and column cropped.
local function LayBody()
	local bag = ns.Art.Path("bagFrame")
	local TW, TH = 560, 270
	local cols, rows = math.ceil((W - 8) / TW), math.ceil((H - 8) / TH)
	local used = 0
	for ty = 0, rows - 1 do
		for tx = 0, cols - 1 do
			used = used + 1
			local t = frame.tiles[used]
			if not t then
				t = frame.back:CreateTexture(nil, "BACKGROUND", nil, -6)
				frame.tiles[used] = t
			end
			local w, h = math.min(TW, W - 8 - tx * TW), math.min(TH, H - 8 - ty * TH)
			t:ClearAllPoints()
			t:SetPoint("TOPLEFT", 4 + tx * TW, -(4 + ty * TH))
			t:SetSize(w, h)
			if bag then
				t:SetTexture(bag)
				local x0, x1, y0, y1 = 14, 14 + w, 170, 170 + h
				if tx % 2 == 1 then x0, x1 = 574, 574 - w end
				if ty % 2 == 1 then y0, y1 = 440, 440 - h end
				t:SetTexCoord(x0 / 1024, x1 / 1024, y0 / 1024, y1 / 1024)
			else
				t:SetColorTexture(0.05, 0.05, 0.05, 1)
			end
			t:Show()
		end
	end
	for i = used + 1, #frame.tiles do frame.tiles[i]:Hide() end
end

Layout = function()
	if not frame then return end
	local shape = Shape()
	W = Clamp(shape.w or 2200, LIMIT.minW, LIMIT.maxW)
	H = Clamp(shape.h or 1080, LIMIT.minH, LIMIT.maxH)
	shape.w, shape.h = W, H
	-- Each pane keeps a least width, so no drag can squeeze another out.
	LEFT.w = Clamp(shape.left or 360, LIMIT.left, W - LEFT.x - LIMIT.mid - LIMIT.right - 76)
	MID.x = LEFT.x + LEFT.w + 26
	MID.w = Clamp(shape.mid or TABLE_W, LIMIT.mid, W - MID.x - LIMIT.right - 50)
	RIGHT.x = MID.x + MID.w + 26
	RIGHT.w = W - RIGHT.x - 24
	CHART.top = H - CHART.h - 60
	LEFT.rows = math.max(3, math.floor((CHART.top - 44 - LEFT.top) / LEFT.pitch))
	MID.rows = math.max(3, math.floor((H - 52 - MID.top) / MID.pitch))
	RIGHT.rows = math.max(3, math.floor((H - 52 - RIGHT.top) / RIGHT.pitch))

	layingOut = true
	frame:SetSize(W * HALF, H * HALF)
	canvas:SetSize(W, H)
	frame.back:SetSize(W, H)
	layingOut = false
	LayBody()
	L.LayGlass(frame.head, frame.glass, W - 28)

	for region, col in pairs({ [frame.left] = LEFT, [frame.mid] = MID, [frame.right] = RIGHT }) do
		Place(region, "TOPLEFT", col.x, -col.top)
		region:SetSize(col.w, col.rows * col.pitch)
	end
	for i, col in ipairs({ LEFT, MID }) do
		Place(frame.dividers[i], "TOPLEFT", col.x + col.w + 7, -76)
		frame.dividers[i]:SetSize(12, H - 100)
	end

	Place(frame.fightsTitle, "TOPLEFT", LEFT.x + 10, -88)
	Place(frame.chartTitle, "TOPLEFT", LEFT.x + 4, -(CHART.top - 30))
	frame.chartTitle:SetWidth(LEFT.w)
	Place(frame.chart, "TOPLEFT", LEFT.x, -CHART.top)
	frame.chart:SetSize(LEFT.w, CHART.h)

	Place(frame.players, "TOPLEFT", MID.x + 10, -80)
	Place(frame.summary, "TOPRIGHT", MID.x + MID.w - 6, -86)
	frame.summary:SetPoint("LEFT", frame.enemies, "RIGHT", 20, 0)
	Lanes()
	for i, col in ipairs(COLUMNS) do
		Place(frame.heads[i], "TOPRIGHT", MID.x + col.right, -120)
		frame.heads[i]:SetSize(col.w, 26)
	end
	for _, row in ipairs(listRows) do SpreadRow(row) end
	Place(frame.wait, "TOPLEFT", MID.x + 12, -(MID.top + 10))
	Place(frame.empty, "TOPLEFT", MID.x + 12, -(MID.top + 10))

	Place(frame.who, "TOPLEFT", RIGHT.x + 4, -84)
	Place(frame.compare, "TOPRIGHT", RIGHT.x + RIGHT.w - 4, -84)
	Place(frame.tabs[1], "TOPLEFT", RIGHT.x + 4, -124)
	Place(frame.enemyNote, "TOPLEFT", RIGHT.x + 4, -126)
	Place(frame.none, "TOPLEFT", RIGHT.x + 12, -(RIGHT.top + 10))
	Place(frame.foot, "BOTTOMLEFT", MID.x + 4, 16, "BOTTOMLEFT")
end

---------------------------------------------------------------------------
-- The window

local function Build()
	L = ns.Meter.Lib
	frame = CreateFrame("Frame", "SanctuaryUIMeterAnalysis", UIParent)
	frame:SetFrameStrata("HIGH")
	frame:SetSize(W * HALF, H * HALF)
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:Hide()
	tinsert(UISpecialFrames, "SanctuaryUIMeterAnalysis") -- Escape closes it

	-- Two layers at half scale: the backdrop (edge, bronze line, the bag window's dark body) and
	-- over it the canvas everything else is drawn on. The body is re-tiled to the window's size
	-- by LayBody; nothing depends on clipping.
	local base = frame:GetFrameLevel()
	local back = CreateFrame("Frame", nil, frame)
	back:SetScale(HALF)
	back:SetPoint("TOPLEFT")
	back:SetFrameLevel(base)
	back:EnableMouse(false)
	frame.back, frame.tiles = back, {}
	local edge = back:CreateTexture(nil, "BACKGROUND", nil, -8)
	edge:SetAllPoints()
	edge:SetColorTexture(0.03, 0.027, 0.023, 1)
	local line = back:CreateTexture(nil, "BACKGROUND", nil, -7)
	line:SetPoint("TOPLEFT", 3, -3)
	line:SetPoint("BOTTOMRIGHT", -3, 3)
	line:SetColorTexture(LINE[1], LINE[2], LINE[3], 1)

	canvas = CreateFrame("Frame", nil, frame)
	canvas:SetScale(HALF)
	canvas:SetPoint("TOPLEFT")
	canvas:SetSize(W, H)
	canvas:SetFrameLevel(base + 2)

	-- Title strip: drag to move.
	local head = CreateFrame("Button", nil, canvas)
	head:SetPoint("TOPLEFT", 10, -10)
	head:SetPoint("TOPRIGHT", -10, -10)
	head:SetHeight(52)
	frame.head, frame.glass = head, {}
	head:RegisterForDrag("LeftButton")
	head:SetScript("OnDragStart", function() frame:StartMoving() end)
	head:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
	local hEdge = head:CreateTexture(nil, "BACKGROUND")
	hEdge:SetAllPoints()
	hEdge:SetColorTexture(0.04, 0.03, 0.024, 1)
	local hLine = head:CreateTexture(nil, "BORDER")
	hLine:SetPoint("TOPLEFT", 3, -3)
	hLine:SetPoint("BOTTOMRIGHT", -3, 3)
	hLine:SetColorTexture(0.59, 0.44, 0.19, 1)
	local over = CreateFrame("Frame", nil, head)
	over:SetAllPoints()
	over:SetFrameLevel(head:GetFrameLevel() + 1)
	local title = L.Text(over, L.TitleFont(), 28, L.GOLD)
	title:SetPoint("LEFT", 18, -1)
	title:SetText("Analysis")
	frame.sub = Label(over, 22)
	frame.sub:SetPoint("LEFT", title, "RIGHT", 24, -1)
	local close = CreateFrame("Button", nil, over)
	close:SetSize(44, 44)
	close:SetPoint("RIGHT", -6, 0)
	close.text = L.Text(close, L.TitleFont(), 28, L.GOLD, "CENTER")
	close.text:SetPoint("CENTER")
	close.text:SetText("X")
	close:SetScript("OnClick", function() frame:Hide() end)

	-- The lines between the panes: drag one to give a pane more room.
	frame.dividers = {}
	for i, key in ipairs({ "left", "mid" }) do
		local d = CreateFrame("Button", nil, canvas)
		d:SetFrameLevel(canvas:GetFrameLevel() + 6)
		d.rule = d:CreateTexture(nil, "ARTWORK")
		d.rule:SetPoint("TOP")
		d.rule:SetPoint("BOTTOM")
		d.rule:SetWidth(2)
		d.rule:SetColorTexture(LINE[1], LINE[2], LINE[3], 0.8)
		local glow = d:CreateTexture(nil, "HIGHLIGHT")
		glow:SetAllPoints()
		glow:SetColorTexture(L.GOLD[1], L.GOLD[2], L.GOLD[3], 0.25)
		d:SetScript("OnMouseDown", function(self, button)
			if button == "RightButton" then
				-- Back to the panes' usual shares of the window, whatever its width.
				local shape = Shape()
				shape.left, shape.mid = W * 360 / 2200, W * TABLE_W / 2200
				Layout()
				A.Refresh()
			else
				self.dragging = true
			end
		end)
		d:SetScript("OnMouseUp", function(self) self.dragging = nil end)
		d:SetScript("OnHide", function(self) self.dragging = nil end)
		d:SetScript("OnUpdate", function(self)
			if not self.dragging then return end
			if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then self.dragging = nil return end
			-- The cursor in the canvas's own pixels, measured from the canvas's left edge.
			local x = GetCursorPosition() / canvas:GetEffectiveScale() - (canvas:GetLeft() or 0)
			local col = key == "left" and LEFT or MID
			local width = math.floor(x - col.x - 13)
			if width ~= Shape()[key] then
				Shape()[key] = width
				Layout()
				A.Refresh()
			end
		end)
		d:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
			GameTooltip:SetText("Drag to resize the panes")
			GameTooltip:AddLine("Right-click to even the panes out.", 1, 1, 1)
			GameTooltip:Show()
		end)
		d:SetScript("OnLeave", GameTooltip_Hide)
		frame.dividers[i] = d
	end

	-- The corner: drag to resize the window.
	frame:SetResizable(true)
	if frame.SetResizeBounds then
		frame:SetResizeBounds(LIMIT.minW * HALF, LIMIT.minH * HALF, LIMIT.maxW * HALF, LIMIT.maxH * HALF)
	elseif frame.SetMinResize then
		frame:SetMinResize(LIMIT.minW * HALF, LIMIT.minH * HALF)
		frame:SetMaxResize(LIMIT.maxW * HALF, LIMIT.maxH * HALF)
	end
	local grip = CreateFrame("Button", nil, canvas)
	grip:SetFrameLevel(canvas:GetFrameLevel() + 8)
	grip:SetSize(36, 36)
	grip:SetPoint("BOTTOMRIGHT", -6, 6)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
	grip:SetScript("OnMouseUp", function() frame:StopMovingOrSizing() end)
	frame:SetScript("OnSizeChanged", function(_, width, height)
		if layingOut or not width then return end
		local shape = Shape()
		local was = shape.w
		shape.w, shape.h = math.floor(width / HALF + 0.5), math.floor(height / HALF + 0.5)
		-- Every pane takes its share of a wider or narrower window; the lines between them
		-- still move one pane at a time.
		if was and was > 0 and shape.w ~= was then
			local grow = shape.w / was
			shape.left = (shape.left or 360) * grow
			shape.mid = (shape.mid or TABLE_W) * grow
		end
		Layout()
		A.Refresh()
	end)

	-- Left: fights, and under them the trend.
	local fights = L.Text(canvas, L.TitleFont(), 22, L.GOLD)
	fights:SetPoint("TOPLEFT", LEFT.x + 10, -88)
	fights:SetText("Fights")
	frame.fightsTitle = fights
	frame.left = Region(LEFT, "fights")
	frame.chartTitle = Label(canvas, 17, L.GOLD)
	frame.chartTitle:SetPoint("TOPLEFT", LEFT.x + 4, -(CHART.top - 30))
	frame.chartTitle:SetWidth(LEFT.w)
	frame.chartTitle:SetAlpha(0.85)
	frame.chart = CreateFrame("Frame", nil, canvas)
	frame.chart:SetPoint("TOPLEFT", canvas, "TOPLEFT", LEFT.x, -CHART.top)
	frame.chart:SetSize(LEFT.w, CHART.h)
	local base = frame.chart:CreateTexture(nil, "BACKGROUND")
	base:SetPoint("BOTTOMLEFT", 0, -2)
	base:SetPoint("BOTTOMRIGHT", 0, -2)
	base:SetHeight(2)
	base:SetColorTexture(LINE[1], LINE[2], LINE[3], 1)

	-- Middle: players or enemies, the totals, and headings that sort.
	frame.players = TextButton(canvas, "Players", function() mode, selected, scroll.list, scroll.detail = "players", nil, 0, 0 A.Refresh() end)
	frame.players:SetPoint("TOPLEFT", MID.x + 10, -80)
	frame.enemies = TextButton(canvas, "Enemies", function() mode, selected, scroll.list, scroll.detail = "enemies", nil, 0, 0 A.Refresh() end)
	frame.enemies:SetPoint("LEFT", frame.players, "RIGHT", 16, 0)
	Tip(frame.players, "Players", "Everyone who took part in the fight, with every tally side by side.")
	Tip(frame.enemies, "Enemies", "What the group hit, by damage taken. Click an enemy for the abilities that hit it. Only for fights the game still remembers.")
	frame.summary = Label(canvas, 19, L.CREAM, "RIGHT")
	frame.summary:SetPoint("TOPRIGHT", canvas, "TOPLEFT", MID.x + MID.w - 6, -86)
	frame.summary:SetPoint("LEFT", frame.enemies, "RIGHT", 20, 0)
	frame.heads = {}
	for i, col in ipairs(COLUMNS) do
		local h = TextButton(canvas, col.label, function()
			if mode ~= "players" then return end
			sortKey, scroll.list = col.key, 0
			A.Refresh()
		end, 17, "RIGHT")
		h.key = col.key
		Tip(h, col.tip[1], col.tip[2], "Click to sort the table by this column.")
		frame.heads[i] = h
	end
	frame.mid = Region(MID, "list")
	frame.wait = Label(canvas, 21)
	frame.wait:SetPoint("TOPLEFT", MID.x + 12, -(MID.top + 10))
	frame.wait:SetText("The game hasn't released the numbers yet...")
	frame.empty = Label(canvas, 21)
	frame.empty:SetPoint("TOPLEFT", MID.x + 12, -(MID.top + 10))
	frame.empty:SetText("Nothing recorded for this fight.")
	frame.empty:SetAlpha(0.7)

	-- Right: the chosen one's abilities, a tab per tally.
	frame.who = L.Text(canvas, L.TitleFont(), 26, L.GOLD)
	frame.who:SetPoint("TOPLEFT", RIGHT.x + 4, -84)
	frame.compare = TextButton(canvas, "Compare: best", function()
		compare = compare == "off" and "best" or compare == "best" and "last" or "off"
		A.Refresh()
	end, 19, "RIGHT")
	frame.compare:SetPoint("TOPRIGHT", canvas, "TOPLEFT", RIGHT.x + RIGHT.w - 4, -84)
	Tip(frame.compare, "Compare", "Sets your damage against an earlier saved attempt at the same fight: your best one, or your last one. Each ability then shows how much more or less it did per second.", "Click to step through off, best, last.")
	frame.tabs = {}
	for i, t in ipairs(TABS) do
		local b = TextButton(canvas, t.label, function() tab, scroll.detail = t.key, 0 A.Refresh() end, 19)
		b.key = t.key
		Tip(b, t.tip[1], t.tip[2])
		if i == 1 then
			b:SetPoint("TOPLEFT", RIGHT.x + 4, -124)
		else
			b:SetPoint("LEFT", frame.tabs[i - 1], "RIGHT", 8, 0)
		end
		frame.tabs[i] = b
	end
	frame.enemyNote = Label(canvas, 21)
	frame.enemyNote:SetPoint("TOPLEFT", RIGHT.x + 4, -126)
	frame.enemyNote:SetText("Damage taken, by ability")
	frame.enemyNote:SetAlpha(0.75)
	frame.right = Region(RIGHT, "detail")
	frame.none = Label(canvas, 21)
	frame.none:SetPoint("TOPLEFT", RIGHT.x + 12, -(RIGHT.top + 10))
	frame.none:SetText("Nothing recorded.")
	frame.none:SetAlpha(0.7)

	local foot = Label(canvas, 18)
	foot:SetPoint("BOTTOMLEFT", MID.x + 4, 16)
	foot:SetText("Out of combat only. Click a heading to sort. Drag the lines between panes, or the corner, to resize.")
	foot:SetAlpha(0.6)
	frame.foot = foot
	frame.best = Label(canvas, 20, L.GOLD, "RIGHT")
	frame.best:SetPoint("BOTTOMRIGHT", -56, 16)
	for _, region in ipairs({ frame.left, frame.mid, frame.right }) do
		if region.SetClipsChildren then region:SetClipsChildren(true) end
	end

	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_REGEN_DISABLED")
	pcall(events.RegisterEvent, events, "DAMAGE_METER_RESET")
	events:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_REGEN_DISABLED" then
			frame:Hide()
		else
			A.Refresh()
		end
	end)
end

-- fight: "current", "overall" or a past fight's ID; nil keeps the last one looked at.
function A.Open(fight)
	if not ns.Meter.Supported() then
		ns.Print("this client has no damage meter data for addons.")
		return
	end
	if InCombatLockdown() then
		ns.Print("the analysis opens when the fight ends: the game hides the numbers from addons in combat.")
		return
	end
	if not frame then Build() end
	if fight ~= nil then seg = fight end
	frame:SetScale(ns.Art.D3Scale(BASE_SCALE * (ns.DB().meter.analysisScale or 1)))
	Layout()
	frame:Show()
	A.Refresh()
end

function A.IsOpen()
	return frame ~= nil and frame:IsShown()
end

function A.Toggle()
	if frame and frame:IsShown() then frame:Hide() else A.Open() end
end
