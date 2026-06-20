-- Kernel library adapter: centralizes optional library lookup, cache, and compatibility exports.
-- Runs during boot; callers should depend on exported helpers rather than direct LibStub probes.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF = _G.MSUF or MSUF
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local _MSUF_KnownFileAssetCache = {}

local function MSUF_NormalizeFileAssetPath(asset)
    if type(asset) ~= "string" or asset == "" then return nil end
    return asset:gsub("/", "\\")
end

local function MSUF_IsKnownFileAsset(asset)
    asset = MSUF_NormalizeFileAssetPath(asset)
    if not asset then return false end

    local cacheKey = asset:lower()
    local cached = _MSUF_KnownFileAssetCache[cacheKey]
    if cached ~= nil then return cached end

    if cacheKey:sub(1, 17) == "interface\\addons\\" then
        _MSUF_KnownFileAssetCache[cacheKey] = true
        return true
    end

    local api = _G.C_UIFileAsset
    if type(api) ~= "table" then
        return nil
    end

    if type(api.IsKnownFile) == "function" then
        if api.IsKnownFile(asset) == true then
            _MSUF_KnownFileAssetCache[cacheKey] = true
            return true
        end
    end

    if type(api.GetFileID) == "function" then
        local fileID = api.GetFileID(asset)
        if type(fileID) == "number" then
            _MSUF_KnownFileAssetCache[cacheKey] = true
            return true
        end
    end

    -- 12.1 no longer publishes all new Interface texture filenames through the
    -- ManifestInterfaceData DB. Unknown here must stay "unknown", not "invalid".
    return nil
end

ExportPublic("MSUF_IsKnownFileAsset", _G.MSUF_IsKnownFileAsset or MSUF_IsKnownFileAsset)
MSUF.Util = MSUF.Util or {}
MSUF.Util.IsKnownFileAsset = MSUF.Util.IsKnownFileAsset or MSUF_IsKnownFileAsset

--- Legacy visual-probing font resolvers were intentionally removed. The path-first
--- pipeline below owns the public font helper globals and guarded SetFont path.

--- Font pipeline v3: path-first, no visual guessing.
--- A selected SharedMedia font is stored/resolved as the exact file path and is
--- applied directly. Fallback is only used after SetFont itself rejects the path.
do
    local ADDON_FONT_BASE = "Interface\\AddOns\\" .. tostring(addonName or "MidnightSimpleUnitFrames") .. "\\Media\\Fonts\\"
    local FALLBACK_FONT = "Fonts\\FRIZQT___CYR.TTF"
    local FALLBACK_FONT_ALTERNATES = {
        "Fonts\\FRIZQT___CYR.TTF",
        "Fonts\\FRIZQT__.TTF",
        "Fonts\\ARIALN.TTF",
    }

    local ALIAS_TO_PATH = {
        FRIZQT = "Fonts\\FRIZQT___CYR.TTF",
        ARIALN = "Fonts\\ARIALN.TTF",
        MORPHEUS = "Fonts\\MORPHEUS_CYR.TTF",
        SKURRI = "Fonts\\SKURRI_CYR.TTF",
        EXPRESSWAY = ADDON_FONT_BASE .. "Expressway Regular.ttf",
        EXPRESSWAY_BOLD = ADDON_FONT_BASE .. "Expressway Bold.ttf",
        EXPRESSWAY_SEMIBOLD = ADDON_FONT_BASE .. "Expressway SemiBold.ttf",
        EXPRESSWAY_EXTRABOLD = ADDON_FONT_BASE .. "Expressway ExtraBold.ttf",
        EXPRESSWAY_CONDENSED_LIGHT = ADDON_FONT_BASE .. "Expressway Condensed Light.otf",

        ["Friz Quadrata TT"] = "Fonts\\FRIZQT___CYR.TTF",
        ["Friz Quadrata (default)"] = "Fonts\\FRIZQT___CYR.TTF",
        ["Arial Narrow"] = "Fonts\\ARIALN.TTF",
        ["Arial (default)"] = "Fonts\\ARIALN.TTF",
        ["Morpheus"] = "Fonts\\MORPHEUS_CYR.TTF",
        ["Morpheus (default)"] = "Fonts\\MORPHEUS_CYR.TTF",
        ["Skurri"] = "Fonts\\SKURRI_CYR.TTF",
        ["Skurri (default)"] = "Fonts\\SKURRI_CYR.TTF",
        ["Expressway Regular (MSUF)"] = ADDON_FONT_BASE .. "Expressway Regular.ttf",
        ["Expressway (MSUF)"] = ADDON_FONT_BASE .. "Expressway Regular.ttf",
        ["Expressway Bold (MSUF)"] = ADDON_FONT_BASE .. "Expressway Bold.ttf",
        ["Expressway SemiBold (MSUF)"] = ADDON_FONT_BASE .. "Expressway SemiBold.ttf",
        ["Expressway ExtraBold (MSUF)"] = ADDON_FONT_BASE .. "Expressway ExtraBold.ttf",
        ["Expressway Condensed Light (MSUF)"] = ADDON_FONT_BASE .. "Expressway Condensed Light.otf",
    }

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
        local isKnown = _G.MSUF_IsKnownFileAsset or MSUF_IsKnownFileAsset
        if type(isKnown) == "function" and isKnown(path) == false then return nil end
        return path
    end

    local function ResolveFallbackFontPath()
        for i = 1, #FALLBACK_FONT_ALTERNATES do
            local path = FontAssetAllowed(FALLBACK_FONT_ALTERNATES[i])
            if path then return path end
        end
        return NormalizeFontPath(FALLBACK_FONT)
    end

    local function IsPath(value)
        if type(value) ~= "string" or value == "" then return false end
        local lower = value:lower()
        return value:find("\\", 1, true) ~= nil
            or value:find("/", 1, true) ~= nil
            or lower:match("%.ttf$") ~= nil
            or lower:match("%.otf$") ~= nil
    end

    local function NormalizeFlags(flags)
        if type(flags) ~= "string" then return "" end
        flags = flags:gsub("^[%s,]+", ""):gsub("[%s,]+$", "")
        if flags == "NONE" then return "" end
        return flags:gsub("%s*,%s*", ","):gsub(",+", ","):gsub("^[%s,]+", ""):gsub("[%s,]+$", "")
    end

    local function GetLSM()
        local LSM = (MSUF and MSUF.LSM) or _G.MSUF_LSM
        if not LSM and type(_G.LibStub) == "function" then
            LSM = _G.LibStub("LibSharedMedia-3.0", true)
        end
        return LSM
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
        if type(value) ~= "string" or value == "" then return FontAssetAllowed(ALIAS_TO_PATH.FRIZQT) or ResolveFallbackFontPath() end
        local normalized = type(_G.MSUF_NormalizeFontKey) == "function" and _G.MSUF_NormalizeFontKey(value) or value
        if IsPath(normalized) then return FontAssetAllowed(normalized) end
        return FontAssetAllowed(ALIAS_TO_PATH[normalized])
            or FontAssetAllowed(ALIAS_TO_PATH[value])
            or FetchLSMFontPath(normalized)
            or FetchLSMFontPath(value)
    end

    local function ResolveFontPath(path, _, _, fontKey)
        return FontAssetAllowed(path) or ResolveFontKeyPath(fontKey) or ResolveFallbackFontPath()
    end

    local function ApplyOne(fs, path, size, flags)
        if not (fs and type(fs.SetFont) == "function" and type(path) == "string" and path ~= "") then return false end
        local isKnown = _G.MSUF_IsKnownFileAsset or MSUF_IsKnownFileAsset
        if type(isKnown) == "function" and isKnown(path) == false then return false end
        if fs._msufFontAppliedPath == path
            and fs._msufFontAppliedSize == size
            and fs._msufFontAppliedFlags == flags
        then
            return true
        end
        local applied = fs:SetFont(path, size, flags)
        if applied ~= false then
            fs._msufFontAppliedPath = path
            fs._msufFontAppliedSize = size
            fs._msufFontAppliedFlags = flags
        end
        return applied ~= false
    end

    local function ApplyResolvedFont(fs, path, size, flags, fontKey)
        size = tonumber(size) or 12
        if size <= 0 then size = 12 end
        flags = NormalizeFlags(flags)
        local requested = ResolveFontPath(path, size, flags, fontKey)
        if fs and fs._msufFontRequestPath == requested
            and fs._msufFontRequestSize == size
            and fs._msufFontRequestFlags == flags
        then
            return true, fs._msufFontRequestAppliedPath or requested, fs._msufFontSource or "cached"
        end

        if ApplyOne(fs, requested, size, flags) or (flags ~= "" and ApplyOne(fs, requested, size, "")) then
            if fs then
                fs._msufFontRequestPath = requested
                fs._msufFontRequestSize = size
                fs._msufFontRequestFlags = flags
                fs._msufFontRequestAppliedPath = requested
                fs._msufFontSource = "requested"
            end
            return true, requested, "requested"
        end
        local fallback = ResolveFallbackFontPath()
        if fallback ~= requested and (ApplyOne(fs, fallback, size, flags) or (flags ~= "" and ApplyOne(fs, fallback, size, ""))) then
            if fs then
                fs._msufFontRequestPath = requested
                fs._msufFontRequestSize = size
                fs._msufFontRequestFlags = flags
                fs._msufFontRequestAppliedPath = fallback
                fs._msufFontSource = "fallback"
            end
            return true, fallback, "fallback"
        end
        if fs then
            fs._msufFontRequestPath = nil
            fs._msufFontRequestSize = nil
            fs._msufFontRequestFlags = nil
            fs._msufFontRequestAppliedPath = nil
            fs._msufFontSource = nil
        end
        return false, requested, "failed"
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

    local function MSUF_ClearResolvedFontPathCache()
    end

    local function MSUF_PrewarmFontVisualCache()
        return true
    end

    local function MSUF_GetInternalFontPrimaryPath(key)
        return ResolveFontKeyPath(key)
    end

    local function MSUF_GetInternalFontPathCandidates(key, path)
        return { ResolveFontPath(path, 14, "", key), ResolveFallbackFontPath() }
    end

    local function MSUF_DebugFontProbe(key)
        if key == nil and _G.MSUF_DB and _G.MSUF_DB.general then
            key = _G.MSUF_DB.general.fontKey
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
    ExportPublic("MSUF_FontPathMatches", MSUF_FontPathEquals)
    ExportPublic("MSUF_FontLooksLikeBundledExpressway", MSUF_FontLooksLikeBundledExpressway)
    ExportPublic("MSUF_ResolveFontKeyPath", MSUF_ResolveFontKeyPath)
    ExportPublic("MSUF_ResolveFontPath", MSUF_ResolveFontPath)
    ExportPublic("MSUF_ClearResolvedFontPathCache", MSUF_ClearResolvedFontPathCache)
    ExportPublic("MSUF_PrewarmFontVisualCache", MSUF_PrewarmFontVisualCache)
    ExportPublic("MSUF_GetInternalFontPrimaryPath", MSUF_GetInternalFontPrimaryPath)
    ExportPublic("MSUF_GetInternalFontPathCandidates", MSUF_GetInternalFontPathCandidates)
    ExportPublic("MSUF_DebugFontProbe", MSUF_DebugFontProbe)

    MSUF.Util = MSUF.Util or {}
    MSUF.Util.ResolveFontPath = MSUF_ResolveFontPath
    MSUF.Util.ResolveFontKeyPath = MSUF_ResolveFontKeyPath
end

--- Shared Lib initialization (loaded BEFORE Options and Main)
--- Goal: stable MSUF.LSM reference regardless of load order / refactors.

local function TryInitLSM()
    if MSUF.LSM then return true end

    local libStub = _G.LibStub
    if not libStub then return false end

    --- LibStub("LibSharedMedia-3.0", true) returns nil if not available.
    local lsm = libStub("LibSharedMedia-3.0", true)
    if lsm then
        MSUF.LSM = lsm
        ExportPublic("MSUF_LSM", lsm)

        --- Inform Main (which caches LSM in a local upvalue) that LSM is now ready.
        if _G.MSUF_OnLSMReady then
            _G.MSUF_OnLSMReady(lsm)
        end

        return true
    end
    return false
end

local LSM_REGISTERED_EVENT = "LibSharedMedia_Registered"
local LSM_CALLBACK_OWNER = MSUF.LSMCallbackOwner
if type(LSM_CALLBACK_OWNER) ~= "table" then
    LSM_CALLBACK_OWNER = { name = "MSUF_LSM_CallbackOwner" }
    MSUF.LSMCallbackOwner = LSM_CALLBACK_OWNER
end

local _MSUF_StatusbarMediaRefreshPending = false
local _MSUF_StatusbarMediaRefreshFrame
local _MSUF_FontMediaRefreshPending = false
local _MSUF_FontMediaRefreshFrame
local _MSUF_LSMCombatFrame
local _MSUF_LSMCallbackActive = false
local _MSUF_LSMMediaCounts = { font = 0, statusbar = 0 }
local _MSUF_BundledMediaRegistrationPending = false

local RegisterBundledFonts
local RegisterLSMCallback
local UnregisterLSMCallback
local EnsureLSMCombatFrame

local function IsCombatLocked()
    return (type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown()) and true or false
end

local function RunStatusbarMediaRefresh()
    _MSUF_StatusbarMediaRefreshPending = false

    if type(_G.MSUF_ClearResolvedStatusbarTextureCache) == "function" then
        _G.MSUF_ClearResolvedStatusbarTextureCache()
    end

    local updateBars = _G.MSUF_UpdateAllBarTextures_Immediate or _G.MSUF_UpdateAllBarTextures
    if type(updateBars) == "function" then updateBars() end

    if type(_G.MSUF_UpdateAbsorbBarTextures) == "function" then
        _G.MSUF_UpdateAbsorbBarTextures()
    end

    local updateCastbars = _G.MSUF_UpdateCastbarTextures_Immediate or _G.MSUF_UpdateCastbarTextures
    if type(updateCastbars) == "function" then updateCastbars() end

    if type(_G.MSUF_ClassPower_RefreshTextures) == "function" then
        _G.MSUF_ClassPower_RefreshTextures()
    end

    local gf = (_G.MSUF_NS and _G.MSUF_NS.GF) or (MSUF and MSUF.GF)
    if gf then
        if type(gf.InvalidateConfCache) == "function" then gf.InvalidateConfCache() end
        if type(gf.RefreshVisuals) == "function" then
            gf.RefreshVisuals()
        elseif type(_G.MSUF_GF_RefreshOverlays) == "function" then
            _G.MSUF_GF_RefreshOverlays()
        end
    elseif type(_G.MSUF_GF_RefreshOverlays) == "function" then
        _G.MSUF_GF_RefreshOverlays()
    end
end

local function EnsureStatusbarMediaRefreshFrame()
    if _MSUF_StatusbarMediaRefreshFrame or type(_G.CreateFrame) ~= "function" then
        return _MSUF_StatusbarMediaRefreshFrame
    end
    local frame = _G.CreateFrame("Frame")
    frame:SetScript("OnEvent", function(self, event)
        if event ~= "PLAYER_REGEN_ENABLED" then return end
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if _MSUF_StatusbarMediaRefreshPending then
            if IsCombatLocked() then
                self:RegisterEvent("PLAYER_REGEN_ENABLED")
            else
                RunStatusbarMediaRefresh()
            end
        end
    end)
    _MSUF_StatusbarMediaRefreshFrame = frame
    return frame
end

local function RunFontMediaRefresh()
    _MSUF_FontMediaRefreshPending = false
    if type(_G.MSUF_UpdateAllFonts) == "function" then
        _G.MSUF_UpdateAllFonts()
    end
end

local function EnsureFontMediaRefreshFrame()
    if _MSUF_FontMediaRefreshFrame or type(_G.CreateFrame) ~= "function" then
        return _MSUF_FontMediaRefreshFrame
    end
    local frame = _G.CreateFrame("Frame")
    frame:SetScript("OnEvent", function(self, event)
        if event ~= "PLAYER_REGEN_ENABLED" then return end
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if _MSUF_FontMediaRefreshPending then
            if IsCombatLocked() then
                self:RegisterEvent("PLAYER_REGEN_ENABLED")
            else
                RunFontMediaRefresh()
            end
        end
    end)
    _MSUF_FontMediaRefreshFrame = frame
    return frame
end

local function FlushFontMediaRefresh()
    if IsCombatLocked() then
        local frame = EnsureFontMediaRefreshFrame()
        if frame then
            frame:RegisterEvent("PLAYER_REGEN_ENABLED")
            return
        end
    end
    RunFontMediaRefresh()
end

local function ScheduleFontMediaRefresh()
    if _MSUF_FontMediaRefreshPending then return end
    _MSUF_FontMediaRefreshPending = true
    if IsCombatLocked() then
        local frame = EnsureFontMediaRefreshFrame()
        if frame then
            frame:RegisterEvent("PLAYER_REGEN_ENABLED")
            return
        end
    end
    if _G.MSUF_ScheduleOnce then
        _G.MSUF_ScheduleOnce("LSM_FONT_MEDIA_REFRESH", FlushFontMediaRefresh)
    else
        _G.C_Timer.After(0, FlushFontMediaRefresh)
    end
end

local function FlushStatusbarMediaRefresh()
    if IsCombatLocked() then
        local frame = EnsureStatusbarMediaRefreshFrame()
        if frame then
            frame:RegisterEvent("PLAYER_REGEN_ENABLED")
            return
        end
    end
    RunStatusbarMediaRefresh()
end

local function ScheduleStatusbarMediaRefresh()
    if _MSUF_StatusbarMediaRefreshPending then return end
    _MSUF_StatusbarMediaRefreshPending = true
    if IsCombatLocked() then
        local frame = EnsureStatusbarMediaRefreshFrame()
        if frame then
            frame:RegisterEvent("PLAYER_REGEN_ENABLED")
            return
        end
    end
    if _G.MSUF_ScheduleOnce then
        _G.MSUF_ScheduleOnce("LSM_STATUSBAR_MEDIA_REFRESH", FlushStatusbarMediaRefresh)
    else
        _G.C_Timer.After(0, FlushStatusbarMediaRefresh)
    end
end

local function CountLSMMediaType(LSM, mediatype)
    if not (LSM and type(LSM.HashTable) == "function") then return 0 end
    local media = LSM:HashTable(mediatype)
    if type(media) ~= "table" then return 0 end
    local count = 0
    for _ in pairs(media) do
        count = count + 1
    end
    return count
end

local function SnapshotLSMMediaCounts(LSM)
    LSM = LSM or MSUF.LSM
    _MSUF_LSMMediaCounts.font = CountLSMMediaType(LSM, "font")
    _MSUF_LSMMediaCounts.statusbar = CountLSMMediaType(LSM, "statusbar")
end

local function RefreshFontMedia(key, forceApply)
    if type(_G.MSUF_ClearResolvedFontPathCache) == "function" then
        _G.MSUF_ClearResolvedFontPathCache()
    end
    if type(_G.MSUF_RebuildFontChoices) == "function" then
        _G.MSUF_RebuildFontChoices()
    end

    local needsFontRefresh = forceApply == true
    if not needsFontRefresh and key ~= nil then
        local normalizeFontKey = _G.MSUF_NormalizeFontKey or function(k) return k end
        local general = _G.MSUF_DB and _G.MSUF_DB.general
        needsFontRefresh = general and normalizeFontKey(general.fontKey) == normalizeFontKey(key)
    end
    if needsFontRefresh then
        ScheduleFontMediaRefresh()
    end
end

local function RefreshStatusbarMedia()
    if type(_G.MSUF_RebuildStatusbarChoices) == "function" then
        _G.MSUF_RebuildStatusbarChoices()
    end
    ScheduleStatusbarMediaRefresh()
end

local function RefreshChangedMediaAfterCombat()
    local LSM = MSUF.LSM
    local fontCount = CountLSMMediaType(LSM, "font")
    local statusbarCount = CountLSMMediaType(LSM, "statusbar")
    local fontChanged = fontCount ~= _MSUF_LSMMediaCounts.font
    local statusbarChanged = statusbarCount ~= _MSUF_LSMMediaCounts.statusbar

    _MSUF_LSMMediaCounts.font = fontCount
    _MSUF_LSMMediaCounts.statusbar = statusbarCount

    if fontChanged then
        RefreshFontMedia(nil, true)
    end
    if statusbarChanged then
        RefreshStatusbarMedia()
    end
end

local function OnLSMRegistered(_, mediatype, key)
    if IsCombatLocked() then
        ExportPublic("MSUF_LSM_CombatRefreshPending", true)
        if UnregisterLSMCallback then
            UnregisterLSMCallback()
        end
        local frame = EnsureLSMCombatFrame and EnsureLSMCombatFrame()
        if frame then
            frame:RegisterEvent("PLAYER_REGEN_ENABLED")
        end
        return
    end

    if mediatype == "font" then
        RefreshFontMedia(key, false)
    elseif mediatype == "statusbar" then
        RefreshStatusbarMedia()
    end
    SnapshotLSMMediaCounts(MSUF.LSM)
end

UnregisterLSMCallback = function()
    if not _MSUF_LSMCallbackActive then return true end
    local LSM = MSUF.LSM
    if LSM and type(LSM.UnregisterCallback) == "function" then
        LSM.UnregisterCallback(LSM_CALLBACK_OWNER, LSM_REGISTERED_EVENT)
    end
    _MSUF_LSMCallbackActive = false
    ExportPublic("MSUF_LSM_CallbackActive", false)
    return true
end

RegisterLSMCallback = function()
    local LSM = MSUF.LSM
    if not (LSM and type(LSM.RegisterCallback) == "function") then return false end
    if IsCombatLocked() then return false end
    if _MSUF_LSMCallbackActive then return true end

    LSM.RegisterCallback(LSM_CALLBACK_OWNER, LSM_REGISTERED_EVENT, OnLSMRegistered)
    _MSUF_LSMCallbackActive = true
    ExportPublic("MSUF_LSM_CallbackActive", true)
    return true
end

EnsureLSMCombatFrame = function()
    if _MSUF_LSMCombatFrame or type(_G.CreateFrame) ~= "function" then
        return _MSUF_LSMCombatFrame
    end
    local frame = _G.CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            UnregisterLSMCallback()
            return
        end
        if event ~= "PLAYER_REGEN_ENABLED" or IsCombatLocked() then return end

        if _MSUF_BundledMediaRegistrationPending and RegisterBundledFonts then
            RegisterBundledFonts()
        end
        RegisterLSMCallback()
        RefreshChangedMediaAfterCombat()
        ExportPublic("MSUF_LSM_CombatRefreshPending", nil)
    end)
    _MSUF_LSMCombatFrame = frame
    return frame
end

local function EnsureLSMCallbacks()
    local LSM = MSUF.LSM
    if not LSM then return end
    ExportPublic("MSUF_LSM_CallbacksRegistered", true)
    EnsureLSMCombatFrame()
    SnapshotLSMMediaCounts(LSM)
    RegisterLSMCallback()
end

--- Shared statusbar texture choices for Menu2 dropdowns.
--- Returns LibSharedMedia entries with a texture path so the native dropdown can
--- render a small statusbar preview for every texture.
local FALLBACK_STATUSBAR_TEXTURES = {
    { key = "Blizzard",      path = "Interface\\TargetingFrame\\UI-StatusBar" },
    { key = "Solid",         path = "Interface\\Buttons\\WHITE8X8" },
    { key = "Flat",          path = "Interface\\Buttons\\WHITE8x8" },
    { key = "RaidHP",        path = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
    { key = "RaidPower",     path = "Interface\\RaidFrame\\Raid-Bar-Resource-Fill" },
    { key = "Skills",        path = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar" },
    { key = "Outline",       path = "Interface\\Tooltips\\UI-Tooltip-Background" },
    { key = "TooltipBorder", path = "Interface\\Tooltips\\UI-Tooltip-Border" },
    { key = "DialogBG",      path = "Interface\\DialogFrame\\UI-DialogBox-Background" },
    { key = "Parchment",     path = "Interface\\AchievementFrame\\UI-Achievement-StatsBackground" },
}

local function GetStatusbarLSM()
    local LSM = (MSUF and MSUF.LSM) or _G.MSUF_LSM
    if not LSM and type(_G.LibStub) == "function" then
        LSM = _G.LibStub("LibSharedMedia-3.0", true)
    end
    return LSM
end

local function StatusbarAssetAllowed(texture)
    if type(texture) ~= "string" or texture == "" then return nil end
    local isKnown = _G.MSUF_IsKnownFileAsset or MSUF_IsKnownFileAsset
    if type(isKnown) == "function" and isKnown(texture) == false then return nil end
    return texture
end

local function FetchStatusbarTexture(lsm, key)
    if type(key) ~= "string" or key == "" then return nil end
    local builtins = _G.MSUF_BUILTIN_BAR_TEXTURES
    if type(builtins) == "table" then
        local texture = builtins[key]
        texture = StatusbarAssetAllowed(texture)
        if texture then return texture end
    end
    for i = 1, #FALLBACK_STATUSBAR_TEXTURES do
        local item = FALLBACK_STATUSBAR_TEXTURES[i]
        if item.key == key then return StatusbarAssetAllowed(item.path) end
    end
    if key:find("\\", 1, true) or key:find("/", 1, true) then return StatusbarAssetAllowed(key) end
    if lsm and type(lsm.Fetch) == "function" then
        local texture = StatusbarAssetAllowed(lsm:Fetch("statusbar", key, true))
        if texture then return texture end
    end
    return nil
end

local function AddStatusbarItem(out, used, value, text, texture, translate)
    if type(value) ~= "string" or value == "" or used[value] then return end
    used[value] = true
    out[#out + 1] = {
        value = value,
        text = text or value,
        texture = texture,
        translate = translate,
    }
end

local function StatusBarTextureItems(followText)
    local out, used = {}, {}
    local lsm = GetStatusbarLSM()
    if followText then
        out[#out + 1] = { value = "", text = followText }
        used[""] = true
    end

    for i = 1, #FALLBACK_STATUSBAR_TEXTURES do
        local item = FALLBACK_STATUSBAR_TEXTURES[i]
        AddStatusbarItem(out, used, item.key, item.key, item.path, false)
    end

    if lsm and type(lsm.List) == "function" then
        local names = lsm:List("statusbar")
        local hash
        if type(lsm.HashTable) == "function" then
            local h = lsm:HashTable("statusbar")
            if type(h) == "table" then hash = h end
        end
        if type(names) == "table" then
            table.sort(names, function(a, b)
                return tostring(a):lower() < tostring(b):lower()
            end)
            for i = 1, #names do
                local name = names[i]
                if type(name) == "string" and name ~= "" then
                    local texture = type(hash) == "table" and hash[name] or nil
                    texture = texture or FetchStatusbarTexture(lsm, name)
                    AddStatusbarItem(out, used, name, name, texture, false)
                end
            end
        end
    end

    return out
end

MSUF.UI = MSUF.UI or {}
MSUF.UI.StatusBarTextureItems = StatusBarTextureItems
ExportPublic("MSUF_StatusBarTextureItems", StatusBarTextureItems)
ExportPublic("MSUF_RebuildStatusbarChoices", _G.MSUF_RebuildStatusbarChoices or function() end)

--- Bundled fonts (Media/Fonts)

RegisterBundledFonts = function()
    if _G.MSUF_BUNDLED_FONTS_REGISTERED == true then return end

    if IsCombatLocked() then
        _MSUF_BundledMediaRegistrationPending = true
        ExportPublic("MSUF_BUNDLED_MEDIA_REGISTRATION_DEFERRED", true)
        local frame = EnsureLSMCombatFrame and EnsureLSMCombatFrame()
        if frame then
            frame:RegisterEvent("PLAYER_REGEN_ENABLED")
        end
        return
    end

    local LSM = MSUF.LSM
    if not LSM or type(LSM.Register) ~= "function" then return end
    local wasDeferred = _MSUF_BundledMediaRegistrationPending == true
        or _G.MSUF_BUNDLED_MEDIA_REGISTRATION_DEFERRED == true
    _MSUF_BundledMediaRegistrationPending = false
    ExportPublic("MSUF_BUNDLED_MEDIA_REGISTRATION_DEFERRED", nil)

    local base = "Interface/AddOns/" .. tostring(addonName) .. "/Media/Fonts/"
    local fonts = {
        { key = "EXPRESSWAY", name = "Expressway Regular (MSUF)", file = "Expressway Regular.ttf", aliases = { "Expressway (MSUF)" } },
        { key = "EXPRESSWAY_BOLD", name = "Expressway Bold (MSUF)", file = "Expressway Bold.ttf" },
        { key = "EXPRESSWAY_SEMIBOLD", name = "Expressway SemiBold (MSUF)", file = "Expressway SemiBold.ttf" },
        { key = "EXPRESSWAY_EXTRABOLD", name = "Expressway ExtraBold (MSUF)", file = "Expressway ExtraBold.ttf" },
        { key = "EXPRESSWAY_CONDENSED_LIGHT", name = "Expressway Condensed Light (MSUF)", file = "Expressway Condensed Light.otf" },
    }

    for _, info in ipairs(fonts) do
        local path = base .. info.file
        LSM:Register("font", info.key, path)
        LSM:Register("font", info.name, path)
        if type(info.aliases) == "table" then
            for i = 1, #info.aliases do
                LSM:Register("font", info.aliases[i], path)
            end
        end
    end

    --- Bundled bar/castbar textures (Media/Bars).
    --- Registered here to be load-order-safe.
    local baseBars = "Interface/AddOns/" .. tostring(addonName) .. "/Media/Bars/"
    local function Reg(name, file)
        LSM:Register("statusbar", name, baseBars .. file)
    end

    Reg("MSUF Charcoal",   "Charcoal.tga")
    Reg("MSUF Minimalist", "Minimalist.tga")
    Reg("MSUF Slickrock",  "Slickrock.tga")
    Reg("MSUF Smooth",     "MSUF_Smooth.tga")
    Reg("MSUF Smooth v2",  "Smoothv2.tga")
    Reg("MSUF Smoother",   "smoother.tga")
    Reg("Better Blizzard", "BetterBlizzard.blp")

    --- DB migration: eliminate broken legacy selections ("MSUF Flat"/"MSUF Smooth")
    local function MigrateLegacyBarKeys()
        local db = _G.MSUF_DB
        if type(db) ~= "table" or type(db.general) ~= "table" then return end
        local g = db.general
        local changed = false

        --- Migrate old Midnight texture names to new MSUF names (renaming only)
        local map = {
            ["Midnight Charcoal"] = "MSUF Charcoal",
            ["Midnight Minimalist"] = "MSUF Minimalist",
            ["Midnight Slickrock"] = "MSUF Slickrock",
            ["Midnight Smooth"] = "MSUF Smooth",
            ["Midnight Smooth v2"] = "MSUF Smooth v2",
            ["Midnight Smoother"] = "MSUF Smoother",
        }
        if type(g.barTexture) == "string" and map[g.barTexture] then
            g.barTexture = map[g.barTexture]
            changed = true
        end
        if type(g.castbarTexture) == "string" and map[g.castbarTexture] then
            g.castbarTexture = map[g.castbarTexture]
            changed = true
        end
        if g.barTexture == "MSUF Flat" then
            g.barTexture = "Solid"
            changed = true
        elseif g.barTexture == "MSUF Smooth" then
            g.barTexture = "MSUF Smooth"
            changed = true
        end

        if g.castbarTexture == "MSUF Flat" then
            g.castbarTexture = "Solid"
            changed = true
        elseif g.castbarTexture == "MSUF Smooth" then
            g.castbarTexture = "MSUF Smooth"
            changed = true
        end

        if changed then
            if type(_G.MSUF_UpdateAllBarTextures) == "function" then
                _G.MSUF_UpdateAllBarTextures()
            end
            if type(_G.MSUF_UpdateCastbarVisuals) == "function" then
                _G.MSUF_UpdateCastbarVisuals()
            end
        end
    end

    _G.C_Timer.After(0, MigrateLegacyBarKeys)

    ExportPublic("MSUF_BUNDLED_FONTS_REGISTERED", true)
    SnapshotLSMMediaCounts(LSM)
    if wasDeferred then
        RefreshFontMedia(nil, true)
        RefreshStatusbarMedia()
    end
end

ExportPublic("MSUF_RegisterBundledMediaWithLSM", RegisterBundledFonts)

--- Initial attempt (works when libs are already available)
if TryInitLSM() then
    RegisterBundledFonts()
    EnsureLSMCallbacks()
else
    --- Load-order-safe fallback: retry when other addons load / on login.
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function()
        if TryInitLSM() then
            RegisterBundledFonts()
            EnsureLSMCallbacks()
            f:UnregisterEvent("ADDON_LOADED")
            f:UnregisterEvent("PLAYER_LOGIN")
            f:SetScript("OnEvent", nil)
        end
    end)
end

--- LoD module helpers (GamePlay/etc.; castbars now load with core)

--- Export the core namespace for optional modules/sub-addons.

--- Safe helper to load a LoD sub-addon at runtime.
--- Returns true if the addon is loaded after the call.
local function MSUF_EnsureAddonLoaded(addonName)
    if type(addonName) ~= "string" or addonName == "" then
        return false
    end

    local function IsLoaded()
        if _G.C_AddOns and type(_G.C_AddOns.IsAddOnLoaded) == "function" then
            return _G.C_AddOns.IsAddOnLoaded(addonName)
        end
        if type(_G.IsAddOnLoaded) == "function" then
            return _G.IsAddOnLoaded(addonName)
        end
        return false
    end

    if IsLoaded() then
        return true
    end

    local loader
    if _G.C_AddOns and type(_G.C_AddOns.LoadAddOn) == "function" then
        loader = _G.C_AddOns.LoadAddOn
    elseif type(_G.LoadAddOn) == "function" then
        loader = _G.LoadAddOn
    end

    if type(loader) ~= "function" then
        return false
    end

    loader(addonName)
    return IsLoaded()
end

ExportPublic("MSUF_EnsureAddonLoaded", MSUF_EnsureAddonLoaded)

--- Global UI Scale (combat-safe gate)
--- Fixes: /reload in combat (or any in-combat scale apply) causing ADDON_ACTION_BLOCKED
--- by deferring Global UI scale changes until PLAYER_REGEN_ENABLED.
--- Important: We intentionally wrap MSUF_SetGlobalUiScale in-place so ANY caller becomes
--- combat-safe without needing to edit every callsite (SlashMenu / Options / etc.).
local function MSUF_InstallGlobalScaleGate()
    if _G.MSUF_GlobalScaleGateInstalled then return end
    ExportPublic("MSUF_GlobalScaleGateInstalled", true)

    local function TryWrap()
        local fn = _G.MSUF_SetGlobalUiScale
        if type(fn) ~= "function" then
            return false
        end

        --- Already wrapped?
        if _G.MSUF_SetGlobalUiScale_GATED and fn == _G.MSUF_SetGlobalUiScale_GATED then
            return true
        end

        --- Preserve raw implementation (first one wins)
        if type(_G.MSUF_SetGlobalUiScale_RAW) ~= "function" then
            ExportPublic("MSUF_SetGlobalUiScale_RAW", fn)
        end

        --- Create/ensure the deferred-apply frame once.
        if not _G.MSUF_GlobalScaleGateFrame then
            local gf = CreateFrame("Frame")
            ExportPublic("MSUF_GlobalScaleGateFrame", gf)
            gf:RegisterEvent("PLAYER_REGEN_ENABLED")
            gf:SetScript("OnEvent", function()
                local args = _G.MSUF_PendingGlobalScaleArgs
                ExportPublic("MSUF_PendingGlobalScaleArgs", nil)

                if not args then return end
                if InCombatLockdown and InCombatLockdown() then
                    --- Still not safe (edge case): keep pending.
                    ExportPublic("MSUF_PendingGlobalScaleArgs", args)
                    return
                end

                local raw = _G.MSUF_SetGlobalUiScale_RAW
                if type(raw) == "function" then
                    --- Unpack pending args and apply once after combat.
                    raw(unpack(args))
                end
            end)
        end

        --- Gate wrapper: defer in combat, else passthrough.
        local gated = function(...)
            local scale = select(1, ...)
            if scale == nil then return end

            if InCombatLockdown and InCombatLockdown() then
                --- Last-call-wins: overwrite pending args.
                ExportPublic("MSUF_PendingGlobalScaleArgs", { ... })
                return
            end

            local raw = _G.MSUF_SetGlobalUiScale_RAW
            if type(raw) == "function" then
                return raw(...)
            end
        end

        ExportPublic("MSUF_SetGlobalUiScale_GATED", gated)
        ExportPublic("MSUF_SetGlobalUiScale", gated)
        return true
    end

    --- Install immediately if possible; otherwise retry on common init events.
    if TryWrap() then return end

    if not _G.MSUF_GlobalScaleInstallFrame then
        local f = CreateFrame("Frame")
        ExportPublic("MSUF_GlobalScaleInstallFrame", f)
        f:RegisterEvent("ADDON_LOADED")
        f:RegisterEvent("PLAYER_LOGIN")
        f:RegisterEvent("PLAYER_ENTERING_WORLD")
        f:SetScript("OnEvent", function()
            if TryWrap() then
                f:UnregisterEvent("ADDON_LOADED")
                f:UnregisterEvent("PLAYER_LOGIN")
                f:UnregisterEvent("PLAYER_ENTERING_WORLD")
                f:SetScript("OnEvent", nil)
            end
        end)
    end
end

ExportPublic("MSUF_InstallGlobalScaleGate", MSUF_InstallGlobalScaleGate)

--- Ensure gate is installed as early as possible (before any C_Timer.After(0) scale applies fire).
_G.C_Timer.After(0, function()
    MSUF_InstallGlobalScaleGate()
end)

--- Auto-load Gameplay LoD addon on login when any gameplay feature is enabled.
--- (Prevents "feature looks enabled but does nothing until you toggle twice" after /reload or relog.)
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function()
        local ensureDB = _G.MSUF_EnsureDB
        if ensureDB then
            ensureDB()
        end

        local g = _G.MSUF_DB and _G.MSUF_DB.gameplay or nil
        if not g then return end

        local need = false
        if g.enableCombatTimer == true then need = true end
        if g.enableCombatStateText == true then need = true end
        if g.enableFirstDanceTimer == true then need = true end
        if g.enableCombatCrosshair == true then need = true end

        if need then
            MSUF_EnsureAddonLoaded("MidnightSimpleUnitFrames_Gameplay")

            --- Apply immediately so event wiring is active without opening the Gameplay menu.
            local ns2 = _G.MSUF_NS
            if ns2 and type(ns2.MSUF_RequestGameplayApply) == "function" then
                ns2.MSUF_RequestGameplayApply()
            elseif _G.MSUF_RequestGameplayApply then
                _G.MSUF_RequestGameplayApply()
            end
        end
    end)
end
