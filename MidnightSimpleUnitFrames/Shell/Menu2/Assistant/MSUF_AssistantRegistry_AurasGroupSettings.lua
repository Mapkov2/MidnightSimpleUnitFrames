-- Assistant Group Aura registry: maps group aura settings to registry metadata.
-- Aura rendering remains Auras3-owned; broad group changes must keep confirmation semantics.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local A = MSUF.Assistant or {}
MSUF.Assistant = A

-- Group Auras assistant registry domain.
local ctx = A.AurasRegistry and A.AurasRegistry.GroupSettings
if type(ctx) ~= "table" then return end

local Registry = ctx.Registry
A = ctx.A or A
local UNIT_LABELS = ctx.UNIT_LABELS or {}
local UNIT_ALIASES = ctx.UNIT_ALIASES or {}
local AddAliasesForUnit = ctx.AddAliasesForUnit
local AuraModel = ctx.AuraModel
local GFAurasRoot = ctx.GFAurasRoot
local GFAuraLaneShown = ctx.GFAuraLaneShown
local SetGFAuraLaneShown = ctx.SetGFAuraLaneShown
local GFReadAuraNumber = ctx.GFReadAuraNumber
local GFWriteAuraNumber = ctx.GFWriteAuraNumber
local GFReadAuraValue = ctx.GFReadAuraValue
local GFWriteAuraValue = ctx.GFWriteAuraValue
local ApplyGroup = ctx.ApplyGroup
local AURA_LANES = ctx.AURA_LANES or {}
local AURA_RELATIVE_SIZE_NOUNS = ctx.AURA_RELATIVE_SIZE_NOUNS or {}

if not (Registry and type(Registry.RegisterSetting) == "function") then return end
if type(AddAliasesForUnit) ~= "function" or type(AuraModel) ~= "function" then return end
if type(GFAurasRoot) ~= "function" or type(GFAuraLaneShown) ~= "function" or type(SetGFAuraLaneShown) ~= "function" then return end
if type(GFReadAuraNumber) ~= "function" or type(GFWriteAuraNumber) ~= "function" then return end
if type(GFReadAuraValue) ~= "function" or type(GFWriteAuraValue) ~= "function" then return end
if type(ApplyGroup) ~= "function" then return end
local GF_AURA_GROUPS = { "party", "raid", "mythicraid" }
local GF_AURA_ANCHORS = { "CENTER", "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }
local GF_AURA_GROWTH = { "RIGHTDOWN", "LEFTDOWN", "RIGHTUP", "LEFTUP" }
local GF_AURA_FILTER_VALUES = {
    buff = { "ALL", "PLAYER", "RAID", "IMPORTANT" },
    debuff = { "ALL", "PLAYER", "RAID", "DISPELLABLE", "IMPORTANT" },
}
local GF_AURA_FILTER_ALIASES = {
    all = "ALL",
    everything = "ALL",
    player = "PLAYER",
    mine = "PLAYER",
    ["my auras"] = "PLAYER",
    raid = "RAID",
    boss = "RAID",
    encounter = "RAID",
    important = "IMPORTANT",
    importantonly = "IMPORTANT",
    ["important only"] = "IMPORTANT",
    dispellable = "DISPELLABLE",
    purgeable = "DISPELLABLE",
}

local function AddGFAuraAliases(out, scope, lane, noun)
    local laneWord = lane == "buff" and "buff" or "debuff"
    local lanePlural = lane == "buff" and "buffs" or "debuffs"
    AddAliasesForUnit(out, scope, laneWord .. " " .. noun)
    AddAliasesForUnit(out, scope, lanePlural .. " " .. noun)
    AddAliasesForUnit(out, scope, "aura " .. laneWord .. " " .. noun)
    AddAliasesForUnit(out, scope, "aura " .. lanePlural .. " " .. noun)
end

local function AddGFAuraStrictAliases(out, scope, lane, noun)
    local laneWord = lane == "buff" and "buff" or "debuff"
    local lanePlural = lane == "buff" and "buffs" or "debuffs"
    local aliases = UNIT_ALIASES[scope] or { scope }
    for i = 1, #aliases do
        local s = aliases[i]
        if s ~= "group" and s ~= "group frames" and s ~= "gruppenframes" and s ~= "gruppe" then
            out[#out + 1] = s .. " " .. laneWord .. " " .. noun
            out[#out + 1] = s .. " " .. lanePlural .. " " .. noun
            out[#out + 1] = laneWord .. " " .. noun .. " " .. s
            out[#out + 1] = lanePlural .. " " .. noun .. " " .. s
            out[#out + 1] = s .. " aura " .. laneWord .. " " .. noun
            out[#out + 1] = s .. " aura " .. lanePlural .. " " .. noun
        end
    end
end

local function AddGFAuraRelativeSizeAliases(out, scope, lane)
    for i = 1, #AURA_RELATIVE_SIZE_NOUNS do
        AddGFAuraStrictAliases(out, scope, lane, AURA_RELATIVE_SIZE_NOUNS[i])
    end
end

A._AssistantAddGFAuraAllLaneAlias = A._AssistantAddGFAuraAllLaneAlias or function(out, scope, noun)
    local aliases = UNIT_ALIASES[scope] or { scope }
    for i = 1, #aliases do
        local s = aliases[i]
        if s ~= "group" and s ~= "group frames" and s ~= "gruppenframes" and s ~= "gruppe" then
            out[#out + 1] = s .. " aura " .. noun
            out[#out + 1] = s .. " auras " .. noun
            out[#out + 1] = "aura " .. noun .. " " .. s
            out[#out + 1] = "auras " .. noun .. " " .. s
        end
    end
end

A._AssistantAddGFAuraAllLaneAliases = A._AssistantAddGFAuraAllLaneAliases or function(out, scope, nouns)
    for i = 1, #(nouns or {}) do
        A._AssistantAddGFAuraAllLaneAlias(out, scope, nouns[i])
    end
end

A._AssistantAddGFAuraAllLaneRelativeSizeAliases = A._AssistantAddGFAuraAllLaneRelativeSizeAliases or function(out, scope)
    for i = 1, #AURA_RELATIVE_SIZE_NOUNS do
        A._AssistantAddGFAuraAllLaneAlias(out, scope, AURA_RELATIVE_SIZE_NOUNS[i])
    end
end

local function RegisterGFAuraBoolean(scope, lane, attr, key, label, defaultValue, aliases)
    Registry:RegisterSetting({
        key = "gf_" .. scope .. ".auras." .. lane .. "." .. key,
        label = UNIT_LABELS[scope] .. " " .. label,
        category = UNIT_LABELS[scope] .. " / Group Auras",
        unit = scope,
        frameType = "groupAura",
        attribute = "gfAura" .. lane .. attr,
        type = "boolean",
        aliases = aliases,
        exactAliases = aliases,
        get = function()
            if key == "enabled" then return GFAuraLaneShown(scope, lane) end
            local value = GFReadAuraValue(scope, lane, key, defaultValue)
            return value and true or false
        end,
        set = function(value)
            if key == "enabled" then SetGFAuraLaneShown(scope, lane, value) else GFWriteAuraValue(scope, lane, key, value and true or false) end
        end,
        apply = function() ApplyGroup(scope, "visual") end,
        combatSafe = false,
    })
end

local function RegisterGFAuraNumber(scope, lane, attr, key, label, defaultValue, minValue, maxValue, aliases, mode, opts)
    opts = opts or {}
    Registry:RegisterSetting({
        key = "gf_" .. scope .. ".auras." .. lane .. "." .. key,
        label = UNIT_LABELS[scope] .. " " .. label,
        category = UNIT_LABELS[scope] .. " / Group Auras",
        unit = scope,
        frameType = "groupAura",
        attribute = "gfAura" .. lane .. attr,
        type = "number",
        aliases = aliases,
        exactAliases = opts.exactAliases or aliases,
        min = minValue,
        max = maxValue,
        step = 1,
        moveAxis = opts.moveAxis,
        moveStep = opts.moveStep,
        moveAmount = opts.moveAmount,
        get = function() return GFReadAuraNumber(scope, lane, key, defaultValue) end,
        set = function(value) GFWriteAuraNumber(scope, lane, key, value, minValue, maxValue, 1) end,
        apply = function() ApplyGroup(scope, mode or "geometry") end,
        combatSafe = false,
    })
end

local function RegisterGFAuraEnum(scope, lane, attr, key, label, values, valueAliases, defaultValue, aliases, mode, opts)
    opts = opts or {}
    local allowed = {}
    for i = 1, #values do allowed[values[i]] = true end
    Registry:RegisterSetting({
        key = "gf_" .. scope .. ".auras." .. lane .. "." .. key,
        label = UNIT_LABELS[scope] .. " " .. label,
        category = UNIT_LABELS[scope] .. " / Group Auras",
        unit = scope,
        frameType = "groupAura",
        attribute = "gfAura" .. lane .. attr,
        type = "enum",
        aliases = aliases,
        exactAliases = opts.exactAliases or aliases,
        values = values,
        valueAliases = valueAliases,
        get = function()
            local value = GFReadAuraValue(scope, lane, key, defaultValue)
            return allowed[value] and value or defaultValue
        end,
        set = function(value) GFWriteAuraValue(scope, lane, key, allowed[value] and value or defaultValue) end,
        apply = function() ApplyGroup(scope, mode or "geometry") end,
        combatSafe = false,
    })
end

local function RegisterGFAuraRootBoolean(scope, attr, key, label, defaultValue, aliases, mode)
    Registry:RegisterSetting({
        key = "gf_" .. scope .. ".auras." .. key,
        label = UNIT_LABELS[scope] .. " " .. label,
        category = UNIT_LABELS[scope] .. " / Group Auras",
        unit = scope,
        frameType = "groupAura",
        attribute = "gfAura" .. attr,
        type = "boolean",
        aliases = aliases,
        exactAliases = aliases,
        get = function()
            local value = GFAurasRoot(scope)[key]
            if value == nil then return defaultValue and true or false end
            return value and true or false
        end,
        set = function(value) GFAurasRoot(scope)[key] = value and true or false end,
        apply = function() ApplyGroup(scope, mode or "visual") end,
        combatSafe = false,
    })
end

local GF_AURA_CATEGORY_SCOPES = { "party", "raid" }
local GF_AURA_CATEGORY_FALLBACK = {
    { key = "RAID_BUFFS", label = "Long-term Raid Buffs", aliases = { "raid buffs", "long term raid buffs", "raid buff" } },
    { key = "PRESERVATION_EVOKER", label = "Preservation Evoker", aliases = { "preservation evoker", "pres evoker" } },
    { key = "AUGMENTATION_EVOKER", label = "Augmentation Evoker", aliases = { "augmentation evoker", "aug evoker" } },
    { key = "RESTO_DRUID", label = "Restoration Druid", aliases = { "resto druid", "restoration druid" } },
    { key = "DISC_PRIEST", label = "Discipline Priest", aliases = { "disc priest", "discipline priest" } },
    { key = "HOLY_PRIEST", label = "Holy Priest", aliases = { "holy priest" } },
    { key = "MISTWEAVER_MONK", label = "Mistweaver Monk", aliases = { "mistweaver monk", "mw monk" } },
    { key = "RESTO_SHAMAN", label = "Restoration Shaman", aliases = { "resto shaman", "restoration shaman" } },
    { key = "HOLY_PALADIN", label = "Holy Paladin", aliases = { "holy paladin", "holy pala" } },
    { key = "BLESSING_BRONZE", label = "Blessing of the Bronze", aliases = { "blessing of the bronze", "bronze blessing" } },
    { key = "SELF_BUFFS", label = "Long-term Self Buffs", aliases = { "self buffs", "long term self buffs" } },
    { key = "ROGUE_POISONS", label = "Rogue Poisons", aliases = { "rogue poisons", "poisons" } },
    { key = "SHAMAN_IMBUE", label = "Shaman Imbuements", aliases = { "shaman imbues", "shaman imbuements", "imbues" } },
    { key = "RESOURCE_AURAS", label = "Resource Auras", aliases = { "resource auras", "resource buffs" } },
    { key = "COOLDOWNS", label = "Cooldowns", aliases = { "cooldowns", "cooldown auras" } },
    { key = "SATED", label = "Sated / Exhaustion", aliases = { "sated", "exhaustion", "heroism exhaustion", "bloodlust exhaustion" } },
    { key = "DESERTER", label = "Deserter", aliases = { "deserter", "deserteur" } },
}

local function CompactAuraCategory(value)
    return tostring(value or ""):lower():gsub("[^%w]+", "")
end

local function GFAuraCategoryScope(scope)
    return scope == "party" and "party" or "raid"
end

local function GFAuraCategoryScopeLabel(scope)
    return GFAuraCategoryScope(scope) == "party" and "Party" or "Raid / Mythic Raid"
end

local function GFAuraCategoryLane(lane)
    return lane == "debuff" and "debuff" or "buff"
end

local function GFAuraCategoryLaneLabel(lane)
    return GFAuraCategoryLane(lane) == "debuff" and "Debuff" or "Buff"
end

local function GFAuraCategoryLanePlural(lane)
    return GFAuraCategoryLane(lane) == "debuff" and "Debuffs" or "Buffs"
end

local function GFAuraCategoryValues()
    local Model = AuraModel()
    if Model and type(Model.GroupBlacklistCategoryValues) == "function" then
        local values = Model.GroupBlacklistCategoryValues()
        if type(values) == "table" and #values > 0 then return values end
    end
    return GF_AURA_CATEGORY_FALLBACK
end

local function GFAuraCategoryLabel(catKey)
    catKey = tostring(catKey or "")
    local Model = AuraModel()
    if Model and type(Model.GroupBlacklistCategoryLabel) == "function" then
        local label = Model.GroupBlacklistCategoryLabel(catKey)
        if type(label) == "string" and label ~= "" then return label end
    end
    if catKey == "RAID_BUFFS" then return "Raid / Mythic Buffs" end
    local values = GFAuraCategoryValues()
    for i = 1, #values do
        local item = values[i]
        if item and (item.key == catKey or item.value == catKey) then return item.label or item.text or catKey end
    end
    return catKey
end

local function ResolveGFAuraCategory(value)
    local Model = AuraModel()
    if Model and type(Model.ResolveGroupBlacklistCategory) == "function" then
        local resolved = Model.ResolveGroupBlacklistCategory(value)
        if type(resolved) == "string" and resolved ~= "" then return resolved end
    end
    local compact = CompactAuraCategory(value)
    if compact == "" then return nil end
    local values = GFAuraCategoryValues()
    local bestKey, bestLen
    for i = 1, #values do
        local item = values[i]
        local key = item and (item.key or item.value)
        if key then
            local candidates = { key, item.label, item.text }
            if type(item.aliases) == "table" then
                for j = 1, #item.aliases do candidates[#candidates + 1] = item.aliases[j] end
            end
            for j = 1, #candidates do
                local token = CompactAuraCategory(candidates[j])
                if token ~= "" then
                    local matchLen
                    if compact == token then
                        matchLen = #token
                    elseif #token >= 5 and compact:find(token, 1, true) then
                        matchLen = #token
                    end
                    if matchLen and (not bestLen or matchLen > bestLen) then
                        bestKey, bestLen = key, matchLen
                    end
                end
            end
        end
    end
    return bestKey
end
A.ResolveAuraGroupCategory = ResolveGFAuraCategory
A.AuraGroupCategoryLabel = GFAuraCategoryLabel

local function ReadGFAuraCategoryState(scope, lane, catKey)
    scope = GFAuraCategoryScope(scope)
    lane = GFAuraCategoryLane(lane)
    catKey = ResolveGFAuraCategory(catKey) or catKey
    local Model = AuraModel()
    if Model and type(Model.ReadGroupBlacklistCategoryState) == "function" then
        local state = Model.ReadGroupBlacklistCategoryState(scope, lane, catKey)
        if type(state) == "table" then return state end
    end
    local function read(kind)
        local group = GFAuraGroup(kind, lane)
        return type(group.blacklistCats) == "table" and group.blacklistCats[catKey] == true
    end
    if scope == "party" then return { party = read("party") } end
    return { raid = read("raid"), mythicraid = read("mythicraid") }
end

local function WriteGFAuraCategoryKind(kind, lane, catKey, value)
    local group = GFAuraGroup(kind, lane)
    if type(group.blacklistCats) ~= "table" then group.blacklistCats = {} end
    group.blacklistCats[catKey] = value and true or nil
end

local function WriteGFAuraCategoryState(scope, lane, catKey, value)
    scope = GFAuraCategoryScope(scope)
    lane = GFAuraCategoryLane(lane)
    catKey = ResolveGFAuraCategory(catKey) or catKey
    if type(catKey) ~= "string" or catKey == "" then return false end
    local Model = AuraModel()
    if Model and type(Model.WriteGroupBlacklistCategoryState) == "function" then
        return Model.WriteGroupBlacklistCategoryState(scope, lane, catKey, value)
    end
    if type(value) == "table" then
        if scope == "party" then
            WriteGFAuraCategoryKind("party", lane, catKey, value.party == true)
        else
            WriteGFAuraCategoryKind("raid", lane, catKey, value.raid == true)
            WriteGFAuraCategoryKind("mythicraid", lane, catKey, value.mythicraid == true)
        end
        return true
    end
    if scope == "party" then
        WriteGFAuraCategoryKind("party", lane, catKey, value)
    else
        WriteGFAuraCategoryKind("raid", lane, catKey, value)
        WriteGFAuraCategoryKind("mythicraid", lane, catKey, value)
    end
    return true
end

local function ReadGFAuraCategorySetting(scope, lane, catKey)
    local state = ReadGFAuraCategoryState(scope, lane, catKey)
    if GFAuraCategoryScope(scope) == "party" then return state.party == true end
    local raid = state.raid == true
    local mythic = state.mythicraid == true
    if raid == mythic then return raid end
    return state
end

local function SameGFAuraCategoryState(oldValue, newValue)
    if type(oldValue) ~= "table" then return oldValue == newValue end
    if oldValue.party ~= nil then return (oldValue.party == true) == (newValue == true) end
    return (oldValue.raid == true) == (newValue == true) and (oldValue.mythicraid == true) == (newValue == true)
end

local function ApplyGFAuraCategory(scope)
    scope = GFAuraCategoryScope(scope)
    if scope == "party" then
        ApplyGroup("party", "visual")
    else
        ApplyGroup("raid", "visual")
        ApplyGroup("mythicraid", "visual")
    end
end

local function GFAuraCategorySummary(scope, lane)
    scope = GFAuraCategoryScope(scope)
    lane = GFAuraCategoryLane(lane)
    local Model = AuraModel()
    if Model and type(Model.GroupBlacklistCategorySummary) == "function" then
        return Model.GroupBlacklistCategorySummary(scope, lane)
    end
    local statePrefix = scope == "party" and "party" or "raid"
    local group = GFAuraGroup(statePrefix, lane)
    local cats = type(group.blacklistCats) == "table" and group.blacklistCats or nil
    if type(cats) ~= "table" then return "No blacklisted aura categories." end
    local out = {}
    for key, enabled in pairs(cats) do
        if enabled == true then out[#out + 1] = GFAuraCategoryLabel(key) end
    end
    table.sort(out)
    if #out == 0 then return "No blacklisted aura categories." end
    return table.concat(out, "\n")
end

local function ClearGFAuraCategoryBlacklist(scope, lane)
    scope = GFAuraCategoryScope(scope)
    lane = GFAuraCategoryLane(lane)
    local values = GFAuraCategoryValues()
    local count = 0
    for i = 1, #values do
        local item = values[i]
        local catKey = item and (item.key or item.value)
        if catKey then
            local state = ReadGFAuraCategorySetting(scope, lane, catKey)
            local wasBlocked = state == true
            if type(state) == "table" then
                if state.party == true or state.raid == true or state.mythicraid == true then wasBlocked = true end
            end
            if wasBlocked then
                WriteGFAuraCategoryState(scope, lane, catKey, false)
                count = count + 1
            end
        end
    end
    if count > 0 then ApplyGFAuraCategory(scope) end
    return count
end

local function AddGFAuraBlacklistSpell(scope, lane, value)
    local Model = AuraModel()
    if not (Model and type(Model.AddGroupBlacklistSpell) == "function") then return false end
    return Model.AddGroupBlacklistSpell(GFAuraCategoryScope(scope), GFAuraCategoryLane(lane), value)
end

local function RemoveGFAuraBlacklistSpell(scope, lane, value)
    local Model = AuraModel()
    if not (Model and type(Model.RemoveGroupBlacklistSpell) == "function") then return false end
    return Model.RemoveGroupBlacklistSpell(GFAuraCategoryScope(scope), GFAuraCategoryLane(lane), value)
end

local function ClearGFAuraBlacklistSpells(scope, lane)
    local Model = AuraModel()
    if not (Model and type(Model.ClearGroupBlacklistSpells) == "function") then return 0 end
    return Model.ClearGroupBlacklistSpells(GFAuraCategoryScope(scope), GFAuraCategoryLane(lane))
end

local function GFAuraBlacklistSummary(scope, lane)
    local Model = AuraModel()
    if Model and type(Model.GroupBlacklistSummary) == "function" then
        return Model.GroupBlacklistSummary(GFAuraCategoryScope(scope), GFAuraCategoryLane(lane))
    end
    return "No blacklisted spells."
end

local function AddGFAuraBlacklistPreset(scope, lane, preset)
    local Model = AuraModel()
    if not (Model and type(Model.AddGroupBlacklistPresetGroup) == "function") then return 0 end
    return Model.AddGroupBlacklistPresetGroup(GFAuraCategoryScope(scope), GFAuraCategoryLane(lane), preset)
end
A.GroupAuraCategoryScope = GFAuraCategoryScope
A.GroupAuraCategoryScopeLabel = GFAuraCategoryScopeLabel
A.GroupAuraCategoryLane = GFAuraCategoryLane
A.GroupAuraCategoryLanePlural = GFAuraCategoryLanePlural
A.WriteGroupAuraCategoryState = WriteGFAuraCategoryState
A.ApplyGroupAuraCategory = ApplyGFAuraCategory
A.GroupAuraCategorySummary = GFAuraCategorySummary
A.ClearGroupAuraCategoryBlacklist = ClearGFAuraCategoryBlacklist
A.AddGroupAuraBlacklistSpell = AddGFAuraBlacklistSpell
A.RemoveGroupAuraBlacklistSpell = RemoveGFAuraBlacklistSpell
A.ClearGroupAuraBlacklistSpells = ClearGFAuraBlacklistSpells
A.GroupAuraBlacklistSummary = GFAuraBlacklistSummary
A.AddGroupAuraBlacklistPreset = AddGFAuraBlacklistPreset

for _, scope in ipairs(GF_AURA_GROUPS) do
    for _, laneInfo in ipairs(AURA_LANES) do
        local lane = laneInfo.key
        local maxDefault = 6
        local sizeDefault = lane == "buff" and 22 or 20
        local perRowDefault = lane == "buff" and 4 or 3
        local anchorDefault = lane == "buff" and "BOTTOMRIGHT" or "TOPLEFT"
        local growthDefault = lane == "buff" and "LEFTUP" or "RIGHTDOWN"
        local layerDefault = lane == "buff" and 5 or 6
        local aliases = {}
        AddAliasesForUnit(aliases, scope, laneInfo.plural:lower())
        AddGFAuraAliases(aliases, scope, lane, "visibility")
        RegisterGFAuraBoolean(scope, lane, "Visible", "enabled", laneInfo.plural, true, aliases)

        aliases = {}
        AddGFAuraAliases(aliases, scope, lane, "max icons")
        AddGFAuraAliases(aliases, scope, lane, "count")
        local exactAliases = {}
        for i = 1, #aliases do exactAliases[#exactAliases + 1] = aliases[i] end
        A._AssistantAddGFAuraAllLaneAliases(aliases, scope, { "max icons", "maximum icons", "icon count", "count" })
        A._AssistantAddAllAuraNouns(aliases, lane, "all group", { "max icons", "maximum icons", "icon count", "count" })
        A._AssistantAddAllAuraNouns(aliases, lane, "all", { "max icons", "maximum icons", "icon count", "count" })
        RegisterGFAuraNumber(scope, lane, "Max", "max", laneInfo.label .. " Max Icons", maxDefault, 0, 20, aliases, "visual")

        aliases = {}
        exactAliases = {}
        AddGFAuraStrictAliases(exactAliases, scope, lane, "size")
        AddGFAuraStrictAliases(exactAliases, scope, lane, "icon size")
        AddGFAuraRelativeSizeAliases(exactAliases, scope, lane)
        for i = 1, #exactAliases do aliases[#aliases + 1] = exactAliases[i] end
        A._AssistantAddGFAuraAllLaneAliases(aliases, scope, { "size", "icon size" })
        A._AssistantAddGFAuraAllLaneRelativeSizeAliases(aliases, scope)
        A._AssistantAddAllAuraNouns(aliases, lane, "all group", { "size", "icon size" })
        A._AssistantAddAllAuraNouns(aliases, lane, "all", { "size", "icon size" })
        A._AssistantAddAllAuraRelativeSizeAliases(aliases, lane, "all group")
        A._AssistantAddAllAuraRelativeSizeAliases(aliases, lane, "all")
        RegisterGFAuraNumber(scope, lane, "Size", "size", laneInfo.label .. " Icon Size", sizeDefault, 8, 64, aliases, "geometry")

        aliases = {}
        AddGFAuraAliases(aliases, scope, lane, "per row")
        AddGFAuraAliases(aliases, scope, lane, "icons per row")
        exactAliases = {}
        for i = 1, #aliases do exactAliases[#exactAliases + 1] = aliases[i] end
        A._AssistantAddGFAuraAllLaneAliases(aliases, scope, { "per row", "icons per row", "wrap count", "row count" })
        A._AssistantAddAllAuraNouns(aliases, lane, "all group", { "per row", "icons per row", "wrap count", "row count" })
        A._AssistantAddAllAuraNouns(aliases, lane, "all", { "per row", "icons per row", "wrap count", "row count" })
        RegisterGFAuraNumber(scope, lane, "PerRow", "perRow", laneInfo.label .. " Icons Per Row", perRowDefault, 1, 20, aliases, "geometry")

        aliases = {}
        AddGFAuraAliases(aliases, scope, lane, "spacing")
        exactAliases = {}
        for i = 1, #aliases do exactAliases[#exactAliases + 1] = aliases[i] end
        A._AssistantAddGFAuraAllLaneAliases(aliases, scope, { "spacing", "gap", "icon gap" })
        A._AssistantAddAllAuraNouns(aliases, lane, "all group", { "spacing", "gap", "icon gap" })
        A._AssistantAddAllAuraNouns(aliases, lane, "all", { "spacing", "gap", "icon gap" })
        RegisterGFAuraNumber(scope, lane, "Spacing", "spacing", laneInfo.label .. " Spacing", 1, 0, 12, aliases, "geometry")

        aliases = {}
        AddGFAuraAliases(aliases, scope, lane, "layer")
        AddGFAuraAliases(aliases, scope, lane, "z order")
        exactAliases = {}
        for i = 1, #aliases do exactAliases[#exactAliases + 1] = aliases[i] end
        A._AssistantAddGFAuraAllLaneAliases(aliases, scope, { "layer", "z order", "frame level" })
        A._AssistantAddAllAuraNouns(aliases, lane, "all group", { "layer", "z order", "frame level" })
        A._AssistantAddAllAuraNouns(aliases, lane, "all", { "layer", "z order", "frame level" })
        RegisterGFAuraNumber(scope, lane, "Layer", "layer", laneInfo.label .. " Layer", layerDefault, 1, 15, aliases, "geometry")

        aliases = {}
        local exactAliases = {}
        AddGFAuraStrictAliases(exactAliases, scope, lane, "x")
        AddGFAuraStrictAliases(exactAliases, scope, lane, "x offset")
        AddGFAuraStrictAliases(exactAliases, scope, lane, "left")
        AddGFAuraStrictAliases(exactAliases, scope, lane, "right")
        AddGFAuraStrictAliases(exactAliases, scope, lane, "links")
        AddGFAuraStrictAliases(exactAliases, scope, lane, "rechts")
        for i = 1, #exactAliases do aliases[#aliases + 1] = exactAliases[i] end
        A._AssistantAddGFAuraAllLaneAliases(aliases, scope, { "x", "x offset", "left", "right", "links", "rechts" })
        aliases[#aliases + 1] = "all group aura left"
        aliases[#aliases + 1] = "all group auras left"
        aliases[#aliases + 1] = "all group aura right"
        aliases[#aliases + 1] = "all group auras right"
        aliases[#aliases + 1] = "all aura left"
        aliases[#aliases + 1] = "all auras left"
        aliases[#aliases + 1] = "all aura right"
        aliases[#aliases + 1] = "all auras right"
        aliases[#aliases + 1] = "all group frame auras left"
        aliases[#aliases + 1] = "all group frame auras right"
        aliases[#aliases + 1] = lane == "buff" and "all group buffs left" or "all group debuffs left"
        aliases[#aliases + 1] = lane == "buff" and "all group buffs right" or "all group debuffs right"
        aliases[#aliases + 1] = lane == "buff" and "all buffs left" or "all debuffs left"
        aliases[#aliases + 1] = lane == "buff" and "all buffs right" or "all debuffs right"
        RegisterGFAuraNumber(scope, lane, "OffsetX", "x", laneInfo.label .. " X Offset", 0, -160, 160, aliases, "geometry", { moveAxis = "x", moveStep = 10 })

        aliases = {}
        exactAliases = {}
        AddGFAuraStrictAliases(exactAliases, scope, lane, "y")
        AddGFAuraStrictAliases(exactAliases, scope, lane, "y offset")
        AddGFAuraStrictAliases(exactAliases, scope, lane, "up")
        AddGFAuraStrictAliases(exactAliases, scope, lane, "down")
        AddGFAuraStrictAliases(exactAliases, scope, lane, "hoch")
        AddGFAuraStrictAliases(exactAliases, scope, lane, "runter")
        for i = 1, #exactAliases do aliases[#aliases + 1] = exactAliases[i] end
        A._AssistantAddGFAuraAllLaneAliases(aliases, scope, { "y", "y offset", "up", "down", "hoch", "runter" })
        aliases[#aliases + 1] = "all group aura up"
        aliases[#aliases + 1] = "all group auras up"
        aliases[#aliases + 1] = "all group aura down"
        aliases[#aliases + 1] = "all group auras down"
        aliases[#aliases + 1] = "all aura up"
        aliases[#aliases + 1] = "all auras up"
        aliases[#aliases + 1] = "all aura down"
        aliases[#aliases + 1] = "all auras down"
        aliases[#aliases + 1] = "all group frame auras up"
        aliases[#aliases + 1] = "all group frame auras down"
        aliases[#aliases + 1] = lane == "buff" and "all group buffs up" or "all group debuffs up"
        aliases[#aliases + 1] = lane == "buff" and "all group buffs down" or "all group debuffs down"
        aliases[#aliases + 1] = lane == "buff" and "all buffs up" or "all debuffs up"
        aliases[#aliases + 1] = lane == "buff" and "all buffs down" or "all debuffs down"
        RegisterGFAuraNumber(scope, lane, "OffsetY", "y", laneInfo.label .. " Y Offset", 0, -160, 160, aliases, "geometry", { moveAxis = "y", moveStep = 10 })

        aliases = {}
        AddGFAuraAliases(aliases, scope, lane, "anchor")
        exactAliases = {}
        for i = 1, #aliases do exactAliases[#exactAliases + 1] = aliases[i] end
        A._AssistantAddGFAuraAllLaneAliases(aliases, scope, { "anchor", "anchor point", "position anchor" })
        A._AssistantAddAllAuraNouns(aliases, lane, "all group", { "anchor", "anchor point", "position anchor" })
        A._AssistantAddAllAuraNouns(aliases, lane, "all", { "anchor", "anchor point", "position anchor" })
        RegisterGFAuraEnum(scope, lane, "Anchor", "anchor", laneInfo.label .. " Anchor", GF_AURA_ANCHORS, {
            center = "CENTER",
            middle = "CENTER",
            topleft = "TOPLEFT",
            top_left = "TOPLEFT",
            top = "TOPLEFT",
            topright = "TOPRIGHT",
            top_right = "TOPRIGHT",
            bottomleft = "BOTTOMLEFT",
            bottom_left = "BOTTOMLEFT",
            bottomright = "BOTTOMRIGHT",
            bottom_right = "BOTTOMRIGHT",
        }, anchorDefault, aliases, "geometry")

        aliases = {}
        AddGFAuraAliases(aliases, scope, lane, "growth")
        AddGFAuraAliases(aliases, scope, lane, "growth direction")
        AddGFAuraAliases(aliases, scope, lane, "grow")
        AddGFAuraAliases(aliases, scope, lane, "grow direction")
        exactAliases = {}
        for i = 1, #aliases do exactAliases[#exactAliases + 1] = aliases[i] end
        A._AssistantAddGFAuraAllLaneAliases(aliases, scope, { "growth", "grow", "growth direction", "grow direction" })
        A._AssistantAddAllAuraNouns(aliases, lane, "all group", { "growth", "grow", "growth direction", "grow direction" })
        A._AssistantAddAllAuraNouns(aliases, lane, "all", { "growth", "grow", "growth direction", "grow direction" })
        RegisterGFAuraEnum(scope, lane, "Growth", "growth", laneInfo.label .. " Growth", GF_AURA_GROWTH, {
            rightdown = "RIGHTDOWN",
            right = "RIGHTDOWN",
            down = "RIGHTDOWN",
            leftdown = "LEFTDOWN",
            left = "LEFTDOWN",
            rightup = "RIGHTUP",
            up = "RIGHTUP",
            leftup = "LEFTUP",
        }, growthDefault, aliases, "geometry")

        aliases = {}
        AddGFAuraAliases(aliases, scope, lane, "filter")
        AddGFAuraAliases(aliases, scope, lane, "filter type")
        AddGFAuraAliases(aliases, scope, lane, "inclusive filter")
        RegisterGFAuraEnum(scope, lane, "FilterToken", "filterToken", laneInfo.label .. " Filter", GF_AURA_FILTER_VALUES[lane], GF_AURA_FILTER_ALIASES, "ALL", aliases, "visual")

        aliases = {}
        AddGFAuraAliases(aliases, scope, lane, "cooldown anchor")
        AddGFAuraAliases(aliases, scope, lane, "timer anchor")
        RegisterGFAuraEnum(scope, lane, "CooldownAnchor", "cooldownAnchor", laneInfo.label .. " Cooldown Anchor", GF_AURA_ANCHORS, {
            center = "CENTER",
            middle = "CENTER",
            topleft = "TOPLEFT",
            top_left = "TOPLEFT",
            top = "TOPLEFT",
            topright = "TOPRIGHT",
            top_right = "TOPRIGHT",
            bottomleft = "BOTTOMLEFT",
            bottom_left = "BOTTOMLEFT",
            bottomright = "BOTTOMRIGHT",
            bottom_right = "BOTTOMRIGHT",
        }, "CENTER", aliases, "geometry")

        aliases = {}
        AddGFAuraAliases(aliases, scope, lane, "cooldown text")
        RegisterGFAuraBoolean(scope, lane, "CooldownText", "showCooldown", laneInfo.label .. " Cooldown Text", true, aliases)

        aliases = {}
        AddGFAuraAliases(aliases, scope, lane, "cooldown swipe")
        RegisterGFAuraBoolean(scope, lane, "CooldownSwipe", "showCooldownSwipe", laneInfo.label .. " Cooldown Swipe", true, aliases)

        aliases = {}
        AddGFAuraAliases(aliases, scope, lane, "stack count")
        AddGFAuraAliases(aliases, scope, lane, "stacks")
        RegisterGFAuraBoolean(scope, lane, "StackCount", "showStacks", laneInfo.label .. " Stack Count", true, aliases)

        aliases = {}
        AddGFAuraAliases(aliases, scope, lane, "cooldown font")
        AddGFAuraAliases(aliases, scope, lane, "cooldown size")
        RegisterGFAuraNumber(scope, lane, "CooldownSize", "cooldownSize", laneInfo.label .. " Cooldown Font Size", 8, 6, 24, aliases, "font")

        aliases = {}
        AddGFAuraAliases(aliases, scope, lane, "stack font")
        AddGFAuraAliases(aliases, scope, lane, "stack size")
        RegisterGFAuraNumber(scope, lane, "StackSize", "stackSize", laneInfo.label .. " Stack Font Size", 10, 6, 24, aliases, "font")
    end

    local rootAliases = {}
    AddAliasesForUnit(rootAliases, scope, "aura tooltip")
    AddAliasesForUnit(rootAliases, scope, "aura tooltips")
    RegisterGFAuraRootBoolean(scope, "Tooltip", "showTooltip", "Aura Tooltips", true, rootAliases, "visual")

    rootAliases = {}
    AddAliasesForUnit(rootAliases, scope, "sort auras by duration")
    AddAliasesForUnit(rootAliases, scope, "aura duration sort")
    RegisterGFAuraRootBoolean(scope, "SortByDuration", "sortByDuration", "Sort Auras By Duration", false, rootAliases, "visual")

    rootAliases = {}
    AddAliasesForUnit(rootAliases, scope, "prefer player auras")
    AddAliasesForUnit(rootAliases, scope, "prefer my auras")
    RegisterGFAuraRootBoolean(scope, "PreferPlayer", "preferPlayer", "Prefer Player Auras", true, rootAliases, "visual")

    rootAliases = {}
    AddAliasesForUnit(rootAliases, scope, "dynamic aura scale")
    AddAliasesForUnit(rootAliases, scope, "dynamic icon scale")
    RegisterGFAuraRootBoolean(scope, "DynamicScale", "dynamicScale", "Dynamic Aura Scale", false, rootAliases, "geometry")
end

do
    local categories = GFAuraCategoryValues()
    for _, scope in ipairs(GF_AURA_CATEGORY_SCOPES) do
        for _, laneInfo in ipairs(AURA_LANES) do
            local lane = laneInfo.key
            for i = 1, #categories do
                local cat = categories[i]
                local catKey = cat and (cat.key or cat.value)
                if catKey then
                    local settingScope, settingLane, settingCatKey = scope, lane, catKey
                    local label = GFAuraCategoryLabel(catKey)
                    local aliases = {}
                    AddAliasesForUnit(aliases, scope, laneInfo.plural:lower() .. " category blacklist " .. label)
                    AddAliasesForUnit(aliases, scope, laneInfo.plural:lower() .. " public category blacklist " .. label)
                    AddAliasesForUnit(aliases, scope, "blacklist " .. label .. " " .. laneInfo.plural:lower() .. " category")
                    Registry:RegisterSetting({
                        key = "gf_" .. settingScope .. ".auras." .. settingLane .. ".blacklistCats." .. tostring(settingCatKey),
                        label = GFAuraCategoryScopeLabel(settingScope) .. " " .. GFAuraCategoryLaneLabel(settingLane) .. " Category Blacklist " .. label,
                        category = GFAuraCategoryScopeLabel(settingScope) .. " / Group Auras",
                        unit = settingScope,
                        frameType = "groupAura",
                        attribute = "gfAura" .. GFAuraCategoryLaneLabel(settingLane) .. "CategoryBlacklist",
                        type = "boolean",
                        aliases = aliases,
                        get = function() return ReadGFAuraCategorySetting(settingScope, settingLane, settingCatKey) end,
                        set = function(value) WriteGFAuraCategoryState(settingScope, settingLane, settingCatKey, value) end,
                        sameValue = SameGFAuraCategoryState,
                        apply = function() ApplyGFAuraCategory(settingScope) end,
                        combatSafe = false,
                    })
                end
            end
        end
    end
end
