-- Shared font resolution and application policy; loaded before State readers.
local addonName, MSUF = ...
MSUF.Fonts = MSUF.Fonts or {}
local Fonts = MSUF.Fonts
local ExportPublic, Optional = MSUF.ExportPublic, MSUF.Optional
local FILE = "Runtime/MSUF_Fonts.lua"
local Require = MSUF.Require
local MSUF_GetRegisteredLSMFontPath = Require("MSUF_GetRegisteredLSMFontPath", FILE)
local MSUF_IsKnownFileAsset = Require("MSUF_IsKnownFileAsset", FILE)
local MSUF_ApplyFontScaleAnimationMode = Require("MSUF_ApplyFontScaleAnimationMode", FILE)
local MSUF_SetFontChecked = Require("MSUF_SetFontChecked", FILE)
local MSUF_FontApplicationMatches = Require("MSUF_FontApplicationMatches", FILE)
local MSUF_ClearFontStringApplyCaches = Require("MSUF_ClearFontStringApplyCaches", FILE)
local MSUF_MarkFontApplyFailed = Require("MSUF_MarkFontApplyFailed", FILE)
local GetLSM = Require("MSUF_GetSharedMedia", FILE)
local table_insert = table.insert

local FONT_LIST = {
    {
        key  = "FRIZQT",
        name = "Friz Quadrata (default)",
        path = "Fonts\\FRIZQT___CYR.TTF",
    },
    {
        key  = "ARIALN",
        name = "Arial (default)",
        path = "Fonts\\ARIALN.TTF",
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
        { key = "SOUNDSCAPE",                 name = "Fritz Soundscape",                  file = "Fritz Soundscape.ttf" },
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

ExportPublic("MSUF_FONT_LIST", Optional("MSUF_FONT_LIST") or FONT_LIST)
Fonts.Catalog = FONT_LIST

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
    ["Fritz Soundscape"] = "SOUNDSCAPE",
}

local function MSUF_NormalizeFontKey(key)
    if type(key) ~= "string" or key == "" then return key end
    return MSUF_INTERNAL_LSM_FONT_KEYS[key] or key
end
ExportPublic("MSUF_NormalizeFontKey", MSUF_NormalizeFontKey)
MSUF.MSUF_NormalizeFontKey = MSUF_NormalizeFontKey

--- Legacy visual-probing font resolvers were intentionally removed. The path-first
--- pipeline below owns the public font helper globals and guarded SetFont path.

--- Font pipeline v3: path-first, no visual guessing.
--- A selected SharedMedia font is stored/resolved as the exact file path and is
--- applied directly. A rejected path surfaces as an error with no replacement font.
do
    local ADDON_FONT_BASE = "Interface\\AddOns\\" .. tostring(addonName or "MidnightSimpleUnitFrames") .. "\\Media\\Fonts\\"
    local ALIAS_TO_PATH = {}
    for _, info in ipairs(FONT_LIST) do ALIAS_TO_PATH[info.key] = info.path end
    for alias, key in pairs(MSUF_INTERNAL_LSM_FONT_KEYS) do ALIAS_TO_PATH[alias] = ALIAS_TO_PATH[key] end
    Fonts.InternalPaths = ALIAS_TO_PATH

    local function NormalizeFontPath(path)
        if type(path) ~= "string" or path == "" then return nil end
        path = path:gsub("/", "\\")
        if path:lower() == "interface\\addons\\midnightsimpleunitframes\\media\\fonts\\expressway.ttf" then
            return ADDON_FONT_BASE .. "Expressway Regular.ttf"
        end
        return path
    end

    local function FontAssetAllowed(path)
        path = NormalizeFontPath(path)
        if type(path) ~= "string" or path == "" then return nil end
        -- An exact LibSharedMedia registration is authoritative metadata for
        -- this session. Skip transient manifest/probe negatives and let the
        -- verified SetFont call remain the final openability check.
        local registered = MSUF_GetRegisteredLSMFontPath(path)
        if registered then return registered end
        local isKnown = MSUF_IsKnownFileAsset
        if type(isKnown) == "function" and isKnown(path) == false then return nil end
        local isAvailable = Optional("MSUF_IsAvailableFontPath")
        if type(isAvailable) == "function" and not isAvailable(path) then return nil end
        return path
    end



    local function IsPath(value)
        if type(value) ~= "string" or value == "" then return false end
        local lower = value:lower()
        return value:find("\\", 1, true) ~= nil
            or value:find("/", 1, true) ~= nil
            or lower:match("%.ttf$") ~= nil
            or lower:match("%.otf$") ~= nil
    end
    Fonts.IsFontPath = IsPath

    local function NormalizeFlags(flags)
        if type(flags) ~= "string" then return "" end
        flags = flags:gsub("^[%s,]+", ""):gsub("[%s,]+$", "")
        if flags == "NONE" then return "" end
        return flags:gsub("%s*,%s*", ","):gsub(",+", ","):gsub("^[%s,]+", ""):gsub("[%s,]+$", "")
    end

    local function FetchLSMFontPath(key)
        if type(key) ~= "string" or key == "" then return nil end
        local LSM = GetLSM()
        if not LSM then return nil end
        if type(LSM.HashTable) == "function" then
            local fonts = LSM:HashTable("font")
            local path = fonts and fonts[key]
            path = FontAssetAllowed(path)
            if path then return path end
        end
        if type(LSM.Fetch) == "function" then
            local path = FontAssetAllowed(LSM:Fetch("font", key, true))
            if path then return path end
        end
        return nil
    end

    local function ResolveFontKeyPath(value)
        if IsPath(value) then return FontAssetAllowed(value) end
        if type(value) ~= "string" or value == "" then return FontAssetAllowed(ALIAS_TO_PATH.FRIZQT) end
        local normalized = MSUF_NormalizeFontKey(value)
        if IsPath(normalized) then return FontAssetAllowed(normalized) end
        return FontAssetAllowed(ALIAS_TO_PATH[normalized])
            or FontAssetAllowed(ALIAS_TO_PATH[value])
            or FetchLSMFontPath(normalized)
            or FetchLSMFontPath(value)
    end

    local function ResolveFontPath(path, _, _, fontKey)
        local resolved
        if path ~= nil and path ~= "" then
            resolved = FontAssetAllowed(path)
        else
            resolved = ResolveFontKeyPath(fontKey)
        end
        -- Missing external media must not abort frame construction. Keep the
        -- stored selection intact so a later registration can restore it.
        return resolved or ALIAS_TO_PATH.FRIZQT
    end

    local function ApplyOne(fs, path, size, flags)
        if not (fs and type(fs.SetFont) == "function") then return false end
        path = FontAssetAllowed(path)
        if not path then return false end
        MSUF_ApplyFontScaleAnimationMode(fs, flags)
        local epoch = tonumber(MSUF_FontApplyEpoch) or 0
        if fs._msufFontAppliedPath == path
            and fs._msufFontAppliedSize == size
            and fs._msufFontAppliedFlags == flags
            and fs._msufFontAppliedEpoch == epoch
        then
            return true
        end
        if MSUF_SetFontChecked(fs, path, size, flags) and MSUF_FontApplicationMatches(fs, path, size) then
            fs._msufFontAppliedPath = path
            fs._msufFontAppliedSize = size
            fs._msufFontAppliedFlags = flags
            fs._msufFontAppliedEpoch = epoch
            return true
        end
        MSUF_ClearFontStringApplyCaches(fs)
        return false
    end

    local function ApplyResolvedFont(fs, path, size, flags, fontKey)
        size = tonumber(size) or 12
        if size <= 0 then size = 12 end
        flags = NormalizeFlags(flags)
        local requested = ResolveFontPath(path, size, flags, fontKey)
        local epoch = tonumber(MSUF_FontApplyEpoch) or 0
        if fs._msufFontRequestPath == requested
            and fs._msufFontRequestSize == size
            and fs._msufFontRequestFlags == flags
            and fs._msufFontRequestEpoch == epoch then
            return true, requested, "cached"
        end
        if not ApplyOne(fs, requested, size, flags) then
            MSUF_MarkFontApplyFailed()
            return false, requested, "pending"
        end
        fs._msufFontRequestPath = requested
        fs._msufFontRequestSize = size
        fs._msufFontRequestFlags = flags
        fs._msufFontRequestAppliedPath = requested
        fs._msufFontSource = "requested"
        fs._msufFontRequestEpoch = epoch
        return true, requested, "requested"
    end

    local function MSUF_NormalizeFontFlags(flags)
        return NormalizeFlags(flags)
    end

    local function MSUF_NormalizeFontPath(path)
        return NormalizeFontPath(path)
    end

    local function MSUF_FontPathEquals(a, b)
        a, b = NormalizeFontPath(a), NormalizeFontPath(b)
        return a ~= nil and b ~= nil and a:lower() == b:lower()
    end

    local function MSUF_FontLooksLikeBundledExpressway(_, path)
        local normalized = NormalizeFontPath(path)
        local key = normalized and normalized:lower() or nil
        return key ~= nil
            and key:find("interface\\addons\\midnightsimpleunitframes\\media\\fonts\\expressway", 1, true) ~= nil
    end

    local function MSUF_ResolveFontKeyPath(key)
        return ResolveFontKeyPath(key)
    end

    local function MSUF_ResolveFontPath(path, size, flags, fontKey)
        return ResolveFontPath(path, size, flags, fontKey)
    end





    local function MSUF_GetInternalFontPrimaryPath(key)
        return ResolveFontKeyPath(key)
    end



    local function MSUF_DebugFontProbe(key)
        local db = key == nil and MSUF_DB
        if db and db.general then
            key = db.general.fontKey
        end
        local requested = ResolveFontKeyPath(key)
        local probe
        if type(CreateFrame) == "function" then
            local frame = CreateFrame("Frame")
            if frame.Hide then frame:Hide() end
            probe = frame.CreateFontString and frame:CreateFontString(nil, "OVERLAY")
        end
        local ok, applied, source = ApplyResolvedFont(probe, requested, 14, "", key)
        local actual
        if probe and type(probe.GetFont) == "function" then
            actual = probe:GetFont()
        end
        return {
            key = key,
            requested = requested,
            ok = ok,
            applied = applied,
            actual = actual,
            source = source,
            lsm = FetchLSMFontPath(key),
        }
    end

    ExportPublic("MSUF_NormalizeFontFlags", MSUF_NormalizeFontFlags)
    ExportPublic("MSUF_NormalizeFontPath", MSUF_NormalizeFontPath)
    ExportPublic("MSUF_FontPathEquals", MSUF_FontPathEquals)
    --- Deprecated compatibility alias of MSUF_FontPathEquals.
    ExportPublic("MSUF_FontPathMatches", MSUF_FontPathEquals)
    MSUF.Compat = MSUF.Compat or {}
    MSUF.Compat.DeprecatedAliases = MSUF.Compat.DeprecatedAliases or {}
    MSUF.Compat.DeprecatedAliases.MSUF_FontPathMatches = "MSUF_FontPathEquals"
    ExportPublic("MSUF_FontLooksLikeBundledExpressway", MSUF_FontLooksLikeBundledExpressway)
    ExportPublic("MSUF_ResolveFontKeyPath", MSUF_ResolveFontKeyPath)
    ExportPublic("MSUF_ResolveFontPath", MSUF_ResolveFontPath)
    ExportPublic("MSUF_ApplyResolvedFont", ApplyResolvedFont)
    ExportPublic("MSUF_GetInternalFontPrimaryPath", MSUF_GetInternalFontPrimaryPath)
    ExportPublic("MSUF_DebugFontProbe", MSUF_DebugFontProbe)

    MSUF.Util = MSUF.Util or {}
    MSUF.Util.ResolveFontPath = MSUF_ResolveFontPath
    MSUF.Util.ResolveFontKeyPath = MSUF_ResolveFontKeyPath
    Fonts.ResolvePath = MSUF_ResolveFontPath
    Fonts.ResolveKeyPath = MSUF_ResolveFontKeyPath
end

local function MSUF_GetInternalFontPathByKey(key)
    if not key then return nil end
    -- Catalogue diagnostics retain a built-in's raw path even when validation
    -- is temporarily negative; application still uses the validated resolver.
    return Fonts.ResolveKeyPath(key) or Fonts.InternalPaths[key]
end
local function GetFontPathForKey(key)
    local path = Fonts.ResolveKeyPath(key)
    return Fonts.ResolvePath(path or FONT_LIST[1].path, 14, "", key)
end
ExportPublic("MSUF_GetInternalFontPathByKey", MSUF_GetInternalFontPathByKey)
Fonts.InternalPathForKey = MSUF_GetInternalFontPathByKey
ExportPublic("MSUF_GetFontPathForKey", GetFontPathForKey)
MSUF.MSUF_GetFontPathForKey = GetFontPathForKey

local function EnsureDB(db)
    db = db or MSUF_DB
    if not db then
        Require("MSUF_EnsureDB", FILE)()
        db = MSUF_DB
    end
    db.general = db.general or {}
    return db
end

local function GetFontPath()
    local general = EnsureDB().general
    local path = GetFontPathForKey(general.fontKey)
    return Fonts.ResolvePath(path, general.fontSize or 14, Fonts.GetFontFlags())
end

local function GetGlobalFontFlags()
    local db = EnsureDB()
    local general = db.general

    if general.fontSlug then
        if general.noOutline then return "SLUG" end
        return "OUTLINE,SLUG"
    end
    if general.noOutline then
        if general.fontMonochrome then return "MONOCHROME" end
        return ""
    elseif general.boldText then
        if general.fontMonochrome then return "THICKOUTLINE,MONOCHROME" end
        return "THICKOUTLINE"
    end

    if general.fontMonochrome then return "OUTLINE,MONOCHROME" end
    return "OUTLINE"
end

local function GetGlobalFontSettings()
    -- Before State seeds a profile, an empty general table has the exact
    -- default tuple. Avoid resolving its unchanged default for each aura text.
    local source = MSUF_DB
    local empty = source and source.general
    if empty and next(empty) == nil and not MSUF.MSUF_GetConfiguredFontColor then
        return FONT_LIST[1].path, "OUTLINE", 1, 1, 1, 14, true
    end
    local db = EnsureDB(source)
    local general = db.general or {}
    local fontPath = GetFontPath()
    local fontFlags = GetGlobalFontFlags()
    local red, green, blue = 1, 1, 1
    local color = Optional("MSUF_GetConfiguredFontColor")
    if color then
        red, green, blue = color()
    end
    local fontSize = general.fontSize or 14
    local textBackdrop = general.textBackdrop ~= false
        and not tostring(fontFlags):upper():find("SLUG", 1, true)
    return fontPath, fontFlags, red, green, blue, fontSize, textBackdrop
end
MSUF.MSUF_GetGlobalFontSettings = GetGlobalFontSettings
Fonts.GetGlobalFontSettings = GetGlobalFontSettings
ExportPublic("MSUF_GetGlobalFontSettings", GetGlobalFontSettings)

Fonts.GetFontPath = GetFontPath
Fonts.GetFontFlags = GetGlobalFontFlags
MSUF.MSUF_GetFontPath = GetFontPath
MSUF.MSUF_GetFontFlags = GetGlobalFontFlags
ExportPublic("MSUF_GetFontPath", GetFontPath)
ExportPublic("MSUF_GetFontFlags", GetGlobalFontFlags)
