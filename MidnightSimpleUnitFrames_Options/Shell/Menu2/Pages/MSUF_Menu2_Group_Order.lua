-- Group order editor; shared scope and history remain in the foundation.
local _, MSUF = ...
local M = MSUF.MSUF2
local Parts = M.GroupPageParts
local GroupPage = M.GroupPage
local PixelLayoutRegion = Parts.PixelLayoutRegion
local W = Parts.W
local Schema = Parts.Schema
local T = Parts.T
local Shared = Parts.Shared
local floor = Parts.floor
local max = Parts.max
local GROWTH_VALUES = Parts.GROWTH_VALUES
local GroupControlMeta = Parts.GroupControlMeta
local RegisterGroupControl = Parts.RegisterGroupControl
local Conf = Parts.Conf
local Val = Parts.Val
local QueueGF = Parts.QueueGF
local Set = Parts.Set
local CurrentScope = Parts.CurrentScope

local GROWTH_TILE_VALUES = {
    { value = "DOWN", text = "Down", dx = 0, dy = -1, arrow = "v" },
    { value = "UP", text = "Up", dx = 0, dy = 1, arrow = "^" },
    { value = "RIGHT", text = "Right", dx = 1, dy = 0, arrow = ">" },
    { value = "LEFT", text = "Left", dx = -1, dy = 0, arrow = "<" },
}
-- Runs on every refresh of the growth tiles, so the cell order is computed inline (no helper call).
local function DrawGrowthMiniPreview(btn, info, raidLike, tileW, tileH)
    if not btn or not info then return end
    btn._cells = btn._cells or {}
    local vertical = info.dy ~= 0
    local cols, rows
    if raidLike then
        cols, rows = vertical and 4 or 5, vertical and 5 or 4
    else
        cols, rows = vertical and 1 or 5, vertical and 5 or 1
    end
    local pad = 5
    local labelH = 13
    local innerW = tileW - (pad * 2)
    local innerH = tileH - pad - labelH
    local cellGap = 1
    local cellW = max(3, floor((innerW - ((cols - 1) * cellGap)) / cols))
    local cellH = max(3, floor((innerH - ((rows - 1) * cellGap)) / rows))
    local gridW = (cols * cellW) + ((cols - 1) * cellGap)
    local gridH = (rows * cellH) + ((rows - 1) * cellGap)
    local originX = pad + floor((innerW - gridW) * 0.5 + 0.5)
    local originY = -pad - floor((innerH - gridH) * 0.5 + 0.5)
    -- Vertical growth fills columns top to bottom (UP from the bottom), horizontal growth fills rows
    -- left to right (LEFT from the right); the first cell is badged.
    local positions = {}
    local outer, inner = vertical and cols or rows, vertical and rows or cols
    local reversed
    if vertical then reversed = info.dy == 1 else reversed = info.dx == -1 end
    for o = 0, outer - 1 do
        for n = 0, inner - 1 do
            local i = reversed and (inner - 1 - n) or n
            positions[#positions + 1] = vertical and { col = o, row = i } or { col = i, row = o }
        end
    end
    for i = 1, #positions do
        local cell = btn._cells[i]
        if not cell then
            cell = PixelLayoutRegion(btn:CreateTexture(nil, "ARTWORK"))
            btn._cells[i] = cell
        end
        local pos = positions[i]
        cell:ClearAllPoints()
        cell:SetPoint("TOPLEFT", btn, "TOPLEFT", originX + (pos.col * (cellW + cellGap)), originY - (pos.row * (cellH + cellGap)))
        cell:SetSize(cellW, cellH)
        if i == 1 then
            cell:SetColorTexture(0.120, 0.950, 0.620, 0.98)
        elseif i <= 4 then
            cell:SetColorTexture(0.220, 0.580, 0.940, 0.78)
        else
            cell:SetColorTexture(0.160, 0.360, 0.640, 0.42)
        end
        cell:Show()
    end
    for i = #positions + 1, #btn._cells do
        btn._cells[i]:Hide()
    end
    W.EnsureTileFirstBadge(btn)
    local first = positions[1]
    if first then
        btn._firstText:ClearAllPoints()
        btn._firstText:SetPoint("CENTER", btn, "TOPLEFT",
            originX + (first.col * (cellW + cellGap)) + (cellW * 0.5),
            originY - (first.row * (cellH + cellGap)) - (cellH * 0.5))
        btn._firstText:Show()
    end
    W.PaintTileDirectionArrow(btn, info, labelH)
end
local function BuildGrowthDirectionTiles(ctx, section, opts)
    if not section then return nil end
    opts = opts or {}
    local x, y = opts.x or section._msuf2ContentX or 14, opts.y or section._msuf2CursorY or -38
    local tileW, tileH, gap = opts.tileWidth or 64, opts.tileHeight or 64, opts.gap or 6
    if opts.advanceCursor ~= false then section._msuf2CursorY = y - tileH - 40 end
    local label = Schema.Build(ctx, section, {
        { "font", "label", nil, { "GameFontNormalSmall", "Growth Direction", T.colors.accent }, scope = "group", domain = "layout",
            anchor = { "TOPLEFT", section, "TOPLEFT", x, y }, meta = GroupControlMeta(ctx, "growth.title") },
    }).label
    local holder = PixelLayoutRegion(CreateFrame("Frame", nil, section))
    holder:SetPoint("TOPLEFT", section, "TOPLEFT", x, y - 20)
    holder:SetSize((tileW * 4) + (gap * 3), tileH)
    holder._msuf2Label = label
    Schema.Custom(holder, { id = GroupControlMeta(ctx, "growth.tiles").controlId,
        kind = "growthTiles", labelKey = "Growth Direction", scope = "group", applyDomain = "layout", owner = holder })
    local buttons = {}
    local SetTileVisual = W.SetTileVisual
    local function RefreshGrowthTiles()
        local current = Val(CurrentScope(), "growth", "DOWN")
        local raidLike = CurrentScope() ~= "party"
        for i = 1, #GROWTH_TILE_VALUES do
            local info = GROWTH_TILE_VALUES[i]
            local btn = buttons[info.value]
            if btn then
                DrawGrowthMiniPreview(btn, info, raidLike, tileW, tileH)
                SetTileVisual(btn, current == info.value, btn.IsMouseOver and btn:IsMouseOver())
            end
        end
    end
    for i = 1, #GROWTH_TILE_VALUES do
        local info = GROWTH_TILE_VALUES[i]
        local btn = PixelLayoutRegion(CreateFrame("Button", nil, holder, T.Template and T.Template() or nil))
        btn:SetSize(tileW, tileH)
        btn:SetPoint("TOPLEFT", holder, "TOPLEFT", (i - 1) * (tileW + gap), 0)
        if btn.SetBackdrop then
            PixelLayoutRegion(btn, "SetBackdrop", {
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
            })
        end
        local text = PixelLayoutRegion(btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
        if text.SetFont then text:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", T.FontSize("micro"), "OUTLINE") end
        text:SetPoint("BOTTOM", btn, "BOTTOM", 0, 3)
        text:SetText(M.Tr(info.text))
        btn._label = text
        btn:SetScript("OnEnter", function(self)
            SetTileVisual(self, Val(CurrentScope(), "growth", "DOWN") == info.value, true)
        end)
        btn:SetScript("OnLeave", function(self)
            SetTileVisual(self, Val(CurrentScope(), "growth", "DOWN") == info.value, false)
        end)
        M.AddTooltip(btn, function() return M.Format("Growth: %s", M.Tr(info.text or "")) end, "Click to set group frame growth direction.",
            { hook = true, titleAsLine = true, bodyColor = { 0.72, 0.76, 0.86 } })
        btn:SetScript("OnClick", function(self)
            self._msuf2RuntimeControlRecord.command.set(info.value)
        end)
        RegisterGroupControl(btn, ctx, "field.growth.option." .. info.value, M.Format("Growth: %s", M.Tr(info.text)), "button", "setting", {
            searchSettingKeys = { "gf_party.growth", "gf_raid.growth", "gf_mythicraid.growth" },
            command = {
                kind = "dropdown", valueKind = "enum", values = GROWTH_VALUES,
                get = function() return Val(CurrentScope(), "growth", "DOWN") end,
                write = { call = Set, group = true, args = { "geometry" }, after = RefreshGrowthTiles }, --[[schema setter: Group.8]]
            },
        })
        Schema.Owned(btn, "group", "geometry")
        buttons[info.value] = btn
    end
    M.TrackRefresh(ctx, RefreshGrowthTiles)
    return holder
end
local ROLE_SORT_DEFS = {
    { key = "TANK", label = "Tank", r = 0.30, g = 0.55, b = 0.85 },
    { key = "HEALER", label = "Healer", r = 0.20, g = 0.72, b = 0.35 },
    { key = "DAMAGER", label = "DPS", r = 0.82, g = 0.30, b = 0.30 },
}
local ROLE_SORT_BY_KEY = {}
for i = 1, #ROLE_SORT_DEFS do
    ROLE_SORT_BY_KEY[ROLE_SORT_DEFS[i].key] = i
end
local ROLE_SORT_VALUES = {
    { value = "TANK,HEALER,DAMAGER", text = "Tank, Healer, DPS" },
    { value = "TANK,DAMAGER,HEALER", text = "Tank, DPS, Healer" },
    { value = "HEALER,TANK,DAMAGER", text = "Healer, Tank, DPS" },
    { value = "HEALER,DAMAGER,TANK", text = "Healer, DPS, Tank" },
    { value = "DAMAGER,TANK,HEALER", text = "DPS, Tank, Healer" },
    { value = "DAMAGER,HEALER,TANK", text = "DPS, Healer, Tank" },
}
local function NormalizeRoleOrder(value)
    if type(value) ~= "string" then return nil end
    local parts, seen = {}, {}
    for token in value:gmatch("[^,]+") do
        token = token:match("^%s*(.-)%s*$"):upper()
        if token == "MELEE" or token == "RANGED" then token = "DAMAGER" end
        if not ROLE_SORT_BY_KEY[token] or seen[token] then return nil end
        seen[token], parts[#parts + 1] = true, token
    end
    if #parts ~= #ROLE_SORT_DEFS then return nil end
    return table.concat(parts, ",")
end
local function BuildRoleOrderRows(ctx, section, opts)
    if not section then return nil end
    opts = opts or {}
    local rowW, rowH, rowGap = opts.width or 220, 22, 4
    local x = opts.x or section._msuf2ContentX or 14
    local y = opts.y or section._msuf2CursorY or -146
    local listY = y
    if opts.hint or opts.title then
        Schema.Build(ctx, section, {
            { "font", "title", nil, { "GameFontNormalSmall", opts.title or "Role Priority", T.colors.text },
                anchor = { "TOPLEFT", section, "TOPLEFT", x, y },
                meta = GroupControlMeta(ctx, "sorting.title"), scope = "group", domain = "layout",
                beforeBind = function(widget)
                    widget:SetWidth(rowW)
                    widget:SetJustifyH("LEFT")
                end },
            { "font", "hint", nil, { "GameFontDisableSmall", opts.hint or "Drag roles to reorder.", T.colors.dim },
                anchor = { "TOPLEFT", section, "TOPLEFT", x, y - 16 },
                meta = GroupControlMeta(ctx, "sorting.hint"), scope = "group", domain = "layout",
                beforeBind = function(widget)
                    widget:SetWidth(rowW + 80)
                    widget:SetJustifyH("LEFT")
                end },
        })
        listY = y - 38
    end
    if opts.advanceCursor ~= false then section._msuf2CursorY = listY - (#ROLE_SORT_DEFS * (rowH + rowGap)) - 10 end
    local function NormalizeRoleToken(token)
        if token == "MELEE" or token == "RANGED" then return "DAMAGER" end
        return token
    end
    local holder, rows
    local function CurrentRoleOrder()
        local conf = Conf(CurrentScope())
        return NormalizeRoleOrder(conf.roleOrder) or "TANK,HEALER,DAMAGER"
    end
    local function ApplyRoleOrder(value)
        value = NormalizeRoleOrder(value)
        if not value then return false end
        local kind = CurrentScope()
        Conf(kind).roleOrder = value
        QueueGF(kind, "rebuild")
        return true
    end
    local function SaveOrder()
        local kind = CurrentScope()
        local function WriteOrder()
            local ordered = {}
            for i = 1, #rows do ordered[#ordered + 1] = rows[i] end
            table.sort(ordered, function(a, b) return (a.slotIndex or 0) < (b.slotIndex or 0) end)
            local parts = {}
            for i = 1, #ordered do parts[#parts + 1] = ordered[i].key end
            ApplyRoleOrder(table.concat(parts, ","))
        end
        M.RunWithHistory("Role Priority Order", "group:roleOrder:" .. tostring(kind), WriteOrder)
    end
    local function LoadOrder()
        local order = CurrentRoleOrder()
        local slot = 0
        local assigned = {}
        for token in order:gmatch("[^,]+") do
            token = NormalizeRoleToken(token)
            local index = ROLE_SORT_BY_KEY[token]
            if index and not assigned[index] then
                slot = slot + 1
                rows[index].slotIndex = slot
                assigned[index] = true
            end
        end
        for i = 1, #rows do
            if not assigned[i] then
                slot = slot + 1
                rows[i].slotIndex = slot
            end
        end
        holder:SnapRows()
    end
    holder = Shared.MakeDragSortRows(section, ROLE_SORT_DEFS, {
        x = x, y = listY, width = rowW, rowHeight = rowH, gap = rowGap,
        controlDomain = "group",
        controlPageKey = ctx and ctx.key,
        controlPath = "sorting.role_priority",
        controlClassification = "setting",
        searchSettingKeys = { "gf_party.roleOrder", "gf_raid.roleOrder", "gf_mythicraid.roleOrder" },
        controlCommand = {
            kind = "dragrow",
            source = "group/sorting/role_priority",
            valueKind = "enum",
            values = ROLE_SORT_VALUES,
            get = CurrentRoleOrder,
            customSetReason = "Executes the existing composite command, conversion or selection-dependent policy.",
            write = { source = function() return Conf(CurrentScope()) end,
                resolve = function() return "gf_" .. CurrentScope() .. ".roleOrder" end,
                accept = function(value) return NormalizeRoleOrder(value) ~= nil end, refused = false,
                convert = NormalizeRoleOrder, success = true,
                after = function()
                    QueueGF(CurrentScope(), "rebuild")
                    if holder and holder.Refresh then holder.Refresh() end
                end
            } --[[schema setter: H4.Group.RoleOrder]],
            canExecute = function()
                local scope = CurrentScope()
                return scope == "party" or scope == "raid" or scope == "mythicraid"
            end,
        },
        onReorder = SaveOrder,
        tooltip = function(self, row, tip)
            tip:SetOwner(self, "ANCHOR_RIGHT")
            tip:AddLine(M.Tr((row and row.def and row.def.label) or ""), 1, 1, 1)
            tip:AddLine(M.Tr("Drag to change role priority."), 0.72, 0.76, 0.86)
            tip:Show()
        end,
    })
    rows = holder.rows
    for _, row in ipairs(rows) do Schema.Owned(row.frame, "group", "rebuild") end
    holder.Refresh = LoadOrder
    M.TrackRefresh(ctx, LoadOrder)
    holder:SetRowsEnabled(false)
    return holder
end

GroupPage.BuildGrowthDirectionTiles = BuildGrowthDirectionTiles
GroupPage.BuildRoleOrderRows = BuildRoleOrderRows
