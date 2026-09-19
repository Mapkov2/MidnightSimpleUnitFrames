-- mainline_unit_preview_boss_target_smoke.lua <repoRoot> <flavor>
--
-- Every client loads the Retail-named Preview/MSUF_Menu2_UnitPreview_View.lua.
-- Its Classic override hunk builds the boss target drag handle only where
-- MSUF.Client.SupportsUnit("boss1") says boss units exist (the file-load
-- upvalue HAS_BOSS_UNITS), and the render draws the marker only when that
-- handle exists. Midnight and WoW Forever have boss units, so their preview
-- must keep Retail's handle, marker, footprint and border highlight; the
-- Classic side of the hunk is pinned by classic_unit_preview_parity_smoke.
--
-- This smoke boots the flavor's whole shipped core and Options graph through
-- tools/tests/client_world.lua, builds the real unit preview and drives the
-- real Refresh from MSUF_DB, compiled by the flavor's own unit config.
--
-- Plain Lua 5.1 with the repo root and a Mainline-family flavor (Mainline or
-- Forever) as arguments.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg and arg[2], "flavor required (Mainline or Forever)")
assert(rawget(_G, "MSUF_Auras3TestLoader") == nil,
    "mainline_unit_preview_boss_target_smoke boots the real TOC graph; run it with plain Lua 5.1")

local World = assert(loadfile(root .. "/tools/tests/client_world.lua"),
    "mainline_unit_preview_boss_target_smoke: tools/tests/client_world.lua is missing")()

local function Check(condition, message)
    if not condition then error(flavor .. ": " .. message, 2) end
end

local world = World.New(root, flavor)
Check(world.client.isClassic ~= true, "is a Classic flavor; this smoke covers the Mainline-family preview")
world:Boot()
local failure = world:FirstFailure()
Check(failure == nil, "load failed in " .. tostring(failure and failure.file) .. ": " .. tostring(failure and failure.message))

local PREVIEW = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/"
local loaded = {}
for _, path in ipairs(world.loaded) do loaded[path] = true end
Check(loaded[PREVIEW .. "MSUF_Menu2_UnitPreview_Render.lua"] and loaded[PREVIEW .. "MSUF_Menu2_UnitPreview_View.lua"],
    "does not load the Retail-named unit preview render and view")
Check(not loaded[PREVIEW .. "MSUF_Menu2_UnitPreview_Render_Classic.lua"],
    "loads the Classic unit preview render")

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
Check(MSUF.Client and MSUF.Client.Family == "Mainline", "the client model does not report the Mainline family")
Check(MSUF.Client.SupportsUnit("boss1") == true, "the client model reports no boss units")
env.C_Texture = { GetAtlasInfo = function() return nil end }
env.MSUF_EnsureDB(true)
local Preview = MSUF.UFPreview
Check(type(Preview) == "table" and type(Preview._BuildPreview) == "function", "no unit preview builder")
local buildSource = debug.getinfo(Preview._BuildPreview, "S").source
Check(buildSource:find("MSUF_Menu2_UnitPreview_View.lua", 1, true) ~= nil,
    "the unit preview builder does not come from the shared view: " .. buildSource)

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

-- The handle exists and is listed once, like every other drag target.
Check(box.handleBossTarget ~= nil, "the preview builds no boss target handle")
local listed = 0
for _, handle in ipairs(box.handles or {}) do
    if handle._key == "bossTarget" then
        listed = listed + 1
        Check(handle == box.handleBossTarget, "the listed boss target handle is not box.handleBossTarget")
    end
end
Check(listed == 1, "the boss target handle is listed " .. listed .. " times")

local function DB() return env.MSUF_DB end
local function Refresh(key)
    previewKey = key
    MSUF.UF.Config.Refresh()
    Preview.Refresh(box, "MAINLINE_UNIT_PREVIEW_BOSS_TARGET_SMOKE")
    Check(box.key == key, "the preview did not switch to " .. key)
end
local function Shown(region) return region ~= nil and region:IsShown() == true end

local g, boss = DB().general, DB().boss
local function HighlightOn(style)
    g.bossTargetHighlightEnabled = true
    g.bossTargetOutlineMode = 1
    g.bossTargetHighlightStyle = style
end

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

HighlightOn("BORDER_ARROW")
Refresh("boss")
Check(Shown(marker) and Shown(box.handleBossTarget) and mock._msufPreviewBossBorder ~= nil,
    "Border and arrow style does not draw both pieces")

g.bossTargetHighlightEnabled = false
g.bossTargetOutlineMode = 0
Refresh("boss")
Check(not Shown(marker) and not Shown(box.handleBossTarget) and mock._msufPreviewBossBorder == nil,
    "the boss target highlight stays with the highlight off")

HighlightOn("BORDER_ARROW")
Refresh("player")
Check(not Shown(marker) and not Shown(box.handleBossTarget) and mock._msufPreviewBossBorder == nil,
    "the boss target highlight shows on a unit that is not a boss")

print(string.format("mainline_unit_preview_boss_target_smoke: ok (%s)", flavor))
