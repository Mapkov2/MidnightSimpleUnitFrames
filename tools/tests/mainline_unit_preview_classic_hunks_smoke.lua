-- mainline_unit_preview_classic_hunks_smoke.lua <repoRoot> <flavor>
--
-- Every client loads the Retail-named Preview/MSUF_Menu2_UnitPreview_Render.lua.
-- Its Classic override hunks are gated on client facts read once at load
-- (PREVIEW_CLASSIC, LEGACY_BLIZZARD_PORTRAIT): on Vanilla, TBC and Mists the
-- texture layers stamp after the portrait instead of inside Stage.RenderHealth,
-- and the Blizzard portrait shape gets a gold fallback ring where the stock atlas
-- is missing; Era also skips the modern atlases. Midnight and WoW Forever must
-- keep Retail's preview exactly. The Classic side is pinned by
-- classic_unit_preview_parity_smoke and classic_unit_preview_texture_layer_order_smoke.
--
-- This smoke boots the flavor's whole shipped core and Options graph through
-- tools/tests/client_world.lua, builds the real unit preview and drives its real
-- Refresh from MSUF_DB:
--   * Retail's stamp order: RenderTextureLayerPreview runs once per refresh,
--     from Stage.RenderHealth, and Preview.Refresh never runs it again after
--     Stage.RenderPortrait (a call hook records who calls it);
--   * the Blizzard portrait shape: the stock atlas ring and atlas mask while the
--     atlases exist, and no gold fallback ring when they do not.
--
-- Plain Lua 5.1 with the repo root and a Mainline-family flavor (Mainline or
-- Forever) as arguments.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg and arg[2], "flavor required (Mainline or Forever)")
assert(rawget(_G, "MSUF_Auras3TestLoader") == nil,
    "mainline_unit_preview_classic_hunks_smoke boots the real TOC graph; run it with plain Lua 5.1")

local World = assert(loadfile(root .. "/tools/tests/client_world.lua"),
    "mainline_unit_preview_classic_hunks_smoke: tools/tests/client_world.lua is missing")()

local function Check(condition, message)
    if not condition then error(flavor .. ": " .. message, 2) end
end

local world = World.New(root, flavor)
Check(world.client.isClassic ~= true, "is a Classic flavor; this smoke covers the Mainline-family preview")
world:Boot()
local failure = world:FirstFailure()
Check(failure == nil, "load failed in " .. tostring(failure and failure.file) .. ": " .. tostring(failure and failure.message))

local RENDER = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Render.lua"
local loaded = {}
for _, path in ipairs(world.loaded) do loaded[path] = true end
Check(loaded[RENDER], "does not load the Retail-named unit preview render")

-- Widget calls the preview makes that the shared stubs do not model. Added
-- after the boot, so the load itself runs on the same surface client_boot_smoke uses.
local Methods = world.widgets.Methods
for name, method in pairs({
    SetStartPoint = function(self, ...) self.startPoint = { ... } end,
    SetEndPoint = function(self, ...) self.endPoint = { ... } end,
    SetThickness = function(self, value) self.thickness = value end,
    SetAutoFocus = function(self, value) self.autoFocus = value end,
    SetMaxLetters = function(self, value) self.maxLetters = value end,
    EnableKeyboard = function(self, value) self.keyboardEnabled = value end,
}) do
    if Methods[name] == nil then Methods[name] = method end
end

local env, MSUF = world.env, world.core
Check(MSUF.Client and MSUF.Client.Family == "Mainline", "the client model does not report the Mainline family")
-- The stock player-frame atlases; the lookup answers only while atlasesPresent.
local FRAME_ATLAS = "UI-HUD-UnitFrame-Player-PortraitOn"
local MASK_ATLAS = "UI-HUD-UnitFrame-Player-Portrait-Mask"
local ATLAS_FILE = 131234
local atlases = {
    [FRAME_ATLAS] = { file = ATLAS_FILE, leftTexCoord = 0.25, rightTexCoord = 0.5, topTexCoord = 0, bottomTexCoord = 0.75 },
    [MASK_ATLAS] = { file = 131235 },
    ["UI-HUD-UnitFrame-Player-PortraitOn-CornerEmbellishment"] = { file = ATLAS_FILE },
}
local atlasesPresent = true
env.C_Texture = { GetAtlasInfo = function(name) return atlasesPresent and atlases[name] or nil end }
env.MSUF_EnsureDB(true)

local Preview = MSUF.UFPreview
Check(type(Preview) == "table" and type(Preview._BuildPreview) == "function", "no unit preview builder")
local refreshInfo = debug.getinfo(Preview.Refresh, "S")
Check(refreshInfo.source:gsub("\\", "/"):find(RENDER, 1, true) ~= nil,
    "Preview.Refresh does not come from the unit preview render: " .. refreshInfo.source)

-- Where the render defines the functions the stamp order is read from.
local source = World.Read(root .. "/" .. RENDER)
local function DefinedAt(pattern, label)
    local at = source:find(pattern)
    Check(at ~= nil, "harness: the unit preview render no longer defines " .. label)
    local line = 1
    for _ in source:sub(1, at):gmatch("\n") do line = line + 1 end
    return line
end
local STAMP_LINE = DefinedAt("\nlocal function RenderTextureLayerPreview%(", "RenderTextureLayerPreview")
local HEALTH_LINE = DefinedAt("\nfunction Stage%.RenderHealth%(", "Stage.RenderHealth")
local REFRESH_LINE = DefinedAt("\nfunction Preview%.Refresh%(", "Preview.Refresh")
Check(refreshInfo.linedefined == REFRESH_LINE, "harness: Preview.Refresh is not the function defined at line " .. REFRESH_LINE)

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
Check(type(mock.texLayers) == "table" and mock.texLayers[1] ~= nil, "the preview has no texture layer holders")

local player = env.MSUF_DB.player
local function Refresh(key)
    previewKey = key
    MSUF.UF.Config.Refresh()
    Preview.Refresh(box, "MAINLINE_UNIT_PREVIEW_CLASSIC_HUNKS_SMOKE")
    Check(box.key == key, "the preview did not switch to " .. key)
end
local function Shown(region) return region ~= nil and region:IsShown() == true end

-- 1. Retail's stamp order ---------------------------------------------------
-- A layer on Player Power and one on the Portrait, both previewed, so the
-- stamp has real targets; the order is what is measured.
player.showPowerBar = true
player.portraitMode = "LEFT"
player.texLayerEnabled, player.texLayerAnchorTarget, player.texLayerAnchor = true, "POWER", "LEFT"
player.texLayer2Enabled, player.texLayer2AnchorTarget, player.texLayer2Anchor = true, "PORTRAIT", "CENTER"
Refresh("player")
local callers = {}
debug.sethook(function()
    local called = debug.getinfo(2, "S")
    if called and called.linedefined == STAMP_LINE and called.source:gsub("\\", "/"):find(RENDER, 1, true) then
        local caller = debug.getinfo(3, "S")
        callers[#callers + 1] = caller and caller.linedefined or -1
    end
end, "c")
Refresh("player")
debug.sethook()
Check(#callers > 0, "the refresh never stamps the texture layers")
Check(#callers == 1, "a refresh stamps the texture layers " .. #callers .. " times instead of once")
Check(callers[1] == HEALTH_LINE, "the texture layers are stamped by the function at line " .. tostring(callers[1])
    .. (callers[1] == REFRESH_LINE and " (Preview.Refresh after Stage.RenderPortrait, the Classic order)" or "")
    .. " instead of Stage.RenderHealth")
Check(Shown(mock.powerBG) and Shown(mock.portrait), "harness: the measured refresh shows no power bar or portrait")
Check(Shown(mock.texLayers[1]), "the texture layer on Player Power is not previewed")
for _, prefix in ipairs({ "texLayer", "texLayer2" }) do
    player[prefix .. "Enabled"], player[prefix .. "AnchorTarget"], player[prefix .. "Anchor"] = nil, nil, nil
end

-- 2. Blizzard portrait shape ------------------------------------------------
player.portraitShape = "BLIZZARD"
Refresh("player")
local portrait = mock.portrait
Check(Shown(portrait), "the Player portrait is not previewed")
local ring, mask = portrait._msufPreviewBlizzRing, portrait._msufPreviewShapeMask
Check(Shown(ring) and ring.texture == ATLAS_FILE, "the preview lost the stock atlas ring for the Blizzard shape")
Check(mask and mask.atlas == MASK_ATLAS, "the preview does not mask the Blizzard shape with the stock atlas")
Check(portrait._msufPreviewBlizzFallback == nil, "the preview builds the Classic gold fallback ring")
-- No atlas: Retail draws no ring at all, never the Classic gold fallback.
atlasesPresent = false
Refresh("player")
Check(not Shown(portrait._msufPreviewBlizzRing), "the stock atlas ring stays without the atlas")
Check(portrait._msufPreviewBlizzFallback == nil, "a missing atlas draws the Classic gold fallback ring")
atlasesPresent = true
player.portraitMode, player.portraitShape, player.showPowerBar = nil, nil, nil

print(string.format("mainline_unit_preview_classic_hunks_smoke: ok (%s)", flavor))
