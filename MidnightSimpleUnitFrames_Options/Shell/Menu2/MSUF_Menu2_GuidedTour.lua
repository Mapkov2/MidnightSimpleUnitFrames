--- Menu-native MSUF 6.0 guided setup.
---
--- The guide walks native pages control by control. Every normal tour step owns
--- one highlighted widget and asks for a real interaction before Next unlocks.
--- It never copies settings into a second wizard and never mutates a value when
--- the user deliberately chooses Keep unchanged or Skip.

local _, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

local _G = _G
local CreateFrame = _G.CreateFrame
local C_Timer = M.MenuTimer or _G.C_Timer
local ceil, floor, max, min = math.ceil, math.floor, math.max, math.min
local format = string.format
local pairs, ipairs, type, tostring = pairs, ipairs, type, tostring
local sort = table.sort

local InvokeGuidedBoundary = M.InvokeBoundary or pcall

local function Tr(text)
    return type(M.Tr) == "function" and M.Tr(tostring(text or "")) or tostring(text or "")
end

local STAGES = {
    {
        id = "menu_basics", special = true, pageKey = "guided_setup", icon = "home",
        title = "What do you want to set up?",
        impact = "Choose Unitframes, Group Frames, Class Resources, or the complete three-part tour.",
    },
    {
        id = "unit_intro", special = true, pageKey = "guided_setup", icon = "uf_player", area = "unitframes",
        title = "Part 1 - Unitframes",
        impact = "Skipping starts at the next selected setup area.",
    },
    {
        id = "edit_mode", special = true, pageKey = "guided_setup", icon = "uf_player",
        area = "unitframes",
        title = "Place your frames",
        impact = "Skipping leaves the current frame positions and anchoring unchanged.",
    },
    {
        id = "uf_player", pageKey = "uf_player", icon = "uf_player", area = "unitframes", title = "Build your Player frame",
        includeSections = { frame_basics = true }, controlLimit = 4,
        impact = "Skipping keeps the current Player-frame basics.",
    },
    {
        id = "uf_player_auras", pageKey = "uf_player", icon = "uf_player", area = "unitframes", title = "Choose your Player auras",
        includeSections = { auras = true, ["region:unit_aura_tools"] = true }, includeEphemeralControls = true, controlLimit = 2,
        controlPaths = {
            "auras/unit-workspace/container-selector",
            "auras/unit-workspace/tool-selector",
        },
        impact = "Skipping keeps the current Player aura container and tool.",
    },
    {
        id = "uf_player_name", pageKey = "uf_player", icon = "uf_player", area = "unitframes", title = "Set up the Player name",
        includeSections = { text = true }, prepareSection = "text", prepareTab = "name", prepareState = "unitTextTabSelection", controlLimit = 3,
        controlPaths = { "unit/text/name/show", "unit/text/name/anchor", "unit/text/name/size" },
        impact = "Skipping keeps the current Player name text.",
    },
    {
        id = "uf_player_hp_text", pageKey = "uf_player", icon = "uf_player", area = "unitframes", title = "Set up Player health text",
        includeSections = { text = true }, prepareSection = "text", prepareTab = "hp", prepareState = "unitTextTabSelection", prepareSlot = "right", prepareSlotState = "unitTextSlotSelection", controlLimit = 3,
        controlPaths = { "unit/text/hp/show", "unit/text/hp/slot/mode", "unit/text/hp/size" },
        impact = "Skipping keeps the current Player health text.",
    },
    {
        id = "uf_player_power_text", pageKey = "uf_player", icon = "uf_player", area = "unitframes", title = "Set up Player power text",
        includeSections = { text = true }, prepareSection = "text", prepareTab = "power", prepareState = "unitTextTabSelection", prepareSlot = "right", prepareSlotState = "unitTextSlotSelection", controlLimit = 3,
        controlPaths = { "unit/text/power/show", "unit/text/power/slot/mode", "unit/text/power/size" },
        impact = "Skipping keeps the current Player power text.",
    },
    {
        id = "uf_player_portrait", pageKey = "uf_player", icon = "uf_player", area = "unitframes", title = "Set up the Player portrait",
        includeSections = { portrait = true }, prepareSection = "portrait", prepareTab = "general", prepareState = "unitPortraitTabSelection", controlLimit = 3,
        controlPaths = { "unit/portrait/enabled", "unit/portrait/position", "unit/portrait/portraitrender" },
        impact = "Skipping keeps the current Player portrait.",
    },
    {
        id = "uf_player_power", pageKey = "uf_player", icon = "uf_player", area = "unitframes", title = "Build the Player power bar",
        includeSections = { power_bar = true }, controlLimit = 4,
        controlPaths = { "unit/power/show", "unit/power/powerbarheight", "unit/power/embedpowerbarintohealth", "unit/power/detached" },
        impact = "Skipping keeps the current Player power bar.",
    },
    {
        id = "uf_player_castbar", pageKey = "uf_player", icon = "uf_player", area = "unitframes", title = "Build the Player castbar",
        includeSections = { castbar = true }, prepareSection = "castbar", prepareTab = "general", prepareState = "unitCastbarTabSelection", controlLimit = 5,
        controlPaths = { "unit/castbar/enabled", "unit/castbar/provider", "unit/castbar/show_interrupt", "unit/castbar/width_mode", "unit/castbar/height" },
        impact = "Skipping keeps the current Player castbar.",
    },
    {
        id = "uf_player_status", pageKey = "uf_player", icon = "uf_player", area = "unitframes", title = "Choose Player indicators",
        includeSections = { status_icons = true }, includeEphemeralControls = true,
        prepareSection = "status_icons", prepareTab = "basic", prepareState = "unitStatusTabSelection", controlLimit = 4,
        controlPaths = { "unit/status/selector", "unit/status/selected/enabled", "unit/status/selected/size", "unit/status/midnight_style" },
        impact = "Skipping keeps the current Player status indicators.",
    },
    {
        id = "unit_copy_open", pageKey = "uf_player", icon = "uf_player", area = "unitframes", title = "Copy your Player setup",
        includeSections = { ["region:unit_scope"] = true }, includeEphemeralControls = true, controlLimit = 1,
        controlPaths = { "unit/copy/open" },
        impact = "Skipping leaves the other Unitframes unchanged.",
    },
    {
        id = "unit_copy_all", pageKey = "uf_player", icon = "uf_player", area = "unitframes", title = "Choose what to copy",
        ensureCopyPopup = "unit", includeSections = { ["region:unit_copy_popup"] = true }, includeEphemeralControls = true, controlLimit = 1,
        controlPaths = { "unit/copy/categories/all" },
        impact = "Skipping keeps the currently selected copy categories.",
    },
    {
        id = "unit_copy_apply", pageKey = "uf_player", icon = "uf_player", area = "unitframes", title = "Copy Player to another Unitframe",
        ensureCopyPopup = "unit", includeSections = { ["region:unit_copy_popup"] = true }, includeEphemeralControls = true, controlLimit = 1,
        controlPaths = { "unit/copy/run" },
        impact = "Skipping does not copy the Player setup.",
    },
    {
        id = "group_intro", special = true, pageKey = "guided_setup", icon = "gf_layout", area = "groupframes",
        title = "Part 2 - Group Frames",
        impact = "Skipping starts at the next selected setup area.",
    },
    {
        id = "group_edit_mode", special = true, pageKey = "guided_setup", icon = "gf_layout", area = "groupframes",
        title = "Place your Party frames",
        impact = "Skipping leaves the current Party-frame position unchanged.",
    },
    {
        id = "gf_layout", pageKey = "gf_layout", icon = "gf_layout", area = "groupframes", title = "Build your Party frame",
        includeSections = { general = true }, controlLimit = 5,
        controlPaths = {
            "group/layout/scope/enable_now",
            "group/layout/field/showplayer",
            "group/layout/field/showsolo",
            "group/layout/field/smoothfill",
            "group/layout/field/clickcastenabled",
        },
        impact = "Skipping keeps the current Group Frame basics.",
    },
    {
        id = "gf_party_name", pageKey = "gf_layout", icon = "gf_layout", area = "groupframes", title = "Set up Party names",
        includeSections = { text = true }, includeLockedControls = true,
        prepareSection = "text", prepareTab = "name", prepareState = "gfTextTabSelection", prepareStateIndex = "party", controlLimit = 3,
        controlPaths = { "group/layout/field/showname", "group/layout/field/nameanchor", "group/layout/field/namefontsize" },
        impact = "Skipping keeps the current Party name text.",
    },
    {
        id = "gf_party_hp_text", pageKey = "gf_layout", icon = "gf_layout", area = "groupframes", title = "Set up Party health text",
        includeSections = { text = true }, includeLockedControls = true,
        prepareSection = "text", prepareTab = "hp", prepareState = "gfTextTabSelection", prepareStateIndex = "party", prepareSlot = "center", prepareSlotState = "gfTextSlotSelection", controlLimit = 3,
        controlPaths = { "group/layout/field/showhptext", "group/layout/text/hp/slot/mode", "group/layout/field/hpfontsize" },
        impact = "Skipping keeps the current Party health text.",
    },
    {
        id = "gf_party_power_text", pageKey = "gf_layout", icon = "gf_layout", area = "groupframes", title = "Set up Party power text",
        includeSections = { text = true }, includeLockedControls = true,
        prepareSection = "text", prepareTab = "power", prepareState = "gfTextTabSelection", prepareStateIndex = "party", prepareSlot = "center", prepareSlotState = "gfTextSlotSelection", controlLimit = 3,
        controlPaths = { "group/layout/text/power/show", "group/layout/text/power/slot/mode", "group/layout/field/powerfontsize" },
        impact = "Skipping keeps the current Party power text.",
    },
    {
        id = "gf_party_resource", pageKey = "gf_layout", icon = "gf_layout", area = "groupframes", title = "Build the Party resource bar",
        includeSections = { power = true }, includeLockedControls = true, controlLimit = 4,
        controlPaths = { "group/layout/field/powerbarenabled", "group/layout/field/powerheight", "group/layout/field/powersmoothfill", "group/layout/field/powershowhealer" },
        impact = "Skipping keeps the current Party resource bar.",
    },
    {
        id = "gf_party_range", pageKey = "gf_layout", icon = "gf_layout", area = "groupframes", title = "Tune Party range fade",
        includeSections = { range = true }, includeLockedControls = true, controlLimit = 4,
        controlPaths = { "group/layout/field/rangefadeenabled", "group/layout/field/rangefadelayermode", "group/layout/field/rangefadealpha", "group/layout/field/offlinealpha" },
        impact = "Skipping keeps the current Party range and offline opacity.",
    },
    {
        id = "gf_party_dispel", pageKey = "gf_bars", icon = "gf_bars", area = "groupframes", title = "Build the Party dispel overlay",
        includeSections = { dispel = true }, includeLockedControls = true, controlLimit = 4,
        controlPaths = { "group/bars/field/dispeloverlayenabled", "group/bars/field/dispeloverlaytrigger", "group/bars/field/dispeloverlaystyle", "group/bars/field/dispeloverlayalpha" },
        impact = "Skipping keeps the current Party dispel overlay.",
    },
    {
        id = "gf_party_stripe", pageKey = "gf_bars", icon = "gf_bars", area = "groupframes", title = "Build the Party debuff stripe",
        includeSections = { dstripe = true }, includeLockedControls = true, controlLimit = 3,
        controlPaths = { "group/bars/field/debuffstripeenabled", "group/bars/field/debuffstripeedge", "group/bars/field/debuffstripeheight" },
        impact = "Skipping keeps the current Party debuff stripe.",
    },
    {
        id = "gf_party_indicators", pageKey = "gf_indicators", icon = "gf_indicators", area = "groupframes", title = "Choose Party frame indicators",
        includeSections = { indicators = true }, controlLimit = 4,
        controlPaths = { "group/indicators/field/targetindicator", "group/indicators/field/showgroupnumber", "group/indicators/field/hlfocusenabled", "group/indicators/field/groupborderenabled" },
        impact = "Skipping keeps the current Party frame indicators.",
    },
    {
        id = "gf_party_status", pageKey = "gf_indicators", icon = "gf_indicators", area = "groupframes", title = "Choose Party status icons",
        includeSections = { sicons = true }, includeEphemeralControls = true, includeLockedControls = true,
        prepareSection = "sicons", prepareTab = "basic", prepareState = "gfStatusIconTabSelection", prepareStateIndex = "party", controlLimit = 4,
        controlPaths = { "group/indicators/status/selector", "group/indicators/status/selected/enabled", "group/indicators/status/selected/size", "group/indicators/field/usemidnighticons" },
        impact = "Skipping keeps the current Party status icons.",
    },
    {
        id = "gf_party_corner_icons", pageKey = "gf_indicators", icon = "gf_indicators", area = "groupframes", title = "Build Party corner indicators",
        includeSections = { ci = true }, includeEphemeralControls = true, includeLockedControls = true, controlLimit = 5,
        controlPaths = { "group/indicators/field/cienabled", "group/indicators/field/cisize", "group/indicators/corner/editor/slot", "group/indicators/corner/editor/category", "group/indicators/corner/editor/spell_ids" },
        impact = "Skipping keeps Party corner assignments and custom spells unchanged.",
    },
    {
        id = "gf_party_auras", pageKey = "gf_auras", icon = "gf_auras", area = "groupframes", title = "Choose your Party auras",
        includeSections = { auras = true, ["region:group_aura_tools"] = true }, includeEphemeralControls = true, controlLimit = 2,
        controlPaths = { "auras/group-workspace/container-selector", "auras/group-workspace/lane/buff/tool-selector" },
        impact = "Skipping keeps the current Party aura lane and tool.",
    },
    {
        id = "gf_spell_icons", pageKey = "gf_auras", icon = "gf_auras", area = "groupframes", title = "Spell Icons by spec",
        includeSections = { si = true }, includeEphemeralControls = true, includeLockedControls = true, controlLimit = 16,
        controlPaths = {
            "group/auras/spell/enabled",
            "group/auras/spell/spec",
            "group/auras/spell/selected_aura",
            "group/auras/spell/selected/enabled",
            "group/auras/spell/selected/spell_ids",
            "group/auras/spell/selected/only_mine",
            "group/auras/spell/selected/auto_blacklist",
            "group/auras/spell/selected/placed/type",
            "group/auras/spell/placed/anchor",
            "group/auras/spell/placed/size",
            "group/auras/spell/placed/x",
            "group/auras/spell/placed/y",
            "group/auras/spell/placed/growth",
            "group/auras/spell/placed/iconeffect",
            "group/auras/spell/selected/frame/type",
            "group/auras/spell/frame/alpha",
        },
        impact = "Skipping leaves Spell Icons unchanged; the Assistant can configure them later.",
    },
    {
        id = "group_copy_open", pageKey = "gf_layout", icon = "gf_layout", area = "groupframes", title = "Copy your Party setup",
        includeSections = { ["region:group_scope"] = true }, includeEphemeralControls = true, controlLimit = 1,
        controlPaths = { "group/layout/copy/open" },
        impact = "Skipping leaves Raid and Mythic Raid unchanged.",
    },
    {
        id = "group_copy_all", pageKey = "gf_layout", icon = "gf_layout", area = "groupframes", title = "Choose what to copy",
        ensureCopyPopup = "group", includeSections = { ["region:group_copy_popup"] = true }, includeEphemeralControls = true, controlLimit = 1,
        controlPaths = { "group/copy/categories/all" },
        impact = "Skipping keeps the currently selected copy categories.",
    },
    {
        id = "group_copy_apply", pageKey = "gf_layout", icon = "gf_layout", area = "groupframes", title = "Copy Party to Raid",
        ensureCopyPopup = "group", includeSections = { ["region:group_copy_popup"] = true }, includeEphemeralControls = true, controlLimit = 1,
        controlPaths = { "group/copy/target/raid", "group/copy/target/mythicraid", "group/copy/target/party" },
        impact = "Skipping does not copy the Party setup.",
    },
    {
        id = "class_intro", special = true, pageKey = "guided_setup", icon = "classpower", area = "classresources",
        title = "Part 3 - Class Resources",
        impact = "Skipping leaves Class Resources unchanged.",
    },
    {
        id = "classpower", pageKey = "classpower", icon = "classpower", area = "classresources", title = "Build your Class Resources",
        includeSections = { classpower_display = true }, controlLimit = 4,
        impact = "Skipping keeps the current Class Resource layout.",
    },
    {
        id = "opt_bars", pageKey = "opt_bars", icon = "opt_bars", area = "shared_style", title = "Quick style: bars",
        includeSections = { bars_textures = true }, controlLimit = 2,
        impact = "Skipping keeps the current global bar textures and gradients.",
    },
    {
        id = "opt_fonts", pageKey = "opt_fonts", icon = "opt_fonts", area = "shared_style", title = "Quick style: fonts",
        includeSections = { fonts_global_font = true }, controlLimit = 2,
        impact = "Skipping keeps the current global font settings.",
    },
    {
        id = "power_moves", special = true, pageKey = "guided_setup", icon = "home",
        title = "What makes MSUF different",
        impact = "Skipping only hides the feature overview.",
    },
    {
        id = "final_review", special = true, pageKey = "guided_setup", icon = "home",
        title = "Your setup is ready",
        impact = "Finish the tour and use the Assistant for anything else.",
    },
}

local LEGACY_STAGE_TARGET = {
    uf_focus = "uf_player", uf_pet = "uf_player", uf_target = "unit_copy_open", uf_boss = "unit_copy_open",
    uf_targettarget = "uf_player", uf_focustarget = "uf_player",
    gf_bars = "gf_layout", gf_indicators = "gf_spell_icons", gf_auras = "gf_spell_icons",
    opt_misc = "power_moves", gameplay = "power_moves", modules = "power_moves", profiles = "power_moves",
    opt_castbar = "opt_bars", opt_colors = "opt_bars", auras3_styling = "power_moves",
}

local STAGE_BY_ID = {}
for i = 1, #STAGES do
    STAGES[i].index = i
    STAGE_BY_ID[STAGES[i].id] = STAGES[i]
end
M.guidedTourStageCount = #STAGES

local Tour, Invoke, CurrentStage
local VALID_SETUP_AREA = {
    unitframes = true,
    groupframes = true,
    classresources = true,
    all = true,
}
local VALID_SETUP_MODE = {
    quick = true,
    complete = true,
}
-- Quick Setup is the default beginner route. It reuses the real Menu2 pages,
-- but only visits the decisions that produce an immediately useful layout.
-- The complete tour remains available from the first route screen.
local QUICK_STAGE_CONTROL_LIMITS = {
    menu_basics = 0,
    edit_mode = 0,
    uf_player = 2,
    uf_player_hp_text = 1,
    uf_player_auras = 2,
    group_edit_mode = 0,
    gf_layout = 3,
    gf_party_hp_text = 1,
    gf_party_auras = 2,
    classpower = 2,
    opt_bars = 1,
    opt_fonts = 1,
    final_review = 0,
}

local function SelectedSetupArea()
    local ok, value = Invoke(Tour(), "GetPreference", "setupArea")
    value = ok and tostring(value or "") or ""
    return VALID_SETUP_AREA[value] and value or nil
end

local function SelectedSetupMode()
    local ok, value = Invoke(Tour(), "GetPreference", "setupMode")
    value = ok and tostring(value or "") or ""
    -- Existing in-progress tours predate setupMode and must keep their full
    -- route. Every newly started tour writes an explicit mode below.
    return VALID_SETUP_MODE[value] and value or "complete"
end

local function EffectiveStageControlLimit(stage)
    if SelectedSetupMode() == "quick" then
        return QUICK_STAGE_CONTROL_LIMITS[stage and stage.id] or 0
    end
    return stage and stage.controlLimit or 0
end

local function StageEnabled(stage)
    if type(stage) ~= "table" then return false end
    if SelectedSetupMode() == "quick" and QUICK_STAGE_CONTROL_LIMITS[stage.id] == nil then return false end
    if not stage.area then return true end
    local selected = SelectedSetupArea() or "all"
    if selected == "all" then return true end
    if stage.area == "shared_style" then
        return selected == "unitframes" or selected == "groupframes"
    end
    return stage.area == selected
end

local function ActiveStages()
    local stages = {}
    for i = 1, #STAGES do
        if StageEnabled(STAGES[i]) then stages[#stages + 1] = STAGES[i] end
    end
    return stages
end

local function ActiveStagePosition(stage, stages)
    stages = stages or ActiveStages()
    for i = 1, #stages do
        if stages[i] == stage or stages[i].id == (stage and stage.id) then return i, #stages, stages end
    end
    return 1, #stages, stages
end

function M.GetGuidedTourStageProgress()
    local stage = CurrentStage and CurrentStage() or STAGES[1]
    local current, total = ActiveStagePosition(stage)
    return current, total, stage and stage.id
end
function M.GetGuidedTourMode()
    return SelectedSetupMode()
end

local function StageIncludesSection(stage, sectionId)
    if type(stage) ~= "table" then return true end
    local included = stage.includeSections
    if type(included) == "table" and included[sectionId] ~= true then return false end
    local excluded = stage.excludeSections
    return type(excluded) ~= "table" or excluded[sectionId] ~= true
end
function M.IsGuidedTourSectionIncluded(stageId, sectionId)
    return StageIncludesSection(STAGE_BY_ID[tostring(stageId or "")], tostring(sectionId or ""))
end
function M.GuidedTourIncludesEphemeralControls(stageId)
    local stage = STAGE_BY_ID[tostring(stageId or "")]
    return type(stage) == "table" and stage.includeEphemeralControls == true
end

local Runtime = M._guidedTourRuntime or {}
M._guidedTourRuntime = Runtime
local EnsureGuidedTourChrome

Tour = function()
    return type(MSUF.GuidedTour6) == "table" and MSUF.GuidedTour6 or nil
end

local function FirstLoad()
    return type(MSUF.FirstLoad6) == "table" and MSUF.FirstLoad6 or nil
end

--- Optional Tour methods are independent lifecycle boundaries. Failures report
--- through ApplyService and read as unavailable instead of breaking Menu2.
Invoke = function(object, method, ...)
    local fn = object and object[method]
    if type(fn) ~= "function" then return false end
    local called, a, b, c = InvokeGuidedBoundary(fn, object, ...)
    return called and a ~= false, a, b, c
end

local function TourIsActive()
    local ok, active = Invoke(Tour(), "IsActive")
    return ok and active == true
end

local function TourState()
    local ok, state = Invoke(Tour(), "GetState")
    return ok and type(state) == "table" and state or {}
end

CurrentStage = function()
    local state = TourState()
    local stateId = tostring(state.currentStageId or "")
    local mappedId = LEGACY_STAGE_TARGET[stateId]
    local stage = STAGE_BY_ID[stateId] or (mappedId and STAGE_BY_ID[mappedId])
    if stage and not StageEnabled(stage) then stage = ActiveStages()[1] end
    if stage and (stateId ~= stage.id or tonumber(state.currentStageIndex) ~= stage.index) then
        Invoke(Tour(), "SetStage", stage.id, stage.index)
    end
    if not stage then stage = STAGES[min(max(tonumber(state.currentStageIndex) or 1, 1), #STAGES)] end
    return stage or STAGES[1]
end

local function ActiveProfileName()
    local profile = tostring(_G.MSUF_ActiveProfile or "Default")
    return profile ~= "" and profile or "Default"
end

local function ProfileMismatch()
    local state = TourState()
    local tourProfile = tostring(state.profileName or "")
    local activeProfile = ActiveProfileName()
    return tourProfile ~= "" and tourProfile ~= activeProfile, tourProfile, activeProfile
end

local function PlayerDisplayName()
    local name
    if type(_G.UnitName) == "function" then
        name = _G.UnitName("player")
    end
    if type(_G.issecretvalue) == "function" and _G.issecretvalue(name) then name = nil end
    if type(name) == "string" then name = name:match("^[^-]+") else name = nil end
    if not name or name == "" or name == "Unknown" then name = Tr("Player") end
    return name
end

local function Preference(key, fallback)
    local ok, value = Invoke(Tour(), "GetPreference", key)
    if not ok or value == nil or value == "" then return fallback end
    return value
end

local function SetupAreaDecisionComplete()
    return SelectedSetupArea() ~= nil
end

local COOLDOWN_ANCHOR_PREFERENCE = "unitframeCooldownAnchor"
local EDIT_MODE_MOVED_PREFERENCE = "editModeMoved"
local EDIT_MODE_MOVED_KEY_PREFERENCE = "editModeMovedKey"
local VALID_COOLDOWN_ANCHOR_DECISION = { cooldown = true, independent = true }
local function AutomaticCooldownProvider()
    local getter = _G.MSUF_GetAutomaticCooldownAnchorProvider
    if type(getter) ~= "function" then return nil, nil end
    return getter()
end
local function CooldownAnchorEnabled()
    local general = type(M.GetGeneralDB) == "function" and M.GetGeneralDB() or nil
    if type(general) ~= "table" then
        local db = _G.MSUF_DB
        general = type(db) == "table" and db.general or nil
    end
    local getter = _G.MSUF_IsCooldownAnchorEnabled
    if type(getter) == "function" then return getter(general) == true end
    return type(general) == "table" and general.anchorToCooldown == true or false
end
local function CooldownConsentDecision()
    local providerId = AutomaticCooldownProvider()
    local getter = _G.MSUF_GetCooldownAnchorConsentDecision
    if not providerId or type(getter) ~= "function" then return nil end
    return getter(providerId)
end
local function CooldownAnchorDecision()
    local value = Preference(COOLDOWN_ANCHOR_PREFERENCE)
    if VALID_COOLDOWN_ANCHOR_DECISION[value] then return value end
    if CooldownConsentDecision() ~= nil then
        return CooldownAnchorEnabled() and "cooldown" or "independent"
    end
    return nil
end
local function CooldownAnchorDecisionComplete()
    return CooldownAnchorDecision() ~= nil
end
local function EditModePlacementComplete()
    return Preference(EDIT_MODE_MOVED_PREFERENCE) == true
        and Preference("editModePopupOpened") == true
end
local function EditModeMovementComplete()
    return Preference(EDIT_MODE_MOVED_PREFERENCE) == true
end
local function GroupEditModePlacementComplete()
    return Preference("groupEditModeMoved") == true and Preference("groupEditModePopupOpened") == true
end
local function GroupEditModeMovementComplete()
    return Preference("groupEditModeMoved") == true
end
M.GetGuidedCooldownAnchorDecision = CooldownAnchorDecision
M.IsGuidedEditModePlacementUnlocked = CooldownAnchorDecisionComplete
M.IsGuidedEditModePlacementComplete = EditModePlacementComplete
M.IsGuidedGroupEditModePlacementComplete = GroupEditModePlacementComplete

local PREFERENCE_LABELS = {
    quick = "Quick Setup",
    complete = "Complete Tour",
    unitframes = "Unitframes",
    groupframes = "Group Frames",
    classresources = "Class Resources",
    all = "Everything",
    general = "General play",
    solo = "Solo and world",
    dungeons = "Dungeons",
    raid = "Raid and Mythic",
    calm = "Clean and calm",
    balanced = "Balanced",
    detailed = "Full combat detail",
}

local function PreferenceLabel(value)
    return Tr(PREFERENCE_LABELS[value] or "Balanced")
end

local function PersonalizedTitle(stage)
    if stage.id == "menu_basics" then return format(Tr("Welcome, %s"), PlayerDisplayName()) end
    if stage.id == "final_review" then return format(Tr("%s, your setup is ready"), PlayerDisplayName()) end
    if SelectedSetupArea() ~= "all" then
        if stage.id == "unit_intro" then return Tr("Unitframes") end
        if stage.id == "group_intro" then return Tr("Group Frames") end
        if stage.id == "class_intro" then return Tr("Class Resources") end
    end
    return Tr(stage.title)
end

local function ControlIsAction(control)
    return control and (control.classification == "action" or control.kind == "button")
end

local function ShortControlHelp(control, limit)
    local help = tostring(control and control.help or ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    limit = tonumber(limit) or 112
    if #help > limit then
        help = help:sub(1, limit - 3):gsub("%s+%S*$", "") .. "..."
    end
    return help ~= "" and Tr(help) or nil
end

local function LockedControlCue(control)
    local id = tostring(control and control.id or ""):lower()
    if id:find("corner", 1, true) then
        return Tr("UNLOCK, THEN CHANGE IT - Enable Corner Indicators, choose a slot, then select Custom Spell when requested.")
    end
    if id:find("spell", 1, true) then
        if id:find("placed", 1, true) then
            return Tr("UNLOCK, THEN CHANGE IT - Enable Spell Indicators, choose a spell, then set Indicator Type.")
        end
        if id:find("frame", 1, true) then
            return Tr("UNLOCK, THEN CHANGE IT - Enable Spell Indicators, choose a spell, then select a Frame Effect.")
        end
        if id:find("selected", 1, true) then
            return Tr("UNLOCK, THEN CHANGE IT - Enable Spell Indicators, choose a spec, then press a tracked spell tile.")
        end
        return Tr("UNLOCK, THEN CHANGE IT - Turn on Spell Indicators in the earlier checkpoint; use Back if you skipped it.")
    end
    return Tr("UNLOCK, THEN CHANGE IT - Enable the parent feature in this section first.")
end

local function ControlCue(control, touched)
    if not control then return nil end
    local label = Tr(control.label)
    if control.actionable == false then return LockedControlCue(control) end
    if touched then
        return format(Tr("CHANGED +10 XP - %s updated. Fine-tune it or claim the checkpoint."), label)
    end
    local kind = tostring(control.kind or ""):lower()
    local verb, action
    if ControlIsAction(control) then
        verb, action = "PRESS", Tr("Use the highlighted action now.")
    elseif kind == "toggle" or kind == "switch" or kind == "checkbox" then
        verb, action = "CHANGE", Tr("Click it to switch the value and watch the Live Preview.")
    elseif kind == "dropdown" then
        verb, action = "CHANGE", Tr("Open it and choose a different value.")
    elseif kind == "slider" then
        verb, action = "CHANGE", Tr("Drag it to a new value while watching the Live Preview.")
    elseif kind == "textinput" or kind == "editbox" then
        verb, action = "CHANGE", Tr("Type a new value, then press Enter.")
    elseif kind == "color" then
        verb, action = "CHANGE", Tr("Pick a different color and confirm it.")
    elseif kind == "segment" or kind == "tabs" then
        verb, action = "CHANGE", Tr("Press a different option and watch the Live Preview.")
    else
        verb, action = "CHANGE", ShortControlHelp(control) or Tr("Alter this setting and watch the result live.")
    end
    return format("%s %s - %s", Tr(verb), label, action)
end

local function StageCue(stage, position, touched)
    local section = position and position.section
    local control = position and position.control
    if control then return ControlCue(control, touched) end
    local sectionId = section and (tostring(section.id or "") .. " " .. tostring(section.label or "")):lower() or ""
    if section then
        if sectionId:find("preview", 1, true) then
            if stage.id == "opt_bars" then
                return Tr("Sample = visual only · real changes = Unit/Group Preview · frame placement = MSUF Edit Mode")
            end
            if stage.id == "opt_castbar" then
                return Tr("Normal/Channel/Empowered = simulation · Interrupt = feedback · handles = saved position")
            end
            if stage.id == "auras3_styling" or stage.id == "gf_auras" then
                return Tr("Live/Dummy = display only · colored aura handles = saved positions")
            end
            if stage.id:match("^gf_") then
                return Tr("Scope = Party/Raid/Mythic · drag = inner position · Shift-layer = isolate · Ctrl-wheel/drag = zoom/pan · Edit Mode = container")
            end
            if stage.id == "classpower" then
                return Tr("Preview controls = inspect layouts and states · MSUF Edit Mode = whole-frame placement")
            end
            return Tr("Preview controls = inspect layouts and states · MSUF Edit Mode = whole-frame placement")
        end
        return format(Tr("CHECKPOINT - Press Enter section to explore every setting in %s."), Tr(section.label))
    end
    if stage.id == "menu_basics" then
        if SetupAreaDecisionComplete() then
            return format(Tr("ROUTE READY - %s, %s. Press Start."), PreferenceLabel(SelectedSetupMode()), PreferenceLabel(SelectedSetupArea()))
        end
        return Tr("YOUR MOVE - Choose what you want to set up.")
    end
    if stage.id == "unit_intro" then return Tr("PART 1 - Build Player once, then copy the finished setup to the other Unitframes.") end
    if stage.id == "edit_mode" then
        local decision = CooldownAnchorDecision()
        if decision and EditModePlacementComplete() then
            return Tr("CHECKPOINT CLEAR - Exit Edit Mode when happy, then claim the checkpoint.")
        end
        if decision and EditModeMovementComplete() then
            return Tr("YOUR MOVE - Click the highlighted Player mover to open its Width and Height popup.")
        end
        if decision == "cooldown" then
            return Tr("YOUR MOVE - Press Open MSUF Edit Mode, then drag the double-arrow frame once.")
        end
        if decision == "independent" then
            return Tr("YOUR MOVE - Press Open MSUF Edit Mode, then drag the double-arrow frame once.")
        end
        return Tr("YOUR MOVE - Choose Follow Blizzard's Essential Cooldowns or Independent placement below.")
    end
    if stage.id == "group_intro" then return Tr("PART 2 - Build Party once, then copy it to Raid or Mythic Raid.") end
    if stage.id == "group_edit_mode" then
        if GroupEditModePlacementComplete() then return Tr("CHECKPOINT CLEAR - Party Frames moved. Click the mover for its size and spacing popup whenever you need it.") end
        if GroupEditModeMovementComplete() then return Tr("YOUR MOVE - Click the highlighted Party Frames mover to open Width, Height, and Spacing.") end
        return Tr("YOUR MOVE - Open Edit Mode, drag Party Frames once, then click the mover to see its Width, Height, and Spacing popup.")
    end
    if stage.id == "class_intro" then return Tr("PART 3 - Shape Class Resources with its interactive preview and cooldown-aware anchoring.") end
    if stage.id == "uf_player" then return Tr("PLAYER IS THE MASTER - Change the highlighted frame basics; the Live Preview updates immediately.") end
    if stage.id == "uf_player_auras" then return Tr("AURA WORKSPACE - Choose Buffs, Debuffs, or a Custom lane, then choose Layout, Filters, or Blacklist.") end
    if stage.id:match("^uf_player_") then return Tr("PLAYER CORE - Change the new green setting and watch the same Player Preview update.") end
    if stage.id:match("^unit_copy_") then return Tr("COPY FLOW - Open Copy To, select All categories, then apply the Player setup to another Unitframe.") end
    if stage.id == "gf_spell_icons" then
        return Tr("MISSION BRIEF - Build Spell Icons from scope and spec through placement, cooldowns, and frame effects.")
    end
    if stage.id == "gf_layout" then return Tr("PARTY IS THE MASTER - Adjust its frame basics, then copy the finished result to Raid or Mythic Raid.") end
    if stage.id == "gf_party_auras" then return Tr("AURA WORKSPACE - Choose Buffs, Debuffs, or External Defensives, then choose the editing tool.") end
    if stage.id == "gf_party_corner_icons" then return Tr("MSUF POWER MOVE - Assign each corner or bind a custom spell to the selected slot.") end
    if stage.id:match("^gf_party_") then return Tr("PARTY CORE - Change the new green setting and watch the Party Preview update.") end
    if stage.id:match("^group_copy_") then return Tr("COPY FLOW - Open Copy To, select All categories, then press a destination to copy Party instantly.") end
    if stage.id == "opt_bars" then return Tr("Sample = visual only · tests = temporary · scope = shared/unit/group") end
    if stage.id == "opt_castbar" then return Tr("Simulate casts here; position castbar handles in Preview or MSUF Edit Mode.") end
    if stage.id == "opt_fonts" then return Tr("Use the scope selector for shared, unit and group text; compare readability in Preview.") end
    if stage.id == "auras3_styling" then return Tr("Live/Dummy = display only · colored handles = saved positions · scope = shared/unit/group/custom") end
    if stage.id == "classpower" then return Tr("Use the interactive preview for layouts and states; use Edit Mode for whole-frame placement.") end
    if stage.id == "profiles" then return Tr("Finish with a profile check and export a backup of your setup.") end
    if stage.id == "power_moves" then return Tr("MSUF POWER MOVES - Scan the highlights, then press Continue.") end
    if stage.id == "final_review" then return Tr("MISSION COMPLETE - Press Finish to open the Assistant on your Dashboard.") end
    return Tr("Review the highlighted sections; previews update while your changes autosave.")
end

local function BlockedByCombat()
    return type(M.BlockCombatAction) == "function" and M.BlockCombatAction() == true
end

local function SetGuidedCooldownAnchorDecision(value)
    if not VALID_COOLDOWN_ANCHOR_DECISION[value] or BlockedByCombat() then return false end
    local previousDecision = CooldownAnchorDecision()
    local enabled = value == "cooldown"
    local general = type(M.GetGeneralDB) == "function" and M.GetGeneralDB() or nil
    if type(general) ~= "table" then
        local db = _G.MSUF_DB
        if type(db) ~= "table" then return false end
        db.general = type(db.general) == "table" and db.general or {}
        general = db.general
    end
    local setter = _G.MSUF_SetCooldownAnchorEnabled
    if type(setter) == "function" then
        if setter(enabled, true) == false then return false end
    elseif general.anchorToCooldown ~= enabled then
        if type(M.SetGeneralValue) == "function" then
            if M.SetGeneralValue("anchorToCooldown", enabled, "MSUF2_GUIDED_COOLDOWN_ANCHOR") == false then return false end
        else
            general.anchorToCooldown = enabled
        end
    end
    local stored = Invoke(Tour(), "SetPreference", COOLDOWN_ANCHOR_PREFERENCE, value)
    if not stored then return false end
    if previousDecision ~= value then
        Invoke(Tour(), "SetPreference", EDIT_MODE_MOVED_PREFERENCE, nil)
        Invoke(Tour(), "SetPreference", EDIT_MODE_MOVED_KEY_PREFERENCE, nil)
        Invoke(Tour(), "SetPreference", "editModePopupOpened", nil)
        Invoke(Tour(), "SetPreference", "editModePopupOpenedKey", nil)
    end
    local apply = M.ApplyService or _G.MSUF_Menu2_ApplyService
    if type(apply) == "table" and type(apply.Flush) == "function" then apply.Flush() end
    return true
end
M.SetGuidedCooldownAnchorDecision = SetGuidedCooldownAnchorDecision

local function RefreshEditModePlacementCue()
    local editMode = _G.MSUF_EM2
    local movers = editMode and editMode.Movers
    if movers and type(movers.RefreshGuidedPlacementCue) == "function" then
        movers.RefreshGuidedPlacementCue()
    end
end

local function ShouldShowEditModeOpenCue()
    if not TourIsActive() or CurrentStage().id ~= "edit_mode" then return false end
    if not CooldownAnchorDecisionComplete() or EditModePlacementComplete() then return false end
    local status = type(M.EditModeLifecycleStatus) == "function" and M.EditModeLifecycleStatus() or {}
    return status.active ~= true and status.combatLocked ~= true
end
M.ShouldShowGuidedEditModeOpenCue = ShouldShowEditModeOpenCue

local function RefreshEditModeOpenCue(show)
    local T = M.Theme
    local button = M.dashboardToolbarEditModeButton
    local cue = Runtime.editModeOpenCue
    show = show == true and button ~= nil and T ~= nil
    if not show then
        if cue then cue:Hide() end
        Runtime.editModeOpenCueVisible = nil
        return
    end
    if not cue or cue:GetParent() ~= button then
        if cue then cue:Hide() end
        cue = CreateFrame("Frame", nil, button)
        cue:SetAllPoints(button)
        cue:EnableMouse(false)
        cue:SetFrameLevel((button:GetFrameLevel() or 1) + 12)
        local color = T.colors.ok or { 0.24, 0.82, 0.46, 1 }
        local function Arrow(point, rotation)
            local texture = cue:CreateTexture(nil, "OVERLAY", nil, 7)
            local usedAtlas = false
            if texture.SetAtlas then texture:SetAtlas("NPE_ArrowRight", false); usedAtlas = true end
            if not usedAtlas and T.media then texture:SetTexture(T.media.collapseArrow) end
            texture:SetSize(20, 20)
            texture:SetPoint(point, cue, point, point == "LEFT" and 3 or -3, 0)
            if rotation and texture.SetRotation then texture:SetRotation(rotation) end
            texture:SetVertexColor(color[1], color[2], color[3], 1)
            return texture
        end
        cue._leftArrow = Arrow("LEFT")
        cue._rightArrow = Arrow("RIGHT", math.pi)
        Runtime.editModeOpenCue = cue
    end
    cue:Show()
    if not Runtime.editModeOpenCueVisible then
        Runtime.editModeOpenCueVisible = true
        if type(T.PlayMotion) == "function" then
            T.PlayMotion(cue, "controlFocusIn", { fromAlpha = 0.30, toAlpha = 1, duration = 0.18 })
        end
        if type(T.PlayNeonFlash) == "function" then
            T.PlayNeonFlash(button, "success", { alpha = 0.28, duration = 0.80 })
        end
    end
end

function M.NotifyGuidedEditModeMoved(moverKey)
    local ok, marked = Invoke(Tour(), "MarkEditModePlacementComplete", moverKey)
    if not ok or marked ~= true then return false end
    RefreshEditModePlacementCue()
    if M.activeKey == "guided_setup" and type(M.RequestRefresh) == "function" then
        M.RequestRefresh(nil, "GUIDED_EDIT_MODE_MOVED")
    end
    if type(M.RefreshGuidedTourChrome) == "function" then
        M.RefreshGuidedTourChrome("EDIT_MODE_MOVED")
    end
    return true
end

function M.NotifyGuidedEditModePopupOpened(moverKey)
    local ok, marked = Invoke(Tour(), "MarkEditModePopupOpened", moverKey)
    if not ok or marked ~= true then return false end
    RefreshEditModePlacementCue()
    if M.activeKey == "guided_setup" and type(M.RequestRefresh) == "function" then
        M.RequestRefresh(nil, "GUIDED_EDIT_MODE_POPUP_OPENED")
    end
    if type(M.RefreshGuidedTourChrome) == "function" then
        M.RefreshGuidedTourChrome("EDIT_MODE_POPUP_OPENED")
    end
    return true
end

local function LiveEditModePopupKey()
    local editMode = _G.MSUF_EM2
    local popups = editMode and editMode.Popups
    if not (popups and type(popups.IsAnyOpen) == "function" and popups.IsAnyOpen()) then return nil end
    local focus = editMode.Focus
    local key = focus and type(focus.GetSelection) == "function" and focus.GetSelection() or nil
    if not key then
        local state = editMode.State
        key = state and type(state.GetUnitKey) == "function" and state.GetUnitKey() or nil
    end
    return tostring(key or "")
end

local function ReconcileGuidedEditModePopup(stage)
    if not TourIsActive() then return false end
    stage = stage or CurrentStage()
    local key = LiveEditModePopupKey()
    if key == "" then return false end
    if stage.id == "group_edit_mode" then
        if key ~= "gf_party" and key ~= "party" then return false end
    elseif stage.id == "edit_mode" then
        if key ~= "player" then return false end
    else
        return false
    end
    local ok, accepted, changed = Invoke(Tour(), "MarkEditModePopupOpened", key)
    return ok and accepted == true and changed == true
end
M.ReconcileGuidedEditModePopup = ReconcileGuidedEditModePopup

local function OpenGuidedEditModePopup(key, stage)
    local editMode = _G.MSUF_EM2
    local popups = editMode and editMode.Popups
    if not (popups and type(popups.Open) == "function") then return false end
    local mover = editMode.Movers and type(editMode.Movers.Get) == "function" and editMode.Movers.Get(key) or nil
    local opened = popups.Open(key, mover)
    if opened ~= true and type(popups.IsAnyOpen) == "function" then opened = popups.IsAnyOpen() == true end
    if not opened then return false end
    ReconcileGuidedEditModePopup(stage)
    return true
end

local function ExpectedPage(stage)
    stage = stage or CurrentStage()
    return stage.special and "guided_setup" or stage.pageKey
end

local function SafeText(fontString)
    if type(fontString) == "string" then return fontString end
    if not (fontString and type(fontString.GetText) == "function") then return "" end
    local value = tostring(fontString:GetText() or "")
    return value:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
end

local function FrameTop(frame)
    if not (frame and type(frame.GetTop) == "function") then return nil end
    return tonumber(frame:GetTop()) or nil
end

local function FrameLeft(frame)
    if not (frame and type(frame.GetLeft) == "function") then return nil end
    return tonumber(frame:GetLeft()) or nil
end

local IsWidgetInside

local function RefreshCachedSectionDescriptors(cached)
    local sections = cached and cached.sections
    if type(sections) ~= "table" then return false end
    for i = 1, #sections do
        local section = sections[i]
        local entry = section.entry
        if type(entry) ~= "table" or tonumber(entry.guidedOrder) ~= section.guidedOrder then return false end
        if section.region then
            local body = entry.body or entry.outer
            local outer = entry.outer or body
            if body ~= section.body or outer ~= section.outer then return false end
            local label = SafeText(entry.label)
            if label == "" then label = SafeText(body and body.title) end
            section.label = label ~= "" and label or "Scope and overrides"
        else
            if entry.body ~= section.body or entry.outer ~= section.outer then return false end
            local label = SafeText(entry.label)
            section.label = label ~= "" and label or tostring(section.id or "Section")
        end
    end
    return true
end

local function SortedSections(pageKey)
    local entry = M.cache and M.cache[pageKey]
    local source = entry and entry.sections
    local regions = entry and entry.guidedRegions
    local cached = entry and entry._msuf2GuidedSortedSections
    if cached and cached.source == source and cached.regions == regions
        and RefreshCachedSectionDescriptors(cached)
    then
        return cached.sections
    end
    if entry then entry._msuf2GuidedSortedSections = nil end
    local sections = {}
    local orders = {}
    local stableOrder = true
    if type(source) == "table" then
        for sectionId, body in pairs(source) do
            local collapsible = body and body._msuf2CollapsibleEntry
            if collapsible then
                local label = SafeText(collapsible.label)
                if label == "" then label = tostring(sectionId or "Section") end
                local guidedOrder = tonumber(collapsible.guidedOrder)
                if guidedOrder == nil or orders[guidedOrder] then
                    stableOrder = false
                else
                    orders[guidedOrder] = true
                end
                sections[#sections + 1] = {
                    id = tostring(sectionId or ""),
                    body = body,
                    outer = collapsible.outer,
                    entry = collapsible,
                    label = label,
                    guidedOrder = guidedOrder,
                    collapsible = true,
                }
            end
        end
    end
    if type(regions) == "table" then
        for regionId, region in pairs(regions) do
            local body = type(region) == "table" and (region.body or region.outer) or nil
            local outer = type(region) == "table" and (region.outer or body) or nil
            if body and outer then
                local label = SafeText(region.label)
                if label == "" then label = SafeText(body.title) end
                if label == "" then label = "Scope and overrides" end
                local guidedOrder = tonumber(region.guidedOrder)
                if guidedOrder == nil or orders[guidedOrder] then
                    stableOrder = false
                else
                    orders[guidedOrder] = true
                end
                sections[#sections + 1] = {
                    id = "region:" .. tostring(region.id or regionId or ""),
                    body = body,
                    outer = outer,
                    entry = region,
                    label = label,
                    guidedOrder = guidedOrder,
                    region = true,
                }
            end
        end
    end
    if not stableOrder then
        for i = 1, #sections do sections[i].top = FrameTop(sections[i].outer) end
    end
    sort(sections, function(a, b)
        if a.guidedOrder ~= b.guidedOrder then
            if a.guidedOrder == nil then return false end
            if b.guidedOrder == nil then return true end
            return a.guidedOrder < b.guidedOrder
        end
        if a.top ~= b.top then
            if a.top == nil then return false end
            if b.top == nil then return true end
            return a.top > b.top
        end
        return a.id < b.id
    end)
    if entry and stableOrder then
        entry._msuf2GuidedSortedSections = { source = source, regions = regions, sections = sections }
    end
    return sections
end

function M.RegisterGuidedCopyPopup(kind, pageKey, ensureVisible)
    kind, pageKey = tostring(kind or ""), tostring(pageKey or "")
    if kind == "" or pageKey == "" or type(ensureVisible) ~= "function" then return false end
    Runtime.copyPopupOpeners = Runtime.copyPopupOpeners or {}
    Runtime.copyPopupOpeners[kind] = Runtime.copyPopupOpeners[kind] or {}
    Runtime.copyPopupOpeners[kind][pageKey] = ensureVisible
    return true
end

local function EnsureStageSurface(stage)
    if type(stage) == "table" and stage.area == "groupframes" and stage.special ~= true and M.gfScope ~= "party" then
        local pageEntry = M.cache and M.cache[stage.pageKey]
        local scopeRegion = pageEntry and pageEntry.guidedRegions and pageEntry.guidedRegions.group_scope
        local selectScope = scopeRegion and scopeRegion.body and scopeRegion.body._msuf2GuidedSelectScope
        local prepared
        if type(selectScope) == "function" then
            local ok, value = InvokeGuidedBoundary(selectScope, "party")
            prepared = ok and value ~= false
        end
        if not prepared then
            if type(M.SetMenuStateValue) == "function" then M.SetMenuStateValue("gfScope", "party") else M.gfScope = "party" end
        end
    end
    if type(stage) == "table" and stage.prepareSection and stage.prepareTab and stage.prepareState then
        local pageEntry = M.cache and M.cache[stage.pageKey]
        local section = pageEntry and pageEntry.sections and pageEntry.sections[stage.prepareSection]
        local selectTab = section and section._msuf2GuidedSelectTab
        local prepared
        if type(selectTab) == "function" then
            local ok, value = InvokeGuidedBoundary(selectTab, stage.prepareTab)
            prepared = ok and value ~= false
        end
        if not prepared then
            local state = M[stage.prepareState]
            if type(state) ~= "table" then
                state = {}
                M[stage.prepareState] = state
            end
            state[stage.prepareStateIndex or "player"] = stage.prepareTab
        end
    end
    if type(stage) == "table" and stage.prepareSection and stage.prepareTab and stage.prepareSlot and stage.prepareSlotState then
        local pageEntry = M.cache and M.cache[stage.pageKey]
        local section = pageEntry and pageEntry.sections and pageEntry.sections[stage.prepareSection]
        local selectSlot = section and section._msuf2GuidedSelectSlot
        local prepared
        if type(selectSlot) == "function" then
            local ok, value = InvokeGuidedBoundary(selectSlot, stage.prepareTab, stage.prepareSlot)
            prepared = ok and value ~= false
        end
        if not prepared then
            local state = M[stage.prepareSlotState]
            if type(state) ~= "table" then state = {}; M[stage.prepareSlotState] = state end
            local index = stage.prepareStateIndex or "player"
            if type(state[index]) ~= "table" then state[index] = {} end
            state[index][stage.prepareTab] = stage.prepareSlot
        end
    end
    local kind = stage and stage.ensureCopyPopup
    if not kind then return true end
    if tostring(Runtime.touchedSignature or ""):match("^" .. tostring(stage.id or "") .. "\031") then return true end
    local byKind = Runtime.copyPopupOpeners and Runtime.copyPopupOpeners[kind]
    local ensureVisible = byKind and byKind[stage.pageKey]
    if type(ensureVisible) ~= "function" then return false end
    local ok, visible = InvokeGuidedBoundary(ensureVisible)
    return ok and visible ~= false
end

local function StageSections(stage)
    EnsureStageSurface(stage)
    local sections = SortedSections(stage and stage.pageKey)
    if type(stage) ~= "table" then return sections end
    local function Filter(source)
        local filtered = {}
        for i = 1, #source do
            local section = source[i]
            if StageIncludesSection(stage, section.id) then filtered[#filtered + 1] = section end
        end
        return filtered
    end
    local filtered = Filter(sections)
    local W = M.Widgets
    local materialized
    if W and type(W.FocusCollapsibleSection) == "function" then
        for i = 1, #filtered do
            local section = filtered[i]
            if section.collapsible and section.entry and section.entry.open ~= true then
                W.FocusCollapsibleSection(section.body, { persist = false, flash = false, scroll = false })
                materialized = true
            end
        end
    end
    if materialized then filtered = Filter(SortedSections(stage.pageKey)) end
    return filtered
end

local function ClearControlEmphasis()
    Runtime.controlEmphasisSignature = nil
    Runtime.controlEmphasisWidget = nil
    local emphasized = Runtime.controlEmphasis
    if type(emphasized) ~= "table" then return end
    for i = 1, #emphasized do
        local item = emphasized[i]
        local widget = item and item.widget
        if widget and type(widget.SetAlpha) == "function" and item.originalAlpha ~= nil then
            local current = type(widget.GetAlpha) == "function" and widget:GetAlpha() or item.appliedAlpha
            if current == nil or item.appliedAlpha == nil or math.abs(current - item.appliedAlpha) < 0.001 then
                widget:SetAlpha(item.originalAlpha)
            end
        end
        local marker = item and item.marker
        if marker then
            if M.Theme and type(M.Theme.StopMotion) == "function" then M.Theme.StopMotion(marker) end
            if type(marker.Hide) == "function" then marker:Hide() end
        end
    end
    Runtime.controlEmphasis = nil
end

local function ClearSectionEmphasis(pageKey)
    Runtime.emphasisSignature = nil
    ClearControlEmphasis()
    local cache = M.cache
    if type(cache) ~= "table" then return end
    for key in pairs(cache) do
        if pageKey == nil or key == pageKey then
            local sections = SortedSections(key)
            for i = 1, #sections do
                local section = sections[i]
                local outer = section.outer
                if outer and outer.SetAlpha and outer._msuf2GuidedOriginalAlpha ~= nil then
                    outer:SetAlpha(outer._msuf2GuidedOriginalAlpha)
                    outer._msuf2GuidedOriginalAlpha = nil
                end
                local flash = outer and outer._msuf2NeonFlash
                if flash then
                    if flash._msuf2FlashGroup and flash._msuf2FlashGroup.Stop then flash._msuf2FlashGroup:Stop() end
                    if flash.SetAlpha then flash:SetAlpha(0) end
                    if flash.Hide then flash:Hide() end
                end
                local marker = section.entry and section.entry._msuf2GuidedArrow
                if marker then
                    if M.Theme and type(M.Theme.StopMotion) == "function" then M.Theme.StopMotion(marker) end
                    marker:Hide()
                end
                local controlMarker = section.entry and section.entry._msuf2GuidedControlArrow
                if controlMarker then
                    if M.Theme and type(M.Theme.StopMotion) == "function" then M.Theme.StopMotion(controlMarker) end
                    controlMarker:Hide()
                end
            end
        end
    end
end

local function EmphasizeSection(pageKey, current, currentControl)
    local T = M.Theme
    local sections = SortedSections(pageKey)
    local signature = tostring(pageKey or "") .. "\031" .. tostring(current and current.id or "")
    local animate = Runtime.emphasisSignature ~= signature
    Runtime.emphasisSignature = signature
    for i = 1, #sections do
        local section = sections[i]
        local entry = section.entry
        local selected = current and section.id == current.id
        local outer = section.outer
        if outer and outer.SetAlpha and outer._msuf2GuidedOriginalAlpha ~= nil then
            -- Older tour builds dimmed every non-current section. Restore that
            -- state once and keep the whole page readable and interactive.
            outer:SetAlpha(outer._msuf2GuidedOriginalAlpha)
            outer._msuf2GuidedOriginalAlpha = nil
        end
        local marker = entry._msuf2GuidedArrow
        if selected and not marker and outer and outer.CreateTexture and T and T.media then
            marker = outer:CreateTexture(nil, "OVERLAY", nil, 7)
            local usedAtlas = false
            if marker.SetAtlas then
                marker:SetAtlas("NPE_ArrowRight", false)
                usedAtlas = true
            end
            if not usedAtlas then marker:SetTexture(T.media.collapseArrow) end
            marker:SetSize(20, 20)
            marker:SetPoint("RIGHT", outer, "LEFT", -4, 0)
            local color = T.colors.accent
            marker:SetVertexColor(color[1], color[2], color[3], 1)
            entry._msuf2GuidedArrow = marker
        end
        if marker then
            local showMarker = selected and not currentControl
            marker:SetShown(showMarker and true or false)
            if showMarker and animate and T and type(T.PlayMotion) == "function" then
                T.PlayMotion(marker, "controlFocusIn", { fromAlpha = 0.28, toAlpha = 1, duration = 0.16 })
            end
        end
    end
end

IsWidgetInside = function(widget, ancestor)
    local current = widget
    for _ = 1, 48 do
        if not current then return false end
        if current == ancestor then return true end
        if type(current.GetParent) ~= "function" then return false end
        local parent = current:GetParent()
        if parent == current then return false end
        current = parent
    end
    return false
end

local function RuntimeControlRecords()
    local catalog = M.RuntimeControlCatalog
    if not (catalog and type(catalog.GetRecords) == "function") then return {} end
    local ok, records = InvokeGuidedBoundary(catalog.GetRecords)
    return ok and type(records) == "table" and records or {}
end

local function GuidedWidgetIsActionable(widget)
    if not widget or widget._msuf2AppliedEnabled == false or widget._msuf2DesiredEnabled == false then return false end
    local function ObjectEnabled(object)
        if not object or type(object.IsEnabled) ~= "function" then return true end
        local enabled = object:IsEnabled()
        return enabled ~= false and enabled ~= 0
    end
    if not ObjectEnabled(widget) then return false end
    if type(widget.buttons) == "table" and #widget.buttons > 0 then
        for i = 1, #widget.buttons do
            local button = widget.buttons[i]
            if button
                and button._msuf2AppliedEnabled ~= false
                and button._msuf2DesiredEnabled ~= false
                and ObjectEnabled(button)
            then
                return true
            end
        end
        return false
    end
    return true
end
M.IsGuidedTourWidgetActionable = GuidedWidgetIsActionable

local function GuidedDisplayLabel(value)
    value = tostring(value or ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if value == "" then return nil end
    -- Semantic identities are excellent stable keys, but terrible UI copy.
    if value:find("/", 1, true) or value:match("^[%w_%-]+%.[%w_.%-]+$") then return nil end
    return value
end

local function HumanizeGuidedIdentity(record)
    local semantic = tostring(record and (record.controlPath or record.identityKey or record.settingKey or record.identityLabel) or "")
    local leaf = semantic:match("([^/%.]+)$") or semantic
    leaf = leaf:gsub("_", " "):gsub("%-", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    local lower = leaf:lower()
    if lower == "enabled" then return Tr("Enable") end
    if lower == "x" then return Tr("X position") end
    if lower == "y" then return Tr("Y position") end
    if lower == "selected aura" then return Tr("Spell") end
    if leaf == "" then return Tr("Setting") end
    return Tr(leaf:sub(1, 1):upper() .. leaf:sub(2))
end

local function GuidedControlLabel(record, widget)
    local label = GuidedDisplayLabel(widget and SafeText(widget._msuf2Title))
    if label then return label end
    label = GuidedDisplayLabel(widget and SafeText(widget._msuf2Label))
    if label then return label end
    label = GuidedDisplayLabel(record and record.label)
    if label then return label end
    label = GuidedDisplayLabel(widget and widget._msuf2SearchText)
    if label then return label end
    label = GuidedDisplayLabel(record and record.identityLabel)
    if label then return label end
    return HumanizeGuidedIdentity(record)
end

local function SectionControls(pageKey, section, sections, records, includeEphemeral, includeLocked, controlLimit, controlPaths)
    local catalog = M.RuntimeControlCatalog
    if not (catalog and section and section.body) then return {} end
    records = type(records) == "table" and records or RuntimeControlRecords()
    sections = type(sections) == "table" and sections or SortedSections(pageKey)
    local controls, seen = {}, {}
    for i = 1, #records do
        local record = records[i]
        if type(record) == "table"
            and record.pageKey == pageKey
            and (record.classification == "setting" or record.classification == "action"
                or (includeEphemeral == true and record.classification == "ephemeral"))
            and type(record.controlId) == "string"
            and not seen[record.controlId]
        then
            local internal = type(catalog.Get) == "function" and catalog.Get(record.controlId) or nil
            local widget = internal and internal.widget
            local shown = true
            if widget and type(widget.IsVisible) == "function" then
                shown = widget:IsVisible() == true
            elseif widget and type(widget.IsShown) == "function" then
                shown = widget:IsShown() == true
            end
            local actionable = GuidedWidgetIsActionable(widget)
            local owner = widget and shown and (actionable or includeLocked == true) and IsWidgetInside(widget, section.body) and section or nil
            if owner then
                for j = 1, #sections do
                    local candidate = sections[j]
                    if candidate ~= owner
                        and candidate.body ~= owner.body
                        and IsWidgetInside(widget, candidate.body)
                        and IsWidgetInside(candidate.body, owner.body)
                    then
                        owner = candidate
                    end
                end
            end
            if owner == section then
                seen[record.controlId] = true
                controls[#controls + 1] = {
                    id = record.controlId,
                    label = GuidedControlLabel(record, widget),
                    help = tostring(record.help or ""),
                    kind = tostring(record.kind or ""),
                    classification = tostring(record.classification or ""),
                    controlPath = tostring(record.controlPath or ""),
                    settingKey = tostring(record.settingKey or ""),
                    widget = widget,
                    actionable = actionable,
                    top = FrameTop(widget),
                    left = FrameLeft(widget),
                }
            end
        end
    end
    sort(controls, function(a, b)
        if a.top ~= b.top then
            if a.top == nil then return false end
            if b.top == nil then return true end
            if math.abs(a.top - b.top) > 2 then return a.top > b.top end
        end
        if a.left ~= b.left then
            if a.left == nil then return false end
            if b.left == nil then return true end
            if math.abs(a.left - b.left) > 2 then return a.left < b.left end
        end
        local al, bl = a.label:lower(), b.label:lower()
        return al == bl and a.id < b.id or al < bl
    end)
    if type(controlPaths) == "table" and #controlPaths > 0 then
        local byPath, selected, selectedIds = {}, {}, {}
        for i = 1, #controls do
            local path = controls[i].controlPath
            if path ~= "" and byPath[path] == nil then byPath[path] = controls[i] end
        end
        for i = 1, #controlPaths do
            local control = byPath[controlPaths[i]]
            if control and not selectedIds[control.id] then
                selectedIds[control.id] = true
                selected[#selected + 1] = control
            end
        end
        -- Keep the tour resilient if a curated control is unavailable in a
        -- future build: fill the remaining slots with the next visible setting.
        for i = 1, #controls do
            local control = controls[i]
            if not selectedIds[control.id] then
                selectedIds[control.id] = true
                selected[#selected + 1] = control
            end
        end
        controls = selected
    end
    controlLimit = max(0, tonumber(controlLimit) or 0)
    if controlLimit > 0 then
        for i = #controls, controlLimit + 1, -1 do controls[i] = nil end
    end
    return controls
end

local function PageGuideModel(pageKey)
    local entry = M.cache and M.cache[pageKey]
    local cached = Runtime.controlModel
    if entry and cached and cached.pageKey == pageKey and cached.entry == entry then return cached end
    local sections = SortedSections(pageKey)
    local records = RuntimeControlRecords()
    local controlsBySection, allControls, seen = {}, {}, {}
    for i = 1, #sections do
        local list = SectionControls(pageKey, sections[i], sections, records)
        controlsBySection[sections[i].id] = list
        for j = 1, #list do
            local control = list[j]
            if not seen[control.id] then
                seen[control.id] = true
                allControls[#allControls + 1] = control
            end
        end
    end
    local model = {
        pageKey = pageKey,
        entry = entry,
        sections = sections,
        controlsBySection = controlsBySection,
        allControls = allControls,
    }
    if entry then Runtime.controlModel = model end
    return model
end

local function AllStageControls(stage)
    local sections = StageSections(stage)
    local records = RuntimeControlRecords()
    local controls, seen = {}, {}
    for i = 1, #sections do
        local list = SectionControls(stage.pageKey, sections[i], sections, records, stage.includeEphemeralControls, stage.includeLockedControls, EffectiveStageControlLimit(stage), stage.controlPaths)
        for j = 1, #list do
            local control = list[j]
            if not seen[control.id] then
                seen[control.id] = true
                controls[#controls + 1] = control
            end
        end
    end
    return controls
end

local function EmphasizeControl(stage, section, controls, current)
    if not (stage and section and current and current.widget) then
        ClearControlEmphasis()
        return
    end
    local signature = table.concat({ stage.id or "", section.id or "", current.id or "" }, "\031")
    if Runtime.controlEmphasisSignature == signature
        and Runtime.controlEmphasisWidget == current.widget
        and type(Runtime.controlEmphasis) == "table"
    then
        return
    end
    ClearControlEmphasis()
    Runtime.controlEmphasisSignature = signature
    Runtime.controlEmphasisWidget = current.widget
    Runtime.controlEmphasis = {}

    local selectedWidget = current.widget
    local T = M.Theme
    if type(CreateFrame) == "function" and T then
        local marker = Runtime.controlMarker
        if marker and marker._msuf2DualPointer ~= true then
            marker:Hide()
            marker = nil
        end
        if not marker then
            marker = CreateFrame("Frame", nil, selectedWidget)
            marker._msuf2DualPointer = true
            if type(marker.EnableMouse) == "function" then marker:EnableMouse(false) end
            local function Arrow(rotation)
                local texture = marker:CreateTexture(nil, "OVERLAY", nil, 7)
                local usedAtlas = false
                if type(texture.SetAtlas) == "function" then
                    texture:SetAtlas("NPE_ArrowRight", false)
                    usedAtlas = true
                end
                if not usedAtlas and T.media then texture:SetTexture(T.media.collapseArrow) end
                texture:SetSize(20, 20)
                if rotation and type(texture.SetRotation) == "function" then texture:SetRotation(rotation) end
                return texture
            end
            marker._msuf2LeftArrow = Arrow()
            marker._msuf2RightArrow = Arrow(math.pi)
            marker._msuf2Edges = {}
            for i = 1, 4 do marker._msuf2Edges[i] = marker:CreateTexture(nil, "OVERLAY", nil, 6) end
            Runtime.controlMarker = marker
        else
            marker:SetParent(selectedWidget)
        end
        marker:ClearAllPoints()
        marker:SetPoint("TOPLEFT", selectedWidget, "TOPLEFT", -5, 5)
        marker:SetPoint("BOTTOMRIGHT", selectedWidget, "BOTTOMRIGHT", 5, -5)
        if type(marker.SetFrameLevel) == "function" and type(selectedWidget.GetFrameLevel) == "function" then
            marker:SetFrameLevel(selectedWidget:GetFrameLevel() + 8)
        end
        local color = (T.colors and T.colors.ok) or { 0.24, 0.88, 0.40, 1 }
        local leftArrow, rightArrow = marker._msuf2LeftArrow, marker._msuf2RightArrow
        leftArrow:ClearAllPoints()
        leftArrow:SetPoint("RIGHT", marker, "LEFT", -4, 0)
        rightArrow:ClearAllPoints()
        rightArrow:SetPoint("LEFT", marker, "RIGHT", 4, 0)
        leftArrow:SetVertexColor(color[1], color[2], color[3], 1)
        rightArrow:SetVertexColor(color[1], color[2], color[3], 1)
        local top, right, bottom, left = marker._msuf2Edges[1], marker._msuf2Edges[2], marker._msuf2Edges[3], marker._msuf2Edges[4]
        top:ClearAllPoints(); top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(2)
        right:ClearAllPoints(); right:SetPoint("TOPRIGHT"); right:SetPoint("BOTTOMRIGHT"); right:SetWidth(2)
        bottom:ClearAllPoints(); bottom:SetPoint("BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT"); bottom:SetHeight(2)
        left:ClearAllPoints(); left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMLEFT"); left:SetWidth(2)
        for i = 1, 4 do marker._msuf2Edges[i]:SetColorTexture(color[1], color[2], color[3], 0.92) end
        marker:Show()
        Runtime.controlEmphasis[#Runtime.controlEmphasis + 1] = { marker = marker }
        if type(T.PlayMotion) == "function" then
            T.PlayMotion(marker, "controlFocusIn", { fromAlpha = 0.28, toAlpha = 1, duration = 0.16 })
        end
    end
    if T and type(T.PlayNeonFlash) == "function" and type(selectedWidget.CreateTexture) == "function" then
        T.PlayNeonFlash(selectedWidget, "success", { alpha = 0.24, duration = 0.72 })
    end
    if ControlIsAction(current) then
        local function HookActionTarget(target)
            if not (target and type(target.HookScript) == "function") then return end
            target._msuf2GuidedActionHooks = target._msuf2GuidedActionHooks or {}
            if target._msuf2GuidedActionHooks[current.id] then return end
            target._msuf2GuidedActionHooks[current.id] = true
            target:HookScript("OnClick", function()
                if type(M.NotifyGuidedTourControlInteraction) == "function" then
                    M.NotifyGuidedTourControlInteraction(selectedWidget)
                end
            end)
        end
        HookActionTarget(selectedWidget)
        for i = 1, type(selectedWidget.buttons) == "table" and #selectedWidget.buttons or 0 do
            HookActionTarget(selectedWidget.buttons[i])
        end
    end
end

local function ResultName(code)
    if code == "s" or code == "skipped" then return "skipped" end
    if code == "k" or code == "kept" then return "kept" end
    return "reviewed"
end

local function RecordControl(stage, section, control, result)
    if not control then return false end
    return Invoke(Tour(), "RecordControl", stage.id, control.id, ResultName(result), {
        pageKey = stage.pageKey,
        sectionId = section.id,
        label = control.label,
        help = control.help,
    })
end

local function RecordControls(stage, section, controls, result)
    controls = type(controls) == "table" and controls or {}
    for i = 1, #controls do RecordControl(stage, section, controls[i], result) end
    return #controls
end

local function RecordSectionOnly(stage, section, result)
    result = ResultName(result)
    Invoke(Tour(), "RecordSection", stage.id, section.id, result, {
        pageKey = stage.pageKey,
        label = section.label,
    })
end

local function RecordSectionAndControls(stage, section, result, sections, records)
    records = type(records) == "table" and records or RuntimeControlRecords()
    local controls = SectionControls(stage.pageKey, section, sections, records, stage.includeEphemeralControls, stage.includeLockedControls, EffectiveStageControlLimit(stage), stage.controlPaths)
    RecordControls(stage, section, controls, result)
    RecordSectionOnly(stage, section, result)
    return #controls
end

local function DerivedSectionResult(stage, controls, fallback)
    local state = TourState()
    local byStage = type(state.controlResults) == "table" and state.controlResults[stage.id] or nil
    byStage = type(byStage) == "table" and byStage or {}
    local found, allKept, allSkipped = 0, true, true
    for i = 1, #controls do
        local code = byStage[controls[i].id]
        if code then
            found = found + 1
            if code ~= "k" then allKept = false end
            if code ~= "s" then allSkipped = false end
        else
            allKept = false
            allSkipped = false
        end
    end
    if #controls > 0 and found == #controls and allSkipped then return "skipped" end
    if #controls > 0 and found == #controls and allKept then return "kept" end
    if found > 0 then return "reviewed" end
    return ResultName(fallback)
end

local function DerivedStageResult(stage, sections, fallback)
    local state = TourState()
    local results = type(state.sectionResults) == "table" and state.sectionResults or {}
    local found, allKept, allSkipped = 0, true, true
    for i = 1, #sections do
        local code = results[stage.id .. "\031" .. sections[i].id]
        if code then
            found = found + 1
            if code ~= "k" then allKept = false end
            if code ~= "s" then allSkipped = false end
        else
            allKept = false
            allSkipped = false
        end
    end
    if found > 0 and found == #sections and allSkipped then return "skipped" end
    if found > 0 and found == #sections and allKept then return "kept" end
    if found > 0 then return "reviewed" end
    return ResultName(fallback)
end

local function RecordWholeStage(stage, sections, result)
    result = ResultName(result)
    sections = sections or {}
    for i = 1, #sections do RecordSectionAndControls(stage, sections[i], result, sections) end
    Invoke(Tour(), "RecordStage", stage.id, result)
end

local function InitialCursor(stage)
    if stage and not stage.special then
        return { overview = false, sectionIndex = 1, controlIndex = 1, controlTotal = 0 }
    end
    return { overview = true, sectionIndex = 0, controlIndex = 0, controlTotal = 0 }
end

local function ReadCursor(stage)
    local ok, cursor = Invoke(Tour(), "GetCursor", stage.id)
    cursor = ok and type(cursor) == "table" and cursor or nil
    if not cursor then return InitialCursor(stage) end
    return {
        overview = cursor.overview ~= false,
        sectionId = type(cursor.sectionId) == "string" and cursor.sectionId or nil,
        sectionIndex = max(0, tonumber(cursor.sectionIndex) or 0),
        controlId = type(cursor.controlId) == "string" and cursor.controlId or nil,
        controlIndex = max(0, tonumber(cursor.controlIndex) or 0),
        controlTotal = max(0, tonumber(cursor.controlTotal) or 0),
    }
end

local function WriteCursor(stage, cursor)
    return Invoke(Tour(), "SetCursor", stage.id, cursor)
end

local function FindCursorSection(cursor, sections)
    if cursor.overview ~= false then return nil, 0 end
    if cursor.sectionId then
        for i = 1, #sections do
            if sections[i].id == cursor.sectionId then return sections[i], i end
        end
    end
    local index = min(max(tonumber(cursor.sectionIndex) or 1, 1), #sections)
    return sections[index], index
end

local function FindCursorControl(cursor, controls)
    if not cursor or (not cursor.controlId and (tonumber(cursor.controlIndex) or 0) < 1) then return nil, 0 end
    if cursor.controlId then
        for i = 1, #controls do
            if controls[i].id == cursor.controlId then return controls[i], i end
        end
    end
    if #controls == 0 then return nil, 0 end
    local index = min(max(tonumber(cursor.controlIndex) or 1, 1), #controls)
    return controls[index], index
end

local function FocusGuidedWidget(widget, fallback, flash)
    local outer = widget or fallback
    local scroll = M.scrollFrame
    local child = M.scrollChild
    Runtime.focusRequest = (tonumber(Runtime.focusRequest) or 0) + 1
    local request = Runtime.focusRequest
    local function OwnsFloatingGuidedSurface(frame)
        local current = frame
        for _ = 1, 24 do
            if not current then return false end
            if current._msuf2GuidedNoScroll then return true end
            if type(current.GetParent) ~= "function" then return false end
            local parent = current:GetParent()
            if parent == current then return false end
            current = parent
        end
        return false
    end
    local function FinishFocus(pass)
        if request ~= Runtime.focusRequest then return end
        if outer and not OwnsFloatingGuidedSurface(outer) and scroll and child
            and outer.GetTop and scroll.GetTop and scroll.GetBottom
            and scroll.GetVerticalScroll and scroll.SetVerticalScroll
        then
            local outerTop = outer:GetTop()
            local scrollTop, scrollBottom = scroll:GetTop(), scroll:GetBottom()
            if outerTop and scrollTop and scrollBottom then
                local visibleTop = scrollTop
                -- Fixed header targets are rejected by OwnsFloatingGuidedSurface
                -- above. Every target that reaches this branch belongs to the
                -- normal settings viewport and uses its regular geometry.
                local topInset = widget and 52 or 16
                local desiredTop = max(scrollBottom + 32, visibleTop - topInset)
                local current = tonumber(scroll:GetVerticalScroll()) or 0
                local childHeight = tonumber(child.GetHeight and child:GetHeight()) or 0
                local scrollHeight = tonumber(scroll.GetHeight and scroll:GetHeight()) or 0
                local maxScroll = max(0, childHeight - scrollHeight)
                local target = min(max(current + (desiredTop - outerTop), 0), maxScroll)
                if math.abs(target - current) >= 1 then scroll:SetVerticalScroll(floor(target + 0.5)) end
                if scroll._msuf2RefreshScrollBar then scroll:_msuf2RefreshScrollBar() end
            end
        end
        local T = M.Theme
        if pass == 1 and flash and outer and T and type(T.PlayNeonFlash) == "function" and type(outer.CreateTexture) == "function" then
            T.PlayNeonFlash(outer, "success", { alpha = 0.24, duration = 0.72 })
        end
        -- Accordion expansion and page relayout settle on the next frame.
        if pass == 1 and C_Timer and type(C_Timer.After) == "function" then
            C_Timer.After(0, function() FinishFocus(2) end)
        end
    end
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0, function() FinishFocus(1) end)
    else
        FinishFocus(1)
        FinishFocus(2)
    end
end

local function FocusCurrentSection(stage)
    if stage.special then return end
    local cursor = ReadCursor(stage)
    if cursor.overview ~= false then
        if type(M.CloseAutoFocusedSections) == "function" then M.CloseAutoFocusedSections(stage.pageKey) end
        ClearSectionEmphasis(stage.pageKey)
        return
    end
    local sections = StageSections(stage)
    local section, index = FindCursorSection(cursor, sections)
    if not section then
        WriteCursor(stage, InitialCursor(stage))
        return
    end
    local controls = SectionControls(stage.pageKey, section, sections, nil, stage.includeEphemeralControls, stage.includeLockedControls, EffectiveStageControlLimit(stage), stage.controlPaths)
    local control, controlIndex = FindCursorControl(cursor, controls)
    if cursor.sectionId ~= section.id
        or cursor.sectionIndex ~= index
        or cursor.controlId ~= (control and control.id or nil)
        or cursor.controlIndex ~= controlIndex
        or cursor.controlTotal ~= #controls
    then
        WriteCursor(stage, {
            overview = false,
            sectionId = section.id,
            sectionIndex = index,
            controlId = control and control.id or nil,
            controlIndex = controlIndex,
            controlTotal = #controls,
        })
    end
    local W = M.Widgets
    if type(M.CloseAutoFocusedSections) == "function" then M.CloseAutoFocusedSections(stage.pageKey) end
    if W and type(W.FocusCollapsibleSection) == "function" then
        for i = 1, #sections do
            local ancestor = sections[i]
            if ancestor.collapsible
                and ancestor.id ~= section.id
                and section.outer
                and IsWidgetInside(section.outer, ancestor.body)
            then
                W.FocusCollapsibleSection(ancestor.body, { persist = false, flash = false })
            end
        end
        if section.collapsible then
            W.FocusCollapsibleSection(section.body, { persist = false, flash = true })
        else
            FocusGuidedWidget(section.outer, nil, true)
        end
    end
    if control then FocusGuidedWidget(control.widget, section.outer, false) end
    EmphasizeSection(stage.pageKey, section, control)
    EmphasizeControl(stage, section, controls, control)
end

local function InvalidateGuidedPage()
    if type(M.InvalidatePage) == "function" then M.InvalidatePage("guided_setup") end
end

local function SelectExpectedPage(stage)
    local pageKey = ExpectedPage(stage)
    if EnsureGuidedTourChrome then EnsureGuidedTourChrome() end
    Runtime.manualAway = nil
    Runtime.warning = nil
    if stage.special then InvalidateGuidedPage() end
    if M.frame and type(M.frame.IsShown) == "function" and M.frame:IsShown() then
        -- Consecutive special stages share the guided_setup page key, but each
        -- stage builds different page content. Invalidation removes the cached
        -- wrapper, so only use the same-page refresh path while that wrapper
        -- still exists; otherwise SelectPage must rebuild it immediately.
        if M.activeKey == pageKey and M.cache and M.cache[pageKey] then
            if type(M.RefreshGuidedTourChrome) == "function" then M.RefreshGuidedTourChrome("SAME_PAGE_STAGE") end
            return true
        end
        if type(M.SelectPage) == "function" then return M.SelectPage(pageKey) end
    elseif type(M.Open) == "function" then
        return M.Open(pageKey)
    elseif type(M.SelectPage) == "function" then
        return M.SelectPage(pageKey)
    end
    return false
end

local function SetStage(stage, resetCursor)
    if not stage then return false end
    ClearSectionEmphasis()
    Invoke(Tour(), "SetStage", stage.id, stage.index)
    if resetCursor or not select(2, Invoke(Tour(), "GetCursor", stage.id)) then
        WriteCursor(stage, InitialCursor(stage))
    end
    return SelectExpectedPage(stage)
end

local function CompleteTour()
    local completedMode = SelectedSetupMode()
    ClearSectionEmphasis()
    Invoke(Tour(), "Complete")
    Invoke(FirstLoad(), "Complete", "guided_tour")
    Runtime.warning = nil
    Runtime.manualAway = nil
    Runtime.touchedSignature = nil
    Runtime.lastVisualSignature = nil
    M.RefreshGuidedTourChrome("COMPLETE")
    if type(M.InvalidatePage) == "function" then M.InvalidatePage("home") end
    if type(M.SelectPage) == "function" then M.SelectPage("home") end
    if completedMode == "complete" and type(M.StartNewAssistantTask) == "function" then M.StartNewAssistantTask() end
    return true
end

local function AdvanceStage(stage, resetCursor)
    local current, total, stages = ActiveStagePosition(stage)
    if current >= total then return CompleteTour() end
    return SetStage(stages[current + 1], resetCursor ~= false)
end

local function ReturnToPreviousStage(stage)
    local current, _, stages = ActiveStagePosition(stage)
    if current <= 1 then return false end
    local previous = stages[current - 1]
    ClearSectionEmphasis()
    Invoke(Tour(), "SetStage", previous.id, previous.index)
    return SelectExpectedPage(previous)
end

local function FindAvailableControl(stage, sections, startIndex, direction)
    sections = type(sections) == "table" and sections or {}
    direction = direction == -1 and -1 or 1
    local index = min(max(tonumber(startIndex) or (direction == 1 and 1 or #sections), 1), max(1, #sections))
    while sections[index] do
        local section = sections[index]
        local controls = SectionControls(stage.pageKey, section, sections, nil, stage.includeEphemeralControls, stage.includeLockedControls, EffectiveStageControlLimit(stage), stage.controlPaths)
        if #controls > 0 then
            local controlIndex = direction == 1 and 1 or #controls
            return section, index, controls, controls[controlIndex], controlIndex
        end
        index = index + direction
    end
    return nil, 0, {}, nil, 0
end

local function CurrentPosition(stage)
    if stage.special then return { overview = true, sections = {}, index = 0 } end
    local sections = StageSections(stage)
    local cursor = ReadCursor(stage)
    local section, index = FindCursorSection(cursor, sections)
    local controls = section and SectionControls(stage.pageKey, section, sections, nil, stage.includeEphemeralControls, stage.includeLockedControls, EffectiveStageControlLimit(stage), stage.controlPaths) or {}
    local control, controlIndex = FindCursorControl(cursor, controls)
    local normalized = false
    if cursor.overview ~= false or not section or not control then
        local startIndex = section and index or 1
        section, index, controls, control, controlIndex = FindAvailableControl(stage, sections, startIndex, 1)
        if not control and startIndex > 1 then
            section, index, controls, control, controlIndex = FindAvailableControl(stage, sections, 1, 1)
        end
        if control then
            cursor = {
                overview = false,
                sectionId = section.id,
                sectionIndex = index,
                controlId = control.id,
                controlIndex = controlIndex,
                controlTotal = #controls,
            }
            WriteCursor(stage, cursor)
            normalized = true
        else
            cursor = InitialCursor(stage)
            cursor.overview = true
        end
    end
    return {
        overview = control == nil,
        cursor = cursor,
        cursorNormalized = normalized,
        sections = sections,
        section = section,
        index = index,
        controls = controls,
        control = control,
        controlIndex = controlIndex,
    }
end

local function TouchSignature(stage, position)
    local control = position and position.control
    if not (stage and control) then return nil end
    return table.concat({ stage.id or "", position.section and position.section.id or "", control.id or "" }, "\031")
end

local function CurrentControlTouched(stage, position)
    local signature = TouchSignature(stage, position)
    return signature ~= nil and Runtime.touchedSignature == signature
end

local function TourExperience()
    local summary = M.GetGuidedTourSummary and M.GetGuidedTourSummary() or {}
    return ((tonumber(summary.reviewedControls) or 0) * 10)
        + ((tonumber(summary.keptControls) or 0) * 5)
        + ((tonumber(summary.reviewedSections) or 0) * 20)
        + ((tonumber(summary.reviewedStages) or 0) * 50)
end

function M.NotifyGuidedTourControlInteraction(widget)
    if not TourIsActive() or Runtime.manualAway or Runtime.warning or ProfileMismatch() then return false end
    local stage = CurrentStage()
    if stage.special then return false end
    local position = CurrentPosition(stage)
    local control = position.control
    if not (control and control.actionable ~= false) then return false end
    local command = widget and widget._msuf2CommandAction
    local controlId = command and command.controlId or (widget and widget._msuf2ControlId)
    if widget ~= control.widget and tostring(controlId or "") ~= tostring(control.id or "") then return false end
    local signature = TouchSignature(stage, position)
    if not signature then return false end
    Runtime.touchedSignature = signature
    local T = M.Theme
    if T and type(T.PlayNeonFlash) == "function" and control.widget and type(control.widget.CreateTexture) == "function" then
        T.PlayNeonFlash(control.widget, "success", { alpha = 0.34, duration = 0.92 })
    end
    if type(M.RefreshGuidedTourChrome) == "function" then M.RefreshGuidedTourChrome("CONTROL_USED") end
    return true
end

local function KeepLabel(stage, position)
    if stage.special then return "Keep as is" end
    if ControlIsAction(position.control) then return "Keep action" end
    if position.control then return "Keep unchanged" end
    return "Skip empty mission"
end

local function SetSectionCursor(stage, sections, sectionIndex, controlIndex, reason)
    local section = sections[sectionIndex]
    if not section then return false end
    local controls = SectionControls(stage.pageKey, section, sections, nil, stage.includeEphemeralControls, stage.includeLockedControls, EffectiveStageControlLimit(stage), stage.controlPaths)
    if #controls == 0 then return false end
    controlIndex = min(max(tonumber(controlIndex) or 1, 1), #controls)
    local control = controls[controlIndex]
    WriteCursor(stage, {
        overview = false,
        sectionId = section.id,
        sectionIndex = sectionIndex,
        controlId = control.id,
        controlIndex = controlIndex,
        controlTotal = #controls,
    })
    FocusCurrentSection(stage)
    M.RefreshGuidedTourChrome(reason or "GUIDED_POSITION")
    return true
end

local function SetAvailableControlCursor(stage, sections, startIndex, direction, reason)
    local _, sectionIndex, _, _, controlIndex = FindAvailableControl(stage, sections, startIndex, direction)
    if sectionIndex < 1 or controlIndex < 1 then return false end
    return SetSectionCursor(stage, sections, sectionIndex, controlIndex, reason)
end

local function AdvanceCurrent(result)
    if ProfileMismatch() then return false end
    local stage = CurrentStage()
    local position = CurrentPosition(stage)
    result = ResultName(result)

    if stage.id == "final_review" then return CompleteTour() end
    if stage.special then
        Invoke(Tour(), "RecordStage", stage.id, result)
        return AdvanceStage(stage, true)
    end
    if position.overview or not position.control then
        if result == "reviewed" and SetAvailableControlCursor(stage, position.sections, 1, 1, "FIRST_CONTROL") then return true end
        RecordWholeStage(stage, position.sections, result)
        return AdvanceStage(stage, true)
    end

    RecordControl(stage, position.section, position.control, result)
    if position.controlIndex < #position.controls then
        return SetSectionCursor(stage, position.sections, position.index, position.controlIndex + 1, "NEXT_CONTROL")
    end
    RecordSectionOnly(stage, position.section, DerivedSectionResult(stage, position.controls, result))

    if position.index < #position.sections
        and SetAvailableControlCursor(stage, position.sections, position.index + 1, 1, "NEXT_CONTROL")
    then return true end
    Invoke(Tour(), "RecordStage", stage.id, DerivedStageResult(stage, position.sections, result))
    return AdvanceStage(stage, true)
end

local function BackCurrent()
    if ProfileMismatch() then
        return type(M.StartGuidedTour) == "function"
            and M.StartGuidedTour({ source = "profile_change", restart = true })
            or false
    end
    if Runtime.warning then
        Runtime.warning = nil
        M.RefreshGuidedTourChrome("CANCEL_SKIP")
        return true
    end
    if Runtime.manualAway then
        Runtime.manualAway = nil
        return SelectExpectedPage(CurrentStage())
    end
    local stage = CurrentStage()
    local position = CurrentPosition(stage)
    if stage.special or position.overview then return ReturnToPreviousStage(stage) end
    if position.control then
        local previousControl = position.controlIndex - 1
        if previousControl > 0 then
            return SetSectionCursor(stage, position.sections, position.index, previousControl, "PREVIOUS_CONTROL")
        end
        if position.index > 1
            and SetAvailableControlCursor(stage, position.sections, position.index - 1, -1, "PREVIOUS_CONTROL")
        then return true end
    end
    return ReturnToPreviousStage(stage)
end

local function LabelList(controls, limit)
    local labels, seen = {}, {}
    for i = 1, #controls do
        local label = tostring(controls[i].label or "")
        if label ~= "" and not seen[label] then
            seen[label] = true
            labels[#labels + 1] = label
            if #labels >= (limit or 4) then break end
        end
    end
    local value = table.concat(labels, ", ")
    if #controls > #labels then value = value .. format(Tr(" and %d more"), #controls - #labels) end
    return value
end

local function SkipSignature(stage, position)
    return table.concat({
        stage.id,
        position.section and position.section.id or "overview",
        position.control and position.control.id or "section",
    }, "\031")
end

local function SkipWarning(stage, position)
    if position.control then
        return format(Tr("SKIP CHECKPOINT? %s stays unchanged. Press Confirm skip."), Tr(position.control.label)), 1
    end

    local controls = position.section and position.controls
        or (not stage.special and AllStageControls(stage, position.sections))
        or {}
    local parts = {}
    if position.section then
        parts[1] = format(Tr("SKIP CHECKPOINT? %s and %d settings stay unchanged."), Tr(position.section.label), #controls)
    elseif not stage.special and #position.sections > 0 then
        parts[1] = format(Tr("SKIP MISSION? %d checkpoints and %d settings stay unchanged."), #position.sections, #controls)
    else
        parts[1] = format(Tr("SKIP MISSION? %s"), Tr(stage.impact))
    end
    parts[#parts + 1] = Tr("Press Confirm skip to continue.")
    return table.concat(parts, "\n"), #controls
end

local function SkipCurrent()
    if ProfileMismatch() then return false end
    local stage = CurrentStage()
    if stage.id == "final_review" then return false end
    local position = CurrentPosition(stage)
    local signature = SkipSignature(stage, position)
    if Runtime.warning then
        local warning = Runtime.warning
        local sectionId = position.section and position.section.id or nil
        if warning.stageId == stage.id and warning.sectionId == sectionId then
            Runtime.warning = nil
            return AdvanceCurrent("skipped")
        end
    end
    local text, count = SkipWarning(stage, position)
    Runtime.warning = {
        signature = signature,
        stageId = stage.id,
        sectionId = position.section and position.section.id or nil,
        controlId = position.control and position.control.id or nil,
        text = text,
        count = count,
    }
    M.RefreshGuidedTourChrome("SKIP_WARNING")
    return true
end

local function PauseTour()
    Runtime.warning = nil
    Runtime.manualAway = nil
    ClearSectionEmphasis()
    local frame = M.frame
    if type(M.HideSlashMenuAndMinibar) == "function" then
        M.HideSlashMenuAndMinibar(frame)
    elseif frame and type(frame.Hide) == "function" then
        frame:Hide()
    end
    return true
end

local function SetButtonEnabled(button, enabled)
    if not button then return end
    button._msuf2GuidedEnabled = enabled and true or false
    if type(button.SetEnabled) == "function" then button:SetEnabled(enabled and true or false) end
    if type(button.SetAlpha) == "function" then button:SetAlpha(enabled and 1 or 0.42) end
end

local function SetButtonText(button, text)
    if button and type(button.SetText) == "function" then button:SetText(Tr(text)) end
    if button and M.Theme and type(M.Theme.CenterButtonLabel) == "function" then M.Theme.CenterButtonLabel(button) end
end

local function SetFontColor(fontString, color)
    if fontString and color and type(fontString.SetTextColor) == "function" then
        fontString:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    end
end

local function SetStageIcon(chrome, stage)
    local T = M.Theme
    local icon = chrome and chrome.icon
    if not (T and icon) then return end
    local grid = T.navIconGrid and T.navIconGrid[stage.icon]
    if grid and T.media and T.media.navIcons then
        icon:SetTexture(T.media.navIcons)
        icon:SetTexCoord(grid[1] / 8, (grid[1] + 1) / 8, grid[2] / 8, (grid[2] + 1) / 8)
    elseif T.media and T.media.logo then
        icon:SetTexture(T.media.logo)
        icon:SetTexCoord(0.075, 0.925, 0.075, 0.925)
    end
    local color = T.navIconColors and T.navIconColors[stage.icon] or T.colors.accent
    if color then icon:SetVertexColor(color[1], color[2], color[3], 1) end
end

local function AnchorTourScroll(chrome, active)
    if not (chrome and chrome.scroll and chrome.host and chrome.status) then return end
    local scroll = chrome.scroll
    local topOwner = chrome.status
    if active then topOwner = chrome end
    if type(M.LayoutPageHeaderHost) == "function" then
        M.LayoutPageHeaderHost(topOwner, chrome.host)
    elseif scroll._msuf2TourAnchorOwner ~= topOwner or scroll._msuf2TourAnchorHost ~= chrome.host then
        scroll:ClearAllPoints()
        scroll:SetPoint("TOPLEFT", topOwner, "BOTTOMLEFT", 0, 0)
        scroll:SetPoint("BOTTOMRIGHT", chrome.host, "BOTTOMRIGHT", -24, 0)
        scroll._msuf2TourAnchorOwner = topOwner
        scroll._msuf2TourAnchorHost = chrome.host
    end
    scroll._msuf2MaxScroll = nil
    scroll._msuf2SmoothScrollTarget = nil
    if type(scroll._msuf2RefreshScrollBar) == "function" then scroll:_msuf2RefreshScrollBar() end
end

local function LayoutChrome(chrome, warning, helpText)
    local hostWidth = max(420, tonumber(chrome.host and chrome.host:GetWidth()) or 760)
    local compact = hostWidth < 700
    local baseHeight = compact and (warning and 234 or 196) or (warning and 164 or 132)
    local charsPerLine = max(36, floor((hostWidth - 28) / 6.2))
    local estimatedLines = min(9, max(1, ceil(#tostring(helpText or "") / charsPerLine)))
    local includedLines = compact and (warning and 5 or 3) or (warning and 3 or 2)
    local height = baseHeight + (max(0, estimatedLines - includedLines) * 13)
    chrome:SetHeight(height)
    chrome._msuf2Compact = compact

    chrome.iconWell:ClearAllPoints()
    chrome.iconWell:SetPoint("TOPLEFT", chrome, "TOPLEFT", 16, -12)
    chrome.iconWell:SetSize(36, 36)
    chrome.title:ClearAllPoints()
    chrome.title:SetPoint("TOPLEFT", chrome, "TOPLEFT", 60, -12)
    chrome.title:SetPoint("RIGHT", chrome.step, "LEFT", -12, 0)
    chrome.step:ClearAllPoints()
    chrome.step:SetPoint("TOPRIGHT", chrome, "TOPRIGHT", -16, -16)
    chrome.step:SetWidth(compact and 118 or 166)
    chrome.section:ClearAllPoints()
    chrome.section:SetPoint("TOPLEFT", chrome, "TOPLEFT", 60, -32)
    chrome.section:SetPoint("TOPRIGHT", chrome, "TOPRIGHT", -16, -32)
    chrome.cueArrow:ClearAllPoints()
    chrome.cueArrow:SetPoint("TOPLEFT", chrome, "TOPLEFT", 16, compact and -64 or -56)
    chrome.help:ClearAllPoints()
    chrome.help:SetPoint("TOPLEFT", chrome, "TOPLEFT", 36, compact and -60 or -52)
    chrome.help:SetPoint("BOTTOMRIGHT", chrome, "BOTTOMRIGHT", -16, compact and 88 or 60)
    chrome.help:SetWidth(hostWidth - 48)
    chrome.progress:ClearAllPoints()
    chrome.progress:SetPoint("BOTTOMLEFT", chrome, "BOTTOMLEFT", 16, compact and 76 or 44)
    chrome.progress:SetPoint("BOTTOMRIGHT", chrome, "BOTTOMRIGHT", -16, compact and 76 or 44)
    chrome.progress:SetHeight(4)

    local buttons = { chrome.back, chrome.keep, chrome.skip, chrome.next, chrome.pause }
    local minimums = compact and { 48, 72, 58, 60, 54 } or { 58, 82, 68, 72, 64 }
    local maximums = compact and { 112, 126, 138, 112, 96 } or { 126, 146, 158, 126, 108 }
    local widths = {}
    for i = 1, #buttons do
        local preferred = minimums[i]
        local fontString = buttons[i]._msuf2Label
            or (type(buttons[i].GetFontString) == "function" and buttons[i]:GetFontString() or nil)
        if fontString and type(fontString.GetStringWidth) == "function" then
            local textWidth = fontString:GetStringWidth()
            if tonumber(textWidth) then
                minimums[i] = max(minimums[i], ceil(textWidth + 8))
                preferred = ceil(textWidth + 22)
                maximums[i] = max(maximums[i], minimums[i])
            end
        end
        widths[i] = min(max(preferred, minimums[i]), maximums[i])
    end
    local gap = compact and 5 or 7
    local function FitRow(indices)
        local available = hostWidth - 20 - (gap * (#indices - 1))
        local widthTotal, flexible = 0, 0
        for i = 1, #indices do
            local index = indices[i]
            widthTotal = widthTotal + widths[index]
            flexible = flexible + max(0, widths[index] - minimums[index])
        end
        if widthTotal <= available or flexible <= 0 then return end
        local overflow = widthTotal - available
        for i = 1, #indices do
            local index = indices[i]
            local room = max(0, widths[index] - minimums[index])
            local reduction = min(room, floor((overflow * room / flexible) + 0.5))
            widths[index] = widths[index] - reduction
        end
        widthTotal = 0
        for i = 1, #indices do widthTotal = widthTotal + widths[indices[i]] end
        local remainder = max(0, widthTotal - available)
        while remainder > 0 do
            local changed = false
            for i = #indices, 1, -1 do
                local index = indices[i]
                if widths[index] > minimums[index] and remainder > 0 then
                    widths[index] = widths[index] - 1
                    remainder = remainder - 1
                    changed = true
                end
            end
            if not changed then break end
        end
    end
    local function PlaceRow(indices, bottom)
        FitRow(indices)
        local total = gap * (#indices - 1)
        for i = 1, #indices do total = total + widths[indices[i]] end
        local x = max(10, floor((hostWidth - total) / 2))
        for i = 1, #indices do
            local index = indices[i]
            local button = buttons[index]
            button:ClearAllPoints()
            button:SetSize(widths[index], 24)
            button:SetPoint("BOTTOMLEFT", chrome, "BOTTOMLEFT", x, bottom)
            x = x + widths[index] + gap
        end
    end
    if compact then
        PlaceRow({ 1, 2, 3 }, 39)
        PlaceRow({ 4, 5 }, 10)
    else
        PlaceRow({ 1, 2, 3, 4, 5 }, 10)
    end
    AnchorTourScroll(chrome, true)
end

local function ProgressFraction(stage, position)
    local within = 0
    if not stage.special and position.control and #position.sections > 0 then
        local total, completed = 0, 0
        local records = RuntimeControlRecords()
        for i = 1, #position.sections do
            local controls = SectionControls(stage.pageKey, position.sections[i], position.sections, records, stage.includeEphemeralControls, stage.includeLockedControls, EffectiveStageControlLimit(stage), stage.controlPaths)
            total = total + #controls
            if i < position.index then
                completed = completed + #controls
            elseif i == position.index and position.control then
                completed = completed + max(0, position.controlIndex - 1)
            end
        end
        within = min(max(completed / max(1, total), 0), 0.99)
    elseif stage.id == "final_review" then
        within = 1
    end
    local current, total = ActiveStagePosition(stage)
    return min(max(((current - 1) + within) / max(1, total), 0), 1)
end

local function PlayChromeTransition(chrome, signature, reason)
    if Runtime.lastVisualSignature == signature or reason == "HOST_SIZE" or reason == "WINDOW_RESIZE" then return end
    Runtime.lastVisualSignature = signature
    local T = M.Theme
    if not (T and type(T.PlayMotion) == "function") then return end
    T.PlayMotion(chrome.iconWell, "controlFocusIn", { fromAlpha = 0.28, toAlpha = 1, duration = 0.18 })
    T.PlayMotion(chrome.title, "controlFocusIn", { fromAlpha = 0.38, toAlpha = 1, duration = 0.16 })
    T.PlayMotion(chrome.help, "controlFocusIn", { fromAlpha = 0.30, toAlpha = 1, duration = 0.20 })
    T.PlayMotion(chrome.progressFill, "controlFocusIn", { fromAlpha = 0.45, toAlpha = 1, duration = 0.22 })
end

local function StopChromeTransition(chrome)
    local T = M.Theme
    if not (chrome and T and type(T.StopMotion) == "function") then return end
    local regions = { chrome.iconWell, chrome.title, chrome.help, chrome.progressFill }
    for i = 1, #regions do T.StopMotion(regions[i]) end
end

local function RegisterSpecialClickTargets(stageId, key, widgets)
    local targets = Runtime.specialClickTargets
    if type(targets) ~= "table" or targets.stageId ~= stageId then
        targets = { stageId = stageId, groups = {} }
        Runtime.specialClickTargets = targets
    end
    targets.groups[key] = type(widgets) == "table" and widgets or {}
end

local function FlashGuidedClickTargets(chrome, stage, position, context, reason)
    if reason == "HOST_SIZE" or reason == "WINDOW_RESIZE" then return end
    local T = M.Theme
    if not (T and type(T.PlayNeonFlash) == "function") then return end
    context = context or {}
    local editStatus = (stage.id == "edit_mode" or stage.id == "group_edit_mode")
        and (type(M.EditModeLifecycleStatus) == "function" and M.EditModeLifecycleStatus() or {})
        or {}
    local signature = table.concat({
        stage.id,
        position.section and position.section.id or "overview",
        position.control and position.control.id or "section",
        context.profileMismatch and "profile" or "profile-ok",
        context.manualAway and "away" or "here",
        context.warning and tostring(context.warning.signature or "warning") or "normal",
        tostring(SelectedSetupArea() or ""),
        tostring(SelectedSetupMode()),
        tostring(CooldownAnchorDecision() or ""),
        EditModePlacementComplete() and "placed" or "unplaced",
        GroupEditModePlacementComplete() and "group-placed" or "group-unplaced",
        editStatus.active and "edit-on" or "edit-off",
    }, "\031")
    if Runtime.lastClickCueSignature == signature then return end
    Runtime.lastClickCueSignature = signature

    local widgets, seen = {}, {}
    local function Add(widget)
        if widget and not seen[widget] then
            seen[widget] = true
            widgets[#widgets + 1] = widget
        end
    end
    local function AddGroup(key)
        local targets = Runtime.specialClickTargets
        local group = targets and targets.stageId == stage.id and targets.groups and targets.groups[key]
        for i = 1, #(group or {}) do Add(group[i]) end
    end

    if context.profileMismatch then
        Add(chrome.back)
    elseif context.manualAway then
        Add(chrome.next)
    elseif context.warning then
        Add(chrome.skip)
    elseif stage.id == "menu_basics" then
        if not SetupAreaDecisionComplete() then
            AddGroup("setupArea")
        else
            Add(chrome.next)
        end
    elseif stage.id == "edit_mode" then
        if not CooldownAnchorDecisionComplete() then
            AddGroup("anchor")
        elseif EditModePlacementComplete() then
            Add(chrome.next)
        elseif editStatus.active ~= true then
            AddGroup("edit_mode_toggle")
            Add(M.dashboardToolbarEditModeButton)
        end
    elseif stage.id == "group_edit_mode" then
        if GroupEditModePlacementComplete() then
            Add(chrome.next)
        elseif editStatus.active ~= true then
            AddGroup("group_edit_mode_toggle")
            Add(M.dashboardToolbarEditModeButton)
        end
    elseif stage.id == "final_review" or not position.control then
        Add(chrome.next)
    end

    for i = 1, #widgets do
        local widget = widgets[i]
        T.PlayNeonFlash(widget, "success", { alpha = 0.28, duration = 0.82 })
        if type(T.PlayMotion) == "function" then
            T.PlayMotion(widget, "controlFocusIn", { fromAlpha = 0.52, toAlpha = 1, duration = 0.18 })
        end
    end
end

function M.RefreshGuidedTourChrome(reason)
    local chrome = Runtime.chrome
    if not chrome then return false end
    if not TourIsActive() then
        if Runtime.tourVisualsDirty ~= true then return false end
        Runtime.warning = nil
        Runtime.manualAway = nil
        Runtime.lastVisualSignature = nil
        Runtime.lastClickCueSignature = nil
        ClearSectionEmphasis()
        StopChromeTransition(chrome)
        chrome:Hide()
        RefreshEditModeOpenCue(false)
        AnchorTourScroll(chrome, false)
        Runtime.tourVisualsDirty = nil
        return false
    end
    Runtime.tourVisualsDirty = true

    local stage = CurrentStage()
    local reconciledPopup = ReconcileGuidedEditModePopup(stage)
    if reconciledPopup and M.activeKey == "guided_setup" and not Runtime.popupReconcileRefreshQueued then
        Runtime.popupReconcileRefreshQueued = true
        C_Timer.After(0, function()
            Runtime.popupReconcileRefreshQueued = nil
            if type(M.RequestRefresh) == "function" then M.RequestRefresh(nil, "GUIDED_POPUP_RECONCILED") end
        end)
    end
    local profileMismatch, tourProfile, activeProfile = ProfileMismatch()
    if profileMismatch then
        Runtime.warning = nil
        Runtime.manualAway = nil
    end
    local expected = ExpectedPage(stage)
    local position = CurrentPosition(stage)
    local touched = CurrentControlTouched(stage, position)
    local currentPage = M.activeKey
    if currentPage and currentPage ~= expected then Runtime.manualAway = true end
    local manualAway = Runtime.manualAway == true and currentPage ~= expected
    local warning = Runtime.warning
    if position.cursorNormalized and not profileMismatch and not manualAway then
        FocusCurrentSection(stage)
    end
    local showEditModeOpenCue = not profileMismatch
        and not manualAway
        and not warning
        and ShouldShowEditModeOpenCue()
    local displayHelp = profileMismatch
        and format(Tr("This tour belongs to profile %s. You are now editing %s. Restart the tour here or switch back to continue safely."), tourProfile, activeProfile)
        or manualAway and Tr("Return to the guided page when you are ready to continue.")
        or warning and warning.text
        or StageCue(stage, position, touched)
    if profileMismatch or manualAway then
        ClearSectionEmphasis()
    elseif stage.special or position.overview then
        ClearSectionEmphasis(stage.pageKey)
    elseif position.section then
        EmphasizeSection(stage.pageKey, position.section, position.control)
        EmphasizeControl(stage, position.section, position.controls, position.control)
    end
    SetStageIcon(chrome, stage)
    local stagePosition, stageTotal = ActiveStagePosition(stage)
    chrome.step:SetText(format(Tr("MISSION %d/%d - %d XP"), stagePosition, stageTotal, TourExperience()))

    if profileMismatch then
        chrome.title:SetText(Tr("Active profile changed"))
        chrome.section:SetText(format(Tr("Tour profile: %s - Active profile: %s"), tourProfile, activeProfile))
        chrome.help:SetText(displayHelp)
    elseif manualAway then
        chrome.title:SetText(format(Tr("Tour paused - %s"), PersonalizedTitle(stage)))
        chrome.section:SetText(Tr("Progress is saved while you use another page."))
        chrome.help:SetText(displayHelp)
    else
        chrome.title:SetText(PersonalizedTitle(stage))
        if stage.special then
            local labels = {
                menu_basics = "QUICK START",
                unit_intro = "PART 1 - UNITFRAMES",
                edit_mode = "MOVE VS SIZE",
                group_intro = "PART 2 - GROUP FRAMES",
                group_edit_mode = "MOVE VS SIZE",
                class_intro = "PART 3 - CLASS RESOURCES",
                power_moves = "MSUF POWER MOVES",
                final_review = "READY TO PLAY",
            }
            chrome.section:SetText(Tr(labels[stage.id] or "GUIDED SETUP"))
        elseif position.overview then
            local controls = AllStageControls(stage, position.sections)
            chrome.section:SetText(format(Tr("MISSION BRIEF - %d checkpoints - %d settings"), #position.sections, #controls))
        elseif position.control then
            if ControlIsAction(position.control) then
                chrome.section:SetText(format(Tr("CHECKPOINT %d/%d - ACTION %d/%d - %s"), position.index, #position.sections, position.controlIndex, #position.controls, Tr(position.control.label)))
            else
                chrome.section:SetText(format(Tr("CHECKPOINT %d/%d - SETTING %d/%d - %s"), position.index, #position.sections, position.controlIndex, #position.controls, Tr(position.control.label)))
            end
        elseif position.section then
            chrome.section:SetText(format(Tr("CHECKPOINT %d/%d - %s - %d settings"), position.index, #position.sections, Tr(position.section.label), #position.controls))
        end
        chrome.help:SetText(displayHelp)
    end
    local alert = profileMismatch or warning
    local controlCue = not alert and not stage.special and position.control ~= nil
    local guidedGreen = M.Theme.colors.ok or { 0.24, 0.88, 0.40, 1 }
    SetFontColor(chrome.help, alert and (M.Theme.colors.warning or M.Theme.colors.warn)
        or controlCue and guidedGreen
        or M.Theme.colors.muted)
    local cueColor = alert and (M.Theme.colors.warning or M.Theme.colors.warn)
        or controlCue and guidedGreen
        or M.Theme.colors.accent
    if cueColor then chrome.cueArrow:SetVertexColor(cueColor[1], cueColor[2], cueColor[3], 1) end

    local fraction = ProgressFraction(stage, position)
    chrome.progressFill:SetWidth(max(1, floor(((chrome.progress:GetWidth() or 1) - 2) * fraction)))

    local firstPosition = stagePosition == 1 and stage.special
    local final = stage.id == "final_review"
    local waitingForAnchorDecision = stage.id == "edit_mode" and not CooldownAnchorDecisionComplete()
    local waitingForEditModeMove = stage.id == "edit_mode" and not waitingForAnchorDecision and not EditModePlacementComplete()
    local waitingForGroupMove = stage.id == "group_edit_mode" and not GroupEditModePlacementComplete()
    local editPopupActionReady = waitingForEditModeMove and EditModeMovementComplete()
    local groupPopupActionReady = waitingForGroupMove and GroupEditModeMovementComplete()
    SetButtonText(chrome.back, profileMismatch and "Restart tour" or (warning and "Cancel" or "Back"))
    SetButtonText(chrome.keep, KeepLabel(stage, position))
    SetButtonText(chrome.skip, warning and "Confirm skip" or "Skip")
    local nextLabel = "Next setting"
    if manualAway then nextLabel = "Return"
    elseif final then nextLabel = SelectedSetupMode() == "quick" and "Finish setup" or "Finish & open Assistant"
    elseif waitingForEditModeMove then nextLabel = EditModeMovementComplete() and "Open size popup" or "Move Player first"
    elseif waitingForGroupMove then nextLabel = GroupEditModeMovementComplete() and "Open size popup" or "Move Party first"
    elseif touched then nextLabel = "Claim +10 XP"
    elseif stage.id == "menu_basics" then nextLabel = SelectedSetupMode() == "quick" and "Start Quick Setup" or "Start Complete Tour"
    elseif stage.id == "edit_mode" then nextLabel = "Claim checkpoint"
    elseif stage.id == "power_moves" then nextLabel = "Continue"
    elseif position.control then nextLabel = "Change it first"
    end
    SetButtonText(chrome.next, nextLabel)
    SetButtonText(chrome.pause, "Pause")
    LayoutChrome(chrome, alert ~= nil and alert ~= false, displayHelp)

    if profileMismatch then
        SetButtonEnabled(chrome.back, true)
        SetButtonEnabled(chrome.keep, false)
        SetButtonEnabled(chrome.skip, false)
        SetButtonEnabled(chrome.next, false)
    elseif manualAway then
        SetButtonEnabled(chrome.back, false)
        SetButtonEnabled(chrome.keep, false)
        SetButtonEnabled(chrome.skip, false)
        SetButtonEnabled(chrome.next, true)
    elseif warning then
        SetButtonEnabled(chrome.back, true)
        SetButtonEnabled(chrome.keep, false)
        SetButtonEnabled(chrome.skip, true)
        SetButtonEnabled(chrome.next, false)
    else
        local changeReady = stage.special or not position.control or touched
        SetButtonEnabled(chrome.back, not firstPosition)
        SetButtonEnabled(chrome.keep, not final and stage.id ~= "menu_basics" and not waitingForAnchorDecision and not waitingForEditModeMove and not waitingForGroupMove)
        SetButtonEnabled(chrome.skip, not final)
        SetButtonEnabled(chrome.next, changeReady
            and (stage.id ~= "menu_basics" or SetupAreaDecisionComplete())
            and not waitingForAnchorDecision
            and (not waitingForEditModeMove or editPopupActionReady)
            and (not waitingForGroupMove or groupPopupActionReady))
    end
    SetButtonEnabled(chrome.pause, true)
    chrome:Show()
    if (reason == "HOST_SIZE" or reason == "WINDOW_RESIZE")
        and not profileMismatch and not manualAway
        and not stage.special and not position.overview and position.section
    then
        FocusGuidedWidget(position.control and position.control.widget, position.section.outer, false)
    end
    local signature = table.concat({ stage.id, position.section and position.section.id or "overview", position.control and position.control.id or "section", profileMismatch and "profile" or (warning and "warning" or "normal"), manualAway and "away" or "guided" }, "\031")
    PlayChromeTransition(chrome, signature, reason)
    RefreshEditModeOpenCue(showEditModeOpenCue)
    RefreshEditModePlacementCue()
    FlashGuidedClickTargets(chrome, stage, position, {
        profileMismatch = profileMismatch,
        manualAway = manualAway,
        warning = warning,
    }, reason)
    return true
end

local function ChromeButton(parent, T, label, handler)
    local button = T.Button(parent, Tr(label), 70, 24)
    button._msuf2SkipHistoryCheckpoint = true
    if type(T.CenterButtonLabel) == "function" then T.CenterButtonLabel(button) end
    button:SetScript("OnClick", function(self)
        if self._msuf2GuidedEnabled == false or BlockedByCombat() then return end
        handler()
    end)
    return button
end

local function RegisterChromeControl(button, suffix, label, help)
    if type(M.RegisterMenuChromeControl) == "function" then
        M.RegisterMenuChromeControl(button, "guided-tour." .. suffix, Tr(label), "action", {
            actionKey = "guided_setup_step",
            actionFixedArgs = { step = suffix },
            historyMode = "none",
            help = Tr(help),
        })
    end
end

function M.RunGuidedTourStep(step)
    step = tostring(step or ""):lower()
    if BlockedByCombat() or not TourIsActive() then return false, "guided_setup_inactive" end
    local stage = CurrentStage()
    ReconcileGuidedEditModePopup(stage)
    if step == "next" and stage.id == "menu_basics" and not SetupAreaDecisionComplete() then
        return false, "guided_setup_area_required"
    end
    if (step == "keep" or step == "next") and stage.id == "edit_mode" then
        if not CooldownAnchorDecisionComplete() then return false, "guided_edit_mode_anchor_required" end
        if not EditModePlacementComplete() then
            if step == "next" and EditModeMovementComplete() and OpenGuidedEditModePopup("player", stage) then
                return true, "guided_edit_mode_popup_opened"
            end
            return false, "guided_edit_mode_move_required"
        end
    end
    if (step == "keep" or step == "next") and stage.id == "group_edit_mode"
        and not GroupEditModePlacementComplete()
    then
        if step == "next" and GroupEditModeMovementComplete() and OpenGuidedEditModePopup("gf_party", stage) then
            return true, "guided_group_edit_mode_popup_opened"
        end
        return false, "guided_group_edit_mode_move_required"
    end
    if step == "next" and not Runtime.manualAway and not Runtime.warning
        and not select(1, ProfileMismatch()) and not stage.special
    then
        local position = CurrentPosition(stage)
        if position.control and not CurrentControlTouched(stage, position) then
            return false, "guided_setting_change_required"
        end
    end
    if step == "back" then
        BackCurrent()
    elseif step == "keep" then
        AdvanceCurrent("kept")
    elseif step == "skip" then
        local skipped = SkipCurrent()
        if skipped and Runtime.warning then
            return true, "confirmation_needed", Runtime.warning.text
        end
    elseif step == "next" then
        if Runtime.manualAway then
            Runtime.manualAway = nil
            SelectExpectedPage(CurrentStage())
        else
            AdvanceCurrent("reviewed")
        end
    elseif step == "pause" then
        PauseTour()
    else
        return false, "unknown_guided_setup_step"
    end
    return true, step
end

function M.InstallGuidedTourChrome(frame, status, host, scroll)
    Runtime.chromeFrame = frame or Runtime.chromeFrame
    Runtime.chromeStatus = status or Runtime.chromeStatus
    Runtime.chromeHost = host or Runtime.chromeHost
    Runtime.chromeScroll = scroll or Runtime.chromeScroll
    if Runtime.chrome then
        Runtime.chrome.frame = Runtime.chromeFrame or Runtime.chrome.frame
        Runtime.chrome.status = Runtime.chromeStatus or Runtime.chrome.status
        Runtime.chrome.host = Runtime.chromeHost or Runtime.chrome.host
        Runtime.chrome.scroll = Runtime.chromeScroll or Runtime.chrome.scroll
        M.RefreshGuidedTourChrome("REINSTALL")
        return Runtime.chrome
    end
    if not TourIsActive() then return nil end
    frame, status, host, scroll = Runtime.chromeFrame, Runtime.chromeStatus, Runtime.chromeHost, Runtime.chromeScroll
    local T = M.Theme
    if not (frame and status and host and scroll and T and type(T.Panel) == "function" and type(T.Font) == "function" and type(T.Button) == "function") then
        return nil
    end

    local chrome = T.Panel(host, nil, T.colors.glassStatus or T.colors.header, T.colors.borderSoft)
    if type(T.ApplySurface) == "function" then T.ApplySurface(chrome, "status") end
    chrome:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, 0)
    chrome:SetPoint("TOPRIGHT", status, "BOTTOMRIGHT", 0, 0)
    chrome:SetHeight(132)
    if type(chrome.SetFrameLevel) == "function" then chrome:SetFrameLevel((host:GetFrameLevel() or 1) + 5) end
    chrome.frame, chrome.status, chrome.host, chrome.scroll = frame, status, host, scroll

    local divider = chrome:CreateTexture(nil, "ARTWORK", nil, 3)
    divider:SetPoint("BOTTOMLEFT", chrome, "BOTTOMLEFT", 16, 0)
    divider:SetPoint("BOTTOMRIGHT", chrome, "BOTTOMRIGHT", -16, 0)
    divider:SetHeight(1)
    divider:SetColorTexture(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 0.18)

    local iconWell = T.Panel(chrome, nil, T.colors.pillBaseSolid or T.colors.panel2, T.colors.pillEdge or T.colors.borderSoft)
    if type(T.ApplySurface) == "function" then T.ApplySurface(iconWell, "card") end
    local icon = iconWell:CreateTexture(nil, "ARTWORK", nil, 2)
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", iconWell, "CENTER", 0, 0)
    chrome.iconWell, chrome.icon = iconWell, icon

    chrome.title = T.Font(chrome, "GameFontNormal", "", T.colors.text)
    chrome.title:SetJustifyH("LEFT")
    chrome.step = T.Font(chrome, "GameFontDisableSmall", "", T.colors.accent)
    chrome.step:SetJustifyH("RIGHT")
    chrome.section = T.Font(chrome, "GameFontDisableSmall", "", T.colors.muted)
    chrome.section:SetJustifyH("LEFT")
    local cueArrow = chrome:CreateTexture(nil, "OVERLAY", nil, 4)
    local cueAtlas = false
    if cueArrow.SetAtlas then cueArrow:SetAtlas("NPE_ArrowRight", false); cueAtlas = true end
    if not cueAtlas then cueArrow:SetTexture(T.media.collapseArrow) end
    cueArrow:SetSize(16, 16)
    cueArrow:SetVertexColor(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 1)
    chrome.cueArrow = cueArrow
    chrome.help = T.Font(chrome, "GameFontHighlightSmall", "", T.colors.muted)
    chrome.help:SetJustifyH("LEFT")
    if chrome.help.SetWordWrap then chrome.help:SetWordWrap(true) end
    if chrome.help.SetNonSpaceWrap then chrome.help:SetNonSpaceWrap(true) end

    local progress = CreateFrame("Frame", nil, chrome)
    local progressBg = progress:CreateTexture(nil, "BACKGROUND")
    progressBg:SetAllPoints()
    local track = T.colors.coreShadow or T.colors.bg
    progressBg:SetColorTexture(track[1], track[2], track[3], 0.92)
    local progressFill = progress:CreateTexture(nil, "ARTWORK")
    progressFill:SetPoint("TOPLEFT", progress, "TOPLEFT", 1, -1)
    progressFill:SetPoint("BOTTOMLEFT", progress, "BOTTOMLEFT", 1, 1)
    progressFill:SetWidth(1)
    progressFill:SetColorTexture(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 0.96)
    chrome.progress, chrome.progressFill = progress, progressFill

    chrome.back = ChromeButton(chrome, T, "Back", function() M.RunGuidedTourStep("back") end)
    chrome.keep = ChromeButton(chrome, T, "Keep current", function() M.RunGuidedTourStep("keep") end)
    chrome.skip = ChromeButton(chrome, T, "Skip", function() M.RunGuidedTourStep("skip") end)
    chrome.next = ChromeButton(chrome, T, "Next", function() M.RunGuidedTourStep("next") end)
    chrome.pause = ChromeButton(chrome, T, "Pause", function() M.RunGuidedTourStep("pause") end)
    if type(T.SkinPrimaryButton) == "function" then T.SkinPrimaryButton(chrome.next) end

    RegisterChromeControl(chrome.back, "back", "Guided setup: Back", "Returns to the previous highlighted setting or mission.")
    RegisterChromeControl(chrome.keep, "keep", "Guided setup: Keep unchanged", "Keeps the highlighted setting unchanged and moves to the next green target.")
    RegisterChromeControl(chrome.skip, "skip", "Guided setup: Skip", "Shows an inline impact warning before skipping.")
    RegisterChromeControl(chrome.next, "next", "Guided setup: Next", "Unlocks after the highlighted setting changes, then marks the next setting in green.")
    RegisterChromeControl(chrome.pause, "pause", "Guided setup: Pause", "Closes the menu while preserving guided setup progress.")

    Runtime.chrome = chrome
    chrome:Hide()
    if type(host.HookScript) == "function" and not host._msuf2GuidedTourSizeHook then
        host._msuf2GuidedTourSizeHook = true
        host:HookScript("OnSizeChanged", function()
            if TourIsActive() then M.RefreshGuidedTourChrome("HOST_SIZE") end
        end)
    end
    if type(frame.HookScript) == "function" and not frame._msuf2GuidedTourHideHook then
        frame._msuf2GuidedTourHideHook = true
        frame:HookScript("OnHide", function()
            ClearSectionEmphasis()
            StopChromeTransition(chrome)
        end)
    end
    M.RefreshGuidedTourChrome("INSTALL")
    return chrome
end

EnsureGuidedTourChrome = function()
    if Runtime.chrome then return Runtime.chrome end
    if not TourIsActive() then return nil end
    if not (Runtime.chromeFrame and Runtime.chromeStatus and Runtime.chromeHost and Runtime.chromeScroll) then return nil end
    return M.InstallGuidedTourChrome(
        Runtime.chromeFrame, Runtime.chromeStatus, Runtime.chromeHost, Runtime.chromeScroll)
end

function M.GuidedTourOnPageSelected(pageKey)
    if not TourIsActive() then
        if Runtime.tourVisualsDirty == true then M.RefreshGuidedTourChrome("PAGE_INACTIVE") end
        return false
    end
    EnsureGuidedTourChrome()
    local stage = CurrentStage()
    local expected = ExpectedPage(stage)
    if tostring(pageKey or "") ~= expected then
        Runtime.manualAway = true
        Runtime.warning = nil
        ClearSectionEmphasis()
        M.RefreshGuidedTourChrome("MANUAL_PAGE")
        return false
    end
    Runtime.manualAway = nil
    if not stage.special then
        CurrentPosition(stage) -- migrate old overview/section cursors to a real control first
        FocusCurrentSection(stage)
    end
    M.RefreshGuidedTourChrome("GUIDED_PAGE")
    return true
end

function M.StartGuidedTour(opts)
    if BlockedByCombat() then return false end
    opts = type(opts) == "table" and opts or {}
    local stage = STAGE_BY_ID[tostring(opts.stageId or "")] or STAGES[1]
    local restorePoint
    if type(M.CaptureGuidedTourRestorePoint) == "function" then
        local captured, value = InvokeGuidedBoundary(M.CaptureGuidedTourRestorePoint)
        if captured and type(value) == "table" then restorePoint = value end
    end
    local ok = Invoke(Tour(), "Start", ActiveProfileName(), stage.id, restorePoint)
    if not ok then return false end
    local requestedMode = tostring(opts.mode or "")
    if not VALID_SETUP_MODE[requestedMode] then
        requestedMode = opts.stageId and "complete" or "quick"
    end
    Invoke(Tour(), "SetPreference", "setupMode", requestedMode)
    if VALID_SETUP_AREA[tostring(opts.setupArea or "")] then
        Invoke(Tour(), "SetPreference", "setupArea", tostring(opts.setupArea))
    end
    Invoke(FirstLoad(), "Start", "guided_tour")
    Runtime.warning = nil
    Runtime.manualAway = nil
    Runtime.touchedSignature = nil
    Runtime.lastVisualSignature = nil
    Invoke(Tour(), "SetStage", stage.id, stage.index)
    WriteCursor(stage, InitialCursor(stage))
    if type(M.InvalidatePage) == "function" then
        M.InvalidatePage("home")
        M.InvalidatePage("guided_setup")
    end
    return SelectExpectedPage(stage)
end

function M.ResumeGuidedTour()
    if BlockedByCombat() or not TourIsActive() then return false end
    Invoke(Tour(), "Resume")
    Runtime.warning = nil
    Runtime.manualAway = nil
    return SelectExpectedPage(CurrentStage())
end

function M.OpenGuidedTourAtStage(stageId, opts)
    if BlockedByCombat() then return false end
    opts = type(opts) == "table" and opts or {}
    local stage = STAGE_BY_ID[tostring(stageId or "")]
    if not stage then return false end
    if not TourIsActive() then
        opts.stageId = stage.id
        return M.StartGuidedTour(opts)
    end
    ClearSectionEmphasis()
    Invoke(Tour(), "SetStage", stage.id, stage.index)
    if opts.resetCursor == true then WriteCursor(stage, InitialCursor(stage)) end
    Runtime.warning = nil
    Runtime.manualAway = nil
    return SelectExpectedPage(stage)
end

function M.GetGuidedTourCurrentPage()
    return ExpectedPage(CurrentStage())
end

function M.GetGuidedTourSummary()
    local ok, source = Invoke(Tour(), "GetSummary")
    source = ok and type(source) == "table" and source or {}
    local activeStages = ActiveStages()
    local activeStageIds = {}
    for i = 1, #activeStages do activeStageIds[activeStages[i].id] = true end
    local summary = {
        reviewedStages = tonumber(source.reviewedStages) or 0,
        keptStages = tonumber(source.keptStages) or 0,
        skippedStages = tonumber(source.skippedStages) or 0,
        reviewedSections = tonumber(source.reviewedSections) or 0,
        keptSections = tonumber(source.keptSections) or 0,
        skippedSections = tonumber(source.skippedSections) or 0,
        reviewedControls = tonumber(source.reviewedControls) or 0,
        keptControls = tonumber(source.keptControls) or 0,
        skippedControls = tonumber(source.skippedControls) or 0,
        totalStages = #activeStages,
        skippedItems = {},
        skippedAreas = {},
        skippedSectionItems = {},
    }
    local state = TourState()
    local stageResults = type(state.stageResults) == "table" and state.stageResults or {}
    for i = 1, #activeStages do
        local stage = activeStages[i]
        if stageResults[stage.id] == "s" then
            summary.skippedAreas[#summary.skippedAreas + 1] = Tr(stage.title)
        end
    end
    local sectionResults = type(state.sectionResults) == "table" and state.sectionResults or {}
    local sectionMetadata = type(state.sectionMetadata) == "table" and state.sectionMetadata or {}
    for resultKey, code in pairs(sectionResults) do
        if code == "s" then
            local metadata = type(sectionMetadata[resultKey]) == "table" and sectionMetadata[resultKey] or {}
            local stageId = tostring(metadata.stageId or resultKey:match("^(.-)\031") or "")
            local stage = STAGE_BY_ID[stageId]
            if stage and activeStageIds[stageId] and stageResults[stageId] ~= "s" then
                summary.skippedSectionItems[#summary.skippedSectionItems + 1] = {
                    stageIndex = stage.index,
                    stageLabel = Tr(stage.title),
                    label = Tr(metadata.label or metadata.sectionId or "Section"),
                }
            end
        end
    end
    sort(summary.skippedSectionItems, function(a, b)
        if a.stageIndex ~= b.stageIndex then return a.stageIndex < b.stageIndex end
        return a.label < b.label
    end)
    local skipped = type(state.skippedControls) == "table" and state.skippedControls or {}
    for controlId, item in pairs(skipped) do
        if type(item) == "table" then
            local stageId = tostring(item.stageId or "")
            local sectionId = tostring(item.sectionId or "")
            local coveredByStage = stageResults[stageId] == "s"
            local coveredBySection = sectionId ~= "" and sectionResults[stageId .. "\031" .. sectionId] == "s"
            if activeStageIds[stageId] and not coveredByStage and not coveredBySection then
                local stage = STAGE_BY_ID[stageId]
                summary.skippedItems[#summary.skippedItems + 1] = {
                    controlId = tostring(controlId),
                    stageId = stageId,
                    stageIndex = stage and stage.index or (#STAGES + 1),
                    stageLabel = stage and Tr(stage.title) or Tr("Guided setup"),
                    label = tostring(item.label or controlId),
                    pageKey = item.pageKey,
                    sectionId = item.sectionId,
                }
            end
        end
    end
    sort(summary.skippedItems, function(a, b)
        if a.stageIndex ~= b.stageIndex then return a.stageIndex < b.stageIndex end
        local al, bl = a.label:lower(), b.label:lower()
        return al == bl and a.controlId < b.controlId or al < bl
    end)
    return summary
end

local function SetWrapped(fontString, width)
    if not fontString then return end
    fontString:SetWidth(max(40, width or 40))
    fontString:SetJustifyH("LEFT")
    if fontString.SetWordWrap then fontString:SetWordWrap(true) end
    if fontString.SetNonSpaceWrap then fontString:SetNonSpaceWrap(true) end
end

local function AddCardIcon(card, T, iconKey)
    local well = T.Panel(card, nil, T.colors.pillBaseSolid or T.colors.panel2, T.colors.pillEdge or T.colors.borderSoft)
    well:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -16)
    well:SetSize(32, 32)
    local icon = well:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)
    icon:SetPoint("CENTER")
    local grid = T.navIconGrid and T.navIconGrid[iconKey]
    if grid and T.media and T.media.navIcons then
        icon:SetTexture(T.media.navIcons)
        icon:SetTexCoord(grid[1] / 8, (grid[1] + 1) / 8, grid[2] / 8, (grid[2] + 1) / 8)
    elseif T.media and T.media.logo then
        icon:SetTexture(T.media.logo)
        icon:SetTexCoord(0.075, 0.925, 0.075, 0.925)
    end
    local color = T.navIconColors and T.navIconColors[iconKey] or T.colors.accent
    icon:SetVertexColor(color[1], color[2], color[3], 1)
    return well
end

local function InfoCard(builder, T, title, body, iconKey, height)
    local card = builder:Section("", height or 82)
    if card.title then card.title:SetText("") end
    AddCardIcon(card, T, iconKey or "home")
    local heading = T.Font(card, "GameFontNormal", Tr(title), T.colors.text)
    heading:SetPoint("TOPLEFT", card, "TOPLEFT", 56, -12)
    heading:SetPoint("RIGHT", card, "RIGHT", -16, 0)
    heading:SetJustifyH("LEFT")
    local copy = T.Font(card, "GameFontHighlightSmall", Tr(body), T.colors.muted)
    copy:SetPoint("TOPLEFT", card, "TOPLEFT", 56, -36)
    SetWrapped(copy, builder.width - 70)
    if type(T.PlayMotion) == "function" then
        T.PlayMotion(card, "controlFocusIn", { fromAlpha = 0.18, toAlpha = 1, duration = 0.20 })
    end
    return card
end

-- InfoCard with a screenshot below the copy. Rounded corners are the one thing
-- on the overview page that a sentence cannot demonstrate, so that card shows a
-- real frame instead. The art is 2:1, so the card height follows the width.
local TOUR_PREVIEW_MAX_WIDTH = 320
local TOUR_PREVIEW_COPY_HEIGHT = 76

local function TourPreview(key)
    local helpers = M.PreviewHelpers
    local previews = type(helpers) == "table" and helpers.TourPreviews or nil
    local spec = type(previews) == "table" and previews[key] or nil
    if type(spec) ~= "table" or type(spec.texture) ~= "string" then return nil end
    return spec
end

local function PreviewCard(builder, T, W, title, body, iconKey, spec)
    if not (type(spec) == "table" and type(W.PreviewImage) == "function") then
        return InfoCard(builder, T, title, body, iconKey, 92)
    end
    local imageWidth = min(TOUR_PREVIEW_MAX_WIDTH, max(180, builder.width - 72))
    local imageHeight = floor(imageWidth / (tonumber(spec.aspect) or 2) + 0.5)
    local card = InfoCard(builder, T, title, body, iconKey, TOUR_PREVIEW_COPY_HEIGHT + imageHeight + 16)
    W.PreviewImage(card, spec, 56, -TOUR_PREVIEW_COPY_HEIGHT, imageWidth)
    return card
end

local function Header(builder, title, subtitle)
    return builder:Header(Tr(title), Tr(subtitle), 72)
end

local function PersonalQuestion(ctx, builder, T, W, key, label, values, opts)
    opts = type(opts) == "table" and opts or {}
    local card = builder:Section("", 100)
    if card.title then card.title:SetText("") end
    local localized = {}
    for i = 1, #values do
        localized[i] = { value = values[i].value, text = Tr(values[i].text), icon = values[i].icon }
    end
    local segment = W.Segment(card, Tr(label), localized, max(240, builder.width - 28))
    RegisterSpecialClickTargets("menu_basics", key, segment.buttons)
    local function Refresh()
        segment:SetValue(Preference(key))
    end
    for i = 1, #(segment.buttons or {}) do
        local button = segment.buttons[i]
        local value = localized[i]
        if value and type(T.AttachNavIcon) == "function" then T.AttachNavIcon(button, value.icon, false, true) end
        button:SetScript("OnClick", function(self)
            if BlockedByCombat() then return end
            Invoke(Tour(), "SetPreference", key, self._msuf2Value)
            Refresh()
            if type(T.PlayMotion) == "function" then
                T.PlayMotion(self, "controlFocusIn", { fromAlpha = 0.45, toAlpha = 1, duration = 0.16 })
            end
            M.RefreshGuidedTourChrome("PERSONAL_CHOICE")
        end)
    end
    if opts.registerSearch ~= false and type(M.RegisterSearchWidget) == "function" then
        local identity = "guided_setup.preference." .. key
        M.RegisterSearchWidget(segment, {
            controlId = "menu2." .. identity,
            identityKey = identity,
            controlPath = identity:gsub("%.", "/"),
            pageKey = "guided_setup",
            label = Tr(label),
            kind = "segment",
            classification = "ephemeral",
            ephemeral = true,
            help = Tr("Personalizes guided setup hints without changing MSUF settings."),
        })
    end
    if type(ctx.AddRefresher) == "function" then ctx:AddRefresher(Refresh) end
    Refresh()
    return card
end

local function BuildMenuBasicsPage(ctx, T, W)
    Runtime.specialClickTargets = { stageId = "menu_basics", groups = {} }
    local b = W.PageBuilder(ctx)
    Header(b, format(Tr("Welcome, %s"), PlayerDisplayName()), "Choose a short setup or the complete learning tour.")
    PersonalQuestion(ctx, b, T, W, "setupMode", "How much help do you want?", {
        { value = "quick", text = "Quick Setup - essentials", icon = "home" },
        { value = "complete", text = "Complete Tour - every detail", icon = "profiles" },
    }, { registerSearch = false })
    PersonalQuestion(ctx, b, T, W, "setupArea", "What do you want to set up?", {
        { value = "unitframes", text = "Unitframes", icon = "uf_player" },
        { value = "groupframes", text = "Group Frames", icon = "gf_layout" },
        { value = "classresources", text = "Class Resources", icon = "classpower" },
        { value = "all", text = "Everything", icon = "home" },
    })
    InfoCard(b, T, "Quick Setup stays focused", "It shows only the essential choices. The Complete Tour keeps every advanced checkpoint available.", "home", 82)
    return math.abs(b.y) + 34
end

local function BuildChapterPage(ctx, T, W, stage)
    Runtime.specialClickTargets = { stageId = stage.id, groups = {} }
    local b = W.PageBuilder(ctx)
    local selected = SelectedSetupArea()
    local all = selected == "all"
    if stage.id == "unit_intro" then
        Header(b, all and "Part 1 of 3 - Unitframes" or "Unitframes", "Build Player once. Copy it when it feels right.")
        InfoCard(b, T, "Move the whole frame", "Edit Mode: drag the Player mover to place the frame on screen.", "uf_player", 76)
        InfoCard(b, T, "Change its size", "Click the mover in Edit Mode: its popup contains Width, Height, and other frame details.", "uf_player", 82)
        InfoCard(b, T, "Then Copy To", "Tune Player in the Live Preview, select All, and copy the result to another Unitframe.", "uf_target", 82)
    elseif stage.id == "group_intro" then
        if type(M.SetMenuStateValue) == "function" then M.SetMenuStateValue("gfScope", "party") else M.gfScope = "party" end
        Header(b, all and "Part 2 of 3 - Group Frames" or "Group Frames", "Build Party once. Copy it to Raid or Mythic Raid.")
        InfoCard(b, T, "Move the group", "Edit Mode: drag the Party Frames mover to place the complete group container.", "gf_layout", 76)
        InfoCard(b, T, "Change frame geometry", "Click the mover: its popup controls frame Width, Height, and Spacing.", "gf_layout", 82)
        InfoCard(b, T, "Then Copy To", "Finish Party, select All, and press Raid or Mythic to copy the setup instantly.", "gf_indicators", 82)
    else
        Header(b, all and "Part 3 of 3 - Class Resources" or "Class Resources", "Use the interactive preview to shape your class display.")
        InfoCard(b, T, "Class-aware preview", "Test the current class layout and change its size and arrangement live.", "classpower", 78)
        InfoCard(b, T, "Cooldown-aware placement", "Anchor it to Essential Cooldowns or keep it independently placed in Edit Mode.", "classpower", 82)
    end
    return math.abs(b.y) + 34
end

local function RegisterGuidedPageButton(button, suffix, label, help)
    if type(M.RegisterSearchWidget) == "function" then
        local identity = "guided_setup." .. suffix
        M.RegisterSearchWidget(button, {
            controlId = "menu2." .. identity,
            identityKey = identity,
            controlPath = identity:gsub("%.", "/"),
            pageKey = "guided_setup",
            label = Tr(label),
            kind = "button",
            classification = "action",
            help = Tr(help),
            historyMode = "none",
        })
    end
end

local function BuildEditModePage(ctx, T, W)
    Runtime.specialClickTargets = { stageId = "edit_mode", groups = {} }
    local b = W.PageBuilder(ctx)
    Header(b, "Move vs size", "Drag Player to move it. Click Player to open the popup for Width and Height.")

    local decisionCard = b:Section("", 146)
    if decisionCard.title then decisionCard.title:SetText("") end
    local decisionValues = {
        { value = "cooldown", text = Tr("Follow Blizzard's Essential Cooldowns") },
        { value = "independent", text = Tr("Independent placement") },
    }
    local decision = W.Segment(decisionCard, Tr("Should all Unitframes follow the Cooldown Manager?"), decisionValues, max(240, b.width - 32))
    RegisterSpecialClickTargets("edit_mode", "anchor", decision.buttons)
    if type(W.MoveWidget) == "function" then W.MoveWidget(decision, decisionCard, 16, -18, max(240, b.width - 32), "LEFT") end
    local decisionCopy = T.Font(decisionCard, "GameFontHighlightSmall", "", T.colors.muted)
    decisionCopy:SetPoint("TOPLEFT", decisionCard, "TOPLEFT", 16, -88)
    SetWrapped(decisionCopy, b.width - 32)

    InfoCard(b, T, "Two different actions", "DRAG = move the whole frame. CLICK = open its size and detail popup. Arrow keys nudge; Undo stays available.", "uf_player", 82)

    local action = b:Section("", 84)
    if action.title then action.title:SetText("") end
    local stateLabel = T.Font(action, "GameFontNormal", "", T.colors.text)
    stateLabel:SetPoint("TOPLEFT", action, "TOPLEFT", 16, -20)
    stateLabel:SetWidth(max(120, b.width - 252))
    stateLabel:SetJustifyH("LEFT")
    local stateCopy = T.Font(action, "GameFontDisableSmall", "", T.colors.muted)
    stateCopy:SetPoint("TOPLEFT", stateLabel, "BOTTOMLEFT", 0, -8)
    stateCopy:SetWidth(max(120, b.width - 252))
    stateCopy:SetJustifyH("LEFT")
    local button = T.Button(action, Tr("Open MSUF Edit Mode"), min(210, max(150, floor(b.width * 0.30))), 28)
    button:SetPoint("RIGHT", action, "RIGHT", -16, 0)
    if type(T.CenterButtonLabel) == "function" then T.CenterButtonLabel(button) end
    if type(T.SkinPrimaryButton) == "function" then T.SkinPrimaryButton(button) end

    local function Refresh()
        local status = type(M.EditModeLifecycleStatus) == "function" and M.EditModeLifecycleStatus() or {}
        local active = status.active == true
        local _, automaticProviderLabel = AutomaticCooldownProvider()
        local anchorDecision = CooldownAnchorDecision()
        local placementComplete = EditModePlacementComplete()
        local movementComplete = EditModeMovementComplete()
        decision:SetValue(anchorDecision)
        for i = 1, #(decision.buttons or {}) do
            SetButtonEnabled(decision.buttons[i], true)
        end
        if decision._msuf2Title and decision._msuf2Title.SetText then
            decision._msuf2Title:SetText(automaticProviderLabel
                and M.Format("Cooldown Manager anchoring (%s)", automaticProviderLabel)
                or Tr("Should all Unitframes follow the Cooldown Manager?"))
        end
        if anchorDecision == "cooldown" then
            decisionCopy:SetText(Tr("Selected: Unitframes follow Blizzard's Essential Cooldowns. If Blizzard's Essential Cooldowns move, the anchored Unitframe layout follows."))
        elseif anchorDecision == "independent" then
            decisionCopy:SetText(Tr("Selected: Unitframes use the current global/custom anchor. Moving Blizzard's Essential Cooldowns will not move them."))
        else
            decisionCopy:SetText(Tr("Required before placement. Changing this later can shift the whole layout because the saved offsets use a different anchor."))
        end
        if placementComplete then
            stateLabel:SetText(Tr("Frame moved - placement complete"))
            stateCopy:SetText(active and Tr("Exit keeps the result. You can now continue the guide.") or Tr("The required Edit Mode movement is complete."))
        elseif movementComplete then
            stateLabel:SetText(Tr("Player moved - now open its size popup"))
            stateCopy:SetText(Tr("Click the highlighted Player mover. Width and Height live in that popup."))
        elseif active then
            stateLabel:SetText(Tr("Move one highlighted frame to continue"))
            stateCopy:SetText(Tr("Two arrows point to a movable frame. Drag it once; Next unlocks after a real position change."))
        elseif anchorDecision then
            stateLabel:SetText(Tr("Anchor chosen - open Edit Mode and move a frame"))
            stateCopy:SetText(Tr("The placement step completes after you drag the highlighted frame once."))
        else
            stateLabel:SetText(Tr("Choose anchoring before placement"))
            stateCopy:SetText(Tr("Edit Mode unlocks after the anchor choice above."))
        end
        SetFontColor(stateLabel, placementComplete and (T.colors.ok or T.colors.accent) or (active and (T.colors.warning or T.colors.accent) or T.colors.text))
        SetButtonText(button, active and "Exit and keep changes" or "Open MSUF Edit Mode")
        SetButtonEnabled(button, not status.combatLocked and (active or anchorDecision ~= nil))
    end
    for i = 1, #(decision.buttons or {}) do
        local choice = decision.buttons[i]
        choice:SetScript("OnClick", function(self)
            if SetGuidedCooldownAnchorDecision(self._msuf2Value) then
                Refresh()
                M.RefreshGuidedTourChrome("COOLDOWN_ANCHOR_DECISION")
            end
        end)
    end
    if type(M.RegisterSearchWidget) == "function" then
        M.RegisterSearchWidget(decision, {
            controlId = "menu2.guided_setup.cooldown_anchor_decision",
            identityKey = "guided_setup.cooldown_anchor_decision",
            controlPath = "guided_setup/cooldown_anchor_decision",
            pageKey = "guided_setup",
            label = Tr("Unitframe Cooldown Manager anchoring"),
            kind = "segment",
            classification = "setting",
            help = Tr("Choose this before moving frames because it changes the anchor used by every Unitframe position."),
        })
    end
    button:SetScript("OnClick", function()
        if BlockedByCombat() then return end
        local status = type(M.EditModeLifecycleStatus) == "function" and M.EditModeLifecycleStatus() or {}
        if type(M.SetMSUFEditModeActive) == "function" then
            M.SetMSUFEditModeActive(not status.active, nil, { source = "guided_tour" })
        end
        Refresh()
    end)
    RegisterSpecialClickTargets("edit_mode", "edit_mode_toggle", { button })
    RegisterGuidedPageButton(button, "edit_mode_toggle", "Open or exit MSUF Edit Mode", "Moves whole MSUF frames and group containers; exiting keeps changes.")
    if type(ctx.AddRefresher) == "function" then ctx:AddRefresher(Refresh) end
    Refresh()
    return math.abs(b.y) + 34
end

local function BuildGroupEditModePage(ctx, T, W)
    Runtime.specialClickTargets = { stageId = "group_edit_mode", groups = {} }
    local b = W.PageBuilder(ctx)
    Header(b, "Move vs size", "Drag Party Frames to move the group. Click it for Width, Height, and Spacing.")
    InfoCard(b, T, "Practice the real workflow", "DRAG the green-marked Party Frames mover once. CLICK the mover to inspect its geometry popup.", "gf_layout", 86)

    local action = b:Section("", 92)
    if action.title then action.title:SetText("") end
    local stateLabel = T.Font(action, "GameFontNormal", "", T.colors.text)
    stateLabel:SetPoint("TOPLEFT", action, "TOPLEFT", 16, -22)
    stateLabel:SetWidth(max(120, b.width - 252))
    stateLabel:SetJustifyH("LEFT")
    local stateCopy = T.Font(action, "GameFontDisableSmall", "", T.colors.muted)
    stateCopy:SetPoint("TOPLEFT", stateLabel, "BOTTOMLEFT", 0, -8)
    stateCopy:SetWidth(max(120, b.width - 252))
    stateCopy:SetJustifyH("LEFT")
    local button = T.Button(action, Tr("Open MSUF Edit Mode"), min(210, max(150, floor(b.width * 0.30))), 28)
    button:SetPoint("RIGHT", action, "RIGHT", -16, 0)
    if type(T.CenterButtonLabel) == "function" then T.CenterButtonLabel(button) end
    if type(T.SkinPrimaryButton) == "function" then T.SkinPrimaryButton(button) end

    local function Refresh()
        local status = type(M.EditModeLifecycleStatus) == "function" and M.EditModeLifecycleStatus() or {}
        local complete = GroupEditModePlacementComplete()
        local moved = GroupEditModeMovementComplete()
        if complete then
            stateLabel:SetText(Tr("Party Frames moved - checkpoint complete"))
            stateCopy:SetText(Tr("Click its mover whenever you want the Width, Height, and Spacing popup."))
        elseif moved then
            stateLabel:SetText(Tr("Party moved - now open its geometry popup"))
            stateCopy:SetText(Tr("Click the highlighted Party Frames mover for Width, Height, and Spacing."))
        elseif status.active then
            stateLabel:SetText(Tr("Drag the highlighted Party Frames mover"))
            stateCopy:SetText(Tr("After the drag, click that mover once to see the geometry popup."))
        else
            stateLabel:SetText(Tr("Open Edit Mode and move Party Frames"))
            stateCopy:SetText(Tr("The next checkpoint unlocks after a real Party-frame position change."))
        end
        SetFontColor(stateLabel, complete and (T.colors.ok or T.colors.accent) or T.colors.text)
        SetButtonText(button, status.active and "Exit and keep changes" or "Open MSUF Edit Mode")
        SetButtonEnabled(button, not status.combatLocked)
    end
    button:SetScript("OnClick", function()
        if BlockedByCombat() then return end
        local status = type(M.EditModeLifecycleStatus) == "function" and M.EditModeLifecycleStatus() or {}
        if type(M.SetMSUFEditModeActive) == "function" then
            M.SetMSUFEditModeActive(not status.active, nil, { source = "guided_tour" })
        end
        Refresh()
    end)
    RegisterSpecialClickTargets("group_edit_mode", "group_edit_mode_toggle", { button })
    RegisterGuidedPageButton(button, "group_edit_mode_toggle", "Open or exit MSUF Edit Mode for Party Frames", "Drag moves the group container; clicking its mover opens Width, Height, and Spacing.")
    if type(ctx.AddRefresher) == "function" then ctx:AddRefresher(Refresh) end
    Refresh()
    return math.abs(b.y) + 34
end

local function BuildPowerMovesPage(ctx, T, W)
    Runtime.specialClickTargets = { stageId = "power_moves", groups = {} }
    local b = W.PageBuilder(ctx)
    Header(b, "MSUF power moves", "A focused frame workflow with direct control over the details that matter in combat.")
    InfoCard(b, T, "Touch the preview", "Click a handle to open its exact setting, drag it to move, or right-click for related actions.", "uf_player", 86)
    PreviewCard(b, T, W, "Rounded frames that match, corner for corner",
        "One clean corner style with five strength levels covers Health, embedded or detached Power, frame outlines, aggro, dispel and highlight borders, on Unitframes and Group Frames alike.",
        "opt_bars", TourPreview("rounded_frames"))
    InfoCard(b, T, "Spell Icons by spec", "Track presets or custom Spell IDs per spec, then choose icon or bar placement, cooldown behavior, and full-frame effects.", "gf_auras", 92)
    InfoCard(b, T, "Party combat intelligence", "Corner Indicators and External Defensives keep critical group information compact.", "gf_indicators", 92)
    InfoCard(b, T, "Cooldown-aware layouts", "Anchor Unitframes and Class Resources to Essential Cooldowns, or keep every frame independently placed.", "classpower", 86)
    InfoCard(b, T, "Ask instead of hunting", "Describe the result you want. The Assistant finds the exact control, keeps safeguards in place, and leaves Undo available.", "home", 86)
    return math.abs(b.y) + 34
end

local function BuildFinalReviewPage(ctx, T, W)
    local summary = M.GetGuidedTourSummary()
    local b = W.PageBuilder(ctx)
    local handled = (tonumber(summary.reviewedControls) or 0) + (tonumber(summary.keptControls) or 0)
    local quick = SelectedSetupMode() == "quick"
    Header(b, format(Tr("%s, your setup is ready"), PlayerDisplayName()), quick
        and "Finish returns to the Dashboard. Smart Search stays ready for settings and questions."
        or "Finish opens the Dashboard and puts the cursor straight into the Assistant.")
    InfoCard(b, T, quick and "You are ready to play" or "Anything else? Just ask", quick
        and "Use the Dashboard for common tasks, or type a setting or full question into Smart Search."
        or "Try: 'make Party frames wider', 'set up Spell Icons for my spec', or 'move Class Resources'. The Assistant opens the exact place and helps you finish safely.", "home", 104)
    InfoCard(b, T, "You trained on real settings", format(Tr("%d guided settings were changed or deliberately kept. Nothing was copied into a separate wizard."), handled), "uf_player", 82)

    local restorePoint = select(2, Invoke(Tour(), "GetRestorePoint"))
    if type(restorePoint) == "table" and type(M.RestoreGuidedTourRestorePoint) == "function" then
        local restoreAlreadyUsed = TourState().restorePointUsedAt ~= nil
        local restoreProfileMismatch = ProfileMismatch()
        local restore = b:Section("", 92)
        if restore.title then restore.title:SetText("") end
        local title = T.Font(restore, "GameFontNormal", Tr(restoreAlreadyUsed and "Starting setup restored" or "Starting setup saved"), T.colors.text)
        title:SetPoint("TOPLEFT", restore, "TOPLEFT", 16, -20)
        title:SetWidth(max(120, b.width - 260))
        title:SetJustifyH("LEFT")
        local copy = T.Font(restore, "GameFontDisableSmall", Tr(restoreAlreadyUsed
            and "The starting profile values are active again. Finish when you are ready."
            or "You can restore the profile state captured before this guided setup."),
            restoreAlreadyUsed and (T.colors.ok or T.colors.accent) or T.colors.muted)
        copy:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
        SetWrapped(copy, max(120, b.width - 260))
        local button = T.Button(restore, Tr(restoreAlreadyUsed and "Starting setup restored" or "Restore starting setup"), min(220, max(170, floor(b.width * 0.32))), 28)
        button:SetPoint("RIGHT", restore, "RIGHT", -16, 0)
        button._msuf2SkipHistoryCheckpoint = true
        if type(T.CenterButtonLabel) == "function" then T.CenterButtonLabel(button) end
        local armed = false
        SetButtonEnabled(button, not restoreAlreadyUsed and not restoreProfileMismatch)
        button:SetScript("OnClick", function()
            if restoreAlreadyUsed or ProfileMismatch() or BlockedByCombat() then return end
            if not armed then
                armed = true
                SetButtonText(button, "Confirm restore")
                copy:SetText(Tr("This replaces the current profile values with the setup starting point. Click again to confirm."))
                SetFontColor(copy, T.colors.warning or T.colors.warn or T.colors.muted)
                return
            end
            local point = select(2, Invoke(Tour(), "GetRestorePoint"))
            if type(point) ~= "table" then return end
            Invoke(Tour(), "MarkRestorePointUsed", true)
            local ok, restored = InvokeGuidedBoundary(M.RestoreGuidedTourRestorePoint, point)
            if not ok or restored ~= true then
                Invoke(Tour(), "MarkRestorePointUsed", false)
                armed = false
                SetButtonText(button, "Restore starting setup")
                copy:SetText(Tr("The starting setup could not be restored. Your current values remain active."))
                SetFontColor(copy, T.colors.warning or T.colors.warn or T.colors.muted)
            end
        end)
        RegisterGuidedPageButton(button, "restore_start", "Restore starting setup", "Restores the active profile values captured before guided setup began after a second confirmation.")
    end
    return math.abs(b.y) + 34
end

function M.BuildGuidedSetupPage(ctx)
    local T, W = M.Theme, M.Widgets
    if not (ctx and ctx.wrapper and T and W and type(W.PageBuilder) == "function") then return 240 end
    local stage = CurrentStage()
    if stage.id == "unit_intro" or stage.id == "group_intro" or stage.id == "class_intro" then
        return BuildChapterPage(ctx, T, W, stage)
    end
    if stage.id == "edit_mode" then return BuildEditModePage(ctx, T, W) end
    if stage.id == "group_edit_mode" then return BuildGroupEditModePage(ctx, T, W) end
    if stage.id == "power_moves" then return BuildPowerMovesPage(ctx, T, W) end
    if stage.id == "final_review" then return BuildFinalReviewPage(ctx, T, W) end
    return BuildMenuBasicsPage(ctx, T, W)
end

M.navPrimaryForKey = type(M.navPrimaryForKey) == "table" and M.navPrimaryForKey or {}
M.navPrimaryForKey.guided_setup = "home"
if type(M.RegisterPage) == "function" then
    M.RegisterPage("guided_setup", { title = "Guided Setup", build = M.BuildGuidedSetupPage, version = 1 })
end
