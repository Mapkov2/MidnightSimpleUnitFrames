local addonName, ns = ...
ns = ns or _G.MSUF_NS or {}
_G.MSUF_NS = ns

local function InCombat()
    return _G.MSUF_InCombat == true
end

_G.MSUF_UnitFrameApplyState = _G.MSUF_UnitFrameApplyState or { dirty = {}, queued = false }
_G.MSUF_ApplyCommitState = _G.MSUF_ApplyCommitState or {
    pending = false,
    queued = false,
    fontKey = nil,
    fonts = false,
    bars = false,
    castbars = false,
    tickers = false,
    bossPreview = false,
}

function MSUF_MarkUnitFrameDirty(key)
    local st = _G.MSUF_UnitFrameApplyState
    if not (st and st.dirty and key) then return end
    st.dirty[key] = true
end
_G.MSUF_MarkUnitFrameDirty = MSUF_MarkUnitFrameDirty

function MSUF_ApplyDirtyUnitFrames()
    local st = _G.MSUF_UnitFrameApplyState
    if not (st and st.dirty) then return end
    if InCombat() then
        st.queued = true
        return
    end
    for key in pairs(st.dirty) do
        if type(_G.MSUF_ApplyUnitFrameKey_Immediate) == "function" then
            _G.MSUF_ApplyUnitFrameKey_Immediate(key)
        end
        st.dirty[key] = nil
    end
    st.queued = false
end
_G.MSUF_ApplyDirtyUnitFrames = MSUF_ApplyDirtyUnitFrames

function MSUF_OnRegenEnabled_ApplyDirty()
    local st = _G.MSUF_UnitFrameApplyState
    if st and st.queued then
        MSUF_ApplyDirtyUnitFrames()
    end
    if type(_G.MSUF_EventBus_Unregister) == "function" then
        _G.MSUF_EventBus_Unregister("PLAYER_REGEN_ENABLED", "MSUF_APPLY_DIRTY")
    end
end
_G.MSUF_OnRegenEnabled_ApplyDirty = MSUF_OnRegenEnabled_ApplyDirty

local function MSUF_CommitApplyDirty_Scheduled()
    local st = _G.MSUF_ApplyCommitState
    if st then st.pending = false end
    MSUF_CommitApplyDirty()
end

function MSUF_ScheduleApplyCommit()
    local st = _G.MSUF_ApplyCommitState
    if not st or st.pending then return end
    st.pending = true
    C_Timer.After(0, MSUF_CommitApplyDirty_Scheduled)
end
_G.MSUF_ScheduleApplyCommit = MSUF_ScheduleApplyCommit

function MSUF_OnRegenEnabled_ApplyCommit()
    local st = _G.MSUF_ApplyCommitState
    if st and st.queued then
        st.queued = false
        MSUF_CommitApplyDirty()
    end
    if type(_G.MSUF_EventBus_Unregister) == "function" then
        _G.MSUF_EventBus_Unregister("PLAYER_REGEN_ENABLED", "MSUF_APPLY_COMMIT")
    end
end
_G.MSUF_OnRegenEnabled_ApplyCommit = MSUF_OnRegenEnabled_ApplyCommit

function ApplySettingsForKey(key)
    if not key then return end
    MSUF_MarkUnitFrameDirty(key)
    local st = _G.MSUF_ApplyCommitState
    if st and key == "boss" then
        st.bossPreview = true
    end
    MSUF_ScheduleApplyCommit()
end
_G.ApplySettingsForKey = ApplySettingsForKey

function ApplyAllSettings()
    local st = _G.MSUF_ApplyCommitState
    if not st then return end
    MSUF_MarkUnitFrameDirty("player")
    MSUF_MarkUnitFrameDirty("target")
    MSUF_MarkUnitFrameDirty("focus")
    MSUF_MarkUnitFrameDirty("targettarget")
    MSUF_MarkUnitFrameDirty("pet")
    MSUF_MarkUnitFrameDirty("boss")
    st.fonts = true
    st.bars = true
    st.castbars = true
    st.tickers = true
    st.bossPreview = true
    MSUF_ScheduleApplyCommit()
end
_G.ApplyAllSettings = ApplyAllSettings

if not _G.MSUF_ApplySettingsForKey_Immediate then
    _G.MSUF_ApplySettingsForKey_Immediate = function(key)
        if not key then return end
        MSUF_MarkUnitFrameDirty(key)
        if InCombat() then
            local stUF = _G.MSUF_UnitFrameApplyState
            if stUF then stUF.queued = true end
            if type(_G.MSUF_EventBus_Register) == "function" then
                _G.MSUF_EventBus_Register("PLAYER_REGEN_ENABLED", "MSUF_APPLY_DIRTY", MSUF_OnRegenEnabled_ApplyDirty)
            end
            return
        end
        if type(_G.MSUF_ApplyUnitFrameKey_Immediate) == "function" then
            _G.MSUF_ApplyUnitFrameKey_Immediate(key)
        end
        local stUF = _G.MSUF_UnitFrameApplyState
        if stUF and stUF.dirty then stUF.dirty[key] = nil end
    end
end

if not _G.MSUF_ApplyAllSettings_Immediate then
    _G.MSUF_ApplyAllSettings_Immediate = function()
        if not _G.MSUF_DB and type(_G.EnsureDB) == "function" then _G.EnsureDB() end
        if type(_G.MSUF_UFCore_NotifyConfigChanged) == "function" then
            _G.MSUF_UFCore_NotifyConfigChanged(nil, false, true, "ApplyAllSettings_Immediate")
        end
        if type(_G.MSUF_ApplyUnitFrameKey_Immediate) == "function" then
            _G.MSUF_ApplyUnitFrameKey_Immediate("player")
            _G.MSUF_ApplyUnitFrameKey_Immediate("target")
            _G.MSUF_ApplyUnitFrameKey_Immediate("focus")
            _G.MSUF_ApplyUnitFrameKey_Immediate("targettarget")
            _G.MSUF_ApplyUnitFrameKey_Immediate("pet")
            _G.MSUF_ApplyUnitFrameKey_Immediate("boss")
        end
        local fnFonts = _G.MSUF_UpdateAllFonts_Immediate or _G.MSUF_UpdateAllFonts
        if type(fnFonts) == "function" then fnFonts() end
        local fnBars = _G.MSUF_UpdateAllBarTextures_Immediate or _G.MSUF_UpdateAllBarTextures
        if type(fnBars) == "function" then fnBars() end
        local fnCBTex = _G.MSUF_UpdateCastbarTextures_Immediate or _G.MSUF_UpdateCastbarTextures
        if type(fnCBTex) == "function" then fnCBTex() end
        local fnCBVis = _G.MSUF_UpdateCastbarVisuals_Immediate or _G.MSUF_UpdateCastbarVisuals
        if type(fnCBVis) == "function" then fnCBVis() end
        if type(_G.MSUF_SyncBossUnitframePreviewWithUnitEdit) == "function" then
            _G.MSUF_FastCall(_G.MSUF_SyncBossUnitframePreviewWithUnitEdit)
        end
        if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
            _G.MSUF_FastCall(_G.MSUF_UpdateBossCastbarPreview)
        end
        if type(_G.MSUF_EnsureStatusIndicatorTicker) == "function" then _G.MSUF_EnsureStatusIndicatorTicker() end
        if type(_G.MSUF_EnsureToTFallbackTicker) == "function" then _G.MSUF_EnsureToTFallbackTicker() end
        if type(_G.MSUF_RefreshSelfHealPredUnitEvent) == "function" then _G.MSUF_RefreshSelfHealPredUnitEvent() end
        if _G.MSUF_UnitFrameApplyState and _G.MSUF_UnitFrameApplyState.dirty then
            for k in pairs(_G.MSUF_UnitFrameApplyState.dirty) do
                _G.MSUF_UnitFrameApplyState.dirty[k] = nil
            end
            _G.MSUF_UnitFrameApplyState.queued = false
        end
        if type(_G.MSUF_EventBus_Unregister) == "function" then
            _G.MSUF_EventBus_Unregister("PLAYER_REGEN_ENABLED", "MSUF_APPLY_DIRTY")
        end
    end
end

function MSUF_CommitApplyDirty()
    local st = _G.MSUF_ApplyCommitState
    if not st then return end
    if InCombat() then
        st.queued = true
        if type(_G.MSUF_EventBus_Register) == "function" then
            _G.MSUF_EventBus_Register("PLAYER_REGEN_ENABLED", "MSUF_APPLY_COMMIT", MSUF_OnRegenEnabled_ApplyCommit)
        end
        return
    end
    MSUF_ApplyDirtyUnitFrames()
    if st.fonts then
        local fn = _G.MSUF_UpdateAllFonts_Immediate or _G.MSUF_UpdateAllFonts
        if type(fn) == "function" then
            local fk = st.fontKey
            if fk and fk ~= false then fn(fk) else fn() end
        end
    end
    if st.bars then
        local fn = _G.MSUF_UpdateAllBarTextures_Immediate or _G.MSUF_UpdateAllBarTextures
        if type(fn) == "function" then fn() end
    end
    if st.castbars then
        local fnTex = _G.MSUF_UpdateCastbarTextures_Immediate or _G.MSUF_UpdateCastbarTextures
        if type(fnTex) == "function" then fnTex() end
        local fnVis = _G.MSUF_UpdateCastbarVisuals_Immediate or _G.MSUF_UpdateCastbarVisuals
        if type(fnVis) == "function" then fnVis() end
    end
    if st.bossPreview then
        if type(_G.MSUF_SyncBossUnitframePreviewWithUnitEdit) == "function" then _G.MSUF_FastCall(_G.MSUF_SyncBossUnitframePreviewWithUnitEdit) end
        if type(_G.MSUF_ApplyBossCastbarPositionSetting) == "function" then _G.MSUF_FastCall(_G.MSUF_ApplyBossCastbarPositionSetting) end
        if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then _G.MSUF_FastCall(_G.MSUF_UpdateBossCastbarPreview) end
        if type(_G.MSUF_SyncCastbarPositionPopup) == "function" then _G.MSUF_FastCall(_G.MSUF_SyncCastbarPositionPopup, "boss") end
    end
    if st.tickers then
        if type(_G.MSUF_EnsureStatusIndicatorTicker) == "function" then _G.MSUF_EnsureStatusIndicatorTicker() end
        if type(_G.MSUF_EnsureToTFallbackTicker) == "function" then _G.MSUF_EnsureToTFallbackTicker() end
    end
    if type(_G.MSUF_RefreshSelfHealPredUnitEvent) == "function" then _G.MSUF_RefreshSelfHealPredUnitEvent() end
    st.fonts = false
    st.fontKey = nil
    st.bars = false
    st.castbars = false
    st.tickers = false
    st.bossPreview = false
    st.queued = false
    if type(_G.MSUF_EventBus_Unregister) == "function" then
        _G.MSUF_EventBus_Unregister("PLAYER_REGEN_ENABLED", "MSUF_APPLY_COMMIT")
    end
end
_G.MSUF_CommitApplyDirty = MSUF_CommitApplyDirty
