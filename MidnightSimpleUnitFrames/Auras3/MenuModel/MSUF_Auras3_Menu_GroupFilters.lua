-- Group filter compatibility bridge and Group blacklist editing.
-- Native filter token translation, hash invalidation, and raid/mythicraid fanout
-- stay together so a saved edit cannot leave either compiled group owner stale.
-- The public MSUF_GF_AuraFilter table retains its identity and legacy aliases.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
local Factories = MSUF.Auras3MenuModelFactories
if not Factories then
    Factories = {}
    MSUF.Auras3MenuModelFactories = Factories
end

function Factories.GroupFilters(A3, Model, Common, Presets, ExportPublic)
    local type = type
    local tonumber = tonumber
    local tostring = tostring
    local pairs = pairs

    local table_sort = table.sort
    local AuraFilter = Common.AuraFilter
    local ClampNumber = Common.ClampNumber
    local CompactKey = Common.CompactKey
    local CountBlacklistSpells = Common.CountBlacklistSpells
    local GroupScopeKinds = Common.GroupScopeKinds
    local NormalizeGroupScope = Common.NormalizeGroupScope
    local NormalizeKind = Common.NormalizeKind
    local Round = Common.Round
    local SpellIDFromInput = Common.SpellIDFromInput
    local SpellInfo = Common.SpellInfo
    local SpellLabel = Common.SpellLabel
    local BlacklistPresetKeysForKind = Presets.BlacklistPresetKeysForKind
    local BuildBlacklistPresetValues = Presets.BuildBlacklistPresetValues
    local FALLBACK_PUBLIC_AURA_META = Presets.FALLBACK_PUBLIC_AURA_META
    local FALLBACK_PUBLIC_AURA_SPELLS = Presets.FALLBACK_PUBLIC_AURA_SPELLS
    local PublicAuraPresetMeta = Presets.PublicAuraPresetMeta
    local PublicAuraPresetSpells = Presets.PublicAuraPresetSpells

    local _gfBlacklistHashCache = setmetatable({}, { __mode = "k" })

    local GroupBlacklistSpellID = _G.MSUF_AuraSpellIDFromKey

    local function DirectGroupBlacklistSpells(group)
        if type(group) ~= "table" then return nil end
        local blacklist = type(group.blacklist) == "table" and group.blacklist or nil
        local spells = blacklist and blacklist.spells
        if type(spells) == "table" then return spells end
        spells = group.blacklistSpells
        return type(spells) == "table" and spells or nil
    end

    local function GroupBlacklistSignature(group)
        if type(group) ~= "table" then return nil end
        local parts, count = nil, 0
        local cats = group.blacklistCats
        if type(cats) == "table" then
            for key, enabled in pairs(cats) do
                if enabled == true and type(key) == "string" and key ~= "" then
                    if not parts then parts = {} end
                    count = count + 1
                    parts[count] = "cat:" .. key
                end
            end
        end
        local spells = DirectGroupBlacklistSpells(group)
        if type(spells) == "table" then
            for key, enabled in pairs(spells) do
                if enabled == true then
                    local spellID = GroupBlacklistSpellID(key)
                    if spellID then
                        if not parts then parts = {} end
                        count = count + 1
                        parts[count] = "spell:" .. tostring(spellID)
                    end
                end
            end
        end
        if count == 0 then return nil end
        table_sort(parts)
        return table.concat(parts, "\001")
    end

    local function AddGroupBlacklistSpell(hash, n, spellID)
        spellID = GroupBlacklistSpellID(spellID)
        if not spellID then return hash, n end
        if not hash then hash = {} end
        if hash[spellID] ~= true then
            hash[spellID] = true
            n = n + 1
        end
        return hash, n
    end

    local function AddGroupBlacklistEntry(hash, n, key, value)
        local valueType = type(value)
        if value == true then
            return AddGroupBlacklistSpell(hash, n, key)
        elseif valueType == "number" or valueType == "string" then
            local nextHash, nextN = AddGroupBlacklistSpell(hash, n, value)
            if nextN ~= n then return nextHash, nextN end
            return AddGroupBlacklistSpell(hash, n, key)
        elseif valueType == "table" then
            local nextHash, nextN = AddGroupBlacklistSpell(hash, n, value.spellID or value.spellId or value.id or value[1])
            if nextN ~= n then return nextHash, nextN end
            if value.enabled ~= false then return AddGroupBlacklistSpell(hash, n, key) end
        elseif value ~= false then
            return AddGroupBlacklistSpell(hash, n, key)
        end
        return hash, n
    end

    local function BuildGroupBlacklistHash(group)
        if type(group) ~= "table" then return nil end
        local cats = group.blacklistCats
        local signature = GroupBlacklistSignature(group)
        if not signature then return nil end

        local cached = _gfBlacklistHashCache[group]
        if cached and cached.signature == signature then return cached.hash end

        local presets = PublicAuraPresetSpells()
        local hash, n = nil, 0
        if type(cats) == "table" then
            for catKey, enabled in pairs(cats) do
                if enabled == true then
                    local spells = presets and presets[catKey]
                    if type(spells) == "table" then
                        for spellID, value in pairs(spells) do
                            hash, n = AddGroupBlacklistEntry(hash, n, spellID, value)
                        end
                    end
                end
            end
        end

        local directSpells = DirectGroupBlacklistSpells(group)
        if type(directSpells) == "table" then
            for spellID, value in pairs(directSpells) do
                hash, n = AddGroupBlacklistEntry(hash, n, spellID, value)
            end
        end

        if n == 0 then
            _gfBlacklistHashCache[group] = nil
            return nil
        end

        _gfBlacklistHashCache[group] = { signature = signature, hash = hash }
        return hash
    end

    local GF_AURA_FILTER = _G.MSUF_GF_AuraFilter
    if type(GF_AURA_FILTER) ~= "table" then
        GF_AURA_FILTER = {}
        ExportPublic("MSUF_GF_AuraFilter", GF_AURA_FILTER)
    end
    GF_AURA_FILTER.PUBLIC_AURA_PRESET_SPELLS = GF_AURA_FILTER.PUBLIC_AURA_PRESET_SPELLS or FALLBACK_PUBLIC_AURA_SPELLS
    GF_AURA_FILTER.PUBLIC_AURA_PRESET_META = GF_AURA_FILTER.PUBLIC_AURA_PRESET_META or FALLBACK_PUBLIC_AURA_META
    GF_AURA_FILTER.DECLASSIFIED_SPELLS = GF_AURA_FILTER.DECLASSIFIED_SPELLS or GF_AURA_FILTER.PUBLIC_AURA_PRESET_SPELLS
    GF_AURA_FILTER.DECLASSIFIED_META = GF_AURA_FILTER.DECLASSIFIED_META or GF_AURA_FILTER.PUBLIC_AURA_PRESET_META
    GF_AURA_FILTER.GROUP_HIGHLIGHTS_TOKEN = "MSUF_GROUP_HIGHLIGHTS_V1"
    GF_AURA_FILTER.BUFF_FILTER_ITEMS = {
        { value = "ALL", text = "All Buffs" },
        {
            value = "MSUF_GROUP_HIGHLIGHTS_V1",
            text = "MSUF Highlights",
            tooltipTitle = "MSUF Highlights",
            tooltip = "Shows MSUF's curated high-value buffs from every Party or Raid member: major defensive, healing, offensive, and support cooldowns, plus tactical states such as Shroud membership and frequent high-value cooldowns such as Shadow Dance. Uses Blizzard's native aura filtering. The exact list overrides duration filters so temporary states Blizzard reports without a duration, such as Shroud membership, remain visible.",
        },
        { value = "Player", text = "Cast by Me" },
        { value = "BigDefensive", text = "Big Defensive" },
        { value = "BigDefensivePlayer", text = "Big Defensive by Me" },
        { value = "ExternalDefensive", text = "External Defensive" },
        { value = "ExternalDefensivePlayer", text = "External Defensive by Me" },
        { value = "RaidInCombat", text = "Raid In Combat" },
        { value = "Raid", text = "Applicable by Me (Raid)" },
        { value = "RaidPlayer", text = "Applicable and Cast by Me" },
    }
    GF_AURA_FILTER.DEBUFF_FILTER_ITEMS = {
        { value = "ALL", text = "All Debuffs" },
        { value = "Player", text = "Cast by Me" },
        { value = "Raid", text = "Dispellable by Me (Raid)" },
        { value = "RaidInCombat", text = "Raid In Combat" },
        { value = "RAID_PLAYER_DISPELLABLE", text = "Dispellable by Group" },
        { value = "DISPELLABLE", text = "Any Dispel Type" },
        { value = "CROWD_CONTROL", text = "Crowd Control" },
        { value = "NonPlayer", text = "Non-Player Auras" },
    }
    local function GFNativeFilterKey(token)
        return tostring(token or "ALL"):upper():gsub("[^A-Z0-9]", "")
    end
    local GF_GROUP_HIGHLIGHTS_FILTER_KEY = GFNativeFilterKey(GF_AURA_FILTER.GROUP_HIGHLIGHTS_TOKEN)
    GF_AURA_FILTER.IsGroupHighlightsFilter = function(token)
        return GFNativeFilterKey(token) == GF_GROUP_HIGHLIGHTS_FILTER_KEY
    end
    GF_AURA_FILTER.ResolveBuffIncludeHash = function(token)
        if not GF_AURA_FILTER.IsGroupHighlightsFilter(token) then return nil end
        local getter = A3.GetGroupHighlightsSpellIDHash
        if type(getter) ~= "function" then return nil end
        return getter()
    end
    local GF_CURRENT_BUFF_FILTER_TOKENS = {
        ALL = "ALL",
        MSUFGROUPHIGHLIGHTSV1 = "MSUF_GROUP_HIGHLIGHTS_V1",
        PLAYER = "Player",
        BIGDEFENSIVE = "BigDefensive",
        BIGDEFENSIVEPLAYER = "BigDefensivePlayer",
        EXTERNALDEFENSIVE = "ExternalDefensive",
        EXTERNALDEFENSIVEPLAYER = "ExternalDefensivePlayer",
        RAIDINCOMBAT = "RaidInCombat",
        RAID = "Raid",
        RAIDPLAYER = "RaidPlayer",
    }
    local GF_CURRENT_DEBUFF_FILTER_TOKENS = {
        ALL = "ALL",
        PLAYER = "Player",
        RAID = "Raid",
        RAIDINCOMBAT = "RaidInCombat",
        RAIDPLAYERDISPELLABLE = "RAID_PLAYER_DISPELLABLE",
        DISPELLABLE = "DISPELLABLE",
        CROWDCONTROL = "CROWD_CONTROL",
        NONPLAYER = "NonPlayer",
    }
    --- Stored Group Aura filters must never retain a token that the current UI no
    --- longer exposes. Reset retired/unknown filters to the lane's visible default
    --- instead of silently continuing an uneditable Blizzard filter expression.
    local function NormalizeGFStoredFilterToken(lane, token)
        local current = lane == "debuff" and GF_CURRENT_DEBUFF_FILTER_TOKENS
            or lane == "buff" and GF_CURRENT_BUFF_FILTER_TOKENS
            or nil
        if not current then return token end
        return current[GFNativeFilterKey(token)] or "ALL"
    end
    GF_AURA_FILTER.NormalizeFilterToken = NormalizeGFStoredFilterToken
    local GF_NATIVE_BUFF_FILTERS = {
        ALL = false,
        MSUFGROUPHIGHLIGHTSV1 = false,
        PLAYER = "PLAYER",
        BIGDEFENSIVEPLAYER = "BIG_DEFENSIVE|PLAYER",
        EXTERNALDEFENSIVEPLAYER = "EXTERNAL_DEFENSIVE|PLAYER",
        RAIDPLAYER = "RAID|PLAYER",
        BIGDEFENSIVE = "BIG_DEFENSIVE",
        EXTERNALDEFENSIVE = "EXTERNAL_DEFENSIVE",
        RAIDINCOMBAT = "RAID_IN_COMBAT",
        RAID = "RAID",
    }
    local GF_NATIVE_DEBUFF_FILTERS = {
        ALL = false,
        PLAYER = "PLAYER",
        RAID = "RAID",
        RAIDINCOMBAT = "RAID_IN_COMBAT",
        RAIDPLAYERDISPELLABLE = "RAID_PLAYER_DISPELLABLE",
        DISPELLABLE = "DISPELLABLE",
        CROWDCONTROL = "CROWD_CONTROL",
        NONPLAYER = false,
    }
    local function ResolveGFNativeFilter(lane, token, baseFilter, filterMap)
        local key = GFNativeFilterKey(token)
        local current = lane == "debuff" and GF_CURRENT_DEBUFF_FILTER_TOKENS or GF_CURRENT_BUFF_FILTER_TOKENS
        if not current[key] then key = "ALL" end
        local filter = filterMap[key]
        if filter == false then return baseFilter end
        if type(filter) == "string" and filter ~= "" then return baseFilter .. "|" .. filter end
        return baseFilter
    end
    GF_AURA_FILTER.ResolveBuffFilter = function(token)
        return ResolveGFNativeFilter("buff", token, "HELPFUL", GF_NATIVE_BUFF_FILTERS)
    end
    GF_AURA_FILTER.ResolveDebuffFilter = function(token)
        return ResolveGFNativeFilter("debuff", token, "HARMFUL", GF_NATIVE_DEBUFF_FILTERS)
    end
    GF_AURA_FILTER.IsNonPlayerDebuffFilter = function(token)
        return GFNativeFilterKey(token) == "NONPLAYER"
    end
    -- Blizzard's 12.1 external-defensive token already selects defensives received
    -- from other players. Keep the dedicated lane identical to the native viewer;
    -- !PLAYER adds a redundant caster-identity dependency on restricted group units.
    GF_AURA_FILTER.EXTERNALS_TOKEN = "HELPFUL|EXTERNAL_DEFENSIVE"
    GF_AURA_FILTER.BuildBlacklistHash = GF_AURA_FILTER.BuildBlacklistHash or BuildGroupBlacklistHash
    GF_AURA_FILTER.InvalidateBlacklistHash = function(group)
        if type(group) == "table" then _gfBlacklistHashCache[group] = nil end
    end

    local function GroupConf(kind)
        local db = _G.MSUF_DB
        if type(db) ~= "table" then db = {}; ExportPublic("MSUF_DB", db) end
        local key = kind == "raid" and "gf_raid" or (kind == "mythicraid" and "gf_mythicraid" or "gf_party")
        if type(db[key]) ~= "table" then db[key] = {} end
        return db[key]
    end

    local function GroupAuraRoot(kind)
        local conf = GroupConf(kind)
        if type(conf.auras) ~= "table" then conf.auras = {} end
        if conf.auras.renderer ~= "CUSTOM" then conf.auras.renderer = "CUSTOM" end
        if type(conf.auras.buff) ~= "table" then conf.auras.buff = {} end
        if type(conf.auras.debuff) ~= "table" then conf.auras.debuff = {} end
        return conf.auras
    end

    local function GroupAuraGroup(kind, groupKey)
        groupKey = NormalizeKind(groupKey)
        local root = GroupAuraRoot(kind)
        if type(root[groupKey]) ~= "table" then root[groupKey] = {} end
        return root[groupKey]
    end

    local function InvalidateGroupBlacklist(scope, groupKey)
        local af = AuraFilter()
        local a, b = GroupScopeKinds(scope)
        if af and type(af.InvalidateBlacklistHash) == "function" then
            af.InvalidateBlacklistHash(GroupAuraGroup(a, groupKey))
            if b then af.InvalidateBlacklistHash(GroupAuraGroup(b, groupKey)) end
        end
        local gf = MSUF and MSUF.GF
        if gf and type(gf.InvalidateCompiledSpecs) == "function" then
            gf.InvalidateCompiledSpecs(a)
            if b then gf.InvalidateCompiledSpecs(b) end
        end
    end

    local function EnsureGroupBlacklistSpells(kind, groupKey, create)
        local group = GroupAuraGroup(kind, groupKey)
        if type(group.blacklist) ~= "table" then
            if not create then return nil end
            group.blacklist = {}
        end
        if type(group.blacklist.spells) ~= "table" then
            if not create then return nil end
            group.blacklist.spells = {}
        end
        return group.blacklist.spells
    end

    function Model.AddGroupBlacklistSpell(scope, groupKey, value)
        local spellID = SpellIDFromInput(value)
        if not spellID then return false end
        local key = tostring(spellID)
        scope = NormalizeGroupScope(scope)
        groupKey = NormalizeKind(groupKey)
        local changed = false
        local a, b = GroupScopeKinds(scope)
        local function write(kind)
            local spells = EnsureGroupBlacklistSpells(kind, groupKey, true)
            if spells and spells[key] ~= true then
                spells[key] = true
                changed = true
            end
        end
        write(a)
        if b then write(b) end
        if changed then InvalidateGroupBlacklist(scope, groupKey) end
        return changed
    end

    function Model.RemoveGroupBlacklistSpell(scope, groupKey, value)
        local raw = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
        local spellID = SpellIDFromInput(raw)
        scope = NormalizeGroupScope(scope)
        groupKey = NormalizeKind(groupKey)
        local changed = false
        local a, b = GroupScopeKinds(scope)
        local function remove(kind)
            local spells = EnsureGroupBlacklistSpells(kind, groupKey, false)
            if type(spells) ~= "table" then return end
            if spellID and spells[tostring(spellID)] ~= nil then
                spells[tostring(spellID)] = nil
                changed = true
            end
            if raw ~= "" and spells[raw] ~= nil then
                spells[raw] = nil
                changed = true
            end
        end
        remove(a)
        if b then remove(b) end
        if changed then InvalidateGroupBlacklist(scope, groupKey) end
        return changed
    end

    function Model.ClearGroupBlacklistSpells(scope, groupKey)
        scope = NormalizeGroupScope(scope)
        groupKey = NormalizeKind(groupKey)
        local count, changed = 0, false
        local a, b = GroupScopeKinds(scope)
        local function clear(kind)
            local spells = EnsureGroupBlacklistSpells(kind, groupKey, false)
            local n = CountBlacklistSpells(spells)
            if n > 0 then
                count = count + n
                local group = GroupAuraGroup(kind, groupKey)
                if type(group.blacklist) ~= "table" then group.blacklist = {} end
                group.blacklist.spells = {}
                changed = true
            end
        end
        clear(a)
        if b then clear(b) end
        if changed then InvalidateGroupBlacklist(scope, groupKey) end
        return count
    end

    function Model.GroupBlacklistSummary(scope, groupKey)
        scope = NormalizeGroupScope(scope)
        groupKey = NormalizeKind(groupKey)
        local a = GroupScopeKinds(scope)
        local spells = EnsureGroupBlacklistSpells(a, groupKey, false)
        if type(spells) ~= "table" then return "No blacklisted spells." end
        local out = {}
        for key, enabled in pairs(spells) do
            if enabled == true then
                local spellID = SpellIDFromInput(key)
                out[#out + 1] = spellID and SpellLabel(spellID) or (tostring(key) .. " (unresolved)")
            end
        end
        table_sort(out)
        if #out == 0 then return "No blacklisted spells." end
        return table.concat(out, "\n")
    end

    function Model.ReadGroupBlacklistHidePermanent(scope, groupKey)
        local kind = GroupScopeKinds(scope)
        local group = GroupAuraGroup(kind, groupKey)
        local blacklist = type(group.blacklist) == "table" and group.blacklist or nil
        return blacklist and blacklist.hidePermanent == true or false
    end

    function Model.WriteGroupBlacklistHidePermanent(scope, groupKey, value)
        local nextValue = value == true
        local changed = false
        local a, b = GroupScopeKinds(scope)
        local function Write(kind)
            local group = GroupAuraGroup(kind, groupKey)
            if type(group.blacklist) ~= "table" then group.blacklist = {} end
            if group.blacklist.hidePermanent ~= nextValue then
                group.blacklist.hidePermanent = nextValue
                changed = true
            end
        end
        Write(a)
        if b then Write(b) end
        if changed then InvalidateGroupBlacklist(scope, groupKey) end
        return changed
    end

    function Model.ReadGroupBlacklistMaxDuration(scope, groupKey)
        local kind = GroupScopeKinds(scope)
        local group = GroupAuraGroup(kind, groupKey)
        local blacklist = type(group.blacklist) == "table" and group.blacklist or nil
        return ClampNumber(blacklist and blacklist.maxDuration, 0, 0, 180)
    end

    function Model.WriteGroupBlacklistMaxDuration(scope, groupKey, value)
        local nextValue = Round(ClampNumber(value, 0, 0, 180))
        local changed = false
        local a, b = GroupScopeKinds(scope)
        local function Write(kind)
            local group = GroupAuraGroup(kind, groupKey)
            if type(group.blacklist) ~= "table" then group.blacklist = {} end
            if (tonumber(group.blacklist.maxDuration) or 0) ~= nextValue then
                group.blacklist.maxDuration = nextValue
                changed = true
            end
        end
        Write(a)
        if b then Write(b) end
        if changed then InvalidateGroupBlacklist(scope, groupKey) end
        return changed
    end

    function Model.GroupBlacklistEntries(scope, groupKey)
        scope = NormalizeGroupScope(scope)
        groupKey = NormalizeKind(groupKey)
        local a = GroupScopeKinds(scope)
        local spells = EnsureGroupBlacklistSpells(a, groupKey, false)
        local out = {}
        if type(spells) ~= "table" then return out end
        for key, enabled in pairs(spells) do
            if enabled == true then
                local spellID = SpellIDFromInput(key)
                local icon
                if spellID then
                    local _, _, resolvedIcon = SpellInfo(spellID)
                    icon = resolvedIcon
                end
                out[#out + 1] = {
                    value = spellID and tostring(spellID) or tostring(key),
                    text = spellID and SpellLabel(spellID) or (tostring(key) .. " (unresolved)"),
                    icon = icon,
                }
            end
        end
        table_sort(out, function(x, y) return tostring(x.text) < tostring(y.text) end)
        return out
    end

    function Model.GroupBlacklistPresetAllowed(groupKey, presetKey)
        presetKey = tostring(presetKey or "")
        return BlacklistPresetKeysForKind(groupKey)[presetKey] == true
    end

    function Model.GroupBlacklistPresetValues(groupKey)
        return BuildBlacklistPresetValues(BlacklistPresetKeysForKind(groupKey))
    end

    function Model.GroupBlacklistSpellValues(groupKey, presetKey)
        if not Model.GroupBlacklistPresetAllowed(groupKey, presetKey) then return {} end
        return Model.BlacklistSpellValues(presetKey)
    end

    function Model.AddGroupBlacklistPresetGroup(scope, groupKey, presetKey)
        local values = Model.GroupBlacklistSpellValues(groupKey, presetKey)
        local count = 0
        for i = 1, #values do
            local item = values[i]
            if item and item.value and Model.AddGroupBlacklistSpell(scope, groupKey, item.value) then
                count = count + 1
            end
        end
        return count
    end

    function Model.GroupBlacklistCategoryValues()
        local meta = PublicAuraPresetMeta()
        local values = {}
        if type(meta) ~= "table" then return values end
        for i = 1, #meta do
            local item = meta[i]
            if item and item.key then
                values[#values + 1] = {
                    key = item.key,
                    value = item.key,
                    label = item.label or item.key,
                    text = item.label or item.key,
                    category = item.category,
                    tooltip = item.tooltip,
                }
            end
        end
        return values
    end

    function Model.GroupBlacklistCategoryLabel(catKey)
        if catKey == "RAID_BUFFS" then return "Raid / Mythic Buffs" end
        local values = Model.GroupBlacklistCategoryValues()
        for i = 1, #values do
            local item = values[i]
            if item.key == catKey then return item.label or item.key end
        end
        return tostring(catKey or "")
    end

    function Model.ResolveGroupBlacklistCategory(value)
        local compact = CompactKey(value)
        if compact == "" then return nil end
        local values = Model.GroupBlacklistCategoryValues()
        local bestKey, bestLen
        for i = 1, #values do
            local item = values[i]
            local key = item.key
            local keyCompact = CompactKey(key)
            local labelCompact = CompactKey(item.label or item.text or key)
            local categoryCompact = CompactKey(item.category)
            local matchLen
            if compact == keyCompact or compact == labelCompact then
                matchLen = math.max(#keyCompact, #labelCompact)
            elseif #labelCompact >= 5 and compact:find(labelCompact, 1, true) then
                matchLen = #labelCompact
            elseif #keyCompact >= 5 and compact:find(keyCompact, 1, true) then
                matchLen = #keyCompact
            elseif #categoryCompact >= 5 and compact == categoryCompact then
                matchLen = #categoryCompact
            end
            if matchLen and (not bestLen or matchLen > bestLen) then
                bestKey, bestLen = key, matchLen
            end
        end
        return bestKey
    end

    function Model.ReadGroupBlacklistCategory(scope, groupKey, catKey)
        scope = NormalizeGroupScope(scope)
        groupKey = NormalizeKind(groupKey)
        catKey = Model.ResolveGroupBlacklistCategory(catKey) or catKey
        if type(catKey) ~= "string" or catKey == "" then return false end
        local a = GroupScopeKinds(scope)
        local group = GroupAuraGroup(a, groupKey)
        return type(group.blacklistCats) == "table" and group.blacklistCats[catKey] == true
    end

    function Model.ReadGroupBlacklistCategoryState(scope, groupKey, catKey)
        scope = NormalizeGroupScope(scope)
        groupKey = NormalizeKind(groupKey)
        catKey = Model.ResolveGroupBlacklistCategory(catKey) or catKey
        local a, b = GroupScopeKinds(scope)
        if type(catKey) ~= "string" or catKey == "" then
            if b then return { raid = false, mythicraid = false } end
            return { party = false }
        end
        local function read(kind)
            local group = GroupAuraGroup(kind, groupKey)
            return type(group.blacklistCats) == "table" and group.blacklistCats[catKey] == true
        end
        if b then
            return { raid = read(a), mythicraid = read(b) }
        end
        return { party = read(a) }
    end

    function Model.WriteGroupBlacklistCategory(scope, groupKey, catKey, value)
        scope = NormalizeGroupScope(scope)
        groupKey = NormalizeKind(groupKey)
        catKey = Model.ResolveGroupBlacklistCategory(catKey) or catKey
        if type(catKey) ~= "string" or catKey == "" then return false end
        local changed = false
        local a, b = GroupScopeKinds(scope)
        local function write(kind)
            local group = GroupAuraGroup(kind, groupKey)
            if type(group.blacklistCats) ~= "table" then group.blacklistCats = {} end
            local nextValue = value and true or nil
            if group.blacklistCats[catKey] == nextValue then return end
            group.blacklistCats[catKey] = nextValue
            changed = true
        end
        write(a)
        if b then write(b) end
        if changed then InvalidateGroupBlacklist(scope, groupKey) end
        return changed
    end

    function Model.WriteGroupBlacklistCategoryState(scope, groupKey, catKey, state)
        if type(state) ~= "table" then return Model.WriteGroupBlacklistCategory(scope, groupKey, catKey, state) end
        scope = NormalizeGroupScope(scope)
        groupKey = NormalizeKind(groupKey)
        catKey = Model.ResolveGroupBlacklistCategory(catKey) or catKey
        if type(catKey) ~= "string" or catKey == "" then return false end
        local changed = false
        local a, b = GroupScopeKinds(scope)
        local function write(kind)
            local group = GroupAuraGroup(kind, groupKey)
            if type(group.blacklistCats) ~= "table" then group.blacklistCats = {} end
            local nextValue = state[kind] == true and true or nil
            if group.blacklistCats[catKey] == nextValue then return end
            group.blacklistCats[catKey] = nextValue
            changed = true
        end
        write(a)
        if b then write(b) end
        if changed then InvalidateGroupBlacklist(scope, groupKey) end
        return changed
    end

    function Model.GroupBlacklistCategorySummary(scope, groupKey)
        scope = NormalizeGroupScope(scope)
        groupKey = NormalizeKind(groupKey)
        local a = GroupScopeKinds(scope)
        local group = GroupAuraGroup(a, groupKey)
        local cats = type(group.blacklistCats) == "table" and group.blacklistCats or nil
        if type(cats) ~= "table" then return "No blacklisted aura categories." end
        local out = {}
        for key, enabled in pairs(cats) do
            if enabled == true then out[#out + 1] = Model.GroupBlacklistCategoryLabel(key) end
        end
        table_sort(out)
        if #out == 0 then return "No blacklisted aura categories." end
        return table.concat(out, "\n")
    end

end
