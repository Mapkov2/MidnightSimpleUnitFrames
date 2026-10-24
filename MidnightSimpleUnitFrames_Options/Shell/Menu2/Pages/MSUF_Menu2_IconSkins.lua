local _, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", "Menu2/IconSkins")

-- Style > Icon Skins is the ONE place where icon skins are chosen: the default
-- skin and look (auras3.shared.iconSkinDefault), a live strip of every icon
-- type, the gallery, and where each icon type's skin comes from (Like default,
-- No skin or its own): MSUF's aura types, then the areas other modules (the
-- Suite's Cooldown Manager and action bars) register with Page.RegisterArea.
-- Other pages show only a status row with a link here (Page.StatusRow). The
-- engine (Auras3/MSUF_Auras3_IconSkins.lua) owns the aura data and its combat
-- snapshot; every write runs the normal aura apply, so a change made in combat
-- shows when combat ends.
local A3 = MSUF.MSUF_Auras3
local Model = A3 and A3.MenuModel
local W, T = M.Widgets, M.Theme
if not (Model and W and T and M.AuraControls) then return end

local floor, ceil, max, min, tonumber = math.floor, math.ceil, math.max, math.min, tonumber
local BindSwitch, BindSlider, BindDropdown = M.BindSwitchAt, M.BindSliderAt, M.BindDropdownAt
local RequestAuraRuntime = M.AuraControls.RequestAuraRuntime

local PAGE = "icon_skins"
local CUSTOM, DEFAULT, RECTANGLE, FOLLOW_PORTRAIT = "CUSTOM", "DEFAULT", "RECTANGLE", "FOLLOW_PORTRAIT"
local SKIN_COLOR_DEFAULT = { 0, 0, 0, 1 }
local GLOSS_COLOR_DEFAULT = { 1, 1, 1, 0.12 }
local GALLERY_ICON = "Interface\\Icons\\Spell_Holy_PowerWordShield"
local TILE, TILE_STEP, SAMPLE = 32, 42, 36
local PRODUCTS = {
    { kind = "buff", label = "Buffs", icon = "Interface\\Icons\\Spell_Holy_WordFortitude" },
    { kind = "debuff", label = "Debuffs", icon = "Interface\\Icons\\Spell_Shadow_ShadowWordPain" },
    { kind = "playerDefensives", label = "Player Defensives", icon = "Interface\\Icons\\Spell_Holy_PowerWordShield" },
    { kind = "targetDots", label = "Dots on Target", icon = "Interface\\Icons\\Spell_Shadow_AbominationExplosion" },
}
local FAMILIES = { "ALL", "Shadow", "Dark", "Frame", "Metal", "Pixel", "Glass", "Round", "Blizzard" }
-- Unset follows each skin's own gloss default, so the control has three states.
local GLOSS_VALUES = { { value = "AUTO", text = "Skin default" }, { value = "ON", text = "On" },
    { value = "OFF", text = "Off" } }
local SEARCH_KEYWORDS = { "masque", "skin", "skins", "icon skin", "icon skins", "icon border", "button skin" }

-- The path's middle segments name the search breadcrumb (the section title).
local function Meta(path, classification)
    local identity = "icon_skins." .. path
    return {
        controlId = "menu2." .. PAGE .. "." .. identity,
        pageKey = PAGE,
        identityKey = identity,
        controlPath = "icon_skins/" .. path:gsub("%.", "/"),
        classification = classification or "setting",
    }
end

-------------------------------------------------------------------------------
--  Page: the shared reads and writes (also used by the Aura Appearance rows).
-------------------------------------------------------------------------------

local Page = { PAGE = PAGE, PRODUCTS = PRODUCTS }
M.IconSkinsPage = Page

-- The core always loads the skin engine before the menu. A headless page build
-- that skips it (the search index harness) sees no skins: only No skin.
local NO_SKINS = {
    List = function() return { { value = CUSTOM, text = "No skin (your border and shadow)" } } end,
    Normalize = function() return CUSTOM end,
    Get = function() return nil end,
    ShapeOf = function() return RECTANGLE end,
    ReadDefault = function(_, fallback) return fallback end,
    WriteDefault = function() return false end,
    AttachPreview = function(style) return style end,
}
local function Skins() return A3.IconSkins or NO_SKINS end

function Page.Read(key, fallback)
    return Skins().ReadDefault(key, fallback)
end

function Page.Color(key, default)
    local c = Page.Read(key, default)
    return type(c) == "table" and c or default
end

--- The look every skin is drawn with (the Icon Skins page edits it).
function Page.Look()
    return {
        styleSkinColor = Page.Color("styleSkinColor", SKIN_COLOR_DEFAULT),
        styleSkinColorOverride = Page.Read("styleSkinColorOverride", false),
        styleSkinGloss = Page.Read("styleSkinGloss", nil),
        styleSkinGlossColor = Page.Color("styleSkinGlossColor", GLOSS_COLOR_DEFAULT),
    }
end

function Page.DefaultSkin()
    return Skins().Normalize(Page.Read("styleSkin", CUSTOM))
end

-- Rows of "Where It Applies" beyond MSUF's aura types, in registration order.
local areas, areaByKey = {}, {}

--- Adds an icon type of another module (the Suite) to "Where It Applies". spec:
---   key    unique id (never an aura kind)
---   group  header the row sits under ("Cooldown Manager"), menu text
---   label  row text ("Essential"), menu text
---   order  optional order inside the group
---   read   function() -> "DEFAULT" (Like default), "CUSTOM" (No skin) or a skin id
---   write  function(value): stores and applies the choice
---   shape  optional function() -> the icon shape these icons have (RECTANGLE)
---   setShape optional function(shape): a skin for another shape sets it, as for
---          auras; without it the row offers only skins drawn on its shape
---   refresh optional function(reason): runs after any change on this page (the
---          default skin or look changed), so the module repaints its icons
---   icon   optional texture: the row also gets a sample in "Your Icons"
---   available optional function() -> true, or false and a reason the caller
---          has already translated: while it is false the row is greyed out
---          with that reason and the status row shows it (the module that
---          draws these icons is off, for example)
--- Returns true when the row was added.
function Page.RegisterArea(spec)
    if not (spec and spec.key and spec.group and spec.label and spec.read and spec.write) then return false end
    if areaByKey[spec.key] then return false end
    for i = 1, #PRODUCTS do
        if PRODUCTS[i].kind == spec.key then return false end
    end
    areas[#areas + 1] = spec
    areaByKey[spec.key] = spec
    if M.InvalidatePage then M.InvalidatePage(PAGE) end
    return true
end

--- DEFAULT, CUSTOM or an available skin id, for an aura kind or an area key.
function Page.ProductSkin(key)
    local area, value = areaByKey[key], nil
    if area then value = area.read() else value = Model.ReadSharedAppearanceValue(key, "styleSkin", DEFAULT) end
    if value == nil or value == DEFAULT then return DEFAULT end
    return Skins().Normalize(value)
end

function Page.EffectiveSkin(key)
    local own = Page.ProductSkin(key)
    if own == DEFAULT then return Page.DefaultSkin() end
    return own
end

function Page.SkinName(id)
    if id == CUSTOM then return M.Tr("No skin (your border and shadow)") end
    local def = Skins().Get(id)
    return def and M.Tr(def.text or def.id) or M.Tr("No skin (your border and shadow)")
end

function Page.ProductShape(key)
    local area = areaByKey[key]
    if area then return area.shape and area.shape() or RECTANGLE end
    return Model.ReadSharedAppearanceIconShape and Model.ReadSharedAppearanceIconShape(key) or RECTANGLE
end

local function Fits(shape, wanted)
    return shape == wanted or (wanted == RECTANGLE and shape == FOLLOW_PORTRAIT)
end

--- A skin made for a round, rounded or hex icon sets that shape; a square skin
--- replaces a fixed shape it cannot draw on (Follow Portrait stays: a square
--- portrait shows the skin). An area without setShape keeps its shape.
function Page.MatchShape(key, id)
    if id == CUSTOM then return end
    local area = areaByKey[key]
    local write = area and area.setShape or (not area and Model.WriteSharedAppearanceIconShape)
    if not write then return end
    local shape, wanted = Page.ProductShape(key), Skins().ShapeOf(id)
    if Fits(shape, wanted) then return end
    if area then write(wanted) else write(key, wanted) end
end

--- True while the effective skin draws these icons (its shape matches).
function Page.SkinDraws(key)
    local skin = Page.EffectiveSkin(key)
    return skin ~= CUSTOM and Fits(Page.ProductShape(key), Skins().ShapeOf(skin))
end

local refreshers = setmetatable({}, { __mode = "k" })
function Page.OnChange(owner, fn) refreshers[owner] = fn end

function Page.Apply(reason)
    reason = reason or "AURAS3_ICON_SKIN"
    RequestAuraRuntime("shared", reason)
    local apply = M.ApplyService
    if apply and apply.Flush then apply.Flush() end
    for i = 1, #areas do
        if areas[i].refresh then areas[i].refresh(reason) end
    end
    for _, fn in pairs(refreshers) do fn() end
end

--- Every icon type, aura kinds first, then the registered areas.
function Page.Keys()
    local keys = {}
    for i = 1, #PRODUCTS do keys[i] = PRODUCTS[i].kind end
    for i = 1, #areas do keys[#keys + 1] = areas[i].key end
    return keys
end

function Page.SelectDefault(id)
    Skins().WriteDefault("styleSkin", id)
    local keys = Page.Keys()
    for i = 1, #keys do
        if Page.ProductSkin(keys[i]) == DEFAULT then Page.MatchShape(keys[i], id) end
    end
    Page.Apply("AURAS3_ICON_SKIN")
end

function Page.SelectProduct(key, id)
    local area = areaByKey[key]
    if area then area.write(id) else Model.WriteSharedAppearanceValue(key, "styleSkin", id) end
    Page.MatchShape(key, id == DEFAULT and Page.DefaultSkin() or id)
    Page.Apply("AURAS3_ICON_SKIN")
end

--- Dropdown items for one icon type: Like default, No skin, then every skin
--- (an area that cannot change its shape gets only the skins drawn on it).
function Page.ProductValues(key)
    local items = { { value = DEFAULT, text = M.Format("Like default (%s)", Page.SkinName(Page.DefaultSkin())),
        translate = false } }
    local list, area = Skins().List(), key and areaByKey[key]
    local shape = area and not area.setShape and Page.ProductShape(key) or nil
    for i = 1, #list do
        local item = list[i]
        if not shape or item.value == CUSTOM or Fits(shape, Skins().ShapeOf(item.value)) then items[#items + 1] = item end
    end
    return items
end

function Page.Open()
    if M.SelectPage then M.SelectPage(PAGE) end
end

--- Paints `icon` (texture icon.tex) as `key` shows it: an aura type with its
--- own border and shadow (the Aura Appearance settings), an area with its
--- skin; or the bare `skinId`.
function Page.PaintSample(icon, key, size, skinId)
    if not (A3.IconShape and A3.ApplyIconStyleSkinned) then return end
    local shape = skinId and Skins().ShapeOf(skinId) or Page.ProductShape(key)
    if shape == FOLLOW_PORTRAIT then shape = RECTANGLE end
    A3.IconShape.ApplyIconShape(icon, shape, nil, false, icon.tex)
    local style, auras = nil, M.AurasPage
    if not skinId and not areaByKey[key] then
        style = auras and auras.ProductIconStyle and auras.ProductIconStyle(key) or nil
    else
        local id = skinId or Page.EffectiveSkin(key)
        style = id ~= CUSTOM and Skins().AttachPreview({}, { styleSkin = id }, Page.Look()) or nil
    end
    A3.ApplyIconStyleSkinned(icon, style, size, shape)
end

--- Whether an area's icons can show a skin now (spec.available; aura kinds and
--- areas without it always can), and the caller's reason when they cannot.
function Page.AreaAvailable(key)
    local area = areaByKey[key]
    if not (area and area.available) then return true end
    local ok, reason = area.available()
    if ok then return true end
    return false, reason
end

--- The row another page shows instead of skin settings of its own: the skin
--- `key` (an aura type or an area) shows, what that does, and the button to
--- this page. `key` may be a function returning the key, read at every refresh
--- (one row that follows a page's own selector). Refreshes with the host page.
--- Returns its height, the button and the two text lines.
Page.STATUS_ROW_KEY_FUNCTION = true
function Page.StatusRow(ctx, parent, x, y, width, key)
    local value = W.Text(parent, "", x, y, max(160, width - 196), T.colors.text)
    local hint = W.Text(parent, "", x, y - 20, max(160, width - 196), T.colors.muted)
    local open = W.Button(parent, "Open Icon Skins", 180)
    open:ClearAllPoints()
    open:SetPoint("TOPLEFT", parent, "TOPLEFT", x + max(176, width - 180), y - 2)
    open:SetScript("OnClick", Page.Open)
    local function Refresh()
        local current = key
        if type(current) == "function" then current = current() end
        local own, skin = Page.ProductSkin(current), Page.EffectiveSkin(current)
        local name = skin == CUSTOM and M.Tr("No skin") or Page.SkinName(skin)
        T.SetTranslatedText(value, M.Format(own == DEFAULT and "Skin: %s, like the default" or "Skin: %s", name))
        local text
        local available, reason = Page.AreaAvailable(current)
        if not available and reason then
            text = reason
        elseif skin == CUSTOM then
            text = M.Tr("These icons keep their own border and shadow. Skins are chosen on the Icon Skins page.")
        elseif Page.SkinDraws(current) then
            text = M.Tr("The skin draws the border of these icons. Skins are chosen on the Icon Skins page.")
        else
            text = M.Tr("This skin is made for another icon shape, so these icons keep their own border and shadow.")
        end
        T.SetTranslatedText(hint, text)
    end
    M.TrackRefresh(ctx, Refresh)
    return 48, open, value, hint
end

-------------------------------------------------------------------------------
--  Sections
-------------------------------------------------------------------------------

local function NewIcon(parent, texture, size, x, y, button)
    local icon = PixelLayoutRegion(CreateFrame(button and "Button" or "Frame", nil, parent))
    icon:SetSize(size, size)
    icon:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    icon.tex = PixelLayoutRegion(icon:CreateTexture(nil, "ARTWORK"))
    icon.tex:SetAllPoints(icon)
    icon.tex:SetTexture(texture)
    icon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    return icon
end

local function StripEntries()
    local entries = {}
    for i = 1, #PRODUCTS do entries[i] = { key = PRODUCTS[i].kind, label = PRODUCTS[i].label, icon = PRODUCTS[i].icon } end
    for i = 1, #areas do
        if areas[i].icon then entries[#entries + 1] = { key = areas[i].key, label = areas[i].label, icon = areas[i].icon } end
    end
    return entries
end

local function BuildStrip(P, b)
    local entries = StripEntries()
    local estimate = b.width or 720
    local perRow = max(1, min(#entries, floor((estimate - 48) / 120)))
    local section = b:CollapsibleSection("icon_skins_strip", "Your Icons", 16 + ceil(#entries / perRow) * 84, true)
    local width = section._msuf2Width or estimate
    local step = max(120, floor((width - 48) / perRow))
    P.samples = {}
    for i, entry in ipairs(entries) do
        local x, y = 24 + ((i - 1) % perRow) * step, -16 - floor((i - 1) / perRow) * 84
        local icon = NewIcon(section, entry.icon, SAMPLE, x, y)
        icon.kind = entry.key
        icon.label = W.Text(section, entry.label, x - 8, y - 44, step - 8, T.colors.text)
        icon.skin = W.Text(section, "", x - 8, y - 60, step - 8, T.colors.muted)
        P.samples[i] = icon
    end
    function P.RefreshStrip()
        for i = 1, #P.samples do
            local icon = P.samples[i]
            Page.PaintSample(icon, icon.kind, SAMPLE)
            local own = Page.ProductSkin(icon.kind)
            local name = Page.SkinName(Page.EffectiveSkin(icon.kind))
            T.SetTranslatedText(icon.skin, own == DEFAULT and M.Format("Like default (%s)", name) or name)
        end
    end
end

local function AlphaSlider(P, section, label, x, y, width, key, default, reason)
    local slider
    slider = BindSlider(P.ctx, section, label, x, y, 0, 100, 1, width,
        function() return floor(((tonumber(Page.Color(key, default)[4]) or default[4]) * 100) + 0.5) end,
        function(value)
            local c = Page.Color(key, default)
            Skins().WriteDefault(key, { c[1] or default[1], c[2] or default[2], c[3] or default[3],
                (tonumber(value) or 100) / 100 })
            P.Queue(slider, reason)
        end,
        Meta("default-skin." .. key:lower() .. "-alpha"))
    slider:HookScript("OnMouseUp", P.Flush)
    slider:HookScript("OnHide", P.Flush)
    return slider
end

local function ColorTarget(label, historyLabel, key, default, reason)
    return {
        label = label,
        historyLabel = historyLabel,
        getRGB = function()
            local c = Page.Color(key, default)
            return c[1] or default[1], c[2] or default[2], c[3] or default[3]
        end,
        setRGB = function(r, g, b)
            Skins().WriteDefault(key, { r, g, b, Page.Color(key, default)[4] or default[4] })
            Page.Apply(reason)
        end,
        defaultR = default[1], defaultG = default[2], defaultB = default[3],
    }
end

local function BuildLook(P, section, width, top)
    local ctx, col = P.ctx, max(140, floor((width - 68) / 2))
    local gloss = BindDropdown(ctx, section, "Gloss", 24, top, GLOSS_VALUES, col,
        function()
            local value = Page.Read("styleSkinGloss", nil)
            if value == nil then return "AUTO" end
            return value == true and "ON" or "OFF"
        end,
        function(value)
            local gloss
            if value == "ON" then gloss = true elseif value == "OFF" then gloss = false end
            Skins().WriteDefault("styleSkinGloss", gloss)
            Page.Apply("AURAS3_ICON_SKIN_GLOSS")
        end,
        Meta("default-skin.gloss"))
    if M.AuraControls.AddTooltip then
        M.AuraControls.AddTooltip(gloss, "Skin gloss",
            "Draws the skin's highlight above the cooldown swipe. Strength sets how bright it is.")
    end
    AlphaSlider(P, section, "Gloss Strength (%)", 34 + col, top + 4, col, "styleSkinGlossColor",
        GLOSS_COLOR_DEFAULT, "AURAS3_ICON_SKIN_GLOSS_COLOR")
    AlphaSlider(P, section, "Skin Alpha (%)", 24, top - 56, col, "styleSkinColor", SKIN_COLOR_DEFAULT,
        "AURAS3_ICON_SKIN_COLOR")
    local own = BindSwitch(ctx, section, "Use Own Color", 34 + col, top - 60, col,
        function() return Page.Read("styleSkinColorOverride", false) == true end,
        function(value)
            Skins().WriteDefault("styleSkinColorOverride", value == true)
            Page.Apply("AURAS3_ICON_SKIN_COLOR")
        end,
        Meta("default-skin.own-color"))
    if M.AuraControls.AddTooltip then
        M.AuraControls.AddTooltip(own, "Own skin color",
            "Paints the skin's frames, metal and rings in the Skin Color from the three dots instead of their own colours. Shadows keep theirs.")
    end
    if W.AttachContextColorShortcut then
        W.AttachContextColorShortcut(section, {
            title = "Icon Skin Colors",
            scopeTag = "Shared",
            historySource = "menu:icon-skins-color",
            getTargets = function()
                return {
                    ColorTarget("Skin Color", "Aura icon skin color", "styleSkinColor", SKIN_COLOR_DEFAULT, "AURAS3_ICON_SKIN_COLOR"),
                    ColorTarget("Gloss Color", "Aura icon gloss color", "styleSkinGlossColor", GLOSS_COLOR_DEFAULT,
                        "AURAS3_ICON_SKIN_GLOSS_COLOR"),
                }
            end,
        })
    end
end

local function NewTile(P, section, item)
    local tile = NewIcon(section, GALLERY_ICON, TILE, 0, 0, true)
    tile.skinId, tile.skinText, tile.family = item.value, item.text, item.family
    tile.translate = item.translate ~= false
    local accent = T.colors.accent or { 1, 0.82, 0.2 }
    tile.mark = PixelLayoutRegion(tile:CreateTexture(nil, "OVERLAY", nil, 7))
    tile.mark:SetTexture("Interface\\Buttons\\WHITE8X8")
    tile.mark:SetVertexColor(accent[1], accent[2], accent[3], 1)
    tile.mark:SetPoint("TOPLEFT", tile, "BOTTOMLEFT", 0, -5)
    tile.mark:SetPoint("TOPRIGHT", tile, "BOTTOMRIGHT", 0, -5)
    tile.mark:SetHeight(2)
    tile:SetScript("OnClick", function() P.Pick(tile.skinId) end)
    tile:SetScript("OnEnter", function() P.ShowName(tile) end)
    tile:SetScript("OnLeave", function() P.ShowName(nil) end)
    return tile
end

local function BuildGallery(P, section, width, top)
    local ctx = P.ctx
    -- The gallery's keyboard route; search also finds every skin by its name.
    P.skinDropdown = BindDropdown(ctx, section, "Skin", 24, top, function() return Skins().List() end, width - 48,
        Page.DefaultSkin, Page.SelectDefault, Meta("default-skin.skin"))
    -- A tile picks through the dropdown: one undo entry, the combat block and
    -- the shown value, exactly as a pick from the list.
    function P.Pick(id)
        local pick = P.skinDropdown and P.skinDropdown._msuf2OnValueChanged
        if pick then pick(id) else Page.SelectDefault(id) end
    end
    top = top - 56
    local values = {}
    for i = 1, #FAMILIES do
        local family = FAMILIES[i]
        values[i] = { value = family, text = family == "ALL" and "All" or family }
    end
    local filter = W.Segment(section, "Family", values, width - 48)
    if W.MoveWidget then W.MoveWidget(filter, section, 24, top, width - 48) end
    M.BindSegment(ctx, filter, function() return P.family end, function(value)
        P.family = value
        P.LayoutTiles()
    end, Meta("default-skin.family", "ephemeral"))
    P.name = W.Text(section, "", 24, top - 54, width - 48, T.colors.text)
    local list = Skins().List()
    P.tiles, P.perRow = {}, max(6, floor((width - 56) / TILE_STEP))
    for i = 1, #list do P.tiles[i] = NewTile(P, section, list[i]) end
    local first = top - 78
    function P.LayoutTiles()
        local n = 0
        for i = 1, #P.tiles do
            local tile = P.tiles[i]
            local shown = P.family == "ALL" or tile.skinId == CUSTOM or tile.family == P.family
            tile:SetShown(shown)
            if shown then
                local col, row = n % P.perRow, floor(n / P.perRow)
                tile:ClearAllPoints()
                tile:SetPoint("TOPLEFT", section, "TOPLEFT", 28 + col * TILE_STEP, first - row * TILE_STEP)
                n = n + 1
            end
        end
    end
    function P.ShowName(tile)
        if tile then
            if tile.translate then P.name:SetText(M.Tr(tile.skinText or "")) else T.SetTranslatedText(P.name, tile.skinText or "") end
            return
        end
        T.SetTranslatedText(P.name, M.Format("Default skin: %s", Page.SkinName(Page.DefaultSkin())))
    end
    function P.RefreshGallery()
        if not (A3.IconShape and A3.ApplyIconStyleSkinned) then return P.ShowName(nil) end
        local selected, look = Page.DefaultSkin(), Page.Look()
        for i = 1, #P.tiles do
            local tile = P.tiles[i]
            local shape = Skins().ShapeOf(tile.skinId)
            A3.IconShape.ApplyIconShape(tile, shape, nil, false, tile.tex)
            local style = tile.skinId ~= CUSTOM and Skins().AttachPreview({}, { styleSkin = tile.skinId }, look) or nil
            A3.ApplyIconStyleSkinned(tile, style, TILE, shape)
            tile.mark:SetShown(tile.skinId == selected)
        end
        P.ShowName(nil)
    end
    P.LayoutTiles()
    return first - floor((#list + P.perRow - 1) / P.perRow) * TILE_STEP
end

local function BuildDefault(P, b)
    local estimate = b.width or 720
    local perRow = max(6, floor((estimate - 56) / TILE_STEP))
    local rows = floor((#Skins().List() + perRow - 1) / perRow)
    local height = 294 + rows * TILE_STEP
    local section = b:CollapsibleSection("icon_skins_default", "Default Skin", height, true)
    local width = section._msuf2Width or b.width or 720
    W.Text(section, "Pick one skin for all your icons. Round, rounded and hex skins also set the icon shape.",
        24, -16, width - 48, T.colors.muted)
    local bottom = BuildGallery(P, section, width, -40)
    BuildLook(P, section, width, bottom - 16)
end

--- The groups of "Where It Applies": MSUF's aura types, then each module's
--- areas under their own header, ordered by spec.order.
local function AreaGroups()
    local first = { title = "Auras", rows = {} }
    for i = 1, #PRODUCTS do first.rows[i] = { key = PRODUCTS[i].kind, label = PRODUCTS[i].label } end
    local groups, byTitle = { first }, {}
    for i = 1, #areas do
        local spec = areas[i]
        local group = byTitle[spec.group]
        if not group then
            group = { title = spec.group, rows = {} }
            byTitle[spec.group] = group
            groups[#groups + 1] = group
        end
        group.rows[#group.rows + 1] = { key = spec.key, label = spec.label, order = spec.order or i }
    end
    for i = 2, #groups do table.sort(groups[i].rows, function(a, c) return a.order < c.order end) end
    return groups
end

local function BuildAreaRow(P, section, row, y, width)
    local key = row.key
    local dropdown = BindDropdown(P.ctx, section, row.label, 24, y, function() return Page.ProductValues(key) end,
        max(260, width - 220), function() return Page.ProductSkin(key) end,
        function(value) Page.SelectProduct(key, value) end, Meta("where-it-applies." .. key:lower()))
    if M.AuraControls.AddTooltip then
        M.AuraControls.AddTooltip(dropdown, "Icon skin",
            "Like default follows the Icon Skins page. No skin keeps your own border and shadow. Changes made in combat apply when combat ends.")
    end
    local area = areaByKey[key]
    if area and area.available then
        W.SetControlDisabledReason(dropdown, function()
            local available, reason = Page.AreaAvailable(key)
            if available then return nil end
            return reason
        end)
        M.TrackRefresh(P.ctx, function() W.SetControlEnabled(dropdown, (Page.AreaAvailable(key))) end)
    end
end

local function BuildAreas(P, b)
    local groups, height = AreaGroups(), 72
    for i = 1, #groups do height = height + 28 + #groups[i].rows * 52 end
    local section = b:CollapsibleSection("icon_skins_areas", "Where It Applies", height, true)
    local width = section._msuf2Width or b.width or 720
    W.Text(section, "Like default follows the skin above. No skin keeps the icons' own border and shadow.",
        24, -16, width - 48, T.colors.muted)
    local y = -44
    for i = 1, #groups do
        W.Text(section, groups[i].title, 24, y, width - 48, T.colors.accent or T.colors.text)
        y = y - 28
        for j = 1, #groups[i].rows do
            BuildAreaRow(P, section, groups[i].rows[j], y, width)
            y = y - 52
        end
    end
    W.Text(section, "Changes made in combat apply when combat ends.", 24, y, width - 48, T.colors.muted)
end

local function NewPageState(ctx)
    local P = { ctx = ctx, family = "ALL" }
    -- Slider drags repaint the menu only; one runtime apply follows on release,
    -- or after a short pause for wheel and text input.
    function P.Queue(slider, reason)
        P.pending = reason
        if P.timer then P.timer:Cancel() end
        P.timer = nil
        if P.Refresh then P.Refresh() end
        if slider and slider._msuf2SliderActive then
            P.dragSlider = slider
            return
        end
        P.dragSlider = nil
        local timers = M.MenuTimer or C_Timer
        P.timer = timers.NewTimer(M.AURA_ICON_STYLE_APPLY_DELAY or 0.18, function()
            P.timer = nil
            P.Flush()
        end)
    end
    function P.Flush()
        if P.timer then P.timer:Cancel() end
        P.timer = nil
        local reason = P.pending
        P.pending = nil
        if reason then Page.Apply(reason) end
    end
    -- The menu timer drops its callback once the combat lock engages, and a
    -- menu hide cancels it; either leaves the apply pending. The page's OnHide
    -- and refresh hand it over, never under the combat lock. A refresh leaves
    -- a live timer (a menu task stays active until it runs) and a drag alone.
    function P.FlushStranded(onHide)
        if not P.pending or M.IsConfigCombatLocked() then return end
        if not onHide then
            local timer, drag = P.timer, P.dragSlider
            if timer and timer.active ~= false then return end
            if drag and drag._msuf2SliderActive then return end
        end
        P.Flush()
    end
    return P
end

local function BuildTrinketShape(P, b)
    if MSUF.Client.MaxArenaOpponents == 0 then return end
    local section = b:CollapsibleSection("icon_skins_trinket_shape", "PvP Trinket", 118, false)
    local function SetShape(value)
        M.ControlSchema.SetUnit("arenaTrinket", "arena", "trinketShape", value, "MSUF2_ARENA_TRINKET", "dropdown")
        M.RequestRefresh(P.ctx, "trinket-shape")
    end
    local meta = M.UnitPage.SettingMeta(P.ctx, "trinket_shape", "arena", "trinketShape")
    BindDropdown(P.ctx, section, "Icon Shape", 24, -20, M.IconShapeValues(), max(260, (b.width or 720) - 220),
        function() return M.UnitPage.GetConf("arena").trinketShape or RECTANGLE end, SetShape, meta)
    local reset = W.Button(section, "Reset section", 150)
    W.MoveWidget(reset, section, 24, -78)
    reset:SetScript("OnClick", function() SetShape(RECTANGLE) end)
end

local CAST_SHAPE_ROWS = {
    { unit = "player", label = "Player", prefix = "castbarPlayer", key = "castbarPlayerIconShape" },
    { unit = "target", label = "Target", prefix = "castbarTarget", key = "castbarTargetIconShape" },
    { unit = "focus", label = "Focus", prefix = "castbarFocus", key = "castbarFocusIconShape" },
    { unit = "boss", label = "Boss", prefix = "bossCast", key = "bossCastIconShape" },
    { unit = "arena", label = "Arena", prefix = "arenaCast", key = "arenaCastIconShape" },
}

local function CastShapeReason(row)
    local general = M.GetGeneralDB()
    local backend = MSUF.Castbars.Backend.Resolve(row.unit, general)
    if backend == "HIDE" then
        return M.Format("%s castbar is off. Turn it on to use the MSUF castbar.", M.Tr(row.label))
    end
    if backend ~= "MSUF" then
        return M.Format("%s castbar uses Blizzard. Select MSUF to adjust castbar layout and text behavior.", M.Tr(row.label))
    end
    if not MSUF.Castbars.Visuals.ShowIconForUnit(general, row.unit, row.prefix) then return M.Tr("Show icon") end
end

local function BuildCastbarShapes(P, b)
    local count = 0
    for _, row in ipairs(CAST_SHAPE_ROWS) do if MSUF.Client.SupportsUnit(row.unit) then count = count + 1 end end
    local section = b:CollapsibleSection("icon_skins_castbar_shapes", "Castbars", 52 + count * 60, false)
    local width, y = section._msuf2Width or b.width or 720, -20
    for _, row in ipairs(CAST_SHAPE_ROWS) do
        if MSUF.Client.SupportsUnit(row.unit) then
            local function SetShape(value)
                M.SetGeneralValue(row.key, value, "MSUF2_CASTBAR_ICON_SHAPE", { castbar = true, preview = true })
                M.RequestRefresh(P.ctx, "castbar-shape")
            end
            local meta = Meta("castbar_shape." .. row.unit)
            meta.settingKey, meta.scope = "general." .. row.key, row.unit
            meta.keywords = { "Castbar", "Icon Shape", row.label }
            local dropdown = BindDropdown(P.ctx, section, row.label, 24, y, M.IconShapeValues(), max(140, width - 220),
                function() return MSUF.Castbars.Visuals.IconShape(M.GetGeneralDB(), row.prefix) end, SetShape, meta)
            local reset = W.Button(section, "Reset section", 140)
            W.MoveWidget(reset, section, max(176, width - 164), y - 18)
            reset:SetScript("OnClick", function() SetShape(RECTANGLE) end)
            W.SetControlsDisabledReason({ dropdown, reset }, function() return CastShapeReason(row) end)
            M.TrackRefresh(P.ctx, M.BindGateGroup(P.ctx, nil, {
                { controls = { dropdown, reset }, on = function() return CastShapeReason(row) == nil end },
            }))
            y = y - 60
        end
    end
end

local function BuildFocusShape(P, b)
    if not MSUF.Client.SupportsUnit("focus") then return end
    local section = b:CollapsibleSection("icon_skins_focus_shape", "Focus interrupt tracker", 118, false)
    local function SetShape(value)
        if M.SetGeneralValue("focusKickIconShape", value, "MSUF2_FOCUS_KICK_SHAPE", { castbar = true, preview = true }) then
            local shared = M.GlobalPage
            shared.ScheduleCastbarPageWork("MSUF2_FOCUS_KICK_OPTIONS", shared.CASTBAR_PAGE_WORK_DELAY, function()
                MSUF.Require("MSUF_UpdateFocusKickIconOptions", "Menu2/IconSkins")()
            end)
        end
        M.RequestRefresh(P.ctx, "focus-kick-shape")
    end
    local meta = Meta("focus_kick_shape")
    meta.settingKey, meta.keywords = "general.focusKickIconShape", { "Focus interrupt tracker", "Icon Shape" }
    local dropdown = BindDropdown(P.ctx, section, "Icon Shape", 24, -20, M.IconShapeValues(), max(140, (b.width or 720) - 220),
        function() return A3.IconShape.Resolve(M.GetGeneralDB().focusKickIconShape) end, SetShape, meta)
    local reset = W.Button(section, "Reset section", 140)
    W.MoveWidget(reset, section, 24, -78)
    reset:SetScript("OnClick", function() SetShape(RECTANGLE) end)
    local function Enabled() return M.GetGeneralDB().enableFocusKickIcon == true end
    W.SetControlsDisabledReason({ dropdown, reset }, W.TurnOnReason("Focus interrupt tracker", Enabled))
    M.TrackRefresh(P.ctx, M.BindGateGroup(P.ctx, nil, { { controls = { dropdown, reset }, on = Enabled } }))
end

local function BuildIconSkins(ctx)
    local b = W.PageBuilder(ctx)
    b:GlobalStyleHeader("Icon Skins", #areas > 0 and "One look for all your icons. Each icon type follows it or keeps its own."
        or "One look for your aura icons. Each aura type follows it or keeps its own.", 72)
    local P = NewPageState(ctx)
    BuildStrip(P, b)
    BuildDefault(P, b)
    BuildAreas(P, b)
    BuildTrinketShape(P, b)
    BuildCastbarShapes(P, b)
    BuildFocusShape(P, b)
    function P.Refresh()
        P.RefreshStrip()
        P.RefreshGallery()
    end
    -- A change repaints the strip and gallery at once and resyncs the bound
    -- controls (the skin and per-type dropdowns, gloss) with the next refresh.
    Page.OnChange(P, function()
        P.Refresh()
        M.RequestRefresh(ctx, "icon-skins")
    end)
    Page.view = P
    P.Refresh()
    M.TrackRefresh(ctx, function()
        P.Refresh()
        P.FlushStranded(false)
    end)
    local wrapper = ctx.wrapper
    if wrapper and wrapper.HookScript then
        wrapper:HookScript("OnHide", function() P.FlushStranded(true) end)
    end
    ctx:SetContentHeight(math.abs(b.y) + 42)
end

M.RegisterPage(PAGE, { title = "Icon Skins", build = BuildIconSkins, version = 1 })

-- Search: the page also answers the names players know from other addons
-- ("masque"); a page row adds these words to the page's own record.
-- Every skin is a result of its own (its name in the menu language, the English
-- name as a keyword) that opens the Default Skin section, ranked like any other
-- control label: page keywords alone lose to other pages' labels ("Pixel").
if M.RegisterSearchProvider then
    M.RegisterSearchProvider("icon-skins", function()
        local rows, list = { { pageKey = PAGE, kind = "page", keywords = SEARCH_KEYWORDS } }, Skins().List()
        local section = M.Tr("Default Skin")
        for i = 2, #list do
            local name = list[i].text
            rows[#rows + 1] = { pageKey = PAGE, kind = "dropdown", label = M.Tr(name), section = section,
                keywords = { name }, sectionId = "icon_skins_default" }
        end
        return rows
    end)
end

-- Reset: the default skin and look, and every row of Where It Applies back to Like default.
if M.RegisterPageResetProvider then
    M.RegisterPageResetProvider("msuf_icon_skins", {
        pages = { [PAGE] = true },
        canReset = function() return true end,
        warning = function()
            return M.Tr("Resets the default icon skin and its look, and sets every row of Where It Applies back to Like default.")
        end,
        reset = function()
            local skins = Skins()
            skins.WriteDefault("styleSkin", CUSTOM)
            skins.WriteDefault("styleSkinColor", { 0, 0, 0, 1 })
            skins.WriteDefault("styleSkinColorOverride", false)
            skins.WriteDefault("styleSkinGloss", nil)
            skins.WriteDefault("styleSkinGlossColor", { 1, 1, 1, 0.12 })
            for i = 1, #PRODUCTS do Model.WriteSharedAppearanceValue(PRODUCTS[i].kind, "styleSkin", DEFAULT) end
            for i = 1, #areas do areas[i].write(DEFAULT) end
            return true
        end,
        finish = function() Page.Apply("AURAS3_ICON_SKIN_RESET") end,
    })
end
