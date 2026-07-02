local addonName, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

local Data = M.SearchData or {}
M.SearchData = Data

-- Search FAQ catalog shard 02.
-- Declarative help rows only; routing and scoring live in the search index layer.
if type(Data.RegisterFAQProvider) == "function" then
    Data.RegisterFAQProvider(function(env)
        local SearchKeywordList, SEARCH_DISPEL_DEBUFF_KEYWORDS, SEARCH_HIGHLIGHT_BORDER_KEYWORDS, SEARCH_BLIZZARD_DISPEL_KEYWORDS, SEARCH_UNIT_AURA_DISPEL_KEYWORDS =
            Data.FAQEnv(env, [[
                SearchKeywordList SEARCH_DISPEL_DEBUFF_KEYWORDS SEARCH_HIGHLIGHT_BORDER_KEYWORDS
                SEARCH_BLIZZARD_DISPEL_KEYWORDS SEARCH_UNIT_AURA_DISPEL_KEYWORDS
            ]])

        return Data.FAQRows({
            { l = "How do I make unit frames transparent?", a = "Open the unit page > Transparency for in-combat/out-of-combat alpha. Fade target chooses whether the sliders affect the whole frame, bars, HP, or backdrop. Group frame transparency is in Group Frames > Layout > Transparency.", p = "uf_player", t = "Opens: Player > Transparency", x = "Transparency alpha in combat out of combat opacity fade target whole frame layer fade bars hp bar backdrop preserve hp color text portrait visible", k = "transparent unitframe|transparent unit frame|alpha unitframe|opacity unitframe|fade frame|frame alpha|whole frame alpha|fade target|in combat alpha|out of combat alpha|transparent player frame|transparent target frame|hp bar alpha|health bar alpha|bars alpha|backdrop alpha|text portrait visible", y = 40 },
        },
        {
            {
                l = "How do I make group frames transparent?",
                a = "Open Group Frames > Layout > Transparency. Opacity controls in-combat and out-of-combat alpha;" ..
                    " Fade target chooses whole frame, bars, HP, or backdrop. Backdrop and Health layers set base" ..
                    " color, HP fill, and HP track opacity.",
                p = "gf_layout",
                t = "Opens: Group Frames > Layout > Transparency",
                x = "Group Frames Layout Transparency opacity fade target in combat out of combat alpha whole frame" ..
                    " bars HP backdrop HP fill HP track preserve HP color",
                k = SearchKeywordList(
                    "transparent group frames|transparent group frame|transparent raid frames",
                    "transparent party frames|group opacity|group alpha|raid opacity|party opacity",
                    "group frame transparency|raid frame transparency|party frame transparency|hp fill opacity",
                    "hp track opacity|group fade target"
                ),
                y = 42,
            },
            {
                l = "How do I change bar textures, gradients, or outlines?",
                a = "Open Global Style > Bars. Textures & Gradient controls shared bar textures; Frame Outline and" ..
                    " Highlight Borders control borders.",
                p = "opt_bars",
                t = "Opens: Global Style > Bars > Textures & Gradient",
                x = "Textures & Gradient Frame Outline Highlight Borders texture gradient outline border",
                k = SearchKeywordList(
                    "bar texture|health texture|power texture|change texture|gradient|outline|border|bar border",
                    "frame outline|highlight border|shared texture"
                ),
                y = 560,
            },
            {
                l = "How do I enable or disable rounded frames?",
                a = "Open Global Style > Bars > Rounded Texture. Use the master toggle for all rounded frame" ..
                    " textures, or the separate toggles for unit frames, group frames, power bars, and mouseover" ..
                    " highlights.",
                p = "opt_bars",
                t = "Opens: Global Style > Bars > Rounded Texture",
                x = "Rounded Texture Rounded frame texture Unit frames Group frames Power bars Mouseover highlights" ..
                    " rounded frames round corners",
                k = SearchKeywordList(
                    "rounded frames|rounded frame texture|rounded texture|round frames|round corners|rounded corners",
                    "frame corners|enable rounded frames|disable rounded frames|turn on rounded frames",
                    "turn off rounded frames|rounded frames on|rounded frames off|rounded unit frames",
                    "rounded unitframes|rounded group frames|rounded power bars|rounded mouseover",
                    "rounded mouseover highlights|abgerundete frames|abgerundete unitframes|runde kanten|runde ecken",
                    "abrundung|abrunden|rounded frames einschalten|rounded frames ausschalten",
                    "abgerundete frames einschalten|abgerundete frames ausschalten|runde kanten einschalten",
                    "runde kanten ausschalten|mouseover abgerundet|powerbar abgerundet"
                ),
                y = 620,
            },
            {
                l = "Where is Smooth fill for unit frames?",
                a = "Open the unit page, then use Frame Basics > Smooth fill for the health bar. For that unit's" ..
                    " power bar animation, open Power Bar > Smooth fill.",
                p = "uf_player",
                t = "Opens: Player > Frame Basics > Smooth fill",
                x = "Frame Basics Smooth fill Power Bar Smooth fill health animation power animation soft fill" ..
                    " weiche Fuellung",
                k = SearchKeywordList(
                    "smooth fill|smooth health fill|smooth power bar|soft fill|fluid fill|bar animation",
                    "health bar animation|power bar animation|where is smooth fill|find smooth fill",
                    "option der weichen fuellung finden|weiche fuellung|weichen fuellung|sanfte fuellung",
                    "fluessige fuellung|balken animation|lebensbalken animation|powerbar animation|relleno suave",
                    "llenado suave|animacion de barra|remplissage doux|remplissage fluide|animation de barre",
                    "riempimento fluido|riempimento morbido|preenchimento suave|animacao da barra|плавное заполнение",
                    "плавная заливка|анимация полосы|부드러운 채우기|막대 애니메이션|平滑填充|柔和填充|条动画|條動畫|平滑填充|柔和填充"
                ),
                y = 360,
            },
            {
                l = "Where is Smooth fill for party or raid frames?",
                a = "Open Group Frames > Layout for Smooth health fill. For group-frame power bars, open Group" ..
                    " Frames > Health & Text > Power Bar > Smooth fill.",
                p = "gf_layout",
                t = "Opens: Group Frames > Layout > Smooth health fill",
                x = "Group Frames Layout Smooth health fill Health Text Power Bar Smooth fill party raid weiche" ..
                    " Fuellung",
                k = SearchKeywordList(
                    "group smooth fill|party smooth fill|raid smooth fill|group frame smooth fill",
                    "smooth health fill group frames|smooth fill party raid|party power smooth fill",
                    "raid power smooth fill|gruppen weiche fuellung|gruppenrahmen weiche fuellung",
                    "party weiche fuellung|raid weiche fuellung|weiche fuellung gruppe|sanfte fuellung gruppe",
                    "relleno suave grupo|relleno suave banda|remplissage fluide groupe|remplissage fluide raid",
                    "riempimento fluido gruppo|preenchimento suave grupo|плавное заполнение группы",
                    "плавное заполнение рейда|그룹 부드러운 채우기|레이드 부드러운 채우기|团队 平滑填充|小队 平滑填充|团队平滑填充|小队平滑填充|團隊 平滑填充|隊伍 平滑填充",
                    "團隊平滑填充|隊伍平滑填充"
                ),
                y = 330,
            },
            {
                l = "How do I change health, power, or class colors?",
                a = "Open Global Style > Colors. Bar Colors and Power Bar Colors control HP/power colors; Class Bar" ..
                    " Colors controls class overrides.",
                p = "opt_colors",
                t = "Opens: Global Style > Colors > Bar Colors",
                x = "Bar Colors Power Bar Colors Class Bar Colors health hp power class color",
                k = SearchKeywordList(
                    "health color|hp color|power color|mana color|class color|bar color|reaction color|npc color",
                    "color by class|farbe|farben"
                ),
                y = 35,
            },
            {
                l = "How do I change colors?",
                a = "Most shared colors are in Global Style > Colors. Bar texture and border style controls are in" ..
                    " Global Style > Bars.",
                p = "opt_colors",
                t = "Opens: Global Style > Colors",
                x = "Colors Bar Background Tint Bar Colors Unitframe Colors Class Bar Colors",
                k = SearchKeywordList(
                    "colors|colours|farbe|farben|class color|reaction color|bar color|background color",
                    "unitframe colors"
                ),
                y = 10,
            },
            {
                l = "How do I change fonts and text?",
                a = "Global Style > Fonts controls shared font settings. Unit pages contain per-unit name, health," ..
                    " and power text position and pattern settings.",
                p = "opt_fonts",
                t = "Opens: Global Style > Fonts",
                x = "Global Font Text Style Name & Power Colors Name Shortening font size outline shadow",
                k = SearchKeywordList(
                    "font|fonts|text|schrift|name text|hp text|health text|power text|text size|font size|outline",
                    "shadow|name shortening|make text bigger|text too small"
                ),
                y = 25,
            },
            {
                l = "Where do I change HP, name, or power text position?",
                a = "Open the unit page and use Text for name/health/power text patterns, anchors, offsets, font" ..
                    " sizes, and layering.",
                p = "uf_player",
                t = "Opens: Player > Text",
                x = "Text name health power text anchor offset font size layer hp pattern",
                k = SearchKeywordList(
                    "hp text position|health text position|name position|power text position|move text|text anchor",
                    "text offset|name text|health pattern|power pattern|percent hp"
                ),
                y = 35,
            },
            {
                l = "Where is the player, target, or unit level text?",
                a = "Open the unit page > Status icons. Select Level in Indicator, then use Enabled, Anchor, X/Y" ..
                    " Offset, Size, and Layer.",
                p = "uf_player",
                t = "Opens: Player > Status icons > Indicator: Level",
                x = "Status icons Indicator Level Enabled Anchor X Offset Y Offset Size Layer level text level" ..
                    " indicator show level player level target level",
                k = SearchKeywordList(
                    "level text|level indicator|player level|target level|unit level|show level|enable level",
                    "disable level|turn on level|turn off level|level anchor|level position|level positioning",
                    "level x offset|level y offset|level size|level layer|status icons level|status indicator level"
                ),
                y = 520,
            },
            {
                l = "How do I import, export, or switch profiles?",
                a = "Open Profiles for active profile, spec auto-switching, import/export strings, legacy imports," ..
                    " and reset options.",
                p = "profiles",
                t = "Opens: Profiles > Export / Import",
                x = "Export / Import Profile Management Spec Profiles import export wago string",
                k = SearchKeywordList(
                    "profile|profiles|import|export|wago|copy profile|reset profile|profil|spec profile",
                    "profile string|import string|export string|share profile"
                ),
                y = 35,
            },
            {
                l = "How do I reset positions or recover a broken layout?",
                a = "Use Dashboard > Reset Positions for frame movers. Use Profiles only when you want to reset," ..
                    " copy, import, or replace profile data.",
                p = "home",
                t = "Opens: Dashboard > Reset Positions",
                x = "Reset Positions Factory Reset Profiles Print Help recovery support",
                k = SearchKeywordList(
                    "reset positions|reset movers|frames off screen|frame offscreen|broken layout|recover layout",
                    "factory reset|fullreset|help reset|position reset"
                ),
                y = 45,
            },
            {
                l = "How do I configure group frames?",
                a = "Use Group Frames pages: Layout for size/growth/sorting, Health & Text for bars/text, Auras for" ..
                    " Buff/Debuff placement, and Status & Indicators for status icons.",
                p = "gf_layout",
                t = "Opens: Group Frames > Layout",
                x = "Group Frames Layout Health & Text Auras Buffs Debuffs Status Indicators party raid growth sorting",
                k = SearchKeywordList(
                    "group frames|groupframes|party|raid|mythic raid|gruppe|raid frames|layout|growth|sorting",
                    "raidframes|partyframes"
                ),
                y = 20,
            },
        },
        {
            { "How do I configure buffs and debuffs?", "Use the relevant Unit Frame or Group Frames > Auras page for on/off, placement and icon grid controls. Use Auras > Style for text and cooldowns, and Auras > Filters for rules and blacklists.", "auras3_styling", "Opens: Auras > Style", "Auras Buffs Debuffs Filters Blacklist Style buffs debuffs", SearchKeywordList(SEARCH_UNIT_AURA_DISPEL_KEYWORDS, "buff|buffs|debuff|debuffs|auras|aura|cooldown|filter|only my buffs|only my debuffs|hide buffs|show debuffs|aura size|aura position"), 120, },
            { "Can MSUF hide debuffs with a blacklist?", "Open Auras > Filters. Unit-frame scopes support spell-ID blacklist entries; group-frame scopes also support category blacklists.", "auras3_filters", "Opens: Auras > Filters", "Filters Blacklist spell id category blacklist black list ignore list hide debuffs hide buffs hidden proc BL ElvUI Emlui", SearchKeywordList(SEARCH_UNIT_AURA_DISPEL_KEYWORDS, "debuff blacklist|debuff black list|aura blacklist|aura black list|buff blacklist|buff black list|blacklist debuffs|black list debuffs|midnight simple unit frame|midnight simple unit frames|midnight simple unitframe|midnight simple unitframes|MSUF unitframe|MSUF unit frames|hide specific debuff|hide specific debuffs|hide a debuff|icon for debuff|hide debuff proc|hide proc|hidden proc|proc hidden|BL hidden proc|BL debuff|top right BL|top right screenshot|ElvUI debuff blacklist|ElvUI blacklist|Emlui debuff blacklist|can MSUF do same|ignore debuffs|ignore aura|ignore list|global ignore list|debuff ausblenden|debuff verstecken|aura ignorieren|schwaechungszauber ausblenden"), 960, },
            { "How do I configure group buffs or debuffs?", "Use Group Frames > Auras for group Buff/Debuff on/off, placement and icon grid controls. Use Auras > Style for text and stack presentation.", "gf_auras", "Opens: Group Frames > Auras", "Buffs Debuffs Style Filters Group Frames Auras", SearchKeywordList(SEARCH_DISPEL_DEBUFF_KEYWORDS, SEARCH_BLIZZARD_DISPEL_KEYWORDS, "raid buffs|raid debuffs|party buffs|party debuffs|group auras|group buffs|group debuffs|group cooldown swipe"), 210, },
            { "How do I add or change status icons and indicators?", "Unit frame status icons are on each unit page. Group frame status and indicators are in Group Frames > Status & Indicators.", "gf_indicators", "Opens: Group Frames > Status & Indicators", "Status Indicators Status Icons Spell Indicators Corner Indicators role icon dispel aggro raid marker", SearchKeywordList(SEARCH_DISPEL_DEBUFF_KEYWORDS, SEARCH_HIGHLIGHT_BORDER_KEYWORDS, "status icons|status and indicators|indicator|indicators|corner indicator|spell indicator|raid marker|role icon|leader icon|ready check|aggro icon|threat icon|focus glow"), 190, },
        },
        {
            {
                l = "Why is something not updating immediately?",
                a = "Some layout changes rebuild frames, while visual changes apply instantly. If needed, close and" ..
                    " reopen the menu or reload after large profile/import changes.",
                p = "opt_misc",
                t = "Opens: Global Style > Miscellaneous",
                x = "refresh reload apply not updating settings",
                k = SearchKeywordList(
                    "not updating|does not update|refresh|reload|apply|changes not showing|aktualisiert nicht",
                    "settings not applying|profile not applying|need reload"
                ),
                y = 20,
            },
            {
                l = "How do I disable Blizzard unit frames?",
                a = "Open Global Style > Miscellaneous and use the Blizzard frame toggles.",
                p = "opt_misc",
                t = "Opens: Global Style > Miscellaneous > Blizzard Frames",
                x = "Blizzard Frames disable blizzard hide blizzard default frames playerframe",
                k = SearchKeywordList(
                    "blizzard frames|disable blizzard|hide blizzard|playerframe|default frames|standard frames",
                    "hide default frames|disable default unit frames|blizzard player frame"
                ),
                y = 35,
            },
            {
                l = "Where is the minimap icon setting?",
                a = "Open Global Style > Miscellaneous > Blizzard Frames and use Show MSUF minimap icon.",
                p = "opt_misc",
                t = "Opens: Global Style > Miscellaneous > Blizzard Frames",
                x = "Blizzard Frames Show MSUF minimap icon minimap button addon compartment",
                k = SearchKeywordList(
                    "minimap|minimap icon|minimap button|hide minimap icon|show minimap icon|addon compartment",
                    "minikarte|minimap symbol"
                ),
                y = 185,
            },
            {
                l = "Where are target sound settings?",
                a = "Open Global Style > Miscellaneous > Blizzard Frames and use Play sound on Target/Target Lost.",
                p = "opt_misc",
                t = "Opens: Global Style > Miscellaneous > Blizzard Frames",
                x = "Blizzard Frames Play sound on Target Target Lost target sounds",
                k = SearchKeywordList(
                    "target sound|target sounds|target lost sound|play sound|sound on target|sound target lost",
                    "ziel sound|sounds"
                ),
                y = 170,
            },
            {
                l = "Where are menu snap or menu behavior settings?",
                a = "Open Global Style > Miscellaneous > Menu behavior for edge snap and related menu behavior.",
                p = "opt_misc",
                t = "Opens: Global Style > Miscellaneous > Menu behavior",
                x = "Menu behavior edge snap windows snap menu resize ui scale menu scale",
                k = SearchKeywordList(
                    "menu snap|edge snap|window snap|menu behavior|menu resize|menu scale|ui scale|menu too big",
                    "menu too small|fenster einrasten"
                ),
                y = 65,
            },
            {
                l = "Where is Miscellaneous?",
                a = "Open Global Style > Miscellaneous for language, menu behavior, startup notices, tooltips," ..
                    " Blizzard frames, minimap icon, and sounds.",
                p = "opt_misc",
                t = "Opens: Global Style > Miscellaneous",
                x = "Miscellaneous misc global style language menu behavior startup notices tooltips blizzard frames" ..
                    " minimap sounds",
                k = SearchKeywordList(
                    "misc|miscellaneous|where is misc|where is miscellaneous|global style misc",
                    "global style miscellaneous|verschiedenes|allgemein|sonstiges"
                ),
                y = 260,
            },
            {
                l = "How do I change range fading?",
                a = "Open a unit page, then use Range Fade. It is available for Target, Target of Target, Focus," ..
                    " Focus Target, Pet, and Boss.",
                p = "uf_target",
                t = "Opens: Target > Range Fade",
                x = "Range Fade unit frame range check range checker distance check out of range range alpha" ..
                    " distance fade target targettarget focus focustarget pet boss",
                k = SearchKeywordList(
                    "range fade|range check|range checker|unit frame range check|distance check|out of range",
                    "range alpha|distance fade|reichweite|reichweitencheck|entfernung|fade portrait|frame fades",
                    "out of range opacity"
                ),
                y = 45,
            },
        })
    end)
end
