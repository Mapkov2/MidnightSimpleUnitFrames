-- Assistant RegistryCore registry methods.
-- Keeps setting/action storage and query indexing separate from DB/apply helpers.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local C = A.RegistryCore
if type(C) ~= "table" then return end

local Registry = C.Registry
if type(Registry) ~= "table" then return end

local AddSettingToFindIndex

-- Alias permutation helpers can emit thousands of near-identical phrases per
-- setting. Canonical phrases are emitted first, so a small normalized head is
-- both a better query surface and dramatically cheaper to retain and score.
--
-- The head must still be long enough to hold the hand-written phrasings a
-- control needs. At 16 every alias past the sixteenth was dropped in silence:
-- a control with a full set of storage-name variants had no room left for the
-- sentences players actually type, and adding one changed nothing at all.
local MAX_SETTING_ALIASES = 20
local MAX_SETTING_EXACT_ALIAS_EXTRAS = 32

local function FoldAliasPhrases(value)
    if value:find("target", 1, true) then
        value = value:gsub("target%s+of%s+target", "targettarget"):gsub("target%s+target", "targettarget")
    end
    if value:find("focus", 1, true) then value = value:gsub("focus%s+target", "focustarget") end
    if value:find("cast", 1, true) then
        value = value:gsub("cast%s+bar", "castbar"):gsub("castbars", "castbar"):gsub("cast%s+text", "castbar text")
    end
    if value:find("power", 1, true) then
        value = value:gsub("powerbars", "power bars"):gsub("power%s+bars", "power bar"):gsub("powerbar", "power bar")
    end
    if value:find("mana", 1, true) then
        value = value:gsub("manabars", "mana bars"):gsub("mana%s+bars", "mana bar"):gsub("manabar", "mana bar")
    end
    if value:find("unit", 1, true) then value = value:gsub("unit%s+frames", "unitframes") end
    if value:find("gruppen", 1, true) then value = value:gsub("gruppen%s+frames", "gruppenframes") end
    if value:find("status", 1, true) then value = value:gsub("status%s+icons", "status icon") end
    if value:find("incoming", 1, true) then
        value = value:gsub("incoming%s+res%s+", "incoming rez "):gsub("incoming%s+res$", "incoming rez")
    end
    return value
end

local function MayNeedFoldedNormalLookup(value)
    return value:find("target", 1, true) or value:find("focus", 1, true)
        or value:find("cast", 1, true) or value:find("power", 1, true)
        or value:find("mana", 1, true) or value:find("unit", 1, true)
        or value:find("gruppen", 1, true) or value:find("status", 1, true)
        or value:find("incoming", 1, true)
end

local SETTING_ALIAS_WORD_REPLACEMENTS = {
    auras = "aura",
    colour = "color",
    mythicraidframe = "mythicraid frame",
    partyframe = "party frame",
    playerframe = "player frame",
    raidframe = "raid frame",
    readycheck = "ready check",
    unitframe = "unit frame",
}

local function AliasKey(value)
    value = tostring(value or "")
    if value ~= "" and value:sub(1, 1) ~= " " and value:sub(-1) ~= " "
        and not value:find("  ", 1, true) and not value:find("[^%l%d_ %./%-]") then
        return value
    end
    value = value:lower()
    if value:find("[\128-\255\"'`,;:!?%(%)]") then
        value = value:gsub("\195\131\194\164", "ae")
        value = value:gsub("\195\131\194\182", "oe")
        value = value:gsub("\195\131\194\188", "ue")
        value = value:gsub("\195\131\194\159", "ss")
        value = value:gsub("\195\164", "ae"):gsub("\195\182", "oe"):gsub("\195\188", "ue"):gsub("\195\159", "ss")
        value = value:gsub("\228", "ae"):gsub("\246", "oe"):gsub("\252", "ue"):gsub("\223", "ss")
        value = value:gsub("[\"'`]", ""):gsub("[,;:!?%(%)]", " ")
    end
    value = value:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return value
end

local function NormalizeSettingAliasKey(value)
    local needsWords = false
    for token in value:gmatch("%S+") do
        if SETTING_ALIAS_WORD_REPLACEMENTS[token] then needsWords = true; break end
    end
    if needsWords then
        local out = {}
        for token in value:gmatch("%S+") do
            out[#out + 1] = SETTING_ALIAS_WORD_REPLACEMENTS[token] or token
        end
        value = table.concat(out, " ")
    end
    return FoldAliasPhrases(value)
end

local function NormalizeSettingAlias(value)
    return NormalizeSettingAliasKey(AliasKey(value))
end

local function AliasNeedsParserNormalization(alias, baseKey)
    if baseKey ~= alias then return true end
    if alias:find("auras", 1, true) or alias:find("colour", 1, true)
        or alias:find("mythicraidframe", 1, true) or alias:find("partyframe", 1, true)
        or alias:find("playerframe", 1, true) or alias:find("raidframe", 1, true)
        or alias:find("readycheck", 1, true) or alias:find("unitframe", 1, true) then return true end
    if alias:find("target", 1, true)
        and (alias:find("target of target", 1, true) or alias:find("target target", 1, true)) then return true end
    if alias:find("focus target", 1, true) then return true end
    if alias:find("cast", 1, true)
        and (alias:find("cast bar", 1, true) or alias:find("castbars", 1, true)
            or alias:find("cast text", 1, true)) then return true end
    if alias:find("power", 1, true)
        and (alias:find("powerbars", 1, true) or alias:find("power bars", 1, true)
            or alias:find("powerbar", 1, true)) then return true end
    if alias:find("mana", 1, true)
        and (alias:find("manabars", 1, true) or alias:find("mana bars", 1, true)
            or alias:find("manabar", 1, true)) then return true end
    return alias:find("unit frames", 1, true) or alias:find("gruppen frames", 1, true)
        or alias:find("status icons", 1, true) or alias:find("incoming res", 1, true)
end

local function BuildAliasNormalizationMask(aliases)
    local mask = 0
    for i = 1, #(aliases or {}) do
        local alias = aliases[i]
        local baseKey = AliasKey(alias)
        if AliasNeedsParserNormalization(alias, baseKey) then
            mask = mask + (2 ^ (i - 1))
        end
    end
    return mask > 0 and mask or nil
end

local function CompactAliasesInPlace(aliases, limit)
    if type(aliases) ~= "table" then return {}, {}, nil end
    local source = aliases
    local out = #source > (limit * 2) and {} or source
    local seen, normalizationMask, write = {}, 0, 0
    for read = 1, #source do
        local alias = source[read]
        local key = type(alias) == "string" and AliasKey(alias) or ""
        if key ~= "" and not seen[key] then
            seen[key] = true
            write = write + 1
            out[write] = alias
            if AliasNeedsParserNormalization(alias, key) then
                normalizationMask = normalizationMask + (2 ^ (write - 1))
            end
            if write >= limit then break end
        end
    end
    if out == source then
        for i = #out, write + 1, -1 do out[i] = nil end
    end
    return out, seen, normalizationMask > 0 and normalizationMask or nil
end

local function CompactExactAliasesInPlace(exactAliases, normalSeen, normalAliases)
    if type(exactAliases) ~= "table" then return exactAliases end
    local source = exactAliases
    local out = {}
    local seen, normalizationMask, foldedNormalSeen, write, extras = {}, 0, nil, 0, 0
    -- One-token exact aliases have distinct parser semantics. Collect them
    -- first so the bounded multiword pass can stop as soon as its budget fills.
    for read = 1, #source do
        local alias = source[read]
        local raw = type(alias) == "string" and alias or ""
        if raw ~= "" and not raw:find("%s") then
            local key = AliasKey(raw)
            if key ~= "" and not seen[key] then
                seen[key] = true
                write = write + 1
                out[write] = alias
                if AliasNeedsParserNormalization(alias, key) then
                    normalizationMask = normalizationMask + (2 ^ (write - 1))
                end
            end
        end
    end
    for read = 1, #source do
        if extras >= MAX_SETTING_EXACT_ALIAS_EXTRAS then break end
        local alias = source[read]
        local raw = type(alias) == "string" and alias or ""
        if raw ~= "" and raw:find("%s") then
            local baseKey = AliasKey(alias)
            local key = baseKey
            local normalDuplicate = normalSeen[baseKey] == true
            if not normalDuplicate and baseKey ~= "" then
                local foldedKey = FoldAliasPhrases(baseKey)
                if foldedKey ~= baseKey or MayNeedFoldedNormalLookup(baseKey) then
                    key = foldedKey
                    if not foldedNormalSeen then
                        foldedNormalSeen = {}
                        for i = 1, #(normalAliases or {}) do
                            foldedNormalSeen[FoldAliasPhrases(AliasKey(normalAliases[i]))] = true
                        end
                    end
                    normalDuplicate = foldedNormalSeen[key] == true
                end
            end
            local keep = key ~= "" and not seen[key]
            if keep then keep = not normalDuplicate end
            if keep then
                seen[key] = true
                write = write + 1
                out[write] = alias
                if AliasNeedsParserNormalization(alias, baseKey) then
                    normalizationMask = normalizationMask + (2 ^ (write - 1))
                end
                extras = extras + 1
            end
        end
    end
    return out, normalizationMask > 0 and normalizationMask or nil
end

C.MAX_SETTING_ALIASES = MAX_SETTING_ALIASES
C.NormalizeSettingAlias = NormalizeSettingAlias

-- Registry settings normally route back to one exact or reviewed dynamic
-- Menu2 control.  These reviewed exceptions intentionally have no scalar
-- widget: they are legacy/fallback values, compound representations, or are
-- operated through an action/preview instead.  Keeping the evidence on the
-- setting prevents semantic fallback from focusing an unrelated control.
local MENU_CONTROL_STANDALONE = {}
local function DefineMenuControlStandalone(keys, reason, evidence)
    for key in tostring(keys or ""):gmatch("%S+") do
        MENU_CONTROL_STANDALONE[key] = { reason = reason, evidence = evidence }
    end
end

DefineMenuControlStandalone([[
general.globalUiScaleEnabled
]], "The Dashboard exposes pending Apply/Revert/Disable actions rather than a persisted enabled toggle.",
    "MSUF_Menu2_Dashboard.lua scaling actions and MSUF_AssistantRegistry_DashboardActions.lua")
DefineMenuControlStandalone([[
general.dropdownStyleMode
]], "Dropdown style mode is a compatibility value; the current Modules page exposes only the MSUF Style enable switch.",
    "MSUF_Menu2_AdvancedProfiles.lua BuildModules")
DefineMenuControlStandalone([[
general.castbarIconSize general.castbarIconOffsetX general.castbarIconOffsetY
general.castbarSpellNameFontSize general.castbarTimeFontSize general.bossCastbarDetached runtime.focusKickPreview
]], "This castbar fallback, Edit Mode attachment, or runtime preview value has no scalar control on the current global Castbar page.",
    "MSUF_Menu2_GlobalCastbars.lua controls, MSUF_EditMode_Movers.lua castbar attachment, and preview fallback reads")
DefineMenuControlStandalone([[
general.classPowerPreviewGuidesEnabled
]], "The persisted Guides toggle belongs to the conditionally-created Class Resources inline preview; when that preview exists its layer control carries this exact settingKey.",
    "MSUF_Menu2_ClassPowerPreview.lua CreateLayerSidebar layer.guides registration")
DefineMenuControlStandalone([[
general.ellesmereEditModeIntegration
]], "The EllesmereUI integration toggle is created only while EllesmereUI is loaded; when present it carries this exact settingKey.",
    "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GlobalMisc.lua conditional misc_ellesmere_ui section")
DefineMenuControlStandalone([[
general.gradientDirection barScope.gf_party.gradientDirection barScope.gf_raid.gradientDirection
]], "The current Bars UI edits independent multi-direction buttons; the legacy scalar direction setting has no equivalent single widget.",
    "MSUF_Menu2_GlobalBars.lua ToggleGradientDirectionForScope direction pad")
DefineMenuControlStandalone([[
general.barOutlineColorA barScope.gf_party.barOutlineColorA barScope.gf_raid.barOutlineColorA
]], "The Bars outline color widget edits RGB only; these legacy opacity scalars are not exposed by that widget.",
    "MSUF_Menu2_GlobalBars.lua BuildOutlineSection")
DefineMenuControlStandalone([[
general.fontSize general.fontColor fontScope.gf_party.fontSize fontScope.gf_raid.fontSize
]], "The current Fonts page has no global or scoped font-size/palette scalar; size is owned by concrete text controls and color by the Colors page.",
    "MSUF_Menu2_GlobalFonts.lua BuildFonts")
DefineMenuControlStandalone([[
gf_mythicraid.nameClipSide gf_mythicraid.nameMaxChars gf_mythicraid.nameNoEllipsis gf_mythicraid.nameShortenEnabled
]], "Raid is the single visible group-font scope and applies to Mythic Raid; there is no separate Mythic Raid selector or widget.",
    "MSUF_Menu2_Global.lua GLOBAL_SCOPE_VALUES and MSUF_Menu2_GlobalFonts.lua group name controls")

function Registry:RegisterSetting(spec)
    if type(spec) ~= "table" or type(spec.key) ~= "string" or spec.key == "" then return nil end
    if self.settingsByKey[spec.key] then return self.settingsByKey[spec.key] end
    local exactSharesNormalList = type(spec.aliases) == "table" and spec.exactAliases == spec.aliases
    local sharedOneTokenExact
    if exactSharesNormalList then
        local seen = {}
        sharedOneTokenExact = {}
        for i = 1, #spec.exactAliases do
            local alias = spec.exactAliases[i]
            local raw = type(alias) == "string" and alias or ""
            if raw ~= "" and not raw:find("%s") then
                local key = AliasKey(raw)
                if key ~= "" and not seen[key] then
                    seen[key] = true
                    sharedOneTokenExact[#sharedOneTokenExact + 1] = alias
                end
            end
        end
    end
    local normalSeen, aliasNormMask, exactAliasNormMask
    spec.aliases, normalSeen, aliasNormMask = CompactAliasesInPlace(spec.aliases, MAX_SETTING_ALIASES)
    -- Exact aliases enable one-token shortcuts that normal aliases deliberately
    -- do not. Preserve those, but remove normalized multiword duplicates and
    -- bound only the genuinely additional exact phrases.
    if exactSharesNormalList then
        spec.exactAliases = sharedOneTokenExact
        exactAliasNormMask = BuildAliasNormalizationMask(spec.exactAliases)
    elseif type(spec.exactAliases) == "table" and #spec.exactAliases > 0 then
        spec.exactAliases, exactAliasNormMask = CompactExactAliasesInPlace(spec.exactAliases, normalSeen, spec.aliases)
    end
    -- Versioned bitmasks let later indexes skip Normalize for canonical aliases
    -- without retaining a parallel string/table graph. A set bit means the
    -- corresponding alias still needs the full parser normalizer.
    spec._assistantAliasNormVersion = 2
    spec._assistantAliasNormMask = aliasNormMask
    spec._assistantExactAliasNormMask = exactAliasNormMask
    local standalone = MENU_CONTROL_STANDALONE[spec.key]
    if spec.generated == true then
        standalone = {
            reason = "AutoCoverage provides a defensive raw-DB Assistant fallback and does not claim a visible Menu2 scalar control.",
            evidence = "MSUF_AssistantRegistry_AutoCoverage.lua generated safe-scalar fallback contract",
        }
    end
    if standalone then
        spec.menuControlDisposition = "standalone"
        spec.menuControlDispositionReason = standalone.reason
        spec.menuControlDispositionEvidence = standalone.evidence
    end
    self.settings[#self.settings + 1] = spec
    self.settingsByKey[spec.key] = spec
    if type(self._findSettingsIndex) == "table"
        and tonumber(self._findSettingsIndexCount) == (#self.settings - 1)
        and type(AddSettingToFindIndex) == "function" then
        AddSettingToFindIndex(self._findSettingsIndex, spec)
        self._findSettingsIndexCount = #self.settings
    end
    if A.Knowledge and type(A.Knowledge.MarkDirty) == "function" then A.Knowledge.MarkDirty() end
    return spec
end

function Registry:GetSetting(key)
    return self.settingsByKey[key]
end

function Registry:AllSettings()
    return self.settings
end

local function AddFindIndex(index, bucket, key, setting)
    key = tostring(key or "")
    if key == "" then return end
    local byKey = index[bucket]
    byKey[key] = byKey[key] or {}
    byKey[key][#byKey[key] + 1] = setting
end

AddSettingToFindIndex = function(index, setting)
    if type(index) ~= "table" or type(setting) ~= "table" then return end
    AddFindIndex(index, "byUnit", setting.unit, setting)
    AddFindIndex(index, "byFrameType", setting.frameType, setting)
    AddFindIndex(index, "byAttribute", setting.attribute, setting)
    AddFindIndex(index, "byType", setting.type, setting)
end

-- Action transaction policy is deliberately keyed by action ID instead of
-- inferred from labels or broad action types.  A diagnostic-looking action
-- can still erase SavedVariables (assistant_nomatch_clear), while an
-- edit-mode action can be either a runtime preview or a profile mutation.
-- Keeping every action in this catalog makes a newly-added action fail the
-- audit as unclassified instead of silently becoming read-only or mutable.
local ACTION_POLICIES = {}
local ACTION_POLICY_ERRORS = {}

local function CopyActionPolicy(policy)
    local out = {}
    for key, value in pairs(policy or {}) do out[key] = value end
    return out
end

local function DefineActionPolicies(keys, policy)
    for key in tostring(keys or ""):gmatch("%S+") do
        if ACTION_POLICIES[key] then
            ACTION_POLICY_ERRORS[#ACTION_POLICY_ERRORS + 1] = "duplicate action policy: " .. key
        else
            ACTION_POLICIES[key] = CopyActionPolicy(policy)
        end
    end
end

DefineActionPolicies([[
assistant.diagnostic.editMode.status assistant.workflow.status assistant_help
assistant_nomatch_telemetry assistant_nomatch_worklist assistant_scope_help assistant_status
aura_blacklist_summary aura_custom_whitelist_summary aura_group_blacklist_summary
aura_group_category_blacklist_summary copy_support_link copy_wago_profiles_link
custom_anchor_picker_status diagnose_aura_visibility diagnose_castbar_visibility
diagnose_class_power_status diagnose_dashboard_setup diagnose_gameplay_helpers
diagnose_group_visibility diagnose_profile_status diagnose_unit_visibility
export_profile profile_summary
]], {
    mutability = "readOnly",
    readOnly = true,
    mutatesState = false,
    stateOwner = "none",
    rollbackStrategy = "none",
})

DefineActionPolicies([[
assistant.panel.close cancel_custom_anchor_picker dashboard_page_back dashboard_page_forward
    menu_search_clear menu_search_query menu_window_close menu_window_maximize menu_window_minimize menu_window_restore
open_dashboard_panel open_page open_setting_control open_profile_import open_recovery_tools support_links_summary
set_dashboard_panel set_menu_selector_state set_nav_search_intro set_nav_section
]], {
    mutability = "navigation",
    readOnly = false,
    mutatesState = false,
    stateOwner = "menuSession",
    rollbackStrategy = "none",
})

-- These actions only open a user-driven picker.  The later click owns the
-- profile mutation and is intentionally outside the synchronous action run.
DefineActionPolicies([[
    assistant.action.editMode.anchorPicker menu_reset_current_page_prompt start_group_custom_anchor_picker
start_unit_custom_anchor_picker
]], {
    mutability = "navigation",
    readOnly = false,
    mutatesState = false,
    stateOwner = "menuSession",
    deferredMutationOwner = "activeProfile",
    transactionAdapter = "userConfirmedAnchorPicker",
    transactionAdapterMode = "deferredUserInput",
    transactionAdapterReady = true,
    transactionAdapterContract = "The action only opens/cancels the picker; the later explicit user pick owns and applies the profile change.",
    rollbackStrategy = "deferredUserInput",
})

DefineActionPolicies([[
assistant.action.editMode.bossPreview assistant.action.editMode.enter
assistant.action.editMode.exit assistant.action.editMode.groupPreview
assistant.action.editMode.preview assistant.action.editMode.snap assistant.action.editMode.toggle
assistant.workflow.cancel class_power_preview_animate
dashboard.globalUiScale.apply dashboard.globalUiScale.revertPending
dashboard.msufFrameScale.apply dashboard.msufFrameScale.revertPending
dashboard.menuScale.apply dashboard.menuScale.revertPending
    preview_castbar preview_group_status_icon preview_player_totems preview_unit_status_indicator set_castbar_test_mode
start_profile_copy_flow start_profile_rename_flow toggle_absorb_bar_test
toggle_highlight_border_test
]], {
    mutability = "ephemeral",
    readOnly = false,
    mutatesState = false,
    stateOwner = "runtimeSession",
    rollbackStrategy = "none",
})

-- Active-profile mutations covered by the normal MSUF_DB snapshot.
DefineActionPolicies([[
apply_global_scale_preset assistant.action.editMode.auras
aura_blacklist_add_preset aura_blacklist_add_spell aura_blacklist_clear_spells
aura_blacklist_remove_spell
aura_custom_whitelist_add_spell aura_custom_whitelist_clear_spells aura_custom_whitelist_remove_spell
reset_aura_custom_container
aura_group_blacklist_add_preset aura_group_blacklist_add_spell aura_group_blacklist_clear_spells
aura_group_blacklist_remove_spell aura_group_category_blacklist_clear aura_group_category_blacklist_set
assistant.action.editMode.backgroundOpacity assistant.action.editMode.cdm
assistant.action.editMode.grid assistant.action.editMode.gridStep
assistant.action.editMode.resetPosition class_power_quick_setup clear_group_custom_anchor
clear_unit_custom_anchor copy_group copy_unit move_group_spell_indicator_order
enable_focus_target_frame show_player_power_or_open_class_resources
reset_all_scoped_global_bars_overrides
reset_all_scoped_global_font_overrides reset_all_unit_positions reset_aura_colors
reset_bar_background_color reset_bar_colors reset_bar_gradient_colors reset_castbar_colors
reset_class_colors reset_class_power_color_token reset_class_power_combo_slot_colors reset_class_power_slot_colors
reset_focus_kick_position reset_gameplay_colors reset_global_font_color
reset_group_corner_indicator_slot reset_group_corner_indicators
reset_group_spell_indicator_aura reset_group_status_icon reset_group_status_icons
reset_selected_group_status_icon reset_class_power_full_color
reset_health_gradient_colors reset_npc_type_colors reset_player_totems_layout
reset_portrait_colors reset_power_color_token reset_resource_colors
reset_scoped_global_bars_override reset_scoped_global_font_override reset_unit_page
reset_unit_position reset_unit_status_indicator reset_unitframe_colors
set_crosshair_melee_spell set_global_font_color set_group_spell_indicator_aura
set_group_spell_indicator_multi_spec dashboard.globalUiScale.disable
]], {
    mutability = "savedState",
    readOnly = false,
    mutatesState = true,
    stateOwner = "activeProfile",
    captureSnapshot = true,
    snapshotCoverage = "complete",
    rollbackStrategy = "captureSnapshot",
})

-- These mutate only the active profile but already use the owner-aware
-- profile snapshot path (which also preserves the active profile binding).
DefineActionPolicies([[
import_legacy_profile_string import_profile_string menu_history_reset_session recover_frames
reset_profile
]], {
    mutability = "savedState",
    readOnly = false,
    mutatesState = true,
    stateOwner = "activeProfile",
    captureProfileSnapshot = true,
    snapshotCoverage = "complete",
    rollbackStrategy = "captureProfileSnapshot",
})

-- Profile lifecycle and per-character profile mapping mutations whose
-- affected profile names are covered by CaptureProfileSnapshot.
DefineActionPolicies([[
clear_broken_spec_profile_mappings clear_spec_profile copy_profile create_profile
delete_profile import_profile_string_new set_new_character_profile set_spec_profile
switch_profile
]], {
    mutability = "savedState",
    readOnly = false,
    mutatesState = true,
    stateOwner = "profileStore",
    captureProfileSnapshot = true,
    snapshotCoverage = "complete",
    rollbackStrategy = "captureProfileSnapshot",
})

-- The underlying history services own their before/after data and retain a
-- failed entry on the relevant stack.  Wrapping these in another full DB
-- snapshot would corrupt stack semantics, so they use explicit adapters.
DefineActionPolicies([[
assistant.action.editMode.cancel assistant.action.editMode.redo
assistant.action.editMode.undo menu_history_redo menu_history_undo
]], {
    mutability = "savedState",
    readOnly = false,
    mutatesState = true,
    stateOwner = "activeProfile",
    transactionAdapter = "managedHistory",
    transactionAdapterMode = "selfManaged",
    transactionAdapterReady = true,
    transactionAdapterContract = "The feature-owned Edit Mode/Menu history service restores its own before/after state and preserves failed stack entries.",
    rollbackStrategy = "transactionAdapter",
})

DefineActionPolicies([[
assistant.action.history.redo assistant.action.history.undo
]], {
    mutability = "savedState",
    readOnly = false,
    mutatesState = true,
    stateOwner = "historyBundle",
    transactionAdapter = "assistantHistoryBundle",
    transactionAdapterMode = "selfManaged",
    transactionAdapterReady = true,
    transactionAdapterContract = "A.UndoLast/A.RedoLast restore the typed active-profile or profile-store bundle and keep failures on their source stack.",
    rollbackStrategy = "transactionAdapter",
})

-- Owner-specific transactions.  These actions touch state outside the active
-- MSUF_DB profile, so ExecuteAction must use the named adapter instead of a
-- generic profile snapshot.  Every adapter captures only its declared owner
-- graph and is reversible through the normal Assistant undo/redo stack.
DefineActionPolicies([[copy_profile_from_to]], {
    mutability = "savedState",
    readOnly = false,
    mutatesState = true,
    stateOwner = "profileStore",
    snapshotCoverage = "complete",
    transactionAdapter = "profileCopyFromTo",
    transactionAdapterMode = "capturedOwnerState",
    transactionAdapterReady = true,
    transactionAdapterContract = "Capture source, destination, previous active profile, and character binding; remove a newly-created destination during rollback.",
    statePath = "MSUF_GlobalDB.profiles[source|destination]",
    rollbackStrategy = "transactionAdapter",
})

DefineActionPolicies([[rename_profile]], {
    mutability = "savedState",
    readOnly = false,
    mutatesState = true,
    stateOwner = "profileStore",
    snapshotCoverage = "complete",
    transactionAdapter = "profileRename",
    transactionAdapterMode = "capturedOwnerState",
    transactionAdapterReady = true,
    transactionAdapterContract = "Capture old and new profile names plus every character/spec binding that can reference either name.",
    statePath = "MSUF_GlobalDB.profiles[old|new] and profile bindings",
    rollbackStrategy = "transactionAdapter",
})

DefineActionPolicies([[factory_reset_all]], {
    mutability = "savedState",
    readOnly = false,
    mutatesState = true,
    stateOwner = "globalStore",
    snapshotCoverage = "complete",
    transactionAdapter = "factoryResetAll",
    transactionAdapterMode = "capturedOwnerState",
    transactionAdapterReady = true,
    transactionAdapterContract = "Capture and restore the complete reset-owned SavedVariables graph, active profile, and character binding before MSUF_DoFullReset.",
    statePath = "MSUF_GlobalDB and MSUF_DB",
    rollbackStrategy = "transactionAdapter",
})

DefineActionPolicies([[assistant_nomatch_clear]], {
    mutability = "savedState",
    readOnly = false,
    mutatesState = true,
    stateOwner = "globalStore",
    snapshotCoverage = "complete",
    transactionAdapter = "globalAssistantNoMatch",
    transactionAdapterMode = "capturedOwnerState",
    transactionAdapterReady = true,
    transactionAdapterContract = "Capture and restore only assistantNoMatch total, recent, and counts plus the in-memory last-no-match pointer.",
    statePath = "MSUF_GlobalDB.global.assistantNoMatch",
    rollbackStrategy = "transactionAdapter",
})

DefineActionPolicies([[
first_load.personalize first_load.import_profile first_load.use_defaults
first_load.whats_new first_load.not_now first_load.full_settings
guided_setup guided_setup_step restart_upgrade_highlight_tour
]], {
    mutability = "savedState",
    readOnly = false,
    mutatesState = true,
    stateOwner = "onboardingStore",
    snapshotCoverage = "complete",
    transactionAdapter = "onboardingFirstLoad",
    transactionAdapterMode = "capturedOwnerState",
    transactionAdapterReady = true,
    transactionAdapterContract = "Capture and restore first-load, guided-tour, and upgrade-highlight SavedVariables plus session deferral flags while preserving lifecycle table identity.",
    statePath = "MSUF_GlobalDB.global.firstLoad6, MSUF_GlobalDB.global.guidedTour6, and MSUF_GlobalDB.global.upgradeHighlights",
    rollbackStrategy = "transactionAdapter",
})

Registry.actionPoliciesByKey = ACTION_POLICIES
Registry.actionPolicyErrors = ACTION_POLICY_ERRORS

local VALID_ACTION_MUTABILITY = {
    readOnly = true,
    ephemeral = true,
    navigation = true,
    savedState = true,
}

local function ApplyActionPolicy(spec)
    local policy = ACTION_POLICIES[spec.key]
    if type(policy) ~= "table" then
        spec.actionPolicyExplicit = false
        spec.actionPolicyError = "missing explicit action policy"
        return
    end
    spec.actionPolicyExplicit = true
    spec.actionPolicySource = "registry.catalog.v1"
    local conflicts = {}
    for key, value in pairs(policy) do
        if spec[key] ~= nil and spec[key] ~= value then
            conflicts[#conflicts + 1] = tostring(key)
        else
            spec[key] = value
        end
    end
    if not VALID_ACTION_MUTABILITY[spec.mutability] then
        conflicts[#conflicts + 1] = "mutability"
    end
    if #conflicts > 0 then
        table.sort(conflicts)
        spec.actionPolicyError = "action policy conflict: " .. table.concat(conflicts, ", ")
    end
end

function Registry:BuildFindSettingsIndex()
    local existing = self._findSettingsIndex
    local indexedCount = tonumber(self._findSettingsIndexCount) or 0
    local settingsCount = #self.settings
    if type(existing) == "table" and indexedCount > 0 and indexedCount <= settingsCount then
        for i = indexedCount + 1, settingsCount do
            AddSettingToFindIndex(existing, self.settings[i])
        end
        self._findSettingsIndexCount = settingsCount
        return existing
    end
    local index = {
        byUnit = {},
        byFrameType = {},
        byAttribute = {},
        byType = {},
    }
    for i = 1, #self.settings do
        AddSettingToFindIndex(index, self.settings[i])
    end
    self._findSettingsIndex = index
    self._findSettingsIndexCount = #self.settings
    return index
end

function Registry:FindSettingsCandidateList(filter, unitSet)
    local index = self._findSettingsIndex
    if not index or self._findSettingsIndexCount ~= #self.settings then
        index = self:BuildFindSettingsIndex()
    end
    local best
    local function consider(list)
        if type(list) == "table" and (not best or #list < #best) then best = list end
    end
    if type(filter.unit) == "string" then
        consider(index.byUnit[filter.unit])
    elseif type(filter.units) == "table" and #filter.units == 1 then
        consider(index.byUnit[filter.units[1]])
    end
    if filter.frameType then consider(index.byFrameType[filter.frameType]) end
    if filter.attribute then consider(index.byAttribute[filter.attribute]) end
    if filter.type then consider(index.byType[filter.type]) end
    return best or self.settings
end

function Registry:FindSettings(filter)
    filter = filter or {}
    local out = {}
    local unitSet
    if type(filter.units) == "table" then
        unitSet = {}
        for i = 1, #filter.units do unitSet[filter.units[i]] = true end
    elseif type(filter.unit) == "string" then
        unitSet = { [filter.unit] = true }
    end
    local candidates = self:FindSettingsCandidateList(filter, unitSet)
    for i = 1, #candidates do
        local setting = candidates[i]
        local ok = true
        if unitSet and not unitSet[setting.unit] then ok = false end
        if ok and filter.frameType and setting.frameType ~= filter.frameType then ok = false end
        if ok and filter.attribute and setting.attribute ~= filter.attribute then ok = false end
        if ok and filter.type and setting.type ~= filter.type then ok = false end
        if ok then out[#out + 1] = setting end
    end
    return out
end

function Registry:RegisterAction(spec)
    if type(spec) ~= "table" or type(spec.key) ~= "string" or spec.key == "" then return nil end
    if self.actionsByKey[spec.key] then return self.actionsByKey[spec.key] end
    ApplyActionPolicy(spec)
    local actionInputs = A.ActionInputs
    local inputContract = type(actionInputs) == "table" and type(actionInputs.GetContract) == "function"
        and actionInputs.GetContract(spec.key) or nil
    if type(inputContract) == "table" then
        if spec.assistantInput ~= nil and spec.assistantInput ~= inputContract then
            spec.assistantInputExplicit = false
            spec.assistantInputError = "action input contract conflict"
        else
            spec.assistantInput = inputContract
            spec.assistantInputExplicit = true
            spec.assistantInputSource = tostring(inputContract.source or "registry.actionInputs.v1")
        end
    else
        spec.assistantInputExplicit = false
        spec.assistantInputError = "missing explicit action input contract"
    end
    spec.aliases = type(spec.aliases) == "table" and spec.aliases or {}
    self.actions[#self.actions + 1] = spec
    self.actionsByKey[spec.key] = spec
    if A.Knowledge and type(A.Knowledge.MarkDirty) == "function" then A.Knowledge.MarkDirty() end
    return spec
end

function Registry:GetAction(key)
    return self.actionsByKey[key]
end

function Registry:AllActions()
    return self.actions
end

function Registry:NormalizeActionInput(actionOrKey, args)
    local actionInputs = A.ActionInputs
    if type(actionInputs) ~= "table" or type(actionInputs.Normalize) ~= "function" then
        return nil, "Assistant action input normalizer is unavailable"
    end
    return actionInputs.Normalize(actionOrKey, args)
end

function Registry:RegisterTodo(text)
    self.todos[#self.todos + 1] = tostring(text or "")
end

function Registry:GetTodos()
    return self.todos
end
