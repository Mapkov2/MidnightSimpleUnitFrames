-- Blizzard's Bag Slot Padding slider has no ConvertValue, so its display info
-- falls back to DefaultSettingDisplayInfo:ConvertValue: the layout stores the
-- shown value itself and a read clamps it to the slider's 2..10
-- (Blizzard_EditMode/Shared/EditModeSettingDisplayInfo.lua on live, forever,
-- classic, classic_anniversary and classic_era;
-- EditModeBagsSystemMixin:UpdateSystemSettingBagSlotPadding assigns that
-- clamped value to BagsBar.bagPadding). The MSUF Edit Mode stepper converted
-- it like a ConvertValueDefault slider (shown = raw + 2): Blizzard's 4 showed
-- as 6, a 6 was saved as 4, 9 and 10 were out of reach, and 2 or 3 saved 0 or
-- 1, below Blizzard's minimum, which MSUF then painted as the bag padding.
-- Every other stepper keeps its ConvertValueDefault / ConvertValueDiffFromMin
-- conversion (identical at step 1).
-- Real ExternalProvider.lua and MSUF_EditMode_Blizzard.lua. arg 1 = repo root.
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")

local failures = {}
local function Check(condition, message)
    if not condition then failures[#failures + 1] = message end
    return condition
end

-- Enum values from the live EditModeManagerConstantsDocumentation.lua.
local SYSTEM = { Minimap = 2, ChatFrame = 8, HudTooltip = 11, MicroMenu = 13, Bags = 14, DamageMeter = 23 }
Enum = {
    EditModeSystem = SYSTEM,
    EditModePresetLayoutsMeta = { NumValues = 2 },
    EditModeMinimapSetting = { HeaderUnderneath = 0, RotateMinimap = 1, Size = 2 },
    EditModeChatFrameSetting = { WidthHundreds = 0, WidthTensAndOnes = 1, HeightHundreds = 2, HeightTensAndOnes = 3 },
    EditModeMicroMenuSetting = { Orientation = 0, Order = 1, Size = 2, EyeSize = 3 },
    EditModeBagsSetting = { Orientation = 0, Direction = 1, Size = 2, BagSlotPadding = 3 },
    EditModeDamageMeterSetting = {
        FrameWidth = 3, FrameHeight = 4, Padding = 5, Transparency = 6,
        ShowSpecIcon = 8, ShowClassColor = 9, BarHeight = 10,
        TextSize = 11, BackgroundTransparency = 12,
    },
    EditModeLayoutType = { Account = 1, Character = 2 },
    MicroMenuOrientation = { Horizontal = 0, Vertical = 1 },
    MicroMenuOrder = { Default = 0, Reverse = 1 },
    BagsOrientation = { Horizontal = 0, Vertical = 1 },
}

-- Plain frames with only the methods the adapter calls on these systems.
local created = {}
local function Frame(systemId)
    local frame = { system = systemId, events = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:SetScript(_, fn) self.onEvent = fn end
    function frame:GetScale() return 1 end
    function frame:SetScale(scale) self.scale = scale end
    function frame:ClearAllPoints() end
    function frame:SetPoint() end
    function frame:Layout() self.layoutCount = (self.layoutCount or 0) + 1 end
    function frame:SetBarSpacing(value) self.barSpacing = value end
    return frame
end
CreateFrame = function()
    local frame = Frame(nil)
    created[#created + 1] = frame
    return frame
end
UIParent = Frame(nil)
local bagsBar = Frame(SYSTEM.Bags)
local meter = Frame(SYSTEM.DamageMeter)
EditModeManagerFrame = { registeredSystemFrames = { Frame(SYSTEM.Minimap), bagsBar, meter } }
InCombatLockdown = function() return false end

local function Row(setting, value) return { setting = setting, value = value } end
local bagsEntry = {
    system = SYSTEM.Bags,
    anchorInfo = { point = "BOTTOMRIGHT", relativeTo = "UIParent", relativePoint = "BOTTOMRIGHT", offsetX = -4, offsetY = 50 },
    -- Size raw 5 shows 100 %; padding 4 is stored as shown.
    settings = { Row(0, 0), Row(1, 0), Row(2, 5), Row(3, 4) },
}
local meterEntry = {
    system = SYSTEM.DamageMeter,
    anchorInfo = { point = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER", offsetX = 0, offsetY = 0 },
    -- Damage Meter Padding is a ConvertValueDefault slider: raw 3 shows 5.
    settings = { Row(5, 3) },
}
local layoutInfo = {
    activeLayout = 3,
    layouts = { { layoutName = "Mine", layoutType = 1, systems = { bagsEntry, meterEntry } } },
}
local saves = 0
C_EditMode = {
    GetLayouts = function() return layoutInfo end,
    SaveLayouts = function(info)
        assert(info == layoutInfo, "adapter saved a detached layout table")
        saves = saves + 1
    end,
    SetActiveLayout = function(index) layoutInfo.activeLayout = index end,
}

local registered = {}
MSUF_EditModeAPI = {
    RegisterElement = function(_, element) registered[element.id] = element; return true end,
    UnregisterOwner = function() return true end,
    RegisterSessionListener = function() return true end,
    RefreshOwner = function() return true end,
}
local general
MSUF_GetGeneralDB = function() return general end
MSUF_EM2 = { Registry = {} }

local ns = {
    ExportPublic = function(name, value) _G[name] = value; return value end,
    Client = { IsForever = false, SupportsEvent = function() return true end },
}
local RequireFixture = assert(loadfile(root .. "/tools/tests/require_fixture.lua"))()
RequireFixture.Install(root, ns)
for _, path in ipairs({
    "MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_ExternalProvider.lua",
    "MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_Blizzard.lua",
}) do
    assert(loadfile(root .. "/" .. path))("MidnightSimpleUnitFrames", ns)
end
-- SavedVariables step, then PLAYER_LOGIN activates the adapter.
general = { blizzardEditModeIntegration = true, blizzardEditModeSnapshot = {} }
for _, frame in ipairs(created) do
    if frame.events.PLAYER_LOGIN and frame.onEvent then frame.onEvent(frame, "PLAYER_LOGIN") end
end

local function Control(elementId, controlId)
    local element = assert(registered[elementId], "Blizzard Edit Mode element missing: " .. elementId)
    for _, control in ipairs(element.extraControls or {}) do
        if control.id == controlId then return control end
    end
    error("missing " .. elementId .. " control " .. controlId)
end
local function Stored(entry, setting)
    for _, row in ipairs(entry.settings) do
        if row.setting == setting then return row.value end
    end
end
local padding = Control("bags", "padding")

Check(padding.min == 2 and padding.max == 10 and padding.step == 1,
    "Bag Slot Padding range changed from Blizzard's 2..10 step 1")
Check(padding.get() == 4,
    "Bag Slot Padding shows " .. tostring(padding.get()) .. " for Blizzard's stored 4")

for _, value in ipairs({ 6, 9, 10, 2, 3 }) do
    Check(padding.set(value) == true, "Bag Slot Padding " .. value .. " did not commit")
    Check(Stored(bagsEntry, 3) == value,
        "Bag Slot Padding " .. value .. " saved raw " .. tostring(Stored(bagsEntry, 3)) .. ", Blizzard stores the shown value")
    Check(bagsBar.bagPadding == value,
        "Bag Slot Padding " .. value .. " painted BagsBar.bagPadding " .. tostring(bagsBar.bagPadding))
    Check(padding.get() == value, "Bag Slot Padding " .. value .. " read back as " .. tostring(padding.get()))
end
padding.set(1)
Check(Stored(bagsEntry, 3) == 2, "Bag Slot Padding below the range saved " .. tostring(Stored(bagsEntry, 3)) .. ", expected 2")
padding.set(14)
Check(Stored(bagsEntry, 3) == 10, "Bag Slot Padding above the range saved " .. tostring(Stored(bagsEntry, 3)) .. ", expected 10")

-- A row an older build saved below the minimum: shown and painted as
-- Blizzard's clamped 2, also when another Bags setting re-applies the row.
bagsEntry.settings[4].value = 0
Check(padding.get() == 2, "a stored padding 0 shows " .. tostring(padding.get()) .. ", Blizzard shows 2")
Check(Control("bags", "size").set(100) == true, "Bags size did not commit")
Check(bagsBar.bagPadding == 2,
    "a stored padding 0 painted BagsBar.bagPadding " .. tostring(bagsBar.bagPadding) .. ", Blizzard paints 2")

-- The ConvertValueDefault steppers keep their conversion.
local size = Control("bags", "size")
Check(size.get() == 100, "Bags size raw 5 shows " .. tostring(size.get()) .. ", expected 100")
size.set(150)
Check(Stored(bagsEntry, 2) == 15, "Bags size 150 saved raw " .. tostring(Stored(bagsEntry, 2)) .. ", expected 15")
local meterPadding = Control("damagemeter", "padding")
Check(meterPadding.get() == 5, "Damage Meter padding raw 3 shows " .. tostring(meterPadding.get()) .. ", expected 5")
meterPadding.set(8)
Check(Stored(meterEntry, 5) == 6, "Damage Meter padding 8 saved raw " .. tostring(Stored(meterEntry, 5)) .. ", expected 6")
Check(meter.barSpacing == 8, "Damage Meter padding 8 painted bar spacing " .. tostring(meter.barSpacing))
Check(saves > 0, "no setting was saved")

if #failures > 0 then
    error("Edit Mode Bag Slot Padding smoke failed:\n  " .. table.concat(failures, "\n  "), 0)
end
print("Edit Mode Bag Slot Padding smoke passed")
