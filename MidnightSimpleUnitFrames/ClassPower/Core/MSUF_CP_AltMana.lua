-- ============================================================================
-- MSUF_CP_AltMana.lua
-- Phase 7B: move AltMana helpers out of MSUF_ClassPower.lua with minimal risk.
-- No CP value/layout/build flow moved here beyond the isolated AltMana block.
-- ============================================================================

local builders = _G.MSUF_CP_CORE_BUILDERS
if type(builders) ~= "table" then
    builders = {}
    _G.MSUF_CP_CORE_BUILDERS = builders
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
    local tonumber = E.tonumber or tonumber
    local CreateFrame = E.CreateFrame
    local ResolveClassPowerColor = E.ResolveClassPowerColor
    local GetBarTexture = E.GetBarTexture

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
        c:SetFrameLevel(playerFrame:GetFrameLevel() + 2)
        c:Hide()
        AM.container = c

        local bg = c:CreateTexture(nil, "BACKGROUND")
        bg:SetTexture("Interface\Buttons\WHITE8x8")
        bg:SetAllPoints(c)
        bg:SetVertexColor(0, 0, 0, 0.4)
        AM.bgTex = bg

        local border = CreateFrame("Frame", nil, c, "BackdropTemplate")
        border:SetPoint("TOPLEFT", c, "TOPLEFT", -1, 1)
        border:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 1, -1)
        border:SetBackdrop({ edgeFile = "Interface\Buttons\WHITE8x8", edgeSize = 1 })
        border:SetBackdropColor(0, 0, 0, 0)
        border:SetBackdropBorderColor(0, 0, 0, 1)
        border:SetFrameLevel(c:GetFrameLevel() + 1)
        AM._border = border

        local bar = CreateFrame("StatusBar", nil, c)
        bar:SetPoint("TOPLEFT", c, "TOPLEFT", 0, 0)
        bar:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 0, 0)
        bar:SetStatusBarTexture(GetBarTexture and GetBarTexture() or "Interface\Buttons\WHITE8x8")
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
        local oY = tonumber(b.altManaOffsetY) or -2

        AM.container:ClearAllPoints()
        AM.container:SetPoint("TOPLEFT",  playerFrame, "BOTTOMLEFT",   2, oY)
        AM.container:SetPoint("TOPRIGHT", playerFrame, "BOTTOMRIGHT", -2, oY)
        AM.container:SetHeight(h)
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
        if cur == nil then cur = 0 end
        if mx  == nil then mx  = 100 end

        local smoothOn = _cpDB.smooth
        local interp = smoothOn and Enum and Enum.StatusBarInterpolation
            and Enum.StatusBarInterpolation.ExponentialEaseOut or nil
        if interp then
            AM.bar:SetMinMaxValues(0, mx, interp)
            AM.bar:SetValue(cur, interp)
        else
            AM.bar:SetMinMaxValues(0, mx)
            AM.bar:SetValue(cur)
        end
    end

    local function AM_RefreshTexture()
        if not AM.bar then return end
        AM.bar:SetStatusBarTexture(GetBarTexture and GetBarTexture() or "Interface\Buttons\WHITE8x8")
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
