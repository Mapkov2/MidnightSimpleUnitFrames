-- Modules/MSUF_PortraitDecoration.lua
-- Portrait decoration: borders, backgrounds, size override, offset, strata elevation.
-- Loads AFTER MSUF_3DPortraits.lua in the TOC.
--
-- Architecture:
--   - portraitContainer frame: reparents portrait texture for strata elevation (above HP/power bars)
--   - ComputeAndApplyLayout: always runs (cheap), asserts size/offset/container after parent layout
--   - Decoration (border, bg, shape): stamp-gated, only updates on settings change
--
-- DB contract: all portrait* keys live on per-unit conf (MSUF_DB[unitKey].*).
--   ScopeSet (Options panel) writes to per-unit directly; no runtime fallback needed.
--
-- Secret-safe. Zero combat cost.

local addonName, ns = ...

local type, tonumber, math_max, rawget = type, tonumber, math.max, rawget
local UnitClassBase = UnitClassBase or (C_UnitInfo and C_UnitInfo.GetUnitClassBase)
local UnitReaction  = UnitReaction
local RAID_CLASS_COLORS = RAID_CLASS_COLORS

local TEX_WHITE8 = "Interface\\Buttons\\WHITE8x8"
local ADDON_PATH = "Interface\\AddOns\\" .. (addonName or "MidnightSimpleUnitFrames")
local RING_CIRCLE = ADDON_PATH .. "\\Media\\Borders\\circle_ring_mask.tga"
local SHAPE_RING  = { CIRCLE = RING_CIRCLE }
local RONDO_PACKS = { RONDO_COLOR = true, RONDO_WOW = true }

-- ────────────────────────────────────────────────────────────
-- Value reader (1 table lookup — ScopeSet writes per-unit directly)
-- ────────────────────────────────────────────────────────────
local function V(conf, key, def)
    local v = conf[key]
    return (v ~= nil) and v or def
end

-- ────────────────────────────────────────────────────────────
-- Decoration stamp (all visual fields)
-- ────────────────────────────────────────────────────────────
local function DecoStamp(conf)
    return V(conf,"portraitShape","Q") .. "|" ..
           V(conf,"portraitBorderStyle","N") .. "|" ..
           V(conf,"portraitBorderThickness",2) .. "|" ..
           V(conf,"portraitBorderColorR",0) .. "|" ..
           V(conf,"portraitBorderColorG",0) .. "|" ..
           V(conf,"portraitBorderColorB",0) .. "|" ..
           V(conf,"portraitBorderColorA",1) .. "|" ..
           (V(conf,"portraitBgEnabled",false) and "1" or "0") .. "|" ..
           V(conf,"portraitBgColorR",0.05) .. "|" ..
           V(conf,"portraitBgColorG",0.05) .. "|" ..
           V(conf,"portraitBgColorB",0.05) .. "|" ..
           V(conf,"portraitBgColorA",0.85) .. "|" ..
           V(conf,"portraitClassStyle","B") .. "|" ..
           (conf.portraitRender or "2D")
end

-- Layout stamp (only position/size relevant fields)
local function LayoutStamp(conf)
    return V(conf,"portraitSizeOverride",0) .. "|" ..
           V(conf,"portraitOffsetX",0) .. "|" ..
           V(conf,"portraitOffsetY",0) .. "|" ..
           (V(conf,"portraitFillBorder",false) and "1" or "0") .. "|" ..
           V(conf,"portraitBorderThickness",2) .. "|" ..
           V(conf,"portraitBorderStyle","N") .. "|" ..
           (conf.portraitMode or "X") .. "|" ..
           (conf.height or 0)
end

-- ────────────────────────────────────────────────────────────
-- Lazy decoration frame
-- ────────────────────────────────────────────────────────────
local function EnsureDecor(f)
    local d = f._msufPortraitDecor
    if d then return d end
    d = CreateFrame("Frame", nil, f)
    d:SetFrameStrata(f:GetFrameStrata())
    d.bg = d:CreateTexture(nil, "BACKGROUND", nil, -1)
    d.bg:SetTexture(TEX_WHITE8); d.bg:Hide()
    d.portraitContainer = CreateFrame("Frame", nil, f)
    d.portraitContainer:SetFrameStrata(f:GetFrameStrata())
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
-- LAYOUT: position, size, container reparent, strata.
-- Runs every hook call but stamp-gated internally.
-- Forces re-apply when portrait parent changed (parent system repositioned it).
-- ────────────────────────────────────────────────────────────
local function ComputeAndApplyLayout(f, conf, portrait)
    local mode = conf.portraitMode or "OFF"
    if mode ~= "LEFT" and mode ~= "RIGHT" then return end

    local d = f._msufPortraitDecor

    -- Layout stamp: skip if nothing layout-relevant changed AND portrait is in container
    local lStamp = LayoutStamp(conf)
    local inContainer = d and d.portraitContainer and portrait.GetParent and portrait:GetParent() == d.portraitContainer
    if inContainer and f._msufLayoutStamp == lStamp then return end
    f._msufLayoutStamp = lStamp

    local anchor = f.hpBar or f
    if f._msufPowerBarReserved then anchor = f end

    local h = conf.height or (f.GetHeight and f:GetHeight()) or 30
    local autoSize = math_max(16, h - 4)
    local sizeOvr = tonumber(V(conf, "portraitSizeOverride", 0)) or 0
    local size = (sizeOvr > 0) and math_max(16, sizeOvr) or autoSize

    if V(conf, "portraitFillBorder", false) and V(conf, "portraitBorderStyle", "NONE") ~= "NONE" then
        local thick = math_max(1, tonumber(V(conf, "portraitBorderThickness", 2)) or 2)
        size = size + (thick * 2)
    end

    local ox = tonumber(V(conf, "portraitOffsetX", 0)) or 0
    local oy = tonumber(V(conf, "portraitOffsetY", 0)) or 0

    -- Strata hierarchy
    local baseLevel = f.hpBar and f.hpBar:GetFrameLevel() or (f:GetFrameLevel() + 1)
    if d then
        d:SetFrameLevel(baseLevel + 5)
        if d.portraitContainer then d.portraitContainer:SetFrameLevel(baseLevel + 6) end
        d.borderFrame:SetFrameLevel(baseLevel + 7)
    end

    -- Reparent portrait into elevated container
    if d and d.portraitContainer then
        local pc = d.portraitContainer
        if portrait.GetParent and portrait:GetParent() ~= pc then
            portrait:SetParent(pc)
        end
        pc:ClearAllPoints(); pc:SetSize(size, size)
        if mode == "LEFT" then pc:SetPoint("RIGHT", anchor, "LEFT", ox, oy)
        else pc:SetPoint("LEFT", anchor, "RIGHT", ox, oy) end
        pc:Show()
        portrait:ClearAllPoints(); portrait:SetAllPoints(pc)
        portrait:SetDrawLayer("ARTWORK", 0)
    else
        portrait:ClearAllPoints(); portrait:SetSize(size, size)
        if mode == "LEFT" then portrait:SetPoint("RIGHT", anchor, "LEFT", ox, oy)
        else portrait:SetPoint("LEFT", anchor, "RIGHT", ox, oy) end
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
    local style = V(conf, "portraitBorderStyle", "NONE")
    if style == "NONE" then return nil end
    if style == "CUSTOM" then
        return V(conf,"portraitBorderColorR",1), V(conf,"portraitBorderColorG",1),
               V(conf,"portraitBorderColorB",1), V(conf,"portraitBorderColorA",1)
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
        local reaction = tonumber(UnitReaction and UnitReaction(unit, "player"))
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
        portrait:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    end
end

-- ────────────────────────────────────────────────────────────
-- Background
-- ────────────────────────────────────────────────────────────
local function ApplyBackground(d, conf, portrait)
    if not V(conf, "portraitBgEnabled", false) then d.bg:Hide(); return end
    d.bg:ClearAllPoints()
    d.bg:SetPoint("TOPLEFT", portrait, "TOPLEFT", -1, 1)
    d.bg:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", 1, -1)
    d.bg:SetVertexColor(V(conf,"portraitBgColorR",0.05), V(conf,"portraitBgColorG",0.05),
                        V(conf,"portraitBgColorB",0.05), V(conf,"portraitBgColorA",0.85))
    local pLevel = (portrait.GetParent and portrait:GetParent() and portrait:GetParent().GetFrameLevel)
        and portrait:GetParent():GetFrameLevel() or 0
    d:SetFrameLevel(math_max(0, pLevel)); d.bg:SetDrawLayer("BACKGROUND", -1); d.bg:Show()
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
    local thick = math_max(1, tonumber(V(conf, "portraitBorderThickness", 2)) or 2)
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
    local pLevel = (portrait.GetParent and portrait:GetParent() and portrait:GetParent().GetFrameLevel)
        and portrait:GetParent():GetFrameLevel() or 0
    d.borderFrame:SetFrameLevel(pLevel + 3)
end

-- ────────────────────────────────────────────────────────────
-- Hide all decoration
-- ────────────────────────────────────────────────────────────
local function HideAllDecor(f)
    local d = f._msufPortraitDecor
    if not d then return end
    d:Hide(); d.bg:Hide(); d.shapedBorder:Hide(); d.borderFrame:Hide()
    if d.portraitContainer then d.portraitContainer:Hide() end
    for i = 1, 4 do d._edges[i]:Hide() end
end

-- ────────────────────────────────────────────────────────────
-- MAIN ENTRY
-- ────────────────────────────────────────────────────────────
local function MSUF_ApplyPortraitDecoration(f, unit, conf, existsForPortrait)
    if not f or not conf then return end
    local portrait = f.portrait
    local mode = conf.portraitMode or "OFF"

    if mode == "OFF" or not portrait then HideAllDecor(f); return end
    if not existsForPortrait then HideAllDecor(f); return end

    local d = EnsureDecor(f)

    -- LAYOUT: always re-assert (parent system may have overridden)
    -- Internally stamp-gated + parent-check for efficiency
    ComputeAndApplyLayout(f, conf, portrait)

    -- DECORATION: stamp-gated (border/bg/shape)
    local stamp = DecoStamp(conf)
    local uStamp = unit or ""
    if f._msufDecoStamp == stamp and f._msufDecoUnitStamp == uStamp then
        d:Show(); d.borderFrame:Show()
        return
    end
    f._msufDecoStamp = stamp
    f._msufDecoUnitStamp = uStamp

    local shape = V(conf, "portraitShape", "SQUARE")
    local render = conf.portraitRender or "2D"
    local isRondo = (render == "CLASS") and RONDO_PACKS[V(conf, "portraitClassStyle", "BLIZZARD")] or false

    ApplyShapeTexCoord(portrait, shape, isRondo)
    ApplyBackground(d, conf, portrait)

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
    return RONDO_PACKS[V(conf, "portraitClassStyle", "BLIZZARD")] or false
end

-- ────────────────────────────────────────────────────────────
-- Hooks
-- ────────────────────────────────────────────────────────────
if type(hooksecurefunc) == "function" then
    -- After portrait rendering (2D/3D/CLASS texture is set)
    if type(_G.MSUF_UpdatePortraitIfNeeded) == "function" then
        hooksecurefunc("MSUF_UpdatePortraitIfNeeded", function(f, unit, conf, exists)
            MSUF_ApplyPortraitDecoration(f, unit, conf, exists)
        end)
    end
    -- After parent layout (ClearAllPoints + SetSize + SetPoint on portrait)
    if type(_G.MSUF_UpdateBossPortraitLayout) == "function" then
        hooksecurefunc("MSUF_UpdateBossPortraitLayout", function(f, conf)
            if not f or not f.portrait or not conf then return end
            if (conf.portraitMode or "OFF") == "OFF" then return end
            -- Invalidate layout stamp so ComputeAndApplyLayout re-asserts
            f._msufLayoutStamp = nil
            ComputeAndApplyLayout(f, conf, f.portrait)
        end)
    end
    -- OFF-gate cleanup
    if type(_G.MSUF_MaybeUpdatePortrait) == "function" then
        hooksecurefunc("MSUF_MaybeUpdatePortrait", function(f, unit, conf)
            if not f or not conf then return end
            if (conf.portraitMode or "OFF") == "OFF" then HideAllDecor(f) end
        end)
    end
end

-- ────────────────────────────────────────────────────────────
-- Event-driven stamp invalidation
-- Ensures decoration is applied/refreshed when units appear/change.
-- ────────────────────────────────────────────────────────────
local function InvalidateFrame(f)
    if not f then return end
    f._msufDecoStamp = nil
    f._msufDecoUnitStamp = nil
    f._msufLayoutStamp = nil
end

local function InvalidateByKey(key)
    if key == "boss" then
        for i = 1, 5 do InvalidateFrame(_G["MSUF_boss" .. i]) end
    else
        InvalidateFrame(_G["MSUF_" .. key])
    end
end

local function InvalidateAll()
    for _, k in ipairs({ "player", "target", "focus", "pet", "targettarget" }) do
        InvalidateByKey(k)
    end
    InvalidateByKey("boss")
end

local function SyncUnitSafe(key)
    local fn = _G.MSUF_PortraitDecoration_SyncUnit
    if type(fn) == "function" then fn(key) end
end

do
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("PLAYER_TARGET_CHANGED")
    ev:RegisterEvent("PLAYER_FOCUS_CHANGED")
    ev:RegisterEvent("UNIT_PET")
    ev:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
    ev:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_ENTERING_WORLD" then
            if C_Timer and C_Timer.After then
                C_Timer.After(0.1, function() InvalidateAll(); if _G.MSUF_PortraitDecoration_RefreshAll then _G.MSUF_PortraitDecoration_RefreshAll() end end)
                C_Timer.After(0.5, function() InvalidateAll(); if _G.MSUF_PortraitDecoration_RefreshAll then _G.MSUF_PortraitDecoration_RefreshAll() end end)
            end
        elseif event == "PLAYER_TARGET_CHANGED" then
            InvalidateByKey("target"); InvalidateByKey("targettarget")
            if C_Timer and C_Timer.After then C_Timer.After(0, function() SyncUnitSafe("target"); SyncUnitSafe("targettarget") end) end
        elseif event == "PLAYER_FOCUS_CHANGED" then
            InvalidateByKey("focus")
            if C_Timer and C_Timer.After then C_Timer.After(0, function() SyncUnitSafe("focus") end) end
        elseif event == "UNIT_PET" then
            InvalidateByKey("pet")
            if C_Timer and C_Timer.After then C_Timer.After(0, function() SyncUnitSafe("pet") end) end
        elseif event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
            InvalidateByKey("boss")
            if C_Timer and C_Timer.After then C_Timer.After(0, function() SyncUnitSafe("boss") end) end
        end
    end)
end

-- ────────────────────────────────────────────────────────────
-- Sync helpers (Options panel live-apply)
-- ────────────────────────────────────────────────────────────
local function GetFramesForUnitKey(key)
    if key == "tot" then key = "targettarget" end
    if key == "boss" then
        local t = {}
        for i = 1, 5 do local f = _G["MSUF_boss"..i]; if f then t[#t+1] = f end end
        return t
    end
    local f = _G["MSUF_" .. (key or "")]
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
            InvalidateFrame(f)
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
