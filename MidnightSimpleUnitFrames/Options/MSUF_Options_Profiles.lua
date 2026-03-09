-- ---------------------------------------------------------------------------
-- MSUF_Options_Profiles.lua  (Phase 9: Rewrite using ns.UI.*)
--
-- Profile management: create, delete, copy, reset, import/export,
-- spec-based auto-switch.
-- ---------------------------------------------------------------------------
local addonName, ns = ...
local TR = ns.TR
local UI = ns.UI
local EnsureDB = ns.EnsureDB

function ns.MSUF_Options_Profiles_Build(panel, profileGroup, ctx)
    if not panel or not profileGroup then return end
    if profileGroup._msufBuilt then return end
    profileGroup._msufBuilt = true

    local SkinBtn = _G.MSUF_SkinMidnightActionButton
    local function Skin(btn)
        if SkinBtn then SkinBtn(btn, { textR = 1, textG = 0.85, textB = 0.1 }) end
    end

    ---------------------------------------------------------------------------
    -- StaticPopup dialogs
    ---------------------------------------------------------------------------
    StaticPopupDialogs["MSUF_CONFIRM_RESET_PROFILE"] = {
        text = "Reset current profile to defaults?",
        button1 = YES, button2 = NO, timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        OnAccept = function(self, data)
            if data and data.name and data.panel then
                MSUF_ResetProfile(data.name)
                if data.panel.LoadFromDB then data.panel:LoadFromDB() end
                if data.panel.UpdateProfileUI then data.panel:UpdateProfileUI(data.name) end
            end
        end,
    }
    StaticPopupDialogs["MSUF_CONFIRM_DELETE_PROFILE"] = {
        text = "Are you sure you want to delete '%s'?",
        button1 = YES, button2 = NO, timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        OnAccept = function(self, data)
            if data and data.name and data.panel then
                MSUF_DeleteProfile(data.name)
                data.panel:UpdateProfileUI(MSUF_ActiveProfile)
            end
        end,
    }
    StaticPopupDialogs["MSUF_COPY_PROFILE_INPUT"] = {
        text = "Copy profile '%s' to new name:",
        button1 = "Copy", button2 = CANCEL, hasEditBox = true,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        OnAccept = function(self, data)
            local eb = self.editBox or self.EditBox
            if not (eb and eb.GetText) then return end
            local newName = (eb:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if newName == "" then return end
            if data and data.source and data.panel then
                if type(MSUF_CopyProfile) == "function" then
                    local ok = MSUF_CopyProfile(data.source, newName)
                    if ok then MSUF_SwitchProfile(newName); data.panel:UpdateProfileUI(newName) end
                end
            end
        end,
        EditBoxOnEnterPressed = function(self) local p = self:GetParent(); if p.button1 then p.button1:Click() end end,
        EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
        OnShow = function(self) local eb = self.editBox or self.EditBox; if eb then eb:SetText(""); eb:SetFocus() end end,
    }

    ---------------------------------------------------------------------------
    -- Header + action buttons
    ---------------------------------------------------------------------------
    local title = profileGroup:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", profileGroup, "TOPLEFT", 16, -140)
    title:SetText(TR("Profiles"))

    local _, btns = UI.ButtonRow(profileGroup, title, 8, {
        { id = "reset",  name = "MSUF_ProfileResetButton",  text = "Reset profile",  w = 140, h = 24, y = 10 },
        { id = "delete", name = "MSUF_ProfileDeleteButton", text = "Delete profile", w = 140, h = 24 },
        { id = "copy",   name = "MSUF_ProfileCopyButton",   text = "Copy profile",   w = 140, h = 24 },
    })
    local resetBtn  = btns.reset
    local deleteBtn = btns.delete
    local copyBtn   = btns.copy
    Skin(resetBtn); Skin(deleteBtn); Skin(copyBtn)

    -- Hidden label for internal profile name tracking
    local currentProfileLabel = profileGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    currentProfileLabel:Hide()

    local helpText = profileGroup:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    helpText:SetPoint("TOPLEFT", resetBtn, "BOTTOMLEFT", 0, -8)
    helpText:SetWidth(540); helpText:SetJustifyH("LEFT")
    helpText:SetText(TR("Profiles are global. Each character selects one active profile. Create a new profile on the left or select an existing one on the right."))

    ---------------------------------------------------------------------------
    -- Spec-based auto-switch
    ---------------------------------------------------------------------------
    local specAutoCB = UI.Check({
        name = "MSUF_ProfileSpecAutoSwitchCB", parent = profileGroup,
        template = "ChatConfigCheckButtonTemplate",
        anchor = helpText, x = 0, y = -12,
        label = TR("Auto-switch profile by specialization"),
        get = function()
            return type(_G.MSUF_IsSpecAutoSwitchEnabled) == "function" and _G.MSUF_IsSpecAutoSwitchEnabled()
        end,
        set = function(v)
            if type(_G.MSUF_SetSpecAutoSwitchEnabled) == "function" then _G.MSUF_SetSpecAutoSwitchEnabled(v) end
        end,
    })

    local specRows = {}
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

    local function ProfileExists(name)
        if type(name) ~= "string" or name == "" then return false end
        local list = type(_G.MSUF_GetAllProfiles) == "function" and _G.MSUF_GetAllProfiles() or {}
        for _, n in ipairs(list) do if n == name then return true end end
        return false
    end

    local function EnsureSpecRows()
        if #specRows > 0 then return end
        local meta = GetSpecMeta()
        local anchor = specAutoCB
        for i, s in ipairs(meta) do
            local row = {}
            row.label = profileGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            row.label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -10)
            row.label:SetText(s.name)

            row.drop = UI.Dropdown({
                name = "MSUF_ProfileSpecDrop" .. i, parent = profileGroup,
                anchor = row.label, anchorPoint = "TOPLEFT", x = 210, y = 2, width = 180,
                items = function()
                    local out = { { key = "None", label = "None" } }
                    local profiles = type(_G.MSUF_GetAllProfiles) == "function" and _G.MSUF_GetAllProfiles() or {}
                    for _, name in ipairs(profiles) do
                        out[#out + 1] = { key = name, label = name }
                    end
                    return out
                end,
                get = function()
                    local cur = type(_G.MSUF_GetSpecProfile) == "function" and _G.MSUF_GetSpecProfile(s.id) or nil
                    return cur or "None"
                end,
                set = function(v)
                    if type(_G.MSUF_SetSpecProfile) == "function" then
                        _G.MSUF_SetSpecProfile(s.id, v ~= "None" and v or nil)
                    end
                end,
            })

            specRows[#specRows + 1] = row
            anchor = row.label
        end
        profileGroup._msufProfilesAfterSpecAnchor = anchor
    end

    local function UpdateSpecUI()
        EnsureSpecRows()
        for _, row in ipairs(specRows) do
            if row.drop and row.drop.Refresh then row.drop:Refresh() end
        end
    end

    panel._msufUpdateSpecProfileUI = UpdateSpecUI
    UpdateSpecUI()

    ---------------------------------------------------------------------------
    -- New / Existing profile row
    ---------------------------------------------------------------------------
    local newLabel = profileGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    newLabel:SetPoint("TOPLEFT", profileGroup._msufProfilesAfterSpecAnchor or specAutoCB, "BOTTOMLEFT", 0, -14)
    newLabel:SetText(TR("New"))

    local existingLabel = profileGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    existingLabel:SetPoint("LEFT", newLabel, "LEFT", 260, 0)
    existingLabel:SetText(TR("Existing profiles"))

    local newEditBox = CreateFrame("EditBox", "MSUF_ProfileNewEdit", profileGroup, "InputBoxTemplate")
    newEditBox:SetSize(220, 20); newEditBox:SetAutoFocus(false)
    newEditBox:SetPoint("TOPLEFT", newLabel, "BOTTOMLEFT", 0, -4)

    local profileDrop = UI.Dropdown({
        name = "MSUF_ProfileDropdown", parent = profileGroup,
        anchor = existingLabel, x = -16, y = -4, width = 200,
        items = function()
            local profiles = type(MSUF_GetAllProfiles) == "function" and MSUF_GetAllProfiles() or { "Default" }
            local out = {}
            for _, name in ipairs(profiles) do out[#out + 1] = { key = name, label = name } end
            return out
        end,
        get = function() return MSUF_ActiveProfile or "Default" end,
        set = function(v)
            MSUF_SwitchProfile(v)
            currentProfileLabel:SetText("Current profile: " .. v)
            if panel._msufUpdateSpecProfileUI then panel._msufUpdateSpecProfileUI() end
        end,
    })

    ---------------------------------------------------------------------------
    -- UpdateProfileUI (used by popups + CRUD)
    ---------------------------------------------------------------------------
    function panel:UpdateProfileUI(currentName)
        local name = currentName or MSUF_ActiveProfile or "Default"
        currentProfileLabel:SetText("Current profile: " .. name)
        if profileDrop and profileDrop.SetValue then profileDrop:SetValue(name) end
        if self._msufUpdateSpecProfileUI then self._msufUpdateSpecProfileUI() end
        if deleteBtn and deleteBtn.SetEnabled then deleteBtn:SetEnabled(name ~= "Default") end
    end

    ---------------------------------------------------------------------------
    -- Button scripts
    ---------------------------------------------------------------------------
    newEditBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        local name = (self:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if name ~= "" then
            MSUF_CreateProfile(name); MSUF_SwitchProfile(name)
            self:SetText(""); panel:UpdateProfileUI(name)
        end
    end)

    resetBtn:SetScript("OnClick", function()
        if not MSUF_ActiveProfile then return end
        StaticPopup_Show("MSUF_CONFIRM_RESET_PROFILE", MSUF_ActiveProfile, nil, { name = MSUF_ActiveProfile, panel = panel })
    end)

    deleteBtn:SetScript("OnClick", function()
        if not MSUF_ActiveProfile or MSUF_ActiveProfile == "Default" then return end
        StaticPopup_Show("MSUF_CONFIRM_DELETE_PROFILE", MSUF_ActiveProfile, nil, { name = MSUF_ActiveProfile, panel = panel })
    end)

    copyBtn:SetScript("OnClick", function()
        if not MSUF_ActiveProfile then return end
        StaticPopup_Show("MSUF_COPY_PROFILE_INPUT", MSUF_ActiveProfile, nil, { source = MSUF_ActiveProfile, panel = panel })
    end)

    ---------------------------------------------------------------------------
    -- Import / Export
    ---------------------------------------------------------------------------
    local profileLine = profileGroup:CreateTexture(nil, "ARTWORK")
    profileLine:SetColorTexture(1, 1, 1, 0.18)
    profileLine:SetPoint("TOPLEFT", newEditBox, "BOTTOMLEFT", 0, -20)
    profileLine:SetSize(540, 1)

    local importTitle = profileGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    importTitle:SetPoint("TOPLEFT", profileLine, "BOTTOMLEFT", 0, -10)
    importTitle:SetText(TR("Profile export / import"))

    -- Simple dialog factory
    local function MakeDialog(name, titleText, w, h)
        local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
        f:SetFrameStrata("DIALOG"); f:SetClampedToScreen(true); f:SetSize(w or 520, h or 96); f:SetPoint("CENTER")
        f:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
        f:SetBackdropColor(0, 0, 0, 0.92)
        f._title = f:CreateFontString(nil, "ARTWORK", "GameFontNormal"); f._title:SetPoint("TOP", 0, -8); f._title:SetText(titleText or "")
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", -2, -2); close:SetScript("OnClick", function() f:Hide() end)
        f:Hide()
        return f
    end

    -- Copy popup (Ctrl+C)
    local copyPopup, copyEdit
    local function ShowCopyPopup(str)
        if not copyPopup then
            copyPopup = MakeDialog("MSUF_ProfileCopyPopup", "Ctrl+C to copy", 560, 96)
            copyEdit = CreateFrame("EditBox", nil, copyPopup, "InputBoxTemplate")
            copyEdit:SetAutoFocus(true); copyEdit:SetSize(500, 22); copyEdit:SetPoint("TOP", copyPopup, "TOP", 0, -36)
            copyEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus(); copyPopup:Hide() end)
            local done = CreateFrame("Button", nil, copyPopup, "UIPanelButtonTemplate")
            done:SetSize(90, 22); done:SetPoint("BOTTOM", 0, 10); done:SetText(TR("Done")); Skin(done)
            done:SetScript("OnClick", function() copyPopup:Hide() end)
            copyPopup:SetScript("OnShow", function() if copyEdit then copyEdit:HighlightText() end end)
        end
        copyEdit:SetText(str or ""); copyEdit:HighlightText(); copyPopup:Show(); copyEdit:SetFocus()
    end

    -- Import popup (Ctrl+V)
    local importPopup, importEdit
    local function ShowImportPopup(mode)
        mode = (mode == "legacy") and "legacy" or "new"
        if not importPopup then
            importPopup = MakeDialog("MSUF_ProfileImportPopup", "Ctrl+V to paste", 560, 110)
            importEdit = CreateFrame("EditBox", nil, importPopup, "InputBoxTemplate")
            importEdit:SetAutoFocus(true); importEdit:SetSize(500, 22); importEdit:SetPoint("TOP", importPopup, "TOP", 0, -36)
            importEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus(); importPopup:Hide() end)
            local doBtn = CreateFrame("Button", nil, importPopup, "UIPanelButtonTemplate")
            doBtn:SetSize(110, 22); doBtn:SetPoint("BOTTOM", importPopup, "BOTTOM", -60, 10); doBtn:SetText(TR("Import")); Skin(doBtn)
            local cancel = CreateFrame("Button", nil, importPopup, "UIPanelButtonTemplate")
            cancel:SetSize(110, 22); cancel:SetPoint("LEFT", doBtn, "RIGHT", 10, 0); cancel:SetText(TR("Cancel")); Skin(cancel)
            cancel:SetScript("OnClick", function() importPopup:Hide() end)
            local function RunImport()
                local str = importEdit and importEdit:GetText() or ""
                local Importer = importPopup._mode == "legacy"
                    and (_G.MSUF_ImportLegacyFromString or ns.MSUF_ImportLegacyFromString)
                    or  (_G.MSUF_ImportFromString or ns.MSUF_ImportFromString)
                if type(Importer) ~= "function" then print("|cffff0000MSUF:|r Import failed: importer missing."); return end
                Importer(str)
                if type(ApplyAllSettings) == "function" then ApplyAllSettings() end
                if type(_G.MSUF_CallUpdateAllFonts) == "function" then _G.MSUF_CallUpdateAllFonts() end
                if panel.LoadFromDB then panel:LoadFromDB() end
                if panel.UpdateProfileUI then panel:UpdateProfileUI(MSUF_ActiveProfile) end
                importPopup:Hide()
            end
            doBtn:SetScript("OnClick", RunImport)
            importEdit:SetScript("OnEnterPressed", RunImport)
        end
        importPopup._mode = mode
        importPopup._title:SetText(mode == "legacy" and TR("Ctrl+V to paste (Legacy Import)") or TR("Ctrl+V to paste"))
        importEdit:SetText(""); importPopup:Show(); importEdit:SetFocus()
    end

    -- Import/Export/Legacy buttons
    local importBtn = UI.Button({ parent = profileGroup, text = TR("Import"), width = 110, height = 22, anchor = importTitle, y = -12,
        onClick = function() ShowImportPopup("new") end })
    local exportBtn = UI.Button({ parent = profileGroup, text = TR("Export"), width = 110, height = 22 })
    exportBtn:ClearAllPoints(); exportBtn:SetPoint("LEFT", importBtn, "RIGHT", 8, 0)
    local legacyBtn = UI.Button({ parent = profileGroup, text = TR("Legacy Import"), width = 120, height = 22 })
    legacyBtn:ClearAllPoints(); legacyBtn:SetPoint("LEFT", exportBtn, "RIGHT", 8, 0)
    Skin(importBtn); Skin(exportBtn); Skin(legacyBtn)
    legacyBtn:SetScript("OnClick", function() ShowImportPopup("legacy") end)

    ---------------------------------------------------------------------------
    -- Export picker popup
    ---------------------------------------------------------------------------
    local exportPickerPopup
    local function ShowExportPicker()
        if exportPickerPopup and exportPickerPopup:IsShown() then exportPickerPopup:Hide(); return end
        if not exportPickerPopup then
            exportPickerPopup = MakeDialog("MSUF_ProfileExportPicker", "What to export?", 420, 86)
            local function makeBtn(text)
                local b = CreateFrame("Button", nil, exportPickerPopup, "UIPanelButtonTemplate")
                b:SetSize(120, 22); b:SetText(text); Skin(b); return b
            end
            local function doExport(kind)
                local Exporter = _G.MSUF_ExportSelectionToString or ns.MSUF_ExportSelectionToString
                if type(Exporter) ~= "function" then print("|cffff0000MSUF:|r Export failed."); exportPickerPopup:Hide(); return end
                ShowCopyPopup(Exporter(kind) or ""); exportPickerPopup:Hide()
                print("|cff00ff00MSUF:|r Exported " .. tostring(kind) .. " settings.")
            end
            local bUnit = makeBtn("Unitframes"); bUnit:SetPoint("BOTTOMLEFT", 10, 10)
            local bCast = makeBtn("Castbars");   bCast:SetPoint("LEFT", bUnit, "RIGHT", 8, 0)
            local bCol  = makeBtn("Colors");     bCol:SetPoint("LEFT", bCast, "RIGHT", 8, 0)
            local bGame = makeBtn("Gameplay");   bGame:SetPoint("TOPLEFT", bUnit, "TOPLEFT", 0, 26)
            local bAll  = makeBtn("Everything"); bAll:SetPoint("LEFT", bGame, "RIGHT", 8, 0)
            bUnit:SetScript("OnClick", function() doExport("unitframe") end)
            bCast:SetScript("OnClick", function() doExport("castbar") end)
            bCol:SetScript("OnClick",  function() doExport("colors") end)
            bGame:SetScript("OnClick", function() doExport("gameplay") end)
            bAll:SetScript("OnClick",  function() doExport("all") end)
        end
        exportPickerPopup:Show()
    end
    exportBtn:SetScript("OnClick", ShowExportPicker)
end
