-- Modules/MSUF_PortraitDecoration.lua  (v4)
-- Portrait decoration: borders, backgrounds, size override, offset.
-- Loads AFTER MSUF_3DPortraits.lua.
--
-- v4 fix: position/size is COMPUTED from DB values, never read back from the
-- portrait frame. Eliminates offset compounding entirely.
--
-- Secret-safe. Zero combat cost (stamp-gated).

local addonName, ns = ...

local type, tonumber, tostring, math_max, rawget = type, tonumber, tostring, math.max, rawget
local UnitClassBase  = UnitClassBase or (C_UnitInfo and C_UnitInfo.GetUnitClassBase)
local UnitReaction   = UnitReaction
local RAID_CLASS_COLORS = RAID_CLASS_COLORS

local TEX_WHITE8 = "Interface\\Buttons\\WHITE8x8"
local ADDON_PATH = "Interface\\AddOns\\" .. (addonName or "MidnightSimpleUnitFrames")

local RING_CIRCLE  = ADDON_PATH .. "\\Media\\Borders\\circle_ring_mask.tga"
local SHAPE_RING = { CIRCLE = RING_CIRCLE }

-- Rondo packs have built-in borders → skip our border + shape crop
local RONDO_PACKS = { RONDO_COLOR = true, RONDO_WOW = true }

-- ────────────────────────────────────────────────────────────
-- Scope resolver
-- ────────────────────────────────────────────────────────────
local function R(conf, key, def)
    if conf.portraitDecoOverride == true then
        local v = conf[key]
        if v ~= nil then return v end
    end
    local db = _G.MSUF_DB
    if type(db) == "table" and type(db.general) == "table" then
        local v = db.general[key]
        if v ~= nil then return v end
    end
    local v = conf[key]
    return (v ~= nil) and v or def
end

-- ────────────────────────────────────────────────────────────
-- Stamp (includes ALL visual fields so any change triggers re-apply)
-- ────────────────────────────────────────────────────────────
local function FullStamp(conf)
    return (R(conf,"portraitShape","Q")) .. "|" ..
           (R(conf,"portraitBorderStyle","N")) .. "|" ..
           (R(conf,"portraitBorderThickness",2)) .. "|" ..
           (R(conf,"portraitSizeOverride",0)) .. "|" ..
           (R(conf,"portraitOffsetX",0)) .. "|" ..
           (R(conf,"portraitOffsetY",0)) .. "|" ..
           (R(conf,"portraitBgEnabled",false) and 1 or 0) .. "|" ..
           (R(conf,"portraitBorderColorR",0)) .. "|" ..
           (R(conf,"portraitBorderColorG",0)) .. "|" ..
           (R(conf,"portraitBorderColorB",0)) .. "|" ..
           (R(conf,"portraitBorderColorA",1)) .. "|" ..
           (R(conf,"portraitBgColorR",0.05)) .. "|" ..
           (R(conf,"portraitBgColorG",0.05)) .. "|" ..
           (R(conf,"portraitBgColorB",0.05)) .. "|" ..
           (R(conf,"portraitBgColorA",0.85)) .. "|" ..
           (R(conf,"portraitClassStyle","B")) .. "|" ..
           (R(conf,"portraitFillBorder",false) and 1 or 0) .. "|" ..
           (conf.portraitMode or "X") .. "|" ..
           (conf.height or 0)
end

-- ────────────────────────────────────────────────────────────
-- Lazy decoration frame
-- ────────────────────────────────────────────────────────────
local function EnsureDecor(f)
    local d = f._msufPortraitDecor
    if d then return d end

    -- Background frame (below portrait)
    d = CreateFrame("Frame", nil, f)
    d:SetFrameStrata(f:GetFrameStrata())
    d.bg = d:CreateTexture(nil, "BACKGROUND", nil, -1)
    d.bg:SetTexture(TEX_WHITE8); d.bg:Hide()

    -- Portrait container frame (portrait texture gets reparented here for strata elevation)
    -- This ensures portrait renders ABOVE HP bar, power bar, absorb bars, text, etc.
    d.portraitContainer = CreateFrame("Frame", nil, f)
    d.portraitContainer:SetFrameStrata(f:GetFrameStrata())

    -- Border overlay frame (above portrait container)
    d.borderFrame = CreateFrame("Frame", nil, f)
    d.borderFrame:SetFrameStrata(f:GetFrameStrata())
    d.shapedBorder = d.borderFrame:CreateTexture(nil, "OVERLAY", nil, 3)
    d.shapedBorder:Hide()
    d.edgeT = d.borderFrame:CreateTexture(nil, "OVERLAY", nil, 3)
    d.edgeB = d.borderFrame:CreateTexture(nil, "OVERLAY", nil, 3)
    d.edgeL = d.borderFrame:CreateTexture(nil, "OVERLAY", nil, 3)
    d.edgeR = d.borderFrame:CreateTexture(nil, "OVERLAY", nil, 3)
    local edges = { d.edgeT, d.edgeB, d.edgeL, d.edgeR }
    for i = 1, 4 do edges[i]:SetTexture(TEX_WHITE8); edges[i]:Hide() end
    d._edges = edges

    f._msufPortraitDecor = d
    return d
end

-- ────────────────────────────────────────────────────────────
-- COMPUTE position & size from DB values (never read back from portrait)
-- Mirrors MSUF_UpdateBossPortraitLayout exactly.
-- ────────────────────────────────────────────────────────────
local function ComputeAndApplyLayout(f, conf, portrait)
    local mode = conf.portraitMode or "OFF"
    if mode ~= "LEFT" and mode ~= "RIGHT" then return end

    local d = f._msufPortraitDecor
    local anchor = f.hpBar or f
    if f._msufPowerBarReserved then anchor = f end

    -- Size
    local h = conf.height or (f.GetHeight and f:GetHeight()) or 30
    local autoSize = math_max(16, h - 4)
    local sizeOvr = tonumber(R(conf, "portraitSizeOverride", 0)) or 0
    local size = (sizeOvr > 0) and math_max(16, sizeOvr) or autoSize

    -- Fill Border: portrait grows to include border thickness
    local fillBorder = R(conf, "portraitFillBorder", false)
    local bStyle = R(conf, "portraitBorderStyle", "NONE")
    if fillBorder and bStyle ~= "NONE" then
        local thick = math_max(1, tonumber(R(conf, "portraitBorderThickness", 2)) or 2)
        size = size + (thick * 2)
    end

    local ox = tonumber(R(conf, "portraitOffsetX", 0)) or 0
    local oy = tonumber(R(conf, "portraitOffsetY", 0)) or 0

    -- Frame level hierarchy: portrait renders ABOVE hp bar, absorb, power bar, text.
    -- hpBar = base+1, absorbBar = base+3, textFrame = base+4
    -- bg = base+5, portraitContainer = base+6, borderFrame = base+7
    local baseLevel = f.hpBar and f.hpBar:GetFrameLevel() or (f:GetFrameLevel() + 1)
    if d then
        d:SetFrameLevel(baseLevel + 5)
        if d.portraitContainer then d.portraitContainer:SetFrameLevel(baseLevel + 6) end
        d.borderFrame:SetFrameLevel(baseLevel + 7)
    end

    -- Reparent portrait texture into elevated container (strata fix)
    if d and d.portraitContainer then
        local pc = d.portraitContainer
        if portrait.GetParent and portrait:GetParent() ~= pc then
            portrait:SetParent(pc)
        end
        -- Position the container frame
        pc:ClearAllPoints()
        pc:SetSize(size, size)
        if mode == "LEFT" then
            pc:SetPoint("RIGHT", anchor, "LEFT", ox, oy)
        else
            pc:SetPoint("LEFT", anchor, "RIGHT", ox, oy)
        end
        pc:Show()
        -- Portrait texture fills its container
        portrait:ClearAllPoints()
        portrait:SetAllPoints(pc)
        portrait:SetDrawLayer("ARTWORK", 0)
    else
        -- Fallback before decor exists
        portrait:ClearAllPoints()
        portrait:SetSize(size, size)
        if mode == "LEFT" then
            portrait:SetPoint("RIGHT", anchor, "LEFT", ox, oy)
        else
            portrait:SetPoint("LEFT", anchor, "RIGHT", ox, oy)
        end
    end

    -- 3D model follows container
    local model = rawget(f, "portraitModel")
    if model and model.IsShown and model:IsShown() then
        if model.SetSize then model:SetSize(size, size) end
        local target = (d and d.portraitContainer) or portrait
        if model.ClearAllPoints then
            model:ClearAllPoints()
            if model.SetAllPoints then model:SetAllPoints(target)
            elseif model.SetPoint then model:SetPoint("CENTER", target, "CENTER", 0, 0) end
        end
        if d and d.portraitContainer and model.SetFrameLevel then
            model:SetFrameLevel(d.portraitContainer:GetFrameLevel() + 1)
        end
    end
end

-- ────────────────────────────────────────────────────────────
-- Border color (secret-safe)
-- ────────────────────────────────────────────────────────────
local function ResolveBorderColor(conf, unit)
    local style = R(conf, "portraitBorderStyle", "NONE")
    if style == "NONE" then return nil end
    if style == "CUSTOM" then
        return R(conf,"portraitBorderColorR",1), R(conf,"portraitBorderColorG",1),
               R(conf,"portraitBorderColorB",1), R(conf,"portraitBorderColorA",1)
    end
    if style == "CLASS_COLOR" then
        local class = UnitClassBase and UnitClassBase(unit)
        if class and RAID_CLASS_COLORS then
            local c = RAID_CLASS_COLORS[class]
            if c then return c.r, c.g, c.b, 1 end
        end
        return 1, 1, 1, 1
    end
    if style == "REACTION" then
        local reaction = UnitReaction and UnitReaction(unit, "player")
        if reaction then
            if reaction <= 2 then return 1, 0, 0, 1 end
            if reaction <= 4 then return 1, 0.6, 0, 1 end
            return 0, 1, 0, 1
        end
        return 1, 1, 1, 1
    end
    return 1, 1, 1, 1  -- SOLID
end

-- ────────────────────────────────────────────────────────────
-- Shape TexCoord
-- ────────────────────────────────────────────────────────────
local function ApplyShapeTexCoord(portrait, shape, isRondo)
    if not portrait or not portrait.SetTexCoord then return end
    if isRondo then portrait:SetTexCoord(0, 1, 0, 1); return end
    if shape == "CIRCLE" then
        portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    else
        -- SQUARE (and any unknown): legacy crop
        portrait:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    end
end

-- ────────────────────────────────────────────────────────────
-- Background
-- ────────────────────────────────────────────────────────────
local function ApplyBackground(d, conf, portrait)
    if not R(conf, "portraitBgEnabled", false) then d.bg:Hide(); return end
    d.bg:ClearAllPoints()
    d.bg:SetPoint("TOPLEFT", portrait, "TOPLEFT", -1, 1)
    d.bg:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", 1, -1)
    d.bg:SetVertexColor(
        R(conf,"portraitBgColorR",0.05), R(conf,"portraitBgColorG",0.05),
        R(conf,"portraitBgColorB",0.05), R(conf,"portraitBgColorA",0.85))
    local pLevel = 0
    if portrait.GetParent and portrait:GetParent() and portrait:GetParent().GetFrameLevel then
        pLevel = portrait:GetParent():GetFrameLevel()
    end
    d:SetFrameLevel(math_max(0, pLevel))
    d.bg:SetDrawLayer("BACKGROUND", -1); d.bg:Show()
end

-- ────────────────────────────────────────────────────────────
-- Border
-- ────────────────────────────────────────────────────────────
local function ApplyBorder(d, conf, portrait, shape, r, g, b, a)
    if not r then
        d.shapedBorder:Hide()
        for i = 1, 4 do d._edges[i]:Hide() end
        return
    end
    local thick = math_max(1, tonumber(R(conf, "portraitBorderThickness", 2)) or 2)

    -- Border always outset (outside portrait edges).
    -- When fillBorder is ON, the portrait itself is already enlarged to fill the border area.
    local ringTex = SHAPE_RING[shape]
    if ringTex then
        for i = 1, 4 do d._edges[i]:Hide() end
        d.shapedBorder:SetTexture(ringTex); d.shapedBorder:SetTexCoord(0, 1, 0, 1)
        d.shapedBorder:ClearAllPoints()
        d.shapedBorder:SetPoint("TOPLEFT", portrait, "TOPLEFT", -thick, thick)
        d.shapedBorder:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", thick, -thick)
        d.shapedBorder:SetVertexColor(r, g, b, a); d.shapedBorder:Show()
    else
        d.shapedBorder:Hide()
        local eT, eB, eL, eR = d.edgeT, d.edgeB, d.edgeL, d.edgeR
        eT:ClearAllPoints(); eT:SetPoint("TOPLEFT", portrait, "TOPLEFT", -thick, thick)
        eT:SetPoint("TOPRIGHT", portrait, "TOPRIGHT", thick, thick)
        eT:SetHeight(thick); eT:SetVertexColor(r,g,b,a); eT:Show()
        eB:ClearAllPoints(); eB:SetPoint("BOTTOMLEFT", portrait, "BOTTOMLEFT", -thick, -thick)
        eB:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", thick, -thick)
        eB:SetHeight(thick); eB:SetVertexColor(r,g,b,a); eB:Show()
        eL:ClearAllPoints(); eL:SetPoint("TOPLEFT", portrait, "TOPLEFT", -thick, thick)
        eL:SetPoint("BOTTOMLEFT", portrait, "BOTTOMLEFT", -thick, -thick)
        eL:SetWidth(thick); eL:SetVertexColor(r,g,b,a); eL:Show()
        eR:ClearAllPoints(); eR:SetPoint("TOPRIGHT", portrait, "TOPRIGHT", thick, thick)
        eR:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", thick, -thick)
        eR:SetWidth(thick); eR:SetVertexColor(r,g,b,a); eR:Show()
    end
    local pLevel = 0
    if portrait.GetParent and portrait:GetParent() and portrait:GetParent().GetFrameLevel then
        pLevel = portrait:GetParent():GetFrameLevel()
    end
    d.borderFrame:SetFrameLevel(pLevel + 3)
end

-- ────────────────────────────────────────────────────────────
-- MAIN ENTRY
-- ────────────────────────────────────────────────────────────
local function MSUF_ApplyPortraitDecoration(f, unit, conf, existsForPortrait)
    if not f or not conf then return end
    local portrait = f.portrait
    local mode = conf.portraitMode or "OFF"

    -- OFF gate
    if mode == "OFF" or not portrait then
        local d = f._msufPortraitDecor
        if d then
            d:Hide(); d.bg:Hide(); d.shapedBorder:Hide(); d.borderFrame:Hide()
            if d.portraitContainer then d.portraitContainer:Hide() end
            for i = 1, 4 do d._edges[i]:Hide() end
        end
        return
    end

    if not existsForPortrait then
        local d = f._msufPortraitDecor
        if d then d:Hide(); d.borderFrame:Hide(); if d.portraitContainer then d.portraitContainer:Hide() end end
        return
    end

    -- Stamp gate (single combined stamp)
    -- CRITICAL: also force re-apply if portrait is not in our container.
    -- The parent system (MSUF_Portraits.lua) may reposition portrait directly
    -- after our hook, breaking our container layout. Detect and force re-apply.
    local d_check = f._msufPortraitDecor
    local needsReparent = false
    if d_check and d_check.portraitContainer then
        if portrait.GetParent and portrait:GetParent() ~= d_check.portraitContainer then
            needsReparent = true
        end
    end

    local stamp = FullStamp(conf)
    local uStamp = unit or ""
    if not needsReparent and f._msufDecoStamp == stamp and f._msufDecoUnitStamp == uStamp then return end
    f._msufDecoStamp = stamp
    f._msufDecoUnitStamp = uStamp

    local d = EnsureDecor(f)
    local shape = R(conf, "portraitShape", "SQUARE")
    local render = conf.portraitRender or "2D"
    local isRondo = (render == "CLASS") and RONDO_PACKS[R(conf, "portraitClassStyle", "BLIZZARD")] or false

    -- 1. LAYOUT: compute position + size from DB (never reads back from portrait)
    ComputeAndApplyLayout(f, conf, portrait)

    -- 2. SHAPE
    ApplyShapeTexCoord(portrait, shape, isRondo)

    -- 3. BACKGROUND
    ApplyBackground(d, conf, portrait)

    -- 4. BORDER (skip for Rondo)
    if isRondo then
        d.shapedBorder:Hide()
        for i = 1, 4 do d._edges[i]:Hide() end
    else
        local br, bg_c, bb, ba = ResolveBorderColor(conf, unit)
        ApplyBorder(d, conf, portrait, shape, br, bg_c, bb, ba)
    end

    d:Show(); d.borderFrame:Show()
end

_G.MSUF_ApplyPortraitDecoration = MSUF_ApplyPortraitDecoration
_G.MSUF_IsRondoPortraitPack = function(conf)
    return RONDO_PACKS[R(conf, "portraitClassStyle", "BLIZZARD")] or false
end

-- ────────────────────────────────────────────────────────────
-- Hooks
-- ────────────────────────────────────────────────────────────
local function HookPortraitUpdate()
    if type(_G.MSUF_UpdatePortraitIfNeeded) ~= "function" then return end
    if type(hooksecurefunc) ~= "function" then return end
    hooksecurefunc("MSUF_UpdatePortraitIfNeeded", function(f, unit, conf, existsForPortrait)
        MSUF_ApplyPortraitDecoration(f, unit, conf, existsForPortrait)
    end)
end
HookPortraitUpdate()

local function HookMaybeUpdate()
    if type(_G.MSUF_MaybeUpdatePortrait) ~= "function" then return end
    if type(hooksecurefunc) ~= "function" then return end
    hooksecurefunc("MSUF_MaybeUpdatePortrait", function(f, unit, conf)
        if not f or not conf then return end
        if (conf.portraitMode or "OFF") == "OFF" then
            local d = f._msufPortraitDecor
            if d then d:Hide(); d.borderFrame:Hide(); if d.portraitContainer then d.portraitContainer:Hide() end end
        end
    end)
end
HookMaybeUpdate()

-- ────────────────────────────────────────────────────────────
-- Login/Reload safety: force decoration after all frames are created.
-- Parent portrait system may override our container positioning during
-- initial frame setup. Delayed RefreshAll guarantees decoration is last.
-- ────────────────────────────────────────────────────────────
do
    local loginFrame = CreateFrame("Frame")
    loginFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    loginFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    loginFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
    loginFrame:RegisterEvent("UNIT_PET")
    loginFrame:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
    loginFrame:SetScript("OnEvent", function(self, event, arg1)
        if event == "PLAYER_ENTERING_WORLD" then
            -- Full refresh with delay (frames may not exist yet)
            local function InvalidateAndRefresh()
                local keys = { "player", "target", "focus", "pet", "targettarget" }
                for _, k in ipairs(keys) do
                    local f = _G["MSUF_" .. k]
                    if f then f._msufDecoStamp = nil; f._msufDecoUnitStamp = nil end
                end
                for i = 1, 5 do
                    local f = _G["MSUF_boss" .. i]
                    if f then f._msufDecoStamp = nil; f._msufDecoUnitStamp = nil end
                end
                if type(_G.MSUF_PortraitDecoration_RefreshAll) == "function" then
                    _G.MSUF_PortraitDecoration_RefreshAll()
                end
            end
            if C_Timer and C_Timer.After then
                C_Timer.After(0.1, InvalidateAndRefresh)
                C_Timer.After(0.5, InvalidateAndRefresh)
            end
        elseif event == "PLAYER_TARGET_CHANGED" then
            -- Invalidate target + targettarget so decoration re-applies with new unit
            local f = _G.MSUF_target
            if f then f._msufDecoStamp = nil; f._msufDecoUnitStamp = nil end
            local tot = _G.MSUF_targettarget or _G.MSUF_tot
            if tot then tot._msufDecoStamp = nil; tot._msufDecoUnitStamp = nil end
            -- Small delay: portrait texture updates slightly after event
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    if type(_G.MSUF_PortraitDecoration_SyncUnit) == "function" then
                        _G.MSUF_PortraitDecoration_SyncUnit("target")
                        _G.MSUF_PortraitDecoration_SyncUnit("targettarget")
                    end
                end)
            end
        elseif event == "PLAYER_FOCUS_CHANGED" then
            local f = _G.MSUF_focus
            if f then f._msufDecoStamp = nil; f._msufDecoUnitStamp = nil end
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    if type(_G.MSUF_PortraitDecoration_SyncUnit) == "function" then
                        _G.MSUF_PortraitDecoration_SyncUnit("focus")
                    end
                end)
            end
        elseif event == "UNIT_PET" then
            local f = _G.MSUF_pet
            if f then f._msufDecoStamp = nil; f._msufDecoUnitStamp = nil end
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    if type(_G.MSUF_PortraitDecoration_SyncUnit) == "function" then
                        _G.MSUF_PortraitDecoration_SyncUnit("pet")
                    end
                end)
            end
        elseif event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
            -- Boss frames
            for i = 1, 5 do
                local f = _G["MSUF_boss" .. i]
                if f then f._msufDecoStamp = nil; f._msufDecoUnitStamp = nil end
            end
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    if type(_G.MSUF_PortraitDecoration_SyncUnit) == "function" then
                        _G.MSUF_PortraitDecoration_SyncUnit("boss")
                    end
                end)
            end
        end
    end)
end

-- ────────────────────────────────────────────────────────────
-- Sync helpers
-- ────────────────────────────────────────────────────────────
local function GetFramesForUnitKey(key)
    if key == "tot" then key = "targettarget" end
    if key == "boss" then
        local t = {}
        for i = 1, 5 do local f = _G["MSUF_boss"..i]; if f then t[#t+1] = f end end
        return t
    end
    local f = _G["MSUF_" .. tostring(key)]
    if not f and key == "targettarget" then f = _G.MSUF_targettarget or _G.MSUF_tot end
    return f and { f } or {}
end

function _G.MSUF_PortraitDecoration_SyncUnit(unitKey)
    if type(unitKey) ~= "string" or unitKey == "" then return end
    local db = _G.MSUF_DB; if type(db) ~= "table" then return end
    local conf = (unitKey == "boss") and db.boss or db[unitKey]
    if unitKey == "tot" then conf = db.targettarget or db.tot end
    if type(conf) ~= "table" then return end
    local frames = GetFramesForUnitKey(unitKey)
    for i = 1, #frames do
        local f = frames[i]
        if f then
            -- Invalidate stamp to force full re-apply
            f._msufDecoStamp = nil
            f._msufDecoUnitStamp = nil
            local unit = f.unit or unitKey
            local exists = UnitExists and UnitExists(unit) or false
            MSUF_ApplyPortraitDecoration(f, unit, conf, exists)
        end
    end
end

function _G.MSUF_PortraitDecoration_RefreshAll()
    for _, k in ipairs({"player","target","focus","pet","targettarget"}) do
        _G.MSUF_PortraitDecoration_SyncUnit(k)
    end
    _G.MSUF_PortraitDecoration_SyncUnit("boss")
end
