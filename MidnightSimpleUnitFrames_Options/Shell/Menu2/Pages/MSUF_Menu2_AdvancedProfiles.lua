local addonName, MSUF = ...
MSUF = MSUF or {}
local FILE = "Shell/Menu2/Pages/MSUF_Menu2_AdvancedProfiles.lua"
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", FILE)
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
-- Core functions this page calls by their global names: required here at
-- load; click handlers resolve the rest through MSUF.Require when they run.
M.RequireGlobals("Shell/Menu2/Pages/MSUF_Menu2_AdvancedProfiles.lua", {
    "MSUF_GetAllProfiles",
    "MSUF_ShowReloadRecommendedPopup",
    "MSUF_ExportSelectionToString",
    "MSUF_IsSpecAutoSwitchEnabled",
    "MSUF_GetSpecProfile",
    "MSUF_ImportFromString",
    "MSUF_ImportIntoNewProfile",
})
-- The refresh closures and value getters below reach these on every page refresh: resolved once here.
local GetAllProfiles = MSUF.Require("MSUF_GetAllProfiles", FILE)
local IsSpecAutoSwitchEnabled = MSUF.Require("MSUF_IsSpecAutoSwitchEnabled", FILE)
local GetSpecProfile = MSUF.Require("MSUF_GetSpecProfile", FILE)
local GetDefaultProfileForNewCharacters = MSUF.Require("MSUF_GetDefaultProfileForNewCharacters", FILE)

-- Advanced Profiles page.
-- Builds profile copy/import/export/spec-switch controls and Wago import affordances.
-- Actual profile mutation stays in State/MSUF_Profiles.lua and import helpers.
local W = M.Widgets
local AP = M.AdvancedPage or {}
local T = M.Theme
local floor = math.floor
local max = math.max
local min = math.min
local G, SetValue, ControlMeta = AP.G, AP.SetValue, AP.ControlMeta
local function RegisterControl(widget, ...)
    AP.RegisterControl(widget, ...)
    local declaration = widget._msuf2ControlSchema
    M.ControlSchema.Owned(widget, "profiles", "profiles")
    if declaration then
        local current = widget._msuf2ControlSchema
        current.get, current.set = current.get or declaration.get, current.set or declaration.set
        current.action = current.action or declaration.action
    end
end
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
    ["import.execute"] = "import_profile_string",
    ["profiles.browse_wago"] = "copy_wago_profiles_link",
    ["new_character.default_profile"] = "set_new_character_profile",
}
local PROFILE_ACTION_INPUT_BY_PATH = {
    ["active_profile.select"] = "name",
    ["new_character.default_profile"] = "name",
    ["profile.create"] = "name",
    ["profile.copy_current"] = "name",
    ["import.execute"] = "value",
}
local function ProfilesMeta(path, classification, exact)
    local resolved = M.Assign({}, exact)
    resolved.settingKey = resolved.settingKey or PROFILE_SETTING_BY_PATH[path]
    resolved.actionKey = resolved.actionKey or PROFILE_ACTION_BY_PATH[path]
    resolved.actionInputArg = resolved.actionInputArg or PROFILE_ACTION_INPUT_BY_PATH[path]
    if path == "profile.delete_current" and resolved.actionFixedArgs == nil then
        resolved.actionFixedArgs = { name = { context = "activeProfile" } }
    end
    return ControlMeta("profiles", "advanced", path, classification, resolved)
end
local function ModulesMeta(path, classification, exact)
    local resolved = M.Assign({}, exact)
    if path == "style.enabled" then resolved.settingKey = resolved.settingKey or "general.styleEnabled" end
    return ControlMeta("modules", "advanced", path, classification, resolved)
end
-- The page's bound rows declare through Schema.Bind; the metadata names the ID and the setting or action key.
local function BindProfileControl(ctx, widget, kind, label, get, set, meta, scope, commitOnBlur)
    return M.ControlSchema.Bind(ctx, widget, { id = meta.controlId, kind = kind, labelKey = label,
        scope = scope or "profiles", applyDomain = "profiles", settingPath = meta.settingKey, meta = meta,
        get = get, set = set, commitOnBlur = commitOnBlur })
end
local MoveWidget = W.MoveWidget or AP.MoveWidget
local Tr = M.TranslateText or M.Tr
local VT = M.ValueTextList
local WAGO_PROFILES_URL = "https://wago.io/search/imports/wow/msuf"
local Trim = M.TrimText
local function SuiteProfiles()
    return MSUF.SuiteLink.Profiles()
end
local function SuiteExportAvailable()
    local profiles = SuiteProfiles()
    return profiles and type(profiles.Available) == "function" and profiles.Available() == true
end
local function ProfileExportValues()
    local values = {}
    if SuiteExportAvailable() then
        values[#values + 1] = { value = "suite_all", text = "Full profile (MSUF + Suite)" }
        local skinReady = MSUF.SuiteLink.SkinAddOnEnabled()
        -- Suite rows are translated here (one format key), so the picker shows them as is.
        values[#values + 1] = { value = "suite_module:skin", text = M.Format("Suite module: %s", Tr("Skinning")),
            translate = false, disabled = not skinReady }
        values[#values + 1] = { value = "all", text = "MSUF only - full profile" }
        for _, module in ipairs(MSUF.SuiteLink.ProfileModules()) do
            values[#values + 1] = { value = "suite_module:" .. module.id,
                text = M.Format("Suite module: %s", Tr(module.title)), translate = false }
        end
    else
        values[#values + 1] = { value = "all", text = "Full profile" }
    end
    return values
end
local function SuiteExport(kind)
    local profiles = SuiteProfiles()
    if not profiles then return nil, "MSUF Suite is not available" end
    if kind == "suite_all" then return profiles.Export() end
    return profiles.ExportModule(kind:sub(14))
end
local function SuiteImportKind(text)
    if type(text) ~= "string" then return nil end
    if text:match("^%s*MSUFS[123]:") then return "full" end
    if text:match("^%s*MSUFM2:") or text:match("^%s*MSKIN1:") then return "module" end
end
-- The unassigned row of a profile picker. No profile can be named "" (every
-- name entry point refuses it), so a real profile named "None" keeps its row.
local NO_PROFILE = ""
local function ProfileValues(includeNone)
    local values = {}
    if includeNone then values[#values + 1] = { value = NO_PROFILE, text = "None" } end
    local list = GetAllProfiles() or { "Default" }
    -- Names are typed by the user and shown as typed, never translated.
    for i = 1, #list do values[#values + 1] = { value = list[i], text = list[i], translate = false } end
    return values
end
-- WoW Forever binds profiles to Blizzard's two talent groups, keyed 1 and 2 by
-- State/MSUF_Profiles.lua, because every class has a single specialization there.
-- The rows reuse Blizzard's own Camelot talent-frame tab labels. Without them, or
-- without the group API, the page keeps its empty state.
local IS_FOREVER = MSUF.Client.IsForever == true
local function GetSpecMeta()
    if IS_FOREVER then
        local primary, secondary = DUAL_SPEC_PRIMARY, DUAL_SPEC_SECONDARY
        local specInfo = C_SpecializationInfo
        if type(primary) ~= "string" or primary == "" or type(secondary) ~= "string" or secondary == ""
            or type(specInfo) ~= "table" or type(specInfo.GetActiveSpecGroup) ~= "function" then
            return {}
        end
        return { { id = 1, name = primary }, { id = 2, name = secondary } }
    end
    local specialization = MSUF.Specialization
    local n = specialization.GetNumSpecializations and specialization.GetNumSpecializations() or 0
    local out = {}
    for i = 1, n do
        if specialization.GetSpecializationInfo then
            local specID, specName = specialization.GetSpecializationInfo(i)
            if type(specID) == "number" and type(specName) == "string" then out[#out + 1] = { id = specID, name = specName } end
        end
    end
    return out
end
M.GetProfileSpecializations = GetSpecMeta
local function RefreshAfterProfileChange(ctx)
    if M.frame and M.frame.RefreshStatus then M.frame:RefreshStatus() end
    if M.RequestRefresh then M.RequestRefresh(ctx, "profiles-change") elseif M.Refresh then M.Refresh(ctx) end
end
local function ActiveProfileName() return MSUF_ActiveProfile or "Default" end

local function ClearProfileHistory() if M.ClearHistory then M.ClearHistory() end end
--- message is an English key, or a format key followed by its arguments; it is
--- translated exactly once here (the status line gets the translated text).
local function PrintProfileMessage(color, message, ...)
    message = M.Format(tostring(message or ""), ...)
    if M.ShowStatusFeedback then
        local kind = tostring(color or ""):find("ff0000", 1, true) and "danger" or "info"
        M.ShowStatusFeedback(message, kind, kind == "danger" and 2.0 or 1.7, true)
    end
    print((color or "|cffffd700") .. "MSUF:|r " .. message)
end
-- M.BlockCombatAction (MSUF_Menu2_Bindings.lua) loads before every page.
local function BlockCombatAction()
    return M.BlockCombatAction() and true or false
end
local function StyleProfileInput(editBox, width, height, multiline)
    if not editBox then return editBox end
    local w = tonumber(width) or (editBox.GetWidth and editBox:GetWidth()) or 260
    local h = tonumber(height) or (editBox.GetHeight and editBox:GetHeight()) or 22
    editBox:SetSize(w, h)
    if editBox.SetMultiLine then editBox:SetMultiLine(multiline and true or false) end
    if editBox.SetJustifyV then editBox:SetJustifyV(multiline and "TOP" or "MIDDLE") end
    if editBox.SetTextInsets then
        local inset = multiline and 8 or 1
        editBox:SetTextInsets(8, 8, inset, inset)
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
    local scroll = PixelLayoutRegion(CreateFrame("ScrollFrame", nil, host))
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
    local function PaintHostBorder(color, alpha)
        if host.SetBackdropBorderColor then
            host:SetBackdropBorderColor(color[1], color[2], color[3], alpha or color[4] or 1)
        end
    end
    editBox:HookScript("OnEditFocusGained", function() PaintHostBorder(T.colors.accent, 0.95) end)
    editBox:HookScript("OnEditFocusLost", function() PaintHostBorder(T.colors.borderSoft) end)
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
-- Prompts are the safety boundary for destructive profile operations. Keep the
-- actual profile mutations inside their accept handlers so callers cannot
-- bypass confirmation by invoking helper functions directly. M.ShowPrompt
-- shows Blizzard's generic confirmation; nothing is written to
-- StaticPopupDialogs.
local ProfilePrompts = {}
local RESET_PROFILE_TEXT = "Reset profile '%s' to defaults?\n\n"
    .. "This resets the entire selected profile to the current MSUF factory defaults. Every menu in that profile will be affected."
local DELETE_PROFILE_TEXT = "Delete profile '%s'?\n\nThis removes the selected profile from MSUF. Other profiles are not affected, "
    .. "but this profile cannot be restored unless you exported or copied it first."
function ProfilePrompts.ConfirmReset(name, after)
    M.ShowPrompt("MSUF2_CONFIRM_RESET_PROFILE", {
        text = string.format(M.Tr(RESET_PROFILE_TEXT), name),
        accept = YES or M.Tr("Yes"),
        cancel = NO or M.Tr("No"),
        onAccept = function()
            if BlockCombatAction() then return end
            MSUF.Require("MSUF_ResetProfile", FILE)(name)
            ClearProfileHistory()
            if M.RequestGeneralDomains then M.RequestGeneralDomains("MSUF2_PROFILE_RESET", { preview = true, applyAll = false, notify = false }) end
            after()
            MSUF.Require("MSUF_ShowReloadRecommendedPopup", FILE)("Profile reset")
        end,
    })
end
function ProfilePrompts.ConfirmDelete(name, after)
    M.ShowPrompt("MSUF2_CONFIRM_DELETE_PROFILE", {
        text = string.format(M.Tr(DELETE_PROFILE_TEXT), name),
        accept = DELETE or M.Tr("Delete"),
        cancel = CANCEL or M.Tr("Cancel"),
        onAccept = function()
            if BlockCombatAction() then return end
            MSUF.Require("MSUF_DeleteProfile", FILE)(name)
            ClearProfileHistory()
            after()
        end,
    })
end
-- An import can stage Blizzard Edit Mode settings (Micro Menu, Bags) that only
-- the Edit Mode adapter's reload merges and saves (MSUF_EditMode_Blizzard.lua).
local function ReloadImportedUI()
    if MSUF.Client.SupportsBlizzardEditMode then
        return MSUF.Require("MSUF_BlizzardEditMode_ReloadUI", FILE)()
    end
    ReloadUI()
end
-- A reload cannot run in combat: the message tells the player to /reload afterwards.
local function ReloadBlockedInCombat(message, ...)
    if not (InCombatLockdown and InCombatLockdown()) then return false end
    PrintProfileMessage("|cffffd700", message, ...)
    return true
end
local function ShowImportReloadPrompt()
    if ReloadBlockedInCombat("Profile imported. Reload after combat with /reload.") then return end
    M.ShowPrompt("MSUF2_IMPORT_RELOAD_PROMPT", {
        text = M.Tr("Profile imported into the current profile.\n\nReload the UI now so every imported setting is applied?"),
        accept = RELOAD or M.Tr("Reload"),
        cancel = CANCEL or M.Tr("Not now"),
        onAccept = ReloadImportedUI,
    })
end
-- A profile switch swaps the whole DB under a live UI. Frames re-apply, but anything baked
-- at load time (group headers, module gating) only settles after a reload, so offer one.
local function ShowProfileSwitchReloadPrompt(profileName)
    local name = tostring(profileName or ActiveProfileName())
    if ReloadBlockedInCombat("Switched to profile '%s'. Reload after combat with /reload.", name) then return end
    M.ShowPrompt("MSUF2_PROFILE_SWITCH_RELOAD", {
        text = string.format(M.Tr("Switched to profile '%s'.\n\nA UI reload is required to fully apply this profile.\n\nReload now?"), name),
        accept = YES or M.Tr("Yes"),
        cancel = NO or M.Tr("No"),
        onAccept = function()
            if ReloadBlockedInCombat("Can't reload the UI in combat. Leave combat, then type /reload.") then return end
            ReloadUI()
        end,
    })
end
local function ReloadAfterNewProfileImport(profileName)
    if ReloadBlockedInCombat("Imported profile '%s'. Reload after combat with /reload.", tostring(profileName)) then return end
    if type(ReloadUI) == "function" then
        ReloadImportedUI()
    else
        PrintProfileMessage("|cffffd700", "Imported profile '%s'. Reload the UI with /reload.", tostring(profileName))
    end
end
local function ProfileExists(name)
    local gdb = MSUF_GlobalDB
    local profiles = type(gdb) == "table" and gdb.profiles or nil
    return type(profiles) == "table" and profiles[name] ~= nil
end
-- The page builds in stages that share one per-call state table. Every stage runs
-- once, in order, from ProfilesPage.Build; Prepare owns the helpers the rest use.
local ProfilesPage = {}
function ProfilesPage.Prepare(ctx)
    local b = W.PageBuilder(ctx)
    local contentW = b.width or ctx.width or 920
    local buttonW, buttonH, buttonGap = 190, 24, 14
    local PROFILE_TOOLTIP = { hook = true, titleAsLine = true, bodyColor = { 0.85, 0.85, 0.85 } }
    local function AddProfileTooltip(frame, title, text) return M.AddTooltip and M.AddTooltip(frame, tostring(title or ""), text, PROFILE_TOOLTIP) or frame end
    local function PlaceActionRow(parent, x, left, right, y)
        left:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        right:SetPoint("LEFT", left, "RIGHT", buttonGap, 0)
    end
    local function ProfileButton(parent, label, onClick, danger, semanticPath, confirmRequired, prepareValue, validateValue, directCommand, width)
        local btn = AP.Row(nil, parent, { "button", "advancedprofiles.btn.1", nil, { label, width or buttonW, buttonH } })
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

    local state = {}
    local function ConfigLocked()
        return (InCombatLockdown and InCombatLockdown())
            or (UnitAffectingCombat and UnitAffectingCombat("player"))
            or false
    end
    local function ExportProfileString(kind)
        kind = kind or M.profileExportKind or (SuiteExportAvailable() and "suite_all" or "all")
        local suiteKind = kind == "suite_all" or kind:match("^suite_module:") ~= nil
        local selected = M.profileExportUnits or { player = true }
        if kind == "unitselection" then
            local any = false
            for _, enabled in pairs(selected) do if enabled == true then any = true end end
            if not any then
                if M.ShowStatusFeedback then M.ShowStatusFeedback("Select at least one unitframe.", "danger", 1.8) end
                return false
            end
        end
        local value, reason
        if suiteKind then value, reason = SuiteExport(kind)
        else value = MSUF.Require("MSUF_ExportSelectionToString", FILE)(kind, selected) end
        if type(value) ~= "string" then
            if reason then PrintProfileMessage("|cffff0000", "Export failed: %s", tostring(reason)) end
            if M.ShowStatusFeedback then M.ShowStatusFeedback("Export failed", "danger", 1.8) end
            return false
        end
        M.profileImportString = value
        local blob = state.blob
        if blob then
            blob:SetText(value)
            blob:SetFocus()
            blob:HighlightText()
        end
        if M.ShowStatusFeedback then
            M.ShowStatusFeedback("Profile string ready - press Ctrl+C", "info", 1.8)
        end
        return true
    end
    local function StatusPill(parent, width, key)
        local pill = PixelLayoutRegion(CreateFrame("Frame", nil, parent))
        pill:SetSize(width, 22)
        local fill, edge = T.CreateSuperellipseLayers(pill, "_msuf2ProfileStatusPill", 1, "ARTWORK", "OVERLAY")
        pill._msuf2Fill, pill._msuf2Edge = fill, edge
        pill.text = AP.Row(nil, pill, { "font", "advancedprofiles.status." .. key, nil, { "GameFontDisableSmall", "", T.colors.text } })
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
            T.SetTranslatedText(pill.text, text or "")
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
    state.ctx, state.b, state.contentW = ctx, b, contentW
    state.buttonH, state.buttonGap = buttonH, buttonGap
    state.AddProfileTooltip, state.PlaceActionRow, state.ProfileButton = AddProfileTooltip, PlaceActionRow, ProfileButton
    state.ConfigLocked, state.ExportProfileString = ConfigLocked, ExportProfileString
    state.StatusPill, state.SetStatusPill = StatusPill, SetStatusPill
    return state
end
function ProfilesPage.Hero(state)
    local ctx, b, contentW = state.ctx, state.b, state.contentW
    local StatusPill, AddProfileTooltip, ExportProfileString = state.StatusPill, state.AddProfileTooltip, state.ExportProfileString

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

    local accent = PixelLayoutRegion(hero:CreateTexture(nil, "OVERLAY"))
    accent:SetPoint("TOPLEFT", hero, "TOPLEFT", 0, -2)
    accent:SetPoint("BOTTOMLEFT", hero, "BOTTOMLEFT", 0, 2)
    accent:SetWidth(4)
    accent:SetColorTexture(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 0.96)
    local profileMark = T.Panel(hero, nil, T.colors.panel2, T.colors.accent)
    profileMark:SetSize(54, 54)
    profileMark:SetPoint("TOPLEFT", hero, "TOPLEFT", 20, -24)
    local markText = AP.Row(nil, profileMark, { "font", "advancedprofiles.markText.3", nil, { "GameFontNormalLarge", "P", T.colors.text } })
    markText:SetPoint("CENTER")
    AP.LabelAt(hero, "ACTIVE PROFILE", 92, -21, 280, "GameFontDisableSmall", T.colors.accent)
    local activeName = AP.Row(nil, hero, { "font", "advancedprofiles.activeName.4", nil, { "GameFontNormalLarge", "", T.colors.text, "section" } })
    activeName:SetPoint("TOPLEFT", hero, "TOPLEFT", 92, -43)
    activeName:SetWidth(300)
    AP.LabelAt(hero, "Used by this character  \194\183  Account-wide profile", 92, -76, 360,
        "GameFontDisableSmall", T.colors.muted)

    local profileCountPill = StatusPill(hero, 104, "count")
    local specStatePill = StatusPill(hero, 146, "specialization")
    local safetyPill = StatusPill(hero, 168, "safety")
    local heroPillX = compactHero and 20 or min(max(430, floor(contentW * 0.45)), max(430, contentW - 690))
    profileCountPill:SetPoint("TOPLEFT", hero, "TOPLEFT", heroPillX, compactHero and -100 or -30)
    specStatePill:SetPoint("LEFT", profileCountPill, "RIGHT", 10, 0)
    safetyPill:SetPoint("TOPLEFT", hero, "TOPLEFT", heroPillX, compactHero and -132 or -64)

    local heroExport = AP.Row(nil, hero, { "button", "advancedprofiles.heroExport.5", nil, { "Export backup", 150, 34, { noSearch = true } } })
    local heroSwitch = AP.Row(nil, hero, { "button", "advancedprofiles.heroSwitch.6", nil, { "Switch profile", 168, 34, { noSearch = true } } })
    if T.CenterButtonLabel then
        T.CenterButtonLabel(heroExport)
        T.CenterButtonLabel(heroSwitch)
    end
    if T.ApplyButtonRole then T.ApplyButtonRole(heroSwitch, "primary") end
    if compactHero then
        heroExport:SetPoint("TOPRIGHT", hero, "TOPRIGHT", -202, -164)
        heroSwitch:SetPoint("TOPRIGHT", hero, "TOPRIGHT", -20, -164)
    else
        heroExport:SetPoint("TOPRIGHT", hero, "TOPRIGHT", -202, -34)
        heroSwitch:SetPoint("TOPRIGHT", hero, "TOPRIGHT", -20, -34)
        local combatHint = AP.LabelAt(hero, "Profile actions are blocked in combat.", contentW - 390, -78, 370,
            "GameFontDisableSmall", T.colors.muted)
        if combatHint and combatHint.SetJustifyH then combatHint:SetJustifyH("RIGHT") end
    end
    heroExport:SetScript("OnClick", function()
        local io = state.io
        if ExportProfileString(SuiteExportAvailable() and "suite_all" or "all") and io and W.FocusCollapsibleSection then
            W.FocusCollapsibleSection(io, { flash = true })
        end
    end)
    heroSwitch:SetScript("OnClick", function()
        local current = state.current
        if current and W.FocusCollapsibleSection then W.FocusCollapsibleSection(current, { flash = true }) end
    end)
    AddProfileTooltip(heroExport, "Export backup", "Creates a full-profile export string and opens Import & Export.")
    AddProfileTooltip(heroSwitch, "Switch profile", "Opens Profile Management. Profile switching is blocked during combat.")
    state.activeName, state.heroExport, state.heroSwitch = activeName, heroExport, heroSwitch
    state.profileCountPill, state.specStatePill, state.safetyPill = profileCountPill, specStatePill, safetyPill
end
function ProfilesPage.ManagementLayout(state)
    local b, contentW = state.b, state.contentW

    -- Profile switches rebuild live frames and can taint secure state in combat, so every
    -- entry point on this page goes through BlockCombatAction before touching profile APIs.
    local managementWide = contentW >= 1180
    local managementMedium = not managementWide and contentW >= 720
    local managementH = managementWide and 444 or (managementMedium and 620 or 884)
    local current = b:CollapsibleSection("profiles_management", "Profile Management", managementH, true)
    M.ControlSchema.Section(current, "profiles")
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
    local currentCard = AP.Row(nil, current, { "card", "advancedprofiles.currentCard.7", nil, { "Current profile", "Switch the profile used by this character.",
        currentCardX, currentCardY, currentCardW, currentCardH } })
    local createCard = AP.Row(nil, current, { "card", "advancedprofiles.createCard.8", nil,
        { "Create or duplicate", "Use a clear name so you can return to this setup later.",
        createCardX, createCardY, createCardW, createCardH } })
    local newCharCard = AP.Row(nil, current, { "card", "advancedprofiles.newCharCard.9", nil,
        { "New characters", "Choose the starting profile for new characters.",
        newCharCardX, newCharCardY, newCharCardW, newCharCardH } })
    local dangerColor = T.colors.danger or { 0.88, 0.28, 0.28, 1 }
    local dangerPanel = T.Panel(current, nil,
        { 0.090, 0.018, 0.030, 0.94 },
        { dangerColor[1], dangerColor[2], dangerColor[3], 0.70 })
    dangerPanel:SetPoint("TOPLEFT", current, "TOPLEFT", dangerX, dangerY)
    dangerPanel:SetSize(dangerW, dangerH)
    local dangerAccent = PixelLayoutRegion(dangerPanel:CreateTexture(nil, "OVERLAY"))
    dangerAccent:SetPoint("TOPLEFT", dangerPanel, "TOPLEFT", 0, -2)
    dangerAccent:SetPoint("BOTTOMLEFT", dangerPanel, "BOTTOMLEFT", 0, 2)
    dangerAccent:SetWidth(4)
    dangerAccent:SetColorTexture(dangerColor[1], dangerColor[2], dangerColor[3], 0.92)
    AP.LabelAt(dangerPanel, "!", 20, -22, 18, "GameFontNormal", dangerColor)
    AP.LabelAt(dangerPanel, "Danger zone", 48, -18, max(160, dangerW - 72), "GameFontNormal", T.colors.text)
    AP.LabelAt(dangerPanel, "These actions change or remove the complete active profile.", 48, -42,
        max(220, dangerW - 72), "GameFontDisableSmall", T.colors.muted)
    AP.LabelAt(dangerPanel, "Export or copy the profile first if you may want to restore it later.", 20,
        managementWide and -96 or -82, max(260, dangerW - 40), "GameFontDisableSmall", T.colors.text)
    state.current, state.managementWide, state.managementMedium = current, managementWide, managementMedium
    state.currentCard, state.createCard, state.newCharCard, state.dangerPanel = currentCard, createCard, newCharCard, dangerPanel
    state.currentCardW, state.createCardW, state.newCharCardW, state.dangerW = currentCardW, createCardW, newCharCardW, dangerW
end
local function BuildNewCharacterDefaults(state)
    local ctx, newCharCard, newCharCardW = state.ctx, state.newCharCard, state.newCharCardW
    -- "Active profile" above is a per-character binding into an account-wide
    -- pool of profiles. This picks what a character that has never run MSUF
    -- starts on. The engine validates the stored name on every login and falls
    -- back to "Default" if the profile was deleted, so "None" is always safe.
    local newCharW = max(180, newCharCardW - 40)
    AP.Row(nil, newCharCard, { "dropdown", "advancedprofiles.newCharDrop.12", nil,
        { "Default profile", function() return ProfileValues(true) end, newCharW },
        bind = function(newCharDrop)
            newCharDrop._msuf2StableSearchLabel = "Default profile"
            MoveWidget(newCharDrop, newCharCard, 20, -78, newCharW)
            BindProfileControl(ctx, newCharDrop, "dropdown", "Default profile",
                function() return GetDefaultProfileForNewCharacters() or NO_PROFILE end,
                function(v)
                    MSUF.Require("MSUF_SetDefaultProfileForNewCharacters", FILE)((v ~= NO_PROFILE) and v or nil)
                    RefreshAfterProfileChange(ctx)
                end,
                ProfilesMeta("new_character.default_profile", "action"))
        end })
    local newCharHelp = AP.Row(nil, newCharCard, { "text", "advancedprofiles.newCharHelp.13", nil, { "Existing characters are not changed.", 20, -146,
        max(180, newCharCardW - 40), T.colors.muted } })
    if newCharHelp and newCharHelp.SetWordWrap then newCharHelp:SetWordWrap(true) end
end
-- The active-profile picker. Switching is blocked in combat: the picker then snaps back to
-- the loaded profile before anything else runs.
local function BuildProfilePicker(state)
    local ctx = state.ctx
    local fieldW = max(180, state.currentCardW - 40)
    local profileDrop = AP.Row(nil, state.currentCard, { "dropdown", ProfilesMeta("active_profile.select").controlId, nil,
        { "Active profile", {}, fieldW },
        bind = AP.NativeInput })
    -- The selected value is a profile name; search keeps the control name.
    profileDrop._msuf2StableSearchLabel = "Active profile"
    RegisterControl(profileDrop, ProfilesMeta("active_profile.select", "action", { historyMode = "none" }), "Active profile", "dropdown", ProfileValues)
    if M.MarkRuntimeControlComponent then M.MarkRuntimeControlComponent(state.heroSwitch, profileDrop) end
    profileDrop:SetOnValueChanged(function(value)
        if BlockCombatAction() then
            profileDrop:SetValue(ActiveProfileName())
            return
        end
        local wanted = value and value ~= "" and value ~= MSUF_ActiveProfile and value or nil
        if wanted then
            MSUF.Require("MSUF_SwitchProfile", FILE)(wanted)
            if MSUF_ActiveProfile == wanted then ClearProfileHistory() end
        end
        M.RequestGeneralDomains("MSUF2_PROFILE_SWITCH", { preview = true, applyAll = false, notify = false })
        RefreshAfterProfileChange(ctx)
        -- The active profile is the switch's completion receipt.
        if wanted and MSUF_ActiveProfile == wanted then ShowProfileSwitchReloadPrompt(wanted) end
    end)
    M.TrackRefresh(ctx, function()
        profileDrop:SetValues(ProfileValues(false))
        profileDrop:SetValue(ActiveProfileName())
    end)
    return profileDrop, fieldW
end
-- Create and Copy share one name field; the new name must be free before either one runs.
local function ProfileWasCreated(prepared)
    return type(prepared) == "table" and prepared.name ~= "" and not prepared.existed and ProfileExists(prepared.name)
end
local function BuildCreateRow(state)
    local ctx, createCard, ProfileButton = state.ctx, state.createCard, state.ProfileButton
    local createFieldW = max(180, state.createCardW - 40)
    local createButtonW = max(120, floor((state.createCardW - 40 - state.buttonGap) / 2))
    local nameInput = AP.Row(nil, createCard, { "textinput", "advancedprofiles.nameInput.11", nil,
        { "New profile name", createFieldW },
        bind = function(nameInput)
            BindProfileControl(ctx, nameInput, "textinput", "New profile name",
                function() return M.profileCreateCopyName or "" end,
                function(value) M.profileCreateCopyName = Trim(value or "") end,
                ProfilesMeta("draft.create_copy_name", "ephemeral"), nil, true)
        end })
    local PrepareProfileName = function(value)
        local name = Trim(value)
        local prepared = { name = name, existed = name ~= "" and ProfileExists(name) or false }
        if name ~= "" then
            M.profileCreateCopyName = name
            nameInput:SetText(name)
        end
        return prepared
    end
    local create = ProfileButton(createCard, "Create profile", function()
        if BlockCombatAction() then return end
        local name = Trim(nameInput:GetText())
        if name and name ~= "" then
            local created = MSUF.Require("MSUF_CreateProfile", FILE)(name)
            if created == true then
                MSUF.Require("MSUF_SwitchProfile", FILE)(name)
                ClearProfileHistory()
            end
        end
        M.profileCreateCopyName = ""
        nameInput:SetText("")
        RefreshAfterProfileChange(ctx)
    end, nil, "profile.create", false, PrepareProfileName, ProfileWasCreated, nil, createButtonW)
    local copy = ProfileButton(createCard, "Copy current profile", function()
        if BlockCombatAction() then return end
        local name = Trim(nameInput:GetText())
        if name and name ~= "" then
            local copied = MSUF.Require("MSUF_CopyProfile", FILE)(ActiveProfileName(), name)
            if copied then MSUF.Require("MSUF_SwitchProfile", FILE)(name) end
            ClearProfileHistory()
            M.profileCreateCopyName = ""
            nameInput:SetText("")
            RefreshAfterProfileChange(ctx)
        end
    end, nil, "profile.copy_current", false, PrepareProfileName, ProfileWasCreated, nil, createButtonW)
    return nameInput, create, copy, createFieldW
end
-- Reset and Delete act on the active profile; Search reaches them through the command tables,
-- the buttons go through the confirmation prompts.
local function BuildDangerRow(state)
    local ctx, dangerPanel, ProfileButton = state.ctx, state.dangerPanel, state.ProfileButton
    local dangerButtonW = max(140, min(250, floor((state.dangerW - 54) / 2)))
    local reset = ProfileButton(dangerPanel, "Reset to defaults", function()
        if BlockCombatAction() then return end
        if M.ShowPageResetConfirm then
            M.ShowPageResetConfirm("profiles")
            return
        end
        ProfilePrompts.ConfirmReset(ActiveProfileName(), function() RefreshAfterProfileChange(ctx) end)
    end, nil, "profile.reset_current", true, nil, nil, {
        kind = "button", historyMode = "none", confirmRequired = true,
        set = function()
            if BlockCombatAction() then return false end
            -- The Search already supplied the explicit destructive-action
            -- confirmation. Execute the same reset/apply/reload path used by
            -- the menu popup instead of bypassing its post-reset work.
            if type(M.ResetPageToDefaults) == "function" then
                if M.ResetPageToDefaults("profiles") ~= true then return false end
                RefreshAfterProfileChange(ctx)
                return true
            end
            local result = MSUF.Require("MSUF_ResetProfile", FILE)(ActiveProfileName())
            if result == false then return false end
            ClearProfileHistory()
            RefreshAfterProfileChange(ctx)
            return true
        end,
    }, dangerButtonW)
    local delete = ProfileButton(dangerPanel, "Delete current profile", function()
        if BlockCombatAction() then return end
        local name = ActiveProfileName()
        if name == "Default" then return end
        ProfilePrompts.ConfirmDelete(name, function() RefreshAfterProfileChange(ctx) end)
    end, true, "profile.delete_current", true, nil, nil, {
        kind = "button", historyMode = "none", confirmRequired = true,
        set = function()
            if BlockCombatAction() then return false end
            local name = ActiveProfileName()
            if name == "Default" then return false end
            local result = MSUF.Require("MSUF_DeleteProfile", FILE)(name)
            if result == false then return false end
            ClearProfileHistory()
            RefreshAfterProfileChange(ctx)
            return true
        end,
    }, dangerButtonW)
    return reset, delete, dangerButtonW
end
function ProfilesPage.ManagementControls(state)
    local ctx, buttonGap, current = state.ctx, state.buttonGap, state.current
    local managementWide, managementMedium = state.managementWide, state.managementMedium
    local currentCard, createCard, dangerPanel = state.currentCard, state.createCard, state.dangerPanel
    local currentCardW, dangerW = state.currentCardW, state.dangerW
    local PlaceActionRow, ConfigLocked, SetStatusPill = state.PlaceActionRow, state.ConfigLocked, state.SetStatusPill
    local profileDrop, fieldW = BuildProfilePicker(state)
    local nameInput, create, copy, createFieldW = BuildCreateRow(state)
    local reset, delete, dangerButtonW = BuildDangerRow(state)
    MoveWidget(profileDrop, currentCard, 20, -78, fieldW)
    local currentStatus = AP.LabelAt(currentCard, "", 20, -150, max(180, currentCardW - 40),
        "GameFontDisableSmall", T.colors.muted)
    MoveWidget(nameInput, createCard, 20, -78, createFieldW)
    StyleProfileInput(nameInput, createFieldW, 28, false)
    PlaceActionRow(createCard, 20, create, copy, -148)
    local dangerActionsX = max(20, dangerW - (dangerButtonW * 2) - buttonGap - 20)
    local dangerActionsY = managementWide and -70 or (managementMedium and -104 or -138)
    PlaceActionRow(dangerPanel, dangerActionsX, reset, delete, dangerActionsY)

    BuildNewCharacterDefaults(state)

    local function RefreshManagementState()
        local active = ActiveProfileName()
        local profiles = ProfileValues(false)
        local profileCount = #profiles
        local profileCountText = profileCount == 1 and M.Tr("1 profile") or M.Format("%d profiles", profileCount)
        local specAuto = IsSpecAutoSwitchEnabled() or false
        local locked = ConfigLocked()
        T.SetTranslatedText(state.activeName, active) -- a profile name, shown as typed
        if currentStatus then
            T.SetTranslatedText(currentStatus, M.Format("Currently loaded and applied: %s", active))
        end
        SetStatusPill(state.profileCountPill, profileCountText, "info")
        SetStatusPill(state.specStatePill, M.Tr(specAuto and "Spec switching: On" or "Spec switching: Off"), specAuto and "ok" or "warn")
        SetStatusPill(state.safetyPill, M.Tr(locked and "Combat locked" or "Safe to manage now"), locked and "danger" or "ok")
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
end
-- The danger zone's other actions touch the active profile only. This one opens
-- a list of the whole account pool (MSUF_Menu2_ProfileCleanup.lua) to delete
-- several profiles at once.
function ProfilesPage.ProfileCleanup(state)
    local ctx, dangerPanel = state.ctx, state.dangerPanel
    local width = max(150, min(220, state.dangerW - 220))
    local cleanup = AP.Row(nil, dangerPanel, { "button", "advancedprofiles.cleanup.14", nil,
        { "Delete several profiles", width, state.buttonH, { noSearch = true, history = false } } })
    T.SkinDangerButton(cleanup)
    T.CenterButtonLabel(cleanup)
    cleanup:SetPoint("TOPRIGHT", dangerPanel, "TOPRIGHT", -20, -14)
    cleanup:SetScript("OnClick", function()
        M.ProfileCleanup.Open(function() RefreshAfterProfileChange(ctx) end)
    end)
    state.AddProfileTooltip(cleanup, "Delete several profiles",
        "Choose profiles in a list and delete them together. The active profile and Default are not offered.")
end
function ProfilesPage.Specializations(state)
    local ctx, b, contentW = state.ctx, state.b, state.contentW
    local specs = GetSpecMeta()
    local specCols = contentW >= 1380 and 4 or contentW >= 980 and 3 or contentW >= 640 and 2 or 1
    specCols = min(specCols, max(1, #specs))
    local specRows = max(1, math.ceil(max(1, #specs) / specCols))
    local specAutoCardH = contentW >= 760 and 126 or 156
    local specCardH, specCardGap = 122, 16
    local specCardsY = -42 - specAutoCardH - 18
    local specH = math.abs(specCardsY) + (specRows * specCardH) + ((specRows - 1) * specCardGap) + 20

    -- Spec-profile rows depend on WoW specialization APIs. The empty-state path keeps the
    -- page usable for low-level characters and offline smoke tests where those APIs are nil.
    local spec = b:CollapsibleSection("profiles_specs", "Specialization Profiles", specH, true)
    M.ControlSchema.Section(spec, "profiles")
    local specInnerW = max(300, contentW - 40)
    local autoCard = AP.Row(nil, spec, { "card", "advancedprofiles.autoCard.15", nil, { "Automatic switching",
        "MSUF switches after combat if specialization changes while combat-locked.",
        20, -42, specInnerW, specAutoCardH } })
    local auto = AP.Row(nil, autoCard, { "switch", "advancedprofiles.auto.16", nil, { "Auto-switch profile by specialization", 20, -66,
        min(380, max(220, specInnerW - 40)) }, bind = function(widget)
        BindProfileControl(ctx, widget, "toggle", "Auto-switch profile by specialization",
            function()
                return IsSpecAutoSwitchEnabled() or false
            end,
            function(v)
                MSUF.Require("MSUF_SetSpecAutoSwitchEnabled", FILE)(v and true or false)
                RefreshAfterProfileChange(ctx)
            end,
            ProfilesMeta("specialization.auto_switch.enabled"))
    end })
    W.SetControlEnabled(auto, #specs > 0)
    local assignHelpX = contentW >= 760 and min(430, floor(specInnerW * 0.47)) or 20
    local assignHelpY = contentW >= 760 and -73 or -112
    AP.Row(nil, autoCard, { "text", "advancedprofiles.text.17", nil, { "Assign one existing profile to each specialization. None keeps the current profile.",
        assignHelpX, assignHelpY, max(220, specInnerW - assignHelpX - 20), T.colors.muted } })
    if #specs == 0 then
        local emptyCard = AP.Row(nil, spec, { "card", "advancedprofiles.emptyCard.18", nil,
            { "No specialization data", nil, 20, specCardsY, specInnerW, specCardH } })
        AP.Row(nil, emptyCard, { "text", "advancedprofiles.text.19", nil, { "Specialization data is not available for this character yet.", 18, -54,
            max(220, specInnerW - 36), T.colors.dim } })
    else
        local specCardW = floor((specInnerW - ((specCols - 1) * specCardGap)) / specCols)
        for i, s in ipairs(specs) do
            local col = ((i - 1) % specCols)
            local row = floor((i - 1) / specCols)
            local x = 20 + (col * (specCardW + specCardGap))
            local y = specCardsY - (row * (specCardH + specCardGap))
            local assignmentCard = AP.Row(nil, spec, { "card", "advancedprofiles.specialization." .. s.id .. ".card", nil,
                { s.name, "Assigned profile", x, y, specCardW, specCardH } })
            local dropW = max(160, specCardW - 36)
            local drop = AP.Row(nil, assignmentCard, { "dropdown", "advancedprofiles.drop.21", nil,
                { "Profile", function() return ProfileValues(true) end, dropW },
                bind = function(drop)
                    drop._msuf2StableSearchLabel = "Profile"
                    MoveWidget(drop, assignmentCard, 18, -58, dropW)
                    BindProfileControl(ctx, drop, "dropdown", "Profile",
                        function()
                            return GetSpecProfile(s.id) or NO_PROFILE
                        end,
                        function(v)
                            MSUF.Require("MSUF_SetSpecProfile", FILE)(s.id, (v ~= NO_PROFILE) and v or nil)
                            RefreshAfterProfileChange(ctx)
                        end,
                        ProfilesMeta("specialization.mapping.slot." .. tostring(i), "action", {
                            actionKey = "set_spec_profile",
                        }))
                end })
        end
    end
    local function RefreshSpecState()
        local enabled = IsSpecAutoSwitchEnabled() or false
        local assigned = 0
        for i = 1, #specs do
            local value = GetSpecProfile(specs[i].id)
            if value and (value ~= "None" or ProfileExists(value)) then assigned = assigned + 1 end
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
end
function ProfilesPage.ImportExport(state)
    local ctx, b, contentW, buttonH, buttonGap = state.ctx, state.b, state.contentW, state.buttonH, state.buttonGap
    local ProfileButton, AddProfileTooltip = state.ProfileButton, state.AddProfileTooltip
    local heroExport, ExportProfileString = state.heroExport, state.ExportProfileString

    local ioWide = contentW >= 980
    local ioH = ioWide and 462 or 824
    local io = b:CollapsibleSection("profiles_io", "Import & Export", ioH, false)
    M.ControlSchema.Section(io, "profiles")

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
    local stringCard = AP.Row(nil, io, { "card", "advancedprofiles.stringCard.22", nil, { "Profile string",
        "Export fills this shared field; the string stays after an import so you can reuse it.",
        stringCardX, stringCardY, stringCardW, stringCardH } })
    local actionsCard = AP.Row(nil, io, { "card", "advancedprofiles.actionsCard.23", nil, { "Export & import",
        "Create a backup first or import into a new profile for the safest workflow.",
        actionsCardX, actionsCardY, actionsCardW, actionsCardH } })
    local ioButtonW = max(140, min(240, floor((actionsCardW - 40 - buttonGap) / 2)))
    local exportKindW = min(280, max(180, stringCardW - 40))
    local exportValues = ProfileExportValues()
    for _, item in ipairs(VT("unitframe", "Unitframes", "castbar", "Castbars", "colors", "Colors",
        "gameplay", "Gameplay", "groupframe", "Group Frames", "unitselection", "Selected unitframes")) do
        exportValues[#exportValues + 1] = item
    end
    local exportKind = AP.Row(nil, stringCard, { "dropdown", "advancedprofiles.exportKind.24", nil,
        { "Export kind", exportValues, exportKindW },
        bind = function(exportKind)
        BindProfileControl(ctx, exportKind, "dropdown", "Export kind",
            function() return M.profileExportKind or (SuiteExportAvailable() and "suite_all" or "all") end,
            function(v)
                M.SetMenuStateValue("profileExportKind", v or "all")
                if v == "unitselection" and state.unitSelectionSection and W.FocusCollapsibleSection then
                    W.FocusCollapsibleSection(state.unitSelectionSection)
                end
            end,
            ProfilesMeta("export.kind", "ephemeral"))
    end })
    local blob = AP.Row(nil, stringCard, { "textinput", "advancedprofiles.blob.25", nil, { "Profile string", max(220, stringCardW - 40) }, bind = function(blob)
        blob._msuf2CommitOnBlur = false
        BindProfileControl(ctx, blob, "textinput", "Profile string",
            function() return M.profileImportString or "" end,
            function(value) M.profileImportString = tostring(value or "") end,
            ProfilesMeta("import_export.buffer", "ephemeral"), nil, false)
    end })
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
        return ExportProfileString(M.profileExportKind or (SuiteExportAvailable() and "suite_all" or "all"))
    end, nil, "export.generate", false, nil, nil, nil, ioButtonW)
    if M.MarkRuntimeControlComponent then M.MarkRuntimeControlComponent(heroExport, export) end
    if T.ApplyButtonRole then T.ApplyButtonRole(export, "primary") end
    local importCreateNew, importProfileName
    local import = AP.Row(nil, actionsCard, { "button", "advancedprofiles.import.26", nil, { "Import to current profile", ioButtonW, buttonH } })
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
                if payload ~= "" then
                    M.profileImportString = payload
                    blob:SetText(payload)
                end
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
    AddProfileTooltip(import, "Import to current profile",
        "Applies the import string to the active profile. Export or copy your profile first if you want an easy backup.")
    importCreateNew = AP.Row(nil, actionsCard, { "switch", ProfilesMeta("import.create_new_mode").controlId, nil, { "Import and create new profile", 20, -176,
        max(220, actionsCardW - 40) }, bind = AP.NativeInput })
    RegisterControl(importCreateNew, ProfilesMeta("import.create_new_mode", "ephemeral"), "Import and create new profile", "toggle")
    AddProfileTooltip(importCreateNew, "Import and create new profile",
        "Creates a separate profile before importing so you can test the import without changing your current profile.")
    local importNameW = min(380, max(180, actionsCardW - 40))
    importProfileName = AP.Row(nil, actionsCard, { "textinput", ProfilesMeta("import.new_profile_name").controlId, nil,
        { "New profile name", importNameW },
        bind = AP.NativeInput })
    RegisterControl(importProfileName, ProfilesMeta("import.new_profile_name", "ephemeral"), "New profile name", "textinput")
    importProfileName._msuf2CommitOnBlur = false
    M.TrackRefresh(ctx, function()
        if importProfileName:HasFocus() then return end
        importProfileName:SetText(tostring(M.profileImportNewName or ""))
    end)
    state.io, state.ioWide, state.stringCard, state.actionsCard = io, ioWide, stringCard, actionsCard
    state.stringCardW, state.actionsCardW, state.ioButtonW = stringCardW, actionsCardW, ioButtonW
    state.exportKind, state.exportKindW, state.blob = exportKind, exportKindW, blob
    state.export, state.import, state.importCreateNew = export, import, importCreateNew
    state.importProfileName, state.importNameW = importProfileName, importNameW
end
-- Both import paths read the shared text box, refresh the page and clear the menu history
-- once the profile data changed.
local function BuildImportHandlers(state)
    local ctx, blob, importProfileName = state.ctx, state.blob, state.importProfileName
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
        local suiteKind = SuiteImportKind(text)
        if suiteKind == "full" then
            M.SetMenuStateValue("profileImportCreateNew", true)
            PrintProfileMessage("|cffffd700", "Full MSUF + Suite imports create a new profile. Enter a name and import again.")
            RefreshAfterProfileChange(ctx)
            return false
        elseif suiteKind == "module" then
            local suite = SuiteProfiles()
            if not suite then
                PrintProfileMessage("|cffff0000", "Install MSUF Suite to import this module.")
                return false
            end
            local ok, reason = suite.ImportModule(text)
            if not ok then
                PrintProfileMessage("|cffff0000", "Module import failed: %s", tostring(reason))
                return false
            end
            ClearProfileHistory()
            RefreshAfterProfileChange(ctx)
            return true
        end
        -- `text` is a string the user pasted
        local imported = MSUF.Require("MSUF_ImportFromString", FILE)(text)
        if imported ~= true then return false end
        ClearProfileHistory()
        M.RequestGeneralDomains("MSUF2_PROFILE_IMPORT", { preview = true, applyAll = false, notify = false })
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
            PrintProfileMessage("|cffff0000", "Profile '%s' already exists.", name)
            return false
        end
        local suiteKind = SuiteImportKind(text)
        if suiteKind then
            local suite = SuiteProfiles()
            if not suite then
                PrintProfileMessage("|cffff0000", "Install MSUF Suite to import this profile.")
                return false
            end
            local ok, reason
            if suiteKind == "full" then ok, reason = suite.Import(name, text)
            else ok, reason = suite.ImportModuleIntoNew(name, text) end
            if not ok then
                PrintProfileMessage("|cffff0000", "Suite import failed: %s", tostring(reason))
                return false
            end
            ClearProfileHistory()
            RefreshAfterProfileChange(ctx)
            M.profileImportNewName = ""
            importProfileName:SetText("")
            ReloadAfterNewProfileImport(name)
            return true
        end

        -- MSUF_ImportIntoNewProfile decodes, validates and stages the string before it creates
        -- or switches a profile; a rejected string leaves SavedVariables untouched.
        local ok, _, stage = MSUF.Require("MSUF_ImportIntoNewProfile", FILE)(name, text)
        if ok ~= true then
            if stage == "create" then
                PrintProfileMessage("|cffff0000", "Import failed: could not create profile '%s'.", name)
                RefreshAfterProfileChange(ctx)
            elseif stage == "switch" then
                PrintProfileMessage("|cffff0000", "Import failed: could not switch to profile '%s'.", name)
                RefreshAfterProfileChange(ctx)
            elseif stage == "exists" then
                PrintProfileMessage("|cffff0000", "Profile '%s' already exists.", name)
            else
                PrintProfileMessage("|cffff0000", "Import failed.")
            end
            return false
        end
        ClearProfileHistory()
        M.RequestGeneralDomains("MSUF2_PROFILE_IMPORT_NEW", { preview = true, applyAll = false, notify = false })
        RefreshAfterProfileChange(ctx)
        M.profileImportNewName = ""
        importProfileName:SetText("")
        ReloadAfterNewProfileImport(name)
        return true
    end
    return ImportIntoCurrent, ImportIntoNewProfile
end
--- Blizzard Edit Mode data is opt-in per session for BOTH directions
--- (never exported by default). The switch drives the two ProfileIO
--- flags directly; nothing is persisted across reloads.
local function BuildEditModeToggle(state)
    local actionsCard, actionsCardW, AddProfileTooltip = state.actionsCard, state.actionsCardW, state.AddProfileTooltip
    local includeBlizzEM = AP.Row(nil, actionsCard, { "switch", ProfilesMeta("import_export.blizzard_edit_mode").controlId, nil,
        { "Include Blizzard Edit Mode layout", 20, -292, max(220, actionsCardW - 40) }, bind = AP.NativeInput })
    RegisterControl(includeBlizzEM, ProfilesMeta("import_export.blizzard_edit_mode", "ephemeral"),
        "Include Blizzard Edit Mode layout", "toggle")
    AddProfileTooltip(includeBlizzEM, "Include Blizzard Edit Mode layout",
        "Off (default): profile strings never carry or change the Blizzard Edit Mode arrangement. On: full-profile exports include it and imports apply it.")
    local function SyncBlizzEMFlag()
        local on = M.profileIncludeBlizzardEM == true
        includeBlizzEM:SetChecked(on)
        MSUF.Require("MSUF_Profiles_SetExportBlizzardEditMode", FILE)(on)
        MSUF.Require("MSUF_Profiles_SetImportBlizzardEditMode", FILE)(on)
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
end
-- The mode switch repaints the import button, the help line and the section badges.
local function TrackImportMode(state, importModeHelp)
    local ctx, io, import = state.ctx, state.io, state.import
    local importCreateNew, importProfileName = state.importCreateNew, state.importProfileName
    local EXPORT_KIND_LABELS = {
        all = SuiteExportAvailable() and "MSUF only" or "Full profile",
        suite_all = "MSUF + Suite",
        unitframe = "Unitframes",
        unitselection = "Selected unitframes",
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
            importModeHelp:SetText(createNew
                and "Safe mode: creates a separate profile before importing and leaves the current profile available."
                or "Warning: importing now changes the active profile. Export or copy it first if you need a backup.")
        end
        if W.SetCollapsibleBadges then
            local exportKindValue = M.profileExportKind or (SuiteExportAvailable() and "suite_all" or "all")
            local exportLabel = EXPORT_KIND_LABELS[exportKindValue]
            if not exportLabel and exportKindValue:match("^suite_module:") then
                exportLabel = MSUF.SuiteLink.ModuleTitle(exportKindValue:sub(14))
            end
            W.SetCollapsibleBadges(io, {
                { text = exportLabel or "Full profile", kind = "info", showWhenClosed = true },
                { text = createNew and "Safe import mode" or "Current profile", kind = createNew and "ok" or "muted", showWhenClosed = true },
            })
        end
    end
    if M.TrackCollapsibleRefresh then
        M.TrackCollapsibleRefresh(ctx, io, RefreshImportMode)
    else
        M.TrackRefresh(ctx, RefreshImportMode)
    end
end
function ProfilesPage.ImportActions(state)
    local ctx, ioWide, stringCard, actionsCard = state.ctx, state.ioWide, state.stringCard, state.actionsCard
    local stringCardW, actionsCardW, ioButtonW = state.stringCardW, state.actionsCardW, state.ioButtonW
    local exportKind, exportKindW, blob = state.exportKind, state.exportKindW, state.blob
    local export, import, importCreateNew = state.export, state.import, state.importCreateNew
    local importProfileName, importNameW = state.importProfileName, state.importNameW
    local ProfileButton, PlaceActionRow = state.ProfileButton, state.PlaceActionRow
    local ImportIntoCurrent, ImportIntoNewProfile = BuildImportHandlers(state)
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
        if M.ShowStatusFeedback then M.ShowStatusFeedback(M.profileImportCreateNew == true and "New-profile import on" or "New-profile import off", "info",
            1.2) end
        if M.RequestRefresh then M.RequestRefresh(ctx, "profiles-import-mode") elseif M.Refresh then M.Refresh(ctx) end
    end)
    BuildEditModeToggle(state)
    local wago = ProfileButton(actionsCard, "Browse Wago Profiles", function()
        MSUF.Require("MSUF_ShowCopyLink", FILE)("Wago MSUF Profiles", WAGO_PROFILES_URL)
    end, nil, "profiles.browse_wago", false, nil, nil, nil, ioButtonW)
    MoveWidget(exportKind, stringCard, 20, -76, exportKindW)
    local blobW = max(220, stringCardW - 40)
    MoveWidget(blob, stringCard, 20, -142, blobW)
    WrapMultilineProfileInput(blob, stringCard, 20, -166, blobW, ioWide and 220 or 162)
    PlaceActionRow(actionsCard, 20, export, import, -82)
    MoveWidget(wago, actionsCard, 20, -126, ioButtonW)
    MoveWidget(importProfileName, actionsCard, 20, -230, importNameW)
    StyleProfileInput(importProfileName, importNameW, 28, false)
    local importModeHelp = AP.Row(nil, actionsCard, { "text", "advancedprofiles.importModeHelp.30", nil,
        { "", 20, -336, max(220, actionsCardW - 40), T.colors.muted } })
    if importModeHelp and importModeHelp.SetWordWrap then importModeHelp:SetWordWrap(true) end
    TrackImportMode(state, importModeHelp)
end
function ProfilesPage.UnitSelection(state)
    local ctx, b = state.ctx, state.b
    local section = b:CollapsibleSection("profiles_unit_selection", "Selected unitframes", 246, false)
    M.ControlSchema.Section(section, "profiles")
    state.unitSelectionSection = section
    AP.Row(nil, section, { "text", "advancedprofiles.text.31", nil,
        { "Choose frames for a Selected unitframes export. Imports automatically use the frames included in the string.",
        20, -44, max(220, state.contentW - 40), T.colors.muted } })
    M.profileExportUnits = M.profileExportUnits or { player = true }
    local labels = VT("player", "Player", "target", "Target", "targettarget", "Target of Target",
        "pet", "Pet", "pettarget", "Pet Target", "focus", "Focus", "focustarget", "Focus Target", "boss", "Boss Frames", "arena", "Arena Frames")
    local index = 0
    for i = 1, #labels do
        local unit, label = labels[i].value, labels[i].text
        if not MSUF.Client.SupportsUnit or MSUF.Client.SupportsUnit(unit) then
            local column = index % 2
            local row = floor(index / 2)
            local width = max(140, floor((state.contentW - 60) / 2))
            local toggle = AP.Row(nil, section, { "switch", ProfilesMeta("export.unit." .. unit).controlId, nil,
                { label, 20 + column * (width + 20), -92 - row * 28, width },
                bind = AP.NativeInput })
            RegisterControl(toggle, ProfilesMeta("export.unit." .. unit, "ephemeral"), label, "toggle")
            toggle:SetChecked(M.profileExportUnits[unit] == true)
            toggle:SetScript("OnClick", function(self)
                M.profileExportUnits[unit] = self:GetChecked() == true
                M.SetMenuStateValue("profileExportKind", "unitselection")
            end)
            index = index + 1
        end
    end
    AP.Row(nil, section, { "text", "advancedprofiles.text.33", nil,
        { "Includes each frame's own settings, auras and castbar. Shared appearance settings stay unchanged.",
        20, -214, max(220, state.contentW - 40), T.colors.muted } })
end
function ProfilesPage.Build(ctx)
    local state = ProfilesPage.Prepare(ctx)
    ProfilesPage.Hero(state)
    ProfilesPage.ManagementLayout(state)
    ProfilesPage.ManagementControls(state)
    ProfilesPage.ProfileCleanup(state)
    ProfilesPage.Specializations(state)
    if M.ProfileVariantPage then M.ProfileVariantPage.Build(state,GetSpecMeta()) end
    if M.ProfileSyncPage then M.ProfileSyncPage.Build(state) end
    ProfilesPage.ImportExport(state)
    ProfilesPage.ImportActions(state)
    ProfilesPage.UnitSelection(state)
    if M.ProfileVariantPage then M.ProfileVariantPage.Transport(state) end
    ctx:SetContentHeight(math.abs(state.b.y) + 42)
end
local StyleIsEnabled
local function BuildModules(ctx)
    local b = W.PageBuilder(ctx)
    b:Header("Modules", "Optional MSUF style and visual modules.", 64)
    local style = b:CollapsibleSection("modules_style", "Style", 96, true)
    M.ControlSchema.Section(style, "modules")
    local enable = AP.Row(nil, style, { "switch", "advancedprofiles.enable.34", nil, { "MSUF Style", 14, -38, 220 }, bind = function(enable)
        BindProfileControl(ctx, enable, "toggle", "MSUF Style",
            function()
                StyleIsEnabled = StyleIsEnabled or MSUF.Require("MSUF_StyleIsEnabled", FILE)
                local v = StyleIsEnabled()
                return v and true or false
            end,
            function(v)
                MSUF.Require("MSUF_SetStyleEnabled", FILE)(v and true or false)
                G().styleEnabled = v and true or false
                MSUF.Require("MSUF_ApplyModules", FILE)()
            end,
            ModulesMeta("style.enabled"), "modules")
    end })
    ctx:SetContentHeight(math.abs(b.y) + 42)
end
M.RegisterPage("profiles", { title = "MSUF Profiles", build = ProfilesPage.Build, version = 7 })
M.RegisterPage("modules", { title = "MSUF Modules", build = BuildModules })
