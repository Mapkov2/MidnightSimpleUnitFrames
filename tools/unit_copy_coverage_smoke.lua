--- Contract smoke: the unit page "Copy to" dialog must actually copy everything a
--- user can configure per unit frame.
---
--- Every new per-unit setting silently misses the copy dialog unless it is added to
--- one of the COPY_* lists in MSUF_Menu2_Unit.lua. That drift is invisible in game:
--- the copy reports success and the destination frame simply keeps looking different.
--- This smoke pins the three key universes against the copy lists:
---
---   1. per-unit config keys seeded by State/MSUF_Defaults.lua (textDefaults + fill)
---   2. the per-unit Bars/Font override scopes from MSUF_Menu2_Bindings.lua
---   3. the per-unit castbar suffixes stored in the general DB
---
--- A new key must land in a copy list or in the ALLOWLIST below with a reason.

local UNIT_PAGE = "MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_Unit.lua"
local BINDINGS = "MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_Bindings.lua"
local DEFAULTS = "MidnightSimpleUnitFrames/State/MSUF_Defaults.lua"

--- Keys that are deliberately not copied. Keep the reason with the entry.
local ALLOWLIST = {
    --- Ownership handoff to the Blizzard frame, not a look. Copying it would hide a
    --- destination frame the user never asked to hide.
    useBlizzardFrame = true,
    --- Player-only nested table (channel tick markers), copied by no category.
    castbar = true,
    --- Preview-only runtime flag, never part of a user's configuration.
    castbarPreviewEnabled = true,
    --- Backend memory for the hide/restore toggle; CopyCastbar derives it instead.
    castbarBackendBeforeHide = true,
    --- Detaching turns OffsetX/OffsetY into an absolute UIParent position, so neither
    --- the flag nor a detached position may travel: both castbars would end up stacked
    --- on the same screen spot. CopyCastbar copies the offsets in the anchored case only.
    castbarDetached = true,
    --- Legacy width-source key; MSUF_Defaults migrates it into MatchWidth, which the
    --- copy already carries. Copying it back would resurrect a pre-migration value.
    castbarMatchUnitWidth = true,
    --- Boss-only container geometry has no equivalent on a single Player/Target/etc.
    --- frame. Carrying any of these through Unit Copy would either leak dead keys into
    --- normal units or erase the destination Boss stack layout.
    bossLayoutMode = true,
    invertBossOrder = true,
    spacing = true,
}

local function Read(path)
    local handle = io.open(path, "rb")
    assert(handle, "cannot open " .. path)
    local body = handle:read("*a")
    handle:close()
    --- The editor saves CRLF; normalize so the line patterns below match locally too.
    return (body:gsub("\r\n", "\n"))
end

local function AddWords(target, text)
    for word in tostring(text or ""):gmatch("%S+") do target[word] = true end
end

--- Collects a `local NAME = WL [[ ... ]]` / `KSW [[ ... ]]` word list.
local function WordListLiteral(source, name)
    local body = source:match("local " .. name .. " = %u+ %[%[(.-)%]%]")
    assert(body, "word list not found: " .. name)
    local out = {}
    AddWords(out, body)
    return out
end

local unitPage = Read(UNIT_PAGE)
local bindings = Read(BINDINGS)
local defaults = Read(DEFAULTS)

-- ---------------------------------------------------------------- covered keys
local covered = {}
for _, name in ipairs({
    "COPY_POWER_BAR_FIELDS", "COPY_PORTRAIT_FIELDS", "COPY_TEXT_FIELDS",
    "COPY_FRAME_BASIC_FIELDS", "COPY_TRANSPARENCY_FIELDS", "COPY_LOAD_CONDITION_FIELDS",
    "COPY_LAYOUT_FIELDS",
}) do
    for key in pairs(WordListLiteral(unitPage, name)) do covered[key] = true end
end

--- STATUS_CONTROLS drives COPY_INDICATOR_FIELDS / COPY_STATUSICON_FIELDS through
--- CopyFieldsFromSpecs, so every camelCase identifier in that block is copied by the
--- status category. Labels ("Leader Icon") and enum values ("TOPLEFT") are skipped.
local statusBlock = unitPage:match("local STATUS_CONTROLS = {\n(.-)\n}")
assert(statusBlock, "STATUS_CONTROLS block not found")
for quoted in statusBlock:gmatch('"([^"]+)"') do
    if quoted:match("^%l[%a%d]*$") then covered[quoted] = true end
end

--- Keys the copy routine assigns one by one instead of through a list.
for key in unitPage:gmatch("dst%.([%a%d_]+) = src%.") do covered[key] = true end

-- --------------------------------------------------------------- required keys
local required = {}
local function RequireBlock(startPattern, stopPattern)
    local inBlock = false
    for line in defaults:gmatch("[^\n]*") do
        if inBlock then
            if line:match(stopPattern) then
                inBlock = false
            else
                local key = line:match("^%s+([%a_][%w_]*)%s*=")
                if key then required[key] = true end
            end
        elseif line:match(startPattern) then
            inBlock = true
        end
    end
end
RequireBlock("^%s*local textDefaults = {%s*$", "^%s*}%s*$")
RequireBlock('^%s*fill%("%a+", {%s*$', "^%s*}%)%s*$")
assert(next(required), "no per-unit default keys parsed from " .. DEFAULTS)

for _, name in ipairs({ "BARS_SCOPE_KEYS", "FONT_SCOPE_KEYS" }) do
    for key in pairs(WordListLiteral(bindings, name)) do required[key] = true end
end

-- ------------------------------------------------------------ castbar suffixes
--- Castbar settings live in the general DB under a per-unit prefix. Use the player
--- prefix as the reference universe; the copy applies the same suffixes to every unit.
local castbarRequired = {}
for _, path in ipairs({ UNIT_PAGE, BINDINGS, DEFAULTS,
    "MidnightSimpleUnitFrames/Castbars/MSUF_CastbarAnchors.lua",
    "MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_UnitFrameVisuals.lua",
}) do
    for suffix in Read(path):gmatch("castbarPlayer(%u[%w]*)") do castbarRequired[suffix] = true end
end
assert(next(castbarRequired), "no castbar suffixes parsed")

local castbarCovered = {}
for _, name in ipairs({ "CASTBAR_COPY_SUFFIXES", "CASTBAR_TARGET_NAME_COPY_SUFFIXES" }) do
    for key in pairs(WordListLiteral(unitPage, name)) do castbarCovered[key] = true end
end
--- CASTBAR_FIELDS names the keys CopyCastbar assigns explicitly, including the
--- non-uniform Boss geometry keys (bossCastbarDetached/OffsetX/OffsetY).
local castbarFields = unitPage:match("local CASTBAR_FIELDS = {\n(.-)\n}")
assert(castbarFields, "CASTBAR_FIELDS block not found")
for suffix in castbarFields:gmatch("castbarPlayer(%u[%w]*)") do castbarCovered[suffix] = true end

-- --------------------------------------------------------------------- compare
local failures = {}
local function Check(requiredSet, coveredSet, allowPrefix, label)
    local missing = {}
    for key in pairs(requiredSet) do
        if not coveredSet[key] and not ALLOWLIST[allowPrefix .. key] and not ALLOWLIST[key] then
            missing[#missing + 1] = key
        end
    end
    table.sort(missing)
    if #missing > 0 then
        failures[#failures + 1] = string.format(
            "%s: %d setting(s) are configurable per unit but no copy category copies them: %s",
            label, #missing, table.concat(missing, " "))
    end
end

Check(required, covered, "", "unit config keys")
Check(castbarRequired, castbarCovered, "castbar", "castbar suffixes")

if #failures > 0 then
    io.write("FAIL unit copy coverage\n", table.concat(failures, "\n"), "\n")
    os.exit(1)
end

local requiredCount, castbarCount = 0, 0
for _ in pairs(required) do requiredCount = requiredCount + 1 end
for _ in pairs(castbarRequired) do castbarCount = castbarCount + 1 end
io.write(string.format(
    "PASS unit copy coverage: %d per-unit keys and %d castbar suffixes are all covered by a copy category\n",
    requiredCount, castbarCount))
