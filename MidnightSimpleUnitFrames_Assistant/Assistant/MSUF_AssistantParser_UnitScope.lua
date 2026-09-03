-- Assistant unit-scope parser: resolves plain-English requests that talk about
-- ONE unit frame ("put the portrait on the left of my player frame", "fade the
-- target frame when they are out of range", "hide my player frame while
-- mounted") against that unit's own registered controls.
--
-- Players do not speak in menu labels. They name the frame once -- as a
-- locative ("on the target frame"), a possessive ("the target's name", "my
-- player portrait") or a bare "my ..." -- and then describe the result they
-- want. Two things went wrong with that before this module existed:
--
--   1. The floating exact-alias window read "target frame" (an alias of Target
--      Frame Enabled) out of "show the pvp flag on my target frame" and
--      answered "already enabled", or wrote the frame's master toggle for
--      "hide the player frame when i am mounted".
--   2. Lanes keyed on one noun ("portrait" -> Portrait Position) claimed every
--      sentence containing it, so "turn on the cast spell icon in the player
--      portrait" moved the portrait to the left.
--
-- The rule here: once the unit is known, EVERY remaining meaningful word must
-- be explained by exactly one of that unit's controls (its label, one of its
-- aliases, or one of its own values), after a small synonym layer folds the
-- player's wording onto the registry's ("health" -> hp, "icon" -> indicator,
-- "mounted" -> the Hide Mounted rule). Anything less resolves to nil and the
-- ordinary pipeline continues, so this lane never guesses.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local P = A.Parser or {}
A.Parser = P

local Normalize = P.Normalize
local ContainsAny = P.ContainsAny
local DetectBoolean = P.DetectBoolean
local FirstNumber = P.FirstNumber
local PluralFoldWord = P.PluralFoldWord
if not (Normalize and ContainsAny and DetectBoolean and FirstNumber) then return end

local UNIT_KEYS = { "player", "target", "focus", "pet", "boss", "targettarget", "focustarget" }

-- Longest first: "targettarget" must be recognised before "target".
local UNIT_WORDS = {
    { "targettarget", "targettarget" }, { "tot", "targettarget" },
    { "focustarget", "focustarget" },
    { "player", "player" }, { "spieler", "player" },
    { "target", "target" }, { "ziel", "target" },
    { "focus", "focus" }, { "fokus", "focus" },
    { "pet", "pet" }, { "begleiter", "pet" },
    { "boss", "boss" },
}
local UNIT_WORD_SET = {}
for i = 1, #UNIT_WORDS do UNIT_WORD_SET[UNIT_WORDS[i][1]] = UNIT_WORDS[i][2] end

local FRAME_WORDS = { frame = true, frames = true, unitframe = true, unitframes = true }
local DETERMINERS = { the = true, my = true, your = true, our = true, a = true, an = true, this = true, that = true, its = true }
local LOCATIVE_PREPS = {
    on = true, ["for"] = true, of = true, ["in"] = true, at = true, from = true, to = true,
    onto = true, into = true, within = true, inside = true, across = true, with = true, against = true,
}
-- "turn on player name": that "on" belongs to the verb, not to a place.
local PHRASAL_VERBS = { turn = true, turned = true, switch = true, switched = true, toggle = true, toggled = true, set = true, is = true, are = true }
local MOVEMENT_VERBS = { "move", "nudge", "shift", "drag", "push", "slide", "reposition", "verschiebe", "verschieben" }
local GROUP_SCOPE_TERMS = {
    "party frame", "party frames", "raid frame", "raid frames", "group frame", "group frames",
    "mythic raid", "mythicraid", "raid frames", "partyframe", "raidframe", "gruppenframes",
}
local AURA_TERMS = { "buff", "buffs", "debuff", "debuffs", "aura", "auras", "blacklist", "whitelist" }
-- "same for target" continues the previous change; the follow-up lanes own it.
local FOLLOWUP_TERMS = {
    "same for", "same on", "same thing", "the same", "do the same", "also for", "and for", "likewise",
    "as well", "ditto", "that too", "this too", "it too", "now for", "now the", "and the", "and my",
    "again", "undo", "redo", "revert", "reset", "restore",
}

-- "no target" names a visibility rule, not the Target frame.
local TARGET_IDIOMS = {
    "out of combat and no target", "out of combat with no target", "no target while out of combat",
    "nothing is targeted", "nothing targeted", "have no target", "has no target", "without a target",
    "without target", "no target selected", "no target", "target selected", "has a target", "with a target",
    "not targeting anything", "not targeting",
}

local function MaskTargetIdioms(text)
    for i = 1, #TARGET_IDIOMS do
        local idiom = TARGET_IDIOMS[i]
        local replacement = (idiom:find("out of combat", 1, true) and "out of combat notarget") or "notarget"
        text = text:gsub("%f[%a]" .. idiom:gsub("%s+", "%%s+") .. "%f[%A]", replacement)
    end
    return text
end

-- Phrase folds run on the SUBJECT (the sentence minus the frame mention) before
-- tokenizing. Longest phrases first so "more transparent" is not cut by
-- "transparent". Each entry: { phrase, replacement }.
local PHRASE_FOLDS = {
    { "hard to read", "size bigger" }, { "hard to see", "size bigger" }, { "cant read", "size bigger" },
    { "too small", "size bigger" }, { "too tiny", "size bigger" }, { "too big", "size smaller" },
    { "too large", "size smaller" }, { "too huge", "size smaller" },
    { "too thin", "height bigger" }, { "too narrow", "width bigger" }, { "too wide", "width smaller" },
    { "too short", "height bigger" }, { "too tall", "height smaller" }, { "too thick", "thickness smaller" },
    { "too transparent", "opacity bigger" }, { "too faint", "opacity bigger" }, { "too strong", "opacity smaller" },
    { "too dark", "opacity smaller" },
    { "out of range", "range fade" }, { "outside of range", "range fade" }, { "outside range", "range fade" },
    { "not in range", "range fade" }, { "in range", "range fade" },
    { "zoomed in", "zoom bigger" }, { "zoom in", "zoom bigger" }, { "zoom out", "zoom smaller" },
    { "more transparent", "opacity smaller" }, { "more see through", "opacity smaller" },
    { "less transparent", "opacity bigger" }, { "more opaque", "opacity bigger" },
    { "more visible", "opacity bigger" }, { "less visible", "opacity smaller" },
    { "half transparent", "opacity 50%" }, { "half opacity", "opacity 50%" }, { "half visible", "opacity 50%" },
    { "fully visible", "visible" }, { "fully opaque", "opacity 100%" },
    { "fill from the right", "reverse fill" }, { "fills from the right", "reverse fill" },
    { "fill right to left", "reverse fill" }, { "fill from right to left", "reverse fill" },
    { "from bottom to top", "vertical" }, { "bottom to top", "vertical" }, { "bottom up", "vertical" },
    { "left to right", "horizontal" }, { "right to left", "horizontal" },
    { "class icon", "class" }, { "class picture", "class" },
    { "over the health bar", "overlay" }, { "over the hp bar", "overlay" }, { "over the bar", "overlay" },
    { "on top of the health bar", "overlay" }, { "on top of the hp bar", "overlay" }, { "on top of the bar", "overlay" },
    { "who interrupted", "interrupter name" }, { "who kicked", "interrupter name" }, { "who interrupts", "interrupter name" },
    { "who is interrupting", "interrupter name" }, { "interrupter s name", "interrupter name" },
    { "class name", "class text" }, { "class of the", "class text of the" },
    { "party leader", "leader" }, { "raid leader", "leader" }, { "group leader", "leader" },
    { "leader crown", "leader icon" }, { "crown icon", "leader icon" }, { "crown", "leader icon" },
    { "in a rest area", "resting" }, { "rest area", "resting" }, { "rested area", "resting" },
    { "not fighting", "out of combat" }, { "not in combat", "out of combat" }, { "not in a fight", "out of combat" },
    { "i leave combat", "out of combat" }, { "leaving combat", "out of combat" }, { "leave combat", "out of combat" },
    { "combat ends", "out of combat" }, { "the fight ends", "out of combat" }, { "after the fight", "out of combat" },
    { "outside of combat", "out of combat" }, { "outside combat", "out of combat" }, { "after combat", "out of combat" },
    { "when fighting", "in combat" }, { "while fighting", "in combat" }, { "during combat", "in combat" },
    { "during a fight", "in combat" }, { "in a fight", "in combat" }, { "fighting", "in combat" },
    { "in a vehicle", "in vehicle" }, { "in vehicles", "in vehicle" },
    { "in stealth", "stealthed" }, { "while stealthed", "stealthed" },
    { "dungeons and raids", "instance" }, { "dungeons or raids", "instance" }, { "dungeons", "instance" },
    { "dungeons and raid", "instance" }, { "dungeon and raid", "instance" }, { "instances and raid", "instance" },
    { "dungeon", "instance" }, { "instances", "instance" },
    { "in a group", "in group" }, { "in a party", "in group" }, { "grouped", "in group" }, { "in groups", "in group" },
    { "always show mana", "show displayed power resource mana" }, { "always display mana", "show displayed power resource mana" },
    { "always mana", "show displayed power resource mana" }, { "show mana instead", "show displayed power resource mana" },
    { "mana instead of", "show displayed power resource mana" },
    { "as a separate bar", "detach" }, { "separate bar", "detach" }, { "own bar", "detach" },
    { "standalone bar", "detach" }, { "standalone", "detach" }, { "separately", "detach" },
    { "inside the health bar", "embed into health" }, { "inside the hp bar", "embed into health" },
    { "into the health bar", "embed into health" }, { "into the hp bar", "embed into health" },
    { "inside of the health bar", "embed into health" },
    { "percentage sign", "% sign" }, { "percent sign", "% sign" }, { "percent symbol", "% sign" },
    { "percentage symbol", "% sign" }, { "% symbol", "% sign" }, { "pct sign", "% sign" },
    { "decimal places", "decimals" }, { "decimal points", "decimals" },
    { "a slash", "/" }, { "slash", "/" }, { "a dash", "-" }, { "a pipe", "|" }, { "a colon", ":" },
    { "i am casting", "cast" }, { "im casting", "cast" }, { "is casting", "cast" }, { "am casting", "cast" },
    { "raid icon", "raid marker" }, { "target marker", "raid marker" }, { "raid mark", "raid marker" },
    { "raid target icon", "raid marker" }, { "raid target marker", "raid marker" },
    { "elite dragon", "elite" }, { "rare dragon", "elite" }, { "dragon", "elite" },
    { "war mode", "pvp" }, { "warmode", "pvp" }, { "flagged for pvp", "pvp flag" }, { "pvp flagged", "pvp flag" },
    { "being resurrected", "incoming rez" }, { "someone is resurrecting", "incoming rez" },
    { "someone resurrects", "incoming rez" }, { "getting resurrected", "incoming rez" },
    { "resurrecting", "incoming rez" }, { "resurrection", "incoming rez" }, { "resurrected", "incoming rez" },
    { "resurrect", "incoming rez" }, { "incoming res", "incoming rez" }, { "battle rez", "incoming rez" },
    { "brez", "incoming rez" }, { "ressing", "incoming rez" }, { "rezzing", "incoming rez" },
    { "short form", "abbreviate" }, { "shortened", "abbreviate" }, { "shorten", "abbreviate" },
    { "abbreviated", "abbreviate" }, { "k and m", "abbreviate" },
    { "animate smoothly", "smooth" }, { "animated", "smooth" }, { "animate", "smooth" }, { "smoothly", "smooth" },
    { "slide instead of jumping", "smooth" }, { "slide", "smooth" },
    { "in chunks", "chunked" }, { "chunky", "chunked" }, { "chunks", "chunked" },
    { "colour scheme", "color scheme" }, { "dark theme", "dark" },
    { "when it dies", "dead" }, { "when they die", "dead" }, { "when dead", "dead" },
    { "when i die", "dead" }, { "on death", "dead" },
    { "next to the name", "" }, { "next to my name", "" }, { "beside the name", "" },
    { "group number", "raid group" }, { "raid group number", "raid group" },
    { "class coloured", "class color" }, { "class colored", "class color" }, { "class colour", "class color" },
    { "by class", "class" }, { "in class colors", "class color" }, { "in class color", "class color" },
    { "solid corners", "square" }, { "sharp corners", "square" }, { "soft corners", "rounded" },
    { "rest of the", "" }, { "a bit", "" }, { "a little", "" }, { "a lot", "" }, { "slightly", "" },
}

-- Word folds map one request word to the canonical token the registry uses.
-- A word may carry several acceptable canonical forms ("icon" is spelled
-- Indicator, Icon or Marker depending on the control).
local WORD_FORMS = {
    health = { "hp" }, hitpoints = { "hp" }, hitpoint = { "hp" }, life = { "hp" }, lives = { "hp" },
    powerbar = { "power" }, powerbars = { "power" }, healthbar = { "hp" }, healthbars = { "hp" },
    hpbar = { "hp" }, manabar = { "power" }, manabars = { "power" },
    -- "mana" stays its own word first: it is the MANA choice of Displayed
    -- Power Resource, and only secondarily a way of saying "power".
    mana = { "mana", "power" }, energy = { "power" }, rage = { "power" }, runic = { "power" }, resource = { "power", "resource" },
    resources = { "power", "resource" },
    icon = { "icon", "indicator", "marker" }, icons = { "icon", "indicator", "marker" },
    indicator = { "indicator", "icon" }, indicators = { "indicator", "icon" },
    marker = { "marker", "icon" }, markers = { "marker", "icon" },
    symbol = { "symbol", "indicator", "icon", "sign" }, symbols = { "symbol", "indicator", "icon" },
    number = { "text", "values" }, numbers = { "text", "values" }, digits = { "text" }, value = { "values", "text" },
    values = { "values", "text" },
    colour = { "color" }, colours = { "color" }, coloured = { "color" }, colored = { "color" }, colors = { "color" },
    transparency = { "opacity" }, transparent = { "opacity" }, alpha = { "opacity" }, opaque = { "opacity" },
    fade = { "fade", "opacity" }, faded = { "fade", "opacity" }, fades = { "fade", "opacity" }, fading = { "fade", "opacity" },
    dim = { "opacity" }, dimmer = { "opacity" },
    pic = { "portrait" }, picture = { "portrait" }, avatar = { "portrait" }, portraits = { "portrait" },
    round = { "circle", "rounded" }, circular = { "circle" }, circle = { "circle" }, squared = { "square" },
    detach = { "detach" }, detached = { "detached" }, attach = { "attach" },
    centre = { "center" }, middle = { "center" }, centered = { "center" }, centred = { "center" },
    vertically = { "vertical" }, horizontally = { "horizontal" },
    dies = { "dead" }, died = { "dead" }, death = { "dead" }, dying = { "dead" },
    lvl = { "level" }, levels = { "level" },
    mount = { "mounted" }, riding = { "mounted" }, mounts = { "mounted" },
    alone = { "solo" }, stealth = { "stealthed" }, invisible = { "stealthed" },
    house = { "housing" }, homes = { "housing" },
    thick = { "thickness" }, thin = { "thickness" }, wide = { "width" }, tall = { "height" },
    big = { "size" }, large = { "size" }, small = { "size" },
    backdrop = { "background" },
    interrupts = { "interrupt" }, interrupted = { "interrupt" }, interruption = { "interrupt" },
    kick = { "interrupt" }, kicks = { "interrupt" }, kicked = { "interrupt" },
    interrupters = { "interrupter" },
    sep = { "delimiter" }, separator = { "delimiter" }, divider = { "delimiter" },
    reverse = { "reverse" }, reversed = { "reverse" }, swap = { "reverse" }, swapped = { "reverse" }, invert = { "reverse" },
    flip = { "mirror", "reverse" }, flipped = { "mirror" }, mirrored = { "mirror" },
    embed = { "embed" }, embedded = { "embed" },
    overlay = { "overlay" }, overlaid = { "overlay" },
    cast = { "cast", "castbar" }, casting = { "cast", "castbar" }, spellcast = { "cast" },
    rez = { "rez" }, res = { "rez" },
    flagged = { "flag" }, flags = { "flag" },
    layers = { "layer" }, textures = { "texture" },
    positioned = { "position" }, placement = { "placement" },
    anchored = { "anchor" }, anchors = { "anchor" },
    outline = { "outline", "border" }, outlines = { "outline", "border" }, borders = { "border" },
    decimal = { "decimals" },
    missing = { "deficit", "missing" }, lost = { "deficit" },
    abbreviations = { "abbreviate" }, abbreviation = { "abbreviate" },
    percentage = { "percent" }, percentages = { "percent" }, pct = { "percent" },
    sizes = { "size" }, widths = { "width" }, heights = { "height" },
    combat = { "combat" }, fight = { "combat" },
    ["%"] = { "%", "percent" },
}

-- Comparatives state a direction on a dimension. Each maps to the dimension
-- token the control's label must carry, plus the sign of the change.
local COMPARATIVES = {
    bigger = { "size", 1 }, larger = { "size", 1 }, enlarge = { "size", 1 }, enlarged = { "size", 1 },
    huge = { "size", 1 }, increase = { false, 1 }, raise = { false, 1 },
    smaller = { "size", -1 }, shrink = { "size", -1 }, tiny = { "size", -1 }, reduce = { false, -1 },
    decrease = { false, -1 }, lower = { false, -1 },
    taller = { "height", 1 }, higher = { "height", 1 }, shorter = { "height", -1 },
    wider = { "width", 1 }, widen = { "width", 1 }, narrower = { "width", -1 }, narrow = { "width", -1 },
    thicker = { "thickness", 1 }, thinner = { "thickness", -1 },
    fainter = { "opacity", -1 }, dimmer = { "opacity", -1 }, brighter = { "opacity", 1 },
    closer = { "zoom", 1 }, further = { "zoom", -1 },
    stronger = { "strength", 1 }, weaker = { "strength", -1 },
}

-- Words that carry no meaning for control identity. Polarity words are here
-- too: they are read by DetectBoolean, never matched against a label.
local STOP_WORDS = {}
for word in ([[
the a an my your our its it them they their i me we you he she im id ive
to of for at from into onto by as is are be am was were been being has have had
that this these those there here so too very really just only all every any some
bit little more much less again also and or but then than when while whenever if once
after before during until always ever still yet now currently instead rather maybe
kind sort something someone anyone everyone nothing thing things stuff
make set change adjust put give let use using have got see look looks read feel
want wanted wanna need needs like would could should can cant cannot may might will wont
please pls plz thanks thank ok okay hey hi hello msuf assistant
show shows showing display displaying hide hides hiding hidden enable enabled disable disabled
turn turned toggle activate activated deactivate deactivated on off
dont do not no never remove removed drop dropped ditch rid without keep keeping stop
side corner area around about over up down out get gets
who what which where how why whose
leave leaving move moving write print say tell
behind beneath next near beside inside draw drawn between among much many amount lot lots
please kindly actually basically simply
me myself own mine yourself
frame frames unitframe unitframes unit units
option options setting settings
]]):gmatch("%S+") do STOP_WORDS[word] = true end
-- "out" and "in" survive as tokens: "Hide Out of Combat" and "Hide in Combat"
-- differ by exactly those words.
STOP_WORDS["out"] = nil
STOP_WORDS["in"] = nil

-- Soft tokens never fail a match on their own and never count as an extra
-- label word: they describe the kind of thing, not which thing.
local SOFT_TOKENS = {
    text = true, bar = true, bars = true, frame = true, frames = true, unit = true, ["in"] = true,
    values = true, value = true, default = true, standard = true, normal = true,
    own = true, whole = true, entire = true, indicator = false,
}

local FRAME_LEVEL_ATTRS = { point = true, anchorPoint = true, width = true, height = true, offsetX = true, offsetY = true,
    anchorToUnitframe = true, anchorFrameName = true, enabled = true, useBlizzardFrame = true }

local REQUIRED_QUALIFIERS = {
    detached = true, custom = true, override = true, embed = true, reverse = true, negative = true,
    positive = true, inline = true, throttle = true, spacer = true, mask = true, test = true,
    preview = true, temp = true, second = true, duplicate = true,
}

-- Generic label words that qualify a control without identifying it; a
-- sentence that never says them still means the control.
local LABEL_QUALIFIERS = {
    enabled = true, status = true, indicator = true, icon = true, marker = true, symbol = true,
    show = false, hide = false,
}

local COLOR_WORDS = {}
for word in ([[red green blue yellow orange purple pink white black grey gray cyan magenta teal
brown violet lime gold silver turquoise navy maroon olive aqua crimson scarlet amber]]):gmatch("%S+") do
    COLOR_WORDS[word] = true
end
local NUMBER_UNIT_TOKENS = { px = true, pixel = true, pixels = true, pt = true, point = true, points = true,
    percent = true, ["%"] = true, degrees = true }

local INTENT_VERBS = {}
for word in ([[show hide display enable disable turn toggle activate deactivate remove drop ditch keep stop
make set change adjust put give let use want need like wanna prefer switch
mirror flip detach attach embed zoom fade reverse swap invert abbreviate shorten draw paint color colour
anchor center centre round square animate fill sync lock unlock apply pick choose select
write print say tell display zoom
should must lets please can could would id im ive i]]):gmatch("%S+") do
    INTENT_VERBS[word] = true
end

-- "set X" / "change X" name a control without stating what it should become.
local NEUTRAL_VERBS = { set = true, change = true, adjust = true, configure = true, modify = true, update = true,
    tweak = true, customize = true, customise = true, pick = true, choose = true, select = true, apply = true }

local HIDE_VERBS = { "hide", "remove", "drop the", "get rid", "ditch", "dont show", "do not show", "never show",
    "dont want", "do not want", "no longer", "turn off", "switch off", "disable", "without" }
local SHOW_VERBS = { "show", "display", "enable", "turn on", "switch on", "activate", "i want", "i need",
    "i would like", "id like", "give me", "let me see", "put", "add" }
local EXPLICIT_TOGGLE_TERMS = { "turn on", "turn off", "switch on", "switch off", "enable", "disable",
    "activate", "deactivate", "to on", "to off", "set to", "toggle on", "toggle off" }

local ONOFF_ENUM_OFF_VALUES = { OFF = true, NONE = true, HIDDEN = true, HIDE = true, DISABLED = true, ["off"] = true, ["none"] = true }
local SYMBOL_VALUES = { ["/"] = true, ["-"] = true, ["|"] = true, [":"] = true, ["\\"] = true, ["<"] = true, [">"] = true, ["~"] = true }

-- Controls that are THE toggle for a feature noun. When a polarity-only
-- sentence names just the feature ("hide the portrait"), these win over the
-- feature's detail toggles that tie on wording.
local PRIMARY_TOGGLE_ATTRS = {
    portraitMode = true, showName = true, showHP = true, showPowerText = true, showPowerBar = true,
    showRaidMarker = true, showLevelIndicator = true, texLayerEnabled = true, statusTextEnabled = true,
    showCombatStateIndicator = true, showLeaderIcon = true, showRestingIndicator = true,
    showIncomingResIndicator = true, showPvpIndicator = true, showStanceIndicator = true,
    rangeFadeEnabled = true, unitDispelSymbolEnabled = true, enabled = true, oocFadeEnabled = true,
    showEliteIcon = true, showClassTextIndicator = true, showRaceIndicator = true, showRaidGroupInName = true,
    powerBarBorderEnabled = true, powerBarDetached = true,
    embedPowerBarIntoHealth = true, statusAFKTextEnabled = true, statusDNDTextEnabled = true,
    statusGhostTextEnabled = true, showInterrupt = true, showInterruptSource = true,
}

local MentionsActionAlias

local function Trim(text)
    return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function EscapePattern(text)
    return (text:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
end

-- Longest phrase first, whatever order the table lists them in, so
-- "dungeons and raid" is folded before "dungeons" can eat its head.
table.sort(PHRASE_FOLDS, function(a, b)
    if #a[1] ~= #b[1] then return #a[1] > #b[1] end
    return a[1] < b[1]
end)

local function ApplyPhraseFolds(text)
    text = " " .. text .. " "
    for i = 1, #PHRASE_FOLDS do
        local phrase, replacement = PHRASE_FOLDS[i][1], PHRASE_FOLDS[i][2]
        local pattern = " " .. EscapePattern(phrase) .. " "
        if text:find(pattern) then
            text = text:gsub(pattern, " " .. replacement .. " ")
        end
    end
    return Trim((text:gsub("%s+", " ")))
end

local function CanonicalWord(word)
    local forms = WORD_FORMS[word]
    if forms then return forms[1] end
    return word
end

local function WordForms(word)
    local forms = WORD_FORMS[word]
    local out = {}
    if forms then
        for i = 1, #forms do out[#out + 1] = forms[i] end
    end
    local seen = {}
    for i = 1, #out do seen[out[i]] = true end
    if not seen[word] then out[#out + 1] = word; seen[word] = true end
    if PluralFoldWord then
        local folded = PluralFoldWord(word)
        if folded and folded ~= "" and not seen[folded] then
            out[#out + 1] = folded
            seen[folded] = true
            local canon = CanonicalWord(folded)
            if canon ~= folded and not seen[canon] then out[#out + 1] = canon; seen[canon] = true end
        end
    end
    return out
end

-- Scope detection --------------------------------------------------------

local function TokensOf(text)
    local out = {}
    for token in text:gmatch("%S+") do out[#out + 1] = token end
    return out
end

local function UnitForToken(token)
    return UNIT_WORD_SET[token]
end

-- Returns unit, subjectTokens, info for a sentence that names exactly one
-- unit frame, else nil. `info.frameMentioned` is true when the word frame was
-- used, `info.locative` when a preposition introduced it, `info.frameIsObject`
-- when the frame phrase was the verb's own object ("hide the player frame").
function P.UnitScopeFromNaturalText(text)
    local norm = Normalize(text)
    if norm == "" then return nil end
    norm = MaskTargetIdioms(norm)
    -- Possessives: Normalize drops the apostrophe, so "target's name" is
    -- "targets name". Fold that back to the unit word.
    for _, pair in ipairs({ { "player", "player" }, { "target", "target" }, { "focus", "focus" }, { "pet", "pet" }, { "boss", "boss" } }) do
        norm = norm:gsub("%f[%a]" .. pair[1] .. "s%s+(%a)", pair[1] .. " %1")
    end
    if ContainsAny(norm, GROUP_SCOPE_TERMS) then return nil end
    -- A party/raid scope word makes it a group-frame sentence ("do not show
    -- raid player in group when solo" is Raid > Show Player), unless the word
    -- is part of a unit-frame idiom such as "raid marker" or "party leader".
    do
        local masked = " " .. norm .. " "
        for _, idiom in ipairs({ "raid marker", "raid markers", "raid icon", "raid icons", "raid group", "raid target",
            "party leader", "raid leader", "group leader", "dungeons and raids", "dungeons or raids", "group number",
            "dungeons and raid", "dungeon and raid", "instances and raid" }) do
            masked = masked:gsub(" " .. EscapePattern(idiom) .. " ", " idiom ")
        end
        local groups = P.DetectGroups and P.DetectGroups(Trim(masked)) or {}
        if #groups > 0 then return nil end
    end
    local tokens = TokensOf(norm)
    local unit, mentionIndex
    local distinct = {}
    for i = 1, #tokens do
        local mapped = UnitForToken(tokens[i])
        if mapped then
            distinct[mapped] = true
            if not unit then unit, mentionIndex = mapped, i end
        end
    end
    local count = 0
    for _ in pairs(distinct) do count = count + 1 end
    if count > 1 then return nil end
    local info = { locative = false, frameMentioned = false, frameIsObject = false, explicit = unit ~= nil }
    if not unit then
        -- "make my name bigger": the parser's own first-person rule.
        local detected = P.DetectUnits and P.DetectUnits(norm) or {}
        if #detected == 1 and detected[1] == "player" then
            unit = "player"
        else
            return nil
        end
        return unit, tokens, info
    end
    -- Remove the frame mention: [prep] [det] <unit> [unit] [frame].
    local first, last = mentionIndex, mentionIndex
    if tokens[last + 1] == "unit" and tokens[last + 2] and FRAME_WORDS[tokens[last + 2]] then
        last = last + 2
        info.frameMentioned = true
    elseif tokens[last + 1] and FRAME_WORDS[tokens[last + 1]] then
        last = last + 1
        info.frameMentioned = true
    end
    if tokens[first - 1] and DETERMINERS[tokens[first - 1]] then first = first - 1 end
    if tokens[first - 1] and LOCATIVE_PREPS[tokens[first - 1]]
        and not (tokens[first - 1] == "on" and tokens[first - 2] and PHRASAL_VERBS[tokens[first - 2]])
    then
        first = first - 1
        info.locative = true
    end
    -- "set only target ..." restricts the scope override; that lane pairs the
    -- write with the scope switch and owns the sentence.
    if tokens[first - 1] == "only" or (tokens[first - 2] == "only" and (DETERMINERS[tokens[first - 1]] or LOCATIVE_PREPS[tokens[first - 1]])) then
        return nil
    end
    -- A frame phrase sitting right behind a verb is the verb's object; behind
    -- a preposition it only says WHERE the real subject lives.
    if info.frameMentioned and not info.locative then info.frameIsObject = true end
    local subject = {}
    for i = 1, #tokens do
        if i < first or i > last then subject[#subject + 1] = tokens[i] end
    end
    return unit, subject, info
end

-- Request analysis --------------------------------------------------------

local OPACITY_FOLD_WORDS = { fade = true, faded = true, fades = true, fading = true, dim = true, dimmer = true }
local DIMENSION_WORDS = { zoom = true, opacity = true, width = true, height = true, thickness = true, strength = true,
    spacing = true, size = true, scale = true, softness = true }

local function MentionsOpacityFold(tokens)
    for i = 1, #tokens do if OPACITY_FOLD_WORDS[tokens[i]] then return true end end
    return false
end

local function AnalyseSubject(subjectTokens, rawText, opacityFold, frameIsObject)
    local text = table.concat(subjectTokens, " ")
    text = ApplyPhraseFolds(text)
    -- "only show ... when in a group" hides the frame everywhere else. Only
    -- when the frame itself is the object: "only show the texture layer in
    -- combat" is that layer's visibility choice.
    if frameIsObject and text:find("%f[%a]only%f[%A]") and (text:find("%f[%a]show%f[%A]") or text:find("%f[%a]visible%f[%A]")) then
        if text:find("in group", 1, true) then text = "hide solo"
        elseif text:find("in combat", 1, true) then text = "hide out of combat"
        elseif text:find("out of combat", 1, true) then text = "hide in combat"
        elseif text:find("notarget", 1, true) or text:find("a target", 1, true) then text = "hide notarget"
        end
    end
    local analysis = {
        text = text,
        content = {},        -- { word = <canonical request word>, forms = {...}, soft = bool }
        hardCount = 0,
        comparative = nil,   -- { dimension = "size", sign = 1 }
        number = nil,
        percent = false,
        colorWord = nil,
        polarity = nil,
        verbHide = false,
        verbShow = false,
        movement = false,
        hasIdiomFold = text ~= table.concat(subjectTokens, " "),
    }
    analysis.movement = ContainsAny(text, MOVEMENT_VERBS)
    -- A bare noun phrase ("focus castbar interrupt", as the compound splitter
    -- hands fragments over) states no intent; only a verb, a value or a
    -- direction turns a mention into a request.
    analysis.hasVerb = false
    analysis.neutralOnly = true
    analysis.hasNeutralVerb = false
    for token in text:gmatch("%S+") do
        if INTENT_VERBS[token] then
            analysis.hasVerb = true
            if NEUTRAL_VERBS[token] then analysis.hasNeutralVerb = true else analysis.neutralOnly = false end
        end
    end
    analysis.verbHide = ContainsAny(text, HIDE_VERBS)
    analysis.verbShow = ContainsAny(text, SHOW_VERBS)
    local polarity = DetectBoolean(text)
    -- "remove the border" states a polarity the boolean reader does not
    -- know; the verb lists above do.
    if polarity == nil and analysis.verbHide and not analysis.verbShow then polarity = false end
    if polarity == nil and analysis.verbShow and not analysis.verbHide then polarity = true end
    analysis.polarity = polarity
    -- Only a standalone number is a value; "2d" is a choice name, and the 3
    -- in "texture layer 3" is part of the name.
    local nameDigitSet = {}
    for noun, digit in text:gmatch("(%a+)%s+(%d+)") do
        if noun == "layer" or noun == "custom" or noun == "container" or noun == "slot" or noun == "aura" then
            nameDigitSet[digit] = true
        end
    end
    for token in text:gmatch("%S+") do
        local numeric = token:match("^[-+]?%d+%.?%d*$") or token:match("^[-+]?%d+%.?%d*%%$")
        if numeric and nameDigitSet[token] then numeric = nil end
        if numeric then
            analysis.number = tonumber((numeric:gsub("%%$", "")))
            analysis.percent = token:sub(-1) == "%" or text:find("%d+%s*%%") ~= nil or text:find("%d+%s*percent") ~= nil
            break
        end
    end
    -- Every word as spoken, stop words included: a label word the player DID
    -- say ("keep" in Keep Text & Portrait Visible) is never an extra.
    analysis.rawSet = {}
    for token in text:gmatch("%S+") do analysis.rawSet[token] = true end
    local seen = {}
    -- "texture layer 3", "custom 2": a digit right behind one of these nouns
    -- is part of the control's name, never its value.
    local nameDigits = {}
    for noun, digit in text:gmatch("(%a+)%s+(%d+)") do
        if noun == "layer" or noun == "custom" or noun == "container" or noun == "slot" or noun == "aura" then
            nameDigits[digit] = true
        end
    end
    for token in text:gmatch("%S+") do
        local handled = false
        if nameDigits[token] then
            if not seen[token] then
                seen[token] = true
                analysis.content[#analysis.content + 1] = { word = token, forms = { token }, soft = false }
                analysis.hardCount = analysis.hardCount + 1
            end
            handled = true
        elseif token:match("^[-+]?%d+%.?%d*%%?$") then
            handled = true
        elseif COMPARATIVES[token] then
            local spec = COMPARATIVES[token]
            -- A bar gets thinner by height; only borders and outlines have a
            -- thickness.
            if spec[1] == "thickness" and (text:find("bar", 1, true) or text:find("frame", 1, true))
                and not text:find("border", 1, true) and not text:find("outline", 1, true)
            then
                spec = { "height", spec[2] }
            end
            analysis.comparative = analysis.comparative or { dimension = spec[1] or nil, sign = spec[2] }
            -- "increase"/"reduce" only give the direction; the dimension must
            -- be named by the sentence itself.
            -- "zoom in"/"opacity bigger": the dimension is already in the
            -- sentence, so the comparative only supplies the direction.
            local dimensionStated = false
            if spec[1] == "size" then
                for j = 1, #analysis.content do
                    if DIMENSION_WORDS[analysis.content[j].word] then dimensionStated = true end
                end
            end
            if spec[1] and not seen[spec[1]] and not dimensionStated then
                seen[spec[1]] = true
                analysis.content[#analysis.content + 1] = { word = spec[1], forms = { spec[1] }, soft = false, dimension = true }
                analysis.hardCount = analysis.hardCount + 1
            end
            handled = true
        elseif COLOR_WORDS[token] then
            analysis.colorWord = analysis.colorWord or token
            handled = true
        elseif NUMBER_UNIT_TOKENS[token] and (analysis.number ~= nil or token == "px" or token == "pixels" or token == "pixel") then
            -- "percent" next to a number is its unit; on its own ("show only
            -- percent") it names what to show.
            if token == "point" or token == "pt" or token == "points" then
                -- "16 point" is a font size.
                for _, w in ipairs({ "font", "size" }) do
                    if not seen[w] then
                        seen[w] = true
                        analysis.content[#analysis.content + 1] = { word = w, forms = { w }, soft = w == "font" }
                        if w ~= "font" then analysis.hardCount = analysis.hardCount + 1 end
                    end
                end
            end
            handled = true
        elseif STOP_WORDS[token] then
            handled = true
        end
        if not handled and not seen[token] then
            seen[token] = true
            local forms = WordForms(token)
            -- "fade" is first tried as the literal word (Range Fade, Fade
            -- Frame Out of Combat); only the second pass reads it as opacity.
            if not opacityFold and OPACITY_FOLD_WORDS[token] then forms = { token } end
            local soft = SOFT_TOKENS[token] == true
            analysis.content[#analysis.content + 1] = { word = token, forms = forms, soft = soft }
            if not soft then analysis.hardCount = analysis.hardCount + 1 end
        end
    end
    -- "zoom the portrait in": the verb itself is the comparative.
    if not analysis.comparative and analysis.number == nil and text:find("%f[%a]zoom%f[%A]") then
        analysis.comparative = { dimension = "zoom", sign = text:find("%f[%a]out%f[%A]") and -1 or 1 }
    end
    -- "a bit lower" / "higher" with no dimension named is a MOVE, which the
    -- offset lanes own; only "lower the opacity" states a dimension.
    if analysis.comparative and not analysis.comparative.dimension then
        local dimensionNamed = false
        for i = 1, #analysis.content do
            if DIMENSION_WORDS[analysis.content[i].word] then dimensionNamed = true end
        end
        if not dimensionNamed and (text:find("%f[%a]lower%f[%A]") or text:find("%f[%a]higher%f[%A]")
            or text:find("%f[%a]raise%f[%A]")) then
            analysis.movement = true
        end
    end
    -- With a comparative in the sentence, a dimension word IS the dimension
    -- ("too narrow, widen it" folds to width), never a vague single word.
    if analysis.comparative then
        for i = 1, #analysis.content do
            if DIMENSION_WORDS[analysis.content[i].word] then analysis.content[i].dimension = true end
        end
    end
    -- Opacity idioms ("fade ... a bit") state a direction without a
    -- comparative word.
    if opacityFold and not analysis.comparative and analysis.number == nil then
        if text:find("%f[%a]fade%f[%A]") or text:find("%f[%a]faded%f[%A]") or text:find("%f[%a]dim%f[%A]") then
            analysis.softOpacityDown = true
        end
    end
    if text:find("%f[%a]opacity%s+50%%") or text:find("%f[%a]opacity%s+100%%") then
        analysis.number = FirstNumber(text)
        analysis.percent = true
    end
    return analysis
end

-- Per-unit control index --------------------------------------------------

local unitIndexCache = {}
local unitIndexSettingsRef, unitIndexSettingsCount

local function UnitLabelWords(unit)
    local words = { [unit] = true }
    if unit == "targettarget" then words["target"] = true; words["tot"] = true end
    if unit == "focustarget" then words["focus"] = true; words["target"] = true end
    return words
end

local function LabelTokenSet(text, unitWords)
    local set = {}
    -- "(War Mode/PvP)" explains the control; it is not part of its name.
    local norm = MaskTargetIdioms(Normalize((tostring(text or ""):gsub("%b()", " "))))
    norm = ApplyPhraseFolds(norm)
    for token in norm:gmatch("%S+") do
        if not unitWords[token] and token ~= "of" and token ~= "the" and token ~= "a" and token ~= "an"
            and token ~= "to" and token ~= "on" and token ~= "off" and token ~= "with" and token ~= "for"
            and token ~= "from" and token ~= "into" and token ~= "by" and token ~= "at" and token ~= "as"
            and token ~= "&" and token ~= "/" and token ~= "(" and token ~= ")" and token ~= "and"
            and token ~= "spieler" and token ~= "ziel" and token ~= "fokus"
        then
            set[CanonicalWord(token)] = true
            if PluralFoldWord then
                local folded = PluralFoldWord(token)
                if folded and folded ~= "" then set[CanonicalWord(folded)] = true end
            end
        end
    end
    return set
end

local function ValueTokenSet(setting)
    -- Single-word choices cover a request word on their own; a multi-word
    -- choice ("rested blizzard animated", "class color") only covers its
    -- words when the sentence names ALL of them, or "blizzard" in "use the
    -- blizzard frame" would point at a rested-indicator symbol.
    local single, phrases = {}, {}
    local function addValueText(value)
        local norm = Normalize(tostring(value):gsub("_", " "))
        local tokens = {}
        for token in norm:gmatch("%S+") do
            tokens[#tokens + 1] = token
        end
        if SYMBOL_VALUES[tostring(value)] then single[tostring(value)] = true end
        if #tokens == 1 then
            local token = tokens[1]
            single[token] = true
            single[CanonicalWord(token)] = true
            local stem = token:match("^(%a+)ed$")
            if stem and #stem >= 4 then
                single[stem] = true
                if stem:sub(-1) ~= "e" then single[stem .. "e"] = true end
            end
        elseif #tokens > 1 then
            local phrase = {}
            for i = 1, #tokens do phrase[#phrase + 1] = CanonicalWord(tokens[i]) end
            phrases[#phrases + 1] = phrase
        end
    end
    if setting.type == "enum" or setting.type == "string" then
        if type(setting.values) == "table" then
            for i = 1, #setting.values do addValueText(setting.values[i]) end
        end
        if type(setting.valueLabels) == "table" then
            for _, label in pairs(setting.valueLabels) do addValueText(label) end
        end
        -- Value ALIASES stay out: "hp bar" as a synonym for the absorb
        -- anchor's "follow" choice made "health" look like that control's
        -- word. The enum reader still honours aliases when a value is read.
    end
    return single, phrases
end

-- The value words a sentence may claim for a control: every single-word
-- choice, plus the words of any multi-word choice the sentence spells out.
local function ValueCoverage(entry, analysis)
    local covered = {}
    for token in pairs(entry.valueSet) do covered[token] = true end
    local phrases = entry.valuePhrases
    if phrases and #phrases > 0 then
        local requestForms = {}
        for i = 1, #analysis.content do
            for _, form in ipairs(analysis.content[i].forms) do requestForms[form] = true end
        end
        for i = 1, #phrases do
            local phrase = phrases[i]
            local missing = 0
            for j = 1, #phrase do
                if not requestForms[phrase[j]] then missing = missing + 1 end
            end
            -- A long choice name may drop one category word: "crossed swords"
            -- names weapon_swords_crossed. Two-word choices need both words,
            -- so "class" alone never claims CLASS_COLOR.
            if missing == 0 or (#phrase >= 3 and missing == 1) then
                for j = 1, #phrase do covered[phrase[j]] = true end
            end
        end
    end
    return covered
end

local function SettingBelongsToUnit(setting, unit)
    local key = tostring(setting.key or "")
    if key:sub(1, #unit + 1) == unit .. "." then return true end
    for _, prefix in ipairs({ "barScope.", "fontScope." }) do
        if key:sub(1, #prefix + #unit + 1) == prefix .. unit .. "." then return true end
    end
    return false
end

local function EnsureUnitIndex(unit)
    local Registry = A.Registry
    local settings = Registry and type(Registry.AllSettings) == "function" and Registry:AllSettings() or nil
    if type(settings) ~= "table" then return nil end
    if unitIndexSettingsRef ~= settings or unitIndexSettingsCount ~= #settings then
        unitIndexCache = {}
        unitIndexSettingsRef, unitIndexSettingsCount = settings, #settings
    end
    local cached = unitIndexCache[unit]
    if cached then return cached end
    local unitWords = UnitLabelWords(unit)
    local entries = {}
    for i = 1, #settings do
        local setting = settings[i]
        if type(setting) == "table" and type(setting.set) == "function" and SettingBelongsToUnit(setting, unit) then
            local labelSet = LabelTokenSet(setting.label or setting.key, unitWords)
            local labelCount = 0
            for _ in pairs(labelSet) do labelCount = labelCount + 1 end
            -- Each alias stays its own phrase: a word inside an alias only
            -- counts when the sentence names that whole alias, or "percent"
            -- inside "hp percent decimals" would claim any percent request.
            local aliasSets = {}
            local aliases = setting.aliases
            if type(aliases) == "table" then
                for j = 1, #aliases do
                    if type(aliases[j]) == "string" then
                        local set = LabelTokenSet(aliases[j], unitWords)
                        local count = 0
                        for _ in pairs(set) do count = count + 1 end
                        if count > 0 then aliasSets[#aliasSets + 1] = set end
                    end
                end
            end
            entries[#entries + 1] = {
                setting = setting,
                labelSet = labelSet,
                labelCount = labelCount,
                aliasSets = aliasSets,
                valueSet = select(1, ValueTokenSet(setting)),
                valuePhrases = select(2, ValueTokenSet(setting)),
                attribute = tostring(setting.attribute or setting.key:match("([^.]+)$") or ""),
                hideNamed = (tostring(setting.attribute or ""):find("^loadCondHide") ~= nil)
                    or (Normalize(setting.label or ""):find("%f[%a]hide%f[%A]") ~= nil),
            }
        end
        if i % 64 == 0 and A and type(A.MaybeYield) == "function" then A.MaybeYield() end
    end
    unitIndexCache[unit] = entries
    return entries
end

function P.UnitScopeIndexReady(unit)
    return unitIndexCache[unit] ~= nil
end

-- Matching ----------------------------------------------------------------

local function TokenCovered(item, entry, namedAlias, valueCover)
    local forms = item.forms
    for i = 1, #forms do
        local form = forms[i]
        if entry.labelSet[form] or (valueCover and valueCover[form]) or (namedAlias and namedAlias[form]) then return true, form end
    end
    if entry.setting.type == "color" then
        for i = 1, #forms do if forms[i] == "color" then return true, "color" end end
    end
    return false
end

-- The alias the sentence spells out in full (every non-soft alias word is
-- among the sentence's word forms), if any.
local function FullyNamedAlias(entry, analysis)
    local sets = entry.aliasSets
    if not sets or #sets == 0 then return nil end
    local requestForms = {}
    for i = 1, #analysis.content do
        for _, form in ipairs(analysis.content[i].forms) do requestForms[form] = true end
    end
    for i = 1, #sets do
        local set = sets[i]
        local complete = true
        for token in pairs(set) do
            if not requestForms[token] and not SOFT_TOKENS[token] and not LABEL_QUALIFIERS[token] then
                complete = false
                break
            end
        end
        if complete then return set end
    end
    return nil
end

local function FullValueNamed(entry, analysis)
    local setting = entry.setting
    if type(setting.values) ~= "table" then return false end
    local requestForms = {}
    for i = 1, #analysis.content do
        for _, form in ipairs(analysis.content[i].forms) do requestForms[form] = true end
    end
    for i = 1, #setting.values do
        local value = setting.values[i]
        local all, any = true, false
        for token in Normalize(tostring(value):gsub("_", " ")):gmatch("%S+") do
            any = true
            if not requestForms[CanonicalWord(token)] then all = false end
        end
        if any and all then return true end
        local label = type(setting.valueLabels) == "table" and setting.valueLabels[value] or nil
        if label then
            all, any = true, false
            for token in Normalize(tostring(label)):gmatch("%S+") do
                any = true
                if not requestForms[CanonicalWord(token)] then all = false end
            end
            if any and all then return true end
        end
    end
    return false
end

function P.UnitScopeAnalyse(text)
    local norm = Normalize(text)
    local unit, subjectTokens, info = P.UnitScopeFromNaturalText(norm)
    if not unit then return nil end
    local analysis = AnalyseSubject(subjectTokens, text, false, info.frameIsObject)
    local words = {}
    for i = 1, #analysis.content do
        local item = analysis.content[i]
        words[#words + 1] = item.word .. (item.soft and "(soft)" or "") .. (item.dimension and "(dim)" or "")
    end
    return unit, table.concat(words, ","), analysis, info
end

local function CandidateScore(entry, analysis)
    local matched = {}
    local valueHits = 0
    local namedAlias = FullyNamedAlias(entry, analysis)
    local valueCover = ValueCoverage(entry, analysis)
    local debugThis = P._unitScopeDebugKey and P._unitScopeDebugKey == tostring(entry.setting.key)
    if debugThis then
        local l = {} for t in pairs(entry.labelSet) do l[#l + 1] = t end
        print("    debug " .. entry.setting.key .. " attr=" .. tostring(entry.attribute) .. " label={" .. table.concat(l, ",") .. "}")
    end
    for i = 1, #analysis.content do
        local item = analysis.content[i]
        local covered, form = TokenCovered(item, entry, namedAlias, valueCover)
        -- The frame's main bar IS the health bar: "make the health bar fill
        -- in chunks" means Chunked Fill even though that label never says
        -- health. Only for bar-generic controls that name no other element.
        if not covered and (item.word == "health" or item.word == "hp" or item.word == "healthbar")
            and (analysis.rawSet and (analysis.rawSet.bar or analysis.rawSet.bars))
            and not (entry.labelSet.power or entry.labelSet.hp or entry.labelSet.name or entry.labelSet.text
                or entry.labelSet.portrait or entry.labelSet.absorb or entry.labelSet.heal)
            and (entry.labelSet.fill or entry.labelSet.bar or entry.labelSet.gradient or entry.labelSet.texture
                or entry.labelSet.chunked or entry.labelSet.smooth)
        then
            covered, form = true, "hp"
        end
        if debugThis then
            print("    debug item " .. tostring(item.word) .. " forms={" .. table.concat(item.forms, ",") .. "} covered=" .. tostring(covered) .. " via=" .. tostring(form)
                .. " label=" .. tostring(form and entry.labelSet[form]) .. " value=" .. tostring(form and entry.valueSet[form]) .. " alias=" .. tostring(form and namedAlias and namedAlias[form]))
        end
        -- A soft word never picks a choice: "default" in "the default
        -- blizzard frame" is not the Rested Indicator Symbol's DEFAULT.
        if covered and item.soft and not entry.labelSet[form] then covered = false end
        if covered then
            matched[form] = true
            if valueCover[form] and not entry.labelSet[form] then valueHits = valueHits + 1 end
        elseif not item.soft then
            if debugThis then print("    debug uncovered: " .. tostring(item.word)) end
            return nil
        end
    end
    -- Some label words narrow WHICH control is meant; a sentence that never
    -- said them means the plain control instead ("make the power bar wider"
    -- is not the detached bar's width).
    for token in pairs(entry.labelSet) do
        if not matched[token] and (REQUIRED_QUALIFIERS[token] or token:match("^%d+$")) then return nil end
    end
    -- Every extra label word the sentence never said costs precision.
    local extras = 0
    for token in pairs(entry.labelSet) do
        if not matched[token] and not SOFT_TOKENS[token] and not LABEL_QUALIFIERS[token]
            and not (analysis.rawSet and analysis.rawSet[token])
            and not (analysis.verbHide and (token == "hide" or token == "hidden"))
            and not (analysis.verbShow and token == "show")
        then
            extras = extras + 1
        end
    end
    -- A control whose name says much more than the sentence did is not what
    -- the sentence meant: "turn off castbar" must not reach Show Castbar
    -- Interrupt just because the frame owns no castbar control of its own.
    if extras > analysis.hardCount then return nil end
    local score = 1000 - extras * 10
    -- "health bar" and "health text" are different things even though both
    -- words are generic on their own.
    local rawSet = analysis.rawSet or {}
    if (rawSet.bar or rawSet.bars) and entry.labelSet.text and not entry.labelSet.bar then score = score - 15 end
    if rawSet.text and entry.labelSet.bar and not entry.labelSet.text then score = score - 15 end
    if valueHits > 0 then
        -- A choice the sentence spells out in full ("class" for CLASS)
        -- outranks one it only touches ("class" inside CLASS_COLOR).
        score = score + (FullValueNamed(entry, analysis) and 5 or 2)
    end
    if PRIMARY_TOGGLE_ATTRS[entry.attribute] then score = score + 2 end
    -- "show the target frame out of combat" is the frame's visibility rule,
    -- not the fade that happens to share the words.
    if analysis.frameIsObject and entry.attribute:find("^loadCond") then score = score + 4 end
    -- "anchor the player frame from its top left corner" is the frame's own
    -- anchor point, not the name text's.
    if analysis.frameIsObject and FRAME_LEVEL_ATTRS[entry.attribute] then score = score + 6 end
    -- A generic noun the sentence used ("frame", "bar", "text") that the
    -- label also carries is a real point of agreement.
    for _, noun in ipairs({ "frame", "bar", "text" }) do
        if rawSet[noun] and entry.labelSet[noun] then score = score + 5 end
    end
    if entry.hideNamed and analysis.verbHide then score = score + 3 end
    if entry.setting.generated then score = score - 1 end
    return score, extras
end

local function TypeCompatible(entry, analysis)
    local setting = entry.setting
    local kind = setting.type
    if analysis.comparative or analysis.softOpacityDown then
        return kind == "number"
    end
    if analysis.number ~= nil then
        if kind == "number" then return true end
        -- A number can still name an enum choice (layer 5 is not; "16 point" is
        -- handled as font size), so only number controls take numbers.
        return false
    end
    if analysis.colorWord then
        return kind == "color" or ValueCoverage(entry, analysis)["color"] ~= nil
    end
    if analysis.polarity ~= nil then
        if kind == "boolean" then return true end
        if (kind == "enum" or kind == "string") and type(setting.values) == "table" then
            if analysis.polarity == false then
                for i = 1, #setting.values do
                    if ONOFF_ENUM_OFF_VALUES[tostring(setting.values[i])] then return true end
                end
            end
            -- An enum whose choice the sentence spells is fine with a polarity
            -- word around it ("show the portrait on the left").
            local valueCover = ValueCoverage(entry, analysis)
            for i = 1, #analysis.content do
                local item = analysis.content[i]
                for _, form in ipairs(item.forms) do
                    if valueCover[form] and not entry.labelSet[form] then return true end
                end
            end
        end
        return false
    end
    return true
end

local function EnumValueFromContent(setting, analysis, valueText)
    local symbolValue
    for token in valueText:gmatch("%S+") do
        if SYMBOL_VALUES[token] then symbolValue = token end
    end
    if symbolValue and type(setting.values) == "table" then
        for i = 1, #setting.values do
            if tostring(setting.values[i]) == symbolValue then return symbolValue end
        end
    end
    local value = P.EnumValueForText and P.EnumValueForText(setting, valueText) or nil
    if value ~= nil then return value end
    -- Token-set fallback: the choice whose own words the sentence covers best.
    if type(setting.values) ~= "table" then return nil end
    local requestForms = {}
    for i = 1, #analysis.content do
        for _, form in ipairs(analysis.content[i].forms) do requestForms[form] = true end
    end
    local best, bestHits, tie = nil, 0, false
    for i = 1, #setting.values do
        local candidate = setting.values[i]
        local hits, total = 0, 0
        for token in Normalize(tostring(candidate):gsub("_", " ")):gmatch("%S+") do
            total = total + 1
            if requestForms[CanonicalWord(token)] then hits = hits + 1 end
        end
        local label = type(setting.valueLabels) == "table" and setting.valueLabels[candidate] or nil
        if label then
            local lhits, ltotal = 0, 0
            for token in Normalize(tostring(label)):gmatch("%S+") do
                ltotal = ltotal + 1
                if requestForms[CanonicalWord(token)] then lhits = lhits + 1 end
            end
            if lhits > hits or (lhits == hits and ltotal < total) then hits, total = lhits, ltotal end
        end
        if hits > 0 and hits == total then
            if hits > bestHits then best, bestHits, tie = candidate, hits, false
            elseif hits == bestHits then tie = true end
        end
    end
    if best ~= nil and not tie then return best end
    if best ~= nil and tie then
        -- Prefer the value whose every token was said over a longer value
        -- that shares them ("center" over "frame center" needs the reverse,
        -- so only accept a tie when one candidate is spelled out in full).
        return nil
    end
    return nil
end

-- The steps the dedicated lanes use for a comparative with no amount: frame
-- widths move by 25, frame heights by 5, sizes and thicknesses by 1.
local function RelativeStep(setting, sign, dimension)
    local maxValue = tonumber(setting.max)
    local attribute = tostring(setting.attribute or "")
    local label = tostring(setting.label or ""):lower()
    if dimension == "width" or label:match("width$") then return 25 * sign end
    if dimension == "height" or label:match("height$") then
        -- A thin bar (max 20) grows by a pixel; a frame-sized height by five.
        return ((maxValue and maxValue <= 24) and 1 or 5) * sign
    end
    if dimension == "zoom" or label:match("zoom$") then return 10 * sign end
    if label:match("opacity$") or label:match("alpha$") or label:match("strength$") then
        return (maxValue and maxValue > 1 and 10 or 0.1) * sign
    end
    local step = tonumber(setting.relativeStep) or tonumber(setting.step)
    if not step then
        if maxValue and maxValue <= 1 then step = 0.1
        elseif maxValue and maxValue <= 10 then step = 1
        elseif maxValue and maxValue <= 100 and (setting.percent or tostring(setting.label or ""):lower():find("opacity", 1, true)) then step = 10
        else step = 2 end
    end
    if maxValue and maxValue <= 1 and step >= 1 then step = 0.1 end
    return step * sign
end

local function DeriveChange(entry, analysis, subjectText, raw)
    local setting = entry.setting
    local kind = setting.type
    if kind == "number" then
        -- "increase target width to 250" states where to end up, not how far
        -- to move: an absolute target wins over the comparative.
        local absoluteTarget = analysis.number ~= nil and type(P.HasAbsoluteNumberTarget) == "function"
            and P.HasAbsoluteNumberTarget(subjectText)
        if (analysis.comparative or analysis.softOpacityDown) and not absoluteTarget then
            local sign = analysis.comparative and analysis.comparative.sign or -1
            local explicitAmount = type(A._RelativeNumberAmountForText) == "function"
                and A._RelativeNumberAmountForText(subjectText) or nil
            local delta
            if explicitAmount ~= nil and P.RelativeNumberDeltaForText then
                delta = P.RelativeNumberDeltaForText(setting, subjectText)
            end
            if delta == nil or (delta > 0) ~= (sign > 0) then
                delta = RelativeStep(setting, sign, analysis.comparative and analysis.comparative.dimension)
            end
            return { setting = setting, relativeDelta = delta }
        end
        if analysis.number ~= nil then
            local value = P.ValueForRegistrySetting and P.ValueForRegistrySetting(setting, subjectText, raw) or nil
            if value == nil then value = analysis.number end
            local maxValue = tonumber(setting.max)
            if analysis.percent and maxValue and value > maxValue and maxValue <= 1 then value = value / 100 end
            if type(value) ~= "number" then return nil end
            return { setting = setting, value = value, explicit = true }
        end
        return nil
    end
    if kind == "boolean" then
        local value
        if entry.hideNamed then
            -- "hide my frame while mounted" ENABLES Hide Mounted; the registry
            -- reader's show/hide lists read the verb the other way round, so
            -- only an explicit on/off wording is left to it.
            if ContainsAny(subjectText, EXPLICIT_TOGGLE_TERMS) and P.ValueForRegistrySetting then
                value = P.ValueForRegistrySetting(setting, subjectText, raw)
            end
            if value == nil and analysis.polarity ~= nil then value = not analysis.polarity end
        else
            -- "i want to change target health text" states no polarity even
            -- though "i want" reads as on: a neutral verb without an explicit
            -- on/off keeps it a value question.
            if analysis.hasNeutralVerb and not ContainsAny(subjectText, EXPLICIT_TOGGLE_TERMS) then return nil end
            -- The registry reader carries per-control semantics ("attach" is
            -- off for the detach toggle) and the explicit on/off grammar.
            if P.ValueForRegistrySetting then value = P.ValueForRegistrySetting(setting, subjectText, raw) end
            if value == nil then value = analysis.polarity end
        end
        if value == nil then
            -- The sentence names the control and states no polarity: the
            -- mention itself asks for it ("mirror the texture layer") -- but a
            -- neutral "set X" states nothing and stays a value question.
            -- "i want to change target health text" wants to CHANGE it, not to
            -- turn it on: any neutral verb keeps this a value question.
            if analysis.neutralOnly or analysis.hasNeutralVerb then return nil end
            value = true
        end
        return { setting = setting, value = value }
    end
    if kind == "color" then
        local value = P.ValueForRegistrySetting and P.ValueForRegistrySetting(setting, subjectText, raw) or nil
        if value == nil then return nil end
        return { setting = setting, value = value, explicit = true }
    end
    if kind == "enum" or kind == "string" then
        if type(setting.values) ~= "table" or #setting.values == 0 then return nil end
        -- Read the choice from the words that are NOT the control's own name:
        -- "use the class icon as my portrait" must not let "portrait" pick
        -- the 2D render through a value alias.
        local valueWords = {}
        for i = 1, #analysis.content do
            local item = analysis.content[i]
            -- Only the word AS SPOKEN counts as the control's own name: "mana"
            -- folds to "power" (the label's word) but is itself the MANA choice
            -- of Displayed Power Resource.
            if not entry.labelSet[item.word] and not entry.labelSet[CanonicalWord(item.word)] then
                valueWords[#valueWords + 1] = item.word
            end
        end
        local value
        if #valueWords > 0 then value = EnumValueFromContent(setting, analysis, table.concat(valueWords, " ")) end
        -- The whole sentence may still name the choice ("set ... to outline")
        -- when a connector introduces it; without one, a word that is only
        -- the control's own name ("change player font outline") states no
        -- value and the sentence stays a value question.
        if value == nil and (subjectText:find(" to ", 1, true) or subjectText:find(" as ", 1, true)
            or subjectText:find(" = ", 1, true) or subjectText:find(" into ", 1, true))
        then
            value = EnumValueFromContent(setting, analysis, subjectText)
        end
        local explicit = value ~= nil and FullValueNamed(entry, analysis)
        if value == nil and analysis.polarity == false then
            for i = 1, #setting.values do
                if ONOFF_ENUM_OFF_VALUES[tostring(setting.values[i])] then value = setting.values[i]; break end
            end
        end
        if value == nil then return nil end
        return { setting = setting, value = value, explicit = explicit }
    end
    return nil
end

local SLOT_WORDS = { left = true, center = true, right = true }

local function SlotFamily(entry)
    -- "hpTextLeftHidePercentSymbol" -> "hpText*HidePercentSymbol"
    local attribute = entry.attribute
    for _, slot in ipairs({ "Left", "Center", "Right" }) do
        local replaced, count = attribute:gsub(slot, "*")
        if count == 1 then return replaced end
    end
    return nil
end

-- Registry settings declare companion writes (a scoped font control switches
-- its scope's override on). Mirror the exact-alias path so a plan from here
-- is the same transaction the label command would produce.
local function AddCompanions(changes, raw)
    local Registry = A.Registry
    local seen = {}
    for i = 1, #changes do seen[tostring(changes[i].setting.key or "")] = true end
    local primaryCount = #changes
    for i = 1, primaryCount do
        local change = changes[i]
        local companions = type(change.setting) == "table" and change.setting.companionChanges or nil
        if type(companions) == "table" then
            for j = 1, #companions do
                local spec = companions[j]
                local companionKey = tostring(spec and spec.key or "")
                local companionSetting = companionKey ~= "" and Registry and Registry:GetSetting(companionKey) or nil
                local whenValue = spec and spec.whenValue
                local textOk = true
                if type(spec.whenTextHas) == "table" then
                    textOk = false
                    local hay = " " .. Normalize(raw) .. " "
                    for k = 1, #spec.whenTextHas do
                        local term = Normalize(spec.whenTextHas[k])
                        if term ~= "" and hay:find(" " .. term .. " ", 1, true) then textOk = true break end
                    end
                end
                if companionSetting and not seen[companionKey] and (whenValue == nil or whenValue == change.value) and textOk then
                    local value = spec.value
                    if type(value) == "function" then value = value(spec, companionSetting, raw, change.value) end
                    local delta = spec.relativeDelta
                    if type(delta) == "function" then delta = delta(spec, companionSetting, raw, change.value) end
                    if value ~= nil or delta ~= nil then
                        seen[companionKey] = true
                        local companion = { setting = companionSetting, value = value, relativeDelta = delta, companion = true }
                        if spec.prepend == true then table.insert(changes, 1, companion) else changes[#changes + 1] = companion end
                    end
                end
            end
        end
    end
    return changes
end

-- A scoped font/bar control only takes effect while its scope's override is
-- on; the dedicated lanes write both, so this plan does too.
local function AddScopeOverrides(changes)
    local Registry = A.Registry
    local seen = {}
    for i = 1, #changes do seen[tostring(changes[i].setting.key or "")] = true end
    local count = #changes
    for i = 1, count do
        local key = tostring(changes[i].setting.key or "")
        local prefix, scope = key:match("^(fontScope)%.([%w_]+)%.")
        if not prefix then prefix, scope = key:match("^(barScope)%.([%w_]+)%.") end
        if prefix and scope ~= "shared" and not key:match("%.override$") then
            local overrideKey = prefix .. "." .. scope .. ".override"
            local override = Registry and Registry:GetSetting(overrideKey)
            if override and not seen[overrideKey] then
                seen[overrideKey] = true
                changes[#changes + 1] = { setting = override, value = true, companion = true }
            end
        end
    end
    return changes
end

local function BuildPlan(changes, unit, label, summary, raw)
    changes = AddScopeOverrides(AddCompanions(changes, raw))
    return {
        kind = "changes",
        changes = changes,
        bulkSafe = #changes > 1 and true or nil,
        label = label,
        summary = summary,
        raw = raw,
        sourceText = raw,
        exactSettingMutation = true,
        unitScoped = unit,
    }
end

local CLAUSE_MARKERS = { "when", "while", "whenever", "if", "once", "unless", "after", "before", "during" }
local VAGUE_SINGLE_WORDS = {}
for word in ([[inline color position anchor offset layer size opacity style mode background border outline
detached custom texture symbol icon indicator text slot delimiter spacing width height thickness
strata level shape placement render direction alignment alpha transparency transparent fade scale
font gradient]]):gmatch("%S+") do
    VAGUE_SINGLE_WORDS[word] = true
end
VAGUE_SINGLE_WORDS["level"] = nil

local actionAliasList, actionAliasCount

local function ActionAliases()
    local Registry = A.Registry
    local actions = Registry and type(Registry.AllActions) == "function" and Registry:AllActions() or {}
    if actionAliasList and actionAliasCount == #actions then return actionAliasList end
    local list = {}
    for i = 1, #actions do
        local action = actions[i]
        if type(action) == "table" then
            for _, field in ipairs({ "aliases", "exactAliases" }) do
                local aliases = action[field]
                for j = 1, #(aliases or {}) do
                    local alias = Normalize(aliases[j])
                    -- One-word aliases ("preview") would veto ordinary sentences.
                    if alias:find(" ", 1, true) then list[#list + 1] = " " .. alias .. " " end
                end
            end
        end
    end
    actionAliasList, actionAliasCount = list, #actions
    return list
end

function MentionsActionAlias(norm)
    local hay = " " .. norm .. " "
    local list = ActionAliases()
    for i = 1, #list do
        if hay:find(list[i], 1, true) then return true end
    end
    return false
end

local function ResolveAgainstUnit(unit, analysis, raw)
    local subjectText = analysis.text
    local entries = EnsureUnitIndex(unit)
    if not entries then return nil end
    local scored = {}
    for i = 1, #entries do
        local entry = entries[i]
        -- A free-text control (a media pack name, an anchor frame name) can
        -- take no value from words; it must not sit at the top of the ranking
        -- and block a control that can ("use the class icon as my portrait").
        local wordless = entry.setting.type == "string"
            and not (type(entry.setting.values) == "table" and #entry.setting.values > 0)
        local score, extras = CandidateScore(entry, analysis)
        if score and TypeCompatible(entry, analysis) then
            scored[#scored + 1] = { entry = entry, score = score, extras = extras, wordless = wordless }
        end
    end
    if #scored == 0 then return nil end
    -- A control whose visible label the sentence spells out in full is the
    -- one meant, and the longest such label is the most specific: "set Player
    -- Portrait Background Enabled to on" names the generated twin, not the
    -- shorter curated Portrait Background it also contains.
    do
        local best, bestCount
        local rawSet = analysis.rawSet or {}
        for i = 1, #scored do
            local entry = scored[i].entry
            local complete = entry.labelCount > 0
            for token in pairs(entry.labelSet) do
                if not rawSet[token] then complete = false break end
            end
            if complete and (not bestCount or entry.labelCount > bestCount) then
                best, bestCount = scored[i], entry.labelCount
            end
        end
        if best then best.score = best.score + 25 end
    end
    table.sort(scored, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return tostring(a.entry.setting.key) < tostring(b.entry.setting.key)
    end)
    -- Only the best-matching controls may take the sentence. When the best
    -- match cannot derive a value ("set player width" states none), the
    -- sentence is NOT handed down to a lower-ranked control that merely shares
    -- a word -- that is how a boolean once claimed a width request.
    local topScore = scored[1].score
    local resolved = {}
    -- Below the top score only a control whose value the sentence SPELLS
    -- ("class" as a Portrait Render choice) may still take it; an inferred
    -- "on" never may ("set player width" must not reach a boolean). And when
    -- the top control's own name already explains every word ("change
    -- target power bar texture"), the sentence is about THAT control and a
    -- missing value stays a value question -- "power" is its name, not a
    -- choice for some other control.
    local topNamesEverything = true
    for i = 1, #analysis.content do
        local item = analysis.content[i]
        if not item.soft then
            local inLabel = false
            for _, form in ipairs(item.forms) do if scored[1].entry.labelSet[form] then inLabel = true end end
            if not inLabel then topNamesEverything = false end
        end
    end
    -- A wordless top control (a media pack, an anchor frame name) names the
    -- thing the sentence is about; only a stated value may pass it ("use the
    -- class icon AS my portrait" reaches Portrait Render, "change target
    -- power bar texture" stays a value question).
    local connector = subjectText:find(" to ", 1, true) or subjectText:find(" as ", 1, true)
        or subjectText:find(" = ", 1, true) or subjectText:find(" into ", 1, true)
    if scored[1].wordless and topNamesEverything and not connector then return {} end
    local explicitFallthrough = false
    for i = 1, #scored do
        local candidate = scored[i]
        if candidate.score < topScore then
            if #resolved > 0 or (topNamesEverything and not scored[1].wordless) then break end
            explicitFallthrough = true
        end
        local change = not candidate.wordless and DeriveChange(candidate.entry, analysis, subjectText, raw) or nil
        if change and explicitFallthrough and not (change.explicit and candidate.entry.setting.type ~= "boolean") then
            change = nil
        end
        if P._unitScopeDebug then
            print(string.format("    candidate %s score=%d extras=%d -> %s", tostring(candidate.entry.setting.key),
                candidate.score, candidate.extras, change and ("value=" .. tostring(change.value) .. " delta=" .. tostring(change.relativeDelta)) or "no value"))
        end
        if change then resolved[#resolved + 1] = { entry = candidate.entry, change = change } end
    end
    return resolved
end

-- Public: the plan for a sentence about one unit frame, or nil.
function P.UnitScopedNaturalPlan(text, raw, ctx)
    raw = raw or text
    local norm = Normalize(text)
    if norm == "" then return nil end
    if type(P.NonMutatingIntent) == "function" then
        local intent = P.NonMutatingIntent(norm)
        -- "the name on my player frame is too small" reads as a problem
        -- report, yet a "too <adjective>" complaint about one control on one
        -- frame states its own remedy; the readability article would only
        -- tell the player to say exactly that.
        local complaintWithRemedy = intent == "problem" and ContainsAny(norm, {
            "too small", "too tiny", "too big", "too large", "too thin", "too narrow", "too wide", "too short",
            "too tall", "too thick", "too transparent", "too faint", "hard to read", "hard to see",
        })
        -- A terse report ("player name too small") keeps the readability
        -- article the Router pins for it; only a full sentence about one frame
        -- ("the name on my player frame is too small") states its remedy.
        if complaintWithRemedy then
            local words = 0
            for _ in norm:gmatch("%S+") do words = words + 1 end
            if words < 6 or not (norm:find("%f[%a]my%f[%A]") or norm:find("%f[%a]the%f[%A]") or norm:find("%f[%a]this%f[%A]")) then
                complaintWithRemedy = false
            end
        end
        if intent and not complaintWithRemedy then
            if P._unitScopeDebug then print("    stand-down: non-mutating intent " .. tostring(intent)) end
            return nil
        end
    end
    if ContainsAny(norm, AURA_TERMS) then return nil end
    -- A question is never a write. "is there Boss Texture Layer 3 Offset X
    -- in msuf?" carries a digit and a control name, which is exactly the
    -- shape a value-hungry lane mistakes for a command.
    if tostring(raw or ""):find("?", 1, true)
        or norm:match("^is%s") or norm:match("^are%s") or norm:match("^does%s") or norm:match("^do%s+you")
        or norm:match("^did%s") or norm:match("^can%s+i%s") or norm:match("^could%s+i%s") or norm:match("^may%s+i%s")
        or norm:match("^what%s") or norm:match("^which%s") or norm:match("^where%s")
        or norm:match("^why%s") or norm:match("^how%s") or norm:match("^who%s") or norm:match("^whats%s")
        or norm:match("^wheres%s") or norm:match("^hows%s") or norm:match("^tell%s+me%s") or norm:match("^explain%s")
        or norm:match("^any%s+way%s") or norm:match("^is%s+it%s") or norm:match("^isnt%s")
        or (type(A.RouterIsFeatureExistenceQuestion) == "function" and A.RouterIsFeatureExistenceQuestion(raw) == true)
    then
        return nil
    end
    -- "make all text bigger on target" spans several controls; the bulk and
    -- compound lanes own every/all wording ("at all" is emphasis, not scope).
    do
        local bulk = norm:gsub("%f[%a]at%s+all%f[%A]", " ")
        if bulk:find("%f[%a]all%f[%A]") or bulk:find("%f[%a]every%f[%A]") or bulk:find("%f[%a]everything%f[%A]")
            or bulk:find("%f[%a]entire%f[%A]") or bulk:find("%f[%a]whole%f[%A]") or bulk:find("%f[%a]both%f[%A]")
        then
            return nil
        end
    end
    -- Two clauses ("set X to off and set Y to on", "... and Y to 5") are the
    -- compound parser's; one frame's control can never satisfy both.
    do
        local head, tail = norm:match("^(.-)%s+and%s+(.+)$")
        if tail and (tail:match("^set%s") or tail:match("^turn%s") or tail:match("^make%s") or tail:match("^show%s")
            or tail:match("^hide%s") or tail:match("^enable%s") or tail:match("^disable%s") or tail:match("^change%s")
            or tail:match("^put%s") or tail:match("^move%s")
            or (tail:find("%s+to%s+") and head:find("%s+to%s+")))
        then
            return nil
        end
    end
    -- Registry actions ("show all status icons target") keep their parser: a
    -- sentence that contains any action's own alias is never a setting write.
    if MentionsActionAlias(norm) then
        if P._unitScopeDebug then print("    stand-down: action alias") end
        return nil
    end
    -- Text anchors are an action with their own value grammar (A.Parse drops
    -- even the exact-alias pre-pass for them).
    if norm:find(" text anchor", 1, true) and not norm:find("custom value", 1, true) then return nil end
    -- "please don't hide target power text" asks to leave things alone; the
    -- Router's refusal reply owns that, not a write of the opposite.
    do
        local lead = norm:gsub("^%s*please%s+", ""):gsub("^%s*can%s+you%s+", ""):gsub("^%s*could%s+you%s+", "")
        local negated = lead:match("^dont%s+(.*)$") or lead:match("^don%s+t%s+(.*)$") or lead:match("^do%s+not%s+(.*)$")
            or lead:match("^never%s+(.*)$") or lead:match("^stop%s+(.*)$")
        -- "don't show X" hides X; every other negated toggle verb ("don't
        -- hide", "don't turn off", "don't change") asks to leave it alone.
        if negated and not (negated:match("^show%s") or negated:match("^display%s") or negated:match("^showing%s")) then
            return nil
        end
    end
    -- "remove player power text" clears the text slots; the slot lane owns
    -- remove/clear wording on a text area.
    if (norm:find("%f[%a]remove%f[%A]") or norm:find("%f[%a]clear%f[%A]") or norm:find("%f[%a]wipe%f[%A]")
        or norm:find("%f[%a]empty%f[%A]")) and norm:find("%f[%a]text%f[%A]")
    then
        return nil
    end
    -- "put target health text right" selects the text slot tab (a menu
    -- selector action); a bare direction right after a text noun is that
    -- action's grammar, not an anchor or bar write.
    if norm:match("%f[%a]text%s+%(?left%)?$") or norm:match("%f[%a]text%s+right$") or norm:match("%f[%a]text%s+center$")
        or norm:match("%f[%a]text%s+centre$") or norm:match("%f[%a]text%s+middle$")
        or norm:match("%f[%a]name%s+left$") or norm:match("%f[%a]name%s+right$") or norm:match("%f[%a]name%s+center$")
    then
        return nil
    end
    -- A leading "only" restricts the scope override ("only turn on target
    -- power bar gradient"); that lane pairs the write with the scope switch.
    -- Anywhere, "only" marks the scope-override form ("only turn on target
    -- power bar gradient", "set target font outline only to thick") -- unless
    -- a condition follows, which makes it a visibility rule or choice ("only
    -- show the texture layer in combat").
    if norm:find("%f[%a]only%f[%A]") and not ContainsAny(norm, {
        "when", "while", "whenever", "in combat", "out of combat", "in group", "in a group", "in party",
        "solo", "mounted", "resting", "in instance", "in dungeons", "stealthed", "in vehicle", "no target",
    }) then
        if P._unitScopeDebug then print("    stand-down: only") end
        return nil
    end
    if ContainsAny(norm, FOLLOWUP_TERMS) or norm:match("^and%s") or norm:match("%stoo$") or norm:match("^same%s")
        or norm:match("^also%s") or norm:match("^then%s")
    then
        return nil
    end
    local unit, subjectTokens, info = P.UnitScopeFromNaturalText(norm)
    if not unit then return nil end
    local function Attempt(tokensForAttempt, opacityFold)
        local analysis = AnalyseSubject(tokensForAttempt, raw, opacityFold, info.frameIsObject)
        analysis.frameIsObject = info.frameIsObject
        if analysis.movement then return nil, analysis, true end
        if not analysis.hasVerb and analysis.polarity == nil and analysis.number == nil
            and not analysis.comparative and not analysis.colorWord and not analysis.softOpacityDown
        then
            return nil, analysis, true
        end
        if analysis.hardCount == 0 then
            -- Only the frame itself was named ("i want a focus frame", "turn
            -- off my player frame"): that is the root toggle, and only with a
            -- polarity or a wanting verb.
            local polarity = analysis.polarity
            if polarity == nil and analysis.verbHide then polarity = false end
            if polarity == nil and analysis.verbShow then polarity = true end
            if info.frameMentioned and polarity ~= nil and not analysis.comparative and analysis.number == nil then
                local Registry = A.Registry
                local root = Registry and Registry.GetSetting and Registry:GetSetting(unit .. ".enabled")
                if root then
                    return BuildPlan({ { setting = root, value = polarity } }, unit,
                        tostring(root.label or (unit .. " Frame Enabled")),
                        "Changes root Unit Frame visibility.", raw), analysis, true
                end
            end
            return nil, analysis, true
        end
        -- "detach target frame": a verb applied to the frame itself (anchoring,
        -- locking, resetting) belongs to the frame lanes, not to a control that
        -- happens to carry the verb in its name.
        if info.frameIsObject then
            local verbsOnly = true
            for i = 1, #analysis.content do
                local item = analysis.content[i]
                if not item.soft and not INTENT_VERBS[item.word] and not item.dimension then verbsOnly = false end
            end
            if verbsOnly and not analysis.comparative and analysis.number == nil then return nil, analysis, true end
        end
        -- "make target text bigger" names a dimension and a generic noun but
        -- no element; the broad text lane offers Name/HP/Power as choices.
        -- Only the frame itself may take a bare dimension ("make the target
        -- frame taller").
        if not info.frameIsObject then
            local featureNamed = false
            for i = 1, #analysis.content do
                local item = analysis.content[i]
                if not item.soft and not item.dimension then featureNamed = true end
            end
            if not featureNamed then return nil, analysis, true end
        end
        -- One generic word ("turn off target of target inline") does not name a
        -- control; the dedicated lanes offer their numbered choices for those.
        if analysis.hardCount == 1 then
            for i = 1, #analysis.content do
                local item = analysis.content[i]
                if not item.soft and not item.dimension and VAGUE_SINGLE_WORDS[item.word] then return nil, analysis, true end
            end
        end
        local resolved = ResolveAgainstUnit(unit, analysis, raw)
        if P._unitScopeDebug then print("    attempt [" .. table.concat(tokensForAttempt, " ") .. "] fold=" .. tostring(opacityFold) .. " -> " .. tostring(resolved and #resolved or 0)) end
        if not resolved or #resolved == 0 then return nil, analysis, false end
        return resolved, analysis, false
    end

    local resolved, analysis, final = Attempt(subjectTokens, false)
    if not resolved and not final and MentionsOpacityFold(subjectTokens) then
        -- "fade the background a bit": no literal control carries "fade", so
        -- read it as an opacity change.
        resolved, analysis, final = Attempt(subjectTokens, true)
    end
    if not resolved and not final then
        -- "keep the text and portrait visible when the frame fades": the
        -- trailing clause describes the situation, not the control. Try once
        -- more without it.
        local cut
        for i = 2, #subjectTokens do
            for j = 1, #CLAUSE_MARKERS do
                if subjectTokens[i] == CLAUSE_MARKERS[j] then cut = i break end
            end
            if cut then break end
        end
        if cut then
            local head = {}
            for i = 1, cut - 1 do head[#head + 1] = subjectTokens[i] end
            resolved, analysis, final = Attempt(head, false)
            if not resolved and not final and MentionsOpacityFold(head) then
                resolved, analysis, final = Attempt(head, true)
            end
        end
    end
    if type(resolved) == "table" and resolved.kind == "changes" then return resolved end
    if not resolved or #resolved == 0 then return nil end
    if #resolved == 1 then
        local setting = resolved[1].entry.setting
        return BuildPlan({ resolved[1].change }, unit, tostring(setting.label or setting.key),
            "Changes the unit-frame control the sentence describes.", raw)
    end
    -- Ties that differ only by text slot (Left/Center/Right) with no slot named
    -- are one request about all three slots -- for booleans. Choosing a slot's
    -- CONTENT for the player is not ours to guess.
    local family
    local sameFamily, allBoolean = true, true
    for i = 1, #resolved do
        local entry = resolved[i].entry
        local thisFamily = SlotFamily(entry)
        if not thisFamily then sameFamily = false break end
        if family and thisFamily ~= family then sameFamily = false break end
        family = thisFamily
        if entry.setting.type ~= "boolean" then allBoolean = false end
    end
    local namesSlot = false
    for i = 1, #analysis.content do
        if SLOT_WORDS[analysis.content[i].word] then namesSlot = true end
    end
    if sameFamily and allBoolean and not namesSlot then
        local changes = {}
        for i = 1, #resolved do changes[#changes + 1] = resolved[i].change end
        return BuildPlan(changes, unit, tostring(resolved[1].entry.setting.label or "Text slot options"),
            "Changes the same option on every text slot of the frame.", raw)
    end
    return nil
end

-- Public: true when a sentence names "<unit> frame" only as a place or with
-- other meaningful words, so the frame's own enable toggle must not claim it.
function P.UnitFrameLocativeVeto(text)
    local norm = Normalize(text)
    if norm == "" then return false end
    local unit, subjectTokens, info = P.UnitScopeFromNaturalText(norm)
    if not unit or not info or not info.explicit then return false end
    if info.locative then return true end
    local analysis = AnalyseSubject(subjectTokens, text)
    return analysis.hardCount > 0
end

-- Question openers carry no control identity; they are peeled before the
-- subject is read ("what does the dead text setting do" -> "dead text").
local QUESTION_LEADS = {
    "what is the", "what is", "what are the", "what are", "whats the", "whats", "what does the", "what does", "what do the",
    "what do", "what would", "what happens when i", "what happens if i", "how do i", "how can i", "how does the",
    "how does", "how to", "how would i", "where do i", "where can i", "where is the", "where is", "where are the",
    "where are", "wheres the", "wheres", "can you explain", "could you explain", "please explain", "explain the",
    "explain", "tell me about the", "tell me about", "tell me what", "describe the", "describe", "i want to know",
    "id like to know", "is there a way to", "is there a", "is there", "can i", "could i", "do i", "does the", "does",
}
local QUESTION_TAILS = { "mean", "do", "for", "setting", "option", "control", "exactly", "in msuf", "on msuf", "please" }

-- Public: the one control a QUESTION about one unit frame is about. Returns
-- key, setting, literal -- `literal` is true when every meaningful word of the
-- control's label was spoken (through the same synonym layer commands use),
-- which is the bar a definitional answer has to clear.
function P.UnitScopedQuestionKey(text)
    local norm = Normalize(text)
    if norm == "" then return nil end
    if ContainsAny(norm, AURA_TERMS) then return nil end
    if ContainsAny(norm, GROUP_SCOPE_TERMS) then return nil end
    local stripped = " " .. norm .. " "
    for i = 1, #QUESTION_LEADS do
        local lead = " " .. QUESTION_LEADS[i] .. " "
        if stripped:sub(1, #lead) == lead then
            stripped = " " .. stripped:sub(#lead + 1)
            break
        end
    end
    stripped = Trim(stripped)
    for _ = 1, 3 do
        for i = 1, #QUESTION_TAILS do
            local tail = QUESTION_TAILS[i]
            if stripped:sub(-#tail - 1) == " " .. tail then stripped = Trim(stripped:sub(1, -#tail - 1)) end
        end
    end
    if stripped == "" then return nil end
    local unit, subjectTokens, info = P.UnitScopeFromNaturalText(stripped)
    local generic = false
    if not unit then
        -- "what does embed power bar into health mean" names no frame; every
        -- unit frame carries the same control, so explain it from the Player
        -- copy and let the caller say so.
        local detected = P.DetectUnits and P.DetectUnits(stripped) or {}
        if #detected > 0 then return nil end
        if P.DetectGroups and #(P.DetectGroups(stripped) or {}) > 0 then return nil end
        unit, subjectTokens, info, generic = "player", TokensOf(stripped), { frameIsObject = false, explicit = false }, true
    end
    local analysis = AnalyseSubject(subjectTokens, text, false, info.frameIsObject)
    analysis.frameIsObject = info.frameIsObject
    if analysis.hardCount == 0 then return nil end
    local entries = EnsureUnitIndex(unit)
    if not entries then return nil end
    local scored = {}
    for i = 1, #entries do
        local entry = entries[i]
        local score, extras = CandidateScore(entry, analysis)
        if score and not (analysis.comparative and entry.setting.type ~= "number") then
            scored[#scored + 1] = { entry = entry, score = score, extras = extras }
        end
    end
    if #scored == 0 then return nil end
    -- The longest fully spoken label is the control meant, exactly as for
    -- commands.
    do
        local best, bestCount
        local rawSet = analysis.rawSet or {}
        for i = 1, #scored do
            local entry = scored[i].entry
            local complete = entry.labelCount > 0
            for token in pairs(entry.labelSet) do
                if not rawSet[token] then complete = false break end
            end
            if complete and (not bestCount or entry.labelCount > bestCount) then best, bestCount = scored[i], entry.labelCount end
        end
        if best then best.score = best.score + 25 end
    end
    table.sort(scored, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return tostring(a.entry.setting.key) < tostring(b.entry.setting.key)
    end)
    if scored[2] and scored[2].score == scored[1].score then return nil end
    local top = scored[1]
    local literal = top.extras == 0 or (analysis.comparative ~= nil and top.extras <= 1)
    -- Without a frame named, only a control that exists on every unit frame
    -- may be explained generically (a player-only control would mislead).
    if generic then
        local attribute = tostring(top.entry.setting.attribute or tostring(top.entry.setting.key):match("([^.]+)$") or "")
        local Registry = A.Registry
        if attribute == "" or not (Registry and Registry:GetSetting("target." .. attribute)) then return nil end
    end
    return tostring(top.entry.setting.key), top.entry.setting, literal, generic
end
