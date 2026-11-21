SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.BookDock = ns.BookDock or {}
local K = ns.BookDock

-- The books beside their profession windows: when the game's Professions window (ProfessionsFrame,
-- Blizzard_Professions) shows the crafting page of Mining, Cooking or Fishing, that profession's
-- book (Rock Bottom on The Smelter, the Cookbook on The Larder, the Angler's journal on Camp)
-- opens docked to its right edge (past the profession tabs), scaled so the two line up top and
-- bottom; it can't be dragged away while docked, and closes with the window if the dock opened it.
--
-- The D3 dress (optional, per book): the window wears the book's stone. A slim header with the
-- profession's own medallion (book-headers.png: ingots over a forge, an egg in a pan, a bobber)
-- sits on its top edge, three-sliced so the medallion stays round, at the book's header height; the stone body runs behind its content and the profession
-- tabs. Blizzard's frame art (border, background, portrait, title, close button) is faded to
-- alpha 0, never hidden or moved, and put back exactly as it was when another profession opens
-- or the window closes. Only textures and alpha are touched; Blizzard's buttons do the smelting.

-- Each profession: its skill line and Enum.Profession value, its book and settings, the chapter the
-- book opens on, and the row of its window's header in book-headers.png.
local DOCKS = {
	{ key = "mining", skill = 186, profession = 6, chapter = "smelter", header = 400,
		book = function() return ns.Mining and ns.Mining.book end, opt = function() return ns.DB().mining end },
	{ key = "cooking", skill = 185, profession = 5, chapter = "larder", header = 240,
		book = function() return ns.Cookbook and ns.Cookbook.book end, opt = function() return ns.DB().cookbook end },
	{ key = "fishing", skill = 356, profession = 10, chapter = "camp", header = 80,
		book = function() return ns.Journal and ns.Journal.book end, opt = function() return ns.DB().journal end },
}
K.DOCKS = DOCKS
local OVERLAP = 24 -- the header covers the window's title bar, this tall
local SLIM = 12 -- the stone's bottom edge under the window
local ATLAS = 1024
-- The slim headers in book-headers.png (tools/build_journal_art.py headers): sliced either side of
-- the medallion, which stays round; the close mark.
local HEADER = { w = 600, h = 72, left = 255, right = 345 }
local CLOSE_MARK = { x = 562, y = 8, size = 30 }
local SIDE = 14 -- bag-frame.png's stone edge
local BODY = { y = 155, h = 300 }
local FOOT = { y = 648, h = 14 }

local function Readable(v) return v ~= nil and not ns.Secret(v) end

local function Match(entry, id, parent, prof, line)
	return (Readable(id) and id == entry.skill) or (Readable(parent) and parent == entry.skill)
		or (Readable(prof) and prof == entry.profession) or (Readable(line) and line == entry.skill)
end

-- Which dock the Professions window's crafting page is showing, or nil.
local function Which(pf)
	if not (pf and pf:IsShown() and pf.CraftingPage and pf.CraftingPage:IsShown()) then return end
	local id, parent, prof, line
	if C_TradeSkillUI then
		for _, fn in ipairs({ "GetBaseProfessionInfo", "GetChildProfessionInfo" }) do
			local get = C_TradeSkillUI[fn]
			local ok, info = pcall(get or function() end)
			if ok and type(info) == "table" then
				id, parent, prof = id or info.professionID, parent or info.parentProfessionID, prof or info.profession
			end
		end
	end
	if Professions and Professions.GetEffectiveSkillLineID then
		local ok, l = pcall(Professions.GetEffectiveSkillLineID)
		if ok then line = l end
	end
	for _, entry in ipairs(DOCKS) do
		if Match(entry, id, parent, prof, line) then return entry end
	end
end
K.Which = Which

---------------------------------------------------------------------------
-- The dress.

local skin
local faded = {} -- region -> its alpha before the dress

local function Fade(region)
	if type(region) ~= "table" or type(region.SetAlpha) ~= "function" or faded[region] then return end
	faded[region] = region.GetAlpha and region:GetAlpha() or 1
	region:SetAlpha(0)
end

local function Restore()
	for region, alpha in pairs(faded) do region:SetAlpha(alpha) end
	wipe(faded)
end

-- Blizzard's own chrome on the window: what the dress replaces.
local function Chrome(pf)
	local list = { pf.NineSlice, pf.Bg, pf.TopTileStreaks, pf.PortraitContainer, pf.TitleContainer, pf.CloseButton,
		pf.MaximizeMinimize }
	-- The crafting page's backdrop has no key: find it by its atlas.
	local page = pf.CraftingPage
	if page and page.GetRegions then
		for _, region in ipairs({ page:GetRegions() }) do
			local atlas = region.GetAtlas and region:GetAtlas()
			if Readable(atlas) and atlas == "Profession-Background-Template2" then list[#list + 1] = region end
		end
	end
	return list
end

local function Piece(parent, slot, x0, y0, x1, y1, layer, sub)
	local tex = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sub)
	if ns.Art.Apply(tex, slot) then
		tex:SetTexCoord(x0 / ATLAS, x1 / ATLAS, y0 / ATLAS, y1 / ATLAS)
	else
		tex:SetColorTexture(0.06, 0.05, 0.04, 0.96)
	end
	return tex
end

local function BuildSkin(pf)
	if skin then return skin end
	ns.Art.Require("bookHeaders")
	skin = CreateFrame("Frame", nil, pf)
	local h = HEADER
	skin.headL = Piece(skin, "bookHeaders", 0, 0, h.left, h.h, "ARTWORK")
	skin.headM = Piece(skin, "bookHeaders", h.left, 0, h.right, h.h, "ARTWORK")
	skin.headR = Piece(skin, "bookHeaders", h.right, 0, h.w, h.h, "ARTWORK")
	skin.bodyL = Piece(skin, "bagFrame", 0, BODY.y, SIDE, BODY.y + BODY.h)
	skin.bodyM = Piece(skin, "bagFrame", SIDE, BODY.y, h.w - SIDE, BODY.y + BODY.h)
	skin.bodyR = Piece(skin, "bagFrame", h.w - SIDE, BODY.y, h.w, BODY.y + BODY.h)
	skin.foot = Piece(skin, "bagFrame", 0, FOOT.y, h.w, FOOT.y + FOOT.h)
	-- The header art's own close mark, made to work.
	local close = CreateFrame("Button", nil, skin)
	local glow = close:CreateTexture(nil, "HIGHLIGHT")
	glow:SetAllPoints()
	glow:SetColorTexture(1, 0.6, 0.3, 0.25)
	glow:SetBlendMode("ADD")
	close:SetScript("OnClick", function()
		if pf.CloseButton and pf.CloseButton.Click then
			pf.CloseButton:Click()
		elseif HideUIPanel then
			HideUIPanel(pf)
		end
	end)
	skin.close = close
	return skin
end

-- Lay the dress out: the profession's header row, header height hh and the gutter for the
-- profession tabs, in the window's own units.
local function LayoutSkin(pf, row, hh, gutter)
	local s = BuildSkin(pf)
	local h = HEADER
	s.headL:SetTexCoord(0, h.left / ATLAS, row / ATLAS, (row + h.h) / ATLAS)
	s.headM:SetTexCoord(h.left / ATLAS, h.right / ATLAS, row / ATLAS, (row + h.h) / ATLAS)
	s.headR:SetTexCoord(h.right / ATLAS, h.w / ATLAS, row / ATLAS, (row + h.h) / ATLAS)
	local w, ht = pf:GetWidth() + gutter, pf:GetHeight()
	local k = hh / HEADER.h
	local mid = (HEADER.right - HEADER.left) * k
	local side = (w - mid) / 2
	local edge = SIDE * k
	s:ClearAllPoints()
	s:SetPoint("TOPLEFT", pf, "TOPLEFT", 0, hh - OVERLAP)
	s:SetSize(w, hh - OVERLAP + ht + SLIM)
	s:SetFrameLevel(math.max(1, pf:GetFrameLevel()))
	s.headL:ClearAllPoints()
	s.headL:SetPoint("TOPLEFT")
	s.headL:SetSize(side, hh)
	s.headM:ClearAllPoints()
	s.headM:SetPoint("TOPLEFT", s.headL, "TOPRIGHT")
	s.headM:SetSize(mid, hh)
	s.headR:ClearAllPoints()
	s.headR:SetPoint("TOPLEFT", s.headM, "TOPRIGHT")
	s.headR:SetSize(side, hh)
	s.bodyL:ClearAllPoints()
	s.bodyL:SetPoint("TOPLEFT", 0, -hh)
	s.bodyL:SetPoint("BOTTOMLEFT", 0, SLIM)
	s.bodyL:SetWidth(edge)
	s.bodyR:ClearAllPoints()
	s.bodyR:SetPoint("TOPRIGHT", 0, -hh)
	s.bodyR:SetPoint("BOTTOMRIGHT", 0, SLIM)
	s.bodyR:SetWidth(edge)
	s.bodyM:ClearAllPoints()
	s.bodyM:SetPoint("TOPLEFT", s.bodyL, "TOPRIGHT")
	s.bodyM:SetPoint("BOTTOMRIGHT", s.bodyR, "BOTTOMLEFT")
	s.foot:ClearAllPoints()
	s.foot:SetPoint("BOTTOMLEFT")
	s.foot:SetPoint("BOTTOMRIGHT")
	s.foot:SetHeight(SLIM)
	-- The close mark, inside the right slice (stretched across, so placed in its units).
	local rk = side / (HEADER.w - HEADER.right)
	s.close:ClearAllPoints()
	s.close:SetPoint("TOPLEFT", s.headR, "TOPLEFT", (CLOSE_MARK.x - HEADER.right) * rk, -CLOSE_MARK.y * k)
	s.close:SetSize(CLOSE_MARK.size * k, CLOSE_MARK.size * k)
	s:Show()
end

---------------------------------------------------------------------------
-- The dock.

local docked, openedByDock = nil, false -- the dock entry whose book is docked

-- The gutter for the profession tabs on the window's right edge.
local function Gutter(pf)
	local tab = pf.ProfessionsOverviewTab
	local w = tab and tab:IsShown() and tab:GetWidth() or 0
	return (Readable(w) and w or 0) + 4
end

local function Undock()
	local book = docked and docked.book()
	if book then
		book.Dock(nil)
		if openedByDock and book.frame and book.frame:IsShown() then book.frame:Hide() end
	end
	docked, openedByDock = nil, false
end

local function Update()
	local pf = ProfessionsFrame
	local entry = pf and Which(pf)
	local opt = entry and entry.opt() or {}
	local on = entry ~= nil
	local book = entry and entry.book()
	-- Another profession's book was docked: it goes back first.
	if docked and docked ~= entry then Undock() end
	-- Sizes, in the window's units: the book's header (scale 1) and the window.
	local _, bookH, headerH = 0, 0, 0
	if book and book.Metrics then _, bookH, headerH = book.Metrics() end
	local pfH = pf and pf:GetHeight() or 0
	local gutter = pf and Gutter(pf) or 0
	local dress = on and opt.skin and bookH > 0
	-- The book's scale beside the window: with the dress, header top to stone bottom; without,
	-- the window's own height.
	local scale
	if bookH > 0 and pfH > 0 then
		if dress then
			scale = (pfH - OVERLAP + SLIM) / (bookH - headerH)
		else
			scale = pfH / bookH
		end
	end
	if dress then
		for _, region in ipairs(Chrome(pf)) do Fade(region) end
		LayoutSkin(pf, entry.header, headerH * scale, gutter)
	else
		Restore()
		if skin then skin:Hide() end
	end
	if on and opt.dock and book and scale then
		-- Tops level: the book's header with the dress's, or with the window.
		local up = dress and (headerH * scale - OVERLAP) or 0
		book.Dock(pf, gutter / scale, up / scale, scale)
		if not (book.frame and book.frame:IsShown()) then
			openedByDock = true
			book.Open(entry.chapter)
		elseif docked ~= entry then
			book.Select(entry.chapter)
		end
		docked = entry
	elseif docked then
		Undock()
	end
end

local pending = false
function K.Refresh()
	if pending or not C_Timer then return end
	pending = true
	-- The window settles over a frame or two (which profession, which page): look after.
	C_Timer.After(0.05, function()
		pending = false
		ns.Try("book dock", Update)
	end)
end

local hooked = false
local function Hook()
	local pf = ProfessionsFrame
	if hooked or not pf then return end
	hooked = true
	pf:HookScript("OnShow", K.Refresh)
	pf:HookScript("OnHide", function()
		ns.Try("book dock", function()
			Restore()
			if skin then skin:Hide() end
			Undock()
		end)
	end)
	pf:HookScript("OnSizeChanged", K.Refresh)
	if pf.CraftingPage then
		pf.CraftingPage:HookScript("OnShow", K.Refresh)
		pf.CraftingPage:HookScript("OnHide", K.Refresh)
	end
	K.Refresh()
end

function K.ApplySettings()
	K.Refresh()
end

function K.Init()
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "ADDON_LOADED", "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE", "TRADE_SKILL_LIST_UPDATE",
		"TRADE_SKILL_DATA_SOURCE_CHANGED" }) do
		pcall(events.RegisterEvent, events, event)
	end
	events:SetScript("OnEvent", function(_, event, name)
		if event == "ADDON_LOADED" then
			if name == "Blizzard_Professions" then Hook() end
			return
		end
		Hook()
		K.Refresh()
	end)
	Hook()
end
