local _, MSUF = ...
MSUF = MSUF or {}
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", "Menu2/GroupPreview_Native")
local ResolveIconTexturePath = MSUF.Require("MSUF_ResolveIconTexturePath", "Menu2/GroupPreview_Native")
local ExportPublic = MSUF.ExportPublic
local PublicGlobals = MSUF.PublicGlobals
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local C_Timer = M.MenuTimer or C_Timer

-- Native group preview renderer.
-- Draws the Menu2 party/raid preview using lightweight mock data and page settings. It should
-- mirror runtime layout decisions but never create secure headers or mutate live group frames.
local T = M.Theme
local PreviewHelpers = M.PreviewHelpers or {}
local Specs = M.GroupPreviewSpecs or {}
local GFZoomPan = M.GroupPreviewZoomPan or {}

local Fallbacks = M.Fallbacks or {}
local floor = math.floor
local GROUP_PREVIEW_REFRESH_DELAY = 0.05
local WHITE8X8 = Specs.WHITE8X8 or "Interface\\Buttons\\WHITE8X8"
local function RegisterGroupPreviewControl(widget, semanticPath, label, kind, classification, extra)
    local page = M.GroupPage
    if page and page.RegisterControl then
        page.RegisterControl(widget, { key = M.activeKey }, "preview." .. tostring(semanticPath), label, kind, classification, extra)
    end
    return widget
end
local LAYER_HEADER_COLOR = { 0.45, 0.50, 0.62, 0.80 }
local LAYER_TEXT_ON = { 0.76, 0.80, 0.90, 0.95 }
local HANDLE_FALLBACK_COLOR = { 0.70, 0.80, 1.00 }
local GF_PREVIEW_ROLE_DEFAULT = Specs.ROLE or "HEALER"
local SECTION_PAGE, PAGE_FOCUS, GF_PREVIEW_ANCHOR_FRAC = Specs.SECTION_PAGE or {}, Specs.PAGE_FOCUS or {}, Specs.ANCHOR_FRAC or {}
local GF_AURA_GROWTH_TABLE, GF_STATUS_RUNTIME_KEYS = Specs.AURA_GROWTH_TABLE or {}, Specs.STATUS_RUNTIME_KEYS or {}
-- The threat text's compiled group entry (Classic Era, TBC and WoW Forever only).
-- Added here rather than in the specs file, which stays a plain Retail copy.
GF_STATUS_RUNTIME_KEYS.threatText = "threat"
if not GF_AURA_GROWTH_TABLE.RIGHTDOWN then GF_AURA_GROWTH_TABLE.RIGHTDOWN = { px = 1, py = 0, sx = 0, sy = -1 } end
local function ShallowCopy(src)
    if type(src) ~= "table" then return nil end
    local out = {}
    for k, v in pairs(src) do
        out[k] = v
    end
    return out
end
local function TrText(text)
    return (M.Tr and M.Tr(text)) or text
end
local function ScheduleNativePreviewRefresh(fn, delay)
    if C_Timer and C_Timer.After then
        C_Timer.After(tonumber(delay) or GROUP_PREVIEW_REFRESH_DELAY, fn)
    else
        fn()
    end
end
local function LayerFont(parent, text, color)
    color = color or LAYER_TEXT_ON
    local fs = PixelLayoutRegion(parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"))
    fs:SetText(TrText(text or ""))
    if fs.SetTextColor then fs:SetTextColor(color[1], color[2], color[3], color[4] or 1) end
    if T and T.StyleFontString then T.StyleFontString(fs, color, 0) end
    return fs
end
local function GroupPage()
    M.GroupPage = M.GroupPage or {}
    return M.GroupPage
end
local function CurrentScope()
    local gp = GroupPage()
    if gp.CurrentScope then return gp.CurrentScope() end
    local scope = M.gfScope or "party"
    return M.NormalizeGroupScope and M.NormalizeGroupScope(scope) or scope
end
local GF_PREVIEW_ROLE_LABELS = {
    TANK = "Tank",
    HEALER = "Healer",
    DAMAGER = "DPS",
}
local GF_PREVIEW_NEXT_ROLE = { TANK = "HEALER", HEALER = "DAMAGER", DAMAGER = "TANK" }
local function NormalizePreviewRole(role)
    if GF_PREVIEW_ROLE_LABELS[role] then return role end
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
    return GF_PREVIEW_NEXT_ROLE[PreviewRole(kind)] or GF_PREVIEW_ROLE_DEFAULT
end
local function Conf(kind)
    local gp = GroupPage()
    if gp.Conf then return gp.Conf(kind) end
    return {}
end
-- The native menu sample uses the same role/geometry overlay as live bindings.
local previewSpecSlots = {}
local function CompiledSpec(kind)
    local gf = MSUF.GF
    if gf and gf.CompileSpec then
        kind = kind or CurrentScope()
        local base = gf.CompileSpec(kind, nil, nil)
        if type(base) ~= "table" then return base end
        local metrics = previewSpecSlots[kind]
        if not metrics or metrics.base ~= base then
            metrics = {}
            previewSpecSlots[kind] = metrics
        end
        metrics.base, metrics.conf = base, Conf(kind)
        local spec = gf.ComputeFrameOverlay(kind, PreviewRole(kind), metrics)
        spec._msufMenu2PreviewRuntime = true
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
-- The aura lane each aura section drives; the EM2 focus request names the same lane.
local SECTION_AURA_LANE = { buffs = "buff", debuffs = "debuff", externals = "externals" }
local SCOPE_PAGE_KEY = { raid = "gf_raid", mythicraid = "gf_mythicraid" }
local function OpenGFSection(sectionKey)
    M.gfPreviewFocus = sectionKey
    local pageKey = PageForGFSection(sectionKey)
    if not (pageKey and M.SelectPage) then return false end
    local lane = SECTION_AURA_LANE[sectionKey]
    local scope = CurrentScope()
    local previousAuraLane, previousAuraTool, requestedAuraLane
    if M.SetMenuStateValue then
        M.SetMenuStateValue("gfScope", scope)
        if pageKey == "gf_auras" then
            M.SetMenuStateValue("auraStyleGFScope", scope == "mythicraid" and "raid" or scope)
            if lane then
                M.gfAuraLaneSelection = M.gfAuraLaneSelection or {}
                previousAuraLane = M.gfAuraLaneSelection[scope] or "buff"
                requestedAuraLane = lane
                M.gfAuraLaneSelection[scope] = lane
                M.gfAuraToolSelection = M.gfAuraToolSelection or {}
                local tools = M.gfAuraToolSelection[scope]
                if type(tools) ~= "table" then
                    tools = {}
                    M.gfAuraToolSelection[scope] = tools
                end
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
        key = SCOPE_PAGE_KEY[scope] or "gf_party",
        component = sectionKey,
        lane = lane,
        pageKey = pageKey,
        sectionId = lane and "auras" or sectionKey,
        source = "group-preview",
        explicit = true,
        changedAt = GetTime and GetTime() or 0,
    })
    -- Group Auras builds its lane-specific controls from gfAuraLaneSelection.
    -- Selecting another preview lane must rebuild any cached Group Auras
    -- page, whether it is active or hidden; refreshers still target the old lane.
    if requestedAuraLane and (requestedAuraLane ~= previousAuraLane or previousAuraTool ~= "layout")
        and M.InvalidatePage then
        M.InvalidatePage(pageKey)
    end
    return M.SelectPage(pageKey) ~= false
end
local function PreviewAnimationInCombat()
    return (InCombatLockdown and InCombatLockdown()) or PublicGlobals.MSUF_InCombat == true
end
local function PreviewAnimationActive(box)
    return box and box._animationEnabled == true
end
local function SetPillText(btn, text)
    if btn.fs and btn.fs.SetText then
        btn.fs:SetText(text)
    elseif btn.SetText then
        btn:SetText(text)
    end
end
local function RefreshPreviewAnimationButton(box)
    local btn = box and box._previewAnimationButton
    if not btn then return end
    local active = PreviewAnimationActive(box)
    -- The button plays an animation loop; it does not switch the preview into a
    -- combat state. Label it after what it does, matching the Unit preview.
    SetPillText(btn, TrText(active and "Stop" or "Animate"))
    if btn.MSUF2RefreshPreviewPill then
        btn:MSUF2RefreshPreviewPill(active)
    elseif btn.SetActive then
        btn:SetActive(active)
    end
end
--- One animation frame: the light tick advances the last scene; only without
--- one (first frame, scope switch, combat, text drag) the full refresh runs.
local function RefreshPreviewAnimationFrame(box)
    if not box then return end
    if box.RefreshAnimation and box:RefreshAnimation() == true then return end
    if box.Refresh then
        box:Refresh("GROUP_PREVIEW_ANIMATE")
    elseif box.RequestRefresh then
        box:RequestRefresh("GROUP_PREVIEW_ANIMATE")
    end
end
local function ClearPreviewAnimationState(box)
    box._msufGFMenuPreviewAnimState = nil
    box._msufGFMenuPreviewAuraStates = nil
end
local function PreviewAnimationCombatHint(box)
    if box._hint then box._hint:SetText(TrText("Preview animation pauses during combat.")) end
end
local StartPreviewAnimationDriver, StopPreviewAnimationDriver, KillPreviewAnimationForCombat, SetPreviewAnimationEnabled =
    M.PreviewHelpers.CreateAnimationStarter(PreviewAnimationInCombat, RefreshPreviewAnimationFrame,
        RefreshPreviewAnimationButton, ClearPreviewAnimationState, PreviewAnimationCombatHint, RefreshPreviewAnimationFrame)
local function TogglePreviewAnimation(box)
    SetPreviewAnimationEnabled(box, not PreviewAnimationActive(box), "GROUP_PREVIEW_COMBAT_ANIMATE_TOGGLE")
end
local function PreviewAllSpecSpellIcons(kind)
    local state = M.gfPreviewAllSpecSpellIcons
    return type(state) == "table" and state[kind or CurrentScope()] == true
end
-- The Animate and Role pills share one frame recipe: backdrop, centred label, pill style, level above the stage.
local function NewPreviewPill(parent, width)
    local template = (T and T.Template and T.Template()) or "BackdropTemplate"
    local btn = PixelLayoutRegion(CreateFrame("Button", nil, parent, template))
    btn:SetSize(width, 22)
    if btn.SetBackdrop then PixelLayoutRegion(btn, "SetBackdrop", { bgFile = WHITE8X8, edgeFile = WHITE8X8, edgeSize = 1 }) end
    btn.fs = PixelLayoutRegion(btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"))
    btn.fs:SetPoint("CENTER", btn, "CENTER", 0, 0)
    btn.fs:SetJustifyH("CENTER")
    if btn.fs.SetJustifyV then btn.fs:SetJustifyV("MIDDLE") end
    if T and T.StyleFontString then T.StyleFontString(btn.fs, T.colors and T.colors.text or LAYER_TEXT_ON, 0) end
    return btn
end
local function StylePreviewPill(btn, parent)
    if PreviewHelpers.StylePreviewPillButton then PreviewHelpers.StylePreviewPillButton(btn, T, { fontField = "fs" }) end
    if btn.SetFrameLevel and parent.GetFrameLevel then btn:SetFrameLevel((parent:GetFrameLevel() or 0) + 85) end
end
local function CreatePreviewAnimationButton(box, registerControl)
    if not box or box._previewAnimationButton then return end
    local parent = box._stage or box
    local btn = NewPreviewPill(parent, 74)
    btn._preview = box
    btn._msuf2AllowCombatClick = true
    if box._zoomBar then
        btn:SetPoint("RIGHT", box._zoomBar, "LEFT", -6, 0)
    elseif box._stage then
        btn:SetPoint("TOPRIGHT", box._stage, "TOPRIGHT", -154, -6)
    else
        btn:SetPoint("TOPRIGHT", box, "TOPRIGHT", -104, -34)
    end
    StylePreviewPill(btn, parent)
    PreviewHelpers.BindPreviewAnimationButton(btn, box, TogglePreviewAnimation, PreviewAnimationActive,
        PreviewAnimationInCombat, SetPreviewAnimationEnabled, "GROUP_PREVIEW_SEARCH_ANIMATION")
    local register = registerControl or RegisterGroupPreviewControl
    register(btn, "combat_animation", "Group Preview Animation", "button", "ephemeral")
    if M.AddTooltip then
        M.AddTooltip(btn, "Animate Preview",
            "Animates health, power, prediction bars, text values, aura timers, and combat-state indicators in this preview only. Pauses during combat.",
            { hook = true })
    end
    box._previewAnimationButton = btn
    box.RefreshAnimationButton = RefreshPreviewAnimationButton
    RefreshPreviewAnimationButton(box)
end
local function RefreshPreviewRoleButton(box, kind)
    local btn = box and box._previewRoleButton
    if not btn then return end
    SetPillText(btn, TrText(GF_PREVIEW_ROLE_LABELS[PreviewRole(kind)]))
end
local function CreatePreviewRoleButton(box, registerControl)
    if not box or box._previewRoleButton then return end
    local parent = box._stage or box
    local btn = NewPreviewPill(parent, 92)
    if box._previewAnimationButton then
        btn:SetPoint("RIGHT", box._previewAnimationButton, "LEFT", -6, 0)
    elseif box._zoomBar then
        btn:SetPoint("RIGHT", box._zoomBar, "LEFT", -86, 0)
    end
    StylePreviewPill(btn, parent)
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
local function ApplyGroupPreviewFlatBackdrop(frame, bg, border)
    if not (frame and frame.SetBackdrop) then return end
    PixelLayoutRegion(frame, "SetBackdrop", { bgFile = WHITE8X8, edgeFile = WHITE8X8, edgeSize = 1 })
    bg = bg or { 0, 0, 0, 1 }
    frame:SetBackdropColor(bg[1] or 0, bg[2] or 0, bg[3] or 0, bg[4] or 1)
    if border and frame.SetBackdropBorderColor then
        frame:SetBackdropBorderColor(border[1] or 0, border[2] or 0, border[3] or 0, border[4] or 1)
    end
end
-- Role chrome from the shared helper; the flat colours apply only when it is missing.
local function ApplyGroupChrome(frame, role, bg, border)
    if PreviewHelpers.ApplyPreviewChrome then
        return PreviewHelpers.ApplyPreviewChrome(frame, role, T, ApplyGroupPreviewFlatBackdrop)
    end
    ApplyGroupPreviewFlatBackdrop(frame, bg, border)
end
local function EnsureGroupLayersButton(box)
    if box._msuf2LayersButton then return box._msuf2LayersButton end
    local btn = T.Button(box, "", 132, 20)
    btn:SetText(TrText("Preview Layers") .. " v", true)
    if T.CenterButtonLabel then T.CenterButtonLabel(btn) end
    btn:SetScript("OnClick", function()
        if box._layers then box._layers:SetShown(not box._layers:IsShown()) end
    end)
    if M.AddTooltip then M.AddTooltip(btn, "Preview Layers", "Toggle the preview layer list.", { hook = true }) end
    local registerControl = box._msuf2RegisterGroupPreviewControl or RegisterGroupPreviewControl
    registerControl(btn, "layers.popover", "Group Preview Layers", "button", "ephemeral")
    box._msuf2LayersButton = btn
    return btn
end
local COMPACT_TOOL_FIELDS = { "_zoomBar", "_previewAnimationButton", "_previewRoleButton" }
local function SetGroupPreviewToolsShown(box, shown)
    if not box then return end
    local controlsHint = box._msuf2PreviewControlsHint
    local method = shown and "Show" or "Hide"
    if not shown and box._msuf2CompactToolsHidden ~= true then
        box._msuf2CompactControlsHintWasShown = controlsHint and controlsHint.IsShown and controlsHint:IsShown() or false
    end
    box._msuf2CompactToolsHidden = not shown or nil
    for i = 1, #COMPACT_TOOL_FIELDS do
        local tool = box[COMPACT_TOOL_FIELDS[i]]
        if tool then tool[method](tool) end
    end
    if controlsHint and (not shown or box._msuf2CompactControlsHintWasShown) then controlsHint[method](controlsHint) end
end
-- The Theme button translates "Preview Layers" itself; the compact label is
-- composed, so it is translated first and set as translated.
local function LayoutGroupPreviewHeaderControls(box, compact)
    PreviewHelpers.LayoutCompactLayersButton(box, compact, M.Tr)
end
-- The full-size header: title, hint and tool buttons back, layers button back in its docked place.
local function ShowExpandedHeader(box)
    if box._title then box._title:Show() end
    if box._hint then box._hint:Show() end
    SetGroupPreviewToolsShown(box, true)
    LayoutGroupPreviewHeaderControls(box, false)
end
local function ApplyGroupCompactPresentation(box, compact)
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
            -- column; the caption is redundant behind a "Preview Layers" button.
            local popoverWidth = 268
            box._msuf2LayerPopoverWidth = popoverWidth
            layers:SetWidth(popoverWidth)
            if box._msuf2LayerRailHeader then box._msuf2LayerRailHeader:Hide() end
            if box.LayoutLayerRail then box:LayoutLayerRail(popoverWidth) end
            if layers.SetFrameLevel and stage.GetFrameLevel then layers:SetFrameLevel((stage:GetFrameLevel() or 1) + 90) end
            layers:Hide()
        end
        layersBtn:Show()
        LayoutGroupPreviewHeaderControls(box, true)
        return
    end
    box._msuf2LayerPopoverWidth = nil
    ShowExpandedHeader(box)
    if M.PreviewSelectionBar then M.PreviewSelectionBar.SetShown(box, true) end
    if box.ApplyDockedPreviewLayout then box:ApplyDockedPreviewLayout(12) end
    if box._msuf2LayersButton then box._msuf2LayersButton:Hide() end
end
local SCOPE_LABELS = { raid = "Raid", mythicraid = "Mythic Raid" }
local function PreviewScopeLabel(kind)
    return SCOPE_LABELS[kind] or "Party"
end
local Tr = M.Tr
local ClassColor = MSUF.UF.Config.ClassColor
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
-- Lane key -> compiled key prefix, show flag and max-count key.
local COMPILED_LANES = {
    buff = { "buff", "showBuffs", "maxBuffs" },
    trackedBuff = { "trackedBuff", "showTrackedBuffs", "maxTrackedBuffs" },
    debuff = { "debuff", "showDebuffs", "maxDebuffs" },
    external = { "external", "showExternals", "maxExternals" },
}
-- Lane field, then the compiled key suffix that follows the lane prefix.
local COMPILED_LANE_FIELDS = {
    "perRow", "PerRow", "size", "IconSize", "spacing", "Spacing", "anchor", "Anchor",
    "x", "OffsetX", "y", "OffsetY", "layer", "Layer", "strata", "Strata",
    "showCooldownSwipe", "ShowCooldownSwipe", "cooldownSwipeReverse", "CooldownSwipeReverse",
    "showCooldown", "ShowCooldown", "showCooldownText", "ShowCooldown",
    "showStacks", "ShowStacks", "showTooltip", "ShowTooltip", "showDurationBar", "ShowDurationBar",
    "durationBarHeight", "DurationBarHeight", "durationBarDisplay", "DurationBarDisplay",
    "durationBarPosition", "DurationBarPosition", "durationBarDirection", "DurationBarDirection",
    "cooldownSize", "CooldownSize", "cooldownAnchor", "CooldownAnchor", "cooldownX", "CooldownX",
    "cooldownY", "CooldownY", "cooldownDecimalSeconds", "CooldownDecimalSeconds",
    "stackSize", "StackSize", "stackAnchor", "StackAnchor", "stackX", "StackX", "stackY", "StackY",
}
-- Each lane's full compiled keys are joined once here, so a repaint concatenates no strings.
for _, lane in pairs(COMPILED_LANES) do
    local prefix, keys = lane[1], {}
    for i = 1, #COMPILED_LANE_FIELDS, 2 do
        keys[(i + 1) / 2] = prefix .. COMPILED_LANE_FIELDS[i + 1]
    end
    lane.keys, lane.growthX, lane.growthY, lane.alphaKey = keys, prefix .. "GrowthX", prefix .. "GrowthY", prefix .. "Alpha"
end
local function CompiledAuraLane(auras, key, fallback, out)
    if type(auras) ~= "table" then return fallback or {} end
    local lane = COMPILED_LANES[key]
    if not lane then return fallback or {} end
    local keys = lane.keys
    -- A caller that keeps one table per lane passes it as out: the lane is
    -- rebuilt in place, so a preview repaint allocates no lane table.
    if out then wipe(out) else out = {} end
    out._compiled = true
    out.enabled = auras[lane[2]] == true
    out.max = auras[lane[3]]
    out.iconZoom = auras.iconZoom
    out.growth = GrowthFromCompiled(auras[lane.growthX], auras[lane.growthY], fallback and fallback.growth)
    for n = 1, #keys do
        out[COMPILED_LANE_FIELDS[2 * n - 1]] = auras[keys[n]]
    end
    out.dispelBorderMode = key == "debuff" and auras.debuffDispelBorderMode or nil
    out.showDispelBorder = key == "debuff" and auras.debuffShowDispelBorder or nil
    out.showDispelSymbol = key == "debuff" and auras.debuffShowDispelSymbol or nil
    local alpha = tonumber(auras[lane.alphaKey]) or 1
    out.alpha = alpha
    out.behindBar = alpha < 1
    return out
end
local STATUS_TEXT_SUBKEYS = { statusGhostText = "ghost", statusAFKText = "afk", statusAFKTimer = "afkTimer", statusDNDText = "dnd" }
local function RuntimeStatusConfig(status, spec)
    if type(status) ~= "table" or type(spec) ~= "table" then return nil end
    local value = spec.value
    local text = status.statusText
    if value == "statusText" then return text and text.dead or text end
    local sub = STATUS_TEXT_SUBKEYS[value]
    if sub then return text and text[sub] or nil end
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
    local tex
    if C_Spell and C_Spell.GetSpellTexture then tex = C_Spell.GetSpellTexture(spellId) end
    if not tex and GetSpellInfo then
        local _, _, icon = GetSpellInfo(spellId)
        tex = icon
    end
    if not tex then return "Interface\\Icons\\INV_Misc_QuestionMark" end
    tex = ResolveIconTexturePath(tex) or tex
    gfMockSpellTextureCache[spellId] = tex
    return tex
end
local function CurrentSpellInfo(kind)
    local gp = GroupPage()
    local gf = MSUF.GF
    local si = gf and gf.SpellIndicators
    local specKey = gp.EffectiveSpellSpec and gp.EffectiveSpellSpec(kind) or nil
    local auraName = gp.CurrentSpellAura and gp.CurrentSpellAura(kind) or nil
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
    if gp.CurrentSpellConfig then
        local cfg = gp.CurrentSpellConfig(kind, false)
        if type(cfg) == "table" then return cfg end
    end
    return nil
end
local function CurrentSpellPlaced(kind)
    local gp = GroupPage()
    if gp.PlacedConfig then
        local placed = gp.PlacedConfig(kind, false)
        if type(placed) == "table" then return placed end
    end
    local cfg = CurrentSpellConfig(kind)
    return type(cfg and cfg.placed) == "table" and cfg.placed or nil
end
local function CurrentSpellTexture(kind)
    local info, specKey, auraName = CurrentSpellInfo(kind)
    local gf = MSUF.GF
    local si = gf and gf.SpellIndicators
    if si and si.GetAuraIcon and specKey and auraName and auraName ~= "" then
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
local ConfigToOffset = ScaleValue -- the same maths without a minimum
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
-- Drag loops call these every update, so the anchor point maths stays inline.
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
    local gf = MSUF.GF
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
--- entry to that dropdown, the layer overview, or the Search ledgers.
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
    if gp.CurrentGFStatusSpec then
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
local STATUS_TEXT_VALUES = {
    statusText = true, statusGhostText = true, statusAFKText = true, statusAFKTimer = true, statusDNDText = true,
    levelText = true,
}
local function StatusSpecIsText(spec)
    return (spec and spec.isText == true) or STATUS_TEXT_VALUES[spec and spec.value] == true
end
--- Sample subgroup label, formatted by the live raid-group formatter so the
--- preview cannot drift from what the frame actually prints.
local PREVIEW_RAID_GROUP = 3
local function PreviewRaidGroupText(style)
    local runtime = MSUF.UFStatusRuntime
    local format = runtime and runtime.RaidGroupText
    if format then return format(style, PREVIEW_RAID_GROUP) end
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
    if value == "threatText" then return "85%" end
    if value == "levelText" then
        local level = UnitLevel and tonumber(UnitLevel("player")) or nil
        return tostring(level and level > 0 and level or 80)
    end
    if value == "showGroupNumber" then
        return PreviewRaidGroupText((runtimeCfg and runtimeCfg.style)
            or (conf and spec.style and conf[spec.style]) or "PAREN")
    end
    return "DEAD"
end
local STATUS_LABELS = {
    roleIcon = "Role", leaderIcon = "Leader", assistIcon = "Assist", raidMarker = "Marker", readyCheckIcon = "Ready",
    summonIcon = "Summon", resurrectIcon = "Rez", pvpIcon = "PvP", phaseIcon = "Phase", statusText = "Dead Text",
    statusGhostText = "Ghost Text", statusAFKText = "AFK Text", statusAFKTimer = "AFK Timer", statusDNDText = "DND Text",
    levelText = "Level Text", showGroupNumber = "Group #",
}
local function StatusLabel(spec)
    return STATUS_LABELS[spec and spec.value] or (spec and spec.text) or "Status"
end
local function StatusPreviewMode()
    local gf = MSUF.GF
    if gf and gf.GetStatusPreviewMode and gf.GetStatusPreviewMode() == "all" then return "all" end
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
})) or {}
local CurrentTextKind = GFTextFocus.CurrentTextKind
local TextOffsetKeys = GFTextFocus.TextOffsetKeys
local TextLabel = GFTextFocus.TextLabel
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
local function DefaultHandleOffsets(handle)
    if not handle then return 0, 0 end
    local gf, scope = MSUF.GF, CurrentScope()
    local source, xKey, yKey
    if handle._cfgGroup then
        local auras = gf.GetDefault(scope, "auras") or {}
        source = auras[handle._cfgGroup] or {}
        xKey, yKey = "x", "y"
        if handle._cfgTrackedBuff then xKey, yKey = "trackedX", "trackedY" end
    elseif handle._cfgStatus then
        local spec = handle._statusSpec or CurrentStatusSpec()
        if spec then xKey, yKey = spec.x, spec.y end
    elseif handle._cfgDispelSymbol then xKey, yKey = "dispelSymbolX", "dispelSymbolY"
    elseif handle._cfgPortrait then xKey, yKey = "portraitOffsetX", "portraitOffsetY"
    elseif handle._cfgPower then xKey, yKey = "detachedPowerBarOffsetX", "detachedPowerBarOffsetY"
    elseif handle._cfgText then
        xKey, yKey = TextOffsetKeys(handle._cfgTextKind or CurrentTextKind(), handle._cfgTextSlot)
    end
    if not xKey then return 0, 0 end
    if source then return tonumber(source[xKey]) or 0, tonumber(source[yKey]) or 0 end
    return tonumber(gf.GetDefault(scope, xKey)) or 0, tonumber(gf.GetDefault(scope, yKey)) or 0
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
local function UpdateHint(box)
    if not box then return end
    if M.PreviewSelectionBar then M.PreviewSelectionBar.Refresh(box) end
    if not box._hint then return end
    T.SetTranslatedText(box._hint, GroupPreviewDefaultHint())
end
if GFZoomPan.Configure then
    GFZoomPan.Configure({ T = T, TR = Tr, WHITE8X8 = WHITE8X8, UpdateHint = UpdateHint })
end
local NudgeStep = PreviewHelpers.NudgeStep or Fallbacks.One
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
    local guidesOn = M.gfPreviewLayerVisible and M.gfPreviewLayerVisible.guides == true
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
    UpdateHint(box)
end
local Helpers = {
    CurrentScope = CurrentScope, Conf = Conf, PreviewScopeLabel = PreviewScopeLabel,
    SetTextMoveTogether = GFTextFocus.SetTextMoveTogether or Fallbacks.Noop,
    CurrentTextKind = CurrentTextKind, TextOffsetKeys = TextOffsetKeys,
    NudgeStep = NudgeStep, StatusSpecs = StatusSpecs, TextLabel = TextLabel, PreviewFocusForPage = PreviewFocusForPage,
    MockPowerHeight = MockPowerHeight, TextMovesTogether = GFTextFocus.TextMovesTogether or Fallbacks.True,
    PlaceHandleAroundRegions = GFTextFocus.PlaceHandleAroundRegions or Fallbacks.False,
    NormalizeTextFocusKind = GFTextFocus.NormalizeTextFocusKind or Fallbacks.Identity,
    NormalizeTextFocusSlot = GFTextFocus.NormalizeTextFocusSlot or Fallbacks.Identity,
    ApplyTextFocus = GFTextFocus.ApplyTextFocus or Fallbacks.Noop,
}
local NativeDeps = {
    M = M,
    MSUF = MSUF,
    T = T,
    WHITE8X8 = WHITE8X8,
    H = Helpers,
    Helpers = Helpers,
    OpenSection = OpenGFSection,
    TR = Tr,
    ResolveDefaultZoomLock = GFZoomPan.ResolveDefaultLock or Fallbacks.Noop,
    StartPan = GFZoomPan.Start or Fallbacks.False,
    StopPan = GFZoomPan.Stop or Fallbacks.Noop,
    ZoomWheel = Fallbacks.Noop,
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
    NAMES = Specs.NAMES or {},
    CLASSES = Specs.CLASSES or {},
    AURA_MOCK_ICON_IDS = Specs.AURA_MOCK_ICON_IDS or {},
    MIN_W = Specs.MIN_W or 380,
    MIN_H = Specs.MIN_H or 130,
    ROLE = GF_PREVIEW_ROLE_DEFAULT,
    PreviewRole = PreviewRole,
    ANCHOR_FRAC = GF_PREVIEW_ANCHOR_FRAC,
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
    ClampZoom = GFZoomPan.Clamp,
    UpdateZoomControls = GFZoomPan.UpdateControls or Fallbacks.Noop,
    ConfigToOffset = ConfigToOffset,
    AuraGrowth = AuraGrowth,
    ApplyBoundsGuide = MSUF.UFPreviewCore and MSUF.UFPreviewCore.ApplyBoundsGuide,
    ClampLayer = ClampLayer,
    MockPowerHeight = MockPowerHeight,
    ClassColor = ClassColor,
}
-- The native preview installs in stages that share one per-call state table;
-- NativeBuild.Create runs them once, in order. Per-refresh work stays inside
-- the box methods and the render module exactly as before.
local NativeBuild = {}
function NativeBuild.Frame(parent, ctx)
    local Deps = ShallowCopy(NativeDeps) or {}
    local width = (ctx.width or 720) - 28
    local layerW = 104
    local box = PixelLayoutRegion(CreateFrame("Frame", nil, parent, T.Template()))
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
        if not (page and page.RegisterControl) then return false end
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
    local chrome = ApplyGroupChrome(box, "outer", T.colors.panel or T.colors.panel2, T.colors.borderSoft or T.colors.border)
        or { title = T.colors.title or T.colors.text, layerHeader = T.colors.muted }
    box:SetSize(width, 358)
    box._msufStaticH = 358
    box.ApplyPinnedPreviewPresentation = function(self, pinned)
        if pinned then
            if PreviewHelpers.SwitchCompactZoomMode then PreviewHelpers.SwitchCompactZoomMode(self, false, 1.50) end
            ShowExpandedHeader(self)
            if self._msuf2LayersButton then self._msuf2LayersButton:Hide() end
        end
        local shade, line = PreviewHelpers.EnsurePinnedHeader(self)
        if M.PreviewSelectionBar then M.PreviewSelectionBar.SetShown(self, true) end
        if self.ApplyDockedPreviewLayout then self:ApplyDockedPreviewLayout(12) end
        if self._footer then self._footer:SetShown(not pinned) end
        PreviewHelpers.PaintPinnedHeader(shade, line, T.colors or {}, pinned)
        UpdateHint(self)
        if not pinned and self._msuf2CompactPreview then ApplyGroupCompactPresentation(self, true) end
    end
    box.ApplyCompactPreviewPresentation = ApplyGroupCompactPresentation
    if parent and parent.GetFrameLevel and box.SetFrameLevel then box:SetFrameLevel((parent:GetFrameLevel() or 0) + 2) end
    local title = T.Font(box, "GameFontNormal", "", chrome.title or T.colors.title or T.colors.text)
    title:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -8)
    T.SetTranslatedText(title, string.format(TrText("%s - %s"), TrText("Group Frame Preview"), PreviewScopeLabel(CurrentScope())))
    box._title = title
    local hint = T.Font(box, "GameFontDisableSmall", "", T.colors.muted)
    hint:SetPoint("LEFT", title, "RIGHT", 12, 0)
    box._hint = hint
    return {
        ctx = ctx, R = Deps, width = width, layerW = layerW, box = box, chrome = chrome,
        RegisterPreviewControl = RegisterPreviewControl,
    }
end
function NativeBuild.Stage(state)
    local Deps, box, RegisterPreviewControl = state.R, state.box, state.RegisterPreviewControl
    -- The stage is re-anchored against the selection bar by
    -- ApplyDockedPreviewLayout once the layer rail exists.
    local stage = PixelLayoutRegion(CreateFrame("Frame", nil, box, T.Template()))
    stage:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -30)
    stage:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -12, 12)
    stage._msuf2PreviewCanvasUnderlay = box
    ApplyGroupChrome(stage, "canvas", { 0.020, 0.039, 0.071, 0.92 }, T.colors.borderSoft)
    if stage.SetClipsChildren then stage:SetClipsChildren(true) end
    stage:EnableMouse(true)
    stage:EnableMouseWheel(true)
    if stage.SetPropagateMouseWheel then stage:SetPropagateMouseWheel(false) end
    box._stage = stage
    PreviewHelpers.BuildZoomBar(box, stage, {
        template = T.Template(),
        texture = WHITE8X8,
        T = T,
        themeReadout = true,
        fieldPrefix = "_",
        wheelField = "_zoomWheel",
        CreateZoomButton = GFZoomPan.CreateButton,
        Tr = Tr,
        StepZoom = GFZoomPan.Step or Fallbacks.Noop,
        SetZoom = GFZoomPan.SetZoom or Fallbacks.Noop,
        StartPan = Deps.StartPan,
        StopPan = Deps.StopPan,
        fitReason = "GROUP_PREVIEW_ZOOM_FIT",
        oneReason = "GROUP_PREVIEW_ZOOM_1TO1",
        lockButton = true,
        defaultLocked = true,
        lockReason = "GROUP_PREVIEW_ZOOM_LOCK",
        unlockReason = "GROUP_PREVIEW_ZOOM_UNLOCK",
    })
    box._msuf2ZoomCommand = box._msuf2ZoomCommand
        or (PreviewHelpers.BuildZoomCommand and PreviewHelpers.BuildZoomCommand(box, GFZoomPan, "GROUP_PREVIEW_SEARCH_ZOOM"))
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
        local controlsHint = PreviewHelpers.EnsurePreviewControlsHint(box, stage, { M = M, T = T, Tr = Tr })
        RegisterPreviewControl(controlsHint and controlsHint._close, "hint.dismiss", "Dismiss preview tip", "button", "ephemeral")
    end
    Deps.ZoomWheel = box._zoomWheel or Deps.ZoomWheel
    CreatePreviewAnimationButton(box, RegisterPreviewControl)
    CreatePreviewRoleButton(box, RegisterPreviewControl)
    local bounds = PixelLayoutRegion(CreateFrame("Frame", nil, stage, T.Template()))
    PixelLayoutRegion(bounds, "SetBackdrop", { bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    bounds:SetBackdropColor(0, 0, 0, 0)
    -- Bounds mark a measurement, not a problem; cyan matches the Unit preview.
    bounds:SetBackdropBorderColor(0.25, 0.75, 0.88, 0.92)
    box._bounds = bounds
    state.stage, state.bounds = stage, bounds
end
--- What a group layer chip does. The layer flags themselves live in M.gfPreviewLayerVisible, shared by every group preview.
local GroupLayerChip = {}
function GroupLayerChip.Available(owner, key)
    return not (owner and owner._layerAvailable and owner._layerAvailable[key] == false)
end
function GroupLayerChip.On(owner, key)
    if not GroupLayerChip.Available(owner, key) then return false end
    if M.gfPreviewSoloLayer ~= nil then return M.gfPreviewSoloLayer == key end
    return M.gfPreviewLayerVisible[key] ~= false
end
function GroupLayerChip.Refresh(owner)
    for j = 1, #(owner._layerButtons or {}) do owner._layerButtons[j]:Refresh() end
    PreviewHelpers.RefreshSampleEffectHint(owner)
    if owner.RequestRefresh then owner:RequestRefresh("GROUP_PREVIEW_LAYER")
    elseif owner.Refresh then owner:Refresh("GROUP_PREVIEW_LAYER") end
end
--- The sample-effect hint hides every painted sample layer exactly as a plain click on its chip would.
function GroupLayerChip.HideSamples(owner)
    local visible, state, changed = M.gfPreviewLayerVisible, M._msuf2SampleLayers, false
    for i = 1, #(owner._layerButtons or {}) do
        local key = owner._layerButtons[i].key
        if PreviewHelpers.IsSampleEffectLayer(key) and GroupLayerChip.On(owner, key) then
            M.gfPreviewSoloLayer = nil
            visible[key], changed = false, true
            if state then state.auto[key] = nil end
        end
    end
    if changed then GroupLayerChip.Refresh(owner) end
end
function GroupLayerChip.Click(self, owner)
    if not GroupLayerChip.Available(owner, self.key) then
        if GameTooltip then GameTooltip:Hide() end
        OpenGFSection(self._sectionKey)
        return
    end
    local visible, sampleState = M.gfPreviewLayerVisible, M._msuf2SampleLayers
    if IsShiftKeyDown and IsShiftKeyDown() then
        local solo
        if M.gfPreviewSoloLayer ~= self.key then solo = self.key end
        M.gfPreviewSoloLayer = solo
        -- Soloing a sample layer is asking for it, so it has to paint.
        if solo and PreviewHelpers.IsSampleEffectLayer(solo) and visible[solo] == false then
            visible[solo] = true
            if sampleState then sampleState.auto[solo] = nil end
        end
    else
        M.gfPreviewSoloLayer = nil
        visible[self.key] = visible[self.key] == false
        -- A chip click is the user's own choice: the settings section no longer owns this layer's state.
        if sampleState then sampleState.auto[self.key] = nil end
    end
    GroupLayerChip.Refresh(owner)
end
function GroupLayerChip.Enter(self, owner, available, on, tr)
    local label = self.fs and self.fs:GetText() or tr("Layer")
    if available and PreviewHelpers.IsSampleEffectLayer(self.key) and GameTooltip then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(label, 1, 1, 1)
        PreviewHelpers.AddSampleEffectTooltipLine(self.key, tr)
        GameTooltip:Show()
    end
    if not owner._hint then return end
    if not available then
        owner._hint:SetText(string.format(tr("%s is off in settings. Click to open its options."), label))
        return
    end
    local solo = M.gfPreviewSoloLayer == self.key
    local action = solo and "Shift-click clears solo layer" or (on and "click to hide - Shift-click to solo" or "click to show")
    owner._hint:SetText(label .. " - " .. tr(action))
end
--- Preview layers: label, swatch colour, owning settings section, layer key and whether the layer starts on.
--- The order follows the Unit preview wherever the two share concepts: guides, text, portrait, resources,
--- content, status, then the optional bounds measurement at the far right. The configured frame outline
--- is rendered independently, so Bounds is only the cyan measurement guide and starts off; sample-effect
--- layers stay off until a chip click or their open settings section asks for them.
--- A chip whose layer is off in settings turns into a shortcut to the setting that enables it, so the
--- Dispel Symbol chip names its own accordion rather than the overlay's.
local LAYER_DEFS = {
    { "Guides", { 0.42, 0.72, 1.00 }, "layout", "guides", false },
    { "Text", { 0.70, 0.90, 1.00 }, "text", "text", true },
    { "Portrait", { 0.90, 0.42, 1.00 }, "portrait", "portrait", true },
    { "Power", { 0.30, 0.62, 0.98 }, "power", "power", true },
    { "Buffs", { 0.20, 0.90, 0.35 }, "buffs", "buff", true },
    { "Tracked", { 0.42, 0.68, 1.00 }, "buffs", "trackedBuff", true },
    { "Debuffs", { 0.90, 0.20, 0.22 }, "debuffs", "debuff", true },
    { "External", { 0.30, 0.72, 1.00 }, "externals", "external", true },
    { "Spells", { 0.86, 0.50, 1.00 }, "si", "si", true },
    { "CD/Stack", { 1.00, 0.82, 0.28 }, "textcolor", "auraText", true },
    { "Status", { 0.95, 0.78, 0.22 }, "sicons", "status", true },
    { "Dispel Overlay", { 0.25, 0.72, 1.00 }, "dispel", "dispelOverlay", false },
    { "Dispel Symbol", { 0.34, 0.84, 1.00 }, "dispelSymbol", "dispelSymbol", false },
    { "Bounds", { 0.25, 0.75, 0.88 }, "layout", "bounds", false },
}
function NativeBuild.LayerRail(state)
    local box, chrome, layerW, RegisterPreviewControl = state.box, state.chrome, state.layerW, state.RegisterPreviewControl
    local layers = PixelLayoutRegion(CreateFrame("Frame", nil, box, T.Template()))
    local layerColors = T.colors or {}
    ApplyGroupChrome(layers, "sidebar", layerColors.coreShadow or layerColors.panel, layerColors.borderSoft)
    -- Layer chips flow along the bottom edge instead of holding a fixed column,
    -- so the stage keeps the full card width. Same treatment as the Unit preview.
    layers:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 12, 12)
    layers:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -12, 12)
    layers:SetHeight(30)
    box._layers = layers
    local layersTitle = LayerFont(layers, "Preview Layers", chrome.layerHeader or (T.colors and T.colors.muted) or LAYER_HEADER_COLOR)
    layersTitle:SetPoint("LEFT", layers, "LEFT", 10, 0)
    box._msuf2LayerRailHeader = layersTitle
    if type(M.gfPreviewLayerVisible) ~= "table" then M.gfPreviewLayerVisible = {} end
    local layerVisibility = M.gfPreviewLayerVisible
    for i = 1, #LAYER_DEFS do
        local def = LAYER_DEFS[i]
        if layerVisibility[def[4]] == nil then layerVisibility[def[4]] = def[5] end
    end
    box._layerButtons = {}
    box.layerVisibility = layerVisibility
    local groupLayerButtonOpts = PreviewHelpers.LayerChipButtonOpts(Tr, layerColors, chrome, {
        IsAvailable = GroupLayerChip.Available,
        IsOn = GroupLayerChip.On,
        OnClick = GroupLayerChip.Click,
        OnEnter = GroupLayerChip.Enter,
        OnLeave = function(_, owner) UpdateHint(owner) end,
    })
    for i = 1, #LAYER_DEFS do
        local def = LAYER_DEFS[i]
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
                local sampleState = M._msuf2SampleLayers
                if sampleState then sampleState.auto[btn._layerKey] = nil end
                if box.RequestRefresh then box:RequestRefresh("GROUP_PREVIEW_SEARCH_LAYER")
                elseif box.Refresh then box:Refresh() end
                return (layerVisibility[btn._layerKey] ~= false) == enabled
            end,
        }
        RegisterPreviewControl(btn, "layer." .. tostring(def[4]), def[1] .. " preview layer", "button", "ephemeral")
        if def[4] == "portrait" then btn:Hide() end
        box._layerButtons[#box._layerButtons + 1] = btn
    end
    PreviewHelpers.SetupSampleEffectHint(box, state.stage, {
        Tr = Tr, T = T, buttons = "_layerButtons", IsOn = GroupLayerChip.On, Hide = GroupLayerChip.HideSamples,
    })
    box.LayoutLayerRail = function(self, railWidth)
        return PreviewHelpers.LayoutLayerRail(self, self._layers, self._layerButtons, railWidth)
    end
    -- The stage is the surface; the rail sits over it with its header shown.
    box.ApplyDockedPreviewLayout = function(self, bottomInset)
        return PreviewHelpers.ApplyDockedPreviewLayout(self, self._layers, self._stage, bottomInset, true)
    end
end
function NativeBuild.Mock(state)
    local Deps, box, stage, bounds, RegisterPreviewControl = state.R, state.box, state.stage, state.bounds, state.RegisterPreviewControl
    local mock = PixelLayoutRegion(CreateFrame("Frame", nil, stage, T.Template()), true)
    PixelLayoutRegion(mock, "SetBackdrop", { bgFile = WHITE8X8 })
    mock:SetBackdropColor(0, 0, 0, 0)
    mock:SetBackdropBorderColor(0, 0, 0, 0)
    mock:EnableMouse(true)
    mock:EnableMouseWheel(true)
    if mock.SetPropagateMouseWheel then mock:SetPropagateMouseWheel(false) end
    mock:SetScript("OnMouseWheel", Deps.ZoomWheel)
    mock:SetScript("OnMouseDown", function(_, button) Deps.StartPan(stage, box, button, true) end)
    mock:SetScript("OnMouseUp", function()
        if stage._msufGFPreviewPanning then Deps.StopPan(stage) end
    end)
    -- Stands in for the live frame's MSUFSpec.scope: the shared preview border
    -- helper puts group mocks in the group foreground band (Layers.BorderOffset).
    mock._msufPreviewGroupScope = true
    box._mock = mock
    box.mock, mock.bounds = mock, bounds
    function box:PanExact(dx, dy)
        if M.IsConfigCombatLocked and M.IsConfigCombatLocked() then return false, "combat-locked" end
        if self._msufGFNativePreviewDisposed then return false, "preview-disposed" end
        if not (self.IsShown and self:IsShown() and (not self.IsVisible or self:IsVisible())) then return false, "preview-not-visible" end
        if (self._stage and self._stage._msufGFPreviewPanning) or (self._dragFrame and self._dragFrame._handle) then return false, "preview-busy" end
        if not GFZoomPan.NudgePan then return false, "pan-api-unavailable" end
        return GFZoomPan.NudgePan(self, dx, dy)
    end
    box._msuf2PanCommand = box._msuf2PanCommand or (PreviewHelpers.BuildPanCommand and PreviewHelpers.BuildPanCommand(
        box, GFZoomPan,
        function(dx, dy)
            if not (M.GroupPreview and M.GroupPreview.Pan) then return false end
            return M.GroupPreview.Pan(dx, dy)
        end,
        { previewSurface = "group" }
    ))
    RegisterPreviewControl(mock, "canvas", "Group preview canvas", "canvas", "ephemeral", {
        help = "Pans this exact Group preview canvas by an explicit X/Y delta.",
        command = box._msuf2PanCommand,
    })
    -- The complete cell is an engine frame: an isolated scene hangs on the mock and Render.RenderCell aliases its regions
    -- (_health, _power, _nameFS, ...) onto the mock for the handles. The scene root is the kit host of this preview:
    -- Activate/Deactivate follow the box's visibility. It is built by the first paint (Render.RenderCell), not here:
    -- a preview that is never shown, or a host without the engine, never builds a scene.
    state.mock = mock
end
--- The selection bar reads and writes the same stored offsets the handles drag.
local GroupSelection = {}
function GroupSelection.Theme()
    return T
end
function GroupSelection.HandleList(owner)
    return owner._handleList
end
-- Locked handles are shown but not movable, so they are not a
-- selectable row or a Tab stop either.
function GroupSelection.IsPlaced(handle)
    if handle._locked then return false end
    return not (handle.IsShown and not handle:IsShown())
end
function GroupSelection.Read(owner, handle)
    -- Name X/Y are anchor-local offsets. Reading the rendered handle
    -- center here makes X=0 mean "center the glyphs in the frame", which
    -- silently rewrites LEFT/RIGHT/TOP anchors into an apparent CENTER.
    -- Keep every other Group handle in the shared rendered-coordinate
    -- space; only Name mirrors the stored offset contract used by its
    -- anchor control and renderer.
    if handle and handle._cfgText == true and handle._cfgTextKind == "name" then
        local _, rawX, rawY = HandleOffsets(handle)
        return Round(tonumber(rawX) or 0), Round(tonumber(rawY) or 0)
    end
    local selection = M.PreviewSelectionBar
    local x, y
    if selection and selection.ReadRenderedCoordinates then
        x, y = selection.ReadRenderedCoordinates(handle, owner and owner._mock,
            owner and (owner._mockScale or (owner._mock and owner._mock._previewScale)) or 1)
    end
    if x == nil or y == nil then
        local _, rawX, rawY = HandleOffsets(handle)
        x, y = rawX, rawY
    end
    return Round(tonumber(x) or 0), Round(tonumber(y) or 0)
end
-- NudgeHandleExact remains the audited storage writer. Name uses its
-- anchor-local stored offsets; every other handle translates exact
-- entry from the shared rendered coordinate space.
function GroupSelection.Nudge(owner, handle, dx, dy)
    if dx == 0 and dy == 0 then return true end
    if not owner.NudgeHandleExact then return false end
    return owner:NudgeHandleExact(handle._key, dx, dy) == true
end
function GroupSelection.WriteStored(owner, handle, x, y)
    local _, curX, curY = HandleOffsets(handle)
    return GroupSelection.Nudge(owner, handle, (tonumber(x) or 0) - (tonumber(curX) or 0), (tonumber(y) or 0) - (tonumber(curY) or 0))
end
function GroupSelection.Write(owner, handle, x, y)
    if handle and handle._cfgText == true and handle._cfgTextKind == "name" then
        return GroupSelection.WriteStored(owner, handle, x, y)
    end
    local curX, curY = GroupSelection.Read(owner, handle)
    return GroupSelection.Nudge(owner, handle, (tonumber(x) or curX) - curX, (tonumber(y) or curY) - curY)
end
function GroupSelection.Reset(owner, handle)
    return GroupSelection.WriteStored(owner, handle, DefaultHandleOffsets(handle))
end
function GroupSelection.NudgeDelta(owner, dx, dy)
    local handle = owner._selectedHandle
    if not (handle and owner.NudgeHandleExact) then return false end
    return owner:NudgeHandleExact(handle._key, dx, dy) == true
end
-- Mirrors the fallbacks ReadHandlePositionExact already treats as
-- each handle type's default.
function GroupSelection.DefaultOffsets(_, handle)
    return DefaultHandleOffsets(handle)
end
function GroupSelection.OpenSettings(_, handle)
    local open = M.GroupPreview and M.GroupPreview.OpenSection
    if not (handle._sectionKey and open) then return false end
    open(handle._sectionKey)
    return true
end
-- Selection bar edit field, its axis, Search path, label, route note and setting key: the shared X/Y
-- fields are pinned to the Party Portrait handle for Search.
GroupSelection.OffsetRows = {
    { "editX", "x", "selection.portrait_offset_x", "Party Portrait X Offset",
        "The shared Preview X field is pinned to the Party Portrait handle for this exact Search route.",
        "gf_party.portraitOffsetX" },
    { "editY", "y", "selection.portrait_offset_y", "Party Portrait Y Offset",
        "The shared Preview Y field is pinned to the Party Portrait handle for this exact Search route.",
        "gf_party.portraitOffsetY" },
}
function GroupSelection.Create(box, stage, selectHandle)
    local selectionAPI = M.PreviewSelectionBar
    selectionAPI.Create(box, {
        Tr = Tr,
        Theme = GroupSelection.Theme,
        ApplyBackdrop = ApplyGroupPreviewFlatBackdrop,
        Round = Round,
        HandleList = GroupSelection.HandleList,
        HandleLabel = HandleText,
        IsPlaced = GroupSelection.IsPlaced,
        ReadOffsets = GroupSelection.Read,
        WriteOffsets = GroupSelection.Write,
        ResetOffsets = GroupSelection.Reset,
        NudgeDelta = GroupSelection.NudgeDelta,
        DefaultOffsets = GroupSelection.DefaultOffsets,
        OpenSettings = GroupSelection.OpenSettings,
        SelectHandle = function(_, handle) return selectHandle(handle) end,
        UpdateHint = UpdateHint,
    })
    selectionAPI.CreatePicker(box, stage)
    local registerControl = box._msuf2RegisterGroupPreviewControl or RegisterGroupPreviewControl
    registerControl(box._msuf2ElementPicker, "element_picker", "Group Preview Element Picker", "button", "ephemeral")
    local selectionBar = box._msuf2SelectionBar
    if not selectionBar then return end
    -- Exact offset rows belong to the Group Frames pages; a preview inside
    -- another page (each Colors category) keeps its fields ephemeral.
    local offsetClass = tostring(M.activeKey or ""):match("^gf_") and "setting" or "ephemeral"
    local rows = GroupSelection.OffsetRows
    for i = 1, #rows do
        local row = rows[i]
        local edit = selectionBar[row[1]]
        selectionAPI.BindExactOffsetSearchTarget(edit, box, "portrait")
        registerControl(edit, row[3], row[4], "textinput", offsetClass, {
            searchRouteDisposition = "dynamic",
            searchRouteDispositionReason = row[5],
            searchSettingKeys = { row[6] },
            command = selectionAPI.BuildExactOffsetCommand(box, "portrait", row[2], {
                previewSurface = "group", previewScope = "party",
            }),
        })
    end
    registerControl(selectionBar.resetButton, "selection.reset", "Reset selected preview element offset", "button", "ephemeral")
    registerControl(selectionBar.openButton, "selection.open_settings", "Open selected preview element settings", "button", "ephemeral")
end
function NativeBuild.Handles(state)
    local Deps, box = state.R, state.box
    box._selectedHandle = nil
    Deps.RegisterPreviewControl = state.RegisterPreviewControl
    local handles = (M.GroupPreviewHandles and M.GroupPreviewHandles.Install and M.GroupPreviewHandles.Install(box, Deps)) or {}
    state.handles = handles
    if M.PreviewSelectionBar then GroupSelection.Create(box, state.stage, handles.SelectHandle) end
end
-- What Handles.Install returns that the renderer consumes (statusHandles is defaulted separately).
local RENDER_HANDLE_FIELDS = {
    "buffHandle", "trackedBuffHandle", "debuffHandle", "externalHandle", "powerBarHandle", "portraitHandle",
    "dispelSymbolHandle", "spellHandle", "SelectHandle", "NudgeHandlePosition", "AddIconPool",
}
function NativeBuild.Render(state)
    local box, handles = state.box, state.handles
    box.OnPreviewCanvasMoved = function(_, button)
        if PreviewHelpers.NotePreviewCanvasMoved then PreviewHelpers.NotePreviewCanvasMoved(button) end
    end
    if box.ApplyDockedPreviewLayout then box:ApplyDockedPreviewLayout(12) end
    if M.GroupPreviewRender and M.GroupPreviewRender.Install then
        local renderDeps = ShallowCopy(state.R) or {}
        renderDeps.width, renderDeps.mock = state.width, state.mock
        for i = 1, #RENDER_HANDLE_FIELDS do
            local key = RENDER_HANDLE_FIELDS[i]
            renderDeps[key] = handles[key]
        end
        renderDeps.statusHandles = handles.statusHandles or {}
        renderDeps.statusSpecs = StatusSpecs()
        M.GroupPreviewRender.Install(box, state.ctx, renderDeps)
    end
end
-- The page that owns this preview has hidden it: callers release the runtime preview instead of painting.
local function PreviewHostHidden(box)
    local hostShown = box._msufGFPreviewHostShown
    return hostShown and not hostShown()
end
function NativeBuild.Lifecycle(state)
    local box, StopHandleDrag = state.box, state.handles.StopHandleDrag
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
        if PreviewHostHidden(self) then
            self:ReleaseRuntimePreview()
            return
        end
        if self._msufGFTextDragActive or self._msufGFRefreshQueued then
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
            if PreviewHostHidden(self) then
                self:ReleaseRuntimePreview()
                return
            end
            if self.Refresh then self:Refresh(self._msufGFRefreshReason) end
            self._msufGFRefreshReason = nil
        end
        -- Live-mirror events (player regen ticks out of combat) coalesce on a
        -- wider window so value streams cost at most five renders per second.
        ScheduleNativePreviewRefresh(RunRefresh, reason == "GROUP_PREVIEW_LIVE_STATE" and 0.2 or nil)
    end
    function box:ReleaseRuntimePreview()
        self:CancelPendingRefresh()
        if M.GroupPreviewRender and M.GroupPreviewRender.HideAdditionalPreview then
            M.GroupPreviewRender.HideAdditionalPreview(self)
        end
        if self.SuspendSpellPreviewEffects then self:SuspendSpellPreviewEffects() end
        StopHandleDrag(self and self._selectedHandle)
        -- The cell is not on screen while the preview is suspended: the scene root goes quiet with it.
        PreviewHelpers.RestoreGroupSceneHandles(self, true)
        if self._scene then self._scene:Deactivate() end
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
    box:HookScript("OnShow", function(self)
        if self.RegisterEvent then
            self:RegisterEvent("PLAYER_REGEN_DISABLED")
            self:RegisterEvent("PLAYER_REGEN_ENABLED")
        end
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
        self:ReleaseRuntimePreview()
    end)
    box:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_REGEN_DISABLED" then
            PreviewHelpers.RestoreGroupSceneHandles(self, true)
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
end
-- Live-state driver: the cell mirrors the player's current values (Render.BuildScene samples them), so refresh when
-- they change while the menu preview is visible. Zero combat overhead by construction: PLAYER_REGEN_DISABLED drops
-- every listener for the whole fight and only the re-arm signal stays.
local GF_LIVE_STATE_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER",
    "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_NAME_UPDATE" }
function NativeBuild.LiveState(state)
    local box = state.box
    local driver = CreateFrame("Frame")
    box._msufGFLiveStateDriver = driver
    function box:ArmLiveStateDriver()
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
        driver:UnregisterAllEvents()
        driver._msufLiveArmed = false
    end
    driver:SetScript("OnEvent", function(_, event)
        if PreviewHelpers.LiveStateDriverGate(driver, event, box) then return end
        if event == "PLAYER_REGEN_ENABLED" then
            box:ArmLiveStateDriver()
            return
        end
        if PreviewAnimationInCombat() then return end
        box:RequestRefresh("GROUP_PREVIEW_LIVE_STATE")
    end)
    box:HookScript("OnShow", box.ArmLiveStateDriver)
    box:HookScript("OnHide", box.ReleaseLiveStateDriver)
end
function NativeBuild.Create(parent, ctx)
    local state = NativeBuild.Frame(parent, ctx)
    NativeBuild.Stage(state)
    NativeBuild.LayerRail(state)
    NativeBuild.Mock(state)
    NativeBuild.Handles(state)
    NativeBuild.Render(state)
    NativeBuild.Lifecycle(state)
    NativeBuild.LiveState(state)
    return state.box
end
M.GroupPreview = M.GroupPreview or {}
M.GroupPreview.CreateNative = NativeBuild.Create
M.GroupPreview.OpenSection = OpenGFSection
function M.FocusGFPreviewTextSlot(kind, slot, active)
    local previews = M._gfNativePreviews
    if not previews then return false end
    local focused = false
    for i = 1, #previews do
        local box = previews[i]
        if box and not box._msufGFNativePreviewDisposed and box.FocusTextSlot and box.IsShown and box:IsShown()
            and (not box.IsVisible or box:IsVisible()) then focused = box:FocusTextSlot(kind, slot, active) or focused end
    end
    return focused
end

-- A sample-effect layer follows its open settings section: opening or closing one repaints every shown group preview,
-- whose render reads the section state and applies the edge.
local GF_SAMPLE_SECTION_IDS = { dispel = true, dispelSymbol = true }
local previousSectionStateChanged = M.OnCollapsibleSectionStateChanged
function M.OnCollapsibleSectionStateChanged(pageKey, sectionId, open, entry)
    if previousSectionStateChanged then previousSectionStateChanged(pageKey, sectionId, open, entry) end
    if pageKey ~= "gf_bars" or not GF_SAMPLE_SECTION_IDS[sectionId] then return end
    local previews = M._gfNativePreviews
    for i = 1, previews and #previews or 0 do
        local box = previews[i]
        if box and not box._msufGFNativePreviewDisposed and box.RequestRefresh and box.IsShown and box:IsShown() then
            box:RequestRefresh("GROUP_PREVIEW_SAMPLE_LAYER")
        end
    end
end
