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
                    " Frames > Layout > Resource Bar > Smooth fill.",
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
                t = "Opens: Profiles > Import & Export",
                x = "Backup Transfer Export Import Profile Management Specialization Profiles Spec Profiles import export wago string",
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
                a = "Use Group Frames pages: Layout for size, growth, sorting, bars, and text; Auras for" ..
                    " Buff/Debuff placement, and Status & Indicators for status icons.",
                p = "gf_layout",
                t = "Opens: Group Frames > Layout",
                x = "Group Frames Layout Resource Bar Text Auras Buffs Debuffs Status Indicators party raid growth sorting",
                k = SearchKeywordList(
                    "group frames|groupframes|party|raid|mythic raid|gruppe|raid frames|layout|growth|sorting",
                    "raidframes|partyframes"
                ),
                y = 20,
            },
        },
        {
            { "How do I configure buffs and debuffs?", "Open the affected UnitFrame > Auras for visibility, layout, filters, and blacklists. Use Appearance > Auras for scope-aware cooldown, stack, duration-bar, and icon styling.", "uf_target", "Opens: Target > Auras", "Auras Buffs Debuffs Filters Blacklist Style buffs debuffs", SearchKeywordList(SEARCH_UNIT_AURA_DISPEL_KEYWORDS, "buff|buffs|debuff|debuffs|auras|aura|cooldown|filter|only my buffs|only my debuffs|hide buffs|show debuffs|aura size|aura position"), 120, },
            { "Can MSUF hide debuffs with a blacklist?", "Open the affected UnitFrame > Auras > Debuffs and use its frame-specific SpellID blacklist. Group exclusions live directly in Group Frames > Auras > Debuffs.", "uf_target", "Opens: Target > Auras", "Filters Blacklist spell id category blacklist black list ignore list hide debuffs hide buffs hidden proc BL ElvUI Emlui", SearchKeywordList(SEARCH_UNIT_AURA_DISPEL_KEYWORDS, "debuff blacklist|debuff black list|aura blacklist|aura black list|buff blacklist|buff black list|blacklist debuffs|black list debuffs|midnight simple unit frame|midnight simple unit frames|midnight simple unitframe|midnight simple unitframes|MSUF unitframe|MSUF unit frames|hide specific debuff|hide specific debuffs|hide a debuff|icon for debuff|hide debuff proc|hide proc|hidden proc|proc hidden|BL hidden proc|BL debuff|top right BL|top right screenshot|ElvUI debuff blacklist|ElvUI blacklist|Emlui debuff blacklist|can MSUF do same|ignore debuffs|ignore aura|ignore list|global ignore list|debuff ausblenden|debuff verstecken|aura ignorieren|schwaechungszauber ausblenden"), 960, },
            { "How do I configure group buffs or debuffs?", "Open Group Frames > Auras for Buff/Debuff filters, lists, visibility, and layout. For text, cooldowns, stacks, and duration bars use Appearance > Auras and select Party or Raid scope.", "gf_auras", "Opens: Group Frames > Auras", "Buffs Debuffs Style Filters Group Frames Auras", SearchKeywordList(SEARCH_DISPEL_DEBUFF_KEYWORDS, SEARCH_BLIZZARD_DISPEL_KEYWORDS, "raid buffs|raid debuffs|party buffs|party debuffs|group auras|group buffs|group debuffs|group cooldown swipe"), 210, },
            { "How do I add or change status icons and indicators?", "Unit frame status icons are on each unit page. Group Spell Indicators are in Group Frames > Auras; group status and corner indicators are in Group Frames > Status & Indicators.", "gf_indicators", "Opens: Group Frames > Status & Indicators", "Status Indicators Status Icons Corner Indicators role icon dispel aggro raid marker", SearchKeywordList(SEARCH_DISPEL_DEBUFF_KEYWORDS, SEARCH_HIGHLIGHT_BORDER_KEYWORDS, "status icons|status and indicators|indicator|indicators|corner indicator|raid marker|role icon|leader icon|ready check|aggro icon|threat icon|focus glow"), 190, },
            { "How do Priority Frames work?", "Priority Frames duplicate automatic tanks and manually pinned current group members into a stable extra strip without removing them from the normal Party or Raid frames. In a party they inherit Party Frames; in a raid they inherit the active Raid or Mythic Raid frames. They work in parties, raids, and Mythic raids, inherit the active group-frame click-cast behavior, and require the matching base group frames to be enabled.", "gf_priority", "Opens: Group Frames > Priority", "Priority Frames overview purpose pinned players automatic tanks extra party raid frames important players", SearchKeywordList("priority frames|priority group frames|what are priority frames|what are pinned frames|party priority frames|dungeon priority frames|extra party frames|extra raid frames|pinned party members|pinned raid frames|tank frames|important players|priority strip"), 300, },
            { "How do I pin or unpin a player in Priority Frames?", "While grouped, set the hover hotkey on Group Frames > Priority. Hover an MSUF Party, Raid, or Priority frame and press the Priority Frames hotkey to pin or unpin that player. Players cannot be added by typing a name or while outside the current group; a saved absent pin waits and reappears when that player rejoins.", "gf_priority", "Opens: Group Frames > Priority", "Priority Frames pinning hover hotkey keybind add remove unpin player by name offline current group", SearchKeywordList("pin player|unpin player|manual pin|pinned player|priority hotkey|priority keybind|hover hotkey|add priority frame|remove priority frame|pin by name|offline pin|saved pin"), 330, },
            { "Can Priority Frames show my co-tank?", "Yes. Include tanks automatically selects current group members whose WoW-assigned role is TANK, normally including both you and your co-tank. To show only your co-tank, disable automatic tanks and manually pin the other tank. If WoW has not assigned that player the TANK role, manual pinning is the fallback.", "gf_priority", "Opens: Group Frames > Priority", "Priority Frames co-tank other tank second tank automatic tanks manual-only tank", SearchKeywordList("co tank frame|co-tank frame|cotank frame|other tank frame|second tank frame|both tanks|two tanks|only co tank|exclude my tank|manual co tank|include tanks automatically"), 350, },
            { "Can Priority Frames automatically show Augmentation Evokers?", "Priority Frames does not automatically detect other players' specializations. Automatic selection currently supports WoW-assigned tanks only. Pin an Augmentation Evoker manually with the hover hotkey; Priority Frames does not choose ideal Prescience or Ebon Might targets.", "gf_priority", "Opens: Group Frames > Priority", "Priority Frames Augmentation Evoker automatic spec detection manual pin Prescience Ebon Might support", SearchKeywordList("augmentation evoker priority frame|augementation evoker priority frame|aug evoker frame|automatic augmentation|automatic augementation|auto augmentation|auto augementation|detect augmentation|detect augementation|augmentation spec detection|augementation spec detection|support spec frame|prescience target|ebon might target"), 370, },
            { "How should an Augmentation Evoker use Priority Frames?", "Manually pin the teammates you want to keep visible for monitoring or click-casting. Priority Frames does not decide who should receive Prescience or Ebon Might. Configure Group Frames > Auras > Spell Indicators if you want inherited Priority frames to show Prescience, Ebon Might, Shifting Sands, Blistering Scales, or other configured effects.", "gf_priority", "Opens: Group Frames > Priority", "Augmentation Evoker Priority Frames workflow buffs spell indicators click-casting manual targets", SearchKeywordList("augmentation priority workflow|augementation priority workflow|aug priority setup|augmentation pinned frames|augementation pinned frames|prescience monitoring|ebon might monitoring|shifting sands|blistering scales|augmentation spell indicators|augementation spell indicators|aug click casting"), 355, },
            { "Do Priority Frames work in parties and dungeons?", "Yes. Priority Frames work in parties, raids, and Mythic raids. In a party or dungeon they inherit Party Frames; in a raid they inherit the active Raid or Mythic Raid setup. They do not create a solo strip, and the matching base Party or Raid frames must be enabled.", "gf_priority", "Opens: Group Frames > Priority", "Priority Frames Party dungeon Mythic Plus raid Mythic Raid solo base frames", SearchKeywordList("priority frames party|priority frames dungeon|priority frames mythic plus|priority frames m+|priority frames raid|priority frames mythic raid|priority frames solo|use priority frames in party|pinned party frames"), 345, },
            { "Why are my Priority Frames empty or missing?", "Check that Priority Frames are enabled, you are grouped, and the matching base Party or Raid frames are enabled. Confirm that an assigned tank or manually pinned player is currently in the group and Visible slots is not full. Saved absent players create no empty placeholders, and protected roster changes made in combat finish after combat ends.", "gf_priority", "Opens: Group Frames > Priority", "Priority Frames troubleshooting empty missing hidden not showing base frames group slots combat", SearchKeywordList("priority frames empty|priority frames missing|priority frames not showing|cannot see priority frames|pinned frame missing|priority strip empty|priority frames invisible|priority frame gone|saved pin not visible"), 365, },
            { "Do Priority Frame pins persist, and what order do they use?", "For Priority Frames, layout is profile-wide, while pins are character-specific. Visible slots can be set from one to five. Automatic tanks fill first, followed by manual pins in saved order; duplicate selections appear once. A saved player who is absent waits until that player rejoins the current group.", "gf_priority", "Opens: Group Frames > Priority", "Priority Frames persistence profile-wide character-specific order sort slots limits saved pins", SearchKeywordList("priority pin persistence|priority pins saved|priority frames profile|priority pins character|priority frames alt|priority frame order|priority frame sorting|priority visible slots|priority pin limit|how many priority frames|reorder priority pins"), 340, },
            { "Do Priority Frames inherit click casting and appearance?", "Yes. Priority Frames inherit the active Party, Raid, or Mythic Raid frame appearance, including configured bars, text, auras, status indicators, and spell indicators. They use the same MSUF click-casting registration and unit behavior, so existing click-cast bindings also work on the duplicated frames.", "gf_priority", "Opens: Group Frames > Priority", "Priority Frames click casting Clique appearance style auras indicators inherited group frames", SearchKeywordList("priority frames click cast|priority frames click casting|clique priority frames|priority frame appearance|priority frame style|priority frame auras|priority frame indicators|priority frame spell indicators|priority frames inherit"), 335, },
            { "Can Priority Frames update during combat?", "Existing Priority frames remain usable in combat, but WoW protects secure group-frame membership and layout changes. Any pin, roster, slot, or placement change that needs a secure refresh is applied after combat ends. Change the Priority Frames keybinding out of combat.", "gf_priority", "Opens: Group Frames > Priority", "Priority Frames combat protected secure deferred refresh keybinding", SearchKeywordList("priority frames combat|pin during combat|priority frame update combat|priority roster combat|priority placement combat|secure priority frame|priority refresh after combat|priority keybind combat"), 325, },
            { "How do I position Priority Frames?", "Open Group Frames > Priority > Placement. Attach the strip to the right, left, top, or bottom of the active Party/Raid container, or choose Free position and use the dedicated Priority Frames mover in Edit Mode. The same page controls growth, spacing, attachment gap, and alignment offset.", "gf_priority", "Opens: Group Frames > Priority", "Priority Frames placement attach free position mover Edit Mode growth spacing offset", SearchKeywordList("position priority frames|place priority frames|move priority frames|attach priority frames|priority frames left|priority frames right|priority frames above|priority frames below|priority free position|priority mover|priority edit mode"), 320, },
            { "Can Priority Frames automatically select healers, DPS, classes, or specs?", "No. Automatic selection currently uses only WoW's assigned TANK role. Healers, DPS, classes, specializations, and support targets must be pinned manually with the hover hotkey. This avoids background inspection or polling and keeps the selection deterministic.", "gf_priority", "Opens: Group Frames > Priority", "Priority Frames automatic selection healer DPS class spec role support manual pin", SearchKeywordList("automatic healer priority frame|automatic dps priority frame|automatic class priority frame|automatic spec priority frame|auto select healer|auto select dps|auto select class|auto select spec|role priority frames|support priority frames"), 360, },
            { "Where can I request a Priority Frames feature?", "The in-game Assistant can explain or help phrase a Priority Frames feature request, but it cannot submit one. Post it in MSUF Discord: https://discord.gg/2Gf9b2Wprz. Include Party/Raid scope, the selection rule, automatic/manual ordering, one-to-five-slot behavior, and the expected combat behavior.", "gf_priority", "Opens: Group Frames > Priority", "Priority Frames feature request suggestion Discord automatic selector pinned frames", SearchKeywordList("priority frames feature request|request priority feature|suggest priority frames feature|add priority frames support|new priority selector|augmentation feature request|co tank feature request|pinned frames request"), 315, },
            { "Do Priority Frames use polling?", "No continuous polling ticker or OnUpdate loop is used for Priority selection. It resolves the roster when configuration, pins, group state, or relevant unit identity changes require a refresh. Automatic selection reads WoW's assigned TANK role and does not inspect every group member's specialization in the background.", "gf_priority", "Opens: Group Frames > Priority", "Priority Frames performance no polling ticker OnUpdate event-driven CPU overhead spec inspection", SearchKeywordList("priority frames performance|priority frames cpu|priority frames fps|priority frames polling|priority frames ticker|priority frames onupdate|priority frames overhead|automatic tank performance|spec inspection performance"), 305, },
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
                l = "How do I show Blizzard unit frames again?",
                a = "Open the unit page > Frame Basics and use Force Blizzard frame on.",
                p = "uf_player",
                t = "Opens: Player > Frame Basics",
                x = "Blizzard Frames force blizzard frame on default frames playerframe",
                k = SearchKeywordList(
                    "blizzard frames|disable blizzard|hide blizzard|playerframe|default frames|standard frames",
                    "hide default frames|disable default unit frames|blizzard player frame|force blizzard frame"
                ),
                y = 76,
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
