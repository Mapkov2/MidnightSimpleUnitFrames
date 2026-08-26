local function Fail(message)
    error("gameplay_config_cache_smoke: " .. tostring(message), 0)
end

local function Expect(condition, message)
    if not condition then Fail(message) end
end

MSUF_ActiveProfile = "ProfileOne"
MSUF_DB = {
    general = {},
    gameplay = {
        enablePlayerTotems = false,
        combatFontSize = 200,
    },
}

local firstGameplay = MSUF_DB.gameplay
local MSUF = {}
local chunk, loadError = loadfile("MidnightSimpleUnitFrames/Features/Gameplay/MSUF_Feature_GameplayConfig.lua")
if not chunk then Fail(loadError) end
chunk("MidnightSimpleUnitFrames", MSUF)

local first = MSUF.MSUF_EnsureGameplayDefaults()
Expect(first == firstGameplay, "default seeding replaced the active gameplay table")
Expect(first.enableCombatTimer == false, "combat timer enable default was not seeded")
Expect(first.combatFontSize == 64, "combat timer text size was not clamped")
Expect(first.combatOffsetX == 0 and first.combatOffsetY == -200,
    "combat timer offsets were not seeded")
Expect(MSUF.MSUF_GetGameplayDBFast() == first, "fast getter missed the current profile table")

local secondGameplay = {
    enablePlayerTotems = false,
    enableCombatTimer = true,
    combatFontSize = 4,
    combatOffsetX = 77,
}
MSUF_DB = { general = {}, gameplay = secondGameplay }

local second = MSUF.MSUF_GetGameplayDBFast()
Expect(second == secondGameplay, "fast getter retained the previous profile table")
Expect(second ~= first, "profile switch returned the stale gameplay cache")
Expect(second.enableCombatTimer == true, "profile switch lost the combat timer enable setting")
Expect(second.combatFontSize == 10, "switched profile text size was not clamped")
Expect(second.combatOffsetX == 77 and second.combatOffsetY == -200,
    "switched profile combat timer offsets were not normalized")

MSUF_DB = { general = {}, gameplay = firstGameplay }
Expect(MSUF.MSUF_GetGameplayDBFast() == firstGameplay,
    "switching back did not follow the active profile table identity")

print("gameplay_config_cache_smoke: OK")
