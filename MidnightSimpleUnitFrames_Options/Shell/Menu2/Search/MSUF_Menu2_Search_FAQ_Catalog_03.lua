local addonName, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

local Data = M.SearchData or {}
M.SearchData = Data

-- Search FAQ catalog shard 03.
-- Declarative help rows only; routing and scoring live in the search index layer.
if type(Data.RegisterFAQProvider) == "function" then
    Data.RegisterFAQProvider(function(env)
        local SearchKeywordList, SEARCH_DISPEL_DEBUFF_KEYWORDS, SEARCH_HIGHLIGHT_BORDER_KEYWORDS, SEARCH_DISPEL_OVERLAY_KEYWORDS, SEARCH_DEBUFF_STRIPE_KEYWORDS, SEARCH_BLIZZARD_DISPEL_KEYWORDS, SEARCH_UNIT_AURA_DISPEL_KEYWORDS =
            Data.FAQEnv(env, [[
                SearchKeywordList SEARCH_DISPEL_DEBUFF_KEYWORDS SEARCH_HIGHLIGHT_BORDER_KEYWORDS
                SEARCH_DISPEL_OVERLAY_KEYWORDS SEARCH_DEBUFF_STRIPE_KEYWORDS SEARCH_BLIZZARD_DISPEL_KEYWORDS
                SEARCH_UNIT_AURA_DISPEL_KEYWORDS
            ]])

        return Data.FAQRows({
            { l = "Where is the unit frame range check?", a = "Open the matching unit page > Range Fade. Group range fade is in Group Frames > Layout.", p = "uf_target", t = "Opens: Target > Range Fade", x = "Range Fade unit frame range check range checker distance check out of range alpha target targettarget focus focustarget pet boss", k = "unit frame range check|unitframe range check|unit frames range check|range check unitframe|range check unit frame|range checker|distance check|distance checker|out of range unit frame|out of range frames|target out of range|focus out of range|boss out of range|target range fade|focus range fade|boss range fade|reichweitencheck|reichweite check|entfernung check", y = 165 },
        },
        {
            {
                l = "How do I change language or translations?",
                a = "Open Global Style > Miscellaneous > Language. Translation coverage can also be checked with the" ..
                    " /msuf locale command.",
                p = "opt_misc",
                t = "Opens: Global Style > Miscellaneous > Language",
                x = "Language locale localization translation deDE ruRU frFR esES",
                k = SearchKeywordList(
                    "language|locale|translation|translations|localization|localisation|sprache|deutsch|english",
                    "russian|french|spanish"
                ),
                y = 25,
            },
            {
                l = "How do I change unitframe or group frame tooltips?",
                a = "Open Global Style > Miscellaneous > Unitframe tooltips to control tooltip source, anchor," ..
                    " visibility mode, and modifier key for MSUF unit and group frames.",
                p = "opt_misc",
                t = "Opens: Global Style > Miscellaneous > Unitframe tooltips",
                x = "Unitframe tooltips group frame tooltips tooltip mouseover modifier hide tooltip show tooltip",
                k = SearchKeywordList(
                    "tooltip|tooltips|unit tooltip|group tooltip|group frame tooltip|mouseover tooltip|hide tooltip",
                    "show tooltip|tooltip on mouseover|modifier tooltip"
                ),
                y = 20,
            },
            {
                l = "How do I change click, mouseover, or targeting behavior?",
                a = "Open Gameplay for crosshair, click-cast, focus/target modifier, mouseover, interaction, and" ..
                    " targeting options.",
                p = "gameplay",
                t = "Opens: Gameplay",
                x = "Gameplay click cast focus target modifier mouseover interaction targeting combat crosshair",
                k = SearchKeywordList(
                    "click cast|clickcast|click casting|clickthrough|click-through|mouseover|target modifier",
                    "focus modifier|mouse buttons|targeting|combat crosshair"
                ),
                y = 30,
            },
            {
                l = "How do I change class resources?",
                a = "Open Class Resources for combo points, holy power, soul shards, chi, maelstrom, essence, runes," ..
                    " stagger, detached power, and alternative mana.",
                p = "classpower",
                t = "Opens: Class Resources",
                x = "Class Resources Layout Behavior Style Auto-Hide Detached Power Bar Alternative Mana",
                k = SearchKeywordList(
                    "class resource|class resources|combo points|holy power|soul shards|chi|maelstrom|essence|runes",
                    "stagger|alternative mana|alt mana|detached power"
                ),
                y = 25,
            },
            {
                l = "How do I hide or show a unit frame?",
                a = "Open that unit page and use Frame Basics > Enable. Boss frames also have Boss Layout options.",
                p = "uf_player",
                t = "Opens: Player > Frame Basics",
                x = "Frame Basics Enable hide show player target focus boss pet",
                k = SearchKeywordList(
                    "hide unitframe|show unitframe|disable unitframe|enable unitframe|hide player frame",
                    "hide target frame|hide focus frame|hide pet frame|show player frame|enable target frame",
                    "disable boss frame"
                ),
                y = 30,
            },
            {
                l = "Where are load conditions?",
                a = "Open the matching unit page and use Load Conditions to control when player, target, focus," ..
                    " boss, or pet frames are shown.",
                p = "uf_player",
                t = "Opens: Player > Load Conditions",
                x = "Load Conditions show hide visibility player target focus boss pet combat group instance",
                k = SearchKeywordList(
                    "load conditions|visibility conditions|show conditions|hide conditions|when to show frame",
                    "when to hide frame|frame visibility|combat visibility|instance visibility|ladebedingungen",
                    "sichtbarkeit"
                ),
                y = 80,
            },
            {
                l = "Why is my player, target, focus, or pet frame gone?",
                a = "Open the matching unit page and check Frame Basics > Enable, Load Conditions," ..
                    " alpha/transparency, and range fade.",
                p = "uf_player",
                t = "Opens: Player > Frame Basics",
                x = "Frame Basics Enable Load Conditions Transparency Range Fade player target focus pet gone" ..
                    " missing invisible",
                k = SearchKeywordList(
                    "player frame gone|target frame gone|focus frame gone|pet frame gone|unitframe missing",
                    "unitframe invisible|frame not visible|frame disappeared|cannot see player frame",
                    "target not showing|focus not showing|pet not showing|unitframe hidden"
                ),
                y = 55,
            },
            {
                l = "Where is Target of Target?",
                a = "Open Target of Target. Use Frame Basics to enable it, Text for labels, and Anchoring/Edit Mode" ..
                    " for placement.",
                p = "uf_targettarget",
                t = "Opens: Target of Target > Frame Basics",
                x = "Frame Basics Target of Target ToT Enable Text Anchoring",
                k = SearchKeywordList(
                    "target of target|tot|targettarget|target target|where is tot|tot missing|show target of target",
                    "enable tot|target of target frame"
                ),
                y = 45,
            },
            {
                l = "Where is Focus Target?",
                a = "Open Focus Target. Use Frame Basics to enable it; it only appears when Focus is enabled and" ..
                    " your focus has a target.",
                p = "uf_focustarget",
                t = "Opens: Focus Target > Frame Basics",
                x = "Frame Basics Focus Target Enable Text Anchoring",
                k = SearchKeywordList(
                    "focus target|focustarget|focus target frame|ft frame|where is focus target|focus target missing",
                    "show focus target|enable focus target"
                ),
                y = 45,
            },
            {
                l = "Why is my castbar not showing?",
                a = "Open the unit page > Castbar to enable that unit's castbar. Shared castbar visuals are in" ..
                    " Global Style > Castbar.",
                p = "uf_player",
                t = "Opens: Player > Castbar",
                x = "Castbar Enable player target focus boss pet show interrupt icon text",
                k = SearchKeywordList(
                    "castbar not showing|castbar missing|player castbar gone|target castbar missing",
                    "focus castbar missing|boss castbar missing|show castbar|enable castbar|my castbar disappeared",
                    "no cast bar"
                ),
                y = 55,
            },
            {
                l = "Where do I change castbar spell names or long cast text?",
                a = "Open Global Style > Castbar > Name Shortening for castbar spell name shortening, max length," ..
                    " and reserved space.",
                p = "opt_castbar",
                t = "Opens: Global Style > Castbar > Name Shortening",
                x = "Name Shortening spell name max name length reserved space castbar",
                k = SearchKeywordList(
                    "cast name too long|spell name too long|castbar text too long|shorten castbar name",
                    "castbar spell name|max name length|reserved space|cast text overlap"
                ),
                y = 45,
            },
            {
                l = "Why are class resources missing?",
                a = "Open Class Resources. Check Enable, Auto-Hide, class-specific behavior, detached power, and" ..
                    " alternative mana settings.",
                p = "classpower",
                t = "Opens: Class Resources > Layout / Auto-Hide",
                x = "Class Resources Enable Auto-Hide Behavior Detached Power Bar Alternative Mana",
                k = SearchKeywordList(
                    "class resources missing|combo points missing|holy power missing|soul shards missing|chi missing",
                    "maelstrom missing|essence missing|runes missing|stagger missing|class power not showing",
                    "resource bar missing"
                ),
                y = 55,
            },
            {
                l = "Where do I configure detached power or alternative mana?",
                a = "Open Class Resources for global class-resource bars. Per-unit detached power options are in the" ..
                    " unit page > Power Bar.",
                p = "classpower",
                t = "Opens: Class Resources > Detached Power Bar",
                x = "Detached Power Bar Alternative Mana Power Bar class resources sync width anchor",
                k = SearchKeywordList(
                    "detached power|detached power bar|alternative mana|alt mana|dual resource|power bar detached",
                    "anchor to class resource|sync width to class resource"
                ),
                y = 45,
            },
        },
        {
            { "Why are my buffs or debuffs missing?", "Open the affected UnitFrame > Auras and choose Buffs or Debuffs. Check its frame-specific Blizzard filters, blacklist, enabled state, and icon cap. For Party/Raid use Group Frames > Auras.", "uf_target", "Opens: Target > Auras", "Aura Filters Blacklist Only my buffs Only my debuffs Show Debuffs Include boss buffs dispellable", SearchKeywordList(SEARCH_UNIT_AURA_DISPEL_KEYWORDS, SEARCH_DISPEL_DEBUFF_KEYWORDS, SEARCH_BLIZZARD_DISPEL_KEYWORDS, "buffs missing|debuffs missing|auras missing|buff not showing|debuff not showing|hide buffs|show debuffs|only my buffs|only my debuffs|boss aura missing|dispellable debuff missing|aura filter"), 180, },
        },
        {
            {
                l = "Why do I have too many buffs or debuffs?",
                a = "Open the affected UnitFrame > Auras, choose Buffs or Debuffs, then adjust filters, icon size," ..
                    " rows, caps, and spacing. Party/Raid settings are in Group Frames > Auras.",
                p = "uf_target",
                t = "Opens: Target > Auras",
                x = "Auras Max Buffs Max Debuffs Icon size rows spacing filters style",
                k = SearchKeywordList(
                    "too many buffs|too many debuffs|too many auras|aura spam|buff spam|debuff spam|max buffs",
                    "max debuffs|aura cap|icon size|aura rows"
                ),
                y = 55,
            },
            {
                l = "How do I turn off player buffs only?",
                a = "Open Player > Auras, then turn off Buffs for the player frame. Scope-aware text and cooldown" ..
                    " styling remains under Appearance > Auras.",
                p = "uf_player",
                t = "Opens: Player > Auras",
                x = "Player Auras Buffs Debuffs hide player buffs only",
                k = SearchKeywordList(
                    "how do i turn off player buffs only its greyed out when editing player auras",
                    "how do i turn off player buffs only|player buffs greyed out|player buffs grayed out",
                    "show buffs greyed out player auras|show buffs grayed out player auras|turn off buffs only player",
                    "disable player buffs only|hide player buffs only|remove player buffs only",
                    "player aura buffs disabled|player auras show buffs locked|custom caps max buffs 0 player",
                    "max buffs 0 player|buffs nur beim spieler ausblenden|spieler buffs ausblenden",
                    "spieler buffs deaktivieren|spieler buffs ausgegraut|spieler auren buffs ausgegraut",
                    "show buffs spieler ausgegraut|max buffs 0 spieler|desactivar buffs jugador|ocultar buffs jugador",
                    "buffs jugador gris|auras jugador buffs gris|desactiver buffs joueur|masquer buffs joueur",
                    "buffs joueur grise|auras joueur buffs grise|disattivare buff giocatore|nascondere buff giocatore",
                    "buff giocatore grigio|desativar buffs jogador|ocultar buffs jogador|buffs jogador cinza",
                    "как отключить баффы игрока|баффы игрока серые|ауры игрока баффы серые|플레이어 버프 끄기|플레이어 버프 비활성화",
                    "플레이어 오라 버프 회색|关闭玩家增益|玩家增益灰色|玩家光环增益灰色|關閉玩家增益|玩家增益灰色|玩家光環增益灰色"
                ),
                y = 720,
            },
            {
                l = "Where do I change aura cooldown text?",
                a = "Open Appearance > Auras for scope-aware cooldown text, stack text, swipe, and duration-bar" ..
                    " styling. Timer colors remain under Colors > Auras.",
                p = "auras3_styling",
                t = "Opens: Appearance > Auras",
                x = "Style Cooldown Timer Text cooldown text size stack count Colors Auras timer colors safe warning urgent pandemic",
                k = SearchKeywordList(
                    "aura cooldown text|aura cooldown text too small|aura timer too small|buff timer|debuff timer",
                    "cooldown text size|stack text size|timer color|aura timer color|cooldown swipe|pandemic color"
                ),
                y = 150,
            },
        },
        {
            { "Where do I change group health text or resource bars?", "Open Group Frames > Layout. Text, Resource Bar, and Range Fade are arranged beside Frame Basics and Transparency. Dispel Overlay and Debuff Stripe are on the Dispel Overlay page. Heal prediction is in Global Style > Bars > Absorb Display.", "gf_layout", "Opens: Group Frames > Layout", "Health Text Resource Bar Text Layout Group Dispel Overlay group range check raid range check party range check", SearchKeywordList(SEARCH_DISPEL_OVERLAY_KEYWORDS, SEARCH_DEBUFF_STRIPE_KEYWORDS, "group health text|raid health text|party health text|group resource bar|group power bar|raid power bar|party power bar|heal prediction|incoming heals|dispel overlay|debuff stripe|group range fade|group range check|raid range check|party range check|raid out of range|party out of range|range check raid frames"), 180, },
        },
        {
            {
                l = "Where is party or raid range check?",
                a = "Open Group Frames > Layout > Range Fade. Affects chooses frame or HP fading, and the" ..
                    " alpha sliders control out-of-range and offline opacity.",
                p = "gf_layout",
                t = "Opens: Group Frames > Layout > Range Fade",
                x = "Range Fade group frame range check raid range check party range check out of range alpha" ..
                    " offline opacity affects frame HP",
                k = SearchKeywordList(
                    "group range check|group frame range check|group frames range check|raid range check",
                    "raid frame range check|raid frames range check|party range check|party frame range check",
                    "party frames range check|raid out of range|party out of range|group out of range",
                    "range check raid frames|range check party frames"
                ),
                y = 140,
            },
            {
                l = "Where are absorb bars or heal prediction?",
                a = "Absorb styling and heal prediction are in Global Style > Bars > Absorb Display. Use the Party" ..
                    " or Raid scope there for group incoming heals.",
                p = "opt_bars",
                t = "Opens: Global Style > Bars > Absorb Display",
                x = "Absorb Display Heal Prediction incoming heals absorb health group frames",
                k = SearchKeywordList(
                    "absorb|absorbs|absorb bar|absorb texture|heal prediction|incoming heals|healing prediction",
                    "shields|shield bar|health absorb"
                ),
                y = 45,
            },
        },
        {
            { "Where do I change aggro, threat, dispel, or raid markers?", "Use Global Style > Bars for highlight borders and Group Frames > Status & Indicators for role, threat, dispel, corner, and raid-marker indicators. Spell Indicators are in Group Frames > Auras.", "gf_indicators", "Opens: Group Frames > Status & Indicators", "Status Indicators Status Icons Corner Indicators aggro threat dispel role icon raid marker", SearchKeywordList(SEARCH_HIGHLIGHT_BORDER_KEYWORDS, SEARCH_DISPEL_DEBUFF_KEYWORDS, "aggro|threat|aggro border|threat border|status and indicators|dispel indicator|magic indicator|curse indicator|poison indicator|disease indicator|raid marker|role icon|ready check|leader icon"), 220, },
        },
        {
            {
                l = "Why is text overlapping or in the wrong place?",
                a = "Open the unit page > Text. Adjust anchors, offsets, font size, spacing, split spacing, and" ..
                    " layer.",
                p = "uf_player",
                t = "Opens: Player > Text",
                x = "Text anchor offset font size layer spacing split spacing overlaps bars portraits" ..
                    " status icons",
                k = SearchKeywordList(
                    "text overlap|text overlapping|text wrong place|text on bar|text on portrait|name overlap",
                    "hp text overlap|power text overlap|layer|text layer|split spacing|move text"
                ),
                y = 55,
            },
            {
                l = "Why is MSUF lagging or costing FPS?",
                a = "Open the affected UnitFrame > Auras or Group Frames > Auras and reduce visible counts," ..
                    " timer text, or unnecessary native filter rules.",
                p = "uf_target",
                t = "Opens: Target > Auras",
                x = "Auras performance lag fps cooldown timers filters aura count style",
                k = SearchKeywordList(
                    "lag|fps|performance|stutter|slow|too much cpu|heavy|optimize|aura performance",
                    "cooldown text performance|combat performance"
                ),
                y = 55,
            },
        })
    end)
end
