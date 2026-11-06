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
		locked = true,
		hideMicroMenu = true,

		-- globes
		numbers = "combat", -- on | combat | hover | off
		numbersMax = true,
		numberSize = 22,
		liquidAnimate = true,
		liquidSpeed = 1,
		lowHealthPulse = true,

		-- rail
		railMode = "auto", -- auto | xp | rep
		railRested = true,

		-- action buttons (main bar and rows)
		buttons = {
			hotkeys = true,
			macroNames = false,
			range = "button", -- button | hotkey | none
			tooltips = "enabled", -- enabled | nocombat | disabled
			grid = true,
			cooldownNumbers = "cvar", -- cvar | show | hide
			lock = false, -- locked buttons still pick up with the pickup modifier (Shift)
			activeGlow = true, -- D3 burning frame while a skill's effect is up
			activeTimer = true, -- D3 tab in the socket with a bar draining to the end
			activeTimerPos = "top", -- top | bottom edge of the socket
			activeMax = 60, -- seconds; longer buffs don't light their skill
			activeEndless = false, -- buffs with no duration (stances, auras, aspects) light their skill too
		},

		-- main bar paging (rows with source "main" follow it too)
		paging = {
			possess = true,
			barPaging = true,
			stances = true,
			forms = { ["*"] = true },
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
				scale = 0.8,
				spacing = 5,
				visibility = "always", -- always | combat | nocombat | custom
				custom = "",
				alpha = 1,
				mouseover = false,
				perLine = 12,
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
			bagSlots = true, -- backpack + bag slots along the top of the window
			scale = 1,
			point = "BOTTOMRIGHT",
			x = -60,
			y = 260,
		},
	},
	global = {
		-- LibDBIcon keeps the minimap button's angle and visibility here, shared by all profiles.
		minimap = { hide = false },
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
		end
		ns.pendingRefresh = true
		return
	end
	ns.pendingRefresh = nil
	local function Run(label, fn)
		if not fn then return end
		local ok, err = pcall(fn)
		if not ok then
			ns.Print(label .. " refresh failed: " .. tostring(err))
		end
	end
	Run("position", ns.ApplyPosition)
	Run("blizzard", ns.Blizzard and ns.Blizzard.Hide)
	Run("buttons", ns.ActionBar and ns.ActionBar.ApplySettings)
	Run("active skills", ns.ActiveSkill and ns.ActiveSkill.ApplySettings)
	Run("layout", ns.Layout)
	Run("globes", ns.Globes and ns.Globes.ApplySettings)
	Run("rail", ns.Experience and ns.Experience.Update)
	Run("auras", ns.Auras and ns.Auras.ApplySettings)
	Run("menu", ns.Menu and ns.Menu.ApplySettings)
	Run("bags", ns.Bags and ns.Bags.ApplySettings)
	Run("bank", ns.Bank and ns.Bank.ApplySettings)
	Run("stance", ns.Stance and ns.Stance.ApplySettings)
	Run("totems", ns.Totem and ns.Totem.ApplySettings)
end
