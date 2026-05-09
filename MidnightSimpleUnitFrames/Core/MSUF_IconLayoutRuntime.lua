-- Core/MSUF_IconLayoutRuntime.lua
-- Leader / raid-marker shared icon layout helpers.
-- Extracted from MidnightSimpleUnitFrames.lua; keep exported globals stable.

local addonName, ns = ...
ns = ns or _G.MSUF_NS or {}
_G.MSUF_NS = ns
ns.Icons = ns.Icons or {}
ns.Icons._layout = ns.Icons._layout or {}

local type, tonumber = type, tonumber
local math_floor = math.floor

local function EnsureDBSafe()
    if not _G.MSUF_DB and type(_G.EnsureDB) == "function" then
        _G.EnsureDB()
    end
end

local function GetConfigKeyForUnitSafe(unit)
    local fn = _G.MSUF_GetConfigKeyForUnit
    if type(fn) == "function" then
        return fn(unit)
    end
    if unit == "player" or unit == "target" or unit == "focus" or unit == "targettarget" or unit == "pet" then
        return unit
    end
    local bossIndex = _G.MSUF_GetBossIndexFromToken
    if type(bossIndex) == "function" and bossIndex(unit) then
        return "boss"
    end
    return nil
end

function ns.Icons._layout.GetConf(f)
    EnsureDBSafe()
    local db = _G.MSUF_DB
    if not db then return nil, nil, nil end
    local g = db.general or {}
    local key = (f and f.unit) and GetConfigKeyForUnitSafe(f.unit) or nil
    return g, key, (key and db[key]) or nil
end

function ns.Icons._layout.Resolve(anchor, allowCenter)
    if allowCenter and anchor == "CENTER" then return "CENTER", "CENTER"
    elseif anchor == "TOPRIGHT" then return "RIGHT", "TOPRIGHT"
    elseif anchor == "BOTTOMLEFT" then return "LEFT", "BOTTOMLEFT"
    elseif anchor == "BOTTOMRIGHT" then return "RIGHT", "BOTTOMRIGHT" end
    return "LEFT", "TOPLEFT"
end

function ns.Icons._layout.Layer(conf, g, key, defaultVal)
    local util = ns.Util and ns.Util.Num
    local v = util and util(conf, g, key, defaultVal or 7) or (defaultVal or 7)
    v = math_floor((tonumber(v) or defaultVal or 7) + 0.5)
    if v < 1 then return 1 end
    if v > 10 then return 10 end
    return v
end

function ns.Icons._layout.EnsureLayerFrame(owner, region, key, parent)
    if not owner or not region or not key then return nil end
    local layerKey = key .. "LayerFrame"
    local layerFrame = owner[layerKey]
    if not layerFrame then
        local p = parent or (region.GetParent and region:GetParent()) or owner
        layerFrame = ns.UF and ns.UF.MakeFrame and ns.UF.MakeFrame(owner, layerKey, "Frame", p)
        if layerFrame and layerFrame.SetAllPoints and p then layerFrame:SetAllPoints(p) end
    end
    if layerFrame then
        region._msufLayerFrame = layerFrame
        region._msufLayerOwner = owner
        if region.SetParent and region:GetParent() ~= layerFrame then region:SetParent(layerFrame) end
    end
    return layerFrame
end

function ns.Icons._layout.ApplyLayer(region, layer, owner)
    if not region then return end
    local l = tonumber(layer) or 7
    l = math_floor(l + 0.5)
    if l < 1 then l = 1 elseif l > 10 then l = 10 end

    local layerFrame = region._msufLayerFrame
    if layerFrame and layerFrame.SetFrameLevel then
        local base = 0
        local o = owner or region._msufLayerOwner
        if o and o.GetFrameLevel then base = o:GetFrameLevel() or 0 end
        local want = base + 10 + l
        if layerFrame._msufLayerLevel ~= want then
            layerFrame._msufLayerLevel = want
            layerFrame:SetFrameLevel(want)
        end
    end

    if region.SetDrawLayer then
        local sub = l - 1
        if sub > 7 then sub = 7 elseif sub < 0 then sub = 0 end
        region:SetDrawLayer("OVERLAY", sub)
    end
end

function ns.Icons._layout.Apply(icon, owner, size, point, relPoint, ox, oy)
    icon:SetSize(size, size)
    icon:ClearAllPoints()
    icon:SetPoint(point, owner, relPoint, ox, oy)
end

local function MSUF_ApplyLeaderIconLayout(f)
    if not f or not f.leaderIcon then return end
    local g, key, conf = ns.Icons._layout.GetConf(f)
    if not g then return end

    local size = ns.Util.Num(conf, g, "leaderIconSize", 14)
    size = math_floor(size + 0.5)
    if size < 8 then size = 8 elseif size > 64 then size = 64 end

    local ox = ns.Util.Num(conf, g, "leaderIconOffsetX", 0)
    local oy = ns.Util.Num(conf, g, "leaderIconOffsetY", 3)
    local anchor = ns.Util.Val(conf, g, "leaderIconAnchor", "TOPLEFT")
    local layer = ns.Icons._layout.Layer(conf, g, "leaderIconLayer", 7)
    if not ns.Cache.StampChanged(f, "LeaderIconLayout", size, ox, oy, anchor, layer, (key or "")) then return end

    local point, relPoint = ns.Icons._layout.Resolve(anchor, false)
    ns.Icons._layout.ApplyLayer(f.leaderIcon, layer, f)
    ns.Icons._layout.Apply(f.leaderIcon, f, size, point, relPoint, ox, oy)
    if f.assistantIcon then
        ns.Icons._layout.ApplyLayer(f.assistantIcon, layer, f)
        ns.Icons._layout.Apply(f.assistantIcon, f, size, point, relPoint, ox, oy - (size - 1))
    end
end

local function MSUF_ApplyRaidMarkerLayout(f)
    if not f or not f.raidMarkerIcon then return end
    local g, key, conf = ns.Icons._layout.GetConf(f)
    if not g then return end
    if g.raidMarkerSize == nil then g.raidMarkerSize = 14 end

    local size = ns.Util.Num(conf, g, "raidMarkerSize", 14)
    size = math_floor(size + 0.5)
    if size < 8 then size = 8 elseif size > 64 then size = 64 end

    local ox = ns.Util.Num(conf, g, "raidMarkerOffsetX", 16)
    local oy = ns.Util.Num(conf, g, "raidMarkerOffsetY", 3)
    local anchor = ns.Util.Val(conf, g, "raidMarkerAnchor", "TOPLEFT")
    local layer = ns.Icons._layout.Layer(conf, g, "raidMarkerLayer", 7)
    if not ns.Cache.StampChanged(f, "RaidMarkerLayout", size, ox, oy, anchor, layer, (key or "")) then return end

    local point, relPoint = ns.Icons._layout.Resolve(anchor, true)
    ns.Icons._layout.ApplyLayer(f.raidMarkerIcon, layer, f)
    ns.Icons._layout.Apply(f.raidMarkerIcon, f, size, point, relPoint, ox, oy)
end

_G.MSUF_ApplyLeaderIconLayout = MSUF_ApplyLeaderIconLayout
_G.MSUF_ApplyRaidMarkerLayout = MSUF_ApplyRaidMarkerLayout
ns.Icons.ApplyLeaderIconLayout = MSUF_ApplyLeaderIconLayout
ns.Icons.ApplyRaidMarkerLayout = MSUF_ApplyRaidMarkerLayout
