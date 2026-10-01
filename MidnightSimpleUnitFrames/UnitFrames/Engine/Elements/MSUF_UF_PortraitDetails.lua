local _, MSUF = ...
local PixelLayoutRegion = _G.MSUF_PixelLayoutRegion or function(region, policy, ...) if type(policy) == "string" then return region[policy](region, ...) end return region end
local D = {}
MSUF.PortraitDetails = D

-- Client functions read once: every portrait refresh passes through here.
local CreateFrame = _G.CreateFrame
local issecretvalue = _G.issecretvalue
local UnitIsVisible = _G.UnitIsVisible
local UnitGUID = _G.UnitGUID
local UnitClass = _G.UnitClass
local UnitCanAttack = _G.UnitCanAttack
local IsInInstance = _G.IsInInstance

local function Number(value, fallback, low, high)
    if issecretvalue and issecretvalue(value) then return fallback end
    value = tonumber(value)
    if not value or value ~= value then return fallback end
    return math.max(low, math.min(high, value))
end

function D.Compile(p, conf)
    p.flip = conf.portraitFlip == true
    p.innerShadow = Number(conf.portraitInnerShadow, 0, 0, 100) / 100
    p.dragonScale = Number(conf.portraitDragonScale, 100, 25, 300) / 100
    p.dragonX = Number(conf.portraitDragonX, 0, -200, 200)
    p.dragonY = Number(conf.portraitDragonY, 0, -200, 200)
    p.dragonFlip = conf.portraitDragonFlip == true
    p.dragonClassColor = conf.portraitDragonClassColor == true
    p.dragonInInstances = conf.portraitDragonInInstances ~= false
    p.dragonLevel = Number(conf.portraitDragonLevel, 1, 0, 30)
    local layer = conf.portraitDragonLayer
    p.dragonLayer = (layer == "BACKGROUND" or layer == "BORDER" or layer == "ARTWORK") and layer or "OVERLAY"
    -- PlayerModel is a rectangular native render surface; texture masks cannot clip it.
    if p.render == "3D" then p.shape = "SQUARE" end
end

-- Unitless events a detail adds to the portrait's own set. A 3D model only
-- needs the two combat edges (identity secrecy can change there); the hostile
-- dragon rule for instances only needs the zone changes. Each union is built
-- the first time a base set asks for it and then reused.
local COMBAT_EDGES = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }
local ZONE_CHANGES = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }
D.COMBAT_EDGE_EVENTS = { PLAYER_REGEN_DISABLED = true, PLAYER_REGEN_ENABLED = true }
local unions = {}

local function Append(target, source)
    for i = 1, #source do target[#target + 1] = source[i] end
end

function D.UnitlessEvents(base, p)
    local combat = p.render == "3D"
    local zone = p.shape == "BLIZZARD" and p.blizzardElite == true and p.dragonInInstances == false
    if not (combat or zone) then return base end
    local byBase = unions[base]
    if not byBase then
        byBase = {}
        unions[base] = byBase
    end
    local key = (combat and 1 or 0) + (zone and 2 or 0)
    local union = byBase[key]
    if not union then
        union = {}
        Append(union, base)
        if combat then Append(union, COMBAT_EDGES) end
        if zone then Append(union, ZONE_CHANGES) end
        byBase[key] = union
    end
    return union
end

-- The secret predicates return plain booleans. C_Secrets is feature-detected
-- per call, like every other reader of it; clients without it never restrict.
local function IdentityRestricted(unit)
    local secrets = _G.C_Secrets
    local predicate = secrets and secrets.ShouldUnitIdentityBeSecret
    return predicate ~= nil and predicate(unit) == true
end

-- ApplyModel records the answer it acted on; a combat edge compares against it
-- so an unchanged answer costs one predicate call and nothing else.
function D.IdentityRestrictionChanged(frame, unit, p)
    if not (p and p.render == "3D" and unit) then return false end
    return IdentityRestricted(unit) ~= (frame._msufPortraitIdentityRestricted == true)
end

-- Hiding a model drops its binding, so the next visible refresh binds the unit
-- again. The cast icon covers the model only while a cast lasts: it suspends
-- the model instead, and the end of the cast shows the same binding again.
local function ClearHiddenModel(model)
    if model._msufSuspending then return end
    model:ClearModel()
    model._msufReady = nil
    model._msufSuspended = nil
    local owner = model._msufOwner
    if owner.portrait then owner.portrait._msufPortraitKey = nil end
    owner._msufPortraitNeedsVisibleRefresh = true
end

function D.HideModel(frame)
    local model = frame.MSUFPortraitModel
    if not model then return end
    -- A suspended model is hidden already; drop its binding now.
    if model._msufSuspended then ClearHiddenModel(model) end
    model:Hide()
end

function D.SuspendModel(frame)
    local model = frame and frame.MSUFPortraitModel
    if not model or model._msufSuspended then return end
    if model._msufReady ~= true then
        D.HideModel(frame)
        return
    end
    model._msufSuspending = true
    model:Hide()
    model._msufSuspending = nil
    model._msufSuspended = true
end

-- Shows a suspended model again while it may still show its unit and returns
-- true; otherwise the clear it skipped runs now and the caller keeps the 2D
-- texture, whose next refresh resolves the portrait from scratch.
function D.ResumeModel(frame)
    local model = frame and frame.MSUFPortraitModel
    if not (model and model._msufSuspended) then return false end
    model._msufSuspended = nil
    local p = frame._msufPortraitRuntimeCfg or (frame.MSUFSpec and frame.MSUFSpec.portrait)
    local unit = frame.MSUFUnitKey
    local visible = unit and UnitIsVisible(unit)
    if not (p and p.render == "3D" and model._msufReady == true and unit)
        or (issecretvalue and issecretvalue(visible)) or not visible
        or IdentityRestricted(unit) then
        ClearHiddenModel(model)
        return false
    end
    model:Show()
    model:SetPortraitZoom(0.6)
    model:SetCamDistanceScale(100 / (p.zoom or 100))
    model:SetRotation(0, false)
    return true
end

-- SetUnit requires a declassified identity on current clients. Native 2D
-- portraits remain the fallback; never inspect, branch on or cache secret IDs.
function D.ApplyModel(frame, unit, p)
    if p.render ~= "3D" or not unit then
        D.HideModel(frame)
        return false
    end
    local restricted = IdentityRestricted(unit)
    frame._msufPortraitIdentityRestricted = restricted
    if restricted then
        D.HideModel(frame)
        return false
    end
    local visible = UnitIsVisible(unit)
    if (issecretvalue and issecretvalue(visible)) or not visible then
        D.HideModel(frame)
        return false
    end
    local model = frame.MSUFPortraitModel
    if not model then
        model = PixelLayoutRegion(CreateFrame("PlayerModel", nil, frame.MSUFPortraitHolder))
        model:SetAllPoints(frame.MSUFPortraitHolder)
        model:EnableMouse(false)
        model._msufOwner = frame
        model:SetScript("OnHide", ClearHiddenModel)
        frame.MSUFPortraitModel = model
    end
    model._msufSuspended = nil
    model:SetFrameLevel(frame.MSUFPortraitHolder:GetFrameLevel())
    model:SetUnit(unit, false)
    model:SetPortraitZoom(0.6)
    model:SetCamDistanceScale(100 / (p.zoom or 100))
    model:SetRotation(0, false)
    model._msufReady = true
    model:Show()
    frame.portrait:Hide()
    frame.portrait._msufShown = false
    return true
end

function D.ApplyShadow(holder, p)
    local shadow = holder.innerShadow
    local enabled = p.innerShadow and p.innerShadow > 0 and p.shape == "SQUARE"
    if not enabled then if shadow then shadow:Hide() end; return end
    if not shadow then
        local layer = PixelLayoutRegion(CreateFrame("Frame", nil, holder))
        layer:SetAllPoints(holder)
        layer:EnableMouse(false)
        holder.innerShadowFrame = layer
        shadow = PixelLayoutRegion(layer:CreateTexture(nil, "ARTWORK", nil, 1))
        shadow:SetAllPoints(holder)
        shadow:SetTexture("Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Borders\\msuf_aura_border_inner_shadow.tga")
        holder.innerShadow = shadow
    end
    holder.innerShadowFrame:SetFrameLevel(holder:GetFrameLevel() + 1)
    shadow:SetVertexColor(0, 0, 0, p.innerShadow)
    shadow:Show()
end

function D.ApplyPreview(holder, p, unit)
    local owner = holder._msufDetailsPreviewOwner
    if not owner then
        owner = { portrait = holder.tex, MSUFPortraitHolder = holder }
        holder._msufDetailsPreviewOwner = owner
    end
    D.ApplyShadow(holder, p)
    if p.render ~= "3D" or not unit then D.HideModel(owner); return end
    if IdentityRestricted(unit) then
        D.HideModel(owner)
        return
    end
    local visible = UnitIsVisible(unit)
    if (issecretvalue and issecretvalue(visible)) or not visible then
        D.HideModel(owner)
        return
    end
    local guid = UnitGUID(unit)
    if issecretvalue and issecretvalue(guid) then guid = nil end
    local model = owner.MSUFPortraitModel
    if model and model._msufReady and guid and owner.guid == guid and owner.zoom == p.zoom then
        model:SetFrameLevel(holder:GetFrameLevel())
        holder.tex:Hide()
        return
    end
    D.ApplyModel(owner, unit, p)
    owner.guid, owner.zoom = guid, p.zoom
end

function D.DragonAllowed(p, unit)
    if not p or p.dragonInInstances ~= false or not unit then return true end
    local inside = IsInInstance()
    if not inside then return true end
    local hostile = UnitCanAttack("player", unit)
    return not (issecretvalue and issecretvalue(hostile)) and hostile ~= true
end

-- The draw layer only orders the dragon against regions of the frame it sits
-- on, so the frame level picks that frame. Level 0 is the portrait frame (the
-- layer puts the dragon behind or in front of the portrait image); the level
-- of the frame that carries the gold ring (1 on the default layout) is that
-- frame (behind or in front of the ring). Any other level is a frame of its
-- own that many levels above the portrait, so the layer no longer matters.
function D.DragonParent(holder, p, renderParent)
    local ring = renderParent or holder.border or holder
    if not p then return ring end
    local level = p.dragonLevel or 1
    if level == 0 then return holder end
    local base = holder._msufLevel or holder:GetFrameLevel()
    if ring ~= holder and base + level == (ring._msufLevel or ring:GetFrameLevel()) then return ring end
    -- A preview draws its image and ring on one frame; its default level
    -- stays on that frame too, as the live portrait's does.
    if ring == holder and level == 1 then return ring end
    local layer = holder.dragonFrame
    if not layer then
        layer = PixelLayoutRegion(CreateFrame("Frame", nil, holder))
        layer:EnableMouse(false)
        layer:SetAllPoints(holder)
        holder.dragonFrame = layer
    end
    local target = base + level
    if layer._msufDragonFrameLevel ~= target then
        layer:SetFrameLevel(target)
        layer._msufDragonFrameLevel = target
    end
    return layer
end

function D.StyleDragon(dragon, p, unit)
    local flip = p and p.dragonFlip == true
    if dragon._msufDragonFlip ~= flip then
        -- SetAtlas owns the sheet crop; mirror its normalized local UVs.
        dragon:SetTexCoord(flip and 1 or 0, flip and 0 or 1, 0, 1)
        dragon._msufDragonFlip = flip
    end
    local r, g, b = 1, 1, 1
    if p and p.dragonClassColor and unit then
        local _, class = UnitClass(unit)
        if not (issecretvalue and issecretvalue(class)) then
            local colors = _G.RAID_CLASS_COLORS
            local color = class and colors and colors[class]
            if color then r, g, b = color.r, color.g, color.b end
        end
    end
    if dragon._msufDragonR ~= r or dragon._msufDragonG ~= g or dragon._msufDragonB ~= b then
        dragon:SetVertexColor(r, g, b, 1)
        dragon._msufDragonR, dragon._msufDragonG, dragon._msufDragonB = r, g, b
    end
    local layer = p and p.dragonLayer or "OVERLAY"
    if dragon._msufDragonLayer ~= layer then
        dragon:SetDrawLayer(layer, 3)
        dragon._msufDragonLayer = layer
    end
end
