SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.Options = ns.Options or {}

-- The options window (AceConfig). /sanctuary opens it standalone; it is also listed under
-- Esc > Options > AddOns. Every change goes through ns.Refresh(), which waits for combat
-- to end before touching secure frames.

local APP = "SanctuaryUI"

local function DB()
	return ns.DB()
end

local function Changed()
	ns.Refresh()
end

-- get/set for a key in the profile, or in a sub-table of it.
local function Field(path, key)
	local function tbl()
		local t = DB()
		if path then
			for part in path:gmatch("[^.]+") do
				t = t[tonumber(part) or part]
			end
		end
		return t
	end
	return function() return tbl()[key] end, function(_, value)
		tbl()[key] = value
		Changed()
	end
end

local function Toggle(order, name, desc, path, key)
	local get, set = Field(path, key)
	return { type = "toggle", order = order, name = name, desc = desc, get = get, set = set, width = "full" }
end

local function Range(order, name, desc, path, key, min, max, step, isPercent)
	local get, set = Field(path, key)
	return { type = "range", order = order, name = name, desc = desc, get = get, set = set, min = min, max = max, step = step, isPercent = isPercent }
end

local function Select(order, name, desc, path, key, values, sorting)
	local get, set = Field(path, key)
	return { type = "select", order = order, name = name, desc = desc, get = get, set = set, values = values, sorting = sorting }
end

-- Greys a target aura setting out while its buffs / debuffs are off.
local function TargetAura(key, option)
	option.disabled = function() return not ns.DB().target[key] end
	return option
end

-- A target text option, greyed out while that text is off.
local function TargetText(key, option)
	option.disabled = function()
		local value = ns.DB().target[key]
		return value == false or value == "none"
	end
	return option
end

local HEALTH_TEXTS = {
	none = "Nothing",
	percent = "Percent (62%)",
	current = "Hitpoints (1.54M)",
	both = "Hitpoints | percent",
	pctcur = "Percent | hitpoints",
	max = "Hitpoints / max",
	maxpct = "Hitpoints / max | percent",
	missing = "Missing hitpoints (-940K)",
}
local HEALTH_ORDER = { "none", "percent", "current", "both", "pctcur", "max", "maxpct", "missing" }
local POS_ORDER = { "left", "center", "right", "above", "below" }
local TEXT_POSITIONS = { left = "In the bar, left", center = "In the bar, centre", right = "In the bar, right", above = "Above the frame", below = "Below the frame" }
local LEVEL_POSITIONS = { badge = "Plaque on the portrait", left = "In the bar, left", center = "In the bar, centre", right = "In the bar, right", above = "Above the frame", below = "Below the frame" }
local LEVEL_ORDER = { "badge", "left", "center", "right", "above", "below" }
local TEXT_FONTS = { d3 = "Diablo (Exocet)", wow = "WoW (Friz Quadrata)", narrow = "Arial Narrow" }

local function Header(order, name)
	return { type = "header", order = order, name = name }
end

local function Note(order, text)
	return { type = "description", order = order, name = text, fontSize = "medium" }
end

-- Options > Globe auras: the look, one page per class of buffs (yours first), and a test
-- page that plays any class's casts.
local function GlobeAuraArgs()
	local DATA = ns.WatchData
	local _, myClass = UnitClass("player")
	local testClass = myClass
	local function Refresh()
		local registry = LibStub("AceConfigRegistry-3.0", true)
		if registry then registry:NotifyChange(APP) end
	end
	local function off() return not DB().globeAuras.enabled end

	local args = {
		intro = Note(1, "Light on the globes while a buff is up: light radiating from behind a globe, a crystal shell over it while a shield holds, or light pouring into it. In combat this client hides your buffs from addons, so they are followed from your casts (and, for shields, from the game's absorb amount, which it still shows). A buff cancelled by hand or purged in combat can stay lit until its time would have run out; the first reading after combat puts it right. /sanctuary watch shows what is known."),
		enabled = Toggle(2, "Enabled", nil, "globeAuras", "enabled"),
		look = Header(10, "Look"),
		intensity = Range(11, "Brightness", nil, "globeAuras", "intensity", 0.25, 1.5, 0.05, true),
		rays = Toggle(12, "Rays", "God rays turning slowly behind a radiating globe.", "globeAuras", "rays"),
		sparks = Toggle(13, "Sparks", "Motes of light rising off a radiating globe's rim.", "globeAuras", "sparks"),
		catch = Toggle(14, "Light on the glass", "Radiance wraps round onto the top of the globe's glass.", "globeAuras", "catch"),
		settleLong = Toggle(15, "Long buffs settle down", "Buffs kept up for minutes (Lightning Shield, Inner Fire) light up in full when cast, then calm to a quiet glow after a few seconds. They still flare when recast, discharge when their charges are spent and blink in their last seconds.", "globeAuras", "settleLong"),
	}

	-- One page per class, with your class first.
	for i, class in ipairs(DATA.CLASSES) do
		local page = {
			type = "group",
			order = class == myClass and 20 or 21 + i,
			name = DATA.CLASS_NAMES[class] .. (class == myClass and " (you)" or ""),
			disabled = off,
			args = {},
		}
		local n = 0
		for _, effect in ipairs(DATA.EFFECTS) do
			if effect.class == class then
				n = n + 1
				page.args[effect.key] = {
					type = "toggle",
					order = n,
					name = effect.label,
					desc = effect.desc:sub(1, 1):upper() .. effect.desc:sub(2) .. ".",
					width = "full",
					get = function() return DB().globeAuras.effects[effect.key] end,
					set = function(_, value)
						DB().globeAuras.effects[effect.key] = value
						Changed()
					end,
				}
			end
		end
		args["class" .. class] = page
	end

	-- Test: any class's casts, played through the same path as real ones.
	local testArgs = {
		note = Note(1, "Play casts yourself, on any class: your real buffs and casts are ignored while testing, nothing is learned or saved, and mana effects show on whatever your resource globe holds. From chat or a macro: /sanctuary aura <name> (\"shield wall\", \"lightning\"), or break, spend, judge, fade, clear, die, off."),
		mode = {
			type = "toggle", order = 2, name = "Test mode", width = "full",
			get = function() return ns.Watch.Testing() end,
			set = function(_, value) ns.Watch.SetTest(value) end,
		},
		length = Range(3, "Test buffs last (seconds)", "Real buffs keep their own lengths; shorter shows the whole life of an effect sooner.", "globeAuras", "testLength", 5, 60, 1),
		class = {
			type = "select", order = 4, name = "Class",
			values = function()
				local values = {}
				for _, class in ipairs(DATA.CLASSES) do values[class] = DATA.CLASS_NAMES[class] end
				return values
			end,
			sorting = DATA.CLASSES,
			get = function() return testClass end,
			set = function(_, value) testClass = value end,
		},
		casts = { type = "header", order = 10, name = "Cast" },
		moments = { type = "header", order = 60, name = "Moments" },
		preview = {
			type = "toggle", order = 80, name = "Showcase loop", width = "full",
			desc = "Loops a run of effects through test mode: Lightning Shield, Innervate, a Power Word: Shield that takes a hit and shatters, Life Tap, Arcane Power, Divine Shield, then everything running out.",
			get = function() return ns.GlobeAura.preview end,
			set = function(_, value) ns.GlobeAura.SetPreview(value) end,
		},
	}
	for i, effect in ipairs(DATA.EFFECTS) do
		testArgs["cast" .. effect.key] = {
			type = "execute", order = 10 + i / 100, name = effect.label,
			desc = effect.look == "flare" and "Plays the burst." or "Casts it on you. Cast it again while it is up to recast it.",
			hidden = function() return effect.class ~= testClass end,
			func = function()
				ns.Watch.Test(effect.key)
				Refresh()
			end,
		}
	end
	local moments = {
		{ "judge", "Judgement", "Spends the seal: its light bursts outward and goes.", function() return testClass ~= "PALADIN" end },
		{ "break", "Break shield", "The shield breaks and shatters." },
		{ "spend", "Spend charges", "A charge buff (Lightning Shield, Inner Fire) runs out of charges." },
		{ "hit", "Shield takes a hit", "The shell's facets flash, as when an absorb soaks a blow." },
		{ "fade", "Last seconds", "Jumps everything lit to 6.5 seconds left, to watch it gutter and run out." },
		{ "clear", "Clear", "Everything goes out quietly, as when a buff is cancelled." },
		{ "die", "Die", "Everything goes out, as on death." },
	}
	for i, m in ipairs(moments) do
		testArgs["m" .. m[1]] = {
			type = "execute", order = 60 + i, name = m[2], desc = m[3], hidden = m[4],
			func = function()
				if m[1] == "hit" then
					if not ns.GlobeAura.Hit() then ns.Print("test: no shield up to take the hit") end
				else
					ns.Watch.Test(m[1])
				end
				Refresh()
			end,
		}
	end
	args.test = { type = "group", order = 19, name = "Test", args = testArgs }
	return args
end

-- CVar toggles (Blizzard settings that also drive the action buttons).
local function CVarToggle(order, name, desc, cvar)
	local GetCVar = C_CVar and C_CVar.GetCVar or GetCVar
	local SetCVar = C_CVar and C_CVar.SetCVar or SetCVar
	return {
		type = "toggle",
		order = order,
		name = name,
		desc = desc,
		width = "full",
		get = function() return GetCVar(cvar) == "1" end,
		set = function(_, value)
			if InCombatLockdown() then
				ns.Print("cannot change that in combat")
				return
			end
			SetCVar(cvar, value and "1" or "0")
			Changed()
		end,
	}
end

---------------------------------------------------------------------------
-- Keybinding widgets

local function SaveBindings_()
	local set = GetCurrentBindingSet and GetCurrentBindingSet() or 1
	if SaveBindings then
		SaveBindings(set)
	elseif AttemptToSaveBindings then
		AttemptToSaveBindings(set)
	end
end

-- A keybinding field for a Blizzard binding name, or a CLICK binding on a button.
local function KeyField(order, name, binding, buttonName)
	local target = binding or ("CLICK " .. buttonName .. ":Keybind")
	return {
		type = "keybinding",
		order = order,
		name = name,
		get = function() return GetBindingKey(target) end,
		set = function(_, key)
			if InCombatLockdown() then
				ns.Print("cannot change keybinds in combat")
				return
			end
			while GetBindingKey(target) do
				SetBinding(GetBindingKey(target), nil)
			end
			if key and key ~= "" then
				if binding then
					SetBinding(key, binding)
				else
					SetBindingClick(key, buttonName, "Keybind")
				end
			end
			SaveBindings_()
			ns.ActionBar.ReassignBindings()
			ns.Menu.ReassignBindings()
		end,
	}
end

local function KeybindArgs()
	local args = {
		intro = Note(1, "Hover-binding works like Bartender4: turn it on, hover a button, press a key. Escape clears the button's binding. Or set keys directly below."),
		mode = {
			type = "execute",
			order = 2,
			name = "Hover-bind mode",
			desc = "Toggle LibKeyBound's hover-binding mode.",
			func = function()
				local KeyBound = LibStub("LibKeyBound-1.0", true)
				if KeyBound and not InCombatLockdown() then
					KeyBound:Toggle()
				end
			end,
		},
		hearth = KeyField(3, "Hearthstone", "SANCTUARYUIHEARTH"),
		main = { type = "group", inline = true, order = 10, name = "Main bar", args = {} },
	}
	for i = 1, 9 do
		args.main.args["b" .. i] = KeyField(i, "Socket " .. i, "ACTIONBUTTON" .. i)
	end
	if ns.Totem and ns.Totem.HasTotems() then
		local group = { type = "group", inline = true, order = 9, name = "Totem bar", args = {} }
		for i, element in ipairs(ns.Totem.ELEMENTS) do
			group.args["t" .. i] = KeyField(i, element.label .. " totem", "SANCTUARYUITOTEM" .. i)
		end
		args.totems = group
	end
	for idx, n in ipairs(ns.ActionBar.ROW_IDS) do
		local opt = DB().rows[n]
		if opt.enabled then
			local spec = ns.ActionBar.RowSpec(n)
			local group = { type = "group", inline = true, order = 10 + idx, name = "Bar " .. n, args = {} }
			for i = 1, spec.count do
				local binding = spec.binding and spec.binding:format(spec.bindingOffset + i)
				group.args["b" .. i] = KeyField(i, "Button " .. i, binding, ("SanctuaryUIRow%dButton%d"):format(n, i))
			end
			args["row" .. n] = group
		end
	end
	return args
end

---------------------------------------------------------------------------
-- Rows

local VISIBILITY = {
	always = "Always",
	combat = "In combat only",
	nocombat = "Out of combat only",
	custom = "Custom conditional",
}

local function SourceValues(n)
	-- Main bar 10-12 has three actions, too few for the console's twelve sockets.
	local values = {}
	if not (n and DB().rows[n].docked) then
		values.main = "Main bar 10-12 (pages with the main bar)"
	end
	for page, name in pairs(ns.ActionBar.PAGE_NAMES) do
		values[page] = name
	end
	return values
end

-- A bar setting that only applies outside the console.
local function Undocked(n, option)
	option.disabled = function() return DB().rows[n].docked end
	return option
end

local function RowGroup(n, order)
	local path = "rows." .. n
	local opt = function() return DB().rows[n] end
	local source = Select(2, "Source", "Which actions this bar shows. Pages 3-6 and 13-15 keep the keybinds you set for those bars in Key Bindings.", path, "source", function() return SourceValues(n) end)
	source.get = function()
		local value = opt().source
		return value == "main" and "main" or tonumber(value)
	end
	return {
		type = "group",
		order = order,
		name = "Bar " .. n,
		args = {
			enabled = Toggle(1, "Enabled", nil, path, "enabled"),
			docked = (function()
				local option = Toggle(1.5, "In the console", "Set this bar into the console: a row of twelve stone sockets between the globes, with the XP rail and the centre skull lifted to sit on top. Up to two bars, stacked in bar order. In the console the bar fills all twelve sockets, so a bar on Main bar 10-12 (three actions) moves to a free action page and takes its spells and keys with it. Size, spacing and position below don't apply while it's in the console.", path, "docked")
				option.set = function(_, value)
					opt().docked = value
					if value then
						local page = ns.ActionBar.LeaveMainSource(n)
						if page then
							ns.Print(("bar %d now shows action page %d, so all twelve console sockets take spells"):format(n, page))
						end
					end
					Changed()
				end
				return option
			end)(),
			source = source,
			-- The main bar has 12 actions and the console holds 9, so a main-bar row has at most
			-- 3. Two sliders so the range matches the source.
			count = {
				type = "range",
				order = 3,
				name = "Buttons",
				min = 1,
				max = 12,
				step = 1,
				get = function() return ns.ActionBar.RowSpec(n).count end,
				set = function(_, value)
					opt().count = value
					Changed()
				end,
				disabled = function() return ns.ActionBar.DockIndex(n) ~= nil end,
				hidden = function() return opt().source == "main" end,
			},
			countMain = {
				type = "range",
				order = 3,
				name = "Buttons",
				min = 1,
				max = 3,
				step = 1,
				get = function() return ns.ActionBar.RowSpec(n).count end,
				set = function(_, value)
					opt().count = value
					Changed()
				end,
				hidden = function() return opt().source ~= "main" end,
			},
			countNote = {
				type = "description",
				order = 4,
				name = "The console holds main-bar actions 1-9, so this source has 3 left (10-12). Pick an action page as the source for a full 12-button bar.",
				hidden = function() return opt().source ~= "main" end,
			},
			countDocked = {
				type = "description",
				order = 4.5,
				name = "In the console this bar fills all twelve sockets.",
				hidden = function() return not ns.ActionBar.DockIndex(n) end,
			},
			size = Header(10, "Size"),
			scale = Undocked(n, Range(11, "Button size", "Relative to a main-bar socket.", path, "scale", 0.5, 1.2, 0.01, true)),
			spacing = Undocked(n, Range(12, "Spacing", nil, path, "spacing", 0, 20, 1)),
			perLine = Undocked(n, Range(13, "Buttons per line", "Wrap the bar into a grid. 1 makes it vertical.", path, "perLine", 1, 12, 1)),
			place = Header(15, "Position"),
			placeNote = {
				type = "description",
				order = 16,
				name = function()
					if opt().docked then
						return ns.ActionBar.DockIndex(n) and "In the console." or "In the console, but two bars are there already: this one stacks above."
					end
					if opt().moved then
						return "Moved: this bar keeps its own position."
					end
					return "Stacked above the console. Turn off General > Lock frames, then drag the bar's mover to place it anywhere."
				end,
			},
			resetPos = {
				type = "execute",
				order = 17,
				name = "Reset position",
				desc = "Put the bar back in the stack above the console.",
				func = function() ns.ActionBar.ResetRowPosition(n) end,
				disabled = function() return not opt().moved or opt().docked end,
			},
			show = Header(20, "Visibility"),
			visibility = Select(21, "Show", nil, path, "visibility", VISIBILITY),
			custom = (function()
				local get, set = Field(path, "custom")
				return {
					type = "input",
					order = 22,
					name = "Custom conditional",
					desc = "A macro conditional, e.g. [combat][mod:shift] show; hide",
					width = "full",
					get = get,
					set = set,
					hidden = function() return opt().visibility ~= "custom" end,
				}
			end)(),
			alpha = Range(23, "Opacity", nil, path, "alpha", 0, 1, 0.05, true),
			mouseover = Toggle(24, "Show on mouseover only", "Invisible until the mouse is over the bar.", path, "mouseover"),
		},
	}
end

---------------------------------------------------------------------------
-- Paging

local function PagingArgs()
	local path = "paging"
	local args = {
		intro = Note(1, "Paging swaps the main bar (and bars set to follow it) to another action page. Page numbers follow Blizzard's action pages."),
		possess = Toggle(2, "Vehicle, possess and override bars", "Swap to the vehicle or possess bar when one is active.", path, "possess"),
		barPaging = Toggle(3, "Action bar paging", "Follow Blizzard's bar page (Shift + number, Shift + mouse wheel).", path, "barPaging"),
		stances = Toggle(4, "Stance and form pages", nil, path, "stances"),
		mods = Header(10, "Modifier pages (0 = off)"),
		ctrl = Range(11, "Ctrl page", nil, path, "ctrl", 0, 10, 1),
		alt = Range(12, "Alt page", nil, path, "alt", 0, 10, 1),
		shift = Range(13, "Shift page", nil, path, "shift", 0, 10, 1),
		adv = Header(20, "Advanced"),
		custom = (function()
			local get, set = Field(path, "custom")
			return {
				type = "input",
				order = 21,
				name = "Custom page conditional",
				desc = "Replaces everything above, e.g. [mod:ctrl]2;[bonusbar:1]7;0. Leave empty to use the settings above.",
				width = "full",
				multiline = 2,
				get = get,
				set = set,
			}
		end)(),
		current = {
			type = "description",
			order = 22,
			name = function() return "|cffd8b86aIn use:|r " .. ns.ActionBar.PageDriver() end,
		},
	}
	local _, class = UnitClass("player")
	local map = ns.ActionBar.CLASS_PAGES[class]
	if map then
		args.forms = { type = "group", inline = true, order = 5, name = "Forms", args = {} }
		for i, entry in ipairs(map) do
			local key = class .. "." .. entry.key
			args.forms.args[entry.key] = {
				type = "toggle",
				order = i,
				name = ("%s (page %d)"):format(entry.label, entry.page),
				get = function() return DB().paging.forms[key] end,
				set = function(_, value)
					DB().paging.forms[key] = value
					Changed()
				end,
				disabled = function() return not DB().paging.stances end,
			}
		end
	end
	return args
end

-- Bars > Main bar: the console's nine sockets, their icon size and paging.
local function MainBarArgs()
	local args = PagingArgs()
	args.size = Header(0.1, "Size")
	args.iconSize = Range(0.2, "Icon size", "Skill icons in the console's sockets, docked bars included. Below 100% they sit centred in the socket with its stone around them; the console keeps its size.", nil, "iconSize", 0.6, 1, 0.01, true)
	args.pagingHeader = Header(0.5, "Paging")
	return args
end

---------------------------------------------------------------------------

local function Build()
	local options = {
		type = "group",
		name = "SanctuaryUI",
		childGroups = "tree",
		args = {
			general = {
				type = "group",
				order = 1,
				name = "General",
				args = {
					console = Header(1, "Console"),
					locked = Toggle(2, "Lock frames", "When unlocked, drag the console to move it, and drag a bar's mover to move that bar.", nil, "locked"),
					snapping = Toggle(2.5, "Bar snapping", "While dragging, the console, bars and other frames snap to each other's edges and centres and to the screen's edges and centre, as in Bartender4. Hold Shift while dragging to place one freely.", nil, "snapping"),
					grid = Toggle(2.6, "Show grid", "While frames are unlocked, draw a grid like Edit Mode's, its centre lines brighter, and snap frames' edges and centres to its lines (with Bar snapping on).", nil, "grid"),
					gridSize = (function()
						local option = Range(2.7, "Grid spacing", "Distance between grid lines, counted out from the screen's centre.", nil, "gridSize", ns.Snap.GRID_MIN, ns.Snap.GRID_MAX, 5)
						option.disabled = function() return not DB().grid end
						return option
					end)(),
					scale = Range(3, "Scale", "The console: its bars, menu and rail, and the globes unless they are scaled separately.", nil, "scale", 0.5, 1.8, 0.01, true),
					globesSeparate = Toggle(3.1, "Scale globes separately", "Give the globes their own scale. They stay on the ends of the bar, bottoms level, whatever its size.", nil, "globesSeparate"),
					globeScale = (function()
						local option = Range(3.2, "Globe scale", "The globes and their statues.", nil, "globeScale", 0.5, 1.8, 0.01, true)
						option.disabled = function() return not DB().globesSeparate end
						return option
					end)(),
					reset = {
						type = "execute",
						order = 4,
						name = "Reset position",
						func = function()
							local db = DB()
							db.point, db.rel, db.x, db.y = "BOTTOM", "BOTTOM", 0, 0
							Changed()
						end,
					},
					blizzard = Header(10, "Blizzard frames"),
					hideMicroMenu = Toggle(11, "Hide Blizzard micro menu", "The console's menu buttons replace it. If it comes back misplaced after turning this off, /reload.", nil, "hideMicroMenu"),
					extras = Header(20, "Extras"),
					minimap = {
						type = "toggle",
						order = 24,
						name = "Minimap button",
						desc = "Left-click opens these options, right-click locks or unlocks frames. Drag it around the minimap.",
						get = function() return not ns.db.global.minimap.hide end,
						set = function(_, value) ns.Minimap.SetShown(value) end,
					},
					hearthItem = {
						type = "input",
						order = 23,
						name = "Town portal item ID",
						desc = "The item the portal socket uses. 6948 is the Hearthstone.",
						get = function() return tostring(DB().hearthItem) end,
						set = function(_, value)
							DB().hearthItem = tonumber(value) or 6948
							Changed()
						end,
						validate = function(_, value)
							return tonumber(value) and true or "Enter an item ID number."
						end,
					},
				},
			},
			globes = {
				type = "group",
				order = 2,
				name = "Globes",
				args = {
					text = Header(1, "Numbers"),
					numbers = Select(2, "Show numbers", nil, nil, "numbers", { on = "Always", combat = "In combat (and on mouseover)", hover = "On mouseover (like D3)", off = "Never" }),
					numbersMax = Toggle(3, "Show maximum under the value", nil, nil, "numbersMax"),
					numberSize = Range(4, "Number size", nil, nil, "numberSize", 12, 34, 1),
					liquid = Header(10, "Liquid"),
					liquidAnimate = Toggle(11, "Swirl", "Animate the globe liquid.", nil, "liquidAnimate"),
					liquidSpeed = Range(12, "Swirl speed", nil, nil, "liquidSpeed", 0.25, 3, 0.05, true),
					lowHealthPulse = Toggle(13, "Low health heartbeat", "The health globe pulses below 35%, faster as it empties.", nil, "lowHealthPulse"),
					lowHealthAgitate = Toggle(14, "Restless at low health", "Below half health the health globe's liquid turns faster and sloshes on its own, more and more as health falls to 10%.", nil, "lowHealthAgitate"),
					prediction = Header(20, "Prediction"),
					healPrediction = Toggle(21, "Incoming heals", "Heals on their way to you show as pale green liquid poured on top of the health globe.", nil, "healPrediction"),
					absorbPrediction = Toggle(21.5, "Absorb shields", "Damage shields (Power Word: Shield and the like) show as silver liquid above your health and incoming heals. A shield bigger than the room left, as at full health, lights a silver glow round the inside of the globe.", nil, "absorbPrediction"),
					costPrediction = Toggle(22, "Spell cost", "While you cast, the part of your resource the spell will spend lights up at the top of the resource globe.", nil, "costPrediction"),
				},
			},
			globeAuras = {
				type = "group",
				order = 2.1,
				name = "Globe auras",
				args = GlobeAuraArgs(),
			},
			rail = {
				type = "group",
				order = 3,
				name = "Experience & Reputation",
				args = {
					railMode = Select(1, "Rail shows", nil, nil, "railMode", {
						auto = "Experience, then reputation at max level",
						xp = "Experience",
						rep = "Reputation (watched faction)",
					}),
					railRested = Toggle(2, "Show rested experience", nil, nil, "railRested"),
					levelPlaque = Toggle(2.5, "Your level on the console", "Your level in a D3 medallion resting on the skull at the console's top centre.", nil, "levelPlaque"),
					note = Note(3, "Reputation is tinted with your resource color. Watch a faction from the Reputation panel."),
				},
			},
			bars = {
				type = "group",
				order = 4,
				name = "Bars",
				args = {
					intro = Note(0, "The main bar is the nine sockets in the console. Bars 2-9 stack above it, bar 2 at the bottom, or dock in the console. The settings on this page apply to every bar's buttons."),
					text = Header(1, "Text"),
					hotkeys = Toggle(2, "Show keybinds", nil, "buttons", "hotkeys"),
					macroNames = Toggle(3, "Show macro names", nil, "buttons", "macroNames"),
					look = Header(10, "Behaviour"),
					range = Select(11, "Out of range", nil, "buttons", "range", { button = "Tint the icon", hotkey = "Tint the keybind", none = "Nothing" }),
					tooltips = Select(12, "Tooltips", nil, "buttons", "tooltips", { enabled = "Always", nocombat = "Out of combat", disabled = "Never" }),
					grid = Toggle(13, "Show empty sockets' grid", "Keep empty buttons visible so actions can be dropped on them.", "buttons", "grid"),
					cooldownNumbers = Select(14, "Cooldown numbers", "The time left on a skill's cooldown, counted down on its button. The global cooldown never shows one.", "buttons", "cooldownNumbers", { cvar = "Blizzard setting", show = "Show", hide = "Hide" }),
					cooldownTenths = (function()
						local option = Range(14.5, "Tenths of a second below", "Cooldowns with less than this many seconds left count down in tenths (4.7). 0 shows whole seconds only.", "buttons", "cooldownTenths", 0, 60, 1)
						option.disabled = function() return DB().buttons.cooldownNumbers == "hide" end
						return option
					end)(),
					keyDown = CVarToggle(15, "Cast on key down", "Blizzard's ActionButtonUseKeyDown.", "ActionButtonUseKeyDown"),
					lock = Toggle(16, "Lock buttons", "Locked buttons only pick up actions while holding Shift. Unlocked buttons drag freely.", "buttons", "lock"),
					active = Header(16.9, "Active skills"),
					activeGlow = Toggle(17, "Active skill glow", "While a skill's buff, channel or totem is up, its socket burns like D3's.", "buttons", "activeGlow"),
					activeTimer = Toggle(18, "Active skill timer", "A tab in the socket with a yellow bar that drains until the effect ends.", "buttons", "activeTimer"),
					activeTimerPos = Select(18.5, "Active skill timer position", nil, "buttons", "activeTimerPos", { top = "Top of the socket", bottom = "Bottom of the socket" }),
					activeEndless = Toggle(20, "Light buffs with no duration", "Stances, paladin auras, aspects and other buffs that never run out glow too. Tracking (Find Minerals, Find Herbs) never does.", "buttons", "activeEndless"),
					activeGlowMax = Range(19.5, "Glow only for buffs up to (seconds)", "Short effects (Bloodrage, trinkets) burn and show the timer. Longer buffs (Battle Shout) show just the timer tab. Channels, totems and buffs with no duration always glow.", "buttons", "activeGlowMax", 0, 600, 5),
					activeMax = Range(19, "Longest buff to show (seconds)", "Buffs that last longer than this don't light their skill, so long buffs like Fortitude stay quiet. Channels and totems always show.", "buttons", "activeMax", 10, 600, 5),
					petHeader = Header(30, "Pet bar"),
					pets = Toggle(31, "Show the pet bar", "Pet actions above the bars when you have a pet.", nil, "pets"),
					main = { type = "group", order = 1, name = "Main bar", args = MainBarArgs() },
					stance = {
						type = "group",
						order = 30,
						name = "Stance bar",
						args = {
							intro = Note(1, "Stances, forms, auras, stealth: whatever your class has. Hidden for classes without any. Keybinds come from Blizzard's Stance Bar bindings, or use hover-binding."),
							enabled = Toggle(2, "Enabled", nil, "stance", "enabled"),
							size = Header(10, "Size"),
							scale = Range(11, "Button size", "Relative to a main-bar socket.", "stance", "scale", 0.4, 1.2, 0.01, true),
							spacing = Range(12, "Spacing", nil, "stance", "spacing", 0, 20, 1),
							perLine = Range(13, "Buttons per line", "1 makes a vertical bar.", "stance", "perLine", 1, 10, 1),
							show = Header(20, "Visibility"),
							alpha = Range(21, "Opacity", nil, "stance", "alpha", 0, 1, 0.05, true),
							mouseover = Toggle(22, "Show on mouseover only", nil, "stance", "mouseover"),
							place = Header(30, "Position"),
							placeNote = Note(31, "Above the health globe by default. Turn off General > Lock frames and drag its mover to place it anywhere."),
							reset = {
								type = "execute",
								order = 32,
								name = "Reset position",
								func = function() ns.Stance.ResetPosition() end,
								disabled = function() return not DB().stance.moved end,
							},
						},
					},
					totems = {
						type = "group",
						order = 31,
						name = "Totem bar",
						args = {
							intro = Note(1, "One socket per element: earth, fire, water, air, framed like the combo point pips. Shown once you know a totem. A totem that is down lights its socket, and a round sweep runs out its time."),
							enabled = Toggle(2, "Enabled", nil, "totems", "enabled"),
							preview = {
								type = "toggle",
								order = 2.5,
								name = "Preview",
								desc = "Show the bar with every totem and two on timers, on any character. Nothing casts. Turns off on /reload.",
								width = "full",
								get = function() return ns.Totem.preview end,
								set = function(_, value) ns.Totem.SetPreview(value) end,
							},
							mode = Select(3, "Mode", nil, "totems", "mode", {
								bar = "Totem bar: cast, pick each socket's totem from a flyout",
								tracker = "Tracker: only show totems that are down",
							}),
							modeNote = Note(4, "Bar mode: left-click casts, right-click dismisses. Shift + right-click a socket to fan out that element's totems: left-click one to put it in the socket, right-click to cast it once. Tracker mode: right-click dismisses. Keybinds are under Key Bindings > AddOns > SanctuaryUI, or use hover-binding."),
							ring = Header(5, "Globe"),
							attach = Select(6, "Attach to", "Ring a globe's rim like the combo point pips, or stand free as a row you can drag anywhere.", "totems", "attach", {
								none = "Nothing: a free row",
								health = "Health globe",
								resource = "Resource globe",
							}),
							arc = {
								type = "range",
								order = 7,
								name = "Position on the rim",
								desc = "Angle of the ring's centre, in degrees: 90 is the top of the globe, 180 its left side, 0 its right. Or turn off General > Lock frames and drag the totems around the globe.",
								min = 0,
								max = 359,
								step = 1,
								get = function()
									local opt = DB().totems
									return opt.attach == "health" and opt.arcHealth or opt.arcResource
								end,
								set = function(_, value)
									local opt = DB().totems
									if opt.attach == "health" then opt.arcHealth = value else opt.arcResource = value end
									Changed()
								end,
								hidden = function() return DB().totems.attach == "none" end,
							},
							ringGap = (function()
								local r = Range(8, "Distance from the rim", nil, "totems", "ringGap", -20, 40, 1)
								r.hidden = function() return DB().totems.attach == "none" end
								return r
							end)(),
							ringNote = {
								type = "description",
								order = 9,
								name = "Attached, the sockets sit on the rim like the pips and follow the console; each picker fans out on a wider arc. Unlock frames to drag them around the globe. The picker direction and vertical settings apply to the free row only.",
								hidden = function() return DB().totems.attach == "none" end,
							},
							size = Header(10, "Size"),
							scale = Range(11, "Button size", "Relative to a main-bar socket.", "totems", "scale", 0.4, 1.2, 0.01, true),
							spacing = Range(12, "Spacing", nil, "totems", "spacing", 0, 20, 1),
							vertical = Toggle(13, "Vertical", "Stack the sockets instead of a row.", "totems", "vertical"),
							flyout = Select(14, "Picker opens", nil, "totems", "flyout", { up = "Up", down = "Down" }),
							show = Header(20, "Visibility"),
							alpha = Range(21, "Opacity", nil, "totems", "alpha", 0, 1, 0.05, true),
							mouseover = Toggle(22, "Show on mouseover only", nil, "totems", "mouseover"),
							place = Header(30, "Position"),
							placeNote = Note(31, "Free row: above the resource globe by default. Turn off General > Lock frames and drag its mover to place it anywhere."),
							reset = {
								type = "execute",
								order = 32,
								name = "Reset position",
								func = function() ns.Totem.ResetPosition() end,
								disabled = function() return not DB().totems.moved end,
							},
						},
					},
					keybinding = {
						type = "group",
						order = 40,
						name = "Keybinds",
						args = {},
					},
				},
			},
			auras = {
				type = "group",
				order = 6.1,
				name = "Buffs",
				args = {
					intro = Note(1, "Your buffs and debuffs, D3 style: Blizzard's buff and debuff frames set in stone sockets, debuffs in red. They are Blizzard's own because this client lets only Blizzard read your buffs in combat. Right-click a buff to cancel it. Turning this off gives Blizzard's look back."),
					enabled = Toggle(2, "Enabled", nil, "auras", "enabled"),
					duration = Toggle(3, "Show time left under each icon", nil, "auras", "duration"),
					bars = Toggle(4, "Countdown bars", "A bar under each timed buff and debuff that runs down, turning red in its last 10 seconds. In combat it shows only while the client lets addons read the time left.", "auras", "bars"),
					editMode = Note(20, "Position, icon size, icons per row, how many and wrap direction are Edit Mode's (Esc > Edit Mode, then drag or click the Buff Frame and Debuff Frame). For the D3 look, place them just above the bars with Icon Wrap set to Up."),
				},
			},
			target = {
				type = "group",
				order = 6.12,
				name = "Target",
				args = {
					intro = Note(1, "D3's monster bar at the top of the screen: a silver frame for ordinary monsters, gold for elites and rares, the gold banner for bosses, and every debuff on the target underneath (yours bright, the rest dimmed). Left-click targets, right-click opens the unit menu. Turning it off brings back Blizzard's target frame."),
					enabled = Toggle(2, "Enabled", nil, "target", "enabled"),
					preview = {
						type = "toggle",
						order = 3,
						name = "Preview",
						desc = "With no target, show a stand-in monster that cycles the normal, elite and boss frames while its health drops, to judge the look in game.",
						get = function() return ns.TargetPlate.preview end,
						set = function(_, value) ns.TargetPlate.SetPreview(value) end,
						width = "full",
					},
					lookHeader = Header(5, "Look"),
					scale = Range(6, "Scale", "100% is D3's own size: the art one-to-one at 1080p, the same share of the screen at any resolution.", "target", "scale", 0.5, 2, 0.05, true),
					width = Range(7, "Width", "Stretches the frame and bar between their ornaments.", "target", "width", 0.6, 2.5, 0.05, true),
					portrait = Toggle(8, "Target portrait", "The target's moving WoW portrait in a D3 hero portrait frame, left of the bar: silver for ordinary monsters, gold for elites and rares, the winged demon for bosses.", "target", "portrait"),
					tot = Toggle(9.2, "Target of target", "Who your target is attacking: a small monster bar with its portrait, right of the target's frame. Its name turns red when it's you. Left-click targets it, right-click opens its menu.", "target", "tot"),
					totPortrait = (function()
						local option = Toggle(9.3, "Target of target portrait", "The target of target's portrait in its silver ring, left of its bar. Off, the bar alone sits beside the target's frame.", "target", "totPortrait")
						option.disabled = function() return DB().target.tot == false end
						return option
					end)(),
					cast = Toggle(9.5, "Cast bar", nil, "target", "cast"),
					liquid = Toggle(9.7, "Liquid in the bar", "The globes' liquid drifting through the health bar.", "target", "liquid"),
					edgeGlow = Toggle(9.8, "Edge glow", "An ember burning at the health bar's leading edge.", "target", "edgeGlow"),
					healPrediction = Toggle(9.9, "Heal prediction", "Heals on their way to your target show in green past the end of its health, damage shields in silver after them, and a silver glow lights the bar's end when the shield is bigger than the health missing.", "target", "healPrediction"),
					healthHeader = Header(11, "Health text"),
					healthText = Select(11.1, "Show", "Works in combat too, where enemy health is hidden from addons: the client fills the numbers in.", "target", "healthText", HEALTH_TEXTS, HEALTH_ORDER),
					healthNumbers = TargetText("healthText", Select(11.2, "Numbers", nil, "target", "healthNumbers", { short = "Short (2.48M)", full = "Full (2,480,000)", raw = "Plain (2480000)" })),
					healthHideFull = TargetText("healthText", Toggle(11.3, "Hide at full health", nil, "target", "healthHideFull")),
					healthPos = TargetText("healthText", Select(11.4, "Position", nil, "target", "healthPos", TEXT_POSITIONS, POS_ORDER)),
					healthFont = TargetText("healthText", Select(11.5, "Font", nil, "target", "healthFont", TEXT_FONTS)),
					healthSize = TargetText("healthText", Range(11.6, "Size", nil, "target", "healthSize", 6, 24, 1)),
					healthX = TargetText("healthText", Range(11.7, "Nudge left / right", nil, "target", "healthX", -200, 200, 1)),
					healthY = TargetText("healthText", Range(11.8, "Nudge up / down", nil, "target", "healthY", -60, 60, 1)),
					nameHeader = Header(12, "Name"),
					nameShow = Toggle(12.1, "Show name", nil, "target", "nameShow"),
					namePos = TargetText("nameShow", Select(12.4, "Position", nil, "target", "namePos", TEXT_POSITIONS, POS_ORDER)),
					nameFont = TargetText("nameShow", Select(12.5, "Font", nil, "target", "nameFont", TEXT_FONTS)),
					nameSize = TargetText("nameShow", Range(12.6, "Size", nil, "target", "nameSize", 6, 24, 1)),
					nameX = TargetText("nameShow", Range(12.7, "Nudge left / right", nil, "target", "nameX", -200, 200, 1)),
					nameY = TargetText("nameShow", Range(12.8, "Nudge up / down", nil, "target", "nameY", -60, 60, 1)),
					levelHeader = Header(13, "Level"),
					levelShow = Toggle(13.1, "Show level", nil, "target", "levelShow"),
					levelColor = TargetText("levelShow", Select(13.2, "Colour", "By difficulty: grey, green, yellow, orange or red against your level, as Blizzard colours it.", "target", "levelColor", { plain = "Plain", difficulty = "By difficulty" })),
					levelPos = TargetText("levelShow", Select(13.4, "Position", "The plaque sits under the portrait frame, in its metal. With the portrait off, the level goes in the bar's left end.", "target", "levelPos", LEVEL_POSITIONS, LEVEL_ORDER)),
					levelFont = TargetText("levelShow", Select(13.5, "Font", nil, "target", "levelFont", TEXT_FONTS)),
					levelSize = TargetText("levelShow", Range(13.6, "Size", nil, "target", "levelSize", 6, 24, 1)),
					levelX = TargetText("levelShow", Range(13.7, "Nudge left / right", nil, "target", "levelX", -200, 200, 1)),
					levelY = TargetText("levelShow", Range(13.8, "Nudge up / down", nil, "target", "levelY", -60, 60, 1)),
					debuffHeader = Header(14, "Debuffs"),
					debuffs = Toggle(14.1, "Debuffs", "Every debuff on the target: yours first and bright, the rest greyed.", "target", "debuffs"),
					maxDebuffs = TargetAura("debuffs", Range(14.2, "How many debuffs", nil, "target", "maxDebuffs", 1, 24, 1)),
					auraPos = TargetAura("debuffs", Select(14.3, "Position", nil, "target", "auraPos", { below = "Below the bar", above = "Above the bar" })),
					auraAlign = TargetAura("debuffs", Select(14.4, "Align to", "Where each line starts: the bar's left end, centre or right end.", "target", "auraAlign", { left = "Left", center = "Centre", right = "Right" })),
					auraGrow = TargetAura("debuffs", Select(14.5, "Grow", "From a left or right end, which way the icons run. Centred lines grow both ways.", "target", "auraGrow", { right = "To the right", left = "To the left" })),
					debuffSize = TargetAura("debuffs", Range(14.6, "Icon size", nil, "target", "debuffSize", 14, 48, 1)),
					auraPerLine = TargetAura("debuffs", Range(14.7, "Icons per line", nil, "target", "auraPerLine", 1, 24, 1)),
					auraSpacing = TargetAura("debuffs", Range(14.8, "Spacing", nil, "target", "auraSpacing", 0, 16, 1)),
					auraX = TargetAura("debuffs", Range(14.9, "Nudge left / right", nil, "target", "auraX", -300, 300, 1)),
					auraY = TargetAura("debuffs", Range(14.95, "Nudge up / down", nil, "target", "auraY", -200, 200, 1)),
					buffHeader = Header(20, "Buffs"),
					buffs = Toggle(20.1, "Buffs", "The target's buffs, laid out on their own.", "target", "buffs"),
					maxBuffs = TargetAura("buffs", Range(20.2, "How many buffs", nil, "target", "maxBuffs", 1, 24, 1)),
					buffPos = TargetAura("buffs", Select(20.3, "Position", "On the same side as the debuffs, the buffs start on the line after them.", "target", "buffPos", { below = "Below the bar", above = "Above the bar" })),
					buffAlign = TargetAura("buffs", Select(20.4, "Align to", "Where each line starts: the bar's left end, centre or right end.", "target", "buffAlign", { left = "Left", center = "Centre", right = "Right" })),
					buffGrow = TargetAura("buffs", Select(20.5, "Grow", "From a left or right end, which way the icons run. Centred lines grow both ways.", "target", "buffGrow", { right = "To the right", left = "To the left" })),
					buffSize = TargetAura("buffs", Range(20.6, "Icon size", nil, "target", "buffSize", 14, 48, 1)),
					buffPerLine = TargetAura("buffs", Range(20.7, "Icons per line", nil, "target", "buffPerLine", 1, 24, 1)),
					buffSpacing = TargetAura("buffs", Range(20.8, "Spacing", nil, "target", "buffSpacing", 0, 16, 1)),
					buffX = TargetAura("buffs", Range(20.9, "Nudge left / right", nil, "target", "buffX", -300, 300, 1)),
					buffY = TargetAura("buffs", Range(20.95, "Nudge up / down", "Sharing the debuffs' side, this is from the end of the debuffs.", "target", "buffY", -200, 200, 1)),
					place = Header(30, "Position"),
					placeNote = Note(31, "Top centre by default. Turn off General > Lock frames and drag its mover to place it anywhere."),
					reset = {
						type = "execute",
						order = 32,
						name = "Reset position",
						func = function() ns.TargetPlate.ResetPosition() end,
						disabled = function() return not DB().target.moved end,
					},
				},
			},
			portraits = {
				type = "group",
				order = 6.14,
				name = "Portraits",
				args = {
					intro = Note(1, "D3 party portraits, top left: your pet, and you if you want it (no health bar on yours: the globe is your health). Left-click targets, right-click opens the unit menu (leave group, loot, raid markers). The frame turns gold on your target, and shows leader, combat, resting and raid marker icons. Turning it off brings back Blizzard's player frame."),
					enabled = Toggle(2, "Enabled", nil, "portraits", "enabled"),
					preview = {
						type = "toggle",
						order = 2.5,
						name = "Preview",
						desc = "Show both portraits (the pet's drawn from you when you have no pet) to judge them in game.",
						get = function() return ns.Portraits.preview end,
						set = function(_, value) ns.Portraits.SetPreview(value) end,
						width = "full",
					},
					player = Toggle(3, "Your portrait", "Right-click it for your unit menu (leave group, loot, raid markers).", "portraits", "player"),
					pet = Toggle(3.5, "Pet portrait", nil, "portraits", "pet"),
					scale = Range(4, "Scale", "100% is D3's own size.", "portraits", "scale", 0.6, 2.5, 0.05, true),
					place = Header(30, "Position"),
					placeNote = Note(31, "Top left by default. Turn off General > Lock frames and drag its mover to place it anywhere."),
					reset = {
						type = "execute",
						order = 32,
						name = "Reset position",
						func = function() ns.Portraits.ResetPosition() end,
						disabled = function() return not DB().portraits.moved end,
					},
				},
			},
			bank = {
				type = "group",
				order = 6.6,
				name = "Bank",
				args = {
					enabled = Toggle(1, "Use the SanctuaryUI bank window", "D3's stash in place of Blizzard's bank. Needs the bag window on. Turning it off needs a /reload.", "bank", "enabled"),
					layout = Header(10, "Layout"),
					dividers = Toggle(11, "Divide bank tabs", "Each bank tab on its own lines, with a divider between them.", "bank", "dividers"),
					columns = Range(12, "Columns", nil, "bank", "columns", 6, 24, 1),
					slotSize = Range(13, "Slot size", nil, "bank", "slotSize", 28, 52, 1),
					spacing = Range(14, "Spacing", nil, "bank", "spacing", 0, 8, 1),
					scale = Range(15, "Scale", nil, "bank", "scale", 0.5, 1.6, 0.01, true),
					look = Header(20, "Look"),
					quality = Toggle(21, "Quality backgrounds", nil, "bank", "quality"),
					bagSlots = Toggle(22, "Show bank bag slots", "The base bank and your bank bag slots across the top: drag bags on to equip them.", "bank", "bagSlots"),
					place = Header(30, "Position"),
					placeNote = Note(31, "Drag the window by its stone to move it."),
					reset = {
						type = "execute",
						order = 32,
						name = "Reset position",
						func = function()
							local opt = DB().bank
							opt.point, opt.x, opt.y = "TOPLEFT", 40, -120
							Changed()
						end,
					},
				},
			},
			bags = {
				type = "group",
				order = 6.5,
				name = "Bags",
				args = {
					enabled = Toggle(1, "Use the SanctuaryUI bag window", "Replaces Blizzard's bags. Turning it off needs a /reload to bring Blizzard's back.", "bags", "enabled"),
					layout = Header(10, "Layout"),
					dividers = Toggle(11, "Divide bags", "Start each bag on its own line, with a divider between bags. Off: one combined grid.", "bags", "dividers"),
					columns = Range(12, "Columns", nil, "bags", "columns", 6, 20, 1),
					slotSize = Range(13, "Slot size", nil, "bags", "slotSize", 28, 52, 1),
					spacing = Range(14, "Spacing", nil, "bags", "spacing", 0, 8, 1),
					scale = Range(15, "Scale", nil, "bags", "scale", 0.5, 1.6, 0.01, true),
					look = Header(20, "Look"),
					quality = Toggle(21, "Quality backgrounds", "D3's colored cell backgrounds for uncommon, rare, epic, legendary and heirloom items.", "bags", "quality"),
					bagSlots = Toggle(23, "Show bag slots", "Your backpack and bag slots across the top of the window: drag bags on to equip or swap them.", "bags", "bagSlots"),
					autoSellJunk = Toggle(22, "Sell junk automatically", "Sell grey items whenever a vendor opens. Off: use the Sell Junk button on the bag window.", "bags", "autoSellJunk"),
					place = Header(30, "Position"),
					placeNote = Note(31, "Drag the window by its stone to move it."),
					reset = {
						type = "execute",
						order = 32,
						name = "Reset position",
						func = function()
							local opt = DB().bags
							opt.point, opt.x, opt.y = "BOTTOMRIGHT", -60, 260
							Changed()
						end,
					},
				},
			},
		},
	}
	for i, n in ipairs(ns.ActionBar.ROW_IDS) do
		options.args.bars.args["row" .. n] = RowGroup(n, 10 + i)
	end
	options.args.profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(ns.db)
	options.args.profiles.order = 100
	return options
end

-- The keybinding page lists the buttons of the rows in use, so it is rebuilt on open.
local function Table()
	local options = ns.Options.table or Build()
	ns.Options.table = options
	options.args.bars.args.keybinding.args = KeybindArgs()
	return options
end

function ns.Options.Init()
	local AceConfig = LibStub("AceConfig-3.0")
	local Dialog = LibStub("AceConfigDialog-3.0")
	AceConfig:RegisterOptionsTable(APP, Table)
	Dialog:SetDefaultSize(APP, 860, 640)
	Dialog:AddToBlizOptions(APP, "SanctuaryUI")
end

function ns.Options.Open()
	local Dialog = LibStub("AceConfigDialog-3.0")
	if Dialog.OpenFrames[APP] then
		Dialog:Close(APP)
	else
		Dialog:Open(APP)
	end
end
