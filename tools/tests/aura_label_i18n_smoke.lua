-- Aura spell-list and Edit Mode labels are composed from translated parts.
--
-- Re-review 2026-10-02: the aura menu model built "Name (#id)", "key
-- (unresolved)" and "Main Hand - item" by concatenation, and the Edit Mode
-- preview header concatenated an English unit label ("Boss " .. n) with an
-- English lane label, so none of it followed the menu language. The words now
-- go through MSUF.Translate and the parts meet in a translated format.
-- Part 1 runs the real label helpers against a marking translator; part 2
-- fails on any of the old concatenations in the aura files.
-- Argument: the repository root.
local root = assert(arg[1], "repository root argument missing")
root = (tostring(root):gsub("\\", "/"):gsub("/+$", ""))
local ADDON = root .. "/MidnightSimpleUnitFrames/"

local translated = {
    ["Spell"] = "Zauber",
    ["%s (unresolved)"] = "%s (nicht aufgelöst)",
    ["Boss %s"] = "Boss-%s",
    ["Arena %s"] = "Arena-%s",
    ["%s %s"] = "%s · %s",
    ["Target"] = "Ziel",
    ["Buffs"] = "Stärkungen",
    ["Debuffs"] = "Schwächungen",
    ["Defensive Buffs"] = "Defensive",
}
local namespace = {
    Translate = function(text) return translated[text] or text end,
}
_G.MSUF_NS = namespace
_G.C_Spell = {
    GetSpellInfo = function(spellID)
        if spellID == 1001 then return { name = "Heiliges Licht", spellID = 1001, iconID = 1 } end
        return nil
    end,
}

-- 1a. Menu model label helpers (Auras3/MenuModel/MSUF_Auras3_Menu_Common.lua).
assert(loadfile(ADDON .. "Auras3/MenuModel/MSUF_Auras3_Menu_Common.lua"))("MidnightSimpleUnitFrames", namespace)
local Common = namespace.Auras3MenuModelFactories.Common({ BOSS_LOOKUP = {}, BOSS_UNITS = {}, ARENA_UNITS = {}, ARENA_LOOKUP = {} })
assert(type(Common.SpellIDText) == "function" and type(Common.UnresolvedSpellText) == "function",
    "the menu model exports no translated spell label helpers")
assert(Common.SpellLabel(1001) == "Heiliges Licht (#1001)", "a resolved spell label changed: " .. Common.SpellLabel(1001))
assert(Common.SpellLabel(2002) == "Zauber (#2002)",
    "an unnamed spell kept the English fallback: " .. Common.SpellLabel(2002))
assert(Common.SpellIDText(nil, 7, "Rend") == "Rend (#7)", "a data fallback name was dropped")
assert(Common.SpellIDText("", 7) == "Zauber (#7)", "an empty name kept the English fallback")
assert(Common.UnresolvedSpellText("mystery") == "mystery (nicht aufgelöst)",
    "an unresolved key kept the English suffix: " .. Common.UnresolvedSpellText("mystery"))

-- 1b. The Edit Mode preview header (Auras3/MSUF_Auras3_EditMode_Config.lua).
namespace.MSUF_Auras3 = {}
assert(loadfile(ADDON .. "Auras3/MSUF_Auras3_EditMode_Config.lua"))("MidnightSimpleUnitFrames", namespace)
local config = namespace.MSUF_Auras3.EditModeModules.Config()
local GroupTitle = assert(config.GroupTitle, "the Edit Mode config exports no preview group title")
local groups = config.GROUPS
assert(GroupTitle("boss2", "buff", groups.buff) == "Boss-2 · Stärkungen",
    "the boss preview header is not translated: " .. GroupTitle("boss2", "buff", groups.buff))
assert(GroupTitle("arena3", "debuff", groups.debuff) == "Arena-3 · Schwächungen",
    "the arena preview header is not translated: " .. GroupTitle("arena3", "debuff", groups.debuff))
assert(GroupTitle("target", "buff", groups.buff) == "Ziel · Stärkungen", "the target preview header is not translated")
assert(GroupTitle("player", "custom4", groups.custom4) == "Player · Defensive",
    "the player defensive header is not translated: " .. GroupTitle("player", "custom4", groups.custom4))

-- 2. No aura file concatenates these labels again.
local FORBIDDEN = {
    { pattern = '%.%.%s*" %(#"', label = '.. " (#" (use SpellIDText)' },
    { pattern = '" %(unresolved%)"', label = '" (unresolved)" (use UnresolvedSpellText)' },
    { pattern = '"Boss "%s*%.%.', label = '"Boss " .. (use the "Boss %s" format)' },
    { pattern = '"Arena "%s*%.%.', label = '"Arena " .. (use the "Arena %s" format)' },
    { pattern = '%(" %- "%s*%.%.', label = '(" - " .. (use the "%s - %s" format)' },
    { pattern = '"Custom Aura "%s*%.%.', label = '"Custom Aura " .. (use the "Custom Aura %d" format)' },
}
-- Persisted default names: translating them changes saved data, which the
-- page owner decides (re-review 2026-10-02, reported to the lead).
local ALLOWED = {
    ["MidnightSimpleUnitFrames/Auras3/MenuModel/MSUF_Auras3_Menu_Containers.lua"] = {
        ['"Custom Aura "%s*%.%.'] = 1,
    },
}

local pipe = assert(io.popen('git -C "' .. root .. '" ls-files -- MidnightSimpleUnitFrames/Auras3 "MidnightSimpleUnitFrames/Game/*/Auras/*"'))
local files = {}
for line in pipe:lines() do if line:match("%.lua$") then files[#files + 1] = line end end
pipe:close()
assert(#files > 80, "the aura file list is incomplete (" .. #files .. " files)")

local failures = {}
for _, path in ipairs(files) do
    local handle = assert(io.open(root .. "/" .. path, "rb"))
    local source = handle:read("*a"):gsub("\r\n", "\n")
    handle:close()
    local lineNumber = 0
    local counts = {}
    for line in (source .. "\n"):gmatch("([^\n]*)\n") do
        lineNumber = lineNumber + 1
        local code = line:gsub("%-%-.*$", "")
        for _, rule in ipairs(FORBIDDEN) do
            if code:find(rule.pattern) then
                counts[rule.pattern] = (counts[rule.pattern] or 0) + 1
                local allowed = ALLOWED[path] and ALLOWED[path][rule.pattern]
                if not allowed or counts[rule.pattern] > allowed then
                    failures[#failures + 1] = path .. ":" .. lineNumber .. ": " .. rule.label
                end
            end
        end
    end
    for pattern, allowedCount in pairs(ALLOWED[path] or {}) do
        assert((counts[pattern] or 0) == allowedCount,
            path .. ": allowlist entry " .. pattern .. " is stale; remove it")
    end
end
if #failures > 0 then
    error("aura labels concatenated before translating:\n  " .. table.concat(failures, "\n  "), 0)
end
print("aura label i18n smoke: OK (" .. #files .. " files)")
