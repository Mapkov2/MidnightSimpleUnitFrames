-- Group frame role power assistant settings.
-- Loaded before MSUF_AssistantRegistry_GroupFramesSettings_Bars.lua; preserves the existing bar registration order.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GroupFramesRegistry = A.GroupFramesRegistry or {}

function A.GroupFramesRegistry.RegisterPowerRoleSettings(ctx, scope)
    if type(ctx) ~= "table" then return end
    scope = tostring(scope or "")
    if scope == "" then return end

    local AddAliasesForUnit = ctx.AddAliasesForUnit
    local RegisterGroupBoolean = ctx.RegisterGroupBoolean
    local UNIT_LABELS = ctx.UNIT_LABELS or {}
    if type(AddAliasesForUnit) ~= "function" or type(RegisterGroupBoolean) ~= "function" then return end

    local scopeLabel = tostring(UNIT_LABELS[scope] or scope):lower()
    local function RolePowerExactAliases(roleTerms)
        local out = {}
        local scopes = { scope }
        if scopeLabel ~= scope then scopes[#scopes + 1] = scopeLabel end
        local nouns = {
            "power", "power bar", "power bars",
            "mana", "mana bar", "mana bars",
            "resource", "resources", "resource bar", "resource bars",
        }
        for i = 1, #scopes do
            for j = 1, #roleTerms do
                for k = 1, #nouns do
                    out[#out + 1] = scopes[i] .. " " .. roleTerms[j] .. " " .. nouns[k]
                    out[#out + 1] = scopes[i] .. " " .. nouns[k] .. " for " .. roleTerms[j]
                end
            end
        end
        return out
    end

    local aliases = {}
    AddAliasesForUnit(aliases, scope, "power smooth fill")
    AddAliasesForUnit(aliases, scope, "smooth power fill")
    RegisterGroupBoolean(scope, "powerSmoothFill", "powerSmoothFill", "Power Smooth Fill", false, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "show tank power")
    AddAliasesForUnit(aliases, scope, "tank power bar")
    AddAliasesForUnit(aliases, scope, "tank power bars")
    AddAliasesForUnit(aliases, scope, "tank mana")
    AddAliasesForUnit(aliases, scope, "tank mana bars")
    AddAliasesForUnit(aliases, scope, "power for tanks")
    AddAliasesForUnit(aliases, scope, "mana for tanks")
    AddAliasesForUnit(aliases, scope, "resource for tanks")
    AddAliasesForUnit(aliases, scope, "resources for tanks")
    AddAliasesForUnit(aliases, scope, "tank resources")
    RegisterGroupBoolean(scope, "powerShowTank", "powerShowTank", "Show Tank Power", true, "visual", aliases, {
        exactAliases = RolePowerExactAliases({ "tank", "tanks" }),
        description = "Controls whether group-frame power/resource bars are shown for tank-role members.",
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "show healer power")
    AddAliasesForUnit(aliases, scope, "healer power bar")
    AddAliasesForUnit(aliases, scope, "healer power bars")
    AddAliasesForUnit(aliases, scope, "healer mana")
    AddAliasesForUnit(aliases, scope, "healer mana bars")
    AddAliasesForUnit(aliases, scope, "power for healers")
    AddAliasesForUnit(aliases, scope, "mana for healers")
    AddAliasesForUnit(aliases, scope, "resource for healers")
    AddAliasesForUnit(aliases, scope, "resources for healers")
    AddAliasesForUnit(aliases, scope, "healer resources")
    RegisterGroupBoolean(scope, "powerShowHealer", "powerShowHealer", "Show Healer Power", true, "visual", aliases, {
        exactAliases = RolePowerExactAliases({ "healer", "healers", "heal" }),
        description = "Controls whether group-frame power/resource bars are shown for healer-role members.",
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "show dps power")
    AddAliasesForUnit(aliases, scope, "dps power bar")
    AddAliasesForUnit(aliases, scope, "dps power bars")
    AddAliasesForUnit(aliases, scope, "dps mana")
    AddAliasesForUnit(aliases, scope, "dps mana bars")
    AddAliasesForUnit(aliases, scope, "damage dealer power")
    AddAliasesForUnit(aliases, scope, "damage dealer mana")
    AddAliasesForUnit(aliases, scope, "power for dps")
    AddAliasesForUnit(aliases, scope, "mana for dps")
    AddAliasesForUnit(aliases, scope, "resource for dps")
    AddAliasesForUnit(aliases, scope, "resources for dps")
    AddAliasesForUnit(aliases, scope, "dps resources")
    AddAliasesForUnit(aliases, scope, "damage dealer resources")
    RegisterGroupBoolean(scope, "powerShowDamager", "powerShowDamager", "Show DPS Power", false, "visual", aliases, {
        exactAliases = RolePowerExactAliases({ "dps", "damager", "damage dealer", "damage dealers" }),
        description = "Controls whether group-frame power/resource bars are shown for DPS-role members.",
    })
end
