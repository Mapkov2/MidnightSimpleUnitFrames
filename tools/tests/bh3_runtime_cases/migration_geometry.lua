-- Probe: a scope stamped GRID_CENTER_V1 by the DB repair (every new profile's
-- Party / Mythic Raid scope: the factory carries no positionMode) whose size is
-- changed before the scope is first shown (Edit Mode "Copy size to...", Copy To
-- Basics, or the Layout sliders while that scope's preview is not up).
-- Two otherwise identical scopes, A converted before the size edit, B after it.
local root = assert(arg[1])
local World = dofile(root .. "/tools/tests/client_world.lua")
local w = World.New(root, "Mainline"):Boot()
local f = w:FirstFailure()
print("boot failure:", f and (f.file .. " " .. f.message) or "none")
local GF, env = w.core.GF, w.env

local function Fresh()
  env.MSUF_DB = { general = {}, gf_raid = { enabled = false } }
  GF.InvalidateConfCache()
  GF.EnsureDB()                      -- stamps GRID_CENTER_V1 + positionMigrationCount
  return env.MSUF_DB.gf_raid
end

local a = Fresh()
print("stamp:", a.positionMode, a.offsetX, a.offsetY, "count", a.positionMigrationCount)
GF.EnsureStableGridPosition("raid", nil, a)            -- shown first
a.width, a.height = 120, 48                             -- then resized
print("A converted before resize ->", a.offsetX, a.offsetY, a.positionMode)

local b = Fresh()
b.width, b.height = 120, 48                             -- resized while still legacy
GF.EnsureStableGridPosition("raid", nil, b)            -- first shown afterwards
print("B converted after resize  ->", b.offsetX, b.offsetY, b.positionMode)
print("expected: identical saved anchor offsets (the stamp's delta undone exactly)")

assert(a.offsetX == b.offsetX and a.offsetY == b.offsetY, "migration used edited size instead of stamped delta")
