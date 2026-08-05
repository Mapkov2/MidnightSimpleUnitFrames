-- Assistant compound parser data.
-- Literal phrase lists live here so parser logic stays focused on command expansion.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Data = A.ParserData or {}
A.ParserData = Data

Data.COMPOUND_PARSER = {
    COMMAND_STARTERS = {
        "set", "change", "make", "turn", "enable", "disable", "show", "hide", "move", "nudge", "shift",
        "increase", "decrease", "raise", "lower", "select", "use", "apply",
        "setze", "stelle", "mach", "mache", "schalte", "schalt", "aktivieren", "aktiviere", "deaktivieren", "deaktiviere",
        "einschalten", "ausschalten", "anzeigen", "zeige", "verstecken", "verstecke", "einblenden", "ausblenden",
        "verschiebe", "verschieben", "waehle", "nutze",
    },
    SKIP_TERMS = {
        "copy", "copy profile", "profile copy", "copy from profile", "rename profile", "profile import", "profile export",
        "import profile", "export profile", "guided setup", "setup guide", "blacklist", "whitelist",
        "kopiere", "kopieren", "profil kopieren", "profil umbenennen",
    },
    SKIP_ALLOW_TERMS = { "width", "height", "alpha", "opacity", "name", "portrait", "color", "colour", "background" },
    VALUE_CONNECTORS = { " to ", " as ", " is ", " be ", " value ", " = ", " auf ", " zu ", " als ", " wert " },
    RELATIVE_VALUE_CONNECTORS = { " by ", " um " },
    SCOPE_RELATIONS = { " for ", " on ", " of ", " fuer ", " fur ", " vom ", " von " },

    BROAD_SCOPE_TERMS = { "all", "every", "alle", "jede", "jeder", "jedes" },
    PARTY_TERMS = { "party" },
    MYTHIC_RAID_TERMS = { "mythic raid", "mythicraid" },
    RAID_TERMS = { "raid" },
    AMBIGUOUS_TAIL_ITEMS = { "names", "portraits", "power bars", "mana bars", "health bars", "hp bars" },
    AMBIGUOUS_TAIL_ITEMS_SHORT = { "names", "portraits", "power bars", "mana bars" },
    PORTRAIT_SCOPE_TERMS = { "portrait" },
    HP_TEXT_SCOPE_TERMS = { "hp text", "health text" },
    POWER_TEXT_SCOPE_TERMS = { "power text" },
    DISTRIBUTABLE_DETAIL_TERMS = {
        "castbar", "cast bar", "portrait", "power bar", "mana bar", "hp text", "health text", "power text", "name text",
    },
    -- "deactivate"/"activate" were missing while their German equivalents were
    -- present, so "deactivate Boss Hide Out of Combat" matched no polarity term
    -- and fell through to the default ON -- turning the setting on when the
    -- player asked to turn it off. OFF is tested before ON at the call site,
    -- which is what keeps "deactivate" from being read as "activate".
    BOOL_OFF_TERMS = { "off", "disable", "disabled", "deactivate", "deactivated", "false", "no", "hide", "hidden", "aus", "deaktivieren", "ausschalten" },
    BOOL_ON_TERMS = { "on", "enable", "enabled", "activate", "activated", "true", "yes", "show", "visible", "keep", "an", "aktivieren", "einschalten" },
    CASTBAR_TERMS = { "castbar", "cast bar" },
    POWER_BAR_TERMS = { "power bar", "powerbar" },
    SHAPE_STYLE_TERMS = { "shape", "style" },
    RELATIVE_INCREASE_TERMS = { "bigger", "larger", "wider", "taller", "higher", "more", "grow", "increase", "raise" },
    RELATIVE_DECREASE_TERMS = { "smaller", "shorter", "narrower", "lower", "less", "decrease", "reduce" },
    SCOPE_TAIL_CONCRETE_TERMS = {
        "all unitframes", "all unit frames", "all group frames", "all groups",
        "every unitframe", "every group frame", "alle unitframes", "alle gruppenframes",
    },
    BOOLEAN_TOGGLE_GUARD_TERMS = { " turn on ", " turn off " },
    BOOLEAN_ON_OFF_TERMS = { " on ", " off " },
    BOOLEAN_COMMAND_TERMS = { "turn on", "turn off", "enable", "disable", "show", "hide" },
    BOOLEAN_ITEM_REJECT_TERMS = { "on", "off", "enable", "disable", "show", "hide" },
    TEXT_LABEL_TERMS = { "text", "label" },
    AURA_FILTER_TERMS = { "filter", "filters" },
    AURA_KIND_TERMS = { "aura", "auras", "buff", "buffs", "debuff", "debuffs" },
    MULTISCOPE_NUMERIC_ATTR_TERMS = {
        "width", "widths", "height", "heights", "x offset", "x offsets", "y offset", "y offsets",
    },
    SINGLE_NUMBER_SPECIAL_TERMS = { "portrait shape", "border thickness", "border size", "background on", "background off" },
    SCOPE_REMOVE_TERMS = {
        "targettarget", "target of target", "tot", "ziel des ziels", "focustarget", "focus target", "fokus ziel",
        "mythic raid", "mythicraid", "player", "spieler", "self", "ich", "target", "ziel", "focus", "fokus",
        "pet", "begleiter", "boss", "party", "raid", "frame", "frames", "unitframe", "unitframes",
        "group frame", "group frames", "gruppenframe", "gruppenframes",
        "and", "und",
    },
    ATTR_SPECS = {
        { phrase = "portrait border thickness", terms = { "portrait border thickness", "portrait border size" } },
        { phrase = "power bar height", terms = { "power bar height", "mana bar height", "energy bar height" } },
        { phrase = "background opacity", terms = { "background opacity", "bg opacity", "track opacity", "hp track opacity" } },
        { phrase = "border thickness", terms = { "border thickness", "outline thickness", "border size", "outline size" } },
        { phrase = "icon size", terms = { "icon size", "spell icon size" } },
        { phrase = "text size", terms = { "text size", "font size" } },
        { phrase = "portrait size", terms = { "portrait size" } },
        { phrase = "height", terms = { "height", "heights", "tall", "high", "hoehe" } },
        { phrase = "width", terms = { "width", "widths", "wide", "breite" } },
        { phrase = "x offset", terms = { "x offset", "x offsets", "offset x", "x" } },
        { phrase = "y offset", terms = { "y offset", "y offsets", "offset y", "y" } },
        { phrase = "alpha", terms = { "alpha", "opacity" } },
    },
    BOOLEAN_TAIL_ITEM_TERMS = {
        { term = "health text", item = "health text" },
        { term = "hp text", item = "health text" },
        { term = "power text", item = "power text" },
        { term = "debuffs", item = "debuff" },
        { term = "debuff", item = "debuff" },
        { term = "buffs", item = "buff" },
        { term = "buff", item = "buff" },
        { term = "castbar icon", item = "castbar icon" },
        { term = "cast bar icon", item = "castbar icon" },
        { term = "status icon", item = "status icon" },
        { term = "power bar", item = "power bar" },
        { term = "mana bar", item = "mana bar" },
        { term = "health bar", item = "health bar" },
        { term = "hp bar", item = "hp bar" },
        { term = "background", item = "background" },
        { term = "bg", item = "background" },
        { term = "portrait", item = "portrait" },
        { term = "name", item = "name" },
        { term = "castbar", item = "castbar" },
        { term = "cast bar", item = "castbar" },
        { term = "icon", item = "icon" },
    },
    BOOL_WORDS = {
        on = "turn on", enabled = "turn on", ["true"] = "turn on", yes = "turn on", show = "turn on",
        off = "turn off", disabled = "turn off", ["false"] = "turn off", no = "turn off", hide = "turn off",
        an = "turn on", aktiviert = "turn on", sichtbar = "turn on", ja = "turn on",
        aus = "turn off", deaktiviert = "turn off", versteckt = "turn off", nein = "turn off",
    },
    BOOLEAN_ITEM_TERMS = {
        { term = "health texts", item = "health text" },
        { term = "health text", item = "health text" },
        { term = "hp texts", item = "health text" },
        { term = "hp text", item = "health text" },
        { term = "power texts", item = "power text" },
        { term = "power text", item = "power text" },
        { term = "debuffs", item = "debuff" },
        { term = "debuff", item = "debuff" },
        { term = "buffs", item = "buff" },
        { term = "buff", item = "buff" },
        { term = "castbar icons", item = "castbar icon" },
        { term = "cast bar icons", item = "castbar icon" },
        { term = "castbar icon", item = "castbar icon" },
        { term = "cast bar icon", item = "castbar icon" },
        { term = "status icons", item = "status icon" },
        { term = "status icon", item = "status icon" },
        { term = "health bars", item = "health bar" },
        { term = "power bars", item = "power bar" },
        { term = "mana bars", item = "mana bar" },
        { term = "castbars", item = "castbar" },
        { term = "cast bars", item = "castbar" },
        { term = "portraits", item = "portrait" },
        { term = "names", item = "name" },
        { term = "namen", item = "name" },
        { term = "icons", item = "icon" },
        { term = "health bar", item = "health bar" },
        { term = "power bar", item = "power bar" },
        { term = "mana bar", item = "mana bar" },
        { term = "castbar", item = "castbar" },
        { term = "cast bar", item = "castbar" },
        { term = "portrait", item = "portrait" },
        { term = "name", item = "name" },
        { term = "icon", item = "icon" },
    },
    BOOLEAN_CHAIN_SCOPE_WORDS = {
        player = true, target = true, focus = true, pet = true, boss = true, party = true, raid = true,
        targettarget = true, focustarget = true,
    },
    CHAIN_SCOPE_WORDS = {
        player = true, target = true, focus = true, pet = true, boss = true, party = true, raid = true,
        targettarget = true, focustarget = true,
    },
    SLOT_WORDS = { left = true, right = true, center = true },
    DIRECTION_WORDS = { left = true, right = true, up = true, down = true },
    COLOR_VALUE_WORDS = {
        white = true, black = true, red = true, green = true, blue = true, yellow = true, cyan = true, magenta = true,
        orange = true, purple = true, pink = true, turquoise = true, grey = true, gray = true, brown = true, gold = true,
        violet = true, aqua = true, teal = true,
        weiss = true, schwarz = true, rot = true, gruen = true, blau = true, gelb = true, lila = true, rosa = true, tuerkis = true,
    },
    FONT_MODE_VALUE_WORDS = {
        default = true, palette = true, class = true, health = true, hp = true, resource = true, power = true, npc = true, red = true,
    },
    SHAPE_VALUE_WORDS = { square = true, circle = true, round = true, rounded = true, diamond = true },
    BORDER_VALUE_WORDS = { none = true, off = true, hide = true, hidden = true, disabled = true, solid = true, class = true, reaction = true, custom = true },
}
