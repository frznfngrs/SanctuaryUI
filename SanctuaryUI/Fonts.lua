SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.Fonts = ns.Fonts or {}
local Fonts = ns.Fonts

-- The addon's fonts (Options > Fonts). Every font string SanctuaryUI styles itself goes
-- through Fonts.Set with a role: "title" (names, globe numbers, headings: Exocet by default)
-- or "body" (hotkeys, counts, timers, labels: the game's font by default). Set remembers what
-- each string asked for, so a change of face, size or outline redraws them all at once.
--
-- Faces come from four places: Diablo III's own (bundled in Media, cut down to Latin, Greek and
-- Cyrillic by tools/build_fonts.py), the fonts every WoW client ships, open-licence fonts bundled
-- in Media\Fonts (tools/build_ofl_fonts.py), and every font another addon has registered with
-- LibSharedMedia (ElvUI, Details, Plater...), when one is loaded.

local MEDIA = "Interface\\AddOns\\SanctuaryUI\\Media\\"

-- key, label, path. Path may be a function, for a client global read when it's drawn.
local BUILTIN = {
	{ "exocet", "Exocet", MEDIA .. "exocet.ttf", "d3" },
	{ "d3serif", "Diablo Serif", MEDIA .. "d3-serif.ttf", "d3" },
	{ "d3sans", "Diablo Sans", MEDIA .. "d3-sans.ttf", "d3" },
	{ "d3script", "Diablo Script", MEDIA .. "d3-script.ttf", "d3" },
	{ "default", "Game font", function() return STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF" end, "wow" },
	{ "friz", "Friz Quadrata", "Fonts\\FRIZQT__.TTF", "wow" },
	{ "narrow", "Arial Narrow", "Fonts\\ARIALN.TTF", "wow" },
	{ "morpheus", "Morpheus", "Fonts\\MORPHEUS.TTF", "wow" },
	{ "skurri", "Skurri", "Fonts\\SKURRI.TTF", "wow" },
	{ "nimrod", "Nimrod MT", "Fonts\\NIM_____.ttf", "wow" },
	{ "2002", "2002", "Fonts\\2002.TTF", "wow" },
	{ "2002b", "2002 Bold", "Fonts\\2002B.TTF", "wow" },
	{ "mok", "MoK", "Fonts\\K_Pagetext.TTF", "wow" },
	-- Open fonts (SIL OFL, from Google Fonts; licences in Media\\Fonts\\licenses).
	{ "cinzel", "Cinzel", MEDIA .. "Fonts\\Cinzel.ttf", "fantasy" },
	{ "cinzelbold", "Cinzel Bold", MEDIA .. "Fonts\\CinzelBold.ttf", "fantasy" },
	{ "cinzeldeco", "Cinzel Decorative", MEDIA .. "Fonts\\CinzelDecorative-Bold.ttf", "fantasy" },
	{ "marcellus", "Marcellus SC", MEDIA .. "Fonts\\MarcellusSC-Regular.ttf", "fantasy" },
	{ "imfell", "IM Fell English SC", MEDIA .. "Fonts\\IMFellEnglishSC.ttf", "fantasy" },
	{ "uncial", "Uncial Antiqua", MEDIA .. "Fonts\\UncialAntiqua-Regular.ttf", "fantasy" },
	{ "fraktur", "UnifrakturCook", MEDIA .. "Fonts\\UnifrakturCook-Bold.ttf", "fantasy" },
	{ "grenze", "Grenze Gotisch", MEDIA .. "Fonts\\GrenzeGotisch.ttf", "fantasy" },
	{ "newrocker", "New Rocker", MEDIA .. "Fonts\\NewRocker-Regular.ttf", "fantasy" },
	{ "medievalsharp", "MedievalSharp", MEDIA .. "Fonts\\MedievalSharp.ttf", "fantasy" },
	{ "almendra", "Almendra SC", MEDIA .. "Fonts\\AlmendraSC-Regular.ttf", "fantasy" },
	{ "metamorphous", "Metamorphous", MEDIA .. "Fonts\\Metamorphous-Regular.ttf", "fantasy" },
	{ "eaglelake", "Eagle Lake", MEDIA .. "Fonts\\EagleLake-Regular.ttf", "fantasy" },
	{ "fondamento", "Fondamento", MEDIA .. "Fonts\\Fondamento-Regular.ttf", "fantasy" },
	{ "alegreya", "Alegreya", MEDIA .. "Fonts\\Alegreya.ttf", "serif" },
	{ "ebgaramond", "EB Garamond", MEDIA .. "Fonts\\EBGaramond.ttf", "serif" },
	{ "cormorant", "Cormorant Garamond", MEDIA .. "Fonts\\CormorantGaramond.ttf", "serif" },
	{ "alegreyasans", "Alegreya Sans", MEDIA .. "Fonts\\AlegreyaSans.ttf", "sans" },
	{ "oswald", "Oswald", MEDIA .. "Fonts\\Oswald.ttf", "sans" },
	{ "robotocond", "Roboto Condensed", MEDIA .. "Fonts\\RobotoCondensed.ttf", "sans" },
	{ "barlowcond", "Barlow Condensed", MEDIA .. "Fonts\\BarlowCondensed.ttf", "sans" },
	{ "firacond", "Fira Sans Condensed", MEDIA .. "Fonts\\FiraSansCondensed.ttf", "sans" },
	{ "teko", "Teko", MEDIA .. "Fonts\\Teko.ttf", "sans" },
	{ "rajdhani", "Rajdhani", MEDIA .. "Fonts\\Rajdhani.ttf", "sans" },
}

-- What each role uses when nothing is chosen, or the chosen face won't load.
Fonts.DEFAULT = { title = "exocet", body = "default" }

-- The names these fonts take in LibSharedMedia, for other addons' font lists.
local SHARED = { exocet = "SanctuaryUI Exocet", d3serif = "SanctuaryUI Diablo Serif", d3sans = "SanctuaryUI Diablo Sans", d3script = "SanctuaryUI Diablo Script" }

local byKey = {}
for i, f in ipairs(BUILTIN) do
	byKey[f[1]] = { key = f[1], label = f[2], path = f[3], group = f[4], order = i }
end

-- WoW loads a font file the first time text is drawn in it, and until then SetFont fails (the
-- first time even for Exocet). ElvUI does the same: every face gets a hidden string drawn in it
-- as early as possible, so it is ready by the time anything picks it.
local preloader = CreateFrame("Frame", nil, UIParent)
preloader:SetPoint("TOP", UIParent, "BOTTOM", 0, -5000)
preloader:SetSize(100, 100)
local preloaded = {}

local function Preload(path)
	if type(path) ~= "string" or preloaded[path] then return end
	preloaded[path] = true
	local fs = preloader:CreateFontString()
	fs:SetAllPoints()
	if pcall(fs.SetFont, fs, path, 14, "") then pcall(fs.SetText, fs, "cache") end
end

for _, f in ipairs(BUILTIN) do
	if type(f[3]) == "string" then Preload(f[3]) end
end

local function LSM()
	return LibStub and LibStub("LibSharedMedia-3.0", true)
end

local function Opt()
	return ns.DB().fonts
end

local function PathOf(key)
	local f = byKey[key]
	if f then
		return type(f.path) == "function" and f.path() or f.path
	end
	local name = type(key) == "string" and key:match("^lsm:(.+)$")
	local lsm = name and LSM()
	return lsm and lsm:IsValid("font", name) and lsm:Fetch("font", name, true) or nil
end

-- Old per-element choices (target frame, damage meter): "d3" and "wow" were Exocet and the game
-- font; they now mean whatever the title and body fonts are. ("narrow" is Arial Narrow's key.)
local ALIAS = { d3 = "title", wow = "body" }

-- The path and size factor for a string of a role, with an element's own choice if it has one.
local function Resolve(role, choice)
	if ALIAS[choice] then role, choice = ALIAS[choice], nil end
	local opt = Opt()
	local scale = (role == "title" and opt.titleScale or opt.bodyScale) or 1
	local key = choice or opt[role] or Fonts.DEFAULT[role] or "default"
	return PathOf(key) or PathOf(Fonts.DEFAULT[role] or "default"), scale, role
end

-- The element's outline, unless the Fonts page overrides it, plus Monochrome when asked.
local OUTLINES = { none = "", outline = "OUTLINE", thick = "THICKOUTLINE" }

local function Flags(flags)
	local opt = Opt()
	local outline = OUTLINES[opt.outline]
	if outline then flags = outline end
	flags = flags or ""
	if opt.monochrome then
		flags = flags == "" and "MONOCHROME" or flags .. ", MONOCHROME"
	end
	return flags
end

local wanted = setmetatable({}, { __mode = "k" }) -- font string: what it asked for

-- A face that wasn't ready: draw in a fallback for now and try again shortly, a few times (a
-- file added since the game started never loads, see Fonts.MissingBundled).
local RETRIES, retries, retrying = 10, 0, false

local function RetryLater()
	if retrying or retries >= RETRIES or not C_Timer then return end
	retrying = true
	C_Timer.After(1, function()
		retrying = false
		retries = retries + 1
		Fonts.Apply(true)
	end)
end

local function Try(fs, path, size, flags)
	Preload(path)
	if fs:SetFont(path, size, flags) == false or not fs:GetFont() then
		RetryLater()
		return false
	end
	return true
end

local function Draw(fs, spec)
	local path, scale, role = Resolve(spec.role, spec.choice)
	local size = math.max(6, spec.size * scale)
	local flags = Flags(spec.flags)
	if not Try(fs, path, size, flags) and not Try(fs, PathOf(Fonts.DEFAULT[role] or "default"), size, flags) then
		fs:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, flags)
	end
end

-- role: "title" or "body". size: the element's own size, before the Fonts page's scale.
-- flags: its outline ("", "OUTLINE"...). choice: a face the element's own options picked
-- (a font key, or the old "d3", "wow", "narrow"), overriding the role's.
function Fonts.Set(fs, role, size, flags, choice)
	if not Fonts.ready then
		-- The first module to style text (the globes, at login) sets ns.FONT for the rest.
		Fonts.ready = true
		ns.FONT = Fonts.Path("title")
	end
	local spec = wanted[fs] or {}
	spec.role, spec.size, spec.flags, spec.choice = role or "body", size or 12, flags, choice
	wanted[fs] = spec
	Draw(fs, spec)
end

-- Style a string once, without keeping it for later redraws (the options window's previews).
function Fonts.Draw(fs, role, size, flags, choice)
	Draw(fs, { role = role or "body", size = size or 12, flags = flags, choice = choice })
end

-- A string made from a Blizzard font object (GameFontNormalSmall...): keep its size and outline,
-- take the role's face.
function Fonts.Adopt(fs, role)
	local _, size, flags = fs:GetFont()
	Fonts.Set(fs, role, size or 12, flags or "")
end

-- The path the role draws in now, for code that sets fonts on strings it doesn't keep
-- (and ns.FONT, which modules read for the title face).
function Fonts.Path(role, choice)
	return (Resolve(role or "body", choice))
end

-- For LibActionButton's text config: path, size, flags.
function Fonts.Spec(role, size, flags)
	local path, scale = Resolve(role, nil)
	return path, math.max(6, (size or 12) * scale), Flags(flags)
end

-- Redraw every string after a change (ns.Refresh runs it first).
-- retry: a pass after a face wasn't ready (RetryLater); anything else starts the count again.
function Fonts.Apply(retry)
	if not retry then retries = 0 end
	ns.FONT = Fonts.Path("title")
	for fs, spec in pairs(wanted) do
		pcall(Draw, fs, spec)
	end
end

---------------------------------------------------------------------------
-- The font list for the options

-- A probe string tells which faces this client can load.
-- Only a success is remembered: a face not loaded yet (Preload) may be by the next look.
local probe, loads = nil, {}

local function Loads(path)
	if not path then return false end
	if not loads[path] then
		Preload(path)
		probe = probe or preloader:CreateFontString()
		probe:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 12, "")
		-- SetFont says false when the file won't load (yet). A client that says nothing is trusted.
		local ok = probe:SetFont(path, 12, "")
		loads[path] = ok ~= false and probe:GetFont() ~= nil
	end
	return loads[path]
end

local GROUP_TAG = {
	d3 = "|cffb3a78fDiablo III|r",
	wow = "|cff8f9fb3WoW|r",
	fantasy = "|cffb38f8ffantasy|r",
	serif = "|cffa3b38fbook|r",
	sans = "|cff8fb3aacondensed|r",
	lsm = "|cff9a8fb3addon|r",
}

-- values and sorting for an AceConfig select. first: extra entries put at the top (key, label).
function Fonts.Choices(first)
	local values, sorting, seen = {}, {}, {}
	for _, entry in ipairs(first or {}) do
		values[entry[1]] = entry[2]
		sorting[#sorting + 1] = entry[1]
	end
	local game = PathOf("default"):lower()
	for _, f in ipairs(BUILTIN) do
		local path = PathOf(f[1])
		-- Friz Quadrata is the game font in English clients: listed once, as Game font.
		local same = f[1] ~= "default" and path and path:lower() == game
		if values[f[1]] == nil and not same and Loads(path) then
			values[f[1]] = f[2] .. "  " .. GROUP_TAG[f[4]]
			sorting[#sorting + 1] = f[1]
		end
		if path and f[1] ~= "default" then seen[path:lower()] = true end
	end
	local lsm = LSM()
	if lsm then
		local names = {}
		for _, name in ipairs(lsm:List("font") or {}) do
			local path = lsm:Fetch("font", name, true)
			if path and not seen[path:lower()] and Loads(path) then
				seen[path:lower()] = true
				names[#names + 1] = name
			end
		end
		table.sort(names, function(a, b) return a:lower() < b:lower() end)
		for _, name in ipairs(names) do
			values["lsm:" .. name] = name .. "  " .. GROUP_TAG.lsm
			sorting[#sorting + 1] = "lsm:" .. name
		end
	end
	return values, sorting
end

-- How many of the fonts SanctuaryUI ships won't load: files added since the game started, which
-- WoW only finds after a restart (/reload is not enough).
function Fonts.MissingBundled()
	local missing = 0
	for _, f in ipairs(BUILTIN) do
		if type(f[3]) == "string" and f[3]:find("^Interface") and not Loads(f[3]) then missing = missing + 1 end
	end
	return missing
end

function Fonts.Label(key)
	local f = byKey[key]
	if f then return f.label end
	return type(key) == "string" and key:match("^lsm:(.+)$") or tostring(key)
end

---------------------------------------------------------------------------
-- Login: share our faces with other addons, and redraw when a chosen addon font turns up late.

local function Share()
	local lsm = LSM()
	if not lsm or Fonts.shared then return end
	Fonts.shared = true
	for _, name in ipairs(lsm:List("font") or {}) do
		Preload(lsm:Fetch("font", name, true))
	end
	local latin = lsm.LOCALE_BIT_western + (lsm.LOCALE_BIT_ruRU or 0)
	for key, name in pairs(SHARED) do
		if Loads(PathOf(key)) then
			pcall(lsm.Register, lsm, "font", name, PathOf(key), latin)
		end
	end
	lsm.RegisterCallback(Fonts, "LibSharedMedia_Registered", function(_, mediatype)
		if mediatype ~= "font" or not ns.db then return end
		local opt = Opt()
		if tostring(opt.title):find("^lsm:") or tostring(opt.body):find("^lsm:") then
			Fonts.Apply()
		end
	end)
end

local login = CreateFrame("Frame")
login:RegisterEvent("PLAYER_LOGIN")
login:SetScript("OnEvent", function()
	pcall(Share)
end)
