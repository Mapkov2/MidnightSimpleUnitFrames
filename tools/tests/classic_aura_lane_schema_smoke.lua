-- classic_aura_lane_schema_smoke.lua <repoRoot>
--
-- One lane schema for the Classic aura backend. Three compilers build the
-- lanes the runtime renders: unit Buff/Debuff lanes and group lanes
-- (Game/Classic/Auras/MSUF_Auras3_Compile.lua) and custom containers, their
-- portrait variants and group indicators (MSUF_Auras3_Features.lua). The
-- runtime (Buttons, Filters, Lanes) reads one shape, so every compiled lane
-- must carry every schema field, and the global settings must reach all of
-- them alike. When the compilers were hand-synced copies, custom containers
-- never got the countdown colour buckets or the stack count colour.
--
-- Runs through .github/scripts/auras3_test_driver.lua, repo root as arg 1.
local root = assert(arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")

local registered
local namespace = {
    Client = { IsClassic = true, DispellableDebuffFilter = "HARMFUL|RAID_PLAYER_DISPELLABLE" },
    MSUF_Auras3 = {},
    UF = { RegisterElement = function(_, element) registered = element end },
    ExportPublic = function(name, value) _G[name] = value; return value end,
}
_G.MSUF_NS, _G.MSUF = namespace, namespace
_G.issecretvalue = function() return false end

-- Widgets: SetCooldownTextColor records the countdown colour.
local Widget = {}
Widget.__index = Widget
function Widget:Show() self._shown = true end
function Widget:Hide() self._shown = false end
function Widget:SetShown(shown) self._shown = shown == true end
function Widget:IsShown() return self._shown == true end
function Widget:IsVisible() return self._shown == true end
function Widget:IsForbidden() return false end
function Widget:SetParent(parent) self._parent = parent end
function Widget:GetParent() return self._parent end
function Widget:SetFrameLevel(level) self._frameLevel = level end
function Widget:GetFrameLevel() return self._frameLevel or 1 end
function Widget:SetScript(name, handler) self._scripts = self._scripts or {}; self._scripts[name] = handler end
function Widget:HookScript(name, handler) self:SetScript(name, handler) end
function Widget:GetNumRegions() return 0 end
function Widget:GetRegions() return nil end
function Widget:GetObjectType() return self._objectType or "Frame" end
function Widget:CreateTexture() return setmetatable({ _shown = true, _parent = self }, Widget) end
function Widget:SetCooldownTextColor(r, g, b) self._textR, self._textG, self._textB = r, g, b end
Widget.CreateMaskTexture = Widget.CreateTexture
Widget.CreateFontString = Widget.CreateTexture
for _, name in ipairs({
    "RegisterEvent", "UnregisterEvent", "RegisterUnitEvent", "ClearAllPoints", "SetAllPoints", "SetAlpha",
    "EnableMouse", "SetPoint", "SetSize", "SetWidth", "SetHeight", "SetDrawSwipe", "SetHideCountdownNumbers",
    "SetSwipeColor", "SetDrawEdge", "SetTexCoord", "SetFont", "SetTextColor", "SetShadowOffset", "SetDesaturated",
    "SetJustifyH", "SetJustifyV", "SetBlendMode", "SetMinMaxValues", "SetValue", "SetStatusBarTexture",
    "SetStatusBarColor", "SetColorTexture", "SetReverse", "SetMouseClickEnabled", "SetMouseMotionEnabled",
    "SetCountdownMillisecondsThreshold", "SetSwipeTexture", "SetFrameStrata", "SetOwner", "SetCooldown", "Clear",
    "SetAtlas", "AddMaskTexture", "RemoveMaskTexture", "SetTexture", "SetText", "SetVertexColor", "SetDrawLayer",
}) do Widget[name] = function() end end
_G.CreateFrame = function(frameType, _, parent)
    return setmetatable({ _shown = true, _parent = parent, _objectType = frameType }, Widget)
end

_G.UnitExists = function() return true end
_G.UnitIsUnit = function(a, b) return a == b end
_G.UnitInRange = function() return true, true end
_G.GetTime = function() return 50 end
_G.InCombatLockdown = function() return false end
_G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
_G.GameTooltip = setmetatable({}, Widget)
_G.C_Timer = {}
local world = {}
local function UnitList(unit) world[unit] = world[unit] or {}; return world[unit] end
local function Matches(aura, filter)
    if filter:find("HARMFUL", 1, true) then
        if aura.isHarmful ~= true then return false end
    elseif aura.isHelpful ~= true then
        return false
    end
    if filter:find("|PLAYER", 1, true) and aura.mine ~= true then return false end
    return true
end
_G.C_UnitAuras = {
    GetAuraSlots = function(unit, filter)
        local list, out = UnitList(unit), {}
        for i = 1, #list do if Matches(list[i], filter) then out[#out + 1] = i end end
        return nil, unpack(out)
    end,
    GetAuraDataBySlot = function(unit, slot) return UnitList(unit)[slot] end,
    GetAuraDataByAuraInstanceID = function(unit, id)
        local list = UnitList(unit)
        for i = 1, #list do if list[i].auraInstanceID == id then return list[i] end end
    end,
    GetAuraDataByIndex = function(unit, index, filter)
        local n, list = 0, UnitList(unit)
        for i = 1, #list do
            if Matches(list[i], filter) then n = n + 1; if n == index then return list[i] end end
        end
    end,
}
_G.AuraUtil = {}

-- Global appearance: countdown colour buckets on, with distinct colours, and a
-- stack count colour.
local WARN, URGENT, SAFE, STACK = { 0.11, 0.22, 0.33 }, { 0.44, 0.55, 0.66 }, { 0.70, 0.80, 0.90 }, { 0.12, 0.34, 0.56 }
_G.MSUF_DB = {
    general = {
        aurasCooldownTextUseBuckets = true,
        aurasCooldownTextWarningColor = WARN, aurasCooldownTextUrgentColor = URGENT,
        aurasCooldownTextSafeColor = SAFE, aurasStackCountColor = STACK,
        aurasCooldownTextSafeSeconds = 60, aurasCooldownTextWarningSeconds = 20, aurasCooldownTextUrgentSeconds = 4,
    },
    auras3 = {
        enabled = true, showPlayer = true, showTarget = true,
        shared = {},
        perUnit = {
            target = { layout = {}, filters = {}, layoutShared = { showBuffs = true, showDebuffs = true } },
            player = { layout = {}, filters = {}, layoutShared = { showBuffs = true, showDebuffs = true } },
        },
        customContainers = { perUnit = {
            target = { items = {
                [1] = { enabled = true, auraType = "BUFF", spellIDs = "880001", placed = { size = 20, max = 4, perRow = 4 } },
                [2] = { enabled = true, auraType = "DEBUFF", spellIDs = "880002",
                    placed = { size = 20, max = 4, perRow = 4, type = "bar", barWidth = 60 } },
                [4] = { enabled = true, targetDots = true, auraType = "DEBUFF", spellIDs = "880003",
                    customSpellIDs = { [880003] = true }, portraitIcon = true, placed = { size = 22, max = 2 } },
            } },
            player = { items = {
                [4] = { enabled = true, playerDefensives = true, portraitIcon = true, spellIDs = "880004",
                    placed = { size = 24, max = 2 } },
            } },
        } },
    },
}

local manifest = assert(loadfile(root .. "/tools/tests/client_manifest.lua"))()
local chain = {
    "Auras3/MSUF_Auras3_Core.lua", "Auras3/MSUF_Auras3_IconShape.lua",
    "Game/Classic/Auras/MSUF_Auras3_Visuals.lua", "Game/Classic/Auras/MSUF_Auras3_Features.lua",
    "Game/Classic/Auras/MSUF_Auras3_Preview.lua", "Game/Classic/Auras/MSUF_Auras3_Compile.lua",
    "Game/Classic/Auras/MSUF_Auras3_Buttons.lua", "Game/Classic/Auras/MSUF_Auras3_Filters.lua",
    "Game/Classic/Auras/MSUF_Auras3_FrameVisuals.lua", "Game/Classic/Auras/MSUF_Auras3_Lanes.lua",
    "Game/Classic/Auras/MSUF_Auras3_UnitFrames.lua", "Game/Classic/Auras/MSUF_Auras3_Requests.lua",
}
manifest.LoadSelected(root, "Vanilla", namespace, chain)
assert(registered, "Classic aura element did not register")
local A3 = namespace.MSUF_Auras3
local Compile = assert(A3._ClassicCompile, "Classic compile module missing")

-- The fields the runtime reads from every lane, whichever compiler built it.
local REQUIRED = {
    "kind", "unit", "enabled", "renderEnabled", "harmful",
    "filter", "playerFilter", "importantFilter", "raidFilter", "raidInCombatFilter",
    "stealableFilter", "dispellableFilter", "bossFilter",
    "max", "size", "spacing", "step", "perRow", "cols", "rows", "padding", "width", "height",
    "x", "y", "anchor", "layer", "xSign", "ySign", "verticalGrowth", "initialAnchor",
    "sortOrder", "sortComparator", "sortReverse", "naturalOrder", "visibleOnlyScan", "cappedFilterScan",
    "reorderOnUpdate",
    "showTooltip", "showCooldownSwipe", "showCooldownText", "showCooldown", "cooldownSwipeDarken",
    "cooldownDecimalSeconds", "cooldownSize", "cooldownAnchor", "cooldownX", "cooldownY",
    "cooldownTextBuckets", "cooldownSafeR", "cooldownSafeG", "cooldownSafeB",
    "cooldownWarnR", "cooldownWarnG", "cooldownWarnB", "cooldownUrgentR", "cooldownUrgentG", "cooldownUrgentB",
    "cooldownSafeSeconds", "cooldownWarningSeconds", "cooldownUrgentSeconds",
    "showStacks", "stackAnchor", "stackSize", "stackX", "stackY", "stackR", "stackG", "stackB",
    "hasFilterWork", "nativePlayerFilter", "needsPlayerFlag", "needsCombatRefresh", "hasInclusive",
    "onlyMine", "hidePermanent", "maxDuration", "showDispelTypeBorder", "showDispelTypeSymbol",
}

local failures = {}
local function Check(condition, message) if not condition then failures[#failures + 1] = message end end
local checked = 0
local function CheckLane(label, lane)
    checked = checked + 1
    for _, field in ipairs(REQUIRED) do
        Check(lane[field] ~= nil, label .. " lacks " .. field)
    end
    Check(lane.cooldownTextBuckets == true, label .. " ignores the countdown colour buckets")
    Check(lane.cooldownWarnR == WARN[1] and lane.cooldownWarnG == WARN[2] and lane.cooldownWarnB == WARN[3]
        and lane.cooldownUrgentR == URGENT[1] and lane.cooldownSafeB == SAFE[3],
        label .. " does not carry the configured countdown colours")
    Check(lane.cooldownWarningSeconds == 20 and lane.cooldownUrgentSeconds == 4,
        label .. " does not carry the configured countdown thresholds")
    Check(lane.stackR == STACK[1] and lane.stackG == STACK[2] and lane.stackB == STACK[3],
        label .. " does not carry the configured stack count colour")
    Check(lane.dispellableFilter == "HARMFUL|RAID_PLAYER_DISPELLABLE", label .. " has the wrong dispellable filter")
    Check(lane.playerFilter == (lane.nativePlayerFilter and lane.filter or lane.filter .. "|PLAYER"),
        label .. " has the wrong ownership filter")
    Check(lane.sortComparator == Compile.SortComparator(lane.sortOrder),
        label .. " sorts with another comparator than its sort mode")
    Check(lane.naturalOrder == (lane.sortOrder == 0 and lane.sortReverse ~= true),
        label .. " has an arrival-order flag that does not follow its sort mode")
    Check(lane.reorderOnUpdate == (lane.sortOrder == 2 or lane.sortOrder == 3 or lane.sortOrder == 4),
        label .. " re-sorts on refresh in the wrong modes")
end

-- 1. Unit Buff/Debuff lanes and custom containers -------------------------------------
local target = A3.ResolveUnitFrameConfig("target", { portrait = { enabled = true, width = 30, height = 30 } })
local player = A3.ResolveUnitFrameConfig("player", { portrait = { enabled = true, width = 30, height = 30 } })
for _, kind in ipairs({ "buff", "debuff", "custom1", "custom2", "targetDotPortrait" }) do
    CheckLane("target " .. kind, assert(target.lanes[kind], "target lane " .. kind .. " did not compile"))
end
CheckLane("player defensivePortrait", assert(player.lanes.defensivePortrait, "player defensive portrait lane missing"))

-- 2. Group lanes and group indicators -----------------------------------------------------
local groupFrame = {
    _msufIsGroupFrame = true, _msufGFKind = "party", MSUFUnitKey = "party1",
    MSUFSpec = {
        scope = "group",
        auras = { enabled = true, showBuffs = true, showTrackedBuffs = true, showDebuffs = true, showExternals = true,
            trackedBuffIncludeHash = { [880005] = true } },
        spellIndicators = { enabled = true, items = { { spellIDs = "880006" } } },
    },
}
local group = Compile.ResolveGroupFrameConfig(groupFrame, "party1")
for _, kind in ipairs({ "buff", "trackedBuff", "debuff", "external", "spellIndicator1" }) do
    CheckLane("party " .. kind, assert(group.lanes[kind], "party lane " .. kind .. " did not compile"))
end

-- 3. The buckets reach a container countdown at runtime --------------------------------------
world.target = { {
    auraInstanceID = 9001, spellId = 880001, name = "Container buff", icon = 1, applications = 1,
    duration = 30, expirationTime = 60, isHelpful = true, isHarmful = false, sourceUnit = "target",
} }
local frame = setmetatable({ _shown = true, MSUFUnitKey = "target", _msufActiveElements = { Auras = true },
    MSUFSpec = {} }, Widget)
registered.Create(frame)
assert(registered.Enable(frame) == true, "target aura element did not enable")
local lane = frame._msufA3State.lanes.custom1
local button = lane and lane[lane.visibleByID[9001]]
local cooldown = button and button.Cooldown
Check(cooldown and cooldown._textR == WARN[1] and cooldown._textG == WARN[2] and cooldown._textB == WARN[3],
    "a custom container countdown with 10 s left is not in the Warning colour")

assert(#failures == 0, "Classic aura lane schema:\n  " .. table.concat(failures, "\n  "))
print(string.format("classic_aura_lane_schema_smoke: ok (%d lanes from every compiler carry %d schema fields)",
    checked, #REQUIRED))
