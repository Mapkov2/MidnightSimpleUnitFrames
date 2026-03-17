-- ============================================================================
-- MSUF_CP_EbonMight.lua
-- Secondary Ebon Might timer bar for Augmentation Evoker.
-- Sits below the Essence pips so both resources are visible simultaneously.
-- Modeled after AltMana: independent container, parented to CP.container.
-- Secret-safe: aura.expirationTime is non-secret in 12.0.
-- ============================================================================

local builders = _G.MSUF_CP_CORE_BUILDERS
if type(builders) ~= "table" then
    builders = {}
    _G.MSUF_CP_CORE_BUILDERS = builders
end

builders.EBON_MIGHT = function(E)
    local EB = E.EB
    local _cpDB = E._cpDB
    local EBON = E.EBON
    local CPK = E.CPK
    local PLAYER_CLASS = E.PLAYER_CLASS
    local GetSpec = E.GetSpec
    local C_UnitAuras = E.C_UnitAuras
    local GetTime = E.GetTime
    local CreateFrame = E.CreateFrame
    local ResolveClassPowerColor = E.ResolveClassPowerColor
    local ResolveClassPowerBgColor = E.ResolveClassPowerBgColor
    local GetBarTexture = E.GetBarTexture
    local string_format = string.format
    local math_floor = math.floor
    local tonumber = tonumber

    local _elapsed = 0

    local function NeedsEbonMightBar()
        return PLAYER_CLASS == "EVOKER"
            and GetSpec and GetSpec() == CPK.SPEC.EVOKER_AUG
    end

    local function EB_Create(cpContainer)
        if EB.container then return end

        local c = CreateFrame("Frame", "MSUF_EbonMightContainer", cpContainer)
        c:SetFrameLevel(cpContainer:GetFrameLevel())
        c:Hide()
        EB.container = c

        local bg = c:CreateTexture(nil, "BACKGROUND")
        bg:SetTexture("Interface\\Buttons\\WHITE8x8")
        bg:SetAllPoints(c)
        bg:SetVertexColor(0, 0, 0, 0.4)
        EB.bgTex = bg

        local bar = CreateFrame("StatusBar", nil, c)
        bar:SetPoint("TOPLEFT", c, "TOPLEFT", 0, 0)
        bar:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 0, 0)
        bar:SetStatusBarTexture(GetBarTexture and GetBarTexture() or "Interface\\Buttons\\WHITE8x8")
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(0)
        bar:SetFrameLevel(c:GetFrameLevel() + 1)
        EB.bar = bar

        -- Outline border (matches CP outline style)
        local tpl = (BackdropTemplateMixin and "BackdropTemplate") or nil
        local ol = CreateFrame("Frame", nil, c, tpl)
        ol:EnableMouse(false)
        ol:SetFrameLevel(c:GetFrameLevel() + 2)
        ol:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        ol:SetBackdropBorderColor(0, 0, 0, 1)
        ol:SetPoint("TOPLEFT", c, "TOPLEFT", -1, 1)
        ol:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 1, -1)
        EB._outline = ol

        -- Timer text overlay (elevated frame so text sits above bar)
        local tf = CreateFrame("Frame", nil, c)
        tf:SetAllPoints(c)
        tf:SetFrameLevel(c:GetFrameLevel() + 3)
        local fs = tf:CreateFontString(nil, "OVERLAY")
        fs:SetPoint("CENTER", tf, "CENTER", 0, 0)
        fs:SetJustifyH("CENTER")
        if fs.SetJustifyV then fs:SetJustifyV("MIDDLE") end
        fs:SetFontObject("GameFontHighlightSmall")
        fs:SetTextColor(1, 1, 1, 1)
        fs:SetShadowColor(0, 0, 0, 1)
        fs:SetShadowOffset(1, -1)
        fs:Hide()
        EB.text = fs
        EB.textFrame = tf
    end

    local function EB_Layout(cpContainer)
        if not EB.container then return end
        local b = _cpDB.bars or {}
        local h = tonumber(b.ebonMightHeight) or 4
        if h < 2 then h = 2 elseif h > 30 then h = 30 end
        local oY = tonumber(b.ebonMightOffsetY) or -1

        EB.container:ClearAllPoints()
        EB.container:SetPoint("TOPLEFT", cpContainer, "BOTTOMLEFT", 0, oY)
        EB.container:SetPoint("TOPRIGHT", cpContainer, "BOTTOMRIGHT", 0, oY)
        EB.container:SetHeight(h)

        -- Outline thickness matching CP
        local outlineThick = tonumber(b.classPowerOutline) or 1
        if outlineThick < 0 then outlineThick = 0 elseif outlineThick > 4 then outlineThick = 4 end
        if EB._outline then
            if outlineThick > 0 then
                local snap = _G.MSUF_Snap
                local edge = (type(snap) == "function") and snap(EB.container, outlineThick) or outlineThick
                EB._outline:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = edge })
                EB._outline:SetBackdropBorderColor(0, 0, 0, 1)
                EB._outline:ClearAllPoints()
                EB._outline:SetPoint("TOPLEFT", EB.container, "TOPLEFT", -edge, edge)
                EB._outline:SetPoint("BOTTOMRIGHT", EB.container, "BOTTOMRIGHT", edge, -edge)
                EB._outline:Show()
            else
                EB._outline:Hide()
            end
        end
    end

    local function EB_ApplyFont()
        if not EB.text then return end
        local b = _cpDB.bars or {}
        local fontSize = tonumber(b.classPowerFontSize) or 14
        local fontPath = _G.MSUF_GetFont and _G.MSUF_GetFont() or "Fonts\\FRIZQT__.TTF"
        EB.text:SetFont(fontPath, fontSize, "OUTLINE")
    end

    local function EB_ApplyColor()
        if not EB.bar then return end
        local r, g, bl = ResolveClassPowerColor("EBON_MIGHT")
        EB.bar:SetStatusBarColor(r, g, bl, 1)
        local bgR, bgG, bgB = ResolveClassPowerBgColor("EBON_MIGHT")
        local bgA = tonumber((_cpDB.bars or {}).classPowerBgAlpha) or 0.3
        if EB.bgTex then EB.bgTex:SetVertexColor(bgR, bgG, bgB, bgA) end
    end

    local function EB_UpdateVisual(remaining)
        local mx = EBON.MAX_DURATION
        local pct = remaining / mx
        if pct > 1 then pct = 1 end

        EB.bar:SetMinMaxValues(0, 1)
        EB.bar:SetValue(pct)
        EB.bar:SetAlpha(remaining > 0.05 and 1 or 0.3)

        if EB.text then
            local b = _cpDB.bars or {}
            if b.classPowerShowText == true and remaining > 0.05 then
                EB.text:SetText(string_format("%.1fs", remaining))
                EB.text:Show()
            else
                EB.text:Hide()
            end
        end
    end

    local function EB_OnUpdate(self, dt)
        if not EB.visible then
            self:SetScript("OnUpdate", nil)
            EB.ouActive = false
            return
        end
        _elapsed = _elapsed + dt
        if _elapsed < 0.05 then return end
        _elapsed = 0

        local getAura = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
        local aura = getAura and getAura(EBON.SPELL_ID)
        local remaining = aura and (aura.expirationTime - GetTime()) or 0
        if remaining < 0 then remaining = 0 end

        local qPct = math_floor(remaining * 10 + 0.5)
        if qPct == EB.cachedQ then return end
        EB.cachedQ = qPct

        EB_UpdateVisual(remaining)

        if remaining <= 0.05 then
            self:SetScript("OnUpdate", nil)
            EB.ouActive = false
        end
    end

    local function EB_StartTicking()
        if EB.ouActive or not EB.container then return end
        _elapsed = 0
        EB.container:SetScript("OnUpdate", EB_OnUpdate)
        EB.ouActive = true
    end

    local function EB_StopTicking()
        if not EB.container then return end
        if EB.ouActive then
            EB.container:SetScript("OnUpdate", nil)
            EB.ouActive = false
        end
    end

    -- Called on UNIT_AURA and initial FullRefresh to sync state
    local function EB_OnAuraChanged()
        if not EB.visible or not EB.bar then return end
        local getAura = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
        local aura = getAura and getAura(EBON.SPELL_ID)
        local remaining = aura and (aura.expirationTime - GetTime()) or 0
        if remaining < 0 then remaining = 0 end

        EB.cachedQ = -1
        EB_UpdateVisual(remaining)

        if remaining > 0.05 then
            EB_StartTicking()
        else
            EB_StopTicking()
        end
    end

    local function EB_RefreshTexture()
        if not EB.bar then return end
        EB.bar:SetStatusBarTexture(GetBarTexture and GetBarTexture() or "Interface\\Buttons\\WHITE8x8")
    end

    return {
        NeedsEbonMightBar = NeedsEbonMightBar,
        EB_Create = EB_Create,
        EB_Layout = EB_Layout,
        EB_ApplyFont = EB_ApplyFont,
        EB_ApplyColor = EB_ApplyColor,
        EB_OnAuraChanged = EB_OnAuraChanged,
        EB_StartTicking = EB_StartTicking,
        EB_StopTicking = EB_StopTicking,
        EB_RefreshTexture = EB_RefreshTexture,
    }
end
