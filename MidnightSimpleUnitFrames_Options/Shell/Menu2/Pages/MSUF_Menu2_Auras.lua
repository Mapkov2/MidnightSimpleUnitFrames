local addonName, MSUF = ...
MSUF = MSUF or {}
addonName = (type(MSUF.AddonName) == "string" and MSUF.AddonName ~= "" and MSUF.AddonName)
    or "MidnightSimpleUnitFrames"
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

-- Menu2 Auras page.
-- Builds controls for Auras3 unit/group scopes, lanes, filters, and visual options. The page
-- talks to the Auras3 menu model; live tracking/filtering is handled by native 12.1 aura containers.
local W = M.Widgets
local T = M.Theme
local GP = M.GroupPage or {}
local A3 = MSUF.MSUF_Auras3
local Model = A3 and A3.MenuModel
local VTP = M.ValueTextPairs
local PreviewHelpers = M.PreviewHelpers or {}
if type(W) ~= "table" or type(T) ~= "table" or type(Model) ~= "table" then return end
local CreateFrame = _G.CreateFrame
local C_Timer = M.MenuTimer or _G.C_Timer
local MSUF_SetIconTexture = _G.MSUF_SetIconTexture
local FONT = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local TEX_W8 = "Interface\\Buttons\\WHITE8X8"
local AURA_PREVIEW_EDGE_OPTS = { linesKey = "edge", maxEdgeSize = 1, texture = TEX_W8, color = function() return 1, 1, 1, 0.95 end }
-- Icon-style art shared with the runtime. Parked on M rather than a file local:
-- this chunk is at Lua 5.1's 200 upvalue ceiling, so new file-scope locals here
-- break the whole page.
M.AURA_SHADOW_TEXTURE = "Interface\\AddOns\\" .. tostring(addonName or "MidnightSimpleUnitFrames")
    .. "\\Media\\Borders\\msuf_aura_border_shadow.tga"
M.AURA_ICON_STYLE_APPLY_DELAY = 0.18
local floor, ceil, max, min, abs = math.floor, math.ceil, math.max, math.min, math.abs
local tonumber, tostring, type, ipairs, pairs = tonumber, tostring, type, ipairs, pairs
local table_concat = table.concat
local function AuraDurationBarColor()
    local resolver = A3 and A3.GetDurationBarColor
    if type(resolver) == "function" then return resolver() end
    return 1, 1, 1
end
local AccessibleNumber = M.AccessibleNumber or function(value, fallback)
    fallback = tonumber(fallback) or 0
    local canaccessvalue = _G.canaccessvalue
    if type(canaccessvalue) == "function" and canaccessvalue(value) ~= true then return fallback end
    local issecretvalue = _G.issecretvalue
    if type(issecretvalue) == "function" and issecretvalue(value) == true then return fallback end
    return tonumber(value) or fallback
end
local AURA_SCOPE_VALUES = VTP "shared=Shared|player=Player|target=Target|focus=Focus|boss=Boss|party=Party|raid=Raid / Mythic"
local AURA_SCOPE_LABELS = { shared = "Shared", player = "Player", target = "Target", focus = "Focus", boss = "Boss", party = "Party", raid = "Raid / Mythic" }
local AURA_SCOPE_VALID = M.KeySetFromWords "shared player target focus boss party raid"
local AURA_GROUP_SCOPES = M.KeySetFromWords "party raid mythicraid"
local SHARED_PREVIEW_SCOPE_VALUES = VTP "player=Player|target=Target|focus=Focus|boss=Boss|party=Party|raid=Raid"
local AURA_PREVIEW_MODE_VALUES = VTP "sample=Sample|live=Live"
local LANE_VALUES = VTP "buff=Buffs|debuff=Debuffs"
local UNIT_STYLE_CONTAINER_VALUES = VTP "buff=Buffs|debuff=Debuffs|custom1=Custom 1|custom2=Custom 2|custom3=Custom 3|custom4=Dots on target"
local UNIT_STYLE_CONTAINER_VALUES_PLAYER = VTP "buff=Buffs|debuff=Debuffs|custom1=Custom 1|custom2=Custom 2|custom3=Custom 3|custom4=Defensive Buffs"
local CUSTOM_FRAME_EFFECTS = VTP "none=None|healthtint=Health Tint|border=Border|glow=Glow|pulse=Pulse|namecolor=Name Overlay"
local DEBUFF_TYPE_BORDER_MODE_VALUES = VTP "OFF=Off|BORDER=Border|SYMBOL=Border + Symbol"
local COOLDOWN_SWIPE_DIRECTION_VALUES = VTP "NORMAL=Normal|REVERSE=Reverse"
local AURA_SORT_DIRECTION_VALUES = VTP "NORMAL=Normal|REVERSE=Reversed"
local BUFF_AURA_SORT_METHOD_VALUES = VTP "DEFAULT=Player & Priority First|BIG_DEFENSIVE=Other Defensives First|IMPORTANT_FIRST=Important First|EXPIRATION=Player First, Expiring Soon|EXPIRATION_ONLY=Expiring Soon|NAME=Player First, then Name|NAME_ONLY=Name|INSTANCE_ID=Arrival Order"
local DEBUFF_AURA_SORT_METHOD_VALUES = VTP "DEFAULT=Player & Priority First|UNIT_FRAME_DEBUFF=Debuff Type First|IMPORTANT_FIRST=Important First|EXPIRATION=Player First, Expiring Soon|EXPIRATION_ONLY=Expiring Soon|NAME=Player First, then Name|NAME_ONLY=Name|INSTANCE_ID=Arrival Order"
local DURATION_BAR_DISPLAY_VALUES = VTP "BAR_ONLY=Bar Only|OVERLAY=Icon + Bar"
local DURATION_BAR_POSITION_VALUES = VTP "BOTTOM=Bottom|TOP=Top"
local DURATION_BAR_DIRECTION_VALUES = VTP "REMAINING=Remaining|ELAPSED=Elapsed"
local function AURA_COOLDOWN_COLOR_REFERENCES()
    local general = _G.MSUF_DB and _G.MSUF_DB.general or nil
    if general and general.aurasCooldownTextUseBuckets == true then
        return {
            "font.global",
            "aura.cooldown.safe",
            "aura.cooldown.warning",
            "aura.cooldown.urgent",
        }
    end
    return { "font.global" }
end
local AURA_DURATION_BAR_COLOR_REFERENCES = { "aura.cooldown.safe" }
local AURA_SHARED_COLOR_NOTE = "Shared by all Aura scopes."
function M.AttachAuraFontsAndColors(section, title, unit)
    if not (section and W.AttachContextColorReferences) then return end
    local references = AURA_COOLDOWN_COLOR_REFERENCES()
    if #references == 1 then references[2] = AURA_DURATION_BAR_COLOR_REFERENCES[1] end
    W.AttachContextColorReferences(section, references, {
        title = title .. " Fonts & Colors",
        historyLabel = title .. " color",
        historySource = "menu:auras-fonts-colors",
        scopeTag = "Shared",
        note = AURA_SHARED_COLOR_NOTE,
        tooltipTitle = "Aura fonts & colors",
        tooltipText = "Open the shared font and colors used by every Aura scope.",
        textSettings = {
            scope = "shared",
            unit = unit,
            kind = "aura",
            colorReferences = references,
            colorTitle = title .. " Colors",
            colorScopeTag = "Shared",
            colorNote = AURA_SHARED_COLOR_NOTE,
            subtitle = "Aura text follows the shared Fonts settings; duration colors stay synchronized with Aura Colors.",
            capabilities = {
                opacity = false, baseline = false,
                shadowAlpha = false, shadowDistance = false,
            },
        },
    })
end
local BUFF_AURA_SORT_METHOD_OK = { DEFAULT=true, BIG_DEFENSIVE=true, IMPORTANT_FIRST=true, EXPIRATION=true, EXPIRATION_ONLY=true, NAME=true, NAME_ONLY=true, INSTANCE_ID=true }
local DEBUFF_AURA_SORT_METHOD_OK = { DEFAULT=true, UNIT_FRAME_DEBUFF=true, IMPORTANT_FIRST=true, EXPIRATION=true, EXPIRATION_ONLY=true, NAME=true, NAME_ONLY=true, INSTANCE_ID=true }
local function AuraSortMethodValues(lane)
    return lane == "debuff" and DEBUFF_AURA_SORT_METHOD_VALUES or BUFF_AURA_SORT_METHOD_VALUES
end
local function ChoiceLabel(values, value, fallback)
    for i = 1, #(values or {}) do
        local item = values[i]
        if item and item.value == value then return item.text or fallback or tostring(value or "") end
    end
    return fallback or tostring(value or "")
end
local AURA_ANCHOR_LABELS = {
    TOPLEFT = "Top Left", TOP = "Top", TOPRIGHT = "Top Right",
    LEFT = "Left", CENTER = "Center", RIGHT = "Right",
    BOTTOMLEFT = "Bottom Left", BOTTOM = "Bottom", BOTTOMRIGHT = "Bottom Right",
}
local AURA_SORT_SUMMARY_LABELS = {
    DEFAULT = "Priority first", BIG_DEFENSIVE = "Defensives first", UNIT_FRAME_DEBUFF = "Debuff type first",
    IMPORTANT_FIRST = "Important first", EXPIRATION = "Player + expiring", EXPIRATION_ONLY = "Expiring soon",
    NAME = "Player + name", NAME_ONLY = "Name", INSTANCE_ID = "Arrival order",
}
local function AnchorLabel(value)
    value = tostring(value or "CENTER"):upper()
    return AURA_ANCHOR_LABELS[value] or value
end
local function NormalizeAuraSortMethodForLane(lane, value)
    value = tostring(value or "DEFAULT"):upper()
    local allowed = lane == "debuff" and DEBUFF_AURA_SORT_METHOD_OK or BUFF_AURA_SORT_METHOD_OK
    return allowed[value] and value or "DEFAULT"
end
local DEBUFF_TYPE_BORDER_PREVIEW_ATLAS = {
    BORDER = "ui-debuff-border-magic-noicon",
    SYMBOL = "ui-debuff-border-magic-icon",
}
local NATIVE_EXACT_AURA_FILTERS_ENABLED = true
local NATIVE_EXACT_AURA_FILTERS_TEXT = "Exact Spell IDs are used when Blizzard exposes them."
local GROUP_NATIVE_FILTER_LABELS = {
    ALL = "All",
    Player = "Player",
    BigDefensivePlayer = "Big Defensive Player",
    ExternalDefensivePlayer = "External Defensive Player",
    RaidInCombatPlayer = "Raid In Combat Player",
    CancelablePlayer = "Cancelable Player",
    NotCancelablePlayer = "Not Cancelable Player",
    RaidPlayer = "Raid Player",
    BigDefensive = "Big Defensive",
    ExternalDefensive = "External Defensive",
    RaidInCombat = "Raid In Combat",
    Cancelable = "Cancelable",
    NotCancelable = "Not Cancelable",
    Raid = "Raid",
    INCLUDE_NAME_PLATE_ONLY = "Include Nameplate-only",
    RAID_PLAYER_DISPELLABLE = "Dispellable by Group",
    DISPELLABLE = "Any Dispel Type",
    IMPORTANT = "Important",
    CROWD_CONTROL = "Crowd Control",
}
local GROUP_NATIVE_FILTER_ALLOWED = {
    buff = {
        ALL = true, Player = true, BigDefensivePlayer = true, ExternalDefensivePlayer = true,
        RaidInCombatPlayer = true, CancelablePlayer = true, NotCancelablePlayer = true,
        RaidPlayer = true, BigDefensive = true, ExternalDefensive = true, RaidInCombat = true,
        Cancelable = true, NotCancelable = true, Raid = true, IMPORTANT = true,
    },
    debuff = {
        ALL = true, Player = true, RaidPlayer = true, RaidInCombatPlayer = true,
        Raid = true, RaidInCombat = true, INCLUDE_NAME_PLATE_ONLY = true,
        RAID_PLAYER_DISPELLABLE = true, DISPELLABLE = true, IMPORTANT = true, CROWD_CONTROL = true,
    },
}
local GROUP_NATIVE_FILTER_CANONICAL = {
    ALL = "ALL",
    PLAYER = "Player",
    BIGDEFENSIVEPLAYER = "BigDefensivePlayer",
    EXTERNALDEFENSIVEPLAYER = "ExternalDefensivePlayer",
    RAIDINCOMBATPLAYER = "RaidInCombatPlayer",
    CANCELABLEPLAYER = "CancelablePlayer",
    NOTCANCELABLEPLAYER = "NotCancelablePlayer",
    RAIDPLAYER = "RaidPlayer",
    BIGDEFENSIVE = "BigDefensive",
    EXTERNALDEFENSIVE = "ExternalDefensive",
    RAIDINCOMBAT = "RaidInCombat",
    CANCELABLE = "Cancelable",
    NOTCANCELABLE = "NotCancelable",
    RAID = "Raid",
    INCLUDENAMEPLATEONLY = "INCLUDE_NAME_PLATE_ONLY",
    RAIDPLAYERDISPELLABLE = "RAID_PLAYER_DISPELLABLE",
    DISPELLABLE = "DISPELLABLE",
    IMPORTANT = "IMPORTANT",
    CROWDCONTROL = "CROWD_CONTROL",
}
local function CanonicalGroupFilterValue(value)
    local key = tostring(value or "ALL"):upper():gsub("[^A-Z0-9]", "")
    return GROUP_NATIVE_FILTER_CANONICAL[key] or "ALL"
end
local function Tr(text)
    if type(M.Tr) == "function" then return M.Tr(text) end
    return text
end
local function AuraCatalogToken(value, fallback)
    local token = tostring(value or ""):lower():gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
    return token ~= "" and token or (fallback or "control")
end
local function AuraCatalogPageKey(value, fallback)
    local token = tostring(value or ""):lower():gsub("[^%w_%-]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
    return token ~= "" and token or (fallback or "auras")
end
local function LaneFrameEffectAssistantContract()
    return {
        assistantDisposition = "compound",
        assistantDispositionReason = "This scope-aware Buff/Debuff Full-Frame effect writes the active shared or per-unit Aura style and has no Assistant setting contract yet.",
    }
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
local function RegisterAuraChoiceBar(ctx, bar, values, path)
    if not bar then return bar end
    RegisterAuraControl(ctx, bar, bar._msuf2SearchTitle or "Editing", "segment", path, "ephemeral")
    return bar
end
local function Round(value)
    value = tonumber(value) or 0
    if value < 0 then return -floor((-value) + 0.5) end
    return floor(value + 0.5)
end
local function NormalizeDebuffTypeBorderMode(value, fallback)
    if value == true then return "SYMBOL" end
    if value == false then return "OFF" end
    value = tostring(value or ""):upper()
    if value == "BORDER" or value == "COLOR" or value == "ON" then return "BORDER" end
    if value == "SYMBOL" or value == "BORDER_SYMBOL" or value == "BORDER_SYMBOLS"
        or value == "BORDER+SYMBOL" or value == "ICON" or value == "WITH_SYMBOL" then
        return "SYMBOL"
    end
    if value == "OFF" or value == "NONE" or value == "DISABLED" then return "OFF" end
    return fallback or "OFF"
end
local function AddTooltip(widget, title, body)
    return M.AddTooltip(widget, title, body, { hook = true, titleAsLine = true })
end
local function ActionButton(parent, label, width, role)
    if W.RoleButton then return W.RoleButton(parent, label, role or "normal", width or 90, 24) end
    if W.TopButton then return W.TopButton(parent, label, width or 90, 24) end
    local btn = T.Button(parent, label, width or 90, 24)
    if W.StyleTopActionButton then W.StyleTopActionButton(btn) end
    return btn
end
local function Card(parent, title, subtitle, x, y, width, height)
    local card = W.ControlCard(parent, title, subtitle, x, y, width, height)
    if card and T.ApplyBackdrop then T.ApplyBackdrop(card, T.colors.panel2, T.colors.cardBorder or T.colors.borderSoft) end
    return card
end
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
local function SelectPage(pageKey, scope)
    if scope then
        M.SetMenuStateValue("auraScope", scope)
        if scope == "party" or scope == "raid" then M.SetMenuStateValue("auraStyleGFScope", scope) end
    end
    if M.SelectPage then M.SelectPage(pageKey or "auras3") end
end
local function RequestAuraRuntime(scope, reason)
    local apply = M.ApplyService or _G.MSUF_Menu2_ApplyService
    if apply and type(apply.RequestAuras) == "function" then
        return apply.RequestAuras(scope or "shared", reason or "AURAS3_MENU2_BATCH")
    end
    Model.Apply(scope or "shared", reason or "AURAS3_MENU2_BATCH")
    return true
end
local function AurasMenuCombatLocked()
    if type(M.IsConfigCombatLocked) == "function" then return M.IsConfigCombatLocked() and true or false end
    if type(_G.MSUF_IsConfigCombatLocked) == "function" then return _G.MSUF_IsConfigCombatLocked() and true or false end
    return (_G.InCombatLockdown and _G.InCombatLockdown()) and true or false
end
local function HandleNestedScrollWheel(scrollFrame, delta, step)
    delta = tonumber(delta) or 0
    if delta == 0 or not scrollFrame then return end
    local range = AccessibleNumber(scrollFrame.GetVerticalScrollRange and scrollFrame:GetVerticalScrollRange() or 0, 0)
    local current = AccessibleNumber(scrollFrame.GetVerticalScroll and scrollFrame:GetVerticalScroll() or 0, 0)
    local leavingTop = delta > 0 and current <= 0.01
    local leavingBottom = delta < 0 and current >= range - 0.01
    if range <= 0 or leavingTop or leavingBottom then
        if scrollFrame.SetPropagateMouseWheel then
            scrollFrame:SetPropagateMouseWheel(true)
        else
            local main = M.scrollFrame
            local handler = main and main.GetScript and main:GetScript("OnMouseWheel")
            if type(handler) == "function" then handler(main, delta) end
        end
        return
    end
    if scrollFrame.SetPropagateMouseWheel then scrollFrame:SetPropagateMouseWheel(false) end
    local value = current - (delta * (tonumber(step) or 42))
    if value < 0 then value = 0 elseif value > range then value = range end
    if scrollFrame.SetVerticalScroll then scrollFrame:SetVerticalScroll(value) end
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
local BindSwitch, BindToggle, BindSlider = M.BindSwitchAt, M.BindToggleAt, M.BindSliderAt
local BindDropdown, BindTextInput = M.BindDropdownAt, M.BindTextInputAt
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
    AddTooltip(slider, "Maximum debuff duration",
        "Off shows debuffs of any duration. Otherwise, debuffs whose total duration exceeds this number of seconds are hidden.")
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
local function CurrentScope()
    if type(M.EnsurePersistentMenuState) == "function" then M.EnsurePersistentMenuState() end
    local scope = M.auraScope or "shared"
    if scope == "mythicraid" then scope = "raid" end
    return AURA_SCOPE_VALID[scope] and scope or "shared"
end
local function CurrentAuraPreviewScope()
    local scope = M.auraStylePreviewScope or "target"
    return AURA_SCOPE_VALID[scope] and scope ~= "shared" and scope or "target"
end
local function CurrentAuraPreviewMode()
    return M.auraStylePreviewMode == "live" and "live" or "sample"
end
local function SetCurrentScope(scope)
    scope = scope or "shared"
    if scope == "mythicraid" then scope = "raid" end
    M.SetMenuStateValue("auraScope", scope)
    if scope == "party" or scope == "raid" then M.SetMenuStateValue("auraStyleGFScope", scope) end
end
local function IsGroupScope(scope)
    scope = scope or CurrentScope()
    return AURA_GROUP_SCOPES[scope] == true
end
local function ScopeLabel(scope)
    return AURA_SCOPE_LABELS[scope] or "Raid / Mythic"
end
local AURA_STYLE_UNIT_SCOPES = {
    { value = "player", text = "Player" },
    { value = "target", text = "Target" },
    { value = "focus", text = "Focus" },
    { value = "boss", text = "Boss" },
}
local function AuraStyleUnitOverrideLabels()
    local out = {}
    for i = 1, #AURA_STYLE_UNIT_SCOPES do
        local item = AURA_STYLE_UNIT_SCOPES[i]
        if not Model.UseSharedVisuals(item.value) then out[#out + 1] = item.text end
    end
    return out
end
local function AuraStyleVisibleOverrideLabels(unitLabels)
    local out = {}
    unitLabels = unitLabels or AuraStyleUnitOverrideLabels()
    for i = 1, #unitLabels do out[#out + 1] = unitLabels[i] end
    out[#out + 1] = "Party"
    out[#out + 1] = "Raid / Mythic"
    return out
end
local function AuraStyleScopeHasOverride(scope)
    if scope == "shared" then return false end
    if IsGroupScope(scope) then return true end
    return not Model.UseSharedVisuals(scope)
end
local function BuildAuraStyleScopeOverrideSection(ctx, b)
    local values = AURA_SCOPE_VALUES
    local compactGroupScope = IsGroupScope(CurrentScope())
    local scopeOpts = {
        values = values,
        width = ctx.width,
        getValue = CurrentScope,
        setValue = function(value)
            SetCurrentScope(value)
            Rebuild(ctx)
        end,
        hasOverride = AuraStyleScopeHasOverride,
    }
    local metrics = W.MeasureScopeOverrideBar and W.MeasureScopeOverrideBar(values, scopeOpts)
    local overrideY = min(-58, ((metrics and metrics.bottomY) or -40) - 18)
    local hintY = overrideY - 34
    local compactHeight = max(68, abs((metrics and metrics.bottomY) or -40) + 18)
    local section = b:Section("", compactGroupScope and compactHeight or max(128, abs(hintY) + 42))
    if section.title then section.title:Hide() end
    local segment = RegisterAuraChoiceBar(ctx, W.ScopeOverrideBar(ctx, section, scopeOpts), values, "style.scope.selector")
    local override = W.ToggleAt(section, "Use custom aura style for this scope", 14, overrideY, 300)
    AddTooltip(override, "Aura style override", "On: this scope keeps local aura style settings. Off: this scope follows Shared aura style.")
    M.BindBoolWidget(ctx, override,
        function()
            local current = CurrentScope()
            return current ~= "shared" and not IsGroupScope(current) and not Model.UseSharedVisuals(current)
        end,
        function(enabled)
            local current = CurrentScope()
            if current == "shared" or IsGroupScope(current) then return end
            Model.SetUseSharedVisuals(current, not enabled)
            ApplyUnit(ctx, current, "AURAS3_STYLE_OVERRIDE", true)
            Rebuild(ctx)
        end,
        AuraControlMeta(ctx, "style.scope.override"))
    local overrideInfo = W.Text(section, "", 14, overrideY, ctx.width - 130, T.colors.text)
    local reset = T.Button(section, "Reset", 76, 24)
    reset:SetPoint("TOPRIGHT", section, "TOPRIGHT", -16, overrideY + 8)
    T.CenterButtonLabel(reset)
    reset:SetScript("OnClick", function()
        for i = 1, #AURA_STYLE_UNIT_SCOPES do
            Model.SetUseSharedVisuals(AURA_STYLE_UNIT_SCOPES[i].value, true)
            ApplyUnit(ctx, AURA_STYLE_UNIT_SCOPES[i].value, "AURAS3_STYLE_RESET", false)
        end
        Rebuild(ctx)
    end)
    RegisterAuraControl(ctx, reset, "Reset", "button", "style.scope.reset-overrides", "action", "reset_all_aura_style_overrides")
    local hint = W.Text(section, "", 14, hintY, ctx.width - 28, T.colors.muted)
    M.TrackRefresh(ctx, function()
        local current = CurrentScope()
        local shared = current == "shared"
        local group = IsGroupScope(current)
        local custom = not shared and not group and tostring(M.auraStyleContainer or ""):match("^custom[1234]$") ~= nil
        local active = AuraStyleUnitOverrideLabels()
        local visibleActive = AuraStyleVisibleOverrideLabels(active)
        W.SetControlShown(override, not shared and not group and not custom)
        overrideInfo:SetShown(shared or custom)
        hint:SetShown(not group)
        reset:SetShown(shared and #active > 0)
        if shared then
            overrideInfo:SetText("|cffffffff" .. Tr("Overrides:") .. "|r " .. (#visibleActive > 0 and table_concat(visibleActive, ", ") or Tr("None")))
            hint:SetText(Tr("Shared aura style is the baseline for unit-frame aura text, swipe, border, and timer settings. Party and Raid are group-frame style scopes with their own settings."))
        elseif group then
            overrideInfo:SetText("")
            hint:SetText("")
        elseif custom then
            overrideInfo:SetText("|cffffffff" .. M.Format("%s Custom style", ScopeLabel(current)) .. "|r")
            hint:SetText(M.Format("Custom 1-3, player Defensive Buffs, and Dots on target are stored per frame. Icon styling and Full-Frame effects here only change %s.", ScopeLabel(current)))
        elseif not Model.UseSharedVisuals(current) then
            hint:SetText(Tr("Override active: this scope keeps its own aura style. Shared style changes will not replace it until the override is reset."))
        else
            hint:SetText(Tr("Inherited: this scope follows Shared aura style. Enable custom aura style only when this scope needs different text, swipe, border, or timer settings."))
        end
        if segment and segment.Refresh then segment:Refresh() end
        hint:SetWidth(ctx.width - 28)
    end)
    if W.AttachStickyPageHeader then
        W.AttachStickyPageHeader(section, {
            pageKey = ctx and ctx.key,
            wrapper = ctx and ctx.wrapper,
            gap = 4,
            builder = b,
            ctx = ctx,
            flowGap = 12,
        })
    end
    return CurrentScope()
end
local function FinishPage(ctx, b)
    if ctx and ctx.SetContentHeight then ctx:SetContentHeight(abs(b.y) + 42) end
end
local SetCurrentLane
local function CurrentLane(stateKey, defaultValue)
    local lane = M[stateKey] or defaultValue or "debuff"
    if lane ~= "buff" and lane ~= "debuff" then lane = defaultValue or "debuff" end
    return lane
end
function SetCurrentLane(stateKey, lane)
    lane = lane == "buff" and "buff" or "debuff"
    M.SetMenuStateValue(stateKey, lane)
    if stateKey ~= "auraStyleGFLane" then M.SetMenuStateValue("auraStyleGFLane", lane) end
end
local function BuildLaneTabs(ctx, parent, stateKey, x, y, width)
    BuildActionTabs(ctx, parent, LANE_VALUES, x, y, width, function() return CurrentLane(stateKey, "debuff") end, function(value)
        SetCurrentLane(stateKey, value)
        Rebuild(ctx)
    end, nil, nil, "workspace.lane-selector." .. AuraCatalogToken(stateKey, "lane"))
end
local function LaneTitle(kind)
    return kind == "buff" and "Buff" or "Debuff"
end
local function LanePlural(kind)
    return kind == "buff" and "Buffs" or "Debuffs"
end
local function CurrentAuraStyleContainer(scope)
    local container = M.auraStyleContainer or CurrentLane("auraStyleGFLane", "debuff")
    local custom = tostring(container):match("^custom[1234]$") ~= nil
    if container ~= "buff" and container ~= "debuff" and not custom then container = "debuff" end
    if (scope == "shared" or IsGroupScope(scope)) and custom then
        container = CurrentLane("auraStyleGFLane", "debuff")
    end
    return container
end
local function BuildAuraStyleNav(ctx, b, scope)
    local h = 56
    local section = T.Panel(b.parent, nil, T.colors.panel2, T.colors.cardBorder or T.colors.borderSoft)
    T.ApplySurface(section, "card")
    section:SetPoint("TOPLEFT", b.parent, "TOPLEFT", b.x, b.y)
    section:SetSize(b.width, h)
    section._msuf2Width = b.width
    if W.RegisterGuidedRegion then W.RegisterGuidedRegion(ctx, section, "Aura container") end
    b.y = b.y - h - 12
    if ctx and ctx.SetContentHeight then ctx:SetContentHeight(abs(b.y) + 28) end
    local w = section._msuf2Width or b.width or 720
    local values = (scope ~= "shared" and not IsGroupScope(scope))
        and (scope == "player" and UNIT_STYLE_CONTAINER_VALUES_PLAYER or UNIT_STYLE_CONTAINER_VALUES)
        or LANE_VALUES
    local bar = RegisterAuraChoiceBar(ctx, W.ScopeOverrideBar(ctx, section, {
        values = values,
        width = w,
        label = "Container:",
        labelWidth = 88,
        centerY = -28,
        getValue = function() return CurrentAuraStyleContainer(scope) end,
        setValue = function(container)
            M.SetMenuStateValue("auraStyleContainer", container)
            if container == "buff" or container == "debuff" then SetCurrentLane("auraStyleGFLane", container) end
            local key = (ctx and ctx.key) or M.activeKey
            if key == "auras3_buffs" or key == "auras3_debuffs" then
                SelectPage("auras3_styling", CurrentScope())
            else
                Rebuild(ctx)
            end
        end,
    }), values, "style.container.selector")
    local current = CurrentAuraStyleContainer(scope)
    local title = current == "custom4" and (scope == "player" and "Defensive Buff Aura Style" or "Dots on target Aura Style")
        or (tostring(current):match("^custom[123]$") and ("Custom " .. tostring(current):match("(%d)$") .. " Aura Style"))
        or (LaneTitle(current) .. " Aura Style")
    M.AttachAuraFontsAndColors(section, title, scope)
    return current
end
local function OtherLane(kind)
    return kind == "buff" and "debuff" or "buff"
end
local function LaneMaxKey(kind)
    return kind == "buff" and "maxBuffs" or "maxDebuffs"
end
local function LaneSizeKey(kind)
    return kind == "buff" and "buffGroupIconSize" or "debuffGroupIconSize"
end
local function LaneXKey(kind)
    return kind == "buff" and "buffGroupOffsetX" or "debuffGroupOffsetX"
end
local function LaneYKey(kind)
    return kind == "buff" and "buffGroupOffsetY" or "debuffGroupOffsetY"
end
local function LaneDefaultMax(kind)
    return kind == "buff" and 8 or 12
end
local function LaneDefaultY(kind)
    return kind == "buff" and 36 or 6
end
local function UnitLaneShown(unit, kind)
    return Model.UnitEnabled(unit) and Model.GroupShown(unit, kind)
end
local UNIT_AURA_DISPEL_WARNING_UNITS = { "player", "target", "focus", "boss" }
local UNIT_AURA_DISPEL_WARNING = "No UnitFrame auras: Dispel Border/Overlay need Player/Target/Focus/Boss auras."
local function AnyUnitFrameAuraEnabled()
    for i = 1, #UNIT_AURA_DISPEL_WARNING_UNITS do
        if Model.UnitEnabled(UNIT_AURA_DISPEL_WARNING_UNITS[i]) then return true end
    end
    return false
end
local function ShowNoUnitAuraDispelWarning()
    if type(M.ShowStatusFeedback) == "function" then
        M.ShowStatusFeedback(UNIT_AURA_DISPEL_WARNING, "warning", 3.0)
    end
end
local function SetUnitLaneShown(ctx, unit, kind, shown, reason)
    if shown then
        Model.SetUnitEnabled(unit, true)
        Model.WriteSharedBool(kind == "buff" and "showBuffs" or "showDebuffs", true)
        Model.SetGroupShown(unit, kind, true)
    else
        Model.SetGroupShown(unit, kind, false)
        if not Model.GroupShown(unit, OtherLane(kind)) then Model.SetUnitEnabled(unit, false) end
    end
    ApplyUnit(ctx, unit, reason or "AURAS3_VISIBILITY", true)
    if not shown and not AnyUnitFrameAuraEnabled() then ShowNoUnitAuraDispelWarning() end
end
local function GF()
    if type(GP.GF) == "function" then return GP.GF() end
    return MSUF and MSUF.GF
end
local function RefreshGFPreview()
    if type(GP.RefreshGFPreview) == "function" then GP.RefreshGFPreview() end
end
local function GroupScopeKinds(scope)
    if scope == "party" then return "party" end
    return "raid", "mythicraid"
end
local function GroupAssistantSettingKeys(scope, suffix)
    suffix = tostring(suffix or "")
    if scope == "party" then return { "gf_party" .. suffix } end
    -- Raid and Mythic Raid share this Menu2 Aura editor and each write fans out
    -- to both backing scopes.  Retain both finite identities so exact guidance
    -- reaches the same reviewed dynamic control from either Registry setting.
    return { "gf_raid" .. suffix, "gf_mythicraid" .. suffix }
end
local function GroupAssistantBlacklistSettingKeys(scope, suffix)
    suffix = tostring(suffix or "")
    if scope == "party" then return { "gf_party" .. suffix } end
    -- Raid/Mythic share this editor and backing blacklist operation, but the
    -- Assistant Registry intentionally exposes one canonical Raid list key.
    return { "gf_raid" .. suffix }
end
local function GroupConf(kind)
    if type(GP.Conf) == "function" then return GP.Conf(kind) end
    local db = M.EnsureDB()
    local key = kind == "raid" and "gf_raid" or (kind == "mythicraid" and "gf_mythicraid" or "gf_party")
    db[key] = db[key] or {}
    return db[key]
end
local function QueueGroupScope(scope, mode)
    local a, b = GroupScopeKinds(scope)
    if type(GP.QueueGF) == "function" then
        GP.QueueGF(a, mode or "visual")
        if b then GP.QueueGF(b, mode or "visual") end
    end
    -- Paint the menu preview from the just-written raw Aura style immediately.
    -- The coalesced group apply below still owns runtime recompilation.
    RefreshGFPreview()
end
local function GFAurasRoot(kind)
    local conf = GroupConf(kind)
    conf.auras = conf.auras or {}
    if conf.auras.renderer ~= "CUSTOM" then conf.auras.renderer = "CUSTOM" end
    conf.auras.blizzardTypes = conf.auras.blizzardTypes or {}
    conf.auras.buff = conf.auras.buff or {}
    conf.auras.debuff = conf.auras.debuff or {}
    return conf.auras
end
local function GFAuraGroup(kind, groupKey)
    local root = GFAurasRoot(kind)
    root[groupKey] = root[groupKey] or {}
    return root[groupKey]
end
local function GFReadRoot(scope)
    local kind = GroupScopeKinds(scope)
    return GFAurasRoot(kind)
end
local function GFReadGroup(scope, groupKey)
    local kind = GroupScopeKinds(scope)
    return GFAuraGroup(kind, groupKey)
end
local function GFWriteScopeValue(scope, mode, getTarget, key, value)
    local changed
    local a, b = GroupScopeKinds(scope)
    local function write(kind)
        local target = getTarget(kind)
        if target[key] == value then return end
        target[key] = value
        changed = true
    end
    write(a)
    if b then write(b) end
    if changed then QueueGroupScope(scope, mode or "visual") end
end
local function GFWriteGroupValue(scope, groupKey, key, value, mode)
    GFWriteScopeValue(scope, mode, function(kind) return GFAuraGroup(kind, groupKey) end, key, value)
end
local function GFWriteGroupValues(scope, groupKey, values, mode)
    local changed
    local a, b = GroupScopeKinds(scope)
    local function write(kind)
        local target = GFAuraGroup(kind, groupKey)
        for key, value in pairs(values) do
            if target[key] ~= value then
                target[key] = value
                changed = true
            end
        end
    end
    write(a)
    if b then write(b) end
    if changed then QueueGroupScope(scope, mode or "visual") end
end
local function GFWriteRootValue(scope, key, value, mode)
    GFWriteScopeValue(scope, mode, GFAurasRoot, key, value)
end
local function AuraFilter()
    local gf = GF()
    return (gf and gf.AuraFilter) or _G.MSUF_GF_AuraFilter
end
local function GroupFilterValues(groupKey)
    local af = AuraFilter()
    local source = groupKey == "debuff" and af and af.DEBUFF_FILTER_ITEMS or af and af.BUFF_FILTER_ITEMS
    local allowed = GROUP_NATIVE_FILTER_ALLOWED[groupKey == "debuff" and "debuff" or "buff"]
    local out = {}
    if type(source) == "table" then
        for i = 1, #source do
            local item = source[i]
            local value = CanonicalGroupFilterValue(item and (item.value or item.key))
            if allowed[value] then
                out[#out + 1] = {
                    value = value,
                    text = GROUP_NATIVE_FILTER_LABELS[value] or item.text or item.label or value,
                }
            end
        end
    end
    if #out > 0 then return out end
    if groupKey == "buff" then
        return VT(
            "ALL", "All Buffs",
            "Player", "Player",
            "BigDefensivePlayer", "Big Defensive Player",
            "ExternalDefensivePlayer", "External Defensive Player",
            "RaidInCombatPlayer", "Raid In Combat Player",
            "CancelablePlayer", "Cancelable Player",
            "NotCancelablePlayer", "Not Cancelable Player",
            "RaidPlayer", "Raid Player",
            "BigDefensive", "Big Defensive",
            "ExternalDefensive", "External Defensive",
            "RaidInCombat", "Raid In Combat",
            "Cancelable", "Cancelable",
            "NotCancelable", "Not Cancelable",
            "Raid", "Applicable by Me (Raid)",
            "IMPORTANT", "Important"
        )
    end
    return VT(
        "ALL", "All Debuffs",
        "Player", "Player",
        "RaidPlayer", "Raid Player",
        "RaidInCombatPlayer", "Raid In Combat Player",
        "Raid", "Dispellable by Me (Raid)",
        "RaidInCombat", "Raid In Combat",
        "INCLUDE_NAME_PLATE_ONLY", "Include Nameplate-only",
        "RAID_PLAYER_DISPELLABLE", "Dispellable by Group",
        "DISPELLABLE", "Any Dispel Type",
        "IMPORTANT", "Important",
        "CROWD_CONTROL", "Crowd Control"
    )
end
local function GFAnchorValues()
    local values = GP.STATUS_ICON_ANCHORS or GP.AURA_ANCHORS
    if type(values) == "table" and #values > 0 then return values end
    return VT("CENTER", "Center", "TOPLEFT", "Top Left", "TOPRIGHT", "Top Right", "BOTTOMLEFT", "Bottom Left", "BOTTOMRIGHT", "Bottom Right")
end
local function BindGroupSwitch(ctx, parent, label, x, y, width, scope, groupKey, key, defaultValue, mode, afterSet)
    return BindSwitch(ctx, parent, label, x, y, width,
        function()
            local group = GFReadGroup(scope, groupKey)
            local value = group[key]
            if value == nil and key == "showTooltip" then
                local root = GFReadRoot(scope)
                value = root and root.showTooltip
            end
            if value == nil then value = defaultValue end
            return value and true or false
        end,
        function(v)
            GFWriteGroupValue(scope, groupKey, key, v and true or false, mode or "visual")
            if afterSet then afterSet(v and true or false) end
        end,
        AuraControlMeta(ctx, "group-style.lane." .. AuraCatalogToken(groupKey, "lane") .. "." .. AuraCatalogToken(key)))
end
local function BindGroupRootSwitch(ctx, parent, label, x, y, width, scope, key, defaultValue, mode, afterSet)
    return BindSwitch(ctx, parent, label, x, y, width,
        function()
            local root = GFReadRoot(scope)
            local value = root[key]
            if value == nil then value = defaultValue end
            return value and true or false
        end,
        function(v)
            GFWriteRootValue(scope, key, v and true or false, mode or "visual")
            if afterSet then afterSet(v and true or false) end
        end,
        AuraControlMeta(ctx, "group-style.root." .. AuraCatalogToken(key)))
end
local function BindGroupSlider(ctx, parent, label, x, y, minVal, maxVal, step, width, scope, groupKey, key, defaultValue, mode, afterSet, assistantContract)
    return BindSlider(ctx, parent, label, x, y, minVal, maxVal, step, width,
        function()
            local group = GFReadGroup(scope, groupKey)
            return tonumber(group[key]) or defaultValue or 0
        end,
        function(v)
            v = Round(v)
            GFWriteGroupValue(scope, groupKey, key, v, mode or "visual")
            if afterSet then afterSet(v) end
        end,
        AuraControlMeta(ctx, "group-style.lane." .. AuraCatalogToken(groupKey, "lane") .. "." .. AuraCatalogToken(key), nil, assistantContract))
end
local function BindGroupDropdown(ctx, parent, label, x, y, values, width, scope, groupKey, key, defaultValue, mode, afterSet)
    return BindDropdown(ctx, parent, label, x, y, values, width,
        function()
            local group = GFReadGroup(scope, groupKey)
            local value = group[key] or defaultValue
            if key == "filterToken" then value = CanonicalGroupFilterValue(value) end
            if key == "sortMethod" then value = NormalizeAuraSortMethodForLane(groupKey, value) end
            return value
        end,
        function(v)
            local value = v or defaultValue
            if key == "filterToken" then value = CanonicalGroupFilterValue(value) end
            if key == "sortMethod" then value = NormalizeAuraSortMethodForLane(groupKey, value) end
            GFWriteGroupValue(scope, groupKey, key, value, mode or "visual")
            if afterSet then afterSet(value) end
        end,
        AuraControlMeta(ctx, "group-style.lane." .. AuraCatalogToken(groupKey, "lane") .. "." .. AuraCatalogToken(key)))
end
local function ReadGroupDebuffTypeBorderMode(scope, groupKey)
    local group = GFReadGroup(scope, groupKey or "debuff")
    if group.dispelBorderMode ~= nil then
        local mode = NormalizeDebuffTypeBorderMode(group.dispelBorderMode, "OFF")
        return (mode == "OFF" and group.showDispelBorder == true) and "SYMBOL" or mode
    end
    return group.showDispelBorder == true and "SYMBOL" or "OFF"
end
local function WriteGroupDebuffTypeBorderMode(scope, groupKey, value)
    value = NormalizeDebuffTypeBorderMode(value, "OFF")
    GFWriteGroupValues(scope, groupKey or "debuff", {
        dispelBorderMode = value,
        showDispelBorder = value ~= "OFF",
        showDispelSymbol = value == "SYMBOL",
    }, "visual")
end
local function CreateAuraPreviewIcon(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(24, 24)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0, 0, 0, 0.85)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    f.icon:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    if f.icon.SetTexCoord then f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    f.swipe = f:CreateTexture(nil, "ARTWORK")
    f.swipe:SetPoint("TOPLEFT", f, "TOP", 0, -1)
    f.swipe:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    f.swipe:SetTexture(TEX_W8)
    f.swipe:SetVertexColor(0, 0, 0, 0.28)
    f.swipe:Hide()
    f.durationBar = f:CreateTexture(nil, "OVERLAY")
    f.durationBar:SetTexture(TEX_W8)
    local durationR, durationG, durationB = AuraDurationBarColor()
    f.durationBar:SetVertexColor(durationR, durationG, durationB, 0.92)
    f.durationBar:Hide()
    f.dispelBorder = f:CreateTexture(nil, "OVERLAY")
    f.dispelBorder:Hide()
    f.edge = {}
    if PreviewHelpers.LayoutEdgeLines then PreviewHelpers.LayoutEdgeLines(f, 1, AURA_PREVIEW_EDGE_OPTS) end
    f.stack = f:CreateFontString(nil, "OVERLAY")
    f.stack:SetFont(FONT, T.FontSize("micro"), "OUTLINE")
    f.stack:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    f.timer = f:CreateFontString(nil, "OVERLAY")
    f.timer:SetFont(FONT, T.FontSize("micro"), "OUTLINE")
    f.timer:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 2, 1)
    return f
end
local function ApplyAuraPreviewIconZoom(texture, zoom)
    if not (texture and texture.SetTexCoord) then return end
    zoom = tonumber(zoom) or 100
    if zoom < 100 then zoom = 100 elseif zoom > 200 then zoom = 200 end
    local visible = 100 / zoom
    local inset = (1 - visible) * 0.5
    texture:SetTexCoord(inset, 1 - inset, inset, 1 - inset)
end
local function ApplyAuraPreviewFont(fs, size)
    if not fs then return end
    local fontPath, fontFlags, r, g, b, _, useShadow
    if type(_G.MSUF_GetGlobalFontSettings) == "function" then fontPath, fontFlags, r, g, b, _, useShadow = _G.MSUF_GetGlobalFontSettings() end
    if fs.SetFont then
        local px = max(7, tonumber(size) or 10)
        local flags = fontFlags or "OUTLINE"
        local path = fontPath or FONT
        local resolveSafe = _G.MSUF_ResolveSafeFontPath
        if type(resolveSafe) == "function" then
            local gdb = _G.MSUF_DB and _G.MSUF_DB.general
            path = resolveSafe(path, px, flags, gdb and gdb.fontKey)
        end
        local ok = pcall(fs.SetFont, fs, path, px, flags)
        if not ok then
            pcall(fs.SetFont, fs, FONT, px, flags)
        end
    end
    if fs.SetTextColor then fs:SetTextColor(r or 1, g or 1, b or 1, 1) end
    if fs.SetShadowOffset then fs:SetShadowOffset(useShadow and 1 or 0, useShadow and -1 or 0) end
end
local function PlaceAuraPreviewText(fs, icon, anchor, x, y)
    if not (fs and icon) then return end
    anchor = tostring(anchor or "CENTER"):upper()
    x = tonumber(x) or 0
    y = tonumber(y) or 0
    fs:ClearAllPoints()
    fs:SetPoint(anchor, icon, anchor, x, y)
    if anchor == "TOPLEFT" or anchor == "LEFT" or anchor == "BOTTOMLEFT" then
        fs:SetJustifyH("LEFT")
    elseif anchor == "TOPRIGHT" or anchor == "RIGHT" or anchor == "BOTTOMRIGHT" then
        fs:SetJustifyH("RIGHT")
    else
        fs:SetJustifyH("CENTER")
    end
    if fs.SetJustifyV then
        if anchor == "TOPLEFT" or anchor == "TOP" or anchor == "TOPRIGHT" then
            fs:SetJustifyV("TOP")
        elseif anchor == "BOTTOMLEFT" or anchor == "BOTTOM" or anchor == "BOTTOMRIGHT" then
            fs:SetJustifyV("BOTTOM")
        else
            fs:SetJustifyV("MIDDLE")
        end
    end
end
local function RefreshMiniAuraPreviewNow(refreshPreview)
    if AurasMenuCombatLocked() then return end
    if type(refreshPreview) ~= "function" then return end
    refreshPreview()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if not AurasMenuCombatLocked() then refreshPreview() end
        end)
    end
end
local function GroupAuraPreviewDefaultSize(scope, lane)
    if scope == "raid" or scope == "mythicraid" then return 16 end
    return lane == "buff" and 22 or 20
end
local function ReadMiniAuraPreviewConfig(scope, lane, width, height)
    local isGroup = IsGroupScope(scope)
    local cfg = {
        size = 24,
        spacing = 2,
        perRow = 7,
        maxIcons = 14,
        showStacks = true,
        showTimers = true,
        showSwipe = true,
        cooldownSwipeReverse = false,
        stackSize = 10,
        stackAnchor = "TOPRIGHT",
        stackX = -1,
        stackY = -1,
        cooldownSize = 9,
        cooldownAnchor = "CENTER",
        cooldownX = 0,
        cooldownY = 0,
        debuffBorderMode = "OFF",
        showDurationBar = false,
        durationBarHeight = 2,
        durationBarDisplay = "BAR_ONLY",
        durationBarPosition = "BOTTOM",
        durationBarDirection = "REMAINING",
        iconZoom = 100,
    }
    -- Shared icon style (border/shadow) is one global block; the preview
    -- mirrors it for every scope and lane, matching the live runtime stamp.
    -- A scope that opted out previews unstyled icons, matching its frames.
    local styleScopeOn = type(Model.IconStyleScopeEnabled) ~= "function" or Model.IconStyleScopeEnabled(scope)
    if type(Model.ReadBool) == "function" then
        cfg.styleBorderEnabled = styleScopeOn and Model.ReadBool("shared", "styleBorderEnabled", false) == true
        cfg.styleShadowEnabled = styleScopeOn and Model.ReadBool("shared", "styleShadowEnabled", false) == true
    end
    cfg.styleBorderStyle = type(Model.ReadBorderStyle) == "function" and Model.ReadBorderStyle("shared") or "SOLID"
    if type(Model.ReadNumber) == "function" then
        cfg.styleBorderThickness = Model.ReadNumber("shared", "styleBorderThickness", 1, 1, 8)
        cfg.styleShadowSize = Model.ReadNumber("shared", "styleShadowSize", 4, 1, 16)
    end
    if type(Model.ReadValue) == "function" then
        local bc = Model.ReadValue("shared", "styleBorderColor", nil)
        cfg.styleBorderColor = type(bc) == "table" and bc or nil
        local sc = Model.ReadValue("shared", "styleShadowColor", nil)
        cfg.styleShadowColor = type(sc) == "table" and sc or nil
    end
    if isGroup then
        local group = GFReadGroup(scope, lane or "debuff")
        local root = GFReadRoot(scope)
        cfg.iconZoom = tonumber(group.iconZoom) or tonumber(root and root.iconZoom) or 100
        local iconScale = ClampNumber(group.iconScale, 100, 20, 300) / 100
        cfg.size = (tonumber(group.size) or GroupAuraPreviewDefaultSize(scope, lane)) * iconScale
        cfg.allowTinyIconScale = true
        cfg.spacing = tonumber(group.spacing) or 1
        cfg.perRow = tonumber(group.perRow) or (lane == "buff" and 4 or 3)
        cfg.maxIcons = tonumber(group.max) or cfg.perRow * 2
        cfg.showStacks = group.showStacks ~= false
        cfg.showTimers = group.showCooldown ~= false
        cfg.showSwipe = group.showCooldownSwipe ~= false
        cfg.cooldownSwipeReverse = group.cooldownSwipeReverse == true
        cfg.stackSize = tonumber(group.stackSize) or 10
        cfg.stackAnchor = group.stackAnchor or "BOTTOMRIGHT"
        cfg.stackX = tonumber(group.stackX) or 0
        cfg.stackY = tonumber(group.stackY) or 0
        cfg.cooldownSize = tonumber(group.cooldownSize) or 8
        cfg.cooldownAnchor = group.cooldownAnchor or "CENTER"
        cfg.cooldownX = tonumber(group.cooldownX) or 0
        cfg.cooldownY = tonumber(group.cooldownY) or 0
        cfg.cooldownDecimalSeconds = tonumber(group.cooldownDecimalSeconds) or 3
        local growthX, growthY = tostring(group.growthX or "RIGHT"), tostring(group.growthY or "DOWN")
        cfg.growth = (growthX == "UP" or growthX == "DOWN") and growthX or (growthX .. growthY)
        cfg.showDurationBar = group.showDurationBar == true
        cfg.durationBarHeight = tonumber(group.durationBarHeight) or 2
        cfg.durationBarDisplay = group.durationBarDisplay == "OVERLAY" and "OVERLAY" or "BAR_ONLY"
        cfg.durationBarPosition = group.durationBarPosition == "TOP" and "TOP" or "BOTTOM"
        cfg.durationBarDirection = group.durationBarDirection == "ELAPSED" and "ELAPSED" or "REMAINING"
        if lane == "debuff" then cfg.debuffBorderMode = ReadGroupDebuffTypeBorderMode(scope, "debuff") end
    else
        local readScope = scope or "shared"
        local runtimePreview = (readScope ~= "shared" and type(Model.ReadPreviewConfig) == "function") and Model.ReadPreviewConfig(readScope) or nil
        if lane == "buff" then
            cfg.size = tonumber(runtimePreview and runtimePreview.buffSize) or Model.ReadNumber(readScope, LaneSizeKey(lane), 26, 10, 128)
            cfg.perRow = tonumber(runtimePreview and runtimePreview.buffPerRow) or Model.ReadLanePerRow(readScope, lane)
            cfg.maxIcons = tonumber(runtimePreview and runtimePreview.maxBuffs) or Model.ReadNumber(readScope, LaneMaxKey(lane), LaneDefaultMax(lane), 0, 80)
        elseif lane == "debuff" then
            cfg.size = tonumber(runtimePreview and runtimePreview.debuffSize) or Model.ReadNumber(readScope, LaneSizeKey(lane), 26, 10, 128)
            cfg.perRow = tonumber(runtimePreview and runtimePreview.debuffPerRow) or Model.ReadLanePerRow(readScope, lane)
            cfg.maxIcons = tonumber(runtimePreview and runtimePreview.maxDebuffs) or Model.ReadNumber(readScope, LaneMaxKey(lane), LaneDefaultMax(lane), 0, 80)
        else
            cfg.size = Model.ReadNumber(readScope, "iconSize", 26, 10, 128)
            cfg.perRow = tonumber(runtimePreview and runtimePreview.perRow) or Model.ReadNumber(readScope, "perRow", 12, 1, 40)
            cfg.maxIcons = cfg.perRow * 2
        end
        cfg.spacing = tonumber(runtimePreview and runtimePreview.spacing) or Model.ReadNumber(readScope, "spacing", 2, 0, 12)
        cfg.iconZoom = lane and Model.ReadLaneStyleNumber(readScope, lane, "iconZoom", 100, 100, 200)
            or Model.ReadNumber(readScope, "iconZoom", 100, 100, 200)
        cfg.growth = lane and type(Model.ReadLaneGrowthPair) == "function" and Model.ReadLaneGrowthPair(readScope, lane) or "RIGHTDOWN"
        if type(Model.ReadLaneStyleBool) == "function" and lane then
            cfg.showStacks = Model.ReadLaneStyleBool(readScope, lane, "showStackCount", true)
            cfg.showTimers = Model.ReadLaneStyleBool(readScope, lane, "showCooldownText", true)
            cfg.showSwipe = Model.ReadLaneStyleBool(readScope, lane, "showCooldownSwipe", true)
            cfg.cooldownSwipeReverse = Model.ReadLaneStyleBool(readScope, lane, "cooldownSwipeReverse", false)
            cfg.showDurationBar = Model.ReadLaneStyleBool(readScope, lane, "showDurationBar", false)
        else
            cfg.showStacks = Model.ReadBool(readScope, "showStackCount", true)
            cfg.showTimers = Model.ReadBool(readScope, "showCooldownText", true)
            cfg.showSwipe = Model.ReadBool(readScope, "showCooldownSwipe", true)
            cfg.cooldownSwipeReverse = Model.ReadBool(readScope, "cooldownSwipeReverse", false)
            cfg.showDurationBar = Model.ReadBool(readScope, "showDurationBar", false)
        end
        cfg.stackSize = lane and Model.ReadLaneStyleNumber(readScope, lane, "stackTextSize", 14, 6, 40) or Model.ReadNumber(readScope, "stackTextSize", 14, 6, 40)
        cfg.stackAnchor = lane and type(Model.ReadLaneStackAnchor) == "function" and Model.ReadLaneStackAnchor(readScope, lane) or Model.ReadStackAnchor(readScope)
        cfg.stackX = lane and Model.ReadLaneStyleNumber(readScope, lane, "stackTextOffsetX", -1, -2000, 2000) or Model.ReadNumber(readScope, "stackTextOffsetX", -1, -2000, 2000)
        cfg.stackY = lane and Model.ReadLaneStyleNumber(readScope, lane, "stackTextOffsetY", 1, -2000, 2000) or Model.ReadNumber(readScope, "stackTextOffsetY", 1, -2000, 2000)
        cfg.cooldownSize = lane and Model.ReadLaneStyleNumber(readScope, lane, "cooldownTextSize", 14, 6, 40) or Model.ReadNumber(readScope, "cooldownTextSize", 14, 6, 40)
        if lane and type(Model.ReadLaneCooldownAnchor) == "function" then
            cfg.cooldownAnchor = Model.ReadLaneCooldownAnchor(readScope, lane)
        elseif type(Model.ReadCooldownAnchor) == "function" then
            cfg.cooldownAnchor = Model.ReadCooldownAnchor(readScope)
        elseif runtimePreview and runtimePreview.cooldownAnchor then
            cfg.cooldownAnchor = runtimePreview.cooldownAnchor
        end
        cfg.cooldownX = lane and Model.ReadLaneStyleNumber(readScope, lane, "cooldownTextOffsetX", 0, -2000, 2000) or Model.ReadNumber(readScope, "cooldownTextOffsetX", 0, -2000, 2000)
        cfg.cooldownY = lane and Model.ReadLaneStyleNumber(readScope, lane, "cooldownTextOffsetY", 0, -2000, 2000) or Model.ReadNumber(readScope, "cooldownTextOffsetY", 0, -2000, 2000)
        cfg.cooldownDecimalSeconds = lane and Model.ReadLaneStyleNumber(readScope, lane, "cooldownDecimalSeconds", 3, 0, 30) or Model.ReadNumber(readScope, "cooldownDecimalSeconds", 3, 0, 30)
        cfg.durationBarHeight = lane and Model.ReadLaneStyleNumber(readScope, lane, "durationBarHeight", 2, 1, 16) or Model.ReadNumber(readScope, "durationBarHeight", 2, 1, 16)
        if lane and type(Model.ReadLaneDurationBarDisplay) == "function" then
            cfg.durationBarDisplay = Model.ReadLaneDurationBarDisplay(readScope, lane)
        else
            cfg.durationBarDisplay = Model.ReadValue(readScope, "durationBarDisplay", "BAR_ONLY")
        end
        if lane and type(Model.ReadLaneDurationBarPosition) == "function" then
            cfg.durationBarPosition = Model.ReadLaneDurationBarPosition(readScope, lane)
        else
            cfg.durationBarPosition = Model.ReadValue(readScope, "durationBarPosition", "BOTTOM")
        end
        if lane and type(Model.ReadLaneDurationBarDirection) == "function" then
            cfg.durationBarDirection = Model.ReadLaneDurationBarDirection(readScope, lane)
        else
            cfg.durationBarDirection = Model.ReadValue(readScope, "durationBarDirection", "REMAINING")
        end
        if lane == "debuff" then
            if type(Model.ReadDebuffTypeBorderMode) == "function" then
                cfg.debuffBorderMode = Model.ReadDebuffTypeBorderMode(readScope)
            elseif type(Model.ReadLaneStyleBool) == "function" then
                cfg.debuffBorderMode = Model.ReadLaneStyleBool(readScope, "debuff", "useDebuffTypeBorders", false) and "SYMBOL" or "OFF"
            end
        end
    end
    local maxSize = max(12, min(128, floor((height or 104) - 38), floor((width or 300) - 20)))
    cfg.actualSize = max(cfg.allowTinyIconScale == true and 1 or 10, tonumber(cfg.size) or 24)
    cfg.size = min(maxSize, cfg.actualSize)
    cfg.spacing = min(10, max(0, tonumber(cfg.spacing) or 2))
    cfg.perRow = max(1, Round(cfg.perRow))
    cfg.maxIcons = max(0, Round(cfg.maxIcons))
    local maxCols = max(1, floor(((width or 300) - 20 + cfg.spacing) / max(1, cfg.size + cfg.spacing)))
    cfg.columns = min(cfg.perRow, maxCols)
    cfg.maxRows = max(1, floor(((height or 104) - 38 + cfg.spacing) / max(1, cfg.size + cfg.spacing)))
    local vertical = cfg.growth == "UP" or cfg.growth == "DOWN"
    cfg.rowsPerColumn = cfg.maxRows
    cfg.columns = vertical and 1 or cfg.columns
    cfg.count = min(14, cfg.maxIcons, cfg.columns * cfg.rowsPerColumn)
    if index == 4 and #entries > 0 then cfg.count = min(cfg.count, #entries) end
    cfg.stackSize = max(7, tonumber(cfg.stackSize) or 10)
    cfg.cooldownSize = max(7, tonumber(cfg.cooldownSize) or 9)
    cfg.cooldownDecimalSeconds = min(30, max(0, tonumber(cfg.cooldownDecimalSeconds) or 3))
    cfg.durationBarHeight = min(max(1, tonumber(cfg.durationBarHeight) or 2), max(1, floor((cfg.size or 24) / 2)))
    cfg.durationBarDisplay = cfg.durationBarDisplay == "OVERLAY" and "OVERLAY" or "BAR_ONLY"
    cfg.durationBarPosition = cfg.durationBarPosition == "TOP" and "TOP" or "BOTTOM"
    cfg.durationBarDirection = cfg.durationBarDirection == "ELAPSED" and "ELAPSED" or "REMAINING"
    return cfg
end
local function ReadCustomAuraPreviewConfig(scope, index, width, height)
    local item = Model.CustomContainer(scope, index, true)
    local placed = item and type(item.placed) == "table" and item.placed or {}
    local entries = type(Model.CustomContainerSpellEntries) == "function" and Model.CustomContainerSpellEntries(scope, index) or {}
    local cfg = {
        size = tonumber(placed.size) or 24,
        spacing = tonumber(placed.spacing) or 2,
        perRow = tonumber(placed.perRow) or 4,
        maxIcons = tonumber(placed.max) or 8,
        alpha = min(1, max(0, tonumber(placed.alpha) or 1)),
        iconZoom = min(200, max(100, tonumber(placed.iconZoom) or 100)),
        showStacks = placed.showStacks ~= false,
        showTimers = placed.showCooldown ~= false,
        showSwipe = placed.showCooldownSwipe ~= false,
        cooldownSwipeReverse = placed.cooldownSwipeReverse == true,
        stackSize = tonumber(placed.stackSize) or 14,
        stackAnchor = placed.stackAnchor or "BOTTOMRIGHT",
        stackX = tonumber(placed.stackX) or 0,
        stackY = tonumber(placed.stackY) or 0,
        cooldownSize = tonumber(placed.cooldownSize) or 14,
        cooldownAnchor = placed.cooldownAnchor or "CENTER",
        cooldownX = tonumber(placed.cooldownX) or 0,
        cooldownY = tonumber(placed.cooldownY) or 0,
        cooldownDecimalSeconds = tonumber(placed.cooldownDecimalSeconds) or 3,
        debuffBorderMode = NormalizeDebuffTypeBorderMode(placed.debuffTypeBorderMode, "OFF"),
        showDurationBar = placed.showDurationBar == true,
        durationBarHeight = tonumber(placed.durationBarHeight) or 2,
        durationBarDisplay = placed.durationBarDisplay == "OVERLAY" and "OVERLAY" or "BAR_ONLY",
        durationBarPosition = placed.durationBarPosition == "TOP" and "TOP" or "BOTTOM",
        durationBarDirection = placed.durationBarDirection == "ELAPSED" and "ELAPSED" or "REMAINING",
        growth = placed.growth or "LEFTDOWN",
        isBuff = not item or item.auraType ~= "DEBUFF",
        previewTextures = {},
    }
    -- Custom lanes use the same shared border/shadow scope as their live
    -- AuraButtons. Keep their Style-page sample on that exact contract.
    local styleScopeOn = type(Model.IconStyleScopeEnabled) ~= "function" or Model.IconStyleScopeEnabled(scope)
    if type(Model.ReadBool) == "function" then
        cfg.styleBorderEnabled = styleScopeOn and Model.ReadBool("shared", "styleBorderEnabled", false) == true
        cfg.styleShadowEnabled = styleScopeOn and Model.ReadBool("shared", "styleShadowEnabled", false) == true
    end
    cfg.styleBorderStyle = type(Model.ReadBorderStyle) == "function" and Model.ReadBorderStyle("shared") or "SOLID"
    if type(Model.ReadNumber) == "function" then
        cfg.styleBorderThickness = Model.ReadNumber("shared", "styleBorderThickness", 1, 1, 8)
        cfg.styleShadowSize = Model.ReadNumber("shared", "styleShadowSize", 4, 1, 16)
    end
    if type(Model.ReadValue) == "function" then
        local bc = Model.ReadValue("shared", "styleBorderColor", nil)
        cfg.styleBorderColor = type(bc) == "table" and bc or nil
        local sc = Model.ReadValue("shared", "styleShadowColor", nil)
        cfg.styleShadowColor = type(sc) == "table" and sc or nil
    end
    for i = 1, #entries do cfg.previewTextures[i] = entries[i] and entries[i].icon end
    local maxSize = max(12, min(128, floor((height or 104) - 38), floor((width or 300) - 20)))
    cfg.actualSize = max(8, cfg.size)
    cfg.size = min(maxSize, cfg.actualSize)
    cfg.spacing = min(24, max(0, cfg.spacing))
    cfg.perRow = max(1, Round(cfg.perRow))
    cfg.maxIcons = max(0, Round(cfg.maxIcons))
    local maxCols = max(1, floor(((width or 300) - 20 + cfg.spacing) / max(1, cfg.size + cfg.spacing)))
    cfg.columns = min(cfg.perRow, maxCols)
    cfg.maxRows = max(1, floor(((height or 104) - 38 + cfg.spacing) / max(1, cfg.size + cfg.spacing)))
    local vertical = cfg.growth == "UP" or cfg.growth == "DOWN"
    cfg.rowsPerColumn = cfg.maxRows
    cfg.columns = vertical and 1 or cfg.columns
    cfg.count = min(14, cfg.maxIcons, cfg.columns * cfg.rowsPerColumn)
    cfg.stackSize = max(7, cfg.stackSize)
    cfg.cooldownSize = max(7, cfg.cooldownSize)
    cfg.cooldownDecimalSeconds = min(30, max(0, cfg.cooldownDecimalSeconds))
    cfg.durationBarHeight = min(max(1, cfg.durationBarHeight), max(1, floor(cfg.size / 2)))
    return cfg
end
local function FormatAuraPreviewTimer(seconds, cfg)
    seconds = tonumber(seconds) or 0
    local decimalSec = tonumber(cfg and cfg.cooldownDecimalSeconds) or 3
    if decimalSec > 0 and seconds < decimalSec then return string.format("%.1f", seconds) end
    if seconds >= 60 then return tostring(max(1, floor(seconds / 60))) end
    return tostring(Round(seconds))
end
local function BuildMiniAuraPreview(ctx, parent, scope, x, y, width, height, lane, opts)
    if ctx and ctx.hiddenBuild then return nil end
    opts = opts or {}
    lane = lane == "buff" and "buff" or (lane == "debuff" and "debuff" or nil)
    local box = T.Panel(parent, nil, { 0.010, 0.016, 0.034, 0.88 }, T.colors.borderSoft)
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    box:SetSize(width or 300, height or 104)
    local innerPad = T.Space("md", 12)
    local titleLabel = W.LabelAt(box, opts.title or "Sample Preview", innerPad, -innerPad, 240, "GameFontNormalSmall", T.colors.text)
    local meta
    if opts.focused == true then
        meta = T.Font(box, "GameFontDisableSmall", "", T.colors.muted)
        meta:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", innerPad, T.Space("sm", 8))
        meta:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -innerPad, T.Space("sm", 8))
        meta:SetJustifyH("LEFT")
        if meta.SetMaxLines then meta:SetMaxLines(1) end
        if meta.SetWordWrap then meta:SetWordWrap(false) end
    end
    local icons = {}
    local iconCapacity = opts.focused == true and 0 or min(14, max(1, tonumber(opts.iconCapacity) or 14))
    for i = 1, iconCapacity do icons[i] = CreateAuraPreviewIcon(box) end
    local function EnsureIconCapacity(count)
        count = min(opts.focused == true and 80 or iconCapacity, max(0, Round(count)))
        for i = #icons + 1, count do icons[i] = CreateAuraPreviewIcon(box) end
        return count
    end
    local buffTex = { 135987, 136116, 135932, 136085, 132333, 135981, 136048 }
    local debuffTex = { 136118, 136139, 136197, 135817, 132851, 136188, 136170 }
    local function HidePreviewIcon(icon)
        icon:Hide()
        icon.swipe:Hide()
        icon.durationBar:Hide()
        icon.dispelBorder:Hide()
        if icon.msufStyleBorder then icon.msufStyleBorder:Hide() end
        if icon.msufStyleBorderPieces then MSUF.BorderStyles.Hide(icon.msufStyleBorderPieces) end
        if icon.msufStyleShadow then MSUF.BorderStyles.Hide(icon.msufStyleShadow) end
    end
    -- Mirrors the runtime's icon style: a BACKGROUND(-7) soft shadow band and a
    -- BORDER(-1) ring that is either the flat pixel quad (Solid) or an edgeFile
    -- drawn by the shared 8-piece renderer.
    local function ApplyPreviewIconStyle(icon, cfg, barOnly)
        local B = MSUF.BorderStyles
        local border = icon.msufStyleBorder
        local borderPieces = icon.msufStyleBorderPieces
        local texture = B and cfg.styleBorderStyle and B.Resolve(cfg.styleBorderStyle) or nil
        if cfg.styleBorderEnabled == true and not barOnly then
            local c = cfg.styleBorderColor
            local cr, cg, cb, ca = c and c[1] or 0, c and c[2] or 0, c and c[3] or 0, c and c[4] or 1
            local t = cfg.styleBorderThickness or 1
            if texture then
                if border then border:Hide() end
                -- Same split as the runtime: inner styles shade the icon from
                -- ARTWORK(7) on top, outer styles frame it from BORDER(-1).
                local inner = B.Placement(cfg.styleBorderStyle) == "inner"
                local edge = B.EdgeSize(cfg.styleBorderStyle, t)
                local inset = 0
                if inner then
                    edge = max(1, min(edge, floor(cfg.size * 0.3)))
                    inset = edge * 0.5
                end
                if borderPieces and icon.msufStyleBorderInner ~= inner then
                    B.Hide(borderPieces)
                    borderPieces = nil
                end
                if not borderPieces then
                    borderPieces = B.Create(icon, inner and "ARTWORK" or "BORDER", inner and 7 or -1, texture)
                    icon.msufStyleBorderPieces = borderPieces
                    icon.msufStyleBorderInner = inner
                else
                    B.SetTexture(borderPieces, texture)
                end
                B.Apply(borderPieces, icon, edge, cfg.size, cfg.size, cr, cg, cb, ca, inset)
            else
                if borderPieces then B.Hide(borderPieces) end
                if not border then
                    border = icon:CreateTexture(nil, "BORDER", nil, -1)
                    border:SetTexture("Interface\\Buttons\\WHITE8X8")
                    icon.msufStyleBorder = border
                end
                border:ClearAllPoints()
                border:SetPoint("TOPLEFT", icon, "TOPLEFT", -t, t)
                border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", t, -t)
                border:SetVertexColor(cr, cg, cb, ca)
                border:Show()
            end
        else
            if border then border:Hide() end
            if borderPieces then B.Hide(borderPieces) end
        end
        local shadow = icon.msufStyleShadow
        if cfg.styleShadowEnabled == true and not barOnly and B then
            if not shadow then
                shadow = B.Create(icon, "BACKGROUND", -7, M.AURA_SHADOW_TEXTURE)
                icon.msufStyleShadow = shadow
            end
            local base = cfg.styleBorderEnabled == true and (cfg.styleBorderThickness or 1) or 0
            local extent = (cfg.styleShadowSize or 4) + base
            local c = cfg.styleShadowColor
            B.Apply(shadow, icon, extent * 2, cfg.size, cfg.size,
                c and c[1] or 0, c and c[2] or 0, c and c[3] or 0, c and c[4] or 0.8)
        elseif shadow then
            B.Hide(shadow)
        end
    end
    local function RenderPreviewIcon(icon, index, cfg, isBuffIcon, forceText)
        icon:SetSize(cfg.size, cfg.size)
        icon:SetAlpha(tonumber(cfg.alpha) or 1)
        local barOnly = cfg.showDurationBar == true and cfg.durationBarDisplay == "BAR_ONLY"
        local tex = isBuffIcon and buffTex or debuffTex
        local previewTextures = cfg.previewTextures
        local previewTexture = previewTextures and previewTextures[((index - 1) % max(1, #previewTextures)) + 1]
        icon.icon:SetTexture(previewTexture or tex[((index - 1) % #tex) + 1])
        ApplyAuraPreviewIconZoom(icon.icon, cfg.iconZoom)
        icon.bg:SetShown(not barOnly)
        icon.icon:SetShown(not barOnly)
        ApplyPreviewIconStyle(icon, cfg, barOnly)
        local r, g, b = isBuffIcon and 0.20 or 0.78, isBuffIcon and 0.72 or 0.20, isBuffIcon and 0.42 or 0.24
        local borderAtlas = (not barOnly and not isBuffIcon) and DEBUFF_TYPE_BORDER_PREVIEW_ATLAS[cfg.debuffBorderMode] or nil
        local showPreviewEdges = isBuffIcon == true and not barOnly
        for _, edge in pairs(icon.edge) do edge:SetShown(showPreviewEdges); edge:SetVertexColor(r, g, b, 0.95) end
        icon.swipe:SetShown(cfg.showSwipe ~= false and not barOnly)
        icon.swipe:ClearAllPoints()
        if cfg.cooldownSwipeReverse == true then
            icon.swipe:SetPoint("TOPRIGHT", icon, "TOP", 0, -1)
            icon.swipe:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", 1, 1)
        else
            icon.swipe:SetPoint("TOPLEFT", icon, "TOP", 0, -1)
            icon.swipe:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
        end
        if borderAtlas and icon.dispelBorder.SetAtlas then
            local pad = max(1, floor((cfg.size / 24) + 0.5))
            icon.dispelBorder:ClearAllPoints()
            icon.dispelBorder:SetPoint("TOPLEFT", icon, "TOPLEFT", -pad, pad)
            icon.dispelBorder:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", pad, -pad)
            icon.dispelBorder:SetAtlas(borderAtlas, TextureKitConstants and TextureKitConstants.IgnoreAtlasSize)
            icon.dispelBorder:Show()
        else
            icon.dispelBorder:Hide()
        end
        if cfg.showDurationBar == true then
            local inset = max(1, floor((cfg.size / 32) + 0.5))
            icon.durationBar:ClearAllPoints()
            icon.durationBar:SetHeight(cfg.durationBarHeight or 2)
            if cfg.durationBarPosition == "TOP" then
                icon.durationBar:SetPoint("TOPLEFT", icon, "TOPLEFT", inset, -inset)
                icon.durationBar:SetPoint("TOPRIGHT", icon, "TOPRIGHT", -inset, -inset)
            else
                icon.durationBar:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", inset, inset)
                icon.durationBar:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -inset, inset)
            end
            local r, g, b = AuraDurationBarColor()
            icon.durationBar:SetVertexColor(r, g, b, 0.92)
            icon.durationBar:Show()
        else
            icon.durationBar:Hide()
        end
        ApplyAuraPreviewFont(icon.stack, cfg.stackSize)
        ApplyAuraPreviewFont(icon.timer, cfg.cooldownSize)
        PlaceAuraPreviewText(icon.stack, icon, cfg.stackAnchor, cfg.stackX, cfg.stackY)
        PlaceAuraPreviewText(icon.timer, icon, cfg.cooldownAnchor, cfg.cooldownX, cfg.cooldownY)
        icon.stack:SetText(cfg.showStacks and ((forceText or index % 3 == 1) and "2" or "") or "")
        local sampleSeconds = forceText and 2.7 or (index % 2 == 0 and 12 or nil)
        icon.timer:SetText(cfg.showTimers and sampleSeconds and FormatAuraPreviewTimer(sampleSeconds, cfg) or "")
        icon:Show()
    end
    local function RefreshPreview()
        if AurasMenuCombatLocked() then return end
        if opts.focused == true and parent.IsShown and not parent:IsShown() then return end
        local previewScope = type(opts.getPreviewScope) == "function" and opts.getPreviewScope() or scope
        if not AURA_SCOPE_VALID[previewScope] then previewScope = scope end
        local mode = type(opts.getMode) == "function" and opts.getMode() or "sample"
        local function HideSamples()
            for i = 1, #icons do HidePreviewIcon(icons[i]) end
        end
        local function HideLive()
            local live = box._msufA3MenuPreviewContainer
            if not live then return end
            if A3 and type(A3._HideLane) == "function" then A3._HideLane(live)
            elseif live.Hide then live:Hide() end
        end
        if opts.focused == true and mode == "live" then
            HideSamples()
            local liveHeight = max(80, (tonumber(height) or 104) - T.Space("xxl", 32))
            local ok, reason = type(A3.UpdateMenuAuraPreview) == "function"
                and A3.UpdateMenuAuraPreview(box, previewScope, lane, width, liveHeight)
            local label = ScopeLabel(previewScope)
            titleLabel:SetText(M.Format("%s Live Preview", label))
            if ok then
                meta:SetText(M.Format("Live %s auras. An empty canvas means no matching aura is active.", label))
            elseif reason == "combat" then
                meta:SetText(Tr("Live preview updates after combat. Sample mode remains available."))
            elseif reason == "no-group-frame" then
                meta:SetText(M.Format("No live %s member is currently available.", label))
            else
                meta:SetText(Tr("Live preview is unavailable for this container. Sample mode remains available."))
            end
            return
        end
        HideLive()
        if opts.focused == true then
            local cfg = opts.customIndex and ReadCustomAuraPreviewConfig(previewScope, opts.customIndex, width, height)
                or ReadMiniAuraPreviewConfig(previewScope, lane, width, height)
            local count = EnsureIconCapacity(cfg.maxIcons)
            local naturalSize = max(1, tonumber(cfg.actualSize) or tonumber(cfg.size) or 24)
            local naturalGap = max(0, tonumber(cfg.spacing) or 0)
            local boxW, boxH = width or 300, height or 104
            local headerH = T.Space("xxl", 32) + T.Space("optical", 2)
            local footerH = T.Space("xxl", 32) - T.Space("optical", 2)
            local availableW = max(1, boxW - innerPad * 2)
            local availableH = max(1, boxH - headerH - footerH)
            local growth = tostring(cfg.growth or "RIGHTDOWN"):upper()
            local vertical = growth == "UP" or growth == "DOWN"
            local perLine = max(1, Round(cfg.perRow or count or 1))
            local columns, rows
            if count <= 0 then
                columns, rows = 1, 1
            elseif vertical then
                rows = min(perLine, count)
                columns = max(1, ceil(count / rows))
            else
                columns = min(perLine, count)
                rows = max(1, ceil(count / columns))
            end
            local naturalW = columns * naturalSize + max(0, columns - 1) * naturalGap
            local naturalH = rows * naturalSize + max(0, rows - 1) * naturalGap
            local scale = min(1, availableW / max(1, naturalW), availableH / max(1, naturalH))
            cfg.size = max(2, naturalSize * scale)
            cfg.spacing = naturalGap * scale
            cfg.stackSize = max(5, (tonumber(cfg.stackSize) or 10) * scale)
            cfg.cooldownSize = max(5, (tonumber(cfg.cooldownSize) or 9) * scale)
            cfg.durationBarHeight = max(1, (tonumber(cfg.durationBarHeight) or 2) * scale)
            local totalW = columns * cfg.size + max(0, columns - 1) * cfg.spacing
            local totalH = rows * cfg.size + max(0, rows - 1) * cfg.spacing
            local startX = innerPad + max(0, (availableW - totalW) * 0.5)
            local startY = -(headerH + max(0, (availableH - totalH) * 0.5))
            local left = growth:find("LEFT", 1, true) ~= nil
            local up = growth:find("UP", 1, true) ~= nil
            for i = 1, #icons do
                local icon = icons[i]
                if i <= count then
                    local col, row
                    if vertical then
                        row = (i - 1) % rows
                        col = floor((i - 1) / rows)
                    else
                        col = (i - 1) % columns
                        row = floor((i - 1) / columns)
                    end
                    if left then col = columns - 1 - col end
                    if up then row = rows - 1 - row end
                    icon:ClearAllPoints()
                    icon:SetPoint("TOPLEFT", box, "TOPLEFT",
                        startX + col * (cfg.size + cfg.spacing),
                        startY - row * (cfg.size + cfg.spacing))
                    RenderPreviewIcon(icon, i, cfg, opts.customIndex and cfg.isBuff or lane == "buff", false)
                else
                    HidePreviewIcon(icon)
                end
            end
            local label = ScopeLabel(previewScope)
            titleLabel:SetText(label .. " Sample Preview")
            if type(opts.getSampleMeta) == "function" then
                meta:SetText(opts.getSampleMeta(cfg, previewScope) or "")
            else
                meta:SetText(label .. " / " .. tostring(Round(cfg.actualSize or cfg.size or 0)) .. "px")
            end
            return
        end
        if meta then meta:SetText("") end
        local cfg = opts.customIndex and ReadCustomAuraPreviewConfig(previewScope, opts.customIndex, width, height)
            or ReadMiniAuraPreviewConfig(previewScope, lane, width, height)
        for i = 1, #icons do
            local icon = icons[i]
            if i <= cfg.count then
                local growth = tostring(cfg.growth or "RIGHTDOWN"):upper()
                local vertical = growth == "UP" or growth == "DOWN"
                local col = vertical and floor((i - 1) / max(1, cfg.rowsPerColumn)) or ((i - 1) % cfg.columns)
                local row = vertical and ((i - 1) % max(1, cfg.rowsPerColumn)) or floor((i - 1) / cfg.columns)
                local left = growth:find("LEFT", 1, true) ~= nil
                local up = growth:find("UP", 1, true) ~= nil
                local startX = left and ((width or 300) - 10 - cfg.size) or 10
                local startY = up and (-((height or 104) - 10 - cfg.size)) or -34
                local step = cfg.size + cfg.spacing
                icon:ClearAllPoints()
                icon:SetPoint("TOPLEFT", box, "TOPLEFT", startX + col * step * (left and -1 or 1), startY + row * step * (up and 1 or -1))
                local isBuffIcon = opts.customIndex and cfg.isBuff or (lane and lane == "buff" or (not lane and i <= 7))
                RenderPreviewIcon(icon, i, cfg, isBuffIcon, false)
            else
                HidePreviewIcon(icon)
            end
        end
    end
    M.TrackRefresh(ctx, RefreshPreview)
    return box, RefreshPreview
end
local function BuildLiveAuraPreview(ctx, parent, scope, laneKind, x, y, width, height)
    if ctx and ctx.hiddenBuild then return nil end
    local box = T.Panel(parent, nil, { 0.010, 0.016, 0.034, 0.88 }, T.colors.borderSoft)
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    box:SetSize(width or 300, height or 120)
    if box.SetClipsChildren then box:SetClipsChildren(true) end
    W.LabelAt(box, "Live Tracked Auras", 10, -10, 180, "GameFontNormalSmall", T.colors.accent)
    local status = W.Text(box, "", 194, -10, max(80, (width or 300) - 204), T.colors.muted)
    status:SetJustifyH("RIGHT")
    local function RefreshLive()
        local ok, reason = type(A3.UpdateMenuAuraPreview) == "function"
            and A3.UpdateMenuAuraPreview(box, scope, laneKind, width, height)
        if ok then
            status:SetText(Tr("Native · ") .. ScopeLabel(scope))
        elseif reason == "combat" then
            status:SetText(Tr("Updates after combat"))
        elseif reason == "no-group-frame" then
            status:SetText(Tr("No live member"))
        elseif tostring(laneKind):match("^custom[1234]$") then
            status:SetText(Tr("Disabled or whitelist empty"))
        else
            status:SetText(Tr("No matching aura active"))
        end
    end
    M.TrackRefresh(ctx, RefreshLive)
    box:HookScript("OnShow", function() RefreshLive() end)
    return box, RefreshLive
end
local EnsureCustomPreviewEffect
local RefreshCustomPreviewEffect
local RefreshAuraFrameEffectPreview
local function BuildAuraStylePreviewWorkbench(ctx, b, scope, lane)
    local rowY = -(T.Space("xxl", 32) + T.Space("md", 12))
    local panelY = rowY - T.Space("xxl", 32) - T.Space("optical", 2)
    local panelH = T.Space("xxl", 32) * 4 + T.Space("lg", 16) + T.Space("xs", 4)
    local sectionH = abs(panelY) + panelH + T.Space("lg", 16)
    local sectionId = "aura_style_" .. tostring(lane or "auras") .. "_preview"
    local section = b:CollapsibleSection(sectionId, "Preview", sectionH, true)
    local width = section._msuf2Width or b.width or 720
    local pad = T.Space("xl", 24)
    local labelW = T.Space("xl", 24) * 3 + T.Space("md", 12)
    W.LabelAt(section, "Preview as:", pad, rowY, labelW, "GameFontNormalSmall", T.colors.muted)

    local refreshPreview
    local function PreviewScope()
        return scope == "shared" and CurrentAuraPreviewScope() or scope
    end
    if scope == "shared" then
        local tabsW = min(620, max(336, width - (pad * 2) - labelW))
        BuildActionTabs(ctx, section, SHARED_PREVIEW_SCOPE_VALUES, pad + labelW, rowY + 4, tabsW,
            CurrentAuraPreviewScope,
            function(value)
                M.SetMenuStateValue("auraStylePreviewScope", value)
                if refreshPreview then refreshPreview() end
            end,
            T.Space("xs", 4), nil, "style.preview.scope")
    else
        W.LabelAt(section, ScopeLabel(scope), pad + labelW, rowY, 180, "GameFontNormalSmall", T.colors.accent)
    end

    local panelW = width - (pad * 2)
    local box
    box, refreshPreview = BuildMiniAuraPreview(ctx, section, scope, pad, panelY, panelW, panelH, lane, {
        focused = true,
        getPreviewScope = PreviewScope,
        getMode = CurrentAuraPreviewMode,
        getSampleMeta = function(cfg, previewScope)
            local source
            if previewScope == "party" or previewScope == "raid" then
                source = ScopeLabel(previewScope) .. " style"
            elseif Model.UseSharedVisuals(previewScope) then
                source = "Shared style"
            else
                source = "Own override"
            end
            local swipe = cfg.cooldownSwipeReverse == true and "Reverse swipe" or "Default swipe"
            return tostring(Round(cfg.actualSize or cfg.size or 0)) .. "px / " .. swipe .. " / " .. source
        end,
    })
    local refreshLanePreview = refreshPreview
    local function RefreshLaneFrameEffect()
        if box and type(RefreshAuraFrameEffectPreview) == "function" then
            RefreshAuraFrameEffectPreview(box, PreviewScope(), lane)
        end
    end
    refreshPreview = function()
        if type(refreshLanePreview) == "function" then refreshLanePreview() end
        RefreshLaneFrameEffect()
    end
    M.TrackRefresh(ctx, RefreshLaneFrameEffect)
    if box then
        local modeW = T.Space("xxl", 32) * 4 + T.Space("md", 12)
        local pinReserve = 90
        BuildActionTabs(ctx, box, AURA_PREVIEW_MODE_VALUES, panelW - T.Space("md", 12) - modeW - pinReserve, -8, modeW,
            CurrentAuraPreviewMode,
            function(value)
                M.SetMenuStateValue("auraStylePreviewMode", value == "live" and "live" or "sample")
                if refreshPreview then refreshPreview() end
            end,
            T.Space("xs", 4), nil, "style.preview.mode")
    end
    if box and W.AttachPinnedPreview then
        W.AttachPinnedPreview(section, box, {
            stateKey = "auraStylePreview",
            left = 14,
            right = 14,
            top = -8,
            buttonWidth = 78,
            buttonHeight = 20,
            centerButton = true,
            quietButton = true,
            pinnedHeight = panelH,
            pageKey = ctx and ctx.key,
            wrapper = ctx and ctx.wrapper,
            restoreParent = section,
            restorePoint = { "TOPLEFT", section, "TOPLEFT", pad, panelY },
            restoreWidth = panelW,
            restoreHeight = panelH,
        })
        RegisterAuraControl(ctx, box._msuf2PinButton, "Pin Aura Preview", "toggle",
            "style.preview.pin.toggle", "ephemeral")
    end
    local previewShowSerial = 0
    local function RefreshVisibleAuraPreview()
        if type(refreshPreview) ~= "function" then return end
        if ctx and ctx.key and M.activeKey and M.activeKey ~= ctx.key then return end
        if ctx and ctx.wrapper and ctx.wrapper.IsShown and not ctx.wrapper:IsShown() then return end
        if section.IsShown and not section:IsShown() then return end
        refreshPreview()
    end
    local function QueueVisibleAuraPreview()
        previewShowSerial = previewShowSerial + 1
        local serial = previewShowSerial
        RefreshVisibleAuraPreview()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if serial == previewShowSerial then RefreshVisibleAuraPreview() end
            end)
            C_Timer.After(0.05, function()
                if serial == previewShowSerial then RefreshVisibleAuraPreview() end
            end)
        end
    end
    if section.HookScript then
        section:HookScript("OnShow", QueueVisibleAuraPreview)
        section:HookScript("OnHide", function() previewShowSerial = previewShowSerial + 1 end)
    end
    if ctx and ctx.wrapper and ctx.wrapper.HookScript then
        ctx.wrapper:HookScript("OnShow", QueueVisibleAuraPreview)
    end
    QueueVisibleAuraPreview()
    return refreshPreview
end
local function BuildUnitStyle(ctx, b, scope)
    local unit = scope == "shared" and "shared" or scope
    local lane = CurrentLane("auraStyleGFLane", "debuff")
    local extraDebuffControls = lane == "debuff" and 64 or 0
    local styleControls = {}
    local refreshMiniPreview
    local function RefreshStylePreview()
        RefreshMiniAuraPreviewNow(refreshMiniPreview)
    end
    local function ReadScopeBool(key, defaultValue)
        if type(Model.ReadLaneStyleBool) == "function" then return Model.ReadLaneStyleBool(unit, lane, key, defaultValue) end
        if type(Model.ReadBool) == "function" then return Model.ReadBool(unit, key, defaultValue) end
        return Model.ReadSharedBool(key, defaultValue)
    end
    local function WriteScopeBool(key, value)
        if type(Model.WriteLaneStyleBool) == "function" then
            Model.WriteLaneStyleBool(unit, lane, key, value)
        elseif type(Model.WriteBool) == "function" then
            Model.WriteBool(unit, key, value)
        else
            Model.WriteSharedBool(key, value)
        end
    end
    local function ReadScopeDebuffBorderMode()
        if type(Model.ReadDebuffTypeBorderMode) == "function" then return Model.ReadDebuffTypeBorderMode(unit) end
        return ReadScopeBool("useDebuffTypeBorders", false) and "SYMBOL" or "OFF"
    end
    local function WriteScopeDebuffBorderMode(value)
        value = NormalizeDebuffTypeBorderMode(value, "OFF")
        if type(Model.WriteDebuffTypeBorderMode) == "function" then
            Model.WriteDebuffTypeBorderMode(unit, value)
        else
            WriteScopeBool("useDebuffTypeBorders", value ~= "OFF")
        end
    end
    local function ReadScopeNumber(key, defaultValue, minValue, maxValue)
        if type(Model.ReadLaneStyleNumber) == "function" then return Model.ReadLaneStyleNumber(unit, lane, key, defaultValue, minValue, maxValue) end
        return Model.ReadNumber(unit, key, defaultValue, minValue, maxValue)
    end
    local function WriteScopeNumber(key, value, minValue, maxValue)
        if type(Model.WriteLaneStyleNumber) == "function" then
            Model.WriteLaneStyleNumber(unit, lane, key, value, minValue, maxValue)
        else
            Model.WriteNumber(unit, key, value, minValue, maxValue)
        end
    end
    local function ReadScopeCooldownAnchor()
        if type(Model.ReadLaneCooldownAnchor) == "function" then return Model.ReadLaneCooldownAnchor(unit, lane) end
        if type(Model.ReadCooldownAnchor) == "function" then return Model.ReadCooldownAnchor(unit) end
        return "CENTER"
    end
    local function WriteScopeCooldownAnchor(value)
        if type(Model.WriteLaneCooldownAnchor) == "function" then
            Model.WriteLaneCooldownAnchor(unit, lane, value)
        elseif type(Model.WriteCooldownAnchor) == "function" then
            Model.WriteCooldownAnchor(unit, value)
        end
    end
    local function ReadScopeSwipeDirection()
        return ReadScopeBool("cooldownSwipeReverse", false) and "REVERSE" or "NORMAL"
    end
    local function WriteScopeSwipeDirection(value)
        WriteScopeBool("cooldownSwipeReverse", value == "REVERSE")
    end
    local function ReadScopeSortMethod()
        local value = type(Model.ReadLaneStyleString) == "function"
            and Model.ReadLaneStyleString(unit, lane, "sortMethod", "DEFAULT") or "DEFAULT"
        return NormalizeAuraSortMethodForLane(lane, value)
    end
    local function WriteScopeSortMethod(value)
        value = NormalizeAuraSortMethodForLane(lane, value)
        if type(Model.WriteLaneStyleString) == "function" then
            Model.WriteLaneStyleString(unit, lane, "sortMethod", value)
        end
    end
    local function ReadScopeSortDirection()
        return ReadScopeBool("sortReverse", false) and "REVERSE" or "NORMAL"
    end
    local function WriteScopeSortDirection(value)
        WriteScopeBool("sortReverse", value == "REVERSE")
    end
    local function ReadScopeDurationBarDisplay()
        if type(Model.ReadLaneDurationBarDisplay) == "function" then return Model.ReadLaneDurationBarDisplay(unit, lane) end
        local value = Model.ReadValue and Model.ReadValue(unit, "durationBarDisplay", "BAR_ONLY") or "BAR_ONLY"
        return value == "OVERLAY" and "OVERLAY" or "BAR_ONLY"
    end
    local function WriteScopeDurationBarDisplay(value)
        value = value == "OVERLAY" and "OVERLAY" or "BAR_ONLY"
        if type(Model.WriteLaneDurationBarDisplay) == "function" then
            Model.WriteLaneDurationBarDisplay(unit, lane, value)
        elseif type(Model.WriteValue) == "function" then
            Model.WriteValue(unit, "durationBarDisplay", value)
        end
    end
    local function ReadScopeDurationBarPosition()
        if type(Model.ReadLaneDurationBarPosition) == "function" then return Model.ReadLaneDurationBarPosition(unit, lane) end
        local value = Model.ReadValue and Model.ReadValue(unit, "durationBarPosition", "BOTTOM") or "BOTTOM"
        return value == "TOP" and "TOP" or "BOTTOM"
    end
    local function WriteScopeDurationBarPosition(value)
        value = value == "TOP" and "TOP" or "BOTTOM"
        if type(Model.WriteLaneDurationBarPosition) == "function" then
            Model.WriteLaneDurationBarPosition(unit, lane, value)
        elseif type(Model.WriteValue) == "function" then
            Model.WriteValue(unit, "durationBarPosition", value)
        end
    end
    local function ReadScopeDurationBarDirection()
        if type(Model.ReadLaneDurationBarDirection) == "function" then return Model.ReadLaneDurationBarDirection(unit, lane) end
        local value = Model.ReadValue and Model.ReadValue(unit, "durationBarDirection", "REMAINING") or "REMAINING"
        return value == "ELAPSED" and "ELAPSED" or "REMAINING"
    end
    local function WriteScopeDurationBarDirection(value)
        value = value == "ELAPSED" and "ELAPSED" or "REMAINING"
        if type(Model.WriteLaneDurationBarDirection) == "function" then
            Model.WriteLaneDurationBarDirection(unit, lane, value)
        elseif type(Model.WriteValue) == "function" then
            Model.WriteValue(unit, "durationBarDirection", value)
        end
    end
    local function AddStyleControl(control) M.AppendValues(styleControls, control); return control end
    local function BindStyleSwitch(parent, label, x, y, width, key, defaultValue, reason)
        return AddStyleControl(BindSwitch(ctx, parent, label, x, y, width,
            function() return ReadScopeBool(key, defaultValue) end,
            function(v)
                WriteScopeBool(key, v)
                ApplyUnit(ctx, unit, reason)
                RefreshStylePreview()
            end,
            AuraControlMeta(ctx, "style.lane." .. AuraCatalogToken(lane) .. "." .. AuraCatalogToken(key))))
    end
    local function BindStyleDropdown(parent, label, x, y, values, width, getValue, setValue, reason)
        return AddStyleControl(BindDropdown(ctx, parent, label, x, y, values, width,
            getValue,
            function(v)
                setValue(v)
                ApplyUnit(ctx, unit, reason)
                RefreshStylePreview()
            end,
            AuraControlMeta(ctx, "style.lane." .. AuraCatalogToken(lane) .. "." .. AuraCatalogToken(reason))))
    end
    local function BindStyleSlider(parent, label, x, y, minVal, maxVal, step, width, key, defaultValue, readMin, readMax, writeMin, writeMax, reason)
        readMin, readMax = readMin or minVal, readMax or maxVal
        writeMin, writeMax = writeMin or readMin, writeMax or readMax
        return AddStyleControl(BindSlider(ctx, parent, label, x, y, minVal, maxVal, step, width,
            function() return ReadScopeNumber(key, defaultValue, readMin, readMax) end,
            function(v)
                WriteScopeNumber(key, v, writeMin, writeMax)
                ApplyUnit(ctx, unit, reason)
                RefreshStylePreview()
            end,
            AuraControlMeta(ctx, "style.lane." .. AuraCatalogToken(lane) .. "." .. AuraCatalogToken(key))))
    end
    local function BodyWidth(body)
        return body and (body._msuf2Width or body.GetWidth and body:GetWidth()) or b.width or 720
    end
    local baseId = "aura_style_" .. tostring(scope or "shared") .. "_" .. lane

    refreshMiniPreview = BuildAuraStylePreviewWorkbench(ctx, b, unit, lane)

    local scaling = b:CollapsibleSection(baseId .. "_scaling", "Scaling", 112, true)
    local scalingWidth = BodyWidth(scaling)
    BindStyleSlider(scaling, "Icon Zoom (%)", 24, -48, 100, 200, 1, scalingWidth - 48,
        "iconZoom", 100, 100, 200, 100, 200, "AURAS3_ICON_ZOOM")

    local featuresH = 188 + extraDebuffControls + (lane == "buff" and 32 or 0)
    local features = b:CollapsibleSection(baseId .. "_features", "Basics", featuresH, true)
    local fw = BodyWidth(features)
    local featuresY = -44
    BindStyleSwitch(features, "Show Cooldown Text", 24, featuresY, fw - 48, "showCooldownText", true, "AURAS3_SHOW_COOLDOWN_TEXT")
    BindStyleSwitch(features, "Show Cooldown Swipe", 24, featuresY - 32, fw - 48, "showCooldownSwipe", true, "AURAS3_SHOW_COOLDOWN_SWIPE")
    BindStyleSwitch(features, "Show Tooltip", 24, featuresY - 64, fw - 48, "showTooltip", true, "AURAS3_TOOLTIP")
    if lane == "buff" then
        -- PTR 7 item enchantments: temporary weapon enchants as native
        -- buttons inside the player buff flow (player scope only at runtime).
        BindStyleSwitch(features, "Show Weapon Enchants (Player)", 24, featuresY - 96, fw - 48, "showWeaponEnchants", false, "AURAS3_WEAPON_ENCHANTS")
    end
    if lane == "debuff" then
        BindStyleDropdown(features, "Dispel-type Border", 24, featuresY - 114,
            type(Model.DebuffTypeBorderModeValues) == "function" and Model.DebuffTypeBorderModeValues() or DEBUFF_TYPE_BORDER_MODE_VALUES,
            fw - 48, ReadScopeDebuffBorderMode, WriteScopeDebuffBorderMode, "AURAS3_DEBUFF_TYPE_BORDER_MODE")
    end

    -- Shared icon style (static border + soft shadow). One global block: writes
    -- apply to every aura lane on all frames (Buffs, Debuffs, Custom containers
    -- incl. the Dot tracker), so one shared runtime apply is authoritative.
    -- "shared" defines the block; it is not a frame scope, so it has no opt-out
    -- row and the section stays at its original height there.
    -- Detail controls gray out while their master toggle is off, matching the
    -- rest of the aura style pages. Collected here so both the page refresher
    -- and the icon-style writes can re-apply the gate without a page rebuild.
    local iconStyleGates = { border = {}, shadow = {} }
    local iconStyleScoped = scope ~= "shared" and type(Model.IconStyleScopeEnabled) == "function"
    local iconStyle = b:CollapsibleSection(baseId .. "_icon_style", "Icon Border & Shadow (all lanes)",
        320 + (iconStyleScoped and 38 or 0), false)
    local isw = BodyWidth(iconStyle)
    local styleCol = max(140, floor((isw - 68) / 2))
    local styleGap = 10
    -- Re-runs the master-toggle gate. Assigned once the controls below exist;
    -- called from every icon-style write so flipping a toggle grays its detail
    -- controls immediately instead of waiting for a page rebuild.
    function iconStyleGates.Apply(editable)
        if type(W.SetControlsEnabled) ~= "function" then return end
        if editable == nil then
            editable = unit == "shared" or not Model.UseSharedVisuals(unit)
        end
        local function On(key)
            return editable and (type(Model.ReadBool) == "function" and Model.ReadBool(unit, key, false)) == true
        end
        W.SetControlsEnabled(iconStyleGates.border, On("styleBorderEnabled"))
        W.SetControlsEnabled(iconStyleGates.shadow, On("styleShadowEnabled"))
    end
    local iconStyleApplyTimer
    local iconStyleApplyPending
    local iconStyleApplyReason
    local iconStyleReleaseScheduled
    local function CancelIconStyleApplyTimer()
        if iconStyleApplyTimer and type(iconStyleApplyTimer.Cancel) == "function" then
            iconStyleApplyTimer:Cancel()
        end
        iconStyleApplyTimer = nil
    end
    local function ApplyIconStyleRuntime(reason)
        iconStyleApplyPending = nil
        iconStyleApplyReason = nil
        iconStyleReleaseScheduled = nil
        CancelIconStyleApplyTimer()
        local ok = RequestAuraRuntime("shared", reason or "AURAS3_ICON_STYLE")
        -- The shared aura batch flushes on a delayed timer, but the workbench
        -- (and its Live container) re-reads the compiled runtime config. Flush
        -- now and repaint afterwards, or the preview keeps the previous style
        -- until some unrelated interaction repaints it. Combat defers the
        -- flush; the preview refresh below is combat-gated as well.
        local apply = M.ApplyService or _G.MSUF_Menu2_ApplyService
        if apply and type(apply.Flush) == "function" then apply.Flush() end
        RefreshStylePreview()
        return ok
    end
    local function IconStyleWrite(key, value, reason, previewOnly)
        if type(Model.WriteValue) == "function" then Model.WriteValue(unit, key, value) end
        if previewOnly ~= true then ApplyIconStyleRuntime(reason) end
        if key == "styleBorderEnabled" or key == "styleShadowEnabled" then iconStyleGates.Apply() end
        RefreshStylePreview()
    end
    local function FlushIconStyleApply()
        if not iconStyleApplyPending then return end
        iconStyleApplyPending = nil
        iconStyleReleaseScheduled = nil
        CancelIconStyleApplyTimer()
        local reason = iconStyleApplyReason
        iconStyleApplyReason = nil
        ApplyIconStyleRuntime(reason)
    end
    local function ScheduleIconStyleReleaseApply()
        if not iconStyleApplyPending then return end
        CancelIconStyleApplyTimer()
        if C_Timer and type(C_Timer.NewTimer) == "function" then
            -- The native Slider may emit its final OnValueChanged after
            -- OnMouseUp. Flush on the next event tick so that final value joins
            -- this single runtime apply instead of scheduling a second one.
            iconStyleReleaseScheduled = true
            iconStyleApplyTimer = C_Timer.NewTimer(0, function()
                iconStyleApplyTimer = nil
                iconStyleReleaseScheduled = nil
                FlushIconStyleApply()
            end)
        else
            FlushIconStyleApply()
        end
    end
    local function QueueIconStyleApply(slider, reason)
        iconStyleApplyPending = true
        iconStyleApplyReason = reason or iconStyleApplyReason
        -- Pointer drags write SavedVariables and repaint only this menu preview.
        -- MouseUp flushes once on the next event tick. Wheel, +/- and text input
        -- have no drag state, so they share one cancellable trailing apply.
        if slider and slider._msuf2SliderActive then
            iconStyleReleaseScheduled = nil
            CancelIconStyleApplyTimer()
            return
        end
        if iconStyleReleaseScheduled then return end
        CancelIconStyleApplyTimer()
        if C_Timer and type(C_Timer.NewTimer) == "function" then
            iconStyleApplyTimer = C_Timer.NewTimer(M.AURA_ICON_STYLE_APPLY_DELAY, FlushIconStyleApply)
        else
            FlushIconStyleApply()
        end
    end
    local function IconStyleReadColor(colorKey, defaultColor)
        local c = type(Model.ReadValue) == "function" and Model.ReadValue(unit, colorKey, defaultColor) or defaultColor
        if type(c) ~= "table" then c = defaultColor end
        return c
    end
    local function IconStyleSwitch(label, y, key, reason)
        return AddStyleControl(BindSwitch(ctx, iconStyle, label, 24, y, styleCol,
            function() return (type(Model.ReadBool) == "function" and Model.ReadBool(unit, key, false)) == true end,
            function(v) IconStyleWrite(key, v == true, reason) end,
            AuraControlMeta(ctx, "style.shared.icon-style." .. AuraCatalogToken(key))))
    end
    local function IconStyleSlider(label, col, y, minVal, maxVal, key, defaultValue, reason)
        local slider
        slider = AddStyleControl(BindSlider(ctx, iconStyle, label, 24 + col * (styleCol + styleGap), y,
            minVal, maxVal, 1, styleCol,
            function()
                local value = type(Model.ReadValue) == "function" and Model.ReadValue(unit, key, defaultValue) or defaultValue
                return tonumber(value) or defaultValue
            end,
            function(value)
                IconStyleWrite(key, tonumber(value) or defaultValue, reason, true)
                QueueIconStyleApply(slider, reason)
            end,
            AuraControlMeta(ctx, "style.shared.icon-style." .. AuraCatalogToken(key))))
        slider:HookScript("OnMouseUp", ScheduleIconStyleReleaseApply)
        slider:HookScript("OnHide", FlushIconStyleApply)
        return slider
    end
    -- Border/Shadow color swatches now live on the Colors page (Auras section)
    -- and are reachable from this section via the three-dot context-color
    -- shortcut attached below; only the enable toggles, thickness/size and the
    -- alpha sliders remain inline here.
    local function IconStyleAlphaSlider(label, col, y, colorKey, defaultColor, reason)
        local slider
        slider = AddStyleControl(BindSlider(ctx, iconStyle, label, 24 + col * (styleCol + styleGap), y,
            0, 100, 1, styleCol,
            function()
                local c = IconStyleReadColor(colorKey, defaultColor)
                return floor(((tonumber(c[4]) or defaultColor[4]) * 100) + 0.5)
            end,
            function(value)
                local c = IconStyleReadColor(colorKey, defaultColor)
                IconStyleWrite(colorKey, { c[1] or defaultColor[1], c[2] or defaultColor[2], c[3] or defaultColor[3], (tonumber(value) or 100) / 100 }, reason, true)
                QueueIconStyleApply(slider, reason)
            end,
            AuraControlMeta(ctx, "style.shared.icon-style." .. AuraCatalogToken(colorKey) .. "-alpha")))
        slider:HookScript("OnMouseUp", ScheduleIconStyleReleaseApply)
        slider:HookScript("OnHide", FlushIconStyleApply)
        return slider
    end
    local ICON_STYLE_BORDER_DEFAULT = { 0, 0, 0, 1 }
    local ICON_STYLE_SHADOW_DEFAULT = { 0, 0, 0, 0.8 }
    -- The RGB swatches were relocated to the Colors page (Auras section). This
    -- quiet three-dot shortcut opens the same two shared colors in the context
    -- picker; alpha stays on the inline sliders above, so the picker is RGB-only.
    if W.AttachContextColorShortcut then
        W.AttachContextColorShortcut(iconStyle, {
            title = "Icon Border & Shadow Colors",
            note = AURA_SHARED_COLOR_NOTE,
            scopeTag = "Shared",
            historySource = "menu:auras-icon-style-color",
            getTargets = function()
                return {
                    {
                        label = "Icon Border Color",
                        historyLabel = "Aura icon border color",
                        getRGB = function()
                            local c = IconStyleReadColor("styleBorderColor", ICON_STYLE_BORDER_DEFAULT)
                            return c[1] or 0, c[2] or 0, c[3] or 0
                        end,
                        setRGB = function(r, g, blue)
                            local c = IconStyleReadColor("styleBorderColor", ICON_STYLE_BORDER_DEFAULT)
                            IconStyleWrite("styleBorderColor", { r, g, blue, c[4] or ICON_STYLE_BORDER_DEFAULT[4] }, "AURAS3_ICON_STYLE_BORDER_COLOR")
                        end,
                        defaultR = 0, defaultG = 0, defaultB = 0,
                    },
                    {
                        label = "Icon Shadow Color",
                        historyLabel = "Aura icon shadow color",
                        getRGB = function()
                            local c = IconStyleReadColor("styleShadowColor", ICON_STYLE_SHADOW_DEFAULT)
                            return c[1] or 0, c[2] or 0, c[3] or 0
                        end,
                        setRGB = function(r, g, blue)
                            local c = IconStyleReadColor("styleShadowColor", ICON_STYLE_SHADOW_DEFAULT)
                            IconStyleWrite("styleShadowColor", { r, g, blue, c[4] or ICON_STYLE_SHADOW_DEFAULT[4] }, "AURAS3_ICON_STYLE_SHADOW_COLOR")
                        end,
                        defaultR = 0, defaultG = 0, defaultB = 0,
                    },
                }
            end,
        })
    end
    IconStyleSwitch("Icon Border", -34, "styleBorderEnabled", "AURAS3_ICON_STYLE_BORDER")
    local borderStyleDropdown = AddStyleControl(BindDropdown(ctx, iconStyle, "Border Style", 24, -70,
        Model.BorderStyleValues, isw - 48,
        function() return Model.ReadBorderStyle(unit) end,
        function(v)
            Model.WriteBorderStyle(unit, v)
            ApplyIconStyleRuntime("AURAS3_ICON_STYLE_BORDER")
            RefreshStylePreview()
        end,
        AuraControlMeta(ctx, "style.shared.icon-style.border-style")))
    AddTooltip(borderStyleDropdown, "Icon border style",
        "Solid draws a crisp pixel ring around the icon. Soft Glow adds a halo, and Shadow shades the icon's own edges. The Blizzard entries and any LibSharedMedia border are drawn as edge art. Thickness scales the edge.")
    iconStyleGates.border[1] = borderStyleDropdown
    iconStyleGates.border[2] = IconStyleSlider("Border Thickness", 0, -122, 1, 8, "styleBorderThickness", 1, "AURAS3_ICON_STYLE_BORDER")
    iconStyleGates.border[3] = IconStyleAlphaSlider("Border Alpha (%)", 1, -122, "styleBorderColor", ICON_STYLE_BORDER_DEFAULT, "AURAS3_ICON_STYLE_BORDER_COLOR")
    IconStyleSwitch("Icon Shadow", -178, "styleShadowEnabled", "AURAS3_ICON_STYLE_SHADOW")
    iconStyleGates.shadow[1] = IconStyleSlider("Shadow Size", 0, -210, 1, 16, "styleShadowSize", 4, "AURAS3_ICON_STYLE_SHADOW")
    iconStyleGates.shadow[2] = IconStyleAlphaSlider("Shadow Alpha (%)", 1, -210, "styleShadowColor", ICON_STYLE_SHADOW_DEFAULT, "AURAS3_ICON_STYLE_SHADOW_COLOR")
    -- PTR 7 native flow padding: inner inset between the lane box and icons.
    IconStyleSlider("Lane Padding", 0, -252, 0, 16, "stylePadding", 0, "AURAS3_LANE_PADDING")
    if iconStyleScoped then
        -- Per-scope opt-out. The block above stays global; this only decides
        -- whether THIS frame scope renders it, resolved once while a lane is
        -- compiled, so an excluded scope costs nothing at all at runtime.
        local scopeSwitch = AddStyleControl(BindSwitch(ctx, iconStyle,
            M.Format("Use icon border & shadow on %s frames", ScopeLabel(scope)), 24, -294, isw - 48,
            function() return Model.IconStyleScopeEnabled(scope) end,
            function(v)
                if Model.SetIconStyleScopeEnabled(scope, v == true) then
                    ApplyIconStyleRuntime("AURAS3_ICON_STYLE_SCOPE")
                end
                RefreshStylePreview()
            end,
            -- The scope belongs in the identity: the styling block itself is
            -- shared, but this switch is per-scope and its label names the
            -- scope, so one shared ID would collapse several differently
            -- labelled controls into one and break schema generation.
            AuraControlMeta(ctx, "style.scope." .. AuraCatalogToken(scope) .. ".icon-style.enabled")))
        AddTooltip(scopeSwitch, "Icon border and shadow on this scope",
            "Turn this off to leave this frame's aura icons unstyled while other frames keep the shared border and shadow.")
    end

    local stack = b:CollapsibleSection(baseId .. "_stack", "Stack Count", 296, false)
    if W.AttachContextColorShortcut then
        W.AttachContextColorShortcut(stack, {
            title = LaneTitle(lane) .. " Stack Text Settings",
            historyLabel = "Aura stack text color",
            historySource = "menu:auras-stack-text-color",
            scopeTag = "Shared",
            note = AURA_SHARED_COLOR_NOTE,
            textSettings = {
                scope = "shared",
                unit = unit,
                kind = "aura",
                colorReferences = { "font.global" },
                colorTitle = "Aura Stack Text Color",
                subtitle = "Aura stack text follows the shared Fonts settings.",
                capabilities = {
                    opacity = false, baseline = false,
                    shadowAlpha = false, shadowDistance = false,
                },
            },
        })
    end
    local sw = BodyWidth(stack)
    BindStyleSwitch(stack, "Show Stack Count", 24, -56, sw - 48, "showStackCount", true, "AURAS3_SHOW_STACKS")
    AddStyleControl(BindDropdown(ctx, stack, "Anchor", 24, -94, Model.StackAnchorValues(), sw - 48,
        function()
            if type(Model.ReadLaneStackAnchor) == "function" then return Model.ReadLaneStackAnchor(unit, lane) end
            return Model.ReadStackAnchor(unit)
        end,
        function(v)
            if type(Model.WriteLaneStackAnchor) == "function" then
                Model.WriteLaneStackAnchor(unit, lane, v)
            else
                Model.WriteStackAnchor(unit, v)
            end
            ApplyUnit(ctx, unit, "AURAS3_STACK_ANCHOR")
            RefreshStylePreview()
        end,
        AuraControlMeta(ctx, "style.lane." .. AuraCatalogToken(lane) .. ".stack-anchor")))
    BindStyleSlider(stack, "Text Size", 24, -152, 6, 40, 1, sw - 48, "stackTextSize", 14, 6, 40, nil, nil, "AURAS3_STACK_SIZE")
    local stackSmallW = max(120, floor((sw - 72) / 2))
    BindStyleSlider(stack, "X", 24, -212, -40, 40, 1, stackSmallW, "stackTextOffsetX", -1, -2000, 2000, nil, nil, "AURAS3_STACK_X")
    BindStyleSlider(stack, "Y", 32 + stackSmallW, -212, -40, 40, 1, stackSmallW, "stackTextOffsetY", 1, -2000, 2000, nil, nil, "AURAS3_STACK_Y")

    local cooldown = b:CollapsibleSection(baseId .. "_cooldown", "Cooldown Text", 374, true)
    if W.AttachContextColorShortcut then
        W.AttachContextColorShortcut(cooldown, {
            title = LaneTitle(lane) .. " Cooldown Text Settings",
            historyLabel = "Aura cooldown text color",
            historySource = "menu:auras-cooldown-text-color",
            scopeTag = "Shared",
            note = AURA_SHARED_COLOR_NOTE,
            textSettings = {
                scope = "shared",
                unit = unit,
                kind = "aura",
                colorReferences = AURA_COOLDOWN_COLOR_REFERENCES,
                colorTitle = LaneTitle(lane) .. " Cooldown Colors",
                subtitle = "Aura cooldown text follows the shared Fonts settings.",
                capabilities = {
                    opacity = false, baseline = false,
                    shadowAlpha = false, shadowDistance = false,
                },
            },
        })
    end
    local cw = BodyWidth(cooldown)
    BindStyleSlider(cooldown, "Text Size", 24, -48, 6, 40, 1, cw - 48, "cooldownTextSize", 14, 6, 40, nil, nil, "AURAS3_COOLDOWN_SIZE")
    BindStyleDropdown(cooldown, "Anchor", 24, -104, type(Model.AuraAnchorValues) == "function" and Model.AuraAnchorValues() or GFAnchorValues(), cw - 48, ReadScopeCooldownAnchor, WriteScopeCooldownAnchor, "AURAS3_COOLDOWN_ANCHOR")
    BindStyleSlider(cooldown, "X", 24, -162, -40, 40, 1, cw - 48, "cooldownTextOffsetX", 0, -2000, 2000, nil, nil, "AURAS3_COOLDOWN_X")
    BindStyleSlider(cooldown, "Y", 24, -222, -40, 40, 1, cw - 48, "cooldownTextOffsetY", 0, -2000, 2000, nil, nil, "AURAS3_COOLDOWN_Y")
    local swipeDirection = BindStyleDropdown(cooldown, "Swipe Direction", 24, -270, COOLDOWN_SWIPE_DIRECTION_VALUES, cw - 48, ReadScopeSwipeDirection, WriteScopeSwipeDirection, "AURAS3_COOLDOWN_SWIPE_DIRECTION")
    AddTooltip(swipeDirection, "Cooldown swipe direction", "Reverses only the swipe overlay. Icon size and position stay unchanged.")
    local decimal = BindStyleSlider(cooldown, "Decimals below sec", 24, -328, 0, 30, 1, cw - 48, "cooldownDecimalSeconds", 3, 0, 30, nil, nil, "AURAS3_COOLDOWN_FORMAT")
    AddTooltip(decimal, "Cooldown text format", "Remaining time below this value uses one decimal place. Timers show unitless seconds below 1 minute and localized minutes above it. Set 0 for whole seconds only.")

    local durationBar = b:CollapsibleSection(baseId .. "_duration_bar", "Duration Bar", 322, false)
    W.AttachContextColorReferences(durationBar, AURA_DURATION_BAR_COLOR_REFERENCES, {
        title = LaneTitle(lane) .. " Duration Bar Color",
        scopeTag = "Shared",
        note = AURA_SHARED_COLOR_NOTE,
    })
    local dbw = BodyWidth(durationBar)
    BindStyleSwitch(durationBar, "Show Duration Bar", 24, -48, dbw - 48, "showDurationBar", false, "AURAS3_DURATION_BAR")
    BindStyleSlider(durationBar, "Height", 24, -104, 1, 16, 1, dbw - 48, "durationBarHeight", 2, 1, 16, nil, nil, "AURAS3_DURATION_BAR_HEIGHT")
    BindStyleDropdown(durationBar, "Display", 24, -162,
        type(Model.DurationBarDisplayValues) == "function" and Model.DurationBarDisplayValues() or DURATION_BAR_DISPLAY_VALUES,
        dbw - 48, ReadScopeDurationBarDisplay, WriteScopeDurationBarDisplay, "AURAS3_DURATION_BAR_DISPLAY")
    BindStyleDropdown(durationBar, "Position", 24, -220,
        type(Model.DurationBarPositionValues) == "function" and Model.DurationBarPositionValues() or DURATION_BAR_POSITION_VALUES,
        dbw - 48, ReadScopeDurationBarPosition, WriteScopeDurationBarPosition, "AURAS3_DURATION_BAR_POSITION")
    BindStyleDropdown(durationBar, "Fill Mode", 24, -278,
        type(Model.DurationBarDirectionValues) == "function" and Model.DurationBarDirectionValues() or DURATION_BAR_DIRECTION_VALUES,
        dbw - 48, ReadScopeDurationBarDirection, WriteScopeDurationBarDirection, "AURAS3_DURATION_BAR_DIRECTION")

    local effectPrefix = lane == "buff" and "buff" or "debuff"
    local function EffectKey(suffix) return effectPrefix .. "FrameEffect" .. suffix end
    local function ReadEffectValue(suffix, fallback)
        return Model.ReadValue(unit, EffectKey(suffix), fallback)
    end
    local function WriteEffectValue(suffix, value, reason)
        Model.WriteValue(unit, EffectKey(suffix), value)
        ApplyUnit(ctx, unit, reason)
        RefreshStylePreview()
    end
    local frameEffect = b:CollapsibleSection(baseId .. "_full_frame", "Full-Frame Effect", 210, false)
    local few = BodyWidth(frameEffect)
    local effectCol = max(140, floor((few - 68) / 3))
    local effectGap = 10
    AddStyleControl(BindDropdown(ctx, frameEffect, "Effect", 24, -34, CUSTOM_FRAME_EFFECTS, effectCol,
        function() return tostring(ReadEffectValue("Type", "none")) end,
        function(value) WriteEffectValue("Type", value or "none", "AURAS3_LANE_FRAME_EFFECT") end,
        AuraControlMeta(ctx, "style.lane." .. AuraCatalogToken(lane) .. ".full-frame.type", nil,
            LaneFrameEffectAssistantContract())))
    local effectColor = W.Color(frameEffect, "Color")
    M.BindColor(ctx, effectColor,
        function()
            local c = ReadEffectValue("Color", { 0.69, 0.50, 0.88, 0.80 })
            return c[1] or 0.69, c[2] or 0.50, c[3] or 0.88
        end,
        function(r, g, blue)
            local c = ReadEffectValue("Color", { 0.69, 0.50, 0.88, 0.80 })
            WriteEffectValue("Color", { r, g, blue, c[4] or 0.80 }, "AURAS3_LANE_FRAME_EFFECT_COLOR")
        end,
        AuraControlMeta(ctx, "style.lane." .. AuraCatalogToken(lane) .. ".full-frame.color", nil,
            LaneFrameEffectAssistantContract()))
    W.MoveWidget(effectColor, frameEffect, 24 + effectCol + effectGap, -34, effectCol, "LEFT")
    AddStyleControl(effectColor)
    local function EffectSlider(label, col, y, minValue, maxValue, step, suffix, fallback, reason)
        return AddStyleControl(BindSlider(ctx, frameEffect, label, 24 + col * (effectCol + effectGap), y,
            minValue, maxValue, step, effectCol,
            function()
                local value = ReadEffectValue(suffix, fallback)
                if suffix == "Alpha" then
                    local c = ReadEffectValue("Color", { 0.69, 0.50, 0.88, 0.80 })
                    return floor(((tonumber(c[4]) or fallback) * 100) + 0.5)
                end
                return tonumber(value) or fallback
            end,
            function(value)
                if suffix == "Alpha" then
                    local c = ReadEffectValue("Color", { 0.69, 0.50, 0.88, 0.80 })
                    WriteEffectValue("Color", { c[1] or 0.69, c[2] or 0.50, c[3] or 0.88, (tonumber(value) or 80) / 100 }, reason)
                else
                    WriteEffectValue(suffix, tonumber(value) or fallback, reason)
                end
            end,
            AuraControlMeta(ctx, "style.lane." .. AuraCatalogToken(lane) .. ".full-frame." .. AuraCatalogToken(suffix), nil,
                LaneFrameEffectAssistantContract())))
    end
    EffectSlider("Opacity", 0, -96, 5, 100, 5, "Alpha", 0.80, "AURAS3_LANE_FRAME_EFFECT_ALPHA")
    EffectSlider("Layer (0-30)", 1, -96, 0, 30, 1, "Layer", 0, "AURAS3_LANE_FRAME_EFFECT_LAYER")
    EffectSlider("Thickness", 2, -96, 1, 16, 1, "Thickness", 2, "AURAS3_LANE_FRAME_EFFECT_THICKNESS")
    EffectSlider("Priority", 0, -150, 1, 10, 1, "Priority", 5, "AURAS3_LANE_FRAME_EFFECT_PRIORITY")

    local behavior = b:CollapsibleSection(baseId .. "_behavior", "Ordering", 156, false)
    local bw = BodyWidth(behavior)
    local sortMethod = BindStyleDropdown(behavior, "Sort By", 24, -48, AuraSortMethodValues(lane), bw - 48,
        ReadScopeSortMethod, WriteScopeSortMethod, "AURAS3_SORT_METHOD")
    AddTooltip(sortMethod, "Aura sorting", "Only relevant sorting methods are shown for buffs and debuffs.")
    local sortDirection = BindStyleDropdown(behavior, "Order", 24, -104, AURA_SORT_DIRECTION_VALUES, bw - 48,
        ReadScopeSortDirection, WriteScopeSortDirection, "AURAS3_SORT_DIRECTION")
    AddTooltip(sortDirection, "Aura sort order", "Reversed flips the complete priority order.")

    M.TrackRefresh(ctx, function()
        local editable = unit == "shared" or not Model.UseSharedVisuals(unit)
        W.SetControlsEnabled(styleControls, editable)
        -- Must come after the blanket pass above, which would otherwise
        -- re-enable detail controls whose master toggle is off.
        iconStyleGates.Apply(editable)
        if W.SetCollapsibleBadges then
            local function ToggleBadge(label, enabled)
                return { text = label .. (enabled and " On" or " Off"), kind = enabled and "accent" or "muted", showWhenClosed = true }
            end
            local featureBadges = {
                { text = unit == "shared" and "Shared baseline" or (editable and "Override active" or "Inherited"), kind = unit == "shared" and "info" or (editable and "accent" or "muted"), showWhenClosed = true },
                ToggleBadge("Text", ReadScopeBool("showCooldownText", true)),
                ToggleBadge("Swipe", ReadScopeBool("showCooldownSwipe", true)),
                ToggleBadge("Tooltip", ReadScopeBool("showTooltip", true)),
            }
            W.SetCollapsibleBadges(scaling, {{
                text = M.Format("Zoom %d%%", Round(ReadScopeNumber("iconZoom", 100, 100, 200))),
                kind = "info", showWhenClosed = true,
            }})
            if lane == "debuff" then
                local borderMode = ReadScopeDebuffBorderMode()
                featureBadges[#featureBadges + 1] = {
                    text = "Border " .. ChoiceLabel(DEBUFF_TYPE_BORDER_MODE_VALUES, borderMode, borderMode),
                    kind = borderMode == "OFF" and "muted" or "accent",
                    showWhenClosed = true,
                }
            end
            W.SetCollapsibleBadges(features, featureBadges)

            local stackEnabled = ReadScopeBool("showStackCount", true)
            W.SetCollapsibleBadges(stack, {{
                text = stackEnabled and (tostring(Round(ReadScopeNumber("stackTextSize", 14, 6, 40))) .. "px / " .. AnchorLabel(type(Model.ReadLaneStackAnchor) == "function" and Model.ReadLaneStackAnchor(unit, lane) or Model.ReadStackAnchor(unit))) or "Off",
                kind = stackEnabled and "accent" or "muted", showWhenClosed = true,
            }})

            local cooldownEnabled = ReadScopeBool("showCooldownText", true)
            local decimal = Round(ReadScopeNumber("cooldownDecimalSeconds", 3, 0, 30))
            W.SetCollapsibleBadges(cooldown, {
                { text = cooldownEnabled and (tostring(Round(ReadScopeNumber("cooldownTextSize", 14, 6, 40))) .. "px / " .. AnchorLabel(ReadScopeCooldownAnchor()) .. " / " .. ChoiceLabel(COOLDOWN_SWIPE_DIRECTION_VALUES, ReadScopeSwipeDirection(), "Normal")) or "Off", kind = cooldownEnabled and "accent" or "muted", showWhenClosed = true },
                { text = decimal > 0 and ("Decimals below " .. tostring(decimal) .. "s") or "Whole seconds", kind = "info", showWhenClosed = true },
            })

            local durationEnabled = ReadScopeBool("showDurationBar", false)
            W.SetCollapsibleBadges(durationBar, {{
                text = durationEnabled and (tostring(Round(ReadScopeNumber("durationBarHeight", 2, 1, 16))) .. "px / " .. ChoiceLabel(DURATION_BAR_DISPLAY_VALUES, ReadScopeDurationBarDisplay(), "Bar Only") .. " / " .. ChoiceLabel(DURATION_BAR_POSITION_VALUES, ReadScopeDurationBarPosition(), "Bottom")) or "Off",
                kind = durationEnabled and "accent" or "muted", showWhenClosed = true,
            }})

            local effectType = tostring(ReadEffectValue("Type", "none"))
            W.SetCollapsibleBadges(frameEffect, {{
                text = ChoiceLabel(CUSTOM_FRAME_EFFECTS, effectType, effectType),
                kind = effectType == "none" and "muted" or "accent", showWhenClosed = true,
            }})

            local sortKey = ReadScopeSortMethod()
            W.SetCollapsibleBadges(behavior, {{
                text = (AURA_SORT_SUMMARY_LABELS[sortKey] or sortKey) .. " / " .. ChoiceLabel(AURA_SORT_DIRECTION_VALUES, ReadScopeSortDirection(), "Normal"),
                kind = "info", showWhenClosed = true,
            }})
        end
    end)
end
local function BuildGroupStyle(ctx, b, scope)
    local lane = CurrentLane("auraStyleGFLane", "debuff")
    local extraDebuffControls = lane == "debuff" and 64 or 0
    local refreshMiniPreview
    local function RefreshStylePreview()
        RefreshMiniAuraPreviewNow(refreshMiniPreview)
    end
    local function BodyWidth(body)
        return body and (body._msuf2Width or body.GetWidth and body:GetWidth()) or b.width or 720
    end
    local baseId = "aura_style_group_" .. tostring(scope or "group") .. "_" .. lane

    refreshMiniPreview = BuildAuraStylePreviewWorkbench(ctx, b, scope, lane)

    local scaling = b:CollapsibleSection(baseId .. "_scaling", "Scaling", 112, true)
    local scalingWidth = BodyWidth(scaling)
    BindGroupSlider(ctx, scaling, "Icon Zoom (%)", 24, -48, 100, 200, 1, scalingWidth - 48,
        scope, lane, "iconZoom", 100, "visual", RefreshStylePreview, {
            assistantDisposition = "dynamic",
            assistantDispositionReason = "Icon Zoom targets the selected Group scope's selected Aura Style lane.",
            assistantSettingKeys = GroupAssistantSettingKeys(scope, ".auras." .. lane .. ".iconZoom"),
        })

    local features = b:CollapsibleSection(baseId .. "_features", "Basics", 186 + extraDebuffControls, true)
    local fw = BodyWidth(features)
    BindGroupSwitch(ctx, features, "Show Cooldown Text", 24, -44, fw - 48, scope, lane, "showCooldown", true, "visual", RefreshStylePreview)
    BindGroupSwitch(ctx, features, "Show Cooldown Swipe", 24, -74, fw - 48, scope, lane, "showCooldownSwipe", true, "visual", RefreshStylePreview)
    BindGroupSwitch(ctx, features, "Show Tooltip", 24, -106, fw - 48, scope, lane, "showTooltip", true, "visual", RefreshStylePreview)
    if lane == "debuff" then
        BindDropdown(ctx, features, "Dispel-type Border", 24, -158,
            type(Model.DebuffTypeBorderModeValues) == "function" and Model.DebuffTypeBorderModeValues() or DEBUFF_TYPE_BORDER_MODE_VALUES,
            fw - 48,
            function() return ReadGroupDebuffTypeBorderMode(scope, lane) end,
            function(v)
                WriteGroupDebuffTypeBorderMode(scope, lane, v)
                RefreshStylePreview()
            end,
            AuraControlMeta(ctx, "group-style.lane." .. AuraCatalogToken(lane) .. ".dispel-border-mode"))
    end

    -- Group frames render the same shared icon border/shadow as unit frames.
    -- The block itself is edited on the Shared scope; group scopes only choose
    -- whether they take part, which is resolved once per lane compile.
    if type(Model.IconStyleScopeEnabled) == "function" then
        local iconStyle = b:CollapsibleSection(baseId .. "_icon_style", "Icon Border & Shadow (all lanes)", 108, false)
        local isw = BodyWidth(iconStyle)
        local scopeSwitch = BindSwitch(ctx, iconStyle,
            M.Format("Use icon border & shadow on %s frames", ScopeLabel(scope)), 24, -44, isw - 48,
            function() return Model.IconStyleScopeEnabled(scope) end,
            function(v)
                if Model.SetIconStyleScopeEnabled(scope, v == true) then
                    RequestAuraRuntime("shared", "AURAS3_ICON_STYLE_SCOPE")
                end
                RefreshStylePreview()
            end,
            AuraControlMeta(ctx, "group-style.scope." .. AuraCatalogToken(scope) .. ".icon-style.enabled"))
        AddTooltip(scopeSwitch, "Icon border and shadow on this scope",
            "Turn this off to leave these group aura icons unstyled. Edit the border style, thickness, shadow and colors on Aura Style > Shared.")
    end

    local cooldown = b:CollapsibleSection(baseId .. "_cooldown", "Cooldown Text", 336, true)
    if W.AttachContextColorShortcut then
        W.AttachContextColorShortcut(cooldown, {
            title = LaneTitle(lane) .. " Cooldown Text Settings",
            historyLabel = "Group aura cooldown text color",
            historySource = "menu:group-auras-cooldown-text-color",
            scopeTag = "Shared",
            note = AURA_SHARED_COLOR_NOTE,
            textSettings = {
                scope = "shared",
                kind = "aura",
                colorReferences = AURA_COOLDOWN_COLOR_REFERENCES,
                colorTitle = LaneTitle(lane) .. " Cooldown Colors",
                subtitle = "Group aura cooldown text follows the shared Fonts settings.",
                capabilities = {
                    opacity = false, baseline = false,
                    shadowAlpha = false, shadowDistance = false,
                },
            },
        })
    end
    local cw = BodyWidth(cooldown)
    BindGroupSlider(ctx, cooldown, "Cooldown Font", 24, -56, 6, 24, 1, cw - 48, scope, lane, "cooldownSize", 8, "font", RefreshStylePreview)
    BindGroupDropdown(ctx, cooldown, "Cooldown Anchor", 24, -112, GFAnchorValues(), cw - 48, scope, lane, "cooldownAnchor", "CENTER", "geometry", RefreshStylePreview)
    local cooldownSmallW = max(120, floor((cw - 72) / 2))
    BindGroupSlider(ctx, cooldown, "Cooldown X", 24, -170, -40, 40, 1, cooldownSmallW, scope, lane, "cooldownX", 0, "geometry", RefreshStylePreview)
    BindGroupSlider(ctx, cooldown, "Cooldown Y", 32 + cooldownSmallW, -170, -40, 40, 1, cooldownSmallW, scope, lane, "cooldownY", 0, "geometry", RefreshStylePreview)
    local groupSwipeDirection = BindDropdown(ctx, cooldown, "Swipe Direction", 24, -230, COOLDOWN_SWIPE_DIRECTION_VALUES, cw - 48,
        function()
            local group = GFReadGroup(scope, lane)
            return group.cooldownSwipeReverse == true and "REVERSE" or "NORMAL"
        end,
        function(v)
            GFWriteGroupValue(scope, lane, "cooldownSwipeReverse", v == "REVERSE", "visual")
            RefreshStylePreview()
        end,
        AuraControlMeta(ctx, "group-style.lane." .. AuraCatalogToken(lane) .. ".cooldown-swipe-direction"))
    AddTooltip(groupSwipeDirection, "Cooldown swipe direction", "Reverses only the swipe overlay. Icon size and position stay unchanged.")
    local groupDecimal = BindGroupSlider(ctx, cooldown, "Decimals below sec", 24, -288, 0, 30, 1, cw - 48, scope, lane, "cooldownDecimalSeconds", 3, "visual", RefreshStylePreview)
    AddTooltip(groupDecimal, "Cooldown text format", "Remaining time below this value uses one decimal place. Timers show unitless seconds below 1 minute and localized minutes above it. Set 0 for whole seconds only.")

    local durationBar = b:CollapsibleSection(baseId .. "_duration_bar", "Duration Bar", 322, false)
    W.AttachContextColorReferences(durationBar, AURA_DURATION_BAR_COLOR_REFERENCES, {
        title = LaneTitle(lane) .. " Duration Bar Color",
        scopeTag = "Shared",
        note = AURA_SHARED_COLOR_NOTE,
    })
    local dbw = BodyWidth(durationBar)
    BindGroupSwitch(ctx, durationBar, "Show Duration Bar", 24, -48, dbw - 48, scope, lane, "showDurationBar", false, "visual", RefreshStylePreview)
    BindGroupSlider(ctx, durationBar, "Height", 24, -104, 1, 16, 1, dbw - 48, scope, lane, "durationBarHeight", 2, "visual", RefreshStylePreview)
    BindGroupDropdown(ctx, durationBar, "Display", 24, -162, DURATION_BAR_DISPLAY_VALUES, dbw - 48, scope, lane, "durationBarDisplay", "BAR_ONLY", "visual", RefreshStylePreview)
    BindGroupDropdown(ctx, durationBar, "Position", 24, -220, DURATION_BAR_POSITION_VALUES, dbw - 48, scope, lane, "durationBarPosition", "BOTTOM", "visual", RefreshStylePreview)
    BindGroupDropdown(ctx, durationBar, "Fill Mode", 24, -278, DURATION_BAR_DIRECTION_VALUES, dbw - 48, scope, lane, "durationBarDirection", "REMAINING", "visual", RefreshStylePreview)

    local stack = b:CollapsibleSection(baseId .. "_stack", "Stack Count", 270, false)
    if W.AttachContextColorShortcut then
        W.AttachContextColorShortcut(stack, {
            title = LaneTitle(lane) .. " Stack Text Settings",
            historyLabel = "Group aura stack text color",
            historySource = "menu:group-auras-stack-text-color",
            scopeTag = "Shared",
            note = AURA_SHARED_COLOR_NOTE,
            textSettings = {
                scope = "shared",
                kind = "aura",
                colorReferences = { "font.global" },
                colorTitle = "Aura Stack Text Color",
                subtitle = "Group aura stack text follows the shared Fonts settings.",
                capabilities = {
                    opacity = false, baseline = false,
                    shadowAlpha = false, shadowDistance = false,
                },
            },
        })
    end
    local sw = BodyWidth(stack)
    BindGroupSwitch(ctx, stack, "Show Stack Count", 24, -56, sw - 48, scope, lane, "showStacks", true, "visual", RefreshStylePreview)
    BindGroupSlider(ctx, stack, "Stack Font", 24, -94, 6, 24, 1, sw - 48, scope, lane, "stackSize", 10, "font", RefreshStylePreview)
    BindGroupDropdown(ctx, stack, "Stack Anchor", 24, -152, GFAnchorValues(), sw - 48, scope, lane, "stackAnchor", "BOTTOMRIGHT", "geometry", RefreshStylePreview)
    local stackSmallW = max(120, floor((sw - 72) / 2))
    BindGroupSlider(ctx, stack, "Stack X", 24, -210, -40, 40, 1, stackSmallW, scope, lane, "stackX", 0, "geometry", RefreshStylePreview)
    BindGroupSlider(ctx, stack, "Stack Y", 32 + stackSmallW, -210, -40, 40, 1, stackSmallW, scope, lane, "stackY", 0, "geometry", RefreshStylePreview)

    local behavior = b:CollapsibleSection(baseId .. "_behavior", "Ordering", 216, false)
    local bw = BodyWidth(behavior)
    local groupSortMethod = BindGroupDropdown(ctx, behavior, "Sort By", 24, -48, AuraSortMethodValues(lane), bw - 48,
        scope, lane, "sortMethod", "DEFAULT", "visual")
    AddTooltip(groupSortMethod, "Aura sorting", "Only relevant sorting methods are shown for buffs and debuffs.")
    local groupSortDirection = BindDropdown(ctx, behavior, "Order", 24, -104, AURA_SORT_DIRECTION_VALUES, bw - 48,
        function()
            local group = GFReadGroup(scope, lane)
            return group.sortReverse == true and "REVERSE" or "NORMAL"
        end,
        function(v)
            GFWriteGroupValue(scope, lane, "sortReverse", v == "REVERSE", "visual")
        end,
        AuraControlMeta(ctx, "group-style.lane." .. AuraCatalogToken(lane) .. ".sort-direction"))
    AddTooltip(groupSortDirection, "Aura sort order", "Reversed flips the complete priority order.")
    BindGroupRootSwitch(ctx, behavior, "Scale Icons for Large Groups", 24, -160, bw - 48, scope, "dynamicScale", false, "geometry", RefreshStylePreview)
    W.Text(behavior, "85% above 15 members · 70% above 25", 24, -192, bw - 48, T.colors.muted)

    M.TrackRefresh(ctx, function()
        if not W.SetCollapsibleBadges then return end
        local group = GFReadGroup(scope, lane)
        local root = GFReadRoot(scope)
        local function ToggleBadge(label, enabled)
            return { text = label .. (enabled and " On" or " Off"), kind = enabled and "accent" or "muted", showWhenClosed = true }
        end
        local cooldownEnabled = group.showCooldown ~= false
        local swipeEnabled = group.showCooldownSwipe ~= false
        local tooltipEnabled = group.showTooltip ~= false
        W.SetCollapsibleBadges(scaling, {{
            text = M.Format("Zoom %d%%", Round(tonumber(group.iconZoom) or tonumber(root.iconZoom) or 100)),
            kind = "info", showWhenClosed = true,
        }})
        local featureBadges = {
            { text = ScopeLabel(scope) .. " style", kind = "info", showWhenClosed = true },
            ToggleBadge("Text", cooldownEnabled),
            ToggleBadge("Swipe", swipeEnabled),
            ToggleBadge("Tooltip", tooltipEnabled),
        }
        if lane == "debuff" then
            local borderMode = ReadGroupDebuffTypeBorderMode(scope, lane)
            featureBadges[#featureBadges + 1] = {
                text = "Border " .. ChoiceLabel(DEBUFF_TYPE_BORDER_MODE_VALUES, borderMode, borderMode),
                kind = borderMode == "OFF" and "muted" or "accent", showWhenClosed = true,
            }
        end
        W.SetCollapsibleBadges(features, featureBadges)

        local decimal = Round(tonumber(group.cooldownDecimalSeconds) or 3)
        W.SetCollapsibleBadges(cooldown, {
            { text = cooldownEnabled and (tostring(Round(tonumber(group.cooldownSize) or 8)) .. "px / " .. AnchorLabel(group.cooldownAnchor or "CENTER") .. " / " .. (group.cooldownSwipeReverse == true and "Reverse" or "Normal")) or "Off", kind = cooldownEnabled and "accent" or "muted", showWhenClosed = true },
            { text = decimal > 0 and ("Decimals below " .. tostring(decimal) .. "s") or "Whole seconds", kind = "info", showWhenClosed = true },
        })

        local durationEnabled = group.showDurationBar == true
        local durationDisplay = group.durationBarDisplay == "OVERLAY" and "OVERLAY" or "BAR_ONLY"
        local durationPosition = group.durationBarPosition == "TOP" and "TOP" or "BOTTOM"
        W.SetCollapsibleBadges(durationBar, {{
            text = durationEnabled and (tostring(Round(tonumber(group.durationBarHeight) or 2)) .. "px / " .. ChoiceLabel(DURATION_BAR_DISPLAY_VALUES, durationDisplay, "Bar Only") .. " / " .. ChoiceLabel(DURATION_BAR_POSITION_VALUES, durationPosition, "Bottom")) or "Off",
            kind = durationEnabled and "accent" or "muted", showWhenClosed = true,
        }})

        local stackEnabled = group.showStacks ~= false
        W.SetCollapsibleBadges(stack, {{
            text = stackEnabled and (tostring(Round(tonumber(group.stackSize) or 10)) .. "px / " .. AnchorLabel(group.stackAnchor or "BOTTOMRIGHT")) or "Off",
            kind = stackEnabled and "accent" or "muted", showWhenClosed = true,
        }})

        local sortKey = NormalizeAuraSortMethodForLane(lane, group.sortMethod or "DEFAULT")
        W.SetCollapsibleBadges(behavior, {
            { text = (AURA_SORT_SUMMARY_LABELS[sortKey] or sortKey) .. " / " .. (group.sortReverse == true and "Reversed" or "Normal"), kind = "info", showWhenClosed = true },
            ToggleBadge("Large-group scaling", root.dynamicScale == true),
        })
    end)
end
EnsureCustomPreviewEffect = function(box)
    if box._msufCustomEffectOverlay then return box._msufCustomEffectOverlay, box._msufCustomEffectEdges, box._msufCustomEffectName end
    local overlay = box:CreateTexture(nil, "BACKGROUND", nil, 1)
    overlay:SetPoint("TOPLEFT", box, "TOPLEFT", 2, -2)
    overlay:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -2, 2)
    overlay:SetTexture(TEX_W8)
    overlay:Hide()
    local edges = {}
    for i = 1, 4 do
        edges[i] = box:CreateTexture(nil, "OVERLAY", nil, 3)
        edges[i]:SetTexture(TEX_W8)
        edges[i]:Hide()
    end
    local name = T.Font(box, "GameFontHighlight", "Preview Unit", T.colors.text)
    name:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 12, 8)
    name:Hide()
    box._msufCustomEffectOverlay = overlay
    box._msufCustomEffectEdges = edges
    box._msufCustomEffectName = name
    return overlay, edges, name
end
RefreshCustomPreviewEffect = function(box, item)
    if not box then return end
    local overlay, edges, name = EnsureCustomPreviewEffect(box)
    local frame = item and type(item.frame) == "table" and item.frame or {}
    local effect = tostring(frame.type or "none"):lower()
    local color = type(frame.color) == "table" and frame.color or { 0.69, 0.50, 0.88, 0.8 }
    local r, g, blue, alpha = color[1] or 0.69, color[2] or 0.50, color[3] or 0.88, color[4] or 0.8
    overlay:SetVertexColor(r, g, blue, alpha)
    overlay:SetShown(effect == "healthtint")
    name:SetTextColor(r, g, blue, alpha)
    name:SetShown(effect == "namecolor")
    local showEdges = effect == "border" or effect == "glow" or effect == "pulse"
    local thickness = min(16, max(1, tonumber(frame.thickness) or 2))
    for i = 1, #edges do
        edges[i]:ClearAllPoints()
        edges[i]:SetVertexColor(r, g, blue, effect == "glow" and min(1, alpha + 0.16) or alpha)
        edges[i]:SetShown(showEdges)
    end
    edges[1]:SetPoint("TOPLEFT", box, "TOPLEFT", 1, -1); edges[1]:SetPoint("TOPRIGHT", box, "TOPRIGHT", -1, -1); edges[1]:SetHeight(thickness)
    edges[2]:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 1, 1); edges[2]:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -1, 1); edges[2]:SetHeight(thickness)
    edges[3]:SetPoint("TOPLEFT", box, "TOPLEFT", 1, -1); edges[3]:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 1, 1); edges[3]:SetWidth(thickness)
    edges[4]:SetPoint("TOPRIGHT", box, "TOPRIGHT", -1, -1); edges[4]:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -1, 1); edges[4]:SetWidth(thickness)
end
RefreshAuraFrameEffectPreview = function(box, scope, lane)
    local prefix = lane == "buff" and "buff" or "debuff"
    local unit = scope == "shared" and "shared" or scope
    RefreshCustomPreviewEffect(box, {
        frame = {
            type = Model.ReadValue(unit, prefix .. "FrameEffectType", "none"),
            color = Model.ReadValue(unit, prefix .. "FrameEffectColor", { 0.69, 0.50, 0.88, 0.80 }),
            thickness = Model.ReadValue(unit, prefix .. "FrameEffectThickness", 2),
        },
    })
end
local function CustomStyleSectionId(index, suffix)
    return "aura_style_custom_" .. tostring(index or 1) .. "_" .. tostring(suffix or "section")
end
local function BuildCustomAuraStylePreview(ctx, b, scope, index)
    local section = b:CollapsibleSection(CustomStyleSectionId(index, "preview"), "Preview", 452, true)
    local w = section._msuf2Width or b.width or 720
    local liveRefresh = select(2, BuildLiveAuraPreview(ctx, section, scope, "custom" .. tostring(index), 24, -34, w - 48, 176))
    local dummyBox, dummyRefresh = BuildMiniAuraPreview(ctx, section, scope, 24, -220, w - 48, 176, nil, {
        customIndex = index,
        title = index == 4
            and (scope == "player" and "Defensive Buff Style Preview" or "Tracked DoT Style Preview")
            or "Dummy + Whitelist Style Preview",
    })
    local meta = W.Text(section, "", 24, -414, w - 48, T.colors.muted)
    local function RefreshCustomPreview()
        RefreshMiniAuraPreviewNow(liveRefresh)
        RefreshMiniAuraPreviewNow(dummyRefresh)
        local item = Model.CustomContainer(scope, index, true)
        local placed = item and type(item.placed) == "table" and item.placed or {}
        local frame = item and type(item.frame) == "table" and item.frame or {}
        local count
        if type(Model.CustomContainerPreviewEntries) == "function" then
            count = #Model.CustomContainerPreviewEntries(scope, index)
        else
            count = type(Model.CustomContainerSpellEntries) == "function"
                and #Model.CustomContainerSpellEntries(scope, index) or 0
        end
        meta:SetText(tostring(tonumber(placed.size) or 24) .. "px · " .. tostring(tonumber(placed.spacing) or 2)
            .. " gap · " .. tostring(tonumber(placed.perRow) or 4) .. " per row · " .. tostring(count)
            .. " whitelisted · Full-Frame: " .. tostring(frame.type or "none"))
        RefreshCustomPreviewEffect(dummyBox, item)
    end
    ctx._auraAppearancePreviewRefresh = RefreshCustomPreview
    M.TrackRefresh(ctx, RefreshCustomPreview)
    return section
end
local function BuildAuraStylePage(ctx)
    local b = W.PageBuilder(ctx)
    Model.EnsureDB()
    b:GlobalStyleHeader("Aura Style", "Text, cooldown, stack and marker styling.", 72)
    local scope = BuildAuraStyleScopeOverrideSection(ctx, b)
    local container = BuildAuraStyleNav(ctx, b, scope)
    if tostring(container):match("^custom[1234]$") then
        local index = tonumber(container:match("(%d)$")) or 1
        BuildCustomAuraStylePreview(ctx, b, scope, index)
        M.BuildAuras3CompactCustomWorkspace(ctx, b, scope, index, "appearance")
        M.BuildAuras3CompactCustomWorkspace(ctx, b, scope, index, "effect")
        M.BuildAuras3CompactCustomWorkspace(ctx, b, scope, index, "behavior")
    elseif IsGroupScope(scope) then
        BuildGroupStyle(ctx, b, scope)
    else
        SetCurrentLane("auraStyleGFLane", container)
        BuildUnitStyle(ctx, b, scope)
    end
    FinishPage(ctx, b)
end
local function BuildAuraStyleLanePage(ctx, lane)
    SetCurrentLane("auraStyleGFLane", lane)
    M.SetMenuStateValue("auraStyleContainer", lane)
    BuildAuraStylePage(ctx)
end
local function GFReadBlacklistCat(scope, groupKey, catKey)
    if Model and type(Model.ReadGroupBlacklistCategory) == "function" then return Model.ReadGroupBlacklistCategory(scope, groupKey, catKey) end
    local group = GFReadGroup(scope, groupKey)
    return type(group.blacklistCats) == "table" and group.blacklistCats[catKey] == true
end
local function GFInvalidateBlacklist(scope, groupKey)
    local af = AuraFilter()
    local a, b = GroupScopeKinds(scope)
    if af and type(af.InvalidateBlacklistHash) == "function" then
        af.InvalidateBlacklistHash(GFAuraGroup(a, groupKey))
        if b then af.InvalidateBlacklistHash(GFAuraGroup(b, groupKey)) end
    end
    local gf = MSUF and MSUF.GF
    if gf and type(gf.InvalidateCompiledSpecs) == "function" then
        gf.InvalidateCompiledSpecs(a)
        if b then gf.InvalidateCompiledSpecs(b) end
    end
end
local function GFWriteBlacklistCat(scope, groupKey, catKey, value)
    if Model and type(Model.WriteGroupBlacklistCategory) == "function" then
        local changed = Model.WriteGroupBlacklistCategory(scope, groupKey, catKey, value)
        if changed then QueueGroupScope(scope, "visual") end
        return
    end
    local changed
    local a, b = GroupScopeKinds(scope)
    local function write(kind)
        local group = GFAuraGroup(kind, groupKey)
        group.blacklistCats = group.blacklistCats or {}
        local nextValue = value and true or nil
        if group.blacklistCats[catKey] == nextValue then return end
        group.blacklistCats[catKey] = nextValue
        changed = true
    end
    write(a)
    if b then write(b) end
    if changed then
        GFInvalidateBlacklist(scope, groupKey)
        QueueGroupScope(scope, "visual")
    end
end
local function CategoryLabel(cat)
    if cat and cat.key == "RAID_BUFFS" then return "Raid / Mythic Buffs" end
    return (cat and cat.label) or (cat and cat.key) or ""
end
local function BuildGroupFilters(ctx, b, scope, fixedLane, opts)
    opts = opts or {}
    local laneKey = fixedLane == "debuff" and "debuff" or (fixedLane == "buff" and "buff" or CurrentLane("auraFilterLane", "buff"))
    local embedded = opts.parent ~= nil
    local tool = embedded and tostring(opts.tool or "") or ""
    local showFilter = tool ~= "blacklist"
    local showBlacklist = tool ~= "filters"
    local af = AuraFilter()
    local meta = af and af.DECLASSIFIED_META
    if type(meta) ~= "table" then meta = {} end
    local half = ceil(#meta / 2)
    local categoryHeight = max(356, 180 + half * 30)
    local originY = embedded and (tonumber(opts.originY) or -400) or 0
    local blacklistY = showFilter and (originY - (laneKey == "debuff" and 362 or 304)) or (originY - 42)
    local directY = blacklistY - categoryHeight - 24
    local standaloneHeight = max(930, abs(directY) + (laneKey == "debuff" and 270 or 324))
    local section = opts.parent or b:CollapsibleSection("group_aura_filters_" .. tostring(scope) .. "_" .. laneKey, "Group Frame Blizzard Filters & Lists", standaloneHeight, false)
    local w = section._msuf2Width or b.width or 720
    local lane = laneKey
    local groupActionPath = "group-blacklist.scope." .. AuraCatalogToken(scope)
        .. ".lane." .. AuraCatalogToken(lane)
    local laneText = lane == "buff" and "Buff" or "Debuff"
    local function ReadHidePermanent()
        return type(Model.ReadGroupBlacklistHidePermanent) == "function"
            and Model.ReadGroupBlacklistHidePermanent(scope, lane) == true
    end
    local function WriteHidePermanent(value)
        if type(Model.WriteGroupBlacklistHidePermanent) == "function"
            and Model.WriteGroupBlacklistHidePermanent(scope, lane, value) then
            QueueGroupScope(scope, "visual")
        end
    end
    local function ReadMaxDuration()
        return type(Model.ReadGroupBlacklistMaxDuration) == "function"
            and Model.ReadGroupBlacklistMaxDuration(scope, lane) or 0
    end
    local function WriteMaxDuration(value)
        if type(Model.WriteGroupBlacklistMaxDuration) == "function"
            and Model.WriteGroupBlacklistMaxDuration(scope, lane, value) then
            QueueGroupScope(scope, "visual")
        end
    end
    local function AddHidePermanentTooltip(control)
        AddTooltip(control, "Hide permanent auras", "Always excludes auras without a duration. This native rule wins over SpellID blacklists and whitelists.")
    end
    local filterW = w - 48
    if embedded and tool == "" then
        W.DividerAt(section, originY - 4, 16, 16)
        W.LabelAt(section, "Blizzard Filters & Lists", 24, originY - 24, w - 48, "GameFontNormal", T.colors.accent)
    end
    if showFilter then
        local filter = Card(section, "Native " .. laneText .. " Filter", "Filter token for " .. ScopeLabel(scope) .. " group-frame " .. laneText .. "s.", 24, originY - 42, filterW, lane == "debuff" and 296 or 234)
        W.LabelAt(filter, fixedLane and (laneText .. " Content") or "Filter Type", 16, -72, fixedLane and 260 or 90, "GameFontNormalSmall", T.colors.accent)
        if not fixedLane then BuildLaneTabs(ctx, filter, "auraFilterLane", 112, -68, min(300, w - 180)) end
        local dropdownW = min(360, max(240, floor((filterW - 48) * 0.55)))
        BindGroupDropdown(ctx, filter, laneText .. " Filter", 16, -142, GroupFilterValues(lane), dropdownW, scope, lane, "filterToken", "ALL", "visual")
        W.Text(filter, "Choose which auras Blizzard provides for this lane.", 40 + dropdownW, -142, max(220, filterW - dropdownW - 64), T.colors.muted)
        local hidePermanent = BindSwitch(ctx, filter, "Hide permanent auras", 16, -192, dropdownW,
            ReadHidePermanent, WriteHidePermanent,
            AuraControlMeta(ctx, "group-filter.lane." .. AuraCatalogToken(lane) .. ".hide-permanent"))
        AddHidePermanentTooltip(hidePermanent)
        if lane == "debuff" then
            ConfigureMaxDurationSlider(BindSlider(ctx, filter, "Maximum duration", 16, -230, 0, 180, 1, filterW - 32,
                ReadMaxDuration, WriteMaxDuration,
                AuraControlMeta(ctx, "group-filter.lane.debuff.max-duration", nil, {
                    assistantDisposition = "compound",
                    assistantDispositionReason = "The native candidate-filter duration limit has no Assistant setting contract yet.",
                })))
        end
    end
    if not showBlacklist then return end
    local blacklist = Card(section, "Category Blacklist", nil, 24, blacklistY, w - 48, categoryHeight)
    W.LabelAt(blacklist, "Active", 16, -50, 70, "GameFontNormalSmall", T.colors.accent)
    W.LabelAt(blacklist, lane == "buff" and "Buff category blacklist" or "Debuff category blacklist", 86, -50, 260, "GameFontHighlightSmall", T.colors.text)
    W.Text(blacklist, NATIVE_EXACT_AURA_FILTERS_TEXT, 16, -72, w - 96, T.colors.muted)
    if #meta == 0 then
        W.Text(blacklist, "No public aura category data is loaded.", 16, -132, w - 96, T.colors.muted)
    end
    local catColW = max(230, floor((w - 104) / 2))
    local x2 = 16 + catColW + 24
    local startY = -152
    local categoryControls = {}
    for i = 1, #meta do
        local cat = meta[i]
        local col = i <= half and 0 or 1
        local row = col == 0 and (i - 1) or (i - half - 1)
        local tx = col == 0 and 16 or x2
        local toggle = BindToggle(ctx, blacklist, CategoryLabel(cat), tx, startY - row * 30, catColW,
            function() return GFReadBlacklistCat(scope, lane, cat.key) end,
            function(v) GFWriteBlacklistCat(scope, lane, cat.key, v) end,
            AuraControlMeta(ctx, "group-blacklist.lane." .. AuraCatalogToken(lane) .. ".category." .. AuraCatalogToken(cat.key)))
        if cat.tooltip then AddTooltip(toggle, CategoryLabel(cat), cat.tooltip) end
        categoryControls[#categoryControls + 1] = toggle
    end
    local direct = Card(section, "Exact SpellID Blacklist", "Frame-specific exclusions for this Group Frame lane.", 24, directY, w - 48, lane == "debuff" and 246 or 300)
    -- Debuff lane only: the free-form spell-ID entry was removed on purpose.
    -- 12.x debuff data is secret at runtime, so only the curated never-secret
    -- preset spells can actually match; entries come from the presets below.
    local directInput, directAdd, directRemove
    if lane ~= "debuff" then
        local directInputValue = ""
        local directInputW = max(260, floor((w - 96) * 0.46))
        directInput = BindTextInput(ctx, direct, "Spell ID, spell link, or spell name", 16, -72, directInputW,
            function() return directInputValue end,
            function(value) directInputValue = value or "" end,
            false, AuraControlMeta(ctx, "group-blacklist.lane." .. AuraCatalogToken(lane) .. ".manual-input", "ephemeral"))
        directAdd = ActionButton(direct, "Add", 90)
        directAdd:SetPoint("TOPLEFT", direct, "TOPLEFT", 28 + directInputW, -92)
        directAdd:SetScript("OnClick", function()
            local value = directInput and directInput.GetText and directInput:GetText() or directInputValue
            local changed = Model.AddGroupBlacklistSpell(scope, lane, value)
            if changed then
                if directInput and directInput.SetText then directInput:SetText("") end
                directInputValue = ""
                QueueGroupScope(scope, "visual")
                Rebuild(ctx)
            end
            return changed and true or false
        end)
        RegisterAuraTextAction(ctx, directAdd, directInput, "Add", groupActionPath .. ".add", {
            actionKey = "aura_group_blacklist_add_spell", actionFixedArgs = { scope = scope, lane = lane }, actionInputArg = "value",
        })
        directRemove = ActionButton(direct, "Remove", 96)
        directRemove:SetPoint("LEFT", directAdd, "RIGHT", 8, 0)
        directRemove:SetScript("OnClick", function()
            local value = directInput and directInput.GetText and directInput:GetText() or directInputValue
            local changed = Model.RemoveGroupBlacklistSpell(scope, lane, value)
            if changed then
                QueueGroupScope(scope, "visual")
                Rebuild(ctx)
            end
            return changed and true or false
        end)
        RegisterAuraTextAction(ctx, directRemove, directInput, "Remove", groupActionPath .. ".remove", {
            actionKey = "aura_group_blacklist_remove_spell", actionFixedArgs = { scope = scope, lane = lane }, actionInputArg = "value",
        })
    end
    local presetW = max(152, floor((w - 96) * 0.22))
    local spellW = max(210, floor((w - 96) * 0.30))
    local function CurrentPreset()
        local key = M.auraBlacklistPreset or "RAID_BUFFS"
        local values = Model.BlacklistPresetValues()
        for i = 1, #values do if values[i].value == key then return key end end
        return values[1] and values[1].value or "RAID_BUFFS"
    end
    local directPresetY = lane == "debuff" and -72 or -126
    local preset = W.Dropdown(direct, "Preset", function() return Model.BlacklistPresetValues() end, presetW)
    W.MoveWidget(preset, direct, 16, directPresetY, presetW)
    M.BindDropdownWidget(ctx, preset, CurrentPreset, function(value)
        M.auraBlacklistPreset = value
        M.auraBlacklistSpell = nil
        QueueAurasPageRefresh(ctx, "group-aura-blacklist-preset")
    end, AuraControlMeta(ctx, "group-blacklist.lane." .. AuraCatalogToken(lane) .. ".preset-selection", "ephemeral"))
    local spell = W.Dropdown(direct, "Spell", function() return Model.BlacklistSpellValues(CurrentPreset()) end, spellW)
    W.MoveWidget(spell, direct, 26 + presetW, directPresetY, spellW)
    M.BindDropdownWidget(ctx, spell,
        function()
            local values, selected = Model.BlacklistSpellValues(CurrentPreset()), M.auraBlacklistSpell
            for i = 1, #values do if values[i].value == selected then return selected end end
            return values[1] and values[1].value or nil
        end,
        function(value) M.auraBlacklistSpell = value end,
        AuraControlMeta(ctx, "group-blacklist.lane." .. AuraCatalogToken(lane) .. ".spell-selection", "ephemeral"))
    local addSpell = ActionButton(direct, "Add spell", 96)
    addSpell:SetPoint("TOPLEFT", direct, "TOPLEFT", 36 + presetW + spellW, directPresetY - 22)
    addSpell:SetScript("OnClick", function()
        local values = Model.BlacklistSpellValues(CurrentPreset())
        local spellID = M.auraBlacklistSpell or (values[1] and values[1].value)
        if Model.AddGroupBlacklistSpell(scope, lane, spellID) then
            QueueGroupScope(scope, "visual")
            Rebuild(ctx)
        end
    end)
    RegisterAuraControl(ctx, addSpell, "Add spell", "button", groupActionPath .. ".add-preset-spell", "action", {
        actionKey = "aura_group_blacklist_add_spell", actionFixedArgs = { scope = scope, lane = lane }, actionInputArg = "value",
    })
    local addSet = ActionButton(direct, "Add set", 88)
    addSet:SetPoint("LEFT", addSpell, "RIGHT", 8, 0)
    addSet:SetScript("OnClick", function()
        if Model.AddGroupBlacklistPresetGroup(scope, lane, CurrentPreset()) > 0 then
            QueueGroupScope(scope, "visual")
            Rebuild(ctx)
        end
    end)
    RegisterAuraControl(ctx, addSet, "Add set", "button", groupActionPath .. ".add-preset-set", "action", {
        actionKey = "aura_group_blacklist_add_preset", actionFixedArgs = { scope = scope, lane = lane }, actionInputArg = "preset",
    })
    local prepared = W.Text(direct, "", 16, directPresetY - 84, w - 80, T.colors.accent)
    local empty = W.Text(direct, lane == "debuff" and "No blacklisted spells. Add one from the presets above."
        or "No blacklisted spells. Add one above or use a preset.", 16, directPresetY - 120, w - 80, T.colors.muted)
    local listScroll = CreateFrame("ScrollFrame", nil, direct, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", direct, "TOPLEFT", 16, directPresetY - 110)
    listScroll:SetSize(w - 108, 48)
    if listScroll.EnableMouseWheel then listScroll:EnableMouseWheel(true) end
    local listChild = CreateFrame("Frame", nil, listScroll)
    listChild:SetSize(w - 130, 48)
    listScroll:SetScrollChild(listChild)
    if listScroll.SetPropagateMouseWheel then listScroll:SetPropagateMouseWheel(false) end
    listScroll:SetScript("OnMouseWheel", function(self, delta) HandleNestedScrollWheel(self, delta, 28) end)
    local rows = {}
    local function EnsureRow(index)
        local row = rows[index]
        if row then return row end
        row = CreateFrame("Button", nil, listChild)
        row:SetPoint("TOPLEFT", listChild, "TOPLEFT", 0, -((index - 1) * 24))
        row:SetPoint("TOPRIGHT", listChild, "TOPRIGHT", 0, -((index - 1) * 24))
        row:SetHeight(20)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetPoint("LEFT", row, "LEFT", 3, 0)
        row.icon:SetSize(17, 17)
        row.text = T.Font(row, "GameFontHighlightSmall", "", T.colors.text)
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
        row:SetScript("OnClick", function(self)
            if self._spellID and Model.RemoveGroupBlacklistSpell(scope, lane, self._spellID) then
                QueueGroupScope(scope, "visual")
                Rebuild(ctx)
            end
        end)
        rows[index] = row
        return row
    end
    M.TrackRefresh(ctx, function()
        W.SetControlsEnabled(categoryControls, NATIVE_EXACT_AURA_FILTERS_ENABLED)
        W.SetControlsEnabled({ preset, spell, addSpell, addSet }, NATIVE_EXACT_AURA_FILTERS_ENABLED)
        if directInput then
            W.SetControlsEnabled({ directInput, directAdd, directRemove }, NATIVE_EXACT_AURA_FILTERS_ENABLED)
        end
        local entries = type(Model.GroupBlacklistEntries) == "function" and Model.GroupBlacklistEntries(scope, lane) or {}
        prepared:SetText((#entries == 1 and "1 blocked spell" or tostring(#entries) .. " blocked spells") .. " · click an entry to remove")
        empty:SetShown(#entries == 0)
        listScroll:SetShown(#entries > 0)
        listChild:SetHeight(max(48, #entries * 24))
        for i = 1, max(#rows, #entries) do
            local row, entry = rows[i], entries[i]
            if entry then
                row = EnsureRow(i)
                row._spellID = entry.value
                row.icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                row.text:SetText(entry.text or entry.value)
                RegisterAuraControl(ctx, row, entry.text or entry.value or "Blacklist entry", "button",
                    "group-blacklist.lane." .. AuraCatalogToken(lane) .. ".entry." .. AuraCatalogToken(entry.value) .. ".remove", "action")
                row:Show()
            elseif row then
                row._spellID = nil
                row:Hide()
            end
        end
    end)
end
local function UniformChoiceWidths(values, width)
    for i = 1, #values do values[i].width = width end
    return values
end
local UNIT_AURA_CHOICE_WIDTH = 92
local UNIT_AURA_WORKSPACE_TABS = UniformChoiceWidths(VTP "buff=Buffs|debuff=Debuffs|custom1=Custom 1|custom2=Custom 2|custom3=Custom 3|custom4=Dots on target", UNIT_AURA_CHOICE_WIDTH)
M._unitAuraWorkspaceTabsPlayer = UniformChoiceWidths(VTP "buff=Buffs|debuff=Debuffs|custom1=Custom 1|custom2=Custom 2|custom3=Custom 3|custom4=Defensives", UNIT_AURA_CHOICE_WIDTH)
local UNIT_AURA_NORMAL_TOOLS = UniformChoiceWidths(VTP "layout=Layout|filters=Filters|blacklist=Blacklist", UNIT_AURA_CHOICE_WIDTH)
local UNIT_AURA_CUSTOM_TOOLS = UniformChoiceWidths(VTP "setup=Setup|layout=Layout|filters=Filters|whitelist=Whitelist", UNIT_AURA_CHOICE_WIDTH)
local UNIT_AURA_TARGET_DOT_TOOLS = UniformChoiceWidths(VTP "setup=Setup|layout=Layout|dots=Dots", UNIT_AURA_CHOICE_WIDTH)
M._unitAuraPlayerDefensiveTools = UniformChoiceWidths(VTP "setup=Setup|layout=Layout|defensives=Defensives", UNIT_AURA_CHOICE_WIDTH)
local UNIT_AURA_NORMAL_TOOL_OK = { layout = true, filters = true, blacklist = true }
local UNIT_AURA_CUSTOM_TOOL_OK = { setup = true, whitelist = true, filters = true, layout = true }
local UNIT_AURA_TARGET_DOT_TOOL_OK = { setup = true, layout = true, dots = true }

local function CurrentUnitAuraTool(unit, container)
    M.unitAuraToolSelection = M.unitAuraToolSelection or {}
    local unitState = M.unitAuraToolSelection[unit]
    if type(unitState) ~= "table" then unitState = {}; M.unitAuraToolSelection[unit] = unitState end
    local custom = tostring(container or ""):match("^custom") ~= nil
    local playerDefensives = unit == "player" and container == "custom4"
    local targetDots = unit ~= "player" and container == "custom4"
    local tool = unitState[container]
    local valid = playerDefensives and { setup = true, layout = true, defensives = true }
        or (targetDots and UNIT_AURA_TARGET_DOT_TOOL_OK or (custom and UNIT_AURA_CUSTOM_TOOL_OK or UNIT_AURA_NORMAL_TOOL_OK))
    if not valid[tool] then tool = custom and "setup" or "layout"; unitState[container] = tool end
    return tool
end

local function SetUnitAuraTool(unit, container, tool)
    M.unitAuraToolSelection = M.unitAuraToolSelection or {}
    local unitState = M.unitAuraToolSelection[unit]
    if type(unitState) ~= "table" then unitState = {}; M.unitAuraToolSelection[unit] = unitState end
    unitState[container] = tool
end

local function BuildCompactUnitAuraLayout(ctx, b, unit, kind)
    local title = kind == "debuff" and "Debuff Layout" or "Buff Layout"
    -- Stufe-1 pilot: this section renders through the uniform W.SettingsRows
    -- grid (fixed cell metrics, per-value reset) instead of hand-placed
    -- offsets. Control identities, setters and apply reasons are unchanged.
    local section = b:Section(title, 208)
    M.AttachAuraFontsAndColors(section, title, unit)
    local w = section._msuf2Width or b.width or 720
    local inner = w - 48
    local gap = 12
    local controls = {}
    local enable = BindSwitch(ctx, section, "Visible", 24, -62, 104,
        function() return UnitLaneShown(unit, kind) end,
        function(v) SetUnitLaneShown(ctx, unit, kind, v, "AURAS3_UNIT_PAGE_" .. (kind == "buff" and "BUFFS" or "DEBUFFS")) end,
        AuraControlMeta(ctx, "unit-workspace.lane." .. AuraCatalogToken(kind) .. ".layout.visible", nil,
            "auras3." .. unit .. "." .. kind .. ".visible"))
    enable._msuf2GroupFrameGateAlwaysEnabled = true
    local function LaneMeta(row, pathSuffix)
        local meta = AuraControlMeta(ctx, "unit-workspace.lane." .. AuraCatalogToken(kind) .. ".layout." .. pathSuffix)
        for key, value in pairs(meta) do
            if row[key] == nil then row[key] = value end
        end
        return row
    end
    local defaultAnchor = kind == "buff" and "BOTTOMRIGHT" or "TOPLEFT"
    local anchorRows = W.SettingsRows(ctx, section, {
        x = 24 + 126 + gap, y = -34, width = inner - 126 - gap, columns = 2, colGap = gap,
        rows = {
            LaneMeta({
                kind = "dropdown", label = "Anchor", id = "anchor",
                values = function()
                    return type(Model.AuraAnchorValues) == "function" and Model.AuraAnchorValues() or GFAnchorValues()
                end,
                get = function()
                    return type(Model.ReadLaneAnchor) == "function" and Model.ReadLaneAnchor(unit, kind) or defaultAnchor
                end,
                set = function(v)
                    if type(Model.WriteLaneAnchor) == "function" then
                        Model.WriteLaneAnchor(unit, kind, v)
                        ApplyUnit(ctx, unit, "AURAS3_UNIT_ANCHOR")
                    end
                end,
            }, "anchor"),
            LaneMeta({
                kind = "dropdown", label = "Growth", id = "growth",
                values = function()
                    return type(Model.LaneGrowthValues) == "function" and Model.LaneGrowthValues() or Model.GrowthValues()
                end,
                get = function()
                    return type(Model.ReadLaneGrowthPair) == "function" and Model.ReadLaneGrowthPair(unit, kind) or Model.ReadLaneGrowth(unit, kind)
                end,
                set = function(v)
                    if type(Model.WriteLaneGrowthPair) == "function" then Model.WriteLaneGrowthPair(unit, kind, v) else Model.WriteLaneGrowth(unit, kind, v) end
                    ApplyUnit(ctx, unit, "AURAS3_UNIT_GROWTH")
                end,
            }, "growth"),
        },
    })
    local function NumberRow(label, id, semanticKey, minValue, maxValue, defaultValue, getValue, setValue)
        return LaneMeta({
            kind = "slider", label = label, id = id,
            min = minValue, max = maxValue, step = 1, default = defaultValue,
            get = getValue, set = setValue,
        }, AuraCatalogToken(semanticKey))
    end
    local numberRows = W.SettingsRows(ctx, section, {
        x = 24, y = -92, width = inner, columns = 4, colGap = gap,
        rows = {
            NumberRow("X", "x", "offset-x", -300, 300, 0,
                function() return Model.ReadNumber(unit, LaneXKey(kind), 0, -4096, 4096) end,
                function(v) Model.WriteNumber(unit, LaneXKey(kind), v, -4096, 4096); ApplyUnit(ctx, unit, "AURAS3_UNIT_X") end),
            NumberRow("Y", "y", "offset-y", -300, 300, LaneDefaultY(kind),
                function() return Model.ReadNumber(unit, LaneYKey(kind), LaneDefaultY(kind), -4096, 4096) end,
                function(v) Model.WriteNumber(unit, LaneYKey(kind), v, -4096, 4096); ApplyUnit(ctx, unit, "AURAS3_UNIT_Y") end),
            NumberRow("Max", "max", "max-icons", 0, 80, LaneDefaultMax(kind),
                function() return Model.ReadNumber(unit, LaneMaxKey(kind), LaneDefaultMax(kind), 0, 80) end,
                function(v) Model.WriteNumber(unit, LaneMaxKey(kind), v, 0, 80); ApplyUnit(ctx, unit, "AURAS3_UNIT_MAX") end),
            NumberRow("Size", "size", "icon-size", 10, 80, 26,
                function() return Model.ReadNumber(unit, LaneSizeKey(kind), 26, 1, 128) end,
                function(v) Model.WriteNumber(unit, LaneSizeKey(kind), v, 1, 128); ApplyUnit(ctx, unit, "AURAS3_UNIT_SIZE") end),
            NumberRow("Per row", "perRow", "per-row", 1, 40, nil,
                function() return Model.ReadLanePerRow(unit, kind) end,
                function(v) Model.WriteLanePerRow(unit, kind, v); ApplyUnit(ctx, unit, "AURAS3_UNIT_PER_ROW") end),
            NumberRow("Gap", "gap", "spacing", 0, 12, 2,
                function() return Model.ReadNumber(unit, "spacing", 2, 0, 64) end,
                function(v) Model.WriteNumber(unit, "spacing", v, 0, 64); ApplyUnit(ctx, unit, "AURAS3_UNIT_SPACING") end),
            NumberRow("Layer (0-30)", "layer", "layer", 0, 30, kind == "buff" and 5 or 6,
                function() return type(Model.ReadLaneLayer) == "function" and Model.ReadLaneLayer(unit, kind) or (kind == "buff" and 5 or 6) end,
                function(v) if type(Model.WriteLaneLayer) == "function" then Model.WriteLaneLayer(unit, kind, v); ApplyUnit(ctx, unit, "AURAS3_UNIT_LAYER") end end),
        },
    })
    local function CollectRows(result)
        if not result then return end
        for i = 1, #result.list do controls[#controls + 1] = result.list[i] end
        for i = 1, #result.resets do controls[#controls + 1] = result.resets[i] end
    end
    CollectRows(anchorRows)
    CollectRows(numberRows)
    local perRowControl = numberRows and numberRows.controls and numberRows.controls.perRow
    M.TrackRefresh(ctx, function()
        local shown = UnitLaneShown(unit, kind)
        W.SetControlEnabled(enable, true)
        W.SetControlsEnabled(controls, shown)
        local growth = type(Model.ReadLaneGrowthPair) == "function" and Model.ReadLaneGrowthPair(unit, kind)
            or Model.ReadLaneGrowth(unit, kind)
        growth = tostring(growth or ""):upper()
        if perRowControl then
            W.SetControlEnabled(perRowControl, shown and growth ~= "UP" and growth ~= "DOWN")
        end
    end)
end

local function BuildCompactUnitAuraFilters(ctx, b, unit, lane)
    local section = b:Section((lane == "debuff" and "Debuff" or "Buff") .. " Filters", lane == "debuff" and 224 or 182)
    local w = section._msuf2Width or b.width or 720
    local inner = w - 48
    local gap = 12
    local colW = floor((inner - gap * 3) / 4)
    local filterControls = {}
    local own = BindSwitch(ctx, section, "Own filters", 24, -42, colW,
        function() return not Model.UseSharedRules(unit) end,
        function(enabled)
            Model.SetUseSharedRules(unit, not enabled)
            ApplyUnit(ctx, unit, "AURAS3_UNIT_FILTER_OWNERSHIP", true)
            Rebuild(ctx)
        end,
        AuraControlMeta(ctx, "unit-workspace.lane." .. AuraCatalogToken(lane) .. ".filters.ownership", nil, {
            assistantDisposition = "compound",
            assistantDispositionReason = "Own filters is the inverse projection of Use Shared Rules and rebuilds the lane editor.",
        }))
    AddTooltip(own, "Filter ownership", "Off follows Shared Blizzard filter tokens. Blacklists and Custom whitelists are always frame-specific.")
    local enabled = BindSwitch(ctx, section, "Enable filters", 24 + colW + gap, -42, colW,
        function() return Model.ScopeFiltersEnabled(unit) end,
        function(value) Model.SetScopeFiltersEnabled(unit, value); ApplyUnit(ctx, unit, "AURAS3_FILTER_ENABLE", true) end,
        AuraControlMeta(ctx, "unit-workspace.lane." .. AuraCatalogToken(lane) .. ".filters.enabled", nil,
            "auras3." .. unit .. ".filtersEnabled"))
    local hidePermanent = BindSwitch(ctx, section, "Hide permanent", 24 + 2 * (colW + gap), -42, colW,
        function()
            return type(Model.ReadBlacklistHidePermanent) == "function"
                and Model.ReadBlacklistHidePermanent(unit, lane) == true
        end,
        function(value)
            if type(Model.WriteBlacklistHidePermanent) == "function"
                and Model.WriteBlacklistHidePermanent(unit, lane, value) then
                ApplyUnit(ctx, unit, "AURAS3_HIDE_PERMANENT", true)
            end
        end,
        AuraControlMeta(ctx, "unit-workspace.lane." .. AuraCatalogToken(lane) .. ".filters.hide-permanent", nil,
            "auras3." .. unit .. "." .. lane .. ".blacklist.hidePermanent"))
    AddTooltip(hidePermanent, "Hide permanent auras", "Always excludes auras without a duration, even when Blizzard token filters are disabled.")
    local maxDuration
    if lane == "debuff" then
        maxDuration = ConfigureMaxDurationSlider(BindSlider(ctx, section, "Maximum duration", 24, -142, 0, 180, 1, inner,
            function()
                return type(Model.ReadBlacklistMaxDuration) == "function"
                    and Model.ReadBlacklistMaxDuration(unit, lane) or 0
            end,
            function(value)
                if type(Model.WriteBlacklistMaxDuration) == "function"
                    and Model.WriteBlacklistMaxDuration(unit, lane, value) then
                    ApplyUnit(ctx, unit, "AURAS3_DEBUFF_MAX_DURATION", true)
                end
            end,
            AuraControlMeta(ctx, "unit-workspace.lane.debuff.filters.max-duration", nil, {
                assistantDisposition = "compound",
                assistantDispositionReason = "The native candidate-filter duration limit has no Assistant setting contract yet.",
            })))
    end
    local specs = lane == "buff" and {
        { "Only mine", "onlyMine", "Only auras applied by the player." },
        { "Important", "onlyImportant", "Only auras Blizzard flags as important." },
        { "Applicable by me", "raid", "Helpful auras your character can apply (Blizzard RAID token)." },
        { "Raid combat", "raidInCombat", "Blizzard's in-combat raid Buff filter." },
        { "Nameplate-only", "includeNameplateOnly", "Include Buffs marked nameplate-only." },
        { "Dispellable / stealable by group", "includeDispellable", "Helpful enemy auras someone in your group can dispel, purge, or steal." },
        { "Any dispel / steal type", "dispellableAny", "Helpful enemy auras with any dispel type, even when your group cannot remove them." },
        { "External defensive", "externalDefensive", "External defensive Buffs." },
        { "Big defensive", "bigDefensive", "Major defensive Buffs." },
        { "Cancelable", "cancelable", "Only cancelable Buffs.", { "notCancelable" } },
        { "Not cancelable", "notCancelable", "Only non-cancelable Buffs.", { "cancelable" } },
    } or {
        { "Only mine", "onlyMine", "Only Debuffs applied by the player." },
        { "Important", "onlyImportant", "Only Debuffs Blizzard flags as important." },
        { "Dispellable by me", "raid", "Harmful auras your character can dispel (Blizzard RAID token)." },
        { "Raid combat", "raidInCombat", "Blizzard's in-combat raid Debuff filter." },
        { "Nameplate-only", "includeNameplateOnly", "Include Debuffs marked nameplate-only." },
        { "Dispellable by group", "includeDispellable", "Debuffs someone in your group can dispel." },
        { "Any dispel type", "dispellableAny", "Debuffs with a dispel type, even when your group cannot remove them." },
        { "Crowd control", "crowdControl", "Crowd-control Debuffs." },
    }
    for i = 1, #specs do
        local spec = specs[i]
        local col = ((i - 1) % 4)
        local row = floor((i - 1) / 4)
        local settingContract = "auras3." .. unit .. "." .. lane .. ".filter." .. spec[2]
        if lane == "debuff" and spec[2] == "raid" then
            settingContract = {
                assistantDisposition = "dynamic",
                assistantDispositionReason = "The visible Raid switch folds the legacy exclusive Raid value into the canonical Debuff Raid filter.",
                assistantSettingKeys = {
                    "auras3." .. unit .. ".debuff.filter.raid",
                    "auras3." .. unit .. ".debuff.filter.exclusive",
                },
            }
        end
        local control = BindSwitch(ctx, section, spec[1], 24 + col * (colW + gap), -78 - row * 32, colW,
            function()
                if spec[2] == "raid" and Model.ReadFilter(unit, lane, "exclusive", "none") == "raid" then
                    return true
                end
                return Model.ReadFilter(unit, lane, spec[2], false) == true
            end,
            function(value)
                if value == true and type(spec[4]) == "table" then for j = 1, #spec[4] do Model.WriteFilter(unit, lane, spec[4][j], false) end end
                -- Older profiles stored the same RAID token in a second
                -- Exclusive dropdown. Fold it into the visible Raid switch so
                -- the legacy restriction can also be turned off here.
                if spec[2] == "raid" then Model.WriteFilter(unit, lane, "exclusive", "none") end
                Model.WriteFilter(unit, lane, spec[2], value)
                ApplyUnit(ctx, unit, "AURAS3_FILTER_" .. lane .. "_" .. spec[2], true)
                if spec[4] then QueueAurasPageRefresh(ctx, "auras-filter-conflict") end
            end,
            AuraControlMeta(ctx, "unit-workspace.lane." .. AuraCatalogToken(lane) .. ".filters." .. AuraCatalogToken(spec[2]), nil,
                settingContract))
        AddTooltip(control, spec[1], spec[3])
        filterControls[#filterControls + 1] = control
    end
    M.TrackRefresh(ctx, function()
        local editable = not Model.UseSharedRules(unit)
        W.SetControlEnabled(own, true)
        W.SetControlEnabled(enabled, editable)
        W.SetControlEnabled(hidePermanent, true)
        W.SetControlEnabled(maxDuration, true)
        W.SetControlsEnabled(filterControls, editable and Model.ScopeFiltersEnabled(unit))
    end)
end

local function BuildCompactUnitAuraBlacklist(ctx, b, unit, lane)
    local laneTitle = lane == "debuff" and "Debuff" or "Buff"
    local isDebuff = lane == "debuff"
    local section = b:Section(laneTitle .. " Blacklist", isDebuff and 446 or 528)
    local w = section._msuf2Width or b.width or 720
    local inner = w - 48
    if not isDebuff then
        local inputValue = ""
        local inputW = max(140, min(floor(inner * 0.62), inner - 130))
        local input = BindTextInput(ctx, section, "Enter buff Spell ID, link, or name", 24, -36, inputW,
            function() return inputValue end, function(value) inputValue = value or "" end,
            false, AuraControlMeta(ctx, "unit-workspace.lane.buff.blacklist.manual-input", "ephemeral"))
        local add = ActionButton(section, "Add custom buff", 118, "primary")
        add:SetPoint("TOPLEFT", section, "TOPLEFT", 36 + inputW, -60)
        add:SetScript("OnClick", function()
            local value = input and input.GetText and input:GetText() or inputValue
            local changed = Model.AddBlacklistSpell(unit, value, lane)
            if changed then ApplyUnit(ctx, unit, "AURAS3_BLACKLIST_ADD", true) end
            if input and input.SetText then input:SetText("") end
            inputValue = ""
            return changed and true or false
        end)
        RegisterAuraTextAction(ctx, add, input, "Add custom buff", "unit-workspace.lane.buff.blacklist.add", {
            actionKey = "aura_blacklist_add_spell", actionFixedArgs = { scope = unit, lane = lane }, actionInputArg = "value",
        })
        AddTooltip(add, "Add custom buff", "Adds one exact buff to this frame's blacklist.")
    end
    local curatedOffset = isDebuff and 0 or -82
    local presetW = max(130, min(floor(inner * 0.62), inner - 138))
    local spellW = max(160, min(floor(inner * 0.68), inner - 108))
    local function CurrentPreset()
        local key = M.auraBlacklistPreset or "RAID_BUFFS"
        local values = Model.BlacklistPresetValues()
        for i = 1, #values do if values[i].value == key then return key end end
        return values[1] and values[1].value or "RAID_BUFFS"
    end
    local function CurrentSpell()
        local values, selected = Model.BlacklistSpellValues(CurrentPreset()), M.auraBlacklistSpell
        for i = 1, #values do if values[i].value == selected then return selected end end
        return values[1] and values[1].value or nil
    end
    local preset = W.Dropdown(section, "Preset", function() return Model.BlacklistPresetValues() end, presetW)
    W.MoveWidget(preset, section, 24, -36 + curatedOffset, presetW)
    M.BindDropdownWidget(ctx, preset, CurrentPreset, function(value) M.auraBlacklistPreset = value; M.auraBlacklistSpell = nil; QueueAurasPageRefresh(ctx, "aura-blacklist-preset") end,
        AuraControlMeta(ctx, "unit-workspace.lane." .. AuraCatalogToken(lane) .. ".blacklist.preset-selection", "ephemeral"))
    local addSet = ActionButton(section, "Add entire set", 126, "primary")
    addSet:SetPoint("TOPLEFT", section, "TOPLEFT", 36 + presetW, -60 + curatedOffset)
    addSet:SetScript("OnClick", function()
        local count = Model.AddBlacklistPresetGroup(unit, CurrentPreset(), lane)
        if count > 0 then ApplyUnit(ctx, unit, "AURAS3_BLACKLIST_PRESET_GROUP_ADD", true) end
        return count > 0
    end)
    RegisterAuraControl(ctx, addSet, "Add entire set", "button", "unit-workspace.lane." .. AuraCatalogToken(lane) .. ".blacklist.add-preset-set", "action", {
        actionKey = "aura_blacklist_add_preset", actionFixedArgs = { scope = unit, lane = lane }, actionInputArg = "preset",
    })
    AddTooltip(addSet, "Add entire set", "Blocks every aura in the selected curated MSUF set.")
    local selectedSummary = W.Text(section, "", 24, -92 + curatedOffset, inner, T.colors.muted)
    local spell = W.Dropdown(section, "Spell", function() return Model.BlacklistSpellValues(CurrentPreset()) end, spellW)
    W.MoveWidget(spell, section, 24, -120 + curatedOffset, spellW)
    M.BindDropdownWidget(ctx, spell,
        CurrentSpell,
        function(value) M.auraBlacklistSpell = value end,
        AuraControlMeta(ctx, "unit-workspace.lane." .. AuraCatalogToken(lane) .. ".blacklist.spell-selection", "ephemeral"))
    local addSpell = ActionButton(section, "Add spell", 96)
    addSpell:SetPoint("TOPLEFT", section, "TOPLEFT", 36 + spellW, -144 + curatedOffset)
    addSpell:SetScript("OnClick", function()
        local changed = Model.AddBlacklistPresetSpell(unit, CurrentSpell(), lane)
        if changed then ApplyUnit(ctx, unit, "AURAS3_BLACKLIST_PRESET_ADD", true) end
        return changed and true or false
    end)
    RegisterAuraControl(ctx, addSpell, "Add spell", "button", "unit-workspace.lane." .. AuraCatalogToken(lane) .. ".blacklist.add-preset-spell", "action", {
        actionKey = "aura_blacklist_add_spell", actionFixedArgs = { scope = unit, lane = lane }, actionInputArg = "value",
    })
    AddTooltip(addSpell, "Add spell", "Blocks only the selected aura from the curated set.")
    local prepared = W.Text(section, "", 24, -186 + curatedOffset, inner, T.colors.accent)
    local searchValue = ""
    local refreshList
    local searchInput = BindTextInput(ctx, section, "Search", 24, -210 + curatedOffset, inner,
        function() return searchValue end,
        function(value)
            searchValue = tostring(value or "")
            if refreshList then refreshList() end
        end,
        true, AuraControlMeta(ctx,
            "unit-workspace.lane." .. AuraCatalogToken(lane) .. ".blacklist.search", "ephemeral"))
    if searchInput and searchInput.HookScript then
        searchInput:HookScript("OnTextChanged", function(self)
            searchValue = self.GetText and tostring(self:GetText() or "") or ""
            if refreshList then refreshList() end
        end)
    end
    local emptyText = isDebuff and "No blocked spells. Add one from the presets above."
        or "No blocked spells. Add one above or use a preset."
    local empty = W.Text(section, emptyText, 24, -284 + curatedOffset, inner, T.colors.muted)
    local listScroll = CreateFrame("ScrollFrame", nil, section, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", section, "TOPLEFT", 24, -260 + curatedOffset)
    listScroll:SetSize(inner - 20, 150)
    if listScroll.EnableMouseWheel then listScroll:EnableMouseWheel(true) end
    local listChild = CreateFrame("Frame", nil, listScroll)
    listChild:SetSize(inner - 44, 150)
    listScroll:SetScrollChild(listChild)
    if listScroll.SetPropagateMouseWheel then listScroll:SetPropagateMouseWheel(false) end
    listScroll:SetScript("OnMouseWheel", function(self, delta) HandleNestedScrollWheel(self, delta, 44) end)
    local rows = {}
    local function EnsureRow(i)
        local row = rows[i]
        if row then return row end
        row = CreateFrame("Frame", nil, listChild)
        row:SetPoint("TOPLEFT", listChild, "TOPLEFT", 0, -((i - 1) * 44))
        row:SetPoint("TOPRIGHT", listChild, "TOPRIGHT", 0, -((i - 1) * 44))
        row:SetHeight(40)
        if T.ApplyBackdrop then T.ApplyBackdrop(row, T.colors.panel2, T.colors.cardBorder or T.colors.borderSoft) end
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetPoint("LEFT", row, "LEFT", 7, 0)
        row.icon:SetSize(28, 28)
        row.name = T.Font(row, "GameFontHighlightSmall", "", T.colors.text)
        row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 9, -1)
        row.id = T.Font(row, "GameFontDisableSmall", "", T.colors.muted)
        row.id:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 9, 1)
        row.remove = ActionButton(row, "Remove", 80)
        row.remove:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        row.remove:SetScript("OnClick", function()
            if row._spellID and Model.RemoveBlacklistSpell(unit, row._spellID, lane) then
                ApplyUnit(ctx, unit, "AURAS3_BLACKLIST_REMOVE", true)
            end
        end)
        AddTooltip(row.remove, "Remove from blacklist", "Stops blocking this aura.")
        rows[i] = row
        return row
    end
    refreshList = function()
        local entries = Model.BlacklistEntries(unit, lane)
        local blocked = {}
        for i = 1, #entries do blocked[tostring(entries[i].value)] = true end
        local setSpells = Model.BlacklistSpellValues(CurrentPreset())
        local missing = 0
        for i = 1, #setSpells do if not blocked[tostring(setSpells[i].value)] then missing = missing + 1 end end
        selectedSummary:SetText(tostring(#setSpells) .. " spells in this set - "
            .. (missing == 0 and "all already blocked" or (tostring(missing) .. " can still be added")))
        W.SetControlEnabled(addSet, missing > 0)
        local selectedSpell = CurrentSpell()
        W.SetControlEnabled(addSpell, selectedSpell ~= nil and not blocked[tostring(selectedSpell)])
        local query = tostring(searchValue or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        local visible = {}
        for i = 1, #entries do
            local entry = entries[i]
            local haystack = (tostring(entry.text or "") .. " "
                .. tostring(entry.spellID or entry.value or "")):lower()
            if query == "" or haystack:find(query, 1, true) then visible[#visible + 1] = entry end
        end
        prepared:SetText((#entries == 1 and "Blocked spells (1)" or ("Blocked spells (" .. tostring(#entries) .. ")"))
            .. (query ~= "" and (" - " .. tostring(#visible) .. " matches") or ""))
        empty:SetText(#entries == 0 and Tr(emptyText) or M.Format(Tr("No results for \"%s\"."), query))
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
                RegisterAuraControl(ctx, row.remove, "Remove " .. name, "button",
                    "unit-workspace.lane." .. AuraCatalogToken(lane) .. ".blacklist.entry." .. AuraCatalogToken(entry.value) .. ".remove", "action")
                row:Show()
            elseif row then row._spellID = nil; row:Hide() end
        end
    end
    M.TrackRefresh(ctx, refreshList)
end

local function BuildCompactGroupAuraFilters(ctx, b, scope, lane)
    local laneTitle = lane == "debuff" and "Debuff" or "Buff"
    local values = GroupFilterValues(lane)
    local optionRows = max(1, ceil(#values / 4))
    local sectionHeight = max(150, 104 + optionRows * 32) + (lane == "debuff" and 58 or 0)
    local section = b:Section(laneTitle .. " Filters", sectionHeight)
    local w = section._msuf2Width or b.width or 720
    local inner = w - 48
    local gap = 12
    local colW = floor((inner - gap * 3) / 4)
    W.Text(section, "Show auras", 24, -42, colW * 2 + gap, T.colors.muted)
    local hidePermanent = BindSwitch(ctx, section, "Hide permanent", 24 + 2 * (colW + gap), -42, colW * 2 + gap,
        function()
            return type(Model.ReadGroupBlacklistHidePermanent) == "function"
                and Model.ReadGroupBlacklistHidePermanent(scope, lane) == true
        end,
        function(value)
            if type(Model.WriteGroupBlacklistHidePermanent) == "function"
                and Model.WriteGroupBlacklistHidePermanent(scope, lane, value) then
                QueueGroupScope(scope, "visual")
            end
        end,
        AuraControlMeta(ctx, "group-workspace.lane." .. AuraCatalogToken(lane) .. ".filters.hide-permanent", nil, {
            assistantDisposition = "dynamic",
            assistantDispositionReason = "This control targets the selected Group scope and Aura lane.",
            assistantSettingKeys = GroupAssistantBlacklistSettingKeys(scope,
                ".auras." .. lane .. ".blacklist.hidePermanent"),
        }))
    AddTooltip(hidePermanent, "Hide permanent auras", "Always excludes auras without a duration.")
    local selectedFilterToken = CanonicalGroupFilterValue((GFReadGroup(scope, lane) or {}).filterToken or "ALL")
    for i = 1, #values do
        local item = values[i]
        local col = (i - 1) % 4
        local row = floor((i - 1) / 4)
        local control = BindSwitch(ctx, section, item.text or item.value, 24 + col * (colW + gap), -78 - row * 32, colW,
            function()
                local group = GFReadGroup(scope, lane)
                return CanonicalGroupFilterValue(group.filterToken or "ALL") == item.value
            end,
            function(enabled)
                local group = GFReadGroup(scope, lane)
                local current = CanonicalGroupFilterValue(group.filterToken or "ALL")
                local value = enabled and item.value or (current == item.value and "ALL" or current)
                GFWriteGroupValue(scope, lane, "filterToken", value, "visual")
                QueueAurasPageRefresh(ctx, "group-native-filter-choice")
            end,
            AuraControlMeta(ctx, "group-workspace.lane." .. AuraCatalogToken(lane) .. ".filters.native." .. AuraCatalogToken(item.value), nil,
                item.value == selectedFilterToken and {
                    assistantDisposition = "dynamic",
                    assistantDispositionReason = "The active native-filter choice represents Filter Token for the selected Group scope and Aura lane.",
                    assistantSettingKeys = GroupAssistantSettingKeys(scope,
                        ".auras." .. lane .. ".filterToken"),
                } or nil))
        AddTooltip(control, item.text or item.value, "Only one filter can be active.")
    end
    if lane == "debuff" then
        ConfigureMaxDurationSlider(BindSlider(ctx, section, "Maximum duration", 24, -78 - optionRows * 32, 0, 180, 1, inner,
            function()
                return type(Model.ReadGroupBlacklistMaxDuration) == "function"
                    and Model.ReadGroupBlacklistMaxDuration(scope, lane) or 0
            end,
            function(value)
                if type(Model.WriteGroupBlacklistMaxDuration) == "function"
                    and Model.WriteGroupBlacklistMaxDuration(scope, lane, value) then
                    QueueGroupScope(scope, "visual")
                end
            end,
            AuraControlMeta(ctx, "group-workspace.lane.debuff.filters.max-duration", nil, {
                assistantDisposition = "compound",
                assistantDispositionReason = "The native candidate-filter duration limit has no Assistant setting contract yet.",
            })))
    end
end

local function BuildCompactGroupAuraBlacklist(ctx, b, scope, lane)
    local laneTitle = lane == "debuff" and "Debuff" or "Buff"
    local isDebuff = lane == "debuff"
    local section = b:Section(laneTitle .. " Blacklist", isDebuff and 502 or 528)
    local groupActionPath = "group-workspace.scope." .. AuraCatalogToken(scope)
        .. ".lane." .. AuraCatalogToken(lane) .. ".blacklist"
    local w = section._msuf2Width or b.width or 720
    local inner = w - 48
    if not isDebuff then
        local inputValue = ""
        local inputW = max(140, min(floor(inner * 0.62), inner - 130))
        local input = BindTextInput(ctx, section, "Enter buff Spell ID, link, or name", 24, -36, inputW,
            function() return inputValue end, function(value) inputValue = value or "" end,
            false, AuraControlMeta(ctx, "group-workspace.lane.buff.blacklist.manual-input", "ephemeral"))
        local add = ActionButton(section, "Add custom buff", 118, "primary")
        add:SetPoint("TOPLEFT", section, "TOPLEFT", 36 + inputW, -60)
        add:SetScript("OnClick", function()
            local value = input and input.GetText and input:GetText() or inputValue
            local changed = Model.AddGroupBlacklistSpell(scope, lane, value)
            if changed then
                QueueGroupScope(scope, "visual")
                Rebuild(ctx)
            end
            if input and input.SetText then input:SetText("") end
            inputValue = ""
            return changed and true or false
        end)
        RegisterAuraTextAction(ctx, add, input, "Add custom buff", groupActionPath .. ".add", {
            actionKey = "aura_group_blacklist_add_spell", actionFixedArgs = { scope = scope, lane = lane }, actionInputArg = "value",
        })
        AddTooltip(add, "Add custom buff", "Adds one exact buff to this group's blacklist.")
    end
    local curatedOffset = isDebuff and 0 or -82
    local presetW = max(130, min(floor(inner * 0.62), inner - 138))
    local spellW = max(160, min(floor(inner * 0.68), inner - 108))
    local function CurrentPreset()
        local defaultKey = lane == "debuff" and "SATED" or "RAID_BUFFS"
        local key = M.auraBlacklistPreset or defaultKey
        local values = Model.BlacklistPresetValues()
        for i = 1, #values do if values[i].value == key then return key end end
        return values[1] and values[1].value or defaultKey
    end
    local function CurrentSpell()
        local values, selected = Model.BlacklistSpellValues(CurrentPreset()), M.auraBlacklistSpell
        for i = 1, #values do if values[i].value == selected then return selected end end
        return values[1] and values[1].value or nil
    end
    local preset = W.Dropdown(section, "Preset", function() return Model.BlacklistPresetValues() end, presetW)
    W.MoveWidget(preset, section, 24, -36 + curatedOffset, presetW)
    M.BindDropdownWidget(ctx, preset, CurrentPreset, function(value)
        M.auraBlacklistPreset = value
        M.auraBlacklistSpell = nil
        QueueAurasPageRefresh(ctx, "group-aura-blacklist-preset")
    end, AuraControlMeta(ctx, "group-workspace.lane." .. AuraCatalogToken(lane) .. ".blacklist.preset-selection", "ephemeral"))
    local addSet = ActionButton(section, "Add entire set", 126, "primary")
    addSet:SetPoint("TOPLEFT", section, "TOPLEFT", 36 + presetW, -60 + curatedOffset)
    addSet:SetScript("OnClick", function()
        local count = Model.AddGroupBlacklistPresetGroup(scope, lane, CurrentPreset())
        if count > 0 then
            QueueGroupScope(scope, "visual")
            Rebuild(ctx)
        end
        return count > 0
    end)
    RegisterAuraControl(ctx, addSet, "Add entire set", "button", groupActionPath .. ".add-preset-set", "action", {
        actionKey = "aura_group_blacklist_add_preset", actionFixedArgs = { scope = scope, lane = lane }, actionInputArg = "preset",
    })
    AddTooltip(addSet, "Add entire set", "Blocks every aura in the selected curated MSUF set.")
    local selectedSummary = W.Text(section, "", 24, -92 + curatedOffset, inner, T.colors.muted)
    local spell = W.Dropdown(section, "Spell", function() return Model.BlacklistSpellValues(CurrentPreset()) end, spellW)
    W.MoveWidget(spell, section, 24, -120 + curatedOffset, spellW)
    M.BindDropdownWidget(ctx, spell,
        CurrentSpell,
        function(value) M.auraBlacklistSpell = value end,
        AuraControlMeta(ctx, "group-workspace.lane." .. AuraCatalogToken(lane) .. ".blacklist.spell-selection", "ephemeral"))
    local addSpell = ActionButton(section, "Add spell", 96)
    addSpell:SetPoint("TOPLEFT", section, "TOPLEFT", 36 + spellW, -144 + curatedOffset)
    addSpell:SetScript("OnClick", function()
        local changed = Model.AddGroupBlacklistSpell(scope, lane, CurrentSpell())
        if changed then
            QueueGroupScope(scope, "visual")
            Rebuild(ctx)
        end
        return changed and true or false
    end)
    RegisterAuraControl(ctx, addSpell, "Add spell", "button", groupActionPath .. ".add-preset-spell", "action", {
        actionKey = "aura_group_blacklist_add_spell", actionFixedArgs = { scope = scope, lane = lane }, actionInputArg = "value",
    })
    AddTooltip(addSpell, "Add spell", "Blocks only the selected aura from the curated set.")
    local prepared = W.Text(section, "", 24, -186 + curatedOffset, inner, T.colors.accent)
    local searchValue = ""
    local refreshList
    local searchInput = BindTextInput(ctx, section, "Search", 24, -210 + curatedOffset, inner,
        function() return searchValue end,
        function(value)
            searchValue = tostring(value or "")
            if refreshList then refreshList() end
        end,
        true, AuraControlMeta(ctx, groupActionPath .. ".search", "ephemeral"))
    if searchInput and searchInput.HookScript then
        searchInput:HookScript("OnTextChanged", function(self)
            searchValue = self.GetText and tostring(self:GetText() or "") or ""
            if refreshList then refreshList() end
        end)
    end
    local emptyText = isDebuff and "No blocked spells. Add one from the presets above."
        or "No blocked spells. Add one above or use a preset."
    local empty = W.Text(section, emptyText, 24, -284 + curatedOffset, inner, T.colors.muted)
    local listScroll = CreateFrame("ScrollFrame", nil, section, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", section, "TOPLEFT", 24, -260 + curatedOffset)
    listScroll:SetSize(inner - 20, 150)
    if listScroll.EnableMouseWheel then listScroll:EnableMouseWheel(true) end
    local listChild = CreateFrame("Frame", nil, listScroll)
    listChild:SetSize(inner - 44, 150)
    listScroll:SetScrollChild(listChild)
    if listScroll.SetPropagateMouseWheel then listScroll:SetPropagateMouseWheel(false) end
    listScroll:SetScript("OnMouseWheel", function(self, delta) HandleNestedScrollWheel(self, delta, 44) end)
    local rows = {}
    local function EnsureRow(i)
        local row = rows[i]
        if row then return row end
        row = CreateFrame("Frame", nil, listChild)
        row:SetPoint("TOPLEFT", listChild, "TOPLEFT", 0, -((i - 1) * 44))
        row:SetPoint("TOPRIGHT", listChild, "TOPRIGHT", 0, -((i - 1) * 44))
        row:SetHeight(40)
        if T.ApplyBackdrop then T.ApplyBackdrop(row, T.colors.panel2, T.colors.cardBorder or T.colors.borderSoft) end
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetPoint("LEFT", row, "LEFT", 7, 0)
        row.icon:SetSize(28, 28)
        row.name = T.Font(row, "GameFontHighlightSmall", "", T.colors.text)
        row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 9, -1)
        row.id = T.Font(row, "GameFontDisableSmall", "", T.colors.muted)
        row.id:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 9, 1)
        row.remove = ActionButton(row, "Remove", 80)
        row.remove:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        row.remove:SetScript("OnClick", function()
            if row._spellID and Model.RemoveGroupBlacklistSpell(scope, lane, row._spellID) then
                QueueGroupScope(scope, "visual")
                Rebuild(ctx)
            end
        end)
        AddTooltip(row.remove, "Remove from blacklist", "Stops blocking this aura.")
        rows[i] = row
        return row
    end
    refreshList = function()
        local entries = type(Model.GroupBlacklistEntries) == "function" and Model.GroupBlacklistEntries(scope, lane) or {}
        local blocked = {}
        for i = 1, #entries do blocked[tostring(entries[i].value)] = true end
        local setSpells = Model.BlacklistSpellValues(CurrentPreset())
        local missing = 0
        for i = 1, #setSpells do if not blocked[tostring(setSpells[i].value)] then missing = missing + 1 end end
        selectedSummary:SetText(tostring(#setSpells) .. " spells in this set - "
            .. (missing == 0 and "all already blocked" or (tostring(missing) .. " can still be added")))
        W.SetControlEnabled(addSet, missing > 0)
        local selectedSpell = CurrentSpell()
        W.SetControlEnabled(addSpell, selectedSpell ~= nil and not blocked[tostring(selectedSpell)])
        local query = tostring(searchValue or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        local visible = {}
        for i = 1, #entries do
            local entry = entries[i]
            local haystack = (tostring(entry.text or "") .. " "
                .. tostring(entry.spellID or entry.value or "")):lower()
            if query == "" or haystack:find(query, 1, true) then visible[#visible + 1] = entry end
        end
        prepared:SetText((#entries == 1 and "Blocked spells (1)" or ("Blocked spells (" .. tostring(#entries) .. ")"))
            .. (query ~= "" and (" - " .. tostring(#visible) .. " matches") or ""))
        empty:SetText(#entries == 0 and Tr(emptyText) or M.Format(Tr("No results for \"%s\"."), query))
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
                RegisterAuraControl(ctx, row.remove, "Remove " .. name, "button",
                    groupActionPath .. ".entry." .. AuraCatalogToken(entry.value) .. ".remove", "action")
                row:Show()
            elseif row then row._spellID = nil; row:Hide() end
        end
    end
    M.TrackRefresh(ctx, refreshList)
    if lane == "debuff" then
        W.Text(section,
            "Friendly debuffs: exact blocking is limited to Blizzard NeverSecret auras such as Sated/Exhaustion.",
            24, -458, inner, T.colors.muted)
    end
end

function M.BuildAuras3GroupLaneWorkspace(ctx, b, scope, lane, opts)
    lane = lane == "debuff" and "debuff" or "buff"
    SetCurrentLane("auraStyleGFLane", lane)
    SetCurrentLane("auraFilterLane", lane)
    if opts and opts.compact == true then
        if opts.tool == "blacklist" then
            BuildCompactGroupAuraBlacklist(ctx, b, scope, lane)
        else
            BuildCompactGroupAuraFilters(ctx, b, scope, lane)
        end
        return
    end
    BuildGroupFilters(ctx, b, scope, lane, opts)
end

local function CreateNestedAuraBuilder(ctx, parentBuilder, body)
    local entry = body and body._msuf2CollapsibleEntry
    if not (entry and W.PageBuilder) then return parentBuilder end
    local bodyWidth = body._msuf2Width or parentBuilder.width or 720
    local nestedCtx = setmetatable({
        wrapper = body,
        width = max(320, bodyWidth - 24),
        key = ctx and ctx.key,
        entry = ctx and ctx.entry,
        _msuf2ContentX = 12,
        _msuf2TopInset = 0,
    }, { __index = ctx })
    function nestedCtx:SetContentHeight(height)
        height = max(80, ceil(tonumber(height) or 80))
        if entry.contentHeight == height then return end
        entry.contentHeight = height
        body:SetHeight(height)
        if parentBuilder.RequestRelayoutCollapsibles then parentBuilder:RequestRelayoutCollapsibles() end
    end
    local nestedBuilder = W.PageBuilder(nestedCtx)
    entry._msuf2SettleContentLayout = function()
        if nestedBuilder.RelayoutCollapsibles then nestedBuilder:RelayoutCollapsibles() end
        nestedCtx:SetContentHeight(abs(nestedBuilder.y) + 42)
    end
    return nestedBuilder
end

function M.BuildAuras3UnitSection(ctx, builder, unit)
    if not Model.UnitSupported(unit) then return end
    M.unitAuraTabSelection = M.unitAuraTabSelection or {}
    local workspaceTabs = unit == "player" and M._unitAuraWorkspaceTabsPlayer or UNIT_AURA_WORKSPACE_TABS
    local function CurrentTab()
        local tab = M.unitAuraTabSelection[unit] or "buff"
        if tab ~= "buff" and tab ~= "debuff" and tab ~= "custom1" and tab ~= "custom2" and tab ~= "custom3" and tab ~= "custom4" then tab = "buff" end
        return tab
    end
    local currentTab = CurrentTab()
    local normalLane = currentTab == "buff" or currentTab == "debuff"
    local currentTool = CurrentUnitAuraTool(unit, currentTab)
    local outer = builder:CollapsibleSection("auras", "Auras", 120, false)
    local auraBuilder = CreateNestedAuraBuilder(ctx, builder, outer)
    local sectionW = auraBuilder.width or 720
    local tools = normalLane and UNIT_AURA_NORMAL_TOOLS
        or (currentTab == "custom4"
            and (unit == "player" and M._unitAuraPlayerDefensiveTools or UNIT_AURA_TARGET_DOT_TOOLS)
            or UNIT_AURA_CUSTOM_TOOLS)
    local containerCenterY = -28
    local containerMetrics = W.MeasureScopeOverrideBar and W.MeasureScopeOverrideBar(workspaceTabs, {
        width = sectionW,
        labelWidth = 72,
        centerY = containerCenterY,
    })
    local toolCenterY = min(-62, ((containerMetrics and containerMetrics.bottomY) or -40) - 22)
    local toolMetrics = W.MeasureScopeOverrideBar and W.MeasureScopeOverrideBar(tools, {
        width = sectionW,
        labelWidth = 72,
        centerY = toolCenterY,
    })
    local footerY = ((toolMetrics and toolMetrics.bottomY) or (toolCenterY - 12)) - 2
    local top = auraBuilder:Section("", max(104, abs(footerY) + 28))
    if top.title then top.title:Hide() end
    if W.RegisterGuidedRegion then
        W.RegisterGuidedRegion(ctx, top, "Aura container and tools", "unit_aura_tools")
    end
    local containerBar = RegisterAuraChoiceBar(ctx, W.ScopeOverrideBar(ctx, top, {
        values = workspaceTabs,
        width = sectionW,
        label = "Container:",
        labelWidth = 72,
        centerY = containerCenterY,
        getValue = CurrentTab,
        setValue = function(value)
            M.unitAuraTabSelection[unit] = value
            Rebuild(ctx)
        end,
    }), workspaceTabs, "unit-workspace.container-selector")
    local toolBar = RegisterAuraChoiceBar(ctx, W.ScopeOverrideBar(ctx, top, {
        values = tools,
        width = sectionW,
        label = "Edit:",
        labelWidth = 72,
        centerY = toolCenterY,
        getValue = function() return CurrentUnitAuraTool(unit, currentTab) end,
        setValue = function(value) SetUnitAuraTool(unit, currentTab, value); Rebuild(ctx) end,
    }), tools, "unit-workspace.tool-selector")
    local openStyle = ActionButton(top, "More Aura Options", 150, "normal")
    openStyle:SetPoint("TOPRIGHT", top, "TOPRIGHT", -16, footerY)
    openStyle:SetScript("OnClick", function()
        SetCurrentScope(unit)
        M.SetMenuStateValue("auraStyleContainer", currentTab)
        if normalLane then SetCurrentLane("auraStyleGFLane", currentTab) end
        SelectPage("auras3_styling", unit)
    end)
    RegisterAuraControl(ctx, openStyle, "More Aura Options", "button", "unit-workspace.open-aura-style", "navigation", "auras3_styling")
    AddTooltip(openStyle, "More Aura Options",
        "Opens the complete Aura Style page for icon appearance, cooldown and stack text, duration bars, colors, and Full-Frame effects.")
    local workspaceHint = W.Text(top, "All icon and full-frame styling: Appearance > Auras.", 16, footerY - 8, sectionW - 198, T.colors.muted)
    M.TrackRefresh(ctx, function()
        workspaceHint:SetText(normalLane and not AnyUnitFrameAuraEnabled()
            and UNIT_AURA_DISPEL_WARNING
            or "All icon and full-frame styling: Appearance > Auras.")
    end)

    if normalLane then
        SetCurrentLane("auraStyleGFLane", currentTab)
        SetCurrentLane("auraFilterLane", currentTab)
        if currentTool == "filters" then
            BuildCompactUnitAuraFilters(ctx, auraBuilder, unit, currentTab)
        elseif currentTool == "blacklist" then
            BuildCompactUnitAuraBlacklist(ctx, auraBuilder, unit, currentTab)
        else
            BuildCompactUnitAuraLayout(ctx, auraBuilder, unit, currentTab)
        end
    elseif type(M.BuildAuras3CompactCustomWorkspace) == "function" then
        M.BuildAuras3CompactCustomWorkspace(ctx, auraBuilder, unit, tonumber(currentTab:match("(%d)$")) or 1, currentTool)
    end
end

local CUSTOM_AURA_TYPES = VTP "BUFF=Buff|DEBUFF=Debuff"
--- Compact, task-focused Custom Aura editor used inside UnitFrame > Auras.
--- Only one tool is rendered at a time; all values still write to the same
--- native Custom Container record consumed by runtime and previews.
function M.BuildAuras3CompactCustomWorkspace(ctx, b, unit, index, tool)
    index = max(1, min(type(Model.CustomContainerMax) == "function" and Model.CustomContainerMax() or 3, tonumber(index) or 1))
    -- The selected Custom Aura index is part of an action's executable
    -- identity.  Reusing one path for Custom 1/2/3 made the generated schema
    -- collapse three different fixed argument contracts into one action.
    local customActionPath = "custom-container.custom" .. tostring(index)
    local isPlayerDefensives = unit == "player" and index == 4
    local isTargetDots = unit ~= "player" and index == 4
    local containerLabel = isPlayerDefensives and "Defensive Buffs"
        or (isTargetDots and "Dots on target" or ("Custom " .. tostring(index)))
    local item = Model.CustomContainer(unit, index, true)
    if not item then return end
    item.filters = type(item.filters) == "table" and item.filters or {}
    item.placed = type(item.placed) == "table" and item.placed or {}
    item.frame = type(item.frame) == "table" and item.frame or { type = "none", color = { 0.69, 0.50, 0.88, 0.8 }, priority = 5, thickness = 2, layer = 0, strata = "AUTO" }
    if type(item.frame.color) ~= "table" then item.frame.color = { 0.69, 0.50, 0.88, 0.8 } end
    local function Apply(reason, rebuild)
        ApplyUnit(ctx, unit, reason or "AURAS3_CUSTOM_CONTAINER", rebuild == true)
        if type(ctx._auraAppearancePreviewRefresh) == "function" then ctx._auraAppearancePreviewRefresh() end
    end
    local function Grid(w, count, gap)
        gap = gap or 10
        return floor(((w - 48) - gap * (count - 1)) / count), gap
    end

    if tool == "defensives" and isPlayerDefensives then
        local section = b:Section("Defensive Buffs", 560)
        local w = section._msuf2Width or b.width or 720
        local inner = w - 48
        local predefined = type(Model.PlayerDefensiveClassEntries) == "function"
            and Model.PlayerDefensiveClassEntries(true) or {}
        local predefinedStatus = W.Text(section, "", 24, -34, inner, T.colors.accent)
        local searchValue = ""
        local RefreshPredefined
        local refreshCustom
        local searchInput = BindTextInput(ctx, section, "Search", 24, -58, inner,
            function() return searchValue end,
            function(value)
                searchValue = tostring(value or "")
                if RefreshPredefined then RefreshPredefined() end
                if refreshCustom then refreshCustom() end
            end,
            true, AuraControlMeta(ctx, "custom-container.player-defensives.search", "ephemeral"))
        if searchInput and searchInput.HookScript then
            searchInput:HookScript("OnTextChanged", function(self)
                searchValue = self.GetText and tostring(self:GetText() or "") or ""
                if RefreshPredefined then RefreshPredefined() end
                if refreshCustom then refreshCustom() end
            end)
        end
        local predefinedScroll = CreateFrame("ScrollFrame", nil, section, "UIPanelScrollFrameTemplate")
        predefinedScroll:SetPoint("TOPLEFT", section, "TOPLEFT", 24, -108)
        predefinedScroll:SetSize(inner - 20, 184)
        if predefinedScroll.EnableMouseWheel then predefinedScroll:EnableMouseWheel(true) end
        local predefinedChild = CreateFrame("Frame", nil, predefinedScroll)
        predefinedChild:SetSize(inner - 44, max(184, #predefined * 30))
        predefinedScroll:SetScrollChild(predefinedChild)
        if predefinedScroll.SetPropagateMouseWheel then predefinedScroll:SetPropagateMouseWheel(false) end
        predefinedScroll:SetScript("OnMouseWheel", function(self, delta) HandleNestedScrollWheel(self, delta, 30) end)
        local predefinedSwitches = {}
        local predefinedIcons = {}
        RefreshPredefined = function()
            local enabledCount = 0
            local visibleCount = 0
            local query = tostring(searchValue or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
            for i = 1, #predefined do
                local entry = predefined[i]
                local enabled = Model.PlayerDefensiveSpellEnabled(unit, entry.spellID)
                if enabled then enabledCount = enabledCount + 1 end
                local switch = predefinedSwitches[i]
                if switch then switch:SetChecked(enabled) end
                local icon = predefinedIcons[i]
                local haystack = (tostring(entry.text or "") .. " " .. tostring(entry.spellID or "")):lower()
                local shown = query == "" or haystack:find(query, 1, true) ~= nil
                if shown then
                    local y = -(visibleCount * 30)
                    visibleCount = visibleCount + 1
                    if icon then
                        icon:ClearAllPoints()
                        icon:SetPoint("TOPLEFT", predefinedChild, "TOPLEFT", 0, y)
                    end
                    if switch then
                        switch:ClearAllPoints()
                        switch:SetPoint("TOPLEFT", predefinedChild, "TOPLEFT", 30, y - 1)
                    end
                end
                if icon then icon:SetShown(shown) end
                if switch then switch:SetShown(shown) end
            end
            predefinedStatus:SetText(tostring(enabledCount) .. " / " .. tostring(#predefined)
                .. " predefined enabled"
                .. (query ~= "" and (" - " .. tostring(visibleCount) .. " matches") or ""))
            predefinedChild:SetHeight(max(184, visibleCount * 30))
        end
        for i = 1, #predefined do
            local entry = predefined[i]
            local spellID = entry.spellID
            local icon = predefinedChild:CreateTexture(nil, "ARTWORK")
            icon:SetPoint("TOPLEFT", predefinedChild, "TOPLEFT", 0, -((i - 1) * 30))
            icon:SetSize(22, 22)
            icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            predefinedIcons[i] = icon
            local switch = W.SwitchAt(predefinedChild, entry.text or tostring(spellID),
                30, -((i - 1) * 30) - 1, inner - 104)
            switch:SetScript("OnClick", function(self)
                local changed = Model.SetPlayerDefensiveSpellEnabled(unit, spellID, self:GetChecked())
                if changed then Apply("AURAS3_PLAYER_DEFENSIVE_PREDEFINED_TOGGLE", true) end
                RefreshPredefined()
            end)
            AddTooltip(switch, entry.text or tostring(spellID),
                "Track this predefined defensive buff. The setting applies to both the defensive bar and the optional portrait icon.")
            predefinedSwitches[i] = switch
        end
        M.TrackRefresh(ctx, RefreshPredefined)
        local customInputValue = ""
        local customInput = BindTextInput(ctx, section, "Custom Buff Spell ID", 24, -322, max(140, inner - 132),
            function() return customInputValue end,
            function(value) customInputValue = value or "" end,
            false, AuraControlMeta(ctx, "custom-container.player-defensives.custom-id", "ephemeral"))
        local addCustom = ActionButton(section, "Add Custom ID", 108)
        addCustom:SetPoint("TOPRIGHT", section, "TOPRIGHT", -24, -344)
        addCustom:SetScript("OnClick", function()
            local value = customInput and customInput.GetText and customInput:GetText() or customInputValue
            local changed = Model.AddCustomContainerSpell(unit, index, value, true)
            if changed then
                if customInput and customInput.SetText then customInput:SetText("") end
                customInputValue = ""
                Apply("AURAS3_PLAYER_DEFENSIVE_CUSTOM_ADD", true)
                Rebuild(ctx)
            end
            return changed and true or false
        end)
        RegisterAuraTextAction(ctx, addCustom, customInput, "Add Custom ID",
            customActionPath .. ".defensives.custom-id.add", {
                actionKey = "aura_custom_whitelist_add_spell",
                actionFixedArgs = { scope = unit, index = index },
                actionInputArg = "value",
            })
        AddTooltip(customInput, "Custom Buff Spell ID",
            "Adds an exact helpful player aura ID in addition to the complete predefined list for your current class.")
        local status = W.Text(section, "", 24, -392, inner, T.colors.accent)
        local empty = W.Text(section, "No custom buffs added.", 24, -442, inner, T.colors.muted)
        local listScroll = CreateFrame("ScrollFrame", nil, section, "UIPanelScrollFrameTemplate")
        listScroll:SetPoint("TOPLEFT", section, "TOPLEFT", 24, -418)
        listScroll:SetSize(inner - 20, 118)
        if listScroll.EnableMouseWheel then listScroll:EnableMouseWheel(true) end
        local listChild = CreateFrame("Frame", nil, listScroll)
        listChild:SetSize(inner - 44, 104)
        listScroll:SetScrollChild(listChild)
        if listScroll.SetPropagateMouseWheel then listScroll:SetPropagateMouseWheel(false) end
        listScroll:SetScript("OnMouseWheel", function(self, delta) HandleNestedScrollWheel(self, delta, 32) end)
        local rows = {}
        local function EnsureRow(i)
            local row = rows[i]
            if row then return row end
            row = CreateFrame("Button", nil, listChild)
            row:SetPoint("TOPLEFT", listChild, "TOPLEFT", 0, -((i - 1) * 24))
            row:SetPoint("TOPRIGHT", listChild, "TOPRIGHT", 0, -((i - 1) * 24))
            row:SetHeight(20)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetPoint("LEFT", row, "LEFT", 3, 0)
            row.icon:SetSize(17, 17)
            row.text = T.Font(row, "GameFontHighlightSmall", "", T.colors.text)
            row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
            row:SetScript("OnClick", function(self)
                if self._spellID and Model.RemoveCustomContainerSpell(unit, index, self._spellID) then
                    Apply("AURAS3_PLAYER_DEFENSIVE_CUSTOM_REMOVE", true)
                    Rebuild(ctx)
                end
            end)
            rows[i] = row
            return row
        end
        refreshCustom = function()
            local entries = Model.CustomContainerSpellEntries(unit, index)
            local enabledPredefined = type(Model.PlayerDefensivePreviewEntries) == "function"
                and #Model.PlayerDefensivePreviewEntries() or 0
            local query = tostring(searchValue or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
            local visible = {}
            for i = 1, #entries do
                local entry = entries[i]
                local haystack = (tostring(entry.text or "") .. " " .. tostring(entry.spellID or "")):lower()
                if query == "" or haystack:find(query, 1, true) then visible[#visible + 1] = entry end
            end
            status:SetText(tostring(enabledPredefined) .. " predefined enabled · "
                .. tostring(#entries) .. " custom · click a custom entry to remove"
                .. (query ~= "" and (" - " .. tostring(#visible) .. " matches") or ""))
            empty:SetText(#entries == 0 and Tr("No custom buffs added.")
                or M.Format(Tr("No results for \"%s\"."), query))
            empty:SetShown(#visible == 0)
            listScroll:SetShown(#visible > 0)
            listChild:SetHeight(max(118, #visible * 24))
            for i = 1, max(#rows, #visible) do
                local row, entry = rows[i], visible[i]
                if entry then
                    row = EnsureRow(i)
                    row._spellID = entry.spellID
                    row.icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                    row.text:SetText(entry.text or tostring(entry.spellID))
                    RegisterAuraControl(ctx, row, entry.text or tostring(entry.spellID), "button",
                        customActionPath .. ".defensives.entry." .. AuraCatalogToken(entry.spellID) .. ".remove", "action")
                    row:Show()
                elseif row then row._spellID = nil; row:Hide() end
            end
        end
        M.TrackRefresh(ctx, refreshCustom)
        return
    end

    if tool == "dots" and isTargetDots then
        local section = b:Section("Dots on target", 370)
        local w = section._msuf2Width or b.width or 720
        local inner = w - 48
        local values = type(Model.TargetDotValues) == "function" and Model.TargetDotValues() or {}
        local selected
        for i = 1, #values do
            if values[i].value then selected = values[i].value; break end
        end
        local dropdown = BindDropdown(ctx, section, "DoT", 24, -34, values, max(140, inner - 132),
            function() return selected end,
            function(value) selected = value end,
            AuraControlMeta(ctx, "custom-container.target-dots.selection", "ephemeral"))
        local add = ActionButton(section, "Track DoT", 108)
        add:SetPoint("TOPRIGHT", section, "TOPRIGHT", -24, -56)
        add:SetScript("OnClick", function()
            local changed = selected and Model.AddCustomContainerSpell(unit, index, selected)
            if changed then Apply("AURAS3_TARGET_DOT_ADD", true); Rebuild(ctx) end
            return changed and true or false
        end)
        RegisterAuraTextAction(ctx, add, {
            SetText = function(_, value) selected = value end,
        }, "Track DoT", customActionPath .. ".dots.add", {
            actionKey = "aura_custom_whitelist_add_spell",
            actionFixedArgs = { scope = unit, index = index },
            actionInputArg = "value",
        })
        AddTooltip(dropdown, "Target DoT", "Curated Retail 12.0+ and 12.1 DoT auras. Tracking is always restricted to your current target and your own aura source.")
        local customInputValue = ""
        local customInput = BindTextInput(ctx, section, "Custom Spell ID", 24, -94, max(140, inner - 132),
            function() return customInputValue end,
            function(value) customInputValue = value or "" end,
            false, AuraControlMeta(ctx, "custom-container.target-dots.custom-id", "ephemeral"))
        local addCustom = ActionButton(section, "Add Custom ID", 108)
        addCustom:SetPoint("TOPRIGHT", section, "TOPRIGHT", -24, -116)
        addCustom:SetScript("OnClick", function()
            local value = customInput and customInput.GetText and customInput:GetText() or customInputValue
            local changed = Model.AddCustomContainerSpell(unit, index, value, true)
            if changed then
                if customInput and customInput.SetText then customInput:SetText("") end
                customInputValue = ""
                Apply("AURAS3_TARGET_DOT_CUSTOM_ADD", true)
                Rebuild(ctx)
            end
            return changed and true or false
        end)
        RegisterAuraTextAction(ctx, addCustom, customInput, "Add Custom ID", customActionPath .. ".dots.custom-id.add", {
            actionKey = "aura_custom_whitelist_add_spell",
            actionFixedArgs = { scope = unit, index = index },
            actionInputArg = "value",
        })
        AddTooltip(customInput, "Custom Spell ID",
            "Adds an exact harmful aura ID that is missing from the curated list. The aura is still restricted to your current target and your own aura source.")
        local status = W.Text(section, "", 24, -162, inner, T.colors.accent)
        local searchValue = ""
        local refreshList
        local searchInput = BindTextInput(ctx, section, "Search", 24, -186, inner,
            function() return searchValue end,
            function(value)
                searchValue = tostring(value or "")
                if refreshList then refreshList() end
            end,
            true, AuraControlMeta(ctx, "custom-container.target-dots.search", "ephemeral"))
        if searchInput and searchInput.HookScript then
            searchInput:HookScript("OnTextChanged", function(self)
                searchValue = self.GetText and tostring(self:GetText() or "") or ""
                if refreshList then refreshList() end
            end)
        end
        local empty = W.Text(section, "No DoT selected. Choose one above or add a custom Spell ID.", 24, -260, inner, T.colors.muted)
        local listScroll = CreateFrame("ScrollFrame", nil, section, "UIPanelScrollFrameTemplate")
        listScroll:SetPoint("TOPLEFT", section, "TOPLEFT", 24, -236)
        listScroll:SetSize(inner - 20, 104)
        if listScroll.EnableMouseWheel then listScroll:EnableMouseWheel(true) end
        local listChild = CreateFrame("Frame", nil, listScroll)
        listChild:SetSize(inner - 44, 104)
        listScroll:SetScrollChild(listChild)
        if listScroll.SetPropagateMouseWheel then listScroll:SetPropagateMouseWheel(false) end
        listScroll:SetScript("OnMouseWheel", function(self, delta) HandleNestedScrollWheel(self, delta, 32) end)
        local rows = {}
        local function EnsureRow(i)
            local row = rows[i]
            if row then return row end
            row = CreateFrame("Button", nil, listChild)
            row:SetPoint("TOPLEFT", listChild, "TOPLEFT", 0, -((i - 1) * 24))
            row:SetPoint("TOPRIGHT", listChild, "TOPRIGHT", 0, -((i - 1) * 24))
            row:SetHeight(20)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetPoint("LEFT", row, "LEFT", 3, 0)
            row.icon:SetSize(17, 17)
            row.text = T.Font(row, "GameFontHighlightSmall", "", T.colors.text)
            row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
            row:SetScript("OnClick", function(self)
                if self._spellID and Model.RemoveCustomContainerSpell(unit, index, self._spellID) then
                    Apply("AURAS3_TARGET_DOT_REMOVE", true)
                    Rebuild(ctx)
                end
            end)
            rows[i] = row
            return row
        end
        refreshList = function()
            local entries = Model.CustomContainerSpellEntries(unit, index)
            local query = tostring(searchValue or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
            local visible = {}
            for i = 1, #entries do
                local entry = entries[i]
                local haystack = (tostring(entry.text or "") .. " " .. tostring(entry.spellID or "")):lower()
                if query == "" or haystack:find(query, 1, true) then visible[#visible + 1] = entry end
            end
            status:SetText((#entries == 1 and "1 tracked DoT" or tostring(#entries) .. " tracked DoTs")
                .. " · click an entry to remove"
                .. (query ~= "" and (" - " .. tostring(#visible) .. " matches") or ""))
            empty:SetText(#entries == 0 and Tr("No DoT selected. Choose one above or add a custom Spell ID.")
                or M.Format(Tr("No results for \"%s\"."), query))
            empty:SetShown(#visible == 0)
            listScroll:SetShown(#visible > 0)
            listChild:SetHeight(max(104, #visible * 24))
            for i = 1, max(#rows, #visible) do
                local row, entry = rows[i], visible[i]
                if entry then
                    row = EnsureRow(i)
                    row._spellID = entry.spellID
                    row.icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                    row.text:SetText(entry.text or tostring(entry.spellID))
                    RegisterAuraControl(ctx, row, entry.text or tostring(entry.spellID), "button",
                        customActionPath .. ".dots.entry." .. AuraCatalogToken(entry.spellID) .. ".remove", "action")
                    row:Show()
                elseif row then row._spellID = nil; row:Hide() end
            end
        end
        M.TrackRefresh(ctx, refreshList)
        return
    end

    if tool == "whitelist" then
        local section = b:Section(containerLabel .. " Whitelist", 430)
        local w = section._msuf2Width or b.width or 720
        local inner = w - 48
        local auraType = item.auraType == "DEBUFF" and "DEBUFF" or "BUFF"
        local auraNoun = auraType == "DEBUFF" and "debuff" or "buff"
        local auraPlural = auraNoun .. "s"
        W.Text(section, auraType, 24, -36, 58, T.colors.accent)
        W.Text(section, Tr(NATIVE_EXACT_AURA_FILTERS_TEXT), 88, -36, inner - 64, T.colors.muted)
        local inputValue = ""
        local inputW = max(140, min(floor(inner * 0.62), inner - 120))
        local input = BindTextInput(ctx, section, "Track a " .. auraNoun .. " - Spell ID, link, or name", 24, -76, inputW,
            function() return inputValue end, function(value) inputValue = value or "" end,
            false, AuraControlMeta(ctx, "custom-container.whitelist.input", "ephemeral"))
        local add = ActionButton(section, "Add " .. auraNoun, 108, "primary")
        add:SetPoint("TOPLEFT", section, "TOPLEFT", 36 + inputW, -100)
        add:SetScript("OnClick", function()
            local value = input and input.GetText and input:GetText() or inputValue
            local changed = Model.AddCustomContainerSpell(unit, index, value)
            if changed then
                if input and input.SetText then input:SetText("") end
                inputValue = ""
                Apply("AURAS3_CUSTOM_WHITELIST_ADD", true)
                Rebuild(ctx)
            end
            return changed and true or false
        end)
        RegisterAuraTextAction(ctx, add, input, "Add " .. auraNoun, customActionPath .. ".whitelist.add", {
            actionKey = "aura_custom_whitelist_add_spell", actionFixedArgs = { scope = unit, index = index }, actionInputArg = "value",
        })
        AddTooltip(input, "Exact aura tracking",
            "Enter a Spell ID, paste a spell link, or type a spell name. This whitelist tracks exact Spell IDs.")
        AddTooltip(add, "Add " .. auraNoun, "Adds this exact " .. auraNoun .. " to the custom container.")
        local status = W.Text(section, "", 24, -136, floor(inner * 0.52), T.colors.accent)
        local empty = W.Text(section, "No spells tracked. Add up to 40 exact SpellIDs.",
            24, -238, inner, T.colors.muted)
        local searchValue = ""
        local refreshList
        local searchInput = BindTextInput(ctx, section, "Search", 24, -164, inner,
            function() return searchValue end,
            function(value)
                searchValue = tostring(value or "")
                if refreshList then refreshList() end
            end,
            true, AuraControlMeta(ctx, "custom-container.whitelist.search", "ephemeral"))
        if searchInput and searchInput.HookScript then
            searchInput:HookScript("OnTextChanged", function(self)
                searchValue = self.GetText and tostring(self:GetText() or "") or ""
                if refreshList then refreshList() end
            end)
        end
        local listScroll = CreateFrame("ScrollFrame", nil, section, "UIPanelScrollFrameTemplate")
        listScroll:SetPoint("TOPLEFT", section, "TOPLEFT", 24, -214)
        listScroll:SetSize(inner - 20, 190)
        if listScroll.EnableMouseWheel then listScroll:EnableMouseWheel(true) end
        local listChild = CreateFrame("Frame", nil, listScroll)
        listChild:SetSize(inner - 44, 190)
        listScroll:SetScrollChild(listChild)
        if listScroll.SetPropagateMouseWheel then listScroll:SetPropagateMouseWheel(false) end
        listScroll:SetScript("OnMouseWheel", function(self, delta) HandleNestedScrollWheel(self, delta, 44) end)
        local rows = {}
        local function EnsureRow(i)
            local row = rows[i]
            if row then return row end
            row = CreateFrame("Frame", nil, listChild)
            row:SetPoint("TOPLEFT", listChild, "TOPLEFT", 0, -((i - 1) * 44))
            row:SetPoint("TOPRIGHT", listChild, "TOPRIGHT", 0, -((i - 1) * 44))
            row:SetHeight(40)
            if T.ApplyBackdrop then T.ApplyBackdrop(row, T.colors.panel2, T.colors.cardBorder or T.colors.borderSoft) end
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetPoint("LEFT", row, "LEFT", 7, 0)
            row.icon:SetSize(28, 28)
            row.name = T.Font(row, "GameFontHighlightSmall", "", T.colors.text)
            row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 9, -1)
            row.id = T.Font(row, "GameFontDisableSmall", "", T.colors.muted)
            row.id:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 9, 1)
            row.remove = ActionButton(row, "Remove", 80)
            row.remove:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            row.remove:SetScript("OnClick", function()
                if row._spellID and Model.RemoveCustomContainerSpell(unit, index, row._spellID) then
                    Apply("AURAS3_CUSTOM_WHITELIST_REMOVE", true)
                    Rebuild(ctx)
                end
            end)
            AddTooltip(row.remove, "Remove from whitelist",
                "Stops tracking this " .. auraNoun .. " in the custom container.")
            rows[i] = row
            return row
        end
        refreshList = function()
            local entries = Model.CustomContainerSpellEntries(unit, index)
            local query = tostring(searchValue or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
            local visible = {}
            for i = 1, #entries do
                local entry = entries[i]
                local haystack = (tostring(entry.text or "") .. " " .. tostring(entry.spellID or "")):lower()
                if query == "" or haystack:find(query, 1, true) then visible[#visible + 1] = entry end
            end
            status:SetText(tostring("Tracked ") .. auraPlural .. " (" .. tostring(#entries) .. " of 40)"
                .. (query ~= "" and (" - " .. tostring(#visible) .. " matches") or ""))
            empty:SetText(#entries == 0 and Tr("No spells tracked. Add up to 40 exact SpellIDs.")
                or M.Format(Tr("No results for \"%s\"."), query))
            empty:SetShown(#visible == 0)
            listScroll:SetShown(#visible > 0)
            listChild:SetHeight(max(190, #visible * 44))
            for i = 1, max(#rows, #visible) do
                local row, entry = rows[i], visible[i]
                if entry then
                    row = EnsureRow(i)
                    row._spellID = entry.spellID
                    row.icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                    local name = tostring(entry.text or entry.spellID or "Spell"):gsub("%s*%(#%d+%)$", "")
                    row.name:SetText(name)
                    row.id:SetText(tostring("Spell ID ") .. tostring(entry.spellID))
                    RegisterAuraControl(ctx, row.remove, "Remove " .. name, "button",
                        customActionPath .. ".whitelist.entry." .. AuraCatalogToken(entry.spellID) .. ".remove", "action")
                    row:Show()
                elseif row then row._spellID = nil; row:Hide() end
            end
        end
        M.TrackRefresh(ctx, refreshList)
        return
    end

    if tool == "filters" then
        local section = b:Section(containerLabel .. " Filters", item.auraType == "DEBUFF" and 224 or 182)
        local w = section._msuf2Width or b.width or 720
        local colW, gap = Grid(w, 4)
        local controls = {}
        local master = BindSwitch(ctx, section, "Enable filters", 24, -40, colW,
            function() return item.filters.enabled ~= false end,
            function(value) item.filters.enabled = value == true; Apply("AURAS3_CUSTOM_FILTER_ENABLE") end,
            AuraControlMeta(ctx, "custom-container.filters.enabled"))
        local hidePermanent = BindSwitch(ctx, section, "Hide permanent", 24 + colW + gap, -40, colW,
            function() return item.filters.hidePermanent == true end,
            function(value) item.filters.hidePermanent = value == true; Apply("AURAS3_CUSTOM_HIDE_PERMANENT", true) end,
            AuraControlMeta(ctx, "custom-container.filters.hide-permanent"))
        AddTooltip(hidePermanent, "Hide permanent auras", "Always excludes auras without a duration. It remains active when token filters are disabled.")
        local specs = item.auraType == "DEBUFF" and {
            { "Only mine", "onlyMine" }, { "Raid", "raid" }, { "Raid combat", "raidInCombat" }, { "Nameplate-only", "includeNameplateOnly" },
            { "Removable by group", "includeDispellable" }, { "Any removable type", "dispellableAny" },
            { "Important", "onlyImportant" }, { "Crowd control", "crowdControl" },
        } or {
            { "Only mine", "onlyMine" }, { "Important", "onlyImportant" }, { "Raid", "raid" }, { "Raid combat", "raidInCombat" }, { "Nameplate-only", "includeNameplateOnly" },
            { "Removable by group", "includeDispellable" }, { "Any removable type", "dispellableAny" },
            { "Cancelable", "cancelable", { "notCancelable" } }, { "Not cancelable", "notCancelable", { "cancelable" } },
            { "External defensive", "externalDefensive" }, { "Big defensive", "bigDefensive" },
        }
        for i = 1, #specs do
            local spec = specs[i]
            local col = (i - 1) % 4
            local row = floor((i - 1) / 4)
            local control = BindSwitch(ctx, section, spec[1], 24 + col * (colW + gap), -76 - row * 32, colW,
                function()
                    if spec[2] == "raid" and item.filters.exclusive == "raid" then return true end
                    return item.filters[spec[2]] == true
                end,
                function(value)
                    if spec[2] == "raid" then item.filters.exclusive = nil end
                    item.filters[spec[2]] = value == true
                    if value == true and spec[3] then for j = 1, #spec[3] do item.filters[spec[3][j]] = false end end
                    Apply("AURAS3_CUSTOM_FILTER")
                    if spec[3] then QueueAurasPageRefresh(ctx, "custom-filter-conflict") end
                end,
                AuraControlMeta(ctx, "custom-container.filters." .. AuraCatalogToken(spec[2])))
            controls[#controls + 1] = control
        end
        local maxDuration
        if item.auraType == "DEBUFF" then
            maxDuration = ConfigureMaxDurationSlider(BindSlider(ctx, section, "Maximum duration", 24, -140, 0, 180, 1, w - 48,
                function() return min(180, max(0, tonumber(item.filters.maxDuration) or 0)) end,
                function(value)
                    item.filters.maxDuration = Round(min(180, max(0, tonumber(value) or 0)))
                    Apply("AURAS3_CUSTOM_DEBUFF_MAX_DURATION", true)
                end,
                AuraControlMeta(ctx, "custom-container.filters.max-duration", nil, {
                    assistantDisposition = "compound",
                    assistantDispositionReason = "The native candidate-filter duration limit has no Assistant setting contract yet.",
                })))
        end
        M.TrackRefresh(ctx, function()
            W.SetControlEnabled(master, true)
            W.SetControlEnabled(hidePermanent, true)
            W.SetControlEnabled(maxDuration, true)
            W.SetControlsEnabled(controls, item.filters.enabled ~= false)
        end)
        return
    end

    if tool == "layout" then
        local section = b:Section(containerLabel .. " Layout", 190)
        M.AttachAuraFontsAndColors(section, containerLabel .. " Layout", unit)
        local w = section._msuf2Width or b.width or 720
        local col3, gap3 = Grid(w, 3)
        BindDropdown(ctx, section, "Anchor", 24, -34, Model.AuraAnchorValues(), col3,
            function() return item.placed.anchor or "TOPRIGHT" end,
            function(value) item.placed.anchor = value or "TOPRIGHT"; Apply("AURAS3_CUSTOM_ANCHOR") end,
            AuraControlMeta(ctx, "custom-container.layout.anchor"))
        BindDropdown(ctx, section, "Growth", 24 + col3 + gap3, -34, Model.LaneGrowthValues(), col3,
            function() return item.placed.growth or "LEFTDOWN" end,
            function(value) item.placed.growth = value or "LEFTDOWN"; Apply("AURAS3_CUSTOM_GROWTH") end,
            AuraControlMeta(ctx, "custom-container.layout.growth"))
        local col4, gap4 = Grid(w, 4)
        local values = {
            { "X", "x", -300, 300, 0 }, { "Y", "y", -300, 300, 0 }, { "Max", "max", 0, 40, 8 }, { "Size", "size", 8, 128, 24 },
            { "Per row", "perRow", 1, 20, 4 }, { "Gap", "spacing", 0, 24, 2 }, { "Layer (0-30)", "layer", 0, 30, 9 },
        }
        local perRowControl
        for i = 1, #values do
            local spec = values[i]
            local row = i <= 4 and 0 or 1
            local col = row == 0 and (i - 1) or (i - 5)
            local assistantContract
            if spec[2] == "layer" then
                local layerSettingKeys = {}
                for customIndex = 1, 4 do
                    layerSettingKeys[#layerSettingKeys + 1] =
                        "auras3." .. tostring(unit) .. ".custom" .. tostring(customIndex) .. ".layer"
                end
                assistantContract = {
                    assistantDisposition = "dynamic",
                    assistantDispositionReason = "Layer targets the selected unit Custom Aura container.",
                    assistantSettingKeys = layerSettingKeys,
                }
            end
            local control = BindSlider(ctx, section, spec[1], 24 + col * (col4 + gap4), row == 0 and -92 or -146, spec[3], spec[4], 1, col4,
                function() return tonumber(spec[2] == "layer" and item.layer or item.placed[spec[2]]) or spec[5] end,
                function(value)
                    if spec[2] == "layer" then item.layer = floor(tonumber(value) or spec[5]) else item.placed[spec[2]] = tonumber(value) or spec[5] end
                    Apply("AURAS3_CUSTOM_" .. spec[2]:upper())
                end,
                AuraControlMeta(ctx, "custom-container.layout." .. AuraCatalogToken(spec[2]), nil, assistantContract))
            if spec[2] == "perRow" then perRowControl = control end
        end
        M.TrackRefresh(ctx, function()
            local growth = tostring(item.placed.growth or "LEFTDOWN"):upper()
            W.SetControlEnabled(perRowControl, growth ~= "UP" and growth ~= "DOWN")
        end)
        W.Text(section, "Move the colored aura handle; Live and dummy previews are display-only.", 24 + 3 * (col4 + gap4), -154, col4, T.colors.muted)
        return
    end

    if tool == "appearance" then
        -- One accordion sub-section per topic, mirroring the Buff/Debuff lane
        -- style sections. Assistant semantic paths keep the historical
        -- "appearance" segment so the generated control schema stays stable.
        local function StyleGrid(section)
            local w = section._msuf2Width or b.width or 720
            local col4, gap = Grid(w, 4)
            local function X(col) return 24 + (col - 1) * (col4 + gap) end
            local function Number(label, col, y, minValue, maxValue, key, fallback)
                return BindSlider(ctx, section, label, X(col), y, minValue, maxValue, 1, col4,
                    function() return tonumber(item.placed[key]) or fallback end,
                    function(value) item.placed[key] = tonumber(value) or fallback; Apply("AURAS3_CUSTOM_APPEARANCE_" .. key:upper()) end,
                    AuraControlMeta(ctx, "custom-container.appearance." .. AuraCatalogToken(key)))
            end
            return col4, X, Number
        end
        local function GateControls(readEnabled, controls)
            M.TrackRefresh(ctx, function() W.SetControlsEnabled(controls, readEnabled()) end)
        end

        local harmfulContainer = isTargetDots or tostring(item.auraType or "BUFF"):upper() == "DEBUFF"
        local scaling = b:CollapsibleSection(CustomStyleSectionId(index, "scaling"), "Scaling", 112, true)
        local _, _, ScalingNumber = StyleGrid(scaling)
        ScalingNumber("Icon Zoom (%)", 1, -48, 100, 200, "iconZoom", 100)

        local basics = b:CollapsibleSection(CustomStyleSectionId(index, "basics"), "Basics", 130, true)
        local basicsCol, basicsX = StyleGrid(basics)
        BindSwitch(ctx, basics, "Tooltip", basicsX(1), -42, basicsCol, function() return item.placed.showTooltip ~= false end,
            function(value) item.placed.showTooltip = value == true; Apply("AURAS3_CUSTOM_TOOLTIP") end,
            AuraControlMeta(ctx, "custom-container.appearance.tooltip"))
        BindSlider(ctx, basics, "Opacity", basicsX(1), -76, 10, 100, 5, basicsCol,
            function() return floor(((tonumber(item.placed.alpha) or 1) * 100) + 0.5) end,
            function(value) item.placed.alpha = (tonumber(value) or 100) / 100; Apply("AURAS3_CUSTOM_ALPHA") end,
            AuraControlMeta(ctx, "custom-container.appearance.opacity"))
        if harmfulContainer then
            BindDropdown(ctx, basics, "Dispel-type Border", basicsX(2), -76, DEBUFF_TYPE_BORDER_MODE_VALUES, basicsCol,
                function() return item.placed.debuffTypeBorderMode or "OFF" end,
                function(value) item.placed.debuffTypeBorderMode = value or "OFF"; Apply("AURAS3_CUSTOM_DEBUFF_TYPE_BORDER") end,
                AuraControlMeta(ctx, "custom-container.appearance.dispel-type-border"))
        end

        local stack = b:CollapsibleSection(CustomStyleSectionId(index, "stack"), "Stack Count", 130, false)
        local stackCol, stackX, StackNumber = StyleGrid(stack)
        BindSwitch(ctx, stack, "Stack count", stackX(1), -42, stackCol, function() return item.placed.showStacks ~= false end,
            function(value) item.placed.showStacks = value == true; Apply("AURAS3_CUSTOM_STACKS") end,
            AuraControlMeta(ctx, "custom-container.appearance.stack-count"))
        GateControls(function() return item.placed.showStacks ~= false end, {
            StackNumber("Stack size", 1, -76, 6, 40, "stackSize", 14),
            BindDropdown(ctx, stack, "Stack anchor", stackX(2), -76, Model.AuraAnchorValues(), stackCol,
                function() return item.placed.stackAnchor or "BOTTOMRIGHT" end,
                function(value) item.placed.stackAnchor = value or "BOTTOMRIGHT"; Apply("AURAS3_CUSTOM_STACK_ANCHOR") end,
                AuraControlMeta(ctx, "custom-container.appearance.stack-anchor")),
            StackNumber("Stack X", 3, -76, -40, 40, "stackX", 0),
            StackNumber("Stack Y", 4, -76, -40, 40, "stackY", 0),
        })

        local cooldown = b:CollapsibleSection(CustomStyleSectionId(index, "cooldown"), "Cooldown Text", 184, true)
        if W.AttachContextColorShortcut then
            W.AttachContextColorShortcut(cooldown, {
                title = containerLabel .. " Cooldown Text Settings",
                historyLabel = "Custom aura cooldown text color",
                historySource = "menu:custom-auras-cooldown-text-color",
                scopeTag = "Shared",
                note = AURA_SHARED_COLOR_NOTE,
                textSettings = {
                    scope = "shared",
                    unit = unit,
                    kind = "aura",
                    colorReferences = AURA_COOLDOWN_COLOR_REFERENCES,
                    colorTitle = containerLabel .. " Cooldown Colors",
                    subtitle = "Custom aura text follows the shared Fonts settings.",
                    capabilities = {
                        opacity = false, baseline = false,
                        shadowAlpha = false, shadowDistance = false,
                    },
                },
            })
        end
        local cdCol, cdX, CdNumber = StyleGrid(cooldown)
        BindSwitch(ctx, cooldown, "Cooldown text", cdX(1), -42, cdCol, function() return item.placed.showCooldown ~= false end,
            function(value) item.placed.showCooldown = value == true; Apply("AURAS3_CUSTOM_COOLDOWN") end,
            AuraControlMeta(ctx, "custom-container.appearance.cooldown-text"))
        BindSwitch(ctx, cooldown, "Cooldown swipe", cdX(2), -42, cdCol, function() return item.placed.showCooldownSwipe ~= false end,
            function(value) item.placed.showCooldownSwipe = value == true; Apply("AURAS3_CUSTOM_SWIPE") end,
            AuraControlMeta(ctx, "custom-container.appearance.cooldown-swipe"))
        local customDecimal = CdNumber("Decimals below sec", 4, -76, 0, 30, "cooldownDecimalSeconds", 3)
        AddTooltip(customDecimal, "Cooldown text format",
            "Remaining time below this value uses one decimal place. Timers show unitless seconds below 1 minute and localized minutes above it. Set 0 for whole seconds only.")
        GateControls(function() return item.placed.showCooldown ~= false end, {
            CdNumber("Cooldown size", 1, -76, 6, 40, "cooldownSize", 14),
            BindDropdown(ctx, cooldown, "Cooldown anchor", cdX(3), -76, Model.AuraAnchorValues(), cdCol,
                function() return item.placed.cooldownAnchor or "CENTER" end,
                function(value) item.placed.cooldownAnchor = value or "CENTER"; Apply("AURAS3_CUSTOM_COOLDOWN_ANCHOR") end,
                AuraControlMeta(ctx, "custom-container.appearance.cooldown-anchor")),
            customDecimal,
            CdNumber("Cooldown X", 1, -130, -40, 40, "cooldownX", 0),
            CdNumber("Cooldown Y", 2, -130, -40, 40, "cooldownY", 0),
        })
        GateControls(function() return item.placed.showCooldownSwipe ~= false end, {
            BindDropdown(ctx, cooldown, "Swipe", cdX(2), -76, COOLDOWN_SWIPE_DIRECTION_VALUES, cdCol,
                function() return item.placed.cooldownSwipeReverse == true and "REVERSE" or "NORMAL" end,
                function(value) item.placed.cooldownSwipeReverse = value == "REVERSE"; Apply("AURAS3_CUSTOM_SWIPE_DIRECTION") end,
                AuraControlMeta(ctx, "custom-container.appearance.swipe-direction")),
        })

        local durationBar = b:CollapsibleSection(CustomStyleSectionId(index, "duration_bar"), "Duration Bar", 130, false)
        local barCol, barX, BarNumber = StyleGrid(durationBar)
        BindSwitch(ctx, durationBar, "Duration bar", barX(1), -42, barCol, function() return item.placed.showDurationBar == true end,
            function(value) item.placed.showDurationBar = value == true; Apply("AURAS3_CUSTOM_DURATION_BAR") end,
            AuraControlMeta(ctx, "custom-container.appearance.duration-bar"))
        GateControls(function() return item.placed.showDurationBar == true end, {
            BarNumber("Bar height", 1, -76, 1, 16, "durationBarHeight", 2),
            BindDropdown(ctx, durationBar, "Bar display", barX(2), -76, DURATION_BAR_DISPLAY_VALUES, barCol,
                function() return item.placed.durationBarDisplay or "BAR_ONLY" end,
                function(value) item.placed.durationBarDisplay = value or "BAR_ONLY"; Apply("AURAS3_CUSTOM_DURATION_DISPLAY") end,
                AuraControlMeta(ctx, "custom-container.appearance.duration-display")),
            BindDropdown(ctx, durationBar, "Bar position", barX(3), -76, DURATION_BAR_POSITION_VALUES, barCol,
                function() return item.placed.durationBarPosition or "BOTTOM" end,
                function(value) item.placed.durationBarPosition = value or "BOTTOM"; Apply("AURAS3_CUSTOM_DURATION_POSITION") end,
                AuraControlMeta(ctx, "custom-container.appearance.duration-position")),
            BindDropdown(ctx, durationBar, "Bar fill", barX(4), -76, DURATION_BAR_DIRECTION_VALUES, barCol,
                function() return item.placed.durationBarDirection or "REMAINING" end,
                function(value) item.placed.durationBarDirection = value or "REMAINING"; Apply("AURAS3_CUSTOM_DURATION_DIRECTION") end,
                AuraControlMeta(ctx, "custom-container.appearance.duration-direction")),
        })

        if W.SetCollapsibleBadges then
            local function ToggleBadge(label, enabled)
                return { text = label .. (enabled and " On" or " Off"), kind = enabled and "accent" or "muted", showWhenClosed = true }
            end
            M.TrackRefresh(ctx, function()
                local placed = item.placed
                local zoom = Round(tonumber(placed.iconZoom) or 100)
                local opacity = floor(((tonumber(placed.alpha) or 1) * 100) + 0.5)
                local basicsBadges = { ToggleBadge("Tooltip", placed.showTooltip ~= false) }
                W.SetCollapsibleBadges(scaling, {{
                    text = M.Format("Zoom %d%%", zoom), kind = "info", showWhenClosed = true,
                }})
                if opacity < 100 then
                    basicsBadges[#basicsBadges + 1] = { text = M.Format("Opacity %d%%", opacity), kind = "info", showWhenClosed = true }
                end
                if harmfulContainer then
                    local borderMode = tostring(placed.debuffTypeBorderMode or "OFF"):upper()
                    basicsBadges[#basicsBadges + 1] = {
                        text = "Border " .. ChoiceLabel(DEBUFF_TYPE_BORDER_MODE_VALUES, borderMode, borderMode),
                        kind = borderMode == "OFF" and "muted" or "accent", showWhenClosed = true,
                    }
                end
                W.SetCollapsibleBadges(basics, basicsBadges)

                local stackEnabled = placed.showStacks ~= false
                W.SetCollapsibleBadges(stack, {{
                    text = stackEnabled and (tostring(Round(tonumber(placed.stackSize) or 14)) .. "px / " .. AnchorLabel(placed.stackAnchor or "BOTTOMRIGHT")) or "Off",
                    kind = stackEnabled and "accent" or "muted", showWhenClosed = true,
                }})

                local cooldownEnabled = placed.showCooldown ~= false
                local decimal = Round(tonumber(placed.cooldownDecimalSeconds) or 3)
                W.SetCollapsibleBadges(cooldown, {
                    { text = cooldownEnabled and (tostring(Round(tonumber(placed.cooldownSize) or 14)) .. "px / " .. AnchorLabel(placed.cooldownAnchor or "CENTER") .. " / " .. ChoiceLabel(COOLDOWN_SWIPE_DIRECTION_VALUES, placed.cooldownSwipeReverse == true and "REVERSE" or "NORMAL", "Normal")) or "Off", kind = cooldownEnabled and "accent" or "muted", showWhenClosed = true },
                    { text = decimal > 0 and ("Decimals below " .. tostring(decimal) .. "s") or "Whole seconds", kind = "info", showWhenClosed = true },
                })

                local durationEnabled = placed.showDurationBar == true
                W.SetCollapsibleBadges(durationBar, {{
                    text = durationEnabled and (tostring(Round(tonumber(placed.durationBarHeight) or 2)) .. "px / " .. ChoiceLabel(DURATION_BAR_DISPLAY_VALUES, placed.durationBarDisplay or "BAR_ONLY", "Bar Only") .. " / " .. ChoiceLabel(DURATION_BAR_POSITION_VALUES, placed.durationBarPosition or "BOTTOM", "Bottom")) or "Off",
                    kind = durationEnabled and "accent" or "muted", showWhenClosed = true,
                }})
            end)
        end
        return
    end

    if tool == "effect" then
        local section = b:CollapsibleSection(CustomStyleSectionId(index, "full_frame"), "Full-Frame Effect", 210, false)
        local w = section._msuf2Width or b.width or 720
        local col3, gap = Grid(w, 3)
        BindDropdown(ctx, section, "Effect", 24, -34, CUSTOM_FRAME_EFFECTS, col3,
            function() return item.frame.type or "none" end,
            function(value) item.frame.type = value or "none"; Apply("AURAS3_CUSTOM_EFFECT") end,
            AuraControlMeta(ctx, "custom-container.effect.type"))
        local color = W.Color(section, "Color")
        M.BindColor(ctx, color,
            function() local c = item.frame.color; return c[1] or 0.69, c[2] or 0.50, c[3] or 0.88 end,
            function(r, g, blue) local a = item.frame.color[4] or 0.8; item.frame.color = { r, g, blue, a }; Apply("AURAS3_CUSTOM_EFFECT_COLOR") end,
            AuraControlMeta(ctx, "custom-container.effect.color"))
        W.MoveWidget(color, section, 24 + col3 + gap, -34, col3, "LEFT")
        BindSlider(ctx, section, "Opacity", 24, -96, 5, 100, 5, col3,
            function() return floor(((item.frame.color[4] or 0.8) * 100) + 0.5) end,
            function(value) item.frame.color[4] = (tonumber(value) or 80) / 100; item.frame.tintAlpha = item.frame.color[4]; Apply("AURAS3_CUSTOM_EFFECT_ALPHA") end,
            AuraControlMeta(ctx, "custom-container.effect.opacity"))
        BindSlider(ctx, section, "Layer (0-30)", 24 + col3 + gap, -96, 0, 30, 1, col3,
            function() return tonumber(item.frame.layer) or 0 end,
            function(value) item.frame.layer = floor(tonumber(value) or 0); Apply("AURAS3_CUSTOM_EFFECT_LAYER") end,
            AuraControlMeta(ctx, "custom-container.effect.layer"))
        BindSlider(ctx, section, "Thickness", 24 + 2 * (col3 + gap), -96, 1, 16, 1, col3,
            function() return tonumber(item.frame.thickness) or 2 end,
            function(value) item.frame.thickness = tonumber(value) or 2; Apply("AURAS3_CUSTOM_EFFECT_THICKNESS") end,
            AuraControlMeta(ctx, "custom-container.effect.thickness"))
        BindSlider(ctx, section, "Priority", 24, -150, 1, 10, 1, col3,
            function() return tonumber(item.frame.priority) or 5 end,
            function(value) item.frame.priority = tonumber(value) or 5; Apply("AURAS3_CUSTOM_EFFECT_PRIORITY") end,
            AuraControlMeta(ctx, "custom-container.effect.priority"))
        if W.SetCollapsibleBadges then
            M.TrackRefresh(ctx, function()
                local effectType = tostring(item.frame.type or "none")
                W.SetCollapsibleBadges(section, {{
                    text = ChoiceLabel(CUSTOM_FRAME_EFFECTS, effectType, effectType),
                    kind = effectType == "none" and "muted" or "accent", showWhenClosed = true,
                }})
            end)
        end
        return
    end

    if tool == "behavior" then
        local sortLane = (isTargetDots or tostring(item.auraType or "BUFF"):upper() == "DEBUFF") and "debuff" or "buff"
        local section = b:CollapsibleSection(CustomStyleSectionId(index, "behavior"), "Ordering", 96, false)
        local w = section._msuf2Width or b.width or 720
        local col4, gap = Grid(w, 4)
        -- The sort-method choice list differs between helpful and harmful
        -- containers, so the catalog path carries the lane type exactly like
        -- the Buff/Debuff style pages do; a shared path would merge two
        -- different value domains into one schema row.
        local sortMethod = BindDropdown(ctx, section, "Sort By", 24, -34, AuraSortMethodValues(sortLane), col4,
            function() return NormalizeAuraSortMethodForLane(sortLane, item.placed.sortMethod) end,
            function(value) item.placed.sortMethod = value or "DEFAULT"; Apply("AURAS3_CUSTOM_SORT_METHOD") end,
            AuraControlMeta(ctx, "custom-container.behavior." .. sortLane .. "-sort-method"))
        AddTooltip(sortMethod, "Aura sorting", "Only relevant sorting methods are shown for buffs and debuffs.")
        local sortDirection = BindDropdown(ctx, section, "Order", 24 + col4 + gap, -34, AURA_SORT_DIRECTION_VALUES, col4,
            function() return item.placed.sortReverse == true and "REVERSE" or "NORMAL" end,
            function(value) item.placed.sortReverse = value == "REVERSE"; Apply("AURAS3_CUSTOM_SORT_DIRECTION") end,
            AuraControlMeta(ctx, "custom-container.behavior.sort-direction"))
        AddTooltip(sortDirection, "Aura sort order", "Reversed flips the complete priority order.")
        if W.SetCollapsibleBadges then
            M.TrackRefresh(ctx, function()
                local sortKey = NormalizeAuraSortMethodForLane(sortLane, item.placed.sortMethod)
                W.SetCollapsibleBadges(section, {{
                    text = (AURA_SORT_SUMMARY_LABELS[sortKey] or sortKey) .. " / "
                        .. ChoiceLabel(AURA_SORT_DIRECTION_VALUES, item.placed.sortReverse == true and "REVERSE" or "NORMAL", "Normal"),
                    kind = "info", showWhenClosed = true,
                }})
            end)
        end
        return
    end

    if isPlayerDefensives then
        local section = b:Section("Defensive Buffs Setup", 390)
        local w = section._msuf2Width or b.width or 720
        local inner = w - 48
        local enabled = BindSwitch(ctx, section, "Enabled", 24, -48, 112,
            function() return item.enabled == true end,
            function(value)
                item.enabled = value == true
                Apply("AURAS3_PLAYER_DEFENSIVES_ENABLE", true)
            end,
            AuraControlMeta(ctx, "custom-container.player-defensives.enabled"))
        AddTooltip(enabled, "Enable defensive buffs",
            "Core feature enabled by default for new profiles and once for existing profiles. It works as a normal defensive buff bar without an enabled portrait. Turn this off to disable both bar and portrait-position display.")
        local portrait = BindSwitch(ctx, section, "Show buffs at portrait position", 24, -86, 280,
            function() return item.portraitIcon == true end,
            function(value)
                item.portraitIcon = value == true
                Apply("AURAS3_PLAYER_DEFENSIVE_PORTRAIT", true)
            end,
            AuraControlMeta(ctx, "custom-container.player-defensives.portrait-icon"))
        AddTooltip(portrait, "Show buffs at portrait position",
            "Optional presentation mode; the Defensive Buffs feature itself does not require a portrait. With an enabled portrait, the first icon occupies it. When the portrait is off, enable the position option below to keep the icons there; otherwise MSUF safely falls back to the normal defensive bar.")
        local portraitMax = BindSlider(ctx, section, "Max portrait icons", 24, -128, 1, 8, 1, inner,
            function() return tonumber(item.portraitMaxIcons) or 1 end,
            function(value)
                item.portraitMaxIcons = max(1, min(8, floor((tonumber(value) or 1) + 0.5)))
                Apply("AURAS3_PLAYER_DEFENSIVE_PORTRAIT_MAX", true)
            end,
            AuraControlMeta(ctx, "custom-container.player-defensives.portrait-max-icons"))
        AddTooltip(portraitMax, "Max portrait icons",
            "Limits the number of simultaneous defensive icons at the portrait from 1 to 8. Existing profiles remain at 1 until this value is changed.")
        local cooldownText = BindSwitch(ctx, section, "Show cooldown text on portrait", 24, -198, 280,
            function() return item.portraitCooldownText ~= false end,
            function(value)
                item.portraitCooldownText = value == true
                Apply("AURAS3_PLAYER_DEFENSIVE_PORTRAIT_COOLDOWN", true)
            end,
            AuraControlMeta(ctx, "custom-container.player-defensives.portrait-cooldown-text"))
        AddTooltip(cooldownText, "Show cooldown text on portrait",
            "Shows the active defensive buff's remaining duration over its portrait icon. Blizzard updates the text natively.")
        local positionOnly = BindSwitch(ctx, section, "Use portrait position while portrait is off", 24, -236, 326,
            function() return item.portraitPositionWhenDisabled == true end,
            function(value)
                item.portraitPositionWhenDisabled = value == true
                Apply("AURAS3_PLAYER_DEFENSIVE_PORTRAIT_POSITION", true)
            end,
            AuraControlMeta(ctx, "custom-container.player-defensives.portrait-position-when-disabled"))
        AddTooltip(positionOnly, "Use portrait position while portrait is off",
            "Keeps the configured portrait size and position as an invisible anchor so the defensive icon can remain there while the portrait itself is disabled.")
        local autoBlacklist = BindSwitch(ctx, section, "Auto-blacklist from player buffs", 24, -274, 280,
            function() return item.autoBlacklistPlayerBuffs ~= false end,
            function(value)
                item.autoBlacklistPlayerBuffs = value == true
                Apply("AURAS3_PLAYER_DEFENSIVE_AUTO_BLACKLIST", true)
            end,
            AuraControlMeta(ctx, "custom-container.player-defensives.auto-blacklist"))
        AddTooltip(autoBlacklist, "Auto-blacklist from player buffs",
            "While the defensive bar or portrait icon is enabled, hides every enabled tracked defensive from the normal player Buffs lane. Disabled defensive entries remain visible there.")
        local reset = ActionButton(section, "Reset", 88)
        reset:SetPoint("TOPRIGHT", section, "TOPRIGHT", -24, -42)
        reset:SetScript("OnClick", function()
            Model.ResetCustomContainer(unit, index)
            Apply("AURAS3_PLAYER_DEFENSIVES_RESET", true)
            Rebuild(ctx)
        end)
        RegisterAuraControl(ctx, reset, "Reset", "button", customActionPath .. ".setup.reset", "action", {
            actionKey = "reset_aura_custom_container", actionFixedArgs = { scope = unit, index = index },
        })
        local predefined = type(Model.PlayerDefensivePreviewEntries) == "function"
            and #Model.PlayerDefensivePreviewEntries() or 0
        local predefinedTotal = type(Model.PlayerDefensiveClassEntries) == "function"
            and #Model.PlayerDefensiveClassEntries(true) or predefined
        local custom = #Model.CustomContainerSpellEntries(unit, index)
        W.Text(section, "Source: player buffs · " .. tostring(predefined) .. " / "
            .. tostring(predefinedTotal) .. " predefined enabled · " .. tostring(custom)
            .. " custom · passive talent procs included", 24, -344, inner, T.colors.muted)
        return
    end

    if isTargetDots then
        local section = b:Section("Dots on target Setup", 132)
        local w = section._msuf2Width or b.width or 720
        local inner = w - 48
        BindSwitch(ctx, section, "Enabled", 24, -48, 112,
            function() return item.enabled == true end,
            function(value) item.enabled = value == true; Apply("AURAS3_TARGET_DOTS_ENABLE") end,
            AuraControlMeta(ctx, "custom-container.target-dots.enabled"))
        local reset = ActionButton(section, "Reset", 88)
        reset:SetPoint("TOPRIGHT", section, "TOPRIGHT", -24, -42)
        reset:SetScript("OnClick", function() Model.ResetCustomContainer(unit, index); Apply("AURAS3_TARGET_DOTS_RESET", true); Rebuild(ctx) end)
        RegisterAuraControl(ctx, reset, "Reset", "button", customActionPath .. ".setup.reset", "action", {
            actionKey = "reset_aura_custom_container", actionFixedArgs = { scope = unit, index = index },
        })
        local count = #Model.CustomContainerSpellEntries(unit, index)
        W.Text(section, "Source: current target · Ownership: only mine · Harmful DoTs only · " .. tostring(count) .. " selected", 24, -94, inner, T.colors.muted)
        return
    end

    local section = b:Section(containerLabel .. " Setup", 132)
    local w = section._msuf2Width or b.width or 720
    local inner = w - 48
    local enabled = BindSwitch(ctx, section, "Enabled", 24, -62, 106,
        function() return item.enabled == true end,
        function(value) item.enabled = value == true; Apply("AURAS3_CUSTOM_CONTAINER_ENABLE") end,
        AuraControlMeta(ctx, "custom-container.setup.enabled"))
    local nameW = max(260, floor(inner * 0.42))
    BindTextInput(ctx, section, "Container name", 140, -34, nameW,
        function() return item.name or ("Custom " .. tostring(index)) end,
        function(value) item.name = value ~= "" and value or ("Custom " .. tostring(index)); Apply("AURAS3_CUSTOM_CONTAINER_NAME") end,
        false, AuraControlMeta(ctx, "custom-container.setup.name"))
    local typeW = max(170, floor(inner * 0.18))
    BindDropdown(ctx, section, "Aura type", 150 + nameW, -34, CUSTOM_AURA_TYPES, typeW,
        function() return item.auraType == "DEBUFF" and "DEBUFF" or "BUFF" end,
        function(value) item.auraType = value == "DEBUFF" and "DEBUFF" or "BUFF"; Apply("AURAS3_CUSTOM_CONTAINER_TYPE", true); Rebuild(ctx) end,
        AuraControlMeta(ctx, "custom-container.setup.aura-type"))
    local reset = ActionButton(section, "Reset", 88)
    reset:SetPoint("TOPRIGHT", section, "TOPRIGHT", -24, -56)
    reset:SetScript("OnClick", function() Model.ResetCustomContainer(unit, index); Apply("AURAS3_CUSTOM_CONTAINER_RESET", true); Rebuild(ctx) end)
    RegisterAuraControl(ctx, reset, "Reset", "button", customActionPath .. ".setup.reset", "action", {
        actionKey = "reset_aura_custom_container",
        actionFixedArgs = { scope = unit, index = index },
    })
    local count = #Model.CustomContainerSpellEntries(unit, index)
    W.Text(section, tostring(count) .. " whitelisted " .. (count == 1 and "spell" or "spells") .. " · style remains live in Menu Preview and Edit Mode.", 24, -104, inner, T.colors.muted)
    M.TrackRefresh(ctx, function() W.SetControlEnabled(enabled, true) end)
end

local function BuildMovedAuraPage(ctx)
    local b = W.PageBuilder(ctx)
    b:GlobalStyleHeader("Aura Content moved to Frames", "Style stays here under Appearance > Auras. Filters and lists now live directly in each frame's matching Aura menu.", 84)
    local section = b:Section("Open a Frame", 190)
    local w = section._msuf2Width or b.width or 720
    local pages = {
        { "Player", "uf_player" }, { "Target", "uf_target" }, { "Focus", "uf_focus" },
        { "Boss", "uf_boss" }, { "Group Frames", "gf_auras" },
    }
    local x = 24
    for i = 1, #pages do
        local page = pages[i]
        local button = ActionButton(section, page[1], i == 5 and 132 or 92)
        button:SetPoint("TOPLEFT", section, "TOPLEFT", x, -60)
        button:SetScript("OnClick", function() if M.SelectPage then M.SelectPage(page[2]) end end)
        RegisterAuraControl(ctx, button, page[1], "button", "moved-page.open." .. AuraCatalogToken(page[2]), "navigation", page[2])
        x = x + (i == 5 and 144 or 104)
    end
    W.Text(section, "Open the frame and expand Auras. Buffs and Debuffs contain their own Blizzard filters and blacklists; Custom 1-3 use whitelists, player Defensive Buffs uses its class list plus custom IDs, and Dots on target uses its curated DoT list.", 24, -118, w - 48, T.colors.muted)
    FinishPage(ctx, b)
end

-- Appearance keeps the scope-aware style editor. Old content/filter routes remain
-- as compatibility landings and direct users to the matching frame Aura menu.
M.RegisterPage("auras3_buffs", { title = "Aura Style: Buffs", build = function(ctx) BuildAuraStyleLanePage(ctx, "buff") end, version = 23 })
M.RegisterPage("auras3_debuffs", { title = "Aura Style: Debuffs", build = function(ctx) BuildAuraStyleLanePage(ctx, "debuff") end, version = 23 })
M.RegisterPage("auras3_custom", { title = "MSUF Auras", build = BuildMovedAuraPage, version = 2 })
M.RegisterPage("auras3_styling", { title = "Aura Style", build = BuildAuraStylePage, version = 47 })
M.RegisterPage("auras3_filters", { title = "MSUF Auras", build = BuildMovedAuraPage, version = 31 })
