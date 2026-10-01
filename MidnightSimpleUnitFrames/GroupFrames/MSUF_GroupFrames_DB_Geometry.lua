--- GroupFrames/MSUF_GroupFrames_DB_Geometry.lua
--- Group-frame geometry: grid metrics, anchor points and their screen clamp,
--- frame scaling and layout tiers, group roles and the per-role power bar.
--- Split by cohesion from MSUF_GroupFrames_DB.lua (2026-10-01). Loads right
--- after it (UFCore_Group.xml and the Classic GroupFrames.xml manifests) and
--- shares the one MSUF.GF table; see that file for the module's API surface.
local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}

MSUF.GF = MSUF.GF or {}
local GF = MSUF.GF
-- Classic and WoW Forever groups may leave roles unassigned (client facts, read once).
local USE_UNASSIGNED_POWER_FALLBACK = MSUF.Client ~= nil
    and (MSUF.Client.IsForever == true or MSUF.Client.IsClassic == true)

local math_max = math.max
local math_min = math.min
local math_ceil = math.ceil
local math_floor = math.floor
local tonumber = tonumber
local tostring = tostring
local type = type
local _GF_UnitGroupRolesAssigned = _G.UnitGroupRolesAssigned
local _GF_issecretvalue = _G.issecretvalue

local PARTY_DEFAULTS = GF.PARTY_DEFAULTS
local RAID_DEFAULTS = GF.RAID_DEFAULTS
local MYTHIC_RAID_DEFAULTS = GF.MYTHIC_RAID_DEFAULTS
local PRIORITY_DEFAULTS = GF.PRIORITY_DEFAULTS

---
--- Grid metrics (V2 stores the selected anchor point of the complete grid bounds)
---
GF._measuredFirstCenterDelta = GF._measuredFirstCenterDelta or {}

local LEGACY_GRID_POSITION_MODE = GF.GRID_POSITION_MODES.LEGACY
local STABLE_GRID_POSITION_MODE = GF.GRID_POSITION_MODES.STABLE

function GF.GetHeaderOriginToFirstCenter(kind, w, h)
    local t = GF._measuredFirstCenterDelta and GF._measuredFirstCenterDelta[kind]
    if t and t.x ~= nil and t.y ~= nil then
        return t.x, t.y
    end
    return (w or 0) * 0.5, -(h or 0) * 0.5
end

local function IsRaidLikeKind(kind)
    return kind == "raid" or kind == "mythicraid"
end

local function IsDefaultsConf(kind, conf)
    if kind == "raid" then return conf == RAID_DEFAULTS end
    if kind == "mythicraid" then return conf == MYTHIC_RAID_DEFAULTS end
    return conf == PARTY_DEFAULTS
end

---
--- Anchor point
--- Party, Raid and Mythic Raid expose exactly ONE anchor control ("Anchor
--- Point"): it pins the chosen corner of the block to the identical corner of
--- the anchor frame. `point` is only its legacy projection, and `relativePoint`
--- has no control at all - but profiles still carry both, and the placement code
--- used to let a stale `relativePoint` win over the visible setting. A scope
--- whose leftover said CENTER anchored to the middle of the anchor frame while a
--- scope without one anchored to its corner, so two scopes showing the same
--- Anchor Point and the same X/Y landed half an anchor frame apart (GitHub #67).
--- Retire the leftovers on the first placement - folding them into the saved
--- offsets keeps the block exactly where it is - and let the visible setting own
--- both sides from then on. Priority Frames are excluded on purpose: point and
--- relativePoint are real, settable options there (GF.SetPriorityOption).
---
local ANCHOR_POINTS = {
    CENTER = true, TOP = true, BOTTOM = true, LEFT = true, RIGHT = true,
    TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true,
}

local function AnchorPointFraction(point)
    local fx, fy = 0.5, 0.5
    if point == "LEFT" or point == "TOPLEFT" or point == "BOTTOMLEFT" then
        fx = 0
    elseif point == "RIGHT" or point == "TOPRIGHT" or point == "BOTTOMRIGHT" then
        fx = 1
    end
    if point == "BOTTOM" or point == "BOTTOMLEFT" or point == "BOTTOMRIGHT" then
        fy = 0
    elseif point == "TOP" or point == "TOPLEFT" or point == "TOPRIGHT" then
        fy = 1
    end
    return fx, fy
end

function GF.GetAnchorPoint(conf)
    local point = conf and (conf.anchorPoint or conf.point) or "CENTER"
    if not ANCHOR_POINTS[point] then point = "CENTER" end
    return point
end

local function ConfigureAnchorScreenClamp(frame, key, left, right, top, bottom)
    if not (frame and frame.SetClampedToScreen and frame.SetClampRectInsets) then return false end
    if frame._msufGFScreenClampKey ~= key then
        frame:SetClampRectInsets(left, right, top, bottom)
        frame._msufGFScreenClampKey = key
    end
    if frame._msufScreenClampEnabled ~= true then
        frame:SetClampedToScreen(true)
        frame._msufScreenClampEnabled = true
    end
    return true
end

--- Clamp the configured anchor point, not the complete group footprint.
--- Party and Raid can have very different grid sizes. Full-frame clamping
--- silently adds a size-dependent delta after SetPoint, so identical
--- Anchor To / Anchor Point / X / Y values no longer identify the same screen
--- point. Blizzard's clamp rect supports an exact point-sized selection (the
--- same mechanism Edit Mode uses for selection bounds), preserving recovery at
--- the screen edge without changing the saved coordinate contract.
function GF.ConfigureAnchorPointScreenClamp(frame, point, width, height)
    if not (frame and frame.SetClampedToScreen) then return false end
    point = ANCHOR_POINTS[point] and point or "CENTER"
    local w = tonumber(width) or (frame.GetWidth and tonumber(frame:GetWidth()))
    local h = tonumber(height) or (frame.GetHeight and tonumber(frame:GetHeight()))
    if not (frame.SetClampRectInsets and w and h and w >= 0 and h >= 0) then
        --- A full-frame fallback would reintroduce the Party/Raid divergence.
        frame:SetClampedToScreen(false)
        frame._msufScreenClampEnabled = nil
        frame._msufGFAnchorPointClampKey = nil
        frame._msufGFScreenClampKey = nil
        return false
    end

    local fx, fy = AnchorPointFraction(point)
    local half = 0.5
    local left, right = w * fx - half, -w * (1 - fx) + half
    local top, bottom = -h * (1 - fy) + half, h * fy - half
    local key = point .. "\030" .. tostring(w) .. "\030" .. tostring(h)
    local configured = ConfigureAnchorScreenClamp(frame, "point\030" .. key, left, right, top, bottom)
    frame._msufGFAnchorPointClampKey = configured and key or nil
    return configured
end

--- After the live secure headers have settled, clamp their measured selection
--- instead of the logical point. The caller supplies native clamp insets in the
--- anchor's local coordinate space; saved offsets and the point-only Preview /
--- Edit Mode contract remain untouched.
function GF.ConfigureAnchorFootprintScreenClamp(frame, left, right, top, bottom)
    if _GF_issecretvalue and (_GF_issecretvalue(left) == true or _GF_issecretvalue(right) == true
        or _GF_issecretvalue(top) == true or _GF_issecretvalue(bottom) == true) then
        return false
    end
    if type(left) ~= "number" or type(right) ~= "number"
        or type(top) ~= "number" or type(bottom) ~= "number" then
        return false
    end
    local key = table.concat({
        "footprint", tostring(left), tostring(right), tostring(top), tostring(bottom),
    }, "\030")
    local configured = ConfigureAnchorScreenClamp(frame, key, left, right, top, bottom)
    if configured then frame._msufGFAnchorPointClampKey = nil end
    return configured
end

--- Convert a legacy relativePoint into the saved offsets. Returns false while
--- the anchor frame has no measurable size so the next placement can retry;
--- until then the old pair stays live and the block does not jump.
local function RetireLegacyRelativePoint(conf, point, parent)
    local legacy = conf.relativePoint
    if not ANCHOR_POINTS[legacy] or legacy == point then
        conf.relativePoint = nil
        return true
    end
    local w = parent and parent.GetWidth and tonumber(parent:GetWidth())
    local h = parent and parent.GetHeight and tonumber(parent:GetHeight())
    if not (w and h and w > 0 and h > 0) then return false end
    local fx, fy = AnchorPointFraction(point)
    local rfx, rfy = AnchorPointFraction(legacy)
    conf.offsetX = math_floor(((tonumber(conf.offsetX) or 0) + w * (rfx - fx)) + 0.5)
    conf.offsetY = math_floor(((tonumber(conf.offsetY) or 0) + h * (rfy - fy)) + 0.5)
    conf.relativePoint = nil
    return true
end

--- Anchor points for one group block, ready to feed a SetPoint call. `parent` is
--- the already resolved anchor frame; it is only read to retire the legacy pair.
--- Callers must read conf.offsetX/offsetY AFTER this, since retiring rewrites
--- them. Cold path only (header setup, preview build, Edit Mode sync).
function GF.ResolveAnchorPoint(kind, conf, parent)
    local point = GF.GetAnchorPoint(conf)
    if kind == "priority" then
        local relativePoint = conf and conf.relativePoint
        return point, ANCHOR_POINTS[relativePoint] and relativePoint or point
    end
    --- Callers reach this with a header key ("raid" also carries the Mythic Raid
    --- conf), so reject every defaults table instead of the one for `kind`:
    --- a shared defaults table must never collect a scope's position.
    if type(conf) ~= "table"
        or conf == PARTY_DEFAULTS or conf == RAID_DEFAULTS
        or conf == MYTHIC_RAID_DEFAULTS or conf == PRIORITY_DEFAULTS then
        return point, point
    end
    if conf.relativePoint ~= nil and not RetireLegacyRelativePoint(conf, point, parent) then
        return point, conf.relativePoint
    end
    --- Keep the legacy projection in step so exports, imports and the menu
    --- never read a point the menu no longer shows.
    if conf.point ~= point then conf.point = point end
    return point, point
end

---
--- Group Frame Scaling
--- Scales the physical frame geometry first; render modules then use the
--- cached scale for fonts and icons. Keeping the math here prevents the
--- header, preview, mover, and child-scan paths from drifting apart.
---
local SCALE_AUTO_DEFAULTS = {
    { max = 10, scale = 100 },  --- 1-10 players
    { max = 20, scale = 85  },  --- 11-20 players
    { max = 25, scale = 80  },  --- 21-25 players
    --- 26+ uses scaleOver25
}
local SCALE_OVER25_DEFAULT = 70

local function ClampScalePct(v, fallback)
    v = tonumber(v) or fallback or 100
    if v < 50 then v = 50 elseif v > 150 then v = 150 end
    return v
end

local function RoundScaled(v, scale)
    v = (tonumber(v) or 0) * (tonumber(scale) or 1)
    if v >= 0 then return math_floor(v + 0.5) end
    return -math_floor((-v) + 0.5)
end

local layoutCountCache = {}
function GF.InvalidateLayoutRoster() wipe(layoutCountCache) end
function GF.GetLayoutGroupCount(kind)
    local conf = GF.GetConf(kind)
    local count = _G.GetNumGroupMembers() or 0
    if kind == "party" or conf.excludeHiddenGroups ~= true or not _G.IsInRaid() then return count end
    local cached = layoutCountCache[kind]
    if cached then return cached end
    local visible = 0
    for i = 1, count do
        local _, _, group = _G.GetRaidRosterInfo(i)
        if (not _GF_issecretvalue or _GF_issecretvalue(group) ~= true) and type(group) == "number" then
            local allowed = not (kind == "mythicraid" and conf.hideMythicGroupsFiveToEight == true and group > 4)
            local filter = conf.groupFilter
            if allowed and type(filter) == "table" then allowed = filter[group] ~= false and filter[tostring(group)] ~= false
            elseif allowed and type(filter) == "string" and filter ~= "" then
                local numeric, match = false, false
                for token in filter:gmatch("[^,]+") do
                    local n = tonumber(token)
                    if n then numeric = true; if n == group then match = true end end
                end
                if numeric then allowed = match end
            end
            if allowed then visible = visible + 1 end
        else
            -- Incomplete/opaque roster: preserve the public total until settled.
            return count
        end
    end
    layoutCountCache[kind] = visible
    return visible
end
--- `count` is the member count a layout is drawn for: previews and Edit Mode
--- pass their sample count, nil means the live roster.
function GF.GetLayoutTier(kind, count)
    local conf = GF.GetConf(kind)
    if kind == "party" or conf.layoutTiersEnabled ~= true then return nil end
    local n = tonumber(count) or GF.GetLayoutGroupCount(kind)
    return n <= 10 and "tier10" or n <= 20 and "tier20" or n <= 25 and "tier25" or "tier40"
end
function GF.ResolveLayoutGrowth(kind, conf, count)
    conf = conf or GF.GetConf(kind)
    local tier = GF.GetLayoutTier(kind, count)
    local value = tier and conf[tier .. "Growth"]
    if value == "UP" or value == "DOWN" or value == "LEFT" or value == "RIGHT" then return value end
    return conf.growth or "DOWN"
end

function GF.ResolveFrameScale(kind)
    local conf = GF.GetConf(kind)
    if not conf then return 1 end
    local mode = conf.frameScaleMode or "off"
    if mode == "off" then return 1 end
    if mode == "manual" then
        return ClampScalePct(conf.frameScaleManual, 100) / 100
    end

    local n = GF.GetLayoutGroupCount(kind)
    local s10 = ClampScalePct(conf.scaleAt10,  SCALE_AUTO_DEFAULTS[1].scale)
    local s20 = ClampScalePct(conf.scaleAt20,  SCALE_AUTO_DEFAULTS[2].scale)
    local s25 = ClampScalePct(conf.scaleAt25,  SCALE_AUTO_DEFAULTS[3].scale)
    local s26 = ClampScalePct(conf.scaleOver25, SCALE_OVER25_DEFAULT)
    if n <= 10 then return s10 / 100 end
    if n <= 20 then return s20 / 100 end
    if n <= 25 then return s25 / 100 end
    return s26 / 100
end

function GF.ApplyFrameScale(kind)
    local conf = GF.GetConf(kind)
    if not conf then return 1 end
    local s = GF.ResolveFrameScale(kind)
    if not IsDefaultsConf(kind, conf) then
        conf._resolvedFrameScale = s
    end
    return s
end

function GF.GetFrameScale(kind)
    return GF.ApplyFrameScale(kind)
end

function GF.ScaleValue(value, scale, minValue)
    local v = RoundScaled(value, scale)
    if minValue ~= nil and v < minValue then v = minValue end
    return v
end

function GF.ScaleFrameValue(kind, value, minValue)
    local conf = GF.GetConf(kind)
    local scale = (conf and conf._resolvedFrameScale) or GF.ApplyFrameScale(kind) or 1
    return GF.ScaleValue(value, scale, minValue)
end

function GF.GetScaledFrameMetrics(kind, count)
    local conf = GF.GetConf(kind)
    local isRaidLike = IsRaidLikeKind(kind)
    if not conf then
        return isRaidLike and 80 or 120, isRaidLike and 32 or 40, 1, 1
    end
    local scale = GF.ApplyFrameScale(kind)
    local w = GF.ScaleValue(tonumber(conf.width) or (isRaidLike and 80 or 120), scale, 1)
    local h = GF.ScaleValue(tonumber(conf.height) or (isRaidLike and 32 or 40), scale, 1)
    local tier = GF.GetLayoutTier(kind, count)
    if tier then
        local tw, th = tonumber(conf[tier .. "Width"]), tonumber(conf[tier .. "Height"])
        if tw and tw > 0 then w = math_floor(math_max(20, math_min(500, tw)) + .5) end
        if th and th > 0 then h = math_floor(math_max(10, math_min(200, th)) + .5) end
    end
    local sp = GF.ScaleValue(tonumber(conf.spacing) or 1, scale, 0)
    return w, h, sp, scale
end

--- Where the active layout sits, for the live anchor, the previews and Edit
--- Mode alike: the conf keys holding its offsets (offsetX/offsetY, or a size
--- tier's own pair when that tier positions itself) and whether the block is
--- pinned to the screen centre instead (Party "Center party frames while solo";
--- never while Edit Mode arranges the groups, so a drag moves what it shows).
function GF.ResolveGroupPositionKeys(kind, conf, count)
    conf = conf or GF.GetConf(kind)
    if kind == "party" and conf.centerSolo == true and GF._groupEditActive ~= true
        and not (_G.IsInGroup and _G.IsInGroup()) then
        return nil, nil, true
    end
    local tier = GF.GetLayoutTier(kind, count)
    if tier and conf[tier .. "Position"] == true then return tier .. "X", tier .. "Y", false end
    return "offsetX", "offsetY", false
end

--- The conf keys the active layout's frame size comes from: a size tier's own
--- width or height when it sets one (non-zero), the base size otherwise.
function GF.ResolveGroupSizeKeys(kind, conf, count)
    conf = conf or GF.GetConf(kind)
    local tier = GF.GetLayoutTier(kind, count)
    local widthKey, heightKey = "width", "height"
    if tier then
        if (tonumber(conf[tier .. "Width"]) or 0) > 0 then widthKey = tier .. "Width" end
        if (tonumber(conf[tier .. "Height"]) or 0) > 0 then heightKey = tier .. "Height" end
    end
    return widthKey, heightKey
end

-- Zero keeps the active group's dimensions; explicit sizes belong only to
-- duplicate Priority frames and never rewrite the inherited appearance table.
--- `kind` names the scope `conf` belongs to; callers that compile a scope pass
--- it. Without it the scope is recovered from the conf table's identity.
function GF.GetResizeScale(conf, kind)
    kind = kind or (conf == GF.GetConf("raid") and "raid" or conf == GF.GetConf("mythicraid") and "mythicraid" or "party")
    local w, h = GF.GetScaledFrameMetrics(kind)
    local baseW, baseH = tonumber(conf.width) or 120, tonumber(conf.height) or 40
    return math_max(.25, math_min(3, w / math_max(1, baseW), h / math_max(1, baseH)))
end

function GF.GetPriorityFrameMetrics(kind)
    local w, h = GF.GetScaledFrameMetrics(kind)
    local conf = GF.GetPriorityConf and GF.GetPriorityConf() or {}
    local width, height = tonumber(conf.width) or 0, tonumber(conf.height) or 0
    if width > 0 then w = math_floor(math.max(20, math.min(500, width)) + .5) end
    if height > 0 then h = math_floor(math.max(10, math.min(200, height)) + .5) end
    return w, h
end

function GF.GetScaledPowerHeight(kind)
    local conf = GF.GetConf(kind)
    if conf and conf.powerBarEnabled == false then return 0 end
    local raw = tonumber(conf and conf.powerHeight) or (IsRaidLikeKind(kind) and 4 or 6)
    if raw <= 0 then return 0 end
    if not conf then return raw end
    local scale = conf._resolvedFrameScale or GF.ApplyFrameScale(kind) or 1
    return GF.ScaleValue(raw, scale, 1)
end

function GF.NormalizeGroupRole(role)
    if _GF_issecretvalue then
        if _GF_issecretvalue(role) == true then return "DAMAGER" end
    end
    if role == "TANK" or role == "HEALER" or role == "DAMAGER" then
        return role
    end
    return "DAMAGER"
end

function GF.GetUnitGroupRole(unit)
    local role = unit and _GF_UnitGroupRolesAssigned and _GF_UnitGroupRolesAssigned(unit)
    return GF.NormalizeGroupRole(role)
end

--- Classic and Forever groups may not have assigned roles. An unassigned
--- healer still needs a mana bar when any role is allowed to show power.
--- Explicit roles, disabled bars and secret roles retain their usual filters.
local function IsUnassignedClassicRole(unit)
    if not (USE_UNASSIGNED_POWER_FALLBACK and unit) then return false end
    if not _GF_UnitGroupRolesAssigned then return true end
    local role = _GF_UnitGroupRolesAssigned(unit)
    if _GF_issecretvalue and _GF_issecretvalue(role) == true then return false end
    return role ~= "TANK" and role ~= "HEALER" and role ~= "DAMAGER"
end

--- `unit` is optional; role-only previews keep the explicit role filter.
function GF.ShouldShowPowerBarForRole(kind, role, conf, unit)
    conf = conf or GF.GetConf(kind)
    if not conf then return false end
    if conf.powerBarEnabled == false then return false end
    local raw = tonumber(conf.powerHeight) or (IsRaidLikeKind(kind) and 4 or 6)
    if raw <= 0 then return false end

    if IsUnassignedClassicRole(unit) then
        return conf.powerShowTank ~= false or conf.powerShowHealer ~= false
            or conf.powerShowDamager ~= false
    end
    role = GF.NormalizeGroupRole(role)
    if role == "TANK" then
        return conf.powerShowTank ~= false
    elseif role == "HEALER" then
        return conf.powerShowHealer ~= false
    end
    return conf.powerShowDamager ~= false
end

function GF.ShouldShowPowerBarForUnit(kind, unit, conf)
    return GF.ShouldShowPowerBarForRole(kind, GF.GetUnitGroupRole(unit), conf, unit)
end

function GF.GetEffectivePowerHeight(kind, unit, role, conf)
    conf = conf or GF.GetConf(kind)
    if not GF.ShouldShowPowerBarForRole(kind, role or GF.GetUnitGroupRole(unit), conf, unit) then
        return 0
    end
    return (GF.GetScaledPowerHeight and GF.GetScaledPowerHeight(kind)) or (tonumber(conf and conf.powerHeight) or 0)
end

local function GetRaidGroupLayoutParts(conf, count, preservedGroupCount)
    local upc = math_floor((tonumber(conf and conf.unitsPerColumn) or 5) + 0.5)
    if upc < 1 then upc = 1 elseif upc > 40 then upc = 40 end
    local primary = math_min(upc, 5)
    local groups = math_floor((tonumber(conf and conf.maxColumns) or 8) + 0.5)
    if groups < 1 then groups = 1 elseif groups > 8 then groups = 8 end
    if preservedGroupCount ~= nil then
        groups = tonumber(preservedGroupCount) or groups
        if groups < 1 then groups = 1 elseif groups > 8 then groups = 8 end
    elseif type(GF.GetPreservedRaidGroupCount) == "function" then
        -- Without a live snapshot count this sizes a preview or an Edit Mode
        -- mover: empty live subgroups must not collapse sample groups.
        groups = tonumber(GF.GetPreservedRaidGroupCount(conf, true)) or groups
        if groups < 1 then groups = 1 elseif groups > 8 then groups = 8 end
    end
    local blockColumns = math_ceil(5 / primary)
    if blockColumns < 1 then blockColumns = 1 end
    return upc, primary, groups, blockColumns
end

function GF.GetVisibleLayoutCount(kind, count, conf)
    count = math_floor((tonumber(count) or 0) + 0.5)
    if count < 1 then return count end
    if not IsRaidLikeKind(kind) then return count end

    conf = conf or (GF.GetConf and GF.GetConf(kind)) or {}
    if conf and conf.preserveRaidGroups == true then
        local groups = math_floor((tonumber(conf.maxColumns) or 8) + 0.5)
        if groups < 1 then groups = 1 elseif groups > 8 then groups = 8 end
        return math_min(count, groups * 5)
    end

    local upc = math_floor((tonumber(conf and conf.unitsPerColumn) or 5) + 0.5)
    if upc < 1 then upc = 1 elseif upc > 40 then upc = 40 end
    local columns = math_floor((tonumber(conf and conf.maxColumns) or 8) + 0.5)
    if columns < 1 then columns = 1 elseif columns > 40 then columns = 40 end
    return math_min(count, upc * columns)
end

function GF.GetPreservedRaidGridMetrics(kind, count, preservedGroupCount)
    local conf = GF.GetConf(kind)
    local tierCount = (tonumber(count) or 0) > 0 and count or nil
    local w, h, sp = GF.GetScaledFrameMetrics(kind, tierCount)
    local growth = GF.ResolveLayoutGrowth(kind, conf, tierCount)

    count = tonumber(count) or 0
    local upc, primary, maxGroups, blockColumns = GetRaidGroupLayoutParts(conf, count, preservedGroupCount)
    local groups = (count > 0) and math_ceil(count / 5) or maxGroups
    if groups < 1 then groups = 1 end
    groups = math_min(maxGroups, groups)

    local blockW, blockH
    if growth == "DOWN" or growth == "UP" then
        blockW = blockColumns * w + math_max(0, blockColumns - 1) * sp
        blockH = primary      * h + math_max(0, primary - 1) * sp
    else
        blockW = primary      * w + math_max(0, primary - 1) * sp
        blockH = blockColumns * h + math_max(0, blockColumns - 1) * sp
    end

    local totalW, totalH
    if growth == "DOWN" or growth == "UP" then
        totalW = groups * blockW + math_max(0, groups - 1) * sp
        totalH = blockH
    else
        totalW = blockW
        totalH = groups * blockH + math_max(0, groups - 1) * sp
    end

    local firstDX, firstDY = GF.GetHeaderOriginToFirstCenter(kind, w, h)
    local dx, dy = firstDX, firstDY
    if growth == "DOWN" then
        dx = dx + (totalW - w) * 0.5
        dy = dy - (totalH - h) * 0.5
    elseif growth == "UP" then
        dx = dx + (totalW - w) * 0.5
        dy = dy + (totalH - h) * 0.5
    elseif growth == "RIGHT" then
        dx = dx + (totalW - w) * 0.5
        dy = dy - (totalH - h) * 0.5
    elseif growth == "LEFT" then
        dx = dx - (totalW - w) * 0.5
        dy = dy - (totalH - h) * 0.5
    end

    return dx, dy, totalW, totalH, w, h, sp, growth, upc, count, firstDX, firstDY, primary, groups, blockColumns, blockW, blockH
end

function GF.GetGridMetrics(kind, count, preservedGroupCount)
    local conf = GF.GetConf(kind)
    if IsRaidLikeKind(kind) and conf.preserveRaidGroups == true and GF.GetPreservedRaidGridMetrics then
        return GF.GetPreservedRaidGridMetrics(kind, count, preservedGroupCount)
    end

    local tierCount = (tonumber(count) or 0) > 0 and count or nil
    local w, h, sp = GF.GetScaledFrameMetrics(kind, tierCount)
    local growth = GF.ResolveLayoutGrowth(kind, conf, tierCount)
    local upc = math_floor((tonumber(conf.unitsPerColumn) or 5) + 0.5)
    if upc < 1 then upc = 1 elseif upc > 40 then upc = 40 end

    count = tonumber(count) or 0
    if count < 1 then count = (IsRaidLikeKind(kind) and 10 or 5) end

    local numCols = math_ceil(count / upc)
    if numCols < 1 then numCols = 1 end
    -- Non-preserve raid columns use maxColumns as a real display cap. The wider
    -- column cap preserves imported/manual values above the menu slider range.
    local columnCap = IsRaidLikeKind(kind) and 40 or 8
    local maxDefault = IsRaidLikeKind(kind) and 8 or numCols
    local maxColumns = math_floor((tonumber(conf.maxColumns) or maxDefault) + 0.5)
    if maxColumns < 1 then maxColumns = 1 elseif maxColumns > columnCap then maxColumns = columnCap end
    if numCols > maxColumns then numCols = maxColumns end
    local major = math_min(count, upc)

    local totalW, totalH
    if growth == "DOWN" or growth == "UP" then
        totalW = numCols * w + math_max(0, numCols - 1) * sp
        totalH = major   * h + math_max(0, major   - 1) * sp
    else
        totalW = major   * w + math_max(0, major   - 1) * sp
        totalH = numCols * h + math_max(0, numCols - 1) * sp
    end

    local firstDX, firstDY = GF.GetHeaderOriginToFirstCenter(kind, w, h)
    local dx, dy = firstDX, firstDY
    if growth == "DOWN" then
        dx = dx + (totalW - w) * 0.5
        dy = dy - (totalH - h) * 0.5
    elseif growth == "UP" then
        dx = dx + (totalW - w) * 0.5
        dy = dy + (totalH - h) * 0.5
    elseif growth == "RIGHT" then
        dx = dx + (totalW - w) * 0.5
        dy = dy - (totalH - h) * 0.5
    elseif growth == "LEFT" then
        dx = dx - (totalW - w) * 0.5
        dy = dy - (totalH - h) * 0.5
    end

    return dx, dy, totalW, totalH, w, h, sp, growth, upc, count, firstDX, firstDY
end

--- GRID_CENTER_V1 was rendered by shifting an already full-size header by the
--- origin-to-center delta. That made the stored point a count-dependent corner
--- in practice. Convert only when a group is actually about to be displayed so
--- the current live/preview count preserves the exact legacy on-screen bounds.
function GF.EnsureStableGridPosition(kind, count, conf, preservedGroupCount)
    conf = conf or (GF.GetConf and GF.GetConf(kind))
    if type(conf) ~= "table" then return false end
    if conf.positionMode == STABLE_GRID_POSITION_MODE then return false end
    if conf.positionMode ~= LEGACY_GRID_POSITION_MODE then return false end

    -- Undo exactly the delta the legacy stamp added. Whoever converts first
    -- (live header, Edit Mode, preview) otherwise supplies a different count
    -- than the migration did, and the difference is written to disk for good.
    local pinnedCount = tonumber(conf.positionMigrationCount)
    local dx, dy = GF.GetGridMetrics(kind, pinnedCount or count, preservedGroupCount)
    local fallbackX = IsRaidLikeKind(kind) and -500 or -400
    conf.offsetX = (tonumber(conf.offsetX) or fallbackX) - (tonumber(dx) or 0)
    conf.offsetY = (tonumber(conf.offsetY) or 0) - (tonumber(dy) or 0)
    conf.positionMode = STABLE_GRID_POSITION_MODE
    conf.positionMigrationCount = nil
    return true
end

local function GetMigrationCount(kind, conf)
    if IsRaidLikeKind(kind) then
        local isInRaid = _G.IsInRaid
        local getNum = _G.GetNumGroupMembers
        local n = (type(getNum) == "function") and (getNum() or 0) or 0
        if (type(isInRaid) == "function" and isInRaid()) and n > 0 then
            return n
        end
        return 10
    end

    local getSub = _G.GetNumSubgroupMembers
    local n = (type(getSub) == "function") and (getSub() or 0) or 0
    if n > 0 then
        if conf.showPlayer ~= false then n = n + 1 end
        return n
    end
    if conf.showSolo and conf.showPlayer ~= false then
        return 1
    end
    return 5
end

--- Legacy stamp half of the pair above; the EnsureDB repair pipeline
--- (MSUF_GroupFrames_DB_Migrations.lua) runs it once per member scope.
function GF.MigrateGroupPositionToGridCenter(conf, kind)
    if not conf then return end
    if conf.positionMode == LEGACY_GRID_POSITION_MODE or conf.positionMode == STABLE_GRID_POSITION_MODE then return end
    local migrationCount = GetMigrationCount(kind, conf)
    local dx, dy = GF.GetGridMetrics(kind, migrationCount)
    conf.offsetX = (conf.offsetX or (IsRaidLikeKind(kind) and -500 or -400)) + dx
    conf.offsetY = (conf.offsetY or 0) + dy
    conf.positionMode = LEGACY_GRID_POSITION_MODE
    -- Carry the count forward so EnsureStableGridPosition can subtract the very
    -- same delta instead of whatever roster the converting surface happens to see.
    conf.positionMigrationCount = migrationCount
end
