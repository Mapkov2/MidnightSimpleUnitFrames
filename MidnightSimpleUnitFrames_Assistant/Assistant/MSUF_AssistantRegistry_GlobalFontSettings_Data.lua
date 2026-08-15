-- Assistant global font setting static values.
-- Loaded before MSUF_AssistantRegistry_GlobalFontSettings_Core.lua.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local FontData = A.GlobalFontSettingsRegistryData or {}
A.GlobalFontSettingsRegistryData = FontData

FontData.SCOPED_FONT_CONTROL_SCOPES = { "shared", "player", "target", "targettarget", "focustarget", "focus", "pet", "boss", "gf_party", "gf_raid" }

FontData.FONT_OUTLINE_VALUES = { "OUTLINE", "THICKOUTLINE", "NONE" }
FontData.FONT_OUTLINE_ALIASES = {
    outline = "OUTLINE",
    normal = "OUTLINE",
    default = "OUTLINE",
    thick = "THICKOUTLINE",
    thickoutline = "THICKOUTLINE",
    ["thick outline"] = "THICKOUTLINE",
    bold = "THICKOUTLINE",
    none = "NONE",
    off = "NONE",
    nooutline = "NONE",
    ["no outline"] = "NONE",
}

FontData.FONT_RENDERING_VALUES = { "SMOOTH", "SHARP", "SLUG" }
FontData.FONT_RENDERING_ALIASES = {
    smooth = "SMOOTH",
    normal = "SMOOTH",
    soft = "SMOOTH",
    sharp = "SHARP",
    crisp = "SHARP",
    pixel = "SHARP",
    monochrome = "SHARP",
    mono = "SHARP",
    pixelscharf = "SHARP",
    ["pixel sharp"] = "SHARP",
    slug = "SLUG",
    ["slug render"] = "SLUG",
    ["slug rendering"] = "SLUG",
    ["slug font"] = "SLUG",
}

FontData.FONT_SHADOW_STRENGTH_VALUES = { "SOFT", "NORMAL", "DEEP" }
FontData.FONT_SHADOW_STRENGTH_ALIASES = {
    soft = "SOFT",
    subtle = "SOFT",
    leicht = "SOFT",
    normal = "NORMAL",
    default = "NORMAL",
    standard = "NORMAL",
    deep = "DEEP",
    strong = "DEEP",
    heavy = "DEEP",
    stark = "DEEP",
}

FontData.CLASS_DEFAULT_VALUES = { "DEFAULT", "CLASS" }
FontData.CLASS_DEFAULT_ALIASES = {
    default = "DEFAULT",
    palette = "DEFAULT",
    class = "CLASS",
    classcolor = "CLASS",
    ["class color"] = "CLASS",
    classcolored = "CLASS",
}

FontData.DEFAULT_NPC_VALUES = { "DEFAULT", "NPC", "CLASS" }
FontData.DEFAULT_NPC_ALIASES = {
    default = "DEFAULT",
    palette = "DEFAULT",
    npc = "NPC",
    red = "NPC",
    npcred = "NPC",
    ["npc red"] = "NPC",
    reaction = "NPC",
    ["reaction color"] = "NPC",
    class = "CLASS",
    classcolor = "CLASS",
    ["class color"] = "CLASS",
    classcolored = "CLASS",
    ["npc class"] = "CLASS",
    ["npc class color"] = "CLASS",
}

FontData.DEFAULT_HEALTH_VALUES = { "DEFAULT", "CLASS", "HEALTH" }
FontData.DEFAULT_HEALTH_ALIASES = {
    default = "DEFAULT",
    palette = "DEFAULT",
    single = "DEFAULT",
    solid = "DEFAULT",
    fixed = "DEFAULT",
    ["single color"] = "DEFAULT",
    ["single colour"] = "DEFAULT",
    ["solid color"] = "DEFAULT",
    ["solid colour"] = "DEFAULT",
    ["fixed color"] = "DEFAULT",
    ["font color"] = "DEFAULT",
    class = "CLASS",
    classcolor = "CLASS",
    ["class color"] = "CLASS",
    ["by class"] = "CLASS",
    health = "HEALTH",
    hp = "HEALTH",
    healthcolor = "HEALTH",
    ["health color"] = "HEALTH",
}

FontData.DEFAULT_RESOURCE_VALUES = { "DEFAULT", "RESOURCE" }
FontData.DEFAULT_RESOURCE_ALIASES = {
    default = "DEFAULT",
    palette = "DEFAULT",
    resource = "RESOURCE",
    power = "RESOURCE",
    powercolor = "RESOURCE",
    ["power color"] = "RESOURCE",
    ["power type"] = "RESOURCE",
    ["by power"] = "RESOURCE",
    ["by power type"] = "RESOURCE",
    energy = "RESOURCE",
    mana = "RESOURCE",
    rage = "RESOURCE",
    focus = "RESOURCE",
    ["runic power"] = "RESOURCE",
    insanity = "RESOURCE",
    fury = "RESOURCE",
    pain = "RESOURCE",
    essence = "RESOURCE",
    ["astral power"] = "RESOURCE",
    ["lunar power"] = "RESOURCE",
    maelstrom = "RESOURCE",
}

FontData.NAME_TRUNCATION_VALUES = { "LEFT", "RIGHT" }
FontData.NAME_TRUNCATION_ALIASES = {
    left = "LEFT",
    endletters = "LEFT",
    ["keep end"] = "LEFT",
    right = "RIGHT",
    startletters = "RIGHT",
    ["keep start"] = "RIGHT",
}
