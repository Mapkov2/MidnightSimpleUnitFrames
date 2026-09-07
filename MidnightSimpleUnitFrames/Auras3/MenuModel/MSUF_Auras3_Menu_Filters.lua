-- Unit aura filter scopes and blacklist editing/live menu inspection.
-- Rule inheritance is independent of visual inheritance. Writes retain the
-- established scope fanout; blacklist reads never become live render work.
-- Live menu inspection keeps the existing secret-value and access guards.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
local Factories = MSUF.Auras3MenuModelFactories
if not Factories then
    Factories = {}
    MSUF.Auras3MenuModelFactories = Factories
end

function Factories.Filters(A3, Model, Schema, Common, Storage)
    local type = type
    local tonumber = tonumber
    local tostring = tostring
    local pairs = pairs
    local table_sort = table.sort
    local C_Spell = _G.C_Spell
    local GetSpellInfo = _G.GetSpellInfo
    local DEFAULT_SHARED = Schema.DEFAULT_SHARED
    local RUNTIME_FILTER_KEYS = Schema.RUNTIME_FILTER_KEYS
    local ClampNumber = Common.ClampNumber
    local CountBlacklistSpells = Common.CountBlacklistSpells
    local DeepCopy = Common.DeepCopy
    local EachRuntimeUnit = Common.EachRuntimeUnit
    local NormalizeKind = Common.NormalizeKind
    local NormalizeScope = Common.NormalizeScope
    local Round = Common.Round
    local RuntimeUnit = Common.RuntimeUnit
    local SpellIDFromInput = Common.SpellIDFromInput
    local SpellInfo = Common.SpellInfo
    local SpellLabel = Common.SpellLabel
    local DefaultsIntoOnce = Storage.DefaultsIntoOnce
    local PerUnit = Storage.PerUnit

    --- Filter scopes are independent from visual layout scopes. A unit can share
    --- its icon positions while overriding aura rules, so reads/writes go through
    --- EnsureScopeFilters rather than the layout helpers above.
    local function EnsureRuntimeFilters(auras, shared, unit, create)
        local pu = PerUnit(auras, unit, create)
        if not pu then return DEFAULT_SHARED.filters end
        if create then
            pu.overrideFilters = true
            if type(pu.filters) ~= "table" then pu.filters = DeepCopy(DEFAULT_SHARED.filters) end
            DefaultsIntoOnce(pu.filters, DEFAULT_SHARED.filters)
            return pu.filters
        end
        if type(pu.filters) == "table" then
            DefaultsIntoOnce(pu.filters, DEFAULT_SHARED.filters)
            return pu.filters
        end
        return DEFAULT_SHARED.filters
    end

    local function EnsureScopeFilters(scope, create)
        local auras, shared = Model.EnsureDB()
        scope = NormalizeScope(scope)
        if scope == "shared" then
            DefaultsIntoOnce(shared.filters, DEFAULT_SHARED.filters)
            return shared.filters
        end
        return EnsureRuntimeFilters(auras, shared, RuntimeUnit(scope), create)
    end

    local function ForEachScopeFilters(scope, create, callback)
        if type(callback) ~= "function" then return end
        local auras, shared = Model.EnsureDB()
        scope = NormalizeScope(scope)
        if scope == "shared" then
            DefaultsIntoOnce(shared.filters, DEFAULT_SHARED.filters)
            callback(shared.filters, true, shared)
            return
        end
        EachRuntimeUnit(scope, function(runtimeUnit)
            callback(EnsureRuntimeFilters(auras, shared, runtimeUnit, create), false, shared)
        end)
    end

    function Model.UseSharedRules(scope)
        return false
    end

    function Model.SetUseSharedRules(scope, useShared)
        scope = NormalizeScope(scope)
        if scope == "shared" then return end
        local auras, shared = Model.EnsureDB()
        EachRuntimeUnit(scope, function(runtimeUnit)
            local pu = PerUnit(auras, runtimeUnit, true)
            if not pu then return end
            local f = EnsureRuntimeFilters(auras, shared, runtimeUnit, true)
            pu.filters = f
            pu.overrideFilters = true
        end)
    end

    function Model.ReadFilter(scope, kind, key, defaultValue)
        local filters = EnsureScopeFilters(scope, false)
        kind = NormalizeKind(kind)
        local tableKey = kind == "buff" and "buffs" or "debuffs"
        local group = filters and filters[tableKey]
        if type(group) ~= "table" then return defaultValue end
        local value = group[key]
        if key == "exclusive" and value == "important" then return "none" end
        if value ~= nil then return value end
        return defaultValue
    end

    function Model.WriteFilter(scope, kind, key, value)
        kind = NormalizeKind(kind)
        local tableKey = kind == "buff" and "buffs" or "debuffs"
        if key == "exclusive" and value == "important" then value = "none" end
        ForEachScopeFilters(scope, true, function(filters)
            if type(filters) ~= "table" then return end
            if type(filters[tableKey]) ~= "table" then filters[tableKey] = {} end
            filters[tableKey][key] = value
        end)
    end

    function Model.LaneFiltersEnabled(scope, kind)
        local filters = EnsureScopeFilters(scope, false)
        kind = NormalizeKind(kind)
        local tableKey = kind == "buff" and "buffs" or "debuffs"
        local lane = type(filters) == "table" and filters[tableKey] or nil
        return type(lane) ~= "table" or lane.enabled ~= false
    end

    function Model.SetLaneFiltersEnabled(scope, kind, enabled)
        kind = NormalizeKind(kind)
        local tableKey = kind == "buff" and "buffs" or "debuffs"
        ForEachScopeFilters(scope, true, function(filters)
            if type(filters) ~= "table" then return end
            if type(filters[tableKey]) ~= "table" then filters[tableKey] = {} end
            filters[tableKey].enabled = enabled == true
        end)
    end

    function Model.ScopeFiltersEnabled(scope)
        return Model.LaneFiltersEnabled(scope, "buff")
            and Model.LaneFiltersEnabled(scope, "debuff")
    end

    local function ApplyScopeFiltersEnabled(filters, enabled, sharedScope, shared)
        if type(filters) ~= "table" then return end

        local snap = filters.disabledSnapshot
        if enabled then
            if type(snap) == "table" then
                for groupKey, keys in pairs(RUNTIME_FILTER_KEYS) do
                    local group = filters[groupKey]
                    local groupSnap = snap[groupKey]
                    if type(group) == "table" and type(groupSnap) == "table" then
                        for i = 1, #keys do
                            local key = keys[i]
                            if groupSnap[key] ~= nil then group[key] = groupSnap[key] end
                        end
                    end
                end
                if sharedScope and type(shared) == "table" then
                    if snap.onlyMyBuffs ~= nil then shared.onlyMyBuffs = snap.onlyMyBuffs end
                    if snap.onlyMyDebuffs ~= nil then shared.onlyMyDebuffs = snap.onlyMyDebuffs end
                end
                if snap.hidePermanent ~= nil then
                    filters.hidePermanent = snap.hidePermanent == true
                end
                filters.disabledSnapshot = nil
            end
            filters.enabled = true
            return
        end

        if type(snap) ~= "table" then
            snap = {}
            for groupKey, keys in pairs(RUNTIME_FILTER_KEYS) do
                local group = filters[groupKey]
                if type(group) == "table" then
                    local groupSnap = {}
                    for i = 1, #keys do
                        local key = keys[i]
                        groupSnap[key] = group[key]
                    end
                    snap[groupKey] = groupSnap
                end
            end
            if sharedScope and type(shared) == "table" then
                snap.onlyMyBuffs = shared.onlyMyBuffs
                snap.onlyMyDebuffs = shared.onlyMyDebuffs
            end
            filters.disabledSnapshot = snap
        end

        if type(filters.buffs) == "table" then
            filters.buffs.onlyMine = false
            filters.buffs.onlyImportant = false
            filters.buffs.raid = false
            filters.buffs.raidInCombat = false
            filters.buffs.includeNameplateOnly = false
            filters.buffs.includeDispellable = false
            filters.buffs.dispellableAny = false
            filters.buffs.cancelable = false
            filters.buffs.notCancelable = false
            filters.buffs.externalDefensive = false
            filters.buffs.bigDefensive = false
            filters.buffs.exclusive = "none"
        end
        if type(filters.debuffs) == "table" then
            filters.debuffs.onlyMine = false
            filters.debuffs.onlyImportant = false
            filters.debuffs.raid = false
            filters.debuffs.raidInCombat = false
            filters.debuffs.includeNameplateOnly = false
            filters.debuffs.includeDispellable = false
            filters.debuffs.dispellableAny = false
            filters.debuffs.crowdControl = false
            filters.debuffs.nonPlayer = false
            filters.debuffs.exclusive = "none"
        end
        if sharedScope and type(shared) == "table" then
            shared.onlyMyBuffs = false
            shared.onlyMyDebuffs = false
        end
        filters.enabled = false
    end

    function Model.SetScopeFiltersEnabled(scope, enabled)
        ForEachScopeFilters(scope, true, function(filters, sharedScope, shared)
            ApplyScopeFiltersEnabled(filters, enabled == true, sharedScope, shared)
            filters.buffs = type(filters.buffs) == "table" and filters.buffs or {}
            filters.debuffs = type(filters.debuffs) == "table" and filters.debuffs or {}
            filters.buffs.enabled = enabled == true
            filters.debuffs.enabled = enabled == true
        end)
    end

    --- Blacklists remain saved in human-editable form. The 12.1 native runtime does
    --- not rebuild blacklist tables during aura display updates.
    local function BlacklistLane(root, kind, create)
        if type(root) ~= "table" then return nil end
        if kind ~= "buff" and kind ~= "debuff" then
            if type(root.spells) ~= "table" and create then root.spells = {} end
            return root
        end
        local key = kind == "buff" and "buffs" or "debuffs"
        if type(root[key]) ~= "table" and create then
            root[key] = { spells = DeepCopy(type(root.spells) == "table" and root.spells or {}) }
        end
        local lane = root[key]
        if type(lane) == "table" and type(lane.spells) ~= "table" and create then lane.spells = {} end
        return lane
    end

    local function EnsureRuntimeBlacklist(auras, runtimeUnit, create, kind)
        local pu = PerUnit(auras, runtimeUnit, true)
        if not pu then return nil end
        pu.overrideBlacklist = true -- retained only for old profile/import compatibility
        if type(pu.blacklist) ~= "table" then pu.blacklist = { spells = {} } end
        if type(pu.blacklist.spells) ~= "table" then pu.blacklist.spells = {} end
        return BlacklistLane(pu.blacklist, kind, create) or BlacklistLane(pu.blacklist, kind, true)
    end

    local function EnsureBlacklist(scope, create, kind)
        local auras = Model.EnsureDB()
        scope = NormalizeScope(scope)
        if scope == "shared" then return nil end
        return EnsureRuntimeBlacklist(auras, RuntimeUnit(scope), create, kind)
    end

    local function ForEachFrameBlacklist(scope, create, kind, callback)
        scope = NormalizeScope(scope)
        if scope == "shared" or type(callback) ~= "function" then return end
        local auras = Model.EnsureDB()
        EachRuntimeUnit(scope, function(runtimeUnit)
            callback(EnsureRuntimeBlacklist(auras, runtimeUnit, create, kind))
        end)
    end

    --- Expose the manual-entry resolver so blacklist UIs can inspect what an
    --- input resolves to (a typed name resolves to the player's cast SpellID,
    --- which is not always the SpellID of the aura left on the unit).
    function Model.ResolveSpellInputID(value)
        return SpellIDFromInput(value)
    end

    local function LiveAuraSecretHelpers()
        local Secrets = type(MSUF.Secrets) == "table" and MSUF.Secrets or nil
        local SafeNumber = Secrets and Secrets.SafeNumber or tonumber
        local NotSecret = Secrets and Secrets.NotSecret or function(_) return true end
        return SafeNumber, NotSecret, Secrets
    end

    --- Tainted aura queries hard-error under Blizzard's addon restrictions. The
    --- observed denial contexts are encounters, Mythic+ (challenge restrictions),
    --- PvP matches, and instanced combat while aura secrecy is active; plain
    --- open-world combat keeps the query callable with per-field secrets.
    local function LiveAuraAccessRestricted()
        local IsEncounterInProgress = _G.IsEncounterInProgress
        if type(IsEncounterInProgress) == "function" and IsEncounterInProgress() then return true end
        local ChallengeMode = _G.C_ChallengeMode
        if type(ChallengeMode) == "table" and type(ChallengeMode.IsChallengeModeActive) == "function"
            and ChallengeMode.IsChallengeModeActive() then return true end
        local PartyInfo = _G.C_PartyInfo
        if type(PartyInfo) == "table" and type(PartyInfo.ChallengeModeRestrictionsActive) == "function"
            and PartyInfo.ChallengeModeRestrictionsActive() then return true end
        local PvP = _G.C_PvP
        if type(PvP) == "table" and type(PvP.IsMatchActive) == "function"
            and PvP.IsMatchActive() then return true end
        local SecretsAPI = _G.C_Secrets
        if type(SecretsAPI) == "table" and type(SecretsAPI.ShouldAurasBeSecret) == "function"
            and SecretsAPI.ShouldAurasBeSecret() == true then
            local IsInInstance = _G.IsInInstance
            if type(IsInInstance) == "function" then
                local inInstance = IsInInstance()
                if inInstance == true or inInstance == 1 then return true end
            end
        end
        return false
    end

    --- Walk every readable aura on the live unit(s) behind a menu scope. Secret
    --- aura fields are the callback's problem to skip; this only guards the unit
    --- and API surface. Returns walked, accessBlockedCount (non-zero when the
    --- restricted context above forbids querying at all); the callback may
    --- return false to stop the walk early.
    local function ForEachLiveUnitAura(scope, kind, callback)
        local CUA = _G.C_UnitAuras
        local UnitExists = _G.UnitExists
        if type(UnitExists) ~= "function" or type(CUA) ~= "table" then return false, 0 end
        local GetByIndex = type(CUA.GetAuraDataByIndex) == "function" and CUA.GetAuraDataByIndex or nil
        if not GetByIndex then return false, 0 end
        scope = NormalizeScope(scope)
        if scope == "shared" then return false, 0 end
        if LiveAuraAccessRestricted() then return false, 1 end
        local _, _, Secrets = LiveAuraSecretHelpers()
        local UnitThere = Secrets and Secrets.UnitExistsPlain
            or function(unit) local exists = UnitExists(unit) return exists == true or exists == 1 end
        local filter = NormalizeKind(kind) == "debuff" and "HARMFUL" or "HELPFUL"
        local stop = false
        EachRuntimeUnit(scope, function(runtimeUnit)
            if stop or not UnitThere(runtimeUnit) then return end
            for i = 1, 80 do
                local aura = GetByIndex(runtimeUnit, i, filter)
                if type(aura) ~= "table" then break end
                if callback(aura) == false then stop = true return end
            end
        end)
        return true, 0
    end

    --- Coldpath check for the manual blacklist inputs: report whether the entered
    --- SpellID is visible on the live unit right now, or whether only a same-named
    --- aura with a different SpellID is (the cast-ID vs aura-ID trap). Secret aura
    --- fields are skipped, never compared; unreadable data yields no verdict.
    function Model.FindLiveBlacklistAura(scope, spellID, kind)
        spellID = tonumber(spellID)
        if not spellID then return nil end
        local SafeNumber, NotSecret = LiveAuraSecretHelpers()
        local wantedName
        if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
            local info = C_Spell.GetSpellInfo(spellID)
            if type(info) == "table" and type(info.name) == "string" and info.name ~= "" then
                wantedName = info.name
            end
        end
        local active, suggestion
        local walked = ForEachLiveUnitAura(scope, kind, function(aura)
            local auraID = SafeNumber(aura.spellId)
            if not auraID then return end
            if auraID == spellID then active = true return false end
            if wantedName and not suggestion then
                local auraName = aura.name
                if NotSecret(auraName) and type(auraName) == "string" and auraName == wantedName then
                    suggestion = { spellID = auraID, name = auraName }
                end
            end
        end)
        if not walked then return nil end
        if active then return { status = "active", spellID = spellID, name = wantedName } end
        if suggestion then
            return { status = "mismatch", spellID = spellID, name = wantedName,
                suggestID = suggestion.spellID, suggestName = suggestion.name }
        end
        return nil
    end

    --- Values list for the live-aura blacklist dropdown: every aura whose SpellID
    --- is readable on the unit(s) right now, carrying the exact ID the aura uses.
    --- Auras with secret IDs cannot be listed (and could not be matched anyway).
    function Model.LiveBlacklistAuraValues(scope, kind)
        local values = {}
        local SafeNumber, NotSecret = LiveAuraSecretHelpers()
        local seen = {}
        local unreadable = 0
        local _, secretSkipped = ForEachLiveUnitAura(scope, kind, function(aura)
            local auraID = SafeNumber(aura.spellId)
            if not auraID then unreadable = unreadable + 1 return end
            if seen[auraID] then return end
            seen[auraID] = true
            local name = aura.name
            if not (NotSecret(name) and type(name) == "string" and name ~= "") then name = nil end
            local icon = aura.icon
            if not (NotSecret(icon) and (type(icon) == "number" or type(icon) == "string")) then icon = nil end
            if not name or not icon then
                local _, staticName, staticIcon = SpellInfo(auraID)
                name = name or staticName
                icon = icon or staticIcon
            end
            local text = (type(name) == "string" and name ~= "" and name or "Spell")
                .. " (#" .. tostring(auraID) .. ")"
            values[#values + 1] = { value = auraID, text = text, name = name, icon = icon }
        end)
        table_sort(values, function(a, b) return tostring(a.text) < tostring(b.text) end)
        -- The second return reports auras hidden by secret data (secret index or
        -- secret SpellID), so scan UIs can say "hidden" instead of under-counting.
        -- The third reports that Blizzard denies aura access entirely right now:
        -- under restrictions every index probes secret, so nothing is readable.
        unreadable = unreadable + (tonumber(secretSkipped) or 0)
        return values, unreadable, (#values == 0 and (tonumber(secretSkipped) or 0) > 0)
    end

    function Model.AddBlacklistSpell(scope, value, kind)
        local spellID = SpellIDFromInput(value)
        if not spellID then return false end
        value = tostring(spellID)
        local changed = false
        ForEachFrameBlacklist(scope, true, kind, function(list)
            if type(list) == "table" and type(list.spells) == "table" then
                if list.spells[value] ~= true then changed = true end
                list.spells[value] = true
            end
        end)
        return changed
    end

    function Model.ReadBlacklistHidePermanent(scope, kind)
        local list = EnsureBlacklist(scope, false, kind)
        return type(list) == "table" and list.hidePermanent == true
    end

    function Model.WriteBlacklistHidePermanent(scope, kind, value)
        local nextValue = value == true
        local changed = false
        ForEachFrameBlacklist(scope, true, kind, function(list)
            if type(list) == "table" and list.hidePermanent ~= nextValue then
                list.hidePermanent = nextValue
                changed = true
            end
        end)
        return changed
    end

    function Model.ReadBlacklistMaxDuration(scope, kind)
        local list = EnsureBlacklist(scope, false, kind)
        return ClampNumber(type(list) == "table" and list.maxDuration, 0, 0, 180)
    end

    function Model.WriteBlacklistMaxDuration(scope, kind, value)
        local nextValue = Round(ClampNumber(value, 0, 0, 180))
        local changed = false
        ForEachFrameBlacklist(scope, true, kind, function(list)
            if type(list) == "table" and (tonumber(list.maxDuration) or 0) ~= nextValue then
                list.maxDuration = nextValue
                changed = true
            end
        end)
        return changed
    end

    function Model.RemoveBlacklistSpell(scope, value, kind)
        local raw = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
        local spellID = SpellIDFromInput(raw)
        local changed = false
        ForEachFrameBlacklist(scope, true, kind, function(list)
            if type(list) == "table" and type(list.spells) == "table" then
                if spellID and list.spells[tostring(spellID)] ~= nil then
                    list.spells[tostring(spellID)] = nil
                    changed = true
                end
                if raw ~= "" and list.spells[raw] ~= nil then
                    list.spells[raw] = nil
                    changed = true
                end
            end
        end)
        return changed
    end

    function Model.BlacklistSummary(scope, kind)
        local list = EnsureBlacklist(scope, false, kind)
        local spells = type(list) == "table" and list.spells
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

    function Model.BlacklistEntries(scope, kind)
        local list = EnsureBlacklist(scope, false, kind)
        local spells = type(list) == "table" and list.spells
        local out = {}
        if type(spells) ~= "table" then return out end
        for key, enabled in pairs(spells) do
            if enabled == true then
                local spellID = SpellIDFromInput(key)
                if spellID then
                    local id, name, icon = SpellInfo(spellID)
                    id = id or spellID
                    out[#out + 1] = {
                        value = tostring(id),
                        spellID = id,
                        text = (type(name) == "string" and name ~= "" and name or "Spell") .. " (#" .. tostring(id) .. ")",
                        icon = icon,
                    }
                else
                    out[#out + 1] = {
                        value = tostring(key),
                        text = tostring(key) .. " (unresolved)",
                    }
                end
            end
        end
        table_sort(out, function(a, b) return tostring(a.text) < tostring(b.text) end)
        return out
    end

    function Model.ClearBlacklistSpells(scope, kind)
        local effective = EnsureBlacklist(scope, false, kind)
        local count = CountBlacklistSpells(type(effective) == "table" and effective.spells or nil)
        ForEachFrameBlacklist(scope, true, kind, function(list)
            if type(list) == "table" then list.spells = {} end
        end)
        return count
    end

    function Model.BlacklistPreparedCount(scope, kind)
        local list = EnsureBlacklist(scope, false, kind)
        local spells = type(list) == "table" and list.spells
        if type(spells) ~= "table" then return 0 end
        local count = 0
        for key, enabled in pairs(spells) do
            if enabled == true and SpellIDFromInput(key) then count = count + 1 end
        end
        return count
    end

end
