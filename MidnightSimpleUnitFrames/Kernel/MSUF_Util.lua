--- Kernel/MSUF_Util.lua
--- Shared pure helpers and compatibility globals used across MSUF.
---
--- Keep hotpath-safe helpers here when they are stateless and shared by several
--- modules. Feature-specific behavior should stay with the owning module.

local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF = _G.MSUF or MSUF
local ExportPublic = MSUF.ExportPublic

--- PERF LOCALS (core runtime)
--- - Reduce global table lookups in high-frequency event/render paths.
--- - Secret-safe: localizing function references only (no value comparisons).
local type, tostring, tonumber = type, tostring, tonumber
local pairs = pairs
local string_sub, string_gsub, string_lower = string.sub, string.gsub, string.lower
local math_abs = math.abs
local InCombatLockdown = InCombatLockdown
local GetTime = GetTime
--- The change-gated setters below read `_G.issecretvalue` per call on purpose:
--- the API is absent on older clients and test harnesses install it after this
--- file loads, so the field stays late-bound. Only the table lookup itself is
--- hoisted here.
local _G = _G

-- Built-in profilers were removed in favor of explicit disposable external traces.
-- Drop their legacy SavedVariables payload once so old reports/armed trace state
-- no longer consume memory or persist back to disk.
local legacyProfilerDB = _G.MSUF_GlobalDB
if type(legacyProfilerDB) == "table" then
    legacyProfilerDB.clickCoreProfilerLast = nil
    legacyProfilerDB.cpTraceArm = nil
end

--- Boss unit token helpers (perf)
--- Avoid pattern matching (string:match) in hot paths. Pattern matching is
--- noticeably heavier than simple substring/tonumber checks.
--- Returns bossIndex (number) if u is "bossN" (N>=1), otherwise nil.
--- NOTE: Keep global names stable so call-sites across files can use them.
local GetBossIndexFromToken = _G.MSUF_GetBossIndexFromToken
if type(GetBossIndexFromToken) ~= "function" then
    function GetBossIndexFromToken(u)
    if type(u) ~= "string" then
        return nil
    end
    --- Fast prefix check
    if string_sub(u, 1, 4) ~= "boss" then
        return nil
    end
    local n = tonumber(string_sub(u, 5))
    if n and n >= 1 then
        return n
    end
    return nil
end
end
ExportPublic("MSUF_GetBossIndexFromToken", GetBossIndexFromToken)

local IsBossUnitToken = _G.MSUF_IsBossUnitToken
if type(IsBossUnitToken) ~= "function" then
    function IsBossUnitToken(u)
    return GetBossIndexFromToken(u) ~= nil
    end
end
ExportPublic("MSUF_IsBossUnitToken", IsBossUnitToken)

local MSUF_POWER_BAR_SHOW_KEYS = {
    player = "showPlayerPowerBar",
    target = "showTargetPowerBar",
    focus  = "showFocusPowerBar",
    boss   = "showBossPowerBar",
}
local MSUF_POWER_BAR_DEFAULTS = {
    player = true,
    target = true,
    focus = true,
    targettarget = false,
    focustarget = false,
    pet = true,
    boss = true,
}
local MSUF_POWER_BAR_UNIT_KEYS = {
    player = true,
    target = true,
    focus = true,
    targettarget = true,
    focustarget = true,
    pet = true,
    boss = true,
}

local CanonPowerBarUnitKey = _G.MSUF_CanonPowerBarUnitKey
if type(CanonPowerBarUnitKey) ~= "function" then
    function CanonPowerBarUnitKey(unitKey)
    if type(unitKey) ~= "string" then return nil end
    unitKey = unitKey:lower()
    if unitKey == "tot" or unitKey == "targetoftarget" or unitKey == "target_of_target" then
        unitKey = "targettarget"
    elseif unitKey == "focus_target" or unitKey == "focustargettarget" then
        unitKey = "focustarget"
    elseif GetBossIndexFromToken(unitKey) then
        unitKey = "boss"
    end
    if MSUF_POWER_BAR_UNIT_KEYS[unitKey] then return unitKey end
    return nil
end
end
ExportPublic("MSUF_CanonPowerBarUnitKey", CanonPowerBarUnitKey)

--- One capability contract for runtime, Edit Mode, and Options previews.  The
--- shared Power element detaches every managed single-unit frame; Player-only
--- shape/Class Resource options are separate capabilities.
local CanDetachUnitPowerBar = _G.MSUF_CanDetachUnitPowerBar
if type(CanDetachUnitPowerBar) ~= "function" then
    function CanDetachUnitPowerBar(unitKey)
        return CanonPowerBarUnitKey(unitKey) ~= nil
    end
end
ExportPublic("MSUF_CanDetachUnitPowerBar", CanDetachUnitPowerBar)

local ReadUnitPowerBarEnabled = _G.MSUF_ReadUnitPowerBarEnabled
if type(ReadUnitPowerBarEnabled) ~= "function" then
    function ReadUnitPowerBarEnabled(unitKey, db)
    db = db or _G.MSUF_DB
    local k = CanonPowerBarUnitKey(unitKey)
    if not k then return true end
    local u = db and db[k]
    if u and u.showPowerBar ~= nil then
        return u.showPowerBar ~= false
    end
    local legacyKey = MSUF_POWER_BAR_SHOW_KEYS[k]
    local bars = db and db.bars
    if legacyKey and bars and bars[legacyKey] ~= nil then
        return bars[legacyKey] ~= false
    end
    return MSUF_POWER_BAR_DEFAULTS[k] ~= false
end
end
ExportPublic("MSUF_ReadUnitPowerBarEnabled", ReadUnitPowerBarEnabled)

local function MSUF_ReadUnitPowerBarNumber(unitKey, field, legacyField, defaultVal, minVal, maxVal, db)
    db = db or _G.MSUF_DB
    local k = CanonPowerBarUnitKey(unitKey)
    local u = k and db and db[k]
    local v = u and u[field]
    if type(v) ~= "number" then
        local bars = db and db.bars
        v = bars and bars[legacyField]
    end
    v = tonumber(v) or defaultVal
    if minVal and v < minVal then v = minVal end
    if maxVal and v > maxVal then v = maxVal end
    return v
end

local function MSUF_ReadUnitPowerBarBool(unitKey, field, legacyField, defaultVal, db)
    db = db or _G.MSUF_DB
    local k = CanonPowerBarUnitKey(unitKey)
    local u = k and db and db[k]
    local v = u and u[field]
    if v == nil then
        local bars = db and db.bars
        v = bars and bars[legacyField]
    end
    if v == nil then return defaultVal and true or false end
    return v == true
end

local ReadUnitPowerBarHeight = _G.MSUF_ReadUnitPowerBarHeight
if type(ReadUnitPowerBarHeight) ~= "function" then
    function ReadUnitPowerBarHeight(unitKey, db)
        return MSUF_ReadUnitPowerBarNumber(unitKey, "powerBarHeight", "powerBarHeight", 3, 1, 80, db)
    end
end
ExportPublic("MSUF_ReadUnitPowerBarHeight", ReadUnitPowerBarHeight)

local ReadUnitPowerBarEmbed = _G.MSUF_ReadUnitPowerBarEmbed
if type(ReadUnitPowerBarEmbed) ~= "function" then
    function ReadUnitPowerBarEmbed(unitKey, db)
        return MSUF_ReadUnitPowerBarBool(unitKey, "embedPowerBarIntoHealth", "embedPowerBarIntoHealth", true, db)
    end
end
ExportPublic("MSUF_ReadUnitPowerBarEmbed", ReadUnitPowerBarEmbed)

local ReadUnitPowerBarBorderEnabled = _G.MSUF_ReadUnitPowerBarBorderEnabled
if type(ReadUnitPowerBarBorderEnabled) ~= "function" then
    function ReadUnitPowerBarBorderEnabled(unitKey, db)
        db = db or _G.MSUF_DB
        local k = CanonPowerBarUnitKey(unitKey)
        local u = k and db and db[k]
        if k == "player" and u and u.powerBarDetached == true then
            local outline = tonumber(db and db.bars and db.bars.detachedPowerBarOutline)
            if outline ~= nil then return outline > 0 end
        end
        return MSUF_ReadUnitPowerBarBool(unitKey, "powerBarBorderEnabled", "powerBarBorderEnabled", false, db)
    end
end
ExportPublic("MSUF_ReadUnitPowerBarBorderEnabled", ReadUnitPowerBarBorderEnabled)

local ReadUnitPowerBarBorderThickness = _G.MSUF_ReadUnitPowerBarBorderThickness
if type(ReadUnitPowerBarBorderThickness) ~= "function" then
    function ReadUnitPowerBarBorderThickness(unitKey, db)
        db = db or _G.MSUF_DB
        local k = CanonPowerBarUnitKey(unitKey)
        local u = k and db and db[k]
        local v
        if k == "player" and u and u.powerBarDetached == true then
            v = tonumber(db and db.bars and db.bars.detachedPowerBarOutline)
        end
        if type(v) ~= "number" then v = u and u.powerBarBorderThickness end
        if type(v) ~= "number" then
            local bars = db and db.bars
            v = bars and (bars.powerBarBorderThickness or bars.powerBarBorderSize)
        end
        v = tonumber(v) or 1
        if v < 0 then v = 0 elseif v > 10 then v = 10 end
        return v
    end
end
ExportPublic("MSUF_ReadUnitPowerBarBorderThickness", ReadUnitPowerBarBorderThickness)

--- MSUF_Util.lua
--- Stateless helpers / pure functions extracted from MidnightSimpleUnitFrames.lua
--- Keep names stable (globals) to avoid touching call-sites.

MSUF.MSUF_Util = MSUF.MSUF_Util or {}
local U = MSUF.MSUF_Util
ExportPublic("MSUF_Util", U)

--- Shared frame layering for visual effects (highlight borders, overlays, stripes).
--- Keep this in Foundation so UnitFrames and GroupFrames use identical strata/level
--- behavior without duplicating hot-path helpers.
if type(_G.MSUF_FRAME_STRATA_RANK) ~= "table" then
    ExportPublic("MSUF_FRAME_STRATA_RANK", {
        BACKGROUND = 1,
        LOW = 2,
        MEDIUM = 3,
        HIGH = 4,
        DIALOG = 5,
        FULLSCREEN = 6,
        FULLSCREEN_DIALOG = 7,
        TOOLTIP = 8,
    })
end

if type(_G.MSUF_EFFECT_FRAME_STRATA) ~= "string" or _G.MSUF_EFFECT_FRAME_STRATA == "" then
    ExportPublic("MSUF_EFFECT_FRAME_STRATA", "HIGH")
end

local function IsSecretValue(value)
    local issecretvalue = _G.issecretvalue
    return type(issecretvalue) == "function" and issecretvalue(value) == true
end
local function NormalizeFrameStrata(value, fallback)
    fallback = fallback or "AUTO"
    if IsSecretValue(value) then return fallback end
    if value == nil or value == "" then return fallback end
    value = tostring(value):upper()
    if value == "AUTO" then return "AUTO" end
    local rank = _G.MSUF_FRAME_STRATA_RANK
    return rank and rank[value] and value or fallback
end
ExportPublic("MSUF_NormalizeFrameStrata", NormalizeFrameStrata)

local ClampFrameLevel = _G.MSUF_ClampFrameLevel
if type(ClampFrameLevel) ~= "function" then
    ClampFrameLevel = function(level)
        level = tonumber(level) or 0
        if level < 0 then return 0 end
        if level > 10000 then return 10000 end
        return level
    end
end
ExportPublic("MSUF_ClampFrameLevel", ClampFrameLevel)

local function MaxFrameStrata(a, b)
    if IsSecretValue(a) then a = nil end
    if IsSecretValue(b) then b = nil end
    if not a or a == "" then return b end
    if not b or b == "" then return a end
    local rank = _G.MSUF_FRAME_STRATA_RANK
    return ((rank[a] or 0) >= (rank[b] or 0)) and a or b
end
ExportPublic("MSUF_MaxFrameStrata", MaxFrameStrata)

local function SyncFrameLayerAbove(child, parent, offset, strata)
    if not (child and parent) then return nil end

    local parentStrata
    if parent.GetFrameStrata then parentStrata = parent:GetFrameStrata() end
    if IsSecretValue(parentStrata) then parentStrata = nil end
    if IsSecretValue(strata) then strata = nil end
    if strata == nil or strata == "" then strata = _G.MSUF_EFFECT_FRAME_STRATA end
    local wantStrata = MaxFrameStrata(parentStrata, strata)
    if wantStrata and child.SetFrameStrata then
        local currentStrata
        if child.GetFrameStrata then currentStrata = child:GetFrameStrata() end
        if IsSecretValue(currentStrata) or currentStrata ~= wantStrata then
            child:SetFrameStrata(wantStrata)
        end
    end

    if child.SetFrameLevel and parent.GetFrameLevel then
        local level = ClampFrameLevel((parent:GetFrameLevel() or 0) + (tonumber(offset) or 1))
        if not child.GetFrameLevel or child:GetFrameLevel() ~= level then
            child:SetFrameLevel(level)
        end
        return level
    end

    return nil
end
ExportPublic("MSUF_SyncFrameLayerAbove", SyncFrameLayerAbove)

--- Atlas helper used by status/state indicator icons.
--- Some call-sites use a global helper name; provide it here as a safe fallback
--- so indicator modules can remain self-contained without load-order fragility.
--- Returns true if something was applied.
if type(_G._MSUF_SetAtlasOrFallback) ~= "function" then
    function _G._MSUF_SetAtlasOrFallback(tex, atlasName, fallbackTexture)
        if not tex then
            return false
        end

        if atlasName and tex.SetAtlas then
            tex:SetAtlas(atlasName, true)
            return true
        end

        if fallbackTexture and tex.SetTexture then
            tex:SetTexture(fallbackTexture)
            return true
        end

        return false
    end
end

--- External icon-pack support:
--- In Midnight, spell/aura APIs commonly return FileDataIDs. Passing those IDs
--- directly to SetTexture bypasses loose files in Interface\Icons. For accessible
--- icon IDs, resolve the original filename and set the extensionless path instead
--- so files like Interface\Icons\inv_belt_39a.tga can override the default icon.
do
    local _fileDataIconPathCache = {}
    local _GetFilenameFromFileDataID

    local function MSUF_CanReadTextureValue(value)
        local canaccessvalue = _G.canaccessvalue
        if type(canaccessvalue) == "function" then
            return canaccessvalue(value) == true
        end
        local issecretvalue = _G.issecretvalue
        if type(issecretvalue) == "function" and issecretvalue(value) == true then
            return false
        end
        return true
    end

    local function MSUF_GetFilenameResolver()
        if _GetFilenameFromFileDataID then return _GetFilenameFromFileDataID end
        local C_Texture = _G.C_Texture
        _GetFilenameFromFileDataID = C_Texture and C_Texture.GetFilenameFromFileDataID
        return _GetFilenameFromFileDataID
    end

    local function MSUF_NormalizeInterfaceIconPath(path)
        if type(path) ~= "string" or path == "" then return nil end
        path = string_gsub(path, "/", "\\")
        local lower = string_lower(path)
        if string_sub(lower, 1, 16) ~= "interface\\icons\\" then
            return nil
        end
        path = string_gsub(path, "%.[Bb][Ll][Pp]$", "")
        path = string_gsub(path, "%.[Tt][Gg][Aa]$", "")
        path = string_gsub(path, "%.[Pp][Nn][Gg]$", "")
        return path
    end

    local ResolveIconTexturePath = _G.MSUF_ResolveIconTexturePath
    if type(ResolveIconTexturePath) ~= "function" then
        ResolveIconTexturePath = function(texture)
            if not MSUF_CanReadTextureValue(texture) then
                return texture
            end

            local vt = type(texture)
            if vt == "string" then
                return MSUF_NormalizeInterfaceIconPath(texture) or texture
            end
            if vt ~= "number" or texture <= 0 then
                return texture
            end

            local cached = _fileDataIconPathCache[texture]
            if cached ~= nil then
                return cached or texture
            end

            local resolver = MSUF_GetFilenameResolver()
            if type(resolver) == "function" then
                local path = MSUF_NormalizeInterfaceIconPath(resolver(texture))
                if path then
                    _fileDataIconPathCache[texture] = path
                    return path
                end
            end

            _fileDataIconPathCache[texture] = false
            return texture
        end
    end

    local SetIconTexture = _G.MSUF_SetIconTexture
    if type(SetIconTexture) ~= "function" then
        SetIconTexture = function(textureRegion, texture, fallback)
            if not (textureRegion and textureRegion.SetTexture) then return end
            local resolver = ResolveIconTexturePath
            local value = (type(resolver) == "function") and resolver(texture) or texture
            if MSUF_CanReadTextureValue(value) and (value == nil or value == "") then
                value = fallback or ""
            end
            textureRegion:SetTexture(value)
        end
    end

    U.ResolveIconTexturePath = ResolveIconTexturePath
    U.SetIconTexture = SetIconTexture
    ExportPublic("MSUF_ResolveIconTexturePath", ResolveIconTexturePath)
    ExportPublic("MSUF_SetIconTexture", SetIconTexture)
end

local function MSUF_DeepCopy(value, seen)
    if type(value) ~= "table" then
        return value
    end
    seen = seen or {}
    if seen[value] then
        return seen[value]
    end
    local copy = {}
    seen[value] = copy
    for k, v in pairs(value) do
        copy[MSUF_DeepCopy(k, seen)] = MSUF_DeepCopy(v, seen)
    end
    return copy
end

local function MSUF_CaptureKeys(src, keys)
    local out = {}
    if type(src) ~= "table" or type(keys) ~= "table" then
        return out
    end
    for i = 1, #keys do
        local k = keys[i]
        out[k] = src[k]
    end
    return out
end

local function MSUF_RestoreKeys(dst, snap)
    if type(dst) ~= "table" or type(snap) ~= "table" then return end
    for k, v in pairs(snap) do
        dst[k] = v --- assigning nil removes the key (restores defaults)
    end
end

local function MSUF_GetNumber(v, default, minValue, maxValue)
    local n = tonumber(v) or default
    if minValue and n < minValue then
        n = minValue
    end
    if maxValue and n > maxValue then
        n = maxValue
    end
    return n
end

local function MSUF_Clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function MSUF_SetTextIfChanged(fs, text)
    if not fs then return end
    --- Secret-safe diff gate: only compare/cache plain Lua values.
    --- Secret values must pass straight through to C-side SetText().
    local sv = _G.issecretvalue
    if sv and sv(text) == true then
        fs._msufLastText = nil
        fs:SetText(text)
        return
    end

    local v = text
    if v == nil then v = "" end

    local tv = type(v)
    if tv == "string" or tv == "number" or tv == "boolean" then
        if fs._msufLastText == v then return end
        fs._msufLastText = v
        fs:SetText(v)
        return
    end

    fs._msufLastText = nil
    fs:SetText(v)
end

local MSUF_CASTBAR_TIME_FORMAT_CURRENT = "CURRENT"
local MSUF_CASTBAR_TIME_FORMATS = {
    CURRENT = true,
    ELAPSED = true,
    CURRENT_MAX = true,
    MAX_CURRENT = true,
    ELAPSED_MAX = true,
    MAX_ELAPSED = true,
}

local function MSUF_NormalizeCastbarTimeFormat(value)
    if type(value) ~= "string" then return MSUF_CASTBAR_TIME_FORMAT_CURRENT end
    value = value:upper()
    value = value:gsub("%s+", "")
    value = value:gsub("/", "_")
    value = value:gsub("-", "_")
    if value == "CURRENTONLY" or value == "CURRENT_ONLY" or value == "REMAINING" or value == "REMAINING_ONLY" then
        return "CURRENT"
    end
    if value == "ELAPSEDONLY" or value == "ELAPSED_ONLY" then
        return "ELAPSED"
    end
    if value == "REMAINING_MAX" then return "CURRENT_MAX" end
    if value == "MAX_REMAINING" then return "MAX_CURRENT" end
    if MSUF_CASTBAR_TIME_FORMATS[value] then return value end
    return MSUF_CASTBAR_TIME_FORMAT_CURRENT
end

local function MSUF_GetCastbarTimeFormatDBKey(unit)
    unit = tostring(unit or ""):lower()
    if unit == "player" then return "castbarPlayerTimeFormat" end
    if unit == "target" then return "castbarTargetTimeFormat" end
    if unit == "focus" then return "castbarFocusTimeFormat" end
    if unit == "boss" or unit:match("^boss%d+$") then return "bossCastTimeFormat" end
    return nil
end

local function MSUF_GetCastbarTimeFormat(unit, g)
    local key = MSUF_GetCastbarTimeFormatDBKey(unit)
    if not key then return MSUF_CASTBAR_TIME_FORMAT_CURRENT end
    if not g then
        local db = _G.MSUF_DB
        g = db and db.general
    end
    return MSUF_NormalizeCastbarTimeFormat(g and g[key])
end

local function MSUF_FormatCastbarTimeText(mode, current, total)
    local cur = tonumber(current)
    if type(cur) ~= "number" then return nil end
    if cur < 0 then cur = 0 end

    mode = MSUF_NormalizeCastbarTimeFormat(mode)
    local maxTime = tonumber(total)
    if not maxTime or maxTime <= 0 then
        return string.format("%.1f", cur)
    end
    if cur > maxTime then cur = maxTime end

    if mode == "CURRENT_MAX" then
        return string.format("%.1f / %.1f", cur, maxTime)
    elseif mode == "ELAPSED" then
        local elapsed = maxTime - cur
        if elapsed < 0 then elapsed = 0 end
        return string.format("%.1f", elapsed)
    elseif mode == "MAX_CURRENT" then
        return string.format("%.1f / %.1f", maxTime, cur)
    elseif mode == "ELAPSED_MAX" then
        local elapsed = maxTime - cur
        if elapsed < 0 then elapsed = 0 end
        return string.format("%.1f / %.1f", elapsed, maxTime)
    elseif mode == "MAX_ELAPSED" then
        local elapsed = maxTime - cur
        if elapsed < 0 then elapsed = 0 end
        return string.format("%.1f / %.1f", maxTime, elapsed)
    end

    return string.format("%.1f", cur)
end

local function MSUF_SetCastTimeText(frame, seconds, totalSeconds)
    local fs = frame and frame.timeText
    if not fs then return end

    if type(seconds) == "nil" then
        MSUF_SetTextIfChanged(fs, "")
        return
    end

    --- Midnight/Beta "secret value" safety:
    --- Avoid arithmetic directly on potentially secret values by converting to a Lua number.
    local n = tonumber(seconds)
    if type(n) ~= "number" then
        MSUF_SetTextIfChanged(fs, "")
        return
    end

    local mode = frame._msufCastTimeFormat
    if not mode and frame.unit then
        mode = MSUF_GetCastbarTimeFormat(frame.unit)
    end
    mode = MSUF_NormalizeCastbarTimeFormat(mode)

    if mode == "CURRENT" and fs.SetFormattedText then
        fs._msufLastText = nil
        fs:SetFormattedText("%.1f", n)
    else
        local text = MSUF_FormatCastbarTimeText(mode, n, totalSeconds or frame._msufPlainTotal)
        MSUF_SetTextIfChanged(fs, text or "")
    end
end

local function MSUF_SetAlphaIfChanged(f, a)
    if not f or not f.SetAlpha or a == nil then return end
    local prev = f._msufAlpha
    if prev == nil or math_abs(prev - a) > 0.001 then
        f:SetAlpha(a)
        f._msufAlpha = a
    end
end

local function MSUF_SetWidthIfChanged(f, w)
    if not f or not f.SetWidth or not w or w <= 0 then return end
    local prev = f._msufW
    if prev == nil or math_abs(prev - w) > 0.01 then
        f:SetWidth(w)
        f._msufW = w
    end
end

local function MSUF_SetHeightIfChanged(f, h)
    if not f or not f.SetHeight or not h or h <= 0 then return end
    local prev = f._msufH
    if prev == nil or math_abs(prev - h) > 0.01 then
        f:SetHeight(h)
        f._msufH = h
    end
end

local function MSUF_SetPointIfChanged(f, point, relTo, relPoint, ofsX, ofsY)
    if not f or not f.SetPoint then return end
    local c = f._msufAnchor
    if not c then
        c = {}
        f._msufAnchor = c
    end
    if c.point ~= point or c.relTo ~= relTo or c.relPoint ~= relPoint or c.ofsX ~= ofsX or c.ofsY ~= ofsY then
        f:ClearAllPoints()
        f:SetPoint(point, relTo, relPoint, ofsX, ofsY)
        c.point, c.relTo, c.relPoint, c.ofsX, c.ofsY = point, relTo, relPoint, ofsX, ofsY
    end
end

local function MSUF_SetJustifyHIfChanged(fs, justify)
    if not fs or not fs.SetJustifyH or not justify then return end
    if fs._msufJustifyH ~= justify then
        fs:SetJustifyH(justify)
        fs._msufJustifyH = justify
    end
end

local function MSUF_SetSliderValueSilent(slider, value)
    if not slider or not slider.SetValue then return end
    slider.MSUF_SkipCallback = true
    slider:SetValue(value)
    slider.MSUF_SkipCallback = false
end

local function MSUF_ClampToSlider(slider, value)
    if type(value) ~= "number" then return value end
    if slider and type(slider.minVal) == "number" then
        value = math.max(slider.minVal, value)
    end
    if slider and type(slider.maxVal) == "number" then
        value = math.min(slider.maxVal, value)
    end
    return value
end

--- Table exports (optional convenience)
U.DeepCopy = MSUF_DeepCopy
U.CaptureKeys = MSUF_CaptureKeys
U.RestoreKeys = MSUF_RestoreKeys
U.Clamp = MSUF_Clamp
U.GetNumber = MSUF_GetNumber
U.SetTextIfChanged = MSUF_SetTextIfChanged
U.NormalizeCastbarTimeFormat = MSUF_NormalizeCastbarTimeFormat
U.GetCastbarTimeFormatDBKey = MSUF_GetCastbarTimeFormatDBKey
U.GetCastbarTimeFormat = MSUF_GetCastbarTimeFormat
U.FormatCastbarTimeText = MSUF_FormatCastbarTimeText
U.SetCastTimeText = MSUF_SetCastTimeText
U.SetAlphaIfChanged = MSUF_SetAlphaIfChanged
U.SetWidthIfChanged = MSUF_SetWidthIfChanged
U.SetHeightIfChanged = MSUF_SetHeightIfChanged
U.SetPointIfChanged = MSUF_SetPointIfChanged
U.SetJustifyHIfChanged = MSUF_SetJustifyHIfChanged
U.SetSliderValueSilent = MSUF_SetSliderValueSilent
U.ClampToSlider = MSUF_ClampToSlider

--- Also keep existing MSUF exports where older code expects them.
MSUF.MSUF_DeepCopy = MSUF_DeepCopy
MSUF.MSUF_CaptureKeys = MSUF_CaptureKeys
MSUF.MSUF_RestoreKeys = MSUF_RestoreKeys
ExportPublic("MSUF_DeepCopy", MSUF_DeepCopy)
ExportPublic("MSUF_CaptureKeys", MSUF_CaptureKeys)
ExportPublic("MSUF_RestoreKeys", MSUF_RestoreKeys)
ExportPublic("MSUF_GetNumber", MSUF_GetNumber)
ExportPublic("MSUF_Clamp", MSUF_Clamp)
ExportPublic("MSUF_SetTextIfChanged", MSUF_SetTextIfChanged)
ExportPublic("MSUF_NormalizeCastbarTimeFormat", MSUF_NormalizeCastbarTimeFormat)
ExportPublic("MSUF_GetCastbarTimeFormatDBKey", MSUF_GetCastbarTimeFormatDBKey)
ExportPublic("MSUF_GetCastbarTimeFormat", MSUF_GetCastbarTimeFormat)
ExportPublic("MSUF_FormatCastbarTimeText", MSUF_FormatCastbarTimeText)
ExportPublic("MSUF_SetCastTimeText", MSUF_SetCastTimeText)
ExportPublic("MSUF_SetAlphaIfChanged", MSUF_SetAlphaIfChanged)
ExportPublic("MSUF_SetWidthIfChanged", MSUF_SetWidthIfChanged)
ExportPublic("MSUF_SetHeightIfChanged", MSUF_SetHeightIfChanged)
ExportPublic("MSUF_SetPointIfChanged", MSUF_SetPointIfChanged)
ExportPublic("MSUF_SetJustifyHIfChanged", MSUF_SetJustifyHIfChanged)
ExportPublic("MSUF_SetSliderValueSilent", MSUF_SetSliderValueSilent)
ExportPublic("MSUF_ClampToSlider", MSUF_ClampToSlider)

--- Shared tiny helpers on the Bootstrap namespace. Runtime files alias these
--- (`local EnsureDBSafe = MSUF.Util.EnsureDBSafe`) instead of carrying their own
--- copy, so call sites and per-call cost stay the same.
MSUF.Util = MSUF.Util or {}
local Util = MSUF.Util

--- Run the full DB bootstrap only while MSUF_DB does not exist yet. The lookup
--- stays late-bound because State/MSUF_Defaults.lua loads after this file.
local function EnsureDBSafe()
    if not _G.MSUF_DB and type(_G.MSUF_EnsureDB) == "function" then
        (_G.MSUF_EnsureDB)()
    end
end

local function InCombat()
    return InCombatLockdown and InCombatLockdown()
end

--- Read a per-unit setting with the documented fallback chain: the unit's own
--- config table wins, then the shared `general` table, then the caller's
--- default. `Num` additionally coerces to a number and falls back to the
--- default when the stored value is not numeric; `Val` passes the value
--- through untouched. Icon layout (Runtime/MSUF_IconLayoutRuntime.lua) reads
--- every offset, size and anchor through these.
local function ScopedValue(conf, g, key, default)
    local value = conf and conf[key]
    if value == nil and g then value = g[key] end
    if value == nil then return default end
    return value
end

local function ScopedNumber(conf, g, key, default)
    local value = tonumber(ScopedValue(conf, g, key, nil))
    if value == nil then return default end
    return value
end

Util.EnsureDBSafe = EnsureDBSafe
Util.InCombat = InCombat
Util.DeepCopy = MSUF_DeepCopy
Util.IsSecret = IsSecretValue
Util.Val = ScopedValue
Util.Num = ScopedNumber

do
    local UIParent = UIParent
    local GetPhysicalScreenSize = GetPhysicalScreenSize
    local InCombatLockdown = InCombatLockdown

    local _cachedPhysH
    local _cachedBase768

    local function EnsureBase()
        local physH
        if GetPhysicalScreenSize then
            local _, h = GetPhysicalScreenSize()
            physH = h
        end

        if physH and physH > 0 then
            if physH ~= _cachedPhysH then
                _cachedPhysH = physH
                _cachedBase768 = 768 / physH
            end
        else
            _cachedPhysH = nil
            _cachedBase768 = nil
        end
    end

    local function GetStepFor(frame)
        EnsureBase()

        local eff = 1
        if frame and frame.GetEffectiveScale then
            eff = frame:GetEffectiveScale() or 1
        elseif UIParent and UIParent.GetEffectiveScale then
            eff = UIParent:GetEffectiveScale() or 1
        elseif UIParent and UIParent.GetScale then
            eff = UIParent:GetScale() or 1
        end
        if eff == 0 then eff = 1 end

        if _cachedBase768 then
            return _cachedBase768 / eff
        end
        return 1 / eff
    end

    local function RoundToGrid(v, step)
        if step == 0 or v == 0 then
            return v
        end
        local q = v / step
        if q >= 0 then
            q = math.floor(q + 0.5)
        else
            q = math.ceil(q - 0.5)
        end
        local out = q * step
        if out == 0 then out = 0 end
        return out
    end

    local function MSUF_GetPhysicalPixelSize(frame, pixels)
        pixels = tonumber(pixels)
        if pixels == nil then pixels = 1 end
        return GetStepFor(frame) * pixels
    end

    -- Read one region in the common physical screen coordinate space used by
    -- GetScaledRect. The fallback converts the region's local coordinates with
    -- its effective scale into the same space.
    local function ReadPhysicalScreenRect(frame)
        if not frame then return nil end

        local left, bottom, width, height
        if frame.GetScaledRect then
            left, bottom, width, height = frame:GetScaledRect()
        end
        if type(left) ~= "number" or type(bottom) ~= "number"
            or type(width) ~= "number" or type(height) ~= "number"
        then
            if not (frame.GetLeft and frame.GetBottom and frame.GetWidth and frame.GetHeight) then
                return nil
            end
            local effectiveScale = (frame.GetEffectiveScale and frame:GetEffectiveScale()) or 1
            if effectiveScale == 0 then effectiveScale = 1 end
            left, bottom = frame:GetLeft(), frame:GetBottom()
            width, height = frame:GetWidth(), frame:GetHeight()
            if type(left) ~= "number" or type(bottom) ~= "number"
                or type(width) ~= "number" or type(height) ~= "number"
            then
                return nil
            end
            left, bottom = left * effectiveScale, bottom * effectiveScale
            width, height = width * effectiveScale, height * effectiveScale
        end

        return left, bottom, width, height
    end

    -- Return one absolute screen rectangle whose origin and dimensions are all
    -- integer physical pixels. GetScaledRect already uses the common
    -- screen-scale coordinate space, where 768 / physicalHeight is one pixel.
    local function MSUF_GetPhysicalScreenRect(frame)
        EnsureBase()
        local left, bottom, width, height = ReadPhysicalScreenRect(frame)
        if not (left and bottom and width and height) then return nil end

        local pixel = _cachedBase768 or 1
        local snappedLeft = RoundToGrid(left, pixel)
        local snappedBottom = RoundToGrid(bottom, pixel)
        local snappedWidth = math.max(pixel, RoundToGrid(width, pixel))
        local snappedHeight = math.max(pixel, RoundToGrid(height, pixel))
        return snappedLeft, snappedBottom,
            snappedLeft + snappedWidth, snappedBottom + snappedHeight,
            pixel
    end

    -- Place a region on an already-resolved absolute physical rectangle while
    -- retaining a live point relationship to its MSUF-owned layout root. The
    -- small parent-relative correction removes the root's fractional pixel
    -- phase, but later UIParent/provider movement still carries every child
    -- with the secure unit button instead of leaving it at a stale screen point.
    local function MSUF_SetRegionPhysicalScreenRect(region, left, bottom, right, top, owner)
        if not (region and region.SetPoint) then return false end
        if type(left) ~= "number" or type(bottom) ~= "number"
            or type(right) ~= "number" or type(top) ~= "number"
        then
            return false
        end
        if InCombatLockdown and InCombatLockdown() then
            return false
        end

        if not owner and region.GetParent then owner = region:GetParent() end
        owner = owner or UIParent
        if not owner then return false end
        local ownerLeft, ownerBottom = ReadPhysicalScreenRect(owner)
        if type(ownerLeft) ~= "number" or type(ownerBottom) ~= "number" then
            return false
        end

        local regionScale = (region.GetEffectiveScale and region:GetEffectiveScale())
            or (UIParent.GetEffectiveScale and UIParent:GetEffectiveScale())
            or (UIParent.GetScale and UIParent:GetScale()) or 1
        if regionScale == 0 then regionScale = 1 end

        region:ClearAllPoints()
        region:SetPoint("BOTTOMLEFT", owner, "BOTTOMLEFT",
            (left - ownerLeft) / regionScale, (bottom - ownerBottom) / regionScale)
        region:SetPoint("TOPRIGHT", owner, "BOTTOMLEFT",
            (right - ownerLeft) / regionScale, (top - ownerBottom) / regionScale)
        return true
    end

    local function MSUF_Snap(frame, v)
        if type(v) ~= "number" then
            return v
        end
        local step = GetStepFor(frame)
        return RoundToGrid(v, step)
    end

    local function MSUF_Scale(v)
        return MSUF_Snap(UIParent, v)
    end

    local function MSUF_UpdatePixelPerfect()
        if InCombatLockdown and InCombatLockdown() then
            return false
        end
        _cachedPhysH = nil
        _cachedBase768 = nil
        EnsureBase()
        return true
    end

    ExportPublic("MSUF_Snap", MSUF_Snap)
    ExportPublic("MSUF_Scale", MSUF_Scale)
    ExportPublic("MSUF_UpdatePixelPerfect", MSUF_UpdatePixelPerfect)
    ExportPublic("MSUF_GetPhysicalPixelSize", MSUF_GetPhysicalPixelSize)
    ExportPublic("MSUF_GetPhysicalScreenRect", MSUF_GetPhysicalScreenRect)
    ExportPublic("MSUF_SetRegionPhysicalScreenRect", MSUF_SetRegionPhysicalScreenRect)
end

--- Phase 2: Global helpers relocated from MSUF_UpdateManager.lua
--- (These must load before any consumer; MSUF_Util.lua is in TOC slot 2.)

--- EventBus and Scheduler call handlers directly. Their queue/subscription
--- bookkeeping is committed before invocation so errors cannot strand it.

--- Global helper: "any edit mode" (MSUF Edit Mode OR Blizzard Edit Mode)
local IsInAnyEditMode = _G.MSUF_IsInAnyEditMode
if type(IsInAnyEditMode) ~= "function" then
    IsInAnyEditMode = function()
        local st = rawget(_G, "MSUF_EditState")
        if st and st.active == true then
             return true
        end
        if rawget(_G, "MSUF_UnitEditModeActive") == true then
             return true
        end
         return false
    end
end
ExportPublic("MSUF_IsInAnyEditMode", IsInAnyEditMode)

do
    local _lastConfigCombatMessage = 0

    local IsConfigCombatLocked = _G.MSUF_IsConfigCombatLocked
    if type(IsConfigCombatLocked) ~= "function" then
        IsConfigCombatLocked = function()
            if InCombatLockdown and InCombatLockdown() then return true end
            return false
        end
    end
    ExportPublic("MSUF_IsConfigCombatLocked", IsConfigCombatLocked)

    local ShowConfigCombatLockMessage = _G.MSUF_ShowConfigCombatLockMessage
    if type(ShowConfigCombatLockMessage) ~= "function" then
        ShowConfigCombatLockMessage = function()
            local now = (GetTime and GetTime()) or 0
            if now > 0 and (now - _lastConfigCombatMessage) < 1.25 then return end
            _lastConfigCombatMessage = now

            local msg = "|cffffd700MSUF:|r Menu and Edit Mode are locked in combat. Leave combat to configure MSUF."
            local tr = MSUF and MSUF.Translate
            if type(tr) == "function" then msg = tr(msg) or msg end
            local shownInline = false
            local m2 = (MSUF and MSUF.MSUF2) or _G.MSUF2
            if m2 and type(m2.ShowStatusFeedback) == "function" then
                m2.ShowStatusFeedback("Combat locked", "combat", 1.6)
                shownInline = true
            end
            if _G.UIErrorsFrame and _G.UIErrorsFrame.AddMessage then
                _G.UIErrorsFrame:AddMessage(msg, 1, 0.82, 0.1)
            end
            if (not shownInline) and print then print(msg) end
        end
    end
    ExportPublic("MSUF_ShowConfigCombatLockMessage", ShowConfigCombatLockMessage)

    local BlockConfigCombatLocked = _G.MSUF_BlockConfigCombatLocked
    if type(BlockConfigCombatLocked) ~= "function" then
        BlockConfigCombatLocked = function()
            local locked = IsConfigCombatLocked and IsConfigCombatLocked()
            if locked then
                if ShowConfigCombatLockMessage then ShowConfigCombatLockMessage() end
                return true
            end
            return false
        end
    end
    ExportPublic("MSUF_BlockConfigCombatLocked", BlockConfigCombatLocked)
end

--- Global helper: restore UIPanelButtonTemplate pieces if another skin/hide pass removed them.
--- This is defensive and safe to call repeatedly; it only touches obvious regions (Left/Middle/Right/Normal/Font).
local ForceShowUIPanelButtonPieces = _G.MSUF_ForceShowUIPanelButtonPieces
if type(ForceShowUIPanelButtonPieces) ~= "function" then
    ForceShowUIPanelButtonPieces = function(btn)
        if not btn then return end

        local name = (btn.GetName and btn:GetName()) or nil
        local left  = btn.Left   or (name and _G[name .. "Left"])   or nil
        local mid   = btn.Middle or (name and _G[name .. "Middle"]) or nil
        local right = btn.Right  or (name and _G[name .. "Right"])  or nil

        local function ShowTex(t)
            if not t then return end
            if t.SetAlpha then t:SetAlpha(1) end
            if t.Show then t:Show() end
        end

        ShowTex(left)
        ShowTex(mid)
        ShowTex(right)

        local nt = (btn.GetNormalTexture and btn:GetNormalTexture()) or nil
        ShowTex(nt)

        local fs = (btn.GetFontString and btn:GetFontString()) or btn.Text or nil
        if fs then
            if fs.SetAlpha then fs:SetAlpha(1) end
            if fs.SetDrawLayer then fs:SetDrawLayer("OVERLAY", 7) end
            if fs.Show then fs:Show() end
        end

        if btn.SetAlpha then btn:SetAlpha(1) end
    end
end
ExportPublic("MSUF_ForceShowUIPanelButtonPieces", ForceShowUIPanelButtonPieces)

local GetProfileScopedCache = _G.MSUF_GetProfileScopedCache
if type(GetProfileScopedCache) ~= "function" then
    GetProfileScopedCache = function(rootKey)
        if type(rootKey) ~= "string" or rootKey == "" then return nil end
        ExportPublic("MSUF_GlobalDB", type(_G.MSUF_GlobalDB) == "table" and _G.MSUF_GlobalDB or {})
        local gdb = _G.MSUF_GlobalDB
        gdb[rootKey] = type(gdb[rootKey]) == "table" and gdb[rootKey] or {}

        local charKey = "global"
        local charFn = _G.MSUF_GetCharKey
        if type(charFn) == "function" then
            local key = charFn()
            if type(key) == "string" and key ~= "" then
                charKey = key
            end
        end

        local profile = _G.MSUF_ActiveProfile
        if type(profile) ~= "string" or profile == "" then
            local char = type(gdb.char) == "table" and gdb.char[charKey]
            profile = type(char) == "table" and char.activeProfile or nil
        end
        if type(profile) ~= "string" or profile == "" then
            profile = "Default"
        end

        local byChar = gdb[rootKey][charKey]
        if type(byChar) ~= "table" then
            byChar = {}
            gdb[rootKey][charKey] = byChar
        end

        local bucket = byChar[profile]
        if type(bucket) ~= "table" then
            bucket = {}
            byChar[profile] = bucket
        end
        return bucket
    end
end
ExportPublic("MSUF_GetProfileScopedCache", GetProfileScopedCache)

--- i18n UI helpers - prevent text overflow in translated locales.
--- Checkbox text in narrow columns can overflow when German/Spanish/French
--- strings are longer than English. These helpers clamp the FontString
--- width so text truncates instead of overlapping adjacent UI elements.
--- Usage: MSUF_ClampCheckboxText(cb, maxPixelWidth)

--- Clamp a checkbox's label FontString to a max pixel width.
--- Disables word-wrap so long translations truncate cleanly.
--- Safe to call on nil / non-checkbox frames (no-op).
local function MSUF_ClampCheckboxText(cb, maxWidth)
    if not cb or not maxWidth then return end
    local fs = cb.Text or cb.text
    if (not fs) and cb.GetName then
        local name = cb:GetName()
        if name then fs = _G[name .. "Text"] end
    end
    if not (fs and fs.SetWidth) then return end
    fs:SetWidth(maxWidth)
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(false) end
end
ExportPublic("MSUF_ClampCheckboxText", MSUF_ClampCheckboxText)

-- Shared coordinate conversion must precede both Edit Mode and UF engine loading.
local function FrameRectToUI(frame)
  if not (frame and frame.GetLeft and frame.GetRight and frame.GetTop and frame.GetBottom) then
    return nil
  end
  if frame.IsShown and not frame:IsShown() then return nil end
  local l, r, t, b = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
  if not (l and r and t and b) then return nil end
  local fS = frame.GetEffectiveScale and frame:GetEffectiveScale() or 1
  local uiS = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
  if not fS or fS == 0 then fS = 1 end
  if not uiS or uiS == 0 then uiS = 1 end
  local ratio = fS / uiS
  return l * ratio, r * ratio, t * ratio, b * ratio
end
U.FrameRectToUI = FrameRectToUI
ExportPublic("MSUF_UF_FrameRectToUI", FrameRectToUI)

-- Edit Mode UI loads before its controller; bind this optional LoD apply route early.
local function RequestGroupGeometryApply(kind, reason)
    if not kind then return false end
    local menu = (MSUF and MSUF.MSUF2) or _G.MSUF2
    local apply = (menu and menu.ApplyService) or _G.MSUF_Menu2_ApplyService
    if not (apply and type(apply.RequestGroup) == "function") then return false end
    apply.RequestGroup(kind, "geometry", reason or "EM2_GROUP_GEOMETRY")
    if type(apply.Flush) == "function" then apply.Flush() end
    return true
end
ExportPublic("MSUF_RequestGroupGeometryApply", RequestGroupGeometryApply)

local function GetGeneralDB()
    local db = _G.MSUF_DB
    return type(db) == "table" and type(db.general) == "table" and db.general or nil
end
U.GetGeneralDB = GetGeneralDB
ExportPublic("MSUF_GetGeneralDB", GetGeneralDB)

local function CooldownAnchorSupported()
  local supported = _G.MSUF_IsCooldownAnchorSupported
  if type(supported) == "function" then return supported() == true end
  return type(_G.C_CooldownViewer) == "table"
end
U.CooldownAnchorSupported = CooldownAnchorSupported
ExportPublic("MSUF_CooldownAnchorSupported", CooldownAnchorSupported)

local function IsPlayerInCombat()
    return _G.MSUF_InCombat == true
        or ((_G.InCombatLockdown and _G.InCombatLockdown()) and true or false)
        or ((_G.UnitAffectingCombat and _G.UnitAffectingCombat("player")) and true or false)
end
U.IsPlayerInCombat = IsPlayerInCombat
ExportPublic("MSUF_IsPlayerInCombat", IsPlayerInCombat)

local function RoundOffset(value)
    value = tonumber(value) or 0
    return value >= 0 and math.floor(value + 0.5) or math.ceil(value - 0.5)
end
U.RoundOffset = RoundOffset
ExportPublic("MSUF_RoundOffset", RoundOffset)

local function IsGlobalCooldownAnchorEnabled(general)
  local isEnabled = _G.MSUF_IsCooldownAnchorEnabled
  if type(isEnabled) == "function" then return isEnabled(general) == true end
  return CooldownAnchorSupported() and general and general.anchorToCooldown == true or false
end
U.IsGlobalCooldownAnchorEnabled = IsGlobalCooldownAnchorEnabled
ExportPublic("MSUF_GlobalCooldownAnchorEnabled", IsGlobalCooldownAnchorEnabled)

local function IsGroupUnitToken(unit)
    return type(unit) == "string" and (unit:match("^party%d+$") ~= nil or unit:match("^raid%d+$") ~= nil)
end
U.IsGroupUnitToken = IsGroupUnitToken
ExportPublic("MSUF_IsGroupUnitToken", IsGroupUnitToken)
