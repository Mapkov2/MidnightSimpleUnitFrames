-- Auras3 runtime: EffectPreview.
-- Mutable addon-owned Dispel overlay/symbol previews. Preview regions never share the sealed live-native region lifecycle.
-- The factory runs once at addon load; dependency bindings are local upvalues on live paths.
local _, MSUF = ...
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", "Auras3/Runtime/MSUF_Auras3_Runtime_EffectPreview.lua")
MSUF.Auras3RuntimeFactories = MSUF.Auras3RuntimeFactories or {}
MSUF.Auras3RuntimeFactories.EffectPreview = function(addonName, MSUF, A3, UF, ExportPublic, dependencies)
local Runtime = A3.Runtime
local EffectPreview = Runtime.EffectPreview
local PublicGlobals = MSUF.PublicGlobals
local pairs = pairs
local tonumber = tonumber
local tostring = tostring
local type = type
local Clamp01 = dependencies.Platform.Clamp01
local ClampNumber = dependencies.Platform.ClampNumber
local CompileDispelSensor = dependencies.DispelConfig.CompileDispelSensor
local CreateFrame = dependencies.Platform.CreateFrame
local DS = dependencies.Appearance.DS
local DispelSensorTarget = dependencies.DispelVisuals.DispelSensorTarget
local IsGroupFrame = dependencies.ConfigValues.IsGroupFrame
local LayoutDispelSensorButton = dependencies.DispelVisuals.LayoutDispelSensorButton
local LayoutDispelSensorOverlay = dependencies.DispelVisuals.LayoutDispelSensorOverlay
local RegisterRoundedDispelOverlayPreviewRegion = dependencies.DispelVisuals.RegisterRoundedDispelOverlayPreviewRegion
local Round = dependencies.Platform.Round

--- Dispel-overlay preview (menu-driven, cold path only).
---
--- The live overlay belongs to Blizzard: MSUF only hands a texture to
--- AddDispelTypeTexture above, and the native container owns both the button's
--- visibility and the dispel-type vertex color. Nothing can force that on
--- without a real dispellable debuff on the unit, so the preview has to be a
--- separate MSUF-owned frame.
---
--- It is laid out by the SAME two helpers as the live sensor button and fed the
--- same compiled sensor, so style, thickness, alpha, target rect, strata and
--- frame level cannot drift from the real thing. Only Show and the flat color
--- are ours -- a live tint is colored by the aura's dispel type, which has no
--- meaning when there is no aura.
EffectPreview.DISPEL_OVERLAY_PREVIEW_FIELD = "_msufA3DispelOverlayPreview"

EffectPreview.NormalizeDispelOverlayPreviewScope = MSUF.AuraConfig.NormalizePreviewScope

--- Scope match mirrors the border test modes: "shared" paints every frame, a
--- group kind paints that kind, anything else matches a unit token.
EffectPreview.DispelOverlayPreviewApplies = function(frame)
    if not frame then return false end
    local wanted = EffectPreview.NormalizeDispelOverlayPreviewScope(PublicGlobals.MSUF_DispelOverlayPreviewScope)
    if wanted == "shared" then return true end
    local groupKind = frame._msufGFKind
    if groupKind == nil then
        local spec = frame.MSUFSpec
        groupKind = spec and spec.groupKind or nil
    end
    if groupKind then
        if wanted == "raid" then return groupKind == "raid" or groupKind == "mythicraid" end
        return groupKind == wanted
    end
    return frame.MSUFUnitKey == wanted or frame.configKey == wanted
end

EffectPreview.HideDispelOverlayPreview = function(frame)
    local host = frame and frame[EffectPreview.DISPEL_OVERLAY_PREVIEW_FIELD]
    if host and host:IsShown() then host:Hide() end
    return false
end

--- Cold path only: reached from the menu toggle, from the aura apply, and from
--- the group preview build. Never from an event route.
EffectPreview.ApplyDispelOverlayPreview = function(frame)
    if PublicGlobals.MSUF_DispelOverlayPreviewMode ~= true then return EffectPreview.HideDispelOverlayPreview(frame) end
    if not (frame and frame.MSUFSpec) then return EffectPreview.HideDispelOverlayPreview(frame) end
    if not EffectPreview.DispelOverlayPreviewApplies(frame) then return EffectPreview.HideDispelOverlayPreview(frame) end
    -- Compiling straight off the frame spec keeps this independent of the
    -- native aura container, so group preview rows past the first one (which
    -- deliberately own no container) still preview the overlay.
    local sensor = CompileDispelSensor(frame.MSUFUnitKey, frame.MSUFSpec, IsGroupFrame(frame), "overlay")
    if not (sensor and sensor.enabled == true) then return EffectPreview.HideDispelOverlayPreview(frame) end
    local host = frame[EffectPreview.DISPEL_OVERLAY_PREVIEW_FIELD]
    if not host then
        -- The preview can only be switched on out of combat, so first creation
        -- always lands there. A spec apply that arrives mid-combat re-stamps an
        -- existing host but never parents a fresh frame onto a secure header.
        if InCombatLockdown and InCombatLockdown() then return false end
        host = PixelLayoutRegion(CreateFrame("Frame", nil, frame._msufHealthVisualRoot or frame))
        host:SetMouseMotionEnabled(false)
        host.Region = PixelLayoutRegion(host:CreateTexture(nil, "OVERLAY"))
        frame[EffectPreview.DISPEL_OVERLAY_PREVIEW_FIELD] = host
    end
    if not LayoutDispelSensorButton(host, sensor, frame, 1) then
        return EffectPreview.HideDispelOverlayPreview(frame)
    end
    local region = host.Region
    if not LayoutDispelSensorOverlay(region, host, sensor, DispelSensorTarget(frame, sensor)) then
        return EffectPreview.HideDispelOverlayPreview(frame)
    end
    RegisterRoundedDispelOverlayPreviewRegion(frame, region)
    A3.SetDispelColorTexture(region, A3.GetDispelColorPreviewType(), true, 1)
    region:SetAlpha(Clamp01(sensor.alpha, 0.35))
    region:Show()
    host:Show()
    return true
end

EffectPreview.ForEachDispelOverlayPreviewFrame = function(fn)
    if UF and type(UF.ForEachFrame) == "function" then UF.ForEachFrame(fn) end
    local gf = MSUF and MSUF.GF
    if not gf then return end
    if type(gf.ForEachFrame) == "function" then gf.ForEachFrame(fn, true) end
    -- Group preview rows live outside GF.frameList; walk them explicitly so the
    -- menu preview covers the rows the user is actually looking at.
    MSUF.AuraConfig.ForEachGroupPreviewFrame(gf, fn)
end

A3.RefreshDispelOverlayPreview = function()
    EffectPreview.ForEachDispelOverlayPreviewFrame(EffectPreview.ApplyDispelOverlayPreview)
    return true
end

--- Menu-facing setter, mirroring the border test-mode contract: one flag plus
--- one scope, cleared by the menu when its page hides. Combat never turns a
--- preview on.
A3.SetDispelOverlayPreview = function(active, scope)
    active = active == true
    if active and InCombatLockdown and InCombatLockdown() then active = false end
    ExportPublic("MSUF_DispelOverlayPreviewMode", active)
    ExportPublic("MSUF_DispelOverlayPreviewScope",
        active and EffectPreview.NormalizeDispelOverlayPreviewScope(scope) or nil)
    A3.RefreshDispelOverlayPreview()
    return active
end

ExportPublic("MSUF_SetDispelOverlayPreview", A3.SetDispelOverlayPreview)
ExportPublic("MSUF_RefreshDispelOverlayPreview", A3.RefreshDispelOverlayPreview)
ExportPublic("MSUF_ApplyDispelOverlayPreviewToFrame", EffectPreview.ApplyDispelOverlayPreview)

--- Dispel-symbol preview (menu-driven, cold path only).
---
--- Same contract as the overlay preview above and for the same reason: the live
--- symbol is a native AuraButton texture whose visibility and artwork Blizzard
--- owns, so nothing short of a real debuff turns it on. The preview is an
--- MSUF-owned frame that borrows the live geometry helper
--- (DS.LayoutButton) and the same compiled sensor, so size, anchor,
--- offsets, growth, strata and frame level cannot drift. Only Show and the
--- stand-in artwork are ours -- and the artwork is read from the SAME per-type
--- atlas/asset tables the live options hand to Blizzard.
---
--- It is also the drag surface: the user positions the indicator here and the
--- menu writes the resulting offset back through A3.DispelSymbolPreviewMoveHandler.
EffectPreview.DISPEL_SYMBOL_PREVIEW_FIELD = "_msufA3DispelSymbolPreview"

--- Group frames are deliberately excluded: their symbol is previewed inside the
--- menu's group preview as its own "Dispel" layer, like every other group
--- element, so painting a second stand-in onto the live raid frames would be a
--- duplicate the user cannot turn off from that layer strip. Unit frames keep
--- the on-frame preview because their Dispel Symbol card lives on Global Style >
--- Bars, which hosts no frame preview of its own.
EffectPreview.DispelSymbolPreviewApplies = function(frame)
    if not frame then return false end
    if IsGroupFrame(frame) or frame._msufGFKind ~= nil then return false end
    local spec = frame.MSUFSpec
    if spec and (spec.scope == "group" or spec.groupKind ~= nil) then return false end
    local wanted = EffectPreview.NormalizeDispelOverlayPreviewScope(PublicGlobals.MSUF_DispelSymbolPreviewScope)
    if wanted == "shared" then return true end
    return frame.MSUFUnitKey == wanted or frame.configKey == wanted
end

EffectPreview.HideDispelSymbolPreview = function(frame)
    local host = frame and frame[EffectPreview.DISPEL_SYMBOL_PREVIEW_FIELD]
    if host and host:IsShown() then host:Hide() end
    return false
end

--- Stand-in artwork for one dispel type, taken from the very tables the live
--- path passes to Blizzard so the preview cannot show art the runtime wouldn't.
function DS.PreviewArt(texture, style, dispelType)
    texture:SetTexCoord(0, 1, 0, 1)
    local assets = DS.AssetMap(style)
    if assets then
        local asset = assets[dispelType]
        texture:SetTexture(asset and asset.asset or nil)
        if A3.HasDispelTypeColorOverride(dispelType) then
            A3.SetDispelVertexColor(texture, dispelType, true, 1)
        else
            texture:SetVertexColor(1, 1, 1, 1)
        end
        return
    end
    local atlas = (style == "BLIZZARD_RING" and DS.rings
        or style == "BLIZZARD_BORDER" and DS.borders
        or DS.icons)[dispelType]
    if atlas and texture.SetAtlas then
        texture:SetAtlas(atlas, TextureKitConstants and TextureKitConstants.IgnoreAtlasSize)
    else
        texture:SetTexture(nil)
    end
    texture:SetVertexColor(1, 1, 1, 1)
end

--- Turn the host's current on-screen rect back into the offset pair that
--- reproduces it from `anchor`. Host and parent share a scale (host is parented
--- to the frame), so raw edge coordinates are directly comparable.
function DS.AnchorOffset(host, parent, anchor)
    local x, y = A3.HostAnchorOffset(host, parent, anchor)
    if x == nil then return nil, nil end
    return Round(x), Round(y)
end

A3.DispelSymbolPreviewMoveHandler = nil

function DS.OnDragStart(host)
    if InCombatLockdown and InCombatLockdown() then return end
    host:StartMoving()
end

function DS.OnDragStop(host)
    host:StopMovingOrSizing()
    local frame = host._msufA3PreviewParent
    local sensor = host._msufA3PreviewSensor
    local handler = A3.DispelSymbolPreviewMoveHandler
    if not (frame and sensor) then return end
    local x, y = DS.AnchorOffset(host, frame, sensor.anchor)
    if x == nil then return end
    -- The dragged tile is slot `index`; the stored offset is the base, so take
    -- that slot's own step back out. Dragging any symbol therefore moves the
    -- whole set and keeps the growth spacing intact.
    local slot = sensor.slots and sensor.slots[host._msufA3PreviewSlotIndex or 1]
    if slot then
        x = x - (tonumber(slot.x) or 0)
        y = y - (tonumber(slot.y) or 0)
    end
    if type(handler) == "function" then
        handler(PublicGlobals.MSUF_DispelSymbolPreviewScope, x, y, frame)
    end
    A3.RefreshDispelSymbolPreview()
end

function DS.PreviewTile(host, index)
    local tiles = host._msufA3PreviewTiles
    if not tiles then
        tiles = {}
        host._msufA3PreviewTiles = tiles
    end
    local tile = tiles[index]
    if not tile then
        tile = PixelLayoutRegion(CreateFrame("Frame", nil, host))
        tile.Texture = PixelLayoutRegion(tile:CreateTexture(nil, "OVERLAY"))
        tile.Texture:SetAllPoints(tile)
        tiles[index] = tile
    end
    return tile
end

--- Cold path only: menu toggle, spec apply, group preview build.
EffectPreview.ApplyDispelSymbolPreview = function(frame)
    if PublicGlobals.MSUF_DispelSymbolPreviewMode ~= true then return EffectPreview.HideDispelSymbolPreview(frame) end
    if not (frame and frame.MSUFSpec) then return EffectPreview.HideDispelSymbolPreview(frame) end
    if not EffectPreview.DispelSymbolPreviewApplies(frame) then return EffectPreview.HideDispelSymbolPreview(frame) end
    local sensor = CompileDispelSensor(frame.MSUFUnitKey, frame.MSUFSpec, IsGroupFrame(frame), "symbol")
    if not (sensor and sensor.enabled == true) then return EffectPreview.HideDispelSymbolPreview(frame) end
    local host = frame[EffectPreview.DISPEL_SYMBOL_PREVIEW_FIELD]
    if not host then
        -- Previews only switch on out of combat, so first creation always lands
        -- there. A spec apply arriving mid-combat re-stamps an existing host but
        -- never parents a fresh frame onto a secure header.
        if InCombatLockdown and InCombatLockdown() then return false end
        host = PixelLayoutRegion(CreateFrame("Frame", nil, frame._msufHealthVisualRoot or frame))
        host:SetClampedToScreen(false)
        host:SetMovable(true)
        host:EnableMouse(true)
        host:RegisterForDrag("LeftButton")
        host:SetScript("OnDragStart", DS.OnDragStart)
        host:SetScript("OnDragStop", DS.OnDragStop)
        frame[EffectPreview.DISPEL_SYMBOL_PREVIEW_FIELD] = host
    end
    host._msufA3PreviewParent = frame
    host._msufA3PreviewSensor = sensor
    -- The host IS the first symbol's rect, laid out by the live helper. Extra
    -- ALL-mode tiles hang off it at their compiled step, so what the user drags
    -- is exactly what the runtime will draw.
    host._msufA3PreviewSlotIndex = 1
    if not DS.LayoutButton(host, sensor, frame, 1) then
        return EffectPreview.HideDispelSymbolPreview(frame)
    end
    local style = sensor.style or "BLIZZARD"
    local alpha = Clamp01(sensor.alpha, 1)
    local size = ClampNumber(sensor.size, 14, 4, 64)
    local slots = sensor.slots
    local count = slots and #slots or 1
    -- Tiles hang off the host, which already sits at slot 1, so every tile is
    -- placed relative to that one origin.
    local baseX, baseY = DS.SlotOffset(sensor, 1)
    for i = 1, count do
        local tile = DS.PreviewTile(host, i)
        local slotX, slotY = DS.SlotOffset(sensor, i)
        tile:ClearAllPoints()
        tile:SetSize(size, size)
        tile:SetPoint("TOPLEFT", host, "TOPLEFT", slotX - baseX, slotY - baseY)
        tile:SetAlpha(alpha)
        DS.PreviewArt(tile.Texture, style,
            (slots and slots[i] and slots[i].dispelType) or "Magic")
        tile:Show()
    end
    local tiles = host._msufA3PreviewTiles
    if tiles then
        for i = count + 1, #tiles do tiles[i]:Hide() end
    end
    host:Show()
    return true
end

A3.RefreshDispelSymbolPreview = function()
    EffectPreview.ForEachDispelOverlayPreviewFrame(EffectPreview.ApplyDispelSymbolPreview)
    return true
end

--- Menu-facing setter, mirroring the overlay preview contract: one flag plus one
--- scope, cleared by the menu when its page hides. Combat never turns it on.
A3.SetDispelSymbolPreview = function(active, scope)
    active = active == true
    if active and InCombatLockdown and InCombatLockdown() then active = false end
    ExportPublic("MSUF_DispelSymbolPreviewMode", active)
    ExportPublic("MSUF_DispelSymbolPreviewScope",
        active and EffectPreview.NormalizeDispelOverlayPreviewScope(scope) or nil)
    A3.RefreshDispelSymbolPreview()
    return active
end

A3.SetDispelSymbolPreviewMoveHandler = function(handler)
    A3.DispelSymbolPreviewMoveHandler = type(handler) == "function" and handler or nil
    return true
end

ExportPublic("MSUF_SetDispelSymbolPreview", A3.SetDispelSymbolPreview)
ExportPublic("MSUF_RefreshDispelSymbolPreview", A3.RefreshDispelSymbolPreview)
ExportPublic("MSUF_ApplyDispelSymbolPreviewToFrame", EffectPreview.ApplyDispelSymbolPreview)
ExportPublic("MSUF_SetDispelSymbolPreviewMoveHandler", A3.SetDispelSymbolPreviewMoveHandler)

function EffectPreview.PaintScene(frame, sensors)
    sensors = sensors or {}
    local overlay, sensor = frame._msufSceneDispelOverlay, sensors.dispelOverlay
    if sensor and sensor.enabled then
        if not overlay then
            overlay = PixelLayoutRegion(CreateFrame("Frame", nil, frame._msufHealthVisualRoot or frame))
            overlay:EnableMouse(false)
            overlay.Region = PixelLayoutRegion(overlay:CreateTexture(nil, "OVERLAY"))
            frame._msufSceneDispelOverlay = overlay
        end
        if LayoutDispelSensorButton(overlay, sensor, frame, 1)
            and LayoutDispelSensorOverlay(overlay.Region, overlay, sensor, DispelSensorTarget(frame, sensor)) then
            RegisterRoundedDispelOverlayPreviewRegion(frame, overlay.Region)
            A3.SetDispelColorTexture(overlay.Region, A3.GetDispelColorPreviewType(), true, 1)
            overlay.Region:SetAlpha(Clamp01(sensor.alpha, 0.35))
            overlay.Region:Show()
            overlay:Show()
        end
    elseif overlay then overlay:Hide() end
    local host = frame._msufSceneDispelSymbol
    sensor = sensors.dispelSymbol
    if sensor and sensor.enabled then
        if not host then
            host = PixelLayoutRegion(CreateFrame("Frame", nil, frame._msufHealthVisualRoot or frame))
            host:EnableMouse(false)
            frame._msufSceneDispelSymbol = host
        end
        DS.LayoutButton(host, sensor, frame, 1)
        local slots, size = sensor.slots, ClampNumber(sensor.size, 14, 4, 64)
        local x, y = DS.SlotOffset(sensor, 1)
        local count = slots and #slots or 1
        for i = 1, count do
            local tile = DS.PreviewTile(host, i)
            local sx, sy = DS.SlotOffset(sensor, i)
            tile:ClearAllPoints()
            tile:SetPoint("TOPLEFT", host, "TOPLEFT", sx - x, sy - y)
            tile:SetSize(size, size)
            tile:SetAlpha(Clamp01(sensor.alpha, 1))
            DS.PreviewArt(tile.Texture, sensor.style or "BLIZZARD", slots and slots[i] and slots[i].dispelType or "Magic")
            tile:Show()
        end
        for i = count + 1, #(host._msufA3PreviewTiles or {}) do host._msufA3PreviewTiles[i]:Hide() end
        host:Show()
    elseif host then host:Hide() end
end

local exports = {
}
for name, value in pairs(exports) do EffectPreview[name] = value end
return EffectPreview
end
