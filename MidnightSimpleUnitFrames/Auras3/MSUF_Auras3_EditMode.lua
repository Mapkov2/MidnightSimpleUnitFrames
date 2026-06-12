--- Auras3/MSUF_Auras3_EditMode.lua
--- Cold-path edit mode preview and movement for the oUF-style Auras3 runtime.
---
--- This file intentionally does not hook UNIT_AURA and does not add per-aura
--- render callbacks. It owns only edit-mode fake previews, drag movement, and
--- config refresh bridges.
local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}
_G.MSUF_NS = MSUF

local type, tonumber, tostring, pairs = type, tonumber, tostring, pairs
local math_floor, math_min, math_max, math_ceil = math.floor, math.min, math.max, math.ceil
local CreateFrame = _G.CreateFrame
local UIParent = _G.UIParent
local GetCursorPosition = _G.GetCursorPosition
local InCombatLockdown = _G.InCombatLockdown
local C_Timer = _G.C_Timer

local A3 = MSUF.MSUF_Auras3
if type(A3) ~= "table" then
    A3 = {}
    MSUF.MSUF_Auras3 = A3
end
_G.MSUF_Auras3 = A3

if A3.__editModeLoaded then return end
A3.__editModeLoaded = true

A3.EditMode = (type(A3.EditMode) == "table") and A3.EditMode or {}
local EM = A3.EditMode

local AURA_UNITS = { "player", "target", "focus", "boss1", "boss2", "boss3", "boss4", "boss5" }
local BOSS_UNITS = { boss1=true, boss2=true, boss3=true, boss4=true, boss5=true }
local GROUPS = {
    buff = {
        label = "Buffs",
        xKey = "buffGroupOffsetX",
        yKey = "buffGroupOffsetY",
        sizeKey = "buffGroupIconSize",
        anchorKey = "buffAnchor",
        layerKey = "buffLayer",
        maxKey = "maxBuffs",
        showKey = "showBuffs",
        perRowKey = "buffPerRow",
        growthKey = "buffGrowthX",
        wrapKey = "buffGrowthY",
        texture = "Interface\\Icons\\Spell_Holy_WordFortitude",
        color = { 0.16, 0.82, 0.35, 0.28 },
        defaultAnchor = "BOTTOMRIGHT",
        defaultLayer = 5,
    },
    debuff = {
        label = "Debuffs",
        xKey = "debuffGroupOffsetX",
        yKey = "debuffGroupOffsetY",
        sizeKey = "debuffGroupIconSize",
        anchorKey = "debuffAnchor",
        layerKey = "debuffLayer",
        maxKey = "maxDebuffs",
        showKey = "showDebuffs",
        perRowKey = "debuffPerRow",
        growthKey = "debuffGrowthX",
        wrapKey = "debuffGrowthY",
        texture = "Interface\\Icons\\Spell_Shadow_ShadowWordPain",
        color = { 0.92, 0.20, 0.20, 0.28 },
        defaultAnchor = "TOPLEFT",
        defaultLayer = 6,
    },
}

local LANE_STYLE_KEYS = {
    buff = {
        stackCountAnchor = "buffStackCountAnchor",
        stackTextSize = "buffStackTextSize",
        stackTextOffsetX = "buffStackTextOffsetX",
        stackTextOffsetY = "buffStackTextOffsetY",
        cooldownTextSize = "buffCooldownTextSize",
        cooldownTextOffsetX = "buffCooldownTextOffsetX",
        cooldownTextOffsetY = "buffCooldownTextOffsetY",
    },
    debuff = {
        stackCountAnchor = "debuffStackCountAnchor",
        stackTextSize = "debuffStackTextSize",
        stackTextOffsetX = "debuffStackTextOffsetX",
        stackTextOffsetY = "debuffStackTextOffsetY",
        cooldownTextSize = "debuffCooldownTextSize",
        cooldownTextOffsetX = "debuffCooldownTextOffsetX",
        cooldownTextOffsetY = "debuffCooldownTextOffsetY",
    },
}

local W8 = "Interface\\Buttons\\WHITE8X8"
local HEADER_H = 18
local PREVIEW_ICONS = 4

local function Clamp(v, defaultValue, minValue, maxValue)
    v = tonumber(v)
    if not v then v = defaultValue end
    if minValue and v < minValue then v = minValue end
    if maxValue and v > maxValue then v = maxValue end
    return v
end

local function Round(v)
    v = tonumber(v) or 0
    if v < -4096 then v = -4096 elseif v > 4096 then v = 4096 end
    if v < 0 then return -math_floor((-v) + 0.5) end
    return math_floor(v + 0.5)
end

local function IsEditModeActive()
    local st = rawget(_G, "MSUF_EditState")
    return (st and st.active == true) or rawget(_G, "MSUF_UnitEditModeActive") == true
end

local function UnitPreviewActive(unit)
    return IsEditModeActive()
        or (BOSS_UNITS[unit] == true and rawget(_G, "MSUF2_BossUnitframePreviewActive") == true)
end

local function IsConfigBlocked()
    if InCombatLockdown and InCombatLockdown() then return true end
    if _G.UnitAffectingCombat and _G.UnitAffectingCombat("player") then return true end
    if _G.MSUF_InCombat == true then return true end
    return false
end

local function RequestUnitFrameMenuPreview(reason)
    local fn = _G.MSUF_UFPreview_RequestRefresh
    if type(fn) == "function" then fn(reason or "AURAS3_EDITMODE") end
end

local function NormalizeKind(kind)
    kind = (type(kind) == "string") and kind:lower() or "buff"
    if kind == "buffs" then return "buff" end
    if kind == "debuffs" then return "debuff" end
    if GROUPS[kind] then return kind end
    return "buff"
end

local function UnitLabel(unit)
    if unit == "player" then return "Player" end
    if unit == "target" then return "Target" end
    if unit == "focus" then return "Focus" end
    if BOSS_UNITS[unit] then return "Boss " .. tostring(unit):match("%d+") end
    return tostring(unit or "")
end

local function EnsureDB()
    local auras, shared
    if A3.EnsureDB then
        auras, shared = A3.EnsureDB()
    else
        local db = _G.MSUF_DB
        auras = db and (db.auras3 or db.auras3)
        shared = auras and auras.shared
    end
    if type(auras) ~= "table" then return nil, nil end
    if type(shared) ~= "table" then
        shared = {}
        auras.shared = shared
    end
    return auras, shared
end

local function UnitEnabled(auras, unit)
    if type(auras) ~= "table" or auras.enabled ~= true then return false end
    if unit == "player" then return auras.showPlayer == true end
    if unit == "target" then return auras.showTarget == true end
    if unit == "focus" then return auras.showFocus == true end
    if BOSS_UNITS[unit] then return auras.showBoss == true end
    return false
end

local function GetFrame(unit)
    if not unit then return nil end
    local frames = _G.MSUF_UnitFrames
    return (A3._runtimeFrames and A3._runtimeFrames[unit])
        or (A3._unitFrameOwners and A3._unitFrameOwners[unit])
        or (frames and frames[unit])
        or _G["MSUF_" .. unit]
end

local function FrameScaleRelativeToUIParent(frame)
    local frameScale = frame and frame.GetEffectiveScale and frame:GetEffectiveScale()
    local uiScale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()
    frameScale = tonumber(frameScale) or 1
    uiScale = tonumber(uiScale) or 1
    if frameScale <= 0 then frameScale = 1 end
    if uiScale <= 0 then uiScale = 1 end
    local scale = frameScale / uiScale
    if scale <= 0 then return 1 end
    return scale
end

local function ApplyGroupScaleForFrame(group, frame)
    local scale = FrameScaleRelativeToUIParent(frame)
    if group and group.SetScale and group._msufA3FrameScale ~= scale then
        group:SetScale(scale)
        group._msufA3FrameScale = scale
    end
    return scale
end

local function GetLayout(auras, unit, create)
    if type(auras) ~= "table" or not unit then return nil end
    if create then
        auras.perUnit = (type(auras.perUnit) == "table") and auras.perUnit or {}
        local pu = auras.perUnit[unit]
        if type(pu) ~= "table" then
            pu = {}
            auras.perUnit[unit] = pu
        end
        pu.overrideLayout = true
        pu.layout = (type(pu.layout) == "table") and pu.layout or {}
        return pu.layout, pu
    end

    local pu = auras.perUnit and auras.perUnit[unit]
    if pu and pu.overrideLayout == true and type(pu.layout) == "table" then
        return pu.layout, pu
    end
    return nil, pu
end

local function GetSharedLayout(auras, unit)
    local pu = auras and auras.perUnit and auras.perUnit[unit]
    if pu and pu.overrideSharedLayout == true and type(pu.layoutShared) == "table" then
        return pu.layoutShared
    end
    return nil
end

local function ReadNumber(shared, layout, key, defaultValue, minValue, maxValue)
    local v = shared and shared[key]
    if layout and layout[key] ~= nil then v = layout[key] end
    return Clamp(v, defaultValue, minValue, maxValue)
end

local function ReadRawNumber(shared, layout, key)
    local v = layout and layout[key]
    if v == nil then v = shared and shared[key] end
    return tonumber(v)
end

local function ReadLaneTextNumber(shared, layout, kind, key, defaultValue, minValue, maxValue)
    kind = NormalizeKind(kind)
    local laneKey = kind and LANE_STYLE_KEYS[kind] and LANE_STYLE_KEYS[kind][key]
    local v = laneKey and ReadRawNumber(shared, layout, laneKey) or nil
    if v == nil then v = ReadRawNumber(shared, layout, key) end
    return Clamp(v, defaultValue, minValue, maxValue)
end

local function ReadLaneTextAnchor(shared, layoutShared, kind)
    kind = NormalizeKind(kind)
    local laneKey = kind and LANE_STYLE_KEYS[kind] and LANE_STYLE_KEYS[kind].stackCountAnchor
    local anchor = laneKey and ((layoutShared and layoutShared[laneKey]) or (shared and shared[laneKey])) or nil
    anchor = anchor or (layoutShared and layoutShared.stackCountAnchor) or (shared and shared.stackCountAnchor) or "TOPRIGHT"
    if anchor ~= "TOPLEFT" and anchor ~= "BOTTOMLEFT" and anchor ~= "BOTTOMRIGHT" then
        anchor = "TOPRIGHT"
    end
    return anchor
end

local function ReadTextConfig(unit, kind)
    local auras, shared = EnsureDB()
    local layout = GetLayout(auras, unit, false)
    local ls = GetSharedLayout(auras, unit)
    return {
        stackSize = ReadLaneTextNumber(shared, layout, kind, "stackTextSize", 14, 6, 40),
        stackX = ReadLaneTextNumber(shared, layout, kind, "stackTextOffsetX", -1, -2000, 2000),
        stackY = ReadLaneTextNumber(shared, layout, kind, "stackTextOffsetY", 1, -2000, 2000),
        cooldownSize = ReadLaneTextNumber(shared, layout, kind, "cooldownTextSize", 14, 6, 40),
        cooldownX = ReadLaneTextNumber(shared, layout, kind, "cooldownTextOffsetX", 0, -2000, 2000),
        cooldownY = ReadLaneTextNumber(shared, layout, kind, "cooldownTextOffsetY", 0, -2000, 2000),
        stackAnchor = ReadLaneTextAnchor(shared, ls, kind),
    }
end

local function ReadGroupConfig(unit, kind)
    kind = NormalizeKind(kind)
    local spec = GROUPS[kind]
    local auras, shared = EnsureDB()
    local layout = GetLayout(auras, unit, false)
    local ls = GetSharedLayout(auras, unit)

    local baseX = ReadNumber(shared, layout, "offsetX", 0, -4096, 4096)
    local baseY = ReadNumber(shared, layout, "offsetY", 6, -4096, 4096)
    local hasX = (layout and type(layout[spec.xKey]) == "number") or (shared and type(shared[spec.xKey]) == "number")
    local hasY = (layout and type(layout[spec.yKey]) == "number") or (shared and type(shared[spec.yKey]) == "number")
    local x = (layout and type(layout[spec.xKey]) == "number" and layout[spec.xKey])
        or (shared and type(shared[spec.xKey]) == "number" and shared[spec.xKey])
        or baseX
    local y = (layout and type(layout[spec.yKey]) == "number" and layout[spec.yKey])
        or (shared and type(shared[spec.yKey]) == "number" and shared[spec.yKey])
        or baseY
    if kind == "buff" and not hasY then
        y = baseY + Clamp(shared and shared.buffOffsetY, 30, -4096, 4096)
    end
    if not hasX and kind == "buff" then
        x = baseX + Clamp(shared and shared.buffOffsetX, 0, -4096, 4096)
    end

    local size = (layout and type(layout[spec.sizeKey]) == "number" and layout[spec.sizeKey])
        or (shared and type(shared[spec.sizeKey]) == "number" and shared[spec.sizeKey])
        or (layout and type(layout.iconSize) == "number" and layout.iconSize)
        or (shared and type(shared.iconSize) == "number" and shared.iconSize)
        or 26

    local spacing = ReadNumber(shared, layout, "spacing", 2, 0, 64)
    local perRow = (ls and type(ls[spec.perRowKey]) == "number" and ls[spec.perRowKey])
        or (shared and type(shared[spec.perRowKey]) == "number" and shared[spec.perRowKey])
        or (ls and type(ls.perRow) == "number" and ls.perRow)
        or (shared and shared.perRow)
        or 12
    local maxN = (ls and type(ls[spec.maxKey]) == "number" and ls[spec.maxKey])
        or (shared and shared[spec.maxKey])
        or (shared and shared.maxIcons)
        or 12
    local growth = (ls and ls[spec.growthKey])
        or (shared and shared[spec.growthKey])
        or (ls and ls.growth)
        or (shared and shared.growth)
        or "RIGHT"
    if growth ~= "RIGHT" and growth ~= "LEFT" and growth ~= "UP" and growth ~= "DOWN" then growth = "RIGHT" end
    local rowWrap = (ls and ls[spec.wrapKey])
        or (shared and shared[spec.wrapKey])
        or (ls and ls.rowWrap)
        or (shared and shared.rowWrap)
        or "DOWN"
    if rowWrap ~= "UP" and rowWrap ~= "DOWN" then rowWrap = "DOWN" end
    local anchor = (layout and layout[spec.anchorKey])
        or (shared and shared[spec.anchorKey])
        or spec.defaultAnchor
        or "TOPLEFT"
    if anchor ~= "TOPLEFT" and anchor ~= "TOPRIGHT" and anchor ~= "BOTTOMLEFT" and anchor ~= "BOTTOMRIGHT" and anchor ~= "CENTER" then
        anchor = spec.defaultAnchor or "TOPLEFT"
    end
    local layer = (layout and layout[spec.layerKey] ~= nil and layout[spec.layerKey])
        or (shared and shared[spec.layerKey])
        or spec.defaultLayer
        or 5

    return {
        x = Round(x),
        y = Round(y),
        anchor = anchor,
        layer = Clamp(layer, spec.defaultLayer or 5, 1, 15),
        size = Clamp(size, 26, 1, 128),
        spacing = spacing,
        perRow = Clamp(perRow, 12, 1, 40),
        max = Clamp(maxN, 12, 0, 80),
        growth = growth,
        rowWrap = rowWrap,
        show = shared and shared[spec.showKey] ~= false,
    }
end

local function AnchorBase(anchor, frame)
    local w = frame and frame.GetWidth and frame:GetWidth() or 0
    local h = frame and frame.GetHeight and frame:GetHeight() or 0
    anchor = tostring(anchor or "TOPLEFT")
    if anchor == "TOPRIGHT" then return w, h end
    if anchor == "BOTTOMLEFT" then return 0, 0 end
    if anchor == "BOTTOMRIGHT" then return w, 0 end
    if anchor == "CENTER" then return w * 0.5, h * 0.5 end
    return 0, h
end

local function WriteOffset(auras, unit, kind, x, y)
    kind = NormalizeKind(kind)
    local spec = GROUPS[kind]
    local layout = GetLayout(auras, unit, true)
    if not layout then return end
    layout[spec.xKey] = Round(x)
    layout[spec.yKey] = Round(y)
end

local function PromoteRuntimeLayout(unit, kind)
    kind = NormalizeKind(kind or rawget(_G, "MSUF_EM2_ActiveAuraGroup"))
    local spec = GROUPS[kind]
    local auras, shared = EnsureDB()
    local layout = GetLayout(auras, unit, true)
    if not layout or not shared then return end

    local hasGroupOffset = type(layout[spec.xKey]) == "number" or type(shared[spec.xKey]) == "number"
    if hasGroupOffset then
        local cfg = ReadGroupConfig(unit, kind)
        layout.offsetX = cfg.x
        layout.offsetY = cfg.y
    end

    local hasGroupSize = type(layout[spec.sizeKey]) == "number" or type(shared[spec.sizeKey]) == "number"
    if hasGroupSize then
        layout.iconSize = ReadGroupConfig(unit, kind).size
    end
end

local function ApplyDragUnit(auras, unit, moverKind, x, y)
    WriteOffset(auras, unit, moverKind, x, y)
    local other = EM.groups and EM.groups[unit] and EM.groups[unit][moverKind]
    local frame = other and GetFrame(unit)
    if other and frame then
        local cfg = ReadGroupConfig(unit, moverKind)
        local baseX, baseY = AnchorBase(cfg.anchor, frame)
        ApplyGroupScaleForFrame(other, frame)
        other:ClearAllPoints()
        other:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", baseX + x, baseY + y)
    end
end

local function RefreshAffectedRuntimeUnits(unit, shared)
    if BOSS_UNITS[unit] and shared and shared.bossEditTogether ~= false then
        for i = 1, 5 do A3.RefreshUnit("boss" .. i) end
    elseif unit then
        A3.RefreshUnit(unit)
    end
end

local function ApplyDragDelta(self, dx, dy)
    if IsConfigBlocked() then return end
    local auras = self._dragAuras
    local shared = self._dragShared
    if not (auras and shared) then
        auras, shared = EnsureDB()
        self._dragAuras = auras
        self._dragShared = shared
    end
    if not auras or not shared then return end
    local startX = self._dragStartOffsetX or 0
    local startY = self._dragStartOffsetY or 0
    local x = Round(startX + dx)
    local y = Round(startY + dy)
    if self._lastDragX == x and self._lastDragY == y then return end
    self._lastDragX = x
    self._lastDragY = y
    local baseUnit = self._msufA3Unit
    local moverKind = self._msufA3MoverKind

    if BOSS_UNITS[baseUnit] and shared.bossEditTogether ~= false then
        for i = 1, 5 do
            ApplyDragUnit(auras, "boss" .. i, moverKind, x, y)
        end
    elseif baseUnit then
        ApplyDragUnit(auras, baseUnit, moverKind, x, y)
    end

    local sync = _G.MSUF_SyncAuras3PositionPopup
    if type(sync) == "function" then sync(baseUnit) end
end

local function AuraGroupDragOnUpdate(me)
    if not me._dragging then me:SetScript("OnUpdate", nil); return end
    local uiScale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    local mx, my = GetCursorPosition()
    mx, my = mx / uiScale, my / uiScale
    local dx = mx - (me._dragStartCursorX or mx)
    local dy = my - (me._dragStartCursorY or my)
    if not me._dragMoved then
        if (dx * dx + dy * dy) < 9 then return end
        me._dragMoved = true
    end

    local Snap = _G.MSUF_EM2 and _G.MSUF_EM2.Snap
    if Snap and Snap.IsEnabled and Snap.IsEnabled() and Snap.Apply then
        if Snap.HideGuides then Snap.HideGuides() end
        local sx, sy = Snap.Apply((me._snapStartCX or 0) + dx, (me._snapStartCY or 0) + dy, me._snapHW or 0, me._snapHH or 0, me._msufA3SnapName)
        dx = sx - (me._snapStartCX or 0)
        dy = sy - (me._snapStartCY or 0)
    end
    local frameScale = tonumber(me._dragFrameScale) or tonumber(me._msufA3FrameScale) or 1
    if frameScale <= 0 then frameScale = 1 end
    ApplyDragDelta(me, dx / frameScale, dy / frameScale)
end

local function ApplyGlobalFont(fs, size)
    if not fs then return end
    local fontPath, fontFlags, r, g, b, _, useShadow
    local gfs = _G.MSUF_GetGlobalFontSettings
    if type(gfs) == "function" then
        fontPath, fontFlags, r, g, b, _, useShadow = gfs()
    end
    fontPath = fontPath or _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    fontFlags = fontFlags or "OUTLINE"
    local fontKey = (_G.MSUF_DB and _G.MSUF_DB.general and _G.MSUF_DB.general.fontKey) or "FRIZQT"
    if type(_G.MSUF_SetFontSafe) == "function" then
        _G.MSUF_SetFontSafe(fs, fontPath, size or 14, fontFlags, fontKey)
    elseif fs.SetFont then
        fs:SetFont(fontPath, size or 14, fontFlags)
    end
    if fs.SetTextColor then fs:SetTextColor(r or 1, g or 1, b or 1, 1) end
    if fs.SetShadowOffset then
        if useShadow then fs:SetShadowOffset(1, -1) else fs:SetShadowOffset(0, 0) end
    end
end

local function PlaceStackText(fs, owner, cfg)
    if not fs or not owner or not cfg then return end
    fs:ClearAllPoints()
    if cfg.stackAnchor == "TOPLEFT" then
        fs:SetPoint("TOPLEFT", owner, "TOPLEFT", cfg.stackX, cfg.stackY)
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("TOP")
    elseif cfg.stackAnchor == "BOTTOMLEFT" then
        fs:SetPoint("BOTTOMLEFT", owner, "BOTTOMLEFT", cfg.stackX, cfg.stackY)
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("BOTTOM")
    elseif cfg.stackAnchor == "BOTTOMRIGHT" then
        fs:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", cfg.stackX, cfg.stackY)
        fs:SetJustifyH("RIGHT")
        fs:SetJustifyV("BOTTOM")
    else
        fs:SetPoint("TOPRIGHT", owner, "TOPRIGHT", cfg.stackX, cfg.stackY)
        fs:SetJustifyH("RIGHT")
        fs:SetJustifyV("TOP")
    end
end

local function ApplyRuntimeButtonStyle(button, unit)
    if not button then return end
    local cfg = ReadTextConfig(unit)
    local count = button.Count
    if count then
        ApplyGlobalFont(count, cfg.stackSize)
        PlaceStackText(count, button, cfg)
    end
end

local function PostCreateRuntimeButton(element, button)
    ApplyRuntimeButtonStyle(button, element and element.unit)
end

local function StyleRuntimeLane(lane, unit)
    if not lane then return end
    lane.PostCreateButton = PostCreateRuntimeButton
    local n = lane.createdButtons or #lane or 0
    for i = 1, n do
        ApplyRuntimeButtonStyle(lane[i], unit)
    end
end

local function StyleRuntimeButtons(unit)
    local frame = GetFrame(unit)
    local element = frame and frame.Auras
    if not element then return end

    StyleRuntimeLane(element.Buffs, unit)
    StyleRuntimeLane(element.Debuffs, unit)
    if not element.Buffs and not element.Debuffs then
        StyleRuntimeLane(element, unit)
    end
end

local function SetRuntimeAuraHidden(unit, hidden)
    local frame = GetFrame(unit)
    local element = frame and frame.Auras
    if not element or not element.SetAlpha then return end
    if hidden then
        if element._msufA3EditModeAlpha == nil and element.GetAlpha then
            element._msufA3EditModeAlpha = element:GetAlpha()
        end
        element:SetAlpha(0)
    elseif element._msufA3EditModeAlpha ~= nil then
        element:SetAlpha(element._msufA3EditModeAlpha)
        element._msufA3EditModeAlpha = nil
    end
end

local function StyleLabel(fs)
    ApplyGlobalFont(fs, 11)
    if fs and fs.SetTextColor then fs:SetTextColor(0.92, 0.96, 1, 0.95) end
end

local function EnsureIcon(group, index)
    local icons = group._icons
    if not icons then
        icons = {}
        group._icons = icons
    end
    local icon = icons[index]
    if icon then return icon end

    icon = CreateFrame("Frame", nil, group, "BackdropTemplate")
    icon:SetBackdrop({ bgFile = W8, edgeFile = W8, edgeSize = 1 })
    icon:SetBackdropColor(0, 0, 0, 0)
    icon:SetBackdropBorderColor(0, 0, 0, 0)

    local tex = icon:CreateTexture(nil, "BORDER")
    tex:SetAllPoints(icon)
    tex:SetTexCoord(0, 1, 0, 1)
    icon.Icon = tex

    local shade = icon:CreateTexture(nil, "ARTWORK")
    shade:SetAllPoints(icon)
    shade:SetColorTexture(0, 0, 0, 0)
    icon.Shade = shade

    local cd = icon:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cd:SetPoint("CENTER", icon, "CENTER", 0, 0)
    ApplyGlobalFont(cd, 14)
    cd:SetText("1m")
    icon.CooldownText = cd

    local count = icon:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ApplyGlobalFont(count, 14)
    count:SetText(index == 1 and "3" or "")
    icon.Count = count

    icons[index] = icon
    return icon
end

local function ApplyPreviewIconText(icon, unit, cfg)
    cfg = cfg or ReadTextConfig(unit)
    if icon.Count then
        ApplyGlobalFont(icon.Count, cfg.stackSize)
        PlaceStackText(icon.Count, icon, cfg)
    end
    if icon.CooldownText then
        ApplyGlobalFont(icon.CooldownText, cfg.cooldownSize)
        icon.CooldownText:ClearAllPoints()
        icon.CooldownText:SetPoint("CENTER", icon, "CENTER", cfg.cooldownX, cfg.cooldownY)
    end
end

local function CreateGroup(unit, kind)
    kind = NormalizeKind(kind)
    EM.groups = EM.groups or {}
    local byUnit = EM.groups[unit]
    if not byUnit then
        byUnit = {}
        EM.groups[unit] = byUnit
    end
    if byUnit[kind] then return byUnit[kind] end

    local spec = GROUPS[kind]
    local safeUnit = tostring(unit):gsub("%W", "")
    local name = "MSUF_A3_" .. safeUnit .. "_" .. kind .. "Preview"
    local group = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    group:SetFrameStrata("DIALOG")
    group:SetFrameLevel(160)
    group:SetClampedToScreen(false)
    group:EnableMouse(true)
    group:SetBackdrop({ bgFile = W8, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    group:SetBackdropColor(0.02, 0.03, 0.08, 0.28)
    group:SetBackdropBorderColor(spec.color[1], spec.color[2], spec.color[3], 0.72)

    local header = CreateFrame("Frame", nil, group, "BackdropTemplate")
    header:SetPoint("TOPLEFT", group, "TOPLEFT", 2, -2)
    header:SetPoint("TOPRIGHT", group, "TOPRIGHT", -2, -2)
    header:SetHeight(HEADER_H)
    header:SetBackdrop({ bgFile = W8 })
    header:SetBackdropColor(spec.color[1], spec.color[2], spec.color[3], spec.color[4])
    group.Header = header

    local label = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", header, "LEFT", 6, 0)
    label:SetPoint("RIGHT", header, "RIGHT", -6, 0)
    label:SetJustifyH("LEFT")
    StyleLabel(label)
    label:SetText(UnitLabel(unit) .. " " .. spec.label)
    group.Label = label

    group._msufA3Unit = unit
    group._msufA3MoverKind = kind
    group._msufA3SnapName = name
    group:Hide()

    group:SetScript("OnMouseDown", function(self, button)
        _G.MSUF_EM2_ActiveAuraGroup = self._msufA3MoverKind
        _G.MSUF_EM2_ActiveAuraUnit = self._msufA3Unit

        if button == "RightButton" then
            if IsEditModeActive() and not IsConfigBlocked() and type(_G.MSUF_OpenAuras3PositionPopup) == "function" then
                _G.MSUF_OpenAuras3PositionPopup(self._msufA3Unit, self)
            end
            return
        end
        if button ~= "LeftButton" or not IsEditModeActive() or IsConfigBlocked() then return end

        local before = _G.MSUF_EM_UndoBeforeChange
        if type(before) == "function" and not _G.MSUF__UndoRestoring then
            before("aura", self._msufA3Unit)
        end

        local cfg = ReadGroupConfig(self._msufA3Unit, self._msufA3MoverKind)
        self._dragStartOffsetX = cfg.x
        self._dragStartOffsetY = cfg.y
        self._dragFrameScale = ApplyGroupScaleForFrame(self, GetFrame(self._msufA3Unit))

        local scale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
        local cx, cy = GetCursorPosition()
        self._dragStartCursorX = cx / scale
        self._dragStartCursorY = cy / scale
        self._dragMoved = false
        self._dragging = true
        self._lastDragX = nil
        self._lastDragY = nil

        local l, r, t, b = self:GetLeft() or 0, self:GetRight() or 0, self:GetTop() or 0, self:GetBottom() or 0
        self._snapStartCX = (l + r) * 0.5
        self._snapStartCY = (t + b) * 0.5
        self._snapHW = (r - l) * 0.5
        self._snapHH = (t - b) * 0.5

        self:SetScript("OnUpdate", AuraGroupDragOnUpdate)
    end)

    group:SetScript("OnMouseUp", function(self)
        local moved = self._dragMoved == true
        self._dragging = false
        self:SetScript("OnUpdate", nil)
        self._dragAuras = nil
        self._dragShared = nil
        local Snap = _G.MSUF_EM2 and _G.MSUF_EM2.Snap
        if Snap and Snap.HideGuides then Snap.HideGuides() end

        if moved then
            local _, shared = EnsureDB()
            RefreshAffectedRuntimeUnits(self._msufA3Unit, shared)
            RequestUnitFrameMenuPreview("AURAS3_EDITMODE_DRAG_END")
            local sync = _G.MSUF_SyncAuras3PositionPopup
            if type(sync) == "function" then sync(self._msufA3Unit) end
            self._lastDragX = nil
            self._lastDragY = nil
            self._dragMoved = false
            return
        end

        if IsEditModeActive() and not IsConfigBlocked() and type(_G.MSUF_OpenAuras3PositionPopup) == "function" then
            _G.MSUF_OpenAuras3PositionPopup(self._msufA3Unit, self)
        end
        self._lastDragX = nil
        self._lastDragY = nil
    end)

    byUnit[kind] = group
    return group
end

function EM.HideUnit(unit)
    local byUnit = EM.groups and EM.groups[unit]
    SetRuntimeAuraHidden(unit, false)
    if not byUnit then return end
    for _, group in pairs(byUnit) do
        if group then group:Hide() end
    end
end

function EM.RefreshUnit(unit)
    if not unit then return end
    if not UnitPreviewActive(unit) then
        EM.HideUnit(unit)
        return
    end

    local auras, shared = EnsureDB()
    if not shared or shared.showInEditMode == false or not UnitEnabled(auras, unit) then
        EM.HideUnit(unit)
        return
    end

    local frame = GetFrame(unit)
    if not frame then
        EM.HideUnit(unit)
        return
    end

    SetRuntimeAuraHidden(unit, true)

    for kind, spec in pairs(GROUPS) do
        local cfg = ReadGroupConfig(unit, kind)
        local metrics = type(A3.BuildAuraLaneMetrics) == "function" and A3.BuildAuraLaneMetrics(unit, kind) or nil
        local group = CreateGroup(unit, kind)
        if not (cfg.show and cfg.max > 0 and (not metrics or metrics.enabled ~= false)) then
            group:Hide()
        else
            local textCfg = ReadTextConfig(unit, kind)
            local shownIcons = math_min(PREVIEW_ICONS, (metrics and metrics.num) or cfg.max)
            if shownIcons < 1 then shownIcons = 1 end
            local size = (metrics and metrics.size) or cfg.size
            local step = (metrics and metrics.step) or (cfg.size + cfg.spacing)
            local perRow = (metrics and metrics.perRow) or cfg.perRow
            local fallbackRows = math_ceil(math_max(cfg.max, 1) / math_max(cfg.perRow, 1))
            local laneW = (metrics and metrics.width) or math_max(1, cfg.perRow * cfg.size + (cfg.perRow - 1) * cfg.spacing)
            local laneH = (metrics and metrics.height) or math_max(1, fallbackRows * cfg.size + (fallbackRows - 1) * cfg.spacing)
            local growthX = (metrics and metrics.growthX) or ((cfg.growth == "LEFT") and -1 or 1)
            local growthY = (metrics and metrics.growthY) or ((cfg.rowWrap == "UP") and 1 or -1)
            local x = (metrics and metrics.x) or cfg.x
            local y = (metrics and metrics.y) or cfg.y
            local baseX, baseY = AnchorBase(cfg.anchor, frame)

            if group.SetClampedToScreen then group:SetClampedToScreen(false) end
            ApplyGroupScaleForFrame(group, frame)
            group:ClearAllPoints()
            group:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", baseX + x, baseY + y)
            group:SetSize(laneW, laneH + HEADER_H)
            group:SetFrameLevel(160 + (tonumber(cfg.layer) or 5))
            if group.Label then
                group.Label:SetText(UnitLabel(unit) .. " " .. spec.label)
                StyleLabel(group.Label)
            end

            for i = 1, shownIcons do
                local icon = EnsureIcon(group, i)
                icon:SetSize(size, size)
                icon:ClearAllPoints()
                local col = (i - 1) % math_max(perRow, 1)
                local row = math_floor((i - 1) / math_max(perRow, 1))
                icon:SetPoint("BOTTOMLEFT", group, "BOTTOMLEFT", col * step * growthX, row * step * growthY)
                if icon.Icon then icon.Icon:SetTexture(spec.texture) end
                if icon.Count then icon.Count:SetText(i == 1 and "3" or "") end
                if icon.CooldownText then icon.CooldownText:SetText(i == 1 and "1m" or "32") end
                ApplyPreviewIconText(icon, unit, textCfg)
                icon:Show()
            end

            local icons = group._icons
            if icons then
                for i = shownIcons + 1, #icons do
                    if icons[i] then icons[i]:Hide() end
                end
            end

            group:Show()
        end
    end
end

function EM.RefreshAll()
    for i = 1, #AURA_UNITS do
        EM.RefreshUnit(AURA_UNITS[i])
    end
end

function EM.HideAll()
    if not EM.groups then return end
    for unit in pairs(EM.groups) do
        EM.HideUnit(unit)
    end
end

local CoreRefreshAll = A3.RefreshAll
function A3.RefreshAll(...)
    local ret
    if type(CoreRefreshAll) == "function" then ret = CoreRefreshAll(...) end
    for i = 1, #AURA_UNITS do
        StyleRuntimeButtons(AURA_UNITS[i])
    end
    if IsEditModeActive() then
        EM.RefreshAll()
    end
    return ret
end

local CoreEnableFrame = A3.EnableFrame
if type(CoreEnableFrame) == "function" then
    function A3.EnableFrame(frame, ...)
        local ret = CoreEnableFrame(frame, ...)
        if frame and frame.unit then
            StyleRuntimeButtons(frame.unit)
            if UnitPreviewActive(frame.unit) then
                EM.RefreshUnit(frame.unit)
            end
        end
        return ret
    end
end

local CoreDisableFrame = A3.DisableFrame
if type(CoreDisableFrame) == "function" then
    function A3.DisableFrame(frame, ...)
        if frame and frame.unit then EM.HideUnit(frame.unit) end
        if type(CoreDisableFrame) == "function" then return CoreDisableFrame(frame, ...) end
    end
end

function A3.RefreshUnit(unit)
    if not unit then return end
    if IsEditModeActive() then
        PromoteRuntimeLayout(unit, rawget(_G, "MSUF_EM2_ActiveAuraGroup"))
    end
    if A3.BumpRuntimeConfig then
        A3.BumpRuntimeConfig()
    elseif A3._runtimeConfigGen then
        A3._runtimeConfigGen = A3._runtimeConfigGen + 1
    end
    local frame = GetFrame(unit)
    if frame and frame.Auras then frame.Auras.needFullUpdate = true end
    if A3.RequestUnit then A3.RequestUnit(unit, 0) end
    StyleRuntimeButtons(unit)
    if UnitPreviewActive(unit) then
        EM.RefreshUnit(unit)
    end
end

function A3.UpdateUnitAnchor(unit)
    if not unit then return end
    if IsEditModeActive() then
        PromoteRuntimeLayout(unit, rawget(_G, "MSUF_EM2_ActiveAuraGroup"))
    end
    EM.RefreshUnit(unit)
end

function A3.RefreshEditPreview(unit)
    if unit then return EM.RefreshUnit(unit) end
    return EM.RefreshAll()
end

_G.MSUF_Auras3_RefreshUnit = A3.RefreshUnit
_G.MSUF_Auras3_RefreshAll = A3.RefreshAll
_G.MSUF_Auras3_UpdateUnitAnchor = A3.UpdateUnitAnchor
_G.MSUF_Auras3_RefreshEditPreview = A3.RefreshEditPreview
_G.MSUF_A3_RefreshUnit = _G.MSUF_Auras3_RefreshUnit
_G.MSUF_A3_UpdateUnitAnchor = _G.MSUF_Auras3_UpdateUnitAnchor

_G.MSUF_OpenAuras3PositionPopup = function(unit, parent)
    if parent and parent._msufA3MoverKind then
        _G.MSUF_EM2_ActiveAuraGroup = parent._msufA3MoverKind
        _G.MSUF_EM2_ActiveAuraUnit = unit
    end
    local EM2 = _G.MSUF_EM2
    if EM2 and EM2.Popups then
        return EM2.Popups.Open("aura_" .. tostring(unit or ""), parent)
    elseif EM2 and EM2.AuraPopup then
        return EM2.AuraPopup.Open(unit, parent)
    end
end

local function OnEditModeChanged(active)
    if active then
        EM.RefreshAll()
    else
        EM.HideAll()
        _G.MSUF_EM2_ActiveAuraGroup = nil
        _G.MSUF_EM2_ActiveAuraUnit = nil
    end
end

local function RegisterEditListener()
    if EM._registered then return end
    local reg = _G.MSUF_RegisterAnyEditModeListener
    if type(reg) == "function" then
        reg(OnEditModeChanged)
        EM._registered = true
        if IsEditModeActive() then OnEditModeChanged(true) end
    end
end

RegisterEditListener()
if not EM._registered and C_Timer and C_Timer.After then
    C_Timer.After(0, RegisterEditListener)
end
