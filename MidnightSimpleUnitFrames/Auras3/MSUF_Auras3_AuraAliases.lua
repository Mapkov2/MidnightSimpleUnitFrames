-- Custom action/talent IDs may differ from their same-name aura IDs. Resolve
-- the complete client-data group once, while compiling configuration. Native
-- candidate filters then own selection, including restricted combat auras.
-- No aura reads, event listeners, timers, protected calls or live refreshes.
local _, MSUF = ...
local A3 = MSUF.MSUF_Auras3
local catalog = A3.AuraAliasCatalog
local common, localized = catalog.common, catalog.localized
local width, step = catalog.width, catalog.width + 1
local find, sub, byte = string.find, string.sub, string.byte
local floor, tonumber, pairs = math.floor, tonumber, pairs
local digits = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
local resolved, commonGroups, localizedGroups = {}, {}, {}

local function ReadGroup(data, groups, token)
    if not data then return end
    -- C performs the string search over ~1.4 MB of selected-locale data. This
    -- avoids a permanent reverse index with hundreds of thousands of Lua keys.
    -- The result (including a miss) is memoized for the configured source ID.
    local at = find(data, token, 1, true)
    if not at then return end
    local first = at
    while first > step and byte(data, first - step) == 95 do first = first - step end
    local group = groups[first]
    if group then return group end
    group = {}
    at = first
    while byte(data, at) == 95 do
        group[#group + 1] = tonumber(sub(data, at + 1, at + width), 36)
        at = at + step
    end
    groups[first] = group
    return group
end

function A3.CompileCustomAuraAliases(spellIDs)
    if not spellIDs then return end
    for spellID in pairs(spellIDs) do
        if not resolved[spellID] then
            resolved[spellID] = true
            if spellID > 0 and spellID % 1 == 0 and spellID < 36 ^ width then
                local value, token = spellID, ""
                for _ = 1, width do
                    local digit = value % 36 + 1
                    token = sub(digits, digit, digit) .. token
                    value = floor(value / 36)
                end
                token = "_" .. token
                local group = ReadGroup(common, commonGroups, token)
                    or ReadGroup(localized, localizedGroups, token)
                if group then
                    local aliases = A3.AuraSpellIDAliases[spellID]
                    if aliases then
                        -- Explicit aliases may deliberately have a different
                        -- name (e.g. Fade to Nothing). Never lose that contract
                        -- or mutate the immutable group shared by other IDs.
                        local merged, seen = {}, {}
                        for i = 1, #group do
                            local id = group[i]
                            merged[#merged + 1], seen[id] = id, true
                        end
                        for i = 1, #aliases do
                            local id = aliases[i]
                            if not seen[id] then merged[#merged + 1], seen[id] = id, true end
                        end
                        group = merged
                    end
                    A3.AuraSpellIDAliases[spellID] = group
                end
            end
        end
    end
end
