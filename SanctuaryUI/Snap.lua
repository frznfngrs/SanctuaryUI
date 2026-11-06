SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.Snap = ns.Snap or {}

-- Snapping while frames are unlocked, the way Bartender4 does it (General > Bar snapping): a
-- dragged frame catches on the edges and centres of every other mover, the console and the
-- screen when it comes within RANGE of one. It lines up with a frame beside it (left, right
-- or centre) and sits flush against it on any side. Hold Shift while dragging to place freely.
--
-- With General > Show grid on, an Edit Mode style grid is drawn while frames are unlocked: lines
-- every gridSize units out from the screen's centre, the centre lines brighter. Frames snap their
-- edges and centre to its lines as well.
--
-- Unlike Bartender's first-match LibSimpleSticky, each axis takes the closest catch among all
-- frames, so a bar dropped into a corner between two others settles against both.

local RANGE = 15 -- UIParent units

-- Everything a frame can snap to: { owner = the frame it positions, box = fn -> l, b, r, t in
-- screen pixels, or nil while hidden }.
local targets = {}

function ns.Snap.Register(owner, box)
	targets[#targets + 1] = { owner = owner, box = box }
end

-- A frame's rect in screen pixels, or nil while it is hidden or not laid out.
function ns.Snap.Rect(frame)
	if not frame or not frame:IsVisible() then return end
	local l, b, w, h = frame:GetRect()
	if not l then return end
	local s = frame:GetEffectiveScale()
	return l * s, b * s, (l + w) * s, (b + h) * s
end

-- Register a mover: it snaps others to its own box (the bar it stands for).
function ns.Snap.RegisterMover(mover, owner)
	ns.Snap.Register(owner, function() return ns.Snap.Rect(mover) end)
end

function ns.Snap.Enabled()
	return ns.DB().snapping ~= false
end

ns.Snap.GRID_MIN, ns.Snap.GRID_MAX = 10, 200

-- Grid spacing in UIParent units.
function ns.Snap.GridSize()
	local size = tonumber(ns.DB().gridSize) or 40
	return math.max(ns.Snap.GRID_MIN, math.min(ns.Snap.GRID_MAX, size))
end

-- The grid is drawn (and snapped to) only while frames are unlocked.
function ns.Snap.GridShown()
	local db = ns.DB()
	return db.grid and not db.locked and not InCombatLockdown() and true or false
end

-- Whether frame's position follows moving (it is anchored to it, directly or down a chain):
-- such frames ride along with the drag, so snapping to them would chase itself.
local function Follows(frame, moving)
	for _ = 1, 8 do
		if not frame then return false end
		if frame == moving then return true end
		local _, rel = frame:GetPoint(1)
		if rel == frame then return false end
		frame = rel
	end
	return false
end

-- The offset (dx, dy, in pixels) that snaps box A, or 0 on an axis that catches on nothing.
local function Catch(moving, l, b, r, t)
	local range = RANGE * UIParent:GetEffectiveScale()
	local cx, cy = (l + r) / 2, (b + t) / 2
	local bestX, bestY = range, range
	local dx, dy = 0, 0
	local function TryX(d)
		if math.abs(d) < bestX then bestX, dx = math.abs(d), d end
	end
	local function TryY(d)
		if math.abs(d) < bestY then bestY, dy = math.abs(d), d end
	end
	local function Against(L, B, R, T, screen)
		local X, Y = (L + R) / 2, (B + T) / 2
		-- Side by side (within reach vertically): line up across.
		if b <= T + range and B <= t + range then
			TryX(X - cx)
			TryX(L - l)
			TryX(R - r)
			if not screen then
				TryX(R - l) -- A right of B
				TryX(L - r) -- A left of B
			end
		end
		-- One above the other (within reach across): line up vertically.
		if l <= R + range and L <= r + range then
			TryY(Y - cy)
			TryY(B - b)
			TryY(T - t)
			if not screen then
				TryY(T - b) -- A on top of B
				TryY(B - t) -- A under B
			end
		end
	end
	local s = UIParent:GetEffectiveScale()
	local W, H = UIParent:GetWidth() * s, UIParent:GetHeight() * s
	Against(0, 0, W, H, true)
	-- Grid lines, counted out from the screen's centre: the nearest line to each edge and centre.
	if ns.Snap.GridShown() then
		local g = ns.Snap.GridSize() * s
		local function Line(v, mid)
			return mid + math.floor((v - mid) / g + 0.5) * g - v
		end
		TryX(Line(l, W / 2))
		TryX(Line(r, W / 2))
		TryX(Line(cx, W / 2))
		TryY(Line(b, H / 2))
		TryY(Line(t, H / 2))
		TryY(Line(cy, H / 2))
	end
	for i = 1, #targets do
		local target = targets[i]
		if target.owner ~= moving and not Follows(target.owner, moving) then
			local L, B, R, T = target.box()
			if L then
				Against(L, B, R, T)
			end
		end
	end
	return dx, dy, bestX < range or bestY < range
end

local driver = CreateFrame("Frame")
local drag

local function Finish()
	if not drag then return end
	local d = drag
	drag = nil
	driver:SetScript("OnUpdate", nil)
	if d.highlight then d.highlight(false) end
	if d.onStop then d.onStop() end
end

-- Drag frame with the cursor, snapping box (fn -> l, b, r, t in pixels at the frame's current
-- spot). frame ends up anchored CENTER to UIParent's BOTTOMLEFT. onStop runs on release, and
-- highlight(snapped) tells the mover when it has caught on something.
function ns.Snap.StartDrag(frame, box, onStop, highlight)
	Finish()
	if InCombatLockdown() then return end
	local s = frame:GetEffectiveScale()
	local fx, fy = frame:GetCenter()
	local x0, y0 = GetCursorPosition()
	if not fx then return end
	-- The box relative to the frame's centre, in pixels; fixed for the drag.
	local l, b, r, t = box()
	if not l then
		l, b, r, t = ns.Snap.Rect(frame)
	end
	local ox, oy = fx - x0 / s, fy - y0 / s
	local bl, bb, br, bt = l - fx * s, b - fy * s, r - fx * s, t - fy * s
	drag = { frame = frame, onStop = onStop, highlight = highlight }
	driver:SetScript("OnUpdate", function()
		-- A missed OnDragStop (mover hidden mid-drag) or combat ends the drag.
		if InCombatLockdown() or not IsMouseButtonDown("LeftButton") then
			Finish()
			return
		end
		local cx, cy = GetCursorPosition()
		local x, y = cx / s + ox, cy / s + oy
		local snapped = false
		if ns.Snap.Enabled() and not IsShiftKeyDown() then
			local px, py = x * s, y * s
			local dx, dy
			dx, dy, snapped = Catch(frame, px + bl, py + bb, px + br, py + bt)
			x, y = x + dx / s, y + dy / s
		end
		frame:ClearAllPoints()
		frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
		if highlight then highlight(snapped) end
	end)
end

-- Release: the mover's OnDragStop.
function ns.Snap.StopDrag()
	Finish()
end

function ns.Snap.Dragging(frame)
	return drag ~= nil and (frame == nil or drag.frame == frame)
end

---------------------------------------------------------------------------
-- The grid overlay: one-pixel lines over the world, under every frame.

local grid
local lines = {}

local function GridFrame()
	if grid then return grid end
	grid = CreateFrame("Frame", "SanctuaryUIGrid", UIParent)
	grid:SetAllPoints(UIParent)
	grid:SetFrameStrata("BACKGROUND")
	grid:SetFrameLevel(0)
	grid:EnableMouse(false)
	grid:Hide()
	grid:RegisterEvent("UI_SCALE_CHANGED")
	grid:RegisterEvent("DISPLAY_SIZE_CHANGED")
	grid:RegisterEvent("PLAYER_REGEN_DISABLED")
	grid:RegisterEvent("PLAYER_REGEN_ENABLED")
	grid:SetScript("OnEvent", function(self, event)
		if event == "PLAYER_REGEN_DISABLED" then
			self:Hide()
		elseif event == "PLAYER_REGEN_ENABLED" then
			ns.Snap.UpdateGrid()
		elseif self:IsShown() then
			ns.Snap.DrawGrid()
		end
	end)
	return grid
end

-- One screen pixel, in UIParent units.
local function Pixel()
	local _, physical = GetPhysicalScreenSize()
	local s = UIParent:GetEffectiveScale()
	if not physical or physical <= 0 or not s or s <= 0 then return 1 end
	return 768 / physical / s
end

function ns.Snap.DrawGrid()
	local frame = GridFrame()
	local W, H = UIParent:GetWidth(), UIParent:GetHeight()
	local g, px = ns.Snap.GridSize(), Pixel()
	local used = 0
	local function Draw(vertical, at, centre)
		used = used + 1
		local line = lines[used]
		if not line then
			line = frame:CreateTexture(nil, "BACKGROUND")
			lines[used] = line
		end
		if centre then
			line:SetColorTexture(0.95, 0.78, 0.42, 0.75) -- D3 gold for the centre lines
		else
			line:SetColorTexture(0.86, 0.72, 0.42, 0.22)
		end
		line:ClearAllPoints()
		if vertical then
			line:SetSize(px * (centre and 2 or 1), H)
			line:SetPoint("CENTER", frame, "BOTTOMLEFT", at, H / 2)
		else
			line:SetSize(W, px * (centre and 2 or 1))
			line:SetPoint("CENTER", frame, "BOTTOMLEFT", W / 2, at)
		end
		line:Show()
	end
	for k = 0, math.floor(W / 2 / g) do
		Draw(true, W / 2 + k * g, k == 0)
		if k > 0 then Draw(true, W / 2 - k * g) end
	end
	for k = 0, math.floor(H / 2 / g) do
		Draw(false, H / 2 + k * g, k == 0)
		if k > 0 then Draw(false, H / 2 - k * g) end
	end
	for i = used + 1, #lines do
		lines[i]:Hide()
	end
	frame.drawn = g .. "x" .. W .. "x" .. H
end

-- Show or hide the grid to match the settings; redraw it when its spacing changed.
function ns.Snap.UpdateGrid()
	local shown = ns.Snap.GridShown()
	if not shown and not grid then return end
	local frame = GridFrame()
	if shown then
		local key = ns.Snap.GridSize() .. "x" .. UIParent:GetWidth() .. "x" .. UIParent:GetHeight()
		if frame.drawn ~= key then ns.Snap.DrawGrid() end
	end
	frame:SetShown(shown)
end
