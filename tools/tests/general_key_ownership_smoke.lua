-- general_key_ownership_smoke.lua <repoRoot>
--
-- profile.general keys have one owner registry (State/MSUF_ProfileFields.lua,
-- F.GeneralOwner). Partial profile exports and imports carry exactly the keys
-- their kind owns. The exports used to guess ownership from key names: a Unit
-- Frames import overwrote the receiver's menu language, menu font, slash menu,
-- integrations and global UI scale; a Colors import wiped settings that only
-- read like colours (useBarBorder, fontSlug, portraitFillBorder, ...).
--
-- Pins:
--   1. every general key the defaults seed on any client is declared, unless
--      its name puts it in unitframes or castbars without doubt;
--   2. the owner of the keys the name rule got wrong;
--   3. the real export/import pipeline: a Unit Frames import keeps the
--      receiver's profile-local keys and a Colors import keeps non-colour keys,
--      while the keys each kind owns still travel.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")

local function Check(condition, message)
    if not condition then error(message, 2) end
end

-- 1 + 2: registry completeness and corrected owners --------------------------
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local CLEAR_BY_NAME = { unitframes = true, castbars = true }
for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do
    local world = World.New(root, flavor)
    world:Boot()
    local failure = world:FirstFailure()
    Check(failure == nil, flavor .. ": load failed in " .. tostring(failure and failure.file) .. ": "
        .. tostring(failure and failure.message))
    world.env.MSUF_EnsureDB()
    local F = assert(world.core.ProfileFields, flavor .. ": no MSUF.ProfileFields")
    local undeclared = {}
    for key in pairs(world.env.MSUF_DB.general) do
        if key:sub(1, 1) ~= "_" and not F.IsDeclaredGeneralKey(key)
            and not CLEAR_BY_NAME[F.FallbackGeneralOwner(key)] then
            undeclared[#undeclared + 1] = key .. " (name rule: " .. tostring(F.FallbackGeneralOwner(key)) .. ")"
        end
    end
    table.sort(undeclared)
    Check(#undeclared == 0, flavor .. ": general keys without an owner row in State/MSUF_ProfileFields.lua: "
        .. table.concat(undeclared, ", "))

    local expected = {
        -- profile-local: a full profile export only
        UIScale = "profile", menuLocale = "profile", menuFontKey = "profile", slashMenuScale = "profile",
        slashMenuSnapEnabled = "profile", hideAdvancedMenu = "profile", showGameMenuButton = "profile",
        globalUiScalePreset = "profile", globalUiScaleValue = "profile", disableScaling = "profile",
        blizzardEditModeIntegration = "profile", blizzardEditModeSnapshot = "profile",
        nsrtNicknameIntegration = "profile", dominosEditModeIntegration = "profile",
        -- read like colours, are unit frame settings
        useBarBorder = "unitframes", fontSlug = "unitframes", fontTextAlpha = "unitframes",
        portraitFillBorder = "unitframes", dispelBorderTrigger = "unitframes", editModeBgAlpha = "unitframes",
        hpBgAlpha = "unitframes", powerBarBgAlpha = "unitframes",
        -- colours stay colours
        classBarBgR = "colors", healthGradientHighG = "colors", fontColor = "colors", barMode = "colors",
        castbarInterruptColor = "castbarColors", empowerColorStages = "castbarColors",
        aurasStackCountColor = "auraColors",
        -- castbar family
        arenaCastTimeFormat = "castbars", castbarPlayerBarWidth = "castbars", showBossCastIcon = "castbars",
        enablePlayerCastbar = "castbars", empowerStageBlink = "castbars",
        -- plain unit frame keys
        fontKey = "unitframes", portraitShape = "unitframes", unitDispelSymbolMode = "unitframes",
        -- undeclared keys a menu may write: the fallback rule
        menuNewSetting = "profile", someIntegrationToggle = "profile", castbarNewColor = "castbarColors",
        bossCastNewOffset = "castbars", newPanelBorderR = "colors", newPanelToggle = "unitframes",
    }
    for key, owner in pairs(expected) do
        Check(F.GeneralOwner(key) == owner, flavor .. ": owner of general." .. key .. " is "
            .. tostring(F.GeneralOwner(key)) .. ", expected " .. owner)
    end
    Check(F.GeneralKeyInKind("aurasStackCountColor", "unitframe") and F.GeneralKeyInKind("aurasStackCountColor", "colors"),
        flavor .. ": aura colours must travel with Unit Frames and Colors")
    Check(not F.GeneralKeyInKind("menuLocale", "unitframe") and not F.GeneralKeyInKind("menuLocale", "colors"),
        flavor .. ": a profile-local key travels with a partial export")
    Check(F.GeneralSyncOwner("castbarInterruptColor") == "castbars" and F.GeneralSyncOwner("menuLocale") == nil
        and F.GeneralSyncOwner("useBarBorder") == "unitframes",
        flavor .. ": profile sync owners disagree with the registry")
end

-- 3: the real export/import pipeline ------------------------------------------
local Harness = assert(loadfile(root .. "/tools/tests/profile_state_harness.lua"))()

local function RunImports(flavor)
    local h = Harness.Load(root, flavor)
    local function Import(kind, payload)
        local ok, why = h.Import(kind, payload)
        Check(ok == true, flavor .. ": " .. kind .. " import failed: " .. tostring(why))
    end

    -- A friend's Unit Frames export carries their menu language, menu font,
    -- slash menu scale, integrations and UI scale.
    local g = MSUF_DB.general
    g.menuLocale, g.menuFontKey, g.slashMenuScale = "frFR", "MY_FONT", 1.1
    g.nsrtNicknameIntegration, g.UIScale = false, { Enabled = true, Scale = 0.8 }
    g.globalUiScalePreset, g.globalUiScaleValue = "custom", 0.8
    g.blizzardEditModeSnapshot = { mine = true }
    Import("unitframe", { general = {
        menuLocale = "deDE", menuFontKey = "FRIEND_FONT", slashMenuScale = 0.7, nsrtNicknameIntegration = true,
        UIScale = { Enabled = false, Scale = 1 }, globalUiScalePreset = "auto", fontKey = "FRIEND_TEXT",
        useBarBorder = false,
    }, player = { width = 222 } })
    g = MSUF_DB.general
    Check(g.menuLocale == "frFR", flavor .. ": a Unit Frames import replaced the menu language with "
        .. tostring(g.menuLocale))
    Check(g.menuFontKey == "MY_FONT" and g.slashMenuScale == 1.1 and g.nsrtNicknameIntegration == false,
        flavor .. ": a Unit Frames import replaced the menu font, slash menu or an integration")
    Check(type(g.UIScale) == "table" and g.UIScale.Enabled == true and g.UIScale.Scale == 0.8
        and g.globalUiScalePreset == "custom", flavor .. ": a Unit Frames import replaced the global UI scale")
    Check(type(g.blizzardEditModeSnapshot) == "table" and g.blizzardEditModeSnapshot.mine == true,
        flavor .. ": a Unit Frames import dropped the Blizzard Edit Mode snapshot")
    Check(g.fontKey == "FRIEND_TEXT" and g.useBarBorder == false and MSUF_DB.player.width == 222,
        flavor .. ": the Unit Frames import lost keys it owns")

    -- A Colors import must only replace colours.
    g.useBarBorder, g.fontSlug, g.portraitFillBorder, g.dispelBorderTrigger = false, true, true, "BY_ME"
    g.fontTextAlpha, g.healthGradientHighR = 0.8, 0.1
    Import("colors", { general = { fontColor = "white", healthGradientHighR = 0.9, healthGradientHighG = 0.8,
        healthGradientHighB = 0.7 }, classColors = {}, npcColors = {} })
    g = MSUF_DB.general
    Check(g.useBarBorder == false and g.fontSlug == true and g.portraitFillBorder == true,
        flavor .. ": a Colors import reset bar border, font slug or portrait fill border")
    Check(g.dispelBorderTrigger == "BY_ME" and g.fontTextAlpha == 0.8,
        flavor .. ": a Colors import reset the dispel border trigger or the text alpha")
    Check(g.fontColor == "white" and g.healthGradientHighR == 0.9, flavor .. ": the Colors import lost its colours")

    -- The exports carry the same sets.
    local function ExportedGeneral(kind)
        local snap = h.Export(kind)
        local general = snap and snap.payload and snap.payload.general
        Check(type(general) == "table", flavor .. ": the " .. kind .. " export has no general table")
        return general
    end
    local exported = ExportedGeneral("unitframe")
    Check(exported.menuLocale == nil and exported.UIScale == nil and exported.menuFontKey == nil,
        flavor .. ": the Unit Frames export carries profile-local keys")
    Check(exported.fontKey == "FRIEND_TEXT" and exported.useBarBorder == false and exported.fontColor == nil,
        flavor .. ": the Unit Frames export lost keys it owns or carries colours")
    exported = ExportedGeneral("colors")
    Check(exported.fontColor == "white" and exported.useBarBorder == nil and exported.fontSlug == nil,
        flavor .. ": the Colors export does not carry exactly the colours")
    exported = ExportedGeneral("castbar")
    Check(exported.castbarTexture ~= nil and exported.castbarInterruptColor == nil and exported.fontKey == nil,
        flavor .. ": the Castbars export does not carry exactly the castbar keys")
end

RunImports("Mainline")
RunImports("Vanilla")
print("general_key_ownership_smoke: ok")
