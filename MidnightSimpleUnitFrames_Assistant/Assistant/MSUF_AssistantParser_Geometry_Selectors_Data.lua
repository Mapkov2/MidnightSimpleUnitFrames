-- Assistant geometry selector parser data.
-- Literal phrases live here so parser logic stays focused on selector behavior.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Data = A.ParserData or {}
A.ParserData = Data

Data.GEOMETRY_SELECTOR_TERMS = {
    MENU_SELECTOR_VERBS = {
        "select", "choose", "pick", "open", "show", "switch to", "go to", "edit",
    },

    MENU_SELECTOR_GATE_TERMS = {
        "select", "choose", "pick", "open", "show", "switch", "edit", "tab",
        "slot", "selector", "dropdown", "status", "indicator", "text", "put",
        "place", "align", "anchor", "class power", "class resource", "highlight",
        "copy", "category", "categories", "scope", "scopes",
    },

    TEXT_MOVE_SEPARATE_TERMS = { "individual", "separate", "separately", "each" },
    TEXT_MOVE_TEXT_TERMS = { "hp text", "health text", "power text", "mana text" },
    TEXT_MOVE_UNIT_TERMS = { "unit", "units", "slot", "slots", "text unit", "text units", "text slot", "text slots" },
    TEXT_MOVE_INTENT_TERMS = {
        "move text as one group", "move as one group", "text as one group",
        "move text together", "text move together", "move together",
        "move text per slot", "text per slot", "per slot", "selected slot mode",
        "individual slot", "individual slots", "separate slot", "separate slots",
        "move text separately", "text separately", "individual text unit", "individual text units",
        "separate text unit", "separate text units", "move individual text", "move each text",
    },
    TEXT_MOVE_SEPARATE_SLOT_TERMS = {
        "per slot", "selected slot mode", "individual slot", "individual slots",
        "separate slot", "separate slots", "separately", "text separately",
        "individual text unit", "individual text units", "separate text unit", "separate text units",
        "move individual text", "move each text",
    },

    NATURAL_TEXT_SELECTOR_ACTION_TERMS = { "put", "place", "align", "anchor", "anchoring" },
    NATURAL_TEXT_SELECTOR_REJECT_TERMS = {
        "move", "nudge", "shift", "offset", "position", "pos", "x", "y", "up", "down",
        "size", "font size", "layer", "current", "percent", "percentage", "max", "maximum",
        "deficit", "missing", "hide", "clear", "remove", "none", "off",
    },
    TEXT_LEFT_TERMS = { "left", "links" },
    TEXT_CENTER_TERMS = { "center", "centre", "middle", "mitte" },
    TEXT_RIGHT_TERMS = { "right", "rechts" },

    STATUS_ADVANCED_TAB_TERMS = {
        "advanced status tab", "advanced status icon tab", "advanced indicator tab",
        "advanced status controls", "advanced status",
    },
    STATUS_BASIC_TAB_TERMS = {
        "basic status tab", "basic status icon tab", "basic indicator tab",
        "basic status controls", "basic status",
    },
    STATUS_SELECTOR_INTENT_TERMS = {
        "status tab", "status icon tab", "status indicator tab", "indicator tab",
        "status selector", "status dropdown", "indicator selector", "indicator dropdown",
        "status controls", "status icon controls", "selected indicator",
    },
    STATUS_SELECTOR_FALLBACK_TERMS = { "indicator", "status icon" },

    CLASS_POWER_STYLE_RESOURCES_TERMS = {
        "textures tab", "texture tab", "resources tab", "resource tab", "style textures", "style resources",
    },
    CLASS_POWER_STYLE_TEXT_TERMS = {
        "text tab", "style text", "class power text tab", "class resource text tab",
    },
    CLASS_POWER_STYLE_OPACITY_TERMS = {
        "opacity tab", "alpha tab", "transparency tab", "style opacity", "style alpha",
    },
    CLASS_POWER_STYLE_PIPS_TERMS = {
        "pips tab", "pip tab", "separator tab", "separators tab", "style pips",
    },
    CLASS_POWER_STYLE_INTENT_TERMS = {
        "class power style", "class resource style", "class resources style", "class power style tab",
        "class resource style tab", "class resources style area", "class power style area",
    },

    BARS_HIGHLIGHT_MODES_TERMS = { "modes tab", "mode tab", "border modes", "highlight modes", "highlight mode" },
    BARS_HIGHLIGHT_PREVIEW_TERMS = { "preview tab", "test tab", "highlight preview", "highlight test" },
    BARS_HIGHLIGHT_PRIORITY_TERMS = { "priority tab", "priorities tab", "priority order", "order tab", "highlight priority" },
    BARS_HIGHLIGHT_INTENT_TERMS = {
        "highlight borders tab", "highlight border tab", "highlight borders", "bar highlight tab",
        "bars highlight tab", "highlight area", "highlight border area",
        "highlight modes", "highlight mode", "highlight preview", "highlight test", "highlight priority",
    },

    GROUP_TEXT_TERMS = { "group text", "group health and text", "party text", "raid text", "mythic raid text" },
    GENERIC_MENU_SELECTOR_INTENT_TERMS = {
        "select text tab", "select text slot", "text move together", "move text as one group", "move text per slot",
        "select status tab", "select status indicator", "select group status icon",
        "select spell indicator", "select corner editor slot",
        "select power color token", "select class resource color token", "select class power color token",
        "select class power style tab", "select class resource style tab", "select class resources style area",
        "select highlight borders tab", "select bars highlight tab", "select highlight area",
        "set profile staging field", "set profile string field",
        "set unit copy category", "select unit copy categories", "set group copy category", "select group copy categories",
    },

    CLASS_POWER_COLOR_TOKEN_TERMS = {
        "class power color token", "class resource color token", "class power token", "class resource token",
    },
    CLASS_POWER_COLOR_TERMS = { "class power color", "class resource color", "resource color" },
    CLASS_POWER_RESOURCE_TOKEN_TERMS = {
        "combo point", "combo points", "holy power", "soul shard", "soul shards", "chi",
        "arcane charge", "arcane charges", "runes", "essence", "maelstrom", "astral",
        "stagger", "ebon", "whirlwind", "tip of the spear", "insanity",
    },
    POWER_COLOR_TOKEN_TERMS = { "power color token", "power token", "power type", "resource type", "resource color token" },
    CLASS_POWER_REJECT_TERMS = { "class power", "class resource", "combo point", "combo points" },

    SPELL_INDICATOR_TERMS = {
        "spell indicator selector", "spell indicator dropdown", "spell indicator spec",
        "tracked spell selector", "tracked spells selector", "tracked spell",
        "multi spec entry", "multi-spec entry",
    },
    CORNER_EDITOR_TERMS = { "corner editor slot", "editor slot", "corner slot", "custom spell editor" },
    GROUP_STATUS_TERMS = { "group status", "group indicator", "party indicator", "raid indicator", "mythic raid indicator" },

    TEXT_SELECTOR_QUESTION_TERMS = {
        "select text tab", "select text slot", "text move together", "move text as one group", "move text per slot",
    },
    STATUS_SELECTOR_QUESTION_TERMS = { "select status tab", "select status indicator", "select group status icon" },
    SPELL_INDICATOR_QUESTION_TERMS = { "select spell indicator" },
    CORNER_EDITOR_QUESTION_TERMS = { "select corner editor slot", "corner editor slot", "editor slot" },
    POWER_COLOR_QUESTION_TERMS = {
        "select power color token", "select class resource color token", "select class power color token",
    },
    CLASS_POWER_STYLE_QUESTION_TERMS = {
        "select class power style tab", "select class resource style tab", "class resources style area",
    },
    BARS_HIGHLIGHT_QUESTION_TERMS = {
        "select highlight borders tab", "select bars highlight tab", "select highlight area",
    },
    PROFILE_STAGING_QUESTION_TERMS = { "set profile staging field", "set profile string field" },
    COPY_CATEGORY_QUESTION_TERMS = {
        "set unit copy category", "select unit copy categories", "set group copy category", "select group copy categories",
    },
}
