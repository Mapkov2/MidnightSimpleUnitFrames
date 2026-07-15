-- Exact live-anchor parity for the castbar offsets in the supplied MSUF 5.5
-- profile. This catches the 6.0 double-rounding regression (0 became 1).
local root = arg and arg[1] or "."

local function Check(condition, message)
    if not condition then error(message or "check failed", 2) end
end

local function NewFrame(name)
    local frame = { name = name, width = 250, height = 18, shown = true }
    function frame:ClearAllPoints() self.point = nil end
    function frame:SetPoint(point, relativeTo, relativePoint, x, y)
        self.point = { point, relativeTo, relativePoint, x, y }
    end
    function frame:GetPoint()
        local p = self.point
        if not p then return nil end
        return p[1], p[2], p[3], p[4], p[5]
    end
    function frame:SetWidth(value) self.width = value end
    function frame:SetHeight(value) self.height = value end
    function frame:GetWidth() return self.width end
    function frame:GetHeight() return self.height end
    function frame:SetScript() end
    function frame:Hide() self.shown = false end
    function frame:Show() self.shown = true end
    return frame
end

local bootFrame = NewFrame("boot")
function bootFrame:RegisterEvent() end
function bootFrame:UnregisterAllEvents() end
_G.CreateFrame = function() return bootFrame end
_G.InCombatLockdown = function() return false end
_G.UnitAffectingCombat = function() return false end
_G.EnsureDB = function() end
_G.UIParent = NewFrame("UIParent")

local unitFrames = {
    player = NewFrame("playerUF"),
    target = NewFrame("targetUF"),
    focus = NewFrame("focusUF"),
}
local namespace = {
    UF = {
        frames = unitFrames,
        GetFrame = function(unit) return unitFrames[unit] end,
    },
    ExportPublic = function(name, value)
        _G[name] = value
        return value
    end,
}
_G.MSUF_NS = namespace

_G.MSUF_SetPointIfChanged = function(frame, point, relativeTo, relativePoint, x, y)
    frame:ClearAllPoints()
    frame:SetPoint(point, relativeTo, relativePoint, x, y)
end
_G.MSUF_SetWidthIfChanged = function(frame, width) frame:SetWidth(width) end
_G.MSUF_SetHeightIfChanged = function(frame, height) frame:SetHeight(height) end
_G.MSUF_HideBlizzardPlayerCastbar = function() end
_G.MSUF_PlayerCastbar_ApplyBackendState = function() end

_G.MSUF_DB = {
    general = {
        enablePlayerCastbar = true,
        enableTargetCastbar = true,
        enableFocusCastbar = true,
        castbarPlayerBarWidth = 288,
        castbarPlayerBarHeight = 10,
        castbarPlayerOffsetX = 0,
        castbarPlayerOffsetY = -38,
        castbarTargetBarWidth = 223,
        castbarTargetBarHeight = 18,
        castbarTargetOffsetX = 0,
        castbarTargetOffsetY = -58,
        castbarFocusBarWidth = 222,
        castbarFocusBarHeight = 18,
        castbarFocusOffsetX = 1,
        castbarFocusOffsetY = -58,
    },
}

local function NewCastbar(name)
    local frame = NewFrame(name)
    frame.statusBar = NewFrame(name .. "Status")
    return frame
end

_G.MSUF_PlayerCastbar = NewCastbar("playerCast")
_G.MSUF_TargetCastbar = NewCastbar("targetCast")
_G.MSUF_FocusCastbar = NewCastbar("focusCast")

assert(loadfile(root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_CastbarAnchors.lua"))(
    "MidnightSimpleUnitFrames", namespace)

local function EqualPoint(frame, point, relativeTo, relativePoint, x, y, label)
    local actual = frame.point or {}
    Check(actual[1] == point and actual[2] == relativeTo and actual[3] == relativePoint
        and actual[4] == x and actual[5] == y,
        string.format("%s anchor drifted: %s/%s x=%s y=%s", label,
            tostring(actual[1]), tostring(actual[3]), tostring(actual[4]), tostring(actual[5])))
end

assert(_G.MSUF_ReanchorPlayerCastBarBase)()
assert(_G.MSUF_ReanchorTargetCastBarBase)()
assert(_G.MSUF_ReanchorFocusCastBarBase)()

EqualPoint(_G.MSUF_PlayerCastbar, "BOTTOM", unitFrames.player, "TOP", 0, -38, "player")
EqualPoint(_G.MSUF_TargetCastbar, "BOTTOMLEFT", unitFrames.target, "TOPLEFT", 0, -58, "target")
EqualPoint(_G.MSUF_FocusCastbar, "BOTTOMLEFT", unitFrames.focus, "TOPLEFT", 1, -58, "focus")

Check(_G.MSUF_PlayerCastbar.width == 288 and _G.MSUF_PlayerCastbar.height == 10,
    "player castbar size drifted")
Check(_G.MSUF_TargetCastbar.width == 223 and _G.MSUF_TargetCastbar.height == 18,
    "target castbar size drifted")
Check(_G.MSUF_FocusCastbar.width == 222 and _G.MSUF_FocusCastbar.height == 18,
    "focus castbar size drifted")

-- Detached mode uses the same saved offsets, only relative to UIParent CENTER.
local general = _G.MSUF_DB.general
general.castbarPlayerDetached = true
general.castbarTargetDetached = true
general.castbarFocusDetached = true
assert(_G.MSUF_ReanchorPlayerCastBarBase)()
assert(_G.MSUF_ReanchorTargetCastBarBase)()
assert(_G.MSUF_ReanchorFocusCastBarBase)()
EqualPoint(_G.MSUF_PlayerCastbar, "CENTER", _G.UIParent, "CENTER", 0, -38, "detached player")
EqualPoint(_G.MSUF_TargetCastbar, "CENTER", _G.UIParent, "CENTER", 0, -58, "detached target")
EqualPoint(_G.MSUF_FocusCastbar, "CENTER", _G.UIParent, "CENTER", 1, -58, "detached focus")

print("PASS legacy 5.5 castbar anchors: exact attached/detached position and size parity")
