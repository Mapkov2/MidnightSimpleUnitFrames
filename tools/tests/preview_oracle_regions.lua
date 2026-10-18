-- Deterministic native-region observations, shared by legacy and future scene adapters.
local Regions = {}

local function Keys(t)
    local keys = {}
    for key in pairs(t) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end
Regions.Keys = Keys

local function Encode(value)
    local kind = type(value)
    if kind == "number" then
        assert(value == value and math.abs(value) < math.huge, "non-finite region property")
        if value == 0 then return "0" end
        return string.format("%.12g", value)
    end
    if kind == "boolean" or kind == "nil" then return tostring(value) end
    if kind == "string" then
        return '"' .. value:gsub('[%z\1-\31\\"]', function(char)
            return string.format("\\%03d", char:byte())
        end) .. '"'
    end
    assert(kind == "table", "unsupported observation: " .. kind)
    local parts = {}
    for _, key in ipairs(Keys(value)) do
        parts[#parts + 1] = "[" .. Encode(key) .. "]=" .. Encode(value[key])
    end
    return "{" .. table.concat(parts, ",") .. "}"
end
Regions.Encode = Encode

function Regions.Install(world)
    local widgets, all = world.widgets, { world.widgets.UIParent }
    world.oracleRegions = all
    local create = widgets.Region
    function widgets:Region(kind, parent)
        local region = create(self, kind, parent)
        all[#all + 1] = region
        return region
    end
    -- These native portrait APIs otherwise resolve to opaque permissive stubs.
    -- Model the texture resource that SetPortraitTexture stamps, so a live snapshot copied with GetTexture/SetTexture
    -- retains its native portrait provenance. Each handle has one explicit source; no color/position inference.
    local portraitSources = {}
    local setTexture = widgets.Methods.SetTexture
    widgets.Methods.SetTexture = function(region, texture, ...)
        local result = setTexture(region, texture, ...)
        if world.oraclePortraitSnapshot then region.oraclePortrait = portraitSources[texture] end
        return result
    end
    world.env.SetPortraitTexture = function(region, unit, legacy)
        if not world.oraclePortraitSnapshot then
            region.oraclePortrait = { unit = unit, legacy = legacy == true }
            return
        end
        local handle = "native-portrait:" .. unit .. (legacy and ":legacy" or "")
        portraitSources[handle] = { unit = unit, legacy = legacy == true }
        region:SetTexture(handle)
    end
    world.env.SetPortraitTextureFromCreatureDisplayID = function(region, id)
        region.oraclePortrait = { displayID = id }
    end
    local methods = widgets.Methods
    for _, method in ipairs({ "SetModel", "SetUnit", "SetCamera", "SetFacing", "SetPortraitZoom", "SetPosition" }) do
        methods[method] = function(region, ...)
            region.oracleModel = region.oracleModel or {}
            region.oracleModel[method] = { ... }
        end
    end
    -- Native SetPoint replaces an anchor with the same point, rather than appending it.
    methods.SetPoint = function(region, point, relative, relativePoint, x, y)
        if type(relative) == "number" then
            x, y, relative, relativePoint = relative, relativePoint, region.parent, point
        elseif type(relative) == "string" then
            relative = assert(world.env[relative], "unknown named anchor " .. relative)
        end
        local entry = { point = point, relativeTo = relative or region.parent,
            relativePoint = relativePoint or point, x = x or 0, y = y or 0 }
        for index, old in ipairs(region.points) do
            if old.point == point then region.points[index] = entry return end
        end
        region.points[#region.points + 1] = entry
    end
    methods.SetAllPoints = function(region, relative)
        region:ClearAllPoints()
        region.allPoints = relative or region.parent
    end
end

local function Within(region, roots)
    local seen = {}
    while region do
        assert(not seen[region], "parent cycle")
        seen[region] = true
        if roots[region] then return true end
        region = rawget(region, "parent")
    end
    return false
end

local OMIT = { parent = true, children = true, regions = true, __env = true, scripts = true,
    events = true, attributes = true, points = true, masks = true, ctx = true, entry = true,
    MSUF = true, M = true, _catalogCtx = true, _msufPreviewScene = true, _msufGFRenderState = true,
    _msufGFSceneState = true, _msufGFHealthTextState = true, _msufCPPreviewAnim = true }

function Regions.OwnedField(key)
    return not OMIT[key] and not tostring(key):match("^_msuf2")
end

-- Prefer named fields, then local native-region ordinals. No global creation IDs or addresses.
local function NameFields(owner, path, selected, ids, seen, depth)
    if seen[owner] or depth > 3 then return end
    seen[owner] = true
    for _, key in ipairs(Keys(owner)) do
        local value = rawget(owner, key)
        if Regions.OwnedField(key) and type(value) == "table" then
            local role = path .. "/" .. tostring(key)
            if rawget(value, "objectType") then
                if not ids[value] then ids[value] = role end
            elseif getmetatable(value) == nil then
                NameFields(value, role, selected, ids, seen, depth + 1)
            end
        end
    end
end

local function Identity(world, roots, aliases)
    local selected, ids, rootSet = {}, {}, {}
    for _, role in ipairs(Keys(roots)) do
        local region = roots[role]
        assert(rawget(region, "objectType"), "root is not a native region: " .. role)
        assert(not ids[region], "two roots name the same region: " .. role .. " and " .. tostring(ids[region]))
        ids[region], rootSet[region] = role, true
    end
    for _, region in ipairs(world.oracleRegions) do
        if Within(region, rootSet) then selected[region] = true end
    end
    -- Native masks/fill textures may be shared outside the scene's parent tree.
    local pendingDependencies = true
    while pendingDependencies do
        pendingDependencies = false
        for region in pairs(selected) do
            local dependencies = {}
            for _, mask in ipairs(region.masks) do dependencies[#dependencies + 1] = mask end
            if region.statusBarTexture then dependencies[#dependencies + 1] = region.statusBarTexture end
            if type(region.mask) == "table" and rawget(region.mask, "objectType") then
                dependencies[#dependencies + 1] = region.mask
            end
            for _, dependency in ipairs(dependencies) do
                if not selected[dependency] then selected[dependency], pendingDependencies = true, true end
            end
        end
    end
    for role, region in pairs(aliases or {}) do
        assert(not ids[region] or ids[region] == role, "duplicate semantic role " .. role)
        ids[region] = role
    end
    ids[world.widgets.UIParent] = "UIParent"
    for _, role in ipairs(Keys(aliases or {})) do
        NameFields(aliases[role], role, selected, ids, {}, 0)
    end
    local pending = true
    while pending do
        pending = false
        local ordered, before = {}, 0
        for region, role in pairs(ids) do
            before = before + 1
            if selected[region] then ordered[#ordered + 1] = { region = region, role = role } end
        end
        table.sort(ordered, function(a, b) return a.role < b.role end)
        for _, entry in ipairs(ordered) do NameFields(entry.region, entry.role, selected, ids, {}, 0) end
        local after = 0
        for _ in pairs(ids) do after = after + 1 end
        pending = after > before
    end
    local ordinals = {}
    local function Name(region)
        if ids[region] then return ids[region] end
        local parent = rawget(region, "parent")
        local base = parent and Name(parent) or "external"
        local label = rawget(region, "frameName")
        if label then ids[region] = base .. "/" .. label return ids[region] end
        assert(selected[region], "unmapped external anchor below " .. base)
        local prefix = base .. "/@" .. region.objectType
        ordinals[prefix] = (ordinals[prefix] or 0) + 1
        ids[region] = prefix .. "[" .. ordinals[prefix] .. "]"
        return ids[region]
    end
    for _, region in ipairs(world.oracleRegions) do if selected[region] then Name(region) end end
    return selected, ids, Name
end

local FIELDS = {
    "width", "height", "shown", "alpha", "scale", "frameLevel", "frameStrata", "drawLayer", "drawSublevel",
    "ignoreParentAlpha", "ignoreParentScale", "clipsChildren", "minimum", "maximum", "value", "color",
    "statusBarTexturePath", "orientation", "reverseFill", "fillStyle", "rotatesTexture", "texture", "atlas",
    "colorTexture", "vertexColor", "texCoord", "blendMode", "desaturated", "desaturation", "rotation", "gradient",
    "gradientAlpha", "mask", "horizTile", "vertTile", "snapToPixelGrid", "texelSnappingBias", "text", "textColor",
    "fontPath", "fontSize", "fontFlags", "fontObject", "justifyH", "justifyV", "shadowColor", "shadowOffset", "spacing",
    "wordWrap", "nonSpaceWrap", "maxLines", "backdrop", "backdropColor", "backdropBorderColor",
    "cooldownStart", "cooldownDuration", "drawEdge", "drawSwipe", "swipeColor", "swipeTexture", "reverse",
    "hideCountdownNumbers", "countdownFont", "circularEdge", "oraclePortrait", "oracleModel",
}

local PROPERTY_KINDS = {}
local function NativeFields(fields, kinds)
    for field in fields:gmatch("%S+") do PROPERTY_KINDS[field] = kinds end
end
local TEXTURES = { Texture = true, MaskTexture = true }
NativeFields("texture atlas colorTexture vertexColor texCoord blendMode desaturated desaturation rotation gradient gradientAlpha", TEXTURES)
NativeFields("mask horizTile vertTile snapToPixelGrid texelSnappingBias oraclePortrait", TEXTURES)
NativeFields("minimum maximum value color statusBarTexturePath orientation reverseFill fillStyle rotatesTexture", { StatusBar = true })
NativeFields("text textColor fontPath fontSize fontFlags fontObject justifyH justifyV shadowColor shadowOffset spacing", { FontString = true })
NativeFields("wordWrap nonSpaceWrap maxLines", { FontString = true })
NativeFields("cooldownStart cooldownDuration drawEdge drawSwipe swipeColor swipeTexture reverse hideCountdownNumbers countdownFont circularEdge",
    { Cooldown = true })
NativeFields("oracleModel", { Model = true, PlayerModel = true, DressUpModel = true })

local function NativeProperty(region, field)
    if field == "text" and (region.objectType == "Button" or region.objectType == "EditBox") then
        return type(rawget(region, field)) == "string"
    end
    local kinds = PROPERTY_KINDS[field]
    return not kinds or kinds[region.objectType] == true
end

local function Plain(value, reference, seen, path)
    if type(value) ~= "table" then return value end
    if rawget(value, "objectType") then return reference(value) end
    assert(getmetatable(value) == nil, "unmodelled native property table " .. path)
    assert(not seen[value], "property cycle")
    seen[value] = true
    local out = {}
    for key, child in pairs(value) do
        if type(child) ~= "function" then out[key] = Plain(child, reference, seen, path .. "/" .. tostring(key)) end
    end
    seen[value] = nil
    return out
end

local function Inherited(region)
    local shown, alpha, scale, inheritAlpha, inheritScale = true, 1, 1, true, true
    while region do
        shown = shown and region.shown ~= false
        if inheritAlpha then alpha = alpha * (region.alpha or 1) end
        if inheritScale then scale = scale * (region.scale or 1) end
        if region.ignoreParentAlpha then inheritAlpha = false end
        if region.ignoreParentScale then inheritScale = false end
        region = region.parent
    end
    return shown, alpha, scale
end

function Regions.Capture(world, roots, aliases)
    local selected, ids, reference = Identity(world, roots, aliases)
    local output, objects = {}, {}
    for _, region in ipairs(world.oracleRegions) do
        if selected[region] then
            local role = ids[region]
            assert(not output[role], "ambiguous semantic role " .. role)
            local props = { kind = region.objectType, parent = region.parent and reference(region.parent) }
            for _, field in ipairs(FIELDS) do
                local value = rawget(region, field)
                if value ~= nil and NativeProperty(region, field) then
                    if type(value) == "table" then
                        assert(rawget(value, "objectType") or getmetatable(value) == nil,
                            "unmodelled native property " .. role .. "/" .. field)
                    end
                    props[field] = Plain(value, reference, {}, role .. "/" .. field)
                end
            end
            props.effectiveShown, props.effectiveAlpha, props.effectiveScale = Inherited(region)
            props.points = {}
            for _, point in ipairs(region.points) do
                props.points[point.point] = { relative = reference(point.relativeTo), point = point.relativePoint, x = point.x, y = point.y }
            end
            if region.allPoints then props.allPoints = reference(region.allPoints) end
            props.masks = {}
            for index, mask in ipairs(region.masks) do props.masks[index] = reference(mask) end
            if region.statusBarTexture then props.statusTexture = reference(region.statusBarTexture) end
            output[role], objects[role] = props, region
        end
    end
    assert(next(output), "renderer produced no captured regions")
    return output, objects
end

local function Compare(expected, actual, path, diffs)
    if type(expected) ~= "table" or type(actual) ~= "table" then
        if Encode(expected) ~= Encode(actual) then
            diffs[#diffs + 1] = path .. ": expected " .. Encode(expected) .. ", actual " .. Encode(actual)
        end
        return
    end
    local union = {}
    for key in pairs(expected) do union[key] = true end
    for key in pairs(actual) do union[key] = true end
    for _, key in ipairs(Keys(union)) do Compare(expected[key], actual[key], path .. "/" .. tostring(key), diffs) end
end

function Regions.Compare(expected, actual)
    local diffs = {}
    Compare(expected, actual, "", diffs)
    return diffs
end

function Regions.Write(path, value)
    assert(io.open(path, "rb") == nil, "refusing to overwrite frozen fixture " .. path)
    local file = assert(io.open(path, "wb"))
    file:write("return {\r\n")
    for _, key in ipairs(Keys(value)) do
        if key == "regions" then
            file:write('["regions"]={\r\n')
            for _, role in ipairs(Keys(value.regions)) do
                file:write("[", Encode(role), "]=", Encode(value.regions[role]), ",\r\n")
            end
            file:write("},\r\n")
        else
            file:write("[", Encode(key), "]=", Encode(value[key]), ",\r\n")
        end
    end
    file:write("}\r\n")
    file:close()
end

return Regions
