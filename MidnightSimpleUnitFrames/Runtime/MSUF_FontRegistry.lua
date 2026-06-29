--- Runtime/MSUF_FontRegistry.lua
--- Font catalogue, LibSharedMedia font registration bridge, and font/color
--- resolver globals.
---
--- This file owns font key normalization and default/bundled font discovery.
--- Runtime font application lives in MSUF_FontRuntime.lua.

local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local G = _G
local type, tostring, ipairs = type, tostring, ipairs
local table_insert = table.insert
local string_lower = string.lower

local LSM = (MSUF and MSUF.LSM) or G.MSUF_LSM or (LibStub and LibStub("LibSharedMedia-3.0", true))

--- Called by the LSM bootstrap when LibSharedMedia becomes available after this
--- file loaded. Keep the local LSM reference fresh for later lookups.
G.MSUF_OnLSMReady = function(lsm)
    LSM = lsm
end

local deferredFontsPending = false
local function DeferredUpdateAllFonts()
    deferredFontsPending = false
    if G.MSUF_UpdateAllFonts then G.MSUF_UpdateAllFonts() end
end

if LSM and not G.MSUF_LSM_CallbacksRegistered and not G.MSUF_LSM_FontCallbackRegistered then
    G.MSUF_LSM_FontCallbackRegistered = true
    LSM:RegisterCallback("LibSharedMedia_Registered", function(_, mediatype, key)
        if mediatype ~= "font" then return end
        if type(G.MSUF_ClearResolvedFontPathCache) == "function" then
            G.MSUF_ClearResolvedFontPathCache()
        end
        if G.MSUF_RebuildFontChoices then
            G.MSUF_RebuildFontChoices()
        end
        local g = G.MSUF_DB and G.MSUF_DB.general
        local normalizeFontKey = G.MSUF_NormalizeFontKey or function(k) return k end
        local registeredKey = normalizeFontKey(key)
        local needsFontRefresh = g and normalizeFontKey(g.fontKey) == registeredKey
        if needsFontRefresh and not deferredFontsPending then
            deferredFontsPending = true
            if G.MSUF_ScheduleOnce then
                G.MSUF_ScheduleOnce("UF_FONTS_DEFERRED_UPDATE", DeferredUpdateAllFonts)
            else
                C_Timer.After(0, DeferredUpdateAllFonts)
            end
        end
    end)
end

local FONT_LIST = {
    {
        key  = "FRIZQT",
        name = "Friz Quadrata (default)",
        path = "Fonts\\FRIZQT___CYR.TTF",
    },
    {
        key  = "ARIALN",
        name = "Arial (default)",
        path = "Fonts\\ARHei.TTF",
    },
    {
        key  = "MORPHEUS",
        name = "Morpheus (default)",
        path = "Fonts\\MORPHEUS_CYR.TTF",
    },
    {
        key  = "SKURRI",
        name = "Skurri (default)",
        path = "Fonts\\SKURRI_CYR.TTF",
    },
}

do
    local base = "Interface\\AddOns\\" .. tostring(addonName) .. "\\Media\\Fonts\\"
    local bundled = {
        { key = "EXPRESSWAY",                 name = "Expressway Regular (MSUF)",         file = "Expressway Regular.ttf" },
        { key = "EXPRESSWAY_BOLD",            name = "Expressway Bold (MSUF)",            file = "Expressway Bold.ttf" },
        { key = "EXPRESSWAY_SEMIBOLD",        name = "Expressway SemiBold (MSUF)",        file = "Expressway SemiBold.ttf" },
        { key = "EXPRESSWAY_EXTRABOLD",       name = "Expressway ExtraBold (MSUF)",       file = "Expressway ExtraBold.ttf" },
        { key = "EXPRESSWAY_CONDENSED_LIGHT", name = "Expressway Condensed Light (MSUF)", file = "Expressway Condensed Light.otf" },
    }

    local function HasFontKey(list, key)
        if type(key) ~= "string" or key == "" then return false end
        if not list then return false end
        for i = 1, #list do
            local t = list[i]
            if t and t.key == key then
                return true
            end
        end
        return false
    end

    for _, info in ipairs(bundled) do
        if not HasFontKey(FONT_LIST, info.key) then
            table_insert(FONT_LIST, {
                key  = info.key,
                name = info.name,
                path = base .. info.file,
            })
        end
    end
end

G.MSUF_FONT_LIST = G.MSUF_FONT_LIST or FONT_LIST

local MSUF_FontPathProbe
local MSUF_FontPathLoadableCache = {}

local function MSUF_NormalizeFontPathForProbe(path)
    if type(path) ~= "string" or path == "" then return nil end
    return path:gsub("/", "\\")
end

local function MSUF_FontPathIsLoadable(path, size, flags)
    path = MSUF_NormalizeFontPathForProbe(path)
    if not path then return false end
    size = tonumber(size) or 14
    if size <= 0 then size = 14 end
    flags = flags or ""

    local cacheKey = path:lower() .. "|" .. tostring(size) .. "|" .. tostring(flags)
    local cached = MSUF_FontPathLoadableCache[cacheKey]
    if cached ~= nil then return cached end

    if type(G.CreateFont) ~= "function" then
        return true
    end
    if not MSUF_FontPathProbe then
        local ok, probe = pcall(G.CreateFont, "MSUF_FontPathProbe")
        if ok then
            MSUF_FontPathProbe = probe
        end
    end
    if not (MSUF_FontPathProbe and type(MSUF_FontPathProbe.SetFont) == "function") then
        return true
    end

    local ok, applied = pcall(MSUF_FontPathProbe.SetFont, MSUF_FontPathProbe, path, size, flags)
    local loadable = ok and applied ~= false
    MSUF_FontPathLoadableCache[cacheKey] = loadable
    return loadable
end

G.MSUF_FontPathIsLoadable = MSUF_FontPathIsLoadable
MSUF.MSUF_FontPathIsLoadable = MSUF_FontPathIsLoadable

local MSUF_INTERNAL_LSM_FONT_KEYS = {
    ["Friz Quadrata TT"] = "FRIZQT",
    ["Arial Narrow"] = "ARIALN",
    ["Morpheus"] = "MORPHEUS",
    ["Skurri"] = "SKURRI",
    ["Friz Quadrata (default)"] = "FRIZQT",
    ["Arial (default)"] = "ARIALN",
    ["Morpheus (default)"] = "MORPHEUS",
    ["Skurri (default)"] = "SKURRI",
    ["Expressway Regular (MSUF)"] = "EXPRESSWAY",
    ["Expressway (MSUF)"] = "EXPRESSWAY",
    ["Expressway Bold (MSUF)"] = "EXPRESSWAY_BOLD",
    ["Expressway SemiBold (MSUF)"] = "EXPRESSWAY_SEMIBOLD",
    ["Expressway ExtraBold (MSUF)"] = "EXPRESSWAY_EXTRABOLD",
    ["Expressway Condensed Light (MSUF)"] = "EXPRESSWAY_CONDENSED_LIGHT",
}

local function MSUF_NormalizeFontKey(key)
    if type(key) ~= "string" or key == "" then return key end
    return MSUF_INTERNAL_LSM_FONT_KEYS[key] or key
end
G.MSUF_NormalizeFontKey = MSUF_NormalizeFontKey
MSUF.MSUF_NormalizeFontKey = MSUF_NormalizeFontKey

local function MSUF_NormalizeFontKeyField(tbl)
    if type(tbl) ~= "table" then return end
    local normalized = MSUF_NormalizeFontKey(tbl.fontKey)
    local resolveKeyPath = G.MSUF_ResolveFontKeyPath
    if type(resolveKeyPath) == "function" then
        local resolved = resolveKeyPath(normalized)
        if type(resolved) == "string" and resolved ~= "" then
            normalized = resolved
        end
    end
    if normalized ~= tbl.fontKey then
        tbl.fontKey = normalized
    end
end

--- Profile migration: old per-scope font keys now collapse to the global font
--- setting. This keeps imports/older profiles from carrying stale overrides.
local function MSUF_NormalizeStoredFontKeys()
    local db = G.MSUF_DB
    if type(db) ~= "table" then return end
    MSUF_NormalizeFontKeyField(db.general)
    for _, key in ipairs({
        "player", "target", "targettarget", "focustarget", "focus", "pet", "boss",
        "gf_party", "gf_raid", "gf_mythicraid",
    }) do
        if type(db[key]) == "table" then
            db[key].fontKey = nil
        end
    end
end
G.MSUF_NormalizeStoredFontKeys = MSUF_NormalizeStoredFontKeys
MSUF.MSUF_NormalizeStoredFontKeys = MSUF_NormalizeStoredFontKeys
MSUF_NormalizeStoredFontKeys()

local MSUF_FONT_COLORS = {
    white     = { 1.0, 1.0, 1.0 },
    black     = { 0.0, 0.0, 0.0 },
    red       = { 1.0, 0.0, 0.0 },
    green     = { 0.0, 1.0, 0.0 },
    blue      = { 0.0, 0.0, 1.0 },
    yellow    = { 1.0, 1.0, 0.0 },
    cyan      = { 0.0, 1.0, 1.0 },
    magenta   = { 1.0, 0.0, 1.0 },
    orange    = { 1.0, 0.5, 0.0 },
    purple    = { 0.6, 0.0, 0.8 },
    pink      = { 1.0, 0.6, 0.8 },
    turquoise = { 0.0, 0.9, 0.8 },
    grey      = { 0.5, 0.5, 0.5 },
    brown     = { 0.6, 0.3, 0.1 },
    gold      = { 1.0, 0.85, 0.1 },
}
MSUF.MSUF_FONT_COLORS = MSUF_FONT_COLORS
G.MSUF_FONT_COLORS = G.MSUF_FONT_COLORS or MSUF_FONT_COLORS

G.MSUF_GetNPCReactionColor = function(kind)
    local defaultR, defaultG, defaultB
    if kind == "friendly" then
        defaultR, defaultG, defaultB = 0, 1, 0
    elseif kind == "neutral" then
        defaultR, defaultG, defaultB = 1, 1, 0
    elseif kind == "enemy" then
        defaultR, defaultG, defaultB = 0.85, 0.10, 0.10
    elseif kind == "dead" then
        defaultR, defaultG, defaultB = 0.4, 0.4, 0.4
    else
        defaultR, defaultG, defaultB = 1, 1, 1
    end
    if not G.MSUF_EnsureDB then
        return defaultR, defaultG, defaultB
    end
    if not G.MSUF_DB then G.MSUF_EnsureDB() end
    G.MSUF_DB.npcColors = G.MSUF_DB.npcColors or {}
    local t = G.MSUF_DB.npcColors[kind]
    if t and t.r and t.g and t.b then
        return t.r, t.g, t.b
    end
    return defaultR, defaultG, defaultB
end

G.MSUF_GetClassBarColor = function(classToken)
    local defaultR, defaultG, defaultB = 0, 1, 0
    if not classToken then
        return defaultR, defaultG, defaultB
    end
    if not G.MSUF_DB then G.MSUF_EnsureDB() end
    G.MSUF_DB.classColors = G.MSUF_DB.classColors or {}
    local override = G.MSUF_DB.classColors[classToken]
    if override and override.r and override.g and override.b then
        return override.r, override.g, override.b
    end
    if type(override) == "string" and MSUF_FONT_COLORS and MSUF_FONT_COLORS[override] then
        local c = MSUF_FONT_COLORS[override]
        return c[1], c[2], c[3]
    end
    local color = G.RAID_CLASS_COLORS and G.RAID_CLASS_COLORS[classToken]
    if color then
        return color.r, color.g, color.b
    end
    return defaultR, defaultG, defaultB
end

local function MSUF_GetPowerBarColor(powerType, powerToken)
    if not powerToken or powerToken == "" then
        return nil
    end
    if not G.MSUF_EnsureDB then
        return nil
    end
    if not G.MSUF_DB then G.MSUF_EnsureDB() end
    local g = G.MSUF_DB.general
    local ov = g and g.powerColorOverrides
    local c = ov and ov[powerToken] or nil
    if type(c) ~= "table" and G.MSUF_AugEvokerActive and powerToken == "ESSENCE" then
        local cpOv = g and g.classPowerColorOverrides
        c = cpOv and cpOv[powerToken] or nil
    end
    if type(c) ~= "table" then
        return nil
    end
    local r, gg, b
    if type(c.r) == "number" and type(c.g) == "number" and type(c.b) == "number" then
        r, gg, b = c.r, c.g, c.b
    else
        r, gg, b = c[1], c[2], c[3]
    end
    if type(r) == "number" and type(gg) == "number" and type(b) == "number" then
        return r, gg, b
    end
    return nil
end
G.MSUF_GetPowerBarColor = MSUF_GetPowerBarColor

local function MSUF_GetResolvedPowerColor(powerType, powerToken)
    if type(MSUF_GetPowerBarColor) == "function" then
        local r, g, b = MSUF_GetPowerBarColor(powerType, powerToken)
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return r, g, b
        end
    end

    local snap = MSUF._PBCSnap
    if type(snap) == "table" then
        if type(powerToken) == "string" and snap[powerToken] then
            local c = snap[powerToken]
            return c.r, c.g, c.b
        end
        if type(powerType) == "number" and snap[powerType] then
            local c = snap[powerType]
            return c.r, c.g, c.b
        end
    end

    local pbc = G.PowerBarColor
    if type(powerToken) == "string" and pbc and pbc[powerToken] then
        local c = pbc[powerToken]
        local r = c.r or c[1]
        local g = c.g or c[2]
        local b = c.b or c[3]
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return r, g, b
        end
    end
    if type(powerType) == "number" and pbc and pbc[powerType] then
        local c = pbc[powerType]
        local r = c.r or c[1]
        local g = c.g or c[2]
        local b = c.b or c[3]
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return r, g, b
        end
    end
    return nil
end
G.MSUF_GetResolvedPowerColor = MSUF_GetResolvedPowerColor
MSUF.MSUF_GetResolvedPowerColor = MSUF_GetResolvedPowerColor

local function MSUF_GetConfiguredFontColor()
    if not G.MSUF_DB then G.MSUF_EnsureDB() end
    local g = G.MSUF_DB.general or {}
    if g.useCustomFontColor and g.fontColorCustomR and g.fontColorCustomG and g.fontColorCustomB then
        return g.fontColorCustomR, g.fontColorCustomG, g.fontColorCustomB
    end
    local key = (g.fontColor or "white"):lower()
    local color = MSUF_FONT_COLORS[key] or MSUF_FONT_COLORS.white
    return color[1], color[2], color[3]
end
G.MSUF_GetConfiguredFontColor = MSUF_GetConfiguredFontColor
MSUF.MSUF_GetConfiguredFontColor = MSUF_GetConfiguredFontColor

local MSUF_FontPreviewObjects = {}
local MSUF_FontPreviewObjectCount = 0

local function MSUF_GetRawLSMFontPath(lsm, key)
    if type(key) ~= "string" or key == "" then return nil end
    if lsm and type(lsm.HashTable) == "function" then
        local fonts = lsm:HashTable("font")
        local p = fonts and fonts[key]
        if type(p) == "string" and p ~= "" then return p end
    end
    return nil
end

local function MSUF_FontKeyIsInternal(key)
    if type(key) ~= "string" or key == "" then return false end
    local normalized = MSUF_NormalizeFontKey(key)
    for _, info in ipairs(FONT_LIST) do
        if info.key == key or info.key == normalized or info.name == key then
            return true
        end
    end
    return false
end

local function MSUF_FetchFontPathFromLSM(key)
    if type(key) ~= "string" or key == "" then return nil end
    if MSUF_FontKeyIsInternal(key) then return nil end
    local lsm = LSM or (MSUF and MSUF.LSM) or G.MSUF_LSM
    if not lsm then return nil end

    local lsmKey = MSUF_NormalizeFontKey(key)
    local p = MSUF_GetRawLSMFontPath(lsm, lsmKey)
    if type(p) == "string" and p ~= "" then return p end
    if lsmKey ~= key then
        p = MSUF_GetRawLSMFontPath(lsm, key)
        if type(p) == "string" and p ~= "" then return p end
    end

    if type(lsm.Fetch) == "function" then
        p = lsm:Fetch("font", lsmKey, true)
        if type(p) == "string" and p ~= "" then return p end
        if lsmKey ~= key then
            p = lsm:Fetch("font", key, true)
            if type(p) == "string" and p ~= "" then return p end
        end
    end

    return nil
end

local function MSUF_ResolveSafeFontPath(path, size, flags, fontKey)
    size = tonumber(size) or 14
    if size <= 0 then size = 14 end
    flags = flags or ""

    local resolve = G.MSUF_ResolveFontPath
    local function TryPath(candidate, candidateKey)
        if type(candidate) ~= "string" or candidate == "" then return nil end
        local resolved = type(resolve) == "function" and resolve(candidate, size, flags, candidateKey or fontKey) or candidate
        if type(resolved) == "string" and resolved ~= "" then
            if MSUF_FontPathIsLoadable(resolved, size, flags) or (flags ~= "" and MSUF_FontPathIsLoadable(resolved, size, "")) then
                return resolved
            end
        end
        return nil
    end

    local internal = type(G.MSUF_GetInternalFontPathByKey) == "function" and G.MSUF_GetInternalFontPathByKey(fontKey) or nil
    return TryPath(path, fontKey)
        or TryPath(internal, fontKey)
        or TryPath(FONT_LIST[1] and FONT_LIST[1].path, "FRIZQT")
        or TryPath("Fonts\\FRIZQT__.TTF", "FRIZQT")
        or "Fonts\\FRIZQT__.TTF"
end

G.MSUF_ResolveSafeFontPath = MSUF_ResolveSafeFontPath
MSUF.MSUF_ResolveSafeFontPath = MSUF_ResolveSafeFontPath

local function MSUF_GetFontPreviewObject(key)
    if not key or key == "" then
        return G.GameFontHighlightSmall
    end
    local obj = MSUF_FontPreviewObjects[key]
    if not obj then
        MSUF_FontPreviewObjectCount = MSUF_FontPreviewObjectCount + 1
        obj = G.CreateFont("MSUF_FontPreview_" .. tostring(MSUF_FontPreviewObjectCount))
        MSUF_FontPreviewObjects[key] = obj
    end
    local resolveKeyPath = G.MSUF_ResolveFontKeyPath
    local path = type(resolveKeyPath) == "function" and resolveKeyPath(key, 14, "") or nil
    local internalPath = type(G.MSUF_GetInternalFontPathByKey) == "function" and G.MSUF_GetInternalFontPathByKey(key) or nil
    path = path or internalPath or MSUF_FetchFontPathFromLSM(key) or FONT_LIST[1].path
    path = MSUF_ResolveSafeFontPath(path, 14, "", key)
    if path then
        local okCall, applied = pcall(obj.SetFont, obj, path, 14, "")
        local ok = okCall and applied ~= false
        if (not ok) and FONT_LIST[1] and FONT_LIST[1].path then
            local fallback = MSUF_ResolveSafeFontPath(FONT_LIST[1].path, 14, "", "FRIZQT")
            pcall(obj.SetFont, obj, fallback, 14, "")
        end
    end
    return obj
end
MSUF.MSUF_GetFontPreviewObject = MSUF_GetFontPreviewObject
G.MSUF_GetFontPreviewObject = MSUF_GetFontPreviewObject

local function MSUF_GetColorFromKey(key, fallbackColor)
    if type(key) ~= "string" then
        if fallbackColor then
            return fallbackColor
        end
        return G.CreateColor(1, 1, 1, 1)
    end
    local normalized = string_lower(key)
    local rgb = MSUF_FONT_COLORS[normalized]
    if rgb then
        local r, g, b = rgb[1], rgb[2], rgb[3]
        return G.CreateColor(r or 1, g or 1, b or 1, 1)
    end
    if fallbackColor then
        return fallbackColor
    end
    return G.CreateColor(1, 1, 1, 1)
end
MSUF.MSUF_GetColorFromKey = MSUF_GetColorFromKey
G.MSUF_GetColorFromKey = MSUF_GetColorFromKey

G.MSUF_DARK_TONES = {
    black    = { 0.0, 0.0, 0.0 },
    darkgray = { 0.08, 0.08, 0.08 },
    softgray = { 0.16, 0.16, 0.16 },
}

function G.MSUF_GetInternalFontPathByKey(key)
    if not key then return nil end
    local registryPath = G.MSUF_GetInternalFontPrimaryPath
    if type(registryPath) == "function" then
        local p = registryPath(key)
        if p then return p end
    end
    local normalized = MSUF_NormalizeFontKey(key)
    for _, info in ipairs(FONT_LIST) do
        if info.key == key or info.key == normalized or info.name == key then
            return info.path
        end
    end
    return nil
end
G.GetInternalFontPathByKey = G.GetInternalFontPathByKey or G.MSUF_GetInternalFontPathByKey

local function MSUF_IsInternalFontKey(key)
    return MSUF_FontKeyIsInternal(key)
end

local function MSUF_GetFontPathForKey(key)
    local resolveKeyPath = G.MSUF_ResolveFontKeyPath
    if type(resolveKeyPath) == "function" then
        local p = resolveKeyPath(key, 14, "")
        if p then return MSUF_ResolveSafeFontPath(p, 14, "", key) end
    end
    local internalPath = G.MSUF_GetInternalFontPathByKey(key)
    if internalPath then return MSUF_ResolveSafeFontPath(internalPath, 14, "", key) end
    local lsmPath = MSUF_FetchFontPathFromLSM(key)
    if lsmPath then return MSUF_ResolveSafeFontPath(lsmPath, 14, "", key) end
    return MSUF_ResolveSafeFontPath(FONT_LIST[1].path, 14, "", "FRIZQT")
end
G.MSUF_GetFontPathForKey = MSUF_GetFontPathForKey
MSUF.MSUF_GetFontPathForKey = MSUF_GetFontPathForKey
G.MSUF_IsInternalFontKey = MSUF_IsInternalFontKey
MSUF.MSUF_IsInternalFontKey = MSUF_IsInternalFontKey
G.MSUF_FetchFontPathFromLSM = MSUF_FetchFontPathFromLSM
MSUF.MSUF_FetchFontPathFromLSM = MSUF_FetchFontPathFromLSM
G.MSUF_GetRawLSMFontPath = MSUF_GetRawLSMFontPath
MSUF.MSUF_GetRawLSMFontPath = MSUF_GetRawLSMFontPath
