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
        -- Every other type = "color" setting reads and writes ONE {r,g,b} table
        -- (see ColorSetting in MSUF_AssistantRegistry_GlobalColorSettings_Core).
        -- This one returned three values and took three arguments, so the shared
        -- execution path handed it the colour table as `r`, the other two
        -- arrived nil, and "set Custom Menu Accent Color to red" stored 000000
        -- while the reply printed a bare channel number instead of a hex.
        get = function()
            local hex = tostring(GeneralDB().menuAccentColor or "3b82f6"):gsub("#", "")
            if not hex:match("^[%da-fA-F][%da-fA-F][%da-fA-F][%da-fA-F][%da-fA-F][%da-fA-F]$") then hex = "3b82f6" end
            return {
                r = tonumber(hex:sub(1, 2), 16) / 255,
                g = tonumber(hex:sub(3, 4), 16) / 255,
                b = tonumber(hex:sub(5, 6), 16) / 255,
                label = "#" .. hex:upper(),
            }
        end,
        set = function(value)
            local function Byte(component)
                component = math.max(0, math.min(1, tonumber(component) or 0))
                return math.floor(component * 255 + 0.5)
            end
            local r, g, b
            if type(value) == "table" then
                r, g, b = value.r or value[1], value.g or value[2], value.b or value[3]
            elseif type(value) == "string" then
                if type(A.HexToColor) == "function" then r, g, b = A.HexToColor(value) end
                if not r and type(A.ColorFromName) == "function" then r, g, b = A.ColorFromName(value) end
            end
            if not r then return end
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
    RegisterGeneralBoolean("previewDragHintAnimationEnabled", "previewDragHintAnimation", "Preview Drag Hint Animation", true, {
        "preview drag hint", "preview drag animation", "drag hint animation", "move hint animation", "preview move tutorial",
        "show preview drag hint animation", "hide preview drag hint animation", "disable preview drag animation",
        "preview bewegungsanimation", "drag hinweis animation", "verschiebe hinweis", "preview animation abschalten",
    }, { category = "Global / Misc", frameType = "misc", reason = "MSUF_ASSISTANT_PREVIEW_DRAG_HINT" })
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
    RegisterGeneralBoolean("showWelcomeMessage", "welcomeMessage", "Welcome Message", true, {
        "welcome message", "startup welcome", "start message", "show welcome message", "login welcome message", "startup message", "willkommensnachricht",
        "willkommens nachricht", "willkommens meldung", "willkommen nachricht", "login nachricht", "start meldung",
    }, { category = "Global / Misc", frameType = "misc", reason = "MSUF_ASSISTANT_WELCOME" })
    RegisterGeneralBoolean("nsrtNicknameIntegration", "nsrtNicknameIntegration", "NSRT Nickname Integration", true, {
        "nsrt nicknames", "nsrt nickname integration", "northern sky raid tools nicknames", "use nsrt nicknames",
        "disable nsrt nicknames", "show character names instead of nsrt nicknames", "nsrt spitznamen", "nsrt namen deaktivieren",
    }, {
        category = "Global / Misc", frameType = "misc", reason = "MSUF_ASSISTANT_NSRT_NICKNAMES",
        apply = function()
            local fn = _G.MSUF_NSRTNicknames_ApplySetting
            if type(fn) == "function" then fn() end
        end,
    })
    RegisterGeneralBoolean("grid2EditModeIntegration", "grid2EditModeIntegration", "Grid2 Edit Mode Integration", true, {
        "grid2 edit mode", "grid2 mover", "move grid2", "show grid2 in edit mode", "grid2 integration",
        "grid2 im edit mode", "grid2 verschieben", "grid2 mover anzeigen",
    }, {
        category = "Global / Misc", frameType = "misc", reason = "MSUF_ASSISTANT_GRID2_EDIT_MODE",
        apply = function()
            local fn = _G.MSUF_Grid2EditMode_SetEnabled
            if type(fn) == "function" then fn(GeneralDB().grid2EditModeIntegration ~= false) end
        end,
    })
    RegisterGeneralBoolean("detailsEditModeIntegration", "detailsEditModeIntegration", "Details! Edit Mode Integration", true, {
        "details edit mode", "details mover", "move details", "show details in edit mode", "details integration",
        "details im edit mode", "details verschieben", "details mover anzeigen",
    }, {
        category = "Global / Misc", frameType = "misc", reason = "MSUF_ASSISTANT_DETAILS_EDIT_MODE",
        apply = function()
            local fn = _G.MSUF_DetailsEditMode_SetEnabled
            if type(fn) == "function" then fn(GeneralDB().detailsEditModeIntegration ~= false) end
        end,
    })
    RegisterGeneralBoolean("dominosEditModeIntegration", "dominosEditModeIntegration", "Dominos Edit Mode Integration", true, {
        "dominos edit mode", "dominos mover", "move dominos", "show dominos in edit mode", "dominos integration",
        "dominos bars edit mode", "move dominos bars", "dominos im edit mode", "dominos verschieben", "dominos mover anzeigen",
    }, {
        category = "Global / Misc", frameType = "misc", reason = "MSUF_ASSISTANT_DOMINOS_EDIT_MODE",
        apply = function()
            local fn = _G.MSUF_DominosEditMode_SetEnabled
            if type(fn) == "function" then fn(GeneralDB().dominosEditModeIntegration ~= false) end
        end,
    })
    RegisterGeneralBoolean("blizzardEditModeIntegration", "blizzardEditModeIntegration", "Blizzard Edit Mode Integration", true, {
        "blizzard edit mode", "blizzard frames edit mode", "move blizzard frames", "move minimap", "move chat",
        "move micro menu", "minimap mover", "chat mover", "micro menu mover", "blizzard integration",
        "blizzard im edit mode", "blizzard frames verschieben", "minimap verschieben", "chat verschieben",
        "mikromenue verschieben",
    }, {
        category = "Global / Misc", frameType = "misc", reason = "MSUF_ASSISTANT_BLIZZARD_EDIT_MODE",
        apply = function()
            local fn = _G.MSUF_BlizzardEditMode_SetEnabled
            if type(fn) == "function" then fn(GeneralDB().blizzardEditModeIntegration ~= false) end
        end,
    })
    RegisterGeneralBoolean("dandersEditModeIntegration", "dandersEditModeIntegration", "DandersFrames Edit Mode Integration", true, {
        "dandersframes edit mode", "danders edit mode", "danders mover", "move dandersframes", "move danders frames",
        "show dandersframes in edit mode", "dandersframes integration", "danders integration",
        "danders im edit mode", "dandersframes verschieben", "danders mover anzeigen",
    }, {
        category = "Global / Misc", frameType = "misc", reason = "MSUF_ASSISTANT_DANDERS_EDIT_MODE",
        apply = function()
            local fn = _G.MSUF_DandersEditMode_SetEnabled
            if type(fn) == "function" then fn(GeneralDB().dandersEditModeIntegration ~= false) end
        end,
    })
    RegisterGeneralBoolean("ellesmereEditModeIntegration", "ellesmereEditModeIntegration", "EllesmereUI Unlock Mode Integration", true, {
        "ellesmere edit mode", "ellesmereui edit mode", "ellesmere unlock mode", "ellesmereui unlock mode",
        "ellesmere integration", "ellesmereui integration", "show msuf in ellesmere", "msuf in ellesmereui",
        "ellesmere im edit mode", "ellesmereui entsperrmodus", "ellesmere entsperrmodus",
    }, {
        category = "Global / Misc", frameType = "misc", reason = "MSUF_ASSISTANT_ELLESMERE_EDIT_MODE",
        apply = function()
            local fn = _G.MSUF_EllesmereEditMode_SetEnabled
            if type(fn) == "function" then fn(GeneralDB().ellesmereEditModeIntegration ~= false) end
        end,
    })
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
    RegisterGeneralBoolean("playerResourcePingEnabled", "playerResourcePing", "Native Player Resource Pings", true, {
        "player resource ping", "player health ping", "health ping", "mana ping", "resource ping", "12.1 ping",
        "spieler ressourcen ping", "spieler health ping", "spieler gesundheit ping", "gesundheits ping", "mana ping",
    }, {
        category = "Global / Misc",
        frameType = "misc",
        reason = "MSUF_ASSISTANT_PLAYER_RESOURCE_PING",
        apply = function()
            local fn = _G.MSUF_RefreshPlayerResourcePing
            if type(fn) == "function" then fn() end
        end,
        combatSafe = true,
        description = "Enables Blizzard's native 12.1 contextual player-resource callout on the MSUF Player frame. Blizzard chooses health or supported mana contexts; separate Health/Power selection and Energy, Rage or Focus pings are not exposed.",
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

    Registry:RegisterSetting({
        key = "general.numberAbbrevStyle",
        label = "Number Abbreviation",
        category = "Global / Misc",
        unit = "global",
        frameType = "misc",
        attribute = "numberAbbrevStyle",
        type = "enum",
        aliases = {
            "number abbreviation", "abbreviate numbers", "number format", "abbreviation style",
            "compact numbers", "short number format", "number suffix",
            "zahlenabkuerzung", "zahlen abkuerzen", "zahlenformat", "kompakte zahlen", "zahlen kuerzen",
        },
        values = { "GAME", "COMPACT" },
        displayValues = {
            GAME = "Game default",
            COMPACT = "Compact",
        },
        valueAliases = {
            game = "GAME",
            default = "GAME",
            blizzard = "GAME",
            client = "GAME",
            locale = "GAME",
            spiel = "GAME",
            standard = "GAME",
            compact = "COMPACT",
            short = "COMPACT",
            english = "COMPACT",
            kompakt = "COMPACT",
            kurz = "COMPACT",
        },
        get = function()
            return GeneralDB().numberAbbrevStyle == "COMPACT" and "COMPACT" or "GAME"
        end,
        set = function(value)
            GeneralDB().numberAbbrevStyle = (value == "COMPACT") and "COMPACT" or "GAME"
        end,
        apply = function()
            --- The style lives as an upvalue in every text consumer, so it has
            --- to be pushed before the repaint formats anything.
            local numberFormat = _G.MSUF_NumberFormat or (_G.MSUF_NS and _G.MSUF_NS.NumberFormat)
            if numberFormat and type(numberFormat.Refresh) == "function" then numberFormat.Refresh() end
            ApplyGeneral("MSUF_ASSISTANT_NUMBER_ABBREV_TEXT", { preview = false, applyAll = false, text = true })
            if type(_G.MSUF_GF_RefreshVisuals) == "function" then _G.MSUF_GF_RefreshVisuals() end
        end,
        combatSafe = true,
    })
end
