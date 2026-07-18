-- Assistant Castbars appearance/interrupt setting registry.
-- Loaded before MSUF_AssistantRegistry_Castbars.lua; the main castbar registry passes helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.CastbarsRegistry = A.CastbarsRegistry or {}

function A.CastbarsRegistry.RegisterAppearanceSettings(ctx)
    if type(ctx) ~= "table" then return end

    local Registry = ctx.Registry
    local CastbarAliases = ctx.CastbarAliases
    local RegisterCastbarBoolean = ctx.RegisterCastbarBoolean
    local RegisterCastbarNumber = ctx.RegisterCastbarNumber
    local RegisterCastbarEnum = ctx.RegisterCastbarEnum
    local RegisterCastbarString = ctx.RegisterCastbarString
    local RegisterCastbarNumericBoolean = ctx.RegisterCastbarNumericBoolean
    local ApplyCastbarTextures = ctx.ApplyCastbarTextures
    local ApplyCastbarOutline = ctx.ApplyCastbarOutline

    if type(Registry) ~= "table" or type(Registry.RegisterSetting) ~= "function" then return end
    if type(CastbarAliases) ~= "function" then return end
    if type(RegisterCastbarBoolean) ~= "function" or type(RegisterCastbarNumber) ~= "function" then return end
    if type(RegisterCastbarEnum) ~= "function" or type(RegisterCastbarString) ~= "function" then return end
    if type(RegisterCastbarNumericBoolean) ~= "function" then return end

    local function RootDB()
        local db
        if M and type(M.EnsureDB) == "function" then db = M.EnsureDB() end
        if type(db) ~= "table" then db = _G.MSUF_DB end
        if type(db) ~= "table" then error("MSUF profile database is unavailable") end
        return db
    end

    local function GeneralDB()
        local db = RootDB()
        if type(db.general) ~= "table" then db.general = {} end
        return db.general
    end

    local function PlayerCastbarDB()
        local db = RootDB()
        if type(db.player) ~= "table" then db.player = {} end
        if type(db.player.castbar) ~= "table" then db.player.castbar = {} end
        return db.player.castbar
    end

    local function IsFiniteNumber(value)
        return type(value) == "number" and value == value
            and value ~= math.huge and value ~= -math.huge
    end

    local function Copy(value, seen)
        if type(value) ~= "table" then return value end
        seen = seen or {}
        if seen[value] then return seen[value] end
        local out = {}
        seen[value] = out
        for key, child in pairs(value) do out[Copy(key, seen)] = Copy(child, seen) end
        return out
    end

    local function ApplyChannelTicks()
        local apply = _G.MSUF_UpdateCastbarChannelTicks or _G.MSUF_ApplyPlayerChannelTickMarkers
        if type(apply) == "function" then apply() end
        return true
    end

    local function ChannelTickCount()
        local count = tonumber(PlayerCastbarDB().channelTickCount)
        if not IsFiniteNumber(count) then count = 5 end
        count = math.floor(count + 0.5)
        if count < 0 then count = 0 elseif count > 10 then count = 10 end
        return count
    end

    local function FormatPosition(value)
        if value == math.floor(value) then return tostring(math.floor(value)) end
        local text = string.format("%.4f", value)
        return (text:gsub("0+$", ""):gsub("%.$", ""))
    end

    local function ParsePositions(value)
        local out = {}
        if type(value) == "table" then
            for i = 1, #value do out[i] = value[i] end
        elseif type(value) == "string" then
            local text = value:lower():gsub("%%", "")
            text = text:gsub("%s+and%s+", ","):gsub("%s+und%s+", ",")
            text = text:gsub("^%s+", ""):gsub("%s+$", "")
            if text == "" or text == "auto" or text == "default" or text == "even"
                or text == "evenly spaced" then
                return out
            end
            for token in text:gmatch("[^,;|%s]+") do
                local number = tonumber(token)
                if not IsFiniteNumber(number) then
                    error("channel tick positions must contain only finite numbers")
                end
                out[#out + 1] = number
            end
        else
            error("channel tick positions must be an ordered number list")
        end

        if #out > 10 then error("channel tick positions support at most 10 entries") end
        local expected = ChannelTickCount()
        if #out > 0 and #out ~= expected then
            error("channel tick positions require exactly " .. tostring(expected)
                .. " entries for the current tick count")
        end
        local previous
        for i = 1, #out do
            local number = out[i]
            if not IsFiniteNumber(number) then
                error("channel tick positions must contain only finite numbers")
            end
            if number < 0 or number > 100 then
                error("channel tick positions must be between 0 and 100 percent")
            end
            if previous ~= nil and number <= previous then
                error("channel tick positions must be strictly increasing")
            end
            previous = number
        end
        return out
    end

    local function PositionString()
        local stored = PlayerCastbarDB().channelTickPosPct
        if type(stored) ~= "table" or #stored == 0 then return "auto" end
        local values = {}
        for i = 1, #stored do
            local value = tonumber(stored[i])
            if not IsFiniteNumber(value) then return "auto" end
            values[#values + 1] = FormatPosition(value)
        end
        return table.concat(values, ", ")
    end

    local function CapturePositionState()
        local castbar = PlayerCastbarDB()
        local value = rawget(castbar, "channelTickPosPct")
        return { present = value ~= nil, value = Copy(value) }
    end

    local function RestorePositionState(state)
        if type(state) ~= "table" or type(state.present) ~= "boolean" then
            error("invalid channel tick position transaction state")
        end
        local castbar = PlayerCastbarDB()
        castbar.channelTickPosPct = state.present and Copy(state.value) or nil
        return true
    end

    local tickCategory = "Appearance / Cast Bars / Channel Ticks"
    Registry:RegisterSetting({
        key = "general.castbarShowChannelTicks",
        label = "Spell-Specific Channel Tick Markers",
        category = tickCategory,
        unit = "global",
        frameType = "castbar",
        page = "opt_castbar",
        attribute = "channelTicks",
        type = "boolean",
        aliases = CastbarAliases("channel ticks", "channel tick lines", "kanal ticks", "kanal tick linien"),
        dbScopes = { { scope = "general", dbKey = "castbarShowChannelTicks" } },
        dbScopesReplace = true,
        get = function() return GeneralDB().castbarShowChannelTicks == true end,
        set = function(value)
            if type(value) ~= "boolean" then error("channel tick visibility expects a boolean") end
            GeneralDB().castbarShowChannelTicks = value
        end,
        apply = ApplyChannelTicks,
        combatSafe = false,
        description = "Shows spell-specific player channel tick markers with talent and duration handling, a five-line fallback for unsupported channels, and custom-layout override support.",
    })

    Registry:RegisterSetting({
        key = "player.castbar.channelTickUseCustom",
        label = "Use Custom Channel Tick Layout",
        category = tickCategory,
        unit = "player",
        frameType = "castbar",
        page = "opt_castbar",
        attribute = "channelTickUseCustom",
        type = "boolean",
        aliases = {
            "use custom channel ticks", "custom channel tick layout", "custom channel ticks",
            "player custom channel ticks", "benutzerdefinierte kanal ticks",
        },
        dbScopes = { { scope = "player", dbKey = "castbar.channelTickUseCustom" } },
        dbScopesReplace = true,
        get = function() return PlayerCastbarDB().channelTickUseCustom == true end,
        set = function(value)
            if type(value) ~= "boolean" then error("custom channel tick layout expects a boolean") end
            PlayerCastbarDB().channelTickUseCustom = value
        end,
        apply = ApplyChannelTicks,
        combatSafe = false,
        menuControlDisposition = "standalone",
        menuControlDispositionReason = "Custom channel layout is an Assistant-owned advanced value with no current Menu2 scalar control.",
        menuControlDispositionEvidence = "MSUF_CastbarChannelTicks.lua TickConfig and MSUF_AssistantRegistry_Castbars_Appearance.lua",
        description = "Uses custom player channel tick count and positions while the global visibility gate is enabled.",
    })

    Registry:RegisterSetting({
        key = "player.castbar.channelTickCount",
        label = "Custom Channel Tick Count",
        category = tickCategory,
        unit = "player",
        frameType = "castbar",
        page = "opt_castbar",
        attribute = "channelTickCount",
        type = "number",
        aliases = {
            "custom channel tick count", "player channel tick count", "channel marker count",
            "number of custom channel ticks", "anzahl kanal ticks",
        },
        dbScopes = { { scope = "player", dbKey = "castbar.channelTickCount" } },
        dbScopesReplace = true,
        min = 0,
        max = 10,
        step = 1,
        get = ChannelTickCount,
        set = function(value)
            if not IsFiniteNumber(value) or value ~= math.floor(value) or value < 0 or value > 10 then
                error("custom channel tick count must be an integer from 0 to 10")
            end
            PlayerCastbarDB().channelTickCount = value
        end,
        apply = ApplyChannelTicks,
        combatSafe = false,
        menuControlDisposition = "standalone",
        menuControlDispositionReason = "Custom channel marker count is an Assistant-owned advanced value with no current Menu2 scalar control.",
        menuControlDispositionEvidence = "MSUF_CastbarChannelTicks.lua TickConfig and MSUF_AssistantRegistry_Castbars_Appearance.lua",
        description = "Sets the custom player channel marker count from 0 to 10.",
    })

    Registry:RegisterSetting({
        key = "player.castbar.channelTickPosPct",
        label = "Custom Channel Tick Positions",
        category = tickCategory,
        unit = "player",
        frameType = "castbar",
        page = "opt_castbar",
        attribute = "channelTickPosPct",
        type = "string",
        aliases = {
            "custom channel tick positions", "player channel tick positions", "channel tick percentages",
            "channel marker positions", "channel tick position list", "kanal tick positionen",
        },
        valuePrefixes = {
            "custom channel tick positions", "player channel tick positions", "channel tick percentages",
            "channel marker positions", "channel tick position list", "kanal tick positionen",
        },
        dbScopes = { { scope = "player", dbKey = "castbar.channelTickPosPct" } },
        dbScopesReplace = true,
        orderedList = true,
        elementType = "number",
        elementMin = 0,
        elementMax = 100,
        minCount = 0,
        maxCount = 10,
        countSettingKey = "player.castbar.channelTickCount",
        normalizesValue = true,
        get = PositionString,
        set = function(value)
            PlayerCastbarDB().channelTickPosPct = Copy(ParsePositions(value))
        end,
        sameValue = function(left, right) return tostring(left or "") == tostring(right or "") end,
        captureTransactionState = CapturePositionState,
        restoreTransactionState = RestorePositionState,
        apply = ApplyChannelTicks,
        combatSafe = false,
        menuControlDisposition = "standalone",
        menuControlDispositionReason = "The atomic custom marker list is an Assistant-owned advanced value with no current Menu2 list editor.",
        menuControlDispositionEvidence = "MSUF_CastbarChannelTicks.lua TickConfig and MSUF_AssistantRegistry_Castbars_Appearance.lua",
        description = "Atomic ascending percentage list. Use Auto for even spacing, or provide exactly one finite 0-100 position per custom tick.",
    })

    RegisterCastbarBoolean("castbarInterruptShake", "interruptShake", "Shake on Interrupt", false, CastbarAliases("interrupt shake", "shake on interrupt", "unterbrechen schuetteln", "unterbrechung schuetteln"), {
        reason = "MSUF2_CASTBAR_SHAKE",
    })
    RegisterCastbarNumber("castbarShakeStrength", "shakeStrength", "Shake Strength", 8, 0, 30, CastbarAliases("shake strength", "interrupt shake strength"), {
        reason = "MSUF2_CASTBAR_SHAKE_STRENGTH",
    })
    RegisterCastbarNumber("castbarInterruptFeedbackDuration", "interruptDuration", "Interrupt Display Duration", 0.5, 0, 5, CastbarAliases("interrupt duration", "interrupt hold time", "interrupted castbar duration", "unterbrechungs anzeigedauer"), {
        step = 0.1,
        reason = "MSUF2_CASTBAR_INTERRUPT_DURATION",
    })
    RegisterCastbarBoolean("castbarUnifiedDirection", "unifiedDirection", "Always Use Fill Direction for All Casts", false, CastbarAliases("unified fill direction", "same fill direction for channels"), {
        reason = "MSUF2_CASTBAR_UNIFIED_DIRECTION",
    })
    RegisterCastbarEnum("castbarFillDirection", "fillDirection", "Castbar Fill Direction", "RTL", { "RTL", "LTR" }, CastbarAliases("fill direction", "direction"), {
        reason = "MSUF2_CASTBAR_FILL_DIRECTION",
        valueAliases = {
            left = "RTL",
            ["right to left"] = "RTL",
            rtl = "RTL",
            default = "RTL",
            right = "LTR",
            ["left to right"] = "LTR",
            ltr = "LTR",
        },
    })
    RegisterCastbarBoolean("castbarOpositeDirectionTarget", "targetOppositeDirection", "Use Opposite Fill Direction for Target", false, CastbarAliases("target opposite fill direction", "opposite target direction"), {
        reason = "MSUF2_CASTBAR_TARGET_DIRECTION",
    })
    RegisterCastbarString("castbarTexture", "texture", "Castbar Texture", "Blizzard", CastbarAliases("texture", "foreground texture", "sharedmedia texture"), {
        reason = "MSUF2_CASTBAR_TEXTURE",
        apply = ApplyCastbarTextures,
        description = "SharedMedia texture name; values are provided dynamically by the UI.",
    })
    RegisterCastbarString("castbarBackgroundTexture", "backgroundTexture", "Castbar Background Texture", "Blizzard", CastbarAliases("background texture", "background texture", "bg texture"), {
        reason = "MSUF2_CASTBAR_BG_TEXTURE",
        apply = ApplyCastbarTextures,
        description = "SharedMedia texture name; values are provided dynamically by the UI.",
    })
    RegisterCastbarNumber("castbarOutlineThickness", "outline", "Castbar Outline Thickness", 1, 0, 6, CastbarAliases("outline thickness", "border thickness"), {
        reason = "MSUF2_CASTBAR_OUTLINE",
        apply = ApplyCastbarOutline,
    })
    RegisterCastbarBoolean("castbarShowGlow", "glow", "Show Castbar Glow Effect", false, CastbarAliases("glow", "glow effect", "gluehen", "glow effekt"), {
        reason = "MSUF2_CASTBAR_GLOW",
        apply = ApplyCastbarTextures,
    })
    RegisterCastbarBoolean("castbarShowLatency", "latency", "Show Latency Indicator", true, CastbarAliases("latency", "latency indicator", "latenz", "latenzanzeige", "latenz anzeige"), {
        reason = "MSUF2_CASTBAR_LATENCY",
        apply = ApplyCastbarTextures,
    })
    RegisterCastbarBoolean("castbarShowSpark", "spark", "Show Spark", false, CastbarAliases("spark", "leading edge highlight", "funke", "zauberleisten funke"), {
        reason = "MSUF2_CASTBAR_SPARK",
        apply = ApplyCastbarTextures,
    })
    RegisterCastbarBoolean("castbarSparkOverflow", "sparkOverflow", "Spark Extends Beyond Bar", true, CastbarAliases("spark overflow", "spark beyond bar", "funke ausserhalb", "spark ausserhalb"), {
        reason = "MSUF2_CASTBAR_SPARK_OVERFLOW",
        apply = ApplyCastbarTextures,
    })

    RegisterCastbarBoolean("empowerColorStages", "empoweredStageColor", "Add Color to Empowered Stages", true, CastbarAliases("empowered stage colors", "empower color stages", "empower stufen farben", "ermaechtigen stufen farben"), {
        reason = "MSUF2_CASTBAR_EMPOWER_COLOR",
    })
    RegisterCastbarBoolean("empowerStageBlink", "empoweredStageBlink", "Add Stage Blink for Empowered Casts", true, CastbarAliases("empowered stage blink", "empower stage blink", "empower stufen blinken", "ermaechtigen stufen blinken"), {
        reason = "MSUF2_CASTBAR_EMPOWER_BLINK",
    })
    RegisterCastbarNumber("empowerStageBlinkTime", "empoweredStageBlinkTime", "Stage Blink Time", 0.25, 0.05, 1.00, CastbarAliases("stage blink time", "empowered blink time"), {
        step = 0.01,
        reason = "MSUF2_CASTBAR_EMPOWER_TIME",
    })

    RegisterCastbarNumericBoolean("castbarSpellNameShortening", "spellNameShortening", "Spell Name Shortening", false, CastbarAliases("spell name shortening", "shorten spell names", "zaubernamen kuerzen", "spell namen kuerzen"), {
        reason = "MSUF2_CASTBAR_NAME_SHORTEN",
    })
    RegisterCastbarNumber("castbarSpellNameMaxLen", "spellNameMaxLength", "Max Spell Name Length", 30, 6, 30, CastbarAliases("max spell name length", "spell name max length"), {
        reason = "MSUF2_CASTBAR_NAME_MAX",
    })
    RegisterCastbarNumber("castbarSpellNameReservedSpace", "spellNameReservedSpace", "Reserved Spell Name Space", 8, 0, 30, CastbarAliases("reserved spell name space", "spell name reserved space"), {
        reason = "MSUF2_CASTBAR_NAME_RESERVED",
    })

    local RegisterInterruptAppearanceSettings = A.CastbarsRegistry and A.CastbarsRegistry.RegisterInterruptAppearanceSettings
    if type(RegisterInterruptAppearanceSettings) == "function" then
        RegisterInterruptAppearanceSettings(ctx)
    end
end
