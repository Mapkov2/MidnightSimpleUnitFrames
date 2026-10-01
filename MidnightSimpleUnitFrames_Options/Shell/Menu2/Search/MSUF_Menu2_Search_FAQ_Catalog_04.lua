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
            {
                l = "Why are party or raid frames not showing?",
                a = "Open Frames > Party/Raid Frames > Layout. Check enable/show behavior, player/solo visibility, layout mode," ..
                    " frame scaling, and anchoring.",
                p = "gf_layout",
                t = "Opens: Frames > Party/Raid Frames > Layout > Frame Basics",
                x = "General Layout show hide player solo party raid enable frame scaling anchoring",
                k = SearchKeywordList(
                    "party frames not showing|raid frames not showing|group frames missing|party frames gone",
                    "raid frames gone|hide player solo|show party frames|show raid frames|group frames invisible",
                    "party hidden|raid hidden"
                ),
                y = 60,
            },
            {
                l = "How do I change dead, offline, AFK, or ready-check indicators?",
                a = "Open Frames > Party/Raid Frames > Status & Indicators for status icons, role/leader/assist, ready check, focus glow," ..
                    " and other group-frame state indicators.",
                p = "gf_indicators",
                t = "Opens: Frames > Party/Raid Frames > Status & Indicators > Status Icons",
                x = "Status Icons ready check dead ghost offline afk dnd leader assist role icon",
                k = SearchKeywordList(
                    "dead icon|offline icon|afk icon|dnd icon|ghost icon|ready check icon|leader icon|assist icon",
                    "status icons|group status icon|raid status icon"
                ),
                y = 85,
            },
        })
    end)
end
