-- uf_late_anchor_reaction_smoke.lua <repoRoot>
--
-- The unit-frame factory re-anchors when an addon load can resolve an anchor
-- frame that was missing (another addon's frame, a Cooldown Manager viewer).
-- It used to do that on every ADDON_LOADED as soon as any named anchor was
-- configured, even one that always resolves (Target of Target on Target, the
-- Cooldown Manager): each Blizzard load-on-demand UI (talents, collections)
-- then ran a full re-apply of every unit frame, ClassPower and the group
-- layout, and in combat queued that full apply for combat's end.
--
-- Boots the real client graph and drives the real factory position pass and
-- late-anchor event handler. Pins: a load that resolves nothing re-applies
-- nothing, in and out of combat; the position pass records a missing anchor;
-- the load that makes it resolve re-anchors.
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

    -- Target of Target anchored to the Target frame: a named anchor that always
    -- resolves, so HasLateAnchorConfig is true from the first apply.
    -- In game MSUF_DB is the active profile Config compiles; the late-anchor
    -- path reads the global.
    local db = Config.GetDB()
    env.MSUF_DB = db
    db.targettarget = db.targettarget or {}
    db.targettarget.anchorToUnitframe = "target"
    db.target = db.target or {}
    db.target.anchorFrameName = nil
    for _, unit in ipairs({ "target", "targettarget" }) do
        local frame = env.CreateFrame("Button", nil, env.UIParent)
        frame.MSUFUnitKey = unit
        function frame:GetCenter() return 500, 400 end
        UF.frames[unit] = frame
        UF.frameList[#UF.frameList + 1] = frame
    end
    UF.spawned = true
    Config.Refresh()
    Factory.ForceReanchor()
    Check(UF.frames.targettarget._msufMissingAnchorName == nil,
        flavor .. ": an anchor that resolves must not be recorded as missing")

    local lateEvents
    for _, frame in ipairs(world.widgets.frames) do
        local events = frame.events or {}
        if events.ADDON_LOADED and events.EDIT_MODE_LAYOUTS_UPDATED and events.PLAYER_REGEN_DISABLED then
            lateEvents = frame
        end
    end
    local handler = assert(lateEvents and lateEvents.scripts and lateEvents.scripts.OnEvent,
        flavor .. ": the late-anchor event frame was not found")

    -- Count the full re-applies the late-anchor path schedules.
    local applies = 0
    local apply = Factory.Apply
    Factory.Apply = function() applies = applies + 1; return true end
    world.widgets:RunTimers()
    applies = 0

    -- A Blizzard load-on-demand UI that anchors nothing MSUF waits for.
    handler(lateEvents, "ADDON_LOADED", "Blizzard_Collections")
    world.widgets:RunTimers()
    Check(applies == 0, flavor .. ": loading an addon that resolves no anchor re-applied every unit frame ("
        .. applies .. " full applies)")

    -- The same kind of load in combat must not queue a full apply for its end.
    for unit in pairs(UF.pendingApply) do UF.pendingApply[unit] = nil end
    world.widgets:SetCombat(true)
    handler(lateEvents, "ADDON_LOADED", "Blizzard_PlayerSpells")
    world.widgets:SetCombat(false)
    Check(next(UF.pendingApply) == nil, flavor .. ": an addon load in combat queued a full re-apply after combat")

    -- A frame anchored to another addon's frame that does not exist yet.
    db.target.anchorFrameName = "MSUFTestProvider_Anchor"
    Config.Refresh()
    Factory.ForceReanchor("target")
    Check(UF.frames.target._msufMissingAnchorName == "MSUFTestProvider_Anchor",
        flavor .. ": the position pass did not record the missing anchor")
    world.widgets:RunTimers()
    applies = 0
    handler(lateEvents, "ADDON_LOADED", "MSUFTestProvider")
    world.widgets:RunTimers()
    Check(applies == 0, flavor .. ": an addon load that leaves the anchor missing re-applied the frames")

    -- The provider loads and creates its frame: exactly that load re-anchors.
    local provider = env.CreateFrame("Frame", nil, env.UIParent)
    function provider:GetCenter() return 400, 300 end
    env.MSUFTestProvider_Anchor = provider
    handler(lateEvents, "ADDON_LOADED", "MSUFTestProvider")
    world.widgets:RunTimers()
    Check(applies >= 1, flavor .. ": the load that made the missing anchor resolve did not re-anchor")
    Factory.Apply = apply
    Factory.ForceReanchor("target")
    Check(UF.frames.target._msufMissingAnchorName == nil,
        flavor .. ": the resolved anchor is still recorded as missing")
    db.target.anchorFrameName = nil
    print("uf_late_anchor_reaction_smoke: ok (" .. flavor .. ")")
end

for _, flavor in ipairs({ "Mainline", "TBC" }) do Run(flavor) end
