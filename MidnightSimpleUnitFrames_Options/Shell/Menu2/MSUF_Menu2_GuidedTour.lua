-- Guided tour stage model, preferences and contextual cues.
--- Menu-native MSUF 6.0 guided setup.
---
--- The guide walks native pages control by control. Every normal tour step owns
--- one highlighted widget and asks for a real interaction before Next unlocks.
--- It never copies settings into a second wizard and never mutates a value when
--- the user deliberately chooses Keep unchanged or Skip.

local MSUF = select(2, ...)
local Parts = {}
MSUF.GuidedTourParts = Parts
MSUF = MSUF or {}
local FILE = "Shell/Menu2/MSUF_Menu2_GuidedTour.lua"
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", FILE)

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

local CreateFrame = CreateFrame
local C_Timer = M.MenuTimer or C_Timer
local ceil, floor, max, min = math.ceil, math.floor, math.max, math.min
local format = string.format
local sort = table.sort

local function Tr(text)
    return M.Tr(tostring(text or "")) or tostring(text or "")
end

-- Every stage names its page, icon and setup area. The constructors fill those
-- shared fields (a normal stage uses its page key as its icon) so a row lists
-- only what is specific to it. Special stages are the chapter and info pages
-- hosted by the guided_setup page.
local Row = {}
function Row.Stage(area, pageKey, id, title, impact, fields)
    fields = fields or {}
    fields.id, fields.pageKey, fields.icon, fields.area = id, pageKey, pageKey, area
    fields.title, fields.impact = title, impact
    return fields
end
function Row.Unit(...) return Row.Stage("unitframes", "uf_player", ...) end
function Row.Group(pageKey, ...) return Row.Stage("groupframes", pageKey, ...) end
function Row.Special(id, icon, area, title, impact)
    return { id = id, special = true, pageKey = "guided_setup", icon = icon, area = area, title = title, impact = impact }
end

local STAGES = {
    Row.Special("menu_basics", "home", nil, "What do you want to set up?",
        "Choose Unitframes, Group Frames, Class Resources, or the complete three-part tour."),
    Row.Special("unit_intro", "uf_player", "unitframes", "Part 1 - Unitframes",
        "Skipping starts at the next selected setup area."),
    Row.Special("edit_mode", "uf_player", "unitframes", "Place your frames",
        "Skipping leaves the current frame positions and anchoring unchanged."),
    Row.Unit("uf_player", "Build your Player frame", "Skipping keeps the current Player-frame basics.",
        { includeSections = { frame_basics = true }, controlLimit = 4 }),
    Row.Unit("uf_player_auras", "Choose your Player auras", "Skipping keeps the current Player aura container and tool.", {
        includeSections = { auras = true, ["region:unit_aura_tools"] = true }, includeEphemeralControls = true, controlLimit = 2,
        controlPaths = { "auras/unit-workspace/container-selector", "auras/unit-workspace/tool-selector" } }),
    Row.Unit("uf_player_name", "Set up the Player name", "Skipping keeps the current Player name text.", {
        includeSections = { text = true }, prepareSection = "text", prepareTab = "name", prepareState = "unitTextTabSelection", controlLimit = 3,
        controlPaths = { "unit/text/name/show", "unit/text/name/anchor", "unit/text/name/size" } }),
    Row.Unit("uf_player_hp_text", "Set up Player health text", "Skipping keeps the current Player health text.", {
        includeSections = { text = true }, prepareSection = "text", prepareTab = "hp", prepareState = "unitTextTabSelection",
        prepareSlot = "right", prepareSlotState = "unitTextSlotSelection", controlLimit = 3,
        controlPaths = { "unit/text/hp/show", "unit/text/hp/slot/mode", "unit/text/hp/size" } }),
    Row.Unit("uf_player_power_text", "Set up Player power text", "Skipping keeps the current Player power text.", {
        includeSections = { text = true }, prepareSection = "text", prepareTab = "power", prepareState = "unitTextTabSelection",
        prepareSlot = "right", prepareSlotState = "unitTextSlotSelection", controlLimit = 3,
        controlPaths = { "unit/text/power/show", "unit/text/power/slot/mode", "unit/text/power/size" } }),
    Row.Unit("uf_player_portrait", "Set up the Player portrait", "Skipping keeps the current Player portrait.", {
        includeSections = { portrait = true }, prepareSection = "portrait", prepareTab = "general", prepareState = "unitPortraitTabSelection", controlLimit = 3,
        controlPaths = { "unit/portrait/enabled", "unit/portrait/position", "unit/portrait/portraitrender" } }),
    Row.Unit("uf_player_power", "Build the Player power bar", "Skipping keeps the current Player power bar.", {
        includeSections = { power_bar = true }, controlLimit = 4,
        controlPaths = { "unit/power/show", "unit/power/powerbarheight", "unit/power/embedpowerbarintohealth", "unit/power/detached" } }),
    Row.Unit("uf_player_castbar", "Build the Player castbar", "Skipping keeps the current Player castbar.", {
        includeSections = { castbar = true }, prepareSection = "castbar", prepareTab = "general", prepareState = "unitCastbarTabSelection", controlLimit = 5,
        controlPaths = { "unit/castbar/enabled", "unit/castbar/provider", "unit/castbar/show_interrupt", "unit/castbar/width_mode", "unit/castbar/height" } }),
    Row.Unit("uf_player_status", "Choose Player indicators", "Skipping keeps the current Player status indicators.", {
        includeSections = { status_icons = true }, includeEphemeralControls = true,
        prepareSection = "status_icons", prepareTab = "basic", prepareState = "unitStatusTabSelection", controlLimit = 4,
        controlPaths = { "unit/status/selector", "unit/status/selected/enabled", "unit/status/selected/size", "unit/status/midnight_style" } }),
    Row.Unit("unit_copy_open", "Copy your Player setup", "Skipping leaves the other Unitframes unchanged.", {
        includeSections = { ["region:unit_scope"] = true }, includeEphemeralControls = true, controlLimit = 1,
        controlPaths = { "unit/copy/open" } }),
    Row.Unit("unit_copy_all", "Choose what to copy", "Skipping keeps the currently selected copy categories.", {
        ensureCopyPopup = "unit", includeSections = { ["region:unit_copy_popup"] = true }, includeEphemeralControls = true, controlLimit = 1,
        controlPaths = { "unit/copy/categories/all" } }),
    Row.Unit("unit_copy_apply", "Copy Player to another Unitframe", "Skipping does not copy the Player setup.", {
        ensureCopyPopup = "unit", includeSections = { ["region:unit_copy_popup"] = true }, includeEphemeralControls = true, controlLimit = 1,
        controlPaths = { "unit/copy/run" } }),
    Row.Special("group_intro", "gf_layout", "groupframes", "Part 2 - Group Frames",
        "Skipping starts at the next selected setup area."),
    Row.Special("group_edit_mode", "gf_layout", "groupframes", "Place your Party frames",
        "Skipping leaves the current Party-frame position unchanged."),
    Row.Group("gf_layout", "gf_layout", "Build your Party frame", "Skipping keeps the current Group Frame basics.", {
        includeSections = { general = true }, controlLimit = 5,
        controlPaths = { "group/layout/scope/enable_now", "group/layout/field/showplayer", "group/layout/field/showsolo",
            "group/layout/field/smoothfill", "group/layout/field/clickcastenabled" } }),
    Row.Group("gf_layout", "gf_party_name", "Set up Party names", "Skipping keeps the current Party name text.", {
        includeSections = { text = true }, includeLockedControls = true,
        prepareSection = "text", prepareTab = "name", prepareState = "gfTextTabSelection", prepareStateIndex = "party", controlLimit = 3,
        controlPaths = { "group/layout/field/showname", "group/layout/field/nameanchor", "group/layout/field/namefontsize" } }),
    Row.Group("gf_layout", "gf_party_hp_text", "Set up Party health text", "Skipping keeps the current Party health text.", {
        includeSections = { text = true }, includeLockedControls = true,
        prepareSection = "text", prepareTab = "hp", prepareState = "gfTextTabSelection", prepareStateIndex = "party", prepareSlot = "center",
        prepareSlotState = "gfTextSlotSelection", controlLimit = 3,
        controlPaths = { "group/layout/field/showhptext", "group/layout/text/hp/slot/mode", "group/layout/field/hpfontsize" } }),
    Row.Group("gf_layout", "gf_party_power_text", "Set up Party power text", "Skipping keeps the current Party power text.", {
        includeSections = { text = true }, includeLockedControls = true,
        prepareSection = "text", prepareTab = "power", prepareState = "gfTextTabSelection", prepareStateIndex = "party", prepareSlot = "center",
        prepareSlotState = "gfTextSlotSelection", controlLimit = 3,
        controlPaths = { "group/layout/text/power/show", "group/layout/text/power/slot/mode", "group/layout/field/powerfontsize" } }),
    Row.Group("gf_layout", "gf_party_resource", "Build the Party resource bar", "Skipping keeps the current Party resource bar.", {
        includeSections = { power = true }, includeLockedControls = true, controlLimit = 4,
        controlPaths = { "group/layout/field/powerbarenabled", "group/layout/field/powerheight", "group/layout/field/powersmoothfill",
            "group/layout/field/powershowhealer" } }),
    Row.Group("gf_layout", "gf_party_range", "Tune Party range fade", "Skipping keeps the current Party range and offline opacity.", {
        includeSections = { range = true }, includeLockedControls = true, controlLimit = 4,
        controlPaths = { "group/layout/field/rangefadeenabled", "group/layout/field/rangefadelayermode", "group/layout/field/rangefadealpha",
            "group/layout/field/offlinealpha" } }),
    Row.Group("gf_bars", "gf_party_dispel", "Build the Party dispel overlay", "Skipping keeps the current Party dispel overlay.", {
        includeSections = { dispel = true }, includeLockedControls = true, controlLimit = 4,
        controlPaths = { "group/bars/field/dispeloverlayenabled", "group/bars/field/dispeloverlaytrigger", "group/bars/field/dispeloverlaystyle",
            "group/bars/field/dispeloverlayalpha" } }),
    Row.Group("gf_bars", "gf_party_stripe", "Build the Party debuff stripe", "Skipping keeps the current Party debuff stripe.", {
        includeSections = { dstripe = true }, includeLockedControls = true, controlLimit = 3,
        controlPaths = { "group/bars/field/debuffstripeenabled", "group/bars/field/debuffstripeedge", "group/bars/field/debuffstripeheight" } }),
    Row.Group("gf_indicators", "gf_party_indicators", "Choose Party frame indicators", "Skipping keeps the current Party frame indicators.", {
        includeSections = { indicators = true }, controlLimit = 4,
        controlPaths = { "group/indicators/field/targetindicator", "group/indicators/field/showgroupnumber", "group/indicators/field/hlfocusenabled",
            "group/indicators/field/groupborderenabled" } }),
    Row.Group("gf_indicators", "gf_party_status", "Choose Party status icons", "Skipping keeps the current Party status icons.", {
        includeSections = { sicons = true }, includeEphemeralControls = true, includeLockedControls = true,
        prepareSection = "sicons", prepareTab = "basic", prepareState = "gfStatusIconTabSelection", prepareStateIndex = "party", controlLimit = 4,
        controlPaths = { "group/indicators/status/selector", "group/indicators/status/selected/enabled", "group/indicators/status/selected/size",
            "group/indicators/field/usemidnighticons" } }),
    Row.Group("gf_indicators", "gf_party_corner_icons", "Build Party corner indicators",
        "Skipping keeps Party corner assignments and custom spells unchanged.", {
        includeSections = { ci = true }, includeEphemeralControls = true, includeLockedControls = true, controlLimit = 5,
        controlPaths = { "group/indicators/field/cienabled", "group/indicators/field/cisize", "group/indicators/corner/editor/slot",
            "group/indicators/corner/editor/category", "group/indicators/corner/editor/spell_ids" } }),
    Row.Group("gf_auras", "gf_party_auras", "Choose your Party auras", "Skipping keeps the current Party aura lane and tool.", {
        includeSections = { auras = true, ["region:group_aura_tools"] = true }, includeEphemeralControls = true, controlLimit = 2,
        controlPaths = { "auras/group-workspace/container-selector", "auras/group-workspace/lane/buff/tool-selector" } }),
    Row.Group("gf_auras", "gf_spell_icons", "Spell Icons by spec",
        "Skipping leaves Spell Icons unchanged; you can find them later with Menu Search.", {
        includeSections = { si = true }, includeEphemeralControls = true, includeLockedControls = true, controlLimit = 16,
        controlPaths = { "group/auras/spell/enabled", "group/auras/spell/spec", "group/auras/spell/selected_aura",
            "group/auras/spell/selected/enabled", "group/auras/spell/selected/spell_ids", "group/auras/spell/selected/only_mine",
            "group/auras/spell/selected/auto_blacklist", "group/auras/spell/selected/placed/type", "group/auras/spell/placed/anchor",
            "group/auras/spell/placed/size", "group/auras/spell/placed/x", "group/auras/spell/placed/y", "group/auras/spell/placed/growth",
            "group/auras/spell/placed/iconeffect", "group/auras/spell/selected/frame/type", "group/auras/spell/frame/alpha" } }),
    Row.Group("gf_layout", "group_copy_open", "Copy your Party setup", "Skipping leaves Raid and Mythic Raid unchanged.", {
        includeSections = { ["region:group_scope"] = true }, includeEphemeralControls = true, controlLimit = 1,
        controlPaths = { "group/layout/copy/open" } }),
    Row.Group("gf_layout", "group_copy_all", "Choose what to copy", "Skipping keeps the currently selected copy categories.", {
        ensureCopyPopup = "group", includeSections = { ["region:group_copy_popup"] = true }, includeEphemeralControls = true, controlLimit = 1,
        controlPaths = { "group/copy/categories/all" } }),
    Row.Group("gf_layout", "group_copy_apply", "Copy Party to Raid", "Skipping does not copy the Party setup.", {
        ensureCopyPopup = "group", includeSections = { ["region:group_copy_popup"] = true }, includeEphemeralControls = true, controlLimit = 1,
        controlPaths = { "group/copy/target/raid", "group/copy/target/mythicraid", "group/copy/target/party" } }),
    Row.Special("class_intro", "classpower", "classresources", "Part 3 - Class Resources",
        "Skipping leaves Class Resources unchanged."),
    Row.Stage("classresources", "classpower", "classpower", "Build your Class Resources", "Skipping keeps the current Class Resource layout.",
        { includeSections = { classpower_display = true }, controlLimit = 4 }),
    Row.Stage("shared_style", "opt_bars", "opt_bars", "Quick style: bars", "Skipping keeps the current global bar textures and gradients.",
        { includeSections = { bars_textures = true }, controlLimit = 2 }),
    Row.Stage("shared_style", "opt_fonts", "opt_fonts", "Quick style: fonts", "Skipping keeps the current global font settings.",
        { includeSections = { fonts_global_font = true }, controlLimit = 2 }),
    Row.Special("power_moves", "home", nil, "What makes MSUF different", "Skipping only hides the feature overview."),
    Row.Special("final_review", "home", nil, "Your setup is ready", "Finish the tour and use Menu Search to find other settings."),
}

local LEGACY_STAGE_TARGET = {
    uf_focus = "uf_player", uf_pet = "uf_player", uf_target = "unit_copy_open", uf_boss = "unit_copy_open",
    uf_targettarget = "uf_player", uf_focustarget = "uf_player", uf_pettarget = "uf_player",
    gf_bars = "gf_layout", gf_indicators = "gf_spell_icons", gf_auras = "gf_spell_icons",
    opt_misc = "power_moves", gameplay = "power_moves", modules = "power_moves", profiles = "power_moves",
    opt_castbar = "opt_bars", opt_colors = "opt_bars", auras3_styling = "power_moves",
}

local function IndexStagesById(stages)
    local byId = {}
    for i = 1, #stages do
        stages[i].index = i
        byId[stages[i].id] = stages[i]
    end
    return byId
end
local STAGE_BY_ID = IndexStagesById(STAGES)
M.guidedTourStageCount = #STAGES

local Tour, Invoke, CurrentStage
-- Tour preference keys, and the values the guide accepts for the choices it stores.
local PREF = { cooldownAnchor = "unitframeCooldownAnchor", editModeMoved = "editModeMoved", editModeMovedKey = "editModeMovedKey" }
local VALID = {
    setupArea = { unitframes = true, groupframes = true, classresources = true, all = true },
    setupMode = { quick = true, complete = true },
    cooldownDecision = { cooldown = true, independent = true },
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
    return VALID.setupArea[value] and value or nil
end

local function SelectedSetupMode()
    local ok, value = Invoke(Tour(), "GetPreference", "setupMode")
    value = ok and tostring(value or "") or ""
    -- Existing in-progress tours predate setupMode and must keep their full
    -- route. Every newly started tour writes an explicit mode below.
    return VALID.setupMode[value] and value or "complete"
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
local function StageIncludesSection(stage, sectionId)
    if type(stage) ~= "table" then return true end
    local included = stage.includeSections
    if type(included) == "table" and included[sectionId] ~= true then return false end
    local excluded = stage.excludeSections
    return type(excluded) ~= "table" or excluded[sectionId] ~= true
end

local Runtime = M._guidedTourRuntime or {}
M._guidedTourRuntime = Runtime
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
    local a, b, c = fn(object, ...)
    return a ~= false, a, b, c
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
    local profile = tostring(MSUF_ActiveProfile or "Default")
    return profile ~= "" and profile or "Default"
end

local function ProfileMismatch()
    local state = TourState()
    local tourProfile = tostring(state.profileName or "")
    local activeProfile = ActiveProfileName()
    return tourProfile ~= "" and tourProfile ~= activeProfile, tourProfile, activeProfile
end

local PlayerDisplayName = M.PlayerDisplayName

local function Preference(key, fallback)
    local ok, value = Invoke(Tour(), "GetPreference", key)
    if not ok or value == nil or value == "" then return fallback end
    return value
end

local function SetupAreaDecisionComplete()
    return SelectedSetupArea() ~= nil
end

local function AutomaticCooldownProvider()
    return MSUF.Require("MSUF_GetAutomaticCooldownAnchorProvider", FILE)()
end
local function CooldownAnchorEnabled()
    local general = M.GetGeneralDB() or nil
    if type(general) ~= "table" then
        local db = MSUF_DB
        general = type(db) == "table" and db.general or nil
    end
    return MSUF.Require("MSUF_IsCooldownAnchorEnabled", FILE)(general) == true
end
local function CooldownConsentDecision()
    local providerId = AutomaticCooldownProvider()
    if not providerId then return nil end
    return MSUF.Require("MSUF_GetCooldownAnchorConsentDecision", FILE)(providerId)
end
local CooldownAnchorSupported = MSUF.Require("MSUF_CooldownAnchorSupported", FILE)
local function CooldownAnchorDecision()
    -- Nothing to decide where no cooldown anchor can exist: the guide must not
    -- gate placement behind a choice the client cannot honour.
    if not CooldownAnchorSupported() then return "independent" end
    local value = Preference(PREF.cooldownAnchor)
    if VALID.cooldownDecision[value] then return value end
    if CooldownConsentDecision() ~= nil then
        return CooldownAnchorEnabled() and "cooldown" or "independent"
    end
    return nil
end
local function CooldownAnchorDecisionComplete()
    return CooldownAnchorDecision() ~= nil
end
-- Progress of the two Edit Mode stages: the mover was dragged (movement) and
-- its size popup was opened afterwards (placement).
local EditDone = {}
function EditDone.placement()
    return Preference(PREF.editModeMoved) == true
        and Preference("editModePopupOpened") == true
end
function EditDone.movement()
    return Preference(PREF.editModeMoved) == true
end
function EditDone.groupPlacement()
    return Preference("groupEditModeMoved") == true and Preference("groupEditModePopupOpened") == true
end
function EditDone.groupMovement()
    return Preference("groupEditModeMoved") == true
end

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
        if decision and EditDone.placement() then
            return Tr("CHECKPOINT CLEAR - Exit Edit Mode when happy, then claim the checkpoint.")
        end
        if decision and EditDone.movement() then
            return Tr("YOUR MOVE - Click the highlighted Player mover to open its Width and Height popup.")
        end
        if decision == "cooldown" or decision == "independent" then
            return Tr("YOUR MOVE - Press Open MSUF Edit Mode, then drag the double-arrow frame once.")
        end
        return Tr("YOUR MOVE - Choose Follow Blizzard's Essential Cooldowns or Independent placement below.")
    end
    if stage.id == "group_intro" then return Tr("PART 2 - Build Party once, then copy it to Raid or Mythic Raid.") end
    if stage.id == "group_edit_mode" then
        if EditDone.groupPlacement() then
            return Tr("CHECKPOINT CLEAR - Party Frames moved. Click the mover for its size and spacing popup whenever you need it.")
        end
        if EditDone.groupMovement() then return Tr("YOUR MOVE - Click the highlighted Party Frames mover to open Width, Height, and Spacing.") end
        return Tr("YOUR MOVE - Open Edit Mode, drag Party Frames once, then click the mover to see its Width, Height, and Spacing popup.")
    end
    if stage.id == "class_intro" then
        return Tr(CooldownAnchorSupported()
            and "PART 3 - Shape Class Resources with its interactive preview and cooldown-aware anchoring."
            or "PART 3 - Shape Class Resources with its interactive preview and independent Edit Mode placement.")
    end
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
    if stage.id == "final_review" then return Tr("MISSION COMPLETE - Press Finish to return to the Dashboard.") end
    return Tr("Review the highlighted sections; previews update while your changes autosave.")
end

local function BlockedByCombat()
    return M.BlockCombatAction() == true
end

local function SetGuidedCooldownAnchorDecision(value)
    if not VALID.cooldownDecision[value] or BlockedByCombat() then return false end
    local previousDecision = CooldownAnchorDecision()
    local enabled = value == "cooldown"
    if type(M.GetGeneralDB()) ~= "table" then
        local db = MSUF_DB
        if type(db) ~= "table" then return false end
        db.general = type(db.general) == "table" and db.general or {}
    end
    if MSUF.Require("MSUF_SetCooldownAnchorEnabled", FILE)(enabled, true) == false then return false end
    local stored = Invoke(Tour(), "SetPreference", PREF.cooldownAnchor, value)
    if not stored then return false end
    if previousDecision ~= value then
        Invoke(Tour(), "SetPreference", PREF.editModeMoved, nil)
        Invoke(Tour(), "SetPreference", PREF.editModeMovedKey, nil)
        Invoke(Tour(), "SetPreference", "editModePopupOpened", nil)
        Invoke(Tour(), "SetPreference", "editModePopupOpenedKey", nil)
    end
    local apply = M.ApplyService
    if type(apply) == "table" and type(apply.Flush) == "function" then apply.Flush() end
    return true
end
M.SetGuidedCooldownAnchorDecision = SetGuidedCooldownAnchorDecision

local function RefreshEditModePlacementCue()
    local editMode = MSUF.EditModeController
    local movers = editMode and editMode.Movers
    if movers and type(movers.RefreshGuidedPlacementCue) == "function" then
        movers.RefreshGuidedPlacementCue()
    end
end

-- The Edit Mode lifecycle status, or an empty table while the lifecycle is not registered.
local function EditModeStatus()
    return type(M.EditModeLifecycleStatus) == "function" and M.EditModeLifecycleStatus() or {}
end

local function ShouldShowEditModeOpenCue()
    if not TourIsActive() or CurrentStage().id ~= "edit_mode" then return false end
    if not CooldownAnchorDecisionComplete() or EditDone.placement() then return false end
    local status = EditModeStatus()
    return status.active ~= true and status.combatLocked ~= true
end


Parts.ActiveProfileName = ActiveProfileName
Parts.ActiveStagePosition = ActiveStagePosition
Parts.ActiveStages = ActiveStages
Parts.AutomaticCooldownProvider = AutomaticCooldownProvider
Parts.BlockedByCombat = BlockedByCombat
Parts.C_Timer = C_Timer
Parts.ControlIsAction = ControlIsAction
Parts.CooldownAnchorDecision = CooldownAnchorDecision
Parts.CooldownAnchorDecisionComplete = CooldownAnchorDecisionComplete
Parts.CooldownAnchorSupported = CooldownAnchorSupported
Parts.CreateFrame = CreateFrame
Parts.CurrentStage = CurrentStage
Parts.EditDone = EditDone
Parts.EditModeStatus = EditModeStatus
Parts.EffectiveStageControlLimit = EffectiveStageControlLimit
Parts.FirstLoad = FirstLoad
Parts.Invoke = Invoke
Parts.M = M
Parts.PersonalizedTitle = PersonalizedTitle
Parts.PixelLayoutRegion = PixelLayoutRegion
Parts.PlayerDisplayName = PlayerDisplayName
Parts.Preference = Preference
Parts.ProfileMismatch = ProfileMismatch
Parts.RefreshEditModePlacementCue = RefreshEditModePlacementCue
Parts.Runtime = Runtime
Parts.STAGES = STAGES
Parts.STAGE_BY_ID = STAGE_BY_ID
Parts.SelectedSetupArea = SelectedSetupArea
Parts.SelectedSetupMode = SelectedSetupMode
Parts.SetGuidedCooldownAnchorDecision = SetGuidedCooldownAnchorDecision
Parts.SetupAreaDecisionComplete = SetupAreaDecisionComplete
Parts.ShouldShowEditModeOpenCue = ShouldShowEditModeOpenCue
Parts.StageCue = StageCue
Parts.StageIncludesSection = StageIncludesSection
Parts.Tour = Tour
Parts.TourIsActive = TourIsActive
Parts.TourState = TourState
Parts.Tr = Tr
Parts.VALID = VALID
Parts.ceil = ceil
Parts.floor = floor
Parts.format = format
Parts.max = max
Parts.min = min
Parts.sort = sort
