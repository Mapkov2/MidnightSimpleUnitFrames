-- Executable smoke for the allocation-free exact preview-pan primitive used by
-- Unit, Group, and Class Resources canvas commands.

local addonRoot = arg[1] or "MidnightSimpleUnitFrames_Options"
-- Load the Core diagnostic export used by the Options addon.
local coreRoot = addonRoot:gsub("MidnightSimpleUnitFrames_Options$", "MidnightSimpleUnitFrames")
assert(loadfile(coreRoot .. "/Kernel/MSUF_Boundary.lua"))("MidnightSimpleUnitFrames",
    { ExportPublic = function(name, value) _G[name] = value end })
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
        if self.corruptAfter then
            self.corruptAfter = self.corruptAfter - 1
        end
        if self.corruptAfter == 0 then
            self.corruptAfter = nil
            x = (tonumber(x) or 0) + 1
        end
        return p[1], p[2], p[3], x, y
    end
    function frame:GetNumPoints() return self.point[1] and 1 or 0 end
    return frame
end

local center = {}
helpers.InstallZoomPan(center, { panPrefix = "_testCenter" })
local canvas, mock = {}, Frame()
local box = { canvas = canvas, mock = mock, _mockBaseOffsetX = 5, _mockBaseOffsetY = -3 }
mock:SetPoint("CENTER", canvas, "CENTER", 5, -3)
local textGuide, textHighlight, mockAnchoredHandle = Frame(), Frame(), Frame()
textGuide._msufPreviewPanFollower = true
textHighlight._msufPreviewPanFollower = true
mockAnchoredHandle._msufPreviewPanFollower = true
textGuide:SetPoint("BOTTOMLEFT", canvas, "BOTTOMLEFT", 10, 20)
textHighlight:SetPoint("BOTTOMLEFT", canvas, "BOTTOMLEFT", 8, 18)
mockAnchoredHandle:SetPoint("CENTER", mock, "CENTER", 0, 0)
box.handles = { textGuide, mockAnchoredHandle }
box._msufMenuTextFocusFrame = textHighlight

local ok, beforeX, beforeY, afterX, afterY = center.NudgePan(box, 7, -4)
assert(ok and beforeX == 0 and beforeY == 0 and afterX == 7 and afterY == -4, "center pan result")
local _, relative, _, x, y = mock:GetPoint(1)
assert(relative == canvas and x == 12 and y == -7, "center pan physical readback")
local _, guideRelative, _, guideX, guideY = textGuide:GetPoint(1)
assert(guideRelative == canvas and guideX == 17 and guideY == 16,
    "absolute text Guide did not follow the panned Preview")
local _, focusRelative, _, focusX, focusY = textHighlight:GetPoint(1)
assert(focusRelative == canvas and focusX == 15 and focusY == 14,
    "text-focus highlight did not follow the panned Preview")
local _, mockRelative, _, mockHandleX, mockHandleY = mockAnchoredHandle:GetPoint(1)
assert(mockRelative == mock and mockHandleX == 0 and mockHandleY == 0,
    "mock-anchored element handle was shifted twice")

mock.corruptAfter = 2
local failed, reason = center.NudgePan(box, 2, 3)
assert(failed == false and reason == "pan-readback-mismatch", "readback mismatch must fail")
assert(box._zoomPanX == 7 and box._zoomPanY == -4, "failed center pan must restore logical offsets")
_, relative, _, x, y = mock:GetPoint(1)
assert(relative == canvas and x == 12 and y == -7, "failed center pan must restore physical point")
_, guideRelative, _, guideX, guideY = textGuide:GetPoint(1)
assert(guideRelative == canvas and guideX == 17 and guideY == 16,
    "failed pan did not roll the text Guide back with the Preview")

local calls = 0
local originalApply, errorReports = center.ApplyPan, {}
local function FailPanOnce(target)
    center.ApplyPan = originalApply
    error("intentional pan write failure")
end
center.ApplyPan = FailPanOnce
_G.geterrorhandler = function()
    return function(message)
        assert(box._zoomPanX == 7 and box._zoomPanY == -4, "error handler observed unrestored pan")
        local _, _, _, px, py = mock:GetPoint(1)
        assert(px == 12 and py == -7, "error handler observed unrestored physical point")
        errorReports[#errorReports + 1] = message
    end
end
local caught, failure = pcall(center.NudgePan, box, 2, 3)
assert(not caught and tostring(failure):find("intentional pan write failure", 1, true), "pan exception was hidden")
assert(box._zoomPanX == 7 and box._zoomPanY == -4 and #errorReports == 0, "failed write committed logical pan")

local command = helpers.BuildPanCommand(box, center, function(dx, dy)
    calls = calls + 1
    return center.NudgePan(box, dx, dy)
end, { previewSurface = "unit", previewUnitKey = "player" })
assert(command and command.kind == "button" and command.interaction == "preview.canvas.pan", "canvas command metadata")
assert(command.set({ dx = -2, dy = 5 }) == true, "table delta command")
assert(command.set("3,-1") == true, "string delta command")
assert(calls == 2 and box._zoomPanX == 8 and box._zoomPanY == 0, "canvas command exact deltas")
assert(command.set(nil) == false, "missing delta must fail closed")

local cursorX, cursorY = 100, 50
_G.GetCursorPosition = function() return cursorX, cursorY end
_G.IsControlKeyDown = function() return false end
_G.IsMouseButtonDown = function() return true end
_G.UIParent = { GetEffectiveScale = function() return 1 end }
local surface = { scripts = {} }
function surface:SetScript(kind, fn) self.scripts[kind] = fn end
assert(center.Start(surface, box, "LeftButton") == false,
    "plain left drag must stay disabled for element handles")
assert(center.Start(surface, box, "LeftButton", true) == true,
    "plain left drag did not start from preview background")
cursorX, cursorY = 112, 44
surface.scripts.OnUpdate(surface)
assert(box._zoomPanX == 20 and box._zoomPanY == -6,
    "background left drag did not pan the preview canvas")
_, guideRelative, _, guideX, guideY = textGuide:GetPoint(1)
assert(guideRelative == canvas and guideX == 30 and guideY == 14,
    "background drag left the text Guide hit region at its old location")
center.Stop(surface)
assert(surface.scripts.OnUpdate == nil, "background pan did not release its OnUpdate")
assert(center.Start(surface, box, "RightButton") == true,
    "right-button Preview pan did not start")
cursorX, cursorY = 107, 52
surface.scripts.OnUpdate(surface)
assert(box._zoomPanX == 15 and box._zoomPanY == 2,
    "right-button drag did not pan the Preview canvas")
_, guideRelative, _, guideX, guideY = textGuide:GetPoint(1)
assert(guideRelative == canvas and guideX == 25 and guideY == 22,
    "right-button drag left the text Guide hit region at its old location")
center.Stop(surface)

local topLeft = {}
helpers.InstallZoomPan(topLeft, { panMode = "topLeft", panPrefix = "_testTopLeft" })
local stage, groupMock = {}, Frame()
local group = { _stage = stage, _mock = groupMock, _mockBaseOffsetX = 20, _mockBaseOffsetY = -10 }
groupMock:SetPoint("TOPLEFT", stage, "TOPLEFT", 20, -10)
local stageTextGuide = Frame()
stageTextGuide._msufPreviewPanFollower = true
stageTextGuide:SetPoint("BOTTOMLEFT", stage, "BOTTOMLEFT", 30, 40)
group.handles = { stageTextGuide }
assert(topLeft.NudgePan(group, -6, 9) == true, "top-left pan")
local point, groupRelative, relativePoint, groupX, groupY = groupMock:GetPoint(1)
assert(point == "TOPLEFT" and groupRelative == stage and relativePoint == "TOPLEFT", "top-left anchors")
assert(groupX == 14 and groupY == -1, "top-left physical readback")
local _, stageRelative, _, stageGuideX, stageGuideY = stageTextGuide:GetPoint(1)
assert(stageRelative == stage and stageGuideX == 24 and stageGuideY == 49,
    "top-left Preview pan left its absolute text Guide behind")

print("PREVIEW EXACT PAN SMOKE PASS - center/text-follow/table/string/rollback/top-left")
