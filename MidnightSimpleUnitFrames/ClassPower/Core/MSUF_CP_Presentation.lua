-- ============================================================================
-- MSUF_CP_Presentation.lua
-- Pure presentation helpers for Class Power (phase 7A split).
-- Intentionally low-risk: no build/layout/value-flow logic moves here.
-- ============================================================================

local builders = _G.MSUF_CP_CORE_BUILDERS
if type(builders) ~= "table" then
    builders = {}
    _G.MSUF_CP_CORE_BUILDERS = builders
end

builders.PRESENTATION = function(E)
    local CP = E.CP
    local _cpDB = E._cpDB
    local PT = E.PT
    local math_floor = E.math_floor or math.floor
    local tonumber = E.tonumber or tonumber
    local ResolveClassPowerColor = E.ResolveClassPowerColor
    local CP_ResolveTexture = E.CP_ResolveTexture
    local GetUpdateFn = E.GetUpdateFn

    local _cpFontRev = 0

    local function CDM_GetScaledWidth(cdmFrame, targetFrame)
        if not cdmFrame or not cdmFrame.GetWidth then return nil end
        local w = cdmFrame:GetWidth()
        if not w or w < 1 then return nil end
        local cdmScale = (cdmFrame.GetEffectiveScale and cdmFrame:GetEffectiveScale()) or 1
        local tgtScale = (targetFrame and targetFrame.GetEffectiveScale and targetFrame:GetEffectiveScale()) or 1
        if cdmScale <= 0 then cdmScale = 1 end
        if tgtScale <= 0 then tgtScale = 1 end
        if cdmScale == tgtScale then return math_floor(w + 0.5) end
        return math_floor(w * cdmScale / tgtScale + 0.5)
    end

    local function CP_ApplyTextOffset()
        local fs = CP.text
        local tf = CP.textFrame
        if not fs or not tf then return end
        local b = _cpDB.bars
        local ox = (b and tonumber(b.classPowerTextOffsetX)) or 0
        local oy = (b and tonumber(b.classPowerTextOffsetY)) or 0
        fs:ClearAllPoints()
        fs:SetPoint("CENTER", tf, "CENTER", ox, oy)
    end

    local function CP_ApplyFont()
        local fs = CP.text
        if not fs then return end

        local path, flags, fr, fg, fb, baseSize, useShadow
        if type(_G.MSUF_GetGlobalFontSettings) == "function" then
            path, flags, fr, fg, fb, baseSize, useShadow = _G.MSUF_GetGlobalFontSettings()
        end
        path     = path or "Fonts\\FRIZQT__.TTF"
        flags    = flags or "OUTLINE"
        fr       = fr or 1
        fg       = fg or 1
        fb       = fb or 1
        baseSize = baseSize or 14

        local fontSize = baseSize
        if _cpDB.bars then
            fontSize = _cpDB.fontSize or baseSize
        end
        if fontSize < 6 then fontSize = 6 end

        local rev = (_G.MSUF_FontPathSerial or 0) + fontSize * 1000003
        if _cpFontRev ~= rev then
            fs:SetFont(path, fontSize, flags)
            _cpFontRev = rev
        end

        local runeSize = fontSize - 2
        if runeSize < 6 then runeSize = 6 end
        for i = 1, (CP.maxBars or 0) do
            local bar = CP.bars[i]
            local rfs = bar and bar._runeText
            if rfs then
                rfs:SetFont(path, runeSize, flags)
            end
        end

        local tr, tg, tb = fr, fg, fb
        if _cpDB.general then
            local ov = _cpDB.colorOverrides
            if type(ov) == "table" then
                local c = ov["RESOURCE_TEXT"]
                if type(c) == "table" then
                    local cr = c[1] or c.r
                    local cg = c[2] or c.g
                    local cb = c[3] or c.b
                    if type(cr) == "number" and type(cg) == "number" and type(cb) == "number" then
                        tr, tg, tb = cr, cg, cb
                    end
                end
            end
        end

        fs:SetTextColor(tr, tg, tb, 1)

        if useShadow then
            fs:SetShadowColor(0, 0, 0, 1)
            fs:SetShadowOffset(1, -1)
        else
            fs:SetShadowOffset(0, 0)
        end
        CP_ApplyTextOffset()
    end

    local function CP_ApplyColors(powerType)
        local updateFn = GetUpdateFn and GetUpdateFn() or nil
        if type(updateFn) == "function" then
            updateFn(powerType, CP.currentMax)
        end
    end

    local function CP_RefreshTexture()
        local b = _cpDB.bars or {}
        local fgKey = b.classPowerTexture
        local bgKey = b.classPowerBgTexture

        local fgPath = CP_ResolveTexture(fgKey)
        local bgPath
        if bgKey and bgKey ~= "" then
            local resolve = _G.MSUF_ResolveStatusbarTextureKey
            bgPath = (type(resolve) == "function" and resolve(bgKey)) or fgPath
        else
            bgPath = fgPath
        end

        for i = 1, CP.maxBars do
            local bar = CP.bars[i]
            if bar then
                bar:SetStatusBarTexture(fgPath)
                if bar._bg then bar._bg:SetTexture(bgPath) end
            end
        end
        if CP.bgTex then CP.bgTex:SetTexture(bgPath) end
    end

    return {
        CDM_GetScaledWidth = CDM_GetScaledWidth,
        CP_ApplyTextOffset = CP_ApplyTextOffset,
        CP_ApplyFont = CP_ApplyFont,
        CP_ApplyColors = CP_ApplyColors,
        CP_RefreshTexture = CP_RefreshTexture,
    }
end
