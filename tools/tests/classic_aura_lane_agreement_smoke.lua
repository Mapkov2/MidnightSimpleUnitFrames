-- Classic aura backend: settings and lanes that must agree, run against the real
-- backend files with widget, C_UnitAuras, UnitCanAssist and UnitGUID stubs.
--   * Bars > Show on filters the dispel border the way Retail's
--     CompileDispelSensor does, on the direct, cached-lane and rescanned-lane
--     paths, and filters the border only; Both never asks UnitCanAssist
--   * the Pandemic-only Full-Frame switch and its badge exist only where the aura
--     backend can show Pandemic, and a stale saved true never hides a Classic
--     effect
--   * Hide permanent and every sort name mean the same in a Buff lane and in a
--     custom container
--   * a group token that changes hands rescans on GROUP_ROSTER_UPDATE, and an
--     unchanged member costs one GUID read, no scan and no allocation
-- Arguments: repository root, then optionally the backend, features, compile,
-- Custom workspace and visuals paths (mutation runs).
local root = assert(arg[1], "repository root argument missing")
root = (tostring(root):gsub("\\", "/"):gsub("/+$", ""))
local ADDON = root .. "/MidnightSimpleUnitFrames/"
local overrides = {
    ["Game/Classic/Auras/MSUF_Auras3_UnitFrames.lua"] = arg[2],
    ["Game/Classic/Auras/MSUF_Auras3_Features.lua"] = arg[3],
    ["Game/Classic/Auras/MSUF_Auras3_Compile.lua"] = arg[4],
    ["Game/Classic/Auras/MSUF_Auras3_Visuals.lua"] = arg[6],
}
local WORKSPACE = arg[5]
    or (root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_CustomWorkspace.lua")

local registered
local namespace = {
    Client = { IsClassic = true, DispellableDebuffFilter = "HARMFUL|RAID_PLAYER_DISPELLABLE" },
    MSUF_Auras3 = {},
    UF = { RegisterElement = function(_, element) registered = element end },
    ExportPublic = function(name, value) _G[name] = value; return value end,
}
_G.MSUF_NS, _G.MSUF = namespace, namespace
_G.issecretvalue = function(value) return type(value) == "table" and value._secret == true end

-- Widget stub ---------------------------------------------------------------------------
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
function Widget:SetTexture(texture) self._texture = texture end
function Widget:SetText(text) self._text = text end
function Widget:SetVertexColor(r, g, b, a) self._vr, self._vg, self._vb, self._va = r, g, b, a end
function Widget:GetNumRegions() return 0 end
function Widget:GetRegions() return nil end
function Widget:GetObjectType() return self._objectType or "Frame" end
function Widget:CreateTexture() return setmetatable({ _shown = true, _parent = self }, Widget) end
Widget.CreateMaskTexture = Widget.CreateTexture
Widget.CreateFontString = Widget.CreateTexture
for _, name in ipairs({
    "RegisterEvent", "UnregisterEvent", "ClearAllPoints", "SetAllPoints", "SetAlpha", "EnableMouse", "SetPoint",
    "SetSize", "SetWidth", "SetHeight", "SetDrawSwipe", "SetHideCountdownNumbers", "SetSwipeColor", "SetDrawEdge",
    "SetTexCoord", "SetFont", "SetTextColor", "SetShadowOffset", "SetDesaturated", "SetJustifyH", "SetJustifyV",
    "SetBlendMode", "SetMinMaxValues", "SetValue", "SetStatusBarTexture", "SetStatusBarColor", "SetColorTexture",
    "SetReverse", "SetMouseClickEnabled", "SetMouseMotionEnabled", "SetCountdownMillisecondsThreshold",
    "SetSwipeTexture", "SetFrameStrata", "SetOwner", "SetCooldown", "Clear", "SetAtlas", "AddMaskTexture",
    "RemoveMaskTexture",
}) do Widget[name] = function() end end
_G.CreateFrame = function(frameType, _, parent)
    return setmetatable({ _shown = true, _parent = parent, _objectType = frameType }, Widget)
end

--- Bytes allocated per call with the collector stopped, so nothing is freed.
local function BytesPerCall(fn, n)
    collectgarbage("collect"); collectgarbage("collect"); collectgarbage("stop")
    local before = collectgarbage("count")
    for _ = 1, n do fn() end
    local after = collectgarbage("count")
    collectgarbage("restart")
    return (after - before) * 1024 / n
end

-- Game API stubs ------------------------------------------------------------------------
-- The backend binds GetAuraSlots and friends as locals at load, so every knob
-- below is data these functions read, never a replacement function.
local world, assistable, guids, exists = {}, {}, {}, {}
local api = { slots = 0, index = 0, assist = 0, guid = 0 }
local snapshots = true
local function Snapshot(aura)
    if not (snapshots and aura) then return aura end
    local copy = {}
    for key, value in pairs(aura) do copy[key] = value end
    return copy
end
local function UnitList(unit) world[unit] = world[unit] or {}; return world[unit] end
local function Matches(aura, filter)
    if filter:find("HARMFUL", 1, true) then
        if aura.isHarmful ~= true then return false end
    elseif aura.isHelpful ~= true then
        return false
    end
    if filter:find("|PLAYER", 1, true) and aura.mine ~= true then return false end
    if filter:find("RAID_PLAYER_DISPELLABLE", 1, true) and aura.dispelName == nil then return false end
    return true
end
_G.UnitExists = function(unit) return exists[unit] ~= false end
_G.UnitIsUnit = function(a, b) return a == b end
_G.UnitInRange = function() return true, true end
_G.UnitCanAssist = function(source, unit)
    api.assist = api.assist + 1
    -- Message built on failure only: the allocation checks run through here.
    if source ~= "player" then error("Show on asked UnitCanAssist about " .. tostring(source)) end
    return assistable[unit] == true
end
_G.UnitGUID = function(unit) api.guid = api.guid + 1; return guids[unit] end
_G.GetTime = function() return 50 end
_G.InCombatLockdown = function() return false end
_G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
_G.GameTooltip = setmetatable({}, Widget)
_G.C_Timer = {}
_G.DebuffTypeColor = { Magic = { r = 0.20, g = 0.60, b = 1.00, a = 1 } }
_G.C_UnitAuras = {
    GetAuraSlots = function(unit, filter)
        api.slots = api.slots + 1
        local list, out = UnitList(unit), {}
        for i = 1, #list do if Matches(list[i], filter) then out[#out + 1] = i end end
        return nil, unpack(out)
    end,
    GetAuraDataBySlot = function(unit, slot) return Snapshot(UnitList(unit)[slot]) end,
    GetAuraDataByAuraInstanceID = function(unit, id)
        local list = UnitList(unit)
        for i = 1, #list do if list[i].auraInstanceID == id then return Snapshot(list[i]) end end
        return nil
    end,
    GetAuraDataByIndex = function(unit, index, filter)
        api.index = api.index + 1
        local n, list = 0, UnitList(unit)
        for i = 1, #list do
            if Matches(list[i], filter) then n = n + 1; if n == index then return Snapshot(list[i]) end end
        end
        return nil
    end,
    GetUnitAuraInstanceIDs = function(unit, filter)
        local out, list = {}, UnitList(unit)
        for i = 1, #list do if Matches(list[i], filter) then out[#out + 1] = list[i].auraInstanceID end end
        return out
    end,
}
_G.AuraUtil = {}

local nextID = 5000
local function Aura(helpful, fields)
    nextID = nextID + 1
    local aura = {
        auraInstanceID = nextID, spellId = 900000 + nextID, name = "Aura" .. nextID, icon = 134400 + nextID,
        applications = 1, duration = 30, expirationTime = 80, isHelpful = helpful, isHarmful = not helpful,
        isFromPlayerOrPlayerPet = false,
    }
    for key, value in pairs(fields or {}) do aura[key] = value end
    return aura
end
local function Magic(fields)
    local aura = Aura(false, { dispelName = "Magic" })
    for key, value in pairs(fields or {}) do aura[key] = value end
    return aura
end

-- SavedVariables ------------------------------------------------------------------------
-- player: a Hide permanent debuff lane has filter work, so its dispel border
-- is resolved from the lane (cached, then rescanned), never directly.
-- target: a Buff lane and custom container 1 share the Hide permanent rule;
-- container 4 (Dots on target) carries a Full-Frame effect with a stale
-- Pandemic-only flag. focus: a Buff lane and custom container 1 share one sort name.
local DOT_SPELL = 700001
_G.MSUF_DB = {
    general = {},
    auras3 = {
        enabled = true, showPlayer = true, showTarget = true, showFocus = true, showBoss = false,
        shared = {},
        perUnit = {
            player = {
                layout = {}, layoutShared = { showBuffs = false, showDebuffs = true },
                filters = { debuffs = { hidePermanent = true } },
            },
            target = {
                layout = {}, layoutShared = { showBuffs = true, showDebuffs = false },
                filters = { buffs = { hidePermanent = true } },
            },
            focus = { layout = {}, layoutShared = { showBuffs = true, showDebuffs = false }, filters = {} },
        },
        customContainers = { perUnit = {
            target = { items = {
                [1] = {
                    enabled = true, auraType = "BUFF", spellIDs = "600001 600002 600003 600004",
                    autoBlacklistDebuffs = false,
                    filters = { enabled = true, hidePermanent = true },
                    placed = { size = 20, max = 8, perRow = 8 },
                },
                [4] = {
                    enabled = true, targetDots = true, auraType = "DEBUFF", spellIDs = tostring(DOT_SPELL),
                    customSpellIDs = { [DOT_SPELL] = true }, filters = { onlyMine = true },
                    placed = { size = 20, max = 4, perRow = 4 },
                    frame = {
                        type = "border", color = { 1, 0, 0, 1 }, priority = 5, thickness = 2, layer = 0,
                        onlyInPandemicWindow = true,
                    },
                },
            } },
            focus = { items = {
                [1] = {
                    enabled = true, auraType = "BUFF", spellIDs = "555001 555003 555004",
                    autoBlacklistDebuffs = false, filters = { enabled = true },
                    placed = { size = 20, max = 8, perRow = 8 },
                },
            } },
        } },
    },
}

-- Load the real chain in the shipped TOC order -------------------------------------------
local manifest = assert(loadfile(root .. "/tools/tests/client_manifest.lua"))()
local chain = {
    "Auras3/MSUF_Auras3_Core.lua", "Auras3/MSUF_Auras3_IconShape.lua",
    "Game/Classic/Auras/MSUF_Auras3_Visuals.lua", "Game/Classic/Auras/MSUF_Auras3_Features.lua",
    "Game/Classic/Auras/MSUF_Auras3_Preview.lua", "Game/Classic/Auras/MSUF_Auras3_Compile.lua",
    "Game/Classic/Auras/MSUF_Auras3_UnitFrames.lua",
}
local overridePaths = {}
for relative, path in pairs(overrides) do overridePaths[ADDON .. relative] = path end
manifest.LoadSelected(root, "Vanilla", namespace, chain, function(path)
    return loadfile(overridePaths[path] or path)
end)
assert(registered, "Classic aura element did not register")
local A3 = namespace.MSUF_Auras3

--- mayStayOff: the frame's only aura work is a border the test may compile away,
--- so a disabled element is an outcome for the test to judge, not a setup error.
local function NewFrame(unit, spec, mayStayOff)
    local frame = setmetatable({
        _shown = true, MSUFUnitKey = unit, _msufActiveElements = { Auras = true }, MSUFSpec = spec or {},
    }, Widget)
    frame.hpBar = _G.CreateFrame("StatusBar", nil, frame)
    registered.Create(frame)
    local enabled = registered.Enable(frame) == true
    assert(enabled or mayStayOff == true, unit .. " aura element did not enable")
    return frame
end
local function Update(frame, payload) return registered.Update(frame, "UNIT_AURA", frame.MSUFUnitKey, payload) end
local function Refresh(frame, aura) return Update(frame, { updatedAuraInstanceIDs = { aura.auraInstanceID } }) end
local function Border(frame) return frame._msufA3DispelActive == true end
local function VisibleIDs(lane)
    local ids = {}
    for i = 1, lane.visible do ids[i] = tostring(lane[i].auraInstanceID) end
    return table.concat(ids, ",")
end
local function IDs(...)
    local ids = {}
    for i = 1, select("#", ...) do ids[i] = tostring((select(i, ...)).auraInstanceID) end
    return table.concat(ids, ",")
end
local function HasEvent(list, event)
    for i = 1, type(list) == "table" and #list or 0 do if list[i] == event then return true end end
    return false
end

-- 1. Bars > Show on ---------------------------------------------------------------------
-- Direct path: boss1 shows no aura icons, so only the border (and an overlay
-- that inherits the border's trigger) scans, straight from the unit.
local bossSpec = {
    border = { dispel = true, dispelTrigger = "DISPEL_TYPE", dispelShowOn = "FRIENDLY" },
    dispelOverlay = { enabled = true, trigger = "BORDER" },
}
local bossMagic = Magic()
UnitList("boss1")[1] = bossMagic
assistable.boss1 = true
local boss = NewFrame("boss1", bossSpec)
local bossCfg = A3.ResolveUnitFrameConfig("boss1", bossSpec)
assert(bossCfg.visualDirect == true and bossCfg.visual.borderShowOn == "FRIENDLY",
    "precondition: boss1 does not resolve its dispel border directly with a Friendly filter")
assert(Border(boss) and boss._msufA3DispelOverlayActive == true,
    "Show on Friendly hid the border on a unit the player can assist")
assistable.boss1 = false
Refresh(boss, bossMagic)
assert(not Border(boss), "Show on Friendly kept the border on a unit the player cannot assist")
assert(boss._msufA3DispelOverlayActive == true,
    "Show on filtered the overlay that only inherits the border's trigger")

bossSpec.border.dispelShowOn = "ENEMY"
A3.BumpRuntimeConfig()
Refresh(boss, bossMagic)
assert(Border(boss), "Show on Enemy hid the border on a unit the player cannot assist")
assistable.boss1 = true
Refresh(boss, bossMagic)
assert(not Border(boss), "Show on Enemy kept the border on a unit the player can assist")

bossSpec.border.dispelShowOn = "BOTH"
A3.BumpRuntimeConfig()
local asked = api.assist
for _, canAssist in ipairs({ true, false, true }) do
    assistable.boss1 = canAssist
    Refresh(boss, bossMagic)
    assert(Border(boss), "Show on Both filtered the border")
end
assert(api.assist == asked, "Show on Both asked UnitCanAssist " .. (api.assist - asked) .. " times")

bossSpec.border.dispelShowOn = "FRIENDLY"
A3.BumpRuntimeConfig()
table.remove(UnitList("boss1"))
Update(boss, { removedAuraInstanceIDs = { bossMagic.auraInstanceID } })
asked = api.assist
Update(boss, { isFullUpdate = true })
assert(not Border(boss) and api.assist == asked,
    "a frame without a matching debuff still asked UnitCanAssist")
UnitList("boss1")[1] = bossMagic
Update(boss, { addedAuras = { Snapshot(bossMagic) } })
assert(Border(boss), "precondition: the border did not return with the debuff")

-- A unit frame's cleanse trigger needs a friendly unit: Enemy compiles no border.
local cleanseSpec = { border = { dispel = true, dispelTrigger = "BY_ME", dispelShowOn = "ENEMY" } }
local cleanseMagic = Magic()
UnitList("boss2")[1] = cleanseMagic
assistable.boss2 = false
local cleanseCfg = A3.ResolveUnitFrameConfig("boss2", cleanseSpec)
assert(not (cleanseCfg.visual and cleanseCfg.visual.borderEnabled == true),
    "Show on Enemy compiled a unit-frame border for Dispellable by me")
asked = api.assist
local cleanse = setmetatable({ _shown = true, MSUFUnitKey = "boss2", _msufActiveElements = { Auras = true },
    MSUFSpec = cleanseSpec }, Widget)
registered.Create(cleanse)
registered.Enable(cleanse)
Update(cleanse, { isFullUpdate = true })
assert(not Border(cleanse) and api.assist == asked,
    "Show on Enemy with Dispellable by me showed a unit-frame border or asked UnitCanAssist")
cleanseSpec.border.dispelShowOn = "FRIENDLY"
A3.BumpRuntimeConfig()
assistable.boss2 = true
Update(cleanse, { isFullUpdate = true })
assert(Border(cleanse), "Show on Friendly with Dispellable by me hid the border on a friendly unit")
-- The filter itself allocates nothing (a border-only frame: the overlay
-- renderer's own signature strings would be measured otherwise).
local cleansePayload = { updatedAuraInstanceIDs = { cleanseMagic.auraInstanceID } }
snapshots = false
asked = api.assist
Update(cleanse, cleansePayload)
assert(api.assist == asked + 1, "precondition: the allocation run does not reach the Show on filter")
local bytes = BytesPerCall(function() Update(cleanse, cleansePayload) end, 200)
snapshots = true
assert(bytes == 0, ("a Show on filtered update allocated %.1f bytes per event"):format(bytes))

-- Group frames keep the Enemy filter for the cleanse trigger (Retail's groupMode).
local groupSpec = {
    scope = "group", auras = { enabled = true },
    border = { dispel = true, dispelTrigger = "BY_ME", dispelShowOn = "ENEMY" },
}
local groupMagic = Magic()
UnitList("party2")[1] = groupMagic
guids.party2 = "Player-C"
assistable.party2 = true
local party2 = NewFrame("party2", groupSpec, true)
assert(not Border(party2), "group Show on Enemy showed the border on a unit the player can assist")
assistable.party2 = false
Refresh(party2, groupMagic)
assert(Border(party2), "group Show on Enemy hid the border on a unit the player cannot assist")

-- Lane paths: the lane caches the unfiltered border, the frame applies Show on.
local playerSpec = { border = { dispel = true, dispelTrigger = "DISPEL_TYPE", dispelShowOn = "ENEMY" } }
local playerMagic = Magic()
UnitList("player")[1] = playerMagic
assistable.player = true
local player = NewFrame("player", playerSpec)
local playerDebuff = player._msufA3State.lanes.debuff
assert(A3.ResolveUnitFrameConfig("player", playerSpec).visualDirect ~= true
    and playerDebuff._msufA3VisualCacheReady == true and playerDebuff._msufA3VisualBorderActive == true,
    "precondition: the player border is not resolved from a cached lane")
assert(not Border(player), "cached lane: Show on Enemy kept the border on a unit the player can assist")
assistable.player = false
local secondMagic = Magic()
UnitList("player")[2] = secondMagic
Update(player, { addedAuras = { Snapshot(secondMagic) } })
assert(playerDebuff._msufA3VisualCacheReady == true and Border(player),
    "cached lane: Show on Enemy hid the border on a unit the player cannot assist")
assistable.player = true
Refresh(player, playerMagic)
assert(playerDebuff._msufA3VisualCacheReady == true and playerDebuff._msufA3VisualBorderActive == true
    and not Border(player), "rescanned lane: Show on Enemy kept the border, or the lane cached the filtered border")

-- 2. Pandemic-only Full-Frame effect ----------------------------------------------------
-- Menu: the real Custom workspace, Effect tool of Dots on target, built once with
-- a backend that has no Pandemic applier (Classic) and once with one (Midnight).
local function BuildEffectTool(withPandemic)
    local labels, refreshers, badges = {}, {}, nil
    local item = {
        filters = {}, placed = {},
        frame = { type = "border", color = { 1, 0, 0, 0.8 }, onlyInPandemicWindow = true },
    }
    local menuA3 = {
        MenuModel = {
            CustomContainerMax = function() return 4 end,
            CustomContainer = function() return item end,
        },
        ApplyPandemicVisual = withPandemic and function() end or nil,
    }
    local function Control()
        return { Hide = function() end, Show = function() end, SetShown = function() end }
    end
    local M = {
        Theme = { colors = {} },
        ValueTextPairs = function() return {} end,
        AuraSettings = { ChoiceLabel = function(_, value) return value end, CUSTOM_FRAME_EFFECTS = {} },
        AuraControls = {
            AuraControlMeta = function() return {} end, AddTooltip = function() end, ApplyUnit = function() end,
        },
        BindColor = function() end,
        TrackRefresh = function(_, fn) refreshers[#refreshers + 1] = fn end,
    }
    local function Bind(_, _, label) labels[#labels + 1] = label; return Control() end
    M.BindSwitchAt, M.BindSliderAt, M.BindDropdownAt, M.BindTextInputAt = Bind, Bind, Bind, Bind
    M.Widgets = {
        Color = function() local color = Control(); color._msuf2Title = Control(); return color end,
        SetCollapsibleBadges = function(section, list)
            if section.title == "Full-Frame Effect" then badges = list end
        end,
    }
    assert(loadfile(WORKSPACE))("MidnightSimpleUnitFrames_Options", { MSUF2 = M, MSUF_Auras3 = menuA3 })
    local b = { width = 720 }
    function b:CollapsibleSection(_, title) return { _msuf2Width = 720, title = title } end
    M.BuildAuras3CompactCustomWorkspace({}, b, "target", 4, "effect")
    for i = 1, #refreshers do refreshers[i]() end
    local switch, badge = false, false
    for i = 1, #labels do if labels[i] == "Only during Pandemic window" then switch = true end end
    for i = 1, type(badges) == "table" and #badges or 0 do
        if badges[i].text == "Pandemic only" then badge = true end
    end
    return switch, badge, labels
end
local classicSwitch, classicBadge, classicLabels = BuildEffectTool(false)
assert(#classicLabels >= 5, "precondition: the Effect tool built " .. #classicLabels .. " controls")
assert(not classicSwitch, "the Effect tool builds Only during Pandemic window without a Pandemic applier")
assert(not classicBadge, "the Effect tool badges a stale Pandemic-only flag the backend cannot honour")
local nativeSwitch, nativeBadge = BuildEffectTool(true)
assert(nativeSwitch and nativeBadge, "the Effect tool lost Only during Pandemic window where Pandemic exists")

-- Runtime: the Classic effect path shows the effect whatever that flag says.
local dot = Aura(false, { spellId = DOT_SPELL, mine = true, sourceUnit = "player", isFromPlayerOrPlayerPet = true })
local targetList = UnitList("target")
targetList[#targetList + 1] = dot
local permanent = Aura(true, { spellId = 600001, duration = 0, expirationTime = 0 })
local timed = Aura(true, { spellId = 600002, duration = 30, expirationTime = 80 })
local zeroExpiry = Aura(true, { spellId = 600003, duration = 30, expirationTime = 0 })
local unreadable = Aura(true, { spellId = 600004, duration = { _secret = true }, expirationTime = { _secret = true } })
for _, aura in ipairs({ permanent, timed, zeroExpiry, unreadable }) do targetList[#targetList + 1] = aura end
local target = NewFrame("target")
local dots = assert(target._msufA3State.lanes.custom4, "Dots on target lane missing")
local function EffectShown()
    local button = dots.visibleByID[dot.auraInstanceID] and dots[dots.visibleByID[dot.auraInstanceID]]
    local effectRoot = button and button._msufA3ClassicFrameEffectRoot
    return effectRoot ~= nil and effectRoot._shown == true
end
local frameEffect = _G.MSUF_DB.auras3.customContainers.perUnit.target.items[4].frame
assert(dots.visible == 1 and EffectShown(),
    "a stale Pandemic-only flag suppressed the Classic Full-Frame effect")
frameEffect.onlyInPandemicWindow = false
A3.BumpRuntimeConfig()
Update(target, { isFullUpdate = true })
assert(EffectShown(), "precondition: the Full-Frame effect does not show without the flag")
frameEffect.type = "none"
A3.BumpRuntimeConfig()
Update(target, { isFullUpdate = true })
assert(not EffectShown(), "precondition: an effect of type none still shows, so this check cannot fail")
frameEffect.type, frameEffect.onlyInPandemicWindow = "border", true
A3.BumpRuntimeConfig()
Update(target, { isFullUpdate = true })
assert(EffectShown(), "a stale Pandemic-only flag suppressed the Classic Full-Frame effect after a refresh")

-- 3. Hide permanent and sort names mean the same in a lane and a container -----------------
local targetState = target._msufA3State
local function ActiveSet(lane)
    local ids = {}
    for _, aura in ipairs({ permanent, timed, zeroExpiry, unreadable }) do
        if lane.active[aura.auraInstanceID] == true then ids[#ids + 1] = tostring(aura.auraInstanceID) end
    end
    return table.concat(ids, ",")
end
assert(targetState.lanes.buff.config.hidePermanent == true and targetState.lanes.custom1.config.hidePermanent == true,
    "precondition: Hide permanent is not on for both target lanes")
assert(ActiveSet(targetState.lanes.buff) == IDs(timed, unreadable),
    "the Buff lane's Hide permanent kept or dropped the wrong auras: " .. ActiveSet(targetState.lanes.buff))
assert(ActiveSet(targetState.lanes.custom1) == ActiveSet(targetState.lanes.buff),
    "Hide permanent means something else in a custom container: container " .. ActiveSet(targetState.lanes.custom1)
    .. ", Buff lane " .. ActiveSet(targetState.lanes.buff))

-- Ties decide these orders: same expiration (permanent), same name, and an
-- arrival order that is not owner-first.
local focusList = UnitList("focus")
local theirs = Aura(true, { spellId = 555001, name = "Same", duration = 0, expirationTime = 0, sourceUnit = "party3" })
local mine = Aura(true, { spellId = 555001, name = "Same", duration = 0, expirationTime = 0,
    sourceUnit = "player", isFromPlayerOrPlayerPet = true })
local alpha = Aura(true, { spellId = 555003, name = "Alpha", duration = 30, expirationTime = 70, sourceUnit = "party3" })
local zulu = Aura(true, { spellId = 555004, name = "Zulu", duration = 20, expirationTime = 60,
    sourceUnit = "player", isFromPlayerOrPlayerPet = true })
focusList[1], focusList[2], focusList[3], focusList[4] = theirs, mine, alpha, zulu
local focus = NewFrame("focus")
local focusShared = _G.MSUF_DB.auras3.perUnit.focus.layoutShared
local focusPlaced = _G.MSUF_DB.auras3.customContainers.perUnit.focus.items[1].placed
local EXPECTED = {
    DEFAULT = IDs(mine, zulu, theirs, alpha),
    IMPORTANT_FIRST = IDs(mine, zulu, theirs, alpha),
    UNIT_FRAME_DEBUFF = IDs(mine, zulu, theirs, alpha),
    SOMETHING_NEW = IDs(mine, zulu, theirs, alpha),
    BIG_DEFENSIVE = IDs(alpha, zulu, mine, theirs),
    EXPIRATION = IDs(zulu, alpha, mine, theirs),
    TIME_REMAINING = IDs(zulu, alpha, mine, theirs),
    EXPIRATION_ONLY = IDs(zulu, alpha, theirs, mine),
    NAME = IDs(alpha, mine, theirs, zulu),
    NAME_ONLY = IDs(alpha, theirs, mine, zulu),
    INSTANCE_ID = IDs(theirs, mine, alpha, zulu),
}
for name, expected in pairs(EXPECTED) do
    focusShared.buffSortMethod, focusPlaced.sortMethod = name, name
    A3.BumpRuntimeConfig()
    Update(focus, { isFullUpdate = true })
    local lanes = focus._msufA3State.lanes
    local laneOrder, containerOrder = VisibleIDs(lanes.buff), VisibleIDs(lanes.custom1)
    assert(laneOrder == expected, name .. ": the Buff lane sorts " .. laneOrder .. ", expected " .. expected)
    assert(containerOrder == laneOrder, name .. ": a custom container sorts " .. containerOrder
        .. " where the Buff lane sorts " .. laneOrder)
    assert(lanes.custom1.config.reorderOnUpdate == lanes.buff.config.reorderOnUpdate,
        name .. ": a custom container and the Buff lane disagree on re-sorting a refreshed aura")
end
-- Custom Priority exists only for containers; Classic keeps arrival order.
focusPlaced.sortMethod = "CUSTOM_PRIORITY"
A3.BumpRuntimeConfig()
Update(focus, { isFullUpdate = true })
assert(VisibleIDs(focus._msufA3State.lanes.custom1) == EXPECTED.INSTANCE_ID,
    "Custom Priority no longer keeps arrival order on Classic")

-- 4. A group token that changes hands --------------------------------------------------
local partyList = UnitList("party1")
local oldBuff, oldDebuff = Aura(true), Magic()
partyList[1], partyList[2] = oldBuff, oldDebuff
guids.party1 = "Player-A"
local partySpec = { scope = "group", auras = { enabled = true, showBuffs = true, maxBuffs = 4, showDebuffs = true, maxDebuffs = 4 } }
local party = NewFrame("party1", partySpec)
local partyLanes = party._msufA3State.lanes
assert(partyLanes.buff.visible == 1 and partyLanes.debuff.visible == 1, "precondition: party1 did not render its auras")
assert(HasEvent(registered.GetUnitlessEvents(party), "GROUP_ROSTER_UPDATE"),
    "group frames do not follow GROUP_ROSTER_UPDATE")
assert(not HasEvent(registered.GetUnitlessEvents(target), "GROUP_ROSTER_UPDATE"),
    "a unit frame registered GROUP_ROSTER_UPDATE")

local function Roster(frame) return registered.Update(frame, "GROUP_ROSTER_UPDATE", frame.MSUFUnitKey) end
local scans, reads = api.slots, api.guid
Roster(party)
assert(api.slots == scans and api.guid == reads + 1,
    "an unchanged member cost " .. (api.slots - scans) .. " scans and " .. (api.guid - reads) .. " GUID reads")
assert(VisibleIDs(partyLanes.buff) == IDs(oldBuff), "an unchanged member repainted the lane")
bytes = BytesPerCall(function() Roster(party) end, 200)
assert(bytes == 0, ("an unchanged member's roster check allocated %.1f bytes"):format(bytes))

-- Someone else now answers to party1, and Classic sends no UNIT_AURA for it.
local newBuff, newDebuff = Aura(true), Aura(false)
partyList[1], partyList[2] = newBuff, newDebuff
guids.party1 = "Player-B"
scans = api.slots
Roster(party)
assert(api.slots > scans, "a new member under party1 was not rescanned")
assert(VisibleIDs(partyLanes.buff) == IDs(newBuff) and VisibleIDs(partyLanes.debuff) == IDs(newDebuff)
    and partyLanes.buff.all[oldBuff.auraInstanceID] == nil and partyLanes.debuff.all[oldDebuff.auraInstanceID] == nil,
    "party1 still shows the previous member's auras: " .. VisibleIDs(partyLanes.buff) .. " / "
    .. VisibleIDs(partyLanes.debuff))
scans = api.slots
Roster(party)
assert(api.slots == scans, "the rescan did not restamp the member, so every roster event rescans")

-- The slot empties: the lanes clear, and an empty slot stays quiet.
guids.party1, exists.party1 = nil, false
partyList[1], partyList[2] = nil, nil
Roster(party)
assert(partyLanes.buff.visible == 0 and partyLanes.debuff.visible == 0, "an emptied party1 kept its auras")
scans, reads = api.slots, api.guid
Roster(party)
assert(api.slots == scans and api.guid == reads + 1, "an empty slot rescanned on a roster event")

-- A border-only group frame (no aura lanes) follows the member as well.
assert(Border(party2), "precondition: party2 does not show its border")
local resolves = api.index
Roster(party2)
assert(api.index == resolves, "an unchanged member re-resolved a border-only group frame")
UnitList("party2")[1] = nil
guids.party2 = "Player-D"
Roster(party2)
assert(not Border(party2), "a border-only group frame kept the previous member's dispel border")

print("classic aura lane agreement smoke passed")
