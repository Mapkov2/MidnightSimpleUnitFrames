local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local C_Timer = M.MenuTimer or _G.C_Timer

-- Menu2 Group page foundation.
-- Owns party/raid/mythicraid option binding and preview sync. Apply work is routed through
-- the shared Menu2 ApplyService when available; the page-local queue remains as a fallback.
local W = M.Widgets
local T = M.Theme
local ControlGates = M.ControlGates or {}
local Shared = M.UnitSectionsShared or {}
local VT = M.ValueTextList
local WL = M.WordList
local floor = math.floor
local max = math.max
local min = math.min
local Specs = M.GroupSpecs or {}
-- Keep every option domain bound by name. A positional multi-return here made
-- one omitted key shift every following Group dropdown onto the next domain.
-- Explicit reads make additions/removals local and impossible to cascade.
local SCOPE_VALUES = Specs.SCOPE_VALUES or {}
local GROWTH_VALUES = Specs.GROWTH_VALUES or {}
local BLIZZARD_FALLBACK_VALUES = Specs.BLIZZARD_FALLBACK_VALUES or {}
local HEALTH_MODES = Specs.HEALTH_MODES or {}
local TEXT_MODES = Specs.TEXT_MODES or {}
local DELIMITER_VALUES = Specs.DELIMITER_VALUES or {}
local ANCHORS = Specs.ANCHORS or {}
local AURA_ANCHORS = Specs.AURA_ANCHORS or {}
local SORT_MODES = Specs.SORT_MODES or {}
local GF_BAR_MODES = Specs.GF_BAR_MODES or {}
local GF_ANCHOR_TO = Specs.GF_ANCHOR_TO or {}
local GF_ANCHOR_POINTS = Specs.GF_ANCHOR_POINTS or {}
local STATUS_ICON_ANCHORS = Specs.STATUS_ICON_ANCHORS or {}
local GF_STATUS_ICON_SPECS = Specs.GF_STATUS_ICON_SPECS or {}
local GF_STATUS_ICON_VALUES = Specs.GF_STATUS_ICON_VALUES or {}
local PLACED_INDICATOR_TYPES = Specs.PLACED_INDICATOR_TYPES or {}
local FRAME_EFFECT_TYPES = Specs.FRAME_EFFECT_TYPES or {}
local ICON_EFFECT_TYPES = Specs.ICON_EFFECT_TYPES or {}
local SPELL_GROWTH_VALUES = Specs.SPELL_GROWTH_VALUES or {}
local CI_SLOT_VALUES = Specs.CI_SLOT_VALUES or {}
local CI_SLOT_DEFAULTS = Specs.CI_SLOT_DEFAULTS or {}
local DISPEL_OVERLAY_STYLES = Specs.DISPEL_OVERLAY_STYLES or {}
local DEBUFF_STRIPE_EDGES = Specs.DEBUFF_STRIPE_EDGES or {}
local GROUP_FRAME_PROVIDER_VALUES = Specs.GROUP_FRAME_PROVIDER_VALUES or {
    { value = "MSUF", text = "MSUF frames" },
    { value = "AUTO", text = "Blizzard frames (WoW settings)" },
    { value = "SHOW", text = "Force Blizzard frames" },
    { value = "NONE", text = "Hide all group frames" },
}
local GROUP_RAID_MANAGER_VALUES = Specs.GROUP_RAID_MANAGER_VALUES or {
    { value = "AUTO", text = "Automatic" },
    { value = "SHOW", text = "Always visible" },
    { value = "MOUSEOVER", text = "Show on mouseover" },
    { value = "HIDDEN", text = "Always hidden" },
}
local HEALTH_TEXT_MODES = Specs.HEALTH_TEXT_MODES or TEXT_MODES
local SIMPLE_TEXTURES = Specs.SimpleTextures or function() return {} end
local pendingGF = {}
local gfFlushQueued = false
local GF_APPLY_DELAY = 0.04
local SCOPE_LABELS = { party = "Party", raid = "Raid", mythicraid = "Mythic Raid" }
local SCOPE_SHORT_LABELS = { mythicraid = "Mythic" }
local FRAME_STRATA_VALUES = {
    { value = "AUTO", text = "Auto (Frame)" },
    { value = "BACKGROUND", text = "BACKGROUND" },
    { value = "LOW", text = "LOW" },
    { value = "MEDIUM", text = "MEDIUM" },
    { value = "HIGH", text = "HIGH" },
    { value = "DIALOG", text = "DIALOG" },
    { value = "FULLSCREEN", text = "FULLSCREEN" },
    { value = "FULLSCREEN_DIALOG", text = "FULLSCREEN_DIALOG" },
    { value = "TOOLTIP", text = "TOOLTIP" },
}
local FRAME_STRATA_COUNT = #FRAME_STRATA_VALUES
local GROUP_SECTION_HEADER_BG = { 0.060, 0.070, 0.130, 0.48 }
local GROUP_SECTION_HEADER_TINTED_BG = { 0, 0, 0, 0.48 }
local function GroupSectionHeaderColor()
    if T.MenuAccentSurfacesTinted and T.MenuAccentSurfacesTinted() then
        local color = T.colors and T.colors.coreSurface
        if color then
            GROUP_SECTION_HEADER_TINTED_BG[1] = color[1]
            GROUP_SECTION_HEADER_TINTED_BG[2] = color[2]
            GROUP_SECTION_HEADER_TINTED_BG[3] = color[3]
            return GROUP_SECTION_HEADER_TINTED_BG
        end
    end
    return GROUP_SECTION_HEADER_BG
end
local function PortableControlToken(value, fallback)
    local token = tostring(value or ""):lower():gsub("[^%w_]+", "."):gsub("^%.*", ""):gsub("%.*$", ""):gsub("%.+", ".")
    return token ~= "" and token or (fallback or "control")
end
local function GroupControlMeta(ctx, semanticPath, classification)
    local pageKey = PortableControlToken(ctx and ctx.key or M.activeKey, "gf_unknown")
    local pageDomain = pageKey:gsub("^gf_", "")
    local path = PortableControlToken(semanticPath, "control")
    local identity = "group." .. pageDomain .. "." .. path
    local meta = {
        controlId = "menu2." .. pageKey .. ".group." .. path,
        pageKey = pageKey,
        identityKey = identity,
        controlPath = identity:gsub("%.", "/"),
        classification = classification or "setting",
    }
    if meta.classification == "setting" or meta.classification == "action" then
        meta.assistantDisposition = "dynamic"
        meta.assistantDispositionReason = "This control targets the currently selected Party, Raid, or Mythic Raid scope."
    end
    -- The control identity describes the visible role. Its command resolves the
    -- currently selected Group scope at runtime, so it is not a static
    -- Assistant Registry action.
    return meta
end
local function RegisterGroupControl(widget, ctx, semanticPath, label, kind, classification, extra)
    if not widget then return widget end
    local meta = GroupControlMeta(ctx, semanticPath, classification)
    meta.label, meta.kind = label, kind
    if type(extra) == "table" then
        for key, value in pairs(extra) do meta[key] = value end
    end
    if meta.settingKey or meta.actionKey then
        meta.assistantDisposition, meta.assistantDispositionReason = nil, nil
    end
    if type(M.RegisterSearchWidget) == "function" then M.RegisterSearchWidget(widget, meta) end
    return widget
end
local function ResolveGroupControlMeta(ctx, semanticPath, fallbackPath)
    if type(semanticPath) == "table" then return semanticPath end
    return GroupControlMeta(ctx, semanticPath or fallbackPath)
end
--- Every status icon, not a hand-picked five. The old list named only pvpIcon and the
--- four status texts, so the enable toggle, size, anchor, offset and layer of the role,
--- leader, assist, raid-marker, ready-check, summon, resurrect and phase icons never
--- copied -- only their icon style did, via the seed below. Deriving the value list
--- from the specs keeps a newly added status icon copyable without another edit here.
local GF_STATUS_ICON_COPY_VALUES = {}
for i = 1, #GF_STATUS_ICON_SPECS do
    GF_STATUS_ICON_COPY_VALUES[i] = GF_STATUS_ICON_SPECS[i].value
end
local GF_INDICATOR_COPY_FIELDS = M.CopyFieldsFromSpecs(GF_STATUS_ICON_SPECS, table.concat(GF_STATUS_ICON_COPY_VALUES, " "),
    [[showGroupNumber groupNumberSize groupNumberAnchor groupNumberX groupNumberY groupNumberLayer groupBorderEnabled groupBorderSize groupBorderPadding groupBorderR groupBorderG groupBorderB groupBorderA iconStyle useMidnightIcons roleIconShowTank roleIconShowHealer roleIconShowDPS roleIconStyle leaderIconStyle assistIconStyle raidMarkerStyle readyCheckIconStyle summonIconStyle resurrectIconStyle pvpIconStyle phaseIconStyle roleIconCustomIcon leaderIconCustomIcon assistIconCustomIcon raidMarkerCustomIcon readyCheckIconCustomIcon summonIconCustomIcon resurrectIconCustomIcon pvpIconCustomIcon phaseIconCustomIcon]], "enabled iconStyle customIcon size anchor x y layer")
local function NormalizeFrameStrata(value, fallback)
    local normalize = _G.MSUF_NormalizeFrameStrata
    if type(normalize) == "function" then return normalize(value, fallback or "AUTO") end
    if value == nil or value == "" then return fallback or "AUTO" end
    value = tostring(value):upper()
    if value == "AUTO" then return "AUTO" end
    local rank = _G.MSUF_FRAME_STRATA_RANK
    return rank and rank[value] and value or (fallback or "AUTO")
end
local function FrameStrataIndex(value)
    value = NormalizeFrameStrata(value, "AUTO")
    for i = 1, FRAME_STRATA_COUNT do
        if FRAME_STRATA_VALUES[i].value == value then return i - 1 end
    end
    return 0
end
local function FrameStrataValue(index)
    index = floor((tonumber(index) or 0) + 0.5) + 1
    if index < 1 then index = 1 elseif index > FRAME_STRATA_COUNT then index = FRAME_STRATA_COUNT end
    return FRAME_STRATA_VALUES[index].value
end
local function FrameStrataLabel(valueOrIndex)
    local value = type(valueOrIndex) == "number" and FrameStrataValue(valueOrIndex) or NormalizeFrameStrata(valueOrIndex, "AUTO")
    if value == "AUTO" then return "AUTO" end
    for i = 1, FRAME_STRATA_COUNT do
        local row = FRAME_STRATA_VALUES[i]
        if row.value == value then return M.Tr(row.text) end
    end
    return "AUTO"
end
local function FrameStrataParse(text)
    text = tostring(text or ""):upper()
    for i = 1, FRAME_STRATA_COUNT do
        local row = FRAME_STRATA_VALUES[i]
        if text == row.value or text == tostring(row.text):upper() then return i - 1 end
    end
    return FrameStrataIndex(text)
end
local function GF()
    return MSUF and MSUF.GF
end
local function CurrentApplyService()
    local apply = (M and M.ApplyService) or _G.MSUF_Menu2_ApplyService
    if type(apply) == "table" then return apply end
    return nil
end
local function MaskHas(mask, flag)
    mask = tonumber(mask) or 0
    flag = tonumber(flag) or 0
    if flag <= 0 then return false end
    return mask % (flag * 2) >= flag
end
local function AddDirty(mask, flag)
    if not flag then return mask or 0 end
    mask = tonumber(mask) or 0
    if MaskHas(mask, flag) then return mask end
    return mask + flag
end
local function MergeDirtyMask(gf, current, incoming)
    if not current then return incoming end
    if not incoming then return current end
    if current == true or incoming == true then return true end
    if gf then
        if current == gf.DIRTY_ALL or incoming == gf.DIRTY_ALL then return gf.DIRTY_ALL end
        if current == gf.DIRTY_CONFIG or incoming == gf.DIRTY_CONFIG then return gf.DIRTY_CONFIG end
    end
    if type(current) ~= "number" or type(incoming) ~= "number" then return incoming end
    local out = current
    if gf then
        out = AddDirty(out, MaskHas(incoming, gf.DIRTY_VISUAL) and gf.DIRTY_VISUAL or nil)
        out = AddDirty(out, MaskHas(incoming, gf.DIRTY_FONT) and gf.DIRTY_FONT or nil)
        out = AddDirty(out, MaskHas(incoming, gf.DIRTY_COLOR) and gf.DIRTY_COLOR or nil)
        out = AddDirty(out, MaskHas(incoming, gf.DIRTY_BORDER) and gf.DIRTY_BORDER or nil)
        out = AddDirty(out, MaskHas(incoming, gf.DIRTY_GEOMETRY) and gf.DIRTY_GEOMETRY or nil)
        out = AddDirty(out, MaskHas(incoming, gf.DIRTY_LAYOUT) and gf.DIRTY_LAYOUT or nil)
        out = AddDirty(out, MaskHas(incoming, gf.DIRTY_AURAS) and gf.DIRTY_AURAS or nil)
        out = AddDirty(out, MaskHas(incoming, gf.DIRTY_UNIT_BINDING) and gf.DIRTY_UNIT_BINDING or nil)
    end
    return out
end
local function ModeDirtyMask(gf, mode)
    if not gf then return nil end
    if mode == "visual" or mode == nil then return gf.DIRTY_VISUAL end
    if mode == "font" or mode == "fonts" then return gf.DIRTY_FONT end
    if mode == "color" or mode == "colors" then return gf.DIRTY_COLOR end
    if mode == "border" or mode == "borders" then return gf.DIRTY_BORDER end
    if mode == "auras" then return gf.DIRTY_AURAS end
    if mode == "geometry" then return AddDirty(gf.DIRTY_GEOMETRY, gf.DIRTY_LAYOUT) end
    if mode == "config" then return gf.DIRTY_CONFIG end
    return nil
end
local function RequestGFPagePreview()
    if type(M.RequestGFPagePreviewForKey) == "function" then
        return M.RequestGFPagePreviewForKey(M.activeKey)
    end
    if type(M.SyncGFPagePreviewForKey) == "function" then
        return M.SyncGFPagePreviewForKey(M.activeKey)
    end
end
local function RefreshGFPreview(kind, opts)
    -- Preview and live group frames have separate render paths. Refresh both when controls
    -- change so the page does not hide a stale runtime configuration.
    local gf = GF()
    if opts and opts.auraOnly == true and gf and type(gf.RefreshPreviewAuras) == "function" then
        gf.RefreshPreviewAuras(kind)
    elseif opts and opts.auraOnly == true and type(_G.MSUF_GF_RefreshPreviewAuras) == "function" then
        _G.MSUF_GF_RefreshPreviewAuras(kind)
    elseif opts and opts.spellOnly == true and gf and type(gf.RefreshPreviewSpellIndicators) == "function" then
        gf.RefreshPreviewSpellIndicators(kind)
    elseif opts and opts.spellOnly == true and type(_G.MSUF_GF_RefreshPreviewSpellIndicators) == "function" then
        _G.MSUF_GF_RefreshPreviewSpellIndicators(kind)
    elseif gf and type(gf.RefreshPreviewLayout) == "function" then
        gf.RefreshPreviewLayout(kind)
    end
    if type(M.RefreshGFNativePreviews) == "function" then
        M.RefreshGFNativePreviews("GF_PAGE_REFRESH")
    end
    -- Targeted Aura/Spell drag refreshes already update the active Edit Mode
    -- dummies directly. Do not queue the page-preview ownership settle too;
    -- that would perform a delayed full ShowPreview for every slider stream.
    if not (opts and (opts.auraOnly == true or opts.spellOnly == true))
        and (type(M.RequestGFPagePreviewForKey) == "function" or type(M.SyncGFPagePreviewForKey) == "function")
    then
        RequestGFPagePreview()
    end
end
local function Conf(kind)
    local gf = GF()
    if gf and type(gf.GetConf) == "function" then return gf.GetConf(kind) end
    local db = M.EnsureDB()
    local key = kind == "raid" and "gf_raid" or (kind == "mythicraid" and "gf_mythicraid" or "gf_party")
    db[key] = db[key] or {}
    return db[key]
end
local function Val(kind, key, default)
    local gf = GF()
    if gf and type(gf.Val) == "function" then
        local value = gf.Val(kind, key)
        if value ~= nil then return value end
    end
    local conf = Conf(kind)
    if conf[key] ~= nil then return conf[key] end
    return default
end
local function FlushGF()
    gfFlushQueued = false
    local gf = GF()
    if not gf then return end
    local rebuild = pendingGF.rebuild
    local geometry = pendingGF.geometry
    local dirtyMask = pendingGF.dirtyMask
    local kind = pendingGF.kind
    pendingGF.rebuild = nil
    pendingGF.geometry = nil
    pendingGF.dirtyMask = nil
    pendingGF.kind = nil
    if kind == false then kind = nil end
    if InCombatLockdown and InCombatLockdown() then
        if rebuild and type(gf.Rebuild) == "function" then
            gf.Rebuild(kind)
            RefreshGFPreview(kind)
            return
        elseif rebuild and type(gf.RebuildAll) == "function" then
            gf.RebuildAll()
            RefreshGFPreview(kind)
            return
        end
        if geometry and type(gf.DeferGroupRuntime) == "function" then
            gf.DeferGroupRuntime("layout", kind, dirtyMask)
        elseif geometry then
            gf._pendingRefreshGeometry = true
        end
        if dirtyMask and not geometry and type(gf.DeferGroupRuntime) == "function" then
            gf.DeferGroupRuntime("refresh", kind, dirtyMask)
        elseif dirtyMask and not geometry then
            gf._pendingRefreshVisuals = true
        end
        RefreshGFPreview(kind)
        return
    end
    if rebuild then
        if type(gf.Rebuild) == "function" then
            gf.Rebuild(kind)
        elseif type(gf.RebuildAll) == "function" then
            gf.RebuildAll()
        end
        RefreshGFPreview()
        return
    end
    if geometry then
        if type(gf.RefreshGeometry) == "function" then gf.RefreshGeometry(kind) end
    end
    if dirtyMask then
        if type(gf.RefreshVisuals) == "function" then gf.RefreshVisuals(kind, dirtyMask) end
    end
    RefreshGFPreview(kind)
end
local QueueGF
local function QueueGFLegacy(kind, mode)
    local gf = GF()
    if kind ~= nil then
        if pendingGF.kind == nil then
            pendingGF.kind = kind
        elseif pendingGF.kind ~= kind then
            pendingGF.kind = false
        end
    end
    if mode == "rebuild" then pendingGF.rebuild = true end
    if mode == "geometry" then pendingGF.geometry = true end
    local dirty = ModeDirtyMask(gf, mode)
    if dirty then pendingGF.dirtyMask = MergeDirtyMask(gf, pendingGF.dirtyMask, dirty) end
    if gfFlushQueued then return end
    gfFlushQueued = true
    if C_Timer and C_Timer.After then
        C_Timer.After(GF_APPLY_DELAY, FlushGF)
    else
        FlushGF()
    end
end
local function QueueGFDirtyMask(kind, dirtyMask)
    local gf = GF()
    if not dirtyMask then return QueueGF(kind, "visual") end
    local apply = CurrentApplyService()
    if apply and type(apply.RequestGroupDirtyMask) == "function" then
        return apply.RequestGroupDirtyMask(kind, dirtyMask, "GF_PAGE_DIRTY")
    end
    if kind ~= nil then
        if pendingGF.kind == nil then
            pendingGF.kind = kind
        elseif pendingGF.kind ~= kind then
            pendingGF.kind = false
        end
    end
    pendingGF.dirtyMask = MergeDirtyMask(gf, pendingGF.dirtyMask, dirtyMask)
    if gfFlushQueued then return end
    gfFlushQueued = true
    if C_Timer and C_Timer.After then
        C_Timer.After(GF_APPLY_DELAY, FlushGF)
    else
        FlushGF()
    end
end
function QueueGF(kind, mode)
    local apply = CurrentApplyService()
    if apply and type(apply.RequestGroup) == "function" then
        return apply.RequestGroup(kind, mode or "visual", "GF_PAGE")
    end
    return QueueGFLegacy(kind, mode)
end
local function Set(kind, key, value, mode)
    local function Write()
        local conf = Conf(kind)
        local textureKey = key == "barTexture" or key == "barBackgroundTexture" or key == "barBgTexture"
        local activatesTextureOverride = textureKey and type(value) == "string" and value ~= "" and conf.hlOverride ~= true
        if conf[key] == value and not activatesTextureOverride then return false end
        conf[key] = value
        if activatesTextureOverride then
            conf.hlOverride = true
        end
        QueueGF(kind, mode or "visual")
        if key == "enabled" and type(_G.MSUF_ShowGroupFrameReloadRequiredPopup) == "function" then
            _G.MSUF_ShowGroupFrameReloadRequiredPopup()
        end
        return true
    end
    return M.RunWithHistory("Group " .. tostring(key), "group:" .. tostring(kind) .. ":" .. tostring(key), Write)
end
local function Bool(kind, key, default)
    local value = Val(kind, key, default and true or false)
    return value and true or false
end
local function Num(kind, key, default)
    return tonumber(Val(kind, key, default)) or default or 0
end
local function CurrentScope()
    return M.gfScope or "party"
end
local function ScopeLabel(kind)
    return M.Tr(SCOPE_LABELS[kind] or "Party")
end
local function ScopeShortLabel(kind)
    return M.Tr(SCOPE_SHORT_LABELS[kind] or SCOPE_LABELS[kind] or "Party")
end
local function NormalizeFrameProvider(value)
    if value == "MSUF" then return "MSUF" end
    if value == true or value == "SHOW" or value == "BLIZZARD" then return "SHOW" end
    if value == false or value == "NONE" or value == "HIDE" then return "NONE" end
    return "AUTO"
end
local function FrameProvider(kind)
    if Bool(kind, "enabled", false) then return "MSUF" end
    return NormalizeFrameProvider(Val(kind, "blizzardFallbackMode", "AUTO"))
end
local function FrameProviderInfo(value)
    value = NormalizeFrameProvider(value)
    for i = 1, #GROUP_FRAME_PROVIDER_VALUES do
        local info = GROUP_FRAME_PROVIDER_VALUES[i]
        if info and info.value == value then return info end
    end
end
local function FrameProviderLabel(kind)
    local info = FrameProviderInfo(FrameProvider(kind))
    return M.Tr((info and info.text) or "Blizzard frames (WoW settings)")
end
local function FrameProviderShortLabel(kind)
    local provider = FrameProvider(kind)
    if provider == "MSUF" then return "MSUF" end
    if provider == "SHOW" then return M.Tr("Blizzard forced") end
    if provider == "NONE" then return M.Tr("Hidden") end
    return M.Tr("Blizzard")
end
local function FrameProviderTooltip(kind)
    local info = FrameProviderInfo(FrameProvider(kind))
    return info and (info.tooltip or info.description) or ""
end
--- Scope-synchronized settings. A few options do not describe a scope's own frames but a
--- single shared piece of Blizzard chrome, so there is exactly one of them for Party,
--- Raid and Mythic Raid together. They still live in the three gf_* rows -- profiles,
--- import/export and reset all walk those -- but every write hits all three at once, the
--- same shape the shared group colors on the Colors page use.
local GF_SYNC_KINDS = { "party", "raid", "mythicraid" }
local function SyncedVal(key, default)
    for i = 1, #GF_SYNC_KINDS do
        local conf = Conf(GF_SYNC_KINDS[i])
        if conf and conf[key] ~= nil then return conf[key] end
    end
    return default
end
local function SetSyncedValue(key, value, apply)
    local function Write()
        local changed = false
        for i = 1, #GF_SYNC_KINDS do
            local conf = Conf(GF_SYNC_KINDS[i])
            if conf and conf[key] ~= value then
                conf[key] = value
                changed = true
            end
        end
        if changed and type(apply) == "function" then apply() end
        return changed
    end
    return M.RunWithHistory("Group " .. tostring(key), "group:synced:" .. tostring(key), Write)
end
--- "DEFAULT" is the pre-release spelling of AUTO; map it so a profile from an in-between
--- build keeps its choice instead of resetting. Mirrors the engine normalizer.
local function NormalizeRaidManagerMode(value)
    if value == "MOUSEOVER" then return "MOUSEOVER" end
    if value == "HIDDEN" then return "HIDDEN" end
    if value == "SHOW" then return "SHOW" end
    return "AUTO"
end
local function RaidManagerMode()
    return NormalizeRaidManagerMode(SyncedVal("raidManagerMode", "AUTO"))
end
--- No QueueGF: nothing about MSUF's own frames changes, only Blizzard's tab.
local function SetRaidManagerMode(value)
    value = NormalizeRaidManagerMode(value)
    return SetSyncedValue("raidManagerMode", value, function()
        local gf = GF()
        if gf and type(gf.ApplyBlizzardRaidManagerMode) == "function" then
            gf.ApplyBlizzardRaidManagerMode()
        end
    end)
end
local function SetFrameProvider(kind, provider)
    kind = kind or CurrentScope()
    provider = NormalizeFrameProvider(provider)
    local function Write()
        local conf = Conf(kind)
        local nextEnabled = provider == "MSUF"
        local enabledChanged = conf.enabled ~= nextEnabled
        local fallbackChanged = not nextEnabled and NormalizeFrameProvider(conf.blizzardFallbackMode) ~= provider
        if not enabledChanged and not fallbackChanged then return false end
        conf.enabled = nextEnabled
        if not nextEnabled then conf.blizzardFallbackMode = provider end
        QueueGF(kind, "rebuild")
        if (enabledChanged or fallbackChanged) and type(_G.MSUF_ShowGroupFrameReloadRequiredPopup) == "function" then
            _G.MSUF_ShowGroupFrameReloadRequiredPopup()
        end
        return true
    end
    return M.RunWithHistory("Group frame provider", "group:" .. tostring(kind) .. ":frameProvider", Write)
end
--- Placement never travels through Copy To: two group headers sharing a placement
--- land on top of each other and the covered one can no longer be dragged. Frames are
--- positioned in MSUF Edit Mode. The anchor family belongs here for the same reason --
--- it decides WHERE the header sits, not what it looks like.
--- raidManagerMode joins them for a different reason: it is already identical in all
--- three scopes by construction (see SetSyncedValue), so copying it would only ever be
--- a no-op that pretends the value is per scope.
local GF_COPY_EXCLUDE = M.KeySetFromWords [[
    offsetX offsetY point positionMode _hlMigrated
    anchorMode anchorPoint anchorToFrame customAnchorFrame attachGap attachOffset
    raidManagerMode
]]
local GF_SHARED_COLOR_KEYS = M.KeySetFromWords [[
    gfBarMode healthColorMode healthCustomR healthCustomG healthCustomB gfDarkR gfDarkG gfDarkB
    gfUnifiedR gfUnifiedG gfUnifiedB bgR bgG bgB deadBgEnabled deadBgOffline deadBgR deadBgG deadBgB deadBgA
    debuffStripeAlpha debuffStripeColorR debuffStripeColorG debuffStripeColorB targetR targetG targetB
    hlFocusColorR hlFocusColorG hlFocusColorB groupBorderR groupBorderG groupBorderB groupBorderA
    ciAggroColorR ciAggroColorG ciAggroColorB
]]
local GF_COPY_CATEGORIES = {
    { key = "general", label = "Basics", keys = WL [[enabled blizzardFallbackMode showPlayer showSolo clickCastEnabled width height spacing growth groupFilter sortMode sortByRole roleOrder playerFirstInRole unitsPerColumn maxColumns maxFrames autoTanks preserveRaidGroups reverseFill smoothFill chunkedFill hideInClientScene hideInHousing hideOfflineEnabled hideOfflineInCombat hideOfflineDelay frameScaleEnabled frameScaleMode frameScaleManual scaleAt10 scaleAt20 scaleAt25 scaleOver25]] },
    { key = "health", label = "Health & Bars", keys = WL [[gfBarMode healthColorMode healthCustomR healthCustomG healthCustomB gfDarkR gfDarkG gfDarkB gfUnifiedR gfUnifiedG gfUnifiedB barTexture barBackgroundTexture barBgTexture hpBarAlpha hpBgAlpha alphaExcludeTextPortrait powerBarEnabled powerHeight showPower showPowerText powerTextLeft powerTextCenter powerTextRight powerTextLeftHidePercentSymbol powerTextCenterHidePercentSymbol powerTextRightHidePercentSymbol powerTextDelimiter powerFontSize powerOffsetX powerOffsetY powerTextLayer powerSmoothFill powerChunkedFill powerShowTank powerShowHealer powerShowDamager powerBarDetached powerBarBorderEnabled powerBarBorderThickness embedPowerBarIntoHealth barOutlineTexture oocFadeEnabled oocFadeAlpha healthFadeEnabled healthFadeThreshold healthFadeAlpha deadBgEnabled deadBgOffline deadBgR deadBgG deadBgB deadBgA powerTextLeftFontSize powerTextCenterFontSize powerTextRightFontSize powerTextLeftOffsetX powerTextLeftOffsetY powerTextCenterOffsetX powerTextCenterOffsetY powerTextRightOffsetX powerTextRightOffsetY]], prefix = WL [[detachedPower]] },
    { key = "dispel", label = "Dispel Overlay", keys = WL [[dispelOverlayEnabled dispelOverlayStyle dispelOverlayOnHealth dispelOverlayAlpha dispelOverlayTrigger dispelOverlayLayer dispelOverlayStrata]], prefix = WL [[dispelSymbol]] },
    { key = "text", label = "Text & Name", keys = WL [[showName hideNameOnDeadOffline nameFontSize nameAnchor nameOffsetX nameOffsetY nameTextLayer nameColorMode nameColorR nameColorG nameColorB nameShortenEnabled nameClipSide nameMaxChars nameNoEllipsis showHPText hpFontSize textLeft textCenter textRight hpTextLeftHidePercentSymbol hpTextCenterHidePercentSymbol hpTextRightHidePercentSymbol hpTextLeftAbsorbIcon hpTextCenterAbsorbIcon hpTextRightAbsorbIcon textDelimiter hpTextReverse healthTextDecimals hpTextDecimals hpFullValueShort hpAbsorbIcon hpOffsetX hpOffsetY textLayer hpTextLeftFontSize hpTextCenterFontSize hpTextRightFontSize hpTextLeftOffsetX hpTextLeftOffsetY hpTextCenterOffsetX hpTextCenterOffsetY hpTextRightOffsetX hpTextRightOffsetY]] },
    { key = "font", label = "Font Override", keys = WL [[fontOverride fontOutline useGlobalFontColor fontR fontG fontB colorHealthTextByHealth colorPowerTextByType powerTextColorByType]] },
    { key = "range", label = "Range Fade", keys = WL [[rangeFadeEnabled rangeFadeAlpha rangeFadeLayerMode offlineFadeEnabled offlineAlpha]] },
    { key = "indicators", label = "Status & Indicators", keys = GF_INDICATOR_COPY_FIELDS, prefix = WL [[si_ statusIcon indicator]] },
    --- No portrait category on purpose: party is the only group scope that owns portrait
    --- settings (CompilePortrait returns a disabled spec for every other kind, and the
    --- Assistant only registers them for party). There is no second scope to copy them
    --- to, and pushing them into raid/mythicraid would plant exactly the stale imported
    --- keys the engine guards against.
    { key = "auras", label = "Aura Options", description = "Copies Group Aura visibility, layout, filters, exact/category blacklists, Strata and dispel options. Aura Style and the global Appearance theme remain unchanged.", tables = WL [[auras]] },
    { key = "aurastyle", label = "Aura Style", default = true, description = "Copies Buff, Debuff, External Defensive and Spell Icon presentation, including icon zoom, text, swipe, duration bars and ordering. Aura Options, tracked Spell Icons and the global Appearance theme remain unchanged." },
    { key = "highlight", label = "Highlight & Aggro", keys = WL [[targetIndicator targetR targetG targetB aggroEnabled aggroMode dispelEnabled dispelOutlineMode dispelBorderEnabled dispelBorderMode dispelBorderTrigger dispelTrigger]], prefix = WL [[hl]] },
    { key = "dstripe", label = "Debuff Stripe", prefix = WL [[debuffStripe]] },
    { key = "features", label = "Corner/Spell", keys = WL [[ciEnabled ciAlpha]], tables = WL [[spellIndicators]], prefix = WL [[ci]] },
}
local function DeepCopy(value)
    local gf = GF()
    if gf and type(gf._DeepCopyTable) == "function" then return gf._DeepCopyTable(value) end
    if type(_G.MSUF_DeepCopy) == "function" then return _G.MSUF_DeepCopy(value) end
    return M.DeepCopy(value)
end
local function NewGFCopyScopes()
    local scopes = {}
    for i = 1, #GF_COPY_CATEGORIES do
        local category = GF_COPY_CATEGORIES[i]
        scopes[category.key] = category.default ~= false
    end
    return scopes
end
local function GroupCopyDirtyMask(scopes)
    local gf = GF()
    if not gf or type(scopes) ~= "table" then return nil end
    if scopes.general then return nil end
    if scopes.health or scopes.dispel or scopes.text or scopes.range or scopes.indicators or scopes.highlight or scopes.dstripe or scopes.features then
        return gf.DIRTY_CONFIG or gf.DIRTY_ALL or gf.DIRTY_VISUAL
    end
    local dirty
    if scopes.font then dirty = AddDirty(dirty, gf.DIRTY_FONT) end
    if scopes.auras or scopes.aurastyle then dirty = AddDirty(dirty, gf.DIRTY_AURAS) end
    return dirty or gf.DIRTY_VISUAL
end
local GROUP_AURA_STYLE_ROOT_KEYS = { "dynamicScale", "showTooltip", "iconZoom" }
local GROUP_AURA_STYLE_LANE_KEYS = {
    "iconZoom",
    "showCooldown", "showCooldownSwipe", "showTooltip",
    "dispelBorderMode", "showDispelBorder", "showDispelSymbol",
    "cooldownSize", "cooldownAnchor", "cooldownX", "cooldownY",
    "cooldownSwipeReverse", "cooldownDecimalSeconds",
    "showDurationBar", "durationBarHeight", "durationBarDisplay", "durationBarPosition", "durationBarDirection",
    "showStacks", "stackSize", "stackAnchor", "stackX", "stackY",
    "sortMethod", "sortReverse",
}

local function CaptureGroupAuraStyle(kind)
    local srcAuras = Conf(kind).auras
    if type(srcAuras) ~= "table" then srcAuras = {} end
    local snapshot = { root = {}, lanes = {} }
    for i = 1, #GROUP_AURA_STYLE_ROOT_KEYS do
        local key = GROUP_AURA_STYLE_ROOT_KEYS[i]
        snapshot.root[key] = DeepCopy(srcAuras[key])
    end
    for _, lane in ipairs({ "buff", "debuff", "externals" }) do
        local source = type(srcAuras[lane]) == "table" and srcAuras[lane] or {}
        local values = {}
        snapshot.lanes[lane] = values
        for i = 1, #GROUP_AURA_STYLE_LANE_KEYS do
            local key = GROUP_AURA_STYLE_LANE_KEYS[i]
            values[key] = DeepCopy(source[key])
        end
    end
    return snapshot
end

local function ApplyGroupAuraStyleSnapshot(dstKind, snapshot)
    if type(snapshot) ~= "table" then return false end
    local dstConf = Conf(dstKind)
    dstConf.auras = type(dstConf.auras) == "table" and dstConf.auras or {}
    local dstAuras = dstConf.auras
    for i = 1, #GROUP_AURA_STYLE_ROOT_KEYS do
        local key = GROUP_AURA_STYLE_ROOT_KEYS[i]
        dstAuras[key] = DeepCopy(snapshot.root and snapshot.root[key])
    end
    for _, lane in ipairs({ "buff", "debuff", "externals" }) do
        local destination = type(dstAuras[lane]) == "table" and dstAuras[lane] or {}
        dstAuras[lane] = destination
        local source = type(snapshot.lanes) == "table" and snapshot.lanes[lane] or nil
        for i = 1, #GROUP_AURA_STYLE_LANE_KEYS do
            local key = GROUP_AURA_STYLE_LANE_KEYS[i]
            destination[key] = DeepCopy(source and source[key])
        end
    end
    return true
end

local function CopyGroupAuraStyle(srcKind, dstKind)
    return ApplyGroupAuraStyleSnapshot(dstKind, CaptureGroupAuraStyle(srcKind))
end
local function CopyGroupSpellIndicatorStyle(srcKind, dstKind)
    local srcConf = Conf(srcKind)
    local dstConf = Conf(dstKind)
    local gf = GF()
    if gf and type(gf.EnsureSpellIndicatorStyle) == "function" then gf.EnsureSpellIndicatorStyle(srcConf) end
    local src = type(srcConf.spellIndicators) == "table" and srcConf.spellIndicators or nil
    if not src then return false end
    dstConf.spellIndicators = type(dstConf.spellIndicators) == "table" and dstConf.spellIndicators or {}
    dstConf.spellIndicators.iconZoom = DeepCopy(src.iconZoom)
    dstConf.spellIndicators.iconScale = DeepCopy(src.iconScale)
    dstConf.spellIndicators.style = DeepCopy(src.style)
    if type(dstConf.spellIndicators.style) == "table" then
        dstConf.spellIndicators.style.iconShape = nil
    end
    if gf and type(gf.EnsureSpellIndicatorStyle) == "function" then gf.EnsureSpellIndicatorStyle(dstConf) end
    return true
end
local function CopyGroupSettings(srcKind, dstKind, scopes)
    local srcConf = Conf(srcKind)
    local dstConf = Conf(dstKind)
    if not (srcConf and dstConf and srcKind and dstKind) or srcKind == dstKind then return false end
    scopes = (type(scopes) == "table") and scopes or NewGFCopyScopes()
    local retainedAuraStyle = scopes.auras and CaptureGroupAuraStyle(dstKind) or nil
    local retainedSpellStyle
    if scopes.features and not scopes.aurastyle then
        local gf = GF()
        if gf and type(gf.EnsureSpellIndicatorStyle) == "function" then gf.EnsureSpellIndicatorStyle(dstConf) end
        local current = type(dstConf.spellIndicators) == "table" and dstConf.spellIndicators or nil
        retainedSpellStyle = current and {
            iconZoom = DeepCopy(current.iconZoom),
            iconScale = DeepCopy(current.iconScale),
            style = DeepCopy(current.style),
        } or nil
        if retainedSpellStyle and type(retainedSpellStyle.style) == "table" then
            retainedSpellStyle.style.iconShape = nil
        end
    end
    local allowKeys, allowPrefixes, allowTables = {}, {}, {}
    for i = 1, #GF_COPY_CATEGORIES do
        local cat = GF_COPY_CATEGORIES[i]
        if scopes[cat.key] then
            if cat.keys then
                for j = 1, #cat.keys do allowKeys[cat.keys[j]] = true end
            end
            if cat.prefix then
                for j = 1, #cat.prefix do allowPrefixes[#allowPrefixes + 1] = cat.prefix[j] end
            end
            if cat.tables then
                for j = 1, #cat.tables do allowTables[cat.tables[j]] = true end
            end
        end
    end
    for key, value in pairs(srcConf) do
        if not GF_COPY_EXCLUDE[key] and not GF_SHARED_COLOR_KEYS[key] then
            local copy = allowKeys[key] or allowTables[key]
            if (not copy) and type(key) == "string" then
                for i = 1, #allowPrefixes do
                    local prefix = allowPrefixes[i]
                    if key:sub(1, #prefix) == prefix then
                        copy = true
                        break
                    end
                end
            end
            if copy then dstConf[key] = DeepCopy(value) end
        end
    end
    if retainedSpellStyle and type(dstConf.spellIndicators) == "table" then
        dstConf.spellIndicators.iconZoom = retainedSpellStyle.iconZoom
        dstConf.spellIndicators.iconScale = retainedSpellStyle.iconScale
        dstConf.spellIndicators.style = retainedSpellStyle.style
    end
    if retainedAuraStyle then ApplyGroupAuraStyleSnapshot(dstKind, retainedAuraStyle) end
    if scopes.aurastyle then
        CopyGroupAuraStyle(srcKind, dstKind)
        CopyGroupSpellIndicatorStyle(srcKind, dstKind)
    end
    if scopes.features or scopes.aurastyle then
        local gf = GF()
        local spellIndicators = gf and gf.SpellIndicators
        if spellIndicators and type(spellIndicators.InvalidateRuntimeCaches) == "function" then
            spellIndicators.InvalidateRuntimeCaches()
        end
    end
    if scopes.general then
        QueueGF(dstKind, "rebuild")
    else
        QueueGFDirtyMask(dstKind, GroupCopyDirtyMask(scopes))
    end
    RefreshGFPreview()
    return true
end
local function RefreshContext(ctx)
    if M.RequestRefresh then return M.RequestRefresh(ctx, "gf-context") end
    if not (ctx and ctx.refreshers) then return end
    for i = 1, #ctx.refreshers do
        local fn = ctx.refreshers[i]
        if type(fn) == "function" then fn() end
    end
end
local function SetSectionHeaderStatus(sec, opts)
    if not Shared.SetSectionHeaderStatus then return end
    if not (opts and opts.bg) then opts = M.Assign({ bg = GroupSectionHeaderColor() }, opts) end
    Shared.SetSectionHeaderStatus(sec, opts)
end
local function SetSectionBadges(sec, specs)
    if W and W.SetCollapsibleBadges then
        if sec then sec._msuf2CollapsibleBadgesOnlyWhenOpen = true end
        W.SetCollapsibleBadges(sec, specs or {})
    end
end
local function SetSectionBadgesAndStatus(sec, specs, status)
    SetSectionBadges(sec, specs)
    SetSectionHeaderStatus(sec, status)
end
local TrackSectionRefresh = M.TrackCollapsibleRefresh
local ApplyScopeEnabledGate
local function FinalizeScopePage(ctx, builder)
    if type(ApplyScopeEnabledGate) == "function" then M.TrackRefresh(ctx, function() ApplyScopeEnabledGate(ctx) end) end
    if ctx and ctx.SetContentHeight and builder then ctx:SetContentHeight(math.abs(builder.y) + 42) end
end
local OnOffBadge, BadgeNumber, OptionText = M.OnOffBadge, M.BadgeNumber, M.OptionText
local function CreateSectionNotice(sec, topY, buttonLabel, buttonWidth)
    return Shared.CreateSectionNotice(sec, topY, buttonLabel, buttonWidth, "_msuf2GroupFrameGateAlwaysEnabled")
end
local NAV_SUBPAGE_LABELS = M.navSubpageLabels or {}
local GROUP_PAGE_TABS = {
    { key = "gf_layout", label = NAV_SUBPAGE_LABELS.gf_layout or "Layout", width = 64 },
    { key = "gf_bars", label = NAV_SUBPAGE_LABELS.gf_bars or "Dispel Overlay", width = 108 },
    { key = "gf_indicators", label = NAV_SUBPAGE_LABELS.gf_indicators or "Status & Indicators", width = 138 },
    { key = "gf_auras", label = NAV_SUBPAGE_LABELS.gf_auras or "Auras", width = 58 },
    { key = "gf_priority", label = NAV_SUBPAGE_LABELS.gf_priority or "Priority", width = 72 },
}
local GROUP_FLOW_TAB_STYLE = {
    bg = { 0.018, 0.032, 0.064, 0.95 },
    border = { 0.090, 0.150, 0.280, 0.70 },
    textColor = { 0.78, 0.87, 0.98, 1 },
    hoverBg = { 0.032, 0.054, 0.096, 0.98 },
    hoverBorder = { 0.140, 0.255, 0.460, 0.86 },
    activeBg = { 0.045, 0.155, 0.405, 0.98 },
    activeBorder = { 0.210, 0.490, 0.920, 0.98 },
    activeTextColor = { 0.94, 0.98, 1.00, 1 },
}
local GROUP_SCOPE_BUTTON_STYLE = {
    bg = { 0.026, 0.040, 0.084, 0.95 },
    border = { 0.095, 0.165, 0.330, 0.68 },
    textColor = { 0.80, 0.88, 0.98, 1 },
    hoverBg = { 0.036, 0.056, 0.108, 0.98 },
    hoverBorder = { 0.150, 0.265, 0.500, 0.86 },
    activeBg = { 0.050, 0.130, 0.315, 0.98 },
    activeBorder = { 0.220, 0.520, 0.960, 0.98 },
    activeTextColor = { 0.96, 0.99, 1.00, 1 },
}
local function ScopeSection(ctx, builder, opts)
    opts = opts or {}
    local priorityMode = opts.priorityMode == true
    local pageW = tonumber(builder.width) or 720
    local pageValues = {}
    for i = 1, #GROUP_PAGE_TABS do
        local tab = GROUP_PAGE_TABS[i]
        pageValues[i] = { value = tab.key, text = tab.label, width = tonumber(tab.width) or 72 }
    end
    local pageOpts = {
        values = pageValues,
        width = pageW,
        maxRight = priorityMode and (pageW - 16) or (pageW - 112),
        label = "Page:",
        labelWidth = 64,
        centerY = priorityMode and -24 or -28,
    }
    local pageMetrics = W.MeasureScopeOverrideBar and W.MeasureScopeOverrideBar(pageValues, pageOpts)
    local pageBottomY = (pageMetrics and pageMetrics.bottomY) or -40
    local scopeCenterY = min(-60, pageBottomY - 20)
    local scopeValues = {}
    if not priorityMode then
        for i = 1, #SCOPE_VALUES do
            local info = SCOPE_VALUES[i]
            scopeValues[i] = {
                value = info.value,
                text = ScopeShortLabel(info.value),
                width = (info.value == "mythicraid") and 86 or 64,
            }
        end
    end
    local scopeMetrics = not priorityMode and W.MeasureScopeOverrideBar and W.MeasureScopeOverrideBar(scopeValues, {
        width = pageW,
        label = "Editing:",
        labelWidth = 64,
        centerY = scopeCenterY,
    })
    local noteY = min(-50, pageBottomY - 10)
    local scopeBottomY = (scopeMetrics and scopeMetrics.bottomY) or -72
    local providerSummaryY = scopeBottomY - 8
    local h = priorityMode
        and max(70, math.abs(noteY) + 20)
        or max(108, math.abs(providerSummaryY) + 24)
    local sec = T.Panel(builder.parent, nil, T.colors.glassStatus or T.colors.header, T.colors.borderSoft)
    T.ApplySurface(sec, "status")
    sec:SetPoint("TOPLEFT", builder.parent, "TOPLEFT", builder.x, builder.y)
    sec:SetSize(pageW, h)
    sec._msuf2Width = pageW
    if W.RegisterGuidedRegion then
        W.RegisterGuidedRegion(ctx, sec, priorityMode and "Priority Frames workspace" or "Party frame and Copy To", "group_scope")
    end
    builder.y = builder.y - h - 8
    if ctx.SetContentHeight then ctx:SetContentHeight(math.abs(builder.y) + 28) end

    local function SelectScope(kind)
        local previousScope = M.gfScope
        M.SetMenuStateValue("gfScope", kind or "party")
        if previousScope ~= M.gfScope and W.CloseTextQuickSettings then W.CloseTextQuickSettings() end
        if previousScope ~= M.gfScope and M.ShowStatusFeedback then M.ShowStatusFeedback(M.Format("%s scope", ScopeShortLabel(M.gfScope)), "info", 1.1) end
        local gf = GF()
        if type(_G.MSUF_GF_EM2_SetActivePreviewKind) == "function" then _G.MSUF_GF_EM2_SetActivePreviewKind(M.gfScope) end
        RequestGFPagePreview()
        if gf and type(gf.PreviewScopeChanged) == "function" then
            gf.PreviewScopeChanged()
        else
            RefreshGFPreview()
        end
        RefreshContext(ctx)
    end
    sec._msuf2GuidedSelectScope = SelectScope

    local command = sec
    pageOpts.getValue = function() return ctx and ctx.key end
    pageOpts.setValue = function(pageKey) if pageKey and pageKey ~= ctx.key then M.SelectPage(pageKey) end end
    local pageBar = W.ScopeOverrideBar(ctx, command, pageOpts)
    RegisterGroupControl(pageBar, ctx, "navigation.section.selector", "Page", "segment", "ephemeral")

    if priorityMode then
        local note = W.Text(sec,
            "Profile-wide · follows the active Party, Raid, or Mythic Raid frame appearance",
            16, noteY, pageW - 32, T.colors.muted)
        if note and note.SetJustifyH then note:SetJustifyH("LEFT") end
        if W.AttachStickyPageHeader then
            W.AttachStickyPageHeader(sec, {
                pageKey = ctx and ctx.key,
                wrapper = ctx and ctx.wrapper,
                gap = 4,
                builder = builder,
                ctx = ctx,
                flowGap = 8,
            })
        end
        return sec
    end

    local copy = (W.RoleButton and W.RoleButton(sec, M.Tr("Copy To"), "success", 86, 24)) or W.TopButton(sec, M.Tr("Copy To"), 86, 24, {})
    copy:SetPoint("TOPRIGHT", sec, "TOPRIGHT", -16, -16)
    local scopeBtns = {}
    local scopeBar = W.ScopeOverrideBar(ctx, command, {
        values = scopeValues,
        width = pageW,
        label = "Editing:",
        labelWidth = 64,
        centerY = scopeCenterY,
        getValue = CurrentScope,
        setValue = SelectScope,
    })
    RegisterGroupControl(scopeBar, ctx, "scope.selector", "Editing", "segment", "ephemeral")
    for i = 1, #SCOPE_VALUES do scopeBtns[SCOPE_VALUES[i].value] = scopeBar and scopeBar.buttons and scopeBar.buttons[i] end
    local providerSummary = W.Text(sec, "", 16, providerSummaryY, pageW - 32, T.colors.muted)
    if providerSummary and providerSummary.SetJustifyH then providerSummary:SetJustifyH("LEFT") end
    M.gfCopyScopes = (type(M.gfCopyScopes) == "table") and M.gfCopyScopes or NewGFCopyScopes()
    local copyPopup = Shared.MakeScopeCopyPopup and Shared.MakeScopeCopyPopup(copy, {
        controlDomain = "group",
        controlPageKey = ctx and ctx.key,
        controlPath = "copy",
        assistantDisposition = "dynamic",
        assistantDispositionReason = "Copy actions depend on the selected Group source, destination, and category set.",
        width = 430,
        height = 334,
        categories = GF_COPY_CATEGORIES,
        scopes = M.gfCopyScopes,
        targets = SCOPE_VALUES,
        targetWidths = { party = 58, raid = 58, mythicraid = 70 },
        sourceKey = CurrentScope,
        sourceLabel = ScopeLabel,
        targetLabelText = ScopeShortLabel,
        isTargetVisible = function(kind, source) return kind ~= source end,
        categoryRowsPerColumn = 6,
        categoryColumnWidth = 205,
        categoryWidth = 150,
        onPopupCreated = function(popup)
            popup._msuf2GuidedNoScroll = true
            if W.RegisterGuidedRegion then W.RegisterGuidedRegion(ctx, popup, "Copy Party settings", "group_copy_popup") end
        end,
        onTargetClick = function(kind, api, popup)
            local function RunCopy()
                if CopyGroupSettings(CurrentScope(), kind, M.gfCopyScopes) then
                    RefreshContext(ctx)
                    if M.ShowStatusFeedback then M.ShowStatusFeedback(M.Format("Copied to %s", ScopeShortLabel(kind)), "ok", 1.3) end
                end
            end
            M.RunWithHistory("Copy Group Settings", "group:copy:" .. tostring(CurrentScope()) .. ":" .. tostring(kind), RunCopy)
            popup:Hide()
        end,
    })
    RegisterGroupControl(copy, ctx, "copy.open", "Copy To", "button", "ephemeral")
    copy:SetScript("OnClick", function(self) if copyPopup then copyPopup.Show(self) end end)
    if type(M.RegisterGuidedCopyPopup) == "function" then
        M.RegisterGuidedCopyPopup("group", ctx.key, function()
            local popup = copyPopup and copyPopup.GetPopup and copyPopup.GetPopup()
            if popup and popup.IsShown and popup:IsShown() then return true end
            if copyPopup then copyPopup.Show(copy) end
            popup = copyPopup and copyPopup.GetPopup and copyPopup.GetPopup()
            return popup and popup.IsShown and popup:IsShown() or false
        end)
    end
    sec:SetScript("OnHide", function() if copyPopup then copyPopup.Hide() end end)
    if W.AttachStickyPageHeader then
        W.AttachStickyPageHeader(sec, {
            pageKey = ctx and ctx.key,
            wrapper = ctx and ctx.wrapper,
            gap = 4,
            builder = builder,
            ctx = ctx,
            flowGap = 8,
        })
    end
    local function RefreshTop()
        local current = CurrentScope()
        for i = 1, #SCOPE_VALUES do
            local info = SCOPE_VALUES[i]
            if scopeBtns[info.value] and scopeBtns[info.value].SetActive then scopeBtns[info.value]:SetActive(current == info.value) end
        end
        if providerSummary then
            providerSummary:SetText(M.Format("Frame providers | Party: %s | Raid: %s | Mythic Raid: %s",
                FrameProviderShortLabel("party"), FrameProviderShortLabel("raid"), FrameProviderShortLabel("mythicraid")))
        end
    end
    M.TrackRefresh(ctx, RefreshTop)
end
local GroupPage = M.GroupPage or {}
M.GroupPage = GroupPage
M.Assign(GroupPage, {
    Conf = Conf, Val = Val, Set = Set, Bool = Bool, Num = Num, CurrentScope = CurrentScope,
    GROUP_FRAME_PROVIDER_VALUES = GROUP_FRAME_PROVIDER_VALUES,
    GROUP_RAID_MANAGER_VALUES = GROUP_RAID_MANAGER_VALUES,
    FrameProvider = FrameProvider, FrameProviderLabel = FrameProviderLabel, FrameProviderShortLabel = FrameProviderShortLabel,
    FrameProviderTooltip = FrameProviderTooltip, SetFrameProvider = SetFrameProvider,
    SyncedVal = SyncedVal, SetSyncedValue = SetSyncedValue,
    RaidManagerMode = RaidManagerMode, SetRaidManagerMode = SetRaidManagerMode,
    GF_COPY_CATEGORIES = GF_COPY_CATEGORIES, NewGFCopyScopes = NewGFCopyScopes, CopyGroupSettings = CopyGroupSettings,
})
local function BindScopeToggle(ctx, widget, key, default, mode, semanticPath)
    M.BindBoolWidget(ctx, widget,
        function() return Bool(CurrentScope(), key, default) end,
        function(v)
            Set(CurrentScope(), key, v and true or false, mode or "visual")
            RefreshContext(ctx)
        end,
        ResolveGroupControlMeta(ctx, semanticPath, "field." .. tostring(key)))
    return widget
end
local function BindScopeSlider(ctx, widget, key, default, mode, semanticPath)
    local metadata = ResolveGroupControlMeta(ctx, semanticPath, "field." .. tostring(key))
    metadata.step, metadata.roundStep = 1, true
    M.BindNumberWidget(ctx, widget,
        function() return Num(CurrentScope(), key, default) end,
        function(v) Set(CurrentScope(), key, floor((tonumber(v) or default or 0) + 0.5), mode or "visual") end,
        default, metadata)
    return widget
end
local function BindScopeDropdown(ctx, widget, key, default, mode, semanticPath)
    M.BindDropdownWidget(ctx, widget,
        function() return Val(CurrentScope(), key, default) end,
        function(v) Set(CurrentScope(), key, v or default, mode or "visual") end,
        ResolveGroupControlMeta(ctx, semanticPath, "field." .. tostring(key)))
    return widget
end
local function ScopeDropdown(ctx, parent, label, values, width, key, default, mode, x, y, placeWidth, justify, semanticPath)
    local control = BindScopeDropdown(ctx, W.Dropdown(parent, label, values, width), key, default, mode, semanticPath)
    if x then W.MoveWidget(control, parent, x, y, placeWidth or width, justify or "LEFT") end
    return control
end
local function ScopeSlider(ctx, parent, label, minValue, maxValue, step, width, key, default, mode, x, y, placeWidth, justify, semanticPath)
    local control = BindScopeSlider(ctx, W.Slider(parent, label, minValue, maxValue, step, width), key, default, mode, semanticPath)
    if x then W.MoveWidget(control, parent, x, y, placeWidth or width, justify or "CENTER") end
    return control
end
local function ScopeColor(ctx, parent, label, width, rKey, gKey, bKey, defaults, mode, x, y, placeWidth, justify, semanticPath)
    local control = W.Color(parent, label)
    defaults = defaults or {}
    M.BindColor(ctx, control,
        function()
            return Num(CurrentScope(), rKey, defaults[1] or 1),
                Num(CurrentScope(), gKey, defaults[2] or 1),
                Num(CurrentScope(), bKey, defaults[3] or 1)
        end,
        function(r, g, b)
            local conf = Conf(CurrentScope())
            conf[rKey], conf[gKey], conf[bKey] = r, g, b
            QueueGF(CurrentScope(), mode or "visual")
        end,
        ResolveGroupControlMeta(ctx, semanticPath, "color." .. tostring(rKey):gsub("[Rr]$", "")))
    if x then W.MoveWidget(control, parent, x, y, placeWidth or width or 220, justify or "LEFT") end
    return control
end

--- Party portrait workspace. Bindings are intentionally fixed to gf_party
--- rather than CurrentScope: the shell is hidden outside Party and Raid/Mythic
--- never receive portrait settings through the dynamic Group binding path.
function GroupPage.BuildPortrait(ctx, builder)
    local kind = "party"
    local cardH = { main = 224, geometry = 440, placement = 382, border = 440, style = 330 }
    local tabH = {
        general = cardH.main + 116,
        geometry = cardH.geometry + 116,
        placement = cardH.placement + 116,
        border = cardH.border + 116,
        advanced = cardH.style + 116,
    }
    local placementValues = {
        modes = VT("ATTACHED", "Attached to bar", "DETACHED", "Detached", "OVERLAY", "Overlay on bar"),
        points = VT(
            "TOPLEFT", "Top left", "TOP", "Top", "TOPRIGHT", "Top right",
            "LEFT", "Left", "CENTER", "Center", "RIGHT", "Right",
            "BOTTOMLEFT", "Bottom left", "BOTTOM", "Bottom", "BOTTOMRIGHT", "Bottom right"),
        overlay = VT("LEFT", "Left", "CENTER", "Center", "RIGHT", "Right", "FULL", "Fill bar"),
        borderArt = VT("FLAT", "Flat", "RELIEF", "Relief"),
        borderDirection = VT("UP", "Up", "RIGHT", "Right", "DOWN", "Down", "LEFT", "Left"),
    }
    local renderValues = VT("2D", "2D portrait", "CLASS", "Class portrait")
    local sizeModeValues = VT("UNIFORM", "Uniform", "SEPARATE", "Width & height")
    local shapeValues = VT("SQUARE", "Square", "CIRCLE", "Circle", "ROUNDED", "Rounded", "DIAMOND", "Diamond")
    local borderValues = VT("NONE", "No border", "SOLID", "Solid", "CLASS_COLOR", "Class color", "REACTION", "Reaction color", "CUSTOM", "Custom color")
    local function ClassStyleValues()
        local media = MSUF and MSUF.PortraitMedia
        local source = media and media.GetPackOptions and media.GetPackOptions()
            or { { value = "BLIZZARD", text = "Blizzard Class Icon" } }
        local values = {}
        for i = 1, #source do
            local item = source[i]
            values[#values + 1] = {
                value = item.value or item.key,
                text = item.text or item.label or item.value or item.key,
            }
        end
        return values
    end
    local function NormalizeTab(value)
        if value ~= "general" and value ~= "geometry" and value ~= "placement"
            and value ~= "border" and value ~= "advanced" then
            return "general"
        end
        return value
    end
    M.unitPortraitTabSelection = M.unitPortraitTabSelection or {}
    local stateKey = "gf_party"
    local currentTab = NormalizeTab(M.unitPortraitTabSelection[stateKey])
    M.unitPortraitTabSelection[stateKey] = currentTab
    local initialHeight = tabH[currentTab] or tabH.general
    local sec = builder:CollapsibleSection("portrait", "Portrait", initialHeight, false)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local cardX = 16
    local cardW = max(260, min(620, sectionW - 32))
    local tabW = max(260, min(780, sectionW - 40))
    local RefreshPortraitControls = M.RefreshProxy()
    local function AttachPortraitFocus(widget)
        W.AttachGroupEditFocus(widget, stateKey, "portrait")
        return widget
    end
    local function PortraitMeta(path, key, extraKeys)
        local meta = GroupControlMeta(ctx, "portrait." .. tostring(path))
        meta.assistantDisposition, meta.assistantDispositionReason = nil, nil
        if key then
            meta.assistantDisposition = "dynamic"
            meta.assistantDispositionReason = "This Party portrait control writes the declared fixed Party setting."
            meta.assistantSettingKeys = { "gf_party." .. tostring(key) }
        end
        if extraKeys then
            meta.assistantDisposition = "dynamic"
            meta.assistantDispositionReason = "This Party portrait RGB swatch writes three persisted color channels as one visible color."
            meta.assistantSettingKeys = extraKeys
        end
        return meta
    end
    local function SetValue(key, value)
        Set(kind, key, value, "config")
        RefreshContext(ctx)
    end
    local function RegisterPreviewOffsetVirtual(axis, key, label)
        if type(M.RegisterVirtualRuntimeControl) ~= "function" then return end
        local path = "preview.selection.portrait_offset_" .. tostring(axis)
        local meta = GroupControlMeta(ctx, path, "setting")
        meta.kind = "textinput"
        meta.label = label
        meta.assistantDisposition = "dynamic"
        meta.assistantDispositionReason = "The lazy Group Preview exact-offset field edits this fixed Party portrait coordinate."
        meta.assistantSettingKeys = { "gf_party." .. tostring(key) }
        meta.command = {
            kind = "textinput",
            historyMode = "single",
            interaction = "preview.handle.offset",
            previewSurface = "group",
            previewHandleKey = "portrait",
            previewScope = "party",
            get = function() return tonumber(Val(kind, key, 0)) or 0 end,
            set = function(value)
                value = tonumber(value)
                if value == nil then return false end
                SetValue(key, value)
                return true
            end,
        }
        M.RegisterVirtualRuntimeControl(meta, "group-preview-offset")
    end
    RegisterPreviewOffsetVirtual("x", "portraitOffsetX", "Party Portrait X Offset")
    RegisterPreviewOffsetVirtual("y", "portraitOffsetY", "Party Portrait Y Offset")
    local function BindDropdown(parent, label, values, x, y, width, key, defaultValue, normalize, after)
        local control = W.Dropdown(parent, label, values, 220)
        W.MoveWidget(control, parent, x, y, width)
        M.BindDropdownWidget(ctx, control,
            function()
                local value = Val(kind, key, defaultValue)
                return normalize and normalize(value) or value
            end,
            function(value)
                value = normalize and normalize(value or defaultValue) or (value or defaultValue)
                SetValue(key, value)
                if after then after() end
            end,
            PortraitMeta(key, key))
        return AttachPortraitFocus(control)
    end
    local function BindNumber(parent, label, x, y, width, minValue, maxValue, step, key, defaultValue, percent, after)
        local control = W.Slider(parent, label, minValue, maxValue, step, 280)
        if percent and M.UsePercentInput then M.UsePercentInput(control) end
        W.MoveWidget(control, parent, x, y, width, "CENTER")
        local meta = PortraitMeta(key, key)
        meta.step, meta.roundStep = step, true
        M.BindNumberWidget(ctx, control,
            function() return Num(kind, key, defaultValue) end,
            function(value)
                SetValue(key, tonumber(value) or defaultValue)
                if after then after() end
            end,
            defaultValue, meta)
        return AttachPortraitFocus(control)
    end
    local function BindToggle(parent, label, x, y, width, key, defaultValue, after)
        local control = W.ToggleAt(parent, label, x, y, width)
        M.BindBoolWidget(ctx, control,
            function() return Bool(kind, key, defaultValue) end,
            function(value)
                SetValue(key, value and true or false)
                if after then after() end
            end,
            PortraitMeta(key, key))
        return AttachPortraitFocus(control)
    end
    local function BindColor(parent, label, x, y, width, prefix, defaults)
        local control = W.Color(parent, label)
        local rKey, gKey, bKey = prefix .. "R", prefix .. "G", prefix .. "B"
        local settingKeys = { "gf_party." .. rKey, "gf_party." .. gKey, "gf_party." .. bKey }
        M.BindColor(ctx, control,
            function()
                return Num(kind, rKey, defaults[1]), Num(kind, gKey, defaults[2]), Num(kind, bKey, defaults[3])
            end,
            function(r, g, b)
                local conf = Conf(kind)
                if conf[rKey] == r and conf[gKey] == g and conf[bKey] == b then return end
                conf[rKey], conf[gKey], conf[bKey] = r, g, b
                QueueGF(kind, "config")
                RefreshContext(ctx)
            end,
            PortraitMeta(prefix, nil, settingKeys))
        W.MoveWidget(control, parent, x, y, width, "LEFT")
        return AttachPortraitFocus(control)
    end
    local function SetSectionHeight(height)
        height = max(120, floor((tonumber(height) or tabH.general) + 0.5))
        local entry = sec and sec._msuf2CollapsibleEntry
        if entry then
            -- The Portrait content builds lazily after its Party-only shell has
            -- already been hidden for Raid/Mythic.  Preserve the desired Party
            -- tab height, but never let that deferred build reactivate space in
            -- a scope where the section is unavailable.
            entry._msufPartyPortraitContentHeight = height
            local appliedHeight = entry._msufPartyPortraitVisible == false and 0 or height
            entry.contentHeight = appliedHeight
            if sec and sec.SetHeight then sec:SetHeight(appliedHeight) end
            if entry.body and entry.body.SetHeight then entry.body:SetHeight(appliedHeight) end
            if entry.outer and entry.outer.SetHeight then
                entry.outer:SetHeight((entry.headerHeight or 28) + (entry.open and appliedHeight or 0))
            end
            if entry.builder and entry.builder.RequestRelayoutCollapsibles then entry.builder:RequestRelayoutCollapsibles() end
        elseif sec and sec.SetHeight then
            sec:SetHeight(height)
        end
    end
    local tabFrames = {}
    local generalTab, geometryTab, placementTab, borderTab, advancedTab =
        Shared.MakeTabFrames(sec, -64, sectionW, tabFrames, "general", "geometry", "placement", "border", "advanced")
    local mainCard = W.ControlCard(generalTab, "Visibility & Mode", nil, cardX, -4, cardW, cardH.main)
    local geometryCard = W.ControlCard(geometryTab, "Geometry", nil, cardX, -4, cardW, cardH.geometry)
    local placementCard = W.ControlCard(placementTab, "Placement", nil, cardX, -4, cardW, cardH.placement)
    local borderCard = W.ControlCard(borderTab, "Shape & Border", nil, cardX, -4, cardW, cardH.border)
    local styleCard = W.ControlCard(advancedTab, "Class & Background", nil, cardX, -4, cardW, cardH.style)
    if W.AttachContextColorReferences then
        W.AttachContextColorReferences(borderCard, { "group.portrait.border" }, {
            title = "Portrait Border Color",
            note = "Configure the Party portrait border color and opacity.",
            historySource = "menu:group-portrait-border-color",
        })
    end
    local narrow = sectionW < 700
    local portraitTabs, RefreshTabs, ReadTab, SetGuidedTab = W.SegmentTabs(ctx, sec, {
        label = "",
        values = narrow
            and VT("general", "General", "placement", "Place", "geometry", "Size", "border", "Border", "advanced", "More")
            or VT("general", "General", "placement", "Placement", "geometry", "Size & Zoom", "border", "Shape & Border", "advanced", "More Options"),
        width = tabW,
        frames = tabFrames,
        defaultTab = "general",
        get = function() return NormalizeTab(M.unitPortraitTabSelection[stateKey]) end,
        set = function(value) M.unitPortraitTabSelection[stateKey] = NormalizeTab(value) end,
        afterRefresh = function(tab) SetSectionHeight(tabH[NormalizeTab(tab)] or tabH.general) end,
        x = 20,
        y = -12,
    })
    if portraitTabs._msuf2Title then portraitTabs._msuf2Title:Hide() end
    AttachPortraitFocus(portraitTabs)
    RegisterGroupControl(portraitTabs, ctx, "portrait.workspace_tab", "Portrait area", "segment", "ephemeral")
    sec._msuf2GuidedSelectTab = function(tab)
        tab = NormalizeTab(tab)
        if type(ReadTab) == "function" and ReadTab() == tab then return true end
        if type(SetGuidedTab) == "function" then SetGuidedTab(tab)
        else
            M.unitPortraitTabSelection[stateKey] = tab
            if type(RefreshTabs) == "function" then RefreshTabs() end
        end
        return type(ReadTab) ~= "function" or ReadTab() == tab
    end
    M._msuf2LastGroupPortraitSide = M._msuf2LastGroupPortraitSide or "LEFT"
    local portraitEnable = W.SwitchAt(mainCard, "Portrait", cardW - 62, -24, 0, "HIDDEN")
    local portraitEnableMeta = PortraitMeta("enabled")
    portraitEnableMeta.assistantDisposition = "compound"
    portraitEnableMeta.assistantDispositionReason =
        "This boolean projection toggles the Party portrait enum between OFF and the remembered LEFT or RIGHT side."
    M.BindBoolWidget(ctx, portraitEnable,
        function() return Val(kind, "portraitMode", "OFF") ~= "OFF" end,
        function(value)
            local mode = Val(kind, "portraitMode", "OFF")
            if value then
                SetValue("portraitMode", M._msuf2LastGroupPortraitSide)
            else
                if mode == "LEFT" or mode == "RIGHT" then M._msuf2LastGroupPortraitSide = mode end
                SetValue("portraitMode", "OFF")
            end
            RefreshPortraitControls()
        end,
        portraitEnableMeta)
    AttachPortraitFocus(portraitEnable)
    local side = W.Segment(mainCard, "Position", VT("LEFT", "Left", "RIGHT", "Right"), min(220, cardW - 32))
    W.MoveWidget(side, mainCard, 16, -62, min(220, cardW - 32))
    M.BindSegment(ctx, side,
        function() return Val(kind, "portraitMode", "OFF") == "RIGHT" and "RIGHT" or "LEFT" end,
        function(value)
            value = value == "RIGHT" and "RIGHT" or "LEFT"
            M._msuf2LastGroupPortraitSide = value
            SetValue("portraitMode", value)
            RefreshPortraitControls()
        end,
        PortraitMeta("position", "portraitMode"))
    AttachPortraitFocus(side)
    local render = BindDropdown(mainCard, "Render", renderValues, 16, -116, min(220, cardW - 32), "portraitRender", "2D", nil, RefreshPortraitControls)
    local shape = BindDropdown(borderCard, "Shape", shapeValues, 16, -58, min(220, cardW - 32), "portraitShape", "SQUARE", nil, RefreshPortraitControls)
    local sizeMode = W.Segment(geometryCard, "Size mode", sizeModeValues, min(360, cardW - 32))
    W.MoveWidget(sizeMode, geometryCard, 16, -62, min(360, cardW - 32))
    M.BindSegment(ctx, sizeMode,
        function()
            local conf = Conf(kind)
            local mode = conf.portraitSizeMode
            if mode == "UNIFORM" or mode == "SEPARATE" then return mode end
            return ((tonumber(conf.portraitWidth) or 0) > 0 or (tonumber(conf.portraitHeight) or 0) > 0)
                and "SEPARATE" or "UNIFORM"
        end,
        function(value)
            SetValue("portraitSizeMode", value == "SEPARATE" and "SEPARATE" or "UNIFORM")
            RefreshPortraitControls()
        end,
        PortraitMeta("portraitSizeMode", "portraitSizeMode"))
    AttachPortraitFocus(sizeMode)
    local size = BindNumber(geometryCard, "Size override", 16, -116, cardW - 58, 0, 128, 1, "portraitSizeOverride", 0)
    local width = BindNumber(geometryCard, "Width override", 16, -170, cardW - 58, 0, 256, 1, "portraitWidth", 0)
    local height = BindNumber(geometryCard, "Height override", 16, -224, cardW - 58, 0, 256, 1, "portraitHeight", 0)
    local zoom = BindNumber(geometryCard, "Portrait zoom", 16, -278, cardW - 58, 100, 200, 1, "portraitZoom", 100)
    local panX = BindNumber(geometryCard, "Zoom center X", 16, -332, cardW - 58, -100, 100, 1, "portraitPanX", 0)
    local panY = BindNumber(geometryCard, "Zoom center Y", 16, -386, cardW - 58, -100, 100, 1, "portraitPanY", 0)
    local placement = BindDropdown(placementCard, "Placement", placementValues.modes, 16, -58, min(220, cardW - 32), "portraitPlacement", "ATTACHED", nil, RefreshPortraitControls)
    placement._msuf2SearchText = "Portrait placement attached detached overlay free position anchor"
    local detachedPoint = BindDropdown(placementCard, "Portrait anchor point", placementValues.points, 16, -112, min(220, cardW - 32), "portraitDetachedPoint", "RIGHT")
    local detachedTo = BindDropdown(placementCard, "Attach to frame point", placementValues.points, 16, -166, min(220, cardW - 32), "portraitDetachedTo", "LEFT")
    local overlayAlign = BindDropdown(placementCard, "Overlay alignment", placementValues.overlay, 16, -220, min(220, cardW - 32), "portraitOverlayAlign", "LEFT")
    local level = BindNumber(placementCard, "Layer offset", 16, -274, cardW - 58, 0, 30, 1, "portraitLevelOffset", 7)
    level._msuf2SearchText = "Portrait layer offset frame level behind in front of bars"
    local alpha = BindNumber(placementCard, "Portrait opacity", 16, -328, cardW - 58, 0, 100, 1, "portraitAlpha", 100)
    local border = BindDropdown(borderCard, "Border", borderValues, 16, -112, min(220, cardW - 32), "portraitBorderStyle", "NONE", nil, RefreshPortraitControls)
    local edgeSoftness = BindNumber(borderCard, "Portrait edge softness", 16, -166, cardW - 58, 0, 30, 2, "portraitEdgeSoftness", 0)
    edgeSoftness._msuf2SearchText = "Portrait edge softness feather fade borderless percent"
    local borderArt = BindDropdown(borderCard, "Border art", placementValues.borderArt, 16, -220, min(220, cardW - 32), "portraitBorderArt", "FLAT", nil, RefreshPortraitControls)
    local direction = BindDropdown(borderCard, "Border direction", placementValues.borderDirection, 16, -274, min(220, cardW - 32), "portraitBorderDirection", "UP")
    local thickness = BindNumber(borderCard, "Border thickness", 16, -328, cardW - 58, 1, 12, 1, "portraitBorderThickness", 2)
    local fill = BindToggle(borderCard, "Fill border into frame gap", 16, -396, cardW - 32, "portraitFillBorder", false)
    local classStyle = BindDropdown(styleCard, "Class portrait style", ClassStyleValues, 16, -58, min(220, cardW - 32), "portraitClassStyle", "BLIZZARD", M.NormalizePortraitClassStyle)
    local background = BindToggle(styleCard, "Portrait background", 16, -112, cardW - 32, "portraitBgEnabled", false, RefreshPortraitControls)
    local backgroundColor = BindColor(styleCard, "Portrait Background Color", 16, -158, min(260, cardW - 32), "portraitBgColor", { 0.05, 0.05, 0.05 })
    local backgroundAlpha = BindNumber(styleCard, "Background opacity", 16, -210, cardW - 58, 0, 1, 0.05, "portraitBgColorA", 0.85, true)
    local castIcon = BindToggle(styleCard, "Show cast spell icon in portrait", 16, -274, cardW - 32, "portraitCastSpellIcon", false)
    castIcon._msuf2SearchText = "Portrait cast spell icon casting channel empower"
    local activeControls = {
        render, shape, sizeMode, size, width, height, placement, level, alpha,
        border, edgeSoftness, background, castIcon,
    }
    local function Active(conf) return (conf.portraitMode or "OFF") ~= "OFF" end
    local function Placed(conf, value)
        return Active(conf) and (conf.portraitPlacement or "ATTACHED") == value
    end
    local function FillsBar(conf)
        return (conf.portraitPlacement or "ATTACHED") == "OVERLAY"
            and (conf.portraitOverlayAlign or "LEFT") == "FULL"
    end
    local function UsesSeparateSize(conf)
        local mode = conf.portraitSizeMode
        if mode == "SEPARATE" then return true end
        if mode == "UNIFORM" then return false end
        return (tonumber(conf.portraitWidth) or 0) > 0 or (tonumber(conf.portraitHeight) or 0) > 0
    end
    RefreshPortraitControls = RefreshPortraitControls(M.BindGateGroup(ctx, function() return Conf(kind) end, {
        { enable = portraitEnable },
        { controls = activeControls, on = Active },
        { controls = side, on = function(conf) return Placed(conf, "ATTACHED") end },
        { controls = { detachedPoint, detachedTo }, on = function(conf) return Placed(conf, "DETACHED") end },
        { controls = overlayAlign, on = function(conf) return Placed(conf, "OVERLAY") end },
        { controls = sizeMode, on = function(conf) return Active(conf) and not FillsBar(conf) end },
        { controls = size, on = function(conf)
            return Active(conf) and not FillsBar(conf) and not UsesSeparateSize(conf)
        end },
        { controls = { width, height }, on = function(conf)
            return Active(conf) and not FillsBar(conf) and UsesSeparateSize(conf)
        end },
        { controls = { zoom, panX, panY }, on = function(conf) return Active(conf) and (conf.portraitRender or "2D") ~= "CLASS" end },
        { controls = edgeSoftness, on = function(conf)
            return Active(conf)
                and (conf.portraitShape or "SQUARE") ~= "BLIZZARD"
                and (conf.portraitBorderStyle or "NONE") == "NONE"
        end },
        { controls = { thickness, borderArt }, on = function(conf) return Active(conf) and (conf.portraitBorderStyle or "NONE") ~= "NONE" end },
        { controls = direction, on = function(conf)
            return Active(conf) and (conf.portraitBorderStyle or "NONE") ~= "NONE"
                and (conf.portraitBorderArt or "FLAT") == "RELIEF"
        end },
        { controls = fill, on = function(conf)
            return Active(conf) and (conf.portraitBorderStyle or "NONE") ~= "NONE"
                and (conf.portraitShape or "SQUARE") == "SQUARE"
                and (conf.portraitBorderArt or "FLAT") ~= "RELIEF"
        end },
        { controls = classStyle, on = function(conf) return Active(conf) and (conf.portraitRender or "2D") == "CLASS" end },
        { controls = { backgroundColor, backgroundAlpha }, on = function(conf) return Active(conf) and conf.portraitBgEnabled == true end },
    }, {
        also = function() SetSectionHeaderStatus(sec, nil) end,
        track = function(c, refresh) return M.TrackCollapsibleRefresh(c, sec, refresh) end,
    }))
    if sec._msufPartyPortraitRefresh then sec._msufPartyPortraitRefresh() end
end

--- Hide and collapse the Portrait shell outside Party without destroying the
--- cached page. Restoring the original geometry makes scope switching cheap
--- and keeps Raid/Mythic controls completely inaccessible.
function GroupPage.PreparePortraitShell(ctx, section)
    local entry = section and section._msuf2CollapsibleEntry
    if not entry then return end
    entry._msufPartyPortraitHeaderHeight = entry._msufPartyPortraitHeaderHeight or entry.headerHeight
    entry._msufPartyPortraitContentHeight = entry._msufPartyPortraitContentHeight or entry.contentHeight
    local function Refresh()
        local shown = CurrentScope() == "party"
        entry._msufPartyPortraitVisible = shown
        if shown then
            entry.headerHeight = entry._msufPartyPortraitHeaderHeight or 28
            entry.contentHeight = entry._msufPartyPortraitContentHeight or entry.contentHeight or 340
            if entry.outer then entry.outer:Show() end
        else
            if (entry.contentHeight or 0) > 0 then entry._msufPartyPortraitContentHeight = entry.contentHeight end
            entry.headerHeight, entry.contentHeight = 0, 0
            if entry.outer then entry.outer:Hide() end
        end
        if entry.body and entry.body.SetHeight then entry.body:SetHeight(entry.contentHeight or 0) end
        if entry.outer and entry.outer.SetHeight then
            entry.outer:SetHeight((entry.headerHeight or 0) + (entry.open and (entry.contentHeight or 0) or 0))
        end
        if entry.builder and entry.builder.RequestRelayoutCollapsibles then entry.builder:RequestRelayoutCollapsibles() end
    end
    section._msufPartyPortraitRefresh = Refresh
    if M.AddRefresherOnce then M.AddRefresherOnce(ctx, "group-party-portrait-shell", Refresh)
    elseif M.AddRefresher then M.AddRefresher(ctx, Refresh) end
    Refresh()
    return Refresh
end

local GROWTH_TILE_VALUES = {
    { value = "DOWN", text = "Down", dx = 0, dy = -1, arrow = "v" },
    { value = "UP", text = "Up", dx = 0, dy = 1, arrow = "^" },
    { value = "RIGHT", text = "Right", dx = 1, dy = 0, arrow = ">" },
    { value = "LEFT", text = "Left", dx = -1, dy = 0, arrow = "<" },
}
local function BuildGrowthDirectionTiles(ctx, section, opts)
    if not section then return nil end
    opts = opts or {}
    local x = opts.x or section._msuf2ContentX or 14
    local y = opts.y or section._msuf2CursorY or -38
    local tileW, tileH, gap = opts.tileWidth or 64, opts.tileHeight or 64, opts.gap or 6
    if opts.advanceCursor ~= false then section._msuf2CursorY = y - tileH - 40 end
    local label = T.Font(section, "GameFontNormalSmall", M.Tr("Growth Direction"), T.colors.accent)
    label:SetPoint("TOPLEFT", section, "TOPLEFT", x, y)
    local holder = CreateFrame("Frame", nil, section)
    holder:SetPoint("TOPLEFT", section, "TOPLEFT", x, y - 20)
    holder:SetSize((tileW * 4) + (gap * 3), tileH)
    holder._msuf2Label = label
    local buttons = {}
    local function SetTileVisual(btn, active, hover)
        if not btn then return end
        if btn.SetBackdropColor then
            if active then
                btn:SetBackdropColor(0.100, 0.180, 0.300, hover and 0.98 or 0.92)
                btn:SetBackdropBorderColor(0.260, 0.620, 1.000, 1.00)
            elseif hover then
                btn:SetBackdropColor(0.115, 0.135, 0.185, 0.95)
                btn:SetBackdropBorderColor(0.380, 0.450, 0.620, 0.95)
            else
                btn:SetBackdropColor(0.045, 0.052, 0.076, 0.92)
                btn:SetBackdropBorderColor(0.190, 0.220, 0.310, 0.85)
            end
        end
        if btn._label then
            if active then
                btn._label:SetTextColor(0.95, 1.00, 1.00, 1)
            else
                btn._label:SetTextColor(0.74, 0.80, 0.90, 0.95)
            end
        end
    end
    local function DrawMiniPreview(btn, info, raidLike)
        if not btn or not info then return end
        btn._cells = btn._cells or {}
        local cols, rows
        if raidLike then
            if info.dy ~= 0 then
                cols, rows = 4, 5
            else
                cols, rows = 5, 4
            end
        elseif info.dy ~= 0 then
            cols, rows = 1, 5
        else
            cols, rows = 5, 1
        end
        local pad = 5
        local labelH = 13
        local innerW = tileW - (pad * 2)
        local innerH = tileH - pad - labelH
        local cellGap = 1
        local cellW = max(3, floor((innerW - ((cols - 1) * cellGap)) / cols))
        local cellH = max(3, floor((innerH - ((rows - 1) * cellGap)) / rows))
        local gridW = (cols * cellW) + ((cols - 1) * cellGap)
        local gridH = (rows * cellH) + ((rows - 1) * cellGap)
        local originX = pad + floor((innerW - gridW) * 0.5 + 0.5)
        local originY = -pad - floor((innerH - gridH) * 0.5 + 0.5)
        local positions = {}
        if info.dy ~= 0 then
            local rowStart, rowEnd, rowStep = 0, rows - 1, 1
            if info.dy == 1 then rowStart, rowEnd, rowStep = rows - 1, 0, -1 end
            for col = 0, cols - 1 do
                for row = rowStart, rowEnd, rowStep do
                    positions[#positions + 1] = { col = col, row = row }
                end
            end
        else
            local colStart, colEnd, colStep = 0, cols - 1, 1
            if info.dx == -1 then colStart, colEnd, colStep = cols - 1, 0, -1 end
            for row = 0, rows - 1 do
                for col = colStart, colEnd, colStep do
                    positions[#positions + 1] = { col = col, row = row }
                end
            end
        end
        for i = 1, #positions do
            local cell = btn._cells[i]
            if not cell then
                cell = btn:CreateTexture(nil, "ARTWORK")
                btn._cells[i] = cell
            end
            local pos = positions[i]
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", btn, "TOPLEFT", originX + (pos.col * (cellW + cellGap)), originY - (pos.row * (cellH + cellGap)))
            cell:SetSize(cellW, cellH)
            if i == 1 then
                cell:SetColorTexture(0.120, 0.950, 0.620, 0.98)
            elseif i <= 4 then
                cell:SetColorTexture(0.220, 0.580, 0.940, 0.78)
            else
                cell:SetColorTexture(0.160, 0.360, 0.640, 0.42)
            end
            cell:Show()
        end
        for i = #positions + 1, #btn._cells do
            btn._cells[i]:Hide()
        end
        if not btn._firstText then
            btn._firstText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            if btn._firstText.SetFont then btn._firstText:SetFont("Fonts\\FRIZQT__.TTF", T.FontSize("micro"), "OUTLINE") end
            btn._firstText:SetText("1")
            btn._firstText:SetTextColor(0, 0, 0, 1)
        end
        local first = positions[1]
        if first then
            btn._firstText:ClearAllPoints()
            btn._firstText:SetPoint("CENTER", btn, "TOPLEFT",
                originX + (first.col * (cellW + cellGap)) + (cellW * 0.5),
                originY - (first.row * (cellH + cellGap)) - (cellH * 0.5))
            btn._firstText:Show()
        end
        if not btn._arrow then
            btn._arrow = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            if btn._arrow.SetFont then btn._arrow:SetFont("Fonts\\FRIZQT__.TTF", T.FontSize("caption"), "OUTLINE") end
            btn._arrow:SetTextColor(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 0.95)
        end
        btn._arrow:SetText(info.arrow)
        btn._arrow:ClearAllPoints()
        if info.dy == -1 then
            btn._arrow:SetPoint("BOTTOM", btn, "BOTTOM", 0, labelH + 1)
        elseif info.dy == 1 then
            btn._arrow:SetPoint("TOP", btn, "TOP", 0, -4)
        elseif info.dx == 1 then
            btn._arrow:SetPoint("RIGHT", btn, "RIGHT", -4, labelH * 0.5)
        else
            btn._arrow:SetPoint("LEFT", btn, "LEFT", 4, labelH * 0.5)
        end
        btn._arrow:Show()
    end
    local function RefreshGrowthTiles()
        local current = Val(CurrentScope(), "growth", "DOWN")
        local raidLike = CurrentScope() ~= "party"
        for i = 1, #GROWTH_TILE_VALUES do
            local info = GROWTH_TILE_VALUES[i]
            local btn = buttons[info.value]
            if btn then
                DrawMiniPreview(btn, info, raidLike)
                SetTileVisual(btn, current == info.value, btn.IsMouseOver and btn:IsMouseOver())
            end
        end
    end
    for i = 1, #GROWTH_TILE_VALUES do
        local info = GROWTH_TILE_VALUES[i]
        local btn = CreateFrame("Button", nil, holder, T.Template and T.Template() or nil)
        btn:SetSize(tileW, tileH)
        btn:SetPoint("TOPLEFT", holder, "TOPLEFT", (i - 1) * (tileW + gap), 0)
        if btn.SetBackdrop then
            btn:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
            })
        end
        local text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        if text.SetFont then text:SetFont("Fonts\\FRIZQT__.TTF", T.FontSize("micro"), "OUTLINE") end
        text:SetPoint("BOTTOM", btn, "BOTTOM", 0, 3)
        text:SetText(info.text)
        btn._label = text
        btn:SetScript("OnEnter", function(self)
            SetTileVisual(self, Val(CurrentScope(), "growth", "DOWN") == info.value, true)
        end)
        btn:SetScript("OnLeave", function(self)
            SetTileVisual(self, Val(CurrentScope(), "growth", "DOWN") == info.value, false)
        end)
        M.AddTooltip(btn, function() return M.Format(M.Tr("Growth: %s"), M.Tr(info.text or "")) end, "Click to set group frame growth direction.", { hook = true, titleAsLine = true, bodyColor = { 0.72, 0.76, 0.86 } })
        btn:SetScript("OnClick", function()
            Set(CurrentScope(), "growth", info.value, "geometry")
            RefreshGrowthTiles()
        end)
        RegisterGroupControl(btn, ctx, "field.growth.option." .. info.value, "Growth: " .. info.text, "button", "setting", {
            assistantDisposition = "dynamic",
            assistantDispositionReason = "This tile edits the growth setting for the currently selected Group scope.",
            assistantSettingKeys = { "gf_party.growth", "gf_raid.growth", "gf_mythicraid.growth" },
            command = {
                kind = "dropdown", valueKind = "enum", values = GROWTH_VALUES,
                get = function() return Val(CurrentScope(), "growth", "DOWN") end,
                set = function(value) Set(CurrentScope(), "growth", value, "geometry"); RefreshGrowthTiles() end,
            },
        })
        buttons[info.value] = btn
    end
    M.TrackRefresh(ctx, RefreshGrowthTiles)
    return holder
end
local ROLE_SORT_DEFS = {
    { key = "TANK", label = "Tank", r = 0.30, g = 0.55, b = 0.85 },
    { key = "HEALER", label = "Healer", r = 0.20, g = 0.72, b = 0.35 },
    { key = "DAMAGER", label = "DPS", r = 0.82, g = 0.30, b = 0.30 },
}
local ROLE_SORT_BY_KEY = {}
for i = 1, #ROLE_SORT_DEFS do
    ROLE_SORT_BY_KEY[ROLE_SORT_DEFS[i].key] = i
end
local ROLE_SORT_VALUES = {
    { value = "TANK,HEALER,DAMAGER", text = "Tank, Healer, DPS" },
    { value = "TANK,DAMAGER,HEALER", text = "Tank, DPS, Healer" },
    { value = "HEALER,TANK,DAMAGER", text = "Healer, Tank, DPS" },
    { value = "HEALER,DAMAGER,TANK", text = "Healer, DPS, Tank" },
    { value = "DAMAGER,TANK,HEALER", text = "DPS, Tank, Healer" },
    { value = "DAMAGER,HEALER,TANK", text = "DPS, Healer, Tank" },
}
local function NormalizeRoleOrder(value)
    if type(value) ~= "string" then return nil end
    local parts, seen = {}, {}
    for token in value:gmatch("[^,]+") do
        token = token:match("^%s*(.-)%s*$"):upper()
        if token == "MELEE" or token == "RANGED" then token = "DAMAGER" end
        if not ROLE_SORT_BY_KEY[token] or seen[token] then return nil end
        seen[token], parts[#parts + 1] = true, token
    end
    if #parts ~= #ROLE_SORT_DEFS then return nil end
    return table.concat(parts, ",")
end
local function BuildRoleOrderRows(ctx, section, opts)
    if not section then return nil end
    opts = opts or {}
    local rowW, rowH, rowGap = opts.width or 220, 22, 4
    local x = opts.x or section._msuf2ContentX or 14
    local y = opts.y or section._msuf2CursorY or -146
    local listY = y
    if opts.hint or opts.title then
        local title = T.Font(section, "GameFontNormalSmall", opts.title or "Role Priority", T.colors.text)
        title:SetPoint("TOPLEFT", section, "TOPLEFT", x, y)
        title:SetWidth(rowW)
        title:SetJustifyH("LEFT")
        local hint = T.Font(section, "GameFontDisableSmall", opts.hint or "Drag roles to reorder.", T.colors.dim)
        hint:SetPoint("TOPLEFT", section, "TOPLEFT", x, y - 16)
        hint:SetWidth(rowW + 80)
        hint:SetJustifyH("LEFT")
        listY = y - 38
    end
    if opts.advanceCursor ~= false then section._msuf2CursorY = listY - (#ROLE_SORT_DEFS * (rowH + rowGap)) - 10 end
    local function NormalizeRoleToken(token)
        if token == "MELEE" or token == "RANGED" then return "DAMAGER" end
        return token
    end
    local holder, rows
    local function CurrentRoleOrder()
        local conf = Conf(CurrentScope())
        return NormalizeRoleOrder(conf.roleOrder) or "TANK,HEALER,DAMAGER"
    end
    local function ApplyRoleOrder(value)
        value = NormalizeRoleOrder(value)
        if not value then return false end
        local kind = CurrentScope()
        Conf(kind).roleOrder = value
        QueueGF(kind, "rebuild")
        return true
    end
    local function SaveOrder()
        local kind = CurrentScope()
        local function WriteOrder()
            local ordered = {}
            for i = 1, #rows do ordered[#ordered + 1] = rows[i] end
            table.sort(ordered, function(a, b) return (a.slotIndex or 0) < (b.slotIndex or 0) end)
            local parts = {}
            for i = 1, #ordered do parts[#parts + 1] = ordered[i].key end
            ApplyRoleOrder(table.concat(parts, ","))
        end
        M.RunWithHistory("Role Priority Order", "group:roleOrder:" .. tostring(kind), WriteOrder)
    end
    local function LoadOrder()
        local order = CurrentRoleOrder()
        local slot = 0
        local assigned = {}
        for token in order:gmatch("[^,]+") do
            token = NormalizeRoleToken(token)
            local index = ROLE_SORT_BY_KEY[token]
            if index and not assigned[index] then
                slot = slot + 1
                rows[index].slotIndex = slot
                assigned[index] = true
            end
        end
        for i = 1, #rows do
            if not assigned[i] then
                slot = slot + 1
                rows[i].slotIndex = slot
            end
        end
        holder:SnapRows()
    end
    holder = Shared.MakeDragSortRows(section, ROLE_SORT_DEFS, {
        x = x, y = listY, width = rowW, rowHeight = rowH, gap = rowGap,
        controlDomain = "group",
        controlPageKey = ctx and ctx.key,
        controlPath = "sorting.role_priority",
        controlClassification = "setting",
        assistantDisposition = "dynamic",
        assistantDispositionReason = "Role-priority rows reorder the selected Group scope as one ordered value.",
        assistantSettingKeys = { "gf_party.roleOrder", "gf_raid.roleOrder", "gf_mythicraid.roleOrder" },
        controlCommand = {
            kind = "dragrow",
            source = "group/sorting/role_priority",
            valueKind = "enum",
            values = ROLE_SORT_VALUES,
            get = CurrentRoleOrder,
            set = function(value)
                local changed = ApplyRoleOrder(value)
                if changed and holder and holder.Refresh then holder.Refresh() end
                return changed
            end,
            canExecute = function()
                local scope = CurrentScope()
                return scope == "party" or scope == "raid" or scope == "mythicraid"
            end,
        },
        onReorder = SaveOrder,
        tooltip = function(self, row, tip)
            tip:SetOwner(self, "ANCHOR_RIGHT")
            tip:AddLine(M.Tr((row and row.def and row.def.label) or ""), 1, 1, 1)
            tip:AddLine(M.Tr("Drag to change role priority."), 0.72, 0.76, 0.86)
            tip:Show()
        end,
    })
    rows = holder.rows
    holder.Refresh = LoadOrder
    M.TrackRefresh(ctx, LoadOrder)
    holder:SetRowsEnabled(false)
    return holder
end
local function AurasRoot(kind)
    local conf = Conf(kind)
    conf.auras = conf.auras or {}
    if conf.auras.renderer ~= "CUSTOM" then conf.auras.renderer = "CUSTOM" end
    conf.auras.blizzardTypes = conf.auras.blizzardTypes or {}
    conf.auras.buff = conf.auras.buff or {}
    conf.auras.debuff = conf.auras.debuff or {}
    conf.auras.externals = conf.auras.externals or {}
    return conf.auras
end
local function AuraGroup(kind, groupKey)
    local root = AurasRoot(kind)
    root[groupKey] = root[groupKey] or {}
    return root[groupKey]
end
local function SpellIndicators(kind)
    local conf = Conf(kind)
    if type(conf.spellIndicators) ~= "table" then conf.spellIndicators = { enabled = false, spec = "auto", specs = {}, layer = 9, strata = "AUTO", iconZoom = 100, iconScale = 100 } end
    conf.spellIndicators.specs = conf.spellIndicators.specs or {}
    if conf.spellIndicators.strata == nil then conf.spellIndicators.strata = "AUTO" end
    if conf.spellIndicators.iconZoom == nil then conf.spellIndicators.iconZoom = 100 end
    if conf.spellIndicators.iconScale == nil then conf.spellIndicators.iconScale = 100 end
    local gf = GF()
    if gf and type(gf.EnsureSpellIndicatorStyle) == "function" then gf.EnsureSpellIndicatorStyle(conf) end
    return conf.spellIndicators
end
local function IconStyleValues()
    local gf = GF()
    if gf and type(gf.ICON_STYLE_ITEMS) == "table" then return gf.ICON_STYLE_ITEMS end
    return VT(
        "BLIZZARD", "Blizzard (Default)", "CLASSIC", "Classic", "MIDNIGHT", "Midnight",
        "UXPRO", "UX Pro", "GLOSSY_ORBS", "Glossy Orbs", "DARK_EMBOSS", "Dark Emboss", "GLASS_PANELS", "Glass Panels",
        "NEON_OUTLINE", "Neon Outline", "RING_SYMBOLS", "Ring Symbols", "DOTS", "Dots",
        "SHAPES", "Shapes", "DIAMONDS", "Diamonds", "SQUARES", "Squares")
end
local function CurrentGFStatusSpec()
    if not M.gfStatusIconSelection then M.SetMenuStateValue("gfStatusIconSelection", "roleIcon") end
    for i = 1, #GF_STATUS_ICON_SPECS do
        local spec = GF_STATUS_ICON_SPECS[i]
        if spec.value == M.gfStatusIconSelection then return spec end
    end
    M.SetMenuStateValue("gfStatusIconSelection", GF_STATUS_ICON_SPECS[1].value)
    return GF_STATUS_ICON_SPECS[1]
end
local function QueueSpellIndicators(kind, mode)
    local gf = GF()
    local si = gf and gf.SpellIndicators
    if si and type(si.InvalidateRuntimeCaches) == "function" then si.InvalidateRuntimeCaches() end
    QueueGF(kind or CurrentScope(), mode or "visual")
end
local spellSpecIconCache = {}
local function SpellSpecIcon(info)
    if type(info) ~= "table" then return nil end
    if info.icon then return info.icon end
    local specID = tonumber(info.specID)
    if not specID then return nil end
    local cached = spellSpecIconCache[specID]
    if cached then return cached end
    local getInfo = _G.GetSpecializationInfoForSpecID or _G.GetSpecializationInfoByID
    if type(getInfo) ~= "function" then return nil end
    local icon = select(4, getInfo(specID))
    if icon then spellSpecIconCache[specID] = icon end
    return icon
end
local function SpellSpecOption(specKey, info)
    return {
        value = specKey,
        text = (info and info.display) or tostring(specKey),
        icon = SpellSpecIcon(info),
    }
end
local function SpellSpecValues()
    local values = VT("auto", "Auto-Detect", "multi", "Multi-Spec")
    local gf = GF()
    local si = gf and gf.SpellIndicators
    if si and type(si.SpecInfo) == "table" then
        local specs = {}
        for specKey, info in pairs(si.SpecInfo) do
            if type(info) ~= "table" or info.customOnly ~= true then
                specs[#specs + 1] = SpellSpecOption(specKey, info)
            end
        end
        table.sort(specs, function(a, b)
            local left, right = tostring(a.text), tostring(b.text)
            if left ~= right then return left < right end
            return tostring(a.value) < tostring(b.value)
        end)
        for i = 1, #specs do values[#values + 1] = specs[i] end
    end
    return values
end
local function SpellTrackedSpecValues()
    local values = {}
    local gf = GF()
    local si = gf and gf.SpellIndicators
    if si and type(si.SpecInfo) == "table" then
        for specKey, info in pairs(si.SpecInfo) do
            values[#values + 1] = SpellSpecOption(specKey, info)
        end
        table.sort(values, function(a, b) return tostring(a.text) < tostring(b.text) end)
    end
    if #values == 0 then values[1] = { value = "", text = "No supported specs", disabled = true } end
    return values
end
local function IsAllSpecsSpellSpec(specKey)
    local gf = GF()
    local si = gf and gf.SpellIndicators
    local info = specKey and si and si.SpecInfo and si.SpecInfo[specKey]
    return type(info) == "table" and info.universal == true
end
local function CurrentSpellMultiSpec(kind)
    M.gfSpellMultiSpecSelection = M.gfSpellMultiSpecSelection or {}
    local selected = M.gfSpellMultiSpecSelection[kind]
    local values = SpellTrackedSpecValues()
    for i = 1, #values do
        if values[i].value == selected then return selected end
    end
    selected = values[1] and values[1].value or ""
    M.gfSpellMultiSpecSelection[kind] = selected
    return selected
end
local function EffectiveSpellSpec(kind)
    local cfg = SpellIndicators(kind)
    local selected = cfg.spec or "auto"
    local gf = GF()
    local si = gf and gf.SpellIndicators
    if selected ~= "auto" and selected ~= "multi" and si and si.SpecInfo and si.SpecInfo[selected] then return selected end
    if selected == "multi" then
        local chosen = CurrentSpellMultiSpec(kind)
        if chosen and si and si.SpecInfo and si.SpecInfo[chosen] then return chosen end
        if type(cfg.multiSpecs) == "table" then
            for specKey, enabled in pairs(cfg.multiSpecs) do
                if enabled and si and si.SpecInfo and si.SpecInfo[specKey] then return specKey end
            end
        end
    end
    if si and type(si.GetPlayerSpec) == "function" then
        local specKey = si.GetPlayerSpec()
        if specKey and si.SpecInfo and si.SpecInfo[specKey] then return specKey end
    end
    if si and type(si.SpecInfo) == "table" then
        for specKey in pairs(si.SpecInfo) do return specKey end
    end
    return nil
end
local function SpellAuraValues(kind)
    local gf = GF()
    local si = gf and gf.SpellIndicators
    local specKey = EffectiveSpellSpec(kind)
    local trackable = specKey and si and si.TrackableAuras and si.TrackableAuras[specKey]
    local siCfg = SpellIndicators(kind)
    local specCfg = type(siCfg.specs) == "table" and specKey and siCfg.specs[specKey] or nil
    local values = {}
    if type(trackable) == "table" then
        for i = 1, #trackable do
            local info = trackable[i]
            local key = info and info.name
            if key and (info.custom ~= true or (type(specCfg) == "table" and specCfg[key] ~= nil)) then
                local icon = info.icon
                if not icon and type(si.GetAuraIcon) == "function" then
                    icon = si.GetAuraIcon(specKey, key)
                end
                values[#values + 1] = { value = key, text = info.display or key, icon = icon }
            end
        end
    end
    if #values == 0 then values[1] = { value = "", text = "No spells for current spec", disabled = true } end
    return values
end
local function SpellSelectionKey(kind, specKey)
    return tostring(kind or "") .. "\030" .. tostring(specKey or "")
end
local function SetCurrentSpellAura(kind, auraName, specKey)
    M.gfSpellIndicatorSelection = M.gfSpellIndicatorSelection or {}
    specKey = specKey or EffectiveSpellSpec(kind)
    if specKey then M.gfSpellIndicatorSelection[SpellSelectionKey(kind, specKey)] = auraName or "" end
    M.gfSpellIndicatorSelection[kind] = auraName or ""
end
local function ClearCurrentSpellAura(kind, specKey)
    M.gfSpellIndicatorSelection = M.gfSpellIndicatorSelection or {}
    specKey = specKey or EffectiveSpellSpec(kind)
    if specKey then M.gfSpellIndicatorSelection[SpellSelectionKey(kind, specKey)] = nil end
    M.gfSpellIndicatorSelection[kind] = nil
end
local function CurrentSpellAura(kind)
    M.gfSpellIndicatorSelection = M.gfSpellIndicatorSelection or {}
    local specKey = EffectiveSpellSpec(kind)
    local selected = specKey and M.gfSpellIndicatorSelection[SpellSelectionKey(kind, specKey)] or nil
    if selected == nil and not specKey then selected = M.gfSpellIndicatorSelection[kind] end
    local values = SpellAuraValues(kind)
    for i = 1, #values do
        if values[i].value == selected then
            if specKey then M.gfSpellIndicatorSelection[SpellSelectionKey(kind, specKey)] = selected end
            return selected
        end
    end
    selected = values[1] and values[1].value or ""
    if specKey then M.gfSpellIndicatorSelection[SpellSelectionKey(kind, specKey)] = selected end
    M.gfSpellIndicatorSelection[kind] = selected
    return selected
end
local function CurrentSpellConfig(kind, create)
    local specKey = EffectiveSpellSpec(kind)
    local auraName = CurrentSpellAura(kind)
    if not (specKey and auraName and auraName ~= "") then return nil end
    local cfg = SpellIndicators(kind)
    cfg.specs[specKey] = cfg.specs[specKey] or {}
    if create and type(cfg.specs[specKey][auraName]) ~= "table" then
        -- Copy the SpecDefaults shape when materializing so the first write to
        -- a defaults-only spell keeps its square/bar/frame layout instead of
        -- collapsing it to the generic icon entry.
        local gf = GF()
        local registry = gf and gf.SpellIndicators
        if registry and type(registry.MaterializeAuraConfig) == "function" then
            registry.MaterializeAuraConfig(cfg, specKey, auraName)
        else
            cfg.specs[specKey][auraName] = { enabled = true, onlyOwn = true }
        end
    end
    return cfg.specs[specKey][auraName], specKey, auraName
end
local function PlacedConfig(kind, create)
    local cfg = CurrentSpellConfig(kind, create)
    if not cfg then return nil end
    if create and type(cfg.placed) ~= "table" then cfg.placed = { type = "icon", anchor = "TOPLEFT", x = 0, y = 0, size = 18, showCooldownSwipe = true } end
    return cfg.placed
end
local function FrameEffectConfig(kind, create)
    local cfg = CurrentSpellConfig(kind, create)
    if not cfg then return nil end
    if create and type(cfg.frame) ~= "table" then cfg.frame = { type = "none", layer = 0, strata = "AUTO" } end
    return cfg.frame
end
local function CICategoryValues()
    local gf = GF()
    if gf and type(gf.CI_CATEGORIES) == "table" then return gf.CI_CATEGORIES end
    return VT("none", "None", "dispel", "Dispellable", "aggro", "Aggro/Threat", "custom", "Custom Spell")
end
local function CIFilterValues()
    local gf = GF()
    if gf and type(gf.CI_CUSTOM_FILTERS) == "table" then return gf.CI_CUSTOM_FILTERS end
    return VT(
        "HELPFUL|PLAYER", "Buff (cast by me)", "HELPFUL", "Buff (any caster)",
        "HARMFUL|PLAYER", "Debuff (cast by me)", "HARMFUL", "Debuff (any caster)")
end
local function CIModeValues()
    local gf = GF()
    if gf and type(gf.CI_CUSTOM_MODES) == "table" then return gf.CI_CUSTOM_MODES end
    return VT("present", "Show when present", "missing", "Show when missing")
end
local function CurrentCISlot()
    if not M.gfCornerSlotSelection then M.SetMenuStateValue("gfCornerSlotSelection", "TL") end
    for i = 1, #CI_SLOT_VALUES do
        if CI_SLOT_VALUES[i].value == M.gfCornerSlotSelection then return M.gfCornerSlotSelection end
    end
    M.SetMenuStateValue("gfCornerSlotSelection", "TL")
    return "TL"
end
local function CICustomConfig(kind, slot, create)
    local conf = Conf(kind)
    local key = "ciCustom" .. (slot or CurrentCISlot())
    if create and type(conf[key]) ~= "table" then conf[key] = { spells = "", mode = "present", filter = "HELPFUL|PLAYER", r = 0.40, g = 1.00, b = 0.40 } end
    return type(conf[key]) == "table" and conf[key] or nil
end
local function BindNestedToggle(ctx, widget, getTable, key, default, mode, semanticPath)
    M.BindBoolWidget(ctx, widget,
        function()
            local tbl = getTable()
            local value = tbl[key]
            if value == nil then return default and true or false end
            return value and true or false
        end,
        function(v)
            local tbl = getTable()
            if tbl[key] == (v and true or false) then return end
            tbl[key] = v and true or false
            QueueGF(CurrentScope(), mode or "visual")
            RefreshContext(ctx)
        end,
        ResolveGroupControlMeta(ctx, semanticPath, "nested." .. tostring(key)))
    return widget
end
local function BindNestedSlider(ctx, widget, getTable, key, default, mode, semanticPath)
    local metadata = ResolveGroupControlMeta(ctx, semanticPath, "nested." .. tostring(key))
    metadata.step, metadata.roundStep = 1, true
    M.BindNumberWidget(ctx, widget,
        function()
            local tbl = getTable()
            return tonumber(tbl[key]) or default or 0
        end,
        function(v)
            local tbl = getTable()
            v = floor((tonumber(v) or default or 0) + 0.5)
            if tbl[key] == v then return end
            tbl[key] = v
            QueueGF(CurrentScope(), mode or "visual")
        end,
        default, metadata)
    return widget
end
local function BindNestedStrataSlider(ctx, widget, getTable, key, default, mode, semanticPath)
    default = NormalizeFrameStrata(default, "AUTO")
    if widget and widget.SetValueFormatter then widget:SetValueFormatter(function(value) return FrameStrataLabel(value) end) end
    if widget and widget.SetValueParser then widget:SetValueParser(FrameStrataParse) end
    M.BindSlider(ctx, widget,
        function()
            local tbl = getTable()
            return FrameStrataIndex(tbl and tbl[key] or default)
        end,
        function(v)
            local tbl = getTable()
            if not tbl then return end
            local value = FrameStrataValue(v)
            if NormalizeFrameStrata(tbl[key], default) == value and tbl[key] ~= nil then return end
            tbl[key] = value
            QueueGF(CurrentScope(), mode or "visual")
        end,
        ResolveGroupControlMeta(ctx, semanticPath, "nested." .. tostring(key)))
    return widget
end
local function BindNestedDropdown(ctx, widget, getTable, key, default, mode, semanticPath)
    M.BindDropdownWidget(ctx, widget,
        function()
            local tbl = getTable()
            return tbl[key] or default
        end,
        function(v)
            local tbl = getTable()
            tbl[key] = v or default
            QueueGF(CurrentScope(), mode or "visual")
        end,
        ResolveGroupControlMeta(ctx, semanticPath, "nested." .. tostring(key)))
    return widget
end
local SetOptionEnabled = W.SetControlEnabled
local SetOptionsEnabled = W.SetControlsEnabled
local function ForEachGroupPageControl(parent, callback)
    if not (parent and parent.GetChildren and type(callback) == "function") then return end
    local children = { parent:GetChildren() }
    for i = 1, #children do
        local child = children[i]
        if child and child._msuf2ControlKind and not child._msuf2GroupFrameGateAlwaysEnabled then callback(child) end
        ForEachGroupPageControl(child, callback)
    end
end
ApplyScopeEnabledGate = function(ctx)
    local wrapper = ctx and ctx.wrapper
    if not wrapper then return end
    local gateKey = "groupFrameEnabled"
    if ControlGates.Apply then
        ControlGates.Apply(wrapper, gateKey, true, { alwaysEnabledFlag = "_msuf2GroupFrameGateAlwaysEnabled" })
        return
    end
    local enabled = true
    if wrapper._msuf2GroupFrameGateKey == gateKey and wrapper._msuf2GroupFrameGateEnabled == enabled then return end
    wrapper._msuf2GroupFrameGateKey = gateKey
    wrapper._msuf2GroupFrameGateEnabled = enabled
    ForEachGroupPageControl(wrapper, function(control)
        W.SetControlGateEnabled(control, gateKey, enabled)
    end)
end
M.Assign(GroupPage, {
    SCOPE_VALUES = SCOPE_VALUES,
    GROWTH_VALUES = GROWTH_VALUES,
    BLIZZARD_FALLBACK_VALUES = BLIZZARD_FALLBACK_VALUES,
    GROUP_FRAME_PROVIDER_VALUES = GROUP_FRAME_PROVIDER_VALUES,
    HEALTH_MODES = HEALTH_MODES,
    TEXT_MODES = TEXT_MODES,
    HEALTH_TEXT_MODES = HEALTH_TEXT_MODES,
    DELIMITER_VALUES = DELIMITER_VALUES,
    ANCHORS = ANCHORS,
    AURA_ANCHORS = AURA_ANCHORS,
    SORT_MODES = SORT_MODES,
    GF_BAR_MODES = GF_BAR_MODES,
    SIMPLE_TEXTURES = SIMPLE_TEXTURES,
    GF_ANCHOR_TO = GF_ANCHOR_TO,
    GF_ANCHOR_POINTS = GF_ANCHOR_POINTS,
    STATUS_ICON_ANCHORS = STATUS_ICON_ANCHORS,
    GF_STATUS_ICON_SPECS = GF_STATUS_ICON_SPECS,
    GF_STATUS_ICON_VALUES = GF_STATUS_ICON_VALUES,
    PLACED_INDICATOR_TYPES = PLACED_INDICATOR_TYPES,
    FRAME_EFFECT_TYPES = FRAME_EFFECT_TYPES,
    ICON_EFFECT_TYPES = ICON_EFFECT_TYPES,
    SPELL_GROWTH_VALUES = SPELL_GROWTH_VALUES,
    CI_SLOT_VALUES = CI_SLOT_VALUES,
    CI_SLOT_DEFAULTS = CI_SLOT_DEFAULTS,
    DISPEL_OVERLAY_STYLES = DISPEL_OVERLAY_STYLES,
    DEBUFF_STRIPE_EDGES = DEBUFF_STRIPE_EDGES,
    GF = GF,
    ControlMeta = GroupControlMeta,
    RegisterControl = RegisterGroupControl,
    RefreshGFPreview = RefreshGFPreview,
    QueueGF = QueueGF,
    QueueGFDirtyMask = QueueGFDirtyMask,
    RefreshContext = RefreshContext,
    ScopeSection = ScopeSection,
    BindScopeToggle = BindScopeToggle,
    BindScopeSlider = BindScopeSlider,
    BindScopeDropdown = BindScopeDropdown,
    ScopeDropdown = ScopeDropdown,
    ScopeSlider = ScopeSlider,
    ScopeColor = ScopeColor,
    BuildGrowthDirectionTiles = BuildGrowthDirectionTiles,
    BuildRoleOrderRows = BuildRoleOrderRows,
    AuraGroup = AuraGroup,
    AurasRoot = AurasRoot,
    SpellIndicators = SpellIndicators,
    IconStyleValues = IconStyleValues,
    CurrentGFStatusSpec = CurrentGFStatusSpec,
    QueueSpellIndicators = QueueSpellIndicators,
    SpellSpecValues = SpellSpecValues,
    SpellTrackedSpecValues = SpellTrackedSpecValues,
    IsAllSpecsSpellSpec = IsAllSpecsSpellSpec,
    CurrentSpellMultiSpec = CurrentSpellMultiSpec,
    EffectiveSpellSpec = EffectiveSpellSpec,
    SpellAuraValues = SpellAuraValues,
    SetCurrentSpellAura = SetCurrentSpellAura,
    ClearCurrentSpellAura = ClearCurrentSpellAura,
    CurrentSpellAura = CurrentSpellAura,
    CurrentSpellConfig = CurrentSpellConfig,
    PlacedConfig = PlacedConfig,
    FrameEffectConfig = FrameEffectConfig,
    CICategoryValues = CICategoryValues,
    CIFilterValues = CIFilterValues,
    CIModeValues = CIModeValues,
    CurrentCISlot = CurrentCISlot,
    CICustomConfig = CICustomConfig,
    BindNestedToggle = BindNestedToggle,
    BindNestedSlider = BindNestedSlider,
    BindNestedStrataSlider = BindNestedStrataSlider,
    BindNestedDropdown = BindNestedDropdown,
    FrameStrataIndex = FrameStrataIndex,
    FrameStrataValue = FrameStrataValue,
    FrameStrataLabel = FrameStrataLabel,
    FrameStrataParse = FrameStrataParse,
    FrameStrataCount = FRAME_STRATA_COUNT,
    SetOptionEnabled = SetOptionEnabled,
    SetOptionsEnabled = SetOptionsEnabled,
    ApplyScopeEnabledGate = ApplyScopeEnabledGate,
    FinalizeScopePage = FinalizeScopePage,
    SetSectionHeaderStatus = SetSectionHeaderStatus,
    SetSectionBadges = SetSectionBadges,
    SetSectionBadgesAndStatus = SetSectionBadgesAndStatus,
    TrackSectionRefresh = TrackSectionRefresh,
    OnOffBadge = OnOffBadge,
    BadgeNumber = BadgeNumber,
    OptionText = OptionText,
    CreateSectionNotice = CreateSectionNotice,
})
