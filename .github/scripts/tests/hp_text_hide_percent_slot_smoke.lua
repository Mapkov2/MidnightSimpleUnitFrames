-- Per-slot "Hide % sign" and absorb-icon flags must stay on their own slot.
--
-- Reported against Beta 30: the target frame's HP text lost its % sign while
-- the player frame kept it. Target renders the percent in the CENTER slot,
-- player in the RIGHT slot, and the compile loops selected the per-slot
-- booleans with `i == n and flagN or ... or flag3`. In Lua that collapses as
-- soon as the selected flag is false, so Left/Center fell through to the RIGHT
-- slot's flag: target's center (hide = false) silently inherited right's
-- hide = true. The right slot read flag3 directly, which is why player looked
-- fine. The same trap applied to the per-slot absorb icon.
--
-- Second defect on the same feature: `slot ~= nil and slot == true or fallback`
-- turned an explicit per-slot false ("show the % sign") back into the global
-- flag's "hide", so the per-slot toggle looked dead whenever the global one
-- was on.
--
-- All of this is apply/compile-time work; the value hotpaths must stay clear.

local root = arg and arg[1] or "."

local function Read(path)
    local file = assert(io.open(root .. "/" .. path, "rb"))
    local source = file:read("*a")
    file:close()
    return (source:gsub("\r\n", "\n"))
end

local format = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Text_Format.lua")

-- 1) The broken boolean selection idiom must not come back for flag values.
assert(not format:find("and hidePercentSymbol1 or", 1, true),
    "health/power hide-% slot flags are selected with the and/or idiom again")
assert(not format:find("and absorbIcon1 or", 1, true),
    "absorb icon slot flags are selected with the and/or idiom again")
assert(not format:find("HidePercentSymbol ~= nil and", 1, true),
    "per-slot hide-% still resolves through `~= nil and ... == true or fallback`")

-- 2) Branch selection is in place for both compile loops.
local _, branchCount = format:gsub("hidePercentSymbol, absorbIcon = hidePercentSymbol%d, absorbIcon%d", "")
assert(branchCount == 3, "health slot compile must branch-select all three slots, got " .. branchCount)
assert(format:find("if i == 1 then hidePercentSymbol = hidePercentSymbol1", 1, true),
    "power slot compile must branch-select its hide-% flags")

-- 3) Behaviour: ResolveHealthTextModes keeps each slot's flag on its own slot
--    and lets an explicit false beat the global fallback.
local chunk = format:match("(local function ResolveHealthTextModes%(text%).-\nend)")
assert(chunk, "could not extract ResolveHealthTextModes")
local loader = assert(loadstring or load)
local Resolve = assert(loader(
    "local REVERSE_HEALTH_MODE = {}\n" .. chunk .. "\nreturn ResolveHealthTextModes"))()

-- The reported case: center shows the percent, right hides it.
local _, _, _, hideLeft, hideCenter, hideRight = Resolve({
    healthLeft = "CURRENT", healthCenter = "PERCENT", healthRight = "NONE",
    healthCenterHidePercentSymbol = false,
    healthRightHidePercentSymbol = true,
})
assert(hideCenter == false, "center slot inherited the right slot's Hide % sign")
assert(hideRight == true, "right slot lost its own Hide % sign")
assert(hideLeft == false, "left slot inherited a foreign Hide % sign")

-- An explicit per-slot false outranks the global flag.
local _, _, _, gLeft, gCenter, gRight = Resolve({
    hidePercentSymbol = true,
    healthLeftHidePercentSymbol = false,
    healthCenterHidePercentSymbol = false,
})
assert(gLeft == false and gCenter == false,
    "explicit per-slot 'show %' was overridden by the global Hide % sign")
assert(gRight == true, "unset slot must still inherit the global Hide % sign")

-- Absorb icons follow the same per-slot rule.
local _, _, _, _, _, _, iconLeft, iconCenter, iconRight = Resolve({
    healthAbsorbIcon = true,
    healthLeftAbsorbIcon = false,
    healthRightAbsorbIcon = true,
})
assert(iconLeft == false, "explicit per-slot absorb icon 'off' was overridden by the unit flag")
assert(iconCenter == true, "unset slot must inherit the unit-level absorb icon")
assert(iconRight == true, "right slot lost its own absorb icon")

-- Reverse order still mirrors the flags with the content, exactly once.
local _, _, _, rLeft, _, rRight = Resolve({
    healthReverse = true,
    healthLeftHidePercentSymbol = false,
    healthRightHidePercentSymbol = true,
})
assert(rLeft == true and rRight == false, "reverse order must mirror the hide-% flags with the slot content")

-- 4) Combat overhead guard: slot flag resolution stays out of the value paths.
for _, path in ipairs({
    "MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Health.lua",
    "MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Power.lua",
    "MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Text_Runtime.lua",
}) do
    local source = Read(path)
    assert(not source:find("HidePercentSymbol", 1, true),
        "per-slot hide-% resolution leaked into a value hotpath: " .. path)
end

print("hp_text_hide_percent_slot_smoke: ok")
