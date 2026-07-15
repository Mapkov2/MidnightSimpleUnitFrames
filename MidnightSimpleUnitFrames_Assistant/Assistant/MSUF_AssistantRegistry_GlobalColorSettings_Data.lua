-- Static data for global color Assistant settings.
-- Loaded before MSUF_AssistantRegistry_GlobalColorSettings.lua.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Data = A.GlobalColorSettingsRegistryData or {}
A.GlobalColorSettingsRegistryData = Data

Data.COLOR_ALIASES = {
    gray = "grey",
    grau = "grey",
    violet = "purple",
    violett = "purple",
    aqua = "cyan",
    teal = "turquoise",
    weiss = "white",
    schwarz = "black",
    rot = "red",
    gruen = "green",
    blau = "blue",
    gelb = "yellow",
    lila = "purple",
    rosa = "pink",
    tuerkis = "turquoise",
}

Data.FALLBACK_COLORS = {
    white = { 1, 1, 1 },
    black = { 0, 0, 0 },
    red = { 1, 0, 0 },
    green = { 0, 1, 0 },
    blue = { 0, 0, 1 },
    yellow = { 1, 1, 0 },
    cyan = { 0, 1, 1 },
    magenta = { 1, 0, 1 },
    orange = { 1, 0.5, 0 },
    purple = { 0.6, 0, 0.8 },
    pink = { 1, 0.6, 0.8 },
    turquoise = { 0, 0.9, 0.8 },
    grey = { 0.5, 0.5, 0.5 },
    brown = { 0.6, 0.3, 0.1 },
    gold = { 1, 0.85, 0.1 },
}

Data.CP_SLOT_DEFAULTS = {
    COMBO_POINTS_1 = { 0.00, 0.95, 1.00 },
    COMBO_POINTS_2 = { 0.00, 0.95, 1.00 },
    COMBO_POINTS_3 = { 1.00, 1.00, 0.00 },
    COMBO_POINTS_4 = { 1.00, 1.00, 0.00 },
    COMBO_POINTS_5 = { 1.00, 1.00, 0.00 },
    COMBO_POINTS_6 = { 1.00, 0.05, 0.05 },
    COMBO_POINTS_7 = { 1.00, 0.05, 0.05 },
}

-- Discrete Class Resource rows shared by the setting registry and the
-- human-language parser. Keep aliases bounded and intentional: class/spec
-- names cover requests that omit "resource", while common misspellings cover
-- speech-to-text and casual chat without fuzzy-scanning every setting.
Data.CLASS_POWER_SLOT_RESOURCES = {
    { token = "COMBO_POINTS", label = "Combo Points", className = "Rogue / Feral Druid", count = 7,
      aliases = { "combo point", "combo points", "combo", "combopoint", "combopoints", "cp", "rogue point", "rogue points", "feral point", "feral points", "kombo punkt", "kombo punkte", "kombopunkt", "kombopunkte", "schurkenpunkte" } },
    { token = "HOLY_POWER", label = "Holy Power", className = "Paladin", count = 5,
      aliases = { "holy power", "holypower", "paladin power", "paladin points", "heilige kraft", "heiligkraft", "paladin kraft" } },
    { token = "SOUL_SHARDS", label = "Soul Shards", className = "Warlock", count = 5,
      aliases = { "soul shard", "soul shards", "soulshard", "soulshards", "warlock shard", "warlock shards", "warlock souls", "seelensplitter", "seelen splitter", "hexer splitter" } },
    { token = "CHI", label = "Chi", className = "Windwalker Monk", count = 6,
      aliases = { "chi", "chi point", "chi points", "monk chi", "windwalker chi", "mönch chi", "moench chi" } },
    { token = "ARCANE_CHARGES", label = "Arcane Charges", className = "Arcane Mage", count = 4,
      aliases = { "arcane charge", "arcane charges", "arcanecharge", "arcanecharges", "arcane stack", "arcane stacks", "arcane mage", "arkane aufladung", "arkane aufladungen", "arkan aufladung" } },
    { token = "RUNES", label = "Runes", className = "Death Knight", count = 6,
      aliases = { "rune", "runes", "dk rune", "dk runes", "death knight rune", "death knight runes", "deathknight rune", "deathknight runes", "todesritter rune", "todesritter runen", "runen" } },
    { token = "ESSENCE", label = "Essence", className = "Evoker", count = 6,
      aliases = { "essence", "essences", "essence point", "essence points", "evoker essence", "evoker essences", "essenz", "essenzen", "rufer essenz", "rufer essenzen" } },
    { token = "SOUL_FRAGMENTS_VENG", label = "Vengeance Soul Fragments", className = "Vengeance Demon Hunter", count = 6,
      aliases = { "vengeance soul fragment", "vengeance soul fragments", "soul fragment", "soul fragments", "demon hunter soul", "demon hunter souls", "dh soul", "dh souls", "vengeance fragment", "vengeance fragments", "seelenfragment", "seelenfragmente" } },
    { token = "MAELSTROM", label = "Maelstrom Weapon", className = "Enhancement Shaman", count = 10,
      aliases = { "maelstrom weapon", "maelstrom stack", "maelstrom stacks", "maelstorm weapon", "maelstorm stacks", "mw stack", "mw stacks", "enhancement maelstrom", "enhancer maelstrom", "mahlstrom waffe", "mahlstromwaffe", "mahlstrom stapel" } },
    { token = "WHIRLWIND", label = "Whirlwind", className = "Warrior", count = 4,
      aliases = { "whirlwind", "whirlwind stack", "whirlwind stacks", "warrior whirlwind", "wirbelwind", "wirbelwind stapel" } },
    { token = "TIP_OF_THE_SPEAR", label = "Tip of the Spear", className = "Survival Hunter", count = 3,
      aliases = { "tip of the spear", "tip of spear", "spear tip", "spear tips", "spear stack", "spear stacks", "survival spear", "spitze des speers", "speerspitze", "speerspitzen" } },
    { token = "ICICLES", label = "Icicles", className = "Frost Mage", count = 5,
      aliases = { "icicle", "icicles", "iceicle", "iceicles", "frost mage icicle", "frost mage icicles", "frost icicle", "frost icicles", "eiskristall", "eiskristalle" } },
}

Data.COLOR_CLASS_TOKENS = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN",
    "MAGE", "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER",
}

Data.COLOR_CLASS_LABELS = {
    WARRIOR = "Warrior",
    PALADIN = "Paladin",
    HUNTER = "Hunter",
    ROGUE = "Rogue",
    PRIEST = "Priest",
    DEATHKNIGHT = "Death Knight",
    SHAMAN = "Shaman",
    MAGE = "Mage",
    WARLOCK = "Warlock",
    MONK = "Monk",
    DRUID = "Druid",
    DEMONHUNTER = "Demon Hunter",
    EVOKER = "Evoker",
}

Data.COLOR_NPC_ROWS = {
    { key = "friendly", label = "Friendly NPC Color", dr = 0, dg = 1, db = 0, aliases = { "friendly npc color", "friendly reaction color" } },
    { key = "neutral", label = "Neutral NPC Color", dr = 1, dg = 1, db = 0, aliases = { "neutral npc color", "neutral reaction color" } },
    { key = "enemy", label = "Enemy NPC Color", dr = 0.85, dg = 0.10, db = 0.10, aliases = { "enemy npc color", "hostile npc color", "enemy reaction color" } },
    { key = "dead", label = "Dead NPC Color", dr = 0.40, dg = 0.40, db = 0.40, aliases = { "dead npc color", "dead unit color" } },
}

Data.COLOR_NPC_TYPE_TOGGLE_ROWS = {
    { key = "npcTypeTarget", label = "NPC Type Color Target", aliases = { "npc type colors target", "target npc type colors" } },
    { key = "npcTypeFocus", label = "NPC Type Color Focus", aliases = { "npc type colors focus", "focus npc type colors" } },
    { key = "npcTypeBoss", label = "NPC Type Color Boss", aliases = { "npc type colors boss", "boss npc type colors" } },
    { key = "npcTypeToT", label = "NPC Type Color Target of Target", aliases = { "npc type colors targettarget", "targettarget npc type colors", "tot npc type colors" } },
}

Data.COLOR_NPC_TYPE_ROWS = {
    { key = "npcBoss", label = "Boss NPC Type Color", dr = 0.74, dg = 0.11, db = 0, aliases = { "boss npc type color", "npc boss color", "boss type color" } },
    { key = "npcMiniboss", label = "Miniboss NPC Type Color", dr = 0.56, dg = 0, db = 0.74, aliases = { "miniboss npc type color", "lieutenant npc color", "npc miniboss color" } },
    { key = "npcCaster", label = "Caster NPC Type Color", dr = 0, dg = 0.45, db = 0.74, aliases = { "caster npc type color", "npc caster color", "caster type color" } },
    { key = "npcMelee", label = "Melee NPC Type Color", dr = 0.99, dg = 0.99, db = 0.99, aliases = { "melee npc type color", "npc melee color", "melee type color" } },
    { key = "npcRegular", label = "Regular NPC Type Color", dr = 0.70, dg = 0.56, db = 0.33, aliases = { "regular npc type color", "npc regular color", "regular type color" } },
}

Data.COLOR_CASTBAR_ROWS = {
    { key = "castbarInterruptible", label = "Interruptible Cast Color", get = "GetInterruptibleCastColor", set = "SetInterruptibleCastColor", dr = 0, dg = 0.9, db = 0.8, aliases = { "interruptible cast color", "interruptible castbar color", "castbar interruptible color", "interrupt castbar color", "castbar interrupt color", "kickable cast color", "kickable castbar color" } },
    { key = "castbarNonInterruptible", label = "Non-Interruptible Cast Color", get = "GetNonInterruptibleCastColor", set = "SetNonInterruptibleCastColor", dr = 0.4, dg = 0.01, db = 0.01, aliases = { "non interruptible cast color", "non interruptible castbar color", "noninterruptible cast color", "noninterruptible castbar color", "not interruptible castbar color", "uninterruptible cast color", "uninterruptible castbar color", "unkickable cast color", "unkickable castbar color", "not kickable castbar color" } },
    { key = "castbarInterruptUnavailable", label = "Interrupt Unavailable Fill Color", get = "GetInterruptUnavailableCastColor", set = "SetInterruptUnavailableCastColor", dr = 1.0, dg = 0.494117647, db = 0.137254902, aliases = { "interrupt unavailable fill color", "unavailable cast fill color", "unavailable fill color", "kick unavailable fill color", "kick cooldown fill color", "interrupt cooldown fill color", "castbar unavailable fill color" } },
    { key = "castbarInterruptFeedback", label = "Interrupt Feedback Cast Color", get = "GetInterruptFeedbackCastColor", set = "SetInterruptFeedbackCastColor", dr = 1, dg = 0.82, db = 0, aliases = { "interrupt feedback color", "castbar interrupt feedback color", "interrupt color all castbars", "interrupt color for all castbars", "interrupted cast color", "interrupted castbar color", "after interrupt cast color" } },
    { key = "castbarFont", label = "Cast Bar Text Color", get = "GetCastbarTextColor", set = "SetCastbarTextColor", dr = 1, dg = 1, db = 1, aliases = { "castbar text color", "castbar font color", "cast bar text color", "castbar spell name color", "castbar spell name text color", "castbar spell color", "castbar spell text color", "spell name color", "spell text color" } },
    { key = "castbarTargetName", label = "Cast Target Name Color", get = "GetCastbarTargetNameColor", set = "SetCastbarTargetNameColor", dr = 1, dg = 1, db = 1, aliases = { "cast target name color", "castbar target name color", "cast target text color", "target name on castbar color", "castbar target text color" } },
}

Data.COLOR_POWER_TOKENS = {
    { key = "MANA", label = "Mana" },
    { key = "RAGE", label = "Rage" },
    { key = "ENERGY", label = "Energy" },
    { key = "FOCUS", label = "Focus" },
    { key = "RUNIC_POWER", label = "Runic Power" },
    { key = "INSANITY", label = "Insanity" },
    { key = "FURY", label = "Fury" },
    { key = "PAIN", label = "Pain" },
    { key = "ESSENCE", label = "Essence" },
    { key = "LUNAR_POWER", label = "Astral Power" },
    { key = "MAELSTROM", label = "Maelstrom" },
}

Data.COLOR_CP_TOKENS = {
    { key = "COMBO_POINTS", label = "Combo Points" },
    { key = "HOLY_POWER", label = "Holy Power" },
    { key = "SOUL_SHARDS", label = "Soul Shards" },
    { key = "CHI", label = "Chi" },
    { key = "ARCANE_CHARGES", label = "Arcane Charges" },
    { key = "RUNES", label = "Runes" },
    { key = "ESSENCE", label = "Essence" },
    { key = "CHARGED", label = "Empowered / Charged" },
    { key = "SOUL_FRAGMENTS", label = "Soul Fragments" },
    { key = "SOUL_FRAGMENTS_META", label = "Soul Fragments Void Meta" },
    { key = "MAELSTROM", label = "Maelstrom Weapon" },
    { key = "MAELSTROM_ABOVE_5", label = "Maelstrom Weapon 5+" },
    { key = "ASTRAL_POWER", label = "Astral Power" },
    { key = "AP_PREDICTION", label = "Astral Prediction" },
    { key = "ECLIPSE_SOLAR", label = "Eclipse Solar" },
    { key = "ECLIPSE_LUNAR", label = "Eclipse Lunar" },
    { key = "ECLIPSE_CA", label = "Celestial Alignment" },
    { key = "STAGGER_GREEN", label = "Stagger Light" },
    { key = "STAGGER_YELLOW", label = "Stagger Moderate" },
    { key = "STAGGER_RED", label = "Stagger Heavy" },
    { key = "SOUL_FRAGMENTS_VENG", label = "Soul Fragments Vengeance" },
    { key = "INSANITY", label = "Insanity" },
    { key = "MAELSTROM_POWER", label = "Maelstrom Power" },
    { key = "WHIRLWIND", label = "Whirlwind" },
    { key = "TIP_OF_THE_SPEAR", label = "Tip of the Spear" },
    { key = "ICICLES", label = "Icicles" },
    { key = "EBON_MIGHT", label = "Ebon Might" },
    { key = "RESOURCE_TEXT", label = "Resource Text" },
}

Data.AURA_COOLDOWN_TEXT_COLOR_ROWS = {
    { key = "aurasCooldownTextSafeColor", label = "Aura Cooldown Safe Text Color", dr = 1, dg = 1, db = 1, aliases = { "aura cooldown safe color", "aura cooldown safe text color", "cooldown text safe color", "aura timer safe color", "aura safe timer color", "safe aura timer color" } },
    { key = "aurasCooldownTextWarningColor", label = "Aura Cooldown Warning Text Color", dr = 1, dg = 0.85, db = 0.2, aliases = { "aura cooldown warning color", "aura cooldown warning text color", "cooldown text warning color", "aura timer warning color", "aura warning timer color", "warning aura timer color" } },
    { key = "aurasCooldownTextUrgentColor", label = "Aura Cooldown Urgent Text Color", dr = 1, dg = 0.55, db = 0.1, aliases = { "aura cooldown urgent color", "aura cooldown urgent text color", "cooldown text urgent color", "aura timer urgent color", "aura urgent timer color", "urgent aura timer color" } },
}

Data.AURA_COOLDOWN_TEXT_THRESHOLD_ROWS = {
    { key = "aurasCooldownTextSafeSeconds", attr = "auraCooldownTextSafeSeconds", label = "Aura Cooldown Safe Seconds", defaultValue = 60, minValue = 0, maxValue = 600, aliases = { "aura cooldown safe seconds", "aura timer safe seconds", "aura safe seconds", "safe aura seconds", "safe aura timer threshold", "aura safe timer threshold" } },
    { key = "aurasCooldownTextWarningSeconds", attr = "auraCooldownTextWarningSeconds", label = "Aura Cooldown Warning Seconds", defaultValue = 15, minValue = 0, maxValue = 60, aliases = { "aura cooldown warning seconds", "aura timer warning seconds", "aura warning seconds", "warning aura seconds", "warning aura timer threshold", "aura warning timer threshold", "warning sec", "warning seconds" } },
    { key = "aurasCooldownTextUrgentSeconds", attr = "auraCooldownTextUrgentSeconds", label = "Aura Cooldown Urgent Seconds", defaultValue = 5, minValue = 0, maxValue = 30, aliases = { "aura cooldown urgent seconds", "aura timer urgent seconds", "aura urgent seconds", "urgent aura seconds", "urgent aura timer threshold", "aura urgent timer threshold", "urgent sec", "urgent seconds" } },
}
