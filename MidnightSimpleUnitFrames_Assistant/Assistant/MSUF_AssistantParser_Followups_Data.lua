-- Assistant follow-up parser data.
-- Phrase lists live here so follow-up logic stays focused on context resolution.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Data = A.ParserData or {}
A.ParserData = Data

Data.FOLLOWUPS_PARSER = {
    LAST_UNIT_CONTEXT_TERMS = {
        "it", "that", "this", "das", "same", "again", "wieder", "back", "more", "mehr",
        "frame", "unitframe", "name", "text", "health", "hp", "power", "width", "height",
        "size", "alpha", "opacity", "position", "offset", "anchor",
    },
    TROUBLESHOOTING_WHY_REFERENCE_TERMS = {
        "why is that", "why is this", "why are those", "why are these",
        "why is it", "why are they",
    },
    TROUBLESHOOTING_STATE_TERMS = {
        "hidden", "missing", "not showing", "not visible", "invisible",
        "disabled", "gone", "broken", "doesnt work", "does not work",
        "frame", "frames", "cast bar", "castbar", "buff", "buffs",
        "debuff", "debuffs", "aura", "auras", "text", "icon", "icons",
    },
    TROUBLESHOOTING_ACTION_TERMS = {
        "edit mode", "exit", "close", "cancel", "leave", "start", "open",
        "cast bar", "castbar", "frame", "frames", "aura", "auras",
        "buff", "buffs", "debuff", "debuffs", "profile", "import", "export",
        "anchor picker", "custom anchor", "copy", "paste",
    },
    PAGE_EXPLANATION_TERMS = {
        "explain this page", "explain current page", "explain the page",
        "explain page", "what is this page", "what can i do on this page",
        "what can i do on current page", "what can i change on this page",
        "what can i change on current page", "what can be changed on this page",
        "how can i configure this page", "show me commands for this page",
        "commands for this page", "current page help", "this page help",
        "help on this page", "help for this page", "page help",
    },
    VALUE_SUBJECT_OF_GUARD_TERMS = {
        "of it", "of that", "of this", "of the last setting", "of last setting", "of the last option", "of last option",
    },
    VALUE_SUBJECT_FOR_GUARD_TERMS = {
        "for it", "for that", "for this", "for the last setting", "for last setting", "for the last option", "for last option",
    },
    ASK_WHAT_CHANGED_TERMS = {
        "what did you change", "what changed", "what was changed", "what did you do",
        "what did you just change", "what exactly did you change", "what did you set",
        "last change", "last assistant change", "previous change", "what is it now",
        "what is it set to", "current value", "value now", "show last change",
        "show me last change", "show me the last change", "what now", "what happened",
        "what did that do", "what did this do", "what does that mean",
        "what does this mean", "explain that", "explain this",
        "explain the last change", "explain last change", "what is the result",
        "what was the result",
        "what did you copy", "what did you just copy", "what was copied", "last copy",
        "show last copy", "show me last copy",
    },
    ASK_WHY_TERMS = {
        "why did you change", "why did you do that", "why did you do this",
        "why did you set", "why did you pick", "why that change",
        "why this change", "why did that happen", "why did this happen",
        "why", "why that", "why this", "why did you", "why did you choose",
        "why did you choose that", "why did you choose this",
        "why did you choose that option", "why did you choose this option",
        "why that option", "why this option", "why did you pick that option",
        "why did you pick this option", "why did you use that",
        "why did you use this", "explain why",
    },
    CONTINUATION_MARKER_TERMS = { "ok now", "and now", " now ", " then ", " also ", " next " },
    PREVIOUS_COPY_QUERY_TERMS = {
        "what did you copy", "what was copied", "what did you just copy",
        "last copy", "previous copy", "copy history", "show copy",
    },

    POSITIVE_TERMS = {
        "bigger", "larger", "higher", "thicker", "wider", "taller", "increase", "raise", "up", "grow", "stronger",
        "brighter", "lighter", "more opaque", "more visible",
        "groesser", "hoeher", "dicker", "breiter", "heller", "hoch",
    },
    NEGATIVE_TERMS = {
        "smaller", "lower", "thinner", "narrower", "shorter", "less", "decrease", "reduce", "down", "shrink", "weaker",
        "darker", "dimmer", "more transparent", "less opaque", "fainter",
        "kleiner", "tiefer", "duenner", "weniger", "dunkler", "runter",
    },
    NEUTRAL_TERMS = {
        "more", "mehr", "weiter", "further", "farther", "again", "do it again", "same again", "once more", "one more",
        "another", "repeat", "keep going", "continue", "nochmal", "noch mal",
    },
    OPPOSITE_TERMS = {
        "opposite", "opposite way", "other way", "reverse", "reverse it", "undo direction", "andersrum", "umgekehrt",
    },
    REVERSE_CORRECTION_TERMS = {
        "too much", "too far", "not that much", "went too far", "go back a bit", "back a bit", "a bit back",
        "zu viel", "zu weit", "etwas zurueck",
    },
    TOO_POSITIVE_TERMS = {
        "too high", "too big", "too large", "too thick", "too wide", "too tall", "too bright", "too visible", "too opaque",
        "zu hoch", "zu gross", "zu dick", "zu breit", "zu hell",
    },
    TOO_NEGATIVE_TERMS = {
        "too low", "too small", "too thin", "too narrow", "too short", "too dark", "too transparent", "not visible enough",
        "zu niedrig", "zu klein", "zu duenn", "zu schmal", "zu dunkel",
    },
    NOT_ENOUGH_TERMS = {
        "not enough", "needs more", "need more", "more still", "still more", "not far enough",
        "not big enough", "not high enough", "not wide enough", "not visible enough",
        "nicht genug", "mehr noch",
    },
    REPLAY_TERMS = {
        "too", "also", "as well", "same", "same for", "same on", "same to",
        "do the same", "do that", "do it", "apply that", "apply it", "copy that", "copy it",
        "repeat that", "repeat it", "repeat that for", "repeat it for",
        "apply that to", "apply it to", "do that for", "do it for",
        "make same change", "make the same change", "make that same change",
        "auch", "auch fuer", "auch fur", "genauso", "genauso fuer", "genauso fur",
        "das auch", "mach das", "mach das gleiche", "das gleiche fuer", "das gleiche fur",
    },
    RIGHT_TERMS = { "right", "rechts" },
    LEFT_TERMS = { "left", "links" },
    UP_TERMS = { "up", "higher", "hoch", "oben", "hoeher" },
    DOWN_TERMS = { "down", "lower", "tiefer", "runter", "unten" },
    FORCE_POSITIVE_TERMS = { "more opaque", "less transparent", "more visible", "brighter", "lighter", "heller" },
    FORCE_NEGATIVE_TERMS = { "more transparent", "less opaque", "darker", "dimmer", "fainter", "dunkler" },
    NEUTRAL_INCREASE_TERMS = { "more", "mehr", "weiter", "further", "farther", "once more", "one more", "another", "keep going", "continue" },
    EXPLICIT_AURA_BULK_SCOPE_TERMS = {
        "all aura", "all auras", "all aura icon", "all aura icons",
        "all unit aura", "all unit auras", "all unit aura icon", "all unit aura icons",
        "all group aura", "all group auras", "all group aura icon", "all group aura icons",
        "all buff", "all buffs", "all buff icon", "all buff icons",
        "all debuff", "all debuffs", "all debuff icon", "all debuff icons",
        "every aura", "every aura icon", "every aura icons",
        "every buff", "every buff icon", "every debuff", "every debuff icon",
    },
    EXACT_VALUE_REFERENCE_TERMS = {
        "it", "that", "this",
        "last setting", "last value", "actually", "instead", "rather",
        "no", "nope", "wait", "oops",
        "set it", "set them", "set those", "set these",
        "make it", "make them", "make those", "make these",
        "change it", "change them", "change those", "change these",
        "move it to", "move them to", "move those to", "move these to",
        "them to", "those to", "these to",
        "use",
    },
    PLURAL_EXACT_VALUE_REFERENCE_TERMS = {
        "them", "those", "these", "both", "all", "all of them",
        "each", "every", "settings", "options", "values",
    },
    MIN_MAX_TERMS = { "min", "minimum", "max", "maximum" },
    COMMAND_INTENT_TERMS = {
        "set", "change", "make", "turn", "enable", "disable", "show", "hide", "move", "nudge", "shift",
        "create", "select", "use", "reset", "copy", "open", "import", "export", "rename", "delete", "remove", "switch", "assign",
        "setze", "stelle", "aktivieren", "deaktivieren", "einschalten", "ausschalten", "anzeigen", "verstecken", "einblenden", "ausblenden", "verschiebe", "verschieben",
    },
    AURA_LANE_OBJECT_REFERENCE_TERMS = {
        "them", "those", "these", "their",
        "the icon", "the icons", "icons", "aura icon", "aura icons",
        "buff icon", "buff icons", "debuff icon", "debuff icons",
        "buffs", "debuffs", "auras",
    },
    AURA_LANE_OBJECT_ACTION_TERMS = {
        "move", "nudge", "shift", "offset", "position", "left", "right", "up", "down",
        "x offset", "y offset", "per row", "icons per row", "spacing", "gap",
        "layer", "z", "z layer", "frame level", "cap", "limit", "max", "maximum", "count",
        "size", "bigger", "larger", "smaller", "shrink", "growth", "grow", "anchor",
    },
    GENERIC_OBJECT_REFERENCE_TERMS = {
        "it", "its", "that", "this", "them", "those", "these", "their",
        "the frame", "the frames", "the bar", "the bars", "the text", "the icon", "the icons",
        "same object", "same option area",
    },
    GENERIC_OBJECT_ACTION_TERMS = {
        "move", "nudge", "shift", "offset", "position", "left", "right", "up", "down",
        "x offset", "y offset", "width", "height", "wider", "narrower", "taller", "shorter",
        "size", "bigger", "larger", "smaller", "shrink",
        "layer", "z", "z layer", "frame level", "anchor", "growth", "grow",
        "color", "colour", "red", "green", "blue", "yellow", "orange", "purple", "white", "black", "gray", "grey",
        "shape", "circle", "circular", "round", "rounded", "square", "diamond",
        "style", "render", "2d", "3d", "zoom",
        "spacing", "gap", "thickness", "border", "alignment", "align", "opacity", "alpha",
        "separator", "seperator", "delimiter", "divider", "trennzeichen",
        "show", "hide", "enable", "disable", "turn on", "turn off", "on", "off",
    },
    EXPLICIT_FOLLOWUP_REFERENCE_TERMS = { "it", "that", "this", "them", "those", "these", "same", "do it", "do that", "again", "more", "less", "opposite", "other way" },
    BARE_DIRECTIONAL_FOLLOWUP_TERMS = {
        "left", "right", "up", "down",
        "move left", "move right", "move up", "move down",
        "nudge left", "nudge right", "nudge up", "nudge down",
        "shift left", "shift right", "shift up", "shift down",
    },
    BARE_DIRECTIONAL_GUARD_TERMS = { "anchor", "attach", "point", "bottom left", "bottom right", "top left", "top right" },
    HIDE_REFERENCE_TERMS = { "hide it", "clear it", "remove it", "empty it", "turn it off", "disable it", "hide that", "clear that", "remove that" },
    EXACT_MAX_TERMS = { "maximum", "max" },
    EXACT_MIN_TERMS = { "minimum", "min" },
    SMALL_AMOUNT_TERMS = { "a bit", "bit", "a little", "little", "slightly", "tiny", "small step", "etwas" },
    HALF_AMOUNT_TERMS = { "half", "half as much" },
    LARGE_AMOUNT_TERMS = { "a lot", "much", "way more", "way less", "far more", "far less", "big step", "large step", "twice", "double" },

    -- Nouns that name a PROPERTY of something rather than a control in their
    -- own right. Right after a change, "change the separator" means the
    -- separator of the thing just changed -- a player who does not know MSUF's
    -- own control names has no other way to say it, and requiring a pronoun
    -- sent those requests to whichever unrelated control happened to share the
    -- word (Class Resource Separator Width won "change the separator").
    -- Deliberately narrow: only nouns that cannot stand alone as a request.
    -- The follow-up still requires a fresh subject, no named frame, and a
    -- family search that resolves to exactly one control.
    SUBJECT_PROPERTY_FOLLOWUP_TERMS = {
        "separator", "separators", "seperator", "seperators",
        "delimiter", "delimiters", "divider", "dividers",
        "trennzeichen", "trenner",
    },
    GENERIC_REFERENCE_TERMS = {
        "it", "its", "that", "this", "them", "those", "these", "their",
        "the frame", "the frames", "the bar", "the bars", "the text", "the icon", "the icons",
        "same", "same object", "same option area",
    },
    GENERIC_ENABLE_TERMS = { "show", "hide", "enable", "disable", "turn on", "turn off", "on", "off" },
    GROWTH_TERMS = { "growth direction", "grow direction", "growth", "grow", "grows" },
    ANCHOR_TERMS = { "anchor", "anchor point", "position anchor", "bottom left", "bottom right", "top left", "top right", "bottomleft", "bottomright", "topleft", "topright" },
    MOVEMENT_TERMS = { "move", "nudge", "shift", "offset", "position", "left", "right", "up", "down", "links", "rechts", "hoch", "runter", "oben", "unten" },
    X_OFFSET_TERMS = { "x offset", "offset x", "horizontal offset" },
    Y_OFFSET_TERMS = { "y offset", "offset y", "vertical offset" },
    WIDTH_TERMS = { "width", "wider", "narrower", "wide", "breite", "breiter", "schmaler" },
    HEIGHT_TERMS = { "height", "taller", "shorter", "tall", "hoehe", "hoeher" },
    LAYER_TERMS = { "layer", "z", "z layer", "z level", "z-level", "z order", "z-order", "z index", "z-index", "draw layer", "frame level", "strata" },
    COLOR_TERMS = { "color", "colour", "farbe", "red", "green", "blue", "yellow", "orange", "purple", "white", "black", "gray", "grey" },
    SHAPE_TERMS = { "shape", "circle", "circular", "round", "rounded", "square", "diamond" },
    RENDER_TERMS = { "render", "2d", "3d", "class icon", "class portrait" },
    BORDER_STYLE_TERMS = { "border style", "border type", "outline style" },
    STYLE_TERMS = { "style", "appearance" },
    -- MSUF calls this control a Separator on some frames and a Delimiter on
    -- others; a player calls it whichever word came to mind, and spells it
    -- however it came out. The registry attributes use both spellings too, so
    -- the follow-up has to accept the whole family.
    SEPARATOR_TERMS = {
        "separator", "separators", "seperator", "seperators",
        "delimiter", "delimiters", "divider", "dividers",
        "trennzeichen", "trenner",
    },
    ZOOM_TERMS = { "zoom", "zoom in", "zoom out" },
    SPACING_TERMS = { "spacing", "gap", "space", "closer", "farther", "further apart" },
    THICKNESS_TERMS = { "thickness", "thicker", "thinner", "border size", "border thickness", "outline thickness" },
    ALIGNMENT_TERMS = { "alignment", "align", "left aligned", "right aligned", "centered", "centred" },
    OPACITY_TERMS = { "opacity", "alpha", "transparent", "transparency", "opaque", "faded", "fade" },
    GENERIC_SIZE_TERMS = { "icon size", "text size", "font size", "size", "bigger", "larger", "smaller", "shrink", "groesse", "grosse", "groesser", "kleiner" },
    -- Object prefix of a retained text setting mapped to the router's text
    -- kind. Unit frames store hp/power/name, group frames store the
    -- healthText/powerText/nameText spelling of the same objects.
    TEXT_KIND_BY_RELATED_PREFIX = {
        hp = "health", healthText = "health",
        power = "power", powerText = "power",
        name = "name", nameText = "name",
        status = "status", statusText = "status",
    },
    POWER_TEXT_TERMS = { "power text", "mana text", "power number", "mana number", "power value", "mana value" },
    HP_TEXT_TERMS = { "hp text", "health text", "health number", "hp number", "health value", "hp value" },
    NAME_TEXT_TERMS = { "name text", "name" },
    TEXT_SLOT_MOVE_TERMS = { "move", "nudge", "shift", "left", "right", "up", "down" },
    TEXT_SLOT_RESIZE_TERMS = { "make it bigger", "make it larger", "bigger", "larger", "increase it", "make it smaller", "smaller", "decrease it", "shrink it" },

    AURA_REFERENCE_TERMS = {
        "it", "that", "this", "them", "those", "these", "their",
        "the icon", "the icons", "icons", "aura icon", "aura icons",
        "buff icon", "buff icons", "debuff icon", "debuff icons",
        "buffs", "debuffs", "auras", "same",
    },
    AURA_PER_ROW_TERMS = { "per row", "icons per row", "wrap count", "row count" },
    AURA_SPACING_TERMS = { "spacing", "gap", "icon gap", "space them", "space out" },
    AURA_MAX_TERMS = {
        "max", "maximum", "max icons", "maximum icons", "max count", "maximum count",
        "icon count", "aura count", "buff count", "debuff count", "count",
        "cap", "caps", "capped", "aura cap", "buff cap", "debuff cap",
        "limit", "limits", "limited", "icon limit", "aura limit", "buff limit", "debuff limit",
    },
    AURA_SIZE_TERMS = { "icon size", "icons size", "size", "bigger", "larger", "smaller", "shrink", "groesse", "grosse", "groesser", "kleiner" },
    BUFF_TERMS = { "buff", "buffs" },
    DEBUFF_TERMS = { "debuff", "debuffs" },

    BOOLEAN_CORRECTION_TERMS = {
        "again", "wieder", "doch", "actually", "ne",
        "it", "that", "this", "back", "back on", "back off",
        "turn it", "turn that", "same setting", "last setting",
    },
    AURA_KIND_TERMS = { "aura", "auras", "buff", "buffs", "debuff", "debuffs" },
    PARSE_MOVEMENT_TERMS = { "move", "nudge", "shift", "verschiebe", "offset", "position", "x", "y" },
    PARSE_ANCHOR_TERMS = { "anchor" },
    ENABLED_GUARD_TERMS = {
        "in group", "when solo", "while solo", "show player", "hide player", "player in group",
        "show while solo", "while in group", "group when solo",
        "out of combat", "outside combat", "in combat", "while mounted", "when mounted", "mounted",
        "in vehicle", "while in vehicle", "when in vehicle", "resting", "stealthed", "load condition",
        "dispel overlay", "unitframe dispel", "debuff overlay",
    },
    DIMENSION_GUARD_TERMS = {
        "width mode", "height mode", "width source", "height source",
        "power bar height", "mana bar height", "energy bar height",
        "portrait height", "portrait width", "castbar height", "castbar width",
        "icon height", "icon width", "text height", "text width",
    },
    ALL_SCOPE_TERMS = { "all", "all of", "every", "each", "alle", "alles", "jede", "jeder", "jedes" },
}
