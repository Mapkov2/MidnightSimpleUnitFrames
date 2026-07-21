local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

-- TEXT_QUICK_SETTINGS
-- One cold, reusable popup for the RGB dots inside Text cards. Everything is
-- resolved when the user opens it; there is no event, ticker, or gameplay path.
local W = M.Widgets
local T = M.Theme
local Tr = M.Tr or function(value) return value end
local floor = math.floor
local max = math.max
local min = math.min

local textQuickPopup
local activeAnchor
local activeOptions
local activeSettings
local cachedFontValues

local OUTLINE_VALUES = {
    { value = "OUTLINE", text = "Outline" },
    { value = "THICKOUTLINE", text = "Thick" },
    { value = "NONE", text = "None" },
}
local RENDER_VALUES = {
    { value = "SMOOTH", text = "Smooth" },
    { value = "SHARP", text = "Sharp" },
}
local SHADOW_VALUES = {
    { value = "ON", text = "On" },
    { value = "OFF", text = "Off" },
}
local TEXT_ALPHA_VALUES = {
    { value = 1, text = "100%" },
    { value = 0.85, text = "85%" },
    { value = 0.70, text = "70%" },
}
local SHADOW_DISTANCE_VALUES = {
    { value = 1, text = "1 px" },
    { value = 2, text = "2 px" },
}
local BASELINE_VALUES = {}
for value = -4, 4 do
    BASELINE_VALUES[#BASELINE_VALUES + 1] = {
        value = value,
        text = value > 0 and ("+" .. tostring(value) .. " px") or (tostring(value) .. " px"),
    }
end
local SHADOW_ALPHA_VALUES = {}
for step = 4, 20 do
    local value = step / 20
    SHADOW_ALPHA_VALUES[#SHADOW_ALPHA_VALUES + 1] = {
        value = value,
        text = tostring(floor(value * 100 + 0.5)) .. "%",
    }
end
local GROUP_PREVIEW_CLASS = { gf_party = "DEATHKNIGHT", gf_raid = "HUNTER" }
local GROUP_PREVIEW_POWER = { gf_party = "RUNIC_POWER", gf_raid = "FOCUS" }
local SCOPE_LABELS = {
    shared = "Shared", player = "Player", target = "Target", targettarget = "Target of Target",
    focustarget = "Focus Target", focus = "Focus", pet = "Pet", boss = "Boss",
    gf_party = "Party", gf_raid = "Raid",
}

local function Resolve(value, fallback)
    if type(value) == "function" then value = value() end
    if value == nil or value == "" then return fallback end
    return value
end

local function GlobalPage()
    return M.GlobalPage or {}
end

local function CurrentScope()
    local settings = activeSettings or {}
    local scope = Resolve(settings.scope or settings.fontScope, "shared")
    local GP = GlobalPage()
    if type(GP.NormalizeScopeKey) == "function" then scope = GP.NormalizeScopeKey(scope) end
    return scope or "shared"
end

-- Some specialized text reuses the shared font renderer while its color mode
-- belongs to another frame (for example the mirrored Player HP text). Keep
-- those two persisted scopes explicit instead of pretending one controls both.
local function CurrentModeScope()
    local settings = activeSettings or {}
    local scope = Resolve(settings.modeScope or settings.colorScope, CurrentScope())
    local GP = GlobalPage()
    if type(GP.NormalizeScopeKey) == "function" then scope = GP.NormalizeScopeKey(scope) end
    return scope or CurrentScope()
end

local function IsGroupSettings(settings, scope)
    if settings and settings.group == true then return true end
    local GP = GlobalPage()
    return type(GP.IsGFScope) == "function" and GP.IsGFScope(scope) == true
end

local function CurrentKind()
    local kind = tostring(Resolve(activeSettings and (activeSettings.kind or activeSettings.textKind), "name")):lower()
    return kind ~= "" and kind or "name"
end

local function ExternalColorReferences()
    local settings = activeSettings or {}
    if settings.colorReferences == nil then return nil end
    return Resolve(settings.colorReferences, nil)
end

local function CurrentCapabilities()
    local capabilities = Resolve(activeSettings and activeSettings.capabilities, nil)
    return type(capabilities) == "table" and capabilities or nil
end

local function HasCapability(key, defaultValue)
    local capabilities = CurrentCapabilities()
    if capabilities and capabilities[key] ~= nil then return capabilities[key] ~= false end
    return defaultValue ~= false
end

local function HasCustomColorMode()
    local settings = activeSettings or {}
    return settings.colorModeValues ~= nil
        and type(settings.getColorMode) == "function"
        and type(settings.setColorMode) == "function"
end

local function HasNativeColorMode()
    if ExternalColorReferences() ~= nil then return false end
    local kind = CurrentKind()
    return kind == "name" or kind == "hp" or kind == "power"
end

local function PreviewUnitData(settings)
    local unit = tostring(Resolve(settings and settings.unit, "player"))
    local model = MSUF and MSUF.UFPreview and MSUF.UFPreview.Model
    local data = model and model.UNIT_DATA
    return unit, (data and (data[unit] or data.player))
        or { class = "WARRIOR", className = "Warrior", powerToken = "MANA", isPlayer = unit == "player" }
end

local function CurrentModeKind()
    local settings, scope, kind = activeSettings or {}, CurrentModeScope(), CurrentKind()
    if kind == "hp" or kind == "power" then return kind end
    if IsGroupSettings(settings, scope) then return "group_name" end
    local _, data = PreviewUnitData(settings)
    return data.isPlayer and "player_name" or "npc_name"
end

local function CurrentColorMode()
    local settings = activeSettings or {}
    if HasCustomColorMode() then return Resolve(settings.getColorMode, "DEFAULT") end
    local GP = GlobalPage()
    if type(GP.FontTextColorModeGetFor) ~= "function" then return "DEFAULT" end
    return GP.FontTextColorModeGetFor(CurrentModeScope(), CurrentModeKind()) or "DEFAULT"
end

local function ColorModeValues()
    local settings = activeSettings or {}
    if HasCustomColorMode() then
        local values = Resolve(settings.colorModeValues, {})
        if type(values) == "table" and #values > 0 then return values end
    end
    local modeKind = CurrentModeKind()
    local GP = GlobalPage()
    if type(GP.FontTextColorValuesFor) == "function" then
        local values = GP.FontTextColorValuesFor(CurrentModeScope(), modeKind)
        if type(values) == "table" and #values > 0 then return values end
    end
    if modeKind == "group_name" then
        return {
            { value = "DEFAULT", text = "Default font color" },
            { value = "CLASS", text = "Class color" },
            { value = "CUSTOM", text = "Custom color" },
        }
    elseif modeKind == "npc_name" then
        return {
            { value = "DEFAULT", text = "Default font color" },
            { value = "NPC", text = "NPC / reaction color" },
            { value = "CLASS", text = "Class color" },
        }
    elseif modeKind == "hp" then
        return {
            { value = "DEFAULT", text = "Default font color" },
            { value = "CLASS", text = "Class color" },
            { value = "HEALTH", text = "Health gradient" },
        }
    elseif modeKind == "power" then
        return {
            { value = "DEFAULT", text = "Default font color" },
            { value = "RESOURCE", text = "By power type" },
        }
    end
    return {
        { value = "DEFAULT", text = "Default font color" },
        { value = "CLASS", text = "Class color" },
    }
end

local function Blocked()
    return M.BlockCombatAction and M.BlockCombatAction()
end

local function RunChange(label, source, fn)
    if Blocked() or type(fn) ~= "function" then return false end
    if type(M.RunWithHistory) == "function" then
        M.RunWithHistory(label, source, fn)
    else
        fn()
    end
    return true
end

local function ApplyTextColors()
    local api = (MSUF and MSUF._colorsAPI) or {}
    if type(api.PushVisualUpdates) == "function" then
        api.PushVisualUpdates()
    elseif type(M.RequestGeneralApply) == "function" then
        M.RequestGeneralApply("MSUF2_TEXT_QUICK_COLOR", { colors = true, preview = true, applyAll = false })
    end
end

local function CopyColor(value)
    if type(value) ~= "table" then return value end
    return { r = value.r, g = value.g, b = value.b, value[1], value[2], value[3] }
end

local function CaptureDBColorEntry(tableKey, key)
    local db = _G.MSUF_DB
    local colors = db and db[tableKey]
    return {
        hadTable = type(colors) == "table",
        hadValue = type(colors) == "table" and colors[key] ~= nil,
        value = type(colors) == "table" and CopyColor(colors[key]) or nil,
    }
end

local function RestoreDBColorEntry(tableKey, key, state)
    local db = _G.MSUF_DB
    if not (db and state) then return end
    if state.hadTable then
        db[tableKey] = type(db[tableKey]) == "table" and db[tableKey] or {}
        db[tableKey][key] = state.hadValue and CopyColor(state.value) or nil
    elseif type(db[tableKey]) == "table" then
        db[tableKey][key] = nil
        if next(db[tableKey]) == nil then db[tableKey] = nil end
    end
    ApplyTextColors()
end

local function GlobalFontTarget()
    local function GetRGB()
        local configured = (MSUF and MSUF.MSUF_GetConfiguredFontColor) or _G.MSUF_GetConfiguredFontColor
        if type(configured) == "function" then
            local r, g, b = configured()
            if type(r) == "number" and type(g) == "number" and type(b) == "number" then return r, g, b end
        end
        local api = (MSUF and MSUF._colorsAPI) or {}
        if type(api.GetGlobalFontColor) == "function" then return api.GetGlobalFontColor() end
        return 1, 1, 1
    end
    local function SetRGB(r, g, b)
        local api = (MSUF and MSUF._colorsAPI) or {}
        if type(api.SetGlobalFontColor) == "function" then api.SetGlobalFontColor(r, g, b); return end
        local general = GlobalPage().G and GlobalPage().G()
        if not general then return end
        general.fontColorCustomR, general.fontColorCustomG, general.fontColorCustomB = r, g, b
        general.useCustomFontColor = true
        ApplyTextColors()
    end
    return {
        label = "Global font color", getRGB = GetRGB, setRGB = SetRGB,
        captureState = function()
            local general = GlobalPage().G and GlobalPage().G() or {}
            return {
                useCustom = general.useCustomFontColor,
                r = general.fontColorCustomR, g = general.fontColorCustomG, b = general.fontColorCustomB,
            }
        end,
        restoreState = function(state)
            local general = GlobalPage().G and GlobalPage().G()
            if not (general and state) then return end
            general.useCustomFontColor = state.useCustom
            general.fontColorCustomR, general.fontColorCustomG, general.fontColorCustomB = state.r, state.g, state.b
            ApplyTextColors()
        end,
    }
end

local function ClassColorTarget(token, label)
    token = token or "WARRIOR"
    return {
        label = label or (token .. " class color"),
        getRGB = function()
            local api = (MSUF and MSUF._colorsAPI) or {}
            if type(api.GetClassColor) == "function" then return api.GetClassColor(token) end
            local color = _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[token]
            return color and color.r or 1, color and color.g or 1, color and color.b or 1
        end,
        setRGB = function(r, g, b)
            local api = (MSUF and MSUF._colorsAPI) or {}
            if type(api.SetClassColor) == "function" then api.SetClassColor(token, r, g, b); return end
            local db = _G.MSUF_DB
            if not db then return end
            db.classColors = type(db.classColors) == "table" and db.classColors or {}
            db.classColors[token] = { r = r, g = g, b = b }
            ApplyTextColors()
        end,
        captureState = function() return CaptureDBColorEntry("classColors", token) end,
        restoreState = function(state) RestoreDBColorEntry("classColors", token, state) end,
    }
end

local function NPCColorTarget(kind)
    kind = kind or "enemy"
    return {
        label = tostring(kind) .. " NPC color",
        getRGB = function()
            local api = (MSUF and MSUF._colorsAPI) or {}
            if type(api.GetNPCColor) == "function" then return api.GetNPCColor(kind) end
            return 0.85, 0.10, 0.10
        end,
        setRGB = function(r, g, b)
            local api = (MSUF and MSUF._colorsAPI) or {}
            if type(api.SetNPCColor) == "function" then api.SetNPCColor(kind, r, g, b); return end
            local db = _G.MSUF_DB
            if not db then return end
            db.npcColors = type(db.npcColors) == "table" and db.npcColors or {}
            db.npcColors[kind] = { r = r, g = g, b = b }
            ApplyTextColors()
        end,
        captureState = function() return CaptureDBColorEntry("npcColors", kind) end,
        restoreState = function(state) RestoreDBColorEntry("npcColors", kind, state) end,
    }
end

local function GeneralRGBTarget(label, prefix, defaultR, defaultG, defaultB)
    local keys = { prefix .. "R", prefix .. "G", prefix .. "B" }
    return {
        label = label,
        getRGB = function()
            local general = GlobalPage().G and GlobalPage().G() or {}
            return tonumber(general[keys[1]]) or defaultR,
                tonumber(general[keys[2]]) or defaultG,
                tonumber(general[keys[3]]) or defaultB
        end,
        setRGB = function(r, g, b)
            local general = GlobalPage().G and GlobalPage().G()
            if not general then return end
            general[keys[1]], general[keys[2]], general[keys[3]] = r, g, b
            ApplyTextColors()
        end,
        captureState = function()
            local general = GlobalPage().G and GlobalPage().G() or {}
            return { general[keys[1]], general[keys[2]], general[keys[3]] }
        end,
        restoreState = function(state)
            local general = GlobalPage().G and GlobalPage().G()
            if not (general and state) then return end
            general[keys[1]], general[keys[2]], general[keys[3]] = state[1], state[2], state[3]
            ApplyTextColors()
        end,
    }
end

local function PowerColorTarget(token)
    token = token or "MANA"
    return {
        label = tostring(token):gsub("_", " ") .. " power color",
        getRGB = function()
            local general = GlobalPage().G and GlobalPage().G() or {}
            local color = type(general.powerColorOverrides) == "table" and general.powerColorOverrides[token]
            if type(color) ~= "table" then color = _G.PowerBarColor and _G.PowerBarColor[token] end
            return tonumber(color and (color.r or color[1])) or 0.8,
                tonumber(color and (color.g or color[2])) or 0.8,
                tonumber(color and (color.b or color[3])) or 0.8
        end,
        setRGB = function(r, g, b)
            local general = GlobalPage().G and GlobalPage().G()
            if not general then return end
            general.powerColorOverrides = type(general.powerColorOverrides) == "table" and general.powerColorOverrides or {}
            general.powerColorOverrides[token] = { r, g, b }
            ApplyTextColors()
        end,
        captureState = function()
            local general = GlobalPage().G and GlobalPage().G() or {}
            local overrides = general.powerColorOverrides
            return {
                hadTable = type(overrides) == "table",
                hadValue = type(overrides) == "table" and overrides[token] ~= nil,
                value = type(overrides) == "table" and CopyColor(overrides[token]) or nil,
            }
        end,
        restoreState = function(state)
            local general = GlobalPage().G and GlobalPage().G()
            if not (general and state) then return end
            if state.hadTable then
                general.powerColorOverrides = type(general.powerColorOverrides) == "table" and general.powerColorOverrides or {}
                general.powerColorOverrides[token] = state.hadValue and CopyColor(state.value) or nil
            elseif type(general.powerColorOverrides) == "table" then
                general.powerColorOverrides[token] = nil
                if next(general.powerColorOverrides) == nil then general.powerColorOverrides = nil end
            end
            ApplyTextColors()
        end,
    }
end

local function CaptureScopeFields(scope, fields)
    local GP, state = GlobalPage(), {}
    local db = GP.DB and GP.DB() or _G.MSUF_DB or {}
    local keys = type(GP.ScopeDBKeys) == "function" and GP.ScopeDBKeys(scope) or nil
    for i = 1, #(keys or {}) do
        local entryKey, entry = keys[i], db[keys[i]]
        local saved = { key = entryKey, hadEntry = type(entry) == "table", fields = {} }
        for j = 1, #fields do
            local field = fields[j]
            saved.fields[field] = { had = type(entry) == "table" and entry[field] ~= nil, value = type(entry) == "table" and entry[field] or nil }
        end
        state[#state + 1] = saved
    end
    return state
end

local function RestoreScopeFields(scope, state)
    local GP = GlobalPage()
    local db = GP.DB and GP.DB() or _G.MSUF_DB
    if not (db and type(state) == "table") then return end
    for i = 1, #state do
        local saved = state[i]
        local entry = db[saved.key]
        if type(entry) ~= "table" then entry = {}; db[saved.key] = entry end
        for field, value in pairs(saved.fields or {}) do entry[field] = value.had and value.value or nil end
        if not saved.hadEntry and next(entry) == nil then db[saved.key] = nil end
    end
    if type(GP.ApplyFontsFor) == "function" then
        GP.ApplyFontsFor(scope, "MSUF2_TEXT_QUICK_COLOR_RESTORE")
    else
        ApplyTextColors()
    end
end

local function ScopedRGBTarget(scope, label, rKey, gKey, bKey, opts)
    opts = opts or {}
    local GP = GlobalPage()
    local fields = { "fontOverride", rKey, gKey, bKey }
    if opts.modeKey then fields[#fields + 1] = opts.modeKey end
    if opts.globalFlagKey then fields[#fields + 1] = opts.globalFlagKey end
    return {
        label = label,
        getRGB = function()
            return tonumber(GP.FontScopeGetFor(scope, rKey, opts.defaultR or 1)) or 1,
                tonumber(GP.FontScopeGetFor(scope, gKey, opts.defaultG or 1)) or 1,
                tonumber(GP.FontScopeGetFor(scope, bKey, opts.defaultB or 1)) or 1
        end,
        setRGB = function(r, g, b)
            GP.FontScopeSetFor(scope, rKey, r, nil, nil, true)
            GP.FontScopeSetFor(scope, gKey, g, nil, nil, true)
            GP.FontScopeSetFor(scope, bKey, b, nil, nil, true)
            if opts.modeKey then GP.FontScopeSetFor(scope, opts.modeKey, opts.modeValue, nil, nil, true) end
            if opts.globalFlagKey then GP.FontScopeSetFor(scope, opts.globalFlagKey, false, nil, nil, true) end
            if type(GP.ApplyFontsFor) == "function" then
                GP.ApplyFontsFor(scope, "MSUF2_TEXT_QUICK_SCOPED_COLOR")
            else
                ApplyTextColors()
            end
        end,
        captureState = function() return CaptureScopeFields(scope, fields) end,
        restoreState = function(state) RestoreScopeFields(scope, state) end,
    }
end

local function DefaultFontTarget(scope, group)
    local GP = GlobalPage()
    if group and type(GP.FontOverrideGetFor) == "function" and GP.FontOverrideGetFor(scope)
        and GP.FontScopeGetFor(scope, "useGlobalFontColor", true) == false
    then
        return ScopedRGBTarget(scope, "Group font color", "fontR", "fontG", "fontB", {
            globalFlagKey = "useGlobalFontColor",
        })
    end
    return GlobalFontTarget()
end

local function ResolveNPCPreviewKind(unit, data)
    local model = MSUF and MSUF.UFPreview and MSUF.UFPreview.Model
    local kind = data and (data.npcKind or data.reactionKind) or "enemy"
    if model and type(model.PreviewNPCKind) == "function" then
        local cache = type(model.SettingsCache) == "function" and model.SettingsCache() or nil
        kind = model.PreviewNPCKind(unit, data, cache, true)
    end
    return kind or "enemy"
end

local function GroupClassTargets()
    local token = GROUP_PREVIEW_CLASS[CurrentScope()] or "HUNTER"
    return { ClassColorTarget(token, token .. " group preview class") }
end

local function GroupPowerTargets()
    local token = GROUP_PREVIEW_POWER[CurrentScope()] or "FOCUS"
    return { PowerColorTarget(token) }
end

local function ResolveTextColorTargets()
    if not HasCapability("colors", true) then return {} end
    local settings, scope, kind = activeSettings or {}, CurrentModeScope(), CurrentKind()
    local externalReferences = ExternalColorReferences()
    if externalReferences ~= nil then
        local resolver = M.ResolveContextColorReferences
        if type(resolver) ~= "function" then return {} end
        local context = Resolve(settings.colorContext, {})
        return resolver(externalReferences, type(context) == "table" and context or {})
    end
    local group = IsGroupSettings(settings, scope)
    local mode = CurrentColorMode()
    if kind == "name" then
        if group then
            if mode == "CUSTOM" then
                return { ScopedRGBTarget(scope, "Custom group name", "nameColorR", "nameColorG", "nameColorB", {
                    modeKey = "nameColorMode", modeValue = "CUSTOM",
                }) }
            end
            if mode == "CLASS" then return GroupClassTargets() end
            return { DefaultFontTarget(scope, true) }
        end
        local unit, data = PreviewUnitData(settings)
        if mode == "CLASS" then
            return { ClassColorTarget(data.class, (data.className or data.class or "Unit") .. " class color") }
        elseif mode == "NPC" then
            return { NPCColorTarget(ResolveNPCPreviewKind(unit, data)) }
        end
        return { GlobalFontTarget() }
    elseif kind == "hp" then
        if mode == "HEALTH" then
            return {
                GeneralRGBTarget("Low health", "healthGradientLow", 1, 0, 0),
                GeneralRGBTarget("Mid health", "healthGradientMid", 1, 1, 0),
                GeneralRGBTarget("High health", "healthGradientHigh", 0, 1, 0),
            }
        elseif mode == "CLASS" then
            if group then return GroupClassTargets() end
            local _, data = PreviewUnitData(settings)
            return { ClassColorTarget(data.class, (data.className or data.class or "Unit") .. " class color") }
        end
        return { DefaultFontTarget(scope, group) }
    end
    if mode == "RESOURCE" then
        if group then return GroupPowerTargets() end
        local _, data = PreviewUnitData(settings)
        return { PowerColorTarget(data.powerToken or "MANA") }
    end
    return { DefaultFontTarget(scope, group) }
end

local function SetShown(control, shown)
    if control and control.SetShown then control:SetShown(shown) end
    if control and control._msuf2Title and control._msuf2Title.SetShown then control._msuf2Title:SetShown(shown) end
end

local function SetEnabled(control, enabled)
    if type(W.SetControlEnabled) == "function" then W.SetControlEnabled(control, enabled); return end
    if not control then return end
    if enabled and control.Enable then control:Enable() elseif not enabled and control.Disable then control:Disable() end
end

local function BindDropdown(control, label, source, getter, setter)
    control._msuf2SkipHistoryCheckpoint = true
    control:SetOnValueChanged(function(value)
        local before = getter()
        if before == value then return end
        if RunChange(label, source, function() setter(value) end) and textQuickPopup and textQuickPopup.Refresh then textQuickPopup:Refresh() end
    end)
end

local function BindSegment(control, label, source, getter, setter)
    control._msuf2SkipHistoryCheckpoint = true
    for i = 1, #(control.buttons or {}) do
        local button = control.buttons[i]
        button._msuf2SkipHistoryCheckpoint = true
        button:SetScript("OnClick", function()
            local value = button._msuf2Value
            if getter() == value then return end
            if RunChange(label, source, function() setter(value) end) and textQuickPopup and textQuickPopup.Refresh then textQuickPopup:Refresh() end
        end)
    end
end

local function NormalizeTextAlpha(value)
    value = tonumber(value) or 1
    if value <= 0.75 then return 0.70 end
    if value <= 0.925 then return 0.85 end
    return 1
end

local function NormalizeBaseline(value)
    return max(-4, min(4, floor((tonumber(value) or 0) + 0.5)))
end

local function ClearLegacyShadowStrength(scope)
    local GP = GlobalPage()
    if scope == "shared" then
        local general = GP.G and GP.G()
        if general then general.fontShadowStrength = nil end
        return
    end
    local db = GP.DB and GP.DB()
    local keys = type(GP.ScopeDBKeys) == "function" and GP.ScopeDBKeys(scope) or nil
    for i = 1, #(keys or {}) do
        local entry = db and db[keys[i]]
        if entry then entry.fontShadowStrength = nil end
    end
end

local function ScopeStyleGet(key, default)
    local GP = GlobalPage()
    return GP.FontScopeGetFor(CurrentScope(), key, default)
end

local function ScopeStyleSet(key, value, reason)
    local GP, scope = GlobalPage(), CurrentScope()
    GP.FontScopeSetFor(scope, key, value, reason)
end

local function ColorModeVisible()
    return HasCapability("colorMode", true)
        and (HasCustomColorMode() or HasNativeColorMode())
        and not (IsGroupSettings(activeSettings, CurrentModeScope()) and CurrentKind() == "power")
end

local function RefreshPopup()
    if textQuickPopup and textQuickPopup.Refresh then textQuickPopup:Refresh() end
end

local function EnsurePopup()
    if textQuickPopup then return textQuickPopup end
    if not (W and T and type(M.CreateMenuPopupPanel) == "function") then return nil end
    local parent = _G.UIParent or M.frame
    if not parent then return nil end

    local popup = M.CreateMenuPopupPanel(parent)
    textQuickPopup = popup
    popup:SetSize(430, 466)
    popup:SetClampedToScreen(true)
    popup:EnableKeyboard(true)
    if popup.SetPropagateKeyboardInput then popup:SetPropagateKeyboardInput(true) end
    popup._msuf2Width = 430
    popup._msuf2ContentX = 16
    popup._msuf2CursorY = -96

    popup.title = T.Font(popup, "GameFontNormal", "", T.colors.accent)
    popup.title:SetPoint("TOPLEFT", popup, "TOPLEFT", 16, -13)
    popup.title:SetWidth(360)
    popup.title:SetJustifyH("LEFT")
    popup.subtitle = W.Text(popup, "", 16, -38, 396, T.colors.muted)

    popup.close = T.Button(popup, "x", 20, 20, { noSearch = true })
    popup.close._msuf2SkipHistoryCheckpoint = true
    popup.close:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -12, -9)
    popup.close:SetScript("OnClick", function() popup:Hide() end)

    popup.override = W.SwitchAt(popup, "Use custom settings for this frame", 16, -65, 330)
    popup.override:SetScript("OnClick", function(self)
        if Blocked() then popup:Refresh(); return end
        local GP, scope = GlobalPage(), CurrentScope()
        local enabled = self:GetChecked() and true or false
        RunChange("Font override", "menu:text-quick:override:" .. scope, function()
            GP.FontOverrideSetFor(scope, enabled, "MSUF2_TEXT_QUICK_OVERRIDE")
        end)
        popup:Refresh()
    end)

    popup.family = W.Dropdown(popup, "Font family (all frames)", function()
        if not cachedFontValues then
            local GP = GlobalPage()
            cachedFontValues = type(GP.FontValues) == "function" and GP.FontValues(false) or {}
        end
        return cachedFontValues
    end, 398)
    W.MoveWidget(popup.family, popup, 16, -102, 398, "LEFT")
    BindDropdown(popup.family, "Font family", "menu:text-quick:font-family",
        function()
            local GP = GlobalPage()
            return type(GP.FontKeyGet) == "function" and GP.FontKeyGet() or nil
        end,
        function(value)
            local GP = GlobalPage()
            if type(GP.FontKeySet) == "function" then GP.FontKeySet(value) end
            if type(_G.MSUF_NormalizeStoredFontKeys) == "function" then _G.MSUF_NormalizeStoredFontKeys() end
            if type(GP.ApplyFontsFor) == "function" then GP.ApplyFontsFor("shared", "MSUF2_TEXT_QUICK_FONT_KEY") end
        end)

    popup.outline = W.Segment(popup, "Outline", OUTLINE_VALUES, 398)
    W.MoveWidget(popup.outline, popup, 16, -156, 398, "LEFT")
    BindSegment(popup.outline, "Font outline", "menu:text-quick:outline",
        function() return GlobalPage().FontOutlineGetFor(CurrentScope()) end,
        function(value) GlobalPage().FontOutlineSetFor(CurrentScope(), value, "MSUF2_TEXT_QUICK_OUTLINE") end)

    popup.rendering = W.Segment(popup, "Rendering", RENDER_VALUES, 190)
    W.MoveWidget(popup.rendering, popup, 16, -210, 190, "LEFT")
    BindSegment(popup.rendering, "Font rendering", "menu:text-quick:rendering",
        function() return ScopeStyleGet("fontMonochrome", false) and "SHARP" or "SMOOTH" end,
        function(value) ScopeStyleSet("fontMonochrome", value == "SHARP", "MSUF2_TEXT_QUICK_RENDERING") end)

    popup.shadow = W.Segment(popup, "Text shadow", SHADOW_VALUES, 190)
    W.MoveWidget(popup.shadow, popup, 224, -210, 190, "LEFT")
    BindSegment(popup.shadow, "Text shadow", "menu:text-quick:shadow",
        function() return ScopeStyleGet("textBackdrop", true) and "ON" or "OFF" end,
        function(value) ScopeStyleSet("textBackdrop", value == "ON", "MSUF2_TEXT_QUICK_SHADOW") end)

    popup.opacity = W.Segment(popup, "Text opacity", TEXT_ALPHA_VALUES, 190)
    W.MoveWidget(popup.opacity, popup, 16, -264, 190, "LEFT")
    BindSegment(popup.opacity, "Text opacity", "menu:text-quick:opacity",
        function() return NormalizeTextAlpha(ScopeStyleGet("fontTextAlpha", 1)) end,
        function(value) ScopeStyleSet("fontTextAlpha", NormalizeTextAlpha(value), "MSUF2_TEXT_QUICK_ALPHA") end)

    popup.baseline = W.Dropdown(popup, "Baseline", BASELINE_VALUES, 190)
    W.MoveWidget(popup.baseline, popup, 224, -264, 190, "LEFT")
    BindDropdown(popup.baseline, "Font baseline", "menu:text-quick:baseline",
        function() return NormalizeBaseline(ScopeStyleGet("fontBaselineOffset", 0)) end,
        function(value) ScopeStyleSet("fontBaselineOffset", NormalizeBaseline(value), "MSUF2_TEXT_QUICK_BASELINE") end)

    popup.shadowAlpha = W.Dropdown(popup, "Shadow opacity", SHADOW_ALPHA_VALUES, 190)
    W.MoveWidget(popup.shadowAlpha, popup, 16, -318, 190, "LEFT")
    BindDropdown(popup.shadowAlpha, "Shadow opacity", "menu:text-quick:shadow-opacity",
        function()
            local GP = GlobalPage()
            local value = type(GP.FontShadowMetricsFor) == "function" and GP.FontShadowMetricsFor(CurrentScope()) or 1
            return max(0.20, min(1, floor(value * 20 + 0.5) / 20))
        end,
        function(value)
            local scope = CurrentScope()
            ClearLegacyShadowStrength(scope)
            ScopeStyleSet("fontShadowOpacity", max(0.20, min(1, tonumber(value) or 1)), "MSUF2_TEXT_QUICK_SHADOW_ALPHA")
        end)

    popup.shadowDistance = W.Segment(popup, "Shadow distance", SHADOW_DISTANCE_VALUES, 190)
    W.MoveWidget(popup.shadowDistance, popup, 224, -318, 190, "LEFT")
    BindSegment(popup.shadowDistance, "Shadow distance", "menu:text-quick:shadow-distance",
        function()
            local GP = GlobalPage()
            local _, distance
            if type(GP.FontShadowMetricsFor) == "function" then _, distance = GP.FontShadowMetricsFor(CurrentScope()) end
            return tonumber(distance) == 2 and 2 or 1
        end,
        function(value)
            local scope = CurrentScope()
            ClearLegacyShadowStrength(scope)
            ScopeStyleSet("fontShadowDistance", tonumber(value) == 2 and 2 or 1, "MSUF2_TEXT_QUICK_SHADOW_DISTANCE")
        end)

    popup.colorMode = W.Dropdown(popup, "Color mode", ColorModeValues, 296)
    W.MoveWidget(popup.colorMode, popup, 16, -372, 296, "LEFT")
    BindDropdown(popup.colorMode, "Text color mode", "menu:text-quick:color-mode",
        CurrentColorMode,
        function(value)
            local settings = activeSettings or {}
            if HasCustomColorMode() then
                settings.setColorMode(value)
                return
            end
            local GP = GlobalPage()
            GP.FontTextColorModeSetFor(CurrentModeScope(), CurrentModeKind(), value, "MSUF2_TEXT_QUICK_COLOR_MODE")
        end)

    popup.colors = T.Button(popup, "|cffff625f•|r|cff61d683•|r|cff5aa7ff•|r  Colors...", 104, 24, { noSearch = true })
    popup.colors._msuf2SkipHistoryCheckpoint = true
    popup.colors:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -16, 14)
    if T.CenterButtonLabel then T.CenterButtonLabel(popup.colors) end
    popup.colorNote = W.Text(popup, "", 16, -430, 282, T.colors.muted)
    popup.colorNote:ClearAllPoints()
    popup.colorNote:SetPoint("BOTTOMLEFT", popup, "BOTTOMLEFT", 16, 18)
    popup.colors:SetScript("OnClick", function()
        if Blocked() then return end
        local anchor, options = activeAnchor, activeOptions
        local targets = ResolveTextColorTargets()
        if #targets == 0 then return end
        local kind = CurrentKind()
        local colorOptions = {
            title = Resolve(activeSettings and activeSettings.colorTitle,
                kind == "name" and "Name colors"
                or (kind == "hp" and "HP text colors"
                or (kind == "power" and "Power text colors" or "Text colors"))),
            note = #targets > 1 and "Choose one of the colors used by this text mode." or "Edit the color used by this text mode.",
            historyLabel = options and options.historyLabel or "Text color",
            historySource = options and options.historySource or "menu:text-quick:color",
            maxTargets = 4,
        }
        popup:Hide()
        local opened = W.OpenContextColors(anchor and anchor:GetParent(), colorOptions, targets, function()
            if anchor and anchor.IsVisible and anchor:IsVisible() and M.frame and M.frame.IsShown and M.frame:IsShown() then
                W.OpenTextQuickSettings(anchor, options)
            end
        end)
        if not opened and anchor and anchor.IsVisible and anchor:IsVisible() then W.OpenTextQuickSettings(anchor, options) end
    end)

    function popup:Refresh()
        local GP, scope, kind = GlobalPage(), CurrentScope(), CurrentKind()
        local group = IsGroupSettings(activeSettings, scope)
        local label = SCOPE_LABELS[scope] or tostring(scope)
        self.title:SetText(Tr("Fonts & Colors") .. " · " .. Tr(label))
        self.subtitle:SetText(Tr(Resolve(activeSettings and activeSettings.subtitle,
            "Font style is synchronized with the Fonts menu for this frame.")))

        local shared = scope == "shared"
        local override = shared or (type(GP.FontOverrideGetFor) == "function" and GP.FontOverrideGetFor(scope))
        local showOverride = not shared and HasCapability("override", true)
        SetShown(self.override, showOverride)
        self.override:SetChecked(override and true or false)

        self.family:SetValue(type(GP.FontKeyGet) == "function" and GP.FontKeyGet() or nil)
        self.outline:SetValue(type(GP.FontOutlineGetFor) == "function" and GP.FontOutlineGetFor(scope) or "OUTLINE")
        self.rendering:SetValue(ScopeStyleGet("fontMonochrome", false) and "SHARP" or "SMOOTH")
        local shadowOn = ScopeStyleGet("textBackdrop", true) == true
        self.shadow:SetValue(shadowOn and "ON" or "OFF")
        self.opacity:SetValue(NormalizeTextAlpha(ScopeStyleGet("fontTextAlpha", 1)))
        self.baseline:SetValue(NormalizeBaseline(ScopeStyleGet("fontBaselineOffset", 0)))
        local shadowAlpha, shadowDistance = 1, 1
        if type(GP.FontShadowMetricsFor) == "function" then
            shadowAlpha, shadowDistance = GP.FontShadowMetricsFor(scope)
        end
        self.shadowAlpha:SetValue(max(0.20, min(1, floor((tonumber(shadowAlpha) or 1) * 20 + 0.5) / 20)))
        self.shadowDistance:SetValue(tonumber(shadowDistance) == 2 and 2 or 1)

        local familyVisible = HasCapability("family", true)
        local outlineVisible = HasCapability("outline", true)
        local renderingVisible = HasCapability("rendering", true)
        local shadowVisible = HasCapability("shadow", true)
        local opacityVisible = HasCapability("opacity", true)
        local baselineVisible = HasCapability("baseline", true)
        local shadowAlphaVisible = shadowVisible and HasCapability("shadowAlpha", true)
        local shadowDistanceVisible = shadowVisible and HasCapability("shadowDistance", true)
        local colorsAllowed = HasCapability("colors", true)
        local targetCount = colorsAllowed and #ResolveTextColorTargets() or 0
        local colorsVisible = colorsAllowed and targetCount > 0
        local modeVisible = ColorModeVisible()
        SetShown(self.family, familyVisible)
        SetShown(self.outline, outlineVisible)
        SetShown(self.rendering, renderingVisible)
        SetShown(self.shadow, shadowVisible)
        SetShown(self.opacity, opacityVisible)
        SetShown(self.baseline, baselineVisible)
        SetShown(self.shadowAlpha, shadowAlphaVisible)
        SetShown(self.shadowDistance, shadowDistanceVisible)
        SetShown(self.colorMode, modeVisible)
        SetShown(self.colors, colorsVisible)
        SetShown(self.colorNote, colorsVisible)
        if modeVisible then
            self.colorMode:SetValues(ColorModeValues())
            self.colorMode:SetValue(CurrentColorMode())
        end

        -- Reflow only while this cold popup is open. Component-specific
        -- capability masks therefore do not leave dead rows or make the
        -- unobtrusive shortcut open an unnecessarily tall panel.
        local y = showOverride and -102 or -76
        local function Full(control, visible)
            if not visible then return end
            W.MoveWidget(control, self, 16, y, 398, "LEFT")
            y = y - 54
        end
        local function Pair(left, leftVisible, right, rightVisible)
            if not leftVisible and not rightVisible then return end
            if leftVisible and rightVisible then
                W.MoveWidget(left, self, 16, y, 190, "LEFT")
                W.MoveWidget(right, self, 224, y, 190, "LEFT")
            elseif leftVisible then
                W.MoveWidget(left, self, 16, y, 398, "LEFT")
            else
                W.MoveWidget(right, self, 16, y, 398, "LEFT")
            end
            y = y - 54
        end
        Full(self.family, familyVisible)
        Full(self.outline, outlineVisible)
        Pair(self.rendering, renderingVisible, self.shadow, shadowVisible)
        Pair(self.opacity, opacityVisible, self.baseline, baselineVisible)
        Pair(self.shadowAlpha, shadowAlphaVisible, self.shadowDistance, shadowDistanceVisible)
        Full(self.colorMode, modeVisible)
        self:SetHeight(max(214, -y + (colorsVisible and 40 or 16)))

        local scopedControls = {
            self.outline, self.rendering, self.shadow, self.opacity, self.baseline,
            self.shadowAlpha, self.shadowDistance,
        }
        for i = 1, #scopedControls do SetEnabled(scopedControls[i], override) end
        SetEnabled(self.shadowAlpha, override and shadowOn and shadowAlphaVisible)
        SetEnabled(self.shadowDistance, override and shadowOn and shadowDistanceVisible)
        local modeScope = CurrentModeScope()
        local modeOverride = modeScope == "shared"
            or (type(GP.FontOverrideGetFor) == "function" and GP.FontOverrideGetFor(modeScope) == true)
        local colorModeEnabled = modeVisible and (HasCustomColorMode() or modeOverride)
        SetEnabled(self.colorMode, colorModeEnabled)
        if colorModeEnabled and self.colorMode._msuf2Title and self.colorMode._msuf2Title.SetTextColor then
            self.colorMode._msuf2Title:SetTextColor(
                T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], T.colors.accent[4] or 1)
        end

        SetEnabled(self.colors, targetCount > 0)
        if group and kind == "power" then
            self.colorNote:SetText(CurrentColorMode() == "RESOURCE"
                and Tr("Group preview resource color") or Tr("Default group font color"))
        else
            self.colorNote:SetText(tostring(targetCount) .. (targetCount == 1 and Tr(" matching color") or Tr(" matching colors")))
        end
    end

    popup:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:Hide()
            if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
        elseif self.SetPropagateKeyboardInput then
            self:SetPropagateKeyboardInput(true)
        end
    end)
    popup:SetScript("OnHide", function()
        if W.CloseDropdown then W.CloseDropdown({ immediate = true }) end
    end)
    if M.frame and M.frame.HookScript and not M.frame._msuf2TextQuickSettingsHideHooked then
        M.frame._msuf2TextQuickSettingsHideHooked = true
        M.frame:HookScript("OnHide", function() if textQuickPopup then textQuickPopup:Hide() end end)
    end
    popup:Hide()
    return popup
end

function W.OpenTextQuickSettings(anchor, options)
    if not anchor or Blocked() then return false end
    local popup = EnsurePopup()
    if not popup then return false end
    if W.CloseDropdown then W.CloseDropdown({ immediate = true }) end
    if popup.SetPropagateKeyboardInput then popup:SetPropagateKeyboardInput(true) end
    if popup:IsShown() and activeAnchor == anchor then popup:Hide(); return true end

    activeAnchor = anchor
    activeOptions = options or {}
    activeSettings = activeOptions.textSettings or {}
    local GP = GlobalPage()
    local general = type(GP.G) == "function" and GP.G() or nil
    local scope = CurrentScope()
    if general and general._fontScopeKey ~= scope then
        general._fontScopeKey = scope
        if type(M.InvalidatePage) == "function" then M.InvalidatePage("opt_fonts") end
    end
    popup:Refresh()
    if M.ApplyPopupFramePriority then M.ApplyPopupFramePriority(popup) end
    popup:ClearAllPoints()
    popup:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -8)
    popup:Show()

    if anchor.HookScript and not anchor._msuf2TextQuickSettingsHideHooked then
        anchor._msuf2TextQuickSettingsHideHooked = true
        anchor:HookScript("OnHide", function(self)
            if textQuickPopup and activeAnchor == self then textQuickPopup:Hide() end
        end)
    end
    return true
end

function W.CloseTextQuickSettings()
    if not textQuickPopup then return false end
    if textQuickPopup:IsShown() then textQuickPopup:Hide() end
    return true
end

M.OpenTextQuickSettings = W.OpenTextQuickSettings
M.CloseTextQuickSettings = W.CloseTextQuickSettings
