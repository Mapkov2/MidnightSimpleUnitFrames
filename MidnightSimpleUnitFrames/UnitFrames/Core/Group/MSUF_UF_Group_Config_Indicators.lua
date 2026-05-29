local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF_NS = MSUF
_G.MSUF = MSUF

local GF = MSUF.GF or {}
MSUF.GF = GF

local tonumber = tonumber
local tostring = tostring
local type = type
local pairs = pairs
local ipairs = ipairs
local next = next
local floor = math.floor
local sort = table.sort

local EMPTY = {}

local function AuraBackendEnabled()
    local a3 = MSUF and (MSUF.MSUF_Auras3 or _G.MSUF_Auras3)
    return a3 and type(a3.BackendEnabled) == "function" and a3.BackendEnabled() == true
end

local function Num(value, fallback)
    value = tonumber(value)
    if value == nil then return fallback end
    return value
end

local function Alpha(value, fallback)
    value = Num(value, fallback)
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

local function Layer(value, fallback)
    value = floor((tonumber(value) or fallback or 7) + 0.5)
    if value < 0 then return 0 end
    if value > 30 then return 30 end
    return value
end

local function AddSpellID(map, value)
    local id = tonumber(value)
    if id and id > 0 then map[id] = true end
end

local function AddName(map, value)
    if type(value) == "string" and value ~= "" and not tonumber(value) then
        map[value] = true
    end
end

local function CompileSpellIDList(value)
    local ids
    local function ensure()
        ids = ids or {}
        return ids
    end
    if type(value) == "number" then
        AddSpellID(ensure(), value)
    elseif type(value) == "string" then
        for token in value:gmatch("%d+") do AddSpellID(ensure(), token) end
    elseif type(value) == "table" then
        for _, v in pairs(value) do AddSpellID(ensure(), v) end
    end
    return ids and next(ids) and ids or nil
end

local function MergeSpellIDs(dst, src)
    if not src then return dst end
    dst = dst or {}
    for id in pairs(src) do dst[id] = true end
    return dst
end

local function MergeNames(dst, src)
    if not src then return dst end
    dst = dst or {}
    for name in pairs(src) do dst[name] = true end
    return dst
end

local function TrackInfo(registry, specKey, auraKey)
    local list = registry and registry.TrackableAuras and registry.TrackableAuras[specKey]
    if type(list) ~= "table" then return nil end
    for i = 1, #list do
        local info = list[i]
        if info and info.name == auraKey then return info, i end
    end
    return nil
end

local function TrackOrder(registry, specKey)
    local order = {}
    local list = registry and registry.TrackableAuras and registry.TrackableAuras[specKey]
    if type(list) == "table" then
        for i = 1, #list do
            local name = list[i] and list[i].name
            if name then order[name] = i end
        end
    end
    return order
end

local function AddRegistrySpellIDs(ids, registry, specKey, auraKey, entry)
    ids = MergeSpellIDs(ids, CompileSpellIDList(auraKey))
    if type(entry) == "table" then
        ids = MergeSpellIDs(ids, CompileSpellIDList(entry.spellID or entry.spellId or entry.id or entry.spells))
    end

    local bySpec = registry and registry.SpellIDs and registry.SpellIDs[specKey]
    if bySpec and bySpec[auraKey] then
        ids = ids or {}
        AddSpellID(ids, bySpec[auraKey])
    end

    local alt = registry and registry.AltSpellIDs and registry.AltSpellIDs[specKey]
    if type(alt) == "table" then
        for spellID, name in pairs(alt) do
            if name == auraKey then
                ids = ids or {}
                AddSpellID(ids, spellID)
            end
        end
    end

    local secret = registry and registry.SecretSpellIDs and registry.SecretSpellIDs[specKey]
    if type(secret) == "table" then
        if secret[auraKey] then
            ids = ids or {}
            AddSpellID(ids, secret[auraKey])
        end
    end

    local selfOnly = registry and registry.SelfOnlySpellIDs and registry.SelfOnlySpellIDs[specKey]
    if type(selfOnly) == "table" then
        for spellID, name in pairs(selfOnly) do
            if name == auraKey then
                ids = ids or {}
                AddSpellID(ids, spellID)
            end
        end
    end

    local linked = registry and registry.LinkedAuraRules and registry.LinkedAuraRules[specKey]
    local rule = type(linked) == "table" and linked[auraKey] or nil
    if type(rule) == "table" then
        ids = ids or {}
        AddSpellID(ids, rule.sourceSpellID)
        ids = MergeSpellIDs(ids, CompileSpellIDList(rule.targetSpellIDs))
    end

    return ids and next(ids) and ids or nil
end

local function CompileAuraNames(registry, specKey, auraKey)
    local names = {}
    AddName(names, auraKey)
    local info = TrackInfo(registry, specKey, auraKey)
    if info then AddName(names, info.display) end
    if registry and type(registry.BuildNameLookup) == "function" then
        local lookup = registry.BuildNameLookup(specKey)
        if type(lookup) == "table" then
            for localizedName, key in pairs(lookup) do
                if key == auraKey then AddName(names, localizedName) end
            end
        end
    end
    return next(names) and names or nil
end

local function AuraColor(registry, specKey, auraKey, frameCfg)
    local c = frameCfg and frameCfg.color
    if type(c) == "table" then
        return Num(c[1] or c.r, 1), Num(c[2] or c.g, 1), Num(c[3] or c.b, 1), Alpha(c[4] or c.a, Num(frameCfg.alpha, 1))
    end
    local info = TrackInfo(registry, specKey, auraKey)
    c = info and info.color
    if type(c) == "table" then
        return Num(c[1] or c.r, 0.5), Num(c[2] or c.g, 0.8), Num(c[3] or c.b, 0.5), Alpha(c[4] or c.a, 1)
    end
    return 0.5, 0.8, 0.5, 1
end

local CI_SLOT_FIELDS = {
    { key = "TL", anchor = "TOPLEFT", x = 2, y = -2 },
    { key = "TR", anchor = "TOPRIGHT", x = -2, y = -2 },
    { key = "BL", anchor = "BOTTOMLEFT", x = 2, y = 2 },
    { key = "BR", anchor = "BOTTOMRIGHT", x = -2, y = 2 },
    { key = "C", anchor = "CENTER", x = 0, y = 0 },
}

function GF.CompileCornerIndicators(conf)
    conf = conf or {}
    local slots, slotMap = {}, {}
    local hasWork, needsAura, needsThreat = false, false, false
    local auraBackend = AuraBackendEnabled()
    for i = 1, #CI_SLOT_FIELDS do
        local field = CI_SLOT_FIELDS[i]
        local slotKey = field.key
        local category = conf["ciSlot" .. slotKey] or "none"
        local custom = conf["ciCustom" .. slotKey]
        if not auraBackend and (category == "dispel" or category == "custom") then
            category = "none"
        end
        local ids
        if type(custom) == "table" then
            ids = MergeSpellIDs(ids, CompileSpellIDList(custom.spells))
            ids = MergeSpellIDs(ids, CompileSpellIDList(custom.spellID or custom.spellId or custom.id))
        end
        local slot = {
            key = slotKey,
            category = category,
            anchor = field.anchor,
            x = field.x,
            y = field.y,
            ids = ids,
            names = nil,
            filter = type(custom) == "table" and (custom.filter or "HELPFUL|PLAYER") or "HELPFUL|PLAYER",
            mode = type(custom) == "table" and (custom.mode or "present") or "present",
            r = type(custom) == "table" and Num(custom.r, 0.4) or 0.4,
            g = type(custom) == "table" and Num(custom.g, 1) or 1,
            b = type(custom) == "table" and Num(custom.b, 0.4) or 0.4,
        }
        if category ~= "none" then
            hasWork = true
            if category == "dispel" or category == "custom" then needsAura = true end
            if category == "aggro" then needsThreat = true end
        end
        slots[#slots + 1] = slot
        slotMap[slotKey] = slot
    end
    return {
        enabled = conf.ciEnabled ~= false,
        hasWork = hasWork,
        needsAura = needsAura,
        needsThreat = needsThreat,
        size = Num(conf.ciSize, 8),
        alpha = Alpha(conf.ciAlpha, 1),
        layer = Layer(conf.ciLayer, 7),
        slots = slots,
        slotMap = slotMap,
        aggroR = Num(conf.ciAggroColorR, 1),
        aggroG = Num(conf.ciAggroColorG, 0.55),
        aggroB = Num(conf.ciAggroColorB, 0),
    }
end

local function RuntimeSpecKey(si, registry)
    if not (type(si) == "table" and si.enabled == true and registry) then return nil end
    local selected = si.spec or "auto"
    local playerSpec = registry.GetPlayerSpec and registry.GetPlayerSpec() or nil
    if selected == "auto" then
        return playerSpec
    elseif selected == "multi" then
        local enabled = type(si.multiSpecs) == "table" and playerSpec and si.multiSpecs[playerSpec] == true
        return enabled and playerSpec or nil
    end
    if playerSpec and selected ~= playerSpec then return nil end
    return selected
end

local function CompileFrameEffect(frameCfg, registry, specKey, auraKey)
    if type(frameCfg) ~= "table" or frameCfg.type == nil or frameCfg.type == "none" then return nil end
    local r, g, b, a = AuraColor(registry, specKey, auraKey, frameCfg)
    return {
        type = frameCfg.type,
        priority = floor(Num(frameCfg.priority, 5) + 0.5),
        r = r,
        g = g,
        b = b,
        a = Alpha(frameCfg.alpha or a, a),
        thickness = floor(Num(frameCfg.thickness, 2) + 0.5),
    }
end

local function CompilePlaced(placed)
    if type(placed) ~= "table" or placed.type == nil or placed.type == "none" then return nil end
    return {
        type = placed.type or "icon",
        anchor = placed.anchor or "TOPLEFT",
        x = floor(Num(placed.x, 0) + 0.5),
        y = floor(Num(placed.y, 0) + 0.5),
        size = floor(Num(placed.size, 18) + 0.5),
        barWidth = floor(Num(placed.barWidth, 42) + 0.5),
        growth = placed.growth or "RIGHTDOWN",
        missing = placed.missing == true,
        showCooldownSwipe = placed.showCooldownSwipe ~= false,
        showCooldown = placed.showCooldown ~= false,
        cooldownSize = floor(Num(placed.cooldownSize, 8) + 0.5),
    }
end

function GF.CompileSpellIndicators(conf)
    conf = conf or {}
    local si = conf.spellIndicators
    local registry = GF.SpellIndicators
    local out = {
        enabled = type(si) == "table" and si.enabled == true,
        layer = type(si) == "table" and Layer(si.layer, 9) or 9,
        spec = type(si) == "table" and (si.spec or "auto") or "auto",
        activeSpec = nil,
        items = {},
        watched = nil,
        hasMissing = false,
        hasEffects = false,
    }
    if not out.enabled or not (registry and type(si.specs) == "table") then
        return out
    end
    if not AuraBackendEnabled() then
        out.enabled = false
        return out
    end

    local specKey = RuntimeSpecKey(si, registry)
    out.activeSpec = specKey
    if not specKey then return out end
    if type(registry.EnsureSpecConfig) == "function" then
        registry.EnsureSpecConfig(si, specKey)
    end

    local specCfg = si.specs and si.specs[specKey]
    if type(specCfg) ~= "table" then return out end
    local order = TrackOrder(registry, specKey)
    local keys = {}
    for auraKey in pairs(specCfg) do keys[#keys + 1] = auraKey end
    sort(keys, function(a, b)
        local oa, ob = order[a] or 9999, order[b] or 9999
        if oa == ob then return tostring(a) < tostring(b) end
        return oa < ob
    end)

    for i = 1, #keys do
        local auraKey = keys[i]
        local entry = specCfg[auraKey]
        if type(entry) == "table" and entry.enabled ~= false then
            local placed = CompilePlaced(entry.placed)
            local effect = CompileFrameEffect(entry.frame, registry, specKey, auraKey)
            if placed or effect then
                local ids = AddRegistrySpellIDs(nil, registry, specKey, auraKey, entry)
                local names = CompileAuraNames(registry, specKey, auraKey)
                if ids or names then
                    out.watched = out.watched or {}
                    out.watched.ids = MergeSpellIDs(out.watched.ids, ids)
                    out.watched.names = MergeNames(out.watched.names, names)
                    local r, g, b, a = AuraColor(registry, specKey, auraKey, entry.frame)
                    out.items[#out.items + 1] = {
                        key = tostring(auraKey),
                        ids = ids,
                        names = names,
                        filter = entry.filter or (placed and placed.filter) or "HELPFUL",
                        onlyOwn = entry.onlyOwn ~= false,
                        placed = placed,
                        effect = effect,
                        icon = registry.GetAuraIcon and registry.GetAuraIcon(specKey, auraKey) or 136243,
                        r = r, g = g, b = b, a = a,
                    }
                    if effect then out.hasEffects = true end
                    if placed and placed.missing == true then out.hasMissing = true end
                end
            end
        end
    end
    return out
end
