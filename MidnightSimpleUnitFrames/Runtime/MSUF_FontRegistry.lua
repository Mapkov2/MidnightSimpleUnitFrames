--- Runtime/MSUF_FontRegistry.lua
--- Font availability metadata, LibSharedMedia readiness bridge and previews.
---
--- Font policy and the catalogue live in MSUF_Fonts.lua, before State loads.
--- Runtime font application lives in MSUF_FontRuntime.lua.

local addonName, MSUF = ...
local FILE = "Runtime/MSUF_FontRegistry.lua"

local ExportPublic = MSUF.ExportPublic
local Require = MSUF.Require
local type, tostring, ipairs = type, tostring, ipairs
local table_insert = table.insert
local IsRegisteredLSMFontPath = Require("MSUF_IsRegisteredLSMFontPath", FILE)
local SetFontChecked = Require("MSUF_SetFontChecked", FILE)
local LSM = MSUF.LSM or Require("MSUF_LSM", FILE)

--- Called by the LSM bootstrap when LibSharedMedia becomes available after this
--- file loaded. Keep the local LSM reference fresh for later lookups.
ExportPublic("MSUF_OnLSMReady", function(lsm)
    LSM = lsm
end)

local FONT_LIST = MSUF.Fonts.Catalog

-- Availability is registry metadata, not a speculative SetFont call. Unknown
-- imported paths stay in saved variables and use the configured default until
-- their provider registers them. Actual font application retains native errors.
local availableFontPaths = {}
local fontAvailabilityCache = {}
local function RememberAvailableFont(path)
    if type(path) == "string" and path ~= "" then
        availableFontPaths[path:gsub("/", "\\"):lower()] = true
    end
end
for i = 1, #FONT_LIST do RememberAvailableFont(FONT_LIST[i].path) end
for _, path in ipairs({
    "Fonts\\FRIZQT__.TTF", "Fonts\\ARIALN.TTF", "Fonts\\MORPHEUS.TTF", "Fonts\\SKURRI.TTF",
}) do RememberAvailableFont(path) end
RememberAvailableFont(STANDARD_TEXT_FONT)
RememberAvailableFont(UNIT_NAME_FONT)
RememberAvailableFont(DAMAGE_TEXT_FONT)

local function MSUF_IsAvailableFontPath(rawPath)
    if type(rawPath) ~= "string" or rawPath == "" then return false end
    local cached = fontAvailabilityCache[rawPath]
    if cached == true then return true end
    -- A late LSM registration promotes a previously unavailable imported face.
    if IsRegisteredLSMFontPath(rawPath) then
        fontAvailabilityCache[rawPath] = true
        return true
    end
    if cached == false then return false end
    local available = availableFontPaths[rawPath:gsub("/", "\\"):lower()] == true
    fontAvailabilityCache[rawPath] = available
    return available
end

ExportPublic("MSUF_IsAvailableFontPath", MSUF_IsAvailableFontPath)
MSUF.MSUF_IsAvailableFontPath = MSUF_IsAvailableFontPath

local MSUF_NormalizeFontKey = Require("MSUF_NormalizeFontKey", FILE)

local function MSUF_NormalizeFontKeyField(tbl)
    if type(tbl) ~= "table" then return end
    local normalized = MSUF_NormalizeFontKey(tbl.fontKey)
    local resolved = MSUF.Fonts.ResolveKeyPath(normalized)
    if type(resolved) == "string" and resolved ~= "" then
        normalized = resolved
    end
    if normalized ~= tbl.fontKey then
        tbl.fontKey = normalized
    end
end

--- Profile migration: old per-scope font keys now collapse to the global font
--- setting. This keeps imports/older profiles from carrying stale overrides.
local function MSUF_NormalizeStoredFontKeys()
    local db = MSUF_DB
    if type(db) ~= "table" then return end
    MSUF_NormalizeFontKeyField(db.general)
    for _, key in ipairs({
        "player", "target", "targettarget", "focustarget", "focus", "pet", "pettarget", "boss", "arena",
        "gf_party", "gf_raid", "gf_mythicraid",
    }) do
        if type(db[key]) == "table" then
            db[key].fontKey = nil
        end
    end
end
ExportPublic("MSUF_NormalizeStoredFontKeys", MSUF_NormalizeStoredFontKeys)
MSUF.MSUF_NormalizeStoredFontKeys = MSUF_NormalizeStoredFontKeys
-- Not run while this file loads: the SavedVariables arrive after every file
-- ran, so it would only see a throwaway profile. The defaults pass
-- (State/MSUF_Defaults.lua: NormalizeFontField and ClearScopedFontKeys) does
-- the same on the saved profile when it loads, and the Fonts page calls this
-- after its own edits.

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
    local lsm = LSM or MSUF.LSM or Require("MSUF_LSM", FILE)

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

-- Plain function instead of a per-call closure: this resolver runs for every
-- text element of every preview refresh.


local function MSUF_ResolveSafeFontPath(path, size, flags, fontKey)
    return MSUF.Fonts.ResolvePath(path, size, flags, fontKey)
end

ExportPublic("MSUF_ResolveSafeFontPath", MSUF_ResolveSafeFontPath)
MSUF.MSUF_ResolveSafeFontPath = MSUF_ResolveSafeFontPath

local function MSUF_GetFontPreviewObject(key)
    if not key or key == "" then
        return GameFontHighlightSmall
    end
    local obj = MSUF_FontPreviewObjects[key]
    if not obj then
        MSUF_FontPreviewObjectCount = MSUF_FontPreviewObjectCount + 1
        obj = CreateFont("MSUF_FontPreview_" .. tostring(MSUF_FontPreviewObjectCount))
        MSUF_FontPreviewObjects[key] = obj
    end
    -- An unknown or not yet registered key previews the default face, like
    -- every other font consumer; the stored selection is left untouched.
    local path = MSUF_ResolveSafeFontPath(nil, 14, "", key)
    SetFontChecked(obj, path, 14, "")
    return obj
end
MSUF.MSUF_GetFontPreviewObject = MSUF_GetFontPreviewObject
ExportPublic("MSUF_GetFontPreviewObject", MSUF_GetFontPreviewObject)

--- Deprecated compatibility alias: the unprefixed name predates the MSUF_
--- prefix; it is only claimed while no other addon owns it.
ExportPublic("GetInternalFontPathByKey", MSUF.Optional("GetInternalFontPathByKey") or Require("MSUF_GetInternalFontPathByKey", FILE))
MSUF.Compat = MSUF.Compat or {}
MSUF.Compat.DeprecatedAliases = MSUF.Compat.DeprecatedAliases or {}
MSUF.Compat.DeprecatedAliases.GetInternalFontPathByKey = "MSUF_GetInternalFontPathByKey"

local function MSUF_IsInternalFontKey(key)
    return MSUF_FontKeyIsInternal(key)
end

ExportPublic("MSUF_IsInternalFontKey", MSUF_IsInternalFontKey)
MSUF.MSUF_IsInternalFontKey = MSUF_IsInternalFontKey
ExportPublic("MSUF_FetchFontPathFromLSM", MSUF_FetchFontPathFromLSM)
MSUF.MSUF_FetchFontPathFromLSM = MSUF_FetchFontPathFromLSM
ExportPublic("MSUF_GetRawLSMFontPath", MSUF_GetRawLSMFontPath)
MSUF.MSUF_GetRawLSMFontPath = MSUF_GetRawLSMFontPath
