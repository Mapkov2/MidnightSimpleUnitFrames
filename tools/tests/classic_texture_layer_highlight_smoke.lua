-- Texture layer "Highlight" contract for the unified page and runtime that every
-- client loads. Turning the highlight on must draw only the highlight glow,
-- whatever source the layer used before. A fresh layer's SharedMedia source
-- ignores custom file paths, so the old toggle drew the bar texture instead of
-- the glow. Turning the highlight off returns the layer to that fresh
-- SharedMedia source.
-- Plain Lua 5.1; arg[1] is the repo root.
local repo = assert(arg[1], "repo root required")

local BAR_TEXTURE = "SMOKE_BAR_TEXTURE"
local GLOW = "Interface\\PETBATTLES\\PetBattle-SelectedPetGlow"
local PACK_PATH = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\TextureLayers\\msuf_texlayer_midnight_rail.png"

MSUF_GetBarTexture = function() return BAR_TEXTURE end
MSUF_ResolveStatusbarTextureKey = function(key) return "SharedMedia:" .. key end
C_Texture = { GetAtlasInfo = function(atlas) return atlas == "UI-HUD-UnitFrame-Player-PortraitOn" and {} or nil end }
CreateFrame = function()
    local frame = {}
    return setmetatable(frame, { __index = function() return function() end end })
end

local namespace = {
    ExportPublic = function(name, value) _G[name] = value end,
    MSUF2 = {
        ValueTextPairs = function() return {} end,
        WordList = function() return {} end,
    },
}
for _, relative in ipairs({
    "MidnightSimpleUnitFrames/UnitFrames/Effects/MSUF_UF_TextureLayer.lua",
    "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitTextureLayer.lua",
}) do
    local chunk = assert(loadfile(repo .. "/" .. relative))
    chunk("MidnightSimpleUnitFrames", namespace)
end

local resolve = assert(namespace.TextureLayer and namespace.TextureLayer.ResolveLayerTexture,
    "runtime TextureLayer.ResolveLayerTexture missing")
local resolveAtlas = assert(namespace.TextureLayer and namespace.TextureLayer.ResolveLayerAtlas,
    "runtime TextureLayer.ResolveLayerAtlas missing")
local apply = assert(namespace.MSUF2.ApplyTextureLayerHighlightConfig,
    "Options M.ApplyTextureLayerHighlightConfig missing")

-- A layer as the Classic defaults create it, plus the given overrides.
local function Layer(overrides)
    local conf = {
        texLayerEnabled = true, texLayerTexture = "", texLayerCustomTexturePath = "",
        texLayerSourceMode = "SHAREDMEDIA", texLayerAlpha = 1, texLayerColorMode = "CUSTOM",
        texLayerCropMode = "FULL", texLayerBlendMode = "BLEND",
    }
    for key, value in pairs(overrides or {}) do conf[key] = value end
    return conf
end

do
    local conf = Layer({ texLayerSourceMode = "ATLAS", texLayerAtlas = "UI-HUD-UnitFrame-Player-PortraitOn" })
    assert(resolveAtlas(conf, "texLayer") == "UI-HUD-UnitFrame-Player-PortraitOn",
        "native Blizzard atlas source did not resolve")
    conf.texLayerAtlas = "missing-atlas"
    assert(resolveAtlas(conf, "texLayer") == nil, "missing atlas did not fail closed")
end

local function AssertOnlyGlow(label, conf)
    assert(resolve(conf, "texLayer") == GLOW,
        label .. ": the layer draws " .. tostring(resolve(conf, "texLayer")) .. " instead of only the highlight")
    assert(conf.texLayerSourceMode == "CUSTOM", label .. ": source " .. tostring(conf.texLayerSourceMode))
    assert(conf.texLayerTexture == "" and conf.texLayerBlendMode == "ADD" and conf.texLayerCropMode == "BOTTOM_HALF",
        label .. ": highlight preset not applied")
    assert(apply(conf, "texLayer", true) == false, label .. ": the highlight does not read as on")
end

-- A fresh layer: before the fix this drew the bar texture.
do
    local conf = Layer()
    assert(resolve(conf, "texLayer") == BAR_TEXTURE, "fresh: a fresh layer should draw the bar texture")
    assert(apply(conf, "texLayer", true) == true, "fresh: enabling the highlight changed nothing")
    AssertOnlyGlow("fresh", conf)
    assert(conf.texLayerAlpha == 0.05 and conf.texLayerColorR == 1 and conf.texLayerColorG == 0.82,
        "fresh: first highlight appearance not initialized")

    -- Turning it off returns the fresh SharedMedia layer.
    assert(apply(conf, "texLayer", false) == true, "fresh/off: disabling the highlight changed nothing")
    assert(conf.texLayerSourceMode == "SHAREDMEDIA" and conf.texLayerCustomTexturePath == ""
        and conf.texLayerBlendMode == "BLEND" and conf.texLayerCropMode == "FULL", "fresh/off: layer not reset")
    assert(resolve(conf, "texLayer") == BAR_TEXTURE, "fresh/off: the layer does not draw its fresh texture")
    assert(apply(conf, "texLayer", false) == false, "fresh/off: a second disable changed the layer again")
end

-- Every other source is replaced by the glow as well.
for label, overrides in pairs({
    sharedmedia = { texLayerTexture = "Smooth" },
    pack = { texLayerSourceMode = "PACK", texLayerCustomTexturePath = PACK_PATH },
    custom = { texLayerSourceMode = "CUSTOM", texLayerCustomTexturePath = "Interface\\Custom\\Art" },
    atlas = { texLayerSourceMode = "ATLAS", texLayerAtlas = "UI-HUD-UnitFrame-Player-PortraitOn" },
}) do
    local conf = Layer(overrides)
    assert(resolve(conf, "texLayer") ~= GLOW, label .. ": the layer already draws the glow")
    assert(apply(conf, "texLayer", true) == true, label .. ": enabling the highlight changed nothing")
    AssertOnlyGlow(label, conf)
end

-- A layer saved by the old toggle kept the SharedMedia source and never showed
-- the glow: it reads as off, and turning it on repairs it.
do
    local conf = Layer()
    apply(conf, "texLayer", true)
    conf.texLayerSourceMode = "SHAREDMEDIA"
    assert(resolve(conf, "texLayer") == BAR_TEXTURE, "legacy: the old saved state should draw the bar texture")
    assert(apply(conf, "texLayer", false) == false, "legacy: a layer that never showed the glow read as on")
    assert(apply(conf, "texLayer", true) == true, "legacy: enabling did not repair the layer")
    AssertOnlyGlow("legacy", conf)
end

print("classic texture layer highlight smoke passed")
