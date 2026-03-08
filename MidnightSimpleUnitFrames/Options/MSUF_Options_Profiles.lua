-- ---------------------------------------------------------------------------
-- MSUF_Options_Profiles.lua
-- Split from MSUF_Options_Core.lua — Profiles tab BUILD code.
-- Zero feature regression: same widgets, same DB keys, same behaviors.
-- Import/Export must work identically to pre-split.
-- ---------------------------------------------------------------------------
local addonName, addonNS = ...
ns = (_G and _G.MSUF_NS) or addonNS or ns or {}
if _G then _G.MSUF_NS = ns end

-- ---------------------------------------------------------------------------
-- Localization helper (keys are English UI strings; fallback = key)
-- ---------------------------------------------------------------------------
ns.L = ns.L or (_G and _G.MSUF_L) or {}
local L = ns.L
if not getmetatable(L) then
    setmetatable(L, { __index = function(t, k) return k end })
end
local isEn = (ns and ns.LOCALE) == "enUS"
local function TR(v)
    if type(v) ~= "string" then return v end
    if isEn then return v end
    return L[v] or v
end

function ns.MSUF_Options_Profiles_Build(panel, profileGroup, ctx)
    if not panel or not profileGroup then return end
    -- -----------------------------------------------------------------
    -- Compat helpers (resolve from ctx / ns / _G; never assume globals)
    -- -----------------------------------------------------------------
    local MSUF_BuildButtonRowList      = ctx and ctx.MSUF_BuildButtonRowList
    local MSUF_ExpandDropdownClickArea = (ns and ns.MSUF_ExpandDropdownClickArea) or _G.MSUF_ExpandDropdownClickArea
    local MSUF_SkinMidnightActionButton = (ns and ns.MSUF_SkinMidnightActionButton) or _G.MSUF_SkinMidnightActionButton
    local MSUF_CallUpdateAllFonts      = _G.MSUF_CallUpdateAllFonts
    if type(MSUF_BuildButtonRowList) ~= "function" then return end
    if type(MSUF_ExpandDropdownClickArea) ~= "function" then MSUF_ExpandDropdownClickArea = function() end end
    -- -----------------------------------------------------------------
    -- Forward-declare locals
    -- -----------------------------------------------------------------
    local profileTitle, currentProfileLabel, helpText
    local resetBtn, deleteBtn
    local newLabel, existingLabel, newEditBox, profileDrop
    local profileLine, importTitle
    local importBtn, exportBtn, legacyImportBtn
    -- -----------------------------------------------------------------
    -- StaticPopupDialogs (profile CRUD confirmation popups)
    -- -----------------------------------------------------------------
    StaticPopupDialogs["MSUF_CONFIRM_RESET_PROFILE"] = {
        text = "Reset all font size overrides?\n\nThis clears per-unit overrides for Name/Health/Power AND per-castbar overrides for Cast Name/Time so everything inherits the global defaults.",
            button1 = YES,
        button2 = NO,
        OnAccept = function(self, data)
            if data and data.name and data.panel then
                MSUF_ResetProfile(data.name)
                if data.panel.LoadFromDB then data.panel:LoadFromDB() end
                if data.panel.UpdateProfileUI then
                    data.panel:UpdateProfileUI(data.name)
                end
            end
         end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopupDialogs["MSUF_CONFIRM_DELETE_PROFILE"] = {
        text = "Are you sure you want to delete '%s'?",
        button1 = YES,
        button2 = NO,
        OnAccept = function(self, data)
            if data and data.name and data.panel then
                MSUF_DeleteProfile(data.name)
                data.panel:UpdateProfileUI(MSUF_ActiveProfile)
            end
         end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopupDialogs["MSUF_COPY_PROFILE_INPUT"] = {
        text = "Copy profile '%s' to new name:",
        button1 = "Copy",
        button2 = CANCEL,
        hasEditBox = true,
        OnAccept = function(self, data)
            local eb = self.editBox or self.EditBox
            if not (eb and eb.GetText) then return end
            local newName = (eb:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if newName == "" then return end
            if data and data.source and data.panel then
                if type(MSUF_CopyProfile) == "function" then
                    local ok = MSUF_CopyProfile(data.source, newName)
                    if ok then
                        MSUF_SwitchProfile(newName)
                        data.panel:UpdateProfileUI(newName)
                    end
                end
            end
        end,
        EditBoxOnEnterPressed = function(self)
            local parent = self:GetParent()
            if parent.button1 and parent.button1:Click() then return end
        end,
        EditBoxOnEscapePressed = function(self)
            self:GetParent():Hide()
        end,
        OnShow = function(self)
            local eb = self.editBox or self.EditBox
            if not (eb and eb.SetText and eb.SetFocus) then return end
            eb:SetText("")
            eb:SetFocus()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
-- ------------------------------------------------------------
-- Profiles header (Step 2: data-driven, reduced boilerplate)
-- ------------------------------------------------------------
profileTitle = profileGroup:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
profileTitle:SetPoint("TOPLEFT", profileGroup, "TOPLEFT", 16, -140)
profileTitle:SetText(TR("Profiles"))
local headerRow, _btns = MSUF_BuildButtonRowList(profileGroup, profileTitle, 8, {
    {
        id   = "reset",
        name = "MSUF_ProfileResetButton",
        text = "Reset profile",
        w    = 140,
        h    = 24,
        y    = 10,
        onClick = function()
            if not MSUF_ActiveProfile then
                print("|cffff0000MSUF:|r No active profile selected to reset.")
                 return
            end
            local name = MSUF_ActiveProfile
            StaticPopup_Show("MSUF_CONFIRM_RESET_PROFILE", name, nil, { name = name, panel = panel })
         end,
    },
    {
        id   = "delete",
        name = "MSUF_ProfileDeleteButton",
        text = "Delete profile",
        w    = 140,
        h    = 24,
    },
    {
        id   = "copy",
        name = "MSUF_ProfileCopyButton",
        text = "Copy profile",
        w    = 140,
        h    = 24,
    },
})
resetBtn  = _btns.reset
deleteBtn = _btns.delete
local copyBtn = _btns.copy
-- Keep the label for internal updates, but hide it so it never overlaps the buttons.
currentProfileLabel = profileGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
currentProfileLabel:Hide()
if MSUF_SkinMidnightActionButton then
    MSUF_SkinMidnightActionButton(resetBtn,  { textR = 1, textG = 0.85, textB = 0.1 })
    MSUF_SkinMidnightActionButton(deleteBtn, { textR = 1, textG = 0.85, textB = 0.1 })
    MSUF_SkinMidnightActionButton(copyBtn,   { textR = 1, textG = 0.85, textB = 0.1 })
end
helpText = profileGroup:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
helpText:SetPoint("TOPLEFT", resetBtn, "BOTTOMLEFT", 0, -8)
helpText:SetWidth(540)
helpText:SetJustifyH("LEFT")
helpText:SetText(TR("Profiles are global. Each character selects one active profile. Create a new profile on the left or select an existing one on the right."))
    -----------------------------------------------------------------
    -- Spec-based profile switching (optional)
    -----------------------------------------------------------------
    local specAutoCB = CreateFrame("CheckButton", "MSUF_ProfileSpecAutoSwitchCB", profileGroup, "ChatConfigCheckButtonTemplate")
    specAutoCB:SetPoint("TOPLEFT", helpText, "BOTTOMLEFT", 0, -12)
    do
        local t = specAutoCB.Text or _G[specAutoCB:GetName() .. "Text"]
        if t then t:SetText(TR("Auto-switch profile by specialization")) end
    end
    local specRows = {}
    local function MSUF_ProfilesUI_GetSpecMeta()
        local n = (type(_G.GetNumSpecializations) == "function") and _G.GetNumSpecializations() or 0
        local out = {}
        for i = 1, n do
            if type(_G.GetSpecializationInfo) == "function" then
                local specID, specName, _, specIcon = _G.GetSpecializationInfo(i)
                if type(specID) == "number" and type(specName) == "string" then out[#out + 1] = { id = specID, name = specName, icon = specIcon } end
            end
        end
         return out
    end
    local function MSUF_ProfilesUI_ProfileExists(profileName)
        if type(profileName) ~= "string" or profileName == "" then  return false end
        local list = (type(_G.MSUF_GetAllProfiles) == "function") and _G.MSUF_GetAllProfiles() or {}
        for _, n in ipairs(list) do
            if n == profileName then  return true end
        end
         return false
    end
    local function MSUF_ProfilesUI_EnsureSpecRows()
        if #specRows > 0 then  return end
        local meta = MSUF_ProfilesUI_GetSpecMeta()
        local anchor = specAutoCB
        for i, s in ipairs(meta) do
            local row = {}
            row.label = profileGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            row.label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -10)
            row.label:SetText(s.name)
            row.drop = (_G.MSUF_CreateStyledDropdown and _G.MSUF_CreateStyledDropdown("MSUF_ProfileSpecDrop" .. i, profileGroup) or CreateFrame("Frame", "MSUF_ProfileSpecDrop" .. i, profileGroup, "UIDropDownMenuTemplate"))
            MSUF_ExpandDropdownClickArea(row.drop)
            row.drop:SetPoint("LEFT", row.label, "LEFT", 210, -2)
            UIDropDownMenu_SetWidth(row.drop, 180)
            row.drop._msufSpecID = s.id
            UIDropDownMenu_Initialize(row.drop, function(self, level)
                if not level then  return end
                local function Add(text, value)
                    local info = UIDropDownMenu_CreateInfo()
                    info.text = text
                    info.value = value
                    info.func = function(btn)
                        UIDropDownMenu_SetSelectedValue(self, btn.value)
                        UIDropDownMenu_SetText(self, btn.value)
                        if type(_G.MSUF_SetSpecProfile) == "function" then _G.MSUF_SetSpecProfile(self._msufSpecID, (btn.value ~= "None") and btn.value or nil) end
                        CloseDropDownMenus()
                     end
                    local cur = (type(_G.MSUF_GetSpecProfile) == "function") and _G.MSUF_GetSpecProfile(self._msufSpecID) or nil
                    info.checked = (cur == value) or (cur == nil and value == "None")
                    UIDropDownMenu_AddButton(info, level)
                 end
                Add("None", "None")
                local profiles = (type(_G.MSUF_GetAllProfiles) == "function") and _G.MSUF_GetAllProfiles() or {}
                for _, name in ipairs(profiles) do
                    Add(name, name)
                end
             end)
            specRows[#specRows + 1] = row
            anchor = row.label
        end
        -- Re-anchor the section below to the last spec row (or checkbox if no specs).
        profileGroup._msufProfilesAfterSpecAnchor = anchor
     end
    local function MSUF_ProfilesUI_UpdateSpecUI()
        if type(_G.MSUF_IsSpecAutoSwitchEnabled) == "function" then
            specAutoCB:SetChecked(_G.MSUF_IsSpecAutoSwitchEnabled() and true or false)
        else
            specAutoCB:SetChecked(false)
        end
        MSUF_ProfilesUI_EnsureSpecRows()
        for _, row in ipairs(specRows) do
            local specID = row.drop and row.drop._msufSpecID
            local cur = (type(_G.MSUF_GetSpecProfile) == "function") and _G.MSUF_GetSpecProfile(specID) or nil
            -- If the mapped profile no longer exists, clear it (prevents confusing UI).
            if cur and (not MSUF_ProfilesUI_ProfileExists(cur)) then
                if type(_G.MSUF_SetSpecProfile) == "function" then _G.MSUF_SetSpecProfile(specID, nil) end
                cur = nil
            end
            if cur then
                UIDropDownMenu_SetSelectedValue(row.drop, cur)
                UIDropDownMenu_SetText(row.drop, cur)
            else
                UIDropDownMenu_SetSelectedValue(row.drop, "None")
                UIDropDownMenu_SetText(row.drop, "None")
            end
        end
     end
    specAutoCB:SetScript("OnClick", function(self)
        local enabled = self:GetChecked() and true or false
        if type(_G.MSUF_SetSpecAutoSwitchEnabled) == "function" then _G.MSUF_SetSpecAutoSwitchEnabled(enabled) end
        MSUF_ProfilesUI_UpdateSpecUI()
     end)
    -- Expose so profile CRUD / LoadFromDB can refresh these rows.
    panel._msufUpdateSpecProfileUI = MSUF_ProfilesUI_UpdateSpecUI
    -- Initial paint
    MSUF_ProfilesUI_UpdateSpecUI()
    newLabel = profileGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    newLabel:SetPoint("TOPLEFT", (profileGroup._msufProfilesAfterSpecAnchor or specAutoCB or helpText), "BOTTOMLEFT", 0, -14)
    newLabel:SetText(TR("New"))
    existingLabel = profileGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    existingLabel:SetPoint("LEFT", newLabel, "LEFT", 260, 0)
    existingLabel:SetText(TR("Existing profiles"))
    newEditBox = CreateFrame("EditBox", "MSUF_ProfileNewEdit", profileGroup, "InputBoxTemplate")
    newEditBox:SetSize(220, 20)
    newEditBox:SetAutoFocus(false)
    newEditBox:SetPoint("TOPLEFT", newLabel, "BOTTOMLEFT", 0, -4)
    profileDrop = (_G.MSUF_CreateStyledDropdown and _G.MSUF_CreateStyledDropdown("MSUF_ProfileDropdown", profileGroup) or CreateFrame("Frame", "MSUF_ProfileDropdown", profileGroup, "UIDropDownMenuTemplate"))
    MSUF_ExpandDropdownClickArea(profileDrop)
    profileDrop:SetPoint("TOPLEFT", existingLabel, "BOTTOMLEFT", -16, -4)
    local function MSUF_ProfileDropdown_Initialize(self, level)
        if not level then  return end
        local profiles = MSUF_GetAllProfiles()
        for _, name in ipairs(profiles) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = name
            info.value = name
            info.func = function(btn)
                UIDropDownMenu_SetSelectedValue(self, btn.value)
                UIDropDownMenu_SetText(self, btn.value)
                MSUF_SwitchProfile(btn.value)
                currentProfileLabel:SetText("Current profile: " .. btn.value)
                if panel and panel._msufUpdateSpecProfileUI then panel._msufUpdateSpecProfileUI() end
             end
            info.checked = (name == MSUF_ActiveProfile)
            UIDropDownMenu_AddButton(info, level)
        end
     end
    UIDropDownMenu_Initialize(profileDrop, MSUF_ProfileDropdown_Initialize)
    UIDropDownMenu_SetWidth(profileDrop, 180)
    UIDropDownMenu_SetText(profileDrop, MSUF_ActiveProfile or "Default")
    function panel:UpdateProfileUI(currentName)
        name = currentName or MSUF_ActiveProfile or "Default"
        currentProfileLabel:SetText("Current profile: " .. name)
        UIDropDownMenu_SetSelectedValue(profileDrop, name)
        UIDropDownMenu_SetText(profileDrop, name)
           if self._msufUpdateSpecProfileUI then
            self._msufUpdateSpecProfileUI()
        end
        if deleteBtn and deleteBtn.SetEnabled then deleteBtn:SetEnabled(name ~= "Default") end
     end
    newEditBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        name = (self:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if name ~= "" then
            MSUF_CreateProfile(name)
            MSUF_SwitchProfile(name)
            self:SetText(TR(""))
            panel:UpdateProfileUI(name)
        end
     end)
deleteBtn:SetScript("OnClick", function()
    if not MSUF_ActiveProfile then  return end
    name = MSUF_ActiveProfile
    if name == "Default" then
        print("|cffff0000MSUF:|r Das 'Default'-Thanks for testing and reporting bugs no you can not delete Default'.")
         return
    end
    StaticPopup_Show(
        "MSUF_CONFIRM_DELETE_PROFILE",
        name,       -- ersetzt %s im Text
        nil,
        {
            name  = name,   -- geht an data.name im Popup
            panel = panel,  -- geht an data.panel ->  UpdateProfileUI
        }
    )
 end)
copyBtn:SetScript("OnClick", function()
    local source = MSUF_ActiveProfile
    if not source then return end
    StaticPopup_Show(
        "MSUF_COPY_PROFILE_INPUT",
        source,
        nil,
        {
            source = source,
            panel  = panel,
        }
    )
 end)
    profileLine = profileGroup:CreateTexture(nil, "ARTWORK")
    profileLine:SetColorTexture(1, 1, 1, 0.18)
    profileLine:SetPoint("TOPLEFT", newEditBox, "BOTTOMLEFT", 0, -20)
    profileLine:SetSize(540, 1)
    importTitle = profileGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    importTitle:SetPoint("TOPLEFT", profileLine, "BOTTOMLEFT", 0, -10)
    importTitle:SetText(TR("Profile export / import"))
    local function MSUF_CreateSimpleDialog(frameName, titleText, w, h)
        local f = CreateFrame("Frame", frameName, UIParent, "BackdropTemplate")
        f:SetFrameStrata("DIALOG")
        f:SetClampedToScreen(true)
        f:SetSize(w or 520, h or 96)
        f:SetPoint("CENTER")
        f:SetBackdrop({
            bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        f:SetBackdropColor(0, 0, 0, 0.92)
        local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        title:SetPoint("TOP", 0, -8)
        title:SetText(titleText or "")
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -2, -2)
        close:SetScript("OnClick", function()  f:Hide()  end)
        f:Hide()
         return f, title
    end
    -- Ctrl+C copy popup
    local copyPopup, copyTitle, copyEdit
    local function MSUF_ShowCopyPopup(str)
        if not copyPopup then
            copyPopup, copyTitle = MSUF_CreateSimpleDialog("MSUF_ProfileCopyPopup", "Ctrl+C to copy", 560, 96)
            copyEdit = CreateFrame("EditBox", nil, copyPopup, "InputBoxTemplate")
            copyEdit:SetAutoFocus(true)
            copyEdit:SetSize(500, 22)
            copyEdit:SetPoint("TOP", copyPopup, "TOP", 0, -36)
            copyEdit:SetScript("OnEscapePressed", function(self)
                self:ClearFocus()
                copyPopup:Hide()
             end)
            local done = CreateFrame("Button", nil, copyPopup, "UIPanelButtonTemplate")
            done:SetSize(90, 22)
            done:SetPoint("BOTTOM", 0, 10)
            done:SetText(TR("Done"))
            done:SetScript("OnClick", function()  copyPopup:Hide()  end)
            if MSUF_SkinMidnightActionButton then MSUF_SkinMidnightActionButton(done, { textR = 1, textG = 0.85, textB = 0.1 }) end
            copyPopup:SetScript("OnShow", function()
                if copyEdit then copyEdit:HighlightText() end
             end)
        end
        copyEdit:SetText(str or "")
        copyEdit:HighlightText()
        copyPopup:Show()
        copyEdit:SetFocus()
     end
    -- Ctrl+V paste popup (new/legacy)
    local importPopup, importTitleFS, importEdit, importDoBtn
    local function MSUF_ShowImportPopup(mode)
        mode = (mode == "legacy") and "legacy" or "new"
        if not importPopup then
            importPopup, importTitleFS = MSUF_CreateSimpleDialog("MSUF_ProfileImportPopup", "Ctrl+V to paste", 560, 110)
            importEdit = CreateFrame("EditBox", nil, importPopup, "InputBoxTemplate")
            importEdit:SetAutoFocus(true)
            importEdit:SetSize(500, 22)
            importEdit:SetPoint("TOP", importPopup, "TOP", 0, -36)
            importEdit:SetScript("OnEscapePressed", function(self)
                self:ClearFocus()
                importPopup:Hide()
             end)
            importDoBtn = CreateFrame("Button", nil, importPopup, "UIPanelButtonTemplate")
            importDoBtn:SetSize(110, 22)
            importDoBtn:SetPoint("BOTTOM", importPopup, "BOTTOM", -60, 10)
            importDoBtn:SetText(TR("Import"))
            local cancel = CreateFrame("Button", nil, importPopup, "UIPanelButtonTemplate")
            cancel:SetSize(110, 22)
            cancel:SetPoint("LEFT", importDoBtn, "RIGHT", 10, 0)
            cancel:SetText(TR("Cancel"))
            cancel:SetScript("OnClick", function()  importPopup:Hide()  end)
            if MSUF_SkinMidnightActionButton then
                MSUF_SkinMidnightActionButton(importDoBtn, { textR = 1, textG = 0.85, textB = 0.1 })
                MSUF_SkinMidnightActionButton(cancel,     { textR = 1, textG = 0.85, textB = 0.1 })
            end
            local function runImport()
                local str = (importEdit and importEdit.GetText) and (importEdit:GetText() or "") or ""
                local Importer
                if importPopup._msufMode == "legacy" then
                    Importer = _G.MSUF_ImportLegacyFromString or (ns and ns.MSUF_ImportLegacyFromString)
                else
                    Importer = _G.MSUF_ImportFromString or (ns and ns.MSUF_ImportFromString)
                end
                if type(Importer) ~= "function" then
                    print("|cffff0000MSUF:|r Import failed: importer missing.")
                     return
                end
                Importer(str)
                if type(ApplyAllSettings) == "function" then ApplyAllSettings() end
                if type(MSUF_CallUpdateAllFonts) == "function" then MSUF_CallUpdateAllFonts() end
                if panel and panel.LoadFromDB then panel:LoadFromDB() end
                if panel and panel.UpdateProfileUI then
                    panel:UpdateProfileUI(MSUF_ActiveProfile)
                end
                importPopup:Hide()
             end
            importDoBtn:SetScript("OnClick", runImport)
            importEdit:SetScript("OnEnterPressed", function()  runImport()  end)
        end
        importPopup._msufMode = mode
        if importTitleFS then
            if mode == "legacy" then
                importTitleFS:SetText(TR("Ctrl+V to paste (Legacy Import)"))
            else
                importTitleFS:SetText(TR("Ctrl+V to paste"))
            end
        end
        importEdit:SetText(TR(""))
        importPopup:Show()
        importEdit:SetFocus()
     end
    -- Buttons (clean panel, no giant box)
    importBtn = CreateFrame("Button", nil, profileGroup, "UIPanelButtonTemplate")
    importBtn:SetSize(110, 22)
    importBtn:SetPoint("TOPLEFT", importTitle, "BOTTOMLEFT", 0, -12)
    importBtn:SetText(TR("Import"))
    exportBtn = CreateFrame("Button", nil, profileGroup, "UIPanelButtonTemplate")
    exportBtn:SetSize(110, 22)
    exportBtn:SetPoint("LEFT", importBtn, "RIGHT", 8, 0)
    exportBtn:SetText(TR("Export"))
    legacyImportBtn = CreateFrame("Button", nil, profileGroup, "UIPanelButtonTemplate")
    legacyImportBtn:SetSize(120, 22)
    legacyImportBtn:SetPoint("LEFT", exportBtn, "RIGHT", 8, 0)
    legacyImportBtn:SetText(TR("Legacy Import"))
    if MSUF_SkinMidnightActionButton then
        MSUF_SkinMidnightActionButton(importBtn,       { textR = 1, textG = 0.85, textB = 0.1 })
        MSUF_SkinMidnightActionButton(exportBtn,       { textR = 1, textG = 0.85, textB = 0.1 })
        MSUF_SkinMidnightActionButton(legacyImportBtn, { textR = 1, textG = 0.85, textB = 0.1 })
    end
    importBtn:SetScript("OnClick", function()  MSUF_ShowImportPopup("new")  end)
    legacyImportBtn:SetScript("OnClick", function()  MSUF_ShowImportPopup("legacy")  end)
    -----------------------------------------------------------------
    -- Export picker (Platynator-style)
    -----------------------------------------------------------------
    local exportPopup
    local function MSUF_ShowExportPicker()
        if exportPopup and exportPopup:IsShown() then
            exportPopup:Hide()
             return
        end
        if not exportPopup then
            exportPopup = CreateFrame("Frame", "MSUF_ProfileExportPicker", UIParent, "BackdropTemplate")
            exportPopup:SetFrameStrata("DIALOG")
            exportPopup:SetClampedToScreen(true)
            exportPopup:SetSize(420, 86)
            exportPopup:SetPoint("CENTER")
            exportPopup:SetBackdrop({
                bgFile = "Interface/Tooltips/UI-Tooltip-Background",
                edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 16,
                insets = { left = 4, right = 4, top = 4, bottom = 4 },
            })
            exportPopup:SetBackdropColor(0, 0, 0, 0.92)
            local title = exportPopup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            title:SetPoint("TOP", 0, -8)
            title:SetText(TR("What to export?"))
            local close = CreateFrame("Button", nil, exportPopup, "UIPanelCloseButton")
            close:SetPoint("TOPRIGHT", -2, -2)
            close:SetScript("OnClick", function()  exportPopup:Hide()  end)
            local function makeBtn(text)
                local b = CreateFrame("Button", nil, exportPopup, "UIPanelButtonTemplate")
                b:SetSize(120, 22)
                b:SetText(text)
                if MSUF_SkinMidnightActionButton then MSUF_SkinMidnightActionButton(b, { textR = 1, textG = 0.85, textB = 0.1 }) end
                 return b
            end
            exportPopup.btnUnit = makeBtn("Unitframes")
            exportPopup.btnCast = makeBtn("Castbars")
            exportPopup.btnCol  = makeBtn("Colors")
            exportPopup.btnGame = makeBtn("Gameplay")
            exportPopup.btnAll  = makeBtn("Everything")
            exportPopup.btnUnit:SetPoint("BOTTOMLEFT", 10, 10)
            exportPopup.btnCast:SetPoint("LEFT", exportPopup.btnUnit, "RIGHT", 8, 0)
            exportPopup.btnCol:SetPoint("LEFT", exportPopup.btnCast, "RIGHT", 8, 0)
            exportPopup.btnGame:SetPoint("TOPLEFT", exportPopup.btnUnit, "TOPLEFT", 0, 26)
            exportPopup.btnAll:SetPoint("LEFT", exportPopup.btnGame, "RIGHT", 8, 0)
            local function doExport(kind)
                local Exporter = _G.MSUF_ExportSelectionToString or (ns and ns.MSUF_ExportSelectionToString)
                if type(Exporter) ~= "function" then
                    print("|cffff0000MSUF:|r Export failed: exporter missing (MSUF_ExportSelectionToString).")
                    exportPopup:Hide()
                     return
                end
                local str = Exporter(kind)
                MSUF_ShowCopyPopup(str or "")
                exportPopup:Hide()
                print("|cff00ff00MSUF:|r Exported " .. tostring(kind) .. " settings.")
             end
            exportPopup.btnUnit:SetScript("OnClick", function()  doExport("unitframe")  end)
            exportPopup.btnCast:SetScript("OnClick", function()  doExport("castbar")  end)
            exportPopup.btnCol:SetScript("OnClick", function()  doExport("colors")  end)
            exportPopup.btnGame:SetScript("OnClick", function()  doExport("gameplay")  end)
            exportPopup.btnAll:SetScript("OnClick", function()  doExport("all")  end)
        end
        exportPopup:Show()
     end
    exportBtn:SetScript("OnClick", MSUF_ShowExportPicker)
end -- ns.MSUF_Options_Profiles_Build
