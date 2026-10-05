-- classic_castbar_spark_sync_smoke.lua <repoRoot> <flavor>
--
-- Classic sizes the castbar spark from the drawable inner status bar (the
-- outline insets it on both sides; Game/Classic/Castbars/
-- MSUF_CastbarVisualCompat.lua replaces MSUF_ApplyCastbarSparkVisual). The
-- shared cold visual pass in Castbars/MSUF_Castbars_Core.lua ran its local
-- Retail spark pass after the Classic one, so every path that does not end in
-- a hooked public entry (the Edit Mode popup's MSUF_ApplyCastbarUnitAndSync,
-- the settings refresh) left the spark at the outer frame height: with the
-- spark on, an outline and no overflow it covered the outline top and bottom.
-- Boots the real core of a Classic client and checks the target castbar's
-- spark after each of those paths.
--
-- Plain Lua 5.1: repo root and Classic flavor as arguments.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Vanilla"
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Check(condition, message)
    if not condition then error(flavor .. ": " .. message, 2) end
end

local world = World.New(root, flavor)
world:Boot()
local failure = world:FirstFailure()
Check(not failure, "boot failed: " .. tostring(failure and failure.message))
local env = world.env
env.MSUF_EnsureDB(true)
-- The settings refresh may swap the general table: always write the live one.
local function General() return env.MSUF_DB.general end
General().castbarShowSpark, General().castbarSparkOverflow, General().castbarOutlineThickness = true, false, 3

local function Spark(path)
    local frame = env.MSUF_TargetCastbar or env.MSUF_TargetCastBar
    Check(frame and frame.statusBar and frame.spark, path .. ": the target castbar has no spark")
    local inner, outer = frame.statusBar:GetHeight(), frame:GetHeight()
    Check(inner and outer and inner < outer, path .. ": the outline did not inset the status bar")
    return frame.spark:GetHeight(), inner, outer
end

env.MSUF_Castbars_OnSettingsChanged()
world.widgets:RunTimers(1000)
local height, inner, outer = Spark("settings refresh")
Check(height == inner, string.format("settings refresh: the spark is %s high, the inner bar %s (outer frame %s)",
    tostring(height), tostring(inner), tostring(outer)))

env.MSUF_ApplyCastbarUnitAndSync("target")
height, inner, outer = Spark("Edit Mode apply")
Check(height == inner, string.format("Edit Mode apply: the spark is %s high, the inner bar %s (outer frame %s)",
    tostring(height), tostring(inner), tostring(outer)))

-- The overflow toggle applies through the public visuals entry; the next Edit
-- Mode apply must keep the inner-surface overflow height.
General().castbarSparkOverflow = true
env.MSUF_UpdateCastbarVisuals("target")
env.MSUF_ApplyCastbarUnitAndSync("target")
height, inner = Spark("Edit Mode apply with overflow")
Check(math.abs(height - inner * 2.1) < 1e-6, string.format(
    "Edit Mode apply with overflow: the spark is %s high, expected 2.1 x the inner bar %s", tostring(height), tostring(inner)))

print("classic_castbar_spark_sync_smoke: " .. flavor .. " OK")
