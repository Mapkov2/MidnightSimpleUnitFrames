-- Auras3 runtime: CustomConfig.
-- Custom containers, curated spell sets, portrait lanes and reminder descriptors. This module owns their cold configuration and capability watchers.
-- The factory runs once at addon load; dependency bindings are local upvalues on live paths.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
MSUF.Auras3RuntimeFactories = MSUF.Auras3RuntimeFactories or {}
MSUF.Auras3RuntimeFactories.CustomConfig = function(addonName, MSUF, A3, UF, ExportPublic, dependencies)
local SpellIndicatorsRuntime = A3.SpellIndicators
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local pairs = pairs
local table_concat = table.concat
local table_sort = table.sort
local tonumber = tonumber
local tostring = tostring
local type = type
local AddMaxDurationCandidateFilter = dependencies.ConfigValues.AddMaxDurationCandidateFilter
local AuraIconBaseOffset = dependencies.ConfigValues.AuraIconBaseOffset
local ButtonAnchor = dependencies.ConfigValues.ButtonAnchor
local CandidateFiltersFromSpellIDs = dependencies.ConfigValues.CandidateFiltersFromSpellIDs
local Clamp01 = dependencies.Platform.Clamp01
local ClampNumber = dependencies.Platform.ClampNumber
local CreateFrame = dependencies.Platform.CreateFrame
local DEFAULT_SHARED = dependencies.Schema.DEFAULT_SHARED
local FinalizeLane = dependencies.ConfigValues.FinalizeLane
local FrameLayers = dependencies.Platform.FrameLayers
local GridShape = dependencies.ConfigValues.GridShape
local GrowthParts = dependencies.ConfigValues.GrowthParts
local InCombat = dependencies.Platform.InCombat
local NativeFilter = dependencies.ConfigValues.NativeFilter
local NormalizeAuraSortMethod = dependencies.Sort.NormalizeAuraSortMethod
local NormalizeDebuffTypeBorderMode = dependencies.ConfigValues.NormalizeDebuffTypeBorderMode
local NormalizeDurationBarDirection = dependencies.ConfigValues.NormalizeDurationBarDirection
local NormalizeDurationBarDisplay = dependencies.ConfigValues.NormalizeDurationBarDisplay
local NormalizeDurationBarPosition = dependencies.ConfigValues.NormalizeDurationBarPosition
local NormalizeFrameStrata = dependencies.Platform.NormalizeFrameStrata
local ReadAnchor = dependencies.ConfigValues.ReadAnchor
local ReadNumber = dependencies.ConfigValues.ReadNumber
local ReadRaw = dependencies.ConfigValues.ReadRaw
local Round = dependencies.Platform.Round
local Shape = dependencies.Appearance.Shape

local function EmptyUnitFrameConfig(unit)
    return {
        unit = unit,
        enabled = false,
        lanes = {},
        sensors = {},
        group = false,
        _msufA3ConfigGen = A3._runtimeConfigGen or 1,
        _msufA3VisualGen = A3._nativeVisualGen or 0,
    }
end

local function UnitCustomDisplayScope(unit)
    if type(unit) == "string" and unit:match("^boss%d+$") then return "boss" end
    return unit
end

local function EffectiveUnitCustomDisplays(auras, unit)
    local root = type(auras) == "table" and auras.customDisplays or nil
    if type(root) ~= "table" then return nil end
    local scope = UnitCustomDisplayScope(unit)
    local record = type(root.perUnit) == "table" and root.perUnit[scope] or nil
    if type(record) == "table" and record.override == true and type(record.items) == "table" then return record.items end
    return nil
end

local function EffectiveUnitCustomContainers(auras, unit)
    local root = type(auras) == "table" and auras.customContainers or nil
    local scope = UnitCustomDisplayScope(unit)
    local record = type(root) == "table" and type(root.perUnit) == "table" and root.perUnit[scope] or nil
    return type(record) == "table" and type(record.items) == "table" and record.items or nil
end

local function CustomSpellIDHash(value)
    local out, count = {}, 0
    if type(value) == "string" then
        for token in value:gmatch("%d+") do
            local spellID = tonumber(token)
            if spellID and spellID > 0 and out[spellID] ~= true then
                out[spellID] = true
                count = count + 1
            end
        end
    elseif type(value) == "table" then
        for key, enabled in pairs(value) do
            local raw = (type(enabled) == "number" or type(enabled) == "string") and enabled or key
            local spellID = tonumber(type(raw) == "number" and raw or tostring(raw):match("%d+"))
            if enabled ~= false and spellID and spellID > 0 and out[spellID] ~= true then
                out[spellID] = true
                count = count + 1
            end
        end
    end
    return count > 0 and out or nil
end

function A3._CustomPrioritySpellIDs(value, allowed)
    if type(allowed) ~= "table" then return nil end
    local ordered, seen = {}, {}
    local function Add(raw)
        local spellID = tonumber(type(raw) == "number" and raw or tostring(raw or ""):match("%d+"))
        if spellID then spellID = math_floor(spellID + 0.5) end
        if spellID and spellID > 0 and allowed[spellID] == true and not seen[spellID] then
            seen[spellID] = true
            ordered[#ordered + 1] = spellID
        end
    end
    if type(value) == "string" then
        for token in value:gmatch("%d+") do Add(token) end
    elseif type(value) == "table" then
        for i = 1, #value do Add(value[i]) end
        for key, child in pairs(value) do
            if type(key) ~= "number" or key < 1 or key > #value or key % 1 ~= 0 then
                Add((type(child) == "number" or type(child) == "string") and child or key)
            end
        end
    end
    local missing = {}
    for spellID in pairs(allowed) do
        if not seen[spellID] then missing[#missing + 1] = spellID end
    end
    table_sort(missing)
    for i = 1, #missing do ordered[#ordered + 1] = missing[i] end
    return #ordered > 0 and ordered or nil
end

A3._PlayerDefensiveTrackedSpellIDHash = function(entry)
    if type(entry) ~= "table" then return nil end
    local disabled = CustomSpellIDHash(entry.disabledPredefinedSpellIDs)
    local combined, count = {}, 0
    for spellID in pairs(A3._PlayerDefensiveSpellIDHash()) do
        if not (disabled and disabled[spellID] == true) then
            combined[spellID] = true
            count = count + 1
        end
    end
    local custom = CustomSpellIDHash(entry.spellIDs or entry.includeSpellIDs)
    for spellID in pairs(custom or {}) do
        if combined[spellID] ~= true then
            combined[spellID] = true
            count = count + 1
        end
    end
    return count > 0 and combined or nil
end

A3._AddPlayerDefensiveAutoBlacklist = function(candidateFilters, candidateFilterSignature, entry, tracked)
    if type(entry) ~= "table" or entry.autoBlacklistPlayerBuffs == false
        or entry.enabled ~= true
    then
        return candidateFilters, candidateFilterSignature
    end
    tracked = tracked or A3._PlayerDefensiveTrackedSpellIDHash(entry)
    if not tracked then return candidateFilters, candidateFilterSignature end
    candidateFilters = candidateFilters or {}
    local excluded = candidateFilters.excludeSpellIDs
    if type(excluded) ~= "table" then
        excluded = {}
        candidateFilters.excludeSpellIDs = excluded
    end
    local expanded = {}
    for spellID in pairs(tracked) do
        if type(A3.AddAuraSpellIDAndAliases) == "function" then
            A3.AddAuraSpellIDAndAliases(expanded, spellID)
        else
            expanded[spellID] = true
        end
    end
    local parts, count = {}, 0
    for spellID in pairs(expanded) do
        excluded[spellID] = true
        count = count + 1
        parts[count] = tostring(spellID)
    end
    table_sort(parts)
    local autoSignature = "autoPlayerDefensives:" .. table_concat(parts, ",")
    candidateFilterSignature = candidateFilterSignature
        and (candidateFilterSignature .. ";" .. autoSignature) or autoSignature
    return candidateFilters, candidateFilterSignature
end

A3._AddTargetDotAutoBlacklist = function(candidateFilters, candidateFilterSignature, entry, tracked)
    if type(entry) ~= "table" or entry.autoBlacklistDebuffs == false
        or entry.enabled ~= true or type(tracked) ~= "table"
    then
        return candidateFilters, candidateFilterSignature
    end
    local parts, count = {}, 0
    for spellID in pairs(tracked) do
        count = count + 1
        parts[count] = tostring(spellID)
    end
    if count == 0 then return candidateFilters, candidateFilterSignature end
    candidateFilters = candidateFilters or {}
    local excluded = candidateFilters.excludeSpellIDs
    if type(excluded) ~= "table" then
        excluded = {}
        candidateFilters.excludeSpellIDs = excluded
    end
    for spellID in pairs(tracked) do
        excluded[spellID] = true
    end
    table_sort(parts)
    local autoSignature = "autoTargetDots:" .. table_concat(parts, ",")
    candidateFilterSignature = candidateFilterSignature
        and (candidateFilterSignature .. ";" .. autoSignature) or autoSignature
    return candidateFilters, candidateFilterSignature
end

local function TargetDotSpellIDHash()
    local cached = A3._targetDotRuntimeLookup
    if cached then return cached end
    cached = {}
    for _, spells in pairs(A3.TargetDotData or {}) do
        for i = 1, #spells do
            local spellID = tonumber(spells[i][1])
            if spellID then cached[spellID] = true end
        end
    end
    A3._targetDotRuntimeLookup = cached
    return cached
end

local function ManagedLaneFrameLevel(parentFrame, lane)
    local parentLevel = parentFrame and parentFrame.GetFrameLevel and (parentFrame:GetFrameLevel() or 0) or 0
    if lane and lane.portraitOverlay == true then
        -- Portrait auras are a replacement surface owned by the portrait
        -- holder, not an independent unit-frame overlay. Keep the proven
        -- parent-relative birth order: container/host on the holder plane,
        -- native AuraButton one level above it, then cooldown text above the
        -- button. Encoding the lane's universal layer here can put the sealed
        -- native icon below the portrait while the separately levelled text
        -- remains visible.
        return parentLevel
    end
    if FrameLayers.ElementLevel then
        return FrameLayers.ElementLevel(lane and lane.layer, 1, 0)
    end
    return parentLevel + AuraIconBaseOffset(parentFrame) + (lane and lane.layer or 1)
end

local function ResolveLaneParentFrame(parentFrame, lane)
    if lane and lane.anchorTarget == "portrait" and parentFrame then
        if lane.portraitPositionWhenDisabled == true then
            local portrait = parentFrame.MSUFSpec and parentFrame.MSUFSpec.portrait
            if portrait and portrait.enabled ~= true then
                local element = UF and UF.elements and UF.elements.Portrait
                if element and type(element.AcquirePositionAnchor) == "function" then
                    element.AcquirePositionAnchor(parentFrame, portrait)
                end
            end
        end
        return parentFrame.MSUFPortraitHolder or parentFrame
    end
    return parentFrame
end

A3._PlayerDefensiveSpellIDHash = function()
    local playerClass
    if type(UnitClass) == "function" then
        local _
        _, playerClass = UnitClass("player")
    end
    if type(playerClass) ~= "string" or playerClass == "" then playerClass = "__ALL" end
    A3._playerDefensiveRuntimeLookup = A3._playerDefensiveRuntimeLookup or {}
    local cached = A3._playerDefensiveRuntimeLookup[playerClass]
    if cached then return cached end
    cached = {}
    if playerClass == "__ALL" then
        for _, spells in pairs(A3.PlayerDefensiveData or {}) do
            for i = 1, #spells do
                local spellID = tonumber(spells[i][1])
                if spellID then cached[spellID] = true end
            end
        end
    else
        local spells = A3.PlayerDefensiveData and A3.PlayerDefensiveData[playerClass]
        for i = 1, type(spells) == "table" and #spells or 0 do
            local spellID = tonumber(spells[i][1])
            if spellID then cached[spellID] = true end
        end
    end
    A3._playerDefensiveRuntimeLookup[playerClass] = cached
    return cached
end

local function CompileUnitCustomDisplays(auras, unit)
    local source = EffectiveUnitCustomDisplays(auras, unit)
    if type(source) ~= "table" then return nil end
    local items = {}
    for i = 1, #source do
        local entry = source[i]
        if type(entry) == "table" and entry.enabled ~= false then
            local includeSpellIDs = CustomSpellIDHash(entry.spellIDs or entry.includeSpellIDs)
            if includeSpellIDs then
                local helpful = tostring(entry.auraType or "BUFF"):upper() ~= "DEBUFF"
                items[#items + 1] = {
                    key = "ufcustom:" .. tostring(entry.id or i),
                    display = entry.name or ("Custom Aura " .. tostring(i)),
                    enabled = true,
                    includeSpellIDs = includeSpellIDs,
                    nativeFilter = helpful and (entry.onlyOwn == true and "HELPFUL|PLAYER" or "HELPFUL")
                        or (entry.onlyOwn == true and "HARMFUL|PLAYER" or "HARMFUL"),
                    onlyOwn = entry.onlyOwn == true,
                    placed = type(entry.placed) == "table" and entry.placed or nil,
                    frame = type(entry.frame) == "table" and entry.frame or nil,
                    layer = entry.layer,
                    strata = entry.strata,
                    icon = entry.icon,
                    color = entry.color or (type(entry.frame) == "table" and entry.frame.color or nil),
                }
            end
        end
    end
    if #items == 0 then return nil end
    return SpellIndicatorsRuntime.CompileSlots(unit, {
        enabled = true,
        items = items,
        layer = 9,
        strata = "AUTO",
    })
end

-- Shared portrait-lane compilation is kept on the established A3 bridge
-- so player-defensive and target-dot callers retain the same contract.
function A3._CompilePortraitAuraLane(lane, frameSpec, entry, kind, rootKey, scope, exactPortraitRect)
    local portrait = frameSpec and frameSpec.portrait
    local usePortraitPosition = entry and entry.portraitPositionWhenDisabled == true
    if not (lane and portrait and (portrait.enabled == true or usePortraitPosition)) then return nil end
    -- Preserve the proven portrait geometry while retaining the custom lane's
    -- complete Aura Style contract. Portrait mode changes placement only; it
    -- must not silently discard opacity, text, swipe, stacks or duration bars.
    local portraitWidth = ClampNumber(portrait.width, portrait.size or 24, 8, 128)
    local portraitHeight = ClampNumber(portrait.height, portrait.size or 24, 8, 128)
    local size = math_min(portraitWidth, portraitHeight)
    local buttonWidth = exactPortraitRect == true and portraitWidth or size
    local buttonHeight = exactPortraitRect == true and portraitHeight or size
    local spacing = 0
    local maxCount = Round(ClampNumber(entry and entry.portraitMaxIcons, 1, 1, 8))
    local verticalGrowth = lane.verticalGrowth == true
    local perRow = verticalGrowth and 1 or math_max(1, Round(ClampNumber(lane.perRow, 4, 1, 40)))
    local cols, rows = GridShape(maxCount, perRow, verticalGrowth)
    local xSign = tonumber(lane.xSign) or 1
    local ySign = tonumber(lane.ySign) or -1
    local initialAnchor = ButtonAnchor(xSign, ySign)
    local insetX = (portraitWidth - buttonWidth) * 0.5
    local insetY = (portraitHeight - buttonHeight) * 0.5
    local anchorX = initialAnchor:find("RIGHT", 1, true) and -insetX or insetX
    local anchorY = initialAnchor:find("BOTTOM", 1, true) and insetY or -insetY
    local out = {}
    for key, value in pairs(lane) do
        if tostring(key):find("^_msufA3") == nil then out[key] = value end
    end
    out.kind = kind
    out.rootKey = rootKey
    out.anchorTarget = "portrait"
    out.portraitOverlay = true
    out.portraitLevelOffset = portrait.levelOffset
    out.portraitPositionWhenDisabled = usePortraitPosition
    out.enabled = maxCount > 0
    out.max = maxCount
    out.size = size
    out.buttonWidth = buttonWidth
    out.buttonHeight = buttonHeight
    out.spacing = spacing
    out.step = size + spacing
    out.stepX = buttonWidth + spacing
    out.stepY = buttonHeight + spacing
    out.perRow = perRow
    out.cols = cols
    out.rows = rows
    out.padding = 0
    out.width = math_max(1, cols * buttonWidth + math_max(cols - 1, 0) * spacing)
    out.height = math_max(1, rows * buttonHeight + math_max(rows - 1, 0) * spacing)
    -- The standalone bar's saved Edit Mode offsets must NOT leak in here: a
    -- previously dragged bar would push the "portrait" icon out of the
    -- portrait entirely. Icon 1 sits exactly inside the portrait; moving the
    -- portrait itself is the one way to move it.
    out.x = anchorX
    out.y = anchorY
    out.anchor = initialAnchor
    out.layer = 0
    out.strata = "AUTO"
    out.alpha = lane.alpha
    out.growthX = lane.growthX
    out.growthY = lane.growthY
    out.xSign = xSign
    out.ySign = ySign
    out.verticalGrowth = verticalGrowth
    out.initialAnchor = initialAnchor
    out.showCooldownText = lane.showCooldownText == true
        and entry and entry.portraitCooldownText ~= false or false
    -- The AuraButton itself is the portrait replacement. Keep Blizzard's
    -- native duration swipe on that same button so icon, swipe, and duration
    -- text can never split into separate visual owners.
    out.showCooldownSwipe = lane.showCooldownSwipe == true
    out.showDurationBar = lane.showDurationBar == true
    out.showStacks = lane.showStacks == true
    if exactPortraitRect == true then
        -- Portrait presentation is an exact replacement surface: dimensions
        -- and mask always follow this UnitFrame's compiled portrait, regardless
        -- of the normal DoT lane's standalone icon-shape choice.
        out.iconShape, out.requestedIconShape = Shape.Resolve(Shape.FOLLOW_PORTRAIT, portrait.shape)
    end
    return FinalizeLane(out, lane.appearanceKind)
end

A3._CompilePlayerDefensivePortraitLane = function(lane, frameSpec, entry)
    return A3._CompilePortraitAuraLane(
        lane, frameSpec, entry, "defensivePortrait", "DefensivePortrait", "player", false)
end

A3._CompileTargetDotPortraitLane = function(lane, frameSpec, entry, unit)
    if unit ~= "target" and unit ~= "focus" and not tostring(unit or ""):match("^boss%d+$") then return nil end
    return A3._CompilePortraitAuraLane(
        lane, frameSpec, entry, "targetDotPortrait", "TargetDotPortrait", unit, true)
end

--- Upgrade the former shared Custom-4 presentation into the owning frame once.
--- Afterwards Player Defensives and Target DoTs use the same frame-local Style
--- contract as every other Aura container. This is cached config work only.
A3._specialCustomStylePlacedKeys = A3._specialCustomStylePlacedKeys or {
    iconZoom = true, iconShape = true, showTooltip = true, alpha = true,
    debuffTypeBorderMode = true,
    showStacks = true, stackSize = true, stackAnchor = true, stackX = true, stackY = true,
    showCooldown = true, showCooldownSwipe = true, cooldownSwipeReverse = true,
    cooldownSize = true, cooldownAnchor = true, cooldownX = true, cooldownY = true,
    cooldownDecimalSeconds = true,
    showDurationBar = true, durationBarHeight = true, durationBarDisplay = true,
    durationBarPosition = true, durationBarDirection = true,
    pandemicEnabled = true, pandemicStyle = true, pandemicColor = true,
    pandemicThickness = true, pandemicPadding = true,
    pandemicBorderAlpha = true, pandemicTintAlpha = true,
    pandemicBlend = true,
}
local function CopySpecialStyleValue(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, child in pairs(value) do out[key] = CopySpecialStyleValue(child) end
    return out
end
A3._ResolveSpecialCustomStyle = function(auras, unit, index, entry)
    local placed = type(entry) == "table" and type(entry.placed) == "table" and entry.placed or {}
    local frame = type(entry) == "table" and type(entry.frame) == "table" and entry.frame or nil
    if index ~= 4 or type(entry) ~= "table" or entry._msufA3LocalStyleFromShared_v1 == true then
        return placed, frame
    end
    local shared = type(auras) == "table" and type(auras.shared) == "table" and auras.shared or nil
    local styles = shared and type(shared.specialStyles) == "table" and shared.specialStyles or nil
    local key = unit == "player" and "playerDefensives" or "targetDots"
    local record = styles and type(styles[key]) == "table" and styles[key] or nil
    local stylePlaced = record and type(record.placed) == "table" and record.placed or nil
    if stylePlaced then
        entry.placed = placed
        for name in pairs(A3._specialCustomStylePlacedKeys) do
            if stylePlaced[name] ~= nil then placed[name] = CopySpecialStyleValue(stylePlaced[name]) end
        end
    end
    if record and type(record.frame) == "table" then
        entry.frame = CopySpecialStyleValue(record.frame)
        frame = entry.frame
    end
    entry._msufA3LocalStyleFromShared_v1 = true
    return placed, frame
end

--- Spell catalog lookup for a Buff Reminder placeholder. Spell art is plain
--- catalog data, not aura state: it stays readable under every 12.1 secret
--- restriction, which is exactly why the placeholder can be drawn at all.
--- Item art for a Buff Reminder placeholder. Like spell art this is plain
--- catalog data, so it stays readable under every secret restriction.
function A3._ReminderItemIcon(itemID)
    itemID = tonumber(itemID)
    if not itemID then return nil end
    local CI = _G.C_Item
    if type(CI) == "table" and type(CI.GetItemIconByID) == "function" then
        return CI.GetItemIconByID(itemID)
    end
    return nil
end

function A3._ReminderSpellIcon(spellID)
    spellID = tonumber(spellID)
    if not spellID then return nil end
    local CS = _G.C_Spell
    if type(CS) ~= "table" then return nil end
    if type(CS.GetSpellTexture) == "function" then
        local icon = CS.GetSpellTexture(spellID)
        if icon then return icon end
    end
    if type(CS.GetSpellInfo) == "function" then
        local info = CS.GetSpellInfo(spellID)
        if type(info) == "table" then return info.iconID or info.icon end
    end
    return nil
end

--- "Only what I can apply myself". One whitelist then serves every character:
--- a Mage sees Arcane Intellect, a Rogue sees the poisons, from the same
--- profile. Evaluated on the compile path only; the watcher below re-runs it
--- when the set of known spells actually changes.
function A3._ReminderSpellIsSelfCastable(spellID)
    spellID = tonumber(spellID)
    if not spellID then return false end
    local book = _G.C_SpellBook
    if type(book) == "table" and type(book.IsSpellKnown) == "function"
        and book.IsSpellKnown(spellID) == true then return true end
    local isPlayerSpell = _G.IsPlayerSpell
    if type(isPlayerSpell) == "function" and isPlayerSpell(spellID) == true then return true end
    return false
end

A3._reminderSelfCastState = A3._reminderSelfCastState or {}

--- Lazily created, and only once a container actually uses the filter. The
--- spellbook cannot change during combat, so an in-combat event is never a
--- real change: the entire in-combat cost of this feature is the lockdown
--- check below, and the recheck is handed to PLAYER_REGEN_ENABLED.
function A3._EnsureReminderSelfCastWatch()
    if A3._reminderSelfCastWatch then return A3._reminderSelfCastWatch end
    local frame = CreateFrame("Frame")
    frame:SetScript("OnEvent", function(self)
        if InCombat() then
            self:RegisterEvent("PLAYER_REGEN_ENABLED")
            return
        end
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        local state = A3._reminderSelfCastState
        local changed = false
        for spellID, known in pairs(state) do
            local now = A3._ReminderSpellIsSelfCastable(spellID)
            if now ~= known then
                state[spellID] = now
                changed = true
            end
        end
        -- SPELLS_CHANGED is noisy. Only a real change to a tracked spell is
        -- worth a config rebuild.
        if not changed then return end
        A3.BumpRuntimeConfig()
        A3.RefreshAll()
    end)
    frame:RegisterEvent("SPELLS_CHANGED")
    frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    frame:RegisterEvent("PLAYER_TALENT_UPDATE")
    A3._reminderSelfCastWatch = frame
    return frame
end

--- Temporary weapon enchant reminders. Oils, stones and weapon-applied
--- poisons are NOT auras: Blizzard keeps them out of aura parsing, groups and
--- slots, and surfaces them through C_PaperDollInfo instead. That API carries
--- no secret annotation, so an enchant reminder can show its real state
--- everywhere -- unlike an aura reminder, which can only be occluded.
--- Player-only by definition: the query reports the player's own equipment.
A3.REMINDER_ENCHANT_SLOTS = A3.REMINDER_ENCHANT_SLOTS or {
    { key = "mainHand", token = "MAINHAND", label = "Main Hand",
      enabledKey = "reminderEnchantMainHand",
      inventorySlot = _G.INVSLOT_MAINHAND or 16 },
    { key = "offHand", token = "OFFHAND", label = "Off Hand",
      enabledKey = "reminderEnchantOffHand",
      inventorySlot = _G.INVSLOT_OFFHAND or 17 },
}

--- Buff Reminder. Every whitelisted spell becomes one fixed AuraSlot laid out
--- on the container's own grid, each with an MSUF-owned placeholder beneath
--- it. Fixed slots are mandatory here: Blizzard's flowing AuraGroup compacts
--- active auras together, which would park a running aura on a different
--- spell's placeholder. Slot order follows the whitelist order the user drags
--- in the menu, independently of the container's sort method.
function A3._CompileCustomReminderItems(lane, entry, index, placed, filters)
    if type(lane) ~= "table" or type(entry) ~= "table" or type(placed) ~= "table" then return nil end
    if placed.reminderEnabled ~= true then return nil end
    -- Aliases select the same configured spell; they never create another
    -- placeholder, click binding, self-castability test or priority position.
    local allowed = lane.sourceSpellIDs
    local ordered = A3._CustomPrioritySpellIDs(entry.prioritySpellIDs, allowed)
    local count = ordered and math_min(#ordered, Round(lane.max or 0)) or 0
    -- An enchant-only reminder is legitimate: oils need no whitelisted aura.
    local hasEnchant = lane.unit == "player" and Round(lane.max or 0) > 0
        and (entry.reminderEnchantMainHand == true or entry.reminderEnchantOffHand == true)
    if count <= 0 and not hasEnchant then return nil end
    local perRow = math_max(Round(lane.perRow or 1), 1)
    local step = lane.step or lane.size or 1
    local xSign, ySign = lane.xSign or 1, lane.ySign or -1
    local tint = type(placed.reminderColor) == "table" and placed.reminderColor or nil
    local alpha = Clamp01(placed.reminderAlpha, 0.45)
    local desaturate = placed.reminderDesaturate ~= false
    local hidePermanent = type(filters) == "table" and filters.hidePermanent == true
    -- Click-to-cast turns each placeholder into a SecureActionButton bound to
    -- that slot's own spell. It is configuration only: the binding is written
    -- once out of combat and never consults the aura state it sits on.
    local clickCast = placed.reminderClickCast ~= false
    local selfCastOnly = placed.reminderOnlyCastable == true
    -- Items bound to a tracked aura: the slot keeps tracking the aura but
    -- shows the item and uses it on click. Flasks, runes and stones apply
    -- their own buff, so one whitelist entry covers both halves.
    local boundItems = type(entry.reminderItems) == "table" and entry.reminderItems or nil
    -- Rows the user pinned as "always show". No API tells us which class owns a
    -- spell, so a flask buff and a foreign class ability are indistinguishable
    -- to a castable test: this list is how the difference gets stated.
    local keepSpells = type(entry.reminderKeepSpells) == "table" and entry.reminderKeepSpells or nil
    local items = {}
    local function GridOffset(gridIndex)
        local n = gridIndex - 1
        local col, row
        if lane.verticalGrowth == true then
            col, row = 0, n
        else
            col, row = n % perRow, math_floor(n / perRow)
        end
        return Round((lane.x or 0) + col * step * xSign),
            Round((lane.y or 0) + row * step * ySign)
    end
    -- Hidden entries must leave no gap, so the grid follows a running counter
    -- over the VISIBLE rows rather than the whitelist index.
    local placedCount = 0
    for i = 1, count do
        local spellID = ordered[i]
        local boundItemID = boundItems and tonumber(boundItems[spellID]) or nil
        -- A bound item is class agnostic and was chosen on purpose, so only
        -- plain spell rows are filtered by "what I can apply myself".
        local visible = true
        if selfCastOnly and not boundItemID and not (keepSpells and keepSpells[spellID] == true) then
            visible = A3._ReminderSpellIsSelfCastable(spellID)
            A3._reminderSelfCastState[spellID] = visible
            A3._EnsureReminderSelfCastWatch()
        end
        if visible then
            placedCount = placedCount + 1
            local slotX, slotY = GridOffset(placedCount)
            items[#items + 1] = {
                key = "reminder_" .. tostring(index) .. "_" .. tostring(spellID),
                display = tostring(entry.name or ("Custom " .. tostring(index))),
                enabled = true,
                unit = lane.unit,
                includeSpellIDs = { [spellID] = true },
                nativeFilter = lane.nativeFilter,
                hidePermanent = hidePermanent,
                icon = boundItemID and A3._ReminderItemIcon(boundItemID) or A3._ReminderSpellIcon(spellID),
                showWhenMissing = true,
                reminderAlpha = alpha,
                reminderDesaturate = desaturate,
                reminderColor = tint,
                castSpellID = clickCast and not boundItemID and spellID or nil,
                castItem = clickCast and boundItemID and ("item:" .. tostring(boundItemID)) or nil,
                castItemID = clickCast and boundItemID or nil,
                castUnit = clickCast and lane.unit or nil,
                iconZoom = lane.iconZoom,
                iconShape = lane.iconShape,
                requestedIconShape = lane.requestedIconShape,
                layer = lane.layer,
                strata = lane.strata,
                placed = {
                    type = "icon",
                    anchor = lane.anchor,
                    x = slotX,
                    y = slotY,
                    size = lane.size,
                    showCooldown = lane.showCooldownText,
                    showCooldownSwipe = lane.showCooldownSwipe,
                    cooldownSwipeReverse = lane.cooldownSwipeReverse,
                    showStacks = lane.showStacks,
                    showTooltip = lane.showTooltip,
                    cooldownSize = lane.cooldownSize,
                    cooldownAnchor = lane.cooldownAnchor,
                    cooldownX = lane.cooldownX,
                    cooldownY = lane.cooldownY,
                    cooldownDecimalSeconds = lane.cooldownDecimalSeconds,
                },
            }
        end
    end
    -- Enchant reminders continue the same grid after the visible spells
    -- and obey the same icon cap, so the row never grows unexpectedly.
    if lane.unit == "player" then
        local position = placedCount
        local maxSlots = Round(lane.max or 0)
        for i = 1, #A3.REMINDER_ENCHANT_SLOTS do
            local spec = A3.REMINDER_ENCHANT_SLOTS[i]
            if entry[spec.enabledKey] == true and position < maxSlots then
                position = position + 1
                -- One consumable covers both weapons in practice, so the
                -- item is shared rather than duplicated per hand.
                local itemID = tonumber(entry.reminderEnchantItem)
                local durationSeconds = ClampNumber(
                    entry.reminderEnchantDurationMinutes, 60, 5, 240) * 60
                local slotX, slotY = GridOffset(position)
                items[#items + 1] = {
                    key = "reminderench_" .. tostring(index) .. "_" .. spec.key,
                    display = spec.label,
                    enabled = true,
                    unit = lane.unit,
                    enchantSlot = spec.token,
                    enchantInventorySlot = spec.inventorySlot,
                    enchantDurationSeconds = durationSeconds,
                    icon = A3._ReminderItemIcon(itemID),
                    showWhenMissing = true,
                    reminderAlpha = alpha,
                    reminderDesaturate = desaturate,
                    reminderColor = tint,
                    iconZoom = lane.iconZoom,
                    iconShape = lane.iconShape,
                    requestedIconShape = lane.requestedIconShape,
                    layer = lane.layer,
                    strata = lane.strata,
                    castItem = clickCast and itemID and ("item:" .. tostring(itemID)) or nil,
                    castItemID = clickCast and itemID or nil,
                    castUnit = clickCast and itemID and lane.unit or nil,
                    placed = {
                        type = "icon",
                        anchor = lane.anchor,
                        x = slotX,
                        y = slotY,
                        size = lane.size,
                        showTooltip = lane.showTooltip,
                        -- Enchant slots have no AuraButton, but their plain
                        -- remainingTimeMs feeds an MSUF-owned native Duration
                        -- object on the persistent reminder placeholder.
                        showCooldown = lane.showCooldownText,
                        showCooldownSwipe = lane.showCooldownSwipe,
                        cooldownSwipeReverse = lane.cooldownSwipeReverse,
                        cooldownSize = lane.cooldownSize,
                        cooldownAnchor = lane.cooldownAnchor,
                        cooldownX = lane.cooldownX,
                        cooldownY = lane.cooldownY,
                        cooldownDecimalSeconds = lane.cooldownDecimalSeconds,
                        showStacks = false,
                    },
                }
            end
        end
    end
    return #items > 0 and items or nil
end

local function CompileUnitCustomLane(unit, entry, index, lanePadding, frameSpec, shared, auras)
    if type(entry) ~= "table" then return nil, nil end
    local playerDefensives = unit == "player" and (index == 4 or entry.playerDefensives == true)
    -- `enabled` is the Core feature's master switch. Portrait mode is only a
    -- presentation choice and cannot keep a disabled feature alive.
    if entry.enabled ~= true then return nil, nil end
    local sourceSpellIDs = CustomSpellIDHash(entry.spellIDs or entry.includeSpellIDs)
    local includeSpellIDs = sourceSpellIDs
    local targetDots = not playerDefensives and (index == 4 or entry.targetDots == true)
    -- Target DoT portrait presentation belongs exclusively to the reserved
    -- index-4 lane. Custom 1-3 must remain normal custom containers even if a
    -- stale/imported record happens to carry the targetDots marker.
    local portraitRequested = (playerDefensives or (targetDots and index == 4))
        and entry.portraitIcon == true
    if playerDefensives then
        includeSpellIDs = A3._PlayerDefensiveTrackedSpellIDHash(entry)
    end
    if targetDots and includeSpellIDs then
        local allowed, customAllowed, count = TargetDotSpellIDHash(), CustomSpellIDHash(entry.customSpellIDs), 0
        for spellID in pairs(includeSpellIDs) do
            if allowed[spellID] ~= true and not (customAllowed and customAllowed[spellID] == true) then
                includeSpellIDs[spellID] = nil
            else
                count = count + 1
            end
        end
        if count == 0 then includeSpellIDs = nil end
    end
    -- A Buff Reminder that only watches temporary weapon enchants has no aura
    -- to whitelist at all: enchants never reach aura parsing, so an empty
    -- whitelist is the normal state for an oil reminder. Keep compiling so
    -- its enchant slots can still be built.
    local reminderPlaced = type(entry.placed) == "table" and entry.placed or nil
    local enchantOnlyReminder = unit == "player" and not playerDefensives and not targetDots
        and reminderPlaced ~= nil and reminderPlaced.reminderEnabled == true
        and (entry.reminderEnchantMainHand == true or entry.reminderEnchantOffHand == true)
    if not includeSpellIDs and not enchantOnlyReminder then return nil, nil end
    -- Resolve only user-selected IDs after DoT eligibility pruning. Curated
    -- defensive defaults and disabled entries retain their explicit ID rules.
    A3.CompileCustomAuraAliases(sourceSpellIDs)
    local candidateFilters, candidateFilterSignature = CandidateFiltersFromSpellIDs(includeSpellIDs, "includeSpellIDs")
    local layoutPlaced = type(entry.placed) == "table" and entry.placed or {}
    local placed, styleFrame = A3._ResolveSpecialCustomStyle(auras, unit, index, entry)
    -- Player Defensive Buffs combines a curated class list with custom IDs and
    -- therefore keeps ordinary AuraKit sorting. Every exact-ID custom lane,
    -- including Dots on target, can use the same native one-group-per-spell
    -- priority path without inspecting aura payloads in Lua.
    local customPriority = not playerDefensives
        and tostring(placed.sortMethod or ""):upper() == "CUSTOM_PRIORITY"
    local customPrioritySpellIDs = customPriority
        and A3._CustomPrioritySpellIDs(entry.prioritySpellIDs, includeSpellIDs) or nil
    lanePadding = ClampNumber((type(placed) == "table" and placed.stylePadding)
        or layoutPlaced.stylePadding, 0, 0, 16)
    local filters = type(entry.filters) == "table" and entry.filters or { enabled = true, onlyMine = entry.onlyOwn == true }
    local sourceUnit = unit
    local helpful = not targetDots and tostring(entry.auraType or "BUFF"):upper() ~= "DEBUFF"
    candidateFilters, candidateFilterSignature = AddMaxDurationCandidateFilter(
        candidateFilters, candidateFilterSignature,
        filters.maxDuration, filters.hidePermanent == true)
    local size = ClampNumber(layoutPlaced.size, 24, 1, 128)
    local spacing = ClampNumber(layoutPlaced.spacing, 2, 0, 64)
    local perRow = ClampNumber(layoutPlaced.perRow, 4, 1, 40)
    local maxCount = ClampNumber(layoutPlaced.max, 8, 0, 40)
    local growthX, growthY, xSign, ySign, verticalGrowth = GrowthParts(layoutPlaced.growth or "LEFTDOWN", "DOWN")
    local cols, rows = GridShape(maxCount, perRow, verticalGrowth)
    local appearanceKind = playerDefensives and "playerDefensives"
        or targetDots and "targetDots" or (helpful and "buff" or "debuff")
    local iconShapeSource = Shape.SharedValue(shared, appearanceKind)
    local iconShape, requestedIconShape = Shape.Resolve(
        iconShapeSource, frameSpec and frameSpec.portrait and frameSpec.portrait.shape)
    lanePadding = Round(ClampNumber(lanePadding, 0, 0, 16))
    local pandemicVisualEnabled = targetDots == true and placed.pandemicEnabled == true
    local pandemicFrameEffect
    if targetDots == true and type(styleFrame) == "table" and styleFrame.onlyInPandemicWindow == true then
        local normalizeFrameEffect = SpellIndicatorsRuntime.NormalizeFrameEffect
        pandemicFrameEffect = type(normalizeFrameEffect) == "function"
            and normalizeFrameEffect(styleFrame) or styleFrame
    end
    local lane = FinalizeLane({
        kind = "custom" .. tostring(index),
        appearanceKind = appearanceKind,
        rootKey = "CustomAuras" .. tostring(index),
        unit = sourceUnit,
        enabled = maxCount > 0,
        nativeFilter = targetDots and "HARMFUL|PLAYER"
            or (playerDefensives and "HELPFUL" or NativeFilter(helpful and "HELPFUL" or "HARMFUL", filters)),
        candidateFilters = candidateFilters,
        candidateFilterSignature = candidateFilterSignature,
        -- Exact spell-ID filters are valid only for the current unit polarity.
        -- Compile this once; the live identity route never reads settings.
        identityCandidateMode = helpful and "assist" or "hostile",
        -- Keep user intent separate from expanded native candidate membership.
        sourceSpellIDs = sourceSpellIDs,
        max = Round(maxCount),
        size = size,
        iconZoom = ClampNumber(placed.iconZoom, 100, 100, 200),
        iconShape = iconShape,
        requestedIconShape = requestedIconShape,
        spacing = spacing,
        step = size + spacing,
        perRow = Round(perRow),
        cols = cols,
        rows = rows,
        padding = lanePadding,
        width = math_max(1, cols * size + math_max(cols - 1, 0) * spacing + 2 * lanePadding),
        height = math_max(1, rows * size + math_max(rows - 1, 0) * spacing + 2 * lanePadding),
        x = Round(ClampNumber(layoutPlaced.x, 0, -4096, 4096)),
        y = Round(ClampNumber(layoutPlaced.y, 0, -4096, 4096)),
        anchor = ReadAnchor(layoutPlaced, nil, "anchor", "TOPRIGHT"),
        layer = Round(ClampNumber(entry.layer, 9, 0, 30)),
        strata = NormalizeFrameStrata(entry.strata, "AUTO"),
        alpha = Clamp01(placed.alpha, 1),
        growthX = growthX,
        growthY = growthY,
        xSign = xSign,
        ySign = ySign,
        verticalGrowth = verticalGrowth == true,
        initialAnchor = ButtonAnchor(xSign, ySign),
        showCooldownText = placed.showCooldown ~= false,
        showCooldownSwipe = placed.showCooldownSwipe ~= false,
        cooldownSwipeReverse = placed.cooldownSwipeReverse == true,
        -- CUSTOM_PRIORITY is an MSUF-owned ordered-group mode, not a Blizzard
        -- AuraContainerSortMethod enum. Each one-frame AuraGroup is natively
        -- filtered to one configured Spell ID and assigned a layoutIndex, so
        -- Blizzard can compact active custom auras in priority order without
        -- exposing their restricted payload or visibility to addon Lua.
        sortMethod = customPriority and "DEFAULT" or NormalizeAuraSortMethod(placed.sortMethod),
        sortReverse = customPriority and false or placed.sortReverse == true,
        customPriority = customPriority == true,
        customPrioritySpellIDs = customPrioritySpellIDs,
        customPrioritySignature = customPrioritySpellIDs and table_concat(customPrioritySpellIDs, ",") or nil,
        showDurationBar = placed.showDurationBar == true,
        durationBarHeight = ClampNumber(placed.durationBarHeight, DEFAULT_SHARED.durationBarHeight, 1, 16),
        durationBarDisplay = NormalizeDurationBarDisplay(placed.durationBarDisplay, DEFAULT_SHARED.durationBarDisplay),
        durationBarPosition = NormalizeDurationBarPosition(placed.durationBarPosition, DEFAULT_SHARED.durationBarPosition),
        durationBarDirection = NormalizeDurationBarDirection(placed.durationBarDirection, DEFAULT_SHARED.durationBarDirection),
        showStacks = placed.showStacks ~= false,
        showTooltip = placed.showTooltip ~= false,
        showAuraBorder = not helpful and NormalizeDebuffTypeBorderMode(placed.debuffTypeBorderMode, "OFF") ~= "OFF",
        showAuraSymbol = not helpful and NormalizeDebuffTypeBorderMode(placed.debuffTypeBorderMode, "OFF") == "SYMBOL",
        cooldownSize = ClampNumber(placed.cooldownSize, DEFAULT_SHARED.cooldownTextSize, 6, 40),
        cooldownAnchor = ReadAnchor(placed, nil, "cooldownAnchor", "CENTER"),
        cooldownX = ClampNumber(placed.cooldownX, 0, -2000, 2000),
        cooldownY = ClampNumber(placed.cooldownY, 0, -2000, 2000),
        cooldownDecimalSeconds = ClampNumber(placed.cooldownDecimalSeconds, DEFAULT_SHARED.cooldownDecimalSeconds, 0, 30),
        stackAnchor = ReadAnchor(placed, nil, "stackAnchor", "BOTTOMRIGHT"),
        stackSize = ClampNumber(placed.stackSize, DEFAULT_SHARED.stackTextSize, 6, 40),
        stackX = ClampNumber(placed.stackX, 0, -2000, 2000),
        stackY = ClampNumber(placed.stackY, 0, -2000, 2000),
        targetDots = targetDots == true,
        pandemicEnabled = pandemicVisualEnabled or pandemicFrameEffect ~= nil,
        pandemicVisualEnabled = pandemicVisualEnabled,
        pandemicFrameEffect = pandemicFrameEffect,
        pandemicStyle = A3.NormalizePandemicStyle(placed.pandemicStyle),
        pandemicColor = type(placed.pandemicColor) == "table" and placed.pandemicColor or A3.DEFAULT_PANDEMIC_COLOR,
        pandemicThickness = ClampNumber(placed.pandemicThickness, 2, 1, 12),
        pandemicPadding = ClampNumber(placed.pandemicPadding, 1, -8, 16),
        pandemicBorderAlpha = Clamp01(placed.pandemicBorderAlpha, 1),
        pandemicTintAlpha = Clamp01(placed.pandemicTintAlpha, 0.22),
        pandemicBlend = tostring(placed.pandemicBlend or "ADD"):upper() == "BLEND" and "BLEND" or "ADD",
    })
    -- Reminder mode owns the container's whole presentation: the flowing lane
    -- is dropped so one aura can never be rendered twice. Reserved index 4
    -- (Player Defensives / Dots on target) keeps its fixed preset product.
    local reminderItems
    if not playerDefensives and not targetDots then
        reminderItems = A3._CompileCustomReminderItems(lane, entry, index, placed, filters)
    end
    local portraitLane
    if portraitRequested then
        if playerDefensives then
            portraitLane = A3._CompilePlayerDefensivePortraitLane(lane, frameSpec, entry)
        elseif targetDots then
            portraitLane = A3._CompileTargetDotPortraitLane(lane, frameSpec, entry, unit)
        end
    end
    -- If the visible portrait is disabled and its position-only option is also
    -- off, fall back to the normal bar instead of silently losing tracked auras.
    local barEnabled = portraitLane == nil
    local effect
    -- Unconditional Full-Frame effects remain independent aura sensors in portrait mode.
    -- Pandemic-only effects live on every visible DoT AuraButton and need no duplicate sensor.
    if pandemicFrameEffect == nil and type(styleFrame) == "table" and styleFrame.type and styleFrame.type ~= "none" then
        effect = {
            key = "ufcustom_effect:" .. tostring(index),
            display = entry.name or ("Custom " .. tostring(index)),
            enabled = true,
            includeSpellIDs = includeSpellIDs,
            hidePermanent = filters.hidePermanent == true,
            nativeFilter = lane.nativeFilter,
            placed = { type = "none", anchor = layoutPlaced.anchor or "TOPRIGHT", x = 0, y = 0, size = 1 },
            frame = styleFrame,
            layer = entry.layer or 9,
            strata = entry.strata or "AUTO",
            color = styleFrame.color,
            unit = sourceUnit,
        }
    end
    return barEnabled and not reminderItems and lane or nil, effect, portraitLane, reminderItems
end

local function CompileUnitCustomContainers(auras, unit, frameSpec)
    local source = EffectiveUnitCustomContainers(auras, unit)
    if type(source) ~= "table" then return nil, nil end
    -- Custom containers carry their own spacing in the per-container record;
    -- there is no Unit-wide or Shared lane-padding fallback.
    local lanes, effectItems, targetDotEffectItems = {}, {}, {}
    for i = 1, 4 do
        local lane, effect, portraitLane, reminderItems =
            CompileUnitCustomLane(unit, source[i], i, nil, frameSpec, auras.shared, auras)
        if lane then lanes["custom" .. tostring(i)] = lane end
        if portraitLane then lanes[portraitLane.kind] = portraitLane end
        -- Reminder slots ride the frame's existing Spell Indicator root: it
        -- already owns fixed AuraSlots, identity partitioning, geometry sync
        -- and teardown, so no second container lifecycle is introduced.
        if reminderItems then
            for j = 1, #reminderItems do effectItems[#effectItems + 1] = reminderItems[j] end
        end
        if effect then
            local bucket = i == 4 and unit ~= "player" and targetDotEffectItems or effectItems
            bucket[#bucket + 1] = effect
        end
    end
    local effects, targetDotEffects
    if #effectItems > 0 then
        effects = SpellIndicatorsRuntime.CompileSlots(unit, { enabled = true, items = effectItems, layer = 9, strata = "AUTO", rootKey = "SpellIndicators" })
    end
    if #targetDotEffectItems > 0 then
        targetDotEffects = SpellIndicatorsRuntime.CompileSlots(
            targetDotEffectItems[1].unit or unit,
            { enabled = true, items = targetDotEffectItems, layer = 9, strata = "AUTO", rootKey = "TargetDotEffects" })
    end
    return lanes, effects, targetDotEffects
end
A3._CompileUnitCustomContainers = CompileUnitCustomContainers

local function CompileUnitLaneEffects(unit, laneLayout, buff, debuff)
    local items = {}
    local function Add(kind, lane)
        if not (lane and lane.enabled == true) then return end
        local prefix = kind == "buff" and "buff" or "debuff"
        local effectType = tostring(ReadRaw(laneLayout, nil, prefix .. "FrameEffectType") or "none"):lower()
        if effectType == "none" or effectType == "" then return end
        local color = ReadRaw(laneLayout, nil, prefix .. "FrameEffectColor")
        items[#items + 1] = {
            key = "uflane_effect:" .. kind,
            display = kind == "buff" and "Buffs" or "Debuffs",
            enabled = true,
            allowAnyAura = true,
            candidateFilters = lane.candidateFilters,
            candidateFilterSignature = lane.candidateFilterSignature,
            nativeFilter = lane.nativeFilter,
            placed = { type = "none", anchor = "CENTER", x = 0, y = 0, size = 1 },
            frame = {
                type = effectType,
                color = type(color) == "table" and color or { 0.69, 0.50, 0.88, 0.80 },
                priority = ReadNumber(laneLayout, nil, prefix .. "FrameEffectPriority", 5, 1, 10),
                thickness = ReadNumber(laneLayout, nil, prefix .. "FrameEffectThickness", 2, 1, 16),
                layer = ReadNumber(laneLayout, nil, prefix .. "FrameEffectLayer", 0, 0, 30),
                strata = ReadRaw(laneLayout, nil, prefix .. "FrameEffectStrata") or "AUTO",
            },
            layer = 9,
            strata = "AUTO",
        }
    end
    Add("buff", buff)
    Add("debuff", debuff)
    if #items == 0 then return nil end
    return SpellIndicatorsRuntime.CompileSlots(unit, {
        enabled = true, items = items, layer = 9, strata = "AUTO", rootKey = "LaneEffects",
    })
end

return {
    CompileUnitCustomContainers = CompileUnitCustomContainers,
    CompileUnitCustomDisplays = CompileUnitCustomDisplays,
    CompileUnitLaneEffects = CompileUnitLaneEffects,
    EffectiveUnitCustomContainers = EffectiveUnitCustomContainers,
    EmptyUnitFrameConfig = EmptyUnitFrameConfig,
    ManagedLaneFrameLevel = ManagedLaneFrameLevel,
    ResolveLaneParentFrame = ResolveLaneParentFrame,
}
end
