-- MSUF_GF_TooltipMouseover.lua - Group frame tooltip and mouseover highlight runtime
local _, ns = ...
ns = ns or (_G.MSUF_NS) or {}
_G.MSUF_NS = ns

local GF = ns.GF
if not GF then return end

local CreateFrame = _G.CreateFrame
local C_Timer = _G.C_Timer
local InCombatLockdown = _G.InCombatLockdown
local UnitExists = _G.UnitExists
local IsAltKeyDown = _G.IsAltKeyDown
local IsControlKeyDown = _G.IsControlKeyDown
local IsShiftKeyDown = _G.IsShiftKeyDown
local math_max = math.max

local function HLVal(kind, key)
    local fn = GF.HighlightValue
    if type(fn) == "function" then return fn(kind, key) end
    return nil
end
------------------------------------------------------------------------
-- Mouseover highlight
------------------------------------------------------------------------
local function _GF_GetHighlightColor()
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    if gen then
        local c = gen.highlightColor
        if c and c[1] then return c[1], c[2] or 1, c[3] or 1 end
        if type(c) == "string" then
            local colors = (ns and ns.MSUF_FONT_COLORS) or _G.MSUF_FONT_COLORS
            if colors and colors[c] then
                local cc = colors[c]
                return cc[1], cc[2], cc[3]
            end
        end
    end
    return 1, 1, 1
end

local function _GF_IsHighlightEnabled()
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    if gen and gen.highlightEnabled == false then return false end
    return true
end

local function _GF_EnsureHoverLine(hb, key)
    local lines = hb._msufGFHoverLines
    if not lines then
        lines = {}
        hb._msufGFHoverLines = lines
    end
    local t = lines[key]
    if not t and hb.CreateTexture then
        t = hb:CreateTexture(nil, "OVERLAY")
        t:SetTexture("Interface\\Buttons\\WHITE8x8")
        lines[key] = t
    end
    return t
end

local function _GF_StyleMouseoverHighlight(f, hb)
    if not (f and hb) then return end
    local kind = f._msufGFKind or "party"
    local sz = math_max(1, tonumber(HLVal(kind, "hlHoverSize")) or 1)
    local ofs = tonumber(HLVal(kind, "hlHoverOffset")) or 0
    local r, g, b = _GF_GetHighlightColor()
    local anchor = f.barGroup or f

    if hb.SetBackdrop then hb:SetBackdrop(nil) end
    if hb.SetClipsChildren then hb:SetClipsChildren(false) end

    if hb._msufGFHoverOffset ~= ofs or hb._msufGFHoverSize ~= sz then
        hb._msufGFHoverOffset = ofs
        hb._msufGFHoverSize = sz
        hb:ClearAllPoints()
        hb:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
        hb:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 0, 0)
    end

    local ext = ofs + sz
    local top = _GF_EnsureHoverLine(hb, "top")
    local bottom = _GF_EnsureHoverLine(hb, "bottom")
    local left = _GF_EnsureHoverLine(hb, "left")
    local right = _GF_EnsureHoverLine(hb, "right")
    if top then
        top:ClearAllPoints()
        top:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", -ext, ofs)
        top:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", ext, ofs)
        top:SetHeight(sz)
        top:SetVertexColor(r, g, b, 0.7)
        top:Show()
    end
    if bottom then
        bottom:ClearAllPoints()
        bottom:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", -ext, -ofs)
        bottom:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", ext, -ofs)
        bottom:SetHeight(sz)
        bottom:SetVertexColor(r, g, b, 0.7)
        bottom:Show()
    end
    if left then
        left:ClearAllPoints()
        left:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -ofs, ext)
        left:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMLEFT", -ofs, -ext)
        left:SetWidth(sz)
        left:SetVertexColor(r, g, b, 0.7)
        left:Show()
    end
    if right then
        right:ClearAllPoints()
        right:SetPoint("TOPLEFT", anchor, "TOPRIGHT", ofs, ext)
        right:SetPoint("BOTTOMLEFT", anchor, "BOTTOMRIGHT", ofs, -ext)
        right:SetWidth(sz)
        right:SetVertexColor(r, g, b, 0.7)
        right:Show()
    end

    if hb.SetFrameLevel and anchor.GetFrameLevel then
        local anchorLevel = anchor:GetFrameLevel() or 0
        local wantLevel = anchorLevel + 3
        local minTextLevel
        local layers = { f.nameTextLayer, f.healthTextLayer, f.powerTextLayer, f.statusTextLayer }
        for i = 1, #layers do
            local layer = layers[i]
            local level = layer and layer.GetFrameLevel and layer:GetFrameLevel()
            if level and (not minTextLevel or level < minTextLevel) then
                minTextLevel = level
            end
        end
        if minTextLevel and wantLevel >= minTextLevel then
            wantLevel = minTextLevel - 1
        end
        if wantLevel <= anchorLevel then
            wantLevel = anchorLevel + 1
        end
        if hb._msufGFHoverLevel ~= wantLevel then
            hb._msufGFHoverLevel = wantLevel
            hb:SetFrameLevel(wantLevel)
        end
    end
end
GF.StyleMouseoverHighlight = _GF_StyleMouseoverHighlight

local function EnsureMouseoverHighlight(f)
    if not _GF_IsHighlightEnabled() then return nil end
    local hb = f._msufGFHoverBorder
    if hb then
        _GF_StyleMouseoverHighlight(f, hb)
        return hb
    end
    local anchor = f.barGroup or f
    hb = CreateFrame("Frame", nil, anchor, "BackdropTemplate")
    hb:EnableMouse(false)
    _GF_StyleMouseoverHighlight(f, hb)
    hb:Hide()
    f._msufGFHoverBorder = hb
    return hb
end

------------------------------------------------------------------------
-- Tooltip + Highlight hooks
------------------------------------------------------------------------
local _tooltipPendingToken = 0 -- invalidates deferred tooltip callbacks
local _tooltipTarget  -- frame awaiting tooltip
local _Debug = ns and ns.Debug

local function DebugHover(message, ...)
    if _Debug and type(_Debug.PrintGFHover) == "function" then
        _Debug.PrintGFHover(message, ...)
    end
end

local function OnEnter(f)
    DebugHover("GF OnEnter frame=%s unit=%s kind=%s", tostring(f and f:GetName() or "<anon>"), tostring(f and f.unit or "nil"), tostring(f and f._msufGFKind or "party"))
    -- Mouseover highlight
    local roundedHandled = false
    if _G.MSUF_RoundedUF_Active == true and f and f._msufRUF_SuppressGFHover == true then
        local roundedHover = _G.MSUF_RoundedUF_OnGroupMouseover
        if type(roundedHover) == "function" then roundedHandled = roundedHover(f, true) == true end
    end
    if not roundedHandled then
        local hb = EnsureMouseoverHighlight(f)
        if hb then hb:Show() end
    end
    -- Cancel any pending tooltip for a different frame
    _tooltipPendingToken = _tooltipPendingToken + 1
    _tooltipTarget = f
    -- Tooltip (throttled 150ms)
    if not f.unit or not UnitExists(f.unit) then return end
    local conf = GF.GetConf(f._msufGFKind or "party")
    local mode = conf.tooltipMode or "ALWAYS"
    if mode == "NEVER" then
        DebugHover("GF tooltip blocked frame=%s reason=mode-never", tostring(f and f:GetName() or "<anon>"))
        return
    end
    if mode == "OOC" and InCombatLockdown() then
        DebugHover("GF tooltip blocked frame=%s reason=in-combat-ooc-mode", tostring(f and f:GetName() or "<anon>"))
        return
    end
    if mode == "MODIFIER" then
        local mod = conf.tooltipModifier or "ALT"
        if mod == "ALT"   and not IsAltKeyDown() then
            DebugHover("GF tooltip blocked frame=%s reason=alt-not-held", tostring(f and f:GetName() or "<anon>"))
            return
        end
        if mod == "CTRL"  and not IsControlKeyDown() then
            DebugHover("GF tooltip blocked frame=%s reason=ctrl-not-held", tostring(f and f:GetName() or "<anon>"))
            return
        end
        if mod == "SHIFT" and not IsShiftKeyDown() then
            DebugHover("GF tooltip blocked frame=%s reason=shift-not-held", tostring(f and f:GetName() or "<anon>"))
            return
        end
    end
    local token = _tooltipPendingToken
    C_Timer.After(0.15, function()
        if _tooltipPendingToken ~= token then
            DebugHover("GF tooltip canceled frame=%s reason=token-changed", tostring(f and f:GetName() or "<anon>"))
            return
        end
        if _tooltipTarget ~= f then
            DebugHover("GF tooltip canceled frame=%s reason=target-changed", tostring(f and f:GetName() or "<anon>"))
            return
        end
        if not f.unit or not UnitExists(f.unit) then
            DebugHover("GF tooltip canceled frame=%s reason=unit-gone", tostring(f and f:GetName() or "<anon>"))
            return
        end
        DebugHover("GF tooltip firing frame=%s unit=%s", tostring(f and f:GetName() or "<anon>"), tostring(f and f.unit or "nil"))
        local tips = ns and ns.Tooltips
        if tips and type(tips.ShowUnit) == "function" then
            tips.ShowUnit(f, f.unit)
        elseif _G.GameTooltip and not _G.GameTooltip:IsForbidden() then
            local gt = _G.GameTooltip
            gt:SetOwner(f, "ANCHOR_RIGHT")
            gt:SetUnit(f.unit)
            gt:Show()
        end
    end)
end

local function OnLeave(f)
    DebugHover("GF OnLeave frame=%s unit=%s kind=%s", tostring(f and f:GetName() or "<anon>"), tostring(f and f.unit or "nil"), tostring(f and f._msufGFKind or "party"))
    -- Cancel pending tooltip
    _tooltipPendingToken = _tooltipPendingToken + 1
    _tooltipTarget = nil
    -- Hide highlight
    if f._msufGFHoverBorder then f._msufGFHoverBorder:Hide() end
    if _G.MSUF_RoundedUF_Active == true and f and f._msufRUF_SuppressGFHover == true then
        local roundedHover = _G.MSUF_RoundedUF_OnGroupMouseover
        if type(roundedHover) == "function" then roundedHover(f, false) end
    end
    -- Hide tooltip
    local tips = ns and ns.Tooltips
    if tips and type(tips.HideUnit) == "function" then
        tips.HideUnit(f)
    elseif _G.GameTooltip and not _G.GameTooltip:IsForbidden() then
        _G.GameTooltip:Hide()
    end
end

function GF.RetireTooltipState(f)
    if _tooltipTarget == f then
        _tooltipPendingToken = _tooltipPendingToken + 1
        _tooltipTarget = nil
    end
end

-- Hook into GF_InitButton from Phase 1
local _origInit = _G.MSUF_GF_InitButton
if type(_origInit) == "function" then
    _G.MSUF_GF_InitButton = function(f, kind)
        _origInit(f, kind)
        -- Add tooltip scripts
        f:SetScript("OnEnter", OnEnter)
        f:SetScript("OnLeave", OnLeave)
        if GF.ClickCastEnabled then GF.RegisterClickCastFrame(f, true) end
        -- GF frames do NOT use the main Alpha module.
        -- Range fade is handled exclusively by ApplyRangeFade Ã¢â€ â€™ SetAlphaFromBoolean.
        -- The Alpha module (MSUF_ApplyUnitAlpha) would override SetAlphaFromBoolean
        -- with SetAlpha(1), killing the range fade.
    end
end

