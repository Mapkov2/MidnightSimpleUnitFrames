-- Auras3 runtime: DispelVisuals.
-- Dispel/Purge sensor art and thickness on square and rounded frames. Build every region and mask before AddDispelTypeTexture transfers native ownership.
-- The factory runs once at addon load; dependency bindings are local upvalues on live paths.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
MSUF.Auras3RuntimeFactories = MSUF.Auras3RuntimeFactories or {}
MSUF.Auras3RuntimeFactories.DispelVisuals = function(addonName, MSUF, A3, UF, ExportPublic, dependencies)
local math_max = math.max
local tonumber = tonumber
local type = type
local CreateFrame = dependencies.Platform.CreateFrame
local AURA_SENSOR_BORDER_OPTIONS = dependencies.Appearance.AURA_SENSOR_BORDER_OPTIONS
local AURA_SENSOR_OVERLAY_OPTIONS = dependencies.Appearance.AURA_SENSOR_OVERLAY_OPTIONS
local AuraIconBaseOffset = dependencies.ConfigValues.AuraIconBaseOffset
local Clamp01 = dependencies.Platform.Clamp01
local ClampNumber = dependencies.Platform.ClampNumber
local DISPEL_OVERLAY_EFFECT_OFFSET = dependencies.Platform.DISPEL_OVERLAY_EFFECT_OFFSET
local DS = dependencies.Appearance.DS
local FrameLayers = dependencies.Platform.FrameLayers
local IsGroupFrame = dependencies.ConfigValues.IsGroupFrame
local ResolveFrameStrata = dependencies.Platform.ResolveFrameStrata
local Round = dependencies.Platform.Round
local SyncFrameStrata = dependencies.Platform.SyncFrameStrata
local ValidateNativeAuraButtonContract = dependencies.NativeContract.ValidateNativeAuraButtonContract

local function DispelSensorTarget(parentFrame, sensor)
    if sensor and sensor.visual == "overlay" and parentFrame then
        local hp = parentFrame.hpBar or parentFrame.Health or parentFrame.health
        if not hp then return nil end
        if sensor.target == "healthFill" then
            return hp.GetStatusBarTexture and hp:GetStatusBarTexture() or nil
        end
        return hp
    end
    return parentFrame
end

local function DispelSensorButtonTarget(parentFrame, sensor)
    if sensor and sensor.visual == "overlay" then
        return parentFrame and (parentFrame.hpBar or parentFrame.Health or parentFrame.health)
    end
    return parentFrame
end

local function DispelSensorFrameLevel(parentFrame, sensor, target)
    local parentLevel = (parentFrame and parentFrame.GetFrameLevel and parentFrame:GetFrameLevel()) or 0
    if sensor and sensor.visual == "overlay" then
        local targetParent = target and target.GetParent and target:GetParent()
        local targetLevel = target and target.GetFrameLevel and target:GetFrameLevel()
            or (targetParent and targetParent.GetFrameLevel and targetParent:GetFrameLevel())
            or parentLevel
        -- Geometry follows the health target, but AUTO/equal-strata ordering is
        -- based on the unit frame so Dispel deterministically wins the shared
        -- health-effect band above every Spell Indicator priority.
        if FrameLayers.ElementLevel then return FrameLayers.ElementLevel(sensor.layer, 0, 12) end
        return math_max(targetLevel + 1, parentLevel + DISPEL_OVERLAY_EFFECT_OFFSET + (sensor.layer or 0))
    end
    if sensor and (sensor.visual == "corner" or sensor.visual == "symbol") then
        if FrameLayers.ElementLevel then return FrameLayers.ElementLevel(sensor.layer, 14, 8) end
        return parentLevel + AuraIconBaseOffset(parentFrame) + (sensor.layer or 14)
    end
    if FrameLayers.ElementLevel then
        return FrameLayers.ElementLevel(sensor and sensor.layer, 14, sensor and sensor.detail or 8)
    end
    return parentLevel + (sensor and sensor.layer or 14)
end

--- Where symbol slot `index` sits relative to the unit frame. TOP mode has a
--- single slot at the configured offset; ALL mode steps each type along the
--- growth axis. Shared by the live button and the menu preview so a dragged
--- position can never mean two different things.
function DS.SlotOffset(sensor, index)
    local x = tonumber(sensor and sensor.x) or 0
    local y = tonumber(sensor and sensor.y) or 0
    local slot = sensor and sensor.slots and sensor.slots[index or 1]
    if slot then
        x = x + (tonumber(slot.x) or 0)
        y = y + (tonumber(slot.y) or 0)
    end
    return x, y
end

function DS.LayoutButton(button, sensor, parentFrame, index)
    local size = ClampNumber(sensor.size, 14, 4, 64)
    local anchor = sensor.anchor or "TOPRIGHT"
    local x, y = DS.SlotOffset(sensor, index)
    button:ClearAllPoints()
    button:SetSize(size, size)
    button:SetPoint(anchor, parentFrame, anchor, x, y)
    SyncFrameStrata(button, ResolveFrameStrata(parentFrame, sensor.strata))
    if button.SetFrameLevel then button:SetFrameLevel(DispelSensorFrameLevel(parentFrame, sensor, parentFrame)) end
    return true
end

local function LayoutDispelSensorButton(button, sensor, parentFrame, index)
    if not (button and sensor and parentFrame) then return false end
    if sensor.visual == "symbol" then
        -- Symbols are the one sensor visual with their own rect: they are a
        -- placed indicator, not a wash over the health bar.
        return DS.LayoutButton(button, sensor, parentFrame, index)
    end
    -- The AuraButton owns native assignment/visibility, but its stable geometry
    -- is the health-bar rectangle. The visible region is anchored separately to
    -- the current fill when requested, avoiding a whole-unit-frame fallback.
    local target = DispelSensorButtonTarget(parentFrame, sensor)
    if not target then return false end
    button:ClearAllPoints()
    -- Corner buttons cover the whole target like border/overlay: the single
    -- consolidated button hosts one region per corner, each anchored to the
    -- button rect (== target rect), so per-corner button geometry is gone.
    button:SetAllPoints(target)
    SyncFrameStrata(button, ResolveFrameStrata(parentFrame, sensor.strata))
    if button.SetFrameLevel then button:SetFrameLevel(DispelSensorFrameLevel(parentFrame, sensor, target)) end
    return true
end

local function LayoutDispelSensorOverlay(region, button, sensor, visualTarget)
    if not (region and button and sensor) then return false end
    local style = sensor.style or "FULL"
    local thickness = ClampNumber(sensor.thickness, 3, 1, 32)
    region:ClearAllPoints()
    local target = visualTarget
    if not target then return false end
    if style == "TOP" then
        region:SetPoint("TOPLEFT", target, "TOPLEFT", 0, 0)
        region:SetPoint("TOPRIGHT", target, "TOPRIGHT", 0, 0)
        region:SetHeight(thickness)
    elseif style == "BOTTOM" then
        region:SetPoint("BOTTOMLEFT", target, "BOTTOMLEFT", 0, 0)
        region:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 0, 0)
        region:SetHeight(thickness)
    elseif style == "LEFT" then
        region:SetPoint("TOPLEFT", target, "TOPLEFT", 0, 0)
        region:SetPoint("BOTTOMLEFT", target, "BOTTOMLEFT", 0, 0)
        region:SetWidth(thickness)
    elseif style == "RIGHT" then
        region:SetPoint("TOPRIGHT", target, "TOPRIGHT", 0, 0)
        region:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 0, 0)
        region:SetWidth(thickness)
    else
        region:SetAllPoints(target)
    end
    return true
end

-- MSUF supplies its own sensor art (WHITE8X8 fill / msuf edge texture) and only
-- wants Blizzard to apply the dispel-type color. On PTR 7 that is
-- PreserveAsset; Border/BorderWithIcon would replace the texture with the
-- stock dispel border atlas and reset its vertex color, destroying the
-- overlay/corner visuals.
local function GetSensorOverlayOptions()
    local styles = _G.Enum and _G.Enum.CustomAuraButtonDispelTypeTextureStyle
    AURA_SENSOR_OVERLAY_OPTIONS.style = styles and styles.PreserveAsset or nil
    return A3.ApplyHarmfulDispelColorOptions(AURA_SENSOR_OVERLAY_OPTIONS)
end

local function GetSensorBorderOptions()
    local styles = _G.Enum and _G.Enum.CustomAuraButtonDispelTypeTextureStyle
    AURA_SENSOR_BORDER_OPTIONS.style = styles and styles.PreserveAsset or nil
    return A3.ApplyHarmfulDispelColorOptions(AURA_SENSOR_BORDER_OPTIONS)
end

--- Symbol sensors let Blizzard pick the artwork, because only Blizzard may look
--- at the aura's dispel type. AddDispelTypeTexture securecopies the options
--- table at bind time, so reusing this one table across buttons is safe.
function DS.Options(style)
    local styles = _G.Enum and _G.Enum.CustomAuraButtonDispelTypeTextureStyle
    local assets = DS.AssetMap(style)
    if assets then
        DS.options.style = styles and styles.CustomAsset or nil
        DS.options.customDispelAssetMap = assets
    else
        DS.options.style = styles
            and (style == "BLIZZARD_RING" and styles.BorderWithIcon
                or style == "BLIZZARD_BORDER" and styles.Border
                or styles.Icon)
            or nil
        DS.options.customDispelAssetMap = nil
    end
    -- Custom MSUF symbols switch overridden types to neutral-alpha companions,
    -- so Blizzard's vertex color replaces their color instead of multiplying
    -- the already-colored art into near-black. Stock Blizzard atlases remain
    -- untouched because they have no tint-neutral asset counterpart.
    DS.options.customDispelColorMap = assets and A3.GetCustomDispelColorMap() or nil
    return DS.options
end

-- Live native regions must be prepared before AddDispelTypeTexture seals their
-- layout. This one-shot bridge never retains the region: later rounded-setting
-- changes recreate the native sensor instead of touching a forbidden object.
local function PrepareRoundedDispelOverlayRegion(parentFrame, region, owner)
    if not (parentFrame and region and owner) then return false end
    local callback = _G.MSUF_RoundedUF_PrepareDispelOverlay
    if type(callback) ~= "function" then return false end
    return callback(parentFrame, region, owner) == true
end

-- Native border regions are initialized once, then sealed by Blizzard. Keep
-- the configured thickness in geometry rather than stretching thin edge art.
-- Multiple textures share ONE AuraSlot: no extra aura selection or Lua scan.
local function PrepareDispelSensorBorder(button, sensor, parentFrame, owner)
    local thickness = Round(ClampNumber(sensor.thickness, 3, 1, 30))
    local prepare = _G.MSUF_RoundedUF_PrepareDispelBorder
    local regions = type(prepare) == "function" and prepare(parentFrame, button, thickness) or nil
    if not regions then
        regions = {}
        for i = 1, 4 do
            local edge = button:CreateTexture(nil, "OVERLAY")
            edge:SetTexture("Interface\\Buttons\\WHITE8X8")
            regions[i] = edge
        end
        local top, bottom, left, right = regions[1], regions[2], regions[3], regions[4]
        local anchor = IsGroupFrame(parentFrame) and (parentFrame.barGroup or parentFrame) or parentFrame
        top:SetPoint("TOPLEFT", anchor, "TOPLEFT", -thickness, thickness)
        top:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", thickness, thickness)
        top:SetHeight(thickness)
        bottom:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", -thickness, -thickness)
        bottom:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", thickness, -thickness)
        bottom:SetHeight(thickness)
        left:SetPoint("TOPLEFT", anchor, "TOPLEFT", -thickness, 0)
        left:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", -thickness, 0)
        left:SetWidth(thickness)
        right:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", thickness, 0)
        right:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", thickness, 0)
        right:SetWidth(thickness)
    end
    local options = sensor.visual == "purge" and A3.GetPurgeSensorTextureOptions(sensor) or GetSensorBorderOptions()
    local alpha = sensor.visual == "purge" and 1 or 0.82
    for i = 1, #regions do
        regions[i]:SetAlpha(alpha)
        owner:AddDispelTypeTexture(regions[i], options)
    end
    return true
end

-- The flat-color menu preview is entirely MSUF-owned, so it may stay in the
-- normal mutable RoundedFrames registry and follow live setting changes.
local function RegisterRoundedDispelOverlayPreviewRegion(parentFrame, region)
    if not (parentFrame and region) then return end
    local key = IsGroupFrame(parentFrame) and "_msufGFDispelOverlayPreviews" or "_msufUFDispelOverlayPreviews"
    local regions = parentFrame[key]
    if type(regions) ~= "table" then
        regions = setmetatable({}, { __mode = "k" })
        parentFrame[key] = regions
    end
    regions[region] = true
    local callback = _G.MSUF_RoundedUF_OnDispelOverlayChanged
    if type(callback) == "function" then
        callback(parentFrame, region)
    end
end

local function PrepareDispelSensorVisual(button, sensor, parentFrame, index, owner)
    if not (button and sensor and parentFrame) then return false end
    button._msufA3DispelSensor = sensor.visual
    if button.EnableMouse then button:EnableMouse(false) end
    button:SetMouseMotionEnabled(false)
    if not LayoutDispelSensorButton(button, sensor, parentFrame, index) then return false end
    -- Reset reused native buttons before a visual-specific alpha is applied.
    -- The overlay deliberately owns alpha on the button below: Blizzard's
    -- PreserveAsset path recolors its texture with SetVertexColor(..., 1) on
    -- every aura update, which otherwise erases the configured opacity.
    button:SetAlpha(1)

    if sensor.visual == "border" or sensor.visual == "purge" then
        return PrepareDispelSensorBorder(button, sensor, parentFrame, owner)
    end
    if sensor.visual == "symbol" then
        -- One texture filling the button rect. Blizzard swaps its atlas/asset
        -- per dispel type and hides it when the slot holds no typed debuff, so
        -- MSUF never needs to know which type is up.
        local region = button._msufA3DispelSymbolRegion
        if not region then
            region = button:CreateTexture(nil, "OVERLAY")
            button._msufA3DispelSymbolRegion = region
        end
        region:ClearAllPoints()
        region:SetAllPoints(button)
        region:SetAlpha(Clamp01(sensor.alpha, 1))
        owner:AddDispelTypeTexture(region, DS.Options(sensor.style))
        return true
    end
    if sensor.visual == "corner" then
        -- PTR 7 multiple dispel textures: the single consolidated corner
        -- button carries one colored region per corner slot. The button covers
        -- the target rect, so each region anchors to the button at its
        -- configured corner offset.
        local slots = sensor.slots
        if not (type(slots) == "table" and #slots > 0) then return false end
        local regions = button._msufA3DispelSensorRegions
        if not regions then
            regions = {}
            button._msufA3DispelSensorRegions = regions
        end
        local size = ClampNumber(sensor.size, 8, 1, 64)
        local alpha = Clamp01(sensor.alpha, 1)
        for i = 1, #slots do
            local slot = slots[i]
            local region = regions[i]
            if not region then
                region = button:CreateTexture(nil, "OVERLAY")
                regions[i] = region
            end
            region:ClearAllPoints()
            region:SetSize(size, size)
            region:SetPoint(slot.anchor or "TOPLEFT", button, slot.anchor or "TOPLEFT", slot.x or 0, slot.y or 0)
            region:SetTexture("Interface\\Buttons\\WHITE8X8")
            region:SetAlpha(alpha)
            owner:AddDispelTypeTexture(region, GetSensorOverlayOptions())
        end
        for i = #slots + 1, #regions do regions[i]:Hide() end
        return true
    end
    local region = button._msufA3DispelSensorRegion
    if not region then
        region = button:CreateTexture(nil, "OVERLAY")
        button._msufA3DispelSensorRegion = region
    end
    local visualTarget = DispelSensorTarget(parentFrame, sensor)
    if not LayoutDispelSensorOverlay(region, button, sensor, visualTarget) then
        region:Hide()
        return false
    end
    if sensor.visual == "overlay" then
        region:SetTexture("Interface\\Buttons\\WHITE8X8")
        region:SetAlpha(1)
        button:SetAlpha(Clamp01(sensor.alpha, 0.35))
        PrepareRoundedDispelOverlayRegion(parentFrame, region, button)
        owner:AddDispelTypeTexture(region, GetSensorOverlayOptions())
    end
    return true
end

local function PrepareDispelSensorButton(button, sensor, parentFrame, index, visuals)
    if not (button and sensor and parentFrame) then return false end
    ValidateNativeAuraButtonContract(button)
    button._msufA3NativeButton = true
    local icon = button.Icon or button:CreateTexture(nil, "ARTWORK")
    button.Icon = icon
    icon:ClearAllPoints()
    icon:SetAllPoints(button)
    icon:SetAlpha(0)
    button:SetIcon(icon)
    button:ClearApplicationCount()
    button:ClearDurationCooldown()
    button:ClearDurationText()
    button:ClearDurationBar()
    button:ClearDispelTypeText()
    button:ClearDispelTypeTextures()
    if not visuals then
        return PrepareDispelSensorVisual(button, sensor, parentFrame, index, button)
    end
    -- Identical selections share one native slot. Each visual keeps a child
    -- host for its independent alpha, layer and geometry. Build all descendants
    -- before native handoff; no MSUF callback touches them during aura updates.
    button:EnableMouse(false)
    button:SetMouseMotionEnabled(false)
    button:SetAlpha(1)
    button:SetAllPoints(parentFrame)
    for i = 1, #visuals do
        local visual = visuals[i]
        local host = CreateFrame("Frame", nil, button)
        PrepareDispelSensorVisual(host, visual.sensor, parentFrame, visual.sensorIndex, button)
    end
    return true
end

return {
    DispelSensorTarget = DispelSensorTarget,
    LayoutDispelSensorButton = LayoutDispelSensorButton,
    LayoutDispelSensorOverlay = LayoutDispelSensorOverlay,
    PrepareDispelSensorButton = PrepareDispelSensorButton,
    RegisterRoundedDispelOverlayPreviewRegion = RegisterRoundedDispelOverlayPreviewRegion,
}
end
