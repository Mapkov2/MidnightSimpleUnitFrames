-- Assistant Aura filtering conversation parser.
--
-- This shard owns human filtering intent before generic setting aliases.  Aura
-- lane visibility, live Blizzard tokens, permanent/no-expiration filtering,
-- exact SpellID lists, and timer presentation are separate MSUF concepts; the
-- Assistant must never infer one from another.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Registry = A.Registry
local P = A.Parser or {}
A.Parser = P

local Normalize = P.Normalize
local ContainsAny = P.ContainsAny
local DetectUnits = P.DetectUnits

local UNIT_LABELS = {
    player = "Player", target = "Target", focus = "Focus", boss = "Boss",
}

local GROUP_LABELS = {
    party = "Party", raid = "Raid", mythicraid = "Mythic Raid",
}

local UNIT_SCOPE_ORDER = { "player", "target", "focus", "boss" }
local GROUP_SCOPE_ORDER = { "party", "raid", "mythicraid" }

local UNIT_FILTER_KEYS = {
    buff = {
        "onlyMine", "onlyImportant", "raid", "raidInCombat", "includeNameplateOnly", "includeDispellable", "dispellableAny",
        "cancelable", "notCancelable", "externalDefensive", "bigDefensive",
    },
    debuff = {
        "onlyMine", "onlyImportant", "raid", "raidInCombat", "includeNameplateOnly",
        "includeDispellable", "dispellableAny", "crowdControl", "nonPlayer",
    },
}

local FILTER_SPECS = {
    {
        id = "raidInCombat", unitKey = "raidInCombat", groupValue = "RaidInCombat",
        label = "Raid-relevant in combat", lane = nil,
        terms = { "raid in combat", "combat raid", "raid combat", "during raid combat" },
    },
    {
        id = "dispellableByMe", unitKey = "raid", groupValue = "Raid",
        label = "Dispellable by me", lane = "debuff",
        terms = { "dispellable by me", "dispelable by me", "i can dispel", "i can cleanse", "player can dispel" },
    },
    {
        id = "dispellableBuffByGroup", unitKey = "includeDispellable", groupValue = nil,
        label = "Dispellable / stealable by group", lane = "buff",
        terms = { "dispellable buff", "dispellable buffs", "stealable buff", "stealable buffs", "purgeable buff", "purgeable buffs", "buffs the group can dispel", "buffs the group can steal" },
    },
    {
        id = "dispellableAnyBuff", unitKey = "dispellableAny", groupValue = nil,
        label = "Any dispel / steal type", lane = "buff",
        terms = { "buff with any dispel type", "buffs with any dispel type", "buff with any steal type", "buffs with any steal type" },
    },
    {
        id = "dispellableAny", unitKey = "dispellableAny", groupValue = "DISPELLABLE",
        label = "Any dispel type", lane = "debuff",
        terms = { "any dispel type", "any dispellable type", "regardless who can dispel", "all dispel types" },
    },
    {
        id = "dispellable", unitKey = "includeDispellable", groupValue = "RAID_PLAYER_DISPELLABLE",
        label = "Dispellable by group", lane = "debuff",
        terms = { "dispellable by group", "dispelable by group", "group can dispel", "raid can dispel", "dispellable", "dispelable", "purgeable", "cleanseable", "cleansable" },
    },
    {
        id = "important", unitKey = "onlyImportant", groupValue = "IMPORTANT",
        label = "Important", lane = nil,
        terms = { "important aura", "important auras", "important buff", "important buffs", "important debuff", "important debuffs" },
    },
    {
        id = "crowdControl", unitKey = "crowdControl", groupValue = "CROWD_CONTROL",
        label = "Crowd control", lane = "debuff",
        terms = { "crowd control", "cc", "cc debuff", "cc debuffs", "control effects" },
    },
    {
        id = "nonPlayer", unitKey = "nonPlayer", groupValue = "NonPlayer",
        label = "Non-player auras", lane = "debuff", conflicts = { "onlyMine" },
        terms = { "non-player aura", "non-player auras", "non-player debuff", "non-player debuffs", "not from a player", "not caused by a player", "not caused by players" },
    },
    {
        id = "nameplateOnly", unitKey = "includeNameplateOnly", groupValue = "INCLUDE_NAME_PLATE_ONLY",
        label = "Nameplate-only", lane = nil,
        terms = { "nameplate only", "nameplate-only", "nameplate auras", "include nameplate" },
    },
    {
        id = "notCancelable", unitKey = "notCancelable", groupValue = "NotCancelable",
        label = "Not cancelable", lane = "buff", conflicts = { "cancelable" },
        terms = { "not cancelable", "not cancellable", "non cancelable", "non cancellable", "non-cancelable", "non-cancellable", "uncancelable", "uncancellable", "cannot be cancelled", "cannot be canceled" },
    },
    {
        id = "cancelable", unitKey = "cancelable", groupValue = "Cancelable",
        label = "Cancelable", lane = "buff", conflicts = { "notCancelable" },
        terms = { "cancelable", "cancellable", "can be cancelled", "can be canceled" },
    },
    {
        id = "externalDefensive", unitKey = "externalDefensive", groupValue = "ExternalDefensive",
        label = "External defensive", lane = "buff",
        terms = { "external defensive", "external defensives", "external buff", "external buffs", "externals" },
    },
    {
        id = "bigDefensive", unitKey = "bigDefensive", groupValue = "BigDefensive",
        label = "Major defensive", lane = "buff",
        terms = { "big defensive", "big defensives", "major defensive", "major defensives", "defensive cooldown", "defensive cooldowns" },
    },
    {
        id = "onlyMine", unitKey = "onlyMine", groupValue = "Player",
        label = "Only mine", lane = nil, conflicts = { "nonPlayer" },
        terms = {
            "only my", "only mine", "only show my", "show only my", "only let my", "my buffs", "my debuffs",
            "mine only", "own buffs", "own debuffs", "other players", "from everyone",
            "all players", "all casters", "everyone's", "everyones",
            "i cast", "cast by me", "applied by me", "to mine", "player filter",
        },
    },
    {
        id = "raid", unitKey = "raid", groupValue = "Raid",
        label = "Raid / encounter relevant", lane = nil,
        terms = { "raid relevant", "raid-relevant", "raid filter", "raid-relevance", "encounter relevant", "encounter-relevant" },
    },
}

local DURATION_TERMS = {
    "permanent", "no timer", "no timers", "without timer", "without timers",
    "without a timer", "without a duration", "no duration", "timeless", "untimed",
    "never expires", "never expire", "does not expire", "do not expire", "doesnt expire",
    "no expiration", "without expiration", "finite duration", "that expire", "which expire",
    "with a timer", "with timers", "only timed", "only show timed", "show only timed",
    "only let timed", "only display timed", "timed only", "regardless of duration",
    "regardless of timer", "do have a timer", "does have a timer", "have a timer",
}

local FILTER_HELP_TERMS = {
    "help me filter", "help with aura filter", "help with buff filter", "help with debuff filter",
    "filter auras", "filter buffs", "filter debuffs", "aura filtering", "what aura filters",
    "which aura filter", "what filter should", "which filter should",
}

local SPECIFIC_LIST_TERMS = {
    "blacklist", "whitelist", "spell id", "spellid", "spell:", "hidden spell", "hidden aura",
}

local function HasAny(text, terms)
    return type(ContainsAny) == "function" and ContainsAny(text, terms) == true
end

local function Setting(key)
    return Registry and type(Registry.GetSetting) == "function" and Registry:GetSetting(key) or nil
end

local function AddChange(changes, seen, key, value, valueLabel)
    local setting = Setting(key)
    if not setting then return false end
    local existingIndex = seen[setting.key]
    if existingIndex then
        changes[existingIndex].value = value
        changes[existingIndex].valueLabel = valueLabel
        return true
    end
    seen[setting.key] = #changes + 1
    changes[#changes + 1] = { setting = setting, value = value, valueLabel = valueLabel }
    return true
end

local function AddChangeWhenDifferent(changes, seen, key, value, valueLabel)
    local setting = Setting(key)
    if setting and type(setting.get) == "function" then
        local ok, current = pcall(setting.get)
        if ok and current == value then return false end
    end
    return AddChange(changes, seen, key, value, valueLabel)
end

local function ScopeLabel(kind, scope)
    if kind == "group" then return GROUP_LABELS[scope] or tostring(scope) end
    return UNIT_LABELS[scope] or tostring(scope)
end

local function LaneLabel(lane)
    if lane == "buff" then return "Buffs" end
    if lane == "debuff" then return "Debuffs" end
    return "Auras"
end

local function ContextScopeLane(ctx)
    if type(ctx) ~= "table" then return nil, nil, nil end
    local keys = {}
    if type(ctx.lastChangeBundle) == "table" then
        for i = #ctx.lastChangeBundle, 1, -1 do
            keys[#keys + 1] = ctx.lastChangeBundle[i] and ctx.lastChangeBundle[i].key
        end
    end
    keys[#keys + 1] = ctx.lastSetting
    for i = 1, #keys do
        local key = tostring(keys[i] or "")
        local scope, lane = key:match("^auras3%.([^.]+)%.([^.]+)%.")
        if scope and (lane == "buff" or lane == "debuff") then return "unit", scope, lane end
        scope, lane = key:match("^gf_([^.]+)%.auras%.([^.]+)%.")
        if scope and (lane == "buff" or lane == "debuff") then return "group", scope, lane end
    end
    return nil, nil, nil
end

local function ExplicitDestinationUnit(text)
    local specs = {
        { "target", { "on target", "on the target", "target frame", "target buff", "target buffs", "target debuff", "target debuffs", "target aura", "target auras", "in target", "in the target", "for target frame" } },
        { "focus", { "on focus", "on the focus", "focus frame", "focus buff", "focus buffs", "focus debuff", "focus debuffs", "focus aura", "focus auras", "in focus", "in the focus", "for focus frame" } },
        { "player", { "on player", "on the player", "player frame", "player buff", "player buffs", "player debuff", "player debuffs", "player aura", "player auras", "in player", "in the player", "for player frame" } },
        { "boss", { "on boss frame", "on the boss frame", "boss frame", "boss buff", "boss buffs", "boss debuff", "boss debuffs", "boss aura", "boss auras", "in boss frame", "for boss frame" } },
    }
    for i = 1, #specs do
        if HasAny(text, specs[i][2]) then return specs[i][1] end
    end
    return nil
end

local function ResolveScope(text, ctx)
    local destination = ExplicitDestinationUnit(text)
    if destination then return "unit", destination, true end

    if HasAny(text, { "mythic raid frame", "mythic raid frames", "mythic raid buff", "mythic raid buffs", "mythic raid debuff", "mythic raid debuffs", "mythicraid" }) then
        return "group", "mythicraid", true
    end
    if HasAny(text, { "party", "party frame", "party frames", "party buff", "party buffs", "party debuff", "party debuffs", "party aura", "party auras" }) then
        return "group", "party", true
    end
    local units = type(DetectUnits) == "function" and DetectUnits(text) or {}
    local chosen
    for i = 1, #units do
        local unit = units[i]
        if unit == "player" or unit == "target" or unit == "focus" or unit == "boss" then
            if not chosen then chosen = unit end
            if unit ~= "boss" then chosen = unit; break end
        end
    end
    if chosen then return "unit", chosen, true end

    -- "raid" names a group scope AND a live filter ("Raid / encounter
    -- relevant"), so in "turn on shared buff raid filter" the head noun is
    -- "filter" and "raid" is its value -- the same distinction AurasPhrases[153]
    -- already draws for "player filter". Only that one occurrence is removed:
    -- "turn on raid buff raid filter" still names the Raid group scope through
    -- its other mention, while the sentence above no longer writes the Raid
    -- group lane's filter token for a frame the player never mentioned.
    local scopeText = (" " .. text .. " "):gsub("%f[%w]raid%s+filter%f[%W]", " ")
    if HasAny(scopeText, { "raid", "raid frame", "raid frames", "raid buff", "raid buffs", "raid debuff", "raid debuffs", "raid aura", "raid auras" }) then
        return "group", "raid", true
    end
    local kind, scope = ContextScopeLane(ctx)
    if kind and scope then return kind, scope, false end
    return nil, nil, false
end

local function ResolveLane(text, ctx)
    local hasBuff = HasAny(text, { "buff", "buffs", "helpful" })
    local hasDebuff = HasAny(text, { "debuff", "debuffs", "harmful" })
    if hasBuff and hasDebuff then return "both", true end
    if hasDebuff then return "debuff", true end
    if hasBuff then return "buff", true end
    local _, _, lane = ContextScopeLane(ctx)
    return lane, false
end

local function IsQuestion(text)
    -- Lua patterns do not support regex alternation (`a|b`). Keep this
    -- constant-time and explicit so question-shaped filtering requests offer
    -- choices instead of being mistaken for direct writes.
    local firstWord = text:match("^(%S+)")
    return firstWord == "can" or firstWord == "could" or firstWord == "would"
        or firstWord == "how" or firstWord == "what" or firstWord == "which"
        or firstWord == "where" or firstWord == "why" or firstWord == "should"
        or firstWord == "is" or firstWord == "are"
        or HasAny(text, { "can you", "could you", "would you", "help me", "what are my choices" })
end

local function DurationIntent(text)
    if HasAny(text, {
        "hide timed", "exclude timed", "remove timed", "do not show timed", "dont show timed",
        "hide buffs that do have a timer", "hide debuffs that do have a timer", "hide auras that do have a timer",
        "only permanent", "only show permanent", "show only permanent", "permanent only", "show permanent only",
    }) or (HasAny(text, { "permanent" }) and HasAny(text, { "only" }))
        or (HasAny(text, { "hide", "exclude", "remove", "do not show", "dont show" })
            and HasAny(text, { "do have a timer", "does have a timer", "with a timer", "with timers" }))
    then
        return "inverse"
    end
    if HasAny(text, { "hide aura timers", "hide buff timers", "hide debuff timers", "turn off aura timers", "turn off buff timers", "turn off debuff timers" })
        and not HasAny(text, DURATION_TERMS)
    then
        return "timerPresentation"
    end
    if HasAny(text, DURATION_TERMS) then return "permanent" end
    return nil
end

local function DurationValue(text)
    -- The control is named "Hide Permanent Auras", so the label itself contains
    -- "hide". Any explicit off token therefore has to win over the label, or
    -- "put Boss Buff Hide Permanent Auras off" reads the "hide" in the NAME as
    -- the intent and switches the filter ON -- the exact opposite of the
    -- request. Previously only "turn off"/"disable" were recognised, so a bare
    -- "off" fell through to the generic "hide" branch below.
    if HasAny(text, { "do not hide permanent", "dont hide permanent", "never hide permanent" })
        or (HasAny(text, {
            "turn off", "disable", "deactivate", "switch off", "off", "false", "no",
        }) and HasAny(text, { "hide permanent" }))
    then
        return false
    end
    if HasAny(text, { "only", "show only", "only show", "only let", "only display", "keep only" })
        and HasAny(text, { "with a timer", "with timers", "that expire", "which expire", "finite duration" })
    then
        return true
    end
    if HasAny(text, {
        "do not show", "dont show", "never show", "stop showing", "filter out", "exclude", "hide",
        "remove permanent", "no permanent", "only timed", "only show timed", "show only timed",
        "timed only", "only let timed", "only display", "that expire", "which expire",
    }) or text:match("filter%s+.+%s+out") then return true end
    if HasAny(text, {
        "show again", "let", "allow", "include", "keep", "regardless of duration",
        "regardless of timer", "any duration", "show permanent", "show no timer",
    }) then return false end
    if HasAny(text, { "show" }) then return false end
    if HasAny(text, { "turn on hide permanent", "enable hide permanent" }) then return true end
    if HasAny(text, { "turn on", "enable" }) and HasAny(text, { "hide permanent" }) then return true end
    return nil
end

local function FilterSpecByID(id)
    for i = 1, #FILTER_SPECS do
        if FILTER_SPECS[i].id == id then return FILTER_SPECS[i] end
    end
    return nil
end

local function FindFilterSpec(text)
    -- Raid is both a group-frame scope and a native filter value. Value-bearing
    -- syntax must establish the filter goal before scope detection sees the
    -- trailing word and treats it as a second frame target.
    if HasAny(text, { "filter to raid", "filters to raid", "filter raid", "filter auf raid" }) then
        return FilterSpecByID("raid")
    end
    if HasAny(text, { "buff", "buffs" }) and HasAny(text, { "any dispel type", "all dispel types", "any steal type" }) then
        return FilterSpecByID("dispellableAnyBuff")
    end
    if HasAny(text, { "buff", "buffs" }) and HasAny(text, { "dispellable by group", "stealable by group", "purgeable by group", "group can dispel", "group can steal" }) then
        return FilterSpecByID("dispellableBuffByGroup")
    end
    if text:find("%f[%a]important%f[%A]")
        and HasAny(text, { "aura", "auras", "buff", "buffs", "debuff", "debuffs", "filter" })
    then
        return FilterSpecByID("important")
    end
    if HasAny(text, { "raid", "raid relevant", "raid-relevant" })
        and HasAny(text, { "combat", "in combat", "during combat" })
    then
        return FilterSpecByID("raidInCombat")
    end
    if HasAny(text, { "raid" })
        and HasAny(text, {
            "target buff", "target buffs", "target debuff", "target debuffs",
            "focus buff", "focus buffs", "focus debuff", "focus debuffs",
            "player buff", "player buffs", "player debuff", "player debuffs",
            "boss frame buff", "boss frame buffs", "boss frame debuff", "boss frame debuffs",
        })
    then
        return FilterSpecByID("raid")
    end
    if HasAny(text, { "boss", "encounter" })
        and HasAny(text, {
            "target buff", "target buffs", "target debuff", "target debuffs",
            "focus buff", "focus buffs", "focus debuff", "focus debuffs",
            "player buff", "player buffs", "player debuff", "player debuffs",
        })
    then
        return FilterSpecByID("raid")
    end
    local destination = ExplicitDestinationUnit(text)
    if destination and destination ~= "boss"
        and HasAny(text, { "boss", "encounter" })
        and HasAny(text, { "buff", "buffs", "debuff", "debuffs", "aura", "auras" })
    then
        return FilterSpecByID("raid")
    end
    for i = 1, #FILTER_SPECS do
        local spec = FILTER_SPECS[i]
        if HasAny(text, spec.terms) then return spec end
    end
    return nil
end

local function SourceIntent(text)
    if HasAny(text, {
        "not cast by me", "not applied by me", "not mine", "except mine", "other players only",
        "only other players", "only from others",
    }) then
        return "unsupportedNotMine"
    end
    if HasAny(text, { "from everyone", "all players", "all casters", "any caster", "everyone's", "everyones" })
        or (HasAny(text, { "stop filtering", "turn off", "disable", "remove" })
            and HasAny(text, { "mine", "only mine", "player filter" }))
    then
        return "everyone"
    end
    if HasAny(text, { "other players", "other people", "from others" })
        and HasAny(text, { "exclude", "hide", "filter out", "do not show", "dont show", "remove" })
    then
        return "mine"
    end
    if HasAny(text, {
        "only my", "only show my", "show only my", "only let my", "my buffs", "my debuffs",
        "mine only", "own buffs", "own debuffs", "i cast", "cast by me", "applied by me", "to mine",
        "my external", "my externals", "my defensive", "my defensives",
    }) then
        return "mine"
    end
    return nil
end

local function IsOnlyIntent(text)
    return HasAny(text, { "only", "show only", "just show", "display only", "filter to", "only let" })
end

local function IsDisableFilterIntent(text)
    return HasAny(text, { "turn off", "disable", "stop filtering", "remove the filter", "clear the filter" })
end

local function IsUnsupportedExcludeIntent(text)
    if IsDisableFilterIntent(text) and HasAny(text, { "filter" }) then return false end
    return HasAny(text, { "hide", "exclude", "filter out", "do not show", "dont show", "remove" })
end

local function ExistingAuraFilterSpecialistOwns(text)
    if DurationIntent(text) then return false end
    local guidedFilterHelp = HasAny(text, FILTER_HELP_TERMS)
    local firstWord = text:match("^(%S+)")
    local questionWords = {
        what = true, why = true, where = true, which = true, how = true,
        is = true, are = true, should = true,
        explain = true, describe = true, tell = true,
    }
    local questionPrefix = questionWords[firstWord] == true
    local comparison = HasAny(text, { " vs ", " versus ", "compare", "comparison", "difference between" })
        or text:find("%s+vs%s+") ~= nil
    local problem = HasAny(text, {
        "not working", "does not work", "doesnt work", "broken", "missing", "hard to see",
        "cannot see", "cant see", "can't see", "not showing", "wrong", "are showing", "is showing",
    })
    if comparison or problem or (questionPrefix and not guidedFilterHelp) then return true end
    if HasAny(text, { "help" }) and not guidedFilterHelp then return true end
    if text:match("^open%s") or HasAny(text, { "take me to", "go to", "navigate to", "show the page", "show me where" }) then return true end
    if text == "turn on aura filters" or text == "turn off aura filters"
        or text == "enable aura filters" or text == "disable aura filters"
        or HasAny(text, { "custom filters", "own filters" })
    then
        return true
    end
    if HasAny(text, {
        "aura filter lane", "aura editing scope", "native group aura", "blizzard aura type", "blizzard aura types",
        "highlight my buffs", "highlight my debuffs", "highlight own buffs", "highlight own debuffs",
        "dispel overlay", "dispel border", "overlay detects", "overlay trigger",
        "cooldown text", "timer text", "cooldown swipe", "duration bar", "stack text",
        "icon size", "aura size", "buff size", "debuff size", "aura growth", "buff growth", "debuff growth",
    }) then
        return true
    end
    if text:match("^set%s+.+%s+filter%s+to%s+")
        or text:match("^change%s+.+%s+filter%s+to%s+")
    then
        return true
    end
    if HasAny(text, {
        "what filters are active", "what filter is active", "which filters are active",
        "current aura filters", "current buff filters", "current debuff filters", "filter status",
        "use custom aura filters", "use its own aura filters",
        "custom aura filters", "own aura filters",
    }) then
        return true
    end
    if HasAny(text, { "active", "current", "status" }) and HasAny(text, { "filter", "filters" }) then
        return true
    end
    return false
end

local function GroupSettingScopeForPermanent(scope)
    -- The current Raid menu/model control owns both Raid and Mythic Raid.
    if scope == "mythicraid" then return "raid" end
    return scope
end

local function PermanentKey(kind, scope, lane)
    if kind == "group" then
        scope = GroupSettingScopeForPermanent(scope)
        return "gf_" .. tostring(scope) .. ".auras." .. tostring(lane) .. ".blacklist.hidePermanent"
    end
    return "auras3." .. tostring(scope) .. "." .. tostring(lane) .. ".blacklist.hidePermanent"
end

local function PermanentChanges(kind, scope, lanes, value)
    local changes, seen = {}, {}
    for i = 1, #lanes do AddChange(changes, seen, PermanentKey(kind, scope, lanes[i]), value) end
    return changes
end

local function PermanentSuccess(kind, scope, lanes, value)
    local scopeLabel = ScopeLabel(kind, scope)
    if kind == "group" and scope == "mythicraid" then scopeLabel = "Raid and Mythic Raid" end
    local laneLabel = #lanes == 2 and "Buffs and Debuffs" or LaneLabel(lanes[1])
    if value then
        return "Done — " .. scopeLabel .. " " .. laneLabel .. " with no expiration are now hidden. Timed auras still show. I left the aura lane and live-filter master unchanged."
    end
    return "Done — permanent/no-duration " .. scopeLabel .. " " .. laneLabel .. " can show again. Timed auras and the aura lane remain unchanged."
end

local function PermanentPlan(kind, scope, lanes, value)
    local changes = PermanentChanges(kind, scope, lanes, value)
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        bulkSafe = #changes > 1,
        label = value and "Hide permanent/no-duration auras" or "Show permanent/no-duration auras",
        summary = "Changes only the permanent/no-expiration candidate filter.",
        successText = PermanentSuccess(kind, scope, lanes, value),
    }
end

local function ChoiceFromPlan(plan, label, summary)
    if not (plan and type(plan.changes) == "table" and #plan.changes > 0) then return nil end
    return {
        changes = plan.changes,
        bulkSafe = plan.bulkSafe,
        label = label or plan.label,
        summary = summary or plan.summary,
        successText = plan.successText,
    }
end

local function AddChoice(choices, choice)
    if choice then choices[#choices + 1] = choice end
end

local function DurationScopeChoices(lane, value)
    local choices = {}
    local lanes = lane == "both" and { "buff", "debuff" } or { lane }
    for i = 1, #UNIT_SCOPE_ORDER do
        local scope = UNIT_SCOPE_ORDER[i]
        AddChoice(choices, ChoiceFromPlan(PermanentPlan("unit", scope, lanes, value), ScopeLabel("unit", scope) .. " " .. (#lanes == 2 and "Buffs and Debuffs" or LaneLabel(lanes[1]))))
    end
    for i = 1, #GROUP_SCOPE_ORDER do
        local scope = GROUP_SCOPE_ORDER[i]
        if scope ~= "mythicraid" then
            AddChoice(choices, ChoiceFromPlan(PermanentPlan("group", scope, lanes, value), ScopeLabel("group", scope) .. " " .. (#lanes == 2 and "Buffs and Debuffs" or LaneLabel(lanes[1]))))
        end
    end
    return choices
end

local function DurationPlan(text, ctx)
    local intent = DurationIntent(text)
    if not intent then return nil end
    if intent == "inverse" then
        return {
            kind = "answer", status = "ambiguous",
            text = "MSUF can hide permanent auras and keep timed ones, but it has no inverse switch that hides every timed aura while keeping only permanent ones. I changed nothing. Try 'hide permanent player buffs', 'turn off player buff cooldown text', or name an exact spell/filter goal.",
            summary = "Explains that inverse duration filtering is not represented by the Hide Permanent control.",
        }
    end
    if intent == "timerPresentation" then
        return {
            kind = "answer", status = "ambiguous",
            text = "Do you want to hide the timer text/swipe while keeping the aura icons, or hide permanent auras that have no expiration? Name the frame and Buff/Debuff lane, for example 'turn off target buff cooldown text' or 'hide permanent target buffs'. I changed nothing.",
            summary = "Separates aura timer presentation from permanent-aura filtering.",
        }
    end

    local kind, scope = ResolveScope(text, ctx)
    local lane = ResolveLane(text, ctx)
    local value = DurationValue(text)
    local question = IsQuestion(text)

    if lane == nil then
        if kind and scope then
            local choices = {}
            local requestedValue = value
            if requestedValue == nil then requestedValue = true end
            AddChoice(choices, ChoiceFromPlan(PermanentPlan(kind, scope, { "buff" }, requestedValue), LaneLabel("buff") .. " — " .. (requestedValue and "hide no-expiration buffs" or "let no-expiration buffs show")))
            AddChoice(choices, ChoiceFromPlan(PermanentPlan(kind, scope, { "debuff" }, requestedValue), LaneLabel("debuff") .. " — " .. (requestedValue and "hide no-expiration debuffs" or "let no-expiration debuffs show")))
            AddChoice(choices, ChoiceFromPlan(PermanentPlan(kind, scope, { "buff", "debuff" }, requestedValue), "Both Buffs and Debuffs"))
            return {
                kind = "ambiguous", choices = choices,
                choiceIntro = "I understand the timer part: you mean permanent auras with no expiration. Which " .. ScopeLabel(kind, scope) .. " lane should change?",
                summary = "Asks for the missing aura lane with executable choices.",
            }
        end
        return {
            kind = "answer", status = "ambiguous",
            text = "I understand 'no timer' as permanent/no-expiration auras. Tell me the frame and lane so I do not hide the wrong icons—for example: 'hide permanent player buffs', 'hide permanent target debuffs', or 'hide permanent raid buffs'.",
            summary = "Asks for the missing aura scope and lane.",
        }
    end

    if not kind or not scope then
        local requestedValue = value
        if requestedValue == nil then requestedValue = true end
        local choices = DurationScopeChoices(lane, requestedValue)
        return {
            kind = "ambiguous", choices = choices,
            choiceIntro = "I understand the filter goal: " .. (requestedValue and "hide" or "show") .. " permanent/no-expiration " .. LaneLabel(lane):lower() .. ". Which frame should change?",
            summary = "Asks for the missing aura scope with executable choices.",
        }
    end

    local lanes = lane == "both" and { "buff", "debuff" } or { lane }
    if question or value == nil then
        local choices = {}
        AddChoice(choices, ChoiceFromPlan(PermanentPlan(kind, scope, lanes, true), "Hide no-expiration " .. LaneLabel(lane):lower()))
        AddChoice(choices, ChoiceFromPlan(PermanentPlan(kind, scope, lanes, false), "Let no-expiration " .. LaneLabel(lane):lower() .. " show"))
        return {
            kind = "ambiguous", choices = choices,
            choiceIntro = "Your 'no timer' wording means permanent auras with no expiration. The MSUF Hide Permanent Auras control is separate from aura-lane visibility, timer text, the live buff filter/master, and an exact SpellID blacklist for a specific spell. What should I do?",
            summary = "Offers executable permanent-aura choices.",
        }
    end
    return PermanentPlan(kind, scope, lanes, value)
end

local function AddUnitFilterClearChanges(changes, seen, scope, lane, clearPermanent)
    local keys = UNIT_FILTER_KEYS[lane] or {}
    for i = 1, #keys do AddChangeWhenDifferent(changes, seen, "auras3." .. scope .. "." .. lane .. ".filter." .. keys[i], false) end
    AddChangeWhenDifferent(changes, seen, "auras3." .. scope .. "." .. lane .. ".filter.exclusive", "none")
    if clearPermanent then AddChangeWhenDifferent(changes, seen, PermanentKey("unit", scope, lane), false) end
end

local function UnitFilterPlan(scope, lane, spec, mode, sourceIntent)
    if not (scope and lane and spec and spec.unitKey) then return nil end
    if spec.lane and spec.lane ~= lane then return nil end
    local changes, seen = {}, {}
    if mode == "clear" then
        AddUnitFilterClearChanges(changes, seen, scope, lane, true)
        AddChange(changes, seen, "auras3." .. scope .. "." .. lane .. ".filtersEnabled", true)
    elseif mode == "disable" then
        AddChange(changes, seen, "auras3." .. scope .. "." .. lane .. ".filter." .. spec.unitKey, false)
    else
        if mode == "replace" then AddUnitFilterClearChanges(changes, seen, scope, lane, true) end
        AddChange(changes, seen, "auras3." .. scope .. "." .. lane .. ".filter." .. spec.unitKey, true)
        if sourceIntent == "mine" and spec.unitKey ~= "onlyMine" then
            AddChange(changes, seen, "auras3." .. scope .. "." .. lane .. ".filter.onlyMine", true)
        end
        if type(spec.conflicts) == "table" then
            for i = 1, #spec.conflicts do AddChange(changes, seen, "auras3." .. scope .. "." .. lane .. ".filter." .. spec.conflicts[i], false) end
        end
        AddChange(changes, seen, "auras3." .. scope .. "." .. lane .. ".filtersEnabled", true)
    end
    if #changes == 0 then return nil end
    local scopeLabel, laneLabel = ScopeLabel("unit", scope), LaneLabel(lane)
    local filterSetting = Setting("auras3." .. scope .. "." .. lane .. ".filter." .. spec.unitKey)
    local filterLabel = filterSetting and filterSetting.label
        or (scopeLabel .. " " .. (lane == "buff" and "Buff" or "Debuff") .. " " .. spec.label .. " Filter")
    local effectLabel = spec.label:lower() .. " " .. laneLabel:lower()
    if spec.id == "onlyMine" then
        effectLabel = lane == "buff" and "buffs cast by you" or "debuffs applied by you"
    elseif spec.id == "dispellable" then
        effectLabel = "debuffs you can dispel"
    elseif spec.id == "crowdControl" then
        effectLabel = "crowd-control debuffs"
    elseif spec.id == "nonPlayer" then
        effectLabel = "debuffs not caused by any player or player pet"
    end
    local success
    if mode == "clear" then
        success = "Done — " .. scopeLabel .. " " .. laneLabel .. " are no longer narrowed by live or permanent filters. The " .. laneLabel .. " lane remains enabled."
    elseif mode == "disable" then
        success = "Done — " .. filterLabel .. " is disabled. " .. scopeLabel .. " " .. laneLabel .. " are no longer narrowed to " .. effectLabel .. "; this does not hide only the matching auras."
    elseif mode == "replace" then
        success = "Done — " .. scopeLabel .. " " .. laneLabel .. " now show only " .. effectLabel .. ". " .. filterLabel .. " is enabled. I cleared the lane's other live and permanent filters, but left the lane enabled."
    else
        success = "Done — " .. filterLabel .. " is enabled, so " .. scopeLabel .. " " .. laneLabel .. " now include " .. effectLabel .. ". Existing filters remain in place, and the lane stays enabled."
    end
    return {
        kind = "changes", changes = changes, bulkSafe = #changes > 1,
        label = scopeLabel .. " " .. laneLabel .. " — " .. spec.label,
        summary = "Changes a live unit aura content rule without changing lane visibility.",
        successText = success,
    }
end

local function UnitShowAllChoices(scope, lane)
    local scopeLabel, laneLabel = ScopeLabel("unit", scope), LaneLabel(lane)
    local visibility = Setting("auras3." .. scope .. "." .. lane .. ".visible")
    local choices = {}

    local clearPlan = UnitFilterPlan(scope, lane, FilterSpecByID("onlyMine"), "clear")
    if clearPlan and visibility then
        clearPlan.changes[#clearPlan.changes + 1] = { setting = visibility, value = true }
        clearPlan.bulkSafe = true
        clearPlan.successText = "Done — " .. scopeLabel .. " " .. laneLabel .. " are enabled and can show every aura still allowed by their exact SpellID lists. I cleared the live and permanent filters; exact lists stayed unchanged."
        AddChoice(choices, ChoiceFromPlan(clearPlan,
            "Show every allowed " .. scopeLabel .. " " .. laneLabel .. " — enable lane and clear live/permanent filters"))
    end

    if visibility then
        AddChoice(choices, ChoiceFromPlan({
            kind = "changes",
            changes = { { setting = visibility, value = true } },
            label = scopeLabel .. " " .. laneLabel .. " visibility",
            summary = "Enables the aura lane without changing content filters.",
            successText = "Done — " .. scopeLabel .. " " .. laneLabel .. " are enabled. I kept every current live, permanent, and exact-list filter unchanged.",
        }, "Only enable " .. scopeLabel .. " " .. laneLabel .. " — keep current filters"))
    end
    return choices
end

local function GroupValueAllowed(lane, value)
    local values = A.AurasRegistryData and A.AurasRegistryData.GF_AURA_FILTER_VALUES
    values = values and values[lane] or nil
    for i = 1, #(values or {}) do if values[i] == value then return true end end
    return false
end

local function GroupFilterValue(spec, sourceIntent)
    if not spec then return nil end
    local value = spec.groupValue
    if sourceIntent == "mine" then
        local playerValues = {
            Raid = "RaidPlayer",
            ExternalDefensive = "ExternalDefensivePlayer",
            BigDefensive = "BigDefensivePlayer",
        }
        value = playerValues[value] or value
    end
    return value
end

local function GroupFilterPlan(scope, lane, spec, mode, sourceIntent)
    if not (scope and lane) then return nil end
    local value = mode == "clear" and "ALL" or GroupFilterValue(spec, sourceIntent)
    if not value or not GroupValueAllowed(lane, value) then return nil end
    local changes, seen = {}, {}
    AddChange(changes, seen, "gf_" .. scope .. ".auras." .. lane .. ".filterToken", value)
    AddChange(changes, seen, "gf_" .. scope .. ".auras.enabled", true)
    AddChange(changes, seen, "gf_" .. scope .. ".auras." .. lane .. ".enabled", true)
    if mode == "clear" then AddChange(changes, seen, PermanentKey("group", scope, lane), false) end
    if #changes == 0 then return nil end
    local scopeLabel, laneLabel = ScopeLabel("group", scope), LaneLabel(lane)
    local filterLabel = mode == "clear" and "All auras" or spec.label
    local filterSetting = Setting("gf_" .. scope .. ".auras." .. lane .. ".filterToken")
    local settingLabel = filterSetting and filterSetting.label
        or (scopeLabel .. " " .. (lane == "buff" and "Buff" or "Debuff") .. " Filter")
    return {
        kind = "changes", changes = changes, bulkSafe = #changes > 1,
        label = scopeLabel .. " " .. laneLabel .. " — " .. filterLabel,
        summary = "Selects the group lane's single live filter token and keeps its gates enabled.",
        successText = mode == "clear"
            and ("Done — " .. scopeLabel .. " " .. laneLabel .. " now show all allowed auras. " .. settingLabel .. " is set to all auras. I also cleared the permanent filter and kept the lane enabled.")
            or ("Done — " .. scopeLabel .. " " .. laneLabel .. " now use the " .. filterLabel .. " filter. " .. settingLabel .. " is set to " .. filterLabel:lower() .. ". The group aura root and lane remain enabled."),
    }
end

local function FilterScopeChoices(lane, spec, mode, sourceIntent)
    local choices = {}
    for i = 1, #UNIT_SCOPE_ORDER do
        local scope = UNIT_SCOPE_ORDER[i]
        AddChoice(choices, ChoiceFromPlan(UnitFilterPlan(scope, lane, spec, mode, sourceIntent), ScopeLabel("unit", scope) .. " " .. LaneLabel(lane)))
    end
    for i = 1, #GROUP_SCOPE_ORDER do
        local scope = GROUP_SCOPE_ORDER[i]
        AddChoice(choices, ChoiceFromPlan(GroupFilterPlan(scope, lane, spec, mode, sourceIntent), ScopeLabel("group", scope) .. " " .. LaneLabel(lane)))
    end
    return choices
end

local function GuideChoices(kind, scope, lane)
    local choices = {}
    local timed = PermanentPlan(kind, scope, { lane }, true)
    AddChoice(choices, ChoiceFromPlan(timed, "Only timed ones — hide auras with no expiration"))

    local mine = FilterSpecByID("onlyMine")
    local raid = FilterSpecByID("raid")
    if kind == "group" then
        AddChoice(choices, ChoiceFromPlan(GroupFilterPlan(scope, lane, mine, "replace"), "Only auras applied by me"))
        AddChoice(choices, ChoiceFromPlan(GroupFilterPlan(scope, lane, raid, "replace"), "Raid / encounter relevant"))
        local special = lane == "debuff" and FilterSpecByID("dispellable") or FilterSpecByID("externalDefensive")
        AddChoice(choices, ChoiceFromPlan(GroupFilterPlan(scope, lane, special, "replace"), lane == "debuff" and "Only debuffs I can dispel" or "External defensive buffs"))
        AddChoice(choices, ChoiceFromPlan(GroupFilterPlan(scope, lane, nil, "clear"), "Show all allowed auras"))
    else
        AddChoice(choices, ChoiceFromPlan(UnitFilterPlan(scope, lane, mine, "replace"), "Only auras applied by me"))
        AddChoice(choices, ChoiceFromPlan(UnitFilterPlan(scope, lane, raid, "replace"), "Raid / encounter relevant"))
        local special = lane == "debuff" and FilterSpecByID("dispellable") or FilterSpecByID("externalDefensive")
        AddChoice(choices, ChoiceFromPlan(UnitFilterPlan(scope, lane, special, "replace"), lane == "debuff" and "Only debuffs I can dispel" or "External defensive buffs"))
        AddChoice(choices, ChoiceFromPlan(UnitFilterPlan(scope, lane, mine, "clear"), "Show all auras — clear filters"))
    end
    return choices
end

local function FilterMasterIntent(text)
    if not HasAny(text, { "filter", "filters", "filtering", "filter master" }) then return nil end
    if FindFilterSpec(text) then return nil end
    local scopeEvidence = HasAny(text, {
        "player filters", "target filters", "focus filters", "boss filters",
        "player aura", "target aura", "focus aura", "boss aura",
        "player buff", "player buffs", "player debuff", "player debuffs",
        "target buff", "target buffs", "target debuff", "target debuffs",
        "focus buff", "focus buffs", "focus debuff", "focus debuffs",
        "boss buff", "boss buffs", "boss debuff", "boss debuffs",
        "for player", "for target", "for focus", "for boss",
    })
    if not scopeEvidence then return nil end
    if HasAny(text, { "turn off", "disable" }) then return false end
    if HasAny(text, { "turn on", "enable" }) then return true end
    return nil
end

local function FilterMasterPlan(text, ctx)
    local value = FilterMasterIntent(text)
    if value == nil then return nil end
    local kind, scope = ResolveScope(text, ctx)
    if kind == "group" then
        return {
            kind = "answer", status = "ambiguous",
            text = "Party, Raid, and Mythic Raid do not use the unit-frame Filters Enabled master. Each group Buff/Debuff lane has one live Filter dropdown plus separate root/lane visibility and Hide Permanent controls. Say, for example, 'show all raid debuffs' or 'set raid debuff filter to Dispellable'. I changed nothing.",
            summary = "Explains the group aura filter-gate model.",
        }
    end
    local requestedLane = ResolveLane(text, ctx)
    if not requestedLane then
        return {
            kind = "answer", status = "ambiguous",
            text = "Filters Enabled belongs to one exact Buff or Debuff lane. Name the lane, for example 'disable Target Buff filters'. I changed nothing.",
            summary = "Asks for the missing unit Aura filter lane.",
        }
    end
    local function PlanFor(unitScope)
        local setting = Setting("auras3." .. unitScope .. "." .. requestedLane .. ".filtersEnabled")
        if not setting then return nil end
        local label = ScopeLabel("unit", unitScope)
        return {
            kind = "changes",
            changes = { { setting = setting, value = value } },
            label = label .. " live-filter master",
            summary = "Changes only the unit Aura live-filter master.",
            successText = "Done — I turned " .. (value and "on" or "off") .. " the " .. label .. " live-filter master. Aura-lane visibility, Hide Permanent, exact lists, and timer styling are unchanged.",
        }
    end
    if kind == "unit" and scope then return PlanFor(scope) end

    local choices = {}
    local scopes = { "player", "target", "focus", "boss" }
    for i = 1, #scopes do
        local unitScope = scopes[i]
        AddChoice(choices, ChoiceFromPlan(PlanFor(unitScope), ScopeLabel("unit", unitScope)))
    end
    return {
        kind = "ambiguous", choices = choices,
        choiceIntro = "Which unit Aura scope should have its live-filter master turned " .. (value and "on" or "off") .. "? This will not hide either aura lane.",
        summary = "Asks for the missing unit Aura filter-master scope.",
    }
end

local function GenericDefensivePlan(text, ctx)
    if not HasAny(text, { "defensive", "defensives", "defensive buff", "defensive buffs" }) then return nil end
    if HasAny(text, {
        "external defensive", "external defensives", "external buff", "external buffs", "externals",
        "big defensive", "big defensives", "major defensive", "major defensives",
    }) then
        return nil
    end
    local kind, scope = ResolveScope(text, ctx)
    if not kind or not scope then
        return {
            kind = "answer", status = "ambiguous",
            text = "I can narrow Buffs to major defensives or to external defensives from other players. Which frame should I change? For example: 'major defensive target buffs' or 'external defensive raid buffs'. I changed nothing.",
            summary = "Asks for the missing defensive-aura scope.",
        }
    end
    local choices = {}
    local mode = IsOnlyIntent(text) and "replace" or "enable"
    local big = FilterSpecByID("bigDefensive")
    local external = FilterSpecByID("externalDefensive")
    if kind == "group" then
        AddChoice(choices, ChoiceFromPlan(GroupFilterPlan(scope, "buff", big, mode), "Major defensive buffs"))
        AddChoice(choices, ChoiceFromPlan(GroupFilterPlan(scope, "buff", external, mode), "External defensive buffs from other players"))
    else
        AddChoice(choices, ChoiceFromPlan(UnitFilterPlan(scope, "buff", big, mode), "Major defensive buffs"))
        AddChoice(choices, ChoiceFromPlan(UnitFilterPlan(scope, "buff", external, mode), "External defensive buffs from other players"))
    end
    return {
        kind = "ambiguous", choices = choices,
        choiceIntro = "'Defensives' can mean two different MSUF filters. Which one do you mean for " .. ScopeLabel(kind, scope) .. " Buffs?",
        summary = "Offers executable major-versus-external defensive choices.",
    }
end

local function FilterPlan(text, ctx)
    local spec = FindFilterSpec(text)
    local sourceIntent = SourceIntent(text)
    local kind, scope = ResolveScope(text, ctx)
    local lane = ResolveLane(text, ctx)
    if spec and spec.lane then lane = spec.lane end

    local showAllWording = HasAny(text, { "show all", "show everything" })
    local clearAll = HasAny(text, { "show all", "show everything", "all sources", "from everyone", "regardless of source", "clear filter", "clear the filter", "no filter" })
        or (HasAny(text, { "clear" }) and HasAny(text, { "filter", "filters" }))
    if clearAll and not spec then spec = FilterSpecByID("onlyMine") end
    local only = IsOnlyIntent(text)
    local disable = spec and IsDisableFilterIntent(text)

    if sourceIntent == "unsupportedNotMine" then
        return {
            kind = "answer", status = "ambiguous",
            text = "MSUF can filter to auras cast by you, but it has no safe inverse for 'everyone except me'. I changed nothing. Try 'only show my target buffs', 'show target buffs from everyone', or use an exact SpellID rule when Blizzard permits identity filtering.",
            summary = "Explains that the inverse player-caster filter is unavailable.",
        }
    end

    if spec and IsUnsupportedExcludeIntent(text) and not disable
        and not (spec.id == "onlyMine" and sourceIntent == "mine")
    then
        return {
            kind = "answer", status = "ambiguous",
            text = "That MSUF filter is an include/narrowing rule. Turning it off stops limiting the lane to " .. spec.label .. "; it does not hide only those matching auras while keeping everything else. I changed nothing. Try 'show only " .. spec.label:lower() .. " target " .. (spec.lane == "buff" and "buffs" or "debuffs") .. "', 'turn off the " .. spec.label:lower() .. " filter', or use an exact SpellID list when Blizzard permits it.",
            summary = "Explains positive aura filter semantics instead of applying an inverse exclusion.",
        }
    end

    if not lane or lane == "both" then
        if spec and spec.lane then lane = spec.lane end
    end
    if not lane or lane == "both" then
        return {
            kind = "answer", status = "ambiguous",
            text = "Which aura lane should this filter apply to: Buffs or Debuffs? Also name the frame if it is not already clear—for example: 'show only my target buffs' or 'show only dispellable raid debuffs'. I changed nothing.",
            summary = "Asks for the missing aura lane.",
        }
    end

    if not kind or not scope then
        if spec then
            local mode = clearAll and "clear" or (disable and "disable" or (only and "replace" or "enable"))
            if spec.id == "onlyMine" and sourceIntent == "everyone" then mode = "disable" end
            local choices = FilterScopeChoices(lane, spec, mode, sourceIntent)
            return {
                kind = "ambiguous", choices = choices,
                choiceIntro = "I understand the filter goal: " .. spec.label .. " for " .. LaneLabel(lane) .. ". Which frame should use it?",
                summary = "Asks for the missing aura scope with executable choices.",
            }
        end
        return {
            kind = "answer", status = "ambiguous",
            text = "Let's narrow this down in two parts: name the frame, then Buffs or Debuffs. Examples: 'filter player buffs', 'filter target debuffs', or 'filter raid buffs'. I changed nothing.",
            summary = "Guides the user to an aura filter scope and lane.",
        }
    end

    if showAllWording and kind == "unit" then
        return {
            kind = "ambiguous", choices = UnitShowAllChoices(scope, lane),
            choiceIntro = "'Show all' can mean two things for " .. ScopeLabel(kind, scope) .. " " .. LaneLabel(lane) .. ". Should I clear their live/permanent filters too, or only turn the lane on? Exact SpellID lists stay unchanged either way.",
            summary = "Clarifies lane visibility versus clearing aura content filters.",
        }
    end

    if not spec and not clearAll then
        local choices = GuideChoices(kind, scope, lane)
        return {
            kind = "ambiguous", choices = choices,
            choiceIntro = "What should " .. ScopeLabel(kind, scope) .. " " .. LaneLabel(lane) .. " keep? These choices change content filtering only; none disables the aura lane.",
            summary = "Offers executable, goal-based aura filter choices.",
        }
    end

    local mode = clearAll and "clear" or (disable and "disable" or (only and "replace" or "enable"))
    if spec and spec.id == "onlyMine" and sourceIntent == "everyone" then mode = "disable" end
    if kind == "group" then
        if mode == "disable" then
            return {
                kind = "answer", status = "ambiguous",
                text = "Group aura lanes use one dropdown, so a category is not independently toggled off. Choose another group filter or say 'show all " .. ScopeLabel(kind, scope):lower() .. " " .. LaneLabel(lane):lower() .. "'. I changed nothing.",
                summary = "Explains the group aura single-token model.",
            }
        end
        return GroupFilterPlan(scope, lane, spec, mode, sourceIntent)
    end
    return UnitFilterPlan(scope, lane, spec, mode, sourceIntent)
end

local function GroupCategoryPlan(text, ctx)
    if not (P.AURA_BLACKLIST_PRESETS and type(P.AURA_BLACKLIST_PRESETS) == "table") then return nil end
    local category
    for i = 1, #P.AURA_BLACKLIST_PRESETS do
        local spec = P.AURA_BLACKLIST_PRESETS[i]
        local genericRaidBuffs = spec.key == "RAID_BUFFS" and not HasAny(text, { "long term", "long-term", "category", "preset" })
        if not genericRaidBuffs and HasAny(text, spec.aliases or {}) then category = spec.key; break end
    end
    if not category then return nil end
    local explicitGroupScope = HasAny(text, { "party", "raid", "mythic raid", "mythicraid", "group frame", "group frames" })
    local currentGroupPage = M and (M.activeKey == "gf_auras" or M.activeKey == "gf_layout")
    if not explicitGroupScope and not currentGroupPage then return nil end
    local kind, scope = ResolveScope(text, ctx)
    local lane = ResolveLane(text, ctx)
    if kind ~= "group" or not scope or not lane or lane == "both" then return nil end
    local settingScope = scope == "mythicraid" and "raid" or scope
    local setting = Setting("gf_" .. settingScope .. ".auras." .. lane .. ".blacklistCats." .. category)
    if not setting then return nil end
    local value
    if HasAny(text, { "show", "allow", "include", "unhide", "remove from blacklist" }) then value = false end
    if HasAny(text, { "hide", "block", "blacklist", "exclude" }) then value = true end
    if value == nil or IsQuestion(text) then return nil end
    local scopeLabel = scope == "mythicraid" and "Raid and Mythic Raid" or ScopeLabel("group", scope)
    return {
        kind = "changes", changes = { { setting = setting, value = value } },
        label = scopeLabel .. " " .. LaneLabel(lane) .. " category " .. category,
        summary = "Changes one effective group aura category blacklist entry.",
        successText = value
            and ("Done — the " .. category .. " category is hidden from " .. scopeLabel .. " " .. LaneLabel(lane) .. ". The lane stays enabled.")
            or ("Done — the " .. category .. " category can show again on " .. scopeLabel .. " " .. LaneLabel(lane) .. "."),
    }
end

function P.LooksLikeAuraFilteringConversation(text, ctx)
    text = type(Normalize) == "function" and Normalize(text) or tostring(text or ""):lower()
    if text == "" then return false end
    local durationIntent = DurationIntent(text)
    local explicitSpellList = HasAny(text, { "spell id", "spellid", "spell:", "hidden spell", "hidden aura" })
        or text:match("#?%d%d%d+") ~= nil
    if explicitSpellList or (HasAny(text, SPECIFIC_LIST_TERMS) and not durationIntent) then return false end
    if ExistingAuraFilterSpecialistOwns(text) then return false end
    local spec = FindFilterSpec(text)
    local filterMasterIntent = FilterMasterIntent(text) ~= nil
    local genericDefensive = HasAny(text, { "defensive", "defensives", "defensive buff", "defensive buffs" })
    local auraNoun = HasAny(text, { "aura", "auras", "buff", "buffs", "debuff", "debuffs" })
    if spec and spec.id == "raidInCombat" and not auraNoun
        and not HasAny(text, { "filter", "filters", "filtering" })
    then
        return false
    end
    if not auraNoun and not spec and not genericDefensive and not filterMasterIntent then
        local kind = ContextScopeLane(ctx)
        if not kind then return false end
    end
    if durationIntent then return true end
    if filterMasterIntent then return true end
    if GroupCategoryPlan(text, ctx) then return true end
    if HasAny(text, FILTER_HELP_TERMS) then return true end
    -- A short answer to the overview (for example, just "dispellable") is a
    -- meaningful filter goal. The semantic parser will ask for the missing
    -- frame with executable choices. Avoid the overloaded Raid/Player words,
    -- which can name a frame or group outside an aura conversation.
    if spec and not auraNoun and spec.id ~= "raid" and spec.id ~= "raidInCombat"
        and spec.id ~= "onlyMine"
    then
        return true
    end
    if spec and (HasAny(text, { "filter", "only", "show", "hide", "include", "exclude", "display", "let", "clear" }) or IsDisableFilterIntent(text)) then return true end
    if spec and auraNoun then return true end
    if auraNoun and HasAny(text, { "show all", "show everything" })
        and not HasAny(text, { "setting", "settings", "option", "options", "page", "pages", "control", "controls" })
    then
        return true
    end
    if genericDefensive and HasAny(text, { "show", "only", "filter", "display", "track", "see" }) then return true end
    if HasAny(text, { "filter", "filters", "filtering" }) and auraNoun then return true end
    return false
end

function P.ParseAuraFilteringConversationShortcut(text, ctx, raw)
    text = type(Normalize) == "function" and Normalize(text) or tostring(text or ""):lower()
    ctx = type(ctx) == "table" and ctx or (type(A.GetContext) == "function" and A.GetContext() or {})
    -- A few native sort comparators share names with filter tokens (for
    -- example Big Defensive). Exact lane-sort aliases own explicit sorting
    -- language and must not be converted into live-filter mutations.
    if type(P.IsAuraSortRequest) == "function" and P.IsAuraSortRequest(text)
        and HasAny(text, { "sort", "sorting", "order", "ordered", "first" })
    then
        return nil
    end
    -- Group externals also own a layer setting whose exact alias carries
    -- the same filter-token wording ("party external defensive layer"). A
    -- layer change is never a live-filter mutation, so leave that language to the
    -- exact aliases on the gf_<scope>.auras.externals.layer settings.
    -- A numbered Custom Aura container names one exact control, and each
    -- container carries its own copy of every filter token. Claiming that
    -- wording as a live-filter mutation made settings like
    -- "player custom aura 1 hide permanent" unreachable: the exact alias
    -- resolves them correctly, this lane answered "ambiguous" first.
    if text:find("custom%s+aura%s+%d") or text:find("custom%s+container%s+%d") then
        return nil
    end
    -- The externals record owns more than its layer now (lane toggle, auto
    -- list, max icons, growth). None of those wordings is a live-filter
    -- mutation, so they belong to the exact aliases on
    -- gf_<scope>.auras.externals.*. A bare "external defensives" stays here:
    -- that is the Buff filter token.
    -- The hyphenated spellings matter: the controls' own labels read
    -- "External Defensive Auto-blacklist from Buffs", and matching only the
    -- spaced form let that exact label through to be read as a filter token --
    -- "set party external defensive auto-blacklist from buffs to on" wrote
    -- gf_party.auras.buff.filterToken = ExternalDefensive and never touched the
    -- control the player named.
    if HasAny(text, {
        "layer", "strata", "draw layer", "frame level",
        "external defensive lane", "externals lane", "external defensive strip",
        "auto list", "auto-list", "auto blacklist", "auto-blacklist",
        "autoblacklist", "max icons", "growth", "grow direction",
    }) then
        return nil
    end
    if not P.LooksLikeAuraFilteringConversation(text, ctx) then return nil end

    local categoryPlan = GroupCategoryPlan(text, ctx)
    if categoryPlan then return categoryPlan end

    local durationPlan = DurationPlan(text, ctx)
    if durationPlan then return durationPlan end

    local masterPlan = FilterMasterPlan(text, ctx)
    if masterPlan then return masterPlan end

    local defensivePlan = GenericDefensivePlan(text, ctx)
    if defensivePlan then return defensivePlan end

    if HasAny(text, FILTER_HELP_TERMS) and not FindFilterSpec(text) then
        local kind, scope = ResolveScope(text, ctx)
        local lane = ResolveLane(text, ctx)
        if kind and scope and lane and lane ~= "both" then return FilterPlan(text, ctx) end
        return {
            kind = "answer", status = "info",
            text = "Auras, buffs, and debuffs help\nAura filtering works best as three small choices: frame or group, Buffs or Debuffs, then the goal. Goals include only timed auras, only auras cast by your player, raid/encounter relevance, dispellable or crowd-control debuffs, defensive buffs, show all, exact SpellID/category lists, and Custom Aura 1–3 include lists. The live-filter master, Hide Permanent, lane visibility, and timer styling are separate controls. Example: 'filter target debuffs to only ones I can dispel'. I changed nothing.",
            summary = "Explains the guided aura-filter flow without mutating a setting.",
        }
    end
    return FilterPlan(text, ctx)
end
