-- menu_preview_guards_smoke.lua <repoRoot> [flavor]
--
-- Secret and combat guards of the Menu2 previews, on one client's real core
-- and Options graph with the menu open:
--   * the raid-group name preview reads the player's raid subgroup; UnitIsUnit
--     is SecretWhenUnitComparisonRestricted (UnitDocumentation.lua, live), so
--     on an addon-restricted map its answer is secret and must not be
--     compared. A strict line watcher (tools/tests/classpower_secrets.lua)
--     records any comparison or boolean test of the secret answer; the
--     preview keeps its stylized fallback then, and a plain answer still
--     gives the live subgroup;
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local Secrets = assert(loadfile(root .. "/tools/tests/classpower_secrets.lua"))()

local failures = {}
local function Check(condition, message)
    if not condition then failures[#failures + 1] = flavor .. ": " .. message end
    return condition
end

---------------------------------------------------------------------------
-- Raid subgroup of the raid-group name preview.
---------------------------------------------------------------------------
do
    local mw = MenuWorld.Open(root, flavor, { locale = "enUS", beforeCore = function(world)
        local stub = world.env.issecretvalue
        world.env.issecretvalue = function(value)
            if Secrets.IsSecret(value) then return true end
            return stub ~= nil and stub(value) == true
        end
    end })
    local env = mw.env
    local Preview = mw.core.UFPreview
    local live = Preview and Preview.LiveRaidSubgroup
    if Check(type(live) == "function", "Preview.LiveRaidSubgroup is missing") then
        local saved = {}
        for _, name in ipairs({ "InCombatLockdown", "IsInRaid", "UnitInRaid", "GetRaidRosterInfo", "UnitIsUnit" }) do
            saved[name] = env[name]
        end
        env.InCombatLockdown = function() return false end
        env.IsInRaid = function() return true end
        env.UnitInRaid = function() return 3 end
        env.GetRaidRosterInfo = function() return "Raider", 0, 4 end
        env.UnitIsUnit = function() return true end
        Check(live() == 4, "a plain UnitIsUnit answer no longer gives the live raid subgroup")
        env.UnitIsUnit = function() return Secrets.New("boolean") end
        local source = debug.getinfo(live, "S").source:sub(2)
        local stop = Secrets.Watch(source, { strict = true })
        local subgroup = live()
        local violations = stop()
        Check(#violations == 0, "a secret UnitIsUnit answer was compared:\n    " .. table.concat(violations, "\n    "))
        Check(subgroup == nil, "a secret UnitIsUnit answer gave subgroup " .. tostring(subgroup)
            .. " instead of the stylized fallback")
        for name, value in pairs(saved) do env[name] = value end
    end
end

if #failures > 0 then
    error("menu_preview_guards_smoke failed:\n  " .. table.concat(failures, "\n  "))
end
print("menu_preview_guards_smoke: ok (" .. flavor .. "; secret UnitIsUnit never compared)")
