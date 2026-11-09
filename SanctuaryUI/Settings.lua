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
		scale = 1,
		globesSeparate = false, -- globes keep globeScale instead of following the console's scale
		globeScale = 1,
		iconSize = 1, -- console skill icons, of their socket; below 1 the stone shows around them
		locked = true,
		snapping = true, -- unlocked frames snap to each other and the screen edges while dragged
		grid = false, -- Edit Mode style grid while unlocked; frames snap to its lines
		gridSize = 40, -- grid spacing, UIParent units out from the screen's centre
		hideMicroMenu = true,

		-- globes
		numbers = "combat", -- on | combat | hover | off
		numbersMax = true,
		numberSize = 22,
		liquidAnimate = true,
		liquidStyle = "classic", -- classic: D3's layered tiles; rendered: the Blender flipbooks (Liquid.lua)
		pollution = true, -- debuffs colour the health globe until they end or are cleansed (Pollution.lua)
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
			style = "d3", -- d3 (D3's monster bar) | lintel | slim | bracket | tablet
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
			style = "globes", -- globes | slab | none (Blizzard's party frames, or another addon's)
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
			scale = 1,
			point = "BOTTOMRIGHT",
			x = -60,
			y = 260,
		},
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
	Run("portraits", ns.Portraits and ns.Portraits.ApplySettings)
	Run("party", ns.Party and ns.Party.ApplySettings)
	Run("pollution", ns.Pollution and ns.Pollution.ApplySettings)
	Run("menu", ns.Menu and ns.Menu.ApplySettings)
	Run("bags", ns.Bags and ns.Bags.ApplySettings)
	Run("bank", ns.Bank and ns.Bank.ApplySettings)
	Run("stance", ns.Stance and ns.Stance.ApplySettings)
	Run("totems", ns.Totem and ns.Totem.ApplySettings)
	-- Last: buttons are sized by the layout and the stance and totem settings.
	Run("cooldown numbers", ns.ActionBar and ns.ActionBar.StyleCountdowns)
end
