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
--   PvP context   Classic has no War Mode: the context follows the player's PvP
--                 flag, the driver listens to the flag events and recompiles in
--                 combat. Mainline keeps Retail's War Mode driver, which never
--                 recompiles in combat.
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
env.UnitIsPVP = function(unit) return unit == "player" and pvp.flagged end
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
local UF = assert(world.core.UF, "no MSUF.UF")
local Config = assert(UF.Config, "no UF.Config")

---------------------------------------------------------------------------
-- PvP context driver
---------------------------------------------------------------------------
local driver = assert(UF.pvpIndicatorContextDriver, "no PvP context driver")
local registered = {}
for event in pairs(driver.events) do registered[#registered + 1] = event end
table.sort(registered)
local registeredText = table.concat(registered, ",")
if classic then
    local expected = { "PLAYER_ENTERING_WORLD", "PLAYER_FLAGS_CHANGED", "UNIT_FACTION", "ZONE_CHANGED_NEW_AREA" }
    if client.SupportsEvent("PVP_TIMER_UPDATE") then expected[#expected + 1] = "PVP_TIMER_UPDATE" end
    table.sort(expected)
    Check(registeredText == table.concat(expected, ","),
        "the Classic PvP context driver registers " .. registeredText .. ", expected the flag events " .. table.concat(expected, ","))
    Check(unitFilters[driver] and unitFilters[driver].UNIT_FACTION == "player",
        "the Classic PvP context driver must watch UNIT_FACTION for the player only")
else
    Check(registeredText == "ACTIVE_GAME_MODE_UPDATED,PLAYER_ENTERING_WORLD,WAR_MODE_STATUS_UPDATE,ZONE_CHANGED_NEW_AREA",
        "the Mainline PvP context driver must keep Retail's War Mode events, registers " .. registeredText)
end

local function Context()
    UF.InvalidatePVPIndicatorContext()
    return UF.PVPIndicatorContextActive()
end

ResetPvP()
Check(Context() == false, "an unflagged player outside PvP content must have no PvP context")
pvp.flagged = true
Check(Context() == classic, classic and "Classic must follow the player's PvP flag"
    or "Mainline must ignore the PvP flag outside War Mode")
ResetPvP(); pvp.ffa = true
Check(Context() == classic, "free-for-all PvP must count on Classic only")
ResetPvP(); pvp.timer = true
Check(Context() == classic, "the PvP flag timer must count on Classic only")
ResetPvP(); pvp.warMode = true
Check(Context() == true, "War Mode must open the PvP context")
ResetPvP(); pvp.instance = "arena"
Check(Context() == true, "arenas must open the PvP context")
ResetPvP(); pvp.instance = "party"; pvp.flagged = true
Check(Context() == false, "dungeons must close the PvP context even when flagged")

-- Driver reaction: the flag flips mid-combat on Classic, so its driver
-- recompiles there; Retail's driver never recompiles in combat.
local refreshes = 0
local refreshElements = UF.RefreshElements
UF.RefreshElements = function() refreshes = refreshes + 1 end
local handler = assert(driver.scripts and driver.scripts.OnEvent, "the PvP context driver has no OnEvent script")
ResetPvP()
Context()
pvp.flagged = true
world.widgets:SetCombat(true)
handler(driver, classic and "UNIT_FACTION" or "ZONE_CHANGED_NEW_AREA", classic and "player" or nil)
world.widgets:SetCombat(false)
if classic then
    Check(refreshes == 1 and UF.PVPIndicatorContextActive() == true,
        "getting flagged in combat must recompile the Classic PvP context at once")
    refreshes = 0
    pvp.flagged = false
    handler(driver, "PLAYER_FLAGS_CHANGED", "party1")
    Check(refreshes == 0 and UF.PVPIndicatorContextActive() == true,
        "another unit's flag change must not touch the Classic PvP context")
    handler(driver, "PLAYER_FLAGS_CHANGED", "player")
    Check(refreshes == 1 and UF.PVPIndicatorContextActive() == false,
        "the player's own flag change must recompile the Classic PvP context")
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
if classic then
    ResetPvP()
    Context()
    refreshes = 0
    pvp.flagged = true
    handler(driver, "UNIT_FACTION", "party1")
    Check(refreshes == 0, "another unit's UNIT_FACTION must still be ignored")
    handler(driver, "UNIT_FACTION", "player")
    Check(refreshes == 1, "the player's own UNIT_FACTION must still recompile")
end
UF.RefreshElements = refreshElements
ResetPvP()
Context()

---------------------------------------------------------------------------
-- Unit support
---------------------------------------------------------------------------
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
local namespace = {
    Client = client,
    ExportPublic = function(name, value) sandbox[name] = value; return value end,
    GF = { GetConf = function(kind) return kind == "party" and party or {} end },
}
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

GF.HideBlizzardRaidFrames()
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
