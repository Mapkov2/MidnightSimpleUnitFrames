-- Assistant global castbar color setting registry.
-- Loaded before MSUF_AssistantRegistry_GlobalColorSettings.lua; the main domain passes helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GlobalRegistry = A.GlobalRegistry or {}

function A.GlobalRegistry.RegisterCastbarColorSettings(ctx)
    if type(ctx) ~= "table" then return end

    local ColorSetting = ctx.ColorSetting
    local GeneralRGB = ctx.GeneralRGB
    local SetGeneralRGB = ctx.SetGeneralRGB
    local GeneralDB = ctx.GeneralDB
    local TableRGB = ctx.TableRGB
    local SetTableRGB = ctx.SetTableRGB
    local ApiRGB = ctx.ApiRGB
    local ApiSetRGB = ctx.ApiSetRGB
    local RegisterGeneralBoolean = ctx.RegisterGeneralBoolean
    local RegisterGeneralEnum = ctx.RegisterGeneralEnum
    local ApplyCastbarColors = ctx.ApplyCastbarColors
    local COLOR_CASTBAR_ROWS = ctx.COLOR_CASTBAR_ROWS or {}

    if type(ColorSetting) ~= "function" then return end
    if type(GeneralRGB) ~= "function" or type(SetGeneralRGB) ~= "function" then return end
    if type(GeneralDB) ~= "function" or type(TableRGB) ~= "function" then return end
    if type(SetTableRGB) ~= "function" or type(ApiRGB) ~= "function" or type(ApiSetRGB) ~= "function" then return end
    if type(RegisterGeneralBoolean) ~= "function" or type(RegisterGeneralEnum) ~= "function" then return end

    local function RegisterApiCastbarColor(key, label, aliases, getName, setName, fallbackPrefix, dr, dg, db, attribute, alpha)
        local apiOwnsRefresh = false
        ColorSetting(key, label, aliases, function()
            return ApiRGB(getName, dr, dg, db, function() return GeneralRGB(fallbackPrefix, dr, dg, db) end)
        end, function(r, g, b)
            apiOwnsRefresh = ApiSetRGB(setName, r, g, b, alpha) == true
            if not apiOwnsRefresh then SetGeneralRGB(fallbackPrefix, r, g, b) end
        end, {
            category = "Colors / Cast Bar",
            attribute = attribute,
            defaultR = dr,
            defaultG = dg,
            defaultB = db,
            apply = function()
                if apiOwnsRefresh then
                    apiOwnsRefresh = false
                    return true
                end
                if type(ApplyCastbarColors) == "function" then return ApplyCastbarColors() end
                return false
            end,
        })
    end

    for _, row in ipairs(COLOR_CASTBAR_ROWS) do
        RegisterApiCastbarColor(
            "general." .. row.key .. "Color", row.label, row.aliases,
            row.get, row.set, row.key, row.dr, row.dg, row.db, row.key .. "Color")
    end

    RegisterApiCastbarColor("general.castbarBorderColor", "Castbar Border Color", {
        "castbar border color", "cast bar border color", "castbar outline color",
    }, "GetCastbarBorderColor", "SetCastbarBorderColor", "castbarBorder", 0, 0, 0, "castbarBorderColor", 1)

    RegisterApiCastbarColor("general.castbarBackgroundColor", "Castbar Background Color", {
        "castbar background color", "cast bar background color", "castbar bg color",
    }, "GetCastbarBackgroundColor", "SetCastbarBackgroundColor", "castbarBg", 0.10, 0.10, 0.10, "castbarBackgroundColor", 0.85)

    RegisterGeneralBoolean("playerCastbarOverrideEnabled", "playerCastbarOverride", "Player Castbar Color Override", true, {
        "player castbar color override", "player castbar override", "player cast color override",
    }, { category = "Colors / Cast Bar", frameType = "colors", apply = ApplyCastbarColors, reason = "MSUF_ASSISTANT_PLAYER_CASTBAR_OVERRIDE" })
    RegisterGeneralEnum("playerCastbarOverrideMode", "playerCastbarOverrideMode", "Player Castbar Override Mode", "CLASS", { "CLASS", "CUSTOM" }, {
        "player castbar override mode", "player castbar color mode",
    }, {
        category = "Colors / Cast Bar",
        frameType = "colors",
        apply = ApplyCastbarColors,
        reason = "MSUF_ASSISTANT_PLAYER_CASTBAR_OVERRIDE_MODE",
        valueAliases = { class = "CLASS", classcolor = "CLASS", custom = "CUSTOM", color = "CUSTOM", manual = "CUSTOM" },
    })
    RegisterApiCastbarColor("general.playerCastbarOverrideColor", "Player Castbar Override Color", {
        "player castbar override color", "player castbar custom color", "player cast custom color",
    }, "GetPlayerCastbarOverrideColor", "SetPlayerCastbarOverrideColor", "playerCastbarOverride", 0, 0.6, 1, "playerCastbarOverrideColor")

    ColorSetting("general.kickReadyColor", "Kick Ready Color", {
        "kick ready color", "interrupt ready color", "ready kick color",
    }, function()
        return TableRGB(GeneralDB(), "kickReadyColor", 0, 1, 0)
    end, function(r, g, b)
        SetTableRGB(GeneralDB(), "kickReadyColor", r, g, b)
    end, { category = "Colors / Cast Bar", attribute = "kickReadyColor", defaultR = 0, defaultG = 1, defaultB = 0, apply = ApplyCastbarColors })
    ColorSetting("general.kickNotReadyColor", "Kick Not Ready Color", {
        "kick not ready color", "interrupt not ready color", "kick cooldown color",
    }, function()
        return TableRGB(GeneralDB(), "kickNotReadyColor", 1, 0, 0)
    end, function(r, g, b)
        SetTableRGB(GeneralDB(), "kickNotReadyColor", r, g, b)
    end, { category = "Colors / Cast Bar", attribute = "kickNotReadyColor", defaultR = 1, defaultG = 0, defaultB = 0, apply = ApplyCastbarColors })

    -- Beta 44 lets each castbar colour its spell name, cast time and target
    -- name separately (Runtime/MSUF_Colors.lua: <prefix><Detail>Color{R,G,B}).
    -- The override is opt-in: unset keeps following the shared castbar text
    -- colour, so reads fall back to that rather than inventing a value, and
    -- writes go through the product's own setter so the refresh it schedules
    -- still happens.
    local CASTBAR_TEXT_UNITS = {
        { unit = "player", prefix = "castbarPlayer", label = "Player" },
        { unit = "target", prefix = "castbarTarget", label = "Target" },
        { unit = "focus",  prefix = "castbarFocus",  label = "Focus" },
        { unit = "boss",   prefix = "bossCast",      label = "Boss" },
    }
    local CASTBAR_TEXT_DETAILS = {
        { detail = "SpellName",  label = "Spell Name",  nouns = { "spell name text color", "spell text color", "spell name color" } },
        { detail = "Time",       label = "Cast Time",   nouns = { "cast time text color", "cast time color", "timer text color" } },
        { detail = "TargetName", label = "Target Name", nouns = { "target name text color", "cast target name color", "castbar target text color" } },
    }

    for _, unitSpec in ipairs(CASTBAR_TEXT_UNITS) do
        for _, detailSpec in ipairs(CASTBAR_TEXT_DETAILS) do
            local unitKey, detailKey = unitSpec.unit, detailSpec.detail
            local storeKey = unitSpec.prefix .. detailKey .. "Color"
            local aliases = {}
            for _, noun in ipairs(detailSpec.nouns) do
                aliases[#aliases + 1] = unitSpec.label:lower() .. " castbar " .. noun
                aliases[#aliases + 1] = unitSpec.label:lower() .. " cast bar " .. noun
            end

            ColorSetting("general." .. storeKey,
                unitSpec.label .. " Castbar " .. detailSpec.label .. " Color", aliases,
                function()
                    local getter = _G.MSUF_GetCastbarDetailTextColor
                    if type(getter) == "function" then
                        local r, g, b, explicit = getter(unitKey, detailKey)
                        if explicit then return r, g, b end
                    end
                    return TableRGB(GeneralDB(), storeKey, 1, 1, 1)
                end,
                function(r, g, b)
                    local setter = _G.MSUF_SetCastbarDetailTextColor
                    if type(setter) == "function" then
                        setter(unitKey, detailKey, r, g, b)
                        return
                    end
                    SetTableRGB(GeneralDB(), storeKey, r, g, b)
                end,
                {
                    category = "Colors / Castbar Text Colors",
                    attribute = "castbarDetailTextColor",
                    defaultR = 1, defaultG = 1, defaultB = 1,
                    apply = ApplyCastbarColors,
                })
        end
    end
end
