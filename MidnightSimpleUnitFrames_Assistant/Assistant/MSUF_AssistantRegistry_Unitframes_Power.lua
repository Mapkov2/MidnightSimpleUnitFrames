-- Assistant UnitFrame power bar setting registry.
-- Keeps power and detached-power controls outside the main UnitFrame registry loop.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.UnitframesRegistry = A.UnitframesRegistry or {}

local POWER_UNITS = { player = true, target = true, focus = true, targettarget = true, focustarget = true, pet = true, boss = true }

local function UnitDefaultPowerBar(unit)
    return not (unit == "targettarget" or unit == "focustarget")
end

local UnitframesRegistry = A.UnitframesRegistry
local AddDetachedPowerVerbAliases = UnitframesRegistry.AddDetachedPowerVerbAliases
local DetachedPowerMoveAliases = UnitframesRegistry.DetachedPowerMoveAliases
local DetachedPowerMoveGuard = UnitframesRegistry.DetachedPowerMoveGuard
local InitDetachedPowerBar = UnitframesRegistry.InitDetachedPowerBar

-- The shared texture-name normalizer lives in the Global Bars data module,
-- which loads long after this registry runs. Resolving it at call time keeps
-- the per-unit power textures on the same alias table as every other texture
-- setting without forcing a load-order change.
local function NormalizeTextureKeyForAssistant(value)
    local Data = A.GlobalBarRegistry and A.GlobalBarRegistry.Data
    local normalize = Data and Data.NormalizeTextureKeyForAssistant
    if type(normalize) == "function" then return normalize(value) end
    return value
end

local function AppendAliases(aliases, ...)
    if type(aliases) ~= "table" then return aliases end
    for i = 1, select("#", ...) do
        local alias = select(i, ...)
        if type(alias) == "string" and alias ~= "" then
            aliases[#aliases + 1] = alias
        end
    end
    return aliases
end

function A.UnitframesRegistry.RegisterPowerSettings(ctx, unit)
    if type(ctx) ~= "table" or type(unit) ~= "string" or not POWER_UNITS[unit] then return end

    local UnitDB = ctx.UnitDB
    local BarsDB = ctx.BarsDB
    local MakeAliases = ctx.MakeAliases
    local RegisterUnitBooleanSetting = ctx.RegisterUnitBooleanSetting
    local RegisterUnitNumberSetting = ctx.RegisterUnitNumberSetting
    local RegisterUnitEnum = ctx.RegisterUnitEnum
    local RegisterUnitString = ctx.RegisterUnitString
    local DETACHED_POWER_SHAPE_VALUES = ctx.DETACHED_POWER_SHAPE_VALUES or {}
    local DETACHED_POWER_SHAPE_ALIASES = ctx.DETACHED_POWER_SHAPE_ALIASES or {}

    if type(UnitDB) ~= "function" or type(BarsDB) ~= "function" or type(MakeAliases) ~= "function" then return end
    if type(RegisterUnitBooleanSetting) ~= "function" or type(RegisterUnitNumberSetting) ~= "function" then return end
    if type(RegisterUnitEnum) ~= "function" then return end
    if type(AddDetachedPowerVerbAliases) ~= "function" or type(DetachedPowerMoveAliases) ~= "function" then return end
    if type(DetachedPowerMoveGuard) ~= "function" or type(InitDetachedPowerBar) ~= "function" then return end

    RegisterUnitBooleanSetting(unit, "powerBar", "showPowerBar", "Power Bar", UnitDefaultPowerBar(unit),
        MakeAliases(unit, "power bar", "show power bar"), { category = "Power Bar", power = true })
    -- Per-unit override of the shared bars power art, applying whether the bar
    -- is detached or not. Empty means "follow the shared texture", which is the
    -- menu's "Use global power texture" entry -- so an empty value is a real
    -- choice here and must not be normalized into a texture name.
    if type(RegisterUnitString) == "function" then
        RegisterUnitString(unit, "texture", "powerBarTexture", "Power Texture", "",
            MakeAliases(unit, "power texture", "power bar texture", "power bar foreground texture", "mana bar texture"), {
            category = "Power Bar",
            power = true,
            mediaType = "statusbar",
            normalizeValue = NormalizeTextureKeyForAssistant,
            description = "Art for this frame's power bar. Leave empty to follow the shared Bars power texture.",
        })
        RegisterUnitString(unit, "backgroundTexture", "powerBarBgTexture", "Power Background Texture", "",
            MakeAliases(unit, "power background texture", "power bar background texture", "power bar bg texture"), {
            category = "Power Bar",
            power = true,
            mediaType = "statusbar",
            normalizeValue = NormalizeTextureKeyForAssistant,
            description = "Background art behind this frame's power bar. Leave empty to follow the shared Bars power background.",
        })
    end
    RegisterUnitBooleanSetting(unit, "powerBarBorder", "powerBarBorderEnabled", "Power Bar Border", false, MakeAliases(unit, "power bar border", "power border"), {
        category = "Power Bar",
        power = true,
        get = function(unitKey)
            local conf = UnitDB(unitKey)
            if unitKey == "player" and conf.powerBarDetached == true then
                local outline = tonumber(BarsDB().detachedPowerBarOutline)
                if outline ~= nil then return outline > 0 end
            end
            if conf.powerBarBorderEnabled ~= nil then return conf.powerBarBorderEnabled == true end
            return BarsDB().powerBarBorderEnabled == true
        end,
        set = function(unitKey, value)
            local conf = UnitDB(unitKey)
            conf.powerBarBorderEnabled = value == true
            if unitKey == "player" then
                local thickness = tonumber(conf.powerBarBorderThickness) or 1
                BarsDB().detachedPowerBarOutline = value == true and thickness or 0
            end
        end,
    })
    RegisterUnitNumberSetting(unit, "powerBarHeight", "powerBarHeight", "Power Bar Height", 3, 1, 20, MakeAliases(unit, "power bar height", "power height"), {
        category = "Power Bar",
        power = true,
        get = function(unitKey) return tonumber(UnitDB(unitKey).powerBarHeight) or tonumber(BarsDB().powerBarHeight) or 3 end,
    })
    RegisterUnitNumberSetting(unit, "powerBarBorderThickness", "powerBarBorderThickness",
        "Power Bar Border Thickness", 1, 0, unit == "player" and 8 or 6,
        MakeAliases(unit, "power bar border thickness", "power border size"), {
        category = "Power Bar",
        power = true,
        get = function(unitKey)
            local conf = UnitDB(unitKey)
            if unitKey == "player" and conf.powerBarDetached == true then
                local outline = tonumber(BarsDB().detachedPowerBarOutline)
                if outline ~= nil then return outline end
            end
            return tonumber(conf.powerBarBorderThickness) or tonumber(BarsDB().powerBarBorderThickness or BarsDB().powerBarBorderSize) or 1
        end,
        set = function(unitKey, value)
            local conf = UnitDB(unitKey)
            conf.powerBarBorderThickness = value
            if unitKey == "player" then
                BarsDB().detachedPowerBarOutline = conf.powerBarBorderEnabled == true and value or 0
            end
        end,
    })
    RegisterUnitBooleanSetting(unit, "embedPowerBarIntoHealth", "embedPowerBarIntoHealth",
        "Embed Power Bar into Health", false,
        MakeAliases(unit, "embed power bar", "embed power into health", "power bar embedded"), {
        category = "Power Bar",
        power = true,
        get = function(unitKey)
            local conf = UnitDB(unitKey)
            if conf.embedPowerBarIntoHealth ~= nil then return conf.embedPowerBarIntoHealth == true end
            return BarsDB().embedPowerBarIntoHealth == true
        end,
    })
    RegisterUnitBooleanSetting(unit, "powerSmoothFill", "powerSmoothFill", "Power Bar Smooth Fill",
        false,
        MakeAliases(unit, "power smooth fill", "smooth power bar"), { category = "Power Bar", power = true })

    local detachedPowerAliases = MakeAliases(unit, "detached power bar", "detach power bar", "power bar detached")
    AddDetachedPowerVerbAliases(detachedPowerAliases, unit, { "detach", "undock", "attach", "dock" }, "power bar")
    AddDetachedPowerVerbAliases(detachedPowerAliases, unit, { "abkoppeln", "ankoppeln" }, "power balken")
    RegisterUnitBooleanSetting(unit, "powerBarDetached", "powerBarDetached", "Detach Power Bar from Frame", false, detachedPowerAliases, {
        category = "Power Bar",
        power = true,
        set = function(unitKey, value)
            UnitDB(unitKey).powerBarDetached = value and true or false
            if value then InitDetachedPowerBar(ctx, unitKey) end
        end,
    })
    local detachedTextOnBarAliases = MakeAliases(unit, "text on detached power bar", "detached power text on bar")
    if unit == "player" then
        AppendAliases(detachedTextOnBarAliases,
            "class resources player power text on bar", "class resources player power bar text on bar",
            "class resource player power text on bar", "player power text on class resources bar"
        )
    end
    RegisterUnitBooleanSetting(unit, "detachedPowerBarTextOnBar", "detachedPowerBarTextOnBar",
        "Text on Detached Power Bar", false,
        detachedTextOnBarAliases,
        { category = "Power Bar", power = true, text = true })

    if unit == "player" then
        local syncClassPowerAliases = MakeAliases(unit, "detached power sync class resource", "sync power bar to class resource")
        AppendAliases(syncClassPowerAliases,
            "class resources player power sync", "class resources player power sync width",
            "class resources player power bar sync", "class resources player power bar sync width",
            "class resource player power sync width", "class power player power sync width",
            "sync class resources player power", "sync class resources player power width",
            "sync class resources player power bar", "sync class resources player power bar width",
            "player power sync class resource width", "player power bar sync class resource width"
        )
        RegisterUnitBooleanSetting(unit, "detachedPowerBarSyncClassPower", "detachedPowerBarSyncClassPower",
            "Detached Power Bar Syncs to Class Resource Width", true,
            syncClassPowerAliases, {
            category = "Power Bar",
            power = true,
            get = function(unitKey) return UnitDB(unitKey).detachedPowerBarSyncClassPower ~= false end,
        })
        local anchorClassPowerAliases = MakeAliases(unit, "anchor detached power to class resource", "detached power anchor class resource")
        AppendAliases(anchorClassPowerAliases,
            "class resources player power anchor", "class resources player power bar anchor",
            "class resource player power anchor", "class power player power anchor",
            "anchor class resources player power to class resource",
            "anchor class resources player power bar to class resource",
            "anchor class resource player power to class resource",
            "anchor player power bar to class resource",
            "class resources player power to class resource",
            "class resources player power bar to class resource",
            "player power bar to class resource"
        )
        RegisterUnitBooleanSetting(unit, "detachedPowerBarAnchorToClassPower", "detachedPowerBarAnchorToClassPower",
            "Detached Power Bar Anchors to Class Resource", false,
            anchorClassPowerAliases,
            { category = "Power Bar", power = true })
        local shapeAliases = MakeAliases(unit,
            "player power shape", "detached power shape", "detached power bar shape", "player detached power shape",
            "follow class resource shape", "power bar shape", "mana orb", "power orb", "mana ball", "power ball", "power sphere"
        )
        AppendAliases(shapeAliases,
            "class resources player power shape", "class resources player power bar shape",
            "class resource player power shape", "class power player power shape"
        )
        RegisterUnitEnum(unit, "detachedPowerBarShape", "detachedPowerBarShape", "Detached Power Bar Shape", "BAR", DETACHED_POWER_SHAPE_VALUES, shapeAliases, {
            category = "Power Bar",
            power = true,
            page = "classpower",
            valueAliases = DETACHED_POWER_SHAPE_ALIASES,
            -- FOLLOW_CLASS is an instruction, not a stored state: the setter
            -- resolves it to the class resource's own shape (ROUND/CRYSTAL/BAR)
            -- and that concrete shape is what gets stored, so the value read
            -- back is never FOLLOW_CLASS. Without this the transaction called
            -- that a failed write and rolled it back, leaving the shape
            -- impossible to set from the class resource.
            normalizesValue = true,
            get = function(unitKey)
                local conf = UnitDB(unitKey)
                local value = tostring(conf.detachedPowerBarShape or "BAR"):upper()
                if value == "BAR" or value == "ROUND" or value == "CRYSTAL" or value == "ORB" then return value end
                return "BAR"
            end,
            set = function(unitKey, value)
                local conf = UnitDB(unitKey)
                value = tostring(value or "BAR"):upper()
                if value == "FOLLOW_CLASS" then
                    local classShape = tostring(BarsDB().classPowerShape or "BAR"):upper()
                    conf.detachedPowerBarShape = classShape == "CIRCLE" and "ROUND"
                        or ((classShape == "DIAMOND" or classShape == "HEX") and "CRYSTAL" or "BAR")
                    return
                end
                conf.detachedPowerBarShape = value
            end,
        })
        local orbSizeAliases = MakeAliases(unit,
            "mana orb size", "power orb size", "detached power orb size", "orb size", "mana ball size", "power ball size"
        )
        AppendAliases(orbSizeAliases,
            "class resources player power orb size", "class resources player power bar orb size",
            "class resource player power orb size", "class power player power orb size"
        )
        RegisterUnitNumberSetting(unit, "detachedPowerOrbSize", "detachedPowerOrbSize", "Detached Power Orb Size", 54, 20, 160, orbSizeAliases, {
            category = "Power Bar",
            power = true,
            get = function(unitKey) return tonumber(UnitDB(unitKey).detachedPowerOrbSize) or 54 end,
        })
    end

    local detachedPowerXAliases = MakeAliases(unit, "detached power x", "detached power bar x offset")
    if unit == "player" then
        AppendAliases(detachedPowerXAliases,
            "class resources player power x", "class resources player power x offset",
            "class resources player power bar x", "class resources player power bar x offset",
            "class resource player power x", "player power x in class resources"
        )
    end
    RegisterUnitNumberSetting(unit, "detachedPowerBarOffsetX", "detachedPowerBarOffsetX",
        "Detached Power Bar X Offset", 0, -1000, 1000,
        detachedPowerXAliases, {
        category = "Power Bar",
        power = true,
        exactAliases = DetachedPowerMoveAliases(unit, "x"),
        moveAxis = "x",
        moveStep = 10,
        intentGuard = DetachedPowerMoveGuard(ctx, unit),
    })
    local detachedPowerYAliases = MakeAliases(unit, "detached power y", "detached power bar y offset")
    if unit == "player" then
        AppendAliases(detachedPowerYAliases,
            "class resources player power y", "class resources player power y offset",
            "class resources player power bar y", "class resources player power bar y offset",
            "class resource player power y", "player power y in class resources"
        )
    end
    RegisterUnitNumberSetting(unit, "detachedPowerBarOffsetY", "detachedPowerBarOffsetY",
        "Detached Power Bar Y Offset", -4, -1000, 1000,
        detachedPowerYAliases, {
        category = "Power Bar",
        power = true,
        exactAliases = DetachedPowerMoveAliases(unit, "y"),
        moveAxis = "y",
        moveStep = 10,
        intentGuard = DetachedPowerMoveGuard(ctx, unit),
    })
    local detachedPowerWidthAliases = MakeAliases(unit, "detached power width", "detached power bar width")
    if unit == "player" then
        AppendAliases(detachedPowerWidthAliases,
            "class resources player power width", "class resources player power bar width",
            "class resource player power width", "class resource player power bar width",
            "class power player power width", "class power player power bar width",
            "player power width in class resources", "player power bar width in class resources"
        )
    end
    RegisterUnitNumberSetting(unit, "detachedPowerBarWidth", "detachedPowerBarWidth",
        "Detached Power Bar Width", unit == "focus" and 180 or 275, 20, 800,
        detachedPowerWidthAliases, {
        category = "Power Bar",
        power = true,
        get = function(unitKey) return tonumber(UnitDB(unitKey).detachedPowerBarWidth) or tonumber(UnitDB(unitKey).width) or (unitKey == "focus" and 180 or 275) end,
    })
    local detachedPowerHeightAliases = MakeAliases(unit, "detached power height", "detached power bar height")
    if unit == "player" then
        AppendAliases(detachedPowerHeightAliases,
            "class resources player power height", "class resources player power bar height",
            "class resource player power height", "class power player power height",
            "player power height in class resources", "player power bar height in class resources"
        )
    end
    RegisterUnitNumberSetting(unit, "detachedPowerBarHeight", "detachedPowerBarHeight",
        "Detached Power Bar Height", 6, 2, 80,
        detachedPowerHeightAliases,
        { category = "Power Bar", power = true })
    local detachedPowerLayerAliases = MakeAliases(unit, "detached power layer", "detached power bar frame level")
    if unit == "player" then
        AppendAliases(detachedPowerLayerAliases,
            "class resources player power layer", "class resources player power bar layer",
            "class resources player power frame level", "class resources player power bar frame level",
            "class resource player power layer", "class power player power layer",
            "player power layer in class resources", "player power bar layer in class resources"
        )
    end
    RegisterUnitNumberSetting(unit, "detachedPowerBarFrameLevelOffset", "detachedPowerBarFrameLevelOffset",
        "Detached Power Bar Layer", 6, 0, 30,
        detachedPowerLayerAliases,
        { category = "Power Bar", power = true })
end
