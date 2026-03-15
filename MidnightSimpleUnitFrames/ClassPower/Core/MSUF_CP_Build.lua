-- Phase 7 CP split: build/text/font helpers for class power core
_G.MSUF_CP_CORE_BUILDERS = _G.MSUF_CP_CORE_BUILDERS or {}

_G.MSUF_CP_CORE_BUILDERS.BUILD = function(env)
    local CP = env.CP
    local _cpDB = env._cpDB
    local CreateFrame = env.CreateFrame
    local CP_ResolveTexture = env.CP_ResolveTexture
    local tonumber = env.tonumber or tonumber
    local type = env.type or type

    local function CP_EnsureBars(parent, count)
        if count <= CP.maxBars then return end
        local b = _cpDB.bars or {}
        local fgPath = CP_ResolveTexture(b.classPowerTexture)
        local bgKey  = b.classPowerBgTexture
        local bgPath
        if bgKey and bgKey ~= "" then
            local resolve = _G.MSUF_ResolveStatusbarTextureKey
            bgPath = (type(resolve) == "function" and resolve(bgKey)) or fgPath
        else
            bgPath = fgPath
        end
        for i = CP.maxBars + 1, count do
            local bar = CreateFrame("StatusBar", nil, CP.container)
            bar:SetStatusBarTexture(fgPath)
            bar:SetMinMaxValues(0, 1)
            bar:SetValue(0)
            bar:Hide()
            local bg = bar:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints(bar)
            bg:SetTexture(bgPath)
            bg:SetVertexColor(0, 0, 0, 0.3)
            bar._bg = bg
            local rfs = bar:CreateFontString(nil, "OVERLAY")
            rfs:SetPoint("CENTER", bar, "CENTER", 0, 0)
            rfs:SetJustifyH("CENTER")
            if rfs.SetJustifyV then rfs:SetJustifyV("MIDDLE") end
            rfs:SetFontObject("GameFontHighlightSmall")
            rfs:SetTextColor(1, 1, 1, 1)
            rfs:SetShadowColor(0, 0, 0, 1)
            rfs:SetShadowOffset(1, -1)
            rfs:Hide()
            bar._runeText = rfs
            bar._runeTextQ = -1
            CP.bars[i] = bar
        end
        for i = CP.maxBars + 1, count - 1 do
            if not CP.ticks[i] then
                local tick = CP.container:CreateTexture(nil, "OVERLAY")
                tick:SetTexture("Interface\Buttons\WHITE8x8")
                tick:SetVertexColor(0, 0, 0, 1)
                tick:Hide()
                CP.ticks[i] = tick
            end
        end
        CP.maxBars = count
    end

    local function CP_Create(playerFrame)
        if CP.container then return end
        local c = CreateFrame("Frame", "MSUF_ClassPowerContainer", playerFrame)
        c:SetFrameLevel(playerFrame:GetFrameLevel() + 5)
        c:Hide()
        CP.container = c
        local bg = c:CreateTexture(nil, "BACKGROUND")
        bg:SetTexture("Interface\Buttons\WHITE8x8")
        bg:SetAllPoints(c)
        bg:SetVertexColor(0, 0, 0, 0.3)
        CP.bgTex = bg
        CP_EnsureBars(playerFrame, 8)
        local tf = CreateFrame("Frame", nil, c)
        tf:SetAllPoints(c)
        tf:SetFrameLevel(c:GetFrameLevel() + 10)
        CP.textFrame = tf
        local fs = tf:CreateFontString(nil, "OVERLAY")
        fs:SetPoint("CENTER", tf, "CENTER", 0, 0)
        fs:SetJustifyH("CENTER")
        if fs.SetJustifyV then fs:SetJustifyV("MIDDLE") end
        fs:SetFontObject("GameFontHighlightSmall")
        fs:SetTextColor(1, 1, 1, 1)
        fs:SetShadowColor(0, 0, 0, 1)
        fs:SetShadowOffset(1, -1)
        fs:Hide()
        CP.text = fs
    end

    local _cpFontRev = 0

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
        path = path or "Fonts\FRIZQT__.TTF"
        flags = flags or "OUTLINE"
        fr = fr or 1
        fg = fg or 1
        fb = fb or 1
        baseSize = baseSize or 14
        local fontSize = baseSize
        if _cpDB.bars then fontSize = _cpDB.fontSize or baseSize end
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
            if rfs then rfs:SetFont(path, runeSize, flags) end
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

    return {
        CP_EnsureBars = CP_EnsureBars,
        CP_Create = CP_Create,
        CP_ApplyTextOffset = CP_ApplyTextOffset,
        CP_ApplyFont = CP_ApplyFont,
    }
end
