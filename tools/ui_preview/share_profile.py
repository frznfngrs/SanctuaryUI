import lupa.lua51 as lupa
REPO = '/home/codym/wow3dui'; SRC = REPO + '/SanctuaryUI'
lua = lupa.LuaRuntime(unpack_returned_tuples=True)
def load(p): lua.execute(f'local f = assert(loadfile("{p}")) f("SanctuaryUI", {{}})')
load(REPO + '/tools/ui_preview/wow.lua')
lua.execute(r'''
function GetRealmName() return "Realm" end
function UnitName() return "Tester" end
function UnitNameUnmodified() return "Tester" end
function UnitClass() return "Paladin", "PALADIN" end
function UnitRace() return "Human", "Human" end
function UnitFactionGroup() return "Alliance" end
function GetCurrentRegion() return 1 end
strlenutf8 = string.len
function GetCurrentRegionName() return "US" end
function GetLocale() return "enUS" end
function geterrorhandler() return function(e) print("ERR " .. tostring(e)) end end
function securecallfunction(f, ...) return f(...) end
function secureexecuterange(t, f, ...) for k, v in pairs(t) do f(k, v, ...) end end
strmatch, strsub, strbyte, strchar, format, tconcat = string.match, string.sub, string.byte, string.char, string.format, table.concat
strfind, gsub, strlen, strrep = string.find, string.gsub, string.len, string.rep
function strsplit(d, s) local out = {} for p in (s .. d):gmatch("(.-)" .. d:gsub("%p", "%%%0")) do out[#out + 1] = p end return unpack(out) end
select = select
POPUPS = {}
StaticPopupDialogs = {}
function StaticPopup_Show(k) POPUPS[#POPUPS + 1] = k end
function ReloadUI() end
''')
for f in ['libs/LibStub/LibStub.lua', 'libs/CallbackHandler-1.0/CallbackHandler-1.0.lua', 'libs/AceDB-3.0/AceDB-3.0.lua',
          'libs/AceSerializer-3.0/AceSerializer-3.0.lua', 'libs/LibDeflate/LibDeflate.lua']:
    lua.execute(f'assert(loadfile("{SRC}/{f}"))()')
load(SRC + '/Settings.lua')
load(SRC + '/Share.lua')
lua.execute(r'''
local ns = SanctuaryUI
ns.Migrate = ns.Migrate or function() end
REFRESHES = 0
ns.Refresh = function() REFRESHES = REFRESHES + 1 end
ns.Log = function() end
SanctuaryUIDB = nil
ns.InitDB()
local FAILS = 0
local function ok(c, m) if not c then FAILS = FAILS + 1 print("FAIL " .. m) else print("ok   " .. m) end end
local p = ns.db.profile
-- change some settings, touch some tables without changing them
p.castTextSize = 14
p.railMode = "rep"
p.rows[3].enabled = true
local _ = p.target.scale -- read only
p.party.style = "slab"
p.pie.rings[1] = { name = "Totems", slices = { { kind = "macro", id = 3, name = "WF", body = "/run DoEvil()" }, { kind = "spell", id = 8071, name = "Stoneskin" } } }
local text, n = ns.Share.Export()
ok(text and text:sub(1, 6) == "!SUI1!", "export string " .. (text and #text or 0) .. " chars, " .. tostring(n) .. " settings")
ok(n and n < 40, "only changed settings exported (" .. tostring(n) .. ")")
local info, err = ns.Share.Decode(text)
local function dump(t, pre) for k, v in pairs(t) do if type(v) == "table" then dump(v, pre .. tostring(k) .. ".") else print("  " .. pre .. tostring(k) .. " = " .. tostring(v)) end end end

ok(info ~= nil, "decodes " .. tostring(err))
ok(info.name == "Default" and info.class == "PALADIN", "name/class " .. tostring(info.name))
ok(info.profile.castTextSize == 14 and info.profile.railMode == "rep" and info.profile.rows[3].enabled == true, "values round-trip")
ok(info.profile.target.scale == nil and info.profile.rows[4] == nil, "untouched settings left out")
ok(info.macros == 1 and info.profile.pie.rings[1].slices[1].body == nil and info.profile.pie.rings[1].slices[1].name == "WF", "macro text dropped, name kept")
-- bad strings
ok(ns.Share.Decode("hello") == nil, "rejects non-profile")
ok(ns.Share.Decode(text:sub(1, #text - 20)) == nil, "rejects cut string")
ok(ns.Share.Decode("   \n" .. text .. " \n") ~= nil, "whitespace around is fine")
-- import as new
local name = ns.Share.FreeName(info.name)
ok(name == "Default (imported)", "free name " .. name)
-- reset current first so we can tell the import came in
ns.db:ResetProfile(false, true)
ok(ns.db.profile.castTextSize == 11, "current reset")
local done, why = ns.Share.Import(info, "new", name)
ok(done, "import new " .. tostring(why))
ok(ns.db:GetCurrentProfile() == name and ns.db.profile.castTextSize == 14 and ns.db.profile.party.style == "slab" and ns.db.profile.rows[3].enabled, "new profile has the settings")
ok(ns.db.profile.target.scale ~= nil, "defaults still fill the rest")
ok(POPUPS[#POPUPS] == "SANCTUARYUI_IMPORT_RELOAD", "reload offered")
ok(ns.Share.FreeName(info.name) == "Default (imported 2)", "next free name")
local again = ns.Share.Import(info, "new", name)
ok(not again, "refuses an existing name")
-- replace
ns.db:SetProfile("Other")
ns.db.profile.railMode = "xp"
ns.db.profile.levelPlaque = false
ok(ns.Share.Import(info, "replace"), "replace current")
ok(ns.db:GetCurrentProfile() == "Other" and ns.db.profile.railMode == "rep" and ns.db.profile.levelPlaque == true, "replace resets then applies")
-- hostile shapes
local ser = LibStub("AceSerializer-3.0"); local d = LibStub("LibDeflate")
local evil = { v = 1, name = "x", profile = { castTextSize = "huge", rows = 5, target = { scale = {} }, unknownKey = 3, [true] = 1 } }
local s = "!SUI1!" .. d:EncodeForPrint(d:CompressDeflate(ser:Serialize(evil)))
local ei = ns.Share.Decode(s)
ok(ei and ei.profile.castTextSize == nil and ei.profile.rows == nil and ei.profile.target.scale == nil and ei.profile.unknownKey == 3, "wrong types dropped (" .. (ei and ei.dropped or -1) .. ")")
print("FAILS " .. FAILS)
''')
for l in lua.globals().PRINTED.values(): print(l)
