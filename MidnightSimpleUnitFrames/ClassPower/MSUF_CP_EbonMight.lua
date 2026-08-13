--- ClassPower/MSUF_CP_EbonMight.lua
--- Native 12.1 Ebon Might duration text.
---
--- Ebon Might can be restricted in combat, so addon Lua cannot reliably
--- discover it through GetPlayerAuraBySpellID. Blizzard's CustomAuraContainer
--- owns aura discovery and writes the remaining duration directly to a
--- FontString. There is deliberately no direct-aura or Lua timer fallback.

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
    local durationTextOptions

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

    local function ApplyTextStyle()
        local text = CP.ebonNativeText
        local overlay = CP.ebonTextOverlay
        local button = CP.ebonButton
        if not (text and overlay and button) then return end

        local source = CP.text
        if source then
            if type(source.GetFont) == "function" and type(text.SetFont) == "function" then
                local path, size, flags = source:GetFont()
                if path and size then text:SetFont(path, size, flags or "") end
            end
            if type(source.GetTextColor) == "function" then text:SetTextColor(source:GetTextColor()) end
            if type(source.GetShadowColor) == "function" then text:SetShadowColor(source:GetShadowColor()) end
            if type(source.GetShadowOffset) == "function" then text:SetShadowOffset(source:GetShadowOffset()) end
        end

        local b = _cpDB.bars or {}
        overlay:ClearAllPoints()
        overlay:SetPoint("CENTER", button, "CENTER",
            tonumber(b.classPowerTextOffsetX) or 0,
            tonumber(b.classPowerTextOffsetY) or 0)
    end

    local function SetActive(active)
        active = active == true
        if active and not CP.ebonSensor then
            local A3 = _G.MSUF_Auras3
            local createSensor = A3 and A3.CreateClassPowerAuraSensor
            if type(createSensor) == "function" and CP.container and EBON.SPELL_ID then
                CP.ebonSensor = createSensor(CP.container, "msuf_cp_ebon_might", { [EBON.SPELL_ID] = true }, function(button)
                    CP.ebonButton = button
                    button:ClearAllPoints()
                    button:SetAllPoints(button:GetParent())
                    button:SetMouseMotionEnabled(false)
                    if button.EnableMouse then button:EnableMouse(false) end
                    button:SetFrameLevel(CP.container:GetFrameLevel() + 16)

                    local overlay = CreateFrame("Frame", nil, button)
                    overlay:SetSize(1, 1)
                    overlay:SetFrameLevel(button:GetFrameLevel() + 1)
                    CP.ebonTextOverlay = overlay

                    local duration = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                    duration:SetPoint("CENTER", overlay, "CENTER", 0, 0)
                    duration:SetJustifyH("CENTER")
                    duration:SetJustifyV("MIDDLE")
                    duration:SetShadowColor(0, 0, 0, 1)
                    duration:SetShadowOffset(1, -1)
                    CP.ebonNativeText = duration
                    ApplyTextStyle()

                    button:SetDurationText(duration, GetDurationTextOptions())
                    local binding = button.GetDurationTextBinding and button:GetDurationTextBinding()
                    if binding then
                        if type(binding.SetUpdateInterval) == "function" then binding:SetUpdateInterval(0.10) end
                        if type(binding.SetExpiredText) == "function" then binding:SetExpiredText("") end
                        if type(binding.SetZeroDurationText) == "function" then binding:SetZeroDurationText("") end
                    end
                end)
                if CP.ebonSensor then
                    CP.ebonSensor:SetAllPoints(CP.container)
                    CP.ebonSensor:SetFrameLevel(CP.container:GetFrameLevel() + 15)
                end
            end
        end

        local sensor = CP.ebonSensor
        if sensor then
            if type(sensor.SetEnabled) == "function" then sensor:SetEnabled(active) end
            sensor:SetShown(active)
            if active then
                ApplyTextStyle()
                if CP.text then CP.text:Hide() end
            end
        end
        return sensor ~= nil
    end

    CP.ApplyEbonTextStyle = ApplyTextStyle
    CP.SetEbonSensorActive = SetActive
    return { ApplyTextStyle = ApplyTextStyle, SetActive = SetActive }
end
