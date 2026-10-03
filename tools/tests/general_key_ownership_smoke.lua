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
--      while the keys each kind owns still travel;
--   4. the keys each page writes resolve to that page's owner. The lists come
--      from the page sources: the Menu2 search index (generated from the
--      pages: page, section and setting key of every control), the Colors page
--      files and the colour API behind them, the MSUF Edit Mode and the menu
--      window chrome. The name rule had put the unified bar colour, the NPC
--      type switches, the GCD bar, kick-ready and cast time keys and the menu
--      and Edit Mode preferences in unitframes.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")

local function Check(condition, message)
    if not condition then error(message, 2) end
end

-- 1 + 2: registry completeness and corrected owners --------------------------
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local CLEAR_BY_NAME = { unitframes = true, castbars = true }
local SEEDED, Registry = {}, nil
for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do
    local world = World.New(root, flavor)
    world:Boot()
    local failure = world:FirstFailure()
    Check(failure == nil, flavor .. ": load failed in " .. tostring(failure and failure.file) .. ": "
        .. tostring(failure and failure.message))
    world.env.MSUF_EnsureDB()
    local F = assert(world.core.ProfileFields, flavor .. ": no MSUF.ProfileFields")
    Registry = F
    for key in pairs(world.env.MSUF_DB.general) do SEEDED[key] = true end
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
        -- menu and MSUF Edit Mode preferences
        flashFullW = "profile", flashFullXpx = "profile", msuf2WindowW = "profile", dropdownStyleMode = "profile",
        tipCycleIndex = "profile", unitPreviewGuidesEnabled = "profile", classPowerPreviewGuidesEnabled = "profile",
        previewDragHintAnimationEnabled = "profile", showNavigationIcons = "profile", reduceMotion = "profile",
        hpPowerTextSelectedKey = "profile", editModeBgAlpha = "profile", editModeSnapToGrid = "profile",
        editModeGridStep = "profile", editModePopupScale = "profile", linkEditModes = "profile",
        -- read like colours, are unit frame settings
        useBarBorder = "unitframes", fontSlug = "unitframes", fontTextAlpha = "unitframes",
        portraitFillBorder = "unitframes", dispelBorderTrigger = "unitframes",
        hpBgAlpha = "unitframes", powerBarBgAlpha = "unitframes",
        -- colours stay colours
        classBarBgR = "colors", healthGradientHighG = "colors", fontColor = "colors", barMode = "colors",
        castbarInterruptColor = "castbarColors", empowerColorStages = "castbarColors",
        aurasStackCountColor = "auraColors",
        -- Colors page settings the name rule put elsewhere
        unifiedBarR = "colors", darkBarB = "colors", darkBarGray = "colors", barBgFillMode = "colors",
        npcTypeBoss = "colors", npcTypeToT = "colors", tapDeniedGray = "colors",
        aurasCooldownTextSafeSeconds = "colors", playerCastbarOverrideMode = "castbarColors",
        playerCastbarOverrideR = "castbarColors", castbarInterruptibleR = "castbarColors",
        castbarTargetNameB = "castbarColors",
        -- castbar family
        arenaCastTimeFormat = "castbars", castbarPlayerBarWidth = "castbars", showBossCastIcon = "castbars",
        enablePlayerCastbar = "castbars", empowerStageBlink = "castbars", gcdBarWidth = "castbars",
        showGCDBar = "castbars", kickReadySize = "castbars", enableFocusKickIcon = "castbars",
        focusKickTextSize = "castbars", showPlayerCastTime = "castbars", showFocusCastTime = "castbars",
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

    -- The unified colour, the NPC type switches, the GCD bar, kick-ready and
    -- cast time keys and the menu and Edit Mode preferences travel with their
    -- own kind only.
    g = MSUF_DB.general
    g.unifiedBarR, g.npcTypeBoss, g.tapDeniedGray = 0.6, false, false
    g.gcdBarWidth, g.kickReadySize, g.showPlayerCastTime = 333, 21, false
    g.flashFullW, g.editModeGridStep, g.tipCycleIndex = 1400, 24, 9
    exported = ExportedGeneral("colors")
    Check(exported.unifiedBarR == 0.6 and exported.npcTypeBoss == false and exported.tapDeniedGray == false,
        flavor .. ": the Colors export lost the unified colour, an NPC type switch or the tapped grey")
    exported = ExportedGeneral("castbar")
    Check(exported.gcdBarWidth == 333 and exported.kickReadySize == 21 and exported.showPlayerCastTime == false,
        flavor .. ": the Castbars export carries no GCD bar, kick-ready or cast time keys")
    local friend = ExportedGeneral("unitframe")
    Check(friend.unifiedBarR == nil and friend.npcTypeBoss == nil and friend.gcdBarWidth == nil
        and friend.flashFullW == nil and friend.editModeGridStep == nil and friend.tipCycleIndex == nil,
        flavor .. ": the Unit Frames export carries colours, castbar keys or menu and Edit Mode preferences")
    friend.unifiedBarR, friend.npcTypeBoss, friend.flashFullW, friend.editModeGridStep = 0.2, true, 700, 64
    friend.gcdBarWidth = 99
    g.unifiedBarR, g.npcTypeBoss, g.flashFullW, g.editModeGridStep, g.gcdBarWidth = 0.4, false, 1200, 16, 250
    Import("unitframe", { general = friend })
    g = MSUF_DB.general
    Check(g.unifiedBarR == 0.4 and g.npcTypeBoss == false and g.gcdBarWidth == 250,
        flavor .. ": a Unit Frames import overwrote a colour or a castbar key")
    Check(g.flashFullW == 1200 and g.editModeGridStep == 16,
        flavor .. ": a Unit Frames import overwrote a menu or Edit Mode preference")
end

RunImports("Mainline")
RunImports("Vanilla")

-- 4: the keys each page writes resolve to that page's owner -------------------
local F = Registry
local COLOR_FAMILY = { colors = true, castbarColors = true, auraColors = true }
local CASTBAR_FAMILY = { castbars = true, castbarColors = true }
local PROFILE = { profile = true }
local OPTIONS = "MidnightSimpleUnitFrames_Options/Shell/Menu2/"
local mismatches, seen, counts = {}, {}, {}

local function ReadSource(rel)
    local handle = assert(io.open(root .. "/" .. rel, "rb"), "missing page source " .. rel)
    local text = handle:read("*a")
    handle:close()
    return (text:gsub("\r\n", "\n"))
end
-- exceptions name keys a page legitimately writes for another owner.
local function Expect(key, family, where, exceptions)
    if type(key) ~= "string" or key:sub(1, 1) == "_" then return end
    counts[where] = (counts[where] or 0) + 1
    local owner, wanted = F.GeneralOwner(key), exceptions and exceptions[key]
    local ok
    if wanted then ok = owner == wanted else ok = family[owner] == true end
    local line = where .. ": general." .. key .. " -> " .. tostring(owner)
    if not ok and not seen[line] then
        seen[line] = true
        mismatches[#mismatches + 1] = line
    end
end
-- The stored keys a control's setting key names: the key itself, or the
-- channels (R, G, B, A) its colour is stored in, also under the key without
-- its "Color" suffix.
local function StoredKeys(key)
    local out = {}
    for _, prefix in ipairs({ key, key:match("^(.-)Color$") }) do
        for _, channel in ipairs({ "R", "G", "B", "A" }) do
            if SEEDED[prefix .. channel] then out[#out + 1] = prefix .. channel end
        end
    end
    if SEEDED[key] or #out == 0 then out[#out + 1] = key end
    return out
end
-- Direct writes to profile.general in a source file.
local function GeneralWrites(text)
    local keys = {}
    for _, pattern in ipairs({ "G%(%)%.([%a_][%w_]*)%s*=[^=]", "%f[%w_]g%.([%a_][%w_]*)%s*=[^=]",
        "%f[%w_]gen%.([%a_][%w_]*)%s*=[^=]", "%f[%w_]general%.([%a_][%w_]*)%s*=[^=]" }) do
        for key in text:gmatch(pattern) do keys[key] = true end
    end
    return keys
end

-- a. Every control of the search index (both index files) with a general
-- setting key: the Castbars page and the castbar section of each unit page,
-- the Colors page, and the menu sections of the Misc page and the menu chrome.
-- The Misc page's minimap and welcome message rows are not menu preferences
-- (their owner is still open), so their sections are not checked.
local MENU_SECTIONS = { misc_menu_behavior = true, misc_external_edit_mode = true,
    misc_nickname_integration = true, misc_mapkoskin = true }
local function IndexFamily(page, section)
    if page == "opt_castbar" or section == "castbar" then return CASTBAR_FAMILY, "Castbars controls" end
    if page == "opt_colors" then return COLOR_FAMILY, "Colors controls" end
    if page == "menu_chrome" or (page == "opt_misc" and MENU_SECTIONS[section]) then
        return PROFILE, "menu preference controls"
    end
end
for _, rel in ipairs({ OPTIONS .. "Search/MSUF_Menu2_Search_StaticIndex_Data.lua",
    OPTIONS .. "Search/MSUF_Menu2_Search_StaticIndex_Data_Classic.lua" }) do
    local blob = assert(ReadSource(rel):match("%[==%[\n?(.-)%]==%]"), rel .. ": no index blob")
    for line in blob:gmatch("[^\n]+") do
        local cols = {}
        for col in (line .. "\t"):gmatch("([^\t]*)\t") do cols[#cols + 1] = col end
        local key = cols[4] and cols[4]:match("^general%.([%a_][%w_]*)")
        local family, where = IndexFamily(cols[1], cols[9])
        if key and family then
            for _, stored in ipairs(StoredKeys(key)) do Expect(stored, family, where) end
        end
    end
end

-- b. The Colors page files: their direct writes and every colour prefix they
-- hand the colour pickers (stored as prefix..R/G/B), and the colour API the
-- page drives (Runtime/MSUF_Colors.lua). The bar text editors remember their
-- selected key in general; that is a menu preference.
local COLOR_PAGE_EXCEPTIONS = { hpPowerTextSelectedKey = "profile" }
local colorSources = {}
for _, name in ipairs({ "", "_Context", "_Group", "_Meta", "_Resources" }) do
    colorSources[#colorSources + 1] = ReadSource(OPTIONS .. "Pages/MSUF_Menu2_AdvancedColors" .. name .. ".lua")
end
for _, text in ipairs(colorSources) do
    for key in pairs(GeneralWrites(text)) do Expect(key, COLOR_FAMILY, "Colors page writes", COLOR_PAGE_EXCEPTIONS) end
    for _, call in ipairs({ "GeneralColorAt", "ContextGeneral", "SetAllPortraitRGB", "ClearRGBs?", "ClearRGBAs" }) do
        for args in text:gmatch(call .. "(%b())") do
            for prefix in args:gmatch('"(%l[%w_]*)"') do
                for _, channel in ipairs({ "R", "G", "B" }) do Expect(prefix .. channel, COLOR_FAMILY, "Colors pickers") end
            end
        end
    end
end
local colorApi = ReadSource("MidnightSimpleUnitFrames/Runtime/MSUF_Colors.lua")
for args in colorApi:gmatch("_setRGBA?(%b())") do
    -- Whole keys only; key .. "R" is a dynamic per-unit castbar text colour.
    for key in args:gmatch('"(%l[%w_]+)"') do Expect(key, COLOR_FAMILY, "Colors API") end
end
for key in pairs(GeneralWrites(colorApi)) do Expect(key, COLOR_FAMILY, "Colors API") end

-- c. The MSUF Edit Mode (every file its manifest loads): grid, snapping and
-- popup preferences. The HUD also edits two unit frame anchors and the player
-- castbar preview switch.
local EDIT_MODE_EXCEPTIONS = { anchorName = "unitframes", anchorToCooldown = "unitframes",
    castbarPlayerPreviewEnabled = "castbars" }
local editModeDir = "MidnightSimpleUnitFrames/Shell/EditMode/"
for file in ReadSource(editModeDir .. "MSUF_EditMode.xml"):gmatch('<Script%s+file="([^"]+)"') do
    for key in pairs(GeneralWrites(ReadSource(editModeDir .. file:gsub("\\", "/")))) do
        Expect(key, PROFILE, "Edit Mode writes", EDIT_MODE_EXCEPTIONS)
    end
end

-- d. The menu window chrome: geometry, theme and preview guides.
for _, rel in ipairs({ "MSUF_Menu2_Window.lua", "MSUF_Menu2_Theme.lua", "MSUF_Menu2_Theme_Forever.lua",
    "Preview/MSUF_Menu2_UnitPreview_View_Chrome.lua" }) do
    for key in pairs(GeneralWrites(ReadSource(OPTIONS .. rel))) do Expect(key, PROFILE, "menu chrome writes") end
end

table.sort(mismatches)
Check(#mismatches == 0, "keys a page writes resolve outside that page's owner (declare them in "
    .. "State/MSUF_ProfileFields.lua):\n  " .. table.concat(mismatches, "\n  "))
-- The derivation must keep finding the pages' keys.
local minimum = { ["Castbars controls"] = 100, ["Colors controls"] = 60, ["menu preference controls"] = 15,
    ["Colors page writes"] = 40, ["Colors pickers"] = 30, ["Colors API"] = 40, ["Edit Mode writes"] = 8,
    ["menu chrome writes"] = 3 }
for where, least in pairs(minimum) do
    Check((counts[where] or 0) >= least, "page key derivation found only " .. tostring(counts[where] or 0)
        .. " " .. where .. " (expected at least " .. least .. "); did a page source or the index format move?")
end
print("general_key_ownership_smoke: ok")
