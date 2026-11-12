SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI

-- Every setting, with its default. AceDB profiles hold these; Options.lua edits them and
-- ns.Refresh() applies them.
ns.DEFAULTS = {
	profile = {
		-- console
		point = "BOTTOM",
		rel = "BOTTOM",
		x = 0,
		y = 0,
		scale = 1, -- the bars: the console between the globes, its menu and rail
		globeScale = 1, -- the globes and their statues
		globesSeparate = false, -- old profiles: the globes kept globeScale instead of following scale
		scalesSplit = false, -- old profiles converted to separate bar and globe scales (Core.lua)
		posUI = false, -- x, y are the console's bottom centre in screen units (Core.lua ApplyPosition)
		iconSize = 1, -- console skill icons, of their socket; below 1 the stone shows around them
		locked = true,
		snapping = true, -- unlocked frames snap to each other and the screen edges while dragged
		grid = false, -- Edit Mode style grid while unlocked; frames snap to its lines
		gridSize = 40, -- grid spacing, UIParent units out from the screen's centre
		hideMicroMenu = true,

		-- fonts (Fonts.lua): a font key, or "lsm:<name>" for one another addon shared
		fonts = {
			title = "exocet", -- names, globe numbers, headings
			body = "default", -- hotkeys, counts, timers, labels: the game's font
			titleScale = 1,
			bodyScale = 1,
			outline = "element", -- element (each text's own) | none | outline | thick
			monochrome = false,
		},

		-- globes
		numbers = "combat", -- on | combat | hover | off
		numbersMax = true,
		numberSize = 22,
		liquidAnimate = true,
		liquidStyle = "classic", -- classic: D3's layered tiles; rendered: the Blender flipbooks (Liquid.lua)
		pollution = true, -- debuffs colour the health globe until they end or are cleansed (Pollution.lua)
		-- the statues' eyes glow while a chosen buff is on you (StatueEyes.lua): names or spell IDs, commas between
		statueEyes = {
			angel = { enabled = true, spells = "Blessing of Wisdom, Greater Blessing of Wisdom", color = { 0.30, 0.62, 1.0 } },
			gargoyle = { enabled = true, spells = "Blessing of Might, Greater Blessing of Might", color = { 1.0, 0.16, 0.10 } },
			wings = { enabled = true, spells = "" }, -- golden light on the angel's wings (AngelRadiance.lua); no buff until one is named
		},
		liquidSpeed = 1,
		lowHealthPulse = true,
		lowHealthAgitate = true, -- the health globe turns faster and sloshes as health falls
		healPrediction = true, -- incoming heals poured on top of the health globe
		absorbPrediction = true, -- damage shields: silver liquid above the heals, a glow when full
		costPrediction = true, -- the cast's cost lit at the top of the resource globe
		-- light radiating from behind a globe while a chosen buff is up (GlobeAura.lua)
		globeAuras = {
			enabled = true,
			intensity = 1,
			rays = true,
			sparks = true,
			catch = true, -- the light wrapping onto the globe's glass
			testLength = 30, -- seconds a test cast lasts (Watch.lua test mode)
			settleLong = true, -- 10-minute buffs (Inner Fire, Lightning Shield) calm down after lighting
			renderedStorm = true, -- Lightning Shield's drawn flipbook lightning (GlobeAura.lua STORM)
			renderedBreak = true, -- shields crack and shatter with the Blender render (GlobeAura.lua BREAK)
			effects = { ["*"] = true, innerFire = false }, -- by Watch.lua effect key
			looks = {}, -- by effect key, what that skill shows; unset: its default (GlobeAura.lua LookOf)
			breaks = {}, -- by effect key, how that shield breaks; unset: its default (GlobeAura.lua BreakOf)
			hotTint = "default", -- healing over time: a GlobeAura.lua colour, or each skill's own
			hotStrength = 1, -- healing over time: brightness against the skill's own
		},

		-- rail
		railMode = "auto", -- auto | xp | rep
		railRested = true,
		levelPlaque = true, -- your level on a D3 plaque over the console's centre skull

		-- action buttons (main bar and rows)
		buttons = {
			hotkeys = true,
			hotkeySize = 11, -- keybind text on action buttons; stance and totem sockets use one less
			macroNames = false,
			range = "button", -- button | hotkey | none
			tooltips = "enabled", -- enabled | nocombat | disabled
			grid = true,
			cooldownNumbers = "show", -- cvar | show | hide
			cooldownTenths = 60, -- seconds; below this cooldown numbers count tenths (0: never)
			lock = false, -- locked buttons still pick up with the pickup modifier (Shift)
			procGlow = true, -- reveal and chasing sparks when a conditional skill becomes usable
			activeGlow = true, -- D3 burning frame while a skill's effect is up
			activeTimer = true, -- D3 tab in the socket with a bar draining to the end
			activeTimerPos = "top", -- top | bottom edge of the socket
			activeMax = 60, -- seconds; longer buffs don't light their skill
			activeGlowMax = 30, -- seconds; longer buffs get the timer tab without the glow
			activeEndless = false, -- buffs with no duration (stances, auras, aspects) light their skill too
		},

		-- main bar paging (rows with source "main" follow it too)
		paging = {
			possess = true,
			barPaging = true,
			stances = true,
			forms = { ["*"] = true, ["DRUID.moonkin"] = false },
			ctrl = 0,
			alt = 0,
			shift = 0,
			custom = "",
		},

		-- rows above the console. source: "main" (actions 10-12, paged with the main bar)
		-- or an action bar page 1-15.
		rows = {
			[2] = { enabled = true, source = "main", count = 3 },
			[3] = { enabled = false, source = 6, count = 12 },
			[4] = { enabled = false, source = 5, count = 12 },
			[5] = { enabled = false, source = 3, count = 12 },
			[6] = { enabled = false, source = 4, count = 12 },
			[7] = { enabled = false, source = 13, count = 12 },
			[8] = { enabled = false, source = 14, count = 12 },
			[9] = { enabled = false, source = 15, count = 12 },
			["**"] = {
				enabled = false,
				source = 2,
				count = 12,
				followForms = false, -- change page with stance or form (ActionBar.lua RowPageDriver)
				formPages = {}, -- by "CLASS.form" (ActionBar.lua CLASS_PAGES): the page shown in that form
				scale = 0.8,
				spacing = 5,
				visibility = "always", -- always | combat | nocombat | custom
				custom = "",
				alpha = 1,
				mouseover = false,
				perLine = 12,
				docked = false, -- in the console: a row of sockets under the lifted rail band
				-- Dragged rows leave the stack and keep their own spot (centre, UIParent bottom-left).
				moved = false,
				mx = 0,
				my = 0,
			},
		},

		pets = true,
		-- buffs and debuffs
		auras = {
			enabled = true,
			size = 30,
			spacing = 4,
			perLine = 12,
			maxBuffs = 16,
			maxDebuffs = 8,
			duration = true,
			bars = true, -- countdown bar under each timed aura
			moved = false,
			mx = 0,
			my = 0,
		},
		hearthItem = 6948,

		-- target plate, top of the screen
		target = {
			enabled = true,
			style = "d3", -- d3 (D3's monster bar) | lintel | slim | slab | bracket | tablet
			scale = 1, -- 1 = D3's own size (one art pixel per pixel at 1080p)
			width = 1, -- frame and bar width, stretched between the ornaments (d3 style)
			rankWidth = "frame", -- frame: every rank as wide | bar: every bar as long | d3: grows with rank
			height = 1, -- the bar's height, the frame's lips and ornaments unstretched (d3 style)
			totWidth = 1, -- the target of target bar's width (d3 style)
			totHeight = 1, -- the target of target bar's height (d3 style)
			power = true, -- the target's resource: a strip in D3's bar, a groove in the other styles
			classColor = true, -- a player's name in their class colour
			classIcon = true, -- a player's class icon on the portrait
			factionIcon = true, -- a player's Alliance or Horde emblem
			raidIcon = true, -- the raid marker (skull, cross...) on any target
			portrait = false, -- 3D portrait of the target in a skill socket, left of the bar
			edgeGlow = true, -- ember at the health bar's leading edge
			textGlow = true, -- a soft dark glow behind the bar's text, so it reads on any fill
			healPrediction = true, -- incoming heals and shields on the health bar, for healers
			-- text on the bar: name, level and health, each placed, sized and fonted
			-- pos: left | center | right (inside the bar) | above | below (the frame)
			-- font: d3 (Exocet) | wow (Friz Quadrata) | narrow (Arial Narrow)
			healthText = "percent", -- none | percent | current | both | pctcur | max | maxpct | missing
			healthNumbers = "short", -- short (2.48M) | full (2,480,000) | raw (2480000)
			healthHideFull = false,
			healthPos = "right",
			healthFont = "wow",
			healthSize = 10,
			healthX = 0,
			healthY = 0,
			nameShow = true,
			namePos = "center",
			nameFont = "d3",
			nameSize = 13,
			nameX = 0,
			nameY = 0,
			surnames = true, -- players' first and last names
			levelShow = true,
			levelPos = "badge", -- badge: a D3 level plaque on the portrait frame (needs the portrait)
			levelFont = "wow",
			levelSize = 10,
			levelColor = "plain", -- plain | difficulty
			levelX = 0,
			levelY = 0,
			cast = true,
			tot = true, -- the target of target: a small monster bar with its portrait, right of the frame
			totPortrait = true, -- the target of target's portrait ring, left of its bar
			liquid = true, -- the globes' liquid moving in the health bar
			debuffs = true,
			maxDebuffs = 16,
			buffs = false,
			maxBuffs = 8,
			debuffSize = 26, -- debuff icon size (the aura* keys below are the debuffs' layout)
			auraPos = "below", -- below | above the bar | left | right of the frame (columns)
			auraAlign = "center", -- left | center | right edge of the bar
			auraGrow = "right", -- right | left, from a left or right edge
			auraPerLine = 12,
			auraSpacing = 4,
			auraX = 0,
			auraY = 0,
			-- the buffs' own layout; on the debuffs' side they start on the line after them
			buffPos = "below",
			buffAlign = "center",
			buffGrow = "right",
			buffSize = 26,
			buffPerLine = 12,
			buffSpacing = 4,
			buffX = 0,
			buffY = 0,
			buffSplit = false, -- set once the shared aura layout has been copied to the buffs
			moved = false,
			mx = 0,
			my = 0,
		},

		-- D3 party-style portraits, top left: your pet, and you if wanted
		portraits = {
			enabled = true,
			scale = 1.25, -- 1 = D3's own size
			player = false, -- your own portrait (no health bar: the globe is your health)
			pet = true,
			moved = false,
			mx = 0,
			my = 0,
		},

		-- party frames: your party members (and their pets) under your portrait
		party = {
			style = "globes", -- globes | slab | lintel | slim | bracket | tablet | d3 | none (Blizzard's party frames, or another addon's)
			scale = 1.25, -- 1 = the art's own size (the portraits above default to 1.25 too)
			spacing = 0, -- added to the gap between members; negative squeezes them together
			stone = 1, -- the slab's stone opacity: down to 0.55 or so for the see-through look
			pets = true,
			portrait3d = true, -- slab: the moving 3D bust in the socket when in view
			healthText = "percent", -- none | percent | current | missing
			healPrediction = true,
			debuffs = true,
			maxDebuffs = 4,
			buffs = true, -- your buffs on them (HoTs, shields)
			surnames = true, -- first and last names (Forever characters have both)
			maxBuffs = 3,
			dispelGlow = true, -- halo while a member has a debuff you can dispel
			threat = true,
			rangeFade = true,
			moved = false,
			mx = 0,
			my = 0,
		},

		-- stance / form bar
		stance = {
			enabled = true,
			scale = 0.62,
			spacing = 4,
			perLine = 10,
			alpha = 1,
			mouseover = false,
			moved = false,
			mx = 0,
			my = 0,
		},

		-- the vehicle exit / flight path stop button (ActionBar.lua)
		leaveButton = {
			size = 40,
			moved = false,
			mx = 0,
			my = 0,
		},

		-- totem bar: one socket per element (earth, fire, water, air)
		totems = {
			enabled = true,
			mode = "bar", -- bar (cast, pick totems from a flyout) | tracker (totems that are down)
			scale = 0.8, -- of a main-bar socket; icons about 30 px at console scale 1
			spacing = 4,
			vertical = false,
			flyout = "up", -- up | down: the picker, in the free row
			attach = "none", -- none | health | resource: ring that globe's rim
			arcHealth = 84, -- degrees, 90 = top; leans a little right, away from the demon
			arcResource = 96, -- leans a little left, away from the angel
			ringGap = 0, -- px past where the pips sit (skulls touching the rim)
			alpha = 1,
			mouseover = false,
			moved = false,
			mx = 0,
			my = 0,
			chosen = {}, -- element -> rank 1 spell ID of the totem its socket casts
			slots = {}, -- element -> totem slot, learned from totems seen down
		},

		-- trinkets (Trinket.lua): sockets for your two trinkets and a menu of the ones in your bags
		trinkets = {
			enabled = true,
			scale = 0.8, -- of a main-bar socket
			spacing = 4,
			vertical = false,
			menu = "hover", -- hover | shift | off: what opens the menu over a socket
			menuDir = "up", -- up | down | left | right
			menuPerLine = 4,
			menuScale = 0.85, -- menu sockets, of a trinket socket
			notify = true, -- the socket flashes when its trinket is ready again
			notifyChat = false, -- and says so in chat
			alpha = 1,
			mouseover = false,
			moved = false,
			mx = 0,
			my = 0,
		},

		-- weapon swing timers (SwingTimer.lua): a bar per weapon, filling to the next auto attack
		swing = {
			enabled = true,
			mainHand = true,
			offHand = true,
			ranged = true,
			show = "combat", -- combat (once a weapon swings in a fight) | always | swinging
			scale = 1.25, -- 100% is the D3 bar's own size
			width = 296, -- art pixels; the D3 bar is 296
			spacing = 6,
			icons = true,
			time = true,
			rangeFade = true, -- dim a bar while the target is out of that weapon's reach
			resets = "", -- more skills that restart the main-hand swing (SwingTimer.lua RESETS): names or IDs, commas between
			moved = false,
			mx = 0,
			my = 0,
		},

		-- the minimap (Map.lua), what it marks (MapPins.lua) and the overlay map (MapOverlay.lua)
		map = {
			style = "parchment", -- parchment | globe | fade | blizzard (the game's own, untouched)
			size = 190, -- the map's side or width across
			scale = 1,
			opacity = 0.92,
			zone = true,
			clock = true,
			headerPlace = "style", -- style (above; below on the globe's plaque) | above | below
			headerAlign = "style", -- style (right on the parchment, else centred) | left | center | right
			headerScale = 1,
			drawer = true, -- gather other addons' minimap buttons into one socket
			-- with the drawer off: other addons' buttons round the map's edge (Map.lua LayoutRim)
			-- shown or not, and on mouseover, with the buttons below (buttons.show)
			rim = {
				scale = 1,
				distance = 0, -- in or out from the style's own line round the map
				gap = 2,
				start = 225, -- degrees, 0 east, counting anticlockwise: where the first unpinned button sits
				clockwise = true, -- the way the unpinned ones run from there
				pos = {}, -- button name -> degrees, for buttons dragged to a spot
			},
			-- the buttons: mail, tracking, the calendar and the drawer
			buttons = {
				show = "always", -- always | hover (while the mouse is on the map or on them) | never
				side = "below", -- below | above | left | right | free (anywhere, with its own mover)
				align = "style", -- style (to the right on the parchment, else centred) | start | center | end
				vertical = false, -- for "free": a column rather than a row
				size = 26,
				gap = 4,
				x = 0, -- nudges from its place by the map
				y = 0,
				mail = true,
				tracking = true,
				calendar = true,
				queue = true, -- the game's queue eye, while you are queued
				moved = false,
				mx = 0,
				my = 0,
			},
			markers = true, -- things off the map, on its rim
			markerYards = true,
			party = true,
			raidCount = 5, -- in a raid, only this many of the nearest members are marked; 0 for none
			pings = true, -- minimap pings: a ripple, and a rim marker when off the map
			difficulty = true, -- inside an instance, its difficulty and size beside the time
			rangeYards = 40, -- a group member's distance turns green within this; 0 for never
			quests = true,
			trail = true,
			trailLength = 300, -- yards
			deathView = true, -- dead: a cold wash over the map and a gold line to your corpse
			autoZoom = true,
			-- the zoom kept for each way of getting about, 0 (widest) to 5; -1: not chosen yet, so
			-- the zoom in use the first time is taken. The wheel rewrites the one in force.
			zoom = { mounted = 0, indoors = 4, city = 2, foot = -1 },
			moved = false,
			mx = 0,
			my = 0,
			overlay = {
				enabled = true,
				mode = "ink", -- ink (the zone's map art) | live (the real minimap, enlarged)
				look = "ghost", -- ghost (grey light over the world) | painted (the art as it is)
				hold = true, -- shown while the key is held; off: the key toggles it
				cityInk = true, -- live mode: in cities and buildings, draw the zone's map instead
				size = 0.8, -- of the screen's height
				reach = 700, -- yards across, for ink
				opacity = 0.55,
				names = true,
				tether = 100, -- a thread to group members this many yards away; 0 for none
				offsetY = 0,
			},
		},

		-- the ally ring (AllyRing.lua): your group around your character, with their distance
		allyRing = {
			enabled = true,
			show = "pvp", -- pvp (flagged, or in a battleground) | combat | group (whenever grouped)
			maxYards = 80, -- allies farther than this are left off
			radius = 230, -- where the farthest sit, in screen units
			inner = 70, -- where the nearest sit
			scale = 1,
			opacity = 0.9,
			offsetY = 0,
			circle = true, -- the dashed "within reach" circle
			target = true, -- a halo round the pip of the group member you have targeted
			names = false,
			totems = true, -- your own totems pinned where you dropped them (RingTotems.lua)
			totemReach = true, -- each totem's reach outlined in its element's colour
			shareTotems = true, -- tell the group where your totems are (hidden addon messages)
			groupTotems = true, -- show totems group members running SanctuaryUI told us about
			totemMarks = true, -- dots by each ally's pip for the totems that reach them (true distance)
			selfDot = false, -- a pip for you in the middle; totems are then drawn true to it
			moved = false,
			mx = 0,
			my = 0,
		},

		-- damage meter (Meter.lua): the client's own tallies on forged rails
		meter = {
			enabled = true,
			style = "glass", -- glass (red glass header) | shadow (glass, dark panel behind) | plaque (red plate header)
			show = "always", -- always | combat | group
			view = "DamageDone", -- Meter.lua VIEWS key
			segment = "current", -- current | overall
			scale = 1, -- 100% is the mockup's size
			width = 560, -- rail length, in the art's pixels
			railHeight = 50, -- rail height, in the art's pixels
			textScale = 1, -- text size on the rails, on top of what the rail height gives
			font = "wow", -- names and numbers: d3 (Exocet) | wow (Friz Quadrata) | narrow (Arial Narrow); the meter's own, apart from any addon-wide font
			titleFont = "d3", -- the title strip: same choices
			analysisScale = 1, -- the analysis window (MeterAnalysis.lua), on top of its own base size
			-- its shape, in the art's pixels: size, and the widths of the fights and table panes
			analysis = { w = 2200, h = 1080, left = 360, mid = 1010 },
			history = true, -- save each fight per character (MeterHistory.lua)
			historyKeep = 50, -- how many, at most 250; the oldest go first
			-- the competitive side (MeterGlory.lua), all on your own screen
			glory = true,
			gloryLead = true, -- taking and losing the lead mid-fight
			gloryBanners = true, -- top damage, streaks and records when a fight ends
			glorySounds = false,
			gloryPlace = "auto", -- the line by the meter: auto (above, or below at the top of the screen) | above | below
			gloryStatues = true, -- the console statues' eyes while you lead
			gloryStreakRail = true, -- your rail turns molten on a streak of three
			gloryGroupOnly = true, -- lead changes only while in a group
			gloryAwards = true, -- awards in chat on leaving a dungeon or raid
			gloryScale = 1, -- the banner
			rival = "", -- a player's name to keep a tally against
			rows = 5,
			panelAlpha = 0.88, -- the dark panel of "shadow"
			ranks = true, -- numbered studs left of the rails
			goldLeader = true, -- first place on a gold rail
			pinSelf = true, -- keep you on the last rail when the list runs past you
			verdict = true, -- where you placed, under the list after a fight
			names = "first", -- first | full | firstInitial (First L.) | initialLast (F. Last)
			headers = true, -- column headings under the title strip
			moved = false,
			mx = 0,
			my = 0,
		},

		-- bank window
		bank = {
			enabled = true,
			columns = 14,
			slotSize = 38,
			spacing = 3,
			dividers = true, -- one section per bank tab
			quality = true,
			bagSlots = true,
			scale = 1,
			point = "TOPLEFT",
			x = 40,
			y = -120,
		},

		-- pie menus (PieMenu.lua): rings of skills that open at the mouse while a key is held
		pie = {
			scale = 1,
			rings = {}, -- [1-6] = { name = "", slices = { { kind = "spell"|"item"|"macro", id = n, name = "" } } }
		},

		-- bag window
		bags = {
			enabled = true,
			columns = 10,
			slotSize = 38,
			spacing = 3,
			dividers = false, -- each bag on its own lines, with a divider between bags
			quality = true, -- D3 quality backgrounds
			autoSellJunk = false,
			bagSlots = true, -- backpack + bag slots in a line with the search box
			backpackPos = "top", -- top | bottom: where the backpack's slots sit in the grid
			slotRowPos = "top", -- top | bottom: the bag slots and search box, above or under the items
			showKeys = false, -- the key slots in the grid, toggled by the keyring socket
			scale = 1,
			point = "BOTTOMRIGHT",
			x = -60,
			y = 260,
		},
	},
	char = {
		-- Trinket.lua auto-swap: per trinket socket, on/off and the item IDs in priority order.
		trinkets = {
			{ auto = false, list = {} },
			{ auto = false, list = {} },
		},
		-- MeterHistory.lua: saved fights, personal bests, the streak and the rival's tally.
		meter = {},
	},
	global = {
		-- LibDBIcon keeps the minimap button's angle and visibility here, shared by all profiles.
		minimap = { hide = false },
		-- How long each buff lasts, by spell ID and name, learned while buffs are readable.
		-- Lets the skill glow time a buff cast in combat, when the client hides buffs.
		buffLengths = {},
	},
}

-- Keys copied from the pre-profile flat SanctuaryUIDB.
local MIGRATE = { "point", "rel", "x", "y", "scale", "locked", "railMode", "numbers" }

-- Bring a profile saved by an older version up to date. Runs at login and whenever the
-- profile changes, so every profile gets it.
function ns.Migrate(p)
	-- auras used to be a plain on/off.
	if type(p.auras) ~= "table" then
		local auras = {}
		for k, v in pairs(ns.DEFAULTS.profile.auras) do
			auras[k] = v
		end
		auras.enabled = p.auras ~= false
		p.auras = auras
	end
	-- The target's health text used to be a percent on/off.
	if type(p.target) == "table" and p.target.percent ~= nil then
		-- (AceDB has already filled in the default, so "not set" looks like the default.)
		if p.target.percent == false and p.target.healthText == ns.DEFAULTS.profile.target.healthText then
			p.target.healthText = "none"
		end
		p.target.percent = nil
	end
	-- Target buffs and debuffs used to share one layout; the buffs start with a copy of it.
	if type(p.target) == "table" and not rawget(p.target, "buffSplit") then
		local copy = { auraPos = "buffPos", auraAlign = "buffAlign", auraGrow = "buffGrow", debuffSize = "buffSize", auraPerLine = "buffPerLine", auraSpacing = "buffSpacing", auraX = "buffX" }
		for from, to in pairs(copy) do
			local value = rawget(p.target, from)
			if value ~= nil and p.target[to] == ns.DEFAULTS.profile.target[to] then
				p.target[to] = value
			end
		end
		p.target.buffSplit = true
	end
	-- The console used to float 28 px up; it now sits on the screen edge by default.
	if p.y == 28 and p.point == "BOTTOM" and p.rel == "BOTTOM" and not p.movedConsole then
		p.y = 0
	end
end

function ns.InitDB()
	if ns.db then return ns.db end
	local old
	if type(SanctuaryUIDB) == "table" and not SanctuaryUIDB.profileKeys then
		old = SanctuaryUIDB
		SanctuaryUIDB = nil
	end
	-- auras used to be a plain on/off. AceDB replaces a false with its default table, turning
	-- them back on, so that has to be converted before AceDB sees it.
	if type(SanctuaryUIDB) == "table" and type(SanctuaryUIDB.profiles) == "table" then
		for _, saved in pairs(SanctuaryUIDB.profiles) do
			if type(saved) == "table" and saved.auras == false then saved.auras = { enabled = false } end
		end
	end
	local AceDB = LibStub("AceDB-3.0")
	ns.db = AceDB:New("SanctuaryUIDB", ns.DEFAULTS, true)
	if old then
		local p = ns.db.profile
		for _, key in ipairs(MIGRATE) do
			if old[key] ~= nil then
				p[key] = old[key]
			end
		end
		if type(old.rows) == "table" then
			for n = 2, 4 do
				if type(old.rows[n]) == "table" and old.rows[n].enabled ~= nil then
					p.rows[n].enabled = old.rows[n].enabled
				end
			end
		elseif old.showExtra ~= nil then
			p.rows[2].enabled = old.showExtra
		end
	end
	ns.Migrate(ns.db.profile)
	local function changed()
		ns.Migrate(ns.db.profile)
		ns.Refresh()
	end
	ns.db.RegisterCallback(ns, "OnProfileChanged", changed)
	ns.db.RegisterCallback(ns, "OnProfileCopied", changed)
	ns.db.RegisterCallback(ns, "OnProfileReset", changed)
	return ns.db
end

-- The focus frame: the target frame's settings, for the focus unit (TargetPlate.lua builds both),
-- a little smaller and with a shorter debuff row, and no target of target by default.
do
	local focus = {}
	for k, v in pairs(ns.DEFAULTS.profile.target) do focus[k] = v end
	focus.scale = 0.8
	focus.tot = false
	focus.maxDebuffs = 8
	focus.auraPerLine = 8
	ns.DEFAULTS.profile.focus = focus
end

function ns.DB()
	return (ns.db or ns.InitDB()).profile
end

-- Apply every setting. Secure frames (buttons, paging, visibility, layout) cannot change in
-- combat, so a refresh asked for in combat runs when combat ends.
function ns.Refresh()
	if not ns.Cluster then return end
	if InCombatLockdown() then
		if not ns.pendingRefresh then
			ns.Print("settings will apply when combat ends")
			ns.Log("refresh deferred by combat")
		end
		ns.pendingRefresh = true
		return
	end
	ns.pendingRefresh = nil
	ns.Log("refresh")
	local function Run(label, fn)
		if not fn then return end
		local ok, err = ns.Try("refresh " .. label, fn)
		if not ok then
			ns.Print(label .. " refresh failed: " .. tostring(err))
		end
	end
	Run("fonts", ns.Fonts and ns.Fonts.Apply)
	Run("position", ns.ApplyPosition)
	Run("blizzard", ns.Blizzard and ns.Blizzard.Hide)
	Run("buttons", ns.ActionBar and ns.ActionBar.ApplySettings)
	Run("active skills", ns.ActiveSkill and ns.ActiveSkill.ApplySettings)
	Run("proc highlight", ns.ProcGlow and ns.ProcGlow.ApplySettings)
	Run("layout", ns.Layout)
	Run("globes", ns.Globes and ns.Globes.ApplySettings)
	Run("globe auras", ns.GlobeAura and ns.GlobeAura.ApplySettings)
	Run("rail", ns.Experience and ns.Experience.Update)
	Run("auras", ns.Auras and ns.Auras.ApplySettings)
	Run("target", ns.TargetPlate and ns.TargetPlate.ApplySettings)
	Run("focus", ns.FocusPlate and ns.FocusPlate.ApplySettings)
	Run("portraits", ns.Portraits and ns.Portraits.ApplySettings)
	Run("party", ns.Party and ns.Party.ApplySettings)
	Run("pollution", ns.Pollution and ns.Pollution.ApplySettings)
	Run("statue eyes", ns.StatueEyes and ns.StatueEyes.ApplySettings)
	Run("menu", ns.Menu and ns.Menu.ApplySettings)
	Run("bags", ns.Bags and ns.Bags.ApplySettings)
	Run("bank", ns.Bank and ns.Bank.ApplySettings)
	Run("stance", ns.Stance and ns.Stance.ApplySettings)
	Run("totems", ns.Totem and ns.Totem.ApplySettings)
	Run("trinkets", ns.Trinket and ns.Trinket.ApplySettings)
	Run("swing timer", ns.Swing and ns.Swing.ApplySettings)
	Run("damage meter", ns.Meter and ns.Meter.ApplySettings)
	Run("minimap", ns.Map and ns.Map.ApplySettings)
	Run("overlay map", ns.MapOverlay and ns.MapOverlay.ApplySettings)
	Run("ally ring", ns.AllyRing and ns.AllyRing.ApplySettings)
	Run("pie menus", ns.Pie and ns.Pie.ApplySettings)
	-- Last: buttons are sized by the layout and the stance and totem settings.
	Run("cooldown numbers", ns.ActionBar and ns.ActionBar.StyleCountdowns)
end
