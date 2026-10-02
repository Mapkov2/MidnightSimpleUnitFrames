--- EditMode/MSUF_EditMode_HUD_Selection.lua - what the toolbar has selected
--- Labels and positions of the selected frame or component for the inspector
--- row, the cooldown anchor queries, and the Settings and Reset actions.
local _, MSUF = ...
-- Functions other modules publish are resolved where they are called
-- (most load after Edit Mode): MSUF.Require raises naming this file when
-- one is missing, and a hook installed on the global still applies.
local CALLER = "Shell/EditMode/MSUF_EditMode_HUD_Selection.lua"
local EM2 = _G.MSUF_EM2
if not EM2 then return end

local HUD = EM2.HUD
local Selection = {}
EM2.HUDSelection = Selection
local HelpText = EM2.HUDKit.HelpText
local floor = math.floor
local U = EM2.Util or {}
local ApplyAllSettingsSafe = U.ApplyAllSettingsSafe
local ApplySettingsForKeySafe = U.ApplySettingsForKeySafe

function HUD.AutomaticCooldownProvider()
    local getter = _G.MSUF_GetAutomaticCooldownAnchorProvider
    if type(getter) ~= "function" then return nil, nil end
    return getter()
end

--- Clients without a Cooldown Manager never get the toolbar toggle: it would
--- write a preference that no anchor can consume.
HUD.CooldownAnchorSupported = _G.MSUF_CooldownAnchorSupported

--- The Integrations module answers first; without it the client model does. The
--- C_CooldownViewer namespace is never the signal: the shared engine exposes it
--- on every client, while only the Mainline family ships Blizzard's Cooldown
--- Manager (Client.HostsCooldownManager).
function HUD.CooldownAnchorEnabled(general)
    local getter = _G.MSUF_IsCooldownAnchorEnabled
    if type(getter) == "function" then return getter(general) == true end
    return MSUF.Client ~= nil and MSUF.Client.HostsCooldownManager == true
        and general and general.anchorToCooldown == true or false
end

local UNIT_KEYS = { player = true, target = true, focus = true, focustarget = true, targettarget = true, pet = true, pettarget = true, boss = true, arena = true }

local GROUP_KEY_TO_KIND = {
    gf_party = "party",
    gf_raid = "raid",
    gf_mythicraid = "mythicraid",
    gf_priority = "priority",
}

local LABEL_BY_KEY = {
    player = "Player",
    target = "Target",
    focus = "Focus",
    focustarget = "Focus Target",
    targettarget = "ToT",
    pet = "Pet",
    pettarget = "Pet Target",
    boss = "Boss",
    arena = "Arena",
    gf_party = "Party Frames",
    gf_raid = "Raid Frames",
    gf_mythicraid = "Mythic Raid Frames",
    gf_priority = "Priority Frames",
}

local COMPONENT_LABEL = {
    frame = "Frame",
    layout = "Layout",
    bounds = "Frame",
    size = "Size",
    name = "Name",
    hp = "Health Text",
    power = "Power Text",
    text = "Text",
    auras = "Auras",
    castbar = "Castbar",
    cast = "Castbar",
    bars = "Bars",
    status = "Status & Indicators",
    indicators = "Status & Indicators",
    sicons = "Status Icons",
}

local function CurrentSelectionKey()
    local key = (EM2.State and EM2.State.GetUnitKey and EM2.State.GetUnitKey()) or _G.MSUF_CurrentEditUnitKey
    if not key and EM2.Focus and EM2.Focus.GetSelection then
        key = EM2.Focus.GetSelection()
    end
    return key
end

local function CurrentFocusSelection()
    local auraPopup = EM2.AuraPopup
    if auraPopup and type(auraPopup.IsOpen) == "function" and auraPopup.IsOpen() then
        local unit = rawget(_G, "MSUF_EM2_ActiveAuraUnit")
        if type(unit) == "string" then
            local key = (unit:match("^boss%d+$") and "boss") or (unit:match("^arena%d+$") and "arena") or unit
            if UNIT_KEYS[key] then return key, "auras", nil end
        end
    end
    if EM2.Focus and EM2.Focus.GetSelection then
        local key, component, slot = EM2.Focus.GetSelection()
        if key then return key, component, slot end
    end
    return CurrentSelectionKey(), nil, nil
end

local function SelectionDetail(component, slot)
    local label = component and (COMPONENT_LABEL[component] or component) or nil
    if label and slot then return label .. " " .. tostring(slot) end
    return label
end

local function AuraSelectionFrame(key, component)
    if component ~= "auras" then return nil end
    local unit = rawget(_G, "MSUF_EM2_ActiveAuraUnit")
    local kind = rawget(_G, "MSUF_EM2_ActiveAuraGroup")
    if type(unit) ~= "string" or type(kind) ~= "string" then return nil end
    local selectionUnit = (unit:match("^boss%d+$") and "boss") or (unit:match("^arena%d+$") and "arena") or unit
    if selectionUnit ~= key then return nil end
    local a3 = MSUF and MSUF.MSUF_Auras3
    local edit = a3 and a3.EditMode
    local groups = edit and edit.groups
    local group = groups and groups[unit] and groups[unit][kind]
    return group and (group.Body or group) or nil
end

local function SelectionValues(key, component, slot)
    if not key then return HelpText("No selection") end
    local cfg = EM2.Registry and EM2.Registry.Get and EM2.Registry.Get(key) or nil
    if cfg and cfg.externalPublicElement == true then
        local external = EM2.ExternalElements
        if external and type(external.GetInspectorValues) == "function" then
            return external.GetInspectorValues(key)
        end
        return HelpText(cfg.label or key)
    end
    local db = _G.MSUF_DB
    local conf
    local groupKind = GROUP_KEY_TO_KIND[key]
    if groupKind then
        conf = db and db[key]
    elseif UNIT_KEYS[key] then
        conf = db and db[key]
    end

    local label = LABEL_BY_KEY[key] and HelpText(LABEL_BY_KEY[key])
        or (cfg and U.ElementLabel and U.ElementLabel(key, cfg)) or HelpText(key)
    local detail = SelectionDetail(component, slot)
    if detail then label = label .. " / " .. HelpText(detail) end
    local frame = AuraSelectionFrame(key, component)
    if not frame and cfg and type(cfg.getFrame) == "function" then
        local resolved = cfg.getFrame()
        do
frame = resolved
end
    end
    if frame and type(U.FramePositionValues) == "function" then
        local x, y, width, height = U.FramePositionValues(frame)
        if x ~= nil then return label, x, y, width, height end
    end
    if not conf then return label end
    local x = floor((tonumber(conf.offsetX) or 0) + 0.5)
    local y = floor((tonumber(conf.offsetY) or 0) + 0.5)
    local w = tonumber(conf.width)
    local h = tonumber(conf.height)
    return label, x, y, w and floor(w + 0.5), h and floor(h + 0.5)
end

local function FormatSelectionSummary(label, x, y, w, h)
    if x == nil or y == nil then return label end
    if w and h then
        return string.format("%s   X %d   Y %d   W %d   H %d", label, x, y, w, h)
    end
    return string.format("%s   X %d   Y %d", label, x, y)
end

local function DefaultHintText(hasSelection)
    if EM2.Popups and EM2.Popups.IsAnyOpen and EM2.Popups.IsAnyOpen() then
        return HelpText("EM_HINT_POPUP")
    end
    if hasSelection then
        return HelpText("EM_HINT_SELECTED")
    end
    return HelpText("EM_HINT_NONE")
end

local function BlockHUDConfigLocked()
    return MSUF.Require("MSUF_BlockConfigCombatLocked", CALLER)() and true or false
end

function HUD.OpenSelectedSettings()
    if BlockHUDConfigLocked() then return end
    local key, component, slot = CurrentFocusSelection()
    key = key or CurrentSelectionKey()
    if not key then
        HUD.SetStatus(HelpText("EM_SELECT_FIRST"), "warn")
        return
    end
    if EM2.Focus and EM2.Focus.SetSelection then
        EM2.Focus.SetSelection(key, component, slot, { source = "hud-settings", openSettings = true })
    end
    local opener = (EM2.Focus and EM2.Focus.OpenFullSettings) or _G.MSUF_EM2_OpenFocusSettings
    if type(opener) == "function" and opener() then
        HUD.SetStatus(HelpText("Opened settings"), "ok")
    else
        HUD.SetStatus(HelpText("Settings unavailable"), "warn")
    end
end

function HUD.ResetCurrentPosition()
    if BlockHUDConfigLocked() then return end

    local key = CurrentSelectionKey()
    if not key then HUD.SetStatus(HelpText("EM_SELECT_FIRST"), "warn"); return end
    local cfg = EM2.Registry and EM2.Registry.Get and EM2.Registry.Get(key) or nil
    if cfg and cfg.externalPublicElement == true then
        local external = EM2.ExternalElements
        if external and type(external.Reset) == "function" and external.Reset(key) then
            HUD.SetStatus(string.format(HelpText("Reset %s"), HelpText(cfg.label or key)), "ok")
        else
            HUD.SetStatus(HelpText("Reset unavailable"), "warn")
        end
        HUD.RefreshControls()
        return
    end
    local groupKind = GROUP_KEY_TO_KIND[key]
    if groupKind then
        MSUF.Require("MSUF_GF_EM2_ResetPosition", CALLER)(groupKind)
        if EM2.Focus and EM2.Focus.NotifyPositionChanged then EM2.Focus.NotifyPositionChanged(key, true) end
        if EM2.Focus and EM2.Focus.Pulse then EM2.Focus.Pulse(key, "layout", nil, { source = "hud-reset", duration = 0.32 }) end
        HUD.SetStatus(string.format(HelpText("Reset %s"), HelpText(LABEL_BY_KEY[key] or key)), "ok")
        HUD.RefreshControls()
        return
    end

    if not UNIT_KEYS[key] then HUD.SetStatus(HelpText("Reset unavailable"), "warn"); return end
    local db = _G.MSUF_DB
    local conf = db and db[key]
    if not conf then return end
    _G.MSUF_EM_UndoBeforeChange("unit", key)
    local defaultX, defaultY = MSUF.Require("MSUF_GetDefaultUnitOffsets", CALLER)(key)
    conf.offsetX = defaultX
    conf.offsetY = defaultY
    if not ApplySettingsForKeySafe(key) then
        ApplyAllSettingsSafe()
    end
    MSUF.Require("MSUF_ApplyPowerBarEmbedLayout_ForUnitKey", CALLER)(key, true)
    if EM2.UnitPopup and EM2.UnitPopup.Sync then EM2.UnitPopup.Sync() end
    if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
    if EM2.Focus and EM2.Focus.NotifyPositionChanged then EM2.Focus.NotifyPositionChanged(key, true) end
    if EM2.Focus and EM2.Focus.Pulse then EM2.Focus.Pulse(key, "frame", nil, { source = "hud-reset", duration = 0.32 }) end
    -- The unit preview belongs to the load-on-demand menu.
    local refreshPreview = MSUF.Optional("MSUF_UFPreview_RequestRefresh")
    if refreshPreview then refreshPreview("EM2_HUD_RESET_POSITION") end
    HUD.SetStatus(string.format(HelpText("Reset %s"), HelpText(LABEL_BY_KEY[key] or key)), "ok")
    HUD.RefreshControls()
end

--- The dock, the frame picker and the toolbar read these.
Selection.UNIT_KEYS, Selection.GROUP_KEY_TO_KIND, Selection.LABEL_BY_KEY = UNIT_KEYS, GROUP_KEY_TO_KIND, LABEL_BY_KEY
Selection.CurrentSelectionKey, Selection.CurrentFocusSelection = CurrentSelectionKey, CurrentFocusSelection
Selection.SelectionValues, Selection.FormatSelectionSummary = SelectionValues, FormatSelectionSummary
Selection.DefaultHintText, Selection.BlockHUDConfigLocked = DefaultHintText, BlockHUDConfigLocked
