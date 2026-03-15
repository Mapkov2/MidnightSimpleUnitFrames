-- ============================================================================
-- MSUF_CP_Mode_Stagger.lua
-- Phase 4 ClassPower split: Brewmaster stagger mode extracted from the core
-- file.
-- ============================================================================

_G.MSUF_CP_MODE_BUILDERS = _G.MSUF_CP_MODE_BUILDERS or {}

_G.MSUF_CP_MODE_BUILDERS.STAGGER = function(E)
    local type = type
    local tonumber = tonumber
    local CP = E.CP
    local _cpDB = E._cpDB
    local NotSecret = E.NotSecret
    local UnitStagger = E.UnitStagger
    local UnitHealthMax = E.UnitHealthMax
    local ResolveClassPowerBgColor = E.ResolveClassPowerBgColor
    local CP_CheckAutoHide = E.CP_CheckAutoHide
    local STAGGER_CONST = E.STAGGER_CONST or {}
    local GetFilledAlpha = E.GetFilledAlpha

    local staggerCachedTier = 0

    local function ResolveStaggerColor(tier)
        local ov = _cpDB.colorOverrides
        if type(ov) == "table" then
            local token = STAGGER_CONST.TOKENS and STAGGER_CONST.TOKENS[tier]
            local c = token and ov[token]
            if type(c) == "table" then
                local r, g, b = c[1] or c.r, c[2] or c.g, c[3] or c.b
                if type(r) == "number" and type(g) == "number" and type(b) == "number" then
                    return r, g, b
                end
            end
        end
        local def = STAGGER_CONST.COLOR_DEFAULTS and STAGGER_CONST.COLOR_DEFAULTS[tier]
        if def then
            return def[1], def[2], def[3]
        end
        if tier == 3 then return 1.00, 0.42, 0.42 end
        if tier == 2 then return 1.00, 0.98, 0.72 end
        return 0.52, 1.00, 0.52
    end

    local function Update(powerType, maxPower)
        local cur = UnitStagger and UnitStagger("player") or 0
        local mx = UnitHealthMax("player") or 1
        if cur == nil then cur = 0 end
        if mx == nil then mx = 1 end

        local bar = CP.bars[1]
        if not bar then return end

        bar:SetMinMaxValues(0, mx)
        bar:SetValue(cur)
        bar:SetAlpha(GetFilledAlpha())
        bar:Show()

        if NotSecret(cur) and NotSecret(mx) then
            if mx <= 0 then mx = 1 end
            local perc = cur / mx
            local tier
            if perc >= (STAGGER_CONST.RED_TRANSITION or 0.6) then tier = 3
            elseif perc > (STAGGER_CONST.YELLOW_TRANSITION or 0.3) then tier = 2
            else tier = 1 end

            if tier ~= staggerCachedTier then
                staggerCachedTier = tier
                local r, g, b = ResolveStaggerColor(tier)
                bar:SetStatusBarColor(r, g, b, 1)
            end
        end

        local bgA = (_cpDB.bars and tonumber(_cpDB.bgAlpha)) or 0.3
        local bgR, bgG, bgB = ResolveClassPowerBgColor("STAGGER")
        if bar._bg then bar._bg:SetVertexColor(bgR, bgG, bgB, bgA) end

        for i = 2, CP.maxBars do
            local b2 = CP.bars[i]
            if b2 then b2:Hide() end
        end
        for i = 1, #CP.ticks do
            if CP.ticks[i] then CP.ticks[i]:Hide() end
        end

        local txt = CP.text
        if txt then
            local showText = _cpDB.bars and (_cpDB.showText == true)
            if showText and NotSecret(cur) then
                if cur >= 1000 then
                    txt:SetFormattedText("%.1fK", cur / 1000)
                else
                    txt:SetFormattedText("%d", cur)
                end
                txt:Show()
            elseif showText then
                txt:SetText("")
                txt:Hide()
            else
                txt:Hide()
            end
        end

        CP_CheckAutoHide(cur, mx)
    end

    return {
        Update = Update,
    }
end
