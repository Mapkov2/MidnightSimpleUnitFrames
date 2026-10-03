-- Shared Aura controls and apply scheduling; no dependency on a page builder.
local _, MSUF = ...
MSUF = MSUF or {}
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", "Shell/Menu2/Pages/MSUF_Menu2_AuraControls.lua")
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local W, T = M.Widgets, M.Theme
local A3 = MSUF.MSUF_Auras3
local Model = A3 and A3.MenuModel
local VTP = M.ValueTextPairs
local C_Timer = M.MenuTimer or _G.C_Timer
local floor, max, min = math.floor, math.max, math.min
local tonumber, tostring, type, pairs = tonumber, tostring, type, pairs
local AurasMenuCombatLocked = M.AuraSettings.AurasMenuCombatLocked
local CurrentLane = M.AuraSettings.CurrentLane
local Round = M.AuraSettings.Round
local SetCurrentLane = M.AuraSettings.SetCurrentLane

local LANE_VALUES = VTP "buff=Buffs|debuff=Debuffs"

local AuraCatalogToken = M.AuraCatalogToken

local function AuraCatalogPageKey(value, fallback)
    local token = tostring(value or ""):lower():gsub("[^%w_%-]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
    return token ~= "" and token or (fallback or "auras")
end

local function AuraControlMeta(ctx, path, classification, routeContract)
    path = tostring(path or "control"):lower():gsub("[^%w%._/-]+", "-")
    path = path:gsub("/", "."):gsub("^%.+", ""):gsub("%.+$", "")
    local pageKey = AuraCatalogPageKey(ctx and ctx.key or M.activeKey, "auras")
    local identity = "auras." .. path
    local meta = {
        controlId = "menu2." .. pageKey .. "." .. identity,
        pageKey = pageKey,
        identityKey = identity,
        controlPath = "auras/" .. path:gsub("%.", "/"),
        classification = classification or "setting",
        ephemeral = classification == "ephemeral" or nil,
    }
    if type(routeContract) == "string" and routeContract ~= "" then
        meta.settingKey = routeContract
    elseif type(routeContract) == "table" then
        meta.settingKey = routeContract.settingKey
        meta.actionKey = routeContract.actionKey
        meta.actionFixedArgs = routeContract.actionFixedArgs
        meta.actionInputArg = routeContract.actionInputArg
        meta.searchSettingKeys = routeContract.searchSettingKeys
        meta.searchSettingKeyPatterns = routeContract.searchSettingKeyPatterns
    end
    return meta
end

local function AuraControlMetaAtVisiblePath(ctx, identityPath, visiblePath, classification, routeContract)
    local meta = AuraControlMeta(ctx, identityPath, classification, routeContract)
    visiblePath = tostring(visiblePath or identityPath or "control"):lower():gsub("[^%w%._/-]+", "-")
    visiblePath = visiblePath:gsub("/", "."):gsub("^%.+", ""):gsub("%.+$", "")
    meta.controlPath = "auras/" .. visiblePath:gsub("%.", "/")
    return meta
end

local function RegisterAuraControl(ctx, widget, label, kind, path, classification, navigationKey)
    if not widget or type(M.RegisterSearchWidget) ~= "function" then return widget end
    local meta = AuraControlMeta(ctx, path, classification,
        type(navigationKey) == "table" and navigationKey or nil)
    meta.label = label
    meta.kind = kind
    if classification == "navigation" then
        meta.navigationKey = navigationKey
    elseif classification == "action" then
        if type(navigationKey) == "string" then meta.actionKey = navigationKey end
    end
    M.RegisterSearchWidget(widget, meta)
    return widget
end

local function RegisterAuraTextAction(ctx, widget, input, label, path, routeContract)
    if widget then
        widget._msuf2CommandAction = {
            kind = "button",
            valueKind = "text",
            set = function(value)
                value = tostring(value or "")
                if input and input.SetText then input:SetText(value) end
                local handler = type(widget.GetScript) == "function" and widget:GetScript("OnClick") or nil
                if type(handler) ~= "function" then return false end
                return handler(widget, "LeftButton", false)
            end,
        }
    end
    return RegisterAuraControl(ctx, widget, label, "button", path, "action", routeContract)
end

local function AddTooltip(widget, title, body)
    return M.AddTooltip(widget, title, body, {
        hook = true,
        titleAsLine = true,
        labelHit = true,
        labelHitWhenDisabled = true,
    })
end

local function AddAuraTooltipHelp(widget)
    return AddTooltip(widget, "Aura tooltip",
        M.Format("Controls this aura lane independently. Always / Out of Combat / Modifier / Never under %s affect only unit and group frames. Auras only reuse the selected Blizzard/MSUF look and cursor placement.",
            M.NavPath("opt_misc", "Unitframe tooltips")))
end

local function ActionButton(parent, label, width, role)
    if W.RoleButton then return W.RoleButton(parent, label, role or "normal", width or 90, 24) end
    if W.TopButton then return W.TopButton(parent, label, width or 90, 24) end
    local btn = T.Button(parent, label, width or 90, 24)
    if W.StyleTopActionButton then W.StyleTopActionButton(btn) end
    return btn
end

local Card = W.ThemedControlCard

local function Rebuild(ctx)
    -- Nested aura workspaces and pinned previews settle their final height after
    -- the page is selected; the shared helper reapplies the viewport for us.
    local key = (ctx and ctx.key) or M.activeKey or "auras3"
    if M.RebuildPageKeepingScroll and M.RebuildPageKeepingScroll(key) then return end
    if M.RequestRefresh then
        M.RequestRefresh(ctx, "auras-rebuild-fallback")
    elseif M.Refresh then
        M.Refresh(ctx)
    end
end

local function RequestAuraRuntime(scope, reason)
    local apply = M.ApplyService or _G.MSUF_Menu2_ApplyService
    if apply and type(apply.RequestAuras) == "function" then
        return apply.RequestAuras(scope or "shared", reason or "AURAS3_MENU2_BATCH")
    end
    Model.Apply(scope or "shared", reason or "AURAS3_MENU2_BATCH")
    return true
end

local function ConfigureAuraSpellPriorityDrag(row, handle, listChild, rowHeight, onDrop)
    if not (row and handle and listChild) then return end
    rowHeight = max(1, tonumber(rowHeight) or 1)
    row:SetMovable(true)
    handle:RegisterForDrag("LeftButton")
    handle:EnableMouse(true)
    local function SnapRow()
        local slot = max(1, tonumber(row._displayIndex) or 1)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", listChild, "TOPLEFT", 0, -((slot - 1) * rowHeight))
        row:SetPoint("TOPRIGHT", listChild, "TOPRIGHT", 0, -((slot - 1) * rowHeight))
    end
    local function ClearDragState(shouldSnap)
        if row.StopMovingOrSizing then row:StopMovingOrSizing() end
        if row.SetFrameStrata and row._msufA3OldStrata then row:SetFrameStrata(row._msufA3OldStrata) end
        row._msufA3OldStrata = nil
        row._msufA3Dragging = nil
        if shouldSnap == true then SnapRow() end
    end
    handle:HookScript("OnEnter", function()
        if row._dragEnabled ~= true or not row.SetBackdropBorderColor then return end
        local c = (T.colors and T.colors.coreBlue) or { 0.095, 0.360, 0.560, 0.95 }
        row:SetBackdropBorderColor(c[1], c[2], c[3], c[4] or 1)
    end)
    handle:HookScript("OnLeave", function()
        if not row.SetBackdropBorderColor then return end
        local c = (T.colors and (T.colors.cardBorder or T.colors.borderSoft)) or { 0.210, 0.230, 0.300, 0.78 }
        row:SetBackdropBorderColor(c[1], c[2], c[3], c[4] or 1)
    end)
    handle:SetScript("OnDragStart", function()
        if row._dragEnabled ~= true or not row._spellID then return end
        if GameTooltip then GameTooltip:Hide() end
        row._msufA3Dragging = true
        row._msufA3OldStrata = row.GetFrameStrata and row:GetFrameStrata() or nil
        if row.SetFrameStrata then row:SetFrameStrata("TOOLTIP") end
        row:StartMoving()
    end)
    handle:SetScript("OnDragStop", function()
        if row._msufA3Dragging ~= true then return end
        if row.StopMovingOrSizing then row:StopMovingOrSizing() end
        local _, centerY = row:GetCenter()
        local top = listChild.GetTop and listChild:GetTop()
        local count = max(1, tonumber(row._entryCount) or 1)
        local source = max(1, min(count, tonumber(row._displayIndex) or 1))
        local target, bestDistance = source, math.huge
        if centerY and top then
            local rowHalf = (row.GetHeight and row:GetHeight() or rowHeight) * 0.5
            for slot = 1, count do
                local distance = math.abs(centerY - (top - ((slot - 1) * rowHeight) - rowHalf))
                if distance < bestDistance then
                    target, bestDistance = slot, distance
                end
            end
        end
        local spellID = row._spellID
        ClearDragState(true)
        if spellID and target ~= source and type(onDrop) == "function" then onDrop(spellID, target) end
    end)
    row:HookScript("OnHide", function() ClearDragState(false) end)
end

local function QueueAurasPageRefresh(ctx, reason)
    if AurasMenuCombatLocked() then return false end
    if M.RequestRefresh then
        M.RequestRefresh(ctx, reason or "auras-refresh")
    elseif M.Refresh then
        M.Refresh(ctx)
    end
end

local auraPageRefreshQueued = false

local pendingAuraPageRefreshCtx

local pendingAuraPageRefreshReason

local function QueueAuraPageControlRefresh(ctx, reason)
    pendingAuraPageRefreshCtx = ctx or pendingAuraPageRefreshCtx
    pendingAuraPageRefreshReason = reason or pendingAuraPageRefreshReason
    if auraPageRefreshQueued then return end
    auraPageRefreshQueued = true
    local function Flush()
        auraPageRefreshQueued = false
        local refreshCtx, refreshReason = pendingAuraPageRefreshCtx, pendingAuraPageRefreshReason
        pendingAuraPageRefreshCtx, pendingAuraPageRefreshReason = nil, nil
        if not AurasMenuCombatLocked() then QueueAurasPageRefresh(refreshCtx, refreshReason or "auras-apply") end
    end
    if C_Timer and C_Timer.After then C_Timer.After(0, Flush) else Flush() end
end

local function ApplyUnit(ctx, unit, reason, refresh)
    reason = reason or "AURAS3_MENU2"
    RequestAuraRuntime(unit or "shared", reason)
    if refresh == true then QueueAuraPageControlRefresh(ctx, reason) end
end

local function ConfigureMaxDurationSlider(slider)
    if not slider then return slider end
    if slider.SetValueFormatter then
        slider:SetValueFormatter(function(value)
            value = Round(value)
            return value <= 0 and "Off" or (tostring(value) .. "s")
        end)
    end
    if slider.SetValueParser then
        slider:SetValueParser(function(value)
            value = tostring(value or ""):lower()
            if value == "off" then return 0 end
            return tonumber(value:match("%d+"))
        end)
    end
    AddTooltip(slider, "Maximum duration",
        "Off shows auras of any duration. Otherwise, auras whose total duration exceeds this number of seconds are hidden.")
    return slider
end

local UNIT_AURA_WORKSPACE_TAB_STYLE = {
    bg = { 0.012, 0.025, 0.052, 0.90 },
    border = { 0.070, 0.130, 0.235, 0.52 },
    textColor = { 0.78, 0.86, 0.97, 0.96 },
    hoverBg = { 0.024, 0.052, 0.100, 0.96 },
    hoverBorder = { 0.120, 0.245, 0.455, 0.78 },
    activeBg = { 0.032, 0.090, 0.205, 0.97 },
    activeBorder = { 0.150, 0.385, 0.760, 0.92 },
    activeTextColor = { 0.94, 0.98, 1.00, 1.00 },
}

local function UnitAuraWorkspaceTabButton(parent, item, width)
    -- Midnight is the authored reference and must keep its exact tuned values.
    -- Other menu accents resolve from the live token family so Preview-as and
    -- Sample/Live do not retain the blue literals baked when this file loaded.
    if T.MenuAccentActive and T.MenuAccentActive() then
        local colors = T.colors or {}
        local style = UNIT_AURA_WORKSPACE_TAB_STYLE
        local function SetColor(target, source)
            target[1], target[2], target[3] = source[1], source[2], source[3]
        end
        SetColor(style.bg, colors.coreShadow or style.bg)
        SetColor(style.border, colors.coreRim or style.border)
        SetColor(style.textColor, colors.pillText or style.textColor)
        SetColor(style.hoverBg, colors.coreSurface or style.hoverBg)
        SetColor(style.hoverBorder, colors.coreGlow or style.hoverBorder)
        SetColor(style.activeBg, colors.pillActive or colors.coreBlue or style.activeBg)
        SetColor(style.activeBorder, colors.pillEdgeActive or colors.coreHot or style.activeBorder)
        SetColor(style.activeTextColor, colors.pillTextActive or style.activeTextColor)
    end
    return W.TopButton(parent, item.text, width, 24, UNIT_AURA_WORKSPACE_TAB_STYLE)
end

local function BuildActionTabs(ctx, parent, values, x, y, width, getValue, setValue, gap, buttonFactory, catalogPath)
    gap = gap or 6
    local count = #values
    local bw = max(56, floor(((width or 720) - gap * (count - 1)) / count))
    local buttons = {}
    local RefreshButtons
    for i = 1, count do
        local item = values[i]
        -- Tab rows show a selection, so they default to the workspace tab
        -- style: the plain action-button style draws its active state exactly
        -- like its idle one, so a selected chip would look unselected.
        local btn = (buttonFactory and buttonFactory(parent, item, bw)) or UnitAuraWorkspaceTabButton(parent, item, bw)
        btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x + (i - 1) * (bw + gap), y)
        btn:SetScript("OnClick", function()
            if item.value == getValue() then return end
            setValue(item.value)
            -- Selecting a tab is menu state, not a page rebuild, so re-stamp
            -- the active chip here instead of waiting for a page refresh.
            if RefreshButtons then RefreshButtons() end
        end)
        RegisterAuraControl(ctx, btn, item.text or item.label or item.value or "Option", "button",
            (catalogPath or "workspace.tabs") .. ".option." .. AuraCatalogToken(item.value, tostring(i)), "ephemeral")
        buttons[i] = btn
        if item.value ~= nil then buttons[item.value] = btn end
    end
    RefreshButtons = function()
        local current = getValue()
        for i = 1, count do
            if buttons[i].SetActive then buttons[i]:SetActive(values[i].value == current) end
        end
    end
    RefreshButtons()
    M.TrackRefresh(ctx, RefreshButtons)
    return getValue(), buttons, RefreshButtons
end

--- The blocked-spell list of a unit or group blacklist section: the empty
--- state text, a scroll list of rows (icon, name, Spell ID, Remove) built on
--- demand, and its repaint through the search query. opts.remove(spellID)
--- removes one entry; opts.removePath(value) names its Remove button.
--- The trimmed lower-case search query and the spell list entries whose
--- name or spell ID contains it (every entry for an empty query).
local function FilterSpellEntries(entries, searchValue)
    local query = tostring(searchValue or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local visible = {}
    for i = 1, #entries do
        local entry = entries[i]
        local haystack = (tostring(entry.text or "") .. " "
            .. tostring(entry.spellID or entry.value or "")):lower()
        if query == "" or haystack:find(query, 1, true) then visible[#visible + 1] = entry end
    end
    return query, visible
end
--- A scrolling spell list in an aura section: the scroll frame at (24, y),
--- height px tall, and its child, styled like the other nested lists.
local function SpellListScroll(section, y, inner, height)
    local listScroll = PixelLayoutRegion(CreateFrame("ScrollFrame", nil, section))
    listScroll:SetPoint("TOPLEFT", section, "TOPLEFT", 24, y)
    listScroll:SetSize(inner - 20, height)
    local listChild = PixelLayoutRegion(CreateFrame("Frame", nil, listScroll))
    listChild:SetSize(inner - 44, height)
    listScroll:SetScrollChild(listChild)
    M._StyleNestedAuraScrollFrame(listScroll, section, 44)
    return listScroll, listChild
end
--- Row i of a 44 px spell list: a 40 px card across the list child.
local function SpellListRow(listChild, i)
    local row = PixelLayoutRegion(CreateFrame("Frame", nil, listChild))
    row:SetPoint("TOPLEFT", listChild, "TOPLEFT", 0, -((i - 1) * 44))
    row:SetPoint("TOPRIGHT", listChild, "TOPRIGHT", 0, -((i - 1) * 44))
    row:SetHeight(40)
    if T.ApplyBackdrop then T.ApplyBackdrop(row, T.colors.panel2, T.colors.cardBorder or T.colors.borderSoft) end
    return row
end
--- A spell list row's icon (left edge at iconAnchor's iconRelPoint, x px
--- in), the name and Spell ID lines beside it and its Remove button.
local function SpellListRowLabels(row, iconAnchor, iconRelPoint, x)
    row.icon = PixelLayoutRegion(row:CreateTexture(nil, "ARTWORK"))
    row.icon:SetPoint("LEFT", iconAnchor, iconRelPoint, x, 0)
    row.icon:SetSize(28, 28)
    row.name = T.Font(row, "GameFontHighlightSmall", "", T.colors.text)
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 9, -1)
    row.id = T.Font(row, "GameFontDisableSmall", "", T.colors.muted)
    row.id:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 9, 1)
    row.remove = ActionButton(row, "Remove", 80)
    row.remove:SetPoint("RIGHT", row, "RIGHT", -8, 0)
end
local function BlockedSpellList(ctx, section, inner, offsetY, emptyText, opts)
    local Tr, MatchSuffix = M.AuraSettings.Tr, M.AuraSettings.MatchSuffix
    local empty = W.Text(section, emptyText, 24, -284 + offsetY, inner, T.colors.muted)
    local listScroll, listChild = SpellListScroll(section, -260 + offsetY, inner, 150)
    local rows = {}
    local function EnsureRow(i)
        local row = rows[i]
        if row then return row end
        row = SpellListRow(listChild, i)
        SpellListRowLabels(row, row, "LEFT", 7)
        row.remove:SetScript("OnClick", function()
            if row._spellID then opts.remove(row._spellID) end
        end)
        AddTooltip(row.remove, "Remove from blacklist", "Stops blocking this aura.")
        rows[i] = row
        return row
    end
    local list = {}
    --- Repaints the rows for the entries matching searchValue and the
    --- prepared header's count.
    function list.Paint(entries, searchValue, prepared)
        local query, visible = FilterSpellEntries(entries, searchValue)
        T.SetTranslatedText(prepared, M.Format("Blocked spells (%d)", #entries) .. MatchSuffix(query, #visible))
        T.SetTranslatedText(empty, #entries == 0 and Tr(emptyText) or M.Format("No results for \"%s\".", query))
        empty:SetShown(#visible == 0)
        listScroll:SetShown(#visible > 0)
        listChild:SetHeight(max(150, #visible * 44))
        for i = 1, max(#rows, #visible) do
            local row, entry = rows[i], visible[i]
            if entry then
                row = EnsureRow(i)
                row._spellID = entry.value
                row.icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                local name = tostring(entry.text or entry.value or "Spell"):gsub("%s*%(#%d+%)$", "")
                row.name:SetText(name)
                row.id:SetText(entry.spellID and (tostring("Spell ID ") .. tostring(entry.spellID)) or tostring(entry.value or ""))
                RegisterAuraControl(ctx, row.remove, "Remove " .. name, "button", opts.removePath(entry.value), "action")
                row:Show()
            elseif row then
                row._spellID = nil
                row:Hide()
            end
        end
    end
    return list
end

--- A blacklist's blocked spells as a set keyed by tostring(spell id).
local function BlockedSet(entries)
    local blocked = {}
    for i = 1, #entries do blocked[tostring(entries[i].value)] = true end
    return blocked
end
--- The spell a blacklist's "Add spell" button adds: the selected preset
--- spell while it is not blocked yet, otherwise the first one that is not.
local function FirstUnblockedSpell(values, selected, blocked)
    for i = 1, #values do
        if values[i].value == selected and not blocked[tostring(selected)] then return selected end
    end
    for i = 1, #values do
        if values[i].value ~= nil and not blocked[tostring(values[i].value)] then return values[i].value end
    end
    return nil
end
--- The preset summary line ("n spells in this set - ...") and the enabled
--- state of the "Add set" and "Add spell" buttons for the blocked set.
local function PaintPresetSummary(selectedSummary, addSet, addSpell, setSpells, blocked, CurrentSpell)
    local missing = 0
    for i = 1, #setSpells do if not blocked[tostring(setSpells[i].value)] then missing = missing + 1 end end
    T.SetTranslatedText(selectedSummary, missing == 0
        and M.Format("%d spells in this set - all already blocked", #setSpells)
        or M.Format("%d spells in this set - %d can still be added", #setSpells, missing))
    W.SetControlEnabled(addSet, missing > 0)
    local selectedSpell = CurrentSpell()
    W.SetControlEnabled(addSpell, selectedSpell ~= nil and not blocked[tostring(selectedSpell)])
end

local function BuildLaneTabs(ctx, parent, stateKey, x, y, width)
    BuildActionTabs(ctx, parent, LANE_VALUES, x, y, width, function() return CurrentLane(stateKey, "debuff") end, function(value)
        SetCurrentLane(stateKey, value)
        Rebuild(ctx)
    end, nil, nil, "workspace.lane-selector." .. AuraCatalogToken(stateKey, "lane"))
end

M.AuraControls = {
    ActionButton = ActionButton,
    AddAuraTooltipHelp = AddAuraTooltipHelp,
    AddTooltip = AddTooltip,
    ApplyUnit = ApplyUnit,
    AuraCatalogToken = AuraCatalogToken,
    AuraControlMeta = AuraControlMeta,
    AuraControlMetaAtVisiblePath = AuraControlMetaAtVisiblePath,
    BlockedSet = BlockedSet,
    BlockedSpellList = BlockedSpellList,
    BuildLaneTabs = BuildLaneTabs,
    Card = Card,
    SpellListRow = SpellListRow,
    SpellListRowLabels = SpellListRowLabels,
    SpellListScroll = SpellListScroll,
    FilterSpellEntries = FilterSpellEntries,
    FirstUnblockedSpell = FirstUnblockedSpell,
    PaintPresetSummary = PaintPresetSummary,
    ConfigureAuraSpellPriorityDrag = ConfigureAuraSpellPriorityDrag,
    ConfigureMaxDurationSlider = ConfigureMaxDurationSlider,
    LANE_VALUES = LANE_VALUES,
    QueueAurasPageRefresh = QueueAurasPageRefresh,
    Rebuild = Rebuild,
    RegisterAuraControl = RegisterAuraControl,
    RegisterAuraTextAction = RegisterAuraTextAction,
    RequestAuraRuntime = RequestAuraRuntime,
}
