local root = arg and arg[1] or "."

local file = assert(io.open(root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras.lua", "rb"))
local source = file:read("*a")
file:close()

local function Has(needle, message)
    assert(source:find(needle, 1, true), message .. ": " .. needle)
end

local function Count(needle)
    local total, cursor = 0, 1
    while true do
        local found = source:find(needle, cursor, true)
        if not found then return total end
        total, cursor = total + 1, found + #needle
    end
end

Has('b:CollapsibleSection(sectionId, "Preview", sectionH, true)',
    "Buff/Debuff preview keeps a redundant lane prefix")
assert(Count('b:CollapsibleSection(baseId .. "_features", "Basics"') == 2,
    "Unit and Group Aura Basics do not share the compact title")
assert(Count('b:CollapsibleSection(baseId .. "_stack", "Stack Count"') == 2,
    "Unit and Group stack accordions do not share the compact title")
assert(Count('b:CollapsibleSection(baseId .. "_cooldown", "Cooldown Text"') == 2,
    "Unit and Group cooldown accordions do not share the compact title")
assert(Count('b:CollapsibleSection(baseId .. "_duration_bar", "Duration Bar"') == 2,
    "Unit and Group duration accordions do not share the compact title")
assert(Count('b:CollapsibleSection(baseId .. "_behavior", "Ordering"') == 2,
    "Unit and Group ordering accordions do not share the compact title")
Has('b:CollapsibleSection(baseId .. "_full_frame", "Full-Frame Effect"',
    "Unit Aura full-frame accordion keeps a redundant lane prefix")

Has('local function CustomStyleSectionId(index, suffix)',
    "Custom Aura accordions have no persistent per-container identity")
Has('b:CollapsibleSection(CustomStyleSectionId(index, "preview"), "Preview", 452, true)',
    "Custom Aura preview is not an accordion")
Has('b:CollapsibleSection(CustomStyleSectionId(index, "basics"), "Basics", 130, true)',
    "Custom Aura basics is not an accordion")
Has('b:CollapsibleSection(CustomStyleSectionId(index, "stack"), "Stack Count", 130, false)',
    "Custom Aura stack count is not an accordion")
Has('b:CollapsibleSection(CustomStyleSectionId(index, "cooldown"), "Cooldown Text", 184, true)',
    "Custom Aura cooldown text is not an accordion")
Has('b:CollapsibleSection(CustomStyleSectionId(index, "duration_bar"), "Duration Bar", 130, false)',
    "Custom Aura duration bar is not an accordion")
Has('b:CollapsibleSection(CustomStyleSectionId(index, "full_frame"), "Full-Frame Effect", 210, false)',
    "Custom Aura full-frame effect is not an accordion")
Has('b:CollapsibleSection(CustomStyleSectionId(index, "behavior"), "Ordering", 96, false)',
    "Custom Aura ordering is not an accordion")
assert(not source:find('"Icon Style"', 1, true),
    "the monolithic Custom Aura Icon Style card is back")

for _, redundant in ipairs({
    'LaneTitle(lane) .. " Preview"',
    'LaneTitle(lane) .. " Basics"',
    'LaneTitle(lane) .. " Stack Count"',
    'LaneTitle(lane) .. " Cooldown Text"',
    'LaneTitle(lane) .. " Duration Bar"',
    'LaneTitle(lane) .. " Full-Frame Effect"',
    'LaneTitle(lane) .. " Ordering"',
}) do
    assert(not source:find(redundant, 1, true),
        "redundant Aura container name remains in an accordion title: " .. redundant)
end

print("aura_style_accordion_contract_smoke: ok")
