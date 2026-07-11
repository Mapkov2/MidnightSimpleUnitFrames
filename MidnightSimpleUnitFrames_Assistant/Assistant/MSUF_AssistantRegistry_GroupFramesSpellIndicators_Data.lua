-- Assistant GroupFrames spell indicator registry data.
-- Kept separate from registration logic so settings/actions stay easier to scan.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GroupFramesRegistry = A.GroupFramesRegistry or {}

local Data = {}
A.GroupFramesRegistry.SpellIndicatorData = Data

Data.SCOPES = { "party", "raid", "mythicraid" }

Data.SPEC_VALUES = {
    "auto", "multi",
    "PreservationEvoker", "AugmentationEvoker", "RestorationDruid", "DisciplinePriest", "HolyPriest",
    "ShadowPriest", "MistweaverMonk", "RestorationShaman", "HolyPaladin", "ProtectionPaladin", "RetributionPaladin",
}

Data.SPEC_DISPLAY_LABELS = {
    auto = "Auto-Detect",
    multi = "Multi-Spec",
    PreservationEvoker = "Preservation Evoker",
    AugmentationEvoker = "Augmentation Evoker",
    RestorationDruid = "Restoration Druid",
    DisciplinePriest = "Discipline Priest",
    HolyPriest = "Holy Priest",
    ShadowPriest = "Shadow Priest",
    MistweaverMonk = "Mistweaver Monk",
    RestorationShaman = "Restoration Shaman",
    HolyPaladin = "Holy Paladin",
    ProtectionPaladin = "Protection Paladin",
    RetributionPaladin = "Retribution Paladin",
}

Data.SPEC_ALIASES = {
    auto = "auto", automatic = "auto", autodetect = "auto", ["auto detect"] = "auto", current = "auto", player = "auto",
    multi = "multi", multispec = "multi", ["multi spec"] = "multi",
    preservation = "PreservationEvoker", preservationevoker = "PreservationEvoker", ["preservation evoker"] = "PreservationEvoker", prevoker = "PreservationEvoker",
    augmentation = "AugmentationEvoker", augmentationevoker = "AugmentationEvoker", ["augmentation evoker"] = "AugmentationEvoker", aug = "AugmentationEvoker", auggie = "AugmentationEvoker",
    restorationdruid = "RestorationDruid", ["restoration druid"] = "RestorationDruid", restodruid = "RestorationDruid", ["resto druid"] = "RestorationDruid", rdruid = "RestorationDruid",
    discipline = "DisciplinePriest", disciplinepriest = "DisciplinePriest", ["discipline priest"] = "DisciplinePriest", disc = "DisciplinePriest", discpriest = "DisciplinePriest", ["disc priest"] = "DisciplinePriest",
    holypriest = "HolyPriest", ["holy priest"] = "HolyPriest", shadowpriest = "ShadowPriest", ["shadow priest"] = "ShadowPriest",
    mistweaver = "MistweaverMonk", mistweavermonk = "MistweaverMonk", ["mistweaver monk"] = "MistweaverMonk", mwmonk = "MistweaverMonk", ["mw monk"] = "MistweaverMonk",
    restorationshaman = "RestorationShaman", ["restoration shaman"] = "RestorationShaman", restoshaman = "RestorationShaman", ["resto shaman"] = "RestorationShaman", rshaman = "RestorationShaman",
    holy = "HolyPaladin", holypaladin = "HolyPaladin", ["holy paladin"] = "HolyPaladin", hpal = "HolyPaladin", hpaladin = "HolyPaladin",
    protectionpaladin = "ProtectionPaladin", ["protection paladin"] = "ProtectionPaladin", protpaladin = "ProtectionPaladin", ["prot paladin"] = "ProtectionPaladin",
    retributionpaladin = "RetributionPaladin", ["retribution paladin"] = "RetributionPaladin", retpaladin = "RetributionPaladin", ["ret paladin"] = "RetributionPaladin",
}

Data.CI_CATEGORY_VALUES = { "none", "dispel", "aggro", "custom" }
Data.CI_MODE_VALUES = { "present", "missing" }
Data.CI_FILTER_VALUES = { "HELPFUL|PLAYER", "HELPFUL", "HARMFUL|PLAYER", "HARMFUL" }

Data.CI_CATEGORY_ALIASES = {
    none = "none", off = "none", empty = "none", disabled = "none", aus = "none", leer = "none", deaktiviert = "none",
    dispel = "dispel", dispellable = "dispel", ["dispellable debuff"] = "dispel", dispellbar = "dispel", reinigbar = "dispel",
    aggro = "aggro", threat = "aggro", ["aggro threat"] = "aggro", bedrohung = "aggro",
    custom = "custom", ["custom spell"] = "custom", spell = "custom", ["eigener zauber"] = "custom", ["custom zauber"] = "custom", benutzerdefiniert = "custom",
}

Data.CI_MODE_ALIASES = {
    present = "present", shown = "present", active = "present", ["when present"] = "present", vorhanden = "present", aktiv = "present", ["wenn vorhanden"] = "present",
    missing = "missing", absent = "missing", ["when missing"] = "missing", fehlend = "missing", fehlt = "missing", ["nicht vorhanden"] = "missing", ["wenn fehlt"] = "missing", ["wenn fehlend"] = "missing",
}

Data.CI_FILTER_ALIASES = {
    helpfulplayer = "HELPFUL|PLAYER", ["helpful player"] = "HELPFUL|PLAYER", ["buff by me"] = "HELPFUL|PLAYER", ["my buff"] = "HELPFUL|PLAYER", ["own buff"] = "HELPFUL|PLAYER", ["hilfreich player"] = "HELPFUL|PLAYER", ["eigener buff"] = "HELPFUL|PLAYER", ["mein buff"] = "HELPFUL|PLAYER",
    helpful = "HELPFUL", buff = "HELPFUL", ["any buff"] = "HELPFUL", hilfreich = "HELPFUL", ["jeder buff"] = "HELPFUL", ["alle buffs"] = "HELPFUL",
    harmfulplayer = "HARMFUL|PLAYER", ["harmful player"] = "HARMFUL|PLAYER", ["debuff by me"] = "HARMFUL|PLAYER", ["my debuff"] = "HARMFUL|PLAYER", ["own debuff"] = "HARMFUL|PLAYER", ["schaedlich player"] = "HARMFUL|PLAYER", ["eigener debuff"] = "HARMFUL|PLAYER", ["mein debuff"] = "HARMFUL|PLAYER",
    harmful = "HARMFUL", debuff = "HARMFUL", ["any debuff"] = "HARMFUL", schaedlich = "HARMFUL", ["jeder debuff"] = "HARMFUL", ["alle debuffs"] = "HARMFUL",
}

Data.CI_SLOTS = {
    { key = "TL", label = "Top Left", default = "dispel", terms = { "top left corner", "top left dot", "top left corner indicator", "tl corner", "oben links", "oben links ecke", "oben links punkt", "oben links ecken indikator" } },
    { key = "TR", label = "Top Right", default = "aggro", terms = { "top right corner", "top right dot", "top right corner indicator", "tr corner", "oben rechts", "oben rechts ecke", "oben rechts punkt", "oben rechts ecken indikator" } },
    { key = "BL", label = "Bottom Left", default = "none", terms = { "bottom left corner", "bottom left dot", "bottom left corner indicator", "bl corner", "unten links", "unten links ecke", "unten links punkt", "unten links ecken indikator" } },
    { key = "BR", label = "Bottom Right", default = "none", terms = { "bottom right corner", "bottom right dot", "bottom right corner indicator", "br corner", "unten rechts", "unten rechts ecke", "unten rechts punkt", "unten rechts ecken indikator" } },
    { key = "C", label = "Center", default = "none", terms = { "center corner", "middle corner", "center dot", "middle dot", "center indicator", "mitte", "mitte ecke", "mitte punkt", "mittlerer indikator" } },
}
