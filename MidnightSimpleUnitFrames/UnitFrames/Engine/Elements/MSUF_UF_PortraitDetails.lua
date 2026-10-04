local _, MSUF = ...
local PixelLayoutRegion = _G.MSUF_PixelLayoutRegion or function(region, policy, ...) if type(policy) == "string" then return region[policy](region, ...) end return region end
local D = {}
MSUF.PortraitDetails = D

-- Client functions read once: every portrait refresh passes through here.
local CreateFrame = _G.CreateFrame
local issecretvalue = _G.issecretvalue
local UnitClass = _G.UnitClass
local UnitCanAttack = _G.UnitCanAttack
local IsInInstance = _G.IsInInstance

local function Number(value, fallback, low, high)
    if issecretvalue and issecretvalue(value) then return fallback end
    value = tonumber(value)
    if not value or value ~= value then return fallback end
    return math.max(low, math.min(high, value))
end

-- The stock contour's flat corner is bottom right. Mirror both dressing and
-- mask selection through one table; the image and classification dragon keep their own controls.
local BLIZZARD_DIRECTIONS = {
    BOTTOMRIGHT = { point = "TOPLEFT", x = 1, y = -1, left = 0, right = 1, top = 0, bottom = 1 },
    BOTTOMLEFT = { point = "TOPRIGHT", x = -1, y = -1, left = 1, right = 0, top = 0, bottom = 1 },
    TOPRIGHT = { point = "BOTTOMLEFT", x = 1, y = 1, left = 0, right = 1, top = 1, bottom = 0 },
    TOPLEFT = { point = "BOTTOMRIGHT", x = -1, y = 1, left = 1, right = 0, top = 1, bottom = 0 },
}
local BLIZZARD_MASK_BASE = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Masks\\portrait_blizzard_mask"
local BLIZZARD_MASKS = {
    BOTTOMRIGHT = BLIZZARD_MASK_BASE .. ".tga",
    BOTTOMLEFT = BLIZZARD_MASK_BASE .. "_bottomleft.tga",
    TOPRIGHT = BLIZZARD_MASK_BASE .. "_topright.tga",
    TOPLEFT = BLIZZARD_MASK_BASE .. "_topleft.tga",
}
function D.NormalizeBlizzardDirection(value)
    return BLIZZARD_DIRECTIONS[value] and value or "AUTO"
end
function D.GetBlizzardDirection(p)
    local direction = p and D.NormalizeBlizzardDirection(p.blizzardDirection) or "AUTO"
    if direction == "AUTO" then direction = p and p.flip and "BOTTOMLEFT" or "BOTTOMRIGHT" end
    return direction, BLIZZARD_DIRECTIONS[direction]
end
function D.GetBlizzardMask(p)
    local direction = D.GetBlizzardDirection(p)
    return BLIZZARD_MASKS[direction]
end
function D.PaintBlizzardDirection(texture, p)
    local direction, coords = D.GetBlizzardDirection(p)
    if texture._msufBlizzardDirection == direction then return end
    texture:SetTexCoord(coords.left, coords.right, coords.top, coords.bottom)
    texture._msufBlizzardDirection = direction
end
function D.LayoutBlizzardCorner(corner, holder, width, height, p)
    local direction, coords = D.GetBlizzardDirection(p)
    local key = width .. "|" .. height .. "|" .. direction
    if corner._msufBlizzardCornerLayout ~= key then
        corner:ClearAllPoints()
        corner:SetPoint(coords.point, holder, coords.point, coords.x * (34.5 / 60) * width, coords.y * (34.5 / 60) * height)
        corner:SetSize((23 / 60) * width, (23 / 60) * height)
        corner._msufBlizzardCornerLayout = key
    end
    D.PaintBlizzardDirection(corner, p)
end

function D.Compile(p, conf)
    p.flip = conf.portraitFlip == true
    p.blizzardDirection = D.NormalizeBlizzardDirection(conf.portraitBlizzardDirection)
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
end

-- Unitless events a detail adds to the portrait's own set: the hostile dragon
-- rule for instances needs the zone changes. Each union is built the first
-- time a base set asks for it and then reused.
local ZONE_CHANGES = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }
local unions = {}

function D.UnitlessEvents(base, p)
    if not (p.shape == "BLIZZARD" and p.blizzardElite == true and p.dragonInInstances == false) then return base end
    local union = unions[base]
    if not union then
        union = {}
        for i = 1, #base do union[i] = base[i] end
        for i = 1, #ZONE_CHANGES do union[#union + 1] = ZONE_CHANGES[i] end
        unions[base] = union
    end
    return union
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
