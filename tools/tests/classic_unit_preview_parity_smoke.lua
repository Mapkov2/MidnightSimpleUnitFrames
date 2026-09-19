-- classic_unit_preview_parity_smoke.lua <repoRoot> <flavor>
--
-- Vanilla, TBC and Mists load Preview/MSUF_Menu2_UnitPreview_Render_Classic.lua
-- and ..._View_Classic.lua in place of the Retail-named unit preview. Those
-- owned copies once lacked features whose controls and runtime every Classic
-- flavor has, so a setting changed and the preview did not follow.
--
-- This smoke boots the flavor's whole shipped core and Options graph through
-- tools/tests/client_world.lua, builds the real unit preview and drives its
-- real Refresh from MSUF_DB, compiled by the flavor's own unit config:
--   * Power gradient on the inline and on a detached power bar;
--   * the Class Resource text layer (bars.classPowerTextLayer);
--   * the boss target marker, its drag handle, footprint and border highlight,
--     only where MSUF.Client.SupportsUnit("boss1") says boss units exist;
--   * unchanged Classic behaviour: the Era legacy Blizzard portrait fallback,
--     the layer popover branch, and no Devourer notch pool.
--
-- Plain Lua 5.1 with the repo root and a Classic flavor as arguments.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg and arg[2], "flavor required (a Classic matrix Suffix)")
assert(rawget(_G, "MSUF_Auras3TestLoader") == nil,
    "classic_unit_preview_parity_smoke boots the real TOC graph; run it with plain Lua 5.1")

local World = assert(loadfile(root .. "/tools/tests/client_world.lua"),
    "classic_unit_preview_parity_smoke: tools/tests/client_world.lua is missing")()

local function Check(condition, message)
    if not condition then error(flavor .. ": " .. message, 2) end
end

local world = World.New(root, flavor)
Check(world.client.isClassic == true, "is not a Classic flavor; this smoke covers the Classic preview copies")
world:Boot()
local failure = world:FirstFailure()
Check(failure == nil, "load failed in " .. tostring(failure and failure.file) .. ": " .. tostring(failure and failure.message))

-- The flavor must load the owned copies, never the Retail-named files.
local PREVIEW = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/"
local loaded = {}
for _, path in ipairs(world.loaded) do loaded[path] = true end
Check(loaded[PREVIEW .. "MSUF_Menu2_UnitPreview_Render_Classic.lua"] and loaded[PREVIEW .. "MSUF_Menu2_UnitPreview_View_Classic.lua"],
    "does not load the Classic unit preview copies")
Check(not loaded[PREVIEW .. "MSUF_Menu2_UnitPreview_Render.lua"] and not loaded[PREVIEW .. "MSUF_Menu2_UnitPreview_View.lua"],
    "loads a Retail-named unit preview file")

-- Widget calls the preview makes that the shared stubs do not model. Added
-- after the boot, so the load itself runs on the same surface client_boot_smoke uses.
local Methods = world.widgets.Methods
local extraMethods = {
    SetStartPoint = function(self, ...) self.startPoint = { ... } end,
    SetEndPoint = function(self, ...) self.endPoint = { ... } end,
    SetThickness = function(self, value) self.thickness = value end,
    SetAutoFocus = function(self, value) self.autoFocus = value end,
    SetMaxLetters = function(self, value) self.maxLetters = value end,
    EnableKeyboard = function(self, value) self.keyboardEnabled = value end,
}
for name, method in pairs(extraMethods) do
    if Methods[name] == nil then Methods[name] = method end
end

local env, MSUF = world.env, world.core
-- The stock player-frame atlases exist on every client; the Era preview must
-- still use its bundled art, which is what makes the legacy check meaningful.
local FRAME_ATLAS = "UI-HUD-UnitFrame-Player-PortraitOn"
local MASK_ATLAS = "UI-HUD-UnitFrame-Player-Portrait-Mask"
local ATLAS_FILE = 131234
local atlases = {
    [FRAME_ATLAS] = { file = ATLAS_FILE, leftTexCoord = 0.25, rightTexCoord = 0.5, topTexCoord = 0, bottomTexCoord = 0.75 },
    [MASK_ATLAS] = { file = 131235 },
    ["UI-HUD-UnitFrame-Player-PortraitOn-CornerEmbellishment"] = { file = ATLAS_FILE },
}
env.C_Texture = { GetAtlasInfo = function(name) return atlases[name] end }

env.MSUF_EnsureDB(true)
local Preview = MSUF.UFPreview
Check(type(Preview) == "table" and type(Preview._BuildPreview) == "function", "no unit preview builder")
local refreshSource = debug.getinfo(Preview.Refresh, "S").source
Check(refreshSource:find("MSUF_Menu2_UnitPreview_Render_Classic.lua", 1, true) ~= nil,
    "Preview.Refresh does not come from the Classic render: " .. refreshSource)

local parent = env.CreateFrame("Frame", nil, env.UIParent)
parent:SetSize(900, 400)
local panel = env.CreateFrame("Frame", nil, env.UIParent)
local previewKey = "player"
panel._msufGetCurrentKey = function() return previewKey end
local box = Preview._BuildPreview(parent, panel, 900, 400)
Check(type(box) == "table" and type(box.mock) == "table", "the unit preview did not build")
box:Show()
-- The stubs resolve no anchors, so give the canvas the size a docked preview
-- has; the Fit zoom is computed from it.
box.canvas:SetSize(400, 200)
local mock = box.mock

local function DB() return env.MSUF_DB end
-- The menu's apply path recompiles the unit specs before the preview reads
-- them; the smoke does the same after every settings change.
local function Refresh(key)
    previewKey = key
    MSUF.UF.Config.Refresh()
    Preview.Refresh(box, "CLASSIC_UNIT_PREVIEW_PARITY_SMOKE")
    Check(box.key == key, "the preview did not switch to " .. key)
end
Refresh("player")
local R = Preview.RefreshDeps and Preview.RefreshDeps._RenderState
Check(type(R) == "table", "the Classic render installed no render state")

local function Shown(region) return region ~= nil and region:IsShown() == true end

-- 1. Power gradient -------------------------------------------------------
local g = DB().general
g.enablePowerGradient = true
Refresh("target")
Check(Shown(mock.power), "the Target preview lost its power bar")
local powerGradients = mock._msufPreviewPowerGradients
Check(type(powerGradients) == "table" and Shown(powerGradients.right),
    "Power gradient is on but the preview power bar shows no gradient")
Check(powerGradients.right._msufGradientTarget == mock.power,
    "the power gradient does not cover the preview power fill")
g.enablePowerGradient = false
Refresh("target")
Check(not Shown(powerGradients.right), "Power gradient is off but the preview still shows it")

-- A detached power bar (no power shape) carries the same gradient live.
local player = DB().player
player.powerBarDetached = true
player.detachedPowerBarShape = "BAR"
g.enablePowerGradient = true
Refresh("player")
Check(Shown(mock.detachedPower), "the detached Player power bar is not previewed")
local detachedGradients = mock._msufPreviewDetachedPowerGradients
Check(type(detachedGradients) == "table" and Shown(detachedGradients.right)
    and detachedGradients.right._msufGradientTarget == mock.detachedPower.fill,
    "Power gradient is on but the detached power bar preview shows no gradient")
g.enablePowerGradient = false
Refresh("player")
Check(not Shown(detachedGradients.right), "Power gradient is off but the detached bar preview still shows it")
player.powerBarDetached = false

-- 2. Class Resource text layer --------------------------------------------
local Layers = MSUF.UF.Layers
local textOwner = mock.classPower and mock.classPower.textOwner
Check(textOwner ~= nil, "the preview has no Class Resource text owner")
local bars = DB().bars
for _, layer in ipairs({ 20, 2 }) do
    bars.classPowerTextLayer = layer
    Refresh("player")
    Check(textOwner:GetFrameLevel() == Layers.TextLevel(textOwner, layer, 5),
        "Class Resource text layer " .. layer .. " is not previewed (level " .. tostring(textOwner:GetFrameLevel()) .. ")")
end
Check(Layers.TextLevel(textOwner, 20, 5) ~= Layers.TextLevel(textOwner, 2, 5),
    "harness: text layers 20 and 2 resolve to the same frame level")
bars.classPowerTextLayer = nil

-- 3. Boss target highlight -------------------------------------------------
local Indicator = MSUF.BossTargetIndicator
Check(type(Indicator) == "table", "the boss target element is not loaded")
local function HighlightOn(style)
    g.bossTargetHighlightEnabled = true
    g.bossTargetOutlineMode = 1
    g.bossTargetHighlightStyle = style
end
local function BorderEdgeColor()
    local overlay = mock._msufPreviewFrameBorder
    local edge = overlay and overlay._edges and overlay._edges.top
    return edge and edge.vertexColor
end
local boss = DB().boss
local bossUnits = MSUF.Client.SupportsUnit("boss1") == true
if bossUnits then
    Check(box.handleBossTarget ~= nil, "boss units exist but the preview has no boss target handle")
    HighlightOn("ARROW")
    Refresh("boss")
    local marker = mock._msufBossTargetIndicator
    Check(Shown(marker), "Arrow style draws no boss target marker")
    Check(Shown(box.handleBossTarget), "the boss target marker has no drag handle")
    local _, handleAnchor = box.handleBossTarget:GetPoint(1)
    Check(handleAnchor == marker, "the boss target handle is not placed on the marker")
    Check(mock._msufPreviewBossBorder == nil, "Arrow style paints the border highlight")
    -- The Fit footprint covers the marker: moved far out, the preview zooms out.
    local nearScale = box._mockAutoScale
    boss.bossTargetIndicatorOffsetX = -500
    Refresh("boss")
    Check(box._mockAutoScale < nearScale, "the boss target marker does not extend the preview footprint ("
        .. tostring(nearScale) .. " -> " .. tostring(box._mockAutoScale) .. ")")
    boss.bossTargetIndicatorOffsetX = nil

    HighlightOn("BORDER")
    Refresh("boss")
    Check(not Shown(marker) and not Shown(box.handleBossTarget), "Border style keeps the boss target marker")
    Check(mock._msufPreviewBossBorder ~= nil, "Border style paints no boss target highlight")
    local color = BorderEdgeColor()
    Check(color and color[1] == 1 and color[2] == 0.82 and color[3] == 0,
        "the boss frame border does not show the boss target highlight colour")

    HighlightOn("BORDER_ARROW")
    Refresh("boss")
    Check(Shown(marker) and mock._msufPreviewBossBorder ~= nil, "Border and arrow style does not draw both pieces")

    g.bossTargetHighlightEnabled = false
    g.bossTargetOutlineMode = 0
    Refresh("boss")
    Check(not Shown(marker) and not Shown(box.handleBossTarget) and mock._msufPreviewBossBorder == nil,
        "the boss target highlight stays with the highlight off")
    color = BorderEdgeColor()
    Check(not (color and color[1] == 1 and color[2] == 0.82 and color[3] == 0 and mock._msufPreviewFrameBorderEnabled == true),
        "the boss frame border keeps the highlight colour with the highlight off")

    HighlightOn("BORDER_ARROW")
    Refresh("player")
    Check(not Shown(marker) and not Shown(box.handleBossTarget) and mock._msufPreviewBossBorder == nil,
        "the boss target highlight shows on a unit that is not a boss")
else
    Check(box.handleBossTarget == nil, "a client without boss units builds the boss target handle")
    for _, handle in ipairs(box.handles or {}) do
        Check(handle._key ~= "bossTarget", "a client without boss units lists a boss target handle")
    end
    -- Even a boss spec reaching the preview must draw no boss piece here: the
    -- spec the flavor compiles for Target carries the same boss target keys.
    HighlightOn("BORDER_ARROW")
    local compiled = R.RuntimeSpecForPreviewKey
    R.RuntimeSpecForPreviewKey = function(key) return compiled(key == "boss" and "target" or key) end
    Refresh("boss")
    local forced = R.RuntimeSpecForPreviewKey("boss")
    Check(forced and Indicator.HasMarker(forced.border) and Indicator.HasBorder(forced.border),
        "harness: the forced boss spec carries no boss target highlight")
    Check(mock._msufBossTargetIndicator == nil, "a client without boss units draws the boss target marker")
    Check(mock._msufPreviewBossBorder == nil, "a client without boss units paints the boss target border")
    -- The forced spec compiles from the Target settings, so move its marker.
    local withHighlight = box._mockAutoScale
    local target = DB().target
    target.bossTargetIndicatorOffsetX = -500
    Refresh("boss")
    Check(R.RuntimeSpecForPreviewKey("boss").border.bossTargetX == -500, "harness: the forced boss spec ignores the marker offset")
    Check(box._mockAutoScale == withHighlight, "a client without boss units sizes the preview for a boss target marker")
    target.bossTargetIndicatorOffsetX = nil
    R.RuntimeSpecForPreviewKey = compiled
end

-- 4. Unchanged Classic behaviour --------------------------------------------
-- Era's legacy PlayerFrame has no modern portrait atlases: the preview keeps
-- its bundled gold ring and circle mask even when the atlas lookup answers.
player.portraitMode = "LEFT"
player.portraitShape = "BLIZZARD"
Refresh("player")
local portrait = mock.portrait
Check(Shown(portrait), "the Player portrait is not previewed")
local ring, fallback = portrait._msufPreviewBlizzRing, portrait._msufPreviewBlizzFallback
local mask = portrait._msufPreviewShapeMask
if MSUF.Client.IsVanilla == true then
    Check(Shown(fallback), "the Era preview lost the gold fallback ring for the Blizzard shape")
    Check(not Shown(ring), "the Era preview draws the modern atlas ring")
    Check(mask and type(mask.texture) == "string" and mask.texture:find("circle_mask", 1, true),
        "the Era preview does not mask the Blizzard shape with the bundled circle")
else
    Check(Shown(ring) and ring.texture == ATLAS_FILE, "the preview lost the stock atlas ring for the Blizzard shape")
    Check(not Shown(fallback), "the preview shows the Era fallback ring on a client with the modern atlases")
    Check(mask and mask.atlas == MASK_ATLAS, "the preview does not mask the Blizzard shape with the stock atlas")
end
player.portraitMode = nil
player.portraitShape = nil

-- The layer rail under the Layers button is a popover with its own width;
-- the render pass re-flows it from the box and must not widen it.
Check(type(box.LayoutLayerRail) == "function" and box.sidebar and #(box.layerButtons or {}) > 0,
    "the preview has no layer rail")
box._msuf2LayerPopoverWidth = 268
box:SetSize(900, 400)
box:LayoutLayerRail(900 - 24)
local railWidth = box.sidebar:GetWidth()
Check(railWidth <= 268, "the layer popover grew past its 268 px column: " .. tostring(railWidth))
local placedChips = 0
for index, chip in ipairs(box.layerButtons) do
    local _, _, _, x = chip:GetPoint(1)
    if chip:IsShown() and x ~= nil then
        placedChips = placedChips + 1
        Check(x >= 0 and x + chip:GetWidth() <= railWidth,
            "layer chip " .. index .. " ends outside the " .. tostring(railWidth) .. " px popover")
    end
end
Check(placedChips > 0, "the layer popover placed no chip")
box._msuf2LayerPopoverWidth = nil

-- Devourer's fragment notches belong to Midnight; no Classic class has them.
Check(mock.classPower.notches == nil, "the Classic preview builds a Devourer notch pool")

print(string.format("classic_unit_preview_parity_smoke: ok (%s, boss units %s)", flavor, bossUnits and "previewed" or "absent"))
