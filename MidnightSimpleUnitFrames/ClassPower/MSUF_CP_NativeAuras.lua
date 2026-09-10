-- Native class-resource displays. Blizzard owns aura values and countdowns;
-- this module only configures their display on structural/settings changes.
-- Contract: upstream/live Blizzard_CustomAuraButton.lua (12.1): bound regions
-- must belong to the slot button. Never inspect their values or visibility.
local _, MSUF = ...
MSUF.CPBuilders = MSUF.CPBuilders or {}

function MSUF.CPBuilders.NativeAuras(E)
    local CP, db = E.CP, E.db
    local states, pending = {}, false
    local spells = { WHIRLWIND = 85739, SWEEPING_STRIKES = 260708 }
    local formatters = {}

    local function Mutable(state)
        if InCombatLockdown and InCombatLockdown() then return false end
        if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then return false end
        return not state or not state.button or not state.button.CanBeAccessedInContext
            or state.button:CanBeAccessedInContext() == true
    end

    local function Formatter(format, step)
        local f = formatters[format]
        if not f then
            f = C_StringUtil.CreateNumericRuleFormatter()
            f:SetBreakpoints({ { threshold = 0, step = step,
                rounding = Enum.NumericRuleFormatRounding.Nearest, format = format } })
            formatters[format] = f
        end
        return f
    end

    local function Park(state)
        if not state or not state.active then return end
        -- The unrestricted proxy is ours; never hide the sealed slot subtree.
        state.proxy:Hide()
        state.sensor:SetEnabled(false)
        state.active = false
    end

    local function Style(state, maximum)
        if not state.bar then pending = true; return false end
        local b, v = db.bars or {}, CP.visual or {}
        local texture = E.Texture(b.classPowerTexture)
        local font = (_G.MSUF_GetFontPath and _G.MSUF_GetFontPath()) or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
        local flags = _G.MSUF_GetFontFlags and _G.MSUF_GetFontFlags() or "OUTLINE"
        local size = tonumber(b.classPowerFontSize) or 14
        local r, g, blue = v.baseR or 1, v.baseG or 1, v.baseB or 1
        local textMode = db.textMode
        local format = textMode == "MAX" and tostring(maximum)
            or textMode == "CURMAX" and ("%d / " .. maximum) or "%d"
        local showText = b.classPowerShowText == true
        local textLevel = E.TextLevel()
        -- A settings-only signature. No aura data enters this cache.
        local signature = table.concat({ texture, font, flags, size, r, g, blue,
            v.filledAlpha or 1, maximum, format, tostring(showText),
            tostring(b.classPowerFillReverse == true), b.classPowerTextOffsetX or 0,
            b.classPowerTextOffsetY or 0, textLevel }, ":")
        if state.signature == signature then return true end
        if not Mutable(state) then pending = true; return false end
        local bar, text = state.bar, state.text
        bar:SetStatusBarTexture(texture)
        bar:SetStatusBarColor(r, g, blue, v.filledAlpha or 1)
        bar:SetReverseFill(b.classPowerFillReverse == true)
        text:SetFont(font, size, flags)
        text:SetTextColor(1, 1, 1, 1)
        text:ClearAllPoints()
        text:SetPoint("CENTER", state.button, "CENTER", b.classPowerTextOffsetX or 0,
            b.classPowerTextOffsetY or 0)
        state.textOwner:SetFrameLevel(textLevel)
        state.button:SetApplicationBar(bar, { maxApplications = maximum,
            interpolation = Enum.StatusBarInterpolation.Immediate })
        if showText then
            state.button:SetApplicationCount(text, { formatter = Formatter(format, 1) })
        else
            state.button:ClearApplicationCount()
            text:SetText("")
        end
        state.signature = signature
        return true
    end

    local function Ensure(key, maximum)
        local state = states[key]
        if state and state.sensor then Style(state, maximum); return state end
        if not Mutable() then pending = true; return nil end
        local A3 = _G.MSUF_Auras3
        if not (A3 and A3.CreateClassPowerAuraSensor) then pending = true; return nil end
        if not state then
            state = { proxy = CreateFrame("Frame", nil, CP.container), ticks = {} }
            state.chrome = CreateFrame("Frame", nil, state.proxy)
            state.chrome:SetAllPoints(state.proxy)
            state.proxy:SetAllPoints(CP.container)
            state.proxy:Hide()
            states[key] = state
        end
        state.sensor = A3.CreateClassPowerAuraSensor(state.proxy, "msuf_cp_" .. key,
            { [spells[key]] = true }, function(button)
                state.button = button
                state.chrome:SetFrameLevel(button:GetFrameLevel() + 3)
                button:ClearAllPoints()
                button:SetAllPoints(state.proxy)
                if button.EnableMouse then button:EnableMouse(false) end
                state.bar = CreateFrame("StatusBar", nil, button)
                state.bar:SetAllPoints(button)
                state.textOwner = CreateFrame("Frame", nil, button)
                state.textOwner:SetAllPoints(button)
                state.text = state.textOwner:CreateFontString(nil, "OVERLAY")
                Style(state, maximum)
            end)
        if not state.sensor then state.proxy:Hide(); pending = true; return nil end
        return state
    end

    local function Activate(state)
        if not state or state.active then return end
        state.sensor:SetEnabled(true)
        state.proxy:Show()
        state.active = true
    end

    local function Sync()
        pending = false
        local b = db.bars or {}
        local key = CP.visible and spells[CP.powerType] and CP.powerType or nil
        for name, state in pairs(states) do
            if name ~= key then Park(state) end
        end
        if key then
            local maximum = key == "WHIRLWIND" and 4 or 18
            if key == "SWEEPING_STRIKES" and C_Spell.GetSpellMaxCumulativeAuraApplications then
                local n = C_Spell.GetSpellMaxCumulativeAuraApplications(spells[key])
                if not (issecretvalue and issecretvalue(n)) and type(n) == "number" and n > 0 then
                    maximum = math.min(64, math.floor(n))
                end
            end
            local state = Ensure(key, maximum)
            if state then
                -- One native fill with static separators: no per-pip aura slots.
                local width = CP.container:GetWidth()
                local gap = math.max(tonumber(b.classPowerGap) or 0, tonumber(b.classPowerTickWidth) or 1)
                for i = 1, maximum - 1 do
                    local tick = state.ticks[i]
                    if not tick then
                        tick = state.chrome:CreateTexture(nil, "OVERLAY", nil, 7)
                        tick:SetColorTexture(0, 0, 0, 1)
                        state.ticks[i] = tick
                    end
                    tick:ClearAllPoints()
                    tick:SetPoint("TOP", state.proxy, "TOPLEFT", width * i / maximum, 0)
                    tick:SetPoint("BOTTOM", state.proxy, "BOTTOMLEFT", width * i / maximum, 0)
                    tick:SetWidth(math.max(gap, 0.01))
                    tick:SetShown(gap > 0)
                end
                for i = maximum, #state.ticks do state.ticks[i]:Hide() end
                Activate(state)
            end
            -- Keep the normal background/outline, but retire its value and text.
            for i = 1, CP.maxBars do
                local bar = CP.bars[i]
                if bar then
                    bar:SetValue(0)
                    -- The legacy renderer must not retain a pre-native value
                    -- cache when a vehicle/spec switch gives it this bar back.
                    bar._msufCPValue = nil
                end
            end
            if CP.text then CP.text:Hide() end
        end
        CP.nativeAuraPending = pending
    end

    return { Sync = Sync, Disable = function()
        for _, state in pairs(states) do Park(state) end
        CP.nativeAuraPending = nil
    end }
end
