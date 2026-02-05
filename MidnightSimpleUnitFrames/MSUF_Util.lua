--[[Perfy has instrumented this file]] local Perfy_GetTime, Perfy_Trace, Perfy_Trace_Passthrough = Perfy_GetTime, Perfy_Trace, Perfy_Trace_Passthrough; Perfy_Trace(Perfy_GetTime(), "Enter", "(main chunk) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua"); local addonName, ns = ...
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
    function _G._MSUF_SetAtlasOrFallback(tex, atlasName, fallbackTexture) Perfy_Trace(Perfy_GetTime(), "Enter", "_G._MSUF_SetAtlasOrFallback file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:18:4");
        if not tex then
            Perfy_Trace(Perfy_GetTime(), "Leave", "_G._MSUF_SetAtlasOrFallback file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:18:4"); return false
        end

        if atlasName and tex.SetAtlas then
            -- SetAtlas may error if atlasName is invalid in the current build.
            local ok = pcall(tex.SetAtlas, tex, atlasName, true)
            if ok then
                Perfy_Trace(Perfy_GetTime(), "Leave", "_G._MSUF_SetAtlasOrFallback file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:18:4"); return true
            end
        end

        if fallbackTexture and tex.SetTexture then
            tex:SetTexture(fallbackTexture)
            Perfy_Trace(Perfy_GetTime(), "Leave", "_G._MSUF_SetAtlasOrFallback file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:18:4"); return true
        end

        Perfy_Trace(Perfy_GetTime(), "Leave", "_G._MSUF_SetAtlasOrFallback file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:18:4"); return false
    end
end

function MSUF_DeepCopy(value, seen) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_DeepCopy file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:40:0");
    if type(value) ~= "table" then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_DeepCopy file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:40:0"); return value
    end
    seen = seen or {}
    if seen[value] then
        return Perfy_Trace_Passthrough("Leave", "MSUF_DeepCopy file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:40:0", seen[value])
    end
    local copy = {}
    seen[value] = copy
    for k, v in pairs(value) do
        copy[MSUF_DeepCopy(k, seen)] = MSUF_DeepCopy(v, seen)
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_DeepCopy file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:40:0"); return copy
end

function MSUF_CaptureKeys(src, keys) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_CaptureKeys file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:56:0");
    local out = {}
    if type(src) ~= "table" or type(keys) ~= "table" then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_CaptureKeys file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:56:0"); return out
    end
    for i = 1, #keys do
        local k = keys[i]
        out[k] = src[k]
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_CaptureKeys file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:56:0"); return out
end

function MSUF_RestoreKeys(dst, snap) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_RestoreKeys file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:68:0");
    if type(dst) ~= "table" or type(snap) ~= "table" then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_RestoreKeys file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:68:0"); return
    end
    for k, v in pairs(snap) do
        dst[k] = v -- assigning nil removes the key (restores defaults)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_RestoreKeys file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:68:0"); end

function MSUF_ClampAlpha(a, default) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_ClampAlpha file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:77:0");
    a = tonumber(a) or default or 1
    if a < 0 then
        a = 0
    elseif a > 1 then
        a = 1
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ClampAlpha file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:77:0"); return a
end

function MSUF_ClampScale(s, default, maxValue) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_ClampScale file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:87:0");
    s = tonumber(s) or default or 1
    if s <= 0 then
        s = default or 1
    end
    if maxValue and s > maxValue then
        s = maxValue
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ClampScale file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:87:0"); return s
end

function MSUF_GetNumber(v, default, minValue, maxValue) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_GetNumber file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:98:0");
    local n = tonumber(v) or default
    if minValue and n < minValue then
        n = minValue
    end
    if maxValue and n > maxValue then
        n = maxValue
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_GetNumber file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:98:0"); return n
end

function MSUF_Clamp(v, lo, hi) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_Clamp file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:109:0");
    if v < lo then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_Clamp file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:109:0"); return lo end
    if v > hi then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_Clamp file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:109:0"); return hi end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_Clamp file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:109:0"); return v
end

function MSUF_SetTextIfChanged(fs, text) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_SetTextIfChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:115:0");
    if not fs then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetTextIfChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:115:0"); return end

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
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetTextIfChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:115:0"); end


function MSUF_SetCastTimeText(frame, seconds) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_SetCastTimeText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:137:0");
    local fs = frame and frame.timeText
    if not fs then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetCastTimeText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:137:0"); return end

    if type(seconds) == "nil" then
        MSUF_SetTextIfChanged(fs, "")
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetCastTimeText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:137:0"); return
    end

    -- Midnight/Beta "secret value" safety:
    -- Avoid arithmetic directly on potentially secret values by converting to a Lua number.
    local n = tonumber(seconds)
    if type(n) ~= "number" then
        MSUF_SetTextIfChanged(fs, "")
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetCastTimeText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:137:0"); return
    end

    if fs.SetFormattedText then
        fs:SetFormattedText("%.1f", n)
    else
        MSUF_SetTextIfChanged(fs, string.format("%.1f", n))
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetCastTimeText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:137:0"); end


function MSUF_SetFormattedTextIfChanged(fs, fmt, ...) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_SetFormattedTextIfChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:162:0");
    if not fs then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetFormattedTextIfChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:162:0"); return end
    if fmt == nil then
        MSUF_SetTextIfChanged(fs, "")
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetFormattedTextIfChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:162:0"); return
    end
    -- Prefer the C-side formatter when available (faster + more secret-safe).
    if fs.SetFormattedText then
        fs:SetFormattedText(fmt, ...)
    else
        MSUF_SetTextIfChanged(fs, string.format(fmt, ...))
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetFormattedTextIfChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:162:0"); end

function MSUF_SetTimeTextTenth(fs, seconds) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_SetTimeTextTenth file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:176:0");
    if not fs then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetTimeTextTenth file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:176:0"); return end

    if type(seconds) == "nil" then
        MSUF_SetTextIfChanged(fs, "")
        fs.MSUF_lastTimeTenth = nil
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetTimeTextTenth file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:176:0"); return
    end

    -- Midnight/Beta "secret value" safety:
    -- Avoid arithmetic directly on potentially secret values.
    local n = tonumber(seconds)
    if type(n) ~= "number" then
        MSUF_SetTextIfChanged(fs, "")
        fs.MSUF_lastTimeTenth = nil
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetTimeTextTenth file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:176:0"); return
    end

    -- Round to tenths (0.1s) to match display.
    local tenths = math.floor(n * 10 + 0.5)
    if fs.MSUF_lastTimeTenth ~= tenths then
        fs.MSUF_lastTimeTenth = tenths
        MSUF_SetTextIfChanged(fs, string.format("%.1f", tenths / 10))
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetTimeTextTenth file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:176:0"); end


function MSUF_SetAlphaIfChanged(f, a) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_SetAlphaIfChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:203:0");
    if not f or not f.SetAlpha or a == nil then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetAlphaIfChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:203:0"); return end
    local prev = f._msufAlpha
    if prev == nil or math.abs(prev - a) > 0.001 then
        f:SetAlpha(a)
        f._msufAlpha = a
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetAlphaIfChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:203:0"); end

function MSUF_SetWidthIfChanged(f, w) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_SetWidthIfChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:212:0");
    if not f or not f.SetWidth or not w or w <= 0 then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetWidthIfChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:212:0"); return end
    local prev = f._msufW
    if prev == nil or math.abs(prev - w) > 0.01 then
        f:SetWidth(w)
        f._msufW = w
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetWidthIfChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:212:0"); end

function MSUF_SetHeightIfChanged(f, h) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_SetHeightIfChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:221:0");
    if not f or not f.SetHeight or not h or h <= 0 then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetHeightIfChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:221:0"); return end
    local prev = f._msufH
    if prev == nil or math.abs(prev - h) > 0.01 then
        f:SetHeight(h)
        f._msufH = h
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetHeightIfChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:221:0"); end

function MSUF_SetPointIfChanged(f, point, relTo, relPoint, ofsX, ofsY) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_SetPointIfChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:230:0");
    if not f or not f.SetPoint then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetPointIfChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:230:0"); return end
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
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetPointIfChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:230:0"); end

function MSUF_SetJustifyHIfChanged(fs, justify) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_SetJustifyHIfChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:244:0");
    if not fs or not fs.SetJustifyH or not justify then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetJustifyHIfChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:244:0"); return end
    if fs._msufJustifyH ~= justify then
        fs:SetJustifyH(justify)
        fs._msufJustifyH = justify
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetJustifyHIfChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:244:0"); end

function MSUF_SetSliderValueSilent(slider, value) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_SetSliderValueSilent file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:252:0");
    if not slider or not slider.SetValue then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetSliderValueSilent file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:252:0"); return end
    slider.MSUF_SkipCallback = true
    slider:SetValue(value)
    slider.MSUF_SkipCallback = false
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetSliderValueSilent file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:252:0"); end

function MSUF_ClampToSlider(slider, value) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_ClampToSlider file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:259:0");
    if type(value) ~= "number" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ClampToSlider file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:259:0"); return value end
    if slider and type(slider.minVal) == "number" then
        value = math.max(slider.minVal, value)
    end
    if slider and type(slider.maxVal) == "number" then
        value = math.min(slider.maxVal, value)
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ClampToSlider file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:259:0"); return value
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

function _G.MSUF_CombatGate_InCombat() Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_CombatGate_InCombat file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:315:0");
    return Perfy_Trace_Passthrough("Leave", "_G.MSUF_CombatGate_InCombat file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:315:0", InCombatLockdown and InCombatLockdown() or false)
end

local function _MSUF_CombatGate_EnsureFrame(gate) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_CombatGate_EnsureFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:319:6");
    if gate._frame then return Perfy_Trace_Passthrough("Leave", "_MSUF_CombatGate_EnsureFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:319:6", gate._frame) end

    local f = CreateFrame("Frame")
    gate._frame = f
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:325:27");
        if _G.MSUF_CombatGate_Flush then
            _G.MSUF_CombatGate_Flush()
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:325:27"); end)
    Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_CombatGate_EnsureFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:319:6"); return f
end

function _G.MSUF_CombatGate_Call(key, fn, ...) Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_CombatGate_Call file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:333:0");
    if type(fn) ~= "function" then Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_CombatGate_Call file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:333:0"); return end

    -- Fast-path: out of combat, just run.
    if not (InCombatLockdown and InCombatLockdown()) then
        return Perfy_Trace_Passthrough("Leave", "_G.MSUF_CombatGate_Call file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:333:0", fn(...))
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
Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_CombatGate_Call file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:333:0"); end

function _G.MSUF_CombatGate_Clear(key) Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_CombatGate_Clear file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:383:0");
    if key == nil then Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_CombatGate_Clear file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:383:0"); return end
    local gate = _G.MSUF_CombatGate
    local pending = gate and gate._pending
    if not pending then Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_CombatGate_Clear file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:383:0"); return end
    pending[key] = nil
Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_CombatGate_Clear file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:383:0"); end

function _G.MSUF_CombatGate_Flush() Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_CombatGate_Flush file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:391:0");
    -- Still in combat -> keep pending.
    if InCombatLockdown and InCombatLockdown() then
        Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_CombatGate_Flush file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:391:0"); return false
    end

    local gate = _G.MSUF_CombatGate
    local pending = gate and gate._pending
    local order = gate and gate._order
    if not pending or not order or #order == 0 then
        Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_CombatGate_Flush file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:391:0"); return true
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

    Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_CombatGate_Flush file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:391:0"); return true
end

-- Convenience alias used by some modules (optional).
_G.MSUF_CombatGate_CallSafe = _G.MSUF_CombatGate_Call


do
    local UIParent = UIParent
    local GetPhysicalScreenSize = GetPhysicalScreenSize
    local InCombatLockdown = InCombatLockdown

    local _cachedPhysH
    local _cachedBase768

    local function EnsureBase() Perfy_Trace(Perfy_GetTime(), "Enter", "EnsureBase file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:437:10");
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
    Perfy_Trace(Perfy_GetTime(), "Leave", "EnsureBase file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:437:10"); end

    local function GetStepFor(frame) Perfy_Trace(Perfy_GetTime(), "Enter", "GetStepFor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:455:10");
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
            return Perfy_Trace_Passthrough("Leave", "GetStepFor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:455:10", _cachedBase768 / eff)
        end
        return Perfy_Trace_Passthrough("Leave", "GetStepFor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:455:10", 1 / eff)
    end

    local function RoundToGrid(v, step) Perfy_Trace(Perfy_GetTime(), "Enter", "RoundToGrid file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:474:10");
        if step == 0 or v == 0 then
            Perfy_Trace(Perfy_GetTime(), "Leave", "RoundToGrid file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:474:10"); return v
        end
        local q = v / step
        if q >= 0 then
            q = math.floor(q + 0.5)
        else
            q = math.ceil(q - 0.5)
        end
        local out = q * step
        if out == 0 then out = 0 end
        Perfy_Trace(Perfy_GetTime(), "Leave", "RoundToGrid file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:474:10"); return out
    end

    function _G.MSUF_Snap(frame, v) Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_Snap file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:489:4");
        if type(v) ~= "number" then
            Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_Snap file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:489:4"); return v
        end
        local step = GetStepFor(frame)
        return Perfy_Trace_Passthrough("Leave", "_G.MSUF_Snap file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:489:4", RoundToGrid(v, step))
    end

    function _G.MSUF_Pixel(frame) Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_Pixel file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:497:4");
        return Perfy_Trace_Passthrough("Leave", "_G.MSUF_Pixel file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:497:4", GetStepFor(frame))
    end

    function _G.MSUF_Scale(v) Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_Scale file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:501:4");
        return Perfy_Trace_Passthrough("Leave", "_G.MSUF_Scale file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:501:4", _G.MSUF_Snap(UIParent, v))
    end

    function _G.MSUF_SetOutside(obj, anchor, xOffset, yOffset, anchor2) Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_SetOutside file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:505:4");
        if not obj then Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_SetOutside file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:505:4"); return end
        if not anchor and obj.GetParent then
            anchor = obj:GetParent()
        end
        if not anchor then Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_SetOutside file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:505:4"); return end

        xOffset = xOffset or 1
        yOffset = yOffset or 1

        local snap = _G.MSUF_Snap
        local sx = (type(snap) == "function") and snap(anchor, xOffset) or xOffset
        local sy = (type(snap) == "function") and snap(anchor, yOffset) or yOffset

        obj:ClearAllPoints()
        obj:SetPoint("TOPLEFT", anchor, "TOPLEFT", -sx, sy)
        obj:SetPoint("BOTTOMRIGHT", anchor2 or anchor, "BOTTOMRIGHT", sx, -sy)
    Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_SetOutside file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:505:4"); end

    function _G.MSUF_SetInside(obj, anchor, xOffset, yOffset, anchor2) Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_SetInside file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:524:4");
        if not obj then Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_SetInside file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:524:4"); return end
        if not anchor and obj.GetParent then
            anchor = obj:GetParent()
        end
        if not anchor then Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_SetInside file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:524:4"); return end

        xOffset = xOffset or 1
        yOffset = yOffset or 1

        local snap = _G.MSUF_Snap
        local sx = (type(snap) == "function") and snap(anchor, xOffset) or xOffset
        local sy = (type(snap) == "function") and snap(anchor, yOffset) or yOffset

        obj:ClearAllPoints()
        obj:SetPoint("TOPLEFT", anchor, "TOPLEFT", sx, -sy)
        obj:SetPoint("BOTTOMRIGHT", anchor2 or anchor, "BOTTOMRIGHT", -sx, sy)
    Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_SetInside file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:524:4"); end

    function _G.MSUF_UpdatePixelPerfect() Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_UpdatePixelPerfect file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:543:4");
        if InCombatLockdown and InCombatLockdown() then
            Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_UpdatePixelPerfect file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:543:4"); return false
        end
        _cachedPhysH = nil
        _cachedBase768 = nil
        EnsureBase()
        Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_UpdatePixelPerfect file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua:543:4"); return true
    end
end


Perfy_Trace(Perfy_GetTime(), "Leave", "(main chunk) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Util.lua");