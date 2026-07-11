-- Assistant GroupFrames text alias helper core.
-- Builds string alias helpers used by the split GroupFrames registry core.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GroupFramesRegistry = A.GroupFramesRegistry or {}

function A.GroupFramesRegistry.BuildTextAliasContext(ctx)
    if type(ctx) ~= "table" then return nil end

    local GroupFramesData = ctx.GroupFramesData
    if type(GroupFramesData) ~= "table" then return nil end

    local function GroupBarModeExactAliases(scope)
        local out = {}
        local function add(value)
            if value and value ~= "" then out[#out + 1] = value end
        end
        local function addModePhrases(term)
            add(term .. " class color")
            add(term .. " class colors")
            add(term .. " class colored")
            add("make " .. term .. " class colored")
            add(term .. " colored by class")
            add(term .. " use class color")
            add(term .. " use class colors")
            add(term .. " bar color mode")
            add(term .. " health bar color mode")
            add(term .. " group bar style")
            add(term .. " global color")
            add(term .. " global colors")
            add(term .. " use global color")
            add(term .. " use global colors")
            add(term .. " default color")
            add(term .. " default colors")
            add(term .. " use default colors")
        end
        local function addModeForScopePhrases(term)
            add("class color mode for " .. term)
            add("class colors for " .. term)
            add("class colored bars for " .. term)
            add("global colors for " .. term)
            add("default colors for " .. term)
        end
        local scopeTerms = {
            party = { "party", "party frame", "party frames", "partyframe", "partyframes" },
            raid = { "raid", "raid frame", "raid frames", "raidframe", "raidframes" },
            mythicraid = { "mythic raid", "mythic raid frame", "mythic raid frames", "mythicraid", "mythicraidframe", "mythicraidframes" },
        }
        for _, term in ipairs({ "all group frames", "group frames", "group frame", "groupframes" }) do
            addModePhrases(term)
            addModeForScopePhrases(term)
        end
        for _, term in ipairs(scopeTerms[scope] or {}) do
            addModePhrases(term)
            addModeForScopePhrases(term)
        end
        return out
    end

    local function GroupGrowthExactAliases(scope)
        local out = {}
        local function add(value)
            if value and value ~= "" then out[#out + 1] = value end
        end
        local function addDirectionPhrases(term)
            for _, phrase in ipairs({
                "grow right", "grows right", "to grow right", "frames grow right", "frames to grow right",
                "grow right then down", "grow right and down", "right then down growth", "right first growth",
                "grow left", "grows left", "to grow left", "frames grow left", "frames to grow left",
                "grow left then down", "grow left and down", "left then down growth", "left first growth",
                "grow down", "grows down", "to grow down", "frames grow down", "frames to grow down",
                "grow down then right", "grow down and right", "down then right growth", "down first growth",
                "grow up", "grows up", "to grow up", "frames grow up", "frames to grow up",
                "grow up then right", "grow up and right", "up then right growth", "up first growth",
                "growth right", "growth left", "growth down", "growth up",
                "growth direction right", "growth direction left", "growth direction down", "growth direction up",
            }) do
                add(term .. " " .. phrase)
            end
        end
        local scopeTerms = {
            party = { "party", "party frame", "party frames", "partyframe", "partyframes", "party group", "party groups" },
            raid = { "raid", "raid frame", "raid frames", "raidframe", "raidframes", "raid group", "raid groups" },
            mythicraid = { "mythic raid", "mythic raid frame", "mythic raid frames", "mythicraid", "mythicraidframe", "mythicraidframes", "mythic raid group", "mythic raid groups" },
        }
        for _, term in ipairs(scopeTerms[scope] or {}) do addDirectionPhrases(term) end
        for _, term in ipairs({ "group frame", "group frames", "groupframes", "all group frames" }) do addDirectionPhrases(term) end
        return out
    end

    local GROUP_REVERSE_FILL_BOOLEAN_ALIASES = GroupFramesData.GROUP_REVERSE_FILL_BOOLEAN_ALIASES or {}

    local function GroupReverseFillExactAliases(scope)
        local out = {}
        local function add(value)
            if value and value ~= "" then out[#out + 1] = value end
        end
        local scopeTerms = {
            party = { "party", "party frame", "party frames", "partyframe", "partyframes" },
            raid = { "raid", "raid frame", "raid frames", "raidframe", "raidframes" },
            mythicraid = { "mythic raid", "mythic raid frame", "mythic raid frames", "mythicraid", "mythicraidframe", "mythicraidframes" },
        }
        local phrases = {
            "reverse fill",
            "reverse health fill",
            "fill backwards",
            "fill backward",
            "fill right to left",
            "right to left fill",
            "fill normal direction",
            "fill normal",
            "normal direction",
            "normal fill",
            "fill left to right",
            "left to right fill",
        }
        for _, term in ipairs(scopeTerms[scope] or {}) do
            for _, phrase in ipairs(phrases) do add(term .. " " .. phrase) end
        end
        for _, term in ipairs({ "group frame", "group frames", "groupframes", "all group frames" }) do
            for _, phrase in ipairs(phrases) do add(term .. " " .. phrase) end
        end
        return out
    end

    local function GroupReverseFillBooleanAliases(scope)
        local out = {}
        for key, value in pairs(GROUP_REVERSE_FILL_BOOLEAN_ALIASES) do out[key] = value end
        local scopeTerms = {
            party = { "party", "party frame", "party frames", "partyframe", "partyframes" },
            raid = { "raid", "raid frame", "raid frames", "raidframe", "raidframes" },
            mythicraid = { "mythic raid", "mythic raid frame", "mythic raid frames", "mythicraid", "mythicraidframe", "mythicraidframes" },
        }
        for _, term in ipairs(scopeTerms[scope] or {}) do
            out["turn off " .. term .. " reverse fill"] = false
            out["disable " .. term .. " reverse fill"] = false
            out[term .. " reverse fill off"] = false
            out["turn on " .. term .. " reverse fill"] = true
            out["enable " .. term .. " reverse fill"] = true
            out[term .. " reverse fill on"] = true
        end
        return out
    end

    return {
        GroupBarModeExactAliases = GroupBarModeExactAliases,
        GroupGrowthExactAliases = GroupGrowthExactAliases,
        GroupReverseFillExactAliases = GroupReverseFillExactAliases,
        GroupReverseFillBooleanAliases = GroupReverseFillBooleanAliases,
    }
end
