local addonName, ns = ...
ns = ns or _G.MSUF_NS or {}
_G.MSUF_NS = ns
ns.Icons = ns.Icons or {}

local floor = math.floor

local function GetConfigKeyForFrame(f)
    if not f then return nil end
    local key = f.msufConfigKey or f.unitKey
    if key then return key end
    local unit = f.unit
    local fn = _G.GetConfigKeyForUnit or _G.MSUF_GetConfigKeyForUnit
    if type(fn) == "function" then
        return fn(unit)
    end
    if unit == "player" or unit == "target" or unit == "focus" or unit == "targettarget" or unit == "pet" then
        return unit
    end
    if type(unit) == "string" and _G.MSUF_GetBossIndexFromToken and _G.MSUF_GetBossIndexFromToken(unit) then
        return "boss"
    end
    return nil
end

ns.Icons._layout = ns.Icons._layout or {}
function ns.Icons._layout.GetConf(f)
    if not _G.MSUF_DB and type(_G.EnsureDB) == "function" then _G.EnsureDB() end
    local db = _G.MSUF_DB
    if not db then return nil, nil, nil end
    local g = db.general or {}
    local key = GetConfigKeyForFrame(f)
    return g, key, (key and db[key]) or nil
end

function ns.Icons._layout.Resolve(anchor, allowCenter)
    if allowCenter and anchor == "CENTER" then return "CENTER", "CENTER" end
    if anchor == "TOPRIGHT" then return "RIGHT", "TOPRIGHT" end
    if anchor == "BOTTOMLEFT" then return "LEFT", "BOTTOMLEFT" end
    if anchor == "BOTTOMRIGHT" then return "RIGHT", "BOTTOMRIGHT" end
    return "LEFT", "TOPLEFT"
end

function ns.Icons._layout.Apply(icon, owner, size, point, relPoint, ox, oy)
    if not icon then return end
    icon:SetSize(size, size)
    icon:ClearAllPoints()
    icon:SetPoint(point, owner, relPoint, ox, oy)
end

function MSUF_ApplyLeaderIconLayout(f)
    if not (f and f.leaderIcon) then return end
    local g, key, conf = ns.Icons._layout.GetConf(f)
    if not g then return end
    local size = (ns.Util and ns.Util.Num and ns.Util.Num(conf, g, "leaderIconSize", 14)) or 14
    size = floor(size + 0.5)
    if size < 8 then size = 8 elseif size > 64 then size = 64 end
    local ox = (ns.Util and ns.Util.Num and ns.Util.Num(conf, g, "leaderIconOffsetX", 0)) or 0
    local oy = (ns.Util and ns.Util.Num and ns.Util.Num(conf, g, "leaderIconOffsetY", 3)) or 3
    local anchor = (ns.Util and ns.Util.Val and ns.Util.Val(conf, g, "leaderIconAnchor", "TOPLEFT")) or "TOPLEFT"
    if ns.Cache and ns.Cache.StampChanged and not ns.Cache.StampChanged(f, "LeaderIconLayout", size, ox, oy, anchor, (key or "")) then return end
    f._msufLeaderIconLayoutStamp = 1
    local point, relPoint = ns.Icons._layout.Resolve(anchor, false)
    ns.Icons._layout.Apply(f.leaderIcon, f, size, point, relPoint, ox, oy)
    if f.assistantIcon then
        ns.Icons._layout.Apply(f.assistantIcon, f, size, point, relPoint, ox, oy - (size - 1))
    end
end
_G.MSUF_ApplyLeaderIconLayout = MSUF_ApplyLeaderIconLayout

function MSUF_ApplyRaidMarkerLayout(f)
    if not (f and f.raidMarkerIcon) then return end
    local g, key, conf = ns.Icons._layout.GetConf(f)
    if not g then return end
    if g.raidMarkerSize == nil then g.raidMarkerSize = 14 end
    local size = (ns.Util and ns.Util.Num and ns.Util.Num(conf, g, "raidMarkerSize", 14)) or 14
    size = floor(size + 0.5)
    if size < 8 then size = 8 elseif size > 64 then size = 64 end
    local ox = (ns.Util and ns.Util.Num and ns.Util.Num(conf, g, "raidMarkerOffsetX", 16)) or 16
    local oy = (ns.Util and ns.Util.Num and ns.Util.Num(conf, g, "raidMarkerOffsetY", 3)) or 3
    local anchor = (ns.Util and ns.Util.Val and ns.Util.Val(conf, g, "raidMarkerAnchor", "TOPLEFT")) or "TOPLEFT"
    if ns.Cache and ns.Cache.StampChanged and not ns.Cache.StampChanged(f, "RaidMarkerLayout", size, ox, oy, anchor, (key or "")) then return end
    f._msufRaidMarkerLayoutStamp = 1
    local point, relPoint = ns.Icons._layout.Resolve(anchor, true)
    ns.Icons._layout.Apply(f.raidMarkerIcon, f, size, point, relPoint, ox, oy)
end
_G.MSUF_ApplyRaidMarkerLayout = MSUF_ApplyRaidMarkerLayout

function MSUF_CreateClassificationText(f, textFrame, conf, fontPath, flags, fr, fg, fb)
    if not (textFrame and textFrame.CreateFontString) then return end
    if f.classificationIndicatorText then return end
    local fs = textFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    if not fs then return end
    fs:SetAlpha(1)
    if fs.SetJustifyH then fs:SetJustifyH("CENTER") end
    if fs.SetJustifyV then fs:SetJustifyV("MIDDLE") end
    local g2 = (type(_G.MSUF_DB) == "table" and _G.MSUF_DB.general) or {}
    local baseSize = (type(g2) == "table" and g2.fontSize) or 14
    local nameSize = (type(g2) == "table" and g2.nameFontSize) or baseSize
    local clsSize = (conf and conf.classificationIndicatorSize) or (conf and conf.nameFontSize) or nameSize
    if type(clsSize) ~= "number" then clsSize = nameSize end
    clsSize = floor(math.max(8, math.min(64, clsSize)) + 0.5)
    if fs.SetFont and type(fontPath) == "string" and fontPath ~= "" then
        fs:SetFont(fontPath, clsSize, flags)
    end
    if fs.SetTextColor then fs:SetTextColor(fr or 1, fg or 1, fb or 1, 1) end
    if (type(g2) == "table" and g2.textBackdrop == true) and fs.SetShadowColor and fs.SetShadowOffset then
        fs:SetShadowColor(0, 0, 0, 1)
        fs:SetShadowOffset(1, -1)
    elseif fs.SetShadowOffset then
        fs:SetShadowOffset(0, 0)
    end
    fs:Hide()
    f.classificationIndicatorText = fs
end
_G.MSUF_CreateClassificationText = MSUF_CreateClassificationText
