--- Auras3/MSUF_Auras3_UnitFrames.lua
--- oUF-style UnitFrame aura element runtime.
---
--- The runtime is intentionally small: one frame-local Auras element owns
--- button creation, aura state tables, sorting, positioning, and UNIT_AURA
--- delta updates.
local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}
_G.MSUF_NS = MSUF

local type, tonumber, next, pairs, select = type, tonumber, next, pairs, select
local table_insert, table_sort = table.insert, table.sort
local math_floor, math_min, math_max, math_ceil = math.floor, math.min, math.max, math.ceil
local string_find = string.find
local CreateFrame = _G.CreateFrame
local UnitExists = _G.UnitExists
local GameTooltip = _G.GameTooltip
local C_Timer = _G.C_Timer
local C_CurveUtil = _G.C_CurveUtil
local C_UnitAuras = _G.C_UnitAuras
local LibStub = _G.LibStub
local issecretvalue = _G.issecretvalue
local STANDARD_TEXT_FONT = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local UF = MSUF.UF

local wipe = _G.wipe or table.wipe or function(t)
    if type(t) ~= "table" then return t end
    for k in pairs(t) do t[k] = nil end
    return t
end

local A3 = MSUF.MSUF_Auras3
if type(A3) ~= "table" then
    A3 = {}
    MSUF.MSUF_Auras3 = A3
end
_G.MSUF_Auras3 = A3

A3.useUnitFrameRuntime = true
A3._runtimeFrames = A3._runtimeFrames or {}
A3._runtimeConfigGen = A3._runtimeConfigGen or 1
A3._slotBuffers = A3._slotBuffers or {}
A3._slotCounts = A3._slotCounts or {}
A3._resolvedUnitConfigs = A3._resolvedUnitConfigs or {}
A3._blacklistHashCache = A3._blacklistHashCache or setmetatable({}, { __mode = "k" })
A3._unitAuraDeferred = A3._unitAuraDeferred or {}

local BOSS_UNITS = { boss1=true, boss2=true, boss3=true, boss4=true, boss5=true }
local GROWTH_OK = { RIGHT=true, LEFT=true, UP=true, DOWN=true }
local WRAP_OK = { DOWN=true, UP=true }
local function EnsureAuraAPIs()
    C_UnitAuras = C_UnitAuras or _G.C_UnitAuras
    return C_UnitAuras
end

local function CaptureSlots(owner, ...)
    owner = owner or "default"
    local buffers = A3._slotBuffers
    local counts = A3._slotCounts
    local slots = buffers[owner]
    if not slots then
        slots = {}
        buffers[owner] = slots
    end

    local n = select("#", ...)
    for i = 1, n do
        slots[i] = select(i, ...)
    end
    for i = n + 1, (counts[owner] or 0) do slots[i] = nil end
    counts[owner] = n
    return slots, n
end

local function QuerySlots(unit, filter, owner)
    local api = C_UnitAuras
    if api and api.GetAuraSlots then
        return CaptureSlots(owner, api.GetAuraSlots(unit, filter))
    end
    return nil, 0
end

local function GetAuraBySlot(unit, slot)
    local api = C_UnitAuras
    return (api and api.GetAuraDataBySlot and unit and slot)
        and api.GetAuraDataBySlot(unit, slot)
        or nil
end

local function GetAuraByID(unit, auraInstanceID)
    local api = C_UnitAuras
    return (api and api.GetAuraDataByAuraInstanceID and unit and auraInstanceID ~= nil)
        and api.GetAuraDataByAuraInstanceID(unit, auraInstanceID)
        or nil
end

local function GetAuraByIndex(unit, index, filter)
    local api = C_UnitAuras
    return (api and api.GetAuraDataByIndex and unit and index)
        and api.GetAuraDataByIndex(unit, index, filter)
        or nil
end

local function GetUnitAuraList(unit, filter)
    local api = C_UnitAuras
    if not (api and api.GetUnitAuras and unit) then return nil end

    local auras = api.GetUnitAuras(unit, filter)
    return type(auras) == "table" and auras or nil
end

local function AuraPassesFilter(unit, auraInstanceID, filter)
    local api = C_UnitAuras
    if not (api and api.IsAuraFilteredOutByInstanceID and unit and auraInstanceID ~= nil and filter) then
        return false
    end
    return not api.IsAuraFilteredOutByInstanceID(unit, auraInstanceID, filter)
end

local function GetDuration(unit, auraInstanceID)
    local api = C_UnitAuras
    return (api and api.GetAuraDuration and unit and auraInstanceID ~= nil)
        and api.GetAuraDuration(unit, auraInstanceID)
        or nil
end

local function GetStackCount(unit, auraInstanceID, minCount, maxCount)
    local api = C_UnitAuras
    return (api and api.GetAuraApplicationDisplayCount and unit and auraInstanceID ~= nil)
        and api.GetAuraApplicationDisplayCount(unit, auraInstanceID, minCount, maxCount)
        or nil
end

local function GetDispelColor(unit, auraInstanceID, curve)
    local api = C_UnitAuras
    return (api and api.GetAuraDispelTypeColor and unit and auraInstanceID ~= nil and curve)
        and api.GetAuraDispelTypeColor(unit, auraInstanceID, curve)
        or nil
end

local function ClampNumber(v, defaultValue, minValue, maxValue)
    v = tonumber(v)
    if not v then v = defaultValue end
    if minValue and v < minValue then v = minValue end
    if maxValue and v > maxValue then v = maxValue end
    return v
end

local function IsSecretValue(value)
    local fn = issecretvalue or _G.issecretvalue
    if type(fn) ~= "function" then return false end
    issecretvalue = fn
    return fn(value) == true
end

local function SafeNumber(value)
    if value == nil or IsSecretValue(value) then return nil end
    return tonumber(value)
end

local function SafeBoolIsFalse(value)
    if IsSecretValue(value) then return false end
    return value == false or value == 0
end

local function CoreDispelOwnsBorder(owner)
    local active = owner and owner._msufActiveElements
    return UF and UF.DispelState and active
        and (active.DispelOverlay == true or active.GroupVisuals == true)
end

local function IsEditMode()
    local st = rawget(_G, "MSUF_EditState")
    return (st and st.active == true) or rawget(_G, "MSUF_UnitEditModeActive") == true
end

local function GetUnitDBEnabled(db, unit)
    if type(db) ~= "table" or db.enabled ~= true then return false end
    if unit == "player" then return db.showPlayer == true end
    if unit == "target" then return db.showTarget == true end
    if unit == "focus" then return db.showFocus == true end
    if BOSS_UNITS[unit] then return db.showBoss == true end
    return false
end

local function BuildFilter(base, onlyMine, onlyImportant)
    local filter = base
    if onlyMine == true then filter = filter .. "|PLAYER" end
    if onlyImportant == true then filter = filter .. "|RAID" end
    return filter
end

local function FilterHasToken(filter, token)
    return type(filter) == "string" and string_find(filter, token, 1, true) ~= nil
end

local function RuntimeDBSnapshot()
    local gen = A3._runtimeConfigGen or 0
    if A3._runtimeDBGen == gen then
        return A3._runtimeAurasDB, A3._runtimeSharedDB
    end

    local auras = A3.EnsureDB and A3.EnsureDB() or nil
    local shared = type(auras) == "table" and auras.shared or nil
    if type(shared) ~= "table" then shared = {} end

    A3._runtimeDBGen = gen
    A3._runtimeAurasDB = auras
    A3._runtimeSharedDB = shared
    return auras, shared
end

local function BlacklistForUnit(auras, shared, unit)
    local list = shared and shared.blacklist
    local pu = auras and auras.perUnit and auras.perUnit[unit]
    if pu and pu.overrideBlacklist == true and type(pu.blacklist) == "table" then
        list = pu.blacklist
    end
    return list
end

local function SpellIDFromBlacklistKey(key)
    if type(key) == "number" then return key end
    if type(key) ~= "string" then return nil end
    return tonumber(key:match("spell:(%d+)") or key:match("#(%d+)") or key:match("^(%d+)$"))
end

local function SafeAuraSpellID(data)
    if type(data) ~= "table" then return nil end
    local spellId = data.spellId
    if spellId == nil or IsSecretValue(spellId) then return nil end
    return tonumber(spellId)
end

local function SafeHashHas(hash, key)
    if type(hash) ~= "table" or key == nil then return false end
    if IsSecretValue(key) then return false end
    return hash[key] == true
end

local function BuildBlacklistHash(list)
    local spells = type(list) == "table" and list.spells
    if type(spells) ~= "table" then return nil end

    local gen = A3._runtimeConfigGen or 0
    local cache = A3._blacklistHashCache[list]
    if cache and cache.gen == gen and cache.source == spells then
        return cache.any and cache.hash or nil
    end

    local hash = cache and cache.hash or {}
    wipe(hash)

    local any = false
    for key, enabled in pairs(spells) do
        if enabled == true then
            local spellID = SpellIDFromBlacklistKey(key)
            if spellID then
                hash[spellID] = true
                any = true
            end
        end
    end

    A3._blacklistHashCache[list] = {
        gen = gen,
        source = spells,
        hash = hash,
        any = any,
    }
    return any and hash or nil
end

local function ResolveGroupFrameConfig(unit, frame)
    local spec = frame and frame.MSUFSpec
    local cfg = spec and spec.scope == "group" and spec.auras or nil
    if not (cfg and cfg.group == true) then
        return nil
    end
    cfg.unit = unit
    return cfg
end

local function ResolveUnitConfig(unit, frame)
    local groupCfg = ResolveGroupFrameConfig(unit, frame)
    if groupCfg then
        return groupCfg
    end

    local gen = A3._runtimeConfigGen or 0
    local cache = A3._resolvedUnitConfigs
    local cacheKey = unit or false
    local cfg = cache[cacheKey]
    if cfg and cfg._runtimeConfigGen == gen then
        return cfg
    end

    local auras, shared = RuntimeDBSnapshot()

    local pu = auras and auras.perUnit and auras.perUnit[unit]
    local lay = (pu and pu.overrideLayout == true and type(pu.layout) == "table") and pu.layout or nil
    local ls = (pu and pu.overrideSharedLayout == true and type(pu.layoutShared) == "table") and pu.layoutShared or nil
    local filters = (pu and pu.overrideFilters == true and type(pu.filters) == "table") and pu.filters or shared.filters
    local buffFilters = type(filters) == "table" and type(filters.buffs) == "table" and filters.buffs or nil
    local debuffFilters = type(filters) == "table" and type(filters.debuffs) == "table" and filters.debuffs or nil
    local blacklistHash = BuildBlacklistHash(BlacklistForUnit(auras, shared, unit))

    if not cfg then
        cfg = {}
        cache[cacheKey] = cfg
    end

    cfg._runtimeConfigGen = gen
    cfg.unit = unit
    cfg.enabled = (A3.UnitFrameAuraEnabled and A3.UnitFrameAuraEnabled(unit) == true) or GetUnitDBEnabled(auras, unit)
    cfg.showBuffs = shared.showBuffs ~= false
    cfg.showDebuffs = shared.showDebuffs ~= false
    cfg.showTooltip = shared.showTooltip == true
    cfg.clickThrough = shared.clickThroughAuras == true
    cfg.showSwipe = shared.showCooldownSwipe ~= false
    cfg.showStacks = shared.showStackCount ~= false
    cfg.iconSize = ClampNumber(shared.iconSize, 26, 1, 128)
    cfg.spacing = ClampNumber(shared.spacing, 2, 0, 64)
    cfg.perRow = ClampNumber(shared.perRow, 12, 1, 40)
    cfg.buffPerRow = ClampNumber(shared.buffPerRow, cfg.perRow, 1, 40)
    cfg.debuffPerRow = ClampNumber(shared.debuffPerRow, cfg.perRow, 1, 40)
    cfg.maxBuffs = ClampNumber(shared.maxBuffs or shared.maxIcons, 12, 0, 80)
    cfg.maxDebuffs = ClampNumber(shared.maxDebuffs or shared.maxIcons, 12, 0, 80)
    cfg.growth = GROWTH_OK[shared.growth] and shared.growth or "RIGHT"
    cfg.rowWrap = WRAP_OK[shared.rowWrap] and shared.rowWrap or "DOWN"
    cfg.buffGrowthX = GROWTH_OK[shared.buffGrowthX] and shared.buffGrowthX or cfg.growth
    cfg.buffGrowthY = WRAP_OK[shared.buffGrowthY] and shared.buffGrowthY or cfg.rowWrap
    cfg.debuffGrowthX = GROWTH_OK[shared.debuffGrowthX] and shared.debuffGrowthX or cfg.growth
    cfg.debuffGrowthY = WRAP_OK[shared.debuffGrowthY] and shared.debuffGrowthY or cfg.rowWrap
    cfg.offsetX = ClampNumber(shared.offsetX, 0, -4096, 4096)
    cfg.offsetY = ClampNumber(shared.offsetY, 6, -4096, 4096)
    cfg.stackAnchor = shared.stackCountAnchor or "BOTTOMRIGHT"
    cfg.buffFilter = BuildFilter("HELPFUL", shared.onlyMyBuffs == true or (buffFilters and buffFilters.onlyMine == true), buffFilters and buffFilters.onlyImportant == true)
    cfg.debuffFilter = BuildFilter("HARMFUL", shared.onlyMyDebuffs == true or (debuffFilters and debuffFilters.onlyMine == true), debuffFilters and debuffFilters.onlyImportant == true)
    cfg.showStealableBuffs = buffFilters and buffFilters.includeStealable == true
    cfg.blacklistHash = blacklistHash

    local hasBuffPerRow = shared.buffPerRow ~= nil
    local hasDebuffPerRow = shared.debuffPerRow ~= nil
    local hasBuffGrowthX = shared.buffGrowthX ~= nil
    local hasBuffGrowthY = shared.buffGrowthY ~= nil
    local hasDebuffGrowthX = shared.debuffGrowthX ~= nil
    local hasDebuffGrowthY = shared.debuffGrowthY ~= nil

    if ls then
        if type(ls.perRow) == "number" then cfg.perRow = ClampNumber(ls.perRow, cfg.perRow, 1, 40) end
        if type(ls.buffPerRow) == "number" then cfg.buffPerRow = ClampNumber(ls.buffPerRow, cfg.perRow, 1, 40); hasBuffPerRow = true end
        if type(ls.debuffPerRow) == "number" then cfg.debuffPerRow = ClampNumber(ls.debuffPerRow, cfg.perRow, 1, 40); hasDebuffPerRow = true end
        if type(ls.maxBuffs) == "number" then cfg.maxBuffs = ClampNumber(ls.maxBuffs, cfg.maxBuffs, 0, 80) end
        if type(ls.maxDebuffs) == "number" then cfg.maxDebuffs = ClampNumber(ls.maxDebuffs, cfg.maxDebuffs, 0, 80) end
        if GROWTH_OK[ls.growth] then cfg.growth = ls.growth end
        if WRAP_OK[ls.rowWrap] then cfg.rowWrap = ls.rowWrap end
        if GROWTH_OK[ls.buffGrowthX] then cfg.buffGrowthX = ls.buffGrowthX; hasBuffGrowthX = true end
        if WRAP_OK[ls.buffGrowthY] then cfg.buffGrowthY = ls.buffGrowthY; hasBuffGrowthY = true end
        if GROWTH_OK[ls.debuffGrowthX] then cfg.debuffGrowthX = ls.debuffGrowthX; hasDebuffGrowthX = true end
        if WRAP_OK[ls.debuffGrowthY] then cfg.debuffGrowthY = ls.debuffGrowthY; hasDebuffGrowthY = true end
    end
    if not hasBuffPerRow then cfg.buffPerRow = cfg.perRow end
    if not hasDebuffPerRow then cfg.debuffPerRow = cfg.perRow end
    if not hasBuffGrowthX then cfg.buffGrowthX = cfg.growth end
    if not hasBuffGrowthY then cfg.buffGrowthY = cfg.rowWrap end
    if not hasDebuffGrowthX then cfg.debuffGrowthX = cfg.growth end
    if not hasDebuffGrowthY then cfg.debuffGrowthY = cfg.rowWrap end

    if lay then
        if type(lay.iconSize) == "number" then cfg.iconSize = ClampNumber(lay.iconSize, cfg.iconSize, 1, 128) end
        if type(lay.spacing) == "number" then cfg.spacing = ClampNumber(lay.spacing, cfg.spacing, 0, 64) end
        if type(lay.offsetX) == "number" then cfg.offsetX = ClampNumber(lay.offsetX, cfg.offsetX, -4096, 4096) end
        if type(lay.offsetY) == "number" then cfg.offsetY = ClampNumber(lay.offsetY, cfg.offsetY, -4096, 4096) end
    end

    local buffX = (lay and type(lay.buffGroupOffsetX) == "number" and lay.buffGroupOffsetX)
        or (shared and type(shared.buffGroupOffsetX) == "number" and shared.buffGroupOffsetX)
    local buffY = (lay and type(lay.buffGroupOffsetY) == "number" and lay.buffGroupOffsetY)
        or (shared and type(shared.buffGroupOffsetY) == "number" and shared.buffGroupOffsetY)
    local debuffX = (lay and type(lay.debuffGroupOffsetX) == "number" and lay.debuffGroupOffsetX)
        or (shared and type(shared.debuffGroupOffsetX) == "number" and shared.debuffGroupOffsetX)
    local debuffY = (lay and type(lay.debuffGroupOffsetY) == "number" and lay.debuffGroupOffsetY)
        or (shared and type(shared.debuffGroupOffsetY) == "number" and shared.debuffGroupOffsetY)
    local buffSize = (lay and type(lay.buffGroupIconSize) == "number" and lay.buffGroupIconSize)
        or (shared and type(shared.buffGroupIconSize) == "number" and shared.buffGroupIconSize)
    local debuffSize = (lay and type(lay.debuffGroupIconSize) == "number" and lay.debuffGroupIconSize)
        or (shared and type(shared.debuffGroupIconSize) == "number" and shared.debuffGroupIconSize)

    cfg.buffOffsetX = ClampNumber(buffX, cfg.offsetX + ClampNumber(shared and shared.buffOffsetX, 0, -4096, 4096), -4096, 4096)
    cfg.buffOffsetY = ClampNumber(buffY, cfg.offsetY + ClampNumber(shared and shared.buffOffsetY, 30, -4096, 4096), -4096, 4096)
    cfg.debuffOffsetX = ClampNumber(debuffX, cfg.offsetX, -4096, 4096)
    cfg.debuffOffsetY = ClampNumber(debuffY, cfg.offsetY, -4096, 4096)
    cfg.buffIconSize = ClampNumber(buffSize, cfg.iconSize, 1, 128)
    cfg.debuffIconSize = ClampNumber(debuffSize, cfg.iconSize, 1, 128)

    return cfg
end

local function EnsureDispelColorCurve()
    if A3._debuffColorCurve then return A3._debuffColorCurve end
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and _G.Enum and _G.Enum.LuaCurveType) then return nil end

    local curve = C_CurveUtil.CreateColorCurve()
    if curve and curve.SetType then curve:SetType(_G.Enum.LuaCurveType.Step) end
    if curve and curve.AddPoint then
        local colors = {
            [0] = _G.DEBUFF_TYPE_NONE_COLOR,
            [1] = _G.DEBUFF_TYPE_MAGIC_COLOR,
            [2] = _G.DEBUFF_TYPE_CURSE_COLOR,
            [3] = _G.DEBUFF_TYPE_DISEASE_COLOR,
            [4] = _G.DEBUFF_TYPE_POISON_COLOR,
            [5] = _G.DEBUFF_TYPE_BLEED_COLOR,
        }
        for idx, color in pairs(colors) do
            if color then curve:AddPoint(idx, color) end
        end
        A3._debuffColorCurve = curve
    end
    return A3._debuffColorCurve
end

local function TooltipForbidden()
    return not GameTooltip or (GameTooltip.IsForbidden and GameTooltip:IsForbidden())
end

local function UpdateTooltip(self)
    if TooltipForbidden() then return end
    local parent = self:GetParent()
    local owner = parent and parent.__owner
    local unit = (owner and owner.unit) or self._msufA3Unit
    if unit and self.auraInstanceID and GameTooltip.SetUnitAuraByAuraInstanceID then
        GameTooltip:SetUnitAuraByAuraInstanceID(unit, self.auraInstanceID)
    end
end

local function Button_OnEnter(self)
    if TooltipForbidden() or not self:IsVisible() then return end
    local parent = self:GetParent()
    local anchor = (parent and parent.tooltipAnchor) or "ANCHOR_BOTTOMRIGHT"
    GameTooltip:SetOwner(self, anchor)
    self:UpdateTooltip()
    GameTooltip:Show()
end

local function Button_OnLeave(self)
    if TooltipForbidden() then return end
    if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
end

local function CreateButton(element, index)
    local button = CreateFrame("Button", nil, element)

    local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cd:SetAllPoints(button)
    cd:SetDrawEdge(false)
    cd:SetDrawSwipe(true)
    button.Cooldown = cd

    local icon = button:CreateTexture(nil, "BORDER")
    icon:SetAllPoints(button)
    button.Icon = icon

    local countFrame = CreateFrame("Frame", nil, button)
    countFrame:SetAllPoints(button)
    countFrame:SetFrameLevel((cd.GetFrameLevel and cd:GetFrameLevel() or button:GetFrameLevel()) + 1)

    local count = countFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    count:SetPoint("BOTTOMRIGHT", countFrame, "BOTTOMRIGHT", -1, 0)
    count:SetText("")
    count:Hide()
    button.Count = count

    local overlay = button:CreateTexture(nil, "OVERLAY")
    overlay:SetTexture([[Interface\Buttons\UI-Debuff-Overlays]])
    overlay:SetAllPoints(button)
    overlay:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
    overlay:Hide()
    button.Overlay = overlay

    local stealable = button:CreateTexture(nil, "OVERLAY")
    stealable:SetTexture([[Interface\TargetingFrame\UI-TargetingFrame-Stealable]])
    stealable:SetPoint("TOPLEFT", -3, 3)
    stealable:SetPoint("BOTTOMRIGHT", 3, -3)
    stealable:SetBlendMode("ADD")
    stealable:Hide()
    button.Stealable = stealable

    button.UpdateTooltip = UpdateTooltip
    button:SetScript("OnEnter", Button_OnEnter)
    button:SetScript("OnLeave", Button_OnLeave)
    button:Hide()

    if element.PostCreateButton then element:PostCreateButton(button) end
    return button
end

local function SetPosition(element, from, to)
    local width = element.width or element.size or 16
    local height = element.height or element.size or 16
    local sizeX = width + (element.spacingX or element.spacing or 0)
    local sizeY = height + (element.spacingY or element.spacing or 0)
    local anchor = element.initialAnchor or "BOTTOMLEFT"
    local growthX = (element.growthX == "LEFT" and -1) or 1
    local growthY = (element.growthY == "DOWN" and -1) or 1
    local cols = element.maxCols or math_floor(element:GetWidth() / sizeX + 0.5)
    if not cols or cols < 1 then cols = 1 end

    for i = from, to do
        local button = element[i]
        if not button then break end

        local col = (i - 1) % cols
        local row = math_floor((i - 1) / cols)
        button:ClearAllPoints()
        button:SetPoint(anchor, element, anchor, col * sizeX * growthX, row * sizeY * growthY)
    end
end

local function ResetButton(button)
    local CT = A3.CooldownText
    if CT and CT.UnregisterButton then CT.UnregisterButton(button) end
    if button.Cooldown then button.Cooldown:Hide() end
    if button.Icon then button.Icon:SetTexture(nil) end
    if button.Overlay then button.Overlay:Hide() end
    if button.Stealable then button.Stealable:Hide() end
    if button.Count then button.Count:SetText(""); button.Count:Hide() end
    button.auraInstanceID = nil
    button.isHarmfulAura = nil
    button._msufA3Unit = nil
    button._msufA3CountShown = false
    button._msufA3OverlayShown = false
    button._msufA3CdTextSize = nil
    button._msufA3CdTextAnchor = nil
end

local TEXT_ANCHORS = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true,
    LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

local function ApplyFontStringStyle(fs, size, anchor)
    if not fs then return end
    size = ClampNumber(size, 10, 6, 32)
    if fs._msufA3FontSize ~= size then
        if type(_G.MSUF_SetFontSafe) == "function" then
            _G.MSUF_SetFontSafe(fs, STANDARD_TEXT_FONT, size, "OUTLINE")
        elseif fs.SetFont then
            fs:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
        end
        fs._msufA3FontSize = size
    end
    anchor = TEXT_ANCHORS[anchor] and anchor or "BOTTOMRIGHT"
    if fs._msufA3Anchor ~= anchor then
        local parent = fs.GetParent and fs:GetParent()
        if not parent then return end
        fs:ClearAllPoints()
        if anchor == "CENTER" then
            fs:SetPoint("CENTER", parent, "CENTER", 0, 0)
        elseif anchor == "TOPLEFT" then
            fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 1, -1)
        elseif anchor == "TOP" then
            fs:SetPoint("TOP", parent, "TOP", 0, -1)
        elseif anchor == "TOPRIGHT" then
            fs:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -1, -1)
        elseif anchor == "LEFT" then
            fs:SetPoint("LEFT", parent, "LEFT", 1, 0)
        elseif anchor == "RIGHT" then
            fs:SetPoint("RIGHT", parent, "RIGHT", -1, 0)
        elseif anchor == "BOTTOMLEFT" then
            fs:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 1, 0)
        elseif anchor == "BOTTOM" then
            fs:SetPoint("BOTTOM", parent, "BOTTOM", 0, 0)
        else
            fs:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -1, 0)
        end
        fs._msufA3Anchor = anchor
    end
end

local function EnsureMasqueGroup()
    local GF = MSUF and MSUF.GF
    if not GF then return nil end
    GF.Masque = GF.Masque or {}
    if GF.Masque.group then return GF.Masque.group end
    local ls = LibStub or _G.LibStub
    if type(ls) ~= "function" then return nil end
    local lib = ls("Masque", true)
    if not (lib and lib.Group) then return nil end
    local group = lib:Group("MSUF", "Group Auras")
    GF.Masque.group = group
    return group
end

local function ApplyMasque(button, element)
    local enabled = element and element.masqueEnabled == true
    if not enabled then
        if button._msufA3MasqueAdded then
            local group = EnsureMasqueGroup()
            if group and group.RemoveButton then group:RemoveButton(button) end
            button._msufA3MasqueAdded = nil
        end
        return
    end
    local group = EnsureMasqueGroup()
    if not (group and group.AddButton) then return end
    if button._msufA3MasqueAdded then return end
    group:AddButton(button, {
        Icon = button.Icon,
        Cooldown = button.Cooldown,
        Count = button.Count,
    })
    button._msufA3MasqueAdded = true
end

local function ReskinLaneButtons(lane)
    local created = lane and lane.createdButtons or 0
    for i = 1, created do
        local button = lane[i]
        if button then ApplyMasque(button, lane) end
    end
end

do
    local GF = MSUF and (MSUF.GF or {})
    if GF then
        MSUF.GF = GF
        GF.Masque = GF.Masque or {}
        function GF.Masque.ReskinAllIcons()
            local frames = GF.frameList
            if type(frames) ~= "table" then return false end
            for i = 1, #frames do
                local auras = frames[i] and frames[i].Auras
                if auras then
                    ReskinLaneButtons(auras.Buffs)
                    ReskinLaneButtons(auras.Debuffs)
                    ReskinLaneButtons(auras.Externals)
                end
            end
            return true
        end
    end
end

local function ApplyButtonStaticConfig(button, element)
    local width = element._msufA3ButtonWidth or element.width or element.size or 16
    local height = element._msufA3ButtonHeight or element.height or element.size or 16
    if button._msufA3Width ~= width or button._msufA3Height ~= height then
        button:SetSize(width, height)
        button._msufA3Width, button._msufA3Height = width, height
    end

    local disableMouse = element.disableMouse == true
    if button._msufA3MouseDisabled ~= disableMouse then
        button:EnableMouse(not disableMouse)
        button._msufA3MouseDisabled = disableMouse
    end
    if button.Count and element.stackSize then
        ApplyFontStringStyle(button.Count, element.stackSize, element.stackAnchor or "BOTTOMRIGHT")
    end
    ApplyMasque(button, element)
end

local function ApplyLaneButtonStaticConfig(element)
    local created = element.createdButtons or 0
    for i = 1, created do
        local button = element[i]
        if button then ApplyButtonStaticConfig(button, element) end
    end
end

local function AcquireButton(element, position)
    local button = element[position]
    if not button then
        button = (element.CreateButton or CreateButton)(element, position)
        table_insert(element, button)
        element.createdButtons = (element.createdButtons or 0) + 1
        ApplyButtonStaticConfig(button, element)
    end
    return button
end

local function SetCountShown(button, shown)
    shown = shown and true or false
    if button._msufA3CountShown == shown then return end
    button._msufA3CountShown = shown
    if shown then
        button.Count:Show()
    else
        button.Count:Hide()
    end
end

local function ClearCount(button)
    button.Count:SetText("")
    SetCountShown(button, false)
end

local function ApplyCount(button, element, unit, auraInstanceID)
    if element.showStacks == false then
        ClearCount(button)
        return
    end

    -- 12.0 returns the display string from C_UnitAuras. It can be secret for
    -- target-derived units, so do not compare/cache it in Lua.
    button.Count:SetText(GetStackCount(unit, auraInstanceID, element.minCount or 2, element.maxCount or 999))
    SetCountShown(button, true)
end

local function ApplyIcon(button, icon)
    button.Icon:SetTexture(icon)
end

local function ApplyOverlayColor(button, color)
    local overlay = button.Overlay
    if not overlay then return end

    if color and color.GetRGBA then
        overlay:SetVertexColor(color:GetRGBA())
    else
        overlay:SetVertexColor(1, 1, 1, 1)
    end
end


local function UpdateAura(element, unit, data, position)
    if not data or data.auraInstanceID == nil then return end
    local button = AcquireButton(element, position)
    local auraInstanceID = data.auraInstanceID
    local sameAura = button.auraInstanceID == auraInstanceID

    button.auraInstanceID = auraInstanceID
    button.isHarmfulAura = data.isHarmfulAura
    button._msufA3Unit = unit
    button._msufA3Aura = data

    if button.Cooldown then
        if element.disableCooldown then
            local CT = A3.CooldownText
            if CT and CT.UnregisterButton then CT.UnregisterButton(button) end
            button.Cooldown:Hide()
        else
            local duration = GetDuration(unit, auraInstanceID)
            if duration and button.Cooldown.SetCooldownFromDurationObject then
                if button.Cooldown.SetDrawSwipe then button.Cooldown:SetDrawSwipe(element.showCooldownSwipe == true) end
                if button.Cooldown.SetHideCountdownNumbers then button.Cooldown:SetHideCountdownNumbers(element.showCooldownText ~= true) end
                if button.Cooldown.SetReverse then button.Cooldown:SetReverse(element.cooldownDarkensOnLoss == true) end
                button.Cooldown:SetCooldownFromDurationObject(duration)
                button.Cooldown:Show()
                local CT = A3.CooldownText
                if CT and element.showCooldownText == true then
                    button._msufA3CdTextSize = element.cooldownSize
                    button._msufA3CdTextAnchor = element.cooldownAnchor
                    if CT.ApplyButtonStyle then CT.ApplyButtonStyle(button, element.cooldownSize, element.cooldownAnchor) end
                    if CT.RegisterButton then CT.RegisterButton(button, duration, element._msufA3CooldownScope or "unit") end
                elseif CT and CT.UnregisterButton then
                    CT.UnregisterButton(button)
                end
            else
                local CT = A3.CooldownText
                if CT and CT.UnregisterButton then CT.UnregisterButton(button) end
                button.Cooldown:Hide()
            end
        end
    end

    if not sameAura then
        if button.Overlay then
            local showOverlay = element.showType or (data.isHarmfulAura and element.showDebuffType) or (not data.isHarmfulAura and element.showBuffType)
            if showOverlay then
                local color = GetDispelColor(unit, auraInstanceID, element.dispelColorCurve)
                if color == nil and element.dispelColorCurve and element.dispelColorCurve.Evaluate then
                    color = element.dispelColorCurve:Evaluate(0)
                end
                ApplyOverlayColor(button, color)
                if button._msufA3OverlayShown ~= true then
                    button.Overlay:Show()
                    button._msufA3OverlayShown = true
                end
            elseif button._msufA3OverlayShown ~= false then
                button.Overlay:Hide()
                button._msufA3OverlayShown = false
            end
        end

        if button.Icon then
            ApplyIcon(button, data.icon)
        end
    end

    if button.Count then
        ApplyCount(button, element, unit, auraInstanceID)
    end

    if not button:IsShown() then
        button:Show()
    end

    if element.PostUpdateButton then
        element:PostUpdateButton(button, unit, data, position)
    end
end

local function FilterAura(element, unit, data)
    if not data then return false end
    local blacklistHash = element._msufA3BlacklistHash
    if blacklistHash then
        local spellID = SafeAuraSpellID(data)
        if SafeHashHas(blacklistHash, spellID) then return false end
    end
    if element.onlyShowPlayer and not data.isPlayerAura then return false end
    return true
end

local function SortAuras(a, b)
    if a.isPlayerAura ~= b.isPlayerAura then
        return a.isPlayerAura
    end
    return (a.auraInstanceID or 0) < (b.auraInstanceID or 0)
end

local function SortAurasNoPrefer(a, b)
    return (a.auraInstanceID or 0) < (b.auraInstanceID or 0)
end

local function AuraDurationSortValue(data)
    return SafeNumber(data and data.expirationTime)
        or SafeNumber(data and data.duration)
        or math.huge
end

local function SortAurasByDuration(a, b)
    local av, bv = AuraDurationSortValue(a), AuraDurationSortValue(b)
    if av ~= bv then return av < bv end
    if a.isPlayerAura ~= b.isPlayerAura then return a.isPlayerAura end
    return (a.auraInstanceID or 0) < (b.auraInstanceID or 0)
end

local function SortAurasByDurationNoPrefer(a, b)
    local av, bv = AuraDurationSortValue(a), AuraDurationSortValue(b)
    if av ~= bv then return av < bv end
    return (a.auraInstanceID or 0) < (b.auraInstanceID or 0)
end

local function InsertDefaultTopAura(sorted, data, cap, count)
    if count < cap then
        count = count + 1
        local i = count
        local dataPlayer = data.isPlayerAura
        local dataID = data.auraInstanceID or 0
        while i > 1 do
            local prev = sorted[i - 1]
            if dataPlayer ~= prev.isPlayerAura then
                if dataPlayer ~= true then
                    break
                end
            elseif dataID >= (prev.auraInstanceID or 0) then
                break
            end
            sorted[i] = prev
            i = i - 1
        end
        sorted[i] = data
        return count
    end

    local tail = sorted[cap]
    local dataPlayer = data.isPlayerAura
    local dataID = data.auraInstanceID or 0
    if dataPlayer ~= tail.isPlayerAura then
        if dataPlayer ~= true then
            return count
        end
    elseif dataID >= (tail.auraInstanceID or 0) then
        return count
    end

    local i = cap
    while i > 1 do
        local prev = sorted[i - 1]
        if dataPlayer ~= prev.isPlayerAura then
            if dataPlayer ~= true then
                break
            end
        elseif dataID >= (prev.auraInstanceID or 0) then
            break
        end
        sorted[i] = prev
        i = i - 1
    end
    sorted[i] = data
    return count
end

local function ProcessData(element, unit, data, filter, playerFilter, playerFiltered)
    if not data or data.auraInstanceID == nil then return nil end
    if playerFiltered == true then
        data.isPlayerAura = true
    else
        data.isPlayerAura = AuraPassesFilter(unit, data.auraInstanceID, playerFilter)
    end
    data.isHarmfulAura = element._msufA3IsHarmfulLane == true
    local postProcess = element._msufA3PostProcessAuraData
    if postProcess then
        data = postProcess(element, unit, data, filter)
    end
    return data
end

local function EnsureState(element)
    element.all = element.all or {}
    element.active = element.active or {}
    element.sorted = element.sorted or {}
end

local RemoveAura

local function TrackAura(element, unit, data, filter, all, active, playerFilter, playerFiltered)
    local auraInstanceID = data and data.auraInstanceID
    data = ProcessData(element, unit, data, filter, playerFilter, playerFiltered)
    if not data then
        return auraInstanceID ~= nil and RemoveAura(auraInstanceID, all, active) or false
    end

    auraInstanceID = data.auraInstanceID
    local wasActive = active[auraInstanceID] == true
    all[auraInstanceID] = data

    if (element._msufA3FilterAura or FilterAura)(element, unit, data, filter) then
        active[auraInstanceID] = true
        return true
    end

    active[auraInstanceID] = nil
    return wasActive
end

RemoveAura = function(auraInstanceID, all, active)
    if auraInstanceID == nil then return false end
    if not all[auraInstanceID] and active[auraInstanceID] ~= true then return false end
    local wasActive = active[auraInstanceID] == true
    all[auraInstanceID] = nil
    active[auraInstanceID] = nil
    return wasActive
end

local function UpdateBorderAuraState(lane)
    if not lane or lane._msufA3LaneKind ~= "debuff" then return end

    local owner = lane.__owner
    local border = owner and owner.MSUFSpec and owner.MSUFSpec.border
    local enabled = border and border.enabled == true and border.dispel == true
    lane._msufBorderAuraEnabled = enabled and true or false
    lane._msufBorderAuraStateKnown = true

    if not enabled then
        lane._msufBorderAuraState = nil
        return
    end
    if CoreDispelOwnsBorder(owner) then
        lane._msufBorderAuraStateKnown = false
        lane._msufBorderAuraState = nil
        return
    end

    local all = lane.all
    local active = lane.active
    if type(all) ~= "table" or type(active) ~= "table" then
        lane._msufBorderAuraState = nil
        return
    end

    local dispelFilter = lane._msufA3DispelFilter or "HARMFUL|RAID"
    local unit = lane.unit
    for auraInstanceID in next, active do
        if AuraPassesFilter(unit, auraInstanceID, dispelFilter) then
            lane._msufBorderAuraState = "dispel"
            return
        end
    end
    lane._msufBorderAuraState = nil
end

local function ScanFull(element, unit, filter, all, active, owner, playerFilter, playerFiltered)
    wipe(all)
    wipe(active)

    local auraList = GetUnitAuraList(unit, filter)
    if auraList then
        for i = 1, #auraList do
            TrackAura(element, unit, auraList[i], filter, all, active, playerFilter, playerFiltered)
        end
        return
    end

    local found = false
    local slots, slotCount = QuerySlots(unit, filter, owner)
    if slots then
        found = true
        for i = 2, slotCount do
            TrackAura(element, unit, GetAuraBySlot(unit, slots[i]), filter, all, active, playerFilter, playerFiltered)
        end
    end

    if found then return end
    for i = 1, 80 do
        local data = GetAuraByIndex(unit, i, filter)
        if not data then break end
        TrackAura(element, unit, data, filter, all, active, playerFilter, playerFiltered)
    end
    return nil
end

local function LaneRuntimeFilter(lane, unit)
    local filter = type(lane.filter) == "function" and lane:filter(unit) or lane.filter
    if type(filter) ~= "string" then
        filter = lane._msufA3IsHarmfulLane and "HARMFUL" or "HELPFUL"
    end

    local playerFilter = lane._msufA3PlayerFilter
    local playerFiltered = lane._msufA3PlayerFiltered
    if lane._msufA3PlayerFilterKnown == true and filter == lane._msufA3FilterString then
        return filter, playerFilter, playerFiltered
    end

    playerFiltered = FilterHasToken(filter, "PLAYER")
    if playerFiltered then
        playerFilter = filter
    elseif lane._msufA3PreferPlayer ~= false then
        playerFilter = filter .. "|PLAYER"
    else
        playerFilter = nil
    end
    if type(lane.filter) ~= "function" then
        lane._msufA3FilterString = filter
        lane._msufA3PlayerFiltered = playerFiltered
        lane._msufA3PlayerFilter = playerFilter
        lane._msufA3PlayerFilterKnown = true
    end
    return filter, playerFilter, playerFiltered
end

local function RebuildDefaultTopSorted(all, active, sorted, cap)
    local count = 0
    for auraInstanceID in next, active do
        local data = all[auraInstanceID]
        if data then
            count = InsertDefaultTopAura(sorted, data, cap, count)
        else
            active[auraInstanceID] = nil
        end
    end
    return count
end

local function RebuildSorted(element, all, active, sorted, sorter, visibleCap)
    wipe(sorted)
    local resolvedSorter = sorter or element.SortAuras or SortAuras
    if resolvedSorter == SortAuras and visibleCap and visibleCap > 0 and visibleCap <= 12 then
        return RebuildDefaultTopSorted(all, active, sorted, visibleCap)
    end

    local n = 0
    for auraInstanceID in next, active do
        local data = all[auraInstanceID]
        if data then
            n = n + 1
            sorted[n] = data
        else
            active[auraInstanceID] = nil
        end
    end
    if sorted[2] ~= nil then
        table_sort(sorted, resolvedSorter)
    end
    return n
end

local function UpdateGapButton(element, unit, position)
    local button = AcquireButton(element, position)
    ResetButton(button)
    button:Show()
    if element.PostUpdateGapButton then
        element:PostUpdateGapButton(unit, button, position)
    end
end

local function HideUnused(element, fromIndex)
    local created = element.createdButtons or 0
    for i = fromIndex, created do
        local button = element[i]
        if button then
            ResetButton(button)
            button:Hide()
        end
    end
    return nil
end

local function HideElement(element, unit)
    if element.Buffs then HideElement(element.Buffs, unit) end
    if element.Debuffs then HideElement(element.Debuffs, unit) end
    if element.Externals then HideElement(element.Externals, unit) end
    HideUnused(element, 1)
    element.visibleButtons = 0
    element:Hide()
    if element.PostUpdate then element:PostUpdate(unit) end
end

local LANE_DEFS = {
    buff = {
        key = "Buffs", storeKey = "_msufA3BuffLane", harmful = false,
        showKey = "showBuffs", maxKey = "maxBuffs", sizeKey = "buffIconSize",
        spacingKey = "buffSpacing", perRowKey = "buffPerRow", growthXKey = "buffGrowthX",
        growthYKey = "buffGrowthY", anchorKey = "buffAnchor", xKey = "buffOffsetX",
        yKey = "buffOffsetY", layerKey = "buffLayer", alphaKey = "buffAlpha",
        filterKey = "buffFilter", blacklistKey = "buffBlacklistHash", scan = "BUFFS_",
        defaultAnchor = "BOTTOMRIGHT", defaultLayer = 5,
        showSwipeKey = "buffShowCooldownSwipe", showCooldownKey = "buffShowCooldown",
        showStacksKey = "buffShowStacks", cooldownSizeKey = "buffCooldownSize",
        cooldownAnchorKey = "buffCooldownAnchor", stackSizeKey = "buffStackSize",
    },
    debuff = {
        key = "Debuffs", storeKey = "_msufA3DebuffLane", harmful = true,
        showKey = "showDebuffs", maxKey = "maxDebuffs", sizeKey = "debuffIconSize",
        spacingKey = "debuffSpacing", perRowKey = "debuffPerRow", growthXKey = "debuffGrowthX",
        growthYKey = "debuffGrowthY", anchorKey = "debuffAnchor", xKey = "debuffOffsetX",
        yKey = "debuffOffsetY", layerKey = "debuffLayer", alphaKey = "debuffAlpha",
        filterKey = "debuffFilter", blacklistKey = "debuffBlacklistHash", scan = "DEBUFFS_",
        defaultAnchor = "TOPLEFT", defaultLayer = 6,
        showSwipeKey = "debuffShowCooldownSwipe", showCooldownKey = "debuffShowCooldown",
        showStacksKey = "debuffShowStacks", cooldownSizeKey = "debuffCooldownSize",
        cooldownAnchorKey = "debuffCooldownAnchor", stackSizeKey = "debuffStackSize",
    },
    externals = {
        key = "Externals", storeKey = "_msufA3ExternalLane", harmful = false,
        showKey = "showExternals", maxKey = "maxExternals", sizeKey = "externalIconSize",
        spacingKey = "externalSpacing", perRowKey = "externalPerRow", growthXKey = "externalGrowthX",
        growthYKey = "externalGrowthY", anchorKey = "externalAnchor", xKey = "externalOffsetX",
        yKey = "externalOffsetY", layerKey = "externalLayer", alphaKey = "externalAlpha",
        filterKey = "externalFilter", blacklistKey = "externalBlacklistHash", scan = "EXTERNALS_",
        defaultAnchor = "CENTER", defaultLayer = 7,
        showSwipeKey = "externalShowCooldownSwipe", showCooldownKey = "externalShowCooldown",
        showStacksKey = "externalShowStacks", cooldownSizeKey = "externalCooldownSize",
        cooldownAnchorKey = "externalCooldownAnchor", stackSizeKey = "externalStackSize",
    },
}

local function LaneDef(kind)
    return LANE_DEFS[kind] or LANE_DEFS.buff
end

local function LaneGrowthValues(cfg, kind)
    local def = LaneDef(kind)
    local growth = cfg[def.growthXKey] or cfg.growth
    local wrap = cfg[def.growthYKey] or cfg.rowWrap
    if not GROWTH_OK[growth] then growth = cfg.growth or "RIGHT" end
    if not WRAP_OK[wrap] then wrap = cfg.rowWrap or "DOWN" end
    return growth, wrap
end

local function ApplyGrowth(element, cfg, kind)
    local growth, wrap = LaneGrowthValues(cfg, kind)
    element.growthX = (growth == "LEFT") and "LEFT" or "RIGHT"
    element.growthY = (wrap == "UP") and "UP" or "DOWN"
    if growth == "UP" or growth == "DOWN" then
        element.growthX = "RIGHT"
        element.growthY = growth
    end
end

local function AuraLaneGrowth(cfg, kind)
    local growth, wrap = LaneGrowthValues(cfg, kind)
    local growthX = (growth == "LEFT") and -1 or 1
    local growthY = (wrap == "UP") and 1 or -1
    if growth == "UP" then
        growthX, growthY = 1, 1
    elseif growth == "DOWN" then
        growthX, growthY = 1, -1
    end
    return growthX, growthY
end

local AURA_ANCHORS = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true,
    LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

local function AuraLaneAnchor(cfg, kind)
    if not (cfg and cfg.group == true) then
        return "BOTTOMLEFT", "TOPLEFT", "BOTTOMLEFT"
    end
    local def = LaneDef(kind)
    local anchor = cfg[def.anchorKey]
    if AURA_ANCHORS[anchor] then
        return anchor, anchor, anchor
    end
    anchor = def.defaultAnchor
    return anchor, anchor, anchor
end

local function BuildAuraLaneMetrics(cfg, kind)
    if type(cfg) ~= "table" then return nil end
    kind = (kind == "Buffs" and "buff") or (kind == "Debuffs" and "debuff") or (kind == "Externals" and "externals") or kind
    local def = LaneDef(kind)
    local num = cfg[def.showKey] and cfg[def.maxKey] or 0
    num = ClampNumber(num, 0, 0, 80)
    local size = cfg[def.sizeKey]
    size = ClampNumber(size, cfg.iconSize or 26, 1, 128)
    local spacing = ClampNumber(cfg[def.spacingKey], cfg.spacing or 2, 0, 64)
    local perRow = ClampNumber(cfg[def.perRowKey], cfg.perRow or 12, 1, 40)
    local rows = math_ceil(math_max(num, 1) / perRow)
    local width = math_max(1, perRow * size + (perRow - 1) * spacing)
    local height = math_max(1, rows * size + (rows - 1) * spacing)
    local x = cfg[def.xKey]
    local y = cfg[def.yKey]
    local growthX, growthY = AuraLaneGrowth(cfg, kind)
    local step = size + spacing
    local point, relativePoint, initialAnchor = AuraLaneAnchor(cfg, kind)
    local shown = num
    local shownCols = math_min(math_max(shown, 1), perRow)
    local shownRows = math_ceil(math_max(shown, 1) / perRow)
    local iconMinX = growthX < 0 and -((shownCols - 1) * step) or 0
    local iconMaxX = growthX < 0 and size or ((shownCols - 1) * step + size)
    local iconMinY = growthY < 0 and -((shownRows - 1) * step) or 0
    local iconMaxY = growthY < 0 and size or ((shownRows - 1) * step + size)
    return {
        kind = def == LANE_DEFS.buff and "buff" or (def == LANE_DEFS.debuff and "debuff" or "externals"),
        enabled = num > 0,
        num = num,
        size = size,
        spacing = spacing,
        step = step,
        perRow = perRow,
        rows = rows,
        width = width,
        height = height,
        x = ClampNumber(x, 0, -4096, 4096),
        y = ClampNumber(y, 0, -4096, 4096),
        point = point,
        relativePoint = relativePoint,
        initialAnchor = initialAnchor,
        growthX = growthX,
        growthY = growthY,
        iconMinX = iconMinX,
        iconMaxX = iconMaxX,
        iconMinY = iconMinY,
        iconMaxY = iconMaxY,
    }
end

local function CreateLaneElement(parent, kind)
    local def = LaneDef(kind)
    local key = def.key
    local storeKey = def.storeKey
    local lane = parent[storeKey] or parent[key]
    if lane and lane._msufA3RuntimeLane == true then return lane end

    lane = CreateFrame("Frame", nil, parent)
    lane._msufA3RuntimeLane = true
    lane._msufA3LaneKind = kind
    lane.__owner = parent.__owner
    lane.createdButtons = 0
    lane.anchoredButtons = 0
    lane.visibleButtons = 0
    lane.ForceUpdate = function(self)
        local owner = parent.__owner
        parent.needFullUpdate = true
        if parent.Update then
            return parent:Update((owner and owner.unit) or parent.unit)
        end
    end
    lane:SetSize(1, 1)
    lane:SetFrameLevel((parent.GetFrameLevel and parent:GetFrameLevel() or 0) + def.defaultLayer)
    parent[storeKey] = lane
    parent[key] = lane
    return lane
end

local ClearLane

local function ApplyLaneConfig(parent, frame, unit, cfg, kind)
    local lane = CreateLaneElement(parent, kind)
    local def = LaneDef(kind)
    local isBuff = kind == "buff"
    local isDebuff = kind == "debuff"
    local metrics = BuildAuraLaneMetrics(cfg, kind)
    local num = metrics and metrics.num or 0
    local size = metrics and metrics.size or cfg[def.sizeKey]
    local x = metrics and metrics.x or cfg[def.xKey]
    local y = metrics and metrics.y or cfg[def.yKey]
    local perRow = metrics and metrics.perRow or (cfg.perRow > 0 and cfg.perRow or 1)
    local spacing = metrics and metrics.spacing or ClampNumber(cfg[def.spacingKey], cfg.spacing or 2, 0, 64)
    local width = metrics and metrics.width or (perRow * size + (perRow - 1) * spacing)
    local height = metrics and metrics.height or size
    local point = metrics and metrics.point or "BOTTOMLEFT"
    local relativePoint = metrics and metrics.relativePoint or "TOPLEFT"
    local frameW = width > 0 and width or 1
    local frameH = height > 0 and height or 1
    local disableMouse = cfg.clickThrough == true or cfg.showTooltip ~= true
    local showStealableBuffs = isBuff and cfg.showStealableBuffs == true or false
    local showSwipe = cfg[def.showSwipeKey]
    if showSwipe == nil then showSwipe = cfg.showSwipe ~= false end
    local showCooldown = cfg[def.showCooldownKey]
    if showCooldown == nil then showCooldown = true end
    local showStacks = cfg[def.showStacksKey]
    if showStacks == nil then showStacks = cfg.showStacks ~= false end
    local oldGrowthX, oldGrowthY = lane.growthX, lane.growthY
    local oldSize, oldSpacing, oldCols = lane._msufA3ButtonWidth, lane.spacing, lane.maxCols
    local oldMouse = lane.disableMouse
    local oldStackSize, oldStackAnchor = lane.stackSize, lane.stackAnchor
    local oldMasque = lane.masqueEnabled

    lane.__owner = frame
    lane.unit = unit
    lane._msufA3IsHarmfulLane = def.harmful == true
    lane.size = size
    lane._msufA3ButtonWidth = size
    lane._msufA3ButtonHeight = size
    lane.width = nil
    lane.height = nil
    lane.spacing = spacing
    lane.maxCols = perRow
    lane.initialAnchor = point
    lane.num = num
    lane.filter = cfg[def.filterKey]
    lane._msufA3BlacklistHash = cfg[def.blacklistKey] or cfg.blacklistHash
    lane._msufA3ScanOwner = "A3_UF_" .. def.scan .. unit
    lane._msufA3FilterString = nil
    lane._msufA3PlayerFilter = nil
    lane._msufA3PlayerFiltered = nil
    lane._msufA3PlayerFilterKnown = nil
    lane._msufA3PreferPlayer = cfg.preferPlayer ~= false
    lane._msufA3FilterAura = lane.FilterAura or FilterAura
    lane._msufA3PostProcessAuraData = lane.PostProcessAuraData
    lane._msufA3CooldownScope = cfg.group == true and "group" or "unit"
    lane.disableMouse = disableMouse
    lane.disableCooldown = not (showSwipe == true or showCooldown == true)
    lane.showCooldownSwipe = showSwipe == true
    lane.showCooldownText = showCooldown == true
    lane.cooldownDarkensOnLoss = cfg.cooldownSwipeDarkenOnLoss == true
    lane.cooldownSize = ClampNumber(cfg[def.cooldownSizeKey], isBuff and 8 or 10, 6, 32)
    lane.cooldownAnchor = TEXT_ANCHORS[cfg[def.cooldownAnchorKey]] and cfg[def.cooldownAnchorKey] or "CENTER"
    lane.showStacks = showStacks == true
    lane.stackSize = ClampNumber(cfg[def.stackSizeKey], 10, 6, 32)
    lane.stackAnchor = "BOTTOMRIGHT"
    lane.masqueEnabled = cfg.masqueEnabled == true
    lane.showStealableBuffs = showStealableBuffs
    lane.showType = false
    lane.showBuffType = isBuff
    lane.showDebuffType = isDebuff and cfg.debuffShowDispelBorder ~= false
    lane.SortAuras = cfg.sortByDuration == true
        and (cfg.preferPlayer == false and SortAurasByDurationNoPrefer or SortAurasByDuration)
        or (cfg.preferPlayer == false and SortAurasNoPrefer or SortAuras)
    lane.minCount = 2
    lane.maxCount = 999
    lane.reanchorIfVisibleChanged = true
    lane.tooltipAnchor = "ANCHOR_BOTTOMRIGHT"
    lane.dispelColorCurve = EnsureDispelColorCurve()

    ApplyGrowth(lane, cfg, kind)
    if oldSize ~= size or oldSpacing ~= spacing or oldCols ~= perRow or oldGrowthX ~= lane.growthX or oldGrowthY ~= lane.growthY then
        lane.anchoredButtons = 0
    end
    if oldSize ~= size or oldMouse ~= disableMouse or oldStackSize ~= lane.stackSize or oldStackAnchor ~= lane.stackAnchor or oldMasque ~= lane.masqueEnabled then
        ApplyLaneButtonStaticConfig(lane)
    end

    if lane._msufA3Point ~= point or lane._msufA3RelativeTo ~= frame or lane._msufA3RelativePoint ~= relativePoint or lane._msufA3X ~= x or lane._msufA3Y ~= y then
        lane:ClearAllPoints()
        lane:SetPoint(point, frame, relativePoint, x, y)
        lane._msufA3Point, lane._msufA3RelativeTo, lane._msufA3RelativePoint = point, frame, relativePoint
        lane._msufA3X, lane._msufA3Y = x, y
    end
    if lane._msufA3FrameW ~= frameW or lane._msufA3FrameH ~= frameH then
        lane:SetSize(frameW, frameH)
        lane._msufA3FrameW, lane._msufA3FrameH = frameW, frameH
    end
    if lane.SetFrameLevel and frame.GetFrameLevel then
        local layer = ClampNumber(cfg[def.layerKey], def.defaultLayer, 1, 40)
        local level = (frame:GetFrameLevel() or 0) + layer
        if lane._msufA3FrameLevel ~= level then
            lane:SetFrameLevel(level)
            lane._msufA3FrameLevel = level
        end
    end
    local alpha = ClampNumber(cfg[def.alphaKey], 1, 0, 1)
    if lane._msufA3Alpha ~= alpha then
        lane:SetAlpha(alpha)
        lane._msufA3Alpha = alpha
    end
    return lane
end

local function ApplyElementConfig(element, frame, unit, cfg)
    element.unit = unit
    element.numBuffs = cfg.showBuffs and cfg.maxBuffs or 0
    element.numDebuffs = cfg.showDebuffs and cfg.maxDebuffs or 0
    element.numExternals = cfg.showExternals and cfg.maxExternals or 0
    element.numTotal = element.numBuffs + element.numDebuffs + element.numExternals

    if element._msufA3RelativeTo ~= frame then
        element:ClearAllPoints()
        element:SetAllPoints(frame)
        element._msufA3RelativeTo = frame
    end
    local buffLane = ApplyLaneConfig(element, frame, unit, cfg, "buff")
    local debuffLane = ApplyLaneConfig(element, frame, unit, cfg, "debuff")
    local externalLane = ApplyLaneConfig(element, frame, unit, cfg, "externals")
    if cfg.enabled and element.numBuffs > 0 then
        element.Buffs = buffLane
        frame.Buffs = buffLane
    else
        element.Buffs = nil
        frame.Buffs = nil
        ClearLane(buffLane, unit)
    end
    if cfg.enabled and element.numDebuffs > 0 then
        element.Debuffs = debuffLane
        frame.Debuffs = debuffLane
    else
        element.Debuffs = nil
        frame.Debuffs = nil
        ClearLane(debuffLane, unit)
    end
    if cfg.enabled and element.numExternals > 0 then
        element.Externals = externalLane
        frame.Externals = externalLane
    else
        element.Externals = nil
        frame.Externals = nil
        ClearLane(externalLane, unit)
    end
end

local function ConfigureElement(element, frame, unit)
    local gen = A3._runtimeConfigGen or 0
    local cfg = element._msufResolvedConfig
    local source = frame and frame.MSUFSpec and frame.MSUFSpec.auras
    if cfg and element._msufResolvedConfigGen == gen and element._msufResolvedConfigUnit == unit and element._msufResolvedConfigSource == source then
        return cfg
    end

    cfg = ResolveUnitConfig(unit, frame)
    element._msufResolvedConfig = cfg
    element._msufResolvedConfigGen = gen
    element._msufResolvedConfigUnit = unit
    element._msufResolvedConfigSource = source
    element.needFullUpdate = true
    element.anchoredButtons = 0
    ApplyElementConfig(element, frame, unit, cfg)
    return cfg
end

ClearLane = function(lane, unit)
    if lane._msufA3Cleared == true and (lane.visibleButtons or 0) == 0 then
        return
    end
    EnsureState(lane)
    wipe(lane.all)
    wipe(lane.active)
    wipe(lane.sorted)
    lane._msufBorderAuraState = nil
    lane._msufBorderAuraStateKnown = true
    lane._msufA3Cleared = true
    HideElement(lane, unit)
end

local function UpdateLaneState(lane, unit, updateInfo, full)
    EnsureState(lane)
    local num = lane.num or 0
    if num <= 0 then
        ClearLane(lane, unit)
        return false
    end
    lane._msufA3Cleared = nil

    local filter, playerFilter, playerFiltered = LaneRuntimeFilter(lane, unit)

    if full then
        ScanFull(lane, unit, filter, lane.all, lane.active, lane._msufA3ScanOwner, playerFilter, playerFiltered)
        UpdateBorderAuraState(lane)
        return true
    end

    local changed = false
    local addedAuras = updateInfo.addedAuras
    if addedAuras then
        for i = 1, #addedAuras do
            local data = addedAuras[i]
            local auraInstanceID = data and data.auraInstanceID
            if auraInstanceID ~= nil and AuraPassesFilter(unit, auraInstanceID, filter) then
                changed = TrackAura(lane, unit, data, filter, lane.all, lane.active, playerFilter, playerFiltered) or changed
            end
        end
    end

    local updatedIDs = updateInfo.updatedAuraInstanceIDs
    if updatedIDs then
        for i = 1, #updatedIDs do
            local auraInstanceID = updatedIDs[i]
            if auraInstanceID ~= nil and lane.all[auraInstanceID] then
                local data = GetAuraByID(unit, auraInstanceID)
                if data then
                    changed = TrackAura(lane, unit, data, filter, lane.all, lane.active, playerFilter, playerFiltered) or changed
                else
                    changed = RemoveAura(auraInstanceID, lane.all, lane.active) or changed
                end
            end
        end
    end

    local removedIDs = updateInfo.removedAuraInstanceIDs
    if removedIDs then
        for i = 1, #removedIDs do
            local auraInstanceID = removedIDs[i]
            if auraInstanceID ~= nil then
                changed = RemoveAura(auraInstanceID, lane.all, lane.active) or changed
            end
        end
    end

    if changed then
        UpdateBorderAuraState(lane)
    end
    return changed
end

local function RenderLane(lane, unit, changed)
    if not changed then return lane.visibleButtons or 0 end

    local sorter = lane.SortAuras
    if lane._msufA3LaneKind == "buff" then
        sorter = lane.SortBuffs or sorter
    elseif lane._msufA3LaneKind == "debuff" then
        sorter = lane.SortDebuffs or sorter
    elseif lane._msufA3LaneKind == "externals" then
        sorter = lane.SortExternals or sorter
    end
    RebuildSorted(lane, lane.all, lane.active, lane.sorted, sorter, lane.num or 0)

    local numVisible = math_min(lane.num or 0, #lane.sorted)
    for i = 1, numVisible do
        UpdateAura(lane, unit, lane.sorted[i], i)
    end

    local oldCreated = lane.createdButtons or 0
    local visibleChanged = numVisible ~= lane.visibleButtons
    lane.visibleButtons = numVisible
    local hideFrom = numVisible + 1
    if visibleChanged or lane._msufHiddenFrom ~= hideFrom or lane._msufHiddenCreated ~= oldCreated then
        HideUnused(lane, hideFrom)
        lane._msufHiddenFrom = hideFrom
        lane._msufHiddenCreated = lane.createdButtons or oldCreated
    end

    if numVisible > 0 then
        lane:Show()
    else
        lane:Hide()
    end

    if numVisible > 0 and (visibleChanged or lane.createdButtons > (lane.anchoredButtons or 0)) then
        if visibleChanged or lane.reanchorIfVisibleChanged then
            (lane.SetPosition or SetPosition)(lane, 1, numVisible)
            lane.anchoredButtons = lane.createdButtons or 0
        else
            (lane.SetPosition or SetPosition)(lane, (lane.anchoredButtons or 0) + 1, lane.createdButtons or 0)
            lane.anchoredButtons = lane.createdButtons or 0
        end
    end

    if lane.PostUpdate then lane:PostUpdate(unit) end
    return numVisible
end

local function UpdateElement(element, unit, updateInfo)
    local frame = element and element.__owner
    if not frame then return end
    unit = frame.unit or unit
    if not unit then return end

    local cfg = ConfigureElement(element, frame, unit)
    local unitMissing = UnitExists and SafeBoolIsFalse(UnitExists(unit))
    if not cfg.enabled or (unitMissing and not IsEditMode()) or element.numTotal <= 0 then
        if element.Buffs then ClearLane(element.Buffs, unit) end
        if element.Debuffs then ClearLane(element.Debuffs, unit) end
        if element.Externals then ClearLane(element.Externals, unit) end
        return HideElement(element, unit)
    end
    EnsureAuraAPIs()

    local buffs = element.Buffs
    local debuffs = element.Debuffs
    local externals = element.Externals
    local full = element.needFullUpdate or not updateInfo or updateInfo.isFullUpdate or (buffs and not buffs.all) or (debuffs and not debuffs.all) or (externals and not externals.all)
    element.needFullUpdate = false

    if element.PreUpdate then element:PreUpdate(unit, full) end

    local buffsChanged = buffs and UpdateLaneState(buffs, unit, updateInfo, full) or false
    local debuffsChanged = debuffs and UpdateLaneState(debuffs, unit, updateInfo, full) or false
    local externalsChanged = externals and UpdateLaneState(externals, unit, updateInfo, full) or false

    if element.PostUpdateInfo then
        element:PostUpdateInfo(unit, buffsChanged, debuffsChanged, externalsChanged)
    end

    if not (buffsChanged or debuffsChanged or externalsChanged) then return end

    local numBuffs = buffs and RenderLane(buffs, unit, buffsChanged) or 0
    local numDebuffs = debuffs and RenderLane(debuffs, unit, debuffsChanged) or 0
    local numExternals = externals and RenderLane(externals, unit, externalsChanged) or 0
    local visibleButtons = numBuffs + numDebuffs + numExternals
    element.visibleButtons = visibleButtons
    element.visibleBuffs = numBuffs
    element.visibleDebuffs = numDebuffs
    element.visibleExternals = numExternals
    element.visibleAuras = visibleButtons

    if visibleButtons > 0 then
        element:Show()
    elseif IsEditMode() then
        element:Show()
    else
        element:Hide()
    end

    if element.PostUpdate then element:PostUpdate(unit) end
    return nil
end

local function CreateAuraElement(frame)
    local auras = frame.Auras
    if auras and auras._msufA3Runtime == true then return auras end

    auras = CreateFrame("Frame", nil, frame)
    auras._msufA3Runtime = true
    auras.__owner = frame
    auras.createdButtons = 0
    auras.anchoredButtons = 0
    auras.visibleButtons = 0
    auras.Update = UpdateElement
    auras.ForceUpdate = function(self)
        self.needFullUpdate = true
        return self:Update((self.__owner and self.__owner.unit) or self.unit)
    end
    auras:SetSize(1, 1)
    auras:SetFrameLevel((frame.GetFrameLevel and frame:GetFrameLevel() or 0) + 20)
    frame.Auras = auras
    return auras
end

function A3.RuntimeOwnsUnit(unit)
    return A3.useUnitFrameRuntime == true and A3.UnitFrameOwnsUnitAura and A3.UnitFrameOwnsUnitAura(unit) == true
end

function A3.EnableFrame(frame)
    if not frame or not frame.unit then return end
    local auras = CreateAuraElement(frame)
    A3._runtimeFrames[frame.unit] = frame
    auras.unit = frame.unit

    if not frame._msufA3ShowHooked and frame.HookScript then
        frame._msufA3ShowHooked = true
        frame:HookScript("OnShow", function(self)
            if A3.RequestUnit then A3.RequestUnit(self.unit, 0) end
        end)
    end

    auras.needFullUpdate = true
    return auras
end

function A3.DisableFrame(frame)
    if not frame or not frame.unit then return end
    if A3._runtimeFrames[frame.unit] == frame then
        A3._runtimeFrames[frame.unit] = nil
    end
    local auras = frame.Auras
    if auras and auras._msufA3Runtime == true then
        HideElement(auras, frame.unit)
    end
end

function A3.ResolveUnitFrameConfig(unit, frame)
    return ResolveUnitConfig(unit, frame)
end

function A3.BuildAuraLaneMetrics(configOrUnit, kind)
    local cfg = type(configOrUnit) == "table" and configOrUnit or ResolveUnitConfig(configOrUnit)
    return BuildAuraLaneMetrics(cfg, kind)
end

function A3.RenderFrame(frame, updateInfo)
    if not frame or not frame.unit then return end
    local auras = CreateAuraElement(frame)
    return auras:Update(frame.unit, updateInfo)
end

function A3.ForceUpdateFrame(frame)
    if not frame and _G.MSUF_UnitFrames then frame = _G.MSUF_UnitFrames.player end
    if not frame then return end
    local auras = CreateAuraElement(frame)
    auras.needFullUpdate = true
    return auras:Update(frame.unit)
end

function A3.RequestUnit(unit, delay)
    if not unit then return end
    local frame = A3._runtimeFrames[unit] or (A3._unitFrameOwners and A3._unitFrameOwners[unit])
    if not frame then return end
    if delay and delay > 0 and C_Timer and C_Timer.After then
        C_Timer.After(delay, function()
            local current = A3._runtimeFrames[unit] or (A3._unitFrameOwners and A3._unitFrameOwners[unit])
            if current == frame then A3.RenderFrame(frame) end
        end)
    else
        return A3.RenderFrame(frame)
    end
end

local function UpdateDeferredBorder(frame, unit)
    local active = frame and frame._msufActiveElements
    if not (active and active.Borders == true) then return end
    local UF = MSUF and MSUF.UF
    local borders = UF and UF.elements and UF.elements.Borders
    if borders and borders.Update then
        borders.Update(frame, "MSUF_AURAS3_DEFERRED_UNIT_AURA", unit or frame.unit)
    end
end

local function RunDeferredUnitAura(unit)
    local pending = A3._unitAuraDeferred
    local storedFrame = pending and pending[unit]
    if pending then pending[unit] = nil end

    local frame = A3._runtimeFrames[unit] or (A3._unitFrameOwners and A3._unitFrameOwners[unit])
    if not frame and type(storedFrame) == "table" then frame = storedFrame end
    if not frame then return end

    local element = CreateAuraElement(frame)
    element.needFullUpdate = true
    A3.RenderFrame(frame)
    UpdateDeferredBorder(frame, unit)
end

local function DeferUnitAura(unit, frame)
    if not (unit and C_Timer and C_Timer.After) then return false end
    local pending = A3._unitAuraDeferred
    if pending[unit] then
        if frame then pending[unit] = frame end
        return true
    end
    pending[unit] = frame or true
    C_Timer.After(0, function()
        RunDeferredUnitAura(unit)
    end)
    return true
end

function A3.RefreshAll()
    A3._runtimeConfigGen = (A3._runtimeConfigGen or 0) + 1
    for unit, frame in pairs(A3._runtimeFrames) do
        if frame and frame.Auras then
            frame.Auras.needFullUpdate = true
        end
        A3.RequestUnit(unit, 0)
    end
end

A3.RefreshRuntime = A3.RefreshAll

local function RequestKnownUnit(unit)
    local frame = A3._runtimeFrames[unit] or (A3._unitFrameOwners and A3._unitFrameOwners[unit])
    if frame and frame.Auras then frame.Auras.needFullUpdate = true end
    if frame then A3.RequestUnit(unit, 0) end
end

local function RequestBossUnits()
    RequestKnownUnit("boss1")
    RequestKnownUnit("boss2")
    RequestKnownUnit("boss3")
    RequestKnownUnit("boss4")
    RequestKnownUnit("boss5")
end

local function UFDriverOwnsRuntimeRefresh()
    local UF = MSUF and MSUF.UF
    return A3.useUnitFrameRuntime == true and UF and type(UF.UpdateRuntime) == "function"
end

function A3.OnUnitAura(unit, updateInfo, frame)
    if not unit then return end
    if frame and frame.unit then
        if A3._runtimeFrames[frame.unit] ~= frame then
            A3._runtimeFrames[frame.unit] = frame
        end
        unit = frame.unit
    end
    frame = frame or A3._runtimeFrames[unit] or (A3._unitFrameOwners and A3._unitFrameOwners[unit])
    local element = frame and frame.Auras
    if type(updateInfo) == "table" then
        if element then element.needFullUpdate = true end
        if DeferUnitAura(unit, frame) then return end
    end
    if element and element.Update then
        return element:Update(unit, updateInfo)
    end
    return A3.RequestUnit(unit, 0)
end

_G.MSUF_A3_RequestUnit = A3.RequestUnit
_G.MSUF_A3_RefreshAll = A3.RefreshAll

do
    local f = CreateFrame("Frame")
    A3._globalEventFrame = f
    if not UFDriverOwnsRuntimeRefresh() then
        f:RegisterEvent("PLAYER_ENTERING_WORLD")
        f:RegisterEvent("PLAYER_TARGET_CHANGED")
        f:RegisterEvent("PLAYER_FOCUS_CHANGED")
        f:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
        f:RegisterEvent("UNIT_TARGETABLE_CHANGED")
    end
    f:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_TARGET_CHANGED" then
            RequestKnownUnit("target")
        elseif event == "PLAYER_FOCUS_CHANGED" then
            RequestKnownUnit("focus")
        elseif event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
            RequestBossUnits()
        elseif event == "UNIT_TARGETABLE_CHANGED" then
            if BOSS_UNITS[unit] then RequestKnownUnit(unit) end
        else
            if A3.RefreshRuntime then
                A3.RefreshRuntime()
            else
                A3.RefreshAll()
            end
        end
    end)
end
