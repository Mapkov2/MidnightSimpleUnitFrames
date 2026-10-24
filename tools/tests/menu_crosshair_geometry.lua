local root = assert(arg[1])
local Slice = assert(loadfile(root .. "/.github/scripts/msuf_source_slice.lua"))()
local path = arg[2] or root .. "/MidnightSimpleUnitFrames/Features/Gameplay/MSUF_Feature_GameplayRuntime.lua"
local source = Slice.Read(path)
local helpers = {}
local fn = Slice.Function(source, "function GameplayHelpers.PaintCrosshairGeometry", path)
local env = { GameplayHelpers = helpers, Clamp = function(v, lo, hi) return math.max(lo, math.min(hi, v)) end }
local chunk = assert(loadstring(fn)); setfenv(chunk, env); chunk()
local calls = 0
local function Texture()
    return { SetSize = function(self, w, h) self.w, self.h = w, h; calls = calls + 1 end }
end
for _, sample in ipairs({{40,2,40,2}, {20,1,20,1}, {80,10,80,10}, {999,-1,80,1}}) do
    local frame = { horiz = Texture(), vert = Texture() }
    local before = calls
    helpers.PaintCrosshairGeometry(frame, sample[1], sample[2])
    assert(frame.horiz.w == sample[3] and frame.horiz.h == sample[4] and frame.vert.w == sample[4] and frame.vert.h == sample[3], "geometry differs")
    assert(calls-before == 2, "runtime geometry native-call budget grew")
end
local preview = Slice.Read(root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedGameplay.lua")
assert(preview:find("MSUF.Gameplay.PaintCrosshairGeometry(preview", 1, true), "preview does not use runtime painter")
assert(source:find("GameplayHelpers.PaintCrosshairGeometry(crosshairFrame, size, thickness)", 1, true), "runtime bypasses shared painter")
assert(not preview:find("size * 0.28", 1, true), "preview retains four-arm geometry")
print("crosshair: preview/runtime 2 continuous lines; 2 native geometry calls")

if arg[3] then
    local function PreviewWrites(text, file)
        local writes = 0
        local function Region()
            return { ClearAllPoints = function() writes = writes + 1 end,
                SetPoint = function() writes = writes + 1 end,
                SetSize = function() writes = writes + 1 end,
                SetVertexColor = function() end }
        end
        local g = { crosshairSize = 40, crosshairThickness = 2, enableCombatCrosshair = true }
        local scope = setmetatable({ Gameplay = function() return g end,
            CurrentMeleeSpellID = function() return 0 end, SpellName = function() end,
            floor = math.floor, bars = {Region(), Region(), Region(), Region()},
            preview = { GetWidth = function() return 260 end, GetHeight = function() return 120 end },
            MSUF = { Gameplay = helpers } }, { __index = _G })
        scope.preview.horiz, scope.preview.vert = scope.bars[1], scope.bars[2]
        local body = Slice.Function(text, "local previewRefresh = function", file)
        local run = assert(loadstring(body .. "\nreturn previewRefresh")); setfenv(run, scope)
        run()()
        return writes
    end
    local before = PreviewWrites(Slice.Read(arg[3]), arg[3])
    local after = PreviewWrites(preview, "AdvancedGameplay")
    assert(before == 12 and after == 2, "preview geometry write budget changed")
    print("preview geometry writes: " .. before .. " -> " .. after)
end
