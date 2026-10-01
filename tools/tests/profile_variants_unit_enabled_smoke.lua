-- Profile variants switch unit frames on and off, live. A variant such as
-- "arena frames only in arena" or "no focus frame while solo" patches a unit
-- root's own enabled field; variants record, preview and apply it like any
-- other field. The Factory normally detaches a frame that is turned off and
-- needs a reload to build it again, so a frame a saved variant switches is
-- never detached: it is held hidden (unit watch and load-condition visibility
-- driver released, spec off) and the variant brings it back without a reload.
--
-- Part 1 drives the real State modules: Resolve applies the switch, Diff
-- records it, a recording previews it, and SwitchesUnitFrame names exactly the
-- patched unit roots (every unit while a recording runs).
-- Part 2 boots each client's real core graph and drives the real Factory:
-- a variant-switched frame goes off and on repeatedly without detaching and
-- without the reload prompt, its load-condition driver is released and
-- rebuilt; a frame no variant switches keeps the detach-and-reload contract;
-- a frame detached before its variant existed prompts once per session.
-- Usage: lua tools/tests/profile_variants_unit_enabled_smoke.lua <repoRoot>
local root = assert(arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")

---------------------------------------------------------------------------
-- Part 1: State modules
---------------------------------------------------------------------------
do
    local NS = {}
    function InCombatLockdown() return false end
    function CreateFrame() return { SetScript = function() end, RegisterEvent = function() end, UnregisterAllEvents = function() end } end
    function IsInInstance() return false, "none" end
    function IsInGroup() return false end
    function MSUF_GetPlayerSpecID() return 63 end
    for _, name in ipairs({ "ProfileFields", "ProfileVariants", "ProfileSync", "ProfileVariantEditor" }) do
        assert(loadfile(root .. "/MidnightSimpleUnitFrames/State/MSUF_" .. name .. ".lua"))("MSUF", NS)
    end
    local F, V = NS.ProfileFields, NS.ProfileVariants
    NS.ProfileRuntime = { Apply = function() end }

    local db = { general = {}, arena = { enabled = false, width = 100 }, player = { enabled = true, width = 150 },
        profileVariants = { version = 1, entries = { { name = "Arena", patch = {
            { path = { "arena", "enabled" }, value = true },
            { path = { "player", "enabled" }, value = false },
            { path = { "arena", "width" }, value = 180 },
        } } } } }
    MSUF_DB = db
    assert(V.Resolve(db, { location = "arena", spec = 63, dark = false }))
    assert(db.arena.enabled == true and db.player.enabled == false, "a variant did not switch its unit frames")
    assert(db.arena.width == 180, "the other fields of the same variant stopped applying")
    assert(V.SwitchesUnitFrame("arena") and V.SwitchesUnitFrame("player"), "the switched unit roots are not reported")
    assert(not V.SwitchesUnitFrame("target") and not V.SwitchesUnitFrame("general"), "an unswitched root is reported")
    V.Restore()
    assert(db.arena.enabled == false and db.player.enabled == true, "leaving the context did not restore the base switches")

    -- A new schema table (save, import, Resolve) is read again.
    db.profileVariants = { version = 1, entries = { { name = "Solo", patch = {
        { path = { "focus", "enabled" }, value = false },
        { path = { "player", "castbar", "enabled" }, value = false },
    } } } }
    assert(V.SwitchesUnitFrame("focus") and not V.SwitchesUnitFrame("arena"), "the switch roots were not rebuilt for a new schema")
    assert(not V.SwitchesUnitFrame("player"), "a nested enabled setting was taken for a unit frame switch")

    -- Record: toggling a frame while recording becomes a variant field.
    local patch = assert(F.Diff({ player = { enabled = true, width = 150 } }, { player = { enabled = false, width = 200 } }))
    local recorded = {}
    for _, field in ipairs(patch) do recorded[table.concat(field.path, ".")] = field.value end
    assert(recorded["player.enabled"] == false and recorded["player.width"] == 200, "a recording lost a unit frame's switch")
    assert(F.UnitSwitchRoot({ "boss", "enabled" }) == "boss" and F.UnitSwitchRoot({ "boss", "castbar", "enabled" }) == nil
        and F.UnitSwitchRoot({ "gf_party", "enabled" }) == nil, "unit switch paths misread")

    -- Preview while recording writes the switch live, and every unit counts.
    db.profileVariants = { version = 1, entries = { { name = "Arena", patch = {
        { path = { "arena", "enabled" }, value = true },
        { path = { "arena", "width" }, value = 180 },
    } } } }
    MSUF_GlobalDB = { profiles = { A = db }, global = {} }
    MSUF_ActiveProfile = "A"
    assert(V.BeginRecording("Arena"))
    assert(db.arena.enabled == true and db.arena.width == 180, "recording preview did not switch the unit frame")
    assert(V.SwitchesUnitFrame("target"), "a recording must keep every unit frame attached while it is off")
    assert(V.CancelRecording(false))
    assert(db.arena.enabled == false and not V.SwitchesUnitFrame("target"), "cancel did not restore the base")
end

---------------------------------------------------------------------------
-- Part 2: the real Factory on every client
---------------------------------------------------------------------------
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local function Run(flavor)
    local world = World.New(root, flavor)
    local env = world.env
    local watched, drivers, driverWrites = {}, {}, 0
    env.RegisterUnitWatch = function(frame) watched[frame] = true end
    env.UnregisterUnitWatch = function(frame) watched[frame] = nil end
    env.UnitWatchRegistered = function(frame) return watched[frame] == true end
    env.RegisterStateDriver = function(frame, state, expression)
        if state == "visibility" then drivers[frame] = expression; driverWrites = driverWrites + 1 end
    end
    env.UnregisterStateDriver = function(frame, state) if state == "visibility" then drivers[frame] = nil end end
    world:Boot()
    local failure = world:FirstFailure()
    Check(failure == nil, flavor .. ": load failed in " .. tostring(failure and failure.file) .. ": "
        .. tostring(failure and failure.message))
    local UF = assert(world.core.UF, flavor .. ": no MSUF.UF")
    local Factory, Config = assert(UF.Factory, "no factory"), assert(UF.Config, "no config")
    local V = assert(world.core.ProfileVariants, flavor .. ": no profile variants")
    local prompts = 0
    env.MSUF_ShowReloadRecommendedPopup = function() prompts = prompts + 1 end
    env.MSUF_ClassPower_Apply = function() end
    -- Blizzard frame ownership is not under test (and needs the full client).
    UF.DisableBlizzardFrames = function() end
    -- Element applies need live unit data; the stub world applies only the real
    -- LoadConditions element (the visibility owner under test) and records the
    -- mask the Factory asks for.
    local masks = {}
    UF.OptimizeFrameHotpaths = function() return false end
    UF.ApplySpec = function(frame, spec, _, mask)
        masks[frame] = mask
        UF.AttachFrame(frame, { scope = spec.scope or "single" })
        return UF.ApplyElementsToFrame(frame, { "LoadConditions" }, spec)
    end

    local db = Config.GetDB()
    env.MSUF_DB = db
    db.target = db.target or {}
    db.pet = db.pet or {}
    db.target.enabled, db.pet.enabled = true, true
    db.target.loadCondHideInCombat = true
    db.profileVariants = { version = 1, entries = { { name = "Solo", conditions = {}, patch = {
        { path = { "target", "enabled" }, value = false },
    } } } }
    Config.Refresh()
    -- The stub world cannot build secure templates; the frames carry the same
    -- Enable/Disable pair Factory's SpawnFrame gives them.
    for _, unit in ipairs({ "target", "pet" }) do
        local frame = env.CreateFrame("Button", nil, env.UIParent)
        frame.MSUFUnitKey = unit
        function frame:GetCenter() return 500, 400 end
        function frame:Enable() env.RegisterUnitWatch(self); self:Show(); return true end
        function frame:Disable() env.UnregisterUnitWatch(self); self:Hide() end
        UF.AttachFrame(frame, { scope = "single" })
        UF.frames[unit] = frame
        UF.frameList[#UF.frameList + 1] = frame
    end
    UF.spawned = true
    Factory.Apply("target")
    Factory.Apply("pet")
    local target, pet = UF.frames.target, UF.frames.pet
    Check(drivers[target] ~= nil and target._msufVisibilityManaged == true,
        flavor .. ": the target frame did not start with its load-condition driver")

    -- A variant context change re-applies with the coordinated (partial) mask.
    local PARTIAL = { Health = true }
    local function Set(unit, enabled)
        db[unit].enabled = enabled
        Config.Refresh()
        Factory.Apply(unit, PARTIAL)
    end

    -- A variant-switched frame: off and on, live, any number of times.
    for round = 1, 3 do
        Set("target", false)
        Check(not target:IsShown() and watched[target] == nil and drivers[target] == nil,
            flavor .. ": round " .. round .. ": a variant-switched frame is not held hidden")
        Check(UF.attachedFrames[target] == true and target._msufDisabledByConfig ~= true and target._msufVariantOff == true,
            flavor .. ": round " .. round .. ": a variant-switched frame was detached")
        Check(target._msufCoreSpecEnabled == false, flavor .. ": a held frame still dispatches events")
        local writes = driverWrites
        Set("target", true)
        -- The driver (or unit watch) shows the frame whenever the unit exists.
        Check(drivers[target] ~= nil and driverWrites == writes + 1,
            flavor .. ": round " .. round .. ": the variant did not bring the frame's visibility driver back")
        Check(target._msufVariantOff == nil and target._msufCoreSpecEnabled == true, flavor .. ": the frame stayed marked off")
        Check(masks[target] == true, flavor .. ": a frame back from a variant's off state was not applied in full")
        Check(prompts == 0, flavor .. ": a variant-switched frame asked for a reload")
    end
    -- Without load conditions the unit watch is the owner again.
    db.target.loadCondHideInCombat = false
    Set("target", false)
    Set("target", true)
    Check(watched[target] == true and drivers[target] == nil and target._msufVariantOff == nil,
        flavor .. ": a held frame without load conditions did not get its unit watch back")

    -- A frame no variant switches keeps the detach-and-reload contract.
    Set("pet", false)
    Check(pet._msufDisabledByConfig == true and UF.attachedFrames[pet] == nil, flavor .. ": an unswitched frame was not detached")
    Set("pet", true)
    Check(prompts == 1 and not pet:IsShown(), flavor .. ": the reload contract of an unswitched frame changed")
    Set("pet", false)

    -- Detached before its variant existed: the variant asks for the reload once.
    db.profileVariants = { version = 1, entries = { { name = "Solo", conditions = {}, patch = {
        { path = { "target", "enabled" }, value = false },
        { path = { "pet", "enabled" }, value = false },
    } } } }
    for _ = 1, 3 do
        Set("pet", true)
        Set("pet", false)
    end
    Check(prompts == 2, flavor .. ": a variant on a detached frame prompted " .. (prompts - 1) .. " times")
    Check(pet._msufDisabledByConfig == true, flavor .. ": a detached frame was held instead of staying detached")
    print("profile_variants_unit_enabled_smoke: " .. flavor .. " OK")
end

for _, flavor in ipairs({ "Mainline", "Vanilla", "TBC", "Mists" }) do Run(flavor) end
print("profile_variants_unit_enabled_smoke: OK")
