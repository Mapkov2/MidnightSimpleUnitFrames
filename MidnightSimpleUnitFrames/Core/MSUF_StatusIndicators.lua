-- NOTE: This file exists in Core/ for newer layouts. A copy is also shipped at addon root for older .toc layouts.
-- Provides:
--   MSUF_UpdateStatusIndicatorForFrame(frame)  (global)
--   MSUF_GetStatusIndicatorDB()               (global)
--   MSUF_GetStatusIconsTestMode()/Set...      (global)
local addonName, ns = ...
ns = ns or {}

-- Hotpath locals (avoid _G lookups)
local _G = _G
local type   = _G.type
local pairs  = _G.pairs
local ipairs = _G.ipairs
local next   = _G.next
local tonumber = _G.tonumber
local tostring = _G.tostring
local select   = _G.select
local IsInInstance = _G.IsInInstance
local issecretvalue = _G.issecretvalue
local InCombatLockdown = _G.InCombatLockdown
local UnitGUID = _G.UnitGUID
local UnitIsAFK = _G.UnitIsAFK
local UnitIsDND = _G.UnitIsDND
local math = _G.math
local wipe = _G.wipe
if not wipe then
    wipe = function(t)
        if not t then return end
        for k in pairs(t) do t[k] = nil end
    end
end
-- Lua 5.1 (WoW) uses global unpack; some environments expose table.unpack
local unpack = _G.unpack
if not unpack then
    local tbl = _G.table
    unpack = tbl and tbl.unpack
end

local function _MSUF_StatusIconsTestActive(conf, generalConf)
    if _G.MSUF_InCombat == true or ((InCombatLockdown and InCombatLockdown()) and true or false) then
        return false
    end
    return ((generalConf and generalConf.stateIconsTestMode == true)
        or (conf and conf.stateIconsTestMode == true)) and true or false
end

-- Status text DB (AFK/DND/DEAD/GHOST/OFFLINE)
if type(_G.MSUF_GetStatusIndicatorDB) ~= "function" then
    -- PERF: Avoid per-call table allocations. This can be hit during very early load
    -- (before EnsureDB is available), and MSUF_GetStatusIndicatorDB may be called in hot paths.
    local _MSUF_DEFAULT_STATUS_INDICATORS = {
        showAFK = true,
        showDND = true,
        showDead = true,
        showGhost = true,
    }
    local function _MSUF_DefaultStatusIndicators()
        return _MSUF_DEFAULT_STATUS_INDICATORS
    end
    function _G.MSUF_GetStatusIndicatorDB()
        if _G.EnsureDB then
            _G.EnsureDB()
        end
        local db = _G.MSUF_DB
        local g = (db) and db.general or nil
        if type(g) ~= "table" then
            return _MSUF_DefaultStatusIndicators()
        end
        if type(g.statusIndicators) ~= "table" then
            g.statusIndicators = {}
        end
        local si = g.statusIndicators
        if si.showAFK == nil then si.showAFK = true end
        if si.showDND == nil then si.showDND = true end
        if si.showDead == nil then si.showDead = true end
        if si.showGhost == nil then si.showGhost = true end
         return si
    end
end
-- Backwards alias used by older call sites
MSUF_GetStatusIndicatorDB = _G.MSUF_GetStatusIndicatorDB

-- AFK/DND are event-driven flags. Cache them separately from the status text
-- refresh path so UpdateStatusIndicator can run often without repeatedly
-- calling UnitIsAFK/UnitIsDND.
local MSUF_AWAY_AFK = 1
local MSUF_AWAY_DND = 2

local _msufAwayFlagsByGUID = ns._msufAwayFlagsByGUID
if type(_msufAwayFlagsByGUID) ~= "table" then
    _msufAwayFlagsByGUID = {}
    ns._msufAwayFlagsByGUID = _msufAwayFlagsByGUID
end
local _msufAwayCheckedByGUID = ns._msufAwayCheckedByGUID
if type(_msufAwayCheckedByGUID) ~= "table" then
    _msufAwayCheckedByGUID = {}
    ns._msufAwayCheckedByGUID = _msufAwayCheckedByGUID
end
local _msufAwayFlagsByUnit = ns._msufAwayFlagsByUnit
if type(_msufAwayFlagsByUnit) ~= "table" then
    _msufAwayFlagsByUnit = {}
    ns._msufAwayFlagsByUnit = _msufAwayFlagsByUnit
end
local _msufAwayCheckedByUnit = ns._msufAwayCheckedByUnit
if type(_msufAwayCheckedByUnit) ~= "table" then
    _msufAwayCheckedByUnit = {}
    ns._msufAwayCheckedByUnit = _msufAwayCheckedByUnit
end
local _msufAwayCacheCount = ns._msufAwayCacheCount or 0
ns._msufAwayRevision = ns._msufAwayRevision or 0

local function _MSUF_AwayHasBit(flags, bit)
    if bit == MSUF_AWAY_AFK then
        return flags == 1 or flags == 3
    end
    return flags == 2 or flags == 3
end

local function _MSUF_AwaySetBit(flags, bit, enabled)
    flags = flags or 0
    local has = _MSUF_AwayHasBit(flags, bit)
    if enabled then
        return has and flags or (flags + bit)
    end
    return has and (flags - bit) or flags
end

local function _MSUF_AwayRequested(needAFK, needDND)
    local requested = 0
    if needAFK then requested = _MSUF_AwaySetBit(requested, MSUF_AWAY_AFK, true) end
    if needDND then requested = _MSUF_AwaySetBit(requested, MSUF_AWAY_DND, true) end
    return requested
end

local function _MSUF_AwayHasRequested(checked, requested)
    if _MSUF_AwayHasBit(requested, MSUF_AWAY_AFK) and not _MSUF_AwayHasBit(checked, MSUF_AWAY_AFK) then
        return false
    end
    if _MSUF_AwayHasBit(requested, MSUF_AWAY_DND) and not _MSUF_AwayHasBit(checked, MSUF_AWAY_DND) then
        return false
    end
    return true
end

local function _MSUF_AwayCacheKey(unit)
    if not unit then return nil, nil, nil end
    local guid = UnitGUID and UnitGUID(unit)
    if issecretvalue and issecretvalue(guid) then guid = nil end
    if guid then
        return _msufAwayFlagsByGUID, _msufAwayCheckedByGUID, guid
    end
    return _msufAwayFlagsByUnit, _msufAwayCheckedByUnit, unit
end

local function _MSUF_ClearAwayStatusCache()
    wipe(_msufAwayFlagsByGUID)
    wipe(_msufAwayCheckedByGUID)
    wipe(_msufAwayFlagsByUnit)
    wipe(_msufAwayCheckedByUnit)
    _msufAwayCacheCount = 0
    ns._msufAwayCacheCount = 0
    ns._msufAwayRevision = (ns._msufAwayRevision or 0) + 1
end
ns.MSUF_ClearAwayStatusCache = _MSUF_ClearAwayStatusCache
_G.MSUF_ClearAwayStatusCache = _MSUF_ClearAwayStatusCache

local function _MSUF_InvalidateAwayStatus(unit)
    if not unit then return end
    local guid = UnitGUID and UnitGUID(unit)
    if issecretvalue and issecretvalue(guid) then guid = nil end
    if guid then
        _msufAwayFlagsByGUID[guid] = nil
        _msufAwayCheckedByGUID[guid] = nil
    end
    _msufAwayFlagsByUnit[unit] = nil
    _msufAwayCheckedByUnit[unit] = nil
    ns._msufAwayRevision = (ns._msufAwayRevision or 0) + 1
end
ns.MSUF_InvalidateAwayStatus = _MSUF_InvalidateAwayStatus
_G.MSUF_InvalidateAwayStatus = _MSUF_InvalidateAwayStatus

local function _MSUF_ReadAwayBit(unit, bit)
    if bit == MSUF_AWAY_AFK then
        if not UnitIsAFK then return false end
        local afk = UnitIsAFK(unit)
        if issecretvalue and issecretvalue(afk) then return nil end
        return afk == true
    end

    if not UnitIsDND then return false end
    local dnd = UnitIsDND(unit)
    if issecretvalue and issecretvalue(dnd) then return nil end
    return dnd == true
end

local function _MSUF_GetCachedAwayStatus(unit, needAFK, needDND, force)
    local requested = _MSUF_AwayRequested(needAFK, needDND)
    if requested == 0 or not unit or ns._msufAwaySuppressed == true then
        return 0
    end

    local flagsMap, checkedMap, key = _MSUF_AwayCacheKey(unit)
    if not key then return 0 end

    local hadKey = (checkedMap[key] ~= nil)
    local flags = flagsMap[key] or 0
    local checked = (force == true) and 0 or (checkedMap[key] or 0)
    if _MSUF_AwayHasRequested(checked, requested) then
        return flags
    end

    if _MSUF_AwayHasBit(requested, MSUF_AWAY_AFK) and not _MSUF_AwayHasBit(checked, MSUF_AWAY_AFK) then
        local afk = _MSUF_ReadAwayBit(unit, MSUF_AWAY_AFK)
        if afk ~= nil then
            flags = _MSUF_AwaySetBit(flags, MSUF_AWAY_AFK, afk)
            checked = _MSUF_AwaySetBit(checked, MSUF_AWAY_AFK, true)
        end
    end
    if _MSUF_AwayHasBit(requested, MSUF_AWAY_DND) and not _MSUF_AwayHasBit(checked, MSUF_AWAY_DND) then
        local dnd = _MSUF_ReadAwayBit(unit, MSUF_AWAY_DND)
        if dnd ~= nil then
            flags = _MSUF_AwaySetBit(flags, MSUF_AWAY_DND, dnd)
            checked = _MSUF_AwaySetBit(checked, MSUF_AWAY_DND, true)
        end
    end

    if not hadKey then
        _msufAwayCacheCount = _msufAwayCacheCount + 1
        if _msufAwayCacheCount > 128 then
            _MSUF_ClearAwayStatusCache()
            _msufAwayCacheCount = 1
        end
        ns._msufAwayCacheCount = _msufAwayCacheCount
    end
    flagsMap[key] = flags
    checkedMap[key] = checked
    return flags
end
ns.MSUF_GetCachedAwayStatus = _MSUF_GetCachedAwayStatus
_G.MSUF_GetCachedAwayStatus = _MSUF_GetCachedAwayStatus

-- Midnight/Beta (12.0+): AFK/DND can return secret booleans in combat/encounters.
-- Cache suppression state via events to avoid per-frame InCombatLockdown/IsEncounter calls.
if ns._msufAwaySuppressed == nil then
    local function _MSUF_AwaySuppressedNow()
        -- Midnight/Beta (12.0+): chat messaging lockdown causes UnitIsAFK/UnitIsDND to return secret values.
        local CCI = _G.C_ChatInfo
        if CCI and CCI.InChatMessagingLockdown and CCI.InChatMessagingLockdown() then
            return true
        end

        -- Match the GF pipeline behavior: instances are fine out of combat.
        -- Only suppress the client-limited case: instance combat/encounters.
        local inInst = false
        if IsInInstance then
            inInst = IsInInstance()
            if issecretvalue and issecretvalue(inInst) then inInst = false end
        end
        if inInst then
            if InCombatLockdown and InCombatLockdown() then
                return true
            end
            local CIE = _G.C_InstanceEncounter
            if CIE and CIE.IsEncounterInProgress and CIE.IsEncounterInProgress() then
                return true
            end
        end

        return false
    end

    ns._msufAwaySuppressed = _MSUF_AwaySuppressedNow()

    local f = CreateFrame and CreateFrame("Frame") or nil
    if f then
        f:RegisterEvent("PLAYER_REGEN_DISABLED")
        f:RegisterEvent("PLAYER_REGEN_ENABLED")
        f:RegisterEvent("ENCOUNTER_START")
        f:RegisterEvent("ENCOUNTER_END")
        f:RegisterEvent("PLAYER_ENTERING_WORLD")
        f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        f:RegisterEvent("PLAYER_FLAGS_CHANGED")

        local function _MSUF_AwayState_OnEvent(_, event, unit)
            if event == "PLAYER_FLAGS_CHANGED" then
                _MSUF_InvalidateAwayStatus(unit or "player")
                return
            end

            local oldSuppressed = ns._msufAwaySuppressed
            ns._msufAwaySuppressed = _MSUF_AwaySuppressedNow()
            if oldSuppressed ~= ns._msufAwaySuppressed or event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
                _MSUF_ClearAwayStatusCache()
            end
        end
        f:SetScript("OnEvent", _MSUF_AwayState_OnEvent)
    end
end

-- Helpers (read config with global fallback)
local function _MSUF_ReadBool(conf, g, k, defaultVal, legacyKey)
    local v
    if type(conf) == "table" then
        v = conf[k]
        if v == nil and legacyKey then v = conf[legacyKey] end
    end
    if v == nil and type(g) == "table" then
        v = g[k]
        if v == nil and legacyKey then v = g[legacyKey] end
    end
    if v == nil then v = defaultVal end
    return (v ~= false)
end
local function _MSUF_ReadNumber(conf, g, k, defaultVal, legacyKey)
    local v
    if type(conf) == "table" then
        v = conf[k]
        if v == nil and legacyKey then v = conf[legacyKey] end
    end
    if v == nil and type(g) == "table" then
        v = g[k]
        if v == nil and legacyKey then v = g[legacyKey] end
    end
    v = tonumber(v)
    if v == nil then v = defaultVal end
     return v
end
local function _MSUF_ReadStr(conf, g, k, defaultVal, legacyKey)
    local v
    if type(conf) == "table" then
        v = conf[k]
        if v == nil and legacyKey then v = conf[legacyKey] end
    end
    if v == nil and type(g) == "table" then
        v = g[k]
        if v == nil and legacyKey then v = g[legacyKey] end
    end
    if v == nil then v = defaultVal end
     return v
end
local function _MSUF_ClampIconLayer(v, defaultVal)
    v = tonumber(v) or defaultVal or 7
    v = math.floor(v + 0.5)
    if v < 1 then return 1 end
    if v > 10 then return 10 end
    return v
end
local function _MSUF_ApplyIconLayer(region, layer, owner)
    if not region then return end
    local layout = ns.Icons and ns.Icons._layout
    if layout and layout.ApplyLayer then
        layout.ApplyLayer(region, layer, owner or region._msufLayerOwner)
        return
    end
    if region.SetDrawLayer then
        local sub = (tonumber(layer) or 7) - 1
        if sub < 0 then sub = 0 elseif sub > 7 then sub = 7 end
        region:SetDrawLayer("OVERLAY", sub)
    end
end

local function _MSUF_GetStatusTextConfig(frame, db)
    if not frame then return nil end
    db = db or _G.MSUF_DB
    if not db then return nil end
    local unit = frame.unit
    local key = frame.msufConfigKey
    if type(key) == "string" and key:match("^boss") then key = "boss" end
    if key == "tot" or key == "targetoftarget" or key == "target_of_target" then key = "targettarget" end
    if not key then
        if frame._msufIsPlayer or unit == "player" then
            key = "player"
        elseif frame._msufIsTarget or unit == "target" then
            key = "target"
        elseif type(unit) == "string" and unit:match("^boss") then
            key = "boss"
        elseif unit == "focus" or unit == "pet" or unit == "targettarget" or unit == "tot" then
            key = (unit == "tot") and "targettarget" or unit
        end
    end
    return key and db[key] or nil, db.general or nil
end

local function _MSUF_GetStatusTextSize(conf, g)
    local v = _MSUF_ReadNumber(conf, g, "statusTextSize", nil)
    if type(v) ~= "number" then
        v = ((g and (tonumber(g.nameFontSize) or tonumber(g.fontSize))) or 14) + 2
    end
    v = math.floor((tonumber(v) or 16) + 0.5)
    if v < 8 then return 8 end
    if v > 64 then return 64 end
    return v
end

local function _MSUF_JustifyForAnchor(anchor)
    if anchor == "CENTER" or anchor == "TOP" or anchor == "BOTTOM" then
        return "CENTER"
    end
    if anchor == "TOPRIGHT" or anchor == "BOTTOMRIGHT" or anchor == "RIGHT" then
        return "RIGHT"
    end
    return "LEFT"
end

function _G.MSUF_ApplyStatusTextLayout(frame)
    if not frame then return end
    local conf, g = _MSUF_GetStatusTextConfig(frame)
    local anchor = _MSUF_ReadStr(conf, g, "statusTextAnchor", "CENTER")
    local x = _MSUF_ReadNumber(conf, g, "statusTextOffsetX", 0)
    local y = _MSUF_ReadNumber(conf, g, "statusTextOffsetY", 0)
    local size = _MSUF_GetStatusTextSize(conf, g)
    local layer = _MSUF_ClampIconLayer(_MSUF_ReadNumber(conf, g, "statusTextLayer", 7), 7)
    local owner = frame.hpBar or frame.health or frame
    local justify = _MSUF_JustifyForAnchor(anchor)

    local function apply(fs)
        if not fs then return end
        if fs.GetFont and fs.SetFont then
            local fontPath, _, flags = fs:GetFont()
            if fontPath then
                local g = _G.MSUF_DB and _G.MSUF_DB.general
                if type(_G.MSUF_SetFontSafe) == "function" then
                    _G.MSUF_SetFontSafe(fs, fontPath, size, flags or "", (g and g.fontKey) or "FRIZQT")
                else
                    fs:SetFont(fontPath, size, flags or "")
                end
            end
        end
        fs:ClearAllPoints()
        fs:SetPoint(anchor, owner, anchor, x, y)
        if fs.SetJustifyH then fs:SetJustifyH(justify) end
        if fs.SetJustifyV then fs:SetJustifyV("MIDDLE") end
        _MSUF_ApplyIconLayer(fs, layer, frame)
    end

    apply(frame.statusIndicatorText)
    apply(frame.statusIndicatorOverlayText)
end

-- Status Icon Symbol Textures (Classic vs Midnight)
local function _MSUF_GetStatusIconsUseMidnight(conf, g)
    -- Global by design; allow per-frame legacy if ever present.
    if conf and conf.statusIconsUseMidnightStyle ~= nil then
        return (conf.statusIconsUseMidnightStyle == true)
    end
    if g and g.statusIconsUseMidnightStyle ~= nil then
        return (g.statusIconsUseMidnightStyle == true)
    end
     return false
end
-- Status Icon Symbol Textures (Classic vs Midnight)
-- Supports different symbol families:
--   weapon_*         -> Media/Symbols/Combat         (128_clean)
--   rested_*         -> Media/Symbols/Rested         (64)
--   resurrection_*   -> Media/Symbols/Ress           (64)
--   classification_* -> Media/Symbols/Classification (64)
local _MSUF_TexPathCache = {}
local function _MSUF_BuildStatusIconSymbolTexturePath(symbolKey, useMidnight)
    if type(symbolKey) ~= "string" or symbolKey == "" or symbolKey == "DEFAULT" then
         return nil
    end
    -- Memoize: symbolKey + style rarely change; avoid repeated string concatenation.
    local cacheKey = useMidnight and symbolKey or (symbolKey .. "\0C")
    local cached = _MSUF_TexPathCache[cacheKey]
    if cached then return cached end

    local folder = "Combat"
    local suffix = useMidnight and "_midnight_128_clean.tga" or "_classic_128_clean.tga"
    if string.find(symbolKey, "^rested_") then
        folder = "Rested"
        suffix = useMidnight and "_midnight_64.tga" or "_classic_64.tga"
    elseif string.find(symbolKey, "^resurrection_") then
        folder = "Ress"
        suffix = useMidnight and "_midnight_64.tga" or "_classic_64.tga"
    elseif string.find(symbolKey, "^classification_") then
        folder = "Classification"
        suffix = useMidnight and "_midnight_64.tga" or "_classic_64.tga"
    end
    local path = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Symbols\\" .. folder .. "\\" .. symbolKey .. suffix
    _MSUF_TexPathCache[cacheKey] = path
    return path
end
local function _MSUF_EnsurePulseAnim(tex)
    if not tex or not tex.CreateAnimationGroup then  return nil end
    if tex._msufPulseAnim then return tex._msufPulseAnim end
    local ag = tex:CreateAnimationGroup()
    ag:SetLooping("REPEAT")
    local a1 = ag:CreateAnimation("Alpha")
    a1:SetFromAlpha(0.45)
    a1:SetToAlpha(1.0)
    a1:SetDuration(0.85)
    a1:SetOrder(1)
    local a2 = ag:CreateAnimation("Alpha")
    a2:SetFromAlpha(1.0)
    a2:SetToAlpha(0.45)
    a2:SetDuration(0.85)
    a2:SetOrder(2)
    tex._msufPulseAnim = ag
     return ag
end
local function _MSUF_StopPulseAnim(tex)
    local ag = tex and tex._msufPulseAnim
    if ag and ag.Stop then ag:Stop() end
    if tex and tex.SetAlpha then tex:SetAlpha(1) end
 end
local function _MSUF_ApplyStatusIconSymbolTexture(tex, symbolKey, useMidnight, wantsPulse)
    if not tex or not tex.SetTexture then  return end

    local path = _MSUF_BuildStatusIconSymbolTexturePath(symbolKey, useMidnight)

    if not path then
        if tex._msufSymbolStamp then
            tex._msufSymbolStamp = nil
            -- Restore original texture/atlas when returning to DEFAULT.
            if tex._msufDefaultAtlas and tex.SetAtlas then
                tex:SetAtlas(tex._msufDefaultAtlas)
            elseif tex._msufDefaultTexture then
                tex:SetTexture(tex._msufDefaultTexture)
            end
            local tc = tex._msufDefaultTexCoord
            if tc and tex.SetTexCoord then
                tex:SetTexCoord(tc[1], tc[2], tc[3], tc[4], tc[5], tc[6], tc[7], tc[8])
            end
            _MSUF_StopPulseAnim(tex)
        end
        return
    end

    -- PERF: Stamp-first early exit — skip all work when texture hasn't changed
    local stamp = path
    if tex._msufSymbolStamp == stamp then
        -- Only check pulse state
        if wantsPulse then
            local ag = _MSUF_EnsurePulseAnim(tex)
            if ag and ag.Play and (not ag:IsPlaying()) then ag:Play() end
        else
            _MSUF_StopPulseAnim(tex)
        end
        return
    end

    -- Lazy capture defaults (once per texture, not every call)
    if not tex._msufDefaultsCaptured then
        tex._msufDefaultsCaptured = true
        if tex.GetTexture then tex._msufDefaultTexture = tex:GetTexture() end
        if tex.GetAtlas then
            local a = tex:GetAtlas()
            if a then tex._msufDefaultAtlas = a end
        end
        if tex.GetTexCoord then
            local ulx, uly, llx, lly, urx, ury, lrx, lry = tex:GetTexCoord()
            tex._msufDefaultTexCoord = { ulx, uly, llx, lly, urx, ury, lrx, lry }
        end
    end

    tex:SetTexture(path)
    tex._msufSymbolStamp = stamp
    if tex.SetTexCoord then
        tex:SetTexCoord(0, 1, 0, 1)
    end

    if wantsPulse then
        local ag = _MSUF_EnsurePulseAnim(tex)
        if ag and ag.Play and (not ag:IsPlaying()) then
            ag:Play()
        end
    else
        _MSUF_StopPulseAnim(tex)
    end
end
local function _MSUF_AnchorCorner(tex, frame, corner, xOff, yOff)
    if not tex or not frame then  return end
    corner = corner or "TOPLEFT"
    xOff = xOff or 0
    yOff = yOff or 0
    tex:ClearAllPoints()
    if corner == "CENTER" then
        tex:SetPoint("CENTER", frame, "CENTER", 0 + xOff, 0 + yOff)
         return
    end
    if corner == "TOPRIGHT" then
        tex:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2 + xOff, -2 + yOff)
         return
    elseif corner == "BOTTOMLEFT" then
        tex:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 2 + xOff, 2 + yOff)
         return
    elseif corner == "BOTTOMRIGHT" then
        tex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2 + xOff, 2 + yOff)
         return
    end
    -- TOPLEFT default
    tex:SetPoint("TOPLEFT", frame, "TOPLEFT", 2 + xOff, -2 + yOff)
 end
-- Target classification state (Boss / Elite / Rare)
local function _MSUF_GetClassificationState(unit)
    if not unit or not UnitExists or not UnitExists(unit) then
         return nil
    end
    local c = UnitClassification and UnitClassification(unit) or nil
    if c == "worldboss" then
         return "BOSS"
    end
    local n = UnitLevel and tonumber(UnitLevel(unit)) or nil
    if n == -1 then
         return "BOSS"
    end
    if c == "rareelite" then  return "RAREELITE" end
    if c == "rare"     then  return "RARE"     end
    if c == "elite"    then  return "ELITE"    end
     return nil
end
local function _MSUF_GetClassificationLabel(state)
    if state == "BOSS" then
         return "BOSS"
    end
    if state == "RAREELITE" then
         return "RARE+"
    end
    if state == "RARE" then
         return "RARE"
    end
    if state == "ELITE" then
         return "ELITE"
    end
     return ""
end
-- Status icons update (Combat / Resting / Incoming Res)
-- Summon was removed intentionally (user request)
local function _MSUF_UpdateStatusIcons(frame)
    if not frame or not frame.unit then  return end
    local unit = frame.unit
    local db = _G.MSUF_DB
    if not db then  return end
    local g = db.general or {}
    local conf
    if frame._msufIsPlayer then
        conf = db.player
    elseif frame._msufIsTarget then
        conf = db.target
    else
         return
    end
    if not conf then  return end

    -- PERF: Cache resolved icon config per-frame. DB reads don't change in combat.
    -- Cache invalidated when cachedConfig is cleared (config change).
    local sic = frame._msufStatusIconsConf
    if not sic then
        local testMode = _MSUF_StatusIconsTestActive(conf, g)
        local showCombat = _MSUF_ReadBool(conf, g, "showCombatStateIndicator", false)
        local showRest = false
        if frame._msufIsPlayer then
            showRest = _MSUF_ReadBool(conf, g, "showRestingIndicator", false, "showRestedStateIndicator")
        end
        local showRez = _MSUF_ReadBool(conf, g, "showIncomingResIndicator", false)
        local showClass = false
        if frame._msufIsTarget then
            showClass = _MSUF_ReadBool(conf, g, "showClassificationIndicator", false)
        end
        local useMidnight = _MSUF_GetStatusIconsUseMidnight(conf, g)
        local combatSymbol = _MSUF_ReadStr(conf, g, "combatStateIndicatorSymbol", "DEFAULT")
        local restSymbol   = _MSUF_ReadStr(conf, g, "restedStateIndicatorSymbol", "DEFAULT", "restingStateIndicatorSymbol")
        local rezSymbol    = _MSUF_ReadStr(conf, g, "incomingResIndicatorSymbol", "DEFAULT")
        local iconAlpha = _MSUF_ReadNumber(conf, g, "stateIconsAlpha", 1)
        local combatCorner = _MSUF_ReadStr(conf, g, "combatStateIndicatorAnchor", (g and g.combatStateIndicatorPos) or "TOPLEFT", "combatStateIndicatorPos")
        local combatX = _MSUF_ReadNumber(conf, g, "combatStateIndicatorOffsetX", 0)
        local combatY = _MSUF_ReadNumber(conf, g, "combatStateIndicatorOffsetY", 0)
        local combatSize = _MSUF_ReadNumber(conf, g, "combatStateIndicatorSize", 18)
        local combatLayer = _MSUF_ClampIconLayer(_MSUF_ReadNumber(conf, g, "combatStateIndicatorLayer", 7), 7)
        local restCorner = _MSUF_ReadStr(conf, g, "restedStateIndicatorAnchor", combatCorner)
        local restX = _MSUF_ReadNumber(conf, g, "restedStateIndicatorOffsetX", 0)
        local restY = _MSUF_ReadNumber(conf, g, "restedStateIndicatorOffsetY", 0)
        local restSize = _MSUF_ReadNumber(conf, g, "restedStateIndicatorSize", 18)
        local restLayer = _MSUF_ClampIconLayer(_MSUF_ReadNumber(conf, g, "restedStateIndicatorLayer", 7), 7)
        local rezCorner = _MSUF_ReadStr(conf, g, "incomingResIndicatorAnchor", (g and g.incomingResIndicatorPos) or "TOPRIGHT", "incomingResIndicatorPos")
        local rezX = _MSUF_ReadNumber(conf, g, "incomingResIndicatorOffsetX", 0)
        local rezY = _MSUF_ReadNumber(conf, g, "incomingResIndicatorOffsetY", 0)
        local rezSize = _MSUF_ReadNumber(conf, g, "incomingResIndicatorSize", 18)
        local rezLayer = _MSUF_ClampIconLayer(_MSUF_ReadNumber(conf, g, "incomingResIndicatorLayer", 7), 7)
        local classCorner = _MSUF_ReadStr(conf, g, "classificationIndicatorAnchor", "TOPLEFT")
        local classX = _MSUF_ReadNumber(conf, g, "classificationIndicatorOffsetX", 0)
        local classY = _MSUF_ReadNumber(conf, g, "classificationIndicatorOffsetY", 0)
        local classSize = _MSUF_ReadNumber(conf, g, "classificationIndicatorSize", 18)
        if type(classSize) ~= "number" then classSize = 18 end
        if classSize < 8 then classSize = 8 end
        if classSize > 64 then classSize = 64 end
        classSize = math.floor(classSize + 0.5)
        sic = {
            testMode = testMode, showCombat = showCombat, showRest = showRest,
            showRez = showRez, showClass = showClass, useMidnight = useMidnight,
            combatSymbol = combatSymbol, restSymbol = restSymbol, rezSymbol = rezSymbol,
            iconAlpha = iconAlpha,
            combatCorner = combatCorner, combatX = combatX, combatY = combatY, combatSize = combatSize, combatLayer = combatLayer,
            restCorner = restCorner, restX = restX, restY = restY, restSize = restSize, restLayer = restLayer,
            rezCorner = rezCorner, rezX = rezX, rezY = rezY, rezSize = rezSize, rezLayer = rezLayer,
            classCorner = classCorner, classX = classX, classY = classY, classSize = classSize,
            restNeedsPulse = (type(restSymbol) == "string" and string.find(restSymbol, "^rested_") ~= nil),
        }
        frame._msufStatusIconsConf = sic
    end

    local testMode = sic.testMode
    if testMode and (_G.MSUF_InCombat == true or ((InCombatLockdown and InCombatLockdown()) and true or false)) then
        testMode = false
    end
    -- Symbol textures (apply once per config, not per call)
    local combatIcon = frame.combatStateIndicatorIcon
    local restIcon = frame.restingIndicatorIcon
    local rezIcon = frame.incomingResIndicatorIcon
    local classIcon = frame.classificationIndicatorIcon
    local classText = frame.classificationIndicatorText
    -- Safety: Summon was removed; if any leftover texture exists, hard-hide it.
    local summonIcon = frame.summonIndicatorIcon
    if summonIcon and summonIcon.Hide then
        summonIcon:Hide()
    end
    _MSUF_ApplyStatusIconSymbolTexture(combatIcon, sic.combatSymbol, sic.useMidnight, false)
    _MSUF_ApplyStatusIconSymbolTexture(restIcon,   sic.restSymbol,   sic.useMidnight, sic.restNeedsPulse)
    _MSUF_ApplyStatusIconSymbolTexture(rezIcon,    sic.rezSymbol,    sic.useMidnight, false)
    local combatOn = (sic.showCombat and (testMode or ((UnitAffectingCombat and UnitAffectingCombat(unit)) and true or false)))
    local restOn = (sic.showRest and (testMode or ((IsResting and IsResting()) and true or false)))
    local rezOn = (sic.showRez and (testMode or ((UnitHasIncomingResurrection and UnitHasIncomingResurrection(unit)) and true or false)))
    local classState = nil
    if sic.showClass then
        classState = testMode and "BOSS" or _MSUF_GetClassificationState(unit)
    end
    local classOn = (sic.showClass and classState ~= nil)
    local iconAlpha = sic.iconAlpha
    -- Combat layout
    if combatIcon then
        if combatOn then
            if combatIcon._msufSizeStamp ~= sic.combatSize then
                combatIcon:SetSize(sic.combatSize, sic.combatSize)
                combatIcon._msufSizeStamp = sic.combatSize
            end
            _MSUF_ApplyIconLayer(combatIcon, sic.combatLayer, frame)
            _MSUF_AnchorCorner(combatIcon, frame, sic.combatCorner, sic.combatX, sic.combatY)
            combatIcon:SetAlpha(iconAlpha)
            combatIcon:Show()
        else
            combatIcon:Hide()
        end
    end
    if restIcon then
        if restOn then
            if restIcon._msufSizeStamp ~= sic.restSize then
                restIcon:SetSize(sic.restSize, sic.restSize)
                restIcon._msufSizeStamp = sic.restSize
            end
            _MSUF_ApplyIconLayer(restIcon, sic.restLayer, frame)
            _MSUF_AnchorCorner(restIcon, frame, sic.restCorner, sic.restX, sic.restY)
            restIcon:SetAlpha(iconAlpha)
            restIcon:Show()
        else
            _MSUF_StopPulseAnim(restIcon)
            restIcon:Hide()
        end
    end
    if rezIcon then
        if rezOn then
            if rezIcon._msufSizeStamp ~= sic.rezSize then
                rezIcon:SetSize(sic.rezSize, sic.rezSize)
                rezIcon._msufSizeStamp = sic.rezSize
            end
            _MSUF_ApplyIconLayer(rezIcon, sic.rezLayer, frame)
            _MSUF_AnchorCorner(rezIcon, frame, sic.rezCorner, sic.rezX, sic.rezY)
            rezIcon:SetAlpha(iconAlpha)
            rezIcon:Show()
        else
            rezIcon:Hide()
        end
    end
    -- Classification indicator: always render as TEXT (reliable even without Media assets)
    if classIcon and classIcon.Hide then
        classIcon:Hide()
    end
    if classText then
        if classOn then
            if classText._msufClassSizeStamp ~= sic.classSize then
                classText._msufClassSizeStamp = sic.classSize
                if _G.MSUF_UpdateAllFonts_Immediate then
                    _G.MSUF_UpdateAllFonts_Immediate()
                elseif _G.MSUF_UpdateAllFonts then
                    _G.MSUF_UpdateAllFonts()
                elseif _G.UpdateAllFonts then
                    _G.UpdateAllFonts()
                end
            end
            _MSUF_AnchorCorner(classText, frame, sic.classCorner, sic.classX, sic.classY)
            classText:SetAlpha(iconAlpha)
            if classText.SetJustifyH then
                local j = "LEFT"
                if sic.classCorner == "CENTER" then
                    j = "CENTER"
                elseif sic.classCorner == "TOPRIGHT" or sic.classCorner == "BOTTOMRIGHT" then
                    j = "RIGHT"
                end
                if classText._msufJustifyStamp ~= j then
                    classText:SetJustifyH(j)
                    classText._msufJustifyStamp = j
                end
            end
            local txt = _MSUF_GetClassificationLabel(classState)
            if _G.MSUF_SetTextIfChanged then
                _G.MSUF_SetTextIfChanged(classText, txt)
            else
                classText:SetText(txt)
            end
            classText:Show()
        else
            if _G.MSUF_SetTextIfChanged then
                _G.MSUF_SetTextIfChanged(classText, "")
            else
                classText:SetText("")
            end
            classText:Hide()
        end
    end
 end
-- PERF: Upvalue frequently-called functions (avoid _G hash lookup in hot paths).
local _MSUF_SetTextIfChanged = _G.MSUF_SetTextIfChanged
local _MSUF_StatusSetText
do
    -- Resolve once; use direct call in hot path.
    if type(_MSUF_SetTextIfChanged) == "function" then
        _MSUF_StatusSetText = _MSUF_SetTextIfChanged
    else
        _MSUF_StatusSetText = function(fs, txt) fs:SetText(txt) end
    end
end

-- Status text update (calls status icons update at the end)
function MSUF_UpdateStatusIndicatorForFrame(frame)
    if not frame or not frame.statusIndicatorText then return end
    local unit = frame.unit
    local dbRoot = _G.MSUF_DB
    local textConf, generalConf = _MSUF_GetStatusTextConfig(frame, dbRoot)
    if textConf and textConf.statusTextEnabled == false then
        local fsOff = frame.statusIndicatorText
        _MSUF_StatusSetText(fsOff, "")
        fsOff:Hide()
        if frame.statusIndicatorOverlayText then
            _MSUF_StatusSetText(frame.statusIndicatorOverlayText, "")
            frame.statusIndicatorOverlayText:Hide()
        end
        if frame.statusIndicatorOverlayFrame then frame.statusIndicatorOverlayFrame:Hide() end
        _MSUF_UpdateStatusIcons(frame)
        return
    end
    -- PERF: Cache resolved status indicator flags per-frame.
    -- The DB doesn't change in combat; cache is invalidated when cachedConfig is cleared.
    local sc = frame._msufStatusConf
    if not sc then
        local db = MSUF_GetStatusIndicatorDB and MSUF_GetStatusIndicatorDB() or nil
        db = (db) and db or {}
        sc = {
            showAFK   = (db.showAFK == true),
            showDND   = (db.showDND == true),
            showDead  = (db.showDead == true),
            showGhost = (db.showGhost == true),
        }
        frame._msufStatusConf = sc
    end
    local showAFK   = sc.showAFK
    local showDND   = sc.showDND
    local showDead  = sc.showDead
    local showGhost = sc.showGhost
    local txt = ""
    local testMode = _MSUF_StatusIconsTestActive(textConf, generalConf)
    if testMode and showDead then
        txt = "DEAD"
    elseif unit and UnitExists and UnitExists(unit) then
        -- Secret-safe: UnitIsConnected can return secret bool in 12.0 Midnight.
        -- Bool comparison or arithmetic on secret values hard-errors. Guard via issecretvalue.
        local connected
        if UnitIsConnected then
            connected = UnitIsConnected(unit)
            if issecretvalue and issecretvalue(connected) then connected = true end
        end
        if showDead and connected == false then
            txt = "OFFLINE"
        else
            -- UnitIsGhost / UnitIsDead / UnitIsDeadOrGhost: precautionary issecretvalue
            -- guards. Status booleans for non-self units may carry secret taint in 12.0
            -- (same risk class as UnitIsConnected). Falls back to "not in this state"
            -- on secret returns — matches GF_Effects UpdateStatusText pattern (L2036).
            local ghost
            if UnitIsGhost then
                ghost = UnitIsGhost(unit)
                if issecretvalue and issecretvalue(ghost) then ghost = false end
            end
            if showGhost and ghost then
                txt = "GHOST"
            elseif showDead then
                local isDead = false
                if UnitIsDead then
                    local d = UnitIsDead(unit)
                    if not (issecretvalue and issecretvalue(d)) and d then isDead = true end
                end
                if not isDead and UnitIsDeadOrGhost then
                    local d = UnitIsDeadOrGhost(unit)
                    if not (issecretvalue and issecretvalue(d)) and d then isDead = true end
                end
                if isDead and not ghost then
                    txt = "DEAD"
                end
            end
        end
	    if txt == "" and (showAFK or showDND) then
	        local forceAway = (frame._msufAwayForceRefresh == true)
	        frame._msufAwayForceRefresh = nil
	        local away
	        if unit == "player" and forceAway ~= true then
	            local rev = ns._msufAwayRevision or 0
	            if frame._msufAwayStatusRev == rev and frame._msufAwayStatusAFK == showAFK and frame._msufAwayStatusDND == showDND then
	                away = frame._msufAwayStatusFlags or 0
	            end
	        end
	        if away == nil then
	            away = _MSUF_GetCachedAwayStatus(unit, showAFK, showDND, forceAway)
	            if unit == "player" then
	                frame._msufAwayStatusRev = ns._msufAwayRevision or 0
	                frame._msufAwayStatusAFK = showAFK
	                frame._msufAwayStatusDND = showDND
	                frame._msufAwayStatusFlags = away
	            end
	        end
	        if showAFK and _MSUF_AwayHasBit(away, MSUF_AWAY_AFK) then
	            txt = "AFK"
	        elseif showDND and _MSUF_AwayHasBit(away, MSUF_AWAY_DND) then
	            txt = "DND"
	        end
	    else
	        frame._msufAwayForceRefresh = nil
	    end
    end
    local fs = frame.statusIndicatorText
    if _G.MSUF_ApplyStatusTextLayout then
        _G.MSUF_ApplyStatusTextLayout(frame)
    end
    local ovText = frame.statusIndicatorOverlayText
    local ovFrame = frame.statusIndicatorOverlayFrame
    if ovText and ovFrame then
        _MSUF_StatusSetText(ovText, "")
        ovText:Hide()
        ovFrame:Hide()
    end
    if txt ~= "" then
        _MSUF_StatusSetText(fs, txt)
        if fs.SetIgnoreParentAlpha then
            fs:SetIgnoreParentAlpha((txt == "OFFLINE" or txt == "DEAD"))
        end
        fs:SetAlpha(1)
        fs:Show()
    else
        if fs.SetIgnoreParentAlpha then
            fs:SetIgnoreParentAlpha(false)
        end
        fs:SetAlpha(1)
        _MSUF_StatusSetText(fs, "")
        fs:Hide()
    end
    _MSUF_UpdateStatusIcons(frame)
 end
-- Public refresh helper
_G.MSUF_RefreshStatusIndicators = function()
    local frames = _G.MSUF_UnitFrames
    local seen
    local function refreshFrame(f)
        if not f then return end
        if seen then seen[f] = true end
        f._msufStatusConf = nil
        f._msufAwayForceRefresh = true
        if f._msufIsGroupFrame and type(_G.MSUF_GF_UpdateStatus) == "function" then
            f._msufGFStatusState = nil
            _G.MSUF_GF_UpdateStatus(f, f.unit, true)
        else
            MSUF_UpdateStatusIndicatorForFrame(f)
        end
    end

    if type(frames) == "table" then
        seen = {}
        for _, f in pairs(frames) do
            refreshFrame(f)
        end
    end

    local gf = _G.MSUF_NS and _G.MSUF_NS.GF
    if gf and type(gf.ForEachFrame) == "function" then
        gf.ForEachFrame(function(f)
            if not seen or not seen[f] then
                refreshFrame(f)
            end
        end)
    end
 end
-- Keep a compatibility stub because older code may call this helper.
do
    local function _MSUF_StopStatusIndicatorTicker()
        local t = _G.MSUF_StatusIndicatorTicker
        if t and t.Cancel then
            t:Cancel()
        end
        _G.MSUF_StatusIndicatorTicker = nil
     end
    _G.MSUF_EnsureStatusIndicatorTicker = function()
        _MSUF_StopStatusIndicatorTicker()
     end
    _MSUF_StopStatusIndicatorTicker()
end
-- Shared API: Status Icons Test Mode
-- Used by Frames menus (Player/Target) and the MSUF Edit Mode panel.
do
    local function _MSUF_RequestUFUpdate(key, reason)
        local uf = _G and (_G.MSUF_UnitFrames or _G.UnitFrames)
        local fr = (uf and key) and uf[key] or nil
        if fr then
            if _G.MSUF_RequestUnitframeUpdate then
                _G.MSUF_RequestUnitframeUpdate(fr, true, true, reason or "StatusIconsTestMode")
            elseif _G.UpdateSimpleUnitFrame then
                _G.UpdateSimpleUnitFrame(fr)
            end
        end
     end
    function _G.MSUF_GetStatusIconsTestMode()
        if _G.EnsureDB then _G.EnsureDB() end
        local db = _G.MSUF_DB
        local g = (db) and db.general or nil
        return (g and g.stateIconsTestMode == true) or false
    end
    function _G.MSUF_SetStatusIconsTestMode(enabled, reason)
        if enabled and (_G.MSUF_InCombat == true or ((InCombatLockdown and InCombatLockdown()) and true or false)) then
            enabled = false
        end
        if _G.EnsureDB then _G.EnsureDB() end
        local db = _G.MSUF_DB
        if not db then  return end
        db.general = (type(db.general) == "table") and db.general or {}
        db.general.stateIconsTestMode = (enabled and true) or false
        if _G.MSUF_RefreshStatusIconsOptionsUI then
            _G.MSUF_RefreshStatusIconsOptionsUI()
        end
        _MSUF_RequestUFUpdate("player", reason or "StatusIconsTestMode")
        _MSUF_RequestUFUpdate("target", reason or "StatusIconsTestMode")
     end
end
