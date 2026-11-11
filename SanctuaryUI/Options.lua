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

-- Every page sits on the same grid. Relative widths hold in the standalone window, inside a
-- tab and in Blizzard's options panel. Two halves or three thirds fill a row.
local HALF, THIRD = 0.5, 0.333

local function Width(option, share)
	option.width, option.relWidth = "relative", share
	return option
end

local function Third(option) return Width(option, THIRD) end

local function Toggle(order, name, desc, path, key)
	local get, set = Field(path, key)
	return Width({ type = "toggle", order = order, name = name, desc = desc, get = get, set = set }, HALF)
end

local function Range(order, name, desc, path, key, min, max, step, isPercent)
	local get, set = Field(path, key)
	return Width({ type = "range", order = order, name = name, desc = desc, get = get, set = set, min = min, max = max, step = step, isPercent = isPercent }, THIRD)
end

local function Select(order, name, desc, path, key, values, sorting)
	local get, set = Field(path, key)
	return Width({ type = "select", order = order, name = name, desc = desc, get = get, set = set, values = values, sorting = sorting }, THIRD)
end

local function Gold(text)
	return "|cffd8b86a" .. text .. "|r"
end

local function Muted(text)
	return "|cffb3a78f" .. text .. "|r"
end

local function Header(order, name)
	return { type = "header", order = order, name = Gold(name) }
end

-- Text may be a function, for a note that changes with the settings.
local function Note(order, text)
	local name = type(text) == "function" and function() return Muted(text()) end or Muted(text)
	return { type = "description", order = order, name = name, fontSize = "medium" }
end

-- A titled box of related settings. extra adds fields such as hidden or disabled.
local function Card(order, name, args, extra)
	local card = { type = "group", inline = true, order = order, name = Gold(name), args = args }
	for key, value in pairs(extra or {}) do card[key] = value end
	return card
end

-- A tab on a tabbed page.
local function Tab(order, name, args, extra)
	local tab = { type = "group", order = order, name = name, args = args }
	for key, value in pairs(extra or {}) do tab[key] = value end
	return tab
end

-- A row of the tree, indented under its label and in cream, so the gold labels lead.
local function TreeRow(name)
	return "   |cffe6dfd0" .. name .. "|r"
end

-- A page in the tree. childGroups = "tab" turns its groups into tabs under its own settings.
local function Page(order, name, args, childGroups)
	return { type = "group", order = order, name = TreeRow(name), args = args, childGroups = childGroups }
end

-- A gold label in the tree. Disabled, so it can't be selected.
local function Section(order, name)
	return { type = "group", order = order, name = Gold(name:upper()), disabled = true, args = {} }
end

-- An empty row between sections of the tree.
local function Gap(order)
	return { type = "group", order = order, name = " ", disabled = true, args = {} }
end

local UNLOCK = "Unlock frames on the General page, then drag its mover to place it anywhere, or hover it and nudge it with the arrow keys."

-- Every movable frame's Position card: where it sits now and how to put it back.
local function PositionCard(order, note, reset, notMoved)
	return Card(order, "Position", {
		note = Note(1, note),
		reset = { type = "execute", order = 2, name = "Reset position", func = reset, disabled = notMoved },
	})
end

-- A statue's card on the Statues page (StatueEyes.lua): the buff that lights its eyes.
local function StatueEyesCard(order, key, title, what, toggle, noColour)
	local path = "statueEyes." .. key
	local function cfg() return ns.DB().statueEyes[key] end
	local function off() return not cfg().enabled end
	local get, set = Field(path, "spells")
	return Card(order, title, {
		enabled = Toggle(1, toggle or "Eyes glow under a buff", what, path, "enabled"),
		color = Width({
			type = "color", order = 2, name = "Colour", disabled = off, hidden = noColour,
			get = function() local c = cfg().color return c[1], c[2], c[3] end,
			set = function(_, r, g, b)
				cfg().color = { r, g, b }
				Changed()
			end,
		}, 0.25),
		preview = {
			type = "execute", order = 3, width = "relative", relWidth = 0.2,
			name = function() return ns.StatueEyes.Previewing(key) and "Stop preview" or "Preview" end,
			desc = "Shows the glow without the buff.",
			func = function() ns.StatueEyes.Preview(key) end,
		},
		spells = {
			type = "input", order = 4, width = "full", disabled = off,
			name = "Buff name or spell ID",
			desc = "The buff that lights it while it is on you: its exact name (every rank counts) or a spell ID. Commas between several, e.g. Blessing of Might, Greater Blessing of Might.",
			get = get,
			set = function(info, value) set(info, (value or ""):gsub("^%s+", ""):gsub("%s+$", "")) end,
		},
		status = Note(5, function() return ns.StatueEyes.Describe(key) end),
	})
end

-- The target frame's looks (ns.Art.TARGET_STYLES, and D3's bar).
local TARGET_STYLES = {
	d3 = "Monster bar (Diablo III)",
	lintel = "Lintel",
	slim = "Slim Lintel",
	slab = "Slab (matches the party Slab)",
	bracket = "Forged Bracket",
	tablet = "Tablet",
}
local TARGET_STYLE_ORDER = { "d3", "lintel", "slim", "slab", "bracket", "tablet" }

-- One-click arrangements of the debuffs and buffs; the settings under them fine-tune any of it.
local AURA_LAYOUTS = {
	rows = { auraPos = "below", auraAlign = "left", auraGrow = "right", auraPerLine = 8, buffPos = "below", buffAlign = "left", buffGrow = "right", buffPerLine = 8 },
	split = { auraPos = "below", auraAlign = "left", auraGrow = "right", auraPerLine = 6, buffPos = "below", buffAlign = "right", buffGrow = "left", buffPerLine = 4 },
	over = { auraPos = "below", auraAlign = "left", auraGrow = "right", auraPerLine = 8, buffPos = "above", buffAlign = "left", buffGrow = "right", buffPerLine = 8 },
	side = { auraPos = "right", auraAlign = "left", auraGrow = "right", auraPerLine = 8, buffPos = "right", buffAlign = "left", buffGrow = "right", buffPerLine = 8 },
}
local AURA_LAYOUT_NAMES = {
	rows = "Rows under the frame",
	split = "Split: debuffs left, buffs right",
	over = "Buffs over, debuffs under",
	side = "Columns beside the frame",
	custom = "Custom",
}
local AURA_LAYOUT_ORDER = { "rows", "split", "over", "side", "custom" }

local AURA_POSITIONS = { below = "Below the frame", above = "Above the frame", right = "Right of the frame", left = "Left of the frame" }
local AURA_POSITION_ORDER = { "below", "above", "right", "left" }

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

-- Options > Globe auras.
local function GlobeAuraArgs()
	local DATA = ns.WatchData
	local _, myClass = UnitClass("player")
	local testClass = myClass
	local function Refresh()
		local registry = LibStub("AceConfigRegistry-3.0", true)
		if registry then registry:NotifyChange(APP) end
	end
	local function off() return not DB().globeAuras.enabled end
	local LOOK_NAMES = DATA.LOOK_NAMES -- one table for every list below (WatchEffects.lua)
	-- A look dropdown's values and order: its own first entries, then the given choices.
	local function LookChoices(order, first)
		local values, sorting = {}, {}
		for _, entry in ipairs(first) do
			values[entry[1]] = entry[2]
			sorting[#sorting + 1] = entry[1]
		end
		for _, key in ipairs(order) do
			values[key] = LOOK_NAMES[key]
			sorting[#sorting + 1] = key
		end
		return values, sorting
	end

	-- A skill's Preview: its whole life on the globe, on its own, then back to your real buffs.
	local function PreviewButton(order, key, isDisabled)
		return {
			type = "execute", order = order, name = "Preview", width = "relative", relWidth = 0.16,
			desc = "Plays this on your globes for a few seconds, from lighting up to how it ends. Not in combat.",
			disabled = function() return InCombatLockdown() or (isDisabled and isDisabled()) end,
			func = function() ns.GlobeAura.PreviewSkill(key) end,
		}
	end

	local hots = {}
	for _, effect in ipairs(DATA.EFFECTS) do
		if effect.hot then hots[#hots + 1] = effect end
	end
	-- The look they share, or "mixed" once they differ.
	local function HotLook()
		local looks = DB().globeAuras.looks
		local look = looks[hots[1].key] or "default"
		for _, effect in ipairs(hots) do
			if (looks[effect.key] or "default") ~= look then return "mixed" end
		end
		return look
	end
	local HOT_LOOKS, HOT_LOOK_SORTING = LookChoices(DATA.LOOK_ORDER, { { "default", "Each skill's default" }, { "mixed", "Set per skill" } })
	-- Red tints are left out: they'd vanish against the health globe.
	local HOT_TINTS = {
		default = "Each skill's own", nature = "Nature green", fel = "Fel green", innervate = "Teal", water = "Blue",
		frost = "Ice", holy = "Gold", arcaneViolet = "Violet", shadow = "Shadow", steel = "Silver",
	}
	local HOT_TINT_ORDER = { "default", "nature", "fel", "innervate", "water", "frost", "holy", "arcaneViolet", "shadow", "steel" }

	-- Tabs: the look, each skill by class (yours first), and a test page for any class's casts.
	local skills = Tab(2, "Skills", {
		note = Note(0.5, "Turn each skill on or off, pick its look, and press Preview to see it."),
	}, { childGroups = "select" })
	local args = {
		intro = Note(1, "Light on the globes while a buff is up. In combat this client hides your buffs from addons, so they are followed from your casts; one cancelled by hand can stay lit until its time would have run out. /sanctuary watch shows what is known."),
		enabled = Toggle(2, "Enabled", nil, "globeAuras", "enabled"),
		look = Tab(1, "Look", {
			light = Card(1, "Light", {
				intensity = Range(1, "Brightness", nil, "globeAuras", "intensity", 0.25, 1.5, 0.05, true),
				spacer = Note(1.5, ""),
				rays = Toggle(2, "Rays", "God rays turning slowly behind a radiating globe.", "globeAuras", "rays"),
				sparks = Toggle(3, "Sparks", "Motes of light rising off a radiating globe's rim.", "globeAuras", "sparks"),
				catch = Toggle(4, "Light on the glass", "Radiance wraps round onto the top of the globe's glass.", "globeAuras", "catch"),
				settleLong = Toggle(5, "Long buffs settle down", "Buffs kept up for minutes (Lightning Shield, Inner Fire) light up in full when cast, then calm to a quiet glow after a few seconds. They still flare when recast, discharge when their charges are spent and blink in their last seconds.", "globeAuras", "settleLong"),
			}),
			rendered = Card(2, "Rendered effects", {
				renderedStorm = Toggle(1, "Rendered lightning", "Lightning Shield's arcs branch and strike round the rim, crawl over the glass, and spending its charges flings bolts off the whole rim. Off, it uses the older static and bolts. Uses about 20 MB of video memory, only for characters who can have it.", "globeAuras", "renderedStorm"),
				renderedBreak = Toggle(2, "Rendered shield break", "The Shatter break cracks along its seams and flies apart with a 3D render, and blows run light along the Crystal shell. Off, they use the drawn shards and ripple. The art uses about 20 MB of video memory, only while this is on. The other shield looks and breaks are set per skill on the Skills tab.", "globeAuras", "renderedBreak"),
			}),
			healing = Card(3, "Healing over time", {
				note = Note(1, "Renew, Rejuvenation, Regrowth and Frenzied Regeneration on your health globe. The Skills tab sets the look one skill at a time."),
				look = Width({
					type = "select", order = 2, name = "Look",
					desc = "What healing over time shows on the health globe.",
					values = HOT_LOOKS,
					sorting = HOT_LOOK_SORTING,
					get = HotLook,
					set = function(_, value)
						if value == "mixed" then return end
						for _, effect in ipairs(hots) do
							DB().globeAuras.looks[effect.key] = value ~= "default" and value or nil
						end
						Changed()
						-- A preview running shows the new look from its start.
						local key = ns.GlobeAura.previewKey
						local effect = key and ns.Watch.Effect(key)
						if effect and effect.hot then ns.GlobeAura.PreviewSkill(key) end
					end,
				}, THIRD),
				tint = Select(3, "Colour", nil, "globeAuras", "hotTint", HOT_TINTS, HOT_TINT_ORDER),
				strength = Range(4, "Brightness", "On top of the overall brightness above.", "globeAuras", "hotStrength", 0.25, 2, 0.05, true),
				preview = (function()
					local key = myClass == "PRIEST" and "renew" or "rejuvenation"
					-- The button's own disabled replaces the card's, so it checks Enabled too.
					return PreviewButton(5, key, function() return off() or not DB().globeAuras.effects[key] end)
				end)(),
			}, { disabled = off }),
		}),
		skills = skills,
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
				local flareOnly = effect.look == "flare"
				page.args[effect.key] = {
					type = "toggle",
					order = n,
					name = effect.label,
					desc = effect.desc:sub(1, 1):upper() .. effect.desc:sub(2) .. ".",
					width = "relative", relWidth = 0.33,
					get = function() return DB().globeAuras.effects[effect.key] end,
					set = function(_, value)
						DB().globeAuras.effects[effect.key] = value
						Changed()
					end,
				}
				page.args[effect.key .. "Preview"] = PreviewButton(n + 0.7, effect.key, function()
					return not DB().globeAuras.enabled or not DB().globeAuras.effects[effect.key]
				end)
				local native = flareOnly and (effect.heal or "burst") or effect.look == "surge" and (effect.surge or "swirl")
					or effect.look == "shell" and (effect.shell or "shell") or effect.look
				local lookValues, lookSorting = LookChoices(flareOnly and DATA.FLARE_ORDER or DATA.LOOK_ORDER,
					{ { "default", "Default (" .. LOOK_NAMES[native] .. ")" } })
				page.args[effect.key .. "Look"] = {
					type = "select",
					order = n + 0.5,
					name = "",
					desc = "What this skill shows on the globe. Default is " .. LOOK_NAMES[native] .. "." ..
						(flareOnly and " A part going out of a globe (Life Tap's cost) stays a burst." or ""),
					width = "relative", relWidth = 0.25,
					values = lookValues,
					sorting = lookSorting,
					disabled = function() return not DB().globeAuras.effects[effect.key] end,
					get = function() return DB().globeAuras.looks[effect.key] or "default" end,
					set = function(_, value)
						DB().globeAuras.looks[effect.key] = value ~= "default" and value or nil
						Changed()
						-- A preview of this skill running shows the new look from its start.
						if ns.GlobeAura.previewKey == effect.key then ns.GlobeAura.PreviewSkill(effect.key) end
					end,
				}
				-- Only damage shields break (Watch.lua IconLost), so only they choose how.
				if effect.absorb or effect.kind == "absorb" then
					local BREAK_NAMES = DATA.BREAK_NAMES
					local nativeBreak = effect.shellBreak or "shatter"
					local breakValues, breakSorting = { default = "Break: Default (" .. BREAK_NAMES[nativeBreak] .. ")" }, { "default" }
					for _, key in ipairs(DATA.BREAK_ORDER) do
						breakValues[key] = "Break: " .. BREAK_NAMES[key]
						breakSorting[#breakSorting + 1] = key
					end
					page.args[effect.key .. "Break"] = {
						type = "select",
						order = n + 0.6,
						name = "",
						desc = "How this shield goes when it breaks. Default is " .. BREAK_NAMES[nativeBreak] .. ".",
						width = "relative", relWidth = 0.25,
						values = breakValues,
						sorting = breakSorting,
						disabled = function() return not DB().globeAuras.effects[effect.key] end,
						-- Shown as anything but a shell it just fades when it breaks.
						hidden = function() return ns.GlobeAura.LookOf(effect) ~= "shell" end,
						get = function() return DB().globeAuras.breaks[effect.key] or "default" end,
						set = function(_, value)
							DB().globeAuras.breaks[effect.key] = value ~= "default" and value or nil
							Changed()
							if ns.GlobeAura.previewKey == effect.key then ns.GlobeAura.PreviewSkill(effect.key) end
						end,
					}
				end
			end
		end
		skills.args["class" .. class] = page
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
		casts = Header(10, "Cast"),
		moments = Header(60, "Moments"),
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
			desc = effect.look == "flare" and "Plays it once." or "Casts it on you. Cast it again while it is up to recast it.",
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
	args.test = Tab(3, "Test", testArgs)
	return args
end

-- CVar toggles (Blizzard settings that also drive the action buttons).
local function CVarToggle(order, name, desc, cvar)
	local GetCVar = C_CVar and C_CVar.GetCVar or GetCVar
	return {
		type = "toggle",
		order = order,
		name = name,
		desc = desc,
		width = "relative",
		relWidth = HALF,
		get = function() return GetCVar(cvar) == "1" end,
		set = function(_, value)
			ns.AskCVarReload(cvar, value and "1" or "0", ("Turn Blizzard's %s %s?"):format(name, value and "on" or "off"))
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
		main = Card(10, "Main bar", {}),
	}
	for i = 1, 9 do
		args.main.args["b" .. i] = KeyField(i, "Socket " .. i, "ACTIONBUTTON" .. i)
	end
	if ns.Totem and ns.Totem.HasTotems() then
		local group = Card(9, "Totem bar", {})
		for i, element in ipairs(ns.Totem.ELEMENTS) do
			group.args["t" .. i] = KeyField(i, element.label .. " totem", "SANCTUARYUITOTEM" .. i)
		end
		args.totems = group
	end
	if DB().trinkets.enabled then
		args.trinkets = Card(9.5, "Trinkets", {
			t1 = KeyField(1, "Use trinket 1", "SANCTUARYUITRINKET1"),
			t2 = KeyField(2, "Use trinket 2", "SANCTUARYUITRINKET2"),
		})
	end
	for idx, n in ipairs(ns.ActionBar.ROW_IDS) do
		local opt = DB().rows[n]
		if opt.enabled then
			local spec = ns.ActionBar.RowSpec(n)
			local group = Card(10 + idx, "Bar " .. n, {})
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
-- Pie menus (PieMenu.lua)

local function PieRingCard(n)
	local function ring() return ns.Pie.Ring(n) end
	local key = KeyField(2, "Hotkey", nil, ns.Pie.ButtonName(n))
	key.desc = "Hold this key to open the ring at the mouse; release it over a skill to use that skill."
	return Card(10 + n, "Ring " .. n, {
		name = Third({
			type = "input", order = 1, name = "Name",
			desc = "Shown in the middle of the ring while nothing is selected.",
			get = function() return ring().name or "" end,
			set = function(_, value)
				ring().name = (value or ""):gsub("^%s+", ""):gsub("%s+$", "")
				Changed()
			end,
		}),
		key = Third(key),
		edit = Third({
			type = "execute", order = 3, name = "Edit skills",
			desc = "Closes this window and shows the ring, so you can drag spells, items and macros onto it.",
			func = function()
				LibStub("AceConfigDialog-3.0"):Close(APP)
				ns.Pie.Edit(n)
			end,
		}),
		skills = Note(4, function() return ns.Pie.Describe(n) end),
	})
end

local function PieArgs()
	local args = {
		intro = Note(1, "A pie menu is a ring of up to 8 skills. Hold its hotkey and it opens at the mouse; move toward a skill and release the key to use it. Release in the middle, or just tap the key, and nothing happens. Give a ring a hotkey, then press Edit skills and drag spells, items or macros onto it."),
		look = Card(2, "Look", {
			scale = Range(1, "Ring size", "How big the rings are drawn.", "pie", "scale", 0.6, 1.6, 0.01, true),
		}),
	}
	for n = 1, ns.Pie.MAX_RINGS do
		args["ring" .. n] = PieRingCard(n)
	end
	return args
end

---------------------------------------------------------------------------
-- Trinkets (Trinket.lua) and the swing timer (SwingTimer.lua)

local MAX_LISTED = 12

local function Notify()
	local registry = LibStub("AceConfigRegistry-3.0", true)
	if registry then registry:NotifyChange(APP) end
end

-- One trinket socket's auto-swap list: on/off, then a row per trinket with up, down, remove.
local function AutoSwapCard(order, i)
	local function char() return ns.db.char.trinkets[i] end
	local function count() return #char().list end
	local args = {
		auto = Width({
			type = "toggle", order = 1, name = "Auto-swap",
			desc = "Out of combat, once this trinket is on a cooldown longer than the 30 seconds an equip costs, the first trinket on the list that's ready goes on. A ready trinket higher on the list replaces a lower one. A trinket you pick from the menu stays until you've used it, and one whose effect is on you stays until it fades.",
			get = function() return char().auto end,
			set = function(_, value) char().auto = value ns.Trinket.Update() end,
		}, HALF),
		empty = Note(2, ("Alt + %s-click a trinket in the menu to add it here. Its place on the list shows in the menu's %s corner."):format(i == 1 and "left" or "right", i == 1 and "top left" or "top right")),
	}
	args.empty.hidden = function() return count() > 0 end
	for n = 1, MAX_LISTED do
		local function hidden() return n > count() end
		local function entry() return ns.Trinket.List(i)[n] end
		args["name" .. n] = Width({
			type = "description", order = 10 + n * 4, fontSize = "medium", hidden = hidden,
			name = function()
				local e = entry()
				if not e then return "" end
				return ("%d.  |T%s:16:16:0:0:64:64:5:59:5:59|t  %s"):format(n, tostring(e.icon or 134400), e.name)
			end,
		}, 0.55)
		args["up" .. n] = Width({
			type = "execute", order = 11 + n * 4, name = "Up", hidden = hidden,
			disabled = function() return n == 1 end,
			func = function() ns.Trinket.MoveListed(i, n, -1) Notify() end,
		}, 0.15)
		args["down" .. n] = Width({
			type = "execute", order = 12 + n * 4, name = "Down", hidden = hidden,
			disabled = function() return n == count() end,
			func = function() ns.Trinket.MoveListed(i, n, 1) Notify() end,
		}, 0.15)
		args["remove" .. n] = Width({
			type = "execute", order = 13 + n * 4, name = "Remove", hidden = hidden,
			func = function() ns.Trinket.RemoveListed(i, n) Notify() end,
		}, 0.15)
	end
	return Card(order, "Auto-swap: trinket " .. i, args)
end

local function TrinketArgs()
	return {
		intro = Note(1, "Your two trinkets in sockets: click one, or press its keybind, to use it. Hover a socket for the trinkets in your bags: left-click one to equip it as trinket 1, right-click for trinket 2. In combat the game won't change trinkets, so your pick waits in the socket's corner and goes on when combat ends. Keybinds are under Keybinds, Key Bindings > AddOns > SanctuaryUI, or hover-binding."),
		enabled = Toggle(2, "Enabled", nil, "trinkets", "enabled"),
		menu = Card(3, "Menu", {
			menu = Select(1, "Opens", "What opens the menu of bag trinkets over a socket.", "trinkets", "menu", { hover = "On mouseover", shift = "Shift + mouseover", off = "Never" }, { "hover", "shift", "off" }),
			menuDir = Select(2, "Direction", nil, "trinkets", "menuDir", { up = "Up", down = "Down", left = "Left", right = "Right" }, { "up", "down", "left", "right" }),
			menuPerLine = Range(3, "Trinkets per line", nil, "trinkets", "menuPerLine", 1, 10, 1),
			menuScale = Range(4, "Menu socket size", "Of a trinket socket.", "trinkets", "menuScale", 0.5, 1.2, 0.05, true),
		}),
		size = Card(4, "Size and spacing", {
			scale = Range(1, "Button size", "Relative to a main-bar socket.", "trinkets", "scale", 0.4, 1.2, 0.01, true),
			spacing = Range(2, "Spacing", nil, "trinkets", "spacing", 0, 20, 1),
			vertical = Third(Toggle(3, "Vertical", "Stack the two sockets instead of a row.", "trinkets", "vertical")),
		}),
		ready = Card(5, "When a trinket is ready", {
			notify = Toggle(1, "Flash its socket", "When a trinket's cooldown ends, its socket flashes.", "trinkets", "notify"),
			notifyChat = Toggle(2, "Say so in chat", nil, "trinkets", "notifyChat"),
		}),
		show = Card(6, "Visibility", {
			alpha = Range(1, "Opacity", nil, "trinkets", "alpha", 0, 1, 0.05, true),
			mouseover = Toggle(2, "Show on mouseover only", nil, "trinkets", "mouseover"),
		}),
		auto1 = AutoSwapCard(7, 1),
		auto2 = AutoSwapCard(8, 2),
		place = PositionCard(9, "Right of the console by default. " .. UNLOCK, function() ns.Trinket.ResetPosition() end, function() return not DB().trinkets.moved end),
	}
end

local function SwingArgs()
	return {
		intro = Note(1, "A bar for each weapon that fills as your next auto attack winds up, and stays full while the swing is ready. While your target is out of a weapon's reach, its bar dims once the swing in hand is done. Haste mid-swing stretches or shortens what's left. Blizzard has a swing timer of its own (Options > Combat); turn one of them off so you don't see two."),
		unsupported = {
			type = "description", order = 1.5, fontSize = "medium",
			name = "|cffff6060This client has no swing timer events, so the bars can't run.|r",
			hidden = function() return ns.Swing.Supported() end,
		},
		enabled = Toggle(2, "Enabled", nil, "swing", "enabled"),
		preview = Width({
			type = "toggle", order = 3, name = "Preview",
			desc = "Show every enabled bar on looping practice swings. Also shown while frames are unlocked, so you can place them. Turns off on /reload.",
			get = function() return ns.Swing.preview end,
			set = function(_, value) ns.Swing.SetPreview(value) end,
		}, HALF),
		bars = Card(4, "Bars", {
			mainHand = Third(Toggle(1, "Main hand", nil, "swing", "mainHand")),
			offHand = Third(Toggle(2, "Off hand", "Shown while you dual wield.", "swing", "offHand")),
			ranged = Third(Toggle(3, "Ranged", "Auto Shot, Shoot and throws.", "swing", "ranged")),
			show = Width(Select(4, "Shown", nil, "swing", "show", {
				combat = "In combat, once that weapon has swung",
				always = "Always",
				swinging = "Only while a swing runs",
			}, { "combat", "always", "swinging" }), 1),
		}),
		look = Card(5, "Look", {
			scale = Range(1, "Scale", "100% is the D3 bar's own size.", "swing", "scale", 0.5, 2.5, 0.05, true),
			width = Range(2, "Length", "In the bar's art pixels; D3's own bar is 296.", "swing", "width", 120, 600, 1),
			spacing = Range(3, "Spacing", nil, "swing", "spacing", 0, 20, 1),
			icons = Third(Toggle(4, "Weapon icons", nil, "swing", "icons")),
			time = Third(Toggle(5, "Time left", nil, "swing", "time")),
			rangeFade = Third(Toggle(6, "Dim out of reach", "Dim a bar, and redden its icon, while your target is out of that weapon's reach.", "swing", "rangeFade")),
		}),
		resets = Card(5.5, "Skills that reset the swing", {
			note = Note(1, function()
				local _, class = UnitClass("player")
				local names = {}
				for _, id in ipairs(ns.Swing.RESETS[class] or {}) do
					local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
					names[#names + 1] = (name and not ns.Secret(name)) and name or tostring(id)
				end
				local own = #names > 0 and ("Yours already: " .. table.concat(names, ", ") .. ". ") or ""
				return "Some skills start your main-hand swing over without the game counting a swing, so the bar would run on. " .. own .. "If another skill does it, name it here."
			end),
			resets = Width({
				type = "input", order = 2, name = "More skills",
				desc = "Skill names or spell IDs, commas between, e.g. Pummel, 6552. Every rank of a named skill counts.",
				get = function() return DB().swing.resets end,
				set = function(_, value) DB().swing.resets = value Changed() end,
			}, 1),
		}),
		place = PositionCard(6, "Under your character by default. " .. UNLOCK, function() ns.Swing.ResetPosition() end, function() return not DB().swing.moved end),
	}
end

---------------------------------------------------------------------------
-- Rows

local VISIBILITY = {
	always = "Always",
	combat = "In combat only",
	nocombat = "Out of combat only",
	custom = "Custom conditional",
}

-- "Page 6", or "Page 6 (bar 3)" while something else shows it. Bar n itself doesn't count.
local function PageLabel(page, n)
	local users = ns.ActionBar.PageUsers(page, n)
	if #users > 0 then
		return ("Page %d (%s)"):format(page, table.concat(users, ", "))
	end
	return "Page " .. page
end

-- The main bar's last 3 buttons are too few for the console's twelve sockets.
local function OffersMainButtons(n)
	return not (n and DB().rows[n].docked)
end

local function SourceValues(n)
	local values = {}
	if OffersMainButtons(n) then
		values.main = "Main bar's last 3 buttons"
	end
	for _, page in ipairs(ns.ActionBar.PAGE_LIST) do
		values[page] = PageLabel(page, n)
	end
	return values
end

local function SourceOrder(n)
	local order = {}
	if OffersMainButtons(n) then
		order[1] = "main"
	end
	for _, page in ipairs(ns.ActionBar.PAGE_LIST) do
		order[#order + 1] = page
	end
	return order
end

-- A bar setting that only applies outside the console.
local function Undocked(n, option)
	option.disabled = function() return DB().rows[n].docked end
	return option
end

-- Bars > Bar n: this bar's own page for each stance or form. Nil for classes without any.
local function RowFormGroup(n)
	local _, class = UnitClass("player")
	local map = ns.ActionBar.CLASS_PAGES[class]
	if not map then return nil end
	local opt = function() return DB().rows[n] end
	local pages = ns.ActionBar.PAGE_LIST
	local args = {
		follow = {
			type = "toggle",
			order = 1,
			name = "Change with stance or form",
			desc = "This bar shows another action page in each form you pick. Each page holds its own spells: shift, then drag spells onto the bar.",
			width = "full",
			get = function() return opt().followForms end,
			set = function(_, value)
				opt().followForms = value
				Changed()
			end,
		},
		clashes = {
			type = "description",
			order = 50,
			name = function()
				return "|cffff8a60Shared pages:|r " .. table.concat(ns.ActionBar.RowFormClashes(n), "; ") .. ". Spells changed in one place change in the other."
			end,
			hidden = function() return #ns.ActionBar.RowFormClashes(n) == 0 end,
		},
	}
	for i, form in ipairs(map) do
		local key = class .. "." .. form.key
		local stay = form.sameAs and ("Same as " .. form.sameAs) or "Stay on this bar's page"
		local sorting = { 0 }
		for _, page in ipairs(pages) do
			sorting[#sorting + 1] = page
		end
		args[form.key] = {
			type = "select",
			order = 1 + i,
			name = form.label,
			width = "relative",
			relWidth = THIRD,
			values = function()
				local values = { [0] = stay }
				for _, page in ipairs(pages) do
					values[page] = PageLabel(page, n)
				end
				return values
			end,
			sorting = sorting,
			disabled = function() return not opt().followForms end,
			get = function() return tonumber(opt().formPages[key]) or 0 end,
			set = function(_, value)
				opt().formPages[key] = value ~= 0 and value or nil
				Changed()
			end,
		}
	end
	return {
		type = "group",
		inline = true,
		order = 4,
		name = Gold("Stances and forms"),
		hidden = function() return opt().source == "main" end,
		args = args,
	}
end

local function RowGroup(n, order)
	local path = "rows." .. n
	local opt = function() return DB().rows[n] end
	local source = Width(Select(1, "Spells from", "WoW keeps your spells on numbered pages of 12 buttons. Pick which page this bar shows. Two bars on the same page show the same spells. Pages 3-6 and 13-15 use the keys set for Blizzard's action bars in Key Bindings; for other pages, set keys with hover-binding.", path, "source", function() return SourceValues(n) end, function() return SourceOrder(n) end), HALF)
	source.get = function()
		local value = opt().source
		return value == "main" and "main" or tonumber(value)
	end
	return {
		type = "group",
		order = order,
		-- Bars that are off read dimmed on the tabs, so the ones in use stand out.
		name = function()
			return opt().enabled and ("Bar " .. n) or ("|cff808080Bar " .. n .. "|r")
		end,
		args = {
			enabled = Toggle(1, "Enabled", nil, path, "enabled"),
			docked = (function()
				local option = Toggle(2, "In the console", "Set this bar into the console: a row of twelve stone sockets between the globes, with the XP rail and the centre skull lifted to sit on top. Up to three bars, stacked in bar order. In the console the bar fills all twelve sockets, so a bar on the main bar's last 3 buttons moves to a free action page and takes its spells and keys with it. Size, spacing and position below don't apply while it's in the console.", path, "docked")
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
			spells = Card(3, "Spells", {
				source = source,
				-- The main bar has 12 actions and the console holds 9, so a main-bar row has at most
				-- 3. Two sliders so the range matches the source.
				count = Width({
					type = "range",
					order = 2,
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
				}, THIRD),
				countMain = Width({
					type = "range",
					order = 2,
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
				}, THIRD),
				countNote = {
					type = "description",
					order = 3,
					name = Muted("The console shows the main bar's first 9 buttons, so these are the 3 left over. They change along with the main bar. Pick a page for a full 12-button bar."),
					hidden = function() return opt().source ~= "main" end,
				},
				countDocked = {
					type = "description",
					order = 4,
					name = Muted("In the console this bar fills all twelve sockets."),
					hidden = function() return not ns.ActionBar.DockIndex(n) end,
				},
			}),
			forms = RowFormGroup(n),
			size = Card(5, "Size and spacing", {
				scale = Undocked(n, Range(1, "Button size", "Relative to a main-bar socket.", path, "scale", 0.5, 1.2, 0.01, true)),
				spacing = Undocked(n, Range(2, "Spacing", nil, path, "spacing", 0, 20, 1)),
				perLine = Undocked(n, Range(3, "Buttons per line", "Wrap the bar into a grid. 1 makes it vertical.", path, "perLine", 1, 12, 1)),
			}),
			show = Card(6, "Visibility", {
				visibility = Select(1, "Show", nil, path, "visibility", VISIBILITY),
				alpha = Range(2, "Opacity", nil, path, "alpha", 0, 1, 0.05, true),
				mouseover = Width(Toggle(3, "Show on mouseover only", "Invisible until the mouse is over the bar.", path, "mouseover"), THIRD),
				custom = (function()
					local get, set = Field(path, "custom")
					return {
						type = "input",
						order = 4,
						name = "Custom conditional",
						desc = "A macro conditional, e.g. [combat][mod:shift] show; hide",
						width = "full",
						get = get,
						set = set,
						hidden = function() return opt().visibility ~= "custom" end,
					}
				end)(),
			}),
			place = PositionCard(7, function()
				if opt().docked then
					return ns.ActionBar.DockIndex(n) and "In the console." or "In the console, but three bars are there already: this one stacks above."
				end
				if opt().moved then
					return "Moved: this bar keeps its own position."
				end
				return "Stacked above the console. " .. UNLOCK
			end, function() ns.ActionBar.ResetRowPosition(n) end, function() return not opt().moved or opt().docked end),
		},
	}
end

---------------------------------------------------------------------------
-- Paging

-- Main bar: the console's sockets and what swaps its page.
local function MainBarArgs()
	local path = "paging"
	local args = {
		sockets = Card(1, "Sockets", {
			iconSize = Range(1, "Icon size", "Skill icons in the console's sockets, docked bars included. Below 100% they sit centred in the socket with its stone around them; the console keeps its size.", nil, "iconSize", 0.6, 1, 0.01, true),
		}),
		paging = Card(2, "Paging", {
			note = Note(1, "Swaps the main bar, and bars set to follow it, to another action page. Page numbers follow Blizzard's action pages."),
			possess = Toggle(2, "Vehicle, possess and override bars", "Swap to the vehicle or possess bar when one is active.", path, "possess"),
			barPaging = Toggle(3, "Action bar paging", "Follow Blizzard's bar page (Shift + number, Shift + mouse wheel).", path, "barPaging"),
			stances = Toggle(4, "Stance and form pages", nil, path, "stances"),
		}),
		mods = Card(4, "Modifier pages (0 = off)", {
			ctrl = Range(1, "Ctrl page", nil, path, "ctrl", 0, 10, 1),
			alt = Range(2, "Alt page", nil, path, "alt", 0, 10, 1),
			shift = Range(3, "Shift page", nil, path, "shift", 0, 10, 1),
		}),
		adv = Card(5, "Advanced", {
			custom = (function()
				local get, set = Field(path, "custom")
				return {
					type = "input",
					order = 1,
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
				order = 2,
				name = function() return Gold("In use:") .. " " .. ns.ActionBar.PageDriver() end,
			},
		}),
	}
	local _, class = UnitClass("player")
	local map = ns.ActionBar.CLASS_PAGES[class]
	if map then
		args.forms = Card(3, "Forms", {})
		for i, entry in ipairs(map) do
			local key = class .. "." .. entry.key
			args.forms.args[entry.key] = Width({
				type = "toggle",
				order = i,
				name = ("%s (page %d)"):format(entry.label, entry.page),
				get = function() return DB().paging.forms[key] end,
				set = function(_, value)
					DB().paging.forms[key] = value
					Changed()
				end,
				disabled = function() return not DB().paging.stances end,
			}, HALF)
		end
	end
	return args
end

---------------------------------------------------------------------------

-- The tree says what you're setting up, grouped by where it is on screen; tabs and cards on
-- a page split it by aspect. Settings keep their saved names wherever a page puts them.
-- The Target and Focus pages: one layout (TargetPlate.lua builds both frames), for the settings
-- ns.DB()[K] and the frame's module M.
local function UnitPlatePage(K, M, order, title, intro, placeNote)
	local WHO = title:lower() -- "target" or "focus", in the descriptions
	local TOT = "Target of " .. WHO
	-- Greys a target aura setting out while its buffs / debuffs are off.
	local function TargetAura(key, option)
		option.disabled = function() return not ns.DB()[K][key] end
		return option
	end

	-- A target text option, greyed out while that text is off.
	local function TargetText(key, option)
		option.disabled = function()
			local value = ns.DB()[K][key]
			return value == false or value == "none"
		end
		return option
	end

	local function StyledTarget()
		return (ns.DB()[K].style or "d3") ~= "d3"
	end

	local function AuraLayoutKey()
		local t = ns.DB()[K]
		for key, layout in pairs(AURA_LAYOUTS) do
			local match = true
			for field, value in pairs(layout) do
				if t[field] ~= value then
					match = false
					break
				end
			end
			if match then return key end
		end
		return "custom"
	end

	-- Beside the frame, "Align to" means top, middle or bottom, and icons run in columns.
	local function AuraSide(posKey)
		local pos = ns.DB()[K][posKey]
		return pos == "left" or pos == "right"
	end

	local function AuraAlignValues(posKey)
		return function()
			if AuraSide(posKey) then
				return { left = "Top", center = "Middle", right = "Bottom" }
			end
			return { left = "Left", center = "Centre", right = "Right" }
		end
	end

	return Page(order, title, {
		intro = Note(1, intro),
		enabled = Toggle(2, "Enabled", nil, K, "enabled"),
		preview = Width({
			type = "toggle",
			order = 3,
			name = "Preview",
			desc = "With no " .. WHO .. ", show a stand-in monster that cycles the normal, elite, rare and boss frames while its health drops, to judge the look in game.",
			get = function() return M.preview end,
			set = function(_, value) M.SetPreview(value) end,
		}, HALF),
		frame = Tab(1, "Frame", {
			look = Card(1, "Style and size", {
				style = Select(1, "Style", "The look of the frame. Monster bar is D3's own enemy bar. The others are rendered for SanctuaryUI: a portrait socket, one health bar and a resource bar.", K, "style", TARGET_STYLES, TARGET_STYLE_ORDER),
				scale = Range(2, "Scale", "100% is D3's own size: the art one-to-one at 1080p, the same share of the screen at any resolution.", K, "scale", 0.5, 2, 0.05, true),
				width = Range(3, "Width", "Stretches the frame and bar between their ornaments; the portrait and the frame's ends keep their size.", K, "width", 0.6, 2.5, 0.05, true),
				height = Range(4, "Height", "Makes the health bar taller or shorter; the frame's lips and ornaments keep their size. In the other styles the portrait socket grows with it, and Bracket's ring stays round.", K, "height", 0.7, 3, 0.05, true),
				rankWidth = (function()
					local option = Select(5, "Width by rank", "D3 draws bosses far wider than ordinary monsters. Same frame width keeps the frame, the portrait and the target of target still as you change targets; same bar width keeps the health bar one length and lets the ornaments differ. Monster bar style only.", K, "rankWidth", { frame = "Same frame width", bar = "Same bar width", d3 = "Grows with rank (D3)" }, { "frame", "bar", "d3" })
					option.disabled = StyledTarget
					return option
				end)(),
			}),
			shows = Card(2, "Shows", {
				portrait = (function()
					local option = Toggle(1, title .. " portrait", "The " .. WHO .. "'s moving WoW portrait in a D3 hero portrait frame, left of the bar: silver for ordinary monsters, gold for elites and rares, the winged demon for bosses. The rendered styles always show it, in their own socket.", K, "portrait")
					option.disabled = StyledTarget
					return option
				end)(),
				cast = Toggle(2, "Cast bar", nil, K, "cast"),
				power = Toggle(3, "Resource bar", "The " .. WHO .. "'s mana, rage or energy. In the Monster bar it runs along the bottom of the health bar; the other styles have a groove for it.", K, "power"),
				healPrediction = Toggle(4, "Heal prediction", "Heals on their way to your " .. WHO .. " show in green past the end of its health, damage shields in silver after them, and a silver glow lights the bar's end when the shield is bigger than the health missing.", K, "healPrediction"),
				raidIcon = Toggle(5, "Raid marker", "The skull, cross or other marker on the " .. WHO .. ", for anyone in your group who set one.", K, "raidIcon"),
				classColor = Toggle(6, "Class colour on player names", "A player's name in their class colour, instead of cream.", K, "classColor"),
				classIcon = Toggle(7, "Class icon on players", "The class crest at the portrait's corner. With no portrait, in a row left of the frame.", K, "classIcon"),
				factionIcon = Toggle(8, "Faction emblem on players", "Alliance or Horde, whether or not they are flagged for PvP.", K, "factionIcon"),
			}),
			effects = Card(3, "Effects", {
				liquid = Third(Toggle(1, "Liquid in the bar", "The globes' liquid drifting through the health bar.", K, "liquid")),
				edgeGlow = Third(Toggle(2, "Edge glow", "An ember burning at the health bar's leading edge.", K, "edgeGlow")),
				textGlow = Third(Toggle(3, "Soft glow behind text", "A soft dark glow around the name and numbers on the bars, so they stay easy to read on red, green or amber.", K, "textGlow")),
			}),
			place = PositionCard(4, placeNote .. " " .. UNLOCK, function() M.ResetPosition() end, function() return not DB()[K].moved end),
		}),
		tot = Tab(2, TOT, {
			card = Card(1, TOT, {
				tot = Toggle(1, "Show " .. TOT:lower(), "Who your " .. WHO .. " is attacking: a small monster bar with its portrait, right of the " .. WHO .. "'s frame. Its name turns red when it's you. Left-click targets it, right-click opens its menu.", K, "tot"),
				totPortrait = (function()
					local option = Toggle(2, "Portrait", "The " .. TOT:lower() .. "'s portrait in its silver ring, left of its bar. Off, the bar alone sits beside the " .. WHO .. "'s frame.", K, "totPortrait")
					option.disabled = function() return DB()[K].tot == false or StyledTarget() end
					return option
				end)(),
				totWidth = (function()
					local option = Range(3, "Width", "Stretches its frame and bar between their ornaments.", K, "totWidth", 0.6, 3, 0.05, true)
					option.disabled = function() return DB()[K].tot == false end
					return option
				end)(),
				totHeight = (function()
					local option = Range(4, "Height", "Makes its bar taller or shorter. In the other styles its ring keeps its size.", K, "totHeight", 0.7, 3, 0.05, true)
					option.disabled = function() return DB()[K].tot == false end
					return option
				end)(),
			}),
		}),
		text = Tab(3, "Text", {
			health = Card(1, "Health", {
				healthText = Select(1, "Show", "Works in combat too, where enemy health is hidden from addons: the client fills the numbers in.", K, "healthText", HEALTH_TEXTS, HEALTH_ORDER),
				healthNumbers = TargetText("healthText", Select(2, "Numbers", nil, K, "healthNumbers", { short = "Short (2.48M)", full = "Full (2,480,000)", raw = "Plain (2480000)" })),
				healthHideFull = TargetText("healthText", Third(Toggle(3, "Hide at full health", nil, K, "healthHideFull"))),
				healthPos = TargetText("healthText", Select(4, "Position", nil, K, "healthPos", TEXT_POSITIONS, POS_ORDER)),
				healthFont = TargetText("healthText", Select(5, "Font", nil, K, "healthFont", TEXT_FONTS)),
				healthSize = TargetText("healthText", Range(6, "Size", nil, K, "healthSize", 6, 24, 1)),
				healthX = TargetText("healthText", Range(7, "Nudge left / right", nil, K, "healthX", -200, 200, 1)),
				healthY = TargetText("healthText", Range(8, "Nudge up / down", nil, K, "healthY", -60, 60, 1)),
			}),
			name = Card(2, "Name", {
				nameShow = Third(Toggle(1, "Show name", nil, K, "nameShow")),
				namePos = TargetText("nameShow", Select(2, "Position", nil, K, "namePos", TEXT_POSITIONS, POS_ORDER)),
				nameFont = TargetText("nameShow", Select(3, "Font", nil, K, "nameFont", TEXT_FONTS)),
				nameSize = TargetText("nameShow", Range(4, "Size", nil, K, "nameSize", 6, 24, 1)),
				nameX = TargetText("nameShow", Range(5, "Nudge left / right", nil, K, "nameX", -200, 200, 1)),
				nameY = TargetText("nameShow", Range(6, "Nudge up / down", nil, K, "nameY", -60, 60, 1)),
				surnames = TargetText("nameShow", Third(Toggle(7, "Last names", "A player's full name, first and last, here and on the " .. TOT:lower() .. ". Off, first names only.", K, "surnames"))),
			}),
			level = Card(3, "Level", {
				levelShow = Third(Toggle(1, "Show level", nil, K, "levelShow")),
				levelColor = TargetText("levelShow", Select(2, "Colour", "By difficulty: grey, green, yellow, orange or red against your level, as Blizzard colours it.", K, "levelColor", { plain = "Plain", difficulty = "By difficulty" })),
				levelPos = TargetText("levelShow", Select(3, "Position", "The plaque sits under the portrait frame, in its metal. With the portrait off, the level goes in the bar's left end.", K, "levelPos", LEVEL_POSITIONS, LEVEL_ORDER)),
				levelFont = TargetText("levelShow", Select(4, "Font", nil, K, "levelFont", TEXT_FONTS)),
				levelSize = TargetText("levelShow", Range(5, "Size", nil, K, "levelSize", 6, 24, 1)),
				levelX = TargetText("levelShow", Range(6, "Nudge left / right", nil, K, "levelX", -200, 200, 1)),
				levelY = TargetText("levelShow", Range(7, "Nudge up / down", nil, K, "levelY", -60, 60, 1)),
			}),
		}),
		auras = Tab(4, "Auras", {
			arrange = Card(1, "Arrangement", {
				auraLayout = Width({
					type = "select", order = 1, name = "Arrange debuffs and buffs",
					desc = "A starting point, for any style. It sets the position, alignment and icons per line below, and clears their nudges; change those for anything else. Turn on Buffs below to see them.",
					values = AURA_LAYOUT_NAMES, sorting = AURA_LAYOUT_ORDER,
					get = AuraLayoutKey,
					set = function(_, value)
						local layout = AURA_LAYOUTS[value]
						if not layout then return end
						local t = DB()[K]
						for field, v in pairs(layout) do t[field] = v end
						t.auraX, t.auraY, t.buffX, t.buffY = 0, 0, 0, 0
						Changed()
					end,
				}, HALF),
			}),
			debuffs = Card(2, "Debuffs", {
				debuffs = Third(Toggle(1, "Show debuffs", "Every debuff on the " .. WHO .. ": yours first and bright, the rest greyed.", K, "debuffs")),
				maxDebuffs = TargetAura("debuffs", Range(2, "How many", "For your debuffs and other players' debuffs separately: the client hides how many of each there are in combat, so up to twice this can show.", K, "maxDebuffs", 1, 24, 1)),
				auraSize = TargetAura("debuffs", Range(3, "Icon size", nil, K, "debuffSize", 14, 48, 1)),
				auraPos = TargetAura("debuffs", Select(4, "Position", "Beside the frame, icons run down in columns (Icons per line sets how many in each).", K, "auraPos", AURA_POSITIONS, AURA_POSITION_ORDER)),
				auraAlign = TargetAura("debuffs", Select(5, "Align to", "Where each line starts: the bar's left end, centre or right end. Beside the frame: its top, middle or bottom.", K, "auraAlign", AuraAlignValues("auraPos"))),
				auraGrow = (function()
					local option = TargetAura("debuffs", Select(6, "Grow", "From a left or right end, which way the icons run. Centred lines grow both ways.", K, "auraGrow", { right = "To the right", left = "To the left" }))
					local off = option.disabled
					option.disabled = function() return off() or AuraSide("auraPos") end
					return option
				end)(),
				auraPerLine = TargetAura("debuffs", Range(7, "Icons per line", nil, K, "auraPerLine", 1, 24, 1)),
				auraSpacing = TargetAura("debuffs", Range(8, "Spacing", nil, K, "auraSpacing", 0, 16, 1)),
				auraSpacer = Note(8.5, ""),
				auraX = TargetAura("debuffs", Range(9, "Nudge left / right", nil, K, "auraX", -300, 300, 1)),
				auraY = TargetAura("debuffs", Range(10, "Nudge up / down", nil, K, "auraY", -200, 200, 1)),
			}),
			buffs = Card(3, "Buffs", {
				buffs = Third(Toggle(1, "Show buffs", "The " .. WHO .. "'s buffs, laid out on their own.", K, "buffs")),
				maxBuffs = TargetAura("buffs", Range(2, "How many", nil, K, "maxBuffs", 1, 24, 1)),
				buffSize = TargetAura("buffs", Range(3, "Icon size", nil, K, "buffSize", 14, 48, 1)),
				buffPos = TargetAura("buffs", Select(4, "Position", "Laid out the same as the debuffs, the buffs start on the line (or column) after them.", K, "buffPos", AURA_POSITIONS, AURA_POSITION_ORDER)),
				buffAlign = TargetAura("buffs", Select(5, "Align to", "Where each line starts: the bar's left end, centre or right end. Beside the frame: its top, middle or bottom.", K, "buffAlign", AuraAlignValues("buffPos"))),
				buffGrow = (function()
					local option = TargetAura("buffs", Select(6, "Grow", "From a left or right end, which way the icons run. Centred lines grow both ways.", K, "buffGrow", { right = "To the right", left = "To the left" }))
					local off = option.disabled
					option.disabled = function() return off() or AuraSide("buffPos") end
					return option
				end)(),
				buffPerLine = TargetAura("buffs", Range(7, "Icons per line", nil, K, "buffPerLine", 1, 24, 1)),
				buffSpacing = TargetAura("buffs", Range(8, "Spacing", nil, K, "buffSpacing", 0, 16, 1)),
				buffSpacer = Note(8.5, ""),
				buffX = TargetAura("buffs", Range(9, "Nudge left / right", nil, K, "buffX", -300, 300, 1)),
				buffY = TargetAura("buffs", Range(10, "Nudge up / down", "Laid out the same as the debuffs, this is from the end of the debuffs.", K, "buffY", -200, 200, 1)),
			}),
		}),
	}, "tab")
end

local function Build()
	local options = {
		type = "group",
		name = "SanctuaryUI",
		childGroups = "tree",
		args = {
			sectionSetup = Section(0, "Setup"),
			general = Page(1, "General", {
				moving = Card(1, "Moving frames", {
					locked = Toggle(1, "Lock frames", "When unlocked, each frame shows a mover: drag it to move that frame, or hover it and use the arrow keys to nudge (Shift: 10). The target frame shows a stand-in while unlocked.", nil, "locked"),
					snapping = Toggle(2, "Bar snapping", "While dragging, the console, bars and other frames snap to each other's edges and centres and to the screen's edges and centre, as in Bartender4. Hold Shift while dragging to place one freely.", nil, "snapping"),
					grid = Toggle(3, "Show grid", "While frames are unlocked, draw a grid like Edit Mode's, its centre lines brighter, and snap frames' edges and centres to its lines (with Bar snapping on).", nil, "grid"),
					gridSize = (function()
						local option = Range(4, "Grid spacing", "Distance between grid lines, counted out from the screen's centre.", nil, "gridSize", ns.Snap.GRID_MIN, ns.Snap.GRID_MAX, 5)
						option.disabled = function() return not DB().grid end
						return option
					end)(),
				}),
				size = Card(2, "Console size", {
					scale = Range(1, "Bar scale", "The console between the globes: its bars, including bars set into it, the menu and the rail.", nil, "scale", 0.5, 1.8, 0.01, true),
					globeScale = Range(2, "Globe scale", "The globes and their statues. They stay on the ends of the bar, bottoms level, and the art round each globe is fitted to it whatever the two scales.", nil, "globeScale", 0.5, 1.8, 0.01, true),
					match = Width({
						type = "execute",
						order = 3,
						name = "Match globes to bars",
						desc = "Set the globe scale to the bar scale.",
						func = function()
							local db = DB()
							db.globeScale = db.scale
							Changed()
						end,
					}, THIRD),
					reset = {
						type = "execute",
						order = 4,
						name = "Reset position",
						func = function()
							local db = DB()
							db.point, db.rel, db.x, db.y, db.posUI = "BOTTOM", "BOTTOM", 0, 0, true
							Changed()
						end,
					},
				}),
				other = Card(3, "Other", {
					hideMicroMenu = Toggle(1, "Hide Blizzard micro menu", "The console's menu buttons replace it. If it comes back misplaced after turning this off, /reload.", nil, "hideMicroMenu"),
					minimap = Width({
						type = "toggle",
						order = 2,
						name = "Minimap button",
						desc = "Left-click opens these options, right-click locks or unlocks frames. Drag it around the minimap.",
						get = function() return not ns.db.global.minimap.hide end,
						set = function(_, value) ns.Minimap.SetShown(value) end,
					}, HALF),
					hearthItem = Width({
						type = "input",
						order = 3,
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
					}, THIRD),
				}),
			}),

			gap10 = Gap(9),
			sectionConsole = Section(10, "Console"),
			globes = Page(11, "Globes", {
				text = Card(1, "Numbers", {
					numbers = Select(1, "Show numbers", nil, nil, "numbers", { on = "Always", combat = "In combat (and on mouseover)", hover = "On mouseover (like D3)", off = "Never" }),
					numberSize = Range(2, "Number size", nil, nil, "numberSize", 12, 34, 1),
					numbersMax = Third(Toggle(3, "Show maximum under value", nil, nil, "numbersMax")),
				}),
				liquid = Card(2, "Liquid", {
					liquidStyle = Select(1, "Liquid style", "Classic is D3's layered tiles. Rendered is a test style: a looping 3D render with real depth, which boils at low health. It uses more video memory (about 48 MB) and only loads while it is selected. Changes straight away.", nil, "liquidStyle", { classic = "Classic", rendered = "Rendered (test)" }),
					liquidSpeed = Range(2, "Swirl speed", nil, nil, "liquidSpeed", 0.25, 3, 0.05, true),
					liquidAnimate = Third(Toggle(3, "Swirl", "Animate the globe liquid.", nil, "liquidAnimate")),
				}),
				warnings = Card(3, "Warnings", {
					lowHealthPulse = Toggle(1, "Low health heartbeat", "The health globe pulses below 35%, faster as it empties.", nil, "lowHealthPulse"),
					lowHealthAgitate = Toggle(2, "Restless at low health", "Below half health the health globe's liquid turns faster and sloshes on its own, more and more as health falls to 10%.", nil, "lowHealthAgitate"),
					pollution = Toggle(3, "Debuffs pollute the health globe", "While you carry a poison, disease, curse or magic debuff, its colour bleeds into your health globe until it wears off or is cleansed. /sanctuary pollute poison, disease, curse or magic shows the look without the debuff. Uses about 28 MB of video memory while on.", nil, "pollution"),
				}),
				prediction = Card(4, "Prediction", {
					healPrediction = Toggle(1, "Incoming heals", "Heals on their way to you show as pale green liquid poured on top of the health globe.", nil, "healPrediction"),
					absorbPrediction = Toggle(2, "Absorb shields", "Damage shields (Power Word: Shield and the like) show as silver liquid above your health and incoming heals. A shield bigger than the room left, as at full health, lights a silver glow round the inside of the globe.", nil, "absorbPrediction"),
					costPrediction = Toggle(3, "Spell cost", "While you cast, the part of your resource the spell will spend lights up at the top of the resource globe.", nil, "costPrediction"),
				}),
			}),
			globeAuras = Page(12, "Globe auras", GlobeAuraArgs(), "tab"),
			rail = Page(13, "XP & Reputation", {
				rail = Card(1, "Rail", {
					railMode = Width(Select(1, "Rail shows", nil, nil, "railMode", {
						auto = "Experience, then reputation at max level",
						xp = "Experience",
						rep = "Reputation (watched faction)",
					}), HALF),
					spacer = Note(1.5, ""),
					railRested = Toggle(2, "Show rested experience", nil, nil, "railRested"),
					levelPlaque = Toggle(3, "Your level on the console", "Your level in a D3 medallion resting on the skull at the console's top centre.", nil, "levelPlaque"),
					note = Note(4, "Reputation is tinted with your resource colour. Watch a faction from the Reputation panel."),
				}),
			}),

			statues = Page(14, "Statues", {
				note = Note(0, "The console's statues can show a buff of yours: their eyes glow, or the angel's wings light up, while it is on you, in combat too. Only buffs on you count, not debuffs or cooldowns. A change made in combat applies when it ends."),
				angel = StatueEyesCard(1, "angel", "Angel", "Wisps of light stream from under the angel's hood while the buff below is on you."),
				gargoyle = StatueEyesCard(2, "gargoyle", "Gargoyle", "The gargoyle's eye burns, trailing wisps, while the buff below is on you."),
				wings = StatueEyesCard(3, "wings", "Angel's wings", "Golden light runs down the angel's wings, shedding sparks, with a glow behind the statue, while the buff below is on you. Nothing is chosen to start with: name a buff to use it.", "Wings light up under a buff", true),
			}),

			gap20 = Gap(19),
			sectionBars = Section(20, "Action bars"),
			buttons = Page(21, "Buttons", {
				intro = Note(0, "These apply to the buttons on every bar."),
				text = Card(1, "On the button", {
					hotkeys = Third(Toggle(1, "Show keybinds", nil, "buttons", "hotkeys")),
					hotkeySize = (function()
						local option = Range(2, "Keybind size", "Font size of the keybind text on every bar's buttons. Stance and totem sockets use one point less.", "buttons", "hotkeySize", 6, 24, 1)
						option.disabled = function() return not DB().buttons.hotkeys end
						return option
					end)(),
					macroNames = Third(Toggle(3, "Show macro names", nil, "buttons", "macroNames")),
					grid = Toggle(4, "Show empty sockets' grid", "Keep empty buttons visible so actions can be dropped on them.", "buttons", "grid"),
				}),
				behaviour = Card(2, "Behaviour", {
					lock = Toggle(1, "Lock buttons", "Locked buttons only pick up actions while holding Shift. Unlocked buttons drag freely.", "buttons", "lock"),
					keyDown = CVarToggle(2, "Cast on key down", "Blizzard's ActionButtonUseKeyDown.", "ActionButtonUseKeyDown"),
					range = Select(3, "Out of range", nil, "buttons", "range", { button = "Tint the icon", hotkey = "Tint the keybind", none = "Nothing" }),
					tooltips = Select(4, "Tooltips", nil, "buttons", "tooltips", { enabled = "Always", nocombat = "Out of combat", disabled = "Never" }),
				}),
				cooldowns = Card(3, "Cooldowns", {
					cooldownNumbers = (function()
						local option = Select(1, "Cooldown numbers", "The time left on a skill's cooldown, counted down on its button. The global cooldown never shows one.", "buttons", "cooldownNumbers", { cvar = "Blizzard setting", show = "Show", hide = "Hide" })
						local set = option.set
						option.set = function(...)
							-- Choosing Show again asks again to turn on Blizzard's setting.
							if ns.ActionBar then ns.ActionBar.countdownAsked = nil end
							return set(...)
						end
						return option
					end)(),
					cooldownTenths = (function()
						local option = Range(2, "Tenths of a second below", "Cooldowns with less than this many seconds left count down in tenths (4.7). 0 shows whole seconds only.", "buttons", "cooldownTenths", 0, 60, 1)
						option.disabled = function() return DB().buttons.cooldownNumbers == "hide" end
						return option
					end)(),
				}),
				highlights = Card(4, "Skill highlights", {
					procGlow = Toggle(1, "Proc highlight", "When a skill that needs a condition becomes available (Overpower, Revenge, Execute, Riposte, Hammer of Wrath), its socket flashes and sparks chase around it until it is used or lapses. /sanctuary proc shows it.", "buttons", "procGlow"),
					activeGlow = Toggle(2, "Active skill glow", "While a skill's buff, channel or totem is up, its socket burns like D3's.", "buttons", "activeGlow"),
					activeTimer = Toggle(3, "Active skill timer", "A tab in the socket with a yellow bar that drains until the effect ends.", "buttons", "activeTimer"),
					activeEndless = Toggle(4, "Light buffs with no duration", "Stances, paladin auras, aspects and other buffs that never run out glow too. Tracking (Find Minerals, Find Herbs) never does.", "buttons", "activeEndless"),
					activeTimerPos = Select(5, "Timer position", nil, "buttons", "activeTimerPos", { top = "Top of the socket", bottom = "Bottom of the socket" }),
					activeGlowMax = Range(6, "Glow up to (seconds)", "Short effects (Bloodrage, trinkets) burn and show the timer. Longer buffs (Battle Shout) show just the timer tab. Channels, totems and buffs with no duration always glow.", "buttons", "activeGlowMax", 0, 600, 5),
					activeMax = Range(7, "Longest buff to show (seconds)", "Buffs that last longer than this don't light their skill, so long buffs like Fortitude stay quiet. Channels and totems always show.", "buttons", "activeMax", 10, 600, 5),
				}),
			}),
			main = Page(22, "Main bar", MainBarArgs()),
			bars = Page(23, "Bars 2-9", {
				intro = Note(0, "Bars stack above the console, bar 2 lowest, or dock into it. Bars that are off read grey on the tabs."),
			}, "tab"),
			stance = Page(24, "Stance & pet bars", {
				intro = Note(1, "Stances, forms, auras, stealth: whatever your class has. Hidden for classes without any. Keybinds come from Blizzard's Stance Bar bindings, or use hover-binding."),
				enabled = Toggle(2, "Enabled", nil, "stance", "enabled"),
				size = Card(3, "Size and spacing", {
					scale = Range(1, "Button size", "Relative to a main-bar socket.", "stance", "scale", 0.4, 1.2, 0.01, true),
					spacing = Range(2, "Spacing", nil, "stance", "spacing", 0, 20, 1),
					perLine = Range(3, "Buttons per line", "1 makes a vertical bar.", "stance", "perLine", 1, 10, 1),
				}),
				show = Card(4, "Visibility", {
					alpha = Range(1, "Opacity", nil, "stance", "alpha", 0, 1, 0.05, true),
					mouseover = Toggle(2, "Show on mouseover only", nil, "stance", "mouseover"),
				}),
				place = PositionCard(5, "Above the health globe by default. " .. UNLOCK, function() ns.Stance.ResetPosition() end, function() return not DB().stance.moved end),
				pet = Card(6, "Pet bar", {
					pets = Toggle(1, "Show the pet bar", "Pet actions above the bars when you have a pet.", nil, "pets"),
				}),
			}),
			totems = Page(25, "Totem bar", {
				intro = Note(1, "One socket per element, shown once you know a totem. A totem that is down lights its socket, and a round sweep runs out its time."),
				enabled = Toggle(2, "Enabled", nil, "totems", "enabled"),
				preview = Width({
					type = "toggle",
					order = 3,
					name = "Preview",
					desc = "Show the bar with every totem and two on timers, on any character. Nothing casts. Turns off on /reload.",
					get = function() return ns.Totem.preview end,
					set = function(_, value) ns.Totem.SetPreview(value) end,
				}, HALF),
				modeCard = Card(4, "Mode", {
					mode = Width(Select(1, "Mode", nil, "totems", "mode", {
						bar = "Totem bar: cast, pick each socket's totem from a flyout",
						tracker = "Tracker: only show totems that are down",
					}), 1),
					modeNote = Note(2, "Bar mode: left-click casts, right-click dismisses. Shift + right-click a socket to fan out that element's totems: left-click one to put it in the socket, right-click to cast it once. Tracker mode: right-click dismisses. Keybinds are under Key Bindings > AddOns > SanctuaryUI, or use hover-binding."),
				}),
				ring = Card(5, "Globe", {
					attach = Select(1, "Attach to", "Ring a globe's rim like the combo point pips, or stand free as a row you can drag anywhere.", "totems", "attach", {
						none = "Nothing: a free row",
						health = "Health globe",
						resource = "Resource globe",
					}),
					arc = Width({
						type = "range",
						order = 2,
						name = "Position on the rim",
						desc = "Angle of the ring's centre, in degrees: 90 is the top of the globe, 180 its left side, 0 its right. Or unlock frames on the General page and drag the totems around the globe.",
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
					}, THIRD),
					ringGap = (function()
						local r = Range(3, "Distance from the rim", nil, "totems", "ringGap", -20, 40, 1)
						r.hidden = function() return DB().totems.attach == "none" end
						return r
					end)(),
					ringNote = {
						type = "description",
						order = 4,
						name = Muted("Attached, the sockets sit on the rim like the pips and follow the console; each picker fans out on a wider arc. The picker direction and vertical settings apply to the free row only."),
						hidden = function() return DB().totems.attach == "none" end,
					},
				}),
				size = Card(6, "Size and spacing", {
					scale = Range(1, "Button size", "Relative to a main-bar socket.", "totems", "scale", 0.4, 1.2, 0.01, true),
					spacing = Range(2, "Spacing", nil, "totems", "spacing", 0, 20, 1),
					flyout = Select(3, "Picker opens", nil, "totems", "flyout", { up = "Up", down = "Down" }),
					vertical = Toggle(4, "Vertical", "Stack the sockets instead of a row.", "totems", "vertical"),
				}),
				show = Card(7, "Visibility", {
					alpha = Range(1, "Opacity", nil, "totems", "alpha", 0, 1, 0.05, true),
					mouseover = Toggle(2, "Show on mouseover only", nil, "totems", "mouseover"),
				}),
				place = PositionCard(8, "Free row: above the resource globe by default. " .. UNLOCK, function() ns.Totem.ResetPosition() end, function() return not DB().totems.moved end),
			}),
			trinkets = Page(25.5, "Trinkets", TrinketArgs()),
			keybinding = Page(26, "Keybinds", {}),
			pie = Page(27, "Pie menus", PieArgs()),

			gap30 = Gap(29),
			sectionUnits = Section(30, "Unit frames"),
			target = UnitPlatePage("target", ns.TargetPlate, 31, "Target", "Your target's frame. Left-click targets, right-click opens the unit menu. Turning it off brings back Blizzard's target frame.", "Top centre by default."),
			focus = UnitPlatePage("focus", ns.FocusPlate, 31.5, "Focus", "Your focus's frame: the same frame as the target's, for the unit you set with /focus (or Set Focus in a unit menu) and clear with /clearfocus. Left-click targets it, right-click opens the unit menu.", "Left of the target frame by default."),
			portraits = Page(32, "Portraits", {
				intro = Note(1, "D3 portraits, top left: your pet, and you if you want it. Left-click targets, right-click opens the unit menu. Turning it off brings back Blizzard's player frame."),
				enabled = Toggle(2, "Enabled", nil, "portraits", "enabled"),
				preview = Width({
					type = "toggle",
					order = 3,
					name = "Preview",
					desc = "Show both portraits (the pet's drawn from you when you have no pet) to judge them in game.",
					get = function() return ns.Portraits.preview end,
					set = function(_, value) ns.Portraits.SetPreview(value) end,
				}, HALF),
				shows = Card(4, "Shows", {
					player = Third(Toggle(1, "Your portrait", "Right-click it for your unit menu (leave group, loot, raid markers).", "portraits", "player")),
					pet = Third(Toggle(2, "Pet portrait", nil, "portraits", "pet")),
					scale = Range(3, "Scale", "100% is D3's own size.", "portraits", "scale", 0.6, 2.5, 0.05, true),
				}),
				place = PositionCard(5, "Top left by default. " .. UNLOCK, function() ns.Portraits.ResetPosition() end, function() return not DB().portraits.moved end),
			}),
			party = Page(33, "Party", {
				intro = Note(1, "Your party under your portrait. Left-click targets, right-click opens the unit menu, and click-casting addons (Clique) work on them. In a raid they hide and Blizzard's raid frames take over."),
				style = Select(2, "Style", "Globes: a small health globe of your own liquid for each member. Slab: a thin slab of D3 stone. Lintel, Slim Lintel, Forged Bracket, Tablet and Monster bar: the target frame's looks, smaller, gold on your target; pets get a small ring and bar. None: Blizzard's party frames (or another addon's) instead.", "party", "style",
					{ globes = "Globes", slab = "Slab", lintel = "Lintel", slim = "Slim Lintel", bracket = "Forged Bracket", tablet = "Tablet", d3 = "Monster bar (Diablo III)", none = "None (Blizzard or another addon)" },
					{ "globes", "slab", "lintel", "slim", "bracket", "tablet", "d3", "none" }),
				preview = Width({
					type = "toggle",
					order = 3,
					name = "Preview",
					desc = "Show four stand-in members (drawn from you) in different states: leader with aggro, your target with heals, a shield and a debuff you can dispel, dead, out of range. Also shown while frames are unlocked, so you can place them.",
					get = function() return ns.Party.preview end,
					set = function(_, value) ns.Party.SetPreview(value) end,
					disabled = function() return not ns.Party.Style() end,
				}, HALF),
				size = Card(4, "Size and spacing", {
					scale = Range(1, "Scale", "100% is the art's own size.", "party", "scale", 0.5, 2, 0.05, true),
					spacing = Range(2, "Spacing", "The space between party members. Lower squeezes them closer together; far enough in, they overlap.", "party", "spacing", -30, 20, 1),
					stone = Width({
						type = "range",
						order = 3,
						name = "Stone opacity",
						desc = "The slab's stone. Turn it down to let the world show through; the metal stays solid.",
						min = 0.2, max = 1, step = 0.05, isPercent = true,
						get = function() return DB().party.stone end,
						set = function(_, value) DB().party.stone = value Changed() end,
						disabled = function() return DB().party.style ~= "slab" end,
					}, THIRD),
				}),
				shows = Card(5, "Shows", {
					healthText = Select(1, "Health text", nil, "party", "healthText",
						{ none = "Nothing", percent = "Percent (62%)", current = "Hitpoints (15.4K)", missing = "Missing hitpoints (-9.4K)" },
						{ "none", "percent", "current", "missing" }),
					spacer = Note(1.5, ""),
					pets = Toggle(2, "Pets", "Party pets, by their owner.", "party", "pets"),
					portrait3d = Width({
						type = "toggle",
						order = 3,
						name = "3D portraits",
						desc = "The member's moving 3D bust in its socket or ring while they're in view (their 2D portrait otherwise). Globes always use the 2D portrait in the round medallion.",
						get = function() return DB().party.portrait3d end,
						set = function(_, value) DB().party.portrait3d = value Changed() end,
						disabled = function() local st = DB().party.style return st == "globes" or st == "none" end,
					}, HALF),
					healPrediction = Toggle(4, "Incoming heals and shields", "Heals on the way and damage shields poured on top of their health, as on your globe.", "party", "healPrediction"),
					threat = Toggle(5, "Threat halo", "A red halo on a member with aggro (orange as they near it).", "party", "threat"),
					rangeFade = Toggle(6, "Fade out of range", nil, "party", "rangeFade"),
					surnames = Toggle(7, "Last names", "Each member's full name, first and last. Off, first names only, which leaves more room on the Slab.", "party", "surnames"),
				}),
				auras = Card(6, "Auras", {
					debuffs = Toggle(1, "Debuffs", "Their debuffs in D3's debuff frame, coloured by type: blue magic, purple curse, brown disease, green poison.", "party", "debuffs"),
					maxDebuffs = Range(2, "Most debuffs", nil, "party", "maxDebuffs", 1, 8, 1),
					buffs = Toggle(3, "Your buffs on them", "Your heals over time, shields and buffs on each member, in D3's gold frame.", "party", "buffs"),
					maxBuffs = Range(4, "Most buffs", nil, "party", "maxBuffs", 1, 6, 1),
					dispelGlow = Toggle(5, "Dispel halo", "A pulsing halo in the debuff's colour while a member has one you can remove.", "party", "dispelGlow"),
				}),
				place = PositionCard(7, "Under your portrait by default. Stand-ins show while frames are unlocked. " .. UNLOCK .. " Changes wait for the end of combat.", function() ns.Party.ResetPosition() end, function() return not DB().party.moved end),
			}),
			auras = Page(34, "Your buffs", {
				intro = Note(1, "Blizzard's buff and debuff frames set in stone sockets, because this client lets only Blizzard read your buffs in combat. Right-click a buff to cancel it. Turning this off gives Blizzard's look back."),
				enabled = Toggle(2, "Enabled", nil, "auras", "enabled"),
				shows = Card(3, "Shows", {
					duration = Toggle(1, "Time left under each icon", nil, "auras", "duration"),
					bars = Toggle(2, "Countdown bars", "A bar under each timed buff and debuff that runs down, turning red in its last 10 seconds. In combat it shows only while the client lets addons read the time left.", "auras", "bars"),
				}),
				editMode = Card(4, "Position and size", {
					note = Note(1, "Position, icon size, icons per row, how many and wrap direction are Edit Mode's (Esc > Edit Mode, then drag or click the Buff Frame and Debuff Frame). For the D3 look, place them just above the bars with Icon Wrap set to Up."),
				}),
			}),

			swing = Page(35, "Swing timer", SwingArgs()),
			gap40 = Gap(39),
			sectionInventory = Section(40, "Inventory"),
			bags = Page(41, "Bags", {
				enabled = Width(Toggle(1, "Use the SanctuaryUI bag window", "Replaces Blizzard's bags. Turning it off needs a /reload to bring Blizzard's back.", "bags", "enabled"), 1),
				layout = Card(2, "Layout", {
					columns = Range(1, "Columns", nil, "bags", "columns", 6, 20, 1),
					slotSize = Range(2, "Slot size", nil, "bags", "slotSize", 28, 52, 1),
					spacing = Range(3, "Spacing", nil, "bags", "spacing", 0, 8, 1),
					scale = Range(4, "Scale", nil, "bags", "scale", 0.5, 1.6, 0.01, true),
					backpackPos = Select(5, "Backpack", "Where the backpack's slots sit among your bags. At the bottom, the bags run last to first and the backpack ends in the bottom-right corner.", "bags", "backpackPos", { top = "Top of the grid", bottom = "Bottom of the grid" }, { "top", "bottom" }),
					slotRowPos = Select(6, "Bag slots and search", nil, "bags", "slotRowPos", { top = "Above the items", bottom = "Below the items" }, { "top", "bottom" }),
					dividers = Toggle(7, "Divide bags", "Start each bag on its own line, with a divider between bags. Off: one combined grid.", "bags", "dividers"),
				}),
				look = Card(3, "Look and behaviour", {
					quality = Toggle(1, "Quality backgrounds", "D3's colored cell backgrounds for uncommon, rare, epic, legendary and heirloom items.", "bags", "quality"),
					bagSlots = Toggle(2, "Show bag slots", "Your backpack and bag slots in a line beside the search box: drag bags on to equip or swap them.", "bags", "bagSlots"),
					autoSellJunk = Toggle(3, "Sell junk automatically", "Sell grey items whenever a vendor opens. Off: use the Sell Junk button on the bag window.", "bags", "autoSellJunk"),
				}),
				place = PositionCard(4, "Drag the window by its stone to move it.", function()
					local opt = DB().bags
					opt.point, opt.x, opt.y = "BOTTOMRIGHT", -60, 260
					Changed()
				end),
			}),
			bank = Page(42, "Bank", {
				enabled = Width(Toggle(1, "Use the SanctuaryUI bank window", "D3's stash in place of Blizzard's bank. Needs the bag window on. Turning it off needs a /reload.", "bank", "enabled"), 1),
				layout = Card(2, "Layout", {
					columns = Range(1, "Columns", nil, "bank", "columns", 6, 24, 1),
					slotSize = Range(2, "Slot size", nil, "bank", "slotSize", 28, 52, 1),
					spacing = Range(3, "Spacing", nil, "bank", "spacing", 0, 8, 1),
					scale = Range(4, "Scale", nil, "bank", "scale", 0.5, 1.6, 0.01, true),
					dividers = Width(Toggle(5, "Divide bank tabs", "Each bank tab on its own lines, with a divider between them.", "bank", "dividers"), 0.666),
				}),
				look = Card(3, "Look", {
					quality = Toggle(1, "Quality backgrounds", nil, "bank", "quality"),
					bagSlots = Toggle(2, "Show bank bag slots", "The base bank and your bank bag slots across the top: drag bags on to equip them.", "bank", "bagSlots"),
				}),
				place = PositionCard(4, "Drag the window by its stone to move it.", function()
					local opt = DB().bank
					opt.point, opt.x, opt.y = "TOPLEFT", 40, -120
					Changed()
				end),
			}),

			feedback = Page(3, "Feedback", {
				note = Note(1, "Each of these gives you a link to paste into a browser. Nothing is sent until you submit it on GitHub."),
				request = {
					type = "execute",
					order = 2,
					name = "Suggest a feature",
					func = function()
						LibStub("AceConfigDialog-3.0"):Close(APP)
						ns.ShowRequest()
					end,
				},
				report = {
					type = "execute",
					order = 3,
					name = "Report a bug",
					desc = "Makes a report from the errors SanctuaryUI has recorded on this version.",
					func = function()
						LibStub("AceConfigDialog-3.0"):Close(APP)
						ns.ShowReport()
					end,
				},
			}),
		},
	}
	for i, n in ipairs(ns.ActionBar.ROW_IDS) do
		options.args.bars.args["row" .. n] = RowGroup(n, i)
	end
	local profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(ns.db)
	profiles.order = 2
	profiles.name = TreeRow(profiles.name)
	options.args.profiles = profiles
	return options
end

-- The keybinding page lists the buttons of the rows in use, so it is rebuilt on open.
local function Table()
	local options = ns.Options.table or Build()
	ns.Options.table = options
	options.args.keybinding.args = KeybindArgs()
	return options
end

function ns.Options.Init()
	local AceConfig = LibStub("AceConfig-3.0")
	local Dialog = LibStub("AceConfigDialog-3.0")
	AceConfig:RegisterOptionsTable(APP, Table)
	Dialog:SetDefaultSize(APP, 900, 680)
	Dialog:AddToBlizOptions(APP, "SanctuaryUI")
end

-- page: a tree row's key to open on (then the window opens rather than toggles).
function ns.Options.Open(page)
	local Dialog = LibStub("AceConfigDialog-3.0")
	if page then
		Dialog:Open(APP)
		Dialog:SelectGroup(APP, page)
	elseif Dialog.OpenFrames[APP] then
		Dialog:Close(APP)
	else
		Dialog:Open(APP)
	end
end
