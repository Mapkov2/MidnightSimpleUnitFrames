-- Group frame ordering assistant settings.
-- Loaded before MSUF_AssistantRegistry_GroupFramesSettings.lua; keeps ordering separate from frame power toggles.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GroupFramesRegistry = A.GroupFramesRegistry or {}

function A.GroupFramesRegistry.RegisterFrameOrderingSettings(ctx, scope)
    if type(ctx) ~= "table" then return end

    local AddAliasesForUnit = ctx.AddAliasesForUnit
    local GroupDB = ctx.GroupDB
    local RegisterGroupBoolean = ctx.RegisterGroupBoolean
    local RegisterGroupNumber = ctx.RegisterGroupNumber
    local RegisterGroupEnum = ctx.RegisterGroupEnum
    local GroupGrowthExactAliases = ctx.GroupGrowthExactAliases
    local NormalizeGroupRoleOrder = ctx.NormalizeGroupRoleOrder
    if type(AddAliasesForUnit) ~= "function" or type(GroupDB) ~= "function" then return end
    if type(RegisterGroupBoolean) ~= "function" or type(RegisterGroupNumber) ~= "function" then return end
    if type(RegisterGroupEnum) ~= "function" or type(GroupGrowthExactAliases) ~= "function" then return end
    if type(NormalizeGroupRoleOrder) ~= "function" then return end

    local aliases = {}
    AddAliasesForUnit(aliases, scope, "range fade alpha", "reichweite fade alpha")
    AddAliasesForUnit(aliases, scope, "out of range alpha", "ausser reichweite alpha")
    AddAliasesForUnit(aliases, scope, "range fade opacity")
    AddAliasesForUnit(aliases, scope, "out of range opacity")
    RegisterGroupNumber(scope, "rangeFadeAlpha", "rangeFadeAlpha", "Range Fade Alpha", 0.4, 0, 1, 0.05, "visual", aliases, { percent = true })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "growth", "wachstum")
    AddAliasesForUnit(aliases, scope, "growth direction", "wachstumsrichtung")
    AddAliasesForUnit(aliases, scope, "grow")
    AddAliasesForUnit(aliases, scope, "to grow")
    AddAliasesForUnit(aliases, scope, "grow direction")
    AddAliasesForUnit(aliases, scope, "frames grow")
    AddAliasesForUnit(aliases, scope, "frames to grow")
    RegisterGroupEnum(scope, "growth", "growth", "Growth Direction", "DOWN", { "DOWN", "UP", "RIGHT", "LEFT" }, {
        ["right then down"] = "RIGHT",
        ["right and down"] = "RIGHT",
        ["right first"] = "RIGHT",
        ["grow right"] = "RIGHT",
        ["to the right"] = "RIGHT",
        horizontal = "RIGHT",
        horizontally = "RIGHT",
        down = "DOWN",
        ["down then right"] = "DOWN",
        ["down and right"] = "DOWN",
        ["down first"] = "DOWN",
        ["grow down"] = "DOWN",
        downwards = "DOWN",
        vertical = "DOWN",
        vertically = "DOWN",
        runter = "DOWN",
        unten = "DOWN",
        up = "UP",
        ["up then right"] = "UP",
        ["up and right"] = "UP",
        ["up first"] = "UP",
        ["grow up"] = "UP",
        upwards = "UP",
        hoch = "UP",
        oben = "UP",
        right = "RIGHT",
        rechts = "RIGHT",
        left = "LEFT",
        ["left then down"] = "LEFT",
        ["left and down"] = "LEFT",
        ["left first"] = "LEFT",
        ["grow left"] = "LEFT",
        ["to the left"] = "LEFT",
        links = "LEFT",
    }, "geometry", aliases, {
        exactAliases = GroupGrowthExactAliases(scope),
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "sort mode", "sortierung")
    AddAliasesForUnit(aliases, scope, "sort order", "sortiermodus")
    RegisterGroupEnum(scope, "sortMode", "sortMode", "Sort Mode", "INDEX", { "INDEX", "ROLE", "GROUP", "GROUP_ROLE", "NAME" }, {
        index = "INDEX",
        default = "INDEX",
        simple = "INDEX",
        off = "INDEX",
        disable = "INDEX",
        disabled = "INDEX",
        role = "ROLE",
        roles = "ROLE",
        byrole = "ROLE",
        ["by role"] = "ROLE",
        group = "GROUP",
        raidgroup = "GROUP",
        ["raid group"] = "GROUP",
        group_role = "GROUP_ROLE",
        grouprole = "GROUP_ROLE",
        ["group role"] = "GROUP_ROLE",
        ["group and role"] = "GROUP_ROLE",
        ["group plus role"] = "GROUP_ROLE",
        name = "NAME",
        alphabetical = "NAME",
        alpha = "NAME",
    }, "rebuild", aliases, {
        get = function(scopeKey)
            local conf = GroupDB(scopeKey)
            local mode = conf.sortMode
            if mode == "INDEX" or mode == "ROLE" or mode == "GROUP" or mode == "GROUP_ROLE" or mode == "NAME" then return mode end
            return conf.sortByRole and "ROLE" or "INDEX"
        end,
        set = function(scopeKey, value)
            local conf = GroupDB(scopeKey)
            if value ~= "ROLE" and value ~= "GROUP" and value ~= "GROUP_ROLE" and value ~= "NAME" then value = "INDEX" end
            conf.sortMode = value
            conf.sortByRole = value == "ROLE"
        end,
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "sort by role")
    AddAliasesForUnit(aliases, scope, "role sorting")
    AddAliasesForUnit(aliases, scope, "sort roles")
    RegisterGroupBoolean(scope, "sortByRole", "sortByRole", "Sort by Role", false, "rebuild", aliases, {
        get = function(scopeKey)
            local conf = GroupDB(scopeKey)
            if conf.sortMode then return conf.sortMode == "ROLE" end
            return conf.sortByRole and true or false
        end,
        set = function(scopeKey, value)
            local conf = GroupDB(scopeKey)
            conf.sortByRole = value and true or false
            conf.sortMode = value and "ROLE" or "INDEX"
        end,
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "player first in role")
    AddAliasesForUnit(aliases, scope, "player first")
    RegisterGroupBoolean(scope, "playerFirstInRole", "playerFirstInRole", "Player First in Role", false, "rebuild", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "role priority order")
    AddAliasesForUnit(aliases, scope, "role order")
    AddAliasesForUnit(aliases, scope, "role sorting order")
    RegisterGroupEnum(scope, "roleOrder", "roleOrder", "Role Priority Order", "TANK,HEALER,DAMAGER", {
        "TANK,HEALER,DAMAGER", "TANK,DAMAGER,HEALER", "HEALER,TANK,DAMAGER",
        "HEALER,DAMAGER,TANK", "DAMAGER,TANK,HEALER", "DAMAGER,HEALER,TANK",
    }, {
        ["tank healer dps"] = "TANK,HEALER,DAMAGER",
        ["tank heal dps"] = "TANK,HEALER,DAMAGER",
        ["tank dps healer"] = "TANK,DAMAGER,HEALER",
        ["tank dps heal"] = "TANK,DAMAGER,HEALER",
        ["healer tank dps"] = "HEALER,TANK,DAMAGER",
        ["heal tank dps"] = "HEALER,TANK,DAMAGER",
        ["healer dps tank"] = "HEALER,DAMAGER,TANK",
        ["heal dps tank"] = "HEALER,DAMAGER,TANK",
        ["dps tank healer"] = "DAMAGER,TANK,HEALER",
        ["dps tank heal"] = "DAMAGER,TANK,HEALER",
        ["dps healer tank"] = "DAMAGER,HEALER,TANK",
        ["dps heal tank"] = "DAMAGER,HEALER,TANK",
    }, "rebuild", aliases, {
        get = function(scopeKey) return NormalizeGroupRoleOrder(GroupDB(scopeKey).roleOrder) end,
        set = function(scopeKey, value) GroupDB(scopeKey).roleOrder = NormalizeGroupRoleOrder(value) end,
    })
end
