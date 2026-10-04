-- Button hints beside the MSUF window the gamepad drives (WoW Forever Gamepad UI),
-- the way Blizzard's own gamepad frames show their prompt footer. The icons are
-- Blizzard's for the connected controller (Xbox, PlayStation, Switch), read
-- through InputIconTextureSetUtility, which only looks up atlas names, and laid
-- out like InputPromptTwoIconWithTextTemplate (24 px icons, a 16 px divider).
-- The hint list comes from PadNavigation.lua; labels are English keys MSUF.L
-- translates.
local _, MSUF = ...
if not (MSUF.Client and MSUF.Client.IsForever) then return end
local PadNav = MSUF.PadNavigation
if not PadNav then return end
local Kit = PadNav.Kit
local PixelLayoutRegion = Kit.PixelLayoutRegion

local Prompts = {}
PadNav.Prompts = Prompts

local max = math.max
local ICON, DIVIDER, GAP, ENTRY_GAP, PAD, HEIGHT, MARGIN = 24, 16, 4, 14, 10, 36, 6
-- Blizzard's newer prompt atlases have a 76x75 canvas with shadow padding;
-- InputIconTextureMixin:ApplyTextureLayout draws them past the icon's box.
local LARGE_W, LARGE_H = 76, 75
local BAR_COLOR, EDGE_COLOR = { 0.015, 0.03, 0.055, 0.92 }, { 0.22, 0.78, 0.94, 0.45 }
local MOVE_EDGE = { 1, 0.62, 0.15, 0.8 }
-- Text when the controller has no icon for a button.
local SHORT = {
    PAD1 = "A", PAD2 = "B", PAD3 = "X", PAD4 = "Y", PADLSHOULDER = "LB", PADRSHOULDER = "RB",
    PADLTRIGGER = "LT", PADRTRIGGER = "RT", PADBACK = "View", PADFORWARD = "Menu", DIRPAD = "+",
    DIRPADHORIZONTAL = "<>", PADRSTICKAXIS = "RS", PADRSTICK = "R3", SLASH = "/", PLUS = "+",
}
-- Icon slots per hint: a modifier, Blizzard's plus, then two buttons with a slash.
local SLOTS = 5

local bar, edges
local entries = {}

local function Tr(text)
    local L = MSUF.L
    local value = L and L[text]
    return type(value) == "string" and value ~= "" and value or text
end

-- InputIconTextureState is local to InputIconTexture.lua; its Normal state is 1.
local NORMAL_STATE = 1

local function IconAtlas(key)
    local util = _G.InputIconTextureSetUtility
    if type(util) ~= "table" or type(util.GetActiveInputIconButtonTextures) ~= "function" then return nil end
    local textures = util.GetActiveInputIconButtonTextures(key)
    local atlas = type(textures) == "table" and textures[NORMAL_STATE] or nil
    return type(atlas) == "string" and atlas ~= "" and atlas or nil
end

-- "large" or "plain" for an atlas the client has, nil for one it lacks (its
-- button then shows as text instead of an empty gap).
local function AtlasLayout(atlas)
    local texture = _G.C_Texture
    if type(texture) ~= "table" or type(texture.GetAtlasInfo) ~= "function" then return "plain" end
    local info = texture.GetAtlasInfo(atlas)
    if type(info) ~= "table" then return nil end
    return info.width == LARGE_W and info.height == LARGE_H and "large" or "plain"
end

local function EnsureBar()
    if bar then return bar end
    bar = Kit.CreateUnhookedFrame("Frame", UIParent)
    bar:SetFrameStrata("TOOLTIP")
    bar:SetFrameLevel(Kit.RING_LEVEL - 50)
    bar:SetClampedToScreen(true)
    bar:EnableMouse(false)
    local fill = PixelLayoutRegion(bar:CreateTexture(nil, "BACKGROUND"))
    fill:SetAllPoints()
    fill:SetColorTexture(BAR_COLOR[1], BAR_COLOR[2], BAR_COLOR[3], BAR_COLOR[4])
    edges = Kit.AddBorder(bar, EDGE_COLOR, 1)
    bar:Hide()
    return bar
end

-- One hint: up to two button icons (with Blizzard's slash between them) and a label.
local function Entry(index)
    local entry = entries[index]
    if entry then return entry end
    entry = { icons = {}, keys = {}, label = PixelLayoutRegion(bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")) }
    for slot = 1, SLOTS do
        entry.icons[slot] = PixelLayoutRegion(bar:CreateTexture(nil, "ARTWORK"))
        entry.keys[slot] = PixelLayoutRegion(bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"))
    end
    entries[index] = entry
    return entry
end

local function Width(region)
    local width = Kit.Plain(region:GetStringWidth())
    return width or 0
end

-- Places one icon of size (or its short text) at x and returns the next x.
local function PlaceKey(entry, slot, key, x, size)
    local icon, text = entry.icons[slot], entry.keys[slot]
    local atlas = IconAtlas(key)
    local layout = atlas and AtlasLayout(atlas)
    icon:ClearAllPoints()
    text:ClearAllPoints()
    if layout then
        local half = size * 0.5
        icon:SetAtlas(atlas)
        if layout == "large" then
            icon:SetPoint("TOPLEFT", bar, "LEFT", x - 5, half + 5)
            icon:SetPoint("BOTTOMRIGHT", bar, "LEFT", x + size + 4, -half - 3)
            icon:SetTexCoord(0.015, 0.96, 0.015, 0.94)
        else
            icon:SetPoint("TOPLEFT", bar, "LEFT", x, half)
            icon:SetPoint("BOTTOMRIGHT", bar, "LEFT", x + size, -half)
            icon:SetTexCoord(0, 1, 0, 1)
        end
        icon:Show()
        text:Hide()
        return x + size + GAP
    end
    icon:Hide()
    text:SetText(SHORT[key] or key)
    text:SetPoint("LEFT", bar, "LEFT", x, 0)
    text:Show()
    return x + Width(text) + GAP
end

-- keys: "PAD1", "A/B" (two buttons, a slash between) or "MOD+..." (a held
-- modifier, Blizzard's plus, then either form).
local function PlaceEntry(entry, keys, label, x)
    local slot = 1
    local modifier, rest = keys:match("^([^+]+)%+(.+)$")
    if modifier then
        x = PlaceKey(entry, 1, modifier, x, ICON)
        x = PlaceKey(entry, 2, "PLUS", x, DIVIDER)
        slot, keys = 3, rest
    end
    local first, second = keys:match("^([^/]+)/([^/]+)$")
    if first then
        x = PlaceKey(entry, slot, first, x, ICON)
        x = PlaceKey(entry, slot + 1, "SLASH", x, DIVIDER)
        x = PlaceKey(entry, slot + 2, second, x, ICON)
        slot = slot + 3
    else
        x = PlaceKey(entry, slot, keys, x, ICON)
        slot = slot + 1
    end
    for index = slot, SLOTS do
        entry.icons[index]:Hide()
        entry.keys[index]:Hide()
    end
    entry.label:SetText(Tr(label))
    entry.label:ClearAllPoints()
    entry.label:SetPoint("LEFT", bar, "LEFT", x, 0)
    entry.label:Show()
    return x + Width(entry.label) + ENTRY_GAP
end

local function HideEntry(entry)
    for index = 1, SLOTS do
        entry.icons[index]:Hide()
        entry.keys[index]:Hide()
    end
    entry.label:Hide()
end

-- The anchor with the lowest bottom edge, or with the highest top edge.
local function Edge(anchors, lowest)
    local best, bestY
    for index = 1, #anchors do
        local _, bottom, _, top = Kit.Rect(anchors[index])
        local y = lowest and bottom or top
        if y and (not best or (lowest and y < bestY) or (not lowest and y > bestY)) then
            best, bestY = anchors[index], y
        end
    end
    return best, bestY
end

-- Under the anchors when the screen has room, else above them, else over the
-- lower edge of a window that fills the screen.
local function Place(anchors)
    bar:ClearAllPoints()
    local need = (HEIGHT + MARGIN) * (Kit.Plain(UIParent:GetEffectiveScale()) or 1)
    local _, _, _, screenTop = Kit.Rect(UIParent)
    local low, bottom = Edge(anchors, true)
    local high, top = Edge(anchors, false)
    if low and bottom >= need then
        bar:SetPoint("TOP", low, "BOTTOM", 0, -MARGIN)
    elseif high and screenTop and screenTop - top >= need then
        bar:SetPoint("BOTTOM", high, "TOP", 0, MARGIN)
    else
        bar:SetPoint("BOTTOM", low or anchors[1], "BOTTOM", 0, MARGIN)
    end
end

-- list holds button keys and English labels in pairs; anchors are the window on
-- top or the frames it names. The bar stays on screen.
function Prompts.Show(list, anchors, moving)
    EnsureBar()
    local x, count = PAD, 0
    for index = 1, #list - 1, 2 do
        count = count + 1
        x = PlaceEntry(Entry(count), list[index], list[index + 1], x)
    end
    for index = count + 1, #entries do HideEntry(entries[index]) end
    local color = moving and MOVE_EDGE or EDGE_COLOR
    for index = 1, #edges do edges[index]:SetColorTexture(color[1], color[2], color[3], color[4]) end
    bar:SetSize(max(1, x - ENTRY_GAP + PAD), HEIGHT)
    Place(anchors)
    bar:Show()
end

function Prompts.Hide()
    if bar then bar:Hide() end
end
