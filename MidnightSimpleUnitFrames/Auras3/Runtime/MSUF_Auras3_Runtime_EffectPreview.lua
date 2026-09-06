-- Auras3 runtime: EffectPreview.
-- Mutable addon-owned Dispel overlay/symbol previews. Preview regions never share the sealed live-native region lifecycle.
-- The factory runs once at addon load; dependency bindings are local upvalues on live paths.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
MSUF.Auras3RuntimeFactories = MSUF.Auras3RuntimeFactories or {}
MSUF.Auras3RuntimeFactories.EffectPreview = function(addonName, MSUF, A3, UF, ExportPublic, dependencies)
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
A3._DISPEL_OVERLAY_PREVIEW_FIELD = "_msufA3DispelOverlayPreview"

A3._NormalizeDispelOverlayPreviewScope = function(scope)
    scope = tostring(scope or "shared"):lower()
    if scope == "" or scope == "all" or scope == "global" then return "shared" end
    if scope == "gf_party" then return "party" end
    if scope == "gf_raid" then return "raid" end
    if scope == "gf_mythicraid" then return "mythicraid" end
    return scope
end

--- Scope match mirrors the border test modes: "shared" paints every frame, a
--- group kind paints that kind, anything else matches a unit token.
A3._DispelOverlayPreviewApplies = function(frame)
    if not frame then return false end
    local wanted = A3._NormalizeDispelOverlayPreviewScope(_G.MSUF_DispelOverlayPreviewScope)
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

A3._HideDispelOverlayPreview = function(frame)
    local host = frame and frame[A3._DISPEL_OVERLAY_PREVIEW_FIELD]
    if host and host:IsShown() then host:Hide() end
    return false
end

--- Cold path only: reached from the menu toggle, from the aura apply, and from
--- the group preview build. Never from an event route.
A3._ApplyDispelOverlayPreview = function(frame)
    if _G.MSUF_DispelOverlayPreviewMode ~= true then return A3._HideDispelOverlayPreview(frame) end
    if not (frame and frame.MSUFSpec) then return A3._HideDispelOverlayPreview(frame) end
    if not A3._DispelOverlayPreviewApplies(frame) then return A3._HideDispelOverlayPreview(frame) end
    -- Compiling straight off the frame spec keeps this independent of the
    -- native aura container, so group preview rows past the first one (which
    -- deliberately own no container) still preview the overlay.
    local sensor = CompileDispelSensor(frame.MSUFUnitKey, frame.MSUFSpec, IsGroupFrame(frame), "overlay")
    if not (sensor and sensor.enabled == true) then return A3._HideDispelOverlayPreview(frame) end
    local host = frame[A3._DISPEL_OVERLAY_PREVIEW_FIELD]
    if not host then
        -- The preview can only be switched on out of combat, so first creation
        -- always lands there. A spec apply that arrives mid-combat re-stamps an
        -- existing host but never parents a fresh frame onto a secure header.
        if _G.InCombatLockdown and _G.InCombatLockdown() then return false end
        host = CreateFrame("Frame", nil, frame._msufHealthVisualRoot or frame)
        host:SetMouseMotionEnabled(false)
        host.Region = host:CreateTexture(nil, "OVERLAY")
        frame[A3._DISPEL_OVERLAY_PREVIEW_FIELD] = host
    end
    if not LayoutDispelSensorButton(host, sensor, frame, 1) then
        return A3._HideDispelOverlayPreview(frame)
    end
    local region = host.Region
    if not LayoutDispelSensorOverlay(region, host, sensor, DispelSensorTarget(frame, sensor)) then
        return A3._HideDispelOverlayPreview(frame)
    end
    RegisterRoundedDispelOverlayPreviewRegion(frame, region)
    A3.SetDispelColorTexture(region, A3.GetDispelColorPreviewType(), true, 1)
    region:SetAlpha(Clamp01(sensor.alpha, 0.35))
    region:Show()
    host:Show()
    return true
end

A3._ForEachDispelOverlayPreviewFrame = function(fn)
    if UF and type(UF.ForEachFrame) == "function" then UF.ForEachFrame(fn) end
    local gf = MSUF and MSUF.GF
    if not gf then return end
    if type(gf.ForEachFrame) == "function" then gf.ForEachFrame(fn, true) end
    -- Group preview rows live outside GF.frameList; walk them explicitly so the
    -- menu preview covers the rows the user is actually looking at.
    local previews = gf._previewFrames
    if type(previews) ~= "table" then return end
    for _, frames in pairs(previews) do
        if type(frames) == "table" then
            for _, frame in pairs(frames) do
                if type(frame) == "table" then fn(frame) end
            end
        end
    end
end

A3.RefreshDispelOverlayPreview = function()
    A3._ForEachDispelOverlayPreviewFrame(A3._ApplyDispelOverlayPreview)
    return true
end

--- Menu-facing setter, mirroring the border test-mode contract: one flag plus
--- one scope, cleared by the menu when its page hides. Combat never turns a
--- preview on.
A3.SetDispelOverlayPreview = function(active, scope)
    active = active == true
    if active and _G.InCombatLockdown and _G.InCombatLockdown() then active = false end
    ExportPublic("MSUF_DispelOverlayPreviewMode", active)
    ExportPublic("MSUF_DispelOverlayPreviewScope",
        active and A3._NormalizeDispelOverlayPreviewScope(scope) or nil)
    A3.RefreshDispelOverlayPreview()
    return active
end

ExportPublic("MSUF_SetDispelOverlayPreview", A3.SetDispelOverlayPreview)
ExportPublic("MSUF_RefreshDispelOverlayPreview", A3.RefreshDispelOverlayPreview)
ExportPublic("MSUF_ApplyDispelOverlayPreviewToFrame", A3._ApplyDispelOverlayPreview)

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
A3._DISPEL_SYMBOL_PREVIEW_FIELD = "_msufA3DispelSymbolPreview"

--- Group frames are deliberately excluded: their symbol is previewed inside the
--- menu's group preview as its own "Dispel" layer, like every other group
--- element, so painting a second stand-in onto the live raid frames would be a
--- duplicate the user cannot turn off from that layer strip. Unit frames keep
--- the on-frame preview because their Dispel Symbol card lives on Global Style >
--- Bars, which hosts no frame preview of its own.
A3._DispelSymbolPreviewApplies = function(frame)
    if not frame then return false end
    if IsGroupFrame(frame) or frame._msufGFKind ~= nil then return false end
    local spec = frame.MSUFSpec
    if spec and (spec.scope == "group" or spec.groupKind ~= nil) then return false end
    local wanted = A3._NormalizeDispelOverlayPreviewScope(_G.MSUF_DispelSymbolPreviewScope)
    if wanted == "shared" then return true end
    return frame.MSUFUnitKey == wanted or frame.configKey == wanted
end

A3._HideDispelSymbolPreview = function(frame)
    local host = frame and frame[A3._DISPEL_SYMBOL_PREVIEW_FIELD]
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
        texture:SetAtlas(atlas, _G.TextureKitConstants and _G.TextureKitConstants.IgnoreAtlasSize)
    else
        texture:SetTexture(nil)
    end
    texture:SetVertexColor(1, 1, 1, 1)
end

--- Turn the host's current on-screen rect back into the offset pair that
--- reproduces it from `anchor`. Host and parent share a scale (host is parented
--- to the frame), so raw edge coordinates are directly comparable.
function DS.AnchorOffset(host, parent, anchor)
    local hl, hr, ht, hb = host:GetLeft(), host:GetRight(), host:GetTop(), host:GetBottom()
    local pl, pr, pt, pb = parent:GetLeft(), parent:GetRight(), parent:GetTop(), parent:GetBottom()
    if not (hl and hr and ht and hb and pl and pr and pt and pb) then return nil, nil end
    anchor = tostring(anchor or "TOPRIGHT")
    local x
    if anchor:find("LEFT", 1, true) then
        x = hl - pl
    elseif anchor:find("RIGHT", 1, true) then
        x = hr - pr
    else
        x = ((hl + hr) * 0.5) - ((pl + pr) * 0.5)
    end
    local y
    if anchor:find("TOP", 1, true) then
        y = ht - pt
    elseif anchor:find("BOTTOM", 1, true) then
        y = hb - pb
    else
        y = ((ht + hb) * 0.5) - ((pt + pb) * 0.5)
    end
    return Round(x), Round(y)
end

A3.DispelSymbolPreviewMoveHandler = nil

function DS.OnDragStart(host)
    if _G.InCombatLockdown and _G.InCombatLockdown() then return end
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
        handler(_G.MSUF_DispelSymbolPreviewScope, x, y, frame)
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
        tile = CreateFrame("Frame", nil, host)
        tile.Texture = tile:CreateTexture(nil, "OVERLAY")
        tile.Texture:SetAllPoints(tile)
        tiles[index] = tile
    end
    return tile
end

--- Cold path only: menu toggle, spec apply, group preview build.
A3._ApplyDispelSymbolPreview = function(frame)
    if _G.MSUF_DispelSymbolPreviewMode ~= true then return A3._HideDispelSymbolPreview(frame) end
    if not (frame and frame.MSUFSpec) then return A3._HideDispelSymbolPreview(frame) end
    if not A3._DispelSymbolPreviewApplies(frame) then return A3._HideDispelSymbolPreview(frame) end
    local sensor = CompileDispelSensor(frame.MSUFUnitKey, frame.MSUFSpec, IsGroupFrame(frame), "symbol")
    if not (sensor and sensor.enabled == true) then return A3._HideDispelSymbolPreview(frame) end
    local host = frame[A3._DISPEL_SYMBOL_PREVIEW_FIELD]
    if not host then
        -- Previews only switch on out of combat, so first creation always lands
        -- there. A spec apply arriving mid-combat re-stamps an existing host but
        -- never parents a fresh frame onto a secure header.
        if _G.InCombatLockdown and _G.InCombatLockdown() then return false end
        host = CreateFrame("Frame", nil, frame._msufHealthVisualRoot or frame)
        host:SetClampedToScreen(false)
        host:SetMovable(true)
        host:EnableMouse(true)
        host:RegisterForDrag("LeftButton")
        host:SetScript("OnDragStart", DS.OnDragStart)
        host:SetScript("OnDragStop", DS.OnDragStop)
        frame[A3._DISPEL_SYMBOL_PREVIEW_FIELD] = host
    end
    host._msufA3PreviewParent = frame
    host._msufA3PreviewSensor = sensor
    -- The host IS the first symbol's rect, laid out by the live helper. Extra
    -- ALL-mode tiles hang off it at their compiled step, so what the user drags
    -- is exactly what the runtime will draw.
    host._msufA3PreviewSlotIndex = 1
    if not DS.LayoutButton(host, sensor, frame, 1) then
        return A3._HideDispelSymbolPreview(frame)
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
    A3._ForEachDispelOverlayPreviewFrame(A3._ApplyDispelSymbolPreview)
    return true
end

--- Menu-facing setter, mirroring the overlay preview contract: one flag plus one
--- scope, cleared by the menu when its page hides. Combat never turns it on.
A3.SetDispelSymbolPreview = function(active, scope)
    active = active == true
    if active and _G.InCombatLockdown and _G.InCombatLockdown() then active = false end
    ExportPublic("MSUF_DispelSymbolPreviewMode", active)
    ExportPublic("MSUF_DispelSymbolPreviewScope",
        active and A3._NormalizeDispelOverlayPreviewScope(scope) or nil)
    A3.RefreshDispelSymbolPreview()
    return active
end

A3.SetDispelSymbolPreviewMoveHandler = function(handler)
    A3.DispelSymbolPreviewMoveHandler = type(handler) == "function" and handler or nil
    return true
end

ExportPublic("MSUF_SetDispelSymbolPreview", A3.SetDispelSymbolPreview)
ExportPublic("MSUF_RefreshDispelSymbolPreview", A3.RefreshDispelSymbolPreview)
ExportPublic("MSUF_ApplyDispelSymbolPreviewToFrame", A3._ApplyDispelSymbolPreview)
ExportPublic("MSUF_SetDispelSymbolPreviewMoveHandler", A3.SetDispelSymbolPreviewMoveHandler)

return {
}
end
