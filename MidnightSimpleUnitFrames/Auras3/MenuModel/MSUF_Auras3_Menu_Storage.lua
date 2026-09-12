-- Profile storage and inheritance own every generic menu read/write here.
-- Canonical profiles stay sparse; legacy defaults are seeded once per concrete
-- table. Apply invalidates that weak-key cache, while replaced tables miss it.
-- Layout inheritance and its migration are local to this owner, with no late
-- binding to renderer functions. Other modules receive only the scope helpers.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
local Factories = MSUF.Auras3MenuModelFactories
if not Factories then
    Factories = {}
    MSUF.Auras3MenuModelFactories = Factories
end

function Factories.Storage(A3, Model, Schema, Common, ExportPublic)
    local type = type
    local tonumber = tonumber
    local pairs = pairs
    local next = next
    local math_floor = math.floor
    local DEFAULT_GENERAL = Schema.DEFAULT_GENERAL
    local DEFAULT_SHARED = Schema.DEFAULT_SHARED
    local LAYOUT_KEYS = Schema.LAYOUT_KEYS
    local SCOPE_MATERIALIZED_LAYOUT_KEYS = Schema.SCOPE_MATERIALIZED_LAYOUT_KEYS
    local SHARED_LAYOUT_KEYS = Schema.SHARED_LAYOUT_KEYS
    local STYLE_LAYOUT_KEYS = Schema.STYLE_LAYOUT_KEYS
    local STYLE_SHARED_LAYOUT_KEYS = Schema.STYLE_SHARED_LAYOUT_KEYS
    local UNIT_FLAG = Schema.UNIT_FLAG
    local Clamp01 = Common.Clamp01
    local ClampNumber = Common.ClampNumber
    local DeepCopy = Common.DeepCopy
    local Default = Common.Default
    local DefaultsInto = Common.DefaultsInto
    local EachRuntimeUnit = Common.EachRuntimeUnit
    local NormalizeDebuffTypeBorderMode = Common.NormalizeDebuffTypeBorderMode
    local NormalizeScope = Common.NormalizeScope
    local NormalizeUnit = Common.NormalizeUnit
    local ReadRGB = Common.ReadRGB
    local Round = Common.Round
    local RuntimeUnit = Common.RuntimeUnit

    -- Menu reads can call EnsureDB hundreds of times while constructing one page.
    -- Seed each concrete profile table once, then invalidate at the next apply
    -- boundary. Replaced profile/subtables naturally miss this weak-key cache.
    local defaultsSeedCache = setmetatable({}, { __mode = "k" })
    local function MarkDefaultsSeeded(tbl, defaults)
        if type(tbl) ~= "table" or type(defaults) ~= "table" then return end
        local seeded = { defaults = defaults, childKeys = {}, childTables = {} }
        defaultsSeedCache[tbl] = seeded
        for key, value in pairs(defaults) do
            if type(value) == "table" and type(tbl[key]) == "table" then
                local childIndex = #seeded.childKeys + 1
                seeded.childKeys[childIndex] = key
                seeded.childTables[childIndex] = tbl[key]
                MarkDefaultsSeeded(tbl[key], value)
            end
        end
    end
    local function DefaultsIntoOnce(tbl, defaults)
        if type(tbl) ~= "table" or type(defaults) ~= "table" then return end
        local seeded = defaultsSeedCache[tbl]
        if seeded and seeded.defaults == defaults then
            local childrenMatch = true
            for i = 1, #seeded.childKeys do
                if tbl[seeded.childKeys[i]] ~= seeded.childTables[i] then
                    childrenMatch = false
                    break
                end
            end
            if childrenMatch then return end
        end
        DefaultsInto(tbl, defaults)
        MarkDefaultsSeeded(tbl, defaults)
    end
    function Model.InvalidateDefaultSeedCache()
        defaultsSeedCache = setmetatable({}, { __mode = "k" })
    end

    local function PerUnit(auras, unit, create)
        if type(auras) ~= "table" then return nil end
        unit = RuntimeUnit(unit)
        if create and type(auras.perUnit) ~= "table" then auras.perUnit = {} end
        local pu = auras.perUnit and auras.perUnit[unit]
        if create and type(pu) ~= "table" then
            pu = {}
            auras.perUnit[unit] = pu
        end
        return pu
    end

    --- Layout values can come from shared defaults, per-unit layout overrides, or
    --- per-unit shared-layout overrides. Keep that fallback order centralized here
    --- so pages, assistant commands, and edit-mode popups do not diverge.
    local function EffectiveLayoutTables(auras, unit)
        local pu = PerUnit(auras, unit, false)
        local layout = (pu and type(pu.layout) == "table") and pu.layout or nil
        local sharedLayout = (pu and type(pu.layoutShared) == "table") and pu.layoutShared or nil
        return layout, sharedLayout, pu
    end

    local function TableHasAny(tbl)
        if type(tbl) ~= "table" then return false end
        return next(tbl) ~= nil
    end

    local TableHasAnyKey = _G.MSUF_AuraTableHasAnyKey

    local function ClearKeys(tbl, keys)
        if type(tbl) ~= "table" or type(keys) ~= "table" then return end
        for key in pairs(keys) do tbl[key] = nil end
    end

    local function UnitHasStyleOverride(pu)
        return type(pu) == "table"
            and (TableHasAnyKey(pu.layout, STYLE_LAYOUT_KEYS) or TableHasAnyKey(pu.layoutShared, STYLE_SHARED_LAYOUT_KEYS))
    end

    local function UnitStyleOverrideActive(pu)
        if type(pu) ~= "table" then return false end
        if pu.overrideStyle ~= nil then return pu.overrideStyle == true end
        return UnitHasStyleOverride(pu)
    end

    local function RefreshLayoutOverrideFlags(pu)
        if type(pu) ~= "table" then return end
        pu.overrideLayout = TableHasAny(pu.layout) and true or false
        pu.overrideSharedLayout = TableHasAny(pu.layoutShared) and true or false
    end

    local function LooksLikeLegacySeededVisualLayout(layout)
        if type(layout) ~= "table" then return false end
        if layout.iconSize == nil or layout.buffGroupIconSize == nil or layout.debuffGroupIconSize == nil then return false end
        local hits = 0
        for key in pairs(LAYOUT_KEYS) do
            if layout[key] ~= nil then hits = hits + 1 end
        end
        return hits >= 10
    end

    local function ClearInheritedLayoutKey(layout, shared, key)
        if type(layout) ~= "table" or type(shared) ~= "table" then return end
        if layout[key] ~= nil and layout[key] == shared[key] then layout[key] = nil end
    end

    local function ClearInheritedBasicLayoutKeys(layout, shared, keys, styleKeys)
        if type(keys) ~= "table" then return end
        for key in pairs(keys) do
            if not SCOPE_MATERIALIZED_LAYOUT_KEYS[key] and not (styleKeys and styleKeys[key]) then
                ClearInheritedLayoutKey(layout, shared, key)
            end
        end
    end

    local function NormalizeSparseVisualOverrides(auras, shared)
        local perUnit = type(auras) == "table" and auras.perUnit or nil
        if type(perUnit) ~= "table" then return end
        for _, pu in pairs(perUnit) do
            if type(pu) == "table" and pu._msufA3SparseVisualOverrides_v2 ~= true then
                if pu.overrideStyle == nil and UnitHasStyleOverride(pu) then pu.overrideStyle = true end
                if pu.overrideLayout == true and pu.overrideSharedLayout == true and LooksLikeLegacySeededVisualLayout(pu.layout) then
                    ClearInheritedBasicLayoutKeys(pu.layout, shared, LAYOUT_KEYS, STYLE_LAYOUT_KEYS)
                    ClearInheritedBasicLayoutKeys(pu.layoutShared, shared, SHARED_LAYOUT_KEYS, STYLE_SHARED_LAYOUT_KEYS)
                    RefreshLayoutOverrideFlags(pu)
                end
                pu._msufA3SparseVisualOverrides_v2 = true
            end
        end
    end

    --- Ensure the Auras3 DB shape for menu operations. This is coldpath and may
    --- seed defaults; live native aura rendering consumes compiled config from the
    --- UnitFrames backend after Model.Apply invalidates it.
    function Model.EnsureDB()
        local auras, shared
        if A3.EnsureDB then
            auras, shared = A3.EnsureDB()
        else
            local db = _G.MSUF_DB
            if type(db) ~= "table" then db = {}; ExportPublic("MSUF_DB", db) end
            if type(db.auras3) ~= "table" then db.auras3 = {} end
            auras = db.auras3
            shared = auras.shared
        end

        if type(auras) ~= "table" then return nil, nil end
        if auras.enabled == nil then auras.enabled = true end
        Default(auras, "showPlayer", false)
        Default(auras, "showTarget", true)
        Default(auras, "showFocus", false)
        Default(auras, "showBoss", true)
        if type(auras.perUnit) ~= "table" then auras.perUnit = {} end
        if type(shared) ~= "table" then shared = {}; auras.shared = shared end
        if type(auras.customDisplays) ~= "table" then auras.customDisplays = {} end
        if type(auras.customDisplays.shared) ~= "table" then auras.customDisplays.shared = { items = {} } end
        if type(auras.customDisplays.shared.items) ~= "table" then auras.customDisplays.shared.items = {} end
        if type(auras.customDisplays.perUnit) ~= "table" then auras.customDisplays.perUnit = {} end
        if type(auras.customDisplays.serial) ~= "number" then auras.customDisplays.serial = 0 end
        if type(auras.customContainers) ~= "table" then auras.customContainers = {} end
        if type(auras.customContainers.perUnit) ~= "table" then auras.customContainers.perUnit = {} end
        -- An existing `specialStyles` table is legacy upgrade input only.  Do not
        -- seed it for new profiles: current Player Defensive and Target-DoT Style
        -- lives on the owning UnitFrame like every other Custom Aura container.
        -- Appearance is now unconditional per Aura product; remove the former
        -- frame participation and shape-follow switches from upgraded profiles.
        shared.styleScopeDisabled = nil
        shared.iconShapeFollowSharedScopes = nil
        local canonicalAuraModel = tonumber(auras.profileModelRevision) == 2
        if canonicalAuraModel then
            -- The Defaults-owned factory is deliberately sparse and authoritative.
            -- Runtime/Menu readers already provide fallbacks, so do not densify a
            -- freshly reset tree with compatibility aliases merely by opening UI.
            if type(shared.filters) ~= "table" then
                shared.filters = DeepCopy(DEFAULT_SHARED.filters)
            end
        else
            DefaultsIntoOnce(shared, DEFAULT_SHARED)
        end
        -- The canonical profile model is already normalized.  Never seed legacy
        -- migration markers back into a freshly hard-reset Aura tree.
        if tonumber(auras.profileModelRevision) ~= 2
            and shared._msufA3_debuffTypeBorderModeMigrated_v1 ~= true then
            shared.debuffTypeBorderMode = shared.useDebuffTypeBorders == true and "SYMBOL" or NormalizeDebuffTypeBorderMode(shared.debuffTypeBorderMode, "OFF")
            shared._msufA3_debuffTypeBorderModeMigrated_v1 = true
        end
        if not canonicalAuraModel then
            NormalizeSparseVisualOverrides(auras, shared)
        end
        return auras, shared
    end

    local function EnsureGeneralDB()
        local db = _G.MSUF_DB
        if type(db) ~= "table" then db = {}; ExportPublic("MSUF_DB", db) end
        if type(db.general) ~= "table" then db.general = {} end
        DefaultsIntoOnce(db.general, DEFAULT_GENERAL)
        return db.general
    end

    function Model.ReadGeneralBool(key, defaultValue)
        local g = EnsureGeneralDB()
        if g[key] == nil then return defaultValue and true or false end
        return g[key] == true
    end

    function Model.WriteGeneralBool(key, value)
        local g = EnsureGeneralDB()
        g[key] = value and true or false
    end

    function Model.ReadGeneralNumber(key, defaultValue, minValue, maxValue)
        local g = EnsureGeneralDB()
        return ClampNumber(g[key], defaultValue, minValue, maxValue)
    end

    function Model.WriteGeneralNumber(key, value, minValue, maxValue)
        local g = EnsureGeneralDB()
        value = ClampNumber(value, 0, minValue, maxValue)
        if math_floor(value) == value then value = Round(value) end
        g[key] = value
    end

    function Model.ReadGeneralColor(key, defaultR, defaultG, defaultB)
        return ReadRGB(EnsureGeneralDB(), key, defaultR, defaultG, defaultB)
    end

    function Model.WriteGeneralColor(key, r, g, b)
        local general = EnsureGeneralDB()
        general[key] = { Clamp01(r, 1), Clamp01(g, 1), Clamp01(b, 1) }
    end

    -- One cold-path source of truth for the aura duration bar and every preview.
    -- The Safe timer color is also the live duration-bar color; when it has not
    -- been customized, it inherits the configured global font color just like the
    -- cooldown formatter.
    function Model.GetDurationBarColor()
        local db = _G.MSUF_DB
        local general = type(db) == "table" and db.general or nil
        local color = general and general.aurasCooldownTextSafeColor
        local r, g, b
        if type(color) == "table" then
            r, g, b = color[1] or color.r, color[2] or color.g, color[3] or color.b
        elseif type(_G.MSUF_GetConfiguredFontColor) == "function" then
            r, g, b = _G.MSUF_GetConfiguredFontColor()
        end
        return Clamp01(r, 1), Clamp01(g, 1), Clamp01(b, 1)
    end
    A3.GetDurationBarColor = Model.GetDurationBarColor

    local function ReadKeyFromTables(layout, sharedLayout, key)
        if LAYOUT_KEYS[key] then
            if layout and layout[key] ~= nil then return layout[key] end
        end
        if SHARED_LAYOUT_KEYS[key] then
            if sharedLayout and sharedLayout[key] ~= nil then return sharedLayout[key] end
        end
        return nil
    end

    -- A preview reads many fields synchronously. Resolve its profile and scope
    -- once after runtime compilation, which may have materialized profile data.
    -- This context is local to that read; profile replacement or nested reads
    -- cannot reuse it accidentally. It never becomes a saved/runtime cache.
    local function CreatePreviewReadContext(unit)
        local auras, shared = Model.EnsureDB()
        local layout, sharedLayout = EffectiveLayoutTables(auras, unit)
        local flag = UNIT_FLAG[unit]
        return {
            shared = shared, layout = layout, sharedLayout = sharedLayout,
            enabled = type(auras) == "table" and auras.enabled == true and flag and auras[flag] == true,
        }
    end

    local function WriteUnitLayoutValue(auras, shared, unit, key, value)
        EachRuntimeUnit(unit, function(runtimeUnit)
            local pu = PerUnit(auras, runtimeUnit, true)
            if not pu then return end

            if SHARED_LAYOUT_KEYS[key] then
                if type(pu.layoutShared) ~= "table" then pu.layoutShared = {} end
                pu.overrideSharedLayout = true
                pu.layoutShared[key] = value
                if STYLE_SHARED_LAYOUT_KEYS[key] then pu.overrideStyle = true end
            else
                if type(pu.layout) ~= "table" then pu.layout = {} end
                pu.overrideLayout = true
                pu.layout[key] = value
                if STYLE_LAYOUT_KEYS[key] then pu.overrideStyle = true end
            end
        end)
    end

    function Model.UnitSupported(unit)
        unit = NormalizeUnit(unit)
        return unit == "player" or unit == "target" or unit == "focus" or unit == "boss"
            or unit == "arena"
    end

    function Model.UnitEnabled(unit)
        local auras = Model.EnsureDB()
        local flag = UNIT_FLAG[NormalizeUnit(unit)]
        return type(auras) == "table" and auras.enabled == true and flag and auras[flag] == true
    end

    function Model.SetUnitEnabled(unit, enabled)
        local auras = Model.EnsureDB()
        if type(auras) ~= "table" then return end
        local flag = UNIT_FLAG[NormalizeUnit(unit)]
        if enabled then auras.enabled = true end
        if flag then auras[flag] = enabled and true or false end
    end

    function Model.UseSharedVisuals(unit)
        return false
    end

    local function EnsureUnitStyleOverrides(auras, runtimeUnit)
        local pu = PerUnit(auras, runtimeUnit, true)
        if not pu then return end
        pu.layout = type(pu.layout) == "table" and pu.layout or {}
        pu.layoutShared = type(pu.layoutShared) == "table" and pu.layoutShared or {}
        if pu.overrideStyle ~= true then
            ClearKeys(pu.layout, STYLE_LAYOUT_KEYS)
            ClearKeys(pu.layoutShared, STYLE_SHARED_LAYOUT_KEYS)
        end
        pu.overrideStyle = true
    end

    function Model.SetUseSharedVisuals(unit, useShared)
        local auras = Model.EnsureDB()
        if type(auras) ~= "table" then return end
        EachRuntimeUnit(unit, function(runtimeUnit)
            EnsureUnitStyleOverrides(auras, runtimeUnit)
        end)
    end

    function Model.ReadValue(unit, key, defaultValue)
        local auras, shared = Model.EnsureDB()
        if type(shared) ~= "table" then return defaultValue end
        if NormalizeScope(unit) == "shared" then
            if shared[key] ~= nil then return shared[key] end
            return defaultValue
        end
        local layout, sharedLayout = EffectiveLayoutTables(auras, unit)
        local value = ReadKeyFromTables(layout, sharedLayout, key)
        if value ~= nil then return value end
        return defaultValue
    end

    function Model.ReadNumber(unit, key, defaultValue, minValue, maxValue)
        return ClampNumber(Model.ReadValue(unit, key, defaultValue), defaultValue, minValue, maxValue)
    end

    function Model.WriteValue(unit, key, value)
        local auras, shared = Model.EnsureDB()
        if type(shared) ~= "table" then return end
        if NormalizeScope(unit) == "shared" then
            shared[key] = value
        elseif LAYOUT_KEYS[key] or SHARED_LAYOUT_KEYS[key] then
            WriteUnitLayoutValue(auras, shared, unit, key, value)
        end
    end

    function Model.WriteNumber(unit, key, value, minValue, maxValue)
        value = ClampNumber(value, 0, minValue, maxValue)
        if math_floor(value) == value then value = Round(value) end
        Model.WriteValue(unit, key, value)
    end

    function Model.ReadBool(unit, key, defaultValue)
        local value = Model.ReadValue(unit, key, defaultValue and true or false)
        if value == nil then return defaultValue and true or false end
        return value == true
    end

    function Model.WriteBool(unit, key, value)
        Model.WriteValue(unit, key, value and true or false)
    end

    function Model.ReadSharedBool(key, defaultValue)
        local _, shared = Model.EnsureDB()
        if type(shared) ~= "table" or shared[key] == nil then return defaultValue and true or false end
        return shared[key] == true
    end

    function Model.WriteSharedBool(key, value)
        local _, shared = Model.EnsureDB()
        if type(shared) == "table" then shared[key] = value and true or false end
    end

    function Model.ReadSharedNumber(key, defaultValue, minValue, maxValue)
        local _, shared = Model.EnsureDB()
        return ClampNumber(type(shared) == "table" and shared[key] or nil, defaultValue, minValue, maxValue)
    end

    function Model.WriteSharedNumber(key, value, minValue, maxValue)
        local _, shared = Model.EnsureDB()
        if type(shared) == "table" then shared[key] = ClampNumber(value, 0, minValue, maxValue) end
    end


    -- Private dependency API; public menu methods remain on A3.MenuModel.
    return {
        CreatePreviewReadContext = CreatePreviewReadContext,
        ClearKeys = ClearKeys,
        DefaultsIntoOnce = DefaultsIntoOnce,
        EffectiveLayoutTables = EffectiveLayoutTables,
        PerUnit = PerUnit,
        ReadKeyFromTables = ReadKeyFromTables,
        RefreshLayoutOverrideFlags = RefreshLayoutOverrideFlags,
        UnitStyleOverrideActive = UnitStyleOverrideActive,
    }
end
