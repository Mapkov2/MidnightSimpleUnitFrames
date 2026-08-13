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

    local function SetHostShown(host, shown)
        if not host then return end
        if type(host.SetShown) == "function" then
            host:SetShown(shown)
        elseif shown then
            host:Show()
        else
            host:Hide()
        end
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

        local source = CP.text
        if source then
            if style.fontPath == nil and type(source.GetFont) == "function" then
                style.fontPath, style.fontSize, style.fontFlags = source:GetFont()
            end
            if style.textR == nil and type(source.GetTextColor) == "function" then
                style.textR, style.textG, style.textB, style.textA = source:GetTextColor()
            end
            if style.shadowR == nil and type(source.GetShadowColor) == "function" then
                style.shadowR, style.shadowG, style.shadowB, style.shadowA = source:GetShadowColor()
            end
            if style.shadowX == nil and type(source.GetShadowOffset) == "function" then
                style.shadowX, style.shadowY = source:GetShadowOffset()
            end
        end

        local bars = _cpDB and _cpDB.bars or {}
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
        local textLayer = tonumber(bars.classPowerTextLayer) or 5
        if textLayer < 0 then textLayer = 0 elseif textLayer > 30 then textLayer = 30 end
        textLayer = math.floor(textLayer + 0.5)
        local layers = MSUF.UF and MSUF.UF.Layers
        style.textLevel = tonumber(style.textLevel)
            or (layers and layers.TextLevel and layers.TextLevel(CP.container, textLayer, 5))
            or (layers and layers.ElementLevel and layers.ElementLevel(textLayer, 5, 8))
            or ((CP.container and CP.container.GetFrameLevel and CP.container:GetFrameLevel() or 0) + 10)
        style.textOffsetX = tonumber(style.textOffsetX)
            or tonumber(bars.classPowerTextOffsetX) or 0
        style.textOffsetY = tonumber(style.textOffsetY)
            or tonumber(bars.classPowerTextOffsetY) or 0
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

    local function SetActive(active)
        active = active == true
        if not active and CP.ebonSensorDesired ~= true then
            CP.ebonSensorRetryPending = nil
            CP.ebonTextLayerRetryPending = nil
        end
        local host = CP.ebonSensorHost
        if active and not host then
            host = ResolveHost()
        elseif not host then
            host = CP.ebonHost
        end
        if not host then return false end

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
            if type(sensor.SetEnabled) == "function" then sensor:SetEnabled(active) end
            sensor:SetShown(active)
            if active then ApplyTextStyle() end
        elseif active then
            local inCombat = _G.InCombatLockdown
            CP.ebonSensorRetryPending = type(inCombat) == "function" and inCombat() == true or nil
        end
        SetHostShown(host, active and sensor ~= nil)
        return sensor ~= nil
    end

    CP.ApplyEbonTextStyle = ApplyTextStyle
    CP.SetEbonSensorActive = SetActive
    return { ApplyTextStyle = ApplyTextStyle, SetActive = SetActive }
end
