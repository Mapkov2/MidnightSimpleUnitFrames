-- castbar_preview_time_offset_smoke.lua <repoRoot> <flavor>
--
-- The live boss and arena castbars place their time text at -2 plus the
-- stored <unit>CastTimeOffsetX (Castbars/MSUF_CastbarVisuals.lua,
-- ApplyTimeTextLayout; castbar_correctness_smoke section 1 pins that side).
-- Both menu castbar previews now paint a real engine castbar scene, so the time
-- text follows that live rule without a preview-side copy of it:
--   1. the Castbars page preview anchors its time text at the live offsets for
--      every unit that has a castbar (boss and arena on the -2 base without the
--      player fallback; the other units fall back to the player offset, then
--      to -2 and 0);
--   2. neither preview file keeps its own offset helper or its own -2 base.
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

local preview = M._msuf2CastbarPreview
Check(type(preview) == "table", "the Castbars page did not build its preview")
local function TimePoint(unit)
    -- A setting write reaches the engine scene through the live castbar config, like the apply path does.
    core.Castbars.Config.Refresh()
    local ok, shown = M.SetCastbarPreviewUnit(unit)
    mw:RunTimers()
    if not ok or shown ~= unit then return nil end
    Check(preview.frame, unit .. ": the preview painted no castbar")
    local time = preview.frame.timeText
    Check(time.shown ~= false, unit .. ": time text hidden")
    local point = time.points[#time.points]
    Check(point ~= nil, unit .. ": time text not anchored")
    return tostring(point.x) .. "/" .. tostring(point.y)
end
local function Clear(unit)
    general[unit .. "CastTimeOffsetX"], general[unit .. "CastTimeOffsetY"] = nil, nil
end

---------------------------------------------------------------------------
-- 1. The Castbars page preview anchors the time text on the live rule
---------------------------------------------------------------------------
local checked = {}
general.castbarPlayerTimeOffsetX, general.castbarPlayerTimeOffsetY = 9, 7
for _, unit in ipairs({ "boss", "arena" }) do
    Clear(unit)
    local unset = TimePoint(unit)
    if unset then
        Check(unset == "-2/0", unit .. ": unset offsets " .. unset .. ", live uses -2/0 (no player fallback)")
        general[unit .. "CastTimeOffsetX"], general[unit .. "CastTimeOffsetY"] = 5, 3
        local stored = TimePoint(unit)
        Check(stored == "3/3", unit .. ": stored 5/3 gave " .. tostring(stored) .. ", live uses 3/3")
        Clear(unit)
        checked[#checked + 1] = unit
    end
end
general.castbarTargetTimeOffsetX, general.castbarTargetTimeOffsetY = 4, -1
Check(TimePoint("target") == "4/-1", "target: own offsets not read")
general.castbarTargetTimeOffsetX, general.castbarTargetTimeOffsetY = nil, nil
Check(TimePoint("target") == "9/7", "target: unset offsets do not fall back to the player offsets 9/7")
checked[#checked + 1] = "target"
general.castbarPlayerTimeOffsetX, general.castbarPlayerTimeOffsetY = nil, nil
general.castbarFocusTimeOffsetX, general.castbarFocusTimeOffsetY = nil, nil
local focus = TimePoint("focus")
if focus then
    Check(focus == "-2/0", "focus: unset offsets gave " .. tostring(focus) .. ", live uses -2/0")
    checked[#checked + 1] = "focus"
end
local arenaFrames = tonumber(core.Client and core.Client.MaxArenaOpponents) or 0
if arenaFrames > 0 then
    Check(table.concat(checked, ","):find("arena", 1, true), "arena: the client has arena frames but the preview has no arena unit")
end

---------------------------------------------------------------------------
-- 2. No preview-side copy of the rule
---------------------------------------------------------------------------
local function Read(path)
    local handle = assert(io.open(root .. "/" .. path, "rb"), "cannot open " .. path)
    local text = handle:read("*a"):gsub("\r\n", "\n")
    handle:close()
    return text
end
local MENU = "MidnightSimpleUnitFrames_Options/Shell/Menu2/"
Check(core.UFPreviewCastbar.TimeOffsets == nil, "the preview-side TimeOffsets helper came back")
for _, path in ipairs({ MENU .. "Preview/MSUF_Menu2_UnitPreview_Render.lua", MENU .. "Pages/MSUF_Menu2_GlobalCastbars_Preview.lua",
    MENU .. "Preview/MSUF_Menu2_UnitPreview_Castbar.lua" }) do
    local text = Read(path)
    Check(not text:find("TimeOffsets", 1, true), path .. " reads time offsets itself again")
    Check(not text:find("-2 + (tonumber(g.arenaCastTimeOffsetX)", 1, true)
        and not text:find("-2 + (tonumber(g.bossCastTimeOffsetX)", 1, true),
        path .. " keeps its own copy of the -2 base")
end

print(string.format("castbar_preview_time_offset_smoke %s: ok (page preview %s)", flavor, table.concat(checked, ", ")))
