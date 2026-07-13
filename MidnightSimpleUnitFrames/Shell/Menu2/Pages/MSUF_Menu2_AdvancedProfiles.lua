local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

-- Advanced Profiles page.
-- Builds profile copy/import/export/spec-switch controls and Wago/UUF import affordances.
-- Actual profile mutation stays in State/MSUF_Profiles.lua and import helpers.
local W = M.Widgets
local T = M.Theme
local AP = M.AdvancedPage or {}
local floor = math.floor
local max = math.max
local min = math.min
local CallGlobal, G, Gameplay, SetValue, LabelAt, ControlMeta, RegisterControl = M.Pick(AP, [[CallGlobal G Gameplay SetValue LabelAt ControlMeta RegisterControl]])
local PROFILE_SETTING_BY_PATH = {
    ["specialization.auto_switch.enabled"] = "profiles.specAutoSwitch",
}
local PROFILE_ACTION_BY_PATH = {
    ["active_profile.select"] = "switch_profile",
    ["profile.create"] = "create_profile",
    ["profile.copy_current"] = "copy_profile",
    ["profile.reset_current"] = "reset_profile",
    ["profile.delete_current"] = "delete_profile",
    ["export.generate"] = "export_profile",
    ["import.legacy"] = "import_legacy_profile_string",
    ["profiles.browse_wago"] = "copy_wago_profiles_link",
}
local function ProfilesMeta(path, classification, exact)
    local resolved = {}
    if type(exact) == "table" then
        for key, value in pairs(exact) do resolved[key] = value end
    end
    resolved.settingKey = resolved.settingKey or PROFILE_SETTING_BY_PATH[path]
    resolved.actionKey = resolved.actionKey or PROFILE_ACTION_BY_PATH[path]
    if path == "import.execute" and not resolved.actionKey then
        resolved.assistantDisposition = "dynamic"
        resolved.assistantDispositionReason = "The button routes to import_profile_string or import_profile_string_new from the explicit new-profile import mode."
    end
    return ControlMeta("profiles", "advanced", path, classification, resolved)
end
local function ModulesMeta(path, classification, exact)
    local resolved = {}
    if type(exact) == "table" then
        for key, value in pairs(exact) do resolved[key] = value end
    end
    if path == "style.enabled" then resolved.settingKey = resolved.settingKey or "general.styleEnabled" end
    return ControlMeta("modules", "advanced", path, classification, resolved)
end
local MoveWidget = W.MoveWidget or AP.MoveWidget
local Tr = M.TranslateText or M.Tr or function(text) return text end
local VT = M.ValueTextList
local WAGO_PROFILES_URL = "https://wago.io/search/imports/wow/msuf"
local function Trim(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end
local function IsUUFImportString(value)
    local fn = _G.MSUF_IsUUFImportString
    if type(fn) == "function" then
        local ok, result = pcall(fn, value)
        if ok then return result == true end
    end
    return type(value) == "string" and value:match("^%s*!UUF_") ~= nil
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
            if type(specID) == "number" and type(specName) == "string" then out[#out + 1] = { id = specID, name = specName } end
        end
    end
    return out
end
local function RefreshAfterProfileChange(ctx)
    if M.frame and M.frame.RefreshStatus then M.frame:RefreshStatus() end
    if M.RequestRefresh then M.RequestRefresh(ctx, "profiles-change") elseif M.Refresh then M.Refresh(ctx) end
end
local function ActiveProfileName() return _G.MSUF_ActiveProfile or "Default" end
local function CallMSUF(name, ...)
    local fn = _G[name]
    return type(fn) == "function" and pcall(fn, ...) or false
end
local function ClearProfileHistory() if M.ClearHistory then M.ClearHistory() end end
local function PrintProfileMessage(color, message)
    if M.ShowStatusFeedback then
        local kind = tostring(color or ""):find("ff0000", 1, true) and "danger" or "info"
        M.ShowStatusFeedback(tostring(message or ""), kind, kind == "danger" and 2.0 or 1.7)
    end
    print((color or "|cffffd700") .. "MSUF:|r " .. tostring(message or ""))
end
local function BlockCombatAction()
    if M.BlockCombatAction then return M.BlockCombatAction() and true or false end
    if type(_G.MSUF_BlockConfigCombatLocked) == "function" then return _G.MSUF_BlockConfigCombatLocked() and true or false end
    if _G.InCombatLockdown and _G.InCombatLockdown() then
        if type(_G.MSUF_ShowConfigCombatLockMessage) == "function" then _G.MSUF_ShowConfigCombatLockMessage() end
        return true
    end
    if _G.UnitAffectingCombat and _G.UnitAffectingCombat("player") then
        if type(_G.MSUF_ShowConfigCombatLockMessage) == "function" then _G.MSUF_ShowConfigCombatLockMessage() end
        return true
    end
    return false
end
local function StyleProfileInput(editBox, width, height, multiline)
    if not editBox then return editBox end
    local w = tonumber(width) or (editBox.GetWidth and editBox:GetWidth()) or 260
    local h = tonumber(height) or (editBox.GetHeight and editBox:GetHeight()) or 22
    editBox:SetSize(w, h)
    if editBox.SetMultiLine then editBox:SetMultiLine(multiline and true or false) end
    if editBox.SetJustifyV then editBox:SetJustifyV(multiline and "TOP" or "MIDDLE") end
    if editBox.SetTextInsets then
        if multiline then
            editBox:SetTextInsets(8, 8, 8, 8)
        else
            editBox:SetTextInsets(8, 8, 1, 1)
        end
    end
    if editBox._msuf2Title then
        editBox._msuf2Title:SetWidth(w)
        editBox._msuf2Title:SetTextColor(T.colors.text[1], T.colors.text[2], T.colors.text[3], 1)
    end
    if editBox._msuf2PaintEditBox then editBox:_msuf2PaintEditBox(false) end
    return editBox
end
local function InstallProfilePopup(key, spec)
    return M.InstallStaticPopup and M.InstallStaticPopup(key, spec)
end

-- Static popups are the safety boundary for destructive profile operations.
-- Keep the actual profile mutations inside the OnAccept handlers so callers cannot bypass
-- confirmation by invoking helper functions directly.
local function EnsureProfilePopups()
    if not _G.StaticPopupDialogs then return end
    InstallProfilePopup("MSUF2_IMPORT_RELOAD_PROMPT", {
        text = M.Tr("Profile imported into the current profile.\n\nReload the UI now so every imported setting is applied?"),
        button1 = _G.RELOAD or M.Tr("Reload"),
        button2 = _G.CANCEL or M.Tr("Not now"),
        OnAccept = function()
            if type(_G.ReloadUI) == "function" then _G.ReloadUI() end
        end,
    })
    InstallProfilePopup("MSUF2_CONFIRM_UUF_IMPORT_BEST_EFFORT", {
        text = M.Tr("This is an UnhaltedUnitFrames profile.\n\nMSUF will translate supported unit-frame, party/raid-frame, and aura settings as a best-effort import. Unsupported UUF-only settings may not map 1:1.\n\nImport anyway?"),
        button1 = M.Tr("Import"),
        button2 = _G.CANCEL or M.Tr("Cancel"),
        OnAccept = function(_, data)
            if BlockCombatAction() then return end
            if data and type(data.after) == "function" then data.after() end
        end,
    })
    InstallProfilePopup("MSUF2_UUF_RUNTIME_DEFERRED", {
        text = M.Tr("The UUF profile was converted and saved.\n\nUnhaltedUnitFrames is currently loaded, so MSUF cannot safely rebuild the live frames: both addons hook Blizzard frame parenting and would recurse.\n\nDisable UnhaltedUnitFrames in the AddOns list, then reload the UI."),
        button1 = _G.OKAY or M.Tr("Okay"),
    })
    InstallProfilePopup("MSUF2_CONFIRM_RESET_PROFILE", {
        text = M.Tr("Reset profile '%s' to defaults?\n\nThis resets the entire selected profile to the current MSUF factory defaults. Every menu in that profile will be affected."),
        button1 = YES or M.Tr("Yes"),
        button2 = NO or M.Tr("No"),
        OnAccept = function(_, data)
            if BlockCombatAction() then return end
            if not (data and data.name) then return end
            CallMSUF("MSUF_ResetProfile", data.name)
            ClearProfileHistory()
            if M.RequestGeneralApply then M.RequestGeneralApply("MSUF2_PROFILE_RESET", { preview = true, applyAll = false, notify = false }) end
            if type(data.after) == "function" then data.after() end
            CallMSUF("MSUF_ShowReloadRecommendedPopup", "Profile reset")
        end,
    })
    InstallProfilePopup("MSUF2_CONFIRM_DELETE_PROFILE", {
        text = M.Tr("Delete profile '%s'?\n\nThis removes the selected profile from MSUF. Other profiles are not affected, but this profile cannot be restored unless you exported or copied it first."),
        button1 = DELETE or M.Tr("Delete"),
        button2 = CANCEL or M.Tr("Cancel"),
        OnAccept = function(_, data)
            if BlockCombatAction() then return end
            if not (data and data.name) then return end
            CallMSUF("MSUF_DeleteProfile", data.name)
            ClearProfileHistory()
            if type(data.after) == "function" then data.after() end
        end,
    })
end
local function ConfirmUUFBestEffortImport(text, after)
    if not IsUUFImportString(text) then
        if type(after) == "function" then return after() end
        return false
    end
    if _G.StaticPopup_Show
        and _G.StaticPopupDialogs
        and _G.StaticPopupDialogs.MSUF2_CONFIRM_UUF_IMPORT_BEST_EFFORT
    then
        _G.StaticPopup_Show("MSUF2_CONFIRM_UUF_IMPORT_BEST_EFFORT", nil, nil, { after = after })
        return true
    end
    PrintProfileMessage("|cffff0000", "Import blocked: UUF best-effort confirmation is not available.")
    return false
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
local function ShowUUFDeferredPrompt()
    if _G.StaticPopup_Show and _G.StaticPopupDialogs and _G.StaticPopupDialogs.MSUF2_UUF_RUNTIME_DEFERRED then
        _G.StaticPopup_Show("MSUF2_UUF_RUNTIME_DEFERRED")
    else
        PrintProfileMessage("|cffffd700", "UUF profile saved. Disable UnhaltedUnitFrames, then reload the UI.")
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
    if type(profiles) == "table" then profiles[name] = nil end
end
local function BuildProfiles(ctx)
    local b = W.PageBuilder(ctx)
    EnsureProfilePopups()
    local contentW = ctx.width or 920
    local buttonW, buttonH, buttonGap = 190, 24, 14
    local buttonGridW = (buttonW * 2) + buttonGap
    local rightX = min(max(420, floor(contentW * 0.52)), max(360, contentW - buttonGridW - 28))
    local PROFILE_TOOLTIP = { hook = true, titleAsLine = true, bodyColor = { 0.85, 0.85, 0.85 } }
    local function AddProfileTooltip(frame, title, text) return M.AddTooltip and M.AddTooltip(frame, tostring(title or ""), text, PROFILE_TOOLTIP) or frame end
    local function PlaceActionRow(parent, x, left, right, y) left:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y); right:SetPoint("LEFT", left, "RIGHT", buttonGap, 0) end
    local function ProfileButton(parent, label, onClick, danger, semanticPath, confirmRequired, prepareValue, validateValue, directCommand)
        local btn = T.Button(parent, label, buttonW, buttonH)
        if danger and T.SkinDangerButton then T.SkinDangerButton(btn) end
        btn:SetScript("OnClick", onClick)
        local command = type(directCommand) == "table" and directCommand or nil
        if type(prepareValue) == "function" then
            command = {
                kind = "button",
                valueKind = "text",
                historyMode = "none",
                confirmRequired = confirmRequired == true,
                set = function(value)
                    local prepared = prepareValue(value)
                    local result = onClick(btn, "LeftButton", false)
                    if type(validateValue) == "function" then return validateValue(prepared, result) end
                    return result
                end,
            }
        end
        RegisterControl(btn, ProfilesMeta(semanticPath, "action", {
            confirmRequired = confirmRequired == true,
            historyMode = "none",
            command = command,
        }), label, "button")
        return btn
    end

    -- Profile switches rebuild live frames and can taint secure state in combat, so every
    -- entry point on this page goes through BlockCombatAction before touching profile APIs.
    local current = b:CollapsibleSection("profiles_management", "Profile Management", 238, true)
    local fieldW = min(360, max(300, rightX - 42))
    local profileDrop = W.Dropdown(current, "Active profile", {}, fieldW)
    RegisterControl(profileDrop, ProfilesMeta("active_profile.select", "action", { historyMode = "none" }), "Active profile", "dropdown", ProfileValues)
    local function RefreshProfileValues()
        profileDrop:SetValues(ProfileValues(false))
    end
    profileDrop:SetOnValueChanged(function(value)
        if BlockCombatAction() then
            profileDrop:SetValue(ActiveProfileName())
            return
        end
        if value and value ~= "" and value ~= _G.MSUF_ActiveProfile and CallMSUF("MSUF_SwitchProfile", value) then ClearProfileHistory() end
        M.RequestGeneralApply("MSUF2_PROFILE_SWITCH", { preview = true, applyAll = false, notify = false })
        RefreshAfterProfileChange(ctx)
    end)
    M.TrackRefresh(ctx, function()
        RefreshProfileValues()
        profileDrop:SetValue(ActiveProfileName())
    end)
    local nameInput = W.TextInput(current, "Profile name for create/copy", fieldW)
    M.BindTextInput(ctx, nameInput,
        function() return M.profileCreateCopyName or "" end,
        function(value) M.profileCreateCopyName = Trim(value or "") end,
        true,
        ProfilesMeta("draft.create_copy_name", "ephemeral"))
    local nameHelp = W.Text(current, "Type a name here before creating or copying a profile.", 14, -158, fieldW, T.colors.muted)
    if nameHelp and nameHelp.SetWordWrap then nameHelp:SetWordWrap(true) end
    local create = ProfileButton(current, "Create profile", function()
        if BlockCombatAction() then return end
        local name = Trim(nameInput:GetText())
        if name and name ~= "" and CallMSUF("MSUF_CreateProfile", name) then
            CallMSUF("MSUF_SwitchProfile", name)
            ClearProfileHistory()
        end
        M.profileCreateCopyName = ""
        nameInput:SetText("")
        RefreshAfterProfileChange(ctx)
    end, nil, "profile.create", false, function(value)
        local name = Trim(value)
        local prepared = { name = name, existed = name ~= "" and ProfileExists(name) or false }
        if name ~= "" then M.profileCreateCopyName = name; nameInput:SetText(name) end
        return prepared
    end, function(prepared)
        return type(prepared) == "table" and prepared.name ~= "" and not prepared.existed and ProfileExists(prepared.name)
    end)
    local copy = ProfileButton(current, "Copy current to name", function()
        if BlockCombatAction() then return end
        local name = Trim(nameInput:GetText())
        if name and name ~= "" then
            local ok, copied = CallMSUF("MSUF_CopyProfile", ActiveProfileName(), name)
            if ok and copied then CallMSUF("MSUF_SwitchProfile", name) end
            if ok then ClearProfileHistory() end
            M.profileCreateCopyName = ""
            nameInput:SetText("")
            RefreshAfterProfileChange(ctx)
        end
    end, nil, "profile.copy_current", false, function(value)
        local name = Trim(value)
        local prepared = { name = name, existed = name ~= "" and ProfileExists(name) or false }
        if name ~= "" then M.profileCreateCopyName = name; nameInput:SetText(name) end
        return prepared
    end, function(prepared)
        return type(prepared) == "table" and prepared.name ~= "" and not prepared.existed and ProfileExists(prepared.name)
    end)
    local reset = ProfileButton(current, "Reset current profile", function()
        if BlockCombatAction() then return end
        if M.ShowPageResetConfirm then
            M.ShowPageResetConfirm("profiles")
            return
        end
        local name = ActiveProfileName()
        if _G.StaticPopup_Show and _G.StaticPopupDialogs and _G.StaticPopupDialogs.MSUF2_CONFIRM_RESET_PROFILE then
            _G.StaticPopup_Show("MSUF2_CONFIRM_RESET_PROFILE", name, nil, { name = name, after = function() RefreshAfterProfileChange(ctx) end })
        elseif CallMSUF("MSUF_ResetProfile", name) then
            ClearProfileHistory()
            RefreshAfterProfileChange(ctx)
        end
    end, nil, "profile.reset_current", true, nil, nil, {
        kind = "button", historyMode = "none", confirmRequired = true,
        set = function()
            if BlockCombatAction() then return false end
            -- The Assistant already supplied the explicit destructive-action
            -- confirmation. Execute the same reset/apply/reload path used by
            -- the menu popup instead of bypassing its post-reset work.
            if type(M.ResetPageToDefaults) == "function" then
                local ok, result = pcall(M.ResetPageToDefaults, "profiles")
                if not ok or result ~= true then return false end
                RefreshAfterProfileChange(ctx)
                return true
            end
            local ok, result = CallMSUF("MSUF_ResetProfile", ActiveProfileName())
            if not ok or result == false then return false end
            ClearProfileHistory()
            RefreshAfterProfileChange(ctx)
            return true
        end,
    })
    local delete = ProfileButton(current, "Delete current profile", function()
        if BlockCombatAction() then return end
        local name = ActiveProfileName()
        if name == "Default" then return end
        if _G.StaticPopup_Show and _G.StaticPopupDialogs and _G.StaticPopupDialogs.MSUF2_CONFIRM_DELETE_PROFILE then
            _G.StaticPopup_Show("MSUF2_CONFIRM_DELETE_PROFILE", name, nil, { name = name, after = function() RefreshAfterProfileChange(ctx) end })
        elseif CallMSUF("MSUF_DeleteProfile", name) then
            ClearProfileHistory()
            RefreshAfterProfileChange(ctx)
        end
    end, true, "profile.delete_current", true, nil, nil, {
        kind = "button", historyMode = "none", confirmRequired = true,
        set = function()
            if BlockCombatAction() then return false end
            local name = ActiveProfileName()
            if name == "Default" then return false end
            local ok, result = CallMSUF("MSUF_DeleteProfile", name)
            if not ok or result == false then return false end
            ClearProfileHistory()
            RefreshAfterProfileChange(ctx)
            return true
        end,
    })
    MoveWidget(profileDrop, current, 14, -42, fieldW)
    MoveWidget(nameInput, current, 14, -104, fieldW)
    StyleProfileInput(nameInput, fieldW, 24, false)
    W.LabelAt(current, "Profile actions", rightX, -42, buttonGridW, "GameFontNormalSmall", T.colors.text)
    PlaceActionRow(current, rightX, create, copy, -70)
    PlaceActionRow(current, rightX, reset, delete, -110)
    M.TrackRefresh(ctx, function()
        if delete.SetEnabled then delete:SetEnabled(ActiveProfileName() ~= "Default") end
    end)
    local specs = GetSpecMeta()
    local specRows = max(1, math.ceil((#specs > 0 and #specs or 1) / 2))

    -- Spec-profile rows depend on WoW specialization APIs. The empty-state path keeps the
    -- page usable for low-level characters and offline smoke tests where those APIs are nil.
    local spec = b:CollapsibleSection("profiles_specs", "Spec Profiles", 120 + (specRows * 58), true)
    local auto = W.SwitchAt(spec, "Auto-switch profile by specialization", 14, -38, 360)
    M.BindBoolWidget(ctx, auto,
        function()
            return type(_G.MSUF_IsSpecAutoSwitchEnabled) == "function" and _G.MSUF_IsSpecAutoSwitchEnabled() or false
        end,
        function(v)
            CallMSUF("MSUF_SetSpecAutoSwitchEnabled", v and true or false)
            RefreshAfterProfileChange(ctx)
        end,
        ProfilesMeta("specialization.auto_switch.enabled"))
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
            M.BindDropdownWidget(ctx, drop,
                function()
                    if type(_G.MSUF_GetSpecProfile) == "function" then return _G.MSUF_GetSpecProfile(s.id) or "None" end
                    return "None"
                end,
                function(v)
                    CallMSUF("MSUF_SetSpecProfile", s.id, (v ~= "None") and v or nil)
                    RefreshAfterProfileChange(ctx)
                end,
                ProfilesMeta("specialization.mapping.slot." .. tostring(i), "action", {
                    actionKey = "set_spec_profile",
                }))
        end
    end
    local io = b:CollapsibleSection("profiles_io", "Export / Import", 424, false)

    -- Import/export shares one text box intentionally: exporting fills the field, importing
    -- consumes it, and tests can exercise both paths without clipboard APIs.
    local ioActionX = min(max(380, floor(contentW * 0.46)), max(340, contentW - 460))
    local ioLeftW = max(320, min(620, ioActionX - 28))
    local exportKind = W.Dropdown(io, "Export kind", VT("all", "Full profile", "unitframe", "Unitframes", "castbar", "Castbars", "colors", "Colors", "gameplay", "Gameplay", "groupframe", "Group Frames"), 240)
    M.BindDropdownWidget(ctx, exportKind,
        function() return M.profileExportKind or "all" end,
        function(v)
            M.SetMenuStateValue("profileExportKind", v or "all")
        end,
        ProfilesMeta("export.kind", "ephemeral"))
    local blob = W.TextInput(io, "Profile string", 640)
    blob._msuf2CommitOnBlur = false
    M.BindTextInput(ctx, blob,
        function() return M.profileImportString or "" end,
        function(value) M.profileImportString = tostring(value or "") end,
        false,
        ProfilesMeta("import_export.buffer", "ephemeral"))
    local export = ProfileButton(io, "Export", function()
        local fn = _G.MSUF_ExportSelectionToString
        if type(fn) == "function" then
            local ok, value = pcall(fn, M.profileExportKind or "all")
            if ok and type(value) == "string" then
                M.profileImportString = value
                blob:SetText(value)
                blob:HighlightText()
                if M.ShowStatusFeedback then M.ShowStatusFeedback("Profile string exported", "ok", 1.5) end
            elseif M.ShowStatusFeedback then
                M.ShowStatusFeedback("Export failed", "danger", 1.8)
            end
        elseif M.ShowStatusFeedback then
            M.ShowStatusFeedback("Export unavailable", "danger", 1.8)
        end
    end, nil, "export.generate")
    local importCreateNew, importProfileName
    local import = T.Button(io, "Import to current profile", buttonW, buttonH)
    RegisterControl(import, ProfilesMeta("import.execute", "action", {
        confirmRequired = true,
        historyMode = "none",
        command = {
            kind = "button",
            valueKind = "text",
            historyMode = "none",
            confirmRequired = true,
            set = function(value)
                local payload, newName
                if type(value) == "table" then
                    payload, newName = Trim(value.payload), Trim(value.profileName)
                else
                    payload = Trim(value)
                end
                if payload ~= "" then M.profileImportString = payload; blob:SetText(payload) end
                if newName and newName ~= "" then
                    M.profileImportCreateNew = true
                    M.profileImportNewName = newName
                    if importCreateNew then importCreateNew:SetChecked(true) end
                    if importProfileName then importProfileName:SetText(newName) end
                end
                local handler = import:GetScript("OnClick")
                if type(handler) == "function" then return handler(import, "LeftButton", false) end
            end,
        },
    }), "Import to current profile", "button")
    AddProfileTooltip(import, "Import to current profile", "Applies the import string to the active profile. Export or copy your profile first if you want an easy backup.")
    importCreateNew = W.SwitchAt(io, "Import and create new profile", ioActionX, -154, 300)
    RegisterControl(importCreateNew, ProfilesMeta("import.create_new_mode", "ephemeral"), "Import and create new profile", "toggle")
    AddProfileTooltip(importCreateNew, "Import and create new profile", "Creates a separate profile before importing so you can test the import without changing your current profile.")
    importProfileName = W.TextInput(io, "New profile name", 260)
    RegisterControl(importProfileName, ProfilesMeta("import.new_profile_name", "ephemeral"), "New profile name", "textinput")
    importProfileName._msuf2CommitOnBlur = false
    M.TrackRefresh(ctx, function()
        if importProfileName:HasFocus() then return end
        importProfileName:SetText(tostring(M.profileImportNewName or ""))
    end)
    local function ImportTextOrFail()
        if BlockCombatAction() then return nil end
        local text = blob:GetText()
        if text and text ~= "" then return text end
        PrintProfileMessage("|cffff0000", "Import failed (empty string).")
    end
    local function ImportIntoCurrent()
        local text = ImportTextOrFail()
        if not text then return false end
        if type(_G.MSUF_ImportFromString) ~= "function" then
            PrintProfileMessage("|cffff0000", "Import failed: profile import API is not available.")
            return false
        end
        return ConfirmUUFBestEffortImport(text, function()
            local ok, imported = pcall(_G.MSUF_ImportFromString, text)
            if not ok then
                PrintProfileMessage("|cffff0000", "Import failed: " .. tostring(imported))
                return false
            end
            if imported ~= true then return false end
            ClearProfileHistory()
            if _G.MSUF_ProfileIO_LastImportDeferredRuntime == true then
                RefreshAfterProfileChange(ctx)
                ShowUUFDeferredPrompt()
                return true
            end
            M.RequestGeneralApply("MSUF2_PROFILE_IMPORT", { preview = true, applyAll = false, notify = false })
            RefreshAfterProfileChange(ctx)
            ShowImportReloadPrompt()
            return true
        end)
    end
    local function ImportIntoNewProfile(rawName)
        local text = ImportTextOrFail()
        if not text then return false end
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

        -- New-profile import is transactional at the SavedVariables level: create, switch,
        -- import, then roll back the created profile if any required step fails.
        return ConfirmUUFBestEffortImport(text, function()
            local previous = ActiveProfileName()
            CallMSUF("MSUF_CreateProfile", name)
            if not ProfileExists(name) then
                PrintProfileMessage("|cffff0000", "Import failed: could not create profile '" .. name .. "'.")
                return false
            end
            local previousExists = ProfileExists(previous)
            CallMSUF("MSUF_SwitchProfile", name)
            if _G.MSUF_ActiveProfile ~= name then
                if previousExists then CallMSUF("MSUF_SwitchProfile", previous) end
                DeleteCreatedProfile(name)
                PrintProfileMessage("|cffff0000", "Import failed: could not switch to profile '" .. name .. "'.")
                return false
            end
            local ok, imported = pcall(_G.MSUF_ImportFromString, text)
            if not ok or imported ~= true then
                if previousExists then CallMSUF("MSUF_SwitchProfile", previous) end
                DeleteCreatedProfile(name)
                PrintProfileMessage("|cffff0000", ok and "Import failed." or ("Import failed: " .. tostring(imported)))
                RefreshAfterProfileChange(ctx)
                return false
            end
            ClearProfileHistory()
            if _G.MSUF_ProfileIO_LastImportDeferredRuntime == true then
                RefreshAfterProfileChange(ctx)
                M.profileImportNewName = ""
                importProfileName:SetText("")
                ShowUUFDeferredPrompt()
                return true
            end
            M.RequestGeneralApply("MSUF2_PROFILE_IMPORT_NEW", { preview = true, applyAll = false, notify = false })
            RefreshAfterProfileChange(ctx)
            M.profileImportNewName = ""
            importProfileName:SetText("")
            ReloadAfterNewProfileImport(name)
            return true
        end)
    end
    import:SetScript("OnClick", function()
        if M.profileImportCreateNew == true then
            return ImportIntoNewProfile()
        else
            return ImportIntoCurrent()
        end
    end)
    importProfileName:SetOnValueCommitted(function(value)
        M.profileImportNewName = Trim(value or "")
        if M.profileImportCreateNew == true then ImportIntoNewProfile(value) end
    end)
    importCreateNew:SetScript("OnClick", function(self)
        if BlockCombatAction() then
            self:SetChecked(M.profileImportCreateNew == true)
            return
        end
        M.SetMenuStateValue("profileImportCreateNew", not (M.profileImportCreateNew == true))
        self:SetChecked(M.profileImportCreateNew == true)
        if M.ShowStatusFeedback then M.ShowStatusFeedback(M.profileImportCreateNew == true and "New-profile import on" or "New-profile import off", "info", 1.2) end
        if M.RequestRefresh then M.RequestRefresh(ctx, "profiles-import-mode") elseif M.Refresh then M.Refresh(ctx) end
    end)
    local legacy = ProfileButton(io, "Import Legacy", function()
        if BlockCombatAction() then return end
        local text = blob:GetText()
        if text and text ~= "" and type(_G.MSUF_ImportLegacyFromString) == "function" then
            ConfirmUUFBestEffortImport(text, function()
                CallMSUF("MSUF_ImportLegacyFromString", text)
                ClearProfileHistory()
                M.RequestGeneralApply("MSUF2_PROFILE_LEGACY_IMPORT", { preview = true, applyAll = false, notify = false })
                RefreshAfterProfileChange(ctx)
                if M.ShowStatusFeedback then M.ShowStatusFeedback("Legacy profile imported", "ok", 1.7) end
            end)
        elseif M.ShowStatusFeedback then
            M.ShowStatusFeedback("Legacy import unavailable", "danger", 1.8)
        end
    end, nil, "import.legacy", true)
    local wago = ProfileButton(io, "Browse Wago Profiles", function()
        if not CallMSUF("MSUF_ShowCopyLink", "Wago MSUF Profiles", WAGO_PROFILES_URL) then
            blob:SetText(WAGO_PROFILES_URL)
            blob:HighlightText()
        end
    end, nil, "profiles.browse_wago")
    MoveWidget(exportKind, io, 14, -42, 260)
    MoveWidget(blob, io, 14, -104, ioLeftW)
    StyleProfileInput(blob, ioLeftW, 168, true)
    W.LabelAt(io, "Actions", ioActionX, -42, buttonGridW, "GameFontNormalSmall", T.colors.text)
    PlaceActionRow(io, ioActionX, export, import, -70)
    PlaceActionRow(io, ioActionX, legacy, wago, -110)
    MoveWidget(importProfileName, io, ioActionX, -202, 300)
    StyleProfileInput(importProfileName, 300, 24, false)
    W.Text(io, "Importing to the current profile changes the active profile. To test safely, enable new-profile import or copy/export your profile first.", ioActionX, -250, max(260, contentW - ioActionX - 28), T.colors.muted)
    M.TrackRefresh(ctx, function()
        local createNew = M.profileImportCreateNew == true
        importCreateNew:SetChecked(createNew)
        if import.SetText then import:SetText(createNew and "Import new profile" or "Import to current profile") end
        W.SetControlShown(importProfileName, createNew)
        if not createNew and importProfileName.HasFocus and importProfileName:HasFocus() then importProfileName:ClearFocus() end
    end)
    ctx:SetContentHeight(math.abs(b.y) + 42)
end
local function BuildModules(ctx)
    local b = W.PageBuilder(ctx)
    local head = b:Header("Modules", "Optional MSUF style and visual modules.", 64)
    local style = b:CollapsibleSection("modules_style", "Style", 96, true)
    local enable = W.SwitchAt(style, "MSUF Style", 14, -38, 220)
    M.BindBoolWidget(ctx, enable,
        function()
            local ok, v = CallMSUF("MSUF_StyleIsEnabled")
            if ok then return v and true or false end
            return G().styleEnabled ~= false
        end,
        function(v)
            CallMSUF("MSUF_SetStyleEnabled", v and true or false)
            G().styleEnabled = v and true or false
            CallGlobal("MSUF_ApplyModules")
        end,
        ModulesMeta("style.enabled"))
    ctx:SetContentHeight(math.abs(b.y) + 42)
end
M.RegisterPage("profiles", { title = "MSUF Profiles", build = BuildProfiles, version = 5 })
M.RegisterPage("modules", { title = "MSUF Modules", build = BuildModules })
