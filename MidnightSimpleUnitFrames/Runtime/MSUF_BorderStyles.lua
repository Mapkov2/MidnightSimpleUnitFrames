--- Runtime/MSUF_BorderStyles.lua
--- Shared border-style catalog and the 8-piece edge renderer that draws them.
---
--- A "border style" is either the flat pixel ring MSUF has always drawn
--- (`SOLID`, one stretched WHITE8X8 quad) or an edgeFile: the Blizzard border
--- art format, a 256x32 sheet of eight 32x32 tiles that BackdropTemplate and
--- every LibSharedMedia `border` entry use.
---
--- Consumers here draw edgeFiles with plain textures instead of a
--- BackdropTemplate child frame. That keeps the caller in full control of the
--- draw layer (an aura shadow has to sit behind the icon, its border in front
--- of the button background), costs no extra frame per icon, and cannot
--- propagate frame protection up a parent chain. The UV table below is copied
--- from Blizzard_SharedXML/Backdrop.lua so any edgeFile authored for the
--- backdrop system renders identically here.
---
--- API:
---   MSUF.BorderStyles.List()                 -- ordered {value,text,...} items
---   MSUF.BorderStyles.FrameList(text)        -- grouped true-outline + texture items
---   MSUF.BorderStyles.NormalizeFrame(key)    -- frame key -> typed stored value
---   MSUF.BorderStyles.ResolveFrame(key)      -- key -> mode, render key, path
---   MSUF.BorderStyles.Resolve(key)           -- key -> texture path (nil = SOLID)
---   MSUF.BorderStyles.EdgeSize(key, size)    -- style-tuned edgeSize in px
---   MSUF.BorderStyles.Normalize(key)         -- unknown/missing -> "SOLID"
---   MSUF.BorderStyles.Apply(pieces, target, edge, r, g, b, a)
---   MSUF.BorderStyles.Create(owner, layer, subLayer, texture)

local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
MSUF.BorderStyles = MSUF.BorderStyles or {}
local B = MSUF.BorderStyles

local type, tonumber, tostring = type, tonumber, tostring
local ipairs, pairs = ipairs, pairs
local math_max, math_min, math_floor = math.max, math.min, math.floor
local table_sort = table.sort

local MEDIA = "Interface\\AddOns\\" .. tostring(addonName or "MidnightSimpleUnitFrames") .. "\\Media\\Borders\\"

B.SOLID = "SOLID"
B.FRAME_BORDER = "border"
B.FRAME_TEXTURE = "texture"
B.FRAME_BORDER_PREFIX = "BORDER:"

-- Built-in styles, in dropdown order.
--
-- `edgeScale`/`minEdge` turn the user's 1..8 thickness slider into an edgeSize:
-- MSUF's own art is a smooth ramp that still reads at 3px, while Blizzard's
-- carved frames need room for the corner pieces or they smear.
--
-- `placement` decides where the band sits relative to the icon:
--   "outer" (default) -- straddles the icon edge, drawn behind the icon, i.e.
--                        a frame around it. This is what edgeFile art expects.
--   "inner"           -- sits wholly inside the icon and is drawn on top of it,
--                        shading the artwork's edges rather than framing it.
local BUILTIN = {
    { value = "SOLID",   text = "Solid" },
    { value = "GLOW",    text = "Soft Glow",  path = MEDIA .. "msuf_aura_border_glow.tga",
      edgeScale = 3, minEdge = 3 },
    { value = "SHADOW",  text = "Shadow",     path = MEDIA .. "msuf_aura_border_inner_shadow.tga",
      edgeScale = 2, minEdge = 2, placement = "inner" },
    { value = "BLIZZARD", text = "Blizzard Tooltip", path = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeScale = 4, minEdge = 8 },
    { value = "DIALOG",  text = "Blizzard Dialog",   path = "Interface\\DialogFrame\\UI-DialogBox-Border",
      edgeScale = 4, minEdge = 10 },
    { value = "ACHIEVEMENT", text = "Blizzard Achievement", path = "Interface\\AchievementFrame\\UI-Achievement-WoodBorder",
      edgeScale = 4, minEdge = 10 },
}
local BUILTIN_BY_KEY = {}
for _, entry in ipairs(BUILTIN) do BUILTIN_BY_KEY[entry.value] = entry end

-- LibSharedMedia borders arrive under an "LSM:" prefix so a media name can
-- never collide with a built-in key. Skipped entries either duplicate a
-- built-in or are backgrounds that render as noise at icon scale. LSM names
-- are shown exactly as their author registered them.
local LSM_SKIP = {
    ["None"] = true,
    ["Blizzard Tooltip"] = true,
    ["Blizzard Dialog"] = true,
    ["Blizzard Achievement Wood"] = true,
}

local DEFAULT_EDGE_SCALE, DEFAULT_MIN_EDGE = 4, 8

local function GetLSM()
    local lsm = (MSUF and MSUF.LSM) or _G.MSUF_LSM
    if not lsm and type(_G.LibStub) == "function" then
        lsm = _G.LibStub("LibSharedMedia-3.0", true)
    end
    return lsm
end

local function AssetAllowed(path)
    if type(path) ~= "string" or path == "" then return nil end
    local isKnown = _G.MSUF_IsKnownFileAsset
    if type(isKnown) == "function" and isKnown(path) == false then return nil end
    return path
end

--- Ordered dropdown items: built-ins first, then LibSharedMedia borders A-Z.
--- Rebuilt on every call because LSM media can be registered by other addons
--- after login; the menu only calls this while a dropdown is opening.
function B.List()
    local items = {}
    for _, entry in ipairs(BUILTIN) do
        items[#items + 1] = { value = entry.value, text = entry.text }
    end
    local lsm = GetLSM()
    local hash = lsm and type(lsm.HashTable) == "function" and lsm:HashTable("border") or nil
    if type(hash) == "table" then
        local names = {}
        for name in pairs(hash) do
            if type(name) == "string" and name ~= "" and not LSM_SKIP[name] then
                names[#names + 1] = name
            end
        end
        table_sort(names, function(a, b) return a:lower() < b:lower() end)
        for _, name in ipairs(names) do
            items[#items + 1] = { value = "LSM:" .. name, text = name, translate = false }
        end
    end
    return items
end


local function StatusbarItems()
    local provider = _G.MSUF_StatusBarTextureItems
        or (MSUF and MSUF.UI and MSUF.UI.StatusBarTextureItems)
    local items = type(provider) == "function" and provider() or nil
    return type(items) == "table" and items or nil
end

--- Frame outlines keep their historic empty-string value for the solid-color
--- ring. True edgeFiles get a prefix; existing statusbar values stay unchanged.
function B.FrameList(solidText)
    local items = {
        { text = "True Outline", header = true, disabled = true, translate = false },
        { value = "", text = solidText or "None (solid color)" },
    }
    local styles = B.List()
    for i = 1, #styles do
        local item = styles[i]
        if item.value ~= B.SOLID then
            items[#items + 1] = {
                value = B.FRAME_BORDER_PREFIX .. item.value,
                text = item.text,
                translate = item.translate,
            }
        end
    end
    items[#items + 1] = { text = "Texture", header = true, disabled = true, translate = false }
    local textures = StatusbarItems()
    for i = 1, #(textures or {}) do
        local item = textures[i]
        if type(item) == "table" and item.value ~= "" then items[#items + 1] = item end
    end
    return items
end

--- Keep statusbar keys backward-compatible; only true outlines are typed.
function B.NormalizeFrame(key)
    if type(key) ~= "string" or key == "" or key == B.SOLID or key == "None" then return "" end
    key = key:match("^TEXTURE:(.+)$") or key -- short-lived development format
    local borderKey = key:match("^" .. B.FRAME_BORDER_PREFIX .. "(.+)$")
    if not borderKey then return key end
    borderKey = B.Normalize(borderKey)
    return borderKey == B.SOLID and "" or B.FRAME_BORDER_PREFIX .. borderKey
end

--- Resolve the selected renderer contract. Texture keys deliberately remain
--- the same values used everywhere else in MSUF's statusbar library.
function B.ResolveFrame(key)
    local normalized = B.NormalizeFrame(key)
    if normalized == "" then return nil, "", nil end
    local borderKey = normalized:match("^" .. B.FRAME_BORDER_PREFIX .. "(.+)$")
    if borderKey then
        local texture = B.Resolve(borderKey)
        return texture and B.FRAME_BORDER or nil, borderKey, texture
    end
    local resolve = _G.MSUF_ResolveStatusbarTextureKey
    local texture = type(resolve) == "function" and AssetAllowed(resolve(normalized)) or nil
    return texture and B.FRAME_TEXTURE or nil, normalized, texture
end

--- Style key -> texture path. Returns nil for SOLID and for anything that no
--- longer resolves (a media addon the user uninstalled), which callers treat
--- as "fall back to the flat ring" rather than drawing nothing.
function B.Resolve(key)
    if type(key) ~= "string" or key == "" or key == B.SOLID then return nil end
    local entry = BUILTIN_BY_KEY[key]
    if entry then return AssetAllowed(entry.path) end
    local name = key:match("^LSM:(.+)$")
    if name then
        local lsm = GetLSM()
        if lsm and type(lsm.Fetch) == "function" then
            return AssetAllowed(lsm:Fetch("border", name, true))
        end
    end
    return nil
end

--- Style key is usable only if it is SOLID or currently resolves to a file.
function B.Normalize(key)
    if type(key) ~= "string" or key == "" then return B.SOLID end
    if key == B.SOLID then return B.SOLID end
    if B.Resolve(key) then return key end
    return B.SOLID
end

--- "inner" for styles that shade the icon itself, "outer" for frames around it.
--- Callers use this to pick the draw layer and whether to inset the band.
function B.Placement(key)
    local entry = BUILTIN_BY_KEY[key]
    return entry and entry.placement == "inner" and "inner" or "outer"
end

--- Turn the shared 1..8 thickness into the edgeSize this style wants.
function B.EdgeSize(key, thickness)
    thickness = math_max(1, math_min(64, math_floor((tonumber(thickness) or 1) + 0.5)))
    local entry = BUILTIN_BY_KEY[key]
    local scale = entry and entry.edgeScale or DEFAULT_EDGE_SCALE
    local minEdge = entry and entry.minEdge or DEFAULT_MIN_EDGE
    return math_max(minEdge, thickness * scale)
end

-------------------------------------------------------------------------------
--  8-piece edge renderer
-------------------------------------------------------------------------------

-- Blizzard_SharedXML/Backdrop.lua, textureUVs. coordStart is the 1/16 inset
-- that keeps bilinear filtering from bleeding neighbouring tiles together.
local COORD_START = 0.0625
local COORD_END = 1 - COORD_START

-- Piece order matches Create()'s return table: 1 TL, 2 TR, 3 BL, 4 BR,
-- 5 top, 6 bottom, 7 left, 8 right.
local CORNER_UV = {
    [1] = { 0.5078125, 0.6171875 },
    [2] = { 0.6328125, 0.7421875 },
    [3] = { 0.7578125, 0.8671875 },
    [4] = { 0.8828125, 0.9921875 },
}
local EDGE_U = {
    [5] = { 0.2578125, 0.3671875 },  -- top
    [6] = { 0.3828125, 0.4921875 },  -- bottom
    [7] = { 0.0078125, 0.1171875 },  -- left
    [8] = { 0.1328125, 0.2421875 },  -- right
}

--- Edge UVs deliberately run past 1 so patterned edgeFile art repeats instead
--- of clamping its last texel across the strip.  Blizzard's PTR
--- BackdropTemplate passes tiling for both axes when it assigns edge art; keep
--- that contract on the four strips only.  Corners never leave their 0..1 tile
--- and stay clamped.
local function SetPieceTexture(piece, texture, repeatEdge)
    if not piece then return end
    if repeatEdge then
        piece:SetTexture(texture, "REPEAT", "REPEAT")
    else
        piece:SetTexture(texture)
    end
end

--- Create the eight textures for one owner. `layer`/`subLayer` place the whole
--- border at the requested owner layer; `texture` is the resolved edgeFile.
function B.Create(owner, layer, subLayer, texture)
    if not (owner and owner.CreateTexture) then return nil end
    local pieces = {}
    for i = 1, 8 do
        local tex = owner:CreateTexture(nil, layer or "OVERLAY", nil, subLayer or 0)
        if texture then SetPieceTexture(tex, texture, i > 4) end
        pieces[i] = tex
    end
    for i = 1, 4 do
        local u = CORNER_UV[i]
        pieces[i]:SetTexCoord(u[1], COORD_START, u[1], COORD_END, u[2], COORD_START, u[2], COORD_END)
    end
    return pieces
end

--- Point the existing pieces at a different edgeFile.
function B.SetTexture(pieces, texture)
    if not pieces then return end
    for i = 1, 8 do
        SetPieceTexture(pieces[i], texture, i > 4)
    end
end

--- Lay the border out around `target`, `edge` pixels wide, centred on the
--- target rect edge -- the placement every edgeFile is authored for.
---
--- `width`/`height` are the target's pixel size, needed for the repeat coords.
--- `inset` pushes the band inward: 0 (default) straddles the edge, `edge / 2`
--- puts the band wholly inside the target with its outer boundary exactly on
--- the target edge, which is what an "inner" style wants.
function B.Apply(pieces, target, edge, width, height, r, g, b, a, inset)
    if not (pieces and target) then return end
    width, height = tonumber(width) or 0, tonumber(height) or 0
    -- A band wider than the target is allowed: the corners then overlap and the
    -- strips between them collapse to zero width, but the corners already cover
    -- the whole run, so a shadow larger than a small icon still renders whole.
    edge = math_max(1, edge)
    local out = (edge * 0.5) - (tonumber(inset) or 0)

    for i = 1, 8 do pieces[i]:ClearAllPoints() end

    -- Corners hang `out` pixels past each target corner.
    pieces[1]:SetPoint("TOPLEFT", target, "TOPLEFT", -out, out)
    pieces[2]:SetPoint("TOPRIGHT", target, "TOPRIGHT", out, out)
    pieces[3]:SetPoint("BOTTOMLEFT", target, "BOTTOMLEFT", -out, -out)
    pieces[4]:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", out, -out)
    for i = 1, 4 do pieces[i]:SetSize(edge, edge) end

    -- Edges span between the corners.
    pieces[5]:SetPoint("TOPLEFT", pieces[1], "TOPRIGHT")
    pieces[5]:SetPoint("TOPRIGHT", pieces[2], "TOPLEFT")
    pieces[5]:SetHeight(edge)
    pieces[6]:SetPoint("BOTTOMLEFT", pieces[3], "BOTTOMRIGHT")
    pieces[6]:SetPoint("BOTTOMRIGHT", pieces[4], "BOTTOMLEFT")
    pieces[6]:SetHeight(edge)
    pieces[7]:SetPoint("TOPLEFT", pieces[1], "BOTTOMLEFT")
    pieces[7]:SetPoint("BOTTOMLEFT", pieces[3], "TOPLEFT")
    pieces[7]:SetWidth(edge)
    pieces[8]:SetPoint("TOPRIGHT", pieces[2], "BOTTOMRIGHT")
    pieces[8]:SetPoint("BOTTOMRIGHT", pieces[4], "TOPRIGHT")
    pieces[8]:SetWidth(edge)

    -- Repeat coords tile the edge art along its run, following
    -- BackdropTemplateMixin:SetupTextureCoordinates. The effective-scale factor
    -- Blizzard applies is deliberately dropped so a pattern tiles the same on
    -- every UI scale. Straight ramps (MSUF's own art) are uniform along that
    -- axis anyway, so the repeat is only visible on patterned Blizzard/LSM
    -- borders, where it is wanted.
    local repeatX = math_max(0, ((width + out * 2) / edge) - 2 - COORD_START)
    local repeatY = math_max(0, ((height + out * 2) / edge) - 2 - COORD_START)

    local u = EDGE_U[5]
    pieces[5]:SetTexCoord(u[1], repeatX, u[2], repeatX, u[1], COORD_START, u[2], COORD_START)
    u = EDGE_U[6]
    pieces[6]:SetTexCoord(u[1], repeatX, u[2], repeatX, u[1], COORD_START, u[2], COORD_START)
    u = EDGE_U[7]
    pieces[7]:SetTexCoord(u[1], COORD_START, u[1], repeatY, u[2], COORD_START, u[2], repeatY)
    u = EDGE_U[8]
    pieces[8]:SetTexCoord(u[1], COORD_START, u[1], repeatY, u[2], COORD_START, u[2], repeatY)

    -- When the band is at least as wide as the target (small icon, thick
    -- shadow), the corner pieces meet or overlap and the strips between them
    -- collapse to a non-positive run. Crossed anchors draw nothing, so hide
    -- those four regions outright instead of keeping degenerate quads alive.
    -- Unknown target size (width/height 0) keeps the strips: the anchors are
    -- target-relative and stay correct either way.
    local runX = width <= 0 or (width + out * 2) > (edge * 2)
    local runY = height <= 0 or (height + out * 2) > (edge * 2)
    for i = 1, 8 do
        pieces[i]:SetVertexColor(r or 1, g or 1, b or 1, a or 1)
    end
    for i = 1, 4 do pieces[i]:Show() end
    if runX then pieces[5]:Show(); pieces[6]:Show() else pieces[5]:Hide(); pieces[6]:Hide() end
    if runY then pieces[7]:Show(); pieces[8]:Show() else pieces[7]:Hide(); pieces[8]:Hide() end
end

function B.Hide(pieces)
    if not pieces then return end
    for i = 1, 8 do
        if pieces[i] then pieces[i]:Hide() end
    end
end

if type(MSUF.ExportPublic) == "function" then
    MSUF.ExportPublic("MSUF_BorderStyles", B)
else
    _G.MSUF_BorderStyles = B
end
