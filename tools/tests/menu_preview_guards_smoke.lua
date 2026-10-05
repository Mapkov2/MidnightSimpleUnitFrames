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
--   * SetPropagateKeyboardInput is HasRestrictions (SimpleFrameAPIDocumentation,
--     every branch). The group preview takes the keyboard for arrow-key
--     nudges: PLAYER_REGEN_DISABLED (InCombatLockdown() still false) hands
--     the keys back, and a key pressed in lockdown calls no restricted API.
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

---------------------------------------------------------------------------
-- Group preview keyboard capture at the combat edge.
---------------------------------------------------------------------------
do
    local mw = MenuWorld.Open(root, flavor, { locale = "enUS", page = "gf_auras" })
    local env = mw.env
    local lockdown = false
    env.InCombatLockdown = function() return lockdown end
    local box
    for _, frame in ipairs(mw.world.widgets.frames) do
        if rawget(frame, "_msufGFRenderState") then box = frame end
    end
    if Check(box ~= nil, "the Auras page built no group preview") then
        local propagate, restricted = nil, 0
        box.SetPropagateKeyboardInput = function(_, value)
            if lockdown then restricted = restricted + 1 end
            propagate = value
        end
        -- An arrow-key nudge just before the pull leaves the keys captured.
        box:SetPropagateKeyboardInput(false)
        local onEvent, onKeyDown = box:GetScript("OnEvent"), box:GetScript("OnKeyDown")
        if Check(onEvent and onKeyDown, "the group preview has no OnEvent or OnKeyDown script") then
            onEvent(box, "PLAYER_REGEN_DISABLED")
            Check(propagate == true, "PLAYER_REGEN_DISABLED left the keyboard captured; keys are swallowed in combat")
            lockdown = true
            onKeyDown(box, "LEFT")
            onKeyDown(box, "A")
            Check(restricted == 0, "a key pressed in combat lockdown called SetPropagateKeyboardInput "
                .. restricted .. " time(s)")
            lockdown = false
        end
    end
end

if #failures > 0 then
    error("menu_preview_guards_smoke failed:\n  " .. table.concat(failures, "\n  "))
end
print("menu_preview_guards_smoke: ok (" .. flavor .. "; secret UnitIsUnit never compared, group preview keyboard"
    .. " released at the combat edge and untouched in lockdown)")
