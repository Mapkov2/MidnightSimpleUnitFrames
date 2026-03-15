-- ============================================================================
-- MSUF_CP_Build.lua
-- Phase 7C: move Class Power build helpers out of MSUF_ClassPower.lua with
-- minimal risk. Only CP_EnsureBars and CP_Create live here.
-- ============================================================================

local builders = _G.MSUF_CP_CORE_BUILDERS
if type(builders) ~= "table" then
    builders = {}
    _G.MSUF_CP_CORE_BUILDERS = builders
end

builders.BUILD = function(E)
    local CP = E.CP
    local _cpDB = E._cpDB
    local CreateFrame = E.CreateFrame
    local CP_ResolveTexture = E.CP_ResolveTexture

local function CP_EnsureBars(parent, count)
        if count <= CP.maxBars then return end

        -- Resolve textures once for all new bars
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

            -- Per-rune cooldown time text (DK runes only; shown/hidden in CPK.MODE.RUNE_CD)
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

        -- Tick separators (between bars)
        for i = CP.maxBars + 1, count - 1 do
            if not CP.ticks[i] then
                local tick = CP.container:CreateTexture(nil, "OVERLAY")
                tick:SetTexture("Interface\\Buttons\\WHITE8x8")
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
        c:SetFrameLevel(playerFrame:GetFrameLevel() + 5)  -- above hpBar (Unhalted overlay approach)
        c:Hide()
        CP.container = c

        -- Background
        local bg = c:CreateTexture(nil, "BACKGROUND")
        bg:SetTexture("Interface\\Buttons\\WHITE8x8")
        bg:SetAllPoints(c)
        bg:SetVertexColor(0, 0, 0, 0.3)
        CP.bgTex = bg

        -- Pre-allocate common max (6 for DK, 5 for most others)
        CP_EnsureBars(playerFrame, 8)

        -- Text overlay (MRB pattern: separate Frame at elevated level so text
        -- is always above individual bar segments and tick separators)
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

    return {
        CP_EnsureBars = CP_EnsureBars,
        CP_Create = CP_Create,
    }
end
