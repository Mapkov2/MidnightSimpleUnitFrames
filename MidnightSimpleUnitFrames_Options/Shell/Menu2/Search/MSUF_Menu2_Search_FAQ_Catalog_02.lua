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
                l = "How do I change health, power, or class colors?",
                a = "Open Style > Colors. Bar Colors and Power Bar Colors control HP/power colors; Class Bar" ..
                    " Colors controls class overrides.",
                p = "opt_colors",
                t = "Opens: Style > Colors > Bar & Prediction Colors",
                x = "Bar Colors Power Bar Colors Class Bar Colors health hp power class color",
                k = SearchKeywordList(
                    "health color|hp color|power color|mana color|class color|bar color|reaction color|npc color",
                    "color by class|farbe|farben"
                ),
                y = 35,
            },
            {
                l = "How do I change fonts and text?",
                a = "Style > Fonts controls shared font settings. Unit pages contain per-unit name, health," ..
                    " and power text position and pattern settings.",
                p = "opt_fonts",
                t = "Opens: Style > Fonts",
                x = "Global Font Text Style Name & Power Colors Name Shortening font size outline shadow",
                k = SearchKeywordList(
                    "font|fonts|text|schrift|name text|hp text|health text|power text|text size|font size|outline",
                    "shadow|name shortening|make text bigger|text too small"
                ),
                y = 25,
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
                l = "How do I import, export, or switch profiles?",
                a = "Open Profiles for active profile, spec auto-switching, 6.x import/export strings," ..
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
                l = "How do I change bar textures, gradients, or outlines?",
                a = "Open Frames > Bars. Textures & Gradient controls shared bar textures; Frame Outline and" ..
                    " Highlight Borders control borders.",
                p = "opt_bars",
                t = "Opens: Frames > Bars > Textures & Gradient",
                x = "Textures & Gradient Frame Outline Highlight Borders texture gradient outline border",
                k = SearchKeywordList(
                    "bar texture|health texture|power texture|change texture|gradient|outline|border|bar border",
                    "frame outline|highlight border|shared texture"
                ),
                y = 560,
            },
        })
    end)
end
