SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.RunReport = ns.RunReport or {}

-- The Run Report: one dungeon or raid visit, page by page, in D3's window (the inventory's
-- header with crossed swords in the medallion, the dark body, the stone foot) with D3's red side
-- tabs for its pages:
--
--   Summary    the bosses, your damage per second pull by pull, the group's totals for the
--              whole run, your run in three lines, the awards in the stone foot.
--   Pulls      the run as a timeline (each pull as wide as it lasted, as tall as the group hit,
--              deaths under it), every pull listed; a click opens it in the analysis window.
--   Bosses     every attempt: the chosen one against the one before it, the group in it, who died.
--   Players    anyone's run: their abilities for each tally, their deaths, their DPS pull by pull.
--   Dangers    every death with the blow that killed, avoidable damage by ability and player,
--              interrupts and dispels, what hurt most.
--   Past runs  your runs here (or everywhere), records, your best on each boss against this run.
--
-- Everything comes from MeterHistory.lua's run records, written half a second after each fight
-- when the game opens its numbers up, so the window works in or out of combat. When a run
-- ends, a "Run complete" line with a Report button waits beside the meter until clicked or the
-- next pull. Sizes are in the mockup's pixels (mockups/run-report-page-*.png), drawn on a
-- half-scale canvas like the meter's other windows.

local R = ns.RunReport
local L -- ns.Meter.Lib, set when the window is first built

local W, H = 1500, 980
local HALF = 0.5
-- 100% on the Window scale slider: 1275 x 833 pixels at 1080p (art pixels x HALF x this, one
-- art pixel being one pixel at 1080p; see ns.Art.D3Scale). Bigger screens get it in proportion.
local BASE_SCALE = 1.7
local MOST_OF_SCREEN = 0.92 -- however the slider is set, the window keeps inside this much of the screen
local BANNER_SCALE = 1.3 -- the run-complete banner, before its own size slider
local HEAD_H = 156
local FOOT_H = 180
local FOOT_Y = H - FOOT_H
local ATLAS = 1024
local CAP = 40 -- a rail's pointed end, in the parts sheet's pixels
local LINE = { 0.29, 0.24, 0.16 }
local GREY = { 0.63, 0.59, 0.53 }
local EMBER = { 0.94, 0.55, 0.31 }
local IRON = { 0.62, 0.52, 0.42 }
local DEATH_ICON = 237274

local PAGES = {
	{ key = "summary", label = "Summary", journal = 0, tip = "The bosses, your damage pull by pull, the group's totals for the whole run, and the awards." },
	{ key = "pulls", label = "Pulls", journal = 3, tip = "The run as a timeline, and every pull in order. Click a pull for its own analysis." },
	{ key = "bosses", label = "Bosses", journal = 7, tip = "Every attempt at every boss: the chosen one against the one before it, and the group in it." },
	{ key = "players", label = "Players", journal = 2, tip = "Anyone's run: their abilities for each tally, their deaths, their damage pull by pull." },
	{ key = "dangers", label = "Dangers", journal = 1, tip = "Every death with the blow that killed, avoidable damage by ability and player, interrupts and dispels." },
	{ key = "past", label = "Past runs", journal = 4, tip = "Your earlier runs, records, and your best on each boss against this run." },
}

local TALLIES = {
	{ key = "d", label = "Damage", word = "damage" },
	{ key = "h", label = "Healing", word = "healing" },
	{ key = "t", label = "Taken", word = "damage taken" },
	{ key = "a", label = "Avoidable", word = "avoidable damage" },
	{ key = "i", label = "Interrupts", word = "interrupts", count = true },
	{ key = "x", label = "Dispels", word = "dispels", count = true },
	{ key = "deaths", label = "Deaths", word = "deaths" },
}

local ORDINAL = { "First", "Second", "Third", "Fourth", "Fifth", "Sixth", "Seventh", "Eighth", "Ninth", "Tenth" }
local PLACE = { "1st", "2nd", "3rd" }

local frame, canvas, banner
local run -- the run shown
local sample -- the preview's made-up runs, while previewing
local page = "summary"
local pages = {}
local chosen = { pull = nil, boss = nil, player = nil, tally = "d", scope = "here" }

local function Opt() return ns.DB().meter end

---------------------------------------------------------------------------
-- Numbers

local function Short(v) return L.Short(v or 0) end
local function Clock(s) return L.Clock(s or 0) end
local function Place(rank) return PLACE[rank] or (tostring(rank) .. "th") end

local function SpellName(id, e)
	if e and e.nm then return e.nm end
	local ok, name = pcall(L.GetSpellName, id)
	return ok and name or ("Spell " .. tostring(id))
end

local function SpellIcon(id)
	if not id or id <= 0 then return 134400 end
	local ok, icon = pcall(L.GetSpellTexture, id)
	return ok and icon or 134400
end

local function Name(n, player)
	if not n then return "?" end
	return L.ShortName(n, player ~= false) or n
end

local function Colored(n, class)
	local r, g, b = L.ClassColor(class)
	return ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, Name(n))
end

local function Pct(part, whole)
	if not whole or whole <= 0 then return "" end
	return ("%d%%"):format(math.floor(part / whole * 100 + 0.5))
end

local function Runs()
	if sample then return sample.runs end
	return ns.MeterHistory.Runs()
end

local function Bests()
	if sample then return sample.bests end
	local m = ns.MeterHistory.Store()
	return m and m.bests or {}
end

-- The run still going on: its clock runs to now.
local function Live(r)
	if sample or r.done or r.complete then return false end
	local m = ns.MeterHistory.Store()
	return m and m.inRun ~= nil and m.run == r.id
end

local function Fighting(r)
	local s = 0
	for _, p in ipairs(r.pulls) do s = s + (p.dur or 0) end
	return s
end

-- Door to door: from going in (or the first pull, if that was earlier) to leaving, or to now.
local function Length(r)
	local first, last = r.t0, r.t1 or r.t0
	for _, p in ipairs(r.pulls) do
		last = math.max(last or 0, p.t or 0)
		first = math.min(first or math.huge, (p.t or 0) - (p.dur or 0))
	end
	if Live(r) then last = math.max(last, time()) end
	return math.max(1, Fighting(r), (last or 0) - (first or last or 0))
end

-- When the run's clock starts: the timeline's zero.
local function Start(r)
	local first = r.t0
	for _, p in ipairs(r.pulls) do first = math.min(first or math.huge, (p.t or 0) - (p.dur or 0)) end
	return first or 0
end

-- Everyone in the run, most damage first.
local function Players(r)
	local list = {}
	for _, n in ipairs(r.order) do list[#list + 1] = r.players[n] end
	table.sort(list, function(a, b) return (a.d or 0) > (b.d or 0) end)
	return list
end

local function Me(r)
	for _, n in ipairs(r.order) do
		if r.players[n].me then return r.players[n] end
	end
end

local function Dps(a)
	return (a.sec or 0) > 0 and (a.d or 0) / a.sec or 0
end

local function BossPulls(r)
	local list = {}
	for i, p in ipairs(r.pulls) do
		if p.boss then list[#list + 1] = i end
	end
	return list
end

local function Wipes(r)
	local n = 0
	for _, p in ipairs(r.pulls) do
		if p.boss and p.kill == false then n = n + 1 end
	end
	return n
end

local function Kills(r)
	local seen, n = {}, 0
	for _, p in ipairs(r.pulls) do
		if p.boss and p.kill ~= false and not seen[p.boss] then
			seen[p.boss] = true
			n = n + 1
		end
	end
	return n
end

local function Topped(r)
	local fights, topped = 0, 0
	for _, p in ipairs(r.pulls) do
		if (p.size or 0) > 1 then
			fights = fights + 1
			if p.rank == 1 then topped = topped + 1 end
		end
	end
	return topped, fights
end

local function PullName(p)
	return p.boss or p.name or "Pull"
end

-- A player's abilities for one tally over the run, largest first: { id, v, n, o, dl, av, from, nm }.
-- A saved ability: kept by name since 0.24.1 (the key is the name, t.id the rank that did most),
-- by spell ID before that.
local function Entry(k, t)
	local id = t.id or (type(k) == "number" and k or nil)
	return { id = id, v = t.v or 0, n = t.n, o = t.o, dl = t.dl, av = t.av, from = t.from,
		nm = t.nm or (type(k) == "string" and k or nil) }
end

-- Fold a rank into the entry for its ability: Lightning Bolt (Rank 3) and (Rank 4) are one line.
-- Pulls take the larger count (two ranks in one pull would otherwise count it twice).
local function Fold(into, e)
	if e.v > into.v then into.id, into.from = e.id, e.from or into.from end
	into.v = into.v + e.v
	into.n = math.max(into.n or 0, e.n or 0)
	if e.o then into.o = (into.o or 0) + e.o end
	if e.dl then into.dl = (into.dl or 0) + e.dl end
	into.av = into.av or e.av
end

-- A player's abilities for one tally over the run, one line per ability (ranks together),
-- largest first: { id, v, n, o, dl, av, from, nm }.
local function Spells(a, key)
	local byName, list = {}, {}
	for k, t in pairs(a and a.sp and a.sp[key] or {}) do
		local e = Entry(k, t)
		local name = SpellName(e.id, e)
		local into = byName[name]
		if into then
			Fold(into, e)
		else
			byName[name] = e
			list[#list + 1] = e
		end
	end
	table.sort(list, function(x, y) return x.v > y.v end)
	return list
end

-- One tally's abilities summed over everyone, one line per ability: { id, v, nm, by = name -> v }.
local function AllSpells(r, key)
	local all, list = {}, {}
	for _, n in ipairs(r.order) do
		for k, t in pairs(r.players[n].sp and r.players[n].sp[key] or {}) do
			local x = Entry(k, t)
			local name = SpellName(x.id, x)
			local e = all[name]
			if not e then
				e = { id = x.id, v = 0, by = {}, nm = x.nm, top = 0 }
				all[name] = e
				list[#list + 1] = e
			end
			if x.v > e.top then e.id, e.top = x.id, x.v end
			e.v = e.v + x.v
			e.by[n] = (e.by[n] or 0) + x.v
		end
	end
	table.sort(list, function(x, y) return x.v > y.v end)
	return list
end

-- Find the saved fight behind a pull, for the analysis window.
local function FightFor(pull)
	local m = ns.MeterHistory.Store()
	if not m or sample then return nil end
	for i = #m.fights, 1, -1 do
		local f = m.fights[i]
		if f.t == pull.t and f.dur == pull.dur then return f end
	end
end

---------------------------------------------------------------------------
-- Widgets

local function Label(parent, size, color, justify)
	return L.Text(parent, L.BodyFont(), size or 22, color or L.CREAM, justify)
end

local function Title(parent, size, color, justify)
	return L.Text(parent, L.TitleFont(), size or 24, color or L.GOLD, justify)
end

-- Text placed by its middle, like the mockup: justify LEFT, RIGHT or CENTER at x.
local function At(fs, parent, x, y, justify)
	fs:ClearAllPoints()
	local point = justify == "RIGHT" and "RIGHT" or justify == "CENTER" and "CENTER" or "LEFT"
	fs:SetPoint(point, parent, "TOPLEFT", x, -y)
	return fs
end

-- A note that wraps inside its room, hung from its top left.
local function Notice(parent, x, y, w, size)
	local fs = Label(parent, size or 21, GREY)
	fs:SetWordWrap(true)
	if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(false) end
	fs:SetJustifyV("TOP")
	fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -(y - 12))
	fs:SetWidth(w)
	return fs
end

local function SetColor(fs, c)
	fs:SetTextColor(c[1], c[2], c[3])
end

local function Heading(parent, x, y, word, note)
	local h = At(Title(parent, 24), parent, x, y)
	h:SetText(word)
	local n = Label(parent, 19, GREY)
	n:SetPoint("LEFT", h, "RIGHT", 24, -1)
	n:SetText(note or "")
	h.note = n
	return h
end

local function Tip(widget, title, text, more)
	widget:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(type(title) == "function" and title(self) or title)
		local body = type(text) == "function" and text(self) or text
		if body then GameTooltip:AddLine(body, 1, 1, 1, true) end
		if more then GameTooltip:AddLine(more, 0.7, 0.7, 0.7, true) end
		GameTooltip:Show()
	end)
	widget:SetScript("OnLeave", GameTooltip_Hide)
end

local function Box(parent, x, y, w, h)
	local f = CreateFrame("Frame", nil, parent)
	f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
	f:SetSize(w, h)
	return f
end

-- D3's red button plate in three slices, behind a chosen word.
local function Plate(parent)
	local list = {}
	local path = ns.Art.Path("d3Button")
	for i, cut in ipairs({ { 0, 24 }, { 24, 72 }, { 96, 24 } }) do
		local t = parent:CreateTexture(nil, "BACKGROUND", nil, 2)
		if path then
			t:SetTexture(path)
			t:SetTexCoord(cut[1] / 128, (cut[1] + cut[2]) / 128, 0, 52 / 64)
		else
			t:SetColorTexture(0.3, 0.05, 0.03, 1)
		end
		list[i] = t
	end
	list[1]:SetPoint("TOPLEFT")
	list[1]:SetPoint("BOTTOMLEFT")
	list[1]:SetWidth(24)
	list[3]:SetPoint("TOPRIGHT")
	list[3]:SetPoint("BOTTOMRIGHT")
	list[3]:SetWidth(24)
	list[2]:SetPoint("TOPLEFT", list[1], "TOPRIGHT")
	list[2]:SetPoint("BOTTOMRIGHT", list[3], "BOTTOMLEFT")
	return list
end

-- A word you click: gold on a red plate while it's the one chosen.
local function Word(parent, word, size, onClick)
	local b = CreateFrame("Button", nil, parent)
	b.text = Label(b, size or 21, L.CREAM)
	b.text:SetPoint("CENTER", 0, 0)
	b.text:SetText(word)
	local wide = b.text:GetStringWidth()
	b:SetSize(math.max(60, (wide and wide > 0 and wide or #word * 11) + 36), 40)
	b.plate = Plate(b)
	b:SetScript("OnClick", onClick)
	b.SetChosen = function(self, on)
		for _, t in ipairs(self.plate) do t:SetShown(on) end
		SetColor(self.text, on and L.GOLD or GREY)
	end
	return b
end

-- A stud from the parts sheet: 0 iron, 2 gold, 3 molten.
local function Stud(parent, size)
	local t = parent:CreateTexture(nil, "ARTWORK", nil, 3)
	t:SetSize(size, size)
	t.Dress = function(self, kind)
		if ns.Art.Apply(self, "targetStyleParts") then
			L.Coords(self, kind * 48, 768, 48, 48, ATLAS)
			if kind == 0 then self:SetVertexColor(IRON[1] * 1.2, IRON[2] * 1.2, IRON[3] * 1.2) else self:SetVertexColor(1, 1, 1) end
		else
			self:SetColorTexture(0.5, 0.4, 0.2, 1)
		end
	end
	return t
end

-- A forged rail like the meter's: three slices of the parts sheet (0 iron, 2 gold, 3 molten)
-- and a class-coloured fill in its slot. lane: how far a full fill reaches (the name's room).
local function Rail(parent, w, h)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(w, h)
	f.l = f:CreateTexture(nil, "ARTWORK", nil, 0)
	f.m = f:CreateTexture(nil, "ARTWORK", nil, 0)
	f.r = f:CreateTexture(nil, "ARTWORK", nil, 0)
	local k = h / 46
	local c = CAP * k
	f.l:SetPoint("TOPLEFT")
	f.l:SetSize(c, h)
	f.r:SetPoint("TOPRIGHT")
	f.r:SetSize(c, h)
	f.m:SetPoint("TOPLEFT", f.l, "TOPRIGHT")
	f.m:SetPoint("BOTTOMRIGHT", f.r, "BOTTOMLEFT")
	f.fill = f:CreateTexture(nil, "ARTWORK", nil, 2)
	f.fill:SetPoint("TOPLEFT", 20 * k, -10 * k)
	f.fill:SetHeight(h - 20 * k)
	f.slot = w - 40 * k
	if not ns.Art.Apply(f.fill, "unitFillWhite") then f.fill:SetColorTexture(1, 1, 1, 1) end
	-- Empty until filled: a texture with no width set takes its file's (512 pixels) and would
	-- run white across the rail and out past its end.
	f.fill:SetWidth(1)
	f.fill:Hide()
	f.Dress = function(self, kind)
		if self.kind == kind then return end
		self.kind = kind
		local y = 562 + kind * 52
		for _, t in ipairs({ self.l, self.m, self.r }) do
			if not ns.Art.Apply(t, "targetStyleParts") then t:SetColorTexture(0.12, 0.1, 0.08, 1) end
		end
		L.Coords(self.l, 4, y, CAP, 46, ATLAS)
		L.Coords(self.m, 4 + CAP, y, 502 - 2 * CAP, 46, ATLAS)
		L.Coords(self.r, 506 - CAP, y, CAP, 46, ATLAS)
		local col = kind == 0 and IRON or { 1, 1, 1 }
		for _, t in ipairs({ self.l, self.m, self.r }) do t:SetVertexColor(col[1], col[2], col[3]) end
	end
	f.Fill = function(self, frac, r, g, b, lane)
		if not frac or frac <= 0 then
			self.fill:Hide()
			return
		end
		self.fill:SetWidth(math.max(1, (lane or self.slot) * math.min(1, frac)))
		self.fill:SetVertexColor(r * 0.85, g * 0.85, b * 0.85, 1)
		self.fill:Show()
	end
	f:Dress(0)
	return f
end

-- The analysis window's chosen-row wash and hover light.
local function Marks(row)
	row.stripe = row:CreateTexture(nil, "BACKGROUND")
	row.stripe:SetAllPoints()
	row.stripe:SetColorTexture(1, 0.94, 0.86, 0.04)
	row.pick = row:CreateTexture(nil, "BACKGROUND", nil, 1)
	row.pick:SetAllPoints()
	row.pick:SetColorTexture(L.GOLD[1], L.GOLD[2], L.GOLD[3], 0.16)
	row.pick:Hide()
	local hover = row:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints()
	hover:SetColorTexture(1, 1, 1, 0.06)
end

-- Rows that scroll with the mouse wheel: make(row, i) builds one, a page's Draw fills them.
local function List(parent, x, y, w, pitch, count, make)
	local list = { rows = {}, offset = 0, count = count, pitch = pitch }
	local region = Box(parent, x, y, w, count * pitch)
	region:EnableMouseWheel(true)
	region:SetScript("OnMouseWheel", function(_, delta)
		list.offset = math.max(0, list.offset - delta)
		R.Refresh()
	end)
	list.region = region
	for i = 1, count do
		local row = CreateFrame("Button", nil, region)
		row:SetPoint("TOPLEFT", region, "TOPLEFT", 0, -(i - 1) * pitch)
		row:SetSize(w, pitch - 2)
		row:SetScript("OnMouseWheel", function(_, delta)
			list.offset = math.max(0, list.offset - delta)
			R.Refresh()
		end)
		make(row, i)
		list.rows[i] = row
	end
	return list
end

local function FillList(list, items, draw)
	list.offset = math.max(0, math.min(list.offset, #items - list.count))
	for i, row in ipairs(list.rows) do
		local item = items[i + list.offset]
		if item ~= nil then
			row.item = item
			draw(row, item, i + list.offset)
			row:Show()
		else
			row.item = nil
			row:Hide()
		end
	end
end

-- Bars, one per pull: { v, color = { r, g, b }, pull = index }. Hover for the pull, click to pick it.
local function Chart(parent, x, y, w, h)
	local c = Box(parent, x, y, w, h)
	c.bars = {}
	local base = c:CreateTexture(nil, "BACKGROUND")
	base:SetPoint("TOPLEFT", c, "BOTTOMLEFT", 0, -4)
	base:SetPoint("TOPRIGHT", c, "BOTTOMRIGHT", 0, -4)
	base:SetHeight(2)
	base:SetColorTexture(LINE[1], LINE[2], LINE[3], 1)
	c.Draw = function(self, items, top, onClick)
		local slot = math.min(36, w / math.max(1, #items)) -- a short run keeps slim bars
		for i = 1, math.max(#items, #self.bars) do
			local bar, item = self.bars[i], items[i]
			if not item then
				if bar then bar:Hide() end
			else
				if not bar then
					bar = CreateFrame("Button", nil, self)
					bar.fill = bar:CreateTexture(nil, "ARTWORK")
					bar.fill:SetPoint("BOTTOMLEFT")
					bar.fill:SetPoint("BOTTOMRIGHT")
					Tip(bar, function(b) return PullName(run.pulls[b.item.pull]) end, function(b)
						local p = run.pulls[b.item.pull]
						return ("%s damage per second, %s%s"):format(Short(b.item.v), Clock(p.dur),
							p.boss and (p.kill == false and ", a wipe" or ", a kill") or "")
					end, "Click to find it among the pulls.")
					self.bars[i] = bar
				end
				bar.item = item
				bar:ClearAllPoints()
				bar:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", (i - 1) * slot + 1, 0)
				bar:SetSize(math.max(1, slot - 3), h)
				bar.fill:SetHeight(math.max(2, top > 0 and item.v / top * h or 2))
				local col = item.color
				bar.fill:SetColorTexture(col[1], col[2], col[3], 0.9)
				bar:SetScript("OnClick", function(b) if onClick then onClick(b.item) end end)
				bar:Show()
			end
		end
	end
	return c
end

local function PullColor(p)
	if p.boss and p.kill == false then return EMBER end
	if p.boss then return L.GOLD end
	return { 0.47, 0.41, 0.33 }
end

-- The stone foot's heading and two lines.
local function Foot(parent)
	local f = {}
	f.title = At(Title(parent, 22), parent, W / 2, FOOT_Y + 42, "CENTER")
	f.lines = {}
	for i = 1, 2 do
		f.lines[i] = At(Label(parent, 22, L.CREAM, "CENTER"), parent, W / 2, FOOT_Y + 84 + (i - 1) * 32, "CENTER")
		f.lines[i]:SetWidth(W - 160)
	end
	f.Set = function(self, title, a, b)
		self.title:SetText(title or "")
		self.lines[1]:SetText(a or "")
		self.lines[2]:SetText(b or "")
	end
	return f
end

-- Column labels: { word, x, justify }.
local function Columns(parent, y, cols, size)
	local list = {}
	for i, c in ipairs(cols) do
		local fs = At(Label(parent, size or 18, GREY, c[3]), parent, c[2], y, c[3])
		fs:SetText(c[1])
		list[i] = fs
	end
	return list
end

-- Cells for a row, at the same x as their column labels.
local function Cells(row, cols, size)
	local list = {}
	for i, c in ipairs(cols) do
		list[i] = At(Label(row, size or 21, L.CREAM, c[3]), row, c[2] - (row.dx or 0), (row:GetHeight()) / 2, c[3])
	end
	return list
end

---------------------------------------------------------------------------
-- Group rails: a stud with the place, a rail with the share of the top damage, the columns.

local GROUP_COLS = {
	{ "Damage", "d" }, { "DPS", "dps" }, { "Healing", "h" }, { "Taken", "t" }, { "Int", "i", true }, { "Died", "k", true },
}

local function GroupRails(parent, x, y, w, pitch, h, count, cols, colw, onClick)
	local right = w - 34
	local labels = {}
	for i, c in ipairs(cols) do
		labels[i] = { c[1], x + right - (#cols - i) * colw, "RIGHT" }
	end
	Columns(parent, y - 26, labels)
	local lane = right - (#cols - 1) * colw - 46 - 14 - (colw - 20)
	local list = List(parent, x - 22, y, w + 22, pitch, count, function(row)
		row:SetHeight(h)
		row.mine = row:CreateTexture(nil, "ARTWORK")
		row.mine:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
		row.mine:SetSize(18, 18)
		row.mine:SetPoint("LEFT", 0, 0)
		row.mine:SetVertexColor(L.GOLD[1], L.GOLD[2], L.GOLD[3])
		row.stud = Stud(row, 38)
		row.stud:SetPoint("LEFT", 22, 0)
		row.place = Label(row, 19, L.CREAM, "CENTER")
		row.place:SetPoint("CENTER", row.stud, "CENTER", 0, 0)
		row.rail = Rail(row, w - 46, h)
		row.rail:SetPoint("LEFT", 22 + 46, 0)
		row.name = Label(row.rail, 23)
		row.name:SetPoint("LEFT", 30 * h / 46, 1)
		row.name:SetWidth(math.max(80, right - (#cols - 1) * colw - 46 - 30 * h / 46 - 95))
		row.cells = {}
		for i in ipairs(cols) do
			local cell = Label(row.rail, 22, L.CREAM, "RIGHT")
			cell:SetPoint("RIGHT", row.rail, "LEFT", right - (#cols - i) * colw - 46, 1)
			row.cells[i] = cell
		end
		row:SetScript("OnClick", function(self) if onClick and self.item then onClick(self.item) end end)
	end)
	list.lane = lane
	list.cols = cols
	return list
end

-- items: players with the column keys (a run's totals or a pull's players).
local function DrawGroup(list, items, dur)
	local top = items[1] and (items[1].d or 0) or 0
	FillList(list, items, function(row, p, i)
		row.mine:SetShown(p.me and true or false)
		local lead = i == 1
		row.stud:Dress(lead and 2 or 0)
		row.place:SetText(i)
		SetColor(row.place, lead and { 0.12, 0.08, 0.03 } or L.CREAM)
		row.rail:Dress(lead and 2 or 0)
		local r, g, b = L.ClassColor(p.c)
		row.rail:Fill(top > 0 and (p.d or 0) / top or 0, r, g, b, list.lane)
		row.name:SetText(Name(p.n))
		SetColor(row.name, p.me and L.GOLD or L.CREAM)
		for j, c in ipairs(list.cols) do
			local v
			if c[2] == "dps" then
				v = p.dps or ((p.sec or dur or 0) > 0 and (p.d or 0) / (p.sec or dur)) or 0
				row.cells[j]:SetText(Short(v))
			else
				v = p[c[2]] or 0
				row.cells[j]:SetText(c[3] and tostring(v) or (v > 0 and Short(v) or "-"))
			end
		end
	end)
end

---------------------------------------------------------------------------
-- Page: Summary

local function GoPage(key)
	page = key
	R.Refresh()
end

local function BuildSummary(pg)
	local lx, lw = 40, 560
	Heading(pg, lx, 222, "Bosses")
	Columns(pg, 264, { { "time", lx + lw - 200, "RIGHT" }, { "place", lx + lw - 120, "RIGHT" }, { "your dps", lx + lw - 24, "RIGHT" } })
	pg.bosses = List(pg, lx, 290, lw, 52, 7, function(row)
		row:SetHeight(42)
		row.stud = Stud(row, 34)
		row.stud:SetPoint("LEFT", 0, 0)
		row.rail = Rail(row, lw - 42, 42)
		row.rail:SetPoint("LEFT", 42, 0)
		row.name = Label(row.rail, 22)
		row.name:SetPoint("LEFT", 28, 1)
		row.name:SetWidth(lw - 42 - 28 - 290)
		-- On the rail's frame, so the rail's art never covers them.
		row.time = At(Label(row.rail, 22, L.CREAM, "RIGHT"), row, lw - 200, 21, "RIGHT")
		row.place = At(Label(row.rail, 22, L.CREAM, "RIGHT"), row, lw - 120, 21, "RIGHT")
		row.dps = At(Label(row.rail, 22, L.CREAM, "RIGHT"), row, lw - 24, 21, "RIGHT")
		row.best = At(Label(row.rail, 16, L.GOLD, "RIGHT"), row, lw - 74, 21, "RIGHT")
		row:SetScript("OnClick", function(self)
			chosen.boss = self.item
			GoPage("bosses")
		end)
		Tip(row, function(self) return PullName(run.pulls[self.item]) end, "Click for this attempt on the Bosses page.")
	end)
	pg.noBosses = Notice(pg, lx, 310, lw)
	pg.noBosses:SetText("No boss fights in this run.")
	pg.chartTitle = Heading(pg, lx, 664, "Your DPS, pull by pull")
	pg.chart = Chart(pg, lx, 690, lw, 90)

	local rx, rw = 640, W - 640 - 60
	Heading(pg, rx, 222, "The group", "the whole run, every pull added up")
	pg.group = GroupRails(pg, rx, 290, rw, 54, 46, 5, GROUP_COLS, 90, function(p)
		chosen.player = p.n
		GoPage("players")
	end)
	Heading(pg, rx, 590, "Your run")
	pg.you = {}
	for i = 1, 3 do
		pg.you[i] = At(Label(pg, 22), pg, rx, 634 + (i - 1) * 32)
		pg.you[i]:SetWidth(rw)
	end

	pg.awardTitle = At(Title(pg, 22), pg, W / 2, FOOT_Y + 38, "CENTER")
	pg.awardTitle:SetText("Awards")
	pg.awards = {}
	local per = (W - 140) / 4
	for i = 1, 8 do
		local cx = 70 + ((i - 1) % 4) * per + per / 2
		local cy = H - 136 + 34 + math.floor((i - 1) / 4) * 54
		pg.awards[i] = {
			title = At(Label(pg, 18, GREY, "CENTER"), pg, cx, cy, "CENTER"),
			value = At(Label(pg, 21, L.CREAM, "CENTER"), pg, cx, cy + 22, "CENTER"),
		}
	end
end

local function YourRun(r)
	local list = Players(r)
	local me = Me(r)
	if not me then return { "You weren't in any saved fight of this run.", "", "" } end
	local rank = 1
	for i, p in ipairs(list) do
		if p == me then rank = i end
	end
	local lines = {}
	if #list < 2 then
		lines[1] = ("%s damage per second over %s of fighting."):format(Short(Dps(me)), Clock(me.sec))
	elseif rank == 1 then
		local second = list[2]
		lines[1] = ("First overall, %s ahead of %s."):format(Pct((me.d or 0) - (second.d or 0), second.d), Name(second.n))
	else
		local lead = list[1]
		lines[1] = ("%s overall, %s behind %s."):format(ORDINAL[rank] or Place(rank), Pct((lead.d or 0) - (me.d or 0), lead.d), Name(lead.n))
	end
	local firsts = 0
	for _, i in ipairs(BossPulls(r)) do
		local p = r.pulls[i]
		if p.kill ~= false and p.rank == 1 and (p.size or 0) > 1 then firsts = firsts + 1 end
	end
	if firsts > 0 then lines[1] = lines[1] .. (" First on %d boss%s."):format(firsts, firsts == 1 and "" or "es") end
	local bests = {}
	for _, i in ipairs(BossPulls(r)) do
		local p = r.pulls[i]
		if p.nb then bests[#bests + 1] = ("%s %s dps"):format(p.boss, Short(p.my or 0)) end
	end
	if #bests > 0 then
		lines[2] = ("%s: %s."):format(#bests == 1 and "A new best" or (#bests .. " new bests"), table.concat(bests, ", "))
	else
		lines[2] = "No new personal bests this run."
	end
	local spells = Spells(me, "d")
	if r.old or #spells == 0 then
		lines[3] = r.old and "Abilities weren't kept: this run began before the run report was installed." or ""
	else
		local parts = {}
		for i = 1, math.min(4, #spells) do
			parts[i] = ("%s %s"):format(SpellName(spells[i].id, spells[i]), Pct(spells[i].v, me.d))
		end
		lines[3] = "Top abilities: " .. table.concat(parts, ", ") .. "."
	end
	return lines
end

local function DrawSummary(pg, r)
	local bosses = BossPulls(r)
	pg.noBosses:SetShown(#bosses == 0)
	FillList(pg.bosses, bosses, function(row, i)
		local p = r.pulls[i]
		local wipe = p.kill == false
		row.stud:Dress(wipe and 3 or 2)
		row.rail:Dress(wipe and 3 or 0)
		row.name:SetText(p.boss)
		SetColor(row.name, wipe and EMBER or L.CREAM)
		row.time:SetText((wipe and "wipe " or "") .. Clock(p.dur))
		SetColor(row.time, wipe and EMBER or L.CREAM)
		row.place:SetText((p.size or 0) > 1 and Place(p.rank or 1) or "")
		SetColor(row.place, p.rank == 1 and L.GOLD or L.CREAM)
		row.dps:SetText(Short(p.my or 0))
		row.best:SetText(p.nb and "best" or "")
	end)
	local items, top = {}, 0
	for i, p in ipairs(r.pulls) do
		items[i] = { v = p.my or 0, color = PullColor(p), pull = i }
		top = math.max(top, p.my or 0)
	end
	pg.chart:Draw(items, top * 1.1, function(item)
		chosen.pull = item.pull
		GoPage("pulls")
	end)
	DrawGroup(pg.group, Players(r))
	local you = YourRun(r)
	for i = 1, 3 do pg.you[i]:SetText(you[i] or "") end
	local players = Players(r)
	local awards = #players > 1 and ns.MeterHistory.AwardsFrom(players) or {}
	pg.awardTitle:SetText(#awards > 0 and "Awards" or "")
	for i, cell in ipairs(pg.awards) do
		local a = awards[i]
		if a then
			local title = a.title:gsub("^Stood in the most avoidable damage$", "Stood in the most"):gsub("^Took the most damage$", "Took the most")
			cell.title:SetText(title)
			cell.value:SetText(("%s  %s"):format(Name(a.name), a.count and tostring(a.value) or Short(a.value)))
			SetColor(cell.value, a.me and L.GOLD or L.CREAM)
		else
			cell.title:SetText(i == 1 and #players < 2 and "Awards need a group." or "")
			cell.value:SetText("")
		end
	end
end

---------------------------------------------------------------------------
-- Page: Pulls

local PULL_COLS = {
	{ "#", 40, "RIGHT" }, { "at", 120, "RIGHT" }, { "pull", 150, "LEFT" }, { "length", 650, "RIGHT" },
	{ "group dps", 810, "RIGHT" }, { "your dps", 940, "RIGHT" }, { "place", 1030, "RIGHT" },
	{ "deaths", 1130, "RIGHT" }, { "top", 1170, "LEFT" },
}

local function BuildPulls(pg)
	local x0, x1 = 50, W - 70
	Heading(pg, x0, 222, "The run, minute by minute", "each block is a pull: as wide as it lasted, as tall as the group hit")
	pg.line = Box(pg, x0, 270, x1 - x0, 120)
	pg.line.blocks, pg.line.ticks, pg.line.dots = {}, {}, {}
	local axis = pg.line:CreateTexture(nil, "BACKGROUND")
	axis:SetPoint("TOPLEFT", pg.line, "BOTTOMLEFT", 0, -6)
	axis:SetPoint("TOPRIGHT", pg.line, "BOTTOMRIGHT", 0, -6)
	axis:SetHeight(2)
	axis:SetColorTexture(0.43, 0.35, 0.24, 1)
	pg.dotNote = At(Label(pg, 16, GREY, "RIGHT"), pg, x1, 270 + 120 + 52, "RIGHT")
	pg.dotNote:SetText("red: deaths")

	local cols = {}
	for i, c in ipairs(PULL_COLS) do cols[i] = { c[1], x0 + c[2], c[3] } end
	Columns(pg, 470, cols)
	pg.list = List(pg, x0, 490, x1 - x0, 36, 8, function(row)
		Marks(row)
		row.dx = x0
		row.cells = Cells(row, cols)
		row.cells[3]:SetWidth(PULL_COLS[4][2] - PULL_COLS[3][2] - 90)
		row.cells[9]:SetWidth(x1 - x0 - PULL_COLS[9][2])
		row:SetScript("OnClick", function(self)
			chosen.pull = self.item
			local fight = FightFor(run.pulls[self.item])
			if fight and ns.MeterAnalysis then
				ns.MeterAnalysis.Open(ns.MeterHistory.SegFor(fight))
			elseif sample then
				ns.Print("in the preview, pulls only light up: a real run's pull opens its analysis.")
			else
				ns.Print("that pull is no longer among the saved fights (Options > Damage meter > Fights > Fights kept).")
			end
			R.Refresh()
		end)
		Tip(row, function(self) return PullName(run.pulls[self.item]) end, "Click for this pull's own analysis: everyone in it, their abilities and deaths.")
	end)
	pg.hint = At(Label(pg, 19, GREY), pg, x0, 490 + 8 * 36 + 18)
	pg.hint:SetWidth(x1 - x0)
	pg.hint:SetText("Click a pull for its own analysis (players, abilities, deaths). The mouse wheel scrolls the list.")
	pg.foot = Foot(pg)
end

local function DrawTimeline(pg, r)
	local line = pg.line
	local w, h = line:GetWidth(), line:GetHeight()
	local total = Length(r)
	local top = 0
	for _, p in ipairs(r.pulls) do
		if (p.dur or 0) > 0 then top = math.max(top, (p.gd or 0) / p.dur) end
	end
	top = top * 1.05
	for i = 1, math.max(#r.pulls, #line.blocks) do
		local b, p = line.blocks[i], r.pulls[i]
		if not p then
			if b then b:Hide() b.label:Hide() end
		else
			if not b then
				b = CreateFrame("Button", nil, line)
				b.fill = b:CreateTexture(nil, "ARTWORK")
				b.fill:SetPoint("BOTTOMLEFT")
				b.fill:SetPoint("BOTTOMRIGHT")
				b.label = Label(line, 16, L.GOLD, "CENTER")
				b.label:SetPoint("BOTTOM", b.fill, "TOP", 0, 4)
				Tip(b, function(self) return PullName(run.pulls[self.index]) end, function(self)
					local q = run.pulls[self.index]
					return ("%s at %s, lasted %s. Group %s dps; you %s, %s."):format(
						q.boss and (q.kill == false and "A wipe" or "A kill") or "A pull", Clock((q.t - q.dur) - Start(run)), Clock(q.dur),
						Short((q.gd or 0) / math.max(1, q.dur)), Short(q.my or 0), Place(q.rank or 1))
				end, "Click to find it in the list.")
				b:SetScript("OnClick", function(self)
					chosen.pull = self.index
					pg.list.offset = math.max(0, self.index - 4)
					R.Refresh()
				end)
				line.blocks[i] = b
			end
			b.index = i
			local start = (p.t or 0) - (p.dur or 0) - Start(r)
			local bx = math.max(0, start / total * w)
			local bw = math.max(4, (p.dur or 0) / total * w)
			b:ClearAllPoints()
			b:SetPoint("BOTTOMLEFT", line, "BOTTOMLEFT", bx, 0)
			b:SetSize(bw, h)
			local gd = (p.dur or 0) > 0 and (p.gd or 0) / p.dur or 0
			b.fill:SetHeight(math.max(3, top > 0 and gd / top * h or 3))
			local c = PullColor(p)
			local lit = chosen.pull == i
			b.fill:SetColorTexture(c[1], c[2], c[3], lit and 1 or 0.88)
			if p.boss then
				b.label:SetText((p.boss:gsub("^Captain ", ""):gsub("^Edwin ", "")))
				SetColor(b.label, p.kill == false and EMBER or L.GOLD)
				b.label:Show()
			else
				b.label:Hide()
			end
			b:Show()
		end
	end
	-- The minutes along the bottom.
	local step = total > 3600 and 900 or total > 1800 and 600 or total > 600 and 300 or 60
	local n = math.floor(total / step)
	for i = 0, math.max(n, #line.ticks - 1) do
		local t = line.ticks[i + 1]
		if i > n then
			if t then t.mark:Hide() t.text:Hide() end
		else
			if not t then
				t = { mark = line:CreateTexture(nil, "BACKGROUND"), text = Label(line, 17, GREY, "CENTER") }
				t.mark:SetColorTexture(0.43, 0.35, 0.24, 1)
				t.mark:SetSize(2, 8)
				line.ticks[i + 1] = t
			end
			local x = i * step / total * w
			t.mark:ClearAllPoints()
			t.mark:SetPoint("TOP", line, "BOTTOMLEFT", x, -8)
			t.text:ClearAllPoints()
			t.text:SetPoint("TOP", line, "BOTTOMLEFT", x, -20)
			t.text:SetText(Clock(i * step))
			t.mark:Show()
			t.text:Show()
		end
	end
	-- A red dot under the pull for each death.
	local used = 0
	local stack = {}
	for _, d in ipairs(r.deaths) do
		local p = r.pulls[d.pull]
		if p then
			used = used + 1
			local dot = line.dots[used]
			if not dot then
				dot = Stud(line, 12)
				line.dots[used] = dot
			end
			dot:Dress(2)
			dot:SetVertexColor(1, 0.22, 0.16)
			stack[d.pull] = (stack[d.pull] or 0) + 1
			local start = (p.t or 0) - (p.dur or 0) - Start(r)
			local x = (start + (p.dur or 0) / 2) / total * w
			dot:ClearAllPoints()
			dot:SetPoint("TOP", line, "BOTTOMLEFT", x, -34 - (stack[d.pull] - 1) * 10)
			dot:Show()
		end
	end
	for i = used + 1, #line.dots do line.dots[i]:Hide() end
	pg.dotNote:SetShown(used > 0)
end

local function DrawPulls(pg, r)
	DrawTimeline(pg, r)
	local items = {}
	for i in ipairs(r.pulls) do items[i] = i end
	FillList(pg.list, items, function(row, i)
		local p = r.pulls[i]
		local c = row.cells
		c[1]:SetText(i)
		c[2]:SetText(Clock((p.t or 0) - (p.dur or 0) - Start(r)))
		c[3]:SetText(PullName(p) .. (p.boss and p.kill == false and "  wipe" or ""))
		SetColor(c[3], p.boss and (p.kill == false and EMBER or L.GOLD) or L.CREAM)
		c[4]:SetText(Clock(p.dur))
		c[5]:SetText(Short((p.gd or 0) / math.max(1, p.dur or 1)))
		c[6]:SetText(Short(p.my or 0))
		c[7]:SetText((p.size or 0) > 1 and Place(p.rank or 1) or "")
		SetColor(c[7], p.rank == 1 and (p.size or 0) > 1 and L.GOLD or L.CREAM)
		c[8]:SetText((p.k or 0) > 0 and tostring(p.k) or "")
		local top = r.players[p.top or ""]
		c[9]:SetText(p.top and Name(p.top) or "")
		SetColor(c[9], top and top.me and L.GOLD or L.CREAM)
		row.stripe:SetShown(i % 2 == 1)
		row.pick:SetShown(chosen.pull == i)
	end)

	-- Pace: time fighting against time between, the longest break, the run back after a wipe.
	local total, fighting = Length(r), Fighting(r)
	local longest, after, back = 0, nil, nil
	for i = 2, #r.pulls do
		local prev, p = r.pulls[i - 1], r.pulls[i]
		local gap = ((p.t or 0) - (p.dur or 0)) - (prev.t or 0)
		if gap > longest then longest, after = gap, PullName(prev) end
		if prev.boss and prev.kill == false and not back then back = gap end
	end
	local a = ("%s of %s fighting (%s)."):format(Clock(fighting), Clock(total), Pct(fighting, total))
	if after then a = a .. ("  Longest break %s, after %s."):format(Clock(longest), after) end
	if back then a = a .. ("  The way back after the wipe: %s."):format(Clock(back)) end
	local gd = 0
	for _, p in ipairs(r.pulls) do gd = gd + (p.gd or 0) end
	local b = ("Group %s dps over the run."):format(Short(fighting > 0 and gd / fighting or 0))
	local fastest, slowest
	for _, p in ipairs(r.pulls) do
		if p.boss and p.kill ~= false and (not fastest or p.dur < fastest.dur) then fastest = p end
		if not p.boss and (not slowest or p.dur > slowest.dur) then slowest = p end
	end
	if fastest then b = b .. ("  Fastest boss: %s %s."):format(fastest.boss, Clock(fastest.dur)) end
	if slowest then b = b .. ("  Longest trash pull: %s, %s."):format(Clock(slowest.dur), PullName(slowest)) end
	pg.foot:Set("Pace", a, b)
end

---------------------------------------------------------------------------
-- Page: Bosses

local BOSS_COLS = {
	{ "Damage", "d" }, { "DPS", "dps" }, { "Healing", "h" }, { "Taken", "t" }, { "Avoid", "a" }, { "Int", "i", true },
}

local function Card(parent, x, y, w)
	local c = Box(parent, x, y, w, 150)
	local back = c:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(0.055, 0.047, 0.04, 0.9)
	c.edges = {}
	for i, spec in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 2 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 2 }, { "TOPLEFT", "BOTTOMLEFT", 2 }, { "TOPRIGHT", "BOTTOMRIGHT", 2 } }) do
		local t = c:CreateTexture(nil, "BORDER")
		t:SetPoint(spec[1])
		t:SetPoint(spec[2])
		if spec[3] then t:SetWidth(spec[3]) else t:SetHeight(spec[4]) end
		c.edges[i] = t
	end
	c.title = At(Label(c, 22), c, 18, 24)
	c.labels, c.values = {}, {}
	for j = 1, 5 do
		local xx = 18 + math.floor((j - 1) / 3) * (w / 2)
		local yy = 58 + ((j - 1) % 3) * 30
		c.labels[j] = At(Label(c, 18, GREY), c, xx, yy)
		c.values[j] = At(Label(c, 20, L.CREAM, "RIGHT"), c, xx + w / 2 - 40, yy, "RIGHT")
	end
	c.Lit = function(self, on)
		local col = on and { L.GOLD[1], L.GOLD[2], L.GOLD[3], 0.8 } or { LINE[1], LINE[2], LINE[3], 1 }
		for _, t in ipairs(self.edges) do t:SetColorTexture(col[1], col[2], col[3], col[4]) end
	end
	return c
end

local function BuildBosses(pg)
	local lx, lw = 40, 470
	Heading(pg, lx, 222, "Bosses", "every attempt")
	pg.list = List(pg, lx, 280, lw, 52, 7, function(row)
		row:SetHeight(42)
		row.stud = Stud(row, 34)
		row.stud:SetPoint("LEFT", 0, 0)
		row.rail = Rail(row, lw - 42, 42)
		row.rail:SetPoint("LEFT", 42, 0)
		row.name = Label(row.rail, 22)
		row.name:SetPoint("LEFT", 28, 1)
		row.name:SetWidth(lw - 42 - 28 - 150)
		row.time = Label(row.rail, 20, GREY, "RIGHT")
		row.time:SetPoint("RIGHT", -28, 1)
		row:SetScript("OnClick", function(self)
			chosen.boss = self.item
			R.Refresh()
		end)
	end)
	pg.none = Notice(pg, lx, 300, lw)
	pg.none:SetText("No boss fights in this run.")

	local rx = 560
	local rw = W - 70 - rx
	pg.head = Heading(pg, rx, 222, "")
	local cw = (rw - 30) / 2
	pg.cards = { Card(pg, rx, 268, cw), Card(pg, rx + cw + 30, 268, cw) }
	pg.arrow = At(Label(pg, 30, L.GOLD, "CENTER"), pg, rx + cw + 15, 343, "CENTER")
	pg.arrow:SetText(">")
	pg.groupHead = Heading(pg, rx, 450, "The group in this attempt")
	pg.group = GroupRails(pg, rx, 514, rw, 46, 40, 5, BOSS_COLS, 96, function(p)
		chosen.player = p.n
		GoPage("players")
	end)
	pg.deaths = At(Label(pg, 20, EMBER), pg, rx, 514 + 5 * 46 + 20)
	pg.deaths:SetWidth(rw)
	pg.foot = Foot(pg)
end

local function Attempts(r, boss)
	local list = {}
	for i, p in ipairs(r.pulls) do
		if p.boss == boss then list[#list + 1] = i end
	end
	return list
end

local function PullStats(p)
	local avoid, ints = 0, 0
	for _, q in ipairs(p.p or {}) do
		avoid, ints = avoid + (q.a or 0), ints + (q.i or 0)
	end
	return {
		Clock(p.dur), Short((p.gd or 0) / math.max(1, p.dur or 1)), tostring(p.k or 0), Short(avoid), tostring(ints),
	}, avoid
end

local function DeathLine(r, index, prefix)
	local parts = {}
	for _, d in ipairs(r.deaths) do
		if d.pull == index then
			local s = ("%s at %s"):format(Name(d.n), Clock(d.at))
			if d.by then s = s .. " to " .. SpellName(d.by, d) end
			if d.o and d.o > 0 then s = s .. (" (%s overkill)"):format(Short(d.o)) end
			parts[#parts + 1] = s
		end
	end
	if #parts == 0 then return nil end
	return (prefix or "Deaths:  ") .. table.concat(parts, ".  ") .. "."
end

local function DrawBosses(pg, r)
	local bosses = BossPulls(r)
	pg.none:SetShown(#bosses == 0)
	local sel = chosen.boss
	if not sel or not r.pulls[sel] or not r.pulls[sel].boss then sel = bosses[#bosses] end
	chosen.boss = sel
	FillList(pg.list, bosses, function(row, i)
		local p = r.pulls[i]
		local wipe = p.kill == false
		row.stud:Dress(wipe and 3 or 2)
		row.rail:Dress(i == sel and 2 or (wipe and 3 or 0))
		row.name:SetText(p.boss)
		SetColor(row.name, wipe and EMBER or L.CREAM)
		row.time:SetText((wipe and "wipe " or "") .. Clock(p.dur))
	end)
	local show = sel ~= nil
	for _, w in ipairs({ pg.cards[1], pg.cards[2], pg.arrow, pg.groupHead, pg.groupHead.note, pg.group.region, pg.deaths, pg.head, pg.head.note }) do
		w:SetShown(show)
	end
	if not show then
		pg.foot:Set("", "", "")
		return
	end
	local p = r.pulls[sel]
	local tries = Attempts(r, p.boss)
	local nth = 1
	for k, i in ipairs(tries) do
		if i == sel then nth = k end
	end
	pg.head:SetText(p.boss)
	pg.head.note:SetText(#tries == 1 and "one attempt" or ("%d attempts, number %d chosen"):format(#tries, nth))
	local prev = nth > 1 and tries[nth - 1] or nil
	local cards = prev and { prev, sel } or { sel }
	for k, card in ipairs(pg.cards) do
		local i = cards[k]
		if not i then
			card:Hide()
		else
			local q = r.pulls[i]
			local num = 1
			for kk, ii in ipairs(tries) do
				if ii == i then num = kk end
			end
			card.title:SetText(("Attempt %d, %s"):format(num, q.kill == false and "wipe" or "kill"))
			SetColor(card.title, q.kill == false and EMBER or L.GOLD)
			local stats = PullStats(q)
			for j, word in ipairs({ "length", "group dps", "deaths", "avoidable taken", "interrupts" }) do
				card.labels[j]:SetText(word)
				card.values[j]:SetText(q.p and stats[j] or (j <= 3 and stats[j] or "-"))
			end
			card:Lit(i == sel)
			card:Show()
		end
	end
	pg.arrow:SetShown(prev ~= nil)
	pg.groupHead:SetText(p.kill == false and "The group in the wipe" or "The group in the kill")
	local players = {}
	for _, q in ipairs(p.p or {}) do players[#players + 1] = q end
	table.sort(players, function(a, b) return (a.d or 0) > (b.d or 0) end)
	DrawGroup(pg.group, players, p.dur)
	local line = DeathLine(r, sel)
	if not line and prev then line = DeathLine(r, prev, ("In attempt %d:  "):format(nth - 1)) end
	pg.deaths:SetText(line or (#players == 0 and "This attempt's players weren't kept." or "Nobody died."))
	SetColor(pg.deaths, line and EMBER or GREY)

	-- From the attempt before to this one, or this one alone.
	local me
	for _, q in ipairs(p.p or {}) do
		if q.me then me = q end
	end
	local best = p.best
	if prev then
		local a = r.pulls[prev]
		local gdA, gdB = (a.gd or 0) / math.max(1, a.dur), (p.gd or 0) / math.max(1, p.dur)
		local _, avA = PullStats(a)
		local _, avB = PullStats(p)
		local change = gdA > 0 and (gdB / gdA - 1) or 0
		local first = ("Group damage per second %s %s"):format(change >= 0 and "rose" or "fell", Pct(math.abs(change) * 100, 100))
		if avA > 0 or avB > 0 then first = first .. ("; avoidable damage went from %s to %s."):format(Short(avA), Short(avB)) else first = first .. "." end
		local second = ("You: %s then %s dps."):format(Short(a.my or 0), Short(p.my or 0))
		if p.nb then second = second .. (" A new best on %s."):format(p.boss) end
		if a.top and a.top == p.top then
			local lead = r.players[a.top]
			second = second .. (lead and lead.me and "  You led both attempts." or ("  %s led both attempts."):format(Name(a.top)))
		end
		pg.foot:Set(a.kill == false and p.kill ~= false and "From wipe to kill" or ("From attempt %d to %d"):format(nth - 1, nth), first, second)
	else
		local first = ("Group %s dps over %s.  Deaths: %d."):format(Short((p.gd or 0) / math.max(1, p.dur)), Clock(p.dur), p.k or 0)
		local second = me and ("You: %s dps, %s."):format(Short(p.my or 0), Place(p.rank or 1)) or ""
		if best then second = second .. ("  Your record on %s: %s dps%s."):format(p.boss, Short(best), p.nb and ", set here" or "") end
		pg.foot:Set(p.kill == false and "The wipe" or "The kill", first, second)
	end
end

---------------------------------------------------------------------------
-- Page: Players

local function BuildPlayers(pg)
	local lx, lw = 40, 470
	Heading(pg, lx, 222, "Players")
	pg.list = List(pg, lx, 280, lw, 52, 5, function(row)
		row:SetHeight(42)
		row.stud = Stud(row, 34)
		row.stud:SetPoint("LEFT", 0, 0)
		row.rail = Rail(row, lw - 42, 42)
		row.rail:SetPoint("LEFT", 42, 0)
		row.name = Label(row.rail, 22)
		row.name:SetPoint("LEFT", 28, 1)
		row.name:SetWidth(lw - 42 - 28 - 140)
		row.total = Label(row.rail, 21, L.CREAM, "RIGHT")
		row.total:SetPoint("RIGHT", -28, 1)
		row:SetScript("OnClick", function(self)
			chosen.player = self.item.n
			R.Refresh()
		end)
	end)
	pg.chartTitle = Heading(pg, lx, 600, "")
	pg.chart = Chart(pg, lx, 650, lw, 110)

	local rx = 560
	local rw = W - 70 - rx
	pg.who = At(Title(pg, 30), pg, rx, 222)
	pg.what = Label(pg, 19)
	pg.what:SetPoint("LEFT", pg.who, "RIGHT", 24, -1)
	pg.whatRoom = rw
	pg.tabs = {}
	local x = rx
	for i, t in ipairs(TALLIES) do
		local b = Word(pg, t.label, 21, function()
			chosen.tally = t.key
			pg.list2.offset = 0
			R.Refresh()
		end)
		b.key = t.key
		b:SetPoint("LEFT", pg, "TOPLEFT", x, -290)
		x = x + b:GetWidth() + 6
		pg.tabs[i] = b
	end
	pg.cols = Columns(pg, 336, { { "total", rx + rw - 300, "RIGHT" }, { "share", rx + rw - 190, "RIGHT" }, { "pulls", rx + rw - 20, "RIGHT" } })
	pg.list2 = List(pg, rx, 360, rw, 50, 8, function(row)
		row:SetHeight(46)
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(40, 40)
		row.icon:SetPoint("LEFT", 0, 0)
		row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		row.rail = Rail(row, rw - 52, 44)
		row.rail:SetPoint("LEFT", 52, 0)
		row.name = Label(row.rail, 21)
		row.name:SetPoint("LEFT", 28, 1)
		row.total = At(Label(row.rail, 21, L.CREAM, "RIGHT"), row, rw - 300, 23, "RIGHT")
		row.share = At(Label(row.rail, 21, L.CREAM, "RIGHT"), row, rw - 190, 23, "RIGHT")
		row.pulls = At(Label(row.rail, 21, L.CREAM, "RIGHT"), row, rw - 20, 23, "RIGHT")
		row.name:SetPoint("RIGHT", row.total, "LEFT", -12, 0)
		row:SetScript("OnClick", function(self)
			local recap = self.item and self.item.recap
			if recap and OpenDeathRecapUI then
				if not pcall(OpenDeathRecapUI, recap) then ns.Print("the game no longer has that recap: it keeps the latest deaths only.") end
			end
		end)
	end)
	pg.none = Notice(pg, rx, 390, rw)
	pg.foot = Foot(pg)
end

local function DrawPlayers(pg, r)
	local list = Players(r)
	local who = chosen.player and r.players[chosen.player]
	if not who then who = Me(r) or list[1] end
	chosen.player = who and who.n
	local top = list[1] and (list[1].d or 0) or 0
	FillList(pg.list, list, function(row, p)
		local sel = p == who
		row.stud:Dress(sel and 2 or 0)
		row.rail:Dress(sel and 2 or 0)
		local cr, cg, cb = L.ClassColor(p.c)
		row.rail:Fill(top > 0 and (p.d or 0) / top or 0, cr, cg, cb, (row.rail:GetWidth() - 40) * 0.55)
		row.name:SetText(Name(p.n))
		SetColor(row.name, p.me and L.GOLD or L.CREAM)
		row.total:SetText(Short(p.d or 0))
	end)
	if not who then
		pg.who:SetText("")
		pg.what:SetText("")
		return
	end
	pg.chartTitle:SetText(who.me and "Your DPS, pull by pull" or ("%s's DPS, pull by pull"):format(Name(who.n)))
	local items, peak = {}, 0
	for i, p in ipairs(r.pulls) do
		local v = p.dp and p.dp[who.n] or 0
		items[i] = { v = v, color = PullColor(p), pull = i }
		peak = math.max(peak, v)
	end
	pg.chart:Draw(items, peak * 1.1, function(item)
		chosen.pull = item.pull
		GoPage("pulls")
	end)

	local cr, cg, cb = L.ClassColor(who.c)
	pg.who:SetText(Name(who.n))
	pg.who:SetTextColor(cr, cg, cb)
	local class = who.c and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[who.c] or who.c or ""
	local deaths = who.k or 0
	pg.what:SetText(("%s  ·  %s damage  ·  %s dps  ·  %d interrupts  ·  %s"):format(
		class, Short(who.d), Short(Dps(who)), who.i or 0, deaths == 0 and "never died" or ("died " .. deaths)))
	pg.what:SetWidth(math.max(100, pg.whatRoom - (pg.who:GetStringWidth() or 0) - 24))
	for _, b in ipairs(pg.tabs) do b:SetChosen(b.key == chosen.tally) end

	local tally
	for _, t in ipairs(TALLIES) do
		if t.key == chosen.tally then tally = t end
	end
	local rows = {}
	local whole = 0
	if tally.key == "deaths" then
		for _, d in ipairs(r.deaths) do
			if d.n == who.n then
				local p = r.pulls[d.pull]
				rows[#rows + 1] = {
					icon = d.by and SpellIcon(d.by) or DEATH_ICON,
					name = ("%s, at %s%s"):format(p and PullName(p) or "?", Clock(d.at), d.by and (": " .. SpellName(d.by, d) .. (d.from and ("  |cffa8a296" .. d.from .. "|r") or "")) or ""),
					total = d.o and d.o > 0 and (Short(d.o) .. " over") or "", recap = d.recap,
				}
			end
		end
	else
		local spells = Spells(who, tally.key)
		whole = who[tally.key] or 0
		if r.old then
			-- Begun before the report: abilities only from the later pulls, so shares are of those.
			whole = 0
			for _, x in ipairs(spells) do whole = whole + x.v end
		end
		for _, s in ipairs(spells) do
			local name = SpellName(s.id, s)
			if s.from and (tally.key == "t" or tally.key == "a") then name = name .. "  |cffa8a296" .. s.from .. "|r" end
			if s.dl then name = name .. ("  |cffff5040killing blow%s|r"):format(s.dl > 1 and (" x" .. s.dl) or "") end
			if s.av and tally.key ~= "a" then name = name .. "  |cffffb040avoidable|r" end
			rows[#rows + 1] = { icon = SpellIcon(s.id), name = name, v = s.v, n = s.n, count = tally.count }
		end
	end
	for _, c in ipairs(pg.cols) do c:SetShown(tally.key ~= "deaths") end
	local first = rows[1] and rows[1].v or 0
	FillList(pg.list2, rows, function(row, item)
		row.icon:SetTexture(item.icon)
		row.name:SetText(item.name)
		if item.v then
			row.rail:Fill(first > 0 and item.v / first or 0, cr, cg, cb, (row.rail:GetWidth() - 40) * 0.5)
			row.total:SetText(item.count and tostring(item.v) or Short(item.v))
			row.share:SetText(Pct(item.v, whole))
			row.pulls:SetText(item.n or "")
		else
			row.rail:Fill(0)
			row.total:SetText(item.total or "")
			row.share:SetText("")
			row.pulls:SetText("")
		end
	end)
	if #rows == 0 then
		pg.none:SetText(r.old and "Abilities weren't kept: this run began before the run report was installed."
			or tally.key == "deaths" and (Name(who.n) .. " never died.") or "Nothing recorded.")
		pg.none:Show()
	else
		pg.none:Hide()
	end

	-- Their run in two lines.
	local bestPull, bestV, weak, weakV
	for _, p in ipairs(r.pulls) do
		local v = p.dp and p.dp[who.n]
		if v and v > 0 then
			if not bestV or v > bestV then bestPull, bestV = p, v end
			if p.boss and (not weakV or v < weakV) then weak, weakV = p, v end
		end
	end
	local a = bestPull and ("Best pull: %s, %s dps."):format(PullName(bestPull), Short(bestV)) or ""
	if weak and weak ~= bestPull then
		a = a .. ("  Weakest boss: %s%s, %s dps."):format(weak.boss, weak.kill == false and " (wipe)" or "", Short(weakV))
	end
	local where = {}
	for _, d in ipairs(r.deaths) do
		if d.n == who.n and r.pulls[d.pull] then where[#where + 1] = PullName(r.pulls[d.pull]) end
	end
	local b = deaths == 0 and "Never died." or ("Deaths: %d%s."):format(deaths, #where > 0 and (" (" .. table.concat(where, ", ") .. ")") or "")
	local rankA, count = 1, 0
	for _, p in ipairs(list) do
		if (p.a or 0) > 0 then
			count = count + 1
			if (p.a or 0) > (who.a or 0) then rankA = rankA + 1 end
		end
	end
	if (who.a or 0) > 0 and count > 1 then
		b = b .. ("  Avoidable damage taken: %s, the %s most of the group."):format(Short(who.a), rankA == 1 and "" or (Place(rankA) .. ""))
		b = b:gsub("the  most", "the most")
	end
	pg.foot:Set(who.me and "Your run" or (Name(who.n) .. "'s run"), a, b)
end

---------------------------------------------------------------------------
-- Page: Dangers

local function BuildDangers(pg)
	local lx, lw = 40, 640
	Heading(pg, lx, 222, "Deaths", "in order; click one for the game's recap")
	local cols = { { "pull", lx + 10, "LEFT" }, { "at", lx + 260, "RIGHT" }, { "who", lx + 290, "LEFT" }, { "killing blow", lx + 410, "LEFT" }, { "overkill", lx + lw - 10, "RIGHT" } }
	Columns(pg, 270, cols)
	pg.deaths = List(pg, lx, 290, lw, 40, 5, function(row)
		Marks(row)
		row.dx = lx
		row.dot = Stud(row, 12)
		row.dot:SetPoint("RIGHT", row, "LEFT", -8, 0)
		row.cells = Cells(row, cols, 20)
		row.cells[4]:SetWidth(lw - 410 - 90)
		row.cells[1]:SetWidth(230)
		row:SetScript("OnClick", function(self)
			local recap = self.item and self.item.recap
			if recap and OpenDeathRecapUI then
				if not pcall(OpenDeathRecapUI, recap) then ns.Print("the game no longer has that recap: it keeps the latest deaths only.") end
			elseif self.item then
				ns.Print("no recap for that death: the game keeps them for recent deaths only.")
			end
		end)
	end)
	pg.noDeaths = Notice(pg, lx + 10, 310, lw - 20)

	Heading(pg, lx, 540, "Interrupts and dispels")
	local icols = { { "int", lx + 200, "RIGHT" }, { "disp", lx + 260, "RIGHT" }, { "with", lx + 290, "LEFT" } }
	Columns(pg, 586, icols)
	pg.ints = List(pg, lx, 600, lw, 30, 5, function(row)
		row.dx = lx
		row.name = At(Label(row, 20), row, 10, 14)
		row.name:SetWidth(170)
		row.cells = Cells(row, icols, 20)
		row.cells[3]:SetWidth(lw - 290)
		SetColor(row.cells[3], GREY)
	end)

	local rx = 730
	local rw = W - 70 - rx
	pg.rx, pg.rw = rx, rw
	pg.avoidHead = Heading(pg, rx, 222, "Avoidable damage", "what hit whom")
	pg.heads = {}
	pg.cellW = 92
	for j = 1, 5 do
		pg.heads[j] = At(Label(pg, 17, L.CREAM, "CENTER"), pg, rx + rw - pg.cellW * (5 - j) - pg.cellW / 2, 270, "CENTER")
	end
	pg.grid = {}
	for i = 1, 5 do
		local y = 304 + (i - 1) * 46
		local g = { icon = pg:CreateTexture(nil, "ARTWORK"), name = At(Label(pg, 20), pg, rx + 48, y + 18), cells = {} }
		g.icon:SetSize(36, 36)
		g.icon:SetPoint("TOPLEFT", pg, "TOPLEFT", rx, -y)
		g.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		g.name:SetWidth(rw - 48 - pg.cellW * 5 - 8)
		for j = 1, 5 do
			local x = rx + rw - pg.cellW * (6 - j) + 4
			local back = pg:CreateTexture(nil, "BACKGROUND", nil, 1)
			back:SetPoint("TOPLEFT", pg, "TOPLEFT", x, -y)
			back:SetSize(pg.cellW - 8, 36)
			local text = At(Label(pg, 19, L.CREAM, "CENTER"), pg, x + (pg.cellW - 8) / 2, y + 18, "CENTER")
			g.cells[j] = { back = back, text = text }
		end
		pg.grid[i] = g
	end
	pg.noAvoid = Notice(pg, rx, 320, rw)
	pg.avoidTotals = At(Label(pg, 20, GREY), pg, rx, 304 + 5 * 46 + 20)
	pg.avoidTotals:SetWidth(rw)
	Heading(pg, rx, 640, "What hurt most", "all damage taken, by ability")
	pg.hurt = At(Label(pg, 20), pg, rx, 692)
	pg.hurt:SetWidth(rw)
	pg.hurt2 = At(Label(pg, 20, GREY), pg, rx, 724)
	pg.hurt2:SetWidth(rw)
	pg.foot = Foot(pg)
end

local function SpellsLine(list, limit, count)
	local parts = {}
	for i = 1, math.min(limit, #list) do
		parts[i] = ("%s %s"):format(SpellName(list[i].id, list[i]), count and tostring(list[i].v) or Short(list[i].v))
	end
	return table.concat(parts, ", ")
end

local function DrawDangers(pg, r)
	local deaths = r.deaths
	pg.noDeaths:SetText(#deaths == 0 and (r.old and "Death times and killing blows weren't kept: this run began before the run report was installed." or "Nobody died. Well played.") or "")
	FillList(pg.deaths, deaths, function(row, d, i)
		local p = r.pulls[d.pull]
		local c = row.cells
		c[1]:SetText(p and PullName(p) or "?")
		SetColor(c[1], p and p.boss and (p.kill == false and EMBER or L.GOLD) or L.CREAM)
		c[2]:SetText(Clock(d.at))
		c[3]:SetText(Name(d.n))
		c[3]:SetTextColor(L.ClassColor(d.c))
		c[4]:SetText(d.by and SpellName(d.by, d) or "")
		c[5]:SetText(d.o and d.o > 0 and Short(d.o) or "")
		row.dot:Dress(2)
		row.dot:SetVertexColor(1, 0.22, 0.16)
		row.stripe:SetShown(i % 2 == 1)
		row.pick:Hide()
	end)

	local folk = Players(r)
	local ints = {}
	for _, p in ipairs(folk) do ints[#ints + 1] = p end
	table.sort(ints, function(a, b) return ((a.i or 0) + (a.x or 0)) > ((b.i or 0) + (b.x or 0)) end)
	FillList(pg.ints, ints, function(row, p)
		row.name:SetText(Name(p.n))
		if p.me then SetColor(row.name, L.GOLD) else row.name:SetTextColor(L.ClassColor(p.c)) end
		row.cells[1]:SetText(p.i or 0)
		row.cells[2]:SetText(p.x or 0)
		local i, x = SpellsLine(Spells(p, "i"), 2, true), SpellsLine(Spells(p, "x"), 2, true)
		row.cells[3]:SetText(i .. ((i ~= "" and x ~= "") and ";  " or "") .. x)
	end)

	-- Avoidable damage: the five abilities that did most, against the five who took most.
	local takers = {}
	for _, p in ipairs(folk) do
		if (p.a or 0) > 0 then takers[#takers + 1] = p end
	end
	table.sort(takers, function(a, b) return (a.a or 0) > (b.a or 0) end)
	local shown = {}
	for j = 1, math.min(5, #takers) do shown[j] = takers[j] end
	-- Back in run order so the columns don't jump about from run to run.
	local spells = AllSpells(r, "a")
	local peak = 0
	for i = 1, math.min(5, #spells) do
		for _, p in ipairs(shown) do peak = math.max(peak, spells[i].by[p.n] or 0) end
	end
	local n = #shown
	for j, head in ipairs(pg.heads) do
		local p = shown[j - (5 - n)]
		head:SetText(p and Name(p.n) or "")
		if p then
			if p.me then SetColor(head, L.GOLD) else head:SetTextColor(L.ClassColor(p.c)) end
		end
	end
	for i, g in ipairs(pg.grid) do
		local s = spells[i]
		g.icon:SetShown(s ~= nil)
		g.name:SetText(s and SpellName(s.id, s) or "")
		if s then g.icon:SetTexture(SpellIcon(s.id)) end
		for j, cell in ipairs(g.cells) do
			local p = s and shown[j - (5 - n)]
			if p then
				local v = s.by[p.n] or 0
				local a = peak > 0 and math.min(1, v / peak) or 0
				cell.back:SetColorTexture(0.24 + 0.63 * a, 0.12 + 0.12 * a, 0.08, 0.24 + 0.66 * a)
				cell.back:Show()
				cell.text:SetText(v > 0 and Short(v) or "-")
			else
				cell.back:Hide()
				cell.text:SetText("")
			end
		end
	end
	pg.noAvoid:SetText(#spells == 0 and (r.old and "Abilities weren't kept: this run began before the run report was installed." or "Nothing the game marks as avoidable hit anyone.") or "")
	local totals = {}
	for _, p in ipairs(takers) do totals[#totals + 1] = ("%s %s"):format(Name(p.n), Short(p.a)) end
	pg.avoidTotals:SetText(#totals > 0 and ("Totals:  " .. table.concat(totals, "  ·  ")) or "")

	local hurt = AllSpells(r, "t")
	pg.hurt:SetText(#hurt > 0 and SpellsLine(hurt, 4):gsub(", ", "  ·  ") or (r.old and "Not kept for this run." or ""))
	local taken, most = 0, nil
	for _, p in ipairs(folk) do
		taken = taken + (p.t or 0)
		if not most or (p.t or 0) > (most.t or 0) then most = p end
	end
	pg.hurt2:SetText(most and taken > 0 and ("%s took %s of all the damage taken."):format(Name(most.n), Pct(most.t, taken)) or "")

	-- Lessons.
	local inWipes, wipeBoss = 0, nil
	for _, d in ipairs(deaths) do
		local p = r.pulls[d.pull]
		if p and p.boss and p.kill == false then
			inWipes = inWipes + 1
			wipeBoss = wipeBoss or p.boss
		end
	end
	local total = 0
	for _, p in ipairs(folk) do total = total + (p.k or 0) end
	local a = total == 0 and "No deaths." or ("%d death%s"):format(total, total == 1 and "" or "s")
	if total > 0 then
		if inWipes == 0 then
			a = a .. "."
		elseif inWipes == total then
			a = a .. (total == 1 and ", in the %s wipe." or ", all of them in the %s wipe."):format(wipeBoss)
		else
			a = a .. (", %d of them in the %s wipe."):format(inWipes, wipeBoss)
		end
	end
	if spells[1] then
		local s = spells[1]
		local whom, v = nil, 0
		for nm, x in pairs(s.by) do
			if x > v then whom, v = nm, x end
		end
		local all = 0
		for _, e in ipairs(spells) do all = all + e.v end
		a = a .. ("  %s was %s of the avoidable damage; %s took %s of it."):format(SpellName(s.id, s), Pct(s.v, all), Name(whom), Short(v))
	end
	local me = Me(r)
	local intsAll = 0
	for _, p in ipairs(folk) do intsAll = intsAll + (p.i or 0) end
	local b = ""
	if me and intsAll > 0 then
		b = ("%d of the %d interrupts were yours."):format(me.i or 0, intsAll)
	end
	pg.foot:Set("Lessons", a, b)
end

---------------------------------------------------------------------------
-- Page: Past runs

local PAST_COLS = {
	{ "date", 10, "LEFT" }, { "where", 200, "LEFT" }, { "time", 570, "RIGHT" }, { "bosses", 660, "RIGHT" },
	{ "wipes", 740, "RIGHT" }, { "deaths", 830, "RIGHT" }, { "your dps", 950, "RIGHT" }, { "place", 1030, "RIGHT" },
	{ "group", 1070, "LEFT" },
}

local function RunPlace(r)
	local list = Players(r)
	for i, p in ipairs(list) do
		if p.me then return i, Dps(p) end
	end
	return nil, 0
end

local function RunDeaths(r)
	local n = 0
	for _, n2 in ipairs(r.order) do n = n + (r.players[n2].k or 0) end
	return n
end

local function BuildPast(pg)
	local x0, x1 = 50, W - 70
	Heading(pg, x0, 222, "Past runs")
	pg.here = Word(pg, "This dungeon", 21, function() chosen.scope = "here" R.Refresh() end)
	pg.here:SetPoint("LEFT", pg, "TOPLEFT", x0 + 230, -238)
	pg.all = Word(pg, "Every dungeon and raid", 21, function() chosen.scope = "all" R.Refresh() end)
	pg.all:SetPoint("LEFT", pg.here, "RIGHT", 10, 0)
	local cols = {}
	for i, c in ipairs(PAST_COLS) do cols[i] = { c[1], x0 + c[2], c[3] } end
	Columns(pg, 290, cols)
	pg.list = List(pg, x0, 306, x1 - x0, 40, 6, function(row)
		Marks(row)
		row.dx = x0
		row.cells = Cells(row, cols)
		row.cells[2]:SetWidth(300)
		row.cells[9]:SetWidth(x1 - x0 - 1080)
		SetColor(row.cells[9], GREY)
		row:SetScript("OnClick", function(self) R.Show(self.item) end)
		Tip(row, function(self) return self.item.name end, "Click to open this run's report.")
	end)
	pg.note = At(Label(pg, 19, GREY), pg, x0 + 10, 306 + 6 * 40 + 18)
	pg.note:SetWidth(x1 - x0 - 20)
	Heading(pg, x0, 600, "Your bests here", "damage per second on each boss: your record against this run")
	pg.legend = At(Label(pg, 17, GREY, "RIGHT"), pg, x1, 600, "RIGHT")
	pg.legend:SetText("dark: your record    light: this run")
	pg.bars = {}
	for i = 1, 8 do
		local b = {
			rec = pg:CreateTexture(nil, "ARTWORK"),
			now = pg:CreateTexture(nil, "ARTWORK"),
			name = Label(pg, 19, L.CREAM, "CENTER"),
			vals = Label(pg, 17, GREY, "CENTER"),
		}
		b.rec:SetColorTexture(0.43, 0.36, 0.27, 0.9)
		pg.bars[i] = b
	end
	pg.noBests = Notice(pg, x0, 680, W - 140)
	pg.foot = Foot(pg)
end

local function DrawPast(pg, r)
	pg.here:SetChosen(chosen.scope == "here")
	pg.all:SetChosen(chosen.scope == "all")
	local all = Runs()
	local list = {}
	for i = #all, 1, -1 do
		local x = all[i]
		if chosen.scope == "all" or x.name == r.name then list[#list + 1] = x end
	end
	-- The records among runs here: the fastest done run with every boss this one killed, your best dps.
	local fastest, bestDps
	for _, x in ipairs(list) do
		if x.name == r.name and (#x.pulls > 0) then
			local _, dps = RunPlace(x)
			if x.done or x == r then
				if Kills(x) >= Kills(r) and (not fastest or Length(x) < Length(fastest)) then fastest = x end
			end
			if dps > 0 and (not bestDps or dps > bestDps) then bestDps = dps end
		end
	end
	FillList(pg.list, list, function(row, x)
		local c = row.cells
		local place, dps = RunPlace(x)
		c[1]:SetText(date and date("%a %d %b %H:%M", x.t0 or 0) or "")
		c[2]:SetText(x.name or "")
		c[3]:SetText(Clock(Length(x)))
		SetColor(c[3], x == fastest and L.GOLD or L.CREAM)
		c[4]:SetText(Kills(x))
		c[5]:SetText(Wipes(x))
		c[6]:SetText(RunDeaths(x))
		c[7]:SetText(Short(dps))
		SetColor(c[7], x.name == r.name and dps > 0 and dps == bestDps and L.GOLD or L.CREAM)
		c[8]:SetText(place and #x.order > 1 and Place(place) or "")
		local names = {}
		for _, n in ipairs(x.order) do
			if not x.players[n].me then names[#names + 1] = Name(n) end
		end
		c[9]:SetText(table.concat(names, ", "))
		row.pick:SetShown(x == r)
		row.stripe:SetShown(false)
	end)
	pg.note:SetText(("Gold: the record here.  Click a run to open its report.  The newest %d runs are kept."):format(
		math.max(1, math.min(50, tonumber(Opt().runsKeep) or 20))))

	-- Your record on each boss this run killed, against what you did here.
	local bests = Bests()
	local kills, seen = {}, {}
	for i = #r.pulls, 1, -1 do
		local p = r.pulls[i]
		if p.boss and p.kill ~= false and not seen[p.boss] then
			seen[p.boss] = true
			table.insert(kills, 1, p)
		end
	end
	local x0, x1 = 50, W - 70
	local n = math.min(#pg.bars, #kills)
	local slot = (x1 - x0) / math.max(1, n)
	local hmax = 110
	local peak = 0
	for i = 1, n do
		local rec = bests["boss:" .. kills[i].boss]
		peak = math.max(peak, kills[i].my or 0, rec and rec.dps or 0)
	end
	for i, b in ipairs(pg.bars) do
		local p = kills[i]
		if i > n or not p then
			b.rec:Hide() b.now:Hide() b.name:Hide() b.vals:Hide()
		else
			local rec = bests["boss:" .. p.boss]
			local recV, nowV = rec and rec.dps or (p.my or 0), p.my or 0
			local cx = x0 + (i - 1) * slot + slot / 2
			local base = 600 + 160
			local hr, hn = math.max(2, recV / peak * hmax), math.max(2, nowV / peak * hmax)
			b.rec:ClearAllPoints()
			b.rec:SetPoint("BOTTOMLEFT", pg, "TOPLEFT", cx - 34, -base)
			b.rec:SetSize(30, hr)
			b.now:ClearAllPoints()
			b.now:SetPoint("BOTTOMLEFT", pg, "TOPLEFT", cx + 4, -base)
			b.now:SetSize(30, hn)
			local top = nowV >= recV * 0.995
			b.now:SetColorTexture(top and L.GOLD[1] or 0.67, top and L.GOLD[2] or 0.55, top and L.GOLD[3] or 0.35, 0.92)
			At(b.name, pg, cx, base + 24, "CENTER")
			b.name:SetText((p.boss:gsub("^Captain ", "Capt. "):gsub("^Edwin ", "")))
			b.name:SetWidth(slot - 10)
			At(b.vals, pg, cx, base - math.max(hr, hn) - 16, "CENTER")
			b.vals:SetText(("%s / %s"):format(Short(nowV), Short(recV)))
			SetColor(b.vals, top and L.GOLD or GREY)
			b.rec:Show() b.now:Show() b.name:Show() b.vals:Show()
		end
	end
	pg.noBests:SetText(n == 0 and "No boss kills in this run." or "")

	-- This run against the others here.
	local same, fasterThan = 0, 0
	local deathsAll = 0
	for _, x in ipairs(all) do
		if x.name == r.name and #x.pulls > 0 then
			same = same + 1
			deathsAll = deathsAll + RunDeaths(x)
			if x ~= r and Kills(x) >= Kills(r) and Length(x) < Length(r) then fasterThan = fasterThan + 1 end
		end
	end
	local _, myDps = RunPlace(r)
	local a
	if same <= 1 then
		a = ("Your first saved run of %s."):format(r.name)
	else
		a = ("%s fastest of your %d runs of %s%s."):format(ORDINAL[fasterThan + 1] or Place(fasterThan + 1), same, r.name,
			fastest and fastest ~= r and (" (record " .. Clock(Length(fastest)) .. ")") or "")
	end
	if myDps > 0 then
		a = a .. ("  Your damage per second here: %s%s."):format(Short(myDps), bestDps and myDps < bestDps and (" (best " .. Short(bestDps) .. ")") or (same > 1 and ", your best" or ""))
	end
	local records = 0
	for _, p in ipairs(r.pulls) do
		if p.nb then records = records + 1 end
	end
	local b = records > 0 and (("%d boss record%s set."):format(records, records == 1 and "" or "s")) or "No boss records this time."
	if same > 1 then b = b .. ("  Deaths: %d (the average here is %.1f)."):format(RunDeaths(r), deathsAll / same) end
	pg.foot:Set("This run against the others", a, b)
end

---------------------------------------------------------------------------
-- The window

local BUILD = { summary = BuildSummary, pulls = BuildPulls, bosses = BuildBosses, players = BuildPlayers, dangers = BuildDangers, past = BuildPast }
local DRAW = { summary = DrawSummary, pulls = DrawPulls, bosses = DrawBosses, players = DrawPlayers, dangers = DrawDangers, past = DrawPast }

-- The header and tabs: the Run Report's own atlas, else the journal's (a new file needs a
-- client restart) with the bag window's header.
local function HeaderArt()
	if ns.Art.Require("runReport") then return "runReport", "runReport" end
	ns.Art.Require("journal")
	return "bagFrame", ns.Art.Path("journal") and "journal" or nil
end

local function Piece(parent, slot, x0, y0, x1, y1, layer, sub)
	local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sub)
	if ns.Art.Apply(t, slot) then
		t:SetTexCoord(x0 / ATLAS, x1 / ATLAS, y0 / ATLAS, y1 / ATLAS)
	else
		t:SetColorTexture(0.06, 0.05, 0.04, 1)
	end
	return t
end

-- D3's window header across width: its ends, the stained glass between (every other pane
-- mirrored), the medallion in the middle. Returns the medallion.
function R.LayHeader(head, width, slot)
	local hl = Piece(head, slot, 0, 0, 50, 155)
	hl:SetPoint("TOPLEFT")
	hl:SetSize(50, HEAD_H)
	local hr = Piece(head, slot, 550, 0, 600, 155)
	hr:SetPoint("TOPRIGHT")
	hr:SetSize(50, HEAD_H)
	local x, i = 50, 0
	while x < width - 50 do
		local w = math.min(180, width - 50 - x)
		local t = Piece(head, slot, 50, 0, 50 + w, 155, "ARTWORK", -1)
		if i % 2 == 1 then t:SetTexCoord(230 / ATLAS, (230 - w) / ATLAS, 0, 155 / ATLAS) end
		t:SetPoint("TOPLEFT", x, 0)
		t:SetSize(w, HEAD_H)
		x, i = x + 180, i + 1
	end
	local medal = Piece(head, slot, 232, 0, 368, 155, "ARTWORK", 1)
	medal:SetPoint("TOP", 0, 0)
	medal:SetSize(136, HEAD_H)
	return medal
end

-- Step a title's size down until it fits its room.
local function FitTitle(fs, size, room, least)
	fs:SetFont(L.TitleFont(), size, "")
	while size > (least or 20) and (fs:GetStringWidth() or 0) > room do
		size = size - 2
		fs:SetFont(L.TitleFont(), size, "")
	end
end

local function TabCoord(index, state)
	local i = index * 3 + state
	local x, y = (i % 16) * 64, 800 + math.floor(i / 16) * 96
	return x / ATLAS, (x + 64) / ATLAS, y / ATLAS, (y + 96) / ATLAS
end

local function SavePosition()
	local opt = Opt()
	local point, _, _, x, y = frame:GetPoint(1)
	opt.runPos = { point = point or "CENTER", x = x or 0, y = y or 0, moved = true }
end

local function Build()
	L = ns.Meter.Lib
	ns.Art.Require("targetStyleParts") -- the rails and studs (lazy: the meter may not have loaded them)
	frame = CreateFrame("Frame", "SanctuaryUIRunReport", UIParent)
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetSize(W * HALF, H * HALF)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:Hide()
	tinsert(UISpecialFrames, "SanctuaryUIRunReport") -- Escape closes it
	frame:SetScript("OnHide", function()
		if sample then sample = nil end
	end)

	canvas = CreateFrame("Frame", nil, frame)
	canvas:SetScale(HALF)
	canvas:SetPoint("TOPLEFT")
	canvas:SetSize(W, H)

	-- The edge, a bronze line, the bag window's dark body tiled to the window.
	local edge = canvas:CreateTexture(nil, "BACKGROUND", nil, -8)
	edge:SetPoint("TOPLEFT", 0, -10)
	edge:SetPoint("BOTTOMRIGHT")
	edge:SetColorTexture(0.03, 0.027, 0.023, 1)
	local line = canvas:CreateTexture(nil, "BACKGROUND", nil, -7)
	line:SetPoint("TOPLEFT", 3, -13)
	line:SetPoint("BOTTOMRIGHT", -3, 3)
	line:SetColorTexture(LINE[1], LINE[2], LINE[3], 1)
	local TW, TH = 560, 270
	local bodyH = FOOT_Y + 10 - 140
	for ty = 0, math.ceil(bodyH / TH) - 1 do
		for tx = 0, math.ceil((W - 24) / TW) - 1 do
			local w, h = math.min(TW, W - 24 - tx * TW), math.min(TH, bodyH - ty * TH)
			local t = canvas:CreateTexture(nil, "BACKGROUND", nil, -6)
			t:SetPoint("TOPLEFT", 12 + tx * TW, -(140 + ty * TH))
			t:SetSize(w, h)
			if ns.Art.Apply(t, "bagFrame") then
				local x0, x1, y0, y1 = 14, 14 + w, 170, 170 + h
				if tx % 2 == 1 then x0, x1 = 574, 574 - w end
				if ty % 2 == 1 then y0, y1 = 440, 440 - h end
				t:SetTexCoord(x0 / ATLAS, x1 / ATLAS, y0 / ATLAS, y1 / ATLAS)
			else
				t:SetColorTexture(0.05, 0.05, 0.05, 1)
			end
		end
	end
	-- The stone foot: the bag window's, its ends kept and its middle stretched.
	local footK = FOOT_H / 206
	local fl = Piece(canvas, "bagFrame", 6, 452, 126, 658, "BORDER")
	fl:SetPoint("BOTTOMLEFT")
	fl:SetSize(120 * footK, FOOT_H)
	local fr = Piece(canvas, "bagFrame", 474, 452, 594, 658, "BORDER")
	fr:SetPoint("BOTTOMRIGHT")
	fr:SetSize(120 * footK, FOOT_H)
	local fm = Piece(canvas, "bagFrame", 126, 452, 474, 658, "BORDER")
	fm:SetPoint("TOPLEFT", fl, "TOPRIGHT")
	fm:SetPoint("BOTTOMRIGHT", fr, "BOTTOMLEFT")

	-- The header: its ends, the stained glass between (every other pane mirrored), the medallion.
	local headSlot, tabSlot = HeaderArt()
	local head = CreateFrame("Frame", nil, canvas)
	head:SetPoint("TOPLEFT")
	head:SetSize(W, HEAD_H)
	head:SetFrameLevel(canvas:GetFrameLevel() + 4)
	head:EnableMouse(true)
	head:RegisterForDrag("LeftButton")
	head:SetScript("OnDragStart", function() frame:StartMoving() end)
	head:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		frame:SetUserPlaced(false)
		SavePosition()
	end)
	R.LayHeader(head, W, headSlot)
	frame.title = At(Title(head, 34), head, W / 2 - 110, 82, "RIGHT")
	frame.title:SetWidth(W / 2 - 200)
	frame.pageTitle = At(Title(head, 30, L.CREAM), head, W / 2 + 110, 82, "LEFT")
	frame.pageTitle:SetWidth(W / 2 - 200)
	local close = CreateFrame("Button", nil, head)
	close:SetSize(38, 38)
	close:SetPoint("TOPRIGHT", -10, -6)
	local glow = close:CreateTexture(nil, "HIGHLIGHT")
	glow:SetAllPoints()
	glow:SetColorTexture(1, 0.6, 0.3, 0.25)
	glow:SetBlendMode("ADD")
	close:SetScript("OnClick", function() frame:Hide() end)

	frame.sub = At(Label(canvas, 23, L.CREAM, "CENTER"), canvas, W / 2, 182, "CENTER")
	frame.sub:SetWidth(W - 120)

	-- The pages, each over the whole canvas, and their tabs down the right edge.
	frame.tabs = {}
	for k, def in ipairs(PAGES) do
		local pg = CreateFrame("Frame", nil, canvas)
		pg:SetAllPoints(canvas)
		pg:SetFrameLevel(canvas:GetFrameLevel() + 2)
		pg:Hide()
		BUILD[def.key](pg)
		pages[def.key] = pg

		local tab = CreateFrame("Button", nil, canvas)
		tab:SetSize(70, 105)
		tab:SetPoint("TOPLEFT", canvas, "TOPLEFT", W - 12, -(160 + (k - 1) * 100))
		tab:SetFrameLevel(canvas:GetFrameLevel() + 1)
		tab.art = tab:CreateTexture(nil, "ARTWORK")
		tab.art:SetAllPoints()
		tab.index = tabSlot == "runReport" and (k - 1) or def.journal
		if tabSlot then
			ns.Art.Apply(tab.art, tabSlot)
			tab.art:SetTexCoord(TabCoord(tab.index, 0))
		else
			tab.art:SetColorTexture(0.3, 0.05, 0.03, 1)
		end
		tab.slot = tabSlot
		tab.key = def.key
		tab:SetScript("OnClick", function() GoPage(def.key) end)
		tab:SetScript("OnEnter", function(self)
			self.over = true
			R.DressTabs()
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(def.label)
			GameTooltip:AddLine(def.tip, 1, 1, 1, true)
			GameTooltip:Show()
		end)
		tab:SetScript("OnLeave", function(self)
			self.over = nil
			R.DressTabs()
			GameTooltip_Hide()
		end)
		frame.tabs[k] = tab
	end
	frame.empty = At(Label(canvas, 24, GREY, "CENTER"), canvas, W / 2, 420, "CENTER")
	frame.empty:SetText("No runs yet. Saved fights in a dungeon or raid make one; Preview shows what it looks like.")
	frame.empty:SetWidth(W - 200)
	frame.preview = At(Label(canvas, 19, L.GOLD, "LEFT"), canvas, 40, FOOT_Y + 24, "LEFT")
end

function R.DressTabs()
	if not frame then return end
	for _, tab in ipairs(frame.tabs) do
		local state = tab.key == page and 2 or (tab.over and 1 or 0)
		if tab.slot then tab.art:SetTexCoord(TabCoord(tab.index, state)) end
		tab:SetFrameLevel(canvas:GetFrameLevel() + (state == 2 and 3 or 1))
	end
end

local function SubLine(r)
	local topped, fights = Topped(r)
	local kills, wipes = Kills(r), Wipes(r)
	local parts = {
		date and date("%a %d %b, %H:%M", r.t0 or 0) or "",
		("%s, %s of it fighting"):format(Clock(Length(r)), Clock(Fighting(r))) .. (Live(r) and " (still going)" or ""),
	}
	local bosses = kills == 1 and "1 boss" or (kills .. " bosses")
	parts[#parts + 1] = bosses .. (wipes > 0 and (", " .. wipes .. (wipes == 1 and " wipe" or " wipes")) or ", no wipes")
	if fights > 0 then
		parts[#parts + 1] = ("%d fight%s, you topped %d"):format(#r.pulls, #r.pulls == 1 and "" or "s", topped)
	else
		parts[#parts + 1] = ("%d fight%s"):format(#r.pulls, #r.pulls == 1 and "" or "s")
	end
	return table.concat(parts, "   ·   ")
end

function R.Refresh()
	if not frame or not frame:IsShown() then return end
	local r = run
	frame.empty:SetShown(r == nil)
	for _, def in ipairs(PAGES) do pages[def.key]:SetShown(r ~= nil and def.key == page) end
	R.DressTabs()
	frame.preview:SetText(sample and "Preview: made-up runs" or "")
	if not r then
		frame.title:SetText("Run report")
		frame.pageTitle:SetText("")
		frame.sub:SetText("")
		return
	end
	-- A long name ("Excavation Site: Wetlands") steps the title down until it fits beside the medallion.
	frame.title:SetText((r.name or "Run"):upper())
	FitTitle(frame.title, 34, W / 2 - 200)
	local label = page == "summary" and ((r.done or r.complete) and "Run complete" or "Run so far")
	for _, def in ipairs(PAGES) do
		if def.key == page and not label then label = def.label end
	end
	frame.pageTitle:SetText(label:upper())
	frame.sub:SetText(SubLine(r))
	local ok, err = pcall(DRAW[page], pages[page], r)
	if not ok then ns.Log("run report %s: %s", page, tostring(err)) end
end

local function Position()
	local opt = Opt()
	local scale = ns.Art.D3Scale(BASE_SCALE * (opt.runScale or 1))
	-- Never past the screen: the window and its tabs, against the screen in UIParent's units.
	local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
	local fw, fh = (W + 70) * HALF, H * HALF
	if sw and sh and sw > 0 and sh > 0 then
		scale = math.min(scale, sw * MOST_OF_SCREEN / fw, sh * MOST_OF_SCREEN / fh)
	end
	frame:SetScale(scale)
	frame:ClearAllPoints()
	local pos = opt.runPos
	if type(pos) == "table" and pos.moved then
		frame:SetPoint(pos.point or "CENTER", UIParent, pos.point or "CENTER", pos.x or 0, pos.y or 0)
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
	end
end

-- Open a run's report: a run record, a run id, or nil for the latest.
function R.Show(which)
	if not ns.Meter or not ns.Meter.Lib then return end
	if not frame then Build() end
	if type(which) ~= "table" then
		local list = Runs()
		which = which and ns.MeterHistory.RunById(which) or list[#list]
	end
	if which ~= run then
		chosen.pull, chosen.boss, chosen.player = nil, nil, nil
		for _, pg in pairs(pages) do
			for _, v in pairs(pg) do
				if type(v) == "table" and v.offset then v.offset = 0 end
			end
		end
	end
	run = which
	Position()
	frame:Show()
	R.Refresh()
end

function R.Open(which)
	sample = nil
	if frame and frame:IsShown() and run and run == which then return R.Refresh() end
	R.Show(which)
end

function R.Toggle()
	if frame and frame:IsShown() then frame:Hide() else R.Open() end
end

function R.IsOpen()
	return frame ~= nil and frame:IsShown()
end

-- A fight was just saved into a run: an open report on that run follows it.
function R.Changed(r)
	if frame and frame:IsShown() and not sample and run == r then R.Refresh() end
end

-- Options changed (scale): an open window takes them.
function R.Relayout()
	if frame and frame:IsShown() then Position() end
end

function R.ResetPosition()
	Opt().runPos = { moved = false }
	if frame then Position() end
end

---------------------------------------------------------------------------
-- The banner when a run ends: D3's "Rift complete" moment. The report's own header (the run's
-- name, the crossed swords, RUN COMPLETE) over a strip of its stone with the run in a line and
-- Report / Dismiss, at the top of the screen. It flashes gold and chimes as it comes, then the
-- medallion pulses until it is clicked or the next pull starts. Movable (unlock frames) and
-- sized by its own slider; Options > Damage meter > Fights.

local BANNER_W, BANNER_STONE = 1000, 132
local bannerHolder

local function BannerOpt()
	local opt = Opt()
	if type(opt.runBannerPos) ~= "table" then opt.runBannerPos = { moved = false, mx = 0, my = 0 } end
	return opt
end

local function BannerButton(parent, word, x, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(200, 56)
	b:SetPoint("TOP", parent, "TOP", x, -(HEAD_H + 66))
	Plate(b)
	b.text = L.Text(b, L.BodyFont(), 26, L.GOLD, "CENTER")
	b.text:SetPoint("CENTER", 0, 1)
	b.text:SetText(word)
	local glow = b:CreateTexture(nil, "HIGHLIGHT")
	glow:SetAllPoints()
	glow:SetColorTexture(1, 0.6, 0.3, 0.18)
	glow:SetBlendMode("ADD")
	b:SetScript("OnClick", onClick)
	return b
end

local function BuildBanner()
	L = L or ns.Meter.Lib
	ns.Art.Require("journal")
	-- The holder stays shown (and carries the mover); the banner inside it comes and goes.
	bannerHolder = CreateFrame("Frame", "SanctuaryUIRunBannerHolder", UIParent)
	bannerHolder:SetFrameStrata("HIGH")
	bannerHolder:SetSize(BANNER_W * HALF, (HEAD_H + BANNER_STONE) * HALF)
	banner = CreateFrame("Frame", "SanctuaryUIRunBanner", bannerHolder)
	banner:SetAllPoints()
	banner:Hide()
	local c = CreateFrame("Frame", nil, banner)
	c:SetScale(HALF)
	c:SetPoint("TOPLEFT")
	c:SetSize(BANNER_W, HEAD_H + BANNER_STONE)
	banner.canvas = c

	-- The stone, under the header: the report's foot, ends kept and middle stretched.
	local k = BANNER_STONE / 206
	local fl = Piece(c, "bagFrame", 6, 452, 126, 658, "BACKGROUND")
	fl:SetPoint("BOTTOMLEFT")
	fl:SetSize(120 * k, BANNER_STONE)
	local fr = Piece(c, "bagFrame", 474, 452, 594, 658, "BACKGROUND")
	fr:SetPoint("BOTTOMRIGHT")
	fr:SetSize(120 * k, BANNER_STONE)
	local fm = Piece(c, "bagFrame", 126, 452, 474, 658, "BACKGROUND")
	fm:SetPoint("TOPLEFT", fl, "TOPRIGHT")
	fm:SetPoint("BOTTOMRIGHT", fr, "BOTTOMLEFT")
	local head = CreateFrame("Frame", nil, c)
	head:SetPoint("TOPLEFT")
	head:SetSize(BANNER_W, HEAD_H)
	local medal = R.LayHeader(head, BANNER_W, (HeaderArt()))
	banner.name = At(Title(head, 32), head, BANNER_W / 2 - 100, 82, "RIGHT")
	banner.name:SetWidth(BANNER_W / 2 - 160)
	local done = At(Title(head, 30, L.CREAM), head, BANNER_W / 2 + 100, 82, "LEFT")
	done:SetWidth(BANNER_W / 2 - 160)
	done:SetText("RUN COMPLETE")
	banner.sub = At(Label(c, 25, L.CREAM, "CENTER"), c, BANNER_W / 2, HEAD_H + 34, "CENTER")
	banner.sub:SetWidth(BANNER_W - 120)

	-- Gold light: a flash over the whole banner as it comes, then a slow pulse on the medallion.
	local flash = head:CreateTexture(nil, "OVERLAY")
	flash:SetAllPoints(c)
	flash:SetColorTexture(1, 0.8, 0.4, 1)
	flash:SetBlendMode("ADD")
	flash:SetAlpha(0)
	banner.flashAnim = flash:CreateAnimationGroup()
	local f1 = banner.flashAnim:CreateAnimation("Alpha")
	f1:SetFromAlpha(0.7)
	f1:SetToAlpha(0)
	f1:SetDuration(1.1)
	-- Behind the medallion (which covers its middle), so the light rings it.
	local glow = head:CreateTexture(nil, "ARTWORK", nil, 0)
	glow:SetPoint("CENTER", medal, "CENTER", 0, -2)
	glow:SetSize(250, 250)
	if ns.Art.Apply(glow, "auraCorona") then glow:SetVertexColor(1, 0.7, 0.3, 1) else glow:SetColorTexture(1, 0.75, 0.35, 0.3) end
	glow:SetBlendMode("ADD")
	glow:SetAlpha(0)
	banner.pulse = glow:CreateAnimationGroup()
	banner.pulse:SetLooping("BOUNCE")
	local p1 = banner.pulse:CreateAnimation("Alpha")
	p1:SetFromAlpha(0.15)
	p1:SetToAlpha(0.85)
	p1:SetDuration(1.2)
	banner.inAnim = banner:CreateAnimationGroup()
	local a1 = banner.inAnim:CreateAnimation("Alpha")
	a1:SetFromAlpha(0)
	a1:SetToAlpha(1)
	a1:SetDuration(0.35)

	banner.open = BannerButton(c, "Report", -115, function()
		banner:Hide()
		if banner.sample then R.Preview() else R.Open(banner.run) end
	end)
	banner.dismiss = BannerButton(c, "Dismiss", 115, function() banner:Hide() end)
	-- The header's X (the window art's own) puts it away too.
	local close = CreateFrame("Button", nil, head)
	close:SetSize(38, 38)
	close:SetPoint("TOPRIGHT", -10, -6)
	local hot = close:CreateTexture(nil, "HIGHLIGHT")
	hot:SetAllPoints()
	hot:SetColorTexture(1, 0.6, 0.3, 0.25)
	hot:SetBlendMode("ADD")
	close:SetScript("OnClick", function() banner:Hide() end)
	banner:SetScript("OnHide", function(self) self.pulse:Stop() end)
	-- The next pull puts it away.
	banner:RegisterEvent("PLAYER_REGEN_DISABLED")
	banner:SetScript("OnEvent", function(self) if not self.held then self:Hide() end end)

	if ns.MakeMover then
		bannerHolder.mover = ns.MakeMover(bannerHolder, "Run complete", function() return BannerOpt().runBannerPos end,
			"Reset its position in /sanctuary > Damage meter > Fights.")
	end
end

-- Where the banner sits and how big: the top of the screen unless moved.
function R.PlaceBanner()
	if not bannerHolder then return end
	local opt = BannerOpt()
	bannerHolder:SetScale(ns.Art.D3Scale(BANNER_SCALE * (opt.runBannerScale or 1)))
	bannerHolder:ClearAllPoints()
	local pos = opt.runBannerPos
	if pos.moved and ns.MovedPoint then
		bannerHolder:SetPoint("CENTER", UIParent, "BOTTOMLEFT", ns.MovedPoint(bannerHolder, pos))
	else
		bannerHolder:SetPoint("TOP", UIParent, "TOP", 0, -90)
	end
end

function R.ResetBannerPosition()
	BannerOpt().runBannerPos = { moved = false, mx = 0, my = 0 }
	R.PlaceBanner()
end

local function ShowBanner(r, isSample, quiet)
	L = L or ns.Meter.Lib
	if not banner then BuildBanner() end
	banner.run, banner.sample = r, isSample
	banner.name:SetText((r.name or "Run"):upper())
	FitTitle(banner.name, 32, BANNER_W / 2 - 160)
	local topped, fights = Topped(r)
	local kills, wipes = Kills(r), Wipes(r)
	local parts = { Clock(Length(r)) }
	parts[#parts + 1] = (kills == 1 and "1 boss" or (kills .. " bosses")) .. (wipes == 0 and ", no wipes" or (wipes == 1 and ", 1 wipe" or (", " .. wipes .. " wipes")))
	if fights > 0 then parts[#parts + 1] = ("you topped %d of %d fights"):format(topped, fights) end
	local deaths = 0
	for _, n in ipairs(r.order) do deaths = deaths + (r.players[n].k or 0) end
	parts[#parts + 1] = deaths == 0 and "nobody died" or (deaths == 1 and "1 death" or (deaths .. " deaths"))
	banner.sub:SetText(table.concat(parts, "   ·   "))
	R.PlaceBanner()
	banner:Show()
	banner.inAnim:Stop()
	banner.inAnim:Play()
	banner.flashAnim:Stop()
	banner.flashAnim:Play()
	banner.pulse:Play()
	if not quiet and Opt().runSound ~= false and PlaySound then
		local kit = SOUNDKIT and (SOUNDKIT.UI_SCENARIO_ENDING or SOUNDKIT.UI_EPICLOOT_TOAST)
		if not (kit and pcall(PlaySound, kit, "SFX")) then pcall(PlaySound, 888, "SFX") end
	end
end

function R.Banner(r, isSample)
	if not r or #r.pulls == 0 then return end
	ShowBanner(r, isSample)
end

-- Frames unlocked (/sanctuary unlock): the banner shows, held, so it can be moved.
function R.UpdateMovers(unlocked)
	if not unlocked and not bannerHolder then return end
	if not bannerHolder then BuildBanner() end
	R.PlaceBanner()
	if bannerHolder.mover then bannerHolder.mover:SetShown(unlocked and true or false) end
	if unlocked then
		if not banner:IsShown() then
			local s = R.SampleRuns()
			ShowBanner(s.runs[#s.runs], true, true)
		end
		banner.held = true
	else
		banner.held = nil
		if banner.sample then banner:Hide() end
	end
end

-- MeterHistory: a run just ended (you left the instance, or entered another).
function R.RunEnded(id)
	local r = ns.MeterHistory.RunById(id)
	if r and #r.pulls > 0 then R.Banner(r) end
end

---------------------------------------------------------------------------
-- Preview: a made-up Deadmines run and four before it

local function Rand(seed)
	local s = seed
	return function(a, b)
		s = (s * 1103515245 + 12345) % 2147483648
		return a + (math.floor(s / 65536) % (b - a + 1))
	end
end

local SAMPLE_CLASS = { Thalric = "HUNTER", Forearms = "WARRIOR", Mirelle = "MAGE", Zinnia = "SHAMAN", Osgood = "PALADIN" }
local SAMPLE_SPELLS = {
	Thalric = { d = { { 75, 160000 }, { 3044, 98000 }, { 2643, 61000 }, { 1978, 42000 }, { 19434, 31000 }, { 6603, 20300 } } },
	Forearms = { d = { { 6603, 163500 }, { 7384, 75800 }, { 78, 55800 }, { 772, 43900 }, { 845, 30100 }, { 6343, 18800 }, { 34428, 11000 } },
		h = { { 34428, 8400 } }, i = { { 6552, 11 }, { 72, 3 } } },
	Mirelle = { d = { { 133, 118600 }, { 116, 64200 }, { 5143, 44900 }, { 2136, 31800 }, { 10, 21400 }, { 120, 12100 }, { 1449, 5900 }, { 6603, 2500 } },
		i = { { 2139, 6 } }, x = { { 475, 3 } } },
	Zinnia = { d = { { 403, 52000 }, { 8042, 38800 }, { 8050, 21000 }, { 6603, 11000 } }, h = { { 331, 98600 }, { 8004, 33000 }, { 1064, 10000 } },
		i = { { 8042, 9 } }, x = { { 526, 5 }, { 370, 2 } } },
	Osgood = { d = { { 6603, 52000 }, { 20271, 22000 }, { 879, 14100 } }, h = { { 635, 168000 }, { 19750, 52000 }, { 633, 16900 } },
		i = { { 1044, 2 } }, x = { { 4987, 11 } } },
}
local SAMPLE_TAKEN = { { id = -1, nm = "Melee", v = 128400 }, { id = -2, nm = "Smite Slam", v = 41200, from = "Mr. Smite" },
	{ id = -3, nm = "Cannon Blast", v = 22800, from = "Defias Cannon" }, { id = -4, nm = "Fireball", v = 18100, from = "Defias Evoker" } }
local SAMPLE_AVOID = {
	{ id = -5, nm = "Smite Stomp", by = { Thalric = 1200, Forearms = 2100, Mirelle = 6400, Zinnia = 800, Osgood = 2000 } },
	{ id = -6, nm = "Cannon Blast", by = { Thalric = 1000, Forearms = 3400, Mirelle = 2200, Zinnia = 600, Osgood = 1100 } },
	{ id = -7, nm = "Flamestrike", by = { Thalric = 900, Forearms = 1900, Mirelle = 2400, Zinnia = 400, Osgood = 900 } },
	{ id = -8, nm = "Whirlwind", by = { Thalric = 600, Forearms = 1600, Mirelle = 900, Zinnia = 200, Osgood = 700 } },
	{ id = -9, nm = "Frost Nova", by = { Thalric = 400, Forearms = 800, Mirelle = 700, Zinnia = 200, Osgood = 600 } },
}

local function SampleRun(t0, seed, me, opts)
	local rand = Rand(seed)
	local names = { "Thalric", "Forearms", "Mirelle", "Zinnia", "Osgood" }
	local share = { Thalric = 1.03, Forearms = 1, Mirelle = 0.76, Zinnia = 0.31, Osgood = 0.22 }
	local bosses = {
		{ "Rhahk'Zor", 48, true }, { "Sneed", 72, true }, { "Gilnid", 91, true }, { "Mr. Smite", 114, false },
		{ "Mr. Smite", 126, true }, { "Captain Greenskin", 65, true }, { "Edwin VanCleef", 141, true },
	}
	if opts and opts.noWipe then table.remove(bosses, 4) end
	local trash = { "Defias Overseer", "Defias Miner", "Goblin Engineer", "Defias Evoker", "Defias Pirate", "Defias Squallshaper",
		"Defias Watchman", "Goblin Craftsman", "Defias Taskmaster", "Defias Blackguard" }
	local r = { id = -seed, name = "The Deadmines", kind = "party", t0 = t0, done = true, pulls = {}, players = {}, order = {}, deaths = {} }
	for _, n in ipairs(names) do
		r.players[n] = { n = n, c = SAMPLE_CLASS[n], me = n == me or nil, sec = 0, pulls = 0, sp = {} }
		r.order[#r.order + 1] = n
	end
	local clock, b = t0 + 35, 1
	local bossAt = { [5] = true, [10] = true, [15] = true, [20] = true, [22] = true, [28] = true, [34] = true }
	local scale = opts and opts.scale or 1
	for i = 1, 34 do
		local gap = (i == 11 and 250) or (i == 21 and 140) or rand(18, 50)
		clock = clock + gap
		local pull
		if bossAt[i] and bosses[b] then
			local def = bosses[b]
			b = b + 1
			pull = { boss = def[1], kill = def[3], dur = def[2] }
		else
			pull = { name = trash[rand(1, #trash)] .. ({ "", " + 1", " + 2", " + 3" })[rand(1, 4)], dur = rand(11, 26) }
		end
		pull.t, pull.size, pull.dp, pull.k = clock + pull.dur, 5, {}, 0
		local base = rand(250, 390) * scale
		if pull.boss then base = (pull.kill == false and 330 or 395) * scale end
		local list = {}
		for _, n in ipairs(names) do
			local dps = math.floor(base * share[n] * (0.88 + rand(0, 24) / 100))
			pull.dp[n] = dps
			list[#list + 1] = { n = n, c = SAMPLE_CLASS[n], me = n == me or nil, dps = dps, d = dps * pull.dur }
		end
		table.sort(list, function(x, y) return x.d > y.d end)
		local gd = 0
		for k, p in ipairs(list) do
			gd = gd + p.d
			if p.me then pull.rank, pull.my = k, p.dps end
			p.h = (p.n == "Osgood" and 250 or p.n == "Zinnia" and 150 or p.n == "Forearms" and 9 or 0) * pull.dur
			p.t = (p.n == "Forearms" and 260 or 40 + rand(0, 40)) * pull.dur
			p.a = pull.boss and rand(0, 900) or rand(0, 200)
			p.i = p.n == "Forearms" and rand(0, 1) or 0
			p.x = p.n == "Osgood" and rand(0, 1) or 0
			p.k = 0
			local a = r.players[p.n]
			for _, key in ipairs({ "d", "h", "t", "a", "i", "x" }) do a[key] = (a[key] or 0) + (p[key] or 0) end
			a.sec, a.pulls = a.sec + pull.dur, a.pulls + 1
		end
		pull.gd, pull.top, pull.topc = gd, list[1].n, list[1].c
		if pull.boss then pull.p = list end
		r.pulls[#r.pulls + 1] = pull
		clock = pull.t
	end
	r.t1 = clock + 60
	-- Deaths: three in the wipe, one on trash early, one late.
	local function Die(pullIndex, n, at, by, nm, over, from)
		local p = r.pulls[pullIndex]
		p.k = p.k + 1
		if p.p then
			for _, q in ipairs(p.p) do
				if q.n == n then q.k = (q.k or 0) + 1 end
			end
		end
		r.players[n].k = (r.players[n].k or 0) + 1
		r.deaths[#r.deaths + 1] = { pull = pullIndex, n = n, c = SAMPLE_CLASS[n], at = at, by = by, nm = nm, o = over, from = from }
	end
	if not (opts and opts.noWipe) then
		Die(8, "Mirelle", 31, -4, "Fireball", 310, "Defias Evoker")
		Die(20, "Mirelle", 91, -5, "Smite Stomp", 640, "Mr. Smite")
		Die(20, "Osgood", 107, -2, "Smite Slam", 220, "Mr. Smite")
		Die(20, "Thalric", 112, -2, "Smite Slam", 480, "Mr. Smite")
		Die(26, "Thalric", 22, -10, "Backstab", 90, "Defias Blackguard")
	end
	-- Abilities.
	for n, kinds in pairs(SAMPLE_SPELLS) do
		local a = r.players[n]
		for key, list in pairs(kinds) do
			a.sp[key] = {}
			local total = 0
			for _, s in ipairs(list) do total = total + s[2] end
			local want = a[key] or total
			for _, s in ipairs(list) do
				a.sp[key][s[1]] = { v = (key == "i" or key == "x") and s[2] or math.floor(s[2] / total * want), n = rand(3, 34) }
			end
			if key == "i" or key == "x" then
				local count = 0
				for _, s in ipairs(list) do count = count + s[2] end
				a[key] = count
			end
		end
		a.sp.t, a.sp.a = {}, {}
		for _, s in ipairs(SAMPLE_TAKEN) do
			local part = n == "Forearms" and 0.46 or 0.135
			a.sp.t[s.id] = { v = math.floor(s.v * part), n = rand(2, 30), nm = s.nm, from = s.from, dl = (s.nm == "Smite Slam" and (n == "Osgood" or n == "Thalric")) and 1 or nil }
		end
		local avoid = 0
		for _, s in ipairs(SAMPLE_AVOID) do
			a.sp.a[s.id] = { v = s.by[n], n = rand(1, 9), nm = s.nm }
			avoid = avoid + s.by[n]
		end
		a.a = avoid
	end
	for _, i in ipairs({ 5, 28 }) do
		local p = r.pulls[i]
		if p and p.boss and not (opts and opts.noBests) then p.nb = true end
	end
	return r
end

function R.SampleRuns()
	local now = time()
	local runs = {
		SampleRun(now - 4 * 86400 - 3600, 11, "Forearms", { scale = 0.82 }),
		SampleRun(now - 3 * 86400, 12, "Forearms", { scale = 0.86, noBests = true }),
		SampleRun(now - 2 * 86400 + 5000, 13, "Forearms", { scale = 0.9, noBests = true }),
		SampleRun(now - 86400 - 7000, 14, "Forearms", { scale = 0.95, noWipe = true, noBests = true }),
		SampleRun(now - 2700, 21, "Forearms"),
	}
	local bests = {}
	for _, r in ipairs(runs) do
		for _, p in ipairs(r.pulls) do
			if p.boss and p.kill ~= false then
				local key = "boss:" .. p.boss
				if not bests[key] or (p.my or 0) > bests[key].dps then bests[key] = { dps = p.my or 0 } end
			end
		end
	end
	return { runs = runs, bests = bests }
end

-- The report with made-up runs, to see every page without a dungeon.
function R.Preview()
	if not ns.Meter or not ns.Meter.Lib then return end
	L = ns.Meter.Lib
	local s = R.SampleRuns()
	sample = s
	R.Show(s.runs[#s.runs])
end

function R.PreviewBanner()
	L = L or ns.Meter.Lib
	local s = R.SampleRuns()
	ShowBanner(s.runs[#s.runs], true)
end
