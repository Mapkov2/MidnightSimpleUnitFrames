-- castbar_preview_time_offset_smoke.lua <repoRoot> <flavor>
--
-- The live boss and arena castbars place their time text at -2 plus the
-- stored <unit>CastTimeOffsetX (Castbars/MSUF_CastbarVisuals.lua,
-- ApplyTimeTextLayout; castbar_correctness_smoke section 1 pins that side).
-- The Castbars page preview applied the arena offset raw, 2 px right of the
-- live bar, the Unit preview and its drag handle. Both menu previews now read
-- the offsets from one helper, MSUF.UFPreviewCastbar.TimeOffsets:
--   1. the helper follows the live rule for every castbar unit (boss and
--      arena on the -2 base without the player fallback; the other units
--      fall back to the player offset, then to -2 and 0);
--   2. the Castbars page preview anchors its time text at those offsets for
--      boss, arena (where the client has arena frames) and target;
--   3. the Unit preview calls the same helper instead of its own copy.
--
-- Boots the real core and Options graph of one client (menu_core_world.lua).
-- Plain Lua 5.1, repo root and client flavor.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client flavor required")
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()

local function Check(condition, message)
    if not condition then error("castbar_preview_time_offset_smoke " .. flavor .. ": " .. message, 2) end
end

local mw = MenuWorld.Open(root, flavor, { page = "opt_castbar" })
local M, env, core = mw.M, mw.env, mw.core
local general = env.MSUF_DB.general

---------------------------------------------------------------------------
-- 1. The shared helper follows the live rule
---------------------------------------------------------------------------
local Castbar = core.UFPreviewCastbar
Check(type(Castbar) == "table" and type(Castbar.TimeOffsets) == "function",
    "MSUF.UFPreviewCastbar.TimeOffsets is missing")
local function Offsets(g, unit)
    local x, y = Castbar.TimeOffsets(g, unit)
    return tostring(x) .. "/" .. tostring(y)
end
local PLAYER = { castbarPlayerTimeOffsetX = 9, castbarPlayerTimeOffsetY = 7 }
for _, unit in ipairs({ "boss", "arena" }) do
    local g = { castbarPlayerTimeOffsetX = 9, castbarPlayerTimeOffsetY = 7 }
    Check(Offsets(g, unit) == "-2/0", unit .. ": unset offsets " .. Offsets(g, unit) .. ", live uses -2/0")
    g[unit .. "CastTimeOffsetX"], g[unit .. "CastTimeOffsetY"] = 5, 3
    Check(Offsets(g, unit) == "3/3", unit .. ": stored 5/3 gave " .. Offsets(g, unit) .. ", live uses 3/3")
    Check(Offsets(g, unit .. "2") == "3/3", unit .. "2: a numbered unit does not share its kind's offsets")
end
Check(Offsets({ castbarTargetTimeOffsetX = 4, castbarTargetTimeOffsetY = -1 }, "target") == "4/-1",
    "target: own offsets not read")
Check(Offsets(PLAYER, "target") == "9/7", "target: unset offsets do not fall back to the player offsets")
Check(Offsets({}, "focus") == "-2/0", "focus: unset offsets are not -2/0")

---------------------------------------------------------------------------
-- 2. The Castbars page preview anchors the time text there
---------------------------------------------------------------------------
local preview = M._msuf2CastbarPreview
Check(type(preview) == "table" and preview.time, "the Castbars page did not build its preview")
local function TimePoint(unit)
    local ok, shown = M.SetCastbarPreviewUnit(unit)
    mw:RunTimers()
    if not ok or shown ~= unit then return nil end
    Check(preview.time.shown ~= false, unit .. ": time text hidden")
    local points = preview.time.points
    local point = points[#points]
    Check(point ~= nil, unit .. ": time text not anchored")
    return tostring(point.x) .. "/" .. tostring(point.y)
end
local checked = {}
general.castbarPlayerTimeOffsetX, general.castbarPlayerTimeOffsetY = 9, 7
for _, unit in ipairs({ "boss", "arena" }) do
    general[unit .. "CastTimeOffsetX"], general[unit .. "CastTimeOffsetY"] = 5, 3
    local point = TimePoint(unit)
    if point then
        Check(point == "3/3", unit .. ": page preview time text at " .. point .. ", the live bar is at 3/3")
        general[unit .. "CastTimeOffsetX"], general[unit .. "CastTimeOffsetY"] = nil, nil
        point = TimePoint(unit)
        Check(point == "-2/0", unit .. ": unset page preview time text at " .. point .. ", the live bar is at -2/0")
        checked[#checked + 1] = unit
    end
end
general.castbarTargetTimeOffsetX, general.castbarTargetTimeOffsetY = nil, nil
local targetPoint = TimePoint("target")
Check(targetPoint == "9/7", "target: page preview time text at " .. tostring(targetPoint)
    .. ", the live bar falls back to the player offsets 9/7")
checked[#checked + 1] = "target"
local arenaFrames = tonumber(core.Client and core.Client.MaxArenaOpponents) or 0
if arenaFrames > 0 then
    Check(table.concat(checked, ","):find("arena", 1, true), "arena: the client has arena frames but the preview has no arena unit")
end

---------------------------------------------------------------------------
-- 3. The Unit preview uses the same helper
---------------------------------------------------------------------------
local function Read(path)
    local handle = assert(io.open(root .. "/" .. path, "rb"), "cannot open " .. path)
    local text = handle:read("*a"):gsub("\r\n", "\n")
    handle:close()
    return text
end
local MENU = "MidnightSimpleUnitFrames_Options/Shell/Menu2/"
for _, path in ipairs({ MENU .. "Preview/MSUF_Menu2_UnitPreview_Render.lua", MENU .. "Pages/MSUF_Menu2_GlobalCastbars_Preview.lua" }) do
    local text = Read(path)
    Check(text:find("CastbarPreview.TimeOffsets(g, ", 1, true), path .. " no longer reads the shared time offsets")
    Check(not text:find('"TimeOffsetX", "bossCastTimeOffsetX"', 1, true) or path:find("Render", 1, true),
        path .. " computes its own time X offset again")
    Check(not text:find("-2 + (tonumber(g.arenaCastTimeOffsetX)", 1, true)
        and not text:find("-2 + (tonumber(g.bossCastTimeOffsetX)", 1, true),
        path .. " keeps its own copy of the -2 base")
end

print(string.format("castbar_preview_time_offset_smoke %s: ok (helper rule; page preview %s)",
    flavor, table.concat(checked, ", ")))
