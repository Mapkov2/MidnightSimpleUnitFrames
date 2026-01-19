--[[
MSUF_UnitframeCore.lua

Goal:
 - Centralize unitframe event routing + update scheduling.
 - Coalesce bursts (target swap spam) into a single flush per frame.
 - Enable element-style updates later without scattering logic through MidnightSimpleUnitFrames.lua.

Design notes:
 - We do NOT touch Edit Mode here.
 - Auras 2.0 already has its own event driver; unitframes should not register UNIT_AURA.
 - Keep legacy entrypoints (_G.MSUF_QueueUnitframeUpdate / Visual / Warmup) so other files keep working.
]]

local addonName, addon = ...

addon = addon or {}

local Core = {}

-- UFCore flush budgeting: configurable via MSUF_DB.general
-- Defaults are ensured in MSUF_Defaults.lua.
local function UFCore_GetFlushBudgetSettings()
    local g = _G.MSUF_DB and _G.MSUF_DB.general
    local budgetMs = g and g.ufcoreFlushBudgetMs
    if type(budgetMs) ~= "number" then budgetMs = 2.0 end
    if budgetMs < 0.25 then budgetMs = 0.25 elseif budgetMs > 10.0 then budgetMs = 10.0 end

    local urgentMax = g and g.ufcoreUrgentMaxPerFlush
    if type(urgentMax) ~= "number" then urgentMax = 10 end
    urgentMax = math.floor(urgentMax + 0.5)
    if urgentMax < 1 then urgentMax = 1 elseif urgentMax > 200 then urgentMax = 200 end

    return budgetMs, urgentMax
end

addon.MSUF_UnitframeCore = Core

-- Deferred layout application (combat safety)
Core._layoutDeferredSet = Core._layoutDeferredSet or {}

-- ------------------------------------------------------------
-- Locals (perf + clarity; behavior-preserving)
-- ------------------------------------------------------------
local _G = _G
local type = type
local pairs = pairs
local tonumber = tonumber
local tostring = tostring
local select = select
local CreateFrame = CreateFrame
local debugprofilestop = debugprofilestop
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local UnitExists = UnitExists
local UnitName = UnitName
local UnitLevel = UnitLevel
local UnitClass = UnitClass
local UnitReaction = UnitReaction
local UnitIsPlayer = UnitIsPlayer
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitIsGroupLeader = UnitIsGroupLeader
local UnitIsGroupAssistant = UnitIsGroupAssistant
local GetRaidTargetIndex = GetRaidTargetIndex
local SetRaidTargetIconTexture = SetRaidTargetIconTexture
local tremove = table.remove
local wipe = wipe
if not wipe then
    wipe = function(t)
        if not t then return end
        for k in pairs(t) do t[k] = nil end
    end
end

local bit = _G.bit
local bit32 = _G.bit32

local bor = (bit and bit.bor) or (bit32 and bit32.bor)
local band = (bit and bit.band) or (bit32 and bit32.band)
local bnot = (bit and bit.bnot) or (bit32 and bit32.bnot)

-- Safety fallback: should never be needed in WoW, but keeps this file resilient.
if not (bor and band and bnot) then
    local MOD = 4294967296 -- 2^32
    local function norm32(x)
        x = x or 0
        if x < 0 then x = x % MOD end
        return x
    end
    local function bitop(a, b, fn)
        a, b = norm32(a), norm32(b)
        local res, bitv = 0, 1
        for _ = 1, 32 do
            local aa = a % 2
            local bb = b % 2
            if fn(aa, bb) then res = res + bitv end
            a = (a - aa) / 2
            b = (b - bb) / 2
            bitv = bitv * 2
        end
        return res
    end
    bor = bor or function(a, b) return bitop(a, b, function(x, y) return (x == 1) or (y == 1) end) end
    band = band or function(a, b) return bitop(a, b, function(x, y) return (x == 1) and (y == 1) end) end
    bnot = bnot or function(a) return (MOD - 1) - norm32(a) end
end
-- ------------------------------------------------------------
-- Dirty flags (future: element updates)
-- ------------------------------------------------------------

local DIRTY_FULL      = 0xFFFFFFFF
local DIRTY_HEALTH    = 0x00000001
local DIRTY_POWER     = 0x00000002
local DIRTY_IDENTITY  = 0x00000004
local DIRTY_PORTRAIT  = 0x00000008
local DIRTY_STATUS    = 0x00000010
local DIRTY_INDICATOR = 0x00000020
local DIRTY_TOTINLINE = 0x00000040

local DIRTY_LAYOUT   = 0x00000080
local DIRTY_VISUAL   = 0x00000100  -- forces a one-shot legacy pass for bar color/gradients/background on unit swaps
local DIRTY_FAST = bor(DIRTY_HEALTH, DIRTY_POWER)

local MASK_UNIT_EVENT_FALLBACK = bor(DIRTY_HEALTH, DIRTY_POWER, DIRTY_IDENTITY, DIRTY_STATUS, DIRTY_PORTRAIT, DIRTY_INDICATOR, DIRTY_TOTINLINE)
local MASK_UNIT_SWAP = bor(MASK_UNIT_EVENT_FALLBACK, DIRTY_VISUAL)

-- ------------------------------------------------------------
-- Frame registry
-- ------------------------------------------------------------

local FramesByUnit = {}

-- Forward decl (used by helpers above the definition). Without this,
-- Lua resolves UFCore_EnsureDBOnce as a *global* inside GetConfForUnit.
local UFCore_EnsureDBOnce

local function InitUnitFlags(f)
    if not f or f._msufUnitFlagsInited then return end
    local u = f.unit
    f._msufIsPlayer = (u == "player")
    f._msufIsTarget = (u == "target")
    f._msufIsFocus  = (u == "focus")
    f._msufIsPet    = (u == "pet")
    f._msufIsToT    = (u == "targettarget")
    local bi = u and u:match("^boss(%d+)$")
    f._msufBossIndex = bi and tonumber(bi) or nil
    f._msufUnitFlagsInited = true
end

local function GetConfForUnit(unit)
    local db = UFCore_EnsureDBOnce()
    if not db or not unit then return nil end
    return db[unit]
end

local function GetFrameConf(f)
    if not f then return nil end
    local conf = f.cachedConfig
    if (not conf) and f.msufConfigKey then
        conf = GetConfForUnit(f.msufConfigKey)
        f.cachedConfig = conf
    end
    return conf
end

-- ------------------------------------------------------------
-- DB bootstrap (keep EnsureDB/Migration out of hot paths)
-- ------------------------------------------------------------

UFCore_EnsureDBOnce = function()
    local db = _G.MSUF_DB
    if db then
        Core._dbEnsured = true
        return db
    end

    -- If DB vanished after having been ensured (shouldn't), allow Ensure again.
    if Core._dbEnsured then
        Core._dbEnsured = nil
    end

    if not Core._dbEnsured then
        local fn = _G.EnsureDB
        if type(fn) == "function" then
            fn()
        end
        Core._dbEnsured = true
    end
    return _G.MSUF_DB
end

-- Cache the Target->ToT inline config node (table reference; stays live as settings change).
Core._totInlineConfDB = Core._totInlineConfDB or nil
Core._totInlineConfRef = Core._totInlineConfRef or nil
Core._totInlineConfMigrated = Core._totInlineConfMigrated or nil



-- Explicit cache invalidation hook (does not change behavior unless called).
-- Useful when profiles/settings swap out MSUF_DB tables and cachedConfig would otherwise stay stale.
function Core.InvalidateAllFrameConfigs()
    for _, f in pairs(FramesByUnit) do
        if f then
            f.cachedConfig = nil
        end
    end
end


-- ------------------------------------------------------------
-- Element enablement (oUF-like: only register events for enabled elements)
-- ------------------------------------------------------------

local EL_HEALTH    = 0x00000001
local EL_POWER     = 0x00000002
local EL_IDENTITY  = 0x00000004
local EL_PORTRAIT  = 0x00000008
local EL_STATUS    = 0x00000010
local EL_TOTINLINE = 0x00000020
local EL_INDICATOR = 0x00000040

-- ------------------------------------------------------------
-- Elements (oUF-style contracts, minimal)
--  - Enable/Disable: element lifecycle (event needs handled elsewhere)
--  - Update: does the smallest possible work for that element
-- Notes:
--  - Health/Power use existing fast helpers if present.
--  - Portrait uses MSUF_UpdatePortraitIfNeeded (layout is stamp-gated).
--  - Identity/Status currently fall back to the legacy full update for correctness.
-- ------------------------------------------------------------

local Elements = {}
local UFCore_GetTargetToTInlineConf -- forward decl (used by ToTInline before its definition)
Core.Elements = Elements

local function _Has(fnName)
    local fn = _G[fnName]
    if type(fn) == "function" then return fn end
    return nil
end

local function _SetShown(obj, show)
    if not obj then return end
    if type(_G.MSUF_SetShown) == "function" then
        _G.MSUF_SetShown(obj, show and true or false)
        return
    end
    if show then
        if obj.Show then obj:Show() end
    else
        if obj.Hide then obj:Hide() end
    end
end

local function _SetText(fs, txt)
    if not fs then return end
    if type(_G.MSUF_SetTextIfChanged) == "function" then
        _G.MSUF_SetTextIfChanged(fs, txt or "")
    else
        if fs.SetText then fs:SetText(txt or "") end
    end
end

local function _UpdateIdentityColors(frame)
    if not frame or not frame.nameText then return end
    local db = _G.MSUF_DB
    local g = (type(db) == "table" and type(db.general) == "table") and db.general or {}
    local r, gCol, b

    if g.nameClassColor and frame.unit and UnitIsPlayer and UnitIsPlayer(frame.unit) then
        local _, classToken = UnitClass(frame.unit)
        if classToken and type(_G.MSUF_GetClassBarColor) == "function" then
            r, gCol, b = _G.MSUF_GetClassBarColor(classToken)
        end
    end

    if (not (r and gCol and b)) and g.npcNameRed and frame.unit and UnitIsPlayer and (not UnitIsPlayer(frame.unit)) then
        if UnitIsDeadOrGhost and UnitIsDeadOrGhost(frame.unit) and type(_G.MSUF_GetNPCReactionColor) == "function" then
            r, gCol, b = _G.MSUF_GetNPCReactionColor("dead")
        else
            local reaction = UnitReaction and UnitReaction("player", frame.unit)
            if reaction and type(_G.MSUF_GetNPCReactionColor) == "function" then
                if reaction >= 5 then
                    r, gCol, b = _G.MSUF_GetNPCReactionColor("friendly")
                elseif reaction == 4 then
                    r, gCol, b = _G.MSUF_GetNPCReactionColor("neutral")
                else
                    r, gCol, b = _G.MSUF_GetNPCReactionColor("enemy")
                end
            end
        end
    end

    if not (r and gCol and b) then
        if type(_G.MSUF_GetConfiguredFontColor) == "function" then
            r, gCol, b = _G.MSUF_GetConfiguredFontColor()
        end
    end

    if frame.nameText.SetTextColor then
        frame.nameText:SetTextColor(r or 1, gCol or 1, b or 1, 1)
    end
    if frame.levelText and frame.levelText.SetTextColor then
        frame.levelText:SetTextColor(r or 1, gCol or 1, b or 1, 1)
    end
end

local function UFCore_UpdateIdentityFast(frame, conf)
    if not frame then return false end
    -- Boss test mode relies on the legacy renderer for fake labels.
    if frame.isBoss and _G.MSUF_BossTestMode then
        return false
    end

    local unit = frame.unit
    local exists = (unit and UnitExists and UnitExists(unit)) and true or false

    local showName = (frame.showName ~= false)
    if conf and conf.showName ~= nil then
        showName = (conf.showName ~= false)
    end

    if frame.nameText then
        if showName and exists then
            local nm = UnitName and UnitName(unit)
            _SetText(frame.nameText, nm or "")
        else
            _SetText(frame.nameText, "")
        end
        _SetShown(frame.nameText, showName and exists)
    end

    if frame.levelText then
        local showLevel = false
        if conf and conf.showLevelIndicator == true then
            showLevel = (showName and exists)
        end
        if showLevel then
            local lvl = UnitLevel and UnitLevel(unit) or 0
            if not lvl or lvl <= 0 then
                _SetText(frame.levelText, "??")
            else
                _SetText(frame.levelText, tostring(lvl))
            end
        else
            _SetText(frame.levelText, "")
        end
        _SetShown(frame.levelText, showLevel)
    end

    if showName and exists then
        _UpdateIdentityColors(frame)
    end

    return true
end

local function UFCore_UpdateStatusFast(frame, conf)
    if not frame then return false end
    local key = frame.msufConfigKey
    if type(_G.MSUF_ApplyUnitAlpha) == "function" then
        _G.MSUF_ApplyUnitAlpha(frame, key)
    end
    if type(_G.MSUF_UpdateStatusIndicatorForFrame) == "function" then
        _G.MSUF_UpdateStatusIndicatorForFrame(frame)
    end
    return true
end

Elements.Health = {
    key = "Health",
    bit = EL_HEALTH,
    dirty = DIRTY_HEALTH,
    events = {
        "UNIT_HEALTH", "UNIT_MAXHEALTH",
        "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_HEAL_ABSORB_AMOUNT_CHANGED",
        "UNIT_HEAL_PREDICTION", "UNIT_MAXHEALTHMODIFIER",
    },
    Enable = function(f, conf) end,
    Disable = function(f) end,
    Update = function(f)
        local fnH = _Has("MSUF_UFCore_UpdateHealthFast")
        if fnH then
            local hp = select(1, fnH(f))
            local fnTxt = _Has("MSUF_UFCore_UpdateHpTextFast")
            if fnTxt then fnTxt(f, hp) end
            return true
        end
        return false
    end,
}

Elements.Power = {
    key = "Power",
    bit = EL_POWER,
    dirty = DIRTY_POWER,
    events = {
        "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER",
        "UNIT_POWER_BAR_SHOW", "UNIT_POWER_BAR_HIDE",
    },
    Enable = function(f, conf) end,
    Disable = function(f)
        -- When the Power element is disabled (power text AND power bar off),
        -- clear/hide both immediately so no stale 'last resource' UI remains.
        if not f then return end

        local pt = f.powerText
        if pt then
            local fnSet = _Has("MSUF_SetTextIfChanged")
            if fnSet then
                fnSet(pt, "")
            else
                pt:SetText("")
            end
            pt:Hide()
        end

        local bar = f.targetPowerBar or f.powerBar
        if bar then
            bar:SetScript("OnUpdate", nil)
            bar:SetMinMaxValues(0, 1)
            if type(_G.MSUF_SetBarValue) == "function" then
                _G.MSUF_SetBarValue(bar, 0, false)
            else
                bar:SetValue(0)
            end
            bar.MSUF_lastValue = 0
            bar.MSUF_lastPowerToken = nil
            bar.MSUF_lastPowerColor = nil
            bar:Hide()
        end
    end,
    Update = function(f)
        local fnBar = _Has("MSUF_UFCore_UpdatePowerBarFast")
        local fnTxt = _Has("MSUF_UFCore_UpdatePowerTextFast")
        local ok = false
        if fnBar then fnBar(f); ok = true end
        if fnTxt then fnTxt(f); ok = true end
        return ok
    end,
}

Elements.Identity = {
    key = "Identity",
    bit = EL_IDENTITY,
    dirty = DIRTY_IDENTITY,
    events = {
        "UNIT_NAME_UPDATE", "UNIT_LEVEL",
        "UNIT_CLASSIFICATION_CHANGED", "UNIT_FACTION",
    },
    Enable = function(f, conf) end,
    Disable = function(f) end,
    Update = function(f, conf)
        return UFCore_UpdateIdentityFast(f, conf)
    end,
}

Elements.Portrait = {
    key = "Portrait",
    bit = EL_PORTRAIT,
    dirty = DIRTY_PORTRAIT,
    events = {
        "UNIT_PORTRAIT_UPDATE",
        "UNIT_MODEL_CHANGED",
    },
    Enable = function(f, conf) end,
    Disable = function(f) end,
    Update = function(f, conf)
        local fn = _G.MSUF_UpdatePortraitIfNeeded
        if type(fn) ~= "function" then return false end
        if not f or not f.portrait then return true end
        if not conf then return false end
        local unit = f.unit
        local existsForPortrait = UnitExists(unit)
        fn(f, unit, conf, existsForPortrait)
        return true
    end,
}

Elements.Status = {
    key = "Status",
    bit = EL_STATUS,
    dirty = DIRTY_STATUS,
    events = {
        "UNIT_CONNECTION",
        "UNIT_FLAGS",
        -- Only relevant for the player frame; filtered in RefreshUnitEvents.
        "PLAYER_FLAGS_CHANGED",
    },
    Enable = function(f, conf) end,
    Disable = function(f) end,
    Update = function(f, conf)
        return UFCore_UpdateStatusFast(f, conf)
    end,
}


Elements.Indicators = {
    key = "Indicators",
    bit = EL_INDICATOR,
    dirty = DIRTY_INDICATOR,
    -- Driven by global events (GROUP_ROSTER_UPDATE / PARTY_LEADER_CHANGED / RAID_TARGET_UPDATE).
    -- No per-frame unit events here.
    events = nil,
    Enable = function(f, conf) end,
    Disable = function(f)
        if not f then return end
        if f.leaderIcon and f.leaderIcon.Hide then f.leaderIcon:Hide() end
        if f.assistantIcon and f.assistantIcon.Hide then f.assistantIcon:Hide() end
        if f.raidMarkerIcon and f.raidMarkerIcon.Hide then f.raidMarkerIcon:Hide() end
    end,
    Update = function(f, conf)
        if not f then return false end
        local db = UFCore_EnsureDBOnce()
        local g = (type(db) == "table" and type(db.general) == "table") and db.general or nil
        local unit = f.unit

        if not g or not unit then
            if f.leaderIcon and f.leaderIcon.Hide then f.leaderIcon:Hide() end
            if f.raidMarkerIcon and f.raidMarkerIcon.Hide then f.raidMarkerIcon:Hide() end
            if f.assistantIcon and f.assistantIcon.Hide then f.assistantIcon:Hide() end
            return true
        end

        -- Leader / Assist icon
        if f.leaderIcon then
            local showAllowed = true
            if conf and conf.showLeaderIcon ~= nil then
                showAllowed = (conf.showLeaderIcon ~= false)
            else
                showAllowed = (g.showLeaderIcon ~= false)
            end

            if not showAllowed then
                if f.leaderIcon.Hide then f.leaderIcon:Hide() end
            else
                local isLeader = (UnitIsGroupLeader and UnitIsGroupLeader(unit)) and true or false
                local isAssist = (not isLeader) and (UnitIsGroupAssistant and UnitIsGroupAssistant(unit)) and true or false

                if isLeader then
                    if f.leaderIcon.SetTexture then
                        f.leaderIcon:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
                    end
                    if f.leaderIcon.Show then f.leaderIcon:Show() end
                elseif isAssist then
                    if f.leaderIcon.SetTexture then
                        f.leaderIcon:SetTexture("Interface\\GroupFrame\\UI-Group-AssistantIcon")
                    end
                    if f.leaderIcon.Show then f.leaderIcon:Show() end
                else
                    if f.leaderIcon.Hide then f.leaderIcon:Hide() end
                end
            end
        end

        -- Raid marker icon
        if f.raidMarkerIcon then
            local show = true
            if conf and conf.showRaidMarker ~= nil then
                show = (conf.showRaidMarker ~= false)
            else
                show = (g.showRaidMarker ~= false)
            end

            if not show then
                if f.raidMarkerIcon.Hide then f.raidMarkerIcon:Hide() end
            else
                local idx = (GetRaidTargetIndex and GetRaidTargetIndex(unit)) or nil
                -- Midnight/Beta can return idx as a "secret value"; never compare / do math on it.
                if addon and addon.EditModeLib and addon.EditModeLib.IsInEditMode and addon.EditModeLib:IsInEditMode() then
                    idx = idx or 8 -- stable preview while editing
                end
                if idx and SetRaidTargetIconTexture then
                    SetRaidTargetIconTexture(f.raidMarkerIcon, idx)
                    if f.raidMarkerIcon.Show then f.raidMarkerIcon:Show() end
                else
                    if f.raidMarkerIcon.Hide then f.raidMarkerIcon:Hide() end
                end
            end
        end

        return true
    end,
}


Elements.ToTInline = {
    key = "ToTInline",
    bit = EL_TOTINLINE,
    dirty = DIRTY_TOTINLINE,
    -- Events are driven by the UFCore Global driver (UNIT_TARGET + PLAYER_TARGET_CHANGED),
    -- so we don't register anything on the target frame here.
    events = nil,
    Enable = function(f, conf) end,
    Disable = function(f)
        if not f then return end
        if f._msufToTInlineSep and f._msufToTInlineSep.Hide then f._msufToTInlineSep:Hide() end
        if f._msufToTInlineText and f._msufToTInlineText.Hide then f._msufToTInlineText:Hide() end
    end,
        Update = function(f, conf)
        if not f or not f._msufIsTarget then return false end
        UFCore_UpdateToTInline(f)
        return true
    end,
}

local ELEMENT_LIST = {
    Elements.Health,
    Elements.Power,
    Elements.Identity,
    Elements.Indicators,
    Elements.ToTInline,
    Elements.Portrait,
    Elements.Status,
}

local UFCORE_EVENT_ALIAS = {
    UNIT_HEALTH_FREQUENT = "UNIT_HEALTH",
    UNIT_POWER_FREQUENT  = "UNIT_POWER_UPDATE",
}


-- Ensure the targettarget DB node exists even when the ToT unitframe is disabled.
-- This is required so "ToT inline in target name" works immediately without ever enabling the ToT frame.
function UFCore_GetTargetToTInlineConf()
    local db = UFCore_EnsureDBOnce()
    if type(db) ~= "table" then
        return nil
    end

    -- DB can be swapped on profile import; refresh cache if so.
    if Core._totInlineConfDB ~= db then
        Core._totInlineConfDB = db
        Core._totInlineConfRef = nil
        Core._totInlineConfMigrated = nil
    end

    local tt = Core._totInlineConfRef
    if type(tt) ~= "table" then
        tt = db.targettarget
        if type(tt) ~= "table" then
            tt = {}
            db.targettarget = tt
        end
        Core._totInlineConfRef = tt
    end

    -- One-time migration/defaults (no per-target-switch work).
    if not Core._totInlineConfMigrated then
        -- Migration / alias: older builds may have stored the flag under MSUF_DB.target.
        if tt.showToTInTargetName == nil then
            local t = db.target
            if type(t) == "table" then
                local v = t.showToTInTargetName
                if v == 1 or v == "1" then v = true end
                if v == 0 or v == "0" then v = false end
                if v ~= nil then
                    tt.showToTInTargetName = (v == true)
                end
            end
        end

        -- Migration / alias: older builds may have stored the separator under MSUF_DB.target.
        if tt.totInlineSeparator == nil then
            local t = db.target
            if type(t) == "table" and type(t.totInlineSeparator) == "string" then
                tt.totInlineSeparator = t.totInlineSeparator
            end
        end
        if type(tt.totInlineSeparator) ~= "string" or tt.totInlineSeparator == "" then
            tt.totInlineSeparator = "|"
        end

        if tt.showToTInTargetName == nil then
            tt.showToTInTargetName = false
        end

        Core._totInlineConfMigrated = true
    end

    return tt
end

-- ToT inline is CORE-owned and must never depend on the ToT unitframe being enabled/built.
local function UFCore_IsToTInlineEnabled()
    local conf = UFCore_GetTargetToTInlineConf()
    return (conf and conf.showToTInTargetName == true) and true or false
end

function UFCore_UpdateToTInline(f)
    if not f or not f._msufIsTarget then return end

    if not UFCore_IsToTInlineEnabled() then
        if f._msufToTInlineSep and f._msufToTInlineSep.Hide then f._msufToTInlineSep:Hide() end
        if f._msufToTInlineText and f._msufToTInlineText.Hide then f._msufToTInlineText:Hide() end
        return
    end

    -- Widgets are created/anchored in the layout path (Step 3 policy).
    if (not f._msufToTInlineSep) or (not f._msufToTInlineText) then
        Core.RequestLayout(f, "ToTInlineWidgetsMissing", true)
        return
    end

    local show = false

    local inEdit = false
    if addon and addon.EditModeLib and addon.EditModeLib.IsInEditMode then
        inEdit = addon.EditModeLib:IsInEditMode() and true or false
    end

    if inEdit then
        show = true
        _SetText(f._msufToTInlineText, "ToT")
    else
        if UnitExists and UnitExists("targettarget") then
            show = true
            local nm
            if UnitName then
                nm = UnitName("targettarget")
            end

            -- Secret-safe: do NOT compare/test nm (can be a secret value).
            -- Just set text (nil-safe via `or ""`), no pcall in hot paths.
            _SetText(f._msufToTInlineText, nm or "")
        end
    end

    -- Separator token (stored in DB; render with spaces around it, legacy-style).
    do
        local conf = UFCore_GetTargetToTInlineConf()
        local token = (conf and conf.totInlineSeparator) or "|"
        if type(token) ~= "string" or token == "" then token = "|" end
        _SetText(f._msufToTInlineSep, " " .. token .. " ")
    end

    if show then
        _SetShown(f._msufToTInlineSep, true)
        _SetShown(f._msufToTInlineText, true)
    else
        if f._msufToTInlineSep and f._msufToTInlineSep.Hide then f._msufToTInlineSep:Hide() end
        if f._msufToTInlineText and f._msufToTInlineText.Hide then f._msufToTInlineText:Hide() end
    end
end
-- Forward declaration: ComputeElementMask may need to ensure ToT-inline widgets
-- before the local function is defined later in this file (Lua scoping).
local UFCore_EnsureToTInlineWidgets

local function ComputeElementMask(f)
    if not f or not f.unit then
        return 0, nil
    end

    -- Prefer cachedConfig, but fall back to msufConfigKey if present.
    local conf = GetFrameConf(f)

    -- Ensure per-unit flags are available for cheap per-unit gating below.
    -- (No behavior change; flags are purely derived from f.unit.)
    InitUnitFlags(f)


-- Ensure widgets exist even on login/reload order edge-cases (e.g. Name Shortening already enabled).
if conf and conf.showToTInTargetName and (not f._msufToTInlineText or not f._msufToTInlineSep) then
    UFCore_EnsureToTInlineWidgets(f, conf)
end

    -- Disabled frames don't need any unit events.
    if conf and conf.enabled == false then
        return 0, conf
    end

    local mask = 0

    -- HEALTH: enabled when the HP bar and/or HP text is in use (or absorb overlays exist).
    -- We avoid IsShown() here because visibility drivers can temporarily hide the frame.
    local wantHealth = true
    if conf and conf.showHP == false and (f.showHPText == false) and (not f.absorbBar) and (not f.healAbsorbBar) then
        wantHealth = false
    end
    if wantHealth and (f.hpBar or f.absorbBar or f.healAbsorbBar) then
        mask = bor(mask, EL_HEALTH)
    end

    -- POWER:
    -- IMPORTANT: power BAR updates must not depend on the power TEXT toggle.
    -- Some layouts keep the power bar enabled via MSUF_DB.bars.* while using conf.showPower only
    -- as the "power text" toggle. If we disable EL_POWER when the text is off, we accidentally
    -- unregister UNIT_POWER_* events and the bar appears "frozen" on target swaps.
    local hasPowerBarWidget  = (f.targetPowerBar ~= nil) or (f.powerBar ~= nil)
    local hasPowerTextWidget = (f.powerText ~= nil)
    local wantPower = false

    -- If a power bar widget exists, enable POWER updates unless the per-unit power bar toggle
    -- explicitly disables it in bars config.
    if hasPowerBarWidget then
        local barsConf = (_G.MSUF_DB and _G.MSUF_DB.bars) or nil
        local hideForUnit = false

        if f._msufIsPlayer then
            hideForUnit = (barsConf and barsConf.showPlayerPowerBar == false) or false
        elseif f._msufIsFocus then
            hideForUnit = (barsConf and barsConf.showFocusPowerBar == false) or false
        elseif f._msufIsTarget then
            hideForUnit = (barsConf and barsConf.showTargetPowerBar == false) or false
        elseif f.isBoss then
            hideForUnit = (barsConf and barsConf.showBossPowerBar == false) or false
        end

        if not hideForUnit then
            wantPower = true
        end
    end

    -- If we don't have a power bar, fall back to legacy behavior for "text-only" power widgets.
    if (not wantPower) and hasPowerTextWidget then
        wantPower = (f.showPowerText ~= false)
    end

    if wantPower then
        mask = bor(mask, EL_POWER)
    end

    -- IDENTITY: name and/or level indicator.
    local wantIdentity = false
    if conf then
        wantIdentity = (conf.showName ~= false) or (conf.showLevelIndicator == true)
    else
        wantIdentity = (f.showName ~= false)
    end
    if wantIdentity then
        mask = bor(mask, EL_IDENTITY)
    end

    -- INDICATORS: leader/assist + raid marker icons (driven by global events)
    if (f.leaderIcon or f.raidMarkerIcon or f.assistantIcon) then
        mask = bor(mask, EL_INDICATOR)
    end


    -- ToT INLINE (Target name extension): only on target frame when enabled.
    if f._msufIsTarget and f.nameText and UFCore_IsToTInlineEnabled() then
        mask = bor(mask, EL_TOTINLINE)
    end


    -- PORTRAIT: only if portrait mode is enabled.
    local pm = conf and conf.portraitMode or "OFF"
    if pm and pm ~= "OFF" and f.portrait then
        mask = bor(mask, EL_PORTRAIT)
    end

    -- STATUS: keep correctness for dead/offline/flags when the frame shows health or status text.
    -- (We treat it as a separate element so it can be gated later if desired.)
    if (mask ~= 0) and (f.statusIndicatorText or f.statusIndicatorOverlayText or f.statusIndicatorOverlayFrame or f.hpBar) then
        mask = bor(mask, EL_STATUS)
    end

    return mask, conf
end

local function RefreshUnitEvents(f, force)
    if not f or not f.unit or not f.RegisterUnitEvent then
        return
    end

    local mask, conf = ComputeElementMask(f)
    local last = f._msufElemMask or 0
    if not force and mask == last then
        return
    end

-- Element lifecycle hooks (Enable/Disable) on transitions.
-- (Currently mostly a structure point; events are gated below via `desired`.)
for i = 1, #ELEMENT_LIST do
    local el = ELEMENT_LIST[i]
    local wasOn = (band(last, el.bit) ~= 0)
    local nowOn = (band(mask, el.bit) ~= 0)
    if nowOn and (not wasOn) and el.Enable then
        el.Enable(f, conf)
    elseif wasOn and (not nowOn) and el.Disable then
        el.Disable(f)
    end
end

    f._msufElemMask = mask

    -- oUF-like: do not nuke all events; only add/remove what we own.
    local reg = f._msufUFCoreEvents
    if not reg then
        reg = {}
        f._msufUFCoreEvents = reg
    end

    local desired = Core._scratchDesired
    if not desired then
        desired = {}
        Core._scratchDesired = desired
    else
        wipe(desired)
    end

	-- Cache for unit-event names that are not supported on this client/branch.
	-- (Some beta branches ship with different unit events; RegisterUnitEvent throws on unknown ones.)
	local unsupported = Core._unsupportedUFCoreUnitEvents

	local function Want(ev)
		local a = UFCORE_EVENT_ALIAS[ev]
		if a then
			ev = a
		end
		if unsupported and unsupported[ev] then
			return
		end
		desired[ev] = true
	end

if mask ~= 0 then
    for i = 1, #ELEMENT_LIST do
        local el = ELEMENT_LIST[i]
        if band(mask, el.bit) ~= 0 then
            local evs = el.events
            if evs then
                for j = 1, #evs do
                    local ev = evs[j]
                    if ev == "PLAYER_FLAGS_CHANGED" then
                        if f._msufIsPlayer then
                            Want(ev)
                        end
                    else
                        Want(ev)
                    end
                end
            end
        end
    end
end

	-- Unregister events we no longer need.
	-- Important: unitframes can be externally hard-disabled via UnregisterAllEvents or similar,
	-- which can desync our bookkeeping table. UnregisterEvent() throws in that case.
	for ev in pairs(reg) do
		if not desired[ev] then
			pcall(f.UnregisterEvent, f, ev)
			reg[ev] = nil
		end
	end

	-- Register new events we now need.
    if mask ~= 0 then
        for ev in pairs(desired) do
            if not reg[ev] then
                if ev == "PLAYER_FLAGS_CHANGED" then
                    f:RegisterEvent(ev)
                    reg[ev] = true
                else
					-- Some events are client/branch-specific; RegisterUnitEvent throws on unknown ones.
					-- Registration is not a hot path, so guard it to avoid hard failures.
					if unsupported and unsupported[ev] then
						-- Skip unsupported events permanently on this client.
					else
						local ok = pcall(f.RegisterUnitEvent, f, ev, f.unit)
						if ok then
							reg[ev] = true
						else
							unsupported = unsupported or {}
							Core._unsupportedUFCoreUnitEvents = unsupported
							unsupported[ev] = true
						end
					end
                end
            end
        end
    end
end

-- ------------------------------------------------------------
-- Queue / flush (coalesced)
-- ------------------------------------------------------------

local wipe = wipe
if not wipe then
    wipe = function(t)
        if not t then return end
        for k in pairs(t) do
            t[k] = nil
        end
    end
end

local function NewQueue(withSet)
    return { t = {}, head = 1, tail = 0, size = 0, set = withSet and {} or nil }
end

-- urgent/normal need fast membership checks for promotion (no O(n) scans)
local urgentQueue = NewQueue(true)
local normalQueue = NewQueue(true)
local warmupQueue = NewQueue()
local visualQueue = NewQueue()

local function QueueContains(q, f)
    if not q or not f then return false end
    local set = q.set
    if set then
        return set[f] and true or false
    end
    local t = q.t
    for i = q.head, q.tail do
        if t[i] == f then
            return true
        end
    end
    return false
end


local function QueueRemove(q, f)
    if not q or not f then return false end
    local set = q.set
    if set then
        if set[f] then
            set[f] = nil
            q.size = q.size - 1
            if q.size == 0 then
                wipe(q.t)
                q.head, q.tail = 1, 0
                wipe(set)
            end
            return true
        end
        return false
    end

    local t = q.t
    for i = q.head, q.tail do
        if t[i] == f then
            t[i] = false -- tombstone (PopFirst skips)
            q.size = q.size - 1
            if q.size == 0 then
                wipe(t)
                q.head, q.tail = 1, 0
            end
            return true
        end
    end
    return false
end


local function Enqueue(q, f)
    if not q or not f then return false end
    local set = q.set
    if set then
        if set[f] then
            return false
        end
        set[f] = true
    end
    local t = q.t
    q.tail = q.tail + 1
    t[q.tail] = f
    q.size = q.size + 1
    return true
end


local function MaybeCompactQueue(q)
    -- Compact occasionally to keep indices bounded (order-preserving).
    if q.size == 0 then
        wipe(q.t)
        q.head, q.tail = 1, 0
        if q.set then wipe(q.set) end
        return
    end
    if q.head <= 256 then return end
    if q.head <= (q.tail * 0.5) then return end

    local old = q.t
    local new = {}
    local n = 0

    local set = q.set
    if set then
        for i = q.head, q.tail do
            local v = old[i]
            if v and v ~= false and set[v] then
                n = n + 1
                new[n] = v
            end
        end
        q.size = n -- keep size honest (stale entries are dropped)
    else
        for i = q.head, q.tail do
            local v = old[i]
            if v and v ~= false then
                n = n + 1
                new[n] = v
            end
        end
        -- NOTE: q.size should already equal n.
    end

    q.t = new
    q.head, q.tail = 1, n
end


local FlushEnabled = false

local function UFCore_FlushTask()
    local budgetMs = UFCore_GetFlushBudgetSettings()
    Core.Flush(budgetMs)
end

local function EnsureFallbackDriver()
    local f = Core._fallbackFrame
    if f then return f end
    f = CreateFrame("Frame")
    f:Hide()
    f:SetScript("OnUpdate", UFCore_FlushTask)
    Core._fallbackFrame = f
    return f
end

local function RequestFlushNextFrame()
    -- Always schedule a UFCore flush for the next frame when something became dirty.
    local UM = _G.MSUF_UpdateManager
    if UM and UM.Kick then
        UM:Kick("UFCoreFlush")
        return
    end
    -- Fallback: keep a simple OnUpdate driver alive while work remains.
    EnsureFallbackDriver():Show()
end


local function EnsureFlushEnabled()
    if FlushEnabled then return end
    FlushEnabled = true
    local UM = _G.MSUF_UpdateManager
    if UM and UM.Register and UM.SetEnabled then
        if not Core._umTaskRegistered then
            Core._umTaskRegistered = true
            Core._umFlushFn = Core._umFlushFn or UFCore_FlushTask
            UM:Register("UFCoreFlush", Core._umFlushFn, 0.03, 20)
            UM:SetEnabled("UFCoreFlush", false)
        end
        UM:SetEnabled("UFCoreFlush", true)
        RequestFlushNextFrame()
        return
    end
    EnsureFallbackDriver():Show()
end

local function DisableFlushIfIdle()
    if urgentQueue.size > 0 or normalQueue.size > 0 or warmupQueue.size > 0 or visualQueue.size > 0 then
        return
    end
    FlushEnabled = false
    local UM = _G.MSUF_UpdateManager
    if UM and UM.SetEnabled then
        UM:SetEnabled("UFCoreFlush", false)
    end
    if Core._fallbackFrame then
        Core._fallbackFrame:Hide()
    end
end

local function _AddDirtyMask(f, mask)
    if not f then return end
    local cur = f._msufDirtyMask or 0
    f._msufDirtyMask = bor(cur, mask)
end

local function PromoteQueuedToUrgent(f)
    if not f then return end
    -- If it's already in urgentQueue, do nothing.
    if QueueContains(urgentQueue, f) then
        return
    end
    -- Remove from normalQueue if present (tombstone, no shifting).
    QueueRemove(normalQueue, f)
    Enqueue(urgentQueue, f)
end

local function QueueFrame(f, urgent)
    if not f then return end

    if f._msufQueuedUFCore then
        -- Escalate to urgent if a later event is urgent (ToT lane etc.).
        if urgent then
            f._msufQueuedUFCoreUrgent = true
            PromoteQueuedToUrgent(f)
            EnsureFlushEnabled()
            RequestFlushNextFrame()
        end
        return
    end

    f._msufQueuedUFCore = true
    f._msufQueuedUFCoreUrgent = urgent or nil

    if urgent then
        Enqueue(urgentQueue, f)
    else
        Enqueue(normalQueue, f)
    end

    EnsureFlushEnabled()
end

-- ------------------------------------------------------------
-- Public API (Step 1: one flush path)
--   External code should only call Core.MarkDirty (or the global wrapper)
--   and NEVER call UpdateSimpleUnitFrame directly.
-- ------------------------------------------------------------

function Core.MarkDirty(f, mask, urgent, reason)
    if not f then return end
    -- Default mask is full, but callers should pass explicit masks whenever possible.
    mask = mask or DIRTY_FULL

    _AddDirtyMask(f, mask)

    -- Optional debug: capture the last reason/mask that dirtied this frame.
    local db = _G.MSUF_DB
    if db and db.general and db.general.ufcoreDebugDirty then
        f._msufLastDirtyReason = reason or "?"
        f._msufLastDirtyMask = mask
        f._msufLastDirtyAt = debugprofilestop and debugprofilestop() or 0
    end

    -- Urgent lane policy: default urgent for target/ToT (and focus) if caller didn't specify.
    if urgent == nil then
        urgent = (f._msufIsTarget or f._msufIsToT or f._msufIsFocus) and true or false
    end

    QueueFrame(f, urgent)
end

-- ------------------------------------------------------------
-- Step 3: "No layout in runtime"
--  - All ClearAllPoints/SetPoint/SetWidth/SetFont/etc should happen ONLY via this path:
--      * Options Apply
--      * Frame size changes (OnSizeChanged)
--      * Portrait mode changes
--      * hpTextSpacer changes
--  - Runtime unit events (health/power/name/flags) must remain layout-free.
-- ------------------------------------------------------------


function UFCore_EnsureToTInlineWidgets(f, conf)
    if not conf or not conf.showToTInTargetName then return end

    local name = f.nameText
    if not name then return end

    -- ToT-Inline must NOT be parented to the name clip/mask container. Keep it in a dedicated overlay
    -- container on the unitframe so Name Shortening can never hide/clip it.
    local overlay = f._msufToTInlineOverlay
    if not overlay then
        overlay = CreateFrame("Frame", nil, f)
        f._msufToTInlineOverlay = overlay
        overlay:SetAllPoints(f)
        overlay:SetFrameLevel((f:GetFrameLevel() or 0) + 80)
    else
        if overlay:GetParent() ~= f then
            overlay:SetParent(f)
            overlay:SetAllPoints(f)
        end
        local desiredLevel = (f:GetFrameLevel() or 0) + 80
        if overlay:GetFrameLevel() < desiredLevel then
            overlay:SetFrameLevel(desiredLevel)
        end
    end

    local sep = f._msufToTInlineSep
    if not sep then
        sep = overlay:CreateFontString(nil, "OVERLAY")
        f._msufToTInlineSep = sep
        sep:SetFontObject(GameFontNormalSmall)
        sep:SetJustifyH("LEFT")
        sep:SetJustifyV("MIDDLE")
    else
        if sep:GetParent() ~= overlay then
            sep:SetParent(overlay)
        end
    end

    local tt = f._msufToTInlineText
    if not tt then
        tt = overlay:CreateFontString(nil, "OVERLAY")
        f._msufToTInlineText = tt
        tt:SetFontObject(GameFontNormalSmall)
        tt:SetJustifyH("LEFT")
        tt:SetJustifyV("MIDDLE")
    else
        if tt:GetParent() ~= overlay then
            tt:SetParent(overlay)
        end
    end

    -- Ensure ToT-Inline renders above the Name Shortening overlay (sublevel must be within -128..127).
    sep:SetDrawLayer("OVERLAY", 7)
    tt:SetDrawLayer("OVERLAY", 7)

    sep:ClearAllPoints()
    sep:SetPoint("LEFT", name, "RIGHT", 0, 0)

    tt:ClearAllPoints()
    tt:SetPoint("LEFT", sep, "RIGHT", 0, 0)

    sep:Hide()
    tt:Hide()
end

local function UFCore_ApplyLayout(frame, conf, why)
    if not frame then return end
    if type(_G.EnsureDB) == "function" then _G.EnsureDB() end
    -- ToT inline widgets are part of the target text layout (must exist even when the ToT unitframe is disabled).
    UFCore_EnsureToTInlineWidgets(frame, conf)


    -- Clamp name width (secret-safe; width budget is derived from frame/config, not name length).
    if type(_G.MSUF_ClampNameWidth) == "function" then
        _G.MSUF_ClampNameWidth(frame, conf)
    end

    -- Indicator layouts (stamp-gated in the underlying helpers).
    if type(_G.MSUF_ApplyLeaderIconLayout) == "function" then
        _G.MSUF_ApplyLeaderIconLayout(frame)
    end
    if type(_G.MSUF_ApplyRaidMarkerLayout) == "function" then
        _G.MSUF_ApplyRaidMarkerLayout(frame)
    end

    -- Future: centralize any other SetPoint/SetFont/SetSize logic here.
end

Core.ApplyLayout = UFCore_ApplyLayout

function Core.RequestLayout(f, reason, urgent)
    if not f then return end
    -- capture why (useful for debugging)
    f._msufLayoutWhy = reason or "LAYOUT"
    -- Combat safety: defer layout application until combat ends.
    if InCombatLockdown and InCombatLockdown() then
        local set = Core._layoutDeferredSet
        if not set then
            set = {}
            Core._layoutDeferredSet = set
        end
        set[f] = true
        f._msufLayoutDeferredUrgent = (urgent == true) and true or nil
        f._msufDirtyMask = bor(f._msufDirtyMask or 0, DIRTY_LAYOUT)
        return
    end
    Core.MarkDirty(f, DIRTY_LAYOUT, urgent, reason or "LAYOUT")
end

function _G.MSUF_UFCore_RequestLayout(f, reason, urgent)
    Core.RequestLayout(f, reason, urgent)
end

function _G.MSUF_UFCore_RequestLayoutForUnit(unit, reason, urgent)
    local f = unit and FramesByUnit[unit]
    if not f then return end
    Core.RequestLayout(f, reason or ("LAYOUT:" .. unit), urgent)
end


function Core.RequestFlush()
    EnsureFlushEnabled()
end

function Core.FlushBudgeted(budgetMs)
    Core.Flush(budgetMs)
end

function _G.MSUF_UFCore_MarkDirty(f, mask, urgent, reason)
    Core.MarkDirty(f, mask, urgent, reason)
end

-- Legacy entrypoints used across the addon (keep names stable)
function _G.MSUF_QueueUnitframeUpdate(f, force)
    if not f then return end
    local mask = force and DIRTY_FULL or (DIRTY_HEALTH + DIRTY_POWER + DIRTY_IDENTITY + DIRTY_PORTRAIT + DIRTY_STATUS + DIRTY_INDICATOR + DIRTY_TOTINLINE)
    Core.MarkDirty(f, mask, true, force and "FORCE" or "LEGACY_QUEUE")
end

function _G.MSUF_ScheduleWarmupFrame(f)
    if not f or f._msufWarmupQueuedUFCore then return end
    f._msufWarmupQueuedUFCore = true
    Enqueue(warmupQueue, f)
    EnsureFlushEnabled()
end

function _G.MSUF_QueueUnitframeVisual(f)
    if not f or f._msufVisualQueuedUFCore then return end
    f._msufVisualQueuedUFCore = true
    Enqueue(visualQueue, f)
    EnsureFlushEnabled()
end

-- ------------------------------------------------------------
-- Flush
-- ------------------------------------------------------------

local function PopFirst(q)
    if not q or q.size == 0 then return nil end
    local t = q.t
    local h = q.head
    local set = q.set

    while h <= q.tail do
        local v = t[h]
        t[h] = nil
        h = h + 1
        if v and v ~= false then
            if set then
                if set[v] then
                    set[v] = nil
                    q.head = h
                    q.size = q.size - 1
                    MaybeCompactQueue(q)
                    return v
                end
            else
                q.head = h
                q.size = q.size - 1
                MaybeCompactQueue(q)
                return v
            end
        end
    end

    -- Safety reset (shouldn't happen unless size desync).
    wipe(t)
    if set then wipe(set) end
    q.head, q.tail, q.size = 1, 0, 0
    return nil
end


local function AfterLegacyFullUpdate(f)
    if not f then return end
    if f._msufIsTarget and UFCore_IsToTInlineEnabled() then
        UFCore_UpdateToTInline(f)
    end
    RefreshUnitEvents(f, false)
end

local function RunUpdate(f)
    if not f then return end
    f._msufQueuedUFCore = nil
    local mask = f._msufDirtyMask or 0
    f._msufDirtyMask = 0

    -- Bridge: the main unitframe renderer only touches the portrait texture when
    -- frame._msufPortraitDirty is set. Our element core uses UNIT_PORTRAIT_UPDATE /
    -- UNIT_MODEL_CHANGED to mark DIRTY_PORTRAIT, so translate that into the legacy
    -- per-frame flag here (secret-safe: no GUID/name comparisons).
    if mask ~= 0 and band(mask, DIRTY_PORTRAIT) ~= 0 then
        f._msufPortraitDirty = true
        f._msufPortraitNextAt = 0
    end

    -- Step 3: layout changes are applied only when explicitly requested (DIRTY_LAYOUT),
    -- never as a side-effect of runtime unit events.
    if mask ~= 0 and band(mask, DIRTY_LAYOUT) ~= 0 then
        -- Combat safety: do not apply layout while in combat. Keep the bit pending
        -- and re-apply immediately on PLAYER_REGEN_ENABLED.
        if InCombatLockdown and InCombatLockdown() then
            Core._layoutDeferredSet[f] = true
            f._msufDirtyMask = bor(f._msufDirtyMask or 0, DIRTY_LAYOUT)
            mask = band(mask, bnot(DIRTY_LAYOUT))
            if mask == 0 then
                return
            end
        else
            local conf = GetFrameConf(f)
            Core.ApplyLayout(f, conf, f._msufLayoutWhy or "DIRTY_LAYOUT")
            f._msufLayoutWhy = nil
            mask = band(mask, bnot(DIRTY_LAYOUT))
            if mask == 0 then
                return
            end
        end
    end

    local upd = _G.UpdateSimpleUnitFrame
    if not upd then return end

    -- Step 2: element-style updates.
    -- We keep correctness by falling back to the legacy full renderer for
    -- non-hotpath bits (identity/status/indicators). Hotpath (health/power/portrait)
    -- updates are minimal and layout-free.
    local HOT_MASK = bor(
        DIRTY_HEALTH, DIRTY_POWER, DIRTY_PORTRAIT,
        DIRTY_IDENTITY, DIRTY_STATUS, DIRTY_TOTINLINE, DIRTY_INDICATOR
    )

    if mask ~= 0 and band(mask, bnot(HOT_MASK)) == 0 then
        -- HEALTH
        if band(mask, DIRTY_HEALTH) ~= 0 then
            Elements.Health.Update(f)
        end

        -- POWER
        if band(mask, DIRTY_POWER) ~= 0 then
            Elements.Power.Update(f)
        end

        local conf
        -- Fetch conf once if any element in this pass needs it.
        if band(mask, bor(DIRTY_IDENTITY, DIRTY_INDICATOR, DIRTY_STATUS, DIRTY_PORTRAIT)) ~= 0 then
            conf = GetFrameConf(f)
        end

        -- IDENTITY
        if band(mask, DIRTY_IDENTITY) ~= 0 then
            Elements.Identity.Update(f, conf)
        end

        -- INDICATORS (leader/assist + raid marker)
        if band(mask, DIRTY_INDICATOR) ~= 0 then
            Elements.Indicators.Update(f, conf)
        end

        -- TARGET ToT inline
        if band(mask, DIRTY_TOTINLINE) ~= 0 then
            Elements.ToTInline.Update(f, conf)
        end

        -- STATUS
        if band(mask, DIRTY_STATUS) ~= 0 then
            Elements.Status.Update(f, conf)
        end

        -- PORTRAIT (requires conf; otherwise fall back)
        if band(mask, DIRTY_PORTRAIT) ~= 0 then
            if not Elements.Portrait.Update(f, conf) then
                if upd then
                    upd(f)
                end
            end
        end

        return
    end

    -- Any other dirty bit: keep correctness by using the legacy full update.
    if upd then
        upd(f)
    end
    AfterLegacyFullUpdate(f)
end -- RunUpdate


local function RunWarmup(f)
    if not f then return end
    f._msufWarmupQueuedUFCore = nil
    local upd = _G.UpdateSimpleUnitFrame
    if upd then
        upd(f)
        AfterLegacyFullUpdate(f)
    end
end

local function RunVisual(f)
    if not f then return end
    f._msufVisualQueuedUFCore = nil
    local fn = _G.MSUF_RefreshRareBarVisuals
    if fn then
        fn(f)
    else
        -- Fallback: full update if helper not exported yet.
        local upd = _G.UpdateSimpleUnitFrame
        if upd then
            upd(f)
            AfterLegacyFullUpdate(f)
        end
    end
end

function Core.Flush(budgetMs)
    local start = debugprofilestop and debugprofilestop() or nil
    local endAt = (start and budgetMs) and (start + budgetMs) or nil

    local function BudgetOk()
        if not endAt then return true end
        return debugprofilestop() <= endAt
    end

    local budgetHit = false

    -- Lane policy:
    --   1) Urgent lane is drained first, but is still budgeted to cap spikes.
    --   2) Normal/Warmup/Visual are budgeted to avoid spikes.
    -- Policy note: urgent frames (player/target/focus/ToT/boss) are processed first
    -- to keep gameplay snappy, but we cap per-flush work so event floods can
    -- never create a single big frame-time spike.
    local _, URGENT_MAX_PER_FLUSH = UFCore_GetFlushBudgetSettings()
    local urgentCount = 0
    while urgentQueue.size > 0 do
        RunUpdate(PopFirst(urgentQueue))
        urgentCount = urgentCount + 1

        -- Hard cap urgent drain only if more urgent work remains.
        if urgentCount >= URGENT_MAX_PER_FLUSH then
            if urgentQueue.size > 0 then
                budgetHit = true
            end
            break
        end

        -- Time budget applies to urgent lane as well (prevents rare long spikes).
        if not BudgetOk() then
            budgetHit = true
            break
        end
    end

    while (not budgetHit) and normalQueue.size > 0 do
        if not BudgetOk() then
            budgetHit = true
            break
        end
        RunUpdate(PopFirst(normalQueue))
    end

    while (not budgetHit) and warmupQueue.size > 0 do
        if not BudgetOk() then
            budgetHit = true
            break
        end
        RunWarmup(PopFirst(warmupQueue))
    end

    while (not budgetHit) and visualQueue.size > 0 do
        if not BudgetOk() then
            budgetHit = true
            break
        end
        RunVisual(PopFirst(visualQueue))
    end

    -- If we still have work, schedule another flush ASAP (next frame / next UM kick).
    if budgetHit and (urgentQueue.size > 0 or normalQueue.size > 0 or warmupQueue.size > 0 or visualQueue.size > 0) then
        RequestFlushNextFrame()
    end

    DisableFlushIfIdle()
end

-- ------------------------------------------------------------
-- Unitframe event routing
-- ------------------------------------------------------------

local UNIT_EVENT_MAP = {
    -- HEALTH
    UNIT_HEALTH                     = { mask = DIRTY_HEALTH },
    UNIT_MAXHEALTH                  = { mask = DIRTY_HEALTH },
    UNIT_HEAL_ABSORB_AMOUNT_CHANGED = { mask = DIRTY_HEALTH },
    UNIT_ABSORB_AMOUNT_CHANGED      = { mask = DIRTY_HEALTH },

    -- POWER
    UNIT_POWER_UPDATE               = { mask = DIRTY_POWER },
    UNIT_MAXPOWER                   = { mask = DIRTY_POWER },
    UNIT_DISPLAYPOWER               = { mask = DIRTY_POWER },

    -- IDENTITY
    UNIT_NAME_UPDATE                = { mask = DIRTY_IDENTITY, urgent = true },
    UNIT_LEVEL                      = { mask = DIRTY_IDENTITY, urgent = true },
    UNIT_CLASSIFICATION_CHANGED     = { mask = DIRTY_IDENTITY, urgent = true },
    UNIT_FACTION                    = { mask = DIRTY_IDENTITY, urgent = true },

    -- PORTRAIT
    UNIT_PORTRAIT_UPDATE            = { mask = DIRTY_PORTRAIT, urgent = false },
    UNIT_MODEL_CHANGED              = { mask = DIRTY_PORTRAIT, urgent = false },

    -- STATUS
    UNIT_CONNECTION                 = { mask = DIRTY_STATUS, urgent = true },
    UNIT_FLAGS                      = { mask = DIRTY_STATUS, urgent = true },

    -- OTHER (cheap visuals)
    UNIT_THREAT_SITUATION_UPDATE     = { mask = DIRTY_INDICATOR, urgent = false },
}

local function FrameOnEvent(self, event, arg1, ...)
    -- oUF-like: skip hidden frames (free win).
    -- Frames can opt out (e.g. previews) by setting self.MSUF_AllowHiddenEvents = true.
    if not self:IsVisible() and not self.MSUF_AllowHiddenEvents then
        return
    end

    -- Non-UNIT events we care about (registered only when needed).
    if event == "PLAYER_FLAGS_CHANGED" then
        if arg1 == self.unit then
            Core.MarkDirty(self, DIRTY_STATUS, true, event)
        end
        return
    end

    -- Unit events: only react to our unit.
    local info = UNIT_EVENT_MAP[event]
    if info then
        if arg1 == self.unit then
            Core.MarkDirty(self, info.mask, info.urgent, event)
        end
        return
    end

    -- Default: unknown UNIT_* events should NOT force full legacy redraws.
    -- Coalesce into a conservative, non-layout update (lane priority is determined by MarkDirty).
    if event:sub(1, 5) == "UNIT_" then
        if arg1 ~= self.unit then return end
        Core.MarkDirty(self, MASK_UNIT_EVENT_FALLBACK, nil, event)
    end
end

function Core.AttachFrame(f)
    if not f or not f.unit then return end

    InitUnitFlags(f)
    FramesByUnit[f.unit] = f

    -- Ensure we start clean.
    f._msufDirtyMask = 0
    f._msufQueuedUFCore = nil
    f._msufWarmupQueuedUFCore = nil
    f._msufVisualQueuedUFCore = nil

    f:SetScript("OnEvent", FrameOnEvent)

    -- oUF-like: only register what we actually need.
    RefreshUnitEvents(f, true)

    -- Step 3: layout updates only on size/apply changes (never on unit event hotpath).
    if not f._msufUFCoreSizeHooked and f.HookScript then
        f._msufUFCoreSizeHooked = true
        f:HookScript("OnSizeChanged", function(self)
            -- Layout-only flush: clamps + icon anchors, no full redraw.
            Core.RequestLayout(self, "OnSizeChanged")
        end)
    end


    -- If a frame was hidden, it may have missed events due to the visible-gate.
    -- Force a coalesced refresh on show so state is never stale.
    if not f._msufUFCoreShowHooked and f.HookScript then
        f._msufUFCoreShowHooked = true
        f:HookScript("OnShow", function(self)
            Core.MarkDirty(self, DIRTY_FULL, true, "OnShow")
        end)
    end
    -- Apply initial layout stamps once.
    Core.RequestLayout(f, "AttachFrame")

    -- First draw is queued (coalesced).
    _G.MSUF_QueueUnitframeUpdate(f, true)
end

-- Public wrappers (used by main/options when config toggles change)
function Core.RefreshUnitEvents(f, force)
    RefreshUnitEvents(f, force)
end

-- Centralized event-gating refresh hooks (no behavior change unless called).
-- Use from options/apply flows to recompute element masks when widgets/toggles change.
function Core.RefreshAllUnitEvents(force)
    if force == nil then force = true end
    for _, f in pairs(FramesByUnit) do
        if f then
            RefreshUnitEvents(f, force)
        end
    end
end

-- Notify that configuration for a unit (or all units) changed.
-- By default this only refreshes event-gating; it does NOT force a redraw unless alsoUpdate=true.
function Core.NotifyConfigChanged(unitKey, alsoUpdate, urgent, reason)
    reason = reason or "CONFIG_CHANGED"

    if not unitKey then
        Core.InvalidateAllFrameConfigs()
        Core.RefreshAllUnitEvents(true)
        if alsoUpdate then
            for _, f in pairs(FramesByUnit) do
                if f then
                    Core.MarkDirty(f, DIRTY_FULL, (urgent ~= false), reason)
                end
            end
        end
        return
    end

    local f = FramesByUnit[unitKey]
    if not f then return end

    f.cachedConfig = nil
    RefreshUnitEvents(f, true)

    if alsoUpdate then
        Core.MarkDirty(f, DIRTY_FULL, (urgent ~= false), reason)
    end
end


-- ------------------------------------------------------------
-- Global driver (one frame; avoid duplicating global events per unitframe)
-- ------------------------------------------------------------

local Global = CreateFrame("Frame")
Core._globalDriver = Global

Global:RegisterEvent("PLAYER_LOGIN")
Global:RegisterEvent("PLAYER_ENTERING_WORLD")
Global:RegisterEvent("PLAYER_REGEN_ENABLED")
Global:RegisterEvent("PLAYER_TARGET_CHANGED")
Global:RegisterEvent("PLAYER_FOCUS_CHANGED")
Global:RegisterEvent("UNIT_TARGET")
Global:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
Global:RegisterEvent("GROUP_ROSTER_UPDATE")
Global:RegisterEvent("PARTY_LEADER_CHANGED")
Global:RegisterEvent("RAID_TARGET_UPDATE")


local function MarkUnit(unit, mask, urgent, reason)
    local f = FramesByUnit[unit]
    if not f then return end
    Core.MarkDirty(f, mask or DIRTY_FULL, urgent, reason or "GLOBAL")
end

local function QueueUnit(unit, urgent, mask, reason)
    MarkUnit(unit, mask or DIRTY_FULL, urgent, reason or "GLOBAL")
end

Global:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        -- Ensure DB exists before we compute element masks (important for ToT-inline bootstrap).
        UFCore_EnsureDBOnce()

        -- Recompute per-frame element masks & unit event registrations once (after DB/init order settles).
        for _, f in pairs(FramesByUnit) do
            RefreshUnitEvents(f, true)

            -- Bootstrap ToT inline on the target frame even when the ToT unitframe itself is disabled.
            if f._msufIsTarget and UFCore_IsToTInlineEnabled() then
                Core.MarkDirty(f, DIRTY_LAYOUT, true, "BOOT_LAYOUT_TOTINLINE")
                Core.MarkDirty(f, DIRTY_TOTINLINE, true, "BOOT_TOTINLINE")
            end

            Core.MarkDirty(f, DIRTY_FULL, true, event)
        end
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        local set = Core._layoutDeferredSet
        if set then
            for f in pairs(set) do
                set[f] = nil
                local u = f._msufLayoutDeferredUrgent
                f._msufLayoutDeferredUrgent = nil
                -- Apply deferred layout immediately after combat.
                Core.MarkDirty(f, DIRTY_LAYOUT, (u == true) and true or true, "REGEN_LAYOUT")
            end
        end
        return
    end

    if event == "PLAYER_TARGET_CHANGED" then
        QueueUnit("target", true, MASK_UNIT_SWAP, event)
        -- Urgent lane: keep ToT snappy (no perceptible delay).
        QueueUnit("targettarget", true, MASK_UNIT_SWAP, event)
        return
    end

    if event == "UNIT_TARGET" and arg1 == "target" then
        -- Target-of-target changes: refresh ToT inline (independent of the ToT unitframe).
        if UFCore_IsToTInlineEnabled() then
            local tf = FramesByUnit["target"]
            if tf then
                Core.MarkDirty(tf, DIRTY_TOTINLINE, true, event)
            end
        end
        -- If the ToT unitframe exists/attached, keep it responsive too.
        QueueUnit("targettarget", true, MASK_UNIT_SWAP, event)
        return
    end

    if event == "PLAYER_FOCUS_CHANGED" then
        QueueUnit("focus", true, MASK_UNIT_SWAP, event)
        return
    end

    if event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
        for i = 1, 5 do
            QueueUnit("boss" .. i, true, DIRTY_FULL, event)
        end
        return
    end

    if event == "GROUP_ROSTER_UPDATE" or event == "PARTY_LEADER_CHANGED" then
        -- Leader/assist icon may change on player/target/focus
        MarkUnit("player", DIRTY_INDICATOR, false, event)
        MarkUnit("target", DIRTY_INDICATOR, false, event)
        MarkUnit("focus", DIRTY_INDICATOR, false, event)
        return
    end

    if event == "RAID_TARGET_UPDATE" then
        -- Rare; only update raid marker visuals (no full frame updates required).
        MarkUnit("player", DIRTY_INDICATOR, false, event)
        MarkUnit("target", DIRTY_INDICATOR, false, event)
        MarkUnit("focus", DIRTY_INDICATOR, false, event)
        MarkUnit("targettarget", DIRTY_INDICATOR, false, event)
        return
    end
end)

-- Expose a stable attach function name (so main can call it without addon table lookups)
function _G.MSUF_UFCore_AttachFrame(f)
    Core.AttachFrame(f)
end
function _G.MSUF_UFCore_RefreshUnitEvents(f, force)
    RefreshUnitEvents(f, force)
end
function _G.MSUF_UFCore_InvalidateAllFrameConfigs()
    Core.InvalidateAllFrameConfigs()
end

function _G.MSUF_UFCore_RefreshAllUnitEvents(force)
    Core.RefreshAllUnitEvents(force)
end

function _G.MSUF_UFCore_NotifyConfigChanged(unitKey, alsoUpdate, urgent, reason)
    Core.NotifyConfigChanged(unitKey, alsoUpdate, urgent, reason)
end
