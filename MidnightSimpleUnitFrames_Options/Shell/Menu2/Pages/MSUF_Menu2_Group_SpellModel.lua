local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

-- Menu2 Group page spell/corner indicator model.
-- Owns the frame-strata helpers, the nested Spell Indicator and Corner Indicator config
-- readers, and the nested-table binders shared by the Group Auras and Indicators pages.
-- Split from MSUF_Menu2_Group.lua: it loads right after that page and publishes through
-- M.GroupPage, so the later Group pages keep picking the same names from one table.
local VT = M.ValueTextList
local floor = math.floor
local GroupPage = M.GroupPage or {}
M.GroupPage = GroupPage
local GF, Conf, QueueGF, CurrentScope, RefreshContext = GroupPage.GF, GroupPage.Conf, GroupPage.QueueGF, GroupPage.CurrentScope, GroupPage.RefreshContext
local ResolveGroupControlMeta = GroupPage.ResolveControlMeta
local GF_STATUS_ICON_SPECS = GroupPage.GF_STATUS_ICON_SPECS or {}
local CI_SLOT_VALUES = GroupPage.CI_SLOT_VALUES or {}
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
local NormalizeFrameStrata = _G.MSUF_NormalizeFrameStrata
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
M.Assign(GroupPage, {
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
})
