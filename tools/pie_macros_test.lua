-- Run from the repo root: lua5.1 tools/pie_macros_test.lua [SanctuaryUI/PieMenu.lua]
-- Offline check for #23: macro lookup in PieMenu.lua against a stand-in macro list.
SanctuaryUI = {}
local printed = {}
local db = { profile = { pie = { scale = 1, rings = {} } }, char = {} }
SanctuaryUI.DB = function() return db.profile end
SanctuaryUI.db = db
SanctuaryUI.Print = function(m) printed[#printed + 1] = m end
Constants = { MacroConsts = { MAX_ACCOUNT_MACROS = 120, MAX_CHARACTER_MACROS = 30 } }
local macros = {}
function GetMacroInfo(i) local m = macros[i]; if m then return m[1], 1, m[2] end end
local f = assert(io.open(arg[1] or "SanctuaryUI/PieMenu.lua")); local src = f:read("*a"); f:close()
src = src .. "\nns.Pie._t = { FindMacro = FindMacro, Action = Action, Schedule = ScheduleNotice, DeadPicked = DeadPicked,\n" ..
	"ResetSession = function() noticeScheduled = false end, SetDead = function(d) dead = d end, SetLive = function(l) live = l end }\n"
assert(loadstring(src, "PieMenu.lua"))()
local T = SanctuaryUI.Pie._t
local fails = 0
local function check(label, got, want)
  local ok = got == want
  if not ok then fails = fails + 1 end
  print((ok and "ok   " or "FAIL ") .. label .. "  got " .. tostring(got) .. " want " .. tostring(want))
end
-- General: 1 blank-named (sorts first), 2 "Heal"; character: 121-124 blank-named totem macros, 125 "Bloodlust", 126 "Heal"
macros = {
  [1] = { " ", "/say first" }, [2] = { "Heal", "/cast Healing Wave" },
  [121] = { " ", "/cast Windfury Weapon" }, [122] = { " ", "/cast Fire Resistance Totem" },
  [123] = { " ", "/cast Frost Resistance Totem" }, [124] = { " ", "/cast Nature Resistance Totem" },
  [125] = { "Bloodlust", "/cast Bloodlust" }, [126] = { "Heal", "/cast Lesser Healing Wave" },
}
-- blank names, own text: each finds its own macro
for i, idx in ipairs({ 121, 122, 123, 124 }) do
  local s = { kind = "macro", name = " ", body = macros[idx][2] }
  local k, v = T.Action(s)
  check("blank-named slice " .. i .. " runs its own macro", v, idx)
  check("  and keeps its own text", s.body, macros[idx][2])
end
-- blank name, text edited since: no guess, runs its saved text, body untouched
local s = { kind = "macro", name = " ", body = "/cast Windfury Weapon\n/say old" }
local k, v, attr = T.Action(s)
check("blank name, edited text: macrotext", attr, "macrotext")
check("  saved text kept", s.body, "/cast Windfury Weapon\n/say old")
-- blank name, no text (profile import): inert, never the first macro
s = { kind = "macro", name = " " }
check("blank name, no text: nothing", (T.Action(s)), nil)
-- unique name, edited text: found by name, text refreshed
s = { kind = "macro", name = "Bloodlust", body = "/cast Heroism" }
k, v = T.Action(s)
check("unique name, edited text: by name", v, 125)
check("  text refreshed", s.body, "/cast Bloodlust")
-- renamed macro, unique text: found by text, name refreshed
s = { kind = "macro", name = "BL old", body = "/cast Bloodlust" }
k, v = T.Action(s)
check("renamed: by text", v, 125)
check("  name refreshed", s.name, "Bloodlust")
-- shared name "Heal": exact text picks the right one
s = { kind = "macro", name = "Heal", body = "/cast Lesser Healing Wave" }
k, v = T.Action(s)
check("shared name, exact text: the character one", v, 126)
-- shared name, unknown text: no guess
s = { kind = "macro", name = "Heal", body = "/cast Chain Heal" }
k, v, attr = T.Action(s)
check("shared name, unknown text: macrotext", attr, "macrotext")
-- shared name, no text: inert
check("shared name, no text: nothing", (T.Action({ kind = "macro", name = "Heal" })), nil)
-- macros not loaded yet: runs saved text
local saved = macros; macros = {}
k, v, attr = T.Action({ kind = "macro", name = " ", body = "/cast Windfury Weapon" })
check("not loaded: macrotext", attr, "macrotext")
macros = saved
-- The reminder for slices the old code set to macro 1
db.profile.pie.rings[1] = { name = "Totems", slices = {
  { kind = "macro", name = " ", body = "/say first" }, { kind = "macro", name = " ", body = "/say first" },
  { kind = "spell", id = 1, name = "x" } } }
db.profile.pie.rings[2] = { slices = { { kind = "macro", name = " ", body = "/say first" },
  { kind = "macro", name = "Bloodlust", body = "/cast Bloodlust" } } }
local lines = SanctuaryUI.Pie.LatchedLines(SanctuaryUI.Pie.Latched())
check("one reminder line", #lines, 1)
local want = "An old bug set 3 pie slices (Totems, Ring 2) to the same unnamed macro. Drag the right ones back on with /sanctuary pie Totems"
check("reminder text", lines[1], want)
check("  with the prefix, about 140 chars", #("SanctuaryUI: " .. lines[1]) <= 145, true)
check("options note says they can't be restored", (SanctuaryUI.Pie.LatchedNote() or ""):find("can't be restored", 1, true) ~= nil, true)
-- a shared, named macro reads as macro "Heal"
macros[3] = { "Heal", "/cast Healing Wave" } -- not first: 2 is
db.profile.pie.rings[3] = { slices = { { kind = "macro", name = "Heal", body = "/cast Healing Wave" },
  { kind = "macro", name = "Heal", body = "/cast Healing Wave" } } }
lines = SanctuaryUI.Pie.LatchedLines(SanctuaryUI.Pie.Latched())
check("named group", lines[2], 'An old bug set 2 pie slices (Ring 3) to the same macro "Heal". Drag the right ones back on with /sanctuary pie 3')
macros[3] = nil
db.profile.pie.rings[3] = nil
-- shown a few seconds after the macros load, once a session, not if dismissed
local timers = {}
C_Timer = { After = function(t, fn) timers[#timers + 1] = { t, fn } end }
T.Schedule()
check("one timer", #timers, 1)
check("  about 5 s", timers[1][1], 5)
check("  nothing printed yet", #printed, 0)
timers[1][2]()
check("printed when it fires", #printed, 1)
T.Schedule()
check("once a session", #timers, 1)
printed = {}
T.ResetSession()
SanctuaryUI.Pie.DismissLatched()
printed = {}
T.Schedule()
check("dismissed: no timer", #timers, 1)
db.char = {}
T.ResetSession()
-- fixed rings: nothing to say
db.profile.pie.rings = { { slices = { { kind = "macro", name = " ", body = "/cast Windfury Weapon" },
  { kind = "macro", name = " ", body = "/cast Fire Resistance Totem" } } } }
check("healthy rings: nothing latched", #SanctuaryUI.Pie.Latched(), 0)
check("healthy rings: no options note", SanctuaryUI.Pie.LatchedNote(), nil)
-- macros not loaded: no timer, wait for the next UPDATE_MACROS
saved = macros; macros = {}
T.Schedule()
check("not loaded: no timer", #timers, 1)
macros = saved
-- /sanctuary pie <ring>
db.profile.pie.rings = { { name = "Totems", slices = {} }, { slices = {} } }
check("ring by number", SanctuaryUI.Pie.FindRing("2"), 2)
check("ring by name, any case", SanctuaryUI.Pie.FindRing("totems"), 1)
check("ring by quoted name", SanctuaryUI.Pie.FindRing('"Totems"'), 1)
check("Ring 2 without quotes", SanctuaryUI.Pie.FindRing("Ring 2"), 2)
check("unknown ring", SanctuaryUI.Pie.FindRing("nope"), nil)
check("command arg: name", SanctuaryUI.Pie.RingArg(1), "Totems")
check("command arg: number when unnamed", SanctuaryUI.Pie.RingArg(2), "2")
db.profile.pie.rings[2].name = "1"
check("command arg: number when the name finds another ring", SanctuaryUI.Pie.RingArg(2), "2")
db.profile.pie.rings[2].name = nil
-- a dead slice: shown Empty, and says so in red when picked, throttled
db.profile.pie.rings[1].slices = { { kind = "macro", name = " " } }
check("dead slice is labelled Empty", SanctuaryUI.Pie.Describe(1), "Empty")
local errors = {}
UIErrorsFrame = { AddMessage = function(_, text, r, g, b) errors[#errors + 1] = { text, r, g, b } end }
local now = 100
GetTime = function() return now end
T.SetDead({ [1] = { [1] = true } })
T.SetLive({ hover = 1 })
local button = { GetAttribute = function(_, k) if k == "pieRing" then return 1 end end }
T.DeadPicked(button, "LeftButton", true)
check("not on key down", #errors, 0)
T.DeadPicked(button, "LeftButton", false)
check("red message on release", errors[1] and errors[1][1], "Slice has no macro: /sanctuary pie Totems")
check("  red", errors[1] and errors[1][2] == 1 and errors[1][3] < 0.2, true)
now = 105; T.DeadPicked(button, "LeftButton", false)
check("throttled within 10 s", #errors, 1)
now = 111; T.DeadPicked(button, "LeftButton", false)
check("again after 10 s", #errors, 2)
T.SetLive({ hover = nil })
now = 200; T.DeadPicked(button, "LeftButton", false)
check("released in the middle: nothing", #errors, 2)
T.SetLive({ hover = 1 }); T.SetDead({})
now = 300; T.DeadPicked(button, "LeftButton", false)
check("live slice: nothing", #errors, 2)
print("FAILS " .. fails)
os.exit(fails == 0 and 0 or 1)
