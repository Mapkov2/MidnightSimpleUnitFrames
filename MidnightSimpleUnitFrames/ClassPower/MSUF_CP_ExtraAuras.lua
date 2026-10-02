-- Optional native duration resources. Bound children belong to the aura slot;
-- no aura values, visibility or remaining time are read by addon Lua.
-- Ignore Pain (Protection Warrior) and the Arcane Surge window (Arcane Mage:
-- one slot each for Arcane Surge and Arcane Soul at the same place, the Arcane
-- Soul slot above, so the bar takes the Arcane Soul colour in that phase) run
-- where the client has the aura container and the spell.
local _, MSUF = ...
local PixelLayoutRegion = _G.MSUF_PixelLayoutRegion or function(region, policy, ...) if type(policy) == "string" then return region[policy](region, ...) end return region end
MSUF.CPBuilders = MSUF.CPBuilders or {}

local IGNORE_PAIN, ARCANE_SURGE, ARCANE_SOUL = 190456, 365362, 451038
local ARCANE_COLOR, ARCANE_WARN_COLOR, PAIN_COLOR = { .66, .42, 1 }, { 1, .78, .25 }, { .45, .7, 1 }
local SOUL_COLOR = { .92, .4, .86 }
local ARCANE_TEXT = { seconds = true, gcds = true, both = true }

function MSUF.CPBuilders.ExtraAuras(E)
    local states, pending, publicHaste, arcaneGCD = {}, false, 0, nil
    local Refresh, previewHost, previewShown, registered, editActive, disabled
    local previewBars, known = {}, {}
    -- The client's own spell data decides, read once per spell.
    local function Known(spellID)
        local answer = known[spellID]
        if answer == nil then
            local spellAPI = _G.C_Spell
            answer = type(spellAPI) == "table" and type(spellAPI.DoesSpellExist) == "function"
                and spellAPI.DoesSpellExist(spellID) == true
            known[spellID] = answer
        end
        return answer
    end
    local function SensorAPI()
        local A3 = _G.MSUF_Auras3
        return A3 and A3.CreateClassPowerAuraSensor and A3 or nil
    end
    local function PainSupported() return E.PLAYER_CLASS == "WARRIOR" and SensorAPI() ~= nil and Known(IGNORE_PAIN) end
    local function ArcaneSupported() return E.PLAYER_CLASS == "MAGE" and SensorAPI() ~= nil and Known(ARCANE_SURGE) end
    local function Mutable(state)
        return not (InCombatLockdown and InCombatLockdown())
            and not (C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret())
            and (not state or not state.button or not state.button.CanBeAccessedInContext or state.button:CanBeAccessedInContext())
    end
    local function RGB(key, fallback)
        local color = E.db.bars[key]
        if type(color) ~= "table" then color = fallback end
        return tonumber(color[1]) or fallback[1], tonumber(color[2]) or fallback[2], tonumber(color[3]) or fallback[3]
    end
    local function WarnSeconds()
        local seconds = tonumber(E.db.bars.arcaneWindowWarnSeconds)
        if not seconds or seconds ~= seconds then seconds = 3 end
        return math.max(0, math.min(10, seconds))
    end
    local function ArcaneText()
        local mode = E.db.bars.arcaneWindowText
        return ARCANE_TEXT[mode] and mode or "seconds"
    end
    local function TextFrom()
        local seconds = tonumber(E.db.bars.arcaneWindowTextFrom)
        if not seconds or seconds ~= seconds then return 0 end
        return math.max(0, math.min(15, math.floor(seconds + 0.5)))
    end
    -- The Arcane window counts global cooldowns only for these choices.
    local function UsesGCD()
        local b = E.db.bars
        return ArcaneText() ~= "seconds" or b.arcaneWindowWarnLastGCD == true
    end
    -- Blizzard's global cooldown for spells: 1.5 seconds shortened by spell
    -- haste, never below 0.75 seconds. Restricted haste keeps the last public
    -- value; 0.01 s steps keep haste procs from rebuilding identical rules.
    local function GlobalCooldown()
        local haste = _G.UnitSpellHaste and _G.UnitSpellHaste("player")
        if E.NotSecret(haste) and type(haste) == "number" and haste == haste and haste > -100 then publicHaste = haste end
        return math.floor(math.max(0.75, 1.5 / (1 + publicHaste / 100)) * 100 + 0.5) / 100
    end
    local function Font()
        local b = E.db.bars
        return (_G.MSUF_GetFontPath and _G.MSUF_GetFontPath()) or STANDARD_TEXT_FONT,
            tonumber(b.classPowerFontSize) or 14, (_G.MSUF_GetFontFlags and _G.MSUF_GetFontFlags()) or "OUTLINE"
    end
    -- Arcane window text rules: seconds (one decimal below ten seconds), the
    -- global cooldowns that can still start ("x3": the count rounds up, a
    -- started one counts), or both; from the chosen seconds up the text is blank.
    local function ArcaneRules(gcd)
        local rounding, mode, from = Enum.NumericRuleFormatRounding, ArcaneText(), TextFrom()
        local count = { div = gcd, step = 1, rounding = rounding.Up }
        local rules
        if mode == "gcds" then
            rules = { { threshold = 0, format = "x%d", components = { count } } }
        elseif mode == "both" then
            rules = {
                { threshold = 0, format = "%.1f (x%d)", components = { { step = .1, rounding = rounding.Nearest }, count } },
                { threshold = 10, format = "%d (x%d)", components = { { step = 1, rounding = rounding.Down }, count } },
            }
        else
            rules = {
                { threshold = 0, step = .1, rounding = rounding.Nearest, format = "%.1f" },
                { threshold = 10, step = 1, rounding = rounding.Down, format = "%d" },
            }
        end
        if from > 0 then
            for i = #rules, 1, -1 do if rules[i].threshold >= from then table.remove(rules, i) end end
            rules[#rules + 1] = { threshold = from, format = " " }
        end
        return rules
    end
    -- Ignore Pain counts seconds with one decimal.
    local function Formatter(key, formatter, gcd)
        formatter = formatter or C_StringUtil.CreateNumericRuleFormatter()
        local rounding = Enum.NumericRuleFormatRounding
        if key == "PAIN" then
            formatter:SetBreakpoints({ { threshold = 0, format = "%.1f s", components = { { step = .1, rounding = rounding.Nearest } } } })
        else
            formatter:SetBreakpoints(ArcaneRules(gcd))
        end
        return formatter
    end
    -- Arcane window text: the warning colour below the configured seconds, or
    -- during the last global cooldown.
    local function WarnCurve(state, curve, gcd)
        local wr, wg, wb = RGB("arcaneWindowWarnColor", ARCANE_WARN_COLOR)
        local warn = E.db.bars.arcaneWindowWarnLastGCD == true and gcd or WarnSeconds()
        curve = curve or C_CurveUtil.CreateColorCurve()
        curve:ClearPoints()
        curve:SetType(Enum.LuaCurveType.Step)
        state.warnColor = state.warnColor or CreateColor(wr, wg, wb, 1)
        state.warnColor:SetRGBA(wr, wg, wb, 1)
        state.plainColor = state.plainColor or CreateColor(1, 1, 1, 1)
        -- 0 seconds turns the warning off: one plain point, never two at 0.
        if warn > 0 then curve:AddPoint(0, state.warnColor) end
        curve:AddPoint(warn, state.plainColor)
        return curve
    end
    local function BarColor(key)
        if key == "PAIN" then return RGB("ignorePainColor", PAIN_COLOR) end
        if key == "SOUL" then return RGB("arcaneWindowSoulColor", SOUL_COLOR) end
        return RGB("arcaneWindowColor", ARCANE_COLOR)
    end
    local function Initialize(state, button)
        local b = E.db.bars
        local texture = E.Texture(b.classPowerTexture)
        local font, size, flags = Font()
        local pain = state.key == "PAIN"
        local r, g, blue = BarColor(state.key)
        local wr, wg, wb = RGB("arcaneWindowWarnColor", ARCANE_WARN_COLOR)
        local gcd = not pain and UsesGCD() and GlobalCooldown() or 1.5
        if not pain then arcaneGCD = gcd end
        -- A settings-only signature; no aura data enters it.
        local signature = table.concat({ texture, font, size, flags, r, g, blue, wr, wg, wb, WarnSeconds(),
            tostring(b.ignorePainTimeMarker ~= false), ArcaneText(), TextFrom(),
            tostring(b.arcaneWindowWarnLastGCD == true), gcd }, ":")
        if state.button == button and state.signature == signature then return end
        button:ClearAllPoints(); button:SetAllPoints(state.host)
        local bar = state.bar or PixelLayoutRegion(CreateFrame("StatusBar", nil, button))
        bar:SetAllPoints(button); bar:SetStatusBarTexture(texture)
        bar:SetStatusBarColor(r, g, blue, 1)
        button:SetDurationBar(bar, { direction = Enum.StatusBarTimerDirection.RemainingTime,
            interpolation = Enum.StatusBarInterpolation.Immediate })
        local text = state.text or PixelLayoutRegion(button:CreateFontString(nil, "OVERLAY"))
        text:SetFont(font, size, flags)
        text:SetPoint("CENTER", button, "CENTER")
        state.formatter = Formatter(state.key, state.formatter, gcd)
        local options = { textFormatter = state.formatter }
        if not pain then
            state.curve = WarnCurve(state, state.curve, gcd)
            options.textColor = { curve = state.curve, property = Enum.DurationTextBindingProperty.RemainingDuration }
        end
        button:SetDurationText(text, options)
        if pain then
            local marker = state.marker or PixelLayoutRegion(button:CreateTexture(nil, "OVERLAY", nil, 7), true); state.marker = marker
            marker:SetColorTexture(1, 1, 1, 1); marker:SetWidth(2)
            marker:SetPoint("TOP", bar:GetStatusBarTexture(), "TOPRIGHT")
            marker:SetPoint("BOTTOM", bar:GetStatusBarTexture(), "BOTTOMRIGHT")
            marker:SetShown(b.ignorePainTimeMarker ~= false)
        end
        state.button, state.bar, state.text, state.signature = button, bar, text, signature
    end
    local function Park(state)
        if state.sensor and state.active then state.sensor:SetEnabled(false) end
        state.active = false; state.host:Hide()
    end
    local function Ensure(key, row)
        local b = E.db.bars
        local state = states[key]
        if not state then
            state = { key = key, host = PixelLayoutRegion(CreateFrame("Frame", nil, E.GetPlayerFrame())) }; states[key] = state
            -- The Arcane Soul slot covers the Arcane Surge slot at the same place.
            if key == "SOUL" and states.ARCANE and states.ARCANE.host.GetFrameLevel then
                state.host:SetFrameLevel(states.ARCANE.host:GetFrameLevel() + 2)
            end
        end
        local x, y = tonumber(b.resourceExtraOffsetX) or 0, tonumber(b.resourceExtraOffsetY) or -18
        local width, height = tonumber(b.resourceExtraWidth) or 220, tonumber(b.resourceExtraHeight) or 8
        local placement = table.concat({ x, y, width, height, row }, ":")
        if state.placement ~= placement then
            state.host:ClearAllPoints()
            state.host:SetPoint("TOP", E.GetPlayerFrame(), "BOTTOM", x, y - row * (height + 6))
            state.host:SetSize(width, height)
            state.placement = placement
        end
        if not Mutable(state) then pending = true; return end
        if state.button then Initialize(state, state.button) end
        local A3 = SensorAPI()
        if not state.sensor and A3 then
            local spells = key == "PAIN" and { [tonumber(b.ignorePainAuraID) or IGNORE_PAIN] = true }
                or key == "SOUL" and { [ARCANE_SOUL] = true } or { [ARCANE_SURGE] = true }
            state.sensor = A3.CreateClassPowerAuraSensor(state.host, "msuf_cp_extra_" .. key, spells, function(button) Initialize(state, button) end)
        end
        if state.sensor then
            if not state.active then state.sensor:SetEnabled(true); state.active = true end
            state.host:Show()
        else pending = true end
    end
    local function Eligible()
        local b, spec = E.db.bars or {}, E.GetSpec and E.GetSpec()
        return b.showIgnorePain == true and spec == 3 and PainSupported(),
            b.showArcaneWindow == true and spec == 1 and ArcaneSupported()
    end
    local function HidePreview()
        if previewHost then previewHost:Hide() end
        previewShown = false
    end
    -- Edit Mode sample: one bar, labelled with the client's own spell name.
    local function Preview(pain, arcane)
        if disabled or not (editActive or _G.MSUF_UnitEditModeActive == true)
            or not (pain or arcane) or (InCombatLockdown and InCombatLockdown()) then HidePreview(); return end
        local b, owner = E.db.bars, E.GetPlayerFrame()
        if not owner then HidePreview(); return end
        if not previewHost then
            previewHost = PixelLayoutRegion(CreateFrame("Frame", nil, owner))
            previewHost:EnableMouse(false)
        end
        if owner.GetFrameLevel then previewHost:SetFrameLevel(owner:GetFrameLevel() + 30) end
        local width, height = tonumber(b.resourceExtraWidth) or 220, tonumber(b.resourceExtraHeight) or 8
        previewHost:ClearAllPoints()
        previewHost:SetPoint("TOP", owner, "BOTTOM", tonumber(b.resourceExtraOffsetX) or 0, tonumber(b.resourceExtraOffsetY) or -18)
        previewHost:SetSize(width, height)
        local bar = previewBars[1]
        if not bar then
            bar = PixelLayoutRegion(CreateFrame("StatusBar", nil, previewHost))
            bar.text = PixelLayoutRegion(bar:CreateFontString(nil, "OVERLAY"))
            bar.text:SetPoint("CENTER", bar, "CENTER")
            previewBars[1] = bar
        end
        bar:ClearAllPoints(); bar:SetPoint("TOPLEFT", previewHost, "TOPLEFT", 0, 0)
        bar:SetSize(width, height); bar:SetStatusBarTexture(E.Texture(b.classPowerTexture))
        bar:SetStatusBarColor(RGB(pain and "ignorePainColor" or "arcaneWindowColor", pain and PAIN_COLOR or ARCANE_COLOR))
        bar:SetMinMaxValues(0, 1); bar:SetValue(pain and .65 or .6)
        bar.text:SetFont(Font())
        local spellAPI = _G.C_Spell
        local name = spellAPI and spellAPI.GetSpellName and spellAPI.GetSpellName(pain and IGNORE_PAIN or ARCANE_SURGE)
        if type(name) ~= "string" then
            local translate = MSUF.Translate or function(text) return text end
            name = translate(pain and "Ignore Pain" or "Arcane Surge")
        end
        bar.text:SetText(name)
        bar:Show()
        previewHost:Show(); previewShown = true
    end
    local function Capture()
        local b = E.db.bars
        return { x = b.resourceExtraOffsetX, y = b.resourceExtraOffsetY,
            width = b.resourceExtraWidth, height = b.resourceExtraHeight }
    end
    local function Restore(state)
        if InCombatLockdown and InCombatLockdown() then return false end
        local b = E.db.bars
        b.resourceExtraOffsetX, b.resourceExtraOffsetY = state.x, state.y
        b.resourceExtraWidth, b.resourceExtraHeight = state.width, state.height
        if not disabled then Refresh() end
        return true
    end
    local function RegisterMover()
        local api = MSUF.EditModeAPI
        if registered or not api or not api.RegisterElement or not (PainSupported() or ArcaneSupported()) then return end
        local translate = MSUF.Translate or function(text) return text end
        registered = true -- A registration may synchronously join an active session.
        registered = api.RegisterElement("MSUF", {
            id = "resource-extras", label = translate("Additional resources"), order = 103,
            getFrame = function()
                local pain, arcane = Eligible()
                if disabled or not (pain or arcane) then return nil end
                if not previewShown then Preview(pain, arcane) end
                return previewShown and previewHost or nil
            end,
            isEnabled = function() local pain, arcane = Eligible(); return not disabled and (pain or arcane) end,
            captureState = Capture, restoreState = Restore,
            movePosition = function(request)
                local state = request.state
                return Restore({ x = (tonumber(state.x) or 0) + request.deltaX,
                    y = (tonumber(state.y) or -18) + request.deltaY, width = state.width, height = state.height })
            end,
            onSessionChanged = function(active) editActive = active; if disabled then HidePreview() else Refresh() end end,
            extraControls = {
                { id = "width", label = translate("Resource bar width"), kind = "number", min = 40, max = 1000, step = 1,
                    get = function() return tonumber(E.db.bars.resourceExtraWidth) or 220 end,
                    set = function(value) local state = Capture(); state.width = value; return Restore(state) end },
                { id = "height", label = translate("Resource bar height"), kind = "number", min = 2, max = 30, step = 1,
                    get = function() return tonumber(E.db.bars.resourceExtraHeight) or 8 end,
                    set = function(value) local state = Capture(); state.height = value; return Restore(state) end },
            },
        }) == true
    end
    Refresh = function()
        disabled = false
        RegisterMover()
        local pain, arcane = Eligible()
        Preview(pain, arcane)
        if not Mutable() then pending = true; return end
        pending = false
        for key, state in pairs(states) do
            if (key == "PAIN" and not pain) or (key ~= "PAIN" and not arcane) then Park(state) end
        end
        if pain then Ensure("PAIN", 0) end
        if arcane then Ensure("ARCANE", 0); Ensure("SOUL", 0) end
    end
    -- Haste changes the global cooldown: only the addon-owned formatter rules
    -- and colour curve of the Arcane slots change, also in combat; the bound
    -- aura buttons stay untouched.
    local function ArcaneActive()
        return (states.ARCANE and states.ARCANE.active) or (states.SOUL and states.SOUL.active) or false
    end
    local function RefreshHaste()
        if disabled or not ArcaneActive() or not UsesGCD() then return end
        local gcd = GlobalCooldown()
        if gcd == arcaneGCD then return end
        arcaneGCD = gcd
        for key, state in pairs(states) do
            if key ~= "PAIN" and state.active and state.formatter and state.curve then
                Formatter(key, state.formatter, gcd)
                WarnCurve(state, state.curve, gcd)
            end
        end
    end
    return { Refresh = Refresh, RefreshHaste = RefreshHaste,
        UsesHaste = function() return not disabled and ArcaneActive() and UsesGCD() end,
        IsPending = function() return pending end, Disable = function()
        disabled = true; HidePreview()
        if not Mutable() then pending = true; return end
        pending = false
        for _, state in pairs(states) do Park(state) end
    end }
end
