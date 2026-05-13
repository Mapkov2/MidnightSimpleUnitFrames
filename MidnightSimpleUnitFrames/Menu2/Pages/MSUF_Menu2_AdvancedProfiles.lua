local addonName, ns = ...
ns = ns or {}

local M = ns.MSUF2 or {}
ns.MSUF2 = M
_G.MSUF2 = M

local W = M.Widgets
local T = M.Theme
local AP = M.AdvancedPage or {}

local floor = math.floor
local max = math.max
local min = math.min

local CallGlobal = AP.CallGlobal
local DB = AP.DB
local G = AP.G
local Bars = AP.Bars
local Gameplay = AP.Gameplay
local BoolValue = AP.BoolValue
local NumValue = AP.NumValue
local SetValue = AP.SetValue
local DeepCopyTable = AP.DeepCopyTable
local BindTableToggle = AP.BindTableToggle
local BindTableSlider = AP.BindTableSlider
local BindTableDropdown = AP.BindTableDropdown
local BindValueDropdown = AP.BindValueDropdown
local ReadRGB = AP.ReadRGB
local WriteRGB = AP.WriteRGB
local BindTableColor = AP.BindTableColor
local BindSeparateRGB = AP.BindSeparateRGB
local ApplyAuras = AP.ApplyAuras
local MoveWidget = W.MoveWidget or AP.MoveWidget
local LabelAt = AP.LabelAt
local DividerAt = AP.DividerAt
local BindValueToggle = AP.BindValueToggle
local BindValueSlider = AP.BindValueSlider
local ToggleAt = AP.ToggleAt
local ValueToggleAt = AP.ValueToggleAt
local SliderAt = AP.SliderAt
local ValueSliderAt = AP.ValueSliderAt
local DropdownAt = AP.DropdownAt
local ValueDropdownAt = AP.ValueDropdownAt
local ColorAt = AP.ColorAt
local ScopedToggleAt = AP.ScopedToggleAt
local ScopedSliderAt = AP.ScopedSliderAt
local ScopedDropdownAt = AP.ScopedDropdownAt
local TogglePillAt = AP.TogglePillAt
local SetControlEnabled = AP.SetControlEnabled

local WAGO_PROFILES_URL = "https://wago.io/search/imports/wow/msuf"

local function Trim(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function ShortLabel(value, limit)
    value = Trim(value)
    limit = tonumber(limit) or 28
    if #value <= limit then return value end
    return value:sub(1, limit - 3) .. "..."
end

local function ProfileValues(includeNone)
    local values = {}
    if includeNone then values[#values + 1] = { value = "None", text = "None" } end
    local list = type(_G.MSUF_GetAllProfiles) == "function" and _G.MSUF_GetAllProfiles() or { "Default" }
    for i = 1, #list do values[#values + 1] = { value = list[i], text = list[i] } end
    return values
end

local function GetSpecMeta()
    local n = type(_G.GetNumSpecializations) == "function" and _G.GetNumSpecializations() or 0
    local out = {}
    for i = 1, n do
        if type(_G.GetSpecializationInfo) == "function" then
            local specID, specName = _G.GetSpecializationInfo(i)
            if type(specID) == "number" and type(specName) == "string" then
                out[#out + 1] = { id = specID, name = specName }
            end
        end
    end
    return out
end

local function RefreshAfterProfileChange(ctx)
    if M.frame and M.frame.RefreshStatus then M.frame:RefreshStatus() end
    if M.Refresh then M.Refresh(ctx) end
end

local function EnsureProfilePopups()
    if not _G.StaticPopupDialogs then return end

    if not _G.StaticPopupDialogs.MSUF2_CONFIRM_RESET_PROFILE then
        _G.StaticPopupDialogs.MSUF2_CONFIRM_RESET_PROFILE = {
            text = "Reset profile '%s' to defaults?",
            button1 = YES or "Yes",
            button2 = NO or "No",
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
            OnAccept = function(_, data)
                if not (data and data.name) then return end
                if type(_G.MSUF_ResetProfile) == "function" then pcall(_G.MSUF_ResetProfile, data.name) end
                if M.ClearHistory then M.ClearHistory() end
                if M.RequestGeneralApply then M.RequestGeneralApply("MSUF2_PROFILE_RESET", { preview = true }) end
                if type(data.after) == "function" then data.after() end
                if type(_G.MSUF_ShowReloadRecommendedPopup) == "function" then
                    _G.MSUF_ShowReloadRecommendedPopup("Profile reset")
                end
            end,
        }
    end

    if not _G.StaticPopupDialogs.MSUF2_CONFIRM_DELETE_PROFILE then
        _G.StaticPopupDialogs.MSUF2_CONFIRM_DELETE_PROFILE = {
            text = "Delete profile '%s'?",
            button1 = DELETE or "Delete",
            button2 = CANCEL or "Cancel",
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
            OnAccept = function(_, data)
                if not (data and data.name) then return end
                if type(_G.MSUF_DeleteProfile) == "function" then pcall(_G.MSUF_DeleteProfile, data.name) end
                if M.ClearHistory then M.ClearHistory() end
                if type(data.after) == "function" then data.after() end
            end,
        }
    end
end

local function BuildProfiles(ctx)
    local b = W.PageBuilder(ctx)
    b:Header("Profiles", "Create, switch, copy, delete, export and import profiles.", 64)
    EnsureProfilePopups()

    local contentW = ctx.width or 920
    local rightX = min(max(420, floor(contentW * 0.52)), max(360, contentW - 390))

    local current = b:CollapsibleSection("profiles_management", "Profile Management", 208, true)
    local profileDrop = W.Dropdown(current, "Active profile", {}, 260)
    local function RefreshProfileValues()
        profileDrop:SetValues(ProfileValues(false))
    end
    profileDrop:SetOnValueChanged(function(value)
        if value and value ~= "" and value ~= _G.MSUF_ActiveProfile and type(_G.MSUF_SwitchProfile) == "function" then
            pcall(_G.MSUF_SwitchProfile, value)
            if M.ClearHistory then M.ClearHistory() end
        end
        M.RequestGeneralApply("MSUF2_PROFILE_SWITCH", { preview = true })
        RefreshAfterProfileChange(ctx)
    end)
    M.AddRefresher(ctx, function()
        RefreshProfileValues()
        profileDrop:SetValue(_G.MSUF_ActiveProfile or "Default")
    end)
    local nameInput = W.TextInput(current, "New / target profile name", 260)
    local create = T.Button(current, "Create profile", 150, 24)
    create:SetScript("OnClick", function()
        local name = Trim(nameInput:GetText())
        if name and name ~= "" and type(_G.MSUF_CreateProfile) == "function" then
            pcall(_G.MSUF_CreateProfile, name)
            pcall(_G.MSUF_SwitchProfile, name)
            if M.ClearHistory then M.ClearHistory() end
        end
        nameInput:SetText("")
        RefreshAfterProfileChange(ctx)
    end)
    local copy = T.Button(current, "Copy current to name", 170, 24)
    copy:SetScript("OnClick", function()
        local name = Trim(nameInput:GetText())
        if name and name ~= "" and type(_G.MSUF_CopyProfile) == "function" then
            local ok, copied = pcall(_G.MSUF_CopyProfile, _G.MSUF_ActiveProfile or "Default", name)
            if ok and copied and type(_G.MSUF_SwitchProfile) == "function" then pcall(_G.MSUF_SwitchProfile, name) end
            if M.ClearHistory then M.ClearHistory() end
            nameInput:SetText("")
            RefreshAfterProfileChange(ctx)
        end
    end)
    local reset = T.Button(current, "Reset current profile", 170, 24)
    reset:SetScript("OnClick", function()
        local name = _G.MSUF_ActiveProfile or "Default"
        if _G.StaticPopup_Show and _G.StaticPopupDialogs and _G.StaticPopupDialogs.MSUF2_CONFIRM_RESET_PROFILE then
            _G.StaticPopup_Show("MSUF2_CONFIRM_RESET_PROFILE", name, nil, { name = name, after = function() RefreshAfterProfileChange(ctx) end })
        elseif type(_G.MSUF_ResetProfile) == "function" then
            pcall(_G.MSUF_ResetProfile, name)
            if M.ClearHistory then M.ClearHistory() end
            RefreshAfterProfileChange(ctx)
        end
    end)
    local delete = T.Button(current, "Delete current profile", 170, 24)
    T.SkinDangerButton(delete)
    delete:SetScript("OnClick", function()
        local name = _G.MSUF_ActiveProfile or "Default"
        if name == "Default" then return end
        if _G.StaticPopup_Show and _G.StaticPopupDialogs and _G.StaticPopupDialogs.MSUF2_CONFIRM_DELETE_PROFILE then
            _G.StaticPopup_Show("MSUF2_CONFIRM_DELETE_PROFILE", name, nil, { name = name, after = function() RefreshAfterProfileChange(ctx) end })
        elseif type(_G.MSUF_DeleteProfile) == "function" then
            pcall(_G.MSUF_DeleteProfile, name)
            if M.ClearHistory then M.ClearHistory() end
            RefreshAfterProfileChange(ctx)
        end
    end)
    MoveWidget(profileDrop, current, 14, -42, 300)
    MoveWidget(nameInput, current, 14, -104, 300)
    create:SetPoint("TOPLEFT", current, "TOPLEFT", rightX, -58)
    copy:SetPoint("LEFT", create, "RIGHT", 10, 0)
    reset:SetPoint("TOPLEFT", current, "TOPLEFT", rightX, -98)
    delete:SetPoint("LEFT", reset, "RIGHT", 10, 0)
    M.AddRefresher(ctx, function()
        local active = _G.MSUF_ActiveProfile or "Default"
        if delete.SetEnabled then delete:SetEnabled(active ~= "Default") end
    end)

    local history = b:CollapsibleSection("profiles_history", "Undo / Redo", 128, true)
    W.Text(history, "Session history for MSUF2 option changes. Profile switches, imports, resets and deletes start a clean history.", 14, -34, contentW - 28, T.colors.muted)
    local undo = T.Button(history, "< Undo", 180, 26)
    T.SkinDangerButton(undo)
    local redo = T.Button(history, "Redo >", 180, 26)
    T.SkinSuccessButton(redo)
    local state = W.Text(history, "", 14, -92, contentW - 28, T.colors.dim)
    undo:SetPoint("TOPLEFT", history, "TOPLEFT", 14, -62)
    redo:SetPoint("LEFT", undo, "RIGHT", 12, 0)
    undo:SetScript("OnClick", function()
        if M.Undo then M.Undo() end
    end)
    redo:SetScript("OnClick", function()
        if M.Redo then M.Redo() end
    end)
    M.AddRefresher(ctx, function()
        local s = M.GetHistoryState and M.GetHistoryState() or {}
        if undo.SetEnabled then undo:SetEnabled(s.canUndo and true or false) end
        if redo.SetEnabled then redo:SetEnabled(s.canRedo and true or false) end
        undo:SetText(s.undoLabel and ("< Undo: " .. ShortLabel(s.undoLabel, 20)) or "< Undo")
        redo:SetText(s.redoLabel and ("Redo: " .. ShortLabel(s.redoLabel, 20) .. " >") or "Redo >")
        if s.canUndo or s.canRedo then
            state:SetText(("Undo: %d   Redo: %d"):format(tonumber(s.undoCount) or 0, tonumber(s.redoCount) or 0))
        else
            state:SetText("No tracked MSUF2 changes in this session.")
        end
    end)

    local specs = GetSpecMeta()
    local specRows = max(1, math.ceil((#specs > 0 and #specs or 1) / 2))
    local spec = b:CollapsibleSection("profiles_specs", "Spec Profiles", 120 + (specRows * 58), true)
    local auto = W.Toggle(spec, "Auto-switch profile by specialization")
    M.BindToggle(ctx, auto,
        function()
            return type(_G.MSUF_IsSpecAutoSwitchEnabled) == "function" and _G.MSUF_IsSpecAutoSwitchEnabled() or false
        end,
        function(v)
            if type(_G.MSUF_SetSpecAutoSwitchEnabled) == "function" then pcall(_G.MSUF_SetSpecAutoSwitchEnabled, v and true or false) end
            RefreshAfterProfileChange(ctx)
        end)
    MoveWidget(auto, spec, 14, -38)
    W.Text(spec, "Assign profiles per specialization. If you change spec in combat, MSUF switches after combat.", 14, -70, contentW - 28, T.colors.muted)
    if #specs == 0 then
        W.Text(spec, "No specialization data is available for this character yet.", 14, -106, contentW - 28, T.colors.dim)
    else
        local specColX = min(max(360, floor(contentW * 0.48)), max(330, contentW - 330))
        for i, s in ipairs(specs) do
            local col = ((i - 1) % 2)
            local row = floor((i - 1) / 2)
            local x = (col == 0) and 14 or specColX
            local y = -112 - (row * 58)
            local drop = W.Dropdown(spec, s.name, function() return ProfileValues(true) end, 260)
            MoveWidget(drop, spec, x, y, 260)
            M.BindDropdown(ctx, drop,
                function()
                    if type(_G.MSUF_GetSpecProfile) == "function" then
                        return _G.MSUF_GetSpecProfile(s.id) or "None"
                    end
                    return "None"
                end,
                function(v)
                    if type(_G.MSUF_SetSpecProfile) == "function" then
                        pcall(_G.MSUF_SetSpecProfile, s.id, (v ~= "None") and v or nil)
                    end
                    RefreshAfterProfileChange(ctx)
                end)
        end
    end

    local io = b:CollapsibleSection("profiles_io", "Export / Import", 286, false)
    local exportKind = W.Dropdown(io, "Export kind", {
        { value = "all", text = "Full profile" },
        { value = "unitframe", text = "Unitframes" },
        { value = "castbar", text = "Castbars" },
        { value = "colors", text = "Colors" },
        { value = "gameplay", text = "Gameplay" },
        { value = "groupframe", text = "Group Frames" },
    }, 240)
    M.BindDropdown(ctx, exportKind,
        function() return M.profileExportKind or "all" end,
        function(v) M.profileExportKind = v or "all" end)
    local blob = W.TextInput(io, "Profile string", 640)
    blob._msuf2CommitOnBlur = false
    local export = T.Button(io, "Export", 120, 24)
    export:SetScript("OnClick", function()
        local fn = _G.MSUF_ExportSelectionToString
        if type(fn) == "function" then
            local ok, value = pcall(fn, M.profileExportKind or "all")
            if ok and type(value) == "string" then blob:SetText(value); blob:HighlightText() end
        end
    end)
    local import = T.Button(io, "Import into current", 160, 24)
    import:SetScript("OnClick", function()
        local text = blob:GetText()
        if text and text ~= "" and type(_G.MSUF_ImportFromString) == "function" then
            pcall(_G.MSUF_ImportFromString, text)
            if M.ClearHistory then M.ClearHistory() end
            M.RequestGeneralApply("MSUF2_PROFILE_IMPORT", { preview = true })
            RefreshAfterProfileChange(ctx)
        end
    end)
    local legacy = T.Button(io, "Legacy Import", 132, 24)
    legacy:SetScript("OnClick", function()
        local text = blob:GetText()
        if text and text ~= "" and type(_G.MSUF_ImportLegacyFromString) == "function" then
            pcall(_G.MSUF_ImportLegacyFromString, text)
            if M.ClearHistory then M.ClearHistory() end
            M.RequestGeneralApply("MSUF2_PROFILE_LEGACY_IMPORT", { preview = true })
            RefreshAfterProfileChange(ctx)
        end
    end)
    local wago = T.Button(io, "Browse Wago Profiles", 220, 28)
    wago:SetScript("OnClick", function()
        if type(_G.MSUF_ShowCopyLink) == "function" then
            _G.MSUF_ShowCopyLink("Wago MSUF Profiles", WAGO_PROFILES_URL)
        else
            blob:SetText(WAGO_PROFILES_URL)
            blob:HighlightText()
        end
    end)
    local ioActionX = min(max(380, floor(contentW * 0.46)), max(340, contentW - 460))
    MoveWidget(exportKind, io, 14, -42, 260)
    MoveWidget(blob, io, 14, -104, max(320, min(620, ioActionX - 28)))
    export:SetPoint("TOPLEFT", io, "TOPLEFT", ioActionX, -64)
    import:SetPoint("LEFT", export, "RIGHT", 10, 0)
    legacy:SetPoint("LEFT", import, "RIGHT", 10, 0)
    wago:SetPoint("TOPLEFT", io, "TOPLEFT", ioActionX, -104)

    ctx:SetContentHeight(math.abs(b.y) + 42)
end

local function BuildModules(ctx)
    local b = W.PageBuilder(ctx)
    b:Header("Modules", "Optional MSUF style and visual modules.", 64)
    local style = b:CollapsibleSection("modules_style", "Style", 230, true)
    local enable = W.Toggle(style, "Enable MSUF Style")
    M.BindToggle(ctx, enable,
        function()
            if type(_G.MSUF_StyleIsEnabled) == "function" then
                local ok, v = pcall(_G.MSUF_StyleIsEnabled)
                if ok then return v and true or false end
            end
            return G().styleEnabled ~= false
        end,
        function(v)
            if type(_G.MSUF_SetStyleEnabled) == "function" then pcall(_G.MSUF_SetStyleEnabled, v and true or false) end
            G().styleEnabled = v and true or false
            CallGlobal("MSUF_ApplyModules")
        end)
    local dropdownMode = W.Dropdown(style, "Dropdown style", {
        { text = "MSUF superellipse", value = "msuf" },
        { text = "Blizzard legacy", value = "old" },
    }, 230)
    M.BindDropdown(ctx, dropdownMode,
        function()
            if type(_G.MSUF_GetDropdownStyleMode) == "function" then
                local ok, value = pcall(_G.MSUF_GetDropdownStyleMode)
                if ok then return value or "msuf" end
            end
            local mode = G().dropdownStyleMode
            return (mode == "old" or mode == "blizzard" or mode == "legacy") and "old" or "msuf"
        end,
        function(v)
            v = (v == "old") and "old" or "msuf"
            if type(_G.MSUF_ApplyDropdownStyleModeImmediate) == "function" then
                pcall(_G.MSUF_ApplyDropdownStyleModeImmediate, v)
            elseif type(_G.MSUF_SetDropdownStyleMode) == "function" then
                pcall(_G.MSUF_SetDropdownStyleMode, v)
                G().dropdownStyleMode = v
            else
                G().dropdownStyleMode = v
            end
        end)
    BindTableToggle(ctx, style, "Rounded unitframes", G, "roundedUnitframes", false, function() CallGlobal("MSUF_ApplyModules") end)
    BindTableToggle(ctx, style, "Portrait decoration", G, "portraitDecorationEnabled", false, function() CallGlobal("MSUF_ApplyModules") end)
    ctx:SetContentHeight(math.abs(b.y) + 42)
end

M.RegisterPage("profiles", { title = "MSUF Profiles", build = BuildProfiles, version = 3 })
M.RegisterPage("modules", { title = "MSUF Modules", build = BuildModules })
