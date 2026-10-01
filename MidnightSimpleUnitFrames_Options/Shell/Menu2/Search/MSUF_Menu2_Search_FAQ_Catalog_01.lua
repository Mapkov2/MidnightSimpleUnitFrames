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
                a = "Open MSUF Edit Mode, select the frame, then drag it. Use the unit page > Anchor only for" ..
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
                l = "How do I resize a unit frame?",
                a = "Open that unit page and use Frame Basics for width, height, and scale. Text size is in" ..
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
                l = "How do I change castbars?",
                a = "Use the unit page for per-unit castbar toggles and Frames > Cast Bars for shared textures," ..
                    " direction, text, and interrupt options.",
                p = "opt_castbar",
                t = "Opens: Frames > Cast Bars",
                x = "Castbar Textures & Outline Focus Kick Interrupt Ready Indicator",
                k = SearchKeywordList(
                    "castbar|cast bar|interrupt|focus kick|channel ticks|zauberleiste|castbar texture",
                    "castbar direction|spell name"
                ),
                y = 20,
            },
            {
                l = "How do I resize party or raid frames?",
                a = "Open Frames > Party/Raid Frames > Layout. Size & Scaling controls frame dimensions and scaling by group size. Group Layout controls growth, columns, and group visibility.",
                p = "gf_layout",
                t = "Opens: Frames > Party/Raid Frames > Layout",
                x = "Size & Scaling Group Layout width height spacing columns growth scale",
                k = SearchKeywordList(
                    "resize raid frames|resize party frames|resize group frames|raid frame size|party frame size",
                    "group frame size|raid frames too big|party frames too small|group scale"
                ),
                y = 45,
            },
        })
    end)
end
