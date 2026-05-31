local addonName, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local Data = M.SearchData or {}
M.SearchData = Data

if type(Data.RegisterFAQProvider) == "function" then
    Data.RegisterFAQProvider(function(env)
        env = env or {}
        local SearchKeywordList = env.SearchKeywordList
        local DASHBOARD_ROUTE_RECOVERY = env.DASHBOARD_ROUTE_RECOVERY
        local DASHBOARD_ROUTE_SCALING = env.DASHBOARD_ROUTE_SCALING
        local DASHBOARD_ROUTE_CHANGELOG = env.DASHBOARD_ROUTE_CHANGELOG
        local SEARCH_DISPEL_DEBUFF_KEYWORDS = env.SEARCH_DISPEL_DEBUFF_KEYWORDS or Data.DISPEL_DEBUFF_KEYWORDS
        local SEARCH_HIGHLIGHT_BORDER_KEYWORDS = env.SEARCH_HIGHLIGHT_BORDER_KEYWORDS or Data.HIGHLIGHT_BORDER_KEYWORDS
        local SEARCH_DISPEL_OVERLAY_KEYWORDS = env.SEARCH_DISPEL_OVERLAY_KEYWORDS or Data.DISPEL_OVERLAY_KEYWORDS
        local SEARCH_DEBUFF_STRIPE_KEYWORDS = env.SEARCH_DEBUFF_STRIPE_KEYWORDS or Data.DEBUFF_STRIPE_KEYWORDS
        local SEARCH_BLIZZARD_DISPEL_KEYWORDS = env.SEARCH_BLIZZARD_DISPEL_KEYWORDS or Data.BLIZZARD_DISPEL_KEYWORDS
        local SEARCH_UNIT_AURA_DISPEL_KEYWORDS = env.SEARCH_UNIT_AURA_DISPEL_KEYWORDS or Data.UNIT_AURA_DISPEL_KEYWORDS
        local SEARCH_DASHBOARD_RECOVERY_KEYWORDS = env.SEARCH_DASHBOARD_RECOVERY_KEYWORDS or Data.DASHBOARD_RECOVERY_KEYWORDS
        local SEARCH_DASHBOARD_DISCORD_KEYWORDS = env.SEARCH_DASHBOARD_DISCORD_KEYWORDS or Data.DASHBOARD_DISCORD_KEYWORDS
        local SEARCH_DASHBOARD_SUPPORT_KEYWORDS = env.SEARCH_DASHBOARD_SUPPORT_KEYWORDS or Data.DASHBOARD_SUPPORT_KEYWORDS
        local SEARCH_DASHBOARD_WAGO_KEYWORDS = env.SEARCH_DASHBOARD_WAGO_KEYWORDS or Data.DASHBOARD_WAGO_KEYWORDS
        local SEARCH_DASHBOARD_SCALING_KEYWORDS = env.SEARCH_DASHBOARD_SCALING_KEYWORDS or Data.DASHBOARD_SCALING_KEYWORDS
        local SEARCH_DASHBOARD_CHANGELOG_KEYWORDS = env.SEARCH_DASHBOARD_CHANGELOG_KEYWORDS or Data.DASHBOARD_CHANGELOG_KEYWORDS

        return {
    {
        label = "How do I make unit frames transparent?",
        answer = "Open the unit page > Transparency for in-combat/out-of-combat alpha. Fade target chooses whether the sliders affect the whole frame, bars, HP, or backdrop. Group frame transparency is in Group Frames > Layout > Transparency.",
        pageKey = "uf_player",
        target = "Opens: Player > Transparency",
        anchorText = "Transparency alpha in combat out of combat opacity fade target whole frame layer fade bars hp bar backdrop preserve hp color text portrait visible",
        keywords = { "transparent unitframe", "transparent unit frame", "alpha unitframe", "opacity unitframe", "fade frame", "frame alpha", "whole frame alpha", "fade target", "in combat alpha", "out of combat alpha", "transparent player frame", "transparent target frame", "hp bar alpha", "health bar alpha", "bars alpha", "backdrop alpha", "text portrait visible" },
        priority = 40,
    },
    {
        label = "How do I make group frames transparent?",
        answer = "Open Group Frames > Layout > Transparency. Opacity controls in-combat and out-of-combat alpha; Fade target chooses whole frame, bars, HP, or backdrop. Backdrop and Health layers set base color, HP fill, and HP track opacity.",
        pageKey = "gf_layout",
        target = "Opens: Group Frames > Layout > Transparency",
        anchorText = "Group Frames Layout Transparency opacity fade target in combat out of combat alpha whole frame bars HP backdrop HP fill HP track preserve HP color",
        keywords = { "transparent group frames", "transparent group frame", "transparent raid frames", "transparent party frames", "group opacity", "group alpha", "raid opacity", "party opacity", "group frame transparency", "raid frame transparency", "party frame transparency", "hp fill opacity", "hp track opacity", "group fade target" },
        priority = 42,
    },
    {
        label = "How do I change bar textures, gradients, or outlines?",
        answer = "Open Global Style > Bars. Textures & Gradient controls shared bar textures; Frame Outline and Highlight Borders control borders.",
        pageKey = "opt_bars",
        target = "Opens: Global Style > Bars > Textures & Gradient",
        anchorText = "Textures & Gradient Frame Outline Highlight Borders texture gradient outline border",
        keywords = { "bar texture", "health texture", "power texture", "change texture", "gradient", "outline", "border", "bar border", "frame outline", "highlight border", "shared texture" },
        priority = 560,
    },
    {
        label = "How do I enable or disable rounded frames?",
        answer = "Open Global Style > Bars > Rounded Texture. Use the master toggle for all rounded frame textures, or the separate toggles for unit frames, group frames, power bars, and mouseover highlights.",
        pageKey = "opt_bars",
        target = "Opens: Global Style > Bars > Rounded Texture",
        anchorText = "Rounded Texture Rounded frame texture Unit frames Group frames Power bars Mouseover highlights rounded frames round corners",
        keywords = {
            "rounded frames", "rounded frame texture", "rounded texture", "round frames", "round corners", "rounded corners", "frame corners",
            "enable rounded frames", "disable rounded frames", "turn on rounded frames", "turn off rounded frames", "rounded frames on", "rounded frames off",
            "rounded unit frames", "rounded unitframes", "rounded group frames", "rounded power bars", "rounded mouseover", "rounded mouseover highlights",
            "abgerundete frames", "abgerundete unitframes", "runde kanten", "runde ecken", "abrundung", "abrunden", "rounded frames einschalten", "rounded frames ausschalten",
            "abgerundete frames einschalten", "abgerundete frames ausschalten", "runde kanten einschalten", "runde kanten ausschalten", "mouseover abgerundet", "powerbar abgerundet",
        },
        priority = 620,
    },
    {
        label = "Where is Smooth fill for unit frames?",
        answer = "Open the unit page, then use Frame Basics > Smooth fill for the health bar. For that unit's power bar animation, open Power Bar > Smooth fill.",
        pageKey = "uf_player",
        target = "Opens: Player > Frame Basics > Smooth fill",
        anchorText = "Frame Basics Smooth fill Power Bar Smooth fill health animation power animation soft fill weiche Fuellung",
        keywords = {
            "smooth fill", "smooth health fill", "smooth power bar", "soft fill", "fluid fill", "bar animation", "health bar animation", "power bar animation",
            "where is smooth fill", "find smooth fill", "option der weichen fuellung finden", "weiche fuellung", "weichen fuellung", "sanfte fuellung", "fluessige fuellung", "balken animation", "lebensbalken animation", "powerbar animation",
            "relleno suave", "llenado suave", "animacion de barra", "remplissage doux", "remplissage fluide", "animation de barre", "riempimento fluido", "riempimento morbido", "preenchimento suave", "animacao da barra",
            "плавное заполнение", "плавная заливка", "анимация полосы", "부드러운 채우기", "막대 애니메이션", "平滑填充", "柔和填充", "条动画", "條動畫", "平滑填充", "柔和填充",
        },
        priority = 360,
    },
    {
        label = "Where is Smooth fill for party or raid frames?",
        answer = "Open Group Frames > Layout for Smooth health fill. For group-frame power bars, open Group Frames > Health & Text > Power Bar > Smooth fill.",
        pageKey = "gf_layout",
        target = "Opens: Group Frames > Layout > Smooth health fill",
        anchorText = "Group Frames Layout Smooth health fill Health Text Power Bar Smooth fill party raid weiche Fuellung",
        keywords = {
            "group smooth fill", "party smooth fill", "raid smooth fill", "group frame smooth fill", "smooth health fill group frames", "smooth fill party raid", "party power smooth fill", "raid power smooth fill",
            "gruppen weiche fuellung", "gruppenrahmen weiche fuellung", "party weiche fuellung", "raid weiche fuellung", "weiche fuellung gruppe", "sanfte fuellung gruppe",
            "relleno suave grupo", "relleno suave banda", "remplissage fluide groupe", "remplissage fluide raid", "riempimento fluido gruppo", "preenchimento suave grupo",
            "плавное заполнение группы", "плавное заполнение рейда", "그룹 부드러운 채우기", "레이드 부드러운 채우기", "团队 平滑填充", "小队 平滑填充", "团队平滑填充", "小队平滑填充", "團隊 平滑填充", "隊伍 平滑填充", "團隊平滑填充", "隊伍平滑填充",
        },
        priority = 330,
    },
    {
        label = "How do I change health, power, or class colors?",
        answer = "Open Global Style > Colors. Bar Colors and Power Bar Colors control HP/power colors; Class Bar Colors controls class overrides.",
        pageKey = "opt_colors",
        target = "Opens: Global Style > Colors > Bar Colors",
        anchorText = "Bar Colors Power Bar Colors Class Bar Colors health hp power class color",
        keywords = { "health color", "hp color", "power color", "mana color", "class color", "bar color", "reaction color", "npc color", "color by class", "farbe", "farben" },
        priority = 35,
    },
    {
        label = "How do I change colors?",
        answer = "Most shared colors are in Global Style > Colors. Bar texture and border style controls are in Global Style > Bars.",
        pageKey = "opt_colors",
        target = "Opens: Global Style > Colors",
        anchorText = "Colors Bar Background Tint Bar Colors Unitframe Colors Class Bar Colors",
        keywords = { "colors", "colours", "farbe", "farben", "class color", "reaction color", "bar color", "background color", "unitframe colors" },
        priority = 10,
    },
    {
        label = "How do I change fonts and text?",
        answer = "Global Style > Fonts controls shared font settings. Unit pages contain per-unit name, health, and power text position and pattern settings.",
        pageKey = "opt_fonts",
        target = "Opens: Global Style > Fonts",
        anchorText = "Global Font Text Style Name & Power Colors Name Shortening font size outline shadow",
        keywords = { "font", "fonts", "text", "schrift", "name text", "hp text", "health text", "power text", "text size", "font size", "outline", "shadow", "name shortening", "make text bigger", "text too small" },
        priority = 25,
    },
    {
        label = "Where do I change HP, name, or power text position?",
        answer = "Open the unit page and use Text for name/health/power text patterns, anchors, offsets, font sizes, and layering.",
        pageKey = "uf_player",
        target = "Opens: Player > Text",
        anchorText = "Text name health power text anchor offset font size layer hp pattern",
        keywords = { "hp text position", "health text position", "name position", "power text position", "move text", "text anchor", "text offset", "name text", "health pattern", "power pattern", "percent hp" },
        priority = 35,
    },
    {
        label = "Where is the player, target, or unit level text?",
        answer = "Open the unit page > Status icons. Select Level in Indicator, then use Enabled, Anchor, X/Y Offset, Size, and Layer.",
        pageKey = "uf_player",
        target = "Opens: Player > Status icons > Indicator: Level",
        anchorText = "Status icons Indicator Level Enabled Anchor X Offset Y Offset Size Layer level text level indicator show level player level target level",
        keywords = { "level text", "level indicator", "player level", "target level", "unit level", "show level", "enable level", "disable level", "turn on level", "turn off level", "level anchor", "level position", "level positioning", "level x offset", "level y offset", "level size", "level layer", "status icons level", "status indicator level" },
        priority = 520,
    },
    {
        label = "How do I import, export, or switch profiles?",
        answer = "Open Profiles for active profile, spec auto-switching, import/export strings, legacy imports, and reset options.",
        pageKey = "profiles",
        target = "Opens: Profiles > Export / Import",
        anchorText = "Export / Import Profile Management Spec Profiles import export wago string",
        keywords = { "profile", "profiles", "import", "export", "wago", "copy profile", "reset profile", "profil", "spec profile", "profile string", "import string", "export string", "share profile" },
        priority = 35,
    },
    {
        label = "How do I reset positions or recover a broken layout?",
        answer = "Use Dashboard > Reset Positions for frame movers. Use Profiles only when you want to reset, copy, import, or replace profile data.",
        pageKey = "home",
        target = "Opens: Dashboard > Reset Positions",
        anchorText = "Reset Positions Factory Reset Profiles Print Help recovery support",
        keywords = { "reset positions", "reset movers", "frames off screen", "frame offscreen", "broken layout", "recover layout", "factory reset", "fullreset", "help reset", "position reset" },
        priority = 45,
    },
    {
        label = "How do I configure group frames?",
        answer = "Use Group Frames pages: Layout for size/growth/sorting, Health & Text for bars/text, Auras for Buff/Debuff placement, and Indicators for status icons.",
        pageKey = "gf_layout",
        target = "Opens: Group Frames > Layout",
        anchorText = "Group Frames Layout Health & Text Auras Buffs Debuffs Indicators party raid growth sorting",
        keywords = { "group frames", "groupframes", "party", "raid", "mythic raid", "gruppe", "raid frames", "layout", "growth", "sorting", "raidframes", "partyframes" },
        priority = 20,
    },
    {
        label = "How do I configure buffs and debuffs?",
        answer = "Use Auras for scope visibility, Auras > Style for text and cooldowns, and Auras > Filters for rules and blacklists. Unit and Group Frames > Auras control icon placement.",
        pageKey = "auras3",
        target = "Opens: Auras",
        anchorText = "Auras Buffs Debuffs Filters Blacklist Style buffs debuffs",
        keywords = SearchKeywordList(SEARCH_UNIT_AURA_DISPEL_KEYWORDS, {
            [0] = false,
            "buff", "buffs", "debuff", "debuffs", "auras", "aura", "cooldown", "filter", "only my buffs", "only my debuffs", "hide buffs", "show debuffs", "aura size", "aura position",
        }),
        priority = 120,
    },
    {
        label = "Can MSUF hide debuffs with a blacklist?",
        answer = "Open Auras > Filters. Unit-frame scopes support spell-ID blacklist entries; group-frame scopes also support category blacklists.",
        pageKey = "auras3_filters",
        target = "Opens: Auras > Filters",
        anchorText = "Filters Blacklist spell id category blacklist black list ignore list hide debuffs hide buffs hidden proc BL ElvUI Emlui",
        keywords = SearchKeywordList(SEARCH_UNIT_AURA_DISPEL_KEYWORDS, {
            [0] = false,
            "debuff blacklist",
            "debuff black list",
            "aura blacklist",
            "aura black list",
            "buff blacklist",
            "buff black list",
            "blacklist debuffs",
            "black list debuffs",
            "midnight simple unit frame",
            "midnight simple unit frames",
            "midnight simple unitframe",
            "midnight simple unitframes",
            "MSUF unitframe",
            "MSUF unit frames",
            "hide specific debuff",
            "hide specific debuffs",
            "hide a debuff",
            "icon for debuff",
            "hide debuff proc",
            "hide proc",
            "hidden proc",
            "proc hidden",
            "BL hidden proc",
            "BL debuff",
            "top right BL",
            "top right screenshot",
            "ElvUI debuff blacklist",
            "ElvUI blacklist",
            "Emlui debuff blacklist",
            "can MSUF do same",
            "ignore debuffs",
            "ignore aura",
            "ignore list",
            "global ignore list",
            "debuff ausblenden",
            "debuff verstecken",
            "aura ignorieren",
            "schwaechungszauber ausblenden",
        }),
        priority = 960,
    },
    {
        label = "How do I configure group buffs or debuffs?",
        answer = "Use Auras for group Buff/Debuff visibility, Auras > Style for text and stack presentation, and Group Frames > Auras for icon placement.",
        pageKey = "auras3",
        target = "Opens: Auras",
        anchorText = "Buffs Debuffs Style Filters Group Frames Auras",
        keywords = SearchKeywordList(SEARCH_DISPEL_DEBUFF_KEYWORDS, SEARCH_BLIZZARD_DISPEL_KEYWORDS, {
            [0] = false,
            "raid buffs", "raid debuffs", "party buffs", "party debuffs", "group auras", "group buffs", "group debuffs", "group cooldown swipe",
        }),
        priority = 210,
    },
    {
        label = "How do I add or change status icons and indicators?",
        answer = "Unit frame status icons are on each unit page. Group frame indicators are in Group Frames > Indicators.",
        pageKey = "gf_indicators",
        target = "Opens: Group Frames > Indicators",
        anchorText = "Indicators Status Icons Spell Indicators Corner Indicators role icon dispel aggro raid marker",
        keywords = SearchKeywordList(SEARCH_DISPEL_DEBUFF_KEYWORDS, SEARCH_HIGHLIGHT_BORDER_KEYWORDS, {
            [0] = false,
            "status icons", "indicator", "indicators", "corner indicator", "spell indicator", "raid marker", "role icon", "leader icon", "ready check", "aggro icon", "threat icon", "focus glow",
        }),
        priority = 190,
    },
    {
        label = "Why is something not updating immediately?",
        answer = "Some layout changes rebuild frames, while visual changes apply instantly. If needed, close and reopen the menu or reload after large profile/import changes.",
        pageKey = "opt_misc",
        target = "Opens: Global Style > Miscellaneous > Update intervals",
        anchorText = "Update intervals refresh reload apply not updating performance",
        keywords = { "not updating", "does not update", "refresh", "reload", "apply", "changes not showing", "aktualisiert nicht", "settings not applying", "profile not applying", "need reload" },
        priority = 20,
    },
    {
        label = "How do I disable Blizzard unit frames?",
        answer = "Open Global Style > Miscellaneous and use the Blizzard frame toggles.",
        pageKey = "opt_misc",
        target = "Opens: Global Style > Miscellaneous > Blizzard Frames",
        anchorText = "Blizzard Frames disable blizzard hide blizzard default frames playerframe",
        keywords = { "blizzard frames", "disable blizzard", "hide blizzard", "playerframe", "default frames", "standard frames", "hide default frames", "disable default unit frames", "blizzard player frame" },
        priority = 35,
    },
    {
        label = "Where is the minimap icon setting?",
        answer = "Open Global Style > Miscellaneous > Blizzard Frames and use Show MSUF minimap icon.",
        pageKey = "opt_misc",
        target = "Opens: Global Style > Miscellaneous > Blizzard Frames",
        anchorText = "Blizzard Frames Show MSUF minimap icon minimap button addon compartment",
        keywords = { "minimap", "minimap icon", "minimap button", "hide minimap icon", "show minimap icon", "addon compartment", "minikarte", "minimap symbol" },
        priority = 185,
    },
    {
        label = "Where are target sound settings?",
        answer = "Open Global Style > Miscellaneous > Blizzard Frames and use Play sound on Target/Target Lost.",
        pageKey = "opt_misc",
        target = "Opens: Global Style > Miscellaneous > Blizzard Frames",
        anchorText = "Blizzard Frames Play sound on Target Target Lost target sounds",
        keywords = { "target sound", "target sounds", "target lost sound", "play sound", "sound on target", "sound target lost", "ziel sound", "sounds" },
        priority = 170,
    },
    {
        label = "Where are menu snap or menu behavior settings?",
        answer = "Open Global Style > Miscellaneous > Menu behavior for edge snap and related menu behavior.",
        pageKey = "opt_misc",
        target = "Opens: Global Style > Miscellaneous > Menu behavior",
        anchorText = "Menu behavior edge snap windows snap menu resize ui scale menu scale",
        keywords = { "menu snap", "edge snap", "window snap", "menu behavior", "menu resize", "menu scale", "ui scale", "menu too big", "menu too small", "fenster einrasten" },
        priority = 65,
    },
    {
        label = "Where is Miscellaneous?",
        answer = "Open Global Style > Miscellaneous for language, menu behavior, update intervals, tooltips, Blizzard frames, minimap icon, and sounds.",
        pageKey = "opt_misc",
        target = "Opens: Global Style > Miscellaneous",
        anchorText = "Miscellaneous misc global style language menu behavior update intervals tooltips blizzard frames minimap sounds",
        keywords = { "misc", "miscellaneous", "where is misc", "where is miscellaneous", "global style misc", "global style miscellaneous", "verschiedenes", "allgemein", "sonstiges" },
        priority = 260,
    },
    {
        label = "How do I change range fading?",
        answer = "Open a unit page, then use Range Fade. It is available for Target, Target of Target, Focus, Focus Target, Pet, and Boss.",
        pageKey = "uf_target",
        target = "Opens: Target > Range Fade",
        anchorText = "Range Fade unit frame range check range checker distance check out of range range alpha distance fade target targettarget focus focustarget pet boss",
        keywords = { "range fade", "range check", "range checker", "unit frame range check", "distance check", "out of range", "range alpha", "distance fade", "reichweite", "reichweitencheck", "entfernung", "fade portrait", "frame fades", "out of range opacity" },
        priority = 45,
    },
        }
    end)
end
