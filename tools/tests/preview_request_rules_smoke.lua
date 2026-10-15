-- Exhaust the old nil/false/true request rules against the actual new visibility caller.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2])
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local world = World.New(root, flavor)
world.env.UnitHealthPercent = function() return 0.5 end
world:Boot()
local failure = world:FirstFailure()
assert(not failure, tostring(failure and failure.file) .. ": " .. tostring(failure and failure.message))
local env, preview = world.env, world.core.UF.Preview
local element = world.core.UF.elements.LoadConditions
local requests = {
    { "editMode", "MSUF_UnitEditModeActive", "SetEditMode" },
    { "all", "MSUF_PreviewTestMode", "SetAll" },
    { "boss", "MSUF_BossTestMode", "SetBoss" },
    { "arena", "MSUF_ArenaTestMode", "SetArena" },
    { "bossPage", "MSUF2_BossUnitframePreviewActive", "SetBossPage" },
    { "arenaPage", "MSUF2_ArenaUnitframePreviewActive", "SetArenaPage" },
    { "unitPage", "MSUF_UnitPreviewActive", "SetUnitPage" },
}
local units = { "player", "target", "focus", "targettarget", "focustarget", "pet", "pettarget",
    "boss1", "boss5", "arena1", "arena5", "arena6", "raid1", "missing" }
local normal = { target = true, focus = true, targettarget = true, focustarget = true, pet = true, pettarget = true }
local bosses = { boss1 = true, boss2 = true, boss3 = true, boss4 = true, boss5 = true }
local arenas = { arena1 = true, arena2 = true, arena3 = true, arena4 = true, arena5 = true }
local values, count = {}, 0
for encoded = 0, 2186 do
    local number = encoded
    for _, request in ipairs(requests) do
        local digit = number % 3
        number = math.floor(number / 3)
        local value
        if digit == 1 then value = false elseif digit == 2 then value = true end
        values[request[1]] = value
        local changed = preview.State[request[1]] ~= value
        assert(preview[request[3]](value) == changed)
        assert(preview.State[request[1]] == value)
        assert(env[request[2]] == value, request[2] .. " mirror")
    end
    for _, unit in ipairs(units) do
        for _, prep in ipairs({ false, true }) do
            local arenaRequest = preview.State.arena
            env.MSUF_ArenaPrepVisibilityActive, env.MSUF_ArenaPrepVisibilityCount = prep, 3
            assert(preview.State.arena == arenaRequest, "native facts changed requests")
            local force = false
            if normal[unit] then force = values.all == true
            elseif bosses[unit] then force = values.boss == true or values.bossPage == true or values.all == true
            elseif arenas[unit] then
                force = (prep and tonumber(unit:match("%d+")) <= 3)
                    or values.arena == true or values.arenaPage == true or values.all == true
            end
            local apiForce = normal[unit] and values.all == true
                or bosses[unit] and (values.boss == true or values.bossPage == true or values.all == true)
                or arenas[unit] and (values.arena == true or values.arenaPage == true or values.all == true) or false
            assert((preview.ForcedUnits[unit] == true) == apiForce, unit .. " request force")
            for _, forced in ipairs({ false, true }) do
                local recorded
                local frame = { MSUFUnitKey = unit, _msufArenaPreviewForced = forced,
                    _msufLoadHealthAlphaApply = true, _msufHealthVisualRoot = { SetAlpha = function(_, value) recorded = value end } }
                assert(element.IsEnabled(frame, {}) == force, unit .. " actual visibility")
                local bypass = values.editMode == true
                    or (bosses[unit] and (values.boss == true or values.bossPage == true)) or forced
                element.UpdateHealthVisibility(frame)
                assert(recorded == (bypass and 1 or 0.5), unit .. " actual health gate")
                count = count + 1
            end
        end
    end
end
print("PASS preview request rules " .. flavor .. ": " .. count .. " actual visibility/health cases")
