--- Rounded surface renderer for MSUF-owned castbars and their previews.
---
--- This module owns no events and no OnUpdate. The existing rounded-frame
--- controller invokes ApplyAll on its deferred/cold apply route; ordinary
--- castbar visual refreshes only rebind masks when their textures changed.
local _, MSUF = ...
MSUF = MSUF or {}

local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end
local RoundedSurface = MSUF.RoundedSurface or {}
local CreateFrame = _G.CreateFrame

local MASK_KEY = "_msufRoundedCastbarMask"
local MASKED_KEY = "_msufRoundedCastbarMasked"
local OUTLINE_STACK_KEY = "_msufRoundedCastbarOutlineStack"
local MAX_OUTLINE = 12

local ClearSurfaceMasks = RoundedSurface.ClearMasks
local BeginSurfaceMaskRefresh = RoundedSurface.BeginMaskRefresh
local EndSurfaceMaskRefresh = RoundedSurface.EndMaskRefresh
local MaskSurfaceTexture = RoundedSurface.MaskTextureWith

local roundedRuntimeActive = false

local function BarsDB()
    local db = _G.MSUF_DB
    return db and db.bars or nil
end

local function SettingEnabled()
    local bars = BarsDB()
    return bars and bars.roundedFramesEnabled == true and bars.roundedCastbars == true or false
end

local function CanCreate(existing)
    local fn = RoundedSurface.CanCreateRegion
    if type(fn) == "function" then return fn(existing) end
    local locked = _G.InCombatLockdown and _G.InCombatLockdown()
    return existing ~= nil or not locked
end

local function SnapOff(region)
    local fn = RoundedSurface.SnapOff
    if type(fn) == "function" then
        fn(region)
    elseif region and region.SetSnapToPixelGrid then
        region:SetSnapToPixelGrid(false)
        if region.SetTexelSnappingBias then region:SetTexelSnappingBias(0) end
    end
end

local function ApplyMediaSlice(region, path)
    local fn = RoundedSurface.ApplyMediaSlice
    if type(fn) == "function" then fn(region, path) end
end

local function ResolveMedia()
    local fn = RoundedSurface.ResolveMedia
    if type(fn) == "function" then return fn() end
    local bars = BarsDB()
    local strength = math.floor((tonumber(bars and bars.roundedCornerStrength) or 3) + 0.5)
    if strength < 1 then strength = 1 elseif strength > 5 then strength = 5 end
    local root = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Masks\\"
    return root .. "rounded_clean_mask_s" .. strength .. ".png",
        root .. "rounded_clean_edge_s" .. strength .. ".png", strength
end

local function ApplySurfaceMasks(frame)
    local statusBar = frame and frame.statusBar
    if not statusBar then return false end
    local maskPath = ResolveMedia()
    BeginSurfaceMaskRefresh(frame, MASKED_KEY)
    local fill = statusBar.GetStatusBarTexture and statusBar:GetStatusBarTexture() or nil
    MaskSurfaceTexture(frame, fill, MASK_KEY, MASKED_KEY, statusBar, maskPath)
    MaskSurfaceTexture(frame, frame.backgroundBar, MASK_KEY, MASKED_KEY, statusBar, maskPath)
    MaskSurfaceTexture(frame, frame.latencyBar, MASK_KEY, MASKED_KEY, statusBar, maskPath)
    if type(frame.empowerSegments) == "table" then
        for index = 1, #frame.empowerSegments do
            MaskSurfaceTexture(frame, frame.empowerSegments[index], MASK_KEY, MASKED_KEY, statusBar, maskPath)
        end
    end
    EndSurfaceMaskRefresh(frame, MASK_KEY, MASKED_KEY)
    return true
end

local function HideRoundedOutline(frame)
    local stack = frame and frame[OUTLINE_STACK_KEY]
    if type(stack) == "table" then
        for index = 1, #stack do
            if stack[index] then stack[index]:Hide() end
        end
    end
    local host = frame and frame._msufRoundedCastbarOutlineHost
    if host then host:Hide() end
end

local function EnsureOutlineHost(frame)
    local statusBar = frame and frame.statusBar
    if not statusBar then return nil end
    local host = frame._msufRoundedCastbarOutlineHost
    if not host then
        if not (CreateFrame and CanCreate(host)) then return nil end
        host = CreateFrame("Frame", nil, frame)
        host:EnableMouse(false)
        frame._msufRoundedCastbarOutlineHost = host
    end
    host:ClearAllPoints()
    host:SetAllPoints(statusBar)
    if host.SetFrameLevel then
        local baseLevel = statusBar.GetFrameLevel and statusBar:GetFrameLevel() or 0
        host:SetFrameLevel(baseLevel + 20)
    end
    return host
end

local function RenderRoundedOutline(frame, _, thickness, red, green, blue, alpha)
    if not frame or frame._msufRoundedCastbarBypass == true then return false end
    thickness = math.max(0, math.min(math.floor((tonumber(thickness) or 0) + 0.5), MAX_OUTLINE))
    if thickness <= 0 then
        local squareHost = frame and frame._msufOutlineHost
        if squareHost then
            if squareHost.SetBackdrop then squareHost:SetBackdrop(nil) end
            squareHost:Hide()
        end
        HideRoundedOutline(frame)
        frame._msufRoundedCastbarActive = true
        return true
    end

    local host = EnsureOutlineHost(frame)
    if not host then return false end
    local squareHost = frame._msufOutlineHost
    if squareHost then
        if squareHost.SetBackdrop then squareHost:SetBackdrop(nil) end
        squareHost:Hide()
    end
    local _, edgePath = ResolveMedia()
    local stack = frame[OUTLINE_STACK_KEY]
    if not stack then
        stack = {}
        frame[OUTLINE_STACK_KEY] = stack
    end
    for index = 1, thickness do
        local edge = stack[index]
        if not edge then
            if not CanCreate(edge) then
                HideRoundedOutline(frame)
                return false
            end
            edge = host:CreateTexture(nil, "OVERLAY", nil, 6)
            SnapOff(edge)
            stack[index] = edge
        end
        if edge._msufRoundedCastbarPath ~= edgePath then
            edge._msufRoundedCastbarPath = edgePath
            edge:SetTexture(edgePath, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        end
        ApplyMediaSlice(edge, edgePath)
        if edge._msufRoundedCastbarPad ~= index then
            edge._msufRoundedCastbarPad = index
            edge:ClearAllPoints()
            edge:SetPoint("TOPLEFT", frame.statusBar, "TOPLEFT", -index, index)
            edge:SetPoint("BOTTOMRIGHT", frame.statusBar, "BOTTOMRIGHT", index, -index)
        end
        edge:SetVertexColor(red or 0, green or 0, blue or 0, alpha or 1)
        edge:Show()
    end
    for index = thickness + 1, #stack do
        if stack[index] then stack[index]:Hide() end
    end
    host:Show()
    frame._msufRoundedCastbarActive = true
    return true
end

local function ApplyRoundedOutline(frame, edge, thickness, red, green, blue, alpha)
    if not (roundedRuntimeActive and SettingEnabled()) then return false end
    return RenderRoundedOutline(frame, edge, thickness, red, green, blue, alpha)
end

local function TintRoundedOutline(frame, red, green, blue, alpha)
    if not (roundedRuntimeActive and SettingEnabled()) then return false end
    local host = frame and frame._msufRoundedCastbarOutlineHost
    local stack = frame and frame[OUTLINE_STACK_KEY]
    if not (host and host.IsShown and host:IsShown() and type(stack) == "table") then return false end
    local tinted = false
    for index = 1, #stack do
        local edge = stack[index]
        if edge and (not edge.IsShown or edge:IsShown()) then
            edge:SetVertexColor(red, green, blue, alpha)
            tinted = true
        end
    end
    return tinted
end

local function FrameUsesMSUFBackend(frame)
    if not frame or frame._msufIsPreview == true then return true end
    local unit = tostring(frame.unit or "")
    if unit:match("^boss%d+$") then unit = "boss" end
    local shouldUse = _G.MSUF_ShouldUseMSUFCastbar
    local general = _G.MSUF_DB and _G.MSUF_DB.general
    if type(shouldUse) == "function" and unit ~= "" then return shouldUse(unit, general) == true end
    return true
end

local function RestoreSquareOutline(frame)
    frame._msufOutlineT = nil
    frame._msufOutlineEdge = nil
    local apply = _G.MSUF_ApplyCastbarOutline
    if type(apply) == "function" then
        frame._msufRoundedCastbarBypass = true
        apply(frame, true)
        frame._msufRoundedCastbarBypass = nil
    end
end

local function ClearFrame(frame, restoreOutline)
    if not frame then return end
    local wasActive = frame._msufRoundedCastbarActive == true
    ClearSurfaceMasks(frame, MASK_KEY, MASKED_KEY)
    HideRoundedOutline(frame)
    frame._msufRoundedCastbarActive = nil
    if restoreOutline and wasActive then RestoreSquareOutline(frame) end
end

-- Menu2 previews use the real castbar rounded renderer instead of maintaining
-- a second approximation. The caller supplies a statusBar-compatible surface
-- and its physical preview outline thickness.
local function RenderPreviewFrame(frame, thickness, red, green, blue, alpha)
    if not (frame and frame.statusBar) then return false end
    if not SettingEnabled() then
        ClearFrame(frame, false)
        return false
    end
    if not ApplySurfaceMasks(frame) then return false end
    frame._msufRoundedCastbarActive = true
    if RenderRoundedOutline(frame, thickness, thickness, red, green, blue, alpha) then return true end
    ClearFrame(frame, false)
    return false
end

local function ApplyFrame(frame)
    if not (frame and frame.statusBar) then return false end
    if not (roundedRuntimeActive and SettingEnabled() and FrameUsesMSUFBackend(frame)) then
        if frame._msufRoundedCastbarActive == true then ClearFrame(frame, true) end
        return false
    end
    ApplySurfaceMasks(frame)
    frame._msufRoundedCastbarActive = true
    local applyOutline = _G.MSUF_ApplyCastbarOutline
    if type(applyOutline) == "function" then applyOutline(frame, true) end
    return true
end

local function ForEachCastbar(callback)
    local seen = {}
    local function Visit(frame)
        if frame and not seen[frame] then
            seen[frame] = true
            callback(frame)
        end
    end
    Visit(_G.MSUF_PlayerCastbar or _G.MSUF_PlayerCastBar)
    Visit(_G.MSUF_TargetCastbar or _G.MSUF_TargetCastBar)
    Visit(_G.MSUF_FocusCastbar or _G.MSUF_FocusCastBar)
    Visit(_G.MSUF_PlayerCastbarPreview)
    Visit(_G.MSUF_TargetCastbarPreview)
    Visit(_G.MSUF_FocusCastbarPreview)
    Visit(_G.MSUF_BossCastbarPreview or _G.MSUF_BossCastbarPreview1)
    local bossCastbars = _G.MSUF_BossCastbars
    local maxBoss = tonumber(_G.MSUF_MAX_BOSS_FRAMES or _G.MAX_BOSS_FRAMES) or 5
    if maxBoss < 1 or maxBoss > 12 then maxBoss = 5 end
    for index = 1, maxBoss do
        Visit(type(bossCastbars) == "table" and bossCastbars[index] or nil)
        Visit(_G["MSUF_BossCastbar" .. index] or _G["MSUF_boss" .. index .. "CastBar"])
        Visit(_G["MSUF_BossCastbarPreview" .. index])
    end
end

local function ApplyAll(masterActive)
    roundedRuntimeActive = masterActive == true and SettingEnabled()
    ForEachCastbar(function(frame)
        if roundedRuntimeActive then ApplyFrame(frame) else ClearFrame(frame, true) end
    end)
end

MSUF.RoundedCastbarsApplyAll = ApplyAll
ExportPublic("MSUF_ApplyRoundedCastbars", function()
    ApplyAll(SettingEnabled())
end)
ExportPublic("MSUF_RoundedCastbar_RefreshFrame", ApplyFrame)
ExportPublic("MSUF_RoundedCastbar_ApplyOutline", ApplyRoundedOutline)
ExportPublic("MSUF_RoundedCastbar_TintOutline", TintRoundedOutline)
ExportPublic("MSUF_RoundedCastbar_RenderPreview", RenderPreviewFrame)
