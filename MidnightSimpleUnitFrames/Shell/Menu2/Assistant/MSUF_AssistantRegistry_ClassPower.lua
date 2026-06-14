-- Assistant ClassPower registry: exposes class resources, detached power, and player HP bridge controls.
-- Writes route through ClassPower helpers so parser metadata does not own live frame behavior.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Registry = A.Registry or { settings = {}, settingsByKey = {}, actions = {}, actionsByKey = {}, todos = {} }
A.Registry = Registry
A.Workflow = A.Workflow or {}

local C = A.RegistryCore
if type(C) ~= "table" then return end

-- ClassPower registry domain.
-- Exposes class-resource, detached power, and player-HP bridge settings to the assistant.
-- Presentation updates are delegated to ClassPower runtime helpers after DB writes.
local Registry = C.Registry
local RegisterBarsBoolean = C.RegisterBarsBoolean
local RegisterBarsString = C.RegisterBarsString
local RegisterBarsNumber = C.RegisterBarsNumber
local RegisterBarsEnum = C.RegisterBarsEnum
local ClassPowerAliases = C.ClassPowerAliases
local ApplyClassPower = C.ApplyClassPower
local ApplyDetachedPowerBar = C.ApplyDetachedPowerBar
local ApplyDetachedPowerBarOutline = C.ApplyDetachedPowerBarOutline
local CallGlobal = C.CallGlobal

local CLASS_POWER_WIDTH_MODE_ALIASES = {
    player = "player",
    frame = "player",
    playerframe = "player",
    playerwidth = "player",
    playerframewidth = "player",
    unitframe = "player",
    unitframewidth = "player",
    cooldown = "cooldown",
    cooldowns = "cooldown",
    essentialcooldown = "cooldown",
    essentialcooldowns = "cooldown",
    essentialcooldownmanager = "cooldown",
    cooldownmanager = "cooldown",
    cooldownsmanager = "cooldown",
    cdmwidth = "cooldown",
    cdm = "cooldown",
    utility = "utility",
    utilitycooldown = "utility",
    utilitycooldowns = "utility",
    utilitycooldownmanager = "utility",
    trackedbuff = "tracked_buffs",
    trackedbuffs = "tracked_buffs",
    bufftracker = "tracked_buffs",
    trackedbuffwidth = "tracked_buffs",
    custom = "custom",
    manual = "custom",
    auto = "auto_pips",
    autofit = "auto_pips",
    autofitpips = "auto_pips",
    fitpips = "auto_pips",
    pips = "auto_pips",
    pipwidth = "auto_pips",
    compact = "auto_pips",
}

local CLASS_POWER_SHAPE_ALIASES = {
    bar = "BAR",
    bars = "BAR",
    rectangle = "BAR",
    rectangular = "BAR",
    default = "BAR",
    circle = "CIRCLE",
    circles = "CIRCLE",
    round = "CIRCLE",
    dot = "CIRCLE",
    dots = "CIRCLE",
    orb = "CIRCLE",
    orbs = "CIRCLE",
    diamond = "DIAMOND",
    diamonds = "DIAMOND",
    gem = "DIAMOND",
    gems = "DIAMOND",
    crystal = "DIAMOND",
    hex = "HEX",
    hexagon = "HEX",
    hexagons = "HEX",
}

local CLASS_POWER_SHAPE_ALIGN_ALIASES = {
    left = "LEFT",
    start = "LEFT",
    center = "CENTER",
    centred = "CENTER",
    middle = "CENTER",
    right = "RIGHT",
    endside = "RIGHT",
}

local COMBO_POINT_COLOR_MODE_ALIASES = {
    default = "default",
    resource = "default",
    resourcecolor = "default",
    ramp = "ramp",
    comboramp = "ramp",
    gradient = "ramp",
    custom = "custom",
    slots = "custom",
}

local function NormalizeInheritedTexture(value)
    local text = tostring(value or ""):match("^%s*(.-)%s*$")
    local lower = text:lower()
    if lower == "" or lower == "global" or lower == "use global" or lower == "use global bar texture" then return "" end
    if lower == "inherit" or lower == "inherited" or lower == "default" or lower == "follow global" then return "" end
    return text
end

local function NormalizeForegroundTexture(value)
    local text = NormalizeInheritedTexture(value)
    local lower = text:lower()
    if lower == "foreground" or lower == "use foreground" or lower == "use foreground texture" then return "" end
    if lower == "same as foreground" or lower == "follow foreground" then return "" end
    return text
end

local DETACHED_POWER_WIDTH_MODE_ALIASES = {
    manual = "manual",
    custom = "manual",
    player = "manual",
    cooldown = "cooldown",
    cooldowns = "cooldown",
    essentialcooldown = "cooldown",
    essentialcooldowns = "cooldown",
    cdm = "cooldown",
    utility = "utility",
    utilitycooldown = "utility",
    utilitycooldowns = "utility",
    trackedbuff = "tracked_buffs",
    trackedbuffs = "tracked_buffs",
    bufftracker = "tracked_buffs",
}

local PLAYER_HP_ANCHOR_ALIASES = {
    classtop = "CLASS_TOP",
    classabove = "CLASS_TOP",
    aboveclass = "CLASS_TOP",
    aboveclassresource = "CLASS_TOP",
    classbottom = "CLASS_BOTTOM",
    classbelow = "CLASS_BOTTOM",
    belowclass = "CLASS_BOTTOM",
    belowclassresource = "CLASS_BOTTOM",
    powertop = "POWER_TOP",
    abovePower = "POWER_TOP",
    abovepower = "POWER_TOP",
    aboveplayerpower = "POWER_TOP",
    powerbottom = "POWER_BOTTOM",
    belowpower = "POWER_BOTTOM",
    belowplayerpower = "POWER_BOTTOM",
    underpower = "POWER_BOTTOM",
}

local PLAYER_HP_WIDTH_MODE_ALIASES = {
    class = "class",
    classresource = "class",
    classresources = "class",
    power = "power",
    playerpower = "power",
    detachedpower = "power",
    player = "player",
    playerframe = "player",
    unitframe = "player",
    custom = "custom",
    manual = "custom",
}

local PLAYER_HP_SHAPE_ALIASES = {
    bar = "BAR",
    classic = "BAR",
    default = "BAR",
    follow = "FOLLOW_POWER",
    followpower = "FOLLOW_POWER",
    followplayerpower = "FOLLOW_POWER",
    ["follow player power"] = "FOLLOW_POWER",
    power = "FOLLOW_POWER",
    powershape = "FOLLOW_POWER",
    ["power shape"] = "FOLLOW_POWER",
    round = "ROUND",
    circle = "ROUND",
    circular = "ROUND",
    dot = "ROUND",
    dots = "ROUND",
    crystal = "CRYSTAL",
    diamond = "CRYSTAL",
    gem = "CRYSTAL",
    gems = "CRYSTAL",
    orb = "ORB",
    sphere = "ORB",
    kugel = "ORB",
}

local PLAYER_HP_COLOR_MODE_ALIASES = {
    global = "GLOBAL",
    inherit = "GLOBAL",
    inherited = "GLOBAL",
    followglobal = "GLOBAL",
    class = "CLASS",
    classcolor = "CLASS",
    ["class color"] = "CLASS",
    classcolour = "CLASS",
    ["class colour"] = "CLASS",
    klassenfarbe = "CLASS",
    dark = "DARK",
    darkmode = "DARK",
    ["dark mode"] = "DARK",
    black = "DARK",
    gradient = "GRADIENT",
    hpgradient = "GRADIENT",
    healthgradient = "GRADIENT",
    ["hp gradient"] = "GRADIENT",
    ["health gradient"] = "GRADIENT",
}

local PLAYER_HP_TEXT_MODE_ALIASES = {
    none = "NONE",
    off = "NONE",
    percent = "PERCENT",
    percentage = "PERCENT",
    current = "CURRENT",
    cur = "CURRENT",
    max = "MAX",
    maximum = "MAX",
    deficit = "DEFICIT",
    missing = "DEFICIT",
    curmax = "CURMAX",
    currentmax = "CURMAX",
    currentmaximum = "CURMAX",
    currentpercent = "CURPERCENT",
    curpercent = "CURPERCENT",
    currentpercentage = "CURPERCENT",
    currentmaxpercent = "CURMAXPERCENT",
    curmaxpercent = "CURMAXPERCENT",
    maxpercent = "MAXPERCENT",
    percentcurrent = "PERCENTCUR",
    percentcur = "PERCENTCUR",
    percentmax = "PERCENTMAX",
    percentcurrentmax = "PERCENTCURMAX",
}

local PLAYER_HP_TEXT_MODES = {
    "PERCENT", "CURRENT", "MAX", "DEFICIT", "CURMAX", "CURPERCENT",
    "CURMAXPERCENT", "MAXPERCENT", "PERCENTCUR", "PERCENTMAX",
    "PERCENTCURMAX", "NONE",
}

local CLASS_POWER_PREVIEW_VALUES = {
    "deathknight_runes",
    "demonhunter_devourer",
    "demonhunter_vengeance",
    "druid_feral",
    "druid_balance",
    "evoker_essence",
    "evoker_augmentation_ebon",
    "hunter_survival_tip",
    "mage_arcane",
    "monk_brewmaster",
    "monk_windwalker",
    "paladin_holy_power",
    "priest_shadow",
    "rogue_combo",
    "shaman_elemental",
    "shaman_enhancement",
    "warlock_soul_shards",
    "warlock_destruction",
    "warrior_whirlwind",
}

local CLASS_POWER_PREVIEW_LABELS = {
    deathknight_runes = "Death Knight - Runes",
    demonhunter_devourer = "Demon Hunter - Soul Fragments",
    demonhunter_vengeance = "Demon Hunter - Vengeance Fragments",
    druid_feral = "Druid - Feral Combo Points",
    druid_balance = "Druid - Balance (no class bar)",
    evoker_essence = "Evoker - Essence",
    evoker_augmentation_ebon = "Evoker - Augmentation Ebon Might",
    hunter_survival_tip = "Hunter - Survival Tip of the Spear",
    mage_arcane = "Mage - Arcane Charges",
    monk_brewmaster = "Monk - Brewmaster Stagger",
    monk_windwalker = "Monk - Windwalker Chi",
    paladin_holy_power = "Paladin - Holy Power",
    priest_shadow = "Priest - Shadow Insanity",
    rogue_combo = "Rogue - Combo Points",
    shaman_elemental = "Shaman - Elemental Maelstrom",
    shaman_enhancement = "Shaman - Enhancement Maelstrom Weapon",
    warlock_soul_shards = "Warlock - Soul Shards",
    warlock_destruction = "Warlock - Destruction Soul Shards",
    warrior_whirlwind = "Warrior - Whirlwind Stacks",
}

local CLASS_POWER_PREVIEW_ALIASES = {
    ["death knight"] = "deathknight_runes",
    dk = "deathknight_runes",
    runes = "deathknight_runes",
    ["demon hunter soul fragments"] = "demonhunter_devourer",
    ["soul fragments"] = "demonhunter_devourer",
    ["vengeance fragments"] = "demonhunter_vengeance",
    vengeance = "demonhunter_vengeance",
    ["feral combo points"] = "druid_feral",
    feral = "druid_feral",
    ["balance druid"] = "druid_balance",
    boomkin = "druid_balance",
    essence = "evoker_essence",
    evoker = "evoker_essence",
    ["ebon might"] = "evoker_augmentation_ebon",
    augmentation = "evoker_augmentation_ebon",
    aug = "evoker_augmentation_ebon",
    ["tip of the spear"] = "hunter_survival_tip",
    hunter = "hunter_survival_tip",
    ["arcane charges"] = "mage_arcane",
    mage = "mage_arcane",
    stagger = "monk_brewmaster",
    monk = "monk_windwalker",
    brewmaster = "monk_brewmaster",
    chi = "monk_windwalker",
    windwalker = "monk_windwalker",
    ["holy power"] = "paladin_holy_power",
    paladin = "paladin_holy_power",
    insanity = "priest_shadow",
    shadow = "priest_shadow",
    ["combo points"] = "rogue_combo",
    combo = "rogue_combo",
    rogue = "rogue_combo",
    maelstrom = "shaman_elemental",
    elemental = "shaman_elemental",
    ["maelstrom weapon"] = "shaman_enhancement",
    enhancement = "shaman_enhancement",
    ["soul shards"] = "warlock_soul_shards",
    warlock = "warlock_soul_shards",
    destruction = "warlock_destruction",
    whirlwind = "warrior_whirlwind",
    warrior = "warrior_whirlwind",
}

local function ClassPowerPreviewValueAliases()
    local aliases = {}
    for i = 1, #CLASS_POWER_PREVIEW_VALUES do
        local key = CLASS_POWER_PREVIEW_VALUES[i]
        aliases[key] = key
        aliases[(CLASS_POWER_PREVIEW_LABELS[key] or key):lower()] = key
        aliases[(CLASS_POWER_PREVIEW_LABELS[key] or key):lower():gsub("%s*%-%s*", " ")] = key
        aliases[key:gsub("_", " ")] = key
    end
    for alias, key in pairs(CLASS_POWER_PREVIEW_ALIASES) do aliases[alias] = key end
    return aliases
end

local function ClassPowerPreviewExactAliases()
    local out = {
        "class resource preview resource",
        "class resource preview",
        "class resources preview",
        "class power preview resource",
        "class power preview",
        "preview class resource",
        "preview class resources",
        "preview class power",
        "preview class bar",
        "preview resource",
        "resource preview",
        "set class resource preview",
        "set class resources preview",
        "set preview resource",
    }
    local seen = {}
    for i = 1, #out do seen[out[i]] = true end
    local aliases = ClassPowerPreviewValueAliases()
    for alias in pairs(aliases) do
        alias = tostring(alias or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        if alias ~= "" then
            local variants = {
                "preview " .. alias,
                "preview " .. alias .. " class resource",
                "preview " .. alias .. " class resources",
                "show " .. alias .. " class resource preview",
            }
            for i = 1, #variants do
                local value = variants[i]
                if not seen[value] then
                    seen[value] = true
                    out[#out + 1] = value
                end
            end
        end
    end
    return out
end

local function ClassPowerPreviewLabel(key)
    return CLASS_POWER_PREVIEW_LABELS[key] or tostring(key or "rogue_combo")
end

local function NormalizeClassPowerPreviewKey(key)
    key = tostring(key or "rogue_combo")
    for i = 1, #CLASS_POWER_PREVIEW_VALUES do
        if CLASS_POWER_PREVIEW_VALUES[i] == key then return key end
    end
    return "rogue_combo"
end

local function ClassPowerPreviewActionTextHas(text, terms)
    local compact = tostring(text or ""):lower():gsub("[^%w]+", "")
    local hay = " " .. tostring(text or ""):lower():gsub("[^%w]+", " ") .. " "
    for i = 1, #(terms or {}) do
        local term = tostring(terms[i] or ""):lower()
        local compactTerm = term:gsub("[^%w]+", "")
        if compactTerm ~= "" and compact:find(compactTerm, 1, true) then return true end
        local phrase = term:gsub("[^%w]+", " ")
        phrase = phrase:gsub("^%s+", ""):gsub("%s+$", "")
        if phrase ~= "" and hay:find(" " .. phrase .. " ", 1, true) then return true end
    end
    return false
end

local function ParseClassPowerPreviewAnimationAliasArgs(text)
    local value
    if ClassPowerPreviewActionTextHas(text, { "toggle", "switch", "umschalten" }) then
        value = nil
    elseif ClassPowerPreviewActionTextHas(text, { "stop", "pause", "off", "disable", "turn off" }) then
        value = false
    elseif ClassPowerPreviewActionTextHas(text, { "start", "play", "animate", "on", "enable", "turn on" }) then
        value = true
    end
    return { value = value }, {
        label = "Animate class resource preview",
        summary = "Controls the Class Resources inline preview animation through registered action metadata.",
    }
end

local function RefreshClassPowerPreview()
    if type(CallGlobal) == "function" then CallGlobal("MSUF_UFPreview_RequestRefresh", "MSUF_ASSISTANT_CLASSPOWER_PREVIEW") end
    if M and type(M.RequestGeneralApply) == "function" then
        M.RequestGeneralApply("MSUF_ASSISTANT_CLASSPOWER_PREVIEW", { preview = true, applyAll = false, notify = false })
    end
    local preview = M and M._msuf2ClassPowerInlinePreview
    if preview and type(preview.Refresh) == "function" then preview:Refresh() end
end

RegisterBarsBoolean("showClassPower", "enabled", "Class Resource", true, {
    "class power enabled", "class resource enabled", "class resources enabled",
    "class power bar enabled", "class resource bar enabled", "resource bar enabled",
}, {
    reason = "MSUF_ASSISTANT_CLASSPOWER_ENABLED",
    matchLabel = false,
    exactAliases = {
        "show class resource",
        "show class resources",
        "show class power",
        "show class power bar",
        "show class resource bar",
        "show class resources bar",
        "show combo points",
        "turn on class resource",
        "turn on class resources",
        "turn on class power",
        "turn on class power bar",
        "turn on class resource bar",
        "enable class resource",
        "enable class resources",
        "enable class power",
        "enable class power bar",
        "enable class resource bar",
        "class resource on",
        "class resources on",
        "class power on",
        "hide class resource",
        "hide class resources",
        "hide class power",
        "hide class power bar",
        "hide class resource bar",
        "hide class resources bar",
        "hide combo points",
        "turn off class resource",
        "turn off class resources",
        "turn off class power",
        "turn off class power bar",
        "turn off class resource bar",
        "disable class resource",
        "disable class resources",
        "disable class power",
        "disable class power bar",
        "disable class resource bar",
        "class resource off",
        "class resources off",
        "class power off",
    },
    description = "Enables or disables MSUF Class Resources live outside combat.",
})
RegisterBarsNumber("classPowerHeight", "height", "Class Resource Height", 4, 1, 40, ClassPowerAliases("height", "class resource bar height"), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_HEIGHT",
    exactAliases = {
        "class resource height",
        "class resources height",
        "class power height",
        "class resource bar height",
        "class resources bar height",
        "class resource size",
        "class resources size",
        "class power size",
        "class resource bigger",
        "class resources bigger",
        "class resource larger",
        "class resources larger",
        "class resource smaller",
        "class resources smaller",
        "combo point bigger",
        "combo point smaller",
        "combo points bigger",
        "combo points smaller",
        "holy power bigger",
        "holy power smaller",
        "soul shards bigger",
        "soul shards smaller",
        "chi bigger",
        "chi smaller",
        "arcane charges bigger",
        "arcane charges smaller",
        "runes bigger",
        "runes smaller",
        "essence bigger",
        "essence smaller",
    },
})
RegisterBarsEnum("classPowerShape", "shape", "Class Resource Shape", "BAR", {
    "BAR", "CIRCLE", "DIAMOND", "HEX",
}, ClassPowerAliases(
    "shape", "class resource shape", "class resources shape", "class power shape",
    "combo point shape", "combo points shape", "holy power shape", "soul shard shape", "chi shape",
    "arcane charge shape", "rune shape", "essence shape"
), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_SHAPE",
    valueAliases = CLASS_POWER_SHAPE_ALIASES,
})
RegisterBarsEnum("classPowerWidthMode", "widthMode", "Class Resource Width Mode", "player", {
    "player", "cooldown", "utility", "tracked_buffs", "custom", "auto_pips",
}, ClassPowerAliases("width mode", "class resource width source", "class power width source", "auto fit pips", "fit pips", "compact pips"), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_WIDTH_MODE",
    valueAliases = CLASS_POWER_WIDTH_MODE_ALIASES,
    exactAliases = {
        "class resource width mode",
        "class resources width mode",
        "class power width mode",
        "class resource width source",
        "class power width source",
        "class resources width",
        "class resource width to player",
        "class resources to player width",
        "class resource same width as player",
        "class resource match player",
        "class resource match player frame",
        "class resource width to cooldowns",
        "class resource width to essential cooldowns",
        "class resource width to cooldownmanager",
        "class resource width to utility cooldowns",
        "class resource width to tracked buffs",
        "class resources width to cooldowns",
        "class resources width to essential cooldowns",
        "class resources width to cooldownmanager",
        "class resources width to utility cooldowns",
        "class resources width to tracked buffs",
        "class resource width mode custom",
        "class resource width mode manual",
        "class resource auto fit pips",
        "class resource fit pips",
        "class resource compact pips",
    },
})
RegisterBarsEnum("classPowerShapeAlign", "shapeAlign", "Class Resource Shape Alignment", "CENTER", {
    "LEFT", "CENTER", "RIGHT",
}, ClassPowerAliases("shape alignment", "pip alignment", "align pips", "class resource alignment", "class power alignment"), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_SHAPE_ALIGN",
    valueAliases = CLASS_POWER_SHAPE_ALIGN_ALIASES,
})
RegisterBarsNumber("classPowerWidth", "width", "Class Resource Width", 0, 30, 800, ClassPowerAliases("width", "class resource bar width"), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_WIDTH",
    relativeStep = 10,
    exactAliases = {
        "class resource width",
        "class resources width",
        "class power width",
        "class resource bar width",
        "class resources bar width",
        "class resource wider",
        "class resources wider",
        "class resource narrower",
        "class resources narrower",
        "combo point width",
        "combo points width",
        "combo point wider",
        "combo points wider",
        "combo point narrower",
        "combo points narrower",
    },
})
RegisterBarsNumber("classPowerOffsetX", "offsetX", "Class Resource Offset X", 0, -800, 800, ClassPowerAliases("x offset", "class resource x", "class power x", "move class resource horizontally"), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_X",
    moveAxis = "x",
    moveStep = 10,
    exactAliases = {
        "move class resource left",
        "move class resource right",
        "move class resources left",
        "move class resources right",
        "nudge class resource left",
        "nudge class resource right",
        "shift class resource left",
        "shift class resource right",
        "move class power left",
        "move class power right",
        "move combo point left",
        "move combo point right",
        "move combo points left",
        "move combo points right",
        "shift combo points left",
        "shift combo points right",
        "verschiebe class resource links",
        "verschiebe class resource rechts",
        "verschiebe combo points links",
        "verschiebe combo points rechts",
    },
})
RegisterBarsNumber("classPowerOffsetY", "offsetY", "Class Resource Offset Y", 0, -800, 800, ClassPowerAliases("y offset", "class resource y", "class power y", "move class resource vertically"), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_Y",
    moveAxis = "y",
    moveStep = 10,
    exactAliases = {
        "move class resource up",
        "move class resource down",
        "move class resources up",
        "move class resources down",
        "nudge class resource up",
        "nudge class resource down",
        "shift class resource up",
        "shift class resource down",
        "move class power up",
        "move class power down",
        "move combo point up",
        "move combo point down",
        "move combo points up",
        "move combo points down",
        "shift combo points up",
        "shift combo points down",
        "verschiebe class resource hoch",
        "verschiebe class resource runter",
        "verschiebe combo points hoch",
        "verschiebe combo points runter",
    },
})
RegisterBarsNumber("classPowerFrameLevelOffset", "frameLevel", "Class Resource Frame Level", 5, 0, 30, ClassPowerAliases("frame level", "class resource strata level"), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_FRAME_LEVEL",
})

local CLASS_POWER_PLACEMENT_TERMS = {
    "under", "below", "beneath", "bottom of", "underneath", "unter", "darunter",
    "above", "over", "top of", "ueber", "darueber",
    "on player", "on the player", "inside player", "inside the player",
}

local function ClassPowerPlacementForText(text)
    text = tostring(text or ""):lower()
    local hay = " " .. text:gsub("[^%w]+", " ") .. " "
    if hay:find(" under ", 1, true)
        or hay:find(" below ", 1, true)
        or hay:find(" beneath ", 1, true)
        or hay:find(" bottom of ", 1, true)
        or hay:find(" underneath ", 1, true)
        or hay:find(" unter ", 1, true)
        or hay:find(" darunter ", 1, true)
    then
        return "below"
    end
    if hay:find(" above ", 1, true)
        or hay:find(" over ", 1, true)
        or hay:find(" top of ", 1, true)
        or hay:find(" ueber ", 1, true)
        or hay:find(" darueber ", 1, true)
    then
        return "above"
    end
    if hay:find(" on player ", 1, true)
        or hay:find(" on the player ", 1, true)
        or hay:find(" inside player ", 1, true)
        or hay:find(" inside the player ", 1, true)
    then
        return "top"
    end
    return nil
end

local function ClassPowerPlacementOffsetsForText(text)
    local db = _G.MSUF_DB or {}
    local player = type(db.player) == "table" and db.player or {}
    local bars = type(db.bars) == "table" and db.bars or {}
    local playerH = tonumber(player.height) or 40
    local cpH = tonumber(bars.classPowerHeight) or 4
    local placement = ClassPowerPlacementForText(text)
    if placement == "below" then return 0, -math.floor(playerH + cpH + 6 + 0.5) end
    if placement == "above" then return 0, math.floor(cpH + 6 + 0.5) end
    if placement == "top" then return 0, 0 end
    return nil, nil
end

local function ClassPowerPlacementXValue(_, _, text)
    local x = ClassPowerPlacementOffsetsForText(text)
    return x
end

local function ClassPowerPlacementYValue(_, _, text)
    local _, y = ClassPowerPlacementOffsetsForText(text)
    return y
end

RegisterBarsBoolean("classPowerAnchorToCooldown", "anchorToCooldown", "Class Resource Anchor To Essential Cooldowns", false, ClassPowerAliases(
    "anchor to cooldown", "anchor to cooldowns", "anchor to essential cooldowns",
    "anchor to essential cooldownmanager", "anchor to cooldownmanager",
    "class resource anchor to essential cooldowns", "class resource anchor to essential cooldownmanager",
    "class power follow cooldowns", "class resource follow essential cooldowns",
    "follow essential cooldowns", "follow cooldownmanager", "position above essential cooldowns"
), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_ANCHOR_COOLDOWN",
    valueAliases = {
        ["to cooldown"] = true,
        ["to cooldowns"] = true,
        ["to cooldown manager"] = true,
        ["to cooldownmanager"] = true,
        ["to essential cooldowns"] = true,
        ["to essential cooldownmanager"] = true,
        ["attach to cooldownmanager"] = true,
        ["dock to cooldownmanager"] = true,
        ["follow cooldownmanager"] = true,
        ["follow essential cooldowns"] = true,
        player = false,
        ["player frame"] = false,
        playerframe = false,
        ["unit frame"] = false,
        detach = false,
        detached = false,
        undock = false,
        disconnect = false,
        ["stop following"] = false,
        ["do not follow"] = false,
        ["dont follow"] = false,
        ["remove from"] = false,
    },
    companionChanges = {
        {
            key = "bars.classPowerWidthMode",
            value = "player",
            whenValue = false,
            whenTextHas = { "player", "player frame", "unit frame" },
        },
        {
            key = "bars.classPowerOffsetX",
            value = ClassPowerPlacementXValue,
            whenValue = false,
            whenTextHas = CLASS_POWER_PLACEMENT_TERMS,
        },
        {
            key = "bars.classPowerOffsetY",
            value = ClassPowerPlacementYValue,
            whenValue = false,
            whenTextHas = CLASS_POWER_PLACEMENT_TERMS,
        },
        {
            key = "bars.classPowerWidthMode",
            value = "cooldown",
            whenValue = true,
            whenTextHas = { "width", "match width", "same width" },
        },
    },
    exactAliases = {
        "anchor class resource to cooldownmanager",
        "anchor class resources to cooldownmanager",
        "anchor class resource to cooldown manager",
        "anchor class resources to cooldown manager",
        "anchor class resource to essential cooldowns",
        "anchor class resources to essential cooldowns",
        "anchor class resource to essential cooldownmanager",
        "anchor class resources to essential cooldownmanager",
        "attach class resource to cooldownmanager",
        "attach class resources to cooldownmanager",
        "dock class resource to cooldownmanager",
        "dock class resources to cooldownmanager",
        "follow cooldownmanager with class resource",
        "follow cooldownmanager with class resources",
        "anchor combo points to cooldownmanager",
        "anchor combo points to cooldown manager",
        "anchor combo points to essential cooldowns",
        "attach combo points to cooldownmanager",
        "dock combo points to cooldownmanager",
        "anchor class resource to player frame",
        "anchor class resources to player frame",
        "anchor class resource player frame",
        "anchor class resources player frame",
        "class resource anchor to player frame",
        "class resources anchor to player frame",
        "anchor combo points to player frame",
        "combo points anchor to player frame",
        "move class resource under player frame",
        "move class resources under player frame",
        "move class resource below player frame",
        "move class resources below player frame",
        "put class resource under player frame",
        "put class resources under player frame",
        "put class resource below player frame",
        "put class resources below player frame",
        "move combo points under player frame",
        "put combo points under player frame",
        "move combo points below player frame",
        "put combo points below player frame",
        "move class resource above player frame",
        "move class resources above player frame",
        "put class resource above player frame",
        "put class resources above player frame",
        "move combo points above player frame",
        "put combo points above player frame",
        "move class resource on player frame",
        "move class resources on player frame",
        "put class resource on player frame",
        "put class resources on player frame",
        "move combo points on player frame",
        "put combo points on player frame",
        "detach class resource from cooldownmanager",
        "detach class resources from cooldownmanager",
        "detach class resource from cooldown manager",
        "detach class resources from cooldown manager",
        "detach combo points from cooldownmanager",
        "detach combo points from cooldown manager",
        "undock class resource from cooldownmanager",
        "undock combo points from cooldownmanager",
        "stop class resource following cooldownmanager",
        "stop combo points following cooldownmanager",
    },
})
RegisterBarsBoolean("showChargedComboPoints", "chargedComboPoints", "Empowered Combo Points", true, ClassPowerAliases("empowered combo points", "charged combo points", "combo point charges"), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_CHARGED_COMBO_POINTS",
})
RegisterBarsBoolean("classPowerShowText", "text", "Class Resource Text", false, ClassPowerAliases("text", "resource text", "class resource numbers", "class power numbers"), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_TEXT",
    valueAliases = {
        ["astext"] = true,
        ["showtext"] = true,
        ["shownumbers"] = true,
        ["shownumber"] = true,
        ["numbersonly"] = true,
        ["textonly"] = true,
        ["aspips"] = false,
        ["asdots"] = false,
        ["asbars"] = false,
        ["showpips"] = false,
        ["showdots"] = false,
        ["showbars"] = false,
        ["pipsonly"] = false,
        ["dotsonly"] = false,
        ["hide numbers"] = false,
        ["hide number"] = false,
        ["hidetext"] = false,
        ["turnoffnumbers"] = false,
        ["turnoffnumber"] = false,
        ["turnofftext"] = false,
        ["disablenumbers"] = false,
        ["disablenumber"] = false,
        ["disabletext"] = false,
        ["withoutnumbers"] = false,
        ["nonumbers"] = false,
    },
    companionChanges = {
        { key = "bars.showClassPower", value = true, whenTextHas = { "show", "turn on", "enable" }, prepend = true },
    },
    exactAliases = {
        "class resource text",
        "class resources text",
        "class power text",
        "class resource numbers",
        "class resources numbers",
        "class power numbers",
        "resource numbers",
        "resource number",
        "show class resources as text",
        "show class resource as text",
        "show class resources as pips",
        "show class resource as pips",
        "show class resources as dots",
        "show class resource as dots",
        "show class resources as bars",
        "show class resource as bars",
        "show combo point numbers",
        "show combo points numbers",
        "hide combo point numbers",
        "hide combo points numbers",
        "show resource numbers",
        "show resource number",
        "hide resource numbers",
        "hide resource number",
        "combo point numbers",
        "combo points numbers",
        "resource text",
    },
})
RegisterBarsBoolean("runeShowTime", "runeTime", "Rune Time", true, ClassPowerAliases("rune time", "rune timers", "rune timer text"), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_RUNE_TIME",
})
RegisterBarsBoolean("classPowerFillReverse", "reverseFill", "Class Resource Reverse Fill", false, ClassPowerAliases(
    "reverse fill", "reverse direction", "fill right to left", "right to left fill",
    "fill backwards", "backwards fill", "fill backward", "class resource fill normal",
    "class resource normal direction", "class resource fill left to right"
), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_REVERSE_FILL",
    exactAliases = {
        "class resource fill",
        "class resources fill",
        "class power fill",
        "class resource fill direction",
        "class resources fill direction",
        "class power fill direction",
        "class resource fill right to left",
        "class resources fill right to left",
        "class power fill right to left",
        "class resource fill backwards",
        "class resources fill backwards",
        "class power fill backwards",
        "class resource reverse fill",
        "class resources reverse fill",
        "class power reverse fill",
        "reverse class resource fill",
        "reverse class resources fill",
        "reverse class power fill",
        "class resource fill normal direction",
        "class resources fill normal direction",
        "class power fill normal direction",
        "class resource fill left to right",
        "class resources fill left to right",
        "class power fill left to right",
    },
    valueAliases = {
        ["right to left"] = true,
        ["fill right to left"] = true,
        ["class resource fill right to left"] = true,
        ["class resources fill right to left"] = true,
        ["class power fill right to left"] = true,
        backwards = true,
        backward = true,
        ["fill backwards"] = true,
        ["fill backward"] = true,
        ["reverse fill"] = true,
        ["reverse direction"] = true,
        ["class resource reverse fill"] = true,
        ["class resources reverse fill"] = true,
        ["class power reverse fill"] = true,
        ["reverse class resource fill"] = true,
        ["reverse class resources fill"] = true,
        ["reverse class power fill"] = true,
        ["turn off class resource reverse fill"] = false,
        ["turn off class resources reverse fill"] = false,
        ["turn off class power reverse fill"] = false,
        ["disable class resource reverse fill"] = false,
        ["left to right"] = false,
        ["fill left to right"] = false,
        ["normal direction"] = false,
        ["normal fill"] = false,
        ["fill normal"] = false,
        ["class resource fill normal direction"] = false,
        ["class resources fill normal direction"] = false,
        ["class power fill normal direction"] = false,
        ["class resource fill left to right"] = false,
        ["class resources fill left to right"] = false,
        ["class power fill left to right"] = false,
    },
})
RegisterBarsBoolean("showEleMaelstrom", "elementalMaelstrom", "Elemental Maelstrom Bar", false, ClassPowerAliases("elemental maelstrom", "maelstrom bar", "ele maelstrom bar"), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_ELE_MAELSTROM",
})
RegisterBarsBoolean("showEbonMight", "ebonMight", "Ebon Might Timer", true, ClassPowerAliases("ebon might", "ebon might timer", "augmentation ebon might"), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_EBON_MIGHT",
})
RegisterBarsBoolean("showShadowMana", "shadowMana", "Shadow Insanity Bar", false, ClassPowerAliases("shadow insanity", "insanity bar", "shadow mana", "shadow resource bar"), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_SHADOW_MANA",
})
RegisterBarsBoolean("classPowerShowPrediction", "prediction", "Class Resource Prediction", true, ClassPowerAliases("prediction", "resource prediction", "incoming resource"), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_PREDICTION",
    exactAliases = {
        "class resource prediction",
        "class resources prediction",
        "class power prediction",
        "resource prediction",
        "incoming resource",
        "show class resource prediction",
        "show class resources prediction",
        "turn on class resource prediction",
        "turn on class resources prediction",
        "enable class resource prediction",
        "enable class resources prediction",
        "hide class resource prediction",
        "hide class resources prediction",
        "turn off class resource prediction",
        "turn off class resources prediction",
        "disable class resource prediction",
        "disable class resources prediction",
    },
})

RegisterBarsBoolean("classPowerColorByType", "colorByType", "Class Resource Color By Type", true, ClassPowerAliases("color by type", "resource type colors", "class resource class colors"), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_COLOR_TYPE",
})
RegisterBarsEnum("classPowerComboPointColorMode", "comboPointColorMode", "Combo Point Color Mode", "default", {
    "default", "ramp", "custom",
}, ClassPowerAliases("combo point color mode", "combo point slot mode", "combo slot mode", "combo point colors", "combo colors"), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_COMBO_COLOR_MODE",
    valueAliases = COMBO_POINT_COLOR_MODE_ALIASES,
})
RegisterBarsNumber("classPowerFontSize", "fontSize", "Class Resource Font Size", 16, 6, 32, ClassPowerAliases("font size", "text size", "number size"), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_FONT_SIZE",
    exactAliases = {
        "class resource font",
        "class resource font size",
        "class resources font",
        "class resources font size",
        "class power font",
        "class power font size",
        "class resource text size",
        "class resources text size",
        "class power text size",
        "class resource number size",
        "class resources number size",
        "class resource numbers size",
        "class resource text bigger",
        "class resource text smaller",
        "class resource text larger",
        "class resource text size bigger",
        "class resource text size smaller",
        "class resource numbers bigger",
        "class resource numbers smaller",
        "resource text size",
        "resource number size",
        "combo point text size",
        "combo point number size",
        "combo point numbers size",
        "combo points text size",
        "combo points number size",
        "combo points numbers size",
    },
})
RegisterBarsNumber("classPowerTextOffsetX", "textOffsetX", "Class Resource Text Offset X", 0, -200, 200, ClassPowerAliases("text x", "text x offset", "number x offset"), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_TEXT_X",
})
RegisterBarsNumber("classPowerTextOffsetY", "textOffsetY", "Class Resource Text Offset Y", 0, -200, 200, ClassPowerAliases("text y", "text y offset", "number y offset"), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_TEXT_Y",
})
RegisterBarsNumber("classPowerBgAlpha", "backgroundAlpha", "Class Resource Background Opacity", 0.3, 0, 1, ClassPowerAliases("background opacity", "background alpha", "empty background opacity", "bg alpha"), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_BG_ALPHA",
    percent = true,
    step = 0.01,
    relativeStep = 0.05,
    booleanOnValue = 0.3,
    booleanOffValue = 0,
    booleanAliases = {
        ["show"] = 0.3,
        ["enable"] = 0.3,
        ["turnon"] = 0.3,
        ["withbackground"] = 0.3,
        ["backgroundon"] = 0.3,
        ["hide"] = 0,
        ["remove"] = 0,
        ["turnoff"] = 0,
        ["without"] = 0,
        ["withoutbackground"] = 0,
        ["nobackground"] = 0,
        ["backgroundoff"] = 0,
    },
    exactAliases = {
        "class resource background",
        "class resources background",
        "class power background",
        "show class resource background",
        "show class resources background",
        "turn on class resource background",
        "turn on class resources background",
        "enable class resource background",
        "enable class resources background",
        "hide class resource background",
        "hide class resources background",
        "turn off class resource background",
        "turn off class resources background",
        "disable class resource background",
        "disable class resources background",
        "combo point background",
        "combo points background",
        "show combo point background",
        "show combo points background",
        "hide combo point background",
        "hide combo points background",
        "turn off combo point background",
        "turn off combo points background",
        "resource background",
        "class resource background opacity",
        "class resources background opacity",
        "class power background opacity",
        "class resource background alpha",
        "class resources background alpha",
        "class power background alpha",
        "class resource empty background",
        "class resource empty background opacity",
        "class resources empty background opacity",
        "class resource bg",
        "class resource bg alpha",
        "class resources bg alpha",
        "class resource bg opacity",
        "class resources bg opacity",
    },
})
RegisterBarsNumber("classPowerTickWidth", "separator", "Class Resource Separator Width", 1, 0, 4, ClassPowerAliases("separator", "separator width", "tick width", "pip separator", "divider", "divider width", "divider line width"), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_SEPARATOR",
    exactAliases = {
        "class resource separator",
        "class resource separators",
        "class resource separator width",
        "class resources separator",
        "class resources separators",
        "class resources separator width",
        "class power separator",
        "class power separators",
        "class power separator width",
        "class resource pip separator",
        "class resource pip separators",
        "class resources pip separator",
        "class resources pip separators",
        "class resource divider",
        "class resource divider width",
        "class resource tick",
        "class resource tick width",
        "resource separator width",
        "combo point separator",
        "combo point separators",
        "combo point separator width",
        "combo point separators width",
        "combo points separator",
        "combo points separators",
        "combo points separator width",
        "combo points separators width",
        "holy power separator",
        "soul shard separator",
        "chi separator",
        "arcane charge separator",
        "rune separator",
        "essence separator",
    },
})
RegisterBarsNumber("classPowerOutline", "outline", "Class Resource Outline", 1, 0, 4, ClassPowerAliases(
    "outline", "border", "outline width", "border width",
    "outline thickness", "border thickness", "class resource outline thickness", "class resource border thickness",
    "make outline bigger", "make outline smaller", "make class resource outline bigger", "make class resource outline smaller",
    "turn off outline", "turn on outline", "turn off class resource outline", "turn on class resource outline"
), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_OUTLINE",
})
RegisterBarsNumber("classPowerFilledAlpha", "filledAlpha", "Class Resource Filled Opacity", 1.0, 0, 1, ClassPowerAliases("filled opacity", "filled alpha", "active opacity"), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_FILLED_ALPHA",
    percent = true,
    step = 0.05,
})
RegisterBarsNumber("classPowerEmptyAlpha", "emptyAlpha", "Class Resource Empty Opacity", 0.3, 0, 1, ClassPowerAliases("empty opacity", "empty alpha", "inactive opacity"), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_EMPTY_ALPHA",
    percent = true,
    step = 0.05,
})
RegisterBarsNumber("classPowerGap", "gap", "Class Resource Pip Gap", 0, 0, 8, ClassPowerAliases("pip gap", "gap", "resource gap", "point gap", "divider gap", "divider spacing", "separator spacing"), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_GAP",
    exactAliases = {
        "class resource gap",
        "class resources gap",
        "class power gap",
        "class resource spacing",
        "class resources spacing",
        "class power spacing",
        "class resource pip gap",
        "class resource pip spacing",
        "class resources pip gap",
        "class resources pip spacing",
        "resource gap",
        "resource spacing",
        "combo point gap",
        "combo point gaps",
        "combo point spacing",
        "combo points gap",
        "combo points gaps",
        "combo points spacing",
        "holy power gap",
        "soul shard gap",
        "chi gap",
        "arcane charge gap",
        "rune gap",
        "essence gap",
    },
})
RegisterBarsString("classPowerTexture", "texture", "Class Resource Foreground Texture", "", {
    "class resource foreground texture", "class resource texture", "class power foreground texture",
    "class power texture", "resource foreground texture", "resource bar foreground texture",
}, {
    category = "Global / Class Resources",
    frameType = "classPower",
    apply = ApplyClassPower,
    reason = "MSUF_ASSISTANT_CLASSPOWER_TEXTURE",
    normalizeValue = NormalizeInheritedTexture,
    description = "Sets the Class Resource foreground texture, or leaves it empty to inherit the global bar texture.",
})
RegisterBarsString("classPowerBgTexture", "backgroundTexture", "Class Resource Background Texture", "", {
    "class resource background texture", "class resource bg texture", "class power background texture",
    "class power bg texture", "resource background texture", "resource bar background texture",
}, {
    category = "Global / Class Resources",
    frameType = "classPower",
    apply = ApplyClassPower,
    reason = "MSUF_ASSISTANT_CLASSPOWER_BG_TEXTURE",
    normalizeValue = NormalizeForegroundTexture,
    description = "Sets the Class Resource background texture, or leaves it empty to follow the foreground texture.",
})

RegisterBarsBoolean("classPowerHideOOC", "hideOOC", "Class Resource Hide Out Of Combat", false, ClassPowerAliases("hide out of combat", "hide ooc", "out of combat hide", "hide when out of combat", "hide class resource out of combat", "hide class power out of combat", "hide class bar out of combat"), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_HIDE_OOC",
    exactAliases = {
        "class resource out of combat",
        "class resources out of combat",
        "class power out of combat",
        "class resource ooc",
        "class resources ooc",
        "class power ooc",
        "hide class resource out of combat",
        "hide class resources out of combat",
        "hide class power out of combat",
        "show class resource out of combat",
        "show class resources out of combat",
        "show class power out of combat",
    },
})
RegisterBarsBoolean("classPowerHideWhenFull", "hideFull", "Class Resource Hide When Full", false, ClassPowerAliases("hide when full", "hide full", "full hide", "hide class resource when full", "hide class power when full"), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_HIDE_FULL",
    exactAliases = {
        "class resource when full",
        "class resources when full",
        "class power when full",
        "combo points when full",
        "hide class resource when full",
        "hide class resources when full",
        "hide class power when full",
        "hide combo points when full",
        "show class resource when full",
        "show class resources when full",
        "show class power when full",
        "show combo points when full",
    },
})
RegisterBarsBoolean("classPowerHideWhenEmpty", "hideEmpty", "Class Resource Hide When Empty", false, ClassPowerAliases("hide when empty", "hide empty", "empty hide", "hide class resource when empty", "hide class power when empty"), {
    reason = "MSUF_ASSISTANT_CLASSPOWER_HIDE_EMPTY",
    exactAliases = {
        "class resource when empty",
        "class resources when empty",
        "class power when empty",
        "combo points when empty",
        "hide class resource when empty",
        "hide class resources when empty",
        "hide class power when empty",
        "hide combo points when empty",
        "show class resource when empty",
        "show class resources when empty",
        "show class power when empty",
        "show combo points when empty",
    },
})

RegisterBarsEnum("detachedPowerBarWidthMode", "widthMode", "Detached Power Bar Width Mode", "manual", {
    "manual", "cooldown", "utility", "tracked_buffs",
}, {
    "detached power bar width mode", "detached power width mode", "detached mana width mode",
    "detached power bar width source", "detached power follows cooldowns", "detached power follows tracked buffs",
}, {
    category = "Global / Detached Power Bar",
    frameType = "detachedPowerBar",
    apply = ApplyDetachedPowerBar,
    reason = "MSUF_ASSISTANT_DETACHED_POWER_WIDTH_MODE",
    nilValue = "manual",
    valueAliases = DETACHED_POWER_WIDTH_MODE_ALIASES,
})
RegisterBarsString("detachedPowerBarTexture", "texture", "Detached Power Bar Foreground Texture", "", {
    "detached power bar foreground texture", "detached power bar texture", "detached power texture",
    "detached mana foreground texture", "detached mana texture",
}, {
    category = "Global / Detached Power Bar",
    frameType = "detachedPowerBar",
    apply = ApplyDetachedPowerBar,
    reason = "MSUF_ASSISTANT_DETACHED_POWER_TEXTURE",
    normalizeValue = NormalizeInheritedTexture,
    description = "Sets the detached power bar foreground texture, or leaves it empty to inherit the global bar texture.",
})
RegisterBarsString("detachedPowerBarBgTexture", "backgroundTexture", "Detached Power Bar Background Texture", "", {
    "detached power bar background texture", "detached power bar bg texture", "detached power background texture",
    "detached mana background texture", "detached mana bg texture",
}, {
    category = "Global / Detached Power Bar",
    frameType = "detachedPowerBar",
    apply = ApplyDetachedPowerBar,
    reason = "MSUF_ASSISTANT_DETACHED_POWER_BG_TEXTURE",
    normalizeValue = NormalizeForegroundTexture,
    description = "Sets the detached power bar background texture, or leaves it empty to follow the foreground texture.",
})
RegisterBarsNumber("detachedPowerBarOutline", "outline", "Detached Power Bar Outline", 1, 0, 8, {
    "detached power bar outline", "detached power outline", "detached mana outline", "detached power bar border",
}, {
    category = "Global / Detached Power Bar",
    frameType = "detachedPowerBar",
    apply = ApplyDetachedPowerBarOutline,
    reason = "MSUF_ASSISTANT_DETACHED_POWER_OUTLINE",
    description = "Controls only the detached Player power outline managed by Class Resources. 0 disables the outline without changing fill or background textures.",
})

RegisterBarsBoolean("playerHPBarEnabled", "enabled", "Class Resources Player HP Bar", false, {
    "player hp bar", "second player hp bar", "duplicate hp bar", "duplicate health bar",
    "class resource hp bar", "class resources hp bar", "show player hp twice",
}, {
    category = "Global / Class Resources / Player HP Bar",
    frameType = "classPowerPlayerHP",
    apply = ApplyClassPower,
    reason = "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_ENABLED",
    description = "Enables the optional second Player health bar managed by Class Resources.",
})
RegisterBarsEnum("playerHPBarAnchor", "anchor", "Class Resources Player HP Anchor", "CLASS_TOP", {
    "CLASS_TOP", "CLASS_BOTTOM", "POWER_TOP", "POWER_BOTTOM",
}, {
    "player hp anchor", "second hp anchor", "duplicate hp anchor", "class resource hp anchor",
    "above class resource", "below class resource", "above player power", "below player power",
}, {
    category = "Global / Class Resources / Player HP Bar",
    frameType = "classPowerPlayerHP",
    apply = ApplyClassPower,
    reason = "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_ANCHOR",
    valueAliases = PLAYER_HP_ANCHOR_ALIASES,
})
RegisterBarsEnum("playerHPBarWidthMode", "widthMode", "Class Resources Player HP Width Mode", "class", {
    "class", "power", "player", "custom",
}, {
    "player hp width mode", "second hp width mode", "duplicate hp width mode",
    "player hp follows class resource", "player hp follows power", "player hp custom width",
}, {
    category = "Global / Class Resources / Player HP Bar",
    frameType = "classPowerPlayerHP",
    apply = ApplyClassPower,
    reason = "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_WIDTH_MODE",
    valueAliases = PLAYER_HP_WIDTH_MODE_ALIASES,
})
RegisterBarsNumber("playerHPBarWidth", "width", "Class Resources Player HP Width", 0, 20, 1200, {
    "player hp width", "second hp width", "duplicate hp width",
    "class resource hp width", "class resources player hp width",
    "class resources player hp bar width", "second player hp bar width",
}, {
    category = "Global / Class Resources / Player HP Bar",
    frameType = "classPowerPlayerHP",
    apply = ApplyClassPower,
    reason = "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_WIDTH",
})
RegisterBarsNumber("playerHPBarHeight", "height", "Class Resources Player HP Height", 6, 2, 80, {
    "player hp height", "second hp height", "duplicate hp height",
    "class resource hp height", "class resources player hp height",
    "class resources player hp bar height", "second player hp bar height",
}, {
    category = "Global / Class Resources / Player HP Bar",
    frameType = "classPowerPlayerHP",
    apply = ApplyClassPower,
    reason = "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_HEIGHT",
})
RegisterBarsNumber("playerHPBarGap", "gap", "Class Resources Player HP Gap", 2, 0, 60, {
    "player hp gap", "second hp gap", "duplicate hp gap", "class resource hp gap",
}, {
    category = "Global / Class Resources / Player HP Bar",
    frameType = "classPowerPlayerHP",
    apply = ApplyClassPower,
    reason = "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_GAP",
})
RegisterBarsNumber("playerHPBarOffsetX", "offsetX", "Class Resources Player HP Offset X", 0, -1000, 1000, {
    "player hp x", "player hp offset x", "second hp x", "duplicate hp x",
}, {
    category = "Global / Class Resources / Player HP Bar",
    frameType = "classPowerPlayerHP",
    apply = ApplyClassPower,
    reason = "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_X",
})
RegisterBarsNumber("playerHPBarOffsetY", "offsetY", "Class Resources Player HP Offset Y", 0, -1000, 1000, {
    "player hp y", "player hp offset y", "second hp y", "duplicate hp y",
}, {
    category = "Global / Class Resources / Player HP Bar",
    frameType = "classPowerPlayerHP",
    apply = ApplyClassPower,
    reason = "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_Y",
})
RegisterBarsNumber("playerHPBarFrameLevelOffset", "frameLevel", "Class Resources Player HP Frame Level", 7, 0, 30, {
    "player hp frame level", "player hp layer", "second hp frame level", "duplicate hp layer",
}, {
    category = "Global / Class Resources / Player HP Bar",
    frameType = "classPowerPlayerHP",
    apply = ApplyClassPower,
    reason = "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_LAYER",
})
RegisterBarsEnum("playerHPBarShape", "shape", "Class Resources Player HP Shape", "BAR", {
    "BAR", "FOLLOW_POWER", "ROUND", "CRYSTAL", "ORB",
}, {
    "player hp shape", "second hp shape", "duplicate hp shape", "class resources player hp shape",
    "class resource hp shape", "second player hp bar shape", "player hp follow power shape",
    "second hp follow player power", "player hp orb", "second hp orb", "player hp round",
    "player hp crystal", "health orb", "hp orb",
}, {
    category = "Global / Class Resources / Player HP Bar",
    frameType = "classPowerPlayerHP",
    apply = ApplyClassPower,
    reason = "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_SHAPE",
    valueAliases = PLAYER_HP_SHAPE_ALIASES,
    description = "Controls the second Player HP bar shape. Follow Player Power mirrors the effective detached Player power shape; Orb uses a single vertical fill.",
})
RegisterBarsNumber("playerHPBarOrbSize", "orbSize", "Class Resources Player HP Orb Size", 54, 20, 160, {
    "player hp orb size", "second hp orb size", "duplicate hp orb size",
    "class resources player hp orb size", "health orb size", "hp orb size",
}, {
    category = "Global / Class Resources / Player HP Bar",
    frameType = "classPowerPlayerHP",
    apply = ApplyClassPower,
    reason = "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_ORB_SIZE",
    description = "Controls the explicit Orb size for the second Player HP bar. Follow Player Power inherits the Player power orb size.",
})
RegisterBarsString("playerHPBarTexture", "texture", "Class Resources Player HP Foreground Texture", "", {
    "player hp foreground texture", "player hp texture", "second hp texture", "duplicate hp texture",
    "class resource hp texture",
}, {
    category = "Global / Class Resources / Player HP Bar",
    frameType = "classPowerPlayerHP",
    apply = ApplyClassPower,
    reason = "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_TEXTURE",
    normalizeValue = NormalizeInheritedTexture,
    description = "Sets the second Player HP foreground texture, or leaves it empty to inherit the global bar texture.",
})
RegisterBarsString("playerHPBarBgTexture", "backgroundTexture", "Class Resources Player HP Background Texture", "", {
    "player hp background texture", "player hp bg texture", "second hp background texture",
    "duplicate hp background texture", "class resource hp background texture",
}, {
    category = "Global / Class Resources / Player HP Bar",
    frameType = "classPowerPlayerHP",
    apply = ApplyClassPower,
    reason = "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_BG_TEXTURE",
    normalizeValue = NormalizeForegroundTexture,
    description = "Sets the second Player HP background texture, or leaves it empty to follow the foreground texture.",
})
RegisterBarsNumber("playerHPBarBgAlpha", "backgroundAlpha", "Class Resources Player HP Background Opacity", 0.35, 0, 1, {
    "player hp background opacity", "player hp bg alpha", "second hp background opacity",
}, {
    category = "Global / Class Resources / Player HP Bar",
    frameType = "classPowerPlayerHP",
    apply = ApplyClassPower,
    reason = "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_BG_ALPHA",
    percent = true,
    step = 0.01,
})
RegisterBarsNumber("playerHPBarOutline", "outline", "Class Resources Player HP Outline", 1, 0, 8, {
    "player hp outline", "player hp border", "second hp outline", "duplicate hp outline",
    "class resources player hp outline", "class resources player hp border",
    "class resources player hp bar outline", "second player hp bar outline",
}, {
    category = "Global / Class Resources / Player HP Bar",
    frameType = "classPowerPlayerHP",
    apply = ApplyClassPower,
    reason = "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_OUTLINE",
    description = "Controls only the second Player HP bar outline. 0 disables the outline without changing fill or background textures.",
})
RegisterBarsEnum("playerHPBarColorMode", "colorMode", "Class Resources Player HP Color Mode", "GLOBAL", {
    "GLOBAL", "CLASS", "DARK", "GRADIENT",
}, {
    "player hp color", "player hp color mode", "second hp color", "second hp color mode",
    "duplicate hp color", "duplicate health color", "class resources player hp color",
    "second player hp class color", "second player hp class colour",
    "second player hp dark mode", "second player hp hp gradient", "second player hp gradient",
}, {
    category = "Global / Class Resources / Player HP Bar",
    frameType = "classPowerPlayerHP",
    apply = ApplyClassPower,
    reason = "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_COLOR_MODE",
    valueAliases = PLAYER_HP_COLOR_MODE_ALIASES,
    description = "Controls the color source for the second Player HP bar: Global, Class Color, Dark Mode, or HP Gradient.",
})
RegisterBarsBoolean("playerHPBarSmoothFill", "smoothFill", "Class Resources Player HP Smooth Fill", false, {
    "player hp smooth fill", "second hp smooth fill", "duplicate hp smooth fill",
    "class resources player hp smooth fill", "smooth second player hp bar",
}, {
    category = "Global / Class Resources / Player HP Bar",
    frameType = "classPowerPlayerHP",
    apply = ApplyClassPower,
    reason = "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_SMOOTH",
    description = "Enables optional smooth interpolation for the second Player HP bar. Off uses direct native SetValue updates.",
})
RegisterBarsBoolean("playerHPBarTextEnabled", "text", "Class Resources Player HP Text", true, {
    "player hp text", "second hp text", "duplicate hp text",
    "class resource hp text", "class resources player hp text",
    "class resources player hp bar text", "second player hp bar text",
}, {
    category = "Global / Class Resources / Player HP Bar",
    frameType = "classPowerPlayerHP",
    apply = ApplyClassPower,
    reason = "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_TEXT",
})
RegisterBarsBoolean("playerHPBarUsePlayerText", "usePlayerText", "Class Resources Player HP Use Player Text", true, {
    "use player hp text", "share player hp text", "shared player hp text",
    "reuse player hp text", "copy player hp text", "second hp use player text",
    "class resources player hp use player text",
}, {
    category = "Global / Class Resources / Player HP Bar",
    frameType = "classPowerPlayerHP",
    apply = ApplyClassPower,
    reason = "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_SHARED_TEXT",
    description = "Uses Player HP text settings and copies already-rendered Player HP text for the second HP bar when possible.",
})
RegisterBarsEnum("playerHPBarTextLeft", "leftText", "Class Resources Player HP Left Text", "NONE", PLAYER_HP_TEXT_MODES, {
    "player hp left text", "second hp left text", "duplicate hp left text",
}, {
    category = "Global / Class Resources / Player HP Bar",
    frameType = "classPowerPlayerHP",
    apply = ApplyClassPower,
    reason = "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_TEXT_LEFT",
    valueAliases = PLAYER_HP_TEXT_MODE_ALIASES,
})
RegisterBarsEnum("playerHPBarTextCenter", "centerText", "Class Resources Player HP Center Text", "NONE", PLAYER_HP_TEXT_MODES, {
    "player hp center text", "player hp middle text", "second hp center text", "duplicate hp center text",
}, {
    category = "Global / Class Resources / Player HP Bar",
    frameType = "classPowerPlayerHP",
    apply = ApplyClassPower,
    reason = "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_TEXT_CENTER",
    valueAliases = PLAYER_HP_TEXT_MODE_ALIASES,
})
RegisterBarsEnum("playerHPBarTextRight", "rightText", "Class Resources Player HP Right Text", "CURPERCENT", PLAYER_HP_TEXT_MODES, {
    "player hp right text", "second hp right text", "duplicate hp right text",
}, {
    category = "Global / Class Resources / Player HP Bar",
    frameType = "classPowerPlayerHP",
    apply = ApplyClassPower,
    reason = "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_TEXT_RIGHT",
    valueAliases = PLAYER_HP_TEXT_MODE_ALIASES,
})
RegisterBarsString("playerHPBarTextSeparator", "textDelimiter", "Class Resources Player HP Text Delimiter", "", {
    "second hp text delimiter", "second hp text separator",
    "duplicate hp text delimiter", "duplicate hp text separator",
    "class resources player hp text delimiter", "class resources player hp text separator",
}, {
    category = "Global / Class Resources / Player HP Bar",
    frameType = "classPowerPlayerHP",
    apply = ApplyClassPower,
    reason = "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_TEXT_SEPARATOR",
    description = "Sets the delimiter used between combined HP text values on the second Player HP bar.",
    matchLabel = false,
})
RegisterBarsBoolean("playerHPBarTextReverse", "reverseText", "Class Resources Player HP Reverse Text", false, {
    "player hp reverse text", "player hp reverse order", "second hp reverse text", "duplicate hp reverse text",
}, {
    category = "Global / Class Resources / Player HP Bar",
    frameType = "classPowerPlayerHP",
    apply = ApplyClassPower,
    reason = "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_TEXT_REVERSE",
})
RegisterBarsNumber("playerHPBarTextSize", "textSize", "Class Resources Player HP Text Size", 14, 6, 48, {
    "player hp text size", "player hp font size", "second hp text size", "duplicate hp font size",
}, {
    category = "Global / Class Resources / Player HP Bar",
    frameType = "classPowerPlayerHP",
    apply = ApplyClassPower,
    reason = "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_TEXT_SIZE",
})
RegisterBarsNumber("playerHPBarTextOffsetX", "textOffsetX", "Class Resources Player HP Text Offset X", 0, -300, 300, {
    "player hp text x", "player hp text offset x", "second hp text x",
}, {
    category = "Global / Class Resources / Player HP Bar",
    frameType = "classPowerPlayerHP",
    apply = ApplyClassPower,
    reason = "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_TEXT_X",
})
RegisterBarsNumber("playerHPBarTextOffsetY", "textOffsetY", "Class Resources Player HP Text Offset Y", 0, -300, 300, {
    "player hp text y", "player hp text offset y", "second hp text y",
}, {
    category = "Global / Class Resources / Player HP Bar",
    frameType = "classPowerPlayerHP",
    apply = ApplyClassPower,
    reason = "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_TEXT_Y",
})

RegisterBarsBoolean("showAltMana", "altMana", "Alternative Mana Bar", false, {
    "alternative mana bar", "alt mana bar", "dual resource mana bar", "secondary mana bar",
    "show alternative mana", "show alt mana", "hide alternative mana", "hide alt mana",
}, {
    category = "Global / Class Resources / Alternative Mana",
    frameType = "altMana",
    reason = "MSUF_ASSISTANT_ALT_MANA",
})
RegisterBarsNumber("altManaHeight", "height", "Alternative Mana Height", 4, 2, 30, {
    "alternative mana height", "alt mana height", "secondary mana height", "dual resource mana height",
}, {
    category = "Global / Class Resources / Alternative Mana",
    frameType = "altMana",
    reason = "MSUF_ASSISTANT_ALT_MANA_HEIGHT",
})
RegisterBarsNumber("altManaOffsetY", "offsetY", "Alternative Mana Offset Y", -2, -50, 50, {
    "alternative mana y", "alternative mana y offset", "alt mana y", "alt mana y offset", "secondary mana y offset",
}, {
    category = "Global / Class Resources / Alternative Mana",
    frameType = "altMana",
    reason = "MSUF_ASSISTANT_ALT_MANA_Y",
})

Registry:RegisterSetting({
    key = "menu.classPowerPreviewResource",
    label = "Class Resource Preview Resource",
    category = "Class Resources / Preview",
    unit = "global",
    frameType = "classPower",
    attribute = "classPowerPreviewResource",
    type = "enum",
    aliases = {
        "class resource preview resource",
        "class resource preview",
        "preview class resource",
        "preview class resources",
        "class power preview resource",
        "class power preview",
        "preview class power",
        "preview class bar",
        "preview resource",
        "resource preview",
    },
    exactAliases = ClassPowerPreviewExactAliases(),
    values = CLASS_POWER_PREVIEW_VALUES,
    valueAliases = ClassPowerPreviewValueAliases(),
    get = function()
        if M and type(M.GetClassPowerPreviewSpecKey) == "function" then return M.GetClassPowerPreviewSpecKey() end
        return NormalizeClassPowerPreviewKey(M and M._msuf2ClassPowerPreviewSpecKey)
    end,
    set = function(value)
        value = NormalizeClassPowerPreviewKey(value)
        if M and type(M.SetClassPowerPreviewSpecKey) == "function" then
            M.SetClassPowerPreviewSpecKey(value)
        elseif M then
            M._msuf2ClassPowerPreviewSpecKey = value
        end
    end,
    apply = RefreshClassPowerPreview,
    combatSafe = true,
    description = "Selects the Class Resources page preview dropdown without changing saved class-resource settings.",
})

A.ClassPowerRegistry = A.ClassPowerRegistry or {}
A.ClassPowerRegistry.Actions = {
    M = M,
    Registry = Registry,
    ParseClassPowerPreviewAnimationAliasArgs = ParseClassPowerPreviewAnimationAliasArgs,
}
