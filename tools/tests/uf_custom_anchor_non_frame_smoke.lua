-- uf_custom_anchor_non_frame_smoke.lua <repoRoot>
--
-- Custom Anchor Frame is free text (MSUF_Menu2_UnitSections stores it raw), so
-- the name can hit any global: a function (CreateFrame, print), an addon
-- namespace table, a string. Only a UI object can be an anchor. The position
-- pass used to hand any truthy global to the anchor cycle check and SetPoint:
-- a function raised "attempt to index local 'region'", which aborted the unit
-- loop so the frames after it were never positioned.
--
-- Boots the real client graph and drives the real factory position pass.
-- Pins: a non-UI-object global is recorded as a missing anchor, the pass runs
-- through every unit without raising, and a real frame of the same kind of
-- name still anchors.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local function Run(flavor)
    local world = World.New(root, flavor)
    local env = world.env
    world:Boot()
    local failure = world:FirstFailure()
    Check(failure == nil, flavor .. ": load failed in " .. tostring(failure and failure.file) .. ": "
        .. tostring(failure and failure.message))
    local UF = assert(world.core.UF, flavor .. ": no MSUF.UF")
    local Factory = assert(UF.Factory, flavor .. ": no UF.Factory")
    local Config = assert(UF.Config, flavor .. ": no UF.Config")
    env.MSUF_ClassPower_Apply = function() end

    local db = Config.GetDB()
    env.MSUF_DB = db
    local units = { "target", "targettarget" }
    for _, unit in ipairs(units) do
        db[unit] = db[unit] or {}
        db[unit].anchorFrameName = nil
        db[unit].anchorToUnitframe = nil
        local frame = env.CreateFrame("Button", nil, env.UIParent)
        frame.MSUFUnitKey = unit
        function frame:GetCenter() return 500, 400 end
        UF.frames[unit] = frame
        UF.frameList[#UF.frameList + 1] = frame
    end
    UF.spawned = true

    env.MSUFTestNamespace = { name = "an addon namespace, not a frame" }
    env.MSUFTestString = "not a frame either"
    local NON_FRAMES = { "CreateFrame", "MSUFTestNamespace", "MSUFTestString" }
    for _, name in ipairs(NON_FRAMES) do
        db.target.anchorFrameName = name
        Config.Refresh()
        UF.frames.targettarget._msufPositionInitialized = nil
        Factory.ForceReanchor()
        Check(UF.frames.target._msufMissingAnchorName == name,
            flavor .. ": the non-frame global " .. name .. " was not recorded as a missing anchor")
        Check(UF.frames.targettarget._msufPositionInitialized == true,
            flavor .. ": anchoring Target to " .. name .. " stopped the position pass before Target of Target")
        Factory.ForceReanchor("target")
    end

    -- A real frame under a plain global name still anchors.
    local provider = env.CreateFrame("Frame", nil, env.UIParent)
    function provider:GetCenter() return 400, 300 end
    env.MSUFTestProvider_Anchor = provider
    db.target.anchorFrameName = "MSUFTestProvider_Anchor"
    Config.Refresh()
    Factory.ForceReanchor("target")
    Check(UF.frames.target._msufMissingAnchorName == nil,
        flavor .. ": a real frame anchor was recorded as missing")
    Check(Factory.ResolveNamedAnchor("MSUFTestProvider_Anchor") == provider,
        flavor .. ": a real frame anchor did not resolve")
    db.target.anchorFrameName = nil
    print("uf_custom_anchor_non_frame_smoke: ok (" .. flavor .. ")")
end

for _, flavor in ipairs({ "Mainline", "Vanilla" }) do Run(flavor) end
