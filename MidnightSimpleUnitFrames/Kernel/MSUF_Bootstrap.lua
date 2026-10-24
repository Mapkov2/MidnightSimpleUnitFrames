local addonName, MSUF = ...
local _G = _G
local type = type
local tostring = tostring

MSUF = MSUF or _G.MSUF or _G.MSUF_NS or {}
_G.MSUF = MSUF
_G.MSUF_NS = MSUF

local function EnsureTable(parent, key)
    local current = parent[key]
    if type(current) ~= "table" then
        current = {}
        parent[key] = current
    end
    return current
end

MSUF.Core = MSUF.Core or {}
MSUF.UF = MSUF.UF or {}
MSUF.Bars = MSUF.Bars or {}
MSUF.Text = MSUF.Text or {}
MSUF.Icons = MSUF.Icons or {}
MSUF.Util = MSUF.Util or {}
MSUF.Cache = MSUF.Cache or {}
MSUF.Compat = MSUF.Compat or {}
MSUF.GF = MSUF.GF or {}
MSUF.Castbars = MSUF.Castbars or {}
MSUF.Public = MSUF.Public or {}
MSUF.API = MSUF.Public
MSUF.Private = MSUF.Private or {}
MSUF.PublicGlobals = MSUF.PublicGlobals or {}
MSUF.Compat.LegacyGlobals = MSUF.Compat.LegacyGlobals or {}

MSUF.AddonName = MSUF.AddonName or addonName
MSUF.Core.BootstrapLoaded = true

local function PublicKey(name)
    if type(name) ~= "string" or name == "" then return nil end
    if name:sub(1, 5) == "MSUF_" then
        return name:sub(6)
    end
    return name
end

function MSUF.MSUF_Namespace(path)
    local node = MSUF
    path = tostring(path or "")
    for key in path:gmatch("[^%.]+") do
        if key ~= "" then node = EnsureTable(node, key) end
    end
    return node
end

MSUF.Namespace = MSUF.MSUF_Namespace

function MSUF.MSUF_PublicKey(name)
    return PublicKey(name)
end

-- BEGIN GENERATED GLOBAL KEEP: tools/gen_global_keep.py
-- Staged data only: the director switches GlobalExports after consumers move.
MSUF.Compat.GlobalKeep = {
    -- native slash/binding
    -- reviewed blizzard-contract
    BINDING_HEADER_MSUF_HEADER = true,
    -- native slash/binding
    -- reviewed blizzard-contract
    ["BINDING_NAME_CLICK MSUF_UnitMenuPlayer:LeftButton"] = true,
    -- native slash/binding
    -- reviewed blizzard-contract
    ["BINDING_NAME_CLICK MSUF_UnitMenuTarget:LeftButton"] = true,
    -- native slash/binding
    -- reviewed blizzard-contract
    BINDING_NAME_MSUF_PRIORITY_TOGGLE = true,
    -- native slash/binding
    -- reviewed blizzard-contract
    BINDING_NAME_MSUF_TOGGLE_EDITMODE = true,
    -- native slash/binding
    -- reviewed blizzard-contract
    BINDING_NAME_MSUF_TOGGLE_OPTIONS = true,
    -- native slash/binding
    -- reviewed blizzard-contract
    BINDING_NAME_MSUF_VARIANT_1 = true,
    -- native slash/binding
    -- reviewed blizzard-contract
    BINDING_NAME_MSUF_VARIANT_2 = true,
    -- native slash/binding
    -- reviewed blizzard-contract
    BINDING_NAME_MSUF_VARIANT_3 = true,
    -- native slash/binding
    -- reviewed blizzard-contract
    BINDING_NAME_MSUF_VARIANT_4 = true,
    -- native slash/binding
    -- reviewed blizzard-contract
    BINDING_NAME_MSUF_VARIANT_5 = true,
    -- native slash/binding
    -- reviewed blizzard-contract
    BINDING_NAME_MSUF_VARIANT_6 = true,
    -- native slash/binding
    -- reviewed blizzard-contract
    BINDING_NAME_MSUF_VARIANT_7 = true,
    -- native slash/binding
    -- reviewed blizzard-contract
    BINDING_NAME_MSUF_VARIANT_8 = true,
    -- Suite reader
    -- reviewed suite
    MSUF = true,
    -- Suite reader
    -- reviewed suite
    MSUF2 = true,
    -- Suite reader
    -- reviewed suite
    MSUF2NativeDropdownList = true,
    -- Suite reader
    -- reviewed suite,external
    MSUF2_Open = true,
    -- reviewed blizzard-contract
    MSUF2_Window = true,
    -- Suite reader
    -- reviewed suite,external
    MSUF_ActiveProfile = true,
    -- XML/TOC contract
    -- reviewed blizzard-contract
    MSUF_AddonCompartment_OnClick = true,
    -- XML/TOC contract
    -- reviewed blizzard-contract
    MSUF_AddonCompartment_OnEnter = true,
    -- XML/TOC contract
    -- reviewed blizzard-contract
    MSUF_AddonCompartment_OnLeave = true,
    -- Suite reader
    -- reviewed suite
    MSUF_ApplyCurrentProfileGlobalUiScale = true,
    -- Suite reader
    -- reviewed suite
    MSUF_ApplyFontScaleAnimationMode = true,
    -- Suite reader
    -- reviewed suite
    MSUF_ApplyMsufScale = true,
    -- Suite reader
    -- reviewed suite,external
    MSUF_ApplyPowerBarEmbedLayout_ForUnitKey = true,
    -- Suite reader
    -- reviewed suite
    MSUF_ClassPower_Apply = true,
    -- reviewed external
    MSUF_CreateProfile = true,
    -- SavedVariables
    -- Suite reader
    -- reviewed sv,suite,external
    MSUF_DB = true,
    -- Suite reader
    -- reviewed suite,external
    MSUF_DeleteProfile = true,
    -- Suite reader
    -- reviewed suite,external
    MSUF_EM2 = true,
    -- Suite reader
    -- reviewed suite,external
    MSUF_EditModeAPI = true,
    -- reviewed external
    MSUF_EditState = true,
    -- reviewed integration
    MSUF_EllesmereEditMode_ClearMoveState = true,
    -- reviewed integration
    MSUF_EllesmereEditMode_IsAvailable = true,
    -- reviewed integration
    MSUF_EllesmereEditMode_ResumePreview = true,
    -- reviewed integration
    MSUF_EllesmereEditMode_SetEnabled = true,
    -- reviewed integration
    MSUF_EllesmereEditMode_SuspendPreview = true,
    -- Suite reader
    -- reviewed suite
    MSUF_EncodeCompactTable = true,
    -- Suite reader
    -- reviewed suite
    MSUF_EnsureCooldownWidthObservers = true,
    -- Suite reader
    -- reviewed suite
    MSUF_FontApplyEpoch = true,
    -- reviewed integration
    MSUF_GetActiveCooldownAnchorProvider = true,
    -- reviewed integration
    MSUF_GetArcUICooldownAnchor = true,
    -- reviewed integration
    MSUF_GetAutomaticCooldownAnchorProvider = true,
    -- reviewed external
    MSUF_GetConfiguredFontColor = true,
    -- reviewed integration
    MSUF_GetCooldownAnchorConsentDecision = true,
    -- reviewed integration
    MSUF_GetCooldownAnchorScaledWidth = true,
    -- reviewed integration
    MSUF_GetCoolinatorCooldownAnchor = true,
    -- Suite reader
    -- reviewed suite
    MSUF_GetDefaultProfileForNewCharacters = true,
    -- reviewed integration
    MSUF_GetEllesmereCooldownAnchor = true,
    -- Suite reader
    -- reviewed suite
    MSUF_GetFontFlags = true,
    -- Suite reader
    -- reviewed suite
    MSUF_GetFontPath = true,
    -- Suite reader
    -- reviewed suite
    MSUF_GetFontPathForKey = true,
    -- reviewed external
    MSUF_GetGlobalFontSettings = true,
    -- Suite reader
    -- reviewed suite
    MSUF_GetPixelPerfectScale = true,
    -- reviewed integration
    MSUF_GetSkironCooldownAnchorProxy = true,
    -- Suite reader
    -- reviewed suite,integration
    MSUF_GetSuiteCooldownAnchor = true,
    -- reviewed integration
    MSUF_GetUsableCooldownAnchorSize = true,
    -- SavedVariables
    -- Suite reader
    -- reviewed sv,suite,external
    MSUF_GlobalDB = true,
    -- XML reference
    -- XML/TOC contract
    -- reviewed blizzard-contract
    MSUF_GroupAdditionalUnitOnLoad = true,
    -- XML/TOC contract
    -- reviewed blizzard-contract
    MSUF_GroupAdditionalUnitTemplate = true,
    -- XML/TOC contract
    -- reviewed blizzard-contract
    MSUF_GroupHeaderUnitButtonTemplate = true,
    -- Suite reader
    -- reviewed suite
    MSUF_HostAPI = true,
    -- bare runtime flag
    MSUF_InCombat = true,
    -- reviewed integration
    MSUF_IsCooldownAnchorEnabled = true,
    -- reviewed integration
    MSUF_IsCooldownAnchorSupported = true,
    -- reviewed external
    MSUF_IsInEditMode = true,
    -- XML script
    -- XML/TOC contract
    -- reviewed blizzard-contract
    MSUF_Keybind_ToggleEditMode = true,
    -- XML script
    -- XML/TOC contract
    -- reviewed blizzard-contract
    MSUF_Keybind_ToggleOptions = true,
    -- XML script
    -- XML/TOC contract
    -- reviewed blizzard-contract
    MSUF_Keybind_TogglePriorityFrame = true,
    -- Suite reader
    -- reviewed suite
    MSUF_NS = true,
    -- reviewed integration
    MSUF_NSRTNicknames_ApplySetting = true,
    -- Suite reader
    -- reviewed suite
    MSUF_PadNavigation = true,
    -- Suite reader
    -- reviewed suite
    MSUF_PixelLayoutRegion = true,
    -- Suite reader
    -- reviewed suite
    MSUF_ProfileWasUnboundAtLogin = true,
    -- Suite reader
    -- reviewed suite,external
    MSUF_Profiles_ExportSelectionToString = true,
    -- Suite reader
    -- reviewed suite
    MSUF_Profiles_ImportExternal = true,
    -- reviewed external
    MSUF_Profiles_ImportFromString = true,
    -- Suite reader
    -- reviewed suite,external
    MSUF_Profiles_ImportIntoNewProfile = true,
    -- Suite reader
    -- reviewed suite,external
    MSUF_RegisterAnyEditModeListener = true,
    -- Suite reader
    -- reviewed suite
    MSUF_ResetGlobalUiScale = true,
    -- Suite reader
    -- reviewed suite
    MSUF_ResolveFontKeyPath = true,
    -- Suite reader
    -- reviewed suite
    MSUF_ResolveStatusbarTextureKey = true,
    -- reviewed integration
    MSUF_SetCooldownAnchorEnabled = true,
    -- Suite reader
    -- reviewed suite
    MSUF_SetCurrentProfileScreenReferenceHeight = true,
    -- Suite reader
    -- reviewed suite
    MSUF_SetDefaultProfileForNewCharacters = true,
    -- Suite reader
    -- reviewed suite
    MSUF_SetFontChecked = true,
    -- Suite reader
    -- reviewed suite
    MSUF_SetGlobalUiScale = true,
    -- documented /run
    MSUF_ShowClientVersionWarning = true,
    -- documented /run
    MSUF_ShowWelcomeMessage = true,
    -- reviewed integration
    MSUF_SkironCooldownAnchor = true,
    -- Suite reader
    -- reviewed suite,external
    MSUF_SwitchProfile = true,
    -- XML script
    -- XML/TOC contract
    -- reviewed blizzard-contract
    MSUF_ToggleProfileVariant = true,
    -- reviewed integration
    MSUF_TryCloseExternalEditMode = true,
    -- Suite reader
    -- reviewed suite
    MSUF_TryDecodeCompactString = true,
    -- reviewed integration
    MSUF_TryOpenExternalEditMode = true,
    -- Suite reader
    -- reviewed suite,external
    MSUF_UFCore_NotifyConfigChanged = true,
    -- Suite reader
    -- reviewed suite
    MSUF_UI = true,
    -- Suite reader
    -- reviewed suite,external
    MSUF_UnitEditModeActive = true,
    -- reviewed external
    MSUF_UnitFrames = true,
    -- XML/TOC contract
    -- reviewed blizzard-contract
    MSUF_UnitMenuPlayer = true,
    -- XML/TOC contract
    -- reviewed blizzard-contract
    MSUF_UnitMenuTarget = true,
    -- reviewed external
    MSUF_boss1 = true,
    -- reviewed external
    MSUF_boss2 = true,
    -- reviewed external
    MSUF_boss3 = true,
    -- reviewed external
    MSUF_boss4 = true,
    -- reviewed external
    MSUF_boss5 = true,
    -- reviewed external
    MSUF_focus = true,
    -- reviewed external
    MSUF_pet = true,
    -- Suite reader
    -- reviewed suite,external
    MSUF_player = true,
    -- Suite reader
    -- reviewed suite,external
    MSUF_target = true,
    -- reviewed external
    MSUF_targettarget = true,
    -- native slash/binding
    -- reviewed blizzard-contract
    SLASH_MIDNIGHTSUF1 = true,
    -- native slash/binding
    -- reviewed blizzard-contract
    SLASH_MSUF2OPTIONS1 = true,
    -- native slash/binding
    -- reviewed blizzard-contract
    SLASH_MSUFAURALAYERS1 = true,
    -- native slash/binding
    -- reviewed blizzard-contract
    SLASH_MSUFDBGPOS1 = true,
    -- native slash/binding
    -- reviewed blizzard-contract
    SLASH_MSUFGROUPPULSE1 = true,
    -- native slash/binding
    -- reviewed blizzard-contract
    SLASH_MSUFMENUCHECK1 = true,
    -- native slash/binding
    -- reviewed blizzard-contract
    SLASH_MSUFOPTIONS1 = true,
    -- native slash/binding
    -- reviewed blizzard-contract
    SLASH_MSUFRELOADUI1 = true,
}
-- END GENERATED GLOBAL KEEP

-- Global compatibility names used by shipped readers and integrations.
local GlobalExports = {
    ["BINDING_HEADER_MSUFSUITE"] = true, ["BINDING_HEADER_MSUFSUITE_DAMAGEMETER"] = true, ["BINDING_HEADER_MSUFSUITE_TOGGLES"] = true,
    ["BINDING_HEADER_MSUF_HEADER"] = true, ["BINDING_NAME_CLICK MSUF_UnitMenuPlayer:LeftButton"] = true,
    ["BINDING_NAME_CLICK MSUF_UnitMenuTarget:LeftButton"] = true, ["BINDING_NAME_MSUFSUITE_RESET_DAMAGE_METER"] = true,
    ["BINDING_NAME_MSUFSUITE_TOGGLE_DAMAGE_METER"] = true, ["BINDING_NAME_MSUFSUITE_TOGGLE_FPS"] = true,
    ["BINDING_NAME_MSUFSUITE_TOGGLE_FRIENDLY_NPCS"] = true, ["BINDING_NAME_MSUF_PRIORITY_TOGGLE"] = true,
    ["BINDING_NAME_MSUF_TOGGLE_EDITMODE"] = true, ["BINDING_NAME_MSUF_TOGGLE_OPTIONS"] = true, ["BINDING_NAME_MSUF_VARIANT_1"] = true,
    ["BINDING_NAME_MSUF_VARIANT_2"] = true, ["BINDING_NAME_MSUF_VARIANT_3"] = true, ["BINDING_NAME_MSUF_VARIANT_4"] = true,
    ["BINDING_NAME_MSUF_VARIANT_5"] = true, ["BINDING_NAME_MSUF_VARIANT_6"] = true, ["BINDING_NAME_MSUF_VARIANT_7"] = true,
    ["BINDING_NAME_MSUF_VARIANT_8"] = true, ["GetInternalFontPathByKey"] = true, ["MSCB_ApplyFontsFromMSUF"] = true, ["MSUF"] = true,
    ["MSUF2"] = true, ["MSUF2FocusVeil"] = true, ["MSUF2LayerOverview"] = true, ["MSUF2NativeDropdownList"] = true,
    ["MSUF2PreviewControlsHelp"] = true, ["MSUF2PreviewHandleContextMenu"] = true, ["MSUF2PreviewMoveCue"] = true, ["MSUF2_ARENA_PAGE"] = true,
    ["MSUF2_ARENA_PAGE_CORE"] = true, ["MSUF2_ARENA_PAGE_FALLBACK"] = true, ["MSUF2_ARENA_PAGE_OFF"] = true,
    ["MSUF2_ArenaPageAuraPreviewActive"] = true, ["MSUF2_BOSS_PAGE"] = true, ["MSUF2_BOSS_PAGE_CORE"] = true, ["MSUF2_BOSS_PAGE_FALLBACK"] = true,
    ["MSUF2_BOSS_PAGE_OFF"] = true, ["MSUF2_BossPageAuraPreviewActive"] = true, ["MSUF2_COPY_TO_ALL_CONFIRM"] = true, ["MSUF2_COPY_UNIT"] = true,
    ["MSUF2_COPY_UNIT_AURAS"] = true, ["MSUF2_COPY_UNIT_STATUS"] = true, ["MSUF2_GFPagePreviewActive"] = true, ["MSUF2_GRADIENT"] = true,
    ["MSUF2_GROUPFRAMES_RELOAD_REQUIRED"] = true, ["MSUF2_LEVEL_INDICATOR"] = true, ["MSUF2_LOCALE_RELOAD_REQUIRED"] = true, ["MSUF2_Open"] = true,
    ["MSUF2_PORTRAIT"] = true, ["MSUF2_PRIORITY_BINDING_CONFLICT"] = true, ["MSUF2_PRIORITY_CLEAR_PINS"] = true,
    ["MSUF2_RANGE_FADE_SLIDER_PREVIEW"] = true, ["MSUF2_STATUS_INDICATOR"] = true, ["MSUF2_STATUS_TEST_MENU_EXIT"] = true, ["MSUF2_TEXT"] = true,
    ["MSUF2_Toggle"] = true, ["MSUF2_Window"] = true, ["MSUF3"] = true, ["MSUFAURALAYERS"] = true, ["MSUFGFInitChild"] = true,
    ["MSUFRELOADUI"] = true, ["MSUFSUITE"] = true, ["MSUFSUITEGUILDPRIVACY"] = true, ["MSUFSUITE_BAR10"] = true, ["MSUFSUITE_BAR10_BUTTON1"] = true,
    ["MSUFSUITE_BAR10_BUTTON10"] = true, ["MSUFSUITE_BAR10_BUTTON11"] = true, ["MSUFSUITE_BAR10_BUTTON12"] = true,
    ["MSUFSUITE_BAR10_BUTTON2"] = true, ["MSUFSUITE_BAR10_BUTTON3"] = true, ["MSUFSUITE_BAR10_BUTTON4"] = true, ["MSUFSUITE_BAR10_BUTTON5"] = true,
    ["MSUFSUITE_BAR10_BUTTON6"] = true, ["MSUFSUITE_BAR10_BUTTON7"] = true, ["MSUFSUITE_BAR10_BUTTON8"] = true, ["MSUFSUITE_BAR10_BUTTON9"] = true,
    ["MSUFSUITE_BAR9"] = true, ["MSUFSUITE_BAR9_BUTTON1"] = true, ["MSUFSUITE_BAR9_BUTTON10"] = true, ["MSUFSUITE_BAR9_BUTTON11"] = true,
    ["MSUFSUITE_BAR9_BUTTON12"] = true, ["MSUFSUITE_BAR9_BUTTON2"] = true, ["MSUFSUITE_BAR9_BUTTON3"] = true, ["MSUFSUITE_BAR9_BUTTON4"] = true,
    ["MSUFSUITE_BAR9_BUTTON5"] = true, ["MSUFSUITE_BAR9_BUTTON6"] = true, ["MSUFSUITE_BAR9_BUTTON7"] = true, ["MSUFSUITE_BAR9_BUTTON8"] = true,
    ["MSUFSUITE_BAR9_BUTTON9"] = true, ["MSUFSUITE_DAMAGEMETER"] = true, ["MSUFSUITE_RESET_DAMAGE_METER"] = true, ["MSUFSUITE_TOGGLES"] = true,
    ["MSUFSUITE_TOGGLE_BAR1"] = true, ["MSUFSUITE_TOGGLE_BAR10"] = true, ["MSUFSUITE_TOGGLE_BAR11"] = true, ["MSUFSUITE_TOGGLE_BAR12"] = true,
    ["MSUFSUITE_TOGGLE_BAR2"] = true, ["MSUFSUITE_TOGGLE_BAR3"] = true, ["MSUFSUITE_TOGGLE_BAR4"] = true, ["MSUFSUITE_TOGGLE_BAR5"] = true,
    ["MSUFSUITE_TOGGLE_BAR6"] = true, ["MSUFSUITE_TOGGLE_BAR7"] = true, ["MSUFSUITE_TOGGLE_BAR8"] = true, ["MSUFSUITE_TOGGLE_BAR9"] = true,
    ["MSUFSUITE_TOGGLE_DAMAGE_METER"] = true, ["MSUFSUITE_TOGGLE_FPS"] = true, ["MSUFSUITE_TOGGLE_FRIENDLY_NPCS"] = true, ["MSUFSuite"] = true,
    ["MSUFSuiteAnnouncements"] = true, ["MSUFSuiteBar"] = true, ["MSUFSuiteChatHistory"] = true, ["MSUFSuiteDB"] = true,
    ["MSUFSuiteDemonLooks"] = true, ["MSUFSuiteMinimap"] = true, ["MSUFSuiteQuestItem"] = true, ["MSUFSuiteSkinDB"] = true,
    ["MSUFSuiteSkinMigrating"] = true, ["MSUFSuite_ApplyFontsFromMSUF"] = true, ["MSUF_"] = true, ["MSUF_ALPHA"] = true,
    ["MSUF_ALPHA_DISCORD"] = true, ["MSUF_APPLY"] = true, ["MSUF_ARENA_MATCH_OPPONENT"] = true, ["MSUF_ARENA_MATCH_PREP"] = true,
    ["MSUF_ARENA_MATCH_REGEN"] = true, ["MSUF_ARENA_MATCH_STATE"] = true, ["MSUF_ARENA_MATCH_WORLD"] = true, ["MSUF_ARENA_PREP_END"] = true,
    ["MSUF_ARENA_TRINKET_COOLDOWN"] = true, ["MSUF_ARENA_TRINKET_LOGIN"] = true, ["MSUF_ARENA_TRINKET_MATCH"] = true,
    ["MSUF_ARENA_TRINKET_MISTS_LOG"] = true, ["MSUF_ARENA_TRINKET_OPPONENT"] = true, ["MSUF_ARENA_TRINKET_SPELL"] = true,
    ["MSUF_ARENA_TRINKET_WORLD"] = true, ["MSUF_ActiveProfile"] = true, ["MSUF_AddTooltip"] = true, ["MSUF_AddonCompartment_OnClick"] = true,
    ["MSUF_AddonCompartment_OnEnter"] = true, ["MSUF_AddonCompartment_OnLeave"] = true, ["MSUF_AggroBorderTestMode"] = true,
    ["MSUF_AggroBorderTestScope"] = true, ["MSUF_Analytics_HandleSlash"] = true, ["MSUF_AnchorPickerOverlay"] = true, ["MSUF_ApplyAllAlpha"] = true,
    ["MSUF_ApplyAllCastbarsAndSync"] = true, ["MSUF_ApplyArenaCastbarPositionSetting"] = true, ["MSUF_ApplyArenaUnitframePreviewState"] = true,
    ["MSUF_ApplyBarBackgroundVisual"] = true, ["MSUF_ApplyBarOutlineThickness_All"] = true, ["MSUF_ApplyBossCastbarPositionSetting"] = true,
    ["MSUF_ApplyBossPhysicalBarGeometry"] = false, ["MSUF_ApplyBossUnitframePreviewState"] = true, ["MSUF_ApplyCachedUnitFrameScreenPosition"] = true,
    ["MSUF_ApplyCastbarGlowFade"] = true, ["MSUF_ApplyCastbarPagePreviewState"] = true, ["MSUF_ApplyCastbarUnitAndSync"] = true,
    ["MSUF_ApplyCastbarVisualsForUnit"] = true, ["MSUF_ApplyCurrentProfileGlobalUiScale"] = true, ["MSUF_ApplyFontScaleAnimationMode"] = true,
    ["MSUF_ApplyModules"] = true, ["MSUF_ApplyMsufScale"] = true, ["MSUF_ApplyPowerBarBorder_All"] = true,
    ["MSUF_ApplyPowerBarEmbedLayout_All"] = true, ["MSUF_ApplyPowerBarEmbedLayout_ForUnitKey"] = true, ["MSUF_ApplyReverseFillBars"] = true,
    ["MSUF_ApplyRoundedUnitframes"] = true, ["MSUF_ApplySpecProfileIfEnabled"] = true, ["MSUF_ArenaCastbar1"] = true,
    ["MSUF_ArenaCastbarPreview1"] = true, ["MSUF_ArenaCastbars"] = true, ["MSUF_ArenaMatch_SyncPrepDisplay"] = true,
    ["MSUF_ArenaMatch_SyncStealthOverlays"] = true, ["MSUF_ArenaMatch_SyncTrinketIcons"] = true, ["MSUF_ArenaPrepVisibilityActive"] = true,
    ["MSUF_ArenaPrepVisibilityCount"] = true, ["MSUF_ArenaStealthOverlay"] = true, ["MSUF_ArenaTrinket"] = true,
    ["MSUF_ArenaTrinkets_RefreshLayout"] = true, ["MSUF_ArenaTrinkets_SyncPreview"] = true, ["MSUF_AuraAnchorOffset"] = true,
    ["MSUF_AuraButtonAnchor"] = true, ["MSUF_AuraPaddingInset"] = true, ["MSUF_BACKGROUND_APPLY"] = true, ["MSUF_BACKGROUND_VISUAL"] = true,
    ["MSUF_BLIZZARD_EDITMODE_RELOAD"] = true, ["MSUF_BUILTIN_BAR_TEXTURES"] = true, ["MSUF_BeginBossCastbarPreviewBatch"] = true,
    ["MSUF_BlizzardEditMode_ApplyProfileSnapshot"] = true, ["MSUF_BlizzardEditMode_Debug"] = true, ["MSUF_BlizzardEditMode_EnsureLayout"] = true,
    ["MSUF_BlizzardEditMode_IsAvailable"] = true, ["MSUF_BlizzardEditMode_ReloadUI"] = true, ["MSUF_BlizzardEditMode_SetEnabled"] = true,
    ["MSUF_BlockConfigCombatLocked"] = true, ["MSUF_BorderStyles"] = true, ["MSUF_BossCastbar"] = true, ["MSUF_BossCastbar1"] = true,
    ["MSUF_BossCastbars"] = true, ["MSUF_BossTargetBorderTestMode"] = true, ["MSUF_BuildPreviewAnimationAuraState"] = true,
    ["MSUF_BuildPreviewAnimationFrameState"] = true, ["MSUF_BumpCastbarStyleRevision"] = true, ["MSUF_CASTBAR_DRIVER_LOGIN"] = true,
    ["MSUF_CASTBAR_DRIVER_WORLD"] = true, ["MSUF_CB_ApplyTexts"] = true, ["MSUF_CDM_GetScaledWidth"] = true, ["MSUF_COMBAT_STATE"] = true,
    ["MSUF_COMBAT_STATE_CLEAR"] = true, ["MSUF_COMBAT_TIMER"] = true, ["MSUF_COOLDOWN_WIDTH_SOURCE"] = true, ["MSUF_CP_CONST"] = true,
    ["MSUF_CP_CORE_BUILDERS"] = true, ["MSUF_CP_CoreUnitFrame"] = true, ["MSUF_CROSSHAIR"] = true, ["MSUF_CacheUnitFrameScreenPosition"] = true,
    ["MSUF_CanDetachUnitPowerBar"] = true, ["MSUF_CancelScheduled"] = true, ["MSUF_CanonPowerBarUnitKey"] = true, ["MSUF_CaptureKeys"] = true,
    ["MSUF_Castbars_OnSettingsChanged"] = true, ["MSUF_Changelog"] = true, ["MSUF_Clamp"] = true, ["MSUF_ClampCheckboxText"] = true,
    ["MSUF_ClampFrameLevel"] = true, ["MSUF_ClampRoundedEdgeSize"] = true, ["MSUF_ClampToSlider"] = true, ["MSUF_ClassPowerContainer"] = true,
    ["MSUF_ClassPowerPreview_NudgeHandle"] = true, ["MSUF_ClassPowerPreview_Pan"] = true, ["MSUF_ClassPower_Apply"] = true,
    ["MSUF_ClassPower_ApplyRoundedSurface"] = true, ["MSUF_ClassPower_MountEbonMight"] = true, ["MSUF_ClassPower_RefreshExternalWidth"] = true,
    ["MSUF_ClearArenaUnitframePreviewForCombat"] = true, ["MSUF_ClearBossUnitframePreviewForCombat"] = true,
    ["MSUF_ClearFontStringApplyCaches"] = true, ["MSUF_ClearManagedBinding"] = true, ["MSUF_ClearResolvedStatusbarTextureCache"] = true,
    ["MSUF_CombatCrosshairEventFrame"] = true, ["MSUF_CombatCrosshairFrame"] = true, ["MSUF_CombatStateFrame"] = true,
    ["MSUF_CombatStateText"] = true, ["MSUF_CombatTimerFrame"] = true, ["MSUF_CooldownAnchorSupported"] = true, ["MSUF_CopyLinkPopup"] = true,
    ["MSUF_CopyProfile"] = true, ["MSUF_CreateFactoryDefaultProfile"] = true, ["MSUF_CreateProfile"] = true, ["MSUF_CurrentFrameBorderColor"] = true,
    ["MSUF_DB"] = true, ["MSUF_DandersEditMode_SetEnabled"] = true, ["MSUF_DebugPingFrame"] = true, ["MSUF_DeepCopy"] = true,
    ["MSUF_DeleteProfile"] = true, ["MSUF_DetailsEditMode_SetEnabled"] = true, ["MSUF_DispelBorderTestMode"] = true,
    ["MSUF_DispelBorderTestScope"] = true, ["MSUF_DoFullReset"] = true, ["MSUF_DominosEditMode_SetEnabled"] = true,
    ["MSUF_EFFECT_FRAME_STRATA"] = true, ["MSUF_EM2"] = true, ["MSUF_EM2_AuraPopup"] = true, ["MSUF_EM2_BlizzardLayoutDialog"] = true,
    ["MSUF_EM2_CancelConfirm"] = true, ["MSUF_EM2_CastPopup"] = true, ["MSUF_EM2_ExternalPopup"] = true, ["MSUF_EM2_GFPopup_mythicraid"] = true,
    ["MSUF_EM2_GFPopup_party"] = true, ["MSUF_EM2_GFPopup_raid"] = true, ["MSUF_EM2_HUD"] = true, ["MSUF_EM2_HUD_PositionPopup"] = true,
    ["MSUF_EM2_HUD_Row2"] = true, ["MSUF_EM2_MoverParent"] = true, ["MSUF_EM2_ReforcePreviewFrames"] = true, ["MSUF_EM2_ResourcePopup"] = true,
    ["MSUF_EM2_SetFocusSelection"] = true, ["MSUF_EM2_SetHUDStatus"] = true, ["MSUF_EM2_SetPreviewNudgeTarget"] = true,
    ["MSUF_EM2_SyncGFPopups"] = true, ["MSUF_EM2_UnitPopup"] = true, ["MSUF_EM_SetCastbarAnchoredToUnit"] = true,
    ["MSUF_EM_UndoBeforeChange"] = true, ["MSUF_EditModeAPI"] = true, ["MSUF_EditModeSizing"] = true, ["MSUF_EditState"] = true,
    ["MSUF_EllesmereEditMode_ClearMoveState"] = true, ["MSUF_EllesmereEditMode_IsAvailable"] = true, ["MSUF_EllesmereEditMode_ResumePreview"] = true,
    ["MSUF_EllesmereEditMode_SetEnabled"] = true, ["MSUF_EllesmereEditMode_SuspendPreview"] = true, ["MSUF_EncodeCompactTable"] = true,
    ["MSUF_EndBossCastbarPreviewBatch"] = true, ["MSUF_EnsureCooldownWidthObservers"] = true, ["MSUF_EnsureDB"] = true,
    ["MSUF_EnsureLegacyCooldownViewerAnchor"] = true, ["MSUF_EnsureOptionsLoaded"] = true, ["MSUF_EventBus_Register"] = true,
    ["MSUF_EventBus_Unregister"] = true, ["MSUF_ExportExternal"] = true, ["MSUF_FONT_COLORS"] = true, ["MSUF_FORCE_UPDATE"] = true,
    ["MSUF_FRAME_SHOWN"] = true, ["MSUF_FRAME_STRATA_RANK"] = true, ["MSUF_FocusCastBar"] = true, ["MSUF_FocusKickDriver_ForceUpdate"] = true,
    ["MSUF_FontApplyEpoch"] = true, ["MSUF_FontApplyFailureSerial"] = true, ["MSUF_FontPathEquals"] = true,
    ["MSUF_ForceReanchorAllUnitFrames_Once"] = true, ["MSUF_ForceShowUIPanelButtonPieces"] = true, ["MSUF_ForceTextLayoutForUnitKey"] = true,
    ["MSUF_FormatCastbarTimeText"] = true, ["MSUF_FullChangelog"] = true, ["MSUF_GAMEPLAY_APPLY"] = true, ["MSUF_GF_BlizzardHiddenParent"] = true,
    ["MSUF_GF_BlizzardSmallRaidParent"] = true, ["MSUF_GF_Container_"] = true, ["MSUF_GF_DisableBlizzard"] = true,
    ["MSUF_GF_EM2_IsPreviewShown"] = true, ["MSUF_GF_EM2_SetActivePreviewKind"] = true, ["MSUF_GF_EM2_ShowPreview"] = true,
    ["MSUF_GF_InvalidateConfCache"] = true, ["MSUF_GF_PartyAnchor"] = true, ["MSUF_GF_PartyHeader"] = true, ["MSUF_GF_PriorityAnchor"] = true,
    ["MSUF_GF_PriorityHeader"] = true, ["MSUF_GF_RaidAnchor"] = true, ["MSUF_GF_RaidHeader"] = true, ["MSUF_GF_RebuildAll"] = true,
    ["MSUF_GF_RefreshAll"] = true, ["MSUF_GF_RefreshOverlays"] = true, ["MSUF_GF_RefreshPreviewAnimation"] = true,
    ["MSUF_GF_RefreshPreviewLayout"] = true, ["MSUF_GF_RefreshVisuals"] = true, ["MSUF_GF_ToggleHoveredPriority"] = true,
    ["MSUF_GF_UNIT_IDENTITY"] = true, ["MSUF_GetActiveCooldownAnchorProvider"] = true, ["MSUF_GetAllProfiles"] = true,
    ["MSUF_GetAnchorFrame"] = true, ["MSUF_GetArcUICooldownAnchor"] = true, ["MSUF_GetArenaIndexFromToken"] = true,
    ["MSUF_GetArenaLayoutDelta"] = true, ["MSUF_GetAutomaticCooldownAnchorProvider"] = true, ["MSUF_GetBarBackgroundTexture"] = true,
    ["MSUF_GetBarBackgroundTintRGBA"] = true, ["MSUF_GetBarOutlineColor"] = true, ["MSUF_GetBarTexture"] = true,
    ["MSUF_GetBossIndexFromToken"] = true, ["MSUF_GetBossLayoutDelta"] = true, ["MSUF_GetCastbarBackgroundTexture"] = true,
    ["MSUF_GetCastbarDefaultOffsets"] = true, ["MSUF_GetCastbarDesiredSize"] = true, ["MSUF_GetCastbarDetailTextColor"] = true,
    ["MSUF_GetCastbarFrameLevelOffset"] = true, ["MSUF_GetCastbarPrefix"] = true, ["MSUF_GetCastbarReverseFillForFrame"] = true,
    ["MSUF_GetCastbarTargetNameColor"] = true, ["MSUF_GetCastbarTexture"] = true, ["MSUF_GetCastbarTimeFormat"] = true,
    ["MSUF_GetCastbarTimeFormatDBKey"] = true, ["MSUF_GetCastbarWidthSourceKey"] = true, ["MSUF_GetCharKey"] = true, ["MSUF_GetColorFromKey"] = true,
    ["MSUF_GetColorRGBFromKey"] = true, ["MSUF_GetConfiguredFontColor"] = true, ["MSUF_GetCooldownAnchorConsentDecision"] = true,
    ["MSUF_GetCooldownAnchorScaledWidth"] = true, ["MSUF_GetCoolinatorCooldownAnchor"] = true, ["MSUF_GetCurrentMirrorPage"] = true,
    ["MSUF_GetDefaultPowerColor"] = true, ["MSUF_GetDefaultProfileForNewCharacters"] = true, ["MSUF_GetEffectiveCooldownFrame"] = true,
    ["MSUF_GetEffectiveHealthBarBackgroundTintRGBA"] = true, ["MSUF_GetEllesmereCooldownAnchor"] = true, ["MSUF_GetFontFlags"] = true,
    ["MSUF_GetFontPath"] = true, ["MSUF_GetFontPathForKey"] = true, ["MSUF_GetGeneralDB"] = true, ["MSUF_GetGlobalFontSettings"] = true,
    ["MSUF_GetInterruptFeedbackCastColor"] = true, ["MSUF_GetManagedBindingKeys"] = true, ["MSUF_GetMirrorPages"] = true, ["MSUF_GetNextTip"] = true,
    ["MSUF_GetNumber"] = true, ["MSUF_GetPhysicalPixelSize"] = true, ["MSUF_GetPhysicalScreenRect"] = true, ["MSUF_GetPixelPerfectScale"] = true,
    ["MSUF_GetPlayerSpecID"] = true, ["MSUF_GetPowerBarBackgroundTintRGBA"] = true, ["MSUF_GetPowerBarColor"] = true,
    ["MSUF_GetPreviewAnimationAuraState"] = true, ["MSUF_GetPreviewAnimationFrameState"] = true, ["MSUF_GetProfileScopedCache"] = true,
    ["MSUF_GetResolvedPowerColor"] = true, ["MSUF_GetSkironCooldownAnchorProxy"] = true, ["MSUF_GetSpecProfile"] = true,
    ["MSUF_GetStatusIconAssetValues"] = true, ["MSUF_GetStatusIconPackValues"] = true, ["MSUF_GetSuiteCooldownAnchor"] = true,
    ["MSUF_GetUsableCooldownAnchorSize"] = true, ["MSUF_GlobalCooldownAnchorEnabled"] = true, ["MSUF_GlobalDB"] = true,
    ["MSUF_Grid2EditMode_SetEnabled"] = true, ["MSUF_GroupAdditionalUnitOnLoad"] = true, ["MSUF_GroupAdditionalUnitTemplate"] = true,
    ["MSUF_GroupHeaderUnitButtonTemplate"] = true, ["MSUF_GuidedTour6"] = true, ["MSUF_HideAllCastbarPreviews"] = true,
    ["MSUF_HideStandaloneOptionsWindow"] = true, ["MSUF_HostAPI"] = true, ["MSUF_ImportExternal"] = true, ["MSUF_InitProfiles"] = true,
    ["MSUF_IsArenaUnitToken"] = true, ["MSUF_IsBlizzardCooldownViewerFrameName"] = true, ["MSUF_IsBossUnitToken"] = true,
    ["MSUF_IsConfigCombatLocked"] = true, ["MSUF_IsCooldownAnchorEnabled"] = true, ["MSUF_IsCooldownAnchorSupported"] = true,
    ["MSUF_IsGroupUnitToken"] = true, ["MSUF_IsInAnyEditMode"] = true, ["MSUF_IsInEditMode"] = true, ["MSUF_IsOptionsLoaded"] = true,
    ["MSUF_IsPlayerInCombat"] = true, ["MSUF_IsPreviewAnimationEnabled"] = true, ["MSUF_IsSpecAutoSwitchEnabled"] = true,
    ["MSUF_Keybind_ToggleEditMode"] = true, ["MSUF_Keybind_ToggleOptions"] = true, ["MSUF_Keybind_TogglePriorityFrame"] = true,
    ["MSUF_Keybinds"] = true, ["MSUF_KickReady_RefreshAll"] = true, ["MSUF_L"] = true, ["MSUF_LSM"] = true, ["MSUF_LateAnchorReanchorState"] = true,
    ["MSUF_LeftJustifyButtonText"] = true, ["MSUF_MAX_ARENA_FRAMES"] = true, ["MSUF_MaxFrameStrata"] = true, ["MSUF_Menu2_ApplyService"] = true,
    ["MSUF_NS"] = true, ["MSUF_NSRTNicknames_ApplySetting"] = true, ["MSUF_NormalizeCastbarBackendForUnit"] = true,
    ["MSUF_NormalizeCastbarTimeFormat"] = true, ["MSUF_NormalizeCastbarWidthSource"] = true, ["MSUF_NormalizeFrameStrata"] = true,
    ["MSUF_NormalizePlayerCastbarWidthSource"] = true, ["MSUF_NormalizePortraitClassStyleValue"] = true, ["MSUF_NormalizeProfileDefaults"] = true,
    ["MSUF_NormalizeRaidManagerMode"] = true, ["MSUF_NumberFormat"] = true, ["MSUF_OOC"] = true, ["MSUF_OpenAuras3PositionPopup"] = true,
    ["MSUF_OpenCastbarPositionPopup"] = true, ["MSUF_OpenExactSettingControl"] = true, ["MSUF_OpenOptionsMenu"] = true, ["MSUF_OpenPage"] = true,
    ["MSUF_OpenStandaloneOptionsWindow"] = true, ["MSUF_Optional"] = true, ["MSUF_PREVIEW_NAME"] = true, ["MSUF_PRIORITY_TOGGLE"] = true,
    ["MSUF_PadNavigation"] = true, ["MSUF_PetBattleFrameHider"] = true, ["MSUF_PixelLayoutRegion"] = true,
    ["MSUF_PlayerCastbar_UpdateLatencyZone"] = true, ["MSUF_PositionCastbarPreviewUnit"] = true, ["MSUF_PositionLegacyCooldownViewerAnchor"] = true,
    ["MSUF_PreviewAnimationDriver"] = true, ["MSUF_Preview_Nudge"] = true, ["MSUF_PrintHelp"] = true, ["MSUF_ProfileWasUnboundAtLogin"] = true,
    ["MSUF_Profiles_ExportSelectionToString"] = true, ["MSUF_Profiles_ImportExternal"] = true, ["MSUF_Profiles_ImportFromString"] = true,
    ["MSUF_Profiles_ImportIntoNewProfile"] = true, ["MSUF_PurgeBorderTestMode"] = true, ["MSUF_PurgeBorderTestScope"] = true,
    ["MSUF_RANGE_FORCE"] = true, ["MSUF_RELOAD_RECOMMENDED"] = true, ["MSUF_ReadUnitPowerBarBorderEnabled"] = true,
    ["MSUF_ReadUnitPowerBarBorderThickness"] = true, ["MSUF_ReadUnitPowerBarEmbed"] = true, ["MSUF_ReadUnitPowerBarEnabled"] = true,
    ["MSUF_ReadUnitPowerBarHeight"] = true, ["MSUF_ReanchorArenaCastBar"] = true, ["MSUF_ReanchorBossCastBar"] = true,
    ["MSUF_ReanchorFocusCastBar"] = true, ["MSUF_ReanchorPlayerCastBar"] = true, ["MSUF_ReanchorTargetCastBar"] = true,
    ["MSUF_RefreshAllCastTargetTextColors"] = true, ["MSUF_RefreshAllIdentityColors"] = true, ["MSUF_RefreshAllPowerTextColors"] = true,
    ["MSUF_RefreshAllUnitAlphas"] = true, ["MSUF_RefreshAllUnitVisibilityDrivers"] = true, ["MSUF_RefreshBossPhysicalGeometry"] = true,
    ["MSUF_RefreshCastbarCooldownWidthSource"] = true, ["MSUF_RefreshEliteIconFrames"] = true, ["MSUF_RefreshExternalUnitFrameAnchor"] = true,
    ["MSUF_RefreshHealthBarBackgroundColor"] = true, ["MSUF_RefreshIdentityTextFrames"] = true, ["MSUF_RefreshLeaderIconFrames"] = true,
    ["MSUF_RefreshPingCompatibility"] = true, ["MSUF_RefreshPlayerPowerBar"] = true, ["MSUF_RefreshPlayerResourcePing"] = true,
    ["MSUF_RefreshRaidGroupNameFrames"] = true, ["MSUF_RefreshRaidMarkerFrames"] = true, ["MSUF_RefreshSquareFrameBorderVisual"] = true,
    ["MSUF_RefreshStatusIndicators"] = true, ["MSUF_RefreshUnitDispelOverlays"] = true, ["MSUF_RegisterAnyEditModeListener"] = true,
    ["MSUF_RegisterModule"] = true, ["MSUF_RegisterPreviewAnimationRefreshOwner"] = true, ["MSUF_ReportError"] = true,
    ["MSUF_RequestAlphaRefresh"] = true, ["MSUF_RequestGameplayApply"] = true, ["MSUF_RequestGroupGeometryApply"] = true,
    ["MSUF_RequestPetHappinessIndicatorRefresh"] = true, ["MSUF_RequestPetXPBarRefresh"] = true, ["MSUF_RequestStatusCombatIndicatorRefresh"] = true,
    ["MSUF_RequestStatusIconsRefreshForCurrent"] = true, ["MSUF_RequestStatusIncomingResIndicatorRefresh"] = true,
    ["MSUF_RequestStatusPvpIndicatorRefresh"] = true, ["MSUF_RequestStatusRestingIndicatorRefresh"] = true, ["MSUF_RequestStatusTextRefresh"] = true,
    ["MSUF_RequestThreatIndicatorRefresh"] = true, ["MSUF_Require"] = true, ["MSUF_ResetCastbarGlowFade"] = true, ["MSUF_ResetGlobalUiScale"] = true,
    ["MSUF_ResetProfile"] = true, ["MSUF_ResolveCastbarColors"] = true, ["MSUF_ResolveFontKeyPath"] = true, ["MSUF_ResolveFontShadowMetrics"] = true,
    ["MSUF_ResolveIconTexturePath"] = true, ["MSUF_ResolveInterruptFeedbackCastColor"] = true, ["MSUF_ResolveInterruptUnavailableCastColor"] = true,
    ["MSUF_ResolveSafeFontPath"] = true, ["MSUF_ResolveStatusbarTextureKey"] = true, ["MSUF_RestoreKeys"] = true, ["MSUF_ResumeGuidedTour"] = true,
    ["MSUF_RoundOffset"] = true, ["MSUF_RoundedUF_Active"] = true, ["MSUF_RoundedUF_OnApplyAll"] = true,
    ["MSUF_RoundedUF_OnBorderVisualChanged"] = true, ["MSUF_RoundedUF_OnDispelOverlayChanged"] = true,
    ["MSUF_RoundedUF_OnGroupAuraVisualCreated"] = true, ["MSUF_RoundedUF_OnGroupBlockBorder"] = true, ["MSUF_RoundedUF_OnGroupFrameApplied"] = true,
    ["MSUF_RoundedUF_OnGroupIndicatorChanged"] = true, ["MSUF_RoundedUF_OnGroupIndicatorPrepared"] = true,
    ["MSUF_RoundedUF_OnGroupMouseover"] = true, ["MSUF_RoundedUF_OnModulesApplied"] = true, ["MSUF_RoundedUF_OnPowerBorderChanged"] = true,
    ["MSUF_RoundedUF_OnRareVisualsRefreshed"] = true, ["MSUF_RoundedUF_OnSpellIndicatorEdge"] = true, ["MSUF_RoundedUF_OnUnitMouseover"] = true,
    ["MSUF_RoundedUF_PrepareDispelBorder"] = true, ["MSUF_RoundedUF_PrepareDispelOverlay"] = true, ["MSUF_RunNextFrame"] = true,
    ["MSUF_STARTUP_TRANSPARENCY"] = true, ["MSUF_SUITE_MERCHANT_BUY"] = true, ["MSUF_SUITE_MERCHANT_QUANTITY"] = true,
    ["MSUF_SUITE_MERCHANT_REFUND"] = true, ["MSUF_Scale"] = true, ["MSUF_ScheduleAfter"] = true, ["MSUF_ScheduleCooldownWidthRefresh"] = true,
    ["MSUF_ScheduleLateAnchorReanchor"] = true, ["MSUF_ScheduleOnce"] = true, ["MSUF_SetAlphaIfChanged"] = true,
    ["MSUF_SetArenaCastbarTestMode"] = true, ["MSUF_SetBossCastbarTestMode"] = true, ["MSUF_SetCastTimeText"] = true,
    ["MSUF_SetCooldownAnchorEnabled"] = true, ["MSUF_SetCurrentProfileScreenReferenceHeight"] = true,
    ["MSUF_SetDefaultProfileForNewCharacters"] = true, ["MSUF_SetFocusCastbarTestMode"] = true, ["MSUF_SetFontChecked"] = true,
    ["MSUF_SetGlobalUiScale"] = true, ["MSUF_SetHeightIfChanged"] = true, ["MSUF_SetIconTexture"] = true, ["MSUF_SetJustifyHIfChanged"] = true,
    ["MSUF_SetMSUFEditModeDirect"] = true, ["MSUF_SetManagedBinding"] = true, ["MSUF_SetPlayerCastbarTestMode"] = true,
    ["MSUF_SetPointIfChanged"] = true, ["MSUF_SetRegionPhysicalScreenRect"] = true, ["MSUF_SetRoundLayoutToNearestPixel"] = true,
    ["MSUF_SetSliderValueSilent"] = true, ["MSUF_SetTargetCastbarTestMode"] = true, ["MSUF_SetTextIfChanged"] = true,
    ["MSUF_SetWidthIfChanged"] = true, ["MSUF_ShakeGroup"] = true, ["MSUF_ShortenCastbarSpellName"] = true, ["MSUF_ShouldUseMSUFCastbar"] = true,
    ["MSUF_ShowConfigCombatLockMessage"] = true, ["MSUF_ShowCopyLink"] = true, ["MSUF_ShowGroupFrameReloadRequiredPopup"] = true,
    ["MSUF_ShowReloadRecommendedPopup"] = true, ["MSUF_ShowStandaloneOptionsWindow"] = true, ["MSUF_SkinButton"] = true,
    ["MSUF_SkironCooldownAnchor"] = true, ["MSUF_Snap"] = true, ["MSUF_SnapshotFrameToUIParentCenter"] = true, ["MSUF_StartGuidedTour"] = true,
    ["MSUF_Suite"] = true, ["MSUF_Suite_Chat"] = true, ["MSUF_Suite_CooldownManager"] = true, ["MSUF_Suite_Locale_"] = true,
    ["MSUF_Suite_Modules"] = true, ["MSUF_Suite_Options"] = true, ["MSUF_Suite_QualityOfLife"] = true, ["MSUF_Suite_Skin"] = true,
    ["MSUF_SwingTimer_"] = true, ["MSUF_SwitchMirrorPage"] = true, ["MSUF_SwitchProfile"] = true, ["MSUF_SyncAllUnitPreviews"] = true,
    ["MSUF_SyncAllUnitPreviewsAsync"] = true, ["MSUF_SyncArenaUnitframePreviewWithUnitEdit"] = true, ["MSUF_SyncAuras3PositionPopup"] = true,
    ["MSUF_SyncBossUnitframePreviewWithUnitEdit"] = true, ["MSUF_SyncCastbarPositionPopup"] = true, ["MSUF_SyncFrameLayerAbove"] = true,
    ["MSUF_SyncUnitPositionPopup"] = true, ["MSUF_TOGGLE_EDITMODE"] = true, ["MSUF_TOGGLE_OPTIONS"] = true, ["MSUF_TargetCastBar"] = true,
    ["MSUF_TargetSoundDriver_ApplySetting"] = true, ["MSUF_TogglePreviewAnimation"] = true, ["MSUF_ToggleProfileVariant"] = true,
    ["MSUF_Tooltip_IsBlizzardControlled"] = true, ["MSUF_TryCloseExternalEditMode"] = true, ["MSUF_TryDecodeCompactString"] = true,
    ["MSUF_TryOpenExternalEditMode"] = true, ["MSUF_UFCore_GetClassBarColorFast"] = true, ["MSUF_UFCore_GetNPCReactionColorFast"] = true,
    ["MSUF_UFCore_GetSettingsCache"] = true, ["MSUF_UFCore_NotifyConfigChanged"] = true, ["MSUF_UFPreview"] = true,
    ["MSUF_UFPreview_ActiveNudgeBox"] = true, ["MSUF_UFPreview_RequestRefresh"] = true, ["MSUF_UF_ApplyCastbarRangeAlpha"] = true,
    ["MSUF_UF_ApplyRangeModifier"] = true, ["MSUF_UF_ClampAnchorOffsetOnScreen"] = true, ["MSUF_UF_FrameRectToUI"] = true,
    ["MSUF_UF_PointFraction"] = true, ["MSUF_UF_ShapeOutlineAlpha"] = true, ["MSUF_UI"] = true, ["MSUF_UNIT_CHANGED_AURAS"] = true,
    ["MSUF_UNIT_IDENTITY_FAST"] = true, ["MSUF_UnitEditModeActive"] = true, ["MSUF_UnitFrames"] = true, ["MSUF_UnitFramesList"] = true,
    ["MSUF_UnitMenuPlayer"] = true, ["MSUF_UnitMenuTarget"] = true, ["MSUF_Unknown"] = true, ["MSUF_UpdateAllBarGradients"] = true,
    ["MSUF_UpdateAllBarTextures"] = true, ["MSUF_UpdateAllBarTextures_Immediate"] = true, ["MSUF_UpdateAllExternalAnchorProxies"] = true,
    ["MSUF_UpdateAllFonts"] = true, ["MSUF_UpdateAllFonts_Immediate"] = true, ["MSUF_UpdateArenaCastbarPreview"] = true,
    ["MSUF_UpdateBossCastbarPreview"] = true, ["MSUF_UpdateCastbarEditInfo"] = true, ["MSUF_UpdateCastbarTextures"] = true,
    ["MSUF_UpdateCastbarTextures_Immediate"] = true, ["MSUF_UpdateCastbarVisuals"] = true, ["MSUF_UpdateCastbarVisuals_Immediate"] = true,
    ["MSUF_UpdateCastbarWidthSourceSync"] = true, ["MSUF_UpdatePixelPerfect"] = true, ["MSUF_UpdatePlayerCastbarPreview"] = true,
    ["MSUF_Util"] = true, ["MSUF_VARIANT_1"] = true, ["MSUF_VARIANT_2"] = true, ["MSUF_VARIANT_3"] = true, ["MSUF_VARIANT_4"] = true,
    ["MSUF_VARIANT_5"] = true, ["MSUF_VARIANT_6"] = true, ["MSUF_VARIANT_7"] = true, ["MSUF_VARIANT_8"] = true, ["MSUF_VISUALS"] = true,
    ["MSUF_arena"] = true, ["MSUF_arena1"] = true, ["MSUF_arena2"] = true, ["MSUF_arena3"] = true, ["MSUF_arena4"] = true, ["MSUF_arena5"] = true,
    ["MSUF_boss"] = true, ["MSUF_boss1"] = true, ["MSUF_boss2"] = true, ["MSUF_boss3"] = true, ["MSUF_boss4"] = true, ["MSUF_boss5"] = true,
    ["MSUF_focus"] = true, ["MSUF_focustarget"] = true, ["MSUF_pet"] = true, ["MSUF_pettarget"] = true, ["MSUF_player"] = true,
    ["MSUF_target"] = true, ["MSUF_targettarget"] = true, ["MSUF_tot"] = true, ["SLASH_MIDNIGHTSUF1"] = true, ["SLASH_MSUF2OPTIONS1"] = true,
    ["SLASH_MSUFAURALAYERS1"] = true, ["SLASH_MSUFDBGPOS1"] = true, ["SLASH_MSUFGROUPPULSE1"] = true, ["SLASH_MSUFMENUCHECK1"] = true,
    ["SLASH_MSUFOPTIONS1"] = true, ["SLASH_MSUFRELOADUI1"] = true, ["SLASH_MSUFSUITEINSTALL1"] = true, ["SLASH_MSUFSUITERUNS1"] = true,
    ["UpdateAllBarTextures"] = true, ["_MSUF_Clamp"] = true, ["_MSUF_CombatTimerModifierFrame"] = true, ["_MSUF_RoundInt"] = true,
    ["_MSUF_SetAtlasOrFallback"] = true, ["__MSUF_CP_Balance_Loaded"] = true, ["__MSUF_ClassPower_Loaded"] = true, ["__MSUF_FocusKickUIInit"] = true,
    ["MSUF2NativeDropdownScroll"] = false, ["MSUF2_ArenaUnitframePreviewActive"] = false, ["MSUF2_BossUnitframePreviewActive"] = false,
    ["MSUF2_CastbarPagePreviewUnit"] = false, ["MSUF2_ClassPowerQuickSetup"] = false, ["MSUF_AbsorbTextureTestMode"] = false,
    ["MSUF_AbsorbTextureTestScope"] = false, ["MSUF_AltManaContainer"] = false, ["MSUF_Analytics_IsEnabled"] = false,
    ["MSUF_Analytics_SetEnabled"] = false, ["MSUF_AnchorPicker"] = false, ["MSUF_AnchorPickerHighlight"] = false,
    ["MSUF_AnyEditModeListeners"] = false, ["MSUF_ApplyDispelOverlayPreviewToFrame"] = false, ["MSUF_ApplyDispelSymbolPreviewToFrame"] = false,
    ["MSUF_ApplyDropdownStyleModeImmediate"] = false, ["MSUF_ApplyGameplayFontFromGlobal"] = false, ["MSUF_ApplyGameplayVisuals"] = false,
    ["MSUF_ApplyLeaderIconLayout"] = false, ["MSUF_ApplyMidnightBackdrop"] = false, ["MSUF_ApplyMidnightControlsToFrame"] = false,
    ["MSUF_ApplyPeelOptionsSkin"] = false, ["MSUF_ApplyPlayerChannelTickMarkers"] = false, ["MSUF_ApplyPowerBarEmbedLayout"] = false,
    ["MSUF_ApplyRaidMarkerLayout"] = false, ["MSUF_ApplyResolvedFont"] = false, ["MSUF_ApplyTooltipCasterNames"] = false,
    ["MSUF_ApplyTooltipSpellIDs"] = false, ["MSUF_ApplyUnitFrameKey_Immediate"] = false, ["MSUF_ArenaTestMode"] = false, ["MSUF_AuraCore"] = false,
    ["MSUF_AuraReadParentFrameStrata"] = false, ["MSUF_AuraSpellIDFromKey"] = false, ["MSUF_AuraSyncFrameStrata"] = false,
    ["MSUF_AuraTableHasAnyKey"] = false, ["MSUF_Auras3"] = false, ["MSUF_BAL_InvalidateColors"] = false, ["MSUF_BAL_RefreshRuntime"] = false,
    ["MSUF_BUNDLED_FONTS_REGISTERED"] = false, ["MSUF_BUNDLED_MEDIA_REGISTRATION_DEFERRED"] = false, ["MSUF_BlizzEditModeStartedByMSUF"] = false,
    ["MSUF_BorderTestModesActive"] = false, ["MSUF_BossTestMode"] = false, ["MSUF_BuildMeleeSpellCache"] = false,
    ["MSUF_CP_FEATURE_BUILDERS"] = false, ["MSUF_CP_GetTrackedPlayerAura"] = false, ["MSUF_CP_MODE_BUILDERS"] = false,
    ["MSUF_CP_MODE_EVENT_PROFILE"] = false, ["MSUF_CastbarBackend"] = false, ["MSUF_CastbarEngine"] = false, ["MSUF_CastbarRuntime"] = false,
    ["MSUF_CastbarStyle"] = false, ["MSUF_CastbarStyleRevision"] = false, ["MSUF_CastbarUpdateInterval"] = false,
    ["MSUF_ClassPowerPlayerHealthBar"] = false, ["MSUF_ClassPower_ApplyFonts"] = false, ["MSUF_ClassPower_EnsureEditModeAnchor"] = false,
    ["MSUF_ClassPower_InvalidateColors"] = false, ["MSUF_ClassPower_IsRuntimeActive"] = false, ["MSUF_ClassPower_Refresh"] = false,
    ["MSUF_ClassPower_RefreshLayout"] = false, ["MSUF_ClassPower_RefreshTextures"] = false, ["MSUF_ClearAbsorbTextureTestMode"] = false,
    ["MSUF_CollectFrameStrataRows"] = false, ["MSUF_CollectLayerOverviewRows"] = false, ["MSUF_ComposeFontFlags"] = false,
    ["MSUF_Core_RunNextFrame"] = false, ["MSUF_CreateCanonicalGroupAuraState"] = false, ["MSUF_CreateCanonicalPlayerDefensiveAuraContainer"] = false,
    ["MSUF_CreateCanonicalUnitAuras"] = false, ["MSUF_CreateStyledDropdown"] = false, ["MSUF_CurrentEditUnitKey"] = false,
    ["MSUF_DARK_TONES"] = false, ["MSUF_DandersEditMode_IsAvailable"] = false, ["MSUF_DebugFontProbe"] = false, ["MSUF_DeleteProfiles"] = false,
    ["MSUF_DetachedGCDBar"] = false, ["MSUF_DetachedPowerBar_RefreshTextures"] = false, ["MSUF_DetailsEditMode_IsAvailable"] = false,
    ["MSUF_DispelOverlayPreviewMode"] = false, ["MSUF_DispelOverlayPreviewScope"] = false, ["MSUF_DispelSymbolPreviewMode"] = false,
    ["MSUF_DispelSymbolPreviewScope"] = false, ["MSUF_DominosEditMode_IsAvailable"] = false, ["MSUF_EM2_ActiveAuraGroup"] = false,
    ["MSUF_EM2_ActiveAuraUnit"] = false, ["MSUF_EM2_ActivePreviewNudgeTarget"] = false, ["MSUF_EM2_ClearFocusHover"] = false,
    ["MSUF_EM2_ClearPopupFocus"] = false, ["MSUF_EM2_GFPopupIsOpen"] = false, ["MSUF_EM2_Grid"] = false, ["MSUF_EM2_HUD_LayoutEvents"] = false,
    ["MSUF_EM2_HUD_PreviewAddonSlot"] = false, ["MSUF_EM2_HideGFPopup"] = false, ["MSUF_EM2_HoverPreviewRing"] = false,
    ["MSUF_EM2_LogoIntro"] = false, ["MSUF_EM2_Menu2Style"] = false, ["MSUF_EM2_MenuFocusRequest"] = false, ["MSUF_EM2_MenuFocusSection"] = false,
    ["MSUF_EM2_NudgeOwner"] = false, ["MSUF_EM2_OpenFocusSettings"] = false, ["MSUF_EM2_PulseFocus"] = false,
    ["MSUF_EM2_RefreshGFHistoryControls"] = false, ["MSUF_EM2_Selection"] = false, ["MSUF_EM2_SetFocusHover"] = false,
    ["MSUF_EM2_SetPopupFocus"] = false, ["MSUF_EM2_ShowGFPopup"] = false, ["MSUF_EM2_SnapGuideFade"] = false, ["MSUF_EM2_SnapGuides"] = false,
    ["MSUF_EM2_SyncFocusInspector"] = false, ["MSUF_EM2_TickerFrame"] = false, ["MSUF_EM_RefreshAfterHistoryRestore"] = false,
    ["MSUF_EM_RefreshHistoryControls"] = false, ["MSUF_EM_UndoBeginChange"] = false, ["MSUF_EM_UndoClear"] = false,
    ["MSUF_EM_UndoCommitChange"] = false, ["MSUF_EM_UndoRedo"] = false, ["MSUF_EM_UndoUndo"] = false, ["MSUF_EditModeGridTools"] = false,
    ["MSUF_EditModeRedoBtn"] = false, ["MSUF_EditModeUndoBtn"] = false, ["MSUF_EnableArrowKeyNudge"] = false,
    ["MSUF_EncodeCompactTableMSUF3"] = false, ["MSUF_EnsureAddonLoaded"] = false, ["MSUF_EnsureAnchorPicker"] = false,
    ["MSUF_EnsureDB_Heavy"] = false, ["MSUF_EnsureGameplayDefaults"] = false, ["MSUF_EventBus"] = false, ["MSUF_EventBus_UnregisterAll"] = false,
    ["MSUF_ExportCompat"] = false, ["MSUF_ExportPublic"] = false, ["MSUF_ExportSelectionToString"] = false,
    ["MSUF_ExternalAnchorForceReanchor"] = false, ["MSUF_FACTORY_DEFAULT_PROFILE_COMPACT"] = false, ["MSUF_FONT_LIST"] = false,
    ["MSUF_FOREVER_FACTORY_DEFAULT_PROFILE_COMPACT"] = false, ["MSUF_FetchFontPathFromLSM"] = false, ["MSUF_FixMouseoverHighlightBindings"] = false,
    ["MSUF_FocusKickIcon"] = false, ["MSUF_FocusKickPreviewFrame"] = false, ["MSUF_FocusKick_ApplyTimeTextFont"] = false,
    ["MSUF_FocusKick_IsPreviewEnabled"] = false, ["MSUF_FocusKick_SetPreviewEnabled"] = false, ["MSUF_FontApplicationMatches"] = false,
    ["MSUF_FontLooksLikeBundledExpressway"] = false, ["MSUF_FontPathKey"] = false, ["MSUF_FontPathMatches"] = false, ["MSUF_FontPathSerial"] = false,
    ["MSUF_FrameUpdateInterval"] = false, ["MSUF_GCDBarDriver"] = false, ["MSUF_GCDBar_IsSupported"] = false, ["MSUF_GCDBar_RefreshLayout"] = false,
    ["MSUF_GameMenuButton"] = false, ["MSUF_GameplayShared"] = false, ["MSUF_Gameplay_ApplyCombatStatePosition"] = false,
    ["MSUF_Gameplay_ApplyCombatTimerAnchorFn"] = false, ["MSUF_Gameplay_ApplyFontToCounter"] = false, ["MSUF_Gameplay_ApplyLockState"] = false,
    ["MSUF_Gameplay_PlayerTotems_Apply"] = false, ["MSUF_Gameplay_TickCombatTimer"] = false, ["MSUF_GetAssistStatusIconTexture"] = false,
    ["MSUF_GetCastbarBackend"] = false, ["MSUF_GetCastbarBackgroundColor"] = false, ["MSUF_GetCastbarTextColor"] = false,
    ["MSUF_GetClassBarColor"] = false, ["MSUF_GetCombatStateColors"] = false, ["MSUF_GetCombatTimerAnchorFrame"] = false,
    ["MSUF_GetCombatTimerFrame"] = false, ["MSUF_GetDefaultUnitOffsets"] = false, ["MSUF_GetDropdownStyleMode"] = false,
    ["MSUF_GetEmpowerStageBlinkTime"] = false, ["MSUF_GetFontPreviewObject"] = false, ["MSUF_GetGameplayDBFast"] = false,
    ["MSUF_GetGameplayFontSettings"] = false, ["MSUF_GetInternalFontPathByKey"] = false, ["MSUF_GetInternalFontPrimaryPath"] = false,
    ["MSUF_GetLeaderStatusIconTexture"] = false, ["MSUF_GetMeleeSpellCache"] = false, ["MSUF_GetNPCReactionColor"] = false,
    ["MSUF_GetPetHappinessIcon"] = false, ["MSUF_GetRawLSMFontPath"] = false, ["MSUF_GetRegisteredLSMFontPath"] = false,
    ["MSUF_GetRoleStatusIconTexture"] = false, ["MSUF_GetSavedMsufScale"] = false, ["MSUF_GetSharedMedia"] = false,
    ["MSUF_GetStatusIconTexture"] = false, ["MSUF_Grid2EditMode_IsAvailable"] = false, ["MSUF_GridFrame"] = false,
    ["MSUF_GroupPreview_NudgeHandle"] = false, ["MSUF_GroupPreview_Pan"] = false, ["MSUF_HideLayerOverviewForAnchor"] = false,
    ["MSUF_HidePlayerInfoTooltip"] = false, ["MSUF_HighlightDebug"] = false, ["MSUF_ImportFromString"] = false,
    ["MSUF_ImportIntoNewProfile"] = false, ["MSUF_InCombat"] = false, ["MSUF_InstallGlobalScaleGate"] = false,
    ["MSUF_InterruptReady_EventFrame"] = false, ["MSUF_IsAvailableFontPath"] = false, ["MSUF_IsEmpowerStageBlinkEnabled"] = false,
    ["MSUF_IsInternalFontKey"] = false, ["MSUF_IsKnownFileAsset"] = false, ["MSUF_IsRegisteredLSMFontPath"] = false,
    ["MSUF_KickReady_ApplyLayout"] = false, ["MSUF_KickReady_EvaluateRGBA"] = false, ["MSUF_KickReady_GetReadyBoolForTint"] = false,
    ["MSUF_KickReady_GetSpellID"] = false, ["MSUF_KickReady_Init"] = false, ["MSUF_KickReady_IsReady"] = false,
    ["MSUF_KickReady_NotifySettings"] = false, ["MSUF_KickReady_RefreshFrame"] = false, ["MSUF_KickReady_RefreshOutline"] = false,
    ["MSUF_KickReady_SelectColor"] = false, ["MSUF_LSM_CallbacksRegistered"] = false, ["MSUF_MODERN_DARK_PROFILE_COMPACT"] = false,
    ["MSUF_MarkFontApplyFailed"] = false, ["MSUF_MaterializeUnitAuraLaneOwners"] = false, ["MSUF_MaybeShowGameplayColorsTip"] = false,
    ["MSUF_Menu2_CreateUnitPreviewBox"] = false, ["MSUF_MigrateDispelPriorityProfile"] = false, ["MSUF_MigrateDispelPriorityProfiles"] = false,
    ["MSUF_MinimapButton"] = false, ["MSUF_Modules"] = false, ["MSUF_ModulesByKey"] = false, ["MSUF_Namespace"] = false,
    ["MSUF_NormalizeAuraDebuffTypeBorderMode"] = false, ["MSUF_NormalizeCastbarBackend"] = false, ["MSUF_NormalizeCastbarIconPosition"] = false,
    ["MSUF_NormalizeCastbarTextJustify"] = false, ["MSUF_NormalizeCastbarTextPosition"] = false, ["MSUF_NormalizeCastbarTruncate"] = false,
    ["MSUF_NormalizeDispelBorderTrigger"] = false, ["MSUF_NormalizeFontFlags"] = false, ["MSUF_NormalizeFontKey"] = false,
    ["MSUF_NormalizeFontPath"] = false, ["MSUF_NormalizeLegacyDispelBorderMode"] = false, ["MSUF_NormalizeNumericLayers"] = false,
    ["MSUF_NormalizePortraitRenderDB"] = false, ["MSUF_NormalizeProfileTo60Defaults"] = false, ["MSUF_NormalizeRGB"] = false,
    ["MSUF_NormalizeStoredFontKeys"] = false, ["MSUF_OnFontApplyFailed"] = false, ["MSUF_OnLSMReady"] = false, ["MSUF_PeelDropdownDefaults"] = false,
    ["MSUF_PeelDropdownTemplate"] = false, ["MSUF_PendingSpecProfileSwitch"] = false, ["MSUF_PlayEditModeLogoIntro"] = false,
    ["MSUF_PlayerCastBar"] = false, ["MSUF_PlayerInfoFrame"] = false, ["MSUF_PlayerTotemsBlizzardEventFrame"] = false,
    ["MSUF_PlayerTotemsPreviewFrame"] = false, ["MSUF_PlayerTotems_ForceRefresh"] = false, ["MSUF_PlayerTotems_IsPreviewActive"] = false,
    ["MSUF_PlayerTotems_TogglePreview"] = false, ["MSUF_PositionGameMenuButton"] = false, ["MSUF_PredictionTestModes"] = false,
    ["MSUF_PreviewTestMode"] = false, ["MSUF_ProfileIO_GetLastImportWarnings"] = false, ["MSUF_ProfileIO_LastImportWarnings"] = false,
    ["MSUF_ProfileIO_TranslateProfileToCurrent"] = false, ["MSUF_ProfileIO_TranslateProfilesToCurrent"] = false,
    ["MSUF_Profiles_ExportExternal"] = false, ["MSUF_Profiles_SetExportBlizzardEditMode"] = false, ["MSUF_Profiles_SetExportVariants"] = false,
    ["MSUF_Profiles_SetImportBlizzardEditMode"] = false, ["MSUF_Profiles_SetImportVariants"] = false, ["MSUF_PublicKey"] = false,
    ["MSUF_QueueDropdownStyleMode"] = false, ["MSUF_QuickSetup_ResetFirstRun"] = false, ["MSUF_RefreshAllFrameColors"] = false,
    ["MSUF_RefreshAllFrames"] = false, ["MSUF_RefreshDispelOverlayPreview"] = false, ["MSUF_RefreshDispelSymbolPreview"] = false,
    ["MSUF_RefreshDropdownSkinMode"] = false, ["MSUF_RefreshMouseoverHighlight"] = false, ["MSUF_RefreshPredictionBars"] = false,
    ["MSUF_RefreshStatusIconPacks"] = false, ["MSUF_RefreshTempMaxHealth"] = false, ["MSUF_RefreshUnitDispelOverlay"] = false,
    ["MSUF_RefreshUnitTextureLayers"] = false, ["MSUF_RegisterBundledMediaWithLSM"] = false, ["MSUF_RegisterStatusIconPack"] = false,
    ["MSUF_RenameProfile"] = false, ["MSUF_RequestFontRecovery"] = false, ["MSUF_ResetCastbarDetailTextColor"] = false,
    ["MSUF_ResetStandaloneWindowGeometry"] = false, ["MSUF_ReskinDropdownLists"] = false, ["MSUF_ResolveFontPath"] = false,
    ["MSUF_RestoreBlizzardUiScale"] = false, ["MSUF_RevertDropdownTemplate"] = false, ["MSUF_RoundedCastbar_RenderPreview"] = false,
    ["MSUF_SPACING"] = false, ["MSUF_STYLE"] = false, ["MSUF_ScaleReanchorPending"] = false, ["MSUF_ScheduleMouseoverHighlightFix"] = false,
    ["MSUF_Scheduler"] = false, ["MSUF_SchedulerFrame"] = false, ["MSUF_SerializeDB"] = false, ["MSUF_SetAbsorbTextureTestMode"] = false,
    ["MSUF_SetAggroBorderTestMode"] = false, ["MSUF_SetBlizzardEditModeFromMSUF"] = false, ["MSUF_SetBossTargetBorderTestMode"] = false,
    ["MSUF_SetCastbarBackend"] = false, ["MSUF_SetCastbarDetailTextColor"] = false, ["MSUF_SetDispelBorderTestMode"] = false,
    ["MSUF_SetDispelOverlayPreview"] = false, ["MSUF_SetDispelSymbolPreview"] = false, ["MSUF_SetDispelSymbolPreviewMoveHandler"] = false,
    ["MSUF_SetDropdownStyleMode"] = false, ["MSUF_SetEnabledMeleeRangeCheck"] = false, ["MSUF_SetGCDBarEnabled"] = false,
    ["MSUF_SetGameMenuButtonEnabled"] = false, ["MSUF_SetLayerOverviewValue"] = false, ["MSUF_SetMinimapIconEnabled"] = false,
    ["MSUF_SetMinimapIconPosition"] = false, ["MSUF_SetPurgeBorderTestMode"] = false, ["MSUF_SetScalingDisabled"] = false,
    ["MSUF_SetSpecAutoSwitchEnabled"] = false, ["MSUF_SetSpecProfile"] = false, ["MSUF_SetStrataOverviewValue"] = false,
    ["MSUF_SetStyleEnabled"] = false, ["MSUF_ShouldShowAbsorbTextureTest"] = false, ["MSUF_ShowClientVersionWarning"] = true,
    ["MSUF_ShowFocusInfoTooltip"] = false, ["MSUF_ShowFocusTargetInfoTooltip"] = false, ["MSUF_ShowLayerOverview"] = false,
    ["MSUF_ShowPetInfoTooltip"] = false, ["MSUF_ShowPetTargetInfoTooltip"] = false, ["MSUF_ShowPlayerInfoTooltip"] = false,
    ["MSUF_ShowTargetInfoTooltip"] = false, ["MSUF_ShowTargetTargetInfoTooltip"] = false, ["MSUF_ShowUnitInfoTooltip"] = false,
    ["MSUF_ShowWelcomeMessage"] = true, ["MSUF_SkinDashboardButton"] = false, ["MSUF_SkinMuted"] = false, ["MSUF_SkinNavButton"] = false,
    ["MSUF_SkinText"] = false, ["MSUF_SkinTitle"] = false, ["MSUF_Space"] = false, ["MSUF_SpecProfileDeferFrame"] = false,
    ["MSUF_SpecProfileEventFrame"] = false, ["MSUF_SplitStatusIconStyle"] = false, ["MSUF_StandaloneOptionsWindow"] = false,
    ["MSUF_StatusBarTextureItems"] = false, ["MSUF_StatusIconPackSupports"] = false, ["MSUF_StopEditModeLogoIntro"] = false, ["MSUF_Style"] = false,
    ["MSUF_StyleAllToggles"] = false, ["MSUF_StyleIsEnabled"] = false, ["MSUF_SuppressBlizzardPlayerCastbars"] = false, ["MSUF_THEME"] = false,
    ["MSUF_TargetSoundDriver_Disable"] = false, ["MSUF_TargetSoundDriver_Ensure"] = false, ["MSUF_TargetSoundDriver_ResetState"] = false,
    ["MSUF_TooltipDragHandle"] = false, ["MSUF_TooltipMiniSettingsPopup"] = false, ["MSUF_Tooltip_HideEditPreview"] = false,
    ["MSUF_Tooltip_ResetPosition"] = false, ["MSUF_Tooltip_ShowEditPreview"] = false, ["MSUF_UFCore_RefreshHealthBarColor"] = false,
    ["MSUF_UFCore_RefreshSettingsCache"] = false, ["MSUF_UFPreview_ClearTextFocus"] = false, ["MSUF_UFPreview_FocusTextSlot"] = false,
    ["MSUF_UFPreview_GetStatusPreviewMode"] = false, ["MSUF_UFPreview_NudgeHandle"] = false, ["MSUF_UFPreview_Pan"] = false,
    ["MSUF_UFPreview_SelectStatusIcon"] = false, ["MSUF_UFPreview_SetStatusPreviewMode"] = false, ["MSUF_UF_ClampBoxAxis"] = false,
    ["MSUF_UF_MaskHas"] = false, ["MSUF_UF_NormalizeClassPowerShape"] = false, ["MSUF_UF_NormalizeDetachedPowerShape"] = false,
    ["MSUF_UF_NormalizePlayerHPShape"] = false, ["MSUF_UF_NormalizeShapeAlign"] = false, ["MSUF_UF_OutlineModeEnabled"] = false,
    ["MSUF_UF_RangeFade_Refresh"] = false, ["MSUF_UF_ScheduleApplyCommit"] = false, ["MSUF_UnitFrameSizeBounds"] = false,
    ["MSUF_UnitMenuBindingOwner"] = false, ["MSUF_UnitPreviewActive"] = false, ["MSUF_UpdateAbsorbBarTextures"] = false,
    ["MSUF_UpdateAbsorbDisplayMode"] = false, ["MSUF_UpdateFocusKickIconOptions"] = false, ["MSUF_VersionCheck_DebugFakeUpdate"] = false,
    ["MSUF__UndoRestoring"] = false, ["__MSUF_STYLE_TAG"] = false, ["__MSUF_STYLE_VERSION"] = false,
}

-- Families of native frame, binding and integration names.
local GlobalExportPrefixes = {
    "BINDING_HEADER_MSUFSUITE_BAR",
    "BINDING_NAME_",
    "BINDING_NAME_MSUFSUITE_BAR",
    "BINDING_NAME_MSUFSUITE_TOGGLE_BAR",
    "BINDING_NAME_MSUF_VARIANT_",
    "MSUFSuiteBar",
    "MSUF_ArenaStealthOverlay",
    "MSUF_ArenaTrinket",
    "MSUF_BossCastbar",
    "MSUF_GF_",
    "MSUF_GF_Container_",
    "MSUF_GF_PartyHeader",
    "MSUF_GF_PriorityHeader",
    "MSUF_GF_RaidHeader",
    "MSUF_Suite_Locale_",
    "MSUF_SwingTimer_",
    "MSUF_arena",
    "MSUF_boss",
    "SLASH_",
}

function MSUF.MSUF_ExportPublic(name, value, publishGlobal)
    local key = PublicKey(name)
    if key then
        MSUF.Public[key] = value
        MSUF.PublicGlobals[name] = value
    end
    if publishGlobal ~= false and type(name) == "string" and name ~= "" then
        local allowed = GlobalExports[name]
        if allowed == nil then
            allowed = false
            for i = 1, #GlobalExportPrefixes do
                local prefix = GlobalExportPrefixes[i]
                if name:sub(1, #prefix) == prefix then
                    allowed = true
                    break
                end
            end
            GlobalExports[name] = allowed
        end
        if allowed then
            _G[name] = value
            MSUF.Compat.LegacyGlobals[name] = true
        end
    end
    return value
end

MSUF.ExportPublic = MSUF.MSUF_ExportPublic
MSUF.ExportGlobal = MSUF.MSUF_ExportPublic

function MSUF.MSUF_ExportCompat(name, fallback)
    local existing
    if type(name) == "string" then existing = _G[name] end
    if existing ~= nil then
        return MSUF.MSUF_ExportPublic(name, existing, false)
    end
    return MSUF.MSUF_ExportPublic(name, fallback, true)
end

MSUF.ExportCompat = MSUF.MSUF_ExportCompat

