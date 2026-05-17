local addonName, ns = ...
ns = ns or _G.MSUF_NS or {}
_G.MSUF_NS = ns

local G = _G
local type, tostring, ipairs = type, tostring, ipairs
local table_insert = table.insert
local string_lower = string.lower

local LSM = (ns and ns.LSM) or G.MSUF_LSM or (LibStub and LibStub("LibSharedMedia-3.0", true))

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
            elseif G.C_Timer and G.C_Timer.After then
                G.C_Timer.After(0, DeferredUpdateAllFonts)
            else
                DeferredUpdateAllFonts()
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
ns.MSUF_NormalizeFontKey = MSUF_NormalizeFontKey

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
ns.MSUF_NormalizeStoredFontKeys = MSUF_NormalizeStoredFontKeys
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
ns.MSUF_FONT_COLORS = MSUF_FONT_COLORS
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

    local snap = ns._PBCSnap
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
ns.MSUF_GetResolvedPowerColor = MSUF_GetResolvedPowerColor

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
ns.MSUF_GetConfiguredFontColor = MSUF_GetConfiguredFontColor

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
    local lsm = LSM or (ns and ns.LSM) or G.MSUF_LSM
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
    path = path or G.MSUF_GetInternalFontPathByKey(key) or MSUF_FetchFontPathFromLSM(key) or FONT_LIST[1].path
    path = (G.MSUF_ResolveFontPath or function(p) return p end)(path, 14, "", key)
    if path then
        local safeSet = G.MSUF_SetFontSafe
        local ok
        if type(safeSet) == "function" then
            ok = safeSet(obj, path, 14, "", key)
        else
            local applied
            ok, applied = pcall(obj.SetFont, obj, path, 14, "")
            ok = ok and applied ~= false
        end
        if (not ok) and FONT_LIST[1] and FONT_LIST[1].path then
            local fallback = (G.MSUF_ResolveFontPath or function(p) return p end)(FONT_LIST[1].path, 14, "")
            if type(safeSet) == "function" then
                safeSet(obj, fallback, 14, "", "FRIZQT")
            else
                pcall(obj.SetFont, obj, fallback, 14, "")
            end
        end
    end
    return obj
end
ns.MSUF_GetFontPreviewObject = MSUF_GetFontPreviewObject
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
ns.MSUF_GetColorFromKey = MSUF_GetColorFromKey
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
        if p then return p end
    end
    local resolve = G.MSUF_ResolveFontPath or function(path) return path end
    local internalPath = G.MSUF_GetInternalFontPathByKey(key)
    if internalPath then return resolve(internalPath, 14, "", key) end
    local lsmPath = MSUF_FetchFontPathFromLSM(key)
    if lsmPath then return resolve(lsmPath, 14, "", key) end
    return resolve(FONT_LIST[1].path, 14, "", "FRIZQT")
end
G.MSUF_GetFontPathForKey = MSUF_GetFontPathForKey
ns.MSUF_GetFontPathForKey = MSUF_GetFontPathForKey
G.MSUF_IsInternalFontKey = MSUF_IsInternalFontKey
ns.MSUF_IsInternalFontKey = MSUF_IsInternalFontKey
G.MSUF_FetchFontPathFromLSM = MSUF_FetchFontPathFromLSM
ns.MSUF_FetchFontPathFromLSM = MSUF_FetchFontPathFromLSM
G.MSUF_GetRawLSMFontPath = MSUF_GetRawLSMFontPath
ns.MSUF_GetRawLSMFontPath = MSUF_GetRawLSMFontPath
