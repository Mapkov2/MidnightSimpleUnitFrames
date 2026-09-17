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

local function ControlIds(element)
    local ids = {}
    for _, control in ipairs(element and element.extraControls or {}) do ids[#ids + 1] = control.id end
    return table.concat(ids, ",")
end
assert(ControlIds(registered.micromenu) == "size,eyesize,vertical,reverse",
    "Micro Menu controls changed on a client that still has the Eye Size setting: "
        .. ControlIds(registered.micromenu))

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
assert(MSUF_DB.general.blizzardEditModeSnapshot.damagemeter.forever == nil,
    "a non-Forever snapshot entry carried the WoW Forever stamp")

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
-- An entry captured on WoW Forever belongs to its own HUD defaults.
MSUF_DB.general.blizzardEditModeSnapshot.chat = {
    point = "BOTTOMLEFT", relativeTo = "UIParent", relativePoint = "BOTTOMLEFT",
    x = 77, y = 145, forever = true,
}
assert(MSUF_BlizzardEditMode_ApplyProfileSnapshot() == true,
    "Classic profile snapshot did not apply")
assert(layoutInfo.layouts[1].systems[1].anchorInfo.offsetX == 42
    and layoutInfo.layouts[1].systems[1].anchorInfo.offsetY == -31,
    "profile snapshot did not update the active Blizzard layout")
assert(layoutInfo.layouts[1].systems[2].anchorInfo.point == "CENTER"
    and layoutInfo.layouts[1].systems[2].anchorInfo.offsetX == 0,
    "a WoW Forever snapshot entry rearranged a non-Forever HUD")
assert(saves == 2, "profile snapshot did not save exactly once")

-- Isolated adapter loads for client-shaped cases: fresh frames, layout data,
-- registrations and profile state per load.
local function Untouchable(frame, label)
    for name, value in pairs(frame) do
        if type(value) == "function" then
            frame[name] = function() error(label .. ":" .. name .. " was called on WoW Forever", 2) end
        end
    end
    return frame
end

local function LoadAdapter(opts)
    local ctx = { registered = {}, saves = 0, normalScaleCalls = 0, queueScaleCalls = 0 }
    local sys = { Minimap = 2, ChatFrame = 8, HudTooltip = 11, MicroMenu = 13, Bags = 14, DamageMeter = 23 }
    ctx.system = sys
    Enum = {
        EditModeSystem = sys,
        EditModePresetLayoutsMeta = { NumValues = opts.presets or 2 },
        EditModeMinimapSetting = { HeaderUnderneath = 0, RotateMinimap = 1, Size = 2 },
        EditModeChatFrameSetting = { WidthHundreds = 0, WidthTensAndOnes = 1, HeightHundreds = 2, HeightTensAndOnes = 3 },
        EditModeMicroMenuSetting = opts.microSetting,
        EditModeBagsSetting = { Orientation = 0, Direction = 1, Size = 2, BagSlotPadding = 3 },
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
    local list = {
        Frame(sys.Minimap, 1600, 850, 200, 200),
        Frame(sys.ChatFrame, 20, 20, 430, 180),
        Frame(sys.MicroMenu, 700, 10, 520, 50),
        Frame(sys.HudTooltip, 1250, 250, 300, 120),
        Frame(sys.Bags, 1450, 10, 350, 60),
        Frame(sys.DamageMeter, 1200, 200, 300, 220),
    }
    EditModeManagerFrame = { registeredSystemFrames = list }
    MinimapCluster, ChatFrame1, MicroMenuContainer = list[1], list[2], list[3]
    GameTooltipDefaultContainer, BagsBar, DamageMeter = list[4], list[5], list[6]
    if opts.forever then
        Untouchable(MicroMenuContainer, "MicroMenuContainer")
        MicroMenu = setmetatable({}, {
            __index = function(_, key) error("MicroMenu." .. tostring(key) .. " was read on WoW Forever", 2) end,
            __newindex = function(_, key) error("MicroMenu." .. tostring(key) .. " was written on WoW Forever", 2) end,
        })
    else
        MicroMenu = {
            SetNormalScale = function() ctx.normalScaleCalls = ctx.normalScaleCalls + 1 end,
            SetQueueStatusScale = function() ctx.queueScaleCalls = ctx.queueScaleCalls + 1 end,
        }
    end
    local micro = Entry(sys.MicroMenu, 5, 6)
    micro.settings[1] = { setting = 3, value = 10 }
    ctx.layoutInfo = {
        activeLayout = opts.activeLayout or ((opts.presets or 2) + 1),
        layouts = {{
            layoutName = "Client Test", layoutType = 1,
            systems = {
                Entry(sys.Minimap, 10, 20), Entry(sys.ChatFrame), micro,
                Entry(sys.HudTooltip), Entry(sys.Bags), Entry(sys.DamageMeter),
            },
        }},
    }
    C_EditMode = {
        GetLayouts = function() return ctx.layoutInfo end,
        SaveLayouts = function(info)
            assert(info == ctx.layoutInfo, "adapter saved a detached layout table")
            ctx.saves = ctx.saves + 1
        end,
        SetActiveLayout = function(index) ctx.layoutInfo.activeLayout = index end,
    }
    MSUF_EditModeAPI = {
        RegisterElement = function(owner, element)
            assert(owner == "MSUF.Blizzard", "wrong Blizzard Edit Mode owner")
            ctx.registered[element.id] = element
            return true
        end,
        UnregisterOwner = function() end,
        RegisterSessionListener = function(_, callback) ctx.listener = callback end,
        RefreshOwner = function() end,
    }
    EditModePresetLayoutManager = opts.presetManager
    MSUF_DB = { general = { blizzardEditModeIntegration = true, blizzardEditModeSnapshot = opts.snapshot } }
    local clientNamespace = { Client = opts.client }
    function clientNamespace.ExportPublic(name, value)
        _G[name] = value
        return value
    end
    ClearExports()
    assert(loadfile(modulePath))("MidnightSimpleUnitFrames", clientNamespace)
    return ctx
end

local DEPRECATED_EYE = { Orientation = 0, Order = 1, Size = 2, DeprecatedEyeSize = 3 }

-- WoW Forever renamed the Micro Menu Eye Size setting to DeprecatedEyeSize.
-- Without the key the stepper is not offered and a leftover row 3 never
-- rescales the queue eye, on any client.
do
    local ctx = LoadAdapter({ microSetting = DEPRECATED_EYE, snapshot = {} })
    assert(ControlIds(ctx.registered.micromenu) == "size,vertical,reverse",
        "Micro Menu offered Eye Size without the setting: " .. ControlIds(ctx.registered.micromenu))
    local sizeControl = ctx.registered.micromenu.extraControls[1]
    assert(sizeControl.id == "size" and sizeControl.set(100) == true, "Micro Menu size did not commit")
    assert(ctx.normalScaleCalls == 1, "Micro Menu size did not apply")
    assert(ctx.queueScaleCalls == 0, "a deprecated Eye Size row rescaled the queue eye")
end

-- WoW Forever: the protected MainActionBar hangs off MicroMenuContainer, so the
-- Micro Menu has no element, no frame access and no snapshot entry. Three
-- presets (Gamepad added) put saved layout 1 at active index 4.
do
    local client = { IsForever = true, IsGameRuleActive = function() return false end }
    local ctx = LoadAdapter({
        forever = true, client = client, presets = 3, activeLayout = 4,
        microSetting = DEPRECATED_EYE, snapshot = nil,
    })
    assert(ctx.registered.micromenu == nil, "WoW Forever registered a Micro Menu element")
    for _, id in ipairs({ "minimap", "chat", "tooltip", "bags", "damagemeter" }) do
        assert(type(ctx.registered[id]) == "table" and ctx.registered[id].isEnabled() == true,
            "WoW Forever Blizzard element missing or disabled: " .. id)
    end
    local minimapState = assert(ctx.registered.minimap.captureState(), "WoW Forever minimap capture failed")
    assert(minimapState.x == 10 and minimapState.y == 20,
        "WoW Forever active layout 4 did not resolve to saved layout 1 behind three presets")
    local snapshot = MSUF_DB.general.blizzardEditModeSnapshot
    assert(type(snapshot) == "table" and snapshot.micromenu == nil, "WoW Forever snapshot captured the Micro Menu")
    for _, key in ipairs({ "minimap", "chat", "tooltip", "bags", "damagemeter" }) do
        assert(type(snapshot[key]) == "table" and snapshot[key].forever == true,
            "WoW Forever snapshot entry lacks its stamp: " .. key)
    end
    assert(not tostring(MSUF_BlizzardEditMode_Debug()):find("micromenu", 1, true),
        "WoW Forever debug probe still reports the Micro Menu")

    -- A Midnight-captured snapshot (no stamp) never reaches the Forever HUD.
    MSUF_DB.general.blizzardEditModeSnapshot = {
        micromenu = { point = "BOTTOMRIGHT", relativeTo = "MicroButtonAndBagsBar",
            relativePoint = "BOTTOMRIGHT", x = 0, y = 0, settings = { [2] = 5 } },
        bags = { point = "TOPRIGHT", relativeTo = "MicroButtonAndBagsBar",
            relativePoint = "TOPRIGHT", x = 0, y = 0 },
        chat = { point = "BOTTOMLEFT", relativeTo = "UIParent", relativePoint = "BOTTOMLEFT", x = 35, y = 50 },
    }
    assert(MSUF_BlizzardEditMode_ApplyProfileSnapshot() == false,
        "a Midnight snapshot applied on WoW Forever")
    assert(ctx.saves == 0 and EditModeManagerFrame.panelShown == nil,
        "a Midnight snapshot saved or resynced the WoW Forever layout")

    -- Forever-stamped entries apply, a stamped Micro Menu entry still does not.
    local stamped = MSUF_DB.general.blizzardEditModeSnapshot
    stamped.minimap = { point = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER",
        x = 42, y = -31, forever = true }
    stamped.micromenu.forever = true
    assert(MSUF_BlizzardEditMode_ApplyProfileSnapshot() == true, "WoW Forever snapshot did not apply")
    local systems = ctx.layoutInfo.layouts[1].systems
    assert(systems[1].anchorInfo.offsetX == 42 and systems[1].anchorInfo.offsetY == -31,
        "WoW Forever snapshot did not update the minimap anchor")
    assert(systems[3].anchorInfo.point == "CENTER" and systems[3].anchorInfo.offsetX == 5
        and #systems[3].settings == 1, "WoW Forever profile apply changed the Micro Menu layout row")
    assert(systems[5].anchorInfo.relativeTo == "UIParent", "a Midnight bags anchor reached WoW Forever")
    assert(ctx.saves == 1 and EditModeManagerFrame.panelShown == 1,
        "WoW Forever snapshot did not save and resync exactly once")
    assert(type(MinimapCluster.point) == "table", "WoW Forever minimap anchor was not applied")
end

-- EditModeDisabled game rule: no enabled Blizzard element, no manager open, no
-- profile apply and no layout creation at session start.
do
    local ruleActive = true
    local client = {
        IsGameRuleActive = function(key) return key == "EditModeDisabled" and ruleActive or false end,
    }
    local ctx = LoadAdapter({
        client = client, activeLayout = 3,
        microSetting = { Orientation = 0, Order = 1, Size = 2, EyeSize = 3 },
        snapshot = { minimap = { point = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER", x = 1, y = 2 } },
        presetManager = { GetCopyOfPresetLayouts = function()
            return { { systems = { Entry(2) } }, { systems = { Entry(2) } } }
        end },
    })
    for id, element in pairs(ctx.registered) do
        assert(element.isEnabled() == false, "Blizzard element enabled under EditModeDisabled: " .. id)
    end
    assert(ctx.registered.minimap.openSettings() == false and EditModeManagerFrame.panelShown == nil,
        "Blizzard Edit Mode opened under EditModeDisabled")
    assert(MSUF_BlizzardEditMode_ApplyProfileSnapshot() == false and ctx.saves == 0
        and ctx.layoutInfo.layouts[1].systems[1].anchorInfo.offsetX == 10,
        "profile snapshot applied under EditModeDisabled")
    -- A preset is active at session start: the create-layout step must not run.
    ctx.layoutInfo.activeLayout = 1
    ctx.listener(true)
    assert(#ctx.layoutInfo.layouts == 1 and ctx.saves == 0,
        "session start created a Blizzard layout under EditModeDisabled")
    assert(GameTooltipDefaultContainer.showCount == nil,
        "Blizzard tooltip mover appeared under EditModeDisabled")
    ctx.listener(false)
    ruleActive = false
    assert(ctx.registered.minimap.isEnabled() == true, "Blizzard element stayed disabled without the rule")
    assert(ctx.registered.minimap.openSettings() == true and EditModeManagerFrame.panelShown == 1,
        "Blizzard Edit Mode did not open without the rule")
end

-- A layout created from a preset keeps the preset's interfaceStyle (Gamepad
-- preset on WoW Forever) and stays untagged when the preset has none.
do
    local ctx = LoadAdapter({
        presets = 3, activeLayout = 3, microSetting = DEPRECATED_EYE, snapshot = {},
        presetManager = { GetCopyOfPresetLayouts = function()
            return {
                { layoutName = "Modern", systems = { Entry(2) }, interfaceStyle = 0 },
                { layoutName = "Classic", systems = { Entry(2) }, interfaceStyle = 0 },
                { layoutName = "Gamepad", systems = { Entry(2, 7, 8) }, interfaceStyle = 1 },
            }
        end },
    })
    local ok, reason = MSUF_BlizzardEditMode_EnsureLayout()
    assert(ok == true and reason == "created", "Gamepad preset copy failed: " .. tostring(reason))
    local created = ctx.layoutInfo.layouts[#ctx.layoutInfo.layouts]
    assert(created.layoutName == "MSUF" and created.interfaceStyle == 1,
        "layout copied from the Gamepad preset lost its interfaceStyle")
    assert(created.systems[1].anchorInfo.offsetX == 7, "layout did not copy the active Gamepad preset")
    assert(ctx.layoutInfo.activeLayout == 3 + #ctx.layoutInfo.layouts,
        "new layout was not activated behind three presets")
end
do
    local ctx = LoadAdapter({
        activeLayout = 1, microSetting = { Orientation = 0, Order = 1, Size = 2, EyeSize = 3 }, snapshot = {},
        presetManager = { GetCopyOfPresetLayouts = function()
            return { { systems = { Entry(2, 3, 4) } }, { systems = { Entry(2) } } }
        end },
    })
    local ok, reason = MSUF_BlizzardEditMode_EnsureLayout()
    assert(ok == true and reason == "created", "Midnight preset copy failed: " .. tostring(reason))
    local created = ctx.layoutInfo.layouts[#ctx.layoutInfo.layouts]
    assert(created.interfaceStyle == nil and created.systems[1].anchorInfo.offsetX == 3,
        "layout copied from an untagged preset changed shape")
end

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

local editCore = Read("MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_Core.lua")
assert(editCore:find("local function HardHideEditModePreviews", 1, true)
    and editCore:find("MSUF_HideAllCastbarPreviews", 1, true)
    and editCore:find("HardHideEditModePreviews()", 1, true),
    "Classic Edit Mode exit no longer hard-hides transient castbar previews")
local auraEditMode = Read("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_EditMode.lua")
assert(auraEditMode:find("local function OnEditModeChanged(active)", 1, true)
    and auraEditMode:find("EM.HideAll()", 1, true)
    and auraEditMode:find("StopAuraDragCapture", 1, true),
    "Classic Edit Mode exit no longer clears Aura previews and drag capture")

print("Classic Edit Mode smoke passed")
