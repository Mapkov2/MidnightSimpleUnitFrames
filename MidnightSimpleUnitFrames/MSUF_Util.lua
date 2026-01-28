local addonName, ns = ...
ns = ns or {}

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

-- ---------------------------------------------------------------------------
-- Pixel perfect helpers (ElvUI-style)
--
-- Goal:
--   * Provide a single, consistent "1 physical pixel" unit in WoW UI coords.
--   * Snap offsets to that grid so 1px borders are always crisp and uniform.
--
-- IMPORTANT:
--   * Keep this cheap: cached + auto-refresh when UI scale or resolution changes.
--   * Expose helpers globally so unitframes and LoD modules (castbars, etc.)
--     can use the exact same snapping logic.
-- ---------------------------------------------------------------------------

do
    local UIParent = UIParent
    local GetPhysicalScreenSize = GetPhysicalScreenSize
    local InCombatLockdown = InCombatLockdown

    local _cachedPhysH
    local _cachedScale
    local _cachedMult

    local function RecalcMult()
        local physW, physH
        if GetPhysicalScreenSize then
            physW, physH = GetPhysicalScreenSize()
        end

        local scale = 1
        if UIParent and UIParent.GetScale then
            scale = UIParent:GetScale() or 1
        end
        if scale == 0 then scale = 1 end

        -- ElvUI-style: "perfect" is UI units per physical pixel at 768p.
        -- mult is then adjusted by the current UIParent scale.
        local mult
        if physH and physH > 0 then
            mult = (768 / physH) / scale
        else
            -- Fallback (should be rare): effectiveScale to UI units per pixel.
            local eff = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or scale
            if eff == 0 then eff = 1 end
            mult = 1 / eff
        end

        if mult == 0 then mult = 1 end
        _cachedPhysH = physH
        _cachedScale = scale
        _cachedMult = mult
    end

    local function EnsureMult()
        if not _cachedMult then
            RecalcMult()
            return
        end

        local physH
        if GetPhysicalScreenSize then
            local _, h = GetPhysicalScreenSize()
            physH = h
        end
        local scale = (UIParent and UIParent.GetScale and UIParent:GetScale()) or 1
        if scale == 0 then scale = 1 end

        if (physH and physH ~= _cachedPhysH) or (scale ~= _cachedScale) then
            RecalcMult()
        end
    end

    -- Snap a value (in "pixel units") to the physical-pixel grid.
    -- If you pass 1, you get exactly one physical pixel in UI coordinates.
    function _G.MSUF_Scale(x)
        if type(x) ~= "number" then
            return x
        end
        EnsureMult()
        local m = _cachedMult or 1
        if m == 1 or x == 0 then
            return x
        end
        local y = m > 1 and m or -m
        return x - x % (x < 0 and y or -y)
    end

    -- Return the UI-unit size of exactly one physical pixel.
    function _G.MSUF_Pixel()
        EnsureMult()
        return _cachedMult or 1
    end

    function _G.MSUF_SetOutside(obj, anchor, xOffsetPx, yOffsetPx, anchor2)
        if not obj then return end
        if not anchor and obj.GetParent then
            anchor = obj:GetParent()
        end
        if not anchor then return end
        xOffsetPx = xOffsetPx or 1
        yOffsetPx = yOffsetPx or 1

        local sx = _G.MSUF_Scale(xOffsetPx)
        local sy = _G.MSUF_Scale(yOffsetPx)

        obj:ClearAllPoints()
        obj:SetPoint("TOPLEFT", anchor, "TOPLEFT", -sx, sy)
        obj:SetPoint("BOTTOMRIGHT", anchor2 or anchor, "BOTTOMRIGHT", sx, -sy)
    end

    function _G.MSUF_SetInside(obj, anchor, xOffsetPx, yOffsetPx, anchor2)
        if not obj then return end
        if not anchor and obj.GetParent then
            anchor = obj:GetParent()
        end
        if not anchor then return end
        xOffsetPx = xOffsetPx or 1
        yOffsetPx = yOffsetPx or 1

        local sx = _G.MSUF_Scale(xOffsetPx)
        local sy = _G.MSUF_Scale(yOffsetPx)

        obj:ClearAllPoints()
        obj:SetPoint("TOPLEFT", anchor, "TOPLEFT", sx, -sy)
        obj:SetPoint("BOTTOMRIGHT", anchor2 or anchor, "BOTTOMRIGHT", -sx, sy)
    end

    -- Optional convenience: force a mult refresh (rare; mostly for debug).
    function _G.MSUF_UpdatePixelPerfect()
        -- Never hard-force during combat; avoid any potential layout/taint chains.
        if InCombatLockdown and InCombatLockdown() then
            return false
        end
        RecalcMult()
        return true
    end
end

