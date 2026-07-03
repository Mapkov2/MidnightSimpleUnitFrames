-- Assistant ClassPower player-HP text registry.
-- Loaded before MSUF_AssistantRegistry_ClassPower_PlayerHP.lua; registers cold text settings.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.ClassPowerRegistry = A.ClassPowerRegistry or {}

local function PlayerHPOpts(applyFn, reason, opts)
    opts = opts or {}
    opts.category = "Global / Class Resources / Player HP Bar"
    opts.frameType = "classPowerPlayerHP"
    opts.apply = applyFn
    opts.reason = reason
    return opts
end

function A.ClassPowerRegistry.RegisterPlayerHPTextSettings(ctx)
    if type(ctx) ~= "table" then return end

    local RegisterBarsBoolean = ctx.RegisterBarsBoolean
    local RegisterBarsString = ctx.RegisterBarsString
    local RegisterBarsNumber = ctx.RegisterBarsNumber
    local RegisterBarsEnum = ctx.RegisterBarsEnum
    local ApplyClassPower = ctx.ApplyClassPower
    local RegistryCore = A.RegistryCore or {}
    local BarsDB = ctx.BarsDB or RegistryCore.BarsDB
    local GeneralDB = ctx.GeneralDB or RegistryCore.GeneralDB

    if type(RegisterBarsBoolean) ~= "function" or type(RegisterBarsString) ~= "function" then return end
    if type(RegisterBarsNumber) ~= "function" or type(RegisterBarsEnum) ~= "function" then return end
    if type(ApplyClassPower) ~= "function" then return end

    local Data = A.ClassPowerRegistryData or {}
    local PLAYER_HP_TEXT_MODE_ALIASES = Data.PLAYER_HP_TEXT_MODE_ALIASES or {}
    local PLAYER_HP_TEXT_MODES = Data.PLAYER_HP_TEXT_MODES or {}

    RegisterBarsBoolean("playerHPBarTextEnabled", "text", "Class Resources Player HP Text", true, {
        "player hp text", "second hp text", "duplicate hp text",
        "class resource hp text", "class resources player hp text",
        "class resources player hp bar text", "second player hp bar text",
    }, PlayerHPOpts(ApplyClassPower, "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_TEXT"))
    RegisterBarsBoolean("playerHPBarUsePlayerText", "usePlayerText", "Class Resources Player HP Use Player Text", true, {
        "use player hp text", "share player hp text", "shared player hp text",
        "reuse player hp text", "copy player hp text", "second hp use player text",
        "class resources player hp use player text",
    }, PlayerHPOpts(ApplyClassPower, "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_SHARED_TEXT", {
        description = "Uses Player HP text settings and copies already-rendered Player HP text for the second HP bar when possible.",
    }))
    RegisterBarsEnum("playerHPBarTextLeft", "leftText", "Class Resources Player HP Left Text", "NONE", PLAYER_HP_TEXT_MODES, {
        "player hp left text", "second hp left text", "duplicate hp left text",
    }, PlayerHPOpts(ApplyClassPower, "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_TEXT_LEFT", {
        valueAliases = PLAYER_HP_TEXT_MODE_ALIASES,
    }))
    RegisterBarsEnum("playerHPBarTextCenter", "centerText", "Class Resources Player HP Center Text", "NONE", PLAYER_HP_TEXT_MODES, {
        "player hp center text", "player hp middle text", "second hp center text", "duplicate hp center text",
    }, PlayerHPOpts(ApplyClassPower, "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_TEXT_CENTER", {
        valueAliases = PLAYER_HP_TEXT_MODE_ALIASES,
    }))
    RegisterBarsEnum("playerHPBarTextRight", "rightText", "Class Resources Player HP Right Text", "CURPERCENT", PLAYER_HP_TEXT_MODES, {
        "player hp right text", "second hp right text", "duplicate hp right text",
    }, PlayerHPOpts(ApplyClassPower, "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_TEXT_RIGHT", {
        valueAliases = PLAYER_HP_TEXT_MODE_ALIASES,
    }))
    local function PercentSignVisible(dbKey)
        local bars = type(BarsDB) == "function" and BarsDB() or nil
        local value = type(bars) == "table" and bars[dbKey] or nil
        if value ~= nil then return value ~= true end
        local g = type(GeneralDB) == "function" and GeneralDB() or nil
        return not (type(g) == "table" and g.hidePercentSymbol == true)
    end
    local function SetPercentSignVisible(dbKey, visible)
        local bars = type(BarsDB) == "function" and BarsDB() or nil
        if type(bars) == "table" then
            bars[dbKey] = not (visible and true or false)
        end
    end
    local function RegisterPercentSign(attr, dbKey, label, aliases, reason)
        RegisterBarsBoolean(dbKey, attr, label, true, aliases, PlayerHPOpts(ApplyClassPower, reason, {
            keySuffix = attr,
            get = function() return PercentSignVisible(dbKey) end,
            set = function(value) SetPercentSignVisible(dbKey, value) end,
        }))
    end
    RegisterBarsBoolean("playerHPBarTextLeftHidePercentSymbol", "leftTextHidePercentSymbol", "Class Resources Player HP Hide Left % Sign", false, {
        "player hp left hide percent sign", "second hp left hide percent sign", "duplicate hp left hide percent sign",
        "hide player hp left percent sign", "hide second hp left percent sign", "hide duplicate hp left percent sign",
        "second hp hide percent sign",
    }, PlayerHPOpts(ApplyClassPower, "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_HIDE_LEFT_PERCENT", { matchLabel = false }))
    RegisterPercentSign("playerHPBarTextLeftPercentSymbol", "playerHPBarTextLeftHidePercentSymbol", "Class Resources Player HP Left % Sign", {
        "player hp left percent sign", "second hp left percent sign", "duplicate hp left percent sign",
        "player hp left % sign", "second hp left % sign", "class resources player hp left percent sign",
    }, "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_LEFT_PERCENT_SIGN")
    RegisterBarsBoolean("playerHPBarTextCenterHidePercentSymbol", "centerTextHidePercentSymbol", "Class Resources Player HP Hide Center % Sign", false, {
        "player hp center hide percent sign", "player hp middle hide percent sign", "second hp center hide percent sign",
        "duplicate hp center hide percent sign", "second hp middle hide percent sign",
        "hide player hp center percent sign", "hide player hp middle percent sign", "hide second hp center percent sign",
        "hide duplicate hp center percent sign",
    }, PlayerHPOpts(ApplyClassPower, "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_HIDE_CENTER_PERCENT", { matchLabel = false }))
    RegisterPercentSign("playerHPBarTextCenterPercentSymbol", "playerHPBarTextCenterHidePercentSymbol", "Class Resources Player HP Center % Sign", {
        "player hp center percent sign", "player hp middle percent sign", "second hp center percent sign",
        "duplicate hp center percent sign", "second hp middle percent sign", "player hp center % sign",
        "class resources player hp center percent sign",
    }, "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_CENTER_PERCENT_SIGN")
    RegisterBarsBoolean("playerHPBarTextRightHidePercentSymbol", "rightTextHidePercentSymbol", "Class Resources Player HP Hide Right % Sign", false, {
        "player hp right hide percent sign", "second hp right hide percent sign", "duplicate hp right hide percent sign",
        "hide player hp right percent sign", "hide second hp right percent sign", "hide duplicate hp right percent sign",
    }, PlayerHPOpts(ApplyClassPower, "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_HIDE_RIGHT_PERCENT", { matchLabel = false }))
    RegisterPercentSign("playerHPBarTextRightPercentSymbol", "playerHPBarTextRightHidePercentSymbol", "Class Resources Player HP Right % Sign", {
        "player hp right percent sign", "second hp right percent sign", "duplicate hp right percent sign",
        "player hp right % sign", "second hp right % sign", "class resources player hp right percent sign",
    }, "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_RIGHT_PERCENT_SIGN")
    RegisterBarsString("playerHPBarTextSeparator", "textDelimiter", "Class Resources Player HP Text Delimiter", "", {
        "second hp text delimiter", "second hp text separator",
        "duplicate hp text delimiter", "duplicate hp text separator",
        "class resources player hp text delimiter", "class resources player hp text separator",
    }, PlayerHPOpts(ApplyClassPower, "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_TEXT_SEPARATOR", {
        description = "Sets the delimiter used between combined HP text values on the second Player HP bar.",
        matchLabel = false,
    }))
    RegisterBarsBoolean("playerHPBarTextReverse", "reverseText", "Class Resources Player HP Reverse Text", false, {
        "player hp reverse text", "player hp reverse order", "second hp reverse text", "duplicate hp reverse text",
    }, PlayerHPOpts(ApplyClassPower, "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_TEXT_REVERSE"))
    RegisterBarsNumber("playerHPBarTextSize", "textSize", "Class Resources Player HP Text Size", 14, 6, 48, {
        "player hp text size", "player hp font size", "second hp text size", "duplicate hp font size",
    }, PlayerHPOpts(ApplyClassPower, "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_TEXT_SIZE"))
    RegisterBarsNumber("playerHPBarTextOffsetX", "textOffsetX", "Class Resources Player HP Text Offset X", 0, -300, 300, {
        "player hp text x", "player hp text offset x", "second hp text x",
    }, PlayerHPOpts(ApplyClassPower, "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_TEXT_X"))
    RegisterBarsNumber("playerHPBarTextOffsetY", "textOffsetY", "Class Resources Player HP Text Offset Y", 0, -300, 300, {
        "player hp text y", "player hp text offset y", "second hp text y",
    }, PlayerHPOpts(ApplyClassPower, "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_TEXT_Y"))
end
