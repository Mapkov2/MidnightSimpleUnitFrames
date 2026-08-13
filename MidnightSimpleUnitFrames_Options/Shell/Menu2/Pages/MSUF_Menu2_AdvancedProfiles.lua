local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

-- Advanced Profiles page.
-- Builds profile copy/import/export/spec-switch controls and Wago import affordances.
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
    ["import.execute"] = "import_profile_string",
    ["profiles.browse_wago"] = "copy_wago_profiles_link",
    ["new_character.default_profile"] = "set_new_character_profile",
}
local PROFILE_ACTION_INPUT_BY_PATH = {
    ["active_profile.select"] = "name",
    ["new_character.default_profile"] = "name",
    ["profile.create"] = "name",
    ["profile.copy_current"] = "name",
    ["import.legacy"] = "value",
    ["import.execute"] = "value",
}
local function ProfilesMeta(path, classification, exact)
    local resolved = {}
    if type(exact) == "table" then
        for key, value in pairs(exact) do resolved[key] = value end
    end
    resolved.settingKey = resolved.settingKey or PROFILE_SETTING_BY_PATH[path]
    resolved.actionKey = resolved.actionKey or PROFILE_ACTION_BY_PATH[path]
    resolved.actionInputArg = resolved.actionInputArg or PROFILE_ACTION_INPUT_BY_PATH[path]
    if path == "profile.delete_current" and resolved.actionFixedArgs == nil then
        resolved.actionFixedArgs = { name = { context = "activeProfile" } }
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
    if type(fn) ~= "function" then return false end
    if type(CallGlobal) == "function" then return CallGlobal(name, ...) end
    local apply = M.ApplyService
    if apply and type(apply.Invoke) == "function" then return apply.Invoke(fn, ...) end
    local ok, r1, r2 = pcall(fn, ...)
    if not ok then
        local handler = _G.geterrorhandler and _G.geterrorhandler()
        if type(handler) == "function" then pcall(handler, r1) end
        return false, r1
    end
    return true, r1, r2
end
local function ClearProfileHistory() if M.ClearHistory then M.ClearHistory() end end
local function PrintProfileMessage(color, message)
    message = M.Tr(tostring(message or ""))
    if M.ShowStatusFeedback then
        local kind = tostring(color or ""):find("ff0000", 1, true) and "danger" or "info"
        M.ShowStatusFeedback(message, kind, kind == "danger" and 2.0 or 1.7)
    end
    print((color or "|cffffd700") .. "MSUF:|r " .. message)
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
-- A multiline EditBox never clips its own text: once the export string outgrows the box,
-- the overflow paints across the whole menu. Host the box in a ScrollFrame (which clips)
-- and hang the skin on a static host frame so the visuals do not scroll with the text.
-- The host is a flat panel: the superellipse pill skin degenerates into a giant ellipse
-- at input heights this large.
local function WrapMultilineProfileInput(editBox, card, x, y, width, height)
    local shadow = T.colors.coreShadow or { 0.006, 0.016, 0.032 }
    local host = T.Panel(card, nil, { shadow[1], shadow[2], shadow[3], 0.96 }, T.colors.borderSoft)
    host:SetPoint("TOPLEFT", card, "TOPLEFT", x, y)
    host:SetSize(width, height)
    local scroll = CreateFrame("ScrollFrame", nil, host)
    scroll:SetPoint("TOPLEFT", host, "TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -26, 8)
    StyleProfileInput(editBox, max(160, width - 34), height - 16, true)
    editBox:SetParent(scroll)
    editBox:ClearAllPoints()
    editBox:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
    scroll:SetScrollChild(editBox)
    -- The box's own skin textures would scroll with the text; the host draws the box now.
    if editBox._msuf2EditBg then editBox._msuf2EditBg:Hide() end
    if editBox._msuf2EditEdges then
        for i = 1, #editBox._msuf2EditEdges do editBox._msuf2EditEdges[i]:Hide() end
    end
    if editBox._msuf2Bg then editBox._msuf2Bg:Hide() end
    editBox:HookScript("OnEditFocusGained", function()
        if host.SetBackdropBorderColor then
            host:SetBackdropBorderColor(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 0.95)
        end
    end)
    editBox:HookScript("OnEditFocusLost", function()
        if host.SetBackdropBorderColor then
            host:SetBackdropBorderColor(T.colors.borderSoft[1], T.colors.borderSoft[2], T.colors.borderSoft[3], T.colors.borderSoft[4] or 1)
        end
    end)
    if T.StyleScrollFrame then T.StyleScrollFrame(scroll, host) end
    scroll:EnableMouse(true)
    scroll:SetScript("OnMouseDown", function()
        editBox:SetFocus()
        if editBox.GetNumLetters then editBox:SetCursorPosition(editBox:GetNumLetters()) end
    end)
    editBox:SetScript("OnCursorChanged", function(_, _, cursorY, _, cursorH)
        local viewH = scroll:GetHeight() or 0
        if viewH <= 0 then return end
        local top = -(tonumber(cursorY) or 0)
        local bottom = top + (tonumber(cursorH) or 0)
        local offset = scroll:GetVerticalScroll() or 0
        if top < offset then
            scroll:SetVerticalScroll(top)
        elseif bottom > offset + viewH then
            scroll:SetVerticalScroll(bottom - viewH)
        end
    end)
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
        PrintProfileMessage("|cffffd700", M.Format("Imported profile '%s'. Reload after combat with /reload.", tostring(profileName)))
        return
    end
    if type(_G.ReloadUI) == "function" then
        _G.ReloadUI()
    else
        PrintProfileMessage("|cffffd700", M.Format("Imported profile '%s'. Reload the UI with /reload.", tostring(profileName)))
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
    local contentW = b.width or ctx.width or 920
    local buttonW, buttonH, buttonGap = 190, 24, 14
    local PROFILE_TOOLTIP = { hook = true, titleAsLine = true, bodyColor = { 0.85, 0.85, 0.85 } }
    local function AddProfileTooltip(frame, title, text) return M.AddTooltip and M.AddTooltip(frame, tostring(title or ""), text, PROFILE_TOOLTIP) or frame end
    local function PlaceActionRow(parent, x, left, right, y) left:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y); right:SetPoint("LEFT", left, "RIGHT", buttonGap, 0) end
    local function ProfileButton(parent, label, onClick, danger, semanticPath, confirmRequired, prepareValue, validateValue, directCommand, width)
        local btn = T.Button(parent, label, width or buttonW, buttonH)
        if danger and T.SkinDangerButton then T.SkinDangerButton(btn) end
        if T.CenterButtonLabel then T.CenterButtonLabel(btn) end
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

    local current, io, blob, profileDrop
    local function ConfigLocked()
        return (_G.InCombatLockdown and _G.InCombatLockdown())
            or (_G.UnitAffectingCombat and _G.UnitAffectingCombat("player"))
            or false
    end
    local function ExportProfileString(kind)
        if type(_G.MSUF_ExportSelectionToString) ~= "function" then
            if M.ShowStatusFeedback then M.ShowStatusFeedback(M.Tr("Export unavailable"), "danger", 1.8) end
            return false
        end
        local called, value = CallMSUF("MSUF_ExportSelectionToString", kind or M.profileExportKind or "all")
        if not called or type(value) ~= "string" then
            if M.ShowStatusFeedback then M.ShowStatusFeedback(M.Tr("Export failed"), "danger", 1.8) end
            return false
        end
        M.profileImportString = value
        if blob then
            blob:SetText(value)
            blob:SetFocus()
            blob:HighlightText()
        end
        if M.ShowStatusFeedback then
            M.ShowStatusFeedback(M.Tr("Profile string ready - press Ctrl+C"), "info", 1.8)
        end
        return true
    end
    local function StatusPill(parent, width)
        local pill = CreateFrame("Frame", nil, parent)
        pill:SetSize(width, 22)
        local fill, edge = T.CreateSuperellipseLayers(pill, "_msuf2ProfileStatusPill", 1, "ARTWORK", "OVERLAY")
        pill._msuf2Fill, pill._msuf2Edge = fill, edge
        pill.text = T.Font(pill, "GameFontDisableSmall", "", T.colors.text)
        pill.text:SetPoint("CENTER")
        pill.text:SetJustifyH("CENTER")
        return pill
    end
    local STATUS_PILL_COLORS = {
        info = {
            bg = { 0.020, 0.110, 0.180, 0.94 },
            border = { 0.120, 0.410, 0.650, 0.84 },
            text = { 0.690, 0.860, 1.000, 1 },
        },
        ok = {
            bg = { 0.020, 0.145, 0.105, 0.94 },
            border = { 0.120, 0.510, 0.350, 0.84 },
            text = { 0.390, 1.000, 0.690, 1 },
        },
        warn = {
            bg = { 0.155, 0.105, 0.025, 0.94 },
            border = { 0.560, 0.390, 0.100, 0.84 },
            text = { 1.000, 0.820, 0.390, 1 },
        },
        danger = {
            bg = { 0.180, 0.045, 0.065, 0.94 },
            border = { 0.660, 0.180, 0.260, 0.88 },
            text = { 1.000, 0.610, 0.670, 1 },
        },
    }
    local function SetStatusPill(pill, text, kind)
        if not pill then return end
        local color = STATUS_PILL_COLORS[kind] or STATUS_PILL_COLORS.info
        if pill.text then
            pill.text:SetText(Tr(text or ""))
            pill.text:SetTextColor(color.text[1], color.text[2], color.text[3], color.text[4] or 1)
        end
        if pill._msuf2Fill then
            if T.SetFillGradient then
                T.SetFillGradient(pill._msuf2Fill, color.bg, 0.10, -0.16)
            else
                pill._msuf2Fill:SetVertexColor(color.bg[1], color.bg[2], color.bg[3], color.bg[4] or 1)
            end
        end
        if pill._msuf2Edge then
            pill._msuf2Edge:SetVertexColor(color.border[1], color.border[2], color.border[3], color.border[4] or 1)
        end
    end

    -- Profile management is a high-impact workflow, so its current state stays visible
    -- even when every task section is collapsed.
    -- The status pills and the two profile actions need more horizontal room
    -- than the rest of this page. Switch to the stacked layout before those
    -- groups can overlap at intermediate menu/UI scales.
    local compactHero = contentW < 1120
    local heroH = compactHero and 206 or 112
    local hero = T.Panel(b.parent, nil, T.colors.glassStatus or T.colors.header, T.colors.borderSoft)
    if T.ApplySurface then T.ApplySurface(hero, "status") end
    hero:SetPoint("TOPLEFT", b.parent, "TOPLEFT", b.x, b.y)
    hero:SetSize(contentW, heroH)
    hero._msuf2Width = contentW
    if W.RegisterGuidedRegion then W.RegisterGuidedRegion(ctx, hero, "Active profile overview", "profiles_overview") end
    b.y = b.y - heroH - 10
    if ctx.SetContentHeight then ctx:SetContentHeight(math.abs(b.y) + 28) end

    local accent = hero:CreateTexture(nil, "OVERLAY")
    accent:SetPoint("TOPLEFT", hero, "TOPLEFT", 0, -2)
    accent:SetPoint("BOTTOMLEFT", hero, "BOTTOMLEFT", 0, 2)
    accent:SetWidth(4)
    accent:SetColorTexture(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 0.96)
    local profileMark = T.Panel(hero, nil, T.colors.panel2, T.colors.accent)
    profileMark:SetSize(54, 54)
    profileMark:SetPoint("TOPLEFT", hero, "TOPLEFT", 20, -24)
    local markText = T.Font(profileMark, "GameFontNormalLarge", "P", T.colors.text)
    markText:SetPoint("CENTER")
    W.LabelAt(hero, "ACTIVE PROFILE", 92, -21, 280, "GameFontDisableSmall", T.colors.accent)
    local activeName = T.Font(hero, "GameFontNormalLarge", "", T.colors.text, "section")
    activeName:SetPoint("TOPLEFT", hero, "TOPLEFT", 92, -43)
    activeName:SetWidth(300)
    W.LabelAt(hero, "Used by this character  \194\183  Account-wide profile", 92, -76, 360,
        "GameFontDisableSmall", T.colors.muted)

    local profileCountPill = StatusPill(hero, 104)
    local specStatePill = StatusPill(hero, 146)
    local safetyPill = StatusPill(hero, 168)
    local heroPillX = compactHero and 20 or min(max(430, floor(contentW * 0.45)), max(430, contentW - 690))
    profileCountPill:SetPoint("TOPLEFT", hero, "TOPLEFT", heroPillX, compactHero and -100 or -30)
    specStatePill:SetPoint("LEFT", profileCountPill, "RIGHT", 10, 0)
    safetyPill:SetPoint("TOPLEFT", hero, "TOPLEFT", heroPillX, compactHero and -132 or -64)

    local heroExport = T.Button(hero, "Export backup", 150, 34, { noSearch = true })
    local heroSwitch = T.Button(hero, "Switch profile", 168, 34, { noSearch = true })
    if T.CenterButtonLabel then T.CenterButtonLabel(heroExport); T.CenterButtonLabel(heroSwitch) end
    if T.ApplyButtonRole then T.ApplyButtonRole(heroSwitch, "primary") end
    if compactHero then
        heroExport:SetPoint("TOPRIGHT", hero, "TOPRIGHT", -202, -164)
        heroSwitch:SetPoint("TOPRIGHT", hero, "TOPRIGHT", -20, -164)
    else
        heroExport:SetPoint("TOPRIGHT", hero, "TOPRIGHT", -202, -34)
        heroSwitch:SetPoint("TOPRIGHT", hero, "TOPRIGHT", -20, -34)
        local combatHint = W.LabelAt(hero, "Profile actions are blocked in combat.", contentW - 390, -78, 370,
            "GameFontDisableSmall", T.colors.muted)
        if combatHint and combatHint.SetJustifyH then combatHint:SetJustifyH("RIGHT") end
    end
    heroExport:SetScript("OnClick", function()
        if ExportProfileString("all") and io and W.FocusCollapsibleSection then
            W.FocusCollapsibleSection(io, { flash = true })
        end
    end)
    heroSwitch:SetScript("OnClick", function()
        if current and W.FocusCollapsibleSection then W.FocusCollapsibleSection(current, { flash = true }) end
    end)
    AddProfileTooltip(heroExport, "Export backup", "Creates a full-profile export string and opens Import & Export.")
    AddProfileTooltip(heroSwitch, "Switch profile", "Opens Profile Management. Profile switching is blocked during combat.")

    -- Profile switches rebuild live frames and can taint secure state in combat, so every
    -- entry point on this page goes through BlockCombatAction before touching profile APIs.
    local managementWide = contentW >= 1180
    local managementMedium = not managementWide and contentW >= 720
    local managementH = managementWide and 444 or (managementMedium and 620 or 884)
    current = b:CollapsibleSection("profiles_management", "Profile Management", managementH, true)
    local manageInset, manageGap = 20, 18
    local manageInnerW = max(320, contentW - (manageInset * 2))
    local currentCardX, currentCardY, currentCardW, currentCardH
    local createCardX, createCardY, createCardW, createCardH
    local newCharCardX, newCharCardY, newCharCardW, newCharCardH
    local dangerX, dangerY, dangerW, dangerH
    if managementWide then
        currentCardX, currentCardY, currentCardW, currentCardH = manageInset, -42, floor(manageInnerW * 0.29), 192
        createCardX, createCardY, createCardW, createCardH = currentCardX + currentCardW + manageGap, -42, floor(manageInnerW * 0.42), 192
        newCharCardX, newCharCardY, newCharCardW, newCharCardH = createCardX + createCardW + manageGap, -42,
            manageInnerW - currentCardW - createCardW - (manageGap * 2), 192
        dangerX, dangerY, dangerW, dangerH = manageInset, -252, manageInnerW, 164
    elseif managementMedium then
        currentCardX, currentCardY, currentCardW, currentCardH = manageInset, -42, floor((manageInnerW - manageGap) * 0.40), 192
        createCardX, createCardY, createCardW, createCardH = currentCardX + currentCardW + manageGap, -42,
            manageInnerW - currentCardW - manageGap, 192
        newCharCardX, newCharCardY, newCharCardW, newCharCardH = manageInset, -252, manageInnerW, 166
        dangerX, dangerY, dangerW, dangerH = manageInset, -436, manageInnerW, 164
    else
        currentCardX, currentCardY, currentCardW, currentCardH = manageInset, -42, manageInnerW, 180
        createCardX, createCardY, createCardW, createCardH = manageInset, -240, manageInnerW, 220
        newCharCardX, newCharCardY, newCharCardW, newCharCardH = manageInset, -478, manageInnerW, 170
        dangerX, dangerY, dangerW, dangerH = manageInset, -666, manageInnerW, 196
    end
    local currentCard = W.ControlCard(current, "Current profile", "Switch the profile used by this character.",
        currentCardX, currentCardY, currentCardW, currentCardH)
    local createCard = W.ControlCard(current, "Create or duplicate", "Use a clear name so you can return to this setup later.",
        createCardX, createCardY, createCardW, createCardH)
    local newCharCard = W.ControlCard(current, "New characters", "Choose the starting profile for new characters.",
        newCharCardX, newCharCardY, newCharCardW, newCharCardH)
    local dangerColor = T.colors.danger or { 0.88, 0.28, 0.28, 1 }
    local dangerPanel = T.Panel(current, nil,
        { 0.090, 0.018, 0.030, 0.94 },
        { dangerColor[1], dangerColor[2], dangerColor[3], 0.70 })
    dangerPanel:SetPoint("TOPLEFT", current, "TOPLEFT", dangerX, dangerY)
    dangerPanel:SetSize(dangerW, dangerH)
    local dangerAccent = dangerPanel:CreateTexture(nil, "OVERLAY")
    dangerAccent:SetPoint("TOPLEFT", dangerPanel, "TOPLEFT", 0, -2)
    dangerAccent:SetPoint("BOTTOMLEFT", dangerPanel, "BOTTOMLEFT", 0, 2)
    dangerAccent:SetWidth(4)
    dangerAccent:SetColorTexture(dangerColor[1], dangerColor[2], dangerColor[3], 0.92)
    W.LabelAt(dangerPanel, "!", 20, -22, 18, "GameFontNormal", dangerColor)
    W.LabelAt(dangerPanel, "Danger zone", 48, -18, max(160, dangerW - 72), "GameFontNormal", T.colors.text)
    W.LabelAt(dangerPanel, "These actions change or remove the complete active profile.", 48, -42,
        max(220, dangerW - 72), "GameFontDisableSmall", T.colors.muted)
    W.LabelAt(dangerPanel, "Export or copy the profile first if you may want to restore it later.", 20,
        managementWide and -96 or -82, max(260, dangerW - 40), "GameFontDisableSmall", T.colors.text)

    local fieldW = max(180, currentCardW - 40)
    profileDrop = W.Dropdown(currentCard, "Active profile", {}, fieldW)
    RegisterControl(profileDrop, ProfilesMeta("active_profile.select", "action", { historyMode = "none" }), "Active profile", "dropdown", ProfileValues)
    if M.MarkRuntimeControlComponent then M.MarkRuntimeControlComponent(heroSwitch, profileDrop) end
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
    local createFieldW = max(180, createCardW - 40)
    local createButtonW = max(120, floor((createCardW - 40 - buttonGap) / 2))
    local nameInput = W.TextInput(createCard, "New profile name", createFieldW)
    M.BindTextInput(ctx, nameInput,
        function() return M.profileCreateCopyName or "" end,
        function(value) M.profileCreateCopyName = Trim(value or "") end,
        true,
        ProfilesMeta("draft.create_copy_name", "ephemeral"))
    local create = ProfileButton(createCard, "Create profile", function()
        if BlockCombatAction() then return end
        local name = Trim(nameInput:GetText())
        if name and name ~= "" then
            local called, created = CallMSUF("MSUF_CreateProfile", name)
            if called and created == true then
                CallMSUF("MSUF_SwitchProfile", name)
                ClearProfileHistory()
            end
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
    end, nil, createButtonW)
    local copy = ProfileButton(createCard, "Copy current profile", function()
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
    end, nil, createButtonW)
    local dangerButtonW = max(140, min(250, floor((dangerW - 54) / 2)))
    local reset = ProfileButton(dangerPanel, "Reset to defaults", function()
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
                local apply = M.ApplyService
                local called, result
                if apply and type(apply.Invoke) == "function" then
                    called, result = apply.Invoke(M.ResetPageToDefaults, "profiles")
                else
                    called, result = pcall(M.ResetPageToDefaults, "profiles")
                end
                if not called or result ~= true then return false end
                RefreshAfterProfileChange(ctx)
                return true
            end
            local ok, result = CallMSUF("MSUF_ResetProfile", ActiveProfileName())
            if not ok or result == false then return false end
            ClearProfileHistory()
            RefreshAfterProfileChange(ctx)
            return true
        end,
    }, dangerButtonW)
    local delete = ProfileButton(dangerPanel, "Delete current profile", function()
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
    }, dangerButtonW)
    MoveWidget(profileDrop, currentCard, 20, -78, fieldW)
    local currentStatus = W.LabelAt(currentCard, "", 20, -150, max(180, currentCardW - 40),
        "GameFontDisableSmall", T.colors.muted)
    MoveWidget(nameInput, createCard, 20, -78, createFieldW)
    StyleProfileInput(nameInput, createFieldW, 28, false)
    PlaceActionRow(createCard, 20, create, copy, -148)
    local dangerActionsX = max(20, dangerW - (dangerButtonW * 2) - buttonGap - 20)
    local dangerActionsY = managementWide and -70 or (managementMedium and -104 or -138)
    PlaceActionRow(dangerPanel, dangerActionsX, reset, delete, dangerActionsY)

    -- "Active profile" above is a per-character binding into an account-wide
    -- pool of profiles. This picks what a character that has never run MSUF
    -- starts on. The engine validates the stored name on every login and falls
    -- back to "Default" if the profile was deleted, so "None" is always safe.
    local newCharW = max(180, newCharCardW - 40)
    local newCharDrop = W.Dropdown(newCharCard, "Default profile", function() return ProfileValues(true) end, newCharW)
    MoveWidget(newCharDrop, newCharCard, 20, -78, newCharW)
    M.BindDropdownWidget(ctx, newCharDrop,
        function()
            local fn = _G.MSUF_GetDefaultProfileForNewCharacters
            return (type(fn) == "function" and fn()) or "None"
        end,
        function(v)
            CallMSUF("MSUF_SetDefaultProfileForNewCharacters", (v ~= "None") and v or nil)
            RefreshAfterProfileChange(ctx)
        end,
        ProfilesMeta("new_character.default_profile", "action"))
    local newCharHelp = W.Text(newCharCard, "Existing characters are not changed.", 20, -146,
        max(180, newCharCardW - 40), T.colors.muted)
    if newCharHelp and newCharHelp.SetWordWrap then newCharHelp:SetWordWrap(true) end

    local function RefreshManagementState()
        local active = ActiveProfileName()
        local profiles = ProfileValues(false)
        local profileCount = #profiles
        local profileCountText = profileCount == 1 and "1 profile" or M.Format("%d profiles", profileCount)
        local specAuto = type(_G.MSUF_IsSpecAutoSwitchEnabled) == "function" and _G.MSUF_IsSpecAutoSwitchEnabled() or false
        local locked = ConfigLocked()
        activeName:SetText(active)
        if currentStatus then
            currentStatus:SetText(M.Format("Currently loaded and applied: %s", active))
        end
        SetStatusPill(profileCountPill, profileCountText, "info")
        SetStatusPill(specStatePill, specAuto and "Spec switching: On" or "Spec switching: Off", specAuto and "ok" or "warn")
        SetStatusPill(safetyPill, locked and "Combat locked" or "Safe to manage now", locked and "danger" or "ok")
        if delete.SetEnabled then delete:SetEnabled(active ~= "Default") end
        if W.SetCollapsibleBadges then
            W.SetCollapsibleBadges(current, {
                { text = M.Format("%s active", active), kind = "accent", showWhenClosed = true },
                { text = profileCountText, kind = "info", showWhenClosed = true },
                { text = locked and "Combat locked" or "Safe", kind = locked and "muted" or "ok", showWhenClosed = true },
            })
        end
    end
    if M.TrackCollapsibleRefresh then
        M.TrackCollapsibleRefresh(ctx, current, RefreshManagementState)
    else
        M.TrackRefresh(ctx, RefreshManagementState)
    end
    local specs = GetSpecMeta()
    local specCols
    if contentW >= 1380 then
        specCols = min(4, max(1, #specs))
    elseif contentW >= 980 then
        specCols = min(3, max(1, #specs))
    elseif contentW >= 640 then
        specCols = min(2, max(1, #specs))
    else
        specCols = 1
    end
    local specRows = max(1, math.ceil(max(1, #specs) / specCols))
    local specAutoCardH = contentW >= 760 and 126 or 156
    local specCardH, specCardGap = 122, 16
    local specCardsY = -42 - specAutoCardH - 18
    local specH = math.abs(specCardsY) + (specRows * specCardH) + ((specRows - 1) * specCardGap) + 20

    -- Spec-profile rows depend on WoW specialization APIs. The empty-state path keeps the
    -- page usable for low-level characters and offline smoke tests where those APIs are nil.
    local spec = b:CollapsibleSection("profiles_specs", "Specialization Profiles", specH, true)
    local specInnerW = max(300, contentW - 40)
    local autoCard = W.ControlCard(spec, "Automatic switching",
        "MSUF switches after combat if specialization changes while combat-locked.",
        20, -42, specInnerW, specAutoCardH)
    local auto = W.SwitchAt(autoCard, "Auto-switch profile by specialization", 20, -66,
        min(380, max(220, specInnerW - 40)))
    M.BindBoolWidget(ctx, auto,
        function()
            return type(_G.MSUF_IsSpecAutoSwitchEnabled) == "function" and _G.MSUF_IsSpecAutoSwitchEnabled() or false
        end,
        function(v)
            CallMSUF("MSUF_SetSpecAutoSwitchEnabled", v and true or false)
            RefreshAfterProfileChange(ctx)
        end,
        ProfilesMeta("specialization.auto_switch.enabled"))
    local assignHelpX = contentW >= 760 and min(430, floor(specInnerW * 0.47)) or 20
    local assignHelpY = contentW >= 760 and -73 or -112
    W.Text(autoCard, "Assign one existing profile to each specialization. None keeps the current profile.",
        assignHelpX, assignHelpY, max(220, specInnerW - assignHelpX - 20), T.colors.muted)
    if #specs == 0 then
        local emptyCard = W.ControlCard(spec, "No specialization data", nil, 20, specCardsY, specInnerW, specCardH)
        W.Text(emptyCard, "Specialization data is not available for this character yet.", 18, -54,
            max(220, specInnerW - 36), T.colors.dim)
    else
        local specCardW = floor((specInnerW - ((specCols - 1) * specCardGap)) / specCols)
        for i, s in ipairs(specs) do
            local col = ((i - 1) % specCols)
            local row = floor((i - 1) / specCols)
            local x = 20 + (col * (specCardW + specCardGap))
            local y = specCardsY - (row * (specCardH + specCardGap))
            local assignmentCard = W.ControlCard(spec, s.name, "Assigned profile", x, y, specCardW, specCardH)
            local dropW = max(160, specCardW - 36)
            local drop = W.Dropdown(assignmentCard, "Profile", function() return ProfileValues(true) end, dropW)
            MoveWidget(drop, assignmentCard, 18, -58, dropW)
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
    local function RefreshSpecState()
        local enabled = type(_G.MSUF_IsSpecAutoSwitchEnabled) == "function" and _G.MSUF_IsSpecAutoSwitchEnabled() or false
        local assigned = 0
        if type(_G.MSUF_GetSpecProfile) == "function" then
            for i = 1, #specs do
                local value = _G.MSUF_GetSpecProfile(specs[i].id)
                if value and value ~= "" and value ~= "None" then assigned = assigned + 1 end
            end
        end
        if W.SetCollapsibleBadges then
            W.SetCollapsibleBadges(spec, {
                { text = enabled and "Auto-switch: On" or "Auto-switch: Off", kind = enabled and "ok" or "muted", showWhenClosed = true },
                { text = M.Format("%d / %d assigned", assigned, #specs), kind = assigned > 0 and "info" or "muted", showWhenClosed = true },
            })
        end
    end
    if M.TrackCollapsibleRefresh then
        M.TrackCollapsibleRefresh(ctx, spec, RefreshSpecState)
    else
        M.TrackRefresh(ctx, RefreshSpecState)
    end

    local ioWide = contentW >= 980
    local ioH = ioWide and 462 or 824
    io = b:CollapsibleSection("profiles_io", "Import & Export", ioH, false)

    -- Import/export shares one text box intentionally: exporting fills the field, importing
    -- reads it, and tests can exercise both paths without clipboard APIs. The field keeps its
    -- contents after an import so the same string can be re-imported into a new profile.
    local ioInset, ioGap = 20, 18
    local ioInnerW = max(320, contentW - (ioInset * 2))
    local stringCardX, stringCardY, stringCardW, stringCardH
    local actionsCardX, actionsCardY, actionsCardW, actionsCardH
    if ioWide then
        stringCardX, stringCardY, stringCardW, stringCardH = ioInset, -42, floor((ioInnerW - ioGap) * 0.56), 398
        actionsCardX, actionsCardY, actionsCardW, actionsCardH = stringCardX + stringCardW + ioGap, -42,
            ioInnerW - stringCardW - ioGap, 398
    else
        stringCardX, stringCardY, stringCardW, stringCardH = ioInset, -42, ioInnerW, 342
        actionsCardX, actionsCardY, actionsCardW, actionsCardH = ioInset, -402, ioInnerW, 398
    end
    local stringCard = W.ControlCard(io, "Profile string",
        "Export fills this shared field; the string stays after an import so you can reuse it.",
        stringCardX, stringCardY, stringCardW, stringCardH)
    local actionsCard = W.ControlCard(io, "Export & import",
        "Create a backup first or import into a new profile for the safest workflow.",
        actionsCardX, actionsCardY, actionsCardW, actionsCardH)
    local ioButtonW = max(140, min(240, floor((actionsCardW - 40 - buttonGap) / 2)))
    local exportKindW = min(280, max(180, stringCardW - 40))
    local exportKind = W.Dropdown(stringCard, "Export kind",
        VT("all", "Full profile", "unitframe", "Unitframes", "castbar", "Castbars", "colors", "Colors",
            "gameplay", "Gameplay", "groupframe", "Group Frames"), exportKindW)
    M.BindDropdownWidget(ctx, exportKind,
        function() return M.profileExportKind or "all" end,
        function(v)
            M.SetMenuStateValue("profileExportKind", v or "all")
        end,
        ProfilesMeta("export.kind", "ephemeral"))
    blob = W.TextInput(stringCard, "Profile string", max(220, stringCardW - 40))
    blob._msuf2CommitOnBlur = false
    M.BindTextInput(ctx, blob,
        function() return M.profileImportString or "" end,
        function(value) M.profileImportString = tostring(value or "") end,
        false,
        ProfilesMeta("import_export.buffer", "ephemeral"))
    -- The box is multiline, so Enter inserts a newline instead of committing, and blur commits
    -- are off (a profile string in the undo history would be pure noise). Mirror user edits into
    -- the menu state directly: every refresh writes the state back into the box, so without this
    -- a pasted string is lost the moment anything refreshes the page - importing, or just
    -- flipping the new-profile toggle. Focus loss re-syncs in case a paste path skips userInput.
    local function MirrorImportBuffer(self) M.profileImportString = self:GetText() or "" end
    blob:HookScript("OnTextChanged", function(self, userInput)
        if userInput then MirrorImportBuffer(self) end
    end)
    blob:HookScript("OnEditFocusLost", MirrorImportBuffer)
    local export = ProfileButton(actionsCard, "Export", function()
        return ExportProfileString(M.profileExportKind or "all")
    end, nil, "export.generate", false, nil, nil, nil, ioButtonW)
    if M.MarkRuntimeControlComponent then M.MarkRuntimeControlComponent(heroExport, export) end
    if T.ApplyButtonRole then T.ApplyButtonRole(export, "primary") end
    local importCreateNew, importProfileName
    local import = T.Button(actionsCard, "Import to current profile", ioButtonW, buttonH)
    if T.CenterButtonLabel then T.CenterButtonLabel(import) end
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
    importCreateNew = W.SwitchAt(actionsCard, "Import and create new profile", 20, -176,
        max(220, actionsCardW - 40))
    RegisterControl(importCreateNew, ProfilesMeta("import.create_new_mode", "ephemeral"), "Import and create new profile", "toggle")
    AddProfileTooltip(importCreateNew, "Import and create new profile", "Creates a separate profile before importing so you can test the import without changing your current profile.")
    local importNameW = min(380, max(180, actionsCardW - 40))
    importProfileName = W.TextInput(actionsCard, "New profile name", importNameW)
    RegisterControl(importProfileName, ProfilesMeta("import.new_profile_name", "ephemeral"), "New profile name", "textinput")
    importProfileName._msuf2CommitOnBlur = false
    M.TrackRefresh(ctx, function()
        if importProfileName:HasFocus() then return end
        importProfileName:SetText(tostring(M.profileImportNewName or ""))
    end)
    local function ImportTextOrFail()
        if BlockCombatAction() then return nil end
        local text = blob:GetText()
        if text and text ~= "" then
            -- Importing refreshes the page, which repaints the box from the menu state; keep the
            -- payload there so the string survives for a second import into a new profile.
            M.profileImportString = text
            return text
        end
        PrintProfileMessage("|cffff0000", "Import failed (empty string).")
    end
    local function ImportIntoCurrent()
        local text = ImportTextOrFail()
        if not text then return false end
        if type(_G.MSUF_ImportFromString) ~= "function" then
            PrintProfileMessage("|cffff0000", "Import failed: profile import API is not available.")
            return false
        end
        -- `text` is a string the user pasted
        local called, imported = CallMSUF("MSUF_ImportFromString", text)
        if not called or imported ~= true then return false end
        ClearProfileHistory()
        M.RequestGeneralApply("MSUF2_PROFILE_IMPORT", { preview = true, applyAll = false, notify = false })
        RefreshAfterProfileChange(ctx)
        ShowImportReloadPrompt()
        return true
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
            PrintProfileMessage("|cffff0000", M.Format("Profile '%s' already exists.", name))
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
        local previous = ActiveProfileName()
        CallMSUF("MSUF_CreateProfile", name)
        if not ProfileExists(name) then
            PrintProfileMessage("|cffff0000", M.Format("Import failed: could not create profile '%s'.", name))
            return false
        end
        local previousExists = ProfileExists(previous)
        CallMSUF("MSUF_SwitchProfile", name)
        if _G.MSUF_ActiveProfile ~= name then
            if previousExists then CallMSUF("MSUF_SwitchProfile", previous) end
            DeleteCreatedProfile(name)
            PrintProfileMessage("|cffff0000", M.Format("Import failed: could not switch to profile '%s'.", name))
            return false
        end
        local called, imported = CallMSUF("MSUF_ImportFromString", text)
        if not called or imported ~= true then
            if previousExists then CallMSUF("MSUF_SwitchProfile", previous) end
            DeleteCreatedProfile(name)
            PrintProfileMessage("|cffff0000", M.Tr("Import failed."))
            RefreshAfterProfileChange(ctx)
            return false
        end
        ClearProfileHistory()
        M.RequestGeneralApply("MSUF2_PROFILE_IMPORT_NEW", { preview = true, applyAll = false, notify = false })
        RefreshAfterProfileChange(ctx)
        M.profileImportNewName = ""
        importProfileName:SetText("")
        ReloadAfterNewProfileImport(name)
        return true
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
        if M.ShowStatusFeedback then M.ShowStatusFeedback(M.Tr(M.profileImportCreateNew == true and "New-profile import on" or "New-profile import off"), "info", 1.2) end
        if M.RequestRefresh then M.RequestRefresh(ctx, "profiles-import-mode") elseif M.Refresh then M.Refresh(ctx) end
    end)
    --- Blizzard Edit Mode data is opt-in per session for BOTH directions
    --- (never exported by default). The switch drives the two ProfileIO
    --- flags directly; nothing is persisted across reloads.
    local includeBlizzEM = W.SwitchAt(actionsCard, "Include Blizzard Edit Mode layout", 20, -292,
        max(220, actionsCardW - 40))
    RegisterControl(includeBlizzEM, ProfilesMeta("import_export.blizzard_edit_mode", "ephemeral"),
        "Include Blizzard Edit Mode layout", "toggle")
    AddProfileTooltip(includeBlizzEM, "Include Blizzard Edit Mode layout",
        "Off (default): profile strings never carry or change the Blizzard Edit Mode arrangement. On: full-profile exports include it and imports apply it.")
    local function SyncBlizzEMFlag()
        local on = M.profileIncludeBlizzardEM == true
        includeBlizzEM:SetChecked(on)
        CallGlobal("MSUF_Profiles_SetExportBlizzardEditMode", on)
        CallGlobal("MSUF_Profiles_SetImportBlizzardEditMode", on)
    end
    includeBlizzEM:SetScript("OnClick", function(self)
        if BlockCombatAction() then
            self:SetChecked(M.profileIncludeBlizzardEM == true)
            return
        end
        M.profileIncludeBlizzardEM = not (M.profileIncludeBlizzardEM == true)
        SyncBlizzEMFlag()
    end)
    SyncBlizzEMFlag()
    local legacy = ProfileButton(actionsCard, "Import Legacy", function()
        if BlockCombatAction() then return end
        local text = blob:GetText()
        if text and text ~= "" and type(_G.MSUF_ImportLegacyFromString) == "function" then
            M.profileImportString = text
            CallMSUF("MSUF_ImportLegacyFromString", text)
            ClearProfileHistory()
            M.RequestGeneralApply("MSUF2_PROFILE_LEGACY_IMPORT", { preview = true, applyAll = false, notify = false })
            RefreshAfterProfileChange(ctx)
            if M.ShowStatusFeedback then M.ShowStatusFeedback(M.Tr("Legacy profile imported"), "ok", 1.7) end
        elseif M.ShowStatusFeedback then
            M.ShowStatusFeedback(M.Tr("Legacy import unavailable"), "danger", 1.8)
        end
    end, nil, "import.legacy", true, nil, nil, nil, ioButtonW)
    local wago = ProfileButton(actionsCard, "Browse Wago Profiles", function()
        if not CallMSUF("MSUF_ShowCopyLink", "Wago MSUF Profiles", WAGO_PROFILES_URL) then
            -- The box mirrors the menu state, so the fallback has to move the state as well or
            -- the next refresh paints the previous string back over the link.
            M.profileImportString = WAGO_PROFILES_URL
            blob:SetText(WAGO_PROFILES_URL)
            blob:HighlightText()
        end
    end, nil, "profiles.browse_wago", false, nil, nil, nil, ioButtonW)
    MoveWidget(exportKind, stringCard, 20, -76, exportKindW)
    local blobW = max(220, stringCardW - 40)
    MoveWidget(blob, stringCard, 20, -142, blobW)
    WrapMultilineProfileInput(blob, stringCard, 20, -166, blobW, ioWide and 220 or 162)
    PlaceActionRow(actionsCard, 20, export, import, -82)
    PlaceActionRow(actionsCard, 20, legacy, wago, -126)
    MoveWidget(importProfileName, actionsCard, 20, -230, importNameW)
    StyleProfileInput(importProfileName, importNameW, 28, false)
    local importModeHelp = W.Text(actionsCard, "", 20, -336, max(220, actionsCardW - 40), T.colors.muted)
    if importModeHelp and importModeHelp.SetWordWrap then importModeHelp:SetWordWrap(true) end
    local EXPORT_KIND_LABELS = {
        all = "Full profile",
        unitframe = "Unitframes",
        castbar = "Castbars",
        colors = "Colors",
        gameplay = "Gameplay",
        groupframe = "Group Frames",
    }
    local function RefreshImportMode()
        local createNew = M.profileImportCreateNew == true
        importCreateNew:SetChecked(createNew)
        if import.SetText then import:SetText(createNew and "Import new profile" or "Import to current profile") end
        if T.ApplyButtonRole then T.ApplyButtonRole(import, createNew and "success" or "danger") end
        W.SetControlShown(importProfileName, createNew)
        if not createNew and importProfileName.HasFocus and importProfileName:HasFocus() then importProfileName:ClearFocus() end
        if importModeHelp then
            importModeHelp:SetText(Tr(createNew
                and "Safe mode: creates a separate profile before importing and leaves the current profile available."
                or "Warning: importing now changes the active profile. Export or copy it first if you need a backup."))
        end
        if W.SetCollapsibleBadges then
            W.SetCollapsibleBadges(io, {
                { text = EXPORT_KIND_LABELS[M.profileExportKind or "all"] or "Full profile", kind = "info", showWhenClosed = true },
                { text = createNew and "Safe import mode" or "Current profile", kind = createNew and "ok" or "muted", showWhenClosed = true },
            })
        end
    end
    if M.TrackCollapsibleRefresh then
        M.TrackCollapsibleRefresh(ctx, io, RefreshImportMode)
    else
        M.TrackRefresh(ctx, RefreshImportMode)
    end
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
M.RegisterPage("profiles", { title = "MSUF Profiles", build = BuildProfiles, version = 7 })
M.RegisterPage("modules", { title = "MSUF Modules", build = BuildModules })
