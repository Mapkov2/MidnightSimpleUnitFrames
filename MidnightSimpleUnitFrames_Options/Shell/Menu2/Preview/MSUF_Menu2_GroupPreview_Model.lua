-- Group preview model owner.
local _, MSUF = ...
local M = MSUF.MSUF2
local RequireFields = M.PreviewContracts.RequireFields
local Specs = M.GroupPreviewSpecs
local PreviewHelpers = M.PreviewHelpers
local Fallbacks = M.Fallbacks
local WHITE8X8 = Specs.WHITE8X8
local Tr = M.Tr
local floor = math.floor

local ResolveIconTexturePath = MSUF.Require("MSUF_ResolveIconTexturePath", "Menu2/GroupPreview_Model")
local GF_PREVIEW_ROLE_DEFAULT = Specs.ROLE or "HEALER"
local SECTION_PAGE, PAGE_FOCUS, GF_PREVIEW_ANCHOR_FRAC = Specs.SECTION_PAGE or {}, Specs.PAGE_FOCUS or {}, Specs.ANCHOR_FRAC or {}
local GF_AURA_GROWTH_TABLE, GF_STATUS_RUNTIME_KEYS = Specs.AURA_GROWTH_TABLE or {}, Specs.STATUS_RUNTIME_KEYS or {}
-- The threat text's compiled group entry (Classic Era, TBC and WoW Forever only).
-- Added here rather than in the specs file, which stays a plain Retail copy.
GF_STATUS_RUNTIME_KEYS.threatText = "threat"
if not GF_AURA_GROWTH_TABLE.RIGHTDOWN then GF_AURA_GROWTH_TABLE.RIGHTDOWN = { px = 1, py = 0, sx = 0, sy = -1 } end
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
        metrics.base, metrics.conf, metrics.preview = base, Conf(kind), true
        local spec = gf.ComputeFrameOverlay(kind, PreviewRole(kind), metrics)
        spec._msufMenu2PreviewRuntime = true
        return spec
    end
    return nil
end
local function PreviewAllSpecSpellIcons(kind)
    local state = M.gfPreviewAllSpecSpellIcons
    return type(state) == "table" and state[kind or CurrentScope()] == true
end
-- The Animate and Role pills share one frame recipe: backdrop, centred label, pill style, level above the stage.
local SCOPE_LABELS = { raid = "Raid", mythicraid = "Mythic Raid" }
local function PreviewScopeLabel(kind)
    return SCOPE_LABELS[kind] or "Party"
end
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

M.GroupPreviewModel = {
    CurrentScope = CurrentScope,
    Conf = Conf,
    PreviewRole = PreviewRole,
    SetPreviewRole = SetPreviewRole,
    NextPreviewRole = NextPreviewRole,
    GF_PREVIEW_ROLE_LABELS = GF_PREVIEW_ROLE_LABELS,
    GF_PREVIEW_ROLE_DEFAULT = GF_PREVIEW_ROLE_DEFAULT,
    PreviewAllSpecSpellIcons = PreviewAllSpecSpellIcons,
    PreviewScopeLabel = PreviewScopeLabel,
    ClassColor = ClassColor,
    CompiledSpec = CompiledSpec,
    AuraGrowth = AuraGrowth,
    CompiledAuraLane = CompiledAuraLane,
    RuntimeStatusConfig = RuntimeStatusConfig,
    Int = Int,
    MockSpellTexture = MockSpellTexture,
    CurrentSpellInfo = CurrentSpellInfo,
    CurrentSpellConfig = CurrentSpellConfig,
    CurrentSpellPlaced = CurrentSpellPlaced,
    CurrentSpellTexture = CurrentSpellTexture,
    CurrentSpellColor = CurrentSpellColor,
    Round = Round,
    ScaleValue = ScaleValue,
    ConfigToOffset = ConfigToOffset,
    OffsetToConfig = OffsetToConfig,
    ResolveAnchor = ResolveAnchor,
    HandleOffset = HandleOffset,
    PointOffset = PointOffset,
    MockPowerHeight = MockPowerHeight,
    ClampLayer = ClampLayer,
    StatusSpecs = StatusSpecs,
    CurrentStatusSpec = CurrentStatusSpec,
    StatusSpecIsText = StatusSpecIsText,
    StatusText = StatusText,
    StatusLabel = StatusLabel,
    StatusPreviewMode = StatusPreviewMode,
    StatusSpecEnabled = StatusSpecEnabled,
    StatusSpecInMode = StatusSpecInMode,
}
