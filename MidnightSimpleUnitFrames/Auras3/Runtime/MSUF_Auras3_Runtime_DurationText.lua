-- Auras3 runtime: DurationText.
-- Native duration formatter/binding cache and text placement. Locale changes invalidate the same cache used by icons and reminder placeholders.
-- The factory runs once at addon load; dependency bindings are local upvalues on live paths.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
MSUF.Auras3RuntimeFactories = MSUF.Auras3RuntimeFactories or {}
MSUF.Auras3RuntimeFactories.DurationText = function(addonName, MSUF, A3, UF, ExportPublic, dependencies)
local table_concat = table.concat
local table_sort = table.sort
local tostring = tostring
local type = type
local Clamp01 = dependencies.Platform.Clamp01
local ClampNumber = dependencies.Platform.ClampNumber
local DEFAULT_SHARED = dependencies.Schema.DEFAULT_SHARED
local FrameLayers = dependencies.Platform.FrameLayers
local Round = dependencies.Platform.Round
local STANDARD_TEXT_FONT = dependencies.Platform.STANDARD_TEXT_FONT

local function ApplyFont(fs, size)
    if not fs then return end
    local readFont = _G.MSUF_GetGlobalFontSettings
    local gen = A3._nativeVisualGen or 0
    if A3._auraFontCacheGen ~= gen or A3._auraFontCacheReader ~= readFont then
        A3._auraFontCacheGen, A3._auraFontCacheReader = gen, readFont
        A3._auraFontPath, A3._auraFontFlags, A3._auraFontR, A3._auraFontG, A3._auraFontB, A3._auraFontShadow = nil, nil, nil, nil, nil, nil
        if type(readFont) == "function" then
            local unusedSize
            A3._auraFontPath, A3._auraFontFlags, A3._auraFontR, A3._auraFontG, A3._auraFontB, unusedSize, A3._auraFontShadow = readFont()
        end
    end
    local fontPath, fontFlags = A3._auraFontPath, A3._auraFontFlags
    local r, g, b, useShadow = A3._auraFontR, A3._auraFontG, A3._auraFontB, A3._auraFontShadow
    fontPath = fontPath or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    fontFlags = fontFlags or "OUTLINE"
    size = ClampNumber(size, 12, 6, 40)
    local general = _G.MSUF_DB and _G.MSUF_DB.general
    local applyResolved = _G.MSUF_ApplyResolvedFont
    if type(applyResolved) == "function" then
        applyResolved(fs, fontPath, size, fontFlags, general and general.fontKey)
    else
        -- Current clients require a valid FontAsset and may raise before a
        -- boolean result is returned. Keep the load-order fallback just as
        -- defensive as the central font service so stale SharedMedia paths can
        -- never escape through profile/runtime apply.
        local called, applied = pcall(fs.SetFont, fs, fontPath, size, fontFlags)
        local ready = called and applied ~= false
        local matches = _G.MSUF_FontApplicationMatches
        if ready and type(matches) == "function" then ready = matches(fs, fontPath, size) == true end
        if not ready then
            if fontPath ~= STANDARD_TEXT_FONT and STANDARD_TEXT_FONT then
                pcall(fs.SetFont, fs, STANDARD_TEXT_FONT, size, fontFlags)
            end
            if type(_G.MSUF_MarkFontApplyFailed) == "function" then _G.MSUF_MarkFontApplyFailed() end
        end
    end
    fs:SetTextColor(r or 1, g or 1, b or 1, 1)
    if useShadow then fs:SetShadowOffset(1, -1) else fs:SetShadowOffset(0, 0) end
end

-- Aura timer text format/color: a C-side NumericRuleFormatter plus a
-- DurationTextBinding template, both evaluated by Blizzard against the secret
-- aura duration object. MSUF only builds/caches them when style config
-- changes; there is no addon timer or OnUpdate work per aura.
local _durationFormatterCache

local function NumericRuleFormatRounding(name, fallback)
    local enum = _G.Enum and _G.Enum.NumericRuleFormatRounding
    if enum and enum[name] ~= nil then return enum[name] end
    local numericRuleFormatter = _G.NumericRuleFormatter and _G.NumericRuleFormatter.Rounding
    if numericRuleFormatter and numericRuleFormatter[name] ~= nil then return numericRuleFormatter[name] end
    return fallback
end

local function ColorEscape(r, g, b)
    return string.format("|cff%02x%02x%02x", Round(Clamp01(r, 1) * 255), Round(Clamp01(g, 1) * 255), Round(Clamp01(b, 1) * 255))
end

local function EscapeFormatLiteral(text)
    return tostring(text or ""):gsub("%%", "%%%%")
end

local function LocalizedTimeSuffix(key, fallback)
    local suffix
    if type(MSUF.Translate) == "function" then
        suffix = MSUF.Translate(key)
        if suffix == key then suffix = nil end
    end
    if suffix == nil or suffix == "" then suffix = fallback end
    return tostring(suffix)
end

-- The binding template carries the render fallbacks the formatter cannot:
-- Blizzard's ApplyDurationText only forwards the secret aura duration and
-- disables the binding when it is zero, so without SetZeroDurationText /
-- SetExpiredText a recycled pool button keeps the previous aura's countdown on
-- permanent auras (flasks, food, raid buffs, poisons). The update interval
-- caps C-side text work at the finest rendered granularity.
local function BuildAuraDurationBinding(formatter, updateInterval)
    local durationUtil = _G.C_DurationUtil
    local createBinding = durationUtil and durationUtil.CreateDurationTextBinding
    if type(createBinding) ~= "function" then return nil end
    local binding = createBinding()
    if not binding then return nil end
    if not (type(binding.SetFormatter) == "function"
        and type(binding.SetZeroDurationText) == "function"
        and type(binding.SetExpiredText) == "function"
        and type(binding.SetUpdateInterval) == "function"
        and type(binding.SetEnabled) == "function")
    then
        return nil
    end
    binding:SetFormatter(formatter)
    binding:SetZeroDurationText("")
    binding:SetExpiredText("")
    binding:SetUpdateInterval(updateInterval)
    binding:SetEnabled(true)
    return binding
end

local function BuildAuraDurationStyle(lane)
    -- Compiled lanes are replaced on config/locale invalidation. Cache the
    -- resolved style record there so pool growth does not rebuild formatter
    -- and binding for every newly initialized AuraButton.
    local cached = type(lane) == "table" and lane._msufA3DurationStyle
    if cached ~= nil then
        if cached == false then return nil end
        return cached
    end

    local general = (_G.MSUF_DB and _G.MSUF_DB.general) or nil
    if not general then return nil end
    local buckets = general.aurasCooldownTextUseBuckets == true
    local decimalSec = ClampNumber(lane and lane.cooldownDecimalSeconds, DEFAULT_SHARED.cooldownDecimalSeconds, 0, 30)

    local stringUtil = _G.C_StringUtil
    local createFormatter = stringUtil and stringUtil.CreateNumericRuleFormatter
    if type(createFormatter) ~= "function" then
        if type(lane) == "table" then lane._msufA3DurationStyle = false end
        return nil
    end

    -- Safe color falls back to the configured global font color when the user has
    -- not picked one, matching the menu's Safe swatch behavior.
    local safe = general.aurasCooldownTextSafeColor
    local sr, sg, sb
    if type(safe) == "table" then
        sr, sg, sb = safe[1] or safe.r, safe[2] or safe.g, safe[3] or safe.b
    elseif type(_G.MSUF_GetConfiguredFontColor) == "function" then
        sr, sg, sb = _G.MSUF_GetConfiguredFontColor()
    end
    sr, sg, sb = Clamp01(sr, 1), Clamp01(sg, 1), Clamp01(sb, 1)

    local warn = general.aurasCooldownTextWarningColor
    local wr, wg, wb = 1, 0.85, 0.20
    if type(warn) == "table" then wr, wg, wb = warn[1] or warn.r or wr, warn[2] or warn.g or wg, warn[3] or warn.b or wb end

    local urgent = general.aurasCooldownTextUrgentColor
    local ur, ug, ub = 1, 0.55, 0.10
    if type(urgent) == "table" then ur, ug, ub = urgent[1] or urgent.r or ur, urgent[2] or urgent.g or ug, urgent[3] or urgent.b or ub end

    -- Three boundaries in seconds, ascending: Urgent < Warning < Safe. A breakpoint's
    -- threshold is the minimum input value it applies to; the highest threshold
    -- <= remaining seconds wins. Above the Safe boundary we emit no color escape so
    -- the text keeps its base font color (the fontstring's own SetTextColor).
    local urgentSec = ClampNumber(general.aurasCooldownTextUrgentSeconds, 5, 0, 600)
    local warningSec = ClampNumber(general.aurasCooldownTextWarningSeconds, 15, 0, 600)
    local safeSec = ClampNumber(general.aurasCooldownTextSafeSeconds, 60, 0, 600)
    if warningSec < urgentSec then warningSec = urgentSec end
    if safeSec < warningSec then safeSec = warningSec end

    local minuteSuffix = LocalizedTimeSuffix("MSUF_AURA_TIMER_MINUTE_SUFFIX", "M")
    local hourSuffix = LocalizedTimeSuffix("MSUF_AURA_TIMER_HOUR_SUFFIX", "H")
    local daySuffix = LocalizedTimeSuffix("MSUF_AURA_TIMER_DAY_SUFFIX", "D")
    local updateInterval = decimalSec > 0 and 0.1 or 0.25
    local sig = table_concat({
        "unit-suffix-binding", buckets and 1 or 0, decimalSec, minuteSuffix, hourSuffix, daySuffix,
        sr, sg, sb, wr, wg, wb, ur, ug, ub, urgentSec, warningSec, safeSec,
    }, "\030")
    _durationFormatterCache = _durationFormatterCache or {}
    local shared = _durationFormatterCache[sig]
    if shared then
        if type(lane) == "table" then lane._msufA3DurationStyle = shared end
        return shared
    end

    local roundingDown = NumericRuleFormatRounding("Down", 2)
    local thresholds, seen = {}, {}
    local function AddThreshold(value)
        value = ClampNumber(value, 0, 0, 600)
        if seen[value] then return end
        seen[value] = true
        thresholds[#thresholds + 1] = value
    end
    AddThreshold(0)
    if decimalSec > 0 then AddThreshold(decimalSec) end
    AddThreshold(60)
    if buckets then
        AddThreshold(urgentSec)
        AddThreshold(warningSec)
        AddThreshold(safeSec)
    end
    -- Unit promotion on Blizzard's own 1 + 1.5x max-interval curve
    -- (Blizzard_AuraContainerShared's DefaultAuraDurationFormatter): minutes
    -- run through "90M", hours through "36H", then days. Config thresholds cap
    -- at 600 s, so they can never collide with these.
    thresholds[#thresholds + 1] = 5401
    thresholds[#thresholds + 1] = 129601
    table_sort(thresholds)

    local function ColorPrefix(threshold)
        if not buckets then return "" end
        if safeSec > warningSec and threshold >= safeSec then return "" end
        if threshold >= warningSec then return ColorEscape(sr, sg, sb) end
        if threshold >= urgentSec then return ColorEscape(wr, wg, wb) end
        return ColorEscape(ur, ug, ub)
    end
    local function UnitBreakpoint(threshold, div, suffix, colorPrefix)
        local colorSuffix = colorPrefix ~= "" and "|r" or ""
        return {
            threshold = threshold,
            step = 1,
            rounding = roundingDown,
            min = 1,
            format = colorPrefix .. "%.0f" .. EscapeFormatLiteral(suffix) .. colorSuffix,
            components = {
                { div = div, step = 1, rounding = roundingDown },
            },
        }
    end
    local function BreakpointAt(threshold)
        -- Hour and day lanes sit far above every bucket boundary; they always
        -- render in the base font color.
        if threshold >= 129601 then return UnitBreakpoint(threshold, 86400, daySuffix, "") end
        if threshold >= 5401 then return UnitBreakpoint(threshold, 3600, hourSuffix, "") end
        local colorPrefix = ColorPrefix(threshold)
        if threshold >= 60 then return UnitBreakpoint(threshold, 60, minuteSuffix, colorPrefix) end
        local colorSuffix = colorPrefix ~= "" and "|r" or ""
        local decimalBreakpoint = threshold < decimalSec
        return {
            threshold = threshold,
            step = decimalBreakpoint and 0.1 or 1,
            rounding = roundingDown,
            -- Blizzard's native duration binding defaults missing minima to 1.
            -- Decimal aura timers must be allowed below one second.
            min = decimalBreakpoint and 0.1 or 1,
            format = colorPrefix .. (decimalBreakpoint and "%.1f" or "%.0f") .. colorSuffix,
        }
    end

    local formatter = createFormatter()
    for i = 1, #thresholds do
        formatter:AddBreakpoint(BreakpointAt(thresholds[i]))
    end

    local style = {
        formatter = formatter,
        binding = BuildAuraDurationBinding(formatter, updateInterval),
        updateInterval = updateInterval,
    }
    _durationFormatterCache[sig] = style
    if type(lane) == "table" then lane._msufA3DurationStyle = style end
    return style
end
local function PlaceStackText(fs, owner, lane)
    if not (fs and owner and lane) then return end
    fs:ClearAllPoints()
    local anchor = lane.stackAnchor or "TOPRIGHT"
    local x, y = lane.stackX or -1, lane.stackY or 1
    if anchor == "TOPLEFT" or anchor == "LEFT" then
        fs:SetPoint(anchor, owner, anchor, x, y)
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV(anchor == "LEFT" and "MIDDLE" or "TOP")
    elseif anchor == "BOTTOMLEFT" then
        fs:SetPoint(anchor, owner, anchor, x, y)
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("BOTTOM")
    elseif anchor == "BOTTOMRIGHT" then
        fs:SetPoint(anchor, owner, anchor, x, y)
        fs:SetJustifyH("RIGHT")
        fs:SetJustifyV("BOTTOM")
    elseif anchor == "CENTER" or anchor == "TOP" or anchor == "BOTTOM" then
        fs:SetPoint(anchor, owner, anchor, x, y)
        fs:SetJustifyH("CENTER")
        fs:SetJustifyV(anchor == "TOP" and "TOP" or (anchor == "BOTTOM" and "BOTTOM" or "MIDDLE"))
    elseif anchor == "RIGHT" then
        fs:SetPoint(anchor, owner, anchor, x, y)
        fs:SetJustifyH("RIGHT")
        fs:SetJustifyV("MIDDLE")
    else
        fs:SetPoint("TOPRIGHT", owner, "TOPRIGHT", x, y)
        fs:SetJustifyH("RIGHT")
        fs:SetJustifyV("TOP")
    end
end

local function PlaceCooldownText(fs, owner, lane)
    if not (fs and owner and lane) then return end
    fs:ClearAllPoints()
    local anchor = lane.cooldownAnchor or "CENTER"
    local x, y = lane.cooldownX or 0, lane.cooldownY or 0
    fs:SetPoint(anchor, owner, anchor, x, y)
    if anchor == "TOPLEFT" or anchor == "LEFT" or anchor == "BOTTOMLEFT" then
        fs:SetJustifyH("LEFT")
    elseif anchor == "TOPRIGHT" or anchor == "RIGHT" or anchor == "BOTTOMRIGHT" then
        fs:SetJustifyH("RIGHT")
    else
        fs:SetJustifyH("CENTER")
    end
    if anchor == "TOPLEFT" or anchor == "TOP" or anchor == "TOPRIGHT" then
        fs:SetJustifyV("TOP")
    elseif anchor == "BOTTOMLEFT" or anchor == "BOTTOM" or anchor == "BOTTOMRIGHT" then
        fs:SetJustifyV("BOTTOM")
    else
        fs:SetJustifyV("MIDDLE")
    end
end

--- Bind a plain MSUF-owned FontString to the same native duration style used
--- by CustomAuraButtons. Buff Reminder weapon-enchant placeholders are not
--- AuraButtons, but C_PaperDollInfo exposes their remaining time as ordinary
--- data, so they can still use a C-side DurationTextBinding without polling.
---
--- The owner retains one binding for its lifetime. Visual setup runs only when
--- the compiled slot signature changes; enchant events update only the native
--- Duration reference and enablement.
local function ConfigureStandaloneAuraDurationText(owner, fs, lane, duration, enabled)
    if not owner then return false end
    local binding = owner._msufA3StandaloneDurationBinding
    if enabled ~= true or not (fs and lane and duration) then
        if binding and type(binding.SetEnabled) == "function" then binding:SetEnabled(false) end
        if fs then
            fs:SetText("")
            fs:Hide()
        end
        return false
    end

    local style = BuildAuraDurationStyle(lane)
    local template = style and style.binding
    local durationUtil = _G.C_DurationUtil
    local createBinding = durationUtil and durationUtil.CreateDurationTextBinding
    if not (template and type(createBinding) == "function") then return false end

    if not binding then
        binding = createBinding()
        if not (binding
            and type(binding.Assign) == "function"
            and type(binding.SetFontString) == "function"
            and type(binding.SetDuration) == "function"
            and type(binding.SetEnabled) == "function")
        then
            return false
        end
        owner._msufA3StandaloneDurationBinding = binding
    end

    local signature = lane._msufA3LayoutSignature or lane._msufA3StructuralSignature or lane
    if owner._msufA3StandaloneDurationSignature ~= signature
        or owner._msufA3StandaloneDurationFontString ~= fs
        or owner._msufA3StandaloneDurationStyle ~= style then
        binding:Assign(template)
        binding:SetFontString(fs)
        ApplyFont(fs, lane.cooldownSize)
        if type(fs.SetDrawLayer) == "function" then
            fs:SetDrawLayer("OVERLAY", FrameLayers.AURA_COOLDOWN_TEXT_DRAW_SUBLEVEL or 7)
        end
        PlaceCooldownText(fs, owner, lane)
        owner._msufA3StandaloneDurationSignature = signature
        owner._msufA3StandaloneDurationFontString = fs
        owner._msufA3StandaloneDurationStyle = style
    end

    binding:SetDuration(duration)
    binding:SetEnabled(true)
    fs:Show()
    return true
end
if type(MSUF.RegisterLocaleCallback) == "function" then
    MSUF.RegisterLocaleCallback("MSUF_Auras3_DurationFormatter", function()
        _durationFormatterCache = nil
        if type(A3.RequestApply) == "function" then A3.RequestApply() end
    end)
end

return {
    ApplyFont = ApplyFont,
    BuildAuraDurationStyle = BuildAuraDurationStyle,
    ConfigureStandaloneAuraDurationText = ConfigureStandaloneAuraDurationText,
    PlaceCooldownText = PlaceCooldownText,
    PlaceStackText = PlaceStackText,
}
end
