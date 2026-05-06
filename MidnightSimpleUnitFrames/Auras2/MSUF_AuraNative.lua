-- Shared Blizzard aura-container helpers for Unit Frames and Group Frames.
local _, ns = ...

local Native = ns.MSUF_AuraNative or {}
ns.MSUF_AuraNative = Native

local type = type
local tostring = tostring
local tonumber = tonumber
local math_floor = math.floor

Native.RENDER_CUSTOM = "CUSTOM"
Native.RENDER_BLIZZARD = "BLIZZARD"
Native.RENDER_MIXED = "MIXED"

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

local STRATA_FIX = {
    BACKGROUND = "LOW",
    LOW = "MEDIUM",
    MEDIUM = "HIGH",
    HIGH = "DIALOG",
    DIALOG = "FULLSCREEN",
    FULLSCREEN = "FULLSCREEN_DIALOG",
    FULLSCREEN_DIALOG = "TOOLTIP",
}

local function Clamp(v, def, lo, hi)
    v = tonumber(v)
    if v == nil then v = def end
    if lo and v < lo then v = lo end
    if hi and v > hi then v = hi end
    return v
end
Native.Clamp = Clamp

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
    }, ":")
end

function Native.ApplyFrameStrata(container, parent, levelParent)
    if not container then return end

    local strataSource = (levelParent and levelParent.GetFrameStrata and levelParent) or (parent and parent.GetFrameStrata and parent)
    if container.SetFrameStrata and strataSource then
        local wantStrata = STRATA_FIX[strataSource:GetFrameStrata()] or "DIALOG"
        if not container.GetFrameStrata or container:GetFrameStrata() ~= wantStrata then
            container:SetFrameStrata(wantStrata)
        end
    end
    if levelParent and container.SetFrameLevel and levelParent.GetFrameLevel then
        local wantLevel = (levelParent:GetFrameLevel() or 0) + 100
        if not container.GetFrameLevel or container:GetFrameLevel() ~= wantLevel then
            container:SetFrameLevel(wantLevel)
        end
    end
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
        Native.ApplyFrameStrata(container, parent, levelParent)
        container:SetAttribute("update-settings", true)
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
    Native.ApplyFrameStrata(container, parent, levelParent)

    Native.SetContainerAttributes(container, cfg)
    if not Native.Clear(container) then
        return false
    end

    local iconSize = math_floor(Clamp(cfg.iconSize, 20, 1, 96) + 0.5)
    local borderScale = Clamp(cfg.borderScale, iconSize / 11, 0, 20)
    local args = {
        unitToken = unit,
        parent = container,
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
                relativeTo = container,
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
    container:Show()
    return true
end
