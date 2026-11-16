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
src = src .. "\nns.Pie._t = { FindMacro = FindMacro, Action = Action }\n"
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
-- the notice for slices the old code latched onto macro 1
db.profile.pie.rings[1] = { name = "Totems", slices = {
  { kind = "macro", name = " ", body = "/say first" }, { kind = "macro", name = " ", body = "/say first" },
  { kind = "spell", id = 1, name = "x" } } }
db.profile.pie.rings[2] = { slices = { { kind = "macro", name = " ", body = "/say first" },
  { kind = "macro", name = "Bloodlust", body = "/cast Bloodlust" } } }
SanctuaryUI.Pie.CheckLatched()
check("latched notice printed once", #printed, 1)
print(printed[1])
SanctuaryUI.Pie.CheckLatched()
check("not again", #printed, 1)
-- nothing latched: no notice
db.char = {}; printed = {}
db.profile.pie.rings = { { slices = { { kind = "macro", name = " ", body = "/cast Windfury Weapon" },
  { kind = "macro", name = " ", body = "/cast Fire Resistance Totem" } } } }
SanctuaryUI.Pie.CheckLatched()
check("healthy rings: no notice", #printed, 0)
print("FAILS " .. fails)
os.exit(fails == 0 and 0 or 1)
