"""Offline preview of the What's new timeline (WhatsNew.lua): the real Lua in lupa against wow.lua,
drawn with render.py's layout and drawing. Shots: the releases missed since 0.24.2 (login), a
first look (nothing seen), and the whole timeline (/sanctuary news, drawn unclipped).

Run: PYTHONPATH=~/.cache/sanctuary-preview-py ~/.venv/bin/python tools/ui_preview/news_preview.py [out_dir]
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "shots")
sys.argv = [sys.argv[0], OUT]
src = open(os.path.join(HERE, "render.py")).read()
exec(compile(src[:src.index("def errors():")], "render.py", "exec"))
os.makedirs(OUT, exist_ok=True)


def string_height(fs):
    size = (T(fs, "size") or 12)
    f = font(T(fs, "font") or "body", size * 4)
    w = (T(fs, "w") or 0) * 4
    text = strip(str(T(fs, "text") or ""))
    lines, cur = 1, ""
    if w > 0:
        for wd in text.split(" "):
            trial = (cur + " " + wd).strip()
            if f.getlength(trial) > w and cur:
                lines, cur = lines + 1, wd
            else:
                cur = trial
    return lines * size * 1.15 + (lines - 1) * (T(fs, "spacing") or 0)


lua.globals().STRING_HEIGHT = string_height
lua.execute('''
local ns = SanctuaryUI
local W = getmetatable(UIParent).__index
local proto = getmetatable(UIParent)
local old = proto.__index
proto.__index = function(t, k)
	if k == "GetStringHeight" then return function(self) return STRING_HEIGHT(self) end end
	if k == "SetSpacing" then return function(self, s) self.spacing = s end end
	if k == "SetScrollChild" then return function(self, c) self.child = c; c.points = { { "TOPLEFT", self, "TOPLEFT", 0, 0 } } end end
	if k == "GetVerticalScroll" then return function() return 0 end end
	return old(t, k)
end
ns.Fonts = ns.Fonts or {}
ns.Fonts.Path = function(role) return role end
PROFILE.news = { enabled = true, scale = 1 }
ns.db.global = {}
ns.Art.D3Scale = function(s) return 1 end
''')
load(SRC + "/WhatsNew.lua")
lua.execute('''
local ns = SanctuaryUI
function ns.Options.Open() end
''') if False else None


def shot(name, setup):
    lua.execute('''
    local w = _G.SanctuaryUIWhatsNew
    if w then w:Hide() end
    ''')
    lua.execute(setup)
    draw(os.path.join(OUT, name), "SanctuaryUIWhatsNew", K=1.6)
    print("wrote", name)


shot("news-missed.png", 'SanctuaryUI.db.global.newsSeen = SanctuaryUI.WhatsNew.RELEASES[4].version; assert(SanctuaryUI.WhatsNew.Show("missed"))')
shot("news-one.png", 'assert(SanctuaryUI.WhatsNew.Show(SanctuaryUI.WhatsNew.RELEASES[1].version))')
shot("news-timeline.png", 'assert(SanctuaryUI.WhatsNew.Show())')
lua.execute('''
local ns = SanctuaryUI
local R = ns.WhatsNew.RELEASES
local newest, second, third = R[1].version, R[2].version, R[3].version
ns.db.global.newsSeen = nil
_G.SanctuaryUIWhatsNew:Hide()
assert(ns.db.global.newsSeen == newest, "closing marks the newest shown as seen: " .. tostring(ns.db.global.newsSeen))
ns.db.global.newsSeen = second
assert(ns.WhatsNew.Show(third))
_G.SanctuaryUIWhatsNew:Hide()
assert(ns.db.global.newsSeen == second, "viewing an older release doesn't move seen back")
-- After an update the whole timeline shows, with only the unseen releases marked NEW.
ns.db.global.newsSeen = second
assert(ns.WhatsNew.Show("missed"))
local news, versions = 0, 0
for _, w in ipairs(ALL) do
	if w.kind == "FontString" and w.shown then
		if w.text == "NEW" then news = news + 1 end
		for _, r in ipairs(R) do if w.text == r.version then versions = versions + 1 end end
	end
end
assert(news == 1, "one release marked NEW, got " .. news)
local want = math.min(#R, ns.WhatsNew.KEEP)
assert(versions == want, "the last " .. want .. " releases show (" .. versions .. ")")
_G.SanctuaryUIWhatsNew:Hide()
''')
print("flow ok")
