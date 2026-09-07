-- Custom display/container storage, product invariants, and style transfer.
-- Custom-4 is Player Defensives on Player and Target DoTs on other UnitFrames;
-- migrations and Copy To must preserve each destination product's controls.
-- Style migration is defined before its reader, with no cross-module late bind.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
local Factories = MSUF.Auras3MenuModelFactories
if not Factories then
    Factories = {}
    MSUF.Auras3MenuModelFactories = Factories
end

function Factories.Containers(A3, Model, Schema, Common, Storage)
    local type = type
    local tonumber = tonumber
    local tostring = tostring
    local pairs = pairs
    local math_floor = math.floor
    local CUSTOM_CONTAINER_MAX = Schema.CUSTOM_CONTAINER_MAX
    local PLAYER_DEFENSIVE_CONTAINER_INDEX = Schema.PLAYER_DEFENSIVE_CONTAINER_INDEX
    local STYLE_LAYOUT_KEYS = Schema.STYLE_LAYOUT_KEYS
    local STYLE_SHARED_LAYOUT_KEYS = Schema.STYLE_SHARED_LAYOUT_KEYS
    local TARGET_DOT_CONTAINER_INDEX = Schema.TARGET_DOT_CONTAINER_INDEX
    local ClampNumber = Common.ClampNumber
    local DeepCopy = Common.DeepCopy
    local EachRuntimeUnit = Common.EachRuntimeUnit
    local NormalizeScope = Common.NormalizeScope
    local NormalizeUnit = Common.NormalizeUnit
    local ClearKeys = Storage.ClearKeys
    local PerUnit = Storage.PerUnit
    local RefreshLayoutOverrideFlags = Storage.RefreshLayoutOverrideFlags
    local UnitStyleOverrideActive = Storage.UnitStyleOverrideActive

    local function CustomDisplayRoot()
        local auras = Model.EnsureDB()
        return auras and auras.customDisplays
    end

    local function CustomDisplayScope(scope, create)
        local root = CustomDisplayRoot()
        if not root then return nil end
        scope = NormalizeScope(scope)
        if scope == "shared" then return root.shared end
        local record = root.perUnit[scope]
        if create and type(record) ~= "table" then
            record = { override = false, items = {} }
            root.perUnit[scope] = record
        end
        return record
    end

    function Model.UseSharedCustomDisplays(scope)
        scope = NormalizeScope(scope)
        if scope == "shared" then return false end
        local record = CustomDisplayScope(scope, false)
        return not (record and record.override == true)
    end

    function Model.SetUseSharedCustomDisplays(scope, useShared)
        scope = NormalizeScope(scope)
        if scope == "shared" then return end
        local root = CustomDisplayRoot()
        local record = CustomDisplayScope(scope, true)
        if not (root and record) then return end
        if useShared then
            record.override = false
        elseif record.override ~= true then
            record.items = DeepCopy(root.shared.items or {})
            record.override = true
        end
    end

    function Model.CustomDisplayItems(scope, editable)
        scope = NormalizeScope(scope)
        local root = CustomDisplayRoot()
        if not root then return {} end
        if scope == "shared" then return root.shared.items end
        local record = CustomDisplayScope(scope, editable == true)
        if editable == true and record and record.override ~= true then
            record.items = DeepCopy(root.shared.items or {})
            record.override = true
        end
        if record and record.override == true and type(record.items) == "table" then return record.items end
        return root.shared.items
    end

    function Model.AddCustomDisplay(scope)
        local root = CustomDisplayRoot()
        if not root then return nil end
        local items = Model.CustomDisplayItems(scope, true)
        root.serial = (tonumber(root.serial) or 0) + 1
        local item = {
            id = root.serial,
            name = "Custom Aura " .. tostring(#items + 1),
            enabled = true,
            auraType = "BUFF",
            spellIDs = "",
            onlyOwn = false,
            layer = 9,
            strata = "AUTO",
            placed = {
                type = "icon", anchor = "TOPRIGHT", x = 0, y = 0,
                size = 24, barWidth = 54, iconShape = "RECTANGLE", showCooldown = true,
                showCooldownSwipe = true, showStacks = true,
            },
            frame = { type = "none", color = { 0.69, 0.50, 0.88, 0.80 }, priority = 5, thickness = 2, layer = 0, strata = "AUTO" },
        }
        items[#items + 1] = item
        return item
    end

    function Model.RemoveCustomDisplay(scope, id)
        local items = Model.CustomDisplayItems(scope, true)
        for i = #items, 1, -1 do
            if items[i] == id or tostring(items[i] and items[i].id) == tostring(id) then
                table.remove(items, i)
                return true
            end
        end
        return false
    end

    function Model.CustomDisplayByID(scope, id, editable)
        local items = Model.CustomDisplayItems(scope, editable == true)
        for i = 1, #items do
            if tostring(items[i] and items[i].id) == tostring(id) then return items[i], i end
        end
        return items[1], 1
    end

    local PLAYER_DEFENSIVE_CORE_DEFAULT_MARKER =
        A3.PlayerDefensiveCoreDefaultMarker or "_msufA3PlayerDefensivesCoreDefault_v1"

    local function EnforcePlayerDefensiveContainer(item, canonicalAuraModel)
        if type(item) ~= "table" then return item end
        -- Fallback for standalone menu-model consumers and old profiles that have
        -- not passed through Auras3 Core yet. This is one-shot by design: once the
        -- user turns the feature off in Menu2, later normalization preserves it.
        -- Canonical profiles are already Defaults-owned and intentionally carry no
        -- legacy marker, so their saved false value must never be treated as new.
        if canonicalAuraModel ~= true and item[PLAYER_DEFENSIVE_CORE_DEFAULT_MARKER] ~= true then
            item.enabled = true
            item[PLAYER_DEFENSIVE_CORE_DEFAULT_MARKER] = true
        end
        item.name = "Defensive Buffs"
        item.auraType = "BUFF"
        item.sourceUnit = "player"
        item.targetDots = nil
        item.playerDefensives = true
        item.portraitIcon = item.portraitIcon == true
        -- Preserve the original one-icon portrait behavior for existing profiles.
        -- Users can opt into a wider outward-growing row from the setup slider.
        item.portraitMaxIcons = math_floor(ClampNumber(item.portraitMaxIcons, 1, 1, 8))
        item.portraitCooldownText = item.portraitCooldownText ~= false
        item.portraitPositionWhenDisabled = item.portraitPositionWhenDisabled == true
        item.autoBlacklistPlayerBuffs = item.autoBlacklistPlayerBuffs ~= false
        item.disabledPredefinedSpellIDs = type(item.disabledPredefinedSpellIDs) == "table"
            and item.disabledPredefinedSpellIDs or {}
        item.placed = type(item.placed) == "table" and item.placed or {}
        item.placed.iconShape = type(A3.NormalizeAuraIconShape) == "function"
            and A3.NormalizeAuraIconShape(item.placed.iconShape) or (item.placed.iconShape or "RECTANGLE")
        item.filters = type(item.filters) == "table" and item.filters or {}
        item.filters.enabled = true
        item.filters.onlyMine = false
        item.filters.onlyImportant = false
        item.filters.raid = false
        item.filters.raidInCombat = false
        item.filters.includeNameplateOnly = false
        item.filters.includeDispellable = false
        item.filters.dispellableAny = false
        item.filters.cancelable = false
        item.filters.notCancelable = false
        item.filters.crowdControl = false
        item.filters.externalDefensive = false
        item.filters.bigDefensive = false
        item.filters.exclusive = "none"
        -- Pre-preset custom4 profiles may carry a DEBUFF-era duration ceiling;
        -- since 6.09 compiles maxDuration for every lane it would silently hide
        -- long or permanent defensives, so the pin clears it like other filters.
        item.filters.maxDuration = nil
        return item
    end

    local function EnforceTargetDotContainer(item)
        if type(item) ~= "table" then return item end
        item.name = "Dots on target"
        item.auraType = "DEBUFF"
        -- The saved scope is shared by the five Boss frames, but the runtime binds
        -- this lane to the concrete frame unit (target/focus/boss1..boss5).
        item.sourceUnit = nil
        item.targetDots = true
        item.playerDefensives = nil
        item.portraitIcon = item.portraitIcon == true
        item.portraitMaxIcons = math_floor(ClampNumber(item.portraitMaxIcons, 1, 1, 8))
        item.portraitCooldownText = item.portraitCooldownText ~= false
        item.portraitPositionWhenDisabled = item.portraitPositionWhenDisabled == true
        item.autoBlacklistDebuffs = item.autoBlacklistDebuffs ~= false
        item.autoBlacklistPlayerBuffs = nil
        item.disabledPredefinedSpellIDs = nil
        item.placed = type(item.placed) == "table" and item.placed or {}
        item.placed.iconShape = type(A3.NormalizeAuraIconShape) == "function"
            and A3.NormalizeAuraIconShape(item.placed.iconShape) or (item.placed.iconShape or "RECTANGLE")
        item.placed.pandemicEnabled = item.placed.pandemicEnabled == true
        if type(A3.NormalizePandemicStyle) == "function" then
            item.placed.pandemicStyle = A3.NormalizePandemicStyle(item.placed.pandemicStyle)
        else
            local pandemicStyle = tostring(item.placed.pandemicStyle or "BORDER"):upper()
            if pandemicStyle == "ALL" then pandemicStyle = "BORDER_TINT"
            elseif pandemicStyle ~= "BORDER" and pandemicStyle ~= "TINT" and pandemicStyle ~= "BORDER_TINT" then pandemicStyle = "BORDER" end
            item.placed.pandemicStyle = pandemicStyle
        end
        local pandemicColor = type(item.placed.pandemicColor) == "table" and item.placed.pandemicColor or nil
        item.placed.pandemicColor = {
            ClampNumber(pandemicColor and (pandemicColor[1] or pandemicColor.r), 1, 0, 1),
            ClampNumber(pandemicColor and (pandemicColor[2] or pandemicColor.g), 0.24, 0, 1),
            ClampNumber(pandemicColor and (pandemicColor[3] or pandemicColor.b), 0.08, 0, 1),
        }
        item.placed.pandemicThickness = ClampNumber(item.placed.pandemicThickness, 2, 1, 12)
        item.placed.pandemicPadding = ClampNumber(item.placed.pandemicPadding, 1, -8, 16)
        item.placed.pandemicBorderAlpha = ClampNumber(item.placed.pandemicBorderAlpha, 1, 0.05, 1)
        item.placed.pandemicTintAlpha = ClampNumber(item.placed.pandemicTintAlpha, 0.22, 0.05, 1)
        item.placed.pandemicBlend = tostring(item.placed.pandemicBlend or "ADD"):upper() == "BLEND" and "BLEND" or "ADD"
        item.frame = type(item.frame) == "table" and item.frame or {
            type = "none", color = { 0.69, 0.50, 0.88, 0.80 },
            priority = 5, thickness = 2, layer = 0, strata = "AUTO",
        }
        item.frame.onlyInPandemicWindow = item.frame.onlyInPandemicWindow == true
        item.filters = type(item.filters) == "table" and item.filters or {}
        item.filters.enabled = true
        item.filters.onlyMine = true
        item.filters.onlyImportant = false
        item.filters.raid = false
        item.filters.raidInCombat = false
        item.filters.includeNameplateOnly = false
        item.filters.includeDispellable = false
        item.filters.dispellableAny = false
        item.filters.cancelable = false
        item.filters.notCancelable = false
        item.filters.crowdControl = false
        item.filters.externalDefensive = false
        item.filters.bigDefensive = false
        item.filters.exclusive = "none"
        return item
    end

    local function NewCustomContainer(index, unit)
        local item = {
            enabled = false,
            name = "Custom " .. tostring(index),
            auraType = "BUFF",
            spellIDs = "",
            -- Temporary weapon enchants are not auras, so they are tracked per
            -- weapon slot instead of through the whitelist. One consumable
            -- covers both hands in practice.
            reminderEnchantMainHand = false,
            reminderEnchantOffHand = false,
            -- C_PaperDollInfo exposes only remainingTimeMs. Oils normally last one
            -- hour, and this user-adjustable total lets their swipe retain the
            -- correct progress after login/reload instead of restarting as full.
            reminderEnchantDurationMinutes = 60,
            filters = {
                enabled = true,
                hidePermanent = false,
                onlyMine = false,
                onlyImportant = false,
                raid = false,
                raidInCombat = false,
                includeNameplateOnly = false,
                includeDispellable = false,
                dispellableAny = false,
                cancelable = false,
                notCancelable = false,
                crowdControl = false,
                externalDefensive = false,
                bigDefensive = false,
                exclusive = "none",
            },
            placed = {
                type = "icon", anchor = "TOPRIGHT", growth = "LEFTDOWN",
                x = 0, y = 0, size = 24, barWidth = 54,
                max = 8, perRow = 4, spacing = 2,
                iconShape = "RECTANGLE",
                showCooldown = true, showCooldownSwipe = true, showStacks = true,
                -- Buff Reminder is off by default: it converts the container from a
                -- compacting list into one fixed slot per whitelisted spell.
                reminderEnabled = false, reminderAlpha = 0.45,
                reminderDesaturate = true, reminderColor = { 1, 1, 1 },
                -- Click-to-cast follows the reminder itself: a placeholder the
                -- user cannot act on is only half the feature.
                reminderClickCast = true,
                -- Opt-in: nothing a user deliberately whitelisted should vanish
                -- without them asking for it.
                reminderOnlyCastable = false,
            },
            layer = 9,
            strata = "AUTO",
            frame = {
                type = "none", color = { 0.69, 0.50, 0.88, 0.80 },
                priority = 5, thickness = 2, layer = 0, strata = "AUTO",
                onlyInPandemicWindow = false,
            },
        }
        if index == PLAYER_DEFENSIVE_CONTAINER_INDEX and NormalizeScope(unit) == "player" then
            return EnforcePlayerDefensiveContainer(item)
        end
        return index == TARGET_DOT_CONTAINER_INDEX and EnforceTargetDotContainer(item) or item
    end

    local function UpgradeLegacyCustomContainer(dst, legacy, index)
        if type(dst) ~= "table" or type(legacy) ~= "table" then return dst end
        dst.enabled = legacy.enabled ~= false
        dst.name = legacy.name or dst.name
        dst.auraType = legacy.auraType == "DEBUFF" and "DEBUFF" or "BUFF"
        dst.spellIDs = legacy.spellIDs or legacy.includeSpellIDs or ""
        dst.layer = legacy.layer or dst.layer
        dst.strata = legacy.strata or dst.strata
        if type(legacy.placed) == "table" then
            for key, value in pairs(legacy.placed) do dst.placed[key] = DeepCopy(value) end
        end
        if type(legacy.frame) == "table" then dst.frame = DeepCopy(legacy.frame) end
        if legacy.onlyOwn == true then dst.filters.onlyMine = true end
        dst._migratedFromCustomDisplay = legacy.id or index
        return dst
    end

    local function EnsureUnitCustomContainers(unit, create)
        unit = NormalizeScope(unit)
        if unit == "shared" then unit = "player" end
        local auras = Model.EnsureDB()
        local root = auras.customContainers
        local record = root.perUnit[unit]
        if type(record) ~= "table" and create then
            record = { items = {} }
            root.perUnit[unit] = record
        end
        if type(record) ~= "table" then return nil, auras end
        if type(record.items) ~= "table" then record.items = {} end
        if record._msufA3CustomContainersMigrated_v1 ~= true then
            local oldRoot = Model.EnsureDB().customDisplays
            local oldRecord = oldRoot and oldRoot.perUnit and oldRoot.perUnit[unit]
            local oldItems = oldRecord and oldRecord.override == true and oldRecord.items
                or (oldRoot and oldRoot.shared and oldRoot.shared.items)
            if type(oldItems) == "table" then
                for i = 1, math.min(CUSTOM_CONTAINER_MAX, #oldItems) do
                    if type(record.items[i]) ~= "table" then
                        record.items[i] = UpgradeLegacyCustomContainer(NewCustomContainer(i, unit), oldItems[i], i)
                    end
                end
            end
            record._msufA3CustomContainersMigrated_v1 = true
        end
        return record, auras
    end

    function Model.CustomContainerMax()
        return CUSTOM_CONTAINER_MAX
    end

    --- Copies only the controls exposed by the UnitFrame Aura Style tools.
    --- Visibility, positioning, filters, whitelists and tracked spells stay owned
    --- by the destination. This is a cold-path Copy To operation.
    Model.CustomContainerStylePlacedKeys = Model.CustomContainerStylePlacedKeys or {
        iconZoom = true,
        showTooltip = true,
        alpha = true,
        debuffTypeBorderMode = true,
        showStacks = true,
        stackSize = true,
        stackAnchor = true,
        stackX = true,
        stackY = true,
        showCooldown = true,
        showCooldownSwipe = true,
        cooldownSwipeReverse = true,
        cooldownSize = true,
        cooldownAnchor = true,
        cooldownX = true,
        cooldownY = true,
        cooldownDecimalSeconds = true,
        showDurationBar = true,
        durationBarHeight = true,
        durationBarDisplay = true,
        durationBarPosition = true,
        durationBarDirection = true,
        pandemicEnabled = true,
        pandemicStyle = true,
        pandemicColor = true,
        pandemicThickness = true,
        pandemicPadding = true,
        pandemicBorderAlpha = true,
        pandemicTintAlpha = true,
        pandemicBlend = true,
        sortMethod = true,
        sortReverse = true,
    }

    --- Custom-4 represents two different products: Player Defensive buffs on
    --- Player and Target DoTs everywhere else. Their common presentation can be
    --- copied, but these destination-only controls have no compatible value on the
    --- opposite product. Preserve them instead of clearing them to defaults (or
    --- importing a sort method from the wrong helpful/harmful domain).
    local INCOMPATIBLE_CUSTOM4_DESTINATION_STYLE_KEYS = {
        debuffTypeBorderMode = true,
        sortMethod = true,
        sortReverse = true,
        pandemicEnabled = true,
        pandemicStyle = true,
        pandemicColor = true,
        pandemicThickness = true,
        pandemicPadding = true,
        pandemicBorderAlpha = true,
        pandemicTintAlpha = true,
        pandemicBlend = true,
    }

    local function CustomContainerStyleProduct(unit, index)
        if index ~= PLAYER_DEFENSIVE_CONTAINER_INDEX then return nil end
        return NormalizeUnit(unit) == "player" and "playerDefensives" or "targetDots"
    end

    --- Older builds stored Custom-4 presentation in one global specialStyles
    --- record.  Materialize that last effective look into every owning frame once,
    --- then keep all future edits frame-local.  Content, filters, placement and
    --- tracked spells never pass through this migration.
    local function MigrateLegacySpecialStyle(unit, index, item)
        if index ~= 4 or type(item) ~= "table" or item._msufA3LocalStyleFromShared_v1 == true then return end
        local normalizedUnit = NormalizeUnit(unit)
        local kind = normalizedUnit == "player" and "playerDefensives" or "targetDots"
        local auras, shared = Model.EnsureDB()
        local styles = type(shared) == "table" and shared.specialStyles or nil
        local legacy = type(styles) == "table" and type(styles[kind]) == "table" and styles[kind] or nil
        if legacy then
            item.placed = type(item.placed) == "table" and item.placed or {}
            local sourcePlaced = type(legacy.placed) == "table" and legacy.placed or nil
            if sourcePlaced then
                for key in pairs(Model.CustomContainerStylePlacedKeys) do
                    if sourcePlaced[key] ~= nil then item.placed[key] = DeepCopy(sourcePlaced[key]) end
                end
            end
            if type(legacy.frame) == "table" then item.frame = DeepCopy(legacy.frame) end
        end
        item._msufA3LocalStyleFromShared_v1 = true
    end

    function Model.CustomContainerStyleItem(unit, index, create)
        return Model.CustomContainer(unit, index, create)
    end

    function Model.CustomContainer(unit, index, create)
        unit = NormalizeScope(unit)
        if unit == "shared" then unit = "player" end
        index = math_floor(ClampNumber(index, 1, 1, CUSTOM_CONTAINER_MAX))
        local record, auras = EnsureUnitCustomContainers(unit, create == true)
        if not record then return nil end
        local item = record.items[index]
        if type(item) ~= "table" and create == true then
            item = NewCustomContainer(index, unit)
            record.items[index] = item
        end
        if index == PLAYER_DEFENSIVE_CONTAINER_INDEX and unit == "player" then
            EnforcePlayerDefensiveContainer(item, (tonumber(auras and auras.profileModelRevision) or 0) >= 1)
        elseif index == TARGET_DOT_CONTAINER_INDEX then
            EnforceTargetDotContainer(item)
        end
        if MigrateLegacySpecialStyle then MigrateLegacySpecialStyle(unit, index, item) end
        return item
    end

    function Model.CustomContainers(unit, create)
        local record = EnsureUnitCustomContainers(unit, create == true)
        return record and record.items or {}
    end

    local function SelectedCopy(source, keys)
        local out = {}
        if type(source) ~= "table" then return out end
        for key in pairs(keys) do
            if source[key] ~= nil then out[key] = DeepCopy(source[key]) end
        end
        return out
    end

    --- Captures only the values exposed by Aura Style.  Aura Options can therefore
    --- replace the rest of a frame's Aura workspace without accidentally changing
    --- its visual presentation.
    function Model.CaptureUnitStyle(unit)
        unit = NormalizeUnit(unit)
        local auras = Model.EnsureDB()
        if type(auras) ~= "table" then return nil end
        local sourceRecord = PerUnit(auras, unit, false)
        local snapshot = {
            ownsStyle = UnitStyleOverrideActive(sourceRecord),
            layout = SelectedCopy(sourceRecord and sourceRecord.layout, STYLE_LAYOUT_KEYS),
            layoutShared = SelectedCopy(sourceRecord and sourceRecord.layoutShared, STYLE_SHARED_LAYOUT_KEYS),
            custom = {},
        }
        for index = 1, CUSTOM_CONTAINER_MAX do
            local item = Model.CustomContainer(unit, index, true)
            local placed = type(item) == "table" and type(item.placed) == "table" and item.placed or nil
            snapshot.custom[index] = {
                product = CustomContainerStyleProduct(unit, index),
                placed = SelectedCopy(placed, Model.CustomContainerStylePlacedKeys),
                frame = type(item) == "table" and type(item.frame) == "table" and DeepCopy(item.frame) or nil,
            }
        end
        return snapshot
    end

    function Model.ApplyUnitStyleSnapshot(destinationUnit, snapshot)
        destinationUnit = NormalizeUnit(destinationUnit)
        if type(snapshot) ~= "table" then return false end
        local auras = Model.EnsureDB()
        if type(auras) ~= "table" then return false end

        EachRuntimeUnit(destinationUnit, function(runtimeUnit)
            local destinationRecord = PerUnit(auras, runtimeUnit, true)
            if not destinationRecord then return end
            destinationRecord.layout = type(destinationRecord.layout) == "table" and destinationRecord.layout or {}
            destinationRecord.layoutShared = type(destinationRecord.layoutShared) == "table" and destinationRecord.layoutShared or {}
            ClearKeys(destinationRecord.layout, STYLE_LAYOUT_KEYS)
            ClearKeys(destinationRecord.layoutShared, STYLE_SHARED_LAYOUT_KEYS)
            if snapshot.ownsStyle == true then
                for key, value in pairs(snapshot.layout or {}) do destinationRecord.layout[key] = DeepCopy(value) end
                for key, value in pairs(snapshot.layoutShared or {}) do destinationRecord.layoutShared[key] = DeepCopy(value) end
                destinationRecord.overrideStyle = true
            else
                destinationRecord.overrideStyle = false
            end
            RefreshLayoutOverrideFlags(destinationRecord)
        end)

        for index = 1, CUSTOM_CONTAINER_MAX do
            local destinationItem = Model.CustomContainer(destinationUnit, index, true)
            local sourceStyle = type(snapshot.custom) == "table" and snapshot.custom[index] or nil
            if destinationItem and type(sourceStyle) == "table" then
                destinationItem.placed = type(destinationItem.placed) == "table" and destinationItem.placed or {}
                local destinationProduct = CustomContainerStyleProduct(destinationUnit, index)
                local preserveDestinationProductStyle = sourceStyle.product ~= nil
                    and destinationProduct ~= nil
                    and sourceStyle.product ~= destinationProduct
                local destinationProductStyle
                local destinationPandemicFrameCondition
                if preserveDestinationProductStyle then
                    destinationProductStyle = SelectedCopy(
                        destinationItem.placed, INCOMPATIBLE_CUSTOM4_DESTINATION_STYLE_KEYS)
                    destinationPandemicFrameCondition = type(destinationItem.frame) == "table"
                        and destinationItem.frame.onlyInPandemicWindow == true or false
                end
                ClearKeys(destinationItem.placed, Model.CustomContainerStylePlacedKeys)
                for key, value in pairs(sourceStyle.placed or {}) do destinationItem.placed[key] = DeepCopy(value) end
                if preserveDestinationProductStyle then
                    -- Iterate the complete schema so an absent destination value
                    -- also removes an incompatible source-only value.
                    for key in pairs(INCOMPATIBLE_CUSTOM4_DESTINATION_STYLE_KEYS) do
                        destinationItem.placed[key] = DeepCopy(destinationProductStyle[key])
                    end
                end
                destinationItem.frame = type(sourceStyle.frame) == "table" and DeepCopy(sourceStyle.frame) or nil
                if preserveDestinationProductStyle and type(destinationItem.frame) == "table" then
                    destinationItem.frame.onlyInPandemicWindow = destinationPandemicFrameCondition
                end
                destinationItem._msufA3LocalStyleFromShared_v1 = true
                -- Re-apply the product invariants without replacing copied Style.
                Model.CustomContainer(destinationUnit, index, true)
            end
        end
        return true
    end

    function Model.CopyUnitStyle(sourceUnit, destinationUnit)
        sourceUnit, destinationUnit = NormalizeUnit(sourceUnit), NormalizeUnit(destinationUnit)
        if sourceUnit == destinationUnit then return false end
        return Model.ApplyUnitStyleSnapshot(destinationUnit, Model.CaptureUnitStyle(sourceUnit))
    end

    function Model.ResetCustomContainer(unit, index)
        unit = NormalizeScope(unit)
        if unit == "shared" then unit = "player" end
        local record = EnsureUnitCustomContainers(unit, true)
        index = math_floor(ClampNumber(index, 1, 1, CUSTOM_CONTAINER_MAX))
        record.items[index] = NewCustomContainer(index, unit)
        return record.items[index]
    end

end
