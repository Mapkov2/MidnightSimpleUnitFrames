-- uf_engine_client_gates_smoke.lua <repoRoot> <flavor>
--
-- Every client compiles unit frames through UnitFrames/Engine/MSUF_UF_Config.lua
-- and owns Blizzard's group frames through
-- UnitFrames/Engine/Group/MSUF_UF_Group_Blizzard.lua. Classic Era, TBC and Mists
-- used to load whole-file Classic copies of both; their Classic behaviour now
-- lives in a few hunks of the Retail-named files, gated on MSUF.Client.Family and
-- read once at load. A Retail sync rebases those hunks, so this smoke boots the
-- flavor's real load graph and pins both sides of every gate:
--
--   PvP context   Classic and Forever follow the player's PvP flag and repaint
--                 configured indicators in combat. Retail follows the flag on
--                 the player frame and keeps the War Mode gate for other units.
--   Unit support  Classic compiles a unit its client cannot produce disabled;
--                 Mainline compiles every unit as configured.
--   Raid manager  Classic's hidden-by-default manager parents the raid container,
--                 and its single legacy toggle button follows the manager's
--                 click-through state. Mainline keeps Retail's model.
--
-- Plain Lua 5.1 with the repo root as arg 1 -- not through the aura test driver,
-- which replaces loadfile and io.open.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg and arg[2], "flavor required (a matrix Suffix or Forever)")
assert(rawget(_G, "MSUF_Auras3TestLoader") == nil,
    "uf_engine_client_gates_smoke loads the real TOC graph; run it with plain Lua 5.1")

local function Check(condition, message)
    if not condition then error(flavor .. ": " .. message, 2) end
end

local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local world = World.New(root, flavor)
local env = world.env

-- Client PvP state, installed before the graph loads: the config compiler
-- captures some of these functions into upvalues at load.
local pvp = {}
local function ResetPvP()
    pvp.flagged, pvp.ffa, pvp.timer, pvp.instance, pvp.warMode = false, false, false, "none", false
end
ResetPvP()
-- Units other than the player that exist and are PvP-flagged (the indicator
-- section below fills it); the core captures both APIs at load.
local flaggedUnits = {}
env.UnitExists = function(unit) return unit == "player" or flaggedUnits[unit] == true end
env.UnitIsPVP = function(unit) return (unit == "player" and pvp.flagged) or flaggedUnits[unit] == true end
env.UnitIsPVPFreeForAll = function(unit) return unit == "player" and pvp.ffa end
env.IsPVPTimerRunning = function() return pvp.timer end
env.IsInInstance = function() return pvp.instance ~= "none", pvp.instance end
env.GetInstanceInfo = function() return "Zone", pvp.instance end
env.C_PvP = {
    IsWarModeDesired = function() return pvp.warMode end,
    IsWarModeActive = function() return pvp.warMode end,
}

local unitFilters = {}
local createFrame = env.CreateFrame
env.CreateFrame = function(...)
    local frame = createFrame(...)
    local registerUnitEvent = frame.RegisterUnitEvent
    frame.RegisterUnitEvent = function(self, event, unit, ...)
        unitFilters[self] = unitFilters[self] or {}
        unitFilters[self][event] = unit
        return registerUnitEvent(self, event, unit, ...)
    end
    return frame
end

world:Boot()
local failure = world:FirstFailure()
Check(failure == nil, "load failed in " .. tostring(failure and failure.file) .. ": " .. tostring(failure and failure.message))

local client = assert(world.core.Client, "no MSUF.Client")
local classic = client.Family == "Classic"
Check(classic == (world.client.isClassic == true), "client family " .. tostring(client.Family) .. " does not match the matrix")
local followsFlag = classic or client.IsForever == true
local UF = assert(world.core.UF, "no MSUF.UF")
local Config = assert(UF.Config, "no UF.Config")

---------------------------------------------------------------------------
-- What a hidden frame misses
---------------------------------------------------------------------------
-- A hidden frame's events are suspended, so every element the core routes
-- frame events for must be reseeded when the frame shows again: by the identity
-- plan, the forced runtime plan or the OnShow replay (UF.reshowElements). An
-- element with none of them shows stale state after a hide, as the stance text
-- did. The exemptions own their reshow themselves.
do
    local OWN_RESHOW = {
        Auras = "native AuraContainer (Mainline) and the Classic OnShow aura refresh",
        GroupCornerIndicators = "group frames reseed through the lifecycle refresh on OnShow",
        GroupStatusRuntime = "group frames reseed through the lifecycle refresh on OnShow",
        GroupVisuals = "group frames reseed through the lifecycle refresh on OnShow",
        GroupRangeFade = "group frames reseed through the lifecycle refresh on OnShow",
    }
    Check(type(UF.EventElementAllowed) == "function" and type(UF.reshowElements) == "table",
        "the core no longer publishes its event-element predicate or the OnShow replay set")
    for _, name in ipairs(UF.elementOrder) do
        if UF.EventElementAllowed(name) and OWN_RESHOW[name] == nil then
            Check(UF.identityElements[name] == true or UF.forceUpdateElements[name] == true
                or UF.reshowElements[name] == true,
                "element " .. name .. " has frame events but nothing reseeds it after a hide")
        end
    end
    for _, name in ipairs({ "StanceIndicator", "RestingIndicator" }) do
        Check(UF.elements[name] ~= nil and UF.reshowElements[name] == true,
            name .. " must be registered and replayed on OnShow")
    end
end

---------------------------------------------------------------------------
-- PvP context driver
---------------------------------------------------------------------------
local driver = assert(UF.pvpIndicatorContextDriver, "no PvP context driver")
local registered = {}
for event in pairs(driver.events) do registered[#registered + 1] = event end
table.sort(registered)
local registeredText = table.concat(registered, ",")
if followsFlag then
    local expected = { "PLAYER_ENTERING_WORLD", "UNIT_FACTION", "ZONE_CHANGED_NEW_AREA" }
    if classic then
        expected[#expected + 1] = "PLAYER_FLAGS_CHANGED"
    else
        expected[#expected + 1] = "ACTIVE_GAME_MODE_UPDATED"
        expected[#expected + 1] = "PLAYER_PVP_FLAG_CHANGED"
        expected[#expected + 1] = "WAR_MODE_STATUS_UPDATE"
    end
    if client.SupportsEvent("PVP_TIMER_UPDATE") then expected[#expected + 1] = "PVP_TIMER_UPDATE" end
    table.sort(expected)
    Check(registeredText == table.concat(expected, ","),
        "the flag-based PvP context driver registers " .. registeredText .. ", expected the flag events " .. table.concat(expected, ","))
    Check(unitFilters[driver] and unitFilters[driver].UNIT_FACTION == "player",
        "the flag-based PvP context driver must watch UNIT_FACTION for the player only")
else
    Check(registeredText
        == "ACTIVE_GAME_MODE_UPDATED,PLAYER_ENTERING_WORLD,PLAYER_FLAGS_CHANGED,WAR_MODE_STATUS_UPDATE,ZONE_CHANGED_NEW_AREA",
        "the Mainline PvP context driver must watch War Mode and flag confirmation, registers " .. registeredText)
    Check(unitFilters[driver] and unitFilters[driver].PLAYER_FLAGS_CHANGED == "player",
        "the Mainline PvP context driver must watch PLAYER_FLAGS_CHANGED for the player only")
end

local function Context()
    UF.InvalidatePVPIndicatorContext()
    return UF.PVPIndicatorContextActive()
end

ResetPvP()
Check(Context() == false, "an unflagged player outside PvP content must have no PvP context")
pvp.flagged = true
Check(Context() == followsFlag, "only flag-based clients open the shared context on a player flag")
ResetPvP(); pvp.ffa = true
Check(Context() == followsFlag, "free-for-all PvP must open the shared context only on flag-based clients")
ResetPvP(); pvp.timer = true
Check(Context() == followsFlag, "the PvP flag timer must open the shared context only on flag-based clients")
ResetPvP(); pvp.warMode = true
Check(Context() == true, "War Mode must open the PvP context")
ResetPvP(); pvp.instance = "arena"
Check(Context() == true, "arenas must open the PvP context")
ResetPvP(); pvp.instance = "party"; pvp.flagged = true
Check(Context() == false, "dungeons must close the PvP context even when flagged")

-- Flag-based drivers update the shared context in combat. Retail's driver
-- only recompiles other units outside combat.
-- refreshes counts context refreshes that did work.
local refreshes = 0
local refreshContext = UF.RefreshPVPIndicatorContext
UF.RefreshPVPIndicatorContext = function(...)
    local didWork = refreshContext(...)
    if didWork then refreshes = refreshes + 1 end
    return didWork
end
local handler = assert(driver.scripts and driver.scripts.OnEvent, "the PvP context driver has no OnEvent script")
ResetPvP()
Context()
pvp.flagged = true
world.widgets:SetCombat(true)
handler(driver, followsFlag and "UNIT_FACTION" or "ZONE_CHANGED_NEW_AREA", followsFlag and "player" or nil)
world.widgets:SetCombat(false)
if followsFlag then
    Check(refreshes == 1 and UF.PVPIndicatorContextActive() == true,
        "getting flagged in combat must refresh the PvP context at once")
    handler(driver, "UNIT_FACTION", "player")
    Check(refreshes == 1, "an unchanged context must skip the frame repaint")
    refreshes = 0
    pvp.flagged = false
    local flagEvent = classic and "PLAYER_FLAGS_CHANGED" or "UNIT_FACTION"
    handler(driver, flagEvent, "party1")
    Check(refreshes == 0 and UF.PVPIndicatorContextActive() == true,
        "another unit's flag change must not touch the flag-based PvP context")
    handler(driver, flagEvent, "player")
    Check(refreshes == 1 and UF.PVPIndicatorContextActive() == false,
        "the player's own flag change must refresh the flag-based PvP context")
else
    Check(refreshes == 0, "the Mainline PvP context driver must never recompile in combat")
end

-- Entering the world. PLAYER_ENTERING_WORLD carries no unit token: its first
-- payload argument is isInitialLogin and its second is isReloadingUi, both
-- booleans. The driver must take its forced refresh on both, and the forced
-- one at the initial login especially: it is the only pass that seeds the PvP
-- context before the first frame apply. Reading that boolean as a unit used to
-- return from the Classic driver at exactly that login.
for _, login in ipairs({ { true, false, "the initial login" }, { false, true, "a UI reload" },
    { false, false, "a zone transition" } }) do
    ResetPvP()
    Context()
    refreshes = 0
    handler(driver, "PLAYER_ENTERING_WORLD", login[1], login[2])
    Check(refreshes == 1, login[3] .. " (isInitialLogin = " .. tostring(login[1])
        .. ", isReloadingUi = " .. tostring(login[2])
        .. ") must force one PvP context refresh, counted " .. refreshes)
end
-- Every other event keeps its unit filter: only the player matters.
if followsFlag then
    ResetPvP()
    Context()
    refreshes = 0
    pvp.flagged = true
    handler(driver, "UNIT_FACTION", "party1")
    Check(refreshes == 0, "another unit's UNIT_FACTION must still be ignored")
    handler(driver, "UNIT_FACTION", "player")
    Check(refreshes == 1, "the player's own UNIT_FACTION must still refresh the context")
end
UF.RefreshPVPIndicatorContext = refreshContext
ResetPvP()
Context()

---------------------------------------------------------------------------
-- PvP indicators on real frames, getting flagged in combat
---------------------------------------------------------------------------
-- Real compiled specs applied through the real UF core. The bug: Classic folded
-- the context into the compile and recompiled through UF.RefreshElements and
-- GF.RefreshVisuals, which both defer in combat, so a player flagged mid-fight
-- saw no PvP icon until combat ended.
do
    flaggedUnits.target, flaggedUnits.party1 = true, true
    local refreshElements = UF.RefreshElements
    local deferred = 0
    UF.RefreshElements = function(...)
        if world.widgets:IsInCombat() then deferred = deferred + 1 end
        return refreshElements(...)
    end
    ResetPvP()
    Context()
    Config.Refresh()
    local spec = assert(Config.GetSpec("target"), "no compiled target spec")
    local target = env.CreateFrame("Button", nil, env.UIParent)
    target.MSUFUnitKey = "target"
    UF.ApplySpec(target, spec, nil, { StatusIndicators = true, PVPIndicator = true })
    local icon = target.pvpIndicatorIcon
    local pvpSpec = spec.status and spec.status.pvp
    if followsFlag then
        Check(pvpSpec and pvpSpec.enabled == true and pvpSpec.contextGated == true,
            "Flag-based clients must compile the target PvP indicator outside the PvP context (context-gated at runtime)")
        Check(icon ~= nil and icon:IsShown() ~= true, "the target PvP icon must stay hidden outside the PvP context")
    else
        Check(pvpSpec and pvpSpec.enabled == false and pvpSpec.contextGated == nil,
            "Mainline keeps Retail's compile: no PvP indicator outside the PvP context")
    end

    local GF = world.core.GF
    local party
    if followsFlag and GF and type(GF.CompileSpec) == "function" then
        party = env.CreateFrame("Button", nil, env.UIParent)
        party.MSUFUnitKey = "party1"
        local partySpec = GF.CompileSpec("party", party, "party1")
        local partyPvp = partySpec and partySpec.status and partySpec.status.pvp
        Check(partyPvp and partyPvp.enabled == true and partyPvp.contextGated == true
            and partySpec.status.runtimePVP == true,
            "Flag-based clients must compile the party PvP icon outside the PvP context (context-gated at runtime)")
        UF.ApplySpec(party, partySpec, nil, GF.GROUP_APPLY_MASK)
    end

    -- PLAYER_REGEN_DISABLED, then lockdown, then the flag flips mid-fight.
    world.widgets:SetCombat(true)
    pvp.flagged = true
    if client.IsForever then
        world:FireEvent("PLAYER_PVP_FLAG_CHANGED", true)
    else
        handler(driver, followsFlag and "UNIT_FACTION" or "ZONE_CHANGED_NEW_AREA", followsFlag and "player" or nil)
    end
    if followsFlag then
        Check(icon:IsShown() == true, "getting flagged in combat must show the target PvP icon at once")
        if party then
            Check(party.pvpIndicatorIcon and party.pvpIndicatorIcon:IsShown() == true,
                "getting flagged in combat must show the party PvP icon at once")
        end
        Check(deferred == 0, "the Classic context flip must not queue a recompile for after combat")
        pvp.flagged = false
        if client.IsForever then
            world:FireEvent("PLAYER_PVP_FLAG_CHANGED", false)
        else
            handler(driver, "UNIT_FACTION", "player")
        end
        Check(icon:IsShown() ~= true, "losing the flag in combat must hide the target PvP icon at once")
        if party then
            Check(party.pvpIndicatorIcon:IsShown() ~= true, "losing the flag in combat must hide the party PvP icon")
        end
    end
    world.widgets:SetCombat(false)
    UF.RefreshElements = refreshElements
    flaggedUnits.target, flaggedUnits.party1 = nil, nil
    ResetPvP()
    Context()
end

-- Apply the option while the player's live flag is already set, then exercise
-- the native unit event on the same frame without a spec refresh.
do
    local db = env.MSUF_EnsureDB()
    local saved = db.player.showPvpIndicator
    local player = env.CreateFrame("Button", nil, env.UIParent)
    player.MSUFUnitKey = "player"
    local prior = UF.frames.player
    local index = #UF.frameList + 1
    UF.frames.player, UF.frameList[index] = player, player
    db.player.showPvpIndicator = false
    UF.Config.RefreshUnit("player")
    UF.ApplySpec(player, UF.Config.GetSpec("player"), nil, { StatusIndicators = true, PVPIndicator = true })

    pvp.flagged = true
    if not followsFlag then
        pvp.warMode = true
        handler(driver, "WAR_MODE_STATUS_UPDATE", true)
    end
    world:FireEvent("UNIT_FACTION", "player")
    Check(not (player.pvpIndicatorIcon and player.pvpIndicatorIcon:IsShown()), "disabled option must hide the PvP icon")
    db.player.showPvpIndicator = true
    env.MSUF_RequestStatusPvpIndicatorRefresh("player")
    local icon = player.pvpIndicatorIcon
    Check(icon and icon:IsShown(), "enabling the option while flagged must show the player PvP icon immediately")

    db.player.showPvpIndicator = false
    env.MSUF_RequestStatusPvpIndicatorRefresh("player")
    Check(not icon:IsShown(), "disabling the option must hide the icon while the player is still flagged")
    db.player.showPvpIndicator = true
    env.MSUF_RequestStatusPvpIndicatorRefresh("player")
    Check(icon:IsShown(), "re-enabling the option must show the icon while still flagged")

    pvp.flagged = false
    world:FireEvent("PVP_TIMER_UPDATE", "player")
    Check(not icon:IsShown(), "the player icon must hide when the native PvP timer event clears the flag")
    world.widgets:SetCombat(true)
    pvp.flagged = true
    world:FireEvent("UNIT_FACTION", "player")
    Check(icon and icon:IsShown(), "UNIT_FACTION must show the player PvP icon immediately in combat")
    world.widgets:SetCombat(false)
    if client.IsForever then
        -- The battleground keeps the context active so this checks the player
        -- event independently of a shared context repaint.
        pvp.instance = "pvp"
        pvp.flagged = false
        world:FireEvent("PLAYER_PVP_FLAG_CHANGED", false)
        Check(UF.PVPIndicatorContextActive() and not icon:IsShown(),
            "the Forever player must repaint on the native flag event even if the context is unchanged")
        pvp.flagged = true
        world:FireEvent("PLAYER_PVP_FLAG_CHANGED", true)
        Check(icon:IsShown(), "the Forever player must show the flag on its native event")

        pvp.instance, pvp.flagged = "none", false
        world:FireEvent("PLAYER_PVP_FLAG_CHANGED", false)
        pvp.flagged = true
        player:GetScript("OnEvent")(player, "PLAYER_PVP_FLAG_CHANGED", true)
        Check(not icon:IsShown(), "the player-first dispatch must still see the old context")
        handler(driver, "PLAYER_PVP_FLAG_CHANGED", true)
        Check(icon:IsShown(), "the driver must repaint the player if its listener runs second")
    elseif not classic then
        Check(unitFilters[player] and unitFilters[player].PLAYER_FLAGS_CHANGED == "player",
            "Retail must register the confirmed flag event for the player only")
        Check(icon:IsShown(), "confirmed War Mode must show the player's PvP flag")
        handler(driver, "WAR_MODE_STATUS_UPDATE", false)
        Check(not icon:IsShown(), "War Mode off must hide a PvP flag that is still set")
        pvp.warMode = false
        for _, event in ipairs({ "PLAYER_FLAGS_CHANGED", "UNIT_FACTION", "PVP_TIMER_UPDATE" }) do
            world:FireEvent(event, "player")
            Check(not icon:IsShown(), event .. " must not restore the badge after War Mode off")
        end

        local reloaded = env.CreateFrame("Button", nil, env.UIParent)
        reloaded.MSUFUnitKey = "player"
        Context()
        UF.Config.RefreshUnit("player")
        UF.ApplySpec(reloaded, UF.Config.GetSpec("player"), nil, { StatusIndicators = true, PVPIndicator = true })
        Check(not (reloaded.pvpIndicatorIcon and reloaded.pvpIndicatorIcon:IsShown()),
            "a fresh player frame after reload must hide the residual PvP flag")

        pvp.warMode, pvp.flagged = true, false
        handler(driver, "WAR_MODE_STATUS_UPDATE", true)
        Check(not icon:IsShown(), "War Mode on must wait for an actual PvP flag")
        pvp.flagged = true
        world:FireEvent("PLAYER_FLAGS_CHANGED", "player")
        Check(icon:IsShown(), "player flags must paint the badge even when the context is already open")

        pvp.warMode = false
        world:FireEvent("PLAYER_FLAGS_CHANGED", "player")
        Check(not icon:IsShown(), "player flags must close the context when Blizzard confirms War Mode off")
        pvp.instance = "pvp"
        handler(driver, "ZONE_CHANGED_NEW_AREA")
        Check(icon:IsShown(), "a PvP instance must show the flag with War Mode off")
    end
    db.player.showPvpIndicator = saved
    UF.frames.player = prior
    table.remove(UF.frameList, index)
    ResetPvP()
    Context()
end

---------------------------------------------------------------------------
-- Unit support
---------------------------------------------------------------------------
-- Config.Refresh compiles only the client's managed units, so asking for a
-- unit the client lacks used to recompile every unit spec on each call.
do
    local refresh = Config.Refresh
    local compiles = 0
    Config.Refresh = function(...) compiles = compiles + 1; return refresh(...) end
    refresh()
    for _, token in ipairs({ "boss1", "arena1", "focus", "arena5" }) do
        if not UF.IsManagedUnit(token) then
            Config.GetSpec(token)
            Config.GetSpec(token)
            Check(compiles == 0, "Config.GetSpec(\"" .. token .. "\") on a unit this client lacks recompiled "
                .. compiles .. " times")
        end
    end
    local saved = Config.specs.target
    Config.specs.target = nil
    Check(Config.GetSpec("target") ~= nil and compiles == 1,
        "a managed unit without a spec must compile once, counted " .. compiles)
    Config.specs.target = Config.specs.target or saved
    Config.Refresh = refresh
end

-- The portrait detail compiler is a separate, optional module: a load without
-- it (a partial graph, a harness) must leave both spec compilers working.
do
    local core = world.core
    local details = core.PortraitDetails
    core.PortraitDetails = nil
    local unitOk, unitError = pcall(Config.Refresh)
    local GF = core.GF
    local groupOk, groupError = true, nil
    if GF and type(GF.CompileSpec) == "function" then
        if type(GF.InvalidateCompiledSpecs) == "function" then GF.InvalidateCompiledSpecs() end
        local frame = env.CreateFrame("Button", nil, env.UIParent)
        frame.MSUFUnitKey = "party1"
        groupOk, groupError = pcall(GF.CompileSpec, "party", frame, "party1")
    end
    core.PortraitDetails = details
    if GF and type(GF.InvalidateCompiledSpecs) == "function" then GF.InvalidateCompiledSpecs() end
    Check(unitOk, "the unit spec compiler fails without the portrait detail module: " .. tostring(unitError))
    Check(groupOk, "the group spec compiler fails without the portrait detail module: " .. tostring(groupError))
    Config.Refresh()
end

local db = Config.GetDB()
local order, lookup = UF.unitOrder, UF.unitLookup
local forced = {}
for _, key in ipairs({ "focus", "boss", "arena" }) do
    db[key] = type(db[key]) == "table" and db[key] or {}
    db[key].enabled = true
end
for _, token in ipairs({ "focus", "boss1", "arena1" }) do
    local present = false
    for index = 1, #order do if order[index] == token then present = true end end
    if not present then
        order[#order + 1] = token
        lookup[token] = true
        forced[#forced + 1] = token
    end
end
Config.Refresh()
for _, token in ipairs({ "focus", "boss1", "arena1" }) do
    local spec = assert(Config.specs[token], "no compiled spec for " .. token)
    local expected = not classic or client.SupportsUnit(token)
    Check(spec.enabled == expected, token .. " compiled enabled=" .. tostring(spec.enabled)
        .. ", expected " .. tostring(expected) .. (classic and " (Classic follows SupportsUnit)"
        or " (Mainline compiles every unit as configured)"))
end
for _, token in ipairs(forced) do
    for index = #order, 1, -1 do if order[index] == token then table.remove(order, index) end end
    lookup[token] = nil
    Config.specs[token] = nil
end

---------------------------------------------------------------------------
-- Blizzard raid manager and container ownership
---------------------------------------------------------------------------
-- The ownership file is loaded again on its own, against recording frames and
-- the client model this flavor just built.
local function Frame(name, fields)
    local frame = { name = name, shown = true, alpha = 1, mouse = true, hooks = {}, scripts = {} }
    for key, value in pairs(fields or {}) do frame[key] = value end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:IsShown() return self.shown end
    function frame:SetAlpha(value) self.alpha = value end
    function frame:EnableMouse(value) self.mouse = value and true or false end
    function frame:IsMouseEnabled() return self.mouse end
    function frame:IsProtected() return false end
    function frame:IsForbidden() return false end
    function frame:SetParent(value) self.parent = value end
    function frame:GetParent() return self.parent end
    function frame:HookScript(kind, callback) self.scripts[kind] = callback end
    function frame:SetScript(kind, callback) self.scripts[kind] = callback end
    function frame:RegisterEvent() end
    function frame:UnregisterEvent() end
    function frame:UnregisterAllEvents() end
    function frame:SetAllPoints() end
    return frame
end

local uiParent = Frame("UIParent")
local hiddenParent
local sandbox = setmetatable({
    UIParent = uiParent,
    CreateFrame = function(_, name)
        local frame = Frame(name or "eventFrame")
        if name == "MSUF_GF_BlizzardHiddenParent" then hiddenParent = frame end
        return frame
    end,
    InCombatLockdown = function() return false end,
    IsInGroup = function() return false end,
    IsInRaid = function() return false end,
    GetNumGroupMembers = function() return 0 end,
    GetMouseFoci = function() return {} end,
    hooksecurefunc = function(target, method, callback) target.hooks[method] = callback end,
    C_Timer = { After = function(_, callback) callback() end },
}, { __index = _G })
sandbox._G = sandbox

local toggle = Frame("ToggleButton")
local manager = Frame("CompactRaidFrameManager", { collapsed = true, toggleButton = toggle, shown = false })
local container = Frame("CompactRaidFrameContainer", { parent = manager })
sandbox.CompactRaidFrameManager = manager
sandbox.CompactRaidFrameManagerToggleButton = toggle
sandbox.CompactRaidFrameContainer = container

local party = { enabled = false, showSolo = false, raidManagerMode = "HIDDEN" }
local raid = {}
local namespace = {
    Client = client,
    ExportPublic = function(name, value) sandbox[name] = value; return value end,
    GF = { GetConf = function(kind) return kind == "party" and party or raid end },
}
-- The group file's hard dependencies come from the same providers the client loads before it:
-- the real Kernel/MSUF_Require.lua resolves them against this sandbox, and
-- MSUF_PixelLayoutRegion is the export the booted flavor graph took from Kernel/MSUF_Util.lua.
sandbox.MSUF_PixelLayoutRegion = assert(env.MSUF_PixelLayoutRegion,
    flavor .. ": the booted graph does not export MSUF_PixelLayoutRegion")
local requireChunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/Kernel/MSUF_Require.lua"))
setfenv(requireChunk, sandbox)
requireChunk("MidnightSimpleUnitFrames", namespace)
Check(namespace.Require == sandbox.MSUF_Require and namespace.Optional ~= nil, "the real Require provider did not publish MSUF.Require")
local chunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Blizzard.lua"))
setfenv(chunk, sandbox)
chunk("MidnightSimpleUnitFrames", namespace)
local GF = namespace.GF

Check(GF.ApplyBlizzardRaidManagerMode() == "HIDDEN", "HIDDEN did not resolve")
Check(manager.alpha == 0 and manager.mouse == false, "HIDDEN must leave the manager invisible and click-through")
if classic then
    Check(type(toggle.scripts.OnClick) == "function" and toggle.mouse == false,
        "Classic HIDDEN must hook the legacy toggle button and make it click-through")
else
    Check(toggle.scripts.OnClick == nil and toggle.mouse == true,
        "Mainline must never touch a legacy toggle button")
end

-- The ownership pass hides the raid container while MSUF owns the raid frames.
raid.enabled = true
GF.ApplyBlizzardGroupFrameOwnership("addon-loaded:client-gates")
raid.enabled = nil
Check(hiddenParent ~= nil, "the hidden parent was never created")
if classic then
    Check(container.parent == hiddenParent and container.shown == false,
        "Classic must take the raid container from under Blizzard's own hidden manager")
else
    Check(container.parent == manager and container.shown == false,
        "Mainline must treat any hidden parent, the manager included, as a foreign owner")
end

print(string.format("uf_engine_client_gates_smoke: ok (%s, %s family, driver events %s)",
    flavor, client.Family, registeredText))
