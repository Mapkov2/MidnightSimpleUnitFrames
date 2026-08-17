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
local AURA_SCOPE_LABELS = { shared = "Shared", player = "Player", target = "Target", focus = "Focus", boss = "Boss", party = "Party", raid = "Raid / Mythic" }
local AURA_SCOPE_VALID = M.KeySetFromWords "shared player target focus boss party raid"
local AURA_GROUP_SCOPES = M.KeySetFromWords "party raid mythicraid"
local LANE_VALUES = VTP "buff=Buffs|debuff=Debuffs"
-- Appearance > Aura Style owns only the genuinely global Aura theme selected
-- by Aura product. Every layout/filter/deep-Style value remains frame-local.
M.SHARED_AURA_STYLE_CONTAINER_VALUES = VTP
    "buff=Buffs|debuff=Debuffs|playerDefensives=Player Defensives|targetDots=Dots on Target"
local UNIT_STYLE_CONTAINER_VALUES = VTP "buff=Buffs|debuff=Debuffs|custom1=Custom 1|custom2=Custom 2|custom3=Custom 3|custom4=Dots on target"
local UNIT_STYLE_CONTAINER_VALUES_PLAYER = VTP "buff=Buffs|debuff=Debuffs|custom1=Custom 1|custom2=Custom 2|custom3=Custom 3|custom4=Defensive Buffs"
local CUSTOM_FRAME_EFFECTS = VTP "none=None|healthtint=Health Tint|border=Border|glow=Glow|pulse=Pulse|namecolor=Name Overlay"
local DEBUFF_TYPE_BORDER_MODE_VALUES = VTP "OFF=Off|BORDER=Border|SYMBOL=Border + Symbol"
local COOLDOWN_SWIPE_DIRECTION_VALUES = VTP "NORMAL=Normal|REVERSE=Reverse"
M.AURA_STEALABLE_STYLE_VALUES = M.AURA_STEALABLE_STYLE_VALUES
    or VTP "BORDER=Border|BORDER_ICON=Border + Icon|ICON=Icon"
M.AURA_PANDEMIC_STYLE_VALUES = M.AURA_PANDEMIC_STYLE_VALUES
    or VTP "BORDER=Border|TINT=Tint|BORDER_TINT=Border + Tint"
M.AURA_PANDEMIC_BLEND_VALUES = M.AURA_PANDEMIC_BLEND_VALUES or VTP "ADD=Additive|BLEND=Normal"
local AURA_SORT_DIRECTION_VALUES = VTP "NORMAL=Normal|REVERSE=Reversed"
local BUFF_AURA_SORT_METHOD_VALUES = VTP "DEFAULT=Player & Priority First|BIG_DEFENSIVE=Other Defensives First|IMPORTANT_FIRST=Important First|EXPIRATION=Player First, Expiring Soon|EXPIRATION_ONLY=Expiring Soon|NAME=Player First, then Name|NAME_ONLY=Name|INSTANCE_ID=Arrival Order"
local DEBUFF_AURA_SORT_METHOD_VALUES = VTP "DEFAULT=Player & Priority First|UNIT_FRAME_DEBUFF=Debuff Type First|IMPORTANT_FIRST=Important First|EXPIRATION=Player First, Expiring Soon|EXPIRATION_ONLY=Expiring Soon|NAME=Player First, then Name|NAME_ONLY=Name|INSTANCE_ID=Arrival Order"
local CUSTOM_PRIORITY_AURA_SORT_METHOD_VALUES = VTP "CUSTOM_PRIORITY=Custom Priority|DEFAULT=Player & Priority First|UNIT_FRAME_DEBUFF=Debuff Type First|IMPORTANT_FIRST=Important First|EXPIRATION=Player First, Expiring Soon|EXPIRATION_ONLY=Expiring Soon|NAME=Player First, then Name|NAME_ONLY=Name|INSTANCE_ID=Arrival Order"
local DURATION_BAR_DISPLAY_VALUES = VTP "BAR_ONLY=Bar Only|OVERLAY=Icon + Bar"
local DURATION_BAR_POSITION_VALUES = VTP "BOTTOM=Bottom|TOP=Top"
local DURATION_BAR_DIRECTION_VALUES = VTP "REMAINING=Remaining|ELAPSED=Elapsed"
M.AURA_ICON_SHAPE_VALUES = VTP "RECTANGLE=Rectangular (current)|FOLLOW_PORTRAIT=Follow frame portrait|CIRCLE=Circle|ROUNDED=Rounded|DIAMOND=Diamond|HEXAGON=Hexagon|STAR=Star|BLIZZARD=Blizzard portrait"
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
-- `title` arrives already localized; only the surrounding wording is a format key.
function M.AttachAuraFontsAndColors(section, title, unit)
    if not (section and W.AttachContextColorReferences) then return end
    local references = AURA_COOLDOWN_COLOR_REFERENCES()
    if #references == 1 then references[2] = AURA_DURATION_BAR_COLOR_REFERENCES[1] end
    W.AttachContextColorReferences(section, references, {
        title = M.Format("%s Fonts & Colors", title),
        historyLabel = M.Format("%s color", title),
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
            colorTitle = M.Format("%s Colors", title),
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
local function AuraSortMethodValues(lane, allowCustomPriority)
    if allowCustomPriority == true then return CUSTOM_PRIORITY_AURA_SORT_METHOD_VALUES end
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
    NAME = "Player + name", NAME_ONLY = "Name", INSTANCE_ID = "Arrival order", CUSTOM_PRIORITY = "Custom priority",
}
local function AnchorLabel(value)
    value = tostring(value or "CENTER"):upper()
    return AURA_ANCHOR_LABELS[value] or value
end
local function NormalizeAuraSortMethodForLane(lane, value, allowCustomPriority)
    value = tostring(value or "DEFAULT"):upper()
    if allowCustomPriority == true and value == "CUSTOM_PRIORITY" then return value end
    local allowed = lane == "debuff" and DEBUFF_AURA_SORT_METHOD_OK or BUFF_AURA_SORT_METHOD_OK
    return allowed[value] and value or "DEFAULT"
end
local DEBUFF_TYPE_BORDER_PREVIEW_ATLAS = {
    BORDER = "ui-debuff-border-magic-noicon",
    SYMBOL = "ui-debuff-border-magic-icon",
}
local NATIVE_EXACT_AURA_FILTERS_ENABLED = true
local NATIVE_EXACT_AURA_FILTERS_TEXT = "Exact Spell IDs are used when Blizzard exposes them."
M.CLASSIC_AURA_FILTERS_REDUCED = MSUF.Client and MSUF.Client.IsClassic == true
    or (_G.WOW_PROJECT_ID ~= nil and _G.WOW_PROJECT_ID ~= _G.WOW_PROJECT_MAINLINE)
local GROUP_NATIVE_FILTER_LABELS = {
    ALL = "All",
    Player = "Cast by Me",
    BigDefensivePlayer = "Big Defensive by Me",
    ExternalDefensivePlayer = "External Defensive by Me",
    RaidInCombatPlayer = "Raid In Combat Player",
    CancelablePlayer = "Cancelable Player",
    NotCancelablePlayer = "Not Cancelable Player",
    RaidPlayer = "Applicable and Cast by Me",
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
    NonPlayer = "Non-Player Auras",
}
local GROUP_NATIVE_FILTER_ALLOWED = {
    buff = {
        ALL = true, Player = true, BigDefensivePlayer = true, ExternalDefensivePlayer = true,
        BigDefensive = true, ExternalDefensive = true, RaidInCombat = true, Raid = true, RaidPlayer = true,
    },
    debuff = {
        ALL = true, Player = true, Raid = true, RaidInCombat = true,
        RAID_PLAYER_DISPELLABLE = true, DISPELLABLE = true, CROWD_CONTROL = true,
        NonPlayer = true,
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
    NONPLAYER = "NonPlayer",
}
local function CanonicalGroupFilterValue(value, lane)
    if M.CLASSIC_AURA_FILTERS_REDUCED == true then
        local key = tostring(value or "ALL"):upper():gsub("[^A-Z0-9]", "")
        local canonical = GROUP_NATIVE_FILTER_CANONICAL[key] or "ALL"
        if canonical == "Player" or canonical:sub(-6) == "Player" then return "Player" end
        return "ALL"
    end
    local auraFilter = (type(MSUF.GF) == "table" and MSUF.GF.AuraFilter) or _G.MSUF_GF_AuraFilter
    local canonical
    if auraFilter and type(auraFilter.NormalizeFilterToken) == "function" then
        canonical = auraFilter.NormalizeFilterToken(lane, value)
    else
        local key = tostring(value or "ALL"):upper():gsub("[^A-Z0-9]", "")
        canonical = GROUP_NATIVE_FILTER_CANONICAL[key] or "ALL"
    end
    local allowed = GROUP_NATIVE_FILTER_ALLOWED[lane == "debuff" and "debuff" or "buff"]
    return allowed[canonical] and canonical or "ALL"
end
local function Tr(text)
    if type(M.Tr) == "function" then return M.Tr(text) end
    return text
end
-- Search-result suffix shared by every aura list status line.
local function MatchSuffix(query, count)
    if query == nil or query == "" then return "" end
    return M.Format(" - %d matches", count)
end
local function AuraCatalogToken(value, fallback)
    local token = tostring(value or ""):lower():gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
    return token ~= "" and token or (fallback or "control")
end
local function AuraCatalogPageKey(value, fallback)
    local token = tostring(value or ""):lower():gsub("[^%w_%-]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
    return token ~= "" and token or (fallback or "auras")
end
local function LaneFrameEffectAssistantContract(unit, lane, field)
    if field == "type" then
        return "auras3." .. tostring(unit or "shared") .. "."
            .. (lane == "buff" and "buff" or "debuff") .. ".frameEffectType"
    end
    return {
        assistantDisposition = "compound",
        assistantDispositionReason = "This Full-Frame effect detail shares a compound color or numeric value; only its Effect dropdown has a direct Assistant setting contract.",
    }
end
M._customContainerAssistantSuffixes = {
    "enabled", "filters.enabled", "filters.hidePermanent", "filters.onlyMine",
    "filters.onlyImportant", "filters.raid", "filters.raidInCombat",
    "filters.includeNameplateOnly", "filters.includeDispellable", "filters.dispellableAny",
    "filters.cancelable", "filters.notCancelable", "filters.externalDefensive",
    "filters.bigDefensive", "filters.crowdControl", "placed.anchor", "placed.growth",
    "placed.x", "placed.y", "placed.max", "placed.size", "placed.perRow", "placed.spacing",
    "placed.showStacks", "placed.showCooldown", "placed.showCooldownSwipe",
}
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
local function RegisterAuraChoiceBar(ctx, bar, values, path, assistantContract)
    if not bar then return bar end
    RegisterAuraControl(ctx, bar, bar._msuf2SearchTitle or "Editing", "segment", path,
        assistantContract and "setting" or "ephemeral", assistantContract)
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
local function AddAuraTooltipHelp(widget)
    return AddTooltip(widget, "Aura tooltip",
        "Controls this aura lane independently. Always / Out of Combat / Modifier / Never under Global Style > Miscellaneous affect only unit and group frames. Auras only reuse the selected Blizzard/MSUF look and cursor placement.")
end
local function ActionButton(parent, label, width, role)
    if W.RoleButton then return W.RoleButton(parent, label, role or "normal", width or 90, 24) end
    if W.TopButton then return W.TopButton(parent, label, width or 90, 24) end
    local btn = T.Button(parent, label, width or 90, 24)
    if W.StyleTopActionButton then W.StyleTopActionButton(btn) end
    return btn
end

local CUSTOM_DEBUFF_BLACKLIST_INFO_SEEN_KEY = "auraEnemyDebuffBlacklistInfoSeen"
local CUSTOM_DEBUFF_BLACKLIST_INFO_TITLE = "UnitFrame Debuff blacklist"
local CUSTOM_DEBUFF_BLACKLIST_INFO_BODY = "You can blacklist any debuff applied by the player on the %s UnitFrame using its exact Spell ID. The debuff on the unit can carry a different Spell ID than the spell you cast - use the ID from the debuff itself."

local function CustomDebuffBlacklistInfoSeen()
    local general = type(M.GetGeneralDB) == "function" and M.GetGeneralDB() or nil
    return type(general) == "table" and general[CUSTOM_DEBUFF_BLACKLIST_INFO_SEEN_KEY] == true
end

local function StopCustomDebuffBlacklistInfoPulse(button)
    local pulse = button and button._msuf2CustomDebuffBlacklistInfoPulse
    if pulse and pulse.Stop then pulse:Stop() end
    if button and button.SetAlpha then button:SetAlpha(1) end
end

local function CreateCustomDebuffBlacklistInfoButton(parent, input, unit)
    local button = ActionButton(parent, "I", 28)
    button:SetSize(28, 26)
    button._msuf2SkipHistoryCheckpoint = true
    button._msuf2AllowCombatClick = true
    if M.MarkRuntimeControlComponent and input then M.MarkRuntimeControlComponent(button, input) end
    if T.CenterButtonLabel then T.CenterButtonLabel(button) end
    if button._msuf2Label and T.ApplyMenuFont then
        T.ApplyMenuFont(button._msuf2Label, 3, "heading")
    end
    local labelAnchor = input and input._msuf2Title
    if labelAnchor then
        local textWidth = labelAnchor.GetStringWidth and tonumber(labelAnchor:GetStringWidth()) or nil
        local titleWidth = labelAnchor.GetWidth and tonumber(labelAnchor:GetWidth()) or nil
        if textWidth and textWidth > 0 then
            local visibleTextWidth = titleWidth and min(textWidth, max(0, titleWidth - 36)) or textWidth
            button:SetPoint("LEFT", labelAnchor, "CENTER", floor((visibleTextWidth * 0.5) + 8), 0)
        else
            button:SetPoint("LEFT", labelAnchor, "RIGHT", 8, 0)
        end
    end
    local unitLabel = M.Tr(AURA_SCOPE_LABELS[unit] or tostring(unit or "Unit"))
    AddTooltip(button, CUSTOM_DEBUFF_BLACKLIST_INFO_TITLE,
        M.Format(CUSTOM_DEBUFF_BLACKLIST_INFO_BODY, unitLabel))
    button:SetScript("OnClick", function(self)
        local general = type(M.GetGeneralDB) == "function" and M.GetGeneralDB() or nil
        if type(general) == "table" then general[CUSTOM_DEBUFF_BLACKLIST_INFO_SEEN_KEY] = true end
        StopCustomDebuffBlacklistInfoPulse(self)
        return true
    end)

    if not CustomDebuffBlacklistInfoSeen()
        and button.CreateAnimationGroup
        and not (T.ReducedMotionEnabled and T.ReducedMotionEnabled())
    then
        local pulse = button:CreateAnimationGroup()
        if T.TrackMenuAnimationGroup then T.TrackMenuAnimationGroup(pulse) end
        if pulse.SetLooping then pulse:SetLooping("REPEAT") end
        local fadeOut = pulse:CreateAnimation("Alpha")
        fadeOut:SetFromAlpha(1)
        fadeOut:SetToAlpha(0.45)
        fadeOut:SetDuration(0.8)
        fadeOut:SetOrder(1)
        if fadeOut.SetSmoothing then fadeOut:SetSmoothing("IN_OUT") end
        local fadeIn = pulse:CreateAnimation("Alpha")
        fadeIn:SetFromAlpha(0.45)
        fadeIn:SetToAlpha(1)
        fadeIn:SetDuration(0.8)
        fadeIn:SetOrder(2)
        if fadeIn.SetSmoothing then fadeIn:SetSmoothing("IN_OUT") end
        if pulse.SetScript then pulse:SetScript("OnStop", function() button:SetAlpha(1) end) end
        button._msuf2CustomDebuffBlacklistInfoPulse = pulse
        pulse:Play()
    end
    return button
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
        local main = M.scrollFrame
        local handler = main and main.GetScript and main:GetScript("OnMouseWheel")
        if type(handler) == "function" and main ~= scrollFrame then
            if scrollFrame.SetPropagateMouseWheel then scrollFrame:SetPropagateMouseWheel(false) end
            handler(main, delta)
        elseif scrollFrame.SetPropagateMouseWheel then
            scrollFrame:SetPropagateMouseWheel(true)
        end
        return
    end
    if scrollFrame.SetPropagateMouseWheel then scrollFrame:SetPropagateMouseWheel(false) end
    local value = current - (delta * (tonumber(step) or 42))
    if value < 0 then value = 0 elseif value > range then value = range end
    if scrollFrame.SetVerticalScroll then scrollFrame:SetVerticalScroll(value) end
end

function M._StyleNestedAuraScrollFrame(scrollFrame, anchor, step)
    if not scrollFrame then return end
    if scrollFrame.SetPropagateMouseWheel then scrollFrame:SetPropagateMouseWheel(false) end
    if type(T.StyleScrollFrame) == "function" then T.StyleScrollFrame(scrollFrame, anchor) end
    local function OnMouseWheel(_, delta)
        HandleNestedScrollWheel(scrollFrame, delta, step)
    end
    if scrollFrame.EnableMouseWheel then scrollFrame:EnableMouseWheel(true) end
    scrollFrame:SetScript("OnMouseWheel", OnMouseWheel)
    local child = scrollFrame.GetScrollChild and scrollFrame:GetScrollChild()
    if child and child.EnableMouseWheel then
        child:EnableMouseWheel(true)
        child:SetScript("OnMouseWheel", OnMouseWheel)
    end
    local bar = scrollFrame._msuf2ScrollBar
    if bar and bar.EnableMouseWheel then
        bar:EnableMouseWheel(true)
        bar:SetScript("OnMouseWheel", OnMouseWheel)
    end
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
local function CurrentScope()
    if type(M.EnsurePersistentMenuState) == "function" then M.EnsurePersistentMenuState() end
    local scope = M.auraScope or "shared"
    if scope == "mythicraid" then scope = "raid" end
    return AURA_SCOPE_VALID[scope] and scope or "shared"
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
    if kind == "buff" then return "Buff" end
    if kind == "external" or kind == "externals" then return "External Defensive" end
    return "Debuff"
end
local function LanePlural(kind)
    if kind == "buff" then return "Buffs" end
    if kind == "external" or kind == "externals" then return "External Defensives" end
    return "Debuffs"
end
local function CurrentAuraStyleContainer(scope)
    local container = scope == "appearance"
        and (M.auraAppearanceContainer or CurrentLane("auraStyleGFLane", "debuff"))
        or (M.auraStyleContainer or CurrentLane("auraStyleGFLane", "debuff"))
    if scope == "appearance" then
        if container ~= "buff" and container ~= "debuff"
            and container ~= "playerDefensives" and container ~= "targetDots"
        then
            container = CurrentLane("auraStyleGFLane", "debuff")
        end
        return container
    end
    local custom = tostring(container):match("^custom[1234]$") ~= nil
    if container ~= "buff" and container ~= "debuff" and not custom then container = "debuff" end
    if IsGroupScope(scope) and custom then
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
    local values = scope == "appearance" and M.SHARED_AURA_STYLE_CONTAINER_VALUES
        or ((not IsGroupScope(scope))
            and (scope == "player" and UNIT_STYLE_CONTAINER_VALUES_PLAYER or UNIT_STYLE_CONTAINER_VALUES)
            or LANE_VALUES)
    local bar = RegisterAuraChoiceBar(ctx, W.ScopeOverrideBar(ctx, section, {
        values = values,
        width = w,
        label = scope == "appearance" and "Aura type:" or "Container:",
        labelWidth = 88,
        centerY = -28,
        getValue = function() return CurrentAuraStyleContainer(scope) end,
        setValue = function(container)
            M.SetMenuStateValue(scope == "appearance" and "auraAppearanceContainer" or "auraStyleContainer", container)
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
    local title = current == "playerDefensives" and Tr("Player Defensives Appearance Preview")
        or current == "targetDots" and Tr("Dots on Target Appearance Preview")
        or scope == "appearance" and M.Format("%s Appearance Preview", Tr(LaneTitle(current)))
        or current == "custom4" and (scope == "player" and Tr("Defensive Buff Aura Style") or Tr("Dots on target Aura Style"))
        or (tostring(current):match("^custom[123]$") and M.Format("Custom %s Aura Style", tostring(current):match("(%d)$")))
        or M.Format("%s Aura Style", Tr(LaneTitle(current)))
    M.AttachAuraFontsAndColors(section, title, scope)
    -- Dock the container strip beneath the already-docked scope strip, like
    -- the unit pages' Editing strip: scope, container and preview form one fixed
    -- stack before the settings ScrollFrame begins.
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
local UNIT_AURA_DISPEL_WARNING = "Dispel Border, Overlay, and Symbol need this UnitFrame's Aura sensor. Enable Buffs or Debuffs, or turn on a Dispel feature to enable the sensor automatically. Set both icon caps to 0 if you want no aura icons."
local function UnitAuraSensorEnabled(unit)
    return Model.UnitEnabled(unit) == true
end
local function ModeEnabled(value, fallback)
    if value == nil then value = fallback end
    if value == true or value == false then return value end
    value = tonumber(value)
    if value == nil then return fallback == true end
    return value == 1
end
local function UnitDispelRequested(unit)
    local db = _G.MSUF_DB
    local general = type(db) == "table" and type(db.general) == "table" and db.general or nil
    local conf = type(db) == "table" and type(db[unit]) == "table" and db[unit] or nil
    local overlay = conf and conf.unitDispelOverlayEnabled
    if overlay == nil then overlay = general and general.unitDispelOverlayEnabled end
    local symbol = conf and conf.unitDispelSymbolEnabled
    if symbol == nil then symbol = general and general.unitDispelSymbolEnabled end
    if overlay == true or symbol == true then return true end
    local mode
    if conf and conf.hlOverride == true then mode = conf.dispelOutlineMode end
    if mode == nil then mode = general and general.dispelOutlineMode end
    local legacy = general and (general.dispelBorderEnabled == true or general.hlDispelBorderEnabled == true)
    if general and general.dispelBorderEnabled == nil and general.hlDispelBorderEnabled == nil then legacy = true end
    return ModeEnabled(mode, legacy)
end
local function ShowNoUnitAuraDispelWarning()
    if type(M.ShowStatusFeedback) == "function" then
        M.ShowStatusFeedback(UNIT_AURA_DISPEL_WARNING, "warning", 3.0)
    end
end
local function SetUnitLaneShown(ctx, unit, kind, shown, reason)
    if shown then
        Model.SetUnitEnabled(unit, true)
        Model.SetGroupShown(unit, kind, true)
    else
        Model.SetGroupShown(unit, kind, false)
        -- Hiding the last native lane must not disable the shared Aura sensor.
        -- A 0 icon cap is the supported sensor-only state used by Dispel.
    end
    ApplyUnit(ctx, unit, reason or "AURAS3_VISIBILITY", true)
    if UnitDispelRequested(unit) and not UnitAuraSensorEnabled(unit) then ShowNoUnitAuraDispelWarning() end
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
    if M.CLASSIC_AURA_FILTERS_REDUCED == true then
        return VT("ALL", "All", "Player", "Only mine")
    end
    local af = AuraFilter()
    local source = groupKey == "debuff" and af and af.DEBUFF_FILTER_ITEMS or af and af.BUFF_FILTER_ITEMS
    local allowed = GROUP_NATIVE_FILTER_ALLOWED[groupKey == "debuff" and "debuff" or "buff"]
    local out = {}
    if type(source) == "table" then
        for i = 1, #source do
            local item = source[i]
            local value = CanonicalGroupFilterValue(item and (item.value or item.key), groupKey)
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
            "Player", "Cast by Me",
            "BigDefensive", "Big Defensive",
            "BigDefensivePlayer", "Big Defensive by Me",
            "ExternalDefensive", "External Defensive",
            "ExternalDefensivePlayer", "External Defensive by Me",
            "RaidInCombat", "Raid In Combat",
            "Raid", "Applicable by Me (Raid)",
            "RaidPlayer", "Applicable and Cast by Me"
        )
    end
    return VT(
        "ALL", "All Debuffs",
        "Player", "Cast by Me",
        "Raid", "Dispellable by Me (Raid)",
        "RaidInCombat", "Raid In Combat",
        "RAID_PLAYER_DISPELLABLE", "Dispellable by Group",
        "DISPELLABLE", "Any Dispel Type",
        "CROWD_CONTROL", "Crowd Control",
        "NonPlayer", "Non-Player Auras"
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
local function BindGroupDropdown(ctx, parent, label, x, y, values, width, scope, groupKey, key, defaultValue, mode, afterSet, controlMeta)
    return BindDropdown(ctx, parent, label, x, y, values, width,
        function()
            local group = GFReadGroup(scope, groupKey)
            local value = group[key] or defaultValue
            if key == "filterToken" then value = CanonicalGroupFilterValue(value, groupKey) end
            if key == "sortMethod" then value = NormalizeAuraSortMethodForLane(groupKey, value) end
            return value
        end,
        function(v)
            local value = v or defaultValue
            if key == "filterToken" then value = CanonicalGroupFilterValue(value, groupKey) end
            if key == "sortMethod" then value = NormalizeAuraSortMethodForLane(groupKey, value) end
            GFWriteGroupValue(scope, groupKey, key, value, mode or "visual")
            if afterSet then afterSet(value) end
        end,
        controlMeta or AuraControlMeta(ctx, "group-style.lane." .. AuraCatalogToken(groupKey, "lane") .. "." .. AuraCatalogToken(key)))
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
    -- Match the full Unit Preview: the swipe must sort above the icon rather
    -- than sharing its otherwise undefined ARTWORK ordering.
    f.swipe = f:CreateTexture(nil, "ARTWORK", nil, 1)
    f.swipe:SetPoint("TOPLEFT", f, "TOP", 0, -1)
    f.swipe:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    f.swipe:SetTexture(TEX_W8)
    f.swipe:SetVertexColor(0, 0, 0, 0.58)
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
function M.ResolveAuraStylePreviewIconShape(scope, requested, effective)
    local portraitShape
    if scope ~= "shared" then
        if IsGroupScope(scope) then
            local kind = GroupScopeKinds(scope)
            local conf = GroupConf(kind)
            portraitShape = conf and conf.portraitShape or "SQUARE"
        else
            local conf = type(M.GetUnitDB) == "function" and M.GetUnitDB(scope) or nil
            portraitShape = conf and conf.portraitShape or "SQUARE"
        end
    end
    if type(A3.ResolveAuraIconShape) == "function" then
        return A3.ResolveAuraIconShape(requested or effective, portraitShape)
    end
    return effective or requested or "RECTANGLE"
end
local function ApplySharedAppearanceStyleToPreview(cfg, kind)
    if kind ~= "debuff" and kind ~= "playerDefensives" and kind ~= "targetDots" then kind = "buff" end
    if type(Model.ReadSharedAppearanceBool) == "function" then
        cfg.styleBorderEnabled = Model.ReadSharedAppearanceBool(kind, "styleBorderEnabled", false)
        cfg.styleShadowEnabled = Model.ReadSharedAppearanceBool(kind, "styleShadowEnabled", false)
    end
    cfg.styleBorderStyle = type(Model.ReadSharedAppearanceBorderStyle) == "function"
        and Model.ReadSharedAppearanceBorderStyle(kind) or "SOLID"
    if type(Model.ReadSharedAppearanceNumber) == "function" then
        cfg.styleBorderThickness = Model.ReadSharedAppearanceNumber(kind, "styleBorderThickness", 1, 1, 8)
        cfg.styleShadowSize = Model.ReadSharedAppearanceNumber(kind, "styleShadowSize", 4, 1, 16)
    end
    if type(Model.ReadSharedAppearanceValue) == "function" then
        local bc = Model.ReadSharedAppearanceValue(kind, "styleBorderColor", nil)
        cfg.styleBorderColor = type(bc) == "table" and bc or nil
        local sc = Model.ReadSharedAppearanceValue(kind, "styleShadowColor", nil)
        cfg.styleShadowColor = type(sc) == "table" and sc or nil
    end
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
        iconShape = "RECTANGLE",
    }
    local appearanceKind = lane == "debuff" and "debuff" or "buff"
    ApplySharedAppearanceStyleToPreview(cfg, appearanceKind)
    if isGroup then
        local group = GFReadGroup(scope, lane or "debuff")
        local root = GFReadRoot(scope)
        cfg.iconZoom = tonumber(group.iconZoom) or tonumber(root and root.iconZoom) or 100
        local requestedIconShape = type(Model.ReadSharedAppearanceIconShape) == "function"
            and Model.ReadSharedAppearanceIconShape(appearanceKind) or "RECTANGLE"
        cfg.iconShape = M.ResolveAuraStylePreviewIconShape(scope, requestedIconShape, requestedIconShape)
        local iconScale = min(300, max(20, AccessibleNumber(group.iconScale, 100))) / 100
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
        -- Gap is per lane like Size and Per row; only the laneless preview
        -- (shared style workbench) falls back to the unit-wide value.
        if lane == "buff" or lane == "debuff" then
            cfg.spacing = tonumber(runtimePreview and runtimePreview[lane .. "Spacing"])
                or Model.ReadLaneSpacing(readScope, lane)
        else
            cfg.spacing = tonumber(runtimePreview and runtimePreview.spacing) or Model.ReadNumber(readScope, "spacing", 2, 0, 12)
        end
        cfg.iconZoom = lane and Model.ReadLaneStyleNumber(readScope, lane, "iconZoom", 100, 100, 200)
            or Model.ReadNumber(readScope, "iconZoom", 100, 100, 200)
        local configuredIconShape = type(Model.ReadSharedAppearanceIconShape) == "function"
            and Model.ReadSharedAppearanceIconShape(appearanceKind) or "RECTANGLE"
        local requestedIconShape = lane and runtimePreview
            and (lane == "buff" and runtimePreview.buffRequestedIconShape or runtimePreview.debuffRequestedIconShape)
            or configuredIconShape
        local effectiveIconShape = lane and runtimePreview
            and (lane == "buff" and runtimePreview.buffIconShape or runtimePreview.debuffIconShape)
            or configuredIconShape
        cfg.iconShape = M.ResolveAuraStylePreviewIconShape(readScope, requestedIconShape, effectiveIconShape)
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
    cfg.stackSize = max(7, tonumber(cfg.stackSize) or 10)
    cfg.cooldownSize = max(7, tonumber(cfg.cooldownSize) or 9)
    cfg.cooldownDecimalSeconds = min(30, max(0, tonumber(cfg.cooldownDecimalSeconds) or 3))
    cfg.durationBarHeight = min(max(1, tonumber(cfg.durationBarHeight) or 2), max(1, cfg.size or 24))
    cfg.durationBarDisplay = cfg.durationBarDisplay == "OVERLAY" and "OVERLAY" or "BAR_ONLY"
    cfg.durationBarPosition = cfg.durationBarPosition == "TOP" and "TOP" or "BOTTOM"
    cfg.durationBarDirection = cfg.durationBarDirection == "ELAPSED" and "ELAPSED" or "REMAINING"
    return cfg
end
local function ReadSharedSpecialAuraPreviewConfig(container, width, height)
    local playerDefensives = container == "playerDefensives"
    local cfg = ReadMiniAuraPreviewConfig("shared", playerDefensives and "buff" or "debuff", width, height)
    -- Appearance previews never read a UnitFrame's deep Style. They show only
    -- the global theme for this Aura product on stable dummy geometry.
    cfg.actualSize, cfg.size = 32, 32
    cfg.spacing, cfg.perRow, cfg.maxIcons, cfg.growth = 4, 4, 4, "RIGHTDOWN"
    cfg.iconShape = type(Model.ReadSharedAppearanceIconShape) == "function"
        and Model.ReadSharedAppearanceIconShape(container) or cfg.iconShape
    ApplySharedAppearanceStyleToPreview(cfg, container)
    cfg.pandemicEnabled = false
    cfg.previewTextures = {}
    local entries = {}
    if playerDefensives then
        if type(Model.PlayerDefensivePreviewEntries) == "function" then
            entries = Model.PlayerDefensivePreviewEntries() or {}
        end
    elseif type(Model.TargetDotValues) == "function" then
        entries = Model.TargetDotValues() or {}
    end
    for i = 1, #entries do
        local entry = entries[i]
        if type(entry) == "table" and entry.header ~= true and entry.icon then
            cfg.previewTextures[#cfg.previewTextures + 1] = entry.icon
            if #cfg.previewTextures >= 4 then break end
        end
    end
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
    local headerH = T.Space("xxl", 32) + T.Space("optical", 2)
    local footerH = T.Space("xxl", 32) - T.Space("optical", 2)
    local contentHost = box
    local zoomPan = type(opts.zoomPan) == "table" and opts.zoomPan or nil
    if opts.focused == true then
        box._msuf2PreviewSurfaceFamily = "aura"
        if PreviewHelpers.ApplyPreviewChrome then PreviewHelpers.ApplyPreviewChrome(box, "canvas", T) end
        if box.SetClipsChildren then box:SetClipsChildren(true) end
        contentHost = CreateFrame("Frame", nil, box)
        contentHost:SetPoint("TOPLEFT", box, "TOPLEFT", innerPad, -headerH)
        contentHost:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -innerPad, footerH)
        if contentHost.SetClipsChildren then contentHost:SetClipsChildren(true) end
        box._msufAuraPreviewViewport = contentHost
    end
    local titleLabel = W.LabelAt(box, opts.title or "Sample Preview", innerPad, -innerPad, 240, "GameFontNormalSmall", T.colors.text)
    local meta
    if opts.focused == true then
        meta = T.Font(box, "GameFontDisableSmall", "", T.colors.muted)
        meta:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", innerPad, T.Space("sm", 8))
        meta:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -innerPad, T.Space("sm", 8))
        meta:SetJustifyH("LEFT")
        if meta.SetMaxLines then meta:SetMaxLines(1) end
        if meta.SetWordWrap then meta:SetWordWrap(false) end
        box._msufAuraPreviewMeta = meta
    end
    local icons = {}
    local iconCapacity = opts.focused == true and 0 or min(14, max(1, tonumber(opts.iconCapacity) or 14))
    for i = 1, iconCapacity do icons[i] = CreateAuraPreviewIcon(contentHost) end
    local function EnsureIconCapacity(count)
        count = min(opts.focused == true and 80 or iconCapacity, max(0, Round(count)))
        for i = #icons + 1, count do icons[i] = CreateAuraPreviewIcon(contentHost) end
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
        if type(A3.ApplyIconStylePreview) == "function" then
            local texture = B and cfg.styleBorderStyle and B.Resolve(cfg.styleBorderStyle) or nil
            local c, sc = cfg.styleBorderColor, cfg.styleShadowColor
            A3.ApplyIconStylePreview(icon, not barOnly and {
                borderEnabled = cfg.styleBorderEnabled == true,
                borderTexture = texture,
                borderEdge = B and B.EdgeSize(cfg.styleBorderStyle, cfg.styleBorderThickness or 1) or 1,
                borderPlacement = B and B.Placement(cfg.styleBorderStyle) or "outer",
                borderThickness = cfg.styleBorderThickness or 1,
                borderR = c and c[1] or 0, borderG = c and c[2] or 0,
                borderB = c and c[3] or 0, borderA = c and c[4] or 1,
                shadowEnabled = cfg.styleShadowEnabled == true,
                shadowSize = cfg.styleShadowSize or 4,
                shadowR = sc and sc[1] or 0, shadowG = sc and sc[2] or 0,
                shadowB = sc and sc[3] or 0, shadowA = sc and sc[4] or 0.8,
            } or nil, cfg.size, cfg.iconShape)
            return
        end
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
        if type(A3.ApplyAuraIconShape) == "function" then
            cfg.iconShape = A3.ApplyAuraIconShape(icon, cfg.iconShape, nil, icon.bg, icon.icon, icon.swipe)
        end
        icon.bg:SetShown(not barOnly)
        icon.icon:SetShown(not barOnly)
        ApplyPreviewIconStyle(icon, cfg, barOnly)
        local r, g, b = isBuffIcon and 0.20 or 0.78, isBuffIcon and 0.72 or 0.20, isBuffIcon and 0.42 or 0.24
        local borderAtlas = (not barOnly and not isBuffIcon) and DEBUFF_TYPE_BORDER_PREVIEW_ATLAS[cfg.debuffBorderMode] or nil
        local showPreviewEdges = isBuffIcon == true and not barOnly and cfg.iconShape == "RECTANGLE"
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
        if borderAtlas and type(A3.ApplyAuraDispelPreview) == "function" then
            A3.ApplyAuraDispelPreview(icon.dispelBorder, icon, cfg.size, cfg.debuffBorderMode,
                cfg.iconShape, A3.PreviewDispelTypeForIndex(index))
        elseif borderAtlas and icon.dispelBorder.SetAtlas then
            local pad = type(A3.NativeAuraDispelBorderPadding) == "function"
                and A3.NativeAuraDispelBorderPadding(cfg.size)
                or max(1, floor((cfg.size / 6) + 0.5))
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
            local availableWidth = max(1, cfg.size - (inset * 2))
            -- This workbench is intentionally event-driven rather than animated.
            -- Give each sample aura a deterministic remaining fraction so the
            -- Remaining/Elapsed setting is still visible without an OnUpdate.
            local remainingFraction = max(0.18, 0.88 - (((index - 1) % 6) * 0.13))
            local fillFraction = cfg.durationBarDirection == "ELAPSED"
                and (1 - remainingFraction) or remainingFraction
            icon.durationBar:ClearAllPoints()
            icon.durationBar:SetHeight(cfg.durationBarHeight or 2)
            icon.durationBar:SetWidth(max(1, floor((availableWidth * fillFraction) + 0.5)))
            if cfg.durationBarPosition == "TOP" then
                icon.durationBar:SetPoint("TOPLEFT", icon, "TOPLEFT", inset, -inset)
            else
                icon.durationBar:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", inset, inset)
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
        if type(A3.ApplyPandemicVisual) == "function"
            and (opts.previewContainer == "targetDots" or icon._msufA3PandemicRegion) then
            A3.ApplyPandemicVisual(icon, cfg,
                opts.previewContainer == "targetDots" and cfg.pandemicEnabled == true and index == 1 and not barOnly)
        end
        icon:Show()
    end
    local function RefreshPreview()
        if AurasMenuCombatLocked() then return end
        if opts.focused == true and parent.IsShown and not parent:IsShown() then return end
        local previewScope = type(opts.getPreviewScope) == "function" and opts.getPreviewScope() or scope
        if not AURA_SCOPE_VALID[previewScope] then previewScope = scope end
        if opts.focused == true then
            local cfg = type(opts.readConfig) == "function"
                and opts.readConfig(previewScope, lane, width, height)
                or ReadMiniAuraPreviewConfig(previewScope, lane, width, height)
            -- Sample is a styling workbench, so a lane configured with Max=0
            -- still renders one dummy icon instead of looking broken. Live mode
            -- continues to mirror the actual disabled/empty lane exactly.
            local count = EnsureIconCapacity(max(1, cfg.maxIcons))
            local naturalSize = max(1, tonumber(cfg.actualSize) or tonumber(cfg.size) or 24)
            local naturalGap = max(0, tonumber(cfg.spacing) or 0)
            local boxW, boxH = width or 300, height or 104
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
            local fitScale = min(1, availableW / max(1, naturalW), availableH / max(1, naturalH))
            if zoomPan and zoomPan.Clamp then fitScale = zoomPan.Clamp(fitScale) end
            local scale = tonumber(box._manualZoom) or fitScale
            if zoomPan and zoomPan.Clamp then scale = zoomPan.Clamp(scale) end
            box._mockAutoScale, box._mockScale = fitScale, scale
            cfg.size = max(2, naturalSize * scale)
            cfg.spacing = naturalGap * scale
            cfg.stackSize = max(5, (tonumber(cfg.stackSize) or 10) * scale)
            cfg.cooldownSize = max(5, (tonumber(cfg.cooldownSize) or 9) * scale)
            cfg.durationBarHeight = max(1, (tonumber(cfg.durationBarHeight) or 2) * scale)
            cfg.styleBorderThickness = max(0.5, (tonumber(cfg.styleBorderThickness) or 1) * scale)
            cfg.styleShadowSize = max(0.5, (tonumber(cfg.styleShadowSize) or 4) * scale)
            local totalW = columns * cfg.size + max(0, columns - 1) * cfg.spacing
            local totalH = rows * cfg.size + max(0, rows - 1) * cfg.spacing
            local startX = (availableW - totalW) * 0.5
            local startY = -((availableH - totalH) * 0.5)
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
                    icon:SetPoint("TOPLEFT", contentHost, "TOPLEFT",
                        startX + col * (cfg.size + cfg.spacing),
                        startY - row * (cfg.size + cfg.spacing))
                    RenderPreviewIcon(icon, i, cfg, lane == "buff", false)
                else
                    HidePreviewIcon(icon)
                end
            end
            local label = ScopeLabel(previewScope)
            titleLabel:SetText(M.Format("%s Sample Preview", Tr(label)))
            if type(opts.getSampleMeta) == "function" then
                meta:SetText(opts.getSampleMeta(cfg, previewScope) or "")
            else
                meta:SetText(label .. " / " .. tostring(Round(cfg.actualSize or cfg.size or 0)) .. "px")
            end
            if zoomPan and zoomPan.UpdateControls then zoomPan.UpdateControls(box) end
            return
        end
        if meta then meta:SetText("") end
        local cfg = type(opts.readConfig) == "function"
            and opts.readConfig(previewScope, lane, width, height)
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
                local isBuffIcon = lane and lane == "buff" or (not lane and i <= 7)
                RenderPreviewIcon(icon, i, cfg, isBuffIcon, false)
            else
                HidePreviewIcon(icon)
            end
        end
    end
    box.Refresh = RefreshPreview
    M.TrackRefresh(ctx, RefreshPreview)
    return box, RefreshPreview
end
local function BuildAuraStylePreviewWorkbench(ctx, b, scope, lane, previewContainer)
    local rowY = -40
    local panelY = -68
    local panelH = 100
    local sectionH = 180
    local section, _, fixedPreview = W.FixedPreviewSection(ctx, b, {
        title = "Preview",
        height = sectionH,
    })
    local width = section._msuf2Width or b.width or 720
    local pad = T.Space("xl", 24)
    local previewLabel = previewContainer == "playerDefensives" and "Player Defensives"
        or previewContainer == "targetDots" and "Dots on Target"
        or LanePlural(previewContainer or lane)
    W.LabelAt(section, M.Format("Shared Preview - %s", Tr(previewLabel)), pad, rowY,
        width - (pad * 2), "GameFontNormalSmall", T.colors.accent)

    local refreshPreview
    local zoomPan = M.AuraStylePreviewZoomPan
    if type(zoomPan) ~= "table" then
        zoomPan = {}
        M.AuraStylePreviewZoomPan = zoomPan
    end
    if type(zoomPan.SetZoom) ~= "function" and PreviewHelpers.InstallZoomPan then
        PreviewHelpers.InstallZoomPan(zoomPan, {
            configureTableOnly = true,
            readoutField = "zoomReadout",
            fitButtonTextPath = { "zoomFitButton", "fs" },
            defaultReason = "AURA_STYLE_PREVIEW_ZOOM",
            stepReason = "AURA_STYLE_PREVIEW_ZOOM_STEP",
            themeButton = true,
            buttonTextureKey = "TEX_W8",
            buttonFontField = "fs",
        })
    end
    if zoomPan.Configure then zoomPan.Configure({ T = T, TR = Tr, TEX_W8 = TEX_W8 }) end
    local panelW = width - (pad * 2)
    local box
    local specialPreview = previewContainer == "playerDefensives" or previewContainer == "targetDots"
    local previewLane = previewContainer == "playerDefensives" and "buff"
        or previewContainer == "targetDots" and "debuff" or lane
    box, refreshPreview = BuildMiniAuraPreview(ctx, section, scope, pad, panelY, panelW, panelH, previewLane, {
        focused = true,
        zoomPan = zoomPan,
        previewContainer = previewContainer,
        readConfig = specialPreview and function(_, _, configWidth, configHeight)
            return ReadSharedSpecialAuraPreviewConfig(previewContainer, configWidth, configHeight)
        end or nil,
        getSampleMeta = function(cfg)
            local swipe = cfg.cooldownSwipeReverse == true and "Reverse swipe" or "Default swipe"
            local owner = previewContainer == "playerDefensives" and "Shared Player Defensive theme"
                or previewContainer == "targetDots" and "Shared Dots on Target theme"
                or "Global Aura theme"
            return tostring(Round(cfg.actualSize or cfg.size or 0)) .. "px / " .. swipe .. " / " .. owner
        end,
    })
    if box then box.Refresh = refreshPreview end
    if box then
        if PreviewHelpers.BuildZoomBar and type(zoomPan.SetZoom) == "function" then
            local zoomBar = PreviewHelpers.BuildZoomBar(box, box, {
                width = 200,
                texture = TEX_W8,
                T = T,
                M = M,
                W = W,
                themeReadout = true,
                CreateZoomButton = zoomPan.CreateButton,
                Tr = Tr,
                StepZoom = zoomPan.Step,
                SetZoom = zoomPan.SetZoom,
                fitReason = "AURA_STYLE_PREVIEW_ZOOM_FIT",
                oneReason = "AURA_STYLE_PREVIEW_ZOOM_1TO1",
                helpTitle = "Aura Preview Zoom",
                helpLines = {
                    Tr("Use - / + or Ctrl + mouse wheel to zoom."),
                    Tr("Fit shows the complete aura layout."),
                    Tr("1:1 shows the configured aura pixel size."),
                    Tr("Zoom changes only this preview, not your Aura settings."),
                },
            })
            if zoomBar then
                zoomBar:ClearAllPoints()
                zoomBar:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -T.Space("md", 12), T.Space("xs", 4) + 2)
                local backgroundButton = box.previewBackgroundButton
                if backgroundButton then
                    backgroundButton:ClearAllPoints()
                    backgroundButton:SetPoint("RIGHT", zoomBar, "LEFT", -T.Space("xs", 4), 0)
                    local meta = box._msufAuraPreviewMeta
                    if meta then
                        meta:ClearAllPoints()
                        meta:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", T.Space("md", 12), T.Space("sm", 8))
                        meta:SetPoint("BOTTOMRIGHT", backgroundButton, "BOTTOMLEFT", -T.Space("sm", 8), 0)
                    end
                end
                if PreviewHelpers.BindPreviewWheel then
                    PreviewHelpers.BindPreviewWheel(box._msufAuraPreviewViewport, box, box._msuf2PreviewZoomWheel)
                end
            end
            if zoomPan.UpdateControls then zoomPan.UpdateControls(box) end
        end
    end
    local pinnedPreviewOpts
    if box and W.AttachPinnedPreview then
        pinnedPreviewOpts = {
            stateKey = "auraStylePreview",
            pageKey = ctx and ctx.key,
            wrapper = ctx and ctx.wrapper,
        }
        W.AttachPinnedPreview(section, box, pinnedPreviewOpts)
    end
    local previewShowSerial = 0
    local function RefreshVisibleAuraPreview()
        if type(refreshPreview) ~= "function" then return end
        if ctx and ctx.key and M.activeKey and M.activeKey ~= ctx.key then return end
        if ctx and ctx.wrapper and ctx.wrapper.IsShown and not ctx.wrapper:IsShown() then return end
        if section.IsShown and not section:IsShown() then return end
        if box and pinnedPreviewOpts then
            -- Navigating away runs ReleasePinnedPreviews: it drops the box's
            -- ownership record and hides the box. A cached re-entry skips the
            -- page build, so nothing re-attaches or shows it; this page has no
            -- expander whose Open() would rescue it either. Reclaim both here,
            -- on the page-activation refresh that only runs while the page owns
            -- the docked section.
            if not box._msuf2PinnedPreviewRecord then
                W.AttachPinnedPreview(section, box, pinnedPreviewOpts)
            end
            if box.IsShown and not box:IsShown() then box:Show() end
        end
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
    -- Fixed under the Aura scope/navigation stack; styling controls scroll below.
    if fixedPreview then fixedPreview.onActivate = QueueVisibleAuraPreview end
    return refreshPreview
end
local function BuildUnitStyle(ctx, b, scope, options)
    options = type(options) == "table" and options or nil
    local embeddedUnitPreview = options and options.embeddedUnitPreview == true
    local appearanceGlobalsOnly = options and options.appearanceGlobalsOnly == true
    local previewContainer = options and options.previewContainer
    local appearanceKind = previewContainer or CurrentLane("auraStyleGFLane", "debuff")
    local unit = scope == "appearance" and "shared" or scope
    local lane = CurrentLane("auraStyleGFLane", "debuff")
    local styleCatalogLane = appearanceGlobalsOnly and appearanceKind or lane
    local styleControls = {}
    local refreshMiniPreview
    local refreshDurationBarSummary
    local function RefreshStylePreview()
        if refreshMiniPreview then
            RefreshMiniAuraPreviewNow(refreshMiniPreview)
        elseif embeddedUnitPreview then
            local refreshOwnedPreview = ctx and ctx._msuf2RefreshUnitPreview
            if type(refreshOwnedPreview) == "function" then
                refreshOwnedPreview("AURAS3_UNIT_STYLE_DUMMY")
            elseif type(_G.MSUF_UFPreview_RequestRefresh) == "function" then
                _G.MSUF_UFPreview_RequestRefresh("AURAS3_UNIT_STYLE_DUMMY")
            end
        end
    end
    local function FlushStyleApply()
        local apply = M.ApplyService or _G.MSUF_Menu2_ApplyService
        if apply and type(apply.Flush) == "function" then apply.Flush() end
    end
    local function ReadScopeBool(key, defaultValue)
        if appearanceGlobalsOnly and type(Model.ReadSharedAppearanceBool) == "function" then
            return Model.ReadSharedAppearanceBool(appearanceKind, key, defaultValue)
        end
        if type(Model.ReadLaneStyleBool) == "function" then return Model.ReadLaneStyleBool(unit, lane, key, defaultValue) end
        if type(Model.ReadBool) == "function" then return Model.ReadBool(unit, key, defaultValue) end
        return Model.ReadSharedBool(key, defaultValue)
    end
    local function WriteScopeBool(key, value)
        if appearanceGlobalsOnly and type(Model.WriteSharedAppearanceBool) == "function" then
            Model.WriteSharedAppearanceBool(appearanceKind, key, value)
        elseif type(Model.WriteLaneStyleBool) == "function" then
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
        if appearanceGlobalsOnly and type(Model.ReadSharedAppearanceNumber) == "function" then
            return Model.ReadSharedAppearanceNumber(appearanceKind, key, defaultValue, minValue, maxValue)
        end
        if type(Model.ReadLaneStyleNumber) == "function" then return Model.ReadLaneStyleNumber(unit, lane, key, defaultValue, minValue, maxValue) end
        return Model.ReadNumber(unit, key, defaultValue, minValue, maxValue)
    end
    local function WriteScopeNumber(key, value, minValue, maxValue)
        if appearanceGlobalsOnly and type(Model.WriteSharedAppearanceNumber) == "function" then
            Model.WriteSharedAppearanceNumber(appearanceKind, key, value, minValue, maxValue)
        elseif type(Model.WriteLaneStyleNumber) == "function" then
            Model.WriteLaneStyleNumber(unit, lane, key, value, minValue, maxValue)
        else
            Model.WriteNumber(unit, key, value, minValue, maxValue)
        end
    end
    local function ReadScopeIconShape()
        if appearanceGlobalsOnly and type(Model.ReadSharedAppearanceIconShape) == "function" then
            return Model.ReadSharedAppearanceIconShape(appearanceKind)
        end
        local appearanceKind = lane == "debuff" and "debuff" or "buff"
        local value = type(Model.ReadSharedAppearanceIconShape) == "function"
            and Model.ReadSharedAppearanceIconShape(appearanceKind) or "RECTANGLE"
        return type(A3.NormalizeAuraIconShape) == "function" and A3.NormalizeAuraIconShape(value) or value
    end
    local function WriteScopeIconShape(value)
        if appearanceGlobalsOnly and type(Model.WriteSharedAppearanceIconShape) == "function" then
            Model.WriteSharedAppearanceIconShape(appearanceKind, value or "RECTANGLE")
            return
        end
        -- Icon Shape belongs exclusively to the global Appearance product.
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
    local function BindStyleSwitch(parent, label, x, y, width, key, defaultValue, reason, afterSet)
        return AddStyleControl(BindSwitch(ctx, parent, label, x, y, width,
            function() return ReadScopeBool(key, defaultValue) end,
            function(v)
                WriteScopeBool(key, v)
                ApplyUnit(ctx, unit, reason)
                -- Switches are discrete writes. Compile/apply the new value
                -- before repainting so Menu and Edit Mode observe one state.
                -- ApplyService itself defers this flush during combat.
                FlushStyleApply()
                RefreshStylePreview()
                if type(afterSet) == "function" then afterSet() end
            end,
            AuraControlMeta(ctx, "style.lane." .. AuraCatalogToken(lane) .. "." .. AuraCatalogToken(key))))
    end
    local function BindStyleDropdown(parent, label, x, y, values, width, getValue, setValue, reason, afterSet)
        return AddStyleControl(BindDropdown(ctx, parent, label, x, y, values, width,
            getValue,
            function(v)
                setValue(v)
                ApplyUnit(ctx, unit, reason)
                FlushStyleApply()
                RefreshStylePreview()
                if type(afterSet) == "function" then afterSet() end
            end,
            AuraControlMeta(ctx, "style.lane." .. AuraCatalogToken(styleCatalogLane) .. "." .. AuraCatalogToken(reason))))
    end
    local function BindStyleSlider(parent, label, x, y, minVal, maxVal, step, width, key, defaultValue, readMin, readMax, writeMin, writeMax, reason, afterSet)
        readMin, readMax = readMin or minVal, readMax or maxVal
        writeMin, writeMax = writeMin or readMin, writeMax or readMax
        return AddStyleControl(BindSlider(ctx, parent, label, x, y, minVal, maxVal, step, width,
            function() return ReadScopeNumber(key, defaultValue, readMin, readMax) end,
            function(v)
                WriteScopeNumber(key, v, writeMin, writeMax)
                ApplyUnit(ctx, unit, reason)
                RefreshStylePreview()
                if type(afterSet) == "function" then afterSet() end
            end,
            AuraControlMeta(ctx, "style.lane." .. AuraCatalogToken(lane) .. "." .. AuraCatalogToken(key))))
    end
    local function BodyWidth(body)
        return body and (body._msuf2Width or body.GetWidth and body:GetWidth()) or b.width or 720
    end
    local baseId = "aura_style_" .. tostring(scope or "unit") .. "_" .. lane

    if not embeddedUnitPreview then
        refreshMiniPreview = BuildAuraStylePreviewWorkbench(ctx, b, unit, lane, previewContainer)
    end

    local frameBasics
    local stealableStyleControl
    if not appearanceGlobalsOnly then
        local stealableLane = lane == "buff" and unit ~= "player"
        frameBasics = b:CollapsibleSection(baseId .. "_frame_basics", "Frame Basics", stealableLane and 228 or 194, true)
        local basicsWidth = BodyWidth(frameBasics)
        local basicsGap = 10
        local basicsCol = max(180, floor((basicsWidth - 48 - basicsGap) / 2))
        local basicsRightX = 24 + basicsCol + basicsGap
        BindStyleSlider(frameBasics, "Icon Zoom (%)", 24, -48, 100, 200, 1, basicsCol,
            "iconZoom", 100, 100, 200, 100, 200, "AURAS3_ICON_ZOOM")
        BindStyleSlider(frameBasics, "Lane Padding", basicsRightX, -48, 0, 16, 1, basicsCol,
            "stylePadding", 0, 0, 16, 0, 16, "AURAS3_LANE_PADDING")
        AddAuraTooltipHelp(BindStyleSwitch(frameBasics, "Show Tooltip", 24, -106, basicsCol,
            "showTooltip", true, "AURAS3_TOOLTIP"))
        BindStyleSwitch(frameBasics, "Show Cooldown Text", basicsRightX, -106, basicsCol,
            "showCooldownText", true, "AURAS3_SHOW_COOLDOWN_TEXT")
        BindStyleSwitch(frameBasics, "Show Cooldown Swipe", 24, -140, basicsCol,
            "showCooldownSwipe", true, "AURAS3_SHOW_COOLDOWN_SWIPE")
        if stealableLane then
            local stealableEnabled = BindStyleSwitch(frameBasics, "Mark Stealable Buffs", basicsRightX, -140,
                basicsCol, "showStealable", false, "AURAS3_STEALABLE_MARKER")
            stealableStyleControl = BindStyleDropdown(frameBasics, "Stealable Marker Style", basicsRightX, -174,
                M.AURA_STEALABLE_STYLE_VALUES, basicsCol,
                function()
                    return type(Model.ReadLaneStyleString) == "function"
                        and Model.ReadLaneStyleString(unit, lane, "stealableStyle", "BORDER_ICON") or "BORDER_ICON"
                end,
                function(value)
                    if type(Model.WriteLaneStyleString) == "function" then
                        Model.WriteLaneStyleString(unit, lane, "stealableStyle", value or "BORDER_ICON")
                    end
                end,
                "AURAS3_STEALABLE_MARKER_STYLE")
            AddTooltip(stealableEnabled, "Native stealable marker",
                "Uses Blizzard's 12.1 AuraButton stealable filter. It adds no MSUF aura scan, ticker, or OnUpdate.")
            M.TrackRefresh(ctx, function()
                W.SetControlEnabled(stealableStyleControl, ReadScopeBool("showStealable", false))
            end)
        end
        if lane == "debuff" then
            BindStyleDropdown(frameBasics, "Dispel-type Border", basicsRightX, -140,
                type(Model.DebuffTypeBorderModeValues) == "function" and Model.DebuffTypeBorderModeValues() or DEBUFF_TYPE_BORDER_MODE_VALUES,
                basicsCol, ReadScopeDebuffBorderMode, WriteScopeDebuffBorderMode, "AURAS3_DEBUFF_TYPE_BORDER_MODE")
        end
    end

    if appearanceGlobalsOnly then
        local appearanceShape = b:CollapsibleSection(baseId .. "_appearance_shape", "Icon Shape", 112, false)
        local ssw = BodyWidth(appearanceShape)
        local appearanceLabel = previewContainer == "playerDefensives" and "Player Defensives"
            or previewContainer == "targetDots" and "Dots on Target" or LaneTitle(lane)
        local shape = BindStyleDropdown(appearanceShape, M.Format("%s Icon Shape", Tr(appearanceLabel)), 24, -48,
            M.AURA_ICON_SHAPE_VALUES, ssw - 48, ReadScopeIconShape, WriteScopeIconShape, "AURAS3_ICON_SHAPE")
        AddTooltip(shape, "Global icon shape",
            "Applies to every UnitFrame and GroupFrame icon of this Aura type. Spell Icons use the Buff appearance.")
    end

    local iconStyleGates = { border = {}, shadow = {}, Apply = function() end }
    if appearanceGlobalsOnly then
    -- Border and shadow are global for the selected Aura product. There is no
    -- frame-level opt-out; UF/GF Style owns only the remaining local details.
    -- Detail controls gray out while their master toggle is off, matching the
    -- rest of the aura style pages. Collected here so both the page refresher
    -- and the icon-style writes can re-apply the gate without a page rebuild.
    local iconStyle = b:CollapsibleSection(baseId .. "_icon_style", "Icon Border & Shadow", 278, false)
    local isw = BodyWidth(iconStyle)
    local styleCol = max(140, floor((isw - 68) / 2))
    local styleGap = 10
    -- Re-runs the master-toggle gate. Assigned once the controls below exist;
    -- called from every icon-style write so flipping a toggle grays its detail
    -- controls immediately instead of waiting for a page rebuild.
    function iconStyleGates.Apply(editable)
        if type(W.SetControlsEnabled) ~= "function" then return end
        if editable == nil then
            editable = true
        end
        local function On(key)
            return editable and ReadScopeBool(key, false) == true
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
        if type(Model.WriteSharedAppearanceValue) == "function" then
            Model.WriteSharedAppearanceValue(appearanceKind, key, value)
        end
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
        local c = type(Model.ReadSharedAppearanceValue) == "function"
            and Model.ReadSharedAppearanceValue(appearanceKind, colorKey, defaultColor) or defaultColor
        if type(c) ~= "table" then c = defaultColor end
        return c
    end
    local function IconStyleSwitch(label, y, key, reason)
        return AddStyleControl(BindSwitch(ctx, iconStyle, label, 24, y, styleCol,
            function() return ReadScopeBool(key, false) == true end,
            function(v) IconStyleWrite(key, v == true, reason) end,
            AuraControlMeta(ctx, "style.appearance.icon-style." .. AuraCatalogToken(key))))
    end
    local function IconStyleSlider(label, col, y, minVal, maxVal, key, defaultValue, reason)
        local slider
        slider = AddStyleControl(BindSlider(ctx, iconStyle, label, 24 + col * (styleCol + styleGap), y,
            minVal, maxVal, 1, styleCol,
            function()
                return ReadScopeNumber(key, defaultValue, minVal, maxVal)
            end,
            function(value)
                IconStyleWrite(key, tonumber(value) or defaultValue, reason, true)
                QueueIconStyleApply(slider, reason)
            end,
            AuraControlMeta(ctx, "style.appearance.icon-style." .. AuraCatalogToken(key))))
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
            AuraControlMeta(ctx, "style.appearance.icon-style." .. AuraCatalogToken(colorKey) .. "-alpha")))
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
        function() return Model.ReadSharedAppearanceBorderStyle(appearanceKind) end,
        function(v)
            Model.WriteSharedAppearanceBorderStyle(appearanceKind, v)
            ApplyIconStyleRuntime("AURAS3_ICON_STYLE_BORDER")
            RefreshStylePreview()
        end,
        AuraControlMeta(ctx, "style.appearance.icon-style.border-style")))
    AddTooltip(borderStyleDropdown, "Icon border style",
        "Solid draws a crisp pixel ring around the icon. Soft Glow adds a halo, and Shadow shades the icon's own edges. The Blizzard entries and any LibSharedMedia border are drawn as edge art. Thickness scales the edge.")
    iconStyleGates.border[1] = borderStyleDropdown
    iconStyleGates.border[2] = IconStyleSlider("Border Thickness", 0, -122, 1, 8, "styleBorderThickness", 1, "AURAS3_ICON_STYLE_BORDER")
    iconStyleGates.border[3] = IconStyleAlphaSlider("Border Alpha (%)", 1, -122, "styleBorderColor", ICON_STYLE_BORDER_DEFAULT, "AURAS3_ICON_STYLE_BORDER_COLOR")
    IconStyleSwitch("Icon Shadow", -178, "styleShadowEnabled", "AURAS3_ICON_STYLE_SHADOW")
    iconStyleGates.shadow[1] = IconStyleSlider("Shadow Size", 0, -210, 1, 16, "styleShadowSize", 4, "AURAS3_ICON_STYLE_SHADOW")
    iconStyleGates.shadow[2] = IconStyleAlphaSlider("Shadow Alpha (%)", 1, -210, "styleShadowColor", ICON_STYLE_SHADOW_DEFAULT, "AURAS3_ICON_STYLE_SHADOW_COLOR")
    end

    if appearanceGlobalsOnly and (previewContainer == "buff" or previewContainer == "debuff") then
        local blizzardFrames = b:CollapsibleSection(baseId .. "_blizzard_aura_frames", "Blizzard Buff & Debuff Frames", 152, false)
        local bfw = BodyWidth(blizzardFrames)
        local function RefreshBlizzardAuraFrameBadge()
            if not W.SetCollapsibleBadges then return end
            local buffsHidden = type(Model.ReadHideBlizzardBuffFrame) == "function"
                and Model.ReadHideBlizzardBuffFrame() == true
            local debuffsHidden = type(Model.ReadHideBlizzardDebuffFrame) == "function"
                and Model.ReadHideBlizzardDebuffFrame() == true
            W.SetCollapsibleBadges(blizzardFrames, {{
                text = Tr(buffsHidden and "Buffs hidden" or "Buffs visible"),
                kind = buffsHidden and "accent" or "muted",
                showWhenClosed = true,
            }, {
                text = Tr(debuffsHidden and "Debuffs hidden" or "Debuffs visible"),
                kind = debuffsHidden and "accent" or "muted",
                showWhenClosed = true,
            }})
        end
        local hideBlizzardBuffs = BindSwitch(ctx, blizzardFrames, "Hide Blizzard Buff Frame", 24, -44, bfw - 48,
            function()
                return type(Model.ReadHideBlizzardBuffFrame) == "function"
                    and Model.ReadHideBlizzardBuffFrame() == true
            end,
            function(value)
                if type(Model.WriteHideBlizzardBuffFrame) == "function" then
                    Model.WriteHideBlizzardBuffFrame(value == true)
                end
                RefreshBlizzardAuraFrameBadge()
            end,
            AuraControlMeta(ctx, "style.appearance.blizzard-aura-frames.hide-buffs"))
        AddTooltip(hideBlizzardBuffs, "Blizzard Buff & Debuff Frames",
            "Hides Blizzard's player Buff Frame near the minimap.")
        local hideBlizzardDebuffs = BindSwitch(ctx, blizzardFrames, "Hide Blizzard Debuff Frame", 24, -84, bfw - 48,
            function()
                return type(Model.ReadHideBlizzardDebuffFrame) == "function"
                    and Model.ReadHideBlizzardDebuffFrame() == true
            end,
            function(value)
                if type(Model.WriteHideBlizzardDebuffFrame) == "function" then
                    Model.WriteHideBlizzardDebuffFrame(value == true)
                end
                RefreshBlizzardAuraFrameBadge()
            end,
            AuraControlMeta(ctx, "style.appearance.blizzard-aura-frames.hide-debuffs"))
        AddTooltip(hideBlizzardDebuffs, "Blizzard Buff & Debuff Frames",
            "Hides only Blizzard's normal Debuff icons near the minimap. Private Auras and Deadly Debuff warnings remain visible.")
        RefreshBlizzardAuraFrameBadge()
        M.TrackRefresh(ctx, RefreshBlizzardAuraFrameBadge)
    end

    if appearanceGlobalsOnly and previewContainer == "buff" then
        local nativeFlow = b:CollapsibleSection(baseId .. "_native_flow", "Native Aura Flow", 112, false)
        local nfw = BodyWidth(nativeFlow)
        local weaponEnchants = BindSwitch(ctx, nativeFlow, "Show Weapon Enchants on Player", 24, -44, nfw - 48,
            function() return Model.ReadSharedBool("showWeaponEnchants", false) end,
            function(value)
                Model.WriteSharedBool("showWeaponEnchants", value == true)
                RequestAuraRuntime("shared", "AURAS3_WEAPON_ENCHANTS")
                RefreshStylePreview()
            end,
            AuraControlMeta(ctx, "style.appearance.native-flow.weapon-enchants"))
        AddTooltip(weaponEnchants, "Native weapon enchant auras",
            "Adds Blizzard's temporary weapon-enchantment buttons to the Player Buff container. This is one shared setting and uses the native aura flow without an MSUF ticker or OnUpdate.")
        M.TrackRefresh(ctx, function()
            iconStyleGates.Apply(true)
            if W.SetCollapsibleBadges then
                W.SetCollapsibleBadges(nativeFlow, { {
                    text = Model.ReadSharedBool("showWeaponEnchants", false) and "Weapon Enchants On" or "Weapon Enchants Off",
                    kind = Model.ReadSharedBool("showWeaponEnchants", false) and "accent" or "muted",
                    showWhenClosed = true,
                } })
            end
        end)
    end
    if appearanceGlobalsOnly then return end

    local stack = b:CollapsibleSection(baseId .. "_stack", "Stack Count", 296, false)
    if W.AttachContextColorShortcut then
        W.AttachContextColorShortcut(stack, {
            title = M.Format("%s Stack Text Settings", Tr(LaneTitle(lane))),
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
            title = M.Format("%s Cooldown Text Settings", Tr(LaneTitle(lane))),
            historyLabel = "Aura cooldown text color",
            historySource = "menu:auras-cooldown-text-color",
            scopeTag = "Shared",
            note = AURA_SHARED_COLOR_NOTE,
            textSettings = {
                scope = "shared",
                unit = unit,
                kind = "aura",
                colorReferences = AURA_COOLDOWN_COLOR_REFERENCES,
                colorTitle = M.Format("%s Cooldown Colors", Tr(LaneTitle(lane))),
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

    local durationInline = (b.width or 720) >= 520
    -- Dropdown buttons sit 24 px below their labels and carry a soft edge/glow.
    -- Keep a real footer inside the body so that art cannot bleed into the next
    -- accordion header in either the inline or narrow stacked layout.
    local durationBar = b:CollapsibleSection(baseId .. "_duration_bar", "Duration Bar", durationInline and 220 or 332, false)
    W.AttachContextColorReferences(durationBar, AURA_DURATION_BAR_COLOR_REFERENCES, {
        title = M.Format("%s Duration Bar Color", Tr(LaneTitle(lane))),
        scopeTag = "Shared",
        note = AURA_SHARED_COLOR_NOTE,
    })
    local dbw = BodyWidth(durationBar)
    local durationChoiceWidth = durationInline and floor(((dbw - 48) - 20) / 3) or (dbw - 48)
    refreshDurationBarSummary = function()
        if not W.SetCollapsibleBadges then return end
        local enabled = ReadScopeBool("showDurationBar", false)
        W.SetCollapsibleBadges(durationBar, {{
            text = enabled and (tostring(Round(ReadScopeNumber("durationBarHeight", 2, 1, 16))) .. "px / " .. ChoiceLabel(DURATION_BAR_DISPLAY_VALUES, ReadScopeDurationBarDisplay(), "Bar Only") .. " / " .. ChoiceLabel(DURATION_BAR_POSITION_VALUES, ReadScopeDurationBarPosition(), "Bottom")) or "Off",
            kind = enabled and "accent" or "muted", showWhenClosed = true,
        }})
    end
    BindStyleSwitch(durationBar, "Show Duration Bar", 24, -48, dbw - 48, "showDurationBar", false, "AURAS3_DURATION_BAR", refreshDurationBarSummary)
    BindStyleSlider(durationBar, "Height", 24, -104, 1, 16, 1, dbw - 48, "durationBarHeight", 2, 1, 16, nil, nil, "AURAS3_DURATION_BAR_HEIGHT", refreshDurationBarSummary)
    AddTooltip(BindStyleDropdown(durationBar, "Display", 24, -162,
        type(Model.DurationBarDisplayValues) == "function" and Model.DurationBarDisplayValues() or DURATION_BAR_DISPLAY_VALUES,
        durationChoiceWidth, ReadScopeDurationBarDisplay, WriteScopeDurationBarDisplay, "AURAS3_DURATION_BAR_DISPLAY", refreshDurationBarSummary),
        "Duration bar display", "Bar Only hides the aura icon. Icon + Bar keeps the icon and draws the duration bar on it.")
    AddTooltip(BindStyleDropdown(durationBar, "Position", durationInline and (34 + durationChoiceWidth) or 24, durationInline and -162 or -220,
        type(Model.DurationBarPositionValues) == "function" and Model.DurationBarPositionValues() or DURATION_BAR_POSITION_VALUES,
        durationChoiceWidth, ReadScopeDurationBarPosition, WriteScopeDurationBarPosition, "AURAS3_DURATION_BAR_POSITION", refreshDurationBarSummary),
        "Duration bar position", "Places the duration bar at the top or bottom edge of the aura slot.")
    AddTooltip(BindStyleDropdown(durationBar, "Fill Mode", durationInline and (44 + (durationChoiceWidth * 2)) or 24, durationInline and -162 or -278,
        type(Model.DurationBarDirectionValues) == "function" and Model.DurationBarDirectionValues() or DURATION_BAR_DIRECTION_VALUES,
        durationChoiceWidth, ReadScopeDurationBarDirection, WriteScopeDurationBarDirection, "AURAS3_DURATION_BAR_DIRECTION", refreshDurationBarSummary),
        "Duration bar fill mode", "Remaining shrinks as the aura expires. Elapsed grows until the aura expires.")

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
    AddStyleControl(BindDropdown(ctx, frameEffect, "Effect", 24, -34, CUSTOM_FRAME_EFFECTS, few - 48,
        function() return tostring(ReadEffectValue("Type", "none")) end,
        function(value) WriteEffectValue("Type", value or "none", "AURAS3_LANE_FRAME_EFFECT") end,
        AuraControlMeta(ctx, "style.lane." .. AuraCatalogToken(lane) .. ".full-frame.type", nil,
            LaneFrameEffectAssistantContract(unit, lane, "type"))))
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
            LaneFrameEffectAssistantContract(unit, lane, "color")))
    -- BindColor remains the single command/history owner and automatically
    -- feeds the card's three-dot picker.  The duplicate inline swatch is hidden
    -- so Full-Frame colors have one visible entry point only.
    effectColor:Hide()
    if effectColor._msuf2Title then
        effectColor._msuf2Title:Hide()
        effectColor._msuf2Title._msuf2AlwaysHidden = true
    end
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
                LaneFrameEffectAssistantContract(unit, lane, suffix))))
    end
    EffectSlider("Opacity", 0, -96, 5, 100, 5, "Alpha", 0.80, "AURAS3_LANE_FRAME_EFFECT_ALPHA")
    EffectSlider("Layer (0-30)", 1, -96, 0, 30, 1, "Layer", 0, "AURAS3_LANE_FRAME_EFFECT_LAYER")
    EffectSlider("Thickness", 2, -96, 1, 16, 1, "Thickness", 2, "AURAS3_LANE_FRAME_EFFECT_THICKNESS")
    EffectSlider("Priority", 0, -150, 1, 10, 1, "Priority", 5, "AURAS3_LANE_FRAME_EFFECT_PRIORITY")

    M.TrackRefresh(ctx, function()
        -- Individual Style editors are always actionable. The first write to a
        -- formerly inherited lane activates its sparse per-frame override.
        local editable = true
        W.SetControlsEnabled(styleControls, true)
        if stealableStyleControl then
            W.SetControlEnabled(stealableStyleControl, editable and ReadScopeBool("showStealable", false))
        end
        -- Must come after the blanket pass above, which would otherwise
        -- re-enable detail controls whose master toggle is off.
        iconStyleGates.Apply(editable)
        if W.SetCollapsibleBadges then
            local function ToggleBadge(label, enabled)
                return { text = label .. (enabled and " On" or " Off"), kind = enabled and "accent" or "muted", showWhenClosed = true }
            end
            local frameBasicsBadges = {
                {
                    text = M.Format("Zoom %d%%", Round(ReadScopeNumber("iconZoom", 100, 100, 200))),
                    kind = "info", showWhenClosed = true,
                },
                ToggleBadge("Text", ReadScopeBool("showCooldownText", true)),
                ToggleBadge("Swipe", ReadScopeBool("showCooldownSwipe", true)),
                ToggleBadge("Tooltip", ReadScopeBool("showTooltip", true)),
            }
            if lane == "debuff" then
                local borderMode = ReadScopeDebuffBorderMode()
                frameBasicsBadges[#frameBasicsBadges + 1] = {
                    text = "Border " .. ChoiceLabel(DEBUFF_TYPE_BORDER_MODE_VALUES, borderMode, borderMode),
                    kind = borderMode == "OFF" and "muted" or "accent",
                    showWhenClosed = true,
                }
            elseif lane == "buff" then
                frameBasicsBadges[#frameBasicsBadges + 1] = ToggleBadge("Stealable", ReadScopeBool("showStealable", false))
            end
            if frameBasics then W.SetCollapsibleBadges(frameBasics, frameBasicsBadges) end

            local stackEnabled = ReadScopeBool("showStackCount", true)
            W.SetCollapsibleBadges(stack, {{
                text = stackEnabled and (tostring(Round(ReadScopeNumber("stackTextSize", 14, 6, 40))) .. "px / " .. AnchorLabel(type(Model.ReadLaneStackAnchor) == "function" and Model.ReadLaneStackAnchor(unit, lane) or Model.ReadStackAnchor(unit))) or "Off",
                kind = stackEnabled and "accent" or "muted", showWhenClosed = true,
            }})

            local cooldownEnabled = ReadScopeBool("showCooldownText", true)
            local decimal = Round(ReadScopeNumber("cooldownDecimalSeconds", 3, 0, 30))
            W.SetCollapsibleBadges(cooldown, {
                { text = cooldownEnabled and (tostring(Round(ReadScopeNumber("cooldownTextSize", 14, 6, 40))) .. "px / " .. AnchorLabel(ReadScopeCooldownAnchor()) .. " / " .. ChoiceLabel(COOLDOWN_SWIPE_DIRECTION_VALUES, ReadScopeSwipeDirection(), "Normal")) or "Off", kind = cooldownEnabled and "accent" or "muted", showWhenClosed = true },
                { text = decimal > 0 and M.Format("Decimals below %ds", decimal) or Tr("Whole seconds"), kind = "info", showWhenClosed = true },
            })

            refreshDurationBarSummary()

            local effectType = tostring(ReadEffectValue("Type", "none"))
            W.SetCollapsibleBadges(frameEffect, {{
                text = ChoiceLabel(CUSTOM_FRAME_EFFECTS, effectType, effectType),
                kind = effectType == "none" and "muted" or "accent", showWhenClosed = true,
            }})

        end
    end)
end

local function BuildUnitOrdering(ctx, b, unit, lane)
    lane = lane == "debuff" and "debuff" or "buff"
    local section = b:Section("Ordering", 156)
    local width = section and (section._msuf2Width or section.GetWidth and section:GetWidth()) or b.width or 720
    local function ReadSortMethod()
        local value = type(Model.ReadLaneStyleString) == "function"
            and Model.ReadLaneStyleString(unit, lane, "sortMethod", "DEFAULT") or "DEFAULT"
        return NormalizeAuraSortMethodForLane(lane, value)
    end
    local function ReadSortDirection()
        local reverse = false
        if type(Model.ReadLaneStyleBool) == "function" then
            reverse = Model.ReadLaneStyleBool(unit, lane, "sortReverse", false)
        elseif type(Model.ReadBool) == "function" then
            reverse = Model.ReadBool(unit, "sortReverse", false)
        end
        return reverse == true and "REVERSE" or "NORMAL"
    end
    local function ApplyOrdering(reason)
        ApplyUnit(ctx, unit, reason)
        local apply = M.ApplyService or _G.MSUF_Menu2_ApplyService
        if apply and type(apply.Flush) == "function" then apply.Flush() end
        local refreshOwnedPreview = ctx and ctx._msuf2RefreshUnitPreview
        if type(refreshOwnedPreview) == "function" then
            refreshOwnedPreview(reason)
        elseif type(_G.MSUF_UFPreview_RequestRefresh) == "function" then
            _G.MSUF_UFPreview_RequestRefresh(reason)
        end
    end
    local sortMethod = BindDropdown(ctx, section, "Sort By", 24, -48, AuraSortMethodValues(lane), width - 48,
        ReadSortMethod,
        function(value)
            value = NormalizeAuraSortMethodForLane(lane, value)
            if type(Model.WriteLaneStyleString) == "function" then
                Model.WriteLaneStyleString(unit, lane, "sortMethod", value)
            end
            ApplyOrdering("AURAS3_SORT_METHOD")
        end,
        AuraControlMetaAtVisiblePath(ctx,
            "style.lane." .. AuraCatalogToken(lane) .. "." .. AuraCatalogToken("AURAS3_SORT_METHOD"),
            "unit-workspace.lane." .. AuraCatalogToken(lane) .. ".ordering.sort-method"))
    AddTooltip(sortMethod, "Aura sorting", "Only relevant sorting methods are shown for buffs and debuffs.")
    local sortDirection = BindDropdown(ctx, section, "Order", 24, -104, AURA_SORT_DIRECTION_VALUES, width - 48,
        ReadSortDirection,
        function(value)
            if type(Model.WriteLaneStyleBool) == "function" then
                Model.WriteLaneStyleBool(unit, lane, "sortReverse", value == "REVERSE")
            elseif type(Model.WriteBool) == "function" then
                Model.WriteBool(unit, "sortReverse", value == "REVERSE")
            end
            ApplyOrdering("AURAS3_SORT_DIRECTION")
        end,
        AuraControlMetaAtVisiblePath(ctx,
            "style.lane." .. AuraCatalogToken(lane) .. "." .. AuraCatalogToken("AURAS3_SORT_DIRECTION"),
            "unit-workspace.lane." .. AuraCatalogToken(lane) .. ".ordering.sort-direction"))
    AddTooltip(sortDirection, "Aura sort order", "Reversed flips the complete priority order.")
end

local function BuildGroupStyle(ctx, b, scope, options)
    options = type(options) == "table" and options or nil
    local embeddedGroupPreview = options and options.embeddedGroupPreview == true
    local requestedLane = options and options.lane
    local lane = requestedLane == "externals" and "externals" or CurrentLane("auraStyleGFLane", "debuff")
    local refreshMiniPreview
    local refreshDurationBarSummary
    local function RefreshStylePreview()
        if refreshMiniPreview then
            RefreshMiniAuraPreviewNow(refreshMiniPreview)
        elseif embeddedGroupPreview then
            RefreshGFPreview()
        end
    end
    local function BodyWidth(body)
        return body and (body._msuf2Width or body.GetWidth and body:GetWidth()) or b.width or 720
    end
    local baseId = "aura_style_group_" .. tostring(scope or "group") .. "_" .. lane

    if not embeddedGroupPreview then
        refreshMiniPreview = BuildAuraStylePreviewWorkbench(ctx, b, scope, lane)
    end

    local frameBasics = b:CollapsibleSection(baseId .. "_frame_basics", "Frame Basics", lane == "debuff" and 194 or 146, true)
    local basicsWidth = BodyWidth(frameBasics)
    local basicsGap = 10
    local basicsCol = max(180, floor((basicsWidth - 48 - basicsGap) / 2))
    local basicsRightX = 24 + basicsCol + basicsGap
    BindGroupSlider(ctx, frameBasics, "Icon Zoom (%)", 24, -48, 100, 200, 1, basicsCol,
        scope, lane, "iconZoom", 100, "visual", RefreshStylePreview, {
            assistantDisposition = "dynamic",
            assistantDispositionReason = "Icon Zoom targets the selected Group scope's selected Aura Style lane.",
            assistantSettingKeys = GroupAssistantSettingKeys(scope, ".auras." .. lane .. ".iconZoom"),
        })
    AddAuraTooltipHelp(BindGroupSwitch(ctx, frameBasics, "Show Tooltip", basicsRightX, -48, basicsCol,
        scope, lane, "showTooltip", true, "visual", RefreshStylePreview))
    BindGroupSwitch(ctx, frameBasics, "Show Cooldown Text", 24, -106, basicsCol,
        scope, lane, "showCooldown", true, "visual", RefreshStylePreview)
    BindGroupSwitch(ctx, frameBasics, "Show Cooldown Swipe", basicsRightX, -106, basicsCol,
        scope, lane, "showCooldownSwipe", true, "visual", RefreshStylePreview)
    if lane == "debuff" then
        BindDropdown(ctx, frameBasics, "Dispel-type Border", 24, -140,
            type(Model.DebuffTypeBorderModeValues) == "function" and Model.DebuffTypeBorderModeValues() or DEBUFF_TYPE_BORDER_MODE_VALUES,
            basicsCol,
            function() return ReadGroupDebuffTypeBorderMode(scope, lane) end,
            function(v)
                WriteGroupDebuffTypeBorderMode(scope, lane, v)
                RefreshStylePreview()
            end,
            AuraControlMeta(ctx, "group-style.lane." .. AuraCatalogToken(lane) .. ".dispel-border-mode"))
    end

    local cooldown = b:CollapsibleSection(baseId .. "_cooldown", "Cooldown Text", 336, true)
    if W.AttachContextColorShortcut then
        W.AttachContextColorShortcut(cooldown, {
            title = M.Format("%s Cooldown Text Settings", Tr(LaneTitle(lane))),
            historyLabel = "Group aura cooldown text color",
            historySource = "menu:group-auras-cooldown-text-color",
            scopeTag = "Shared",
            note = AURA_SHARED_COLOR_NOTE,
            textSettings = {
                scope = "shared",
                kind = "aura",
                colorReferences = AURA_COOLDOWN_COLOR_REFERENCES,
                colorTitle = M.Format("%s Cooldown Colors", Tr(LaneTitle(lane))),
                subtitle = "Group aura cooldown text follows the shared Fonts settings.",
                capabilities = {
                    opacity = false, baseline = false,
                    shadowAlpha = false, shadowDistance = false,
                },
            },
        })
    end
    local cw = BodyWidth(cooldown)
    -- Mode must be "auras", not "font": the DIRTY_FONT fast path refreshes the
    -- compiled spec's text domain in place and never recompiles the aura lanes,
    -- so the lane CooldownSize stays stale until an unrelated geometry write
    -- drops the cache (issue #64). "auras" invalidates the compiled spec and
    -- re-applies only the aura element.
    BindGroupSlider(ctx, cooldown, "Cooldown Font", 24, -56, 6, 24, 1, cw - 48, scope, lane, "cooldownSize", 8, "auras", RefreshStylePreview)
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

    local durationInline = (b.width or 720) >= 520
    local durationBar = b:CollapsibleSection(baseId .. "_duration_bar", "Duration Bar", durationInline and 220 or 332, false)
    W.AttachContextColorReferences(durationBar, AURA_DURATION_BAR_COLOR_REFERENCES, {
        title = M.Format("%s Duration Bar Color", Tr(LaneTitle(lane))),
        scopeTag = "Shared",
        note = AURA_SHARED_COLOR_NOTE,
    })
    local dbw = BodyWidth(durationBar)
    local durationChoiceWidth = durationInline and floor(((dbw - 48) - 20) / 3) or (dbw - 48)
    refreshDurationBarSummary = function()
        if not W.SetCollapsibleBadges then return end
        local group = GFReadGroup(scope, lane)
        local enabled = group.showDurationBar == true
        local display = group.durationBarDisplay == "OVERLAY" and "OVERLAY" or "BAR_ONLY"
        local position = group.durationBarPosition == "TOP" and "TOP" or "BOTTOM"
        W.SetCollapsibleBadges(durationBar, {{
            text = enabled and (tostring(Round(tonumber(group.durationBarHeight) or 2)) .. "px / " .. ChoiceLabel(DURATION_BAR_DISPLAY_VALUES, display, "Bar Only") .. " / " .. ChoiceLabel(DURATION_BAR_POSITION_VALUES, position, "Bottom")) or "Off",
            kind = enabled and "accent" or "muted", showWhenClosed = true,
        }})
    end
    local function RefreshDurationBarPreviewAndSummary()
        RefreshStylePreview()
        refreshDurationBarSummary()
    end
    BindGroupSwitch(ctx, durationBar, "Show Duration Bar", 24, -48, dbw - 48, scope, lane, "showDurationBar", false, "visual", RefreshDurationBarPreviewAndSummary)
    BindGroupSlider(ctx, durationBar, "Height", 24, -104, 1, 16, 1, dbw - 48, scope, lane, "durationBarHeight", 2, "visual", RefreshDurationBarPreviewAndSummary)
    AddTooltip(BindGroupDropdown(ctx, durationBar, "Display", 24, -162, DURATION_BAR_DISPLAY_VALUES, durationChoiceWidth, scope, lane, "durationBarDisplay", "BAR_ONLY", "visual", RefreshDurationBarPreviewAndSummary),
        "Duration bar display", "Bar Only hides the aura icon. Icon + Bar keeps the icon and draws the duration bar on it.")
    AddTooltip(BindGroupDropdown(ctx, durationBar, "Position", durationInline and (34 + durationChoiceWidth) or 24, durationInline and -162 or -220, DURATION_BAR_POSITION_VALUES, durationChoiceWidth, scope, lane, "durationBarPosition", "BOTTOM", "visual", RefreshDurationBarPreviewAndSummary),
        "Duration bar position", "Places the duration bar at the top or bottom edge of the aura slot.")
    AddTooltip(BindGroupDropdown(ctx, durationBar, "Fill Mode", durationInline and (44 + (durationChoiceWidth * 2)) or 24, durationInline and -162 or -278, DURATION_BAR_DIRECTION_VALUES, durationChoiceWidth, scope, lane, "durationBarDirection", "REMAINING", "visual", RefreshDurationBarPreviewAndSummary),
        "Duration bar fill mode", "Remaining shrinks as the aura expires. Elapsed grows until the aura expires.")

    local stack = b:CollapsibleSection(baseId .. "_stack", "Stack Count", 270, false)
    if W.AttachContextColorShortcut then
        W.AttachContextColorShortcut(stack, {
            title = M.Format("%s Stack Text Settings", Tr(LaneTitle(lane))),
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
    -- "auras" for the same reason as Cooldown Font above: lane StackSize lives
    -- in the aura domain, which the "font" fast path never recompiles.
    BindGroupSlider(ctx, stack, "Stack Font", 24, -94, 6, 24, 1, sw - 48, scope, lane, "stackSize", 10, "auras", RefreshStylePreview)
    BindGroupDropdown(ctx, stack, "Stack Anchor", 24, -152, GFAnchorValues(), sw - 48, scope, lane, "stackAnchor", "BOTTOMRIGHT", "geometry", RefreshStylePreview)
    local stackSmallW = max(120, floor((sw - 72) / 2))
    BindGroupSlider(ctx, stack, "Stack X", 24, -210, -40, 40, 1, stackSmallW, scope, lane, "stackX", 0, "geometry", RefreshStylePreview)
    BindGroupSlider(ctx, stack, "Stack Y", 32 + stackSmallW, -210, -40, 40, 1, stackSmallW, scope, lane, "stackY", 0, "geometry", RefreshStylePreview)

    local largeGroups = b:CollapsibleSection(baseId .. "_large_groups", "Large Groups", 112, false)
    local lgw = BodyWidth(largeGroups)
    BindGroupRootSwitch(ctx, largeGroups, "Scale Icons for Large Groups", 24, -48, lgw - 48, scope, "dynamicScale", false, "geometry", RefreshStylePreview)
    W.Text(largeGroups, "85% above 15 members / 70% above 25", 24, -78, lgw - 48, T.colors.muted)

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
        local frameBasicsBadges = {
            {
                text = M.Format("Zoom %d%%", Round(tonumber(group.iconZoom) or tonumber(root.iconZoom) or 100)),
                kind = "info", showWhenClosed = true,
            },
            ToggleBadge("Text", cooldownEnabled),
            ToggleBadge("Swipe", swipeEnabled),
            ToggleBadge("Tooltip", tooltipEnabled),
        }
        if lane == "debuff" then
            local borderMode = ReadGroupDebuffTypeBorderMode(scope, lane)
            frameBasicsBadges[#frameBasicsBadges + 1] = {
                text = "Border " .. ChoiceLabel(DEBUFF_TYPE_BORDER_MODE_VALUES, borderMode, borderMode),
                kind = borderMode == "OFF" and "muted" or "accent", showWhenClosed = true,
            }
        end
        W.SetCollapsibleBadges(frameBasics, frameBasicsBadges)

        local decimal = Round(tonumber(group.cooldownDecimalSeconds) or 3)
        W.SetCollapsibleBadges(cooldown, {
            { text = cooldownEnabled and (tostring(Round(tonumber(group.cooldownSize) or 8)) .. "px / " .. AnchorLabel(group.cooldownAnchor or "CENTER") .. " / " .. (group.cooldownSwipeReverse == true and "Reverse" or "Normal")) or "Off", kind = cooldownEnabled and "accent" or "muted", showWhenClosed = true },
            { text = decimal > 0 and M.Format("Decimals below %ds", decimal) or Tr("Whole seconds"), kind = "info", showWhenClosed = true },
        })

        refreshDurationBarSummary()

        local stackEnabled = group.showStacks ~= false
        W.SetCollapsibleBadges(stack, {{
            text = stackEnabled and (tostring(Round(tonumber(group.stackSize) or 10)) .. "px / " .. AnchorLabel(group.stackAnchor or "BOTTOMRIGHT")) or "Off",
            kind = stackEnabled and "accent" or "muted", showWhenClosed = true,
        }})

        W.SetCollapsibleBadges(largeGroups, {
            ToggleBadge("Large-group scaling", root.dynamicScale == true),
        })
    end)
end

local function BuildGroupOrdering(ctx, b, scope, lane)
    lane = lane == "externals" and "externals" or (lane == "debuff" and "debuff" or "buff")
    local section = b:Section("Ordering", 156)
    local width = section and (section._msuf2Width or section.GetWidth and section:GetWidth()) or b.width or 720
    local groupSortMethod = BindGroupDropdown(ctx, section, "Sort By", 24, -48, AuraSortMethodValues(lane), width - 48,
        scope, lane, "sortMethod", "DEFAULT", "visual", nil,
        AuraControlMetaAtVisiblePath(ctx,
            "group-style.lane." .. AuraCatalogToken(lane) .. ".sortmethod",
            "group-workspace.lane." .. AuraCatalogToken(lane) .. ".ordering.sort-method"))
    AddTooltip(groupSortMethod, "Aura sorting", "Only relevant sorting methods are shown for helpful and harmful auras.")
    local groupSortDirection = BindDropdown(ctx, section, "Order", 24, -104, AURA_SORT_DIRECTION_VALUES, width - 48,
        function()
            local group = GFReadGroup(scope, lane)
            return group.sortReverse == true and "REVERSE" or "NORMAL"
        end,
        function(value)
            GFWriteGroupValue(scope, lane, "sortReverse", value == "REVERSE", "visual")
        end,
        AuraControlMetaAtVisiblePath(ctx,
            "group-style.lane." .. AuraCatalogToken(lane) .. ".sort-direction",
            "group-workspace.lane." .. AuraCatalogToken(lane) .. ".ordering.sort-direction"))
    AddTooltip(groupSortDirection, "Aura sort order", "Reversed flips the complete priority order.")
end
local function CustomStyleSectionId(index, suffix)
    return "aura_style_custom_" .. tostring(index or 1) .. "_" .. tostring(suffix or "section")
end
local function BuildAuraStylePage(ctx)
    local b = W.PageBuilder(ctx)
    Model.EnsureDB()
    b:GlobalStyleHeader("Global Aura Appearance", "Global Appearance theme selected only by Aura type. All layout, filters, timers, text and effects stay scope-aware in the corresponding UnitFrame or GroupFrame.", 84)
    local container = BuildAuraStyleNav(ctx, b, "appearance")
    local themeLane = container == "targetDots" and "debuff" or "buff"
    if container == "debuff" then themeLane = "debuff" end
    SetCurrentLane("auraStyleGFLane", themeLane)
    BuildUnitStyle(ctx, b, "appearance", {
        appearanceGlobalsOnly = true,
        previewContainer = container,
    })
    FinishPage(ctx, b)
end
local function BuildAuraStyleLanePage(ctx, lane)
    SetCurrentLane("auraStyleGFLane", lane)
    M.SetMenuStateValue("auraAppearanceContainer", lane)
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
    local blacklistY = showFilter and (originY - 362) or (originY - 42)
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
        local filter = Card(section, M.Format("Native %s Filter", Tr(laneText)), M.Format("Filter token for %s group-frame %s.", Tr(ScopeLabel(scope)), Tr(LanePlural(lane))), 24, originY - 42, filterW, 296)
        W.LabelAt(filter, fixedLane and M.Format("%s Content", Tr(laneText)) or Tr("Filter Type"), 16, -72, fixedLane and 260 or 90, "GameFontNormalSmall", T.colors.accent)
        if not fixedLane then BuildLaneTabs(ctx, filter, "auraFilterLane", 112, -68, min(300, w - 180)) end
        local dropdownW = min(360, max(240, floor((filterW - 48) * 0.55)))
        BindGroupDropdown(ctx, filter, M.Format("%s Filter", Tr(laneText)), 16, -142, GroupFilterValues(lane), dropdownW, scope, lane, "filterToken", "ALL", "visual")
        W.Text(filter, "Choose which auras Blizzard provides for this lane.", 40 + dropdownW, -142, max(220, filterW - dropdownW - 64), T.colors.muted)
        local hidePermanent = BindSwitch(ctx, filter, "Hide permanent auras", 16, -192, dropdownW,
            ReadHidePermanent, WriteHidePermanent,
            AuraControlMeta(ctx, "group-filter.lane." .. AuraCatalogToken(lane) .. ".hide-permanent"))
        AddHidePermanentTooltip(hidePermanent)
        if M.CLASSIC_AURA_FILTERS_REDUCED ~= true then
            ConfigureMaxDurationSlider(BindSlider(ctx, filter, "Maximum duration", 16, -230, 0, 180, 1, filterW - 32,
                ReadMaxDuration, WriteMaxDuration,
                AuraControlMeta(ctx, "group-filter.lane." .. AuraCatalogToken(lane) .. ".max-duration", nil, {
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
    local function PresetValues()
        return type(Model.GroupBlacklistPresetValues) == "function"
            and Model.GroupBlacklistPresetValues(lane) or Model.BlacklistPresetValues()
    end
    local function CurrentPreset()
        local defaultKey = lane == "debuff" and "SATED" or "RAID_BUFFS"
        local key = M.auraBlacklistPreset or defaultKey
        local values = PresetValues()
        for i = 1, #values do if values[i].value == key then return key end end
        return values[1] and values[1].value or defaultKey
    end
    local function PresetSpellValues()
        return type(Model.GroupBlacklistSpellValues) == "function"
            and Model.GroupBlacklistSpellValues(lane, CurrentPreset()) or Model.BlacklistSpellValues(CurrentPreset())
    end
    local directPresetY = lane == "debuff" and -72 or -126
    local preset = W.Dropdown(direct, "Preset", PresetValues, presetW)
    W.MoveWidget(preset, direct, 16, directPresetY, presetW)
    M.BindDropdownWidget(ctx, preset, CurrentPreset, function(value)
        M.auraBlacklistPreset = value
        M.auraBlacklistSpell = nil
        QueueAurasPageRefresh(ctx, "group-aura-blacklist-preset")
    end, AuraControlMeta(ctx, "group-blacklist.lane." .. AuraCatalogToken(lane) .. ".preset-selection", "ephemeral"))
    local spell = W.Dropdown(direct, "Spell", PresetSpellValues, spellW)
    W.MoveWidget(spell, direct, 26 + presetW, directPresetY, spellW)
    M.BindDropdownWidget(ctx, spell,
        function()
            local values, selected = PresetSpellValues(), M.auraBlacklistSpell
            for i = 1, #values do if values[i].value == selected then return selected end end
            return values[1] and values[1].value or nil
        end,
        function(value) M.auraBlacklistSpell = value end,
        AuraControlMeta(ctx, "group-blacklist.lane." .. AuraCatalogToken(lane) .. ".spell-selection", "ephemeral"))
    local addSpell = ActionButton(direct, "Add spell", 96)
    addSpell:SetPoint("TOPLEFT", direct, "TOPLEFT", 36 + presetW + spellW, directPresetY - 22)
    addSpell:SetScript("OnClick", function()
        local values = PresetSpellValues()
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
    local listScroll = CreateFrame("ScrollFrame", nil, direct)
    listScroll:SetPoint("TOPLEFT", direct, "TOPLEFT", 16, directPresetY - 110)
    listScroll:SetSize(w - 108, 48)
    local listChild = CreateFrame("Frame", nil, listScroll)
    listChild:SetSize(w - 130, 48)
    listScroll:SetScrollChild(listChild)
    M._StyleNestedAuraScrollFrame(listScroll, direct, 28)
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
        prepared:SetText(#entries == 1 and Tr("1 blocked spell · click an entry to remove")
            or M.Format("%d blocked spells · click an entry to remove", #entries))
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
local UNIT_AURA_NORMAL_TOOLS = UniformChoiceWidths(VTP "layout=Layout|behavior=Ordering|filters=Filters|blacklist=Blacklist|style=Style", UNIT_AURA_CHOICE_WIDTH)
local UNIT_AURA_CUSTOM_TOOLS = UniformChoiceWidths(VTP "setup=Setup|layout=Layout|behavior=Ordering|filters=Filters|whitelist=Whitelist|style=Style", UNIT_AURA_CHOICE_WIDTH)
local UNIT_AURA_TARGET_DOT_TOOLS = UniformChoiceWidths(VTP "setup=Setup|layout=Layout|behavior=Ordering|filters=Filters|dots=Dots|style=Style", UNIT_AURA_CHOICE_WIDTH)
M._unitAuraPlayerDefensiveTools = UniformChoiceWidths(VTP "setup=Setup|layout=Layout|behavior=Ordering|filters=Filters|defensives=Defensives|style=Style", UNIT_AURA_CHOICE_WIDTH)
local UNIT_AURA_NORMAL_TOOL_OK = { layout = true, behavior = true, filters = true, blacklist = true, style = true }
local UNIT_AURA_CUSTOM_TOOL_OK = { setup = true, behavior = true, whitelist = true, filters = true, layout = true, style = true }
local UNIT_AURA_TARGET_DOT_TOOL_OK = { setup = true, layout = true, behavior = true, filters = true, dots = true, style = true }
M._unitAuraPlayerDefensiveToolOK = { setup = true, layout = true, behavior = true, filters = true, defensives = true, style = true }

local function CurrentUnitAuraTool(unit, container)
    M.unitAuraToolSelection = M.unitAuraToolSelection or {}
    local unitState = M.unitAuraToolSelection[unit]
    if type(unitState) ~= "table" then unitState = {}; M.unitAuraToolSelection[unit] = unitState end
    local custom = tostring(container or ""):match("^custom") ~= nil
    local playerDefensives = unit == "player" and container == "custom4"
    local targetDots = unit ~= "player" and container == "custom4"
    local tool = unitState[container]
    local valid = playerDefensives and M._unitAuraPlayerDefensiveToolOK
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
    local title = kind == "debuff" and Tr("Debuff Layout") or Tr("Buff Layout")
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
                    ApplyUnit(ctx, unit, "AURAS3_UNIT_GROWTH", true)
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
                function() return Model.ReadLaneSpacing(unit, kind) end,
                function(v) Model.WriteLaneSpacing(unit, kind, v); ApplyUnit(ctx, unit, "AURAS3_UNIT_SPACING") end),
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
    local section = b:Section((lane == "debuff" and "Debuff" or "Buff") .. " Filters",
        M.CLASSIC_AURA_FILTERS_REDUCED == true and 118 or 256)
    local w = section._msuf2Width or b.width or 720
    local inner = w - 48
    local gap = 12
    local colW = floor((inner - gap * 3) / 4)
    local filterControls = {}
    if M.CLASSIC_AURA_FILTERS_REDUCED == true then
        local onlyMine = BindSwitch(ctx, section, "Only mine", 24, -42, colW,
            function()
                return Model.LaneFiltersEnabled(unit, lane)
                    and Model.ReadFilter(unit, lane, "onlyMine", false) == true
            end,
            function(value)
                if value == true and Model.LaneFiltersEnabled(unit, lane) ~= true then
                    Model.SetLaneFiltersEnabled(unit, lane, true)
                end
                Model.WriteFilter(unit, lane, "onlyMine", value == true)
                ApplyUnit(ctx, unit, "AURAS3_FILTER_" .. lane .. "_onlyMine", true)
            end,
            AuraControlMeta(ctx, "unit-workspace.lane." .. AuraCatalogToken(lane) .. ".filters.only-mine", nil,
                "auras3." .. unit .. "." .. lane .. ".filter.onlyMine"))
        AddTooltip(onlyMine, "Only mine", lane == "debuff"
            and "Only Debuffs applied by the player."
            or "Only auras applied by the player.")
        local hidePermanent = BindSwitch(ctx, section, "Hide permanent", 24 + colW + gap, -42, colW,
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
        AddTooltip(hidePermanent, "Hide permanent auras", "Always excludes auras without a duration.")
        M.TrackRefresh(ctx, function()
            W.SetControlEnabled(onlyMine, true)
            W.SetControlEnabled(hidePermanent, true)
        end)
        return
    end
    local enabled = BindSwitch(ctx, section, "Enable filters", 24, -42, colW,
        function() return Model.LaneFiltersEnabled(unit, lane) end,
        function(value) Model.SetLaneFiltersEnabled(unit, lane, value); ApplyUnit(ctx, unit, "AURAS3_FILTER_ENABLE", true) end,
        AuraControlMeta(ctx, "unit-workspace.lane." .. AuraCatalogToken(lane) .. ".filters.enabled", nil,
            "auras3." .. unit .. "." .. lane .. ".filtersEnabled"))
    AddTooltip(enabled, "Enable filters", "Turns aura classification filters on or off for this exact lane. Big Defensive uses MSUF's curated list on friendly frames.")
    local hidePermanent = BindSwitch(ctx, section, "Hide permanent", 24 + colW + gap, -42, colW,
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
    if M.CLASSIC_AURA_FILTERS_REDUCED ~= true then
        maxDuration = ConfigureMaxDurationSlider(BindSlider(ctx, section, "Maximum duration", 24, -174, 0, 180, 1, inner,
            function()
                return type(Model.ReadBlacklistMaxDuration) == "function"
                    and Model.ReadBlacklistMaxDuration(unit, lane) or 0
            end,
            function(value)
                if type(Model.WriteBlacklistMaxDuration) == "function"
                    and Model.WriteBlacklistMaxDuration(unit, lane, value) then
                    ApplyUnit(ctx, unit, "AURAS3_" .. tostring(lane):upper() .. "_MAX_DURATION", true)
                end
            end,
            AuraControlMeta(ctx, "unit-workspace.lane." .. AuraCatalogToken(lane) .. ".filters.max-duration", nil, {
                assistantDisposition = "compound",
                assistantDispositionReason = "The native candidate-filter duration limit has no Assistant setting contract yet.",
            })))
    end
    local specs = lane == "buff" and {
        { "Only mine", "onlyMine", "Only auras applied by the player." },
        { "Important", "onlyImportant", "Only auras Blizzard flags as important." },
        { "Applicable by me", "raid", "Helpful auras your character can apply (Blizzard RAID token)." },
        { "Raid combat", "raidInCombat", "Blizzard's in-combat raid Buff filter." },
        { "Also include nameplate-only", "includeNameplateOnly", "Broadens the selected filter to also admit Buffs Blizzard marks nameplate-only; it is not a standalone only-filter." },
        { "Dispellable / stealable by group", "includeDispellable", "Helpful enemy auras someone in your group can dispel, purge, or steal." },
        { "Any dispel / steal type", "dispellableAny", "Helpful enemy auras with any dispel type, even when your group cannot remove them." },
        { "External defensive", "externalDefensive", "External defensive Buffs." },
        { "Big defensive", "bigDefensive", "MSUF's curated major-defensive Spell-ID list on friendly frames; Blizzard's safe native classification is used where exact identity filtering is restricted." },
        { "Cancelable", "cancelable", "Only cancelable Buffs.", { "notCancelable" } },
        { "Not cancelable", "notCancelable", "Only non-cancelable Buffs.", { "cancelable" } },
    } or {
        { "Only mine", "onlyMine", "Only Debuffs applied by the player.", { "nonPlayer" } },
        { "Important", "onlyImportant", "Only Debuffs Blizzard flags as important." },
        { "Dispellable by me", "raid", "Harmful auras your character can dispel (Blizzard RAID token)." },
        { "Raid combat", "raidInCombat", "Blizzard's in-combat raid Debuff filter." },
        { "Also include nameplate-only", "includeNameplateOnly", "Broadens the selected filter to also admit Debuffs Blizzard marks nameplate-only; it is not a standalone only-filter." },
        { "Dispellable by group", "includeDispellable", "Debuffs someone in your group can dispel." },
        { "Any dispel type", "dispellableAny", "Debuffs with a dispel type, even when your group cannot remove them." },
        { "Crowd control", "crowdControl", "Crowd-control Debuffs." },
        { "Non-player auras", "nonPlayer", "Only Debuffs not caused by any player or player pet.", { "onlyMine" } },
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
                local key = spec[2]
                local modifier = key == "onlyMine" or key == "includeNameplateOnly"
                if value == true and not modifier then
                    -- Blizzard joins native filter tokens as an intersection.
                    -- Present classification choices as one active selector so
                    -- the switch UI cannot accidentally build empty AND chains;
                    -- caster and nameplate inclusion remain explicit modifiers.
                    for j = 1, #specs do
                        local otherKey = specs[j][2]
                        if otherKey ~= key and otherKey ~= "onlyMine" and otherKey ~= "includeNameplateOnly" then
                            Model.WriteFilter(unit, lane, otherKey, false)
                        end
                    end
                end
                if value == true and type(spec[4]) == "table" then for j = 1, #spec[4] do Model.WriteFilter(unit, lane, spec[4][j], false) end end
                -- Older profiles stored the same RAID token in a second
                -- Exclusive dropdown. Fold it into the visible Raid switch so
                -- the legacy restriction can also be turned off here.
                if spec[2] == "raid" then Model.WriteFilter(unit, lane, "exclusive", "none") end
                Model.WriteFilter(unit, lane, spec[2], value)
                ApplyUnit(ctx, unit, "AURAS3_FILTER_" .. lane .. "_" .. spec[2], true)
                if not modifier or spec[4] then QueueAurasPageRefresh(ctx, "auras-filter-conflict") end
            end,
            AuraControlMeta(ctx, "unit-workspace.lane." .. AuraCatalogToken(lane) .. ".filters." .. AuraCatalogToken(spec[2]), nil,
                settingContract))
        AddTooltip(control, spec[1], spec[3])
        filterControls[#filterControls + 1] = control
    end
    M.TrackRefresh(ctx, function()
        W.SetControlEnabled(enabled, true)
        W.SetControlEnabled(hidePermanent, true)
        W.SetControlEnabled(maxDuration, true)
        W.SetControlsEnabled(filterControls, Model.LaneFiltersEnabled(unit, lane))
    end)
end

local function BuildCompactUnitAuraBlacklist(ctx, b, unit, lane)
    local laneTitle = lane == "debuff" and "Debuff" or "Buff"
    local isDebuff = lane == "debuff"
    local enemyDebuff = isDebuff and unit ~= "player"
    local showPresets = not isDebuff or type(Model.UnitBlacklistPresetValues) ~= "function"
        or #Model.UnitBlacklistPresetValues(unit, lane) > 0
    local combinedManualAndPresets = (not isDebuff or enemyDebuff) and showPresets
    local refreshList, renderVerify, refreshLiveBlock, nonPresetHint
    local section = b:Section(laneTitle .. " Blacklist",
        combinedManualAndPresets and 620 or ((not isDebuff or enemyDebuff) and 538 or 446))
    local w = section._msuf2Width or b.width or 720
    local inner = w - 48
    if not isDebuff or enemyDebuff then
        local inputValue = ""
        local inputW = max(140, min(floor(inner * 0.62), inner - 130))
        local inputLabel = enemyDebuff and "Enemy debuff Spell ID, link, or name"
            or "Enter buff Spell ID, link, or name"
        local addLabel = enemyDebuff and "Add enemy debuff" or "Add custom buff"
        local input = BindTextInput(ctx, section, inputLabel, 24, -36, inputW,
            function() return inputValue end, function(value) inputValue = value or "" end,
            false, AuraControlMeta(ctx, "unit-workspace.lane." .. AuraCatalogToken(lane) .. ".blacklist.manual-input", "ephemeral"))
        if enemyDebuff then CreateCustomDebuffBlacklistInfoButton(section, input, unit) end
        AddTooltip(input, "Spell ID vs. aura ID",
            "The aura on the unit can use a different Spell ID than the spell you cast. Enter the ID shown on the aura itself. After adding, MSUF checks the live unit and warns when only a same-named aura with a different ID is active.")
        local add = ActionButton(section, addLabel, enemyDebuff and 132 or 118, "primary")
        add:SetPoint("TOPLEFT", section, "TOPLEFT", 36 + inputW, -60)
        local verifyText = W.Text(section, "", 24, -92, inner - 214, T.colors.muted)
        if verifyText.SetMaxLines then verifyText:SetMaxLines(2) end
        local swapBtn = ActionButton(section, "", 180, "primary")
        swapBtn:SetPoint("TOPRIGHT", section, "TOPRIGHT", -24, -86)
        if M.MarkRuntimeControlComponent then M.MarkRuntimeControlComponent(swapBtn, input) end
        swapBtn:Hide()
        renderVerify = function()
            local state = M.auraBlacklistVerify
            local mine = state and state.unit == unit and state.lane == lane and state or nil
            if not mine then
                verifyText:SetText("")
            elseif mine.status == "scan" and mine.blocked then
                local c = T.colors.accent2 or T.colors.accent
                if c and verifyText.SetTextColor then verifyText:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1) end
                verifyText:SetText(Tr("Blizzard is blocking aura scanning right now (encounter, Mythic+, or PvP match). Use the curated presets - they cover everything blockable in instanced content."))
            elseif mine.status == "scan" then
                local c = T.colors.accent
                if c and verifyText.SetTextColor then verifyText:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1) end
                if (mine.secretCount or 0) > 0 then
                    verifyText:SetText(M.Format("Scan complete: %d auras readable right now, %d captured this session. %d more are hidden by Blizzard and cannot be blocked by any addon.",
                        mine.liveCount or 0, mine.sessionCount or 0, mine.secretCount))
                else
                    verifyText:SetText(M.Format("Scan complete: %d auras readable right now, %d captured this session.",
                        mine.liveCount or 0, mine.sessionCount or 0))
                end
            elseif mine.status == "active" then
                local c = T.colors.accent
                if c and verifyText.SetTextColor then verifyText:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1) end
                verifyText:SetText(M.Format("%s (#%d) is active on this frame right now - blacklist entry verified.",
                    tostring(mine.name or "Spell"), mine.enteredID or 0))
            else
                local c = T.colors.accent2 or T.colors.accent
                if c and verifyText.SetTextColor then verifyText:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1) end
                verifyText:SetText(M.Format("#%d is not active on this frame, but %s is currently active as #%d. The aura's ID can differ from your cast's Spell ID.",
                    mine.enteredID or 0, tostring(mine.suggestName or "Spell"), mine.suggestID or 0))
            end
            local showSwap = mine ~= nil and mine.status == "mismatch" and mine.suggestID ~= nil
            if showSwap and swapBtn._msuf2Label and swapBtn._msuf2Label.SetText then
                swapBtn._msuf2Label:SetText(M.Format("Block #%d instead", mine.suggestID))
            end
            swapBtn:SetShown(showSwap)
            if nonPresetHint then nonPresetHint:SetShown(mine == nil) end
        end
        swapBtn:SetScript("OnClick", function()
            local state = M.auraBlacklistVerify
            local mine = state and state.unit == unit and state.lane == lane and state or nil
            if not (mine and mine.suggestID) then return false end
            if mine.enteredID and mine.enteredID ~= mine.suggestID then
                Model.RemoveBlacklistSpell(unit, mine.enteredID, lane)
            end
            Model.AddBlacklistSpell(unit, mine.suggestID, lane)
            M.auraBlacklistVerify = {
                unit = unit, lane = lane, status = "active",
                enteredID = mine.suggestID, name = mine.suggestName,
            }
            ApplyUnit(ctx, unit, "AURAS3_BLACKLIST_ADD", true)
            if refreshList then refreshList() end
            QueueAurasPageRefresh(ctx, "aura-blacklist-swap-suggested")
            return true
        end)
        local liveY = showPresets and -122 or -134
        local liveW = max(140, min(floor(inner * 0.62), inner - 266))
        local captureKey = unit .. "|" .. lane
        local function CapturedAuras(wipeStore)
            local store = M.auraBlacklistCaptured
            if type(store) ~= "table" then store = {} M.auraBlacklistCaptured = store end
            if wipeStore then store[captureKey] = nil end
            local captured = store[captureKey]
            if type(captured) ~= "table" then captured = {} store[captureKey] = captured end
            return captured
        end
        -- Scanning is strictly click-driven: only the Rescan/Block handlers
        -- call LiveAuraValues. Refreshes and the dropdown read the cached
        -- last scan, so an open menu never scans the unit on its own.
        local liveScanCache
        local function LiveAuraValues()
            local values, unreadable, blocked
            if type(Model.LiveBlacklistAuraValues) == "function" then
                values, unreadable, blocked = Model.LiveBlacklistAuraValues(unit, lane)
            end
            values = values or {}
            -- Every scan also feeds the session capture list, so short-lived
            -- combat debuffs stay pickable after they expire or combat ends.
            local captured = CapturedAuras(false)
            local liveSeen = {}
            for i = 1, #values do
                local entry = values[i]
                liveSeen[entry.value] = true
                local cap = captured[entry.value]
                if type(cap) ~= "table" then
                    cap = { name = type(cap) == "string" and cap or nil }
                    captured[entry.value] = cap
                end
                if type(entry.name) == "string" then cap.name = entry.name end
                if entry.icon ~= nil and cap.icon == nil then cap.icon = entry.icon end
            end
            local capturedOnly = {}
            for id, cap in pairs(captured) do
                if not liveSeen[id] then
                    local capName = type(cap) == "table" and cap.name or (type(cap) == "string" and cap or nil)
                    local label = (capName or "Spell") .. " (#" .. tostring(id) .. ")"
                    capturedOnly[#capturedOnly + 1] = {
                        value = id, name = capName, icon = type(cap) == "table" and cap.icon or nil,
                        text = M.Format("%s - captured", label), captured = true,
                    }
                end
            end
            table.sort(capturedOnly, function(a, b) return tostring(a.text) < tostring(b.text) end)
            for i = 1, #capturedOnly do values[#values + 1] = capturedOnly[i] end
            if #values == 0 then
                values = { { value = nil, text = Tr("No readable auras right now") } }
            end
            liveScanCache = values
            return values, tonumber(unreadable) or 0, blocked == true
        end
        local function CachedAuraValues()
            if liveScanCache then return liveScanCache end
            -- No scan ran in this menu session yet: show the session capture
            -- store as-is (a plain table read - no unit scan happens here).
            local captured = CapturedAuras(false)
            local values = {}
            for id, cap in pairs(captured) do
                local capName = type(cap) == "table" and cap.name or (type(cap) == "string" and cap or nil)
                local label = (capName or "Spell") .. " (#" .. tostring(id) .. ")"
                values[#values + 1] = {
                    value = id, name = capName, icon = type(cap) == "table" and cap.icon or nil,
                    text = M.Format("%s - captured", label), captured = true,
                }
            end
            if #values == 0 then
                return { { value = nil, text = Tr("No scan yet - click Rescan") } }
            end
            table.sort(values, function(a, b) return tostring(a.text) < tostring(b.text) end)
            return values
        end
        local function CurrentLiveAura()
            local values = CachedAuraValues()
            local selected = M.auraBlacklistLiveSpell
            for i = 1, #values do if values[i].value ~= nil and values[i].value == selected then return selected end end
            for i = 1, #values do if values[i].value ~= nil then return values[i].value end end
            return nil
        end
        local liveDrop = W.Dropdown(section, "Active auras on this frame", CachedAuraValues, liveW)
        W.MoveWidget(liveDrop, section, 24, liveY, liveW)
        M.BindDropdownWidget(ctx, liveDrop, CurrentLiveAura,
            function(value) M.auraBlacklistLiveSpell = value end)
        if M.MarkRuntimeControlComponent then M.MarkRuntimeControlComponent(liveDrop, input) end
        AddTooltip(liveDrop, "Active auras on this frame",
            "Shows the result of the last scan: every readable aura with the exact ID it carried, plus everything captured earlier this session. Press Rescan to scan the current unit - blocking from this list always uses the aura's own ID. Secret auras cannot be listed.")
        local blockLive = ActionButton(section, "Block selected aura", 150, "primary")
        blockLive:SetPoint("TOPLEFT", section, "TOPLEFT", 36 + liveW, liveY - 24)
        if M.MarkRuntimeControlComponent then M.MarkRuntimeControlComponent(blockLive, input) end
        AddTooltip(blockLive, "Block selected aura",
            "Blocks the selected aura using the exact ID it carries right now.")
        blockLive:SetScript("OnClick", function()
            local spellID = CurrentLiveAura()
            if not spellID then return false end
            local auraName, liveNow
            local liveValues = type(Model.LiveBlacklistAuraValues) == "function"
                and Model.LiveBlacklistAuraValues(unit, lane) or {}
            for i = 1, #liveValues do
                if liveValues[i].value == spellID then liveNow = true auraName = liveValues[i].name break end
            end
            if not auraName then
                local values = LiveAuraValues()
                for i = 1, #values do if values[i].value == spellID then auraName = values[i].name break end end
            end
            local changed = Model.AddBlacklistSpell(unit, spellID, lane)
            M.auraBlacklistLiveSpell = nil
            -- Captured entries may no longer be on the unit; only claim the
            -- live-verified state when the aura is actually visible right now.
            M.auraBlacklistVerify = liveNow
                and { unit = unit, lane = lane, status = "active", enteredID = spellID, name = auraName } or nil
            if changed then
                ApplyUnit(ctx, unit, "AURAS3_BLACKLIST_ADD", true)
                if refreshList then refreshList() end
                QueueAurasPageRefresh(ctx, "aura-blacklist-live-added")
            else
                renderVerify()
            end
            return changed and true or false
        end)
        refreshLiveBlock = function(blocked)
            local liveSel = CurrentLiveAura()
            W.SetControlEnabled(blockLive, liveSel ~= nil and not blocked[tostring(liveSel)])
        end
        local rescan = ActionButton(section, "Rescan", 96)
        rescan:SetPoint("TOPLEFT", section, "TOPLEFT", 36 + liveW + 158, liveY - 24)
        if M.MarkRuntimeControlComponent then M.MarkRuntimeControlComponent(rescan, input) end
        rescan._msuf2SkipHistoryCheckpoint = true
        -- Scanning only reads C_UnitAuras and repaints plain menu widgets, so
        -- this click is safe during combat lockdown; blocking stays gated.
        rescan._msuf2AllowCombatClick = true
        AddTooltip(rescan, "Rescan",
            "Re-reads the auras on the current unit and adds everything it sees to this session's captured list - works in combat too. Shift-click clears the captured list.")
        rescan:SetScript("OnClick", function()
            if type(_G.IsShiftKeyDown) == "function" and _G.IsShiftKeyDown() then
                CapturedAuras(true)
            end
            M.auraBlacklistLiveSpell = nil
            local values, secretCount, blocked = LiveAuraValues()
            local liveCount = 0
            for i = 1, #values do
                if values[i].value ~= nil and not values[i].captured then liveCount = liveCount + 1 end
            end
            local sessionCount = 0
            for _ in pairs(CapturedAuras(false)) do sessionCount = sessionCount + 1 end
            M.auraBlacklistVerify = {
                unit = unit, lane = lane, status = "scan", blocked = blocked or nil,
                liveCount = liveCount, sessionCount = sessionCount, secretCount = secretCount,
            }
            if liveDrop.SetValue then liveDrop:SetValue(CurrentLiveAura()) end
            if refreshList then refreshList() end
            return true
        end)
        local startScan = ActionButton(section, "Start combat scan", 170)
        startScan:SetPoint("TOPLEFT", section, "TOPLEFT", 24, liveY - 54)
        if M.MarkRuntimeControlComponent then M.MarkRuntimeControlComponent(startScan, input) end
        startScan._msuf2SkipHistoryCheckpoint = true
        startScan._msuf2AllowCombatClick = true
        AddTooltip(startScan, "Start combat scan",
            "Closes the menu and keeps scanning this frame's auras until combat ends or you press Stop. Every aura an addon can block is captured with its icon - auras Blizzard keeps secret cannot be blocked by any addon.")
        startScan:SetScript("OnClick", function()
            -- The scanner overlay is a shared singleton parked on M (this file
            -- sits at the 200-upvalue ceiling, so no new file-scope locals).
            local s = M._auraCombatScanner
            if not s then
                s = CreateFrame("Frame", nil, _G.UIParent)
                M._auraCombatScanner = s
                s:SetSize(372, 100)
                s:SetPoint("TOP", _G.UIParent, "TOP", 0, -160)
                s:SetFrameStrata("DIALOG")
                s:SetMovable(true)
                s:EnableMouse(true)
                s:RegisterForDrag("LeftButton")
                s:SetScript("OnDragStart", function(self) self:StartMoving() end)
                s:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
                s:SetClampedToScreen(true)
                if T.ApplyBackdrop then T.ApplyBackdrop(s, T.colors.panel2, T.colors.cardBorder or T.colors.borderSoft) end
                s.title = T.Font(s, "GameFontHighlightSmall", "", T.colors.accent)
                s.title:SetPoint("TOPLEFT", s, "TOPLEFT", 12, -10)
                s.count = T.Font(s, "GameFontDisableSmall", "", T.colors.muted)
                s.count:SetPoint("TOPLEFT", s, "TOPLEFT", 12, -28)
                s.hint = T.Font(s, "GameFontDisableSmall", "", T.colors.muted)
                s.hint:SetPoint("TOPLEFT", s, "TOPLEFT", 12, -42)
                s.hint:SetPoint("TOPRIGHT", s, "TOPRIGHT", -12, -42)
                s.hint:SetJustifyH("LEFT")
                s.hint:Hide()
                s.icons = {}
                for i = 1, 12 do
                    local tex = s:CreateTexture(nil, "ARTWORK")
                    tex:SetSize(20, 20)
                    tex:SetPoint("BOTTOMLEFT", s, "BOTTOMLEFT", 12 + (i - 1) * 24, 10)
                    tex:Hide()
                    s.icons[i] = tex
                end
                s.stopBtn = ActionButton(s, "Stop scan", 96)
                s.stopBtn:SetPoint("TOPRIGHT", s, "TOPRIGHT", -10, -10)
                s.stopBtn._msuf2AllowCombatClick = true
                s.stopBtn._msuf2SkipHistoryCheckpoint = true
                s.Finish = function(reopen)
                    if not s:IsShown() then return end
                    s:Hide()
                    M.auraBlacklistVerify = {
                        unit = s._scope, lane = s._lane, status = "scan",
                        liveCount = s._lastLive or 0, sessionCount = s._count or 0,
                        secretCount = s._unreadable or 0,
                    }
                    if reopen and not (M.BlockCombatAction and M.BlockCombatAction()) then
                        M.CallIf(M.Open, s._returnPage)
                    end
                end
                s.stopBtn:SetScript("OnClick", function()
                    s.Finish(not (M.BlockCombatAction and M.BlockCombatAction()))
                    return true
                end)
                s:RegisterEvent("PLAYER_REGEN_ENABLED")
                s:SetScript("OnEvent", function(self)
                    if self:IsShown() then self.Finish(true) end
                end)
                s:SetScript("OnUpdate", function(self, elapsed)
                    self._accum = (self._accum or 0) + (tonumber(elapsed) or 0)
                    if self._accum < 0.4 then return end
                    self._accum = 0
                    local live, unreadable, blocked
                    if type(Model.LiveBlacklistAuraValues) == "function" then
                        live, unreadable, blocked = Model.LiveBlacklistAuraValues(self._scope, self._lane)
                    end
                    if blocked then
                        -- Access denial is temporary (encounter/M+/PvP); keep
                        -- ticking cheaply so the scan resumes on its own.
                        self._dots = ((self._dots or 0) % 3) + 1
                        self.title:SetText(Tr("Scanning auras - creating a list") .. string.rep(".", self._dots))
                        self.hint:SetText(Tr("Blocked by Blizzard during this fight - resumes automatically. In instances, use the curated presets."))
                        self.hint:Show()
                        return
                    end
                    live = live or {}
                    self._lastLive = #live
                    self._unreadable = tonumber(unreadable) or 0
                    local store = M.auraBlacklistCaptured
                    if type(store) ~= "table" then store = {} M.auraBlacklistCaptured = store end
                    local capKey = tostring(self._scope) .. "|" .. tostring(self._lane)
                    local captured = store[capKey]
                    if type(captured) ~= "table" then captured = {} store[capKey] = captured end
                    for i = 1, #live do
                        local entry = live[i]
                        local cap = captured[entry.value]
                        if type(cap) ~= "table" then
                            cap = { name = type(cap) == "string" and cap or nil }
                            captured[entry.value] = cap
                            self._count = (self._count or 0) + 1
                            self._recent[#self._recent + 1] = entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark"
                        end
                        if type(entry.name) == "string" then cap.name = entry.name end
                        if entry.icon ~= nil and cap.icon == nil then cap.icon = entry.icon end
                    end
                    local total = #self._recent
                    for i = 1, #self.icons do
                        local tex = self.icons[i]
                        local icon = self._recent[total - i + 1]
                        if icon then tex:SetTexture(icon) tex:Show() else tex:Hide() end
                    end
                    self._dots = ((self._dots or 0) % 3) + 1
                    self.title:SetText(Tr("Scanning auras - creating a list") .. string.rep(".", self._dots))
                    if (self._unreadable or 0) > 0 then
                        self.count:SetText(M.Format("%d captured so far - %d hidden by Blizzard",
                            self._count or 0, self._unreadable))
                        self.hint:SetText(Tr("Hidden auras are Blizzard-secret - no addon can block them. Everything blockable was captured."))
                        self.hint:Show()
                    else
                        self.count:SetText(M.Format("%d captured so far", self._count or 0))
                        self.hint:Hide()
                    end
                end)
            end
            s._scope, s._lane = unit, lane
            s._returnPage = M.activeKey
            s._recent = {}
            s._accum = 1
            s._dots = 0
            s._lastLive = 0
            local sessionCount = 0
            for _ in pairs(CapturedAuras(false)) do sessionCount = sessionCount + 1 end
            s._count = sessionCount
            s.title:SetText(Tr("Scanning auras - creating a list"))
            s.count:SetText(M.Format("%d captured so far", sessionCount))
            if s.hint then s.hint:Hide() end
            for i = 1, #s.icons do s.icons[i]:Hide() end
            s:Show()
            M.CallIf(M.HideSlashMenuAndMinibar, M.frame)
            return true
        end)
        add:SetScript("OnClick", function()
            local value = input and input.GetText and input:GetText() or inputValue
            local spellID = type(Model.ResolveSpellInputID) == "function" and Model.ResolveSpellInputID(value) or nil
            local changed = Model.AddBlacklistSpell(unit, value, lane)
            if changed then
                ApplyUnit(ctx, unit, "AURAS3_BLACKLIST_ADD", true)
            end
            -- The aura left on the unit can carry a different SpellID than the
            -- cast the entry resolved to; compare against the live unit so the
            -- mismatch surfaces immediately instead of failing silently.
            M.auraBlacklistVerify = nil
            local verdict = spellID and type(Model.FindLiveBlacklistAura) == "function"
                and Model.FindLiveBlacklistAura(unit, spellID, lane) or nil
            if verdict then
                M.auraBlacklistVerify = {
                    unit = unit, lane = lane, status = verdict.status,
                    enteredID = spellID, name = verdict.name,
                    suggestID = verdict.suggestID, suggestName = verdict.suggestName,
                }
            end
            if changed then
                if refreshList then refreshList() end
                QueueAurasPageRefresh(ctx, "aura-blacklist-manual-added")
            else
                renderVerify()
            end
            if input and input.SetText then input:SetText("") end
            inputValue = ""
            return changed and true or false
        end)
        RegisterAuraTextAction(ctx, add, input, addLabel,
            "unit-workspace.lane." .. AuraCatalogToken(lane) .. ".blacklist.add-manual", {
            actionKey = "aura_blacklist_add_spell", actionFixedArgs = { scope = unit, lane = lane }, actionInputArg = "value",
        })
        if enemyDebuff then
            AddTooltip(add, "Add enemy debuff",
                "Adds one exact harmful aura to this Target, Focus, or Boss blacklist. Blizzard applies arbitrary SpellID filters only while the unit is not assistable.")
        else
            AddTooltip(add, "Add custom buff", "Adds one exact buff to this frame's blacklist.")
        end
    end
    local curatedOffset = combinedManualAndPresets and -174 or 0
    local presetW = max(130, min(floor(inner * 0.62), inner - 138))
    local spellW = max(160, min(floor(inner * 0.68), inner - 108))
    local function PresetValues()
        return type(Model.UnitBlacklistPresetValues) == "function"
            and Model.UnitBlacklistPresetValues(unit, lane) or Model.BlacklistPresetValues()
    end
    local function CurrentPreset()
        local fallback = type(Model.UnitBlacklistDefaultPreset) == "function"
            and Model.UnitBlacklistDefaultPreset(unit, lane) or "RAID_BUFFS"
        local key = M.auraBlacklistPreset or fallback
        local values = PresetValues()
        for i = 1, #values do if values[i].value == key then return key end end
        for i = 1, #values do if values[i].value then return values[i].value end end
        return fallback
    end
    local function CurrentSpell()
        local values = type(Model.UnitBlacklistSpellValues) == "function"
            and Model.UnitBlacklistSpellValues(unit, lane, CurrentPreset())
            or Model.BlacklistSpellValues(CurrentPreset())
        local selected = M.auraBlacklistSpell
        local entries = Model.BlacklistEntries(unit, lane)
        local blocked = {}
        for i = 1, #entries do blocked[tostring(entries[i].value)] = true end
        for i = 1, #values do
            if values[i].value == selected and not blocked[tostring(selected)] then return selected end
        end
        for i = 1, #values do
            if values[i].value ~= nil and not blocked[tostring(values[i].value)] then return values[i].value end
        end
        return nil
    end
    local selectedSummary, addSet, addSpell
    if showPresets then
        local preset = W.Dropdown(section, "Preset", PresetValues, presetW)
        W.MoveWidget(preset, section, 24, -36 + curatedOffset, presetW)
        M.BindDropdownWidget(ctx, preset, CurrentPreset, function(value) M.auraBlacklistPreset = value; M.auraBlacklistSpell = nil; QueueAurasPageRefresh(ctx, "aura-blacklist-preset") end,
            AuraControlMeta(ctx, "unit-workspace.lane." .. AuraCatalogToken(lane) .. ".blacklist.preset-selection", "ephemeral"))
        addSet = ActionButton(section, "Add entire set", 126, "primary")
        addSet:SetPoint("TOPLEFT", section, "TOPLEFT", 36 + presetW, -60 + curatedOffset)
        addSet:SetScript("OnClick", function()
            local count = Model.AddBlacklistPresetGroup(unit, CurrentPreset(), lane)
            if count > 0 then
                M.auraBlacklistSpell = nil
                ApplyUnit(ctx, unit, "AURAS3_BLACKLIST_PRESET_GROUP_ADD", true)
                if refreshList then refreshList() end
                QueueAurasPageRefresh(ctx, "aura-blacklist-preset-group-added")
            end
            return count > 0
        end)
        RegisterAuraControl(ctx, addSet, "Add entire set", "button", "unit-workspace.lane." .. AuraCatalogToken(lane) .. ".blacklist.add-preset-set", "action", {
            actionKey = "aura_blacklist_add_preset", actionFixedArgs = { scope = unit, lane = lane }, actionInputArg = "preset",
        })
        AddTooltip(addSet, "Add entire set", "Blocks every aura in the selected curated MSUF set.")
        selectedSummary = W.Text(section, "", 24, -92 + curatedOffset, inner, T.colors.muted)
        local spell = W.Dropdown(section, "Spell", function()
            return type(Model.UnitBlacklistSpellValues) == "function"
                and Model.UnitBlacklistSpellValues(unit, lane, CurrentPreset())
                or Model.BlacklistSpellValues(CurrentPreset())
        end, spellW)
        W.MoveWidget(spell, section, 24, -120 + curatedOffset, spellW)
        M.BindDropdownWidget(ctx, spell,
            CurrentSpell,
            function(value) M.auraBlacklistSpell = value end,
            AuraControlMeta(ctx, "unit-workspace.lane." .. AuraCatalogToken(lane) .. ".blacklist.spell-selection", "ephemeral"))
        addSpell = ActionButton(section, "Add spell", 96)
        addSpell:SetPoint("TOPLEFT", section, "TOPLEFT", 36 + spellW, -144 + curatedOffset)
        addSpell:SetScript("OnClick", function()
            local changed = Model.AddBlacklistPresetSpell(unit, CurrentSpell(), lane)
            if changed then
                M.auraBlacklistSpell = nil
                ApplyUnit(ctx, unit, "AURAS3_BLACKLIST_PRESET_ADD", true)
                if refreshList then refreshList() end
                QueueAurasPageRefresh(ctx, "aura-blacklist-preset-spell-added")
            end
            return changed and true or false
        end)
        RegisterAuraControl(ctx, addSpell, "Add spell", "button", "unit-workspace.lane." .. AuraCatalogToken(lane) .. ".blacklist.add-preset-spell", "action", {
            actionKey = "aura_blacklist_add_spell", actionFixedArgs = { scope = unit, lane = lane }, actionInputArg = "value",
        })
        AddTooltip(addSpell, "Add spell", "Blocks only the selected aura from the curated set.")
    else
        nonPresetHint = W.Text(section,
            "Enemy debuffs: hide only exact noisy SpellIDs. Selected Dots on target are handled automatically by that scope's Auto-blacklist toggle.",
            24, -104, inner, T.colors.muted)
    end
    local listOffset = showPresets and curatedOffset or (enemyDebuff and -48 or 44)
    local prepared = W.Text(section, "", 24, -186 + listOffset, inner, T.colors.accent)
    local searchValue = ""
    local searchInput = BindTextInput(ctx, section, "Search", 24, -210 + listOffset, inner,
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
    local emptyText = enemyDebuff and not showPresets and "No blocked enemy debuffs. Add an exact SpellID above."
        or (enemyDebuff and "No blocked spells. Add one above or use a preset.")
        or (isDebuff and "No blocked spells. Add one from the allowed presets above."
        or "No blocked spells. Add one above or use a preset.")
    local empty = W.Text(section, emptyText, 24, -284 + listOffset, inner, T.colors.muted)
    local listScroll = CreateFrame("ScrollFrame", nil, section)
    listScroll:SetPoint("TOPLEFT", section, "TOPLEFT", 24, -260 + listOffset)
    listScroll:SetSize(inner - 20, 150)
    local listChild = CreateFrame("Frame", nil, listScroll)
    listChild:SetSize(inner - 44, 150)
    listScroll:SetScrollChild(listChild)
    M._StyleNestedAuraScrollFrame(listScroll, section, 44)
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
                if refreshList then refreshList() end
                QueueAurasPageRefresh(ctx, "aura-blacklist-removed")
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
        if refreshLiveBlock then refreshLiveBlock(blocked) end
        if showPresets then
            local setSpells = type(Model.UnitBlacklistSpellValues) == "function"
                and Model.UnitBlacklistSpellValues(unit, lane, CurrentPreset())
                or Model.BlacklistSpellValues(CurrentPreset())
            local missing = 0
            for i = 1, #setSpells do if not blocked[tostring(setSpells[i].value)] then missing = missing + 1 end end
            selectedSummary:SetText(missing == 0
                and M.Format("%d spells in this set - all already blocked", #setSpells)
                or M.Format("%d spells in this set - %d can still be added", #setSpells, missing))
            W.SetControlEnabled(addSet, missing > 0)
            local selectedSpell = CurrentSpell()
            W.SetControlEnabled(addSpell, selectedSpell ~= nil and not blocked[tostring(selectedSpell)])
        end
        local query = tostring(searchValue or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        local visible = {}
        for i = 1, #entries do
            local entry = entries[i]
            local haystack = (tostring(entry.text or "") .. " "
                .. tostring(entry.spellID or entry.value or "")):lower()
            if query == "" or haystack:find(query, 1, true) then visible[#visible + 1] = entry end
        end
        prepared:SetText(M.Format("Blocked spells (%d)", #entries) .. MatchSuffix(query, #visible))
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
        if renderVerify then renderVerify() end
    end
    M.TrackRefresh(ctx, refreshList)
end

local function BuildCompactGroupAuraFilters(ctx, b, scope, lane)
    local laneTitle = lane == "debuff" and "Debuff" or "Buff"
    local values = GroupFilterValues(lane)
    local optionRows = max(1, ceil(#values / 4))
    local sectionHeight = max(150, 104 + optionRows * 32)
        + (M.CLASSIC_AURA_FILTERS_REDUCED ~= true and 58 or 0)
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
    local selectedFilterToken = CanonicalGroupFilterValue((GFReadGroup(scope, lane) or {}).filterToken or "ALL", lane)
    for i = 1, #values do
        local item = values[i]
        local col = (i - 1) % 4
        local row = floor((i - 1) / 4)
        local control = BindSwitch(ctx, section, item.text or item.value, 24 + col * (colW + gap), -78 - row * 32, colW,
            function()
                local group = GFReadGroup(scope, lane)
                return CanonicalGroupFilterValue(group.filterToken or "ALL", lane) == item.value
            end,
            function(enabled)
                local group = GFReadGroup(scope, lane)
                local current = CanonicalGroupFilterValue(group.filterToken or "ALL", lane)
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
    if M.CLASSIC_AURA_FILTERS_REDUCED ~= true then
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
            AuraControlMeta(ctx, "group-workspace.lane." .. AuraCatalogToken(lane) .. ".filters.max-duration", nil, {
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
    local function PresetValues()
        return type(Model.GroupBlacklistPresetValues) == "function"
            and Model.GroupBlacklistPresetValues(lane) or Model.BlacklistPresetValues()
    end
    local function CurrentPreset()
        local defaultKey = lane == "debuff" and "SATED" or "RAID_BUFFS"
        local key = M.auraBlacklistPreset or defaultKey
        local values = PresetValues()
        for i = 1, #values do if values[i].value == key then return key end end
        return values[1] and values[1].value or defaultKey
    end
    local function PresetSpellValues()
        return type(Model.GroupBlacklistSpellValues) == "function"
            and Model.GroupBlacklistSpellValues(lane, CurrentPreset()) or Model.BlacklistSpellValues(CurrentPreset())
    end
    local function CurrentSpell()
        local values, selected = PresetSpellValues(), M.auraBlacklistSpell
        local entries = type(Model.GroupBlacklistEntries) == "function"
            and Model.GroupBlacklistEntries(scope, lane) or {}
        local blocked = {}
        for i = 1, #entries do blocked[tostring(entries[i].value)] = true end
        for i = 1, #values do
            if values[i].value == selected and not blocked[tostring(selected)] then return selected end
        end
        for i = 1, #values do
            if values[i].value ~= nil and not blocked[tostring(values[i].value)] then return values[i].value end
        end
        return nil
    end
    local preset = W.Dropdown(section, "Preset", PresetValues, presetW)
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
            M.auraBlacklistSpell = nil
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
    local spell = W.Dropdown(section, "Spell", PresetSpellValues, spellW)
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
            M.auraBlacklistSpell = nil
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
    local listScroll = CreateFrame("ScrollFrame", nil, section)
    listScroll:SetPoint("TOPLEFT", section, "TOPLEFT", 24, -260 + curatedOffset)
    listScroll:SetSize(inner - 20, 150)
    local listChild = CreateFrame("Frame", nil, listScroll)
    listChild:SetSize(inner - 44, 150)
    listScroll:SetScrollChild(listChild)
    M._StyleNestedAuraScrollFrame(listScroll, section, 44)
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
        local setSpells = PresetSpellValues()
        local missing = 0
        for i = 1, #setSpells do if not blocked[tostring(setSpells[i].value)] then missing = missing + 1 end end
        selectedSummary:SetText(missing == 0
            and M.Format("%d spells in this set - all already blocked", #setSpells)
            or M.Format("%d spells in this set - %d can still be added", #setSpells, missing))
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
        prepared:SetText(M.Format("Blocked spells (%d)", #entries) .. MatchSuffix(query, #visible))
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
    lane = lane == "externals" and "externals" or (lane == "debuff" and "debuff" or "buff")
    if lane ~= "externals" then
        SetCurrentLane("auraStyleGFLane", lane)
        SetCurrentLane("auraFilterLane", lane)
    end
    if opts and opts.compact == true then
        if opts.tool == "style" then
            BuildGroupStyle(ctx, b, scope, { embeddedGroupPreview = true, lane = lane })
        elseif opts.tool == "behavior" then
            BuildGroupOrdering(ctx, b, scope, lane)
        elseif opts.tool == "blacklist" then
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
    ctx._auraAppearancePreviewRefresh = function(reason)
        local refreshOwnedPreview = ctx._msuf2RefreshUnitPreview
        if type(refreshOwnedPreview) == "function" then
            refreshOwnedPreview(reason or "AURAS3_UNIT_STYLE_DUMMY")
        elseif type(_G.MSUF_UFPreview_RequestRefresh) == "function" then
            _G.MSUF_UFPreview_RequestRefresh("AURAS3_UNIT_STYLE_DUMMY")
        end
    end
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
    local customContainerPatterns = {}
    for i = 1, #M._customContainerAssistantSuffixes do
        local suffix = M._customContainerAssistantSuffixes[i]
        customContainerPatterns[i] = "^auras3%." .. tostring(unit):gsub("([^%w])", "%%%1") .. "%.custom%d+%."
            .. tostring(suffix):gsub("([^%w])", "%%%1") .. "$"
    end
    local customContainerContract = {
        assistantDisposition = "dynamic",
        assistantDispositionReason = "This selector opens the dynamic editor for any persisted setting on the selected Custom Aura container.",
        assistantSettingKeyPatterns = customContainerPatterns,
    }
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
    }), workspaceTabs, "unit-workspace.container-selector", customContainerContract)
    if containerBar and unit ~= "player" then
        local exactKind = "unitAuraWorkspace"
        -- prepareValue -> { tab, tool, representative settingKey }. Changelog
        -- highlights and search deep-links use these to open the exact
        -- workspace view instead of flashing an unrelated control.
        local exactViews = {
            custom4_behavior = { tab = "custom4", tool = "behavior",
                settingKey = "auras3." .. tostring(unit) .. ".custom4.placed.sortMethod" },
            debuff_blacklist = { tab = "debuff", tool = "blacklist",
                settingKey = "auras3." .. tostring(unit) .. ".debuff.blacklist.hidePermanent" },
        }
        local exactContracts = {}
        for value, view in pairs(exactViews) do exactContracts[value] = view.settingKey end
        containerBar._msuf2ExactTargetKinds = { [exactKind] = true }
        containerBar._msuf2ExactTargetContracts = {
            [exactKind] = exactContracts,
        }
        containerBar._msuf2PrepareExactSearchTarget = function(_, exactTarget)
            if type(exactTarget) ~= "table" or exactTarget.prepareKind ~= exactKind then
                return false
            end
            local view = exactViews[tostring(exactTarget.prepareValue or "")]
            if not view then return false end
            local alreadySelected = M.unitAuraTabSelection[unit] == view.tab
                and CurrentUnitAuraTool(unit, view.tab) == view.tool
            if not alreadySelected then
                M.unitAuraTabSelection[unit] = view.tab
                SetUnitAuraTool(unit, view.tab, view.tool)
            end
            return true
        end
    end
    local toolBar = RegisterAuraChoiceBar(ctx, W.ScopeOverrideBar(ctx, top, {
        values = tools,
        width = sectionW,
        label = "Edit:",
        labelWidth = 72,
        centerY = toolCenterY,
        getValue = function() return CurrentUnitAuraTool(unit, currentTab) end,
        setValue = function(value) SetUnitAuraTool(unit, currentTab, value); Rebuild(ctx) end,
    }), tools, "unit-workspace.tool-selector")
    local openStyle = ActionButton(top, "Global Aura Appearance", 170, "normal")
    openStyle:SetPoint("TOPRIGHT", top, "TOPRIGHT", -16, footerY)
    openStyle:SetScript("OnClick", function()
        local previewContainer = currentTab == "custom4"
            and (unit == "player" and "playerDefensives" or "targetDots")
            or currentTab
        M.SetMenuStateValue("auraAppearanceContainer", previewContainer)
        if normalLane then SetCurrentLane("auraStyleGFLane", currentTab) end
        SelectPage("auras3_styling")
    end)
    RegisterAuraControl(ctx, openStyle, "Global Aura Appearance", "button", "unit-workspace.open-aura-style", "navigation", "auras3_styling")
    AddTooltip(openStyle, "Global Aura Appearance",
        "Opens the global Aura icon appearance: shape, border, shadow, colors and native Player weapon enchants. This frame's container Style stays here.")
    local workspaceHint = W.Text(top,
        "Aura Options, Ordering and Aura Style belong to this UnitFrame. Global icon appearance: Appearance > Aura Style.",
        16, footerY - 8, sectionW - 198, T.colors.muted)
    M.TrackRefresh(ctx, function()
        workspaceHint:SetText(normalLane and UnitDispelRequested(unit) and not UnitAuraSensorEnabled(unit)
            and UNIT_AURA_DISPEL_WARNING
            or "Aura Options, Ordering and Aura Style belong to this UnitFrame. Global icon appearance: Appearance > Aura Style.")
    end)

    if normalLane then
        SetCurrentLane("auraStyleGFLane", currentTab)
        SetCurrentLane("auraFilterLane", currentTab)
        if currentTool == "style" then
            BuildUnitStyle(ctx, auraBuilder, unit, { embeddedUnitPreview = true })
        elseif currentTool == "behavior" then
            BuildUnitOrdering(ctx, auraBuilder, unit, currentTab)
        elseif currentTool == "filters" then
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
    local styleItem = item
    local function Apply(reason, rebuild)
        ApplyUnit(ctx, unit, reason or "AURAS3_CUSTOM_CONTAINER", rebuild == true)
        if type(ctx._auraAppearancePreviewRefresh) == "function" then ctx._auraAppearancePreviewRefresh() end
    end
    local function Grid(w, count, gap)
        gap = gap or 10
        return floor(((w - 48) - gap * (count - 1)) / count), gap
    end

    -- Every UnitFrame-local Custom Aura exposes the same rich styling
    -- accordions, tailored to its aura type. Dots additionally expose Pandemic;
    -- all containers retain their Full-Frame effect controls.
    if tool == "style" then
        M.BuildAuras3CompactCustomWorkspace(ctx, b, unit, index, "appearance")
        M.BuildAuras3CompactCustomWorkspace(ctx, b, unit, index, "effect")
        return
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
        local predefinedScroll = CreateFrame("ScrollFrame", nil, section)
        predefinedScroll:SetPoint("TOPLEFT", section, "TOPLEFT", 24, -108)
        predefinedScroll:SetSize(inner - 20, 184)
        local predefinedChild = CreateFrame("Frame", nil, predefinedScroll)
        predefinedChild:SetSize(inner - 44, max(184, #predefined * 30))
        predefinedScroll:SetScrollChild(predefinedChild)
        M._StyleNestedAuraScrollFrame(predefinedScroll, section, 30)
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
            predefinedStatus:SetText(M.Format("%d / %d predefined enabled", enabledCount, #predefined)
                .. MatchSuffix(query, visibleCount))
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
        local customInput = BindTextInput(ctx, section, "Track a buff - Spell ID, link, or name", 24, -322, max(140, inner - 132),
            function() return customInputValue end,
            function(value) customInputValue = value or "" end,
            false, AuraControlMeta(ctx, "custom-container.player-defensives.custom-id", "ephemeral"))
        local addCustom = ActionButton(section, "Add buff", 108)
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
        RegisterAuraTextAction(ctx, addCustom, customInput, "Add buff",
            customActionPath .. ".defensives.custom-id.add", {
                actionKey = "aura_custom_whitelist_add_spell",
                actionFixedArgs = { scope = unit, index = index },
                actionInputArg = "value",
            })
        AddTooltip(customInput, "Exact aura tracking",
            "Enter a Spell ID, paste a spell link, or type a spell name. The visible helpful aura is matched even when its buff ID differs from the cast Spell ID.")
        local status = W.Text(section, "", 24, -392, inner, T.colors.accent)
        local empty = W.Text(section, "No custom buffs added.", 24, -442, inner, T.colors.muted)
        local listScroll = CreateFrame("ScrollFrame", nil, section)
        listScroll:SetPoint("TOPLEFT", section, "TOPLEFT", 24, -418)
        listScroll:SetSize(inner - 20, 118)
        local listChild = CreateFrame("Frame", nil, listScroll)
        listChild:SetSize(inner - 44, 104)
        listScroll:SetScrollChild(listChild)
        M._StyleNestedAuraScrollFrame(listScroll, section, 32)
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
            status:SetText(M.Format("%d predefined enabled · %d custom · click a custom entry to remove",
                enabledPredefined, #entries) .. MatchSuffix(query, #visible))
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
        local section = b:Section("Dots on target", 430)
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
        AddTooltip(dropdown, "Target DoT", "Curated Retail 12.0+ and 12.1 DoT auras. Tracking is restricted to this UnitFrame's unit and your own aura source; Boss settings bind separately to boss1 through boss5.")
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
        local empty = W.Text(section, "No DoT selected. Choose one above or add a custom Spell ID.", 24, -288, inner, T.colors.muted)
        local listScroll = CreateFrame("ScrollFrame", nil, section)
        listScroll:SetPoint("TOPLEFT", section, "TOPLEFT", 24, -236)
        listScroll:SetSize(inner - 20, 164)
        local listChild = CreateFrame("Frame", nil, listScroll)
        listChild:SetSize(inner - 44, 164)
        listScroll:SetScrollChild(listChild)
        M._StyleNestedAuraScrollFrame(listScroll, section, 32)
        local rows = {}
        local function EnsureRow(i)
            local row = rows[i]
            if row then return row end
            row = CreateFrame("Frame", nil, listChild)
            row:SetPoint("TOPLEFT", listChild, "TOPLEFT", 0, -((i - 1) * 34))
            row:SetPoint("TOPRIGHT", listChild, "TOPRIGHT", 0, -((i - 1) * 34))
            row:SetHeight(30)
            if T.ApplyBackdrop then T.ApplyBackdrop(row, T.colors.panel2, T.colors.cardBorder or T.colors.borderSoft) end
            row.rank = T.Font(row, "GameFontDisableSmall", "", T.colors.accent)
            row.rank:SetPoint("LEFT", row, "LEFT", 7, 0)
            row.rank:SetWidth(24)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetPoint("LEFT", row.rank, "RIGHT", 3, 0)
            row.icon:SetSize(20, 20)
            row.text = T.Font(row, "GameFontHighlightSmall", "", T.colors.text)
            row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
            row.up = ActionButton(row, "Up", 38)
            row.up:SetPoint("RIGHT", row, "RIGHT", -84, 0)
            row.down = ActionButton(row, "Down", 48)
            row.down:SetPoint("LEFT", row.up, "RIGHT", 3, 0)
            row.remove = ActionButton(row, "X", 30, "danger")
            row.remove:SetPoint("LEFT", row.down, "RIGHT", 3, 0)
            row.text:SetPoint("RIGHT", row.up, "LEFT", -8, 0)
            row.up:SetScript("OnClick", function()
                if row._spellID and Model.MoveCustomContainerSpell(unit, index, row._spellID, -1) then
                    Apply("AURAS3_TARGET_DOT_PRIORITY", true)
                    Rebuild(ctx)
                end
            end)
            row.down:SetScript("OnClick", function()
                if row._spellID and Model.MoveCustomContainerSpell(unit, index, row._spellID, 1) then
                    Apply("AURAS3_TARGET_DOT_PRIORITY", true)
                    Rebuild(ctx)
                end
            end)
            row.remove:SetScript("OnClick", function()
                if row._spellID and Model.RemoveCustomContainerSpell(unit, index, row._spellID) then
                    Apply("AURAS3_TARGET_DOT_REMOVE", true)
                    Rebuild(ctx)
                end
            end)
            AddTooltip(row.up, "Move up", "Raises this DoT in the fixed priority order.")
            AddTooltip(row.down, "Move down", "Lowers this DoT in the fixed priority order.")
            AddTooltip(row.remove, "Remove DoT", "Stops tracking this DoT.")
            AddTooltip(row, "Drag to reorder", "Drag this row to a new position. Reordering activates Custom Priority.")
            ConfigureAuraSpellPriorityDrag(row, row, listChild, 34, function(spellID, target)
                if Model.MoveCustomContainerSpellToIndex(unit, index, spellID, target) then
                    Model.EnableCustomContainerSpellPriority(unit, index)
                    Apply("AURAS3_TARGET_DOT_PRIORITY", true)
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
            local customPriority = tostring(item.placed.sortMethod or ""):upper() == "CUSTOM_PRIORITY"
            status:SetText(M.Format("%d tracked DoTs", #entries)
                .. (customPriority and query ~= "" and Tr(" - clear Search to reorder")
                    or customPriority and Tr(" - dynamic priority active")
                    or Tr(" - drag to set Custom Priority"))
                .. MatchSuffix(query, #visible))
            empty:SetText(#entries == 0 and Tr("No DoT selected. Choose one above or add a custom Spell ID.")
                or M.Format(Tr("No results for \"%s\"."), query))
            empty:SetShown(#visible == 0)
            listScroll:SetShown(#visible > 0)
            listChild:SetHeight(max(164, #visible * 34))
            for i = 1, max(#rows, #visible) do
                local row, entry = rows[i], visible[i]
                if entry then
                    row = EnsureRow(i)
                    row._spellID = entry.spellID
                    row.rank:SetText("#" .. tostring(entry.priority or i))
                    row.icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                    row.text:SetText(entry.text or tostring(entry.spellID))
                    RegisterAuraControl(ctx, row.remove, "Remove " .. (entry.text or tostring(entry.spellID)), "button",
                        customActionPath .. ".dots.entry." .. AuraCatalogToken(entry.spellID) .. ".remove", "action")
                    RegisterAuraControl(ctx, row.up, "Raise " .. (entry.text or tostring(entry.spellID)), "button",
                        customActionPath .. ".dots.entry." .. AuraCatalogToken(entry.spellID) .. ".up", "action")
                    RegisterAuraControl(ctx, row.down, "Lower " .. (entry.text or tostring(entry.spellID)), "button",
                        customActionPath .. ".dots.entry." .. AuraCatalogToken(entry.spellID) .. ".down", "action")
                    if type(W.SetControlsEnabled) == "function" then
                        W.SetControlsEnabled({ row.up }, customPriority and query == "" and (entry.priority or i) > 1)
                        W.SetControlsEnabled({ row.down }, customPriority and query == "" and (entry.priority or i) < #entries)
                    end
                    row._entryCount = #entries
                    row._displayIndex = i
                    row._dragEnabled = query == "" and #entries > 1
                    row:Show()
                elseif row then row._spellID = nil; row._displayIndex = nil; row._dragEnabled = nil; row:Hide() end
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
        -- Whole sentences per lane: inserting the noun with %s breaks declension in
        -- German and Russian. `auraNoun` itself stays raw - it feeds Assistant action ids.
        local isDebuff = auraType == "DEBUFF"
        local addLabel = isDebuff and Tr("Add debuff") or Tr("Add buff")
        local trackHint = isDebuff and Tr("Track a debuff - Spell ID, link, or name")
            or Tr("Track a buff - Spell ID, link, or name")
        local addBody = isDebuff and Tr("Adds this exact debuff to the custom container.")
            or Tr("Adds this exact buff to the custom container.")
        local removeBody = isDebuff and Tr("Stops tracking this debuff in the custom container.")
            or Tr("Stops tracking this buff in the custom container.")
        W.Text(section, auraType, 24, -36, 58, T.colors.accent)
        W.Text(section, Tr(NATIVE_EXACT_AURA_FILTERS_TEXT), 88, -36, inner - 64, T.colors.muted)
        local inputValue = ""
        local inputW = max(140, min(floor(inner * 0.62), inner - 120))
        local input = BindTextInput(ctx, section, trackHint, 24, -76, inputW,
            function() return inputValue end, function(value) inputValue = value or "" end,
            false, AuraControlMeta(ctx, "custom-container.whitelist.input", "ephemeral"))
        local add = ActionButton(section, addLabel, 108, "primary")
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
        AddTooltip(add, addLabel, addBody)
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
        local listScroll = CreateFrame("ScrollFrame", nil, section)
        listScroll:SetPoint("TOPLEFT", section, "TOPLEFT", 24, -214)
        listScroll:SetSize(inner - 20, 190)
        local listChild = CreateFrame("Frame", nil, listScroll)
        listChild:SetSize(inner - 44, 190)
        listScroll:SetScrollChild(listChild)
        M._StyleNestedAuraScrollFrame(listScroll, section, 44)
        local rows = {}
        local function EnsureRow(i)
            local row = rows[i]
            if row then return row end
            row = CreateFrame("Frame", nil, listChild)
            row:SetPoint("TOPLEFT", listChild, "TOPLEFT", 0, -((i - 1) * 44))
            row:SetPoint("TOPRIGHT", listChild, "TOPRIGHT", 0, -((i - 1) * 44))
            row:SetHeight(40)
            if T.ApplyBackdrop then T.ApplyBackdrop(row, T.colors.panel2, T.colors.cardBorder or T.colors.borderSoft) end
            row.rank = T.Font(row, "GameFontDisableSmall", "", T.colors.accent)
            row.rank:SetPoint("LEFT", row, "LEFT", 7, 0)
            row.rank:SetWidth(24)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetPoint("LEFT", row.rank, "RIGHT", 3, 0)
            row.icon:SetSize(28, 28)
            row.name = T.Font(row, "GameFontHighlightSmall", "", T.colors.text)
            row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 9, -1)
            row.id = T.Font(row, "GameFontDisableSmall", "", T.colors.muted)
            row.id:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 9, 1)
            row.remove = ActionButton(row, "Remove", 80)
            row.remove:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            row.name:SetPoint("RIGHT", row.remove, "LEFT", -8, 0)
            row.remove:SetScript("OnClick", function()
                if row._spellID and Model.RemoveCustomContainerSpell(unit, index, row._spellID) then
                    Apply("AURAS3_CUSTOM_WHITELIST_REMOVE", true)
                    Rebuild(ctx)
                end
            end)
            AddTooltip(row.remove, "Remove from whitelist", removeBody)
            AddTooltip(row, "Drag to reorder", "Drag this row to a new position. Reordering activates Custom Priority.")
            ConfigureAuraSpellPriorityDrag(row, row, listChild, 44, function(spellID, target)
                if Model.MoveCustomContainerSpellToIndex(unit, index, spellID, target) then
                    Model.EnableCustomContainerSpellPriority(unit, index)
                    Apply("AURAS3_CUSTOM_PRIORITY", true)
                    Rebuild(ctx)
                end
            end)
            rows[i] = row
            return row
        end
        refreshList = function()
            local entries = Model.CustomContainerSpellEntries(unit, index)
            local query = tostring(searchValue or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
            local customPriority = tostring(item.placed.sortMethod or ""):upper() == "CUSTOM_PRIORITY"
            local visible = {}
            for i = 1, #entries do
                local entry = entries[i]
                local haystack = (tostring(entry.text or "") .. " " .. tostring(entry.spellID or "")):lower()
                if query == "" or haystack:find(query, 1, true) then visible[#visible + 1] = entry end
            end
            status:SetText(tostring("Tracked ") .. auraPlural .. " (" .. tostring(#entries) .. " of 40)"
                .. (customPriority and query ~= "" and Tr(" - clear Search to reorder")
                    or customPriority and Tr(" - dynamic priority active")
                    or Tr(" - drag to set Custom Priority"))
                .. MatchSuffix(query, #visible))
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
                    row.rank:SetText("#" .. tostring(entry.priority or i))
                    row.icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                    local name = tostring(entry.text or entry.spellID or "Spell"):gsub("%s*%(#%d+%)$", "")
                    row.name:SetText(name)
                    row.id:SetText(tostring("Spell ID ") .. tostring(entry.spellID))
                    RegisterAuraControl(ctx, row.remove, "Remove " .. name, "button",
                        customActionPath .. ".whitelist.entry." .. AuraCatalogToken(entry.spellID) .. ".remove", "action")
                    row._entryCount = #entries
                    row._displayIndex = i
                    row._dragEnabled = query == "" and #entries > 1
                    row:Show()
                elseif row then row._spellID = nil; row._displayIndex = nil; row._dragEnabled = nil; row:Hide() end
            end
        end
        M.TrackRefresh(ctx, refreshList)
        return
    end

    if tool == "filters" then
        if isPlayerDefensives or isTargetDots then
            local section = b:Section(containerLabel .. " Filters", 160)
            local w = section._msuf2Width or b.width or 720
            local inner = w - 48
            local hidePermanent = BindSwitch(ctx, section, "Hide permanent", 24, -40, inner,
                function() return item.filters.hidePermanent == true end,
                function(value)
                    item.filters.hidePermanent = value == true
                    Apply("AURAS3_CUSTOM_HIDE_PERMANENT", true)
                end,
                AuraControlMeta(ctx, "custom-container.filters.hide-permanent"))
            AddTooltip(hidePermanent, "Hide permanent auras",
                "Always excludes auras without a duration.")
            local maxDuration = ConfigureMaxDurationSlider(BindSlider(ctx, section, "Maximum duration",
                24, -92, 0, 180, 1, inner,
                function() return min(180, max(0, tonumber(item.filters.maxDuration) or 0)) end,
                function(value)
                    item.filters.maxDuration = Round(min(180, max(0, tonumber(value) or 0)))
                    Apply("AURAS3_CUSTOM_MAX_DURATION", true)
                end,
                AuraControlMeta(ctx, "custom-container.filters.max-duration", nil, {
                    assistantDisposition = "compound",
                    assistantDispositionReason = "The native candidate-filter duration limit has no Assistant setting contract yet.",
                })))
            M.TrackRefresh(ctx, function()
                W.SetControlEnabled(hidePermanent, true)
                W.SetControlEnabled(maxDuration, true)
            end)
            return
        end
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
        local optionRows = max(1, ceil(#specs / 4))
        local section = b:Section(containerLabel .. " Filters", 160 + optionRows * 32)
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
        local maxDuration = ConfigureMaxDurationSlider(BindSlider(ctx, section, "Maximum duration", 24,
            -76 - optionRows * 32, 0, 180, 1, w - 48,
            function() return min(180, max(0, tonumber(item.filters.maxDuration) or 0)) end,
            function(value)
                item.filters.maxDuration = Round(min(180, max(0, tonumber(value) or 0)))
                Apply("AURAS3_CUSTOM_MAX_DURATION", true)
            end,
            AuraControlMeta(ctx, "custom-container.filters.max-duration", nil, {
                assistantDisposition = "compound",
                assistantDispositionReason = "The native candidate-filter duration limit has no Assistant setting contract yet.",
            })))
        M.TrackRefresh(ctx, function()
            W.SetControlEnabled(master, true)
            W.SetControlEnabled(hidePermanent, true)
            W.SetControlEnabled(maxDuration, true)
            W.SetControlsEnabled(controls, item.filters.enabled ~= false)
        end)
        return
    end

    if tool == "layout" then
        local layoutTitle = M.Format("%s Layout", Tr(containerLabel))
        local section = b:Section(layoutTitle, 190)
        M.AttachAuraFontsAndColors(section, layoutTitle, unit)
        local w = section._msuf2Width or b.width or 720
        local col3, gap3 = Grid(w, 3)
        BindDropdown(ctx, section, "Anchor", 24, -34, Model.AuraAnchorValues(), col3,
            function() return item.placed.anchor or "TOPRIGHT" end,
            function(value) item.placed.anchor = value or "TOPRIGHT"; Apply("AURAS3_CUSTOM_ANCHOR") end,
            AuraControlMeta(ctx, "custom-container.layout.anchor"))
        BindDropdown(ctx, section, "Growth", 24 + col3 + gap3, -34, Model.LaneGrowthValues(), col3,
            function() return item.placed.growth or "LEFTDOWN" end,
            function(value) item.placed.growth = value or "LEFTDOWN"; Apply("AURAS3_CUSTOM_GROWTH", true) end,
            AuraControlMeta(ctx, "custom-container.layout.growth"))
        local col4, gap4 = Grid(w, 4)
        local values = {
            { "Max", "max", 0, 40, 8 }, { "Size", "size", 8, 128, 24 },
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
        W.Text(section, "Position is controlled by the colored aura handle in Preview.", 24 + col4 + gap4, -154, col4 * 3 + gap4 * 2, T.colors.muted)
        return
    end

    if tool == "appearance" then
        -- Every Custom container, including Player Defensives and Dots on
        -- Target, binds visual controls to this UnitFrame-owned record.
        local item = styleItem
        -- One accordion sub-section per topic, mirroring the Buff/Debuff lane
        -- style sections. Assistant semantic paths keep the historical
        -- "appearance" segment so the generated control schema stays stable.
        local function StyleGrid(section)
            local w = section._msuf2Width or b.width or 720
            local col4, gap = Grid(w, 4)
            local function X(col) return 24 + (col - 1) * (col4 + gap) end
            local function Number(label, col, y, minValue, maxValue, key, fallback, afterSet)
                return BindSlider(ctx, section, label, X(col), y, minValue, maxValue, 1, col4,
                    function() return tonumber(item.placed[key]) or fallback end,
                    function(value)
                        item.placed[key] = tonumber(value) or fallback
                        Apply("AURAS3_CUSTOM_APPEARANCE_" .. key:upper())
                        if type(afterSet) == "function" then afterSet() end
                    end,
                    AuraControlMeta(ctx, "custom-container.appearance." .. AuraCatalogToken(key)))
            end
            return col4, X, Number
        end
        local function GateControls(readEnabled, controls)
            M.TrackRefresh(ctx, function() W.SetControlsEnabled(controls, readEnabled()) end)
        end

        local harmfulContainer = isTargetDots or tostring(item.auraType or "BUFF"):upper() == "DEBUFF"
        local frameBasics = b:CollapsibleSection(CustomStyleSectionId(index, "frame_basics"), "Frame Basics", 220, true)
        local frameBasicsWidth = frameBasics._msuf2Width or b.width or 720
        local frameBasicsGap = 10
        local frameBasicsCol = max(180, floor((frameBasicsWidth - 48 - frameBasicsGap) / 2))
        local frameBasicsRightX = 24 + frameBasicsCol + frameBasicsGap
        BindSlider(ctx, frameBasics, "Icon Zoom (%)", 24, -48, 100, 200, 1, frameBasicsCol,
            function() return tonumber(item.placed.iconZoom) or 100 end,
            function(value)
                item.placed.iconZoom = tonumber(value) or 100
                Apply("AURAS3_CUSTOM_APPEARANCE_ICONZOOM")
            end,
            AuraControlMeta(ctx, "custom-container.appearance.icon-zoom"))
        AddAuraTooltipHelp(BindSwitch(ctx, frameBasics, "Tooltip", frameBasicsRightX, -48, frameBasicsCol,
            function() return item.placed.showTooltip ~= false end,
            function(value) item.placed.showTooltip = value == true; Apply("AURAS3_CUSTOM_TOOLTIP") end,
            AuraControlMeta(ctx, "custom-container.appearance.tooltip")))
        BindSlider(ctx, frameBasics, "Opacity", 24, -106, 10, 100, 5, frameBasicsCol,
            function() return floor(((tonumber(item.placed.alpha) or 1) * 100) + 0.5) end,
            function(value) item.placed.alpha = (tonumber(value) or 100) / 100; Apply("AURAS3_CUSTOM_ALPHA") end,
            AuraControlMeta(ctx, "custom-container.appearance.opacity"))
        BindSlider(ctx, frameBasics, "Lane Padding", 24, -164, 0, 16, 1, frameBasicsCol,
            function() return tonumber(item.placed.stylePadding) or 0 end,
            function(value) item.placed.stylePadding = tonumber(value) or 0; Apply("AURAS3_CUSTOM_STYLE_PADDING") end,
            AuraControlMeta(ctx, "custom-container.appearance.style-padding"))
        if harmfulContainer then
            BindDropdown(ctx, frameBasics, "Dispel-type Border", frameBasicsRightX, -106,
                DEBUFF_TYPE_BORDER_MODE_VALUES, frameBasicsCol,
                function() return item.placed.debuffTypeBorderMode or "OFF" end,
                function(value) item.placed.debuffTypeBorderMode = value or "OFF"; Apply("AURAS3_CUSTOM_DEBUFF_TYPE_BORDER") end,
                AuraControlMeta(ctx, "custom-container.appearance.dispel-type-border"))
        end

        local pandemic
        if isTargetDots then
            pandemic = b:CollapsibleSection(CustomStyleSectionId(index, "pandemic"), "Pandemic Warning & Style", 248, false)
            local pandemicCol, pandemicX, PandemicNumber = StyleGrid(pandemic)
            local pandemicControls = {}
            local pandemicWarning = W.Text(pandemic,
                "PERFORMANCE WARNING (12.1): Blizzard can run an OnUpdate every frame on each visible aura button for the full aura while it has a calculated pandemic window, not only while the warning is shown. Enable only if you accept this potentially high combat cost.",
                24, -96, (pandemic._msuf2Width or b.width or 720) - 48, { 1.00, 0.38, 0.18, 1 })
            if pandemicWarning.SetWordWrap then pandemicWarning:SetWordWrap(true) end
            local RefreshPandemicState
            local pandemicToggle = BindSwitch(ctx, pandemic, "Show Pandemic State", pandemicX(1), -42,
                pandemicCol, function() return item.placed.pandemicEnabled == true end,
                function(value)
                    item.placed.pandemicEnabled = value == true
                    Apply("AURAS3_TARGET_DOT_PANDEMIC", true)
                    if RefreshPandemicState then RefreshPandemicState() end
                end,
                AuraControlMeta(ctx, "custom-container.appearance.pandemic.enabled"))
            AddTooltip(pandemicToggle, "12.1 Pandemic state",
                "Disabled by default. Blizzard's native implementation enables a per-frame OnUpdate for each visible aura button as soon as that aura has a calculated pandemic window; this can begin before the warning becomes visible.")
            pandemicControls[#pandemicControls + 1] = BindDropdown(ctx, pandemic, "Style", pandemicX(2), -42,
                M.AURA_PANDEMIC_STYLE_VALUES, pandemicCol,
                function() return item.placed.pandemicStyle or "BORDER" end,
                function(value) item.placed.pandemicStyle = value or "BORDER"; Apply("AURAS3_TARGET_DOT_PANDEMIC_STYLE", true) end,
                AuraControlMeta(ctx, "custom-container.appearance.pandemic.style"))
            pandemicControls[#pandemicControls + 1] = BindDropdown(ctx, pandemic, "Blend", pandemicX(3), -42,
                M.AURA_PANDEMIC_BLEND_VALUES, pandemicCol,
                function() return item.placed.pandemicBlend or "ADD" end,
                function(value) item.placed.pandemicBlend = value == "BLEND" and "BLEND" or "ADD"; Apply("AURAS3_TARGET_DOT_PANDEMIC_BLEND", true) end,
                AuraControlMeta(ctx, "custom-container.appearance.pandemic.blend"))
            -- The ::: shortcut is the section's only visible way into the color picker,
            -- so this swatch is never laid out. It still exists and stays bound: it is
            -- the control the Assistant and menu search resolve for this setting, and
            -- unlike the status text colors there is no Colors page surface carrying a
            -- per-custom-container pandemic color to fall back to.
            -- Attached before M.BindColor so the explicit shortcut owns the section:
            -- a shortcut generated by BindColor would be replaced by later color
            -- controls, and it could not serve as a stable search anchor.
            -- Deliberately kept out of pandemicControls: a disabled owner drops out of
            -- the shortcut's relevance check, which would make the ::: come and go with
            -- the toggle instead of staying put.
            local pandemicColor = W.Color(pandemic, "Color")
            pandemicColor._msuf2ContextColorAllowDisabled = true
            W.SetControlShown(pandemicColor, false)
            local pandemicColorShortcut
            if W.AttachContextColorShortcut then
                pandemicColorShortcut = W.AttachContextColorShortcut(pandemic, {
                    historyLabel = "Pandemic color",
                    historySource = "menu:custom-auras-pandemic-color",
                    getTargets = function() return { pandemicColor } end,
                })
            end
            local pandemicColorMeta = AuraControlMeta(ctx, "custom-container.appearance.pandemic.color")
            -- Search must land on the shortcut; highlighting the hidden swatch would
            -- point the player at nothing.
            pandemicColorMeta.anchor = pandemicColorShortcut or nil
            M.BindColor(ctx, pandemicColor,
                function()
                    local color = item.placed.pandemicColor or { 1, 0.24, 0.08 }
                    return color[1] or 1, color[2] or 0.24, color[3] or 0.08
                end,
                function(r, g, blue)
                    item.placed.pandemicColor = { r, g, blue }
                    Apply("AURAS3_TARGET_DOT_PANDEMIC_COLOR", true)
                end,
                pandemicColorMeta)
            pandemicControls[#pandemicControls + 1] = PandemicNumber("Thickness", 1, -174, 1, 12,
                "pandemicThickness", 2)
            pandemicControls[#pandemicControls + 1] = PandemicNumber("Padding", 2, -174, -8, 16,
                "pandemicPadding", 1)
            pandemicControls[#pandemicControls + 1] = BindSlider(ctx, pandemic, "Border Opacity", pandemicX(3), -174,
                5, 100, 5, pandemicCol,
                function() return floor(((tonumber(item.placed.pandemicBorderAlpha) or 1) * 100) + 0.5) end,
                function(value) item.placed.pandemicBorderAlpha = (tonumber(value) or 100) / 100; Apply("AURAS3_TARGET_DOT_PANDEMIC_BORDER_ALPHA", true) end,
                AuraControlMeta(ctx, "custom-container.appearance.pandemic.border-opacity"))
            pandemicControls[#pandemicControls + 1] = BindSlider(ctx, pandemic, "Tint Opacity", pandemicX(4), -174,
                5, 100, 5, pandemicCol,
                function() return floor(((tonumber(item.placed.pandemicTintAlpha) or 0.22) * 100) + 0.5) end,
                function(value) item.placed.pandemicTintAlpha = (tonumber(value) or 22) / 100; Apply("AURAS3_TARGET_DOT_PANDEMIC_TINT_ALPHA", true) end,
                AuraControlMeta(ctx, "custom-container.appearance.pandemic.tint-opacity"))
            RefreshPandemicState = function()
                local enabled = item.placed.pandemicEnabled == true
                W.SetControlsEnabled(pandemicControls, enabled)
                pandemicWarning:SetShown(enabled)
                if W.SetCollapsibleBadges then
                    W.SetCollapsibleBadges(pandemic, { {
                        text = enabled and M.Format("On / %s", ChoiceLabel(M.AURA_PANDEMIC_STYLE_VALUES,
                            item.placed.pandemicStyle or "BORDER", "Border")) or Tr("Off"),
                        kind = enabled and "accent" or "muted", showWhenClosed = true,
                    } })
                end
            end
            M.TrackRefresh(ctx, RefreshPandemicState)
            RefreshPandemicState()
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
        local durationBarControls
        local function RefreshCustomDurationBarState()
            local placed = item.placed
            local enabled = placed.showDurationBar == true
            if durationBarControls then W.SetControlsEnabled(durationBarControls, enabled) end
            if W.SetCollapsibleBadges then
                W.SetCollapsibleBadges(durationBar, {{
                    text = enabled and (tostring(Round(tonumber(placed.durationBarHeight) or 2)) .. "px / " .. ChoiceLabel(DURATION_BAR_DISPLAY_VALUES, placed.durationBarDisplay or "BAR_ONLY", "Bar Only") .. " / " .. ChoiceLabel(DURATION_BAR_POSITION_VALUES, placed.durationBarPosition or "BOTTOM", "Bottom")) or "Off",
                    kind = enabled and "accent" or "muted", showWhenClosed = true,
                }})
            end
        end
        BindSwitch(ctx, durationBar, "Duration bar", barX(1), -42, barCol, function() return item.placed.showDurationBar == true end,
            function(value)
                item.placed.showDurationBar = value == true
                Apply("AURAS3_CUSTOM_DURATION_BAR")
                RefreshCustomDurationBarState()
            end,
            AuraControlMeta(ctx, "custom-container.appearance.duration-bar"))
        durationBarControls = {
            BarNumber("Bar height", 1, -76, 1, 16, "durationBarHeight", 2, RefreshCustomDurationBarState),
            BindDropdown(ctx, durationBar, "Bar display", barX(2), -76, DURATION_BAR_DISPLAY_VALUES, barCol,
                function() return item.placed.durationBarDisplay or "BAR_ONLY" end,
                function(value)
                    item.placed.durationBarDisplay = value or "BAR_ONLY"
                    Apply("AURAS3_CUSTOM_DURATION_DISPLAY")
                    RefreshCustomDurationBarState()
                end,
                AuraControlMeta(ctx, "custom-container.appearance.duration-display")),
            BindDropdown(ctx, durationBar, "Bar position", barX(3), -76, DURATION_BAR_POSITION_VALUES, barCol,
                function() return item.placed.durationBarPosition or "BOTTOM" end,
                function(value)
                    item.placed.durationBarPosition = value or "BOTTOM"
                    Apply("AURAS3_CUSTOM_DURATION_POSITION")
                    RefreshCustomDurationBarState()
                end,
                AuraControlMeta(ctx, "custom-container.appearance.duration-position")),
            BindDropdown(ctx, durationBar, "Bar fill", barX(4), -76, DURATION_BAR_DIRECTION_VALUES, barCol,
                function() return item.placed.durationBarDirection or "REMAINING" end,
                function(value)
                    item.placed.durationBarDirection = value or "REMAINING"
                    Apply("AURAS3_CUSTOM_DURATION_DIRECTION")
                    RefreshCustomDurationBarState()
                end,
                AuraControlMeta(ctx, "custom-container.appearance.duration-direction")),
        }

        if W.SetCollapsibleBadges then
            local function ToggleBadge(label, enabled)
                return { text = label .. (enabled and " On" or " Off"), kind = enabled and "accent" or "muted", showWhenClosed = true }
            end
            M.TrackRefresh(ctx, function()
                local placed = item.placed
                local zoom = Round(tonumber(placed.iconZoom) or 100)
                local opacity = floor(((tonumber(placed.alpha) or 1) * 100) + 0.5)
                local frameBasicsBadges = {
                    { text = M.Format("Zoom %d%%", zoom), kind = "info", showWhenClosed = true },
                    ToggleBadge("Tooltip", placed.showTooltip ~= false),
                }
                if opacity < 100 then
                    frameBasicsBadges[#frameBasicsBadges + 1] = { text = M.Format("Opacity %d%%", opacity), kind = "info", showWhenClosed = true }
                end
                if harmfulContainer then
                    local borderMode = tostring(placed.debuffTypeBorderMode or "OFF"):upper()
                    frameBasicsBadges[#frameBasicsBadges + 1] = {
                        text = "Border " .. ChoiceLabel(DEBUFF_TYPE_BORDER_MODE_VALUES, borderMode, borderMode),
                        kind = borderMode == "OFF" and "muted" or "accent", showWhenClosed = true,
                    }
                end
                W.SetCollapsibleBadges(frameBasics, frameBasicsBadges)

                local stackEnabled = placed.showStacks ~= false
                W.SetCollapsibleBadges(stack, {{
                    text = stackEnabled and (tostring(Round(tonumber(placed.stackSize) or 14)) .. "px / " .. AnchorLabel(placed.stackAnchor or "BOTTOMRIGHT")) or "Off",
                    kind = stackEnabled and "accent" or "muted", showWhenClosed = true,
                }})

                local cooldownEnabled = placed.showCooldown ~= false
                local decimal = Round(tonumber(placed.cooldownDecimalSeconds) or 3)
                W.SetCollapsibleBadges(cooldown, {
                    { text = cooldownEnabled and (tostring(Round(tonumber(placed.cooldownSize) or 14)) .. "px / " .. AnchorLabel(placed.cooldownAnchor or "CENTER") .. " / " .. ChoiceLabel(COOLDOWN_SWIPE_DIRECTION_VALUES, placed.cooldownSwipeReverse == true and "REVERSE" or "NORMAL", "Normal")) or "Off", kind = cooldownEnabled and "accent" or "muted", showWhenClosed = true },
                    { text = decimal > 0 and M.Format("Decimals below %ds", decimal) or Tr("Whole seconds"), kind = "info", showWhenClosed = true },
                })

                RefreshCustomDurationBarState()
            end)
        end
        return
    end

    if tool == "effect" then
        local item = styleItem
        local section = b:CollapsibleSection(CustomStyleSectionId(index, "full_frame"), "Full-Frame Effect", 210, false)
        local w = section._msuf2Width or b.width or 720
        local col3, gap = Grid(w, 3)
        BindDropdown(ctx, section, "Effect", 24, -34, CUSTOM_FRAME_EFFECTS, w - 48,
            function() return item.frame.type or "none" end,
            function(value) item.frame.type = value or "none"; Apply("AURAS3_CUSTOM_EFFECT") end,
            AuraControlMeta(ctx, "custom-container.effect.type"))
        local color = W.Color(section, "Color")
        M.BindColor(ctx, color,
            function() local c = item.frame.color; return c[1] or 0.69, c[2] or 0.50, c[3] or 0.88 end,
            function(r, g, blue) local a = item.frame.color[4] or 0.8; item.frame.color = { r, g, blue, a }; Apply("AURAS3_CUSTOM_EFFECT_COLOR") end,
            AuraControlMeta(ctx, "custom-container.effect.color"))
        color:Hide()
        if color._msuf2Title then
            color._msuf2Title:Hide()
            color._msuf2Title._msuf2AlwaysHidden = true
        end
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
        if isTargetDots then
            local pandemicOnly = BindSwitch(ctx, section, "Only during Pandemic window", 24 + col3 + gap, -150,
                col3 * 2 + gap, function() return item.frame.onlyInPandemicWindow == true end,
                function(value)
                    item.frame.onlyInPandemicWindow = value == true
                    Apply("AURAS3_TARGET_DOT_EFFECT_PANDEMIC_ONLY", true)
                end,
                AuraControlMeta(ctx, "custom-container.effect.only-during-pandemic-window"))
            AddTooltip(pandemicOnly, "Pandemic-only Full-Frame effect",
                "Shows this effect only while a tracked DoT is in its native Pandemic window. Multiple DoTs in Pandemic can intensify the same effect. Blizzard may run an OnUpdate on each visible aura button while its Pandemic timing is available.")
        end
        if W.SetCollapsibleBadges then
            M.TrackRefresh(ctx, function()
                local effectType = tostring(item.frame.type or "none")
                local badges = {{
                    text = ChoiceLabel(CUSTOM_FRAME_EFFECTS, effectType, effectType),
                    kind = effectType == "none" and "muted" or "accent", showWhenClosed = true,
                }}
                if isTargetDots and item.frame.onlyInPandemicWindow == true then
                    badges[#badges + 1] = { text = "Pandemic only", kind = "info", showWhenClosed = true }
                end
                W.SetCollapsibleBadges(section, badges)
            end)
        end
        return
    end

    if tool == "behavior" then
        local sortLane = (isTargetDots or tostring(item.auraType or "BUFF"):upper() == "DEBUFF") and "debuff" or "buff"
        local supportsCustomPriority = not isPlayerDefensives
        local section = b:Section("Ordering", 156)
        local w = section._msuf2Width or b.width or 720
        -- Keep every custom container's identity separate. Exact-ID custom
        -- containers can each persist their own CUSTOM_PRIORITY or ordinary
        -- sort mode without sharing a lane preset.
        local orderingPath = customActionPath .. ".ordering"
        local visibleOrderingPath = isTargetDots and "custom-container.dots-on-target.ordering"
            or (isPlayerDefensives and "custom-container.defensive-buffs.ordering" or orderingPath)
        local sortMethod = BindDropdown(ctx, section, "Sort By", 24, -48, AuraSortMethodValues(sortLane, supportsCustomPriority), w - 48,
            function() return NormalizeAuraSortMethodForLane(sortLane, item.placed.sortMethod, supportsCustomPriority) end,
            function(value)
                if supportsCustomPriority and value == "CUSTOM_PRIORITY"
                    and type(Model.EnableCustomContainerSpellPriority) == "function" then
                    Model.EnableCustomContainerSpellPriority(unit, index)
                else
                    item.placed.sortMethod = value or "DEFAULT"
                end
                Apply("AURAS3_CUSTOM_SORT_METHOD", supportsCustomPriority)
            end,
            AuraControlMetaAtVisiblePath(ctx,
                orderingPath .. "." .. sortLane .. "-sort-method",
                visibleOrderingPath .. "." .. sortLane .. "-sort-method"))
        AddTooltip(sortMethod, "Aura sorting", supportsCustomPriority
            and "Custom Priority packs active tracked auras into the configured order. Inactive entries leave no gap; drag the spell rows in Setup to change their priority."
            or "Only relevant sorting methods are shown for buffs and debuffs.")
        local sortDirection = BindDropdown(ctx, section, "Order", 24, -104, AURA_SORT_DIRECTION_VALUES, w - 48,
            function() return item.placed.sortReverse == true and "REVERSE" or "NORMAL" end,
            function(value) item.placed.sortReverse = value == "REVERSE"; Apply("AURAS3_CUSTOM_SORT_DIRECTION") end,
            AuraControlMetaAtVisiblePath(ctx,
                orderingPath .. ".sort-direction",
                visibleOrderingPath .. ".sort-direction"))
        AddTooltip(sortDirection, "Aura sort order", "Reversed flips the complete priority order.")
        if supportsCustomPriority and type(W.SetControlsEnabled) == "function" then
            M.TrackRefresh(ctx, function()
                W.SetControlsEnabled({ sortDirection },
                    NormalizeAuraSortMethodForLane(sortLane, item.placed.sortMethod, supportsCustomPriority) ~= "CUSTOM_PRIORITY")
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
        -- The 12.1 native aura buttons render their icon unmaskable; shaping
        -- was attempted exhaustively and reverted (2026-07-31). Keep users
        -- informed instead of letting them hunt for a shape option.
        W.Text(section, "Aura Style > Defensive Buffs can follow the frame portrait shape.", 24, -312, inner, T.colors.muted)
        W.Text(section, M.Format("Source: player buffs · %d / %d predefined enabled · %d custom · passive talent procs included",
        predefined, predefinedTotal, custom), 24, -344, inner, T.colors.muted)
        return
    end

    if isTargetDots then
        local section = b:Section("Dots on target Setup", 410)
        local w = section._msuf2Width or b.width or 720
        local inner = w - 48
        local enabled = BindSwitch(ctx, section, "Enabled", 24, -48, 112,
            function() return item.enabled == true end,
            function(value) item.enabled = value == true; Apply("AURAS3_TARGET_DOTS_ENABLE", true) end,
            AuraControlMeta(ctx, "custom-container.target-dots.enabled"))
        AddTooltip(enabled, "Enable tracked DoTs",
            "Tracks your selected harmful auras on this UnitFrame's unit. Boss frames use their own boss1 through boss5 unit token.")
        local portrait = BindSwitch(ctx, section, "Show DoTs at portrait position", 24, -86, 280,
            function() return item.portraitIcon == true end,
            function(value)
                item.portraitIcon = value == true
                Apply("AURAS3_TARGET_DOTS_PORTRAIT", true)
            end,
            AuraControlMeta(ctx, "custom-container.target-dots.portrait-icon"))
        AddTooltip(portrait, "Show DoTs at portrait position",
            "Replaces the normal DoT lane with portrait-sized icons. The first icon exactly follows this frame's portrait width, height, and shape.")
        local portraitMax = BindSlider(ctx, section, "Max portrait icons", 24, -128, 1, 8, 1, inner,
            function() return tonumber(item.portraitMaxIcons) or 1 end,
            function(value)
                item.portraitMaxIcons = max(1, min(8, floor((tonumber(value) or 1) + 0.5)))
                Apply("AURAS3_TARGET_DOTS_PORTRAIT_MAX", true)
            end,
            AuraControlMeta(ctx, "custom-container.target-dots.portrait-max-icons"))
        AddTooltip(portraitMax, "Max portrait icons",
            "Limits simultaneous DoT icons at the portrait from 1 to 8. Additional icons grow outward using this DoT lane's configured Growth direction.")
        local cooldownText = BindSwitch(ctx, section, "Show cooldown text on portrait", 24, -198, 280,
            function() return item.portraitCooldownText ~= false end,
            function(value)
                item.portraitCooldownText = value == true
                Apply("AURAS3_TARGET_DOTS_PORTRAIT_COOLDOWN", true)
            end,
            AuraControlMeta(ctx, "custom-container.target-dots.portrait-cooldown-text"))
        AddTooltip(cooldownText, "Show cooldown text on portrait",
            "Shows the tracked DoT's remaining duration over its portrait icon. Blizzard updates the duration natively.")
        local positionOnly = BindSwitch(ctx, section, "Use portrait position while portrait is off", 24, -236, 326,
            function() return item.portraitPositionWhenDisabled == true end,
            function(value)
                item.portraitPositionWhenDisabled = value == true
                Apply("AURAS3_TARGET_DOTS_PORTRAIT_POSITION", true)
            end,
            AuraControlMeta(ctx, "custom-container.target-dots.portrait-position-when-disabled"))
        AddTooltip(positionOnly, "Use portrait position while portrait is off",
            "Keeps the configured portrait size, position, and shape as an invisible anchor for tracked DoTs while the portrait itself is disabled.")
        local autoBlacklist = BindSwitch(ctx, section, "Auto-blacklist from Debuffs", 24, -274, 280,
            function() return item.autoBlacklistDebuffs ~= false end,
            function(value)
                item.autoBlacklistDebuffs = value == true
                Apply("AURAS3_TARGET_DOTS_AUTO_BLACKLIST", true)
            end,
            AuraControlMeta(ctx, "custom-container.target-dots.auto-blacklist-debuffs"))
        AddTooltip(autoBlacklist, "Auto-blacklist from Debuffs",
            "Hides this scope's selected DoT Spell IDs from the same UnitFrame's normal Debuff container while Dots on target is enabled. Blizzard's blacklist is SpellID-based, so the same spell cast by another player is hidden there too.")
        local reset = ActionButton(section, "Reset", 88)
        reset:SetPoint("TOPRIGHT", section, "TOPRIGHT", -24, -42)
        reset:SetScript("OnClick", function() Model.ResetCustomContainer(unit, index); Apply("AURAS3_TARGET_DOTS_RESET", true); Rebuild(ctx) end)
        RegisterAuraControl(ctx, reset, "Reset", "button", customActionPath .. ".setup.reset", "action", {
            actionKey = "reset_aura_custom_container", actionFixedArgs = { scope = unit, index = index },
        })
        local count = #Model.CustomContainerSpellEntries(unit, index)
        W.Text(section, M.Format("Source: this UnitFrame · Ownership: only mine · Harmful DoTs only · %d selected", count), 24, -324, inner, T.colors.muted)
        W.Text(section, "Display: " .. (item.portraitIcon == true and "portrait position" or "normal DoT lane"), 24, -356, inner, T.colors.muted)
        return
    end

    local setupW = b.width or 720
    local compactSetup = setupW < 680
    local section = b:Section(containerLabel .. " Setup", compactSetup and 184 or 132)
    local w = section._msuf2Width or setupW
    local inner = w - 48
    local enabled = BindSwitch(ctx, section, "Enabled", 24, compactSetup and -52 or -62, 106,
        function() return item.enabled == true end,
        function(value) item.enabled = value == true; Apply("AURAS3_CUSTOM_CONTAINER_ENABLE") end,
        AuraControlMeta(ctx, "custom-container.setup.enabled"))
    local resetW = 88
    local reset = ActionButton(section, "Reset", resetW)
    reset:SetPoint("TOPRIGHT", section, "TOPRIGHT", -24, compactSetup and -46 or -56)
    reset:SetScript("OnClick", function() Model.ResetCustomContainer(unit, index); Apply("AURAS3_CUSTOM_CONTAINER_RESET", true); Rebuild(ctx) end)
    RegisterAuraControl(ctx, reset, "Reset", "button", customActionPath .. ".setup.reset", "action", {
        actionKey = "reset_aura_custom_container",
        actionFixedArgs = { scope = unit, index = index },
    })

    local fieldX = compactSetup and 24 or 140
    local fieldY = compactSetup and -82 or -34
    local fieldRight = compactSetup and (w - 24) or (w - 24 - resetW - 12)
    local fieldGap = 12
    local fieldSpace = max(0, fieldRight - fieldX - fieldGap)
    local typeW = compactSetup and max(140, floor(fieldSpace * 0.34))
        or max(150, min(max(170, floor(inner * 0.18)), fieldSpace - 200))
    local nameW = compactSetup and max(120, fieldSpace - typeW)
        or max(120, min(max(260, floor(inner * 0.42)), fieldSpace - typeW))
    BindTextInput(ctx, section, "Container name", fieldX, fieldY, nameW,
        function() return item.name or ("Custom " .. tostring(index)) end,
        function(value) item.name = value ~= "" and value or ("Custom " .. tostring(index)); Apply("AURAS3_CUSTOM_CONTAINER_NAME") end,
        false, AuraControlMeta(ctx, "custom-container.setup.name"))
    BindDropdown(ctx, section, "Aura type", fieldX + nameW + fieldGap, fieldY, CUSTOM_AURA_TYPES, typeW,
        function() return item.auraType == "DEBUFF" and "DEBUFF" or "BUFF" end,
        function(value)
            local nextType = value == "DEBUFF" and "DEBUFF" or "BUFF"
            local prevType = item.auraType == "DEBUFF" and "DEBUFF" or "BUFF"
            -- A duration ceiling configured for one aura type must not survive
            -- the switch: since 6.09 it compiles for every lane and would
            -- silently hide long or permanent auras of the other type.
            if nextType ~= prevType and type(item.filters) == "table" then
                item.filters.maxDuration = nil
            end
            item.auraType = nextType
            Apply("AURAS3_CUSTOM_CONTAINER_TYPE", true)
            Rebuild(ctx)
        end,
        AuraControlMeta(ctx, "custom-container.setup.aura-type"))
    local count = #Model.CustomContainerSpellEntries(unit, index)
    W.Text(section, count == 1 and Tr("1 whitelisted spell · style remains live in Menu Preview and Edit Mode.")
        or M.Format("%d whitelisted spells · style remains live in Menu Preview and Edit Mode.", count), 24, compactSetup and -156 or -104, inner, T.colors.muted)
    M.TrackRefresh(ctx, function() W.SetControlEnabled(enabled, true) end)
end

local function BuildMovedAuraPage(ctx)
    local b = W.PageBuilder(ctx)
    b:GlobalStyleHeader("Aura Controls moved to Frames", "Layout, filters, lists and every container-specific Style live in each frame. Appearance > Aura Style owns only the global icon theme.", 96)
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
    W.Text(section, "Open the frame and expand Auras. Buffs and Debuffs contain their own layout, filters, blacklists and Style; Custom 1-3, Defensive Buffs and Dots on target expose controls appropriate to their content.", 24, -118, w - 48, T.colors.muted)
    FinishPage(ctx, b)
end

-- Old content/filter routes remain as compatibility landings. The Buff/Debuff
-- aliases open the matching global Appearance preview; individual Style stays on the
-- selected UnitFrame or GroupFrame page.
M.RegisterPage("auras3_buffs", { title = "Global Aura Appearance: Buffs", build = function(ctx) BuildAuraStyleLanePage(ctx, "buff") end, version = 25 })
M.RegisterPage("auras3_debuffs", { title = "Global Aura Appearance: Debuffs", build = function(ctx) BuildAuraStyleLanePage(ctx, "debuff") end, version = 25 })
M.RegisterPage("auras3_custom", { title = "MSUF Auras", build = BuildMovedAuraPage, version = 2 })
M.RegisterPage("auras3_styling", { title = "Aura Style", build = BuildAuraStylePage, version = 53 })
M.RegisterPage("auras3_filters", { title = "MSUF Auras", build = BuildMovedAuraPage, version = 31 })
