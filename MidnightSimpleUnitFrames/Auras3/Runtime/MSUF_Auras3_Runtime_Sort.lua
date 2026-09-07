-- Auras3 runtime: Sort.
-- Native sort normalization and signatures. Both compiler and renderer consume these functions; they never inspect restricted aura data.
-- The factory runs once at addon load; dependency bindings are local upvalues on live paths.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
MSUF.Auras3RuntimeFactories = MSUF.Auras3RuntimeFactories or {}
MSUF.Auras3RuntimeFactories.Sort = function(addonName, MSUF, A3, UF, ExportPublic, dependencies)
local tostring = tostring
local DEFAULT_SHARED = dependencies.Schema.DEFAULT_SHARED

local AuraSortEnums, AuraSortSignature, NormalizeAuraSortMethod

local AURA_SORT_METHOD_FIELDS = {
    DEFAULT = "Default",
    BIG_DEFENSIVE = "BigDefensive",
    UNIT_FRAME_DEBUFF = "UnitFrameDebuff",
    IMPORTANT_FIRST = "ImportantOnly",
    EXPIRATION = "Expiration",
    EXPIRATION_ONLY = "ExpirationOnly",
    NAME = "Name",
    NAME_ONLY = "NameOnly",
    INSTANCE_ID = "AuraInstanceIDOnly",
}

local AURA_SORT_METHOD_FALLBACKS = {
    DEFAULT = 0,
    BIG_DEFENSIVE = 1,
    UNIT_FRAME_DEBUFF = 2,
    IMPORTANT_FIRST = 3,
    EXPIRATION = 4,
    EXPIRATION_ONLY = 5,
    NAME = 6,
    NAME_ONLY = 7,
    INSTANCE_ID = 8,
}

NormalizeAuraSortMethod = function(value)
    value = tostring(value or DEFAULT_SHARED.sortMethod):upper():gsub("[%s%-]+", "_")
    if value == "BIGDEFENSIVE" then value = "BIG_DEFENSIVE" end
    if value == "UNITFRAMEDEBUFF" then value = "UNIT_FRAME_DEBUFF" end
    if value == "IMPORTANTONLY" or value == "IMPORTANT" then value = "IMPORTANT_FIRST" end
    if value == "EXPIRATIONONLY" then value = "EXPIRATION_ONLY" end
    if value == "NAMEONLY" then value = "NAME_ONLY" end
    -- PTR 7: aura-instance-ID-only sort (stable arrival order, no payload reads).
    if value == "INSTANCEID" or value == "AURA_INSTANCE_ID" or value == "AURAINSTANCEID"
        or value == "INSTANCE_ID_ONLY" or value == "ARRIVAL" then
        value = "INSTANCE_ID"
    end
    return AURA_SORT_METHOD_FIELDS[value] and value or DEFAULT_SHARED.sortMethod
end

AuraSortEnums = function(lane)
    local methodKey = NormalizeAuraSortMethod(lane and lane.sortMethod)
    local methodEnums = _G.AuraContainerSortMethod
    local directionEnums = _G.AuraContainerSortDirection
    local method = methodEnums and methodEnums[AURA_SORT_METHOD_FIELDS[methodKey]] or AURA_SORT_METHOD_FALLBACKS[methodKey]
    local reverse = lane and lane.sortReverse == true
    local direction = directionEnums and directionEnums[reverse and "Reverse" or "Normal"] or (reverse and 1 or 0)
    return method, direction
end

AuraSortSignature = function(lane)
    return NormalizeAuraSortMethod(lane and lane.sortMethod) .. ":" .. (lane and lane.sortReverse == true and "R" or "N")
end

return {
    AuraSortEnums = AuraSortEnums,
    AuraSortSignature = AuraSortSignature,
    NormalizeAuraSortMethod = NormalizeAuraSortMethod,
}
end
