-- Dense parity against frozen formulas, including typed/stored fractional positions.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local ns = { ExportPublic = function(name, value) _G[name] = value return value end }
local base = root .. "/MidnightSimpleUnitFrames/Shell/EditMode/"
assert(loadfile(base .. "MSUF_EditMode_Geometry.lua"))("MidnightSimpleUnitFrames", ns)
MSUF_RoundOffset = ns.Geometry.RoundOffset
assert(loadfile(base .. "MSUF_EditMode_Core.lua"))("MidnightSimpleUnitFrames", ns)
local Legacy = assert(loadfile(root .. "/tools/fixtures/editmode_geometry_legacy.lua"))()
local Geometry, Util = ns.Geometry, MSUF_EM2.Util
local checks = 0
local function Same(a, b, label)
    assert(a == b or (a ~= a and b ~= b), label .. ": " .. tostring(a) .. " ~= " .. tostring(b))
    checks = checks + 1
end
local function Results(old, new, frame, count, label)
    local a, b = { old(frame) }, { new(frame) }
    for i = 1, count do Same(a[i], b[i], label .. " field " .. i) end
end
local pairsOfRects = {
    { Legacy.VisibleRect, Geometry.VisibleRect, 4, "visible" },
    { Legacy.ExternalRect, Geometry.ExternalRect, 4, "external" },
    { Legacy.EditRect, Geometry.EditRect, 6, "edit" },
    { Legacy.PopupRect, Geometry.PopupRect, 4, "popup" },
    { Legacy.Edges, Geometry.Edges, 6, "snap" },
    { Legacy.InspectorRect, function(frame) return Geometry.Rect(frame, "inspector") end, 5, "inspector" },
}
local frame = { shown = true }
function frame:GetLeft() return self.left end
function frame:GetRight() return self.left + (self.width or 183.5) end
function frame:GetTop() return self.top end
function frame:GetBottom() return self.top - (self.height or 37.5) end
function frame:GetEffectiveScale() return self.scale end
function frame:IsShown() return self.shown end
UIParent = {}
function UIParent:GetEffectiveScale() return self.scale end
function UIParent:GetLeft() return 0 end
function UIParent:GetRight() return self.width end
function UIParent:GetTop() return self.height end
function UIParent:GetBottom() return 0 end
function UIParent:GetWidth() return self.width end
function UIParent:GetHeight() return self.height end

for i = -32768, 32768 do
    local value = i / 8
    Same(Legacy.RoundOffset(value), Geometry.RoundOffset(value), "stored offset")
    Same(Legacy.RoundOptional(value), Geometry.RoundOptional(value), "inspector round")
    Same(Legacy.RoundEven(value), Geometry.RoundEven(value), "drag round")
    Same(Legacy.RoundOffset(tostring(value)), Geometry.RoundOffset(tostring(value)), "typed offset")
end
for _, value in ipairs({ "invalid", "", "1e309", "-1e309", "0.5", "-0.5" }) do
    Same(Legacy.RoundOffset(value), Geometry.RoundOffset(value), "offset string")
    Same(Legacy.RoundOptional(value), Geometry.RoundOptional(value), "optional string")
end
for _, resolution in ipairs({ { 1920, 1080 }, { 2560, 1440 } }) do
    for step = 64, 115 do
        UIParent.scale = step / 100
        UIParent.width, UIParent.height = resolution[1] / UIParent.scale, resolution[2] / UIParent.scale
        for _, ratio in ipairs({ 0.64, 0.85, 1, 1.15, 1.25 }) do
            frame.scale = UIParent.scale * ratio
            for i = -128, 128 do
                local fractional = i / 8
                frame.width = ({ 10, 20, 35, 100, 183.5, 250, 271, 384 })[i % 8 + 1]
                frame.height = ({ 12, 18, 20, 35, 0.5 })[i % 5 + 1]
                for _, edge in ipairs({ -4096, -512, 0, 512, 4096 }) do
                    frame.left = (UIParent.width / 2 + edge + fractional) / ratio
                    frame.top = (UIParent.height / 2 + fractional) / ratio
                    for _, pair in ipairs(pairsOfRects) do
                        Results(pair[1], pair[2], frame, pair[3], pair[4])
                    end
                    Results(Legacy.Util.FramePositionValues, Util.FramePositionValues, frame, 4, "displayed position")
                    local x, y = Legacy.Util.FramePositionValues(frame)
                    for _, delta in ipairs({ -0.500000001, -0.5, -0.499999999, 0, 0.499999999, 0.5, 0.500000001 }) do
                        local a, b, c = Legacy.Util.TranslateFramePosition(frame, fractional, -fractional, tostring(x + delta), tostring(y - delta))
                        local d, e, f = Util.TranslateFramePosition(frame, fractional, -fractional, tostring(x + delta), tostring(y - delta))
                        Same(a, d, "typed X")
                        Same(b, e, "typed Y")
                        Same(c, f, "typed change")
                    end
                end
            end
        end
    end
end
frame.left, frame.top = 23.5, 50.5
for _, shown in ipairs({ true, false }) do
    frame.shown = shown
    for _, scale in ipairs({ 0, -1, 1 }) do
        frame.scale = scale
        for _, pair in ipairs(pairsOfRects) do Results(pair[1], pair[2], frame, pair[3], pair[4]) end
    end
end
print("PASS geometry position parity: " .. checks .. " comparisons, zero drift; scales 0.64-1.15; 1920x1080 and 2560x1440")
