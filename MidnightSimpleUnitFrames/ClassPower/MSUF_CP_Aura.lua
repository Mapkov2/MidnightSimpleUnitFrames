local _, MSUF = ...
local shared = MSUF.CPFactoryShared.Modes
local modeBuilders = shared.modeBuilders
local type = shared.type
local CP_SetPassthroughFormattedText = shared.CP_SetPassthroughFormattedText
local CP_StampText = shared.CP_StampText
local CP_SetPassthroughText = shared.CP_SetPassthroughText
local PixelLayoutRegion = shared.PixelLayoutRegion
local OverrideRGB = shared.OverrideRGB
local Snap = MSUF.Require("MSUF_Snap", "ClassPower/MSUF_CP_Aura.lua")
local IS_CLASSIC = shared.IS_CLASSIC
local CP_StampMinMax = shared.CP_StampMinMax
local CP_SetPowerValue = shared.CP_SetPowerValue
local CP_StampAlpha = shared.CP_StampAlpha
local CP_PaintPip = shared.CP_PaintPip
local CP_PaintResourceText = shared.CP_PaintResourceText
local CP_StampStatusBarColor = shared.CP_StampStatusBarColor
local CP_StampVertexColor = shared.CP_StampVertexColor
local CP_StampShown = shared.CP_StampShown

modeBuilders.AURA = function(E)
    local type = type
    local tonumber = tonumber
    local math_floor = math.floor
    --- Bound once by AURA at controller load. Devourer reads the Collapsing
    --- Star cost on every Meta aura update.
    local GetTime, CP, _cpDB, C_UnitAuras, GetTrackedPlayerAura, C_Spell, CPK, NotSecret
    local ResolveClassPowerBgColor, ResolveMWAbove5Color, CP_CheckAutoHide
    local CollapsingStarCost
    local MAX_FRAGMENT_NOTCHES
    --- Top of the Pip gap slider; the divider budget is shared across it.
    local MAX_PIP_GAP = 8

    --- Aura count writers for CP_PaintResourceText: a plain count is cached,
    --- a restricted one goes straight to the native widget.
    local function WriteRestrictedCurMax(txt, value, maximum)
        if NotSecret(value) then
            CP_SetPassthroughFormattedText(txt, "%d / %d", tonumber(value) or 0, maximum)
        else
            CP_SetPassthroughFormattedText(txt, "%s / %d", value, maximum)
        end
    end

    local function WriteAuraCount(txt, value)
        if NotSecret(value) then CP_StampText(txt, tonumber(value) or 0)
        else CP_SetPassthroughText(txt, value) end
    end

    --- Resolved once by AURA, on the Classic clients only: no Classic game type
    --- loads a Blizzard call site for either entry point, so the Classic build
    --- must not assume them and keeps the client decision off the per-pip
    --- render path.
    local ClassicSpellCastCount, ClassicSpellMaxApplications

    --- Devourer's fragment separators.
    --- Its Soul Fragment maximum is talent-dependent (30/35/50), far above
    --- MAX_CLASS_POWER, so the resource can never own one StatusBar per
    --- fragment - clamping it to ten is exactly what made the fill saturate at
    --- ten fragments. The fill therefore stays Blizzard's single normalized bar
    --- and the fragment boundaries are drawn as notches over it, which is what
    --- the Separator and Pip gap sliders act on.
    --- Placement is cold path. Aura traffic only compares the resolved fragment
    --- count, so a stack change costs one comparison and touches no texture;
    --- only a Meta transition, a changed Collapsing Star cost or a relayout
    --- moves a notch.
    local fragCount
    local function ApplyFragmentNotches(count)
        local bar = CP.bars and CP.bars[1]
        if not (bar and type(bar.CreateTexture) == "function") then return end
        fragCount = count

        local pool = CP.fragNotches
        if not pool then
            pool = {}
            CP.fragNotches = pool
        end

        local b = _cpDB.bars or {}
        local tickW = tonumber(b.classPowerTickWidth) or 1
        if tickW < 0 then tickW = 0 elseif tickW > 4 then tickW = 4 end
        local gap = tonumber(b.classPowerGap) or 0
        if gap < 0 then gap = 0 elseif gap > 8 then gap = 8 end
        local width = (type(bar.GetWidth) == "function" and tonumber(bar:GetWidth())) or 0
        local height = (type(bar.GetHeight) == "function" and tonumber(bar:GetHeight())) or 0
        --- Past the pool ceiling the dividers would no longer sit on real
        --- fragment boundaries, and a separator that lies about the count is
        --- the bug this bar already had. Draw none instead.
        if count > MAX_FRAGMENT_NOTCHES then count = 0 end

        --- A divider may take every pixel the fragments do not need, and that
        --- budget is what the two sliders share: Separator keeps its literal
        --- width inside it, Pip gap spends the rest of it in proportion.
        --- Spending it literally would saturate after two steps on a
        --- forty-fragment bar - six pixels cannot hold nine distinct widths -
        --- and read as a Pip gap that ignores its setting. Both sliders at zero
        --- stays the opt-out.
        local notchW = 0
        if count >= 2 and width > count and (tickW + gap) > 0 then
            local maxNotchW = math_floor((width - count) / (count - 1))
            if maxNotchW >= 1 then
                local base = (tickW > maxNotchW) and maxNotchW or tickW
                notchW = base + math_floor(((gap * (maxNotchW - base)) / MAX_PIP_GAP) + 0.5)
                --- Crisp like every other separator, but a scale that snaps a
                --- hairline below one pixel must not erase the division.
                local snapped = tonumber(Snap(CP.container or bar, notchW))
                if snapped and snapped >= 1 then notchW = snapped end
                if notchW > maxNotchW then notchW = maxNotchW end
            end
        end

        local shown = 0
        if count >= 2 and notchW >= 1 and height >= 1 then
            local reverse = (b.classPowerFillReverse == true)
            local limit = width - notchW
            for i = 1, count - 1 do
                local tex = pool[i]
                if not tex then
                    tex = PixelLayoutRegion(bar:CreateTexture(nil, "OVERLAY", nil, 7))
                    tex:SetTexture("Interface\\Buttons\\WHITE8x8")
                    tex:SetVertexColor(0, 0, 0, 1)
                    pool[i] = tex
                end
                local x = math_floor(((width * i) / count) - (notchW * 0.5) + 0.5)
                if x < 0 then x = 0 elseif x > limit then x = limit end
                tex:ClearAllPoints()
                tex:SetSize(notchW, height)
                if reverse then
                    tex:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -x, 0)
                else
                    tex:SetPoint("TOPLEFT", bar, "TOPLEFT", x, 0)
                end
                tex:Show()
                shown = i
            end
        end
        for i = shown + 1, #pool do pool[i]:Hide() end
    end

    --- Passing false is how every other resource and every shape mode drops the
    --- notches again when it takes the single bar over.
    local function RefreshFragmentNotches(active)
        ApplyFragmentNotches((active and fragCount > 1) and fragCount or 0)
    end

    local function GetPlayerAura(spellID)
        if type(GetTrackedPlayerAura) == "function" then
            return GetTrackedPlayerAura(spellID)
        end
        return C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID and C_UnitAuras.GetPlayerAuraBySpellID(spellID) or nil
    end

    local function GetTrackedTipStacks()
        if CP.spExpires and GetTime and GetTime() >= CP.spExpires then
            CP.spStacks = 0
            CP.spExpires = nil
        end
        return tonumber(CP.spStacks) or 0
    end

    local function ResolveDHColor(isVoidMeta)
        local r, g, b = OverrideRGB(_cpDB.colorOverrides, isVoidMeta and "SOUL_FRAGMENTS_META" or "SOUL_FRAGMENTS")
        if r then return r, g, b end
        if isVoidMeta then return 0.60, 0.20, 0.93 end
        return 0.00, 0.80, 0.00
    end

    local function UpdateSegmented(powerType, maxPower)
        if maxPower <= 0 then return end
        local visual = CP.visual
        local smoothInterp = visual and visual.smoothInterp
        local baseR, baseG, baseB = visual and visual.baseR or 1, visual and visual.baseG or 1, visual and visual.baseB or 1
        local useSlotColors = visual and visual.useSlotColors == true
        local bgA = visual and visual.bgAlpha or 0.3
        local bgR, bgG, bgB = visual and visual.bgR or 0, visual and visual.bgG or 0, visual and visual.bgB or 0
        local filledAlpha, emptyAlpha = visual and visual.filledAlpha or (CP.filledAlpha or 1), visual and visual.emptyAlpha or (CP.emptyAlpha or 0.3)
        if powerType == "SOUL_FRAGMENTS_VENG" then
            local rawCur
            if not IS_CLASSIC then
                rawCur = C_Spell.GetSpellCastCount(CPK.SPELL.SOUL_CLEAVE)
            elseif ClassicSpellCastCount then
                rawCur = ClassicSpellCastCount(CPK.SPELL.SOUL_CLEAVE)
            end
            local curSafe = NotSecret(rawCur)
            local rawCurSecret = not curSafe
            if curSafe and rawCur == nil then rawCur = 0 end
            local isFull = visual and visual.useFullColor == true and curSafe and (tonumber(rawCur) or 0) >= maxPower
            for i = 1, maxPower do
                local bar = CP.bars[i]
                if bar then
                    CP_StampMinMax(bar, i - 1, i)
                    CP_SetPowerValue(bar, rawCur, smoothInterp, rawCurSecret)
                    CP_StampAlpha(bar, filledAlpha)
                    local slotR = useSlotColors and visual.slotR and visual.slotR[i]
                    CP_PaintPip(bar, isFull and visual.fullR or (slotR or baseR),
                        isFull and visual.fullG or (slotR and visual.slotG[i] or baseG),
                        isFull and visual.fullB or (slotR and visual.slotB[i] or baseB), bgR, bgG, bgB, bgA)
                end
            end
            local txt = CP.text
            if txt then CP_PaintResourceText(txt, visual, _cpDB.textMode, rawCur, maxPower, nil, WriteRestrictedCurMax) end
            CP_CheckAutoHide(curSafe and tonumber(rawCur) or nil, maxPower)
        else
            local cur = 0
            local textValue = 0
            local restrictedApplications = false
            if powerType == "MAELSTROM_WEAPON" then
                local info = GetPlayerAura(CPK.SPELL.MAELSTROM_WEAPON)
                if info then
                    local apps = info.applications
                    textValue = apps
                    if NotSecret(apps) then
                        if apps ~= nil then cur = tonumber(apps) or 0 end
                    else
                        restrictedApplications = true
                    end
                end
            elseif powerType == "TIP_OF_THE_SPEAR" then
                cur = GetTrackedTipStacks()
                textValue = cur
            elseif powerType == "ICICLES" then
                local icicleID = CPK.SPELL and CPK.SPELL.ICICLES
                if icicleID then
                    local info = GetPlayerAura(icicleID)
                    if info then
                        local apps = info.applications
                        textValue = apps
                        if NotSecret(apps) then
                            if apps ~= nil then cur = tonumber(apps) or 0 end
                        else
                            restrictedApplications = true
                        end
                    end
                end
            elseif IS_CLASSIC and powerType == "MISTS_ARCANE_CHARGES" then
                --- Mists Arcane Charges (aura 36032, Game/Mists/ClassPower.lua).
                local arcaneChargeID = CPK.SPELL and CPK.SPELL.MISTS_ARCANE_CHARGE
                if arcaneChargeID then
                    local info = GetPlayerAura(arcaneChargeID)
                    if info then
                        local apps = info.applications
                        if NotSecret(apps) and apps ~= nil then cur = tonumber(apps) or 0 end
                    end
                end
                textValue = cur
            end
            local mwAbove5 = (powerType == "MAELSTROM_WEAPON" and cur > CPK.THRESH.MW_SPEND)
            local isFull = visual and visual.useFullColor == true and cur >= maxPower
            local abR, abG, abB
            if mwAbove5 then abR, abG, abB = ResolveMWAbove5Color() end
            for i = 1, maxPower do
                local bar = CP.bars[i]
                if bar then
                    local isFilled = not restrictedApplications and (i <= cur)
                    if restrictedApplications then
                        -- Blizzard's CustomAuraButton application bar follows
                        -- this same contract: restricted application counts go
                        -- straight into StatusBar:SetValue. Giving every pip its
                        -- own [i-1, i] range lets native clamping resolve the
                        -- filled state without comparing the secret in Lua.
                        CP_StampMinMax(bar, i - 1, i)
                        CP_SetPowerValue(bar, textValue, smoothInterp, true)
                        CP_StampAlpha(bar, filledAlpha)
                    else
                        CP_StampMinMax(bar, 0, 1)
                        CP_SetPowerValue(bar, isFilled and 1 or 0, smoothInterp)
                        CP_StampAlpha(bar, isFilled and filledAlpha or emptyAlpha)
                    end
                    local r, g, b
                    if not restrictedApplications and isFull then
                        r, g, b = visual.fullR, visual.fullG, visual.fullB
                    elseif not restrictedApplications and mwAbove5 and isFilled and i > CPK.THRESH.MW_SPEND then
                        r, g, b = abR, abG, abB
                    else
                        local slotR = useSlotColors and visual.slotR and visual.slotR[i]
                        r, g, b = slotR or baseR, slotR and visual.slotG[i] or baseG, slotR and visual.slotB[i] or baseB
                    end
                    CP_PaintPip(bar, r, g, b, bgR, bgG, bgB, bgA)
                end
            end
            local txt = CP.text
            if txt then CP_PaintResourceText(txt, visual, _cpDB.textMode, textValue, maxPower, nil, WriteAuraCount) end
            local autoHideCur = cur
            if restrictedApplications then autoHideCur = nil end
            CP_CheckAutoHide(autoHideCur, maxPower)
        end
    end

    local function UpdateSingle()
        --- Devourer mirrors Blizzard's 12.1 Soul Fragments bar and Elemental's
        --- MSUF presentation: one continuous bar normalized to the real maximum.
        local cur, displayCur, inMeta = 0, 0, false
        local textValue = 0
        inMeta = not not GetPlayerAura(CPK.SPELL.VOID_METAMORPHOSIS)
        local progressMax
        if inMeta then
            --- Collapsing Star's cost can change while Meta is active.
            if type(CollapsingStarCost) == "function" then
                local rawCost = CollapsingStarCost()
                if NotSecret(rawCost) and rawCost ~= nil then progressMax = tonumber(rawCost) end
            end
            local whispers = GetPlayerAura(CPK.SPELL.SILENCE_THE_WHISPERS)
            if whispers then
                local apps = whispers.applications
                textValue = apps
                if NotSecret(apps) and apps ~= nil then
                    displayCur = tonumber(apps) or 0
                end
            end
        else
            --- Read Blizzard's live maximum just like its own bar and ElvUI do;
            --- talent setups can expose 40, 50, or another supported maximum.
            local rawMax
            if not IS_CLASSIC then
                rawMax = C_Spell.GetSpellMaxCumulativeAuraApplications(CPK.SPELL.DARK_HEART)
            elseif ClassicSpellMaxApplications then
                rawMax = ClassicSpellMaxApplications(CPK.SPELL.DARK_HEART)
            end
            if NotSecret(rawMax) and rawMax ~= nil then progressMax = tonumber(rawMax) end
            local darkHeart = GetPlayerAura(CPK.SPELL.DARK_HEART)
            if darkHeart then
                local apps = darkHeart.applications
                textValue = apps
                if NotSecret(apps) and apps ~= nil then
                    displayCur = tonumber(apps) or 0
                end
            end
        end
        if progressMax and progressMax > 0 then cur = displayCur / progressMax end
        if cur < 0 then cur = 0 elseif cur > 1 then cur = 1 end
        local visual = CP.visual
        local smoothInterp = visual and visual.smoothInterp
        local colorByType = not visual or visual.colorByType ~= false
        local r, g, bl
        if colorByType then r, g, bl = ResolveDHColor(inMeta) else r, g, bl = 1,1,1 end
        local bgA = visual and visual.bgAlpha or 0.3
        local bgR, bgG, bgB = ResolveClassPowerBgColor(inMeta and "SOUL_FRAGMENTS_META" or "SOUL_FRAGMENTS")
        local filledAlpha, emptyAlpha = visual and visual.filledAlpha or (CP.filledAlpha or 1), visual and visual.emptyAlpha or (CP.emptyAlpha or 0.3)
        local bar = CP.bars[1]
        if bar then
            CP_StampMinMax(bar, 0, 1)
            CP_SetPowerValue(bar, cur, smoothInterp)
            CP_StampAlpha(bar, cur > 0.01 and filledAlpha or emptyAlpha)
            CP_StampStatusBarColor(bar, r, g, bl, 1)
            CP_StampVertexColor(bar._bg, bgR, bgG, bgB, bgA)
        end
        --- Separators follow the resolved maximum, never the stack value, so a
        --- fragment gained or spent leaves every notch untouched.
        local notchCount = math_floor(tonumber(progressMax) or 0)
        if notchCount < 2 then notchCount = 0 end
        if fragCount ~= notchCount then ApplyFragmentNotches(notchCount) end
        local visualVersion = visual and visual.version or 0
        if CP._singleVisualVersion ~= visualVersion or CP._singleVisualMode ~= CP.renderMode then
            for i = 2, CP.maxBars do if CP.bars[i] then CP_StampShown(CP.bars[i], false) end end
            for i = 1, #CP.ticks do if CP.ticks[i] then CP_StampShown(CP.ticks[i], false) end end
            CP._singleVisualVersion = visualVersion
            CP._singleVisualMode = CP.renderMode
        end
        local txt = CP.text
        if txt then CP_PaintResourceText(txt, visual, _cpDB.textMode, textValue, progressMax or 1, nil, WriteAuraCount) end
        CP_CheckAutoHide(cur, 1)
    end

    local API = {
        UpdateSegmented = UpdateSegmented,
        UpdateSingle = UpdateSingle,
    }

        GetTime, CP, _cpDB = E.GetTime, E.CP, E._cpDB
        C_UnitAuras, GetTrackedPlayerAura, C_Spell = E.C_UnitAuras, E.GetTrackedPlayerAura, E.C_Spell
        CPK, NotSecret = E.CPK, E.NotSecret
        ResolveClassPowerBgColor, ResolveMWAbove5Color = E.ResolveClassPowerBgColor, E.ResolveMWAbove5Color
        CP_CheckAutoHide = E.CP_CheckAutoHide
        CollapsingStarCost = GetCollapsingStarCost
        MAX_FRAGMENT_NOTCHES = (E.CPConst and tonumber(E.CPConst.MAX_FRAGMENT_NOTCHES)) or 64
        ClassicSpellCastCount, ClassicSpellMaxApplications = nil, nil
        if IS_CLASSIC then
            local castCount = C_Spell and C_Spell.GetSpellCastCount
            if type(castCount) == "function" then ClassicSpellCastCount = castCount end
            local maxApplications = C_Spell and C_Spell.GetSpellMaxCumulativeAuraApplications
            if type(maxApplications) == "function" then ClassicSpellMaxApplications = maxApplications end
        end
        fragCount = -1
        --- Layout owns the geometry, so it hands the new one straight back here
        --- instead of leaving the notches stale until the next aura event.
        CP.RefreshFragmentNotches = RefreshFragmentNotches
    return API
end
