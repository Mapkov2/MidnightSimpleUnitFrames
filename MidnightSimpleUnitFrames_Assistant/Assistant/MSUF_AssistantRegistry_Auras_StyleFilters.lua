-- Assistant Auras style/filter registry shard.
-- Loaded before MSUF_AssistantRegistry_Auras.lua; the main domain passes DB and registry helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.AurasRegistry = A.AurasRegistry or {}

function A.AurasRegistry.RegisterStyleAndFilterSettings(ctx)
    if type(ctx) ~= "table" then return end

    local Registry = ctx.Registry
    local AURA_SCOPES = ctx.AURA_SCOPES or {}
    local AURA_LANES = ctx.AURA_LANES or {}
    local AURA_ANCHOR_VALUES = ctx.AURA_ANCHOR_VALUES or {}
    local AURA_ANCHOR_ALIASES = ctx.AURA_ANCHOR_ALIASES or {}
    local AURA_STACK_ANCHOR_VALUES = ctx.AURA_STACK_ANCHOR_VALUES or {}
    local AURA_STACK_ANCHOR_ALIASES = ctx.AURA_STACK_ANCHOR_ALIASES or {}
    local AURA_COOLDOWN_SWIPE_DIRECTION_VALUES = ctx.AURA_COOLDOWN_SWIPE_DIRECTION_VALUES or {}
    local AURA_COOLDOWN_SWIPE_DIRECTION_ALIASES = ctx.AURA_COOLDOWN_SWIPE_DIRECTION_ALIASES or {}
    local AURA_FRAME_EFFECT_TYPE_VALUES = ctx.AURA_FRAME_EFFECT_TYPE_VALUES or {}
    local AURA_FRAME_EFFECT_TYPE_ALIASES = ctx.AURA_FRAME_EFFECT_TYPE_ALIASES or {}
    local AURA_SORT_METHOD_VALUES = ctx.AURA_SORT_METHOD_VALUES or {}
    local AURA_SORT_METHOD_ALIASES = ctx.AURA_SORT_METHOD_ALIASES or {}
    local AURA_SORT_DIRECTION_VALUES = ctx.AURA_SORT_DIRECTION_VALUES or {}
    local AURA_SORT_DIRECTION_ALIASES = ctx.AURA_SORT_DIRECTION_ALIASES or {}
    local AURA_DURATION_BAR_POSITION_VALUES = ctx.AURA_DURATION_BAR_POSITION_VALUES or {}
    local AURA_DURATION_BAR_POSITION_ALIASES = ctx.AURA_DURATION_BAR_POSITION_ALIASES or {}
    local AURA_DURATION_BAR_DISPLAY_VALUES = ctx.AURA_DURATION_BAR_DISPLAY_VALUES or {}
    local AURA_DURATION_BAR_DISPLAY_ALIASES = ctx.AURA_DURATION_BAR_DISPLAY_ALIASES or {}
    local AURA_DURATION_BAR_DIRECTION_VALUES = ctx.AURA_DURATION_BAR_DIRECTION_VALUES or {}
    local AURA_DURATION_BAR_DIRECTION_ALIASES = ctx.AURA_DURATION_BAR_DIRECTION_ALIASES or {}
    local AURA_LANE_STYLE_BOOLEAN_SPECS = ctx.AURA_LANE_STYLE_BOOLEAN_SPECS or {}
    local AURA_LANE_STYLE_NUMBER_SPECS = ctx.AURA_LANE_STYLE_NUMBER_SPECS or {}
    local AURA_DEBUFF_TYPE_BORDER_VALUES = ctx.AURA_DEBUFF_TYPE_BORDER_VALUES or {}
    local AURA_DEBUFF_TYPE_BORDER_ALIASES = ctx.AURA_DEBUFF_TYPE_BORDER_ALIASES or {}
    local AURA_STEALABLE_STYLE_VALUES = ctx.AURA_STEALABLE_STYLE_VALUES or {}
    local AURA_STEALABLE_STYLE_ALIASES = ctx.AURA_STEALABLE_STYLE_ALIASES or {}
    local AddAliasesForAuraScope = ctx.AddAliasesForAuraScope
    local AddAuraLaneAliases = ctx.AddAuraLaneAliases
    local AuraScopeLabel = ctx.AuraScopeLabel
    local RegisterAuraScopeLaneBoolean = ctx.RegisterAuraScopeLaneBoolean
    local RegisterAuraScopeLaneNumber = ctx.RegisterAuraScopeLaneNumber
    local RegisterAuraScopeLaneEnum = ctx.RegisterAuraScopeLaneEnum
    local AuraReadLaneStyleBool = ctx.AuraReadLaneStyleBool
    local AuraWriteLaneStyleBool = ctx.AuraWriteLaneStyleBool
    local AuraReadLaneStyleNumber = ctx.AuraReadLaneStyleNumber
    local AuraWriteLaneStyleNumber = ctx.AuraWriteLaneStyleNumber
    local AuraReadLaneStackAnchor = ctx.AuraReadLaneStackAnchor
    local AuraWriteLaneStackAnchor = ctx.AuraWriteLaneStackAnchor
    local AuraReadLaneCooldownAnchor = ctx.AuraReadLaneCooldownAnchor
    local AuraWriteLaneCooldownAnchor = ctx.AuraWriteLaneCooldownAnchor
    local AuraModel = ctx.AuraModel
    local EnsureAuraFallbackDB = ctx.EnsureAuraFallbackDB
    local ApplyAura = ctx.ApplyAura

    if not (Registry and type(Registry.RegisterSetting) == "function") then return end
    if type(AddAliasesForAuraScope) ~= "function" or type(AddAuraLaneAliases) ~= "function" then return end
    if type(AuraScopeLabel) ~= "function" then return end

    if #AURA_DEBUFF_TYPE_BORDER_VALUES == 0 then
        AURA_DEBUFF_TYPE_BORDER_VALUES = { "OFF", "BORDER", "SYMBOL" }
    end
    if #AURA_COOLDOWN_SWIPE_DIRECTION_VALUES == 0 then
        AURA_COOLDOWN_SWIPE_DIRECTION_VALUES = { "NORMAL", "REVERSE" }
    end
    if #AURA_FRAME_EFFECT_TYPE_VALUES == 0 then
        AURA_FRAME_EFFECT_TYPE_VALUES = { "none", "border", "glow", "pulse", "healthtint", "namecolor" }
    end
    if type(AURA_SORT_METHOD_VALUES.buff) ~= "table" or #AURA_SORT_METHOD_VALUES.buff == 0 then
        AURA_SORT_METHOD_VALUES.buff = { "DEFAULT", "BIG_DEFENSIVE", "IMPORTANT_FIRST", "EXPIRATION", "EXPIRATION_ONLY", "NAME", "NAME_ONLY" }
    end
    if type(AURA_SORT_METHOD_VALUES.debuff) ~= "table" or #AURA_SORT_METHOD_VALUES.debuff == 0 then
        AURA_SORT_METHOD_VALUES.debuff = { "DEFAULT", "UNIT_FRAME_DEBUFF", "IMPORTANT_FIRST", "EXPIRATION", "EXPIRATION_ONLY", "NAME", "NAME_ONLY" }
    end
    if #AURA_SORT_DIRECTION_VALUES == 0 then
        AURA_SORT_DIRECTION_VALUES = { "NORMAL", "REVERSE" }
    end
    if #AURA_DURATION_BAR_POSITION_VALUES == 0 then
        AURA_DURATION_BAR_POSITION_VALUES = { "BOTTOM", "TOP" }
    end
    if #AURA_DURATION_BAR_DISPLAY_VALUES == 0 then
        AURA_DURATION_BAR_DISPLAY_VALUES = { "BAR_ONLY", "OVERLAY" }
    end
    if #AURA_DURATION_BAR_DIRECTION_VALUES == 0 then
        AURA_DURATION_BAR_DIRECTION_VALUES = { "REMAINING", "ELAPSED" }
    end
    local debuffBorderAllowed = {}
    for i = 1, #AURA_DEBUFF_TYPE_BORDER_VALUES do debuffBorderAllowed[AURA_DEBUFF_TYPE_BORDER_VALUES[i]] = true end

    local durationBarPositionAllowed = {}
    for i = 1, #AURA_DURATION_BAR_POSITION_VALUES do durationBarPositionAllowed[AURA_DURATION_BAR_POSITION_VALUES[i]] = true end
    local durationBarDisplayAllowed = {}
    for i = 1, #AURA_DURATION_BAR_DISPLAY_VALUES do durationBarDisplayAllowed[AURA_DURATION_BAR_DISPLAY_VALUES[i]] = true end
    local durationBarDirectionAllowed = {}
    for i = 1, #AURA_DURATION_BAR_DIRECTION_VALUES do durationBarDirectionAllowed[AURA_DURATION_BAR_DIRECTION_VALUES[i]] = true end

    local function NormalizeDebuffTypeBorderMode(value)
        value = tostring(value or "OFF")
        return debuffBorderAllowed[value] and value or "OFF"
    end

    local function LaneStyleKey(lane, key)
        local prefix = lane == "buff" and "buff" or "debuff"
        return prefix .. key:sub(1, 1):upper() .. key:sub(2)
    end

    local sortMethodAllowed = { buff = {}, debuff = {} }
    for lane, values in pairs(AURA_SORT_METHOD_VALUES) do
        sortMethodAllowed[lane] = sortMethodAllowed[lane] or {}
        for i = 1, #(values or {}) do sortMethodAllowed[lane][values[i]] = true end
    end

    local function NormalizeAuraSortMethod(lane, value)
        value = tostring(value or "DEFAULT"):upper():gsub("[%s%-]+", "_")
        if value == "BIGDEFENSIVE" then value = "BIG_DEFENSIVE" end
        if value == "UNITFRAMEDEBUFF" then value = "UNIT_FRAME_DEBUFF" end
        if value == "IMPORTANTONLY" or value == "IMPORTANT" then value = "IMPORTANT_FIRST" end
        if value == "EXPIRATIONONLY" then value = "EXPIRATION_ONLY" end
        if value == "NAMEONLY" then value = "NAME_ONLY" end
        return sortMethodAllowed[lane] and sortMethodAllowed[lane][value] and value or "DEFAULT"
    end

    local function AuraFallbackLaneStyle(scope, lane, key, defaultValue, writeValue)
        -- The Assistant must never turn a missing Unit model into a write to
        -- another owner. Returning the declared default fails closed.
        return defaultValue
    end

    local function AuraReadLaneSortMethod(scope, lane)
        local Model = type(AuraModel) == "function" and AuraModel() or nil
        local value
        if Model and type(Model.ReadLaneStyleString) == "function" then
            value = Model.ReadLaneStyleString(scope, lane, "sortMethod", "DEFAULT")
        else
            value = AuraFallbackLaneStyle(scope, lane, "sortMethod", "DEFAULT")
        end
        return NormalizeAuraSortMethod(lane, value)
    end

    local function AuraWriteLaneSortMethod(scope, lane, value)
        value = NormalizeAuraSortMethod(lane, value)
        local Model = type(AuraModel) == "function" and AuraModel() or nil
        if Model and type(Model.WriteLaneStyleString) == "function" then
            Model.WriteLaneStyleString(scope, lane, "sortMethod", value)
        else
            AuraFallbackLaneStyle(scope, lane, "sortMethod", "DEFAULT", value)
        end
    end

    local frameEffectTypeAllowed = {}
    for i = 1, #AURA_FRAME_EFFECT_TYPE_VALUES do
        frameEffectTypeAllowed[AURA_FRAME_EFFECT_TYPE_VALUES[i]] = true
    end

    local function NormalizeLaneFrameEffectType(value)
        value = tostring(value or "none"):lower():gsub("[%s_%-]+", "")
        if value == "outline" then value = "border" end
        if value == "tint" or value == "healthbartint" then value = "healthtint" end
        if value == "nameoverlay" then value = "namecolor" end
        return frameEffectTypeAllowed[value] and value or "none"
    end

    local function AuraReadLaneFrameEffectType(scope, lane)
        local key = LaneStyleKey(lane, "frameEffectType")
        local Model = type(AuraModel) == "function" and AuraModel() or nil
        local value
        if Model and type(Model.ReadValue) == "function" then
            value = Model.ReadValue(scope, key, "none")
        else
            value = AuraFallbackLaneStyle(scope, lane, "frameEffectType", "none")
        end
        return NormalizeLaneFrameEffectType(value)
    end

    local function AuraWriteLaneFrameEffectType(scope, lane, value)
        value = NormalizeLaneFrameEffectType(value)
        local key = LaneStyleKey(lane, "frameEffectType")
        local Model = type(AuraModel) == "function" and AuraModel() or nil
        if Model and type(Model.WriteValue) == "function" then
            Model.WriteValue(scope, key, value)
        else
            AuraFallbackLaneStyle(scope, lane, "frameEffectType", "none", value)
        end
    end

    -- Marker wording only. The includeDispellable FILTER owns "stealable buffs"
    -- and "purgeable buffs" -- it chooses which buffs are listed at all, while
    -- these two decide how the listed ones are marked.
    local AURA_STEALABLE_MARKER_NOUNS = {
        "stealable marker", "stealable markers", "stealable highlight",
        "stealable indicator", "mark stealable buffs", "highlight stealable buffs",
        "spellsteal marker",
    }
    local AURA_STEALABLE_STYLE_NOUNS = {
        "stealable marker style", "stealable highlight style",
        "stealable indicator style", "stealable buff style", "spellsteal marker style",
    }

    -- Exact whole-phrase aliases, so these win their wording outright instead of
    -- competing on fuzzy score with the older dispellable/stealable filter.
    local function AuraStealableExactAliases(scope, nouns)
        local out, seen = {}, {}
        local function add(value)
            value = tostring(value or "")
            if value ~= "" and not seen[value] then seen[value] = true; out[#out + 1] = value end
        end
        local scopeWords = { scope }
        for i = 1, #nouns do
            local noun = nouns[i]
            for j = 1, #scopeWords do
                add(scopeWords[j] .. " " .. noun)
                add(scopeWords[j] .. " buff " .. noun)
            end
        end
        return out
    end

    local function NormalizeStealableStyle(value)
        value = tostring(value or ""):upper()
        if value == "BORDER" or value == "BORDER_ICON" or value == "ICON" then return value end
        return "BORDER_ICON"
    end

    local function AuraReadLaneStealableStyle(scope, lane)
        local Model = type(AuraModel) == "function" and AuraModel() or nil
        local value
        if Model and type(Model.ReadLaneStyleString) == "function" then
            value = Model.ReadLaneStyleString(scope, lane, "stealableStyle", "BORDER_ICON")
        else
            value = AuraFallbackLaneStyle(scope, lane, "stealableStyle", "BORDER_ICON")
        end
        return NormalizeStealableStyle(value)
    end

    local function AuraWriteLaneStealableStyle(scope, lane, value)
        value = NormalizeStealableStyle(value)
        local Model = type(AuraModel) == "function" and AuraModel() or nil
        if Model and type(Model.WriteLaneStyleString) == "function" then
            Model.WriteLaneStyleString(scope, lane, "stealableStyle", value)
        else
            AuraFallbackLaneStyle(scope, lane, "stealableStyle", "BORDER_ICON", value)
        end
    end

    local function AuraReadLaneSortDirection(scope, lane)
        local Model = type(AuraModel) == "function" and AuraModel() or nil
        local reverse
        if Model and type(Model.ReadLaneStyleBool) == "function" then
            reverse = Model.ReadLaneStyleBool(scope, lane, "sortReverse", false)
        else
            reverse = AuraFallbackLaneStyle(scope, lane, "sortReverse", false) == true
        end
        return reverse and "REVERSE" or "NORMAL"
    end

    local function AuraWriteLaneSortDirection(scope, lane, value)
        local reverse = value == "REVERSE"
        local Model = type(AuraModel) == "function" and AuraModel() or nil
        if Model and type(Model.WriteLaneStyleBool) == "function" then
            Model.WriteLaneStyleBool(scope, lane, "sortReverse", reverse)
        else
            AuraFallbackLaneStyle(scope, lane, "sortReverse", false, reverse)
        end
    end

    local function AuraSortExactAliases(scope, lane, direction)
        local out, seen = {}, {}
        local function add(value)
            if value ~= "" and not seen[value] then seen[value] = true; out[#out + 1] = value end
        end
        local scopeWords = { scope }
        local singular = lane == "buff" and "buff" or "debuff"
        local plural = lane == "buff" and "buffs" or "debuffs"
        for i = 1, #scopeWords do
            local scopeWord = scopeWords[i]
            if direction then
                add("order of " .. scopeWord .. " " .. plural)
                add(scopeWord .. " " .. plural .. " order")
                add(scopeWord .. " " .. plural .. " sort order")
                add(scopeWord .. " " .. plural .. " sort direction")
                add(scopeWord .. " " .. singular .. " order")
            else
                add("sort " .. scopeWord .. " " .. plural)
                add(scopeWord .. " " .. plural .. " sort")
                add(scopeWord .. " " .. plural .. " sort method")
                add(scopeWord .. " " .. plural .. " sorting")
                add("sort " .. scopeWord .. " " .. singular)
            end
        end
        return out
    end

    local function NormalizeDurationBarPosition(value)
        value = tostring(value or "BOTTOM"):upper()
        return durationBarPositionAllowed[value] and value or "BOTTOM"
    end

    local function NormalizeDurationBarDisplay(value)
        value = tostring(value or "BAR_ONLY"):upper()
        if value == "ICON" or value == "ICON_BAR" then value = "OVERLAY" end
        return durationBarDisplayAllowed[value] and value or "BAR_ONLY"
    end

    local function NormalizeDurationBarDirection(value)
        value = tostring(value or "REMAINING"):upper()
        if value == "ELAPSED_TIME" then value = "ELAPSED" end
        return durationBarDirectionAllowed[value] and value or "REMAINING"
    end

    local function AuraReadLaneDurationBarPosition(scope, lane)
        local Model = type(AuraModel) == "function" and AuraModel() or nil
        if Model and type(Model.ReadLaneDurationBarPosition) == "function" then
            return NormalizeDurationBarPosition(Model.ReadLaneDurationBarPosition(scope, lane))
        end
        if Model and type(Model.ReadValue) == "function" then
            local laneKey = LaneStyleKey(lane, "durationBarPosition")
            local value = Model.ReadValue(scope, laneKey, nil)
            if value == nil then value = Model.ReadValue(scope, "durationBarPosition", "BOTTOM") end
            return NormalizeDurationBarPosition(value)
        end
        return "BOTTOM"
    end

    local function AuraWriteLaneDurationBarPosition(scope, lane, value)
        value = NormalizeDurationBarPosition(value)
        local Model = type(AuraModel) == "function" and AuraModel() or nil
        if Model and type(Model.WriteLaneDurationBarPosition) == "function" then
            Model.WriteLaneDurationBarPosition(scope, lane, value)
            return
        end
        if Model and type(Model.WriteValue) == "function" then
            Model.WriteValue(scope, LaneStyleKey(lane, "durationBarPosition"), value)
        end
    end

    local function AuraReadLaneDurationBarDisplay(scope, lane)
        local Model = type(AuraModel) == "function" and AuraModel() or nil
        if Model and type(Model.ReadLaneDurationBarDisplay) == "function" then
            return NormalizeDurationBarDisplay(Model.ReadLaneDurationBarDisplay(scope, lane))
        end
        if Model and type(Model.ReadValue) == "function" then
            local laneKey = LaneStyleKey(lane, "durationBarDisplay")
            local value = Model.ReadValue(scope, laneKey, nil)
            if value == nil then value = Model.ReadValue(scope, "durationBarDisplay", "BAR_ONLY") end
            return NormalizeDurationBarDisplay(value)
        end
        return "BAR_ONLY"
    end

    local function AuraWriteLaneDurationBarDisplay(scope, lane, value)
        value = NormalizeDurationBarDisplay(value)
        local Model = type(AuraModel) == "function" and AuraModel() or nil
        if Model and type(Model.WriteLaneDurationBarDisplay) == "function" then
            Model.WriteLaneDurationBarDisplay(scope, lane, value)
            return
        end
        if Model and type(Model.WriteValue) == "function" then
            Model.WriteValue(scope, LaneStyleKey(lane, "durationBarDisplay"), value)
        end
    end

    local function AuraReadLaneDurationBarDirection(scope, lane)
        local Model = type(AuraModel) == "function" and AuraModel() or nil
        if Model and type(Model.ReadLaneDurationBarDirection) == "function" then
            return NormalizeDurationBarDirection(Model.ReadLaneDurationBarDirection(scope, lane))
        end
        if Model and type(Model.ReadValue) == "function" then
            local laneKey = LaneStyleKey(lane, "durationBarDirection")
            local value = Model.ReadValue(scope, laneKey, nil)
            if value == nil then value = Model.ReadValue(scope, "durationBarDirection", "REMAINING") end
            return NormalizeDurationBarDirection(value)
        end
        return "REMAINING"
    end

    local function AuraWriteLaneDurationBarDirection(scope, lane, value)
        value = NormalizeDurationBarDirection(value)
        local Model = type(AuraModel) == "function" and AuraModel() or nil
        if Model and type(Model.WriteLaneDurationBarDirection) == "function" then
            Model.WriteLaneDurationBarDirection(scope, lane, value)
            return
        end
        if Model and type(Model.WriteValue) == "function" then
            Model.WriteValue(scope, LaneStyleKey(lane, "durationBarDirection"), value)
        end
    end

    local function AuraReadDebuffTypeBorderMode(scope)
        local Model = type(AuraModel) == "function" and AuraModel() or nil
        if Model and type(Model.ReadDebuffTypeBorderMode) == "function" then
            return NormalizeDebuffTypeBorderMode(Model.ReadDebuffTypeBorderMode(scope))
        end
        return AuraReadLaneStyleBool(scope, "debuff", "useDebuffTypeBorders", false) and "SYMBOL" or "OFF"
    end

    local function AuraWriteDebuffTypeBorderMode(scope, value)
        value = NormalizeDebuffTypeBorderMode(value)
        local Model = type(AuraModel) == "function" and AuraModel() or nil
        if Model and type(Model.WriteDebuffTypeBorderMode) == "function" then
            Model.WriteDebuffTypeBorderMode(scope, value)
            return
        end
        AuraWriteLaneStyleBool(scope, "debuff", "useDebuffTypeBorders", value ~= "OFF")
    end

    for _, scope in ipairs(AURA_SCOPES) do
        local aliases = {}
        AddAliasesForAuraScope(aliases, scope, "debuff type border")
        AddAliasesForAuraScope(aliases, scope, "debuff border mode")
        AddAliasesForAuraScope(aliases, scope, "dispel type border")
        AddAliasesForAuraScope(aliases, scope, "dispel border mode")
        AddAliasesForAuraScope(aliases, scope, "aura debuff border")
        Registry:RegisterSetting({
            key = "auras3." .. scope .. ".debuff.debuffTypeBorderMode",
            label = AuraScopeLabel(scope) .. " Debuff Type Border",
            category = AuraScopeLabel(scope) .. " / Aura Style",
            unit = scope,
            frameType = "aura",
            attribute = "auraDebuffTypeBorderMode",
            type = "enum",
            aliases = aliases,
            values = AURA_DEBUFF_TYPE_BORDER_VALUES,
            valueAliases = AURA_DEBUFF_TYPE_BORDER_ALIASES,
            get = function() return AuraReadDebuffTypeBorderMode(scope) end,
            set = function(value) AuraWriteDebuffTypeBorderMode(scope, value) end,
            apply = function()
                if type(ApplyAura) == "function" then ApplyAura(scope, "MSUF_ASSISTANT_AURA_STYLE") end
            end,
            combatSafe = false,
        })

        for _, laneInfo in ipairs(AURA_LANES) do
            local lane = laneInfo.key
            local settingScope, settingLane = scope, lane
            for i = 1, #AURA_LANE_STYLE_BOOLEAN_SPECS do
                local spec = AURA_LANE_STYLE_BOOLEAN_SPECS[i]
                aliases = {}
                for j = 1, #spec.words do AddAuraLaneAliases(aliases, settingScope, settingLane, spec.words[j]) end
                if spec.key == "showDurationBar" then
                    A._AssistantAddAuraAllLaneNouns(aliases, settingScope, { "duration bar", "show duration bar", "timer bar", "show timer bar" })
                    A._AssistantAddAllAuraNouns(aliases, settingLane, "all", { "duration bar", "show duration bar", "timer bar", "show timer bar" })
                end
                RegisterAuraScopeLaneBoolean(settingScope, settingLane, spec.key, spec.label, spec.defaultValue, aliases,
                    function() return AuraReadLaneStyleBool(settingScope, settingLane, spec.key, spec.defaultValue) end,
                    function(value) AuraWriteLaneStyleBool(settingScope, settingLane, spec.key, value) end,
                    true)
            end

            aliases = {}
            AddAuraLaneAliases(aliases, settingScope, settingLane, "full frame effect", "vollbild effekt")
            AddAuraLaneAliases(aliases, settingScope, settingLane, "frame effect", "rahmeneffekt")
            RegisterAuraScopeLaneEnum(settingScope, settingLane, "frameEffectType", "Full-Frame Effect",
                AURA_FRAME_EFFECT_TYPE_VALUES, AURA_FRAME_EFFECT_TYPE_ALIASES, aliases,
                function() return AuraReadLaneFrameEffectType(settingScope, settingLane) end,
                function(value) AuraWriteLaneFrameEffectType(settingScope, settingLane, value) end,
                true, {
                    page = "uf_" .. settingScope,
                    exactAliases = aliases,
                    description = "Chooses the Aura-driven Full-Frame visual for this Buff or Debuff lane; it is separate from UnitFrame Dispel Overlay.",
                })

            aliases = {}
            AddAuraLaneAliases(aliases, settingScope, settingLane, "stack anchor")
            AddAuraLaneAliases(aliases, settingScope, settingLane, "stack count anchor")
            RegisterAuraScopeLaneEnum(settingScope, settingLane, "stackAnchor", "Stack Count Anchor", AURA_STACK_ANCHOR_VALUES, AURA_STACK_ANCHOR_ALIASES, aliases,
                function() return AuraReadLaneStackAnchor(settingScope, settingLane) end,
                function(value) AuraWriteLaneStackAnchor(settingScope, settingLane, value) end,
                true)

            aliases = {}
            AddAuraLaneAliases(aliases, settingScope, settingLane, "cooldown anchor")
            AddAuraLaneAliases(aliases, settingScope, settingLane, "cooldown text anchor")
            AddAuraLaneAliases(aliases, settingScope, settingLane, "timer text anchor")
            RegisterAuraScopeLaneEnum(settingScope, settingLane, "cooldownAnchor", "Cooldown Anchor", AURA_ANCHOR_VALUES, AURA_ANCHOR_ALIASES, aliases,
                function() return AuraReadLaneCooldownAnchor(settingScope, settingLane) end,
                function(value) AuraWriteLaneCooldownAnchor(settingScope, settingLane, value) end,
                true)

            aliases = {}
            AddAuraLaneAliases(aliases, settingScope, settingLane, "swipe direction")
            AddAuraLaneAliases(aliases, settingScope, settingLane, "cooldown swipe direction")
            AddAuraLaneAliases(aliases, settingScope, settingLane, "timer swipe direction")
            AddAuraLaneAliases(aliases, settingScope, settingLane, "reverse cooldown swipe")
            RegisterAuraScopeLaneEnum(settingScope, settingLane, "cooldownSwipeReverse", "Cooldown Swipe Direction", AURA_COOLDOWN_SWIPE_DIRECTION_VALUES, AURA_COOLDOWN_SWIPE_DIRECTION_ALIASES, aliases,
                function() return AuraReadLaneStyleBool(settingScope, settingLane, "cooldownSwipeReverse", false) and "REVERSE" or "NORMAL" end,
                function(value) AuraWriteLaneStyleBool(settingScope, settingLane, "cooldownSwipeReverse", value == "REVERSE") end,
                true)

            -- Stealable/purgeable marking exists on the buff lane only; a
            -- debuff cannot be stolen or purged, so registering it for both
            -- lanes would publish a control that can never do anything.
            -- Vocabulary deliberately avoids the bare "stealable buffs" /
            -- "purgeable buffs" wording: the includeDispellable FILTER already
            -- owns those, and it decides WHICH buffs are listed. This setting
            -- only marks the ones already shown, so it answers to marker,
            -- highlight and indicator wording instead.
            if settingLane == "buff" then
                aliases = {}
                for _, noun in ipairs(AURA_STEALABLE_MARKER_NOUNS) do
                    AddAuraLaneAliases(aliases, settingScope, settingLane, noun)
                end
                RegisterAuraScopeLaneBoolean(settingScope, settingLane, "showStealable", "Stealable Marker", false, aliases,
                    function() return AuraReadLaneStyleBool(settingScope, settingLane, "showStealable", false) end,
                    function(value) AuraWriteLaneStyleBool(settingScope, settingLane, "showStealable", value) end,
                    true, { exactAliases = AuraStealableExactAliases(settingScope, AURA_STEALABLE_MARKER_NOUNS) })

                aliases = {}
                for _, noun in ipairs(AURA_STEALABLE_STYLE_NOUNS) do
                    AddAuraLaneAliases(aliases, settingScope, settingLane, noun)
                end
                RegisterAuraScopeLaneEnum(settingScope, settingLane, "stealableStyle", "Stealable Marker Style",
                    AURA_STEALABLE_STYLE_VALUES, AURA_STEALABLE_STYLE_ALIASES, aliases,
                    function() return AuraReadLaneStealableStyle(settingScope, settingLane) end,
                    function(value) AuraWriteLaneStealableStyle(settingScope, settingLane, value) end,
                    true, { exactAliases = AuraStealableExactAliases(settingScope, AURA_STEALABLE_STYLE_NOUNS) })
            end

            aliases = {}
            AddAuraLaneAliases(aliases, settingScope, settingLane, "sort")
            AddAuraLaneAliases(aliases, settingScope, settingLane, "sort method")
            AddAuraLaneAliases(aliases, settingScope, settingLane, "sorting")
            RegisterAuraScopeLaneEnum(settingScope, settingLane, "sortMethod", "Sort Method",
                AURA_SORT_METHOD_VALUES[settingLane], AURA_SORT_METHOD_ALIASES[settingLane] or {}, aliases,
                function() return AuraReadLaneSortMethod(settingScope, settingLane) end,
                function(value) AuraWriteLaneSortMethod(settingScope, settingLane, value) end,
                false, {
                    page = settingLane == "buff" and "auras3_buffs" or "auras3_debuffs",
                    exactAliases = AuraSortExactAliases(settingScope, settingLane, false),
                    description = "Chooses the native Blizzard AuraContainer comparator for this Aura lane; it does not enable or disable the lane.",
                })

            aliases = {}
            AddAuraLaneAliases(aliases, settingScope, settingLane, "sort order")
            AddAuraLaneAliases(aliases, settingScope, settingLane, "order")
            AddAuraLaneAliases(aliases, settingScope, settingLane, "sort direction")
            RegisterAuraScopeLaneEnum(settingScope, settingLane, "sortReverse", "Sort Order",
                AURA_SORT_DIRECTION_VALUES, AURA_SORT_DIRECTION_ALIASES, aliases,
                function() return AuraReadLaneSortDirection(settingScope, settingLane) end,
                function(value) AuraWriteLaneSortDirection(settingScope, settingLane, value) end,
                false, {
                    page = settingLane == "buff" and "auras3_buffs" or "auras3_debuffs",
                    exactAliases = AuraSortExactAliases(settingScope, settingLane, true),
                    description = "Uses the native normal or reversed AuraContainer order without changing lane visibility.",
                })

            aliases = {}
            AddAuraLaneAliases(aliases, settingScope, settingLane, "duration bar position")
            AddAuraLaneAliases(aliases, settingScope, settingLane, "timer bar position")
            AddAuraLaneAliases(aliases, settingScope, settingLane, "duration bar edge")
            A._AssistantAddAuraAllLaneNouns(aliases, settingScope, { "duration bar position", "timer bar position", "duration bar edge" })
            RegisterAuraScopeLaneEnum(settingScope, settingLane, "durationBarPosition", "Duration Bar Position", AURA_DURATION_BAR_POSITION_VALUES, AURA_DURATION_BAR_POSITION_ALIASES, aliases,
                function() return AuraReadLaneDurationBarPosition(settingScope, settingLane) end,
                function(value) AuraWriteLaneDurationBarPosition(settingScope, settingLane, value) end,
                true)

            aliases = {}
            AddAuraLaneAliases(aliases, settingScope, settingLane, "duration bar display")
            AddAuraLaneAliases(aliases, settingScope, settingLane, "timer bar display")
            AddAuraLaneAliases(aliases, settingScope, settingLane, "duration bar mode")
            AddAuraLaneAliases(aliases, settingScope, settingLane, "timer bar mode")
            A._AssistantAddAuraAllLaneNouns(aliases, settingScope, { "duration bar display", "timer bar display", "duration bar mode", "timer bar mode" })
            RegisterAuraScopeLaneEnum(settingScope, settingLane, "durationBarDisplay", "Duration Bar Display", AURA_DURATION_BAR_DISPLAY_VALUES, AURA_DURATION_BAR_DISPLAY_ALIASES, aliases,
                function() return AuraReadLaneDurationBarDisplay(settingScope, settingLane) end,
                function(value) AuraWriteLaneDurationBarDisplay(settingScope, settingLane, value) end,
                true)

            aliases = {}
            AddAuraLaneAliases(aliases, settingScope, settingLane, "duration bar fill mode")
            AddAuraLaneAliases(aliases, settingScope, settingLane, "duration bar direction")
            AddAuraLaneAliases(aliases, settingScope, settingLane, "timer bar fill mode")
            AddAuraLaneAliases(aliases, settingScope, settingLane, "timer bar direction")
            A._AssistantAddAuraAllLaneNouns(aliases, settingScope, { "duration bar fill mode", "duration bar direction", "timer bar fill mode", "timer bar direction" })
            RegisterAuraScopeLaneEnum(settingScope, settingLane, "durationBarDirection", "Duration Bar Fill Mode", AURA_DURATION_BAR_DIRECTION_VALUES, AURA_DURATION_BAR_DIRECTION_ALIASES, aliases,
                function() return AuraReadLaneDurationBarDirection(settingScope, settingLane) end,
                function(value) AuraWriteLaneDurationBarDirection(settingScope, settingLane, value) end,
                true)

            for i = 1, #AURA_LANE_STYLE_NUMBER_SPECS do
                local spec = AURA_LANE_STYLE_NUMBER_SPECS[i]
                aliases = {}
                for j = 1, #spec.words do AddAuraLaneAliases(aliases, settingScope, settingLane, spec.words[j]) end
                if spec.key == "durationBarHeight" then
                    A._AssistantAddAuraAllLaneNouns(aliases, settingScope, { "duration bar height", "timer bar height" })
                    A._AssistantAddAllAuraNouns(aliases, settingLane, "all", { "duration bar height", "timer bar height" })
                end
                RegisterAuraScopeLaneNumber(settingScope, settingLane, spec.key, spec.label, spec.defaultValue, spec.minValue, spec.maxValue, aliases,
                    function() return AuraReadLaneStyleNumber(settingScope, settingLane, spec.key, spec.defaultValue, spec.minValue, spec.maxValue) end,
                    function(value) AuraWriteLaneStyleNumber(settingScope, settingLane, spec.key, value, spec.minValue, spec.maxValue) end,
                    true)
            end
        end

        local RegisterFilterSettings = A.AurasRegistry and A.AurasRegistry.RegisterFilterSettings
        if type(RegisterFilterSettings) == "function" then RegisterFilterSettings(ctx, scope) end
    end
end
