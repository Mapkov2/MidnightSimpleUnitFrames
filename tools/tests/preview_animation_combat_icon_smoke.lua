-- preview_animation_combat_icon_smoke.lua <repoRoot>
--
-- The Edit Mode / menu preview animation (UnitFrames/Engine/MSUF_UF_PreviewAnimation.lua)
-- shows a pulsing combat-state icon. It set the atlas
-- "UI-HUD-UnitFrame-Player-PortraitCombatIcon", which no Blizzard branch has,
-- so the icon drew nothing. Blizzard's own player frame uses
-- "UI-HUD-UnitFrame-Player-CombatIcon" (AttackIcon, upstream/live
-- PlayerFrame.xml:329 and upstream/forever PlayerFrame.xml:344); no Classic
-- branch's code uses that atlas, so a client without it must get the
-- Interface\CharacterFrame\UI-StateIcon fallback the runtime uses.
--
-- Boots Mainline (atlas known) and Vanilla (atlas unknown) and drives the real
-- PA.ApplyUnitFrame. Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local COMBAT_ATLAS = "UI-HUD-UnitFrame-Player-CombatIcon"

local function Check(condition, message)
    if not condition then error(message, 2) end
end

for _, case in ipairs({ { "Mainline", true }, { "Forever", true }, { "Vanilla", false } }) do
    local flavor, hasAtlas = case[1], case[2]
    local world = World.New(root, flavor)
    local env = world.env
    local known = { [COMBAT_ATLAS] = hasAtlas or nil }
    env.C_Texture = { GetAtlasInfo = function(atlas) return known[atlas] and { width = 32, height = 32 } or nil end }
    world:Boot()
    local failure = world:FirstFailure()
    Check(failure == nil, flavor .. ": load failed in " .. tostring(failure and failure.file) .. ": "
        .. tostring(failure and failure.message))
    local PA = assert(world.core.PreviewAnimation, flavor .. ": no MSUF.PreviewAnimation")

    local frame = env.CreateFrame("Button", nil, env.UIParent)
    frame.MSUFUnitKey = "target"
    local icon = frame:CreateTexture()
    frame.combatStateIndicatorIcon = icon
    local atlases = {}
    local setAtlas = icon.SetAtlas
    function icon:SetAtlas(atlas, ...)
        atlases[#atlases + 1] = atlas
        return setAtlas(self, atlas, ...)
    end
    PA.enabled = true
    Check(PA.ApplyUnitFrame(frame, 1, "target") == true, flavor .. ": the preview animation did not apply")
    for i = 1, #atlases do
        Check(known[atlases[i]], flavor .. ": the combat icon set the atlas " .. tostring(atlases[i])
            .. ", which this client does not have")
    end
    if hasAtlas then
        Check(icon.atlas == COMBAT_ATLAS, flavor .. ": the combat icon must use Blizzard's player-frame combat atlas")
    else
        Check(icon.texture == "Interface\\CharacterFrame\\UI-StateIcon",
            flavor .. ": without the atlas the combat icon must fall back to the state icon texture")
    end
    PA.enabled = false
    print("preview_animation_combat_icon_smoke: ok (" .. flavor .. ")")
end
