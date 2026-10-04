-- status_atlas_memo_smoke.lua <repo root> <flavor>
--
-- C_Texture.GetAtlasInfo builds a new table on every call, and atlas data
-- cannot change while the client runs. The combat icon asks for its atlas on
-- every UNIT_FLAGS in combat, so it asks the client once per session. A class
-- portrait never asks: SetAtlas owns the icon crop. The combat icon atlas
-- is Blizzard's Mainline PlayerFrame one (AttackIcon,
-- UI-HUD-UnitFrame-Player-CombatIcon); clients without it, and the preview
-- animation on them, draw the classic state icon instead.
-- Boots the flavor's shipped core through tools/tests/client_world.lua.
local root, flavor = assert(arg[1], "repository root argument missing"), arg[2] or "Forever"
local world = assert(loadfile(root .. "/tools/tests/client_world.lua"))().New(root, flavor)
local env, core = world.env, world.core
local function Check(condition, message)
    if not condition then error(flavor .. ": " .. message, 2) end
end

local COMBAT_ATLAS = "UI-HUD-UnitFrame-Player-CombatIcon"
local STATE_TEXTURE = "Interface\\CharacterFrame\\UI-StateIcon"
-- Only the Mainline PlayerFrame family ships the HUD combat icon atlas.
local hasCombatAtlas = flavor == "Mainline" or flavor == "Forever"
local reads = {}
env.C_Texture = { GetAtlasInfo = function(atlas)
    reads[atlas] = (reads[atlas] or 0) + 1
    if atlas == COMBAT_ATLAS and not hasCombatAtlas then return nil end
    return { width = 32, height = 32, leftTexCoord = 0, rightTexCoord = 1, topTexCoord = 0, bottomTexCoord = 1 }
end }
-- Blizzard class icon coordinates, so the Blizzard class pack uses its atlases.
env.CLASS_ICON_TCOORDS = { MAGE = { 0.25, 0.49, 0, 0.25 }, WARRIOR = { 0, 0.25, 0, 0.25 } }
local unitClass = "MAGE"
env.UnitExists = function() return true end
env.UnitIsConnected = function() return true end
env.UnitIsVisible = function() return true end
env.UnitClass = function() return unitClass, unitClass end
env.InCombatLockdown = function() return false end
env.UnitAffectingCombat = function() return false end
world:Boot()
local failure = world:FirstFailure()
Check(not failure, failure and failure.message)
env.MSUF_InitProfiles(); env.MSUF_EnsureDB(true)
local UF = core.UF

-- 1. Combat icon: one atlas question per session, however many updates.
local Runtime = assert(core.UFStatusRuntime, "the status runtime is missing")
local frame = env.CreateFrame("Frame", nil, env.UIParent)
frame.MSUFUnitKey = "target"
frame.combatStateIndicatorIcon = frame:CreateTexture(nil, "OVERLAY")
local status = { combat = { enabled = true }, testMode = true }
for _ = 1, 20 do Runtime.UpdateCombat(frame, status) end
Check((reads[COMBAT_ATLAS] or 0) <= 1, "20 combat updates asked for the combat atlas " .. tostring(reads[COMBAT_ATLAS]) .. " times")
local icon = frame.combatStateIndicatorIcon
if hasCombatAtlas then
    Check(icon.atlas == COMBAT_ATLAS, "the combat icon must use the Mainline PlayerFrame atlas")
else
    Check(icon.atlas == nil and icon.texture == STATE_TEXTURE, "a client without the atlas must draw the classic state icon")
end

-- 2. Class portraits: class changes show the whole icon and never ask for atlas info.
local conf = env.MSUF_DB.player
conf.portraitMode, conf.portraitRender, conf.portraitShape = "LEFT", "CLASS", "SQUARE"
conf.portraitClassStyle = "BLIZZARD"
local player = env.CreateFrame("Frame", nil, env.UIParent)
player:SetSize(240, 44); player.MSUFUnitKey = "player"
player.Health = env.CreateFrame("StatusBar", nil, player); player.Health:SetSize(240, 44)
player.hpBar = player.Health
local portrait = UF.elements.Portrait
UF.Config.Refresh()
player.MSUFSpec = UF.Config.GetSpec("player")
portrait.Apply(player, player.MSUFSpec)
Check(player.portrait.atlas == "classicon-MAGE", "harness: the Blizzard class pack did not use its atlas")
for _, class in ipairs({ "WARRIOR", "MAGE", "WARRIOR", "MAGE" }) do
    unitClass = class
    portrait.Update(player, "MSUF_UNIT_IDENTITY_VISUAL", "player")
    Check(player.portrait.atlas == "classicon-" .. class, "the class portrait did not follow the class")
    local uv = player.portrait.texCoord
    Check(uv and uv[1] == 0 and uv[2] == 1 and uv[3] == 0 and uv[4] == 1, "the class portrait must show its whole atlas")
end
Check(reads["classicon-MAGE"] == nil and reads["classicon-WARRIOR"] == nil,
    "class portraits asked for atlas info: MAGE " .. tostring(reads["classicon-MAGE"])
    .. ", WARRIOR " .. tostring(reads["classicon-WARRIOR"]))

-- 3. Preview animation: never the atlas name no client has.
local PA = assert(core.PreviewAnimation, "the preview animation module is missing")
local previewFrame = env.CreateFrame("Frame", nil, env.UIParent)
previewFrame.MSUFUnitKey = "target"
previewFrame.combatStateIndicatorIcon = previewFrame:CreateTexture(nil, "OVERLAY")
PA.enabled = true
Check(PA.ApplyUnitFrame(previewFrame, 1, "smoke") == true, "the preview animation did not apply")
PA.enabled = nil
local previewIcon = previewFrame.combatStateIndicatorIcon
Check(previewIcon.atlas ~= "UI-HUD-UnitFrame-Player-PortraitCombatIcon", "the preview combat icon uses an atlas no client has")
if hasCombatAtlas then
    Check(previewIcon.atlas == COMBAT_ATLAS, "the preview combat icon must use the Mainline PlayerFrame atlas")
else
    Check(previewIcon.atlas == nil and previewIcon.texture == STATE_TEXTURE,
        "the preview combat icon must fall back to the classic state icon")
end
print("status_atlas_memo_smoke: OK (" .. flavor .. ")")
