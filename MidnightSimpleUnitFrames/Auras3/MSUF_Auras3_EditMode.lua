--- Auras3/MSUF_Auras3_EditMode.lua
---
--- This file intentionally does not own live aura objects and does not add
--- per-aura render callbacks. It owns only edit-mode fake previews, drag
--- movement, and config refresh bridges.
---
--- Edit-mode state is visual and coldpath. Dragging writes layout offsets to
--- the Auras3 DB through the same shape that Menu_Model uses, then asks runtime
--- frames to refresh. Keep live aura payload handling inside the native runtime.
local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local type, tonumber, tostring, pairs = type, tonumber, tostring, pairs
local math_floor, math_min, math_max, math_ceil, math_abs = math.floor, math.min, math.max, math.ceil, math.abs
local CreateFrame = _G.CreateFrame
local UIParent = _G.UIParent
local GetCursorPosition = _G.GetCursorPosition
local IsMouseButtonDown = _G.IsMouseButtonDown
local InCombatLockdown = _G.InCombatLockdown
local C_Timer = _G.C_Timer
local issecretvalue = _G.issecretvalue
local TextureKitConstants = _G.TextureKitConstants

-- SetOnUpdateMode takes an Enum.OnUpdateMode value, not a name; a string argument leaves the
-- driver disabled and silently kills the drag OnUpdate.
local Enum = _G.Enum
local ONUPDATE_MODE_DISABLED = (Enum and Enum.OnUpdateMode and Enum.OnUpdateMode.Disabled) or 0
local ONUPDATE_MODE_RUN_WHEN_VISIBLE = (Enum and Enum.OnUpdateMode and Enum.OnUpdateMode.RunWhenVisible) or 1

local A3 = MSUF.MSUF_Auras3
if type(A3) ~= "table" then
    A3 = {}
    MSUF.MSUF_Auras3 = A3
end
ExportPublic("MSUF_Auras3", A3)

local function AuraDurationBarColor()
    local resolver = A3.GetDurationBarColor
    if type(resolver) == "function" then return resolver() end
    return 1, 1, 1
end

if A3.__editModeLoaded then return end
A3.__editModeLoaded = true

A3.EditMode = (type(A3.EditMode) == "table") and A3.EditMode or {}
local EM = A3.EditMode
local FrameLayers = MSUF.UF and MSUF.UF.Layers or {}
local SPELL_FRAME_EFFECT_BASE_OFFSET = tonumber(FrameLayers.SPELL_FRAME_EFFECT_BASE_OFFSET) or 1

local AURA_DRAG_RUNTIME_INTERVAL = 0.05
local AURA_PENDING_DRAG_THRESHOLD = 3
local AURA_UNITS = { "player", "target", "focus", "boss1", "boss2", "boss3", "boss4", "boss5" }
local BOSS_UNITS = { boss1=true, boss2=true, boss3=true, boss4=true, boss5=true }
local function IsBossScope(unit)
    return tostring(unit or ""):lower() == "boss"
end

local function ForEachBossUnit(fn)
    if type(fn) ~= "function" then return end
    for i = 1, 5 do fn("boss" .. i) end
end

local GROUPS = {
    buff = {
        label = "Buffs",
        xKey = "buffGroupOffsetX",
        yKey = "buffGroupOffsetY",
        sizeKey = "buffGroupIconSize",
        paddingKey = "buffStylePadding",
        iconZoomKey = "buffIconZoom",
        iconShapeKey = "buffIconShape",
        anchorKey = "buffAnchor",
        layerKey = "buffLayer",
        maxKey = "maxBuffs",
        showKey = "showBuffs",
        perRowKey = "buffPerRow",
        spacingKey = "buffSpacing",
        growthKey = "buffGrowthX",
        wrapKey = "buffGrowthY",
        texture = "Interface\\Icons\\Spell_Holy_WordFortitude",
        color = { 0.16, 0.82, 0.35, 0.28 },
        defaultAnchor = "BOTTOMRIGHT",
        defaultLayer = 5,
    },
    debuff = {
        label = "Debuffs",
        xKey = "debuffGroupOffsetX",
        yKey = "debuffGroupOffsetY",
        sizeKey = "debuffGroupIconSize",
        paddingKey = "debuffStylePadding",
        iconZoomKey = "debuffIconZoom",
        iconShapeKey = "debuffIconShape",
        anchorKey = "debuffAnchor",
        layerKey = "debuffLayer",
        maxKey = "maxDebuffs",
        showKey = "showDebuffs",
        perRowKey = "debuffPerRow",
        spacingKey = "debuffSpacing",
        growthKey = "debuffGrowthX",
        wrapKey = "debuffGrowthY",
        texture = "Interface\\Icons\\Spell_Shadow_ShadowWordPain",
        color = { 0.92, 0.20, 0.20, 0.28 },
        defaultAnchor = "TOPLEFT",
        defaultLayer = 6,
    },
    custom1 = { customIndex = 1, label = "Custom 1", texture = "Interface\\Icons\\INV_Misc_QuestionMark", color = { 0.45, 0.72, 1.00, 0.28 }, defaultAnchor = "TOPRIGHT", defaultLayer = 9 },
    custom2 = { customIndex = 2, label = "Custom 2", texture = "Interface\\Icons\\INV_Misc_QuestionMark", color = { 0.70, 0.48, 1.00, 0.28 }, defaultAnchor = "TOPRIGHT", defaultLayer = 9 },
    custom3 = { customIndex = 3, label = "Custom 3", texture = "Interface\\Icons\\INV_Misc_QuestionMark", color = { 1.00, 0.58, 0.28, 0.28 }, defaultAnchor = "TOPRIGHT", defaultLayer = 9 },
    custom4 = { customIndex = 4, label = "Dots on target", texture = "Interface\\Icons\\Ability_Rogue_Garrote", color = { 0.88, 0.24, 0.42, 0.28 }, defaultAnchor = "TOPRIGHT", defaultLayer = 9 },
}

local LANE_STYLE_KEYS = {
    buff = {
        showStackCount = "buffShowStackCount",
        showCooldownText = "buffShowCooldownText",
        showCooldownSwipe = "buffShowCooldownSwipe",
        cooldownSwipeReverse = "buffCooldownSwipeReverse",
        stackCountAnchor = "buffStackCountAnchor",
        cooldownTextAnchor = "buffCooldownTextAnchor",
        stackTextSize = "buffStackTextSize",
        stackTextOffsetX = "buffStackTextOffsetX",
        stackTextOffsetY = "buffStackTextOffsetY",
        cooldownTextSize = "buffCooldownTextSize",
        cooldownTextOffsetX = "buffCooldownTextOffsetX",
        cooldownTextOffsetY = "buffCooldownTextOffsetY",
        cooldownDecimalSeconds = "buffCooldownDecimalSeconds",
        showDurationBar = "buffShowDurationBar",
        durationBarHeight = "buffDurationBarHeight",
        durationBarDisplay = "buffDurationBarDisplay",
        durationBarPosition = "buffDurationBarPosition",
        durationBarDirection = "buffDurationBarDirection",
    },
    debuff = {
        showStackCount = "debuffShowStackCount",
        showCooldownText = "debuffShowCooldownText",
        showCooldownSwipe = "debuffShowCooldownSwipe",
        cooldownSwipeReverse = "debuffCooldownSwipeReverse",
        debuffTypeBorderMode = "debuffTypeBorderMode",
        useDebuffTypeBorders = "useDebuffTypeBorders",
        stackCountAnchor = "debuffStackCountAnchor",
        cooldownTextAnchor = "debuffCooldownTextAnchor",
        stackTextSize = "debuffStackTextSize",
        stackTextOffsetX = "debuffStackTextOffsetX",
        stackTextOffsetY = "debuffStackTextOffsetY",
        cooldownTextSize = "debuffCooldownTextSize",
        cooldownTextOffsetX = "debuffCooldownTextOffsetX",
        cooldownTextOffsetY = "debuffCooldownTextOffsetY",
        cooldownDecimalSeconds = "debuffCooldownDecimalSeconds",
        showDurationBar = "debuffShowDurationBar",
        durationBarHeight = "debuffDurationBarHeight",
        durationBarDisplay = "debuffDurationBarDisplay",
        durationBarPosition = "debuffDurationBarPosition",
        durationBarDirection = "debuffDurationBarDirection",
    },
}

local W8 = "Interface\\Buttons\\WHITE8X8"
local DEBUFF_TYPE_BORDER_PREVIEW_ATLAS = {
    BORDER = "ui-debuff-border-magic-noicon",
    SYMBOL = "ui-debuff-border-magic-icon",
}
local HEADER_H = 18
local PREVIEW_ICONS = 4
local TEXT_STYLE_LAYOUT_KEYS = {
    stackTextSize = true,
    stackTextOffsetX = true,
    stackTextOffsetY = true,
    cooldownTextSize = true,
    cooldownTextOffsetX = true,
    cooldownTextOffsetY = true,
    cooldownDecimalSeconds = true,
    durationBarHeight = true,
    buffStackTextSize = true,
    buffStackTextOffsetX = true,
    buffStackTextOffsetY = true,
    buffCooldownTextSize = true,
    buffCooldownTextOffsetX = true,
    buffCooldownTextOffsetY = true,
    buffCooldownDecimalSeconds = true,
    buffDurationBarHeight = true,
    debuffStackTextSize = true,
    debuffStackTextOffsetX = true,
    debuffStackTextOffsetY = true,
    debuffCooldownTextSize = true,
    debuffCooldownTextOffsetX = true,
    debuffCooldownTextOffsetY = true,
    debuffCooldownDecimalSeconds = true,
    debuffDurationBarHeight = true,
}
local TEXT_STYLE_SHARED_KEYS = {
    stackCountAnchor = true,
    cooldownTextAnchor = true,
    showStackCount = true,
    showCooldownText = true,
    showCooldownSwipe = true,
    cooldownSwipeReverse = true,
    showDurationBar = true,
    durationBarDisplay = true,
    durationBarPosition = true,
    durationBarDirection = true,
    buffStackCountAnchor = true,
    buffCooldownTextAnchor = true,
    buffShowStackCount = true,
    buffShowCooldownText = true,
    buffShowCooldownSwipe = true,
    buffCooldownSwipeReverse = true,
    buffShowDurationBar = true,
    buffDurationBarDisplay = true,
    buffDurationBarPosition = true,
    buffDurationBarDirection = true,
    debuffStackCountAnchor = true,
    debuffCooldownTextAnchor = true,
    debuffShowStackCount = true,
    debuffShowCooldownText = true,
    debuffShowCooldownSwipe = true,
    debuffCooldownSwipeReverse = true,
    debuffTypeBorderMode = true,
    useDebuffTypeBorders = true,
    debuffShowDurationBar = true,
    debuffDurationBarDisplay = true,
    debuffDurationBarPosition = true,
    debuffDurationBarDirection = true,
}
local AURA_TEXT_ANCHOR_OK = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true,
    LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

local function Clamp(v, defaultValue, minValue, maxValue)
    v = tonumber(v)
    if not v then v = defaultValue end
    if minValue and v < minValue then v = minValue end
    if maxValue and v > maxValue then v = maxValue end
    return v
end

local function Round(v)
    v = tonumber(v) or 0
    if v < -4096 then v = -4096 elseif v > 4096 then v = 4096 end
    if v < 0 then return -math_floor((-v) + 0.5) end
    return math_floor(v + 0.5)
end

local function IsEditModeActive()
    local st = rawget(_G, "MSUF_EditState")
    return (st and st.active == true) or rawget(_G, "MSUF_UnitEditModeActive") == true
end

local function EditPreviewActive()
    return IsEditModeActive() and rawget(_G, "MSUF_UnitPreviewActive") == true
end

--- Menu2's boss page keeps the out-of-menu boss frame preview alive; boss aura
--- lanes follow that flag so the page shows auras 1:1 without edit mode.
local function BossPageAuraPreviewActive()
    return rawget(_G, "MSUF2_BossPageAuraPreviewActive") == true
end

local function UnitPreviewActive(unit)
    if EditPreviewActive() then return true end
    if unit == nil then return BossPageAuraPreviewActive() end
    return (BOSS_UNITS[unit] == true or IsBossScope(unit)) and BossPageAuraPreviewActive() or false
end

--- Preview lanes must never cover Menu2. The slash menu sits at DIALOG while it
--- drives the boss page preview and only rises to FULLSCREEN_DIALOG once MSUF
--- Edit Mode is active, so the movers follow that split instead of pinning
--- FULLSCREEN in both cases. HIGH still keeps the dummy icons above the unit
--- frames, which never raise themselves past the UIParent default.
local function SyncPreviewGroupStrata(group)
    if not (group and group.SetFrameStrata) then return end
    local strata = IsEditModeActive() and "FULLSCREEN" or "HIGH"
    if group._msufA3PreviewStrata == strata then return end
    group._msufA3PreviewStrata = strata
    group:SetFrameStrata(strata)
end

local function IsConfigBlocked()
    if InCombatLockdown and InCombatLockdown() then return true end
    if _G.UnitAffectingCombat and _G.UnitAffectingCombat("player") then return true end
    if _G.MSUF_InCombat == true then return true end
    return false
end

local function RequestUnitFrameMenuPreview(reason)
    local fn = _G.MSUF_UFPreview_RequestRefresh
    if type(fn) == "function" then fn(reason or "AURAS3_EDITMODE") end
end

local function NormalizeKind(kind)
    kind = (type(kind) == "string") and kind:lower() or "buff"
    if kind == "buffs" then return "buff" end
    if kind == "debuffs" then return "debuff" end
    if GROUPS[kind] then return kind end
    return "buff"
end

local function CustomItem(unit, index, create)
    local model = A3 and A3.MenuModel
    if not (model and type(model.CustomContainer) == "function") then return nil end
    return model.CustomContainer(unit, index, create == true)
end

--- Real tracked spells for a custom lane so previews mirror the runtime 1:1:
--- each preview icon shows an actually configured spell (dots keep the runtime
--- include filter). Returns nil while nothing is configured; edit mode then
--- keeps a placeholder drag surface, the boss page preview shows nothing.
local function CustomPreviewEntries(unit, kind)
    local spec = GROUPS[kind]
    local customIndex = spec and spec.customIndex
    if not customIndex then return nil end
    local model = A3 and A3.MenuModel
    local fetch = model and (model.CustomContainerPreviewEntries or model.CustomContainerSpellEntries)
    if type(fetch) ~= "function" then return nil end
    local entries = fetch(unit, customIndex)
    if type(entries) ~= "table" or #entries == 0 then return nil end
    return entries
end

local function CustomPreviewEntriesSignature(entries)
    if type(entries) ~= "table" then return "none" end
    local out = ""
    for i = 1, #entries do
        local entry = entries[i]
        out = out .. tostring(entry and (entry.spellID or entry.value) or "?") .. ","
    end
    return out
end

local function UnitLabel(unit)
    if unit == "player" then return "Player" end
    if unit == "target" then return "Target" end
    if unit == "focus" then return "Focus" end
    if BOSS_UNITS[unit] then return "Boss " .. tostring(unit):match("%d+") end
    return tostring(unit or "")
end

local function GroupLabel(unit, kind, spec)
    if unit == "player" and kind == "custom4" then return "Defensive Buffs" end
    return spec and spec.label or tostring(kind or "")
end

local function EnsureDB()
    local auras, shared
    if A3.EnsureDB then
        auras, shared = A3.EnsureDB()
    else
        local db = _G.MSUF_DB
        auras = db and (db.auras3 or db.auras3)
        shared = auras and auras.shared
    end
    if type(auras) ~= "table" then return nil, nil end
    if type(shared) ~= "table" then
        shared = {}
        auras.shared = shared
    end
    return auras, shared
end

local function UnitEnabled(auras, unit)
    if type(auras) ~= "table" or auras.enabled ~= true then return false end
    if unit == "player" then return auras.showPlayer == true end
    if unit == "target" then return auras.showTarget == true end
    if unit == "focus" then return auras.showFocus == true end
    if BOSS_UNITS[unit] then return auras.showBoss == true end
    return false
end

local function UnitHasCustomPreview(unit)
    for index = 1, 4 do
        local item = CustomItem and CustomItem(unit, index, false)
        local placed = item and item.placed
        if item and (tonumber(placed and placed.max) or 8) > 0 then
            if item.enabled == true then return true end
            -- Tracked target DoTs keep their configuration preview while the
            -- lane is disabled. Player Defensives use `enabled` as a strict
            -- master switch, matching both Runtime and the Menu2 preview.
            if unit ~= "player" and index == 4
                and CustomPreviewEntries(unit, "custom4") then return true end
        end
    end
    return false
end

local function GetFrame(unit)
    if not unit then return nil end
    local uf = MSUF and MSUF.UF
    return (A3._runtimeFrames and A3._runtimeFrames[unit])
        or (A3._unitFrameOwners and A3._unitFrameOwners[unit])
        or (uf and type(uf.GetFrame) == "function" and uf.GetFrame(unit))
        or (uf and uf.frames and uf.frames[unit])
        or _G["MSUF_" .. unit]
end

local function FrameScaleRelativeToUIParent(frame)
    local frameScale = frame and frame.GetEffectiveScale and frame:GetEffectiveScale()
    local uiScale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()
    frameScale = tonumber(frameScale) or 1
    uiScale = tonumber(uiScale) or 1
    if frameScale <= 0 then frameScale = 1 end
    if uiScale <= 0 then uiScale = 1 end
    local scale = frameScale / uiScale
    if scale <= 0 then return 1 end
    return scale
end

local function ApplyGroupScaleForFrame(group, frame)
    local scale = FrameScaleRelativeToUIParent(frame)
    if group and group.SetScale and group._msufA3FrameScale ~= scale then
        group:SetScale(scale)
        group._msufA3FrameScale = scale
    end
    return scale
end

local function GetLayout(auras, unit, create)
    if type(auras) ~= "table" or not unit then return nil end
    if create then
        auras.perUnit = (type(auras.perUnit) == "table") and auras.perUnit or {}
        local pu = auras.perUnit[unit]
        if type(pu) ~= "table" then
            pu = {}
            auras.perUnit[unit] = pu
        end
        --- Shared-layout scopes may still carry an old dormant local table.
        --- The first Edit Mode drag must follow the same ownership transition
        --- as Menu/Popup writes instead of reactivating stale geometry/style.
        if pu.overrideLayout ~= true then pu.layout = {} end
        pu.overrideLayout = true
        pu.layout = (type(pu.layout) == "table") and pu.layout or {}
        return pu.layout, pu
    end

    local pu = auras.perUnit and auras.perUnit[unit]
    if pu and type(pu.layout) == "table" then
        return pu.layout, pu
    end
    return nil, pu
end

local function GetSharedLayout(auras, unit)
    local pu = auras and auras.perUnit and auras.perUnit[unit]
    if pu and type(pu.layoutShared) == "table" then
        return pu.layoutShared
    end
    return nil
end

local function TableHasAnyKey(tbl, keys)
    if type(tbl) ~= "table" or type(keys) ~= "table" then return false end
    for key in pairs(keys) do
        if tbl[key] ~= nil then return true end
    end
    return false
end

local function UnitStyleOverrideActive(pu)
    if type(pu) ~= "table" then return false end
    if pu.overrideStyle ~= nil then return pu.overrideStyle == true end
    return TableHasAnyKey(pu.layout, TEXT_STYLE_LAYOUT_KEYS) or TableHasAnyKey(pu.layoutShared, TEXT_STYLE_SHARED_KEYS)
end

local function ReadNumber(shared, layout, key, defaultValue, minValue, maxValue)
    local v = shared and shared[key]
    if layout and layout[key] ~= nil then v = layout[key] end
    return Clamp(v, defaultValue, minValue, maxValue)
end

local function ReadRawNumber(shared, layout, key)
    local v = layout and layout[key]
    if v == nil then v = shared and shared[key] end
    return tonumber(v)
end

local function ReadRawValue(shared, layout, key)
    if layout and layout[key] ~= nil then return layout[key] end
    return shared and shared[key]
end

local function ReadLaneTextNumber(shared, layout, kind, key, defaultValue, minValue, maxValue)
    kind = NormalizeKind(kind)
    local laneKey = kind and LANE_STYLE_KEYS[kind] and LANE_STYLE_KEYS[kind][key]
    local v = laneKey and ReadRawNumber(nil, layout, laneKey) or nil
    return Clamp(v, defaultValue, minValue, maxValue)
end

local function ReadLaneTextBool(shared, layout, kind, key, defaultValue)
    kind = NormalizeKind(kind)
    local laneKey = kind and LANE_STYLE_KEYS[kind] and LANE_STYLE_KEYS[kind][key]
    -- `false` is a real per-lane override. The usual and/or shortcut turns it
    -- into nil and incorrectly falls back to the generic/shared On value.
    local v
    if laneKey then v = ReadRawValue(nil, layout, laneKey) end
    if v == nil then return defaultValue == true end
    return v == true
end

local function ReadLaneTextString(shared, layout, kind, key, fallback)
    kind = NormalizeKind(kind)
    local laneKey = kind and LANE_STYLE_KEYS[kind] and LANE_STYLE_KEYS[kind][key]
    local v = laneKey and ReadRawValue(nil, layout, laneKey) or nil
    return tostring(v or fallback or "")
end

local function ReadLaneTextAnchor(shared, layoutShared, kind)
    kind = NormalizeKind(kind)
    local laneKey = kind and LANE_STYLE_KEYS[kind] and LANE_STYLE_KEYS[kind].stackCountAnchor
    local anchor = laneKey and layoutShared and layoutShared[laneKey] or nil
    anchor = anchor or "TOPRIGHT"
    if anchor ~= "TOPLEFT" and anchor ~= "BOTTOMLEFT" and anchor ~= "BOTTOMRIGHT" then
        anchor = "TOPRIGHT"
    end
    return anchor
end

local function ReadLaneCooldownTextAnchor(shared, layoutShared, kind)
    kind = NormalizeKind(kind)
    local laneKey = kind and LANE_STYLE_KEYS[kind] and LANE_STYLE_KEYS[kind].cooldownTextAnchor
    local anchor = laneKey and layoutShared and layoutShared[laneKey] or nil
    anchor = anchor or "CENTER"
    return AURA_TEXT_ANCHOR_OK[anchor] and anchor or "CENTER"
end

local function NormalizeDebuffBorderMode(value, useLegacy)
    if value == true then return "SYMBOL" end
    value = tostring(value or ""):upper()
    if value == "BORDER" or value == "COLOR" or value == "ON" then return "BORDER" end
    if value == "SYMBOL" or value == "BORDER_SYMBOL" or value == "BORDER_SYMBOLS"
        or value == "BORDER+SYMBOL" or value == "ICON" or value == "WITH_SYMBOL" then
        return "SYMBOL"
    end
    return useLegacy == true and "SYMBOL" or "OFF"
end

local function ReadTextConfig(unit, kind)
    kind = NormalizeKind(kind)
    local customSpec = GROUPS[kind]
    if customSpec and customSpec.customIndex then
        local item = CustomItem(unit, customSpec.customIndex, false)
        local placed = item and item.placed or {}
        local isDebuff = item and item.auraType == "DEBUFF"
        return {
            showStackCount = placed.showStacks ~= false,
            showCooldownText = placed.showCooldown ~= false,
            showCooldownSwipe = placed.showCooldownSwipe ~= false,
            cooldownSwipeReverse = placed.cooldownSwipeReverse == true,
            stackSize = Clamp(placed.stackSize, 14, 6, 40),
            stackX = Clamp(placed.stackX, 0, -2000, 2000),
            stackY = Clamp(placed.stackY, 0, -2000, 2000),
            cooldownSize = Clamp(placed.cooldownSize, 14, 6, 40),
            cooldownX = Clamp(placed.cooldownX, 0, -2000, 2000),
            cooldownY = Clamp(placed.cooldownY, 0, -2000, 2000),
            cooldownDecimalSeconds = Clamp(placed.cooldownDecimalSeconds, 3, 0, 30),
            showDurationBar = placed.showDurationBar == true,
            durationBarHeight = Clamp(placed.durationBarHeight, 2, 1, 16),
            durationBarDisplay = placed.durationBarDisplay == "OVERLAY" and "OVERLAY" or "BAR_ONLY",
            durationBarPosition = placed.durationBarPosition == "TOP" and "TOP" or "BOTTOM",
            durationBarDirection = placed.durationBarDirection == "ELAPSED" and "ELAPSED" or "REMAINING",
            stackAnchor = placed.stackAnchor or "BOTTOMRIGHT",
            cooldownAnchor = placed.cooldownAnchor or "CENTER",
            debuffBorderMode = isDebuff and NormalizeDebuffBorderMode(placed.debuffTypeBorderMode, placed.useDebuffTypeBorders) or "OFF",
        }
    end
    local auras, shared = EnsureDB()
    local layout = GetLayout(auras, unit, false)
    local ls = GetSharedLayout(auras, unit)
    return {
        showStackCount = ReadLaneTextBool(shared, ls, kind, "showStackCount", true),
        showCooldownText = ReadLaneTextBool(shared, ls, kind, "showCooldownText", true),
        showCooldownSwipe = ReadLaneTextBool(shared, ls, kind, "showCooldownSwipe", true),
        cooldownSwipeReverse = ReadLaneTextBool(shared, ls, kind, "cooldownSwipeReverse", false),
        stackSize = ReadLaneTextNumber(shared, layout, kind, "stackTextSize", 14, 6, 40),
        stackX = ReadLaneTextNumber(shared, layout, kind, "stackTextOffsetX", -1, -2000, 2000),
        stackY = ReadLaneTextNumber(shared, layout, kind, "stackTextOffsetY", 1, -2000, 2000),
        cooldownSize = ReadLaneTextNumber(shared, layout, kind, "cooldownTextSize", 14, 6, 40),
        cooldownX = ReadLaneTextNumber(shared, layout, kind, "cooldownTextOffsetX", 0, -2000, 2000),
        cooldownY = ReadLaneTextNumber(shared, layout, kind, "cooldownTextOffsetY", 0, -2000, 2000),
        cooldownDecimalSeconds = ReadLaneTextNumber(shared, layout, kind, "cooldownDecimalSeconds", 3, 0, 30),
        showDurationBar = ReadLaneTextBool(shared, ls, kind, "showDurationBar", false),
        durationBarHeight = ReadLaneTextNumber(shared, layout, kind, "durationBarHeight", 2, 1, 16),
        durationBarDisplay = ReadLaneTextString(shared, ls, kind, "durationBarDisplay", "BAR_ONLY") == "OVERLAY" and "OVERLAY" or "BAR_ONLY",
        durationBarPosition = ReadLaneTextString(shared, ls, kind, "durationBarPosition", "BOTTOM") == "TOP" and "TOP" or "BOTTOM",
        durationBarDirection = ReadLaneTextString(shared, ls, kind, "durationBarDirection", "REMAINING") == "ELAPSED" and "ELAPSED" or "REMAINING",
        stackAnchor = ReadLaneTextAnchor(shared, ls, kind),
        cooldownAnchor = ReadLaneCooldownTextAnchor(shared, ls, kind),
        debuffBorderMode = kind == "debuff" and NormalizeDebuffBorderMode(
            ReadLaneTextString(shared, ls, kind, "debuffTypeBorderMode", "OFF"),
            ReadLaneTextBool(shared, ls, kind, "useDebuffTypeBorders", false)) or "OFF",
    }
end

local function ReadGroupConfig(unit, kind)
    kind = NormalizeKind(kind)
    local spec = GROUPS[kind]
    if spec and spec.customIndex then
        local item = CustomItem(unit, spec.customIndex, false)
        local placed = item and item.placed or {}
        local auraType = item and item.auraType == "DEBUFF" and "DEBUFF" or "BUFF"
        local anchor = placed.anchor
        if not AURA_TEXT_ANCHOR_OK[anchor] then anchor = spec.defaultAnchor end
        return {
            x = Round(placed.x or 0),
            y = Round(placed.y or 0),
            anchor = anchor,
            layer = Clamp(item and item.layer, spec.defaultLayer, 0, 30),
            alpha = Clamp(placed.alpha, 1, 0, 1),
            iconZoom = Clamp(placed.iconZoom, 100, 100, 200),
            iconShape = type(placed.iconShape) == "string" and placed.iconShape or "RECTANGLE",
            size = Clamp(placed.size, 24, 1, 128),
            padding = Clamp(placed.stylePadding, 0, 0, 16),
            spacing = Clamp(placed.spacing, 2, 0, 64),
            perRow = Clamp(placed.perRow, 4, 1, 40),
            max = Clamp(placed.max, 8, 0, 40),
            growth = placed.growth or "LEFTDOWN",
            rowWrap = "DOWN",
            show = item and item.enabled == true or false,
            -- The dots container keeps its own placeholder (Garrote) instead of
            -- the generic debuff icon; tracked entries override it anyway.
            texture = spec.customIndex == 4 and spec.texture
                or (auraType == "DEBUFF" and "Interface\\Icons\\Spell_Shadow_ShadowWordPain" or "Interface\\Icons\\Spell_Holy_WordFortitude"),
        }
    end
    local auras, shared = EnsureDB()
    local layout = GetLayout(auras, unit, false)
    local ls = GetSharedLayout(auras, unit)

    local x = layout and layout[spec.xKey] or 0
    local y = layout and layout[spec.yKey] or 0
    local size = layout and layout[spec.sizeKey] or 26
    local iconZoom = layout and layout[spec.iconZoomKey] or 100
    local shapes = type(shared) == "table" and shared.appearanceIconShapes or nil
    local iconShape = type(shapes) == "table" and shapes[kind] or "RECTANGLE"
    local spacing = layout and layout[spec.spacingKey] or 2
    spacing = Clamp(spacing, 2, 0, 64)
    local perRow = (ls and type(ls[spec.perRowKey]) == "number" and ls[spec.perRowKey])
        or 12
    local maxN = (ls and type(ls[spec.maxKey]) == "number" and ls[spec.maxKey])
        or 12
    local growth = (ls and ls[spec.growthKey])
        or "RIGHT"
    if growth ~= "RIGHT" and growth ~= "LEFT" and growth ~= "UP" and growth ~= "DOWN" then growth = "RIGHT" end
    local rowWrap = (ls and ls[spec.wrapKey])
        or "DOWN"
    if rowWrap ~= "UP" and rowWrap ~= "DOWN" then rowWrap = "DOWN" end
    local anchor = (layout and layout[spec.anchorKey])
        or spec.defaultAnchor
        or "TOPLEFT"
    if not AURA_TEXT_ANCHOR_OK[anchor] then
        anchor = spec.defaultAnchor or "TOPLEFT"
    end
    local layer = (layout and layout[spec.layerKey] ~= nil and layout[spec.layerKey])
        or spec.defaultLayer
        or 5

    return {
        x = Round(x),
        y = Round(y),
        anchor = anchor,
        layer = Clamp(layer, spec.defaultLayer or 5, 0, 30),
        size = Clamp(size, 26, 1, 128),
        iconZoom = Clamp(iconZoom, 100, 100, 200),
        iconShape = iconShape,
        padding = Clamp(layout and layout[spec.paddingKey], 0, 0, 16),
        spacing = spacing,
        perRow = Clamp(perRow, 12, 1, 40),
        max = Clamp(maxN, 12, 0, 80),
        growth = growth,
        rowWrap = rowWrap,
        show = not ls or ls[spec.showKey] ~= false,
    }
end

local AnchorOffset

local function AnchorBase(anchor, frame)
    local w = frame and frame.GetWidth and frame:GetWidth() or 0
    local h = frame and frame.GetHeight and frame:GetHeight() or 0
    return AnchorOffset(anchor, w, h)
end

AnchorOffset = function(anchor, w, h)
    w = tonumber(w) or 0
    h = tonumber(h) or 0
    anchor = tostring(anchor or "TOPLEFT")
    if anchor == "TOPLEFT" then return 0, h end
    if anchor == "TOP" then return w * 0.5, h end
    if anchor == "TOPRIGHT" then return w, h end
    if anchor == "LEFT" then return 0, h * 0.5 end
    if anchor == "CENTER" then return w * 0.5, h * 0.5 end
    if anchor == "RIGHT" then return w, h * 0.5 end
    if anchor == "BOTTOMLEFT" then return 0, 0 end
    if anchor == "BOTTOM" then return w * 0.5, 0 end
    if anchor == "BOTTOMRIGHT" then return w, 0 end
    return 0, h
end

local function ButtonAnchor(xSign, ySign)
    if ySign > 0 then
        return xSign < 0 and "BOTTOMRIGHT" or "BOTTOMLEFT"
    end
    return xSign < 0 and "TOPRIGHT" or "TOPLEFT"
end

local function GrowthParts(growth, rowWrap)
    if growth == "LEFTUP" then return -1, 1, false, "BOTTOMRIGHT" end
    if growth == "LEFTDOWN" then return -1, -1, false, "TOPRIGHT" end
    if growth == "RIGHTUP" then return 1, 1, false, "BOTTOMLEFT" end
    if growth == "RIGHTDOWN" then return 1, -1, false, "TOPLEFT" end
    if growth ~= "LEFT" and growth ~= "UP" and growth ~= "DOWN" then growth = "RIGHT" end
    if rowWrap ~= "UP" then rowWrap = "DOWN" end
    local xSign = growth == "LEFT" and -1 or 1
    local ySign = rowWrap == "UP" and 1 or -1
    if growth == "UP" or growth == "DOWN" then
        xSign = 1
        ySign = growth == "UP" and 1 or -1
        return xSign, ySign, true, ButtonAnchor(xSign, ySign)
    end
    return xSign, ySign, false, ButtonAnchor(xSign, ySign)
end

local function GridDimensions(maxN, perRow, size, spacing, vertical)
    local count = math_max(Round(maxN), 1)
    local per = math_max(Round(perRow), 1)
    local cols, rows
    if vertical == true then
        rows = count
        cols = 1
    else
        cols = math_min(count, per)
        rows = math_ceil(count / per)
    end
    size = Clamp(size, 26, 1, 128)
    spacing = Clamp(spacing, 2, 0, 64)
    return math_max(1, cols * size + math_max(cols - 1, 0) * spacing),
        math_max(1, rows * size + math_max(rows - 1, 0) * spacing),
        cols,
        rows
end

local function IconGridCoord(index, perRow, vertical)
    local per = math_max(Round(perRow), 1)
    local idx = index - 1
    if vertical == true then
        return 0, idx
    end
    local col = idx % per
    return col, (idx - col) / per
end

--- Inward offset from the lane's initial corner for the shared style padding,
--- mirroring the runtime container's SetFlowLayoutPadding inset.
local function PaddingInset(anchor, pad)
    pad = tonumber(pad) or 0
    if pad == 0 then return 0, 0 end
    anchor = tostring(anchor or "TOPLEFT")
    local dx = anchor:find("LEFT", 1, true) and pad or (anchor:find("RIGHT", 1, true) and -pad or 0)
    local dy = anchor:find("BOTTOM", 1, true) and pad or (anchor:find("TOP", 1, true) and -pad or 0)
    return dx, dy
end

--- Shared icon style for a previewed lane: the compiled runtime style when the
--- lane metrics carry one, otherwise the scope-resolved preview style. Bar-only
--- lanes pass nil downstream, matching the runtime's chrome-off rendering.
local function LaneIconStyle(metrics, _, kind)
    if metrics and metrics.iconStyle then return metrics.iconStyle end
    if type(A3.IconStylePreviewForKind) == "function" then
        return A3.IconStylePreviewForKind((metrics and metrics.appearanceKind) or kind)
    end
    return nil
end

local function PositionPreviewGroup(group, frame, anchor, x, y, laneW, laneH)
    if not (group and frame) then return end
    local baseX, baseY = AnchorBase(anchor, frame)
    local localX, localY = AnchorOffset(anchor, laneW, laneH)
    group:ClearAllPoints()
    group:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", baseX + (tonumber(x) or 0) - localX, baseY + (tonumber(y) or 0) - localY)
end

local function FallbackMetrics(cfg)
    local xSign, ySign, vertical, initialAnchor = GrowthParts(cfg and cfg.growth, cfg and cfg.rowWrap)
    local laneW, laneH = GridDimensions(cfg and cfg.max, cfg and cfg.perRow, cfg and cfg.size, cfg and cfg.spacing, vertical)
    local padding = Clamp(cfg and cfg.padding, 0, 0, 16)
    return {
        enabled = cfg and cfg.show == true,
        num = cfg and Round(cfg.max) or 0,
        size = cfg and cfg.size or 26,
        iconZoom = cfg and cfg.iconZoom or 100,
        iconShape = cfg and cfg.iconShape or "RECTANGLE",
        spacing = cfg and cfg.spacing or 2,
        step = ((cfg and cfg.size) or 26) + ((cfg and cfg.spacing) or 2),
        perRow = cfg and cfg.perRow or 12,
        padding = padding,
        width = laneW + 2 * padding,
        height = laneH + 2 * padding,
        growthX = xSign,
        growthY = ySign,
        verticalGrowth = vertical == true,
        initialAnchor = initialAnchor,
        x = cfg and cfg.x or 0,
        y = cfg and cfg.y or 0,
        anchor = cfg and cfg.anchor or "TOPLEFT",
    }
end

local function WriteOffset(auras, unit, kind, x, y)
    kind = NormalizeKind(kind)
    local spec = GROUPS[kind]
    if spec and spec.customIndex then
        local item = CustomItem(unit, spec.customIndex, true)
        if not item then return end
        item.placed = type(item.placed) == "table" and item.placed or {}
        item.placed.x = Round(x)
        item.placed.y = Round(y)
        return
    end
    local layout = GetLayout(auras, unit, true)
    if not layout then return end
    layout[spec.xKey] = Round(x)
    layout[spec.yKey] = Round(y)
end

--- Older profiles may store only group-lane offsets/sizes. When a user drags a
--- lane in edit mode, promote the effective runtime position back into the
--- per-unit layout so future edits are stable and visible in the menu model.
local function PromoteRuntimeLayout(unit, kind)
    -- Kept as a call-site compatibility no-op. Unit lanes already persist the
    -- exact lane keys; promoting them into generic unit-wide aliases would
    -- recreate the retired Shared-era ownership path.
end

local function ApplyDragUnit(auras, unit, moverKind, x, y)
    WriteOffset(auras, unit, moverKind, x, y)
    local other = EM.groups and EM.groups[unit] and EM.groups[unit][moverKind]
    local frame = other and GetFrame(unit)
    if other and frame then
        local cfg = ReadGroupConfig(unit, moverKind)
        local metrics = type(A3.BuildAuraLaneMetrics) == "function" and A3.BuildAuraLaneMetrics(unit, moverKind) or nil
        metrics = metrics or FallbackMetrics(cfg)
        local laneW = metrics.width or cfg.size
        local laneH = metrics.height or cfg.size
        ApplyGroupScaleForFrame(other, frame)
        PositionPreviewGroup(other, frame, metrics.anchor or cfg.anchor, x, y, laneW, laneH)
    end
end

local function RefreshAffectedRuntimeUnits(unit, shared)
    if BOSS_UNITS[unit] and shared and shared.bossEditTogether ~= false then
        for i = 1, 5 do
            A3.RefreshUnit("boss" .. i)
        end
    elseif unit then
        A3.RefreshUnit(unit)
    end
end

local function ShouldFlushDragRuntime(self, elapsed)
    self._dragRuntimeElapsed = (tonumber(self._dragRuntimeElapsed) or AURA_DRAG_RUNTIME_INTERVAL) + (tonumber(elapsed) or 0)
    if self._dragRuntimeElapsed < AURA_DRAG_RUNTIME_INTERVAL then
        self._dragRuntimePending = true
        return false
    end
    self._dragRuntimeElapsed = 0
    self._dragRuntimePending = nil
    return true
end

local function FlushDragRuntime(self, baseUnit, shared, reason, force)
    if not force and not ShouldFlushDragRuntime(self, self and self._lastDragElapsed) then return end
    RefreshAffectedRuntimeUnits(baseUnit, shared)
    RequestUnitFrameMenuPreview(reason or "AURAS3_EDITMODE_DRAG")
    local sync = _G.MSUF_SyncAuras3PositionPopup
    if type(sync) == "function" then sync(baseUnit) end
end

--- Drag writes are throttled by value equality and blocked in combat. Boss aura
--- lanes can be edited together, but the persisted value is still written to
--- each boss unit so the runtime path stays simple.
local function ApplyDragDelta(self, dx, dy, elapsed)
    if IsConfigBlocked() then return end
    local auras = self._dragAuras
    local shared = self._dragShared
    if not (auras and shared) then
        auras, shared = EnsureDB()
        self._dragAuras = auras
        self._dragShared = shared
    end
    if not auras or not shared then return end
    local startX = self._dragStartOffsetX or 0
    local startY = self._dragStartOffsetY or 0
    local x = Round(startX + dx)
    local y = Round(startY + dy)
    if self._lastDragX == x and self._lastDragY == y then return end
    self._lastDragX = x
    self._lastDragY = y
    self._lastDragElapsed = tonumber(elapsed) or 0
    local baseUnit = self._msufA3Unit
    local moverKind = self._msufA3MoverKind

    if BOSS_UNITS[baseUnit] and shared.bossEditTogether ~= false then
        for i = 1, 5 do
            ApplyDragUnit(auras, "boss" .. i, moverKind, x, y)
        end
    elseif baseUnit then
        ApplyDragUnit(auras, baseUnit, moverKind, x, y)
    end
    FlushDragRuntime(self, baseUnit, shared, "AURAS3_EDITMODE_DRAG", false)
end

local function AuraGroupDragOnUpdate(me, elapsed)
    if not me._dragging then
        me:SetScript("OnUpdate", nil)
        if me.SetOnUpdateMode then me:SetOnUpdateMode(ONUPDATE_MODE_DISABLED) end
        return
    end
    if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
        local handler = me:GetScript("OnMouseUp")
        if handler then handler(me, "LeftButton") end
        return
    end
    local uiScale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    local mx, my = GetCursorPosition()
    if not (mx and my) then return end
    mx, my = mx / uiScale, my / uiScale
    local dx = mx - (me._dragStartCursorX or mx)
    local dy = my - (me._dragStartCursorY or my)
    if not me._dragMoved then
        if (dx * dx + dy * dy) < 9 then return end
        me._dragMoved = true
    end

    local Snap = _G.MSUF_EM2 and _G.MSUF_EM2.Snap
    if Snap and Snap.IsEnabled and Snap.IsEnabled() and Snap.Apply then
        if Snap.HideGuides then Snap.HideGuides() end
        local sx, sy = Snap.Apply((me._snapStartCX or 0) + dx, (me._snapStartCY or 0) + dy, me._snapHW or 0, me._snapHH or 0, me._msufA3SnapName)
        dx = sx - (me._snapStartCX or 0)
        dy = sy - (me._snapStartCY or 0)
    end
    local frameScale = tonumber(me._dragFrameScale) or tonumber(me._msufA3FrameScale) or 1
    if frameScale <= 0 then frameScale = 1 end
    ApplyDragDelta(me, dx / frameScale, dy / frameScale, elapsed)
end

local activeAuraDragGroup
local pendingAuraDragFrame
local pendingAuraDragGroup
local pendingAuraDragStartX
local pendingAuraDragStartY
local auraDragCaptureFrame
local BeginAuraGroupDrag

local function OpenAuraGroupPopup(group)
    if not (group and IsEditModeActive() and not IsConfigBlocked()) then return false end
    if type(_G.MSUF_OpenAuras3PositionPopup) ~= "function" then return false end
    ExportPublic("MSUF_EM2_ActiveAuraGroup", group._msufA3MoverKind)
    ExportPublic("MSUF_EM2_ActiveAuraUnit", group._msufA3Unit)
    _G.MSUF_OpenAuras3PositionPopup(group._msufA3Unit, group)
    return true
end

local function StopAuraPendingDrag(group)
    if group and pendingAuraDragGroup and pendingAuraDragGroup ~= group then return end
    pendingAuraDragGroup = nil
    pendingAuraDragStartX = nil
    pendingAuraDragStartY = nil
    if pendingAuraDragFrame then
        pendingAuraDragFrame:SetScript("OnUpdate", nil)
        pendingAuraDragFrame:Hide()
    end
end

local function EnsureAuraPendingDragFrame()
    if pendingAuraDragFrame then return pendingAuraDragFrame end
    pendingAuraDragFrame = CreateFrame("Frame", nil, UIParent)
    pendingAuraDragFrame:Hide()
    return pendingAuraDragFrame
end

local function StopAuraDragCapture(group)
    if group and activeAuraDragGroup and activeAuraDragGroup ~= group then return end
    activeAuraDragGroup = nil
    if auraDragCaptureFrame then
        auraDragCaptureFrame:SetScript("OnUpdate", nil)
        auraDragCaptureFrame:Hide()
    end
end

local function EnsureAuraDragCaptureFrame()
    if auraDragCaptureFrame then return auraDragCaptureFrame end
    auraDragCaptureFrame = CreateFrame("Button", nil, UIParent)
    auraDragCaptureFrame:SetAllPoints(UIParent)
    auraDragCaptureFrame:SetFrameStrata("TOOLTIP")
    auraDragCaptureFrame:SetFrameLevel(1500)
    auraDragCaptureFrame:EnableMouse(true)
    if auraDragCaptureFrame.RegisterForClicks then
        auraDragCaptureFrame:RegisterForClicks("LeftButtonUp")
    end
    auraDragCaptureFrame:SetScript("OnMouseUp", function(_, button)
        local target = activeAuraDragGroup
        local handler = target and target:GetScript("OnMouseUp")
        if handler then handler(target, button) end
    end)
    auraDragCaptureFrame:SetScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    auraDragCaptureFrame:Hide()
    return auraDragCaptureFrame
end

local function StartAuraDragCapture(group)
    if not group then return end
    activeAuraDragGroup = group
    local capture = EnsureAuraDragCaptureFrame()
    if capture.SetFrameLevel then
        capture:SetFrameLevel(math_max(1500, (group.GetFrameLevel and (group:GetFrameLevel() or 0) or 0) + 200))
    end
    capture:SetScript("OnUpdate", function(_, elapsed)
        local target = activeAuraDragGroup
        if target and target._dragging then
            AuraGroupDragOnUpdate(target, elapsed)
        else
            StopAuraDragCapture(target)
        end
    end)
    capture:Show()
end

local function QueueAuraPendingDrag(group, button)
    if button ~= "LeftButton" or not group or group._dragging then return false end
    if not IsEditModeActive() or IsConfigBlocked() then return false end
    local cx, cy = GetCursorPosition()
    if not (cx and cy) then return false end
    ExportPublic("MSUF_EM2_ActiveAuraGroup", group._msufA3MoverKind)
    ExportPublic("MSUF_EM2_ActiveAuraUnit", group._msufA3Unit)
    group._suppressNextAuraClick = nil
    pendingAuraDragGroup = group
    pendingAuraDragStartX = cx
    pendingAuraDragStartY = cy

    local frame = EnsureAuraPendingDragFrame()
    frame:SetScript("OnUpdate", function()
        local target = pendingAuraDragGroup
        if not target then
            StopAuraPendingDrag()
            return
        end
        if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
            StopAuraPendingDrag(target)
            return
        end
        if not IsEditModeActive() or IsConfigBlocked() or (target.IsShown and not target:IsShown()) then
            StopAuraPendingDrag(target)
            return
        end
        local mx, my = GetCursorPosition()
        if not (mx and my) then return end
        if math_max(math_abs(mx - (pendingAuraDragStartX or mx)), math_abs(my - (pendingAuraDragStartY or my))) < AURA_PENDING_DRAG_THRESHOLD then
            return
        end
        StopAuraPendingDrag(target)
        if type(BeginAuraGroupDrag) == "function" then BeginAuraGroupDrag(target, true) end
    end)
    frame:Show()
    return true
end

BeginAuraGroupDrag = function(self, fromMotion)
    if not self or self._dragging then return true end
    StopAuraPendingDrag(self)
    if not IsEditModeActive() or IsConfigBlocked() then return false end
    if self.Raise then self:Raise() end

    ExportPublic("MSUF_EM2_ActiveAuraGroup", self._msufA3MoverKind)
    ExportPublic("MSUF_EM2_ActiveAuraUnit", self._msufA3Unit)

    local cfg = ReadGroupConfig(self._msufA3Unit, self._msufA3MoverKind)
    self._dragStartOffsetX = cfg.x
    self._dragStartOffsetY = cfg.y
    self._dragFrameScale = ApplyGroupScaleForFrame(self, GetFrame(self._msufA3Unit))

    local scale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    if not scale or scale == 0 then scale = 1 end
    local cx, cy = GetCursorPosition()
    if not (cx and cy) then return false end
    if type(_G.MSUF_EM_UndoBeginChange) == "function" and not _G.MSUF__UndoRestoring then
        self._msufA3HistoryDrag = _G.MSUF_EM_UndoBeginChange("aura", self._msufA3Unit, "Move") == true
    else
        local before = _G.MSUF_EM_UndoBeforeChange
        if type(before) == "function" and not _G.MSUF__UndoRestoring then before("aura", self._msufA3Unit) end
    end
    self._dragStartCursorX = cx / scale
    self._dragStartCursorY = cy / scale
    self._dragMoved = false
    self._dragStartedByMotion = fromMotion == true
    self._dragging = true
    self._lastDragX = nil
    self._lastDragY = nil
    self._dragRuntimeElapsed = AURA_DRAG_RUNTIME_INTERVAL
    self._dragRuntimePending = nil
    self._lastDragElapsed = 0

    local l, r, t, b = self:GetLeft(), self:GetRight(), self:GetTop(), self:GetBottom()
    if not (l and r and t and b) then
        local centerX, centerY = self:GetCenter()
        local w = self:GetWidth() or 0
        local h = self:GetHeight() or 0
        centerX, centerY = centerX or 0, centerY or 0
        l, r = centerX - w * 0.5, centerX + w * 0.5
        b, t = centerY - h * 0.5, centerY + h * 0.5
    end
    self._snapStartCX = (l + r) * 0.5
    self._snapStartCY = (t + b) * 0.5
    self._snapHW = (r - l) * 0.5
    self._snapHH = (t - b) * 0.5

    if self.SetOnUpdateMode then self:SetOnUpdateMode(ONUPDATE_MODE_RUN_WHEN_VISIBLE) end
    self:SetScript("OnUpdate", AuraGroupDragOnUpdate)
    StartAuraDragCapture(self)
    return true
end

local function EndAuraGroupDrag(self, button, suppressClick)
    if button and button ~= "LeftButton" then return false end
    StopAuraPendingDrag(self)
    if not self then return false end

    if not self._dragging then
        if self._suppressNextAuraClick then
            self._suppressNextAuraClick = nil
            return false
        end
        if not suppressClick and button == "LeftButton" then OpenAuraGroupPopup(self) end
        return false
    end

    local moved = self._dragMoved == true or self._dragStartedByMotion == true
    self._dragging = false
    self:SetScript("OnUpdate", nil)
    StopAuraDragCapture(self)
    if self.SetOnUpdateMode then self:SetOnUpdateMode(ONUPDATE_MODE_DISABLED) end
    self._dragAuras = nil
    self._dragShared = nil
    self._dragRuntimeElapsed = nil
    self._dragRuntimePending = nil
    self._lastDragElapsed = nil
    self._dragStartedByMotion = nil
    if self._msufA3HistoryDrag and type(_G.MSUF_EM_UndoCommitChange) == "function" then
        self._msufA3HistoryDrag = nil
        _G.MSUF_EM_UndoCommitChange()
    end
    local Snap = _G.MSUF_EM2 and _G.MSUF_EM2.Snap
    if Snap and Snap.HideGuides then Snap.HideGuides() end

    if moved then
        local _, shared = EnsureDB()
        RefreshAffectedRuntimeUnits(self._msufA3Unit, shared)
        RequestUnitFrameMenuPreview("AURAS3_EDITMODE_DRAG_END")
        local sync = _G.MSUF_SyncAuras3PositionPopup
        if type(sync) == "function" then sync(self._msufA3Unit) end
        self._lastDragX = nil
        self._lastDragY = nil
        self._dragMoved = false
        self._suppressNextAuraClick = true
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if self then self._suppressNextAuraClick = nil end
            end)
        end
        return true
    end

    if not suppressClick then OpenAuraGroupPopup(self) end
    self._lastDragX = nil
    self._lastDragY = nil
    return false
end

local function ApplyGlobalFont(fs, size)
    if not fs then return end
    local fontPath, fontFlags, r, g, b, _, useShadow
    local gfs = _G.MSUF_GetGlobalFontSettings
    if type(gfs) == "function" then
        fontPath, fontFlags, r, g, b, _, useShadow = gfs()
    end
    fontPath = fontPath or _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    fontFlags = fontFlags or "OUTLINE"
    if fs.SetFont then
        size = tonumber(size) or 14
        if size <= 0 then size = 14 end
        if size < 6 then size = 6 elseif size > 40 then size = 40 end
        pcall(fs.SetFont, fs, fontPath, size, fontFlags)
    end
    if fs.SetTextColor then fs:SetTextColor(r or 1, g or 1, b or 1, 1) end
    if fs.SetShadowOffset then
        if useShadow then fs:SetShadowOffset(1, -1) else fs:SetShadowOffset(0, 0) end
    end
end

local function PlaceStackText(fs, owner, cfg)
    if not fs or not owner or not cfg then return end
    fs:ClearAllPoints()
    if cfg.stackAnchor == "TOPLEFT" then
        fs:SetPoint("TOPLEFT", owner, "TOPLEFT", cfg.stackX, cfg.stackY)
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("TOP")
    elseif cfg.stackAnchor == "BOTTOMLEFT" then
        fs:SetPoint("BOTTOMLEFT", owner, "BOTTOMLEFT", cfg.stackX, cfg.stackY)
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("BOTTOM")
    elseif cfg.stackAnchor == "BOTTOMRIGHT" then
        fs:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", cfg.stackX, cfg.stackY)
        fs:SetJustifyH("RIGHT")
        fs:SetJustifyV("BOTTOM")
    else
        fs:SetPoint("TOPRIGHT", owner, "TOPRIGHT", cfg.stackX, cfg.stackY)
        fs:SetJustifyH("RIGHT")
        fs:SetJustifyV("TOP")
    end
end

local function PlaceCooldownText(fs, owner, cfg)
    if not fs or not owner or not cfg then return end
    fs:ClearAllPoints()
    local anchor = AURA_TEXT_ANCHOR_OK[cfg.cooldownAnchor] and cfg.cooldownAnchor or "CENTER"
    fs:SetPoint(anchor, owner, anchor, cfg.cooldownX or 0, cfg.cooldownY or 0)
    if anchor == "TOPLEFT" or anchor == "LEFT" or anchor == "BOTTOMLEFT" then
        fs:SetJustifyH("LEFT")
    elseif anchor == "TOPRIGHT" or anchor == "RIGHT" or anchor == "BOTTOMRIGHT" then
        fs:SetJustifyH("RIGHT")
    else
        fs:SetJustifyH("CENTER")
    end
    if anchor == "TOPLEFT" or anchor == "TOP" or anchor == "TOPRIGHT" then
        fs:SetJustifyV("TOP")
    elseif anchor == "BOTTOMLEFT" or anchor == "BOTTOM" or anchor == "BOTTOMRIGHT" then
        fs:SetJustifyV("BOTTOM")
    else
        fs:SetJustifyV("MIDDLE")
    end
end

local function SafeFrameCall(frame, methodName, ...)
    local method = frame and frame[methodName]
    if type(method) ~= "function" then return nil end
    local ok, value = pcall(method, frame, ...)
    if ok then return value end
    return nil
end

local function IsSecretValue(value)
    -- issecretvalue is the sanctioned never-throwing probe.
    if type(issecretvalue) ~= "function" then return true end
    return issecretvalue(value) == true
end

local function SafeFrameBool(frame, methodName)
    local value = SafeFrameCall(frame, methodName)
    if value == nil then return nil end
    if IsSecretValue(value) then return nil end
    return value == true
end

local function StoreAuraMouseState(frame)
    if not frame or frame._msufA3EditMouseStored == true then return end
    frame._msufA3EditMouseStored = true
    frame._msufA3EditMouseEnabled = SafeFrameBool(frame, "IsMouseEnabled")
    frame._msufA3EditClickEnabled = SafeFrameBool(frame, "IsMouseClickEnabled")
    frame._msufA3EditMotionEnabled = SafeFrameBool(frame, "IsMouseMotionEnabled")
    frame._msufA3EditPropagateClicks = SafeFrameBool(frame, "GetPropagateMouseClicks")
end

local function SuppressAuraMouse(frame, forwardClicks)
    if not frame then return end
    StoreAuraMouseState(frame)
    local hasClick = type(frame.SetMouseClickEnabled) == "function"
    local hasMotion = type(frame.SetMouseMotionEnabled) == "function"
    if type(frame.EnableMouse) == "function" then
        SafeFrameCall(frame, "EnableMouse", forwardClicks ~= false)
    end
    if hasClick then SafeFrameCall(frame, "SetMouseClickEnabled", forwardClicks ~= false) end
    if hasMotion then SafeFrameCall(frame, "SetMouseMotionEnabled", false) end
    if forwardClicks ~= false then
        SafeFrameCall(frame, "SetPropagateMouseClicks", true)
        frame._msufA3EditPropagateChanged = true
    end
end

local function RestoreAuraMouse(frame, motionEnabled, fallbackClickEnabled)
    if not frame then return end
    local stored = frame._msufA3EditMouseStored == true
    local mouseEnabled = frame._msufA3EditMouseEnabled
    local clickEnabled = frame._msufA3EditClickEnabled
    local storedMotionEnabled = frame._msufA3EditMotionEnabled
    local propagateClicks = frame._msufA3EditPropagateClicks
    local propagateChanged = frame._msufA3EditPropagateChanged

    frame._msufA3EditMouseStored = nil
    frame._msufA3EditMouseEnabled = nil
    frame._msufA3EditClickEnabled = nil
    frame._msufA3EditMotionEnabled = nil
    frame._msufA3EditPropagateClicks = nil
    frame._msufA3EditPropagateChanged = nil

    local hasClick = type(frame.SetMouseClickEnabled) == "function"
    local hasMotion = type(frame.SetMouseMotionEnabled) == "function"
    if type(frame.EnableMouse) == "function" then
        if mouseEnabled ~= nil then
            SafeFrameCall(frame, "EnableMouse", mouseEnabled)
        elseif not hasClick and not hasMotion then
            if stored ~= true or fallbackClickEnabled == true then
                mouseEnabled = true
            elseif motionEnabled ~= nil then
                mouseEnabled = motionEnabled
            else
                mouseEnabled = false
            end
            SafeFrameCall(frame, "EnableMouse", mouseEnabled)
        end
    end
    if hasClick then
        if clickEnabled == nil then clickEnabled = fallbackClickEnabled == true end
        SafeFrameCall(frame, "SetMouseClickEnabled", clickEnabled)
    end
    if hasMotion then
        if motionEnabled == nil then motionEnabled = storedMotionEnabled end
        if motionEnabled == nil then motionEnabled = false end
        SafeFrameCall(frame, "SetMouseMotionEnabled", motionEnabled)
    end
    if propagateClicks ~= nil then
        SafeFrameCall(frame, "SetPropagateMouseClicks", propagateClicks)
    elseif propagateChanged == true then
        SafeFrameCall(frame, "SetPropagateMouseClicks", false)
    end
end

local function NativeAuraEditGroup(frame)
    if not frame or not IsEditModeActive() then return nil end
    local container = frame._msufA3EditForwardContainer or frame
    local laneKind = container._msufA3NativeLane
    if laneKind == "buffs" then laneKind = "buff" end
    if laneKind == "debuffs" then laneKind = "debuff" end
    if laneKind ~= "buff" and laneKind ~= "debuff" then return nil end
    local lane = container._msufA3NativeLaneConfig
    local unit = (lane and lane.unit) or container.unit
    return unit and EM.groups and EM.groups[unit] and EM.groups[unit][laneKind] or nil
end

local function ForwardNativeAuraMouse(frame, scriptName, button)
    if button ~= "LeftButton" and button ~= "RightButton" then return end
    local group = NativeAuraEditGroup(frame)
    local handler = group and group:GetScript(scriptName)
    if handler then handler(group, button) end
end

local function WireNativeAuraEditForward(frame, container)
    if not (frame and frame.HookScript) then return false end
    if frame._msufA3EditDragForwardHooked == true then return true end
    frame._msufA3EditForwardContainer = container or frame
    local okDown = pcall(frame.HookScript, frame, "OnMouseDown", function(self, button)
        ForwardNativeAuraMouse(self, "OnMouseDown", button)
    end)
    local okUp = pcall(frame.HookScript, frame, "OnMouseUp", function(self, button)
        ForwardNativeAuraMouse(self, "OnMouseUp", button)
    end)
    frame._msufA3EditDragForwardHooked = (okDown or okUp) and true or nil
    return frame._msufA3EditDragForwardHooked == true
end

local function SetLaneMouseSuppressed(element, container, suppressed)
    if not container then return end
    local laneKind = container._msufA3NativeLane
    local forwardKind = laneKind
    if forwardKind == "buffs" then forwardKind = "buff" end
    if forwardKind == "debuffs" then forwardKind = "debuff" end
    local canForward = forwardKind == "buff" or forwardKind == "debuff"
    local laneCfg = element and element._msufA3Config and element._msufA3Config.lanes and element._msufA3Config.lanes[laneKind]
    local motionEnabled = not laneCfg or laneCfg.showTooltip ~= false
    local nativeLaneCfg = container._msufA3NativeLaneConfig or laneCfg
    local cancelablePlayerBuff = forwardKind == "buff"
        and nativeLaneCfg and nativeLaneCfg.unit == "player"
    if suppressed then
        if canForward then WireNativeAuraEditForward(container, container) end
        SuppressAuraMouse(container, canForward)
    else
        RestoreAuraMouse(container, nil, false)
    end

    local count = type(container.GetAuraFrameCount) == "function" and container:GetAuraFrameCount() or tonumber(container.createdButtons) or 0
    for i = 1, count do
        local ok, button
        if type(container.GetAuraFrame) == "function" then
            ok, button = pcall(container.GetAuraFrame, container, i)
        end
        if not button then button = container[i] end
        if ok ~= false and button then
            if suppressed then
                if canForward then WireNativeAuraEditForward(button, container) end
                SuppressAuraMouse(button, canForward)
            else
                -- Forbidden buttons can hide their stored input state. Restore
                -- the sole runtime exception (Player Buff RightButtonUp cancel)
                -- and keep every other AuraButton click-through.
                RestoreAuraMouse(button, motionEnabled, cancelablePlayerBuff)
            end
        end
    end
end

local function SetRuntimeAuraHidden(unit, hidden)
    local frame = GetFrame(unit)
    local element = frame and frame.Auras
    if not element or not element.SetAlpha then return end
    if hidden then
        if element._msufA3EditModeAlpha == nil and element.GetAlpha then
            element._msufA3EditModeAlpha = element:GetAlpha()
        end
        element:SetAlpha(0)
        SetLaneMouseSuppressed(element, element.Buffs, true)
        SetLaneMouseSuppressed(element, element.Debuffs, true)
        SetLaneMouseSuppressed(element, element.Externals, true)
    elseif element._msufA3EditModeAlpha ~= nil then
        element:SetAlpha(element._msufA3EditModeAlpha)
        element._msufA3EditModeAlpha = nil
        SetLaneMouseSuppressed(element, element.Buffs, false)
        SetLaneMouseSuppressed(element, element.Debuffs, false)
        SetLaneMouseSuppressed(element, element.Externals, false)
    end
end

local function StyleLabel(fs)
    ApplyGlobalFont(fs, 11)
    if fs and fs.SetTextColor then fs:SetTextColor(0.92, 0.96, 1, 0.95) end
end

local function EnsureIcon(group, index)
    local icons = group._icons
    if not icons then
        icons = {}
        group._icons = icons
    end
    local icon = icons[index]
    if icon then return icon end

    icon = CreateFrame("Frame", nil, group.Body or group, "BackdropTemplate")
    icon:SetBackdrop({ bgFile = W8, edgeFile = W8, edgeSize = 1 })
    icon:SetBackdropColor(0, 0, 0, 0)
    icon:SetBackdropBorderColor(0, 0, 0, 0)

    local tex = icon:CreateTexture(nil, "BORDER")
    tex:SetAllPoints(icon)
    tex:SetTexCoord(0, 1, 0, 1)
    icon.Icon = tex

    local shade = icon:CreateTexture(nil, "ARTWORK")
    shade:SetAllPoints(icon)
    shade:SetColorTexture(0, 0, 0, 0)
    icon.Shade = shade

    -- Preview-only deterministic swipe. The shared preview animation advances
    -- its width; no native Cooldown state survives an Off -> On transition.
    local swipe = icon:CreateTexture(nil, "ARTWORK", nil, 1)
    swipe:SetTexture(W8)
    swipe:SetVertexColor(0, 0, 0, 0.58)
    swipe:Hide()
    icon.Swipe = swipe

    local durationBar = icon:CreateTexture(nil, "OVERLAY")
    durationBar:SetTexture(W8)
    local durationR, durationG, durationB = AuraDurationBarColor()
    durationBar:SetVertexColor(durationR, durationG, durationB, 0.92)
    durationBar:Hide()
    icon.DurationBar = durationBar

    local dispelBorder = icon:CreateTexture(nil, "OVERLAY", nil, 2)
    dispelBorder:Hide()
    icon.DispelBorder = dispelBorder

    local cd = icon:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if cd.SetDrawLayer then
        cd:SetDrawLayer("OVERLAY", FrameLayers.AURA_COOLDOWN_TEXT_DRAW_SUBLEVEL or 7)
    end
    cd:SetPoint("CENTER", icon, "CENTER", 0, 0)
    ApplyGlobalFont(cd, 14)
    cd:SetText("1m")
    icon.CooldownText = cd

    local count = icon:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if count.SetDrawLayer then
        count:SetDrawLayer("OVERLAY", FrameLayers.AURA_STACK_DRAW_SUBLEVEL or 6)
    end
    ApplyGlobalFont(count, 14)
    count:SetText(index == 1 and "3" or "")
    icon.Count = count

    icons[index] = icon
    return icon
end

local function LayoutPreviewSwipe(icon, cfg, remainingFrac)
    local swipe = icon and icon.Swipe
    local barOnly = cfg and cfg.showDurationBar == true and cfg.durationBarDisplay == "BAR_ONLY"
    if not (swipe and cfg and cfg.showCooldownSwipe ~= false and not barOnly) then
        if swipe then swipe:Hide() end
        return
    end
    local size = math_max(1, (icon.GetWidth and icon:GetWidth()) or 1)
    -- Keep the preview legible at both ends of its loop while preserving the
    -- configured direction and the existing event-driven animation cadence.
    local frac = math_max(0.08, math_min(0.92, tonumber(remainingFrac) or 0.48))
    swipe:ClearAllPoints()
    swipe:SetWidth(math_max(1, math_floor(size * frac + 0.5)))
    swipe:SetHeight(size)
    if cfg.cooldownSwipeReverse == true then
        swipe:SetPoint("TOPLEFT", icon, "TOPLEFT")
        swipe:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT")
    else
        swipe:SetPoint("TOPRIGHT", icon, "TOPRIGHT")
        swipe:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT")
    end
    swipe:Show()
end

local function LayoutPreviewDispelBorder(icon, cfg, index)
    local border = icon and icon.DispelBorder
    local atlas = cfg and DEBUFF_TYPE_BORDER_PREVIEW_ATLAS[cfg.debuffBorderMode]
    local barOnly = cfg and cfg.showDurationBar == true and cfg.durationBarDisplay == "BAR_ONLY"
    local size = math_max(1, (icon and icon.GetWidth and icon:GetWidth()) or 24)
    if not barOnly and type(A3.ApplyAuraDispelPreview) == "function"
        and A3.ApplyAuraDispelPreview(border, icon, size, cfg and cfg.debuffBorderMode,
            cfg and cfg.iconShape, A3.PreviewDispelTypeForIndex(index)) then
        return
    end
    if not (border and atlas and border.SetAtlas and not barOnly) then
        if border then border:Hide() end
        return
    end
    local pad = type(A3.NativeAuraDispelBorderPadding) == "function"
        and A3.NativeAuraDispelBorderPadding(size)
        or math_max(1, math_floor(size / 6 + 0.5))
    border:ClearAllPoints()
    border:SetPoint("TOPLEFT", icon, "TOPLEFT", -pad, pad)
    border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", pad, -pad)
    border:SetAtlas(atlas, TextureKitConstants and TextureKitConstants.IgnoreAtlasSize)
    border:Show()
end

local function ApplyIconZoom(texture, zoom)
    if not (texture and texture.SetTexCoord) then return end
    zoom = Clamp(zoom, 100, 100, 200)
    local visible = 100 / zoom
    local inset = (1 - visible) * 0.5
    texture:SetTexCoord(inset, 1 - inset, inset, 1 - inset)
end

local function ApplyPreviewIconText(icon, unit, cfg, index)
    cfg = cfg or ReadTextConfig(unit)
    local barOnly = cfg.showDurationBar == true and cfg.durationBarDisplay == "BAR_ONLY"
    if icon.Icon then icon.Icon:SetShown(not barOnly) end
    if icon.Shade then icon.Shade:SetShown(not barOnly) end
    if icon.Count then
        ApplyGlobalFont(icon.Count, cfg.stackSize)
        PlaceStackText(icon.Count, icon, cfg)
        icon.Count:SetShown(cfg.showStackCount ~= false)
    end
    if icon.CooldownText then
        ApplyGlobalFont(icon.CooldownText, cfg.cooldownSize)
        PlaceCooldownText(icon.CooldownText, icon, cfg)
        icon.CooldownText:SetShown(cfg.showCooldownText ~= false)
    end
    LayoutPreviewSwipe(icon, cfg)
    LayoutPreviewDispelBorder(icon, cfg, index)
    if icon.DurationBar then
        if cfg.showDurationBar == true then
            local height = Clamp(cfg.durationBarHeight, 2, 1, 16)
            local inset = 1
            icon.DurationBar:ClearAllPoints()
            icon.DurationBar:SetHeight(height)
            if cfg.durationBarPosition == "TOP" then
                icon.DurationBar:SetPoint("TOPLEFT", icon, "TOPLEFT", inset, -inset)
                icon.DurationBar:SetPoint("TOPRIGHT", icon, "TOPRIGHT", -inset, -inset)
            else
                icon.DurationBar:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", inset, inset)
                icon.DurationBar:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -inset, inset)
            end
            local r, g, b = AuraDurationBarColor()
            icon.DurationBar:SetVertexColor(r, g, b, 0.92)
            icon.DurationBar:Show()
        else
            icon.DurationBar:Hide()
        end
    end
end

local function PreviewAuraState(kind, index, icon, cfg, elapsed)
    local previewAnimation = MSUF and MSUF.PreviewAnimation
    local fn = elapsed ~= nil and (previewAnimation and previewAnimation.BuildAuraState
        or _G.MSUF_BuildPreviewAnimationAuraState)
        or _G.MSUF_GetPreviewAnimationAuraState
    if type(fn) ~= "function" then return nil end
    icon._msufA3PreviewAuraScratch = icon._msufA3PreviewAuraScratch or {}
    local options = icon._msufA3PreviewAuraOptions
    if not options then
        options = {}
        icon._msufA3PreviewAuraOptions = options
    end
    options.decimalThreshold = tonumber(cfg and cfg.cooldownDecimalSeconds) or 3
    if elapsed ~= nil then
        return fn(kind, index, icon._msufA3PreviewAuraScratch, options, elapsed)
    end
    return fn(kind, index, icon._msufA3PreviewAuraScratch, options)
end

local function ApplyPreviewDurationBarProgress(icon, cfg, auraState)
    local bar = icon and icon.DurationBar
    if not (bar and cfg and cfg.showDurationBar == true) then
        if bar then bar:Hide() end
        return
    end
    local size = math_max(1, (icon.GetWidth and icon:GetWidth()) or 1)
    local height = Clamp(cfg.durationBarHeight, 2, 1, math_max(1, size))
    local inset = math_max(1, math_floor(size / 32 + 0.5))
    local frac
    if cfg.durationBarDirection == "ELAPSED" then
        frac = auraState and auraState.elapsedFrac or 1
    else
        frac = auraState and auraState.remainingFrac or 1
    end
    local r, g, b = AuraDurationBarColor()
    bar:SetVertexColor(r, g, b, 0.92)
    frac = math_max(0.02, math_min(1, tonumber(frac) or 1))
    bar:ClearAllPoints()
    bar:SetHeight(height)
    if auraState then
        bar:SetWidth(math_max(1, math_floor(math_max(1, size - inset * 2) * frac + 0.5)))
        if cfg.durationBarPosition == "TOP" then
            bar:SetPoint("TOPLEFT", icon, "TOPLEFT", inset, -inset)
        else
            bar:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", inset, inset)
        end
    elseif cfg.durationBarPosition == "TOP" then
        bar:SetPoint("TOPLEFT", icon, "TOPLEFT", inset, -inset)
        bar:SetPoint("TOPRIGHT", icon, "TOPRIGHT", -inset, -inset)
    else
        bar:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", inset, inset)
        bar:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -inset, inset)
    end
    bar:Show()
end

local function ApplyPreviewAuraAnimation(group, kind, shownIcons, textCfg, elapsed)
    local icons = group and group._icons
    if not icons then return end
    for i = 1, shownIcons do
        local icon = icons[i]
        if icon then
            local auraState = PreviewAuraState(kind, i, icon, textCfg, elapsed)
            if icon.Count then icon.Count:SetText(textCfg.showStackCount ~= false and (auraState and auraState.stacks or (i == 1 and "3" or "")) or "") end
            if icon.CooldownText then icon.CooldownText:SetText(textCfg.showCooldownText ~= false and (auraState and auraState.text or (i == 1 and "1m" or "32")) or "") end
            LayoutPreviewSwipe(icon, textCfg, auraState and auraState.remainingFrac)
            ApplyPreviewDurationBarProgress(icon, textCfg, auraState)
        end
    end
end

local function CreateGroup(unit, kind)
    kind = NormalizeKind(kind)
    EM.groups = EM.groups or {}
    local byUnit = EM.groups[unit]
    if not byUnit then
        byUnit = {}
        EM.groups[unit] = byUnit
    end
    if byUnit[kind] then return byUnit[kind] end

    local spec = GROUPS[kind]
    local snapName = "AuraPreview:" .. tostring(unit) .. ":" .. tostring(kind)
    local group = CreateFrame("Button", nil, UIParent, "BackdropTemplate")
    SyncPreviewGroupStrata(group)
    group:SetFrameLevel(900)
    group:SetClampedToScreen(false)
    group:SetMovable(true)
    group:EnableMouse(true)
    if group.SetMouseClickEnabled then group:SetMouseClickEnabled(true) end
    if group.SetMouseMotionEnabled then group:SetMouseMotionEnabled(true) end
    if group.RegisterForClicks then group:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    if group.RegisterForDrag then group:RegisterForDrag("LeftButton") end
    group:SetBackdrop({ bgFile = W8, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    group:SetBackdropColor(0.02, 0.03, 0.08, 0.28)
    group:SetBackdropBorderColor(spec.color[1], spec.color[2], spec.color[3], 0.72)

    local header = CreateFrame("Frame", nil, group, "BackdropTemplate")
    header:SetPoint("TOPLEFT", group, "TOPLEFT", 2, -2)
    header:SetPoint("TOPRIGHT", group, "TOPRIGHT", -2, -2)
    header:SetHeight(HEADER_H)
    header:SetBackdrop({ bgFile = W8 })
    header:SetBackdropColor(spec.color[1], spec.color[2], spec.color[3], spec.color[4])
    group.Header = header

    local label = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", header, "LEFT", 6, 0)
    label:SetPoint("RIGHT", header, "RIGHT", -6, 0)
    label:SetJustifyH("LEFT")
    StyleLabel(label)
    label:SetText(UnitLabel(unit) .. " " .. GroupLabel(unit, kind, spec))
    group.Label = label

    local body = CreateFrame("Frame", nil, group)
    body:SetPoint("BOTTOMLEFT", group, "BOTTOMLEFT", 0, 0)
    body:SetSize(1, 1)
    group.Body = body

    group._msufA3Unit = unit
    group._msufA3MoverKind = kind
    group._msufA3SnapName = snapName
    group:Hide()

    group:SetScript("OnMouseDown", function(self, button)
        if button == "RightButton" then
            StopAuraPendingDrag(self)
            OpenAuraGroupPopup(self)
            return
        end
        QueueAuraPendingDrag(self, button)
    end)

    group:SetScript("OnMouseUp", function(self, button)
        EndAuraGroupDrag(self, button)
    end)
    group:SetScript("OnDragStart", function(self)
        BeginAuraGroupDrag(self, true)
    end)
    group:SetScript("OnDragStop", function(self)
        EndAuraGroupDrag(self, "LeftButton")
    end)
    group:SetScript("OnHide", function(self)
        EndAuraGroupDrag(self, "LeftButton", true)
    end)

    local hitbox = CreateFrame("Button", nil, group)
    hitbox:SetAllPoints(group)
    hitbox:EnableMouse(true)
    if hitbox.SetMouseClickEnabled then hitbox:SetMouseClickEnabled(true) end
    if hitbox.SetMouseMotionEnabled then hitbox:SetMouseMotionEnabled(true) end
    if hitbox.RegisterForClicks then hitbox:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    if hitbox.RegisterForDrag then hitbox:RegisterForDrag("LeftButton") end
    hitbox._msufA3HitboxOwner = group
    hitbox:SetScript("OnMouseDown", function(self, button)
        local owner = self._msufA3HitboxOwner or self:GetParent()
        if button == "RightButton" then
            StopAuraPendingDrag(owner)
            OpenAuraGroupPopup(owner)
        else
            QueueAuraPendingDrag(owner, button)
        end
    end)
    hitbox:SetScript("OnMouseUp", function(self, button)
        local owner = self._msufA3HitboxOwner or self:GetParent()
        EndAuraGroupDrag(owner, button)
    end)
    hitbox:SetScript("OnDragStart", function(self)
        local owner = self._msufA3HitboxOwner or self:GetParent()
        BeginAuraGroupDrag(owner, true)
    end)
    hitbox:SetScript("OnDragStop", function(self)
        local owner = self._msufA3HitboxOwner or self:GetParent()
        EndAuraGroupDrag(owner, "LeftButton")
    end)
    group.Hitbox = hitbox

    byUnit[kind] = group
    return group
end

local function ApplyEditModeCustomEffect(group, frame, item)
    local effect = item and item.frame
    local kind = type(effect) == "table" and tostring(effect.type or "none"):lower() or "none"
    local root = group and group._msufA3CustomEffectPreview
    if kind == "none" then
        if root then root:Hide() end
        return
    end
    local health = frame and (frame.hpBar or frame.Health or frame.health)
    local target = health and health.GetStatusBarTexture and health:GetStatusBarTexture()
    local nameSource = frame and (frame.Name or frame.name or frame.NameText or frame.nameText or frame._nameFS)
    if kind ~= "namecolor" and not (health and target) then
        if root then root:Hide() end
        return
    end
    if kind == "namecolor" and not nameSource then
        if root then root:Hide() end
        return
    end
    if not root then
        root = CreateFrame("Frame", nil, group)
        root:EnableMouse(false)
        root.tint = root:CreateTexture(nil, "OVERLAY")
        root.tint:SetTexture(W8)
        root.edges = {}
        for i = 1, 4 do
            root.edges[i] = root:CreateTexture(nil, "OVERLAY")
            root.edges[i]:SetTexture(W8)
        end
        root.name = root:CreateFontString(nil, "OVERLAY")
        group._msufA3CustomEffectPreview = root
    end
    if not root.name then root.name = root:CreateFontString(nil, "OVERLAY") end
    root:ClearAllPoints()
    root:SetAllPoints(health or frame)
    if root.SetFrameLevel then
        local priority = Clamp(effect.priority, 5, 1, 10)
        local layer = Clamp(effect.layer, 0, 0, 30)
        local targetOwner = health
        if kind == "namecolor" then
            targetOwner = nameSource and nameSource.GetParent and nameSource:GetParent() or frame
        end
        root:SetFrameLevel(FrameLayers.AuraEffectLevel and FrameLayers.AuraEffectLevel(layer, priority, targetOwner)
            or FrameLayers.ElementLevel and FrameLayers.ElementLevel(layer, 0, 11 - priority)
            or ((group:GetFrameLevel() or 900) + SPELL_FRAME_EFFECT_BASE_OFFSET + (11 - priority) + layer))
    end
    root.tint:Hide()
    for i = 1, 4 do root.edges[i]:Hide() end
    root.name:Hide()
    local color = effect.color or {}
    local r, g, b, a = color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 0.8
    if kind == "healthtint" then
        root.tint:ClearAllPoints()
        root.tint:SetAllPoints(target)
        root.tint:SetVertexColor(r, g, b, tonumber(effect.tintAlpha) or a)
        root.tint:Show()
    elseif kind == "namecolor" then
        local path, size, flags
        if nameSource.GetFont then path, size, flags = nameSource:GetFont() end
        if path and size then root.name:SetFont(path, size, flags) end
        if nameSource.GetJustifyH then root.name:SetJustifyH(nameSource:GetJustifyH()) end
        if nameSource.GetJustifyV then root.name:SetJustifyV(nameSource:GetJustifyV()) end
        if nameSource.GetShadowColor then root.name:SetShadowColor(nameSource:GetShadowColor()) end
        if nameSource.GetShadowOffset then root.name:SetShadowOffset(nameSource:GetShadowOffset()) end
        root.name:ClearAllPoints()
        root.name:SetAllPoints(nameSource)
        root.name:SetText(nameSource.GetText and nameSource:GetText() or "")
        root.name:SetTextColor(r, g, b, a)
        root.name:Show()
    elseif kind == "border" or kind == "glow" or kind == "pulse" then
        local thickness = Clamp(effect.thickness, kind == "glow" and 3 or 2, 1, 16)
        local top, bottom, left, right = root.edges[1], root.edges[2], root.edges[3], root.edges[4]
        top:ClearAllPoints(); top:SetPoint("TOPLEFT", target, "TOPLEFT", -thickness, thickness); top:SetPoint("TOPRIGHT", target, "TOPRIGHT", thickness, thickness); top:SetHeight(thickness)
        bottom:ClearAllPoints(); bottom:SetPoint("BOTTOMLEFT", target, "BOTTOMLEFT", -thickness, -thickness); bottom:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", thickness, -thickness); bottom:SetHeight(thickness)
        left:ClearAllPoints(); left:SetPoint("TOPLEFT", top, "BOTTOMLEFT"); left:SetPoint("BOTTOMLEFT", bottom, "TOPLEFT"); left:SetWidth(thickness)
        right:ClearAllPoints(); right:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT"); right:SetPoint("BOTTOMRIGHT", bottom, "TOPRIGHT"); right:SetWidth(thickness)
        for i = 1, 4 do root.edges[i]:SetVertexColor(r, g, b, kind == "glow" and math_min(1, a + 0.16) or a); root.edges[i]:Show() end
    end
    root:Show()
end

local function FrameRefreshSignature(frame)
    if not frame then return "noframe" end
    local l = frame.GetLeft and frame:GetLeft() or 0
    local t = frame.GetTop and frame:GetTop() or 0
    local w = frame.GetWidth and frame:GetWidth() or 0
    local h = frame.GetHeight and frame:GetHeight() or 0
    return tostring(Round(l or 0)) .. "\031" .. tostring(Round(t or 0))
        .. "\031" .. tostring(Round(w or 0)) .. "\031" .. tostring(Round(h or 0))
        .. "\031" .. tostring(Round(FrameScaleRelativeToUIParent(frame) * 1000))
end

local function EditModeThemeRevision()
    local menu = MSUF and MSUF.MSUF2
    return tostring((menu and (menu._msuf2MenuDataRevision or menu._msuf2LayoutVersion)) or 0)
end

local function RefreshSignature(unit, kind, cfg, metrics, textCfg, shownIcons, size, step, perRow, laneW, laneH, growthX, growthY, vertical, initialAnchor, x, y, anchor, frameSig)
    return tostring(unit) .. "\030" .. tostring(kind) .. "\030" .. tostring(frameSig)
        .. "\030" .. EditModeThemeRevision()
        .. "\030" .. tostring(cfg and cfg.show) .. "\030" .. tostring(metrics and metrics.num or cfg and cfg.max)
        .. "\030" .. tostring(metrics and metrics.layer or cfg and cfg.layer)
        .. "\030" .. tostring(metrics and metrics.spacing or cfg and cfg.spacing)
        .. "\030" .. tostring(metrics and metrics.alpha or cfg and cfg.alpha)
        .. "\030" .. tostring(shownIcons) .. "\030" .. tostring(size)
        .. "\030" .. tostring(step) .. "\030" .. tostring(perRow)
        .. "\030" .. tostring(laneW) .. "\030" .. tostring(laneH)
        .. "\030" .. tostring(growthX) .. "\030" .. tostring(growthY)
        .. "\030" .. tostring(vertical) .. "\030" .. tostring(initialAnchor)
        .. "\030" .. tostring(x) .. "\030" .. tostring(y) .. "\030" .. tostring(anchor)
        .. "\030" .. tostring(metrics and metrics.enabled)
        .. "\030" .. tostring(metrics and metrics.iconZoom or cfg and cfg.iconZoom)
        .. "\030" .. tostring(metrics and metrics.iconShape or cfg and cfg.iconShape)
        .. "\030" .. tostring(textCfg and textCfg.stackSize) .. "\030" .. tostring(textCfg and textCfg.stackX)
        .. "\030" .. tostring(textCfg and textCfg.stackY) .. "\030" .. tostring(textCfg and textCfg.cooldownSize)
        .. "\030" .. tostring(textCfg and textCfg.cooldownX) .. "\030" .. tostring(textCfg and textCfg.cooldownY)
        .. "\030" .. tostring(textCfg and textCfg.cooldownDecimalSeconds)
        .. "\030" .. tostring(textCfg and textCfg.stackAnchor) .. "\030" .. tostring(textCfg and textCfg.cooldownAnchor)
        .. "\030" .. tostring(textCfg and textCfg.showDurationBar) .. "\030" .. tostring(textCfg and textCfg.durationBarHeight)
        .. "\030" .. tostring(textCfg and textCfg.durationBarDisplay) .. "\030" .. tostring(textCfg and textCfg.durationBarPosition)
        .. "\030" .. tostring(textCfg and textCfg.durationBarDirection)
        .. "\030" .. tostring(textCfg and textCfg.showStackCount) .. "\030" .. tostring(textCfg and textCfg.showCooldownText)
        .. "\030" .. tostring(textCfg and textCfg.showCooldownSwipe) .. "\030" .. tostring(textCfg and textCfg.cooldownSwipeReverse)
        .. "\030" .. tostring(textCfg and textCfg.debuffBorderMode)
end

--- Edit mode shows draggable chrome (header, tinted backdrop, mouse). The boss
--- page preview renders the same lanes chromeless and click-through so they
--- read as pure aura previews on top of the previewed frames.
local function ApplyGroupChrome(group, spec, chrome)
    if not group or group._msufA3ChromeMode == chrome then return end
    group._msufA3ChromeMode = chrome
    if group.Header then group.Header:SetShown(chrome) end
    if group.SetBackdropColor then group:SetBackdropColor(0.02, 0.03, 0.08, chrome and 0.28 or 0) end
    if group.SetBackdropBorderColor then
        local color = (spec and spec.color) or {}
        group:SetBackdropBorderColor(color[1] or 1, color[2] or 1, color[3] or 1, chrome and 0.72 or 0)
    end
    local interactive = chrome == true
    group:EnableMouse(interactive)
    if group.SetMouseClickEnabled then group:SetMouseClickEnabled(interactive) end
    if group.SetMouseMotionEnabled then group:SetMouseMotionEnabled(interactive) end
    local hitbox = group.Hitbox
    if hitbox then
        hitbox:EnableMouse(interactive)
        if hitbox.SetMouseClickEnabled then hitbox:SetMouseClickEnabled(interactive) end
        if hitbox.SetMouseMotionEnabled then hitbox:SetMouseMotionEnabled(interactive) end
    end
end

function EM.HideUnit(unit)
    if IsBossScope(unit) then
        ForEachBossUnit(EM.HideUnit)
        return
    end
    local byUnit = EM.groups and EM.groups[unit]
    SetRuntimeAuraHidden(unit, false)
    if not byUnit then return end
    for _, group in pairs(byUnit) do
        if group then
            group._msufA3RefreshSignature = nil
            group:Hide()
        end
    end
end

function EM.RefreshUnit(unit)
    if not unit then return end
    if IsBossScope(unit) then
        ForEachBossUnit(EM.RefreshUnit)
        return
    end
    if not UnitPreviewActive(unit) then
        EM.HideUnit(unit)
        return
    end

    local auras, shared = EnsureDB()
    -- showInEditMode is an edit-mode-only toggle; the boss page preview keeps
    -- rendering lanes regardless because it is the page's whole purpose.
    if not shared or (EditPreviewActive() and shared.showInEditMode == false)
        or (not UnitEnabled(auras, unit) and not UnitHasCustomPreview(unit)) then
        EM.HideUnit(unit)
        return
    end

    local frame = GetFrame(unit)
    if not frame then
        EM.HideUnit(unit)
        return
    end
    -- Outside edit mode (boss page preview) lanes only make sense on frames the
    -- preview actually shows; edit mode forces its frames visible itself.
    if not EditPreviewActive() and frame.IsShown and not frame:IsShown() then
        EM.HideUnit(unit)
        return
    end

    SetRuntimeAuraHidden(unit, true)
    local frameSig = FrameRefreshSignature(frame)

    local chrome = EditPreviewActive()
    for kind, spec in pairs(GROUPS) do
        local cfg = ReadGroupConfig(unit, kind)
        local metrics = type(A3.BuildAuraLaneMetrics) == "function" and A3.BuildAuraLaneMetrics(unit, kind) or nil
        local group = CreateGroup(unit, kind)
        SyncPreviewGroupStrata(group)
        local entries = spec.customIndex and CustomPreviewEntries(unit, kind) or nil
        -- Target DoTs retain their configuration preview while disabled.
        -- Player Defensives obey their master switch in Edit Mode as well.
        local laneShown = cfg.show
            or (unit ~= "player" and spec.customIndex == 4 and entries ~= nil)
        -- Outside edit mode custom lanes stay strictly 1:1 with the runtime:
        -- nothing tracked means nothing to preview. Placeholder-only custom
        -- lanes exist purely as edit-mode drag surfaces.
        if laneShown and spec.customIndex and not entries and not chrome then laneShown = false end
        if not (laneShown and cfg.max > 0 and (not metrics or metrics.enabled ~= false)) then
            group._msufA3RefreshSignature = nil
            group:Hide()
        else
            -- Existing lanes use the compiler-finalized Runtime contract.
            -- ReadTextConfig remains only for edit-only placeholders that do
            -- not have a compiled lane yet.
            local textCfg = (metrics and metrics.textConfig) or ReadTextConfig(unit, kind)
            local shownIcons
            if entries then
                -- Custom lanes preview the tracked spells 1:1: one icon per
                -- configured spell, capped by the lane's own max.
                shownIcons = math_min((metrics and metrics.num) or cfg.max, #entries)
            else
                shownIcons = math_min(PREVIEW_ICONS, (metrics and metrics.num) or cfg.max)
            end
            if shownIcons < 1 then shownIcons = 1 end
            local size = (metrics and metrics.size) or cfg.size
            local step = (metrics and metrics.step) or (cfg.size + cfg.spacing)
            local perRow = (metrics and metrics.perRow) or cfg.perRow
            local fallback
            if not metrics then fallback = FallbackMetrics(cfg) end
            local laneW = (metrics and metrics.width) or (fallback and fallback.width) or cfg.size
            local laneH = (metrics and metrics.height) or (fallback and fallback.height) or cfg.size
            local growthX = (metrics and metrics.growthX) or (fallback and fallback.growthX) or 1
            local growthY = (metrics and metrics.growthY) or (fallback and fallback.growthY) or -1
            local vertical = metrics and metrics.verticalGrowth == true or (fallback and fallback.verticalGrowth == true)
            local initialAnchor = (metrics and metrics.initialAnchor) or (fallback and fallback.initialAnchor) or "TOPLEFT"
            local x = (metrics and metrics.x) or cfg.x
            local y = (metrics and metrics.y) or cfg.y
            local anchor = (metrics and metrics.anchor) or cfg.anchor
            -- Shared icon style + lane padding, 1:1 with the runtime lane. A
            -- bar-only lane renders no icon chrome, so the style stays off.
            local padding = Clamp(metrics and metrics.padding, 0, 0, 16)
            local barOnly = textCfg.showDurationBar == true and textCfg.durationBarDisplay == "BAR_ONLY"
            local appearanceKind = spec.customIndex == 4 and unit == "player" and "playerDefensives"
                or spec.customIndex == 4 and "targetDots"
                or ((kind == "debuff" or cfg.auraType == "DEBUFF") and "debuff" or "buff")
            local iconStyle = (not barOnly) and LaneIconStyle(metrics, unit, appearanceKind) or nil
            local requestedIconShape = (metrics and metrics.requestedIconShape) or cfg.iconShape
            local iconShape = (metrics and metrics.iconShape) or cfg.iconShape or "RECTANGLE"
            if type(A3.ResolveAuraIconShape) == "function" then
                iconShape = A3.ResolveAuraIconShape(requestedIconShape,
                    frame and frame.MSUFSpec and frame.MSUFSpec.portrait and frame.MSUFSpec.portrait.shape)
            end
            textCfg.iconShape = iconShape
            local signature = RefreshSignature(unit, kind, cfg, metrics, textCfg, shownIcons, size, step, perRow, laneW, laneH, growthX, growthY, vertical, initialAnchor, x, y, anchor, frameSig)
                .. "\030" .. CustomPreviewEntriesSignature(entries) .. "\030" .. tostring(chrome)
                .. "\030" .. tostring(padding) .. "\030" .. tostring(iconStyle and iconStyle.signature)

            if group._msufA3RefreshSignature ~= signature or not (group.IsShown and group:IsShown()) then
                group._msufA3RefreshSignature = signature
                if group.SetClampedToScreen then group:SetClampedToScreen(false) end
                ApplyGroupScaleForFrame(group, frame)
                PositionPreviewGroup(group, frame, anchor, x, y, laneW, laneH)
                group:SetSize(laneW, laneH + HEADER_H)
                if group.Body then group.Body:SetSize(laneW, laneH) end
                if group.Body then group.Body:SetAlpha(Clamp(metrics and metrics.alpha or cfg.alpha, 1, 0, 1)) end
                local layers = MSUF.UF and MSUF.UF.Layers
                local layer = (metrics and metrics.layer) or cfg.layer
                group:SetFrameLevel(layers and layers.ElementLevel and layers.ElementLevel(layer, 5, 0)
                    or (900 + Clamp(layer, 5, 0, 30)))
                if group.Hitbox and group.Hitbox.SetFrameLevel then
                    group.Hitbox:SetFrameLevel((group:GetFrameLevel() or 0) + 20)
                end
                if group.Label then
                    group.Label:SetText(UnitLabel(unit) .. " " .. GroupLabel(unit, kind, spec))
                    StyleLabel(group.Label)
                end
                ApplyGroupChrome(group, spec, chrome)

                local padX, padY = PaddingInset(initialAnchor, padding)
                for i = 1, shownIcons do
                    local icon = EnsureIcon(group, i)
                    icon:SetSize(size, size)
                    icon:ClearAllPoints()
                    local col, row = IconGridCoord(i, perRow, vertical)
                    local body = group.Body or group
                    icon:SetPoint(initialAnchor, body, initialAnchor, col * step * growthX + padX, row * step * growthY + padY)
                    if icon.Icon then
                        local entry = entries and entries[i]
                        icon.Icon:SetTexture((entry and entry.icon) or cfg.texture or spec.texture)
                        ApplyIconZoom(icon.Icon, metrics and metrics.iconZoom or cfg.iconZoom)
                    end
                    if type(A3.ApplyAuraIconShape) == "function" then
                        A3.ApplyAuraIconShape(icon, iconShape, nil, icon.Icon, icon.Shade, icon.Swipe)
                    end
                    if icon.Count then icon.Count:SetText(i == 1 and "3" or "") end
                    if icon.CooldownText then icon.CooldownText:SetText(i == 1 and "1m" or "32") end
                    ApplyPreviewIconText(icon, unit, textCfg, i)
                    if type(A3.ApplyIconStylePreview) == "function" then
                        A3.ApplyIconStylePreview(icon, iconStyle, size, iconShape)
                    end
                    icon:Show()
                end

                local icons = group._icons
                if icons then
                    for i = shownIcons + 1, #icons do
                        if icons[i] then icons[i]:Hide() end
                    end
                end
            end

            -- Cache the already-resolved lane state so Menu2's existing
            -- animation tick can advance only these visible regions.  It must
            -- not rerun DB reads, metrics, anchoring, or a full RefreshUnit at
            -- 20 Hz merely to keep Edit Mode in phase with the menu preview.
            group._msufA3AnimationKind = kind
            group._msufA3AnimationShownIcons = shownIcons
            group._msufA3AnimationTextConfig = textCfg
            ApplyPreviewAuraAnimation(group, kind, shownIcons, textCfg)
            if spec.customIndex then ApplyEditModeCustomEffect(group, frame, CustomItem(unit, spec.customIndex, false)) end
            group:Show()
            if group.Raise then group:Raise() end
        end
    end
end

function EM.RefreshAll()
    for i = 1, #AURA_UNITS do
        EM.RefreshUnit(AURA_UNITS[i])
    end
end

function EM.HideAll()
    if not EM.groups then return end
    for unit in pairs(EM.groups) do
        EM.HideUnit(unit)
    end
end

local editRefreshSerial = 0
local function CancelQueuedEditRefresh()
    editRefreshSerial = editRefreshSerial + 1
end

local function RequestEditModeAurasRefresh(delay)
    CancelQueuedEditRefresh()
    if IsConfigBlocked() then return end
    if not UnitPreviewActive() then
        EM.HideAll()
        return
    end
    local serial = editRefreshSerial
    if C_Timer and C_Timer.After then
        C_Timer.After(delay or 0, function()
            if serial ~= editRefreshSerial then return end
            if not UnitPreviewActive() then
                EM.HideAll()
                return
            end
            EM.RefreshAll()
        end)
    else
        EM.RefreshAll()
    end
end

local CoreRefreshAll = A3.RefreshAll
function A3.RefreshAll(...)
    local ret
    if type(CoreRefreshAll) == "function" then ret = CoreRefreshAll(...) end
    if IsConfigBlocked() then return ret end
    RequestEditModeAurasRefresh(0)
    return ret
end

local CoreDisableFrame = A3.DisableFrame
if type(CoreDisableFrame) == "function" then
    function A3.DisableFrame(frame, ...)
        local unit = frame and (frame.MSUFUnitKey or frame.unit)
        if unit then EM.HideUnit(unit) end
        if type(CoreDisableFrame) == "function" then return CoreDisableFrame(frame, ...) end
    end
end

local CoreRefreshUnit = A3.RefreshUnit
function A3.RefreshUnit(unit)
    if IsConfigBlocked() then
        if type(CoreRefreshUnit) == "function" then return CoreRefreshUnit(unit) end
        return false
    end
    if not unit then return end
    if IsEditModeActive() then
        if IsBossScope(unit) then
            ForEachBossUnit(function(bossUnit)
                PromoteRuntimeLayout(bossUnit, rawget(_G, "MSUF_EM2_ActiveAuraGroup"))
            end)
        else
            PromoteRuntimeLayout(unit, rawget(_G, "MSUF_EM2_ActiveAuraGroup"))
        end
    end
    local frame = GetFrame(unit)
    if frame and frame.Auras then frame.Auras.needFullUpdate = true end
    local ret = CoreRefreshUnit(unit)
    EM.RefreshUnit(unit)
    return ret
end

function A3.UpdateUnitAnchor(unit)
    if not unit then return end
    if IsConfigBlocked() then
        if type(A3._QueueDeferredAuraRuntime) == "function" then
            return A3._QueueDeferredAuraRuntime(unit, "AURAS3_UPDATE_ANCHOR")
        end
        return false
    end
    if IsBossScope(unit) then
        if IsEditModeActive() then
            ForEachBossUnit(function(bossUnit)
                PromoteRuntimeLayout(bossUnit, rawget(_G, "MSUF_EM2_ActiveAuraGroup"))
            end)
        end
        EM.RefreshUnit("boss")
        return
    end
    if IsEditModeActive() then
        PromoteRuntimeLayout(unit, rawget(_G, "MSUF_EM2_ActiveAuraGroup"))
    end
    EM.RefreshUnit(unit)
end

function A3.RefreshEditPreview(unit)
    if IsConfigBlocked() then return false end
    if not UnitPreviewActive(unit) then
        if unit then return EM.HideUnit(unit) end
        return EM.HideAll()
    end
    if unit then return EM.RefreshUnit(unit) end
    return EM.RefreshAll()
end

--- Advances only already-built Edit Mode aura dummy regions from Menu2's
--- existing preview clock.  This creates no driver of its own and is rejected
--- during combat; layout/config work remains on the normal cold refresh path.
function A3.RefreshEditPreviewAnimation(unit, elapsed)
    if IsConfigBlocked() or not EditPreviewActive() then return false end
    elapsed = tonumber(elapsed)
    if elapsed == nil then return false end
    if IsBossScope(unit) then
        local any = false
        ForEachBossUnit(function(bossUnit)
            any = A3.RefreshEditPreviewAnimation(bossUnit, elapsed) or any
        end)
        return any
    end
    local byUnit = unit and EM.groups and EM.groups[unit]
    if not byUnit then return false end
    local any = false
    for kind, group in pairs(byUnit) do
        if group and group.IsShown and group:IsShown() then
            local textCfg = group._msufA3AnimationTextConfig
            local shownIcons = tonumber(group._msufA3AnimationShownIcons) or 0
            if textCfg and shownIcons > 0 then
                ApplyPreviewAuraAnimation(group, group._msufA3AnimationKind or kind,
                    shownIcons, textCfg, elapsed)
                any = true
            end
        end
    end
    return any
end

local function OpenAuras3PositionPopup(unit, parent)
    if parent and parent._msufA3MoverKind then
        ExportPublic("MSUF_EM2_ActiveAuraGroup", parent._msufA3MoverKind)
        ExportPublic("MSUF_EM2_ActiveAuraUnit", unit)
    end
    local EM2 = _G.MSUF_EM2
    if EM2 and EM2.Popups then
        return EM2.Popups.Open("aura_" .. tostring(unit or ""), parent)
    elseif EM2 and EM2.AuraPopup then
        return EM2.AuraPopup.Open(unit, parent)
    end
end
ExportPublic("MSUF_OpenAuras3PositionPopup", OpenAuras3PositionPopup)

local function OnEditModeChanged(active)
    if active then
        RequestEditModeAurasRefresh(0.12)
    else
        CancelQueuedEditRefresh()
        EM.HideAll()
        ExportPublic("MSUF_EM2_ActiveAuraGroup", nil)
        ExportPublic("MSUF_EM2_ActiveAuraUnit", nil)
        -- Leaving edit mode must not strip the boss page's aura preview lanes.
        if BossPageAuraPreviewActive() then RequestEditModeAurasRefresh(0) end
    end
end

local function RegisterEditListener()
    if EM._registered then return end
    local reg = _G.MSUF_RegisterAnyEditModeListener
    if type(reg) == "function" then
        reg(OnEditModeChanged)
        EM._registered = true
        if IsEditModeActive() then OnEditModeChanged(true) end
    end
end

RegisterEditListener()
if not EM._registered then
    C_Timer.After(0, RegisterEditListener)
end
