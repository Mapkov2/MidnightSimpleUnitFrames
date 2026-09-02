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

local function Exists(path)
    local handle = io.open(path, "rb")
    if not handle then return false end
    handle:close()
    return true
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

-- Classic clients load their own config compiler. Keep its indexed Arena
-- scope in step with the shared core instead of only validating Mainline.
local classicConfig = Read("MidnightSimpleUnitFrames/Game/Classic/UnitFrames/MSUF_UF_Config.lua")
for _, marker in ipairs({
    "arena = { width = 180, height = 30",
    'arena = "showArenaPowerBar"',
    'arena = "enableArenaCastbar"',
    'unit:match("^arena(%d+)$")',
    'ExportPublic("MSUF_GetArenaLayoutDelta"',
}) do
    Check(classicConfig:find(marker, 1, true),
        "Classic config compiler lost its Arena contract: " .. marker)
end

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
Check(profiles:find("alphaExcludePredictionBars = true", 1, true)
        and profiles:find("alphaExcludePredictionBars = false", 1, true),
    "Arena profile alpha ownership lost the prediction-bar exclusion setting")

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

local castbarPagePreview = Read("MidnightSimpleUnitFrames/Castbars/MSUF_CastbarPreviews.lua")
local detailsStart = assert(castbarPagePreview:find("local function ResolvePreviewTestDetails", 1, true),
    "shared castbar preview detail resolver is missing")
local detailsStop = assert(castbarPagePreview:find("local function UpdatePreviewTest", detailsStart, true),
    "shared castbar preview detail resolver boundary is missing")
local compile = loadstring or load
local detailsChunk, detailsError = compile([[
local PREVIEW_UNITS = {}
]] .. castbarPagePreview:sub(detailsStart, detailsStop - 1) .. [[
return ResolvePreviewTestDetails
]], "@arena_castbar_preview_details")
Check(detailsChunk ~= nil, detailsError)
local resolvePreviewTestDetails = detailsChunk()
local showTime, showTargetName, targetLabel = resolvePreviewTestDetails(
    { unit = "arena", _msufIsArenaCastbar = true },
    { showArenaCastTime = false, showArenaCastTargetName = false })
Check(showTime == false and showTargetName == false and targetLabel == "Arena Ally",
    "Arena test preview ignored disabled time/target-name settings")
showTime, showTargetName = resolvePreviewTestDetails(
    { unit = "arena", _msufIsArenaCastbar = true },
    { showArenaCastTime = true, showArenaCastTargetName = true })
Check(showTime == true and showTargetName == true,
    "Arena test preview ignored enabled time/target-name settings")
showTime, showTargetName = resolvePreviewTestDetails(
    { unit = "boss", _msufIsBossCastbar = true },
    { showBossCastTime = false, showBossCastTargetName = true })
Check(showTime == false and showTargetName == true,
    "Boss test preview lost symmetric time/target-name behavior")

local previewEdit = Read("MidnightSimpleUnitFrames/Castbars/MSUF_CastbarPreviewEdit.lua")
for _, marker in ipairs({
    'w = "arenaCastbarWidth"',
    'h = "arenaCastbarHeight"',
    'x = "arenaCastbarOffsetX"',
    'y = "arenaCastbarOffsetY"',
    'reanchor = "MSUF_ReanchorArenaCastBar"',
    'test = "MSUF_SetArenaCastbarTestMode"',
    'or (unit == "arena" and "arenaCastbarTestMode")',
}) do
    Check(previewEdit:find(marker, 1, true),
        "Arena preview edit ownership is incomplete: " .. marker)
end

local castPopup = Read("MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_CastPopup.lua")
for _, marker in ipairs({
    'arena = "MSUF_SetArenaCastbarTestMode"',
    'if unit == "arena" then return "arenaCastbarOffsetX", "arenaCastbarOffsetY" end',
    'if unit == "arena" then return "arenaCastbarWidth" end',
    'if unit == "arena" then return "arenaCastbarHeight" end',
    'if unit == "arena" then return "arenaCastbarMatchWidth" end',
    'if unit == "arena" then return "arenaCastbarDetached" end',
    'or (unit == "arena" and "MSUF_ReanchorArenaCastBar")',
}) do
    Check(castPopup:find(marker, 1, true),
        "Arena Edit Mode cast popup ownership is incomplete: " .. marker)
end

local editModeCore = Read("MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_Core.lua")
for _, marker in ipairs({
    'if key == "player" or key == "target" or key == "focus" or key == "boss" or key == "arena" then return key end',
    'if key:match("^arena%d+$") then return "arena" end',
    'if unit:match("^arena%d+$") then return "arena" end',
    'if unit == "player" or unit == "target" or unit == "focus" or unit == "boss" or unit == "arena" then return unit end',
}) do
    Check(editModeCore:find(marker, 1, true),
        "Arena Edit Mode castbar normalization is incomplete: " .. marker)
end

local externalProvider = Read("MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_ExternalProvider.lua")
Check(externalProvider:find('arena  = { x = "arenaCastbarOffsetX",   y = "arenaCastbarOffsetY",   w = "arenaCastbarWidth",      h = "arenaCastbarHeight" }', 1, true),
    "external Edit Mode providers do not expose Arena castbar geometry")
Check(externalProvider:find('arena = "enableArenaCastbar"', 1, true),
    "external Edit Mode providers do not honor Arena castbar enablement")

for _, marker in ipairs({
    'and unit ~= "arena" then unit = nil end',
    'ClearPreviewTest(frame, "arena")',
    'local createArenaPreview = _G.MSUF_CreateArenaCastbarPreview',
    '_G.MSUF_ApplyArenaCastbarPreviewLayout(frame, index)',
    '_G.MSUF_PositionArenaCastbarPreview(frame, index)',
    '_G.MSUF_UpdateArenaCastbarPreview()',
    'general.arenaCastbarTestMode = false',
    '_G.MSUF_HideAllArenaCastbarPreviews()',
    'HideCastbarPreviewFrame(_G["MSUF_ArenaCastbarPreview" .. index])',
}) do
    Check(castbarPagePreview:find(marker, 1, true),
        "Arena global castbar-page preview lifecycle is incomplete: " .. marker)
end

local menuPagePreview = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_PagePreviews.lua")
for _, marker in ipairs({
    'and unit ~= "arena" then unit = "player" end',
    'local arenaActive = (active or castbarUnit == "arena") and true or false',
    'and lastCastbarPagePreviewUnit == castbarUnit then',
}) do
    Check(menuPagePreview:find(marker, 1, true),
        "Menu2 does not coordinate the Arena castbar-page preview: " .. marker)
end

-- Vanilla, TBC, and Mists load the Classic Menu2 page variant. It must expose
-- the same Arena page/castbar/aura/preview surface as Mainline.
local classicUnitMenu = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Unit_Classic.lua")
for _, marker in ipairs({
    'uf_arena = { unit = "arena"',
    "arena = {",
    'KSW("player target focus boss arena")',
    'WL("arena1 arena2 arena3")',
    'if key:match("^arena") then return "arena" end',
    "local function SetArenaPagePreviewActive(active)",
    "SetArenaPagePreviewActive = SetArenaPagePreviewActive",
}) do
    Check(classicUnitMenu:find(marker, 1, true),
        "Classic Menu2 Arena page contract is incomplete: " .. marker)
end

local unitSections = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitSections.lua")
for _, marker in ipairs({
    "UNIT_PAGE_FOR_UNIT[pageInfo.unit] = pageKey",
    "local pageKey = UNIT_PAGE_FOR_UNIT[tabUnit]",
    "M.SelectPage(pageKey)",
    "for key, info in pairs(UNIT_PAGES) do",
    "M.RegisterPage(key, {",
}) do
    Check(unitSections:find(marker, 1, true),
        "Arena tab click can no longer reach its registered Menu2 page: " .. marker)
end

local searchRouting = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Search/MSUF_Menu2_Search_Routing.lua")
Check(searchRouting:find('uf_arena = "arena",', 1, true),
    "Menu2 search routing cannot prepare deep Arena setting routes")

local aurasRuntime = Read("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_UnitFrames.lua")
local auraScopeStart = assert(aurasRuntime:find("local function UnitCustomDisplayScope", 1, true),
    "Auras3 custom-scope normalizer is missing")
local auraScopeStop = assert(aurasRuntime:find("local function EffectiveUnitCustomDisplays", auraScopeStart, true),
    "Auras3 custom-scope normalizer boundary is missing")
local auraScopeChunk, auraScopeError = compile(
    aurasRuntime:sub(auraScopeStart, auraScopeStop - 1) .. [[
return UnitCustomDisplayScope, UnitCustomContainerScope, UnitSupportsTargetDots
]], "@arena_auras3_target_dots")
Check(auraScopeChunk ~= nil, auraScopeError)
local _, customContainerScope, supportsTargetDots = auraScopeChunk()
for index = 1, 3 do
    local unit = "arena" .. index
    Check(customContainerScope(unit) == "arena" and supportsTargetDots(unit) == true,
        unit .. " does not inherit the Arena Target-DoT container")
end
Check(supportsTargetDots("player") == false,
    "Arena Target-DoT support leaked into Player Defensives")
Check(aurasRuntime:find("local scope = UnitCustomContainerScope(unit)", 1, true),
    "Arena runtime does not read its canonical custom-container scope")
Check(aurasRuntime:find("if not UnitSupportsTargetDots(unit) then return nil end", 1, true),
    "Arena Target-DoT portrait does not use the shared unit gate")
Check(aurasRuntime:find("elseif UnitSupportsTargetDots(unit) then", 1, true),
    "Arena normal Debuffs do not use the Target-DoT auto-blacklist gate")

-- 5) Arena match feature module -------------------------------------------------
local match = Read("MidnightSimpleUnitFrames/Features/Gameplay/MSUF_Feature_ArenaMatch.lua")
for _, marker in ipairs({
    "GetArenaOpponentSpec",
    "SetPrepNameClassColor",
    '"unseen"',
}) do
    Check(match:find(marker, 1, true),
        "arena match feature lost its contract: " .. marker)
end
-- Prep display must never touch protected visibility in combat.
Check(match:find("if InCombat() then return end", 1, true),
    "arena prep display lost its combat guard")
local loadConditions = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_LoadConditions.lua")
Check(loadConditions:find("local function ArenaPrepForcesUnit", 1, true)
        and loadConditions:find("_G.MSUF_ArenaPrepVisibilityCount", 1, true),
    "arena prep is not slot-bounded in the secure visibility owner")
local structuralPreviewElements = loadConditions:match(
    "local BOSS_PREVIEW_REFRESH_ELEMENTS = (%b{})")
Check(structuralPreviewElements and not structuralPreviewElements:find('"Alpha"', 1, true),
    "arena preview structural refresh still owns alpha")
Check(loadConditions:find("local function ReapplyArenaPreviewAlpha", 1, true)
        and loadConditions:find("if active then ReapplyArenaPreviewAlpha(refreshReason) end", 1, true)
        and loadConditions:find("ReapplyArenaPreviewAlpha(refreshReason)\n  RefreshArenaAuras()", 1, true),
    "arena preview no longer reapplies configured alpha after full and light seeds")
Check(match:find('uf.RefreshVisibilityDrivers("arena")', 1, true),
    "arena prep no longer swaps away from RegisterUnitWatch visibility")
Check(match:find("previousCount == opponentCount", 1, true),
    "arena prep does not refresh secure drivers when the opponent count changes")
local prepVisibilityPos = match:find("SyncPrepVisibility(prepCount)", 1, true)
local prepFramePos = match:find("changed = ApplyPrepFrame(frame, index)", 1, true)
Check(prepVisibilityPos and prepFramePos and prepVisibilityPos < prepFramePos,
    "arena prep data is applied before its unitless frames become securely visible")

local trinkets = Read("MidnightSimpleUnitFrames/Features/Gameplay/MSUF_Feature_ArenaTrinkets.lua")
for _, marker in ipairs({
    "SetCooldownFromDurationObject",
    "RequestCrowdControlSpell",
    "GetArenaCrowdControlInfo",
    "ARENA_CROWD_CONTROL_SPELL_UPDATE",
    "ARENA_COOLDOWNS_UPDATE",
    "MISTS_TRINKET_DURATION = 120",
}) do
    Check(trinkets:find(marker, 1, true),
        "arena trinket feature lost its contract: " .. marker)
end
Check(not trinkets:find('SetScript("OnUpdate"', 1, true),
    "arena trinket feature introduced an OnUpdate polling path")

local tocRoot = "MidnightSimpleUnitFrames/MidnightSimpleUnitFrames"
local mainlineTocPath = tocRoot .. "_Mainline.toc"
local multiClientLayout = Exists(mainlineTocPath)
if not multiClientLayout then mainlineTocPath = tocRoot .. ".toc" end

local mainlineToc = Read(mainlineTocPath)
for _, module in ipairs({
    "Features\\Gameplay\\MSUF_Feature_ArenaMatch.lua",
    "Features\\Gameplay\\MSUF_Feature_ArenaTrinkets.lua",
    "Castbars\\MSUF_ArenaCastbars.lua",
    "Castbars\\MSUF_ArenaCastbars_Preview.lua",
}) do
    Check(mainlineToc:find(module, 1, true),
        "dedicated arena runtime is missing from the Mainline TOC: " .. module)
end

local classicTocs = multiClientLayout and { "Mists", "TBC", "Vanilla" } or {}
for _, toc in ipairs(classicTocs) do
    local tocSource = Read(tocRoot .. "_" .. toc .. ".toc")
    local previousFeature
    for _, module in ipairs({
        "Features\\Gameplay\\MSUF_Feature_TotemPreview.lua",
        "Features\\Gameplay\\MSUF_Feature_ArenaMatch.lua",
        "Features\\Gameplay\\MSUF_Feature_ArenaTrinkets.lua",
    }) do
        local position = tocSource:find(module, 1, true)
        Check(position, "arena feature load order is missing from the " .. toc .. " TOC: " .. module)
        Check(not previousFeature or previousFeature < position,
            "arena feature load order is invalid in the " .. toc .. " TOC: " .. module)
        previousFeature = position
    end

    local previousCastbar
    for _, module in ipairs({
        "Castbars\\MSUF_BossCastbars.lua",
        "Castbars\\MSUF_BossCastbars_Preview.lua",
        "Castbars\\MSUF_ArenaCastbars.lua",
        "Castbars\\MSUF_ArenaCastbars_Preview.lua",
        "Castbars\\MSUF_Castbars.lua",
    }) do
        local position = tocSource:find(module, 1, true)
        Check(position, "arena castbar load order is missing from the " .. toc .. " TOC: " .. module)
        Check(not previousCastbar or previousCastbar < position,
            "arena castbar load order is invalid in the " .. toc .. " TOC: " .. module)
        previousCastbar = position
    end
end

-- Classic exposes the arena lifecycle events but not
-- PVP_MATCH_STATE_CHANGED. Pin both sides of the runtime event-validity gate:
-- invalid clients must never register or unregister it, while Retail keeps it.
local function ExerciseArenaCastbarEventGate(valid)
    local registeredEvents, unregisteredEvents = {}, {}
    _G.C_EventUtils = {
        IsEventValid = function(event)
            Check(event == "PVP_MATCH_STATE_CHANGED", "arena castbars validated the wrong event")
            return valid
        end,
    }
    _G.MSUF_DB = { general = { enableArenaCastbar = true } }
    _G.EnsureDB = function() end
    _G.MSUF_ShouldUseMSUFCastbar = function() return true end
    _G.MSUF_EventBus_Register = function(event)
        registeredEvents[event] = true
        return true
    end
    _G.MSUF_EventBus_Unregister = function(event)
        unregisteredEvents[event] = true
        return true
    end

    local gateNamespace = {
        ExportPublic = function(name, value)
            _G[name] = value
            return value
        end,
    }
    assert(loadfile("MidnightSimpleUnitFrames/Castbars/MSUF_ArenaCastbars.lua"))(
        "MidnightSimpleUnitFrames", gateNamespace)

    for _, event in ipairs({
        "PLAYER_LOGIN",
        "PLAYER_ENTERING_WORLD",
        "ARENA_OPPONENT_UPDATE",
        "ARENA_PREP_OPPONENT_SPECIALIZATIONS",
    }) do
        Check(registeredEvents[event] == true and unregisteredEvents[event] == true,
            "arena castbar lifecycle lost its valid event: " .. event)
    end
    Check((registeredEvents.PVP_MATCH_STATE_CHANGED == true) == valid,
        "arena castbars registered PVP_MATCH_STATE_CHANGED against IsEventValid")
    Check((unregisteredEvents.PVP_MATCH_STATE_CHANGED == true) == valid,
        "arena castbars unregistered PVP_MATCH_STATE_CHANGED against IsEventValid")
end

ExerciseArenaCastbarEventGate(false)
ExerciseArenaCastbarEventGate(true)

print("arena_unit_scope_smoke: ok")
