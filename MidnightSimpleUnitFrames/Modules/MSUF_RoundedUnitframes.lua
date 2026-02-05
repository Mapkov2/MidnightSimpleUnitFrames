--[[Perfy has instrumented this file]] local Perfy_GetTime, Perfy_Trace, Perfy_Trace_Passthrough = Perfy_GetTime, Perfy_Trace, Perfy_Trace_Passthrough; Perfy_Trace(Perfy_GetTime(), "Enter", "(main chunk) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua"); -- MSUF Module: Rounded Unitframes (Superellipse)
--
-- What it does (when enabled):
-- - Rounds the *actual visible unitframe content* by masking ALL relevant textures
--   (frame BG + HP/Power/Absorb fills + HP gradient overlays) with the same
--   superellipse mask used across MSUF.
-- - Draws a subtle superellipse border (3-slice) on top, matching the SlashMenu pill style.
--
-- NOTE (why v1 felt "does nothing"):
-- Unitframes use additional overlay textures (HP gradients etc.) that were NOT masked.
-- Those square overlays will visually "re-square" the corners even if the StatusBar fill
-- is masked. This version masks *everything that can touch the corners*.
--
-- Hard requirements:
-- - This file must be loaded by WoW (listed in a .toc, or shipped as its own addon).
-- - No OnUpdate/tickers; only event/hooks + one-shot C_Timer.After(0) for post-login ordering.
-- - 0 regression unless the module is enabled.

local addonName, ns = ...
ns = ns or {}

-- IMPORTANT: Use the *folder* name (addonName) for asset paths.
local MASK_PATH = "Interface\\AddOns\\" .. tostring(addonName or "MidnightSimpleUnitFrames") .. "\\Media\\superellipse.png"
local SE_TEX    = "Interface/AddOns/" .. tostring(addonName or "MidnightSimpleUnitFrames") .. "/Media/superellipse.tga"

-- v3 behavior (requested): provide the rounded superellipse silhouette ONLY.
-- - Suppress any existing square bar outline/frames while enabled.
-- - Do not draw an extra module border/outline (pure rounding).
-- - Reduce edge artifacts by disabling texel snapping and clamping the mask.
local DRAW_MODULE_BORDER = false
local SUPPRESS_NATIVE_OUTLINE = true

local function EnsureDB() Perfy_Trace(Perfy_GetTime(), "Enter", "EnsureDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:33:6");
    if type(_G.EnsureDB) == "function" then
        _G.EnsureDB()
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "EnsureDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:33:6"); end

local function IsEnabled() Perfy_Trace(Perfy_GetTime(), "Enter", "IsEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:39:6");
    local db = _G.MSUF_DB
    return Perfy_Trace_Passthrough("Leave", "IsEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:39:6", (db and db.general and db.general.roundedUnitframes == true) and true or false)
end

-- ------------------------------------------------------------
-- Superellipse shell (3-slice: left cap / stretch / right cap)
-- ------------------------------------------------------------

local function SE_SnapOff(tex) Perfy_Trace(Perfy_GetTime(), "Enter", "SE_SnapOff file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:48:6");
    if tex and tex.SetSnapToPixelGrid then
        tex:SetSnapToPixelGrid(false)
        if tex.SetTexelSnappingBias then tex:SetTexelSnappingBias(0) end
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "SE_SnapOff file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:48:6"); end

local function SE_EnsureGroup(frame, key, layer, subLevel) Perfy_Trace(Perfy_GetTime(), "Enter", "SE_EnsureGroup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:55:6");
    if not (frame and frame.CreateTexture) then Perfy_Trace(Perfy_GetTime(), "Leave", "SE_EnsureGroup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:55:6"); return nil end
    if frame[key] then return Perfy_Trace_Passthrough("Leave", "SE_EnsureGroup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:55:6", frame[key]) end

    local g = {}
    g.L = frame:CreateTexture(nil, layer, nil, subLevel or 0)
    g.M = frame:CreateTexture(nil, layer, nil, subLevel or 0)
    g.R = frame:CreateTexture(nil, layer, nil, subLevel or 0)
    g._parts = { g.L, g.M, g.R }

    g.L:SetTexture(SE_TEX)
    g.M:SetTexture(SE_TEX)
    g.R:SetTexture(SE_TEX)

    -- Atlas UVs: 128x64, L=0..0.25, M=0.25..0.75, R=0.75..1
    g.L:SetTexCoord(0.0, 0.25, 0.0, 1.0)
    g.M:SetTexCoord(0.25, 0.75, 0.0, 1.0)
    g.R:SetTexCoord(0.75, 1.0, 0.0, 1.0)

    SE_SnapOff(g.L); SE_SnapOff(g.M); SE_SnapOff(g.R)

    function g:SetVertexColor(r, gg, b, a) Perfy_Trace(Perfy_GetTime(), "Enter", "g:SetVertexColor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:76:4");
        for i = 1, #self._parts do
            local t = self._parts[i]
            if t and t.SetVertexColor then t:SetVertexColor(r, gg, b, a) end
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "g:SetVertexColor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:76:4"); end
    function g:Hide() Perfy_Trace(Perfy_GetTime(), "Enter", "g:Hide file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:82:4");
        for i = 1, #self._parts do
            local t = self._parts[i]
            if t and t.Hide then t:Hide() end
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "g:Hide file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:82:4"); end
    function g:Show() Perfy_Trace(Perfy_GetTime(), "Enter", "g:Show file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:88:4");
        for i = 1, #self._parts do
            local t = self._parts[i]
            if t and t.Show then t:Show() end
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "g:Show file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:88:4"); end

    frame[key] = g
    Perfy_Trace(Perfy_GetTime(), "Leave", "SE_EnsureGroup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:55:6"); return g
end

local function SE_Layout(frameOrAnchor, g, pad) Perfy_Trace(Perfy_GetTime(), "Enter", "SE_Layout file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:99:6");
    if not (frameOrAnchor and g and g.L and g.M and g.R) then Perfy_Trace(Perfy_GetTime(), "Leave", "SE_Layout file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:99:6"); return end
    pad = tonumber(pad) or 0

    local w = (frameOrAnchor.GetWidth and frameOrAnchor:GetWidth()) or 0
    local h = (frameOrAnchor.GetHeight and frameOrAnchor:GetHeight()) or 0
    if w <= 0 or h <= 0 then Perfy_Trace(Perfy_GetTime(), "Leave", "SE_Layout file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:99:6"); return end

    local innerW = math.max(1, w - pad * 2)
    local innerH = math.max(1, h - pad * 2)

    -- cap width = radius
    local r = math.floor(innerH * 0.5 + 0.5)
    local capW = math.min(r, math.floor(innerW * 0.5))

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
Perfy_Trace(Perfy_GetTime(), "Leave", "SE_Layout file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:99:6"); end

local function SE_EnsureShell(f) Perfy_Trace(Perfy_GetTime(), "Enter", "SE_EnsureShell file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:130:6");
    if not f then Perfy_Trace(Perfy_GetTime(), "Leave", "SE_EnsureShell file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:130:6"); return nil end
    if f._msufRoundedShell then return Perfy_Trace_Passthrough("Leave", "SE_EnsureShell file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:130:6", f._msufRoundedShell) end

    local shell = {}
    -- Optional: module border. (v3 default: disabled; rounding only)
    shell.border = SE_EnsureGroup(f, "_msufRUF_Border3", "OVERLAY", 0)
    shell._hooked = false

    f._msufRoundedShell = shell
    Perfy_Trace(Perfy_GetTime(), "Leave", "SE_EnsureShell file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:130:6"); return shell
end

local function SE_ApplyShellVisuals(f, enabled) Perfy_Trace(Perfy_GetTime(), "Enter", "SE_ApplyShellVisuals file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:143:6");
    local shell = SE_EnsureShell(f)
    if not shell then Perfy_Trace(Perfy_GetTime(), "Leave", "SE_ApplyShellVisuals file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:143:6"); return end

    -- v3: don't draw a border at all (pure rounding).
    if not DRAW_MODULE_BORDER then
        if shell.border then shell.border:Hide() end
        Perfy_Trace(Perfy_GetTime(), "Leave", "SE_ApplyShellVisuals file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:143:6"); return
    end
    if not shell.border then Perfy_Trace(Perfy_GetTime(), "Leave", "SE_ApplyShellVisuals file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:143:6"); return end

    if not enabled then
        shell.border:Hide()
        Perfy_Trace(Perfy_GetTime(), "Leave", "SE_ApplyShellVisuals file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:143:6"); return
    end

    -- Border tint: reuse MSUF theme if present, otherwise a subtle blueish edge.
    local br, bgc, bb, ba = 0.20, 0.40, 0.85, 0.90
    local theme = _G.MSUF_THEME
    if type(theme) == "table" and theme.edgeR then
        br, bgc, bb, ba = theme.edgeR or br, theme.edgeG or bgc, theme.edgeB or bb, theme.edgeA or ba
        -- Slightly brighter than frame border, like the nav pills
        br = math.min(1, (br or 0) * 1.25)
        bgc = math.min(1, (bgc or 0) * 1.25)
        bb = math.min(1, (bb or 0) * 1.18)
        ba = math.min(1, (ba or 0) + 0.05)
    end

    shell.border:SetVertexColor(br, bgc, bb, ba)

    -- Layout: use the same inner rect as the frame background (2px inset)
    local anchor = f.bg or f
    SE_Layout(anchor, shell.border, 0)

    shell.border:Show()

    if f.HookScript and not shell._hooked then
        shell._hooked = true
        f:HookScript("OnSizeChanged", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:181:38");
            local a = f.bg or f
            SE_Layout(a, shell.border, 0)
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:181:38"); end)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "SE_ApplyShellVisuals file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:143:6"); end

-- ------------------------------------------------------------
-- Masking helpers
-- ------------------------------------------------------------

local function EnsureFrameMask(f) Perfy_Trace(Perfy_GetTime(), "Enter", "EnsureFrameMask file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:192:6");
    if not (f and type(f.CreateMaskTexture) == "function") then Perfy_Trace(Perfy_GetTime(), "Leave", "EnsureFrameMask file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:192:6"); return nil end
    local m = f._msufRUF_Mask
    if not m then
        m = f:CreateMaskTexture(nil, "ARTWORK")
        -- Reduce grey/fringing artifacts at the edges.
        SE_SnapOff(m)
        f._msufRUF_Mask = m
    end

    local anchor = f.bg or f
    if not f._msufRUF_MaskAnchor or f._msufRUF_MaskAnchor ~= anchor then
        f._msufRUF_MaskAnchor = anchor
        if m.ClearAllPoints then m:ClearAllPoints() end
        -- Use clamp-to-black-additive to avoid edge bleed from filtering.
        m:SetTexture(MASK_PATH, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m:SetAllPoints(anchor)
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "EnsureFrameMask file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:192:6"); return m
end

local function ClearAllMasks(f) Perfy_Trace(Perfy_GetTime(), "Enter", "ClearAllMasks file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:213:6");
    if not f then Perfy_Trace(Perfy_GetTime(), "Leave", "ClearAllMasks file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:213:6"); return end
    local m = f._msufRUF_Mask
    local masked = f._msufRUF_MaskedTextures
    if m and masked then
        for tex in pairs(masked) do
            if tex and type(tex.RemoveMaskTexture) == "function" then
                tex:RemoveMaskTexture(m)
            end
        end
    end
    f._msufRUF_MaskedTextures = nil
Perfy_Trace(Perfy_GetTime(), "Leave", "ClearAllMasks file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:213:6"); end

local function MaskTexture(f, tex) Perfy_Trace(Perfy_GetTime(), "Enter", "MaskTexture file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:227:6");
    if not (f and tex) then Perfy_Trace(Perfy_GetTime(), "Leave", "MaskTexture file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:227:6"); return end
    if type(tex.AddMaskTexture) ~= "function" then Perfy_Trace(Perfy_GetTime(), "Leave", "MaskTexture file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:227:6"); return end
    local m = EnsureFrameMask(f)
    if not m then Perfy_Trace(Perfy_GetTime(), "Leave", "MaskTexture file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:227:6"); return end

    f._msufRUF_MaskedTextures = f._msufRUF_MaskedTextures or {}
    if f._msufRUF_MaskedTextures[tex] then Perfy_Trace(Perfy_GetTime(), "Leave", "MaskTexture file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:227:6"); return end

    tex:AddMaskTexture(m)
    f._msufRUF_MaskedTextures[tex] = true
Perfy_Trace(Perfy_GetTime(), "Leave", "MaskTexture file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:227:6"); end

-- ------------------------------------------------------------
-- Suppress square outlines/borders while enabled (v3 request)
-- ------------------------------------------------------------

local function SuppressNativeOutlineNow(f) Perfy_Trace(Perfy_GetTime(), "Enter", "SuppressNativeOutlineNow file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:244:6");
    if not (SUPPRESS_NATIVE_OUTLINE and f) then Perfy_Trace(Perfy_GetTime(), "Leave", "SuppressNativeOutlineNow file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:244:6"); return end

    -- Unitframe bar outline (black square border around HB+PB).
    local o = f._msufBarOutline
    if o and o.frame and o.frame.Hide then
        o.frame:Hide()
    end

    -- Legacy border texture (some builds keep a spare reference).
    if f.border and f.border.Hide then
        f.border:Hide()
    end

    -- Hover highlight border (square): keep feature, but suppress it while rounding is enabled.
    if f.highlightBorder and f.highlightBorder.Hide then
        f.highlightBorder:Hide()
    end

    if f.HookScript and not f._msufRUF_HighlightHooked then
        f._msufRUF_HighlightHooked = true
        f:HookScript("OnEnter", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:265:32");
            if IsEnabled() and self.highlightBorder and self.highlightBorder.Hide then
                self.highlightBorder:Hide()
            end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:265:32"); end)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "SuppressNativeOutlineNow file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:244:6"); end

-- ------------------------------------------------------------
-- Apply/remove
-- ------------------------------------------------------------

local function ApplyToFrame(f) Perfy_Trace(Perfy_GetTime(), "Enter", "ApplyToFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:277:6");
    if not f then Perfy_Trace(Perfy_GetTime(), "Leave", "ApplyToFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:277:6"); return end

    local enabled = IsEnabled()

    -- Shell: show/hide + keep colors in sync.
    SE_ApplyShellVisuals(f, enabled)

    if not enabled then
        ClearAllMasks(f)
        -- Restore the original square outline behavior immediately (0 regression when disabled).
        if SUPPRESS_NATIVE_OUTLINE and type(_G.MSUF_RefreshRareBarVisuals) == "function" then
            _G.MSUF_RefreshRareBarVisuals(f)
        end
        Perfy_Trace(Perfy_GetTime(), "Leave", "ApplyToFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:277:6"); return
    end

    -- v3: hide square outlines/borders while rounding is enabled.
    SuppressNativeOutlineNow(f)

    -- Bar textures can be swapped at runtime (texture dropdown etc.), so rebuild the mask list.
    ClearAllMasks(f)

    -- Frame/background (inner rect) – this is what users perceive as the unitframe silhouette.
    if f.bg then
        MaskTexture(f, f.bg)
    end

    -- Health bar fill + background
    if f.hpBar and type(f.hpBar.GetStatusBarTexture) == "function" then
        local hbFill = f.hpBar:GetStatusBarTexture()
        if hbFill then MaskTexture(f, hbFill) end
    end
    if f.hpBarBG then
        MaskTexture(f, f.hpBarBG)
    end

    -- HP gradient overlays (these were the main reason corners still looked square)
    local grads = f.hpGradients
    if type(grads) == "table" then
        if grads.left  then MaskTexture(f, grads.left)  end
        if grads.right then MaskTexture(f, grads.right) end
        if grads.up    then MaskTexture(f, grads.up)    end
        if grads.down  then MaskTexture(f, grads.down)  end
    end

    -- Absorb overlays
    if f.absorbBar and type(f.absorbBar.GetStatusBarTexture) == "function" then
        local t = f.absorbBar:GetStatusBarTexture()
        if t then MaskTexture(f, t) end
    end
    if f.healAbsorbBar and type(f.healAbsorbBar.GetStatusBarTexture) == "function" then
        local t = f.healAbsorbBar:GetStatusBarTexture()
        if t then MaskTexture(f, t) end
    end

    -- Power bar fill + background
    if f.targetPowerBar and type(f.targetPowerBar.GetStatusBarTexture) == "function" then
        local pbFill = f.targetPowerBar:GetStatusBarTexture()
        if pbFill then MaskTexture(f, pbFill) end
    end
    if f.powerBarBG then
        MaskTexture(f, f.powerBarBG)
    end

    -- Portrait can touch outer corners depending on layout, so mask it too (safe + no visual change beyond rounding).
    if f.portrait then
        MaskTexture(f, f.portrait)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "ApplyToFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:277:6"); end

local function ForEachUnitFrame(fn) Perfy_Trace(Perfy_GetTime(), "Enter", "ForEachUnitFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:348:6");
    local frames = _G.MSUF_UnitFrames
    if type(frames) ~= "table" then Perfy_Trace(Perfy_GetTime(), "Leave", "ForEachUnitFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:348:6"); return end
    for _, f in pairs(frames) do
        if type(fn) == "function" then
            fn(f)
        end
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "ForEachUnitFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:348:6"); end

local function ApplyAll() Perfy_Trace(Perfy_GetTime(), "Enter", "ApplyAll file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:358:6");
    EnsureDB()
    ForEachUnitFrame(ApplyToFrame)
Perfy_Trace(Perfy_GetTime(), "Leave", "ApplyAll file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:358:6"); end

-- ------------------------------------------------------------
-- Hooks / bootstrap
-- ------------------------------------------------------------

local function HookOnce() Perfy_Trace(Perfy_GetTime(), "Enter", "HookOnce file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:367:6");
    if ns.__msufRoundedUF_Hooked then Perfy_Trace(Perfy_GetTime(), "Leave", "HookOnce file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:367:6"); return end
    ns.__msufRoundedUF_Hooked = true

    if type(_G.hooksecurefunc) == "function" then
        if type(_G.MSUF_UpdateAllBarTextures) == "function" then
            _G.hooksecurefunc("MSUF_UpdateAllBarTextures", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:373:59");
                if IsEnabled() then ApplyAll() end
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:373:59"); end)
        end
        if type(_G.MSUF_UpdateAllUnitframesNow) == "function" then
            _G.hooksecurefunc("MSUF_UpdateAllUnitframesNow", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:378:61");
                if IsEnabled() then ApplyAll() end
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:378:61"); end)
        end
        if type(_G.MSUF_ApplyModules) == "function" then
            _G.hooksecurefunc("MSUF_ApplyModules", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:383:51");
                -- Allows this module to work even if it wasn't registered due to load order.
                ApplyAll()
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:383:51"); end)
        end

        -- Keep square unitframe outlines hidden while the module is enabled.
        if SUPPRESS_NATIVE_OUTLINE and type(_G.MSUF_RefreshRareBarVisuals) == "function" then
            _G.hooksecurefunc("MSUF_RefreshRareBarVisuals", function(frame) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:391:60");
                if frame and IsEnabled() then
                    SuppressNativeOutlineNow(frame)
                end
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:391:60"); end)
        end
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "HookOnce file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:367:6"); end
-- Module contract
local Module = {
    key   = "roundedUnitframes",
    name  = "Rounded unitframes",
    desc  = "Superellipse-rounded unitframe silhouette (no border/outline; MSUF only).",

    IsEnabled = function() Perfy_Trace(Perfy_GetTime(), "Enter", "Module.IsEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:405:16");
        EnsureDB()
        return Perfy_Trace_Passthrough("Leave", "Module.IsEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:405:16", IsEnabled())
    end,

    Init = function() Perfy_Trace(Perfy_GetTime(), "Enter", "Module.Init file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:410:11");
        HookOnce()
    Perfy_Trace(Perfy_GetTime(), "Leave", "Module.Init file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:410:11"); end,

    Enable = function() Perfy_Trace(Perfy_GetTime(), "Enter", "Module.Enable file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:414:13");
        HookOnce()
        ApplyAll()
    Perfy_Trace(Perfy_GetTime(), "Leave", "Module.Enable file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:414:13"); end,

    Disable = function() Perfy_Trace(Perfy_GetTime(), "Enter", "Module.Disable file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:419:14");
        HookOnce()
        ApplyAll() -- ApplyToFrame handles disable cleanup
    Perfy_Trace(Perfy_GetTime(), "Leave", "Module.Disable file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:419:14"); end,

    Apply = function() Perfy_Trace(Perfy_GetTime(), "Enter", "Module.Apply file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:424:12");
        HookOnce()
        ApplyAll()
    Perfy_Trace(Perfy_GetTime(), "Leave", "Module.Apply file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:424:12"); end,
}

-- Bootstrap:
-- 1) Hook ASAP.
-- 2) Register with manager once MSUF is loaded.
-- 3) Apply once after login so unitframes exist.

HookOnce()

do
    local f = CreateFrame and CreateFrame("Frame") or nil
    if f and f.RegisterEvent and f.SetScript then
        f:RegisterEvent("ADDON_LOADED")
        f:RegisterEvent("PLAYER_LOGIN")
        f:SetScript("OnEvent", function(_, event, arg1) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:442:31");
            if event == "ADDON_LOADED" then
                -- When MSUF finishes loading, the module manager globals should exist.
                if arg1 == addonName or arg1 == "MidnightSimpleUnitFrames" then
                    HookOnce()
                    if not ns.__msufRoundedUF_Registered then
                        local reg = (ns and ns.MSUF_RegisterModule) or _G.MSUF_RegisterModule
                        if type(reg) == "function" then
                            reg("roundedUnitframes", Module)
                            ns.__msufRoundedUF_Registered = true
                        end
                    end
                end
            elseif event == "PLAYER_LOGIN" then
                HookOnce()
                -- Defer one tick: MSUF creates unitframes on PLAYER_LOGIN too.
                if _G.C_Timer and _G.C_Timer.After then
                    _G.C_Timer.After(0, ApplyAll)
                else
                    ApplyAll()
                end
            end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua:442:31"); end)
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
_G.MSUF_ApplyRoundedUnitframes = ApplyAll

Perfy_Trace(Perfy_GetTime(), "Leave", "(main chunk) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Modules/MSUF_RoundedUnitframes.lua");