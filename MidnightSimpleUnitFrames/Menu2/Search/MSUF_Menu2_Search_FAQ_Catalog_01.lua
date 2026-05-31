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
        label = "Discord",
        pageKey = "home",
        target = "MSUF2_SEARCH_TARGET_DASHBOARD_RECOVERY_DISCORD",
        anchorText = "Display & recovery Discord Copy Discord Link support help feedback bug report",
        keywords = SearchKeywordList(SEARCH_DASHBOARD_DISCORD_KEYWORDS, {
            [0] = false,
            "discord", "discord link", "copy discord link", "where is discord", "open discord", "support discord", "feedback discord", "report bugs discord",
        }),
        route = DASHBOARD_ROUTE_RECOVERY,
        priority = 760,
    },
    {
        label = "Display & recovery",
        pageKey = "home",
        target = "MSUF2_SEARCH_TARGET_DASHBOARD_RECOVERY",
        anchorText = "Display & recovery Print Help Discord Factory Reset All recovery tools reset support",
        keywords = SearchKeywordList(SEARCH_DASHBOARD_RECOVERY_KEYWORDS, {
            [0] = false,
            "display recovery", "recovery tools", "print help", "factory reset", "fullreset", "reset all", "recover menu", "dashboard recovery",
        }),
        route = DASHBOARD_ROUTE_RECOVERY,
        priority = 760,
    },
    {
        label = "Wago profile hub",
        pageKey = "home",
        target = "MSUF2_SEARCH_TARGET_DASHBOARD_WAGO",
        anchorText = "Wago profile hub Browse Wago profiles Backup current profile",
        keywords = SearchKeywordList(SEARCH_DASHBOARD_WAGO_KEYWORDS, {
            [0] = false,
            "wago profiles", "browse wago profiles", "wago profile hub", "wago link", "wago backup",
        }),
        priority = 320,
    },
    {
        label = "Support MSUF Development",
        pageKey = "home",
        target = "MSUF2_SEARCH_TARGET_DASHBOARD_SUPPORT",
        anchorText = "Support MSUF Development Patreon PayPal Ko-fi GitHub support links donate repository",
        keywords = SearchKeywordList(SEARCH_DASHBOARD_SUPPORT_KEYWORDS, {
            [0] = false,
            "support links", "donate", "donation", "support development", "support msuf", "patreon", "paypal", "ko-fi", "kofi", "github", "repository",
        }),
        priority = 660,
    },
    {
        label = "Scaling",
        pageKey = "home",
        target = "MSUF2_SEARCH_TARGET_DASHBOARD_SCALING",
        anchorText = "Scaling UI Scale MSUF Frame Scale MSUF Menu Scale Apply Revert resize window bigger smaller",
        keywords = SearchKeywordList(SEARCH_DASHBOARD_SCALING_KEYWORDS, {
            [0] = false,
            "scaling", "ui scale", "menu scale", "msuf frame scale", "msuf menu scale", "make menu bigger", "make menu smaller", "resize window", "options too big", "options too small",
        }),
        route = DASHBOARD_ROUTE_SCALING,
        priority = 760,
    },
    {
        label = "Changelog",
        pageKey = "home",
        target = "MSUF2_SEARCH_TARGET_DASHBOARD_CHANGELOG",
        anchorText = "Changelog release notes patch notes version changes beta notes",
        keywords = SearchKeywordList(SEARCH_DASHBOARD_CHANGELOG_KEYWORDS, {
            [0] = false,
            "changelog", "change log", "release notes", "patch notes", "version notes", "what changed", "latest changes", "beta notes",
        }),
        route = DASHBOARD_ROUTE_CHANGELOG,
        priority = 760,
    },
    {
        label = "Highlight Borders",
        answer = "Open Global Style > Bars. Textures & Gradient controls shared bar textures; Frame Outline and Highlight Borders control borders.",
        pageKey = "opt_bars",
        anchorText = "Highlight Borders Border Modes Dispel border Dispel border detects Highlight Priority Aggro border Purge border Boss target border",
        keywords = SearchKeywordList(SEARCH_HIGHLIGHT_BORDER_KEYWORDS, SEARCH_DISPEL_DEBUFF_KEYWORDS, {
            [0] = false,
            "where are highlight borders", "where is dispel border", "where is dispel overlay", "change dispel highlight", "change aggro highlight",
            "highlight border settings", "priority dispel aggro target focus",
        }),
        priority = 780,
    },
    {
        label = "Dispel Overlay",
        answer = "Tints the health bar when a configured debuff condition is active.",
        pageKey = "gf_bars",
        anchorText = "Dispel Overlay Overlay detects Overlay style Show on current health only Overlay opacity health bar tint dispellable debuff any debuff",
        keywords = SearchKeywordList(SEARCH_DISPEL_OVERLAY_KEYWORDS, SEARCH_DISPEL_DEBUFF_KEYWORDS, {
            [0] = false,
            "where is dispel overlay", "health bar changes color for dispel", "raid frame tint dispel", "party frame tint dispel", "party overlay any debuff",
        }),
        priority = 740,
    },
    {
        label = "Debuff Stripe",
        answer = "Shows a thin colored stripe for debuffs matched by the debuff filter.",
        pageKey = "gf_bars",
        anchorText = "Debuff Stripe Stripe edge Stripe height Stripe opacity debuff filter colored stripe",
        keywords = SearchKeywordList(SEARCH_DEBUFF_STRIPE_KEYWORDS, SEARCH_DISPEL_DEBUFF_KEYWORDS, {
            [0] = false,
            "where is debuff stripe", "thin debuff indicator", "colored line for debuffs", "raid debuff line",
        }),
        priority = 730,
    },
    {
        label = "Why are boss frames not visible?",
        answer = "Boss frames normally appear only during boss encounters. Enable Boss Frames and use Edit Mode or Boss Preview to test them outside combat.",
        pageKey = "uf_boss",
        target = "Opens: Boss > Frame Basics / Boss Layout",
        anchorText = "Enable boss castbars Boss Layout Boss Preview Frame Basics",
        keywords = { "boss frames not visible", "boss frames hidden", "why boss not show", "warum sehe ich boss frames nicht", "bossframes weg", "boss preview", "boss frames anzeigen", "boss frames sichtbar", "boss frames show" },
        priority = 20,
    },
    {
        label = "How do I move frames?",
        answer = "Open MSUF Edit Mode, select the frame, then drag it. Use the unit page > Anchoring only for exact anchor/X/Y fine-tuning.",
        pageKey = "home",
        target = "Opens: Dashboard > MSUF Edit Mode",
        anchorText = "MSUF Edit Mode move frames drag position x offset y offset",
        keywords = { "where do i move my unitframe", "how to move unitframe", "how to move a unitframe", "how do i move unitframe", "move unitframe", "move unit frame", "move frames", "drag frames", "position", "verschieben", "frames bewegen", "edit mode", "x offset", "y offset", "unitframe position", "move player unitframe", "move target unitframe", "move focus unitframe", "move pet unitframe", "move boss unitframe", "how do i move the player frame", "move player frame", "move target frame", "move focus frame", "move pet frame", "move boss frame", "drag player frame", "drag target frame", "player frame position" },
        priority = 320,
    },
    {
        label = "How do I move the player frame?",
        answer = "Use MSUF Edit Mode to drag the player frame. For exact anchor or X/Y values, open Player > Anchoring after that.",
        pageKey = "home",
        target = "Opens: Dashboard > MSUF Edit Mode",
        anchorText = "MSUF Edit Mode move player frame drag player frame position x offset y offset",
        keywords = { "how do i move the player frame", "how to move player frame", "how to move player unitframe", "where do i move my player frame", "move my player frame", "move player frame", "move player unitframe", "drag player frame", "player frame position", "playerframe position", "player x y", "player anchor", "player anchoring", "spieler frame verschieben", "spieler verschieben" },
        priority = 360,
    },
    {
        label = "How do I move or anchor one unit frame?",
        answer = "Use MSUF Edit Mode to drag a single unit frame. Use the unit page > Anchoring when you need exact anchor targets or X/Y values.",
        pageKey = "home",
        target = "Opens: Dashboard > MSUF Edit Mode",
        anchorText = "MSUF Edit Mode Anchoring Anchor unit to Custom anchor target Global anchor move position",
        keywords = { "unit frame anchor", "unitframe anchor", "anchor player frame", "custom anchor", "global anchor", "anchor target frame", "anchor focus frame", "unitframe position", "unit frame position", "player frame position", "move player frame", "move target frame", "move focus frame", "move unitframe", "player x y", "target x y" },
        priority = 160,
    },
    {
        label = "How do I move party or raid frames?",
        answer = "Open Group Frames > Layout. Use Layout, Frame Scaling, and Anchoring for party/raid position, growth, spacing, size, and anchor behavior.",
        pageKey = "gf_layout",
        target = "Opens: Group Frames > Layout > Anchoring",
        anchorText = "Anchoring Layout Frame Scaling growth direction spacing columns position move party raid",
        keywords = { "move raid frames", "move party frames", "move group frames", "raidframes position", "partyframes position", "groupframes position", "group frame anchor", "raid frame anchor", "party frame anchor", "gruppe verschieben", "raid verschieben" },
        priority = 55,
    },
    {
        label = "How do I turn off party or raid frames?",
        answer = "Open Group Frames > Layout, choose Party, Raid, or Mythic at the top, then turn off Use MSUF group frames. Use If this switch is off to choose whether Blizzard frames show normally or both frame systems stay hidden.",
        pageKey = "gf_layout",
        target = "Opens: Group Frames > Layout > General",
        anchorText = "General Use MSUF group frames If this switch is off enable disable turn off hide raid party mythic",
        keywords = {
            "turn off raid frames", "disable raid frames", "hide raid frames", "raid frames off", "raidframes off",
            "turn off party frames", "disable party frames", "hide party frames", "party frames off", "partyframes off",
            "turn off group frames", "disable group frames", "hide group frames", "group frames off", "groupframes off",
            "how to turn off msuf raid frames", "how do i turn off msuf raid frames", "use msuf group frames off",
            "raid frames ausschalten", "raidframes ausschalten", "gruppenframes ausschalten", "gruppenrahmen ausschalten",
            "raid frames deaktivieren", "raidframes deaktivieren", "gruppenframes deaktivieren", "raid frames ausblenden",
        },
        priority = 365,
    },
    {
        label = "How do I resize a unit frame?",
        answer = "Open that unit page and use Frame Basics for width, height, and scale. Text size is in Global Style > Fonts or the unit Text section.",
        pageKey = "uf_player",
        target = "Opens: Player > Frame Basics",
        anchorText = "Frame Basics width height scale size player target focus boss pet",
        keywords = { "resize unitframe", "resize unit frame", "make frame bigger", "make player frame bigger", "make target frame smaller", "width height scale", "unitframe size", "frame size", "frames too big", "frames too small" },
        priority = 40,
    },
    {
        label = "How do I resize party or raid frames?",
        answer = "Open Group Frames > Layout. General/Layout controls frame width, height, spacing, columns, and growth; Frame Scaling controls scale behavior.",
        pageKey = "gf_layout",
        target = "Opens: Group Frames > Layout",
        anchorText = "General Layout Frame Scaling width height spacing columns growth scale",
        keywords = { "resize raid frames", "resize party frames", "resize group frames", "raid frame size", "party frame size", "group frame size", "raid frames too big", "party frames too small", "group scale" },
        priority = 45,
    },
    {
        label = "How do I change portraits?",
        answer = "Open the unit page, then use the Portrait section for mode, render type, shape, size, offset, and border.",
        pageKey = "uf_player",
        target = "Opens: Player > Portrait",
        anchorText = "Portrait mode render type shape size offset class icon portrait background",
        keywords = { "portrait", "portraits", "avatar", "face", "bild", "portraet", "portrait mode", "portrait shape", "class icon", "2d portrait", "3d portrait", "portrait background" },
        priority = 15,
    },
    {
        label = "How do I change castbars?",
        answer = "Use the unit page for per-unit castbar toggles and Global Style > Castbar for shared textures, direction, text, and interrupt options.",
        pageKey = "opt_castbar",
        target = "Opens: Global Style > Castbar",
        anchorText = "Castbar Textures & Outline Focus Kick Interrupt Ready Indicator",
        keywords = { "castbar", "cast bar", "interrupt", "focus kick", "channel ticks", "zauberleiste", "castbar texture", "castbar direction", "spell name" },
        priority = 20,
    },
    {
        label = "Where are Evoker empowered cast settings?",
        answer = "Open Global Style > Castbar and use Empowered Casts for Evoker stage color, stage blink, and blink timing.",
        pageKey = "opt_castbar",
        target = "Opens: Global Style > Castbar > Empowered Casts",
        anchorText = "Empowered Casts Evoker stage blink empower hold release",
        keywords = { "evoker castbar", "evoker cast bar", "empowered casts", "empower", "empower stage", "stage blink", "hold cast", "release cast", "augmentation", "devastation", "preservation", "quell" },
        priority = 180,
    },
    {
        label = "Where are Demon Hunter interrupt and castbar settings?",
        answer = "Open Global Style > Castbar for Focus Kick and Interrupt Ready Indicator. Per-unit castbar interrupt toggles are on each unit page.",
        pageKey = "opt_castbar",
        target = "Opens: Global Style > Castbar > Interrupt Ready Indicator",
        anchorText = "Interrupt Ready Indicator Focus Kick Demon Hunter devour consume magic disrupt kick",
        keywords = { "devour demonhunter castbar", "devour demon hunter castbar", "dh castbar", "demon hunter interrupt", "demonhunter interrupt", "havoc kick", "vengeance kick", "consume magic", "disrupt", "interrupt ready", "focus kick", "kick cooldown" },
        priority = 180,
    },
    {
        label = "How do I make missing health white in Dark Mode?",
        answer = "Set Bar Background Tint to white and enable Custom color in Dark Mode. If black, enable Preserve HP color on all unit frames.",
        pageKey = "opt_colors",
        target = "Opens: Global Style > Colors > Bar Background Tint > Preserve HP color on all unit frames",
        anchorText = "Bar Background Tint Custom color in Dark Mode Preserve HP color missing health white background",
        keywords = {
            "is there a way to change the background color of unit frames",
            "change background color unit frames",
            "unit frame background color",
            "missing health white",
            "missing hp white",
            "dark mode white background",
            "custom color in dark mode",
            "bar background tint white",
            "singular global color",
            "background color dark mode",
            "preserve hp color",
            "hp track black",
            "target frame background black",
            "empty health area black",
            "backgroud color",
            "backgrond color",
            "backround color",
            "bg color white",
            "hintergrund weiss",
        },
        priority = 340,
    },
    {
        label = "How do I change my background?",
        answer = "For bar backgrounds: Bar Background Tint. White in Dark Mode needs Custom color in Dark Mode; black track? check Preserve HP color.",
        pageKey = "opt_colors",
        target = "Opens: Global Style > Colors > Bar Background Tint",
        anchorText = "Bar Background Tint Custom color in Dark Mode background backgrond backround bg backdrop opacity alpha",
        keywords = { "how do i change my backgrond", "how do i change my background", "change background", "change backgrond", "backround", "backgroud", "background color", "bar background", "background tint", "bg color", "backdrop", "opacity", "alpha", "transparent background", "hintergrund", "custom color in dark mode", "missing health white", "dark mode background", "preserve hp color", "hp track black" },
        priority = 70,
    },
        }
    end)
end
