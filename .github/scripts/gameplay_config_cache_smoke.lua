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
        apexItFontSize = 200,
    },
}

local firstGameplay = MSUF_DB.gameplay
local MSUF = {}
local chunk, loadError = loadfile("MidnightSimpleUnitFrames/Features/Gameplay/MSUF_Feature_GameplayConfig.lua")
if not chunk then Fail(loadError) end
chunk("MidnightSimpleUnitFrames", MSUF)

local first = MSUF.MSUF_EnsureGameplayDefaults()
Expect(first == firstGameplay, "default seeding replaced the active gameplay table")
Expect(first.enableApexItDevAura == false, "APEX IT enable default was not seeded")
Expect(first.enableShadowTechniquesStackHighlight == false, "Shadow Techniques stack-highlight default was not seeded")
Expect(first.shadowTechniquesGlowColor[1] == 0.69 and first.shadowTechniquesGlowColor[2] == 0.50
    and first.shadowTechniquesGlowColor[3] == 0.88, "Shadow Techniques glow color default was not seeded")
Expect(first.shadowTechniquesGlowScale == 100 and first.shadowTechniquesGlowStrength == 80,
    "Shadow Techniques glow appearance defaults were not seeded")
Expect(first.apexItFontSize == 64, "APEX IT text size was not clamped")
Expect(first.apexItOffsetX == 0 and first.apexItOffsetY == 140, "APEX IT offsets were not seeded")
Expect(MSUF.MSUF_GetGameplayDBFast() == first, "fast getter missed the current profile table")

local secondGameplay = {
    enablePlayerTotems = false,
    enableApexItDevAura = true,
    enableShadowTechniquesStackHighlight = true,
    shadowTechniquesGlowScale = 300,
    shadowTechniquesGlowStrength = 1,
    apexItFontSize = 4,
    apexItOffsetX = 77,
}
MSUF_DB = { general = {}, gameplay = secondGameplay }

local second = MSUF.MSUF_GetGameplayDBFast()
Expect(second == secondGameplay, "fast getter retained the previous profile table")
Expect(second ~= first, "profile switch returned the stale gameplay cache")
Expect(second.enableApexItDevAura == true, "profile switch lost the APEX IT enable setting")
Expect(second.enableShadowTechniquesStackHighlight == true, "profile switch lost the stack-highlight setting")
Expect(second.shadowTechniquesGlowColor[1] == 0.69 and second.shadowTechniquesGlowColor[2] == 0.50
    and second.shadowTechniquesGlowColor[3] == 0.88, "switched profile glow color was not seeded")
Expect(second.shadowTechniquesGlowScale == 175 and second.shadowTechniquesGlowStrength == 10,
    "switched profile glow appearance was not clamped")
Expect(second.apexItFontSize == 10, "switched profile text size was not clamped")
Expect(second.apexItOffsetX == 77 and second.apexItOffsetY == 140,
    "switched profile APEX IT offsets were not normalized")

MSUF_DB = { general = {}, gameplay = firstGameplay }
Expect(MSUF.MSUF_GetGameplayDBFast() == firstGameplay,
    "switching back did not follow the active profile table identity")

print("gameplay_config_cache_smoke: OK")
