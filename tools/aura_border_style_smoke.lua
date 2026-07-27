-- Contract smoke for the shared aura icon border-style catalog and renderer.
--
-- Covers:
--   * MSUF.BorderStyles catalog: normalization, LSM resolution, edge sizing.
--   * The 8-piece edge geometry and the Blizzard backdrop UVs it reproduces.
--   * The Auras3 menu model's per-scope icon-style opt-out (raid fans out to
--     mythicraid, "shared" is not a frame scope).
--   * The zero-combat-cost contract: neither the renderer nor the Auras3 icon
--     style may touch OnUpdate/event surfaces, and the compiled style must be
--     memoized per runtime-config generation.
_G = _G or _ENV

local failures = 0
local function check(ok, message)
    if not ok then
        failures = failures + 1
        print("FAIL: " .. tostring(message))
    end
end
local function near(a, b, tolerance)
    return type(a) == "number" and math.abs(a - b) <= (tolerance or 1e-6)
end

local function read(path)
    local handle = io.open(path, "rb")
    if not handle then return nil end
    local body = handle:read("*a")
    handle:close()
    -- The editor writes CRLF; normalize so "\n" patterns behave like CI.
    return (body:gsub("\r\n", "\n"))
end

local ADDON = "MidnightSimpleUnitFrames/"
if not read(ADDON .. "MidnightSimpleUnitFrames.toc") then ADDON = "" end
local OPTIONS = ADDON ~= "" and "MidnightSimpleUnitFrames_Options/"
    or "../MidnightSimpleUnitFrames_Options/"

-------------------------------------------------------------------------------
--  Harness
-------------------------------------------------------------------------------

local textures = {}
local function NewTexture(layer, subLayer)
    local tex = { layer = layer, subLayer = subLayer, points = {}, shown = false }
    function tex:SetTexture(path, wrapH, wrapV)
        self.texture = path
        self.wrapH, self.wrapV = wrapH, wrapV
    end
    function tex:SetTexCoord(...) self.coords = { ... } end
    function tex:ClearAllPoints() self.points = {} end
    function tex:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function tex:SetSize(w, h) self.w, self.h = w, h end
    function tex:SetWidth(w) self.w = w end
    function tex:SetHeight(h) self.h = h end
    function tex:SetVertexColor(r, g, b, a) self.color = { r, g, b, a } end
    function tex:Show() self.shown = true end
    function tex:Hide() self.shown = false end
    textures[#textures + 1] = tex
    return tex
end

local owner = {}
function owner:CreateTexture(_, layer, _, subLayer) return NewTexture(layer, subLayer) end

local lsmBorders = {
    ["Lightspark Border"] = "Interface\\AddOns\\Other\\lightspark-border",
    ["Blizzard Tooltip"] = "Interface\\Tooltips\\UI-Tooltip-Border",
    ["None"] = "",
}
local LSM = {
    HashTable = function(_, kind) return kind == "border" and lsmBorders or nil end,
    Fetch = function(_, kind, name) return kind == "border" and lsmBorders[name] or nil end,
}

local MSUF = { LSM = LSM }
MSUF.ExportPublic = function(name, value) _G[name] = value; return value end
_G.MSUF_NS = MSUF
_G.MSUF = MSUF
_G.LibStub = function() return LSM end

local chunk = assert(loadstring(assert(read(ADDON .. "Runtime/MSUF_BorderStyles.lua"),
    "Runtime/MSUF_BorderStyles.lua not found"), "@MSUF_BorderStyles.lua"))
chunk("MidnightSimpleUnitFrames", MSUF)

local B = MSUF.BorderStyles
check(type(B) == "table", "MSUF.BorderStyles must be exported")

-------------------------------------------------------------------------------
--  Catalog
-------------------------------------------------------------------------------

check(B.Normalize(nil) == "SOLID", "missing style normalizes to SOLID")
check(B.Normalize("") == "SOLID", "empty style normalizes to SOLID")
check(B.Normalize("NOPE") == "SOLID", "unknown style normalizes to SOLID")
check(B.Normalize("LSM:Not Installed") == "SOLID", "unresolvable LSM style normalizes to SOLID")
check(B.Normalize("GLOW") == "GLOW", "built-in style survives normalization")
check(B.Normalize("LSM:Lightspark Border") == "LSM:Lightspark Border", "registered LSM style survives normalization")

check(B.Resolve("SOLID") == nil, "SOLID must resolve to no texture (flat quad path)")
check(B.Resolve("GLOW") == "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Borders\\msuf_aura_border_glow.tga",
    "GLOW resolves to the bundled glow edge file")
check(B.Resolve("SHADOW") == "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Borders\\msuf_aura_border_inner_shadow.tga",
    "SHADOW resolves to the bundled inner-shadow edge file")
check(B.Resolve("LSM:Lightspark Border") == lsmBorders["Lightspark Border"], "LSM styles resolve through LibSharedMedia")

-- Placement decides draw layer and inset: only Shadow shades the icon itself.
check(B.Placement("SHADOW") == "inner", "Shadow must be an inner style (shading, not a frame)")
check(B.Placement("GLOW") == "outer", "Glow frames the icon")
check(B.Placement("SOLID") == "outer", "Solid frames the icon")
check(B.Placement("LSM:Lightspark Border") == "outer", "LSM borders frame the icon")

local list = B.List()
check(type(list) == "table" and #list >= 7, "catalog lists built-ins plus LSM borders")
check(list[1] and list[1].value == "SOLID", "SOLID is the first (default) entry")
local seen = {}
for _, item in ipairs(list) do
    check(not seen[item.value], "catalog values are unique: " .. tostring(item.value))
    seen[item.value] = true
    check(type(item.text) == "string" and item.text ~= "", "catalog entries carry display text")
end
check(seen["LSM:Lightspark Border"] == true, "LSM borders are offered under the LSM: prefix")
check(seen["LSM:Blizzard Tooltip"] == nil, "LSM entries duplicating a built-in are skipped")
check(seen["LSM:None"] == nil, "the LSM None border is skipped")

-- Our own art ramps smoothly and stays readable at small sizes; Blizzard's
-- carved frames need a floor or the corner pieces smear.
check(B.EdgeSize("GLOW", 1) == 3, "GLOW edge scales tightly with thickness")
check(B.EdgeSize("GLOW", 4) == 12, "GLOW edge scales linearly")
check(B.EdgeSize("SHADOW", 4) == 8, "SHADOW shades gently (inner band)")
check(B.EdgeSize("DIALOG", 1) == 10, "DIALOG edge is floored")
check(B.EdgeSize("DIALOG", 8) == 32, "DIALOG edge scales past its floor")
check(B.EdgeSize("LSM:Lightspark Border", 1) == 8, "LSM borders use the default floor")

-------------------------------------------------------------------------------
--  8-piece geometry + Blizzard backdrop UVs
-------------------------------------------------------------------------------

local pieces = B.Create(owner, "BORDER", -1, "tex")
check(#pieces == 8, "a border is exactly eight textures")
for i = 1, 8 do
    check(pieces[i].layer == "BORDER" and pieces[i].subLayer == -1, "pieces honor the caller's draw layer")
    check(pieces[i].texture == "tex", "pieces take the requested texture")
end
for i = 1, 4 do
    check(pieces[i].wrapH == nil and pieces[i].wrapV == nil,
        "corner pieces stay clamped instead of enabling unnecessary tiling")
end
for i = 5, 8 do
    check(pieces[i].wrapH == "REPEAT" and pieces[i].wrapV == "REPEAT",
        "edge pieces enable REPEAT wrap for UVs above 1")
end
B.SetTexture(pieces, "tex2")
for i = 1, 4 do
    check(pieces[i].texture == "tex2" and pieces[i].wrapH == nil and pieces[i].wrapV == nil,
        "SetTexture keeps corner pieces clamped")
end
for i = 5, 8 do
    check(pieces[i].texture == "tex2" and pieces[i].wrapH == "REPEAT" and pieces[i].wrapV == "REPEAT",
        "SetTexture preserves edge REPEAT wrap")
end

local EDGE, SIZE = 8, 32
B.Apply(pieces, owner, EDGE, SIZE, SIZE, 0.25, 0.5, 0.75, 0.5)
for i = 1, 8 do
    check(pieces[i].shown == true, "Apply shows every piece")
    local c = pieces[i].color
    check(c and near(c[1], 0.25) and near(c[4], 0.5), "Apply tints every piece")
end
for i = 1, 4 do
    check(pieces[i].w == EDGE and pieces[i].h == EDGE, "corners are edge x edge")
end
-- Corners anchor half an edge outside the target, so the band straddles it.
local topLeft = pieces[1].points[1]
check(topLeft[1] == "TOPLEFT" and topLeft[3] == "TOPLEFT", "top-left corner anchors to the target corner")
check(near(topLeft[4], -EDGE / 2) and near(topLeft[5], EDGE / 2), "the band straddles the target edge")
check(pieces[5].h == EDGE and pieces[6].h == EDGE, "top/bottom edges are edge tall")
check(pieces[7].w == EDGE and pieces[8].w == EDGE, "left/right edges are edge wide")

-- Blizzard_SharedXML/Backdrop.lua: coordStart = 0.0625, and edge pieces repeat
-- across their run at (outer / edgeSize) - 2 - coordStart.
local COORD_START = 0.0625
local expectedRepeat = ((SIZE + EDGE) / EDGE) - 2 - COORD_START
local topCoords = pieces[5].coords
check(#topCoords == 8, "edge pieces use the 8-argument SetTexCoord form")
check(near(topCoords[1], 0.2578125) and near(topCoords[3], 0.3671875), "top edge samples the third tile")
check(near(topCoords[2], expectedRepeat) and near(topCoords[6], COORD_START),
    "top edge repeat coords match the backdrop formula")
local leftCoords = pieces[7].coords
check(near(leftCoords[1], 0.0078125) and near(leftCoords[5], 0.1171875), "left edge samples the first tile")
check(near(leftCoords[4], expectedRepeat), "left edge repeats along its run")
local cornerCoords = pieces[1].coords
check(near(cornerCoords[1], 0.5078125) and near(cornerCoords[2], COORD_START),
    "corners sample the inset middle of their tile")

-- Small target + wide band: the corners meet across the whole ring, so the
-- degenerate edge strips must hide instead of lingering as zero-area quads --
-- and they must come back when the run turns positive again.
B.Apply(pieces, owner, 24, 10, 10, 1, 1, 1, 1)
for i = 1, 4 do check(pieces[i].shown == true, "corner hidden in degenerate layout") end
for i = 5, 8 do check(pieces[i].shown == false, "degenerate strip must hide") end
B.Apply(pieces, owner, EDGE, SIZE, SIZE, 0.25, 0.5, 0.75, 0.5)
for i = 1, 8 do check(pieces[i].shown == true, "strips must return once the run is positive") end

B.Hide(pieces)
for i = 1, 8 do check(pieces[i].shown == false, "Hide hides every piece") end

-- Re-applying must not allocate: a border is built once per button and then
-- only re-anchored, so repeated Apply calls may never create new regions.
local textureCountBefore = #textures
for _ = 1, 50 do
    B.Apply(pieces, owner, EDGE, SIZE, SIZE, 1, 1, 1, 1)
    B.Apply(pieces, owner, EDGE * 2, SIZE, SIZE, 0, 0, 0, 0.5, EDGE)
end
check(#textures == textureCountBefore, "Apply must never create regions (creation belongs to Create)")

-------------------------------------------------------------------------------
--  Per-scope opt-out (menu model)
-------------------------------------------------------------------------------

local shared = {}
local Model = {}
Model.EnsureDB = function() return {}, shared end
do
    local source = assert(read(ADDON .. "Auras3/MSUF_Auras3_Menu_Model.lua"), "menu model not found")
    -- Lift the scope helpers out of the model verbatim so the smoke pins the
    -- shipped logic rather than a copy of it.
    local first = source:find("local ICON_STYLE_SCOPE_KEYS", 1, true)
    local last = source:find("    return changed\nend", first or 1, true)
    local block = first and last and source:sub(first, last + #"    return changed\nend") or nil
    check(block ~= nil, "menu model still defines the icon-style scope helpers")
    if block then
        local env = { Model = Model, type = type, next = next, MSUF = MSUF }
        local fn = assert(loadstring(block, "@icon_style_scopes"))
        setfenv(fn, env)
        fn()
    end
end

check(Model.IconStyleScopeEnabled("player") == true, "scopes are styled by default")
check(Model.IconStyleScopeEnabled("shared") == true, "shared is not a frame scope and stays enabled")
check(Model.SetIconStyleScopeEnabled("shared", false) == false, "shared cannot be opted out")
check(shared.styleScopeDisabled == nil, "no storage is created until a scope opts out")

check(Model.SetIconStyleScopeEnabled("player", false) == true, "opting a scope out reports a change")
check(Model.IconStyleScopeEnabled("player") == false, "an opted-out scope reads back disabled")
check(Model.IconStyleScopeEnabled("target") == true, "opting one scope out leaves the others alone")
check(Model.SetIconStyleScopeEnabled("player", false) == false, "re-writing the same value reports no change")

check(Model.SetIconStyleScopeEnabled("raid", false) == true, "raid opts out")
check(shared.styleScopeDisabled.raid == true and shared.styleScopeDisabled.mythicraid == true,
    "the Raid editor fans out to mythicraid")
check(Model.SetIconStyleScopeEnabled("raid", true) == true, "raid opts back in")
check(shared.styleScopeDisabled.raid == nil and shared.styleScopeDisabled.mythicraid == nil,
    "opting back in clears both raid keys")

check(Model.SetIconStyleScopeEnabled("player", true) == true, "the last scope opts back in")
check(shared.styleScopeDisabled == nil, "storage is dropped once no scope opts out")

-------------------------------------------------------------------------------
--  Zero combat cost
-------------------------------------------------------------------------------

local borderSource = assert(read(ADDON .. "Runtime/MSUF_BorderStyles.lua"))
for _, forbidden in ipairs({ "OnUpdate", "SetScript", "RegisterEvent", "C_Timer", "After%(" }) do
    check(borderSource:find(forbidden) == nil,
        "the border renderer must stay a cold-path drawing helper (found " .. forbidden .. ")")
end

local auraSource = assert(read(ADDON .. "Auras3/MSUF_Auras3_UnitFrames.lua"))
check(auraSource:find("_iconStyleCompiled and _iconStyleCompiledGen == gen", 1, true) ~= nil,
    "the compiled icon style stays memoized per runtime-config generation")
check(auraSource:find("_iconStyleOffScopesGen ~= gen", 1, true) ~= nil,
    "the per-scope opt-out lookup stays memoized per runtime-config generation")
-- Both renderers may only be reached from cold paths: one definition, the
-- initializeFrame call, and the shared preview export (edit mode / menu mocks).
for _, name in ipairs({ "ApplyIconStyleShadow", "ApplyIconStyleBorder" }) do
    local uses = 0
    for _ in auraSource:gmatch(name .. "%(") do uses = uses + 1 end
    check(uses == 3, name .. " must have exactly one definition, the initializeFrame call, and the preview export (found " .. uses .. ")")
end
check(auraSource:find("function A3.ApplyIconStylePreview(button, style, size)", 1, true) ~= nil,
    "the preview surfaces lost their shared icon-style stamp export")
check(auraSource:find("function A3.IconStylePreviewForScope(scope)", 1, true) ~= nil,
    "the preview surfaces lost the scope-resolved icon-style accessor")
check(auraSource:find("style.signature", 1, true) ~= nil,
    "the icon style still contributes to the lane layout signature")

local menuSource = assert(read(OPTIONS .. "Shell/Menu2/Pages/MSUF_Menu2_Auras.lua"))
local iconStyleStart = assert(menuSource:find("local function ApplyIconStyleRuntime", 1, true))
local iconStyleEnd = assert(menuSource:find("local ICON_STYLE_BORDER_DEFAULT", iconStyleStart, true))
local iconStyleBlock = menuSource:sub(iconStyleStart, iconStyleEnd)
check(iconStyleBlock:find('RequestAuraRuntime("shared"', 1, true) ~= nil
    and iconStyleBlock:find("runtime.RequestApply", 1, true) == nil
    and iconStyleBlock:find("ApplyUnit(ctx", 1, true) == nil,
    "icon-style changes must use exactly one authoritative shared Aura apply")
check(iconStyleBlock:find("if slider and slider._msuf2SliderActive then", 1, true) ~= nil
    and iconStyleBlock:find("C_Timer.NewTimer(M.AURA_ICON_STYLE_APPLY_DELAY, FlushIconStyleApply)", 1, true) ~= nil
    and iconStyleBlock:find("if iconStyleReleaseScheduled then return end", 1, true) ~= nil
    and iconStyleBlock:find("C_Timer.NewTimer(0, function()", 1, true) ~= nil
    and iconStyleBlock:find('slider:HookScript("OnMouseUp", ScheduleIconStyleReleaseApply)', 1, true) ~= nil,
    "icon-style sliders lost preview-only drag plus bounded release/debounce apply")
check(iconStyleBlock:find("OnUpdate", 1, true) == nil
    and iconStyleBlock:find("RegisterEvent", 1, true) == nil,
    "icon-style slider batching added polling or event work")

if failures > 0 then
    print(("aura_border_style_smoke: %d failure(s)"):format(failures))
    os.exit(1)
end
print("PASS aura border style smoke")
