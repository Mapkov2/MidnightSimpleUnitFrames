-- Kernel library adapter: centralizes optional library lookup, cache, and compatibility exports.
-- Runs during boot; callers should depend on exported helpers rather than direct LibStub probes.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF = _G.MSUF or MSUF
local ExportPublic = MSUF.ExportPublic
--- The font, texture, castbar, class power and status icon owners load after
--- this file. Media can register (and in combat refresh synchronously) while
--- the core is still loading, so each refresh below resolves its owners as
--- optional and skips one that has not loaded yet.
local Optional = MSUF.Optional

local function GetLSM()
    local LSM = (MSUF and MSUF.LSM) or _G.MSUF_LSM
    if not LSM and type(_G.LibStub) == "function" then
        LSM = _G.LibStub("LibSharedMedia-3.0", true)
    end
    return LSM
end

local _MSUF_KnownFileAssetCache = {}
local _MSUF_LSMFontAssetPaths = {}
local _MSUF_FontApplyFailureSerial = tonumber(_G.MSUF_FontApplyFailureSerial) or 0
_G.MSUF_FontApplyEpoch = tonumber(_G.MSUF_FontApplyEpoch) or 0

local function MSUF_NormalizeFileAssetPath(asset)
    if type(asset) ~= "string" or asset == "" then return nil end
    return asset:gsub("/", "\\")
end

local function MSUF_FileAssetPathKey(asset)
    local normalized = MSUF_NormalizeFileAssetPath(asset)
    if not normalized then return nil end
    return normalized:lower(), normalized
end

local function MSUF_RememberLSMFontAsset(asset)
    local key, normalized = MSUF_FileAssetPathKey(asset)
    if key then
        -- The exact normalized entry is the allocation-free common lookup.
        -- The folded alias handles old/imported profiles with different case.
        _MSUF_LSMFontAssetPaths[normalized] = normalized
        _MSUF_LSMFontAssetPaths[key] = normalized
    end
    return normalized
end

local function MSUF_GetRegisteredLSMFontPath(asset)
    if type(asset) ~= "string" or asset == "" then return nil end
    local registered = _MSUF_LSMFontAssetPaths[asset]
    if registered then return registered end
    local key, normalized = MSUF_FileAssetPathKey(asset)
    if not key then return nil end
    return _MSUF_LSMFontAssetPaths[normalized] or _MSUF_LSMFontAssetPaths[key]
end

local function MSUF_IsRegisteredLSMFontPath(asset)
    return MSUF_GetRegisteredLSMFontPath(asset) ~= nil
end

local function MSUF_FileAssetPathsEqual(a, b)
    local aKey = MSUF_FileAssetPathKey(a)
    local bKey = MSUF_FileAssetPathKey(b)
    return aKey ~= nil and bKey ~= nil and aKey == bKey
end

local function MSUF_SeedLSMFontAssets(lsm)
    if not (lsm and type(lsm.HashTable) == "function") then return end
    local fonts = lsm:HashTable("font")
    if type(fonts) ~= "table" then return end
    for _, path in pairs(fonts) do
        MSUF_RememberLSMFontAsset(path)
    end
end

local function MSUF_GetLSMFontAsset(lsm, key)
    if not lsm or type(key) ~= "string" or key == "" then return nil end
    local path
    if type(lsm.HashTable) == "function" then
        local fonts = lsm:HashTable("font")
        if type(fonts) == "table" then path = fonts[key] end
    end
    if not path and type(lsm.Fetch) == "function" then
        path = lsm:Fetch("font", key, true)
    end
    return MSUF_RememberLSMFontAsset(path)
end

local function MSUF_FontApplicationMatches(fs, expectedPath, expectedSize)
    if not fs or type(fs.GetFont) ~= "function" then return true end
    local actualPath, actualSize = fs:GetFont()
    if not MSUF_FileAssetPathsEqual(expectedPath, actualPath) then return false end
    actualSize, expectedSize = tonumber(actualSize), tonumber(expectedSize)
    return actualSize ~= nil and expectedSize ~= nil and math.abs(actualSize - expectedSize) <= 0.01
end

local function MSUF_ApplyFontScaleAnimationMode(fs, flags)
    if not (fs and type(fs.SetScaleAnimationMode) == "function") then return end
    local modes = _G.FontStringScaleAnimationMode
    if type(modes) ~= "table" then return end
    local useSlug = type(flags) == "string" and flags:upper():find("SLUG", 1, true) ~= nil
    local mode = useSlug and modes.Vertex or modes.FontSize
    if mode == nil or fs._msufFontScaleAnimationMode == mode then return end
    fs.SetScaleAnimationMode(fs, mode)
    do
fs._msufFontScaleAnimationMode = mode
end
end

--- SetFont validates assets/arguments natively; native errors propagate. On
--- the Mainline family (Midnight, WoW Forever) an unavailable asset returns
--- false, so the caller's fallback font runs. On Classic clients the return
--- value and immediate readback are no synchronous readiness guarantee on a
--- cold client: success is reported and readiness stays with the caller and
--- the font coordinator.
local SETFONT_RESULT_IS_READY = MSUF.Client ~= nil and MSUF.Client.Family == "Mainline"
local function MSUF_SetFontChecked(fs, path, size, flags)
    local accepted = fs:SetFont(path, size, flags or "")
    if SETFONT_RESULT_IS_READY then return accepted ~= false end
    return true
end

local function MSUF_ClearFontStringApplyCaches(fs)
    if not fs then return end
    fs._msufFontAppliedPath = nil
    fs._msufFontAppliedSize = nil
    fs._msufFontAppliedFlags = nil
    fs._msufFontAppliedEpoch = nil
    fs._msufFontRequestPath = nil
    fs._msufFontRequestSize = nil
    fs._msufFontRequestFlags = nil
    fs._msufFontRequestAppliedPath = nil
    fs._msufFontRequestEpoch = nil
    fs._msufFontSource = nil
    fs._msufFontRev = nil
    fs._msufFontEpoch = nil
    fs._msufFont = nil
    fs._msufFontSize = nil
    fs._msufFontFlags = nil
    fs._msufFontAttemptEpoch = nil
    fs._msufTextFontEpoch = nil
    fs._msufStatusFont = nil
    fs._msufStatusFontSize = nil
    fs._msufStatusFontFlags = nil
    fs._msufStatusFontEpoch = nil
    fs._msufStatusFontAttemptEpoch = nil
    fs._msufCastbarFontEpoch = nil
    fs._msufFontScaleAnimationMode = nil
end

local function MSUF_MarkFontApplyFailed()
    _MSUF_FontApplyFailureSerial = _MSUF_FontApplyFailureSerial + 1
    _G.MSUF_FontApplyFailureSerial = _MSUF_FontApplyFailureSerial
    local notify = _G.MSUF_OnFontApplyFailed
    if type(notify) == "function" then notify(_MSUF_FontApplyFailureSerial) end
    return _MSUF_FontApplyFailureSerial
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
ExportPublic("MSUF_GetRegisteredLSMFontPath", MSUF_GetRegisteredLSMFontPath)
ExportPublic("MSUF_IsRegisteredLSMFontPath", MSUF_IsRegisteredLSMFontPath)
ExportPublic("MSUF_FontApplicationMatches", MSUF_FontApplicationMatches)
ExportPublic("MSUF_ApplyFontScaleAnimationMode", MSUF_ApplyFontScaleAnimationMode)
ExportPublic("MSUF_ClearFontStringApplyCaches", MSUF_ClearFontStringApplyCaches)
ExportPublic("MSUF_SetFontChecked", MSUF_SetFontChecked)
ExportPublic("MSUF_MarkFontApplyFailed", MSUF_MarkFontApplyFailed)
MSUF.Util = MSUF.Util or {}
MSUF.Util.IsKnownFileAsset = MSUF.Util.IsKnownFileAsset or MSUF_IsKnownFileAsset

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
local _MSUF_StatusIconMediaRefreshPending = false
local _MSUF_FontMediaRefreshPending = false
local _MSUF_BundledMediaRegistrationPending = false

local RegisterBundledFonts

local function IsCombatLocked()
    return (type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown()) and true or false
end

local function RunStatusbarMediaRefresh()
    _MSUF_StatusbarMediaRefreshPending = false

    local clearTextureCache = Optional("MSUF_ClearResolvedStatusbarTextureCache")
    if clearTextureCache then clearTextureCache() end

    local updateBars = _G.MSUF_UpdateAllBarTextures_Immediate or _G.MSUF_UpdateAllBarTextures
    if type(updateBars) == "function" then updateBars() end

    local updateAbsorb = Optional("MSUF_UpdateAbsorbBarTextures")
    if updateAbsorb then updateAbsorb() end

    local updateCastbars = _G.MSUF_UpdateCastbarTextures_Immediate or _G.MSUF_UpdateCastbarTextures
    if type(updateCastbars) == "function" then updateCastbars() end

    local refreshClassPower = Optional("MSUF_ClassPower_RefreshTextures")
    if refreshClassPower then refreshClassPower() end

end

local function RunStatusIconMediaRefresh()
    _MSUF_StatusIconMediaRefreshPending = false

    local refreshPacks = Optional("MSUF_RefreshStatusIconPacks")
    if refreshPacks then refreshPacks() end

    local refreshIcons = Optional("MSUF_RequestStatusIconsRefreshForCurrent")
    if refreshIcons then refreshIcons() end

end

local function RunFontMediaRefresh()
    _MSUF_FontMediaRefreshPending = false
    local recoverFonts = Optional("MSUF_RequestFontRecovery")
    if recoverFonts then
        recoverFonts("LSM_FONT_REGISTERED")
        return
    end
    local updateFonts = Optional("MSUF_UpdateAllFonts_Immediate") or Optional("MSUF_UpdateAllFonts")
    if updateFonts then updateFonts() end
end

local function RefreshMediaGroupVisuals(statusbars)
    local gf = (_G.MSUF_NS and _G.MSUF_NS.GF) or (MSUF and MSUF.GF)
    if gf and type(gf.InvalidateConfCache) == "function" then gf.InvalidateConfCache() end
    if gf and type(gf.RefreshVisuals) == "function" then
        gf.RefreshVisuals(nil, not statusbars and gf.DIRTY_VISUAL or nil)
    else
        local refresh = statusbars and _G.MSUF_GF_RefreshOverlays or _G.MSUF_GF_RefreshVisuals
        if type(refresh) == "function" then refresh() end
    end
end

-- One coalesced flush owns all changed media kinds, and it is the only combat
-- deferral for media: the LibSharedMedia callback stays registered for the whole
-- session and records what changed through the pending flags; while the player
-- is in combat the flush parks behind one PLAYER_REGEN_ENABLED listener and runs
-- once afterwards. Flags are cleared by each owner before it calls consumers.
local mediaRefreshFrame
local mediaRefreshQueued = false
local function FlushMediaRefresh()
    mediaRefreshQueued = false
    if IsCombatLocked() then
        mediaRefreshQueued = true
        if not mediaRefreshFrame then
            mediaRefreshFrame = _G.CreateFrame("Frame")
            mediaRefreshFrame:SetScript("OnEvent", FlushMediaRefresh)
        end
        mediaRefreshFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    if mediaRefreshFrame then mediaRefreshFrame:UnregisterEvent("PLAYER_REGEN_ENABLED") end
    -- Bundled media that could not register in combat; it raises its own flags.
    if _MSUF_BundledMediaRegistrationPending then RegisterBundledFonts() end
    local statusbars, icons = _MSUF_StatusbarMediaRefreshPending, _MSUF_StatusIconMediaRefreshPending
    if statusbars then RunStatusbarMediaRefresh() end
    if icons then RunStatusIconMediaRefresh() end
    if statusbars or icons then RefreshMediaGroupVisuals(statusbars) end
    if _MSUF_FontMediaRefreshPending then RunFontMediaRefresh() end
end

local function ScheduleMediaRefresh()
    if mediaRefreshQueued then return end
    if IsCombatLocked() then FlushMediaRefresh(); return end
    mediaRefreshQueued = true
    if _G.MSUF_ScheduleOnce then
        _G.MSUF_ScheduleOnce("LSM_MEDIA_REFRESH", FlushMediaRefresh)
    else
        _G.C_Timer.After(0, FlushMediaRefresh)
    end
end

--- Menu2 lists LibSharedMedia fonts live when a font dropdown opens, so a newly
--- registered font needs no choice-list rebuild here.
local function RefreshFontMedia(key, forceApply, registeredPath)
    local needsFontRefresh = forceApply == true
    if not needsFontRefresh and key ~= nil then
        local normalizeFontKey = _G.MSUF_NormalizeFontKey
        local general = _G.MSUF_DB and _G.MSUF_DB.general
        local configured = general and general.fontKey
        needsFontRefresh = configured ~= nil
            and (normalizeFontKey(configured) == normalizeFontKey(key)
                or MSUF_FileAssetPathsEqual(configured, registeredPath))
    end
    if needsFontRefresh then
        _MSUF_FontMediaRefreshPending = true
        ScheduleMediaRefresh()
    end
end

local function RefreshStatusbarMedia()
    _MSUF_StatusbarMediaRefreshPending = true
    ScheduleMediaRefresh()
end

local function RefreshStatusIconMedia()
    _MSUF_StatusIconMediaRefreshPending = true
    ScheduleMediaRefresh()
end

--- Every registration is handled the same way, in or out of combat: the refresh
--- requests below park behind the flush's single combat listener, so media a
--- mod registers mid-combat is applied once, right after combat.
local function OnLSMRegistered(_, mediatype, key)
    if mediatype == "font" then
        -- The registered path is recorded first: registered media is cold-path
        -- metadata and lets the refresh bypass a stale negative file probe. A
        -- font that arrives in combat refreshes unconditionally afterwards.
        RefreshFontMedia(key, IsCombatLocked(), MSUF_GetLSMFontAsset(MSUF.LSM, key))
    elseif mediatype == "statusbar" then
        RefreshStatusbarMedia()
        RefreshStatusIconMedia()
    elseif mediatype == "background" or mediatype == "msuf_statusicon" then
        RefreshStatusIconMedia()
    end
end

local function EnsureLSMCallbacks()
    local LSM = MSUF.LSM
    if not LSM then return end
    MSUF_SeedLSMFontAssets(LSM)
    ExportPublic("MSUF_LSM_CallbacksRegistered", true)
    LSM.RegisterCallback(LSM_CALLBACK_OWNER, LSM_REGISTERED_EVENT, OnLSMRegistered)
end

--- Shared statusbar texture choices for Menu2 dropdowns.
--- Returns LibSharedMedia entries with a texture path so the native dropdown can
--- render a small statusbar preview for every texture.
local FALLBACK_STATUSBAR_TEXTURES = {
    { key = "Blizzard",      path = "Interface\\TargetingFrame\\UI-StatusBar" },
    { key = "Solid",         path = "Interface\\Buttons\\WHITE8X8" },
    { key = "MSUF Lucent",   path = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Bars\\MSUF_Lucent_v2.tga" },
    { key = "Flat",          path = "Interface\\Buttons\\WHITE8x8" },
    { key = "RaidHP",        path = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
    { key = "RaidPower",     path = "Interface\\RaidFrame\\Raid-Bar-Resource-Fill" },
    { key = "Skills",        path = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar" },
    { key = "Outline",       path = "Interface\\Tooltips\\UI-Tooltip-Background" },
    { key = "TooltipBorder", path = "Interface\\Tooltips\\UI-Tooltip-Border" },
    { key = "DialogBG",      path = "Interface\\DialogFrame\\UI-DialogBox-Background" },
    { key = "Parchment",     path = "Interface\\AchievementFrame\\UI-Achievement-StatsBackground" },
}

local GetStatusbarLSM = GetLSM

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
        texturePreview = texture,
        previewKind = "statusbar",
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

--- Bundled fonts (Media/Fonts)

RegisterBundledFonts = function()
    if _G.MSUF_BUNDLED_FONTS_REGISTERED == true then return end

    if IsCombatLocked() then
        _MSUF_BundledMediaRegistrationPending = true
        ExportPublic("MSUF_BUNDLED_MEDIA_REGISTRATION_DEFERRED", true)
        -- Parks the media flush behind PLAYER_REGEN_ENABLED; it registers the bundle.
        ScheduleMediaRefresh()
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
        { key = "SOUNDSCAPE", name = "Fritz Soundscape", file = "Fritz Soundscape.ttf" },
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
    Reg("MSUF Lucent",     "MSUF_Lucent_v2.tga")
    Reg("MSUF Minimalist", "Minimalist.tga")
    Reg("MSUF Slickrock",  "Slickrock.tga")
    Reg("MSUF Smooth",     "MSUF_Smooth.tga")
    Reg("MSUF Smooth v2",  "Smoothv2.tga")
    Reg("MSUF Smoother",   "smoother.tga")
    Reg("MSUF Arcane Pulse",   "MSUF_ArcanePulse.tga")
    Reg("MSUF Aurora Silk",    "MSUF_AuroraSilk.tga")
    Reg("MSUF Deep Current",   "MSUF_DeepCurrent.tga")
    Reg("MSUF Dragon Scale",   "MSUF_DragonScale.tga")
    Reg("MSUF Ember Weave",    "MSUF_EmberWeave.tga")
    Reg("MSUF Forged Steel",   "MSUF_ForgedSteel.tga")
    Reg("MSUF Frosted Quartz", "MSUF_FrostedQuartz.tga")
    Reg("MSUF Lunar Mist",     "MSUF_LunarMist.tga")
    Reg("MSUF Obsidian Glass", "MSUF_ObsidianGlass.tga")
    Reg("MSUF Runic Circuit",  "MSUF_RunicCircuit.tga")
    --- Bar art contributed by Aur0r4 (bundled with permission).
    Reg("MSUF Dreamy",            "MSUF_Dreamy.tga")
    Reg("MSUF Dreamy Soft",       "MSUF_DreamySoft.tga")
    Reg("MSUF Dreamy Ultra Soft", "MSUF_DreamyUltraSoft.tga")
    Reg("MSUF Foggy",             "MSUF_Foggy.tga")
    Reg("MSUF Glass",             "MSUF_Glass.tga")
    Reg("MSUF Mirrored Glass",    "MSUF_MirroredGlass.tga")
    Reg("Better Blizzard", "BetterBlizzard.blp")

    ExportPublic("MSUF_BUNDLED_FONTS_REGISTERED", true)
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

--- Compatibility hook retained for older callers. The current scale owner in
--- Runtime/MSUF_UIScaleRuntime.lua is itself combat-safe and creates a PLAYER_REGEN_ENABLED
--- watcher only while an apply is pending, so a second permanent gate/frame is
--- unnecessary.
local function MSUF_InstallGlobalScaleGate()
    return Optional("MSUF_SetGlobalUiScale") ~= nil
end

ExportPublic("MSUF_InstallGlobalScaleGate", MSUF_InstallGlobalScaleGate)

-- Font flags have one owner for unit/group compilation, runtime and Options.
local function MSUF_ComposeFontFlags(outline, monochrome, slug)
    local flags = ""
    outline = tostring(outline or "OUTLINE"):upper()
    if slug == true then
        return (outline == "NONE" or outline == "") and "SLUG" or "OUTLINE,SLUG"
    end
    if outline == "THICKOUTLINE" then
        flags = "THICKOUTLINE"
    elseif outline ~= "NONE" and outline ~= "" then
        flags = "OUTLINE"
    end
    if monochrome == true then
        flags = flags ~= "" and (flags .. ",MONOCHROME") or "MONOCHROME"
    end
    return flags
end
ExportPublic("MSUF_ComposeFontFlags", MSUF_ComposeFontFlags)

ExportPublic("MSUF_GetSharedMedia", GetLSM)
