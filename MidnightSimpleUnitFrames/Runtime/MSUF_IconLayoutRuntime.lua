--- Core/MSUF_IconLayoutRuntime.lua
--- Leader / raid-marker shared icon layout helpers.
--- Shared icon layout runtime helpers with stable exported globals.

local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF
MSUF.Icons = MSUF.Icons or {}
MSUF.Icons._layout = MSUF.Icons._layout or {}

local type, tonumber = type, tonumber
local math_floor = math.floor

local function EnsureDBSafe()
    if not _G.MSUF_DB and type(_G.MSUF_EnsureDB) == "function" then
        (_G.MSUF_EnsureDB)()
    end
end

local function GetConfigKeyForUnitSafe(unit)
    local UF = MSUF and MSUF.UF
    if UF and UF.ConfigKeyForUnit then
        return UF.ConfigKeyForUnit(unit)
    end
    if unit == "player" or unit == "target" or unit == "focus" or unit == "focustarget" or unit == "targettarget" or unit == "pet" then
        return unit
    end
    local bossIndex = _G.MSUF_GetBossIndexFromToken
    if type(bossIndex) == "function" and bossIndex(unit) then
        return "boss"
    end
    return nil
end

function MSUF.Icons._layout.GetConf(f)
    EnsureDBSafe()
    local db = _G.MSUF_DB
    if not db then return nil, nil, nil end
    local g = db.general or {}
    local key = (f and f.unit) and GetConfigKeyForUnitSafe(f.unit) or nil
    return g, key, (key and db[key]) or nil
end

function MSUF.Icons._layout.Resolve(anchor, allowCenter)
    if anchor == "CENTER" then return "CENTER", "CENTER"
    elseif anchor == "TOP" then return "TOP", "TOP"
    elseif anchor == "BOTTOM" then return "BOTTOM", "BOTTOM"
    elseif anchor == "LEFT" then return "LEFT", "LEFT"
    elseif anchor == "RIGHT" then return "RIGHT", "RIGHT"
    elseif anchor == "TOPRIGHT" then return "RIGHT", "TOPRIGHT"
    elseif anchor == "BOTTOMLEFT" then return "LEFT", "BOTTOMLEFT"
    elseif anchor == "BOTTOMRIGHT" then return "RIGHT", "BOTTOMRIGHT" end
    return "LEFT", "TOPLEFT"
end

function MSUF.Icons._layout.Layer(conf, g, key, defaultVal)
    local util = MSUF.Util and MSUF.Util.Num
    local v = util and util(conf, g, key, defaultVal or 7) or (defaultVal or 7)
    v = math_floor((tonumber(v) or defaultVal or 7) + 0.5)
    if v < 1 then return 1 end
    if v > 10 then return 10 end
    return v
end

function MSUF.Icons._layout.EnsureLayerFrame(owner, region, key, parent)
    if not owner or not region or not key then return nil end
    local layerKey = key .. "LayerFrame"
    local layerFrame = owner[layerKey]
    if not layerFrame then
        local p = parent or (region.GetParent and region:GetParent()) or owner
        layerFrame = MSUF.UF and MSUF.UF.MakeFrame and MSUF.UF.MakeFrame(owner, layerKey, "Frame", p)
        if layerFrame and layerFrame.SetAllPoints and p then layerFrame:SetAllPoints(p) end
    end
    if layerFrame then
        region._msufLayerFrame = layerFrame
        region._msufLayerOwner = owner
        if region.SetParent and region:GetParent() ~= layerFrame then region:SetParent(layerFrame) end
    end
    return layerFrame
end

function MSUF.Icons._layout.ApplyLayer(region, layer, owner)
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

function MSUF.Icons._layout.Apply(icon, owner, size, point, relPoint, ox, oy)
    icon:SetSize(size, size)
    icon:ClearAllPoints()
    icon:SetPoint(point, owner, relPoint, ox, oy)
end

local function MSUF_ApplyLeaderIconLayout(f)
    if not f or not f.leaderIcon then return end
    local g, key, conf = MSUF.Icons._layout.GetConf(f)
    if not g then return end

    local size = MSUF.Util.Num(conf, g, "leaderIconSize", 14)
    size = math_floor(size + 0.5)
    if size < 8 then size = 8 elseif size > 64 then size = 64 end

    local ox = MSUF.Util.Num(conf, g, "leaderIconOffsetX", 0)
    local oy = MSUF.Util.Num(conf, g, "leaderIconOffsetY", 3)
    local anchor = MSUF.Util.Val(conf, g, "leaderIconAnchor", "TOPLEFT")
    local layer = MSUF.Icons._layout.Layer(conf, g, "leaderIconLayer", 7)
    if not MSUF.Cache.StampChanged(f, "LeaderIconLayout", size, ox, oy, anchor, layer, (key or "")) then return end

    local point, relPoint = MSUF.Icons._layout.Resolve(anchor, false)
    MSUF.Icons._layout.ApplyLayer(f.leaderIcon, layer, f)
    MSUF.Icons._layout.Apply(f.leaderIcon, f, size, point, relPoint, ox, oy)
    if f.assistantIcon then
        MSUF.Icons._layout.ApplyLayer(f.assistantIcon, layer, f)
        MSUF.Icons._layout.Apply(f.assistantIcon, f, size, point, relPoint, ox, oy - (size - 1))
    end
end

local function MSUF_ApplyRaidMarkerLayout(f)
    if not f or not f.raidMarkerIcon then return end
    local g, key, conf = MSUF.Icons._layout.GetConf(f)
    if not g then return end
    if g.raidMarkerSize == nil then g.raidMarkerSize = 14 end

    local size = MSUF.Util.Num(conf, g, "raidMarkerSize", 14)
    size = math_floor(size + 0.5)
    if size < 8 then size = 8 elseif size > 64 then size = 64 end

    local ox = MSUF.Util.Num(conf, g, "raidMarkerOffsetX", 16)
    local oy = MSUF.Util.Num(conf, g, "raidMarkerOffsetY", 3)
    local anchor = MSUF.Util.Val(conf, g, "raidMarkerAnchor", "TOPLEFT")
    local layer = MSUF.Icons._layout.Layer(conf, g, "raidMarkerLayer", 7)
    if not MSUF.Cache.StampChanged(f, "RaidMarkerLayout", size, ox, oy, anchor, layer, (key or "")) then return end

    local point, relPoint = MSUF.Icons._layout.Resolve(anchor, true)
    MSUF.Icons._layout.ApplyLayer(f.raidMarkerIcon, layer, f)
    MSUF.Icons._layout.Apply(f.raidMarkerIcon, f, size, point, relPoint, ox, oy)
end

local function RefreshFrames(applyFn, fieldName)
    if type(applyFn) ~= "function" then return end
    local UF = MSUF and MSUF.UF
    local frames = UF and UF.frames
    if type(frames) ~= "table" then return end
    for _, frame in pairs(frames) do
        if frame and frame[fieldName] then
            applyFn(frame)
        end
    end
end

function _G.MSUF_RefreshLeaderIconFrames()
    RefreshFrames(MSUF_ApplyLeaderIconLayout, "leaderIcon")
end

function _G.MSUF_RefreshRaidMarkerFrames()
    RefreshFrames(MSUF_ApplyRaidMarkerLayout, "raidMarkerIcon")
end

_G.MSUF_ApplyLeaderIconLayout = MSUF_ApplyLeaderIconLayout
_G.MSUF_ApplyRaidMarkerLayout = MSUF_ApplyRaidMarkerLayout
MSUF.Icons.ApplyLeaderIconLayout = MSUF_ApplyLeaderIconLayout
MSUF.Icons.ApplyRaidMarkerLayout = MSUF_ApplyRaidMarkerLayout
