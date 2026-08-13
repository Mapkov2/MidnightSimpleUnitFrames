--- MSUF_CP_AltMana.lua
--- Alt Mana class-power builder. Loaded before the controller so the controller
--- can bind the builder without carrying AltMana implementation details inline.
do
--- MSUF_CP_AltMana.lua
--- MSUF_CP_AltMana.lua
--- Phase 7B: move AltMana helpers out of MSUF_ClassPower.lua with minimal risk.
--- No CP value/layout/build flow moved here beyond the isolated AltMana block.

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

builders.ALT_MANA = function(E)
    local AM = E.AM
    local _cpDB = E._cpDB
    local PT = E.PT
    local PLAYER_CLASS = E.PLAYER_CLASS
    local GetSpec = E.GetSpec
    local NotSecret = E.NotSecret
    local UnitPowerType = E.UnitPowerType
    local UnitPower = E.UnitPower
    local UnitPowerMax = E.UnitPowerMax
    local Enum = E.Enum
    local StatusBarInterpolation = Enum and Enum.StatusBarInterpolation
    local SMOOTH_INTERP = StatusBarInterpolation and StatusBarInterpolation.ExponentialEaseOut or nil
    local tonumber = E.tonumber or tonumber
    local CreateFrame = E.CreateFrame
    local ResolveClassPowerColor = E.ResolveClassPowerColor
    local GetBarTexture = E.GetBarTexture

    local function ApplyRoundedSurface()
        local rounded = MSUF and MSUF.RoundedSurface
        local apply = rounded and rounded.ApplyAltMana
        if type(apply) == "function" then apply(AM) end
    end

    local function NeedsAltManaBar()
        if _G.MSUF_EleMaelstromActive then return false end
        if _G.MSUF_AugEvokerActive then return true end
        if _G.MSUF_ShadowManaActive then return false end
        local pType = UnitPowerType("player")
        if NotSecret(pType) then
            if pType == nil or pType == PT.Mana then return false end
        end
        local maxMana = UnitPowerMax("player", PT.Mana)
        if NotSecret(maxMana) and maxMana ~= nil and maxMana <= 0 then
            return false
        end
        if not NotSecret(pType) then
            local SPECS_NEED_ALT = {
                PRIEST  = { [3] = true },
                SHAMAN  = { [1] = true, [2] = true },
                DRUID   = { [1] = true, [2] = true, [3] = true },
                PALADIN = { [3] = true },
                MONK    = { [3] = true },
            }
            local specs = SPECS_NEED_ALT[PLAYER_CLASS]
            if not specs then return false end
            local si = GetSpec and GetSpec()
            return si and specs[si] or false
        end
        return true
    end

    local function AM_Create(playerFrame)
        if AM.container then return end

        local c = CreateFrame("Frame", "MSUF_AltManaContainer", playerFrame)
        local layers = MSUF.UF and MSUF.UF.Layers
        local layer = _cpDB.bars and _cpDB.bars.classPowerFrameLevelOffset
        c:SetFrameLevel(layers and layers.ElementLevel and layers.ElementLevel(layer, 5, 0)
            or (playerFrame:GetFrameLevel() + 2))
        c:Hide()
        AM.container = c

        local bg = c:CreateTexture(nil, "BACKGROUND")
        bg:SetTexture("Interface\\Buttons\\WHITE8x8")
        bg:SetAllPoints(c)
        bg:SetVertexColor(0, 0, 0, 0.4)
        AM.bgTex = bg

        local border = CreateFrame("Frame", nil, c, "BackdropTemplate")
        border:SetPoint("TOPLEFT", c, "TOPLEFT", -1, 1)
        border:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 1, -1)
        border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        border:SetBackdropColor(0, 0, 0, 0)
        border:SetBackdropBorderColor(0, 0, 0, 1)
        border:SetFrameLevel(c:GetFrameLevel() + 1)
        AM._border = border

        local bar = CreateFrame("StatusBar", nil, c)
        bar:SetPoint("TOPLEFT", c, "TOPLEFT", 0, 0)
        bar:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 0, 0)
        bar:SetStatusBarTexture(GetBarTexture and GetBarTexture() or "Interface\\Buttons\\WHITE8x8")
        bar:SetMinMaxValues(0, 100)
        bar:SetValue(0)
        bar:SetFrameLevel(c:GetFrameLevel() + 1)
        AM.bar = bar
    end

    local function AM_Layout(playerFrame)
        if not AM.container then return end
        local b = _cpDB.bars or {}

        local h = tonumber(b.altManaHeight) or 4
        if h < 2 then h = 2 elseif h > 30 then h = 30 end
        local oX = tonumber(b.altManaOffsetX) or 0
        if oX < -1000 then oX = -1000 elseif oX > 1000 then oX = 1000 end
        local oY = tonumber(b.altManaOffsetY) or -2
        local customW
        if b.altManaWidthMode == "custom" then
            customW = tonumber(b.altManaWidth)
            if customW and customW < 20 then customW = nil end
            if customW and customW > 1200 then customW = 1200 end
        end
        local layers = MSUF.UF and MSUF.UF.Layers
        if AM.container.SetFrameLevel then
            local level = layers and layers.ElementLevel and layers.ElementLevel(b.classPowerFrameLevelOffset, 5, 0)
                or ((playerFrame:GetFrameLevel() or 0) + 2)
            AM.container:SetFrameLevel(level)
            if AM.bar then AM.bar:SetFrameLevel(level + 1) end
            if AM._border then AM._border:SetFrameLevel(level + 2) end
        end

        AM.container:ClearAllPoints()
        if customW then
            AM.container:SetPoint("TOP", playerFrame, "BOTTOM", oX, oY)
            AM.container:SetWidth(customW)
        else
            --- Legacy/default mode remains live-linked to Player width. Applying
            --- the same X delta to both edge anchors moves without resizing.
            AM.container:SetPoint("TOPLEFT",  playerFrame, "BOTTOMLEFT",   2 + oX, oY)
            AM.container:SetPoint("TOPRIGHT", playerFrame, "BOTTOMRIGHT", -2 + oX, oY)
        end
        AM.container:SetHeight(h)
        ApplyRoundedSurface()
    end

    local function AM_ApplyColor()
        if not AM.bar then return end
        local b = _cpDB.bars or {}
        local r = tonumber(b.altManaColorR) or 0.0
        local g = tonumber(b.altManaColorG) or 0.0
        local bl = tonumber(b.altManaColorB) or 0.8

        local mr, mg, mb = ResolveClassPowerColor(PT.Mana)
        if mr then r, g, bl = mr, mg, mb end

        AM.bar:SetStatusBarColor(r, g, bl, 1)
    end

    local function AM_UpdateValue()
        if not AM.bar then return end

        local cur = UnitPower("player", PT.Mana)
        local mx  = UnitPowerMax("player", PT.Mana)
        local curSecret = not NotSecret(cur)
        local maxSecret = not NotSecret(mx)
        if not curSecret and cur == nil then cur = 0 end
        if not maxSecret and mx == nil then mx = 100 end

        local rangeInterp = _cpDB.altManaSmooth and SMOOTH_INTERP or nil
        local valueInterp = rangeInterp
        if maxSecret or AM._maxValue ~= mx then
            if rangeInterp then AM.bar:SetMinMaxValues(0, mx, rangeInterp) else AM.bar:SetMinMaxValues(0, mx) end
            if maxSecret then AM._maxValue = nil else AM._maxValue = mx end
        end
        if curSecret or AM._currentValue ~= cur then
            if valueInterp then AM.bar:SetValue(cur, valueInterp) else AM.bar:SetValue(cur) end
            if curSecret then AM._currentValue = nil else AM._currentValue = cur end
        end
    end

    local function AM_RefreshTexture()
        if not AM.bar then return end
        AM.bar:SetStatusBarTexture(GetBarTexture and GetBarTexture() or "Interface\\Buttons\\WHITE8x8")
        ApplyRoundedSurface()
    end

    return {
        NeedsAltManaBar = NeedsAltManaBar,
        AM_Create = AM_Create,
        AM_Layout = AM_Layout,
        AM_ApplyColor = AM_ApplyColor,
        AM_UpdateValue = AM_UpdateValue,
        AM_RefreshTexture = AM_RefreshTexture,
    }
end
end
