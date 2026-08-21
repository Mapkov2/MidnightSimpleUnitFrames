-- Menu2 dashboard: builds dashboard panels, summaries, and launcher actions.
-- UI construction stays here; profile/runtime mutations route through shared Menu2 or Assistant helpers.
local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local C_Timer = M.MenuTimer or _G.C_Timer
local T = M.Theme
local W = M.Widgets

-- Menu2 dashboard page.
-- Builds the home overview, recovery panels, changelog preview, and quick actions. Dashboard
-- widgets should call workflow/page helpers; profile/runtime mutation stays outside this file.
local floor = math.floor
local max = math.max
local min = math.min
local CreateFrame = _G.CreateFrame
local CreateColor = _G.CreateColor
local InvokeDashboardBoundary = M.InvokeBoundary or pcall
local function NormalizeControlPath(value)
    local path = tostring(value or "")
    path = path:gsub("([%l%d])([%u])", "%1_%2"):lower()
    path = path:gsub("[^%w]+", "."):gsub("^%.*", ""):gsub("%.*$", ""):gsub("%.+", ".")
    return path
end
local function DashboardMeta(semanticPath, classification, exact)
    local identity = table.concat({ "home", "dashboard", NormalizeControlPath(semanticPath) }, ".")
    local meta = {
        controlId = "menu2." .. identity,
        identityKey = identity,
        controlPath = identity:gsub("%.", "/"),
        pageKey = "home",
        classification = classification or "setting",
    }
    if meta.classification == "ephemeral" then meta.ephemeral = true end
    if type(exact) == "table" then
        for key, value in pairs(exact) do meta[key] = value end
    end
    return meta
end
local DASHBOARD_DIRECT_BY_ID
local function RegisterDashboardControl(widget, meta, label, kind, values)
    if not (widget and type(meta) == "table" and type(M.RegisterSearchWidget) == "function") then return widget end
    local payload = {}
    for key, value in pairs(meta) do payload[key] = value end
    payload.label = label or payload.label
    payload.kind = kind or payload.kind
    payload.values = values or payload.values
    local direct = DASHBOARD_DIRECT_BY_ID and DASHBOARD_DIRECT_BY_ID[payload.controlId]
    if direct then
        payload.settingKey = payload.settingKey or (direct.meta and direct.meta.settingKey)
        payload.actionKey = payload.actionKey or (direct.meta and direct.meta.actionKey)
        payload.actionFixedArgs = payload.actionFixedArgs or (direct.meta and direct.meta.actionFixedArgs)
        payload.actionInputArg = payload.actionInputArg or (direct.meta and direct.meta.actionInputArg)
        payload.assistantDisposition = payload.assistantDisposition or (direct.meta and direct.meta.assistantDisposition)
        payload.assistantDispositionReason = payload.assistantDispositionReason
            or (direct.meta and direct.meta.assistantDispositionReason)
        payload.confirmRequired = direct.confirmRequired == true or payload.confirmRequired == true
        if not payload.help then payload.help = direct.help end
        if not payload.blockCombat and direct.command then payload.blockCombat = direct.command.blockCombat end
        if direct.useDirectCommandWithWidget == true then
            payload.kind = direct.kind or payload.kind
            payload.command = direct.command
        end
    end
    M.RegisterSearchWidget(widget, payload)
    return widget
end

-- Dashboard disclosures deliberately avoid allocating their inner frames until
-- opened.  The Assistant must still be able to discover and execute the real
-- settings/actions, so keep a compact command-only counterpart for every
-- conditional scaling/recovery control.  RuntimeControlCatalog promotes these
-- records to the real widgets (same explicit IDs) when a disclosure is opened.
local function DirectClamp(value, minValue, maxValue)
    value = tonumber(value) or minValue
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end
local function DirectPercent(value, fallback)
    return math.floor(((tonumber(value) or fallback or 1) * 100) + 0.5)
end
local function DirectSnapPercent(value, minPercent, maxPercent, stepPercent)
    stepPercent = stepPercent or 1
    local percent = math.floor((tonumber(value) or 100) / stepPercent + 0.5) * stepPercent
    return DirectClamp(percent, minPercent, maxPercent)
end
local MENU_SCALE_REFERENCE = 0.80
local MENU_SCALE_MIN_PERCENT, MENU_SCALE_MAX_PERCENT, MENU_SCALE_STEP_PERCENT = 25, 200, 5
local MSUF_SCALE_MIN_PERCENT, MSUF_SCALE_MAX_PERCENT, MSUF_SCALE_STEP_PERCENT = 25, 200, 5
local function MenuScalePercentFromStored(value)
    local minStored = MENU_SCALE_REFERENCE * (MENU_SCALE_MIN_PERCENT / 100)
    local maxStored = MENU_SCALE_REFERENCE * (MENU_SCALE_MAX_PERCENT / 100)
    return DirectPercent(DirectClamp(tonumber(value) or MENU_SCALE_REFERENCE, minStored, maxStored) / MENU_SCALE_REFERENCE, 1)
end
local function MenuScaleStoredFromPercent(value)
    return (DirectSnapPercent(value, MENU_SCALE_MIN_PERCENT, MENU_SCALE_MAX_PERCENT, MENU_SCALE_STEP_PERCENT) / 100)
        * MENU_SCALE_REFERENCE
end
local function DirectGeneralDB()
    if type(M.GetGeneralDB) ~= "function" then return nil end
    local db = M.GetGeneralDB()
    return type(db) == "table" and db or nil
end
local function DirectGlobalState()
    local db = DirectGeneralDB()
    if not db then return nil end
    db.UIScale = type(db.UIScale) == "table" and db.UIScale or { Enabled = false, Scale = 1 }
    db.UIScale.Enabled = db.UIScale.Enabled == true
    db.UIScale.Scale = DirectClamp(db.UIScale.Scale, 0.3, 1.5)
    return db, db.UIScale
end
local function DirectCombatLocked()
    return type(M.IsConfigCombatLocked) == "function" and M.IsConfigCombatLocked() == true
end
local function DirectRequestScaleApply(reason)
    if type(M.RequestGeneralApply) == "function" then
        M.RequestGeneralApply(reason, { preview = true, applyAll = false, notify = false })
    end
end
local function DirectSetGlobalScale(enabled, value, preset)
    local db, ui = DirectGlobalState()
    if not db then return false end
    ui.Enabled = enabled == true
    ui.Scale = DirectClamp(value or ui.Scale, 0.3, 1.5)
    db.globalUiScalePreset = preset or (ui.Enabled and "custom" or "auto")
    db.globalUiScaleValue = ui.Enabled and ui.Scale or nil
    if ui.Enabled and type(_G.MSUF_SetGlobalUiScale) == "function" then
        _G.MSUF_SetGlobalUiScale(ui.Scale, true)
    elseif not ui.Enabled and type(_G.MSUF_ResetGlobalUiScale) == "function" then
        _G.MSUF_ResetGlobalUiScale(true)
    end
    DirectRequestScaleApply("MSUF2_DASH_GLOBAL_SCALE")
    return true
end
local function DirectGlobalScalePercent()
    local _, ui = DirectGlobalState()
    if not ui then return nil end
    return ui.Enabled and DirectPercent(ui.Scale, 1) or false
end
local function DirectSetGlobalScalePercent(value)
    local _, ui = DirectGlobalState()
    if not ui then return false end
    if value == false then return DirectSetGlobalScale(false, ui.Scale, "auto") end
    return DirectSetGlobalScale(true, DirectSnapPercent(value, 30, 150, 1) / 100, "custom")
end
local function DirectMSUFScalePercent()
    local db = DirectGeneralDB()
    return db and DirectPercent(DirectClamp(tonumber(db.msufUiScale) or 1, 0.25, 2.0), 1) or nil
end
local function DirectSetMSUFScalePercent(value)
    local db = DirectGeneralDB()
    if not db then return false end
    local scale = DirectSnapPercent(value, MSUF_SCALE_MIN_PERCENT, MSUF_SCALE_MAX_PERCENT, MSUF_SCALE_STEP_PERCENT) / 100
    db.msufUiScale = scale
    if type(_G.MSUF_ApplyMsufScale) == "function" then _G.MSUF_ApplyMsufScale(scale) end
    DirectRequestScaleApply("MSUF2_DASH_MSUF_SCALE")
    return true
end
local function DirectMenuScalePercent()
    local db = DirectGeneralDB()
    return db and MenuScalePercentFromStored(db.slashMenuScale) or nil
end
local function DirectSetMenuScalePercent(value)
    local db = DirectGeneralDB()
    if not db then return false end
    local scale = MenuScaleStoredFromPercent(value)
    db.slashMenuScale = scale
    if M.frame and type(M.ApplyMenuFrameScale) == "function" then
        M.ApplyMenuFrameScale(M.frame)
    elseif M.frame and type(M.frame.SetScale) == "function" then
        M.frame:SetScale((type(M.GetEffectiveMenuScale) == "function" and M.GetEffectiveMenuScale(scale)) or scale)
    end
    return true
end
local function DirectPixelScale()
    if type(_G.MSUF_GetPixelPerfectScale) == "function" then
        local value = tonumber(_G.MSUF_GetPixelPerfectScale())
        if value then return DirectClamp(value, 0.3, 1.5) end
    end
    if type(_G.GetPhysicalScreenSize) == "function" then
        local _, height = _G.GetPhysicalScreenSize()
        if tonumber(height) and height > 0 then return DirectClamp(768 / height, 0.3, 1.5) end
    end
    return 1
end
local function DirectRunSlash(message)
    local slash = _G.SlashCmdList and _G.SlashCmdList["MIDNIGHTSUF"]
    if type(slash) ~= "function" then return false end
    slash(message or "")
    return true
end
local function DirectAction(setter, combatLocked)
    local command = { kind = "button", set = setter, historyMode = "none" }
    if combatLocked then command.blockCombat = DirectCombatLocked end
    return command
end

local DASHBOARD_DIRECT_SPECS = {
    {
        path = "scaling.global_ui.percent", label = "Global UI Scale", kind = "slider", classification = "setting",
        settingKey = "general.globalUiScale",
        help = "Reads and applies the global WoW UI scale percentage directly.",
        command = { kind = "slider", min = 30, max = 150, step = 1, percentIsValue = true,
            get = DirectGlobalScalePercent, set = DirectSetGlobalScalePercent, blockCombat = DirectCombatLocked },
    },
    {
        path = "scaling.msuf_frames.percent", label = "MSUF Frame Scale", kind = "slider", classification = "setting",
        settingKey = "general.msufUiScale",
        help = "Reads and applies the MSUF unit-frame scale percentage directly.",
        command = { kind = "slider", min = MSUF_SCALE_MIN_PERCENT, max = MSUF_SCALE_MAX_PERCENT,
            step = MSUF_SCALE_STEP_PERCENT, percentIsValue = true,
            get = DirectMSUFScalePercent, set = DirectSetMSUFScalePercent, blockCombat = DirectCombatLocked },
    },
    {
        path = "scaling.menu.percent", label = "MSUF Menu Scale", kind = "slider", classification = "setting",
        settingKey = "general.slashMenuScale",
        help = "Reads and applies the MSUF configuration-menu scale percentage directly.",
        command = { kind = "slider", min = MENU_SCALE_MIN_PERCENT, max = MENU_SCALE_MAX_PERCENT,
            step = MENU_SCALE_STEP_PERCENT, percentIsValue = true,
            get = DirectMenuScalePercent, set = DirectSetMenuScalePercent, blockCombat = DirectCombatLocked },
    },
    { path = "display_recovery.reset_positions", label = "Reset Positions", classification = "action", actionKey = "reset_all_unit_positions",
        command = DirectAction(function() return DirectRunSlash("reset") end, true) },
    --- Wago and Discord are deliberately absent here: the card no longer carries those
    --- buttons, so a direct control would advertise a menu location that does not exist.
    --- Both links stay reachable through the guided setup Wago button and the support row.
    { path = "display_recovery.print_help", label = "Print Help", classification = "action", actionKey = "assistant_help",
        command = DirectAction(function() return DirectRunSlash("help") end) },
    { path = "display_recovery.factory_reset_all", label = "Factory Reset All", classification = "action", actionKey = "factory_reset_all", confirmRequired = true,
        command = DirectAction(function() return type(M.StageFactoryReset) == "function" and M.StageFactoryReset() or false end, true) },
    { path = "scaling.global_ui.preset.1080p", label = "1080p", classification = "action", actionKey = "apply_global_scale_preset",
        actionFixedArgs = { preset = "1080p" },
        command = DirectAction(function() return DirectSetGlobalScale(true, 768 / 1080, "1080p") end, true) },
    { path = "scaling.global_ui.preset.1440p", label = "1440p", classification = "action", actionKey = "apply_global_scale_preset",
        actionFixedArgs = { preset = "1440p" },
        command = DirectAction(function() return DirectSetGlobalScale(true, 768 / 1440, "1440p") end, true) },
    { path = "scaling.global_ui.preset.4k", label = "4K", classification = "action", actionKey = "apply_global_scale_preset",
        actionFixedArgs = { preset = "4k" },
        command = DirectAction(function() return DirectSetGlobalScale(true, 768 / 2160, "4k") end, true) },
    { path = "scaling.global_ui.preset.pixel", label = "Pixel", classification = "action", actionKey = "apply_global_scale_preset",
        actionFixedArgs = { preset = "pixel" },
        command = DirectAction(function() return DirectSetGlobalScale(true, DirectPixelScale(), "pixel") end, true) },
    { path = "scaling.global_ui.apply", label = "Apply Global UI Scale", classification = "action", actionKey = "dashboard.globalUiScale.apply",
        command = DirectAction(function()
            local db, ui = DirectGlobalState()
            return db and DirectSetGlobalScale(ui.Enabled, ui.Scale, db.globalUiScalePreset) or false
        end, true) },
    { path = "scaling.global_ui.revert_pending", label = "Revert Global UI Scale", classification = "action", actionKey = "dashboard.globalUiScale.revertPending",
        command = DirectAction(function() return true end) },
    { path = "scaling.global_ui.select_off", label = "Disable Global UI Scale", classification = "action", actionKey = "dashboard.globalUiScale.disable",
        command = DirectAction(function()
            local _, ui = DirectGlobalState()
            return ui and DirectSetGlobalScale(false, ui.Scale, "auto") or false
        end, true) },
    { path = "scaling.msuf_frames.apply", label = "Apply MSUF Frame Scale", classification = "action", actionKey = "dashboard.msufFrameScale.apply",
        command = DirectAction(function() return DirectSetMSUFScalePercent(DirectMSUFScalePercent()) end, true) },
    { path = "scaling.msuf_frames.revert_pending", label = "Revert MSUF Frame Scale", classification = "action", actionKey = "dashboard.msufFrameScale.revertPending",
        command = DirectAction(function() return true end) },
    { path = "scaling.menu.apply", label = "Apply MSUF Menu Scale", classification = "action", actionKey = "dashboard.menuScale.apply",
        command = DirectAction(function() return DirectSetMenuScalePercent(DirectMenuScalePercent()) end, true) },
    { path = "scaling.menu.revert_pending", label = "Revert MSUF Menu Scale", classification = "action", actionKey = "dashboard.menuScale.revertPending",
        command = DirectAction(function() return true end) },
}
for i = 1, #DASHBOARD_DIRECT_SPECS do
    local spec = DASHBOARD_DIRECT_SPECS[i]
    spec.meta = DashboardMeta(spec.path, spec.classification, {
        label = spec.label,
        kind = spec.kind or "button",
        help = spec.help,
        settingKey = spec.settingKey,
        actionKey = spec.actionKey,
        actionFixedArgs = spec.actionFixedArgs,
        actionInputArg = spec.actionInputArg,
        confirmRequired = spec.confirmRequired == true,
        historyMode = spec.command and spec.command.historyMode,
        command = spec.command,
    })
end
DASHBOARD_DIRECT_BY_ID = {}
local DASHBOARD_DIRECT_BY_ACTION = {}
for i = 1, #DASHBOARD_DIRECT_SPECS do
    local spec = DASHBOARD_DIRECT_SPECS[i]
    DASHBOARD_DIRECT_BY_ID[spec.meta.controlId] = spec
    if type(spec.actionKey) == "string" and spec.actionKey ~= "" then
        DASHBOARD_DIRECT_BY_ACTION[spec.actionKey] = spec
    end
end
function M.RunDashboardDirectAction(actionKey)
    local spec = DASHBOARD_DIRECT_BY_ACTION[tostring(actionKey or "")]
    local command = spec and spec.command
    if not (command and type(command.set) == "function") then
        return false, "That Dashboard action is not available in this menu build."
    end
    if type(command.blockCombat) == "function" then
        local ok, blocked = InvokeDashboardBoundary(command.blockCombat)
        if not ok then return false, "The Dashboard action failed safely: " .. tostring(blocked) end
        if blocked == true then return false, "That Dashboard action is unavailable during combat." end
    end
    local ok, result, detail = InvokeDashboardBoundary(command.set)
    if not ok then return false, "The Dashboard action failed safely: " .. tostring(result) end
    if result == false then return false, detail or "The Dashboard action could not be completed." end
    return true, detail or (spec and spec.label) or "Dashboard action complete."
end
local function RegisterDashboardDirectControls()
    if type(M.RegisterVirtualRuntimeControl) ~= "function" then return 0 end
    local registered = 0
    for i = 1, #DASHBOARD_DIRECT_SPECS do
        local id = M.RegisterVirtualRuntimeControl(DASHBOARD_DIRECT_SPECS[i].meta, "dashboard-direct")
        if id then registered = registered + 1 end
    end
    return registered
end
M.RegisterDashboardDirectControls = RegisterDashboardDirectControls
RegisterDashboardDirectControls()

local function GetBundledChangelog()
    -- Changelog data is bundled as static state. The dashboard renders it read-only and should
    -- tolerate older builds where no changelog table exists.
    local data = (type(MSUF) == "table" and MSUF.MSUF_Changelog) or _G.MSUF_Changelog
    if type(data) ~= "table" or type(data.entries) ~= "table" or type(data.entries[1]) ~= "table" then return nil end
    return data
end
local function ThemeColor(name, fallback)
    local color = T and T.colors and T.colors[name]
    return color or fallback
end
local function CreateDashboardAccordionTone(header, arrow)
    local headerActiveBlue = ThemeColor("coreGlow", { 0.231, 0.510, 0.965, 1.00 })
    local headerActiveDeep = ThemeColor("coreBlue", { 0.141, 0.365, 0.741, 1.00 })
    local headerBg = W.CreateAccordionRoundedRegions(header, "BACKGROUND", 0)
    local headerActiveFrom = { headerActiveBlue[1], headerActiveBlue[2], headerActiveBlue[3], 0.62 }
    local headerActiveTo = { headerActiveDeep[1], headerActiveDeep[2], headerActiveDeep[3], 0.56 }
    local headerOpenHighlight = W.CreateAccordionOpenHighlight(header, headerActiveFrom, headerActiveTo)
    local function Refresh(open, hover)
        local headerSurface = ThemeColor("coreSurface", { 0.014, 0.038, 0.072, 1.00 })
        local headerRaised = ThemeColor("coreRaised", { 0.026, 0.070, 0.110, 1.00 })
        headerActiveBlue = ThemeColor("coreGlow", { 0.231, 0.510, 0.965, 1.00 })
        headerActiveDeep = ThemeColor("coreBlue", { 0.141, 0.365, 0.741, 1.00 })
        headerActiveFrom[1], headerActiveFrom[2], headerActiveFrom[3] = headerActiveBlue[1], headerActiveBlue[2], headerActiveBlue[3]
        headerActiveTo[1], headerActiveTo[2], headerActiveTo[3] = headerActiveDeep[1], headerActiveDeep[2], headerActiveDeep[3]
        if headerOpenHighlight.SetColors then headerOpenHighlight:SetColors(headerActiveFrom, headerActiveTo) end
        headerOpenHighlight:SetShown(open)
        headerBg:SetAlpha(open and 0 or 1)
        M.CallIf(T.ApplyCollapseVisual, arrow, nil, open)
        if open then arrow:SetVertexColor(1, 1, 1, 0.98) end
        local color = hover and headerRaised or headerSurface
        headerBg:SetColorTexture(color[1], color[2], color[3], hover and 0.42 or 0.34)
    end
    return Refresh
end
--- Dashboard disclosures change card heights, so they toggle by rebuilding the
--- whole page. Keep the viewport so the clicked header stays under the cursor.
local function RebuildDashboardPage()
    M.CallIf(M.RebuildPageKeepingScroll, "home")
end
local function BuildDashboardChangelog(parent, cardWidth, opts)
    opts = opts or {}
    local data = GetBundledChangelog()
    local top = opts.top or -130
    local headerH = 44
    local contentW = max(120, cardWidth or 420)
    local scrollW = max(80, contentW - 60)
    local function RawFont(parentFrame, template, text, color, bump, role)
        local fs = parentFrame:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
        if T.StyleFontString then
            T.StyleFontString(fs, color or T.colors.muted, bump or 0, role)
        elseif color and fs.SetTextColor then
            fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
        end
        fs:SetText(tostring(text or ""))
        return fs
    end
    local header = CreateFrame("Button", nil, parent)
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, top)
    header:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, top)
    header:SetHeight(headerH)
    local headerEdge = header:CreateTexture(nil, "BORDER")
    headerEdge:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    headerEdge:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
    headerEdge:SetHeight(1)
    headerEdge:SetColorTexture(T.colors.borderSoft[1], T.colors.borderSoft[2], T.colors.borderSoft[3], 0.44)
    local arrow = header:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(10, 10)
    arrow:SetPoint("LEFT", header, "LEFT", 16, 0)
    arrow:SetTexture(T.media.collapseArrow)
    local PaintHeaderTone = CreateDashboardAccordionTone(header, arrow)
    PaintHeaderTone(false, false)
    local title = T.Font(header, "GameFontNormal", M.Tr(opts.title or "Changelog"), T.colors.text)
    title:SetPoint("LEFT", arrow, "RIGHT", 8, 0)
    title:SetPoint("RIGHT", header, "RIGHT", -94, 0)
    title:SetJustifyH("LEFT")
    local hint = T.Font(header, "GameFontDisableSmall", "", T.colors.muted, "caption")
    hint:SetPoint("RIGHT", header, "RIGHT", -16, 0)
    hint:SetJustifyH("RIGHT")
    if not data then
        header:EnableMouse(false)
        hint:SetText("")
        RawFont(parent, "GameFontHighlightSmall", M.Tr("No release notes bundled with this build."), T.colors.muted, 0, "body")
            :SetPoint("TOPLEFT", parent, "TOPLEFT", 16, top - headerH - 8)
        if arrow.SetVertexColor then arrow:SetVertexColor(T.colors.dim[1], T.colors.dim[2], T.colors.dim[3], 0.55) end
        return
    end
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, top - headerH - 12)
    scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -36, opts.bottom or 72)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(scrollW, 1)
    scroll:SetScrollChild(child)
    local y = 0
    -- Release notes are long-form prose, so they run on the shared type roles (body/card/
    -- section) with real line spacing instead of the smallest Blizzard template. Roles keep
    -- the sizes identical at every UI and menu scale.
    local bodyColor = { T.colors.text[1], T.colors.text[2], T.colors.text[3], 0.94 }
    local function AddText(text, fontObject, color, indent, gap, translate, role)
        local rawText = tostring(text or "")
        if translate and type(M.Tr) == "function" then rawText = M.Tr(rawText) end
        local fs = RawFont(child, fontObject or "GameFontHighlightSmall", rawText, color or T.colors.muted, 0, role or "body")
        indent = indent or 0
        fs:SetPoint("TOPLEFT", child, "TOPLEFT", indent, y)
        fs:SetWidth(max(40, scrollW - indent - 4))
        fs:SetJustifyH("LEFT")
        if fs.SetWordWrap then fs:SetWordWrap(true) end
        if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(true) end
        if fs.SetSpacing then fs:SetSpacing(3) end
        fs:SetText(rawText)
        -- GetStringHeight is the wrapped height; keep GetHeight in the mix so the added line
        -- spacing can never be measured away and let a long bullet collide with the next one.
        local h = max((fs.GetStringHeight and fs:GetStringHeight()) or 0, (fs.GetHeight and fs:GetHeight()) or 0)
        if h < 12 then h = 14 end
        y = y - h - (gap or 4)
        return fs
    end
    local function AddBullet(value, dotColor, textColor, isHighlight)
        local text, link
        if type(value) == "table" then
            text = tostring(value.text or "")
            link = type(value.link) == "table" and value.link or nil
        else
            text = tostring(value or "")
        end
        dotColor = dotColor or T.colors.accent
        textColor = textColor or bodyColor
        local dot = child:CreateTexture(nil, "ARTWORK")
        dot:SetSize(5, 5)
        dot:SetPoint("TOPLEFT", child, "TOPLEFT", 9, y - 6)
        dot:SetColorTexture(dotColor[1], dotColor[2], dotColor[3], 0.95)
        if isHighlight and link then
            local button = CreateFrame("Button", nil, child)
            button:SetPoint("TOPLEFT", child, "TOPLEFT", 22, y)
            local linkWidth = max(40, scrollW - 32)
            button:SetWidth(linkWidth)
            local fs = RawFont(button, "GameFontHighlightSmall", M.Tr(text), T.colors.accent2 or T.colors.warning, 0, "body")
            fs:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
            fs:SetWidth(linkWidth)
            fs:SetJustifyH("LEFT")
            if fs.SetWordWrap then fs:SetWordWrap(true) end
            if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(true) end
            if fs.SetSpacing then fs:SetSpacing(3) end
            local h = max((fs.GetStringHeight and fs:GetStringHeight()) or 0, (fs.GetHeight and fs:GetHeight()) or 0, 14)
            button:SetHeight(h)
            local PaintFeatureLink = type(T.StyleFeatureLink) == "function" and T.StyleFeatureLink(button, fs) or nil
            button:SetScript("OnClick", function()
                if type(M.OpenChangelogMenuLink) == "function" then M.OpenChangelogMenuLink(link) end
            end)
            button:SetScript("OnEnter", function()
                if PaintFeatureLink then PaintFeatureLink(true) end
            end)
            button:SetScript("OnLeave", function()
                if PaintFeatureLink then PaintFeatureLink(false) end
            end)
            y = y - h - 9
            return button
        end
        return AddText(text, "GameFontHighlightSmall", textColor, 22, 9, true, "body")
    end
    local function AddRule()
        local rule = child:CreateTexture(nil, "ARTWORK")
        rule:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
        rule:SetPoint("TOPRIGHT", child, "TOPRIGHT", -4, y)
        rule:SetHeight(1)
        rule:SetColorTexture(T.colors.borderSoft[1], T.colors.borderSoft[2], T.colors.borderSoft[3], 0.55)
        y = y - 1
    end
    local entries = data.entries
    local maxEntries = min(#entries, 4)
    for entryIndex = 1, maxEntries do
        local entry = entries[entryIndex]
        if type(entry) == "table" then
            local version = tostring(entry.version or "")
            local date = tostring(entry.date or "")
            local heading = (date ~= "" and (version .. " - " .. date)) or version
            if entryIndex > 1 then
                y = y - 10
                AddRule()
                y = y - 12
            end
            AddText(heading, "GameFontNormal", T.colors.accent, 0, 10, false, "section")
            local sections = entry.sections
            if type(sections) == "table" then
                for sectionIndex = 1, #sections do
                    local section = sections[sectionIndex]
                    if type(section) == "table" and type(section.bullets) == "table" and #section.bullets > 0 then
                        if sectionIndex > 1 then y = y - 8 end
                        local sectionTitle = tostring(section.title or "")
                        local isHighlights = sectionTitle == "Highlights"
                        AddText(sectionTitle, "GameFontNormalSmall", isHighlights and T.colors.accent or T.colors.accent2, 0, 7, true, "card")
                        for bulletIndex = 1, #section.bullets do
                            AddBullet(
                                section.bullets[bulletIndex],
                                isHighlights and T.colors.accent2 or nil,
                                isHighlights and T.colors.text or nil,
                                isHighlights
                            )
                        end
                    end
                end
            end
        end
    end
    child:SetHeight(max(1, math.abs(y) + 8))
    M.CallIf(T.StyleScrollFrame, scroll, parent)
    local open = M.dashboardChangelogOpen == true
    RegisterDashboardControl(header, DashboardMeta("changelog.disclosure", "ephemeral", {
        help = "Shows or hides the bundled MSUF release notes.",
    }), opts.title or "Changelog", "button")
    local function PaintHeader(isOpen)
        PaintHeaderTone(isOpen, false)
        if headerEdge.SetColorTexture then headerEdge:SetColorTexture(T.colors.borderSoft[1], T.colors.borderSoft[2], T.colors.borderSoft[3], isOpen and 0.58 or 0.34) end
        hint:SetText(isOpen and M.Tr("Hide") or M.Tr("View"))
    end
    local function RefreshOpenState()
        M.SetMenuStateValue("dashboardChangelogOpen", open)
        scroll:SetShown(open)
        PaintHeader(open)
        if open then
            if scroll._msuf2RefreshScrollBar then scroll:_msuf2RefreshScrollBar() end
        elseif scroll._msuf2ScrollBar then
            scroll._msuf2ScrollBar:Hide()
        end
    end
    header:SetScript("OnClick", function()
        open = not open
        RefreshOpenState()
        if type(opts.onToggle) == "function" then opts.onToggle(open) end
    end)
    header:SetScript("OnEnter", function()
        PaintHeaderTone(open, true)
    end)
    header:SetScript("OnLeave", function()
        PaintHeader(open)
    end)
    RefreshOpenState()
end
local function StartGuidedSetupFromDashboard(restart)
    if type(M.StartGuidedTour) ~= "function" then return false end
    return M.StartGuidedTour({ source = "dashboard", restart = restart == true, mode = "quick" })
end
-- Setup stays available after onboarding, but a stray click on the completed
-- card should not drop the user back into the walkthrough. Only the restart
-- path asks; resuming an active tour and the very first run stay one click.
local function ConfirmGuidedSetupRestart()
    if not (_G.StaticPopupDialogs and _G.StaticPopup_Show and type(M.InstallStaticPopup) == "function") then
        return StartGuidedSetupFromDashboard(true)
    end
    M.InstallStaticPopup("MSUF2_GUIDED_SETUP_RESTART_CONFIRM", {
        text = "%s",
        button1 = _G.YES or "Yes",
        button2 = _G.NO or "No",
        OnAccept = function() StartGuidedSetupFromDashboard(true) end,
    })
    _G.StaticPopup_Show("MSUF2_GUIDED_SETUP_RESTART_CONFIRM",
        M.Tr("Run the guided setup again? The walkthrough starts over at the first step."))
    return true
end
local function BuildDashboardUX(ctx)
    if type(M.BuildUpgradeHighlightDashboardScene) == "function" and M.BuildUpgradeHighlightDashboardScene(ctx) == true then
        return
    end
    if type(M.BuildFirstLoadDashboardScene) == "function" and M.BuildFirstLoadDashboardScene(ctx) == true then
        return
    end
    -- BuildPageEntry clears the page catalog immediately before invoking us.
    -- Restore the frame-free contracts first; conditional real widgets below
    -- then promote only the controls whose disclosures are currently open.
    RegisterDashboardDirectControls()
    local root = ctx.wrapper
    local width = ctx.width or 760
    local x0, y0 = 12, -12
    local layoutW = max(1, width - x0)
    local mainW = layoutW
    local function Card(parent, title, x, y, w, h, bg, border)
        bg = bg or T.colors.panel2
        border = border or T.colors.cardBorder or T.colors.borderSoft
        local card = T.Panel(parent or root, nil, bg, border)
        if T.ApplyMaterial then
            T.ApplyMaterial(card, { bg = bg, border = border, glass = "card", gradient = "card" })
        elseif T.ApplySurface then
            T.ApplySurface(card, "card")
        end
        card:SetPoint("TOPLEFT", parent or root, "TOPLEFT", x, y)
        card:SetSize(w, h)
        if title and title ~= "" then
            local label = T.Font(card, "GameFontNormal", M.Tr(title), T.colors.text)
            label:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -16)
            card._msuf2Title = label
        end
        return card
    end
    local function SetDashboardGradient(texture, orientation, from, to)
        if not texture then return end
        from = from or { 1, 1, 1, 0 }
        to = to or { 1, 1, 1, 1 }
        local fromA = from[4] or 1
        local toA = to[4] or 1
        local media = T and T.media
        local horizontal = (orientation or "HORIZONTAL") == "HORIZONTAL"
        local path
        local color
        if horizontal then
            path = (toA >= fromA) and (media and media.gradHRev) or (media and media.gradH)
            color = (toA >= fromA) and to or from
        else
            path = (fromA >= toA) and (media and media.gradV) or (media and media.gradVRev)
            color = (fromA >= toA) and from or to
        end
        if path and path ~= "" then
            texture:SetTexture(path)
            texture:SetTexCoord(0, 1, 0, 1)
            if texture.SetVertexColor then texture:SetVertexColor(color[1], color[2], color[3], color[4] or 1) end
        elseif texture.SetGradientAlpha then
            texture:SetTexture("Interface\\Buttons\\WHITE8X8")
            texture:SetGradientAlpha(orientation or "HORIZONTAL", from[1], from[2], from[3], fromA, to[1], to[2], to[3], toA)
        elseif texture.SetGradient and CreateColor then
            texture:SetTexture("Interface\\Buttons\\WHITE8X8")
            texture:SetGradient(orientation or "HORIZONTAL", CreateColor(from[1], from[2], from[3], fromA), CreateColor(to[1], to[2], to[3], toA))
        elseif texture.SetColorTexture then
            texture:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
        end
    end
    local function ApplyDashboardHeroGradient(card, w, h)
        if not (card and card.CreateTexture) or card._msuf2DashboardHeroGradient then return end
        card._msuf2DashboardHeroGradient = true
        local c = T.colors
        local wash = card:CreateTexture(nil, "BACKGROUND", nil, 1)
        wash:SetPoint("TOPLEFT", card, "TOPLEFT", 2, -2)
        wash:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -2, 2)
        SetDashboardGradient(wash, "HORIZONTAL",
            { c.coreShadow[1], c.coreShadow[2], c.coreShadow[3], 0.00 },
            { c.coreRaised[1], c.coreRaised[2], c.coreRaised[3], 0.12 })
        local top = card:CreateTexture(nil, "BACKGROUND", nil, 2)
        top:SetPoint("TOPLEFT", card, "TOPLEFT", 2, -2)
        top:SetPoint("TOPRIGHT", card, "TOPRIGHT", -2, -2)
        top:SetHeight(max(54, min(96, floor((h or 190) * 0.42))))
        SetDashboardGradient(top, "VERTICAL",
            { c.coreBlue[1], c.coreBlue[2], c.coreBlue[3], 0.055 },
            { c.coreShadow[1], c.coreShadow[2], c.coreShadow[3], 0.00 })
        local focus = card:CreateTexture(nil, "BACKGROUND", nil, 3)
        focus:SetPoint("TOPLEFT", card, "TOPLEFT", 2, -2)
        focus:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -2, 2)
        SetDashboardGradient(focus, "HORIZONTAL",
            { c.coreBlue[1], c.coreBlue[2], c.coreBlue[3], 0.00 },
            { c.coreBlue[1], c.coreBlue[2], c.coreBlue[3], 0.035 })
    end
    local function Button(parent, text, x, y, w, h, onClick, skin, semanticPath, classification, exact)
        local btn = T.Button(parent, M.Tr(text or ""), w, h or 24)
        btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        T.CenterButtonLabel(btn)
        if skin == "primary" and T.SkinPrimaryButton then T.SkinPrimaryButton(btn) end
        if skin == "success" and T.SkinSuccessButton then T.SkinSuccessButton(btn) end
        if skin == "danger" and T.SkinDangerButton then T.SkinDangerButton(btn) end
        if onClick then btn:SetScript("OnClick", onClick) end
        RegisterDashboardControl(btn, DashboardMeta(semanticPath, classification or "action", exact), text, "button")
        return btn
    end
    local function Kicker(parent, text, x, y, color)
        local fs = T.Font(parent, "GameFontDisableSmall", string.upper(M.Tr(text or "")), color or T.colors.accent)
        fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 16, y or -16)
        return fs
    end
    local function Pill(parent, text, x, y, w, color)
        local pill = T.Panel(parent, nil, T.colors.pillBaseSolid, T.colors.pillEdge)
        pill:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        pill:SetSize(w or 82, 20)
        local label = T.Font(pill, "GameFontDisableSmall", M.Tr(text or ""), color or T.colors.muted)
        label:SetPoint("CENTER", pill, "CENTER", 0, 0)
        label:SetJustifyH("CENTER")
        pill._msuf2Label = label
        return pill
    end
    local function AddTooltip(frame, title, text)
        return M.AddTooltip and M.AddTooltip(frame, title, text, {
            hook = true,
            titleAsLine = true,
            bodyColor = { 0.85, 0.85, 0.85 },
        }) or frame
    end
    local function IsDashboardEditModeActive()
        return M.IsMSUFEditModeActive(true)
    end
    local function IsDashboardEditModeCombatLocked()
        return M.IsEditModeCombatLocked(true)
    end
    local function RefreshDashboardEditModeButtonSafe() M.CallIf(M.RefreshDashboardEditModeButton) end
    local function RefreshMenuFramePrioritySafe() M.CallIf(M.RefreshMenuFramePriority) end
    local function RefreshDashboardFrameStatus() local f = M.frame; if f and f.RefreshStatus then f:RefreshStatus() end end
    local function ToggleEditMode()
        local active = IsDashboardEditModeActive()
        if (not active) and IsDashboardEditModeCombatLocked() then
            M.CallIf(M.BlockCombatAction)
            RefreshDashboardEditModeButtonSafe()
            RefreshDashboardFrameStatus()
            return
        end
        if type(_G.MSUF_SetMSUFEditModeDirect) == "function" then _G.MSUF_SetMSUFEditModeDirect(not active) end
        RefreshMenuFramePrioritySafe()
        C_Timer.After(0, RefreshMenuFramePrioritySafe)
        RefreshDashboardEditModeButtonSafe()
        RefreshDashboardFrameStatus()
    end
    M.ToggleDashboardEditMode = ToggleEditMode
    local function StartNewAssistantTask()
        local A = MSUF and MSUF.Assistant
        if not A then return end
        if type(A.StartNewTaskWithRuntime) == "function" then
            return A.StartNewTaskWithRuntime("new-task")
        end
        if type(A.StartNewTask) ~= "function" and type(A.EnsureRuntimeLoaded) == "function" then
            local loaded = A.EnsureRuntimeLoaded("new-task")
            if not loaded then return false end
            A = MSUF and MSUF.Assistant or A
        end
        if type(A.ShowRuntimeDashboardCard) == "function" then A.ShowRuntimeDashboardCard() end
        if type(A.StartNewTask) == "function" then return A.StartNewTask() end
        if A.Workflow and type(A.Workflow.CancelActiveWorkflow) == "function" then A.Workflow.CancelActiveWorkflow() end
        if type(A.CloseLargeTextPanel) == "function" then
            A.CloseLargeTextPanel()
        else
            A.largeTextPanel = nil
        end
        if type(A.ClearHistory) == "function" then A.ClearHistory() end
        local ui = A.dashboardUI
        if ui and ui.input then
            ui.input:SetText("")
            if ui.input.SetFocus then ui.input:SetFocus() end
            if ui.input._msufAssistantPlaceholder and ui.input._msufAssistantPlaceholder.SetShown then ui.input._msufAssistantPlaceholder:SetShown(true) end
        end
        if type(A.RequestRefreshUI) == "function" then
            A.RequestRefreshUI("assistant.new_task")
        elseif type(A.RefreshUI) == "function" then
            A.RefreshUI()
        end
    end
    M.StartNewAssistantTask = StartNewAssistantTask
    local iconDir = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Masks\\"
    local function CopyWagoLink()
        if type(_G.MSUF_ShowCopyLink) == "function" then _G.MSUF_ShowCopyLink("Wago MSUF Profiles", "https://wago.io/search/imports/wow/msuf") end
    end
    local function Percent(value, fallback)
        return math.floor(((tonumber(value) or fallback or 1) * 100) + 0.5)
    end
    local function Clamp(v, minV, maxV)
        v = tonumber(v) or minV
        if v < minV then return minV end
        if v > maxV then return maxV end
        return v
    end
    local function SnapPct(value, minPct, maxPct, stepPct)
        stepPct = stepPct or 1
        local pct = math.floor((tonumber(value) or 100) / stepPct + 0.5) * stepPct
        return Clamp(pct, minPct or 25, maxPct or 150)
    end
    local function SetSliderValueSafe(slider, value)
        if not (slider and slider.SetValue) then return end
        slider._msuf2Refreshing = true
        slider:SetValue(value)
        if slider.editBox and slider._msuf2FormatValue then slider.editBox:SetText(slider._msuf2FormatValue(value)) end
        if slider._msuf2UpdateFill then slider:_msuf2UpdateFill() end
        slider._msuf2Refreshing = nil
    end
    local function HideSliderValueBox(slider)
        if slider and slider.editBox then slider.editBox:Hide() end
        if slider and slider._msuf2StepButtons then
            for i = 1, #slider._msuf2StepButtons do
                slider._msuf2StepButtons[i]:Hide()
            end
        end
        if slider and slider._msuf2Title then T.StyleFontString(slider._msuf2Title, T.colors.text, 3) end
    end
    local function EnablePercentWheel(slider, minPct, maxPct, stepPct)
        if not slider then return end
        slider:EnableMouseWheel(true)
        slider:SetScript("OnMouseWheel", function(self, delta)
            if not delta then return end
            local value = tonumber((self.GetValue and self:GetValue()) or 100) or 100
            value = value + ((delta > 0) and stepPct or -stepPct)
            self:SetValue(SnapPct(value, minPct, maxPct, stepPct))
        end)
    end
    local function PixelScale()
        if type(_G.MSUF_GetPixelPerfectScale) == "function" then
            local v = _G.MSUF_GetPixelPerfectScale()
            if tonumber(v) then return Clamp(v, 0.3, 1.5) end
        end
        if type(GetPhysicalScreenSize) == "function" then
            local _, h = GetPhysicalScreenSize()
            h = tonumber(h)
            if h and h > 0 then return Clamp(768 / h, 0.3, 1.5) end
        end
        return 1
    end
    local function GlobalState()
        local g = M.GetGeneralDB()
        g.UIScale = (type(g.UIScale) == "table") and g.UIScale or { Enabled = false, Scale = 1 }
        local ui = g.UIScale
        ui.Enabled = ui.Enabled == true
        ui.Scale = Clamp(ui.Scale, 0.3, 1.5)
        return g, ui
    end
    local function RunMSUFSlashCommand(message)
        local slash = _G.SlashCmdList and _G.SlashCmdList["MIDNIGHTSUF"]
        if type(slash) ~= "function" then return false end
        slash(message or "")
        return true
    end
    M.dashboardEditModeButton = nil
    M.TrackRefresh(ctx, RefreshDashboardEditModeButtonSafe)
    local mainTop = y0

    -- Setup remains available after onboarding. Quick Setup is the default;
    -- the first route screen still offers the complete learning tour.
    -- launcher deliberately compact; the persistent progress bar itself lives
    -- in the window chrome while the tour is active.
    local tour = MSUF and MSUF.GuidedTour6
    local tourState = type(tour) == "table" and type(tour.GetState) == "function" and tour:GetState() or nil
    local tourActive = type(tourState) == "table" and tourState.status == "active"
    local tourCompleted = type(tourState) == "table" and tourState.status == "completed"
    local firstLoad = MSUF and MSUF.FirstLoad6
    local highlightGuidedSetup = type(firstLoad) == "table"
        and type(firstLoad.ShouldHighlightGuidedSetup) == "function"
        and firstLoad:ShouldHighlightGuidedSetup()
    local launcherNarrow = mainW < 520
    -- The Wago button rides along with the setup action: narrow stacks it below,
    -- wide seats it left of the action, so both reserve room in the same card.
    local launcherH = launcherNarrow and 162 or 78
    local launcher = Card(root, "", x0, mainTop, mainW, launcherH, T.colors.panel2, T.colors.borderSoft)
    Kicker(launcher, tourActive and "GUIDED SETUP IN PROGRESS" or (tourCompleted and "GUIDED SETUP COMPLETE" or "GUIDED SETUP"), 16, -14)
    local launcherTitle = tourActive and "Continue your MSUF setup"
        or (tourCompleted and "Review or run setup again" or "Get the essentials right in a few minutes")
    local title = T.Font(launcher, "GameFontNormal", M.Tr(launcherTitle), T.colors.text)
    title:SetPoint("TOPLEFT", launcher, "TOPLEFT", 16, -36)
    title:SetWidth(max(120, mainW - (launcherNarrow and 32 or 388)))
    title:SetJustifyH("LEFT")
    if tourActive then
        local current, total
        if type(M.GetGuidedTourStageProgress) == "function" then current, total = M.GetGuidedTourStageProgress() end
        total = max(1, tonumber(total) or tonumber(M.guidedTourStageCount) or 1)
        current = min(total, max(1, tonumber(current) or 1))
        local step = T.Font(launcher, "GameFontDisableSmall", M.Format("Step %d of %d", current, total), T.colors.muted)
        step:SetPoint("TOPLEFT", launcher, "TOPLEFT", 16, launcherNarrow and -72 or -56)
    end
    local actionText = tourActive and "Resume setup" or (tourCompleted and "Run setup again" or "Start Quick Setup")
    local actionX = launcherNarrow and 16 or (mainW - 196)
    local actionY = launcherNarrow and -92 or -27
    local actionW = launcherNarrow and min(196, mainW - 32) or 180
    local action = Button(launcher, actionText, actionX, actionY, actionW, 30, function()
        if M.BlockCombatAction and M.BlockCombatAction() then return end
        if tourActive and type(M.ResumeGuidedTour) == "function" then
            M.ResumeGuidedTour()
        elseif tourCompleted then
            ConfirmGuidedSetupRestart()
        else
            StartGuidedSetupFromDashboard(false)
        end
    end, highlightGuidedSetup and "success" or "primary", "guided_setup.start_or_resume", "action", { actionKey = "guided_setup" })
    M.CallIf(T.AttachNavIcon, action, "home", false, true)
    local wagoW = launcherNarrow and actionW or 150
    local wago = Button(launcher, "Wago Profiles",
        launcherNarrow and actionX or (mainW - 354),
        launcherNarrow and -126 or -27,
        wagoW, 30, CopyWagoLink, nil, "guided_setup.browse_wago_profiles", "action",
        { actionKey = "copy_wago_profiles_link",
          keywords = { "Browse Wago profiles", "Wago profile imports" },
          help = "Opens a copyable link to the MSUF profile imports on Wago." })
    local wagoIcon = wago:CreateTexture(nil, "ARTWORK", nil, 3)
    wagoIcon:SetTexture(iconDir .. "Wago.png")
    wagoIcon:SetSize(22, 22)
    wagoIcon:SetPoint("LEFT", wago, "LEFT", 8, 0)
    if wago._msuf2Label then
        wago._msuf2Label:ClearAllPoints()
        wago._msuf2Label:SetPoint("LEFT", wagoIcon, "RIGHT", 6, 0)
        wago._msuf2Label:SetPoint("RIGHT", wago, "RIGHT", -10, 0)
        wago._msuf2Label:SetJustifyH("CENTER")
    end
    AddTooltip(wago, "Wago Profiles", "Browse Wago profiles")

    mainTop = mainTop - launcherH - 10
    local tinyHero = mainW < 390
    local heroH = tinyHero and 398 or (mainW < 560 and 382 or 360)
    local hero = Card(root, "", x0, mainTop, mainW, heroH, T.colors.glassHost, T.colors.cardBorder)
    ApplyDashboardHeroGradient(hero, mainW, heroH)
    M.CallIf(T.ApplyNeonEdge, hero, "ambient", { variant = "host" })
    if MSUF and MSUF.Assistant and type(MSUF.Assistant.BuildDashboardCard) == "function" then
        MSUF.Assistant.BuildDashboardCard(hero, mainW, heroH)
    else
        Kicker(hero, "MSUF", 22, -24)
        local title = T.Font(hero, "GameFontNormalLarge", M.Tr("Dashboard unavailable"), T.colors.text)
        title:SetPoint("TOPLEFT", hero, "TOPLEFT", 24, -52)
        title:SetWidth(mainW - 44)
        W.Text(hero, "The Assistant dashboard module is not available. Use the navigation pages and search to configure MSUF.", 22, -82, mainW - 44, T.colors.muted)
    end
    local featureBlockBottom = mainTop - heroH
    local function DashboardDisclosure(parent, title, open, stateKey, width, fillPills, semanticPath)
        local head = CreateFrame("Button", nil, parent)
        head:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
        head:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
        head:SetHeight(44)
        local arrow = head:CreateTexture(nil, "OVERLAY")
        arrow:SetTexture(T.media.collapseArrow)
        arrow:SetSize(10, 10)
        arrow:SetPoint("LEFT", head, "LEFT", 16, 0)
        local PaintHeaderTone = CreateDashboardAccordionTone(head, arrow)
        PaintHeaderTone(open, false)
        local label = T.Font(head, "GameFontNormal", M.Tr(title), T.colors.text)
        label:SetPoint("LEFT", arrow, "RIGHT", 8, 0)
        if type(fillPills) == "function" then fillPills(head, width) end
        head:SetScript("OnClick", function()
            M.SetMenuStateValue(stateKey, not open)
            RebuildDashboardPage()
        end)
        head:SetScript("OnEnter", function()
            PaintHeaderTone(open, true)
        end)
        head:SetScript("OnLeave", function()
            PaintHeaderTone(open, false)
        end)
        RegisterDashboardControl(head, DashboardMeta(semanticPath, "ephemeral", {
            help = M.Format("Shows or hides the %s dashboard section.", tostring(title)),
        }), title, "button")
        return head
    end
    local recoveryW = layoutW
    local recoveryOpen = M.dashboardRecoveryOpen == true
    --- Three buttons fit one row down to ~392px (Reset + Print Help end at 232, the
    --- right-aligned Factory Reset starts at width-152); below that the reset drops
    --- to a second row with its warning text beside it.
    local recoveryWrap = recoveryW < 420
    local recoveryH = recoveryOpen and (recoveryWrap and 154 or 122) or 42
    local changelogOpen = M.dashboardChangelogOpen == true
    local changelogH = changelogOpen and 420 or 42
    local scalingOpen = M.dashboardScalingOpen == true
    local scalingColumns = (recoveryW >= 960) and 3 or ((recoveryW >= 680) and 2 or 1)
    local scalingH = scalingOpen and ((scalingColumns == 3) and 250 or ((scalingColumns == 2) and 382 or 548)) or 42
    --- Card order top to bottom: Changelog, Scaling, Display & recovery, Support. The
    --- cards are still built in their old order below, so the whole top chain has to be
    --- resolved here where every height is known.
    local changelogTop = featureBlockBottom - 16
    local scalingTop = changelogTop - changelogH - 10
    local recoveryTop = scalingTop - scalingH - 10
    local supportTop = recoveryTop - recoveryH - 10
    local recovery = Card(root, "", x0, recoveryTop, recoveryW, recoveryH, T.colors.panel2, T.colors.borderSoft)
    local g = M.GetGeneralDB and M.GetGeneralDB() or {}
    DashboardDisclosure(recovery, "Display & recovery", recoveryOpen, "dashboardRecoveryOpen", recoveryW, function(head)
        if recoveryW >= 520 then Pill(head, "Factory reset hidden", recoveryW - 124, -11, 110, T.colors.accent2) end
    end, "display_recovery.disclosure")
    if recoveryOpen then
        W.Text(recovery, "Fix positions, print help, or reset MSUF.", 16, -60, recoveryW - 32, T.colors.muted)
        local resetPositions = Button(recovery, "Reset Positions", 16, -94, 118, 22, function()
            if not RunMSUFSlashCommand("reset") and M.ShowStatusFeedback then M.ShowStatusFeedback(M.Tr("Reset unavailable"), "danger", 1.4) end
        end, "primary", "display_recovery.reset_positions")
        AddTooltip(resetPositions, "Reset Positions", "Runs /msuf reset for frame positions and visibility.")
        local factoryY = recoveryWrap and -126 or -94
        --- "all" includes the diagnostic commands: someone who opened this card
        --- is usually troubleshooting and wants the complete list, not a subset.
        local printHelp = Button(recovery, "Print Help", 146, -94, 86, 22, function()
            if not RunMSUFSlashCommand("help all") and M.ShowStatusFeedback then
                M.ShowStatusFeedback(M.Tr("Help unavailable"), "danger", 1.4)
            end
        end, nil, "display_recovery.print_help")
        AddTooltip(printHelp, "Print Help", "Lists every MSUF slash command in chat, diagnostics included.")
        Button(recovery, "Factory Reset All", recoveryWrap and 16 or (recoveryW - 152), factoryY, 136, 22, function()
            M.CallIf(M.StageFactoryReset)
        end, "danger", "display_recovery.factory_reset_all", "action", { confirmRequired = true })
        if recoveryWrap then
            W.Text(recovery, "Factory reset affects every MSUF setting.", 160, -128, recoveryW - 176, T.colors.muted)
        end
    end
    local scaling = Card(root, "", x0, scalingTop, recoveryW, scalingH, T.colors.panel2, T.colors.borderSoft)
    DashboardDisclosure(scaling, "Scaling", scalingOpen, "dashboardScalingOpen", recoveryW, function(scaleHead)
        if recoveryW < 520 then return end
        local _, ui = GlobalState()
        local uiValue = ui.Enabled and M.Format("%d%%", Percent(ui.Scale, 1)) or M.Tr("Off")
        Pill(scaleHead, M.Format("UI %s", uiValue), recoveryW - 250, -11, 64)
        Pill(scaleHead, M.Format("Menu %d%%", MenuScalePercentFromStored(g.slashMenuScale)), recoveryW - 180, -11, 76)
        Pill(scaleHead, M.Format("Frames %d%%", Percent(g.msufUiScale, 1)), recoveryW - 98, -11, 84)
    end, "scaling.disclosure")
    if scalingOpen then
        W.Text(scaling, "Use sliders for exact scale changes. Apply commits the selected value; Revert returns to the active value.", 16, -60, recoveryW - 32, T.colors.muted)
        local pendingGlobalEnabled, pendingGlobalScale, pendingMsufScale, pendingMenuScale
        local colGap = 24
        local colW = (scalingColumns == 3) and math.floor((recoveryW - 32 - (colGap * 2)) / 3)
            or ((scalingColumns == 2) and math.floor((recoveryW - 32 - colGap) / 2) or (recoveryW - 32))
        local globalX, globalTop = 16, -94
        local msufX = (scalingColumns == 3) and (16 + colW + colGap) or ((scalingColumns == 2) and (16 + colW + colGap) or 16)
        local msufTop = (scalingColumns == 3 or scalingColumns == 2) and -94 or -242
        local menuX = (scalingColumns == 3) and (16 + ((colW + colGap) * 2)) or 16
        local menuTop = (scalingColumns == 3) and -94 or ((scalingColumns == 2) and -242 or -390)
        local function AppliedGlobalScale()
            local _, ui = GlobalState()
            return ui.Enabled, Clamp(ui.Scale, 0.3, 1.5)
        end
        local function SelectedGlobalScale()
            local enabled, appliedScale = AppliedGlobalScale()
            local selectedEnabled = pendingGlobalEnabled
            if selectedEnabled == nil then selectedEnabled = enabled end
            local selectedScale = Clamp(pendingGlobalScale or appliedScale, 0.3, 1.5)
            return selectedEnabled, selectedScale, enabled, appliedScale
        end
        local function AppliedMsufScale()
            local dbScale = M.GetGeneralDB()
            return Clamp(tonumber(dbScale.msufUiScale) or 1, 0.25, 2.0)
        end
        local function PendingMsufScale()
            return Clamp(pendingMsufScale or AppliedMsufScale(), 0.25, 2.0)
        end
        local function AppliedMenuScale()
            local dbScale = M.GetGeneralDB()
            return MenuScalePercentFromStored(dbScale.slashMenuScale) / 100
        end
        local function PendingMenuScale()
            return Clamp(pendingMenuScale or AppliedMenuScale(), MENU_SCALE_MIN_PERCENT / 100, MENU_SCALE_MAX_PERCENT / 100)
        end
        local function BuildScaleSlider(parent, label, x, top, width, minPct, maxPct, stepPct, semanticPath, command)
            local slider = W.Slider(parent, label, minPct, maxPct, stepPct, width)
            HideSliderValueBox(slider)
            slider:ClearAllPoints()
            slider:SetPoint("TOPLEFT", parent, "TOPLEFT", x, top - 64)
            if slider._msuf2SetLayoutWidth then slider:_msuf2SetLayoutWidth(width) end
            if slider._msuf2Title then
                slider._msuf2Title:ClearAllPoints()
                slider._msuf2Title:SetPoint("TOPLEFT", parent, "TOPLEFT", x, top)
                slider._msuf2Title:SetWidth(width)
            end
            EnablePercentWheel(slider, minPct, maxPct, stepPct)
            RegisterDashboardControl(slider, DashboardMeta(semanticPath, command and "setting" or "ephemeral", {
                help = command and "Reads and applies this scale percentage directly."
                    or "Selects a pending scale percentage; use Apply to commit it.",
                command = command,
            }), label, "slider")
            return slider
        end
        local function BuildSimpleScaleColumn(opts)
            W.Text(scaling, opts.help, opts.x, opts.top - 20, colW, T.colors.muted)
            local status = W.Text(scaling, "", opts.x, opts.top - 40, colW, T.colors.muted)
            local Refresh
            local command = {
                kind = "slider", min = opts.minPct, max = opts.maxPct, step = opts.stepPct, percentIsValue = true,
                blockCombat = DirectCombatLocked,
                get = function() return Percent(opts.applied(), 1) end,
                set = function(value)
                    local pct = SnapPct(value, opts.minPct, opts.maxPct, opts.stepPct)
                    opts.apply(pct / 100)
                    if Refresh then Refresh() end
                    return true
                end,
                refresh = function() if Refresh then Refresh() end end,
            }
            local slider = BuildScaleSlider(scaling, opts.label, opts.x, opts.top, colW, opts.minPct, opts.maxPct, opts.stepPct,
                opts.semanticPath .. ".percent", command)
            local apply, revert
            Refresh = function()
                local applied = opts.applied()
                local pending = opts.pending()
                local changed = math.abs(applied - pending) > 0.001
                status:SetText(M.Format(M.Tr("Applied: %d%%  Selected: %d%%"), Percent(applied, 1), Percent(pending, 1)))
                SetSliderValueSafe(slider, SnapPct(pending * 100, opts.minPct, opts.maxPct, opts.stepPct))
                if apply then
                    if changed then apply:Enable() else apply:Disable() end
                    if apply.SetActive then apply:SetActive(changed) end
                end
                if revert then
                    if changed then revert:Enable() else revert:Disable() end
                end
            end
            slider:HookScript("OnValueChanged", function(self, value)
                if self._msuf2Refreshing then return end
                local pct = SnapPct(value, opts.minPct, opts.maxPct, opts.stepPct)
                if pct ~= value then SetSliderValueSafe(self, pct) end
                opts.set(Clamp(pct / 100, opts.minPct / 100, opts.maxPct / 100))
                Refresh()
            end)
            apply = Button(scaling, "Apply", opts.x, opts.top - 100, 72, 20, function()
                opts.apply(opts.pending())
                Refresh()
            end, "primary", opts.semanticPath .. ".apply")
            revert = Button(scaling, "Revert", opts.x + 82, opts.top - 100, 72, 20, function()
                opts.clear()
                Refresh()
            end, nil, opts.semanticPath .. ".revert_pending", "ephemeral")
            return Refresh
        end
        W.Text(scaling, "Changes the global WoW UI scale through MSUF presets.", globalX, globalTop - 20, colW, T.colors.muted)
        local globalStatus = W.Text(scaling, "", globalX, globalTop - 40, colW, T.colors.muted)
        local RefreshGlobalScale, ApplyGlobalScale
        local globalScaleCommand = {
            kind = "slider", min = 30, max = 150, step = 1, percentIsValue = true,
            blockCombat = DirectCombatLocked,
            get = function()
                local _, _, appliedEnabled, appliedScale = SelectedGlobalScale()
                return appliedEnabled and Percent(appliedScale, 1) or false
            end,
            set = function(value)
                local _, _, _, appliedScale = SelectedGlobalScale()
                if value == false then ApplyGlobalScale(false, appliedScale, "auto")
                else ApplyGlobalScale(true, SnapPct(value, 30, 150, 1) / 100, "custom") end
                return true
            end,
            refresh = function() if RefreshGlobalScale then RefreshGlobalScale() end end,
        }
        local globalScale = BuildScaleSlider(scaling, "Global UI Scale", globalX, globalTop, colW, 30, 150, 1,
            "scaling.global_ui.percent", globalScaleCommand)
        local globalApply, globalRevert
        RefreshGlobalScale = function()
            local selectedEnabled, selectedScale, appliedEnabled, appliedScale = SelectedGlobalScale()
            local applied = appliedEnabled and (Percent(appliedScale, 1) .. "%") or M.Tr("Off")
            local selected = selectedEnabled and (Percent(selectedScale, 1) .. "%") or M.Tr("Off")
            local changed = (selectedEnabled ~= appliedEnabled) or math.abs(selectedScale - appliedScale) > 0.001
            globalStatus:SetText(M.Format(M.Tr("Applied: %s   Selected: %s"), applied, selected))
            SetSliderValueSafe(globalScale, SnapPct(selectedScale * 100, 30, 150, 1))
            if globalApply then
                if changed then globalApply:Enable() else globalApply:Disable() end
                if globalApply.SetActive then globalApply:SetActive(changed) end
            end
            if globalRevert then
                if changed then globalRevert:Enable() else globalRevert:Disable() end
            end
        end
        globalScale:HookScript("OnValueChanged", function(self, value)
            if self._msuf2Refreshing then return end
            local pct = SnapPct(value, 30, 150, 1)
            if pct ~= value then SetSliderValueSafe(self, pct) end
            pendingGlobalEnabled = true
            pendingGlobalScale = Clamp(pct / 100, 0.3, 1.5)
            RefreshGlobalScale()
        end)
        ApplyGlobalScale = function(enabled, value, preset)
            local dbScale, ui = GlobalState()
            ui.Enabled = enabled == true
            ui.Scale = Clamp(value or ui.Scale, 0.3, 1.5)
            dbScale.globalUiScalePreset = preset or (ui.Enabled and "custom" or "auto")
            dbScale.globalUiScaleValue = ui.Enabled and ui.Scale or nil
            pendingGlobalEnabled, pendingGlobalScale = nil, nil
            if ui.Enabled and type(_G.MSUF_SetGlobalUiScale) == "function" then
                _G.MSUF_SetGlobalUiScale(ui.Scale, true)
            elseif (not ui.Enabled) and type(_G.MSUF_ResetGlobalUiScale) == "function" then
                _G.MSUF_ResetGlobalUiScale(true)
            end
            if M.RequestGeneralApply then M.RequestGeneralApply("MSUF2_DASH_GLOBAL_SCALE", { preview = true, applyAll = false }) end
            RefreshGlobalScale()
        end
        Button(scaling, "1080p", globalX, globalTop - 100, 52, 20, function() ApplyGlobalScale(true, 768 / 1080, "1080p") end,
            nil, "scaling.global_ui.preset.1080p")
        Button(scaling, "1440p", globalX + 60, globalTop - 100, 52, 20, function() ApplyGlobalScale(true, 768 / 1440, "1440p") end,
            nil, "scaling.global_ui.preset.1440p")
        Button(scaling, "4K", globalX + 120, globalTop - 100, 42, 20, function() ApplyGlobalScale(true, 768 / 2160, "4k") end,
            nil, "scaling.global_ui.preset.4k")
        Button(scaling, "Pixel", globalX + 170, globalTop - 100, 52, 20, function() ApplyGlobalScale(true, PixelScale(), "pixel") end,
            nil, "scaling.global_ui.preset.pixel")
        globalApply = Button(scaling, "Apply", globalX, globalTop - 126, 72, 20, function()
            local selectedEnabled, selectedScale = SelectedGlobalScale()
            ApplyGlobalScale(selectedEnabled, selectedScale, selectedEnabled and "custom" or "auto")
        end, "primary", "scaling.global_ui.apply")
        globalRevert = Button(scaling, "Revert", globalX + 82, globalTop - 126, 72, 20, function()
            pendingGlobalEnabled, pendingGlobalScale = nil, nil
            RefreshGlobalScale()
        end, nil, "scaling.global_ui.revert_pending", "ephemeral")
        Button(scaling, "Off", globalX + 164, globalTop - 126, 52, 20, function()
            pendingGlobalEnabled = false
            RefreshGlobalScale()
        end, nil, "scaling.global_ui.select_off", "ephemeral")
        local RefreshMsufScale = BuildSimpleScaleColumn({
            x = msufX, top = msufTop, label = "MSUF Frame Scale", help = "Changes the actual MSUF unit frames in-game.",
            semanticPath = "scaling.msuf_frames",
            minPct = MSUF_SCALE_MIN_PERCENT, maxPct = MSUF_SCALE_MAX_PERCENT, stepPct = MSUF_SCALE_STEP_PERCENT,
            applied = AppliedMsufScale,
            pending = PendingMsufScale,
            set = function(value) pendingMsufScale = value end,
            clear = function() pendingMsufScale = nil end,
            apply = function(scaleValue)
                local dbScale = M.GetGeneralDB()
                dbScale.msufUiScale = scaleValue
                pendingMsufScale = nil
                if type(_G.MSUF_ApplyMsufScale) == "function" then _G.MSUF_ApplyMsufScale(scaleValue) end
                if M.RequestGeneralApply then
                    M.RequestGeneralApply("MSUF2_DASH_MSUF_SCALE", { preview = true, applyAll = false, notify = false })
                end
            end,
        })
        local RefreshMenuScale = BuildSimpleScaleColumn({
            x = menuX, top = menuTop, label = "MSUF Menu Scale", help = "Changes only this configuration menu window.",
            semanticPath = "scaling.menu",
            minPct = MENU_SCALE_MIN_PERCENT, maxPct = MENU_SCALE_MAX_PERCENT, stepPct = MENU_SCALE_STEP_PERCENT,
            applied = AppliedMenuScale,
            pending = PendingMenuScale,
            set = function(value) pendingMenuScale = value end,
            clear = function() pendingMenuScale = nil end,
            apply = function(scaleValue)
                local dbScale = M.GetGeneralDB()
                dbScale.slashMenuScale = MenuScaleStoredFromPercent(scaleValue * 100)
                pendingMenuScale = nil
                if M.frame and M.ApplyMenuFrameScale then M.ApplyMenuFrameScale(M.frame)
                elseif M.frame and M.frame.SetScale then
                    local storedScale = dbScale.slashMenuScale
                    M.frame:SetScale((M.GetEffectiveMenuScale and M.GetEffectiveMenuScale(storedScale)) or storedScale)
                end
            end,
        })
        M.TrackRefresh(ctx, RefreshGlobalScale)
        M.TrackRefresh(ctx, RefreshMsufScale)
        M.TrackRefresh(ctx, RefreshMenuScale)
    end
    local changelog = Card(root, "", x0, changelogTop, recoveryW, changelogH, T.colors.panel2, T.colors.borderSoft)
    BuildDashboardChangelog(changelog, recoveryW, {
        title = "Changelog",
        sectionHeader = true,
        top = 0,
        bottom = 18,
        hideSummaryWhenClosed = true,
        onToggle = function()
            RebuildDashboardPage()
        end,
    })
    local supportCompact = recoveryW < 560
    local supportH = supportCompact and 116 or 78
    local support = Card(root, "", x0, supportTop, recoveryW, supportH, T.colors.panel2, T.colors.borderSoft)
    local supportTitle = T.Font(support, "GameFontNormal", M.Tr("How to support MSUF"), T.colors.text)
    supportTitle:SetPoint("TOPLEFT", support, "TOPLEFT", 16, -16)
    local supportTextW = max(160, recoveryW - (supportCompact and 32 or 230))
    local supportDesc = W.Text(support, "If MSUF helps your UI, support links are one click away.", 16, -42, supportTextW, T.colors.muted)
    if supportDesc.SetWordWrap then supportDesc:SetWordWrap(true) end
    if supportDesc.SetNonSpaceWrap then supportDesc:SetNonSpaceWrap(true) end
    local aboutVer
    if _G.C_AddOns and type(_G.C_AddOns.GetAddOnMetadata) == "function" then aboutVer = _G.C_AddOns.GetAddOnMetadata("MidnightSimpleUnitFrames", "Version") end
    local aboutText = M.Tr("by Mapko with the help from R41z0r, Lead QA: Aur0r4")
    if type(aboutVer) == "string" and aboutVer ~= "" then
        local displayVersion = aboutVer:match("^%d") and ("v" .. aboutVer) or aboutVer
        aboutText = M.Format(M.Tr("%s  -  by Mapko with the help from R41z0r, Lead QA: Aur0r4"), displayVersion)
    end
    local supportDescH = (supportDesc.GetStringHeight and supportDesc:GetStringHeight()) or 0
    if supportDescH < 12 then supportDescH = 12 end
    local aboutY = -44 - supportDescH - 4
    local supportAbout = W.Text(support, aboutText, 16, aboutY, supportTextW, T.colors.muted)
    if supportAbout.SetWordWrap then supportAbout:SetWordWrap(true) end
    if supportAbout.SetNonSpaceWrap then supportAbout:SetNonSpaceWrap(true) end
    local supportAboutH = (supportAbout.GetStringHeight and supportAbout:GetStringHeight()) or 0
    if supportAboutH < 12 then supportAboutH = 12 end
    local supportTextBottom = math.abs(aboutY - supportAboutH)
    if supportCompact then
        supportH = max(supportH, floor(supportTextBottom + 24 + 24))
    else
        supportH = max(supportH, floor(supportTextBottom + 14))
    end
    support:SetHeight(supportH)
    local supportLinks = {
        { key = "discord", texture = "Discord.png", title = "Discord", tooltip = "Copy Discord Link", url = "https://discord.gg/2Gf9b2Wprz" },
        { key = "patreon", texture = "Patreon.png", title = "Patreon", tooltip = "Click to copy the Patreon support link.", url = "https://www.patreon.com/cw/MidnightSimpleUnitframes" },
        { key = "paypal", texture = "PayPal.png", title = "PayPal", tooltip = "Click to copy the PayPal support link.", url = "https://www.paypal.com/ncp/payment/H3N2P87S53KBQ" },
        { key = "kofi", texture = "Ko-Fi.png", title = "Ko-fi", tooltip = "Click to copy the Ko-fi link.", url = "https://ko-fi.com/midnightsimpleunitframes#linkModal" },
        { key = "github", texture = "GitHub.png", title = "GitHub", tooltip = "Click to copy the GitHub repository link.", url = "https://github.com/Mapkov2/MidnightSimpleUnitFrames" },
    }
    local iconRow = CreateFrame("Frame", nil, support)
    iconRow:SetSize(168, 24)
    if supportCompact then
        iconRow:SetPoint("BOTTOMLEFT", support, "BOTTOMLEFT", 16, 12)
    else
        iconRow:SetPoint("RIGHT", support, "RIGHT", -16, 0)
    end
    local previous
    for i = 1, #supportLinks do
        local data = supportLinks[i]
        local btn = CreateFrame("Button", nil, iconRow)
        btn:SetSize(24, 24)
        local tex = btn:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        tex:SetTexture(iconDir .. data.texture)
        local hover = btn:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, 0.10)
        btn:SetScript("OnClick", function()
            if type(_G.MSUF_ShowCopyLink) == "function" then _G.MSUF_ShowCopyLink(data.title, data.url) end
        end)
        AddTooltip(btn, data.title, data.tooltip)
        RegisterDashboardControl(btn, DashboardMeta("support.link." .. tostring(data.title), "action", {
            actionKey = "copy_support_link",
            actionFixedArgs = { link = data.key },
            anchor = supportTitle,
            keywords = { data.tooltip, "How to support MSUF", "support links", data.url },
            help = data.tooltip,
        }), data.title, "button")
        if previous then
            btn:SetPoint("LEFT", previous, "RIGHT", 12, 0)
        else
            btn:SetPoint("LEFT", iconRow, "LEFT", 0, 0)
        end
        previous = btn
    end
    local bottom = supportTop - supportH
    ctx:SetContentHeight(math.abs(bottom) + 42)
end
M.RegisterPage("home", { title = "MSUF Menu", build = BuildDashboardUX, version = 9 })
