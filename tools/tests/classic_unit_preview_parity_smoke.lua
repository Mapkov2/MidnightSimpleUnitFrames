-- classic_unit_preview_parity_smoke.lua <repoRoot> <flavor>
--
-- Vanilla, TBC and Mists load the Retail-named Preview/MSUF_Menu2_UnitPreview_Render.lua
-- and ..._View.lua, whose Classic differences are gated on MSUF.Client facts read
-- once at load. The owned copies they replaced once lacked features whose
-- controls and runtime every Classic flavor has, so a setting changed and the
-- preview did not follow.
--
-- This smoke boots the flavor's whole shipped core and Options graph through
-- tools/tests/client_world.lua, builds the real unit preview and drives its
-- real Refresh from MSUF_DB, compiled by the flavor's own unit config:
--   * Power gradient on the inline and on a detached power bar;
--   * the Class Resource text layer (bars.classPowerTextLayer);
--   * the boss target marker, its drag handle, footprint and border highlight,
--     only where MSUF.Client.SupportsUnit("boss1") says boss units exist;
--   * the shared ..._Status.lua: the Pet Happiness icon where the client has
--     pet happiness, together with the Pet page control, the unit compile and
--     the runtime element that read the same settings, and the Level Text
--     difficulty colour and its settings, which the Status > Level toggle and
--     the unit compile read the same way;
--   * the Threat % text where MSUF.Client.SupportsThreatText is true: the Unit
--     page control, the runtime module, the unit compile and the preview row
--     with its dark plate (Background) and the plate's width;
--   * unchanged Classic behaviour: the Era legacy Blizzard portrait fallback,
--     the layer popover branch, and no Devourer notch drawn.
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
Check(world.client.isClassic == true, "is not a Classic flavor; this smoke covers the Classic unit preview")
world:Boot()
local failure = world:FirstFailure()
Check(failure == nil, "load failed in " .. tostring(failure and failure.file) .. ": " .. tostring(failure and failure.message))

-- The flavor must load the Retail-named render and view, never the retired
-- Classic copies of either.
local PREVIEW = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/"
local loaded = {}
for _, path in ipairs(world.loaded) do loaded[path] = true end
Check(loaded[PREVIEW .. "MSUF_Menu2_UnitPreview_Render.lua"] and loaded[PREVIEW .. "MSUF_Menu2_UnitPreview_View.lua"],
    "does not load the unit preview render and view")
Check(not loaded[PREVIEW .. "MSUF_Menu2_UnitPreview_Render_Classic.lua"] and not loaded[PREVIEW .. "MSUF_Menu2_UnitPreview_View_Classic.lua"],
    "loads a retired Classic unit preview render or view copy")

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
Check(refreshSource:find("MSUF_Menu2_UnitPreview_Render.lua", 1, true) ~= nil,
    "Preview.Refresh does not come from the unit preview render: " .. refreshSource)
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
Check(type(R) == "table", "the unit preview render installed no render state")

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

-- 4. Status preview ---------------------------------------------------------
-- The flavor loads the Retail-named ..._Status.lua, an override row, so a
-- Retail rebase lands in it: its Pet Happiness hunk and the Level Text
-- difficulty colour are pinned by what the preview draws.
local UnitPage = world.options.MSUF2 and world.options.MSUF2.UnitPage
Check(type(UnitPage) == "table" and type(UnitPage.ReadStatusBool) == "function", "the Unit page publishes no status reader")
local function StatusControl(value)
    for _, spec in ipairs(UnitPage.STATUS_CONTROLS or {}) do
        if spec.value == value then return spec end
    end
    return nil
end
Preview.SetStatusPreviewMode("all")
local pet = DB().pet
pet.showPetHappinessIndicator = true
Refresh("pet")
local happiness = mock.icons and mock.icons.statusPetHappiness
if MSUF.Client.SupportsPetHappiness == true then
    Check(Shown(happiness) and Shown(happiness.tex), "Pet Happiness is on but the Pet preview draws no happiness icon")
    Check(happiness.tex.texture == "Interface\\PetPaperDollFrame\\UI-PetHappiness",
        "the Pet Happiness preview does not use the stock happiness texture: " .. tostring(happiness.tex.texture))
    local coords = happiness.tex.texCoord or {}
    Check(coords[1] == 0 and coords[2] == 0.1875 and coords[3] == 0 and coords[4] == 0.359375,
        "the Pet Happiness preview does not show the Happy state: " .. table.concat(coords, ","))
else
    Check(not Shown(happiness), "a client without pet happiness previews the happiness icon")
end
pet.showPetHappinessIndicator = nil

-- The preview reads the settings, not the compile, so it cannot see the live
-- side. The Pet page control, the unit compile of the Retail-named
-- UnitFrames/Engine/MSUF_UF_Config.lua (an override row every Retail sync
-- rebases) and the runtime element, which reads only spec.status.petHappiness,
-- must agree: a rebase that drops the entry on Classic would keep the control
-- and the preview and leave the live pet frame blank.
local happinessControl = StatusControl("statusPetHappiness")
local happinessModule = loaded["MidnightSimpleUnitFrames/Game/Shared/UnitFrames/MSUF_UF_PetHappiness.lua"] == true
local happinessElement = MSUF.UF.elements and MSUF.UF.elements.PetHappinessIndicator
local petFrame = { MSUFUnitKey = "pet" }
local function CompiledHappiness(key)
    MSUF.UF.Config.Refresh()
    local spec = MSUF.UF.Config.GetSpec(key)
    return spec and spec.status and spec.status.petHappiness, spec
end
local function Placement(show, size, anchor, x, y, layer)
    return string.format("%s %s %s %s %s layer %s", tostring(show), tostring(size), tostring(anchor), tostring(x), tostring(y), tostring(layer))
end
local function EntryPlacement(entry)
    return entry and Placement(entry.enabled, entry.size, entry.anchor, entry.x, entry.y, entry.layer) or "no entry"
end
if MSUF.Client.SupportsPetHappiness == true then
    local control = happinessControl
    Check(control and control.allowed("pet") and not control.allowed("player") and not control.allowed("target"),
        "the Unit page does not offer Pet Happiness on the Pet page only")
    Check(happinessModule and type(happinessElement) == "table" and type(happinessElement.IsEnabled) == "function",
        "the Pet Happiness runtime element is not loaded")
    local DEFAULT = Placement(true, 24, "RIGHT", -7, -4, 7)
    Check(Placement(control.defaultShow, control.defaultSize, control.defaultAnchor, control.defaultX, control.defaultY,
        control.defaultLayer) == DEFAULT, "the Pet page control no longer defaults to " .. DEFAULT)
    -- A fresh profile, as the Defaults seed it.
    local entry, spec = CompiledHappiness("pet")
    Check(EntryPlacement(entry) == DEFAULT, "the unit compile has no default-on Pet Happiness entry at " .. DEFAULT
        .. " (" .. EntryPlacement(entry) .. ")")
    Check(happinessElement.IsEnabled(petFrame, spec) == true, "the Pet Happiness element does not run on the default compile")
    local targetEntry = CompiledHappiness("target")
    Check(targetEntry == nil or targetEntry.enabled == false, "the unit compile enables Pet Happiness on the Target frame")
    -- Nothing stored at all: the compile's own fallbacks must be what the page
    -- shows. Size is left out: an unset size falls back to the status text size
    -- on every client, Midnight and Forever included, and the Defaults seed
    -- petHappinessIndicatorSize wherever the client has pet happiness.
    local keys = { control.show, control.size, control.anchor, control.x, control.y, control.layer }
    local saved = {}
    for index, key in ipairs(keys) do
        saved[index] = { pet[key], g[key] }
        pet[key], g[key] = nil, nil
    end
    entry = CompiledHappiness("pet")
    local unset = entry and Placement(entry.enabled, "-", entry.anchor, entry.x, entry.y, entry.layer) or "no entry"
    local pageUnset = Placement(control.defaultShow, "-", control.defaultAnchor, control.defaultX, control.defaultY, control.defaultLayer)
    Check(unset == pageUnset, "an unset Pet Happiness compiles to " .. unset .. " while the Pet page shows " .. pageUnset)
    -- The keys the page control writes are the keys the compile reads.
    pet[control.show], pet[control.size], pet[control.anchor] = false, 30, "LEFT"
    pet[control.x], pet[control.y], pet[control.layer] = 5, 6, 9
    entry, spec = CompiledHappiness("pet")
    Check(EntryPlacement(entry) == Placement(false, 30, "LEFT", 5, 6, 9),
        "the Pet page's Pet Happiness settings do not reach the unit compile: " .. EntryPlacement(entry))
    Check(not happinessElement.IsEnabled(petFrame, spec), "the Pet Happiness element still runs with Pet Happiness off")
    for index, key in ipairs(keys) do
        pet[key], g[key] = saved[index][1], saved[index][2]
    end
else
    Check(happinessControl == nil, "the Unit page offers Pet Happiness on a client without it")
    Check(not happinessModule and happinessElement == nil, "a client without pet happiness loads its runtime")
    Check(CompiledHappiness("pet") == nil, "the unit compile has a Pet Happiness entry on a client without it")
end

-- Level Text: levelIndicatorDifficultyColor is the key the Status > Level
-- toggle writes. Per frame first, then general; unset means on unless the
-- frame carries its own level text colour. A distinct palette per tier, so
-- the difficulty colour can never pass for the font or the custom colour.
local TIER_KEYS = { "levelColorImpossible", "levelColorVeryDifficult", "levelColorStandard", "levelColorEasy", "levelColorTrivial" }
for index, prefix in ipairs(TIER_KEYS) do
    g[prefix .. "R"], g[prefix .. "G"], g[prefix .. "B"] = index / 10, 0.05, 1 - index / 10
end
local fontR, fontG, fontB = Preview.Model.FontColor()
local target = DB().target
target.showLevelIndicator = true
local function LevelColor()
    Refresh("target")
    local level = mock.icons and mock.icons.level
    Check(Shown(level) and level.txt ~= nil, "the Target preview shows no level text")
    local color = level.txt.textColor or {}
    return color[1], color[2], color[3]
end
local function IsTier(r, green, b)
    for index = 1, #TIER_KEYS do
        if r == index / 10 and green == 0.05 and b == 1 - index / 10 then return true end
    end
    return false
end
local function IsFont(r, green, b) return r == fontR and green == fontG and b == fontB end
local function Custom(r, green, b)
    target.levelIndicatorColorR, target.levelIndicatorColorG, target.levelIndicatorColorB = r, green, b
end
-- The Status > Level toggle (the status section's own reader, run against the
-- Unit page's helpers) and the unit compile must agree with what the preview
-- draws at every step: one key, one default rule, one palette (ledger B52).
local sectionFile = assert(io.open(root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitStatusSection.lua", "rb"))
local sectionSource = sectionFile:read("*a"):gsub("\r\n", "\n")
sectionFile:close()
Check(sectionSource:find('SetBool(unit, "levelIndicatorDifficultyColor", value, "MSUF2_STATUS_LEVEL_DIFFICULTY_COLOR"', 1, true),
    "the Status > Level toggle no longer writes levelIndicatorDifficultyColor")
local readerBody = sectionSource:match("\n    (local function LevelDifficultyColorEnabled%(%)\n.-\n    end)\n")
Check(readerBody, "the Status > Level toggle lost its reader")
local MenuLevelToggle = assert(loadstring("local unit, GetConf, GetGeneral, ReadStatusBool = ...\n" .. readerBody
    .. "\nreturn LevelDifficultyColorEnabled"))("target", UnitPage.GetConf, UnitPage.GetGeneral, UnitPage.ReadStatusBool)
local function Coherent(label)
    local previewOn = IsTier(LevelColor())
    -- The palette is one shared buffer: recompile last so the compile's own read is checked.
    MSUF.UF.Config.Refresh()
    local level = MSUF.UF.Config.GetSpec("target").status.level
    Check(level ~= nil, label .. ": the unit compile has no Level Text entry")
    Check((level.difficultyColor == true) == previewOn, label .. ": the unit compile says difficulty colour "
        .. tostring(level.difficultyColor) .. " while the preview " .. (previewOn and "draws it" or "does not"))
    Check(MenuLevelToggle() == previewOn, label .. ": the Status > Level toggle shows " .. tostring(MenuLevelToggle())
        .. " while the preview " .. (previewOn and "draws the difficulty colour" or "does not"))
    if previewOn then
        local palette = level.difficultyColors or {}
        for index = 1, #TIER_KEYS do
            Check(palette[index * 3 - 2] == index / 10 and palette[index * 3 - 1] == 0.05 and palette[index * 3] == 1 - index / 10,
                label .. ": the unit compile does not take tier " .. index .. " from the Colors page palette")
        end
    end
end
Check(IsTier(LevelColor()), "Level Text with no stored choice is not coloured by difficulty")
Coherent("no stored choice")
target.levelIndicatorDifficultyColor = false
Check(IsFont(LevelColor()), "Level Text keeps the difficulty colour with the toggle off")
Coherent("frame toggle off")
target.levelIndicatorDifficultyColor = true
Custom(0.2, 0.4, 0.6)
Check(IsTier(LevelColor()), "the toggle on does not win over a custom level text colour")
Coherent("frame toggle on over a custom colour")
target.levelIndicatorDifficultyColor = nil
local r, green, b = LevelColor()
Check(r == 0.2 and green == 0.4 and b == 0.6, "a custom level text colour does not turn the difficulty colour off by default")
Coherent("custom colour, toggle unset")
Custom(nil, nil, nil)
g.levelIndicatorDifficultyColor = false
Check(IsFont(LevelColor()), "the general toggle off does not reach a frame without its own choice")
Coherent("general toggle off")
target.levelIndicatorDifficultyColor = true
Check(IsTier(LevelColor()), "the frame toggle on does not win over the general toggle")
Coherent("frame toggle on over the general toggle off")
target.levelIndicatorDifficultyColor = nil
target.showLevelIndicator = nil
g.levelIndicatorDifficultyColor = nil
for _, prefix in ipairs(TIER_KEYS) do
    g[prefix .. "R"], g[prefix .. "G"], g[prefix .. "B"] = nil, nil, nil
end

-- Threat % text: Classic Era and TBC offer it, Mists does not. Every piece
-- lives in a file all clients share, so the client fact alone decides.
local supportsThreat = MSUF.Client.SupportsThreatText == true
local threatControl = StatusControl("statusThreat")
local threatModule = loaded["MidnightSimpleUnitFrames/Game/Shared/UnitFrames/MSUF_UF_ThreatText.lua"] == true
local function ThreatText()
    Refresh("target")
    return MSUF.UF.Config.GetSpec("target").status.threat, mock.icons and mock.icons.statusThreat
end
local compiledThreat, threatRow = ThreatText()
if supportsThreat then
    Check(threatControl and threatControl.allowed("target") and threatControl.allowed("focus")
        and threatControl.allowed("boss") and not threatControl.allowed("player"),
        "the Unit page does not offer Threat % on the target, focus and boss pages only")
    Check(threatModule and type(MSUF.UFThreatText) == "table", "the threat text runtime is not loaded")
    Check(compiledThreat and compiledThreat.enabled == true and compiledThreat.colorCurve == true,
        "the unit compile has no default-on Threat % entry with Color by threat")
    Check(threatRow and Shown(threatRow.txt) and threatRow.txt.text == "85%", "the Target preview shows no 85% threat sample")
    local cr, cg, cb = MSUF.UFThreatText.CurveColorAt(g, 85)
    local color = threatRow.txt.textColor or {}
    Check(color[1] == cr and color[2] == cg and color[3] == cb, "the threat sample is not drawn in its 85% curve colour")
    -- The dark plate (Background, on by default): the render lays the row out
    -- at the width of "100%" in the sample's font, and the plate pads it evenly.
    local function RowWidth(text)
        local shown = threatRow.txt:GetText()
        threatRow.txt:SetText(text)
        local width = threatRow.txt:GetStringWidth()
        threatRow.txt:SetText(shown)
        return math.max(1, math.floor(width + 0.5))
    end
    Check(RowWidth("100%") ~= RowWidth("85%"), "harness: 100% and 85% measure the same width")
    local plate = threatRow.bg
    Check(threatRow._msufThreatPlate == true and plate ~= nil, "the Target preview draws the threat sample without its dark plate")
    local topLeft, bottomRight = plate.points[1], plate.points[2]
    Check(#plate.points == 2 and topLeft.point == "TOPLEFT" and topLeft.relativeTo == threatRow
        and bottomRight.point == "BOTTOMRIGHT" and bottomRight.relativeTo == threatRow
        and topLeft.x < 0 and topLeft.y > 0 and bottomRight.x == -topLeft.x and bottomRight.y == -topLeft.y,
        "the threat plate is not padded evenly around the sample")
    local plateColor = plate.colorTexture or {}
    Check(plateColor[1] == 0 and plateColor[2] == 0 and plateColor[3] == 0 and plateColor[4] == 0.75,
        "the threat plate is not the runtime's dark plate")
    Check(threatRow:GetWidth() == RowWidth("100%"), "the threat sample on its plate is not as wide as 100% ("
        .. tostring(threatRow:GetWidth()) .. ")")
    target.threatIndicatorBackground = false
    Refresh("target")
    Check(threatRow._msufThreatPlate == nil and plate.allPoints ~= nil and (plate.colorTexture or {})[4] == 0,
        "Background off does not clear the threat plate")
    Check(threatRow:GetWidth() == RowWidth("85%"), "without its plate the threat sample keeps the width of 100%")
    target.threatIndicatorBackground = nil
    Refresh("target")
    Check(threatRow._msufThreatPlate == true, "Background back on does not bring the threat plate back")
    target.threatIndicatorColorCurve = false
    compiledThreat, threatRow = ThreatText()
    color = threatRow.txt.textColor or {}
    Check(compiledThreat.colorCurve == false and color[1] == fontR and color[2] == fontG and color[3] == fontB,
        "Color by threat off does not reach the unit compile and the preview together")
    target.threatIndicatorColorCurve = nil
    target.showThreatIndicator = false
    compiledThreat = ThreatText()
    Check(compiledThreat.enabled == false, "Threat % off does not reach the unit compile")
    target.showThreatIndicator = nil
else
    Check(threatControl == nil, "the Unit page offers Threat % on a client without it")
    Check(not threatModule, "a client without the threat text loads its runtime")
    Check(compiledThreat == nil, "the unit compile has a Threat % entry on a client without it")
    Check(threatRow == nil, "the preview has a Threat % row on a client without it")
end
Preview.SetStatusPreviewMode("current")

-- 5. Unchanged Classic behaviour --------------------------------------------
-- Era's legacy PlayerFrame has no modern portrait atlases: the preview keeps
-- its bundled gold ring and circle mask even when the atlas lookup answers.
player.portraitMode = "LEFT"
player.portraitShape = "BLIZZARD"
Refresh("player")
local portrait = mock.portrait
Check(Shown(portrait), "the Player portrait is not previewed")
Check(not Shown(portrait._msufPreviewBlizzCorner), "the player bar-housing joint overlays the standalone ring")
local ring, fallback = portrait._msufPreviewBlizzRing, portrait._msufPreviewBlizzFallback
local mask = portrait._msufPreviewShapeMask
if MSUF.Client.IsVanilla == true then
    Check(Shown(fallback), "the Era preview lost the gold fallback ring for the Blizzard shape")
    Check(not Shown(ring), "the Era preview draws the modern atlas ring")
    Check(mask and type(mask.texture) == "string" and mask.texture:find("circle_mask", 1, true),
        "the Era preview does not mask the Blizzard shape with the bundled circle")
else
    Check(Shown(ring) and type(ring.texture) == "string" and ring.texture:find("msuf_portrait_ring_blizzard", 1, true), "the preview lost the standalone contour ring for the Blizzard shape")
    Check(not Shown(fallback), "the preview shows the Era fallback ring on a client with the modern atlases")
    Check(mask and type(mask.texture) == "string" and mask.texture:find("portrait_blizzard_mask", 1, true), "the preview does not mask the Blizzard shape with the matching contour asset")
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
-- The shared view builds Retail's empty pool; on Classic the render never fills it.
Check(mock.classPower.notches == nil or next(mock.classPower.notches) == nil,
    "the Classic preview draws a Devourer notch")

print(string.format("classic_unit_preview_parity_smoke: ok (%s, boss units %s)", flavor, bossUnits and "previewed" or "absent"))
