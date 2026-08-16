-- Assistant UnitFrame status icon registry.
-- Keeps status-icon metadata outside the main UnitFrame registry loop while
-- preserving the same cold Assistant registration behavior.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.UnitframesRegistry = A.UnitframesRegistry or {}

function A.UnitframesRegistry.RegisterStatusIconSettings(ctx, unit)
    if type(ctx) ~= "table" or type(unit) ~= "string" then return end

    local AddAliasesForUnit = ctx.AddAliasesForUnit
    local MakeAliases = ctx.MakeAliases
    local RegisterUnitBooleanSetting = ctx.RegisterUnitBooleanSetting
    local RegisterUnitString = ctx.RegisterUnitString
    local RegisterUnitEnum = ctx.RegisterUnitEnum
    local RegisterUnitNumberSetting = ctx.RegisterUnitNumberSetting
    local StatusIconOpts = ctx.StatusIconOpts
    local UnitDB = ctx.UnitDB
    local GeneralDB = ctx.GeneralDB
    local AllowedMap = ctx.AllowedMap

    if type(AddAliasesForUnit) ~= "function" or type(MakeAliases) ~= "function" then return end
    if type(RegisterUnitBooleanSetting) ~= "function" or type(RegisterUnitString) ~= "function" then return end
    if type(RegisterUnitEnum) ~= "function" or type(RegisterUnitNumberSetting) ~= "function" then return end
    if type(StatusIconOpts) ~= "function" or type(UnitDB) ~= "function" or type(GeneralDB) ~= "function" then return end
    if type(AllowedMap) ~= "function" then return end

    local STATUS_CONTROL_SPECS = ctx.STATUS_CONTROL_SPECS or {}
    local STATUS_ICON_PACK_FALLBACK_VALUES = ctx.STATUS_ICON_PACK_FALLBACK_VALUES or {}
    local STATUS_SYMBOL_ALIASES = ctx.STATUS_SYMBOL_ALIASES
    local STATUS_ANCHOR_VALUES = ctx.STATUS_ANCHOR_VALUES
    local STATUS_CORNER_ANCHOR_VALUES = ctx.STATUS_CORNER_ANCHOR_VALUES
    local STATUS_ANCHOR_ALIASES = ctx.STATUS_ANCHOR_ALIASES
    local RAID_GROUP_STYLE_VALUES = ctx.RAID_GROUP_STYLE_VALUES
    local RAID_GROUP_STYLE_ALIASES = ctx.RAID_GROUP_STYLE_ALIASES
    local STATUS_ICON_PACK_LABELS = {
        BLIZZARD = "Blizzard (Default)", CLASSIC = "Classic", MIDNIGHT = "Midnight", UXPRO = "UX Pro",
        GLOSSY_ORBS = "Glossy Orbs", DARK_EMBOSS = "Dark Emboss", GLASS_PANELS = "Glass Panels",
        NEON_OUTLINE = "Neon Outline", RING_SYMBOLS = "Ring Symbols", DOTS = "Dots", SHAPES = "Shapes",
        DIAMONDS = "Diamonds", SQUARES = "Squares",
    }
    local function StatusIconPackContract(includeDefault)
        local values, labels, seen = {}, {}, {}
        local function Add(value, label)
            value = tostring(value or "")
            if value == "" or seen[value] then return end
            seen[value] = true
            values[#values + 1] = value
            labels[value] = tostring(label or value)
        end
        local fn = _G.MSUF_GetStatusIconPackValues
        local items = type(fn) == "function" and fn(includeDefault == true) or nil
        for i = 1, #(items or {}) do
            local item = items[i]
            if type(item) == "table" then Add(item.value or item.key, item.text or item.label) end
        end
        if #values == 0 then
            if includeDefault then Add("DEFAULT", "Follow global style") end
            for i = 1, #STATUS_ICON_PACK_FALLBACK_VALUES do
                local value = STATUS_ICON_PACK_FALLBACK_VALUES[i]
                Add(value, STATUS_ICON_PACK_LABELS[value] or value)
            end
        end
        return values, labels
    end
    local statusPackValues, statusPackLabels = StatusIconPackContract(false)
    local function IsRoleStatusSpec(spec)
        local value = spec and spec.value
        return value == "leader" or value == "assist"
    end
    local function StatusIconStyleLabel(spec)
        return tostring(spec and spec.label or "Status Indicator") .. (IsRoleStatusSpec(spec) and " Role Icon Style" or " Indicator Icon Set")
    end
    local function StatusAliasRoots(spec)
        local roots, seen = {}, {}
        for i = 1, #(spec and spec.aliases or {}) do
            local root = tostring(spec.aliases[i] or "")
            root = root:gsub("%s+icons?$", ""):gsub("%s+indicators?$", ""):gsub("%s+symbols?$", "")
            root = root:gsub("^%s+", ""):gsub("%s+$", "")
            if root ~= "" and not seen[root] then
                seen[root] = true
                roots[#roots + 1] = root
            end
        end
        return roots
    end
    local function CanonicalStatusAliases(spec, suffixes, includeOriginal)
        local out, seen = {}, {}
        local function add(value)
            value = tostring(value or ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
            if value ~= "" and not seen[value] and #out < 16 then
                seen[value] = true
                out[#out + 1] = value
            end
        end
        local roots = StatusAliasRoots(spec)
        for i = 1, #roots do
            for j = 1, #(suffixes or {}) do add(roots[i] .. " " .. suffixes[j]) end
        end
        if includeOriginal then
            for i = 1, #(spec and spec.aliases or {}) do
                for j = 1, #(suffixes or {}) do add(tostring(spec.aliases[i]) .. " " .. suffixes[j]) end
            end
        end
        return out
    end

    local raidGroupSpec
    for s = 1, #STATUS_CONTROL_SPECS do
        local spec = STATUS_CONTROL_SPECS[s]
        if spec.value == "raidgroupname" then raidGroupSpec = spec end
        if not spec.units or spec.units[unit] == true then
            local aliases = {}
            for a = 1, #(spec.aliases or {}) do
                local alias = spec.aliases[a]
                aliases[#aliases + 1] = alias
                AddAliasesForUnit(aliases, unit, alias)
            end
            RegisterUnitBooleanSetting(unit, spec.show, spec.show, spec.label, spec.defaultShow, aliases, StatusIconOpts(spec, {
                reason = "MSUF_ASSISTANT_STATUS_" .. spec.value,
                text = true,
                description = spec.description or ("Status icon visibility for " .. spec.label .. "."),
            }))

            if type(spec.iconStyle) == "string" and spec.iconStyle ~= "" then
                -- Keep the natural, value-bearing phrase before unit
                -- permutations. Registry aliases are intentionally bounded;
                -- filling the list with "leader icon icon style" variants
                -- used to discard every useful "icon pack" prefix.
                aliases = CanonicalStatusAliases(spec, {
                    "icon pack", "icon style", "icon design", "indicator style", "role icon style",
                })
                -- Status icon packs are extensible at runtime through
                -- MSUF_RegisterStatusIconPack. A closed enum would reject a
                -- valid SharedMedia/custom pack that was registered after
                -- this file loaded, so retain a string setting and let the
                -- specialized parser normalize the built-in aliases.
                RegisterUnitString(unit, spec.iconStyle, spec.iconStyle, StatusIconStyleLabel(spec),
                    spec.defaultIconStyle or "BLIZZARD", aliases, StatusIconOpts(spec, {
                        values = statusPackValues,
                        valueLabels = statusPackLabels,
                        valueAliases = { default = "BLIZZARD", blizzard = "BLIZZARD", ["blizzard default"] = "BLIZZARD" },
                        closedValues = true,
                        refreshValues = function() return StatusIconPackContract(false) end,
                        description = "Icon pack for this status indicator. Built-ins include "
                            .. table.concat(STATUS_ICON_PACK_FALLBACK_VALUES, ", ")
                            .. "; registered extension pack keys are accepted too.",
                    }))
            end

            if type(spec.customIcon) == "string" and spec.customIcon ~= "" then
                aliases = CanonicalStatusAliases(spec, {
                    "custom icon", "specific icon", "icon asset", "override icon",
                }, true)
                RegisterUnitString(unit, spec.customIcon, spec.customIcon, spec.label .. " Custom Icon", "", aliases,
                    StatusIconOpts(spec, { keySuffix = spec.customIcon }))
            end

            if spec.symbol then
                aliases = {}
                for a = 1, #(spec.aliases or {}) do
                    local base = spec.aliases[a]
                    local alias = tostring(base):find("symbol", 1, true) and base or (tostring(base) .. " symbol")
                    aliases[#aliases + 1] = alias
                    AddAliasesForUnit(aliases, unit, alias)
                end
                RegisterUnitEnum(unit, spec.symbol, spec.symbol, spec.label .. " Symbol", "DEFAULT", spec.symbolValues or { "DEFAULT" }, aliases, StatusIconOpts(spec, {
                    valueAliases = STATUS_SYMBOL_ALIASES,
                }))
            end

            aliases = {}
            for a = 1, #(spec.aliases or {}) do
                local alias = spec.aliases[a] .. " size"
                aliases[#aliases + 1] = alias
                AddAliasesForUnit(aliases, unit, alias)
            end
            RegisterUnitNumberSetting(unit, spec.value .. "Size", spec.size, spec.label .. " Size", spec.defaultSize, 8, 64, aliases, StatusIconOpts(spec, {
                keySuffix = spec.size,
                get = function(unitKey) return tonumber(UnitDB(unitKey)[spec.size]) or tonumber(GeneralDB()[spec.size]) or spec.defaultSize end,
            }))

            aliases = {}
            for a = 1, #(spec.aliases or {}) do
                local alias = spec.aliases[a] .. " anchor"
                aliases[#aliases + 1] = alias
                AddAliasesForUnit(aliases, unit, alias)
            end
            RegisterUnitEnum(unit, spec.value .. "Anchor", spec.anchor, spec.label .. " Anchor", spec.defaultAnchor, spec.nameAnchors and STATUS_ANCHOR_VALUES or STATUS_CORNER_ANCHOR_VALUES, aliases, StatusIconOpts(spec, {
                keySuffix = spec.anchor,
                valueAliases = STATUS_ANCHOR_ALIASES,
                get = function(unitKey)
                    local value = UnitDB(unitKey)[spec.anchor] or GeneralDB()[spec.anchor]
                    local allowed = AllowedMap(spec.nameAnchors and STATUS_ANCHOR_VALUES or STATUS_CORNER_ANCHOR_VALUES)
                    return allowed[value] and value or spec.defaultAnchor
                end,
            }))

            aliases = {}
            for a = 1, #(spec.aliases or {}) do
                local alias = spec.aliases[a] .. " x offset"
                aliases[#aliases + 1] = alias
                AddAliasesForUnit(aliases, unit, alias)
            end
            RegisterUnitNumberSetting(unit, spec.value .. "OffsetX", spec.x, spec.label .. " X Offset", spec.defaultX, -1000, 1000, aliases, StatusIconOpts(spec, {
                keySuffix = spec.x,
            }))

            aliases = {}
            for a = 1, #(spec.aliases or {}) do
                local alias = spec.aliases[a] .. " y offset"
                aliases[#aliases + 1] = alias
                AddAliasesForUnit(aliases, unit, alias)
            end
            RegisterUnitNumberSetting(unit, spec.value .. "OffsetY", spec.y, spec.label .. " Y Offset", spec.defaultY, -1000, 1000, aliases, StatusIconOpts(spec, {
                keySuffix = spec.y,
            }))

            aliases = {}
            for a = 1, #(spec.aliases or {}) do
                local alias = spec.aliases[a] .. " layer"
                aliases[#aliases + 1] = alias
                AddAliasesForUnit(aliases, unit, alias)
                alias = spec.aliases[a] .. " strata"
                aliases[#aliases + 1] = alias
                AddAliasesForUnit(aliases, unit, alias)
            end
            RegisterUnitNumberSetting(unit, spec.value .. "Layer", spec.layer, spec.label .. " Layer", spec.defaultLayer, 0, 30, aliases, StatusIconOpts(spec, {
                keySuffix = spec.layer,
                get = function(unitKey)
                    local conf, general = UnitDB(unitKey), GeneralDB()
                    return tonumber(conf[spec.layer])
                        or (spec.legacyLayer and tonumber(conf[spec.legacyLayer]))
                        or tonumber(general[spec.layer])
                        or (spec.legacyLayer and tonumber(general[spec.legacyLayer]))
                        or spec.defaultLayer
                end,
            }))

            if spec.value == "raidgroupname" then
                aliases = MakeAliases(unit, "raid group style", "raid group name style", "group number style")
                RegisterUnitEnum(unit, "raidGroupNameStyle", "raidGroupNameStyle", "Raid Group Name Style", "PAREN", RAID_GROUP_STYLE_VALUES, aliases, StatusIconOpts(spec, {
                    valueAliases = RAID_GROUP_STYLE_ALIASES,
                }))
            end
        end
    end

    -- Menu2 builds the shared status-placement surface for every unit page,
    -- including the hidden raid-group style dropdown. Keep its declared
    -- setting key typed even on Boss/Pet so the catalog never falls back to an
    -- unconstrained generated string owner.
    if raidGroupSpec and raidGroupSpec.units and raidGroupSpec.units[unit] ~= true then
        local aliases = MakeAliases(unit, "raid group style", "raid group name style", "group number style")
        RegisterUnitEnum(unit, "raidGroupNameStyle", "raidGroupNameStyle", "Raid Group Name Style",
            "PAREN", RAID_GROUP_STYLE_VALUES, aliases, StatusIconOpts(raidGroupSpec, {
                valueAliases = RAID_GROUP_STYLE_ALIASES,
                description = "Typed backing value for the shared status-placement surface on this unit page.",
            }))
    end

    RegisterUnitBooleanSetting(unit, "stateIconsTestMode", "stateIconsTestMode", "Status Icon Test Mode", false, MakeAliases(unit,
        "status icon test mode",
        "status icons test mode",
        "test status icons",
        "test status icon",
        "status icon preview mode",
        "status icons preview mode",
        "status preview mode",
        "status indicator test mode",
        "test status indicators"
    ), {
        category = "Status Icons",
        get = function(unitKey)
            local value = UnitDB(unitKey).stateIconsTestMode
            if value == nil then value = GeneralDB().stateIconsTestMode end
            return value == true
        end,
        refresh = "MSUF_RequestStatusIconsRefreshForCurrent",
        applyOpts = { preview = true, text = true },
        applyWhenUnchanged = true,
    })

    A.UnitframesRegistry.RegisterStatusTextColorSettings(ctx, unit)
end

-- Beta 44 gave each status indicator its own text colour. They are stored on
-- the unit as <colorPrefix>Color{R,G,B} (the colorPrefix values come straight
-- from the menu's status specs), and the override is opt-in: an incomplete
-- triple means "keep following the frame's font colour", which is why the
-- getter falls back to white rather than inventing a stored value.
local STATUS_TEXT_COLOR_SPECS = {
    { prefix = "levelIndicator",     label = "Level Text Color",      nouns = { "level text color", "level color", "level indicator color" } },
    { prefix = "raceIndicator",      label = "Race Text Color",       nouns = { "race text color", "race color", "race indicator color" } },
    { prefix = "classTextIndicator", label = "Class Text Color",      nouns = { "class text color", "class indicator color" } },
    { prefix = "raidGroupName",      label = "Raid Group Text Color", nouns = { "raid group text color", "raid group name color", "group number color" } },
    { prefix = "statusText",         label = "Dead Text Color",       nouns = { "dead text color", "dead color", "death text color" } },
    { prefix = "statusGhostText",    label = "Ghost Text Color",      nouns = { "ghost text color", "ghost color" } },
    { prefix = "statusAFKText",      label = "AFK Text Color",        nouns = { "afk text color", "afk color", "away text color" } },
    { prefix = "statusAFKTimer",     label = "AFK Timer Color",       nouns = { "afk timer color", "afk duration color", "afk time color" } },
    { prefix = "statusDNDText",      label = "DND Text Color",        nouns = { "dnd text color", "dnd color", "do not disturb text color" } },
}

function A.UnitframesRegistry.RegisterStatusTextColorSettings(ctx, unit)
    if type(ctx) ~= "table" or type(unit) ~= "string" then return end

    -- The status loop's ctx carries the unit helpers but not the Registry or
    -- the apply hook, so take those from the module namespace rather than
    -- refusing to register.
    local Registry = ctx.Registry or A.Registry
    local UnitDB = ctx.UnitDB
    local ApplyUnit = ctx.ApplyUnit
    local AddAliasesForUnit = ctx.AddAliasesForUnit

    if not (Registry and type(Registry.RegisterSetting) == "function") then return end
    if type(UnitDB) ~= "function" or type(AddAliasesForUnit) ~= "function" then return end

    local UNIT_LABELS = ctx.UNIT_LABELS or {}
    local unitLabel = UNIT_LABELS[unit] or unit

    local function Clamp01(value)
        value = tonumber(value)
        if value == nil then return nil end
        if value < 0 then return 0 end
        if value > 1 then return 1 end
        return value
    end

    for _, spec in ipairs(STATUS_TEXT_COLOR_SPECS) do
        local prefix = spec.prefix
        local aliases = {}
        for _, noun in ipairs(spec.nouns) do
            aliases[#aliases + 1] = unit .. " " .. noun
            AddAliasesForUnit(aliases, unit, noun)
        end

        Registry:RegisterSetting({
            key = unit .. "." .. prefix .. "Color",
            label = tostring(unitLabel) .. " " .. spec.label,
            category = tostring(unitLabel) .. " / Status Text Colors",
            page = "opt_colors",
            unit = unit,
            frameType = "unitframe",
            attribute = "statusTextColor",
            type = "color",
            aliases = aliases,
            exactAliases = aliases,
            get = function()
                local conf = UnitDB(unit)
                local r = Clamp01(conf and conf[prefix .. "ColorR"])
                local g = Clamp01(conf and conf[prefix .. "ColorG"])
                local b = Clamp01(conf and conf[prefix .. "ColorB"])
                if r and g and b then return { r = r, g = g, b = b } end
                return { r = 1, g = 1, b = 1 }
            end,
            set = function(value)
                local conf = UnitDB(unit)
                if type(conf) ~= "table" or type(value) ~= "table" then return end
                conf[prefix .. "ColorR"] = Clamp01(value.r) or 1
                conf[prefix .. "ColorG"] = Clamp01(value.g) or 1
                conf[prefix .. "ColorB"] = Clamp01(value.b) or 1
            end,
            apply = function()
                if type(ApplyUnit) == "function" then
                    ApplyUnit(unit, "MSUF_ASSISTANT_STATUS_TEXT_COLOR", { preview = true, text = true })
                    return
                end
                local refresh = _G.MSUF_RequestStatusIconsRefreshForCurrent
                if type(refresh) == "function" then refresh() end
            end,
            combatSafe = false,
        })
    end
end
