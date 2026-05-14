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

local function PrintProfileMessage(color, message)
    print((color or "|cffffd700") .. "MSUF:|r " .. tostring(message or ""))
end

local function BlockCombatAction()
    if M.BlockCombatAction then return M.BlockCombatAction() and true or false end
    if type(_G.MSUF_BlockConfigCombatLocked) == "function" then
        return _G.MSUF_BlockConfigCombatLocked() and true or false
    end
    if _G.InCombatLockdown and _G.InCombatLockdown() then
        if type(_G.MSUF_ShowConfigCombatLockMessage) == "function" then
            _G.MSUF_ShowConfigCombatLockMessage()
        end
        return true
    end
    if _G.UnitAffectingCombat and _G.UnitAffectingCombat("player") then
        if type(_G.MSUF_ShowConfigCombatLockMessage) == "function" then
            _G.MSUF_ShowConfigCombatLockMessage()
        end
        return true
    end
    return false
end

local function EnsureProfilePopups()
    if not _G.StaticPopupDialogs then return end

    if not _G.StaticPopupDialogs.MSUF2_IMPORT_RELOAD_PROMPT then
        _G.StaticPopupDialogs.MSUF2_IMPORT_RELOAD_PROMPT = {
            text = "Profile imported into the current profile.\n\nReload the UI now so every imported setting is applied?",
            button1 = _G.RELOAD or "Reload",
            button2 = _G.CANCEL or "Not now",
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
            OnAccept = function()
                if type(_G.ReloadUI) == "function" then _G.ReloadUI() end
            end,
        }
    end

    if not _G.StaticPopupDialogs.MSUF2_CONFIRM_RESET_PROFILE then
        _G.StaticPopupDialogs.MSUF2_CONFIRM_RESET_PROFILE = {
            text = "Reset profile '%s' to defaults?\n\nThis resets the entire selected profile to the current MSUF factory defaults. Every menu in that profile will be affected.",
            button1 = YES or "Yes",
            button2 = NO or "No",
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
            OnAccept = function(_, data)
                if BlockCombatAction() then return end
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
                if BlockCombatAction() then return end
                if not (data and data.name) then return end
                if type(_G.MSUF_DeleteProfile) == "function" then pcall(_G.MSUF_DeleteProfile, data.name) end
                if M.ClearHistory then M.ClearHistory() end
                if type(data.after) == "function" then data.after() end
            end,
        }
    end
end

local function ShowImportReloadPrompt()
    if _G.InCombatLockdown and _G.InCombatLockdown() then
        PrintProfileMessage("|cffffd700", "Profile imported. Reload after combat with /reload.")
        return
    end
    if _G.StaticPopup_Show and _G.StaticPopupDialogs and _G.StaticPopupDialogs.MSUF2_IMPORT_RELOAD_PROMPT then
        _G.StaticPopup_Show("MSUF2_IMPORT_RELOAD_PROMPT")
        return
    end
    if type(_G.MSUF_ShowReloadRecommendedPopup) == "function" then
        _G.MSUF_ShowReloadRecommendedPopup("Profile import")
    else
        PrintProfileMessage("|cffffd700", "Profile imported. Reload the UI with /reload.")
    end
end

local function ReloadAfterNewProfileImport(profileName)
    if _G.InCombatLockdown and _G.InCombatLockdown() then
        PrintProfileMessage("|cffffd700", "Imported profile '" .. tostring(profileName) .. "'. Reload after combat with /reload.")
        return
    end
    if type(_G.ReloadUI) == "function" then
        _G.ReloadUI()
    else
        PrintProfileMessage("|cffffd700", "Imported profile '" .. tostring(profileName) .. "'. Reload the UI with /reload.")
    end
end

local function ProfileExists(name)
    local gdb = _G.MSUF_GlobalDB
    local profiles = type(gdb) == "table" and gdb.profiles or nil
    return type(profiles) == "table" and profiles[name] ~= nil
end

local function DeleteCreatedProfile(name)
    local gdb = _G.MSUF_GlobalDB
    local profiles = type(gdb) == "table" and gdb.profiles or nil
    if type(profiles) == "table" then
        profiles[name] = nil
    end
end

local function BuildProfiles(ctx)
    local b = W.PageBuilder(ctx)
    local head = b:Header("Profiles", "Create, switch, copy, delete, export and import profiles.", 64)
    if W.CreatePageResetButton then
        W.CreatePageResetButton(ctx, head, nil, { width = 118, text = "Reset Profile", y = -20 })
    end
    EnsureProfilePopups()

    local contentW = ctx.width or 920
    local rightX = min(max(420, floor(contentW * 0.52)), max(360, contentW - 390))

    local current = b:CollapsibleSection("profiles_management", "Profile Management", 208, true)
    local profileDrop = W.Dropdown(current, "Active profile", {}, 260)
    local function RefreshProfileValues()
        profileDrop:SetValues(ProfileValues(false))
    end
    profileDrop:SetOnValueChanged(function(value)
        if BlockCombatAction() then
            profileDrop:SetValue(_G.MSUF_ActiveProfile or "Default")
            return
        end
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
        if BlockCombatAction() then return end
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
        if BlockCombatAction() then return end
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
        if BlockCombatAction() then return end
        if M.ShowPageResetConfirm then
            M.ShowPageResetConfirm("profiles")
            return
        end
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
        if BlockCombatAction() then return end
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

    local io = b:CollapsibleSection("profiles_io", "Export / Import", 356, false)
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
    local importCreateNew = W.Toggle(io, "Import and create new profile")
    local importProfileName = W.TextInput(io, "New profile name", 260)
    importProfileName._msuf2CommitOnBlur = false

    local function ImportIntoCurrent()
        if BlockCombatAction() then return false end
        local text = blob:GetText()
        if not (text and text ~= "") then
            PrintProfileMessage("|cffff0000", "Import failed (empty string).")
            return false
        end
        if type(_G.MSUF_ImportFromString) ~= "function" then
            PrintProfileMessage("|cffff0000", "Import failed: profile import API is not available.")
            return false
        end
        local ok, imported = pcall(_G.MSUF_ImportFromString, text)
        if not ok then
            PrintProfileMessage("|cffff0000", "Import failed: " .. tostring(imported))
            return false
        end
        if imported ~= true then
            return false
        end
        if M.ClearHistory then M.ClearHistory() end
        M.RequestGeneralApply("MSUF2_PROFILE_IMPORT", { preview = true })
        RefreshAfterProfileChange(ctx)
        ShowImportReloadPrompt()
        return true
    end

    local function ImportIntoNewProfile(rawName)
        if BlockCombatAction() then return false end
        local text = blob:GetText()
        if not (text and text ~= "") then
            PrintProfileMessage("|cffff0000", "Import failed (empty string).")
            return false
        end
        local name = Trim(rawName or importProfileName:GetText())
        if not (name and name ~= "") then
            PrintProfileMessage("|cffff0000", "Enter a new profile name first.")
            return false
        end
        if ProfileExists(name) then
            PrintProfileMessage("|cffff0000", "Profile '" .. name .. "' already exists.")
            return false
        end
        if type(_G.MSUF_CreateProfile) ~= "function"
            or type(_G.MSUF_SwitchProfile) ~= "function"
            or type(_G.MSUF_ImportFromString) ~= "function"
        then
            PrintProfileMessage("|cffff0000", "Import failed: profile API is not available.")
            return false
        end

        local previous = _G.MSUF_ActiveProfile or "Default"
        pcall(_G.MSUF_CreateProfile, name)
        if not ProfileExists(name) then
            PrintProfileMessage("|cffff0000", "Import failed: could not create profile '" .. name .. "'.")
            return false
        end
        local previousExists = ProfileExists(previous)

        pcall(_G.MSUF_SwitchProfile, name)
        if _G.MSUF_ActiveProfile ~= name then
            if previousExists then pcall(_G.MSUF_SwitchProfile, previous) end
            DeleteCreatedProfile(name)
            PrintProfileMessage("|cffff0000", "Import failed: could not switch to profile '" .. name .. "'.")
            return false
        end

        local ok, imported = pcall(_G.MSUF_ImportFromString, text)
        if not ok or imported ~= true then
            if previousExists then pcall(_G.MSUF_SwitchProfile, previous) end
            DeleteCreatedProfile(name)
            PrintProfileMessage("|cffff0000", ok and "Import failed." or ("Import failed: " .. tostring(imported)))
            RefreshAfterProfileChange(ctx)
            return false
        end

        if M.ClearHistory then M.ClearHistory() end
        M.RequestGeneralApply("MSUF2_PROFILE_IMPORT_NEW", { preview = true })
        RefreshAfterProfileChange(ctx)
        importProfileName:SetText("")
        ReloadAfterNewProfileImport(name)
        return true
    end

    import:SetScript("OnClick", function()
        if M.profileImportCreateNew == true then
            ImportIntoNewProfile()
        else
            ImportIntoCurrent()
        end
    end)
    importProfileName:SetOnValueCommitted(function(value)
        if M.profileImportCreateNew == true then
            ImportIntoNewProfile(value)
        end
    end)
    importCreateNew:SetScript("OnClick", function(self)
        if BlockCombatAction() then
            self:SetChecked(M.profileImportCreateNew == true)
            return
        end
        M.profileImportCreateNew = not (M.profileImportCreateNew == true)
        self:SetChecked(M.profileImportCreateNew == true)
        if M.Refresh then M.Refresh(ctx) end
    end)
    local legacy = T.Button(io, "Legacy Import", 132, 24)
    legacy:SetScript("OnClick", function()
        if BlockCombatAction() then return end
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
    MoveWidget(importCreateNew, io, ioActionX, -144)
    MoveWidget(importProfileName, io, ioActionX, -178, 260)
    M.AddRefresher(ctx, function()
        local createNew = M.profileImportCreateNew == true
        importCreateNew:SetChecked(createNew)
        if import.SetText then
            import:SetText(createNew and "Import new profile" or "Import into current")
        end
        W.SetControlShown(importProfileName, createNew)
        if not createNew and importProfileName.HasFocus and importProfileName:HasFocus() then
            importProfileName:ClearFocus()
        end
    end)

    ctx:SetContentHeight(math.abs(b.y) + 42)
end

local function BuildModules(ctx)
    local b = W.PageBuilder(ctx)
    local head = b:Header("Modules", "Optional MSUF style and visual modules.", 64)
    if W.CreatePageResetButton then
        W.CreatePageResetButton(ctx, head, nil, { width = 88, y = -20 })
    end
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
    ctx:SetContentHeight(math.abs(b.y) + 42)
end

M.RegisterPage("profiles", { title = "MSUF Profiles", build = BuildProfiles, version = 5 })
M.RegisterPage("modules", { title = "MSUF Modules", build = BuildModules })
