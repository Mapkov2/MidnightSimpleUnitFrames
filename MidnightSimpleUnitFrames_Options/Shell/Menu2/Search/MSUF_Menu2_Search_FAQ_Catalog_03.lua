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
            {
                l = "Where are absorb bars or heal prediction?",
                a = "Absorb styling and heal prediction are in Frames > Bars > Absorb Display. Use the Party" ..
                    " or Raid scope there for group incoming heals.",
                p = "opt_bars",
                t = "Opens: Frames > Bars > Absorb Display",
                x = "Absorb Display Heal Prediction incoming heals absorb health group frames",
                k = SearchKeywordList(
                    "absorb|absorbs|absorb bar|absorb texture|heal prediction|incoming heals|healing prediction",
                    "shields|shield bar|health absorb"
                ),
                y = 45,
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
        })
    end)
end
