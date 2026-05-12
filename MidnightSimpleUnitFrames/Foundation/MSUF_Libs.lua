local addonName, ns = ...
ns = ns or {}

-- WoW 12.0.5+ can throw hard errors when SetFont receives a missing asset.
-- Keep one early global guard so LSM entries from disabled/missing media addons
-- cannot break Edit Mode, previews, or runtime text refresh.
do
    local FALLBACK_FONT = "Fonts\\FRIZQT__.TTF"
    local EXPRESSWAY_BOLD_FONT = "Interface\\AddOns\\" .. tostring(addonName or "MidnightSimpleUnitFrames") .. "\\Media\\Fonts\\Expressway Bold.ttf"
    local VISUAL_SAMPLE = "AaBbCcWwMmIi 0123456789 - Midnight Simple Unit Frames"
    local FONT_ALIASES = {
        ["interface\\addons\\midnightsimpleunitframes\\media\\fonts\\expressway.ttf"] = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Fonts\\Expressway Regular.ttf",
        ["interface\\addons\\midnightsimpleunitframes\\media\\fonts\\expressway regular.ttf"] = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Fonts\\Expressway Regular.ttf",
    }
    local _probeFrame, _probeFS, _probeFS2
    local _fontPathCache = {}
    local _visualOverrideCache = {}
    local PathLooksLikeBundledExpressway
    local PrewarmInternalFontVisualCache
    local ScheduleFontVisualPrewarm
    local _fontPrewarmScheduled = false

    local function IsCombatLocked()
        if _G.MSUF_InCombat == true then return true end
        return (type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown()) and true or false
    end

    local function NormalizeFontFlags(flags)
        if type(flags) ~= "string" then return "" end
        flags = flags:gsub("^[%s,]+", ""):gsub("[%s,]+$", "")
        if flags == "NONE" then return "" end
        if flags:find(",", 1, true) or flags:find("%s") then
            flags = flags:gsub("%s*,%s*", ","):gsub(",+", ",")
            flags = flags:gsub("^[%s,]+", ""):gsub("[%s,]+$", "")
        end
        return flags
    end

    local function NormalizeFontPath(path)
        if type(path) ~= "string" or path == "" then return nil end
        local key = path:gsub("/", "\\"):lower()
        return FONT_ALIASES[key] or path
    end

    local function FontPathKey(path)
        if type(path) ~= "string" or path == "" then return nil end
        return path:gsub("/", "\\"):lower()
    end

    local FONT_EQUIV = {
        ["fonts\\frizqt__.ttf"] = "friz",
        ["fonts\\frizqt___cyr.ttf"] = "friz",
        ["fonts\\arialn.ttf"] = "arial",
        ["fonts\\morpheus.ttf"] = "morpheus",
        ["fonts\\morpheus_cyr.ttf"] = "morpheus",
        ["fonts\\skurri.ttf"] = "skurri",
        ["fonts\\skurri_cyr.ttf"] = "skurri",
    }

    local function FontPathMatches(requested, actual)
        local want = FontPathKey(NormalizeFontPath(requested))
        local got = FontPathKey(NormalizeFontPath(actual))
        if not want or not got then return false end
        if want == got then return true end
        local wantGroup = FONT_EQUIV[want]
        return wantGroup ~= nil and wantGroup == FONT_EQUIV[got]
    end

    local function FontPathEquals(requested, actual)
        local want = FontPathKey(NormalizeFontPath(requested))
        local got = FontPathKey(NormalizeFontPath(actual))
        return want ~= nil and want == got
    end

    local INTERNAL_FONT_PATH_KEYS = {
        ["fonts\\frizqt__.ttf"] = "FRIZQT",
        ["fonts\\frizqt___cyr.ttf"] = "FRIZQT",
        ["fonts\\arialn.ttf"] = "ARIALN",
        ["fonts\\morpheus.ttf"] = "MORPHEUS",
        ["fonts\\morpheus_cyr.ttf"] = "MORPHEUS",
        ["fonts\\skurri.ttf"] = "SKURRI",
        ["fonts\\skurri_cyr.ttf"] = "SKURRI",
    }

    local INTERNAL_FONT_CANDIDATES = {
        FRIZQT = {
            globals = { "STANDARD_TEXT_FONT" },
            objects = { "GameFontNormal", "GameFontHighlight", "GameFontHighlightSmall", "SystemFont_Shadow_Med1" },
            paths = { "Fonts\\FRIZQT__.TTF", "Fonts\\FRIZQT___CYR.TTF" },
        },
        ARIALN = {
            globals = { "UNIT_NAME_FONT", "NAMEPLATE_FONT" },
            objects = { "SystemFont_NamePlate", "SystemFont_NamePlateCastBar", "NumberFontNormalSmall" },
            paths = { "Fonts\\ARIALN.TTF" },
        },
        MORPHEUS = {
            globals = { "QUEST_TEXT_FONT" },
            objects = { "QuestFont", "QuestFont_Large", "QuestFont_Enormous" },
            paths = { "Fonts\\MORPHEUS_CYR.TTF", "Fonts\\MORPHEUS.TTF" },
        },
        SKURRI = {
            globals = { "DAMAGE_TEXT_FONT" },
            objects = { "CombatTextFont", "NumberFontNormal", "NumberFontNormalLarge", "SystemFont_Shadow_Huge1" },
            paths = { "Fonts\\SKURRI_CYR.TTF", "Fonts\\SKURRI.TTF" },
        },
    }

    local function NormalizeInternalFontKey(key, path)
        if type(_G.MSUF_NormalizeFontKey) == "function" and type(key) == "string" and key ~= "" then
            key = _G.MSUF_NormalizeFontKey(key)
        end
        if type(key) == "string" then
            key = key:upper()
            if INTERNAL_FONT_CANDIDATES[key] then return key end
        end
        return INTERNAL_FONT_PATH_KEYS[FontPathKey(path)] or nil
    end

    local function InternalPathMatchesKey(key, path)
        local info = key and INTERNAL_FONT_CANDIDATES[key]
        if not (info and info.paths) then return false end
        for i = 1, #info.paths do
            if FontPathMatches(info.paths[i], path) then return true end
        end
        return false
    end

    local function AddUniquePath(list, seen, path)
        path = NormalizeFontPath(path)
        if type(path) ~= "string" or path == "" then return end
        local pathKey = FontPathKey(path)
        if seen[pathKey] then return end
        seen[pathKey] = true
        list[#list + 1] = path
    end

    local function AddFontObjectPath(list, seen, objectName, key)
        local obj = type(objectName) == "string" and _G[objectName] or objectName
        if not (obj and type(obj.GetFont) == "function") then return end
        local ok, path = pcall(obj.GetFont, obj)
        if ok and ((not key) or InternalPathMatchesKey(key, path)) then
            if PathLooksLikeBundledExpressway and PathLooksLikeBundledExpressway(key, path, 14, "") then
                return
            end
            AddUniquePath(list, seen, path)
        end
    end

    local function BuildInternalFontPathCandidates(key, path)
        key = NormalizeInternalFontKey(key, path)
        if not key then return nil end
        local info = INTERNAL_FONT_CANDIDATES[key]
        if not info then return nil end

        local list, seen, deferred, deferredSeen = {}, {}, {}, {}
        local function AddCandidate(p)
            if not InternalPathMatchesKey(key, p) then return end
            if PathLooksLikeBundledExpressway and PathLooksLikeBundledExpressway(key, p, 14, "") then
                AddUniquePath(deferred, deferredSeen, p)
            else
                AddUniquePath(list, seen, p)
            end
        end

        if InternalPathMatchesKey(key, path) then
            AddCandidate(path)
        end
        if info.globals then
            for i = 1, #info.globals do
                AddCandidate(_G[info.globals[i]])
            end
        end
        if info.objects then
            for i = 1, #info.objects do
                AddFontObjectPath(list, seen, info.objects[i], key)
            end
        end
        if info.paths then
            for i = 1, #info.paths do
                AddCandidate(info.paths[i])
            end
        end
        for i = 1, #deferred do
            AddUniquePath(list, seen, deferred[i])
        end
        return list, key
    end

    local function GetProbeFS()
        if _probeFS then return _probeFS end
        if type(CreateFrame) ~= "function" then return nil end
        _probeFrame = _probeFrame or CreateFrame("Frame", "MSUF_FontProbeFrame", UIParent)
        if _probeFrame and _probeFrame.Hide then _probeFrame:Hide() end
        if _probeFrame and _probeFrame.CreateFontString then
            _probeFS = _probeFrame:CreateFontString(nil, "OVERLAY")
            if _probeFS and _probeFS.Hide then _probeFS:Hide() end
        end
        return _probeFS
    end

    local function GetProbeFS2()
        if _probeFS2 then return _probeFS2 end
        if not GetProbeFS() then return nil end
        if _probeFrame and _probeFrame.CreateFontString then
            _probeFS2 = _probeFrame:CreateFontString(nil, "OVERLAY")
            if _probeFS2 and _probeFS2.Hide then _probeFS2:Hide() end
        end
        return _probeFS2
    end

    local function TrySetFont(fs, path, size, flags)
        if not (fs and type(fs.SetFont) == "function" and path and size) then return false end
        local ok, applied = pcall(fs.SetFont, fs, path, size, flags)
        if not ok or applied == false then return false end
        if type(fs.GetFont) == "function" then
            local okGet, actual = pcall(fs.GetFont, fs)
            if okGet and actual then
                return FontPathMatches(path, actual)
            end
        end
        return true
    end

    local function MeasureFontWidth(fs, path, size, flags)
        if not (fs and type(fs.SetText) == "function" and type(fs.GetStringWidth) == "function") then return nil end
        if not TrySetFont(fs, path, size, flags) then return nil end
        fs:SetText(VISUAL_SAMPLE)
        local ok, width = pcall(fs.GetStringWidth, fs)
        width = ok and tonumber(width) or nil
        return width and width > 0 and width or nil
    end

    PathLooksLikeBundledExpressway = function(key, path, size, flags)
        key = NormalizeInternalFontKey(key, path)
        if not (key and InternalPathMatchesKey(key, path)) then return false end
        local pathKey = FontPathKey(path)
        if not pathKey then return false end
        if pathKey:find("interface\\addons\\midnightsimpleunitframes\\media\\fonts\\expressway", 1, true) then
            return true
        end

        size = tonumber(size) or 14
        flags = NormalizeFontFlags(flags)
        local cacheKey = tostring(key) .. "|" .. pathKey .. "|" .. tostring(size) .. "|" .. flags
        local cached = _visualOverrideCache[cacheKey]
        if cached ~= nil then return cached end
        if IsCombatLocked() then return false end

        local a = GetProbeFS()
        local b = GetProbeFS2()
        local w1 = MeasureFontWidth(a, path, size, flags)
        local w2 = MeasureFontWidth(b, EXPRESSWAY_BOLD_FONT, size, flags)
        local same = (w1 ~= nil and w2 ~= nil and math.abs(w1 - w2) <= 0.05) and true or false
        _visualOverrideCache[cacheKey] = same
        return same
    end

    local function TryFontObjectFallback(fs, key, size, flags)
        local info = key and INTERNAL_FONT_CANDIDATES[key]
        if not (info and info.objects and fs) then return false end
        if type(fs.SetFontObject) ~= "function" and type(fs.CopyFontObject) ~= "function" then return false end

        for i = 1, #info.objects do
            local objectName = info.objects[i]
            local obj = _G[objectName]
            if obj then
                local okObject
                if type(fs.SetFontObject) == "function" then
                    okObject = pcall(fs.SetFontObject, fs, obj)
                    if (not okObject) and type(objectName) == "string" then
                        okObject = pcall(fs.SetFontObject, fs, objectName)
                    end
                else
                    okObject = pcall(fs.CopyFontObject, fs, obj)
                end
                if okObject then
                    local actual
                    if type(fs.GetFont) == "function" then
                        local okGet, fontPath = pcall(fs.GetFont, fs)
                        if okGet then actual = fontPath end
                    end
                    if actual and FontPathMatches(info.paths and info.paths[1], actual) then
                        if TrySetFont(fs, actual, size, flags) or (flags ~= "" and TrySetFont(fs, actual, size, "")) then
                            return true, actual, "fontObject:" .. tostring(objectName)
                        end
                        if type(fs.SetTextHeight) == "function" then
                            pcall(fs.SetTextHeight, fs, size)
                        end
                        return true, actual, "fontObject:" .. tostring(objectName)
                    end
                end
            end
        end
        return false
    end

    function _G.MSUF_NormalizeFontFlags(flags)
        return NormalizeFontFlags(flags)
    end

    function _G.MSUF_NormalizeFontPath(path)
        return NormalizeFontPath(path)
    end

    function _G.MSUF_FontPathMatches(requested, actual)
        return FontPathMatches(requested, actual)
    end

    function _G.MSUF_FontPathEquals(requested, actual)
        return FontPathEquals(requested, actual)
    end

    function _G.MSUF_FontLooksLikeBundledExpressway(key, path, size, flags)
        return PathLooksLikeBundledExpressway(key, path, size or 14, flags or "")
    end

    function _G.MSUF_GetInternalFontPathCandidates(key, path)
        local candidates = BuildInternalFontPathCandidates(key, path)
        return candidates
    end

    function _G.MSUF_ClearResolvedFontPathCache()
        for k in pairs(_fontPathCache) do
            _fontPathCache[k] = nil
        end
        if not IsCombatLocked() then
            for k in pairs(_visualOverrideCache) do
                _visualOverrideCache[k] = nil
            end
        end
        if ScheduleFontVisualPrewarm then
            ScheduleFontVisualPrewarm(IsCombatLocked() and 1 or 0)
        end
    end

    function _G.MSUF_ResolveFontPath(path, size, flags)
        size = tonumber(size) or 12
        if size <= 0 then size = 12 end
        flags = NormalizeFontFlags(flags)

        local normalized = NormalizeFontPath(path)
        local cacheKey = tostring(normalized or "") .. "|" .. tostring(flags)
        local cached = _fontPathCache[cacheKey]
        if cached then return cached end

        local candidates = {}
        local seen = {}
        local function Add(p)
            p = NormalizeFontPath(p)
            if type(p) ~= "string" or p == "" or seen[p] then return end
            seen[p] = true
            candidates[#candidates + 1] = p
        end
        local function AddGameFontAlternates(p)
            local key = FontPathKey(p)
            if key == "fonts\\frizqt__.ttf" then
                Add("Fonts\\FRIZQT___CYR.TTF")
            elseif key == "fonts\\frizqt___cyr.ttf" then
                Add("Fonts\\FRIZQT__.TTF")
            elseif key == "fonts\\morpheus.ttf" then
                Add("Fonts\\MORPHEUS_CYR.TTF")
            elseif key == "fonts\\morpheus_cyr.ttf" then
                Add("Fonts\\MORPHEUS.TTF")
            elseif key == "fonts\\skurri.ttf" then
                Add("Fonts\\SKURRI_CYR.TTF")
            elseif key == "fonts\\skurri_cyr.ttf" then
                Add("Fonts\\SKURRI.TTF")
            end
        end

        local requestedInternalKey = NormalizeInternalFontKey(nil, normalized)
        if not requestedInternalKey then
            Add(normalized)
        end
        local internalCandidates
        internalCandidates, requestedInternalKey = BuildInternalFontPathCandidates(requestedInternalKey, normalized)
        if internalCandidates then
            for i = 1, #internalCandidates do
                Add(internalCandidates[i])
            end
        end
        AddGameFontAlternates(normalized)
        if not requestedInternalKey then
            Add(FALLBACK_FONT)
            Add("Fonts\\ARIALN.TTF")
            Add(STANDARD_TEXT_FONT)
        end

        if IsCombatLocked() then
            local fast = candidates[1] or normalized or NormalizeFontPath(FALLBACK_FONT)
            _fontPathCache[cacheKey] = fast
            return fast
        end

        local probe = GetProbeFS()
        if probe then
            for i = 1, #candidates do
                local p = candidates[i]
                if TrySetFont(probe, p, size, flags) or (flags ~= "" and TrySetFont(probe, p, size, "")) then
                    _fontPathCache[cacheKey] = p
                    return p
                end
            end
        end

        if requestedInternalKey and normalized then
            _fontPathCache[cacheKey] = normalized
            return normalized
        end

        local fallback = NormalizeFontPath(FALLBACK_FONT)
        _fontPathCache[cacheKey] = fallback
        return fallback
    end

    function _G.MSUF_SetFontSafe(fs, path, size, flags, fontKey)
        size = tonumber(size) or 12
        if size <= 0 then size = 12 end
        flags = NormalizeFontFlags(flags)
        path = NormalizeFontPath(path) or NormalizeFontPath(FALLBACK_FONT)

        local candidates, internalKey = BuildInternalFontPathCandidates(fontKey, path)
        if not candidates then
            candidates = { path }
        end

        local resolved = _G.MSUF_ResolveFontPath(path, size, flags)
        if resolved and ((not internalKey) or InternalPathMatchesKey(internalKey, resolved)) then
            local seen = {}
            for i = 1, #candidates do
                seen[FontPathKey(candidates[i])] = true
            end
            AddUniquePath(candidates, seen, resolved)
        end

        for i = 1, #candidates do
            local p = candidates[i]
            if TrySetFont(fs, p, size, flags) or (flags ~= "" and TrySetFont(fs, p, size, "")) then
                return true, p, "path"
            end
        end

        local okObject, objectPath, objectSource = TryFontObjectFallback(fs, internalKey, size, flags)
        if okObject then return true, objectPath, objectSource end

        local fallback = _G.MSUF_ResolveFontPath(FALLBACK_FONT, size, flags) or FALLBACK_FONT
        if TrySetFont(fs, fallback, size, flags) or (flags ~= "" and TrySetFont(fs, fallback, size, "")) then
            return true, fallback, "fallback"
        end

        return false, path, "failed"
    end

    PrewarmInternalFontVisualCache = function()
        _fontPrewarmScheduled = false
        if IsCombatLocked() then
            if ScheduleFontVisualPrewarm then
                ScheduleFontVisualPrewarm(1)
            end
            return false
        end

        for key, info in pairs(INTERNAL_FONT_CANDIDATES) do
            if info.globals then
                for i = 1, #info.globals do
                    PathLooksLikeBundledExpressway(key, _G[info.globals[i]], 14, "")
                end
            end
            if info.objects then
                for i = 1, #info.objects do
                    local obj = _G[info.objects[i]]
                    if obj and type(obj.GetFont) == "function" then
                        local ok, p = pcall(obj.GetFont, obj)
                        if ok then
                            PathLooksLikeBundledExpressway(key, p, 14, "")
                        end
                    end
                end
            end
            if info.paths then
                for i = 1, #info.paths do
                    local p = info.paths[i]
                    PathLooksLikeBundledExpressway(key, p, 14, "")
                    _G.MSUF_ResolveFontPath(p, 14, "")
                    _G.MSUF_ResolveFontPath(p, 14, "OUTLINE")
                    _G.MSUF_ResolveFontPath(p, 14, "THICKOUTLINE")
                end
            end
        end
        return true
    end

    ScheduleFontVisualPrewarm = function(delay)
        if _fontPrewarmScheduled then return end
        _fontPrewarmScheduled = true
        delay = tonumber(delay) or 0
        if _G.C_Timer and _G.C_Timer.After then
            _G.C_Timer.After(delay, PrewarmInternalFontVisualCache)
        elseif not IsCombatLocked() then
            PrewarmInternalFontVisualCache()
        else
            _fontPrewarmScheduled = false
        end
    end

    _G.MSUF_PrewarmFontVisualCache = PrewarmInternalFontVisualCache

    function _G.MSUF_DebugFontProbe(key)
        local fontKey = NormalizeInternalFontKey(key, key) or key
        local path
        if type(_G.MSUF_GetFontPathForKey) == "function" then
            path = _G.MSUF_GetFontPathForKey(key)
        elseif INTERNAL_FONT_CANDIDATES[fontKey] and INTERNAL_FONT_CANDIDATES[fontKey].paths then
            path = INTERNAL_FONT_CANDIDATES[fontKey].paths[1]
        else
            path = key
        end
        local probe = GetProbeFS()
        local ok, appliedPath, source = _G.MSUF_SetFontSafe(probe, path, 14, "", fontKey)
        local actual
        if probe and type(probe.GetFont) == "function" then
            local okGet, got = pcall(probe.GetFont, probe)
            if okGet then actual = got end
        end
        local expresswayOverridePath
        local info = INTERNAL_FONT_CANDIDATES[fontKey]
        if info and info.paths then
            for i = 1, #info.paths do
                if PathLooksLikeBundledExpressway(fontKey, info.paths[i], 14, "") then
                    expresswayOverridePath = info.paths[i]
                    break
                end
            end
        end
        return {
            key = fontKey,
            requested = path,
            ok = ok,
            applied = appliedPath,
            actual = actual,
            source = source,
            matches = FontPathMatches(appliedPath, actual),
            expresswayOverride = PathLooksLikeBundledExpressway(fontKey, actual or appliedPath or path, 14, ""),
            expresswayOverridePath = expresswayOverridePath,
            candidates = BuildInternalFontPathCandidates(fontKey, path),
        }
    end

    ns.Util = ns.Util or {}
    ns.Util.ResolveFontPath = _G.MSUF_ResolveFontPath
    ns.Util.SetFontSafe = _G.MSUF_SetFontSafe
    ScheduleFontVisualPrewarm(0)
end

-- Shared Lib initialization (loaded BEFORE Options and Main)
-- Goal: stable ns.LSM reference regardless of load order / refactors.

local function TryInitLSM()
    if ns.LSM then return true end

    local libStub = _G.LibStub
    if not libStub then return false end

    local ok, lsm = pcall(libStub, "LibSharedMedia-3.0", true)
    -- LibStub("LibSharedMedia-3.0", true) returns nil if not available.
    if ok and lsm then
        ns.LSM = lsm
        _G.MSUF_LSM = lsm

        -- Inform Main (which caches LSM in a local upvalue) that LSM is now ready.
        if _G.MSUF_OnLSMReady then
            _G.MSUF_OnLSMReady(lsm)
        end

        return true
    end
    return false
end

local function EnsureLSMCallbacks()
    local LSM = ns.LSM
    if not LSM then return end
    if _G.MSUF_LSM_CallbacksRegistered then return end
    _G.MSUF_LSM_CallbacksRegistered = true

    LSM:RegisterCallback("LibSharedMedia_Registered", function(_, mediatype, key)
        if mediatype == "font" then
            if type(_G.MSUF_ClearResolvedFontPathCache) == "function" then
                _G.MSUF_ClearResolvedFontPathCache()
            end
            if _G.MSUF_RebuildFontChoices then
                _G.MSUF_RebuildFontChoices()
            end

            local normalizeFontKey = _G.MSUF_NormalizeFontKey or function(k) return k end
            if _G.MSUF_DB and _G.MSUF_DB.general and normalizeFontKey(_G.MSUF_DB.general.fontKey) == normalizeFontKey(key) then
                if _G.C_Timer and _G.C_Timer.After then
                    _G.C_Timer.After(0, function()
                        if _G.UpdateAllFonts then
                            _G.UpdateAllFonts()
                        end
                    end)
                elseif _G.UpdateAllFonts then
                    _G.UpdateAllFonts()
                end
            end

        elseif mediatype == "statusbar" then
            if _G.MSUF_RebuildStatusbarChoices then
                _G.MSUF_RebuildStatusbarChoices()
            end
        end
    end)
end

-- Bundled fonts (Media/Fonts)

local function RegisterBundledFonts()
    if _G.MSUF_BUNDLED_FONTS_REGISTERED then return end

    local LSM = ns.LSM
    if not LSM or type(LSM.Register) ~= "function" then return end

    local base = "Interface/AddOns/" .. tostring(addonName) .. "/Media/Fonts/"
    local fonts = {
        { key = "EXPRESSWAY", name = "Expressway Regular (MSUF)", file = "Expressway Regular.ttf" },
        { key = "EXPRESSWAY_BOLD", name = "Expressway Bold (MSUF)", file = "Expressway Bold.ttf" },
        { key = "EXPRESSWAY_SEMIBOLD", name = "Expressway SemiBold (MSUF)", file = "Expressway SemiBold.ttf" },
        { key = "EXPRESSWAY_EXTRABOLD", name = "Expressway ExtraBold (MSUF)", file = "Expressway ExtraBold.ttf" },
        { key = "EXPRESSWAY_CONDENSED_LIGHT", name = "Expressway Condensed Light (MSUF)", file = "Expressway Condensed Light.otf" },
    }

    for _, info in ipairs(fonts) do
        local path = base .. info.file
        pcall(LSM.Register, LSM, "font", info.key, path)
    end

    -- Bundled bar/castbar textures (Media/Bars).
    -- Registered here to be load-order-safe.
    local baseBars = "Interface/AddOns/" .. tostring(addonName) .. "/Media/Bars/"
    local function Reg(name, file)
        pcall(LSM.Register, LSM, "statusbar", name, baseBars .. file)
    end

    Reg("MSUF Charcoal",   "Charcoal.tga")
    Reg("MSUF Minimalist", "Minimalist.tga")
    Reg("MSUF Slickrock",  "Slickrock.tga")
    Reg("MSUF Smooth",     "MSUF_Smooth.tga")
    Reg("MSUF Smooth v2",  "Smoothv2.tga")
    Reg("MSUF Smoother",   "smoother.tga")
    Reg("Better Blizzard", "BetterBlizzard.blp")

    -- DB migration: eliminate broken legacy selections ("MSUF Flat"/"MSUF Smooth")
    local function MigrateLegacyBarKeys()
        local db = _G.MSUF_DB
        if type(db) ~= "table" or type(db.general) ~= "table" then return end
        local g = db.general
        local changed = false

        -- Migrate old Midnight texture names to new MSUF names (renaming only)
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
                pcall(_G.MSUF_UpdateAllBarTextures)
            end
            if type(_G.MSUF_UpdateCastbarVisuals) == "function" then
                pcall(_G.MSUF_UpdateCastbarVisuals)
            end
        end
    end

    if _G.C_Timer and type(_G.C_Timer.After) == "function" then
        _G.C_Timer.After(0, MigrateLegacyBarKeys)
    else
        MigrateLegacyBarKeys()
    end

    _G.MSUF_BUNDLED_FONTS_REGISTERED = true
end

-- Initial attempt (works when libs are already available)
if TryInitLSM() then
    EnsureLSMCallbacks()
    RegisterBundledFonts()
else
    -- Load-order-safe fallback: retry when other addons load / on login.
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function()
        if TryInitLSM() then
            EnsureLSMCallbacks()
            RegisterBundledFonts()
            f:UnregisterEvent("ADDON_LOADED")
            f:UnregisterEvent("PLAYER_LOGIN")
            f:SetScript("OnEvent", nil)
        end
    end)
end

-- LoD module helpers (Castbars/GamePlay/etc.)

-- Export the core namespace for LoadOnDemand sub-addons.
_G.MSUF_NS = _G.MSUF_NS or ns

-- Safe helper to load a LoD sub-addon at runtime.
-- Returns true if the addon is loaded after the call.
function _G.MSUF_EnsureAddonLoaded(addonName)
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

    pcall(loader, addonName)
    return IsLoaded()
end

-- Global UI Scale (combat-safe gate)
-- Fixes: /reload in combat (or any in-combat scale apply) causing ADDON_ACTION_BLOCKED
-- by deferring Global UI scale changes until PLAYER_REGEN_ENABLED.
-- Important: We intentionally wrap MSUF_SetGlobalUiScale in-place so ANY caller becomes
-- combat-safe without needing to edit every callsite (SlashMenu / Options / etc.).
function _G.MSUF_InstallGlobalScaleGate()
    if _G.MSUF_GlobalScaleGateInstalled then return end
    _G.MSUF_GlobalScaleGateInstalled = true

    local function TryWrap()
        local fn = _G.MSUF_SetGlobalUiScale
        if type(fn) ~= "function" then
            return false
        end

        -- Already wrapped?
        if _G.MSUF_SetGlobalUiScale_GATED and fn == _G.MSUF_SetGlobalUiScale_GATED then
            return true
        end

        -- Preserve raw implementation (first one wins)
        if type(_G.MSUF_SetGlobalUiScale_RAW) ~= "function" then
            _G.MSUF_SetGlobalUiScale_RAW = fn
        end

        -- Create/ensure the deferred-apply frame once.
        if not _G.MSUF_GlobalScaleGateFrame then
            local gf = CreateFrame("Frame")
            _G.MSUF_GlobalScaleGateFrame = gf
            gf:RegisterEvent("PLAYER_REGEN_ENABLED")
            gf:SetScript("OnEvent", function()
                local args = _G.MSUF_PendingGlobalScaleArgs
                _G.MSUF_PendingGlobalScaleArgs = nil

                if not args then return end
                if InCombatLockdown and InCombatLockdown() then
                    -- Still not safe (edge case): keep pending.
                    _G.MSUF_PendingGlobalScaleArgs = args
                    return
                end

                local raw = _G.MSUF_SetGlobalUiScale_RAW
                if type(raw) == "function" then
                    -- Unpack pending args and apply once after combat.
                    pcall(raw, unpack(args))
                end
            end)
        end

        -- Gate wrapper: defer in combat, else passthrough.
        _G.MSUF_SetGlobalUiScale_GATED = function(...)
            local scale = select(1, ...)
            if scale == nil then return end

            if InCombatLockdown and InCombatLockdown() then
                -- Last-call-wins: overwrite pending args.
                _G.MSUF_PendingGlobalScaleArgs = { ... }
                return
            end

            local raw = _G.MSUF_SetGlobalUiScale_RAW
            if type(raw) == "function" then
                return raw(...)
            end
        end

        _G.MSUF_SetGlobalUiScale = _G.MSUF_SetGlobalUiScale_GATED
        return true
    end

    -- Install immediately if possible; otherwise retry on common init events.
    if TryWrap() then return end

    if not _G.MSUF_GlobalScaleInstallFrame then
        local f = CreateFrame("Frame")
        _G.MSUF_GlobalScaleInstallFrame = f
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

-- Ensure gate is installed as early as possible (before any C_Timer.After(0) scale applies fire).
if _G.C_Timer and _G.C_Timer.After then
    _G.C_Timer.After(0, function()
        _G.MSUF_InstallGlobalScaleGate()
    end)
else
    _G.MSUF_InstallGlobalScaleGate()
end

-- Auto-load Castbars LoD addon on login when any castbar feature is enabled.
-- (Keeps the core addon slim, but still "just works" out of the box.)
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function()
        if _G.EnsureDB then
            _G.EnsureDB()
        end

        local g = _G.MSUF_DB and _G.MSUF_DB.general or nil
        if not g then return end

        local need = false
        if g.enablePlayerCastbar ~= false then need = true end
        if g.enableTargetCastbar ~= false then need = true end
        if g.enableFocusCastbar ~= false then need = true end
        if g.enableBossCastbar == true then need = true end

        if need then
            _G.MSUF_EnsureAddonLoaded("MidnightSimpleUnitFrames_Castbars")
        end
    end)
end

-- Auto-load Gameplay LoD addon on login when any gameplay feature is enabled.
-- (Prevents "feature looks enabled but does nothing until you toggle twice" after /reload or relog.)
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function()
        if _G.EnsureDB then
            _G.EnsureDB()
        end

        local g = _G.MSUF_DB and _G.MSUF_DB.gameplay or nil
        if not g then return end

        local need = false
        if g.enableCombatTimer == true then need = true end
        if g.enableCombatStateText == true then need = true end
        if g.enableFirstDanceTimer == true then need = true end
        if g.enableCombatCrosshair == true then need = true end

        if need then
            _G.MSUF_EnsureAddonLoaded("MidnightSimpleUnitFrames_Gameplay")

            -- Apply immediately so event wiring is active without opening the Gameplay menu.
            local ns2 = _G.MSUF_NS
            if ns2 and type(ns2.MSUF_RequestGameplayApply) == "function" then
                ns2.MSUF_RequestGameplayApply()
            elseif _G.MSUF_RequestGameplayApply then
                _G.MSUF_RequestGameplayApply()
            end
        end
    end)
end
