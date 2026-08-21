--- ClassPower/MSUF_CP_EbonMight.lua
--- Native 12.1 Ebon Might duration bar and text.
---
--- Ebon Might can be restricted in combat, so addon Lua cannot reliably
--- discover it through GetPlayerAuraBySpellID. Blizzard's CustomAuraContainer
--- owns aura discovery and writes the remaining duration directly to a
--- descendant StatusBar and FontString. There is deliberately no direct-aura
--- or Lua timer fallback.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local builders = _G.MSUF_CP_CORE_BUILDERS
if type(builders) ~= "table" then
    builders = {}
    ExportPublic("MSUF_CP_CORE_BUILDERS", builders)
end

builders.EBON_MIGHT = function(E)
    local CP = E.CP
    local EBON = E.EBON or {}
    local _cpDB = E._cpDB
    local CreateFrame = E.CreateFrame or CreateFrame
    local GetHost = E.GetHost
    local GetStyle = E.GetStyle
    local GetTextLevel = E.GetTextLevel
    local durationTextOptions
    local durationBarOptions

    local function ResolveHost()
        if type(GetHost) == "function" then
            local host = GetHost()
            if host then return host end
        end
        return CP.ebonHost
    end

    --- Capture a plain, immutable-by-convention style snapshot before the
    --- native slot is created. Every write to the restricted slot subtree then
    --- happens inside initializeFrame; later activation only toggles owners.
    local function CaptureStyle()
        local supplied = type(GetStyle) == "function" and GetStyle() or nil
        if type(supplied) ~= "table" then supplied = nil end

        local style = {
            texture = supplied and supplied.texture,
            barR = supplied and supplied.barR,
            barG = supplied and supplied.barG,
            barB = supplied and supplied.barB,
            barA = supplied and supplied.barA,
            fontPath = supplied and supplied.fontPath,
            fontSize = supplied and supplied.fontSize,
            fontFlags = supplied and supplied.fontFlags,
            textR = supplied and supplied.textR,
            textG = supplied and supplied.textG,
            textB = supplied and supplied.textB,
            textA = supplied and supplied.textA,
            shadowR = supplied and supplied.shadowR,
            shadowG = supplied and supplied.shadowG,
            shadowB = supplied and supplied.shadowB,
            shadowA = supplied and supplied.shadowA,
            shadowX = supplied and supplied.shadowX,
            shadowY = supplied and supplied.shadowY,
            textLevel = supplied and supplied.textLevel,
            textOffsetX = supplied and supplied.textOffsetX,
            textOffsetY = supplied and supplied.textOffsetY,
        }

        style.texture = style.texture or "Interface\\Buttons\\WHITE8x8"
        style.barR = tonumber(style.barR) or 1
        style.barG = tonumber(style.barG) or 1
        style.barB = tonumber(style.barB) or 1
        style.barA = tonumber(style.barA) or 1
        style.textR = tonumber(style.textR) or 1
        style.textG = tonumber(style.textG) or 1
        style.textB = tonumber(style.textB) or 1
        style.textA = tonumber(style.textA) or 1
        style.shadowR = tonumber(style.shadowR) or 0
        style.shadowG = tonumber(style.shadowG) or 0
        style.shadowB = tonumber(style.shadowB) or 0
        style.shadowA = tonumber(style.shadowA) or 1
        style.shadowX = tonumber(style.shadowX) or 1
        style.shadowY = tonumber(style.shadowY) or -1
        style.textLevel = tonumber(style.textLevel)
            or (type(GetTextLevel) == "function" and tonumber(GetTextLevel()))
            or 1
        style.textOffsetX = tonumber(style.textOffsetX) or 0
        style.textOffsetY = tonumber(style.textOffsetY) or 0
        return style
    end

    local function GetDurationTextOptions()
        if durationTextOptions ~= nil then return durationTextOptions or nil end

        local stringUtil = _G.C_StringUtil
        local createFormatter = stringUtil and stringUtil.CreateNumericRuleFormatter
        local rounding = _G.Enum and _G.Enum.NumericRuleFormatRounding
        if type(createFormatter) ~= "function" or not (rounding and rounding.Nearest ~= nil) then
            durationTextOptions = false
            return nil
        end

        local formatter = createFormatter()
        if not (formatter and type(formatter.SetBreakpoints) == "function") then
            durationTextOptions = false
            return nil
        end
        formatter:SetBreakpoints({
            { threshold = 0, step = 0.1, rounding = rounding.Nearest, format = "%.1f" },
        })
        durationTextOptions = { textFormatter = formatter }
        return durationTextOptions
    end

    local function GetDurationBarOptions()
        if durationBarOptions then return durationBarOptions end
        durationBarOptions = {}
        local enum = _G.Enum
        local interpolation = enum and enum.StatusBarInterpolation
        local direction = enum and enum.StatusBarTimerDirection
        if interpolation and interpolation.Immediate ~= nil then
            durationBarOptions.interpolation = interpolation.Immediate
        end
        if direction and direction.RemainingTime ~= nil then
            durationBarOptions.direction = direction.RemainingTime
        end
        return durationBarOptions
    end

    --- The registered FontString stays construction-only. Its addon-owned
    --- parent may change level later, but SetFrameLevel is protected and the
    --- AuraContainer can deny tainted access while its aura is secret. Keep a
    --- plain cached level so the restricted subtree is never probed by a getter.
    local function ApplyTextStyle()
        local owner = CP.ebonTextFrame
        if not owner then return CP.ebonSensor ~= nil end

        local textLevel = type(GetTextLevel) == "function" and tonumber(GetTextLevel()) or nil
        if not textLevel then return false end
        textLevel = math.floor(textLevel + 0.5)
        if CP.ebonTextFrameLevel == textLevel then
            CP.ebonTextLayerRetryPending = nil
            return true
        end

        local inCombat = _G.InCombatLockdown
        if type(inCombat) == "function" and inCombat() == true then
            CP.ebonTextLayerRetryPending = true
            return false
        end
        local canAccess = owner.CanBeAccessedInContext
        if type(canAccess) ~= "function" or canAccess(owner) ~= true then
            CP.ebonTextLayerRetryPending = true
            return false
        end

        owner:SetFrameLevel(textLevel)
        CP.ebonTextFrameLevel = textLevel
        CP.ebonTextLayerRetryPending = nil
        return true
    end

    --- The registered bar and FontString are plain addon-owned regions inside
    --- the restricted slot subtree, so re-styling them later is legal and does
    --- not touch the aura data itself. Without this every media, colour, font
    --- and offset change would stay invisible until the next /reload, because
    --- the slot is created exactly once per session.
    local function RefreshStyle()
        local bar, text = CP.ebonNativeBar, CP.ebonNativeText
        if not (bar or text) then return false end
        local style = CaptureStyle()
        if bar then
            bar:SetStatusBarTexture(style.texture)
            bar:SetStatusBarColor(style.barR, style.barG, style.barB, style.barA)
        end
        if text then
            if style.fontPath and style.fontSize then
                text:SetFont(style.fontPath, style.fontSize, style.fontFlags or "")
            end
            text:SetTextColor(style.textR, style.textG, style.textB, style.textA)
            text:SetShadowColor(style.shadowR, style.shadowG, style.shadowB, style.shadowA)
            text:SetShadowOffset(style.shadowX, style.shadowY)
            local owner = CP.ebonTextFrame
            if owner then
                text:ClearAllPoints()
                text:SetPoint("CENTER", owner, "CENTER", style.textOffsetX, style.textOffsetY)
            end
        end
        return true
    end

    local function SetActive(active)
        active = active == true
        if not active and CP.ebonSensorDesired ~= true then
            CP.ebonSensorRetryPending = nil
            CP.ebonTextLayerRetryPending = nil
        end
        --- The host is the Player Power bar, which the Power element may only
        --- have created on a later apply. Re-resolve every activation instead of
        --- trusting the first answer.
        local host = active and ResolveHost() or (CP.ebonSensorHost or CP.ebonHost)
        if not host then
            if active then
                CP.ebonSensorRetryPending = true
            end
            return false
        end

        if active and not CP.ebonSensor then
            local A3 = _G.MSUF_Auras3
            local createSensor = A3 and A3.CreateClassPowerAuraSensor
            if type(createSensor) == "function" and EBON.SPELL_ID then
                local style = CaptureStyle()
                CP.ebonSensor = createSensor(host, "msuf_cp_ebon_might", { [EBON.SPELL_ID] = true }, function(button)
                    CP.ebonButton = button
                    button:ClearAllPoints()
                    button:SetAllPoints(button:GetParent())
                    if button.SetMouseClickEnabled then button:SetMouseClickEnabled(false) end
                    if button.SetMouseMotionEnabled then button:SetMouseMotionEnabled(false) end
                    if button.EnableMouse then button:EnableMouse(false) end
                    if button.SetFrameLevel and host.GetFrameLevel then
                        button:SetFrameLevel((host:GetFrameLevel() or 0) + 1)
                    end

                    local bar = CreateFrame("StatusBar", nil, button)
                    bar:SetAllPoints(button)
                    bar:SetStatusBarTexture(style.texture)
                    bar:SetMinMaxValues(0, 1)
                    bar:SetValue(0)
                    bar:SetStatusBarColor(style.barR, style.barG, style.barB, style.barA)
                    CP.ebonNativeBar = bar
                    button:SetDurationBar(bar, GetDurationBarOptions())

                    local textOwner = CreateFrame("Frame", nil, button)
                    textOwner:SetAllPoints(button)
                    textOwner:SetFrameLevel(style.textLevel)
                    if textOwner.EnableMouse then textOwner:EnableMouse(false) end
                    CP.ebonTextFrame = textOwner
                    CP.ebonTextFrameLevel = style.textLevel
                    CP.ebonTextLayerRetryPending = nil

                    local duration = textOwner:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                    duration:SetPoint("CENTER", textOwner, "CENTER", style.textOffsetX, style.textOffsetY)
                    duration:SetJustifyH("CENTER")
                    duration:SetJustifyV("MIDDLE")
                    if style.fontPath and style.fontSize then
                        duration:SetFont(style.fontPath, style.fontSize, style.fontFlags or "")
                    end
                    duration:SetTextColor(style.textR, style.textG, style.textB, style.textA)
                    duration:SetShadowColor(style.shadowR, style.shadowG, style.shadowB, style.shadowA)
                    duration:SetShadowOffset(style.shadowX, style.shadowY)
                    CP.ebonNativeText = duration

                    button:SetDurationText(duration, GetDurationTextOptions())
                    local binding = button.GetDurationTextBinding and button:GetDurationTextBinding()
                    if binding then
                        if type(binding.SetUpdateInterval) == "function" then binding:SetUpdateInterval(0.10) end
                        if type(binding.SetExpiredText) == "function" then binding:SetExpiredText("") end
                        if type(binding.SetZeroDurationText) == "function" then binding:SetZeroDurationText("") end
                    end
                end)
                if CP.ebonSensor then
                    CP.ebonSensorHost = host
                    CP.ebonSensor:SetAllPoints(host)
                    if CP.ebonSensor.SetFrameLevel and host.GetFrameLevel then
                        CP.ebonSensor:SetFrameLevel(host:GetFrameLevel() or 0)
                    end
                end
            end
        end

        local sensor = CP.ebonSensor
        if sensor then
            CP.ebonSensorRetryPending = nil
            --- The Power element owns the bar for the whole session, but a
            --- re-parent would silently orphan the sensor. Re-point it instead
            --- of rendering into a frame nobody lays out any more.
            if active and CP.ebonSensorHost ~= host then
                CP.ebonSensorHost = host
                sensor:SetParent(host)
                sensor:ClearAllPoints()
                sensor:SetAllPoints(host)
                CP.ebonTextFrameLevel = nil
            end
            if type(sensor.SetEnabled) == "function" then sensor:SetEnabled(active) end
            sensor:SetShown(active)
            if active then
                if sensor.SetFrameLevel and host.GetFrameLevel then
                    sensor:SetFrameLevel(host:GetFrameLevel() or 0)
                end
                RefreshStyle()
                ApplyTextStyle()
            end
        elseif active then
            local inCombat = _G.InCombatLockdown
            CP.ebonSensorRetryPending = type(inCombat) == "function" and inCombat() == true or nil
        end
        return sensor ~= nil
    end

    CP.ApplyEbonTextStyle = ApplyTextStyle
    CP.RefreshEbonStyle = RefreshStyle
    CP.SetEbonSensorActive = SetActive
    return { ApplyTextStyle = ApplyTextStyle, RefreshStyle = RefreshStyle, SetActive = SetActive }
end
