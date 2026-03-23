-- ============================================================================
-- MSUF_EM2_Popups.lua
-- Popup router. All popups are Midnight-native (EM2).
-- ============================================================================
local addonName, ns = ...
local EM2 = _G.MSUF_EM2
if not EM2 then return end

local Popups = {}
EM2.Popups = Popups

function Popups.CloseAll()
    if EM2.UnitPopup then EM2.UnitPopup.Close() end
    if EM2.CastPopup then EM2.CastPopup.Close() end
    if EM2.AuraPopup then EM2.AuraPopup.Close() end
    if EM2.GroupPopup then EM2.GroupPopup.Close() end
    if EM2.State then EM2.State.SetPopupOpen(false) end
end

function Popups.Open(key, anchorFrame)
    local cfg = EM2.Registry and EM2.Registry.Get(key)
    local pType = cfg and cfg.popupType

    if not pType then
        -- Fallback: if key is a known unit, open unit popup
        if key == "player" or key == "target" or key == "focus" or key == "targettarget" or key == "pet" or key:match("^boss%d") then
            pType = "unit"
        end
    end

    Popups.CloseAll()

    if pType == "unit" then
        _G.MSUF_EM2_ActiveAuraGroup = nil
        _G.MSUF_EM2_ActiveAuraUnit  = nil
        local unit = key
        if key:match("^boss%d") then unit = "boss" end
        local frame = cfg and cfg.getFrame and cfg.getFrame()
        if EM2.UnitPopup then
            EM2.UnitPopup.Open(unit, frame or anchorFrame)
            if EM2.State then EM2.State.SetPopupOpen(true) end
        end
    elseif pType == "castbar" then
        _G.MSUF_EM2_ActiveAuraGroup = nil
        _G.MSUF_EM2_ActiveAuraUnit  = nil
        local unit = key
        if key:sub(1, 8) == "castbar_" then unit = key:sub(9) end
        local frame = cfg and cfg.getFrame and cfg.getFrame()
        if EM2.CastPopup then EM2.CastPopup.Open(unit, frame or anchorFrame) end
    elseif pType == "aura" then
        local unit = key
        if key:sub(1, 5) == "aura_" then unit = key:sub(6) end
        local frame = cfg and cfg.getFrame and cfg.getFrame()
        if EM2.AuraPopup then EM2.AuraPopup.Open(unit, frame or anchorFrame) end
    elseif pType == "group" then
        local scope = (key == "group_raid") and "raid" or "party"
        if EM2.GroupPopup then EM2.GroupPopup.Open(scope, anchorFrame) end
    end
end

function Popups.IsAnyOpen()
    return (EM2.UnitPopup and EM2.UnitPopup.IsOpen())
        or (EM2.CastPopup and EM2.CastPopup.IsOpen())
        or (EM2.AuraPopup and EM2.AuraPopup.IsOpen())
        or (EM2.GroupPopup and EM2.GroupPopup.IsOpen())
        or false
end
