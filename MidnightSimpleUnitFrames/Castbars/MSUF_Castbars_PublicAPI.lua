--- Namespace ownership and the complete castbar compatibility boundary.
local _, MSUF = ...
local Castbars = {}
MSUF.Castbars = Castbars
Castbars.Anchors = {}
Castbars.Backend = {}
Castbars.Bridge = {}
Castbars.ChannelTicks = {}
Castbars.Config = {}
Castbars.Core = {}
Castbars.Driver = {}
Castbars.Empower = {}
Castbars.Engine = {}
Castbars.FocusDriver = {}
Castbars.FocusKick = {}
Castbars.Frames = {}
Castbars.GCD = {}
Castbars.KickReady = {}
Castbars.Manager = {}
Castbars.Player = {}
Castbars.PoolPreviews = {}
Castbars.Pools = {}
Castbars.PreviewEdit = {}
Castbars.Previews = {}
Castbars.PublicAPI = {}
Castbars.Rounded = {}
Castbars.Runtime = {}
Castbars.Style = {}
Castbars.Utils = {}
Castbars.Visuals = {}

local Frames = Castbars.Frames
local indexed = { boss = {}, arena = {}, bossPreview = {}, arenaPreview = {} }
Frames.indexed = indexed

function Frames.Get(kind, index)
    local pool = indexed[kind]
    if pool then return pool[index or 1] end
    return Frames[kind]
end

function Frames.Register(kind, index, frame)
    local pool = indexed[kind]
    if pool then
        pool[index or 1] = frame
    else
        Frames[kind] = frame
    end
    return frame
end

local ExportPublic = MSUF.ExportPublic
local publishers = {
    MSUF_BossTestMode = function(v) ExportPublic("MSUF_BossTestMode", v) end,
    MSUF_ApplyAllCastbarsAndSync = function(v) ExportPublic("MSUF_ApplyAllCastbarsAndSync", v) end,
    MSUF_ApplyArenaCastbarPositionSetting = function(v) ExportPublic("MSUF_ApplyArenaCastbarPositionSetting", v) end,
    MSUF_ApplyBossCastbarPositionSetting = function(v) ExportPublic("MSUF_ApplyBossCastbarPositionSetting", v) end,
    MSUF_ApplyCastbarGlowFade = function(v) ExportPublic("MSUF_ApplyCastbarGlowFade", v) end,
    MSUF_ApplyCastbarPagePreviewState = function(v) ExportPublic("MSUF_ApplyCastbarPagePreviewState", v) end,
    MSUF_ApplyCastbarUnitAndSync = function(v) ExportPublic("MSUF_ApplyCastbarUnitAndSync", v) end,
    MSUF_ApplyCastbarVisualsForUnit = function(v) ExportPublic("MSUF_ApplyCastbarVisualsForUnit", v) end,
    MSUF_ApplyPlayerChannelTickMarkers = function(v) ExportPublic("MSUF_ApplyPlayerChannelTickMarkers", v) end,
    MSUF_ArenaCastbars = function(v) ExportPublic("MSUF_ArenaCastbars", v) end,
    MSUF_BUILTIN_BAR_TEXTURES = function(v) ExportPublic("MSUF_BUILTIN_BAR_TEXTURES", v) end,
    MSUF_BeginBossCastbarPreviewBatch = function(v) ExportPublic("MSUF_BeginBossCastbarPreviewBatch", v) end,
    MSUF_BossCastbars = function(v) ExportPublic("MSUF_BossCastbars", v) end,
    MSUF_BumpCastbarStyleRevision = function(v) ExportPublic("MSUF_BumpCastbarStyleRevision", v) end,
    MSUF_CB_ApplyTexts = function(v) ExportPublic("MSUF_CB_ApplyTexts", v) end,
    MSUF_CastbarStyleRevision = function(v) ExportPublic("MSUF_CastbarStyleRevision", v) end,
    MSUF_Castbars_OnSettingsChanged = function(v) ExportPublic("MSUF_Castbars_OnSettingsChanged", v) end,
    MSUF_ClearResolvedStatusbarTextureCache = function(v) ExportPublic("MSUF_ClearResolvedStatusbarTextureCache", v) end,
    MSUF_EndBossCastbarPreviewBatch = function(v) ExportPublic("MSUF_EndBossCastbarPreviewBatch", v) end,
    MSUF_FocusKickDriver_ForceUpdate = function(v) ExportPublic("MSUF_FocusKickDriver_ForceUpdate", v) end,
    MSUF_FocusKick_ApplyTimeTextFont = function(v) ExportPublic("MSUF_FocusKick_ApplyTimeTextFont", v) end,
    MSUF_FocusKick_IsPreviewEnabled = function(v) ExportPublic("MSUF_FocusKick_IsPreviewEnabled", v) end,
    MSUF_FocusKick_SetPreviewEnabled = function(v) ExportPublic("MSUF_FocusKick_SetPreviewEnabled", v) end,
    MSUF_GCDBar_IsSupported = function(v) ExportPublic("MSUF_GCDBar_IsSupported", v) end,
    MSUF_GCDBar_RefreshLayout = function(v) ExportPublic("MSUF_GCDBar_RefreshLayout", v) end,
    MSUF_GetAnchorFrame = function(v) ExportPublic("MSUF_GetAnchorFrame", v) end,
    MSUF_GetBarBackgroundTexture = function(v) ExportPublic("MSUF_GetBarBackgroundTexture", v) end,
    MSUF_GetBarTexture = function(v) ExportPublic("MSUF_GetBarTexture", v) end,
    MSUF_GetCastbarBackend = function(v) ExportPublic("MSUF_GetCastbarBackend", v) end,
    MSUF_GetCastbarBackgroundTexture = function(v) ExportPublic("MSUF_GetCastbarBackgroundTexture", v) end,
    MSUF_GetCastbarDefaultOffsets = function(v) ExportPublic("MSUF_GetCastbarDefaultOffsets", v) end,
    MSUF_GetCastbarDesiredSize = function(v) ExportPublic("MSUF_GetCastbarDesiredSize", v) end,
    MSUF_GetCastbarFrameLevelOffset = function(v) ExportPublic("MSUF_GetCastbarFrameLevelOffset", v) end,
    MSUF_GetCastbarPrefix = function(v) ExportPublic("MSUF_GetCastbarPrefix", v) end,
    MSUF_GetCastbarReverseFillForFrame = function(v) ExportPublic("MSUF_GetCastbarReverseFillForFrame", v) end,
    MSUF_GetCastbarTexture = function(v) ExportPublic("MSUF_GetCastbarTexture", v) end,
    MSUF_GetCastbarWidthSourceKey = function(v) ExportPublic("MSUF_GetCastbarWidthSourceKey", v) end,
    MSUF_GetEmpowerStageBlinkTime = function(v) ExportPublic("MSUF_GetEmpowerStageBlinkTime", v) end,
    MSUF_GetFontFlags = function(v) ExportPublic("MSUF_GetFontFlags", v) end,
    MSUF_GetFontPath = function(v) ExportPublic("MSUF_GetFontPath", v) end,
    MSUF_GetGlobalFontSettings = function(v) ExportPublic("MSUF_GetGlobalFontSettings", v) end,
    MSUF_HideAllCastbarPreviews = function(v) ExportPublic("MSUF_HideAllCastbarPreviews", v) end,
    MSUF_IsEmpowerStageBlinkEnabled = function(v) ExportPublic("MSUF_IsEmpowerStageBlinkEnabled", v) end,
    MSUF_KickReady_ApplyLayout = function(v) ExportPublic("MSUF_KickReady_ApplyLayout", v) end,
    MSUF_KickReady_EvaluateRGBA = function(v) ExportPublic("MSUF_KickReady_EvaluateRGBA", v) end,
    MSUF_KickReady_GetReadyBoolForTint = function(v) ExportPublic("MSUF_KickReady_GetReadyBoolForTint", v) end,
    MSUF_KickReady_GetSpellID = function(v) ExportPublic("MSUF_KickReady_GetSpellID", v) end,
    MSUF_KickReady_Init = function(v) ExportPublic("MSUF_KickReady_Init", v) end,
    MSUF_KickReady_IsReady = function(v) ExportPublic("MSUF_KickReady_IsReady", v) end,
    MSUF_KickReady_NotifySettings = function(v) ExportPublic("MSUF_KickReady_NotifySettings", v) end,
    MSUF_KickReady_RefreshAll = function(v) ExportPublic("MSUF_KickReady_RefreshAll", v) end,
    MSUF_KickReady_RefreshFrame = function(v) ExportPublic("MSUF_KickReady_RefreshFrame", v) end,
    MSUF_KickReady_RefreshOutline = function(v) ExportPublic("MSUF_KickReady_RefreshOutline", v) end,
    MSUF_KickReady_SelectColor = function(v) ExportPublic("MSUF_KickReady_SelectColor", v) end,
    MSUF_NormalizeCastbarBackend = function(v) ExportPublic("MSUF_NormalizeCastbarBackend", v) end,
    MSUF_NormalizeCastbarBackendForUnit = function(v) ExportPublic("MSUF_NormalizeCastbarBackendForUnit", v) end,
    MSUF_NormalizeCastbarIconPosition = function(v) ExportPublic("MSUF_NormalizeCastbarIconPosition", v) end,
    MSUF_NormalizeCastbarTextJustify = function(v) ExportPublic("MSUF_NormalizeCastbarTextJustify", v) end,
    MSUF_NormalizeCastbarTextPosition = function(v) ExportPublic("MSUF_NormalizeCastbarTextPosition", v) end,
    MSUF_NormalizeCastbarTruncate = function(v) ExportPublic("MSUF_NormalizeCastbarTruncate", v) end,
    MSUF_NormalizeCastbarWidthSource = function(v) ExportPublic("MSUF_NormalizeCastbarWidthSource", v) end,
    MSUF_NormalizePlayerCastbarWidthSource = function(v) ExportPublic("MSUF_NormalizePlayerCastbarWidthSource", v) end,
    MSUF_PlayerCastbar_UpdateLatencyZone = function(v) ExportPublic("MSUF_PlayerCastbar_UpdateLatencyZone", v) end,
    MSUF_PositionCastbarPreviewUnit = function(v) ExportPublic("MSUF_PositionCastbarPreviewUnit", v) end,
    MSUF_ReanchorArenaCastBar = function(v) ExportPublic("MSUF_ReanchorArenaCastBar", v) end,
    MSUF_ReanchorBossCastBar = function(v) ExportPublic("MSUF_ReanchorBossCastBar", v) end,
    MSUF_ReanchorFocusCastBar = function(v) ExportPublic("MSUF_ReanchorFocusCastBar", v) end,
    MSUF_ReanchorPlayerCastBar = function(v) ExportPublic("MSUF_ReanchorPlayerCastBar", v) end,
    MSUF_ReanchorTargetCastBar = function(v) ExportPublic("MSUF_ReanchorTargetCastBar", v) end,
    MSUF_RefreshAllCastTargetTextColors = function(v) ExportPublic("MSUF_RefreshAllCastTargetTextColors", v) end,
    MSUF_RefreshCastbarCooldownWidthSource = function(v) ExportPublic("MSUF_RefreshCastbarCooldownWidthSource", v) end,
    MSUF_ResetCastbarGlowFade = function(v) ExportPublic("MSUF_ResetCastbarGlowFade", v) end,
    MSUF_ResolveCastbarColors = function(v) ExportPublic("MSUF_ResolveCastbarColors", v) end,
    MSUF_ResolveInterruptFeedbackCastColor = function(v) ExportPublic("MSUF_ResolveInterruptFeedbackCastColor", v) end,
    MSUF_ResolveInterruptUnavailableCastColor = function(v) ExportPublic("MSUF_ResolveInterruptUnavailableCastColor", v) end,
    MSUF_ResolveStatusbarTextureKey = function(v) ExportPublic("MSUF_ResolveStatusbarTextureKey", v) end,
    MSUF_RoundedCastbar_RenderPreview = function(v) ExportPublic("MSUF_RoundedCastbar_RenderPreview", v) end,
    MSUF_SetArenaCastbarTestMode = function(v) ExportPublic("MSUF_SetArenaCastbarTestMode", v) end,
    MSUF_SetBossCastbarTestMode = function(v) ExportPublic("MSUF_SetBossCastbarTestMode", v) end,
    MSUF_SetCastbarBackend = function(v) ExportPublic("MSUF_SetCastbarBackend", v) end,
    MSUF_SetFocusCastbarTestMode = function(v) ExportPublic("MSUF_SetFocusCastbarTestMode", v) end,
    MSUF_SetGCDBarEnabled = function(v) ExportPublic("MSUF_SetGCDBarEnabled", v) end,
    MSUF_SetPlayerCastbarTestMode = function(v) ExportPublic("MSUF_SetPlayerCastbarTestMode", v) end,
    MSUF_SetTargetCastbarTestMode = function(v) ExportPublic("MSUF_SetTargetCastbarTestMode", v) end,
    MSUF_ShortenCastbarSpellName = function(v) ExportPublic("MSUF_ShortenCastbarSpellName", v) end,
    MSUF_ShouldUseMSUFCastbar = function(v) ExportPublic("MSUF_ShouldUseMSUFCastbar", v) end,
    MSUF_SuppressBlizzardPlayerCastbars = function(v) ExportPublic("MSUF_SuppressBlizzardPlayerCastbars", v) end,
    MSUF_UpdateArenaCastbarPreview = function(v) ExportPublic("MSUF_UpdateArenaCastbarPreview", v) end,
    MSUF_UpdateBossCastbarPreview = function(v) ExportPublic("MSUF_UpdateBossCastbarPreview", v) end,
    MSUF_UpdateCastbarTextures = function(v) ExportPublic("MSUF_UpdateCastbarTextures", v) end,
    MSUF_UpdateCastbarTextures_Immediate = function(v) ExportPublic("MSUF_UpdateCastbarTextures_Immediate", v) end,
    MSUF_UpdateCastbarVisuals = function(v) ExportPublic("MSUF_UpdateCastbarVisuals", v) end,
    MSUF_UpdateCastbarVisuals_Immediate = function(v) ExportPublic("MSUF_UpdateCastbarVisuals_Immediate", v) end,
    MSUF_UpdateCastbarWidthSourceSync = function(v) ExportPublic("MSUF_UpdateCastbarWidthSourceSync", v) end,
    MSUF_UpdateFocusKickIconOptions = function(v) ExportPublic("MSUF_UpdateFocusKickIconOptions", v) end,
    MSUF_UpdatePlayerCastbarPreview = function(v) ExportPublic("MSUF_UpdatePlayerCastbarPreview", v) end,
}

function Castbars.PublicAPI.Publish(name, v)
    local publish = publishers[name]
    if publish then publish(v) end
    return v
end
