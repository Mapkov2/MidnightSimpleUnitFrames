-- MSUF_GF_Masque.lua - Masque integration for Group Frames aura icons
-- Separate Masque group from A2 (UF auras). Registers Icon + Cooldown only.
-- Count FontString is managed by GF and is never passed to Masque.

local _, ns = ...
ns = ns or (_G.MSUF_NS) or {}
_G.MSUF_NS = ns

local GF = ns.GF
if not GF then return end

local C_Timer = _G.C_Timer

local MSQ_GROUP
local _btnCount = 0
local _lastReskinCount = -1
local _reskinQueued = false
local _forceReskin = false

local function IsMasqueLoaded()
    if _G.C_AddOns and _G.C_AddOns.IsAddOnLoaded then
        return C_AddOns.IsAddOnLoaded("Masque") == true
    end
    return _G.IsAddOnLoaded and _G.IsAddOnLoaded("Masque") == true
end

local function GetMasqueLib()
    local LS = _G.LibStub
    if not LS then return nil end
    local ok, lib = pcall(LS, "Masque", true)
    return ok and lib or nil
end

local function EnsureGroup()
    if MSQ_GROUP then return MSQ_GROUP end
    if not IsMasqueLoaded() then return nil end
    local lib = GetMasqueLib()
    if not lib then return nil end
    MSQ_GROUP = lib:Group("MidnightSimpleUnitFrames", "Group Frames")
    return MSQ_GROUP
end

------------------------------------------------------------------------
local function ReskinNow()
    _reskinQueued = false
    local g = MSQ_GROUP
    if not g then return end
    if not _forceReskin and _btnCount == _lastReskinCount then return end
    _forceReskin = false
    _lastReskinCount = _btnCount
    if g.ReSkin then pcall(g.ReSkin, g)
    elseif g.Reskin then pcall(g.Reskin, g)
    elseif g.ReSkinAllButtons then pcall(g.ReSkinAllButtons, g) end
end

local function RequestReskin()
    if _reskinQueued then return end
    _reskinQueued = true
    if _G.MSUF_ScheduleOnce then
        _G.MSUF_ScheduleOnce("GF_MASQUE_RESKIN", ReskinNow)
    elseif C_Timer and C_Timer.After then
        C_Timer.After(0, ReskinNow)
    else
        ReskinNow()
    end
end

------------------------------------------------------------------------
local function GetIconKind(icon, explicitKind)
    if explicitKind then return explicitKind end
    if not icon then return nil end
    local owner = icon._msufGFOwner
    if owner and owner._msufGFKind then return owner._msufGFKind end
    return icon._msufGFMasqueKind
end

local function IsKindEnabled(kind)
    if not kind then return false end
    local conf = GF.GetConf and GF.GetConf(kind)
    if not conf or conf.masqueEnabled ~= true then return false end
    return EnsureGroup() ~= nil
end

local function SyncOverlayLevels(icon)
    if not icon then return end
    local base = icon:GetFrameLevel() or 0
    if icon.cooldown and icon.cooldown.GetFrameLevel then
        local lvl = icon.cooldown:GetFrameLevel() or 0
        if lvl > base then base = lvl end
    end

    local cp = icon.count and icon.count:GetParent()
    if cp and cp ~= icon and cp.SetFrameLevel then
        cp:SetFrameLevel(base + 10)
    end
    if icon._cdPreviewFrame and icon._cdPreviewFrame.SetFrameLevel then
        icon._cdPreviewFrame:SetFrameLevel(base + 10)
    end
    if icon._cdText and icon._cdText.SetDrawLayer then
        icon._cdText:SetDrawLayer("OVERLAY", 3)
    end
    if icon._stkText and icon._stkText.SetDrawLayer then
        icon._stkText:SetDrawLayer("OVERLAY", 3)
    end
end

------------------------------------------------------------------------
GF.Masque = {}

function GF.Masque.IsEnabled(kind)
    if kind then return IsKindEnabled(kind) end
    return IsKindEnabled("party") or IsKindEnabled("raid") or IsKindEnabled("mythicraid")
end

function GF.Masque.IconUsesMasque(icon, kind)
    if not icon or icon._msufGFMsqAdded ~= true then return false end
    return IsKindEnabled(GetIconKind(icon, kind))
end

function GF.Masque.AddButton(icon, kind)
    if not icon then return false end
    kind = GetIconKind(icon, kind)
    if kind then icon._msufGFMasqueKind = kind end
    if not IsKindEnabled(kind) then return false end

    local g = EnsureGroup()
    if not g then return false end

    -- Icon + Cooldown only. Count/text overlays stay owned by MSUF.
    if not icon._msufGFMsqRgn then icon._msufGFMsqRgn = {} end
    local r = icon._msufGFMsqRgn
    r.Icon     = icon.texture or icon._tex
    r.Cooldown = icon.cooldown
    r.Count    = nil

    if icon._msufGFMsqAdded then
        SyncOverlayLevels(icon)
        return true
    end

    local ok = pcall(g.AddButton, g, icon, r)
    if ok then
        icon._msufGFMsqAdded = true
        _btnCount = _btnCount + 1
        SyncOverlayLevels(icon)
        RequestReskin()
        return true
    end
    return false
end

function GF.Masque.RemoveButton(icon)
    if not icon then return end
    local g = MSQ_GROUP
    if g and icon._msufGFMsqAdded then
        if g.RemoveButton then pcall(g.RemoveButton, g, icon) end
        _btnCount = _btnCount > 0 and (_btnCount - 1) or 0
        _forceReskin = true
        RequestReskin()
    end
    icon._msufGFMsqAdded = nil
    icon._msufGFMsqSize = nil
end

function GF.Masque.SyncIconGeometry(icon, size, kind)
    if not icon then return false end
    kind = GetIconKind(icon, kind)
    if kind then icon._msufGFMasqueKind = kind end

    if not IsKindEnabled(kind) then
        if icon._msufGFMsqAdded then
            GF.Masque.RemoveButton(icon)
        end
        return false
    end

    if not GF.Masque.AddButton(icon, kind) then return false end

    size = tonumber(size) or (icon.GetWidth and icon:GetWidth()) or 0
    if size > 0 then
        local changed = (icon._msufGFMsqSize ~= size)
        icon._msufGFMsqSize = size
        if changed then
            icon:SetSize(size, size)
            if icon.cooldown then
                icon.cooldown:ClearAllPoints()
                icon.cooldown:SetAllPoints(icon)
            end
            _forceReskin = true
            _lastReskinCount = -1
            RequestReskin()
        end
    end

    SyncOverlayLevels(icon)
    return true
end

function GF.Masque.ForceReskin()
    _forceReskin = true
    _lastReskinCount = -1
    RequestReskin()
end

function GF.Masque.ReskinAllIcons()
    if not GF.frames then return end
    local POOLS = { "_msufAuraPool_buff", "_msufAuraPool_debuff", "_msufAuraPool_externals" }
    GF.ForEachFrame(function(f)
        for _, pk in ipairs(POOLS) do
            local pool = f[pk]
            if pool then
                for i = 1, #pool do
                    if pool[i] then
                        GF.Masque.SyncIconGeometry(pool[i], pool[i]._msufCachedSz)
                    end
                end
            end
        end
    end)
    GF.Masque.ForceReskin()
end

GF.Masque.RequestReskin = RequestReskin
