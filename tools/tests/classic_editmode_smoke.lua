local root = assert(arg[1], "repo root missing")
local modulePath = root .. "/MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_Blizzard.lua"

local function ClearExports()
    for _, name in ipairs({
        "MSUF_BlizzardEditMode_IsAvailable",
        "MSUF_BlizzardEditMode_SetEnabled",
        "MSUF_BlizzardEditMode_EnsureLayout",
        "MSUF_BlizzardEditMode_ApplyProfileSnapshot",
        "MSUF_BlizzardEditMode_Debug",
    }) do
        _G[name] = nil
    end
end

-- Older or partial Classic clients must load the shared manifest without
-- constructing a Blizzard adapter when the native Edit Mode enum is absent.
ClearExports()
Enum = nil
C_EditMode = nil
MSUF_EditModeAPI = {
    RegisterElement = function()
        error("Blizzard element registered without Enum.EditModeSystem")
    end,
}
assert(loadfile(modulePath))("MidnightSimpleUnitFrames", {})
assert(MSUF_BlizzardEditMode_IsAvailable == nil,
    "unsupported Classic client exported a partial Blizzard adapter")

-- Some transitional clients expose the enum before the C_EditMode namespace.
-- The module may publish its probe there, but must not register dead movers.
local prematureRegistrations = 0
Enum = { EditModeSystem = { Minimap = 1 } }
C_EditMode = nil
MSUF_EditModeAPI = {
    RegisterElement = function()
        prematureRegistrations = prematureRegistrations + 1
        return true
    end,
}
MSUF_DB = { general = { blizzardEditModeIntegration = true } }
ClearExports()
assert(loadfile(modulePath))("MidnightSimpleUnitFrames", {})
assert(type(MSUF_BlizzardEditMode_IsAvailable) == "function"
    and MSUF_BlizzardEditMode_IsAvailable() == false,
    "partial Classic client reported Blizzard Edit Mode as available")
assert(prematureRegistrations == 0,
    "partial Classic client registered unusable Blizzard movers")

local system = {
    Minimap = 1,
    ChatFrame = 2,
    MicroMenu = 3,
    HudTooltip = 4,
    Bags = 5,
    ObjectiveTracker = 6,
    DamageMeter = 23,
}
Enum = {
    EditModeSystem = system,
    EditModePresetLayoutsMeta = { NumValues = 2 },
    EditModeMinimapSetting = { HeaderUnderneath = 0, RotateMinimap = 1, Size = 2 },
    EditModeChatFrameSetting = { WidthHundreds = 0, WidthTensAndOnes = 1, HeightHundreds = 2, HeightTensAndOnes = 3 },
    EditModeMicroMenuSetting = { Orientation = 0, Order = 1, Size = 2, EyeSize = 3 },
    EditModeBagsSetting = { Orientation = 0, Direction = 1, Size = 2, BagSlotPadding = 3 },
    EditModeObjectiveTrackerSetting = { Opacity = 1, TextSize = 2 },
    EditModeDamageMeterSetting = {
        FrameWidth = 3, FrameHeight = 4, Padding = 5, Transparency = 6,
        ShowSpecIcon = 8, ShowClassColor = 9, BarHeight = 10,
        TextSize = 11, BackgroundTransparency = 12,
    },
    EditModeLayoutType = { Account = 1, Character = 2 },
    MicroMenuOrientation = { Horizontal = 0 },
    MicroMenuOrder = { Default = 0 },
    BagsOrientation = { Horizontal = 0 },
}

local function Frame(systemId, left, bottom, width, height)
    local frame = {
        system = systemId,
        left = left or 100,
        bottom = bottom or 100,
        width = width or 200,
        height = height or 100,
        shown = false,
    }
    function frame:GetLeft() return self.left end
    function frame:GetRight() return self.left + self.width end
    function frame:GetBottom() return self.bottom end
    function frame:GetTop() return self.bottom + self.height end
    function frame:GetWidth() return self.width end
    function frame:GetHeight() return self.height end
    function frame:GetScale() return 1 end
    function frame:GetEffectiveScale() return 1 end
    function frame:ClearAllPoints() self.cleared = true end
    function frame:SetPoint(point, relative, relativePoint, x, y)
        self.point = { point, relative, relativePoint, x, y }
    end
    function frame:SetSize(widthValue, heightValue)
        self.width, self.height = widthValue, heightValue
    end
    function frame:IsShown() return self.shown end
    function frame:Show() self.shown = true; self.showCount = (self.showCount or 0) + 1 end
    function frame:Hide() self.shown = false; self.hideCount = (self.hideCount or 0) + 1 end
    function frame:Layout() self.layoutCount = (self.layoutCount or 0) + 1 end
    function frame:SetHeaderUnderneath(value) self.headerUnderneath = value end
    return frame
end

UIParent = Frame(nil, 0, 0, 1920, 1080)
local frames = {
    Frame(system.Minimap, 1600, 850, 200, 200),
    Frame(system.ChatFrame, 20, 20, 430, 180),
    Frame(system.MicroMenu, 700, 10, 520, 50),
    Frame(system.HudTooltip, 1250, 250, 300, 120),
    Frame(system.Bags, 1450, 10, 350, 60),
    Frame(system.ObjectiveTracker, 1450, 450, 350, 450),
    Frame(system.DamageMeter, 1200, 200, 300, 220),
}
EditModeManagerFrame = { registeredSystemFrames = frames }
MinimapCluster = frames[1]
ChatFrame1 = frames[2]
MicroMenuContainer = frames[3]
GameTooltipDefaultContainer = frames[4]
BagsBar = frames[5]
ObjectiveTrackerFrame = frames[6]
DamageMeter = frames[7]
MicroMenu = {}

local function Entry(systemId, x, y)
    return {
        system = systemId,
        anchorInfo = {
            point = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER",
            offsetX = x or 0, offsetY = y or 0,
        },
        settings = {},
    }
end

local layoutInfo = {
    activeLayout = 3,
    layouts = {{
        layoutName = "Classic Test",
        layoutType = 1,
        systems = {
            Entry(system.Minimap, 10, 20),
            Entry(system.ChatFrame),
            Entry(system.MicroMenu),
            Entry(system.HudTooltip),
            Entry(system.Bags),
            Entry(system.ObjectiveTracker),
            -- Damage Meter deliberately absent: old layouts need a seeded row.
        },
    }},
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

local registered, listener = {}, nil
MSUF_EditModeAPI = {
    RegisterElement = function(owner, element)
        assert(owner == "MSUF.Blizzard", "wrong Blizzard Edit Mode owner")
        registered[element.id] = element
        return true
    end,
    UnregisterOwner = function(owner) assert(owner == "MSUF.Blizzard") end,
    RegisterSessionListener = function(owner, callback)
        assert(owner == "MSUF.Blizzard")
        listener = callback
    end,
    RefreshOwner = function(owner) assert(owner == "MSUF.Blizzard") end,
}
MSUF_DB = {
    general = {
        blizzardEditModeIntegration = true,
        blizzardEditModeSnapshot = {},
    },
}
InCombatLockdown = function() return false end
ShowUIPanel = function(frame) frame.panelShown = (frame.panelShown or 0) + 1 end
HideUIPanel = function(frame) frame.panelHidden = (frame.panelHidden or 0) + 1 end

local namespace = {}
function namespace.ExportPublic(name, value)
    _G[name] = value
    return value
end
ClearExports()
assert(loadfile(modulePath))("MidnightSimpleUnitFrames", namespace)

assert(type(MSUF_BlizzardEditMode_IsAvailable) == "function"
    and MSUF_BlizzardEditMode_IsAvailable() == true,
    "Classic C_EditMode availability was not exported")
for _, id in ipairs({ "minimap", "chat", "micromenu", "tooltip", "bags", "damagemeter" }) do
    assert(type(registered[id]) == "table", "missing Classic Edit Mode element: " .. id)
    assert(registered[id].isEnabled() == true, "Classic Edit Mode element disabled: " .. id)
end
assert(registered.tracker == nil, "Objective Tracker must remain entirely Blizzard-owned")
assert(type(listener) == "function", "Classic Edit Mode session listener missing")

local meterState = assert(registered.damagemeter.captureState(),
    "Damage Meter could not seed a missing Classic layout row")
assert(#layoutInfo.layouts[1].systems == 7,
    "Damage Meter seed did not extend the active layout")
assert(meterState.point == "CENTER" and type(meterState.x) == "number" and type(meterState.y) == "number",
    "seeded Damage Meter state is incomplete")
assert(registered.damagemeter.movePosition({
    phase = "commit", state = meterState, deltaX = 15, deltaY = -9,
}) == true, "Damage Meter move did not commit")
assert(saves == 1, "Damage Meter move did not save exactly once")
assert(MSUF_DB.general.blizzardEditModeSnapshot.damagemeter.x == meterState.x + 15
    and MSUF_DB.general.blizzardEditModeSnapshot.damagemeter.y == meterState.y - 9,
    "Damage Meter position was not copied into the MSUF profile snapshot")

MSUF_Tooltip_IsBlizzardControlled = function() return false end
listener(true)
assert(GameTooltipDefaultContainer.showCount == nil,
    "Blizzard tooltip mover appeared while the MSUF tooltip owned Edit Mode")
listener(false)
MSUF_Tooltip_IsBlizzardControlled = function() return true end
listener(true)
assert(GameTooltipDefaultContainer.showCount == 1,
    "Blizzard tooltip mover did not appear for the Blizzard-owned tooltip")
listener(false)
assert(GameTooltipDefaultContainer.hideCount == 1,
    "temporary Blizzard tooltip mover was not restored on session exit")

MSUF_DB.general.blizzardEditModeSnapshot.minimap = {
    point = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER",
    x = 42, y = -31,
}
assert(MSUF_BlizzardEditMode_ApplyProfileSnapshot() == true,
    "Classic profile snapshot did not apply")
assert(layoutInfo.layouts[1].systems[1].anchorInfo.offsetX == 42
    and layoutInfo.layouts[1].systems[1].anchorInfo.offsetY == -31,
    "profile snapshot did not update the active Blizzard layout")
assert(saves == 2, "profile snapshot did not save exactly once")

local function Read(relativePath)
    local file = assert(io.open(root .. "/" .. relativePath, "rb"))
    local source = file:read("*a")
    file:close()
    return source
end
local manifest = Read("MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode.xml")
assert(manifest:find('MSUF_EditMode_Blizzard.lua', 1, true),
    "shared Classic Edit Mode manifest does not load the Blizzard adapter")
local profileSource = Read("MidnightSimpleUnitFrames/State/MSUF_Profiles.lua")
for _, contract in ipairs({
    "MSUF_Profiles_SetExportBlizzardEditMode",
    "MSUF_Profiles_SetImportBlizzardEditMode",
    "blizzardEditModeSnapshot",
    "MSUF_BlizzardEditMode_ApplyProfileSnapshot",
}) do
    assert(profileSource:find(contract, 1, true),
        "Classic profile Edit Mode contract missing: " .. contract)
end
local auraModel = Read("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_Menu_Model.lua")
assert(auraModel:find("buffSpacing = true", 1, true)
    and auraModel:find("debuffSpacing = true", 1, true),
    "Classic profile model drops per-lane aura spacing")

print("Classic Edit Mode smoke passed")
