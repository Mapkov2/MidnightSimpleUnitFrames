local addonName, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

local Data = M.SearchData or {}
M.SearchData = Data

-- Search FAQ catalog shard 04.
-- Declarative help rows only; routing and scoring live in the search index layer.
if type(Data.RegisterFAQProvider) == "function" then
    Data.RegisterFAQProvider(function(env)
        local SearchKeywordList, SEARCH_DISPEL_DEBUFF_KEYWORDS, SEARCH_UNIT_AURA_DISPEL_KEYWORDS =
            Data.FAQEnv(env, [[
                SearchKeywordList SEARCH_DISPEL_DEBUFF_KEYWORDS SEARCH_UNIT_AURA_DISPEL_KEYWORDS
            ]])

        return Data.FAQRows({
            { l = "Why can I not change something in combat?", a = "WoW blocks some protected frame changes in combat. Leave combat, then apply layout, anchoring, enable/disable, profile, or protected-frame changes.", p = "opt_misc", t = "Opens: Global Style > Miscellaneous", x = "combat lockdown protected frames settings in combat out of combat", k = "combat lockdown|cannot change in combat|can't change in combat|protected frame|blocked in combat|in combat settings|combat error|leave combat|why can't i move in combat", y = 50 },
        },
        {
            {
                l = "Where did the menu window go?",
                a = "Open MSUF again with /msuf. If frame positions are broken, use Dashboard > Reset Positions or" ..
                    " the profile/reset tools.",
                p = "home",
                t = "Opens: Dashboard > Reset Positions",
                x = "Reset Positions menu window offscreen dashboard slash msuf recovery",
                k = SearchKeywordList(
                    "menu gone|menu missing|window offscreen|menu offscreen|can't open menu|cannot open menu",
                    "lost menu|options window gone|reset menu position|where is menu"
                ),
                y = 45,
            },
            {
                l = "Why did my profile or import look wrong?",
                a = "Open Profiles. Check active profile, spec profiles, import/export, and legacy imports. Large" ..
                    " imports may need a reload.",
                p = "profiles",
                t = "Opens: Profiles > Profile Management / Import & Export",
                x = "Profile Management Specialization Profiles Spec Profiles Backup Transfer Export Import legacy imports active profile reload",
                k = SearchKeywordList(
                    "profile wrong|profile missing|profile gone|import failed|import looks wrong|wago import wrong",
                    "profile not loading|spec profile wrong|active profile|legacy import|copy profile"
                ),
                y = 55,
            },
            {
                l = "Why are party or raid frames not showing?",
                a = "Open Group Frames > Layout. Check enable/show behavior, player/solo visibility, layout mode," ..
                    " frame scaling, and anchoring.",
                p = "gf_layout",
                t = "Opens: Group Frames > Layout > Frame Basics",
                x = "General Layout show hide player solo party raid enable frame scaling anchoring",
                k = SearchKeywordList(
                    "party frames not showing|raid frames not showing|group frames missing|party frames gone",
                    "raid frames gone|hide player solo|show party frames|show raid frames|group frames invisible",
                    "party hidden|raid hidden"
                ),
                y = 60,
            },
            {
                l = "Where do I make names shorter?",
                a = "Open Global Style > Fonts > Name Shortening for unit names. Castbar spell name shortening is in" ..
                    " Global Style > Castbar > Name Shortening.",
                p = "opt_fonts",
                t = "Opens: Global Style > Fonts > Name Shortening",
                x = "Name Shortening names too long max name length castbar spell name shortening",
                k = SearchKeywordList(
                    "name too long|names too long|shorten names|name shortening|long names|cut names|truncate names",
                    "player name too long|target name too long"
                ),
                y = 45,
            },
            {
                l = "Why are group names still shortened when name shortening is off?",
                a = "Global Style > Fonts has Shared settings plus per-scope font overrides. If Party or Raid uses" ..
                    " custom font settings, its Name Shortening can stay enabled even when Shared is off. Select" ..
                    " Party/Raid in Fonts or reset the font override.",
                p = "opt_fonts",
                t = "Opens: Global Style > Fonts > Name Shortening / scope override",
                x = "Name Shortening Use custom settings for this scope Overrides Party Raid group frame name" ..
                    " truncation font override shared changes",
                k = SearchKeywordList(
                    "see image not sure whats happening here|name shortening off but group names still shortened",
                    "shorten names disabled but names still cut|group names still shortened",
                    "party names still shortened|raid names still shortened|group frame name truncation override",
                    "group frame font override name shortening|shared name shortening does not affect party raid",
                    "getting confused with overrides|no group frame override",
                    "namen werden gekuerzt obwohl namenskuerzung aus|namenskuerzung aus aber gruppennamen gekuerzt",
                    "gruppenframe override namenskuerzung|raid override namenskuerzung",
                    "acortar nombres desactivado pero los nombres siguen acortados",
                    "abreviar nombres desactivado pero nombres cortados|marcos de grupo anulacion nombres",
                    "sobrescritura de marcos de grupo nombres",
                    "raccourcissement des noms desactive mais noms encore raccourcis",
                    "noms raccourcis malgre option desactivee|remplacement cadres de groupe noms",
                    "abbreviazione nomi disattivata ma nomi ancora abbreviati|nomi gruppo abbreviati override",
                    "encurtar nomes desativado mas nomes ainda encurtados|quadros de grupo substituicao nomes",
                    "сокращение имен отключено но имена сокращаются|сокращение имён выключено но имена сокращаются",
                    "оверрайд рамок группы сокращение имен|переопределение рамок группы имена|이름 줄이기 꺼짐인데 이름이 줄어듦",
                    "이름 줄이기 꺼짐 이름 줄어듦|그룹 프레임 재정의 이름 줄이기|名字缩短关闭但仍然缩短|姓名缩短关闭但仍然缩短|团队框架覆盖名字缩短|小队框架覆盖名字缩短|名字縮短關閉但仍然縮短",
                    "姓名縮短關閉但仍然縮短|團隊框架覆蓋名字縮短|隊伍框架覆蓋名字縮短"
                ),
                y = 650,
            },
            {
                l = "Where do I make the menu bigger or smaller?",
                a = "Use the Dashboard scale controls for menu scale or UI scale. You can also resize the MSUF2" ..
                    " window from its corner.",
                p = "home",
                t = "Opens: Dashboard > UI Scale / Menu Scale",
                x = "UI Scale Menu Scale resize window bigger smaller dashboard",
                k = SearchKeywordList(
                    "menu too big|menu too small|make menu bigger|make menu smaller|ui scale|menu scale|resize window",
                    "options too big|options too small"
                ),
                y = 45,
            },
            {
                l = "Where are optional modules or style modules?",
                a = "Open Modules > Style for optional style modules such as portrait decoration and dropdown" ..
                    " styling.",
                p = "modules",
                t = "Opens: Modules > Style",
                x = "Modules Style portrait decoration dropdown style optional modules skins",
                k = SearchKeywordList(
                    "modules|optional modules|style modules|portrait decoration|portrait deco|module style|skins"
                ),
                y = 70,
            },
            {
                l = "How do I show party or raid frames while solo?",
                a = "Open Group Frames > Layout and check the solo/player visibility options. That is where MSUF" ..
                    " controls whether party-style frames appear when you are alone.",
                p = "gf_layout",
                t = "Opens: Group Frames > Layout > Frame Basics",
                x = "General show solo show player party raid group frames visibility",
                k = SearchKeywordList(
                    "show party frames while solo|show raid frames while solo|solo raid frames|solo party frames",
                    "always show party frames|always show raid frames|show player solo|show self in party",
                    "party frames when alone|raid frames when alone"
                ),
                y = 90,
            },
            {
                l = "How do I hide myself from party or raid frames?",
                a = "Open Group Frames > Layout. Frame Basics and Sorting control player/self visibility and how" ..
                    " player units are ordered in group frames.",
                p = "gf_layout",
                t = "Opens: Group Frames > Layout > Frame Basics",
                x = "General Show player Player first in role Sorting party raid self visibility",
                k = SearchKeywordList(
                    "hide myself from party|hide player in party|hide self in party frames",
                    "show player in party frames|player in raid frames|self in party frames|show player",
                    "player first in role|party contains me"
                ),
                y = 75,
            },
            {
                l = "How do I show only my HoTs or buffs on party frames?",
                a = "Open Group Frames > Auras > Buffs, then configure the native Player/Only Mine filter and placement there.",
                p = "gf_auras",
                t = "Opens: Group Frames > Auras",
                x = "Buffs own buffs only mine HoTs healer buffs group frames",
                k = SearchKeywordList(
                    "show only my buffs party|only my hots|only my HoTs|track my hots|track my heals|show my rejuv",
                    "show my renew|show my shields|own buffs party|own buffs raid|healer hots|druid hots|priest hots"
                ),
                y = 120,
            },
            {
                l = "How do I make my own buffs or debuffs bigger?",
                a = "Open the affected UnitFrame > Auras for icon size, placement, and filters. Use Appearance >" ..
                    " Auras for scope-aware text and cooldown styling.",
                p = "uf_target",
                t = "Opens: Target > Auras",
                x = "Auras icon size own buffs own debuffs custom buffs custom debuffs group buffs debuffs",
                k = SearchKeywordList(
                    "make my buffs bigger|make own buffs bigger|make my debuffs bigger|bigger own buffs",
                    "bigger own debuffs|my buffs bigger|my debuffs bigger|own aura size|personal debuff size",
                    "personal buff size"
                ),
                y = 95,
            },
            {
                l = "How do I move buff or debuff icons near a unit frame?",
                a = "Open the unit page > Auras or the aura Position Popup for unit-frame aura placement." ..
                    " Buff/debuff icons are configured as aura layout, not moved through MSUF Edit Mode.",
                p = "uf_player",
                t = "Opens: Player > Auras",
                x = "Auras buffs debuffs position anchor rows spacing unit frame auras",
                k = SearchKeywordList(
                    "move buffs|move debuffs|move buff icons|move debuff icons|buff icons next to unit frame",
                    "debuff icons next to unit frame|buffs under portrait|debuffs under portrait|unlock buffs debuffs",
                    "buff debuff anchor|anchor debuffs to buffs|buffs on top|debuffs on top"
                ),
                y = 110,
            },
            {
                l = "How do I add a specific boss debuff to the blacklist?",
                a = "Open Boss Frames > Auras > Debuffs. SpellID blacklist entries, Blizzard filters, placement," ..
                    " and preview live together there; styling remains under Appearance > Auras.",
                p = "uf_boss",
                t = "Opens: Boss Frames > Auras",
                x = "Filters Blacklist buffs debuffs boss debuffs spell id raid debuffs",
                k = SearchKeywordList(
                    "boss debuff missing|boss debuffs not showing|raid debuff missing|add boss debuff|add spell id",
                    "spell id|spellid|debuff stack count|raid mechanic debuff"
                ),
                y = 125,
            },
        },
        {
            { "How do I show only dispellable debuffs?", "Open the affected UnitFrame > Auras > Debuffs and enable the native Dispellable rule. For Party/Raid use Group Frames > Auras > Debuffs.", "uf_target", "Opens: Target > Auras", "Filters Status Indicators dispel magic curse poison disease debuffs debuff type border group frames", SearchKeywordList(SEARCH_DISPEL_DEBUFF_KEYWORDS, SEARCH_UNIT_AURA_DISPEL_KEYWORDS, "only dispellable debuffs|dispellable debuffs|dispel debuffs|magic debuff|curse debuff|poison debuff|disease debuff|debuff type border|debuff color border|show dispels|healer dispels"), 260, },
        },
        {
            {
                l = "How do I move or resize target, focus, or boss castbars?",
                a = "Use MSUF Edit Mode to drag supported castbars. Per-unit castbar enable/icon/text options are on" ..
                    " each unit page; shared castbar style is in Global Style > Castbar.",
                p = "home",
                t = "Opens: Dashboard > MSUF Edit Mode",
                x = "MSUF Edit Mode move castbars target castbar focus castbar boss castbar player castbar resize",
                k = SearchKeywordList(
                    "move target castbar|move focus castbar|move boss castbar|move enemy castbar",
                    "resize target castbar|resize focus castbar|target cast bar position|focus cast bar position",
                    "boss cast bar position|castbar edit mode|drag castbar"
                ),
                y = 115,
            },
            {
                l = "How do I stop castbars covering party or raid frames?",
                a = "MSUF group frames do not use per-player castbars over the health frame. For MSUF castbar" ..
                    " positioning, use MSUF Edit Mode and Global Style > Castbar.",
                p = "opt_castbar",
                t = "Opens: Global Style > Castbar",
                x = "Castbar position edit mode group frames party raid castbars over health",
                k = SearchKeywordList(
                    "party castbar covering health|raid castbar over frame|castbar covers party frame",
                    "castbar covers raid frame|group castbar position|party frame castbar|raid frame castbar",
                    "cast bars on raid frames"
                ),
                y = 70,
            },
            {
                l = "Why can I not unlock or drag buffs and debuffs?",
                a = "MSUF Edit Mode moves frames and supported castbars. Aura icon placement is controlled from each" ..
                    " unit page > Auras or Group Frames > Auras.",
                p = "uf_player",
                t = "Opens: Player > Auras",
                x = "Auras aura position buffs debuffs edit mode drag unlock frames",
                k = SearchKeywordList(
                    "can't unlock buffs|can't unlock debuffs|cannot move buffs|cannot move debuffs|unlock buff frames",
                    "unlock debuff frames|drag buffs debuffs|buffs not movable|debuffs not movable|lock frames buffs",
                    "unlock frames buffs"
                ),
                y = 130,
            },
            {
                l = "How do I make raid frames cleaner for healing?",
                a = "Use Group Frames > Layout for frame size and spacing, Auras for Buff/Debuff placement, and" ..
                    " Status & Indicators for fixed-position status icons.",
                p = "gf_layout",
                t = "Opens: Group Frames > Layout / Auras / Status & Indicators",
                x = "Layout Auras Buffs Debuffs Status Indicators healer clean raid frames HoTs fixed positions",
                k = SearchKeywordList(
                    "clean raid frames|healer raid frames|minimal raid frames|declutter raid frames",
                    "fixed hots positions|fixed aura positions|healer hots indicators|raid frame indicators",
                    "too much information raid frames|healing frames setup"
                ),
                y = 100,
            },
            {
                l = "How do I change dead, offline, AFK, or ready-check indicators?",
                a = "Open Group Frames > Status & Indicators for status icons, role/leader/assist, ready check, focus glow," ..
                    " and other group-frame state indicators.",
                p = "gf_indicators",
                t = "Opens: Group Frames > Status & Indicators > Status Icons",
                x = "Status Icons ready check dead ghost offline afk dnd leader assist role icon",
                k = SearchKeywordList(
                    "dead icon|offline icon|afk icon|dnd icon|ghost icon|ready check icon|leader icon|assist icon",
                    "status icons|group status icon|raid status icon"
                ),
                y = 85,
            },
            {
                l = "How do I hide realm names or shorten player names?",
                a = "Open Global Style > Fonts > Name Shortening. It controls name shortening globally; unit text" ..
                    " placement is on each unit page > Text.",
                p = "opt_fonts",
                t = "Opens: Global Style > Fonts > Name Shortening",
                x = "Name Shortening realm names short names player names font text",
                k = SearchKeywordList(
                    "hide realm names|remove realm names|short names|shorten player names|names too long",
                    "realm name showing|server name showing|name realm|truncate names"
                ),
                y = 90,
            },
            {
                l = "How do I get class-colored health bars or names?",
                a = "Open Global Style > Colors for class bar colors, unitframe colors, and Group Frame Colors.",
                p = "opt_colors",
                t = "Opens: Global Style > Colors > Class Bar Colors",
                x = "Class Bar Colors Unitframe Colors Group Health Colors class colored names health bars",
                k = SearchKeywordList(
                    "class colored health|class colored names|class color names|class color health bars",
                    "green health bars|health bar class color|target class color|player class color|raid class colors"
                ),
                y = 105,
            },
            {
                l = "How do I open the MSUF options?",
                a = "Use /msuf to open MSUF2. The Dashboard also contains reset, support, profile, and scale tools.",
                p = "home",
                t = "Opens: Dashboard",
                x = "Dashboard slash command msuf options menu support profiles reset",
                k = SearchKeywordList(
                    "how to open msuf|open msuf|open options|open addon options|slash command|/msuf|msuf menu",
                    "where is options|addon options|config menu|configuration menu|settings menu"
                ),
                y = 700,
            },
        })
    end)
end
