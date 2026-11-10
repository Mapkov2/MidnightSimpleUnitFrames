local root = (arg[1] or "."):gsub("\\", "/"):gsub("/$", "")
local source = arg[2] or root .. "/MidnightSimpleUnitFrames/Runtime/MSUF_NameplateSettings.lua"
local checks = 0
local function Check(value, message)
    checks = checks + 1
    assert(value, message)
end

local Secrets = assert(loadfile(root .. "/tools/tests/classpower_secrets.lua"))()
Secrets.Install()
local combat, failRefresh, refreshes, fontRefreshes = false, false, 0, 0
local MSUF = { Util = { IsSecret = issecretvalue, InCombat = function() return combat end },
    Public = {}, SuiteLink = {}, UF = { Config = {} }, MSUF_FONT_COLORS = { white = { 1, 1, 1 }, green = { 0, 1, 0 } } }
MSUF.HostAPIPlayerInCombat = function() return combat end
MSUF.RunHostAPIStep = function(_, callback, ...) return pcall(callback, ...) end
MSUF.SuiteLink.ApplyFonts = function() fontRefreshes = fontRefreshes + 1 end
MSUF.UFText = { DescribeNameFormat = function(mode, maximum, dots, side)
    if mode == "SHORT" then return "CUT", 10, false, "RIGHT" end
    return mode, maximum, dots, side
end }
local function ResolveColors(_, general)
    Check(general ~= nil, "capture passes the requested profile to the cast-color owner")
    return general.castbarInterruptibleR or 0, general.castbarInterruptibleG or 0.85, general.castbarInterruptibleB or 0.85,
        general.castbarNonInterruptibleR or 0.9, general.castbarNonInterruptibleG or 0.1, general.castbarNonInterruptibleB or 0.1
end
MSUF.Public.ResolveCastbarColors = ResolveColors
MSUF.Public.ResolveInterruptUnavailableCastColor = function(general)
    return general.castbarInterruptUnavailableR or 1, general.castbarInterruptUnavailableG or 0.494117647,
        general.castbarInterruptUnavailableB or 0.137254902
end
MSUF.Require = function(name)
    if name == "MSUF_ResolveFontShadowMetrics" then
        return function(alpha, distance, legacy, fallbackAlpha, fallbackDistance)
            if legacy then return legacy == "SOFT" and 0.55 or 1, legacy == "DEEP" and 2 or 1 end
            return alpha or fallbackAlpha or 1, distance or fallbackDistance or 1
        end
    end
    if name == "MSUF_Castbars_OnSettingsChanged" then
        return function()
            refreshes = refreshes + 1
            if failRefresh then error("injected refresh failure") end
        end
    end
    if name == "MSUF_ApplyAllCastbarsAndSync" then return function() end end
    error("unexpected dependency " .. name)
end
assert(loadfile(root .. "/MidnightSimpleUnitFrames/State/MSUF_ProfileFields.lua"))("MSUF", MSUF)
assert(loadfile(source))("MSUF", MSUF)
local Settings, Fields = MSUF.NameplateSettings, MSUF.ProfileFields
Check(Settings and Settings.version == 1, "published settings provider")
UnitAffectingCombat = function() return false end
MSUF.ExportPublic = function(name, value) _G[name] = value end
assert(loadfile(root .. "/MidnightSimpleUnitFrames/Runtime/MSUF_HostAPI.lua"))("MSUF", MSUF)
Check(MSUF_HostAPI.GetNameplateSettings() == Settings, "host facade returns the settings owner")

local function Reset(fonts)
    MSUF.UF.Config.ResolveNameplateFont = fonts and function() end or nil
    MSUF_DB = { general = { unrelated = "keep", fontKey = "EXPRESSWAY", fontSize = 15,
        nameFontSize = 18, fontColor = "green", nameFormat = "ABBREV", kickReadyStyle = "box",
        kickReadyShowTarget = true, castbarTexture = "Global Texture", castbarOutlineThickness = 3 },
        player = { width = 211 }, shortenNames = false }
    MSUF_ActiveProfile = "Current"
    MSUF_GlobalDB = { profiles = { Current = MSUF_DB, Other = { general = { fontKey = "FRIZQT", fontSize = 20,
        nameFontSize = 22, kickReadyStyle = "fill", castbarInterruptibleR = 0.3 } } } }
    combat, failRefresh, refreshes, fontRefreshes = false, false, 0, 0
end

for _, fonts in ipairs({ false, true }) do
    Reset(fonts)
    local before = Fields.Copy(MSUF_DB)
    local payload, why, snapshot = Settings.Capture()
    Check(payload ~= nil and why == nil and snapshot ~= nil, "capture payload plus rollback snapshot")
    Check(payload.general.kickReadyShowNameplates == false and payload.general.kickReadyStyle == nil
        and snapshot.general.kickReadyStyle == nil, "capture carries the nameplate switch, not the castbar menu's look")
    Check(payload.nameplates.fontKey == "EXPRESSWAY" and payload.nameplates.fontSize == 15, "capture inherited font")
    Check(payload.nameplates.fontColorG == 1 and payload.nameplates.fontColorR == 0, "capture font palette")
    Check(Fields.Equal(MSUF_DB, before), "capture does not populate or replace profile data")
    local other = Settings.Capture("Other")
    Check(other.nameplates.fontSize == 20 and other.general.kickReadyShowNameplates == false
        and other.general.castbarInterruptibleR == nil, "inactive profile export")
    Check(MSUF_ActiveProfile == "Current" and MSUF_DB == MSUF_GlobalDB.profiles.Current, "inactive export keeps active identity")
    Check(Settings.Capture("missing") == nil, "unknown named profile refuses")
    MSUF_GlobalDB.profiles.Sparse = { player = { width = 151 } }
    Check(Settings.Capture("Sparse") ~= nil, "inactive sparse profile captures defaults without materializing the profile")
    payload.general.kickReadyStyle, payload.general.kickReadyShowNameplates = "fill", true
    payload.general.castbarTexture, payload.general.castbarOutlineThickness = "Plate Texture", 8
    payload.nameplates.fontKey, payload.nameplates.fontSize = "FRIZQT", 23
    local db, general = MSUF_DB, MSUF_DB.general
    local ok, report = Settings.Apply(payload)
    Check(ok and report.snapshot and report.fontFallback == not fonts, "apply reports fallback capability and rollback state")
    Check(MSUF_DB == db and MSUF_DB.general == general and MSUF_ActiveProfile == "Current", "apply retains profile identity")
    Check(general.unrelated == "keep" and MSUF_DB.player.width == 211, "unrelated settings survive")
    Check(general.kickReadyStyle == "box" and general.castbarTexture == "Global Texture"
        and general.castbarOutlineThickness == 3 and general.kickReadyShowTarget == true, "other castbars are untouched")
    Check(general.kickReadyShowNameplates == true, "nameplate switch applied")
    Check(not fonts or MSUF_DB.nameplates.interrupt == nil, "imported interrupt look is not stored for nameplates")
    Check(not fonts or MSUF_DB.nameplates.fontKey == "FRIZQT" and MSUF_DB.nameplates.fontSize == 23, "native typography stored in its scope")
    Check(fonts or MSUF_DB.nameplates == nil, "legacy host leaves typography storage to Suite")
    Check(Settings.InterruptView == nil, "nameplates have no interrupt look of their own")
    Check(Settings.Apply(report.snapshot), "caller rollback applies")
    Check(Fields.Equal(MSUF_DB, before), "caller rollback restores sparse scoped data")

    failRefresh = true
    local failed, reason = Settings.Apply(payload)
    Check(not failed and reason == "failed", "refresh failure reports cleanly")
    Check(Fields.Equal(MSUF_DB, before), "failed apply and failing restore repaint preserve data")
    failRefresh, combat = false, true
    failed, reason = Settings.Apply(payload)
    Check(not failed and reason == "combat" and Fields.Equal(MSUF_DB, before), "combat edge refuses before writes")
end

Reset(true)
MSUF_DB.nameplates = { fontOverride = true, fontKey = "FRIZQT", noOutline = true,
    fontShadowStrength = "SOFT", nameMaxChars = 9, nameClipSide = "RIGHT", nameNoEllipsis = true,
    nameColorMode = "CUSTOM", nameColorR = 0.2, nameColorG = 0.3, nameColorB = 0.4 }
local effective = Settings.Capture()
Check(effective.nameplates.fontKey == "FRIZQT" and effective.nameplates.noOutline, "capture scope override")
Check(effective.nameplates.fontShadowOpacity == 0.55 and effective.nameplates.fontShadowStrength == nil, "legacy shadow canonicalized")
Check(effective.nameplates.shortenNameMaxChars == 9 and not effective.nameplates.shortenNameShowDots, "legacy name shortening canonicalized")
Check(effective.nameplates.nameColorR == 0.2 and not effective.nameplates.nameClassColor, "custom name color resolves completely")
MSUF_DB.nameplates.nameFormat = "SHORT"
effective = Settings.Capture()
Check(effective.nameplates.nameFormat == "CUT" and effective.nameplates.shortenNameMaxChars == 10
    and effective.nameplates.shortenNameShowDots == false, "legacy fixed name preset is captured by its effective appearance")

MSUF_DB.general.boldText, MSUF_DB.general.nameColorMode = true, "CUSTOM"
MSUF_DB.general.nameColorR = 0.2
MSUF_DB.nameplates = { fontOverride = true, noOutline = false }
effective = Settings.Capture()
Check(not effective.nameplates.boldText and not effective.nameplates.noOutline, "scoped outline selection replaces the inherited outline group")
Check(effective.nameplates.nameColorMode ~= "CUSTOM", "custom font scope does not inherit the global custom name mode")
MSUF_DB.nameplates.nameColorMode = "CUSTOM"
effective = Settings.Capture()
Check(effective.nameplates.nameColorR == 1, "missing scoped custom color channel uses its native default")

MSUF_DB.general.castbarTexture = ""
effective = Settings.Capture()
Check(effective and effective.general.castbarTexture == nil and effective.nameplates.fontSize,
    "invalid legacy texture does not discard the complete capture")

-- A profile from an earlier 7.0 build still carries the retired nameplate look.
Reset(true)
MSUF_DB.nameplates = { interrupt = { kickReadyStyle = "fill", kickReadySize = 31 } }
local legacyBefore = Fields.Copy(MSUF_DB)
Check(Settings.Capture().general.kickReadyStyle == nil and Fields.Equal(MSUF_DB, legacyBefore),
    "capture neither reads nor rewrites the retired nameplate look")
failRefresh = true
Check(not Settings.Apply({ version = 1, general = { kickReadyShowNameplates = true } }) and Fields.Equal(MSUF_DB, legacyBefore),
    "failed apply keeps the profile byte for byte")
failRefresh = false
Check(Settings.Apply({ version = 1, general = { kickReadyShowNameplates = true, kickReadyStyle = "box" } }), "legacy profile applies")
Check(MSUF_DB.nameplates == nil and MSUF_DB.general.kickReadyStyle == "box" and MSUF_DB.general.kickReadyShowNameplates == true,
    "successful apply drops the retired nameplate look and leaves the castbar menu's")
Reset(true)
MSUF_DB.nameplates = { fontOverride = true, fontSize = 19, interrupt = { kickReadyStyle = "fill" } }
refreshes = 0
Check(Settings.Apply({ version = 1, general = { kickReadyStyle = "fill" }, clear = { "general.kickReadySize" } }) and refreshes == 0,
    "retired look fields change nothing and repaint nothing")
Check(MSUF_DB.nameplates.interrupt == nil and MSUF_DB.nameplates.fontSize == 19 and MSUF_DB.general.kickReadyStyle == "box",
    "dropping the retired look keeps nameplate typography")

Reset(false)
MSUF_DB.general.boldText, MSUF_DB.general.fontShadowOpacity = true, 0.55
MSUF_DB.general.nameColorMode, MSUF_DB.general.nameClassColor = "CUSTOM", true
local typographyBefore = Fields.Copy(MSUF_DB)
local typography = Settings.ResolveTypography({ fontSize = 21 })
Check(typography.fontSize == 21 and typography.nameFontSize == 18 and typography.boldText,
    "legacy host resolves partial font inheritance")
Check(typography.fontShadowOpacity == 0.55 and typography.nameColorMode == "CLASS",
    "partial scope preserves shadow and uses scoped name-color rules")
typography = Settings.ResolveTypography({ noOutline = false, fontColorR = 0.2 })
Check(not typography.boldText and not typography.noOutline and typography.fontColorG == 1 and typography.fontColorB == 1,
    "outline and RGB overrides replace complete native groups")
typography = Settings.ResolveTypography({ fontColorG = 0.2 })
Check(typography.fontColorG == 1, "green-only override does not activate a custom native RGB group")
Check(Fields.Equal(MSUF_DB, typographyBefore), "typography resolution does not change host storage")
Check(Settings.ResolveTypography({ unrelated = true }) == nil, "typography resolver rejects unknown fields")

for _, payload in ipairs({ { version = 2 }, { general = { unrelated = true } },
    { general = { kickReadyStyle = "bad" } }, { nameplates = { fontSize = 0 / 0 } },
    { nameplates = { fontSize = 201 } }, { nameplates = { fontSize = -1 } },
    { nameplates = { fontTextAlpha = math.huge } }, { general = { kickReadyColor = { 0, 1 } } },
    { clear = { "general.kickReadyShowTarget" } }, { general = { kickReadySize = 10 }, clear = { "general.kickReadySize" } },
    { clear = { [2] = "general.kickReadySize" } }, { clear = { "general.kickReadySize", "general.kickReadySize" } } }) do
    local normalized, reason = Settings.Normalize(payload)
    Check(normalized == nil and reason == "invalid", "invalid or out-of-scope payload refused")
end
local legacy = Settings.Normalize({ general = { kickReadyColor = { ["1"] = 0.2, ["2"] = 0.3, ["3"] = 0.4 } } })
Check(legacy.general.kickReadyColor[1] == 0.2 and legacy.general.kickReadyColor[4] == 1, "legacy keyed colors normalized")
Check(Settings.Normalize(nil) == nil, "old exports can omit shared settings")

local stop = Secrets.Watch(source, { strict = true })
for _, kind in ipairs({ "number", "string", "boolean", "table" }) do
    local secret = Secrets.New(kind)
    Check(Settings.Normalize(secret) == nil, "secret payload refused")
    Check(Settings.Normalize({ version = secret }) == nil, "secret version refused")
    Check(Settings.Normalize({ general = { [secret] = true } }) == nil, "secret field key refused")
    Check(Settings.Normalize({ nameplates = { fontSize = secret } }) == nil, "secret field value refused")
    Check(Settings.Normalize({ general = { kickReadyColor = { secret, 0, 0 } } }) == nil, "secret color refused")
    Check(Settings.Normalize({ clear = { secret } }) == nil, "secret reset path refused")
end
local violations = stop()
Check(#violations == 0, table.concat(violations, "\n"))
print("nameplate settings smoke: " .. checks .. " checks passed")
