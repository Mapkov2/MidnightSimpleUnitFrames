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
-- Kernel/MSUF_Util.lua loads before the runtime in every TOC and provides the
-- combat-state source the layer visibility asks.
for _, relative in ipairs({
    "MidnightSimpleUnitFrames/Kernel/MSUF_Util.lua",
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

-- Exercise the complete runtime against the real shared NPC resolver. The
-- health configuration deliberately disables every NPC colour option.
local function NPCTypeLayers(flavor)
    local World = assert(loadfile(repo .. "/tools/tests/client_world.lua"))()
    local world = World.New(repo, flavor)
    local env = world.env
    local Secrets = assert(loadfile(repo .. "/tools/tests/classpower_secrets.lua"))()
    env.issecretvalue = Secrets.IsSecret
    local units = {
        player = { player = true, class = "MAGE", level = 80 },
        target = { classification = "elite", mana = true, level = 80 },
        focus = { classification = "elite", mana = false, level = 80 },
        boss2 = { classification = "worldboss", level = -1 },
        boss3 = { classification = "elite", level = 81 },
    }
    local function State(unit) return units[unit] or {} end
    env.UnitExists = function(unit) return units[unit] ~= nil end
    env.UnitIsPlayer = function(unit) return State(unit).player or false end
    env.UnitClass = function(unit) return "Class", State(unit).class or "WARRIOR" end
    env.UnitClassification = function(unit) return State(unit).classification or "normal" end
    env.UnitHasPowerType = function(unit) return State(unit).mana or false end
    env.UnitEffectiveLevel = function(unit) return State(unit).level or 80 end
    env.UnitIsBossMob = function(unit) return State(unit).classification == "worldboss" end
    env.UnitIsLieutenant = function() return false end
    env.UnitSelectionType = function(unit) return State(unit).neutral and 2 or 0 end
    env.UnitReaction = function(unit) return State(unit).neutral and 4 or 2 end
    env.UnitIsDeadOrGhost = function(unit) return State(unit).dead or false end
    env.UnitCanAttack = function(unit, target) return State(target or unit).friendly ~= true end
    env.UnitCanAssist = function(unit, target) return State(target or unit).friendly == true end
    env.IsInInstance = function() return false, "none" end
    world:Boot()
    local failure = world:FirstFailure()
    assert(not failure, failure and (failure.file .. ": " .. failure.message))
    env.MSUF_EnsureDB(true)
    world.core.UF.Config.Refresh()
    local db, core = env.MSUF_DB, world.core
    db.general.npcColorMode = "reaction"
    db.general.npcTypeColorBar, db.general.npcTypeColorText = false, false
    db.general.npcTypeTarget, db.general.npcTypeFocus, db.general.npcTypeBoss = false, false, false
    local colors = {
        npcCaster = { r = 0.12, g = 0.34, b = 0.56 },
        npcMelee = { r = 0.62, g = 0.23, b = 0.14 },
        npcBoss = { r = 0.27, g = 0.58, b = 0.19 },
        npcMiniboss = { r = 0.38, g = 0.29, b = 0.71 },
        npcRegular = { r = 0.42, g = 0.51, b = 0.63 },
        neutral = { r = 0.65, g = 0.41, b = 0.23 },
        friendly = { r = 0.13, g = 0.67, b = 0.45 },
        enemy = { r = 0.78, g = 0.21, b = 0.32 },
    }
    db.npcColors = colors
    db.classColors = { MAGE = { r = 0.16, g = 0.37, b = 0.68 } }
    core.UF.Config.Refresh()
    local runtime, frames = core.TextureLayer, {}
    core.UF.frames = frames
    for _, unit in ipairs({ "player", "target", "focus", "boss2", "boss3" }) do
        local key = unit:match("^boss") and "boss" or unit
        local conf = db[key]
        assert(conf, "missing fixture config " .. key)
        for _, prefix in ipairs({ "texLayer", "texLayer2", "texLayer3" }) do
            conf[prefix .. "Enabled"] = true
            conf[prefix .. "ColorMode"] = "CLASS_NPC"
            conf[prefix .. "Visibility"] = "ALWAYS"
            conf[prefix .. "TargetOnly"] = false
            conf[prefix .. "HealthCondition"] = "ANY"
            conf[prefix .. "HealthLowAlphaEnabled"] = false
            conf[prefix .. "SourceMode"] = "CUSTOM"
            conf[prefix .. "CustomTexturePath"] = GLOW
            conf[prefix .. "ColorR"], conf[prefix .. "ColorG"], conf[prefix .. "ColorB"] = 0.8, 0.7, 0.6
        end
        local frame = env.CreateFrame("Frame", nil, env.UIParent)
        frame:SetSize(220, 35)
        frame.MSUFUnitKey, frame.configKey = unit, key
        frame.MSUFSpec = { key = key, health = { colorMode = "BLACK", npcColorMode = "reaction", npcTypeColorBar = false }, text = {} }
        frame.hpBar = env.CreateFrame("StatusBar", nil, frame)
        frame.hpBar:SetStatusBarColor(0, 0, 0)
        frames[unit] = frame
    end
    local function CheckColor(unit, color)
        local hpColor = frames[unit].hpBar.color
        assert(hpColor[1] == 0 and hpColor[2] == 0 and hpColor[3] == 0, "texture mode recoloured the HP bar")
        for slot = 1, 3 do
            local holder = assert(frames[unit]._msufTexLayers[slot])
            local tint = holder.tex.gradient and holder.tex.gradient.from
            assert(tint and tint.r == color.r and tint.g == color.g and tint.b == color.b,
                flavor .. " " .. unit .. " slot " .. slot .. ": wrong NPC/class tint")
        end
    end
    runtime.Refresh()
    assert(env.MSUF_DB == db, "profile changed during fixture")
    assert(core.UF.frames == frames, "runtime changed fixture frames")
    CheckColor("player", db.classColors.MAGE)
    CheckColor("target", colors.npcCaster)
    CheckColor("focus", colors.npcMelee)
    CheckColor("boss2", colors.npcBoss)
    CheckColor("boss3", colors.npcMiniboss)
    -- A texture request must not change the health resolver's reaction mode.
    assert(core.UFBarTextCommon.UnitNPCKind(frames.target, "target", frames.target.MSUFSpec) == "enemy",
        "texture NPC type contaminated the health colour cache")
    assert(db.general.npcColorMode == "reaction" and db.general.npcTypeColorBar == false,
        "texture mode changed health settings")
    units.target.mana = false
    world:FireEvent("PLAYER_TARGET_CHANGED")
    CheckColor("target", colors.npcMelee)
    units.target.mana = true
    world:FireEvent("UNIT_DISPLAYPOWER", "target")
    CheckColor("target", colors.npcCaster)
    units.target.neutral = true
    world:FireEvent("UNIT_FACTION", "target")
    CheckColor("target", colors.neutral)
    units.target.neutral, units.target.classification = false, "normal"
    world:FireEvent("UNIT_CLASSIFICATION_CHANGED", "target")
    CheckColor("target", colors.npcRegular)
    units.boss2.friendly = true
    world:FireEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
    CheckColor("boss2", colors.friendly)
    colors.npcRegular.r = 0.73
    core.UF.Config.Refresh()
    runtime.Refresh("target")
    CheckColor("target", colors.npcRegular)
    -- Missing units and secret identity retain the configured layer tint.
    local secret = Secrets.New("boolean")
    units.target.player = secret
    local stop = Secrets.Watch(repo .. "/MidnightSimpleUnitFrames/UnitFrames/Effects/MSUF_UF_TextureLayer.lua", { strict = true })
    runtime.Refresh("target")
    assert(#stop() == 0, "CLASS_NPC tested a secret identity before guarding it")
    CheckColor("target", { r = 0.8, g = 0.7, b = 0.6 })
    units.target.player, units.target.class = true, Secrets.New("string")
    stop = Secrets.Watch(repo .. "/MidnightSimpleUnitFrames/UnitFrames/Effects/MSUF_UF_TextureLayer.lua", { strict = true })
    runtime.Refresh("target")
    assert(#stop() == 0, "CLASS_NPC used a secret player class before guarding it")
    CheckColor("target", { r = 0.8, g = 0.7, b = 0.6 })
    units.target = nil
    runtime.Refresh("target")
    CheckColor("target", { r = 0.8, g = 0.7, b = 0.6 })
    for _, key in ipairs({ "player", "target", "focus", "boss" }) do
        for _, prefix in ipairs({ "texLayer", "texLayer2", "texLayer3" }) do
            db[key][prefix .. "ColorMode"] = "CUSTOM"
        end
    end
    runtime.Refresh()
    for _, frame in ipairs(world.widgets.frames) do
        local handler = frame:GetScript("OnEvent")
        if handler and debug.getinfo(handler, "S").source:find("MSUF_UF_TextureLayer.lua", 1, true) then
            assert(not frame:IsEventRegistered("UNIT_FACTION") and not frame:IsEventRegistered("UNIT_DISPLAYPOWER"),
                "disabling CLASS_NPC retained NPC colour event subscriptions")
            assert(frame:GetScript("OnUpdate") == nil, "NPC colour driver uses polling")
        end
    end
end
for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do NPCTypeLayers(flavor) end
print("classic texture layer highlight smoke passed: NPC palette, HP independence, lifecycle and three slots on five clients")
