-- Executable smoke for the allocation-free exact preview-pan primitive used by
-- Unit, Group, and Class Resources canvas commands.

local addonRoot = arg[1] or "MidnightSimpleUnitFrames_Options"
local ns = { MSUF2 = { Fallbacks = {} } }
local chunk, err = loadfile(addonRoot .. "/Shell/Menu2/MSUF_Menu2_PreviewHelpers.lua")
assert(chunk, err)
chunk("MidnightSimpleUnitFrames", ns)
local helpers = assert(ns.MSUF2.PreviewHelpers)

local function Frame()
    local frame = { point = {} }
    function frame:ClearAllPoints() self.point = {} end
    function frame:SetPoint(point, relative, relativePoint, x, y)
        self.point = { point, relative, relativePoint, x, y }
    end
    function frame:GetPoint()
        local p = self.point
        local x, y = p[4], p[5]
        if self.corruptOnce then
            self.corruptOnce = nil
            x = (tonumber(x) or 0) + 1
        end
        return p[1], p[2], p[3], x, y
    end
    return frame
end

local center = {}
helpers.InstallZoomPan(center, { panPrefix = "_testCenter" })
local canvas, mock = {}, Frame()
local box = { canvas = canvas, mock = mock, _mockBaseOffsetX = 5, _mockBaseOffsetY = -3 }
mock:SetPoint("CENTER", canvas, "CENTER", 5, -3)

local ok, beforeX, beforeY, afterX, afterY = center.NudgePan(box, 7, -4)
assert(ok and beforeX == 0 and beforeY == 0 and afterX == 7 and afterY == -4, "center pan result")
local _, relative, _, x, y = mock:GetPoint(1)
assert(relative == canvas and x == 12 and y == -7, "center pan physical readback")

mock.corruptOnce = true
local failed, reason = center.NudgePan(box, 2, 3)
assert(failed == false and reason == "pan-readback-mismatch", "readback mismatch must fail")
assert(box._zoomPanX == 7 and box._zoomPanY == -4, "failed center pan must restore logical offsets")
_, relative, _, x, y = mock:GetPoint(1)
assert(relative == canvas and x == 12 and y == -7, "failed center pan must restore physical point")

local calls = 0
local command = helpers.BuildPanCommand(box, center, function(dx, dy)
    calls = calls + 1
    return center.NudgePan(box, dx, dy)
end, { previewSurface = "unit", previewUnitKey = "player" })
assert(command and command.kind == "button" and command.interaction == "preview.canvas.pan", "canvas command metadata")
assert(command.set({ dx = -2, dy = 5 }) == true, "table delta command")
assert(command.set("3,-1") == true, "string delta command")
assert(calls == 2 and box._zoomPanX == 8 and box._zoomPanY == 0, "canvas command exact deltas")
assert(command.set(nil) == false, "missing delta must fail closed")

local topLeft = {}
helpers.InstallZoomPan(topLeft, { panMode = "topLeft", panPrefix = "_testTopLeft" })
local stage, groupMock = {}, Frame()
local group = { _stage = stage, _mock = groupMock, _mockBaseOffsetX = 20, _mockBaseOffsetY = -10 }
groupMock:SetPoint("TOPLEFT", stage, "TOPLEFT", 20, -10)
assert(topLeft.NudgePan(group, -6, 9) == true, "top-left pan")
local point, groupRelative, relativePoint, groupX, groupY = groupMock:GetPoint(1)
assert(point == "TOPLEFT" and groupRelative == stage and relativePoint == "TOPLEFT", "top-left anchors")
assert(groupX == 14 and groupY == -1, "top-left physical readback")

print("PREVIEW EXACT PAN SMOKE PASS - center/table/string/rollback/top-left")
