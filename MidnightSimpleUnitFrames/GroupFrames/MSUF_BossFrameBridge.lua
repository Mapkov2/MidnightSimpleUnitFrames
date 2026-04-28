-- MSUF_BossFrameBridge.lua
-- ============================================================================
-- Bridges MSUF's standalone boss1..boss5 unitframes into the GF private-aura
-- subsystem so friendly-boss NPCs (e.g. healable encounter allies) display
-- the same icons + 12.0.5 Private Aura Dispel Overlay as party/raid frames.
--
-- This is purely additive:
--   • Boss frames are NOT registered as GF children — GF layout, range fade,
--     aggro logic, and the header-child secure template are untouched.
--   • We only call GF.ApplyPrivateAuras / GF.ApplyPrivateAuraContainerOverlay
--     with an *explicit* config table, which the GF path supports via the
--     paOverride parameter on ApplyPrivateAuras.
--   • AddPrivateAuraAnchor is NOT combat-safe — all sync calls defer until
--     PLAYER_REGEN_ENABLED if combat is active.
--
-- Why not hook UF's own private-aura path? The existing UF A2 subsystem
-- scans *addon-visible* auras; private auras are Blizzard-hidden and require
-- a dedicated anchor-registration API (C_UnitAuras.AddPrivateAuraAnchor).
-- GF already implements that API correctly with combat deferral and 12.0.5
-- container-overlay support, so reusing it is strictly simpler than porting
-- the logic into UF/A2.
-- ============================================================================
local _, ns = ...
ns.BossBridge = ns.BossBridge or {}
local BB = ns.BossBridge

local GF = ns.GF
if not GF or type(GF.ApplyPrivateAuras) ~= "function" then
    -- GF module not loaded (e.g. user disabled it via load condition). Nothing
    -- to bridge — silently no-op rather than failing the whole addon load.
    return
end

local CreateFrame      = _G.CreateFrame
local C_Timer          = _G.C_Timer
local InCombatLockdown = _G.InCombatLockdown

-- Keep in lockstep with MSUF_MAX_BOSS_FRAMES in MidnightSimpleUnitFrames.lua.
-- If that constant bumps to 8 for 12.0 parity, update here too.
local MAX_BOSS = 5

------------------------------------------------------------------------
-- Config
--
-- Stored under MSUF_DB.boss.privateAuras to keep the boss-frame namespace
-- separate from GF's per-kind (party / raid) config. Mirrors the shape of
-- GF party/raid privateAuras so GF.ApplyPrivateAuras can consume it via
-- the paOverride parameter without any conf-shape translation.
------------------------------------------------------------------------
local BOSS_PA_DEFAULTS = {
    enabled        = false,                 -- OPT-IN: off by default
    max            = 4,
    size           = 22,
    anchor         = "BOTTOMRIGHT",
    direction      = "LEFT",
    x              = 0,
    y              = 0,
    showCountdown  = true,
    showNumbers    = true,
    layer          = 8,
    containerOverlay = {
        enabled     = false,
        showIcons   = true,
        dispelMode  = "dispellableByMe",    -- or "allDispellable"
        gradientDir = "default",
    },
}

local function _EnsureBossPAConf()
    local db = _G.MSUF_DB
    if not db then return nil end
    db.boss = db.boss or {}

    local bpa = db.boss.privateAuras
    if type(bpa) ~= "table" then
        bpa = {}
        db.boss.privateAuras = bpa
    end
    -- Seed missing keys from defaults (non-destructive; user values preserved).
    for k, v in pairs(BOSS_PA_DEFAULTS) do
        if bpa[k] == nil then
            if type(v) == "table" then
                bpa[k] = {}
                for k2, v2 in pairs(v) do bpa[k][k2] = v2 end
            else
                bpa[k] = v
            end
        end
    end
    -- Ensure container sub-table is complete on upgrade paths.
    if type(bpa.containerOverlay) ~= "table" then
        bpa.containerOverlay = {}
    end
    for k, v in pairs(BOSS_PA_DEFAULTS.containerOverlay) do
        if bpa.containerOverlay[k] == nil then
            bpa.containerOverlay[k] = v
        end
    end
    return bpa
end

BB.GetConf = _EnsureBossPAConf

------------------------------------------------------------------------
-- Sync
------------------------------------------------------------------------
local _needsPostCombatSync = false
local _pendingSync         = false

local function _GetBossFrame(i)
    local unit = "boss" .. i
    local uf = _G.MSUF_UnitFrames
    return (uf and uf[unit]) or _G["MSUF_" .. unit], unit
end

local function _SyncOne(bossFrame, unit, conf)
    if not bossFrame or not unit or not conf then return end

    -- Icon anchors (private aura slots). paOverride lets GF skip the
    -- per-kind lookup and read directly from the boss config.
    GF.ApplyPrivateAuras(bossFrame, unit, conf)

    -- 12.0.5+ Blizzard-rendered dispel overlay (no-op on older clients —
    -- ApplyPrivateAuraContainerOverlay internally gates on
    -- GF._privateAuraContainerSupported).
    if type(GF.ApplyPrivateAuraContainerOverlay) == "function" then
        GF.ApplyPrivateAuraContainerOverlay(bossFrame, unit, conf)
    end
end

local function _SyncAll()
    _pendingSync = false
    if InCombatLockdown and InCombatLockdown() then
        _needsPostCombatSync = true
        return
    end
    local conf = _EnsureBossPAConf()
    if not conf then return end

    for i = 1, MAX_BOSS do
        local bf, unit = _GetBossFrame(i)
        if bf then _SyncOne(bf, unit, conf) end
    end
end

local function _ScheduleSync()
    if _pendingSync then return end
    _pendingSync = true
    if C_Timer and C_Timer.After then
        if _G.MSUF_ScheduleOnce then _G.MSUF_ScheduleOnce("GF_BOSS_BRIDGE_SYNC", _SyncAll) else C_Timer.After(0, _SyncAll) end
    else
        _SyncAll()
    end
end

-- Public: re-apply settings across all boss frames (used by Options
-- live-apply on settings change).
BB.RefreshAll = _ScheduleSync
BB.Sync       = _ScheduleSync

------------------------------------------------------------------------
-- Event driver
--
-- Boss units spawn/despawn at encounter boundaries and UNIT_TARGETABLE_CHANGED
-- fires when a boss-slot NPC comes into range. Each of these triggers a
-- debounced full sync — cheap because _SyncAll internally diff-gates in
-- GF.ApplyPrivateAuras (skip rebuild when unit/size/max/anchor/dir match).
------------------------------------------------------------------------
local _ev = CreateFrame("Frame")
_ev:RegisterEvent("PLAYER_ENTERING_WORLD")
_ev:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
_ev:RegisterEvent("ENCOUNTER_END")
_ev:RegisterEvent("UNIT_TARGETABLE_CHANGED")
_ev:RegisterEvent("PLAYER_REGEN_ENABLED")
_ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_REGEN_ENABLED" then
        if _needsPostCombatSync then
            _needsPostCombatSync = false
            _ScheduleSync()
        end
        return
    end
    if event == "UNIT_TARGETABLE_CHANGED" then
        -- Only care about boss1..bossN; other unit changes are irrelevant.
        if type(arg1) == "string" and arg1:sub(1, 4) == "boss" then
            _ScheduleSync()
        end
        return
    end
    -- PLAYER_ENTERING_WORLD / INSTANCE_ENCOUNTER_ENGAGE_UNIT / ENCOUNTER_END
    _ScheduleSync()
end)

-- Deferred initial sync: boss frames are created after this file loads,
-- so an immediate _SyncAll() would find nothing. The PLAYER_ENTERING_WORLD
-- fire covers the first real sync.
