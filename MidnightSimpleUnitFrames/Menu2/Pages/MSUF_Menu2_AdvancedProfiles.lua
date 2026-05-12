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
local MoveWidget = AP.MoveWidget
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
local function BuildProfiles(ctx)
    local b = W.PageBuilder(ctx)
    b:Header("Profiles", "Create, switch, copy, delete, export and import profiles.", 64)

    local current = b:CollapsibleSection("profiles_management", "Profile Management", 278, true)
    local profileDrop = W.Dropdown(current, "Active profile", {}, 260)
    local function RefreshProfileValues()
        local values = {}
        local list = type(_G.MSUF_GetAllProfiles) == "function" and _G.MSUF_GetAllProfiles() or { "Default" }
        for i = 1, #list do values[#values + 1] = { value = list[i], text = list[i] } end
        profileDrop.values = values
    end
    profileDrop:SetOnValueChanged(function(value)
        if type(_G.MSUF_SwitchProfile) == "function" then pcall(_G.MSUF_SwitchProfile, value) end
        M.RequestGeneralApply("MSUF2_PROFILE_SWITCH", { preview = true })
        if M.frame and M.frame.RefreshStatus then M.frame:RefreshStatus() end
    end)
    M.AddRefresher(ctx, function()
        RefreshProfileValues()
        profileDrop:SetValue(_G.MSUF_ActiveProfile or "Default")
    end)
    local nameInput = W.TextInput(current, "New / target profile name", 260)
    local create = W.Button(current, "Create profile", 150)
    create:SetScript("OnClick", function()
        local name = nameInput:GetText()
        if name and name ~= "" and type(_G.MSUF_CreateProfile) == "function" then
            pcall(_G.MSUF_CreateProfile, name)
            pcall(_G.MSUF_SwitchProfile, name)
        end
        M.InvalidatePage("profiles")
        M.SelectPage("profiles")
    end)
    local copy = T.Button(current, "Copy current to name", 170, 24)
    copy:SetPoint("LEFT", create, "RIGHT", 8, 0)
    copy:SetScript("OnClick", function()
        local name = nameInput:GetText()
        if name and name ~= "" and type(_G.MSUF_CopyProfile) == "function" then
            pcall(_G.MSUF_CopyProfile, _G.MSUF_ActiveProfile or "Default", name)
            M.InvalidatePage("profiles")
            M.SelectPage("profiles")
        end
    end)
    local reset = W.Button(current, "Reset current profile", 170)
    reset:SetScript("OnClick", function()
        if type(_G.MSUF_ResetProfile) == "function" then pcall(_G.MSUF_ResetProfile, _G.MSUF_ActiveProfile or "Default") end
        M.RequestGeneralApply("MSUF2_PROFILE_RESET", { preview = true })
    end)
    local delete = T.Button(current, "Delete current profile", 170, 24)
    delete:SetPoint("LEFT", reset, "RIGHT", 8, 0)
    T.SkinDangerButton(delete)
    delete:SetScript("OnClick", function()
        if type(_G.MSUF_DeleteProfile) == "function" then pcall(_G.MSUF_DeleteProfile, _G.MSUF_ActiveProfile or "Default") end
        M.InvalidatePage("profiles")
        M.SelectPage("profiles")
    end)

    local io = b:CollapsibleSection("profiles_io", "Export / Import", 232, false)
    local exportKind = W.Dropdown(io, "Export kind", {
        { value = "all", text = "Full profile" },
        { value = "unitframe", text = "Unitframes" },
        { value = "colors", text = "Colors" },
        { value = "gameplay", text = "Gameplay" },
        { value = "groupframe", text = "Group Frames" },
    }, 240)
    M.BindDropdown(ctx, exportKind,
        function() return M.profileExportKind or "all" end,
        function(v) M.profileExportKind = v or "all" end)
    local blob = W.TextInput(io, "Profile string", 640)
    blob._msuf2CommitOnBlur = false
    local export = W.Button(io, "Export", 120)
    export:SetScript("OnClick", function()
        local fn = _G.MSUF_ExportSelectionToString
        if type(fn) == "function" then
            local ok, value = pcall(fn, M.profileExportKind or "all")
            if ok and type(value) == "string" then blob:SetText(value); blob:HighlightText() end
        end
    end)
    local import = T.Button(io, "Import into current", 160, 24)
    import:SetPoint("LEFT", export, "RIGHT", 8, 0)
    import:SetScript("OnClick", function()
        local text = blob:GetText()
        if text and text ~= "" and type(_G.MSUF_ImportFromString) == "function" then
            pcall(_G.MSUF_ImportFromString, text)
            M.RequestGeneralApply("MSUF2_PROFILE_IMPORT", { preview = true })
        end
    end)

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

M.RegisterPage("profiles", { title = "MSUF Profiles", build = BuildProfiles })
M.RegisterPage("modules", { title = "MSUF Modules", build = BuildModules })
