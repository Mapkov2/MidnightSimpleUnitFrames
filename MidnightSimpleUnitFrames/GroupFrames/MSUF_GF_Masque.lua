-- MSUF_GF_Masque.lua — Masque integration for Group Frames aura icons
-- Separate Masque group from A2 (UF auras). Registers Icon + Cooldown ONLY.
-- Count FontString is managed by GF — NEVER passed to Masque.
-- Zero cost when Masque absent or masqueEnabled=false.

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
    if _btnCount == _lastReskinCount then return end
    _lastReskinCount = _btnCount
    if g.ReSkin then pcall(g.ReSkin, g)
    elseif g.Reskin then pcall(g.Reskin, g) end
end

local function RequestReskin()
    if _reskinQueued then return end
    _reskinQueued = true
    C_Timer.After(0, ReskinNow)
end

------------------------------------------------------------------------
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
end

------------------------------------------------------------------------
GF.Masque = {}

function GF.Masque.IsEnabled()
    local conf = GF.GetConf and GF.GetConf("party")
    if not conf or conf.masqueEnabled ~= true then return false end
    return EnsureGroup() ~= nil
end

function GF.Masque.AddButton(icon)
    if not icon then return false end
    local owner = icon._msufGFOwner
    local kind = owner and owner._msufGFKind or "party"
    local conf = GF.GetConf and GF.GetConf(kind)
    if not conf or conf.masqueEnabled ~= true then return false end

    local g = EnsureGroup()
    if not g then return false end

    -- Build regions: Icon + Cooldown ONLY (NEVER Count)
    if not icon._msufGFMsqRgn then icon._msufGFMsqRgn = {} end
    local r = icon._msufGFMsqRgn
    r.Icon     = icon.texture
    r.Cooldown = icon.cooldown
    r.Count    = nil

    if icon._msufGFMsqAdded then return true end

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
        pcall(g.RemoveButton, g, icon)
        _btnCount = _btnCount > 0 and (_btnCount - 1) or 0
        RequestReskin()
    end
    icon._msufGFMsqAdded = nil
end

function GF.Masque.ForceReskin()
    _lastReskinCount = -1
    RequestReskin()
end

function GF.Masque.ReskinAllIcons()
    if not GF.frames then return end
    local POOLS = { "_msufGFBuff", "_msufGFDebuff", "_msufGFExt" }
    GF.ForEachFrame(function(f)
        for _, pk in ipairs(POOLS) do
            local pool = f[pk]
            if pool then
                for i = 1, #pool do
                    if pool[i] then GF.Masque.AddButton(pool[i]) end
                end
            end
        end
    end)
    GF.Masque.ForceReskin()
end
