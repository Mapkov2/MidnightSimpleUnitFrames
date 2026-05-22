-- Shared Blizzard aura-container helpers for Unit Frames and Group Frames.
local _, ns = ...

local Native = ns.MSUF_AuraNative or {}
ns.MSUF_AuraNative = Native

local type = type
local tostring = tostring
local tonumber = tonumber
local math_floor = math.floor
local pairs = pairs

Native.RENDER_CUSTOM = "CUSTOM"
Native.RENDER_BLIZZARD = "BLIZZARD"
Native.RENDER_MIXED = "MIXED"
Native.DEFAULT_CONTAINER_STRATA = "AUTO"
Native.DEFAULT_CONTAINER_FRAME_LEVEL = 1
Native.DEFAULT_PRIVATE_LAYER_OFFSET = 1

local DEFAULT_TYPES = {
    buffs = true,
    debuffs = true,
    dispels = true,
    externals = true,
    privateAuras = true,
}
Native.DEFAULT_TYPES = DEFAULT_TYPES

local VALID_FRAME_ANCHORS = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true,
    LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

local VALID_CONTAINER_STRATA = {
    AUTO = true,
    BACKGROUND = true,
    LOW = true,
    MEDIUM = true,
    HIGH = true,
    DIALOG = true,
}
Native.VALID_CONTAINER_STRATA = VALID_CONTAINER_STRATA


local DISPEL_OVERLAY_ORIENTATION = _G.EnumUtil and _G.EnumUtil.MakeEnum("VerticalTopToBottom", "VerticalBottomToTop", "HorizontalLeftToRight")

local function SetOverlayAtlas(texture, atlas)
    if not (texture and texture.SetAtlas and atlas) then return end
    if not texture.GetAtlas or texture:GetAtlas() ~= atlas then
        texture:SetAtlas(atlas, false)
    end
end

local function ResolveDispelOverlayOrientation(value)
    if DISPEL_OVERLAY_ORIENTATION then
        if value == DISPEL_OVERLAY_ORIENTATION.VerticalBottomToTop then return "VerticalBottomToTop" end
        if value == DISPEL_OVERLAY_ORIENTATION.HorizontalLeftToRight then return "HorizontalLeftToRight" end
    end
    if type(value) == "string" then
        local token = value:gsub("[%s_]", ""):lower()
        if token == "verticalbottomtotop" then return "VerticalBottomToTop" end
        if token == "horizontallefttoright" then return "HorizontalLeftToRight" end
    end
    return "VerticalTopToBottom"
end

-- Blizzard_PrivateAurasUI may ask every registered private-aura parent for a
-- DispelOverlay when C_UnitAuras.TriggerPrivateAuraShowDispelType is enabled.
-- Custom slot parents created by addons do not get that member automatically,
-- so provide the same lightweight shape Blizzard compact frames expose.
function Native.EnsurePrivateAuraDispelOverlay(parent)
    if not parent then return nil end
    local overlay = parent.DispelOverlay
    if overlay then return overlay end

    overlay = _G.CreateFrame("Frame", nil, parent)
    overlay:EnableMouse(false)
    overlay:SetAllPoints(parent)

    local background = overlay:CreateTexture(nil, "ARTWORK", nil, -6)
    background:SetAllPoints(overlay)
    SetOverlayAtlas(background, "RaidFrame-Dispel-Fill")
    overlay.Background = background

    local gradient = overlay:CreateTexture(nil, "ARTWORK", nil, -5)
    gradient:SetAllPoints(overlay)
    overlay.Gradient = gradient

    local border = overlay:CreateTexture(nil, "ARTWORK", nil, -5)
    border:SetAllPoints(overlay)
    SetOverlayAtlas(border, "RaidFrame-DispelHighlight")
    overlay.Border = border

    function overlay:SetOrientation(orientationOrOwner, orientation, xOffset, yOffset)
        local resolvedOrientation = orientationOrOwner
        local resolvedX = orientation
        local resolvedY = xOffset
        if type(orientationOrOwner) == "table" and orientation ~= nil then
            resolvedOrientation = orientation
            resolvedX = xOffset
            resolvedY = yOffset
        end
        local token = ResolveDispelOverlayOrientation(resolvedOrientation)
        if token == "HorizontalLeftToRight" then
            SetOverlayAtlas(self.Gradient, "!RaidFrame-Dispel-Vertical")
            self.Gradient:SetTexCoord(0, 1, 0, 1)
        else
            SetOverlayAtlas(self.Gradient, "_RaidFrame-Dispel-Highlight-Horizontal")
            if token == "VerticalBottomToTop" then
                self.Gradient:SetTexCoord(0, 1, 1, 0)
            else
                self.Gradient:SetTexCoord(0, 1, 0, 1)
            end
        end
        self.Border:ClearAllPoints()
        self.Border:SetPoint("TOPLEFT")
        self.Border:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", resolvedX or 0, resolvedY or 0)
    end

    overlay:SetOrientation(DISPEL_OVERLAY_ORIENTATION and DISPEL_OVERLAY_ORIENTATION.VerticalTopToBottom or "VerticalTopToBottom", 0, 0)
    overlay:Hide()
    parent.DispelOverlay = overlay
    parent.DispelOverlayAuraOffset = parent.DispelOverlayAuraOffset or 0
    return overlay
end

local function Clamp(v, def, lo, hi)
    v = tonumber(v)
    if v == nil then v = def end
    if lo and v < lo then v = lo end
    if hi and v > hi then v = hi end
    return v
end
Native.Clamp = Clamp

local function IsInCombat()
    return _G.InCombatLockdown and _G.InCombatLockdown()
end

function Native.NormalizeContainerStrata(value)
    if value == nil or value == "" then return Native.DEFAULT_CONTAINER_STRATA end
    value = tostring(value):upper()
    if VALID_CONTAINER_STRATA[value] then return value end
    return Native.DEFAULT_CONTAINER_STRATA
end

local function ResolveSourceStrata(container, parent, levelParent)
    local source = (levelParent and levelParent.GetFrameStrata and levelParent)
        or (parent and parent.GetFrameStrata and parent)
        or (container and container.GetFrameStrata and container)
    local strata = source and source:GetFrameStrata()
    if VALID_CONTAINER_STRATA[strata] and strata ~= "AUTO" then return strata end
    return "LOW"
end

local function ResolveLayerValues(container, cfg, parent, levelParent)
    cfg = cfg or {}
    levelParent = levelParent or parent
    local strata = Native.NormalizeContainerStrata(cfg.containerStrata or cfg.blizzardContainerStrata)
    if strata == "AUTO" then
        strata = ResolveSourceStrata(container, parent, levelParent)
    end
    local offset = math_floor(Clamp(cfg.containerFrameLevel or cfg.blizzardContainerFrameLevel, Native.DEFAULT_CONTAINER_FRAME_LEVEL, 0, 30) + 0.5)
    local baseLevel = 0
    if levelParent and levelParent.GetFrameLevel then
        baseLevel = tonumber(levelParent:GetFrameLevel()) or 0
    elseif parent and parent.GetFrameLevel then
        baseLevel = tonumber(parent:GetFrameLevel()) or 0
    end
    return strata, baseLevel + offset, offset
end

local function EnsureLayerEventFrame()
    if Native._layerEventFrame then return Native._layerEventFrame end
    local frame = _G.CreateFrame("Frame")
    frame:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        Native._layerEventRegistered = nil
        local pending = Native._layerDeferred
        Native._layerDeferred = nil
        if not pending then return end
        for container in pairs(pending) do
            if container and container._msufLayerDeferred then
                local item = container._msufLayerDeferred
                container._msufLayerDeferred = nil
                Native.ApplyBlizzardAuraContainerLayer(container, item.unitKey, item.opts)
                if item.privateHost then
                    Native.EnsurePrivateAuraHost(container, item.unitKey, item.opts)
                end
            end
        end
    end)
    Native._layerEventFrame = frame
    return frame
end

local function QueueLayerApply(container, unitKey, opts, privateHost)
    if not container then return false end
    container._msufLayerDeferred = {
        unitKey = unitKey,
        opts = opts,
        privateHost = privateHost and true or false,
    }
    Native._layerDeferred = Native._layerDeferred or {}
    Native._layerDeferred[container] = true
    local frame = EnsureLayerEventFrame()
    if frame and not Native._layerEventRegistered then
        frame:RegisterEvent("PLAYER_REGEN_ENABLED")
        Native._layerEventRegistered = true
    end
    return false
end

function Native.ApplyBlizzardAuraContainerLayerForConfig(container, unitKey, cfg, parent, levelParent)
    if not container then return false end
    if IsInCombat() then
        return QueueLayerApply(container, unitKey, {
            config = cfg or {},
            parent = parent,
            levelParent = levelParent,
        }, false)
    end

    local wantStrata, wantLevel = ResolveLayerValues(container, cfg, parent, levelParent)
    if container.SetFrameStrata and container._msufAppliedStrata ~= wantStrata then
        container:SetFrameStrata(wantStrata)
        container._msufAppliedStrata = wantStrata
    end
    if container.SetFrameLevel and container._msufAppliedFrameLevel ~= wantLevel then
        container:SetFrameLevel(wantLevel)
        container._msufAppliedFrameLevel = wantLevel
    end
    return true
end

function Native.ApplyBlizzardAuraContainerLayer(container, unitKey, opts)
    opts = opts or {}
    return Native.ApplyBlizzardAuraContainerLayerForConfig(container, unitKey, opts.config or opts, opts.parent, opts.levelParent)
end

function Native.ClearPrivateAuraHost(container)
    local host = container and container._msufPrivateAuraHost
    if host then
        host:Hide()
    end
end

function Native.EnsurePrivateAuraHostForConfig(container, unitKey, cfg)
    if not container then return nil end
    cfg = cfg or {}
    if cfg.privateLayerFix == false or cfg.blizzardPrivateLayerFix == false then
        Native.ClearPrivateAuraHost(container)
        return nil
    end
    if IsInCombat() then
        QueueLayerApply(container, unitKey, { config = cfg }, true)
        return container._msufPrivateAuraHost
    end

    local host = container._msufPrivateAuraHost
    if not host then
        host = _G.CreateFrame("Frame", nil, container)
        host:EnableMouse(false)
        if host.SetMouseClickEnabled then host:SetMouseClickEnabled(false) end
        host:SetAllPoints(container)
        container._msufPrivateAuraHost = host
    elseif host.GetParent and host:GetParent() ~= container and host.SetParent then
        host:SetParent(container)
        host:ClearAllPoints()
        host:SetAllPoints(container)
    end

    local wantStrata = (container.GetFrameStrata and container:GetFrameStrata()) or container._msufAppliedStrata or "LOW"
    local offset = math_floor(Clamp(cfg.privateLayerOffset or cfg.blizzardPrivateLayerOffset, Native.DEFAULT_PRIVATE_LAYER_OFFSET, 0, 10) + 0.5)
    local baseLevel = (container.GetFrameLevel and (tonumber(container:GetFrameLevel()) or 0)) or 0
    local wantLevel = baseLevel + offset
    if host.SetFrameStrata and host._msufAppliedStrata ~= wantStrata then
        host:SetFrameStrata(wantStrata)
        host._msufAppliedStrata = wantStrata
    end
    if host.SetFrameLevel and host._msufAppliedFrameLevel ~= wantLevel then
        host:SetFrameLevel(wantLevel)
        host._msufAppliedFrameLevel = wantLevel
    end
    host:Show()
    return host
end

function Native.EnsurePrivateAuraHost(container, unitKey, opts)
    opts = opts or {}
    return Native.EnsurePrivateAuraHostForConfig(container, unitKey, opts.config or opts)
end

_G.MSUF_ApplyBlizzardAuraContainerLayer = function(container, unitKey, opts)
    return Native.ApplyBlizzardAuraContainerLayer(container, unitKey, opts)
end

_G.MSUF_EnsurePrivateAuraHost = function(container, unitKey, opts)
    return Native.EnsurePrivateAuraHost(container, unitKey, opts)
end

function Native.NormalizeRenderer(value)
    if value == Native.RENDER_BLIZZARD or value == "blizzard" or value == "Blizzard" then
        return Native.RENDER_BLIZZARD
    end
    if value == Native.RENDER_MIXED or value == "mixed" or value == "Mixed"
        or value == "BOTH" or value == "both"
        or value == "CUSTOM_BLIZZARD" or value == "CUSTOM+BLIZZARD"
    then
        return Native.RENDER_BLIZZARD
    end
    return Native.RENDER_CUSTOM
end

function Native.IsBlizzardRenderer(value)
    return Native.NormalizeRenderer(value) == Native.RENDER_BLIZZARD
end

function Native.IsCustomRenderer(value)
    return Native.NormalizeRenderer(value) == Native.RENDER_CUSTOM
end

function Native.IsMixedRenderer(value)
    return false
end

function Native.EnsureTypes(types, includeExternals)
    if type(types) ~= "table" then
        types = {}
    end
    for key, value in pairs(DEFAULT_TYPES) do
        if key ~= "externals" or includeExternals then
            if types[key] == nil then types[key] = value end
        end
    end
    if not includeExternals then
        types.externals = nil
    end
    return types
end

function Native.TypeEnabled(types, key, defaultValue)
    if type(types) ~= "table" then return defaultValue ~= false end
    if types[key] == nil then return defaultValue ~= false end
    return types[key] == true
end

function Native.Supported()
    local CUA = _G.C_UnitAuras
    return CUA
        and type(CUA.AddPrivateAuraAnchor) == "function"
        and type(CUA.RemovePrivateAuraAnchor) == "function"
end

function Native.ResolveOrganizationType(value)
    local E = _G.Enum and _G.Enum.RaidAuraOrganizationType
    local legacy = E and E.Legacy or 1
    local buffsTop = E and E.BuffsTopDebuffsBottom or 2
    local buffsRight = E and E.BuffsRightDebuffsLeft or 3

    if value == "BOTTOM" or value == "BUFFS_TOP_DEBUFFS_BOTTOM" then return buffsTop end
    if value == "LEFT" or value == "RIGHT" or value == "BUFFS_RIGHT_DEBUFFS_LEFT" then return buffsRight end
    return legacy
end

function Native.ResolveDispelOption(value)
    local E = _G.Enum and _G.Enum.RaidDispelDisplayType
    local byMe = E and E.DispellableByMe or 1
    local all = E and E.DisplayAll or 2
    if value == "allDispellable" or value == "ALL" or value == all then return all end
    return byMe
end

function Native.ResolveGroupType(unit, explicitGroupType)
    if explicitGroupType then return explicitGroupType end
    local G = _G.CompactRaidGroupTypeEnum
    if type(unit) == "string" and unit:find("^party") then
        return G and G.Party or 4
    end
    return G and G.Raid or 5
end

function Native.ResolveUnitToken(unit)
    if type(unit) == "string" and unit ~= "player" and _G.UnitIsUnit then
        local ok, isPlayer = pcall(_G.UnitIsUnit, unit, "player")
        if ok and isPlayer == true then return "player" end
    end
    return unit
end

local function BoolAttr(frame, key, value)
    frame:SetAttribute(key, value and true or false)
end

function Native.SetContainerAttributes(container, cfg)
    if not container or type(container.SetAttribute) ~= "function" then return end
    cfg = cfg or {}

    local iconSize = math_floor(Clamp(cfg.iconSize, 20, 1, 96) + 0.5)
    local maxBuffs = math_floor(Clamp(cfg.maxBuffs, 0, 0, 80) + 0.5)
    local maxDebuffs = math_floor(Clamp(cfg.maxDebuffs, 0, 0, 80) + 0.5)
    local maxDispels = math_floor(Clamp(cfg.maxDispelDebuffs, 0, 0, 10) + 0.5)
    local bigSize = math_floor(Clamp(cfg.bigDefensiveSize or cfg.iconSize, iconSize, 1, 128) + 0.5)
    local showBuffs = cfg.showBuffs == true
    local showDebuffs = cfg.showDebuffs == true
    local showDispels = cfg.showDispels == true
    local showBigDefensive = cfg.showBigDefensive == true

    container:SetAttribute("max-buffs", showBuffs and maxBuffs or 0)
    container:SetAttribute("max-debuffs", showDebuffs and maxDebuffs or 0)
    container:SetAttribute("max-dispel-debuffs", showDispels and maxDispels or 0)
    container:SetAttribute("aura-organization-type", Native.ResolveOrganizationType(cfg.organizationType))
    container:SetAttribute("dispel-indicator-option", Native.ResolveDispelOption(cfg.dispelMode))
    container:SetAttribute("group-type", Native.ResolveGroupType(cfg.unit, cfg.groupType))
    container:SetAttribute("icon-size", iconSize)
    container:SetAttribute("big-defensive-size", bigSize)
    container:SetAttribute("border-scale", Clamp(cfg.borderScale, iconSize / 11, 0, 20))
    container:SetAttribute("power-bar-used-height", Clamp(cfg.powerBarUsedHeight, 0, 0, 200))

    BoolAttr(container, "ignore-buffs", not showBuffs)
    BoolAttr(container, "ignore-debuffs", not showDebuffs)
    BoolAttr(container, "ignore-dispel-debuffs", not showDispels)
    BoolAttr(container, "display-only-dispellable-debuffs", cfg.displayOnlyDispellableDebuffs == true)
    BoolAttr(container, "display-larger-role-specific-debuffs", cfg.displayLargerRoleSpecificDebuffs == true)
    BoolAttr(container, "show-big-defensive", showBigDefensive)
    BoolAttr(container, "show-dispel-indicator-overlay", showDispels and cfg.showDispelOverlay ~= false)
    BoolAttr(container, "suppress-dispel-border-icons", cfg.suppressDispelBorderIcons ~= false)
    BoolAttr(container, "always-hide-duration", cfg.alwaysHideDuration ~= false)
    BoolAttr(container, "set-aura-size-to-icon-size", cfg.setAuraSizeToIconSize ~= false)
end

function Native.Clear(container)
    if not container then return true end
    local id = container._msufNativeAuraAnchorID
    if id then
        local CUA = _G.C_UnitAuras
        local removeFn = CUA and CUA.RemovePrivateAuraAnchor
        if type(removeFn) == "function" then
            local ok, err = pcall(removeFn, id)
            if not ok then
                container._msufNativeAuraLastError = err
                return false
            end
        else
            container._msufNativeAuraLastError = "RemovePrivateAuraAnchor unavailable"
            return false
        end
    end
    container._msufNativeAuraAnchorID = nil
    container._msufNativeAuraSignature = nil
    container._msufNativeAuraUnit = nil
    container._msufNativeAuraRenderParent = nil
    Native.ClearPrivateAuraHost(container)
    container:Hide()
    return true
end

function Native.Signature(unit, cfg)
    cfg = cfg or {}
    local maxBuffs = tonumber(cfg.maxBuffs) or 0
    local maxDebuffs = tonumber(cfg.maxDebuffs) or 0
    local maxDispels = tonumber(cfg.maxDispelDebuffs) or 0
    local showBuffs = cfg.showBuffs == true
    local showDebuffs = cfg.showDebuffs == true
    local showDispels = cfg.showDispels == true
    local showBigDefensive = cfg.showBigDefensive == true
    return table.concat({
        tostring(unit or ""),
        tostring(showBuffs),
        tostring(showDebuffs),
        tostring(showDispels),
        tostring(showBigDefensive),
        tostring(cfg.privateAuras ~= false),
        tostring(cfg.maxBuffs or 0),
        tostring(cfg.maxDebuffs or 0),
        tostring(cfg.maxDispelDebuffs or 0),
        tostring(cfg.iconSize or 0),
        tostring(cfg.bigDefensiveSize or 0),
        tostring(cfg.borderScale or 0),
        tostring(cfg.organizationType or "default"),
        tostring(cfg.dispelMode or "dispellableByMe"),
        tostring(cfg.showCountdownFrame ~= false),
        tostring(cfg.showCountdownNumbers == true),
        tostring(cfg.displayOnlyDispellableDebuffs == true),
        tostring(cfg.displayLargerRoleSpecificDebuffs == true),
        tostring(cfg.showDispelOverlay ~= false),
        tostring(cfg.suppressDispelBorderIcons ~= false),
        tostring(cfg.alwaysHideDuration ~= false),
        tostring(cfg.setAuraSizeToIconSize ~= false),
        tostring(cfg.powerBarUsedHeight or 0),
        tostring(cfg.groupType or ""),
        tostring(cfg.containerAnchor or cfg.anchor or ""),
        tostring(cfg.containerOffsetX or 0),
        tostring(cfg.containerOffsetY or 0),
        tostring(cfg.iconAnchor or ""),
        tostring(cfg.iconOffsetX or 0),
        tostring(cfg.iconOffsetY or 0),
        tostring(cfg.privateLayerFix ~= false and cfg.blizzardPrivateLayerFix ~= false),
    }, ":")
end

function Native.ApplyFrameStrata(container, parent, levelParent, cfg)
    return Native.ApplyBlizzardAuraContainerLayerForConfig(container, nil, cfg or {}, parent, levelParent)
end

function Native.Apply(container, unit, cfg, parent, levelParent)
    if not container or not unit or not Native.Supported() then
        if container then Native.Clear(container) end
        return false
    end
    cfg = cfg or {}

    local maxBuffs = math_floor(Clamp(cfg.maxBuffs, 0, 0, 80) + 0.5)
    local maxDebuffs = math_floor(Clamp(cfg.maxDebuffs, 0, 0, 80) + 0.5)
    local maxDispels = math_floor(Clamp(cfg.maxDispelDebuffs, 0, 0, 10) + 0.5)
    local showBuffs = cfg.showBuffs == true
    local showDebuffs = cfg.showDebuffs == true
    local showDispels = cfg.showDispels == true
    if not (showBuffs and maxBuffs > 0)
       and not (showDebuffs and maxDebuffs > 0)
       and not (showDispels and maxDispels > 0)
       and cfg.showBigDefensive ~= true
    then
        if Native.Clear(container) ~= false then
            container._msufNativeAuraLastError = nil
        end
        return false
    end

    -- Fast path: resolve unit + check signature BEFORE any expensive UI operations.
    -- On every UNIT_AURA event this runs; if config hasn't changed we return immediately.
    unit = Native.ResolveUnitToken(unit)
    cfg.unit = unit
    local sig = Native.Signature(unit, cfg)
    parent = parent or container:GetParent()
    if not cfg.forceApply and container._msufNativeAuraAnchorID and container._msufNativeAuraSignature == sig then
        Native.ApplyFrameStrata(container, parent, levelParent, cfg)
        local renderParent = container
        if cfg.privateAuras ~= false and cfg.privateLayerFix ~= false and cfg.blizzardPrivateLayerFix ~= false then
            renderParent = Native.EnsurePrivateAuraHostForConfig(container, unit, cfg) or container
        else
            Native.ClearPrivateAuraHost(container)
        end
        container:SetAttribute("update-settings", true)
        if renderParent ~= container and renderParent.SetAttribute then
            renderParent:SetAttribute("update-settings", true)
        end
        container:Show()
        return true
    end

    -- Slow path: config changed; do full reposition + re-registration.
    if parent and container:GetParent() ~= parent then
        container:SetParent(parent)
    end
    local resolvedIconAnchor = "CENTER"
    local resolvedIconOffsetX = Clamp(cfg.iconOffsetX, 0, -10000, 10000)
    local resolvedIconOffsetY = Clamp(cfg.iconOffsetY, 0, -10000, 10000)
    container:ClearAllPoints()
    if parent then
        local anchor = cfg.containerAnchor or cfg.anchor
        local offsetX = Clamp(cfg.containerOffsetX, 0, -10000, 10000)
        local offsetY = Clamp(cfg.containerOffsetY, 0, -10000, 10000)
        if anchor or offsetX ~= 0 or offsetY ~= 0 then
            anchor = VALID_FRAME_ANCHORS[anchor] and anchor or "CENTER"
            resolvedIconAnchor = anchor
            container:SetSize(1, 1)
            container:SetPoint(anchor, parent, anchor, offsetX, offsetY)
        else
            container:SetAllPoints(parent)
        end
    end
    if cfg.iconAnchor and VALID_FRAME_ANCHORS[cfg.iconAnchor] then
        resolvedIconAnchor = cfg.iconAnchor
    end
    container:EnableMouse(false)
    if container.SetMouseClickEnabled then container:SetMouseClickEnabled(false) end
    Native.ApplyFrameStrata(container, parent, levelParent, cfg)

    if not Native.Clear(container) then
        return false
    end
    local renderParent = container
    if cfg.privateAuras ~= false and cfg.privateLayerFix ~= false and cfg.blizzardPrivateLayerFix ~= false then
        renderParent = Native.EnsurePrivateAuraHostForConfig(container, unit, cfg) or container
    else
        Native.ClearPrivateAuraHost(container)
    end
    Native.SetContainerAttributes(container, cfg)
    if renderParent ~= container then
        Native.SetContainerAttributes(renderParent, cfg)
    end

    local iconSize = math_floor(Clamp(cfg.iconSize, 20, 1, 96) + 0.5)
    local borderScale = Clamp(cfg.borderScale, iconSize / 11, 0, 20)
    local args = {
        unitToken = unit,
        parent = renderParent,
        isContainer = true,
        auraIndex = 1,
        showCountdownFrame = cfg.showCountdownFrame ~= false,
        showCountdownNumbers = cfg.showCountdownNumbers == true,
        iconInfo = {
            iconWidth = iconSize,
            iconHeight = iconSize,
            borderScale = borderScale,
            iconAnchor = {
                point = resolvedIconAnchor,
                relativeTo = renderParent,
                relativePoint = resolvedIconAnchor,
                offsetX = resolvedIconOffsetX,
                offsetY = resolvedIconOffsetY,
            },
        },
    }

    local addFn = _G.C_UnitAuras and _G.C_UnitAuras.AddPrivateAuraAnchor
    local ok, anchorID = pcall(addFn, args)
    if not ok or not anchorID then
        container._msufNativeAuraLastError = anchorID
        Native.Clear(container)
        return false
    end

    container._msufNativeAuraAnchorID = anchorID
    container._msufNativeAuraSignature = sig
    container._msufNativeAuraUnit = unit
    container._msufNativeAuraRenderParent = renderParent
    container:Show()
    if renderParent ~= container then renderParent:Show() end
    return true
end
