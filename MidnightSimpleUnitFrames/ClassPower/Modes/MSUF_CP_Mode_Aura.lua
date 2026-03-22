-- ============================================================================
-- MSUF_CP_Mode_Aura.lua
-- Phase 2 ClassPower split: aura-driven modes extracted from the core file.
-- Secret-safe: C_UnitAuras fields (applications) and C_Spell returns can be
-- secret in 12.0. All Lua-side comparisons/arithmetic guarded with NotSecret.
-- ============================================================================

_G.MSUF_CP_MODE_BUILDERS = _G.MSUF_CP_MODE_BUILDERS or {}

_G.MSUF_CP_MODE_BUILDERS.AURA = function(E)
    local type = type
    local tonumber = tonumber
    local GetTime = E.GetTime
    local CP = E.CP
    local _cpDB = E._cpDB
    local C_UnitAuras = E.C_UnitAuras
    local C_Spell = E.C_Spell
    local CPK = E.CPK
    local WW = E.WW
    local NotSecret = E.NotSecret
    local ResolveClassPowerColor = E.ResolveClassPowerColor
    local ResolveClassPowerBgColor = E.ResolveClassPowerBgColor
    local ResolveMWAbove5Color = E.ResolveMWAbove5Color
    local CP_CheckAutoHide = E.CP_CheckAutoHide

    local function ResolveDHColor(isVoidMeta)
        local ov = _cpDB.colorOverrides
        if type(ov) == "table" then
            local token = isVoidMeta and "SOUL_FRAGMENTS_META" or "SOUL_FRAGMENTS"
            local c = ov[token]
            if type(c) == "table" then
                local r, g, b = c[1] or c.r, c[2] or c.g, c[3] or c.b
                if type(r) == "number" and type(g) == "number" and type(b) == "number" then return r, g, b end
            end
        end
        if isVoidMeta then return 0.60, 0.20, 0.93 end
        return 0.00, 0.80, 0.00
    end

    local function UpdateSegmented(powerType, maxPower)
        if maxPower <= 0 then return end
        local colorByType = true
        local b = _cpDB.bars or {}
        if b then colorByType = (b.classPowerColorByType ~= false) end
        local baseR, baseG, baseB
        if colorByType then baseR, baseG, baseB = ResolveClassPowerColor(powerType) else baseR, baseG, baseB = 1,1,1 end
        local bgA = tonumber(b.classPowerBgAlpha) or 0.3
        local bgR, bgG, bgB = ResolveClassPowerBgColor(powerType)
        local filledAlpha, emptyAlpha = E.GetFilledAlpha(), E.GetEmptyAlpha()
        if powerType == "SOUL_FRAGMENTS_VENG" then
            local getCastCount = C_Spell and C_Spell.GetSpellCastCount
            local rawCur = getCastCount and getCastCount(CPK.SPELL.SOUL_CLEAVE)
            local cur = 0
            local curSafe = (rawCur ~= nil and NotSecret(rawCur))
            if curSafe then cur = tonumber(rawCur) or 0 end
            for i = 1, maxPower do
                local bar = CP.bars[i]
                if bar then
                    bar:SetMinMaxValues(i - 1, i)
                    bar:SetValue(cur)
                    bar:SetAlpha(filledAlpha)
                    bar:SetStatusBarColor(baseR, baseG, baseB, 1)
                    bar._bg:SetVertexColor(bgR, bgG, bgB, bgA)
                end
            end
            local txt = CP.text
            if txt then
                local showText = b.classPowerShowText == true
                if showText and curSafe then txt:SetFormattedText("%d / %d", cur, maxPower); txt:Show() else txt:Hide() end
            end
        else
            local cur = 0
            if powerType == "MAELSTROM_WEAPON" then
                if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
                    local info = C_UnitAuras.GetPlayerAuraBySpellID(CPK.SPELL.MAELSTROM_WEAPON)
                    if info then
                        local apps = info.applications
                        if apps ~= nil and NotSecret(apps) then cur = tonumber(apps) or 0 end
                    end
                end
            elseif powerType == "WHIRLWIND" then
                cur = WW.GetStacks()
            elseif powerType == "TIP_OF_THE_SPEAR" then
                if CP.spExpires and GetTime() >= CP.spExpires then CP.spStacks = 0; CP.spExpires = nil end
                cur = CP.spStacks
            end
            local mwAbove5 = (powerType == "MAELSTROM_WEAPON" and cur > CPK.THRESH.MW_SPEND)
            local abR, abG, abB
            if mwAbove5 then abR, abG, abB = ResolveMWAbove5Color() end
            for i = 1, maxPower do
                local bar = CP.bars[i]
                if bar then
                    local isFilled = (i <= cur)
                    bar:SetMinMaxValues(0, 1)
                    bar:SetValue(isFilled and 1 or 0)
                    bar:SetAlpha(isFilled and filledAlpha or emptyAlpha)
                    if mwAbove5 and isFilled and i > CPK.THRESH.MW_SPEND then bar:SetStatusBarColor(abR,abG,abB,1) else bar:SetStatusBarColor(baseR,baseG,baseB,1) end
                    bar._bg:SetVertexColor(bgR, bgG, bgB, bgA)
                end
            end
            local txt = CP.text
            if txt then
                local showText = b.classPowerShowText == true
                if showText and cur > 0 then txt:SetText(cur); txt:Show() else txt:Hide() end
            end
            CP_CheckAutoHide(cur, maxPower)
        end
    end

    local function BuildWWRender()
        return function()
            if CP.visible and CP.powerType == "WHIRLWIND" then UpdateSegmented(CP.powerType, CP.currentMax) end
        end
    end

    local function UpdateSingle(powerType, maxPower)
        local cur, displayCur, inMeta = 0, 0, false
        if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
            inMeta = not not C_UnitAuras.GetPlayerAuraBySpellID(CPK.SPELL.VOID_METAMORPHOSIS)
            if inMeta then
                local whispers = C_UnitAuras.GetPlayerAuraBySpellID(CPK.SPELL.SILENCE_THE_WHISPERS)
                if whispers then
                    local apps = whispers.applications
                    if apps ~= nil and NotSecret(apps) then
                        displayCur = tonumber(apps) or 0
                        local cost = 1
                        if type(GetCollapsingStarCost) == "function" then
                            local rawCost = GetCollapsingStarCost()
                            if rawCost ~= nil and NotSecret(rawCost) then cost = tonumber(rawCost) or 1 end
                        end
                        if cost > 0 then cur = displayCur / cost end
                    end
                end
            else
                local darkHeart = C_UnitAuras.GetPlayerAuraBySpellID(CPK.SPELL.DARK_HEART)
                if darkHeart then
                    local apps = darkHeart.applications
                    if apps ~= nil and NotSecret(apps) then
                        displayCur = tonumber(apps) or 0
                        local maxApp = 1
                        if C_Spell and C_Spell.GetSpellMaxCumulativeAuraApplications then
                            local rawMax = C_Spell.GetSpellMaxCumulativeAuraApplications(CPK.SPELL.DARK_HEART)
                            if rawMax ~= nil and NotSecret(rawMax) then maxApp = tonumber(rawMax) or 1 end
                        end
                        if maxApp > 0 then cur = displayCur / maxApp end
                    end
                end
            end
        end
        if cur > 1 then cur = 1 end
        local colorByType = true
        local b = _cpDB.bars or {}
        if b then colorByType = (b.classPowerColorByType ~= false) end
        local r, g, bl
        if colorByType then r, g, bl = ResolveDHColor(inMeta) else r, g, bl = 1,1,1 end
        local bgA = tonumber(b.classPowerBgAlpha) or 0.3
        local bgR, bgG, bgB = ResolveClassPowerBgColor(inMeta and "SOUL_FRAGMENTS_META" or "SOUL_FRAGMENTS")
        local filledAlpha, emptyAlpha = E.GetFilledAlpha(), E.GetEmptyAlpha()
        local bar = CP.bars[1]
        if bar then
            bar:SetMinMaxValues(0, 1)
            bar:SetValue(cur)
            bar:SetAlpha(cur > 0.01 and filledAlpha or emptyAlpha)
            bar:SetStatusBarColor(r, g, bl, 1)
            if bar._bg then bar._bg:SetVertexColor(bgR, bgG, bgB, bgA) end
        end
        for i = 2, CP.maxBars do if CP.bars[i] then CP.bars[i]:Hide() end end
        for i = 1, #CP.ticks do if CP.ticks[i] then CP.ticks[i]:Hide() end end
        local txt = CP.text
        if txt then
            local showText = b.classPowerShowText == true
            if showText and displayCur > 0 then txt:SetText(displayCur); txt:Show() else txt:Hide() end
        end
        local intCur = (cur > 0.01) and 1 or 0
        CP_CheckAutoHide(intCur, 1)
    end

    return { UpdateSegmented = UpdateSegmented, UpdateSingle = UpdateSingle, BuildWWRender = BuildWWRender }
end
