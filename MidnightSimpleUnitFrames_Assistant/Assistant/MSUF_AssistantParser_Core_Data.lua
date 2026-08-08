-- Assistant core parser data.
-- Shared phrase lists for low-level parser helpers.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Data = A.ParserData or {}
A.ParserData = Data

Data.CORE_PARSER = {
    UNIT_TERMS = {
        player = { "player", "player frame", "player unitframe", "spieler", "self", "ich" },
        target = { "target", "target frame", "target unitframe", "ziel" },
        focus = { "focus", "focus frame", "focus unitframe", "fokus" },
        pet = { "pet", "pet frame", "pet unitframe", "begleiter" },
        boss = { "boss", "boss frame", "boss frames", "bossframe", "bossframes" },
        targettarget = { "targettarget", "target of target", "target of target frame", "tot", "ziel des ziels" },
        focustarget = { "focustarget", "focus target", "focus target frame", "fokus ziel" },
    },
    MYTHIC_GROUP_TERMS = {
        "mythic raid frames", "mythic raid frame", "mythicraidframes", "mythicraidframe", "mythic raid", "mythicraid",
    },
    PARTY_GROUP_TERMS = { "party", "party frame", "party frames", "partyframe", "partyframes" },
    RAID_DETAIL_TERMS = { "preserve raid groups", "raid marker icon", "raid marker indicator", "raid marker symbol", "raid marker", "raid markers" },
    RAID_GROUP_TERMS = { "raid", "raid frame", "raid frames", "raidframe", "raidframes", "schlachtzug" },
    GROUP_COPY_GUARD_TERMS = { "group copy", "copy group", "copy category", "copy categories", "copy scope" },
    GROUP_FRAME_TERMS = { "group frames", "group frame", "groups", "group", "gruppenframes", "gruppe", "gruppen" },
    GLOBAL_SCOPE_TERMS = { "shared", "global" },
    -- "my name", "make my health text bigger": with no frame named anywhere,
    -- this is the player's own frame. Consumed only as DetectUnits' last
    -- resort, so an explicit unit always wins.
    FIRST_PERSON_POSSESSIVE_TERMS = { "my", "mine", "my own", "mein", "meine", "meinen", "meiner" },
    -- "all my frames" is every frame, not the speaker's own one: a bulk word
    -- outranks the possessive, so the fallback above must stand down. Without
    -- this, "reset the position of all my frames" reset only the Player frame.
    FIRST_PERSON_POSSESSIVE_BULK_GUARD_TERMS = {
        "all", "every", "each", "everything", "any",
        "alle", "allen", "jede", "jeder", "jedes", "saemtliche",
    },
    -- Here the possessive says WHOSE AURA it is, not which frame: MSUF's own
    -- control is called "Highlight My Buffs". Reading it as the Player frame
    -- retargeted those requests onto Player Buffs visibility.
    FIRST_PERSON_AURA_OWNERSHIP_TERMS = {
        "my buff", "my buffs", "my debuff", "my debuffs", "my aura", "my auras",
        "mine buff", "mine buffs", "mine debuff", "mine debuffs",
        "my own buff", "my own buffs", "my own debuff", "my own debuffs",
        "my own aura", "my own auras", "my cast", "my casts",
        "meine buffs", "meine debuffs", "meine auren",
    },

    ALT_MANA_TERMS = { "alt mana", "alternative mana", "secondary mana", "dual resource mana" },
    COMBAT_TIMER_TERMS = { "combat timer" },
    COMBAT_STATE_TERMS = { "combat state", "combat enter", "combat leave", "combat enter leave" },
    PLAYER_TOTEMS_TERMS = { "totem frame", "totemframe", "blizzard totem", "statue frame", "totem rahmen", "totemrahmen", "statuen rahmen", "statuenrahmen", "statue rahmen" },
    COMBAT_CROSSHAIR_TERMS = { "combat crosshair", "crosshair", "fadenkreuz", "melee range spell" },
    RAID_MARKER_FRAME_TERMS = { "raid marker", "raidmarker", "raid marker icon", "raid marker indicator", "raid marker symbol", "target marker" },
    RAID_MARKER_GROUP_GUARD_TERMS = { "group frame", "group frames", "party frame", "party frames", "raid frame", "raid frames", "mythic raid frame", "mythic raid frames" },

    DIRECTION_RIGHT_TERMS = { "right", "rechts" },
    DIRECTION_LEFT_TERMS = { "left", "links" },
    DIRECTION_DOWN_TERMS = { "down", "lower", "tiefer", "runter", "unten" },
    DIRECTION_UP_TERMS = { "up", "higher", "hoeher", "hoch", "oben" },
    DIRECTION_REPEAT_TERMS = { "more", "mehr", "weiter" },

    RANGE_FADE_TERMS = { "range fade", "range fading", "reichweite fade" },
    RAID_MARKER_ATTR_TERMS = { "raid marker", "raidmarker", "raid marker icon", "schlachtzug marker" },
    CASTBAR_TERMS = { "castbar", "zauberleiste" },
    CASTBAR_ICON_TERMS = { "spell icon", "cast icon", "icon", "symbol" },
    CASTBAR_TIME_TERMS = { "cast time", "castbar time", "time text", "timer", "time" },
    CASTBAR_TEXT_TERMS = { "spell name", "spell text", "castbar name", "castbar text", "name text", "name", "text" },
    CASTBAR_INTERRUPT_TERMS = { "interrupt", "interruptible", "kick", "kickable", "unterbrechen" },
    CASTBAR_ROOT_GUARD_TERMS = { "width", "height", "breite", "hoehe", "x", "y", "left", "right", "up", "down", "links", "rechts", "hoch", "tiefer" },
    HP_TEXT_TERMS = { "hp text", "health text", "health value", "life text", "leben text", "leben", "gesundheit", "lebenspunkte", "lebensanzeige" },
    POWER_TEXT_TERMS = { "power text", "mana text", "power value", "mana value", "energie text", "energie", "ressource", "ressourcen" },
    NAME_TEXT_TERMS = { "name text", "unit name", "name", "namen" },
    WIDTH_TERMS = { "width", "wide", "wider", "narrower", "breite", "breiter", "schmaler" },
    HEIGHT_TERMS = { "height", "tall", "taller", "shorter", "hoehe", "hoeher", "kleiner" },
    ENABLED_VERB_TERMS = { "enable", "disable", "show", "hide", "on", "off", "an", "aus", "aktivieren", "deaktivieren", "einschalten", "ausschalten", "anzeigen", "verstecken", "einblenden", "ausblenden" },
    FRAME_SCOPE_TERMS = { "frame", "frames", "unitframe", "unitframes", "group", "gruppe" },
    ENABLED_EXCLUDE_TERMS = {
        "indicator", "indicators", "status icon", "status indicator", "icon", "icons", "symbol", "symbols",
        "border", "outline", "portrait", "alpha", "opacity", "texture", "font", "text", "name", "names", "color", "farbe",
        "power bar", "mana bar", "health bar", "hp bar", "castbar", "cast bar", "load condition",
        "offline", "solo", "sort", "sorting", "role", "scale", "scaling", "shorten", "shortening", "truncate", "truncation",
    },
}
