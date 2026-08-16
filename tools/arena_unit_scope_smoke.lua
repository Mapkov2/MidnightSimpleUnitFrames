-- arena_unit_scope_smoke.lua
-- Contract smoke for the dedicated arena1-3 unit-frame scope.
-- Pins the registration surface a new indexed unit family must keep in step:
--   1. Engine roster: UF.unitOrder / UF.configKeyUnits / ConfigKeyForUnit.
--   2. State seeding: fill("arena") keys incl. the reused boss stacked-layout
--      keys (spacing/bossLayoutMode), the trinket toggle, and root-table entry.
--   3. Profile IO: arena in the unit-key ledgers and the arenacast castbar
--      key marker.
--   4. Castbars: the arenaCastbar* key family and the arena castbar module's
--      lifecycle exports.
-- Run from the repo root with no arguments: lua tools/arena_unit_scope_smoke.lua

local function Check(ok, message)
    if not ok then
        error(message, 2)
    end
end

local function Read(path)
    local handle = assert(io.open(path, "rb"), "missing file: " .. path)
    local source = handle:read("*a")
    handle:close()
    -- Editor saves CRLF; normalize so "\n"-anchored patterns match locally.
    return (source:gsub("\r\n", "\n"))
end

-- 1) Engine roster ----------------------------------------------------------
local core = Read("MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Core.lua")
Check(core:find('"arena1", "arena2", "arena3",', 1, true),
    "UF.unitOrder does not spawn arena1..arena3")
Check(core:find('arena = { "arena1", "arena2", "arena3" },', 1, true),
    "UF.configKeyUnits lacks the arena config-key fan-out")
Check(core:find('if ARENA_UNITS[unit] then return "arena" end', 1, true),
    "ConfigKeyForUnit does not collapse arenaN to the arena scope")
Check(core:find('return "ARENA_OPPONENT_UPDATE"', 1, true),
    "arena frames lost their OnShow identity follow-up event")
Check(core:find('AddEventHandler(frame, "ARENA_OPPONENT_UPDATE", ArenaOpponentIdentityUpdate, false)', 1, true),
    "arena identity lifecycle no longer listens to ARENA_OPPONENT_UPDATE")
Check(core:find("QueueDependentIdentity(frame, event)", 1, true),
    "arena opponent updates lost their burst coalescer")

-- 2) State seeding -----------------------------------------------------------
local defaults = Read("MidnightSimpleUnitFrames/State/MSUF_Defaults.lua")
Check(defaults:find('fill("arena", {', 1, true),
    "State defaults no longer seed the arena scope")
Check(defaults:find('"arena",\n}', 1, true) or defaults:find('"arena",', 1, true),
    "MSUF_DEFAULTS_ROOT_TABLE_KEYS lost the arena root table")
local arenaFill = defaults:match('fill%("arena", %{(.-)%}%)')
Check(type(arenaFill) == "string", "arena fill block is unreadable")
for _, key in ipairs({ "spacing", "bossLayoutMode", "showInterrupt", "portraitMode" }) do
    Check(arenaFill:find(key, 1, true), "arena fill block lost key: " .. key)
end
Check(defaults:find("MSUF_DB.arena.showTrinket", 1, true),
    "arena trinket toggle default is gone")
Check(defaults:find('_InitCastbarBackend("arena", "arenaCastbarBackend", "enableArenaCastbar")', 1, true),
    "arena castbar backend is no longer initialized")
Check(defaults:find('"arena1", "arena2", "arena3",', 1, true),
    "arena1..3 left the unit-aura runtime unit list")

-- 3) Profile IO ---------------------------------------------------------------
local profiles = Read("MidnightSimpleUnitFrames/State/MSUF_Profiles.lua")
Check(profiles:find('"focus", "pet", "boss", "arena" }', 1, true),
    "MSUF_PROFILEIO_UNIT_KEYS lost the arena scope")
Check(profiles:find('lk:find("arenacast", 1, true)', 1, true),
    "MSUF_IsCastbarKey no longer recognizes arenaCast keys")
Check(profiles:find('"arena", "arena1", "arena2", "arena3",', 1, true),
    "profile text-scope ledger lost the arena scopes")

-- 4) Castbars ------------------------------------------------------------------
local anchors = Read("MidnightSimpleUnitFrames/Castbars/MSUF_CastbarAnchors.lua")
Check(anchors:find('arena  = { w = "arenaCastbarWidth"', 1, true),
    "UNIT_CASTBAR lost the arenaCastbar* key family")
Check(anchors:find('"player", "target", "focus", "boss", "arena"', 1, true),
    "CASTBAR_UNITS no longer syncs the arena castbars")
local arenaCastbars = Read("MidnightSimpleUnitFrames/Castbars/MSUF_ArenaCastbars.lua")
for _, marker in ipairs({
    'ExportPublic("MSUF_ApplyArenaCastbarPositionSetting"',
    'ExportPublic("MSUF_ArenaCastbars_SyncLifecycle"',
    '"ARENA_OPPONENT_UPDATE"',
    '"ARENA_PREP_OPPONENT_SPECIALIZATIONS"',
    '"PVP_MATCH_STATE_CHANGED"',
}) do
    Check(arenaCastbars:find(marker, 1, true),
        "MSUF_ArenaCastbars lost its lifecycle contract: " .. marker)
end

-- 5) Arena match feature module -------------------------------------------------
local match = Read("MidnightSimpleUnitFrames/Features/Gameplay/MSUF_Feature_ArenaMatch.lua")
for _, marker in ipairs({
    "GetArenaOpponentSpec",
    "SetCooldownFromDurationObject",
    '"unseen"',
    "RequestCrowdControlSpell",
}) do
    Check(match:find(marker, 1, true),
        "arena match feature lost its contract: " .. marker)
end
-- Prep display must never touch protected visibility in combat.
Check(match:find("if InCombat() then return end", 1, true),
    "arena prep display lost its combat guard")

print("arena_unit_scope_smoke: ok")
