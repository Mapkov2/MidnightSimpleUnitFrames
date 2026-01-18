-- This file was split out of MidnightSimpleUnitFrames.lua for cleanliness and maintainability.
-- Status Indicator (AFK/DND/DEAD/GHOST/OFFLINE) + lightweight ticker
local addonName, ns = ...
ns = ns or {}

-- Ensure StatusIndicator DB accessor exists even if core refactors change.
-- We keep this in the module (not Main) so the split stays robust.
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
        -- EnsureDB is provided by MSUF_Defaults.lua (loaded before this file in the .toc).
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

-- Keep a global alias used by older callsites.
MSUF_GetStatusIndicatorDB = _G.MSUF_GetStatusIndicatorDB

function MSUF_UpdateStatusIndicatorForFrame(frame)
    if not frame or not frame.statusIndicatorText then
        return
    end
    local unit = frame.unit
    local db = MSUF_GetStatusIndicatorDB()
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
        MSUF_SetTextIfChanged(ovText, "")
        ovText:Hide()
        ovFrame:Hide()
    end
    if txt ~= "" then
        MSUF_SetTextIfChanged(fs, txt)
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
        MSUF_SetTextIfChanged(fs, "")
        fs:Hide()
    end
end
_G.MSUF_RefreshStatusIndicators = function()
    local frames = _G.MSUF_UnitFrames
    if type(frames) ~= "table" then
        return
    end
    for _, f in pairs(frames) do
        MSUF_UpdateStatusIndicatorForFrame(f)
    end
end
---------------------------------------------------------------------------
---------------------------------------------------------------------------
do
    -- Fallback ticker removed: status indicators are fully event-driven now.
    -- Keep a compatibility stub because older code may call this helper.
    local function MSUF_StopStatusIndicatorTicker()
        local t = _G.MSUF_StatusIndicatorTicker
        if t and t.Cancel then
            t:Cancel()
        end
        _G.MSUF_StatusIndicatorTicker = nil
    end

    _G.MSUF_EnsureStatusIndicatorTicker = function()
        MSUF_StopStatusIndicatorTicker()
    end

    MSUF_StopStatusIndicatorTicker()
end
