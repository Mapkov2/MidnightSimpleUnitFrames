-- Assistant GroupFrames frame-scaling setting registry.
-- Loaded before MSUF_AssistantRegistry_GroupFramesSettings.lua; the main domain passes helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GroupFramesRegistry = A.GroupFramesRegistry or {}

function A.GroupFramesRegistry.RegisterScalingSettings(ctx, scope)
    if type(ctx) ~= "table" or type(scope) ~= "string" then return end

    local AddAliasesForUnit = ctx.AddAliasesForUnit
    local GroupDB = ctx.GroupDB
    local RegisterGroupBoolean = ctx.RegisterGroupBoolean
    local RegisterGroupNumber = ctx.RegisterGroupNumber
    local RegisterGroupEnum = ctx.RegisterGroupEnum

    if type(AddAliasesForUnit) ~= "function" or type(GroupDB) ~= "function" then return end
    if type(RegisterGroupBoolean) ~= "function" or type(RegisterGroupNumber) ~= "function" then return end
    if type(RegisterGroupEnum) ~= "function" then return end

    local aliases = {}
    AddAliasesForUnit(aliases, scope, "scale mode", "skalierungsmodus")
    AddAliasesForUnit(aliases, scope, "group scale mode")
    RegisterGroupEnum(scope, "frameScaleMode", "frameScaleMode", "Frame Scaling Mode", "off", { "off", "manual", "auto" }, {
        off = "off",
        none = "off",
        disable = "off",
        disabled = "off",
        ["false"] = "off",
        manual = "manual",
        on = "manual",
        enable = "manual",
        enabled = "manual",
        custom = "manual",
        auto = "auto",
        automatic = "auto",
        breakpoint = "auto",
        breakpoints = "auto",
    }, "rebuild", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "frame scaling")
    AddAliasesForUnit(aliases, scope, "group frame scaling")
    AddAliasesForUnit(aliases, scope, "scaling")
    RegisterGroupBoolean(scope, "frameScaleEnabled", "frameScaleEnabled", "Frame Scaling", false, "rebuild", aliases, {
        get = function(scopeKey)
            local mode = GroupDB(scopeKey).frameScaleMode
            return mode == "manual" or mode == "auto"
        end,
        set = function(scopeKey, value)
            local conf = GroupDB(scopeKey)
            if value then
                if conf.frameScaleMode ~= "manual" and conf.frameScaleMode ~= "auto" then conf.frameScaleMode = "manual" end
            else
                conf.frameScaleMode = "off"
            end
        end,
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "manual scale", "manuelle skalierung")
    AddAliasesForUnit(aliases, scope, "scale")
    AddAliasesForUnit(aliases, scope, "frame scale")
    AddAliasesForUnit(aliases, scope, "scale percent")
    AddAliasesForUnit(aliases, scope, "frame scale percent")
    RegisterGroupNumber(scope, "frameScaleManual", "frameScaleManual", "Manual Frame Scale", 100, 50, 150, 5, "rebuild", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "scale at 10")
    AddAliasesForUnit(aliases, scope, "1-10 player scale")
    AddAliasesForUnit(aliases, scope, "small group scale")
    AddAliasesForUnit(aliases, scope, "scale when 10 players")
    AddAliasesForUnit(aliases, scope, "scale for 10 players")
    AddAliasesForUnit(aliases, scope, "scaling when there are 10 players")
    RegisterGroupNumber(scope, "scaleAt10", "scaleAt10", "Scale 1-10 Players", 100, 50, 100, 5, "rebuild", aliases, {
        description = "Scale used by the Group Layout frame-scaling breakpoint for 1 to 10 players. Example: set raid scale for 10 players to 95.",
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "scale at 20")
    AddAliasesForUnit(aliases, scope, "11-20 player scale")
    AddAliasesForUnit(aliases, scope, "scale when 20 players")
    AddAliasesForUnit(aliases, scope, "scale for 20 players")
    AddAliasesForUnit(aliases, scope, "scaling when there are 20 players")
    RegisterGroupNumber(scope, "scaleAt20", "scaleAt20", "Scale 11-20 Players", 85, 50, 100, 5, "rebuild", aliases, {
        description = "Scale used by the Group Layout frame-scaling breakpoint for 11 to 20 players. Example: set raid scale for 20 players to 80.",
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "scale at 25")
    AddAliasesForUnit(aliases, scope, "21-25 player scale")
    AddAliasesForUnit(aliases, scope, "scale when 25 players")
    AddAliasesForUnit(aliases, scope, "scale for 25 players")
    AddAliasesForUnit(aliases, scope, "scaling when there are 25 players")
    RegisterGroupNumber(scope, "scaleAt25", "scaleAt25", "Scale 21-25 Players", 80, 50, 100, 5, "rebuild", aliases, {
        description = "Scale used by the Group Layout frame-scaling breakpoint for 21 to 25 players. Example: set raid scale for 25 players to 75.",
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "scale over 25")
    AddAliasesForUnit(aliases, scope, "26 plus player scale")
    AddAliasesForUnit(aliases, scope, "large raid scale")
    AddAliasesForUnit(aliases, scope, "scale when over 25 players")
    AddAliasesForUnit(aliases, scope, "scale for more than 25 players")
    AddAliasesForUnit(aliases, scope, "scaling when there are 26 players")
    RegisterGroupNumber(scope, "scaleOver25", "scaleOver25", "Scale 26+ Players", 70, 50, 100, 5, "rebuild", aliases, {
        description = "Scale used by the Group Layout frame-scaling breakpoint for 26 or more players. Example: set mythic raid scale over 25 players to 70.",
    })
end
