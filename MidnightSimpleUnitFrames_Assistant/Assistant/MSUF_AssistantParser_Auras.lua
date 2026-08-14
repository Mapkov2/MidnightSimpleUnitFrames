-- Assistant Aura parser: parses aura-specific natural language into setting plans.
-- Mutating aura commands must preserve combat safety, confirmation, and undo metadata.
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
local Data = A.ParserData or {}
A.ParserData = Data
local AurasData = Data.AURAS_PARSER or {}
local AurasPhrases = AurasData.PHRASES or {}

-- Aura parser shard for quick presets, blacklist commands, and aura-lane bulk intent.
-- Keep the language matching here separate from Auras3 runtime code: this file decides what
-- the user likely meant, while Auras3 owns saved data and visual refresh.
local Trim = P.Trim
local Normalize = P.Normalize
local HasPhrase = P.HasPhrase
local ContainsAny = P.ContainsAny
local DetectUnits = P.DetectUnits
local DetectGroups = P.DetectGroups
local FirstNumber = P.FirstNumber
local Compact = P.Compact
local DetectDirection = P.DetectDirection
local DetectBoolean = P.DetectBoolean

local function IsAuraSortRequest(text)
    text = " " .. tostring(text or "") .. " "
    local hasLane = text:find(" buff", 1, true)
        or text:find(" debuff", 1, true)
        or text:find(" aura", 1, true)
    if not hasLane then return false end
    return text:find(" sort ", 1, true) ~= nil
        or text:find(" sorting ", 1, true) ~= nil
        or text:find(" sorted ", 1, true) ~= nil
        or text:find(" order ", 1, true) ~= nil
        or text:find(" reverse ", 1, true) ~= nil
        or text:find(" reversed ", 1, true) ~= nil
end
P.IsAuraSortRequest = IsAuraSortRequest

local AURA_BLACKLIST_PRESETS = {
    { key = "RAID_BUFFS", aliases = { "raid buffs", "raid buff", "long term raid buffs", "raid buff preset" } },
    { key = "PRESERVATION_EVOKER", aliases = { "preservation evoker", "pres evoker" } },
    { key = "AUGMENTATION_EVOKER", aliases = { "augmentation evoker", "aug evoker" } },
    { key = "RESTO_DRUID", aliases = { "resto druid", "restoration druid" } },
    { key = "DISC_PRIEST", aliases = { "disc priest", "discipline priest" } },
    { key = "HOLY_PRIEST", aliases = { "holy priest" } },
    { key = "MISTWEAVER_MONK", aliases = { "mistweaver monk", "mw monk" } },
    { key = "RESTO_SHAMAN", aliases = { "resto shaman", "restoration shaman" } },
    { key = "HOLY_PALADIN", aliases = { "holy paladin", "holy pala" } },
    { key = "BLESSING_BRONZE", aliases = { "blessing of the bronze", "bronze blessing" } },
    { key = "SELF_BUFFS", aliases = { "self buffs", "self buff", "long term self buffs" } },
    { key = "ROGUE_POISONS", aliases = { "rogue poisons", "rogue poison", "poisons" } },
    { key = "SHAMAN_IMBUE", aliases = { "shaman imbues", "shaman imbue", "shaman imbuements", "imbues" } },
    { key = "RESOURCE_AURAS", aliases = { "resource auras", "resource aura", "resource buffs", "resource buff" } },
    { key = "COOLDOWNS", aliases = { "cooldowns", "cooldown aura", "cooldown auras" } },
    { key = "SATED", aliases = { "sated", "exhaustion", "heroism exhaustion", "bloodlust exhaustion" } },
    { key = "DESERTER", aliases = { "deserter", "deserteur" } },
    { key = "CHALLENGE_DEBUFFS", aliases = { "challenge debuffs", "instance debuffs", "challenge instance debuffs", "challengers burden" } },
    { key = "CLASS_UTILITY", aliases = { "class utility", "class utility auras", "utility auras" } },
    { key = "SKYRIDING", aliases = { "skyriding", "skyriding auras", "ride along", "ridealong" } },
}

local function AuraBlacklistScope(text)
    if ContainsAny(text, AurasPhrases[1]) then return nil end
    local units = DetectUnits(text)
    for i = 1, #units do
        local unit = units[i]
        if unit == "player" or unit == "target" or unit == "focus" or unit == "boss" then return unit end
    end
    return nil
end

local function AuraBlacklistLane(text)
    text = Normalize(text)
    if text:find("debuff", 1, true) or text:find("harmful", 1, true) then return "debuff" end
    if text:find("buff", 1, true) or text:find("helpful", 1, true) then return "buff" end
    return "both"
end

local AURA_GEOMETRY_UNITS = { "player", "target", "focus", "boss" }
local AURA_GEOMETRY_GROUPS = { "party", "raid", "mythicraid" }

local function AddAuraGeometryScope(out, kind, key)
    for i = 1, #out do
        local scope = out[i]
        if scope.kind == kind and scope.key == key then return end
    end
    out[#out + 1] = { kind = kind, key = key }
end

local function AddAuraGeometryUnits(out)
    for i = 1, #AURA_GEOMETRY_UNITS do
        AddAuraGeometryScope(out, "unit", AURA_GEOMETRY_UNITS[i])
    end
end

local function AddAuraGeometryGroups(out)
    for i = 1, #AURA_GEOMETRY_GROUPS do
        AddAuraGeometryScope(out, "group", AURA_GEOMETRY_GROUPS[i])
    end
end

local function HasAllAuraGeometryScope(text)
    return HasPhrase(text, "all auras")
        or HasPhrase(text, "all aura icons")
        or HasPhrase(text, "all aura icon")
        or HasPhrase(text, "all buff icons")
        or HasPhrase(text, "all buff icon")
        or HasPhrase(text, "all buffs")
        or HasPhrase(text, "all debuff icons")
        or HasPhrase(text, "all debuff icon")
        or HasPhrase(text, "all debuffs")
        or HasPhrase(text, "every aura")
        or HasPhrase(text, "every aura icon")
        or HasPhrase(text, "every buff")
        or HasPhrase(text, "every debuff")
        or HasPhrase(text, "aura icons everywhere")
        or HasPhrase(text, "auras everywhere")
        or HasPhrase(text, "buffs everywhere")
        or HasPhrase(text, "debuffs everywhere")
        or HasPhrase(text, "alle auren")
        or HasPhrase(text, "alle aura icons")
        or HasPhrase(text, "alle buffs")
        or HasPhrase(text, "alle debuffs")
        or HasPhrase(text, "auren ueberall")
end

local function HasUnitAuraGeometryScope(text)
    return HasPhrase(text, "unit auras")
        or HasPhrase(text, "unit aura")
        or HasPhrase(text, "unit aura icons")
        or HasPhrase(text, "unit aura icon")
        or HasPhrase(text, "unitframe auras")
        or HasPhrase(text, "unitframe aura")
        or HasPhrase(text, "unitframe aura icons")
        or HasPhrase(text, "unit frame auras")
        or HasPhrase(text, "unit frame aura")
        or HasPhrase(text, "unit frame aura icons")
        or HasPhrase(text, "all unit auras")
        or HasPhrase(text, "all unit aura")
        or HasPhrase(text, "all unit aura icons")
        or HasPhrase(text, "all unitframe auras")
        or HasPhrase(text, "all unitframe aura")
        or HasPhrase(text, "all unitframe aura icons")
        or HasPhrase(text, "all unit frame auras")
        or HasPhrase(text, "all unit frame aura")
        or HasPhrase(text, "all unit frame aura icons")
        or HasPhrase(text, "alle unitframe auren")
        or HasPhrase(text, "alle unit frame auren")
end

local function HasGenericGroupAuraGeometryScope(text)
    return ContainsAny(text, AurasPhrases[2])
end

local function HasConcreteGroupAuraGeometryScope(text)
    return ContainsAny(text, AurasPhrases[3])
end

local function RaidFilterTokenIsValue(text)
    local explicitRaidScopeJoin = HasPhrase(text, "party and raid")
        or HasPhrase(text, "party und raid")
        or HasPhrase(text, "party plus raid")
    if explicitRaidScopeJoin then return false end
    return HasPhrase(text, "filter to raid")
        or HasPhrase(text, "filters to raid")
        or HasPhrase(text, "filter raid")
        or HasPhrase(text, "filter auf raid")
end

local function AuraGeometryLanes(text)
    if ContainsAny(text, AurasPhrases[4]) then return { "buff" } end
    if ContainsAny(text, AurasPhrases[5]) then return { "debuff" } end
    if ContainsAny(text, AurasPhrases[6]) then return { "buff", "debuff" } end
    return nil
end

local function AuraGeometryScopes(text)
    local groups = DetectGroups(text)
    if #groups > 0 then
        local out = {}
        local raidIsFilterValue = #groups > 1 and RaidFilterTokenIsValue(text)
        for i = 1, #groups do
            if groups[i] == "party" or groups[i] == "raid" or groups[i] == "mythicraid" then
                if not (groups[i] == "raid" and raidIsFilterValue) then
                    AddAuraGeometryScope(out, "group", groups[i])
                end
            end
        end
        if #out > 0 then return out end
    end

    local units = DetectUnits(text)
    local out = {}
    for i = 1, #units do
        for j = 1, #AURA_GEOMETRY_UNITS do
            if units[i] == AURA_GEOMETRY_UNITS[j] then out[#out + 1] = { kind = "unit", key = units[i] } end
        end
    end
    if #out > 0 then return out end

    if HasGenericGroupAuraGeometryScope(text) then
        AddAuraGeometryGroups(out)
        return out
    end

    if HasUnitAuraGeometryScope(text) then
        AddAuraGeometryUnits(out)
        return out
    end
    if HasAllAuraGeometryScope(text) then
        AddAuraGeometryUnits(out)
        AddAuraGeometryGroups(out)
        return out
    end
    return nil
end

local function AuraGeometrySettingKey(scope, lane, attr)
    if scope.kind == "group" then
        local groupAttr = attr == "offsetX" and "x" or attr == "offsetY" and "y" or attr
        return "gf_" .. tostring(scope.key) .. ".auras." .. tostring(lane) .. "." .. tostring(groupAttr)
    end
    return "auras3." .. tostring(scope.key) .. "." .. tostring(lane) .. "." .. tostring(attr)
end

local function AuraGeometryAxis(text, direction)
    if ContainsAny(text, AurasPhrases[7]) then return "offsetX" end
    if ContainsAny(text, AurasPhrases[8]) then return "offsetY" end
    if direction == "left" or direction == "right" then return "offsetX" end
    if direction == "up" or direction == "down" then return "offsetY" end
    return nil
end

local function AuraGeometryAttribute(text, direction)
    local hasSizeIntent = ContainsAny(text, AurasPhrases[16])
    if ContainsAny(text, AurasPhrases[9]) then
        return "cooldownAnchor"
    end
    if ContainsAny(text, AurasPhrases[10])
        or (ContainsAny(text, AurasPhrases[11]) and not ContainsAny(text, AurasPhrases[12])) then
        return "filterToken"
    end
    if ContainsAny(text, AurasPhrases[13])
        or (ContainsAny(text, AurasPhrases[14]) and (direction or not hasSizeIntent)) then
        return "growth"
    end
    if ContainsAny(text, AurasPhrases[15]) then
        return "anchor"
    end
    if not hasSizeIntent and ContainsAny(text, AurasPhrases[17]) then
        return "max"
    end
    if ContainsAny(text, AurasPhrases[18]) then
        return "perRow"
    end
    if ContainsAny(text, AurasPhrases[19]) then
        return "spacing"
    end
    if ContainsAny(text, AurasPhrases[20]) then
        return "layer"
    end
    if hasSizeIntent then
        return "size"
    end
    if ContainsAny(text, AurasPhrases[21]) then
        return AuraGeometryAxis(text, direction)
    end
    return nil
end

local function AuraGeometryEnumValue(text, setting, attr, direction)
    local aliases = setting and setting.valueAliases
    local compactText = Compact(text)
    local bestValue, bestLen
    if type(aliases) == "table" then
        for alias, value in pairs(aliases) do
            local compactAlias = Compact(alias)
            if compactAlias ~= "" and compactText:find(compactAlias, 1, true) and (not bestLen or #compactAlias > bestLen) then
                bestValue, bestLen = value, #compactAlias
            end
        end
    end
    if bestValue ~= nil then return bestValue end
    if attr == "growth" and direction then
        local dir = tostring(direction):upper()
        if dir == "LEFT" or dir == "RIGHT" or dir == "UP" or dir == "DOWN" then
            if setting and setting.values then
                for i = 1, #setting.values do
                    if setting.values[i] == dir then return dir end
                end
            end
            if dir == "LEFT" then return "LEFTDOWN" end
            if dir == "UP" then return "RIGHTUP" end
            return "RIGHTDOWN"
        end
    end
    return nil
end

local function AuraGeometryDelta(text, setting, attr, direction)
    if setting and setting.type == "enum" then
        return AuraGeometryEnumValue(text, setting, attr, direction), nil
    end
    local relative = P.RelativeNumberDeltaForText and P.RelativeNumberDeltaForText(setting, text)
    if relative ~= nil then return nil, relative end
    if attr == "max" or attr == "perRow" or attr == "spacing" or attr == "layer" then
        return FirstNumber(text), nil
    end
    if attr == "size" then
        local value = FirstNumber(text)
        if value ~= nil then return value, nil end
        if ContainsAny(text, AurasPhrases[22]) then return nil, 1 end
        if ContainsAny(text, AurasPhrases[23]) then return nil, -1 end
        return nil, nil
    end
    if direction then
        local amount = FirstNumber(text) or 10
        if direction == "left" or direction == "down" then amount = -amount end
        return nil, amount
    end
    return FirstNumber(text), nil
end

--- Custom aura containers (Custom 1-4, including the Target DoT lane) are
--- separate settings with their own exact aliases, e.g. "player custom 1 aura
--- layer". They are not Buff/Debuff lanes, so this Buff/Debuff-only geometry
--- shortcut must not answer for them -- it would drop the container identity
--- and read the container index as the value. Matching the four registered
--- alias shapes keeps generic wording such as "custom aura style" untouched,
--- because only an indexed mention resolves to a container.
local function MentionsCustomAuraContainer(text)
    if type(text) ~= "string" then return false end
    return text:find("custom%s*%d") ~= nil
        or text:find("custom%s+aura%s*%d") ~= nil
        or text:find("custom%s+container%s*%d") ~= nil
        or text:find("custom%s+aura%s+container%s*%d") ~= nil
end

local function ParseAuraGeometryShortcut(text)
    if not ContainsAny(text, AurasPhrases[24]) then return nil end
    if MentionsCustomAuraContainer(text) then return nil end
    if ContainsAny(text, { "private aura", "private auras", "private-aura", "private-auras" }) then
        return {
            kind = "answer",
            status = "info",
            text = "MSUF has no standalone Private Aura layout control here, so I kept every Buff and Debuff option unchanged. Name a normal Buff or Debuff lane if that is what you want to resize or move.",
            summary = "Keeps retired private-aura layout wording from changing ordinary Aura lanes.",
        }
    end
    -- Defensives are never their own positionable lane. They are either a
    -- filter on the Buff lane, or -- when the player set them up that way -- a
    -- Custom Aura container (auras3.customContainers), whose portrait render
    -- mode produces the internal "defensivePortrait" lane. Neither is moved by
    -- the Buff/Debuff offsets this shortcut owns, so dropping the word and
    -- moving those lanes shifted every buff and debuff icon instead of the one
    -- group the player named.
    -- ...but a FILTER request is not an offset request. This shortcut owns
    -- Buff/Debuff offsets only, and its own advice below tells the player to
    -- "turn on player big defensive filter" -- which it was then intercepting
    -- and answering with this same explanation instead of applying.
    if ContainsAny(text, { "filter", "filters" }) then return nil end
    -- Same reasoning for the group external-defensive lane's OWN controls: an
    -- auto-blacklist toggle, lane switch or icon cap is a request to change
    -- that control, not to move a lane. Answering those with this explanation
    -- left "set party external defensive auto-blacklist from buffs to on"
    -- unreachable -- the very phrasing the menu label produces.
    -- Scoped to the external-defensive wording on purpose: a bare "max icons"
    -- is ordinary aura-lane geometry that this shortcut legitimately owns
    -- ("set all unit aura max icons to 10"), so guarding on it broke that.
    if ContainsAny(text, {
        "auto blacklist", "auto-blacklist", "autoblacklist", "auto list", "auto-list",
        "external defensive lane", "externals lane", "external defensive strip",
        "external defensive max", "externals max", "external defensive count",
    }) then return nil end
    -- "Big Defensive" is also a Sort Method VALUE, and sorting is not a lane
    -- offset either. Without this, "set Player Buff Sort Method to big
    -- defensive" -- the exact wording the menu's own dropdown produces -- was
    -- answered with the explanation below on all eight scopes, so the value
    -- could only be selected by typing its raw storage token.
    if ContainsAny(text, { "sort", "sorting", "sort method", "sort order", "sortierung" }) then return nil end
    if ContainsAny(text, { "defensive", "defensives", "defensive aura", "defensive auras", "defensive buff", "defensive buffs" }) then
        return {
            kind = "answer",
            status = "info",
            text = "Defensives are not their own aura lane, so I did not touch your Buff or Debuff offsets -- moving those would have shifted every icon in both lanes, not just your defensives."
                .. "\nDefensives live in a Custom Aura container (the player defensive container is Custom 4), and each container has its own position, size and layout."
                .. "\nSo move the container itself, for example 'set player custom aura 4 y offset to 20', 'set player custom aura 4 icon size to 30', or 'set player custom aura 4 per row to 3'."
                .. "\nIf you meant the whole Buff lane instead, say 'move player buffs up 10'. To change which defensives show, say 'turn on player big defensive filter' or 'turn on player external defensive filter'.",
            summary = "Explains that defensives are a Buff-lane filter or a Custom Aura container rather than a positionable lane.",
        }
    end
    if ContainsAny(text, AurasPhrases[25]) then return nil end
    local explicitNonGroupAuraScope = ContainsAny(text, AurasPhrases[26])
    local groupFastIntent = not explicitNonGroupAuraScope
        and ContainsAny(text, AurasPhrases[27])
        and (ContainsAny(text, AurasPhrases[28])
            or (ContainsAny(text, AurasPhrases[29]) and not ContainsAny(text, AurasPhrases[30])))
    if ContainsAny(text, AurasPhrases[31]) and not groupFastIntent then return nil end
    if ContainsAny(text, AurasPhrases[32])
        and not ContainsAny(text, AurasPhrases[33])
    then
        return nil
    end
    if not groupFastIntent and ContainsAny(text, AurasPhrases[34])
        and ContainsAny(text, AurasPhrases[35]) then
        return nil
    end
    local lanes = AuraGeometryLanes(text)
    local scopes = AuraGeometryScopes(text)
    if not lanes or not scopes then return nil end

    local direction = DetectDirection(text, {})
    local attr = AuraGeometryAttribute(text, direction)
    if not attr then return nil end

    local changes = {}
    local missingEnumSettings = {}
    for i = 1, #scopes do
        for j = 1, #lanes do
            local key = AuraGeometrySettingKey(scopes[i], lanes[j], attr)
            local setting = Registry and Registry:GetSetting(key)
            if setting then
                local value, relativeDelta = AuraGeometryDelta(text, setting, attr, direction)
                if value ~= nil or relativeDelta ~= nil then
                    changes[#changes + 1] = {
                        setting = setting,
                        value = value,
                        relativeDelta = relativeDelta,
                        direction = direction,
                    }
                elseif setting.type == "enum" then
                    missingEnumSettings[#missingEnumSettings + 1] = setting
                end
            end
        end
    end
    if #changes == 0 then
        if #missingEnumSettings == 1 and type(P.MissingValueResponse) == "function" then
            return P.MissingValueResponse({ { setting = missingEnumSettings[1], score = 100 } }, text)
        end
        if #missingEnumSettings > 1 then
            return {
                kind = "answer",
                status = "ambiguous",
                text = "Which aura frame and lane should I change? For example: 'change player buff growth', 'change target debuff growth', or 'change raid buff growth'.",
                summary = "Asks for the missing Aura growth scope before changing several lanes.",
            }
        end
        return nil
    end
    return {
        kind = "changes",
        changes = changes,
        bulkSafe = #changes > 1,
        label = "Change Aura layout",
        summary = "Adjusts Aura layout options.",
    }
end

local function AuraEditScopeForText(text)
    if ContainsAny(text, AurasPhrases[36]) then return nil end
    if ContainsAny(text, AurasPhrases[37]) then return "player" end
    if ContainsAny(text, AurasPhrases[38]) then return "target" end
    if ContainsAny(text, AurasPhrases[39]) then return "focus" end
    if ContainsAny(text, AurasPhrases[40]) then return "boss" end
    if ContainsAny(text, AurasPhrases[41]) then return "party" end
    if ContainsAny(text, AurasPhrases[42]) then return "raid" end
    local units = DetectUnits(text)
    for i = 1, #units do
        if units[i] == "player" or units[i] == "target" or units[i] == "focus" or units[i] == "boss" then return units[i] end
    end
    local groups = DetectGroups(text)
    for i = 1, #groups do
        if groups[i] == "party" then return "party" end
        if groups[i] == "raid" or groups[i] == "mythicraid" then return "raid" end
    end
    return nil
end

local function AuraShortcutScopes(text)
    local out = {}

    local groups = DetectGroups(text)
    for i = 1, #groups do
        if groups[i] == "party" or groups[i] == "raid" or groups[i] == "mythicraid" then
            AddAuraGeometryScope(out, "group", groups[i])
        end
    end

    local units = DetectUnits(text)
    for i = 1, #units do
        local unit = units[i]
        if unit == "player" or unit == "target" or unit == "focus" or unit == "boss" then
            AddAuraGeometryScope(out, "unit", unit)
        end
    end

    if #out == 0 and HasUnitAuraGeometryScope(text) then
        AddAuraGeometryUnits(out)
    end
    if #out == 0 and HasAllAuraGeometryScope(text) then
        AddAuraGeometryUnits(out)
        AddAuraGeometryGroups(out)
    end

    if #out > 0 then return out end

    local scope = AuraEditScopeForText(text)
    if scope == "party" or scope == "raid" then
        AddAuraGeometryScope(out, "group", scope)
    elseif scope == "player" or scope == "target" or scope == "focus" or scope == "boss" then
        AddAuraGeometryScope(out, "unit", scope)
    end
    return #out > 0 and out or nil
end

local function AuraEnumAliasValue(text, aliases)
    if type(aliases) ~= "table" then return nil end
    local compactText = Compact(text)
    local bestValue, bestLen
    for alias, value in pairs(aliases) do
        local compactAlias = Compact(alias)
        if compactAlias ~= "" and (HasPhrase(text, alias) or (#compactAlias >= 5 and compactText:find(compactAlias, 1, true))) then
            local len = #compactAlias
            if not bestLen or len > bestLen then
                bestValue, bestLen = value, len
            end
        end
    end
    return bestValue
end

local function AuraCooldownSwipeDirectionValue(text)
    local data = A.AurasRegistryData or {}
    return AuraEnumAliasValue(text, data.AURA_COOLDOWN_SWIPE_DIRECTION_ALIASES)
end

local function AuraDurationBarPositionValue(text)
    local data = A.AurasRegistryData or {}
    return AuraEnumAliasValue(text, data.AURA_DURATION_BAR_POSITION_ALIASES)
end

local function AuraDurationBarDisplayValue(text)
    local data = A.AurasRegistryData or {}
    return AuraEnumAliasValue(text, data.AURA_DURATION_BAR_DISPLAY_ALIASES)
end

local function AuraDurationBarDirectionValue(text)
    local data = A.AurasRegistryData or {}
    return AuraEnumAliasValue(text, data.AURA_DURATION_BAR_DIRECTION_ALIASES)
end

local function AuraDebuffBorderModeValue(text)
    if ContainsAny(text, AurasPhrases[44]) then return "SYMBOL" end
    if ContainsAny(text, AurasPhrases[45]) then return "OFF" end
    if ContainsAny(text, AurasPhrases[46]) then return "BORDER" end
    if HasPhrase(text, "to border") or HasPhrase(text, "as border") or HasPhrase(text, "mode border") or HasPhrase(text, "use border") then return "BORDER" end
    return nil
end

local function AuraShortcutLanes(text)
    local lanes = AuraGeometryLanes(text)
    if lanes then return lanes end
    return { "buff", "debuff" }
end

local function AddAuraShortcutChange(changes, setting, value, label)
    if not setting then return end
    changes[#changes + 1] = {
        setting = setting,
        value = value,
        label = label,
    }
end

local UNIT_AURA_FILTER_KEYS = {
    buff = { "onlyMine", "raid", "raidInCombat", "includeNameplateOnly", "cancelable", "notCancelable", "externalDefensive", "bigDefensive", "onlyImportant", "includeDispellable", "dispellableAny" },
    debuff = { "onlyMine", "raid", "raidInCombat", "includeNameplateOnly", "includeDispellable", "dispellableAny", "onlyImportant", "crowdControl", "nonPlayer" },
}

local AURA_FILTER_LABELS = {
    onlyMine = "Player",
    raid = "Raid",
    raidInCombat = "Raid In Combat",
    includeNameplateOnly = "Include Nameplate-only",
    cancelable = "Cancelable",
    notCancelable = "Not Cancelable",
    externalDefensive = "External Defensive",
    bigDefensive = "Big Defensive",
    includeDispellable = "Dispellable by Group",
    dispellableAny = "Any Dispel Type",
    onlyImportant = "Important",
    crowdControl = "Crowd Control",
    nonPlayer = "Non-Player Auras",
}

local AURA_FILTER_EFFECTS = {
    onlyMine = "only your own auras pass through.",
    raid = "uses Blizzard's raid-relevant aura filter.",
    raidInCombat = "uses the stricter raid-relevant filter while in combat.",
    includeNameplateOnly = "also allows auras Blizzard marks as nameplate-only.",
    cancelable = "shows buffs you can cancel.",
    notCancelable = "shows buffs you cannot cancel.",
    externalDefensive = "focuses external defensive cooldown buffs.",
    bigDefensive = "uses MSUF's curated major-defensive Spell-ID list on friendly frames and Blizzard's safe native fallback where exact identity filtering is restricted.",
    includeDispellable = "shows debuffs someone in your group can dispel.",
    dispellableAny = "shows debuffs with any dispel type, regardless of group capability.",
    onlyImportant = "shows auras Blizzard flags as important.",
    crowdControl = "focuses crowd-control debuffs.",
    nonPlayer = "shows only debuffs not caused by any player or player pet.",
}

local GROUP_AURA_FILTER_EFFECTS = {
    ALL = "shows the normal aura set without an extra live group-filter token.",
    Player = "shows only your own auras.",
    RaidPlayer = "shows raid-relevant auras applied by you.",
    RaidInCombatPlayer = "shows combat raid-frame auras applied by you.",
    Raid = "shows player-actionable RAID auras (harmful means player-dispellable).",
    RaidInCombat = "shows combat raid-frame auras regardless of caster.",
    BigDefensivePlayer = "shows MSUF's curated major-defensive buffs applied by you.",
    ExternalDefensivePlayer = "shows external defensive cooldown buffs applied by you.",
    CancelablePlayer = "shows cancelable buffs applied by you.",
    NotCancelablePlayer = "shows non-cancelable buffs applied by you.",
    BigDefensive = "shows MSUF's curated major-defensive buffs regardless of caster.",
    ExternalDefensive = "shows external defensive cooldown buffs regardless of caster.",
    Cancelable = "shows cancelable buffs regardless of caster.",
    NotCancelable = "shows non-cancelable buffs regardless of caster.",
    PLAYER = "shows only your own auras.",
    RAID = "shows helpful auras the player can apply or harmful auras the player can dispel.",
    RAID_IN_COMBAT = "shows a cleaner raid-relevant set during combat.",
    RAID_PLAYER_DISPELLABLE = "shows auras someone in your group can dispel, including helpful enrages on enemies.",
    DISPELLABLE = "shows auras with any dispel type, even when nobody in your group can remove them.",
    IMPORTANT = "shows auras Blizzard flags as important.",
    BIG_DEFENSIVE = "shows MSUF's curated major-defensive buffs on friendly frames.",
    EXTERNAL_DEFENSIVE = "shows external defensive cooldown buffs.",
    CROWD_CONTROL = "shows crowd-control effects.",
    NonPlayer = "shows only debuffs not caused by any player or player pet.",
}

local function AuraReadSettingValue(key)
    local setting = Registry and Registry:GetSetting(key)
    if setting and type(setting.get) == "function" then
        local ok, value = pcall(setting.get)
        if ok then return value, setting end
    end
    return nil, setting
end

local function AuraFilterDisplayScope(text)
    local groups = DetectGroups(text)
    for i = 1, #groups do
        local group = groups[i]
        if group == "party" or group == "raid" or group == "mythicraid" then
            local label = group == "mythicraid" and "Mythic Raid" or (group:gsub("^%l", string.upper))
            return "group", group, label
        end
    end
    local units = DetectUnits(text)
    for i = 1, #units do
        local unit = units[i]
        if unit == "player" or unit == "target" or unit == "focus" or unit == "boss" then
            return "unit", unit, unit:gsub("^%l", string.upper)
        end
    end
    return nil, nil, nil
end

local function AuraFilterDisplayLane(text)
    if ContainsAny(text, AurasPhrases[47]) then return "debuff", "Debuff" end
    if ContainsAny(text, AurasPhrases[48]) then return "buff", "Buff" end
    return nil, nil
end

local function AuraFilterGuidanceRecommendation()
    local lines = {
        "Raid aura filter recommendation",
        "Short answer: start with Raid for general raid relevance, use Raid In Combat when you want less clutter during pulls, and use Dispellable Debuffs if your main job is cleansing.",
        "For a new player, filters are a sieve: the aura lane still exists, but the filter decides which icons are allowed through.",
        "Good raid starting points:",
        "- Raid or Mythic Raid debuffs: set the Debuff filter to Raid. If the frame is still too noisy, try RaidInCombat.",
        "- Group dispels: use RAID_PLAYER_DISPELLABLE for auras someone in your group can remove; use DISPELLABLE for every aura with a dispel type.",
        "- DPS personal tracking: use Player on target debuffs when you only care about your own DoTs.",
        "- Defensive cooldown tracking: use BigDefensive for non-player major defensives, BigDefensivePlayer for your own, or ExternalDefensive for externals.",
        "MSUF detail: Player/Target/Focus/Boss use separate filter toggles. Party/Raid/Mythic Raid use one live dropdown token per Buff or Debuff lane.",
        "Examples: set raid debuff filter to Raid; set raid debuff filter to RAID_PLAYER_DISPELLABLE; set target debuffs to any dispel type; set target buffs to Important.",
    }
    return { kind = "answer", status = "info", result = "info", text = table.concat(lines, "\n"), summary = "Recommends beginner-friendly aura filters for raid use." }
end

local function AuraFilterGuidanceOverview()
    local lines = {
        "Aura filters, in normal words",
        "Filters do not move icons or resize them. They decide which Buff or Debuff icons are allowed to show.",
        "Common choices:",
        "- Player: only your own buffs/debuffs. Good for tracking your DoTs or HoTs.",
        "- Raid / RaidPlayer: Blizzard's raid-frame relevant list, split by not-player vs player-applied auras.",
        "- RaidInCombat / RaidInCombatPlayer: stricter raid list while fighting, split by not-player vs player-applied auras.",
        "- RAID: harmful auras your character can dispel.",
        "- RAID_PLAYER_DISPELLABLE: auras someone in your group can dispel.",
        "- DISPELLABLE: every aura with a dispel type, regardless of group capability.",
        "- IMPORTANT: auras Blizzard flags as important.",
        "- BigDefensive / ExternalDefensive and their Player variants: defensive cooldown tracking.",
        "To read the exact active state I need the frame and lane, for example Target Debuffs, Player Buffs, Raid Debuffs, or Party Buffs.",
    }
    return { kind = "answer", status = "info", result = "info", text = table.concat(lines, "\n"), summary = "Explains aura filters for beginners." }
end

local function AuraUnitFilterGuidance(scope, scopeLabel, lane, laneLabel)
    local filtersEnabled = AuraReadSettingValue("auras3." .. tostring(scope) .. "." .. tostring(lane) .. ".filtersEnabled")
    if filtersEnabled == nil then filtersEnabled = true end
    local lines = {}
    lines[#lines + 1] = scopeLabel .. " " .. laneLabel .. " filters"
    lines[#lines + 1] = "Plain English: this controls which " .. laneLabel:lower() .. " icons MSUF lets through on " .. scopeLabel .. ". It does not change icon size or position."
    lines[#lines + 1] = filtersEnabled and "Filter gate: enabled. The active toggles below affect the live native AuraContainer." or "Filter gate: disabled. These filter toggles will not narrow the lane until filters are enabled."
    local active = {}
    local tokens = { lane == "buff" and "HELPFUL" or "HARMFUL" }
    local playerScoped = false
    local bigDefensiveActive = false
    local exclusive = AuraReadSettingValue("auras3." .. tostring(scope) .. "." .. tostring(lane) .. ".filter.exclusive")
    if tostring(exclusive or "none") ~= "none" then
        active[#active + 1] = "Exclusive: starts from the stricter " .. tostring(exclusive) .. " list."
        if tostring(exclusive) == "raid" then
            tokens[#tokens + 1] = "RAID"
        end
    end
    local keys = UNIT_AURA_FILTER_KEYS[lane] or {}
    for i = 1, #keys do
        local key = keys[i]
        local value = AuraReadSettingValue("auras3." .. tostring(scope) .. "." .. tostring(lane) .. ".filter." .. tostring(key))
        if value == true then
            active[#active + 1] = tostring(AURA_FILTER_LABELS[key] or key) .. ": " .. tostring(AURA_FILTER_EFFECTS[key] or "narrows this lane.")
            if key == "onlyMine" then playerScoped = true end
            if key == "raid" then tokens[#tokens + 1] = "RAID" end
            if key == "raidInCombat" then tokens[#tokens + 1] = "RAID_IN_COMBAT" end
            if key == "includeNameplateOnly" then tokens[#tokens + 1] = "INCLUDE_NAME_PLATE_ONLY" end
            if key == "cancelable" then tokens[#tokens + 1] = "CANCELABLE" end
            if key == "notCancelable" then tokens[#tokens + 1] = "!CANCELABLE" end
            if key == "externalDefensive" then tokens[#tokens + 1] = "EXTERNAL_DEFENSIVE" end
            if key == "bigDefensive" then tokens[#tokens + 1] = "BIG_DEFENSIVE"; bigDefensiveActive = true end
            if key == "onlyImportant" then tokens[#tokens + 1] = "IMPORTANT" end
            if key == "includeDispellable" then tokens[#tokens + 1] = "RAID_PLAYER_DISPELLABLE" end
            if key == "dispellableAny" then tokens[#tokens + 1] = "DISPELLABLE" end
            if key == "crowdControl" then tokens[#tokens + 1] = "CROWD_CONTROL" end
            if key == "nonPlayer" then tokens[#tokens + 1] = "candidate:isFromPlayerOrPlayerPet=false" end
        end
    end
    if playerScoped then tokens[#tokens + 1] = "PLAYER" end
    if #active == 0 then
        lines[#lines + 1] = "Active filters right now: none. This lane is not being narrowed by MSUF's live filter toggles."
        lines[#lines + 1] = lane == "debuff"
            and "Beginner tip: for raid debuffs, Raid is the normal first filter; Dispellable is the healer-cleanse view; Player is only your own debuffs."
            or "Beginner tip: for raid buffs, Raid is the normal clean view; Big Defensive and External Defensive are specialized cooldown-tracking views."
    else
        lines[#lines + 1] = "Active filters right now:"
        for i = 1, #active do lines[#lines + 1] = "- " .. active[i] end
    end
    lines[#lines + 1] = "Native filter string MSUF builds from this: " .. table.concat(tokens, "|") .. "."
    if bigDefensiveActive then
        lines[#lines + 1] = "Big Defensive execution: MSUF replaces that token with its curated exact Spell-ID gate on friendly frames and retains BIG_DEFENSIVE as the safe hostile/restricted fallback."
    end
    lines[#lines + 1] = "Safe next commands: 'turn on " .. tostring(scope) .. " " .. tostring(lane) .. " raid filter', 'turn off " .. tostring(scope) .. " " .. tostring(lane) .. " player filter', or 'set " .. tostring(scope) .. " " .. tostring(lane) .. " exclusive filter to none'."
    return { kind = "answer", status = "info", result = "info", text = table.concat(lines, "\n"), summary = "Explains active unit aura filters." }
end

local function AuraGroupFilterGuidance(scope, scopeLabel, lane, laneLabel)
    local rootEnabled = AuraReadSettingValue("gf_" .. tostring(scope) .. ".auras.enabled")
    local laneEnabled = AuraReadSettingValue("gf_" .. tostring(scope) .. ".auras." .. tostring(lane) .. ".enabled")
    local token = AuraReadSettingValue("gf_" .. tostring(scope) .. ".auras." .. tostring(lane) .. ".filterToken")
    token = tostring(token or "ALL")
    local lines = {}
    lines[#lines + 1] = scopeLabel .. " " .. laneLabel .. " group aura filter"
    lines[#lines + 1] = "Plain English: group-frame aura filters are a single dropdown per lane. Pick one main job for the lane: all auras, your auras, raid-relevant auras, dispellable debuffs, defensive buffs, or crowd control."
    lines[#lines + 1] = (rootEnabled == false) and "Group Auras are disabled for this scope, so this filter will not be visible until Group Auras are enabled." or "Group Auras are enabled or using their default enabled state."
    lines[#lines + 1] = (laneEnabled == false) and laneLabel .. " lane is disabled, so the filter cannot show icons yet." or laneLabel .. " lane is enabled or using its default enabled state."
    lines[#lines + 1] = "Current live filter token: " .. token .. ". Plain English: it " .. tostring(GROUP_AURA_FILTER_EFFECTS[token] or "uses that group aura filter token for the lane.")
    lines[#lines + 1] = lane == "debuff"
        and "Raid beginner tip: Raid is the player-dispellable view, RAID_PLAYER_DISPELLABLE covers the whole group's dispels, and DISPELLABLE includes every dispel type."
        or "Raid beginner tip: Raid is the usual not-player buff view; BigDefensive and ExternalDefensive are for non-player defensive cooldown tracking."
    lines[#lines + 1] = "Safe next commands: 'set " .. tostring(scope) .. " " .. tostring(lane) .. " filter to Raid', 'set " .. tostring(scope) .. " " .. tostring(lane) .. " filter to RaidInCombat', or 'set " .. tostring(scope) .. " " .. tostring(lane) .. " filter to ALL'."
    return { kind = "answer", status = "info", result = "info", text = table.concat(lines, "\n"), summary = "Explains active group aura filter." }
end

local function ParseAuraFilterGuidanceShortcut(text)
    if not ContainsAny(text, AurasPhrases[49]) then return nil end
    if ContainsAny(text, AurasPhrases[50]) then
        return AuraFilterGuidanceRecommendation()
    end
    local wantsStatus = ContainsAny(text, AurasPhrases[51])
    if not wantsStatus then return nil end
    local kind, scope, scopeLabel = AuraFilterDisplayScope(text)
    local lane, laneLabel = AuraFilterDisplayLane(text)
    if not kind or not scope or not lane then return AuraFilterGuidanceOverview() end
    if kind == "group" then return AuraGroupFilterGuidance(scope, scopeLabel, lane, laneLabel) end
    return AuraUnitFilterGuidance(scope, scopeLabel, lane, laneLabel)
end

local function AddAuraRegisteredChange(changes, key, value, label)
    local setting = Registry and Registry:GetSetting(key)
    AddAuraShortcutChange(changes, setting, value, label or (setting and setting.label) or key)
end

local function AuraBooleanValue(text)
    local value = DetectBoolean and DetectBoolean(text)
    if value ~= nil then return value end
    if ContainsAny(text, AurasPhrases[52]) then
        return false
    end
    return true
end

local function AuraDirectionValue(text)
    if ContainsAny(text, AurasPhrases[53]) then return "UP" end
    if ContainsAny(text, AurasPhrases[54]) then return "DOWN" end
    if ContainsAny(text, AurasPhrases[55]) then return "LEFT" end
    if ContainsAny(text, AurasPhrases[56]) then return "RIGHT" end
    return nil
end

local function AuraDirectSettingChange(key, value, label)
    if value == nil then return nil end
    local setting = Registry and Registry:GetSetting(key)
    if not setting then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value, label = label or setting.label } },
        label = label or setting.label or "Aura setting",
        summary = "Changes the matched Aura option.",
    }
end

local AURA_STYLE_BOOL_SPECS = {
    { key = "showStackCount", label = "Show Stack Count", aliases = { "show stack count", "stack count", "stacks" } },
    { key = "showCooldownText", label = "Show Cooldown Text", aliases = { "show cooldown text", "cooldown text", "timer text" } },
    { key = "showCooldownSwipe", label = "Show Cooldown Swipe", aliases = { "show cooldown swipe", "cooldown swipe", "timer swipe" } },
    { key = "showDurationBar", label = "Show Duration Bar", aliases = { "show duration bar", "duration bar", "timer bar", "aura duration bar", "aura timer bar" } },
}

local function AuraStyleScopes(text)
    local scopes = AuraShortcutScopes(text)
    if scopes then
        local out = {}
        for i = 1, #scopes do
            local scope = scopes[i]
            if scope.kind == "unit"
                and (scope.key == "player" or scope.key == "target" or scope.key == "focus" or scope.key == "boss")
            then
                AddAuraGeometryScope(out, "unit", scope.key)
            elseif scope.kind == "group" and (scope.key == "party" or scope.key == "raid" or scope.key == "mythicraid") then
                AddAuraGeometryScope(out, "group", scope.key)
            end
        end
        if #out > 0 then return out end
    end
    return nil
end

local function ParseAuraStyleBoolShortcut(text)
    if not ContainsAny(text, AurasPhrases[58]) then
        return nil
    end
    if ContainsAny(text, AurasPhrases[59]) then
        return nil
    end

    local spec
    for i = 1, #AURA_STYLE_BOOL_SPECS do
        if ContainsAny(text, AURA_STYLE_BOOL_SPECS[i].aliases) then
            spec = AURA_STYLE_BOOL_SPECS[i]
            break
        end
    end
    if not spec then return nil end

    local scopes = AuraStyleScopes(text)
    if not scopes then return nil end
    local lanes = nil
    if ContainsAny(text, AurasPhrases[60]) then
        lanes = { "debuff" }
    elseif ContainsAny(text, AurasPhrases[61]) then
        lanes = { "buff" }
    end

    local value = AuraBooleanValue(text)
    if value == nil then return nil end

    local changes = {}
    for i = 1, #scopes do
        local scope = scopes[i]
        if scope.kind == "group" then
            if lanes then
                for j = 1, #lanes do
                    AddAuraRegisteredChange(changes, AuraGeometrySettingKey(scope, lanes[j], spec.key), value, spec.label)
                end
            end
        elseif lanes then
            for j = 1, #lanes do
                AddAuraRegisteredChange(changes, "auras3." .. tostring(scope.key) .. "." .. lanes[j] .. "." .. spec.key, value, spec.label)
            end
        else
            AddAuraRegisteredChange(changes, "auras3." .. tostring(scope.key) .. "." .. spec.key, value, spec.label)
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        bulkSafe = #changes > 1,
        label = spec.label,
        summary = "Changes Aura display style toggles.",
    }
end

local AURA_STYLE_NUMBER_SPECS = {
    { key = "stackTextSize", label = "Stack Text Size", aliases = {
        "stack size", "stack text size", "stack count text size",
        "stack groesse", "stack grosse", "stack text groesse", "stack text grosse",
        "stack count text groesse", "stack count text grosse",
    }, root = true },
    { key = "cooldownTextSize", label = "Cooldown Text Size", aliases = { "cooldown size", "cooldown text size", "timer text size", "timer size" }, root = true },
    { key = "stackTextOffsetX", label = "Stack Text X Offset", aliases = { "stack x", "stack x offset", "stack text x", "stack text x offset" } },
    { key = "stackTextOffsetY", label = "Stack Text Y Offset", aliases = { "stack y", "stack y offset", "stack text y", "stack text y offset" } },
    { key = "cooldownTextOffsetX", label = "Cooldown Text X Offset", aliases = { "cooldown x", "cooldown x offset", "cooldown text x", "timer text x", "timer text x offset" } },
    { key = "cooldownTextOffsetY", label = "Cooldown Text Y Offset", aliases = { "cooldown y", "cooldown y offset", "cooldown text y", "timer text y", "timer text y offset" } },
    { key = "cooldownDecimalSeconds", label = "Cooldown Decimal Threshold", aliases = { "cooldown decimals", "cooldown decimal", "cooldown decimal threshold", "timer decimals", "timer decimal threshold", "decimal seconds" } },
    { key = "durationBarHeight", label = "Duration Bar Height", aliases = { "duration bar height", "timer bar height", "aura duration bar height", "aura timer bar height" } },
}

local function ParseAuraStyleNumberShortcut(text)
    if not ContainsAny(text, AurasPhrases[62]) then
        return nil
    end
    if ContainsAny(text, AurasPhrases[63]) then
        return nil
    end

    local spec
    for i = 1, #AURA_STYLE_NUMBER_SPECS do
        if ContainsAny(text, AURA_STYLE_NUMBER_SPECS[i].aliases) then
            spec = AURA_STYLE_NUMBER_SPECS[i]
            break
        end
    end
    if not spec then return nil end

    local scopes = AuraStyleScopes(text)
    if not scopes then return nil end
    local lanes = nil
    if ContainsAny(text, AurasPhrases[64]) then
        lanes = { "debuff" }
    elseif ContainsAny(text, AurasPhrases[65]) then
        lanes = { "buff" }
    end

    local changes = {}
    local sawSetting = false
    for i = 1, #scopes do
        local scope = scopes[i]
        if scope.kind == "group" then
            if lanes then
                for j = 1, #lanes do
                    local setting = Registry and Registry:GetSetting(AuraGeometrySettingKey(scope, lanes[j], spec.key))
                    if setting then
                        sawSetting = true
                        local value = FirstNumber(text)
                        local relativeDelta = value == nil and P.RelativeNumberDeltaForText and P.RelativeNumberDeltaForText(setting, text) or nil
                        if value ~= nil or relativeDelta ~= nil then
                            changes[#changes + 1] = { setting = setting, value = value, relativeDelta = relativeDelta, label = tostring(setting.label or spec.label) }
                        end
                    end
                end
            end
        elseif scope.kind == "unit" and (scope.key == "player" or scope.key == "target" or scope.key == "focus" or scope.key == "boss") then
            if lanes then
                for j = 1, #lanes do
                    local setting = Registry and Registry:GetSetting("auras3." .. tostring(scope.key) .. "." .. lanes[j] .. "." .. spec.key)
                    if setting then
                        sawSetting = true
                        local value = FirstNumber(text)
                        local relativeDelta = value == nil and P.RelativeNumberDeltaForText and P.RelativeNumberDeltaForText(setting, text) or nil
                        if value ~= nil or relativeDelta ~= nil then
                            changes[#changes + 1] = { setting = setting, value = value, relativeDelta = relativeDelta, label = tostring(setting.label or spec.label) }
                        end
                    end
                end
            elseif spec.root then
                local setting = Registry and Registry:GetSetting("auras3." .. tostring(scope.key) .. "." .. spec.key)
                if setting then
                    sawSetting = true
                    local value = FirstNumber(text)
                    local relativeDelta = value == nil and P.RelativeNumberDeltaForText and P.RelativeNumberDeltaForText(setting, text) or nil
                    if value ~= nil or relativeDelta ~= nil then
                        changes[#changes + 1] = { setting = setting, value = value, relativeDelta = relativeDelta, label = tostring(setting.label or spec.label) }
                    end
                end
            end
        end
    end
    if #changes > 0 then
        return {
            kind = "changes",
            changes = changes,
            bulkSafe = #changes > 1,
            label = spec.label,
            summary = "Changes Aura text and timer numeric style options.",
        }
    end
    if sawSetting then
        return {
            kind = "answer",
            status = "missing_value",
            text = "Which number should I use for that Aura style option? Example: 'set target buff stack x to 0'.",
            summary = "Asks for a numeric Aura style value.",
        }
    end
    return nil
end

local function ParseAuraStyleAnchorShortcut(text)
    local attr
    local label
    if ContainsAny(text, AurasPhrases[66]) then
        attr = "stackAnchor"
        label = "Stack Count Anchor"
    elseif ContainsAny(text, AurasPhrases[67]) then
        attr = "cooldownAnchor"
        label = "Cooldown Anchor"
    else
        return nil
    end
    if ContainsAny(text, AurasPhrases[68]) then
        return nil
    end

    local scopes = AuraShortcutScopes(text)
    if not scopes then return nil end
    local lanes = nil
    if ContainsAny(text, AurasPhrases[69]) then
        lanes = { "debuff" }
    elseif ContainsAny(text, AurasPhrases[70]) then
        lanes = { "buff" }
    end

    local changes = {}
    local sawSetting = false
    local sawMissingValue = false
    for i = 1, #scopes do
        local scope = scopes[i]
        if scope.kind == "group" then
            if lanes then
                for j = 1, #lanes do
                    local setting = Registry and Registry:GetSetting(AuraGeometrySettingKey(scope, lanes[j], attr))
                    if setting then
                        sawSetting = true
                        local value = P.EnumValueForText and P.EnumValueForText(setting, text) or nil
                        if value ~= nil then
                            AddAuraShortcutChange(changes, setting, value, tostring(setting.label or label))
                        else
                            sawMissingValue = true
                        end
                    end
                end
            end
        elseif scope.kind == "unit" and (scope.key == "player" or scope.key == "target" or scope.key == "focus" or scope.key == "boss") then
            if lanes then
                for j = 1, #lanes do
                    local setting = Registry and Registry:GetSetting("auras3." .. tostring(scope.key) .. "." .. lanes[j] .. "." .. attr)
                    if setting then
                        sawSetting = true
                        local value = P.EnumValueForText and P.EnumValueForText(setting, text) or nil
                        if value ~= nil then
                            AddAuraShortcutChange(changes, setting, value, tostring(setting.label or label))
                        else
                            sawMissingValue = true
                        end
                    end
                end
            else
                local setting = Registry and Registry:GetSetting("auras3." .. tostring(scope.key) .. "." .. attr)
                if setting then
                    sawSetting = true
                    local value = P.EnumValueForText and P.EnumValueForText(setting, text) or nil
                    if value ~= nil then
                        AddAuraShortcutChange(changes, setting, value, tostring(setting.label or label))
                    else
                        sawMissingValue = true
                    end
                end
            end
        end
    end
    if #changes > 0 then
        return {
            kind = "changes",
            changes = changes,
            bulkSafe = #changes > 1,
            label = label,
            summary = "Changes Aura text anchor options.",
        }
    end
    if sawSetting and sawMissingValue then
        return {
            kind = "answer",
            status = "missing_value",
            text = "Use an anchor point such as TOPLEFT, TOPRIGHT, BOTTOMLEFT, BOTTOMRIGHT, or CENTER where that Aura option supports it.",
            summary = "Asks for a concrete Aura anchor value.",
        }
    end
    return nil
end

local function ParseUnitAuraTooltipShortcut(text)
    if not ContainsAny(text, AurasPhrases[71]) then return nil end
    if ContainsAny(text, AurasPhrases[72]) then
        return nil
    end

    local scopes = AuraShortcutScopes(text)
    if not scopes then return nil end
    local value = AuraBooleanValue(text)
    if value == nil then return nil end
    local lanes = AuraShortcutLanes(text)

    local changes = {}
    for i = 1, #scopes do
        local scope = scopes[i]
        if scope.kind == "unit" and (scope.key == "player" or scope.key == "target" or scope.key == "focus" or scope.key == "boss") then
            for j = 1, #lanes do
                AddAuraRegisteredChange(changes, "auras3." .. tostring(scope.key) .. "." .. tostring(lanes[j]) .. ".showTooltip", value, "Aura Tooltips")
            end
        elseif scope.kind == "group" and (scope.key == "party" or scope.key == "raid" or scope.key == "mythicraid") then
            for j = 1, #lanes do
                AddAuraRegisteredChange(changes, "gf_" .. tostring(scope.key) .. ".auras." .. tostring(lanes[j]) .. ".showTooltip", value, "Group Aura Tooltips")
            end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        bulkSafe = #changes > 1,
        label = "Aura Tooltips",
        summary = "Changes unit Aura tooltip display.",
    }
end

local function ParseAuraExclusiveFilterShortcut(text)
    if not ContainsAny(text, AurasPhrases[73]) then return nil end

    local lane
    if ContainsAny(text, AurasPhrases[74]) then
        lane = "debuff"
    elseif ContainsAny(text, AurasPhrases[75]) then
        lane = "buff"
    end
    if not lane then
        return {
            kind = "answer",
            status = "ambiguous",
            text = "Which Aura lane should use the exclusive filter: Buffs or Debuffs? Example: 'set target debuff exclusive filter to none'.",
            summary = "Asks for a concrete Aura lane before changing an exclusive filter.",
        }
    end

    local scopes = {}
    if not ContainsAny(text, AurasPhrases[76]) then
        local units = DetectUnits(text)
        for i = 1, #units do
            local unit = units[i]
            if unit == "player" or unit == "target" or unit == "focus" or unit == "boss" then
                scopes[#scopes + 1] = unit
            end
        end
    end
    if #scopes == 0 then
        return {
            kind = "answer",
            status = "ambiguous",
            text = "Which UnitFrame Aura scope should use that exclusive filter: Player, Target, Focus, or Boss?",
            summary = "Asks for a concrete Aura scope before changing an exclusive filter.",
        }
    end

    local changes = {}
    local sawSetting = false
    local sawMissingValue = false
    for i = 1, #scopes do
        local key = "auras3." .. tostring(scopes[i]) .. "." .. lane .. ".filter.exclusive"
        local setting = Registry and Registry:GetSetting(key)
        if setting then
            sawSetting = true
            local value = P.EnumValueForText and P.EnumValueForText(setting, text) or nil
            if value ~= nil then
                AddAuraShortcutChange(changes, setting, value, tostring(setting.label or "Exclusive Filter"))
            else
                sawMissingValue = true
            end
        end
    end
    if #changes > 0 then
        return {
            kind = "changes",
            changes = changes,
            bulkSafe = #changes > 1,
            label = "Aura Exclusive Filter",
            summary = "Changes a unit Aura exclusive filter.",
        }
    end
    if sawSetting and sawMissingValue then
        return {
            kind = "answer",
            status = "missing_value",
            text = lane == "debuff" and "Use none or raid for Debuff Exclusive Filter." or "Use none for Buff Exclusive Filter.",
            summary = "Asks for a concrete Aura exclusive filter value.",
        }
    end
    return nil
end

local function ParseGroupAuraLaneVisibilityDirectShortcut(text)
    if not ContainsAny(text, AurasPhrases[88]) then
        return nil
    end
    if ContainsAny(text, AurasPhrases[89]) then
        return nil
    end
    if FirstNumber(text) ~= nil then return nil end

    local lane
    if ContainsAny(text, AurasPhrases[90]) then
        lane = "debuff"
    elseif ContainsAny(text, AurasPhrases[91]) then
        lane = "buff"
    end
    if not lane then return nil end

    local groups = DetectGroups(text)
    local changes = {}
    local value = AuraBooleanValue(text)
    if value == nil then return nil end
    for i = 1, #groups do
        local group = groups[i]
        if group == "party" or group == "raid" or group == "mythicraid" then
            AddAuraRegisteredChange(changes, "gf_" .. tostring(group) .. ".auras." .. lane .. ".enabled", value)
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        bulkSafe = #changes > 1,
        label = lane == "buff" and "Group Buffs" or "Group Debuffs",
        summary = "Changes Group Aura lane visibility.",
    }
end

local function ParseAuraDirectSettingShortcut(text, raw)
    if not ContainsAny(text, AurasPhrases[92]) then return nil end
    -- Asking about an aura control is not asking to change one. Without this,
    -- "what is Boss Buff Anchor" reached the enable branch below and switched
    -- unit auras on, because the sentence mentions auras and the boolean
    -- reader defaulted to true. The same guard already protects the exact-alias
    -- lane; questions must never reach a write here either.
    if type(P.NonMutatingIntent) == "function" and P.NonMutatingIntent(text) then return nil end
    -- Sorting language belongs to the reviewed lane sortMethod/sortReverse
    -- descriptors. Resolve their exact aliases here, before broad registry
    -- priorities and AuraBooleanValue can select a filter or enable the lane.
    if IsAuraSortRequest(text) then
        return P.ParseRegistryExactAliasShortcut
            and P.ParseRegistryExactAliasShortcut(text, raw)
            or nil
    end
    if ContainsAny(text, AurasPhrases[93]) then
        local value = P.RawAfterLastConnector and P.RawAfterLastConnector(raw or text, { " to ", " as ", " = " }) or nil
        if not value or value == "" then
            value = tostring(raw or text):match("[Ss][Pp][Ee][Ll][Ll]%s+(.+)$")
        end
        if value and value ~= "" then
            return AuraDirectSettingChange("menu.auraBlacklistSpell", value, "Hidden Aura Spell")
        end
    end
    if ContainsAny(text, AurasPhrases[94])
        and not ContainsAny(text, AurasPhrases[95])
    then
        return nil
    end

    if ContainsAny(text, AurasPhrases[96]) then
        local value = AuraBooleanValue(text)
        if value ~= nil then return AuraDirectSettingChange("auras3.enabled", value, "Unit Auras") end
    end
    if ContainsAny(text, AurasPhrases[98]) then
        local setting = Registry and Registry:GetSetting("menu.auraStyleGFLane")
        local value = setting and P.EnumValueForText and P.EnumValueForText(setting, text) or nil
        return AuraDirectSettingChange("menu.auraStyleGFLane", value, "Aura Style Lane")
    end
    if ContainsAny(text, AurasPhrases[99]) then
        local setting = Registry and Registry:GetSetting("menu.auraFilterLane")
        local value = setting and P.EnumValueForText and P.EnumValueForText(setting, text) or nil
        return AuraDirectSettingChange("menu.auraFilterLane", value, "Aura Filter Lane")
    end
    if ContainsAny(text, AurasPhrases[100]) then
        local setting = Registry and Registry:GetSetting("menu.aurasUXMode")
        local value = setting and P.EnumValueForText and P.EnumValueForText(setting, text) or nil
        return AuraDirectSettingChange("menu.aurasUXMode", value, "Aura Options View")
    end
    if ContainsAny(text, AurasPhrases[101]) then
        local compactText = Compact(text)
        for i = 1, #AURA_BLACKLIST_PRESETS do
            local spec = AURA_BLACKLIST_PRESETS[i]
            local compactKey = Compact(tostring(spec.key or ""))
            local readableKey = tostring(spec.key or ""):lower():gsub("_", " ")
            if ContainsAny(text, spec.aliases)
                or (readableKey ~= "" and text:find(readableKey, 1, true))
                or (compactKey ~= "" and compactText:find(compactKey, 1, true))
            then
                return AuraDirectSettingChange("menu.auraBlacklistPreset", spec.key, "Aura Blacklist Preset")
            end
        end
    end
    local laneUnits = DetectUnits(text)
    if #laneUnits > 0 and ContainsAny(text, AurasPhrases[107])
        and not ContainsAny(text, AurasPhrases[108])
    then
        local value = AuraBooleanValue(text)
        if value ~= nil then
            local changes = {}
            local lanes = AuraShortcutLanes(text)
            for i = 1, #laneUnits do
                local unit = laneUnits[i]
                if unit == "player" or unit == "target" or unit == "focus" or unit == "boss" then
                    for j = 1, #lanes do
                        AddAuraRegisteredChange(changes,
                            "auras3." .. tostring(unit) .. "." .. tostring(lanes[j]) .. ".filtersEnabled", value)
                    end
                end
            end
            if #changes > 0 then
                return {
                    kind = "changes",
                    changes = changes,
                    bulkSafe = #changes > 1,
                    label = "Unit Aura Filters",
                    summary = "Changes per-unit Aura Filters toggles.",
                }
            end
        end
    end
    do
        local result = ParseAuraExclusiveFilterShortcut(text)
        if result then return result end
    end
    do
        local result = ParseGroupAuraLaneVisibilityDirectShortcut(text)
        if result then return result end
    end
    if #laneUnits > 0 and ContainsAny(text, AurasPhrases[109])
        and ContainsAny(text, AurasPhrases[110])
    then
        return nil
    end
    do
        local result = ParseAuraStyleBoolShortcut(text)
        if result then return result end
    end
    do
        local result = ParseAuraStyleNumberShortcut(text)
        if result then return result end
    end
    do
        local result = ParseAuraStyleAnchorShortcut(text)
        if result then return result end
    end
    do
        local result = ParseUnitAuraTooltipShortcut(text)
        if result then return result end
    end
    if #laneUnits > 0 and ContainsAny(text, AurasPhrases[111])
        and ContainsAny(text, AurasPhrases[112])
        and not ContainsAny(text, AurasPhrases[113])
    then
        local lane
        if ContainsAny(text, AurasPhrases[114]) then
            lane = "debuff"
        elseif ContainsAny(text, AurasPhrases[115]) then
            lane = "buff"
        end
        local direction = DetectDirection(text, {})
        local attr
        if ContainsAny(text, AurasPhrases[116]) or direction == "left" or direction == "right" then
            attr = "offsetX"
        elseif ContainsAny(text, AurasPhrases[117]) or direction == "up" or direction == "down" then
            attr = "offsetY"
        end
        if lane and attr then
            local value = FirstNumber(text)
            local relativeDelta
            if ContainsAny(text, AurasPhrases[118]) and direction then
                local amount = value or 10
                if direction == "left" or direction == "down" then amount = -amount end
                value = nil
                relativeDelta = amount
            end
            if value ~= nil or relativeDelta ~= nil then
                local changes = {}
                for i = 1, #laneUnits do
                    local unit = laneUnits[i]
                    if unit == "player" or unit == "target" or unit == "focus" or unit == "boss" then
                        local setting = Registry and Registry:GetSetting("auras3." .. tostring(unit) .. "." .. lane .. "." .. attr)
                        if setting then
                            changes[#changes + 1] = { setting = setting, value = value, relativeDelta = relativeDelta }
                        end
                    end
                end
                if #changes > 0 then
                    return {
                        kind = "changes",
                        changes = changes,
                        bulkSafe = #changes > 1,
                        label = "Unit Aura Lane Offset",
                        summary = "Changes unit Buff/Debuff X/Y offset.",
                    }
                end
            end
        end
    end
    if #laneUnits > 0 and ContainsAny(text, AurasPhrases[119])
        and not ContainsAny(text, AurasPhrases[120])
    then
        local lane
        if ContainsAny(text, AurasPhrases[121]) then
            lane = "debuff"
        elseif ContainsAny(text, AurasPhrases[122]) then
            lane = "buff"
        end
        local value = lane and AuraBooleanValue(text) or nil
        if value ~= nil then
            local changes = {}
            for i = 1, #laneUnits do
                local unit = laneUnits[i]
                if unit == "player" or unit == "target" or unit == "focus" or unit == "boss" then
                    AddAuraRegisteredChange(changes, "auras3." .. tostring(unit) .. "." .. lane .. ".visible", value)
                end
            end
            if #changes > 0 then
                return {
                    kind = "changes",
                    changes = changes,
                    bulkSafe = #changes > 1,
                    label = "Unit Aura Lane Visibility",
                    summary = "Changes unit Buff/Debuff visibility.",
                }
            end
        end
    end
    if ContainsAny(text, AurasPhrases[137]) then
        return AuraDirectSettingChange("general.aurasCooldownTextUseBuckets", AuraBooleanValue(text), "Aura Timer Color Buckets")
    end

    local number = FirstNumber(text)
    if number ~= nil then
        if ContainsAny(text, AurasPhrases[146]) then
            return AuraDirectSettingChange("general.aurasCooldownTextSafeSeconds", number, "Aura Safe Timer Threshold")
        end
        if ContainsAny(text, AurasPhrases[147]) then
            return AuraDirectSettingChange("general.aurasCooldownTextWarningSeconds", number, "Aura Warning Timer Threshold")
        end
        if ContainsAny(text, AurasPhrases[148]) then
            return AuraDirectSettingChange("general.aurasCooldownTextUrgentSeconds", number, "Aura Urgent Timer Threshold")
        end
    end

    if ContainsAny(text, AurasPhrases[149]) then
        local setting = Registry and Registry:GetSetting("general.aurasCooldownTextSafeColor")
        local value = setting and P.ValueForRegistrySetting and P.ValueForRegistrySetting(setting, text, text)
        return AuraDirectSettingChange("general.aurasCooldownTextSafeColor", value, "Aura Safe Timer Color")
    end
    if ContainsAny(text, AurasPhrases[150]) then
        local setting = Registry and Registry:GetSetting("general.aurasCooldownTextWarningColor")
        local value = setting and P.ValueForRegistrySetting and P.ValueForRegistrySetting(setting, text, text)
        return AuraDirectSettingChange("general.aurasCooldownTextWarningColor", value, "Aura Warning Timer Color")
    end
    if ContainsAny(text, AurasPhrases[151]) then
        local setting = Registry and Registry:GetSetting("general.aurasCooldownTextUrgentColor")
        local value = setting and P.ValueForRegistrySetting and P.ValueForRegistrySetting(setting, text, text)
        return AuraDirectSettingChange("general.aurasCooldownTextUrgentColor", value, "Aura Urgent Timer Color")
    end

    return nil
end

local function UnitAuraFilterExplicitScope(text)
    if ContainsAny(text, AurasPhrases[152]) then return nil end
    local units = DetectUnits(text)
    local playerIsFilterValue = ContainsAny(text, AurasPhrases[153])
    for i = 1, #units do
        local unit = units[i]
        if unit == "player" or unit == "target" or unit == "focus" or unit == "boss" then
            if not (unit == "player" and playerIsFilterValue and #units > 1) then return unit end
        end
    end
    return nil
end

local function UnitAuraFilterLaneFromSpec(text, spec)
    if ContainsAny(text, AurasPhrases[154]) then return "buff" end
    if ContainsAny(text, AurasPhrases[155]) then return "debuff" end
    return spec and spec.lane or nil
end

local function UnitAuraFilterSpecForText(text)
    local data = A.AurasRegistryData or {}
    local specs = data.AURA_FILTER_BOOLEAN_SPECS or {}
    local compactText = Compact(text)
    local scopeStripped = " " .. Normalize(text) .. " "
    for _, word in ipairs({ "target", "focus", "boss" }) do
        scopeStripped = scopeStripped:gsub(" " .. word .. " ", " ")
    end
    scopeStripped = Trim(scopeStripped:gsub("%s+", " "))
    local compactScopeStripped = Compact(scopeStripped)
    local bestSpec, bestLen
    for i = 1, #specs do
        local spec = specs[i]
        local words = type(spec.words) == "table" and spec.words or {}
        for j = 1, #words do
            local alias = tostring(words[j] or "")
            local compactAlias = Compact(alias)
            if compactAlias ~= "" and (
                HasPhrase(text, alias)
                or HasPhrase(scopeStripped, alias)
                or (#compactAlias >= 5 and compactText:find(compactAlias, 1, true))
                or (#compactAlias >= 5 and compactScopeStripped:find(compactAlias, 1, true))
            ) then
                local len = #compactAlias
                if not bestLen or len > bestLen then
                    bestSpec, bestLen = spec, len
                end
            end
        end
    end
    return bestSpec
end

local function UnitAuraFilterHasIntent(text)
    if ContainsAny(text, AurasPhrases[156]) then return false end
    if ContainsAny(text, AurasPhrases[157]) then return false end
    if ContainsAny(text, AurasPhrases[158])
        and ContainsAny(text, AurasPhrases[159])
    then
        return false
    end
    if ContainsAny(text, AurasPhrases[160]) then return false end
    local auraSubject = ContainsAny(text, {
        "aura", "auras", "buff", "buffs", "debuff", "debuffs", "auren",
    })
    local explicitFilterWord = ContainsAny(text, {
        "filter", "filters", "filtering", "filtern", "filtere",
    })
    local concreteFilterValue = ContainsAny(text, AurasPhrases[153])
        or ContainsAny(text, AurasPhrases[163])
    if ContainsAny(text, AurasPhrases[161]) or ContainsAny(text, AurasPhrases[162]) then
        return auraSubject or explicitFilterWord or concreteFilterValue
    end
    return concreteFilterValue
end

local function HasNativeGroupAuraRootIntent(text)
    if not ContainsAny(text, AurasPhrases[164]) then return false end
    if not ContainsAny(text, AurasPhrases[165]) then
        return false
    end
    return ContainsAny(text, AurasPhrases[166])
end

local function AddUnitAuraFiltersEnabled(changes, scope, lane)
    AddAuraRegisteredChange(changes,
        "auras3." .. tostring(scope) .. "." .. tostring(lane) .. ".filtersEnabled", true,
        "Enable " .. tostring(lane) .. " Aura Filters")
end

local function AddUnitAuraFilterClearLaneChanges(changes, scope, lane)
    local keys = UNIT_AURA_FILTER_KEYS[lane] or {}
    for i = 1, #keys do
        AddAuraRegisteredChange(changes, "auras3." .. tostring(scope) .. "." .. tostring(lane) .. ".filter." .. tostring(keys[i]), false)
    end
    AddAuraRegisteredChange(changes, "auras3." .. tostring(scope) .. "." .. tostring(lane) .. ".filter.exclusive", "none")
end

local function AddUnitAuraFilterSetChange(changes, scope, lane, key, value, conflicts)
    AddAuraRegisteredChange(changes, "auras3." .. tostring(scope) .. "." .. tostring(lane) .. ".filter." .. tostring(key), value)
    if value == true and type(conflicts) == "table" then
        for i = 1, #conflicts do
            AddAuraRegisteredChange(changes, "auras3." .. tostring(scope) .. "." .. tostring(lane) .. ".filter." .. tostring(conflicts[i]), false)
        end
    end
end

local function GroupAuraFilterExplicitScopes(text, value)
    if #DetectUnits(text) > 0 then return nil, false, false end

    local explicitAll = ContainsAny(text, AurasPhrases[167])
    if explicitAll then return { "party", "raid", "mythicraid" }, true end

    local scopes = {}
    local hasParty = ContainsAny(text, AurasPhrases[168])
    local hasMythic = ContainsAny(text, AurasPhrases[169])
    local hasRaidFrameScope = ContainsAny(text, AurasPhrases[170])
    local hasRaidScope = not hasMythic and ContainsAny(text, AurasPhrases[172])
    if hasParty then scopes[#scopes + 1] = "party" end
    if hasMythic then scopes[#scopes + 1] = "mythicraid" end
    if hasRaidScope then
        -- "Raid" is both a real group-frame scope and a native filter value.
        -- Once another concrete scope is already present, value-bearing syntax
        -- such as "set party debuff filter to Raid" must keep Party as the
        -- scope instead of silently adding Raid frames as a second target.
        -- An explicit "party and raid" join still names both frame scopes.
        local raidPhraseLooksLikeFilterValue = (value == "RAID" or value == "Raid" or value == "RaidPlayer")
            and not hasRaidFrameScope and (hasParty or hasMythic)
            and RaidFilterTokenIsValue(text)
        if not raidPhraseLooksLikeFilterValue then scopes[#scopes + 1] = "raid" end
    end
    if #scopes > 0 then return scopes, true end
    if HasGenericGroupAuraGeometryScope(text) or ContainsAny(text, AurasPhrases[173]) then
        return nil, false, true
    end
    return nil, false, false
end

local function GroupAuraFilterLaneForText(text, value)
    if ContainsAny(text, AurasPhrases[174]) and not ContainsAny(text, AurasPhrases[175]) then return "buff" end
    if ContainsAny(text, AurasPhrases[176]) then return "debuff" end
    if value == "CANCELABLE" or value == "NOT_CANCELABLE" or value == "EXTERNAL_DEFENSIVE" or value == "BIG_DEFENSIVE"
        or value == "Cancelable" or value == "NotCancelable" or value == "ExternalDefensive" or value == "BigDefensive"
        or value == "CancelablePlayer" or value == "NotCancelablePlayer" or value == "ExternalDefensivePlayer" or value == "BigDefensivePlayer" then
        return "buff"
    end
    if value == "RAID_PLAYER_DISPELLABLE" or value == "DISPELLABLE" or value == "CROWD_CONTROL" or value == "NonPlayer" then return "debuff" end
    return nil
end

local function GroupAuraFilterValueForText(text)
    if ContainsAny(text, AurasPhrases[177]) or (ContainsAny(text, AurasPhrases[178]) and ContainsAny(text, AurasPhrases[179]))
        or ((HasPhrase(text, "to all") or HasPhrase(text, "all filter") or HasPhrase(text, "filter all")) and ContainsAny(text, AurasPhrases[180]))
    then
        return "ALL"
    end
    -- Scope words can make a longer generic alias win (for example,
    -- "non-player raid debuffs" also contains the alias "raid debuffs").
    -- Treat this explicit classifier as the value before the scope/lane words
    -- are considered by the generic longest-alias resolver.
    if ContainsAny(text, {
        "non-player", "non player",
        "not from a player", "not caused by a player",
    }) then
        return "NonPlayer"
    end
    local data = A.AurasRegistryData or {}
    return AuraEnumAliasValue(text, data.GF_AURA_FILTER_ALIASES)
end

local function ParseGroupAuraLiveFilterShortcut(text)
    if not UnitAuraFilterHasIntent(text) then return nil end
    if ContainsAny(text, AurasPhrases[181]) then return nil end
    local explicitFilterIntent = ContainsAny(text, AurasPhrases[182])
    if not explicitFilterIntent and ContainsAny(text, AurasPhrases[183]) then
        return nil
    end
    local value = GroupAuraFilterValueForText(text)
    if not value then return nil end
    local scopes, concrete, genericGroup = GroupAuraFilterExplicitScopes(text, value)
    if genericGroup then
        return {
            kind = "answer",
            status = "ambiguous",
            text = "Which group aura scope should use that filter: Party, Raid, Mythic Raid, or all group frames? Example: 'show only dispellable raid debuffs'.",
            summary = "Asks for a concrete group aura scope before changing the live filter.",
        }
    end
    if not scopes or #scopes == 0 then return nil end

    local lane = GroupAuraFilterLaneForText(text, value)
    if not lane then
        return {
            kind = "answer",
            status = "ambiguous",
            text = "Which group aura lane should use that filter: Buffs or Debuffs? Example: 'show only dispellable raid debuffs'.",
            summary = "Asks for a group aura lane before changing the live filter.",
        }
    end

    local values = (A.AurasRegistryData and A.AurasRegistryData.GF_AURA_FILTER_VALUES and A.AurasRegistryData.GF_AURA_FILTER_VALUES[lane]) or {}
    local allowed = false
    for i = 1, #values do
        if values[i] == value then
            allowed = true
            break
        end
    end
    if not allowed then return nil end

    local changes = {}
    for i = 1, #scopes do
        local scope = scopes[i]
        AddAuraRegisteredChange(changes, "gf_" .. tostring(scope) .. ".auras." .. tostring(lane) .. ".filterToken", value)
        AddAuraRegisteredChange(changes, "gf_" .. tostring(scope) .. ".auras.enabled", true)
        AddAuraRegisteredChange(changes, "gf_" .. tostring(scope) .. ".auras." .. tostring(lane) .. ".enabled", true)
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        bulkSafe = #changes > 1,
        label = lane == "buff" and "Group Buff Filter" or "Group Debuff Filter",
        summary = "Enables the requested Group Aura lane and changes its live filter dropdown.",
    }
end

local function ParseUnitAuraLiveFilterShortcut(text)
    if not UnitAuraFilterHasIntent(text) then return nil end
    if ContainsAny(text, AurasPhrases[184]) then return nil end
    local explicitFilterIntent = ContainsAny(text, AurasPhrases[182])
    if not explicitFilterIntent and ContainsAny(text, AurasPhrases[183]) then
        return nil
    end
    if ContainsAny(text, AurasPhrases[185])
        and not ContainsAny(text, AurasPhrases[186])
    then
        return nil
    end
    if HasNativeGroupAuraRootIntent(text) then return nil end
    local explicitUnitAuraScope = ContainsAny(text, AurasPhrases[187])
    if not explicitUnitAuraScope
        and (HasGenericGroupAuraGeometryScope(text)
            or HasConcreteGroupAuraGeometryScope(text)
            or ContainsAny(text, AurasPhrases[188]))
    then
        return nil
    end

    local scope = UnitAuraFilterExplicitScope(text)
    if not scope then
        return {
            kind = "answer",
            status = "ambiguous",
            text = "Which UnitFrame Aura scope should use that live filter: Player, Target, Focus, or Boss? Example: 'show only dispellable target debuffs'.",
            summary = "Asks for a unit aura scope before changing live filters.",
        }
    end

    local clearAll = ContainsAny(text, AurasPhrases[189])
    if clearAll then
        local lanes = AuraShortcutLanes(text)
        local changes = {}
        for i = 1, #lanes do
            AddUnitAuraFiltersEnabled(changes, scope, lanes[i])
            AddUnitAuraFilterClearLaneChanges(changes, scope, lanes[i])
        end
        if #changes == 0 then return nil end
        return {
            kind = "changes",
            changes = changes,
            bulkSafe = #changes > 1,
            label = "Show all Aura filter results",
            summary = "Clears live unit aura filters for the requested lane.",
        }
    end

    local spec = UnitAuraFilterSpecForText(text)
    if not spec then return nil end
    local lane = UnitAuraFilterLaneFromSpec(text, spec)
    if not lane then
        return {
            kind = "answer",
            status = "ambiguous",
            text = "Which aura lane should use that filter: Buffs or Debuffs? Example: 'show only my target buffs' or 'show only my target debuffs'.",
            summary = "Asks for a unit aura lane before changing live filters.",
        }
    end

    local value = DetectBoolean and DetectBoolean(text)
    if value == nil then
        if ContainsAny(text, AurasPhrases[190]) then
            value = false
        else
            value = true
        end
    end

    local directChanges = {}
    AddUnitAuraFilterSetChange(directChanges, scope, lane, spec.key, value, spec.conflicts)
    AddUnitAuraFiltersEnabled(directChanges, scope, lane)
    if #directChanges == 0 then return nil end

    local wantsOnly = value == true and ContainsAny(text, AurasPhrases[191])
    if wantsOnly then
        local replaceChanges = {}
        AddUnitAuraFilterClearLaneChanges(replaceChanges, scope, lane)
        AddUnitAuraFilterSetChange(replaceChanges, scope, lane, spec.key, true, spec.conflicts)
        AddUnitAuraFiltersEnabled(replaceChanges, scope, lane)
        if #replaceChanges > #directChanges then
            return {
                kind = "ambiguous",
                choices = {
                    {
                        changes = directChanges,
                        label = "Enable " .. tostring(spec.label or "that filter"),
                        bulkSafe = #directChanges > 1,
                        summary = "Enables one live Aura filter without changing other filters.",
                    },
                    {
                        changes = replaceChanges,
                        label = "Use only " .. tostring(spec.label or "that filter"),
                        bulkSafe = true,
                        summary = "Clears the lane's other live Aura filters first.",
                    },
                },
                label = "How should I apply that Aura filter?",
                summary = "Clarifies whether to replace other live Aura filters.",
            }
        end
    end

    return {
        kind = "changes",
        changes = directChanges,
        bulkSafe = #directChanges > 1,
        label = "Change live Aura filter",
    summary = "Changes a live unit Aura filter.",
    }
end

local function ParseUnitAuraFilterBooleanShortcut(text)
    if P.LooksLikeExactKeyLookup and P.LooksLikeExactKeyLookup(text) then return nil end
    if ContainsAny(text, AurasPhrases[192]) then return nil end
    if ContainsAny(text, AurasPhrases[193]) then return nil end
    if HasNativeGroupAuraRootIntent(text) then return nil end
    local explicitUnits = DetectUnits(text)
    local explicitShared = ContainsAny(text, AurasPhrases[194])
    if #explicitUnits == 0 and not explicitShared and (HasGenericGroupAuraGeometryScope(text) or HasConcreteGroupAuraGeometryScope(text)
        or ContainsAny(text, AurasPhrases[195]))
    then
        return nil
    end
    if (#explicitUnits > 0 or explicitShared) and ContainsAny(text, AurasPhrases[196]) then
        return nil
    end
    if #explicitUnits == 0 and not explicitShared then return nil end

    local lane
    if ContainsAny(text, AurasPhrases[197]) and not ContainsAny(text, AurasPhrases[198]) then
        lane = "buff"
    elseif ContainsAny(text, AurasPhrases[199]) then
        lane = "debuff"
    end
    if not lane then return nil end

    local key
    local conflicts
    local label
    if ContainsAny(text, AurasPhrases[200]) then
        key = "raidInCombat"
        label = lane == "buff" and "Buff Raid In Combat Filter" or "Debuff Raid In Combat Filter"
    elseif ContainsAny(text, AurasPhrases[201]) then
        key = "raid"
        label = lane == "buff" and "Buff Raid Filter" or "Debuff Raid Filter"
    elseif ContainsAny(text, AurasPhrases[202]) then
        key = "includeNameplateOnly"
        label = lane == "buff" and "Buff Include Nameplate-only Filter" or "Debuff Include Nameplate-only Filter"
    elseif lane == "debuff" and ContainsAny(text, AurasPhrases[203]) then
        key = "includeDispellable"
        label = "Debuff Dispellable Filter"
    elseif lane == "debuff" and ContainsAny(text, AurasPhrases[204]) then
        key = "crowdControl"
        label = "Debuff Crowd Control Filter"
    elseif lane == "buff" and ContainsAny(text, AurasPhrases[205]) then
        key = "notCancelable"
        conflicts = { "cancelable" }
        label = "Buff Not Cancelable Filter"
    elseif lane == "buff" and ContainsAny(text, AurasPhrases[206]) then
        key = "cancelable"
        conflicts = { "notCancelable" }
        label = "Buff Cancelable Filter"
    elseif lane == "buff" and ContainsAny(text, AurasPhrases[207]) then
        key = "externalDefensive"
        label = "Buff External Defensive Filter"
    elseif lane == "buff" and ContainsAny(text, AurasPhrases[208]) then
        key = "bigDefensive"
        label = "Buff Big Defensive Filter"
    elseif ContainsAny(text, AurasPhrases[209]) then
        key = "onlyMine"
        label = lane == "buff" and "Buff Player Filter" or "Debuff Player Filter"
    else
        return nil
    end

    local scope = UnitAuraFilterExplicitScope(text)
    if not scope then return nil end
    local value = DetectBoolean and DetectBoolean(text)
    if value == nil then
        value = not ContainsAny(text, AurasPhrases[210])
    end

    local changes = {}
    AddUnitAuraFilterSetChange(changes, scope, lane, key, value, conflicts)
    AddUnitAuraFiltersEnabled(changes, scope, lane)
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        bulkSafe = #changes > 1,
        label = label,
        summary = "Changes a live unit Aura filter directly.",
    }
end

local function AddGroupAuraVisibilityChoice(choices, scope, lane, value)
    local setting = Registry and Registry:GetSetting("gf_" .. tostring(scope) .. ".auras." .. tostring(lane) .. ".enabled")
    if not setting then return end
    local laneLabel = lane == "buff" and "Buffs" or "Debuffs"
    local verb = value and "show" or "hide"
    choices[#choices + 1] = {
        setting = setting,
        value = value,
        label = tostring(setting.label or laneLabel) .. " -> " .. verb,
        summary = "Changes " .. tostring(setting.label or laneLabel) .. " visibility.",
    }
end

local function AddGroupAuraVisibilityChange(changes, scope, lane, value)
    local setting = Registry and Registry:GetSetting("gf_" .. tostring(scope) .. ".auras." .. tostring(lane) .. ".enabled")
    AddAuraShortcutChange(changes, setting, value, tostring(setting and setting.label or "Group Aura Visibility"))
end

local function AddGroupAuraRootVisibilityChoice(choices, scope, value)
    local setting = Registry and Registry:GetSetting("gf_" .. tostring(scope) .. ".auras.enabled")
    if not setting then return end
    local verb = value and "show" or "hide"
    choices[#choices + 1] = {
        setting = setting,
        value = value,
        label = tostring(setting.label or "Group Auras Enabled") .. " -> " .. verb,
        summary = "Changes the whole Group Aura system for that scope.",
    }
end

local function ParseGroupAuraRootSettingShortcut(text)
    if P.LooksLikeExactKeyLookup and P.LooksLikeExactKeyLookup(text) then return nil end
    if ContainsAny(text, AurasPhrases[211]) then return nil end
    if not ContainsAny(text, AurasPhrases[212]) then
        return nil
    end

    local key
    local label
    if ContainsAny(text, AurasPhrases[213]) then
        key = "preferPlayer"
        label = "Prefer Player Auras"
    elseif ContainsAny(text, AurasPhrases[214]) then
        key = "dynamicScale"
        label = "Dynamic Aura Scale"
    elseif ContainsAny(text, AurasPhrases[215]) then
        key = "showTooltip"
        label = "Aura Tooltips"
    elseif ContainsAny(text, AurasPhrases[216]) then
        key = "sortByDuration"
        label = "Sort Auras by Duration"
    elseif ContainsAny(text, AurasPhrases[217]) then
        key = "blizzardDispelBorder"
        label = "Native Dispel Border"
    elseif ContainsAny(text, AurasPhrases[218]) then
        key = "blizzardTypes.buffs"
        label = "Native Buffs"
    elseif ContainsAny(text, AurasPhrases[219]) then
        key = "blizzardTypes.debuffs"
        label = "Native Debuffs"
    elseif ContainsAny(text, AurasPhrases[220]) then
        key = "blizzardTypes.dispels"
        label = "Native Dispel Auras"
    elseif ContainsAny(text, AurasPhrases[221]) then
        key = "blizzardTypes.externals"
        label = "Native External Auras"
    elseif ContainsAny(text, AurasPhrases[223]) then
        key = "enabled"
        label = "Group Auras Enabled"
    else
        return nil
    end

    local scopes = {}
    local groups = DetectGroups(text)
    for i = 1, #groups do
        local scope = groups[i]
        if scope == "party" or scope == "raid" or scope == "mythicraid" then
            scopes[#scopes + 1] = scope
        end
    end
    if #scopes == 0 then
        if ContainsAny(text, AurasPhrases[224]) then
            scopes = { "party", "raid", "mythicraid" }
        else
            return nil
        end
    end

    local value = AuraBooleanValue(text)
    local changes = {}
    for i = 1, #scopes do
        local setting = Registry and Registry:GetSetting("gf_" .. tostring(scopes[i]) .. ".auras." .. key)
        AddAuraShortcutChange(changes, setting, value, tostring(setting and setting.label or label))
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = label,
        bulkSafe = #changes > 1,
        summary = "Changes a Group Aura root option directly.",
    }
end

local function ParseGroupAuraVisibilityShortcut(text)
    if IsAuraSortRequest(text) then return nil end
    local hasBuff = ContainsAny(text, AurasPhrases[225])
    local hasDebuff = ContainsAny(text, AurasPhrases[226])
    if not ContainsAny(text, AurasPhrases[227]) and not (hasBuff and hasDebuff) then return nil end
    if not ContainsAny(text, AurasPhrases[228]) then return nil end
    if ContainsAny(text, AurasPhrases[229]) then
        return nil
    end
    if ContainsAny(text, AurasPhrases[230]) then
        return nil
    end
    if ContainsAny(text, AurasPhrases[231]) then
        return nil
    end

    local scopes = {}
    local groups = DetectGroups(text)
    for i = 1, #groups do
        local group = groups[i]
        if group == "party" or group == "raid" or group == "mythicraid" then
            AddAuraGeometryScope(scopes, "group", group)
        end
    end

    if #scopes == 0 then
        if HasGenericGroupAuraGeometryScope(text) or ContainsAny(text, AurasPhrases[232]) then
            return {
                kind = "answer",
                status = "ambiguous",
                text = "Which group aura scope do you mean: Party or Raid? Also say Buffs, Debuffs, or both. Example: 'hide party debuffs' or 'hide both raid buffs and debuffs'.",
                summary = "Asks for a concrete group aura scope before changing visibility.",
            }
        end
        return nil
    end

    local value = DetectBoolean and DetectBoolean(text)
    if value == nil then
        if ContainsAny(text, AurasPhrases[233]) then value = true end
        if ContainsAny(text, AurasPhrases[234]) then value = false end
    end
    if value == nil then return nil end

    local explicitBothLanes = hasBuff and hasDebuff
        or ContainsAny(text, AurasPhrases[235])
    local broadAllAuras = ContainsAny(text, AurasPhrases[236])
    local wantsBoth = explicitBothLanes or broadAllAuras
    if hasBuff ~= hasDebuff then
        local lane = hasBuff and "buff" or "debuff"
        local changes = {}
        for i = 1, #scopes do
            AddGroupAuraVisibilityChange(changes, scopes[i].key, lane, value)
        end
        if #changes == 0 then return nil end
        return {
            kind = "changes",
            changes = changes,
            bulkSafe = #changes > 1,
            label = lane == "buff" and "Group Buff visibility" or "Group Debuff visibility",
            summary = "Changes one Group Aura lane visibility.",
        }
    end
    if wantsBoth then
        if broadAllAuras and not explicitBothLanes and #scopes == 1 then
            local scope = scopes[1].key
            local choices = {}
            local bothChanges = {}
            AddGroupAuraVisibilityChange(bothChanges, scope, "buff", value)
            AddGroupAuraVisibilityChange(bothChanges, scope, "debuff", value)
            if #bothChanges == 2 then
                local verb = value and "show" or "hide"
                choices[#choices + 1] = {
                    changes = bothChanges,
                    label = "Buff and Debuff lanes -> " .. verb,
                    bulkSafe = true,
                    summary = "Changes only the Group Aura Buff and Debuff lanes.",
                }
            end
            AddGroupAuraRootVisibilityChoice(choices, scope, value)
            if #choices > 1 then
                return {
                    kind = "ambiguous",
                    choices = choices,
                    label = "How much should I change?",
                    summary = "Clarifies whether to change visible lanes or the whole Group Aura system.",
                }
            end
        end
        local changes = {}
        for i = 1, #scopes do
            local scope = scopes[i].key
            AddGroupAuraVisibilityChange(changes, scope, "buff", value)
            AddGroupAuraVisibilityChange(changes, scope, "debuff", value)
        end
        if #changes == 0 then return nil end
        return {
            kind = "changes",
            changes = changes,
            bulkSafe = #changes > 1,
            label = "Group Aura visibility",
            summary = "Changes Group Aura Buff and Debuff visibility.",
        }
    end

    if #scopes == 1 then
        local scope = scopes[1].key
        local choices = {}
        AddGroupAuraVisibilityChoice(choices, scope, "buff", value)
        AddGroupAuraVisibilityChoice(choices, scope, "debuff", value)
        local bothChanges = {}
        AddGroupAuraVisibilityChange(bothChanges, scope, "buff", value)
        AddGroupAuraVisibilityChange(bothChanges, scope, "debuff", value)
        if #bothChanges == 2 then
            local verb = value and "show" or "hide"
            choices[#choices + 1] = {
                changes = bothChanges,
                label = "Both Group Aura lanes -> " .. verb,
                bulkSafe = true,
                summary = "Changes both Group Aura Buff and Debuff visibility.",
            }
        end
        if #choices == 0 then return nil end
        return {
            kind = "ambiguous",
            choices = choices,
            label = "Which group aura lane?",
            summary = "Asks whether to change group buffs, group debuffs, or both.",
        }
    end

    return {
        kind = "answer",
        status = "ambiguous",
        text = "Which group aura lane do you mean for those scopes: Buffs, Debuffs, or both? Example: 'hide both party and raid buffs and debuffs'.",
        summary = "Asks for a concrete group aura lane before changing multiple scopes.",
    }
end

local function ParseAuraCooldownSwipeDirectionShortcut(text)
    if not ContainsAny(text, AurasPhrases[237]) then return nil end
    if not ContainsAny(text, AurasPhrases[238]) then return nil end

    local scopes = AuraShortcutScopes(text)
    if not scopes then return nil end

    local value = AuraCooldownSwipeDirectionValue(text)
    if not value then
        return {
            kind = "answer",
            status = "missing_value",
            text = "Use normal or reverse for Aura Cooldown Swipe Direction. Example: set raid cooldown swipe direction to reverse.",
        }
    end

    local lanes = AuraShortcutLanes(text)
    local changes = {}
    for i = 1, #scopes do
        for j = 1, #lanes do
            local key = AuraGeometrySettingKey(scopes[i], lanes[j], "cooldownSwipeReverse")
            local setting = Registry and Registry:GetSetting(key)
            AddAuraShortcutChange(changes, setting, value, tostring(setting and setting.label or "Aura Cooldown Swipe Direction"))
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        bulkSafe = #changes > 1,
        label = "Change Aura cooldown swipe direction",
        summary = "Adjusts Aura cooldown swipe direction.",
    }
end

local function ParseAuraDurationBarShortcut(text)
    if not ContainsAny(text, AurasPhrases[239]) then return nil end

    local attr, value, missingText, label, summary
    local wantsPosition = ContainsAny(text, AurasPhrases[240])
    local wantsDisplay = ContainsAny(text, AurasPhrases[241])
    local wantsDirection = ContainsAny(text, AurasPhrases[242])

    if wantsPosition and not wantsDirection and not wantsDisplay then
        attr = "durationBarPosition"
        value = AuraDurationBarPositionValue(text)
        missingText = "Use top or bottom for Aura Duration Bar Position. Example: put target buff duration bar on top."
        label = "Change Aura duration bar position"
        summary = "Adjusts Aura Duration Bar Position."
    elseif wantsDisplay and not wantsDirection then
        attr = "durationBarDisplay"
        value = AuraDurationBarDisplayValue(text)
        missingText = "Use bar only or icon + bar for Aura Duration Bar Display. Example: set target buff duration bar display to icon + bar."
        label = "Change Aura duration bar display"
        summary = "Adjusts Aura Duration Bar Display."
    elseif wantsDirection then
        attr = "durationBarDirection"
        value = AuraDurationBarDirectionValue(text)
        missingText = "Use remaining or elapsed for Aura Duration Bar Fill Mode. Example: set raid duration bar fill mode to elapsed."
        label = "Change Aura duration bar fill mode"
        summary = "Adjusts Aura Duration Bar Fill Mode."
    else
        return nil
    end

    if not value then
        return {
            kind = "answer",
            status = "missing_value",
            text = missingText,
        }
    end

    local scopes = AuraShortcutScopes(text)
    if not scopes then return nil end

    local lanes = AuraShortcutLanes(text)
    local changes = {}
    for i = 1, #scopes do
        for j = 1, #lanes do
            local key = AuraGeometrySettingKey(scopes[i], lanes[j], attr)
            local setting = Registry and Registry:GetSetting(key)
            AddAuraShortcutChange(changes, setting, value, tostring(setting and setting.label or "Aura Duration Bar"))
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        bulkSafe = #changes > 1,
        label = label,
        summary = summary,
    }
end

local function ParseAuraDebuffBorderModeShortcut(text)
    if not ContainsAny(text, AurasPhrases[243]) then return nil end

    local scopes = AuraShortcutScopes(text)
    if not scopes then return nil end

    local boolValue = DetectBoolean and DetectBoolean(text)
    if boolValue ~= nil
        and not ContainsAny(text, AurasPhrases[244])
    then
        local changes = {}
        for i = 1, #scopes do
            local scope = scopes[i]
            local key
            if scope.kind == "group" then
                key = "gf_" .. tostring(scope.key) .. ".auras.debuff.showDispelBorder"
            else
                key = "auras3." .. tostring(scope.key) .. ".useDebuffTypeBorders"
            end
            local setting = Registry and Registry:GetSetting(key)
            AddAuraShortcutChange(changes, setting, boolValue, tostring(setting and setting.label or "Debuff Dispel-type Border"))
        end
        if #changes == 0 then return nil end
        return {
            kind = "changes",
            changes = changes,
            bulkSafe = #changes > 1,
            label = "Debuff Dispel-type Border",
            summary = "Changes Debuff Dispel-type Border visibility.",
        }
    end

    local value = AuraDebuffBorderModeValue(text)
    if not value then
        return {
            kind = "answer",
            status = "missing_value",
            text = "Use off, border, or symbol for Debuff Dispel-type Border Mode. Example: set raid debuff dispel border mode to border.",
        }
    end

    local changes = {}
    for i = 1, #scopes do
        local scope = scopes[i]
        local key
        if scope.kind == "group" then
            key = "gf_" .. tostring(scope.key) .. ".auras.debuff.dispelBorderMode"
        else
            key = "auras3." .. tostring(scope.key) .. ".debuff.debuffTypeBorderMode"
        end
        local setting = Registry and Registry:GetSetting(key)
        AddAuraShortcutChange(changes, setting, value, tostring(setting and setting.label or "Debuff Dispel-type Border Mode"))
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        bulkSafe = #changes > 1,
        label = "Change Aura debuff border mode",
        summary = "Adjusts Debuff Dispel-type Border Mode.",
    }
end

local function ParseAuraScopeOverrideShortcut(text)
    return nil
end

local function AuraBlacklistPresetForText(text)
    for i = 1, #AURA_BLACKLIST_PRESETS do
        local spec = AURA_BLACKLIST_PRESETS[i]
        if ContainsAny(text, spec.aliases) then return spec.key end
    end
    return nil
end

local function AuraGroupBlacklistScope(text)
    if ContainsAny(text, AurasPhrases[252]) then return "party" end
    if ContainsAny(text, AurasPhrases[253]) then return "raid" end
    if ContainsAny(text, AurasPhrases[254]) then return "raid" end
    local groups = DetectGroups(text)
    for i = 1, #groups do
        if groups[i] == "party" then return "party" end
    end
    for i = 1, #groups do
        if groups[i] == "raid" or groups[i] == "mythicraid" then return "raid" end
    end
    return "raid"
end

local function AuraGroupBlacklistLane(text)
    if ContainsAny(text, AurasPhrases[255]) then return "debuff" end
    return "buff"
end

local function AuraGroupBlacklistCategoryForText(text)
    if A.ResolveAuraGroupCategory then
        local resolved = A.ResolveAuraGroupCategory(text)
        if resolved then return resolved end
    end
    return AuraBlacklistPresetForText(text)
end

local function CleanAuraBlacklistSpellValue(value)
    value = Trim(tostring(value or ""))
    local spellID = value:match("[Hh]spell:(%d+)") or value:match("spell:(%d+)")
    if spellID then return "spell:" .. tostring(spellID) end
    local linkedName = value:match("|h%[(.-)%]|h")
    if linkedName and linkedName ~= "" then value = linkedName end
    value = value:gsub("^['\"]", ""):gsub("['\"]$", "")
    value = value:gsub("^%[", ""):gsub("%]$", "")
    value = value:gsub("^spell%s+", "")
    value = value:gsub("^named%s+", "")
    value = value:gsub("^called%s+", "")
    value = value:gsub("^#%s*", "")
    value = value:gsub("[%s%.%,%;%!%?]+$", "")
    value = Trim(value)
    local normalized = Normalize(value)
    if normalized == "" or normalized == "all" or normalized == "all spell" or normalized == "all spells"
        or normalized == "all aura" or normalized == "all auras" or normalized == "every spell"
        or normalized == "every aura" or normalized == "aura" or normalized == "auras"
        or normalized == "buff" or normalized == "buffs" or normalized == "debuff"
        or normalized == "debuffs" or normalized == "spell" or normalized == "spells" then
        return nil
    end
    return value
end

local function AuraBlacklistSpellValue(raw)
    raw = tostring(raw or "")
    local value = raw:match("(spell:%d+)") or raw:match("#%s*(%d+)") or raw:match("(%d%d+)")
    if value then return value end

    local patterns = {
        "[Ww]hitelist%s+(.+)%s+[Ii]n%s+",
        "[Ww]hitelist%s+(.+)%s+[Ff]or%s+",
        "[Ww]hitelist%s+(.+)%s+[Oo]n%s+",
        "[Aa]dd%s+(.+)%s+to%s+.+[Ww]hitelist",
        "[Rr]emove%s+(.+)%s+from%s+.+[Ww]hitelist",
        "[Aa]dd%s+(.+)%s+to%s+.+[Bb]lacklist",
        "[Aa]dd%s+(.+)%s+to%s+.+[Aa]uras?",
        "[Bb]lacklist%s+(.+)%s+[Ff]or%s+",
        "[Bb]lacklist%s+(.+)%s+[Oo]n%s+",
        "[Bb]lacklist%s+(.+)%s+[Ii]n%s+",
        "[Bb]lock%s+(.+)%s+[Ff]or%s+",
        "[Bb]lock%s+(.+)%s+[Oo]n%s+",
        "[Ii]gnore%s+(.+)%s+[Ff]or%s+",
        "[Ii]gnore%s+(.+)%s+[Oo]n%s+",
        "[Hh]ide%s+(.+)%s+[Ff]or%s+",
        "[Hh]ide%s+(.+)%s+[Oo]n%s+",
        "[Hh]ide%s+(.+)%s+[Ii]n%s+",
        "[Hh]ide%s+[Aa]ura%s+[Ss]pell%s+(.+)$",
        "[Hh]ide%s+[Hh]idden%s+[Aa]ura%s+[Ss]pell%s+(.+)$",
        "[Hh]ide%s+[Gg]roup%s+[Aa]ura%s+[Ss]pell%s+(.+)$",
        "[Hh]ide%s+[Pp]arty%s+[Aa]ura%s+[Ss]pell%s+(.+)$",
        "[Hh]ide%s+[Rr]aid%s+[Aa]ura%s+[Ss]pell%s+(.+)$",
        "[Hh]ide%s+[Pp]arty%s+[Bb]uff%s+[Aa]ura%s+[Ss]pell%s+(.+)$",
        "[Hh]ide%s+[Rr]aid%s+[Bb]uff%s+[Aa]ura%s+[Ss]pell%s+(.+)$",
        "[Hh]ide%s+[Pp]arty%s+[Dd]ebuff%s+[Aa]ura%s+[Ss]pell%s+(.+)$",
        "[Hh]ide%s+[Rr]aid%s+[Dd]ebuff%s+[Aa]ura%s+[Ss]pell%s+(.+)$",
        "[Vv]erstecke%s+(.+)%s+[Aa]uf%s+",
        "[Vv]erstecke%s+(.+)%s+[Ff]uer%s+",
        "[Vv]erstecke%s+(.+)%s+[Ii]n%s+",
        "[Aa]usblenden%s+(.+)%s+[Aa]uf%s+",
        "[Aa]usblenden%s+(.+)%s+[Ff]uer%s+",
        "[Ss]uppress%s+(.+)%s+[Ff]or%s+",
        "[Ss]uppress%s+(.+)%s+[Oo]n%s+",
        "[Ss]top%s+showing%s+(.+)%s+[Ff]or%s+",
        "[Ss]top%s+showing%s+(.+)%s+[Oo]n%s+",
        "[Rr]emove%s+(.+)%s+from%s+.+[Bb]lacklist",
        "[Rr]emove%s+(.+)%s+from%s+.+[Aa]uras?",
        "[Aa]llow%s+(.+)%s+[Ff]or%s+.+[Aa]uras?",
        "[Aa]llow%s+(.+)%s+[Oo]n%s+.+[Aa]uras?",
        "[Aa]llow%s+(.+)%s+[Ff]or%s+.+[Bb]lacklist",
        "[Aa]llow%s+(.+)%s+[Oo]n%s+.+[Bb]lacklist",
        "[Aa]llow%s+(.+)%s+[Ii]n%s+.+[Aa]uras?",
        "[Aa]llow%s+(.+)%s+[Ii]n%s+",
        "[Aa]llow%s+[Hh]idden%s+[Aa]ura%s+[Ss]pell%s+(.+)%s+[Ii]n%s+",
        "[Aa]llow%s+[Aa]ura%s+[Ss]pell%s+(.+)%s+[Ii]n%s+",
        "[Aa]llow%s+[Hh]idden%s+[Aa]ura%s+[Ss]pell%s+(.+)$",
        "[Aa]llow%s+[Aa]ura%s+[Ss]pell%s+(.+)$",
        "[Aa]llow%s+[Gg]roup%s+[Aa]ura%s+[Ss]pell%s+(.+)$",
        "[Aa]llow%s+[Pp]arty%s+[Aa]ura%s+[Ss]pell%s+(.+)$",
        "[Aa]llow%s+[Rr]aid%s+[Aa]ura%s+[Ss]pell%s+(.+)$",
        "[Aa]llow%s+[Pp]arty%s+[Bb]uff%s+[Aa]ura%s+[Ss]pell%s+(.+)$",
        "[Aa]llow%s+[Rr]aid%s+[Bb]uff%s+[Aa]ura%s+[Ss]pell%s+(.+)$",
        "[Aa]llow%s+[Pp]arty%s+[Dd]ebuff%s+[Aa]ura%s+[Ss]pell%s+(.+)$",
        "[Aa]llow%s+[Rr]aid%s+[Dd]ebuff%s+[Aa]ura%s+[Ss]pell%s+(.+)$",
        "[Uu]nblacklist%s+(.+)%s+[Ff]or%s+",
        "[Uu]nblacklist%s+(.+)%s+[Oo]n%s+",
        "[Uu]nblock%s+(.+)%s+[Ff]or%s+",
        "[Uu]nblock%s+(.+)%s+[Oo]n%s+",
        "[Uu]nhide%s+(.+)%s+[Ff]or%s+",
        "[Uu]nhide%s+(.+)%s+[Oo]n%s+",
        "[Ss]top%s+hiding%s+(.+)%s+[Ff]or%s+",
        "[Ss]top%s+hiding%s+(.+)%s+[Oo]n%s+",
        "[Ss]how%s+(.+)%s+again%s+[Ff]or%s+",
        "[Ss]how%s+(.+)%s+again%s+[Oo]n%s+",
        "[Ll]et%s+(.+)%s+show%s+[Ff]or%s+",
        "[Ll]et%s+(.+)%s+show%s+[Oo]n%s+",
    }
    for i = 1, #patterns do
        value = CleanAuraBlacklistSpellValue(raw:match(patterns[i]))
        if value then return value end
    end
    return nil
end

P.AURA_BLACKLIST_PRESETS = AURA_BLACKLIST_PRESETS
P.AuraBlacklistScope = AuraBlacklistScope
P.AuraBlacklistLane = AuraBlacklistLane
P.AuraEditScopeForText = AuraEditScopeForText
P.ParseAuraGeometryShortcut = ParseAuraGeometryShortcut
P.AuraGeometryShortcut = ParseAuraGeometryShortcut
P.ParseGroupAuraLiveFilterShortcut = ParseGroupAuraLiveFilterShortcut
P.ParseUnitAuraFilterBooleanShortcut = ParseUnitAuraFilterBooleanShortcut
P.ParseUnitAuraLiveFilterShortcut = ParseUnitAuraLiveFilterShortcut
P.ParseAuraFilterGuidanceShortcut = ParseAuraFilterGuidanceShortcut
P.ParseAuraDirectSettingShortcut = ParseAuraDirectSettingShortcut
P.ParseGroupAuraRootSettingShortcut = ParseGroupAuraRootSettingShortcut
P.ParseGroupAuraVisibilityShortcut = ParseGroupAuraVisibilityShortcut
P.ParseAuraCooldownSwipeDirectionShortcut = ParseAuraCooldownSwipeDirectionShortcut
P.ParseAuraDurationBarShortcut = ParseAuraDurationBarShortcut
P.ParseAuraDebuffBorderModeShortcut = ParseAuraDebuffBorderModeShortcut
P.ParseAuraScopeOverrideShortcut = ParseAuraScopeOverrideShortcut
P.AuraBlacklistPresetForText = AuraBlacklistPresetForText
P.AuraGroupBlacklistScope = AuraGroupBlacklistScope
P.AuraGroupBlacklistLane = AuraGroupBlacklistLane
P.AuraGroupBlacklistCategoryForText = AuraGroupBlacklistCategoryForText
P.AuraBlacklistSpellValue = AuraBlacklistSpellValue
