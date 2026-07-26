-- Contract: the legal unit-frame size range is ONE shared table
-- (State/MSUF_Defaults.lua -> MSUF_UnitFrameSizeBounds). The EM2 unit popup
-- clamps every conf.width/height write against it, and the options unit
-- preview clamps its mock body against the same table. If either side drifts,
-- tall/narrow frames render a mock rectangle that disagrees with the live
-- frame - frame-relative offsets (raid marker, status icons) then land inside
-- the live frame but outside the mock, or vice versa.

local root = (arg and arg[1]) or "."

local function ReadSource(rel)
    local path = root .. "/" .. rel
    local file = assert(io.open(path, "rb"), "cannot open " .. path)
    local source = file:read("*a")
    file:close()
    return (source:gsub("\r\n", "\n"))
end

-- 1) canonical bounds live in State and are exported
local defaults = ReadSource("MidnightSimpleUnitFrames/State/MSUF_Defaults.lua")
local dMinW, dMaxW, dMinH, dMaxH = defaults:match(
    "MSUF_UNIT_FRAME_SIZE_BOUNDS%s*=%s*{%s*minW%s*=%s*(%d+),%s*maxW%s*=%s*(%d+),%s*minH%s*=%s*(%d+),%s*maxH%s*=%s*(%d+)%s*}")
assert(dMinW, "State/MSUF_Defaults.lua no longer defines MSUF_UNIT_FRAME_SIZE_BOUNDS as a literal table")
assert(defaults:find('ExportPublic("MSUF_UnitFrameSizeBounds", MSUF_UNIT_FRAME_SIZE_BOUNDS)', 1, true),
    "size-bounds table is not exported as MSUF_UnitFrameSizeBounds")

-- 2) EM2 popup binds the shared table and clamps every size write against it
local popups = ReadSource("MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_Popups.lua")
local pMinW, pMaxW, pMinH, pMaxH = popups:match(
    "local SizeBounds%s*=%s*_G%.MSUF_UnitFrameSizeBounds%s*or%s*{%s*minW%s*=%s*(%d+),%s*maxW%s*=%s*(%d+),%s*minH%s*=%s*(%d+),%s*maxH%s*=%s*(%d+)%s*}")
assert(pMinW, "EM2 popup no longer binds SizeBounds to MSUF_UnitFrameSizeBounds with a literal fallback")
for _, pin in ipairs({
    "conf.width=floor(max(SizeBounds.minW,min(SizeBounds.maxW,w))+0.5)",
    "conf.height=floor(max(SizeBounds.minH,min(SizeBounds.maxH,h))+0.5)",
    "dst.width = floor(max(SizeBounds.minW, min(SizeBounds.maxW, tonumber(src.width) or 250)) + 0.5)",
    "dst.height = floor(max(SizeBounds.minH, min(SizeBounds.maxH, tonumber(src.height) or 40)) + 0.5)",
    "floor(max(SizeBounds.minH, min(SizeBounds.maxH, w / ratio)) + 0.5)",
    "floor(max(SizeBounds.minW, min(SizeBounds.maxW, h * ratio)) + 0.5)",
}) do
    assert(popups:find(pin, 1, true), "EM2 popup size write no longer uses the shared bounds: " .. pin)
end

-- 3) the unit preview mock clamps against the same shared export
local render = ReadSource("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Render.lua")
assert(render:find("w, h = R.ClampUnitPreviewSize(w, h)", 1, true),
    "unit preview Refresh no longer clamps the mock via R.ClampUnitPreviewSize")
assert(not render:find("elseif w > 520 then w = 520", 1, true)
    and not render:find("elseif h > 140 then h = 140", 1, true),
    "unit preview still carries the legacy landscape-only mock clamp")
assert(render:find("_G.MSUF_UnitFrameSizeBounds", 1, true),
    "preview clamp no longer reads the shared MSUF_UnitFrameSizeBounds export")
local rMinW = render:match("tonumber%(b and b%.minW%) or (%d+)")
local rMaxW = render:match("tonumber%(b and b%.maxW%) or (%d+)")
local rMinH = render:match("tonumber%(b and b%.minH%) or (%d+)")
local rMaxH = render:match("tonumber%(b and b%.maxH%) or (%d+)")
assert(rMinW and rMaxW and rMinH and rMaxH, "preview clamp fallback literals are missing")

-- 4) definition and both fallback sites agree exactly
local function AssertSame(label, a, b)
    assert(tonumber(a) == tonumber(b),
        label .. " drifted: " .. tostring(a) .. " vs " .. tostring(b))
end
AssertSame("minW popup fallback", dMinW, pMinW)
AssertSame("maxW popup fallback", dMaxW, pMaxW)
AssertSame("minH popup fallback", dMinH, pMinH)
AssertSame("maxH popup fallback", dMaxH, pMaxH)
AssertSame("minW preview fallback", dMinW, rMinW)
AssertSame("maxW preview fallback", dMaxW, rMaxW)
AssertSame("minH preview fallback", dMinH, rMinH)
AssertSame("maxH preview fallback", dMaxH, rMaxH)

io.write("unit_preview_size_parity_smoke: ok\n")
