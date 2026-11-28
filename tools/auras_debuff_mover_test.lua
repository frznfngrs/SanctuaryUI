-- Run from the repo root: lua5.1 tools/auras_debuff_mover_test.lua [SanctuaryUI/Auras.lua]
-- Offline check for #49: the debuffs' mover in Auras.lua against stand-in frames. Blizzard's
-- DebuffFrame must not be touched until the mover is used, nothing moves in combat, and a
-- reset puts back the anchor Edit Mode set.
SanctuaryUI = {}
local ns = SanctuaryUI
local combat = false
function InCombatLockdown() return combat end
function issecretvalue() return false end
function hooksecurefunc(t, name, fn)
	local orig = t[name]
	t[name] = function(...) local r = orig(...); fn(...); return r end
end
local frames = {}
local function NewFrame(name, parent)
	local f = { name = name, parent = parent, points = {}, w = 0, h = 0, scripts = {}, hooks = {}, calls = 0, shown = true }
	function f:ClearAllPoints() self.points = {}; self.calls = self.calls + 1 end
	function f:SetPoint(p, rel, rp, x, y) self.points[#self.points + 1] = { p, rel, rp, x, y }; self.calls = self.calls + 1 end
	function f:GetNumPoints() return #self.points end
	function f:GetPoint(i) local p = self.points[i]; return p[1], p[2], p[3], p[4], p[5] end
	function f:SetSize(w, h) self.w, self.h = w, h end
	function f:GetSize() return self.w, self.h end
	function f:GetEffectiveScale() return 1 end
	function f:GetCenter() return self.cx or 500, self.cy or 400 end
	function f:GetLeft() return 100 end
	function f:GetTop() return 700 end
	function f:EnableMouse() end
	function f:SetScript(k, fn) self.scripts[k] = fn end
	function f:HookScript(k, fn) self.hooks[k] = fn end
	function f:RegisterEvent() end
	function f:RegisterUnitEvent() end
	function f:SetShown(s) self.shown = s end
	function f:IsVisible() return self.shown end
	frames[#frames + 1] = f
	return f
end
function CreateFrame(_, name, parent) return NewFrame(name, parent) end
UIParent = NewFrame("UIParent")
MinimapCluster = NewFrame("MinimapCluster")
BuffFrame = NewFrame("BuffFrame")
DebuffFrame = NewFrame("DebuffFrame")
DebuffFrame.w, DebuffFrame.h = 200, 40
-- Edit Mode's anchor and the methods the hooks wrap.
DebuffFrame:SetPoint("TOPRIGHT", BuffFrame, "BOTTOMRIGHT", 0, -10)
DebuffFrame.calls = 0
function DebuffFrame:ApplySystemAnchor()
	self:ClearAllPoints()
	self:SetPoint("TOPRIGHT", MinimapCluster, "TOPLEFT", -20, -60)
end
function DebuffFrame:OnDragStart() end
function DebuffFrame:OnDragStop() self:ClearAllPoints(); self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", 300, 300) end
DebuffFrame.auraFrames = {}

local db = { auras = { enabled = true, duration = true, bars = true, debuffPos = { moved = false, mx = 0, my = 0 } } }
ns.DB = function() return db end
local printed = {}
ns.Print = function(m) printed[#printed + 1] = m end
local refreshes = 0
ns.Refresh = function() refreshes = refreshes + 1; ns.Auras.ApplySettings() end
ns.MovedPoint = function(_, opt) return opt.mx, opt.my end
local mover
ns.MakeMover = function(anchor, label, opt)
	mover = NewFrame("mover", anchor); mover.label = label; mover.opt = opt
	return mover
end
ns.Art = { Apply = function() return false end, SOCKET_INSET = { left = 0, right = 0, top = 0, bottom = 0 }, Path = function() end }

local f = assert(io.open(arg[1] or "SanctuaryUI/Auras.lua")); local src = f:read("*a"); f:close()
assert(loadstring(src, "Auras.lua"))()

local fails = 0
local function check(label, got, want)
	local ok = got == want
	if not ok then fails = fails + 1 end
	print(("%s %s  got %s want %s"):format(ok and "ok  " or "FAIL", label, tostring(got), tostring(want)))
end

ns.Auras.Init()
local holder = mover.parent
check("mover made, labelled Debuffs", mover.label, "Debuffs")
check("default: DebuffFrame never touched", DebuffFrame.calls, 0)
check("default: still Edit Mode's anchor", select(2, DebuffFrame:GetPoint(1)), BuffFrame)
check("default: holder sits over the debuffs", select(2, holder:GetPoint(1)), DebuffFrame)
ns.Refresh()
check("default refresh: still untouched", DebuffFrame.calls, 0)

-- Edit Mode re-applies its anchor while we hold nothing: we stay out of it.
DebuffFrame:ApplySystemAnchor()
local editCalls = DebuffFrame.calls
check("edit mode anchor, not moved: only Blizzard's two calls", editCalls, 2)

-- Unlock and drag: the debuffs ride on the holder, then the drop is saved.
mover.hooks.OnShow()
mover.hooks.OnDragStart()
check("picked up: hangs on holder", select(2, DebuffFrame:GetPoint(1)), holder)
check("by Edit Mode's corner", DebuffFrame:GetPoint(1), "TOPRIGHT")
check("holder no longer hangs on DebuffFrame", select(2, holder:GetPoint(1)), UIParent)
local o = db.auras.debuffPos
o.moved, o.mx, o.my = true, 640, 360 -- what the mover's Record saves
ns.Refresh()
check("dropped: holder at the saved place", holder.points[1][4], 640)
check("dropped: DebuffFrame on holder", select(2, DebuffFrame:GetPoint(1)), holder)
check("box size kept", o.w ~= nil and o.h ~= nil, true)

-- Edit Mode re-anchors (layout change): we put it back on the holder.
DebuffFrame:ApplySystemAnchor()
check("edit mode re-anchor: back on holder", select(2, DebuffFrame:GetPoint(1)), holder)

-- In combat nothing moves; it waits for the end of combat.
combat = true
DebuffFrame:ApplySystemAnchor()
local before = DebuffFrame.calls
check("combat: left on Edit Mode's anchor", select(2, DebuffFrame:GetPoint(1)), MinimapCluster)
ns.Auras.PlaceDebuffs()
check("combat: no calls on DebuffFrame", DebuffFrame.calls, before)
combat = false
ns.Auras.frame.scripts.OnEvent(ns.Auras.frame, "PLAYER_REGEN_ENABLED")
check("combat over: back on holder", select(2, DebuffFrame:GetPoint(1)), holder)

-- Reset: Edit Mode's last anchor comes back.
ns.Auras.ResetDebuffPosition()
check("reset: moved cleared", o.moved, false)
check("reset: Edit Mode's anchor back", select(2, DebuffFrame:GetPoint(1)), MinimapCluster)
check("reset: Edit Mode's offset back", select(4, DebuffFrame:GetPoint(1)), -20)
check("reset: holder over the debuffs again", select(2, holder:GetPoint(1)), DebuffFrame)

-- Turned off: Blizzard's place back, saved place kept.
o.moved, o.mx, o.my = true, 640, 360
ns.Refresh()
db.auras.enabled = false
ns.Refresh()
check("disabled: Edit Mode's anchor back", select(2, DebuffFrame:GetPoint(1)), MinimapCluster)
check("disabled: saved place kept", o.moved, true)
db.auras.enabled = true
ns.Refresh()

-- Dragged in Edit Mode: Edit Mode has it again.
DebuffFrame:OnDragStart()
DebuffFrame:OnDragStop()
check("edit mode drag: moved cleared", o.moved, false)
check("edit mode drag: frame where Edit Mode dropped it", select(2, DebuffFrame:GetPoint(1)), UIParent)
check("edit mode drag: told in chat", #printed > 0, true)
ns.Refresh()
check("then refresh: left alone", select(2, DebuffFrame:GetPoint(1)), UIParent)

print(fails == 0 and "all passed" or ("FAILS " .. fails))
os.exit(fails == 0 and 0 or 1)
