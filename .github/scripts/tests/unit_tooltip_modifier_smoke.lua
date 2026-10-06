local function fail(message)
    error("unit_tooltip_modifier_smoke: " .. tostring(message), 0)
end

local function expect(condition, message)
    if not condition then fail(message) end
end

local function readFile(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a")
    file:close()
    return text
end

local function resolvePath(relative)
    local candidates = {
        relative,
        "../" .. relative,
        "../../../" .. relative,
    }
    for _, path in ipairs(candidates) do
        local file = io.open(path, "rb")
        if file then
            file:close()
            return path
        end
    end
    fail("cannot resolve " .. relative)
end

local runtimePath = resolvePath("MidnightSimpleUnitFrames/Runtime/MSUF_UnitTooltips.lua")
local groupPath = resolvePath("MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Adapter.lua")

local controlDown = false
local shiftDown = false
local altDown = false
local watcher

MSUF_DB = {
    general = {
        unitTooltipProvider = "GAME",
        unitTooltipAnchor = "EXTERNAL",
        unitTooltipMode = "MODIFIER",
        unitTooltipModifier = "CTRL",
        disableUnitInfoTooltips = true,
        unitInfoTooltipStyle = "classic",
    },
}
MSUF_EnsureDB = function() end
UnitExists = function() return true end
IsControlKeyDown = function() return controlDown end
IsShiftKeyDown = function() return shiftDown end
IsAltKeyDown = function() return altDown end
InCombatLockdown = function() return false end
UIParent = {}

GameTooltip = {
    shown = false,
    hiddenCount = 0,
}
function GameTooltip:HookScript() end
function GameTooltip:IsForbidden() return false end
function GameTooltip:IsShown() return self.shown end
function GameTooltip:SetOwner(owner) self.owner = owner end
function GameTooltip:SetUnit(unit) self.unit = unit end
function GameTooltip:GetUnit() return nil, self.unit end
function GameTooltip:Show() self.shown = true end
function GameTooltip:Hide()
    self.shown = false
    self.hiddenCount = self.hiddenCount + 1
end
hooksecurefunc = function(object, key, callback)
    local original = object[key]
    object[key] = function(self, ...)
        original(self, ...)
        callback(self, ...)
    end
end
GameTooltip_SetDefaultAnchor = function(tooltip, owner)
    tooltip:SetOwner(owner)
end

CreateFrame = function()
    local frame = { events = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:SetScript(script, handler) self[script] = handler end
    watcher = frame
    return frame
end

local MSUF = {}
-- The tooltip runtime declares MSUF_EnsureDB (State/MSUF_Defaults.lua, which
-- loads long before it) a hard dependency through MSUF.Require, installed by
-- Kernel/MSUF_Require.lua right after Kernel/MSUF_Boundary.lua in the TOC.
_G.MSUF_EnsureDB = function() return _G.MSUF_DB end
assert(loadfile((runtimePath:gsub("Runtime/MSUF_UnitTooltips%.lua$", "Kernel/MSUF_Require.lua"))))(
    "MidnightSimpleUnitFrames", MSUF)
local chunk = assert(loadfile(runtimePath))
chunk("MidnightSimpleUnitFrames", MSUF)

expect(watcher and not watcher.events.MODIFIER_STATE_CHANGED,
    "runtime listens for modifier transitions without a hovered frame")
expect(type(watcher.OnEvent) == "function", "modifier watcher has no OnEvent handler")

local owner = { hovered = true, shown = true }
function owner:IsMouseOver() return self.hovered end
function owner:IsShown() return self.shown end

expect(MSUF.Tooltips.ShowUnit(owner, "target") == false,
    "CTRL-gated tooltip showed without CTRL")
expect(not GameTooltip.shown, "tooltip became visible before CTRL was pressed")
expect(watcher.events.MODIFIER_STATE_CHANGED,
    "runtime did not listen for modifier transitions during a gated hover")

controlDown = true
watcher:OnEvent("MODIFIER_STATE_CHANGED", "LCTRL", 1)
expect(GameTooltip.shown and GameTooltip.unit == "target",
    "pressing CTRL while hovered did not show the tooltip")

controlDown = false
watcher:OnEvent("MODIFIER_STATE_CHANGED", "LCTRL", 0)
expect(not GameTooltip.shown,
    "releasing CTRL while hovered did not hide the tooltip")

-- A modifier transition must never hide a GameTooltip that another owner has
-- replaced while the MSUF frame remains hovered.
GameTooltip.shown = true
GameTooltip.unit = "foreign-tooltip"
GameTooltip._msufUnitTooltipOwner = nil
GameTooltip._msufUnitTooltipUnit = nil
watcher:OnEvent("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
expect(GameTooltip.shown and GameTooltip.unit == "foreign-tooltip",
    "modifier refresh hid a GameTooltip not owned by the hovered MSUF frame")
GameTooltip:Hide()

controlDown = true
watcher:OnEvent("MODIFIER_STATE_CHANGED", "LCTRL", 1)
expect(GameTooltip.shown, "pressing CTRL a second time did not restore the tooltip")

MSUF_DB.general.unitTooltipModifier = "SHIFT"
shiftDown = false
MSUF.Tooltips.HideUnit(owner)
MSUF.Tooltips.ShowUnit(owner, "target")
shiftDown = true
watcher:OnEvent("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
expect(GameTooltip.shown, "the newly selected modifier did not show the tooltip")

owner.hovered = false
MSUF.Tooltips.HideUnit(owner)
expect(not watcher.events.MODIFIER_STATE_CHANGED,
    "runtime kept its modifier listener after the owner received OnLeave")
watcher:OnEvent("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
expect(not GameTooltip.shown, "tooltip returned after the owner received OnLeave")

local groupSource = readFile(groupPath)
local gateAt = groupSource:find("if not TooltipAllowed%(%) then")
local trackAt = groupSource:find("tooltips.TrackUnitHover%(self, StoredAttrUnit%(self%)%)")
expect(gateAt and trackAt and gateAt < trackAt,
    "group frames do not record a modifier-blocked hover")

print("unit_tooltip_modifier_smoke: OK")
