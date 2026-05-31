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
        label = "Where is the unit frame range check?",
        answer = "Open the matching unit page > Range Fade. Group range fade is still in Group Frames > Health & Text.",
        pageKey = "uf_target",
        target = "Opens: Target > Range Fade",
        anchorText = "Range Fade unit frame range check range checker distance check out of range alpha target targettarget focus focustarget pet boss",
        keywords = { "unit frame range check", "unitframe range check", "unit frames range check", "range check unitframe", "range check unit frame", "range checker", "distance check", "distance checker", "out of range unit frame", "out of range frames", "target out of range", "focus out of range", "boss out of range", "target range fade", "focus range fade", "boss range fade", "reichweitencheck", "reichweite check", "entfernung check" },
        priority = 165,
    },
    {
        label = "How do I change language or translations?",
        answer = "Open Global Style > Miscellaneous > Language. Translation coverage can also be checked with the /msuf locale command.",
        pageKey = "opt_misc",
        target = "Opens: Global Style > Miscellaneous > Language",
        anchorText = "Language locale localization translation deDE ruRU frFR esES",
        keywords = { "language", "locale", "translation", "translations", "localization", "localisation", "sprache", "deutsch", "english", "russian", "french", "spanish" },
        priority = 25,
    },
    {
        label = "How do I change unitframe tooltips?",
        answer = "Open Global Style > Miscellaneous > Unitframe tooltips to control mouseover tooltip behavior.",
        pageKey = "opt_misc",
        target = "Opens: Global Style > Miscellaneous > Unitframe tooltips",
        anchorText = "Unitframe tooltips tooltip mouseover hide tooltip show tooltip",
        keywords = { "tooltip", "tooltips", "unit tooltip", "mouseover tooltip", "hide tooltip", "show tooltip", "tooltip on mouseover" },
        priority = 20,
    },
    {
        label = "How do I change click, mouseover, or targeting behavior?",
        answer = "Open Gameplay for crosshair, click-cast, focus/target modifier, mouseover, interaction, and targeting options.",
        pageKey = "gameplay",
        target = "Opens: Gameplay",
        anchorText = "Gameplay click cast focus target modifier mouseover interaction targeting combat crosshair",
        keywords = { "click cast", "clickcast", "click casting", "clickthrough", "click-through", "mouseover", "target modifier", "focus modifier", "mouse buttons", "targeting", "combat crosshair" },
        priority = 30,
    },
    {
        label = "How do I change class resources?",
        answer = "Open Class Resources for combo points, holy power, soul shards, chi, maelstrom, essence, runes, stagger, detached power, and alternative mana.",
        pageKey = "classpower",
        target = "Opens: Class Resources",
        anchorText = "Class Resources Layout Behavior Style Auto-Hide Detached Power Bar Alternative Mana",
        keywords = { "class resource", "class resources", "combo points", "holy power", "soul shards", "chi", "maelstrom", "essence", "runes", "stagger", "alternative mana", "alt mana", "detached power" },
        priority = 25,
    },
    {
        label = "How do I hide or show a unit frame?",
        answer = "Open that unit page and use Frame Basics > Enable. Boss frames also have Boss Layout options.",
        pageKey = "uf_player",
        target = "Opens: Player > Frame Basics",
        anchorText = "Frame Basics Enable hide show player target focus boss pet",
        keywords = { "hide unitframe", "show unitframe", "disable unitframe", "enable unitframe", "hide player frame", "hide target frame", "hide focus frame", "hide pet frame", "show player frame", "enable target frame", "disable boss frame" },
        priority = 30,
    },
    {
        label = "Where are load conditions?",
        answer = "Open the matching unit page and use Load Conditions to control when player, target, focus, boss, or pet frames are shown.",
        pageKey = "uf_player",
        target = "Opens: Player > Load Conditions",
        anchorText = "Load Conditions show hide visibility player target focus boss pet combat group instance",
        keywords = { "load conditions", "visibility conditions", "show conditions", "hide conditions", "when to show frame", "when to hide frame", "frame visibility", "combat visibility", "instance visibility", "ladebedingungen", "sichtbarkeit" },
        priority = 80,
    },
    {
        label = "Why is my player, target, focus, or pet frame gone?",
        answer = "Open the matching unit page and check Frame Basics > Enable, Load Conditions, alpha/transparency, and range fade.",
        pageKey = "uf_player",
        target = "Opens: Player > Frame Basics",
        anchorText = "Frame Basics Enable Load Conditions Transparency Range Fade player target focus pet gone missing invisible",
        keywords = { "player frame gone", "target frame gone", "focus frame gone", "pet frame gone", "unitframe missing", "unitframe invisible", "frame not visible", "frame disappeared", "cannot see player frame", "target not showing", "focus not showing", "pet not showing", "unitframe hidden" },
        priority = 55,
    },
    {
        label = "Where is Target of Target?",
        answer = "Open Target of Target. Use Frame Basics to enable it, Text for labels, and Anchoring/Edit Mode for placement.",
        pageKey = "uf_targettarget",
        target = "Opens: Target of Target > Frame Basics",
        anchorText = "Frame Basics Target of Target ToT Enable Text Anchoring",
        keywords = { "target of target", "tot", "targettarget", "target target", "where is tot", "tot missing", "show target of target", "enable tot", "target of target frame" },
        priority = 45,
    },
    {
        label = "Where is Focus Target?",
        answer = "Open Focus Target. Use Frame Basics to enable it; it only appears when Focus is enabled and your focus has a target.",
        pageKey = "uf_focustarget",
        target = "Opens: Focus Target > Frame Basics",
        anchorText = "Frame Basics Focus Target Enable Text Anchoring",
        keywords = { "focus target", "focustarget", "focus target frame", "ft frame", "where is focus target", "focus target missing", "show focus target", "enable focus target" },
        priority = 45,
    },
    {
        label = "Why is my castbar not showing?",
        answer = "Open the unit page > Castbar to enable that unit's castbar. Shared castbar visuals are in Global Style > Castbar.",
        pageKey = "uf_player",
        target = "Opens: Player > Castbar",
        anchorText = "Castbar Enable player target focus boss pet show interrupt icon text",
        keywords = { "castbar not showing", "castbar missing", "player castbar gone", "target castbar missing", "focus castbar missing", "boss castbar missing", "show castbar", "enable castbar", "my castbar disappeared", "no cast bar" },
        priority = 55,
    },
    {
        label = "Where do I change castbar spell names or long cast text?",
        answer = "Open Global Style > Castbar > Name Shortening for castbar spell name shortening, max length, and reserved space.",
        pageKey = "opt_castbar",
        target = "Opens: Global Style > Castbar > Name Shortening",
        anchorText = "Name Shortening spell name max name length reserved space castbar",
        keywords = { "cast name too long", "spell name too long", "castbar text too long", "shorten castbar name", "castbar spell name", "max name length", "reserved space", "cast text overlap" },
        priority = 45,
    },
    {
        label = "Why are class resources missing?",
        answer = "Open Class Resources. Check Enable, Auto-Hide, class-specific behavior, detached power, and alternative mana settings.",
        pageKey = "classpower",
        target = "Opens: Class Resources > Layout / Auto-Hide",
        anchorText = "Class Resources Enable Auto-Hide Behavior Detached Power Bar Alternative Mana",
        keywords = { "class resources missing", "combo points missing", "holy power missing", "soul shards missing", "chi missing", "maelstrom missing", "essence missing", "runes missing", "stagger missing", "class power not showing", "resource bar missing" },
        priority = 55,
    },
    {
        label = "Where do I configure detached power or alternative mana?",
        answer = "Open Class Resources for global class-resource bars. Per-unit detached power options are in the unit page > Power Bar.",
        pageKey = "classpower",
        target = "Opens: Class Resources > Detached Power Bar",
        anchorText = "Detached Power Bar Alternative Mana Power Bar class resources sync width anchor",
        keywords = { "detached power", "detached power bar", "alternative mana", "alt mana", "dual resource", "power bar detached", "anchor to class resource", "sync width to class resource" },
        priority = 45,
    },
    {
        label = "Why are my buffs or debuffs missing?",
        answer = "Open Auras > Filters. Check the active scope, Only Mine, boss/raid filters, dispellable filters, and blacklist entries.",
        pageKey = "auras3_filters",
        target = "Opens: Auras > Filters",
        anchorText = "Aura Filters Blacklist Only my buffs Only my debuffs Show Debuffs Include boss buffs dispellable",
        keywords = SearchKeywordList(SEARCH_UNIT_AURA_DISPEL_KEYWORDS, SEARCH_DISPEL_DEBUFF_KEYWORDS, SEARCH_BLIZZARD_DISPEL_KEYWORDS, {
            [0] = false,
            "buffs missing", "debuffs missing", "auras missing", "buff not showing", "debuff not showing", "hide buffs", "show debuffs", "only my buffs", "only my debuffs", "boss aura missing", "dispellable debuff missing", "aura filter",
        }),
        priority = 180,
    },
    {
        label = "Why do I have too many buffs or debuffs?",
        answer = "Open Auras > Style to adjust icon size, rows and spacing. Use Auras > Filters for filtering.",
        pageKey = "auras3_styling",
        target = "Opens: Auras > Style",
        anchorText = "Auras Max Buffs Max Debuffs Icon size rows spacing filters style",
        keywords = { "too many buffs", "too many debuffs", "too many auras", "aura spam", "buff spam", "debuff spam", "max buffs", "max debuffs", "aura cap", "icon size", "aura rows" },
        priority = 55,
    },
    {
        label = "How do I turn off player buffs only?",
        answer = "Open Auras, select Player, then turn off Buffs for that scope. Use Auras > Style for text and cooldown styling.",
        pageKey = "auras3",
        target = "Opens: Auras",
        anchorText = "Player Auras Buffs Debuffs hide player buffs only",
        keywords = {
            "how do i turn off player buffs only its greyed out when editing player auras",
            "how do i turn off player buffs only",
            "player buffs greyed out",
            "player buffs grayed out",
            "show buffs greyed out player auras",
            "show buffs grayed out player auras",
            "turn off buffs only player",
            "disable player buffs only",
            "hide player buffs only",
            "remove player buffs only",
            "player aura buffs disabled",
            "player auras show buffs locked",
            "custom caps max buffs 0 player",
            "max buffs 0 player",
            "buffs nur beim spieler ausblenden",
            "spieler buffs ausblenden",
            "spieler buffs deaktivieren",
            "spieler buffs ausgegraut",
            "spieler auren buffs ausgegraut",
            "show buffs spieler ausgegraut",
            "max buffs 0 spieler",
            "desactivar buffs jugador",
            "ocultar buffs jugador",
            "buffs jugador gris",
            "auras jugador buffs gris",
            "desactiver buffs joueur",
            "masquer buffs joueur",
            "buffs joueur grise",
            "auras joueur buffs grise",
            "disattivare buff giocatore",
            "nascondere buff giocatore",
            "buff giocatore grigio",
            "desativar buffs jogador",
            "ocultar buffs jogador",
            "buffs jogador cinza",
            "как отключить баффы игрока",
            "баффы игрока серые",
            "ауры игрока баффы серые",
            "플레이어 버프 끄기",
            "플레이어 버프 비활성화",
            "플레이어 오라 버프 회색",
            "关闭玩家增益",
            "玩家增益灰色",
            "玩家光环增益灰色",
            "關閉玩家增益",
            "玩家增益灰色",
            "玩家光環增益灰色",
        },
        priority = 720,
    },
    {
        label = "Where do I change aura cooldown text?",
        answer = "Open Auras > Style for timer colors, stack text, cooldown text size, and group-frame aura text styling.",
        pageKey = "auras3_styling",
        target = "Opens: Auras > Style",
        anchorText = "Style Cooldown Timer Text cooldown text size safe warning urgent stack count",
        keywords = { "aura cooldown text", "aura cooldown text too small", "aura timer too small", "buff timer", "debuff timer", "cooldown text size", "stack text size", "timer color", "aura timer color", "cooldown swipe", "pandemic color" },
        priority = 150,
    },
    {
        label = "Where do I change group health text or power bars?",
        answer = "Open Group Frames > Health & Text. It controls health colors, bars, power bar, text, dispel overlay, debuff stripe, and range fade. Heal prediction is in Global Style > Bars > Absorb Display.",
        pageKey = "gf_bars",
        target = "Opens: Group Frames > Health & Text",
        anchorText = "Health Colors Bars Power Bar Text Dispel Overlay Debuff Stripe Range Fade group range check raid range check party range check",
        keywords = SearchKeywordList(SEARCH_DISPEL_OVERLAY_KEYWORDS, SEARCH_DEBUFF_STRIPE_KEYWORDS, {
            [0] = false,
            "group health text", "raid health text", "party health text", "group power bar", "raid power bar", "party power bar", "heal prediction", "incoming heals", "dispel overlay", "debuff stripe", "group range fade", "group range check", "raid range check", "party range check", "raid out of range", "party out of range", "range check raid frames",
        }),
        priority = 180,
    },
    {
        label = "Where is party or raid range check?",
        answer = "Open Group Frames > Health & Text > Range Fade. Affects chooses frame or HP fading, and the alpha sliders control out-of-range and offline opacity.",
        pageKey = "gf_bars",
        target = "Opens: Group Frames > Health & Text > Range Fade",
        anchorText = "Range Fade group frame range check raid range check party range check out of range alpha offline opacity affects frame HP",
        keywords = { "group range check", "group frame range check", "group frames range check", "raid range check", "raid frame range check", "raid frames range check", "party range check", "party frame range check", "party frames range check", "raid out of range", "party out of range", "group out of range", "range check raid frames", "range check party frames" },
        priority = 140,
    },
    {
        label = "Where are absorb bars or heal prediction?",
        answer = "Absorb styling and heal prediction are in Global Style > Bars > Absorb Display. Use the Party or Raid scope there for group incoming heals.",
        pageKey = "opt_bars",
        target = "Opens: Global Style > Bars > Absorb Display",
        anchorText = "Absorb Display Heal Prediction incoming heals absorb health group frames",
        keywords = { "absorb", "absorbs", "absorb bar", "absorb texture", "heal prediction", "incoming heals", "healing prediction", "shields", "shield bar", "health absorb" },
        priority = 45,
    },
    {
        label = "Where do I change aggro, threat, dispel, or raid markers?",
        answer = "Use Global Style > Bars for highlight borders and Group Frames > Indicators for role, threat, dispel, spell, corner, and raid-marker indicators.",
        pageKey = "gf_indicators",
        target = "Opens: Group Frames > Indicators",
        anchorText = "Indicators Status Icons Spell Indicators Corner Indicators aggro threat dispel role icon raid marker",
        keywords = SearchKeywordList(SEARCH_HIGHLIGHT_BORDER_KEYWORDS, SEARCH_DISPEL_DEBUFF_KEYWORDS, {
            [0] = false,
            "aggro", "threat", "aggro border", "threat border", "dispel indicator", "magic indicator", "curse indicator", "poison indicator", "disease indicator", "raid marker", "role icon", "ready check", "leader icon",
        }),
        priority = 220,
    },
    {
        label = "Why is text overlapping or in the wrong place?",
        answer = "Open the unit page > Text. Adjust anchors, offsets, font size, spacing, split spacing, and layer/draw order.",
        pageKey = "uf_player",
        target = "Opens: Player > Text",
        anchorText = "Text anchor offset font size layer draw order spacing split spacing overlaps bars portraits status icons",
        keywords = { "text overlap", "text overlapping", "text wrong place", "text on bar", "text on portrait", "name overlap", "hp text overlap", "power text overlap", "draw order", "text layer", "split spacing", "move text" },
        priority = 55,
    },
    {
        label = "Why is MSUF lagging or costing FPS?",
        answer = "Open Global Style > Miscellaneous > Update intervals. Also reduce aura counts/timers if aura-heavy layouts are expensive.",
        pageKey = "opt_misc",
        target = "Opens: Global Style > Miscellaneous > Update intervals",
        anchorText = "Update intervals performance lag fps auras cooldown timers filters",
        keywords = { "lag", "fps", "performance", "stutter", "slow", "too much cpu", "heavy", "optimize", "update intervals", "aura performance", "cooldown text performance", "combat performance" },
        priority = 55,
    },
        }
    end)
end
