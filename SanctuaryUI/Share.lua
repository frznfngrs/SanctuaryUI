SanctuaryUI = SanctuaryUI or {}
local ns = SanctuaryUI
ns.Share = ns.Share or {}
local S = ns.Share

-- Profile import and export (Options > Setup > Import / Export): the current profile as one line
-- of text to paste to a friend or another account, and back. The string is "!SUI1!" and then
-- the profile, AceSerializer'd, deflated and printable-encoded by LibDeflate, as ElvUI and
-- WeakAuras share theirs.
--
-- Only settings that differ from the defaults go in. Character data (meter history, fishing and
-- cooking notes, trinket queues) and the game's own keybindings stay behind. A string comes from
-- someone else, so on the way in it is only ever data: a value of the wrong type for its setting
-- is dropped, a table where the defaults have a value (or the reverse) is dropped, and pie menu
-- macros lose their stored text (they match one of your macros by name instead), so nothing
-- pasted can run as a macro.

local PREFIX = "!SUI1!"
local MAX_LEN = 2 * 1024 * 1024

local function Libs()
	local ser = LibStub and LibStub("AceSerializer-3.0", true)
	local deflate = LibStub and LibStub("LibDeflate", true)
	return ser, deflate
end

local function Copy(v)
	if type(v) ~= "table" then return v end
	local out = {}
	for k, x in pairs(v) do out[k] = Copy(x) end
	return out
end

-- The default for key k in an AceDB defaults table: its own, else the "*"/"**" catch-all.
-- inherit: the parent's "**", which AceDB also lays under keys it names (rows[3] gets every
-- "**" row setting it doesn't set itself).
local function DefaultOf(defaults, k, inherit)
	local d
	if type(defaults) == "table" then d = defaults[k] end -- (not `and/or`: a false default would turn into nil)
	if d == nil and type(inherit) == "table" then d = inherit[k] end
	if d == nil and type(defaults) == "table" then
		d = defaults["**"]
		if d == nil then d = defaults["*"] end
	end
	return d
end

-- What a named table key inherits from its parent's "**".
local function InheritOf(defaults, k)
	if type(defaults) == "table" and defaults[k] ~= nil and type(defaults["**"]) == "table" then
		return defaults["**"]
	end
end

-- Drop what equals its default, and tables left empty. Errs on keeping: a value kept that is
-- also the default does no harm.
local function Strip(t, defaults, inherit)
	for k, v in pairs(t) do
		local d = DefaultOf(defaults, k, inherit)
		if type(v) == "table" then
			if type(d) == "table" then
				Strip(v, d, InheritOf(defaults, k))
				if next(v) == nil then t[k] = nil end
			end
		elseif v == d then
			t[k] = nil
		end
	end
end

-- How many settings a table holds (its leaves).
local function Count(t)
	local n = 0
	for _, v in pairs(t) do
		n = n + (type(v) == "table" and Count(v) or 1)
	end
	return n
end

local function Version()
	local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
	return getMeta and getMeta("SanctuaryUI", "Version") or "?"
end

function S.Export()
	local ser, deflate = Libs()
	if not ser or not deflate then return nil, "The export libraries didn't load (restart the game after updating)." end
	local profile = Copy(ns.db.profile) -- raw keys only: pairs doesn't see AceDB's defaults
	Strip(profile, ns.DEFAULTS.profile)
	local _, class = UnitClass("player")
	local payload = {
		v = 1,
		addon = Version(),
		name = ns.db:GetCurrentProfile(),
		class = class,
		profile = profile,
	}
	local packed = deflate:CompressDeflate(ser:Serialize(payload), { level = 9 })
	return PREFIX .. deflate:EncodeForPrint(packed), Count(profile)
end

-- Keep only what this version knows, in the shape it expects.
local function Clean(t, defaults, inherit)
	local dropped = 0
	for k, v in pairs(t) do
		local d = DefaultOf(defaults, k, inherit)
		local keyOK = type(k) == "string" or type(k) == "number"
		if not keyOK then
			t[k] = nil
			dropped = dropped + 1
		elseif d ~= nil and type(d) ~= "table" and type(v) ~= "table" and type(v) ~= type(d) then
			-- A number where a number belongs, and so on.
			t[k] = nil
			dropped = dropped + 1
		elseif type(v) == "table" then
			if d ~= nil and type(d) ~= "table" then
				t[k] = nil
				dropped = dropped + 1
			elseif type(d) == "table" then
				dropped = dropped + Clean(v, d, InheritOf(defaults, k))
			end
		elseif d ~= nil and type(d) == "table" then
			-- A value where the defaults have a table: the one exception is an old on/off,
			-- which Migrate converts (auras). Anything else would break the table's readers.
			if type(v) ~= "boolean" then
				t[k] = nil
				dropped = dropped + 1
			end
		end
	end
	return dropped
end

-- Pie menu macros keep their name only (see the top).
local function Defuse(profile)
	local rings = type(profile.pie) == "table" and profile.pie.rings
	if type(rings) ~= "table" then return 0 end
	local n = 0
	for _, ring in pairs(rings) do
		if type(ring) == "table" and type(ring.slices) == "table" then
			for _, slice in pairs(ring.slices) do
				if type(slice) == "table" and slice.body ~= nil then
					slice.body = nil
					n = n + 1
				end
			end
		end
	end
	return n
end

-- Read a pasted string. Returns info { name, class, addon, profile, count, dropped, macros } or
-- nil and why.
function S.Decode(text)
	if type(text) ~= "string" then return nil, "Nothing pasted." end
	text = text:gsub("%s", "")
	if text == "" then return nil, "Nothing pasted." end
	if #text > MAX_LEN then return nil, "That is far too long to be a SanctuaryUI profile." end
	if text:sub(1, #PREFIX) ~= PREFIX then
		return nil, "That isn't a SanctuaryUI profile string (it should start with " .. PREFIX .. ")."
	end
	local ser, deflate = Libs()
	if not ser or not deflate then return nil, "The import libraries didn't load (restart the game after updating)." end
	local packed = deflate:DecodeForPrint(text:sub(#PREFIX + 1))
	local raw = packed and deflate:DecompressDeflate(packed)
	if not raw then return nil, "The string is damaged or cut short: copy all of it again." end
	local ok, payload = ser:Deserialize(raw)
	if not ok or type(payload) ~= "table" or type(payload.profile) ~= "table" then
		return nil, "The string is damaged: its settings couldn't be read."
	end
	local profile = payload.profile
	local dropped = Clean(profile, ns.DEFAULTS.profile)
	local macros = Defuse(profile)
	return {
		name = type(payload.name) == "string" and payload.name:sub(1, 48) or "Imported",
		class = type(payload.class) == "string" and payload.class or nil,
		addon = type(payload.addon) == "string" and payload.addon or "?",
		profile = profile,
		count = Count(profile),
		dropped = dropped,
		macros = macros,
	}
end

local function Assign(dst, src)
	for k, v in pairs(src) do
		if type(v) == "table" and type(dst[k]) == "table" then
			Assign(dst[k], v)
		else
			dst[k] = Copy(v)
		end
	end
end

function S.ProfileExists(name)
	for _, existing in ipairs(ns.db:GetProfiles()) do
		if existing == name then return true end
	end
	return false
end

-- mode "new": a new profile called name, switched to. "replace": the current profile, reset first.
function S.Import(info, mode, name)
	if InCombatLockdown() then return false, "Not in combat: try again once it ends." end
	if not info then return false, "Paste a profile string first." end
	if mode == "new" then
		name = name and name:match("^%s*(.-)%s*$") or ""
		if name == "" then return false, "Give the new profile a name." end
		if S.ProfileExists(name) then return false, ("There is already a profile called %s."):format(name) end
		ns.db:SetProfile(name)
	else
		ns.db:ResetProfile(false, true)
	end
	Assign(ns.db.profile, info.profile)
	if ns.Migrate then ns.Migrate(ns.db.profile) end
	ns.Log("profile imported (%s): %d settings from %s, %s", mode, info.count, tostring(info.name), tostring(info.addon))
	ns.Refresh()
	StaticPopup_Show("SANCTUARYUI_IMPORT_RELOAD")
	return true
end

StaticPopupDialogs["SANCTUARYUI_IMPORT_RELOAD"] = {
	text = "Profile imported. Most of it is in place already; a reload settles the rest (bars, fonts and the frames that only build once).",
	button1 = "Reload now",
	button2 = "Later",
	OnAccept = function() ReloadUI() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

-- A profile name not yet taken: "Name (imported)", then "(imported 2)" and on.
function S.FreeName(name)
	local base = (name and name ~= "" and name or "Imported") .. " (imported"
	local candidate = base .. ")"
	local n = 2
	while S.ProfileExists(candidate) do
		candidate = ("%s %d)"):format(base, n)
		n = n + 1
	end
	return candidate
end
