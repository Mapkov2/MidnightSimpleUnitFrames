-- Deterministic Assistant action input contracts.
--
-- This catalog is deliberately independent from action run-function source and
-- parser internals.  It is loaded before action registration, attaches one
-- explicit contract to every public action, and performs no event/timer work.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Inputs = A.ActionInputs or {}
A.ActionInputs = Inputs

local CONTRACT_SOURCE = "registry.actionInputs.v1"
local Contracts = {}
local CatalogErrors = {}
Inputs.Contracts = Contracts
Inputs.CatalogErrors = CatalogErrors
Inputs.Source = CONTRACT_SOURCE

local function Trim(value)
    return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function WordList(words)
    local out = {}
    for word in tostring(words or ""):gmatch("%S+") do out[#out + 1] = word end
    return out
end

local function CopyArray(values)
    local out = {}
    for i = 1, #(values or {}) do out[i] = values[i] end
    return out
end

local function Boolean()
    return { type = "boolean" }
end

local function Number(minValue, maxValue)
    return { type = "number", min = minValue, max = maxValue }
end

local function Integer(minValue, maxValue)
    return { type = "integer", min = minValue, max = maxValue }
end

local function String(opts)
    opts = opts or {}
    return {
        type = "string",
        trim = opts.trim ~= false,
        minLength = opts.minLength,
        maxLength = opts.maxLength,
        pattern = opts.pattern,
    }
end

local function Enum(values, aliases)
    local copy = CopyArray(values)
    local lookup = {}
    for i = 1, #copy do
        local value = tostring(copy[i])
        lookup[value:lower()] = copy[i]
    end
    for alias, value in pairs(aliases or {}) do lookup[Trim(alias):lower()] = value end
    return { type = "enum", values = copy, aliases = aliases, _lookup = lookup }
end

local function TokenEnum(values, aliases)
    aliases = aliases or {}
    for i = 1, #(values or {}) do
        local value = tostring(values[i])
        aliases[value:lower():gsub("_", " ")] = values[i]
    end
    return Enum(values, aliases)
end

local function Array(items, minItems, maxItems, unique)
    return {
        type = "array",
        items = items,
        minItems = minItems,
        maxItems = maxItems,
        unique = unique == true,
    }
end

local function Map(fields)
    return { type = "map", fields = fields }
end

local function Color()
    return { type = "color" }
end

local function OneOf(...)
    return { type = "oneOf", choices = { ... } }
end

local BOOL = Boolean()
local NONEMPTY = String({ minLength = 1, maxLength = 1024 })
local SHORT_TEXT = String({ minLength = 0, maxLength = 1024 })
local NAME = String({ minLength = 1, maxLength = 128 })
local IDENTIFIER = String({ minLength = 1, maxLength = 192, pattern = "^[%w%._%-]+$" })
local IMPORT_TEXT = String({ trim = false, minLength = 1, maxLength = 4194304 })
local DYNAMIC_TEXT = String({ trim = false, minLength = 0, maxLength = 4194304 })
local DYNAMIC_SHORT_TEXT = String({ trim = false, minLength = 0, maxLength = 1024 })
local FINITE_VALUE = Number(-1000000000, 1000000000)
local DYNAMIC_SCALAR = OneOf(BOOL, FINITE_VALUE, DYNAMIC_SHORT_TEXT, Color())
local SELECTOR_VALUE = OneOf(BOOL, FINITE_VALUE, DYNAMIC_TEXT, Color())
local SPELL_TEXT = String({ minLength = 1, maxLength = 512 })
local SPELL_VALUE = OneOf(SPELL_TEXT, Integer(0))
local SPEC_VALUE = OneOf(String({ minLength = 1, maxLength = 128 }), Integer(1))

local UNIT_FRAME = Enum({
    "player", "target", "targettarget", "focustarget", "focus", "pet", "boss",
}, {
    ["target of target"] = "targettarget", tot = "targettarget",
    ["focus target"] = "focustarget", boss1 = "boss", bosses = "boss",
})
local EDIT_UNIT = Enum({
    "player", "target", "targettarget", "focustarget", "focus", "pet", "boss",
    "party", "raid", "mythicraid", "gf_priority",
}, {
    ["target of target"] = "targettarget", tot = "targettarget",
    ["focus target"] = "focustarget", boss1 = "boss", bosses = "boss",
    group = "party", ["mythic raid"] = "mythicraid",
    priority = "gf_priority", ["priority frame"] = "gf_priority", ["priority frames"] = "gf_priority",
    ["pinned frame"] = "gf_priority", ["pinned frames"] = "gf_priority",
})
local CASTBAR_UNIT = Enum({ "player", "target", "focus", "boss" }, {
    boss1 = "boss", bosses = "boss",
})
local GROUP_SCOPE = Enum({ "party", "raid", "mythicraid" }, {
    group = "party", ["mythic raid"] = "mythicraid", mythic = "mythicraid",
})
local GROUP_AURA_SCOPE = Enum({ "party", "raid" }, {
    group = "party", mythicraid = "raid", ["mythic raid"] = "raid", mythic = "raid",
})
local AURA_UNIT_INPUT_SCOPE = Enum({ "player", "target", "focus", "boss" })
local AURA_CUSTOM_CONTAINER_SCOPE = Enum({ "player", "target", "focus", "boss" })
local AURA_DIAGNOSTIC_SCOPE = Enum({ "player", "target", "focus", "boss", "party", "raid", "mythicraid" }, {
    group = "party", ["mythic raid"] = "mythicraid", mythic = "mythicraid",
})
local AURA_ROUTE_SCOPE = Enum({ "shared", "player", "target", "focus", "boss", "party", "raid", "mythicraid" }, {
    global = "shared", all = "shared", group = "party", ["mythic raid"] = "mythicraid", mythic = "mythicraid",
})
local AURA_LANE = Enum({ "buff", "debuff", "both" }, {
    buffs = "buff", helpful = "buff", debuffs = "debuff", harmful = "debuff", all = "both",
})
local GROUP_AURA_LANE = Enum({ "buff", "debuff" }, {
    buffs = "buff", helpful = "buff", debuffs = "debuff", harmful = "debuff",
})
local GLOBAL_SCOPE = Enum({
    "player", "target", "targettarget", "focustarget", "focus", "pet", "boss", "gf_party", "gf_raid",
}, {
    party = "gf_party", group = "gf_party", gfparty = "gf_party",
    raid = "gf_raid", mythicraid = "gf_raid", mythic = "gf_raid", gfraid = "gf_raid",
    ["target of target"] = "targettarget", tot = "targettarget", ["focus target"] = "focustarget",
})

local GLOBAL_SCALE_PRESET = Enum({ "1080p", "1440p", "4k", "pixel", "auto" }, {
    ["1080"] = "1080p", ["1440"] = "1440p", ["2160"] = "4k", ["2160p"] = "4k",
    ["pixel perfect"] = "pixel", off = "auto", disabled = "auto",
})
local BLACKLIST_PRESET_VALUES = {
    "RAID_BUFFS", "PRESERVATION_EVOKER", "AUGMENTATION_EVOKER", "RESTO_DRUID", "DISC_PRIEST",
    "HOLY_PRIEST", "MISTWEAVER_MONK", "RESTO_SHAMAN", "HOLY_PALADIN", "BLESSING_BRONZE",
    "SELF_BUFFS", "ROGUE_POISONS", "SHAMAN_IMBUE", "RESOURCE_AURAS", "COOLDOWNS", "SATED", "DESERTER",
    "CHALLENGE_DEBUFFS", "CLASS_UTILITY", "SKYRIDING",
}
local BLACKLIST_PRESET = Enum(BLACKLIST_PRESET_VALUES, {
    ["raid buffs"] = "RAID_BUFFS", ["preservation evoker"] = "PRESERVATION_EVOKER",
    ["augmentation evoker"] = "AUGMENTATION_EVOKER", ["resto druid"] = "RESTO_DRUID",
    ["disc priest"] = "DISC_PRIEST", ["discipline priest"] = "DISC_PRIEST",
    ["holy priest"] = "HOLY_PRIEST", ["mistweaver monk"] = "MISTWEAVER_MONK",
    ["resto shaman"] = "RESTO_SHAMAN", ["holy paladin"] = "HOLY_PALADIN",
    ["blessing bronze"] = "BLESSING_BRONZE", ["self buffs"] = "SELF_BUFFS",
    ["rogue poisons"] = "ROGUE_POISONS", ["shaman imbue"] = "SHAMAN_IMBUE",
    ["resource auras"] = "RESOURCE_AURAS", exhaustion = "SATED", deserteur = "DESERTER",
    ["challenge debuffs"] = "CHALLENGE_DEBUFFS", ["instance debuffs"] = "CHALLENGE_DEBUFFS",
    ["class utility"] = "CLASS_UTILITY", ["class utility auras"] = "CLASS_UTILITY",
    ["skyriding auras"] = "SKYRIDING", ["ride along"] = "SKYRIDING",
})
local GROUP_AURA_CATEGORY = BLACKLIST_PRESET
local PROFILE_EXPORT_KIND = Enum({ "all", "unitframe", "castbar", "colors", "gameplay", "groupframe" }, {
    full = "all", profile = "all", unitframes = "unitframe", ["unit frame"] = "unitframe",
    ["unit frames"] = "unitframe", castbars = "castbar", ["cast bar"] = "castbar",
    ["cast bars"] = "castbar", color = "colors", group = "groupframe", groupframes = "groupframe",
    ["group frame"] = "groupframe", ["group frames"] = "groupframe",
})
local SUPPORT_LINK = Enum({ "discord", "patreon", "paypal", "kofi", "github" }, {
    ["ko-fi"] = "kofi", ["ko fi"] = "kofi",
})
local DASHBOARD_PANEL = Enum({ "recovery", "scaling", "changelog", "all" })
local NAV_SECTION = Enum({ "unitframes", "groupframes", "auras", "globalstyle", "modules" }, {
    frames = "unitframes", frame = "unitframes", unitframe = "unitframes",
    group = "groupframes", groups = "groupframes", groupframe = "groupframes",
    raidframes = "groupframes", partyframes = "groupframes", aura = "auras",
    buffs = "auras", debuffs = "auras", appearance = "globalstyle", global = "globalstyle",
    style = "globalstyle", look = "globalstyle", advanced = "modules", module = "modules",
})
local SEARCH_INTRO_COMMAND = Enum({ "show", "hide", "seen", "reset" })
local CASTBAR_TYPE = Enum({ "normal", "channel", "empowered" }, {
    channeled = "channel", channelled = "channel", empower = "empowered",
})
local PREVIEW_MODE = Enum({ "current", "all" })
local BORDER_TEST_KIND = Enum({ "aggro", "dispel", "purge", "bossTarget" }, {
    bosstarget = "bossTarget", ["boss target"] = "bossTarget",
})
local CORNER_SLOT = Enum({ "TL", "TR", "BL", "BR", "C" }, {
    ["top left"] = "TL", topleft = "TL", ["top right"] = "TR", topright = "TR",
    ["bottom left"] = "BL", bottomleft = "BL", ["bottom right"] = "BR", bottomright = "BR",
    center = "C", centre = "C", middle = "C",
})
local GROUP_STATUS_ICON = Enum({
    "roleIcon", "leaderIcon", "assistIcon", "raidMarker", "readyCheckIcon", "summonIcon",
    "resurrectIcon", "pvpIcon", "phaseIcon", "statusText", "statusGhostText", "statusAFKText",
}, {
    roleicon = "roleIcon", leadericon = "leaderIcon", assisticon = "assistIcon",
    assistanticon = "assistIcon", raidmarker = "raidMarker", targetmarker = "raidMarker",
    readycheck = "readyCheckIcon", readycheckicon = "readyCheckIcon", summonicon = "summonIcon",
    resurrecticon = "resurrectIcon", resurrectionicon = "resurrectIcon", rezicon = "resurrectIcon",
    pvpicon = "pvpIcon", phaseicon = "phaseIcon", deadtext = "statusText",
    ghosttext = "statusGhostText", afktext = "statusAFKText",
})
local GAMEPLAY_FEATURE = Enum({ "all", "combatTimer", "combatState", "playerTotems", "combatCrosshair" }, {
    combattimer = "combatTimer", combatstate = "combatState", playertotems = "playerTotems",
    totems = "playerTotems", combatcrosshair = "combatCrosshair", crosshair = "combatCrosshair",
})
local GUIDED_STEP = Enum({ "back", "keep", "skip", "next", "pause" })
local SPELL_PLACED_TYPE = Enum({ "none", "icon", "square", "bar", "number" })
local SPELL_PLACED_ANCHOR = Enum({
    "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT", "CENTER", "TOP", "BOTTOM", "LEFT", "RIGHT",
}, {
    ["top left"] = "TOPLEFT", ["top right"] = "TOPRIGHT",
    ["bottom left"] = "BOTTOMLEFT", ["bottom right"] = "BOTTOMRIGHT",
    centre = "CENTER", middle = "CENTER",
})
local SPELL_PLACED_GROWTH = Enum({ "RIGHTDOWN", "LEFTDOWN", "RIGHTUP", "LEFTUP" }, {
    ["right down"] = "RIGHTDOWN", ["left down"] = "LEFTDOWN",
    ["right up"] = "RIGHTUP", ["left up"] = "LEFTUP",
})
local SPELL_FRAME_TYPE = Enum({ "none", "healthtint", "border", "glow", "pulse", "namecolor" }, {
    ["health tint"] = "healthtint", ["name color"] = "namecolor", ["name colour"] = "namecolor",
})

local POWER_TOKENS = {
    "MANA", "RAGE", "ENERGY", "FOCUS", "RUNIC_POWER", "INSANITY", "FURY", "PAIN",
    "ESSENCE", "LUNAR_POWER", "MAELSTROM",
}
local POWER_TOKEN = TokenEnum(POWER_TOKENS, {
    ["runic power"] = "RUNIC_POWER", ["astral power"] = "LUNAR_POWER",
})
local CLASS_POWER_BASE_TOKENS = {
    "COMBO_POINTS", "HOLY_POWER", "SOUL_SHARDS", "CHI", "ARCANE_CHARGES", "RUNES", "ESSENCE",
    "CHARGED", "SOUL_FRAGMENTS", "SOUL_FRAGMENTS_META", "MAELSTROM", "MAELSTROM_ABOVE_5",
    "ASTRAL_POWER", "AP_PREDICTION", "ECLIPSE_SOLAR", "ECLIPSE_LUNAR", "ECLIPSE_CA",
    "STAGGER_GREEN", "STAGGER_YELLOW", "STAGGER_RED", "SOUL_FRAGMENTS_VENG", "INSANITY",
    "MAELSTROM_POWER", "WHIRLWIND", "TIP_OF_THE_SPEAR", "ICICLES", "EBON_MIGHT", "RESOURCE_TEXT",
}
local CLASS_POWER_SLOT_COUNTS = {
    COMBO_POINTS = 7, HOLY_POWER = 5, SOUL_SHARDS = 5, CHI = 6, ARCANE_CHARGES = 4, RUNES = 6,
    ESSENCE = 6, SOUL_FRAGMENTS_VENG = 6, MAELSTROM = 10, WHIRLWIND = 4, TIP_OF_THE_SPEAR = 3, ICICLES = 5,
}
local CLASS_POWER_RESOURCE_TOKENS = {}
for token in pairs(CLASS_POWER_SLOT_COUNTS) do
    CLASS_POWER_RESOURCE_TOKENS[#CLASS_POWER_RESOURCE_TOKENS + 1] = token
end
table.sort(CLASS_POWER_RESOURCE_TOKENS)
local CLASS_POWER_COLOR_TOKEN = TokenEnum(CLASS_POWER_BASE_TOKENS)
local CLASS_POWER_RESOURCE_TOKEN = TokenEnum(CLASS_POWER_RESOURCE_TOKENS)

-- These mirror UF_COPY_CATEGORIES / GF_COPY_CATEGORIES in Menu2's Unit and
-- Group pages. A key missing here is not a cosmetic omission: the contract
-- rejects the whole action, so the category simply cannot be copied by the
-- Assistant. auras/aurastyle/texlayer were absent for units and aurastyle for
-- groups, which is why RC9's independent Aura Options vs Aura Style copy was
-- unreachable.
local UNIT_COPY_SCOPE = Map({
    basics = BOOL, text = BOOL, portrait = BOOL, power = BOOL, castbar = BOOL,
    status = BOOL, load = BOOL, transparency = BOOL, layout = BOOL,
    auras = BOOL, aurastyle = BOOL, texlayer = BOOL,
})
local GROUP_COPY_SCOPE = Map({
    general = BOOL, health = BOOL, dispel = BOOL, text = BOOL, font = BOOL, range = BOOL,
    indicators = BOOL, auras = BOOL, aurastyle = BOOL, highlight = BOOL, dstripe = BOOL, features = BOOL,
})
local COPY_CATEGORY = Enum({
    "basics", "text", "portrait", "power", "castbar", "status", "load", "transparency", "layout",
    "auras", "aurastyle", "texlayer",
    "general", "health", "dispel", "font", "range", "indicators", "highlight", "dstripe", "features",
})
local UNIT_COPY_CATEGORY = Enum({
    "basics", "text", "portrait", "power", "castbar", "status", "load", "transparency", "layout",
    "auras", "aurastyle", "texlayer",
})
local GROUP_COPY_CATEGORY = Enum({
    "general", "health", "dispel", "text", "font", "range", "indicators", "auras", "highlight", "dstripe", "features",
})
local SELECTOR_KIND = Enum({ "power", "classPower" }, {
    classpower = "classPower", classresource = "classPower", cp = "classPower",
})
local SELECTOR_NAME = Enum({
    "unit_text", "group_text", "unit_text_move_together", "group_text_move_together",
    "unit_status", "group_status", "group_spell", "group_corner", "color_token",
    "profile_staging", "class_power_style_tab", "bars_highlight_tab", "unit_copy_scope", "group_copy_scope",
})
local SELECTOR_TAB = Enum({
    "name", "hp", "power", "basic", "advanced", "resources", "text", "opacity", "pips", "modes", "preview", "priority",
}, {
    health = "hp", healthtext = "hp", mana = "power", manatext = "power", powertext = "power",
    nametext = "name", texture = "resources", textures = "resources", alpha = "opacity",
    transparency = "opacity", pip = "pips", separators = "pips", mode = "modes", test = "preview",
    priorities = "priority", order = "priority",
})
local TEXT_SELECTOR_TAB = Enum({ "name", "hp", "power" }, {
    health = "hp", healthtext = "hp", mana = "power", manatext = "power",
    powertext = "power", nametext = "name",
})
local STATUS_SELECTOR_TAB = Enum({ "basic", "advanced" })
local CLASS_POWER_STYLE_TAB = Enum({ "resources", "text", "opacity", "pips" }, {
    texture = "resources", textures = "resources", alpha = "opacity", transparency = "opacity",
    pip = "pips", separators = "pips",
})
local BARS_HIGHLIGHT_TAB = Enum({ "modes", "preview", "priority" }, {
    mode = "modes", test = "preview", priorities = "priority", order = "priority",
})
local SELECTOR_SLOT = Enum({ "left", "center", "right", "TL", "TR", "BL", "BR", "C" }, {
    centre = "center", middle = "center", ["top left"] = "TL", ["top right"] = "TR",
    ["bottom left"] = "BL", ["bottom right"] = "BR",
})
local SELECTOR_COMMAND = Enum({ "all", "none", "clear", "only", "selectall", "selectnone" }, {
    ["select all"] = "selectall", ["select none"] = "selectnone",
})
local SELECTOR_FIELD = Enum({
    "profileExportKind", "profileImportCreateNew", "profileCreateCopyName", "profileImportNewName", "profileString",
}, {
    exportkind = "profileExportKind", exporttype = "profileExportKind",
    importcreatenew = "profileImportCreateNew", importnewprofile = "profileImportCreateNew",
    createname = "profileCreateCopyName", copyname = "profileCreateCopyName", profilename = "profileCreateCopyName",
    importnewname = "profileImportNewName", newprofilename = "profileImportNewName",
    profileimportstring = "profileString", importstring = "profileString",
})
local SELECTOR_TOKEN_VALUES = CopyArray(POWER_TOKENS)
for i = 1, #CLASS_POWER_BASE_TOKENS do SELECTOR_TOKEN_VALUES[#SELECTOR_TOKEN_VALUES + 1] = CLASS_POWER_BASE_TOKENS[i] end
local SELECTOR_TOKEN = TokenEnum(SELECTOR_TOKEN_VALUES)

local function FieldSet(words)
    local out = {}
    for _, field in ipairs(WordList(words)) do out[field] = true end
    return out
end

local function Define(keys, contract)
    contract.source = CONTRACT_SOURCE
    for key in tostring(keys or ""):gmatch("%S+") do
        if Contracts[key] then
            CatalogErrors[#CatalogErrors + 1] = "duplicate action input contract: " .. key
        else
            Contracts[key] = contract
        end
    end
end

local function DefineNone(keys)
    Define(keys, { kind = "none", fields = {} })
end

local function DefineObject(keys, fields, opts)
    opts = opts or {}
    Define(keys, {
        kind = "object",
        fields = fields,
        required = CopyArray(opts.required),
        requireAny = opts.requireAny,
        allOrNone = opts.allOrNone,
        discriminator = opts.discriminator,
        variants = opts.variants,
        dependentTypes = opts.dependentTypes,
    })
end

DefineNone([[
assistant.action.editMode.anchorPicker assistant.action.editMode.cancel assistant.action.editMode.exit
assistant.action.editMode.redo assistant.action.editMode.resetPosition assistant.action.editMode.undo
assistant.action.history.redo assistant.action.history.undo assistant.panel.close assistant.workflow.cancel
assistant.workflow.status assistant_help assistant_nomatch_clear assistant_nomatch_telemetry assistant_status
cancel_custom_anchor_picker class_power_quick_setup clear_broken_spec_profile_mappings copy_wago_profiles_link
custom_anchor_picker_status dashboard.globalUiScale.apply dashboard.globalUiScale.disable
dashboard.globalUiScale.revertPending dashboard.menuScale.apply dashboard.menuScale.revertPending
dashboard.msufFrameScale.apply dashboard.msufFrameScale.revertPending dashboard_page_back dashboard_page_forward
diagnose_class_power_status diagnose_dashboard_setup diagnose_profile_status factory_reset_all
first_load.full_settings first_load.import_profile first_load.not_now first_load.personalize
first_load.use_defaults first_load.whats_new guided_setup restart_upgrade_highlight_tour menu_history_redo menu_history_reset_session
menu_history_undo menu_reset_current_page_prompt menu_search_clear menu_window_close menu_window_maximize
menu_window_minimize menu_window_restore open_profile_import open_recovery_tools preview_player_totems
profile_summary recover_frames
reset_all_scoped_global_bars_overrides reset_all_scoped_global_font_overrides reset_all_unit_positions
reset_aura_colors reset_bar_background_color reset_bar_colors reset_bar_gradient_colors reset_castbar_colors reset_class_colors
reset_class_power_combo_slot_colors reset_focus_kick_position reset_gameplay_colors reset_global_font_color
reset_health_gradient_colors reset_npc_type_colors reset_player_totems_layout reset_portrait_colors
reset_profile reset_resource_colors reset_unitframe_colors support_links_summary
enable_focus_target_frame show_player_power_or_open_class_resources
reset_selected_group_status_icon
]])

DefineObject("apply_global_scale_preset", { preset = GLOBAL_SCALE_PRESET }, { required = { "preset" } })

DefineObject([[
assistant.action.editMode.auras assistant.action.editMode.bossPreview assistant.action.editMode.cdm
assistant.action.editMode.grid assistant.action.editMode.preview assistant.action.editMode.snap
class_power_preview_animate toggle_absorb_bar_test
]], { value = BOOL })
DefineObject("assistant.action.editMode.backgroundOpacity", { value = Number(0, 1) }, { required = { "value" } })
DefineObject("assistant.action.editMode.gridStep", { value = Integer(8, 64) }, { required = { "value" } })
DefineObject("assistant.action.editMode.enter assistant.action.editMode.toggle", { unit = EDIT_UNIT })
DefineObject("assistant.action.editMode.groupPreview", { scope = GROUP_SCOPE, value = BOOL })
DefineObject("assistant.diagnostic.editMode.status", { reason = SHORT_TEXT })

DefineObject("assistant_nomatch_worklist", {
    owner = SHORT_TEXT, ownerFilter = SHORT_TEXT, resolution = SHORT_TEXT, resolutionFilter = SHORT_TEXT,
    priority = SHORT_TEXT, priorityFilter = SHORT_TEXT, tag = SHORT_TEXT, tagFilter = SHORT_TEXT,
})
DefineObject("assistant_scope_help", {
    frameType = IDENTIFIER, unit = UNIT_FRAME, group = GROUP_SCOPE, page = IDENTIFIER, label = SHORT_TEXT,
})
DefineObject("guided_setup_step", { step = GUIDED_STEP })

DefineObject("aura_blacklist_add_spell aura_blacklist_remove_spell", {
    scope = AURA_UNIT_INPUT_SCOPE, lane = AURA_LANE, value = SPELL_TEXT,
}, { required = { "scope", "value" } })
DefineObject("aura_blacklist_clear_spells aura_blacklist_summary", {
    scope = AURA_UNIT_INPUT_SCOPE, lane = AURA_LANE,
}, { required = { "scope" } })
DefineObject("aura_blacklist_add_preset", {
    scope = AURA_UNIT_INPUT_SCOPE, lane = AURA_LANE, preset = BLACKLIST_PRESET,
}, { required = { "scope", "preset" } })
DefineObject("aura_custom_whitelist_add_spell aura_custom_whitelist_remove_spell", {
    scope = AURA_UNIT_INPUT_SCOPE, index = Integer(1, 4), value = SPELL_VALUE,
}, { required = { "scope", "index", "value" } })
DefineObject("aura_custom_whitelist_clear_spells aura_custom_whitelist_summary", {
    scope = AURA_UNIT_INPUT_SCOPE, index = Integer(1, 4),
}, { required = { "scope", "index" } })
DefineObject("reset_aura_custom_container", {
    scope = AURA_CUSTOM_CONTAINER_SCOPE, index = Integer(1, 3),
}, { required = { "scope", "index" } })

DefineObject("aura_group_blacklist_add_spell aura_group_blacklist_remove_spell", {
    scope = GROUP_AURA_SCOPE, lane = GROUP_AURA_LANE, value = SPELL_TEXT,
}, { required = { "value" } })
DefineObject("aura_group_blacklist_clear_spells aura_group_blacklist_summary", {
    scope = GROUP_AURA_SCOPE, lane = GROUP_AURA_LANE,
})
DefineObject("aura_group_blacklist_add_preset", {
    scope = GROUP_AURA_SCOPE, lane = GROUP_AURA_LANE, preset = BLACKLIST_PRESET,
}, { required = { "preset" } })
DefineObject("aura_group_category_blacklist_set", {
    scope = GROUP_AURA_SCOPE, lane = GROUP_AURA_LANE, category = GROUP_AURA_CATEGORY, value = BOOL,
}, { required = { "category", "value" } })
DefineObject("aura_group_category_blacklist_clear aura_group_category_blacklist_summary", {
    scope = GROUP_AURA_SCOPE, lane = GROUP_AURA_LANE,
})
DefineObject("clear_group_custom_anchor reset_group_corner_indicators reset_group_status_icons", { scope = GROUP_SCOPE })
DefineObject("clear_unit_custom_anchor reset_unit_page reset_unit_position", { unit = UNIT_FRAME }, { required = { "unit" } })
DefineObject("copy_group", {
    source = GROUP_SCOPE, target = GROUP_SCOPE, targets = Array(GROUP_SCOPE, 1, 3, true), scopes = GROUP_COPY_SCOPE,
}, { requireAny = { { "target", "targets" } } })
DefineObject("copy_unit", {
    source = UNIT_FRAME, targets = Array(UNIT_FRAME, 1, 7, true), scopes = UNIT_COPY_SCOPE,
}, { required = { "source", "targets" } })

DefineObject("copy_profile delete_profile switch_profile", { name = NAME }, { required = { "name" } })
DefineObject("create_profile", { name = NAME, switch = BOOL }, { required = { "name" } })
DefineObject("copy_profile_from_to", {
    source = NAME, destination = NAME, name = NAME,
}, { required = { "source" }, requireAny = { { "destination", "name" } } })
DefineObject("rename_profile", {
    source = NAME, destination = NAME, name = NAME,
}, { requireAny = { { "destination", "name" } } })
DefineObject("start_profile_copy_flow start_profile_rename_flow", { source = NAME })
DefineObject("clear_spec_profile", { spec = SPEC_VALUE }, { required = { "spec" } })
DefineObject("set_spec_profile", { spec = SPEC_VALUE, name = NAME }, { required = { "spec", "name" } })
-- "None" clears the choice, so the name is required but may be the sentinel.
DefineObject("set_new_character_profile", { name = NAME }, { required = { "name" } })
DefineObject("export_profile", { kind = PROFILE_EXPORT_KIND })
DefineObject("import_profile_string import_legacy_profile_string", {
    value = IMPORT_TEXT,
}, { required = { "value" } })
DefineObject("import_profile_string_new", {
    value = IMPORT_TEXT, name = NAME,
}, { required = { "value", "name" } })

DefineObject("copy_support_link", { link = SUPPORT_LINK }, { required = { "link" } })
DefineObject("diagnose_castbar_visibility", { unit = CASTBAR_UNIT })
DefineObject("diagnose_unit_visibility", { unit = UNIT_FRAME })
DefineObject("diagnose_group_visibility", { scope = GROUP_SCOPE })
DefineObject("diagnose_aura_visibility", { scope = AURA_DIAGNOSTIC_SCOPE, lane = AURA_LANE })
DefineObject("diagnose_gameplay_helpers", { feature = GAMEPLAY_FEATURE })

DefineObject("menu_search_query", {
    query = NONEMPTY, text = NONEMPTY, value = NONEMPTY,
}, { requireAny = { { "query", "text", "value" } } })
DefineObject("open_dashboard_panel", { panel = DASHBOARD_PANEL }, { required = { "panel" } })
DefineObject("set_dashboard_panel", { panel = DASHBOARD_PANEL, open = BOOL }, { required = { "panel" } })
DefineObject("set_nav_section", { section = NAV_SECTION, open = BOOL }, { required = { "section" } })
DefineObject("set_nav_search_intro", { command = SEARCH_INTRO_COMMAND })
DefineObject("open_page", {
    page = IDENTIFIER, anchor = SHORT_TEXT, query = SHORT_TEXT, label = SHORT_TEXT,
    settingKey = IDENTIFIER, scope = AURA_ROUTE_SCOPE, lane = AURA_LANE,
}, { required = { "page" } })
DefineObject("open_setting_control", {
    settingKey = IDENTIFIER, label = SHORT_TEXT, page = IDENTIFIER,
}, { required = { "settingKey" } })

DefineObject("preview_castbar", {
    unit = CASTBAR_UNIT, kind = CASTBAR_TYPE, castType = CASTBAR_TYPE, interrupt = BOOL,
})
DefineObject("set_castbar_test_mode", { unit = CASTBAR_UNIT, value = BOOL })
DefineObject("preview_group_status_icon", { scope = GROUP_SCOPE, icon = GROUP_STATUS_ICON, mode = PREVIEW_MODE, text = SHORT_TEXT })
DefineObject("reset_group_status_icon", { icon = GROUP_STATUS_ICON, scope = GROUP_SCOPE }, { required = { "icon" } })
DefineObject("preview_unit_status_indicator", {
    unit = UNIT_FRAME, status = SHORT_TEXT, text = SHORT_TEXT, mode = PREVIEW_MODE,
})
DefineObject("reset_unit_status_indicator", {
    unit = UNIT_FRAME, status = SHORT_TEXT, text = SHORT_TEXT,
}, { required = { "unit" }, requireAny = { { "status", "text" } } })

local SPELL_ACTION_TARGET_FIELDS = {
    scope = GROUP_SCOPE, spec = SPEC_VALUE, aura = NONEMPTY, text = NONEMPTY,
}
DefineObject("reset_group_spell_indicator_aura", SPELL_ACTION_TARGET_FIELDS, {
    requireAny = { { "spec", "text" }, { "aura", "text" } },
})
DefineObject("set_group_spell_indicator_aura", {
    scope = GROUP_SCOPE, spec = SPEC_VALUE, aura = NONEMPTY, text = NONEMPTY,
    field = Enum({
        "enabled", "onlyOwn", "placedType", "placedAnchor", "placedSize", "placedX", "placedY",
        "placedBarWidth", "placedGrowth", "placedMissing", "placedCooldownSwipe", "placedCooldown",
        "placedCooldownSize", "placedBarSmoothFill", "placedBarShowTimer", "placedBarTimerAnchor",
        "placedBarTimerX", "placedBarTimerY", "frameType", "framePriority", "frameAlpha", "frameThickness", "frameColor",
    }),
    value = DYNAMIC_SCALAR,
}, {
    required = { "field", "value" },
    requireAny = { { "spec", "text" }, { "aura", "text" } },
    dependentTypes = {
        value = {
            by = "field",
            values = {
                enabled = BOOL,
                onlyOwn = BOOL,
                placedType = SPELL_PLACED_TYPE,
                placedAnchor = SPELL_PLACED_ANCHOR,
                placedSize = Integer(6, 48),
                placedX = Integer(-100, 100),
                placedY = Integer(-100, 100),
                placedBarWidth = Integer(8, 120),
                placedGrowth = SPELL_PLACED_GROWTH,
                placedMissing = BOOL,
                placedCooldownSwipe = BOOL,
                placedCooldown = BOOL,
                placedCooldownSize = Integer(6, 24),
                placedBarSmoothFill = BOOL,
                placedBarShowTimer = BOOL,
                placedBarTimerAnchor = SPELL_PLACED_ANCHOR,
                placedBarTimerX = Integer(-100, 100),
                placedBarTimerY = Integer(-100, 100),
                frameType = SPELL_FRAME_TYPE,
                framePriority = Integer(1, 10),
                frameAlpha = Number(0, 1),
                frameThickness = Integer(1, 8),
                frameColor = Color(),
            },
        },
    },
})
DefineObject("set_group_spell_indicator_multi_spec", {
    scope = GROUP_SCOPE, spec = SPEC_VALUE, value = BOOL,
}, { required = { "spec", "value" } })
DefineObject("move_group_spell_indicator_order", {
    scope = GROUP_SCOPE, spec = SPEC_VALUE, aura = NONEMPTY, text = NONEMPTY, position = Integer(1),
}, {
    required = { "position" },
    requireAny = { { "spec", "text" }, { "aura", "text" } },
})
DefineObject("reset_group_corner_indicator_slot", {
    scope = GROUP_SCOPE, slot = CORNER_SLOT,
}, { required = { "slot" } })

DefineObject("set_crosshair_melee_spell", { value = SPELL_VALUE }, { required = { "value" } })
DefineObject("reset_scoped_global_bars_override reset_scoped_global_font_override", {
    scope = GLOBAL_SCOPE,
}, { required = { "scope" } })
DefineObject("toggle_highlight_border_test", { kind = BORDER_TEST_KIND, value = BOOL })
DefineObject("reset_power_color_token", { token = POWER_TOKEN }, { required = { "token" } })
DefineObject("reset_class_power_color_token", {
    token = CLASS_POWER_COLOR_TOKEN, background = BOOL,
}, { required = { "token" } })
DefineObject("reset_class_power_slot_colors", {
    resourceToken = CLASS_POWER_RESOURCE_TOKEN,
}, { required = { "resourceToken" } })
DefineObject("reset_class_power_full_color", {
    resourceToken = CLASS_POWER_RESOURCE_TOKEN,
}, { required = { "resourceToken" } })
DefineObject("set_global_font_color", {
    r = Number(0, 1), g = Number(0, 1), b = Number(0, 1), color = NONEMPTY, label = SHORT_TEXT,
}, {
    requireAny = { { "color", "r" } },
    allOrNone = { { "r", "g", "b" } },
})

DefineObject("start_group_custom_anchor_picker", { scope = GROUP_SCOPE }, { required = { "scope" } })
DefineObject("start_unit_custom_anchor_picker", { unit = UNIT_FRAME }, { required = { "unit" } })

DefineObject("set_menu_selector_state", {
    selector = SELECTOR_NAME,
    unit = UNIT_FRAME,
    scope = GROUP_SCOPE,
    tab = SELECTOR_TAB,
    slot = SELECTOR_SLOT,
    status = SHORT_TEXT,
    text = SHORT_TEXT,
    icon = GROUP_STATUS_ICON,
    spec = SPEC_VALUE,
    aura = NONEMPTY,
    kind = OneOf(SELECTOR_KIND, PROFILE_EXPORT_KIND),
    token = SELECTOR_TOKEN,
    field = SELECTOR_FIELD,
    value = SELECTOR_VALUE,
    command = SELECTOR_COMMAND,
    category = COPY_CATEGORY,
    categories = Array(COPY_CATEGORY, 1, 19, true),
}, {
    required = { "selector" },
    discriminator = "selector",
    variants = {
        unit_text = {
            fields = FieldSet("selector unit tab slot"), required = { "unit", "tab" },
            fieldTypes = { tab = TEXT_SELECTOR_TAB, slot = Enum({ "left", "center", "right" }) },
        },
        group_text = {
            fields = FieldSet("selector scope tab slot"), required = { "tab" },
            fieldTypes = { tab = TEXT_SELECTOR_TAB, slot = Enum({ "left", "center", "right" }) },
        },
        unit_text_move_together = {
            fields = FieldSet("selector unit tab value"), required = { "unit", "tab" },
            fieldTypes = { tab = Enum({ "hp", "power" }, { health = "hp", mana = "power" }), value = BOOL },
        },
        group_text_move_together = {
            fields = FieldSet("selector scope tab value"), required = { "tab" },
            fieldTypes = { tab = Enum({ "hp", "power" }, { health = "hp", mana = "power" }), value = BOOL },
        },
        unit_status = {
            fields = FieldSet("selector unit tab status text"), required = { "unit" },
            requireAny = { { "tab", "status", "text" } }, fieldTypes = { tab = STATUS_SELECTOR_TAB },
        },
        group_status = {
            fields = FieldSet("selector scope tab icon text"),
            requireAny = { { "tab", "icon", "text" } }, fieldTypes = { tab = STATUS_SELECTOR_TAB },
        },
        group_spell = {
            fields = FieldSet("selector scope spec aura text"), requireAny = { { "spec", "aura", "text" } },
        },
        group_corner = {
            fields = FieldSet("selector scope slot text"), requireAny = { { "slot", "text" } },
            fieldTypes = { slot = CORNER_SLOT },
        },
        color_token = {
            fields = FieldSet("selector kind token"), required = { "token" },
            fieldTypes = { kind = SELECTOR_KIND },
            dependentTypes = {
                token = { by = "kind", default = POWER_TOKEN, values = { power = POWER_TOKEN, classPower = CLASS_POWER_COLOR_TOKEN } },
            },
        },
        profile_staging = {
            fields = FieldSet("selector field kind value"), required = { "field" },
            fieldTypes = { kind = PROFILE_EXPORT_KIND },
            dependentTypes = {
                value = {
                    by = "field",
                    values = {
                        profileImportCreateNew = BOOL,
                        profileCreateCopyName = NAME,
                        profileImportNewName = NAME,
                        profileString = DYNAMIC_TEXT,
                    },
                },
            },
        },
        class_power_style_tab = {
            fields = FieldSet("selector tab"), required = { "tab" }, fieldTypes = { tab = CLASS_POWER_STYLE_TAB },
        },
        bars_highlight_tab = {
            fields = FieldSet("selector tab"), required = { "tab" }, fieldTypes = { tab = BARS_HIGHLIGHT_TAB },
        },
        unit_copy_scope = {
            fields = FieldSet("selector unit command category categories value"),
            requireAny = { { "command", "category" } },
            fieldTypes = {
                category = UNIT_COPY_CATEGORY, categories = Array(UNIT_COPY_CATEGORY, 1, 9, true), value = BOOL,
            },
        },
        group_copy_scope = {
            fields = FieldSet("selector command category categories value"),
            requireAny = { { "command", "category" } },
            fieldTypes = {
                category = GROUP_COPY_CATEGORY, categories = Array(GROUP_COPY_CATEGORY, 1, 11, true), value = BOOL,
            },
        },
    },
})

local function IsFiniteNumber(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function NormalizeBoolean(value)
    if type(value) == "boolean" then return value end
    if value == 1 then return true end
    if value == 0 then return false end
    if type(value) == "string" then
        local token = Trim(value):lower()
        if token == "true" or token == "on" or token == "yes" or token == "enabled" or token == "enable" or token == "1" then return true end
        if token == "false" or token == "off" or token == "no" or token == "disabled" or token == "disable" or token == "0" then return false end
    end
    return nil, "must be a boolean"
end

local function NormalizeNumber(descriptor, value, integer)
    if type(value) == "string" then
        local text = Trim(value)
        if text == "" then return nil, "must be a finite number" end
        value = tonumber(text)
    end
    if not IsFiniteNumber(value) then return nil, "must be a finite number" end
    if integer and value ~= math.floor(value) then return nil, "must be an integer" end
    if descriptor.min ~= nil and value < descriptor.min then return nil, "must be at least " .. tostring(descriptor.min) end
    if descriptor.max ~= nil and value > descriptor.max then return nil, "must be at most " .. tostring(descriptor.max) end
    return value
end

local NormalizeValue

local function NormalizeColor(value, path)
    if type(value) ~= "table" or getmetatable(value) ~= nil then return nil, path .. " must be an RGB/RGBA color object" end
    local keyed = value.r ~= nil or value.g ~= nil or value.b ~= nil or value.a ~= nil
    local positional = value[1] ~= nil or value[2] ~= nil or value[3] ~= nil or value[4] ~= nil
    if keyed and positional then return nil, path .. " cannot mix keyed and positional color components" end
    local allowed = keyed and { r = true, g = true, b = true, a = true, label = true }
        or { [1] = true, [2] = true, [3] = true, [4] = true }
    for key in pairs(value) do
        if not allowed[key] then return nil, path .. " has unknown color component " .. tostring(key) end
    end
    local r, g, b, a
    if keyed then r, g, b, a = value.r, value.g, value.b, value.a else r, g, b, a = value[1], value[2], value[3], value[4] end
    if r == nil or g == nil or b == nil then return nil, path .. " requires r, g, and b" end
    local component = Number(0, 1)
    local nr, er = NormalizeNumber(component, r, false)
    if nr == nil then return nil, path .. ".r " .. er end
    local ng, eg = NormalizeNumber(component, g, false)
    if ng == nil then return nil, path .. ".g " .. eg end
    local nb, eb = NormalizeNumber(component, b, false)
    if nb == nil then return nil, path .. ".b " .. eb end
    local out = { r = nr, g = ng, b = nb }
    if a ~= nil then
        local na, ea = NormalizeNumber(component, a, false)
        if na == nil then return nil, path .. ".a " .. ea end
        out.a = na
    end
    if keyed and value.label ~= nil then
        if type(value.label) ~= "string" or #value.label > 128 then return nil, path .. ".label must be a short string" end
        out.label = value.label
    end
    return out
end

local function DenseArrayLength(value)
    local count, max = 0, 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then return nil end
        count = count + 1
        if key > max then max = key end
    end
    if count ~= max then return nil end
    return max
end

NormalizeValue = function(descriptor, value, path)
    local kind = descriptor and descriptor.type
    if kind == "boolean" then
        local normalized, err = NormalizeBoolean(value)
        if normalized == nil then return nil, path .. " " .. err end
        return normalized
    end
    if kind == "number" or kind == "integer" then
        local normalized, err = NormalizeNumber(descriptor, value, kind == "integer")
        if normalized == nil then return nil, path .. " " .. err end
        return normalized
    end
    if kind == "string" then
        if type(value) ~= "string" then return nil, path .. " must be a string" end
        local normalized = descriptor.trim == false and value or Trim(value)
        if descriptor.minLength ~= nil and #normalized < descriptor.minLength then return nil, path .. " is too short" end
        if descriptor.maxLength ~= nil and #normalized > descriptor.maxLength then return nil, path .. " is too long" end
        if descriptor.pattern and not normalized:match(descriptor.pattern) then return nil, path .. " has an invalid format" end
        return normalized
    end
    if kind == "enum" then
        if type(value) ~= "string" and type(value) ~= "number" then return nil, path .. " must be one of the allowed values" end
        local normalized = descriptor._lookup[Trim(value):lower()]
        if normalized == nil then return nil, path .. " is not an allowed value" end
        return normalized
    end
    if kind == "array" then
        if type(value) ~= "table" or getmetatable(value) ~= nil then return nil, path .. " must be an array" end
        local length = DenseArrayLength(value)
        if length == nil then return nil, path .. " must be a dense array" end
        if descriptor.minItems and length < descriptor.minItems then return nil, path .. " has too few items" end
        if descriptor.maxItems and length > descriptor.maxItems then return nil, path .. " has too many items" end
        local out, seen = {}, {}
        for i = 1, length do
            local normalized, err = NormalizeValue(descriptor.items, value[i], path .. "[" .. tostring(i) .. "]")
            if normalized == nil then return nil, err end
            if descriptor.unique then
                local identity = type(normalized) .. ":" .. tostring(normalized)
                if seen[identity] then return nil, path .. " contains a duplicate item" end
                seen[identity] = true
            end
            out[i] = normalized
        end
        return out
    end
    if kind == "map" then
        if type(value) ~= "table" or getmetatable(value) ~= nil then return nil, path .. " must be an object" end
        local out = {}
        for key, item in pairs(value) do
            local field = type(key) == "string" and descriptor.fields[key] or nil
            if not field then return nil, path .. " has unknown field " .. tostring(key) end
            local normalized, err = NormalizeValue(field, item, path .. "." .. key)
            if normalized == nil then return nil, err end
            out[key] = normalized
        end
        return out
    end
    if kind == "color" then return NormalizeColor(value, path) end
    if kind == "oneOf" then
        for i = 1, #(descriptor.choices or {}) do
            local normalized = NormalizeValue(descriptor.choices[i], value, path)
            if normalized ~= nil then return normalized end
        end
        return nil, path .. " has the wrong type"
    end
    return nil, path .. " has no deterministic type contract"
end

local function ApplyFieldTypes(spec, raw, out, key)
    for field, descriptor in pairs(spec and spec.fieldTypes or {}) do
        if raw[field] ~= nil then
            local normalized, err = NormalizeValue(descriptor, raw[field], tostring(key) .. "." .. tostring(field))
            if normalized == nil then return nil, err end
            out[field] = normalized
        end
    end
    for field, dependency in pairs(spec and spec.dependentTypes or {}) do
        if raw[field] ~= nil then
            local byValue = out[dependency.by]
            local descriptor = dependency.values and dependency.values[byValue] or nil
            descriptor = descriptor or dependency.default
            if descriptor then
                local normalized, err = NormalizeValue(descriptor, raw[field], tostring(key) .. "." .. tostring(field))
                if normalized == nil then return nil, err end
                out[field] = normalized
            end
        end
    end
    return true
end

local function RequireContractFields(spec, out, key)
    for i = 1, #(spec and spec.required or {}) do
        local field = spec.required[i]
        if out[field] == nil then return nil, "action " .. tostring(key) .. " requires input field " .. tostring(field) end
    end
    for i = 1, #(spec and spec.requireAny or {}) do
        local group, found = spec.requireAny[i], false
        for j = 1, #(group or {}) do if out[group[j]] ~= nil then found = true; break end end
        if not found then return nil, "action " .. tostring(key) .. " requires one of: " .. table.concat(group or {}, ", ") end
    end
    for i = 1, #(spec and spec.allOrNone or {}) do
        local group, present = spec.allOrNone[i], 0
        for j = 1, #(group or {}) do if out[group[j]] ~= nil then present = present + 1 end end
        if present > 0 and present < #(group or {}) then
            return nil, "action " .. tostring(key) .. " requires all or none of: " .. table.concat(group or {}, ", ")
        end
    end
    return true
end

local function ContractFor(actionOrKey)
    if type(actionOrKey) == "table" then
        actionOrKey = actionOrKey.key
    end
    local key = tostring(actionOrKey or "")
    return Contracts[key], key
end

function Inputs.GetContract(actionOrKey)
    local contract = ContractFor(actionOrKey)
    return contract
end

function Inputs.Normalize(actionOrKey, args)
    local contract, key = ContractFor(actionOrKey)
    if type(contract) ~= "table" then return nil, "missing explicit action input contract: " .. tostring(key) end
    if args == nil then args = {} end
    if type(args) ~= "table" or getmetatable(args) ~= nil then return nil, "action input for " .. tostring(key) .. " must be a plain object" end
    if contract.kind == "none" then
        if next(args) ~= nil then return nil, "action " .. tostring(key) .. " does not accept input fields" end
        return {}
    end
    if contract.kind ~= "object" or type(contract.fields) ~= "table" then
        return nil, "invalid action input contract for " .. tostring(key)
    end

    local out = {}
    for field, value in pairs(args) do
        local descriptor = type(field) == "string" and contract.fields[field] or nil
        if not descriptor then return nil, "action " .. tostring(key) .. " has unknown input field " .. tostring(field) end
        local normalized, err = NormalizeValue(descriptor, value, tostring(key) .. "." .. field)
        if normalized == nil then return nil, err end
        out[field] = normalized
    end

    local typed, typedErr = ApplyFieldTypes(contract, args, out, key)
    if not typed then return nil, typedErr end
    local valid, validationErr = RequireContractFields(contract, out, key)
    if not valid then return nil, validationErr end

    local variant
    if contract.discriminator ~= nil then
        variant = contract.variants and contract.variants[out[contract.discriminator]] or nil
        if type(variant) ~= "table" then return nil, "action " .. tostring(key) .. " has no input variant for " .. tostring(out[contract.discriminator]) end
        for field in pairs(args) do
            if not (variant.fields and variant.fields[field]) then
                return nil, "action " .. tostring(key) .. " input variant " .. tostring(out[contract.discriminator])
                    .. " does not accept field " .. tostring(field)
            end
        end
        typed, typedErr = ApplyFieldTypes(variant, args, out, key)
        if not typed then return nil, typedErr end
        local validVariant, variantErr = RequireContractFields(variant, out, key)
        if not validVariant then return nil, variantErr end
    end

    return out
end

Inputs.NormalizeActionInput = Inputs.Normalize
A.NormalizeAssistantActionInput = Inputs.Normalize
