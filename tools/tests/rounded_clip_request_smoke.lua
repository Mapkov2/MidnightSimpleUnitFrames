-- rounded_clip_request_smoke.lua <repoRoot>
--
-- Texture layers and live dispel overlays ask Rounded Frames to clip their
-- textures to the rounded surface (MSUF_RoundedUF_OnDispelOverlayChanged).
-- ApplyToUnitFrame (UnitFrames/Effects/MSUF_UF_RoundedFrames.lua) refreshes the
-- unit frame masks between BeginMaskRefresh and EndMaskRefresh, and the end
-- removes every mask its own pass did not repeat. The clip requests were not
-- part of that pass, so each rounded refresh (a setting change, a profile
-- switch, combat end) stripped the texture layer clip until the layer was
-- applied again.
--
-- Plain Lua 5.1, repo root as arg 1. Boots each client's real load graph.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local function Masked(tex)
    return tex:GetNumMaskTextures() > 0
end

local function Run(flavor)
    local world = World.New(root, flavor)
    local env = world.env
    world:Boot()
    local failure = world:FirstFailure()
    Check(failure == nil, flavor .. ": load failed in " .. tostring(failure and failure.file) .. ": "
        .. tostring(failure and failure.message))
    env.MSUF_EnsureDB()
    local bars = env.MSUF_DB.bars
    bars.roundedFramesEnabled = true
    bars.roundedUnitFrames = true

    local UF = world.core.UF
    local frame = env.CreateFrame("Button", nil, env.UIParent)
    frame.MSUFUnitKey = "player"
    frame.MSUFSpec = { key = "player" }
    frame.hpBar = env.CreateFrame("StatusBar", nil, frame)
    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    -- The rounded pass walks the core's frame list (UF.ForEachFrame).
    local list = UF.frameList
    list[#list + 1] = frame
    env.MSUF_ApplyRoundedUnitframes()
    Check(Masked(frame.bg), flavor .. ": the rounded pass did not mask the frame background")

    local layer = frame:CreateTexture(nil, "ARTWORK")
    local request = env.MSUF_RoundedUF_OnDispelOverlayChanged
    Check(type(request) == "function", flavor .. ": the clip request hook is not exported")
    Check(request(frame, layer) == true and Masked(layer), flavor .. ": a clip request was not masked")

    -- A rounded refresh must keep the requested clip.
    env.MSUF_ApplyRoundedUnitframes()
    Check(Masked(layer), flavor .. ": a rounded refresh stripped the requested clip mask")
    Check(layer:GetNumMaskTextures() == 1, flavor .. ": the refresh stacked a second mask on the clipped texture")
    Check(Masked(frame.bg), flavor .. ": the refresh lost the frame background mask")

    -- Rounded off clears every mask; back on restores the requested clip.
    bars.roundedFramesEnabled = false
    env.MSUF_ApplyRoundedUnitframes()
    Check(not Masked(layer), flavor .. ": rounded off kept the clip mask")
    bars.roundedFramesEnabled = true
    env.MSUF_ApplyRoundedUnitframes()
    Check(Masked(layer), flavor .. ": rounded back on did not restore the requested clip")
    list[#list] = nil
    print("rounded_clip_request_smoke: ok (" .. flavor .. ")")
end

for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do Run(flavor) end
