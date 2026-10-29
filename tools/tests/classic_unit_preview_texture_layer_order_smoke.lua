-- classic_unit_preview_texture_layer_order_smoke.lua <repoRoot> <flavor>
--
-- Every client (Midnight, WoW Forever, Vanilla, TBC and Mists) loads the
-- Retail-named unit preview render (Preview/MSUF_Menu2_UnitPreview_Render.lua).
-- Preview.Refresh stamps texture layers once the health bar, the power bar and
-- the portrait have their geometry for this refresh, as Factory.Apply does on
-- live frames. A layer anchored to Player Power or to the Portrait must
-- therefore follow what this refresh shows, not what the previous refresh left
-- behind. (The file name predates the Mainline fix; it runs on clients+Forever.)
--
-- The smoke boots the flavor's whole shipped core and Options graph through
-- tools/tests/client_world.lua, builds the real unit preview and drives its
-- real Refresh twice per case: the first refresh shows the opposite power bar
-- and portrait state, the second one is measured.
--
-- Plain Lua 5.1 with the repo root and a client matrix Suffix (or Forever) as arguments.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg and arg[2], "flavor required (a client matrix Suffix or Forever)")
assert(rawget(_G, "MSUF_Auras3TestLoader") == nil,
    "classic_unit_preview_texture_layer_order_smoke boots the real TOC graph; run it with plain Lua 5.1")

local World = assert(loadfile(root .. "/tools/tests/client_world.lua"),
    "classic_unit_preview_texture_layer_order_smoke: tools/tests/client_world.lua is missing")()

local function Check(condition, message)
    if not condition then error(flavor .. ": " .. message, 2) end
end

local world = World.New(root, flavor)
local liveUnits = {}
local function Live(unit) return liveUnits[unit] or {} end
world.env.UnitExists = function(unit) return liveUnits[unit] ~= nil end
world.env.UnitIsPlayer = function(unit) return Live(unit).player == true end
world.env.UnitClass = function(unit) return "Class", Live(unit).class or "WARRIOR" end
world.env.UnitClassification = function(unit) return Live(unit).classification or "normal" end
world.env.UnitHasPowerType = function(unit) return Live(unit).mana == true end
world.env.UnitPowerType = function(unit) return Live(unit).mana and 0 or 1, Live(unit).mana and "MANA" or "RAGE" end
world.env.UnitEffectiveLevel = function(unit) return Live(unit).level or 80 end
world.env.UnitIsBossMob = function(unit) return Live(unit).classification == "worldboss" end
world.env.UnitIsLieutenant = function(unit) return Live(unit).lieutenant == true end
world.env.UnitSelectionType = function(unit) return Live(unit).neutral and 2 or 0 end
world.env.UnitReaction = function(unit) return Live(unit).neutral and 4 or 2 end
world.env.UnitIsDeadOrGhost = function() return false end
world.env.UnitCanAttack = function() return true end
world.env.UnitCanAssist = function() return false end
world.env.IsInInstance = function() return false, "none" end
world:Boot()
local failure = world:FirstFailure()
Check(failure == nil, "load failed in " .. tostring(failure and failure.file) .. ": " .. tostring(failure and failure.message))

-- Widget calls the preview makes that the shared stubs do not model.
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
env.MSUF_EnsureDB(true)
MSUF.UF.Config.Refresh()
local Preview = MSUF.UFPreview
Check(type(Preview) == "table" and type(Preview._BuildPreview) == "function", "no unit preview builder")
local refreshSource = debug.getinfo(Preview.Refresh, "S").source
Check(refreshSource:find("MSUF_Menu2_UnitPreview_Render.lua", 1, true) ~= nil,
    "Preview.Refresh does not come from the unit preview render: " .. refreshSource)

local parent = env.CreateFrame("Frame", nil, env.UIParent)
parent:SetSize(900, 400)
local panel = env.CreateFrame("Frame", nil, env.UIParent)
local currentKey = "player"
panel._msufGetCurrentKey = function() return currentKey end
local box = Preview._BuildPreview(parent, panel, 900, 400)
Check(type(box) == "table" and type(box.mock) == "table", "the unit preview did not build")
box:Show()
box.canvas:SetSize(400, 200)
local mock = box.mock
Check(type(mock.texLayers) == "table" and mock.texLayers[1] and mock.texLayers[2], "the preview has no texture layer holders")

local player = env.MSUF_DB.player
local function Refresh()
    MSUF.UF.Config.Refresh()
    Preview.Refresh(box, "CLASSIC_TEXTURE_LAYER_ORDER_SMOKE")
end
local function Show(powerAndPortrait)
    player.showPowerBar = powerAndPortrait
    player.portraitMode = powerAndPortrait and "LEFT" or "OFF"
end
local function Anchor(holder)
    local _, relativeTo = holder:GetPoint(1)
    return relativeTo
end
local function Shown(region) return region ~= nil and region:IsShown() == true end

-- Layer 1 follows Player Power, layer 2 the Portrait, both sized by their target.
player.texLayerEnabled = true
player.texLayerAnchorTarget = "POWER"
player.texLayerAnchor = "LEFT"
player.texLayer2Enabled = true
player.texLayer2AnchorTarget = "PORTRAIT"
player.texLayer2Anchor = "CENTER"
for _, prefix in ipairs({ "texLayer", "texLayer2" }) do
    player[prefix .. "Width"] = 0
    player[prefix .. "Height"] = 0
end

-- 1. The previous refresh hid the power bar and the portrait; this one shows them.
Show(false)
Refresh()
Check(not Shown(mock.powerBG) and not Shown(mock.portrait), "harness: the first refresh still shows power or the portrait")
Show(true)
Refresh()
Check(Shown(mock.powerBG) and Shown(mock.portrait), "harness: the measured refresh shows no power bar or portrait")
Check(Anchor(mock.texLayers[1]) == mock.powerBG,
    "a texture layer anchored to Player Power follows the previous refresh instead of the power bar shown now")
Check(Anchor(mock.texLayers[2]) == mock.portrait,
    "a texture layer anchored to the Portrait follows the previous refresh instead of the portrait shown now")

-- 2. The previous refresh showed both; this one hides them, so both layers
-- fall back to the frame instead of a bar or portrait that is gone.
Show(false)
Refresh()
Check(not Shown(mock.powerBG) and not Shown(mock.portrait), "harness: the measured refresh still shows power or the portrait")
Check(Anchor(mock.texLayers[1]) == mock,
    "a texture layer stays on the Player Power bar this refresh hid")
Check(Anchor(mock.texLayers[2]) == mock,
    "a texture layer stays on the Portrait this refresh hid")

-- The same real preview lifecycle paints all three slots with the shared
-- class/NPC palette even when health remains black and its NPC flags are off.
do
    local db, runtime = env.MSUF_DB, MSUF.TextureLayer
    local colors = {
        npcCaster = { r = 0.12, g = 0.34, b = 0.56 },
        npcMiniboss = { r = 0.38, g = 0.29, b = 0.71 },
        npcBoss = { r = 0.27, g = 0.58, b = 0.19 },
        neutral = { r = 0.65, g = 0.41, b = 0.23 },
    }
    db.npcColors = colors
    db.classColors = { MAGE = { r = 0.16, g = 0.37, b = 0.68 } }
    db.general.npcColorMode = "reaction"
    db.general.npcTypeColorBar, db.general.npcTypeColorText = false, false
    db.general.npcTypeTarget, db.general.npcTypeBoss = false, false
    db.general.barMode = "dark"
    db.general.darkBarR, db.general.darkBarG, db.general.darkBarB = 0, 0, 0
    local prefixes = { "texLayer", "texLayer2", "texLayer3" }
    for _, key in ipairs({ "player", "target", "boss" }) do
        local conf = db[key]
        conf.healthColorMode = "DARK"
        for _, prefix in ipairs(prefixes) do
            conf[prefix .. "Enabled"] = true
            conf[prefix .. "ColorMode"] = "CLASS_NPC"
            conf[prefix .. "SourceMode"] = "CUSTOM"
            conf[prefix .. "CustomTexturePath"] = "Interface\\PETBATTLES\\PetBattle-SelectedPetGlow"
            conf[prefix .. "AnchorTarget"] = "HEALTH"
            conf[prefix .. "Visibility"] = "ALWAYS"
            conf[prefix .. "TargetOnly"] = false
            conf[prefix .. "HealthCondition"] = "ANY"
            conf[prefix .. "HealthLowAlphaEnabled"] = false
            conf[prefix .. "ColorR"], conf[prefix .. "ColorG"], conf[prefix .. "ColorB"] = 0.8, 0.7, 0.6
        end
    end
    local function Tint(color, label)
        for slot = 1, 3 do
            local holder = mock.texLayers[slot]
            local tint = holder and holder.tex and holder.tex.gradient and holder.tex.gradient.from
            Check(Shown(holder) and tint and tint.r == color.r and tint.g == color.g and tint.b == color.b,
                label .. ": slot " .. slot .. " did not paint the shared NPC/class colour")
        end
        local hp = mock.healthBar.color
        Check(hp and hp[1] == 0 and hp[2] == 0 and hp[3] == 0, label .. ": texture mode changed the black HP bar")
    end
    local sample = Preview.RefreshDeps.UNIT_DATA
    Check(sample and sample.target and sample.player, "harness: preview sample data missing")
    sample.target.npcKind, sample.target.reactionKind = "npcCaster", "enemy"
    currentKey = "target"
    Refresh()
    Check(not box._msufPreviewScene.data.live, "harness: expected a simulated target")
    Tint(colors.npcCaster, "simulated caster")
    sample.target.reactionKind = "neutral"
    Refresh()
    Tint(colors.neutral, "simulated neutral")
    sample.player.class = "MAGE"
    currentKey = "player"
    Refresh()
    Tint(db.classColors.MAGE, "simulated player")

    -- The live model's approximate elite sample is a caster. The real shared
    -- classifier must win and identify this lieutenant as a miniboss.
    liveUnits.target = { classification = "elite", mana = true, lieutenant = true, level = 80 }
    currentKey = "target"
    Refresh()
    Check(box._msufPreviewScene.data.liveUnit == "target", "harness: target did not use live data")
    Tint(colors.npcMiniboss, "live lieutenant")
    liveUnits.boss1 = { classification = "worldboss", level = -1 }
    currentKey = "boss"
    Refresh()
    Tint(colors.npcBoss, "live boss")

    -- Low-health opacity animates the existing tint without consulting NPCs
    -- again. A subsequent full refresh must pick up the changed palette.
    currentKey = "target"
    local calls, resolve = 0, runtime.ResolveClassNPCRGB
    runtime.ResolveClassNPCRGB = function(...)
        calls = calls + 1
        return resolve(...)
    end
    for _, prefix in ipairs(prefixes) do
        db.target[prefix .. "HealthLowAlphaEnabled"] = true
        db.target[prefix .. "HealthThreshold"] = 1
        db.target[prefix .. "HealthLowAlpha"] = 0.25
    end
    box._animationEnabled, box._animationElapsed = true, 0
    Refresh()
    Check(calls == 1, "three preview slots resolved the NPC more than once per refresh")
    box._animationElapsed = 0.8
    Check(Preview.RefreshAnimation(box) == true, "CLASS_NPC opacity animation requested a full repaint")
    Check(calls == 1, "opacity animation queried NPC classification again")
    Tint(colors.npcMiniboss, "animated lieutenant")
    for slot = 1, 3 do Check(mock.texLayers[slot]:GetAlpha() == 0.25, "low-health opacity was not animated") end
    colors.npcMiniboss.r = 0.73
    Refresh()
    Tint(colors.npcMiniboss, "updated NPC palette")
    Check(db.general.npcColorMode == "reaction" and db.general.npcTypeColorBar == false,
        "preview enabled NPC health colours")
    runtime.ResolveClassNPCRGB = resolve
end
print(string.format("classic_unit_preview_texture_layer_order_smoke: ok (%s, geometry + NPC tint lifecycle)", flavor))
