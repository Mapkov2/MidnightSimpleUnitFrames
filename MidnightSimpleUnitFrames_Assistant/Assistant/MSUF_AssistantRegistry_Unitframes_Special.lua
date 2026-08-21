-- Assistant UnitFrame registry special settings.
-- Keeps ToT inline text, status icon style, and boss layout registrations outside
-- the main UnitFrame registry body while preserving the same cold load order.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local ctx = A.UnitframesRegistry and A.UnitframesRegistry.SpecialSettings
if type(ctx) ~= "table" then return end

local Registry = ctx.Registry
local UnitDB = ctx.UnitDB
local GeneralDB = ctx.GeneralDB
local CallGlobal = ctx.CallGlobal
local RegisterUnitNumberSetting = ctx.RegisterUnitNumberSetting
local RegisterUnitEnum = ctx.RegisterUnitEnum
local MakeAliases = ctx.MakeAliases
local ApplyToTInline = ctx.ApplyToTInline
local CleanToTInlineCustomSeparator = ctx.CleanToTInlineCustomSeparator
local NormalizeToTInlineColor = ctx.NormalizeToTInlineColor
local NormalizeToTInlineSeparatorValue = ctx.NormalizeToTInlineSeparatorValue
local NormalizeBossLayoutMode = ctx.NormalizeBossLayoutMode

if not (Registry and type(Registry.RegisterSetting) == "function") then return end
if type(UnitDB) ~= "function" or type(GeneralDB) ~= "function" then return end

local TOT_INLINE_SEPARATOR_CUSTOM = ctx.TOT_INLINE_SEPARATOR_CUSTOM
local TOT_INLINE_SEPARATOR_VALUES = { "", "-", "/", "\\", "|", "<", ">", "~", ":", TOT_INLINE_SEPARATOR_CUSTOM }

Registry:RegisterSetting({
    key = "general.statusIconsUseMidnightStyle",
    label = "Status Icons Use Midnight Style",
    category = "Status Icons",
    unit = "global",
    frameType = "unitframe",
    attribute = "statusIconsUseMidnightStyle",
    type = "boolean",
    aliases = { "status icons midnight style", "use midnight status icons", "midnight status icon style" },
    exactAliases = {
        "status icons midnight style",
        "status icon midnight style",
        "midnight status icons",
        "use midnight status icons",
        "midnight status icon style",
        "midnight style for rested icon player",
        "midnight style for combat icon target",
        "rested icon midnight style",
        "combat icon midnight style",
        "player rested icon midnight style",
        "target combat icon midnight style",
    },
    get = function() return GeneralDB().statusIconsUseMidnightStyle == true end,
    set = function(value) GeneralDB().statusIconsUseMidnightStyle = value and true or false end,
    apply = function()
        CallGlobal("MSUF_SetStatusIconStyleUseMidnight", GeneralDB().statusIconsUseMidnightStyle == true)
        CallGlobal("MSUF_RequestStatusIconsRefreshForCurrent")
    end,
    combatSafe = false,
})

Registry:RegisterSetting({
    key = "targettarget.showToTInTargetName",
    label = "Target Target Inline Text",
    category = "Target / Inline Text",
    unit = "target",
    frameType = "unitframe",
    attribute = "totInline",
    type = "boolean",
    aliases = {
        "target inline text",
        "target of target inline text",
        "target of target inline name",
        "target of target name inline",
        "target of target name on target frame",
        "target of target name on the target frame",
        "target of target name in target frame",
        "target of target name in the target frame",
        "target of target name inside target frame",
        "target of target name inside the target frame",
        "targettarget name on target frame",
        "targets target name on target frame",
        "targets target name on the target frame",
        "targets target name in target frame",
        "targets target name inside target frame",
        "show target of target text inline",
        "show target of target name inline",
        "show target of target name on target frame",
        "show target of target name on the target frame",
        "display target of target name on target frame",
        "display target of target name in target frame",
        "tot inline text",
        "tot inline name",
        "tot name inline",
        "tot name on target frame",
        "tot name in target frame",
        "tot name inside target frame",
    },
    exactAliases = {
        "target of target inline text",
        "target of target inline name",
        "target of target name inline",
        "target of target name on target frame",
        "target of target name on the target frame",
        "target of target name in target frame",
        "target of target name in the target frame",
        "target of target name inside target frame",
        "target of target name inside the target frame",
        "targettarget name on target frame",
        "targettarget name in target frame",
        "targets target name on target frame",
        "targets target name on the target frame",
        "targets target name in target frame",
        "targets target name inside target frame",
        "show target of target text inline",
        "show target of target name inline",
        "show target of target name on target frame",
        "show target of target name on the target frame",
        "display target of target name on target frame",
        "display target of target name in target frame",
        "show target of target in target name",
        "show target of target inside target name",
        "tot inline text",
        "tot inline name",
        "tot name inline",
        "tot name on target frame",
        "tot name in target frame",
        "tot name inside target frame",
    },
    get = function() return UnitDB("targettarget").showToTInTargetName == true end,
    set = function(value) UnitDB("targettarget").showToTInTargetName = value and true or false end,
    apply = function() ApplyToTInline("MSUF_ASSISTANT_TOT_INLINE") end,
    combatSafe = false,
})

Registry:RegisterSetting({
    key = "targettarget.totInlineColorMode",
    label = "Target Target Inline Color",
    category = "Target / Inline Text",
    unit = "target",
    frameType = "unitframe",
    attribute = "totInlineColor",
    type = "enum",
    aliases = { "target inline color", "target of target inline color", "tot inline color" },
    values = ctx.TOT_INLINE_COLOR_VALUES,
    valueAliases = ctx.TOT_INLINE_COLOR_ALIASES,
    get = function() return NormalizeToTInlineColor(UnitDB("targettarget").totInlineColorMode) end,
    set = function(value) UnitDB("targettarget").totInlineColorMode = NormalizeToTInlineColor(value) end,
    apply = function() ApplyToTInline("MSUF_ASSISTANT_TOT_INLINE_COLOR") end,
    combatSafe = false,
})

Registry:RegisterSetting({
    key = "targettarget.totInlineSeparator",
    label = "Target Target Inline Separator",
    category = "Target / Inline Text",
    unit = "target",
    frameType = "unitframe",
    attribute = "totInlineSeparator",
    type = "enum",
    aliases = { "target inline separator", "target of target inline separator", "tot inline separator", "target inline delimiter" },
    values = TOT_INLINE_SEPARATOR_VALUES,
    valueAliases = ctx.SEPARATOR_ALIASES,
    get = function()
        local value = UnitDB("targettarget").totInlineSeparator
        -- Only an UNSET separator falls back to "|".
        if value == nil then return "|" end
        -- "" is the declared "no separator" choice (first entry in
        -- TOT_INLINE_SEPARATOR_VALUES), but the setter stores it as a single
        -- space, matching how MSUF_UF_Config.ResolveToTInlineSeparator renders
        -- it. Report that back as the declared value so the advertised enum
        -- domain round-trips: reporting " " (or "|") for a requested "" made
        -- the transaction's verify step read back a different value than it had
        -- just written, roll the change back, and leave "no separator"
        -- impossible to apply.
        if value == " " or value == "" then return "" end
        return value
    end,
    set = function(value)
        if value == TOT_INLINE_SEPARATOR_CUSTOM then
            UnitDB("targettarget").totInlineSeparator = TOT_INLINE_SEPARATOR_CUSTOM
            UnitDB("targettarget").totInlineCustomSeparator = CleanToTInlineCustomSeparator(UnitDB("targettarget").totInlineCustomSeparator)
        else
            UnitDB("targettarget").totInlineSeparator = NormalizeToTInlineSeparatorValue(value)
        end
    end,
    apply = function() ApplyToTInline("MSUF_ASSISTANT_TOT_INLINE_SEPARATOR") end,
    combatSafe = false,
})

Registry:RegisterSetting({
    key = "targettarget.totInlineCustomSeparator",
    label = "Target Target Inline Custom Separator",
    category = "Target / Inline Text",
    unit = "target",
    frameType = "unitframe",
    attribute = "totInlineCustomSeparator",
    type = "string",
    aliases = { "target inline custom separator", "target of target inline custom separator", "tot inline custom separator" },
    valuePrefixes = { "target inline custom separator", "target of target inline custom separator", "tot inline custom separator" },
    -- A separator is capped at five characters and stripped of control
    -- characters, so anything longer is stored shortened. Without declaring the
    -- normalization the transaction read back the trimmed text, called it a
    -- failed write and rolled it back -- so a longer separator could not be set
    -- at all rather than simply being trimmed.
    normalizesValue = true,
    get = function() return CleanToTInlineCustomSeparator(UnitDB("targettarget").totInlineCustomSeparator) end,
    set = function(value)
        UnitDB("targettarget").totInlineCustomSeparator = CleanToTInlineCustomSeparator(value)
        UnitDB("targettarget").totInlineSeparator = TOT_INLINE_SEPARATOR_CUSTOM
    end,
    apply = function() ApplyToTInline("MSUF_ASSISTANT_TOT_INLINE_CUSTOM_SEPARATOR") end,
    combatSafe = false,
})

Registry:RegisterSetting({
    key = "general.bossTargetHighlightEnabled",
    label = "Boss Target Highlight",
    category = "Boss Frames / Boss Layout",
    unit = "boss",
    frameType = "unitframe",
    attribute = "bossTargetHighlight",
    type = "boolean",
    aliases = {
        "boss target highlight",
        "boss target outline",
        "highlight boss target",
        "highlight boss target frame",
        "boss ziel highlight",
        "boss ziel hervorhebung",
        "boss ziel markierung",
        "boss ziel rahmen",
    },
    exactAliases = {
        "boss target highlight",
        "boss target outline",
        "highlight boss target",
        "boss ziel highlight",
        "boss ziel hervorhebung",
        "boss ziel markierung",
    },
    get = function()
        local value = GeneralDB().bossTargetHighlightEnabled
        if value == nil then return true end
        return value == true
    end,
    set = function(value)
        local enabled = value and true or false
        local g = GeneralDB()
        g.bossTargetHighlightEnabled = enabled
        g.bossTargetOutlineMode = enabled and 1 or 0
    end,
    apply = function()
        if M and type(M.RequestUnitApply) == "function" then
            M.RequestUnitApply("boss", "MSUF2_BOSS_TARGET_HIGHLIGHT", { preview = true })
        else
            CallGlobal("MSUF_UFPreview_RequestRefresh", "MSUF2_BOSS_TARGET_HIGHLIGHT")
        end
    end,
    combatSafe = false,
    description = "Controls the Boss Layout toggle that highlights the unit targeted by boss frames.",
})
RegisterUnitNumberSetting("boss", "spacing", "spacing", "Boss Spacing", -36, -400, 0, MakeAliases("boss", "spacing", "frame spacing", "closer together", "farther apart", "gap between frames", "distance between frames"), {
    category = "Boss Layout",
    applyOpts = { preview = true },
})

RegisterUnitEnum("boss", "bossLayoutMode", "bossLayoutMode", "Boss Frame Layout", "VERTICAL_DOWN", ctx.BOSS_LAYOUT_VALUES, MakeAliases("boss", "frame layout", "layout"), {
    category = "Boss Layout",
    valueAliases = ctx.BOSS_LAYOUT_ALIASES,
    get = function()
        return NormalizeBossLayoutMode(UnitDB("boss").bossLayoutMode)
    end,
    set = function(_, value)
        local conf = UnitDB("boss")
        conf.bossLayoutMode = NormalizeBossLayoutMode(value)
        conf.invertBossOrder = nil
    end,
    applyOpts = { preview = true },
})
