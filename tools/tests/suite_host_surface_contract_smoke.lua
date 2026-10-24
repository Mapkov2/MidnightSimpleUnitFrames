-- Suite host contracts on the real Mainline/Forever graph; no external addon is needed.
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client flavor required")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local world = World.New(root, flavor)
world:Boot()
local failure = world:FirstFailure()
assert(not failure, "host load failed: " .. tostring(failure and failure.file))
local env, host, menu = world.env, world.core, world.options.MSUF2

-- Pin the current Suite readers, including names passed through adapter tables.
local PUBLIC_NAMES = {
    "MSUF",
    "MSUF2",
    "MSUF2.ALIASES",
    "MSUF2.AddNavIcon",
    "MSUF2.AddTooltip",
    "MSUF2.AllowCombatClick",
    "MSUF2.ApplyPopupFramePriority",
    "MSUF2.BeginHistoryTransaction",
    "MSUF2.BindBoolWidget",
    "MSUF2.BindDropdownAt",
    "MSUF2.BindSegment",
    "MSUF2.BindSwitchAt",
    "MSUF2.BindTextInputAt",
    "MSUF2.BuildPageResetWarning",
    "MSUF2.CancelHistoryTransaction",
    "MSUF2.CommitHistoryTransaction",
    "MSUF2.ControlMeta",
    "MSUF2.CreateMenuPopupPanel",
    "MSUF2.GetControlLabel",
    "MSUF2.GetControlSearchMeta",
    "MSUF2.GetControlTitle",
    "MSUF2.GetHistoryState",
    "MSUF2.GetMissingSectionResolver",
    "MSUF2.GetRawSetText",
    "MSUF2.GetSearchTargetPrepare",
    "MSUF2.GetSectionCursor",
    "MSUF2.GetSectionEnsureVisible",
    "MSUF2.GetSectionEntry",
    "MSUF2.GetSectionRefreshState",
    "MSUF2.GetSectionWidth",
    "MSUF2.GlobalPage",
    "MSUF2.HOST_API_VERSION",
    "MSUF2.IconSkinsPage",
    "MSUF2.InvalidatePage",
    "MSUF2.InvalidateSearchProvider",
    "MSUF2.IsHistoryCapturing",
    "MSUF2.MarkContextColorHost",
    "MSUF2.MenuTimer",
    "MSUF2.OpenExactSettingControl",
    "MSUF2.PageHasReset",
    "MSUF2.PreviewHelpers",
    "MSUF2.PreviewSelectionBar",
    "MSUF2.RebuildPageKeepingScroll",
    "MSUF2.Redo",
    "MSUF2.RefreshSectionLayout",
    "MSUF2.RegisterControlMetadata",
    "MSUF2.RegisterHistoryProvider",
    "MSUF2.RegisterLayerOverviewProvider",
    "MSUF2.RegisterPage",
    "MSUF2.RegisterPageResetProvider",
    "MSUF2.RegisterSearchAvailability",
    "MSUF2.RegisterSearchProvider",
    "MSUF2.RegisterSearchWidget",
    "MSUF2.ReleaseColorShortcut",
    "MSUF2.RequestRefresh",
    "MSUF2.ReserveSectionActions",
    "MSUF2.ResetPageToDefaults",
    "MSUF2.ResumeForeverPadNavigation",
    "MSUF2.RunWithHistory",
    "MSUF2.SearchBridge",
    "MSUF2.SelectPage",
    "MSUF2.SetBuilderInsets",
    "MSUF2.SetCommandAction",
    "MSUF2.SetFixedPreviewHeight",
    "MSUF2.SetMissingSectionResolver",
    "MSUF2.SetPreviewArrowBindings",
    "MSUF2.SetSearchTargetPrepare",
    "MSUF2.SetSectionCursor",
    "MSUF2.SetSectionEnsureVisible",
    "MSUF2.SetSectionEntry",
    "MSUF2.SetSectionPopupGetter",
    "MSUF2.SetSectionRefreshState",
    "MSUF2.SetSectionWidth",
    "MSUF2.ShouldExpandFixedPreview",
    "MSUF2.ShowPageResetConfirm",
    "MSUF2.ShowStatusFeedback",
    "MSUF2.SkipHistoryCheckpoint",
    "MSUF2.StatusBarTextureItems",
    "MSUF2.SyncExternalHistoryState",
    "MSUF2.Theme",
    "MSUF2.Tr",
    "MSUF2.TrackRefresh",
    "MSUF2.Undo",
    "MSUF2.UnitSectionsShared",
    "MSUF2.Widgets",
    "MSUF2.cache",
    "MSUF2.frame",
    "MSUF2.navItems",
    "MSUF2.navPrimaryForKey",
    "MSUF2NativeDropdownList",
    "MSUF2_Open",
    "MSUF_ActiveProfile",
    "MSUF_ApplyCurrentProfileGlobalUiScale",
    "MSUF_ApplyFontScaleAnimationMode",
    "MSUF_ApplyMsufScale",
    "MSUF_ApplyPowerBarEmbedLayout_ForUnitKey",
    "MSUF_ClassPower_Apply",
    "MSUF_DB",
    "MSUF_DeleteProfile",
    "MSUF_EM2",
    "MSUF_EM2.ExternalElements",
    "MSUF_EM2.State",
    "MSUF_EditModeAPI",
    "MSUF_EditModeAPI.EnterEditMode",
    "MSUF_EditModeAPI.IsActive",
    "MSUF_EditModeAPI.RefreshOwner",
    "MSUF_EditModeAPI.RegisterElement",
    "MSUF_EditModeAPI.RegisterSessionListener",
    "MSUF_EditModeAPI.UnregisterOwner",
    "MSUF_EditModeAPI.UnregisterSessionListener",
    "MSUF_EncodeCompactTable",
    "MSUF_EnsureCooldownWidthObservers",
    "MSUF_FontApplyEpoch",
    "MSUF_GetDefaultProfileForNewCharacters",
    "MSUF_GetFontFlags",
    "MSUF_GetFontPath",
    "MSUF_GetFontPathForKey",
    "MSUF_GetPixelPerfectScale",
    "MSUF_GetSuiteCooldownAnchor",
    "MSUF_GlobalDB",
    "MSUF_HostAPI",
    "MSUF_HostAPI.ApplyUIScaleProfile",
    "MSUF_HostAPI.GetIconSkins",
    "MSUF_HostAPI.GetKickReady",
    "MSUF_HostAPI.SetResourceStack",
    "MSUF_HostAPI.version",
    "MSUF_NS",
    "MSUF_NS.BossTargetIndicator",
    "MSUF_NS.Client",
    "MSUF_NS.FirstLoad6",
    "MSUF_NS.GF",
    "MSUF_NS.L",
    "MSUF_NS.LOCALE",
    "MSUF_NS.MSUF_Auras3",
    "MSUF_NS.MSUF_FACTORY_DEFAULT_PROFILE_COMPACT",
    "MSUF_NS.MSUF_FOREVER_FACTORY_DEFAULT_PROFILE_COMPACT",
    "MSUF_NS.MSUF_MODERN_DARK_PROFILE_COMPACT",
    "MSUF_NS.ProfileFields",
    "MSUF_NS.ProfilePolicy",
    "MSUF_NS.ProfileRuntime",
    "MSUF_NS.ProfileSync",
    "MSUF_NS.ProfileVariants",
    "MSUF_NS.RegisterLocale",
    "MSUF_NS.UF",
    "MSUF_PadNavigation",
    "MSUF_PixelLayoutRegion",
    "MSUF_ProfileWasUnboundAtLogin",
    "MSUF_Profiles_ExportSelectionToString",
    "MSUF_Profiles_ImportExternal",
    "MSUF_Profiles_ImportIntoNewProfile",
    "MSUF_RegisterAnyEditModeListener",
    "MSUF_ResetGlobalUiScale",
    "MSUF_ResolveFontKeyPath",
    "MSUF_ResolveStatusbarTextureKey",
    "MSUF_SetCurrentProfileScreenReferenceHeight",
    "MSUF_SetDefaultProfileForNewCharacters",
    "MSUF_SetFontChecked",
    "MSUF_SetGlobalUiScale",
    "MSUF_SwitchProfile",
    "MSUF_TryDecodeCompactString",
    "MSUF_UFCore_NotifyConfigChanged",
    "MSUF_UI",
    "MSUF_UnitEditModeActive",
    "MSUF_player",
    "MSUF_target",
}

local function Read(path)
    local file = assert(io.open(root .. "/" .. path, "rb"), path)
    local text = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    return text
end

local ledger = {}
for line in Read("tools/public-globals.tsv"):gmatch("[^\n]+") do
    local name = line:match("^([^\t]+)\t")
    if name then ledger[name] = true end
end
for _, name in ipairs(PUBLIC_NAMES) do
    assert(ledger[name], "Suite host reader is absent from public ledger: " .. name)
end

-- Root globals are read without permissive client fallback stubs.
assert(rawget(env, "MSUF_NS") == host and rawget(env, "MSUF") == host)
assert(rawget(env, "MSUF2") == menu)
local api = rawget(env, "MSUF_HostAPI")
assert(api == host.HostAPI and api.version == 1 and menu.HOST_API_VERSION == 2)
local function Functions(owner, names, label)
    assert(type(owner) == "table", "Suite host table missing: " .. label)
    for name in names:gmatch("%S+") do
        assert(type(rawget(owner, name)) == "function", "Suite host method missing: " .. label .. "." .. name)
    end
end

Functions(api, "ApplyUIScaleProfile SetResourceStack GetResourceStack GetKickReady GetIconSkins", "MSUF_HostAPI")
-- Icon skins (2026-10-17): the interface the Suite paints with, and the page that lists its areas.
local iconSkins = api.GetIconSkins()
assert(type(iconSkins) == "table" and iconSkins.version == 1 and iconSkins.DEFAULT == "DEFAULT", "icon skin interface")
Functions(iconSkins, "Compile Paint Subscribe Unsubscribe", "MSUF_HostAPI.GetIconSkins()")
Functions(menu.IconSkinsPage, "RegisterArea", "MSUF2.IconSkinsPage")
assert(api.GetKickReady() == host.KickReady and host.KickReady.version == 1)
Functions(host.KickReady, "Register Unregister HasConsumers SetActive Look RGBA FillColors SelectColor SlotCount Cooldown",
    "MSUF.KickReady")
Functions(host.ProfilePolicy, "SelectSupportedDecodedProfile", "MSUF.ProfilePolicy")
Functions(host.ProfileFields, "RegisterExternal", "MSUF.ProfileFields")
Functions(host.ProfileVariants, "BaseSnapshot HasExternalOverlay IsRecording IsMaterialized Restore ResolveCurrent",
    "MSUF.ProfileVariants")
Functions(host.ProfileSync, "RegisterModule RebaseExternal", "MSUF.ProfileSync")
Functions(host.ProfileRuntime, "Apply", "MSUF.ProfileRuntime")
Functions(host.FirstLoad6, "IsFirstRunPending", "MSUF.FirstLoad6")
Functions(host.UF.Layers, "ApplyOwnedSurface ElementLevel", "MSUF.UF.Layers")
Functions(host.BossTargetIndicator, "Apply Style HasBorder HasMarker IsPaired PortraitExtents SetPreviewInteractive",
    "MSUF.BossTargetIndicator")
Functions(rawget(env, "MSUF_EM2").ExternalElements, "GetRecord", "MSUF_EM2.ExternalElements")
Functions(host.EventBus, "Register Unregister UnregisterAll Publish DefineEvent", "MSUF.EventBus")
Functions(host, "RunHostAPIStep HostAPIPlayerInCombat", "MSUF")
assert(type(host.MSUF_Auras3.TargetDotData) == "table")
assert(host.Client.Flavor == "Mainline" and host.Client.IsForever == (flavor == "Forever"))
Functions(host.Client, "SupportsEvent", "MSUF.Client")
Functions(host.MenuSkin, "Surface Button WindowAction TrackPaint TrackText BindColors IsActive Owns Refresh",
    "MSUF.MenuSkin")
Functions(menu.Theme, "Button ApplyMaterial StyleFontString", "MSUF2.Theme")
Functions(menu.Theme, "ApplySurface CenterButtonLabel Font MeasureButtonWidth Panel SetTranslatedText SkinEditBox StyleScrollFrame",
    "MSUF2.Theme")
Functions(menu.Widgets, "AttachContextColorShortcut AttachFixedPreviewExpander AttachPinnedPreview AttachStickyPageHeader "
    .. "CloseDropdown Description DividerAt Dropdown EnsureSectionContent FixedPreviewSection FocusCollapsibleSection "
    .. "HelpButton MeasureScopeOverrideBar MoveWidget OpenContextColors OpenDropdown PageBuilder RoleButton ScopeOverrideBar "
    .. "SectionSwitch SegmentTabs SetCollapsibleBadges SetCollapsibleSummary SetControlDisabledReason SetControlEnabled "
    .. "SetControlShown SettingsRows StyleSectionActionButton SwitchAt TopButton", "MSUF2.Widgets")
assert(type(menu.Widgets.DescriptionDetails) == "boolean" and type(env.MSUF_UI.colors) == "table")
Functions(host.GF, "FrameForUnit", "MSUF.GF")
Functions(env.MSUF_EM2.State, "Enter", "MSUF_EM2.State")
Functions(menu.UnitSectionsShared, "MakeScopeCopyPopup", "MSUF2.UnitSectionsShared")
Functions(menu.SearchBridge, "OpenSearchTarget", "MSUF2.SearchBridge")
Functions(menu, "BeginHistoryTransaction CancelHistoryTransaction CommitHistoryTransaction GetHistoryState "
    .. "IsHistoryCapturing Undo Redo", "MSUF2")
assert(type(menu.GlobalPage.FontValues) == "function")
Functions(menu.PreviewSelectionBar, "Create CreatePicker CycleHandle Refresh SetShown", "MSUF2.PreviewSelectionBar")
Functions(menu.PreviewHelpers, "ApplyPreviewChrome ArrowKeyDown CreateLayerButton EnsurePreviewBackgroundButton FlowLayerChips "
    .. "FocusKeyboardTarget IsTextInputFocused LayerChipButtonOpts NotePreviewElementMoved NudgeStep PreviewChromePalette "
    .. "RefreshSelectedLayerButtons ReleaseKeyboardCapture ShouldSkipDuplicateNudge ShowPreviewMoveCue", "MSUF2.PreviewHelpers")
Functions(rawget(env, "MSUF_UI"), "Button Color ApplyFontRole ApplyMaterial", "MSUF_UI")
if flavor == "Forever" then
    Functions(rawget(env, "MSUF_PadNavigation"), "Attach Activate Release", "MSUF_PadNavigation")
end

local MENU_FUNCTIONS = {
    "AddNavIcon",
    "AddTooltip",
    "AllowCombatClick",
    "ApplyPopupFramePriority",
    "BindBoolWidget",
    "BindDropdownAt",
    "BindSegment",
    "BindSwitchAt",
    "BindTextInputAt",
    "BuildPageResetWarning",
    "ControlMeta",
    "CreateMenuPopupPanel",
    "GetControlLabel",
    "GetControlSearchMeta",
    "GetControlTitle",
    "GetMissingSectionResolver",
    "GetRawSetText",
    "GetSearchTargetPrepare",
    "GetSectionCursor",
    "GetSectionEnsureVisible",
    "GetSectionEntry",
    "GetSectionRefreshState",
    "GetSectionWidth",
    "InvalidatePage",
    "InvalidateSearchProvider",
    "MarkContextColorHost",
    "OpenExactSettingControl",
    "PageHasReset",
    "RebuildPageKeepingScroll",
    "RefreshSectionLayout",
    "RegisterControlMetadata",
    "RegisterHistoryProvider",
    "RegisterLayerOverviewProvider",
    "RegisterPage",
    "RegisterPageResetProvider",
    "RegisterSearchAvailability",
    "RegisterSearchProvider",
    "RegisterSearchWidget",
    "ReleaseColorShortcut",
    "RequestRefresh",
    "ReserveSectionActions",
    "ResetPageToDefaults",
    "RunWithHistory",
    "SelectPage",
    "SetBuilderInsets",
    "SetCommandAction",
    "SetFixedPreviewHeight",
    "SetMissingSectionResolver",
    "SetPreviewArrowBindings",
    "SetSearchTargetPrepare",
    "SetSectionCursor",
    "SetSectionEnsureVisible",
    "SetSectionEntry",
    "SetSectionPopupGetter",
    "SetSectionRefreshState",
    "SetSectionWidth",
    "ShouldExpandFixedPreview",
    "ShowPageResetConfirm",
    "SkipHistoryCheckpoint",
    "StatusBarTextureItems",
    "SyncExternalHistoryState",
    "Tr",
    "TrackRefresh",
}
for _, name in ipairs(MENU_FUNCTIONS) do
    assert(type(rawget(menu, name)) == "function", "Suite Menu2 contract missing: " .. name)
end

-- Shared layers restore a Suite surface exactly when it returns to Auto.
local surface = env.CreateFrame("Frame")
surface:SetFrameLevel(73)
local layers = host.UF.Layers
assert(layers.ApplyOwnedSurface(surface, 4, 3) == true)
assert(surface:GetFrameLevel() == layers.ElementLevel(4, 0, 3))
assert(layers.ApplyOwnedSurface(surface, -1, 3) == true and surface:GetFrameLevel() == 73)
assert(layers.ApplyOwnedSurface(surface, -1, 3) == false)

-- The nameplate engine hands out one reused look with every consumed field.
local look = host.KickReady.Look()
assert(look == host.KickReady.Look(), "KickReady.Look stopped reusing its public table")
for name in ("show style marker segment readyR readyG readyB readyA outline boxSize "
    .. "boxAnchor boxOffsetX boxOffsetY texture"):gmatch("%S+") do
    assert(look[name] ~= nil, "Suite interrupt look field missing: " .. name)
end

-- Menu2 binds the same widget objects and callbacks the Suite supplies.
local prepare = function() return true end
menu.SetSearchTargetPrepare(surface, prepare)
assert(menu.GetSearchTargetPrepare(surface) == prepare)
local entry = {}
menu.SetSectionEntry(surface, entry)
assert(menu.GetSectionEntry(surface) == entry)
menu.SetSectionWidth(entry, 420)
assert(menu.GetSectionWidth(entry) == 420)

-- Suite HUD reveal calls the captured inherited tab hook with no arguments.
local tab = env.CreateFrame("Frame")
local selected = 0
tab._msuf2ExactTabView = { kind = "suiteHostTab", value = "hud", select = function(value)
    assert(value == "hud")
    selected = selected + 1
end }
local control = env.CreateFrame("CheckButton", nil, tab)
assert(menu.RegisterControlMetadata(control, { pageKey = "suite_host_probe", kind = "toggle",
    classification = "setting", settingKey = "msufsuite.host.probe", label = "Suite host probe" }))
local inherited = assert(menu.GetSearchTargetPrepare(control))
assert(inherited() == true and selected == 1, "Suite zero-argument tab preparation failed")
assert(inherited(control, "invalid") == false and selected == 1)
assert(inherited(control, { prepareKind = "other", prepareValue = "hud" }) == false and selected == 1)
assert(inherited(control, { prepareKind = "suiteHostTab", prepareValue = "other" }) == false and selected == 1)
assert(inherited(control, { prepareKind = "suiteHostTab", prepareValue = "hud" }) == true and selected == 2)

-- The host boundary preserves callback arguments and its first result.
local ok, answer = host.RunHostAPIStep("Suite host probe", function(a, b) return a + b end, 19, 23)
assert(ok == true and answer == 42)
assert(host.SuiteLink.GetOverview() == nil and host.SuiteLink.HasNameplateKickReady() == false)
assert(host.SuiteLink.NotifyProfileLifecycle("delete", "Suite host probe") == true)

print("suite_host_surface_contract_smoke: " .. flavor .. " PASS (public names, nested services and native host contracts)")
