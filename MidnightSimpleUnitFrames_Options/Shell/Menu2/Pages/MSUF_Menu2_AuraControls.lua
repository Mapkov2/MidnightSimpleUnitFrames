-- Shared Aura controls and apply scheduling; no dependency on a page builder.
local _, MSUF = ...
MSUF = MSUF or {}
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

local function AuraControlMeta(ctx, path, classification, assistantContract)
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
    if type(assistantContract) == "string" and assistantContract ~= "" then
        meta.settingKey = assistantContract
    elseif type(assistantContract) == "table" then
        meta.settingKey = assistantContract.settingKey
        meta.actionKey = assistantContract.actionKey
        meta.actionFixedArgs = assistantContract.actionFixedArgs
        meta.actionInputArg = assistantContract.actionInputArg
        meta.assistantDisposition = assistantContract.assistantDisposition
        meta.assistantDispositionReason = assistantContract.assistantDispositionReason
        meta.assistantSettingKeys = assistantContract.assistantSettingKeys
        meta.assistantSettingKeyPatterns = assistantContract.assistantSettingKeyPatterns
    end
    if (meta.classification == "setting" or meta.classification == "action")
        and not meta.settingKey and not meta.actionKey and not meta.assistantDisposition
    then
        meta.assistantDisposition = "dynamic"
        meta.assistantDispositionReason = "This Aura control targets the selected scope, lane, tool, or container on the current Aura workspace."
    end
    return meta
end

local function AuraControlMetaAtVisiblePath(ctx, identityPath, visiblePath, classification, assistantContract)
    local meta = AuraControlMeta(ctx, identityPath, classification, assistantContract)
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
        if meta.actionKey then
            meta.assistantDisposition = nil
            meta.assistantDispositionReason = nil
        end
    end
    M.RegisterSearchWidget(widget, meta)
    return widget
end

local function RegisterAuraTextAction(ctx, widget, input, label, path, assistantContract)
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
    return RegisterAuraControl(ctx, widget, label, "button", path, "action", assistantContract)
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
        "Controls this aura lane independently. Always / Out of Combat / Modifier / Never under Appearance > Miscellaneous affect only unit and group frames. Auras only reuse the selected Blizzard/MSUF look and cursor placement.")
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
    BuildLaneTabs = BuildLaneTabs,
    Card = Card,
    ConfigureAuraSpellPriorityDrag = ConfigureAuraSpellPriorityDrag,
    ConfigureMaxDurationSlider = ConfigureMaxDurationSlider,
    LANE_VALUES = LANE_VALUES,
    QueueAurasPageRefresh = QueueAurasPageRefresh,
    Rebuild = Rebuild,
    RegisterAuraControl = RegisterAuraControl,
    RegisterAuraTextAction = RegisterAuraTextAction,
    RequestAuraRuntime = RequestAuraRuntime,
}
