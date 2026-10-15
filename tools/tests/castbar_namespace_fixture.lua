-- Partial castbar worlds bind their old fixture handles to the real namespace.
-- Client boot/public-export smokes never use this adapter.
local Fixture = {}
local slots = {
    { "MSUF_FocusKickIcon", "Frames", "focusKick" },
    { "MSUF_DetachedGCDBar", "Frames", "gcd" },
    { "MSUF_ApplyAllCastbarsAndSync", "Core", "ApplyAllCastbarsAndSync" },
    { "MSUF_ApplyArenaCastbarPositionSetting", "Pools", "ApplyArenaCastbarPositionSetting" },
    { "MSUF_ApplyArenaCastbarsEnabled", "Pools", "ApplyArenaCastbarsEnabled" },
    { "MSUF_ApplyBossCastbarPositionSetting", "Pools", "ApplyBossCastbarPositionSetting" },
    { "MSUF_ApplyBossCastbarsEnabled", "Pools", "ApplyBossCastbarsEnabled" },
    { "MSUF_ApplyCastTargetTextColor", "Driver", "ApplyCastTargetTextColor" },
    { "MSUF_ApplyCastbarDetailLayout", "Visuals", "ApplyCastbarDetailLayout" },
    { "MSUF_ApplyCastbarEffectiveSizeUnit", "Anchors", "ApplyCastbarEffectiveSizeUnit" },
    { "MSUF_ApplyCastbarFrameLayer", "Core", "ApplyCastbarFrameLayer" },
    { "MSUF_ApplyCastbarGlowFade", "Utils", "ApplyCastbarGlowFade" },
    { "MSUF_ApplyCastbarOutline", "Style", "ApplyCastbarOutline" },
    { "MSUF_ApplyCastbarPagePreviewState", "Previews", "ApplyCastbarPagePreviewState" },
    { "MSUF_ApplyCastbarSparkVisual", "Core", "ApplyCastbarSparkVisual" },
    { "MSUF_ApplyCastbarTimerDirection", "Runtime", "ApplyCastbarTimerDirection" },
    { "MSUF_ApplyCastbarUnitAndSync", "Core", "ApplyCastbarUnitAndSync" },
    { "MSUF_ApplyCastbarVisualsForUnit", "Core", "ApplyCastbarVisualsForUnit" },
    { "MSUF_ApplyInterruptBarVisuals", "Runtime", "ApplyInterruptBarVisuals" },
    { "MSUF_ApplyPlayerCastbarSizeAndLayout", "Anchors", "ApplyPlayerCastbarSizeAndLayout" },
    { "MSUF_ApplyPlayerChannelTickMarkers", "ChannelTicks", "ApplyPlayerChannelTickMarkers" },
    { "MSUF_ApplyTimerAndFill", "Runtime", "ApplyTimerAndFill" },
    { "MSUF_AreAnyCastbarsEnabled", "Bridge", "AreAnyCastbarsEnabled" },
    { "MSUF_ArenaCastbarPreview", "Frames", "arenaPreview" },
    { "MSUF_ArenaCastbar_Stop", "Pools", "ArenaCastbar_Stop" },
    { "MSUF_ArenaCastbars", "Pools", "ArenaCastbars" },
    { "MSUF_ArenaCastbars_SyncLifecycle", "Pools", "ArenaCastbars_SyncLifecycle" },
    { "MSUF_BUILTIN_BAR_TEXTURES", "Core", "BUILTIN_BAR_TEXTURES" },
    { "MSUF_BeginBossCastbarPreviewBatch", "Previews", "BeginBossCastbarPreviewBatch" },
    { "MSUF_BlinkEmpowerTick", "Empower", "BlinkEmpowerTick" },
    { "MSUF_BossCastbarPreview", "Frames", "bossPreview" },
    { "MSUF_BossCastbar_Stop", "Pools", "BossCastbar_Stop" },
    { "MSUF_BossCastbars", "Pools", "BossCastbars" },
    { "MSUF_BossCastbars_SyncLifecycle", "Pools", "BossCastbars_SyncLifecycle" },
    { "MSUF_BossPreviewEventDriver", "Previews", "BossPreviewEventDriver" },
    { "MSUF_BuildCastState", "Engine", "BuildCastState" },
    { "MSUF_BuildCastbarFrameElements", "Frames", "BuildCastbarFrameElements" },
    { "MSUF_BumpCastTimeRev", "Manager", "BumpCastTimeRev" },
    { "MSUF_BumpCastbarStyleRev", "Manager", "BumpCastbarStyleRev" },
    { "MSUF_BumpCastbarStyleRevision", "Core", "BumpCastbarStyleRevision" },
    { "MSUF_CB_ApplyColor", "Utils", "CB_ApplyColor" },
    { "MSUF_CB_ApplyTexts", "Utils", "CB_ApplyTexts" },
    { "MSUF_CB_ResetStateOnStop", "Runtime", "CB_ResetStateOnStop" },
    { "MSUF_CastTimeUnitKey", "Utils", "CastTimeUnitKey" },
    { "MSUF_CastbarBackgroundTextureCache", "Core", "CastbarBackgroundTextureCache" },
    { "MSUF_CastbarDriver_ApplyBackendState", "Driver", "CastbarDriver_ApplyBackendState" },
    { "MSUF_CastbarDriver_SyncLifecycle", "Driver", "CastbarDriver_SyncLifecycle" },
    { "MSUF_CastbarFrameInset", "Anchors", "CastbarFrameInset" },
    { "MSUF_CastbarManager", "Manager", "CastbarManager" },
    { "MSUF_CastbarPreviewPulseTimers", "PreviewEdit", "CastbarPreviewPulseTimers" },
    { "MSUF_CastbarStyleRevision", "Config", "textureRevision" },
    { "MSUF_CastbarTextureCache", "Core", "CastbarTextureCache" },
    { "MSUF_CastbarUnitInfo", "Core", "CastbarUnitInfo" },
    { "MSUF_Castbar_ApplyActiveDuration", "Runtime", "Castbar_ApplyActiveDuration" },
    { "MSUF_Castbar_ApplyNonInterruptibleTint", "Utils", "Castbar_ApplyNonInterruptibleTint" },
    { "MSUF_Castbar_DisableFrameOnUpdate", "Utils", "Castbar_DisableFrameOnUpdate" },
    { "MSUF_Castbar_GetInterruptUnavailableTintArgs", "Utils", "Castbar_GetInterruptUnavailableTintArgs" },
    { "MSUF_Castbar_PlainNumber", "Utils", "Castbar_PlainNumber" },
    { "MSUF_Castbar_ResolveInterruptLabel", "Driver", "Castbar_ResolveInterruptLabel" },
    { "MSUF_Castbar_ResolvePushbackMS", "Utils", "Castbar_ResolvePushbackMS" },
    { "MSUF_Castbar_SetLifecycleActive", "Driver", "Castbar_SetLifecycleActive" },
    { "MSUF_Castbar_ShouldUseInterruptUnavailableColor", "Utils", "Castbar_ShouldUseInterruptUnavailableColor" },
    { "MSUF_Castbar_SyncTimeTextFollower", "Manager", "Castbar_SyncTimeTextFollower" },
    { "MSUF_Castbars_ForceHideAll", "Bridge", "Castbars_ForceHideAll" },
    { "MSUF_Castbars_OnSettingsChanged", "Bridge", "Castbars_OnSettingsChanged" },
    { "MSUF_Castbars_RunNextFrame", "Bridge", "Castbars_RunNextFrame" },
    { "MSUF_ClassicCastbar_ApplySparkVisual", "Style", "ClassicCastbar_ApplySparkVisual" },
    { "MSUF_ClassicCastbar_GetOutlineInset", "Style", "ClassicCastbar_GetOutlineInset" },
    { "MSUF_ClearCastbarTimerDuration", "Runtime", "ClearCastbarTimerDuration" },
    { "MSUF_ClearEmpowerState", "Utils", "ClearEmpowerState" },
    { "MSUF_ClearResolvedStatusbarTextureCache", "Core", "ClearResolvedStatusbarTextureCache" },
    { "MSUF_CreateCastBar", "Driver", "CreateCastBar" },
    { "MSUF_CreateCastbarPreviewFrame", "Frames", "CreateCastbarPreviewFrame" },
    { "MSUF_EndBossCastbarPreviewBatch", "Previews", "EndBossCastbarPreviewBatch" },
    { "MSUF_EnsureCastbarGeneralDB", "Utils", "EnsureCastbarGeneralDB" },
    { "MSUF_EnsureDBLazy", "Utils", "EnsureDBLazy" },
    { "MSUF_FocusCastBar", "Frames", "focus" },
    { "MSUF_FocusCastbar", "Frames", "focus" },
    { "MSUF_FocusCastbarPreview", "Frames", "focusPreview" },
    { "MSUF_FocusKickDriver_ForceUpdate", "FocusDriver", "FocusKickDriver_ForceUpdate" },
    { "MSUF_FocusKickUseEngineDriver", "FocusDriver", "FocusKickUseEngineDriver" },
    { "MSUF_FocusKick_ApplyCastState", "FocusKick", "FocusKick_ApplyCastState" },
    { "MSUF_FocusKick_ApplyTimeTextFont", "FocusKick", "FocusKick_ApplyTimeTextFont" },
    { "MSUF_FocusKick_IsPreviewEnabled", "FocusKick", "FocusKick_IsPreviewEnabled" },
    { "MSUF_FocusKick_PlayInterruptFeedback", "FocusKick", "FocusKick_PlayInterruptFeedback" },
    { "MSUF_FocusKick_RefreshReadyColor", "FocusKick", "FocusKick_RefreshReadyColor" },
    { "MSUF_FocusKick_SetPreviewEnabled", "FocusKick", "FocusKick_SetPreviewEnabled" },
    { "MSUF_GCDBar_IsSupported", "GCD", "GCDBar_IsSupported" },
    { "MSUF_GCDBar_RefreshLayout", "GCD", "GCDBar_RefreshLayout" },
    { "MSUF_GCDBar_SyncRegistration", "GCD", "GCDBar_SyncRegistration" },
    { "MSUF_GetAnchorFrame", "Utils", "GetAnchorFrame" },
    { "MSUF_GetBarBackgroundTexture", "Core", "GetBarBackgroundTexture" },
    { "MSUF_GetBarTexture", "Core", "GetBarTexture" },
    { "MSUF_GetCastbarAutoAnchorOffsetX", "Anchors", "GetCastbarAutoAnchorOffsetX" },
    { "MSUF_GetCastbarBackend", "Backend", "GetCastbarBackend" },
    { "MSUF_GetCastbarBackgroundTexture", "Core", "GetCastbarBackgroundTexture" },
    { "MSUF_GetCastbarCountsDown", "Utils", "GetCastbarCountsDown" },
    { "MSUF_GetCastbarDefaultOffsets", "Core", "GetCastbarDefaultOffsets" },
    { "MSUF_GetCastbarDesiredSize", "Anchors", "GetCastbarDesiredSize" },
    { "MSUF_GetCastbarEngine", "Engine", "GetCastbarEngine" },
    { "MSUF_GetCastbarFrameLevelOffset", "Core", "GetCastbarFrameLevelOffset" },
    { "MSUF_GetCastbarOutlineInset", "Style", "GetCastbarOutlineInset" },
    { "MSUF_GetCastbarPrefix", "Core", "GetCastbarPrefix" },
    { "MSUF_GetCastbarReverseFillForFrame", "Utils", "GetCastbarReverseFillForFrame" },
    { "MSUF_GetCastbarSpellNameShorteningConfig", "Utils", "GetCastbarSpellNameShorteningConfig" },
    { "MSUF_GetCastbarTexture", "Core", "GetCastbarTexture" },
    { "MSUF_GetCastbarUnitFromFrame", "Core", "GetCastbarUnitFromFrame" },
    { "MSUF_GetCastbarUnitframeBottomInset", "Anchors", "GetCastbarUnitframeBottomInset" },
    { "MSUF_GetCastbarUnitframeWidthSource", "Anchors", "GetCastbarUnitframeWidthSource" },
    { "MSUF_GetCastbarWidthSourceKey", "Anchors", "GetCastbarWidthSourceKey" },
    { "MSUF_GetEmpowerStageBlinkTime", "Empower", "GetEmpowerStageBlinkTime" },
    { "MSUF_GetFontFlags", "Core", "GetFontFlags" },
    { "MSUF_GetFontPath", "Core", "GetFontPath" },
    { "MSUF_GetGlobalFontSettings", "Core", "GetGlobalFontSettings" },
    { "MSUF_GetInterruptFeedbackDuration", "Utils", "GetInterruptFeedbackDuration" },
    { "MSUF_GetInterruptUnavailableCastColor", "Utils", "GetInterruptUnavailableCastColor" },
    { "MSUF_GetInterruptibleCastColor", "Utils", "GetInterruptibleCastColor" },
    { "MSUF_GetNonInterruptibleCastColor", "Utils", "GetNonInterruptibleCastColor" },
    { "MSUF_GetReverseFillSafe", "Utils", "GetReverseFillSafe" },
    { "MSUF_GlobalCastbarStyleCache", "Core", "GlobalCastbarStyleCache" },
    { "MSUF_HardSyncCastbarPreview", "Utils", "HardSyncCastbarPreview" },
    { "MSUF_HideAllCastbarPreviews", "Previews", "HideAllCastbarPreviews" },
    { "MSUF_HideBlizzardPlayerCastbar", "Previews", "HideBlizzardPlayerCastbar" },
    { "MSUF_INTERRUPT_FEEDBACK_DURATION", "Driver", "INTERRUPT_FEEDBACK_DURATION" },
    { "MSUF_InitFocusKickIcon", "FocusKick", "InitFocusKickIcon" },
    { "MSUF_InitSafePlayerCastbar", "Manager", "InitSafePlayerCastbar" },
    { "MSUF_IsCastTimeEnabled", "Manager", "IsCastTimeEnabled" },
    { "MSUF_IsCastbarEnabledForUnit", "Bridge", "IsCastbarEnabledForUnit" },
    { "MSUF_IsEmpowerStageBlinkEnabled", "Empower", "IsEmpowerStageBlinkEnabled" },
    { "MSUF_KickReady_ApplyLayout", "KickReady", "KickReady_ApplyLayout" },
    { "MSUF_KickReady_EvaluateRGBA", "KickReady", "KickReady_EvaluateRGBA" },
    { "MSUF_KickReady_GetReadyBoolForTint", "KickReady", "KickReady_GetReadyBoolForTint" },
    { "MSUF_KickReady_GetSpellID", "KickReady", "KickReady_GetSpellID" },
    { "MSUF_KickReady_Init", "KickReady", "KickReady_Init" },
    { "MSUF_KickReady_IsReady", "KickReady", "KickReady_IsReady" },
    { "MSUF_KickReady_NotifySettings", "KickReady", "KickReady_NotifySettings" },
    { "MSUF_KickReady_RefreshAll", "KickReady", "KickReady_RefreshAll" },
    { "MSUF_KickReady_RefreshFrame", "KickReady", "KickReady_RefreshFrame" },
    { "MSUF_KickReady_RefreshOutline", "KickReady", "KickReady_RefreshOutline" },
    { "MSUF_KickReady_SelectColor", "KickReady", "KickReady_SelectColor" },
    { "MSUF_LayoutEmpowerTicks", "Empower", "LayoutEmpowerTicks" },
    { "MSUF_NormalizeCastbarBackend", "Backend", "NormalizeCastbarBackend" },
    { "MSUF_NormalizeCastbarBackendForUnit", "Backend", "NormalizeCastbarBackendForUnit" },
    { "MSUF_NormalizeCastbarIconPosition", "Visuals", "NormalizeCastbarIconPosition" },
    { "MSUF_NormalizeCastbarTextJustify", "Visuals", "NormalizeCastbarTextJustify" },
    { "MSUF_NormalizeCastbarTextPosition", "Visuals", "NormalizeCastbarTextPosition" },
    { "MSUF_NormalizeCastbarTruncate", "Visuals", "NormalizeCastbarTruncate" },
    { "MSUF_NormalizeCastbarWidthSource", "Anchors", "NormalizeCastbarWidthSource" },
    { "MSUF_NormalizePlayerCastbarWidthSource", "Anchors", "NormalizePlayerCastbarWidthSource" },
    { "MSUF_PlayCastbarShake", "Utils", "PlayCastbarShake" },
    { "MSUF_PlayerCastBar", "Frames", "player" },
    { "MSUF_PlayerCastbar", "Frames", "player" },
    { "MSUF_PlayerCastbarPreview", "Frames", "playerPreview" },
    { "MSUF_PlayerCastbar_ApplyBackendState", "Manager", "PlayerCastbar_ApplyBackendState" },
    { "MSUF_PlayerCastbar_Cast", "Player", "PlayerCastbar_Cast" },
    { "MSUF_PlayerCastbar_ClearEmpower", "Empower", "PlayerCastbar_ClearEmpower" },
    { "MSUF_PlayerCastbar_EmpowerStart", "Empower", "PlayerCastbar_EmpowerStart" },
    { "MSUF_PlayerCastbar_OnEvent", "Player", "PlayerCastbar_OnEvent" },
    { "MSUF_PlayerCastbar_UpdateColorForInterruptible", "Player", "PlayerCastbar_UpdateColorForInterruptible" },
    { "MSUF_PlayerCastbar_UpdateLatencyZone", "Player", "PlayerCastbar_UpdateLatencyZone" },
    { "MSUF_PlayerChannelHasteMarkers_Hide", "ChannelTicks", "PlayerChannelHasteMarkers_Hide" },
    { "MSUF_PlayerChannelHasteMarkers_Update", "ChannelTicks", "PlayerChannelHasteMarkers_Update" },
    { "MSUF_PositionCastbarPreviewUnit", "Previews", "PositionCastbarPreviewUnit" },
    { "MSUF_PositionFocusCastbarPreview", "Previews", "PositionFocusCastbarPreview" },
    { "MSUF_PositionPlayerCastbarPreview", "Previews", "PositionPlayerCastbarPreview" },
    { "MSUF_PositionTargetCastbarPreview", "Previews", "PositionTargetCastbarPreview" },
    { "MSUF_ReanchorArenaCastBar", "Anchors", "ReanchorArenaCastBar" },
    { "MSUF_ReanchorBossCastBar", "Anchors", "ReanchorBossCastBar" },
    { "MSUF_ReanchorFocusCastBar", "Anchors", "ReanchorFocusCastBar" },
    { "MSUF_ReanchorFocusCastBarBase", "Anchors", "ReanchorFocusCastBarBase" },
    { "MSUF_ReanchorPlayerCastBar", "Anchors", "ReanchorPlayerCastBar" },
    { "MSUF_ReanchorPlayerCastBarBase", "Anchors", "ReanchorPlayerCastBarBase" },
    { "MSUF_ReanchorTargetCastBar", "Anchors", "ReanchorTargetCastBar" },
    { "MSUF_ReanchorTargetCastBarBase", "Anchors", "ReanchorTargetCastBarBase" },
    { "MSUF_RefreshAllCastTargetTextColors", "Driver", "RefreshAllCastTargetTextColors" },
    { "MSUF_RefreshCastTargetText", "Driver", "RefreshCastTargetText" },
    { "MSUF_RefreshCastbarCooldownWidthSource", "Anchors", "RefreshCastbarCooldownWidthSource" },
    { "MSUF_RefreshCastbarFrame", "Visuals", "RefreshCastbarFrame" },
    { "MSUF_RefreshCastbarSpellNameText", "Utils", "RefreshCastbarSpellNameText" },
    { "MSUF_RefreshCastbarStyleCache", "Core", "RefreshCastbarStyleCache" },
    { "MSUF_RegisterCastbar", "Manager", "RegisterCastbar" },
    { "MSUF_ResetCastbarGlowFade", "Utils", "ResetCastbarGlowFade" },
    { "MSUF_ResolveCastbarColors", "Utils", "ResolveCastbarColors" },
    { "MSUF_ResolveCastbarIconFrameLevel", "Core", "ResolveCastbarIconFrameLevel" },
    { "MSUF_ResolveCastbarTargetInfo", "Engine", "ResolveCastbarTargetInfo" },
    { "MSUF_ResolveInterruptFeedbackCastColor", "Utils", "ResolveInterruptFeedbackCastColor" },
    { "MSUF_ResolveInterruptUnavailableCastColor", "Utils", "ResolveInterruptUnavailableCastColor" },
    { "MSUF_ResolveStatusbarTextureKey", "Core", "ResolveStatusbarTextureKey" },
    { "MSUF_RoundedCastbar_ApplyOutline", "Rounded", "RoundedCastbar_ApplyOutline" },
    { "MSUF_RoundedCastbar_RefreshFrame", "Rounded", "RoundedCastbar_RefreshFrame" },
    { "MSUF_RoundedCastbar_RenderPreview", "Rounded", "RoundedCastbar_RenderPreview" },
    { "MSUF_RoundedCastbar_TintOutline", "Rounded", "RoundedCastbar_TintOutline" },
    { "MSUF_SetArenaCastbarTestMode", "Previews", "SetArenaCastbarTestMode" },
    { "MSUF_SetBossCastbarTestMode", "Previews", "SetBossCastbarTestMode" },
    { "MSUF_SetCastbarBackend", "Backend", "SetCastbarBackend" },
    { "MSUF_SetFocusCastbarTestMode", "Previews", "SetFocusCastbarTestMode" },
    { "MSUF_SetGCDBarEnabled", "GCD", "SetGCDBarEnabled" },
    { "MSUF_SetPlayerCastbarTestMode", "Previews", "SetPlayerCastbarTestMode" },
    { "MSUF_SetStatusBarColorIfChanged", "Utils", "SetStatusBarColorIfChanged" },
    { "MSUF_SetTargetCastbarTestMode", "Previews", "SetTargetCastbarTestMode" },
    { "MSUF_SetupArenaCastbarPreviewEditMode", "Previews", "SetupArenaCastbarPreviewEditMode" },
    { "MSUF_SetupBossCastbarPreviewEditMode", "Previews", "SetupBossCastbarPreviewEditMode" },
    { "MSUF_SetupCastbarPreviewEditHandlers", "PreviewEdit", "SetupCastbarPreviewEditHandlers" },
    { "MSUF_ShortenCastbarSpellName", "Utils", "ShortenCastbarSpellName" },
    { "MSUF_ShouldUseBlizzardCastbar", "Backend", "ShouldUseBlizzardCastbar" },
    { "MSUF_ShouldUseMSUFCastbar", "Backend", "ShouldUseMSUFCastbar" },
    { "MSUF_SuppressBlizzardPlayerCastbars", "Bridge", "SuppressBlizzardPlayerCastbars" },
    { "MSUF_SyncCastbarBackendLegacyFlags", "Backend", "SyncCastbarBackendLegacyFlags" },
    { "MSUF_TargetCastBar", "Frames", "target" },
    { "MSUF_TargetCastbar", "Frames", "target" },
    { "MSUF_TargetCastbarPreview", "Frames", "targetPreview" },
    { "MSUF_UnregisterCastbar", "Manager", "UnregisterCastbar" },
    { "MSUF_UpdateArenaCastbarPreview", "Previews", "UpdateArenaCastbarPreview" },
    { "MSUF_UpdateBossCastbarPreview", "Previews", "UpdateBossCastbarPreview" },
    { "MSUF_UpdateCastTimeText_FromStatusBar", "Driver", "UpdateCastTimeText_FromStatusBar" },
    { "MSUF_UpdateCastbarFrame", "Manager", "UpdateCastbarFrame" },
    { "MSUF_UpdateCastbarTextures", "Core", "UpdateCastbarTextures" },
    { "MSUF_UpdateCastbarTextures_Immediate", "Core", "UpdateCastbarTextures_Immediate" },
    { "MSUF_UpdateCastbarVisuals", "Core", "UpdateCastbarVisuals" },
    { "MSUF_UpdateCastbarVisuals_Immediate", "Core", "UpdateCastbarVisuals_Immediate" },
    { "MSUF_UpdateCastbarWidthSourceSync", "Anchors", "UpdateCastbarWidthSourceSync" },
    { "MSUF_UpdateFocusKickIconOptions", "FocusKick", "UpdateFocusKickIconOptions" },
    { "MSUF_UpdatePlayerCastbarPreview", "Previews", "UpdatePlayerCastbarPreview" },
    { "MSUF__castTimeGlobalRev", "Config", "timeRevision" },
    { "MSUF__castbarStyleGlobalRev", "Config", "styleRevision" },
}

local function FixtureProvider(value)
    if type(value) ~= "function" then return value end
    local source = debug.getinfo(value, "S").source:gsub("\\", "/")
    if source:find("/MidnightSimpleUnitFrames/", 1, true) then return nil end
    return value
end

function Fixture.Seed(ns, env)
    env = env or _G
    for _, slot in ipairs(slots) do
        local module = ns.Castbars[slot[2]]
        if module[slot[3]] == nil then module[slot[3]] = FixtureProvider(env[slot[1]]) end
    end
end

function Fixture.Bind(ns, env)
    -- Internal providers stay in the namespace, exactly as in the real client.
end

function Fixture.Attach(root, ns, original, env)
    env = env or _G
    env.MSUF, env.MSUF_NS = ns, ns
    if ns._castbarFixtureAttached then return end
    -- Publication reuses the namespace but initializes fresh submodules. Keep
    -- the fixture's module references before those fields are replaced.
    local existing = {}
    for name, value in pairs(ns.Castbars or {}) do existing[name] = value end
    local legacyBackend = ns.MSUF_CastbarBackend
    local legacyRuntime = env.MSUF_CastbarRuntime
    local initialTextureRevision = env.MSUF_CastbarStyleRevision
    local initialStyleRevision = env.MSUF__castbarStyleGlobalRev
    local load = original
    original = function(path)
        local chunk, why = load(path)
        if chunk then setfenv(chunk, env) end
        return chunk, why
    end
    env.MSUF_DB = env.MSUF_DB or { general = {} }
    if not env.MSUF_EnsureDB then
        env.MSUF_EnsureDB = function() assert(type(env.MSUF_DB) == "table", "fixture profile is missing") end
    end
    ns.Public = ns.Public or {}
    ns.Public.GetCastbarTimeFormat = env.MSUF_GetCastbarTimeFormat
    if not ns.Require or not ns.Optional then
        assert(original(root .. "/MidnightSimpleUnitFrames/Kernel/MSUF_Require.lua"))("MSUF", ns)
    end
    assert(original(root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_Castbars_PublicAPI.lua"))("MSUF", ns)
    if existing then
        for name, value in pairs(existing) do ns.Castbars[name] = value end
    end
    assert(original(root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_Castbars_Backend.lua"))("MSUF", ns)
    assert(original(root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_CastbarConfig.lua"))("MSUF", ns)
    if legacyBackend then
        for key, value in pairs(legacyBackend) do ns.Castbars.Backend[key] = value end
    end
    Fixture.Seed(ns, env)
    if legacyRuntime then
        for key, value in pairs(legacyRuntime) do if ns.Castbars.Runtime[key] == nil then ns.Castbars.Runtime[key] = FixtureProvider(value) end end
    end
    if initialTextureRevision then
        ns.Castbars.Config.textureRevision = initialTextureRevision
        ns.Castbars.Config.revisions.texture = initialTextureRevision
    end
    if initialStyleRevision then
        ns.Castbars.Config.styleRevision = initialStyleRevision
        ns.Castbars.Config.revisions.style = initialStyleRevision
    end
    Fixture.Seed(ns, env)
    ns.Castbars.Pools.live = ns.Castbars.Pools.live or {}
    for _, kind in ipairs({ "boss", "arena" }) do
        ns.Castbars.Pools.live[kind] = env["MSUF_" .. (kind == "boss" and "Boss" or "Arena") .. "Castbars"]
    end
    ns.Castbars.Config.Compile()
    ns._castbarFixtureAttached = true
end

function Fixture.Loader(original)
    return function(path)
        local chunk, why = original(path)
        if not chunk then return chunk, why end
        local normalized = path:gsub("\\", "/")
        local root = normalized:match("^(.-)/MidnightSimpleUnitFrames/")
        if normalized:match("^MidnightSimpleUnitFrames/") then root = "." end
        if not root or not normalized:find("/Castbars/", 1, true) then return chunk, why end
        return function(addon, ns)
            Fixture.Attach(root, ns, original, getfenv(chunk))
            if normalized:match("/MSUF_Castbars_Core%.lua$") then
                local env = getfenv(chunk)
                local previewFixture = assert(original(root .. "/tools/tests/preview_namespace_fixture.lua"))()
                previewFixture.Install(root, ns, env, original)
                local mediaFixture = assert(original(root .. "/tools/tests/runtime_media_fixture.lua"))()
                mediaFixture.LoadFonts(root, ns, original, env)
                if not ns.Media then
                    local owner = assert(original(root .. "/MidnightSimpleUnitFrames/Runtime/MSUF_MediaRuntime.lua"))
                    setfenv(owner, env)
                    owner("MidnightSimpleUnitFrames", ns)
                end
            end
            local result = chunk(addon, ns)
            Fixture.Bind(ns, getfenv(chunk))
            return result
        end
    end
end

return Fixture
