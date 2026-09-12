-- Shared Aura values and configuration readers; independent of page construction.
local _, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local EnsureDB = M.EnsureDB
local GP = M.GroupPage or {}
local VT, VTP = M.ValueTextList, M.ValueTextPairs
local floor = math.floor
local tonumber, tostring, type, pairs = tonumber, tostring, type, pairs

local AccessibleNumber = M.AccessibleNumber

local AURA_SCOPE_LABELS = { shared = "Shared", player = "Player", target = "Target", focus = "Focus", boss = "Boss", party = "Party", raid = "Raid / Mythic" }

local AURA_SCOPE_VALID = M.KeySetFromWords "shared player target focus boss party raid"

local AURA_GROUP_SCOPES = M.KeySetFromWords "party raid mythicraid"

local CUSTOM_FRAME_EFFECTS = VTP "none=None|healthtint=Health Tint|border=Border|glow=Glow|pulse=Pulse|namecolor=Name Overlay"

local DEBUFF_TYPE_BORDER_MODE_VALUES = VTP "OFF=Off|BORDER=Border|SYMBOL=Border + Symbol"

local COOLDOWN_SWIPE_DIRECTION_VALUES = VTP "NORMAL=Normal|REVERSE=Reverse"

local AURA_SORT_DIRECTION_VALUES = VTP "NORMAL=Normal|REVERSE=Reversed"

local BUFF_AURA_SORT_METHOD_VALUES = VTP "DEFAULT=Player & Priority First|BIG_DEFENSIVE=Other Defensives First|IMPORTANT_FIRST=Important First|EXPIRATION=Player First, Expiring Soon|EXPIRATION_ONLY=Expiring Soon|NAME=Player First, then Name|NAME_ONLY=Name|INSTANCE_ID=Arrival Order"

local DEBUFF_AURA_SORT_METHOD_VALUES = VTP "DEFAULT=Player & Priority First|UNIT_FRAME_DEBUFF=Debuff Type First|IMPORTANT_FIRST=Important First|EXPIRATION=Player First, Expiring Soon|EXPIRATION_ONLY=Expiring Soon|NAME=Player First, then Name|NAME_ONLY=Name|INSTANCE_ID=Arrival Order"

local CUSTOM_PRIORITY_AURA_SORT_METHOD_VALUES = VTP "CUSTOM_PRIORITY=Custom Priority|DEFAULT=Player & Priority First|UNIT_FRAME_DEBUFF=Debuff Type First|IMPORTANT_FIRST=Important First|EXPIRATION=Player First, Expiring Soon|EXPIRATION_ONLY=Expiring Soon|NAME=Player First, then Name|NAME_ONLY=Name|INSTANCE_ID=Arrival Order"

local DURATION_BAR_DISPLAY_VALUES = VTP "BAR_ONLY=Bar Only|OVERLAY=Icon + Bar"

local DURATION_BAR_POSITION_VALUES = VTP "BOTTOM=Bottom|TOP=Top"

local DURATION_BAR_DIRECTION_VALUES = VTP "REMAINING=Remaining|ELAPSED=Elapsed"

local function AURA_COOLDOWN_COLOR_REFERENCES()
    local general = EnsureDB().general
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

local NATIVE_EXACT_AURA_FILTERS_ENABLED = true

local NATIVE_EXACT_AURA_FILTERS_TEXT = "Exact Spell IDs are used when Blizzard exposes them."

local function Tr(text)
    if type(M.Tr) == "function" then return M.Tr(text) end
    return text
end

local function MatchSuffix(query, count)
    if query == nil or query == "" then return "" end
    return M.Format(" - %d matches", count)
end

local function Round(value)
    value = tonumber(value) or 0
    if value < 0 then return -floor((-value) + 0.5) end
    return floor(value + 0.5)
end

local NormalizeDebuffTypeBorderMode = _G.MSUF_NormalizeAuraDebuffTypeBorderMode

local function AurasMenuCombatLocked()
    if type(M.IsConfigCombatLocked) == "function" then return M.IsConfigCombatLocked() and true or false end
    if type(_G.MSUF_IsConfigCombatLocked) == "function" then return _G.MSUF_IsConfigCombatLocked() and true or false end
    return (_G.InCombatLockdown and _G.InCombatLockdown()) and true or false
end

local function CurrentScope()
    if type(M.EnsurePersistentMenuState) == "function" then M.EnsurePersistentMenuState() end
    local scope = M.auraScope or "shared"
    if scope == "mythicraid" then scope = "raid" end
    return AURA_SCOPE_VALID[scope] and scope or "shared"
end

local function IsGroupScope(scope)
    scope = scope or CurrentScope()
    return AURA_GROUP_SCOPES[scope] == true
end

local function ScopeLabel(scope)
    return AURA_SCOPE_LABELS[scope] or "Raid / Mythic"
end

local function CurrentLane(stateKey, defaultValue)
    local lane = M[stateKey] or defaultValue or "debuff"
    if lane ~= "buff" and lane ~= "debuff" then lane = defaultValue or "debuff" end
    return lane
end

local function SetCurrentLane(stateKey, lane)
    lane = lane == "buff" and "buff" or "debuff"
    M.SetMenuStateValue(stateKey, lane)
    if stateKey ~= "auraStyleGFLane" then M.SetMenuStateValue("auraStyleGFLane", lane) end
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

local function LaneMaxKey(kind)
    return kind == "buff" and "maxBuffs" or "maxDebuffs"
end

local function LaneSizeKey(kind)
    return kind == "buff" and "buffGroupIconSize" or "debuffGroupIconSize"
end

local function LaneDefaultMax(kind)
    return kind == "buff" and 8 or 12
end

local function GFAnchorValues()
    local values = GP.STATUS_ICON_ANCHORS or GP.AURA_ANCHORS
    if type(values) == "table" and #values > 0 then return values end
    return VT("CENTER", "Center", "TOPLEFT", "Top Left", "TOPRIGHT", "Top Right", "BOTTOMLEFT", "Bottom Left", "BOTTOMRIGHT", "Bottom Right")
end

M.AuraSettings = {
    AURA_COOLDOWN_COLOR_REFERENCES = AURA_COOLDOWN_COLOR_REFERENCES,
    AURA_DURATION_BAR_COLOR_REFERENCES = AURA_DURATION_BAR_COLOR_REFERENCES,
    AURA_SCOPE_LABELS = AURA_SCOPE_LABELS,
    AURA_SCOPE_VALID = AURA_SCOPE_VALID,
    AURA_SHARED_COLOR_NOTE = AURA_SHARED_COLOR_NOTE,
    AURA_SORT_DIRECTION_VALUES = AURA_SORT_DIRECTION_VALUES,
    AccessibleNumber = AccessibleNumber,
    AnchorLabel = AnchorLabel,
    AuraSortMethodValues = AuraSortMethodValues,
    AurasMenuCombatLocked = AurasMenuCombatLocked,
    COOLDOWN_SWIPE_DIRECTION_VALUES = COOLDOWN_SWIPE_DIRECTION_VALUES,
    CUSTOM_FRAME_EFFECTS = CUSTOM_FRAME_EFFECTS,
    ChoiceLabel = ChoiceLabel,
    CurrentLane = CurrentLane,
    CurrentScope = CurrentScope,
    DEBUFF_TYPE_BORDER_MODE_VALUES = DEBUFF_TYPE_BORDER_MODE_VALUES,
    DURATION_BAR_DIRECTION_VALUES = DURATION_BAR_DIRECTION_VALUES,
    DURATION_BAR_DISPLAY_VALUES = DURATION_BAR_DISPLAY_VALUES,
    DURATION_BAR_POSITION_VALUES = DURATION_BAR_POSITION_VALUES,
    GFAnchorValues = GFAnchorValues,
    IsGroupScope = IsGroupScope,
    LaneDefaultMax = LaneDefaultMax,
    LaneMaxKey = LaneMaxKey,
    LanePlural = LanePlural,
    LaneSizeKey = LaneSizeKey,
    LaneTitle = LaneTitle,
    MatchSuffix = MatchSuffix,
    NATIVE_EXACT_AURA_FILTERS_ENABLED = NATIVE_EXACT_AURA_FILTERS_ENABLED,
    NATIVE_EXACT_AURA_FILTERS_TEXT = NATIVE_EXACT_AURA_FILTERS_TEXT,
    NormalizeAuraSortMethodForLane = NormalizeAuraSortMethodForLane,
    NormalizeDebuffTypeBorderMode = NormalizeDebuffTypeBorderMode,
    Round = Round,
    ScopeLabel = ScopeLabel,
    SetCurrentLane = SetCurrentLane,
    Tr = Tr,
}
