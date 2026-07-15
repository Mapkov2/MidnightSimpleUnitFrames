-- Assistant GroupFrames corner indicator setting registry.
-- Loaded before MSUF_AssistantRegistry_GroupFramesSpellIndicators.lua; the main registry passes helper context in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GroupFramesRegistry = A.GroupFramesRegistry or {}

function A.GroupFramesRegistry.RegisterCornerIndicatorSettings(ctx)
    if type(ctx) ~= "table" then return end

    local SCOPES = ctx.SCOPES or {}
    local CI_CATEGORY_VALUES = ctx.CI_CATEGORY_VALUES or {}
    local CI_MODE_VALUES = ctx.CI_MODE_VALUES or {}
    local CI_FILTER_VALUES = ctx.CI_FILTER_VALUES or {}
    local CI_CATEGORY_ALIASES = ctx.CI_CATEGORY_ALIASES or {}
    local CI_MODE_ALIASES = ctx.CI_MODE_ALIASES or {}
    local CI_FILTER_ALIASES = ctx.CI_FILTER_ALIASES or {}
    local CI_SLOTS = ctx.CI_SLOTS or {}
    local AddAliasesForUnit = ctx.AddAliasesForUnit
    local AddSlotAliases = ctx.AddSlotAliases
    local GroupDB = ctx.GroupDB
    local ClampNumber = ctx.ClampNumber
    local Clamp01 = ctx.Clamp01
    local ColorSame = ctx.ColorSame
    local CustomConfig = ctx.CustomConfig
    local ActivateCustom = ctx.ActivateCustom
    local RegisterGroupNested = ctx.RegisterGroupNested

    if type(AddAliasesForUnit) ~= "function" or type(AddSlotAliases) ~= "function" then return end
    if type(GroupDB) ~= "function" or type(ClampNumber) ~= "function" or type(Clamp01) ~= "function" then return end
    if type(ColorSame) ~= "function" or type(CustomConfig) ~= "function" or type(ActivateCustom) ~= "function" then return end
    if type(RegisterGroupNested) ~= "function" then return end

    for _, scope in ipairs(SCOPES) do
        local aliases = {}
        AddAliasesForUnit(aliases, scope, "corner indicators", "ecken indikatoren")
        AddAliasesForUnit(aliases, scope, "corner indicator", "ecken indikator")
        AddAliasesForUnit(aliases, scope, "corner dots", "ecken punkte")
        RegisterGroupNested(scope, "ciEnabled", "cornerIndicators", "Corner Indicators", "boolean", aliases, {
            get = function()
                local value = GroupDB(scope).ciEnabled
                if value == nil then return false end
                return value and true or false
            end,
            set = function(value) GroupDB(scope).ciEnabled = value and true or false end,
        })

        aliases = {}
        AddAliasesForUnit(aliases, scope, "corner indicator size", "ecken indikator groesse")
        AddAliasesForUnit(aliases, scope, "corner dot size", "ecken punkt groesse")
        RegisterGroupNested(scope, "ciSize", "cornerIndicatorSize", "Corner Indicator Size", "number", aliases, {
            min = 4, max = 24, step = 1,
            get = function() return tonumber(GroupDB(scope).ciSize) or 8 end,
            set = function(value) GroupDB(scope).ciSize = ClampNumber(value, 4, 24, 1) end,
        })

        aliases = {}
        AddAliasesForUnit(aliases, scope, "corner indicator layer", "ecken indikator ebene")
        AddAliasesForUnit(aliases, scope, "corner indicators layer", "ecken indikatoren ebene")
        AddAliasesForUnit(aliases, scope, "corner dot layer", "ecken punkt ebene")
        AddAliasesForUnit(aliases, scope, "corner indicator draw layer", "ecken indikator zeichnungsebene")
        AddAliasesForUnit(aliases, scope, "corner indicator strata", "ecken indikator strata")
        AddAliasesForUnit(aliases, scope, "corner indicator frame strata", "ecken indikator frame strata")
        RegisterGroupNested(scope, "ciLayer", "cornerIndicatorLayer", "Corner Indicator Layer", "number", aliases, {
            min = 0, max = 30, step = 1,
            get = function() return tonumber(GroupDB(scope).ciLayer) or 7 end,
            set = function(value) GroupDB(scope).ciLayer = ClampNumber(value, 0, 30, 1) end,
        })

        aliases = {}
        AddAliasesForUnit(aliases, scope, "corner indicator alpha", "ecken indikator alpha")
        AddAliasesForUnit(aliases, scope, "corner indicator opacity", "ecken indikator deckkraft")
        AddAliasesForUnit(aliases, scope, "corner dot opacity", "ecken punkt deckkraft")
        RegisterGroupNested(scope, "ciAlpha", "cornerIndicatorAlpha", "Corner Indicator Opacity", "number", aliases, {
            min = 0.1, max = 1, step = 0.05, percent = true,
            get = function() return tonumber(GroupDB(scope).ciAlpha) or 1 end,
            set = function(value) GroupDB(scope).ciAlpha = ClampNumber(value, 0.1, 1, 0.05) end,
        })

        for _, slot in ipairs(CI_SLOTS) do
            local slotKey, slotLabel, slotDefault = slot.key, slot.label, slot.default
            aliases = {}
            AddSlotAliases(aliases, scope, slot)
            AddSlotAliases(aliases, scope, slot, "indicator")
            AddSlotAliases(aliases, scope, slot, "category")
            RegisterGroupNested(scope, "ciSlot" .. slotKey, "cornerIndicator" .. slotKey, slotLabel .. " Corner Indicator", "enum", aliases, {
                values = CI_CATEGORY_VALUES, valueAliases = CI_CATEGORY_ALIASES,
                get = function() return GroupDB(scope)["ciSlot" .. slotKey] or slotDefault end,
                set = function(value) GroupDB(scope)["ciSlot" .. slotKey] = value or "none" end,
            })

            aliases = {}
            AddSlotAliases(aliases, scope, slot, "custom spells")
            AddSlotAliases(aliases, scope, slot, "custom spell ids")
            AddSlotAliases(aliases, scope, slot, "spell ids")
            RegisterGroupNested(scope, "ciCustom" .. slotKey .. ".spells", "cornerIndicator" .. slotKey .. "CustomSpells", slotLabel .. " Corner Custom Spells", "string", aliases, {
                get = function()
                    local cfg = CustomConfig(scope, slotKey, false)
                    return cfg and cfg.spells or ""
                end,
                set = function(value)
                    local cfg = CustomConfig(scope, slotKey, true)
                    cfg.spells = tostring(value or "")
                    ActivateCustom(scope, slotKey)
                end,
                description = "Comma-separated spell IDs for this corner custom spell slot.",
            })

            aliases = {}
            AddSlotAliases(aliases, scope, slot, "custom mode")
            AddSlotAliases(aliases, scope, slot, "custom when")
            RegisterGroupNested(scope, "ciCustom" .. slotKey .. ".mode", "cornerIndicator" .. slotKey .. "CustomMode", slotLabel .. " Corner Custom Mode", "enum", aliases, {
                values = CI_MODE_VALUES, valueAliases = CI_MODE_ALIASES,
                get = function()
                    local cfg = CustomConfig(scope, slotKey, false)
                    return cfg and cfg.mode or "present"
                end,
                set = function(value)
                    local cfg = CustomConfig(scope, slotKey, true)
                    cfg.mode = value == "missing" and "missing" or "present"
                    ActivateCustom(scope, slotKey)
                end,
            })

            aliases = {}
            AddSlotAliases(aliases, scope, slot, "custom filter")
            AddSlotAliases(aliases, scope, slot, "custom aura filter")
            RegisterGroupNested(scope, "ciCustom" .. slotKey .. ".filter", "cornerIndicator" .. slotKey .. "CustomFilter", slotLabel .. " Corner Custom Filter", "enum", aliases, {
                values = CI_FILTER_VALUES, valueAliases = CI_FILTER_ALIASES,
                get = function()
                    local cfg = CustomConfig(scope, slotKey, false)
                    return cfg and cfg.filter or "HELPFUL|PLAYER"
                end,
                set = function(value)
                    local cfg = CustomConfig(scope, slotKey, true)
                    local ok = { ["HELPFUL|PLAYER"] = true, HELPFUL = true, ["HARMFUL|PLAYER"] = true, HARMFUL = true }
                    cfg.filter = ok[value] and value or "HELPFUL|PLAYER"
                    ActivateCustom(scope, slotKey)
                end,
            })

            aliases = {}
            AddSlotAliases(aliases, scope, slot, "custom color")
            AddSlotAliases(aliases, scope, slot, "spell color")
            RegisterGroupNested(scope, "ciCustom" .. slotKey .. ".color", "cornerIndicator" .. slotKey .. "CustomColor", slotLabel .. " Corner Custom Color", "color", aliases, {
                sameValue = ColorSame,
                get = function()
                    local cfg = CustomConfig(scope, slotKey, false)
                    return { r = (cfg and tonumber(cfg.r)) or 0.40, g = (cfg and tonumber(cfg.g)) or 1.00, b = (cfg and tonumber(cfg.b)) or 0.40 }
                end,
                set = function(value)
                    local cfg = CustomConfig(scope, slotKey, true)
                    cfg.r = Clamp01(type(value) == "table" and (value.r or value[1]) or 0.40, 0.40)
                    cfg.g = Clamp01(type(value) == "table" and (value.g or value[2]) or 1.00, 1.00)
                    cfg.b = Clamp01(type(value) == "table" and (value.b or value[3]) or 0.40, 0.40)
                    ActivateCustom(scope, slotKey)
                end,
            })
        end
    end
end
