-- Status Indicator + Status Icons (Combat/Resting/Incoming Res)
-- NOTE: This file exists in Core/ for newer layouts. A copy is also shipped at addon root for older .toc layouts.
--
-- Provides:
--   MSUF_UpdateStatusIndicatorForFrame(frame)  (global)
--   MSUF_GetStatusIndicatorDB()               (global)
--   MSUF_GetStatusIconsTestMode()/Set...      (global)

local addonName, ns = ...
ns = ns or {}

-- ------------------------------------------------------------
-- Status text DB (AFK/DND/DEAD/GHOST/OFFLINE)
-- ------------------------------------------------------------

if type(_G.MSUF_GetStatusIndicatorDB) ~= "function" then
    local function _MSUF_DefaultStatusIndicators()
        return {
            showAFK = true,
            showDND = true,
            showDead = true,
            showGhost = true,
        }
    end

    function _G.MSUF_GetStatusIndicatorDB()
        if type(_G.EnsureDB) == "function" then
            _G.EnsureDB()
        end

        local db = _G.MSUF_DB
        local g = (type(db) == "table") and db.general or nil
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

-- ------------------------------------------------------------
-- Helpers (read config with global fallback)
-- ------------------------------------------------------------

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

-- ------------------------------------------------------------
-- Status Icon Symbol Textures (Classic vs Midnight)
-- ------------------------------------------------------------
local function _MSUF_GetStatusIconsUseMidnight(conf, g)
    -- Global by design; allow per-frame legacy if ever present.
    if type(conf) == "table" and conf.statusIconsUseMidnightStyle ~= nil then
        return (conf.statusIconsUseMidnightStyle == true)
    end
    if type(g) == "table" and g.statusIconsUseMidnightStyle ~= nil then
        return (g.statusIconsUseMidnightStyle == true)
    end
    return false
end

local function _MSUF_BuildStatusIconSymbolTexturePath(symbolKey, useMidnight)
    if type(symbolKey) ~= "string" or symbolKey == "" or symbolKey == "DEFAULT" then
        return nil
    end
    -- Custom slots are reserved for later user-provided textures.
    if symbolKey == "CUSTOM1" or symbolKey == "CUSTOM2" then
        return nil
    end

    local suffix = (useMidnight == true) and "_midnight_128_clean.tga" or "_classic_128_clean.tga"
    return "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Symbols\\Combat\\" .. symbolKey .. suffix
end

local function _MSUF_ApplyStatusIconSymbolTexture(tex, symbolKey, useMidnight)
    if not tex or not tex.SetTexture then return end

    -- Capture default texcoords so we can restore them when the user selects
    -- DEFAULT again. MSUF's built-in status icons may use cropped coords,
    -- but custom symbol TGAs should be displayed fully.
    if tex._msufDefaultTexCoord == nil and tex.GetTexCoord then
        local ulx, uly, llx, lly, urx, ury, lrx, lry = tex:GetTexCoord()
        tex._msufDefaultTexCoord = { ulx, uly, llx, lly, urx, ury, lrx, lry }
    end

    local path = _MSUF_BuildStatusIconSymbolTexturePath(symbolKey, useMidnight)
    if not path then
        -- Keep whatever default texture was assigned during creation.
        tex._msufSymbolStamp = nil

        -- Restore original texcoords when returning to DEFAULT.
        local tc = tex._msufDefaultTexCoord
        if tc and tex.SetTexCoord then
            tex:SetTexCoord(tc[1], tc[2], tc[3], tc[4], tc[5], tc[6], tc[7], tc[8])
        end
        return
    end

    local stamp = path
    if tex._msufSymbolStamp ~= stamp then
        tex:SetTexture(path)
        tex._msufSymbolStamp = stamp

        -- Ensure the symbol TGAs are not cropped.
        if tex.SetTexCoord then
            tex:SetTexCoord(0, 1, 0, 1)
        end
    end
end


local function _MSUF_AnchorCorner(tex, frame, corner, xOff, yOff)
    if not tex or not frame then return end
    corner = corner or "TOPLEFT"
    xOff = xOff or 0
    yOff = yOff or 0
    tex:ClearAllPoints()

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

-- ------------------------------------------------------------
-- Status icons update (Combat / Resting / Incoming Res)
-- Summon was removed intentionally (user request)
-- ------------------------------------------------------------

local function _MSUF_UpdateStatusIcons(frame)
    if not frame or not frame.unit then return end
    local unit = frame.unit

    local db = _G.MSUF_DB
    if type(db) ~= "table" then return end
    local g = db.general or {}

    local conf
    if frame._msufIsPlayer then
        conf = db.player
    elseif frame._msufIsTarget then
        conf = db.target
    else
        return
    end
    if type(conf) ~= "table" then return end

    -- Test mode is global (sync across frames) but we accept per-frame legacy keys if present.
    local testMode = ((type(g) == "table" and g.stateIconsTestMode == true) or (type(conf) == "table" and conf.stateIconsTestMode == true)) and true or false

    local showCombat = _MSUF_ReadBool(conf, g, "showCombatStateIndicator", false)
    local showRest = false
    if frame._msufIsPlayer then
        showRest = _MSUF_ReadBool(conf, g, "showRestingIndicator", false, "showRestedStateIndicator")
    end
    local showRez = _MSUF_ReadBool(conf, g, "showIncomingResIndicator", false)

    local combatIcon = frame.combatStateIndicatorIcon
    local restIcon = frame.restingIndicatorIcon
    local rezIcon = frame.incomingResIndicatorIcon

    -- Safety: Summon was removed; if any leftover texture exists, hard-hide it.
    local summonIcon = frame.summonIndicatorIcon
    if summonIcon and summonIcon.Hide then
        summonIcon:Hide()
    
-- Symbol textures (selected via Options -> Status icons)
local useMidnight = _MSUF_GetStatusIconsUseMidnight(conf, g)

local combatSymbol = _MSUF_ReadStr(conf, g, "combatStateIndicatorSymbol", "DEFAULT")
local restSymbol   = _MSUF_ReadStr(conf, g, "restingStateIndicatorSymbol", "DEFAULT", "restedStateIndicatorSymbol")
local rezSymbol    = _MSUF_ReadStr(conf, g, "incomingResIndicatorSymbol", "DEFAULT")

_MSUF_ApplyStatusIconSymbolTexture(combatIcon, combatSymbol, useMidnight)
_MSUF_ApplyStatusIconSymbolTexture(restIcon, restSymbol, useMidnight)
_MSUF_ApplyStatusIconSymbolTexture(rezIcon, rezSymbol, useMidnight)

end

    local combatOn = (showCombat and (testMode or ((UnitAffectingCombat and UnitAffectingCombat(unit)) and true or false)))
    local restOn = (showRest and (testMode or ((IsResting and IsResting()) and true or false)))
    local rezOn = (showRez and (testMode or ((UnitHasIncomingResurrection and UnitHasIncomingResurrection(unit)) and true or false)))

    local iconAlpha = _MSUF_ReadNumber(conf, g, "stateIconsAlpha", 1)

    -- Combat layout
    local combatCorner = _MSUF_ReadStr(conf, g, "combatStateIndicatorAnchor", (type(g) == "table" and g.combatStateIndicatorPos) or "TOPLEFT", "combatStateIndicatorPos")
    local combatX = _MSUF_ReadNumber(conf, g, "combatStateIndicatorOffsetX", 0)
    local combatY = _MSUF_ReadNumber(conf, g, "combatStateIndicatorOffsetY", 0)
    local combatSize = _MSUF_ReadNumber(conf, g, "combatStateIndicatorSize", 18)

    if combatIcon then
        if combatOn then
            if combatIcon._msufSizeStamp ~= combatSize then
                combatIcon:SetSize(combatSize, combatSize)
                combatIcon._msufSizeStamp = combatSize
            end
            _MSUF_AnchorCorner(combatIcon, frame, combatCorner, combatX, combatY)
            combatIcon:SetAlpha(iconAlpha)
            combatIcon:Show()
        else
            combatIcon:Hide()
        end
    end

    if restIcon then
        if restOn then
            local restCorner = _MSUF_ReadStr(conf, g, "restedStateIndicatorAnchor", combatCorner)
            local restX = _MSUF_ReadNumber(conf, g, "restedStateIndicatorOffsetX", combatX)
            local restY = _MSUF_ReadNumber(conf, g, "restedStateIndicatorOffsetY", combatY)
            local restSize = _MSUF_ReadNumber(conf, g, "restedStateIndicatorSize", combatSize)

            if restIcon._msufSizeStamp ~= restSize then
                restIcon:SetSize(restSize, restSize)
                restIcon._msufSizeStamp = restSize
            end

            -- If both use same corner and combat is visible, stack resting under combat (UUF-style).
            if restCorner == combatCorner and combatOn and combatIcon and combatIcon.IsShown and combatIcon:IsShown() then
                local gap = 2
                restIcon:ClearAllPoints()
                if restCorner == "TOPLEFT" then
                    restIcon:SetPoint("TOPLEFT", combatIcon, "TOPLEFT", 0, -(combatSize + gap))
                elseif restCorner == "TOPRIGHT" then
                    restIcon:SetPoint("TOPRIGHT", combatIcon, "TOPRIGHT", 0, -(combatSize + gap))
                elseif restCorner == "BOTTOMLEFT" then
                    restIcon:SetPoint("BOTTOMLEFT", combatIcon, "BOTTOMLEFT", 0, (combatSize + gap))
                else -- BOTTOMRIGHT
                    restIcon:SetPoint("BOTTOMRIGHT", combatIcon, "BOTTOMRIGHT", 0, (combatSize + gap))
                end
            else
                _MSUF_AnchorCorner(restIcon, frame, restCorner, restX, restY)
            end

            restIcon:SetAlpha(iconAlpha)
            restIcon:Show()
        else
            restIcon:Hide()
        end
    end

    if rezIcon then
        if rezOn then
            local rezCorner = _MSUF_ReadStr(conf, g, "incomingResIndicatorAnchor", (type(g) == "table" and g.incomingResIndicatorPos) or "TOPRIGHT", "incomingResIndicatorPos")
            local rezX = _MSUF_ReadNumber(conf, g, "incomingResIndicatorOffsetX", 0)
            local rezY = _MSUF_ReadNumber(conf, g, "incomingResIndicatorOffsetY", 0)
            local rezSize = _MSUF_ReadNumber(conf, g, "incomingResIndicatorSize", 18)

            if rezIcon._msufSizeStamp ~= rezSize then
                rezIcon:SetSize(rezSize, rezSize)
                rezIcon._msufSizeStamp = rezSize
            end
            _MSUF_AnchorCorner(rezIcon, frame, rezCorner, rezX, rezY)
            rezIcon:SetAlpha(iconAlpha)
            rezIcon:Show()
        else
            rezIcon:Hide()
        end
    end
end

-- ------------------------------------------------------------
-- Status text update (calls status icons update at the end)
-- ------------------------------------------------------------

function MSUF_UpdateStatusIndicatorForFrame(frame)
    if not frame or not frame.statusIndicatorText then
        return
    end

    local unit = frame.unit
    local db = _G.MSUF_GetStatusIndicatorDB and _G.MSUF_GetStatusIndicatorDB() or nil
    db = (type(db) == "table") and db or {}

    local showAFK   = (db.showAFK == true)
    local showDND   = (db.showDND == true)
    local showDead  = (db.showDead == true)   -- also covers OFFLINE
    local showGhost = (db.showGhost == true)

    local txt = ""
    if unit and UnitExists and UnitExists(unit) then
        if showDead and UnitIsConnected and (UnitIsConnected(unit) == false) then
            txt = "OFFLINE"
        elseif showGhost and UnitIsGhost and UnitIsGhost(unit) then
            txt = "GHOST"
        elseif showDead then
            local isDead = false
            if UnitIsDead and UnitIsDead(unit) then
                isDead = true
            elseif UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) then
                isDead = true
            end
            if isDead and (not (UnitIsGhost and UnitIsGhost(unit))) then
                txt = "DEAD"
            end
        end

        if txt == "" then
            if showAFK and UnitIsAFK and UnitIsAFK(unit) then
                txt = "AFK"
            elseif showDND and UnitIsDND and UnitIsDND(unit) then
                txt = "DND"
            end
        end
    end

    local fs = frame.statusIndicatorText
    local ovText = frame.statusIndicatorOverlayText
    local ovFrame = frame.statusIndicatorOverlayFrame
    if ovText and ovFrame then
        if type(_G.MSUF_SetTextIfChanged) == "function" then
            _G.MSUF_SetTextIfChanged(ovText, "")
        else
            ovText:SetText("")
        end
        ovText:Hide()
        ovFrame:Hide()
    end

    if txt ~= "" then
        if type(_G.MSUF_SetTextIfChanged) == "function" then
            _G.MSUF_SetTextIfChanged(fs, txt)
        else
            fs:SetText(txt)
        end
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
        if type(_G.MSUF_SetTextIfChanged) == "function" then
            _G.MSUF_SetTextIfChanged(fs, "")
        else
            fs:SetText("")
        end
        fs:Hide()
    end

    _MSUF_UpdateStatusIcons(frame)
end

-- Public refresh helper
_G.MSUF_RefreshStatusIndicators = function()
    local frames = _G.MSUF_UnitFrames
    if type(frames) ~= "table" then
        return
    end
    for _, f in pairs(frames) do
        MSUF_UpdateStatusIndicatorForFrame(f)
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

-- ------------------------------------------------------------
-- Shared API: Status Icons Test Mode
-- Used by Frames menus (Player/Target) and the MSUF Edit Mode panel.
-- ------------------------------------------------------------
do
    local function _MSUF_RequestUFUpdate(key, reason)
        local uf = _G and (_G.MSUF_UnitFrames or _G.UnitFrames)
        local fr = (uf and key) and uf[key] or nil
        if fr then
            if type(_G.MSUF_RequestUnitframeUpdate) == "function" then
                _G.MSUF_RequestUnitframeUpdate(fr, true, true, reason or "StatusIconsTestMode")
            elseif type(_G.UpdateSimpleUnitFrame) == "function" then
                _G.UpdateSimpleUnitFrame(fr)
            end
        end
    end

    function _G.MSUF_GetStatusIconsTestMode()
        if type(_G.EnsureDB) == "function" then _G.EnsureDB() end
        local db = _G.MSUF_DB
        local g = (type(db) == "table") and db.general or nil
        return (type(g) == "table" and g.stateIconsTestMode == true) or false
    end

    function _G.MSUF_SetStatusIconsTestMode(enabled, reason)
        if type(_G.EnsureDB) == "function" then _G.EnsureDB() end
        local db = _G.MSUF_DB
        if type(db) ~= "table" then return end
        db.general = (type(db.general) == "table") and db.general or {}
        db.general.stateIconsTestMode = (enabled and true) or false

        if type(_G.MSUF_RefreshStatusIconsOptionsUI) == "function" then
            _G.MSUF_RefreshStatusIconsOptionsUI()
        end

        _MSUF_RequestUFUpdate("player", reason or "StatusIconsTestMode")
        _MSUF_RequestUFUpdate("target", reason or "StatusIconsTestMode")
    end
end
