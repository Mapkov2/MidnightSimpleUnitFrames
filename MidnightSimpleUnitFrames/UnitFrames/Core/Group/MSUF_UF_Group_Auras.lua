local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF_NS = MSUF
_G.MSUF = MSUF

local UF = MSUF.UF
local GF = MSUF.GF or {}
MSUF.GF = GF

if not (UF and UF.RegisterElement) then return end

local AuraCache = GF.AuraCache or {}
local SetShown = AuraCache.SetShown or function(region, show) if region then region:SetShown(show) end end
local CreateFrame = CreateFrame
local C_UnitAuras = C_UnitAuras
local UnitExists = UnitExists
local InCombatLockdown = InCombatLockdown
local type = type
local tonumber = tonumber
local math_max = math.max
local wipe = _G.wipe or table.wipe

local GroupAuraLanes = {}

function GroupAuraLanes.IsEnabled(frame, spec)
    if spec and spec.auras and spec.auras.group == true then
        return false
    end
    local cfg = spec and spec.group and spec.group.auras
    return spec and spec.scope == "group" and cfg and cfg.enabled == true and (cfg.maxIcons or 0) > 0
end

function GroupAuraLanes.GetEvents()
    return { "UNIT_AURA" }
end

local function EnsureAuraHolder(frame)
    local holder = frame.MSUFGroupAuraHolder
    if not holder then
        holder = CreateFrame("Frame", nil, frame)
        holder:SetAllPoints(frame)
        holder:EnableMouse(false)
        frame.MSUFGroupAuraHolder = holder
    end
    return holder
end

local function EnsureAuraIcon(frame, index)
    frame.MSUFGroupAuraIcons = frame.MSUFGroupAuraIcons or {}
    local icon = frame.MSUFGroupAuraIcons[index]
    if not icon then
        icon = EnsureAuraHolder(frame):CreateTexture(nil, "OVERLAY")
        frame.MSUFGroupAuraIcons[index] = icon
    end
    return icon
end

local function FillIcons(src, remaining, out)
    if not src then return remaining end
    for i = 1, #src do
        if remaining <= 0 then return 0 end
        out[#out + 1] = src[i]
        remaining = remaining - 1
    end
    return remaining
end

local function UpdateAuraLanes(frame, event, updateInfo)
    local cfg = frame.MSUFSpec and frame.MSUFSpec.group and frame.MSUFSpec.group.auras
    if not cfg then return end
    local snapshot
    if event == "UNIT_AURA" and AuraCache.UpdateSnapshot then
        snapshot = AuraCache.UpdateSnapshot(frame, updateInfo)
    else
        snapshot = AuraCache.GetSnapshot and AuraCache.GetSnapshot(frame)
    end
    local maxIcons = cfg.maxIcons or 4
    local icons = frame._msufGFAuraIconScratch
    if not icons then
        icons = {}
        frame._msufGFAuraIconScratch = icons
    else
        wipe(icons)
    end
    local remaining = maxIcons
    if cfg.showDebuffs ~= false then
        remaining = FillIcons(snapshot and snapshot.debuffIcons, remaining, icons)
    end
    if remaining > 0 and cfg.showBuffs ~= false then
        FillIcons(snapshot and snapshot.buffIcons, remaining, icons)
    end

    local size, spacing = cfg.iconSize or 20, cfg.spacing or 2
    local anchor, x, y = cfg.anchor or "TOPRIGHT", cfg.x or 0, cfg.y or 0
    for i = 1, maxIcons do
        local icon = EnsureAuraIcon(frame, i)
        local texture = icons[i]
        if texture then
            icon:SetTexture(texture)
            icon:SetSize(size, size)
            icon:ClearAllPoints()
            if anchor == "TOPLEFT" or anchor == "LEFT" or anchor == "BOTTOMLEFT" then
                icon:SetPoint(anchor, frame, anchor, x + ((i - 1) * (size + spacing)), y)
            else
                icon:SetPoint(anchor, frame, anchor, x - ((i - 1) * (size + spacing)), y)
            end
            SetShown(icon, true)
        else
            SetShown(icon, false)
        end
    end
end

function GroupAuraLanes.Apply(frame) UpdateAuraLanes(frame) end
function GroupAuraLanes.Update(frame, event, unit, updateInfo) UpdateAuraLanes(frame, event, updateInfo) end
function GroupAuraLanes.Disable(frame)
    if frame and frame.MSUFGroupAuraIcons then
        for i = 1, #frame.MSUFGroupAuraIcons do SetShown(frame.MSUFGroupAuraIcons[i], false) end
    end
end

UF.RegisterElement("GroupAuraLanes", GroupAuraLanes)

local EMPTY_EVENTS = {}

local function GetNativeAuraAPI()
    local native = MSUF and MSUF.MSUF_AuraNative
    if native and native.Supported and native.Supported() == true then
        return native
    end
    return nil
end

local function EnsureNativeAuraContainer(frame, parent)
    if not frame then return nil end
    local container = frame._msufGFNativeAuras
    if not container then
        container = CreateFrame("Frame", nil, parent or frame)
        container:EnableMouse(false)
        if container.SetMouseClickEnabled then container:SetMouseClickEnabled(false) end
        frame._msufGFNativeAuras = container
    elseif parent and container.GetParent and container:GetParent() ~= parent then
        container:SetParent(parent)
    end
    return container
end

local function ClearNativeAuraContainer(frame)
    local container = frame and frame._msufGFNativeAuras
    if not container then return true end
    local native = MSUF and MSUF.MSUF_AuraNative
    if native and native.Clear then
        return native.Clear(container) ~= false
    end
    local remove = C_UnitAuras and C_UnitAuras.RemovePrivateAuraAnchor
    local id = container._msufNativeAuraAnchorID
    if id and type(remove) == "function" then
        remove(id)
    end
    container._msufNativeAuraAnchorID = nil
    container._msufNativeAuraSignature = nil
    container._msufNativeAuraUnit = nil
    container:Hide()
    return true
end

function GF.ClearBlizzardAuraContainer(frame)
    return ClearNativeAuraContainer(frame)
end

local function BlizzardSpec(spec)
    local auras = spec and spec.auras
    local blizzard = auras and auras.blizzard
    if not blizzard then return nil, nil end
    if blizzard.buffs or blizzard.debuffs or blizzard.dispels or blizzard.externals or blizzard.privateAuras then
        return auras, blizzard
    end
    return nil, nil
end

local function NativeAuraConfig(frame, spec)
    local auras, blizzard = BlizzardSpec(spec)
    if not auras then return nil end
    local private = auras.private or {}
    local maxDebuffs = blizzard.debuffs and (tonumber(auras.maxDebuffs) or 0) or 0
    if blizzard.privateAuras == true then
        maxDebuffs = math_max(maxDebuffs, tonumber(private.num) or 0)
    end
    local iconSize = tonumber(blizzard.iconSize) or tonumber(auras.iconSize) or 20
    local power = spec and spec.power
    local groupType = (spec and spec.groupKind == "party") and 4 or 5
    return {
        showBuffs = blizzard.buffs == true,
        showDebuffs = blizzard.debuffs == true or blizzard.privateAuras == true,
        showDispels = blizzard.dispels == true,
        showBigDefensive = blizzard.externals == true,
        privateAuras = blizzard.privateAuras == true,
        maxBuffs = blizzard.buffs == true and (tonumber(auras.maxBuffs) or 0) or 0,
        maxDebuffs = maxDebuffs,
        maxDispelDebuffs = blizzard.dispels == true and 3 or 0,
        iconSize = iconSize,
        bigDefensiveSize = tonumber(auras.externalIconSize) or iconSize,
        showDispelOverlay = blizzard.dispels == true,
        organizationType = blizzard.organizationType or "default",
        dispelMode = "allDispellable",
        showCountdownFrame = true,
        showCountdownNumbers = blizzard.showCooldownText ~= false,
        groupType = groupType,
        displayLargerRoleSpecificDebuffs = true,
        powerBarUsedHeight = (power and power.enabled == true and tonumber(power.height)) or 0,
        containerStrata = blizzard.strata or "AUTO",
        containerFrameLevel = tonumber(blizzard.frameLevelOffset) or 1,
        privateLayerFix = blizzard.privateLayerFix ~= false,
        privateLayerOffset = 1,
    }
end

local function NativeAuraParent(frame)
    return frame and (frame.statusIconLayer or frame.barGroup or frame)
end

local function ApplyNativeAuras(frame, forceApply)
    local native = GetNativeAuraAPI()
    local spec = frame and frame.MSUFSpec
    local cfg = native and NativeAuraConfig(frame, spec)
    if not (frame and native and cfg and frame.unit) then
        return ClearNativeAuraContainer(frame)
    end
    if UnitExists and not UnitExists(frame.unit) then
        return ClearNativeAuraContainer(frame)
    end
    if forceApply == true then
        cfg.forceApply = true
    end
    local parent = NativeAuraParent(frame)
    local container = EnsureNativeAuraContainer(frame, parent)
    if not container then return false end
    local applied = native.Apply(container, frame.unit, cfg, parent, parent)
    if not applied then
        ClearNativeAuraContainer(frame)
    end
    return applied
end

local nativeLayerEventFrame
local function QueueNativeLayeringAfterCombat(kind, forceReapply)
    GF._pendingNativeAuraLayering = GF._pendingNativeAuraLayering or {}
    GF._pendingNativeAuraLayering[kind or "_all"] = forceReapply == true
    if not nativeLayerEventFrame then
        nativeLayerEventFrame = CreateFrame("Frame")
        nativeLayerEventFrame:SetScript("OnEvent", function(self)
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            local pending = GF._pendingNativeAuraLayering
            GF._pendingNativeAuraLayering = nil
            if not pending then return end
            for pendingKind, force in pairs(pending) do
                GF.ApplyBlizzardAuraContainerLayering(pendingKind ~= "_all" and pendingKind or nil, force)
            end
        end)
    end
    nativeLayerEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

function GF.UpdateBlizzardAuraContainer(frame, unit, conf, scale, frameScale, updateInfo)
    if not frame then return nil end
    if unit and frame.unit ~= unit then
        frame.unit = unit
    end
    local forceApply = updateInfo and updateInfo.isFullUpdate == true
    local applied = ApplyNativeAuras(frame, forceApply)
    local _, blizzard = BlizzardSpec(frame.MSUFSpec)
    if not blizzard then return nil end
    return {
        buffs = applied and blizzard.buffs == true,
        debuffs = applied and blizzard.debuffs == true,
        dispels = applied and blizzard.dispels == true,
        externals = applied and blizzard.externals == true,
        privateAuras = applied and blizzard.privateAuras == true,
    }
end

function GF.ApplyBlizzardAuraContainerLayering(kind, forceReapply)
    if InCombatLockdown and InCombatLockdown() then
        QueueNativeLayeringAfterCombat(kind, forceReapply)
        return
    end
    if not GF.ForEachFrame then return end
    GF.ForEachFrame(function(frame, unit, frameKind)
        if kind and frameKind ~= kind then return end
        ApplyNativeAuras(frame, forceReapply == true)
    end, true)
end

local GroupBlizzardAuras = {}

function GroupBlizzardAuras.IsEnabled(frame, spec)
    if not (spec and spec.scope == "group") then return false end
    if not GetNativeAuraAPI() then return false end
    local auras = BlizzardSpec(spec)
    return auras ~= nil
end

function GroupBlizzardAuras.GetEvents()
    return EMPTY_EVENTS
end

function GroupBlizzardAuras.GetUnitlessEvents()
    return EMPTY_EVENTS
end

function GroupBlizzardAuras.Apply(frame)
    return ApplyNativeAuras(frame, false)
end

function GroupBlizzardAuras.Update(frame, event)
    if event == "UNIT_CHANGED" or event == "MSUF_GF_APPLY" or event == "MSUF_GF_SCAN"
        or event == "MSUF_GF_REFRESH_VISUALS" or event == "MSUF_FORCE_UPDATE" then
        return ApplyNativeAuras(frame, false)
    end
end

function GroupBlizzardAuras.Disable(frame)
    return ClearNativeAuraContainer(frame)
end

UF.RegisterElement("GroupBlizzardAuras", GroupBlizzardAuras)

local GroupPrivateAuras = {}

local PRIVATE_UNITS = {
    player = true,
    party1 = true, party2 = true, party3 = true, party4 = true,
}
for i = 1, 40 do PRIVATE_UNITS["raid" .. i] = true end

local function PrivateUnitAllowed(unit)
    return unit and PRIVATE_UNITS[unit] == true
end

local function EnsurePrivateHolder(frame)
    local holder = frame.MSUFGroupPrivateAuras
    if not holder then
        holder = CreateFrame("Frame", nil, frame)
        holder.__owner = frame
        holder.anchors = {}
        frame.MSUFGroupPrivateAuras = holder
    end
    holder.__owner = frame
    return holder
end

local function ClearPrivateAnchors(holder)
    local remove = C_UnitAuras and C_UnitAuras.RemovePrivateAuraAnchor
    if holder and holder.anchors and type(remove) == "function" then
        for i = 1, #holder.anchors do
            remove(holder.anchors[i])
            holder.anchors[i] = nil
        end
    end
    if holder then
        holder._msufUnit = nil
        holder._msufNum = nil
        holder._msufSize = nil
        holder._msufSpacing = nil
        holder._msufAnchor = nil
        holder._msufGrowth = nil
        holder._msufX = nil
        holder._msufY = nil
        holder._msufCountdown = nil
        holder._msufNumbers = nil
        holder:Hide()
    end
end

local function GrowthStep(growth, size, spacing)
    local step = size + spacing
    if growth == "LEFT" then return -step, 0 end
    if growth == "UP" then return 0, step end
    if growth == "DOWN" then return 0, -step end
    return step, 0
end

local function EnsurePrivateAuraAnchor(holder, index)
    local anchor = holder[index]
    if anchor then return anchor end
    anchor = CreateFrame("Frame", nil, holder)
    anchor.Icon = CreateFrame("Frame", nil, anchor)
    anchor.Icon:SetAllPoints(anchor)
    holder[index] = anchor
    return anchor
end

local function PrivateConfigUnchanged(holder, unit, cfg)
    return holder._msufUnit == unit
        and holder._msufNum == (cfg.num or 0)
        and holder._msufSize == (cfg.size or 0)
        and holder._msufSpacing == (cfg.spacing or 0)
        and holder._msufAnchor == (cfg.anchor or "")
        and holder._msufGrowth == (cfg.growth or "")
        and holder._msufX == (cfg.x or 0)
        and holder._msufY == (cfg.y or 0)
        and holder._msufCountdown == (cfg.showCountdown and true or false)
        and holder._msufNumbers == (cfg.showNumbers and true or false)
end

local function StorePrivateConfig(holder, unit, cfg)
    holder._msufUnit = unit
    holder._msufNum = cfg.num or 0
    holder._msufSize = cfg.size or 0
    holder._msufSpacing = cfg.spacing or 0
    holder._msufAnchor = cfg.anchor or ""
    holder._msufGrowth = cfg.growth or ""
    holder._msufX = cfg.x or 0
    holder._msufY = cfg.y or 0
    holder._msufCountdown = cfg.showCountdown and true or false
    holder._msufNumbers = cfg.showNumbers and true or false
end

local function ApplyPrivateAuras(frame)
    local spec = frame and frame.MSUFSpec
    local cfg = spec and spec.auras and spec.auras.private
    local holder = frame and EnsurePrivateHolder(frame)
    local add = C_UnitAuras and C_UnitAuras.AddPrivateAuraAnchor
    if not (holder and cfg and cfg.enabled == true and type(add) == "function" and PrivateUnitAllowed(frame.unit)) then
        return ClearPrivateAnchors(holder)
    end
    if UnitExists and not UnitExists(frame.unit) then
        return ClearPrivateAnchors(holder)
    end

    if PrivateConfigUnchanged(holder, frame.unit, cfg) then
        holder:Show()
        return true
    end

    ClearPrivateAnchors(holder)
    holder:ClearAllPoints()
    holder:SetPoint(cfg.anchor or "TOPRIGHT", frame, cfg.anchor or "TOPRIGHT", cfg.x or 0, cfg.y or 0)
    holder:SetSize(1, 1)
    holder:EnableMouse(false)

    local num = cfg.num or 0
    local size = cfg.size or 20
    local spacing = cfg.spacing or 1
    local dx, dy = GrowthStep(cfg.growth, size, spacing)
    local added = 0
    for i = 1, num do
        local anchor = EnsurePrivateAuraAnchor(holder, i)
        anchor:SetSize(size, size)
        anchor:ClearAllPoints()
        anchor:SetPoint("CENTER", holder, "CENTER", (i - 1) * dx, (i - 1) * dy)
        anchor:Show()
        local anchorID = add({
            unitToken = frame.unit,
            auraIndex = i,
            parent = anchor,
            showCountdownFrame = cfg.showCountdown ~= false,
            showCountdownNumbers = cfg.showNumbers == true,
            iconInfo = {
                iconWidth = size,
                iconHeight = size,
                iconAnchor = {
                    point = "CENTER",
                    relativeTo = anchor.Icon,
                    relativePoint = "CENTER",
                    offsetX = 0,
                    offsetY = 0,
                },
            },
        })
        if anchorID then
            holder.anchors[#holder.anchors + 1] = anchorID
            added = added + 1
        end
    end
    for i = num + 1, #holder do
        if holder[i] then holder[i]:Hide() end
    end
    if added > 0 then
        StorePrivateConfig(holder, frame.unit, cfg)
        holder:Show()
        return true
    end
    ClearPrivateAnchors(holder)
    return false
end

function GroupPrivateAuras.IsEnabled(frame, spec)
    local private = spec and spec.scope == "group" and spec.auras and spec.auras.private
    return private and private.enabled == true and (private.num or 0) > 0 and PrivateUnitAllowed(frame and frame.unit)
end

function GroupPrivateAuras.Apply(frame)
    return ApplyPrivateAuras(frame)
end

function GroupPrivateAuras.Update(frame)
    return ApplyPrivateAuras(frame)
end

function GroupPrivateAuras.Disable(frame)
    return ClearPrivateAnchors(frame and frame.MSUFGroupPrivateAuras)
end

UF.RegisterElement("GroupPrivateAuras", GroupPrivateAuras)
