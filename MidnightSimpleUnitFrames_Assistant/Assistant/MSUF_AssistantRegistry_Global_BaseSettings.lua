-- Assistant Global base and misc setting registry.
-- Loaded before MSUF_AssistantRegistry_Global.lua; the main global hub passes registry helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GlobalRegistry = A.GlobalRegistry or {}

function A.GlobalRegistry.RegisterBaseSettings(ctx)
    if type(ctx) ~= "table" then return end

    local Registry = ctx.Registry
    local Menu = ctx.M or M
    local GeneralDB = ctx.GeneralDB
    local ApplyGeneral = ctx.ApplyGeneral
    local RegisterGeneralBoolean = ctx.RegisterGeneralBoolean
    local RegisterGeneralString = ctx.RegisterGeneralString
    local RegisterBaseAppearanceSettings = A.GlobalRegistry and A.GlobalRegistry.RegisterBaseAppearanceSettings

    if not (Registry and type(Registry.RegisterSetting) == "function") then return end
    if type(GeneralDB) ~= "function" then return end
    if type(RegisterGeneralBoolean) ~= "function" or type(RegisterGeneralString) ~= "function" or type(RegisterBaseAppearanceSettings) ~= "function" then return end

    RegisterBaseAppearanceSettings(ctx)

    Registry:RegisterSetting({
        key = "general.menuAccent",
        label = "Menu Accent Color",
        category = "Global / Misc",
        unit = "global",
        frameType = "misc",
        attribute = "menuAccent",
        type = "enum",
        values = { "midnight", "class", "ember", "jade", "violet", "custom" },
        valueAliases = {
            default = "midnight", blue = "midnight", classcolor = "class",
            orange = "ember", green = "jade", purple = "violet",
        },
        aliases = { "menu accent", "menu accent color", "options accent", "menu theme color" },
        get = function()
            local value = tostring(GeneralDB().menuAccent or "midnight")
            local allowed = { midnight = true, class = true, ember = true, jade = true, violet = true, custom = true }
            return allowed[value] and value or "midnight"
        end,
        set = function(value) GeneralDB().menuAccent = tostring(value or "midnight") end,
        apply = function() return true end,
        combatSafe = true,
        requiresReload = true,
    })
    Registry:RegisterSetting({
        key = "general.menuAccentColor",
        label = "Custom Menu Accent Color",
        category = "Global / Misc",
        unit = "global",
        frameType = "misc",
        attribute = "menuAccentColor",
        type = "color",
        aliases = { "custom menu accent color", "menu custom color", "options accent color" },
        defaultR = 0.231, defaultG = 0.510, defaultB = 0.965,
        get = function()
            local hex = tostring(GeneralDB().menuAccentColor or "3b82f6"):gsub("#", "")
            if not hex:match("^[%da-fA-F][%da-fA-F][%da-fA-F][%da-fA-F][%da-fA-F][%da-fA-F]$") then hex = "3b82f6" end
            return tonumber(hex:sub(1, 2), 16) / 255,
                tonumber(hex:sub(3, 4), 16) / 255,
                tonumber(hex:sub(5, 6), 16) / 255
        end,
        set = function(r, g, b)
            local function Byte(value)
                value = math.max(0, math.min(1, tonumber(value) or 0))
                return math.floor(value * 255 + 0.5)
            end
            GeneralDB().menuAccentColor = string.format("%02x%02x%02x", Byte(r), Byte(g), Byte(b))
        end,
        apply = function() return true end,
        combatSafe = true,
        requiresReload = true,
    })

    -- Companion to the accent choice above: whether the accent hue is rotated
    -- onto panels, borders and the nav rail, or stays on buttons and highlights
    -- only. Like the accent itself, the rehue happens once at login, so this
    -- needs a reload to take effect.
    RegisterGeneralBoolean("menuAccentTintSurfaces", "menuAccentTintSurfaces", "Tint Menu Surfaces", false, {
        "tint menu surfaces", "menu surface tint", "tint menu panels", "accent tint surfaces",
        "tint the menu background", "menu accent tint", "tint options panels",
    }, {
        category = "Global / Misc",
        frameType = "misc",
        combatSafe = true,
        requiresReload = true,
        apply = function() return true end,
        description = "Off keeps panels midnight while the accent colors buttons, tabs and highlights. On rotates panels, borders and the navigation rail onto the accent hue too.",
    })

    RegisterGeneralString("menuFontKey", "menuFont", "MSUF Menu Font", "", {
        "msuf menu font", "menu font", "options menu font", "options font", "dashboard menu font",
        "font of the msuf menu", "font for the msuf menu", "msuf menu typeface", "menu typeface",
    }, {
        category = "Global / Misc",
        frameType = "misc",
        mediaType = "font",
        reason = "MSUF_ASSISTANT_MENU_FONT",
        normalizeValue = function(value)
            value = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if value == "" then return "" end
            local normalizePath = _G.MSUF_NormalizeFontPath
            if type(normalizePath) == "function" then
                local normalized = normalizePath(value)
                if type(normalized) == "string" and normalized ~= "" then return normalized end
            end
            return value
        end,
        apply = function()
            local theme = Menu and Menu.Theme
            if theme and type(theme.ClearMenuFontCache) == "function" then theme.ClearMenuFontCache() end
            if theme and type(theme.RefreshMenuFonts) == "function" then theme.RefreshMenuFonts() end
        end,
        combatSafe = true,
        description = "Font used only by the MSUF options menu. Blizzard default is stored as an empty value.",
    })

    RegisterGeneralBoolean("slashMenuSnapEnabled", "menuSnap", "Menu Edge Snap", true, {
        "menu edge snap", "edge snap", "window snap", "menu snapping", "snapping feature",
        "snap feature", "menu snap feature", "windows style edge snap", "windows-style edge snap",
        "enable windows style edge snap for this menu", "enable windows-style edge snap for this menu", "fenster andocken",
        "menue andocken", "menue einrasten", "menue snap", "fenster einrasten", "kante andocken",
        "an bildschirmkante andocken", "windows snap", "windows andocken",
    }, { category = "Global / Misc", frameType = "misc", reason = "MSUF_ASSISTANT_MENU_SNAP" })
    Registry:RegisterSetting({
        key = "general.hideAdvancedMenu",
        label = "Advanced Menu Section",
        category = "Global / Misc",
        unit = "global",
        frameType = "misc",
        attribute = "advancedMenuVisible",
        type = "boolean",
        aliases = { "advanced menu", "advanced menu section", "advanced section", "hide advanced menu", "hide advanced menu section", "show advanced menu", "show advanced menu section", "erweitertes menu", "erweitertes menue", "advanced menue", "zeige erweitertes menue", "verstecke erweitertes menue" },
        get = function() return GeneralDB().hideAdvancedMenu ~= true end,
        set = function(value) GeneralDB().hideAdvancedMenu = not (value and true or false) end,
        apply = function()
            ApplyGeneral("MSUF_ASSISTANT_ADVANCED_MENU", { preview = false, applyAll = false, notify = false })
            if Menu and type(Menu.RefreshAdvancedNavVisibility) == "function" then Menu.RefreshAdvancedNavVisibility() end
        end,
        combatSafe = false,
    })
    RegisterGeneralBoolean("reduceMotion", "reduceMotion", "Reduce Menu Motion", false, {
        "reduce motion", "menu motion", "animations", "reduce animations", "reduce menu motion", "menu animations", "bewegung reduzieren",
        "menue bewegung reduzieren", "animationen reduzieren", "weniger bewegung", "weniger animationen", "reduzierte bewegung",
    }, { category = "Global / Misc", frameType = "misc", reason = "MSUF_ASSISTANT_REDUCE_MOTION" })
    RegisterGeneralBoolean("showNavigationIcons", "navigationIcons", "Navigation Icons", false, {
        "navigation icons", "nav icons", "menu icons", "sidebar icons", "rail icons", "show navigation icons", "hide navigation icons",
        "navigation symbols", "nav symbols", "menu symbols", "sidebar symbols", "rail symbols", "navi symbole", "navigationssymbole",
        "navigation symbole", "menue symbole", "menu symbole", "seitenleisten symbole", "navi icons", "navi symbole anzeigen",
        "navigationssymbole anzeigen", "navigationssymbole ausblenden",
    }, { category = "Global / Misc", frameType = "misc", reason = "MSUF_ASSISTANT_NAV_ICONS" })
    RegisterGeneralBoolean("showGameMenuButton", "gameMenuButton", "MSUF Game Menu Button", true, {
        "game menu button", "msuf game menu button", "escape menu button", "esc menu button", "game menu entry",
        "msuf escape menu", "msuf esc menu", "show game menu button", "hide game menu button",
        "show msuf button in game menu", "hide msuf button in game menu", "spielmenue button",
        "spielmenue knopf", "game menu knopf", "escape menue button", "esc menue button",
        "msuf button im spielmenue", "msuf knopf im spielmenue", "msuf im escape menue",
    }, { category = "Global / Misc", frameType = "misc", reason = "MSUF_ASSISTANT_GAME_MENU_BUTTON" })
    Registry:RegisterSetting({
        key = "general.navHoverScale",
        label = "Navigation Hover Size",
        category = "Global / Misc",
        unit = "global",
        frameType = "misc",
        attribute = "navHoverScale",
        type = "number",
        min = 1,
        max = 1.5,
        step = 0.01,
        percent = true,
        aliases = { "navigation hover size", "nav hover size", "nav hover scale", "navigation hover scale", "sidebar hover size", "rail hover size", "apple dock hover", "apple ux hover", "navigation magnification", "nav magnification", "navi hover groesse", "navigation hover groesse" },
        get = function() return tonumber(GeneralDB().navHoverScale) or 1.05 end,
        set = function(value)
            value = tonumber(value) or 1
            if value < 1 then value = 1 elseif value > 1.5 then value = 1.5 end
            GeneralDB().navHoverScale = value
        end,
        apply = function()
            ApplyGeneral("MSUF_ASSISTANT_NAV_HOVER_SCALE", { preview = false, applyAll = false, notify = false })
            if Menu and type(Menu.RefreshNavHoverScale) == "function" then Menu.RefreshNavHoverScale() end
        end,
        combatSafe = false,
    })
    RegisterGeneralBoolean("showWelcomeMessage", "welcomeMessage", "Welcome Message", true, {
        "welcome message", "startup welcome", "start message", "show welcome message", "login welcome message", "startup message", "willkommensnachricht",
        "willkommens nachricht", "willkommens meldung", "willkommen nachricht", "login nachricht", "start meldung",
    }, { category = "Global / Misc", frameType = "misc", reason = "MSUF_ASSISTANT_WELCOME" })
    RegisterGeneralBoolean("versionCheckEnabled", "versionCheck", "Peer Version Check", true, {
        "version check", "peer version check", "update check", "enable version check", "peer-to-peer version check", "version check peer to peer", "versions pruefung", "versionscheck",
        "version pruefung", "versionspruefung", "peer versionspruefung", "update pruefung", "addon versionscheck",
    }, { category = "Global / Misc", frameType = "misc", reason = "MSUF_ASSISTANT_VERSION_CHECK" })
    RegisterGeneralBoolean("showMinimapIcon", "minimapIcon", "MSUF Minimap Icon", true, {
        "minimap icon", "minimap button", "msuf minimap icon", "msuf minimap button", "show minimap icon", "hide minimap icon", "minikarten symbol",
        "minimap symbol", "minimap knopf", "minikarten icon", "minikarten button", "minikarten knopf", "symbol an der minimap",
    }, {
        category = "Global / Misc", frameType = "misc", reason = "MSUF_ASSISTANT_MINIMAP_ICON",
        dbScopes = { { scope = "general", dbKey = "minimapIconDB.hide" } },
    })
    Registry:RegisterSetting({
        key = "general.minimapIconPosition",
        label = "MSUF Minimap Icon Position",
        category = "Global / Misc",
        unit = "global",
        frameType = "misc",
        attribute = "minimapIconPosition",
        type = "number",
        min = 0,
        max = 360,
        step = 1,
        aliases = { "minimap icon position", "minimap button position", "minimap icon angle", "minimap button angle" },
        -- The minimap button itself is the native UI for this value: users
        -- change the angle by dragging it around the minimap. There is no
        -- duplicate Menu2 slider to navigate to, while the Assistant may read
        -- and set the same persisted value directly.
        menuControlDisposition = "standalone",
        menuControlDispositionReason = "The minimap icon angle is controlled by dragging the minimap button, not by a Menu2 control.",
        menuControlDispositionEvidence = "MidnightSimpleUnitFrames/Shell/MSUF_MinimapButton.lua:242-270,303-317",
        dbScopes = { { scope = "general", dbKey = "minimapIconDB.minimapPos" } },
        dbScopesReplace = true,
        get = function()
            local g = GeneralDB()
            local db = type(g.minimapIconDB) == "table" and g.minimapIconDB or nil
            return tonumber(db and db.minimapPos) or 220
        end,
        set = function(value)
            local g = GeneralDB()
            g.minimapIconDB = type(g.minimapIconDB) == "table" and g.minimapIconDB or {}
            value = tonumber(value) or 220
            if value < 0 then value = 0 elseif value > 360 then value = 360 end
            g.minimapIconDB.minimapPos = value
        end,
        apply = function()
            local fn = _G.MSUF_SetMinimapIconPosition
            if type(fn) == "function" then fn(GeneralDB().minimapIconDB.minimapPos) end
        end,
        combatSafe = false,
    })
    RegisterGeneralBoolean("playTargetSelectLostSounds", "targetSounds", "Target Select/Lost Sounds", false, {
        "target sounds", "target sound", "target lost sound", "target lost sounds", "target select sound", "target select sounds",
        "target select lost sounds", "play sound on target", "play sound on target lost", "play sound on target select", "ziel sound", "ziel sounds",
        "zielauswahl sound", "ziel verloren sound", "ziel verloren sounds", "sound bei ziel", "sound bei zielwechsel", "spiele sound bei ziel",
    }, { category = "Global / Misc", frameType = "misc", reason = "MSUF_ASSISTANT_TARGET_SOUNDS" })
    Registry:RegisterSetting({
        key = "general.disableBlizzardUnitFrames",
        label = "Blizzard Unit Frames",
        category = "Global / Misc",
        unit = "global",
        frameType = "misc",
        attribute = "blizzardFramesVisible",
        type = "boolean",
        aliases = { "blizzard unitframes", "blizzard unit frames", "disable blizzard unitframes", "disable blizzard unit frames", "enable blizzard unitframes", "enable blizzard unit frames", "blizzard frames", "standard frames", "default frames", "blizzard unitframe", "blizzard rahmen", "blizzard unitframes deaktivieren", "blizzard unitframes aktivieren", "blizzard unitframes ausblenden", "blizzard unitframes einblenden", "standardrahmen", "standard rahmen", "wow unitframes", "wow rahmen", "original frames" },
        get = function() return GeneralDB().disableBlizzardUnitFrames == false end,
        set = function(value) GeneralDB().disableBlizzardUnitFrames = not (value and true or false) end,
        apply = function() ApplyGeneral("MSUF_ASSISTANT_BLIZZARD_FRAMES", { preview = false, applyAll = false }) end,
        combatSafe = false,
        requiresReload = true,
    })

    Registry:RegisterSetting({
        key = "general.hardKillBlizzardPlayerFrame",
        label = "Fully Hide Blizzard PlayerFrame",
        category = "Global / Misc",
        unit = "global",
        frameType = "misc",
        attribute = "hardKillBlizzardPlayerFrame",
        type = "boolean",
        aliases = {
            "fully hide blizzard playerframe", "hard hide blizzard playerframe",
            "hard kill blizzard playerframe", "resource bar compatibility",
            "blizzard player frame compatibility", "hide blizzard player frame completely",
            "fully hide blizzard player frame", "hard hide blizzard player frame",
            "hard kill blizzard player frame", "fully hide blizzard playerframe resource bar compatibility",
            "fully hide blizzard playerframe - resource bar compatibility",
            "blizzard spieler rahmen komplett verstecken", "blizzard spieler frame komplett verstecken",
            "playerframe hart verstecken", "spieler frame hart verstecken", "ressourcenleisten kompatibilitaet",
        },
        get = function() return GeneralDB().hardKillBlizzardPlayerFrame == true end,
        set = function(value) GeneralDB().hardKillBlizzardPlayerFrame = value and true or false end,
        apply = function()
            ApplyGeneral("MSUF_ASSISTANT_HARDKILL_PLAYERFRAME", { preview = false, applyAll = false })
            if type(_G.MSUF_ShowReloadRecommendedPopup) == "function" then _G.MSUF_ShowReloadRecommendedPopup("Blizzard PlayerFrame hide mode") end
        end,
        combatSafe = false,
        requiresReload = true,
    })

    Registry:RegisterSetting({
        key = "general.menuLocale",
        label = "Menu Language",
        category = "Global / Misc",
        unit = "global",
        frameType = "misc",
        attribute = "menuLocale",
        type = "enum",
        aliases = { "menu language", "msuf language", "menu locale", "locale", "language", "menue sprache", "menuesprache", "msuf sprache", "sprache menue", "sprache der optionen", "optionen sprache" },
        values = { "auto", "enUS", "enGB", "deDE", "esES", "esMX", "frFR", "itIT", "ptBR", "ruRU", "koKR", "zhCN", "zhTW" },
        displayValues = {
            auto = "Automatic",
            enUS = "English (US)",
            enGB = "English (UK)",
            deDE = "German (deDE)",
            esES = "Spanish (EU)",
            esMX = "Spanish (MX)",
            frFR = "French",
            itIT = "Italian",
            ptBR = "Portuguese (BR)",
            ruRU = "Russian",
            koKR = "Korean",
            zhCN = "Chinese (Simplified)",
            zhTW = "Chinese (Traditional)",
        },
        valueAliases = {
            auto = "auto",
            blizzard = "auto",
            default = "auto",
            automatisch = "auto",
            ["blizzard sprache"] = "auto",
            ["client sprache"] = "auto",
            english = "enUS",
            englisch = "enUS",
            ["english us"] = "enUS",
            ["us english"] = "enUS",
            ["english gb"] = "enGB",
            ["british english"] = "enGB",
            german = "deDE",
            deutsch = "deDE",
            deutschsprachig = "deDE",
            spanish = "esES",
            spanisch = "esES",
            ["spanish eu"] = "esES",
            ["spanish mx"] = "esMX",
            mexican = "esMX",
            french = "frFR",
            francais = "frFR",
            franzoesisch = "frFR",
            italian = "itIT",
            italienisch = "itIT",
            portuguese = "ptBR",
            portugiesisch = "ptBR",
            brazilian = "ptBR",
            russian = "ruRU",
            russisch = "ruRU",
            korean = "koKR",
            koreanisch = "koKR",
            chinese = "zhCN",
            chinesisch = "zhCN",
            simplified = "zhCN",
            traditional = "zhTW",
            taiwan = "zhTW",
        },
        get = function()
            local value = GeneralDB().menuLocale
            if value == "enUS" or value == "enGB" or value == "deDE" or value == "esES" or value == "esMX"
                or value == "frFR" or value == "itIT" or value == "ptBR" or value == "ruRU"
                or value == "koKR" or value == "zhCN" or value == "zhTW"
            then
                return value
            end
            return "auto"
        end,
        set = function(value) GeneralDB().menuLocale = tostring(value or "auto") end,
        apply = function()
            local value = GeneralDB().menuLocale or "auto"
            if Menu and type(Menu.ApplyLocaleSelection) == "function" then Menu.ApplyLocaleSelection(value) end
            if Menu and type(Menu.InvalidatePage) == "function" then Menu.InvalidatePage() end
            if Menu and type(Menu.SelectPage) == "function" then Menu.SelectPage("opt_misc") end
        end,
        combatSafe = true,
    })
end
