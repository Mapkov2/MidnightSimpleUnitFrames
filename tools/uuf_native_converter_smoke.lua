-- Contract smoke for the native-only UnhaltedUnitFrames V12.1 -> MSUF 5.7
-- converter. This test intentionally inspects converted data, not production
-- implementation strings or importer-only runtime hooks.
--
-- Run from the repository root with Lua 5.1:
--   lua tools/uuf_native_converter_smoke.lua

local scriptPath = (arg and arg[0] or ""):gsub("\\", "/")
local scriptDir = scriptPath:match("^(.*[/])") or ""
local repoRoot = scriptDir:gsub("tools/$", "")
if repoRoot == "" then repoRoot = "." end
local addonRoot = repoRoot .. "/MidnightSimpleUnitFrames"

local function LoadAddonFile(relativePath, ...)
    local path = addonRoot .. "/" .. relativePath
    local chunk, why = loadfile(path)
    if not chunk then error("cannot load " .. path .. ": " .. tostring(why), 2) end
    return chunk(...)
end

_G.strmatch = string.match
LoadAddonFile("Libs/LibStub/LibStub.lua")
LoadAddonFile("Libs/AceSerializer-3.0/AceSerializer-3.0.lua")
LoadAddonFile("Libs/LibDeflate/LibDeflate.lua")

local ns = {}
LoadAddonFile("Foundation/MSUF_UUFImport.lua", "MidnightSimpleUnitFrames", ns)

local Import = assert(ns.MSUF_UUFImport, "MSUF_UUFImport was not registered")
local AceSerializer = assert(LibStub:GetLibrary("AceSerializer-3.0"))
local LibDeflate = assert(LibStub:GetLibrary("MSUF-LibDeflate-Bounded"))

local checks = 0
local failures = {}

local function Describe(value)
    if type(value) == "string" then return string.format("%q", value) end
    return tostring(value)
end

local function Check(ok, label, actual, expected)
    checks = checks + 1
    if ok then return end
    failures[#failures + 1] = string.format(
        "%s: expected %s, got %s",
        tostring(label), Describe(expected), Describe(actual)
    )
end

local function Equal(actual, expected, label)
    Check(actual == expected, label, actual, expected)
end

local function Truthy(value, label)
    Check(not not value, label, value, true)
end

local function Near(actual, expected, label, epsilon)
    epsilon = epsilon or 0.000001
    Check(
        type(actual) == "number" and math.abs(actual - expected) <= epsilon,
        label, actual, expected
    )
end

local function DeepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, child in pairs(value) do
        copy[DeepCopy(key, seen)] = DeepCopy(child, seen)
    end
    return copy
end

local function DeepEqual(left, right, seen)
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return left == right end
    seen = seen or {}
    if seen[left] == right then return true end
    seen[left] = right
    for key, value in pairs(left) do
        if not DeepEqual(value, right[key], seen) then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
end

local function CountKeys(value)
    local count = 0
    if type(value) == "table" then
        for _ in pairs(value) do count = count + 1 end
    end
    return count
end

local function At(root, path)
    local value = root
    for key in path:gmatch("[^.]+") do
        if type(value) ~= "table" then return nil end
        value = value[key]
    end
    return value
end

local function EqualAt(root, path, expected)
    Equal(At(root, path), expected, path)
end

local function NearAt(root, path, expected)
    Near(At(root, path), expected, path)
end

local function DeepEqualAt(left, right, path, label)
    local leftValue, rightValue = At(left, path), At(right, path)
    Check(
        DeepEqual(leftValue, rightValue),
        label or ("sparse/default parity: " .. path),
        leftValue,
        rightValue
    )
end

local function ComparePaths(left, right, paths, labelPrefix)
    for index = 1, #paths do
        local path = paths[index]
        DeepEqualAt(left, right, path, (labelPrefix or "") .. path)
    end
end

local function ReportContains(report, bucket, fragment, label)
    local values = type(report) == "table" and report[bucket] or nil
    local found = false
    if type(values) == "table" then
        for index = 1, #values do
            if tostring(values[index]):find(fragment, 1, true) then
                found = true
                break
            end
        end
    end
    Truthy(found, label or (bucket .. " report contains " .. fragment))
end

local function Finish()
    if #failures > 0 then
        error(string.format(
            "uuf_native_converter_smoke: FAILED (%d/%d checks)\n- %s",
            #failures, checks, table.concat(failures, "\n- ")
        ), 0)
    end
    print(string.format("uuf_native_converter_smoke: OK (%d checks)", checks))
end

local function EncodeSerialized(serialized)
    local compressed = assert(LibDeflate:CompressDeflate(serialized))
    return "!UUF_" .. assert(LibDeflate:EncodeForPrint(compressed))
end

local function EncodeProfile(profile)
    return EncodeSerialized(AceSerializer:Serialize({profile = profile}))
end

local function ExpectDecodeFailure(value, expectedFragment, label)
    local decoded, why = Import.Decode(value)
    Equal(decoded, nil, label .. " output")
    Truthy(
        type(why) == "string" and why:lower():find(expectedFragment:lower(), 1, true),
        label .. " reason contains " .. expectedFragment
    )
end

local function Tag(token, point, relativePoint, x, y, size, color)
    return {
        Tag = token or "",
        FontSize = size or 12,
        Layout = {point or "CENTER", relativePoint or point or "CENTER", x or 0, y or 0},
        Colour = color or {1, 1, 1, 1},
    }
end

local function Tags(one, two, three, four, five)
    return {
        TagOne = one or Tag(""),
        TagTwo = two or Tag(""),
        TagThree = three or Tag(""),
        TagFour = four or Tag(""),
        TagFive = five or Tag(""),
    }
end

-- Decode contract: exact shipped codecs, bounded input/output, useful errors.
Truthy(Import.IsImportString("  !UUF_test"), "prefix recognition")
local sparseWire = EncodeProfile({General = {}})
local sparseDecoded, sparseWhy = Import.Decode(sparseWire)
Truthy(type(sparseDecoded) == "table", "valid V12 wire decodes: " .. tostring(sparseWhy))
ExpectDecodeFailure("MSUF_not-uuf", "not an UnhaltedUnitFrames string", "wrong prefix")
ExpectDecodeFailure("!UUF_", "empty", "empty payload")
ExpectDecodeFailure("!UUF_%%%", "decode", "invalid print-safe payload")
ExpectDecodeFailure("!UUF_" .. string.rep("A", 64 * 1024 + 1), "too large", "encoded limit")

local bomb = {General = {Padding = string.rep("A", 1024 * 1024 + 256)}}
ExpectDecodeFailure(EncodeProfile(bomb), "decompressed UUF payload is too large", "decoded limit")

local deepProfile = {General = {}}
local cursor = deepProfile
for _ = 1, 70 do
    cursor.child = {}
    cursor = cursor.child
end
ExpectDecodeFailure(EncodeProfile(deepProfile), "nesting is too deep", "table depth limit")

-- Sparse exports are legal UUF profiles: AceDB omits values which still equal
-- the shipped defaults. Keep the relevant V12.1 defaults embedded here so the
-- converter cannot silently depend on a local UUF installation or Defaults.lua.
local UUF_BULLET = "\226\128\162"
local UUF_GUILLEMET = "\194\187"

local function UUFDefaultHealPrediction()
    return {
        IncomingHeal = {
            Enabled = false,
            UseStripedTexture = false,
            MatchParentHeight = true,
            Colour = {0.25, 1, 0.25, 1},
            Position = "RIGHT",
            Height = 40,
        },
        Absorbs = {
            Enabled = true,
            ShowOverAbsorb = true,
            UseStripedTexture = false,
            MatchParentHeight = true,
            Colour = {0.5, 0.75, 1, 0.8},
            Position = "ATTACH",
            Height = 40,
        },
        HealAbsorbs = {
            Enabled = true,
            UseStripedTexture = false,
            MatchParentHeight = true,
            Colour = {0.5, 0.25, 1, 1},
            Position = "ATTACH",
            Height = 40,
        },
    }
end

local function UUFDefaultCastbar(enabled)
    return {
        Enabled = enabled,
        Width = 244,
        Height = 24,
        Layout = {"TOPLEFT", "BOTTOMLEFT", 0, -1},
        MatchParentWidth = true,
        Icon = {Enabled = true, Position = "LEFT"},
        Text = {
            SpellName = {
                Enabled = true,
                FontSize = 12,
                Layout = {"LEFT", "LEFT", 3, 0},
                Colour = {1, 1, 1, 1},
                MaxChars = 15,
            },
            Duration = {
                Enabled = true,
                FontSize = 12,
                Layout = {"RIGHT", "RIGHT", -3, 0},
                Colour = {1, 1, 1, 1},
            },
        },
    }
end

local function UUFDefaultPrivateAuras()
    return {
        Enabled = true,
        Layout = {"CENTER", "CENTER", 0, 0},
        Size = 32,
        Spacing = 1,
        GrowthX = "LEFT",
        GrowthY = "UP",
        InitialAnchor = "CENTER",
        Num = 1,
        DisableCooldown = false,
        DisableCooldownText = false,
    }
end

local function UUFDefaultGroupIndicators(isRaid)
    return {
        RaidTargetMarker = {
            Enabled = true,
            Size = 24,
            Layout = {"CENTER", "CENTER", 0, 0},
        },
        Role = {
            Enabled = not isRaid,
            ShowTank = true,
            ShowHealer = true,
            ShowDamager = not isRaid,
            Size = isRaid and 12 or 16,
            Layout = isRaid
                and {"TOPRIGHT", "TOPRIGHT", -3, -3}
                or {"TOPLEFT", "TOPLEFT", 1, 0},
        },
        Phase = {
            Enabled = false,
            Size = isRaid and 12 or 16,
            Layout = {"CENTER", "CENTER", 0, 0},
        },
        Summon = {
            Enabled = true,
            Size = 24,
            Layout = {"CENTER", "CENTER", 0, 0},
        },
        ReadyCheckIndicator = {
            Enabled = true,
            Size = 24,
            Layout = {"CENTER", "CENTER", 0, 0},
        },
        ResurrectIndicator = {
            Enabled = true,
            Size = isRaid and 18 or 24,
            Layout = {"CENTER", "CENTER", 0, 0},
        },
        LeaderAssistantIndicator = {
            Enabled = false,
            Size = isRaid and 14 or 16,
            Layout = isRaid
                and {"TOPRIGHT", "TOPRIGHT", -3, -3}
                or {"RIGHT", "TOPRIGHT", -3, 0},
        },
        Target = {Enabled = false, Colour = {1, 1, 1, 1}},
        Threat = {Enabled = false},
    }
end

local function UUFDefaultGroup(isRaid)
    return {
        PowerBar = {Enabled = true, Height = 1, OnlyShowHealers = true},
        Indicators = UUFDefaultGroupIndicators(isRaid),
        Auras = {PrivateAuras = UUFDefaultPrivateAuras()},
        HealPrediction = UUFDefaultHealPrediction(),
    }
end

local defaultColours = {
    Reaction = {
        [1] = {1, 0.25098040699959, 0.25098040699959},
        [2] = {1, 0.25098040699959, 0.25098040699959},
        [3] = {1, 0.50196081399918, 0.25098040699959},
        [4] = {1, 1, 0.25098040699959},
        [5] = {0.25098040699959, 1, 0.25098040699959},
        [6] = {0.25098040699959, 1, 0.25098040699959},
        [7] = {0.25098040699959, 1, 0.25098040699959},
        [8] = {0.25098040699959, 1, 0.25098040699959},
    },
    Power = {
        [0] = {0.25098040699959, 0.50196081399918, 1},
        [1] = {1, 0, 0},
        [2] = {1, 0.5, 0.25},
        [3] = {1, 1, 0},
        [6] = {0, 0.82, 1},
        [8] = {0.75, 0.52, 0.9},
        [11] = {0, 0.5, 1},
        [13] = {0.4, 0, 0.8},
        [17] = {0.79, 0.26, 0.99},
        [18] = {1, 0.61, 0},
    },
    SecondaryPower = {
        [4] = {1, 0.96, 0.41},
        [5] = {0.5, 0.5, 0.5},
        [7] = {0.58, 0.51, 0.79},
        [9] = {0.95, 0.9, 0.6},
        [12] = {0.71, 1, 0.92},
        [16] = {0.41, 0.8, 0.94},
        [19] = {0.3921568627451, 0.67843137254902, 0.8078431372549},
    },
    Dispel = {
        Magic = {0.2, 0.6, 1},
        Curse = {0.6, 0, 1},
        Disease = {0.6, 0.4, 0},
        Poison = {0, 0.6, 0},
        Bleed = {0.6, 0, 0.1},
    },
    Threat = {
        [0] = {0.69, 0.69, 0.69},
        [1] = {1, 1, 0.47},
        [2] = {1, 0.6, 0},
        [3] = {1, 0, 0},
    },
}

local explicitDefaultProfile = {
    General = {
        Separator = UUF_BULLET,
        ToTSeparator = UUF_GUILLEMET,
        UIScale = {Enabled = true, Scale = 0.53333333333333},
        Colours = defaultColours,
    },
    Units = {
        player = {
            CastBar = UUFDefaultCastbar(false),
            HealPrediction = UUFDefaultHealPrediction(),
        },
        target = {
            PowerBar = {Enabled = true, Height = 1},
            CastBar = UUFDefaultCastbar(true),
            HealPrediction = UUFDefaultHealPrediction(),
        },
        boss = {
            PowerBar = {Enabled = true, Height = 1},
            CastBar = UUFDefaultCastbar(true),
            HealPrediction = UUFDefaultHealPrediction(),
        },
        party = UUFDefaultGroup(false),
        raid = UUFDefaultGroup(true),
    },
}

local function SeededGroupDefaults()
    return {
        powerShowHealer = false,
        powerShowTank = true,
        powerShowDamager = true,
        raidMarker = false,
        roleIcon = true,
        roleIconShowTank = false,
        roleIconShowHealer = false,
        roleIconShowDPS = true,
        readyCheckIcon = false,
        summonIcon = false,
        resurrectIcon = false,
        phaseIcon = true,
        leaderIcon = true,
        assistIcon = true,
        targetIndicator = true,
        aggroEnabled = true,
        privateAuras = {enabled = false, max = 9, size = 9},
        healPredEnabled = true,
        enableAbsorbBar = false,
        healAbsorbEnabled = false,
    }
end

local sparseDefaultBase = {
    general = {
        hpTextSeparator = "SEED",
        powerTextSeparator = "SEED",
        enableHealPrediction = true,
        showSelfHealPrediction = true,
        enableAbsorbBar = false,
        healAbsorbEnabled = false,
        powerColorOverrides = {MANA = {r = 0.01, g = 0.02, b = 0.03}},
        classPowerColorOverrides = {COMBO_POINTS = {r = 0.01, g = 0.02, b = 0.03}},
    },
    targettarget = {
        totInlineSeparator = "SEED",
        totInlineCustomSeparator = "SEED",
    },
    npcColors = {enemy = {r = 0.01, g = 0.02, b = 0.03}},
    gf_party = SeededGroupDefaults(),
    gf_raid = SeededGroupDefaults(),
    gf_mythicraid = SeededGroupDefaults(),
}

local sparseDefaultOut = Import.Convert({General = {}, Units = {}}, DeepCopy(sparseDefaultBase))
local explicitDefaultOut = Import.Convert(explicitDefaultProfile, DeepCopy(sparseDefaultBase))
Truthy(type(sparseDefaultOut) == "table", "sparse-default fixture converts")
Truthy(type(explicitDefaultOut) == "table", "explicit-default fixture converts")

if type(sparseDefaultOut) == "table" and type(explicitDefaultOut) == "table" then
    ComparePaths(sparseDefaultOut, explicitDefaultOut, {
        "general.UIScale",
        "general.hpTextSeparator",
        "general.powerTextSeparator",
        "targettarget.totInlineSeparator",
        "targettarget.totInlineCustomSeparator",
        "npcColors",
        "general.powerColorOverrides",
        "general.classPowerColorOverrides",
        "general.dispelTypeMagicR", "general.dispelTypeMagicG", "general.dispelTypeMagicB",
        "general.dispelTypeCurseR", "general.dispelTypeCurseG", "general.dispelTypeCurseB",
        "general.dispelTypeDiseaseR", "general.dispelTypeDiseaseG", "general.dispelTypeDiseaseB",
        "general.dispelTypePoisonR", "general.dispelTypePoisonG", "general.dispelTypePoisonB",
        "general.dispelTypeBleedR", "general.dispelTypeBleedG", "general.dispelTypeBleedB",
        "general.hlAggroColorR", "general.hlAggroColorG", "general.hlAggroColorB",
        "general.enableHealPrediction",
        "general.showSelfHealPrediction",
        "general.enableAbsorbBar",
        "general.healAbsorbEnabled",
        "general.healPredColorR", "general.healPredColorG", "general.healPredColorB",
        "general.absorbBarColorR", "general.absorbBarColorG", "general.absorbBarColorB", "general.absorbBarColorA",
        "general.healAbsorbBarColorR", "general.healAbsorbBarColorG", "general.healAbsorbBarColorB", "general.healAbsorbBarColorA",
    }, "sparse general parity: ")

    local castbarPaths = {
        "enablePlayerCastbar", "castbarPlayerBarWidth", "castbarPlayerBarHeight",
        "castbarPlayerOffsetX", "castbarPlayerOffsetY", "castbarPlayerMatchWidth", "castbarPlayerDetached",
        "enableTargetCastbar", "castbarTargetBarWidth", "castbarTargetBarHeight",
        "castbarTargetOffsetX", "castbarTargetOffsetY", "castbarTargetMatchWidth", "castbarTargetDetached",
        "enableBossCastbar", "bossCastbarWidth", "bossCastbarHeight",
        "bossCastbarOffsetX", "bossCastbarOffsetY", "bossCastbarMatchWidth", "bossCastbarDetached",
    }
    for index = 1, #castbarPaths do
        castbarPaths[index] = "general." .. castbarPaths[index]
    end
    ComparePaths(sparseDefaultOut, explicitDefaultOut, castbarPaths, "sparse castbar parity: ")

    local groupFields = {
        "powerBarEnabled", "powerHeight", "powerShowHealer", "powerShowTank", "powerShowDamager",
        "raidMarker", "raidMarkerSize", "raidMarkerAnchor", "raidMarkerX", "raidMarkerY",
        "roleIcon", "roleIconSize", "roleIconAnchor", "roleIconX", "roleIconY",
        "roleIconShowTank", "roleIconShowHealer", "roleIconShowDPS",
        "readyCheckIcon", "readyCheckSize", "readyCheckAnchor", "readyCheckX", "readyCheckY",
        "summonIcon", "summonIconSize", "summonAnchor", "summonX", "summonY",
        "resurrectIcon", "resurrectIconSize", "resurrectAnchor", "resurrectX", "resurrectY",
        "phaseIcon", "phaseIconSize", "phaseAnchor", "phaseX", "phaseY",
        "leaderIcon", "leaderIconSize", "leaderIconAnchor", "leaderIconX", "leaderIconY",
        "assistIcon", "assistIconSize", "assistIconAnchor", "assistIconX", "assistIconY",
        "targetIndicator", "aggroEnabled", "privateAuras",
        "healPredEnabled", "enableAbsorbBar", "healAbsorbEnabled",
    }
    for _, groupKey in ipairs({"gf_party", "gf_raid", "gf_mythicraid"}) do
        local paths = {}
        for index = 1, #groupFields do paths[index] = groupKey .. "." .. groupFields[index] end
        ComparePaths(sparseDefaultOut, explicitDefaultOut, paths, "sparse group parity: ")
    end

    EqualAt(sparseDefaultOut, "general.hpTextSeparator", UUF_BULLET)
    EqualAt(sparseDefaultOut, "general.powerTextSeparator", UUF_BULLET)
    EqualAt(sparseDefaultOut, "targettarget.totInlineSeparator", "__CUSTOM__")
    EqualAt(sparseDefaultOut, "targettarget.totInlineCustomSeparator", UUF_GUILLEMET)
    Equal(CountKeys(sparseDefaultOut.general.powerColorOverrides), 10, "all default UUF power colors")
    Equal(
        CountKeys(sparseDefaultOut.general.classPowerColorOverrides),
        8,
        "seven UUF class-power colors plus the default alternative-mana color"
    )
    NearAt(sparseDefaultOut, "npcColors.enemy.g", 0.25098040699959)
    NearAt(sparseDefaultOut, "npcColors.neutral.g", 1)
    NearAt(sparseDefaultOut, "npcColors.friendly.r", 0.25098040699959)
    NearAt(sparseDefaultOut, "general.dispelTypeMagicB", 1)
    NearAt(sparseDefaultOut, "general.hlAggroColorR", 1)
    NearAt(sparseDefaultOut, "general.hlAggroColorG", 0)
    NearAt(sparseDefaultOut, "general.hlAggroColorB", 0)

    EqualAt(sparseDefaultOut, "target.showPowerBar", true)
    EqualAt(sparseDefaultOut, "target.showPower", false)
    EqualAt(sparseDefaultOut, "target.showPowerText", false)
    EqualAt(sparseDefaultOut, "general.enableTargetCastbar", true)
    EqualAt(sparseDefaultOut, "general.castbarTargetOffsetX", 0)
    EqualAt(sparseDefaultOut, "general.castbarTargetOffsetY", -67)
    EqualAt(sparseDefaultOut, "general.enableBossCastbar", true)
    EqualAt(sparseDefaultOut, "general.bossCastbarOffsetX", 0)
    EqualAt(sparseDefaultOut, "general.bossCastbarOffsetY", -79)
    EqualAt(sparseDefaultOut, "general.enableHealPrediction", false)
    EqualAt(sparseDefaultOut, "general.enableAbsorbBar", true)
    EqualAt(sparseDefaultOut, "general.healAbsorbEnabled", true)

    EqualAt(sparseDefaultOut, "gf_party.powerShowHealer", true)
    EqualAt(sparseDefaultOut, "gf_party.powerShowTank", false)
    EqualAt(sparseDefaultOut, "gf_party.powerShowDamager", false)
    EqualAt(sparseDefaultOut, "gf_party.roleIcon", true)
    EqualAt(sparseDefaultOut, "gf_party.roleIconShowDPS", true)
    EqualAt(sparseDefaultOut, "gf_party.privateAuras.enabled", true)
    EqualAt(sparseDefaultOut, "gf_party.privateAuras.max", 1)
    EqualAt(sparseDefaultOut, "gf_party.privateAuras.size", 32)
    EqualAt(sparseDefaultOut, "gf_party.privateAuras.direction", "LEFT")
    EqualAt(sparseDefaultOut, "gf_raid.roleIcon", false)
    EqualAt(sparseDefaultOut, "gf_raid.roleIconShowDPS", false)
    EqualAt(sparseDefaultOut, "gf_raid.resurrectIconSize", 18)
    EqualAt(sparseDefaultOut, "gf_raid.privateAuras.enabled", true)
end

-- One representative V12 profile deliberately combines the real Default
-- geometry/text layout with exact native mappings and a few unsupported source
-- semantics which must be documented in the report.
local profile = {
    General = {
        UIScale = {Enabled = true, Scale = 0.625},
        Textures = {Foreground = "Better Blizzard", Background = "Better Blizzard"},
        Fonts = {
            Font = "Friz Quadrata TT",
            FontFlag = "OUTLINE, MONOCHROME",
            Shadow = {Enabled = false, Colour = {0, 0, 0, 1}, XPos = 0, YPos = 0},
        },
        Colours = {
            Power = {[0] = {0.12, 0.34, 0.56, 1}},
        },
        CooldownText = {Advanced = false, FontSize = 12, Layout = {"CENTER", "CENTER", 0, 0}},
    },
    Units = {
        player = {
            Enabled = true,
            Frame = {Width = 244, Height = 42, Layout = {"BOTTOM", "CENTER", -190, -170}},
            HealthBar = {
                ColourByClass = true,
                Background = {0.08, 0.09, 0.10, 1},
                BackgroundOpacity = 1,
            },
            Indicators = {
                Resting = {
                    Enabled = true, Size = 16,
                    Layout = {"TOPLEFT", "TOPLEFT", 3, -3},
                },
                Combat = {
                    Enabled = true, Size = 16,
                    Layout = {"TOPLEFT", "TOPLEFT", 3, -3},
                },
            },
            Tags = Tags(Tag("[name]", "LEFT", "LEFT", 3, 0, 12)),
        },
        target = {
            Enabled = true,
            Frame = {Width = 244, Height = 42, Layout = {"LEFT", "RIGHT", 20, 0}},
            HealthBar = {ColourByClass = true, Background = {0.08, 0.09, 0.10, 1}},
            PowerBar = {Enabled = true, Height = 3, Position = "BOTTOM", ColourByType = true},
            Tags = Tags(
                Tag("[name]", "LEFT", "LEFT", 3, 0, 12),
                Tag("[curhp:abbr]", "RIGHT", "RIGHT", -3, 0, 12),
                Tag("[curpp]", "RIGHT", "BOTTOMRIGHT", -3, 2, 12)
            ),
            Indicators = {
                RaidTargetMarker = {
                    Enabled = true, Size = 24,
                    Layout = {"CENTER", "CENTER", 0, 0},
                },
                LeaderAssistantIndicator = {
                    Enabled = true, Size = 16,
                    Layout = {"TOPLEFT", "TOPLEFT", 3, -3},
                },
                Classification = {
                    Enabled = true, Size = 24,
                    Layout = {"RIGHT", "TOPRIGHT", -3, 0},
                    Texture = "CLASSIFICATION2",
                },
            },
            Portrait = {
                Enabled = true, Width = 42, Height = 42,
                Layout = {"LEFT", "RIGHT", 1, 0}, Style = "3D", Zoom = 0.4,
            },
            CastBar = {
                Enabled = true, Width = 244, Height = 20,
                Layout = {"TOPLEFT", "BOTTOMLEFT", 0, -1}, MatchParentWidth = true,
                ShowTarget = true, FrameStrata = "HIGH",
                Icon = {Enabled = true, Position = "LEFT"},
                Text = {
                    SpellName = {Enabled = true, FontSize = 13, Layout = {"LEFT", "LEFT", 3, 0}},
                    Duration = {Enabled = true, FontSize = 12, Layout = {"RIGHT", "RIGHT", -3, 0}},
                },
            },
            HealPrediction = {
                IncomingHeal = {
                    Enabled = true, Position = "RIGHT", Colour = {0.25, 1, 0.25, 1},
                    UseStripedTexture = true,
                },
                Absorbs = {Enabled = true, Position = "ATTACH", Colour = {0.5, 0.75, 1, 0.8}},
                HealAbsorbs = {Enabled = true, Position = "ATTACH", Colour = {0.5, 0.25, 1, 1}},
            },
            Auras = {
                Buffs = {
                    Enabled = true, Size = 19, Num = 5, Wrap = 5, Spacing = 2,
                    Layout = {"BOTTOMLEFT", "TOPLEFT", 0, 1, 1}, GrowthDirection = "RIGHT",
                    OnlyShowPlayer = true,
                },
                Debuffs = {
                    Enabled = true, Size = 21, Num = 4, Wrap = 4, Spacing = 1,
                    Layout = {"BOTTOMRIGHT", "TOPRIGHT", 0, 1, 1}, GrowthDirection = "LEFT",
                },
                AuraDuration = {FontSize = 12, Layout = {"CENTER", "CENTER", 0, 0}},
            },
        },
        focus = {
            Enabled = true,
            Frame = {Width = 122, Height = 22, Layout = {"BOTTOM", "TOPLEFT", 0, 110}},
            CastBar = {
                Enabled = true, Width = 122, Height = 14,
                Layout = {"TOPLEFT", "BOTTOMLEFT", 2, -3}, MatchParentWidth = true,
            },
            Tags = Tags(Tag("[name]", "LEFT", "LEFT", 3, 0, 12)),
        },
        boss = {
            Enabled = true,
            Frame = {Width = 244, Height = 42, Layout = {"CENTER", "CENTER", 550, 0, 26}},
            Indicators = {
                Classification = {
                    Enabled = true, Size = 22,
                    Layout = {"RIGHT", "TOPRIGHT", -3, 0},
                },
            },
            CastBar = {
                Enabled = true, Width = 244, Height = 16,
                Layout = {"TOPLEFT", "BOTTOMLEFT", 4, -2}, MatchParentWidth = true,
            },
            Tags = Tags(Tag("[name]", "LEFT", "LEFT", 3, 0, 12)),
        },
        party = {
            Enabled = true,
            Frame = {
                Width = 244, Height = 52, Layout = {"CENTER", "CENTER", -550, 0, 1},
                GrowthDirection = "DOWN", SortMethod = "ROLE",
                RoleOrder = {"TANK", "HEALER", "DAMAGER"}, ShowPlayer = false,
            },
            PowerBar = {Enabled = true, Height = 3, OnlyShowHealers = true},
            Tags = Tags(
                Tag("[name]", "TOPLEFT", "TOPLEFT", 16, -3, 12),
                Tag("[perhp-with-sign]", "TOPRIGHT", "TOPRIGHT", -3, -3, 12)
            ),
            HealPrediction = {
                IncomingHeal = {Enabled = true, Position = "RIGHT", Colour = {0.25, 1, 0.25, 1}},
                Absorbs = {Enabled = true, Position = "ATTACH", Colour = {0.5, 0.75, 1, 0.8}},
                HealAbsorbs = {Enabled = true, Position = "ATTACH", Colour = {0.5, 0.25, 1, 1}},
            },
            Auras = {
                Buffs = {
                    Enabled = true, Size = 20, Num = 3, Wrap = 3, Spacing = 1,
                    Layout = {"BOTTOMLEFT", "BOTTOMLEFT", 1, 1, 1},
                    GrowthDirection = "RIGHT", Filters = {Raid = true},
                },
                Debuffs = {
                    Enabled = true, Size = 22, Num = 4, Wrap = 4, Spacing = 2,
                    Layout = {"BOTTOMRIGHT", "BOTTOMRIGHT", -1, 1, 1},
                    GrowthDirection = "LEFT", Filters = {RaidPlayer = true},
                },
                PrivateAuras = {
                    Enabled = true, Num = 2, Size = 18, Spacing = 3,
                    Layout = {"CENTER", "CENTER", 4, -5}, GrowthX = "RIGHT", GrowthY = "UP",
                },
            },
        },
        raid = {
            Enabled = true,
            Frame = {
                Width = 90, Height = 52, Layout = {"LEFT", "LEFT", 1, 0, 1},
                GrowthDirection = "LEFT_DOWN", AutoAdjustGroups = true, ShowPlayer = true,
            },
            Tags = Tags(
                Tag("[name]", "TOPLEFT", "TOPLEFT", 3, -3, 12),
                Tag("[status]", "TOPRIGHT", "TOPRIGHT", -3, -3, 12)
            ),
            Auras = {
                Buffs = {Enabled = true, Size = 18, Num = 1, Wrap = 1, Layout = {"BOTTOMLEFT", "BOTTOMLEFT", 1, 1}},
                Debuffs = {Enabled = true, Size = 20, Num = 2, Wrap = 2, Layout = {"BOTTOMRIGHT", "BOTTOMRIGHT", -1, 1}},
            },
        },
    },
}

local base = {
    msufOnlySentinel = {value = "keep-root", nested = {answer = 42}},
    general = {msufOnlyGeneral = "keep-general"},
    target = {
        msufOnlyTarget = {value = "keep-target"},
        showClassificationIndicator = true,
    },
    boss = {showClassificationIndicator = true},
    gf_mythicraid = {msufOnlyMythic = "keep-mythic"},
}
local baseBefore = DeepCopy(base)
local wire = EncodeProfile(profile)

Equal(type(Import.ConvertString), "function", "converter API")
if type(Import.ConvertString) ~= "function" then Finish() end

local callOK, output, report = pcall(Import.ConvertString, wire, base)
Truthy(callOK, "ConvertString does not throw")
Truthy(type(output) == "table", "ConvertString returns profile: " .. tostring(output))
Truthy(type(report) == "table", "ConvertString returns report: " .. tostring(report))
if type(output) ~= "table" then Finish() end

-- Base profile is copied, never mutated or aliased.
Truthy(DeepEqual(base, baseBefore), "base profile remains byte-semantically unchanged")
Truthy(output ~= base, "converted profile is a new root table")
EqualAt(output, "msufOnlySentinel.value", "keep-root")
EqualAt(output, "msufOnlySentinel.nested.answer", 42)
EqualAt(output, "general.msufOnlyGeneral", "keep-general")
EqualAt(output, "target.msufOnlyTarget.value", "keep-target")
EqualAt(output, "gf_mythicraid.msufOnlyMythic", "keep-mythic")
Truthy(output.msufOnlySentinel ~= base.msufOnlySentinel, "MSUF-only sentinel is deep-copied")

-- Alpha translation is cold-path only, but it must overwrite stale MSUF base
-- values and preserve UUF's distinct health-fill, health-track, in-range and
-- out-of-range opacity semantics as closely as the native schema permits.
local function AlphaUnit()
    return {
        HealthBar = {
            ForegroundOpacity = 0.65,
            BackgroundOpacity = 0.35,
        },
    }
end

local alphaProfile = {
    General = {
        Range = {Enabled = true, InRange = 0.8, OutOfRange = 0.4},
    },
    Units = {
        player = AlphaUnit(),
        target = AlphaUnit(),
        targettarget = AlphaUnit(),
        focus = AlphaUnit(),
        focustarget = AlphaUnit(),
        pet = AlphaUnit(),
        boss = AlphaUnit(),
        party = AlphaUnit(),
        raid = AlphaUnit(),
    },
}
local alphaBase = {
    bars = {barBackgroundAlpha = 90},
    target = {
        alphaInCombat = 0.1,
        alphaOutOfCombat = 0.2,
        alphaSync = false,
        alphaSyncBoth = false,
        alphaExcludeTextPortrait = false,
        alphaLayerMode = 0,
        alphaFGInCombat = 0.3,
        alphaBGInCombat = 0.4,
        alphaHPInCombat = 0.5,
    },
}
local alphaOutput, alphaReport = assert(Import.Convert(alphaProfile, alphaBase))
NearAt(alphaOutput, "bars.barBackgroundAlpha", 35)
NearAt(alphaOutput, "general.rangeFadeAlpha", 0.5)
NearAt(alphaOutput, "player.alphaInCombat", 1)
NearAt(alphaOutput, "player.alphaHPInCombat", 0.65)
EqualAt(alphaOutput, "player.alphaExcludeTextPortrait", true)
NearAt(alphaOutput, "target.alphaInCombat", 0.8)
NearAt(alphaOutput, "target.alphaOutOfCombat", 0.8)
NearAt(alphaOutput, "target.alphaFGInCombat", 0.8)
NearAt(alphaOutput, "target.alphaBGInCombat", 0.8)
NearAt(alphaOutput, "target.alphaHPInCombat", 0.52)
EqualAt(alphaOutput, "target.alphaSync", true)
EqualAt(alphaOutput, "target.alphaSyncBoth", true)
EqualAt(alphaOutput, "target.alphaExcludeTextPortrait", true)
EqualAt(alphaOutput, "target.alphaLayerMode", 2)
NearAt(alphaOutput, "target.rangeFadeAlpha", 0.5)
NearAt(alphaOutput, "gf_party.hpBarAlpha", 0.65)
NearAt(alphaOutput, "gf_party.hpBgAlpha", 0.35)
NearAt(alphaOutput, "gf_party.alphaInCombat", 0.8)
NearAt(alphaOutput, "gf_party.rangeFadeAlpha", 0.5)
Equal(alphaReport._rangeInAlpha, nil, "alpha converter scratch state is removed")

local defaultAlphaOutput = assert(Import.Convert({
    General = {Range = {Enabled = true, InRange = 1, OutOfRange = 0.5}},
    Units = {target = {HealthBar = {ForegroundOpacity = 1, BackgroundOpacity = 1}}},
}, {
    target = {
        alphaInCombat = 0.1,
        alphaOutOfCombat = 0.2,
        alphaSyncBoth = false,
        alphaExcludeTextPortrait = true,
        alphaLayerMode = 2,
        alphaFGInCombat = 0.3,
        alphaBGInCombat = 0.4,
        alphaHPInCombat = 0.5,
    },
}))
NearAt(defaultAlphaOutput, "target.alphaInCombat", 1)
NearAt(defaultAlphaOutput, "target.alphaOutOfCombat", 1)
NearAt(defaultAlphaOutput, "target.alphaFGInCombat", 1)
NearAt(defaultAlphaOutput, "target.alphaBGInCombat", 1)
NearAt(defaultAlphaOutput, "target.alphaHPInCombat", 1)
EqualAt(defaultAlphaOutput, "target.alphaSyncBoth", true)
EqualAt(defaultAlphaOutput, "target.alphaExcludeTextPortrait", false)
EqualAt(defaultAlphaOutput, "target.alphaLayerMode", 0)

-- Compact UUF frames commonly put name and HP into one FontString. MSUF has
-- separate native text regions, so the converter must split the composite
-- instead of dropping both values as an unsupported tag.
local compactTextOutput, compactTextReport = assert(Import.Convert({
    Units = {
        target = {
            Enabled = true,
            Tags = {
                TagOne = Tag(
                    "[name] [name:target:colour]",
                    "LEFT", "LEFT", 3, 0, 12
                ),
            },
        },
        targettarget = {
            Enabled = true,
            Frame = {Width = 122, Height = 22},
            Tags = {
                TagOne = Tag(
                    "[reactioncolour][name] | [curhpperhp:abbr]",
                    "CENTER", "CENTER", 0, 0, 12
                ),
            },
        },
    },
}, {}))
EqualAt(compactTextOutput, "targettarget.showName", true)
EqualAt(compactTextOutput, "targettarget.nameClassColor", true)
EqualAt(compactTextOutput, "targettarget.npcNameRed", true)
EqualAt(compactTextOutput, "targettarget.nameTextAnchor", "LEFT")
EqualAt(compactTextOutput, "targettarget.showHP", true)
EqualAt(compactTextOutput, "targettarget.showHPText", true)
EqualAt(compactTextOutput, "targettarget.textLeft", "NONE")
EqualAt(compactTextOutput, "targettarget.textCenter", "NONE")
EqualAt(compactTextOutput, "targettarget.textRight", "CURPERCENT")
EqualAt(compactTextOutput, "targettarget.nameFontSize", 12)
EqualAt(compactTextOutput, "targettarget.hpFontSize", 12)
EqualAt(compactTextOutput, "target.showName", true)
EqualAt(compactTextOutput, "targettarget.showToTInTargetName", true)
EqualAt(compactTextOutput, "targettarget.totInlineColorMode", "TOT_NAME")
ReportContains(
    compactTextReport,
    "approximated",
    "combined UUF name/health text uses native left-name and right-HP slots",
    "compact target-of-target composite is explicitly reported"
)

-- UUF commonly prefixes compact names with a dynamic color tag. The prefix
-- must not make either the ToT name or its separate HP value disappear.
local coloredCompactOutput = assert(Import.Convert({
    Units = {
        targettarget = {
            Enabled = true,
            Tags = {
                TagOne = Tag("[reactioncolour][name]", "LEFT", "LEFT", 3, 0, 11),
                TagTwo = Tag("[curhp:abbr]", "RIGHT", "RIGHT", -3, 0, 10),
            },
        },
    },
}, {}))
EqualAt(coloredCompactOutput, "targettarget.showName", true)
EqualAt(coloredCompactOutput, "targettarget.nameClassColor", true)
EqualAt(coloredCompactOutput, "targettarget.npcNameRed", true)
EqualAt(coloredCompactOutput, "targettarget.nameTextAnchor", "LEFT")
EqualAt(coloredCompactOutput, "targettarget.nameFontSize", 11)
EqualAt(coloredCompactOutput, "targettarget.showHP", true)
EqualAt(coloredCompactOutput, "targettarget.showHPText", true)
EqualAt(coloredCompactOutput, "targettarget.textRight", "CURRENT")
EqualAt(coloredCompactOutput, "targettarget.hpFontSize", 10)

-- Native-only invariant: no converter-private UUF key survives at any depth.
local forbidden = {}
local seen = {}
local function ScanKeys(value, path)
    if type(value) ~= "table" or seen[value] then return end
    seen[value] = true
    for key, child in pairs(value) do
        local childPath = path .. "." .. tostring(key)
        if type(key) == "string" then
            local lower = key:lower()
            if lower:match("^uuf") or lower == "_uufimport" then
                forbidden[#forbidden + 1] = childPath
            end
        end
        ScanKeys(child, childPath)
    end
end
ScanKeys(output, "profile")
Equal(#forbidden, 0, "recursive native-only key scan: " .. table.concat(forbidden, ", "))
if output.importProvenance ~= nil then
    Truthy(type(output.importProvenance) == "table", "optional provenance is generic table data")
end

-- General media, native font flags, and native colors.
EqualAt(output, "general.UIScale.Enabled", true)
NearAt(output, "general.UIScale.Scale", 0.625)
Truthy(
    output.general.UIScale.Scale >= 0.3 and output.general.UIScale.Scale <= 1.5,
    "general.UIScale.Scale stays inside the native reader range"
)
EqualAt(output, "general.fontKey", "FRIZQT")
EqualAt(output, "general.noOutline", false)
EqualAt(output, "general.boldText", false)
EqualAt(output, "general.fontMonochrome", nil)
EqualAt(output, "general.fontShadowStrength", nil)
EqualAt(output, "general.textBackdrop", false)
EqualAt(output, "general.barMode", "class")
EqualAt(output, "general.useClassColors", true)
NearAt(output, "general.classBarBgR", 0.08)
NearAt(output, "general.classBarBgG", 0.09)
NearAt(output, "general.classBarBgB", 0.10)
NearAt(output, "general.powerColorOverrides.MANA.r", 0.12)
NearAt(output, "general.powerColorOverrides.MANA.g", 0.34)
NearAt(output, "general.powerColorOverrides.MANA.b", 0.56)

-- Real Default core geometry and the native folded Bild-2 text layout.
EqualAt(output, "player.width", 244)
EqualAt(output, "player.height", 42)
EqualAt(output, "target.width", 244)
EqualAt(output, "target.height", 42)
EqualAt(output, "focus.width", 122)
EqualAt(output, "focus.height", 22)
EqualAt(output, "boss.width", 244)
EqualAt(output, "boss.height", 42)
EqualAt(output, "target.showName", true)
EqualAt(output, "target.nameTextAnchor", "LEFT")
EqualAt(output, "target.nameOffsetX", 3)
EqualAt(output, "target.nameOffsetY", -15)
EqualAt(output, "target.nameFontSize", 12)
EqualAt(output, "target.showHP", true)
EqualAt(output, "target.showHPText", true)
EqualAt(output, "target.textRight", "CURRENT")
EqualAt(output, "target.hpTextRightOffsetX", 1)
EqualAt(output, "target.hpTextRightOffsetY", -15)
EqualAt(output, "target.hpFontSize", 12)
EqualAt(output, "target.showPower", true)
EqualAt(output, "target.showPowerText", true)
EqualAt(output, "target.powerTextRight", "CURRENT")
EqualAt(output, "target.powerTextRightOffsetX", 1)
EqualAt(output, "target.powerTextRightOffsetY", -4)
EqualAt(output, "target.powerFontSize", 12)

-- UUF Classification becomes the existing elite icon, never the random BOSS
-- classification text observed in the broken import.
for _, key in ipairs({"target", "boss"}) do
    EqualAt(output, key .. ".showClassificationIndicator", false)
    EqualAt(output, key .. ".showEliteIcon", true)
    EqualAt(output, key .. ".eliteIconAnchor", "TOPRIGHT")
    EqualAt(output, key .. ".eliteIconLayer", 7)
end
EqualAt(output, "target.eliteIconSize", 24)
EqualAt(output, "target.eliteIconOffsetX", -3)
EqualAt(output, "target.eliteIconOffsetY", 0)
EqualAt(output, "target.showLeaderIcon", true)
EqualAt(output, "target.leaderIconSize", 16)
EqualAt(output, "target.leaderIconAnchor", "TOPLEFT")
EqualAt(output, "target.leaderIconOffsetX", 3)
EqualAt(output, "target.leaderIconOffsetY", -11)
EqualAt(output, "target.showRaidMarker", true)
EqualAt(output, "target.raidMarkerSize", 24)
EqualAt(output, "target.raidMarkerAnchor", "CENTER")
EqualAt(output, "target.raidMarkerOffsetX", 0)
EqualAt(output, "target.raidMarkerOffsetY", 0)

-- Combat/rest use _MSUF_AnchorCorner, which adds the native TOPLEFT inset
-- (+2, -2). The stored offsets compensate so the final reader geometry stays
-- at the original UUF (+3, -3) position.
EqualAt(output, "player.showCombatStateIndicator", true)
EqualAt(output, "player.combatStateIndicatorSize", 16)
EqualAt(output, "player.combatStateIndicatorAnchor", "TOPLEFT")
EqualAt(output, "player.combatStateIndicatorOffsetX", 1)
EqualAt(output, "player.combatStateIndicatorOffsetY", -1)
EqualAt(output, "player.showRestingIndicator", true)
EqualAt(output, "player.restedStateIndicatorSize", 16)
EqualAt(output, "player.restedStateIndicatorAnchor", "TOPLEFT")
EqualAt(output, "player.restedStateIndicatorOffsetX", 1)
EqualAt(output, "player.restedStateIndicatorOffsetY", -1)

-- Party/raid/mythic profiles use only the native GroupFrames schema.
EqualAt(output, "gf_party.width", 244)
EqualAt(output, "gf_party.height", 52)
EqualAt(output, "gf_party.positionMode", "GRID_CENTER_V1")
EqualAt(output, "gf_party.growth", "DOWN")
EqualAt(output, "gf_party.sortMode", "ROLE")
EqualAt(output, "gf_party.roleOrder", "TANK,HEALER,DAMAGER")
EqualAt(output, "gf_party.showPlayer", false)
EqualAt(output, "gf_party.nameAnchor", "LEFT")
EqualAt(output, "gf_party.nameOffsetX", 13)
EqualAt(output, "gf_party.nameOffsetY", 15.5)
EqualAt(output, "gf_party.textRight", "PERCENT")
EqualAt(output, "gf_party.hpTextRightOffsetX", 0)
EqualAt(output, "gf_party.hpTextRightOffsetY", 15.5)
EqualAt(output, "gf_raid.width", 90)
EqualAt(output, "gf_raid.height", 52)
EqualAt(output, "gf_raid.positionMode", "GRID_CENTER_V1")
EqualAt(output, "gf_raid.preserveRaidGroups", true)
EqualAt(output, "gf_raid.maxColumns", 8)
EqualAt(output, "gf_mythicraid.width", 90)
EqualAt(output, "gf_mythicraid.height", 52)
EqualAt(output, "gf_mythicraid.maxColumns", 4)
EqualAt(output, "gf_party.groupGrowth", nil)
EqualAt(output, "gf_raid.groupGrowth", nil)
EqualAt(output, "gf_mythicraid.groupGrowth", nil)
for i = 1, 8 do
    Equal(output.gf_raid.groupFilter[i], true, "gf_raid group " .. i)
    Equal(output.gf_mythicraid.groupFilter[i], i <= 4, "gf_mythicraid group " .. i)
end

-- Unit Auras2 and GroupFrames aura/private-aura native destinations.
EqualAt(output, "auras2.enabled", true)
EqualAt(output, "auras2.showTarget", true)
EqualAt(output, "auras2.perUnit.target.overrideLayout", true)
EqualAt(output, "auras2.perUnit.target.layout.buffGroupIconSize", 19)
EqualAt(output, "auras2.perUnit.target.layout.debuffGroupIconSize", 21)
EqualAt(output, "auras2.perUnit.target.layout.buffGroupOffsetY", 1)
EqualAt(output, "auras2.perUnit.target.layout.debuffGroupOffsetY", 1)
EqualAt(output, "auras2.perUnit.target.layoutShared.maxBuffs", 5)
EqualAt(output, "auras2.perUnit.target.layoutShared.maxDebuffs", 4)
EqualAt(output, "auras2.perUnit.target.layoutShared.perRow", 5)
EqualAt(output, "auras2.perUnit.target.layoutShared.buffPerRow", nil)
EqualAt(output, "auras2.perUnit.target.layoutShared.debuffPerRow", nil)
EqualAt(output, "auras2.perUnit.target.filters.buffs.onlyMine", true)
EqualAt(output, "gf_party.auras.buff.enabled", true)
EqualAt(output, "gf_party.auras.buff.size", 20)
EqualAt(output, "gf_party.auras.buff.max", 3)
EqualAt(output, "gf_party.auras.buff.filterToken", "RAID")
EqualAt(output, "gf_party.auras.debuff.enabled", true)
EqualAt(output, "gf_party.auras.debuff.size", 22)
EqualAt(output, "gf_party.privateAuras.enabled", true)
EqualAt(output, "gf_party.privateAuras.max", 2)
EqualAt(output, "gf_party.privateAuras.size", 18)
EqualAt(output, "gf_party.privateAuras.direction", "RIGHT")

-- Existing Castbar, Portrait, and HealPrediction settings own these features.
EqualAt(output, "general.enableTargetCastbar", true)
EqualAt(output, "general.castbarTargetBarWidth", 244)
EqualAt(output, "general.castbarTargetBarHeight", 20)
EqualAt(output, "general.castbarTargetMatchWidth", "unitframe")
EqualAt(output, "general.castbarTargetDetached", false)
EqualAt(output, "general.castbarTargetOffsetX", 0)
EqualAt(output, "general.castbarTargetOffsetY", -63)
EqualAt(output, "general.castbarTargetShowIcon", true)
EqualAt(output, "general.castbarTargetShowSpellName", true)
EqualAt(output, "general.showTargetCastTime", true)
EqualAt(output, "general.enableFocusCastbar", true)
EqualAt(output, "general.castbarFocusBarWidth", 122)
EqualAt(output, "general.castbarFocusBarHeight", 14)
EqualAt(output, "general.castbarFocusMatchWidth", "unitframe")
EqualAt(output, "general.castbarFocusDetached", false)
EqualAt(output, "general.castbarFocusOffsetX", 2)
EqualAt(output, "general.castbarFocusOffsetY", -39)
EqualAt(output, "general.enableBossCastbar", true)
EqualAt(output, "general.bossCastbarWidth", 244)
EqualAt(output, "general.bossCastbarHeight", 16)
EqualAt(output, "general.bossCastbarMatchWidth", "unitframe")
EqualAt(output, "general.bossCastbarDetached", false)
EqualAt(output, "general.bossCastbarOffsetX", 4)
EqualAt(output, "general.bossCastbarOffsetY", -62)
EqualAt(output, "target.portraitMode", "RIGHT")
EqualAt(output, "target.portraitRender", "2D")
EqualAt(output, "target.portraitShape", "SQUARE")
EqualAt(output, "target.portraitSizeOverride", 42)
EqualAt(output, "general.enableHealPrediction", true)
EqualAt(output, "general.enableAbsorbBar", true)
EqualAt(output, "general.healAbsorbEnabled", true)
NearAt(output, "general.healPredColorR", 0.25)
NearAt(output, "general.absorbBarColorB", 1)
NearAt(output, "general.healAbsorbBarColorR", 0.5)
EqualAt(output, "target.hlOverride", true)
EqualAt(output, "target.healPredAnchorMode", 2)
EqualAt(output, "target.absorbAnchorMode", 4)
EqualAt(output, "gf_party.healPredEnabled", true)
EqualAt(output, "gf_party.enableAbsorbBar", true)
EqualAt(output, "gf_party.healAbsorbEnabled", true)

-- Reader-level geometry contract. Load the real MSUF indicator readers and
-- feed them the converted target/player tables. This catches converter fields
-- which look plausible in isolation but are transformed again by Resolve() or
-- by the status-indicator corner inset at runtime.
do
    local function ReadValue(conf, general, key, fallback)
        local value = type(conf) == "table" and conf[key] or nil
        if value == nil and type(general) == "table" then value = general[key] end
        if value == nil then return fallback end
        return value
    end

    local readerNS = {
        Cache = {StampChanged = function() return true end},
        Icons = {_layout = {}},
        UF = {},
        Util = {},
    }
    readerNS.Util.Num = function(conf, general, key, fallback)
        return tonumber(ReadValue(conf, general, key, fallback)) or fallback
    end
    readerNS.Util.Val = function(conf, general, key, fallback)
        return ReadValue(conf, general, key, fallback)
    end

    local function ReaderRegion()
        local region = {}
        function region:SetSize(width, height) self.width, self.height = width, height end
        function region:ClearAllPoints() self.point = nil end
        function region:SetPoint(point, owner, relativePoint, x, y)
            self.point = {point, owner, relativePoint, x, y}
        end
        function region:SetDrawLayer(layer, sublevel) self.layer, self.sublevel = layer, sublevel end
        function region:SetAlpha(alpha) self.alpha = alpha end
        function region:SetAtlas(atlas) self.atlas = atlas end
        function region:GetAtlas() return self.atlas end
        function region:SetTexture(texture) self.texture = texture end
        function region:GetTexture() return self.texture end
        function region:SetTexCoord(...) self.texCoord = {...} end
        function region:GetTexCoord() return 0, 1, 0, 1 end
        function region:SetText(text) self.text = text end
        function region:SetJustifyH(justify) self.justify = justify end
        function region:Show() self.shown = true end
        function region:Hide() self.shown = false end
        return region
    end

    local function CheckReaderPoint(region, owner, size, point, relativePoint, x, y, label)
        local actual = region.point or {}
        Equal(region.width, size, label .. " width")
        Equal(region.height, size, label .. " height")
        Equal(actual[1], point, label .. " point")
        Truthy(actual[2] == owner, label .. " owner")
        Equal(actual[3], relativePoint, label .. " relativePoint")
        Equal(actual[4], x, label .. " x")
        Equal(actual[5], y, label .. " y")
    end

    _G.MSUF_NS = readerNS
    _G.MSUF_DB = output
    _G.MSUF_EnsureDB = function() end
    _G.MSUF_GetConfigKeyForUnit = function(unit) return unit end
    _G.InCombatLockdown = function() return false end
    _G.UnitExists = function() return true end
    _G.UnitClassification = function() return "elite" end

    LoadAddonFile("Core/MSUF_IconLayoutRuntime.lua", "MidnightSimpleUnitFrames", readerNS)
    LoadAddonFile("Core/MSUF_EliteIcon.lua", "MidnightSimpleUnitFrames", readerNS)

    local targetFrame = {
        unit = "target",
        leaderIcon = ReaderRegion(),
        raidMarkerIcon = ReaderRegion(),
        eliteIcon = ReaderRegion(),
    }
    _G.MSUF_ApplyLeaderIconLayout(targetFrame)
    _G.MSUF_ApplyRaidMarkerLayout(targetFrame)
    _G.MSUF_ApplyEliteIconLayout(targetFrame)

    CheckReaderPoint(
        targetFrame.leaderIcon, targetFrame, 16,
        "LEFT", "TOPLEFT", 3, -11,
        "real leader-icon reader preserves UUF TOPLEFT geometry"
    )
    CheckReaderPoint(
        targetFrame.raidMarkerIcon, targetFrame, 24,
        "CENTER", "CENTER", 0, 0,
        "real raid-marker reader preserves UUF CENTER geometry"
    )
    CheckReaderPoint(
        targetFrame.eliteIcon, targetFrame, 24,
        "RIGHT", "TOPRIGHT", -3, 0,
        "real elite-icon reader preserves UUF RIGHT geometry"
    )

    -- StatusIndicators has a different reader: TOPLEFT always adds (+2, -2).
    -- Test mode makes both imported icons visible without game-state APIs.
    output.general.stateIconsTestMode = true
    output.player.statusTextEnabled = false
    LoadAddonFile("Core/MSUF_StatusIndicators.lua", "MidnightSimpleUnitFrames", readerNS)

    local playerFrame = {
        unit = "player",
        _msufIsPlayer = true,
        statusIndicatorText = ReaderRegion(),
        combatStateIndicatorIcon = ReaderRegion(),
        restingIndicatorIcon = ReaderRegion(),
    }
    _G.MSUF_UpdateStatusIndicatorForFrame(playerFrame)

    CheckReaderPoint(
        playerFrame.combatStateIndicatorIcon, playerFrame, 16,
        "TOPLEFT", "TOPLEFT", 3, -3,
        "real combat-indicator reader preserves UUF TOPLEFT geometry"
    )
    CheckReaderPoint(
        playerFrame.restingIndicatorIcon, playerFrame, 16,
        "TOPLEFT", "TOPLEFT", 3, -3,
        "real resting-indicator reader preserves UUF TOPLEFT geometry"
    )
end

-- Unsupported source semantics remain visible to the user via the report.
ReportContains(report, "skipped", "MONOCHROME", "dead MONOCHROME flag is reported as skipped")
Truthy(type(report.approximated) == "table" and #report.approximated > 0, "report has approximations")
Truthy(type(report.skipped) == "table" and #report.skipped > 0, "report has skipped semantics")

Finish()
