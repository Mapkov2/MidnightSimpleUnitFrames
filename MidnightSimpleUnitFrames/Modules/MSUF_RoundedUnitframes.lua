-- MSUF Module: Rounded Frame Texture
-- What it does:
-- - Applies a rounded mask texture to frame/bar surfaces.
-- - Covers both unitframes and group frames.
-- - Bars > Rounded Texture controls which frame surfaces receive the style.
-- - Combat path: no geometry or mask rebuilding; pending work is deferred.
-- NOTE (why v1 felt "does nothing"):
-- Unitframes use additional overlay textures (HP gradients etc.) that were NOT masked.
-- Those square overlays will visually "re-square" the corners even if the StatusBar fill
-- is masked. This version masks *everything that can touch the corners*.
-- Hard requirements:
-- - This file must be loaded by WoW (listed in a .toc, or shipped as its own addon).
-- - No OnUpdate/tickers; only event/hooks + one-shot C_Timer.After(0) for post-login ordering.

local addonName, ns = ...
ns = ns or {}

-- IMPORTANT: Use the *folder* name (addonName) for asset paths.
local MASK_ROOT = "Interface\\AddOns\\" .. tostring(addonName or "MidnightSimpleUnitFrames") .. "\\Media\\Masks\\"
local MASK_PATH = MASK_ROOT .. "rounded_bar_4x.tga"
local MASK_PATH_1X = MASK_ROOT .. "rounded_bar_1x.tga"
local MASK_PATH_2X = MASK_ROOT .. "rounded_bar_2x.tga"
local MASK_PATH_4X = MASK_ROOT .. "rounded_bar_4x.tga"
local MASK_PATH_8X = MASK_ROOT .. "rounded_bar_8x.tga"
local EDGE_PATH_4X = MASK_ROOT .. "rounded_bar_edge_4x.tga"
local WHITE8 = "Interface\\Buttons\\WHITE8x8"

local InCombatLockdown = _G.InCombatLockdown

local BASE_BORDER_R, BASE_BORDER_G, BASE_BORDER_B, BASE_BORDER_A = 0, 0, 0, 1
local ACTIVE_BORDER_A = 1.00

local forceDisabled = false

-- Baseline behavior: rounded bar content only.
-- Square native outlines are suppressed while enabled, because they visually
-- fight the rounded mask.
local DRAW_MODULE_BORDER = false
local SUPPRESS_NATIVE_OUTLINE = true

local function IsCombatLocked()
    return InCombatLockdown and InCombatLockdown()
end

local function ResolveBaseEdgeColor()
    return BASE_BORDER_R, BASE_BORDER_G, BASE_BORDER_B, BASE_BORDER_A
end

local function DeferApply()
    ns.__msufRoundedPending = true
end

local function CanCreateRoundedRegion(existing)
    if existing then return true end
    if IsCombatLocked() then
        DeferApply()
        return false
    end
    return true
end

local function EnsureDB()
    local ensureDB = _G.MSUF_EnsureDB
    if ensureDB then
        ensureDB()
    end
end

local function BarsDB()
    local db = _G.MSUF_DB
    return db and db.bars or nil
end

local function ReadRoundedBool(key, default)
    local bars = BarsDB()
    local value = bars and bars[key]
    if value == nil then return default and true or false end
    return value and true or false
end

local function IsConfiguredEnabled()
    return ReadRoundedBool("roundedFramesEnabled", false)
end

local function IsEnabled()
    return forceDisabled ~= true and IsConfiguredEnabled()
end

local function RoundedUnitFramesEnabled()
    return IsEnabled() and ReadRoundedBool("roundedUnitFrames", true)
end

local function RoundedGroupFramesEnabled()
    return IsEnabled() and ReadRoundedBool("roundedGroupFrames", true)
end

local function RoundedPowerBarsEnabled()
    return IsEnabled() and ReadRoundedBool("roundedPowerBars", true)
end

local function RoundedMouseoverEnabled()
    return IsEnabled() and ReadRoundedBool("roundedMouseover", true)
end

local function ResolveMouseoverEdgeColor()
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    if gen then
        local c = gen.highlightColor
        if type(c) == "table" and c[1] then
            return c[1], c[2] or 1, c[3] or 1, 0.78
        end
        if type(c) == "string" then
            local colors = (ns and ns.MSUF_FONT_COLORS) or _G.MSUF_FONT_COLORS
            local cc = colors and colors[c]
            if cc then return cc[1], cc[2], cc[3], 0.78 end
        end
    end
    return 1, 1, 1, 0.72
end

local function ClampEdgeSize(value, fallback, maxValue)
    local n = tonumber(value)
    if n == nil then n = tonumber(fallback) or 0 end
    n = math.floor(n + 0.5)
    if n < 0 then n = 0 end
    maxValue = tonumber(maxValue) or 8
    if n > maxValue then n = maxValue end
    return n
end

local function RoundedEdgeLayoutPad(thickness, fallback)
    -- The rounded edge asset is a fixed stroke; large offsets distort the corners.
    local pad = ClampEdgeSize(thickness, fallback, 30)
    if pad > 2 then pad = 2 end
    return pad
end

local function ResolveUnitOutlineThickness(f)
    local get = _G.MSUF_GetDesiredBarBorderThicknessAndStamp
    local thickness
    if type(get) == "function" then
        thickness = select(1, get(f))
    end
    if thickness == nil then
        local bars = BarsDB()
        thickness = bars and bars.barOutlineThickness or 1
    end
    return ClampEdgeSize(thickness, 0, 8)
end

local function LayoutRoundedEdge(edge, anchor, thickness, padOverride)
    if not (edge and anchor) then return false end
    local pad = padOverride and ClampEdgeSize(padOverride, 1, 8) or RoundedEdgeLayoutPad(thickness, 1)
    if pad <= 0 then
        edge:Hide()
        return false
    end
    if edge._msufRUFEdgeLayoutReady and edge._msufRUFEdgeAnchor == anchor and edge._msufRUFEdgePad == pad then
        return true
    end
    if IsCombatLocked() then
        DeferApply()
        return edge._msufRUFEdgeLayoutReady == true
    end
    edge:ClearAllPoints()
    edge:SetPoint("TOPLEFT", anchor, "TOPLEFT", -pad, pad)
    edge:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", pad, -pad)
    edge._msufRUFEdgeLayoutReady = true
    edge._msufRUFEdgeAnchor = anchor
    edge._msufRUFEdgePad = pad
    return true
end

-- Optional edge shell (kept for cleanup/backward compatibility; disabled by default).

local function SE_SnapOff(tex)
    if tex and tex.SetSnapToPixelGrid then
        tex:SetSnapToPixelGrid(false)
        if tex.SetTexelSnappingBias then tex:SetTexelSnappingBias(0) end
    end
end

local function SE_EnsureGroup(frame, key, layer, subLevel)
    if not (frame and frame.CreateTexture) then return nil end
    if frame[key] then return frame[key] end
    if not CanCreateRoundedRegion(frame[key]) then return nil end

    local g = {}
    g.L = frame:CreateTexture(nil, layer, nil, subLevel or 0)
    g.M = frame:CreateTexture(nil, layer, nil, subLevel or 0)
    g.R = frame:CreateTexture(nil, layer, nil, subLevel or 0)
    g._parts = { g.L, g.M, g.R }

    g.L:SetTexture(WHITE8)
    g.M:SetTexture(WHITE8)
    g.R:SetTexture(WHITE8)

    -- Atlas UVs: L=0..0.25, M=0.25..0.75, R=0.75..1
    g.L:SetTexCoord(0.0, 0.25, 0.0, 1.0)
    g.M:SetTexCoord(0.25, 0.75, 0.0, 1.0)
    g.R:SetTexCoord(0.75, 1.0, 0.0, 1.0)

    SE_SnapOff(g.L); SE_SnapOff(g.M); SE_SnapOff(g.R)

    function g:SetVertexColor(r, gg, b, a)
        for i = 1, #self._parts do
            local t = self._parts[i]
            if t and t.SetVertexColor then t:SetVertexColor(r, gg, b, a) end
        end
    end
    function g:Hide()
        for i = 1, #self._parts do
            local t = self._parts[i]
            if t and t.Hide then t:Hide() end
        end
    end
    function g:Show()
        for i = 1, #self._parts do
            local t = self._parts[i]
            if t and t.Show then t:Show() end
        end
    end

    frame[key] = g
    return g
end

local function SE_Layout(frameOrAnchor, g, pad)
    if not (frameOrAnchor and g and g.L and g.M and g.R) then return end
    pad = tonumber(pad) or 0

    -- Avoid GetWidth/GetHeight here. This code can be reached through secure
    -- frame callbacks, where comparing protected dimensions taints execution.
    local capW = 16

    g.L:ClearAllPoints()
    g.M:ClearAllPoints()
    g.R:ClearAllPoints()

    g.L:SetPoint("TOPLEFT", frameOrAnchor, "TOPLEFT", pad, -pad)
    g.L:SetPoint("BOTTOMLEFT", frameOrAnchor, "BOTTOMLEFT", pad, pad)
    g.L:SetWidth(capW)

    g.R:SetPoint("TOPRIGHT", frameOrAnchor, "TOPRIGHT", -pad, -pad)
    g.R:SetPoint("BOTTOMRIGHT", frameOrAnchor, "BOTTOMRIGHT", -pad, pad)
    g.R:SetWidth(capW)

    g.M:SetPoint("TOPLEFT", g.L, "TOPRIGHT", 0, 0)
    g.M:SetPoint("BOTTOMRIGHT", g.R, "BOTTOMLEFT", 0, 0)
end

local function SE_EnsureShell(f)
    if not f then return nil end
    if f._msufRoundedShell then
        if not f._msufRoundedShell.border then
            f._msufRoundedShell.border = SE_EnsureGroup(f, "_msufRUF_Border3", "OVERLAY", 0)
        end
        return f._msufRoundedShell
    end
    if not CanCreateRoundedRegion(f._msufRoundedShell) then return nil end

    local shell = {}
    -- Optional: module border. Default path is pure texture masking.
    shell.border = SE_EnsureGroup(f, "_msufRUF_Border3", "OVERLAY", 0)
    shell._hooked = false

    f._msufRoundedShell = shell
    return shell
end

local function SE_ApplyShellVisuals(f, enabled)
    local shell = f and f._msufRoundedShell or nil
    if not DRAW_MODULE_BORDER then
        if shell and shell.border then shell.border:Hide() end
        return
    end
    if not shell and not enabled then return end
    shell = shell or SE_EnsureShell(f)
    if not shell then return end

    if not shell.border then return end

    if not enabled then
        shell.border:Hide()
        return
    end

    local br, bgc, bb, ba = ResolveBaseEdgeColor()

    shell.border:SetVertexColor(br, bgc, bb, ba)

    -- Layout: use the same inner rect as the frame background (2px inset)
    local anchor = f.bg or f
    SE_Layout(anchor, shell.border, 0)

    shell.border:Show()

    if f.HookScript and not shell._hooked then
        shell._hooked = true
        f:HookScript("OnSizeChanged", function()
            local a = f.bg or f
            SE_Layout(a, shell.border, 0)
        end)
    end
end

local function SE_EnsureGroupFrameShell(f)
    if not (f and f._msufGFBorderFrame) then return nil end
    if f._msufRoundedGFShell then
        if not f._msufRoundedGFShell.border then
            f._msufRoundedGFShell.border = SE_EnsureGroup(f._msufGFBorderFrame, "_msufRGF_Border3", "OVERLAY", 0)
        end
        return f._msufRoundedGFShell
    end
    if not CanCreateRoundedRegion(f._msufRoundedGFShell) then return nil end

    local shell = {}
    shell.border = SE_EnsureGroup(f._msufGFBorderFrame, "_msufRGF_Border3", "OVERLAY", 0)
    f._msufRoundedGFShell = shell
    return shell
end

local function SE_ApplyGroupFrameShellVisuals(f, enabled)
    local shell = f and f._msufRoundedGFShell or nil
    if not DRAW_MODULE_BORDER then
        if shell and shell.border then shell.border:Hide() end
        return
    end
    if not shell and not enabled then return end
    shell = shell or SE_EnsureGroupFrameShell(f)
    if not shell or not shell.border then return end

    if not enabled then
        shell.border:Hide()
        return
    end

    local borderHost = f._msufGFBorderFrame
    if borderHost and borderHost.SetBackdrop then
        borderHost:SetBackdrop(nil)
        borderHost._msufGFBorderSize = nil
    end

    local br, bgc, bb, ba = BASE_BORDER_R, BASE_BORDER_G, BASE_BORDER_B, BASE_BORDER_A
    local active = f._msufGFHighlightBorder
    if active and active._msufHLActivePrio then
        br = active._msufHLR or br
        bgc = active._msufHLG or bgc
        bb = active._msufHLB or bb
        ba = active._msufHLA or ACTIVE_BORDER_A
    end
    shell.border:SetVertexColor(br, bgc, bb, ba)
    SE_Layout(borderHost, shell.border, 0)
    if borderHost and borderHost.Show then borderHost:Show() end
    shell.border:Show()
end

-- Masking helpers

local function ResolveMaskPath(maskPath)
    -- Do not inspect protected frame dimensions here. This can run from secure
    -- Blizzard handlers where GetWidth/GetHeight return restricted values.
    return maskPath or MASK_PATH
end

local function ResolveMaskOwner(f, tex, anchor)
    local owner = tex and tex.GetParent and tex:GetParent() or nil
    if owner and type(owner.CreateMaskTexture) == "function" then return owner end
    if anchor and type(anchor.CreateMaskTexture) == "function" then return anchor end
    return f
end

local function EnsureMaskForAnchor(f, maskKey, anchor, tex, maskPath)
    if not (f and type(f.CreateMaskTexture) == "function") then return nil end
    anchor = anchor or f
    local owner = ResolveMaskOwner(f, tex, anchor)
    if not (owner and type(owner.CreateMaskTexture) == "function") then return nil end
    local cacheKey = tex or owner

    local masksByOwner = f[maskKey .. "ByOwner"]
    if not masksByOwner then
        masksByOwner = {}
        f[maskKey .. "ByOwner"] = masksByOwner
    end

    local m = masksByOwner[cacheKey]
    if not m then
        if not CanCreateRoundedRegion(m) then return nil end
        m = owner:CreateMaskTexture(nil, "ARTWORK")
        -- Reduce grey/fringing artifacts at the edges.
        SE_SnapOff(m)
        masksByOwner[cacheKey] = m
    end

    local anchorByOwner = f[maskKey .. "AnchorByOwner"]
    if not anchorByOwner then
        anchorByOwner = {}
        f[maskKey .. "AnchorByOwner"] = anchorByOwner
    end
    local pathByOwner = f[maskKey .. "PathByOwner"]
    if not pathByOwner then
        pathByOwner = {}
        f[maskKey .. "PathByOwner"] = pathByOwner
    end

    local path = ResolveMaskPath(maskPath)
    if anchorByOwner[cacheKey] ~= anchor or pathByOwner[cacheKey] ~= path then
        if IsCombatLocked() then
            DeferApply()
            return nil
        end
        anchorByOwner[cacheKey] = anchor
        pathByOwner[cacheKey] = path
        if m.ClearAllPoints then m:ClearAllPoints() end
        -- Use clamp-to-black-additive to avoid edge bleed from filtering.
        m:SetTexture(path, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m:SetAllPoints(anchor)
    end
    return m
end

local function ClearMasks(f, maskKey, maskedKey)
    if not f then return end
    local masked = f[maskedKey]
    if masked then
        for tex, mask in pairs(masked) do
            if tex and type(tex.RemoveMaskTexture) == "function" then
                if mask and mask ~= true then
                    tex:RemoveMaskTexture(mask)
                elseif f[maskKey] then
                    tex:RemoveMaskTexture(f[maskKey])
                end
            end
        end
    end
    f[maskedKey] = nil
end

local function MaskTextureWith(f, tex, maskKey, maskedKey, anchor, maskPath)
    if not (f and tex) then return end
    if type(tex.AddMaskTexture) ~= "function" then return end

    local masked = f[maskedKey]
    if IsCombatLocked() and not (masked and masked[tex]) then
        DeferApply()
        return
    end

    local m = EnsureMaskForAnchor(f, maskKey, anchor, tex, maskPath)
    if not m then return end

    f[maskedKey] = f[maskedKey] or {}
    if f[maskedKey][tex] then return end

    tex:AddMaskTexture(m)
    f[maskedKey][tex] = m
end

local function EnsureFrameMask(f)
    return EnsureMaskForAnchor(f, "_msufRUF_Mask", f and (f.bg or f) or nil, nil, MASK_PATH)
end

local function ClearAllMasks(f)
    ClearMasks(f, "_msufRUF_Mask", "_msufRUF_MaskedTextures")
end

local function MaskTexture(f, tex, anchor, maskPath)
    MaskTextureWith(f, tex, "_msufRUF_Mask", "_msufRUF_MaskedTextures", anchor or (f and (f.bg or f) or nil), maskPath or MASK_PATH)
end

local function ClearGroupMasks(f)
    ClearMasks(f, "_msufRGF_Mask", "_msufRGF_MaskedTextures")
end

local function MaskGroupTexture(f, tex, anchor, maskPath)
    MaskTextureWith(f, tex, "_msufRGF_Mask", "_msufRGF_MaskedTextures", anchor or (f and (f.barGroup or f) or nil), maskPath or MASK_PATH)
end

local function ClearMaskForTexture(f, maskedKey, tex)
    local masked = f and f[maskedKey]
    local mask = masked and tex and masked[tex]
    if mask and tex.RemoveMaskTexture then
        tex:RemoveMaskTexture(mask)
        masked[tex] = nil
    end
end

local function SetRoundedEdgeTexture(edge)
    if edge and edge._msufRUF_EdgeTexture ~= EDGE_PATH_4X then
        edge._msufRUF_EdgeTexture = EDGE_PATH_4X
        edge:SetTexture(EDGE_PATH_4X, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    end
end

local function HideRoundedEdgeStack(owner, baseEdge, poolKey)
    if baseEdge then baseEdge:Hide() end
    local stack = owner and owner[poolKey]
    if type(stack) ~= "table" then return end
    for i = 2, #stack do
        local edge = stack[i]
        if edge and edge.Hide then edge:Hide() end
    end
end

local function ShowRoundedEdgeStack(owner, baseEdge, poolKey)
    local stack = owner and owner[poolKey]
    if type(stack) ~= "table" then
        if baseEdge then baseEdge:Show() end
        return
    end
    local count = ClampEdgeSize(stack._msufCount, 1, 8)
    for i = 1, count do
        local edge = (i == 1) and baseEdge or stack[i]
        if edge and edge.Show then edge:Show() end
    end
end

local function SetRoundedEdgeStackColor(owner, baseEdge, poolKey, r, g, b, a)
    if baseEdge and baseEdge.SetVertexColor then baseEdge:SetVertexColor(r, g, b, a) end
    local stack = owner and owner[poolKey]
    if type(stack) ~= "table" then return end
    for i = 2, #stack do
        local edge = stack[i]
        if edge and edge.SetVertexColor then edge:SetVertexColor(r, g, b, a) end
    end
end

local function ApplyRoundedEdgeStack(owner, parent, baseEdge, anchor, thickness, poolKey, maskedKey, layer, subLevel)
    if not (owner and parent and baseEdge and anchor) then return false end
    local count = ClampEdgeSize(thickness, 0, 8)
    if count <= 0 then
        HideRoundedEdgeStack(owner, baseEdge, poolKey)
        return false
    end

    local stack = owner[poolKey]
    if not stack then
        stack = {}
        owner[poolKey] = stack
    end
    stack[1] = baseEdge
    stack._msufCount = count

    for i = 1, count do
        local edge = (i == 1) and baseEdge or stack[i]
        if not edge then
            if not CanCreateRoundedRegion(edge) then return false end
            edge = parent:CreateTexture(nil, layer, nil, subLevel or 0)
            SE_SnapOff(edge)
            stack[i] = edge
        end
        ClearMaskForTexture(owner, maskedKey, edge)
        SetRoundedEdgeTexture(edge)
        if not LayoutRoundedEdge(edge, anchor, i, i) then return false end
        edge:Show()
    end

    for i = count + 1, #stack do
        local edge = stack[i]
        if edge and edge.Hide then edge:Hide() end
    end

    return true
end

local function ResolveUnitEdgeColor(f)
    local key = f and tonumber(f._msufHighlightActiveKey or f._msufHighlightColorKey) or 0
    if key and key ~= 0 then
        return f._msufHighlightOutlineR or 1,
            f._msufHighlightOutlineG or 1,
            f._msufHighlightOutlineB or 1,
            ACTIVE_BORDER_A
    end
    return ResolveBaseEdgeColor()
end

local function ResolveUnitEdgeThickness(f, active, activeThickness)
    if active then
        return ClampEdgeSize(activeThickness, 2, 30)
    end
    return ResolveUnitOutlineThickness(f)
end

local function ApplyUnitRoundedEdge(f, enabled, active, activeThickness)
    if not f then return end
    local edge = f._msufRUF_Edge
    if not enabled then
        HideRoundedEdgeStack(f, edge, "_msufRUF_EdgeStack")
        return
    end
    local anchor = f.bg or f
    local thickness = ResolveUnitEdgeThickness(f, active, activeThickness)
    if not edge then
        if not CanCreateRoundedRegion(edge) then return end
        edge = f:CreateTexture(nil, "BACKGROUND", nil, -7)
        SE_SnapOff(edge)
        f._msufRUF_Edge = edge
    end
    if thickness <= 0 and not active then
        HideRoundedEdgeStack(f, edge, "_msufRUF_EdgeStack")
        return edge
    end
    if not ApplyRoundedEdgeStack(f, f, edge, anchor, thickness, "_msufRUF_EdgeStack", "_msufRUF_MaskedTextures", "BACKGROUND", -7) then return edge end
    local r, g, b, a = ResolveUnitEdgeColor(f)
    SetRoundedEdgeStackColor(f, edge, "_msufRUF_EdgeStack", r, g, b, a)
    return edge
end

local function SetUnitRoundedEdgeColor(f, active, r, g, b, a, thickness)
    if not f then return false end
    local edge = f._msufRUF_Edge
    if not edge then
        if IsCombatLocked() then return false end
        ApplyUnitRoundedEdge(f, true, active, thickness)
        edge = f._msufRUF_Edge
    end
    if not edge then return false end
    local resolvedThickness = ResolveUnitEdgeThickness(f, active, thickness)
    if resolvedThickness <= 0 and not active then
        HideRoundedEdgeStack(f, edge, "_msufRUF_EdgeStack")
        return true
    end
    if active then
        if not ApplyRoundedEdgeStack(f, f, edge, f.bg or f, resolvedThickness, "_msufRUF_EdgeStack", "_msufRUF_MaskedTextures", "BACKGROUND", -7) then return false end
        SetRoundedEdgeStackColor(f, edge, "_msufRUF_EdgeStack", r or 1, g or 1, b or 1, a or ACTIVE_BORDER_A)
    else
        local br, bgc, bb, ba = ResolveBaseEdgeColor()
        if not ApplyRoundedEdgeStack(f, f, edge, f.bg or f, resolvedThickness, "_msufRUF_EdgeStack", "_msufRUF_MaskedTextures", "BACKGROUND", -7) then return false end
        SetRoundedEdgeStackColor(f, edge, "_msufRUF_EdgeStack", br, bgc, bb, ba)
    end
    return true
end

local function HandleUnitHighlightChanged(f, hlKey, r, g, b, cfg)
    if not (f and RoundedUnitFramesEnabled()) then
        if f then f._msufRoundedHighlightGlowAnchor = nil end
        return false
    end
    local active = (tonumber(hlKey) or 0) ~= 0
    if f._msufHighlightOutline and f._msufHighlightOutline.Hide then
        f._msufHighlightOutline:Hide()
    end
    f._msufRoundedHighlightGlowAnchor = active and f or nil
    return SetUnitRoundedEdgeColor(f, active, r, g, b,
        active and ((cfg and cfg.highlightBorderAlpha) or ACTIVE_BORDER_A) or nil,
        active and (cfg and cfg.highlightBorderThickness) or nil)
end

local function ApplyUnitRoundedHoverEdge(f, enabled)
    if not f then return nil end
    local edge = f._msufRUF_HoverEdge
    if not enabled then
        if edge then edge:Hide() end
        return edge
    end

    local anchor = f.bg or f
    if not edge then
        if not CanCreateRoundedRegion(edge) then return nil end
        edge = f:CreateTexture(nil, "OVERLAY", nil, 7)
        SE_SnapOff(edge)
        f._msufRUF_HoverEdge = edge
    end

    ClearMaskForTexture(f, "_msufRUF_MaskedTextures", edge)
    SetRoundedEdgeTexture(edge)
    local thickness = ResolveUnitOutlineThickness(f)
    if thickness < 1 then thickness = 1 end
    ApplyRoundedEdgeStack(f, f, edge, anchor, thickness, "_msufRUF_HoverEdgeStack", "_msufRUF_MaskedTextures", "OVERLAY", 7)
    local r, g, b, a = ResolveMouseoverEdgeColor()
    SetRoundedEdgeStackColor(f, edge, "_msufRUF_HoverEdgeStack", r, g, b, a)
    HideRoundedEdgeStack(f, edge, "_msufRUF_HoverEdgeStack")
    return edge
end

local function HandleUnitMouseover(f, active)
    if not (f and RoundedUnitFramesEnabled() and RoundedMouseoverEnabled()) then return false end
    if f.highlightBorder and f.highlightBorder.Hide then
        f.highlightBorder:Hide()
    end

    local edge = f._msufRUF_HoverEdge
    if not edge and not IsCombatLocked() then
        edge = ApplyUnitRoundedHoverEdge(f, true)
    end
    if edge then
        if active then
            ShowRoundedEdgeStack(f, edge, "_msufRUF_HoverEdgeStack")
        else
            HideRoundedEdgeStack(f, edge, "_msufRUF_HoverEdgeStack")
        end
    end
    return true
end

local function ResolveDetachedPowerEdgeThickness(f)
    if not (f and f._msufPowerBarDetached and f.targetPowerBar) then return 0 end
    local bars = BarsDB()
    local raw = bars and bars.detachedPowerBarOutline
    if raw == nil then raw = ResolveUnitOutlineThickness(f) end
    return ClampEdgeSize(raw, 0, 8)
end

local function ApplyDetachedPowerRoundedEdge(f, enabled)
    if not f then return nil end
    local edge = f._msufRUF_DetachedPowerEdge
    if not enabled then
        HideRoundedEdgeStack(f, edge, "_msufRUF_DetachedPowerEdgeStack")
        return edge
    end

    local pb = f.targetPowerBar
    local thickness = ResolveDetachedPowerEdgeThickness(f)
    if not (pb and thickness > 0) then
        HideRoundedEdgeStack(f, edge, "_msufRUF_DetachedPowerEdgeStack")
        return edge
    end
    if not edge then
        if not CanCreateRoundedRegion(edge) then return nil end
        edge = pb:CreateTexture(nil, "OVERLAY", nil, 6)
        SE_SnapOff(edge)
        f._msufRUF_DetachedPowerEdge = edge
    end
    if not ApplyRoundedEdgeStack(f, pb, edge, pb, thickness, "_msufRUF_DetachedPowerEdgeStack", "_msufRUF_MaskedTextures", "OVERLAY", 6) then return edge end
    local r, g, b, a = ResolveBaseEdgeColor()
    SetRoundedEdgeStackColor(f, edge, "_msufRUF_DetachedPowerEdgeStack", r, g, b, a)
    return edge
end

local ApplyGroupRoundedEdge
local ResolveGroupOutlineThickness

local function ResolveGroupEdgeColor(f)
    local r, g, b, a = ResolveBaseEdgeColor()
    if RoundedMouseoverEnabled() and f and f._msufRUF_GroupMouseoverActive then
        return ResolveMouseoverEdgeColor()
    end
    local active = f and f._msufGFHighlightBorder or nil
    if active and active._msufHLActivePrio then
        r = active._msufHLR or r
        g = active._msufHLG or g
        b = active._msufHLB or b
        a = active._msufHLA or ACTIVE_BORDER_A
    end
    return r, g, b, a
end

local function ResolveGroupEdgeThickness(f)
    local active = f and f._msufGFHighlightBorder or nil
    if active and active._msufHLActivePrio then
        return ClampEdgeSize(active._msufHLEdgeSz or active._msufHLOfs, 2, 30)
    end
    if f and f._msufRUF_GroupMouseoverActive then
        local t = ResolveGroupOutlineThickness and ResolveGroupOutlineThickness(f) or 1
        if t < 1 then t = 1 end
        return t
    end
    return ResolveGroupOutlineThickness and ResolveGroupOutlineThickness(f) or 1
end

local function SetGroupRoundedEdgeColor(f)
    if not f then return false end
    local edge = f._msufRGF_Edge
    local thickness = ResolveGroupEdgeThickness(f)
    local active = (f._msufRUF_GroupMouseoverActive == true)
        or (f._msufGFHighlightBorder and f._msufGFHighlightBorder._msufHLActivePrio)
    if not edge and thickness <= 0 and not active then
        return true
    end
    if not edge then
        if IsCombatLocked() then return false end
        ApplyGroupRoundedEdge(f, true)
        edge = f._msufRGF_Edge
    end
    if not edge then return false end
    if thickness <= 0 and not active then
        HideRoundedEdgeStack(f, edge, "_msufRGF_EdgeStack")
        return true
    end
    if not ApplyRoundedEdgeStack(f, f.barGroup or f, edge, f.barGroup or f, thickness, "_msufRGF_EdgeStack", "_msufRGF_MaskedTextures", "BACKGROUND", -8) then return false end
    local r, g, b, a = ResolveGroupEdgeColor(f)
    SetRoundedEdgeStackColor(f, edge, "_msufRGF_EdgeStack", r, g, b, a)
    return true
end

ApplyGroupRoundedEdge = function(f, enabled)
    if not f then return end
    local edge = f._msufRGF_Edge
    if not enabled then
        HideRoundedEdgeStack(f, edge, "_msufRGF_EdgeStack")
        return
    end
    local anchor = f.barGroup or f
    local parent = f.barGroup or f
    local thickness = ResolveGroupEdgeThickness(f)
    local active = (f._msufRUF_GroupMouseoverActive == true)
        or (f._msufGFHighlightBorder and f._msufGFHighlightBorder._msufHLActivePrio)
    if not edge then
        if not CanCreateRoundedRegion(edge) then return end
        edge = parent:CreateTexture(nil, "BACKGROUND", nil, -8)
        SE_SnapOff(edge)
        f._msufRGF_Edge = edge
    end
    if thickness <= 0 and not active then
        HideRoundedEdgeStack(f, edge, "_msufRGF_EdgeStack")
        return edge
    end
    if not ApplyRoundedEdgeStack(f, parent, edge, anchor, thickness, "_msufRGF_EdgeStack", "_msufRGF_MaskedTextures", "BACKGROUND", -8) then return edge end
    local r, g, b, a = ResolveGroupEdgeColor(f)
    SetRoundedEdgeStackColor(f, edge, "_msufRGF_EdgeStack", r, g, b, a)
    return edge
end

-- Suppress square outlines/borders while rounded masking is active.

local function SuppressNativeOutlineNow(f)
    if not (SUPPRESS_NATIVE_OUTLINE and f) then return end

    -- Unitframe bar outline (black square border around HB+PB).
    local o = f._msufBarOutline
    if o and o.frame and o.frame.Hide then
        o.frame:Hide()
    end

    -- Legacy border texture (some builds keep a spare reference).
    if f.border and f.border.Hide then
        f.border:Hide()
    end

    local pb = f.targetPowerBar or f.powerBar
    local pbo = pb and pb._msufPowerBorder
    if RoundedPowerBarsEnabled() and pbo and pbo.Hide then
        pbo:Hide()
    end
    if RoundedPowerBarsEnabled() and f._msufDetachedPBOutline and f._msufDetachedPBOutline.Hide then
        f._msufDetachedPBOutline:Hide()
    end

    -- Hover highlight border (square): keep feature, but suppress it while rounding is enabled.
    if RoundedMouseoverEnabled() and f.highlightBorder and f.highlightBorder.Hide then
        f.highlightBorder:Hide()
    end
    if f._msufHighlightOutline and f._msufHighlightOutline.Hide then
        f._msufHighlightOutline:Hide()
    end

    f._msufRUF_SuppressMouseover = RoundedMouseoverEnabled() and true or nil
end

local ApplyToGroupFrame

local function ResolveGF()
    return (ns and ns.GF) or (_G.MSUF_NS and _G.MSUF_NS.GF) or nil
end

local function IsGroupFrame(f)
    return f and f.barGroup and f.health
end

local function ResolveGroupKind(f, kind)
    if kind then return kind end
    local GF = ResolveGF()
    return (f and f._msufGFKind) or (GF and GF.frames and GF.frames[f]) or "party"
end

ResolveGroupOutlineThickness = function(f)
    local GF = ResolveGF()
    local kind = ResolveGroupKind(f)
    local thickness
    if GF and type(GF.GetBarOutlineThickness) == "function" then
        thickness = GF.GetBarOutlineThickness(kind)
    end
    if GF and type(GF.ScaleFrameValue) == "function" then
        thickness = GF.ScaleFrameValue(kind, thickness or 0, 0)
    end
    return ClampEdgeSize(thickness, 0, 8)
end

local function ResolveGroupBackdropColor(f, kind)
    local GF = ResolveGF()
    kind = ResolveGroupKind(f, kind)
    local conf = GF and GF.GetConf and GF.GetConf(kind) or nil
    local layerA = 1
    if GF and GF.GetEffectiveBackgroundAlpha then
        layerA = GF.GetEffectiveBackgroundAlpha(kind, conf) or 1
    end
    if not conf then return 0.1, 0.1, 0.1, 0.85 end
    return conf.bgR or 0.1, conf.bgG or 0.1, conf.bgB or 0.1, (conf.bgA or 0.85) * layerA
end

local function EnsureGroupBackground(f)
    if not (f and f.barGroup and f.barGroup.CreateTexture) then return nil end
    local bg = f._msufRGF_Background
    if not bg then
        if not CanCreateRoundedRegion(bg) then return nil end
        bg = f.barGroup:CreateTexture(nil, "BACKGROUND", nil, -8)
        bg:SetTexture(WHITE8)
        bg:SetAllPoints(f.barGroup)
        SE_SnapOff(bg)
        f._msufRGF_Background = bg
    end
    return bg
end

local function ApplyGroupBackdrop(f, kind, enabled)
    if not (f and f.barGroup) then return end
    local r, g, b, a = ResolveGroupBackdropColor(f, kind)
    local bg = enabled and EnsureGroupBackground(f) or f._msufRGF_Background
    if enabled and not bg then
        DeferApply()
        return
    end
    if bg then
        if f._msufRGF_BgR ~= r or f._msufRGF_BgG ~= g or f._msufRGF_BgB ~= b or f._msufRGF_BgA ~= a then
            f._msufRGF_BgR, f._msufRGF_BgG, f._msufRGF_BgB, f._msufRGF_BgA = r, g, b, a
            bg:SetVertexColor(r, g, b, a)
        end
        bg:SetShown(enabled)
    end
    if f.barGroup.SetBackdropColor then
        if enabled then
            f.barGroup._msufGFBackdropR = nil
            f.barGroup._msufGFBackdropG = nil
            f.barGroup._msufGFBackdropB = nil
            f.barGroup._msufGFBackdropA = nil
            f.barGroup:SetBackdropColor(0, 0, 0, 0)
        else
            f.barGroup:SetBackdropColor(r, g, b, a)
            f.barGroup._msufGFBackdropR = r
            f.barGroup._msufGFBackdropG = g
            f.barGroup._msufGFBackdropB = b
            f.barGroup._msufGFBackdropA = a
        end
    end
end

local function MaskStatusBarFill(f, bar, group)
    if not (bar and type(bar.GetStatusBarTexture) == "function") then return end
    local tex = bar:GetStatusBarTexture()
    if tex then
        if group then MaskGroupTexture(f, tex, bar) else MaskTexture(f, tex, bar) end
    end
end

local function MaskGFGradientTable(f, bar)
    local grads = bar and bar._msufGFGrads
    if type(grads) ~= "table" then return end
    if grads.left then MaskGroupTexture(f, grads.left, bar) end
    if grads.right then MaskGroupTexture(f, grads.right, bar) end
    if grads.up then MaskGroupTexture(f, grads.up, bar) end
    if grads.down then MaskGroupTexture(f, grads.down, bar) end
end

local function SuppressGroupSquareBorders(f)
    local borderHost = f and f._msufGFBorderFrame
    if borderHost and borderHost.SetBackdrop then
        borderHost:SetBackdrop(nil)
        borderHost._msufGFBorderSize = nil
    end

    local border = f and f._msufGFHighlightBorder
    if border then
        if not border._msufRGFOwner then border._msufRGFOwner = f end
        if border.HookScript and not border._msufRGFHooked then
            border._msufRGFHooked = true
            border:HookScript("OnShow", function(self)
                if RoundedGroupFramesEnabled() then
                    local owner = self._msufRGFOwner
                    local handled = false
                    if owner then
                        owner._msufRGF_GlowAnchor = owner.barGroup or owner
                        handled = SetGroupRoundedEdgeColor(owner)
                        if not handled and not IsCombatLocked() and ApplyToGroupFrame then
                            ApplyToGroupFrame(owner)
                            handled = owner._msufRGF_Edge and true or false
                        end
                    end
                    if handled and self.Hide then self:Hide() end
                end
            end)
        end
        if RoundedGroupFramesEnabled() and border.Hide then
            f._msufRGF_GlowAnchor = f.barGroup or f
            if SetGroupRoundedEdgeColor(f) then
                border:Hide()
            end
        end
    end
end

local function HandleGroupMouseover(f, active)
    if not (f and RoundedGroupFramesEnabled() and RoundedMouseoverEnabled()) then return false end
    if not f._msufRGF_Edge and IsCombatLocked() then return false end
    if f._msufGFHoverBorder and f._msufGFHoverBorder.Hide then
        f._msufGFHoverBorder:Hide()
    end
    f._msufRUF_GroupMouseoverActive = active and true or nil
    if not SetGroupRoundedEdgeColor(f) and not IsCombatLocked() then
        ApplyGroupRoundedEdge(f, true)
    end
    return true
end

local function HandleGroupHighlightChanged(border)
    local owner = border and (border._msufRGFOwner or (border.GetParent and border:GetParent() and border:GetParent():GetParent()))
    if not (owner and RoundedGroupFramesEnabled()) then return false end
    owner._msufRGF_GlowAnchor = owner.barGroup or owner
    if SetGroupRoundedEdgeColor(owner) then
        if border.Hide then border:Hide() end
        return true
    end
    if not IsCombatLocked() and ApplyToGroupFrame then
        ApplyToGroupFrame(owner)
        if owner._msufRGF_Edge then
            if border.Hide then border:Hide() end
            return true
        end
    end
    return false
end

-- Apply/remove

local function ApplyToUnitFrame(f)
    if not f then return end
    if IsCombatLocked() then
        DeferApply()
        return
    end

    local enabled = RoundedUnitFramesEnabled()
    local roundPower = RoundedPowerBarsEnabled()

    -- Shell: show/hide + keep colors in sync.
    SE_ApplyShellVisuals(f, enabled)

    if not enabled then
        f._msufRUF_SuppressMouseover = nil
        ClearAllMasks(f)
        ApplyUnitRoundedEdge(f, false)
        ApplyUnitRoundedHoverEdge(f, false)
        ApplyDetachedPowerRoundedEdge(f, false)
        -- Restore the original square outline behavior immediately (0 regression when disabled).
        if SUPPRESS_NATIVE_OUTLINE then
            local fnStatic = _G.MSUF_RefreshStaticUnitFrameOutlines
            if type(fnStatic) == "function" then
                fnStatic(f)
            elseif type(_G.MSUF_RefreshRareBarVisuals) == "function" then
                _G.MSUF_RefreshRareBarVisuals(f)
            end
        end
        return
    end

    -- Hide square outlines/borders while rounding is enabled.
    SuppressNativeOutlineNow(f)
    f._msufRUF_SuppressMouseover = RoundedMouseoverEnabled() and true or nil

    -- Bar textures can be swapped at runtime (texture dropdown etc.), so rebuild the mask list.
    ClearAllMasks(f)
    ApplyUnitRoundedEdge(f, true)
    ApplyUnitRoundedHoverEdge(f, RoundedMouseoverEnabled())
    ApplyDetachedPowerRoundedEdge(f, roundPower)

    -- Frame/background (inner rect) – this is what users perceive as the unitframe silhouette.
    if f.bg then
        MaskTexture(f, f.bg, f.bg)
    end

    -- Health bar fill + background
    if f.hpBar and type(f.hpBar.GetStatusBarTexture) == "function" then
        local hbFill = f.hpBar:GetStatusBarTexture()
        if hbFill then MaskTexture(f, hbFill, f.hpBar) end
    end
    if f.hpBarBG then
        MaskTexture(f, f.hpBarBG, f.hpBar or f.hpBarBG)
    end

    -- HP gradient overlays (these were the main reason corners still looked square)
    local grads = f.hpGradients
    if type(grads) == "table" then
        if grads.left  then MaskTexture(f, grads.left, f.hpBar)  end
        if grads.right then MaskTexture(f, grads.right, f.hpBar) end
        if grads.up    then MaskTexture(f, grads.up, f.hpBar)    end
        if grads.down  then MaskTexture(f, grads.down, f.hpBar)  end
    end

    -- Absorb overlays
    if f.absorbBar and type(f.absorbBar.GetStatusBarTexture) == "function" then
        local t = f.absorbBar:GetStatusBarTexture()
        if t then MaskTexture(f, t, f.absorbBar or f.hpBar) end
    end
    if f.healAbsorbBar and type(f.healAbsorbBar.GetStatusBarTexture) == "function" then
        local t = f.healAbsorbBar:GetStatusBarTexture()
        if t then MaskTexture(f, t, f.healAbsorbBar or f.hpBar) end
    end
    MaskStatusBarFill(f, f.incomingHealBar or f.selfHealPredBar)
    if f.selfHealPredBar ~= f.incomingHealBar then
        MaskStatusBarFill(f, f.selfHealPredBar)
    end

    if roundPower then
        -- Power bar fill + background
        local powerBar = f.targetPowerBar or f.powerBar
        if powerBar and type(powerBar.GetStatusBarTexture) == "function" then
            local pbFill = powerBar:GetStatusBarTexture()
            if pbFill then MaskTexture(f, pbFill, powerBar) end
        end
        if f.powerBarBG then
            MaskTexture(f, f.powerBarBG, powerBar or f.powerBarBG)
        end
        local pgrads = f.powerGradients
        if powerBar and type(pgrads) == "table" then
            if pgrads.left  then MaskTexture(f, pgrads.left, powerBar)  end
            if pgrads.right then MaskTexture(f, pgrads.right, powerBar) end
            if pgrads.up    then MaskTexture(f, pgrads.up, powerBar)    end
            if pgrads.down  then MaskTexture(f, pgrads.down, powerBar)  end
        end
    end

    -- Portrait can touch outer corners depending on layout, so mask it too (safe + no visual change beyond rounding).
    if f.portrait then
        MaskTexture(f, f.portrait, f.portrait, MASK_PATH_1X)
    end
end

ApplyToGroupFrame = function(f, kind)
    if not IsGroupFrame(f) then return end
    if IsCombatLocked() then
        DeferApply()
        return
    end

    local enabled = RoundedGroupFramesEnabled()
    local roundPower = RoundedPowerBarsEnabled()
    kind = ResolveGroupKind(f, kind)

    if not enabled then
        f._msufRUF_SuppressGFHover = nil
        f._msufRUF_GroupMouseoverActive = nil
        f._msufRGF_GlowAnchor = nil
        local hadRounded = f._msufRGF_Background or f._msufRGF_Edge or f._msufRoundedGFShell or f._msufRGF_MaskedTextures
        ClearGroupMasks(f)
        ApplyGroupRoundedEdge(f, false)
        if f._msufRGF_Background then f._msufRGF_Background:Hide() end
        SE_ApplyGroupFrameShellVisuals(f, false)
        ApplyGroupBackdrop(f, kind, false)

        local GF = ResolveGF()
        if hadRounded and GF and GF.MarkDirty and not f._msufRGFDisableRestoreQueued then
            f._msufRGFDisableRestoreQueued = true
            GF.MarkDirty(f, (GF.DIRTY_COLOR or 0x08) + (GF.DIRTY_BORDER or 0x10))
        end
        return
    end

    f._msufRGFDisableRestoreQueued = nil
    f._msufRUF_SuppressGFHover = RoundedMouseoverEnabled() and true or nil
    local combatLocked = IsCombatLocked()
    if combatLocked and not f._msufRGF_MaskedTextures then
        DeferApply()
        return
    end

    SuppressGroupSquareBorders(f)
    SE_ApplyGroupFrameShellVisuals(f, true)
    ApplyGroupBackdrop(f, kind, true)

    if combatLocked then
        DeferApply()
        return
    end

    ClearGroupMasks(f)
    ApplyGroupRoundedEdge(f, true)
    if f._msufRGF_Background then MaskGroupTexture(f, f._msufRGF_Background, f.barGroup) end
    if f.healthBg then MaskGroupTexture(f, f.healthBg, f.health or f.healthBg) end
    if roundPower and f.powerBg then MaskGroupTexture(f, f.powerBg, f.power or f.powerBg) end
    if f._msufBehindBarBg then MaskGroupTexture(f, f._msufBehindBarBg, f.barGroup) end

    MaskStatusBarFill(f, f.health, true)
    if roundPower then MaskStatusBarFill(f, f.power, true) end
    MaskStatusBarFill(f, f.incomingHealBar, true)
    MaskStatusBarFill(f, f.absorbBar, true)
    MaskStatusBarFill(f, f.healAbsorbBar, true)
    MaskStatusBarFill(f, f._msufGFDispelOverlay, true)
    MaskStatusBarFill(f, f._msufGFDebuffStripe, true)

    MaskGFGradientTable(f, f.health)
    if roundPower then MaskGFGradientTable(f, f.power) end
end

local function ForEachUnitFrame(fn)
    local frames = _G.MSUF_UnitFrames
    if not frames then return end
    for _, f in pairs(frames) do
        if type(fn) == "function" then
            fn(f)
        end
    end
end

local function ForEachGroupFrame(fn)
    local GF = ResolveGF()
    if not GF then return end
    if type(GF.ForEachFrame) == "function" then
        GF.ForEachFrame(fn, true)
    elseif type(GF.frames) == "table" then
        for f, kind in pairs(GF.frames) do
            fn(f, kind)
        end
    end
    if type(GF._previewFrames) == "table" then
        for kind, list in pairs(GF._previewFrames) do
            for i = 1, #list do
                local f = list[i]
                if f then fn(f, kind) end
            end
        end
    end
end

local function ApplyAll()
    EnsureDB()
    ns.__msufRoundedPending = nil
    local enabled = IsEnabled()
    if not enabled and not ns.__msufRoundedUF_Hooked then
        _G.MSUF_RoundedUF_Active = nil
        return
    end
    if IsCombatLocked() then
        if enabled then DeferApply() end
        return
    end
    _G.MSUF_RoundedUF_Active = enabled and true or nil
    ForEachUnitFrame(function(f)
        if IsGroupFrame(f) then
            ApplyToGroupFrame(f)
        else
            ApplyToUnitFrame(f)
        end
    end)
    ForEachGroupFrame(ApplyToGroupFrame)
    if not enabled then
        _G.MSUF_RoundedUF_Active = nil
        local eventFrame = ns.__msufRoundedEventFrame
        if eventFrame and eventFrame.UnregisterEvent then
            eventFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
        end
    end
end

-- Hooks / bootstrap

local function HookOnce()
    local eventFrame = ns.__msufRoundedEventFrame
    if eventFrame and eventFrame.RegisterEvent then
        eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
    if ns.__msufRoundedUF_Hooked then return end
    ns.__msufRoundedUF_Hooked = true

    -- Export callbacks for direct notification (replaces hooksecurefunc hooks).
    -- Source functions call these directly — zero hook overhead.
    _G.MSUF_RoundedUF_OnApplyAll = function()
        ApplyAll()
    end
    _G.MSUF_RoundedUF_OnGroupMouseover = function(frame, active)
        return HandleGroupMouseover(frame, active)
    end
    _G.MSUF_RoundedUF_OnUnitMouseover = function(frame, active)
        return HandleUnitMouseover(frame, active)
    end
    _G.MSUF_RoundedUF_OnUnitHighlightChanged = function(frame, hlKey, r, g, b, cfg)
        return HandleUnitHighlightChanged(frame, hlKey, r, g, b, cfg)
    end
    _G.MSUF_RoundedUF_OnGroupFrameApplied = function(frame, kind)
        if IsCombatLocked() then DeferApply(); return end
        if frame then ApplyToGroupFrame(frame, kind) end
    end
    _G.MSUF_RoundedUF_OnGroupHighlightChanged = function(border)
        return HandleGroupHighlightChanged(border)
    end
    _G.MSUF_RoundedUF_OnModulesApplied = function()
        ApplyAll() -- always (load-order safety)
    end
    if SUPPRESS_NATIVE_OUTLINE then
        _G.MSUF_RoundedUF_OnRareVisualsRefreshed = function(frame)
            if frame and RoundedUnitFramesEnabled() then
                if not IsCombatLocked() then
                    SuppressNativeOutlineNow(frame)
                    ApplyUnitRoundedEdge(frame, true)
                    ApplyUnitRoundedHoverEdge(frame, RoundedMouseoverEnabled())
                end
                HandleUnitHighlightChanged(frame, frame._msufHighlightActiveKey or frame._msufHighlightColorKey or 0,
                    frame._msufHighlightOutlineR, frame._msufHighlightOutlineG, frame._msufHighlightOutlineB)
            end
        end
    end
end
-- Module contract
local Module = {
    key   = "roundedUnitframes",
    name  = "Rounded frame texture",
    desc  = "Rounded mask texture for unit and group frame bar surfaces.",

    IsEnabled = function()
        return IsConfiguredEnabled()
    end,

    Init = function()
        if IsEnabled() then
            HookOnce()
            ApplyAll()
        end
    end,

    Enable = function()
        forceDisabled = false
        HookOnce()
        ApplyAll()
    end,

    Disable = function()
        forceDisabled = true
        HookOnce()
        ApplyAll() -- Frame apply paths handle disable cleanup.
    end,

    Apply = function()
        forceDisabled = false
        HookOnce()
        ApplyAll()
    end,
}

-- Bootstrap:
-- 1) Hook ASAP.
-- 2) Register with manager once MSUF is loaded.
-- 3) Apply once after login so unitframes exist.

do
    local f = CreateFrame and CreateFrame("Frame") or nil
    if f and f.RegisterEvent and f.SetScript then
        ns.__msufRoundedEventFrame = f
        f:RegisterEvent("ADDON_LOADED")
        f:RegisterEvent("PLAYER_LOGIN")
        f:SetScript("OnEvent", function(_, event, arg1)
            if event == "ADDON_LOADED" then
                -- When MSUF finishes loading, the module manager globals should exist.
                if arg1 == addonName or arg1 == "MidnightSimpleUnitFrames" then
                    if not ns.__msufRoundedUF_Registered then
                        local reg = (ns and ns.MSUF_RegisterModule) or _G.MSUF_RegisterModule
                        if type(reg) == "function" then
                            reg("roundedUnitframes", Module)
                            ns.__msufRoundedUF_Registered = true
                        end
                    end
                    if IsEnabled() then HookOnce() end
                    if f.UnregisterEvent then f:UnregisterEvent("ADDON_LOADED") end
                end
            elseif event == "PLAYER_LOGIN" then
                if f.UnregisterEvent then f:UnregisterEvent("PLAYER_LOGIN") end
                if IsEnabled() then
                    HookOnce()
                    -- Defer one tick: MSUF creates unitframes on PLAYER_LOGIN too.
                    if _G.C_Timer and _G.C_Timer.After then
                        _G.C_Timer.After(0, ApplyAll)
                    else
                        ApplyAll()
                    end
                end
            elseif event == "PLAYER_REGEN_ENABLED" then
                if ns.__msufRoundedPending then
                    if _G.C_Timer and _G.C_Timer.After then
                        _G.C_Timer.After(0, ApplyAll)
                    else
                        ApplyAll()
                    end
                end
            end
        end)
    end
end

-- Fallback direct registration (works if MSUF manager already exists).
if not ns.__msufRoundedUF_Registered then
    local reg = (ns and ns.MSUF_RegisterModule) or _G.MSUF_RegisterModule
    if type(reg) == "function" then
        reg("roundedUnitframes", Module)
        ns.__msufRoundedUF_Registered = true
    end
end

-- Expose helper for debugging / manual refresh.
_G.MSUF_ApplyRoundedUnitframes = function()
    forceDisabled = false
    if IsEnabled() then HookOnce() end
    ApplyAll()
end
