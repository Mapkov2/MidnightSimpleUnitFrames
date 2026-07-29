-- Group preview name parity: the live group spec always compiles
-- text.anchorToBars = true, so the name renders as a LEFT/RIGHT span across the
-- health bar (LayoutBarAnchoredName), not as a TOPLEFT box on the frame like
-- the unit-frame path. The preview mirrored the unit-frame layout and drew the
-- name roughly half a frame height too high. This pins both sides of that
-- contract plus the handle-drag pieces that depend on the span.
local function Read(path)
    local file = assert(io.open(path, "rb"), "missing file: " .. path)
    local source = file:read("*a")
    file:close()
    -- The editor saves CRLF; normalize so multi-line patterns match locally too.
    return (source:gsub("\r\n", "\n"))
end

local render = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Render.lua")
local handles = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Handles.lua")
local layout = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Text_Layout.lua")
local groupConfig = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Config.lua")

-- Premise: group frames are the only bar-anchored text scope.
assert(groupConfig:find("anchorToBars = true", 1, true),
    "group specs no longer compile anchorToBars = true")

-- Live side: the span formula the preview mirrors.
assert(layout:find('LayoutTextSpan(fs, health, 3 + x, -3 + x, y, "CENTER")', 1, true),
    "live bar-anchored CENTER name formula changed")
assert(layout:find('LayoutTextSpan(fs, health, 3 + x, -3 + x, y, "RIGHT")', 1, true),
    "live bar-anchored RIGHT name formula changed")
assert(layout:find('LayoutTextSpan(fs, health, 3 + x, -3, y, "LEFT")', 1, true),
    "live bar-anchored LEFT name formula changed")
assert(layout:find('fs:SetPoint("LEFT", relativeTo, "LEFT", leftX, y)', 1, true)
    and layout:find('fs:SetPoint("RIGHT", relativeTo, "RIGHT", rightX, y)', 1, true),
    "live LayoutTextSpan no longer anchors LEFT+RIGHT")
assert(layout:find("local health = text and text.nameAnchorToFrame == true and frame or BarTextHealthAnchor(frame)", 1, true),
    "live name anchor frame resolution changed")

-- Preview side: same span, anchored to the mock health bar.
assert(render:find("local function LayoutPreviewSpan(fs, relativeTo, leftX, rightX, y, justify)", 1, true),
    "preview span helper missing")
assert(render:find('fs:SetPoint("LEFT", relativeTo, "LEFT", leftX or 0, y or 0)', 1, true)
    and render:find('fs:SetPoint("RIGHT", relativeTo, "RIGHT", rightX or 0, y or 0)', 1, true),
    "preview span helper no longer anchors LEFT+RIGHT")
assert(render:find("if runtimeText.anchorToBars == true then", 1, true),
    "preview no longer branches on the live anchorToBars flag")
assert(render:find("local nameRef = (runtimeText.nameAnchorToFrame ~= true and mock._health) or mock", 1, true),
    "preview name no longer anchors to the mock health bar")
assert(render:find("local pad3 = ScaleValue(3, previewScale, 1)", 1, true),
    "preview name padding no longer matches the live 3px span inset")
assert(render:find("mock._nameFS:SetWidth(0)", 1, true),
    "preview name width must be cleared so the span defines it (live parity)")
assert(render:find("LayoutPreviewSpan(mock._nameFS, nameRef, pad3 + nox, -pad3 + nox, noy, \"CENTER\")", 1, true),
    "preview CENTER name formula drifted from live")
assert(render:find("LayoutPreviewSpan(mock._nameFS, nameRef, pad3 + nox, -pad3 + nox, noy, \"RIGHT\")", 1, true),
    "preview RIGHT name formula drifted from live")
assert(render:find("LayoutPreviewSpan(mock._nameFS, nameRef, pad3 + nox, -pad3, noy, \"LEFT\")", 1, true),
    "preview LEFT name formula drifted from live")

-- The mock health bar has to keep matching the live hpBar geometry (no inset,
-- power height reserved at the bottom) or the span lands somewhere else.
assert(render:find('mock._health:SetPoint("TOPLEFT", mock, "TOPLEFT", inset, -inset)', 1, true)
    and render:find("local inset = 0", 1, true),
    "mock health bar geometry no longer matches the live hpBar")

-- Handle: grab box fits the drawn string, not the bar-wide span rect.
assert(render:find("H.PlaceHandleAroundRegions(handles.name, mock, { mock._nameFS }, 3, { fitText = true })", 1, true),
    "name grab handle would span the whole health bar")

-- Handle drag: all anchors are restored, and the span is not mirrored.
assert(handles:find("frame:GetNumPoints()", 1, true),
    "text drag capture dropped multi-point support; a span collapses while dragging")
assert(handles:find("if fs and fs._msufPreviewSpan == true then return false end", 1, true),
    "span name drag still mirrors the X delta like the TOPRIGHT fallback")
assert(render:find("fs._msufPreviewSpan = true", 1, true)
    and render:find("fs._msufPreviewSpan = nil", 1, true),
    "preview span marker read by the handle drag is no longer maintained")

-- The TOP* fallback stays for refreshes before the runtime spec exists.
assert(render:find('LayoutPreviewText(mock._nameFS, "TOPLEFT", "TOPLEFT", nox, noy, "LEFT", mock)', 1, true),
    "preview lost the non-bar-anchored name fallback")

print("group preview name bar anchor smoke: ok")
