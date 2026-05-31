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
        label = "Why can I not change something in combat?",
        answer = "WoW blocks some protected frame changes in combat. Leave combat, then apply layout, anchoring, enable/disable, profile, or protected-frame changes.",
        pageKey = "opt_misc",
        target = "Opens: Global Style > Miscellaneous",
        anchorText = "combat lockdown protected frames settings in combat out of combat",
        keywords = { "combat lockdown", "cannot change in combat", "can't change in combat", "protected frame", "blocked in combat", "in combat settings", "combat error", "leave combat", "why can't i move in combat" },
        priority = 50,
    },
    {
        label = "Where did the menu window go?",
        answer = "Open MSUF again with /msuf. If frame positions are broken, use Dashboard > Reset Positions or the profile/reset tools.",
        pageKey = "home",
        target = "Opens: Dashboard > Reset Positions",
        anchorText = "Reset Positions menu window offscreen dashboard slash msuf recovery",
        keywords = { "menu gone", "menu missing", "window offscreen", "menu offscreen", "can't open menu", "cannot open menu", "lost menu", "options window gone", "reset menu position", "where is menu" },
        priority = 45,
    },
    {
        label = "Why did my profile or import look wrong?",
        answer = "Open Profiles. Check active profile, spec profiles, import/export, and legacy imports. Large imports may need a reload.",
        pageKey = "profiles",
        target = "Opens: Profiles > Profile Management / Export / Import",
        anchorText = "Profile Management Spec Profiles Export Import legacy imports active profile reload",
        keywords = { "profile wrong", "profile missing", "profile gone", "import failed", "import looks wrong", "wago import wrong", "profile not loading", "spec profile wrong", "active profile", "legacy import", "copy profile" },
        priority = 55,
    },
    {
        label = "Why are party or raid frames not showing?",
        answer = "Open Group Frames > Layout. Check enable/show behavior, player/solo visibility, layout mode, frame scaling, and anchoring.",
        pageKey = "gf_layout",
        target = "Opens: Group Frames > Layout > General",
        anchorText = "General Layout show hide player solo party raid enable frame scaling anchoring",
        keywords = { "party frames not showing", "raid frames not showing", "group frames missing", "party frames gone", "raid frames gone", "hide player solo", "show party frames", "show raid frames", "group frames invisible", "party hidden", "raid hidden" },
        priority = 60,
    },
    {
        label = "Where do I make names shorter?",
        answer = "Open Global Style > Fonts > Name Shortening for unit names. Castbar spell name shortening is in Global Style > Castbar > Name Shortening.",
        pageKey = "opt_fonts",
        target = "Opens: Global Style > Fonts > Name Shortening",
        anchorText = "Name Shortening names too long max name length castbar spell name shortening",
        keywords = { "name too long", "names too long", "shorten names", "name shortening", "long names", "cut names", "truncate names", "player name too long", "target name too long" },
        priority = 45,
    },
    {
        label = "Why are group names still shortened when name shortening is off?",
        answer = "Global Style > Fonts has Shared settings plus per-scope font overrides. If Party or Raid uses custom font settings, its Name Shortening can stay enabled even when Shared is off. Select Party/Raid in Fonts or reset the font override.",
        pageKey = "opt_fonts",
        target = "Opens: Global Style > Fonts > Name Shortening / scope override",
        anchorText = "Name Shortening Use custom settings for this scope Overrides Party Raid group frame name truncation font override shared changes",
        keywords = {
            "see image not sure whats happening here",
            "name shortening off but group names still shortened",
            "shorten names disabled but names still cut",
            "group names still shortened",
            "party names still shortened",
            "raid names still shortened",
            "group frame name truncation override",
            "group frame font override name shortening",
            "shared name shortening does not affect party raid",
            "getting confused with overrides",
            "no group frame override",
            "namen werden gekuerzt obwohl namenskuerzung aus",
            "namenskuerzung aus aber gruppennamen gekuerzt",
            "gruppenframe override namenskuerzung",
            "raid override namenskuerzung",
            "acortar nombres desactivado pero los nombres siguen acortados",
            "abreviar nombres desactivado pero nombres cortados",
            "marcos de grupo anulacion nombres",
            "sobrescritura de marcos de grupo nombres",
            "raccourcissement des noms desactive mais noms encore raccourcis",
            "noms raccourcis malgre option desactivee",
            "remplacement cadres de groupe noms",
            "abbreviazione nomi disattivata ma nomi ancora abbreviati",
            "nomi gruppo abbreviati override",
            "encurtar nomes desativado mas nomes ainda encurtados",
            "quadros de grupo substituicao nomes",
            "сокращение имен отключено но имена сокращаются",
            "сокращение имён выключено но имена сокращаются",
            "оверрайд рамок группы сокращение имен",
            "переопределение рамок группы имена",
            "이름 줄이기 꺼짐인데 이름이 줄어듦",
            "이름 줄이기 꺼짐 이름 줄어듦",
            "그룹 프레임 재정의 이름 줄이기",
            "名字缩短关闭但仍然缩短",
            "姓名缩短关闭但仍然缩短",
            "团队框架覆盖名字缩短",
            "小队框架覆盖名字缩短",
            "名字縮短關閉但仍然縮短",
            "姓名縮短關閉但仍然縮短",
            "團隊框架覆蓋名字縮短",
            "隊伍框架覆蓋名字縮短",
        },
        priority = 650,
    },
    {
        label = "Where do I make the menu bigger or smaller?",
        answer = "Use the Dashboard scale controls for menu scale or UI scale. You can also resize the MSUF2 window from its corner.",
        pageKey = "home",
        target = "Opens: Dashboard > UI Scale / Menu Scale",
        anchorText = "UI Scale Menu Scale resize window bigger smaller dashboard",
        keywords = { "menu too big", "menu too small", "make menu bigger", "make menu smaller", "ui scale", "menu scale", "resize window", "options too big", "options too small" },
        priority = 45,
    },
    {
        label = "Where do I change click-through auras?",
        answer = "Open the unit page > Auras for click-through aura behavior. Gameplay contains click-cast and targeting behavior.",
        pageKey = "uf_player",
        target = "Opens: Player > Auras",
        anchorText = "Auras click-through auras click through click cast gameplay targeting",
        keywords = { "clickthrough auras", "click-through auras", "click through auras", "auras block mouse", "can't click through buffs", "aura mouse", "click aura", "click cast not working", "mouse blocked by auras" },
        priority = 45,
    },
    {
        label = "Where are optional modules or style modules?",
        answer = "Open Modules > Style for optional style modules such as portrait decoration and dropdown styling.",
        pageKey = "modules",
        target = "Opens: Modules > Style",
        anchorText = "Modules Style portrait decoration dropdown style optional modules skins",
        keywords = { "modules", "optional modules", "style modules", "portrait decoration", "portrait deco", "module style", "skins" },
        priority = 70,
    },
    {
        label = "How do I show party or raid frames while solo?",
        answer = "Open Group Frames > Layout and check the solo/player visibility options. That is where MSUF controls whether party-style frames appear when you are alone.",
        pageKey = "gf_layout",
        target = "Opens: Group Frames > Layout > General",
        anchorText = "General show solo show player party raid group frames visibility",
        keywords = { "show party frames while solo", "show raid frames while solo", "solo raid frames", "solo party frames", "always show party frames", "always show raid frames", "show player solo", "show self in party", "party frames when alone", "raid frames when alone" },
        priority = 90,
    },
    {
        label = "How do I hide myself from party or raid frames?",
        answer = "Open Group Frames > Layout. The General and Sorting sections control player/self visibility and how player units are ordered in group frames.",
        pageKey = "gf_layout",
        target = "Opens: Group Frames > Layout > General",
        anchorText = "General Show player Player first in role Sorting party raid self visibility",
        keywords = { "hide myself from party", "hide player in party", "hide self in party frames", "show player in party frames", "player in raid frames", "self in party frames", "show player", "player first in role", "party contains me" },
        priority = 75,
    },
    {
        label = "How do I show only my HoTs or buffs on party frames?",
        answer = "Open Auras > Filters for group-frame aura filters, then use Group Frames > Auras for placement.",
        pageKey = "auras3_filters",
        target = "Opens: Auras > Filters",
        anchorText = "Buffs own buffs only mine HoTs healer buffs group frames",
        keywords = { "show only my buffs party", "only my hots", "only my HoTs", "track my hots", "track my heals", "show my rejuv", "show my renew", "show my shields", "own buffs party", "own buffs raid", "healer hots", "druid hots", "priest hots" },
        priority = 120,
    },
    {
        label = "How do I make my own buffs or debuffs bigger?",
        answer = "Open Auras > Style for text and cooldowns. Icon size and placement live on the relevant unit page > Auras or Group Frames > Auras.",
        pageKey = "auras3_styling",
        target = "Opens: Auras > Style",
        anchorText = "Auras icon size own buffs own debuffs custom buffs custom debuffs group buffs debuffs",
        keywords = { "make my buffs bigger", "make own buffs bigger", "make my debuffs bigger", "bigger own buffs", "bigger own debuffs", "my buffs bigger", "my debuffs bigger", "own aura size", "personal debuff size", "personal buff size" },
        priority = 95,
    },
    {
        label = "How do I move buff or debuff icons near a unit frame?",
        answer = "Open the unit page > Auras or the aura Position Popup for unit-frame aura placement. Buff/debuff icons are configured as aura layout, not moved through MSUF Edit Mode.",
        pageKey = "uf_player",
        target = "Opens: Player > Auras",
        anchorText = "Auras buffs debuffs position anchor rows spacing unit frame auras",
        keywords = { "move buffs", "move debuffs", "move buff icons", "move debuff icons", "buff icons next to unit frame", "debuff icons next to unit frame", "buffs under portrait", "debuffs under portrait", "unlock buffs debuffs", "buff debuff anchor", "anchor debuffs to buffs", "buffs on top", "debuffs on top" },
        priority = 110,
    },
    {
        label = "How do I add a specific boss debuff to the blacklist?",
        answer = "Open Auras > Filters for unit spell-ID blacklists and group category blacklists. Group aura placement stays in Group Frames > Auras.",
        pageKey = "auras3_filters",
        target = "Opens: Auras > Filters",
        anchorText = "Filters Blacklist buffs debuffs boss debuffs spell id raid debuffs",
        keywords = { "boss debuff missing", "boss debuffs not showing", "raid debuff missing", "add boss debuff", "add spell id", "spell id", "spellid", "debuff stack count", "raid mechanic debuff" },
        priority = 125,
    },
    {
        label = "How do I show only dispellable debuffs?",
        answer = "Open Auras > Filters for unit-frame and group-frame Debuff filtering. Party/Raid status indicators stay in Group Frames > Indicators.",
        pageKey = "auras3_filters",
        target = "Opens: Auras > Filters",
        anchorText = "Filters Indicators dispel magic curse poison disease debuffs debuff type border group frames",
        keywords = SearchKeywordList(SEARCH_DISPEL_DEBUFF_KEYWORDS, SEARCH_UNIT_AURA_DISPEL_KEYWORDS, {
            [0] = false,
            "only dispellable debuffs", "dispellable debuffs", "dispel debuffs", "magic debuff", "curse debuff", "poison debuff", "disease debuff", "debuff type border", "debuff color border", "show dispels", "healer dispels",
        }),
        priority = 260,
    },
    {
        label = "How do I move or resize target, focus, or boss castbars?",
        answer = "Use MSUF Edit Mode to drag supported castbars. Per-unit castbar enable/icon/text options are on each unit page; shared castbar style is in Global Style > Castbar.",
        pageKey = "home",
        target = "Opens: Dashboard > MSUF Edit Mode",
        anchorText = "MSUF Edit Mode move castbars target castbar focus castbar boss castbar player castbar resize",
        keywords = { "move target castbar", "move focus castbar", "move boss castbar", "move enemy castbar", "resize target castbar", "resize focus castbar", "target cast bar position", "focus cast bar position", "boss cast bar position", "castbar edit mode", "drag castbar" },
        priority = 115,
    },
    {
        label = "How do I stop castbars covering party or raid frames?",
        answer = "MSUF group frames do not use per-player castbars over the health frame. For MSUF castbar positioning, use MSUF Edit Mode and Global Style > Castbar.",
        pageKey = "opt_castbar",
        target = "Opens: Global Style > Castbar",
        anchorText = "Castbar position edit mode group frames party raid castbars over health",
        keywords = { "party castbar covering health", "raid castbar over frame", "castbar covers party frame", "castbar covers raid frame", "group castbar position", "party frame castbar", "raid frame castbar", "cast bars on raid frames" },
        priority = 70,
    },
    {
        label = "Why can I not unlock or drag buffs and debuffs?",
        answer = "MSUF Edit Mode moves frames and supported castbars. Aura icon placement is controlled from each unit page > Auras or Group Frames > Auras.",
        pageKey = "uf_player",
        target = "Opens: Player > Auras",
        anchorText = "Auras aura position buffs debuffs edit mode drag unlock frames",
        keywords = { "can't unlock buffs", "can't unlock debuffs", "cannot move buffs", "cannot move debuffs", "unlock buff frames", "unlock debuff frames", "drag buffs debuffs", "buffs not movable", "debuffs not movable", "lock frames buffs", "unlock frames buffs" },
        priority = 130,
    },
    {
        label = "How do I make raid frames cleaner for healing?",
        answer = "Use Group Frames > Layout for frame size and spacing, Auras for Buff/Debuff placement, and Indicators for fixed-position status icons.",
        pageKey = "gf_layout",
        target = "Opens: Group Frames > Layout / Auras / Indicators",
        anchorText = "Layout Auras Buffs Debuffs Indicators healer clean raid frames HoTs fixed positions",
        keywords = { "clean raid frames", "healer raid frames", "minimal raid frames", "declutter raid frames", "fixed hots positions", "fixed aura positions", "healer hots indicators", "raid frame indicators", "too much information raid frames", "healing frames setup" },
        priority = 100,
    },
    {
        label = "How do I change dead, offline, AFK, or ready-check indicators?",
        answer = "Open Group Frames > Indicators for status icons, role/leader/assist, ready check, focus glow, and other group-frame state indicators.",
        pageKey = "gf_indicators",
        target = "Opens: Group Frames > Indicators > Status Icons",
        anchorText = "Status Icons ready check dead ghost offline afk dnd leader assist role icon",
        keywords = { "dead icon", "offline icon", "afk icon", "dnd icon", "ghost icon", "ready check icon", "leader icon", "assist icon", "status icons", "group status icon", "raid status icon" },
        priority = 85,
    },
    {
        label = "How do I hide realm names or shorten player names?",
        answer = "Open Global Style > Fonts > Name Shortening. It controls name shortening globally; unit text placement is on each unit page > Text.",
        pageKey = "opt_fonts",
        target = "Opens: Global Style > Fonts > Name Shortening",
        anchorText = "Name Shortening realm names short names player names font text",
        keywords = { "hide realm names", "remove realm names", "short names", "shorten player names", "names too long", "realm name showing", "server name showing", "name realm", "truncate names" },
        priority = 90,
    },
    {
        label = "How do I get class-colored health bars or names?",
        answer = "Open Global Style > Colors for class bar colors and unitframe colors. Group health colors are in Group Frames > Health & Text.",
        pageKey = "opt_colors",
        target = "Opens: Global Style > Colors > Class Bar Colors",
        anchorText = "Class Bar Colors Unitframe Colors Group Health Colors class colored names health bars",
        keywords = { "class colored health", "class colored names", "class color names", "class color health bars", "green health bars", "health bar class color", "target class color", "player class color", "raid class colors" },
        priority = 105,
    },
    {
        label = "How do I change click-casting so aura icons do not block heals?",
        answer = "Open the relevant unit page > Auras for click-through aura behavior, then use Gameplay for click-cast, mouseover, and targeting behavior.",
        pageKey = "uf_player",
        target = "Opens: Player > Auras",
        anchorText = "Auras click-through auras Gameplay click cast mouseover healing party frames",
        keywords = { "auras block heals", "buffs block click casting", "debuffs block click cast", "can't heal through buffs", "mouseover heal blocked", "click cast blocked by aura", "heal mouseover auras", "party frame click through buffs" },
        priority = 115,
    },
    {
        label = "How do I open the MSUF options?",
        answer = "Use /msuf to open MSUF2. The Dashboard also contains reset, support, profile, and scale tools.",
        pageKey = "home",
        target = "Opens: Dashboard",
        anchorText = "Dashboard slash command msuf options menu support profiles reset",
        keywords = { "how to open msuf", "open msuf", "open options", "open addon options", "slash command", "/msuf", "msuf menu", "where is options", "addon options", "config menu", "configuration menu", "settings menu" },
        priority = 700,
    },
        }
    end)
end
