local addonName, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

local Data = M.SearchData or {}
M.SearchData = Data

-- Search FAQ catalog shard 01.
-- Declarative help rows only; routing and scoring live in the search index layer.
if type(Data.RegisterFAQProvider) == "function" then
    Data.RegisterFAQProvider(function(env)
        local SearchKeywordList, DASHBOARD_ROUTE_RECOVERY, DASHBOARD_ROUTE_SCALING, DASHBOARD_ROUTE_CHANGELOG, SEARCH_DISPEL_DEBUFF_KEYWORDS, SEARCH_HIGHLIGHT_BORDER_KEYWORDS, SEARCH_DISPEL_OVERLAY_KEYWORDS, SEARCH_DEBUFF_STRIPE_KEYWORDS, SEARCH_DASHBOARD_RECOVERY_KEYWORDS, SEARCH_DASHBOARD_DISCORD_KEYWORDS, SEARCH_DASHBOARD_SUPPORT_KEYWORDS, SEARCH_DASHBOARD_WAGO_KEYWORDS, SEARCH_DASHBOARD_SCALING_KEYWORDS, SEARCH_DASHBOARD_CHANGELOG_KEYWORDS =
            Data.FAQEnv(env, [[
                SearchKeywordList DASHBOARD_ROUTE_RECOVERY DASHBOARD_ROUTE_SCALING DASHBOARD_ROUTE_CHANGELOG
                SEARCH_DISPEL_DEBUFF_KEYWORDS SEARCH_HIGHLIGHT_BORDER_KEYWORDS SEARCH_DISPEL_OVERLAY_KEYWORDS
                SEARCH_DEBUFF_STRIPE_KEYWORDS SEARCH_DASHBOARD_RECOVERY_KEYWORDS SEARCH_DASHBOARD_DISCORD_KEYWORDS
                SEARCH_DASHBOARD_SUPPORT_KEYWORDS SEARCH_DASHBOARD_WAGO_KEYWORDS SEARCH_DASHBOARD_SCALING_KEYWORDS
                SEARCH_DASHBOARD_CHANGELOG_KEYWORDS
            ]])

        return Data.FAQRows({
            -- Discord lives in the support link row only; the Display & recovery card
            -- carried a duplicate button and no longer does, so this must not route there.
            { l = "Discord", p = "home", t = "MSUF2_SEARCH_TARGET_DASHBOARD_SUPPORT", x = "How to support MSUF Discord Copy Discord Link support help feedback bug report", k = SearchKeywordList(SEARCH_DASHBOARD_DISCORD_KEYWORDS, "discord|discord link|copy discord link|where is discord|open discord|support discord|feedback discord|report bugs discord"), y = 760 },
            { "Display & recovery", false, "home", "MSUF2_SEARCH_TARGET_DASHBOARD_RECOVERY", "Display & recovery Reset Positions Print Help Factory Reset All recovery tools reset", SearchKeywordList(SEARCH_DASHBOARD_RECOVERY_KEYWORDS, "display recovery|recovery tools|print help|factory reset|fullreset|reset all|recover menu|dashboard recovery"), 760, DASHBOARD_ROUTE_RECOVERY, },
            { "Wago profile hub", false, "home", "MSUF2_SEARCH_TARGET_DASHBOARD_WAGO", "Wago profile hub Browse and share Wago profiles", SearchKeywordList(SEARCH_DASHBOARD_WAGO_KEYWORDS, "wago profiles|browse wago profiles|share wago profiles|wago profile hub|wago link"), 320, },
            { "Support MSUF Development", false, "home", "MSUF2_SEARCH_TARGET_DASHBOARD_SUPPORT", "Support MSUF Development Patreon PayPal Ko-fi GitHub support links donate repository", SearchKeywordList(SEARCH_DASHBOARD_SUPPORT_KEYWORDS, "support links|donate|donation|support development|support msuf|patreon|paypal|ko-fi|kofi|github|repository"), 660, },
            { "Scaling", false, "home", "MSUF2_SEARCH_TARGET_DASHBOARD_SCALING", "Scaling UI Scale MSUF Frame Scale MSUF Menu Scale Apply Revert resize window bigger smaller", SearchKeywordList(SEARCH_DASHBOARD_SCALING_KEYWORDS, "scaling|ui scale|menu scale|msuf frame scale|msuf menu scale|make menu bigger|make menu smaller|resize window|options too big|options too small"), 760, DASHBOARD_ROUTE_SCALING, },
            { "Changelog", false, "home", "MSUF2_SEARCH_TARGET_DASHBOARD_CHANGELOG", "Changelog release notes patch notes version changes beta notes", SearchKeywordList(SEARCH_DASHBOARD_CHANGELOG_KEYWORDS, "changelog|change log|release notes|patch notes|version notes|what changed|latest changes|beta notes"), 760, DASHBOARD_ROUTE_CHANGELOG, },
            { "Highlight Borders", "Open Global Style > Bars. Textures & Gradient controls shared bar textures; Frame Outline and Highlight Borders control borders.", "opt_bars", false, "Highlight Borders Border Modes Dispel border Dispel border detects Highlight Priority Aggro border Purge border Boss target border", SearchKeywordList(SEARCH_HIGHLIGHT_BORDER_KEYWORDS, SEARCH_DISPEL_DEBUFF_KEYWORDS, "where are highlight borders|where is dispel border|where is dispel overlay|change dispel highlight|change aggro highlight|highlight border settings|priority dispel aggro target focus"), 780, },
            { "Dispel Overlay", "Tints the health bar when a configured debuff condition is active.", "gf_bars", false, "Dispel Overlay Overlay detects Overlay style Show on current health only Overlay opacity health bar tint dispellable debuff any debuff", SearchKeywordList(SEARCH_DISPEL_OVERLAY_KEYWORDS, SEARCH_DISPEL_DEBUFF_KEYWORDS, "where is dispel overlay|health bar changes color for dispel|raid frame tint dispel|party frame tint dispel|party overlay any debuff"), 740, },
            { "Debuff Stripe", "Shows a thin colored stripe for debuffs matched by the debuff filter.", "gf_bars", false, "Debuff Stripe Stripe edge Stripe height Stripe opacity debuff filter colored stripe", SearchKeywordList(SEARCH_DEBUFF_STRIPE_KEYWORDS, SEARCH_DISPEL_DEBUFF_KEYWORDS, "where is debuff stripe|thin debuff indicator|colored line for debuffs|raid debuff line"), 730, },
        },
        {
            {
                l = "Why are boss frames not visible?",
                a = "Boss frames normally appear only during boss encounters. Enable Boss Frames and use Edit Mode" ..
                    " or Boss Preview to test them outside combat.",
                p = "uf_boss",
                t = "Opens: Boss > Frame Basics / Boss Layout",
                x = "Enable boss castbars Boss Layout Boss Preview Frame Basics",
                k = SearchKeywordList(
                    "boss frames not visible|boss frames hidden|why boss not show|warum sehe ich boss frames nicht",
                    "bossframes weg|boss preview|boss frames anzeigen|boss frames sichtbar|boss frames show"
                ),
                y = 20,
            },
            {
                l = "How do I move frames?",
                a = "Open MSUF Edit Mode, select the frame, then drag it. Use the unit page > Anchoring only for" ..
                    " exact anchor/X/Y fine-tuning.",
                p = "home",
                t = "Opens: Dashboard > MSUF Edit Mode",
                x = "MSUF Edit Mode move frames drag position x offset y offset",
                k = SearchKeywordList(
                    "where do i move my unitframe|how to move unitframe|how to move a unitframe",
                    "how do i move unitframe|move unitframe|move unit frame|move frames|drag frames|position",
                    "verschieben|frames bewegen|edit mode|x offset|y offset|unitframe position|move player unitframe",
                    "move target unitframe|move focus unitframe|move pet unitframe|move boss unitframe",
                    "how do i move the player frame|move player frame|move target frame|move focus frame",
                    "move pet frame|move boss frame|drag player frame|drag target frame|player frame position"
                ),
                y = 320,
            },
            {
                l = "How do I move the player frame?",
                a = "Use MSUF Edit Mode to drag the player frame. For exact anchor or X/Y values, open Player >" ..
                    " Anchoring after that.",
                p = "home",
                t = "Opens: Dashboard > MSUF Edit Mode",
                x = "MSUF Edit Mode move player frame drag player frame position x offset y offset",
                k = SearchKeywordList(
                    "how do i move the player frame|how to move player frame|how to move player unitframe",
                    "where do i move my player frame|move my player frame|move player frame|move player unitframe",
                    "drag player frame|player frame position|playerframe position|player x y|player anchor",
                    "player anchoring|spieler frame verschieben|spieler verschieben"
                ),
                y = 360,
            },
            {
                l = "How do I move or anchor one unit frame?",
                a = "Use MSUF Edit Mode to drag a single unit frame. Use the unit page > Anchoring when you need" ..
                    " exact anchor targets or X/Y values.",
                p = "home",
                t = "Opens: Dashboard > MSUF Edit Mode",
                x = "MSUF Edit Mode Anchoring Anchor unit to Custom anchor target Global anchor move position",
                k = SearchKeywordList(
                    "unit frame anchor|unitframe anchor|anchor player frame|custom anchor|global anchor",
                    "anchor target frame|anchor focus frame|unitframe position|unit frame position",
                    "player frame position|move player frame|move target frame|move focus frame|move unitframe",
                    "player x y|target x y"
                ),
                y = 160,
            },
            {
                l = "How do I move party or raid frames?",
                a = "Open Group Frames > Layout. Use Layout, Frame Scaling, and Anchoring for party/raid position," ..
                    " growth, spacing, size, and anchor behavior.",
                p = "gf_layout",
                t = "Opens: Group Frames > Layout > Anchoring",
                x = "Anchoring Layout Frame Scaling growth direction spacing columns position move party raid",
                k = SearchKeywordList(
                    "move raid frames|move party frames|move group frames|raidframes position|partyframes position",
                    "groupframes position|group frame anchor|raid frame anchor|party frame anchor|gruppe verschieben",
                    "raid verschieben"
                ),
                y = 55,
            },
            {
                l = "How do I turn off party or raid frames?",
                a = "Open Group Frames > Layout, choose Party, Raid, or Mythic at the top, then turn off Use MSUF" ..
                    " group frames. Use If this switch is off to choose whether Blizzard frames show normally or" ..
                    " both frame systems stay hidden.",
                p = "gf_layout",
                t = "Opens: Group Frames > Layout > Frame Basics",
                x = "General Use MSUF group frames If this switch is off enable disable turn off hide raid party" ..
                    " mythic",
                k = SearchKeywordList(
                    "turn off raid frames|disable raid frames|hide raid frames|raid frames off|raidframes off",
                    "turn off party frames|disable party frames|hide party frames|party frames off|partyframes off",
                    "turn off group frames|disable group frames|hide group frames|group frames off|groupframes off",
                    "how to turn off msuf raid frames|how do i turn off msuf raid frames|use msuf group frames off",
                    "raid frames ausschalten|raidframes ausschalten|gruppenframes ausschalten",
                    "gruppenrahmen ausschalten|raid frames deaktivieren|raidframes deaktivieren",
                    "gruppenframes deaktivieren|raid frames ausblenden"
                ),
                y = 365,
            },
            {
                l = "How do I resize a unit frame?",
                a = "Open that unit page and use Frame Basics for width, height, and scale. Text size is in Global" ..
                    " Style > Fonts or the unit Text section.",
                p = "uf_player",
                t = "Opens: Player > Frame Basics",
                x = "Frame Basics width height scale size player target focus boss pet",
                k = SearchKeywordList(
                    "resize unitframe|resize unit frame|make frame bigger|make player frame bigger",
                    "make target frame smaller|width height scale|unitframe size|frame size|frames too big",
                    "frames too small"
                ),
                y = 40,
            },
            {
                l = "How do I resize party or raid frames?",
                a = "Open Group Frames > Layout. Frame Basics/Layout controls frame width, height, spacing, columns," ..
                    " and growth; Frame Scaling controls scale behavior.",
                p = "gf_layout",
                t = "Opens: Group Frames > Layout",
                x = "General Layout Frame Scaling width height spacing columns growth scale",
                k = SearchKeywordList(
                    "resize raid frames|resize party frames|resize group frames|raid frame size|party frame size",
                    "group frame size|raid frames too big|party frames too small|group scale"
                ),
                y = 45,
            },
            {
                l = "How do I change portraits?",
                a = "Open the unit page, then use the Portrait section for mode, render type, shape, size, offset," ..
                    " and border.",
                p = "uf_player",
                t = "Opens: Player > Portrait",
                x = "Portrait mode render type shape size offset class icon portrait background",
                k = SearchKeywordList(
                    "portrait|portraits|avatar|face|bild|portraet|portrait mode|portrait shape|class icon|2d portrait",
                    "3d portrait|portrait background"
                ),
                y = 15,
            },
            {
                l = "How do I change castbars?",
                a = "Use the unit page for per-unit castbar toggles and Global Style > Castbar for shared textures," ..
                    " direction, text, and interrupt options.",
                p = "opt_castbar",
                t = "Opens: Global Style > Castbar",
                x = "Castbar Textures & Outline Focus Kick Interrupt Ready Indicator",
                k = SearchKeywordList(
                    "castbar|cast bar|interrupt|focus kick|channel ticks|zauberleiste|castbar texture",
                    "castbar direction|spell name"
                ),
                y = 20,
            },
            {
                l = "Where are Evoker empowered cast settings?",
                a = "Open Global Style > Castbar and use Empowered Casts for Evoker stage color, stage blink, and" ..
                    " blink timing.",
                p = "opt_castbar",
                t = "Opens: Global Style > Castbar > Empowered Casts",
                x = "Empowered Casts Evoker stage blink empower hold release",
                k = SearchKeywordList(
                    "evoker castbar|evoker cast bar|empowered casts|empower|empower stage|stage blink|hold cast",
                    "release cast|augmentation|devastation|preservation|quell"
                ),
                y = 180,
            },
            {
                l = "Where are Demon Hunter interrupt and castbar settings?",
                a = "Open Global Style > Castbar for Focus Kick and Interrupt Ready Indicator. Per-unit castbar" ..
                    " interrupt toggles are on each unit page.",
                p = "opt_castbar",
                t = "Opens: Global Style > Castbar > Interrupt Ready Indicator",
                x = "Interrupt Ready Indicator Focus Kick Demon Hunter devour consume magic disrupt kick",
                k = SearchKeywordList(
                    "devour demonhunter castbar|devour demon hunter castbar|dh castbar|demon hunter interrupt",
                    "demonhunter interrupt|havoc kick|vengeance kick|consume magic|disrupt|interrupt ready|focus kick",
                    "kick cooldown"
                ),
                y = 180,
            },
            {
                l = "How do I make missing health white in Dark Mode?",
                a = "Set Bar Background Tint to white and enable Custom color in Dark Mode. If black, enable" ..
                    " Preserve HP color on all unit frames.",
                p = "opt_colors",
                t = "Opens: Global Style > Colors > Bar Background Tint > Preserve HP color on all unit frames",
                x = "Bar Background Tint Custom color in Dark Mode Preserve HP color missing health white background",
                k = SearchKeywordList(
                    "is there a way to change the background color of unit frames|change background color unit frames",
                    "unit frame background color|missing health white|missing hp white|dark mode white background",
                    "custom color in dark mode|bar background tint white|singular global color",
                    "background color dark mode|preserve hp color|hp track black|target frame background black",
                    "empty health area black|backgroud color|backgrond color|backround color|bg color white",
                    "hintergrund weiss"
                ),
                y = 340,
            },
            {
                l = "How do I change my background?",
                a = "For bar backgrounds: Bar Background Tint. White in Dark Mode needs Custom color in Dark Mode;" ..
                    " black track? check Preserve HP color.",
                p = "opt_colors",
                t = "Opens: Global Style > Colors > Bar Background Tint",
                x = "Bar Background Tint Custom color in Dark Mode background backgrond backround bg backdrop" ..
                    " opacity alpha",
                k = SearchKeywordList(
                    "how do i change my backgrond|how do i change my background|change background|change backgrond",
                    "backround|backgroud|background color|bar background|background tint|bg color|backdrop|opacity",
                    "alpha|transparent background|hintergrund|custom color in dark mode|missing health white",
                    "dark mode background|preserve hp color|hp track black"
                ),
                y = 70,
            },
        })
    end)
end
