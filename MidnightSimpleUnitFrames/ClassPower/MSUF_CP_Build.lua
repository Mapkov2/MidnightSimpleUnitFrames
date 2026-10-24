local _, MSUF = ...
local shared = MSUF.CPFactoryShared.Core
local builders = shared.builders
local PixelLayoutRegion = shared.PixelLayoutRegion
local CP_ResolveTextLayerLevel = shared.CP_ResolveTextLayerLevel
local type = shared.type
local math_max = shared.math_max
local tonumber = shared.tonumber
local CP_LevelOffset = shared.CP_LevelOffset
local CP_ResolveBarPaths = shared.CP_ResolveBarPaths
local SetRoundLayoutToNearestPixel = MSUF.Require("MSUF_SetRoundLayoutToNearestPixel", "ClassPower/MSUF_CP_Build.lua")

builders.BUILD = function(E)
    --- Bound once by BUILD at controller load.
    local CP, _cpDB, CreateFrame, CP_ResolveTexture

    local function CP_EnsureTextFrame()
        if CP.textFrame then return CP.textFrame end
        local c = CP.container
        if not c then return nil end

        local tf = PixelLayoutRegion(CreateFrame("Frame", nil, c))
        tf:SetAllPoints(c)
        local textLevel = CP_ResolveTextLayerLevel(c, _cpDB.bars)
        tf:SetFrameLevel(textLevel)
        tf._msufFrameLevelStamp = textLevel
        if tf.SetFrameStrata and c.GetFrameStrata then tf:SetFrameStrata(c:GetFrameStrata()) end
        if tf.EnableMouse then tf:EnableMouse(false) end
        CP.textFrame = tf
        return tf
    end

    local function CP_EnsureRuneText(bar)
        if not bar then return nil, false end
        if bar._runeText then return bar._runeText, false end
        local tf = CP_EnsureTextFrame()
        if not tf then return nil, false end

        local rfs = PixelLayoutRegion(tf:CreateFontString(nil, "OVERLAY"))

        rfs:SetPoint("CENTER", bar, "CENTER", 0, 0)
        rfs:SetJustifyH("CENTER")
        if rfs.SetJustifyV then rfs:SetJustifyV("MIDDLE") end
        rfs:SetFontObject("GameFontHighlightSmall")
        rfs:SetTextColor(1, 1, 1, 1)
        rfs:SetShadowColor(0, 0, 0, 1)
        rfs:SetShadowOffset(1, -1)
        rfs:Hide()
        bar._runeText = rfs
        return rfs, true
    end

    local function CP_EnsureMainText()
        if CP.text then return CP.text, false end
        local tf = CP_EnsureTextFrame()
        if not tf then return nil, false end

        local fs = PixelLayoutRegion(tf:CreateFontString(nil, "OVERLAY"))

        fs:SetPoint("CENTER", tf, "CENTER", 0, 0)
        fs:SetJustifyH("CENTER")
        if fs.SetJustifyV then fs:SetJustifyV("MIDDLE") end
        fs:SetFontObject("GameFontHighlightSmall")
        fs:SetTextColor(1, 1, 1, 1)
        fs:SetShadowColor(0, 0, 0, 1)
        fs:SetShadowOffset(1, -1)
        fs:Hide()
        CP.text = fs
        return fs, true
    end

    local function CP_EnsureBars(parent, count)
        if count <= CP.maxBars then return end

        --- Resolve textures once for all new bars. Existing bars are refreshed
        --- by PRESENTATION so this path only pays setup cost for newly needed
        --- resource slots.
        local b = _cpDB.bars or {}
        local fgPath, bgPath = CP_ResolveBarPaths(b, CP_ResolveTexture)

        for i = CP.maxBars + 1, count do
            local bar = PixelLayoutRegion(CreateFrame("StatusBar", nil, CP.container))

            bar:SetStatusBarTexture(fgPath)
            bar._msufCPTexturePath = fgPath
            bar:SetMinMaxValues(0, 1)
            bar._msufCPMin, bar._msufCPMax = 0, 1
            bar:SetValue(0)
            bar._msufCPValue = 0
            bar:Hide()

            local bg = PixelLayoutRegion(bar:CreateTexture(nil, "BACKGROUND"))
            bg:SetAllPoints(bar)
            bg:SetTexture(bgPath)
            bg._msufCPTexturePath = bgPath
            bg:SetVertexColor(0, 0, 0, 0.3)
            bar._bg = bg

            CP.bars[i] = bar
        end

        --- Tick separators (between bars)
        for i = math_max(1, CP.maxBars), count - 1 do
            if not CP.ticks[i] then
                local tick = PixelLayoutRegion(CP.container:CreateTexture(nil, "OVERLAY"))

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

        --- Parent to the player frame so ClassPower follows scale, strata, and
        --- secure visibility rules from the owning unit frame.
        local c = PixelLayoutRegion(CreateFrame("Frame", "MSUF_ClassPowerContainer", playerFrame._msufHealthVisualRoot or playerFrame))
        -- Native pixel rounding (12.1.5); the pips anchor against this rect.
        SetRoundLayoutToNearestPixel(c, true)
        c._msufOwnedAnchorRoot = true
        local b = _cpDB.bars or {}
        local levelOffset = CP_LevelOffset(b.classPowerFrameLevelOffset, 5)
        local layers = MSUF.UF and MSUF.UF.Layers
        c:SetFrameLevel(layers and layers.ElementLevel and layers.ElementLevel(levelOffset, 5, 0)
            or (playerFrame:GetFrameLevel() + levelOffset))
        c:Hide()
        CP.container = c

        --- Background
        local bg = PixelLayoutRegion(c:CreateTexture(nil, "BACKGROUND"))
        bg:SetTexture("Interface\\Buttons\\WHITE8x8")
        bg:SetAllPoints(c)
        bg:SetVertexColor(0, 0, 0, 0.3)
        CP.bgTex = bg

        --- Pre-allocate common max (6 for DK, 5 for most others)
        CP_EnsureBars(playerFrame, 8)

    end

    local API = {
        CP_EnsureBars = CP_EnsureBars,
        CP_Create = CP_Create,
        CP_EnsureRuneText = CP_EnsureRuneText,
        CP_EnsureMainText = CP_EnsureMainText,
    }

        CP, _cpDB = E.CP, E._cpDB
        CreateFrame, CP_ResolveTexture = E.CreateFrame, E.CP_ResolveTexture
    return API
end
