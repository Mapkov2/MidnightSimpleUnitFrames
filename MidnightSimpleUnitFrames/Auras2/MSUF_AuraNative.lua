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
    return Native.RENDER_CUSTOM
end

function Native.IsBlizzardRenderer(value)
    return Native.NormalizeRenderer(value) == Native.RENDER_BLIZZARD
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
    local legacy = E and E.Legacy or 0
    local buffsTop = E and E.BuffsTopDebuffsBottom or 1
    local buffsRight = E and E.BuffsRightDebuffsLeft or 2

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

    container:SetAttribute("max-buffs", maxBuffs)
    container:SetAttribute("max-debuffs", maxDebuffs)
    container:SetAttribute("max-dispel-debuffs", maxDispels)
    container:SetAttribute("aura-organization-type", Native.ResolveOrganizationType(cfg.organizationType))
    container:SetAttribute("dispel-indicator-option", Native.ResolveDispelOption(cfg.dispelMode))
    container:SetAttribute("group-type", Native.ResolveGroupType(cfg.unit, cfg.groupType))
    container:SetAttribute("icon-size", iconSize)
    container:SetAttribute("big-defensive-size", bigSize)
    container:SetAttribute("border-scale", Clamp(cfg.borderScale, iconSize / 11, 0, 20))
    container:SetAttribute("power-bar-used-height", Clamp(cfg.powerBarUsedHeight, 0, 0, 200))

    BoolAttr(container, "ignore-buffs", maxBuffs <= 0)
    BoolAttr(container, "ignore-debuffs", maxDebuffs <= 0)
    BoolAttr(container, "ignore-dispel-debuffs", maxDispels <= 0)
    BoolAttr(container, "display-only-dispellable-debuffs", cfg.displayOnlyDispellableDebuffs == true)
    BoolAttr(container, "display-larger-role-specific-debuffs", cfg.displayLargerRoleSpecificDebuffs == true)
    BoolAttr(container, "show-big-defensive", cfg.showBigDefensive == true)
    BoolAttr(container, "show-dispel-indicator-overlay", maxDispels > 0 and cfg.showDispelOverlay ~= false)
    BoolAttr(container, "suppress-dispel-border-icons", cfg.suppressDispelBorderIcons ~= false)
    BoolAttr(container, "always-hide-duration", cfg.alwaysHideDuration ~= false)
    BoolAttr(container, "set-aura-size-to-icon-size", cfg.setAuraSizeToIconSize ~= false)
end

function Native.Clear(container)
    if not container then return end
    local id = container._msufNativeAuraAnchorID
    if id then
        local CUA = _G.C_UnitAuras
        local removeFn = CUA and CUA.RemovePrivateAuraAnchor
        if type(removeFn) == "function" then
            pcall(removeFn, id)
        end
    end
    container._msufNativeAuraAnchorID = nil
    container._msufNativeAuraSignature = nil
    container._msufNativeAuraUnit = nil
    container:Hide()
end

function Native.Signature(unit, cfg)
    cfg = cfg or {}
    return table.concat({
        tostring(unit or ""),
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
        tostring(cfg.showBigDefensive == true),
        tostring(cfg.displayOnlyDispellableDebuffs == true),
        tostring(cfg.displayLargerRoleSpecificDebuffs == true),
        tostring(cfg.showDispelOverlay ~= false),
        tostring(cfg.suppressDispelBorderIcons ~= false),
        tostring(cfg.alwaysHideDuration ~= false),
        tostring(cfg.setAuraSizeToIconSize ~= false),
        tostring(cfg.powerBarUsedHeight or 0),
        tostring(cfg.groupType or ""),
    }, ":")
end

function Native.Apply(container, unit, cfg, parent, levelParent)
    if not container or not unit or not Native.Supported() then
        Native.Clear(container)
        return false
    end
    cfg = cfg or {}
    cfg.unit = unit

    local maxBuffs = math_floor(Clamp(cfg.maxBuffs, 0, 0, 80) + 0.5)
    local maxDebuffs = math_floor(Clamp(cfg.maxDebuffs, 0, 0, 80) + 0.5)
    local maxDispels = math_floor(Clamp(cfg.maxDispelDebuffs, 0, 0, 10) + 0.5)
    if maxBuffs <= 0 and maxDebuffs <= 0 and maxDispels <= 0 and cfg.showBigDefensive ~= true then
        Native.Clear(container)
        return false
    end

    parent = parent or container:GetParent()
    if parent and container:GetParent() ~= parent then
        container:SetParent(parent)
    end
    container:ClearAllPoints()
    if parent then
        local anchor = cfg.containerAnchor or cfg.anchor
        local offsetX = Clamp(cfg.containerOffsetX, 0, -10000, 10000)
        local offsetY = Clamp(cfg.containerOffsetY, 0, -10000, 10000)
        if anchor or offsetX ~= 0 or offsetY ~= 0 then
            anchor = VALID_FRAME_ANCHORS[anchor] and anchor or "CENTER"
            local w, h = 1, 1
            if parent.GetSize then
                w, h = parent:GetSize()
            end
            if not w or w < 1 then w = 1 end
            if not h or h < 1 then h = 1 end
            container:SetSize(w or 1, h or 1)
            container:SetPoint(anchor, parent, anchor, offsetX, offsetY)
        else
            container:SetAllPoints(parent)
        end
    end
    container:EnableMouse(false)
    if container.SetMouseClickEnabled then container:SetMouseClickEnabled(false) end
    local strataSource = (levelParent and levelParent.GetFrameStrata and levelParent) or (parent and parent.GetFrameStrata and parent)
    if container.SetFrameStrata and strataSource then
        local strata = strataSource:GetFrameStrata()
        container:SetFrameStrata(STRATA_FIX[strata] or "DIALOG")
    end
    if container.SetFrameLevel and levelParent and levelParent.GetFrameLevel then
        container:SetFrameLevel((levelParent:GetFrameLevel() or 0) + 100 + (cfg.frameLevelOffset or 0))
    end

    unit = Native.ResolveUnitToken(unit)
    cfg.unit = unit
    Native.SetContainerAttributes(container, cfg)

    local sig = Native.Signature(unit, cfg)
    if container._msufNativeAuraAnchorID and container._msufNativeAuraSignature == sig then
        container:SetAttribute("update-settings", true)
        container:Show()
        return true
    end

    Native.Clear(container)
    Native.SetContainerAttributes(container, cfg)

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
                point = "CENTER",
                relativeTo = container,
                relativePoint = "CENTER",
                offsetX = 0,
                offsetY = 0,
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
