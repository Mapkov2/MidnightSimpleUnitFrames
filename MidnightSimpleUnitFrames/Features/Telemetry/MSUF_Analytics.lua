--- Wago Analytics integration for MSUF beta telemetry.
--- Cold-path only: one session snapshot, never from combat, no OnUpdate or hot-path hooks.
--- Telemetry must stay opt-in/defensive and may read coarse configuration state only; it
--- should not observe unit events, frame state, profile import payloads, or user text input.
local addonName, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local LibStub = _G.LibStub
local CreateFrame = _G.CreateFrame
local C_Timer = _G.C_Timer
local InCombatLockdown = _G.InCombatLockdown
local GetAddOnMetadata = _G.C_AddOns and _G.C_AddOns.GetAddOnMetadata or _G.GetAddOnMetadata

local type = type
local tostring = tostring
local tonumber = tonumber
local pairs = pairs
local math_floor = math.floor
local string_lower = string.lower
local string_gsub = string.gsub
local string_match = string.match

local Analytics = MSUF.Analytics or {}
MSUF.Analytics = Analytics

local ADDON_NAME = addonName or "MidnightSimpleUnitFrames"
local eventFrame
local session
local registerAttempted = false
local sessionSent = false
local pendingAfterCombat = false

local function Print(msg)
    if _G.DEFAULT_CHAT_FRAME and _G.DEFAULT_CHAT_FRAME.AddMessage then
        _G.DEFAULT_CHAT_FRAME:AddMessage("|cff7aa2f7MSUF|r: " .. tostring(msg))
    elseif _G.print then
        _G.print("|cff7aa2f7MSUF|r: " .. tostring(msg))
    end
end

local function EnsureGlobalAnalytics(create)
    local gdb = _G.MSUF_GlobalDB
    if type(gdb) ~= "table" then
        if not create then return nil end
        gdb = {}
        ExportPublic("MSUF_GlobalDB", gdb)
    end

    local global = gdb.global
    if type(global) ~= "table" then
        if not create then return nil end
        global = {}
        gdb.global = global
    end

    local analytics = global.analytics
    if type(analytics) ~= "table" then
        if not create then return nil end
        analytics = {}
        global.analytics = analytics
    end

    if analytics.enabled == nil then
        -- Default-on matches existing beta telemetry behavior, but the flag remains stored in
        -- GlobalDB so users/builds can disable it persistently.
        analytics.enabled = true
    end

    return analytics
end

local function IsEnabled()
    local analytics = EnsureGlobalAnalytics(false)
    return not (analytics and analytics.enabled == false)
end
Analytics.IsEnabled = IsEnabled

local function IsInCombat()
    if _G.MSUF_InCombat == true then return true end
    return (InCombatLockdown and InCombatLockdown()) and true or false
end

local FlushSession
local QueueAfterCombat

local function EnsureEventFrame()
    if eventFrame then return eventFrame end

    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_LOGIN" then
            self:UnregisterEvent("PLAYER_LOGIN")
            if IsInCombat() then
                -- Login can complete during combat reloads. Defer instead of touching analytics
                -- libraries while protected state is unstable.
                QueueAfterCombat()
                return
            end
            C_Timer.After(0, function()
                FlushSession("login")
            end)
        elseif event == "PLAYER_REGEN_ENABLED" then
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            pendingAfterCombat = false
            FlushSession("regen")
        end
    end)

    return eventFrame
end

QueueAfterCombat = function()
    if pendingAfterCombat then return end
    pendingAfterCombat = true
    EnsureEventFrame():RegisterEvent("PLAYER_REGEN_ENABLED")
end

local function GetAnalyticsSession()
    if session then return session end
    if registerAttempted then return nil end
    if not IsEnabled() then return nil end
    if IsInCombat() then
        QueueAfterCombat()
        return nil
    end
    if not LibStub then return nil end

    local lib = LibStub("WagoAnalytics", true)
    if not lib then return nil end

    -- WagoAnalytics has shipped multiple registration names; use the one present.
    registerAttempted = true
    local result
    if type(lib.RegisterAddon) == "function" then
        result = lib:RegisterAddon(ADDON_NAME)
    elseif type(lib.RegisterAddOn) == "function" then
        result = lib:RegisterAddOn(ADDON_NAME)
    elseif type(lib.Register) == "function" and type(GetAddOnMetadata) == "function" then
        local wagoID = GetAddOnMetadata(ADDON_NAME, "X-Wago-ID")
        if wagoID then
            result = lib:Register(wagoID)
        end
    end

    if type(result) == "table" then
        session = result
    end

    return session
end

local function ApplySwitch(target, key, value)
    local fn = target and target.Switch
    if type(fn) ~= "function" then return end
    fn(target, key, value and true or false)
end

local function ApplyCounter(target, key, value)
    local n = tonumber(value)
    if not n then return end
    local fn = target and target.SetCounter
    if type(fn) ~= "function" then return end
    fn(target, key, n)
end

local function Round(value)
    local n = tonumber(value)
    if not n then return nil end
    if n >= 0 then return math_floor(n + 0.5) end
    return -math_floor((-n) + 0.5)
end

local function EnabledUnlessFalse(conf)
    return type(conf) == "table" and conf.enabled ~= false
end

local function Bool(value)
    return value and true or false
end

local function CountProfiles()
    local profiles = _G.MSUF_GlobalDB and _G.MSUF_GlobalDB.profiles
    if type(profiles) ~= "table" then return 0 end

    local count = 0
    for _ in pairs(profiles) do
        count = count + 1
    end
    return count
end

local function SanitizeMetricPart(value)
    local text = tostring(value or "")
    text = string_gsub(text, "[^%w]+", "_")
    text = string_gsub(text, "^_+", "")
    text = string_gsub(text, "_+$", "")
    return text
end

local function EnsureMSUFDB()
    local ensureDB = _G.MSUF_EnsureDB
    if type(ensureDB) == "function" then
        ensureDB()
    end

    local db = _G.MSUF_DB
    if type(db) == "table" then return db end
    return nil
end

local function CollectSessionSnapshot(target)
    local db = EnsureMSUFDB()
    if not db then return end

    -- Snapshot data is coarse feature/config shape only. Do not include unit state, profile
    -- import strings, user-entered Assistant text, or frame positions.
    local general = type(db.general) == "table" and db.general or {}
    local gameplay = type(db.gameplay) == "table" and db.gameplay or {}
    local auras3 = type(db.auras3) == "table" and db.auras3 or {}
    local aurasShared = type(auras3.shared) == "table" and auras3.shared or {}

    ApplySwitch(target, "Addon_Loaded", true)
    ApplySwitch(target, "Analytics_Enabled", true)

    if type(GetAddOnMetadata) == "function" then
        local version = GetAddOnMetadata(ADDON_NAME, "Version")
        local versionKey = SanitizeMetricPart(version)
        if versionKey ~= "" then
            ApplySwitch(target, "Version_" .. versionKey, true)
        end
    end

    local unitCount = 0
    local function UnitSwitch(metric, key)
        local enabled = EnabledUnlessFalse(db[key])
        ApplySwitch(target, metric, enabled)
        if enabled then unitCount = unitCount + 1 end
    end

    UnitSwitch("UF_Player", "player")
    UnitSwitch("UF_Target", "target")
    UnitSwitch("UF_TargetTarget", "targettarget")
    UnitSwitch("UF_Focus", "focus")
    UnitSwitch("UF_Pet", "pet")
    UnitSwitch("UF_Boss", "boss")
    ApplyCounter(target, "UF_EnabledCount", unitCount)

    ApplyCounter(target, "Player_Width", Round(db.player and db.player.width))
    ApplyCounter(target, "Player_Height", Round(db.player and db.player.height))
    ApplyCounter(target, "Target_Width", Round(db.target and db.target.width))
    ApplyCounter(target, "Target_Height", Round(db.target and db.target.height))

    local castbarCount = 0
    local function CastbarSwitch(metric, value)
        local enabled = value ~= false
        ApplySwitch(target, metric, enabled)
        if enabled then castbarCount = castbarCount + 1 end
    end

    CastbarSwitch("Castbar_Player", general.enablePlayerCastbar)
    CastbarSwitch("Castbar_Target", general.enableTargetCastbar)
    CastbarSwitch("Castbar_Focus", general.enableFocusCastbar)
    CastbarSwitch("Castbar_Boss", general.enableBossCastbar)
    ApplyCounter(target, "Castbar_EnabledCount", castbarCount)

    local groupCount = 0
    local function GroupSwitch(metric, key)
        local enabled = type(db[key]) == "table" and db[key].enabled == true
        ApplySwitch(target, metric, enabled)
        if enabled then groupCount = groupCount + 1 end
    end

    GroupSwitch("GF_Party", "gf_party")
    GroupSwitch("GF_Raid", "gf_raid")
    GroupSwitch("GF_MythicRaid", "gf_mythicraid")
    ApplyCounter(target, "GF_EnabledCount", groupCount)

    ApplySwitch(target, "Auras3_Enabled", auras3.enabled ~= false)
    ApplySwitch(target, "Auras3_Target", auras3.showTarget ~= false)
    ApplySwitch(target, "Auras3_Focus", auras3.showFocus ~= false)
    ApplySwitch(target, "Auras3_Boss", auras3.showBoss ~= false)
    ApplyCounter(target, "Auras3_MaxIcons", Round(aurasShared.maxIcons))

    local gameplayCount = 0
    local function GameplaySwitch(metric, value)
        local enabled = Bool(value)
        ApplySwitch(target, metric, enabled)
        if enabled then gameplayCount = gameplayCount + 1 end
    end

    GameplaySwitch("Gameplay_CombatTimer", gameplay.enableCombatTimer)
    GameplaySwitch("Gameplay_CombatStateText", gameplay.enableCombatStateText)
    GameplaySwitch("Gameplay_CombatCrosshair", gameplay.enableCombatCrosshair)
    GameplaySwitch("Gameplay_CrosshairRangeColor", gameplay.enableCombatCrosshairMeleeRangeColor)
    GameplaySwitch("Gameplay_PlayerTotems", gameplay.enablePlayerTotems)
    ApplyCounter(target, "Gameplay_EnabledCount", gameplayCount)

    ApplySwitch(target, "Style_ClassColors", general.useClassColors ~= false)
    ApplySwitch(target, "Style_DarkMode", general.darkMode == true)
    ApplySwitch(target, "Style_Gradient", general.enableGradient == true)
    ApplySwitch(target, "Style_HealthGradient", general.enableHealthGradient ~= false)
    local uiScale = (type(general.UIScale) == "table") and general.UIScale or nil
    ApplySwitch(target, "Style_GlobalScalingDisabled", not (uiScale and uiScale.Enabled == true))
    ApplyCounter(target, "Profiles_Count", CountProfiles())
    ApplyCounter(target, "MSUF_UiScalePct", Round((tonumber(general.msufUiScale) or 1) * 100))
end

FlushSession = function(reason)
    if sessionSent then return end
    if not IsEnabled() then return end
    if IsInCombat() then
        QueueAfterCombat()
        return
    end

    local target = GetAnalyticsSession()
    if not target then return end

    CollectSessionSnapshot(target)
    sessionSent = true
end
Analytics.FlushSession = FlushSession

function Analytics.SetEnabled(enabled, quiet)
    local analytics = EnsureGlobalAnalytics(true)
    if not analytics then return end

    analytics.enabled = enabled and true or false

    if not analytics.enabled then
        if eventFrame then
            eventFrame:UnregisterAllEvents()
        end
        pendingAfterCombat = false
        if not quiet then
            Print("Wago Analytics disabled. Use |cffc0caf5/msuf analytics on|r to enable it again.")
        end
        return
    end

    if not quiet then
        Print("Wago Analytics enabled. Use |cffc0caf5/msuf analytics off|r to disable it.")
    end
    FlushSession("slash")
end

function Analytics.PrintStatus()
    if IsEnabled() then
        Print("Wago Analytics is enabled. Use |cffc0caf5/msuf analytics off|r to disable it.")
    else
        Print("Wago Analytics is disabled. Use |cffc0caf5/msuf analytics on|r to enable it.")
    end
end

function Analytics.HandleSlash(rest)
    rest = string_lower(tostring(rest or ""))
    rest = string_gsub(rest, "^%s+", "")
    rest = string_gsub(rest, "%s+$", "")

    local cmd = string_match(rest, "^(%S+)") or "status"
    if cmd == "off" or cmd == "disable" or cmd == "disabled" then
        Analytics.SetEnabled(false)
    elseif cmd == "on" or cmd == "enable" or cmd == "enabled" then
        Analytics.SetEnabled(true)
    elseif cmd == "status" or cmd == "" then
        Analytics.PrintStatus()
    else
        Print("Usage: |cffc0caf5/msuf analytics off|r, |cffc0caf5/msuf analytics on|r, |cffc0caf5/msuf analytics status|r")
    end
end

ExportPublic("MSUF_Analytics_HandleSlash", function(rest)
    Analytics.HandleSlash(rest)
end)
ExportPublic("MSUF_Analytics_SetEnabled", function(enabled, quiet)
    Analytics.SetEnabled(enabled, quiet)
end)
ExportPublic("MSUF_Analytics_IsEnabled", function()
    return Analytics.IsEnabled()
end)

if IsEnabled() then EnsureEventFrame():RegisterEvent("PLAYER_LOGIN") end
