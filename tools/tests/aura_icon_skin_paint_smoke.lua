-- Aura icon skins: the painter and the compiler (Auras3/MSUF_Auras3_IconSkins.lua).
--
-- Runs the real skin files on widget stubs:
--   1. every catalog skin paints the layers its definition names, on the
--      documented draw layers (gloss on the owner at OVERLAY(-1), below the
--      owner's text), and stays inside the per-button widget budget (a pool
--      fill in combat pays this once per button);
--   2. repainting an unchanged skin writes nothing at all, and repainting
--      CUSTOM after a skin was hidden touches no skin region again (the
--      Classic backend repaints on aura updates); switching skins hides the
--      previous skin's extra layers; CUSTOM and shaped icons hand the look
--      back to the user's border and shadow;
--   3. a flat icon (height below 100%) keeps every band and line inside it,
--      and a ring quad on a wide icon scales its extent per axis;
--   4. a Classic lane that hides its icon hides its skin, decided by the lane's
--      final settings when the button is laid out (bar-only duration bars, a
--      group Spell Icon style applied after the lane compiled, indicators drawn
--      as a square, bar or number); a layout repeated for the same compiled
--      skin (a cooldown that appeared) reads no size and writes nothing;
--   5. Attach leaves a CUSTOM style and its signature byte-identical (no
--      container rebuild for profiles without a skin) and appends the skin
--      signature otherwise;
--   6. the skin files are cold path only: no events, hooks, timers, scripts
--      or frames;
--   7. the mock previews keep their frozen layers without a skin and, with one,
--      lift the swipe above the skin, gloss, dispel border and duration bar and
--      below the text, like the live button, only while the skin is drawn (not
--      for a skin rejected by the icon shape); they size a skin from the icon's
--      real width and height;
--   8. previews and the gallery never switch the live painters: only a runtime
--      compile that produced a skin does, once, for every registered owner, and
--      a skin removed later is still hidden on the live button it was drawn on;
--   9. Skins.Outset reports, for every catalog skin, square and flat icons, how
--      far the painted frame (not the soft shadow) reaches past the icon: the
--      width a bar matched to a row of skinned icons must add.
-- Argument: the repository root.
local root = assert(arg[1], "repository root argument missing")
root = (tostring(root):gsub("\\", "/"):gsub("/+$", ""))
local ADDON = root .. "/MidnightSimpleUnitFrames/"

local calls, created, skinHides, sizeReads = 0, 0, 0, 0
local Region = {}
Region.__index = Region
local function Count() calls = calls + 1 end
function Region:SetTexture(path) Count(); self.texture = path end
function Region:SetAtlas(name) Count(); self.atlas = name end
function Region:SetTexCoord() Count() end
function Region:SetDrawLayer(layer, sublevel) Count(); self.layer, self.sublevel = layer, sublevel end
function Region:ClearAllPoints() Count(); self.points = {} end
function Region:SetPoint(point, _, _, x, y)
    Count()
    self.points = self.points or {}
    self.points[#self.points + 1] = point
    self.offsets = self.offsets or {}
    self.offsets[point] = { x, y }
end
function Region:SetAllPoints() Count(); self.allPoints = true end
function Region:SetSize(width, height) Count(); self.width, self.height = width, height end
function Region:SetWidth(width) Count(); self.width = width end
function Region:SetHeight(height) Count(); self.height = height end
function Region:SetVertexColor(r, g, b, a) Count(); self.color = { r, g, b, a } end
function Region:SetBlendMode(mode) Count(); self.blend = mode end
function Region:SetShown(shown) Count(); self.shown = shown == true end
function Region:SetReverse() Count() end
function Region:SetSwipeTexture() Count() end
function Region:GetNumRegions() return 0 end
function Region:GetWidth() sizeReads = sizeReads + 1; return self.width end
function Region:GetHeight() sizeReads = sizeReads + 1; return self.height end
function Region:GetRegions() end
function Region:Show() Count(); self.shown = true end
function Region:Hide()
    Count()
    if self.skinLayer then skinHides = skinHides + 1 end
    self.shown = false
end
local function IsSkinLayer(layer, sublevel)
    return (layer == "ARTWORK" and sublevel and sublevel >= -8 and sublevel <= 7)
        or (layer == "OVERLAY" and sublevel == -1)
end
function Region:CreateTexture(_, layer, _, sublevel)
    Count()
    created = created + 1
    local texture = setmetatable({ layer = layer, sublevel = sublevel, kind = "Texture" }, Region)
    texture.skinLayer = IsSkinLayer(layer, sublevel)
    self.children = self.children or {}
    self.children[#self.children + 1] = texture
    return texture
end
function Region:CreateMaskTexture() return setmetatable({}, Region) end
local framesCreated = 0
_G.CreateFrame = function()
    framesCreated = framesCreated + 1
    return setmetatable({ kind = "Frame" }, Region)
end

-- The skin files bind MSUF_PixelLayoutRegion and the MSUF event bus (the combat
-- snapshot's combat edges) through MSUF.Require (Kernel/MSUF_Require.lua).
-- Owners the Classic visuals and the lane config bind at load: the shipped functions, cut out
-- of their own files by the shared source slicer (no copy of their rules).
local Slice = assert(loadfile(root .. "/.github/scripts/msuf_source_slice.lua"))()
local function Shipped(path, declaration, name)
    return assert(loadstring(Slice.Function(Slice.Read(root .. "/" .. path), declaration, path)
        .. "\nreturn " .. name, name))()
end
local PROVIDERS = {
    MSUF_PixelLayoutRegion = function(region) return region end,
    MSUF_EventBus_Register = function() end,
    MSUF_EventBus_Unregister = function() end,
    -- Runtime/MSUF_BorderStyles.lua binds the shared-media and file-asset owners at load.
    -- This harness has no LibSharedMedia and no file-asset API: no library, and a file
    -- the client cannot vouch for stays unknown (not invalid).
    MSUF_GetSharedMedia = function() return nil end,
    MSUF_IsKnownFileAsset = function() return nil end,
    -- Game/Classic/Auras/MSUF_Auras3_Visuals.lua reads the general settings through it.
    MSUF_GetGeneralDB = Shipped("MidnightSimpleUnitFrames/Kernel/MSUF_Util.lua", "local function GetGeneralDB", "GetGeneralDB"),
    -- Auras3/MSUF_Auras3_MockAuraPainter.lua binds the preview sample builders at load (the TOC
    -- loads the preview animation first). The skin-layer checks never build a sample: a call is
    -- a harness error, not a silent answer.
    MSUF_BuildPreviewAnimationAuraState = function()
        error("fixture: the preview sample builders are not modeled by this harness", 2)
    end,
    MSUF_GetPreviewAnimationAuraState = function()
        error("fixture: the preview sample builders are not modeled by this harness", 2)
    end,
}
-- The shipped namespace API (ExportPublic with the keep policy, the registries); the strict
-- Require below replaces the shipped one so only the listed providers resolve.
local RequireFixture = assert(loadfile(root .. "/tools/tests/require_fixture.lua"))()
local namespace = { MSUF_Auras3 = {} }
RequireFixture.InstallKernel(root, namespace)
function namespace.Require(name)
    return assert(PROVIDERS[name], "unexpected dependency " .. tostring(name))
end
local function Load(path)
    local source = path == "Auras3/MSUF_Auras3_IconSkins.lua" and arg[2] or (ADDON .. path)
    assert(loadfile(source))("MidnightSimpleUnitFrames", namespace)
end
Load("Runtime/MSUF_BorderStyles.lua")
Load("Auras3/MSUF_Auras3_IconShape.lua")
Load("Auras3/MSUF_Auras3_IconSkins.lua")
Load("Auras3/MSUF_Auras3_IconSkins_Catalog.lua")
local A3 = namespace.MSUF_Auras3
local Skins = assert(A3.IconSkins, "IconSkins did not load")

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local function NewButton() return setmetatable({ kind = "Frame" }, Region) end
local function Children(button, layer, sublevel)
    local list = {}
    for _, child in ipairs(button.children or {}) do
        if child.layer == layer and (sublevel == nil or child.sublevel == sublevel) then list[#list + 1] = child end
    end
    return list
end
local function ShownCount(list)
    local count = 0
    for _, region in ipairs(list) do if region.shown then count = count + 1 end end
    return count
end

local function KindChildren(owner, id, kind, visible)
    local def, pieces = assert(Skins.Get(id)), {}
    for rank, layer in ipairs(def.layers) do
        if layer.kind == kind then
            local children = Children(owner, "ARTWORK", 7 - #def.layers + rank)
            local expected = visible or (kind == "band" and 8 or (kind == "line" and 4 or 1))
            Check(ShownCount(children) == expected, id .. ": geometry probe found no " .. kind .. " layer")
            for _, child in ipairs(children) do if child.shown then pieces[#pieces + 1] = child end end
        end
    end
    return pieces
end

-- 1. Catalog and painter -------------------------------------------------------
local maxCalls = 0
local ids = {}
for _, item in ipairs(Skins.List()) do ids[#ids + 1] = item.value end
Check(ids[1] == "CUSTOM", "the dropdown must start with the user's own look")
Check(#ids == 52, "expected CUSTOM plus 51 skins, got " .. #ids)

local BUDGET = 200
-- `look` is the default skin's look (shared.iconSkinDefault): colour, own
-- colour and gloss; the aura type names the skin.
local function StyleFor(id, look)
    return Skins.Attach({ borderEnabled = true, borderThickness = 1, borderR = 1, borderG = 0, borderB = 0, borderA = 1,
        shadowEnabled = true, shadowSize = 4, shadowR = 0, shadowG = 0, shadowB = 0, shadowA = 0.8,
        signature = "base" }, { styleSkin = id }, look)
end

for i = 2, #ids do
    local id = ids[i]
    local def = Skins.Get(id)
    local button = NewButton()
    local style = StyleFor(id)
    Check(style.skin and style.skin.id == id, id .. ": Attach did not compile the skin")
    -- The user's own border and shadow exist first, as on a profile switching to a skin.
    local shape = def.shape
    A3.ApplyIconStylePreview(button, StyleFor("CUSTOM"), 32, shape)
    calls, created = 0, 0
    A3.ApplyIconStylePreview(button, style, 32, shape)
    Check(calls <= BUDGET, ("%s: %d widget calls on first paint, budget %d"):format(id, calls, BUDGET))
    if calls > maxCalls then maxCalls = calls end
    local bands, quads, lines, dims = 0, 0, 0, 0
    for _, layer in ipairs(def.layers) do
        if layer.kind == "band" then bands = bands + 1 end
        if layer.kind == "quad" or layer.kind == "atlas" then quads = quads + 1 end
        if layer.kind == "line" then lines = lines + 1 end
        if layer.kind == "dim" then dims = dims + 1 end
    end
    local previous = -9
    for rank, layer in ipairs(def.layers) do
        local sublevel = 7 - #def.layers + rank
        Check(sublevel > previous and sublevel >= -8 and sublevel <= 7, id .. ": invalid layer stack")
        local pieces = layer.kind == "band" and 8 or (layer.kind == "line" and 4 or 1)
        Check(ShownCount(Children(button, "ARTWORK", sublevel)) == pieces,
            id .. ": skin layer draw order must be bottom-to-top at rank " .. rank)
        previous = sublevel
    end
    Check(ShownCount(Children(button, "ARTWORK")) == bands * 8 + quads + lines * 4 + dims, id .. ": extra skin layers")
    Check(ShownCount(Children(button, "BACKGROUND", -7)) == 0, id .. ": the user's shadow is still shown under a skin")
    Check(ShownCount(Children(button, "BORDER", -1)) == 0, id .. ": the user's border is still shown under a skin")
    local gloss = Children(button, "OVERLAY", -1)[1]
    if style.skin.gloss then
        Check(gloss and gloss.shown and gloss.blend == "ADD", id .. ": gloss must be an additive OVERLAY(-1) texture on the owner")
    else
        Check(not (gloss and gloss.shown), id .. ": gloss shown although the skin has it off")
    end
    -- 2. An unchanged repaint writes nothing.
    calls, created = 0, 0
    A3.ApplyIconStylePreview(button, style, 32, shape)
    Check(calls == 0 and created == 0, id .. ": an unchanged repaint made " .. calls .. " widget calls")
    -- A size change repaints in place.
    created = 0
    A3.ApplyIconStylePreview(button, style, 40, shape)
    Check(created == 0, id .. ": a size change created " .. created .. " regions")
    -- Another icon shape hands the look back to the user's painter.
    A3.ApplyIconStylePreview(button, style, 32, shape == "RECTANGLE" and "CIRCLE" or "RECTANGLE")
    Check(ShownCount(Children(button, "ARTWORK")) == 0, id .. ": a skin drew on an icon shape it was not made for")
    -- CUSTOM restores the user's look, and repeating it never touches the skin again.
    A3.ApplyIconStylePreview(button, StyleFor("CUSTOM"), 32, "RECTANGLE")
    Check(ShownCount(Children(button, "ARTWORK")) == 0, id .. ": CUSTOM still shows skin bands")
    Check(ShownCount(Children(button, "BORDER", -1)) > 0, id .. ": CUSTOM did not bring back the user's border")
    skinHides = 0
    for _ = 1, 3 do A3.ApplyIconStylePreview(button, StyleFor("CUSTOM"), 32, "RECTANGLE") end
    Check(skinHides == 0, id .. ": CUSTOM repaints hid skin regions " .. skinHides .. " more times")
end
Check(framesCreated == 0, "skins must not create frames (" .. framesCreated .. " created)")

-- Every catalog texture exists in the generator manifest with the same band span
-- or quad extent, and every generated texture is used by some skin.
do
    local manifest, used = {}, {}
    local handle = assert(io.open(root .. "/tools/aura_icon_skins_manifest.tsv", "rb"))
    for line in handle:read("*a"):gmatch("[^\r\n]+") do
        local name, kind, outer, inner, extent = line:match("^([^\t]+)\t([^\t]+)\t([^\t]*)\t([^\t]*)\t([^\t]*)$")
        if name and name ~= "name" then
            manifest[name] = { kind = kind, outer = tonumber(outer), inner = tonumber(inner), extent = tonumber(extent) }
        end
    end
    handle:close()
    for i = 2, #ids do
        local def = Skins.Get(ids[i])
        for _, layer in ipairs(def.layers) do
            if layer.file then
                local entry = manifest[layer.file]
                Check(entry, ids[i] .. ": the generator does not build " .. layer.file)
                used[layer.file] = true
                if layer.kind == "band" then
                    Check(entry.kind == "band" and entry.outer == layer.outer and entry.inner == layer.inner,
                        ("%s: %s spans %s/%s in the catalog"):format(ids[i], layer.file, layer.outer, layer.inner))
                else
                    Check(entry.kind == "quad" and entry.extent == layer.extent,
                        ("%s: %s extent %s in the catalog"):format(ids[i], layer.file, tostring(layer.extent)))
                end
            end
        end
        if def.gloss and def.gloss.file then
            Check(manifest[def.gloss.file], ids[i] .. ": missing gloss texture " .. def.gloss.file)
            used[def.gloss.file] = true
        end
    end
    for name in pairs(manifest) do Check(used[name], "no skin uses the generated texture " .. name) end
end

-- Switching from a two-band skin to a one-band skin hides the second band.
do
    local button = NewButton()
    A3.ApplyIconStylePreview(button, StyleFor("SHADOW3"), 32, "RECTANGLE")
    local first, second = Children(button, "ARTWORK", 6), Children(button, "ARTWORK", 7)
    Check(ShownCount(first) == 8 and ShownCount(second) == 8, "SHADOW3 paints two ordered bands")
    local reused, spare = first[1], second[1]
    A3.ApplyIconStylePreview(button, StyleFor("SHADOW2"), 32, "RECTANGLE")
    Check(reused.shown and reused.sublevel == 7 and not spare.shown, "switching bands lost pool identity or left the spare visible")
    Check(ShownCount(Children(button, "ARTWORK", 6)) == 0 and ShownCount(Children(button, "ARTWORK", 7)) == 8,
        "switching to SHADOW2 did not retarget the reused band")
end

-- Gloss: on by the skin's default, off on request, tinted by the user colour.
do
    Check(StyleFor("SHADOW1").skin.gloss == true, "SHADOW1 shows gloss by default")
    local off = StyleFor("SHADOW1", { styleSkinGloss = false })
    Check(off.skin.gloss == false, "styleSkinGloss=false must turn the gloss off")
    local tinted = StyleFor("SHADOW1", { styleSkinGlossColor = { 1, 1, 1, 0.5 } })
    Check(tinted.skin.ga == 0.5, "the gloss colour did not reach the compiled skin")
    local button = NewButton()
    A3.ApplyIconStylePreview(button, tinted, 32, "RECTANGLE")
    local gloss = Children(button, "OVERLAY", -1)[1]
    Check(gloss.color[4] == 0.5, "the gloss texture did not take the user colour")
    A3.ApplyIconStylePreview(button, off, 32, "RECTANGLE")
    Check(not gloss.shown, "turning the gloss off did not hide it")
end

-- 3. A flat icon keeps its bands and lines inside -------------------------------
for _, id in ipairs({ "SHADOW1", "SHADOW2", "DARK2", "DARK3" }) do
    local button = NewButton()
    A3.ApplyIconStylePreview(button, StyleFor(id), 32, "RECTANGLE", 8)
    local def = Skins.Get(id)
    local outer = 0
    for _, layer in ipairs(def.layers) do
        if layer.kind == "band" and layer.outer > outer then outer = layer.outer end
    end
    local outerPx = outer > 0 and math.floor(32 * outer / 32 + 0.5) or 0
    -- At height8, the clamped four-pixel inner corners meet vertically:
    -- the eight-piece pool keeps four corners and two horizontal strips shown.
    -- The real BorderStyles painter hides the two zero-run vertical strips.
    for _, piece in ipairs(KindChildren(button, id, "band", 6)) do
        if piece.width and piece.width == piece.height then
            Check(piece.width - outerPx <= 4, ("%s: a band corner reaches %d px into an 8 px tall icon")
                :format(id, piece.width - outerPx))
        end
    end
    for _, line in ipairs(KindChildren(button, id, "line")) do
        Check((line.height or line.width or 0) <= 4, id .. ": a frame line is wider than half the flat icon")
    end
end

-- A ring quad follows the mask stretched over a 40x20 icon: 5.76u of 40 px
-- sideways, 5.12u of 20 px up and down (Px rounds to 7 and 3).
do
    local button = NewButton()
    A3.ApplyIconStylePreview(button, StyleFor("COOLDOWN_MANAGER"), 20, "ROUNDED", 20, 40)
    local quad
    for _, child in ipairs(KindChildren(button, "COOLDOWN_MANAGER", "atlas")) do
        if child.atlas == "UI-HUD-CoolDownManager-IconOverlay" and child.shown then quad = child end
    end
    Check(quad and quad.offsets and quad.offsets.TOPLEFT, "the Cooldown Manager ring did not paint on a wide icon")
    local x, y = quad.offsets.TOPLEFT[1], quad.offsets.TOPLEFT[2]
    Check(x == -7 and y == 3, ("the ring extent on a 40x20 icon is %s/%s px, expected -7/3"):format(x, y))
    Check(quad.offsets.BOTTOMRIGHT[1] == 7 and quad.offsets.BOTTOMRIGHT[2] == -3,
        "the ring's bottom-right extent does not mirror its top-left")
end

-- 4. Classic lanes that hide their icon hide the skin with it --------------------
do
    namespace.Client = { IsClassic = true }
    Load("Game/Classic/Auras/MSUF_Auras3_Visuals.lua")
    local Classic = assert(A3.ClassicVisuals, "Classic visuals did not load")
    local shared = { appearanceIconStyles = { buff = { styleSkin = "SHADOW1" } } }
    _G.MSUF_DB = { auras3 = { shared = shared } }
    local function Lane(layout)
        return Classic.EnrichUnitLane({ unit = "player", size = 32, rows = 1, spacing = 0, padding = 0 }, layout, {},
            shared, "buff")
    end
    -- Buttons.ApplyButtonLayout sizes the button before the visual layout.
    local function Layout(lane)
        local button = NewButton()
        button.Icon, button.Cooldown, button.Count = NewButton(), NewButton(), NewButton()
        button:SetSize(lane.buttonWidth or lane.size, lane.buttonHeight or lane.size)
        Classic.ApplyButtonLayout({ config = lane }, button)
        return button
    end
    local function Skinned(button) return ShownCount(Children(button, "ARTWORK", 6)) == 8 end
    local lane = Lane({})
    Check(lane.iconStyle.skin ~= nil, "Classic did not compile the skin on an icon lane")
    sizeReads = 0
    local button = Layout(lane)
    Check(Skinned(button), "Classic did not paint the skin on an icon lane")
    Check(sizeReads == 2, "a Classic skin read the button size " .. sizeReads .. " times on its first layout")
    -- A cooldown that appeared lays the button out again for the same lane.
    sizeReads, calls = 0, 0
    button._msufA3CooldownShown = true
    Classic.ApplyButtonLayout({ config = lane }, button)
    Check(sizeReads == 0, "a repeated Classic layout read the button size " .. sizeReads .. " times")
    lane = Lane({ buffShowDurationBar = true, buffDurationBarDisplay = "BAR_ONLY" })
    button = Layout(lane)
    Check(not Skinned(button), "a Classic bar-only lane still shows the skin")
    Check(not (Children(button, "OVERLAY", -1)[1] or {}).shown, "a Classic bar-only lane still shows the gloss")
    -- A skinless lane never reads the button size.
    shared.appearanceIconStyles.debuff = { styleSkin = "CUSTOM" }
    sizeReads = 0
    Layout(Classic.EnrichUnitLane({ unit = "player", size = 32, rows = 1, spacing = 0, padding = 0 }, {}, {}, shared,
        "debuff"))
    Check(sizeReads == 0, "a Classic lane without a skin read the button size")
    -- Group Spell Icons (Features AddIndicatorLane) compile through
    -- EnrichCustomLane and then take the Spell Icon style, which may switch the
    -- duration bar either way; the laid-out button follows the final lane.
    local function Indicator(placed, visual)
        return Classic.EnrichCustomLane({ unit = "party1", appearanceKind = "buff", visual = visual or "icon", size = 32 },
            { placed = placed }, nil)
    end
    local indicator = Indicator({})
    indicator.showDurationBar, indicator.durationBarDisplay = true, "BAR_ONLY"
    Check(not Skinned(Layout(indicator)), "a Spell Icon style that made the indicator bar-only kept its skin")
    indicator = Indicator({ showDurationBar = true, durationBarDisplay = "BAR_ONLY" })
    indicator.durationBarDisplay = "OVERLAY"
    Check(Skinned(Layout(indicator)), "a Spell Icon style that shows the indicator's icon lost its skin")
    for _, visual in ipairs({ "square", "bar", "number", "none" }) do
        Check(not Skinned(Layout(Indicator({}, visual))), "a " .. visual .. " indicator drew a skin around its hidden icon")
    end
    -- Unit debuff lanes keep a dispel-frame table in `visual`: still an icon.
    indicator = Indicator({})
    indicator.visual = {}
    Check(Skinned(Layout(indicator)), "a lane with a dispel-frame visual lost its skin")
end

-- 5. Signatures -------------------------------------------------------------------
do
    local custom = Skins.Attach({ signature = "B:SOLID:x" }, { styleSkin = "CUSTOM" })
    Check(custom.signature == "B:SOLID:x" and custom.skin == nil, "CUSTOM changed the style signature")
    local unknown = Skins.Attach({ signature = "B:SOLID:x" }, { styleSkin = "MISSING" })
    Check(unknown.signature == "B:SOLID:x" and unknown.skin == nil, "an unknown skin id must fall back to CUSTOM")
    local legacy = Skins.Attach({ signature = "B:SOLID:x" }, {})
    Check(legacy.signature == "B:SOLID:x", "a profile without skin keys changed the style signature")
    local skinned = Skins.Attach({ signature = "B:SOLID:x" }, { styleSkin = "DARK2" })
    Check(skinned.signature:find("^B:SOLID:x:K:DARK2:"), "the skin signature was not appended: " .. skinned.signature)
    local recolored = Skins.Attach({ signature = "B:SOLID:x" }, { styleSkin = "DARK2" }, { styleSkinColor = { 1, 0, 0, 1 } })
    Check(recolored.signature ~= skinned.signature, "a skin colour change must change the signature")
    -- Like default: DEFAULT and a missing styleSkin take the default skin, an
    -- own skin or CUSTOM overrides it, and the look always comes from the default.
    local defaults = { styleSkin = "SHADOW2", styleSkinColor = { 0, 0, 0, 0.5 } }
    Check(Skins.Attach({}, { styleSkin = "DEFAULT" }, defaults).skin.id == "SHADOW2", "DEFAULT did not take the default skin")
    Check(Skins.Attach({}, {}, defaults).skin.id == "SHADOW2", "a missing styleSkin did not take the default skin")
    Check(Skins.Attach({}, { styleSkin = "DARK1" }, defaults).skin.id == "DARK1", "an own skin did not override the default")
    Check(Skins.Attach({}, { styleSkin = "CUSTOM" }, defaults).skin == nil, "No skin did not override the default")
    Check(Skins.Attach({}, { styleSkin = "DARK1" }, defaults).skin.a == 0.5, "an own skin did not take the default look")
    Check(Skins.EffectiveId({ styleSkin = "DEFAULT" }, defaults) == "SHADOW2" and Skins.EffectiveId({}, nil) == "CUSTOM",
        "EffectiveId does not follow the default")
    for _, item in ipairs(Skins.List()) do
        Check(item.value == "CUSTOM" or item.family ~= nil, item.value .. " has no gallery family")
    end
end

-- 6. Cold path only -----------------------------------------------------------------
for _, path in ipairs({ "Auras3/MSUF_Auras3_IconSkins.lua", "Auras3/MSUF_Auras3_IconSkins_Catalog.lua" }) do
    local file = assert(io.open(ADDON .. path, "rb"))
    local source = file:read("*a"):gsub("%-%-[^\n]*", "")
    file:close()
    for _, token in ipairs({ "RegisterEvent", "SetScript", "HookScript", "hooksecurefunc", "C_Timer",
        "OnUpdate", "RunNextFrame", "UNIT_AURA", "CreateFrame" }) do
        Check(not source:find(token, 1, true), path .. " must stay cold path; found " .. token)
    end
end

-- 7. Mock previews (Auras3/MSUF_Auras3_MockAuraPainter.lua) ----------------------
do
    Load("Auras3/MSUF_Auras3_MockAuraPainter.lua")
    local Painter = assert(A3.MockAuraPainter, "the mock aura painter did not load")
    A3.GetDurationBarColor = A3.GetDurationBarColor or function() return 1, 1, 1 end
    local icon = NewButton()
    local swipe, bar = Painter.NewSwipe(icon), Painter.NewDurationBar(icon)
    -- Without a skin the regions keep the frozen preview layers.
    Check(swipe.layer == "ARTWORK" and swipe.sublevel == 1, "a new preview swipe left its frozen ARTWORK 1 layer")
    Check(bar.layer == "OVERLAY" and bar.sublevel == nil, "a new preview duration bar left its frozen OVERLAY layer")
    local art = setmetatable({}, Region)
    Painter.Art(icon, art, setmetatable({}, Region), swipe, 134400, 100, nil, nil, "RECTANGLE", false,
        StyleFor("CUSTOM"), 20, nil)
    Check(swipe.layer == "ARTWORK" and swipe.sublevel == 1, "an unskinned preview moved its swipe")
    -- A square-cropped (width/height nil) 40x20 icon sizes its skin from skinWidth/skinHeight.
    Painter.Art(icon, art, setmetatable({}, Region), swipe, 134400, 100, nil, nil, "ROUNDED", false,
        StyleFor("COOLDOWN_MANAGER"), 20, nil, 40, 20)
    -- Live order: skin (ARTWORK 5-7), gloss (OVERLAY -1), dispel border and the
    -- duration bar (OVERLAY 0-2) < cooldown swipe < text (OVERLAY 6/7).
    Check(swipe.layer == "OVERLAY" and swipe.sublevel == 4, "a skinned preview did not lift its swipe above the skin")
    Check(swipe.sublevel < 6, "the preview swipe must stay below the stack and timer text (OVERLAY 6/7)")
    Painter.Art(icon, art, setmetatable({}, Region), swipe, 134400, 100, nil, nil, "RECTANGLE", false,
        StyleFor("CUSTOM"), 20, nil)
    Check(swipe.layer == "ARTWORK" and swipe.sublevel == 1, "a preview that lost its skin kept the lifted swipe")
    Painter.Art(icon, art, setmetatable({}, Region), swipe, 134400, 100, nil, nil, "ROUNDED", false,
        StyleFor("COOLDOWN_MANAGER"), 20, nil, 40, 20)
    local quad
    for _, child in ipairs(KindChildren(icon, "COOLDOWN_MANAGER", "atlas")) do
        if child.atlas == "UI-HUD-CoolDownManager-IconOverlay" and child.shown then quad = child end
    end
    Check(quad and quad.offsets and quad.offsets.TOPLEFT, "the preview did not paint the Cooldown Manager ring")
    Check(quad.offsets.TOPLEFT[1] == -7 and quad.offsets.TOPLEFT[2] == 3,
        "a preview skin on a 40x20 icon was not sized from the icon's real width and height")
    -- A skin made for another icon shape draws nothing, so the swipe keeps its
    -- frozen layer, under the duration bar and the dispel border.
    local _, skinned = Painter.Art(icon, art, setmetatable({}, Region), swipe, 134400, 100, nil, nil, "CIRCLE", false,
        StyleFor("SHADOW1"), 20, nil)
    Check(skinned == false and ShownCount(Children(icon, "ARTWORK")) == 0, "a preview drew a skin on another icon shape")
    Check(swipe.layer == "ARTWORK" and swipe.sublevel == 1, "a skin rejected by the icon shape lifted the preview swipe")
end

-- 8. Only runtime compiles switch the live painters --------------------------------
do
    local fresh = { MSUF_Auras3 = {} }
    RequireFixture.InstallKernel(root, fresh)
    fresh.Require = namespace.Require
    local function LoadFresh(path) assert(loadfile(ADDON .. path))("MidnightSimpleUnitFrames", fresh) end
    LoadFresh("Runtime/MSUF_BorderStyles.lua")
    LoadFresh("Auras3/MSUF_Auras3_IconShape.lua")
    LoadFresh("Auras3/MSUF_Auras3_IconSkins.lua")
    LoadFresh("Auras3/MSUF_Auras3_IconSkins_Catalog.lua")
    local FA3 = fresh.MSUF_Auras3
    local plain = FA3.ApplyIconStylePreview
    local switched = 0
    FA3.IconShape.OnSkinsLive(function() switched = switched + 1 end)
    -- The gallery compiles every skin and the workbench its own; both paint.
    for i = 2, #ids do
        local style = FA3.IconSkins.AttachPreview({}, { styleSkin = ids[i] })
        Check(FA3.ApplyIconStyleSkinned(NewButton(), style, 32, Skins.Get(ids[i]).shape) == true,
            ids[i] .. ": the preview painter did not draw the skin")
    end
    Check(FA3.ApplyIconStylePreview == plain and switched == 0, "a preview compile switched the live painters")
    FA3.IconSkins.Attach({}, { styleSkin = "CUSTOM" })
    Check(FA3.ApplyIconStylePreview == plain and switched == 0, "a runtime compile without a skin switched the live painters")
    FA3.IconSkins.Attach({}, { styleSkin = "DARK1" })
    Check(FA3.ApplyIconStylePreview == FA3.ApplyIconStyleSkinned and switched == 1,
        "a runtime compile with a skin did not switch the live painters")
    FA3.IconSkins.Attach({}, { styleSkin = "DARK2" })
    local late = 0
    FA3.IconShape.OnSkinsLive(function() late = late + 1 end)
    Check(switched == 1 and late == 1, "the live switch must run once per owner, also for an owner registered later")
    -- The switch lasts for the session: a skin removed later is hidden on the
    -- live button it was drawn on, and the user's border comes back.
    local liveButton = NewButton()
    FA3.ApplyIconStylePreview(liveButton, FA3.IconSkins.Attach({}, { styleSkin = "DARK2" }), 32, "RECTANGLE")
    Check(ShownCount(Children(liveButton, "ARTWORK", 6)) > 0, "the live button did not draw the skin")
    local plainStyle = FA3.IconSkins.Attach({ borderEnabled = true, borderThickness = 1, borderR = 1, borderG = 0,
        borderB = 0, borderA = 1, shadowEnabled = false, shadowSize = 4, shadowR = 0, shadowG = 0, shadowB = 0,
        shadowA = 0 }, { styleSkin = "CUSTOM" })
    FA3.ApplyIconStylePreview(liveButton, plainStyle, 32, "RECTANGLE")
    Check(FA3.ApplyIconStylePreview == FA3.ApplyIconStyleSkinned, "the live painters switched back during the session")
    Check(ShownCount(Children(liveButton, "ARTWORK", 6)) == 0 and ShownCount(Children(liveButton, "BORDER", -1)) > 0,
        "a removed skin stayed on the live button, or its own border did not come back")
end

-- 9. Outset ------------------------------------------------------------------
-- The painted frame's reach past the icon, read from the regions the painter
-- anchored to the owner's corners; soft shadow art does not count.
local function PaintedOutset(button)
    local x, y = 0, 0
    for _, child in ipairs(button.children or {}) do
        local art = tostring(child.texture or "")
        if child.shown and not art:find("msuf_skin_shadow", 1, true) and child.offsets then
            local o = child.offsets
            if o.TOPLEFT and o.TOPLEFT[1] then x, y = math.max(x, -o.TOPLEFT[1]), math.max(y, o.TOPLEFT[2]) end
            if o.TOPRIGHT and o.TOPRIGHT[1] then x, y = math.max(x, o.TOPRIGHT[1]), math.max(y, o.TOPRIGHT[2]) end
            if o.BOTTOMLEFT and o.BOTTOMLEFT[1] then x, y = math.max(x, -o.BOTTOMLEFT[1]), math.max(y, -o.BOTTOMLEFT[2]) end
            if o.BOTTOMRIGHT and o.BOTTOMRIGHT[1] then x, y = math.max(x, o.BOTTOMRIGHT[1]), math.max(y, -o.BOTTOMRIGHT[2]) end
        end
    end
    return x, y
end
local framed = 0
for i = 2, #ids do
    local id = ids[i]
    local def = Skins.Get(id)
    for _, size in ipairs({ { 36, 36 }, { 37, 37 }, { 44, 22 } }) do
        local button = NewButton()
        Skins.Paint(button, StyleFor(id), size[1], def.shape, size[2], size[1])
        local px, py = PaintedOutset(button)
        local ox, oy = Skins.Outset(id, size[1], size[2])
        Check(ox == px and oy == py, ("%s at %dx%d: Outset %s,%s but the frame reaches %s,%s"):format(id, size[1], size[2],
            tostring(ox), tostring(oy), tostring(px), tostring(py)))
        if size[1] == 36 and ox > 0 then framed = framed + 1 end
    end
end
Check(framed >= 10, "only " .. framed .. " skins draw a frame past the icon; the Outset pin lost its subjects")
local sx, sy = Skins.Outset("SHADOW1", 36)
Check(sx == 0 and sy == 0, "a soft shadow counts as frame")
Check(select(1, Skins.Outset(Skins.Get("SHADOW1"), 36)) == 0 and select(1, Skins.Outset(nil, 36)) == 0
    and select(1, Skins.Outset("DARK1", 0)) == 0, "Outset without a skin or a size must be 0")
Check(Skins.Outset(StyleFor("DARK1").skin, 36) == Skins.Outset("DARK1", 36), "a compiled skin and its id differ")

-- A cached line and band exchange ranks without recreating regions.
do
    local line = { kind = "line", px = 1, place = "inside" }
    local band = { kind = "band", file = "msuf_skin_shadow_hard", outer = 0, inner = 13 }
    Skins.Register("SMOKE_LINE_BEHIND", { layers = { line, band } })
    Skins.Register("SMOKE_LINE_ABOVE", { layers = { band, line } })
    local button = NewButton()
    A3.ApplyIconStylePreview(button, StyleFor("SMOKE_LINE_BEHIND"), 32, "RECTANGLE")
    local reused = assert(KindChildren(button, "SMOKE_LINE_BEHIND", "line")[1])
    created = 0
    A3.ApplyIconStylePreview(button, StyleFor("SMOKE_LINE_ABOVE"), 32, "RECTANGLE")
    Check(created == 0 and reused.shown and reused.sublevel == 7, "cached line did not retarget its stack rank in place")
    Check(#KindChildren(button, "SMOKE_LINE_ABOVE", "line") == 4, "cached line geometry lost a side")
    Check(#KindChildren(button, "SMOKE_LINE_ABOVE", "band") == 8, "cached band geometry lost a piece")
end

print(("aura_icon_skin_paint_smoke: OK (%d skins, first paint at most %d widget calls, %d framed outsets)")
    :format(#ids - 1, maxCalls, framed))
