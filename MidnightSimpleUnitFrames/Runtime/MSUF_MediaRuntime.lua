-- Shared statusbar media resolution; castbar styling remains with Castbars.
local _, MSUF = ...
MSUF.Media = MSUF.Media or {}
local Media = MSUF.Media
local ExportPublic = MSUF.ExportPublic
local FILE = "Runtime/MSUF_MediaRuntime.lua"
local IsKnownFileAsset = MSUF.Require("MSUF_IsKnownFileAsset", FILE)
local EnsureDBProvider = MSUF.Require("MSUF_EnsureDB", FILE)
local SharedMedia = MSUF.Require("MSUF_GetSharedMedia", FILE)
local lsm = MSUF.LSM
local function EnsureDB()
    local db = MSUF.Optional("MSUF_DB")
    if not db then EnsureDBProvider() db = MSUF.Require("MSUF_DB", FILE) end
    db.general = db.general or {}
    return db
end

local function GetLSM()
    local resolved = SharedMedia() or lsm
    if resolved then lsm = resolved end
    return resolved
end

local function IsKnownAsset(path)
    if type(path) ~= "string" or path == "" then return false end

    local validator = IsKnownFileAsset
    if type(validator) == "function" and validator(path) == false then
        return false
    end
    return true
end

local resolvedStatusbarTextureCache = {}

local function ClearResolvedStatusbarTextureCache()
    resolvedStatusbarTextureCache = {}
    local castbars = MSUF.Castbars
    local castbarTextureCache = castbars and castbars.Core.CastbarTextureCache
    if type(castbarTextureCache) == "table" then
        for key in pairs(castbarTextureCache) do castbarTextureCache[key] = nil end
    end

    GetLSM()
end
Media.ClearResolvedStatusbarTextureCache = ClearResolvedStatusbarTextureCache
ExportPublic("MSUF_ClearResolvedStatusbarTextureCache", Media.ClearResolvedStatusbarTextureCache)

local function ResolveStatusbarTextureKey(key)
    if type(key) ~= "string" or key == "" then return "Interface\\TargetingFrame\\UI-StatusBar" end

    local cached = resolvedStatusbarTextureCache[key]
    if cached then return cached end

    local resolved
    local cacheable = false
    local builtin = Media.BUILTIN_BAR_TEXTURES
    if type(builtin) == "table" then
        local path = builtin[key]
        if type(path) == "string" and path ~= "" and IsKnownAsset(path) then
            resolved = path
            cacheable = true
        end
    end

    if not resolved then
        if key:find("\\") or key:find("/") then
            if IsKnownAsset(key) then
                resolved = key
                cacheable = true
            end
        else
            local media = GetLSM()
            if media and type(media.Fetch) == "function" then
                local fetched = media:Fetch("statusbar", key, true)
                if type(fetched) == "string" and fetched ~= "" and IsKnownAsset(fetched) then
                    resolved = fetched
                    cacheable = true
                end
            end
        end
    end

    if resolved then
        if cacheable then resolvedStatusbarTextureCache[key] = resolved end
        return resolved
    end

    local fallback = "Interface\\TargetingFrame\\UI-StatusBar"
    if cacheable then resolvedStatusbarTextureCache[key] = fallback end
    return fallback
end
Media.ResolveStatusbarTextureKey = ResolveStatusbarTextureKey
ExportPublic("MSUF_ResolveStatusbarTextureKey", Media.ResolveStatusbarTextureKey)

Media.BUILTIN_BAR_TEXTURES = Media.BUILTIN_BAR_TEXTURES or {
    Blizzard = "Interface\\TargetingFrame\\UI-StatusBar",
    Flat = "Interface\\Buttons\\WHITE8x8",
    ["MSUF Lucent"] = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Bars\\MSUF_Lucent_v2.tga",
    RaidHP = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill",
    RaidPower = "Interface\\RaidFrame\\Raid-Bar-Resource-Fill",
    Skills = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar",
    Outline = "Interface\\Tooltips\\UI-Tooltip-Background",
    TooltipBorder = "Interface\\Tooltips\\UI-Tooltip-Border",
    DialogBG = "Interface\\DialogFrame\\UI-DialogBox-Background",
    Parchment = "Interface\\AchievementFrame\\UI-Achievement-StatsBackground",
}
ExportPublic("MSUF_BUILTIN_BAR_TEXTURES", Media.BUILTIN_BAR_TEXTURES)

local function GetBarTexture()
    local db = EnsureDB()
    local general = (db and db.general) or nil
    return ResolveStatusbarTextureKey(general and general.barTexture)
end
Media.GetBarTexture = GetBarTexture
ExportPublic("MSUF_GetBarTexture", Media.GetBarTexture)

local function GetBarBackgroundTexture()
    local db = EnsureDB()
    local general = (db and db.general) or nil
    local key = general and general.barBackgroundTexture
    if key == nil or key == "" then key = general and general.barTexture end
    return ResolveStatusbarTextureKey(key)
end
Media.GetBarBackgroundTexture = GetBarBackgroundTexture
ExportPublic("MSUF_GetBarBackgroundTexture", Media.GetBarBackgroundTexture)

local function ResolveTextureCandidate(key)
    if type(key) ~= "string" or key == "" then return nil, true end

    local builtin = Media.BUILTIN_BAR_TEXTURES
    if type(builtin) == "table" then
        local path = builtin[key]
        if type(path) == "string" and path ~= "" then
            if IsKnownAsset(path) then return path, true end
            return nil, false
        end
    end

    if key:find("\\") or key:find("/") then
        if IsKnownAsset(key) then return key, true end
        return nil, false
    end

    local media = GetLSM()
    if media and media.Fetch then
        local path = media:Fetch("statusbar", key, true)
        if type(path) == "string" and path ~= "" then
            if IsKnownAsset(path) then return path, true end
            return nil, false
        end
    end

    return nil, false
end

Media.ResolveTextureCandidate = ResolveTextureCandidate
