local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local World = dofile(root .. "/tools/tests/castbar_secret_world.lua")
local world = World.New(root, { flavor = "Mainline", playerClass = "PALADIN" })
local ns, env = world.core, world.env
ns.Require("MSUF_EnsureDB", "nameplate consumer test")(true)
local before = ns.ProfileFields.Copy(env.MSUF_DB.general)
local settings = ns.HostAPI.GetNameplateSettings()
-- An imported nameplate setup may still name a look; only the castbar menu owns one.
local ok, report = settings.Apply({ version = 1, general = {
    kickReadyStyle = "fill", kickReadyColor = { 0.2, 0.3, 0.4 }, kickReadyTimeMarker = true,
    kickReadyTimeSegment = true, castbarOutlineThickness = 7, kickReadyAutoSize = false,
    kickReadySize = 31, kickReadyAnchor = "LEFT", kickReadyOffsetX = 17, kickReadyOffsetY = -9,
    castbarInterruptibleR = 0.1, castbarInterruptibleG = 0.2, castbarInterruptibleB = 0.3,
} })
assert(ok, "native settings application failed: " .. tostring(report))
assert(ns.ProfileFields.Equal(env.MSUF_DB.general, before), "nameplate apply changed the castbar menu's look")
assert(env.MSUF_DB.nameplates == nil, "nameplate apply stored a look of its own")
-- The castbar menu's settings are the consumer's look; a look stored for
-- nameplates by an earlier 7.0 build is neither read nor kept.
local general = env.MSUF_DB.general
general.kickReadyStyle, general.kickReadyColor = "fill", { 0.2, 0.3, 0.4, 1 }
general.kickReadyTimeMarker, general.kickReadyTimeSegment, general.castbarOutlineThickness = true, true, 5
general.kickReadyAutoSize, general.kickReadySize, general.kickReadyAnchor = false, 31, "LEFT"
general.kickReadyOffsetX, general.kickReadyOffsetY = 17, -9
general.castbarInterruptibleR, general.castbarInterruptibleG, general.castbarInterruptibleB = 0.1, 0.2, 0.3
general.castbarNonInterruptibleR, general.castbarNonInterruptibleG, general.castbarNonInterruptibleB = 0.4, 0.5, 0.6
general.castbarInterruptUnavailableR, general.castbarInterruptUnavailableG, general.castbarInterruptUnavailableB = 0.7, 0.8, 0.9
env.MSUF_DB.nameplates = { interrupt = { kickReadyStyle = "box", kickReadySize = 12, kickReadyAnchor = "TOP" } }
local expected = ns.ProfileFields.Copy(general)
-- The switch is the one nameplate setting; its apply repaints the consumers.
ok, report = settings.Apply({ version = 1, general = { kickReadyShowNameplates = true } })
assert(ok, "nameplate switch application failed: " .. tostring(report))
assert(env.MSUF_DB.nameplates == nil, "a retired nameplate look survived an apply")
local look = ns.KickReady.Look()
assert(look.show == true, "nameplate switch did not reach the consumer")
assert(look.style == "fill" and look.marker and look.segment and look.outline == 5, "native consumer missed the castbar menu's style")
assert(look.boxSize == 31 and look.boxAnchor == "LEFT" and look.boxOffsetX == 17 and look.boxOffsetY == -9,
    "native consumer missed the castbar menu's geometry")
assert(look.readyR == 0.2 and look.readyG == 0.3 and look.readyB == 0.4, "native consumer missed the castbar menu's ready color")
local cast, non, unavailable = ns.KickReady.FillColors()
local red, green, blue = cast:GetRGB()
assert(red == 0.1 and green == 0.2 and blue == 0.3, "native fill missed the interruptible color")
red, green, blue = non:GetRGB()
assert(red == 0.4 and green == 0.5 and blue == 0.6, "native fill missed the uninterruptible color")
red, green, blue = unavailable:GetRGB()
assert(red == 0.7 and green == 0.8 and blue == 0.9, "native fill missed the unavailable color")
assert(settings.Apply(report.snapshot) and ns.KickReady.Look().show ~= true, "native snapshot rollback failed")
assert(ns.ProfileFields.Equal(env.MSUF_DB.general, expected), "native rollback changed other castbars")
print("nameplate native consumer: castbar menu look, switch, retired scope and rollback passed")
