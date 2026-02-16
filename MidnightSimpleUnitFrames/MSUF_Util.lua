local addonName, ns = ...
ns = ns or {}

-- =========================================================================
-- PERF LOCALS (core runtime)
--  - Reduce global table lookups in high-frequency event/render paths.
--  - Secret-safe: localizing function references only (no value comparisons).
-- =========================================================================
local type, tostring, tonumber, select = type, tostring, tonumber, select
local pairs, ipairs, next = pairs, ipairs, next
local math_min, math_max, math_floor = math.min, math.max, math.floor
local string_format, string_match, string_sub = string.format, string.match, string.sub
local UnitExists, UnitIsPlayer = UnitExists, UnitIsPlayer
local UnitHealth, UnitHealthMax = UnitHealth, UnitHealthMax
local UnitPower, UnitPowerMax = UnitPower, UnitPowerMax
local UnitPowerType = UnitPowerType
local UnitHealthPercent, UnitPowerPercent = UnitHealthPercent, UnitPowerPercent
local InCombatLockdown = InCombatLockdown
local CreateFrame, GetTime = CreateFrame, GetTime

-- MSUF_Util.lua
-- Stateless helpers / pure functions extracted from MidnightSimpleUnitFrames.lua
-- Keep names stable (globals) to avoid touching call-sites.

ns.MSUF_Util = ns.MSUF_Util or {}
local U = ns.MSUF_Util
_G.MSUF_Util = U

-- ---------------------------------------------------------------------------
-- Atlas helper used by status/state indicator icons.
-- Some call-sites use a global helper name; provide it here as a safe fallback
-- so indicator modules can remain self-contained without load-order fragility.
-- Returns true if something was applied.
if type(_G._MSUF_SetAtlasOrFallback) ~= "function" then
    function _G._MSUF_SetAtlasOrFallback(tex, atlasName, fallbackTexture)
        if not tex then
            return false
        end

        if atlasName and tex.SetAtlas then
            -- SetAtlas may error if atlasName is invalid in the current build.
            local ok = pcall(tex.SetAtlas, tex, atlasName, true)
            if ok then
                return true
            end
        end

        if fallbackTexture and tex.SetTexture then
            tex:SetTexture(fallbackTexture)
            return true
        end

        return false
    end
end

function MSUF_DeepCopy(value, seen)
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

function MSUF_CaptureKeys(src, keys)
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

function MSUF_RestoreKeys(dst, snap)
    if type(dst) ~= "table" or type(snap) ~= "table" then
        return
    end
    for k, v in pairs(snap) do
        dst[k] = v -- assigning nil removes the key (restores defaults)
    end
end

function MSUF_ClampAlpha(a, default)
    a = tonumber(a) or default or 1
    if a < 0 then
        a = 0
    elseif a > 1 then
        a = 1
    end
    return a
end

function MSUF_ClampScale(s, default, maxValue)
    s = tonumber(s) or default or 1
    if s <= 0 then
        s = default or 1
    end
    if maxValue and s > maxValue then
        s = maxValue
    end
    return s
end

function MSUF_GetNumber(v, default, minValue, maxValue)
    local n = tonumber(v) or default
    if minValue and n < minValue then
        n = minValue
    end
    if maxValue and n > maxValue then
        n = maxValue
    end
    return n
end

function MSUF_Clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function MSUF_SetTextIfChanged(fs, text)
    if not fs then return end

    -- Midnight/Beta "secret value" safety:
    -- Never compare or cache text, because secret values will error on equality checks.
    -- Just push the text through to the FontString.
    local tt = type(text)
    if tt == "nil" then
        fs:SetText("")
    elseif tt == "string" then
        fs:SetText(text)
    elseif tt == "number" then
        -- IMPORTANT: do NOT tostring() here. Midnight/Beta "secret values" can
        -- error during string conversion; the FontString API can handle numbers.
        fs:SetText(text)
    else
        -- Be conservative: avoid passing unknown types (could error without pcall).
        fs:SetText("")
    end
end


function MSUF_SetCastTimeText(frame, seconds)
    local fs = frame and frame.timeText
    if not fs then return end

    if type(seconds) == "nil" then
        MSUF_SetTextIfChanged(fs, "")
        return
    end

    -- Midnight/Beta "secret value" safety:
    -- Avoid arithmetic directly on potentially secret values by converting to a Lua number.
    local n = tonumber(seconds)
    if type(n) ~= "number" then
        MSUF_SetTextIfChanged(fs, "")
        return
    end

    if fs.SetFormattedText then
        fs:SetFormattedText("%.1f", n)
    else
        MSUF_SetTextIfChanged(fs, string.format("%.1f", n))
    end
end


function MSUF_SetFormattedTextIfChanged(fs, fmt, ...)
    if not fs then return end
    if fmt == nil then
        MSUF_SetTextIfChanged(fs, "")
        return
    end
    -- Prefer the C-side formatter when available (faster + more secret-safe).
    if fs.SetFormattedText then
        fs:SetFormattedText(fmt, ...)
    else
        MSUF_SetTextIfChanged(fs, string.format(fmt, ...))
    end
end

function MSUF_SetTimeTextTenth(fs, seconds)
    if not fs then return end

    if type(seconds) == "nil" then
        MSUF_SetTextIfChanged(fs, "")
        fs.MSUF_lastTimeTenth = nil
        return
    end

    -- Midnight/Beta "secret value" safety:
    -- Avoid arithmetic directly on potentially secret values.
    local n = tonumber(seconds)
    if type(n) ~= "number" then
        MSUF_SetTextIfChanged(fs, "")
        fs.MSUF_lastTimeTenth = nil
        return
    end

    -- Round to tenths (0.1s) to match display.
    local tenths = math.floor(n * 10 + 0.5)
    if fs.MSUF_lastTimeTenth ~= tenths then
        fs.MSUF_lastTimeTenth = tenths
        MSUF_SetTextIfChanged(fs, string.format("%.1f", tenths / 10))
    end
end

-- ---------------------------------------------------------------------------
-- Stamp cache (performance)
--
-- Avoid re-applying expensive UI state (SetFont/SetPoint/SetColor/etc.) when
-- the inputs are unchanged.
--
-- Secret-safe rules:
-- - Only compares primitive Lua types (number/string/boolean/nil).
-- - Any non-primitive value is treated as "changed" to avoid secret-value
--   equality errors.
-- - Stores the last tuple in a reusable table on the target object.

local function _MSUF_IsStampPrimitive(v)
    local t = type(v)
    return (t == "number" or t == "string" or t == "boolean" or t == "nil")
end

function MSUF_StampChanged(obj, stampKey, ...)
    if not obj or not stampKey then
        return true
    end
    local cacheKey = "_msufStamp_" .. stampKey
    local prev = obj[cacheKey]
    if not prev then
        prev = {}
        obj[cacheKey] = prev
        -- store
        local n = select('#', ...)
        prev._n = n
        for i = 1, n do
            local v = select(i, ...)
            if not _MSUF_IsStampPrimitive(v) then
                -- unknown type => always "changed"; do not cache
                prev._n = 0
                return true
            end
            prev[i] = v
        end
        return true
    end

    local n = select('#', ...)
    if prev._n ~= n then
        prev._n = n
        for i = 1, n do
            local v = select(i, ...)
            if not _MSUF_IsStampPrimitive(v) then
                prev._n = 0
                return true
            end
            prev[i] = v
        end
        return true
    end

    -- compare
    for i = 1, n do
        local v = select(i, ...)
        if not _MSUF_IsStampPrimitive(v) then
            prev._n = 0
            return true
        end
        if prev[i] ~= v then
            -- update cached tuple
            for j = i, n do
                local vv = select(j, ...)
                if not _MSUF_IsStampPrimitive(vv) then
                    prev._n = 0
                    return true
                end
                prev[j] = vv
            end
            return true
        end
    end
    return false
end



function MSUF_SetAlphaIfChanged(f, a)
    if not f or not f.SetAlpha or a == nil then return end
    local prev = f._msufAlpha
    if prev == nil or math.abs(prev - a) > 0.001 then
        f:SetAlpha(a)
        f._msufAlpha = a
    end
end

function MSUF_SetWidthIfChanged(f, w)
    if not f or not f.SetWidth or not w or w <= 0 then return end
    local prev = f._msufW
    if prev == nil or math.abs(prev - w) > 0.01 then
        f:SetWidth(w)
        f._msufW = w
    end
end

function MSUF_SetHeightIfChanged(f, h)
    if not f or not f.SetHeight or not h or h <= 0 then return end
    local prev = f._msufH
    if prev == nil or math.abs(prev - h) > 0.01 then
        f:SetHeight(h)
        f._msufH = h
    end
end

function MSUF_SetPointIfChanged(f, point, relTo, relPoint, ofsX, ofsY)
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

function MSUF_SetJustifyHIfChanged(fs, justify)
    if not fs or not fs.SetJustifyH or not justify then return end
    if fs._msufJustifyH ~= justify then
        fs:SetJustifyH(justify)
        fs._msufJustifyH = justify
    end
end

function MSUF_SetSliderValueSilent(slider, value)
    if not slider or not slider.SetValue then return end
    slider.MSUF_SkipCallback = true
    slider:SetValue(value)
    slider.MSUF_SkipCallback = false
end

function MSUF_ClampToSlider(slider, value)
    if type(value) ~= "number" then return value end
    if slider and type(slider.minVal) == "number" then
        value = math.max(slider.minVal, value)
    end
    if slider and type(slider.maxVal) == "number" then
        value = math.min(slider.maxVal, value)
    end
    return value
end

-- Table exports (optional convenience)
U.DeepCopy = MSUF_DeepCopy
U.CaptureKeys = MSUF_CaptureKeys
U.RestoreKeys = MSUF_RestoreKeys
U.Clamp = MSUF_Clamp
U.ClampAlpha = MSUF_ClampAlpha
U.ClampScale = MSUF_ClampScale
U.GetNumber = MSUF_GetNumber
U.SetTextIfChanged = MSUF_SetTextIfChanged
U.SetFormattedTextIfChanged = MSUF_SetFormattedTextIfChanged
U.SetCastTimeText = MSUF_SetCastTimeText
U.SetTimeTextTenth = MSUF_SetTimeTextTenth
U.SetAlphaIfChanged = MSUF_SetAlphaIfChanged
U.SetWidthIfChanged = MSUF_SetWidthIfChanged
U.SetHeightIfChanged = MSUF_SetHeightIfChanged
U.SetPointIfChanged = MSUF_SetPointIfChanged
U.SetJustifyHIfChanged = MSUF_SetJustifyHIfChanged
U.SetSliderValueSilent = MSUF_SetSliderValueSilent
U.ClampToSlider = MSUF_ClampToSlider

-- Also keep existing ns exports where older code expects them.
ns.MSUF_DeepCopy = MSUF_DeepCopy
ns.MSUF_CaptureKeys = MSUF_CaptureKeys
ns.MSUF_RestoreKeys = MSUF_RestoreKeys

-- ============================================================================
-- MSUF_CombatGate
--
-- Purpose:
-- Defer combat-locked / secure / taint-sensitive operations until PLAYER_REGEN_ENABLED.
--
-- Design goals:
--  - Zero overhead fast-path out of combat (just one InCombatLockdown() check).
--  - Coalesce by key ("last call wins") to avoid spam and to keep perf stable.
--  - No assumptions about the caller; works for StateDrivers, Secure attributes,
--    Edit Mode binding ops, LoD loads, global UI scale apply, etc.
--
-- Usage:
--  MSUF_CombatGate_Call("visibility:target", RegisterStateDriver, frame, "visibility", expr)
--  MSUF_CombatGate_Call("lod:castbars", MSUF_EnsureAddonLoaded, "MidnightSimpleUnitFrames_Castbars")
--  MSUF_CombatGate_Call(nil, function() ... end)  -- (use sparingly; key coalescing is better)
-- ============================================================================

_G.MSUF_CombatGate = _G.MSUF_CombatGate or {}

function _G.MSUF_CombatGate_InCombat()
    return InCombatLockdown and InCombatLockdown() or false
end

local function _MSUF_CombatGate_EnsureFrame(gate)
    if gate._frame then return gate._frame end

    local f = CreateFrame("Frame")
    gate._frame = f
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent", function()
        if _G.MSUF_CombatGate_Flush then
            _G.MSUF_CombatGate_Flush()
        end
    end)
    return f
end

function _G.MSUF_CombatGate_Call(key, fn, ...)
    if type(fn) ~= "function" then return end

    -- Fast-path: out of combat, just run.
    if not (InCombatLockdown and InCombatLockdown()) then
        return fn(...)
    end

    local gate = _G.MSUF_CombatGate
    gate._pending = gate._pending or {}
    gate._order = gate._order or {}

    local k = key or fn
    local entry = gate._pending[k]
    if not entry then
        entry = {}
        gate._pending[k] = entry
        gate._order[#gate._order + 1] = k
    end

    entry.fn = fn

    -- Store args (last call wins).
    local args = entry.args
    if not args then
        args = {}
        entry.args = args
        entry.maxN = 0
    end

    local n = select("#", ...)
    entry.n = n

    -- Save args without creating per-call tables.
    for i = 1, n do
        args[i] = select(i, ...)
    end

    -- Clear leftovers from previous larger arg lists.
    local maxN = entry.maxN or 0
    if n < maxN then
        for i = n + 1, maxN do
            args[i] = nil
        end
    end
    entry.maxN = (n > maxN) and n or maxN

    _MSUF_CombatGate_EnsureFrame(gate)
end

function _G.MSUF_CombatGate_Clear(key)
    if key == nil then return end
    local gate = _G.MSUF_CombatGate
    local pending = gate and gate._pending
    if not pending then return end
    pending[key] = nil
end

function _G.MSUF_CombatGate_Flush()
    -- Still in combat -> keep pending.
    if InCombatLockdown and InCombatLockdown() then
        return false
    end

    local gate = _G.MSUF_CombatGate
    local pending = gate and gate._pending
    local order = gate and gate._order
    if not pending or not order or #order == 0 then
        return true
    end

    -- Drain queue (preserve order of first enqueue; last args win per key).
    for i = 1, #order do
        local k = order[i]
        local entry = pending[k]
        if entry and entry.fn then
            pending[k] = nil

            local args = entry.args
            local n = entry.n or 0

            -- Call without pcall/xpcall to preserve normal error visibility.
            -- (Flush runs out of combat; if it errors, we want a real stack.)
            entry.fn(table.unpack(args or {}, 1, n))
        end

        order[i] = nil
    end

    return true
end

-- Convenience alias used by some modules (optional).
_G.MSUF_CombatGate_CallSafe = _G.MSUF_CombatGate_Call


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

    function _G.MSUF_Snap(frame, v)
        if type(v) ~= "number" then
            return v
        end
        local step = GetStepFor(frame)
        return RoundToGrid(v, step)
    end

    function _G.MSUF_Pixel(frame)
        return GetStepFor(frame)
    end

    function _G.MSUF_Scale(v)
        return _G.MSUF_Snap(UIParent, v)
    end

    function _G.MSUF_SetOutside(obj, anchor, xOffset, yOffset, anchor2)
        if not obj then return end
        if not anchor and obj.GetParent then
            anchor = obj:GetParent()
        end
        if not anchor then return end

        xOffset = xOffset or 1
        yOffset = yOffset or 1

        local snap = _G.MSUF_Snap
        local sx = (type(snap) == "function") and snap(anchor, xOffset) or xOffset
        local sy = (type(snap) == "function") and snap(anchor, yOffset) or yOffset

        obj:ClearAllPoints()
        obj:SetPoint("TOPLEFT", anchor, "TOPLEFT", -sx, sy)
        obj:SetPoint("BOTTOMRIGHT", anchor2 or anchor, "BOTTOMRIGHT", sx, -sy)
    end

    function _G.MSUF_SetInside(obj, anchor, xOffset, yOffset, anchor2)
        if not obj then return end
        if not anchor and obj.GetParent then
            anchor = obj:GetParent()
        end
        if not anchor then return end

        xOffset = xOffset or 1
        yOffset = yOffset or 1

        local snap = _G.MSUF_Snap
        local sx = (type(snap) == "function") and snap(anchor, xOffset) or xOffset
        local sy = (type(snap) == "function") and snap(anchor, yOffset) or yOffset

        obj:ClearAllPoints()
        obj:SetPoint("TOPLEFT", anchor, "TOPLEFT", sx, -sy)
        obj:SetPoint("BOTTOMRIGHT", anchor2 or anchor, "BOTTOMRIGHT", -sx, sy)
    end

    function _G.MSUF_UpdatePixelPerfect()
        if InCombatLockdown and InCombatLockdown() then
            return false
        end
        _cachedPhysH = nil
        _cachedBase768 = nil
        EnsureBase()
        return true
    end
end

-- =============================================================
-- Phase 2: Global helpers relocated from MSUF_UpdateManager.lua
-- (These must load before any consumer; MSUF_Util.lua is in TOC slot 2.)
-- =============================================================

-- Fast-path replacement for protected calls.
-- Intentionally does NOT catch errors (for maximum performance).
-- Preserves (ok, ...) return convention and returns false if fn is not callable.
if not _G.MSUF_FastCall then
    function _G.MSUF_FastCall(fn, ...)
        if type(fn) ~= "function" then
             return false
        end
        return true, fn(...)
    end
end

-- Global helper: "any edit mode" (MSUF Edit Mode OR Blizzard Edit Mode)
if not _G.MSUF_IsInAnyEditMode then
    function _G.MSUF_IsInAnyEditMode()
        local st = rawget(_G, "MSUF_EditState")
        if type(st) == "table" and st.active == true then
             return true
        end
        if rawget(_G, "MSUF_UnitEditModeActive") == true then
             return true
        end
         return false
    end
end


-- Global helper: restore UIPanelButtonTemplate pieces if another skin/hide pass removed them.
-- This is defensive and safe to call repeatedly; it only touches obvious regions (Left/Middle/Right/Normal/Font).
if not _G.MSUF_ForceShowUIPanelButtonPieces then
    function _G.MSUF_ForceShowUIPanelButtonPieces(btn)
        if not btn then return end

        local name = (btn.GetName and btn:GetName()) or nil
        local left  = btn.Left   or (name and _G[name .. "Left"])   or nil
        local mid   = btn.Middle or (name and _G[name .. "Middle"]) or nil
        local right = btn.Right  or (name and _G[name .. "Right"])  or nil

        local function ShowTex(t)
            if not t then return end
            if t.SetAlpha then pcall(t.SetAlpha, t, 1) end
            if t.Show then pcall(t.Show, t) end
        end

        ShowTex(left)
        ShowTex(mid)
        ShowTex(right)

        local nt = (btn.GetNormalTexture and btn:GetNormalTexture()) or nil
        ShowTex(nt)

        local fs = (btn.GetFontString and btn:GetFontString()) or btn.Text or nil
        if fs then
            if fs.SetAlpha then pcall(fs.SetAlpha, fs, 1) end
            if fs.SetDrawLayer then pcall(fs.SetDrawLayer, fs, "OVERLAY", 7) end
            if fs.Show then pcall(fs.Show, fs) end
        end

        if btn.SetAlpha then pcall(btn.SetAlpha, btn, 1) end
    end
end
