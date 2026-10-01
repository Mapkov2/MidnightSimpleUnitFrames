local PixelLayoutRegion = _G.MSUF_PixelLayoutRegion or function(region, policy, ...) if type(policy) == "string" then return region[policy](region, ...) end return region end
--- Game/Classic/Auras/MSUF_Auras3_Buttons.lua
--- Aura buttons of the Classic scan backend: the per-lane button pool, button
--- layout, tooltips, the cooldown swipe and its countdown colour buckets,
--- stack text, the own-aura highlight, the per-aura dispel type border and
--- symbol, and the per-config button updaters the lanes call for every shown
--- aura. Every write is cached on the button, so an unchanged refresh
--- writes nothing.
---
--- Game/<Flavor>/Auras.xml loads the unit-frame aura backend after Compile.lua
--- in this order: Buttons, Filters, FrameVisuals, Lanes, UnitFrames, Requests.
--- Each file imports the earlier ones from A3._ClassicBackend at load time.
--- This first file claims the backend for the client.
if not (select(2, ...) and select(2, ...).Client and select(2, ...).Client.IsClassic) then return end
local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}
local ExportPublic = MSUF.ExportPublic

local A3 = MSUF.MSUF_Auras3
if type(A3) ~= "table" then
    A3 = {}
    MSUF.MSUF_Auras3 = A3
end

ExportPublic("MSUF_Auras3", A3)

local UF = MSUF.UF
if not (UF and UF.RegisterElement) then return end

if A3.__unitFrameBackendLoaded then return end
A3.__unitFrameBackendLoaded = true

local Compile = A3._ClassicCompile
assert(type(Compile) == "table", "Classic aura backend requires Game/Classic/Auras/MSUF_Auras3_Compile.lua")
local Buttons = {}
A3._ClassicBackend = { Buttons = Buttons }

local type, select = type, select
local math_floor, math_max = math.floor, math.max
local CreateFrame = _G.CreateFrame
local GameTooltip = _G.GameTooltip
local GetTime = _G.GetTime
local InCombatLockdown = _G.InCombatLockdown
local IsSecret = _G.issecretvalue or function() return false end
local C_UnitAuras = _G.C_UnitAuras
local GetAuraDataByIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
local GetAuraApplicationDisplayCount = C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount

local DEFAULT_SHARED = Compile.DEFAULT_SHARED
local PlainNumber = Compile.PlainNumber
local PlainString = Compile.PlainString
local ColorObjectRGBA = Compile.ColorObjectRGBA
local HasSecretColor = Compile.HasSecretColor

local W8 = "Interface\\Buttons\\WHITE8X8"
local DEBUFF_OVERLAY_TEXTURE = "Interface\\Buttons\\UI-Debuff-Overlays"

--- Era/Mists/TBC do not consistently expose tooltip setters by aura instance
--- ID. Resolve the current filtered index only on mouseover; this never adds
--- work to UNIT_AURA or the render path.
local function AuraIndexByInstanceID(unit, auraInstanceID, filter)
    if not (GetAuraDataByIndex and auraInstanceID) then return nil end
    local index = 1
    local data = GetAuraDataByIndex(unit, index, filter)
    while data do
        if data.auraInstanceID == auraInstanceID then return index end
        index = index + 1
        data = GetAuraDataByIndex(unit, index, filter)
    end
    return nil
end

local function OnAuraEnter(button)
    if not (button and button:IsVisible() and GameTooltip and not GameTooltip:IsForbidden()) then return end
    local lane = button._msufA3Lane
    if not (lane and lane.config and lane.config.showTooltip and button.auraInstanceID) then return end
    GameTooltip:SetOwner(button, "ANCHOR_CURSOR")
    if button._msufA3WeaponEnchantSlot then
        if GameTooltip.SetInventoryItem then GameTooltip:SetInventoryItem("player", button._msufA3WeaponEnchantSlot) end
        return
    end
    local filter = lane.config.filter
    if GameTooltip.SetUnitAuraByAuraInstanceID then
        GameTooltip:SetUnitAuraByAuraInstanceID(lane.unit, button.auraInstanceID)
    elseif lane.config.harmful ~= true and GameTooltip.SetUnitBuffByAuraInstanceID then
        GameTooltip:SetUnitBuffByAuraInstanceID(lane.unit, button.auraInstanceID, filter)
    elseif lane.config.harmful == true and GameTooltip.SetUnitDebuffByAuraInstanceID then
        GameTooltip:SetUnitDebuffByAuraInstanceID(lane.unit, button.auraInstanceID, filter)
    else
        local index = AuraIndexByInstanceID(lane.unit, button.auraInstanceID, filter)
        if index and lane.config.harmful ~= true and GameTooltip.SetUnitBuff then
            GameTooltip:SetUnitBuff(lane.unit, index, filter)
        elseif index and lane.config.harmful == true and GameTooltip.SetUnitDebuff then
            GameTooltip:SetUnitDebuff(lane.unit, index, filter)
        elseif index and GameTooltip.SetUnitAura then
            GameTooltip:SetUnitAura(lane.unit, index, filter)
        end
    end
end

local function OnAuraLeave()
    if GameTooltip and not GameTooltip:IsForbidden() then GameTooltip:Hide() end
end

local function ApplyFont(fs, size)
    if not fs then return end
    local fontPath, fontFlags, r, g, b, _, useShadow
    local gfs = _G.MSUF_GetGlobalFontSettings
    if type(gfs) == "function" then
        fontPath, fontFlags, r, g, b, _, useShadow = gfs()
    end
    fontPath = fontPath or _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    fontFlags = fontFlags or "OUTLINE"
    if fs.SetFont then fs:SetFont(fontPath, size or 14, fontFlags) end
    if fs.SetTextColor then fs:SetTextColor(r or 1, g or 1, b or 1, 1) end
    if fs.SetShadowOffset then
        if useShadow then fs:SetShadowOffset(1, -1) else fs:SetShadowOffset(0, 0) end
    end
end

local function PlaceStackText(fs, button, cfg)
    if not (fs and button and cfg) then return end
    fs:ClearAllPoints()
    if cfg.stackAnchor == "TOPLEFT" then
        fs:SetPoint("TOPLEFT", button, "TOPLEFT", cfg.stackX, cfg.stackY)
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("TOP")
    elseif cfg.stackAnchor == "BOTTOMLEFT" then
        fs:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", cfg.stackX, cfg.stackY)
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("BOTTOM")
    elseif cfg.stackAnchor == "BOTTOMRIGHT" then
        fs:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", cfg.stackX, cfg.stackY)
        fs:SetJustifyH("RIGHT")
        fs:SetJustifyV("BOTTOM")
    else
        fs:SetPoint("TOPRIGHT", button, "TOPRIGHT", cfg.stackX, cfg.stackY)
        fs:SetJustifyH("RIGHT")
        fs:SetJustifyV("TOP")
    end
end

local function PositionButton(lane, button, index)
    local cfg = lane.config
    local perRow = cfg.perRow > 0 and cfg.perRow or 1
    local idx = index - 1
    local col, row
    if cfg.verticalGrowth == true then
        row = idx % perRow
        col = (idx - row) / perRow
    else
        col = idx % perRow
        row = (idx - col) / perRow
    end
    local padding = cfg.padding or 0
    local x = (padding + col * (cfg.stepX or cfg.step)) * cfg.xSign
    local y = (padding + row * (cfg.stepY or cfg.step)) * cfg.ySign
    button:ClearAllPoints()
    button:SetPoint(cfg.initialAnchor, lane.frame, cfg.initialAnchor, x, y)
end

local CooldownTextRegion
local ResetCooldownTextColor

local function CooldownTextLayoutCustom(cfg)
    if not cfg then return false end
    if (cfg.cooldownSize or DEFAULT_SHARED.cooldownTextSize) ~= DEFAULT_SHARED.cooldownTextSize then return true end
    if (cfg.cooldownX or 0) ~= 0 or (cfg.cooldownY or 0) ~= 0 then return true end
    return cfg.cooldownAnchor ~= nil and cfg.cooldownAnchor ~= "CENTER"
end

local function ApplyCooldownTextLayout(cooldown, button, cfg)
    if not (cooldown and button and cfg) then return end
    local custom = CooldownTextLayoutCustom(cfg)
    local fs = cooldown._msufA3TextRegion
    if not custom and not fs then return end
    fs = fs or (CooldownTextRegion and CooldownTextRegion(cooldown))
    if not fs then return end

    if fs.GetFont and not fs._msufA3BaseFont then
        fs._msufA3BaseFont, fs._msufA3BaseSize, fs._msufA3BaseFlags = fs:GetFont()
    end

    if fs.SetFont then
        local font = fs._msufA3BaseFont
        local size = custom and (cfg.cooldownSize or DEFAULT_SHARED.cooldownTextSize) or fs._msufA3BaseSize
        local flags = fs._msufA3BaseFlags
        if font and size and fs._msufA3AppliedSize ~= size then
            fs:SetFont(font, size, flags or "")
            fs._msufA3AppliedSize = size
        end
    end

    if fs.ClearAllPoints and fs.SetPoint then
        local anchor = custom and (cfg.cooldownAnchor or "CENTER") or "CENTER"
        local x = custom and (cfg.cooldownX or 0) or 0
        local y = custom and (cfg.cooldownY or 0) or 0
        if fs._msufA3Anchor ~= anchor or fs._msufA3X ~= x or fs._msufA3Y ~= y then
            fs:ClearAllPoints()
            fs:SetPoint(anchor, button, anchor, x, y)
            fs._msufA3Anchor, fs._msufA3X, fs._msufA3Y = anchor, x, y
        end
    end
end

local function ApplyButtonLayout(lane, button, index)
    local cfg = lane.config
    if not cfg then return end
    button._msufA3Lane = lane
    button:SetSize(cfg.buttonWidth or cfg.size, cfg.buttonHeight or cfg.size)
    -- A Classic aura button has no click action and covers part of the secure
    -- unit button it sits on, so its clicks always pass through to that unit
    -- button (targeting, click-casting, menus), as on Retail's native aura
    -- buttons. Hover stays independent so the tooltip setting still works.
    if button.SetMouseClickEnabled and button.SetMouseMotionEnabled then
        button:SetMouseClickEnabled(false)
        button:SetMouseMotionEnabled(cfg.showTooltip == true)
    else
        button:EnableMouse(cfg.showTooltip == true)
    end
    if button.Cooldown then
        if button.Cooldown.SetDrawSwipe then button.Cooldown:SetDrawSwipe(cfg.showCooldown == true and cfg.showCooldownSwipe ~= false) end
        if button.Cooldown.SetHideCountdownNumbers then button.Cooldown:SetHideCountdownNumbers(cfg.showCooldownText == false) end
        if button.Cooldown.SetCountdownMillisecondsThreshold then
            button.Cooldown:SetCountdownMillisecondsThreshold(cfg.cooldownDecimalSeconds or 0)
        end
        ApplyCooldownTextLayout(button.Cooldown, button, cfg)
        if cfg.cooldownTextBuckets ~= true and ResetCooldownTextColor then
            ResetCooldownTextColor(button.Cooldown)
        end
        if button.Cooldown.SetSwipeColor then
            if cfg.cooldownSwipeDarken == true then
                button.Cooldown:SetSwipeColor(0, 0, 0, 0.78)
            else
                button.Cooldown:SetSwipeColor(0, 0, 0, 0.55)
            end
        end
        if cfg.showCooldown ~= true then
            button.Cooldown:Hide()
            button._msufA3CooldownShown = nil
        end
    end
    if button.Count then
        if cfg.showStacks == false then
            button.Count:Hide()
        else
            button.Count:Show()
            ApplyFont(button.Count, cfg.stackSize)
            PlaceStackText(button.Count, button, cfg)
            if button.Count.SetTextColor then
                button.Count:SetTextColor(cfg.stackR or 1, cfg.stackG or 1, cfg.stackB or 1, 1)
            end
        end
    end
    if cfg.showDispelTypeBorder ~= true and button._msufA3DispelOverlay then
        button._msufA3DispelOverlay._msufA3Shown = nil
        button._msufA3DispelOverlay:Hide()
    end
    if cfg.showDispelTypeSymbol ~= true and button._msufA3DispelTypeSymbol then
        button._msufA3DispelTypeSymbol:Hide()
    end
    if cfg.ownHighlight ~= true and button._msufA3OwnHighlight then
        button._msufA3OwnHighlight._msufA3Shown = nil
        button._msufA3OwnHighlight:Hide()
    end
    PositionButton(lane, button, index)
    local visuals = A3.ClassicVisuals
    if visuals and type(visuals.ApplyButtonLayout) == "function" then
        visuals.ApplyButtonLayout(lane, button)
    end
end

local function CreateAuraButton(lane, index)
    local button = PixelLayoutRegion(CreateFrame("Button", nil, lane.frame))
    local icon = PixelLayoutRegion(button:CreateTexture(nil, "BORDER"))
    icon:SetAllPoints()
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    button.Icon = icon

    local cooldown = PixelLayoutRegion(CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate"))
    cooldown:SetAllPoints()
    if cooldown.SetDrawEdge then cooldown:SetDrawEdge(false) end
    if cooldown.SetReverse then cooldown:SetReverse(true) end
    button.Cooldown = cooldown

    local textLayer = PixelLayoutRegion(CreateFrame("Frame", nil, button))
    textLayer:SetAllPoints(button)
    if cooldown.GetFrameLevel and textLayer.SetFrameLevel then
        textLayer:SetFrameLevel(cooldown:GetFrameLevel() + 1)
    end
    local count = PixelLayoutRegion(textLayer:CreateFontString(nil, "OVERLAY", "NumberFontNormal"))
    button.Count = count

    button:SetScript("OnEnter", OnAuraEnter)
    button:SetScript("OnLeave", OnAuraLeave)
    ApplyButtonLayout(lane, button, index)
    button:Hide()

    lane[index] = button
    lane.createdButtons = index
    if type(lane.PostCreateButton) == "function" then
        lane:PostCreateButton(button)
    end
    return button
end

local function EnsureButton(lane, index)
    return lane[index] or CreateAuraButton(lane, index)
end

--- Button pools and lane state are runtime-owned. Config may change the desired
--- max/layout, but live buttons stay attached to their lane so delta updates can
--- reuse them without creating frames during combat.
-- Pre-create the visible button pool for single unit frames while out of
-- combat, so the first swap onto an aura-heavy target never pays a burst of
-- CreateFrame calls mid-fight. Group frames keep the lazy path: their pools
-- are per-member, so eager prewarm would multiply login/reload cost across the
-- raid. If group creation spikes regress, fix them with a budgeted render queue
-- instead of creating every member's buttons up front.
local function PrewarmLaneButtons(lane, frame)
    local cfg = lane.config
    if not cfg then return end
    if frame and frame._msufA3GroupRuntime == true then return end
    local want = cfg.max or 0
    if want <= (lane.createdButtons or 0) then return end
    if InCombatLockdown and InCombatLockdown() then return end
    for i = (lane.createdButtons or 0) + 1, want do
        EnsureButton(lane, i)
    end
end

--- The aura's dispel type colour: the compiled per-type colour (profile
--- overrides included), else Blizzard's DebuffTypeColor. An untyped debuff
--- takes the None colour, as Blizzard's Classic AuraUtil.SetAuraBorderColor
--- paints it (DEBUFF_DISPLAY_INFO.None). A plain lookup by the public
--- dispelName that never writes into the AuraData, which UNIT_AURA shares
--- with every other listener.
local function AuraDispelColor(cfg, unit, data)
    local raw = data and data.dispelName
    local name = PlainString(raw)
    if raw == nil or name == "" then
        name = "None"
    elseif not name then
        return false
    end
    local colors = cfg and cfg.dispelTypeColors
    local color = colors and colors[name]
    if color then return true, color[1], color[2], color[3], 1, false end
    color = _G.DebuffTypeColor and (_G.DebuffTypeColor[name] or (name == "None" and _G.DebuffTypeColor.none))
    if color then
        local r, g, b, a = ColorObjectRGBA(color)
        if r then return true, r, g, b, a or 1, HasSecretColor(r, g, b, a) end
    end
    return false
end

local function RemainingTime(data)
    local expirationTime = PlainNumber(data and data.expirationTime)
    if not (expirationTime and expirationTime > 0 and GetTime) then return nil end
    local remaining = expirationTime - GetTime()
    if remaining < 0 then remaining = 0 end
    return remaining
end

local function ShowButton(button)
    if button._msufA3Shown ~= true then
        button._msufA3Shown = true
        button:Show()
    end
end

local function HideButton(button)
    local visuals = A3.ClassicVisuals
    if visuals and type(visuals.HideButtonVisual) == "function" then visuals.HideButtonVisual(button) end
    -- ClearLane intentionally invalidates auraInstanceID before reaching this
    -- helper. Always hide here so a stale/missing visibility marker cannot
    -- leave a pooled Classic aura button visible after its container is off.
    button._msufA3Shown = nil
    button:Hide()
end

--- cfg and expiration: the countdown's lane config and its aura's expiration
--- while it can still cross a colour bucket; nil, nil untracks it.
local function TrackCooldownBucket(cooldown, cfg, expiration)
    cooldown._msufA3BucketConfig, cooldown._msufA3BucketExpiration = cfg, expiration
    local visuals = A3.ClassicVisuals
    if visuals and visuals.TrackCooldownBucket then visuals.TrackCooldownBucket(cooldown, cfg ~= nil) end
end

local function ShowCooldown(button, cooldown)
    if button._msufA3CooldownShown ~= true then
        button._msufA3CooldownShown = true
        cooldown:Show()
    end
end

local function HideCooldown(button, cooldown)
    if button._msufA3CooldownShown ~= nil then
        button._msufA3CooldownShown = nil
        if cooldown.Clear then cooldown:Clear() end
        cooldown:Hide()
    end
    if cooldown._msufA3BucketConfig then TrackCooldownBucket(cooldown, nil, nil) end
end

local function EnsureOwnHighlight(button)
    local tex = button._msufA3OwnHighlight
    if tex then return tex end
    tex = PixelLayoutRegion(button:CreateTexture(nil, "OVERLAY"))
    tex:SetTexture(W8)
    tex:SetAllPoints(button)
    tex:SetBlendMode("ADD")
    tex:Hide()
    button._msufA3OwnHighlight = tex
    return tex
end

local function EnsureDispelTypeOverlay(button)
    local tex = button._msufA3DispelOverlay
    if tex then return tex end
    tex = PixelLayoutRegion(button:CreateTexture(nil, "OVERLAY"))
    tex:SetTexture(DEBUFF_OVERLAY_TEXTURE)
    tex:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
    tex:SetAllPoints(button)
    tex:Hide()
    button._msufA3DispelOverlay = tex
    return tex
end

local function EnsureDispelTypeSymbol(button)
    local tex = button and button._msufA3DispelTypeSymbol
    if tex then return tex end
    if not button then return nil end
    tex = PixelLayoutRegion(button:CreateTexture(nil, "OVERLAY", nil, 6))
    tex:Hide()
    button._msufA3DispelTypeSymbol = tex
    return tex
end

local function UpdateDispelTypeSymbol(button, cfg, data)
    local tex = button and button._msufA3DispelTypeSymbol
    local dispelName = cfg and cfg.showDispelTypeSymbol == true and PlainString(data and data.dispelName) or nil
    local visuals = A3.ClassicVisuals
    if not (dispelName and visuals and type(visuals.SetDispelSymbolArt) == "function") then
        if tex then tex:Hide() end
        return false
    end
    tex = tex or EnsureDispelTypeSymbol(button)
    if not (tex and visuals.SetDispelSymbolArt(tex, "BLIZZARD", dispelName)) then
        if tex then tex:Hide() end
        return false
    end
    local size = math_max(8, math_floor(((cfg.size or 24) * 0.44) + 0.5))
    tex:ClearAllPoints()
    tex:SetSize(size, size)
    tex:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 1, -1)
    tex:Show()
    return true
end

local function UpdateDispelTypeOverlay(button, lane, unit, data)
    local cfg = lane and lane.config
    if not (cfg and cfg.showDispelTypeBorder == true) then
        local tex = button and button._msufA3DispelOverlay
        if tex and tex._msufA3Shown ~= nil then
            tex._msufA3Shown = nil
            tex:Hide()
        end
        UpdateDispelTypeSymbol(button, cfg, nil)
        return
    end
    local hasColor, r, g, b, a, secret = AuraDispelColor(cfg, unit, data)
    local tex = button._msufA3DispelOverlay
    if hasColor then
        tex = tex or EnsureDispelTypeOverlay(button)
        -- Geometry only, and only when the lane's shape or size changed. Nothing
        -- here may colour or show the texture: both are cached below, and the
        -- preview helper's sample colour, written behind that cache, survived
        -- every later repaint of the same dispel type.
        local shape, size = cfg.iconShape or "RECTANGLE", cfg.size
        if tex._msufA3BorderShape ~= shape or tex._msufA3BorderSize ~= size then
            local shaped = type(A3.ApplyAuraDispelShape) == "function"
                and A3.ApplyAuraDispelShape(tex, button.Icon or button, size, shape) == true
            if not shaped then
                tex:SetTexture(DEBUFF_OVERLAY_TEXTURE)
                if tex.SetTexCoord then tex:SetTexCoord(0.296875, 0.5703125, 0, 0.515625) end
                tex:ClearAllPoints()
                tex:SetAllPoints(button)
            end
            tex._msufA3BorderShape, tex._msufA3BorderSize = shape, size
        end
        r, g, b, a = r or 1, g or 1, b or 1, a or 1
        if secret == true or tex._msufA3ColorPlain ~= true
            or tex._msufA3R ~= r or tex._msufA3G ~= g
            or tex._msufA3B ~= b or tex._msufA3A ~= a then
            tex:SetVertexColor(r, g, b, a)
            if secret == true then
                tex._msufA3ColorPlain = nil
            else
                tex._msufA3ColorPlain = true
                tex._msufA3R, tex._msufA3G, tex._msufA3B, tex._msufA3A = r, g, b, a
            end
        end
        if tex._msufA3Shown ~= true then
            tex._msufA3Shown = true
            tex:Show()
        end
    elseif tex then
        if tex._msufA3Shown ~= nil then
            tex._msufA3Shown = nil
            tex:Hide()
        end
    end
    UpdateDispelTypeSymbol(button, cfg, data)
end

local function UpdateOwnHighlight(button, cfg, mine)
    local active = cfg and cfg.ownHighlight == true and mine == true
    local tex = button._msufA3OwnHighlight
    if active then
        tex = EnsureOwnHighlight(button)
        local r, g, b, a = cfg.ownR or 1, cfg.ownG or 1, cfg.ownB or 1, 0.24
        if tex._msufA3ColorPlain ~= true
            or tex._msufA3R ~= r or tex._msufA3G ~= g
            or tex._msufA3B ~= b or tex._msufA3A ~= a then
            tex:SetVertexColor(r, g, b, a)
            tex._msufA3ColorPlain = true
            tex._msufA3R, tex._msufA3G, tex._msufA3B, tex._msufA3A = r, g, b, a
        end
        if tex._msufA3Shown ~= true then
            tex._msufA3Shown = true
            tex:Show()
        end
    elseif tex then
        if tex._msufA3Shown ~= nil then
            tex._msufA3Shown = nil
            tex:Hide()
        end
    end
end

--- remaining: seconds left, nil for an untimed aura.
local function CooldownTextRGB(cfg, remaining)
    if not (cfg and cfg.cooldownTextBuckets == true) then
        return cfg and cfg.cooldownSafeR or 1, cfg and cfg.cooldownSafeG or 1, cfg and cfg.cooldownSafeB or 1
    end
    if not remaining then
        return cfg.cooldownSafeR or 1, cfg.cooldownSafeG or 1, cfg.cooldownSafeB or 1
    end
    if remaining <= (cfg.cooldownUrgentSeconds or 5) then
        return cfg.cooldownUrgentR or 1, cfg.cooldownUrgentG or 0.55, cfg.cooldownUrgentB or 0.10
    end
    if remaining <= (cfg.cooldownWarningSeconds or 15) then
        return cfg.cooldownWarnR or 1, cfg.cooldownWarnG or 0.85, cfg.cooldownWarnB or 0.20
    end
    return cfg.cooldownSafeR or 1, cfg.cooldownSafeG or 1, cfg.cooldownSafeB or 1
end

CooldownTextRegion = function(cooldown)
    if not cooldown then return nil end
    local cached = cooldown._msufA3TextRegion
    if cached and cached.SetTextColor then return cached end
    if not cooldown.GetRegions then return nil end
    for i = 1, cooldown:GetNumRegions() do
        local region = select(i, cooldown:GetRegions())
        if region and region.GetObjectType and region:GetObjectType() == "FontString"
            and region.SetTextColor then
            cooldown._msufA3TextRegion = region
            return region
        end
    end
    return nil
end

local function MarkCooldownTextColor(cooldown, region, r, g, b)
    if region.GetTextColor and not region._msufA3BaseTextR then
        region._msufA3BaseTextR, region._msufA3BaseTextG, region._msufA3BaseTextB, region._msufA3BaseTextA = region:GetTextColor()
    end
    region:SetTextColor(r, g, b, 1)
    region._msufA3ColorApplied = true
    if cooldown then cooldown._msufA3ColorApplied = true end
end

ResetCooldownTextColor = function(cooldown)
    if not (cooldown and cooldown._msufA3ColorApplied == true) then return end
    local region = cooldown._msufA3TextRegion
    if region and region.SetTextColor and region._msufA3ColorApplied == true then
        region:SetTextColor(region._msufA3BaseTextR or 1, region._msufA3BaseTextG or 1, region._msufA3BaseTextB or 1, region._msufA3BaseTextA or 1)
        region._msufA3ColorApplied = nil
    elseif cooldown.SetCooldownTextColor then
        cooldown:SetCooldownTextColor(1, 1, 1, 1)
    elseif cooldown.SetTextColor then
        cooldown:SetTextColor(1, 1, 1, 1)
    end
    cooldown._msufA3ColorApplied = nil
    cooldown._msufA3TextColorPlain = nil
    cooldown._msufA3TextR, cooldown._msufA3TextG, cooldown._msufA3TextB = nil, nil, nil
    if cooldown._msufA3BucketConfig then TrackCooldownBucket(cooldown, nil, nil) end
end

--- Paints one bucket colour on the countdown text, once per change.
local function PaintCooldownTextColor(cooldown, r, g, b)
    if cooldown._msufA3TextColorPlain == true
        and cooldown._msufA3TextR == r
        and cooldown._msufA3TextG == g
        and cooldown._msufA3TextB == b then
        return
    end
    if cooldown.SetCooldownTextColor then
        cooldown:SetCooldownTextColor(r, g, b, 1)
        cooldown._msufA3ColorApplied = true
        cooldown._msufA3TextColorPlain = true
        cooldown._msufA3TextR, cooldown._msufA3TextG, cooldown._msufA3TextB = r, g, b
        return
    end
    if cooldown.SetTextColor then
        cooldown:SetTextColor(r, g, b, 1)
        cooldown._msufA3ColorApplied = true
        cooldown._msufA3TextColorPlain = true
        cooldown._msufA3TextR, cooldown._msufA3TextG, cooldown._msufA3TextB = r, g, b
        return
    end
    local region = CooldownTextRegion(cooldown)
    if region then
        MarkCooldownTextColor(cooldown, region, r, g, b)
        cooldown._msufA3TextColorPlain = true
        cooldown._msufA3TextR, cooldown._msufA3TextG, cooldown._msufA3TextB = r, g, b
    end
end

--- Time alone moves a countdown through the colour buckets, with no aura
--- event. While the aura can still cross a threshold the shared timer driver
--- (Visuals) re-checks it four times a second; the last threshold untracks it.
local function ApplyCooldownTextColor(cooldown, cfg, data)
    if not (cooldown and cfg and cfg.showCooldownText ~= false and cfg.cooldownTextBuckets == true) then return end
    local remaining = RemainingTime(data)
    PaintCooldownTextColor(cooldown, CooldownTextRGB(cfg, remaining))
    if remaining ~= nil and remaining > (cfg.cooldownUrgentSeconds or 5) then
        TrackCooldownBucket(cooldown, cfg, PlainNumber(data.expirationTime))
    elseif cooldown._msufA3BucketConfig then
        TrackCooldownBucket(cooldown, nil, nil)
    end
end

if A3.ClassicVisuals then
    A3.ClassicVisuals.RepaintCooldownBucket = function(cooldown, now)
        local cfg, expiration = cooldown._msufA3BucketConfig, cooldown._msufA3BucketExpiration
        if not (cfg and expiration) then return TrackCooldownBucket(cooldown, nil, nil) end
        local remaining = expiration - now
        if remaining < 0 then remaining = 0 end
        PaintCooldownTextColor(cooldown, CooldownTextRGB(cfg, remaining))
        if remaining <= (cfg.cooldownUrgentSeconds or 5) then TrackCooldownBucket(cooldown, nil, nil) end
    end
end

local function SetIcon(button, icon)
    local tex = button.Icon
    if not tex then return end
    if IsSecret(icon) then
        tex:SetTexture(icon)
        button._msufA3IconPlain = nil
        button._msufA3Icon = nil
        return
    end
    if button._msufA3IconPlain == true and button._msufA3Icon == icon then
        return
    end
    tex:SetTexture(icon)
    button._msufA3Icon = icon
    button._msufA3IconPlain = true
end

local function SetCount(button, text)
    local count = button.Count
    if not count then return end
    if IsSecret(text) then
        count:SetText(text)
        button._msufA3Count = nil
        button._msufA3CountPlain = nil
        return
    end
    text = text or ""
    if button._msufA3CountPlain == true and button._msufA3Count == text then
        return
    end
    count:SetText(text)
    button._msufA3Count = text
    button._msufA3CountPlain = true
end

local UpdateButtonStacks
if GetAuraApplicationDisplayCount then
    UpdateButtonStacks = function(button, unit, data)
        local applications = data.applications
        if not IsSecret(applications) and type(applications) == "number" then
            SetCount(button, applications > 1 and applications or "")
            return
        end
        SetCount(button, GetAuraApplicationDisplayCount(unit, data.auraInstanceID, 2, 999))
    end
else
    UpdateButtonStacks = function(button, unit, data)
        local applications = data.applications
        if not IsSecret(applications) and type(applications) == "number" then
            SetCount(button, applications > 1 and applications or "")
        else
            SetCount(button, "")
        end
    end
end

-- Classic never uses GetAuraDuration/SetCooldownFromDurationObject: no
-- Blizzard UI on any Classic branch exercises that API pair, and on
-- Mists/TBC it painted hour-scale cooldowns (millisecond-scale values read
-- as seconds -- the "1h Renewing Mist" report). Classic aura duration and
-- expiration are plain numbers, so the raw SetCooldown pair that Blizzard's
-- own Classic target frame uses is the only correct path.
-- TimedAura (Hide permanent) may still read LuaDurationObject:IsZero; that is a
-- scale-independent boolean and never feeds a cooldown widget.
local function UpdateCooldown(button, cooldown, unit, data)
    local duration = data.duration
    local expirationTime = data.expirationTime
    if not IsSecret(duration) and not IsSecret(expirationTime)
        and type(duration) == "number" and type(expirationTime) == "number"
        and duration > 0 and expirationTime > 0 then
        local start = expirationTime - duration
        if button._msufA3CooldownPlain ~= true
            or button._msufA3CooldownStart ~= start
            or button._msufA3CooldownDuration ~= duration then
            cooldown:SetCooldown(start, duration)
            button._msufA3CooldownStart = start
            button._msufA3CooldownDuration = duration
            button._msufA3CooldownPlain = true
        end
        ShowCooldown(button, cooldown)
        return
    end

    if button._msufA3CooldownPlain ~= nil then
        button._msufA3CooldownStart = nil
        button._msufA3CooldownDuration = nil
        button._msufA3CooldownPlain = nil
    end
    HideCooldown(button, cooldown)
end

local function UpdateButton(lane, button, unit, data)
    local cfg = lane.config
    button.auraInstanceID = data.auraInstanceID
    button._msufA3WeaponEnchantSlot = data._msufA3WeaponEnchantSlot
    SetIcon(button, data.icon)
    local cooldown = button.Cooldown
    if cooldown and cfg.showCooldown == true then
        UpdateCooldown(button, cooldown, unit, data)
        if cfg.cooldownTextBuckets == true then
            ApplyCooldownTextColor(cooldown, cfg, data)
        end
    elseif cooldown then
        HideCooldown(button, cooldown)
    end
    if cfg.showStacks ~= false then
        UpdateButtonStacks(button, unit, data)
    end
    if cfg.ownHighlight == true or button._msufA3OwnHighlight then
        UpdateOwnHighlight(button, cfg, lane.mine[data.auraInstanceID])
    end
    if cfg.showDispelTypeBorder == true or button._msufA3DispelOverlay then
        UpdateDispelTypeOverlay(button, lane, unit, data)
    end
    ShowButton(button)
end

local function UpdateButtonHeader(lane, button, data)
    button.auraInstanceID = data.auraInstanceID
    button._msufA3WeaponEnchantSlot = data._msufA3WeaponEnchantSlot
    SetIcon(button, data.icon)
end

local function UpdateButtonCooldownOnly(lane, button, unit, data)
    UpdateButtonHeader(lane, button, data)
    UpdateCooldown(button, button.Cooldown, unit, data)
    ShowButton(button)
end

local function UpdateButtonCooldownStacks(lane, button, unit, data)
    UpdateButtonHeader(lane, button, data)
    UpdateCooldown(button, button.Cooldown, unit, data)
    UpdateButtonStacks(button, unit, data)
    ShowButton(button)
end

local function UpdateButtonCooldownBuckets(lane, button, unit, data)
    UpdateButtonHeader(lane, button, data)
    local cooldown = button.Cooldown
    UpdateCooldown(button, cooldown, unit, data)
    ApplyCooldownTextColor(cooldown, lane.config, data)
    ShowButton(button)
end

local function UpdateButtonCooldownBucketsStacks(lane, button, unit, data)
    UpdateButtonHeader(lane, button, data)
    local cooldown = button.Cooldown
    UpdateCooldown(button, cooldown, unit, data)
    ApplyCooldownTextColor(cooldown, lane.config, data)
    UpdateButtonStacks(button, unit, data)
    ShowButton(button)
end

local function UpdateButtonStacksOnly(lane, button, unit, data)
    UpdateButtonHeader(lane, button, data)
    UpdateButtonStacks(button, unit, data)
    ShowButton(button)
end

local function UpdateButtonBasic(lane, button, unit, data)
    UpdateButtonHeader(lane, button, data)
    ShowButton(button)
end

local function BuildButtonUpdater(cfg)
    if not cfg then return UpdateButton end

    local core
    if cfg.showCooldown == true then
        if cfg.cooldownTextBuckets == true and cfg.showCooldownText ~= false then
            core = cfg.showStacks ~= false and UpdateButtonCooldownBucketsStacks or UpdateButtonCooldownBuckets
        else
            core = cfg.showStacks ~= false and UpdateButtonCooldownStacks or UpdateButtonCooldownOnly
        end
    else
        core = cfg.showStacks ~= false and UpdateButtonStacksOnly or UpdateButtonBasic
    end

    local visuals = A3.ClassicVisuals
    if visuals and type(visuals.UpdateButtonVisual) == "function" then
        local rawCore = core
        core = function(lane, button, unit, data)
            rawCore(lane, button, unit, data)
            visuals.UpdateButtonVisual(lane, button, unit, data)
        end
    end

    local own = cfg.ownHighlight == true
    local dispel = cfg.showDispelTypeBorder == true
    if own and dispel then
        return function(lane, button, unit, data)
            core(lane, button, unit, data)
            UpdateOwnHighlight(button, lane.config, lane.mine[data.auraInstanceID])
            UpdateDispelTypeOverlay(button, lane, unit, data)
        end
    elseif own then
        return function(lane, button, unit, data)
            core(lane, button, unit, data)
            UpdateOwnHighlight(button, lane.config, lane.mine[data.auraInstanceID])
        end
    elseif dispel then
        return function(lane, button, unit, data)
            core(lane, button, unit, data)
            UpdateDispelTypeOverlay(button, lane, unit, data)
        end
    end
    return core
end

local function HideTrailingButtons(lane, visibleByID, visible)
    local oldVisible = lane.visible or 0
    if visible >= oldVisible then
        lane.visible = visible
        return
    end
    for i = visible + 1, oldVisible do
        local button = lane[i]
        if button then
            if button.auraInstanceID ~= nil then
                visibleByID[button.auraInstanceID] = nil
            end
            button.auraInstanceID = nil
            HideButton(button)
        end
    end
    lane.visible = visible
end

Buttons.AuraIndexByInstanceID = AuraIndexByInstanceID
Buttons.AuraDispelColor = AuraDispelColor
Buttons.RemainingTime = RemainingTime
Buttons.ApplyButtonLayout = ApplyButtonLayout
Buttons.EnsureButton = EnsureButton
Buttons.PrewarmLaneButtons = PrewarmLaneButtons
Buttons.HideButton = HideButton
Buttons.HideTrailingButtons = HideTrailingButtons
Buttons.UpdateButton = UpdateButton
Buttons.BuildButtonUpdater = BuildButtonUpdater
