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
-- Active ExportPublic policy; regenerate from reviewed contracts.
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
    -- bare runtime flag
    MSUF_AggroBorderTestMode = true,
    -- bare runtime flag
    MSUF_AggroBorderTestScope = true,
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
    -- documented /run
    MSUF_BlizzardEditMode_Debug = true,
    -- documented /run
    MSUF_BlizzardEditMode_EnsureLayout = true,
    -- bare runtime flag
    MSUF_BossTargetBorderTestMode = true,
    -- bare runtime flag
    MSUF_BossTargetBorderTestScope = true,
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
    -- bare runtime flag
    MSUF_DispelBorderTestMode = true,
    -- bare runtime flag
    MSUF_DispelBorderTestScope = true,
    -- Suite reader
    -- reviewed suite,external
    MSUF_EM2 = true,
    -- native SetOverrideBindingClick target
    MSUF_EM2_NudgeDOWN = true,
    -- native SetOverrideBindingClick target
    MSUF_EM2_NudgeLEFT = true,
    -- native SetOverrideBindingClick target
    MSUF_EM2_NudgeRIGHT = true,
    -- native SetOverrideBindingClick target
    MSUF_EM2_NudgeUP = true,
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
    -- Forever gamepad named container reader
    MSUF_GF_Container_mythicraid = true,
    -- Forever gamepad named container reader
    MSUF_GF_Container_party = true,
    -- Forever gamepad named container reader
    MSUF_GF_Container_priority = true,
    -- Forever gamepad named container reader
    MSUF_GF_Container_raid = true,
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
    -- documented /run
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
    -- bare runtime flag
    MSUF_PurgeBorderTestMode = true,
    -- bare runtime flag
    MSUF_PurgeBorderTestScope = true,
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

-- Generated compatibility names are the only ExportPublic aliases in _G.
local GlobalExports = MSUF.Compat.GlobalKeep
function MSUF.MSUF_ExportPublic(name, value, publishGlobal)
    local key = PublicKey(name)
    if key then
        MSUF.Public[key] = value
        MSUF.PublicGlobals[name] = value
    end
    if publishGlobal ~= false and type(name) == "string" and name ~= "" then
        if GlobalExports[name] then
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
    if type(name) == "string" then
        existing = _G[name]
        if existing == nil then existing = MSUF.PublicGlobals[name] end
    end
    if existing ~= nil then
        return MSUF.MSUF_ExportPublic(name, existing, false)
    end
    return MSUF.MSUF_ExportPublic(name, fallback, true)
end

MSUF.ExportCompat = MSUF.MSUF_ExportCompat

