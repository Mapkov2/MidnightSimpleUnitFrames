-- MSUF_GF_Cleanup.lua
-- Retire/hide cleanup for Group Frame module-owned runtime state.

local _, ns = ...
ns = ns or (_G.MSUF_NS) or {}
_G.MSUF_NS = ns

local GF = ns.GF
if not GF then return end

_G.MSUF_GF_OnFrameRetire = function(f)
    if not f then return end

    if GF.CancelReadyCheckTimer then GF.CancelReadyCheckTimer(f) end
    if GF.StopDispelGlow then GF.StopDispelGlow(f) end
    if GF.ResetOfflineHiddenFrame then GF.ResetOfflineHiddenFrame(f) end
    if GF.HideFrameAuras then GF.HideFrameAuras(f) end
    if GF.RecycleFramePools then GF.RecycleFramePools(f) end
    if GF.UnregisterUnitEvents then GF.UnregisterUnitEvents(f) end
    if GF.ForgetEventFrameRefs then GF.ForgetEventFrameRefs(f) end
    if GF.RetireTooltipState then GF.RetireTooltipState(f) end
    if GF.RetireTextState then GF.RetireTextState(f) end
    if GF.RetireAuraEffectsState then GF.RetireAuraEffectsState(f) end

    local gmap = GF._guidMap
    if gmap then
        for guid, framef in pairs(gmap) do
            if framef == f then gmap[guid] = nil end
        end
    end

    if GF._RetireFromDirty then GF._RetireFromDirty(f) end
end
