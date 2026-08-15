local addonName, MSUF = ...
MSUF = MSUF or {}
addonName = (type(MSUF.AddonName) == "string" and MSUF.AddonName ~= "" and MSUF.AddonName)
    or "MidnightSimpleUnitFrames"
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local C_Timer = M.MenuTimer or _G.C_Timer

-- Native group preview renderer.
-- Draws the Menu2 party/raid preview using lightweight mock data and page settings. It should
-- mirror runtime layout decisions but never create secure headers or mutate live group frames.
local T = M.Theme
local PreviewHelpers = M.PreviewHelpers or {}
local Specs = M.GroupPreviewSpecs or {}
local GFZoomPan = M.GroupPreviewZoomPan or {}
local PickDefaults = M.PickDefaults
local F = M.Fallbacks or {}
local floor = math.floor
local max = math.max
local min = math.min
local MSUF_ResolveIconTexturePath = _G.MSUF_ResolveIconTexturePath
local GROUP_PREVIEW_REFRESH_DELAY = 0.05
local GROUP_PREVIEW_ANIMATION_INTERVAL = 1 / 20
local WHITE8X8 = Specs.WHITE8X8 or "Interface\\Buttons\\WHITE8X8"
local function RegisterGroupPreviewControl(widget, semanticPath, label, kind, classification, extra)
    local page = M.GroupPage
    if page and type(page.RegisterControl) == "function" then
        page.RegisterControl(widget, { key = M.activeKey }, "preview." .. tostring(semanticPath), label, kind, classification, extra)
    end
    return widget
end
local LAYER_HEADER_COLOR = { 0.45, 0.50, 0.62, 0.80 }
local LAYER_TEXT_ON = { 0.76, 0.80, 0.90, 0.95 }
local HANDLE_FALLBACK_COLOR = { 0.70, 0.80, 1.00 }
local GF_PREVIEW_ROLE_DEFAULT = Specs.ROLE or "HEALER"
local SECTION_PAGE, PAGE_FOCUS, GF_PREVIEW_CLASSES, GF_PREVIEW_NAMES, GF_PREVIEW_ANCHOR_FRAC, GF_AURA_MOCK_ICON_IDS, GF_AURA_GROWTH_TABLE, GF_STATUS_RUNTIME_KEYS = PickDefaults(Specs, [[
    SECTION_PAGE PAGE_FOCUS CLASSES NAMES ANCHOR_FRAC AURA_MOCK_ICON_IDS AURA_GROWTH_TABLE STATUS_RUNTIME_KEYS
]])
if not GF_AURA_GROWTH_TABLE.RIGHTDOWN then GF_AURA_GROWTH_TABLE.RIGHTDOWN = { px = 1, py = 0, sx = 0, sy = -1 } end
local function ShallowCopy(src)
    if type(src) ~= "table" then return nil end
    local out = {}
    for k, v in pairs(src) do
        out[k] = v
    end
    return out
end
local function SetFSColor(fs, color)
    if fs and fs.SetTextColor and color then fs:SetTextColor(color[1], color[2], color[3], color[4] or 1) end
end
local function ScheduleNativePreviewRefresh(box, fn, delay)
    if type(fn) ~= "function" then return end
    if C_Timer and C_Timer.After then
        C_Timer.After(tonumber(delay) or GROUP_PREVIEW_REFRESH_DELAY, fn)
    else
        fn()
    end
end
local function LayerFont(parent, text, color)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    fs:SetText((M.Tr and M.Tr(text or "")) or (text or ""))
    SetFSColor(fs, color or LAYER_TEXT_ON)
    if T and T.StyleFontString then T.StyleFontString(fs, color or LAYER_TEXT_ON, 0) end
    return fs
end
local function GroupPage()
    M.GroupPage = M.GroupPage or {}
    return M.GroupPage
end
local function CurrentScope()
    local gp = GroupPage()
    if type(gp.CurrentScope) == "function" then return gp.CurrentScope() end
    return M.gfScope or "party"
end
local GF_PREVIEW_ROLE_LABELS = {
    TANK = "Tank",
    HEALER = "Healer",
    DAMAGER = "DPS",
}
local GF_PREVIEW_ROLE_ORDER = { "TANK", "HEALER", "DAMAGER" }
local function NormalizePreviewRole(role)
    if role == "TANK" or role == "HEALER" or role == "DAMAGER" then return role end
    return GF_PREVIEW_ROLE_DEFAULT
end
local function PreviewRole(kind)
    kind = kind or CurrentScope()
    local roles = M.gfPreviewRoles
    return NormalizePreviewRole(type(roles) == "table" and roles[kind] or nil)
end
local function SetPreviewRole(kind, role)
    kind = kind or CurrentScope()
    role = NormalizePreviewRole(role)
    M.gfPreviewRoles = M.gfPreviewRoles or {}
    if M.gfPreviewRoles[kind] == role then return false end
    M.gfPreviewRoles[kind] = role
    return true
end
local function NextPreviewRole(kind)
    local current = PreviewRole(kind)
    for i = 1, #GF_PREVIEW_ROLE_ORDER do
        if GF_PREVIEW_ROLE_ORDER[i] == current then
            return GF_PREVIEW_ROLE_ORDER[(i % #GF_PREVIEW_ROLE_ORDER) + 1]
        end
    end
    return GF_PREVIEW_ROLE_DEFAULT
end
local function Conf(kind)
    local gp = GroupPage()
    if type(gp.Conf) == "function" then return gp.Conf(kind) end
    return {}
end
local function CompiledSpec(kind)
    local gf = MSUF and MSUF.GF
    if gf and type(gf.CompileSpec) == "function" then
        kind = kind or CurrentScope()
        local base = gf.CompileSpec(kind, nil, nil)
        if type(base) ~= "table" then return base end
        local spec = ShallowCopy(base) or {}
        local conf = Conf(kind)
        local previewRole = PreviewRole(kind)
        spec.key = "gf_" .. tostring(kind)
        spec.groupKind = kind
        spec._msufMenu2PreviewRuntime = true
        if type(base.power) == "table" then
            local power = ShallowCopy(base.power) or {}
            local powerHeight = tonumber(power.height) or 0
            if type(gf.GetEffectivePowerHeight) == "function" then
                powerHeight = tonumber(gf.GetEffectivePowerHeight(kind, nil, previewRole, conf)) or 0
            elseif type(gf.ShouldShowPowerBarForRole) == "function" and gf.ShouldShowPowerBarForRole(kind, previewRole, conf) ~= true then
                powerHeight = 0
            end
            power.enabled = powerHeight > 0
            power.height = powerHeight
            spec.power = power
            spec.showPowerText = powerHeight > 0 and base.showPowerText == true
        end
        if type(base.status) == "table" then
            local status = ShallowCopy(base.status) or {}
            status.roleValue = previewRole
            spec.status = status
        end
        return spec
    end
    return nil
end
local function PageForGFSection(sectionKey)
    return SECTION_PAGE[sectionKey or ""]
end
local function PreviewFocusForPage(pageKey)
    local focus = M.gfPreviewFocus
    if focus and PageForGFSection(focus) == pageKey then return focus end
    return PAGE_FOCUS[pageKey]
end
local function OpenGFSection(sectionKey)
    M.gfPreviewFocus = sectionKey
    local pageKey = PageForGFSection(sectionKey)
    if pageKey and M.SelectPage then
        local auraLane = sectionKey == "buffs" or sectionKey == "debuffs" or sectionKey == "externals"
        local focusSectionId = auraLane and "auras" or sectionKey
        local scope = CurrentScope()
        local previousAuraLane
        local previousAuraTool
        local requestedAuraLane
        if M.SetMenuStateValue then
            M.SetMenuStateValue("gfScope", scope)
            if pageKey == "gf_auras" then
                M.SetMenuStateValue("auraStyleGFScope", scope == "mythicraid" and "raid" or scope)
                local lane
                if sectionKey == "buffs" then
                    lane = "buff"
                elseif sectionKey == "debuffs" then
                    lane = "debuff"
                elseif sectionKey == "externals" then
                    lane = "externals"
                end
                if lane then
                    M.gfAuraLaneSelection = M.gfAuraLaneSelection or {}
                    previousAuraLane = M.gfAuraLaneSelection[scope] or "buff"
                    requestedAuraLane = lane
                    M.gfAuraLaneSelection[scope] = lane
                    M.gfAuraToolSelection = M.gfAuraToolSelection or {}
                    local tools = M.gfAuraToolSelection[scope]
                    if type(tools) ~= "table" then tools = {}; M.gfAuraToolSelection[scope] = tools end
                    previousAuraTool = tools[lane]
                    tools[lane] = "layout"
                    if lane ~= "externals" then M.SetMenuStateValue("auraStyleGFLane", lane) end
                end
            end
        end
        if sectionKey == "portrait" then
            M.unitPortraitTabSelection = M.unitPortraitTabSelection or {}
            M.unitPortraitTabSelection.gf_party = "placement"
        elseif sectionKey == "sicons" then
            M.gfStatusIconTabSelection = M.gfStatusIconTabSelection or {}
            M.gfStatusIconTabSelection[scope] = "basic"
        end
        ExportPublic("MSUF_EM2_MenuFocusRequest", {
            key = (scope == "raid" and "gf_raid") or (scope == "mythicraid" and "gf_mythicraid") or "gf_party",
            component = sectionKey,
            lane = sectionKey == "buffs" and "buff"
                or (sectionKey == "debuffs" and "debuff"
                or (sectionKey == "externals" and "externals" or nil)),
            pageKey = pageKey,
            sectionId = focusSectionId,
            source = "group-preview",
            explicit = true,
            changedAt = GetTime and GetTime() or 0,
        })
        -- Group Auras builds its lane-specific controls from gfAuraLaneSelection.
        -- Selecting another preview lane must rebuild any cached Group Auras
        -- page, whether it is active or hidden; refreshers still target the old lane.
        if requestedAuraLane and (requestedAuraLane ~= previousAuraLane or previousAuraTool ~= "layout")
            and type(M.InvalidatePage) == "function" then
            M.InvalidatePage(pageKey)
        end
        return M.SelectPage(pageKey) ~= false
    end
    return false
end
local function PreviewAnimationInCombat()
    return (_G.InCombatLockdown and _G.InCombatLockdown()) or _G.MSUF_InCombat == true
end
local function PreviewAnimationActive(box)
    return box and box._animationEnabled == true
end
local function RefreshPreviewAnimationButton(box)
    local btn = box and box._previewAnimationButton
    if not btn then return end
    local active = PreviewAnimationActive(box)
    -- The button plays an animation loop; it does not switch the preview into a
    -- combat state. Label it after what it does, matching the Unit preview.
    local label = active and "Stop" or "Animate"
    local text = (M.Tr and M.Tr(label)) or label
    if btn.fs then
        btn.fs:SetText(text)
    elseif btn.SetText then
        btn:SetText(text)
    end
    if btn.MSUF2RefreshPreviewPill then
        btn:MSUF2RefreshPreviewPill(active)
    elseif btn.SetActive then
        btn:SetActive(active)
    end
end
local function StopPreviewAnimationDriver(box)
    if not (box and box.SetScript) then return end
    box:SetScript("OnUpdate", nil)
end
local function KillPreviewAnimationForCombat(box)
    if not box then return end
    StopPreviewAnimationDriver(box)
    box._animationEnabled = nil
    box._animationElapsed = 0
    box._animationAccum = 0
    box._msufGFMenuPreviewAnimState = nil
    box._msufGFMenuPreviewAuraStates = nil
    RefreshPreviewAnimationButton(box)
end
local function RefreshPreviewAnimationFrame(box)
    if box and type(box.Refresh) == "function" then
        box:Refresh("GROUP_PREVIEW_ANIMATE")
    elseif box and type(box.RequestRefresh) == "function" then
        box:RequestRefresh("GROUP_PREVIEW_ANIMATE")
    end
end
local function PreviewAnimationOnUpdate(box, elapsed)
    if not (box and box._animationEnabled == true and box.IsShown and box:IsShown()) then
        StopPreviewAnimationDriver(box)
        return
    end
    if PreviewAnimationInCombat() then
        KillPreviewAnimationForCombat(box)
        if box._hint then box._hint:SetText((M.Tr and M.Tr("Preview animation pauses during combat.")) or "Preview animation pauses during combat.") end
        return
    end
    elapsed = tonumber(elapsed) or 0
    box._animationElapsed = (tonumber(box._animationElapsed) or 0) + elapsed
    box._animationAccum = (tonumber(box._animationAccum) or 0) + elapsed
    if box._animationAccum < GROUP_PREVIEW_ANIMATION_INTERVAL then return end
    box._animationAccum = 0
    RefreshPreviewAnimationFrame(box)
end
local function StartPreviewAnimationDriver(box)
    if not (box and box._animationEnabled == true) then return end
    if PreviewAnimationInCombat() then
        StopPreviewAnimationDriver(box)
        return
    end
    if box.RegisterEvent then box:RegisterEvent("PLAYER_REGEN_DISABLED") end
    box:SetScript("OnUpdate", PreviewAnimationOnUpdate)
end
local function SetPreviewAnimationEnabled(box, enabled, reason)
    if not box then return end
    enabled = enabled == true
    if enabled and PreviewAnimationInCombat() then
        KillPreviewAnimationForCombat(box)
        if box._hint then box._hint:SetText((M.Tr and M.Tr("Preview animation pauses during combat.")) or "Preview animation pauses during combat.") end
        RefreshPreviewAnimationButton(box)
        return
    end
    if enabled and box._animationEnabled ~= true then
        box._animationElapsed = 0
        box._animationAccum = 0
    end
    box._animationEnabled = enabled
    if enabled then
        StartPreviewAnimationDriver(box)
    else
        StopPreviewAnimationDriver(box)
        box._msufGFMenuPreviewAnimState = nil
        box._msufGFMenuPreviewAuraStates = nil
    end
    RefreshPreviewAnimationButton(box)
    RefreshPreviewAnimationFrame(box)
end
local function TogglePreviewAnimation(box)
    SetPreviewAnimationEnabled(box, not PreviewAnimationActive(box), "GROUP_PREVIEW_COMBAT_ANIMATE_TOGGLE")
end
local function PreviewAllSpecSpellIcons(kind)
    local state = M.gfPreviewAllSpecSpellIcons
    return type(state) == "table" and state[kind or CurrentScope()] == true
end
local function CreatePreviewAnimationButton(box, registerControl)
    if not box or box._previewAnimationButton then return end
    local parent = box._stage or box
    local template = (T and T.Template and T.Template()) or "BackdropTemplate"
    local btn = CreateFrame("Button", nil, parent, template)
    btn:SetSize(74, 22)
    if btn.SetBackdrop then btn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 }) end
    btn.fs = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    btn.fs:SetPoint("CENTER", btn, "CENTER", 0, 0)
    btn.fs:SetJustifyH("CENTER")
    if btn.fs.SetJustifyV then btn.fs:SetJustifyV("MIDDLE") end
    if T and T.StyleFontString then T.StyleFontString(btn.fs, T.colors and T.colors.text or LAYER_TEXT_ON, 0) end
    btn._preview = box
    btn._msuf2AllowCombatClick = true
    if box._zoomBar then
        btn:SetPoint("RIGHT", box._zoomBar, "LEFT", -6, 0)
    elseif box._stage then
        btn:SetPoint("TOPRIGHT", box._stage, "TOPRIGHT", -154, -6)
    else
        btn:SetPoint("TOPRIGHT", box, "TOPRIGHT", -104, -34)
    end
    if PreviewHelpers.StylePreviewPillButton then PreviewHelpers.StylePreviewPillButton(btn, T, { fontField = "fs" }) end
    if btn.SetFrameLevel and parent.GetFrameLevel then btn:SetFrameLevel((parent:GetFrameLevel() or 0) + 85) end
    btn:SetScript("OnClick", function(self) TogglePreviewAnimation(self._preview) end)
    btn._msuf2CommandAction = {
        kind = "toggle",
        historyMode = "none",
        get = function() return PreviewAnimationActive(box) end,
        set = function(enabled)
            if enabled == true and PreviewAnimationInCombat() then return false end
            SetPreviewAnimationEnabled(box, enabled == true, "GROUP_PREVIEW_ASSISTANT_ANIMATION")
            return PreviewAnimationActive(box) == (enabled == true)
        end,
    }
    (registerControl or RegisterGroupPreviewControl)(btn, "combat_animation", "Group Preview Animation", "button", "ephemeral")
    if M.AddTooltip then
        M.AddTooltip(btn, "Animate Preview", "Animates health, power, prediction bars, text values, aura timers, and combat-state indicators in this preview only. Pauses during combat.", { hook = true })
    end
    box._previewAnimationButton = btn
    box.RefreshAnimationButton = RefreshPreviewAnimationButton
    RefreshPreviewAnimationButton(box)
end
local function RefreshPreviewRoleButton(box, kind)
    local btn = box and box._previewRoleButton
    if not btn then return end
    local role = PreviewRole(kind)
    local text = (M.Tr and M.Tr(GF_PREVIEW_ROLE_LABELS[role])) or GF_PREVIEW_ROLE_LABELS[role]
    if btn.fs and btn.fs.SetText then btn.fs:SetText(text)
    elseif btn.SetText then btn:SetText(text) end
end
local function CreatePreviewRoleButton(box, registerControl)
    if not box or box._previewRoleButton then return end
    local parent = box._stage or box
    local template = (T and T.Template and T.Template()) or "BackdropTemplate"
    local btn = CreateFrame("Button", nil, parent, template)
    btn:SetSize(92, 22)
    if btn.SetBackdrop then btn:SetBackdrop({ bgFile = WHITE8X8, edgeFile = WHITE8X8, edgeSize = 1 }) end
    btn.fs = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    btn.fs:SetPoint("CENTER", btn, "CENTER", 0, 0)
    btn.fs:SetJustifyH("CENTER")
    if btn.fs.SetJustifyV then btn.fs:SetJustifyV("MIDDLE") end
    if T and T.StyleFontString then T.StyleFontString(btn.fs, T.colors and T.colors.text or LAYER_TEXT_ON, 0) end
    if box._previewAnimationButton then
        btn:SetPoint("RIGHT", box._previewAnimationButton, "LEFT", -6, 0)
    elseif box._zoomBar then
        btn:SetPoint("RIGHT", box._zoomBar, "LEFT", -86, 0)
    end
    if PreviewHelpers.StylePreviewPillButton then PreviewHelpers.StylePreviewPillButton(btn, T, { fontField = "fs" }) end
    if btn.SetFrameLevel and parent.GetFrameLevel then btn:SetFrameLevel((parent:GetFrameLevel() or 0) + 85) end
    btn:SetScript("OnClick", function()
        local kind = CurrentScope()
        SetPreviewRole(kind, NextPreviewRole(kind))
        RefreshPreviewRoleButton(box, kind)
        if box.Refresh then box:Refresh("GROUP_PREVIEW_ROLE") end
    end)
    local register = registerControl or RegisterGroupPreviewControl
    register(btn, "member_role", "Group Preview Member Role", "button", "ephemeral")
    box._previewRoleButton = btn
    box.RefreshRoleButton = RefreshPreviewRoleButton
    RefreshPreviewRoleButton(box)
end
local function ApplyGroupPreviewFlatBackdrop(frame, texture, bg, border)
    if not (frame and frame.SetBackdrop) then return end
    texture = texture or "Interface\\Buttons\\WHITE8X8"
    frame:SetBackdrop({ bgFile = texture, edgeFile = texture, edgeSize = 1 })
    bg = bg or { 0, 0, 0, 1 }
    frame:SetBackdropColor(bg[1] or 0, bg[2] or 0, bg[3] or 0, bg[4] or 1)
    if border and frame.SetBackdropBorderColor then
        frame:SetBackdropBorderColor(border[1] or 0, border[2] or 0, border[3] or 0, border[4] or 1)
    end
end
local UpdateHint
local function ApplyGroupPinnedPresentation(box, pinned, opts, sideW)
    if not box then return end
    local colors = (T and T.colors) or {}
    local shade = box._msuf2PinnedHeaderShade
    if not shade and box.CreateTexture then
        shade = box:CreateTexture(nil, "BORDER", nil, -1)
        shade:SetPoint("TOPLEFT", box, "TOPLEFT", 1, -1)
        shade:SetPoint("TOPRIGHT", box, "TOPRIGHT", -1, -1)
        shade:SetHeight(29)
        shade:SetTexture(WHITE8X8)
        box._msuf2PinnedHeaderShade = shade
    end
    local line = box._msuf2PinnedHeaderLine
    if not line and box.CreateTexture then
        line = box:CreateTexture(nil, "BORDER", nil, 0)
        line:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -29)
        line:SetPoint("TOPRIGHT", box, "TOPRIGHT", -10, -29)
        line:SetHeight(1)
        line:SetTexture(WHITE8X8)
        box._msuf2PinnedHeaderLine = line
    end
    if M.PreviewSelectionBar then M.PreviewSelectionBar.SetShown(box, true) end
    if box.ApplyDockedPreviewLayout then box:ApplyDockedPreviewLayout(12) end
    if box._footer then box._footer:SetShown(not pinned) end
    if shade then
        local bg = colors.coreShadow or { 0.006, 0.016, 0.032, 1 }
        shade:SetColorTexture(bg[1], bg[2], bg[3], pinned and 0.92 or 0)
        shade:SetShown(pinned)
    end
    if line then
        local border = colors.borderSoft or colors.border or { 0.070, 0.260, 0.390, 1 }
        line:SetColorTexture(border[1], border[2], border[3], pinned and 0.52 or 0)
        line:SetShown(pinned)
    end
    if UpdateHint then UpdateHint(box, box._selectedHandle) end
end
local function EnsureGroupLayersButton(box)
    if box._msuf2LayersButton then return box._msuf2LayersButton end
    local btn = T.Button(box, ((M.Tr and M.Tr("Layers")) or "Layers") .. " v", 76, 20)
    if T.CenterButtonLabel then T.CenterButtonLabel(btn) end
    btn:SetScript("OnClick", function()
        if box._layers then box._layers:SetShown(not box._layers:IsShown()) end
    end)
    if M.AddTooltip then M.AddTooltip(btn, "Layers", "Toggle the preview layer list.", { hook = true }) end
    local registerControl = box._msuf2RegisterGroupPreviewControl or RegisterGroupPreviewControl
    registerControl(btn, "layers.popover", "Group Preview Layers", "button", "ephemeral")
    box._msuf2LayersButton = btn
    return btn
end
local function SetGroupPreviewToolsShown(box, shown)
    local controlsHint = box and box._msuf2PreviewControlsHint
    if not box then return end
    if not shown then
        if box._msuf2CompactToolsHidden ~= true then
            box._msuf2CompactControlsHintWasShown = controlsHint and controlsHint.IsShown and controlsHint:IsShown() or false
        end
        box._msuf2CompactToolsHidden = true
        if box._zoomBar then box._zoomBar:Hide() end
        if box._previewAnimationButton then box._previewAnimationButton:Hide() end
        if box._previewRoleButton then box._previewRoleButton:Hide() end
        if controlsHint then controlsHint:Hide() end
        return
    end
    box._msuf2CompactToolsHidden = nil
    if box._zoomBar then box._zoomBar:Show() end
    if box._previewAnimationButton then box._previewAnimationButton:Show() end
    if box._previewRoleButton then box._previewRoleButton:Show() end
    if controlsHint and box._msuf2CompactControlsHintWasShown then controlsHint:Show() end
end
local function LayoutGroupPreviewHeaderControls(box, compact)
    if not box then return end
    local header = box._msuf2CompactHeader
    local expandBtn = box._msuf2CompactExpandButton
    local layersBtn = box._msuf2LayersButton
    if compact and header then
        if layersBtn then
            layersBtn:SetText(((M.Tr and M.Tr("Layers")) or "Layers") .. " v")
            layersBtn:SetParent(header)
            layersBtn:ClearAllPoints()
            if expandBtn then layersBtn:SetPoint("RIGHT", expandBtn, "LEFT", -8, 0)
            else layersBtn:SetPoint("RIGHT", header, "RIGHT", -108, 0) end
            if layersBtn.SetFrameLevel and header.GetFrameLevel then layersBtn:SetFrameLevel((header:GetFrameLevel() or 1) + 3) end
        end
        return
    end
    if layersBtn then
        layersBtn:SetText((M.Tr and M.Tr("Layers")) or "Layers")
        layersBtn:SetParent(box)
        layersBtn:ClearAllPoints()
        layersBtn:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -5)
    end
end
local function ApplyGroupCompactPresentation(box, compact, sideW)
    if not box then return end
    compact = compact == true
    box._msuf2CompactPreview = compact
    if box._msuf2PinnedFloating == true then compact = false end
    if PreviewHelpers.SwitchCompactZoomMode then PreviewHelpers.SwitchCompactZoomMode(box, compact, 1.50) end
    local stage, layers = box._stage, box._layers
    if compact then
        if box._title then box._title:Hide() end
        if box._hint then box._hint:Hide() end
        SetGroupPreviewToolsShown(box, false)
        if stage then
            stage:ClearAllPoints()
            stage:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -8)
            stage:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -8, 8)
        end
        local layersBtn = EnsureGroupLayersButton(box)
        if M.PreviewSelectionBar then M.PreviewSelectionBar.SetShown(box, false) end
        if layers and stage then
            layers:ClearAllPoints()
            if box._msuf2CompactHeader then layers:SetPoint("TOPRIGHT", layersBtn, "BOTTOMRIGHT", 0, -6)
            else layers:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -28) end
            -- The chips keep their flow inside the popover, sized to a readable
            -- column; the caption is redundant behind a "Layers" button.
            local popoverWidth = 268
            layers:SetWidth(popoverWidth)
            if box._msuf2LayerRailHeader then box._msuf2LayerRailHeader:Hide() end
            if box.LayoutLayerRail then box:LayoutLayerRail(popoverWidth + 24) end
            if layers.SetFrameLevel and stage.GetFrameLevel then layers:SetFrameLevel((stage:GetFrameLevel() or 1) + 90) end
            layers:Hide()
        end
        layersBtn:Show()
        LayoutGroupPreviewHeaderControls(box, true)
        return
    end
    if box._title then box._title:Show() end
    if box._hint then box._hint:Show() end
    SetGroupPreviewToolsShown(box, true)
    LayoutGroupPreviewHeaderControls(box, false)
    if M.PreviewSelectionBar then M.PreviewSelectionBar.SetShown(box, true) end
    if box.ApplyDockedPreviewLayout then box:ApplyDockedPreviewLayout(12) end
    if box._msuf2LayersButton then box._msuf2LayersButton:Hide() end
end
local function PreviewScopeLabel(kind)
    if kind == "raid" then return "Raid" end
    if kind == "mythicraid" then return "Mythic Raid" end
    return "Party"
end
local function ResolvePreviewStatusbarTexture(conf, key)
    conf = conf or {}
    local value = conf[key]
    if value == nil or value == "" then
        local db = M.EnsureDB and M.EnsureDB()
        value = db and db.general and db.general.barTexture or "Solid"
    end
    if type(_G.MSUF_ResolveStatusbarTextureKey) == "function" then
        local texture = _G.MSUF_ResolveStatusbarTextureKey(value)
        if texture then return texture end
    end
    if LibStub then
        local lsm = LibStub("LibSharedMedia-3.0", true)
        if lsm and type(lsm.Fetch) == "function" then
            local texture = lsm:Fetch("statusbar", value, true)
            if texture then return texture end
        end
    end
    return "Interface\\Buttons\\WHITE8X8"
end
local function NormalizeHealthMode(mode)
    if type(mode) ~= "string" then return nil end
    mode = mode:lower()
    if mode == "global" then return nil end
    if mode == "class" or mode == "gradient" or mode == "dark" or mode == "unified" then return mode end
    if mode == "custom" then return "unified" end
    return nil
end
local function PreviewGradientHealth(conf, cache)
    local general = _G.MSUF_DB and _G.MSUF_DB.general or {}
    conf = conf or {}
    return {
        gradientLowR = (cache and cache.healthGradientLowR) or conf.healthGradientLowR or general.healthGradientLowR or 1,
        gradientLowG = (cache and cache.healthGradientLowG) or conf.healthGradientLowG or general.healthGradientLowG or 0,
        gradientLowB = (cache and cache.healthGradientLowB) or conf.healthGradientLowB or general.healthGradientLowB or 0,
        gradientMidR = (cache and cache.healthGradientMidR) or conf.healthGradientMidR or general.healthGradientMidR or 1,
        gradientMidG = (cache and cache.healthGradientMidG) or conf.healthGradientMidG or general.healthGradientMidG or 1,
        gradientMidB = (cache and cache.healthGradientMidB) or conf.healthGradientMidB or general.healthGradientMidB or 0,
        gradientHighR = (cache and cache.healthGradientHighR) or conf.healthGradientHighR or general.healthGradientHighR or 0,
        gradientHighG = (cache and cache.healthGradientHighG) or conf.healthGradientHighG or general.healthGradientHighG or 1,
        gradientHighB = (cache and cache.healthGradientHighB) or conf.healthGradientHighB or general.healthGradientHighB or 0,
    }
end
local function PreviewGradientColor(conf, cache, pct)
    local health = PreviewGradientHealth(conf, cache)
    local p = max(0, min(1, tonumber(pct) or 0.72))
    local common = MSUF and MSUF.UFBarTextCommon
    if common and type(common.PreviewHealthGradientColor) == "function" then
        local r, g, b = common.PreviewHealthGradientColor(health, p)
        if r ~= nil then return r, g, b end
    end
    local lr, lg, lb = health.gradientLowR, health.gradientLowG, health.gradientLowB
    local mr, mg, mb = health.gradientMidR, health.gradientMidG, health.gradientMidB
    local hr, hg, hb = health.gradientHighR, health.gradientHighG, health.gradientHighB
    if p <= 0.5 then
        local t = p * 2
        return lr + (mr - lr) * t, lg + (mg - lg) * t, lb + (mb - lb) * t
    end
    local t = (p - 0.5) * 2
    return mr + (hr - mr) * t, mg + (hg - mg) * t, mb + (hb - mb) * t
end
local function HealthColor(conf, pct, classToken)
    conf = conf or {}
    local getCache = _G.MSUF_UFCore_GetSettingsCache
    local cache = type(getCache) == "function" and getCache() or nil
    local mode = NormalizeHealthMode(conf.gfBarMode)
    if not mode then
        local general = _G.MSUF_DB and _G.MSUF_DB.general or nil
        local globalMode = NormalizeHealthMode((cache and cache.barMode) or (general and general.barMode))
        if globalMode == "gradient" and cache and cache.healthGradientEnabled == false then
            globalMode = "class"
        elseif globalMode == "gradient" and not cache and general and general.enableHealthGradient == false then
            globalMode = "class"
        end
        mode = globalMode or NormalizeHealthMode(conf.healthColorMode) or "class"
    end
    if mode == "dark" then
        return conf.gfDarkR or (cache and cache.darkBarR) or 0,
            conf.gfDarkG or (cache and cache.darkBarG) or 0,
            conf.gfDarkB or (cache and cache.darkBarB) or 0
    end
    if mode == "unified" then
        return conf.gfUnifiedR or (cache and cache.unifiedBarR) or 0.10,
            conf.gfUnifiedG or (cache and cache.unifiedBarG) or 0.60,
            conf.gfUnifiedB or (cache and cache.unifiedBarB) or 0.90
    end
    if mode == "class" then
        local fastClass = _G.MSUF_UFCore_GetClassBarColorFast
        local r, g, b
        if type(fastClass) == "function" then r, g, b = fastClass(classToken) end
        if not r then
            local cc = classToken and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[classToken]
            if cc then r, g, b = cc.r, cc.g, cc.b end
        end
        return r or 0.2, g or 0.8, b or 0.2
    end
    if mode == "gradient" then
        return PreviewGradientColor(conf, cache, pct)
    end
    return conf.healthCustomR or 0.2,
        conf.healthCustomG or 0.8,
        conf.healthCustomB or 0.2
end
local maskRoot = "Interface\\AddOns\\" .. tostring(addonName or "MidnightSimpleUnitFrames") .. "\\Media\\Masks\\"
local GF_PREVIEW_ROUNDED_MASK = Specs.ROUNDED_MASK or (maskRoot .. "rounded_clean_mask_s3.png")
local GF_PREVIEW_ROUNDED_EDGE = Specs.ROUNDED_EDGE or (maskRoot .. "rounded_clean_edge_s3.png")
local GF_PREVIEW_MIN_W = Specs.MIN_W or 380
local GF_PREVIEW_MIN_H = Specs.MIN_H or 130
local GF_PREVIEW_ZOOM_MIN = Specs.ZOOM_MIN or 0.35
local GF_PREVIEW_ZOOM_MAX = Specs.ZOOM_MAX or 4.0
local function Tr(text)
    return (M.Tr and M.Tr(text)) or text
end
local function ClassColor(classToken, dr, dg, db)
    if type(_G.MSUF_UFCore_GetClassBarColorFast) == "function" then
        local r, g, b = _G.MSUF_UFCore_GetClassBarColorFast(classToken)
        if r then return r, g, b end
    end
    local c = classToken and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[classToken]
    if c then return c.r, c.g, c.b end
    return dr or 0.06, dg or 0.06, db or 0.07
end
local function AuraGrowth(growth)
    return GF_AURA_GROWTH_TABLE[growth] or GF_AURA_GROWTH_TABLE.RIGHTDOWN
end
local function GrowthFromCompiled(primary, wrap, fallback)
    if primary == "LEFT" then
        return wrap == "UP" and "LEFTUP" or "LEFTDOWN"
    elseif primary == "UP" then
        return "UPRIGHT"
    elseif primary == "DOWN" then
        return "DOWNRIGHT"
    end
    return wrap == "UP" and "RIGHTUP" or (fallback or "RIGHTDOWN")
end
local function CompiledAuraLane(auras, key, fallback)
    if type(auras) ~= "table" then return fallback or {} end
    local prefix, showKey
    if key == "buff" then
        prefix, showKey = "buff", "showBuffs"
    elseif key == "trackedBuff" then
        prefix, showKey = "trackedBuff", "showTrackedBuffs"
    elseif key == "debuff" then
        prefix, showKey = "debuff", "showDebuffs"
    elseif key == "external" then
        prefix, showKey = "external", "showExternals"
    else
        return fallback or {}
    end
    local maxKey = key == "trackedBuff" and "maxTrackedBuffs"
        or (key == "buff" and "maxBuffs")
        or (key == "debuff" and "maxDebuffs")
        or "maxExternals"
    local out = {
        _compiled = true,
        enabled = auras[showKey] == true,
        max = auras[maxKey],
        perRow = auras[prefix .. "PerRow"],
        size = auras[prefix .. "IconSize"],
        iconZoom = auras.iconZoom,
        spacing = auras[prefix .. "Spacing"],
        anchor = auras[prefix .. "Anchor"],
        growth = GrowthFromCompiled(auras[prefix .. "GrowthX"], auras[prefix .. "GrowthY"], fallback and fallback.growth),
        x = auras[prefix .. "OffsetX"],
        y = auras[prefix .. "OffsetY"],
        layer = auras[prefix .. "Layer"],
        strata = auras[prefix .. "Strata"],
        showCooldownSwipe = auras[prefix .. "ShowCooldownSwipe"],
        cooldownSwipeReverse = auras[prefix .. "CooldownSwipeReverse"],
        showCooldown = auras[prefix .. "ShowCooldown"],
        showCooldownText = auras[prefix .. "ShowCooldown"],
        showStacks = auras[prefix .. "ShowStacks"],
        showTooltip = auras[prefix .. "ShowTooltip"],
        showDurationBar = auras[prefix .. "ShowDurationBar"],
        durationBarHeight = auras[prefix .. "DurationBarHeight"],
        durationBarDisplay = auras[prefix .. "DurationBarDisplay"],
        durationBarPosition = auras[prefix .. "DurationBarPosition"],
        durationBarDirection = auras[prefix .. "DurationBarDirection"],
        cooldownSize = auras[prefix .. "CooldownSize"],
        cooldownAnchor = auras[prefix .. "CooldownAnchor"],
        cooldownX = auras[prefix .. "CooldownX"],
        cooldownY = auras[prefix .. "CooldownY"],
        cooldownDecimalSeconds = auras[prefix .. "CooldownDecimalSeconds"],
        stackSize = auras[prefix .. "StackSize"],
        stackAnchor = auras[prefix .. "StackAnchor"],
        stackX = auras[prefix .. "StackX"],
        stackY = auras[prefix .. "StackY"],
        dispelBorderMode = key == "debuff" and auras.debuffDispelBorderMode or nil,
        showDispelBorder = key == "debuff" and auras.debuffShowDispelBorder or nil,
        showDispelSymbol = key == "debuff" and auras.debuffShowDispelSymbol or nil,
        alpha = tonumber(auras[prefix .. "Alpha"]) or 1,
        behindBar = (tonumber(auras[prefix .. "Alpha"]) or 1) < 1,
    }
    return out
end
local function RuntimeStatusConfig(status, spec)
    if type(status) ~= "table" or type(spec) ~= "table" then return nil end
    local value = spec.value
    if value == "statusText" then
        return status.statusText and status.statusText.dead or status.statusText
    elseif value == "statusGhostText" then
        return status.statusText and status.statusText.ghost or nil
    elseif value == "statusAFKText" then
        return status.statusText and status.statusText.afk or nil
    elseif value == "statusAFKTimer" then
        return status.statusText and status.statusText.afkTimer or nil
    elseif value == "statusDNDText" then
        return status.statusText and status.statusText.dnd or nil
    end
    local key = GF_STATUS_RUNTIME_KEYS[value]
    return key and status[key] or nil
end
local function Int(value, fallback, minValue, maxValue)
    local n = floor((tonumber(value) or tonumber(fallback) or 0) + 0.0001)
    if minValue ~= nil and n < minValue then n = minValue end
    if maxValue ~= nil and n > maxValue then n = maxValue end
    return n
end
local gfMockSpellTextureCache = {}
local function MockSpellTexture(spellId)
    local cached = gfMockSpellTextureCache[spellId]
    if cached then return cached end
    if C_Spell and C_Spell.GetSpellTexture then
        local tex = C_Spell.GetSpellTexture(spellId)
        if tex then
            tex = (type(MSUF_ResolveIconTexturePath) == "function" and MSUF_ResolveIconTexturePath(tex)) or tex
            gfMockSpellTextureCache[spellId] = tex
            return tex
        end
    end
    if GetSpellInfo then
        local _, _, icon = GetSpellInfo(spellId)
        if icon then
            icon = (type(MSUF_ResolveIconTexturePath) == "function" and MSUF_ResolveIconTexturePath(icon)) or icon
            gfMockSpellTextureCache[spellId] = icon
            return icon
        end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end
local function CurrentSpellInfo(kind)
    local gp = GroupPage()
    local gf = MSUF and MSUF.GF
    local si = gf and gf.SpellIndicators
    local specKey = type(gp.EffectiveSpellSpec) == "function" and gp.EffectiveSpellSpec(kind) or nil
    local auraName = type(gp.CurrentSpellAura) == "function" and gp.CurrentSpellAura(kind) or nil
    if not (specKey and auraName and auraName ~= "") then return nil, specKey, auraName end
    local trackable = si and si.TrackableAuras and si.TrackableAuras[specKey]
    if type(trackable) == "table" then
        for i = 1, #trackable do
            local info = trackable[i]
            if info and info.name == auraName then return info, specKey, auraName end
        end
    end
    return nil, specKey, auraName
end
local function CurrentSpellConfig(kind)
    local gp = GroupPage()
    if type(gp.CurrentSpellConfig) == "function" then
        local cfg = gp.CurrentSpellConfig(kind, false)
        if type(cfg) == "table" then return cfg end
    end
    return nil
end
local function CurrentSpellPlaced(kind)
    local gp = GroupPage()
    if type(gp.PlacedConfig) == "function" then
        local placed = gp.PlacedConfig(kind, false)
        if type(placed) == "table" then return placed end
    end
    local cfg = CurrentSpellConfig(kind)
    return type(cfg and cfg.placed) == "table" and cfg.placed or nil
end
local function CurrentSpellTexture(kind)
    local info, specKey, auraName = CurrentSpellInfo(kind)
    local gf = MSUF and MSUF.GF
    local si = gf and gf.SpellIndicators
    if si and type(si.GetAuraIcon) == "function" and specKey and auraName and auraName ~= "" then
        local icon = si.GetAuraIcon(specKey, auraName)
        if icon then return icon end
    end
    if info and info.spellId then return MockSpellTexture(info.spellId) end
    return MockSpellTexture(774)
end
local function CurrentSpellColor(kind)
    local info = CurrentSpellInfo(kind)
    local c = info and info.color
    return (c and c[1]) or 0.69, (c and c[2]) or 0.50, (c and c[3]) or 0.88
end
local function Round(value)
    return floor((tonumber(value) or 0) + 0.5)
end
local function ScaleValue(value, scale, minValue)
    local v = Round((tonumber(value) or 0) * (tonumber(scale) or 1))
    if minValue ~= nil and v < minValue then v = minValue end
    return v
end
if GFZoomPan.Configure then
    GFZoomPan.Configure({
        T = T,
        TR = Tr,
        WHITE8X8 = WHITE8X8,
        UpdateHint = function(box, selected)
            if UpdateHint then UpdateHint(box, selected) end
        end,
    })
end
local ClampZoom = GFZoomPan.Clamp or function(value)
    value = tonumber(value) or 1
    if value < GF_PREVIEW_ZOOM_MIN then return GF_PREVIEW_ZOOM_MIN end
    if value > GF_PREVIEW_ZOOM_MAX then return GF_PREVIEW_ZOOM_MAX end
    return floor(value * 100 + 0.5) / 100
end
local UpdateZoomControls = GFZoomPan.UpdateControls or F.Noop
local ResolveDefaultZoomLock = GFZoomPan.ResolveDefaultLock or F.Noop
local SetZoom = GFZoomPan.SetZoom or F.Noop
local StepZoom = GFZoomPan.Step or F.Noop
local StartPan = GFZoomPan.Start or F.False
local StopPan = GFZoomPan.Stop or F.Noop
local function ReadBarsBool(key, default)
    local bars = _G.MSUF_DB and _G.MSUF_DB.bars
    local value = bars and bars[key]
    if value == nil then return default and true or false end
    return value and true or false
end
local function NormalizeAnchorMode(value, fallback)
    local mode = tonumber(value) or fallback or 3
    if mode < 1 or mode > 5 then mode = fallback or 3 end
    return mode
end
local function SharedHealPredictionEnabled()
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    if type(gen) ~= "table" then return false end
    if gen.showSelfHealPrediction ~= nil then return gen.showSelfHealPrediction == true end
    if gen.enableHealPrediction ~= nil then return gen.enableHealPrediction ~= false end
    return false
end
local function HealPredictionEnabled(kind, conf)
    local gf = MSUF and MSUF.GF
    if gf and type(gf.IsHealPredictionEnabled) == "function" then return gf.IsHealPredictionEnabled(kind, conf) == true end
    if conf and conf.hlOverride == true and conf.healPredEnabled ~= nil then return conf.healPredEnabled == true end
    return SharedHealPredictionEnabled()
end
local function HealPredAnchorMode(conf)
    if conf and conf.hlOverride == true and conf.healPredAnchorMode ~= nil then return NormalizeAnchorMode(conf.healPredAnchorMode, 3) end
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    return NormalizeAnchorMode(gen and gen.healPredAnchorMode, 3)
end
local GFRounded = (M.GroupPreviewRounded and M.GroupPreviewRounded.Install and M.GroupPreviewRounded.Install({
    PreviewHelpers = PreviewHelpers,
    Specs = Specs,
    WHITE8X8 = WHITE8X8,
    ROUNDED_MASK = GF_PREVIEW_ROUNDED_MASK,
    ROUNDED_EDGE = GF_PREVIEW_ROUNDED_EDGE,
    ReadBarsBool = ReadBarsBool,
    Round = Round,
    HealPredAnchorMode = HealPredAnchorMode,
})) or {}
local SetOutlineShown = GFRounded.SetOutlineShown or F.Noop
local LayoutOutline = GFRounded.LayoutOutline or F.Noop
local BaseEdgeColor = GFRounded.BaseEdgeColor or F.BlackRGBA
local ApplyRounded = GFRounded.ApplyRounded or F.False
local function ConfigToOffset(value, scale)
    return Round((tonumber(value) or 0) * (tonumber(scale) or 1))
end
local function OffsetToConfig(value, scale)
    scale = tonumber(scale) or 1
    if scale <= 0 then scale = 1 end
    return Round((tonumber(value) or 0) / scale)
end
local function ResolveAnchor(rx, ry)
    local best, bestD = "CENTER", 1e9
    for point, frac in pairs(GF_PREVIEW_ANCHOR_FRAC) do
        local dx = rx - frac[1]
        local dy = ry - (1 - frac[2])
        local d = dx * dx + dy * dy
        if d < bestD then best, bestD = point, d end
    end
    return best
end
local function HandleOffset(handle, anchorFrame, anchor)
    local frac = GF_PREVIEW_ANCHOR_FRAC[anchor]
    if not (handle and anchorFrame and frac) then return 0, 0 end
    local hL, hB, hW, hH = handle:GetLeft() or 0, handle:GetBottom() or 0, handle:GetWidth() or 1, handle:GetHeight() or 1
    local aL, aB, aW, aH = anchorFrame:GetLeft() or 0, anchorFrame:GetBottom() or 0, anchorFrame:GetWidth() or 1, anchorFrame:GetHeight() or 1
    local hx = hL + hW * frac[1]
    local hy = hB + hH * frac[2]
    local ax = aL + aW * frac[1]
    local ay = aB + aH * frac[2]
    return Round(hx - ax), Round(hy - ay)
end
local function PointOffset(px, py, anchorFrame, anchor)
    local frac = GF_PREVIEW_ANCHOR_FRAC[anchor]
    if not (anchorFrame and frac) then return 0, 0 end
    local aL, aB = anchorFrame:GetLeft() or 0, anchorFrame:GetBottom() or 0
    local aW, aH = anchorFrame:GetWidth() or 1, anchorFrame:GetHeight() or 1
    local ax = aL + aW * frac[1]
    local ay = aB + aH * frac[2]
    return Round((px or 0) - ax), Round((py or 0) - ay)
end
local function MockPowerHeight(kind, conf, zoom, frameScale)
    local livePowerH
    local gf = MSUF and MSUF.GF
    local previewRole = PreviewRole(kind)
    if gf and gf.GetEffectivePowerHeight then livePowerH = gf.GetEffectivePowerHeight(kind, nil, previewRole, conf) end
    if livePowerH == nil then
        local raw = conf and (tonumber(conf.powerHeight) or 6) or 6
        if gf and gf.ShouldShowPowerBarForRole and not gf.ShouldShowPowerBarForRole(kind, previewRole, conf) then raw = 0 end
        livePowerH = raw > 0 and ScaleValue(raw, frameScale or 1, 0) or 0
    end
    livePowerH = tonumber(livePowerH) or 0
    if livePowerH <= 0 then return 0 end
    return Round(livePowerH * (tonumber(zoom) or 1))
end
local function HandleText(handle)
    if not handle then return "Group preview" end
    local label = handle._label
    local text = label and label.GetText and label:GetText()
    if text and text ~= "" then return text end
    local previewText = handle._previewText
    if previewText and previewText ~= "" then return previewText end
    return handle._key or "Group preview"
end
local function ClampLayer(value, fallback)
    local v = floor((tonumber(value) or fallback or 0) + 0.5)
    if v < 0 then return 0 end
    if v > 30 then return 30 end
    return v
end
--- Preview-only status entries. The group number is a placed status text on the
--- live frame, but it owns a dedicated menu card instead of a slot in the
--- Status Icons dropdown. Appending it here gives the preview a draggable
--- handle (and the generic anchor/x/y write-back) without adding a duplicate
--- entry to that dropdown, the layer overview, or the Assistant ledgers.
local PREVIEW_ONLY_STATUS_SPECS = {
    {
        value = "showGroupNumber", text = "Group Number", enabled = "showGroupNumber",
        style = "groupNumberStyle",
        size = "groupNumberSize", anchor = "groupNumberAnchor",
        x = "groupNumberX", y = "groupNumberY", layer = "groupNumberLayer",
        defaultSize = 10, defaultAnchor = "BOTTOMRIGHT", defaultLayer = 7,
        previewOnly = true, isText = true, alwaysInMode = true, fitTextBounds = true,
    },
}
local previewStatusSpecCache, previewStatusSpecSource
local function StatusSpecs()
    local gp = GroupPage()
    local base
    if type(gp.GF_STATUS_ICON_SPECS) == "table" and #gp.GF_STATUS_ICON_SPECS > 0 then
        base = gp.GF_STATUS_ICON_SPECS
    else
        local sharedSpecs = M.GroupSpecs and M.GroupSpecs.GF_STATUS_ICON_SPECS
        if type(sharedSpecs) == "table" and #sharedSpecs > 0 then base = sharedSpecs end
    end
    if not base then return PREVIEW_ONLY_STATUS_SPECS end
    if previewStatusSpecSource == base then return previewStatusSpecCache end
    local merged = {}
    for i = 1, #base do merged[i] = base[i] end
    for i = 1, #PREVIEW_ONLY_STATUS_SPECS do merged[#merged + 1] = PREVIEW_ONLY_STATUS_SPECS[i] end
    previewStatusSpecSource, previewStatusSpecCache = base, merged
    return merged
end
local function CurrentStatusSpec()
    local gp = GroupPage()
    if type(gp.CurrentGFStatusSpec) == "function" then
        local spec = gp.CurrentGFStatusSpec()
        if type(spec) == "table" then return spec end
    end
    local specs = StatusSpecs()
    local selected = M.gfStatusIconSelection or "roleIcon"
    for i = 1, #specs do
        if specs[i].value == selected then return specs[i] end
    end
    return specs[1]
end
local function StatusSpecIsText(spec)
    if spec and spec.isText == true then return true end
    local value = spec and spec.value
    return value == "statusText" or value == "statusGhostText"
        or value == "statusAFKText" or value == "statusAFKTimer" or value == "statusDNDText"
end
--- Sample subgroup label, formatted by the live raid-group formatter so the
--- preview cannot drift from what the frame actually prints.
local PREVIEW_RAID_GROUP = 3
local function PreviewRaidGroupText(style)
    local runtime = MSUF and MSUF.UFStatusRuntime
    local format = runtime and runtime.RaidGroupText
    if type(format) == "function" then return format(style, PREVIEW_RAID_GROUP) end
    if style == "BRACKET" then return "[" .. PREVIEW_RAID_GROUP .. "]" end
    if style == "NONE" then return tostring(PREVIEW_RAID_GROUP) end
    return "(" .. PREVIEW_RAID_GROUP .. ")"
end
local function StatusText(spec, runtimeCfg, conf)
    local value = spec and spec.value
    if value == "statusGhostText" then return "GHOST" end
    if value == "statusAFKText" then return "AFK" end
    if value == "statusAFKTimer" then return "5m" end
    if value == "statusDNDText" then return "DND" end
    if value == "showGroupNumber" then
        return PreviewRaidGroupText((runtimeCfg and runtimeCfg.style)
            or (conf and spec.style and conf[spec.style]) or "PAREN")
    end
    return "DEAD"
end
local function StatusLabel(spec)
    local value = spec and spec.value
    if value == "roleIcon" then return "Role" end
    if value == "leaderIcon" then return "Leader" end
    if value == "assistIcon" then return "Assist" end
    if value == "raidMarker" then return "Marker" end
    if value == "readyCheckIcon" then return "Ready" end
    if value == "summonIcon" then return "Summon" end
    if value == "resurrectIcon" then return "Rez" end
    if value == "pvpIcon" then return "PvP" end
    if value == "phaseIcon" then return "Phase" end
    if value == "statusText" then return "Dead Text" end
    if value == "statusGhostText" then return "Ghost Text" end
    if value == "statusAFKText" then return "AFK Text" end
    if value == "statusAFKTimer" then return "AFK Timer" end
    if value == "statusDNDText" then return "DND Text" end
    if value == "showGroupNumber" then return "Group #" end
    return (spec and spec.text) or "Status"
end
local function StatusPreviewMode()
    local gf = MSUF and MSUF.GF
    if gf and type(gf.GetStatusPreviewMode) == "function" then
        local mode = gf.GetStatusPreviewMode()
        if mode == "all" then return "all" end
    end
    return M.gfStatusPreviewMode == "all" and "all" or "current"
end
local function StatusSpecEnabled(conf, spec)
    if not spec then return false end
    conf = conf or {}
    return conf[spec.enabled] ~= false
end
local function StatusSpecInMode(spec, selectedSpec)
    -- Entries with no slot in the Status Icons dropdown can never be the
    -- selected spec, so they must not be gated behind that selection.
    if spec and spec.alwaysInMode == true then return true end
    if StatusPreviewMode() == "all" then return true end
    local selected = selectedSpec and selectedSpec.value or M.gfStatusIconSelection or "roleIcon"
    return spec and spec.value == selected
end
local GFTextFocus = (M.GroupPreviewTextFocus and M.GroupPreviewTextFocus.Install and M.GroupPreviewTextFocus.Install({
    CurrentScope = CurrentScope,
    Conf = Conf,
    min = min,
    max = max,
})) or {}
local CurrentTextKind = GFTextFocus.CurrentTextKind or function() return "name" end
local TextOffsetKeys = GFTextFocus.TextOffsetKeys or function() return "nameOffsetX", "nameOffsetY" end
local TextLabel = GFTextFocus.TextLabel or function() return "Name Text" end
local TextMovesTogether = GFTextFocus.TextMovesTogether or F.True
local SetTextMoveTogether = GFTextFocus.SetTextMoveTogether or F.Noop
local PlaceHandleAroundRegions = GFTextFocus.PlaceHandleAroundRegions or F.False
local NormalizeTextFocusKind = GFTextFocus.NormalizeTextFocusKind or F.Identity
local NormalizeTextFocusSlot = GFTextFocus.NormalizeTextFocusSlot or F.Identity
local ApplyTextFocus = GFTextFocus.ApplyTextFocus or F.Noop
local function SpellPlacedForHandle(handle, conf)
    local item = handle and handle._cfgSpellItem
    if type(item) ~= "table" then return nil end
    local specKey, auraName = item.specKey, item.auraName
    local specs = conf and conf.spellIndicators and conf.spellIndicators.specs
    local cfg = specKey and auraName and type(specs) == "table"
        and type(specs[specKey]) == "table" and specs[specKey][auraName] or nil
    if type(cfg) == "table" and type(cfg.placed) == "table" then return cfg.placed end
    if type(handle._msufSpellIndicatorPlaced) == "table" then return handle._msufSpellIndicatorPlaced end
    return nil
end
local function HandleOffsets(handle)
    if not handle then return nil end
    local conf = Conf(CurrentScope()) or {}
    if handle._cfgGroup then
        local auras = conf.auras or {}
        local cfg = auras[handle._cfgGroup] or {}
        if handle._cfgTrackedBuff then
            return cfg.trackedAnchor or "TOPLEFT", tonumber(cfg.trackedX) or 0, tonumber(cfg.trackedY) or 0
        end
        return cfg.anchor, tonumber(cfg.x) or 0, tonumber(cfg.y) or 0
    elseif handle._cfgStatus then
        local spec = handle._statusSpec or CurrentStatusSpec()
        if not spec then return nil end
        return conf[spec.anchor] or spec.defaultAnchor, tonumber(conf[spec.x]) or 0, tonumber(conf[spec.y]) or 0
    elseif handle._cfgSpell then
        -- Dynamic preview handles own an exact spec+aura identity. Never let
        -- their coordinates fall back to whichever spell the menu happened
        -- to select previously.
        local cfg
        if handle._cfgSpellItem then
            cfg = SpellPlacedForHandle(handle, conf) or {}
        else
            cfg = CurrentSpellPlaced(CurrentScope()) or {}
        end
        return cfg.anchor, tonumber(cfg.x) or 0, tonumber(cfg.y) or 0
    elseif handle._cfgDispelSymbol then
        return "DISPEL", tonumber(conf.dispelSymbolX) or 0, tonumber(conf.dispelSymbolY) or 0
    elseif handle._cfgPortrait then
        return "PORTRAIT", tonumber(conf.portraitOffsetX) or 0, tonumber(conf.portraitOffsetY) or 0
    elseif handle._cfgPower then
        -- Fixed runtime anchor (TOP -> frame BOTTOM); only the offsets move.
        return "TOP", tonumber(conf.detachedPowerBarOffsetX) or 0, tonumber(conf.detachedPowerBarOffsetY) or -4
    elseif handle._cfgText then
        local kind = handle._cfgTextKind or CurrentTextKind()
        local slot = handle._cfgTextSlot
        local xKey, yKey = TextOffsetKeys(kind, slot)
        return (kind == "name" and (conf.nameAnchor or "LEFT") or TextLabel(kind, slot)), tonumber(conf[xKey]) or 0, tonumber(conf[yKey]) or 0
    end
    return nil
end
--- The hint line is a message surface, nothing else. Selected element, offsets
--- and actions live in the selection bar, the full control list behind the ?
--- button, so the text no longer changes shape per selection.
local function GroupPreviewDefaultHint()
    local base = Tr("drag to move - Tab picks the next element - ? lists every control")
    local remaining = PreviewHelpers.PreviewMoveHintRemaining and PreviewHelpers.PreviewMoveHintRemaining() or 0
    if remaining > 0 then
        return string.format("|cffff4d3f%s|r   %s",
            string.format(Tr("Drag background (%dx)"), remaining), base)
    end
    return base
end
UpdateHint = function(box, handle)
    if not box then return end
    if M.PreviewSelectionBar then M.PreviewSelectionBar.Refresh(box) end
    if not box._hint then return end
    box._hint:SetText(GroupPreviewDefaultHint())
end
local NudgeStep = PreviewHelpers.NudgeStep or F.One
--- The selected element is user intent, but `_selectedHandle` is a live frame
--- pointer on a box whose lifecycle is suspend/resume: one shared native box
--- serves every Group preview page, and Group sections open on *other* pages, so
--- opening an element's settings suspends the box mid-click. Storing the
--- selection only as that pointer therefore destroyed the intent on every
--- suspend, and the selection bar resumed reading "No element selected" - no
--- X/Y, no axis pulse. Unit frames never showed it because their sections open
--- on the page their preview already sits on, so nothing suspends.
---
--- Suspend hands the key over, resume takes it back. Both halves are exact
--- inverses and neither knows anything about navigation.
local function SuspendSelection(box)
    local handle = box._selectedHandle
    if handle and handle._key ~= nil then box._msufGFSuspendedSelectionKey = handle._key end
    box._selectedHandle = nil
end
local function ResumeSelection(box)
    if box._msufGFSuspendedSelectionKey == nil then return nil end
    if box._selectedHandle then
        -- Only a *different* element retires the key. Suspending stops the drag
        -- first, which refreshes while the selection it is about to hand over is
        -- still live, so retiring on any live selection would drop the key one
        -- step before the resume could ever run.
        if box._selectedHandle._key ~= box._msufGFSuspendedSelectionKey then
            box._msufGFSuspendedSelectionKey = nil
        end
        return box._selectedHandle
    end
    -- Mid-transition the box is already invisible while its handles still carry
    -- their own Shown flag. Resuming there would spend the key on the page that
    -- is being torn down.
    if box.IsVisible and not box:IsVisible() then return nil end
    local handle = box._handles and box._handles[box._msufGFSuspendedSelectionKey]
    if not handle or handle._locked then return nil end
    if handle.IsVisible and not handle:IsVisible() then return nil end
    box._msufGFSuspendedSelectionKey = nil
    -- A plain re-select: the menu-state side effects of a real click (aura lane,
    -- status entry, text tab) were written when it was clicked, and the keyboard
    -- focus belongs to whatever the resumed page opened.
    box._selectedHandle = handle
    return handle
end
local function RefreshHandleSelection(box)
    if not box then return end
    local selected = box._selectedHandle
    local guidesOn = not (M.gfPreviewLayerVisible and M.gfPreviewLayerVisible.guides == false)
    if selected and selected.IsShown and not selected:IsShown() then
        selected = nil
        box._selectedHandle = nil
    end
    local resumed = ResumeSelection(box)
    if resumed then selected = resumed end
    if PreviewHelpers.RefreshSelectedLayerButtons then
        PreviewHelpers.RefreshSelectedLayerButtons(box, selected, "_layerButtons")
    end
    local handles = box._handleList or {}
    for i = 1, #handles do
        local handle = handles[i]
        if handle then
            local color = handle._color or HANDLE_FALLBACK_COLOR
            local isSelected = handle == selected
            local isHover = handle._hovering == true
            local isDrag = handle._dragging == true
            local visualState = (guidesOn and 1 or 0) + (isSelected and 2 or 0) + (isHover and 4 or 0)
                + (isDrag and 8 or 0) + (handle._locked and 16 or 0) + (handle._cfgText and 32 or 0)
            local r, g, b = color[1], color[2], color[3]
            if handle._msufGFSelectionVisualState ~= visualState
                or handle._msufGFSelectionVisualR ~= r
                or handle._msufGFSelectionVisualG ~= g
                or handle._msufGFSelectionVisualB ~= b then
                handle._msufGFSelectionVisualState = visualState
                handle._msufGFSelectionVisualR = r
                handle._msufGFSelectionVisualG = g
                handle._msufGFSelectionVisualB = b
                if handle._selectFill then handle._selectFill:SetColorTexture(r, g, b, guidesOn and (isDrag and 0.18 or (isHover and 0.14 or 0)) or 0) end
                if handle._selectBorder then
                    handle._selectBorder:SetShown(guidesOn and (isSelected or isHover))
                    handle._selectBorder:SetBackdropBorderColor(r, g, b, isSelected and 0.70 or 0.72)
                end
                if handle.SetBackdropBorderColor then
                    local borderAlpha = guidesOn and (isSelected and 0.70 or (isHover and 0.85 or (handle._locked and 0.55 or 0.95))) or 0
                    if handle._cfgText then borderAlpha = 0 end
                    handle:SetBackdropBorderColor(r, g, b, borderAlpha)
                end
                if handle.SetBackdropColor and not handle._cfgText then
                    local alpha = guidesOn and 0.42 or 0
                    handle:SetBackdropColor(r * 0.12, g * 0.12, b * 0.12, alpha)
                end
                if handle._cfgText and handle.SetBackdropColor then handle:SetBackdropColor(0, 0, 0, 0) end
                if handle._msuf2SettingsGear then handle._msuf2SettingsGear:SetShown(guidesOn and isSelected) end
            end
        end
    end
    UpdateHint(box, selected)
end
local Helpers = {
    CurrentScope = CurrentScope, Conf = Conf, PreviewScopeLabel = PreviewScopeLabel,
    SetTextMoveTogether = SetTextMoveTogether, CurrentTextKind = CurrentTextKind, TextOffsetKeys = TextOffsetKeys,
    NudgeStep = NudgeStep, StatusSpecs = StatusSpecs, TextLabel = TextLabel, PreviewFocusForPage = PreviewFocusForPage,
    MockPowerHeight = MockPowerHeight, HealPredAnchorMode = HealPredAnchorMode, HealPredictionEnabled = HealPredictionEnabled,
    SetOutlineShown = SetOutlineShown, LayoutOutline = LayoutOutline, TextMovesTogether = TextMovesTogether,
    PlaceHandleAroundRegions = PlaceHandleAroundRegions, NormalizeTextFocusKind = NormalizeTextFocusKind,
    NormalizeTextFocusSlot = NormalizeTextFocusSlot, ApplyTextFocus = ApplyTextFocus,
}
local NativeDeps = {
    M = M,
    MSUF = MSUF,
    T = T,
    WHITE8X8 = WHITE8X8,
    H = Helpers,
    Helpers = Helpers,
    OpenSection = OpenGFSection,
    LayerFont = LayerFont,
    LayerHeaderColor = LAYER_HEADER_COLOR,
    CreateZoomButton = GFZoomPan.CreateButton,
    TR = Tr,
    Tr = Tr,
    StepZoom = StepZoom,
    SetZoom = SetZoom,
    ResolveDefaultZoomLock = ResolveDefaultZoomLock,
    StartPan = StartPan,
    StopPan = StopPan,
    ZoomWheel = F.Noop,
    UpdateHint = UpdateHint,
    Round = Round,
    ResolveAnchor = ResolveAnchor,
    PointOffset = PointOffset,
    HandleOffset = HandleOffset,
    OffsetToConfig = OffsetToConfig,
    CurrentStatusSpec = CurrentStatusSpec,
    CurrentSpellInfo = CurrentSpellInfo,
    PreviewAllSpecSpellIcons = PreviewAllSpecSpellIcons,
    CurrentSpellConfig = CurrentSpellConfig,
    CurrentSpellPlaced = CurrentSpellPlaced,
    HandleText = HandleText,
    HandleOffsets = HandleOffsets,
    RefreshHandleSelection = RefreshHandleSelection,
    StatusLabel = StatusLabel,
    NAMES = GF_PREVIEW_NAMES,
    CLASSES = GF_PREVIEW_CLASSES,
    AURA_MOCK_ICON_IDS = GF_AURA_MOCK_ICON_IDS,
    MIN_W = GF_PREVIEW_MIN_W,
    MIN_H = GF_PREVIEW_MIN_H,
    ROLE = GF_PREVIEW_ROLE_DEFAULT,
    PreviewRole = PreviewRole,
    ANCHOR_FRAC = GF_PREVIEW_ANCHOR_FRAC,
    AUTO_ZOOM_MIN = Specs.AUTO_ZOOM_MIN or 0.75,
    AUTO_ZOOM_MAX = Specs.AUTO_ZOOM_MAX or 1.65,
    AUTO_ZOOM_STAGE_PAD_X = Specs.AUTO_ZOOM_STAGE_PAD_X or 48,
    AUTO_ZOOM_STAGE_PAD_Y = Specs.AUTO_ZOOM_STAGE_PAD_Y or 72,
    CompiledSpec = CompiledSpec,
    CompiledAuraLane = CompiledAuraLane,
    RuntimeStatusConfig = RuntimeStatusConfig,
    StatusSpecEnabled = StatusSpecEnabled,
    StatusSpecInMode = StatusSpecInMode,
    StatusSpecIsText = StatusSpecIsText,
    StatusText = StatusText,
    CurrentSpellTexture = CurrentSpellTexture,
    CurrentSpellColor = CurrentSpellColor,
    MockSpellTexture = MockSpellTexture,
    Int = Int,
    ScaleValue = ScaleValue,
    ClampZoom = ClampZoom,
    UpdateZoomControls = UpdateZoomControls,
    ConfigToOffset = ConfigToOffset,
    AuraGrowth = AuraGrowth,
    ApplyRounded = ApplyRounded,
    ApplyFrameBorder = MSUF.UFPreviewCore and MSUF.UFPreviewCore.ApplyFrameBorder,
    ApplyBoundsGuide = MSUF.UFPreviewCore and MSUF.UFPreviewCore.ApplyBoundsGuide,
    BaseEdgeColor = BaseEdgeColor,
    LayoutOutline = LayoutOutline,
    ClampLayer = ClampLayer,
    HealPredictionEnabled = HealPredictionEnabled,
    HealPredAnchorMode = HealPredAnchorMode,
    MockPowerHeight = MockPowerHeight,
    ClassColor = ClassColor,
    HealthColor = HealthColor,
    ResolveStatusbarTexture = ResolvePreviewStatusbarTexture,
}
local function CreateNativeGFPreview(parent, ctx, onOpen)
    local R = ShallowCopy(NativeDeps) or {}
    local H, T, M = R.Helpers, R.T, R.M
    local width = (ctx.width or 720) - 28
    local layerW = 104
    local box = CreateFrame("Frame", nil, parent, T.Template())
    local previewControls = {}
    local runtimePageContext = { key = ctx and ctx.key }
    local function RegisterPreviewControl(widget, semanticPath, label, kind, classification, extra)
        if not widget then return widget end
        if widget._msuf2GroupPreviewControlOwner ~= box then
            widget._msuf2GroupPreviewControlOwner = box
            previewControls[#previewControls + 1] = widget
        end
        widget._msuf2GroupPreviewSemanticPath = semanticPath
        widget._msuf2GroupPreviewLabel = label
        widget._msuf2GroupPreviewKind = kind
        widget._msuf2GroupPreviewClassification = classification
        widget._msuf2GroupPreviewExtra = extra
        return RegisterGroupPreviewControl(widget, semanticPath, label, kind, classification, extra)
    end
    box._msuf2RegisterGroupPreviewControl = RegisterPreviewControl
    function box:RegisterRuntimeControlsForPage(pageKey)
        local page = M.GroupPage
        if not (page and type(page.RegisterControl) == "function") then return false end
        runtimePageContext.key = pageKey
        for i = 1, #previewControls do
            local widget = previewControls[i]
            page.RegisterControl(widget, runtimePageContext,
                "preview." .. tostring(widget._msuf2GroupPreviewSemanticPath),
                widget._msuf2GroupPreviewLabel,
                widget._msuf2GroupPreviewKind,
                widget._msuf2GroupPreviewClassification,
                widget._msuf2GroupPreviewExtra)
        end
        return true
    end
    local chrome
    if PreviewHelpers.ApplyPreviewChrome then
        chrome = PreviewHelpers.ApplyPreviewChrome(box, "outer", T, function(frame, bg, border)
            ApplyGroupPreviewFlatBackdrop(frame, R.WHITE8X8, bg, border)
        end)
    else
        chrome = { title = T.colors.title or T.colors.text, layerHeader = T.colors.muted }
        ApplyGroupPreviewFlatBackdrop(box, R.WHITE8X8, T.colors.panel or T.colors.panel2, T.colors.borderSoft or T.colors.border)
    end
    box:SetSize(width, 358)
    box._msufStaticH = 358
    box.ApplyPinnedPreviewPresentation = function(self, pinned, opts)
        if pinned then
            if PreviewHelpers.SwitchCompactZoomMode then PreviewHelpers.SwitchCompactZoomMode(self, false, 1.50) end
            SetGroupPreviewToolsShown(self, true)
            LayoutGroupPreviewHeaderControls(self, false)
            if self._title then self._title:Show() end
            if self._hint then self._hint:Show() end
            if self._msuf2LayersButton then self._msuf2LayersButton:Hide() end
        end
        ApplyGroupPinnedPresentation(self, pinned, opts, layerW)
        if not pinned and self._msuf2CompactPreview then ApplyGroupCompactPresentation(self, true, layerW) end
    end
    box.ApplyCompactPreviewPresentation = function(self, compact)
        ApplyGroupCompactPresentation(self, compact, layerW)
    end
    if parent and parent.GetFrameLevel and box.SetFrameLevel then box:SetFrameLevel((parent:GetFrameLevel() or 0) + 2) end
    local title = T.Font(box, "GameFontNormal", "", chrome.title or T.colors.title or T.colors.text)
    title:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -8)
    title:SetText(string.format((M.Tr and M.Tr("%s - %s")) or "%s - %s", (M.Tr and M.Tr("Group Frame Preview")) or "Group Frame Preview", H.PreviewScopeLabel(H.CurrentScope())))
    box._title = title
    local hint = T.Font(box, "GameFontDisableSmall", "", T.colors.muted)
    hint:SetPoint("LEFT", title, "RIGHT", 12, 0)
    box._hint = hint
    -- The stage is re-anchored against the selection bar by
    -- ApplyDockedPreviewLayout once the layer rail exists.
    local stage = CreateFrame("Frame", nil, box, T.Template())
    stage:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -30)
    stage:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -12, 12)
    stage._msuf2PreviewCanvasUnderlay = box
    if PreviewHelpers.ApplyPreviewChrome then
        PreviewHelpers.ApplyPreviewChrome(stage, "canvas", T, function(frame, bg, border)
            ApplyGroupPreviewFlatBackdrop(frame, R.WHITE8X8, bg, border)
        end)
    else
        ApplyGroupPreviewFlatBackdrop(stage, R.WHITE8X8, { 0.020, 0.039, 0.071, 0.92 }, T.colors.borderSoft)
    end
    if stage.SetClipsChildren then stage:SetClipsChildren(true) end
    stage:EnableMouse(true)
    stage:EnableMouseWheel(true)
    if stage.SetPropagateMouseWheel then stage:SetPropagateMouseWheel(false) end
    box._stage = stage
    PreviewHelpers.BuildZoomBar(box, stage, {
        template = T.Template(),
        texture = R.WHITE8X8,
        T = T,
        themeReadout = true,
        fieldPrefix = "_",
        wheelField = "_zoomWheel",
        CreateZoomButton = R.CreateZoomButton,
        Tr = R.Tr,
        StepZoom = R.StepZoom,
        SetZoom = R.SetZoom,
        StartPan = R.StartPan,
        StopPan = R.StopPan,
        fitReason = "GROUP_PREVIEW_ZOOM_FIT",
        oneReason = "GROUP_PREVIEW_ZOOM_1TO1",
        lockButton = true,
        defaultLocked = true,
        lockReason = "GROUP_PREVIEW_ZOOM_LOCK",
        unlockReason = "GROUP_PREVIEW_ZOOM_UNLOCK",
    })
    box._msuf2ZoomCommand = box._msuf2ZoomCommand
        or (PreviewHelpers.BuildZoomCommand and PreviewHelpers.BuildZoomCommand(box, GFZoomPan, "GROUP_PREVIEW_ASSISTANT_ZOOM"))
    RegisterPreviewControl(box._zoomBar, "zoom.surface", "Group Preview Zoom", "slider", "ephemeral", {
        help = "Sets the Group preview zoom percentage; Fit and 1:1 remain available as exact actions.",
        command = box._msuf2ZoomCommand,
    })
    local zoomControls = {
        { "_zoomOutButton", "zoom.out", "Zoom out" },
        { "_zoomFitButton", "zoom.fit", "Fit preview" },
        { "_zoomOneButton", "zoom.one_to_one", "Pixel preview" },
        { "_zoomInButton", "zoom.in", "Zoom in" },
        { "_zoomHelpButton", "zoom.help", "Preview controls help" },
        { "zoomLockButton", "zoom.lock", "Lock preview zoom" },
    }
    for i = 1, #zoomControls do
        local info = zoomControls[i]
        RegisterPreviewControl(box[info[1]], info[2], info[3], "button", "ephemeral")
    end
    if PreviewHelpers.EnsurePreviewControlsHint then
        local controlsHint = PreviewHelpers.EnsurePreviewControlsHint(box, stage, { M = M, T = T, Tr = R.Tr })
        RegisterPreviewControl(controlsHint and controlsHint._close, "hint.dismiss", "Dismiss preview tip", "button", "ephemeral")
    end
    R.ZoomWheel = box._zoomWheel or R.ZoomWheel
    CreatePreviewAnimationButton(box, RegisterPreviewControl)
    CreatePreviewRoleButton(box, RegisterPreviewControl)
    local bounds = CreateFrame("Frame", nil, stage, T.Template())
    bounds:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    bounds:SetBackdropColor(0, 0, 0, 0)
    -- Bounds mark a measurement, not a problem; cyan matches the Unit preview.
    bounds:SetBackdropBorderColor(0.25, 0.75, 0.88, 0.92)
    box._bounds = bounds
    local layers = CreateFrame("Frame", nil, box, T.Template())
    local layerColors = T.colors or {}
    if PreviewHelpers.ApplyPreviewChrome then
        PreviewHelpers.ApplyPreviewChrome(layers, "sidebar", T, function(frame, bg, border)
            ApplyGroupPreviewFlatBackdrop(frame, R.WHITE8X8, bg, border)
        end)
    else
        ApplyGroupPreviewFlatBackdrop(layers, R.WHITE8X8, layerColors.coreShadow or layerColors.panel, layerColors.borderSoft)
    end
    -- Layer chips flow along the bottom edge instead of holding a fixed column,
    -- so the stage keeps the full card width. Same treatment as the Unit preview.
    layers:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 12, 12)
    layers:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -12, 12)
    layers:SetHeight(30)
    box._layers = layers
    local layersTitle = R.LayerFont(layers, "LAYERS", chrome.layerHeader or (T.colors and T.colors.muted) or R.LayerHeaderColor)
    layersTitle:SetPoint("LEFT", layers, "LEFT", 10, 0)
    box._msuf2LayerRailHeader = layersTitle
    local layerDefaults = {
        guides = true,
        -- The configured frame outline is rendered independently. Bounds is
        -- only the optional cyan measurement guide and therefore starts off.
        bounds = false,
        power = true,
        portrait = true,
        buff = true,
        trackedBuff = true,
        debuff = true,
        external = true,
        status = true,
        si = true,
        auraText = true,
        text = true,
        dispelOverlay = true,
        dispelSymbol = true,
    }
    if type(M.gfPreviewLayerVisible) ~= "table" then M.gfPreviewLayerVisible = {} end
    for key, value in pairs(layerDefaults) do
        if M.gfPreviewLayerVisible[key] == nil then M.gfPreviewLayerVisible[key] = value end
    end
    local layerVisibility = M.gfPreviewLayerVisible
    local layerDefs = {
        { "Guides", { 0.42, 0.72, 1.00 }, "layout", "guides" },
        -- Follow the Unit preview's semantic order wherever the two previews
        -- share concepts: guides, text, portrait, resources, content, status,
        -- then the optional bounds measurement at the far right.
        { "Text", { 0.70, 0.90, 1.00 }, "text", "text" },
        { "Portrait", { 0.90, 0.42, 1.00 }, "portrait", "portrait" },
        { "Power", { 0.30, 0.62, 0.98 }, "power", "power" },
        { "Buffs", { 0.20, 0.90, 0.35 }, "buffs", "buff" },
        { "Tracked", { 0.42, 0.68, 1.00 }, "buffs", "trackedBuff" },
        { "Debuffs", { 0.90, 0.20, 0.22 }, "debuffs", "debuff" },
        { "External", { 0.30, 0.72, 1.00 }, "externals", "external" },
        { "Spells", { 0.86, 0.50, 1.00 }, "si", "si" },
        { "CD/Stack", { 1.00, 0.82, 0.28 }, "textcolor", "auraText" },
        { "Status", { 0.95, 0.78, 0.22 }, "sicons", "status" },
        { "Dispel Overlay", { 0.25, 0.72, 1.00 }, "dispel", "dispelOverlay" },
        -- Own section, not the overlay's: a chip whose layer is off in settings
        -- turns into a shortcut to the setting that enables it, so it has to name
        -- the accordion that actually owns it.
        { "Dispel Symbol", { 0.34, 0.84, 1.00 }, "dispelSymbol", "dispelSymbol" },
        { "Bounds", { 0.25, 0.75, 0.88 }, "layout", "bounds" },
    }
    box._layerButtons = {}
    box.layerVisibility = layerVisibility
    local activeLayerText = layerColors.pillTextActive or layerColors.text or { 0.92, 0.96, 1.00, 1.00 }
    local mutedLayerText = layerColors.muted or { 0.62, 0.70, 0.82, 0.90 }
    local disabledLayerText = layerColors.dim or { 0.36, 0.46, 0.60, 0.82 }
    local groupLayerButtonOpts = {
        Tr = R.Tr,
        layout = "chip",
        height = 20,
        rowHeight = 20,
        topOffset = 23,
        showOffText = false,
        quiet = true,
        quietBase = chrome.rowBase,
        quietHover = chrome.rowHover,
        textOn = { activeLayerText[1], activeLayerText[2], activeLayerText[3], 1.00 },
        textOff = { mutedLayerText[1], mutedLayerText[2], mutedLayerText[3], 0.72 },
        textDisabled = { disabledLayerText[1], disabledLayerText[2], disabledLayerText[3], 0.64 },
        IsAvailable = function(owner, key)
            return not (owner and owner._layerAvailable and owner._layerAvailable[key] == false)
        end,
        IsOn = function(owner, key)
            if owner and owner._layerAvailable and owner._layerAvailable[key] == false then return false end
            if M.gfPreviewSoloLayer ~= nil then return M.gfPreviewSoloLayer == key end
            return layerVisibility[key] ~= false
        end,
        IsSelected = function(owner, key) return owner and owner._msuf2SelectedPreviewLayerKey == key end,
        OnClick = function(self, owner)
            if owner and owner._layerAvailable and owner._layerAvailable[self.key] == false then
                if GameTooltip then GameTooltip:Hide() end
                OpenGFSection(self._sectionKey)
                return
            end
            if IsShiftKeyDown and IsShiftKeyDown() then
                M.gfPreviewSoloLayer = (M.gfPreviewSoloLayer == self.key) and nil or self.key
            else
                M.gfPreviewSoloLayer = nil
                layerVisibility[self.key] = layerVisibility[self.key] == false
            end
            for j = 1, #(owner._layerButtons or {}) do owner._layerButtons[j]:Refresh() end
            if owner.RequestRefresh then owner:RequestRefresh("GROUP_PREVIEW_LAYER")
            elseif owner.Refresh then owner:Refresh("GROUP_PREVIEW_LAYER") end
        end,
        OnEnter = function(self, owner, available, on, tr)
            if not owner._hint then return end
            local label = self.fs and self.fs:GetText() or tr("Layer")
            if not available then
                owner._hint:SetText(string.format(tr("%s is off in settings. Click to open its options."), label))
                return
            end
            local solo = M.gfPreviewSoloLayer == self.key
            local action = solo and "Shift-click clears solo layer" or (on and "click to hide - Shift-click to solo" or "click to show")
            owner._hint:SetText(label .. " - " .. tr(action))
        end,
        OnLeave = function(_, owner) R.UpdateHint(owner, owner._selectedHandle) end,
    }
    for i = 1, #layerDefs do
        local def = layerDefs[i]
        local btn = PreviewHelpers.CreateLayerButton(layers, box, {
            key = def[4], label = def[1], color = def[2],
        }, i, layerW, groupLayerButtonOpts)
        btn._sectionKey, btn._layerKey = def[3], def[4]
        btn._label, btn._stripe, btn._bg, btn._off = btn.fs, btn.bar, btn.bg, btn.off
        M.AddTooltip(btn, "Layer disabled", "Click to open the setting that enables this layer.", {
            hook = true,
            enabled = function(self) return self._layerAvailable == false end,
        })
        btn._msuf2CommandAction = {
            kind = "toggle",
            historyMode = "none",
            get = function()
                if btn._layerAvailable == false then return false end
                if M.gfPreviewSoloLayer ~= nil then return M.gfPreviewSoloLayer == btn._layerKey end
                return layerVisibility[btn._layerKey] ~= false
            end,
            set = function(enabled)
                if btn._layerAvailable == false then return false end
                enabled = enabled == true
                M.gfPreviewSoloLayer = nil
                layerVisibility[btn._layerKey] = enabled
                if box.RequestRefresh then box:RequestRefresh("GROUP_PREVIEW_ASSISTANT_LAYER")
                elseif box.Refresh then box:Refresh() end
                return (layerVisibility[btn._layerKey] ~= false) == enabled
            end,
        }
        RegisterPreviewControl(btn, "layer." .. tostring(def[4]), def[1] .. " preview layer", "button", "ephemeral")
        if def[4] == "portrait" then btn:Hide() end
        box._layerButtons[#box._layerButtons + 1] = btn
    end
    box.LayoutLayerRail = function(self, railWidth)
        if not PreviewHelpers.FlowLayerChips then return 30 end
        railWidth = tonumber(railWidth) or (self._layers and self._layers.GetWidth and self._layers:GetWidth()) or 0
        local headerWidth = 0
        local header = self._msuf2LayerRailHeader
        if header and header:IsShown() then
            headerWidth = ((header.GetStringWidth and header:GetStringWidth()) or 44) + 18
        end
        return PreviewHelpers.FlowLayerChips(self._layers, self._layerButtons, {
            width = railWidth - headerWidth,
            padX = 10 + headerWidth,
            rowHeight = 20,
        })
    end
    -- One layout path for the docked and floating states: chips on the bottom
    -- edge, selection bar above them, stage takes whatever is left.
    box.ApplyDockedPreviewLayout = function(self, bottomInset)
        bottomInset = tonumber(bottomInset) or 12
        local rail, selection, surface = self._layers, self._msuf2SelectionBar, self._stage
        if not surface then return end
        if rail then
            rail:ClearAllPoints()
            rail:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 12, bottomInset)
            rail:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -12, bottomInset)
            if rail.SetFrameLevel and surface.GetFrameLevel then
                rail:SetFrameLevel((surface:GetFrameLevel() or 1) + 1)
            end
            if self._msuf2LayerRailHeader then self._msuf2LayerRailHeader:Show() end
            rail:Show()
            self:LayoutLayerRail((self.GetWidth and self:GetWidth() or 0) - 24)
        end
        surface:ClearAllPoints()
        surface:SetPoint("TOPLEFT", self, "TOPLEFT", 12, -30)
        if selection and rail then
            selection:ClearAllPoints()
            selection:SetPoint("BOTTOMLEFT", rail, "TOPLEFT", 0, 6)
            selection:SetPoint("BOTTOMRIGHT", rail, "TOPRIGHT", 0, 6)
            selection:Show()
            surface:SetPoint("BOTTOMRIGHT", selection, "TOPRIGHT", 0, 6)
        else
            surface:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -12, bottomInset)
        end
        if self._msuf2ElementPicker then self._msuf2ElementPicker:Show() end
    end
    local mock = CreateFrame("Frame", nil, stage, T.Template())
    mock:SetBackdrop({ bgFile = R.WHITE8X8 })
    mock:SetBackdropColor(0.08, 0.08, 0.09, 0.92)
    mock:SetBackdropBorderColor(0.0, 0.0, 0.0, 0)
    mock:EnableMouse(true)
    mock:EnableMouseWheel(true)
    if mock.SetPropagateMouseWheel then mock:SetPropagateMouseWheel(false) end
    mock:SetScript("OnMouseWheel", R.ZoomWheel)
    mock:SetScript("OnMouseDown", function(_, button) R.StartPan(stage, box, button, true) end)
    mock:SetScript("OnMouseUp", function()
        if stage._msufGFPreviewPanning then R.StopPan(stage) end
    end)
    -- Stands in for the live frame's MSUFSpec.scope: the shared preview border
    -- helper puts group mocks in the group foreground band (Layers.BorderOffset).
    mock._msufPreviewGroupScope = true
    box._mock = mock
    box.mock, mock.bounds = mock, bounds
    function box:PanExact(dx, dy)
        if type(M.IsConfigCombatLocked) == "function" and M.IsConfigCombatLocked() then return false, "combat-locked" end
        if self._msufGFNativePreviewDisposed then return false, "preview-disposed" end
        if not (self.IsShown and self:IsShown() and (not self.IsVisible or self:IsVisible())) then return false, "preview-not-visible" end
        if (self._stage and self._stage._msufGFPreviewPanning) or (self._dragFrame and self._dragFrame._handle) then return false, "preview-busy" end
        if type(GFZoomPan.NudgePan) ~= "function" then return false, "pan-api-unavailable" end
        return GFZoomPan.NudgePan(self, dx, dy)
    end
    box._msuf2PanCommand = box._msuf2PanCommand or (PreviewHelpers.BuildPanCommand and PreviewHelpers.BuildPanCommand(
        box, GFZoomPan,
        function(dx, dy)
            if not (M.GroupPreview and type(M.GroupPreview.Pan) == "function") then return false end
            return M.GroupPreview.Pan(dx, dy)
        end,
        { previewSurface = "group" }
    ))
    RegisterPreviewControl(mock, "canvas", "Group preview canvas", "canvas", "ephemeral", {
        help = "Pans this exact Group preview canvas by an explicit X/Y delta.",
        command = box._msuf2PanCommand,
    })
    mock._health = CreateFrame("StatusBar", nil, mock)
    mock._health:SetMinMaxValues(0, 1)
    mock._health:SetValue(0.72)
    mock._healthBg = mock._health:CreateTexture(nil, "BACKGROUND")
    mock._healthBg:SetAllPoints()
    mock._tempMaxHealth = CreateFrame("StatusBar", nil, mock)
    mock._tempMaxHealth:SetMinMaxValues(0, 1)
    mock._tempMaxHealth:SetValue(0.20)
    mock._tempMaxHealth:SetStatusBarTexture(R.WHITE8X8)
    mock._tempMaxHealth:SetStatusBarColor(0.70, 0.10, 0.10, 1)
    mock._tempMaxHealthBg = mock._tempMaxHealth:CreateTexture(nil, "BACKGROUND")
    mock._tempMaxHealthBg:SetColorTexture(0, 0, 0, 0.65)
    local tempMaxFill = mock._tempMaxHealth.GetStatusBarTexture
        and mock._tempMaxHealth:GetStatusBarTexture()
    mock._tempMaxHealthBg:SetAllPoints(tempMaxFill or mock._tempMaxHealth)
    mock._healPred = CreateFrame("StatusBar", nil, mock)
    mock._healPred:SetMinMaxValues(0, 1)
    mock._healPred:SetValue(0.12)
    mock._healPred:SetStatusBarTexture(R.WHITE8X8)
    mock._healPred:SetStatusBarColor(0, 1, 0.4, 0.45)
    mock._absorb = CreateFrame("StatusBar", nil, mock)
    mock._absorb:SetMinMaxValues(0, 1)
    mock._absorb:SetValue(1)
    mock._absorb:SetStatusBarTexture(R.WHITE8X8)
    mock._absorb:SetStatusBarColor(0.55, 0.70, 1, 0.55)
    mock._healAbsorb = CreateFrame("StatusBar", nil, mock._health)
    mock._healAbsorb:SetMinMaxValues(0, 1)
    mock._healAbsorb:SetValue(0.07)
    mock._healAbsorb:SetStatusBarTexture(R.WHITE8X8)
    mock._healAbsorb:SetStatusBarColor(0.70, 0, 0, 1)
    if mock._health.SetClipsChildren then mock._health:SetClipsChildren(true) end
    if mock._healAbsorb.SetFrameLevel and mock._health.GetFrameLevel then mock._healAbsorb:SetFrameLevel((mock._health:GetFrameLevel() or 1) + 3) end
    mock._power = CreateFrame("StatusBar", nil, mock)
    mock._power:SetMinMaxValues(0, 1)
    mock._power:SetValue(1)
    mock._power:SetStatusBarColor(0.13, 0.27, 0.67, 1)
    mock._powerBg = mock._power:CreateTexture(nil, "BACKGROUND")
    mock._powerBg:SetAllPoints()
    mock._nameTextLayer = CreateFrame("Frame", nil, mock)
    mock._nameTextLayer:SetAllPoints(mock)
    mock._healthTextLayer = CreateFrame("Frame", nil, mock)
    mock._healthTextLayer:SetAllPoints(mock)
    mock._powerTextLayer = CreateFrame("Frame", nil, mock)
    mock._powerTextLayer:SetAllPoints(mock)
    mock._nameFS = T.Font(mock._nameTextLayer, "GameFontHighlightSmall", "", T.colors.text)
    mock._hpFS = T.Font(mock._healthTextLayer, "GameFontHighlight", "", T.colors.text)
    mock._powerFS = T.Font(mock._powerTextLayer, "GameFontHighlightSmall", "", T.colors.text)
    mock._hpLeftFS = T.Font(mock._healthTextLayer, "GameFontHighlight", "", T.colors.text)
    mock._hpCenterFS = T.Font(mock._healthTextLayer, "GameFontHighlight", "", T.colors.text)
    mock._hpRightFS = mock._hpFS
    mock._powerLeftFS = T.Font(mock._powerTextLayer, "GameFontHighlightSmall", "", T.colors.text)
    mock._powerCenterFS = mock._powerFS
    mock._powerRightFS = T.Font(mock._powerTextLayer, "GameFontHighlightSmall", "", T.colors.text)
    box._selectedHandle = nil
    R.RegisterPreviewControl = RegisterPreviewControl
    local handleBundle = (M.GroupPreviewHandles and M.GroupPreviewHandles.Install and M.GroupPreviewHandles.Install(box, R)) or {}
    local buffHandle = handleBundle.buffHandle
    local trackedBuffHandle = handleBundle.trackedBuffHandle
    local debuffHandle = handleBundle.debuffHandle
    local externalHandle = handleBundle.externalHandle
    local powerBarHandle = handleBundle.powerBarHandle
    local portraitHandle = handleBundle.portraitHandle
    local dispelSymbolHandle = handleBundle.dispelSymbolHandle
    local statusHandles = handleBundle.statusHandles or {}
    local spellHandle = handleBundle.spellHandle
    local SelectHandle = handleBundle.SelectHandle or function() end
    local NudgeHandlePosition = handleBundle.NudgeHandlePosition or function() end
    local AddIconPool = handleBundle.AddIconPool or function() end
    local StopHandleDrag = handleBundle.StopHandleDrag or function()
        if box._dragFrame then
            box._dragFrame:SetScript("OnUpdate", nil)
            box._dragFrame._handle = nil
            box._dragFrame:Hide()
        end
    end
    local function ReadGroupSelectionCoordinates(owner, handle)
        -- Name X/Y are anchor-local offsets. Reading the rendered handle
        -- center here makes X=0 mean "center the glyphs in the frame", which
        -- silently rewrites LEFT/RIGHT/TOP anchors into an apparent CENTER.
        -- Keep every other Group handle in the shared rendered-coordinate
        -- space; only Name mirrors the stored offset contract used by its
        -- anchor control and renderer.
        if handle and handle._cfgText == true and handle._cfgTextKind == "name" then
            local _, rawX, rawY = R.HandleOffsets(handle)
            return R.Round(tonumber(rawX) or 0), R.Round(tonumber(rawY) or 0)
        end
        local selection = M.PreviewSelectionBar
        local x, y
        if selection and type(selection.ReadRenderedCoordinates) == "function" then
            x, y = selection.ReadRenderedCoordinates(handle, owner and owner._mock,
                owner and (owner._mockScale or (owner._mock and owner._mock._previewScale)) or 1)
        end
        if x == nil or y == nil then
            local _, rawX, rawY = R.HandleOffsets(handle)
            x, y = rawX, rawY
        end
        return R.Round(tonumber(x) or 0), R.Round(tonumber(y) or 0)
    end
    local function WriteGroupStoredOffsets(owner, handle, x, y)
        local _, curX, curY = R.HandleOffsets(handle)
        local dx = (tonumber(x) or 0) - (tonumber(curX) or 0)
        local dy = (tonumber(y) or 0) - (tonumber(curY) or 0)
        if dx == 0 and dy == 0 then return true end
        if type(owner.NudgeHandleExact) ~= "function" then return false end
        return owner:NudgeHandleExact(handle._key, dx, dy) == true
    end
    local function WriteGroupSelectionCoordinates(owner, handle, x, y)
        if handle and handle._cfgText == true and handle._cfgTextKind == "name" then
            return WriteGroupStoredOffsets(owner, handle, x, y)
        end
        local curX, curY = ReadGroupSelectionCoordinates(owner, handle)
        local dx = (tonumber(x) or curX) - curX
        local dy = (tonumber(y) or curY) - curY
        if dx == 0 and dy == 0 then return true end
        if type(owner.NudgeHandleExact) ~= "function" then return false end
        return owner:NudgeHandleExact(handle._key, dx, dy) == true
    end
    local function ResetGroupSelectionOffsets(owner, handle)
        local defaultX, defaultY = 0, handle and handle._cfgPower and -4 or 0
        return WriteGroupStoredOffsets(owner, handle, defaultX, defaultY)
    end
    if M.PreviewSelectionBar then
        M.PreviewSelectionBar.Create(box, {
            Tr = R.Tr,
            Theme = function() return T end,
            ApplyBackdrop = function(frame, bg, border)
                ApplyGroupPreviewFlatBackdrop(frame, R.WHITE8X8, bg, border)
            end,
            Round = R.Round,
            HandleList = function(owner) return owner._handleList end,
            HandleLabel = R.HandleText,
            -- Locked handles are shown but not movable, so they are not a
            -- selectable row or a Tab stop either.
            IsPlaced = function(handle)
                if handle._locked then return false end
                return not (handle.IsShown and not handle:IsShown())
            end,
            ReadOffsets = ReadGroupSelectionCoordinates,
            -- NudgeHandleExact remains the audited storage writer. Name uses
            -- its anchor-local stored offsets; every other handle translates
            -- exact entry from the shared rendered coordinate space.
            WriteOffsets = WriteGroupSelectionCoordinates,
            ResetOffsets = ResetGroupSelectionOffsets,
            NudgeDelta = function(owner, dx, dy)
                local handle = owner._selectedHandle
                if not (handle and type(owner.NudgeHandleExact) == "function") then return false end
                return owner:NudgeHandleExact(handle._key, dx, dy) == true
            end,
            -- Mirrors the fallbacks ReadHandlePositionExact already treats as
            -- each handle type's default.
            DefaultOffsets = function(_, handle)
                if handle._cfgPower then return 0, -4 end
                return 0, 0
            end,
            OpenSettings = function(_, handle)
                local open = M.GroupPreview and M.GroupPreview.OpenSection
                if not (handle._sectionKey and type(open) == "function") then return false end
                open(handle._sectionKey)
                return true
            end,
            SelectHandle = function(_, handle) return SelectHandle(handle) end,
            UpdateHint = function(owner, handle) return UpdateHint(owner, handle) end,
        })
        M.PreviewSelectionBar.CreatePicker(box, stage)
        local registerControl = box._msuf2RegisterGroupPreviewControl or RegisterGroupPreviewControl
        registerControl(box._msuf2ElementPicker, "element_picker", "Group Preview Element Picker", "button", "ephemeral")
        local selectionBar = box._msuf2SelectionBar
        if selectionBar then
            local selectionAPI = M.PreviewSelectionBar
            selectionAPI.BindExactOffsetSearchTarget(selectionBar.editX, box, "portrait")
            selectionAPI.BindExactOffsetSearchTarget(selectionBar.editY, box, "portrait")
            registerControl(selectionBar.editX, "selection.portrait_offset_x", "Party Portrait X Offset",
                "textinput", "setting", {
                    assistantDisposition = "dynamic",
                    assistantDispositionReason = "The shared Preview X field is pinned to the Party Portrait handle for this exact Assistant route.",
                    assistantSettingKeys = { "gf_party.portraitOffsetX" },
                    command = selectionAPI.BuildExactOffsetCommand(box, "portrait", "x", {
                        previewSurface = "group", previewScope = "party",
                    }),
                })
            registerControl(selectionBar.editY, "selection.portrait_offset_y", "Party Portrait Y Offset",
                "textinput", "setting", {
                    assistantDisposition = "dynamic",
                    assistantDispositionReason = "The shared Preview Y field is pinned to the Party Portrait handle for this exact Assistant route.",
                    assistantSettingKeys = { "gf_party.portraitOffsetY" },
                    command = selectionAPI.BuildExactOffsetCommand(box, "portrait", "y", {
                        previewSurface = "group", previewScope = "party",
                    }),
                })
            registerControl(selectionBar.resetButton, "selection.reset", "Reset selected preview element offset", "button", "ephemeral")
            registerControl(selectionBar.openButton, "selection.open_settings", "Open selected preview element settings", "button", "ephemeral")
        end
    end
    box.OnPreviewCanvasMoved = function(_, button)
        if PreviewHelpers.NotePreviewCanvasMoved then PreviewHelpers.NotePreviewCanvasMoved(button) end
    end
    if box.ApplyDockedPreviewLayout then box:ApplyDockedPreviewLayout(12) end
    if M.GroupPreviewRender and M.GroupPreviewRender.Install then
        local renderDeps = ShallowCopy(R) or {}
        renderDeps.width, renderDeps.mock = width, mock
        renderDeps.buffHandle, renderDeps.debuffHandle = buffHandle, debuffHandle
        renderDeps.trackedBuffHandle = trackedBuffHandle
        renderDeps.externalHandle = externalHandle
        renderDeps.powerBarHandle = powerBarHandle
        renderDeps.portraitHandle = portraitHandle
        renderDeps.dispelSymbolHandle = dispelSymbolHandle
        renderDeps.statusHandles, renderDeps.spellHandle = statusHandles, spellHandle
        renderDeps.statusSpecs = H.StatusSpecs and H.StatusSpecs()
        renderDeps.SelectHandle = SelectHandle
        renderDeps.NudgeHandlePosition = NudgeHandlePosition
        renderDeps.AddIconPool = AddIconPool
        M.GroupPreviewRender.Install(box, ctx, renderDeps)
    end
    function box:CancelPendingRefresh()
        self._msufGFRefreshSerial = (tonumber(self._msufGFRefreshSerial) or 0) + 1
        self._msufGFRefreshQueued = nil
        self._msufGFRefreshReason = nil
    end
    function box:SetTextDragRefreshSuppressed(active)
        if active then
            self._msufGFTextDragActive = true
            if self.CancelPendingRefresh then self:CancelPendingRefresh() end
        else
            self._msufGFTextDragActive = nil
        end
    end
    function box:RequestRefresh(reason)
        if PreviewAnimationInCombat() then
            self._msufGFRefreshAfterCombat = reason or self._msufGFRefreshAfterCombat or true
            if self.CancelPendingRefresh then self:CancelPendingRefresh() end
            return
        end
        self._msufGFRefreshAfterCombat = nil
        local hostShown = self._msufGFPreviewHostShown
        if type(hostShown) == "function" and not hostShown() then
            self:ReleaseRuntimePreview()
            return
        end
        if self._msufGFTextDragActive then
            self._msufGFRefreshReason = reason or self._msufGFRefreshReason
            return
        end
        if self._msufGFRefreshQueued then
            self._msufGFRefreshReason = reason or self._msufGFRefreshReason
            return
        end
        self._msufGFRefreshSerial = (tonumber(self._msufGFRefreshSerial) or 0) + 1
        local serial = self._msufGFRefreshSerial
        self._msufGFRefreshQueued = true
        self._msufGFRefreshReason = reason
        local function RunRefresh()
            if not self then return end
            if serial ~= self._msufGFRefreshSerial then return end
            self._msufGFRefreshQueued = nil
            if PreviewAnimationInCombat() then
                self._msufGFRefreshAfterCombat = self._msufGFRefreshReason or self._msufGFRefreshAfterCombat or true
                return
            end
            if self._msufGFNativePreviewDisposed then return end
            if self.IsShown and not self:IsShown() then return end
            local currentHostShown = self._msufGFPreviewHostShown
            if type(currentHostShown) == "function" and not currentHostShown() then
                self:ReleaseRuntimePreview()
                return
            end
            if self.Refresh then self:Refresh(self._msufGFRefreshReason) end
            self._msufGFRefreshReason = nil
        end
        -- Live-mirror events (player regen ticks out of combat) coalesce on a
        -- wider window so value streams cost at most five renders per second.
        ScheduleNativePreviewRefresh(self, RunRefresh,
            reason == "GROUP_PREVIEW_LIVE_STATE" and 0.2 or nil)
    end
    function box:ReleaseRuntimePreview()
        self._msufGFRefreshSerial = (tonumber(self._msufGFRefreshSerial) or 0) + 1
        self._msufGFRefreshQueued = nil
        self._msufGFRefreshReason = nil
        if self.SuspendSpellPreviewEffects then self:SuspendSpellPreviewEffects() end
        StopHandleDrag(self and self._selectedHandle)
        -- This is the one place the runtime preview is suspended - page switches,
        -- the fixed-preview expander and window hides all funnel through here,
        -- repeatedly and in any order - so it is also the one place the selection
        -- is handed over rather than destroyed.
        SuspendSelection(self)
        if PreviewHelpers.ReleaseKeyboardCapture then
            PreviewHelpers.ReleaseKeyboardCapture(self)
        elseif self.SetPropagateKeyboardInput then
            self:SetPropagateKeyboardInput(true)
        end
    end
    -- Live-state driver: the mock cell mirrors the player's current values,
    -- so refresh when they change while the menu preview is visible. Zero
    -- combat overhead by construction: PLAYER_REGEN_DISABLED drops every
    -- listener for the whole fight and only the re-arm signal stays.
    local GF_LIVE_STATE_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_NAME_UPDATE" }
    local liveStateDriver = CreateFrame("Frame")
    box._msufGFLiveStateDriver = liveStateDriver
    function box:ArmLiveStateDriver()
        local driver = self._msufGFLiveStateDriver
        if not driver then return end
        driver:UnregisterAllEvents()
        if PreviewAnimationInCombat() then
            driver._msufLiveArmed = false
            driver:RegisterEvent("PLAYER_REGEN_ENABLED")
            return
        end
        driver._msufLiveArmed = true
        driver:RegisterEvent("PLAYER_REGEN_DISABLED")
        if driver.RegisterUnitEvent then
            for i = 1, #GF_LIVE_STATE_EVENTS do
                driver:RegisterUnitEvent(GF_LIVE_STATE_EVENTS[i], "player")
            end
        end
    end
    function box:ReleaseLiveStateDriver()
        local driver = self._msufGFLiveStateDriver
        if not driver then return end
        driver:UnregisterAllEvents()
        driver._msufLiveArmed = false
    end
    liveStateDriver:SetScript("OnEvent", function(driver, event)
        if event == "PLAYER_REGEN_DISABLED" then
            driver:UnregisterAllEvents()
            driver._msufLiveArmed = false
            driver:RegisterEvent("PLAYER_REGEN_ENABLED")
            return
        end
        if not (box.IsShown and box:IsShown()) then
            driver:UnregisterAllEvents()
            driver._msufLiveArmed = false
            return
        end
        if event == "PLAYER_REGEN_ENABLED" then
            box:ArmLiveStateDriver()
            return
        end
        if PreviewAnimationInCombat() then return end
        box:RequestRefresh("GROUP_PREVIEW_LIVE_STATE")
    end)
    box:HookScript("OnShow", function(self)
        if self.RegisterEvent then
            self:RegisterEvent("PLAYER_REGEN_DISABLED")
            self:RegisterEvent("PLAYER_REGEN_ENABLED")
        end
        if self.ArmLiveStateDriver then self:ArmLiveStateDriver() end
        if PreviewAnimationActive(self) then StartPreviewAnimationDriver(self) end
        RefreshPreviewAnimationButton(self)
        self:RequestRefresh("GROUP_PREVIEW_SHOW")
    end)
    box:HookScript("OnHide", function(self)
        StopPreviewAnimationDriver(self)
        if self.UnregisterEvent then
            self:UnregisterEvent("PLAYER_REGEN_DISABLED")
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        end
        if self.ReleaseLiveStateDriver then self:ReleaseLiveStateDriver() end
        self:ReleaseRuntimePreview()
    end)
    box:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_REGEN_DISABLED" then
            KillPreviewAnimationForCombat(self)
            if self.SuspendSpellPreviewEffects then self:SuspendSpellPreviewEffects() end
            self._msufGFRefreshAfterCombat = self._msufGFRefreshReason or self._msufGFRefreshAfterCombat or true
            if self.CancelPendingRefresh then self:CancelPendingRefresh() end
        elseif event == "PLAYER_REGEN_ENABLED" and self._msufGFRefreshAfterCombat then
            local reason = self._msufGFRefreshAfterCombat
            self._msufGFRefreshAfterCombat = nil
            self:RequestRefresh(type(reason) == "string" and reason or "GROUP_PREVIEW_REGEN")
        end
    end)
    box:HookScript("OnSizeChanged", function(self, width, height)
        if not self:IsShown() then return end
        width = floor((tonumber(width) or self:GetWidth() or 0) + 0.5)
        height = floor((tonumber(height) or self:GetHeight() or 0) + 0.5)
        if self._msufGFRefreshWidth == width and self._msufGFRefreshHeight == height then return end
        self._msufGFRefreshWidth = width
        self._msufGFRefreshHeight = height
        self:RequestRefresh("GROUP_PREVIEW_SIZE")
    end)
    return box
end
M.GroupPreview = M.GroupPreview or {}
M.GroupPreview.CreateNative = CreateNativeGFPreview
M.GroupPreview.OpenSection = OpenGFSection
function M.FocusGFPreviewTextSlot(kind, slot, active)
    local previews = M._gfNativePreviews
    if not previews then return false end
    local focused = false
    for i = 1, #previews do
        local box = previews[i]
        if box and not box._msufGFNativePreviewDisposed and box.FocusTextSlot and box.IsShown and box:IsShown() and (not box.IsVisible or box:IsVisible()) then focused = box:FocusTextSlot(kind, slot, active) or focused end
    end
    return focused
end
