-- uf_custom_anchor_non_frame_smoke.lua <repoRoot>
--
-- Custom Anchor Frame is free text (MSUF_Menu2_UnitSections stores it raw), so
-- the name can hit any global: a function (CreateFrame, print), an addon
-- namespace table, a string, or a UI object that is not a region (a Font, an
-- AnimationGroup such as AnimateMouse). Only a region can be an anchor. The
-- position pass used to hand any truthy global to the anchor cycle check and
-- SetPoint: a function raised "attempt to index local 'region'", which aborted
-- the unit loop so the frames after it were never positioned, and a non-region
-- UI object made SetPoint raise the same way.
--
-- Boots the real client graph and drives the real factory position pass.
-- Pins: a non-region global is recorded as a missing anchor, the pass runs
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
    -- UI objects that are not regions. The shared widget stub gives every
    -- object one method table (SetPoint included), which is more lenient
    -- than the client, so these carry only the surface their client type
    -- has: SetPoint and its relativeTo exist only on ScriptRegion
    -- (SimpleScriptRegionResizingAPIDocumentation, every mirror branch).
    -- AnimateMouse is a real AnimationGroup global (TutorialFrame.xml), and
    -- GameFontNormal-style globals are Font objects.
    local function NonRegion(objectType)
        local object = {}
        function object:GetObjectType() return objectType end
        function object:IsObjectType(kind) return kind == objectType end
        function object:IsForbidden() return false end
        function object:GetParent() return env.UIParent end
        function object:GetName() return nil end
        return object
    end
    env.MSUFTestAnimationGroup = NonRegion("AnimationGroup")
    env.MSUFTestFontObject = NonRegion("Font")
    local nativeSetPoint = world.widgets.Methods.SetPoint
    world.widgets.Methods.SetPoint = function(self, point, relativeTo, ...)
        if type(relativeTo) == "table" and relativeTo.SetPoint == nil then
            error("SetPoint: relativeTo must be a ScriptRegion, got " .. tostring(relativeTo:GetObjectType()), 2)
        end
        return nativeSetPoint(self, point, relativeTo, ...)
    end
    local NON_FRAMES = { "CreateFrame", "MSUFTestNamespace", "MSUFTestString",
        "MSUFTestAnimationGroup", "MSUFTestFontObject" }
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
