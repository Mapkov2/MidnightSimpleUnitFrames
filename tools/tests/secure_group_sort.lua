-- secure_group_sort.lua -- the order a SecureGroupHeader shows, for smokes.
--
-- Mirrors SecureGroupHeader_Update's roster selection and sorting in
-- Blizzard_RestrictedAddOnEnvironment/SecureGroupHeaders.lua (the same code on
-- live, forever, classic_era, classic_anniversary and classic for these
-- attributes): nameList as a filter (NAMELIST keeps its order, NAME sorts),
-- otherwise groupFilter/roleFilter (default "1,...,8", non-strict) with an
-- optional groupBy GROUP/CLASS/ROLE/ASSIGNEDROLE ordered by groupingOrder and
-- INDEX or NAME inside a group, and sortDir DESC reversing the whole list.
--
-- Order(header, roster) returns the shown names joined by commas.
-- roster = { kind = "RAID" or "PARTY", members = { { unit, name, subgroup,
-- class, role, assignedRole }, ... } } in Blizzard's index order (party: player
-- first when the header shows it).

local Sort = {}

local function Trim(text) return (tostring(text):gsub("^%s+", ""):gsub("%s+$", "")) end

local function Fill(tokens, text)
    local position = 0
    for token in (tostring(text) .. ","):gmatch("([^,]*),") do
        position = position + 1
        local key = tonumber(token) or Trim(token)
        tokens[key] = position
    end
end

local function UnitIndex(unit)
    return tonumber(unit:match("%d+") or -1)
end

function Sort.Order(header, roster)
    local get = function(key) return header:GetAttribute(key) end
    local nameList, groupFilter, roleFilter = get("nameList"), get("groupFilter"), get("roleFilter")
    local sortMethod, groupBy = get("sortMethod"), get("groupBy")
    local members = {}
    for _, member in ipairs(roster.members) do
        if roster.kind == "RAID" or member.unit ~= "player" or get("showPlayer") then members[#members + 1] = member end
    end
    local shown, names, grouping = {}, {}, {}
    if not groupFilter and not roleFilter and not nameList then groupFilter = "1,2,3,4,5,6,7,8" end
    if groupFilter or roleFilter then
        local tokens = {}
        if groupFilter then Fill(tokens, groupFilter) end
        if roleFilter then Fill(tokens, roleFilter) end
        for _, member in ipairs(members) do
            local subgroup = roster.kind == "RAID" and member.subgroup or 1
            if member.name and (tokens[subgroup] or tokens[member.class] or (member.role and tokens[member.role])
                or tokens[member.assignedRole]) then
                shown[#shown + 1] = member.unit
                names[member.unit] = member.name
                if groupBy == "GROUP" then grouping[member.unit] = subgroup
                elseif groupBy == "CLASS" then grouping[member.unit] = member.class
                elseif groupBy == "ROLE" then grouping[member.unit] = member.role
                elseif groupBy == "ASSIGNEDROLE" then grouping[member.unit] = member.assignedRole end
            end
        end
        if groupBy then
            local order = {}
            Fill(order, (get("groupingOrder") or ""):gsub("%s+", ""))
            local function Inner(a, b)
                if sortMethod == "NAME" then return names[a] < names[b] end
                return UnitIndex(a) < UnitIndex(b)
            end
            table.sort(shown, function(a, b)
                local orderA, orderB = order[grouping[a]], order[grouping[b]]
                if orderA then
                    if not orderB then return true end
                    if orderA == orderB then return Inner(a, b) end
                    return orderA < orderB
                end
                if orderB then return false end
                return Inner(a, b)
            end)
        elseif sortMethod == "NAME" then
            table.sort(shown, function(a, b) return names[a] < names[b] end)
        end
    else
        local order = {}
        Fill(order, nameList)
        for _, member in ipairs(members) do
            if member.name and order[member.name] then
                shown[#shown + 1] = member.unit
                names[member.unit] = member.name
            end
        end
        if sortMethod == "NAME" then
            table.sort(shown, function(a, b) return names[a] < names[b] end)
        elseif sortMethod == "NAMELIST" then
            table.sort(shown, function(a, b) return order[names[a]] < order[names[b]] end)
        end
    end
    local out = {}
    for i = 1, #shown do out[i] = names[shown[i]] end
    if (get("sortDir") or "ASC") == "DESC" then
        local reversed = {}
        for i = #out, 1, -1 do reversed[#reversed + 1] = out[i] end
        out = reversed
    end
    return table.concat(out, ",")
end

return Sort
