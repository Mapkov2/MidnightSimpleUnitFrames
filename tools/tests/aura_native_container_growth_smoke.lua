-- Native AuraContainers stay bounded across menu edits (Retail and WoW Forever).
--
-- A frame is never freed, and Blizzard's 12.1 AuraContainer neither removes an
-- AuraGroup or AuraSlot nor lets addon code restyle a button once its
-- initializeFrame has returned. Retiring a container therefore orphaned it and
-- its batch of AuraButtons for the session (re-review R6):
--   * the lane signature held the lane's offsets and alpha, so every step of a
--     position or opacity slider built a new container, on every unit and group
--     frame the lane draws on;
--   * the lane park kept eight signatures, so a slider drag across more values
--     rebuilt the ones it had evicted;
--   * dispel sensor roots, group owners (one-deep memo) and Spell Indicator
--     roots were never parked, and HideState dropped every live container.
--
-- The real Signatures, OwnerConfig, NativeContract, Containers, NativeApply and
-- Spell Indicator runtime run here against a counting AuraContainer model whose
-- AuraButtons refuse scripts once initializeFrame returns (as the client does)
-- and count every write after it. The cases, on a target frame and a party
-- frame (a group owner with a fixed slot lane, a flowing lane, a dispel sensor
-- and a Spell Indicator):
--   * 50 position and 50 opacity steps of a flowing lane build nothing and
--     touch no button: the host moves and the container fades (a group owner
--     still builds one for an opacity change: it sets each button's alpha in
--     initializeFrame);
--   * 50 steps of a structural slider over 12 values build one per value;
--   * 12 distinct group layouts applied twice build 12, the second pass none;
--   * a lane toggled off and on, a sensor toggled off and on, a Spell
--     Indicator moved and moved back, and the frame's auras switched off and on
--     (HideState) build nothing, and a revived Spell Indicator lists its frame
--     effect again;
--   * a forced recreate builds a fresh container and drops the key's park,
--     which may hold containers from before PLAYER_ENTERING_WORLD.
-- Runs through .github/scripts/auras3_test_driver.lua with the repository root
-- as the working directory (MSUF_AURAS3_TEST_SOURCE_ROOT swaps in other Auras3
-- sources for mutation runs).
local root = assert(arg[1], "repository root argument missing")
root = (tostring(root):gsub("\\", "/"):gsub("/+$", ""))
local ADDON = root .. "/MidnightSimpleUnitFrames/"

local counts = { containers = 0, buttons = 0, sealedWrites = 0 }
local function Noop() end

-- Widget model ------------------------------------------------------------------------
local Region = {}
Region.__index = Region
local function NewRegion(kind, parent, class)
    local region = setmetatable({ _kind = kind, _parent = parent, _shown = true, _alpha = 1,
        _level = parent and ((parent._level or 0) + 1) or 1 }, class or Region)
    return region
end
local function Sealed(region)
    while region do
        if region._sealed == true then return true end
        region = region._parent
    end
    return false
end
function Region:Show() self._shown = true end
function Region:Hide() self._shown = false end
function Region:SetShown(shown) self._shown = shown and true or false end
function Region:IsShown() return self._shown end
function Region:IsVisible()
    if not self._shown then return false end
    return self._parent == nil or self._parent:IsVisible()
end
function Region:GetParent() return self._parent end
function Region:SetParent(parent) self._parent = parent end
function Region:SetAlpha(alpha) self._alpha = alpha end
function Region:GetAlpha() return self._alpha end
function Region:GetFrameLevel() return self._level end
function Region:SetFrameLevel(level) self._level = level end
function Region:GetFrameStrata() return self._strata or "MEDIUM" end
function Region:SetFrameStrata(strata) self._strata = strata end
function Region:SetPoint(point, relative, relativePoint, x, y)
    self._point = { point, relative, relativePoint, x, y }
end
function Region:ClearAllPoints() self._point = nil end
function Region:SetAllPoints(relative) self._point = { "ALL", relative } end
function Region:GetObjectType() return self._kind end
function Region:IsForbidden() return false end
function Region:GetWidth() return 20 end
function Region:GetHeight() return 20 end
function Region:GetSize() return 20, 20 end
function Region:GetNumPoints() return self._point and 1 or 0 end
function Region:SetScript(name, handler)
    if Sealed(self) then error("Frame:SetScript(): Cannot assign script handler for '" .. tostring(name)
        .. "' (blocked by secret aspects)", 2) end
    self._scripts = self._scripts or {}
    self._scripts[name] = handler
end
Region.HookScript = Region.SetScript
function Region:GetScript(name) return self._scripts and self._scripts[name] end
function Region:CreateTexture() return NewRegion("Texture", self) end
Region.CreateFontString = function(self) return NewRegion("FontString", self) end
Region.CreateMaskTexture = Region.CreateTexture
function Region:CreateAnimationGroup() return NewRegion("AnimationGroup", self) end
function Region:CreateAnimation() return NewRegion("Animation", self) end
for _, name in ipairs({
    "SetSize", "SetWidth", "SetHeight", "EnableMouse", "SetMouseClickEnabled", "SetMouseMotionEnabled",
    "SetTexture", "SetTexCoord", "SetVertexColor", "SetColorTexture", "SetDrawLayer", "SetBlendMode",
    "SetDesaturated", "SetFont", "SetFontObject", "SetText", "SetTextColor", "SetShadowOffset", "SetShadowColor",
    "SetJustifyH", "SetJustifyV", "SetIgnoreParentAlpha", "SetIgnoreParentScale", "SetScale", "SetDrawSwipe",
    "SetSwipeColor", "SetHideCountdownNumbers", "SetDrawBling", "SetDrawEdge", "SetReverse", "SetSwipeTexture",
    "SetCountdownMillisecondsThreshold", "SetMinMaxValues", "SetValue", "SetStatusBarTexture", "SetStatusBarColor",
    "SetOrientation", "SetReverseFill", "AddMaskTexture", "RemoveMaskTexture", "RegisterEvent", "UnregisterEvent",
    "SetAttribute", "SetClipsChildren", "SetAtlas", "SetSnapToPixelGrid", "SetTexelSnappingBias", "SetRotation",
    "SetLooping", "SetDuration", "SetFromAlpha", "SetToAlpha", "SetSmoothing", "SetOrder", "SetStartDelay",
    "Play", "Stop", "SetTextScale", "SetWordWrap", "SetNonSpaceWrap", "SetMaxLines", "SetSpacing",
    "SetPropagateMouseClicks", "SetPropagateMouseMotion", "RegisterForClicks", "SetHitRectInsets",
}) do
    if Region[name] == nil then Region[name] = Noop end
end

-- An AuraButton is sealed once initializeFrame returns: count every later write.
local Button = setmetatable({}, { __index = Region })
Button.__index = Button
for _, name in ipairs({
    "SetIcon", "ClearIcon", "SetDurationCooldown", "ClearDurationCooldown", "SetDurationBar", "ClearDurationBar",
    "SetDurationText", "ClearDurationText", "SetApplicationCount", "ClearApplicationCount", "AddDispelTypeTexture",
    "ClearDispelTypeTextures", "SetDispelTypeText", "ClearDispelTypeText", "SetCancelAuraButtons",
    "UpdateAuraDisplay", "AddPandemicRegion",
}) do Button[name] = Noop end
for _, name in ipairs({ "SetPoint", "ClearAllPoints", "SetAllPoints", "SetSize", "SetAlpha", "Show", "Hide",
    "SetFrameLevel", "SetFrameStrata", "SetMouseClickEnabled", "SetMouseMotionEnabled" }) do
    local base = Region[name]
    Button[name] = function(self, ...)
        if self._sealed == true then counts.sealedWrites = counts.sealedWrites + 1 end
        return base(self, ...)
    end
end

local Container = setmetatable({}, { __index = Region })
Container.__index = Container
local delayGroupInitialization = false
local function NewButton(container, options)
    local button = NewRegion("AuraButton", container, Button)
    counts.buttons = counts.buttons + 1
    if options and options.initializeFrame then options.initializeFrame(button) end
    button._sealed = true
    return button
end
function Container:SetUnit(unit) self._unit = unit end
function Container:GetUnit() return self._unit end
function Container:SetEnabled(enabled) self._enabled = enabled == true end
function Container:IsEnabled() return self._enabled == true end
function Container:AddAuraGroup(key, _, options)
    self._groupOptions = self._groupOptions or {}
    self._groupOptions[key] = options
    self._buttons = self._buttons or {}
    if delayGroupInitialization then return end
    for _ = 1, 10 do self._buttons[#self._buttons + 1] = NewButton(self, options) end
end
function Container:AddAuraSlot(_, _, options)
    self._buttons = self._buttons or {}
    local button = NewButton(self, options)
    self._buttons[#self._buttons + 1] = button
    return button
end
Container.AddItemEnchantment = Container.AddAuraSlot
for _, name in ipairs({
    "SetAuraGroupFilterString", "SetAuraGroupLayout", "SetAuraGroupMaxFrameCount", "SetAuraGroupCandidateFilters",
    "SetAuraGroupSortMethod", "SetAuraSlotFilterString", "SetAuraSlotCandidateFilters", "SetAuraSlotSortMethod",
    "SetFlowLayoutAnchorPoint", "SetFlowLayoutGrowthDirection", "SetFlowLayoutMaximumLineSize",
    "SetFlowLayoutPadding", "SetEditModePreviewEnabled", "SetItemEnchantmentLayout", "UpdateAllAuras",
}) do Container[name] = Noop end

_G.CreateFrame = function(kind, _, parent)
    if kind == "AuraContainer" then
        counts.containers = counts.containers + 1
        return NewRegion("AuraContainer", parent, Container)
    end
    return NewRegion(kind or "Frame", parent)
end
_G.issecretvalue = function() return false end
_G.InCombatLockdown = function() return false end
_G.GetTime = function() return 0 end
_G.UnitExists = function() return true end
_G.C_Timer = { After = Noop }

-- The real runtime -----------------------------------------------------------------------
local A3 = {}
local MSUF = { MSUF_Auras3 = A3, UF = {}, Auras3RuntimeFactories = {},
    ExportPublic = function(name, value) _G[name] = value end,
    MSUF_CreateCanonicalPlayerDefensiveAuraContainer = function() return { placed = {} } end,
}
_G.MSUF_NS, _G.MSUF = MSUF, MSUF
assert(loadfile(ADDON .. "Auras3/MSUF_Auras3_Core.lua"))("MidnightSimpleUnitFrames", MSUF)
assert(loadfile(ADDON .. "Libs/MSUFUnitFrames/MSUF_UF_Layers.lua"))("MidnightSimpleUnitFrames", MSUF)
assert(loadfile(ADDON .. "Auras3/MSUF_Auras3_SpellIndicators.lua"))("MidnightSimpleUnitFrames", MSUF)
local SpellIndicators = assert(A3.SpellIndicators, "Spell Indicator runtime did not load")
for _, name in ipairs({ "DurationText", "Signatures", "OwnerConfig", "NativeContract", "ButtonVisuals", "Containers", "NativeApply" }) do
    assert(loadfile(ADDON .. "Auras3/Runtime/MSUF_Auras3_Runtime_" .. name .. ".lua"))("MidnightSimpleUnitFrames", MSUF)
end
local Factories = MSUF.Auras3RuntimeFactories
dofile(root .. "/tools/tests/auras3_runtime_fixture.lua").Prepare(root, MSUF)

local function ClampNumber(value, fallback, minValue, maxValue)
    value = tonumber(value) or fallback
    if minValue and value < minValue then value = minValue end
    if maxValue and value > maxValue then value = maxValue end
    return value
end
local dependencies = {
    Platform = {
        AURA_CONTAINER_ADDON = "Blizzard_AuraContainer", ApplyAuraTooltipStyle = Noop, CreateFrame = _G.CreateFrame,
        EnsureBlizzardAuraContainerLoaded = function() return true end,
        ResolveFrameStrata = function(_, strata) return (strata and strata ~= "AUTO") and strata or "MEDIUM" end,
        SyncFrameStrata = function(frame, strata) if frame and strata then frame:SetFrameStrata(strata) end end,
        ReadParentFrameStrata = function() return "MEDIUM" end,
        Clamp01 = function(value, fallback) return ClampNumber(value, fallback or 1, 0, 1) end,
        ClampNumber = ClampNumber, FrameLayers = MSUF.UF.Layers,
    },
    Sort = { AuraSortEnums = function() return 0, 0 end, AuraSortSignature = function() return "DEFAULT" end },
    Schema = { DEFAULT_SHARED = { iconSize = 20, spacing = 2, cooldownDecimalSeconds = 0 },
        COLD_APPLY_REASONS = {}, IDENTITY_AURA_REFRESH_REASONS = {} },
    Appearance = { DS = {}, Shape = {} },
    DispelVisuals = {
        DispelSensorTarget = function(parentFrame) return parentFrame end,
        PrepareDispelSensorButton = function(button, sensor) button._bakedWith = sensor end,
    },
    ConfigValues = {
        EffectiveLaneFilters = function(lane) return lane.nativeFilter, lane.candidateFilters, lane.candidateFilterSignature end,
        ApplyAuraIconZoom = Noop, GetAuraBorderOptions = function() return nil end,
    },
    CustomConfig = {
        ManagedLaneFrameLevel = function(parentFrame) return (parentFrame and parentFrame:GetFrameLevel() or 0) + 11 end,
        ResolveLaneParentFrame = function(parentFrame) return parentFrame end,
    },
    Identity = { IsLiveGroupAuraFrame = function() return false end, SetAssistAlpha = Noop },
    GroupConfig = { FrameAuraConfig = function() return nil end },
    DurationText = setmetatable({}, { __index = function() return Noop end }),
}
local function Build(name)
    local exports = Factories[name]("MidnightSimpleUnitFrames", MSUF, A3, MSUF.UF, Noop, dependencies)
    dependencies[name] = exports
    return exports
end
local Signatures = Build("Signatures")
Build("DurationText")
Build("OwnerConfig")
local Contract = Build("NativeContract")
local Visuals = Build("ButtonVisuals")
-- Buttons record the lane they were styled for; geometry is the real cold path.
dependencies.ButtonVisuals = {
    PrepareAuraButton = function(button, lane)
        lane._msufA3NativeVisualInputs = lane._msufA3NativeVisualInputs or A3.GetNativeVisualInputs()
        button._bakedWith = lane
    end,
    SyncContainerGeometry = Visuals.SyncContainerGeometry,
}
local Containers = Build("Containers")
local NativeApply = Build("NativeApply")
Containers.Bind({ RegisterNativeContainer = NativeApply.RegisterNativeContainer })
Contract.Bind({ RefreshAppliedNativeRoot = NativeApply.RefreshAppliedNativeRoot })
NativeApply.Initialize()
for _, name in ipairs({
    "_RegisterDirectIdentityRefreshContainer", "_UnregisterDirectIdentityRefreshContainer", "_SeedUnitAuraIdentityOwner",
    "_SeedGroupAuraPresenceGate", "_SeedGroupAuraAssistGate", "_RecordNativeAuraRuntimeError",
    "_QueueDeferredAuraRuntime", "_HideDispelOverlayPreview",
}) do A3[name] = A3[name] or Noop end

-- Profile-shaped configs --------------------------------------------------------------------
local function Lane(o)
    local size = o.size or 20
    local lane = {
        enabled = o.enabled ~= false, kind = o.kind, rootKey = o.rootKey, unit = o.unit, max = o.max or 8,
        size = size, buttonWidth = size, buttonHeight = size, spacing = 2, step = size + 2, stepX = size + 2,
        stepY = size + 2, perRow = 8, cols = 8, rows = 1, width = 8 * size + 14, height = size, padding = 0,
        anchor = o.anchor or "BOTTOMLEFT", x = o.x or 0, y = o.y or 0, alpha = o.alpha or 1,
        initialAnchor = "BOTTOMLEFT", xSign = 1, ySign = 1, layer = 1, strata = "AUTO", iconShape = "SQUARE",
        nativeFilter = o.filter or "HELPFUL", candidateFilterSignature = "none", showCooldownSwipe = true, iconStyle = o.iconStyle,
    }
    lane._msufA3TrackingSignature = Signatures.LaneTrackingSignature(lane)
    lane._msufA3StructuralSignature = Signatures.LaneStructuralSignature(lane)
    lane._msufA3LayoutSignature = Signatures.LaneLayoutSignature(lane)
    return lane
end
local function Sensor(unit, size)
    local sensor = {
        sensor = true, enabled = true, kind = "dispelBorder", unit = unit, max = 1, visual = "border",
        target = "frame", style = "solid", alpha = 1, thickness = 2, layer = 3, strata = "AUTO",
        nativeFilter = "HARMFUL|RAID", candidateFilterSignature = "none", size = size or 2,
        r = 1, g = 0, b = 0, mode = "border",
    }
    sensor._msufA3StructuralSignature = Signatures.SensorStructuralSignature(sensor)
    sensor._msufA3LayoutSignature = Signatures.SensorLayoutSignature(sensor)
    return sensor
end
local function SpellRoot(unit, x, effect)
    return SpellIndicators.CompileSlots(unit, {
        enabled = true, layer = 9, strata = "AUTO", iconZoom = 100,
        items = { {
            enabled = true, key = "renew", display = "Renew", includeSpellIDs = { [139] = true },
            placed = { type = "icon", size = 14, anchor = "TOPRIGHT", x = x or 0, y = 0 },
            frame = effect and { type = "border", color = { 1, 0, 0, 1 }, thickness = 2 } or nil,
        } },
    })
end

local targetFrame = NewRegion("Button", nil)
targetFrame.MSUFUnitKey, targetFrame.MSUFSpec = "target", {}
-- A health bar gives Spell Indicator frame effects their surface.
targetFrame.hpBar = NewRegion("StatusBar", targetFrame)
local healthFill = NewRegion("Texture", targetFrame.hpBar)
function targetFrame.hpBar.GetStatusBarTexture() return healthFill end
local partyFrame = NewRegion("Button", nil)
partyFrame.MSUFUnitKey, partyFrame.MSUFSpec = "party1", { scope = "group" }

local function ApplyTarget(o, debuff)
    local cfg = { enabled = true, unit = "target", group = false, lanes = {
        buff = Lane({ kind = "buff", rootKey = "Buffs", unit = "target", size = o.size, x = o.x, alpha = o.alpha }),
    } }
    if debuff ~= false then
        cfg.lanes.debuff = Lane({ kind = "debuff", rootKey = "Debuffs", unit = "target", filter = "HARMFUL" })
    end
    cfg.spellIndicators = o.spell and SpellRoot("target", o.spell, true) or nil
    assert(NativeApply.ApplyConfig(targetFrame, cfg, "AURAS3_GROWTH_SMOKE"), "target aura config did not apply")
    return targetFrame.Auras
end
local function ApplyParty(o)
    local unit = o.unit or "party1"
    local cfg = { enabled = true, unit = unit, group = true, lanes = {
        buff = Lane({ kind = "buff", rootKey = "Buffs", unit = unit, max = 1, x = o.slotX }),
        debuff = Lane({ kind = "debuff", rootKey = "Debuffs", unit = unit, max = 3, filter = "HARMFUL",
            x = o.flowX, size = o.flowSize, alpha = o.flowAlpha, enabled = o.flow ~= false }),
    }, sensors = o.sensor ~= false and { dispelBorder = Sensor(unit, o.sensorSize) } or nil,
        spellIndicators = SpellRoot(unit, o.spell) }
    assert(NativeApply.ApplyConfig(partyFrame, cfg, "AURAS3_GROWTH_SMOKE"), "party aura config did not apply")
    return partyFrame.Auras
end
local function Built(before, label, expected)
    local built = counts.containers - before
    assert(built == expected, label .. ": built " .. built .. " native containers, expected " .. expected)
end

-- 1. A flowing lane moves and fades without a new container or a touched button.
local targetRoot = ApplyTarget({ x = 0 })
local buffs = assert(targetRoot.Buffs, "precondition: the target Buffs lane has no container")
local start, writes = counts.containers, counts.sealedWrites
for step = 1, 50 do ApplyTarget({ x = step * 2 }) end
Built(start, "50 position steps of a flowing lane", 0)
assert(targetRoot.Buffs == buffs and buffs._msufA3LayoutHost._point[4] == 100,
    "the reused lane's host did not move to the last offset")
for step = 1, 50 do ApplyTarget({ x = 100, alpha = 1 - step / 100 }) end
Built(start, "50 opacity steps of a flowing lane", 0)
assert(targetRoot.Buffs == buffs and buffs:GetAlpha() == 0.5, "the reused lane's container did not take the last alpha")
assert(counts.sealedWrites == writes,
    "moving or fading a lane wrote " .. (counts.sealedWrites - writes) .. " times to sealed AuraButtons")

-- 2. A structural slider dragged back and forth over 12 values builds 12.
start = counts.containers
local sizes = {}
for step = 0, 49 do
    local phase = step % 22
    sizes[#sizes + 1] = 20 + (phase <= 11 and phase or 22 - phase)
end
local distinct = {}
for i = 1, #sizes do distinct[sizes[i]] = true end
local distinctCount = 0
for _ in pairs(distinct) do distinctCount = distinctCount + 1 end
assert(distinctCount == 12, "precondition: the size drag visits " .. distinctCount .. " values")
for i = 1, #sizes do ApplyTarget({ x = 100, size = sizes[i] }) end
Built(start, "50 steps of a structural slider over 12 values", 11)
for i = 1, #sizes do ApplyTarget({ x = 100, size = sizes[i] }) end
Built(start, "a second drag over the same 12 values", 11)
for i = 1, #(targetRoot.Buffs._buttons or {}) do
    local baked = targetRoot.Buffs._buttons[i]._bakedWith
    assert(baked and baked.size == sizes[#sizes], "a revived lane's buttons were styled for another size")
end

-- 3. A lane toggled off and on takes its own container back.
local debuffs = assert(targetRoot.Debuffs, "precondition: the target Debuffs lane has no container")
start = counts.containers
ApplyTarget({ x = 100, size = sizes[#sizes] }, false)
assert(targetRoot.Debuffs == nil and not debuffs:IsShown(), "a disabled lane kept its container live")
ApplyTarget({ x = 100, size = sizes[#sizes] })
Built(start, "a lane toggled off and on", 0)
assert(targetRoot.Debuffs == debuffs and debuffs:IsShown() and debuffs:IsEnabled(),
    "a re-enabled lane did not take its own container back")

-- 4. A unit Spell Indicator moved and moved back revives its root.
ApplyTarget({ x = 100, size = sizes[#sizes], spell = 1 })
local spellRoot = assert(targetRoot.SpellIndicators, "precondition: the target Spell Indicator has no container")
start = counts.containers
ApplyTarget({ x = 100, size = sizes[#sizes], spell = 2 })
ApplyTarget({ x = 100, size = sizes[#sizes], spell = 1 })
Built(start, "a Spell Indicator moved and moved back", 1)
assert(targetRoot.SpellIndicators == spellRoot, "the Spell Indicator root was not revived")
-- Its frame effect is listed again, as a fresh root's initializeFrame lists it.
local effectButton = assert(spellRoot[1], "precondition: the Spell Indicator root has no AuraButton")
assert(effectButton._msufA3FrameEffectApplied
    and (targetFrame._msufA3SpellIndicatorEffectButtons or {})[effectButton] == true,
    "the revived Spell Indicator's frame effect is missing from the frame's effect list")

-- 5. A group owner: 12 distinct layouts applied twice build 12.
local partyRoot = ApplyParty({ slotX = 0 })
assert(partyRoot.GroupSlots, "precondition: the party frame has no group owner")
start = counts.containers
for pass = 1, 2 do
    for slotX = 1, 12 do ApplyParty({ slotX = slotX * 3 }) end
    Built(start, "pass " .. pass .. " over 12 group layouts", 12)
end

-- 6. The group's flowing lane moves without a new owner or a touched button.
local owner = partyRoot.GroupSlots
start, writes = counts.containers, counts.sealedWrites
for step = 1, 50 do ApplyParty({ slotX = 36, flowX = step }) end
Built(start, "50 position steps of a group's flowing lane", 0)
assert(partyRoot.GroupSlots == owner and owner._msufA3LayoutHost._point[4] == 50,
    "the group owner's flowing host did not move to the last offset")
assert(counts.sealedWrites == writes,
    "moving a group's flowing lane wrote " .. (counts.sealedWrites - writes) .. " times to sealed AuraButtons")
-- A group owner sets each flowing button's alpha in initializeFrame, so the
-- lane's opacity still needs an owner of its own there.
ApplyParty({ slotX = 36, flowX = 50, flowAlpha = 0.5 })
Built(start, "a group's flowing lane faded", 1)
local faded = partyRoot.GroupSlots
assert(faded ~= owner and faded._buttons[#faded._buttons]._alpha == 0.5,
    "a group owner's flowing buttons did not take the lane's new alpha")
ApplyParty({ slotX = 36, flowX = 50 })
Built(start, "a group's flowing lane faded back", 1)
assert(partyRoot.GroupSlots == owner, "the group owner was not revived after the fade was undone")

-- 7. Group lanes, the dispel sensor and the Spell Indicator toggled or moved and back.
start = counts.containers
ApplyParty({ slotX = 36, flowX = 50, flow = false })
ApplyParty({ slotX = 36, flowX = 50 })
ApplyParty({ slotX = 36, flowX = 50, sensor = false })
ApplyParty({ slotX = 36, flowX = 50 })
ApplyParty({ slotX = 36, flowX = 50, spell = 4 })
ApplyParty({ slotX = 36, flowX = 50 })
Built(start, "group lane, sensor and Spell Indicator edits undone", 3)
assert(partyRoot.GroupSlots == owner, "the group owner was not revived after the edits were undone")

-- 8. Switching a frame's auras off and on (HideState) takes every container back.
start = counts.containers
NativeApply.HideState(partyFrame)
NativeApply.HideState(targetFrame)
assert(partyRoot.GroupSlots == nil and not owner:IsShown() and not owner:IsEnabled(),
    "HideState left a group owner live")
ApplyParty({ slotX = 36, flowX = 50 })
ApplyTarget({ x = 100, size = sizes[#sizes], spell = 1 })
Built(start, "auras switched off and on", 0)
assert(partyRoot.GroupSlots == owner and targetRoot.Buffs and targetRoot.SpellIndicators == spellRoot,
    "auras switched back on did not take their containers back")

-- 9. A forced recreate builds fresh AuraButtons: it never revives a parked
-- container, and none parked for its key from before it comes back.
start = counts.containers
local before = targetRoot.Buffs
local fresh = NativeApply.ApplyLane(targetRoot, Lane({ kind = "buff", rootKey = "Buffs", unit = "target",
    size = sizes[#sizes], x = 100 }), targetFrame, true)
Built(start, "a forced recreate", 1)
assert(fresh and fresh ~= before and targetRoot.Buffs == fresh, "a forced recreate reused a container")
assert(sizes[#sizes] ~= 24, "precondition: size 24 is not the current size")
ApplyTarget({ x = 100, size = 24 })
Built(start, "a size parked before a forced recreate", 2)
ApplyTarget({ x = 100, size = sizes[#sizes] })
Built(start, "the forced recreate's own size again", 2)
assert(targetRoot.Buffs == fresh, "the forced recreate's fresh container was not parked for its size")

-- Priority groups retain their per-spell contract when filters or max change.
do
    local function Priority(maximum, filter)
        local lane=Lane({kind="buff",rootKey="Priority",unit="target",max=maximum,filter=filter})
        lane.customPriority=true;lane.customPrioritySpellIDs={101,102,103}
        lane._msufA3StructuralSignature=Signatures.LaneStructuralSignature(lane)
        return lane
    end
    local first=NativeApply.ApplyLane(targetRoot,Priority(2,"HELPFUL"),targetFrame)
    assert(first and #first._msufA3PriorityGroupKeys==2)
    local writes=0
    first.SetAuraGroupFilterString=function(_,_,filter) assert(filter=="HELPFUL|PLAYER");writes=writes+1 end
    local changed=NativeApply.ApplyLane(targetRoot,Priority(2,"HELPFUL|PLAYER"),targetFrame)
    assert(changed==first and writes==2,"priority filter change did not update both existing groups")
    NativeApply.ApplyLane(targetRoot,Priority(2,"HELPFUL|PLAYER"),targetFrame)
    assert(writes==2,"unchanged priority filter repeated native writes")
    local grown=NativeApply.ApplyLane(targetRoot,Priority(3,"HELPFUL|PLAYER"),targetFrame)
    assert(grown~=first and #grown._msufA3PriorityGroupKeys==3,"priority max change kept stale group count")
end

-- Leaving an owned reminder never hides another UI's reused shared tooltip.
do
    local slotRoot=SpellIndicators.CompileSlots("target",{enabled=true,items={{enabled=true,key="click",includeSpellIDs={[139]=true},
        showWhenMissing=true,castSpellID=139,castUnit="target",placed={type="icon",size=14}}}})
    SpellIndicators.SyncReminderCastButtons(targetFrame,slotRoot)
    local store=targetFrame._msufA3ReminderCastButtons
    local button=store and select(2,next(store))
    assert(button and button:GetScript("OnLeave"),"reminder cast button not created")
    local owner,hides=nil,0
    _G.GameTooltip={IsOwned=function(_,candidate) return owner==candidate end,Hide=function() hides=hides+1 end}
    button:GetScript("OnLeave")(button);assert(hides==0,"reminder hid another owner's tooltip")
    owner=button;button:GetScript("OnLeave")(button);assert(hides==1,"reminder did not hide its own tooltip")
end


-- Global visuals are addressed by content. Exercise the complete Core queue
-- and Facade factories, never source slices or simulated generation bumps.
do
    local combat=false
    dependencies.Platform.InCombat=function()return combat end
    dependencies.Platform.AuraRuntimeCombatBlocked=function()return combat end
    dependencies.Platform.Round=function(n)return math.floor(n+0.5)end
    dependencies.IdentityTopology={DrainDirectIdentityEventTopologyBatch=Noop}
    dependencies.UnitConfig={InvalidateUnitRuntimeConfig=function(unit)return unit end}
    MSUF.UF.RegisterElement=Noop
    for _,name in ipairs({"DurationText","Facade"})do
        assert(loadfile(ADDON.."Auras3/Runtime/MSUF_Auras3_Runtime_"..name..".lua"))("MSUF",MSUF)
        Build(name)
    end
    local path,red,flags,shadow="FontA",1,"OUTLINE",true
    _G.MSUF_GetGlobalFontSettings=function()return path,flags,red,1,1,14,shadow end
    local function ApplyOwners()
        ApplyTarget({size=20,spell=1})
        ApplyParty({flowSize=20,spell=1})
    end
    A3._runtimeFrames={target=targetFrame}
    A3.RenderFrame=function(frame)assert(frame==targetFrame);ApplyOwners();return true end
    A3._NotifyAuraColdpathPreview=Noop
    A3.RefreshEditPreview=nil
    A3._RequestUnitNow=ApplyOwners
    A3._BeginDirectIdentityEventTopologyBatch=Noop
    A3._EndDirectIdentityEventTopologyBatch=Noop
    A3._EnsureDeferredAuraRuntimeDriver=function()return nil end
    local timers={}
    dependencies.Platform.C_Timer={After=function(_,callback)timers[#timers+1]=callback end}
    -- Facade captured C_Timer at construction; rebuild against the timer model.
    Build("Facade")
    A3._RequestUnitNow=ApplyOwners
    A3.RenderFrame=function(frame)assert(frame==targetFrame);ApplyOwners();return true end
    A3._NotifyAuraColdpathPreview=Noop
    local function Flush()
        while #timers>0 do local callback=table.remove(timers,1);callback() end
    end
    _G.MSUF_DB={general={}}
    MSUF.Require=function()return Noop end
    MSUF.Util={InCombat=function()return combat end}
    _G.C_Timer=dependencies.Platform.C_Timer
    _G.MSUF_ApplyRoundedUnitframes=function()A3.RefreshRoundedDispelOverlayMasks()end
    assert(loadfile(ADDON.."Runtime/MSUF_Colors.lua"))("MSUF",MSUF)
    local function Push()MSUF._colorsAPI.PushVisualUpdates();Flush()end
    A3.ApplyFontsFromGlobal();local fontA=targetFrame.Auras.Buffs
    Flush()
    local noops,buttons=counts.containers,counts.buttons
    for _=1,20 do Push() end
    print(string.format("20 no-op colour pushes: +%d containers / +%d AuraButtons",
        counts.containers-noops,counts.buttons-buttons))
    Built(noops,"20 no-op colour pushes",0)
    assert(counts.buttons==buttons,"no-op colour pushes built AuraButtons")
    path="FontB";A3.ApplyFontsFromGlobal();local fontB=targetFrame.Auras.Buffs
    assert(fontA~=fontB,"different resolved fonts reused immutable buttons")
    local warm=counts.containers
    for step=1,20 do
        path=step%2==1 and "FontA" or "FontB"
        A3.ApplyFontsFromGlobal()
        assert(targetFrame.Auras.Buffs==(path=="FontA" and fontA or fontB),"font A/B/A did not revive matching native lane")
    end
    Built(warm,"font A/B/A repeated after warmup",0)
    red=0.2;A3.ApplyFontsFromGlobal();assert(counts.containers>warm,"font color change reused stale native buttons")
    red=1;A3.ApplyFontsFromGlobal();assert(targetFrame.Auras.Buffs==fontB,"font color restore did not revive previous style")
    combat=true;path="FontA";A3.ApplyFontsFromGlobal();path="FontB";A3.ApplyFontsFromGlobal()
    local before=counts.containers;combat=false;A3._FlushDeferredAuraRuntime()
    Built(before,"coalesced combat font changes ending on current style",0)
    Flush()
    path="FontA";A3.ApplyFontsFromGlobal();Flush()
    assert(targetFrame.Auras.Buffs==fontA,"font restore lost its content address")

    local function Owners()
        return {targetFrame.Auras.Buffs,targetFrame.Auras.Debuffs,partyFrame.Auras.GroupSlots,targetFrame.Auras.SpellIndicators}
    end
    local function SameOwners(expected,label)
        local actual=Owners()
        for i=1,#expected do assert(actual[i]==expected[i],label..": owner "..i.." was not revived") end
    end
    local function RoundTrip(label,write)
        Push();local original=Owners();local token=A3.GetNativeVisualSignature()
        local before=counts.containers
        write(true);A3.RequestScope("shared");Flush()
        local changed=Owners()
        assert(A3.GetNativeVisualSignature()~=token,label..": baked input missing from token")
        Built(before,label.." A to B",4)
        write(false);Push();SameOwners(original,label.." B to A")
        for _=1,3 do
            write(true);Push();SameOwners(changed,label.." warm B")
            write(false);Push();SameOwners(original,label.." warm A")
        end
        Built(before,label.." repeated A/B/A",4)
    end
    local general=_G.MSUF_DB.general
    RoundTrip("font flags",function(on)flags=on and "THICKOUTLINE" or "OUTLINE"end)
    RoundTrip("font shadow",function(on)shadow=not on end)
    RoundTrip("font key",function(on)general.fontKey=on and "OtherFont" or nil end)
    RoundTrip("locale",function(on)MSUF.LOCALE=on and "deDE" or nil end)
    for _,key in ipairs({"aurasCooldownTextUseBuckets","aurasCooldownTextUrgentSeconds",
        "aurasCooldownTextWarningSeconds","aurasCooldownTextSafeSeconds"}) do
        RoundTrip(key,function(on)general[key]=on and 2 or nil end)
    end
    for _,key in ipairs({"aurasCooldownTextSafeColor","aurasCooldownTextWarningColor","aurasCooldownTextUrgentColor"}) do
        RoundTrip(key,function(on)general[key]=on and {0.2,0.4,0.6} or nil end)
    end
    local barRed=1
    A3.GetDurationBarColor=function()return barRed,1,1 end
    RoundTrip("duration bar",function(on)barRed=on and 0.3 or 1 end)
    for _,kind in ipairs({"Magic","Curse","Disease","Poison","Bleed"}) do
        RoundTrip("dispel "..kind,function(on)general.dispelTypeColorOverrides=on and {[kind]={0.1,0.2,0.3}} or nil end)
    end
    assert(loadfile(ADDON.."UnitFrames/Effects/MSUF_UF_RoundedSurface.lua"))("MSUF",MSUF)
    local kit=MSUF.RoundedSurfaceKit
    assert(kit.DispelVisualSignature()=="-","inactive rounded signature is not '-'")
    _G.MSUF_DB.bars={roundedCornerStrength=1}
    Push();local inactive=Owners();local inactiveBefore=counts.containers
    _G.MSUF_DB.bars.roundedCornerStrength=5;Push()
    Built(inactiveBefore,"inactive rounded strength change",0);SameOwners(inactive,"inactive rounded")
    RoundTrip("rounded active",function(on)_G.MSUF_DB.bars.roundedFramesEnabled=on end)
    _G.MSUF_DB.bars.roundedFramesEnabled=true;Push()
    RoundTrip("rounded strength",function(on)_G.MSUF_DB.bars.roundedCornerStrength=on and 1 or 5 end)
    _G.MSUF_DB.bars.roundedFramesEnabled=false;_G.MSUF_DB.target={frameBarShape="SLANTED"};Push()
    RoundTrip("slanted cut",function(on)_G.MSUF_DB.target.slantedBarDirection=on and "LEFT_UP" or nil end)
    _G.MSUF_DB.target=nil;Push()

    -- Distinct content, rather than input revisions, bounds parking.
    local distinctBefore=counts.containers
    for pass=1,2 do
        for i=1,12 do general.aurasCooldownTextSafeSeconds=60+i;Push() end
        if pass==1 then Built(distinctBefore,"12 distinct global visuals",48)
        else Built(distinctBefore,"same 12 global visuals revisited",48) end
    end
    general.aurasCooldownTextSafeSeconds=nil;Push()
    local committed=Owners();local dragBefore,dragButtons=counts.containers,counts.buttons
    local ticket=A3.BeginNativeColorInteraction()
    for i=1,20 do
        general.aurasCooldownTextSafeColor={i/100,0.4,0.6}
        Push();A3.RequestScope("shared");ApplyOwners()
    end
    Built(dragBefore,"20 live colour samples",0)
    assert(counts.buttons==dragButtons,"live drag built AuraButtons")
    SameOwners(committed,"live drag")
    A3.EndNativeColorInteraction(ticket);Flush()
    Built(dragBefore,"one colour commit",4)
    assert(counts.buttons-dragButtons==34,"colour commit built an unexpected button set")
    print("20 live colour samples: +0 containers / +0 AuraButtons; commit: +4 / +34")
    general.aurasCooldownTextSafeColor=nil;Push();SameOwners(committed,"colour restore")
    dragBefore=counts.containers;ticket=A3.BeginNativeColorInteraction()
    general.aurasCooldownTextSafeColor={0.7,0.8,0.9};Push()
    general.aurasCooldownTextSafeColor=nil;Push()
    A3.EndNativeColorInteraction(ticket);Flush()
    Built(dragBefore,"cancelled colour drag",0);SameOwners(committed,"cancel")
    ticket=A3.BeginNativeColorInteraction();combat=true
    general.aurasCooldownTextWarningColor={0.7,0.8,0.9}
    A3.EndNativeColorInteraction(ticket)
    Built(dragBefore,"combat colour commit remains deferred",0)
    combat=false;A3._FlushDeferredAuraRuntime();Flush()
    Built(dragBefore,"deferred colour commit",4)

    -- Content memos survive input-revision changes and table replacement.
    A3.IconShape={ApplyIconShape=Noop}
    assert(loadfile(ADDON.."Auras3/Runtime/MSUF_Auras3_Runtime_Appearance.lua"))("MSUF",MSUF)
    Build("Appearance")
    local colors=0
    _G.CreateColor=function(r,g,b,a)colors=colors+1;return {r,g,b,a}end
    general.dispelTypeColorOverrides={Magic={0.1,0.2,0.3}}
    A3.InvalidateNativeVisualInputs();local colorMap=A3.GetCustomDispelColorMap()
    assert(colorMap and colorMap.Magic[1]==0.1,"dispel colour memo did not bake its input")
    general.dispelTypeColorOverrides={Magic={r=0.1,g=0.2,b=0.3}}
    A3.InvalidateNativeVisualInputs()
    assert(A3.GetCustomDispelColorMap()==colorMap and colors==1,"identical dispel RGB rebuilt the colour memo")
    general.dispelTypeColorOverrides.Magic.r=0.4;A3.RequestScope("shared");Flush()
    assert(A3.GetCustomDispelColorMap().Magic[1]==0.4,"in-place dispel RGB edit kept stale colours")
    local formatters=0
    _G.C_StringUtil={CreateNumericRuleFormatter=function()
        formatters=formatters+1
        return {AddBreakpoint=Noop}
    end}
    local lane={cooldownDecimalSeconds=3}
    local duration=dependencies.DurationText
    local style=duration.BuildAuraDurationStyle(lane)
    for _=1,20 do
        A3.InvalidateNativeVisualInputs()
        assert(duration.BuildAuraDurationStyle(lane)==style,"no-op revision rebuilt the duration formatter")
    end
    assert(formatters==1,"duration memo created duplicate formatters")
    general.aurasCooldownTextWarningSeconds=12;A3.InvalidateNativeVisualInputs()
    assert(duration.BuildAuraDurationStyle(lane)~=style and formatters==2,"timer input retained stale lane style")

    -- Blizzard may grow a live AuraGroup without going through ApplyConfig.
    -- Its captured native lane must retain A while addon-owned previews show B.
    general.aurasCooldownTextUseBuckets=true
    general.aurasCooldownTextSafeColor={1,1,1};Push()
    local committedLane=targetFrame.Auras.Buffs._buttons[1]._bakedWith
    local committedStyle=duration.BuildAuraDurationStyle(committedLane)
    local committedInputs=committedLane._msufA3NativeVisualInputs
    ticket=A3.BeginNativeColorInteraction()
    general.aurasCooldownTextSafeColor={0.2,0.4,0.6};path="FontPreview";Push()
    local options=select(2,next(targetFrame.Auras.Buffs._groupOptions))
    local late=NewButton(targetFrame.Auras.Buffs,options)
    assert(late._bakedWith._msufA3NativeVisualInputs==committedInputs,"native pool growth changed its committed inputs")
    assert(duration.BuildAuraDurationStyle(late._bakedWith)==committedStyle,"late initializer baked preview timer colours")
    assert(duration.BuildAuraDurationStyle({cooldownDecimalSeconds=3})~=committedStyle,"preview timer colours did not update live")
    local appliedPath
    _G.MSUF_ApplyResolvedFont=function(_,fontPath)appliedPath=fontPath end
    duration.ApplyFont(NewRegion("FontString"),14,late._bakedWith)
    assert(appliedPath=="FontA","late initializer baked the preview font")
    general.aurasCooldownTextSafeColor={1,1,1};path="FontA";Push()
    A3.EndNativeColorInteraction(ticket);Flush()
    assert(duration.BuildAuraDurationStyle(late._bakedWith)==committedStyle,"cancel poisoned the committed native lane")

    -- Empty native groups must capture A at birth, before their first button.
    delayGroupInitialization=true
    local emptyLane=Lane({kind="buff",rootKey="LateInput",unit="target"})
    local empty=NativeApply.ApplyLane(targetRoot,emptyLane,targetFrame)
    delayGroupInitialization=false
    local birthInputs=empty._msufA3NativeButtonConfigs[1]._msufA3NativeVisualInputs
    assert(birthInputs and birthInputs.general.aurasCooldownTextSafeColor[1]==1,"empty group missed its birth inputs")
    general.aurasCooldownTextSafeColor={0.3,0.4,0.5}
    MSUF._colorsAPI.PushVisualUpdates() -- Native refresh still waits for its 40 ms flush.
    local first=NewButton(empty,select(2,next(empty._groupOptions)))
    assert(first._bakedWith._msufA3NativeVisualInputs==birthInputs,"first initializer captured an uncommitted colour push")
    assert(first._bakedWith._msufA3NativeVisualInputs.general.aurasCooldownTextSafeColor[1]==1,"first initializer baked B under A")
    general.aurasCooldownTextSafeColor={1,1,1};Flush()

    -- Per-lane colour edits enter through RefreshUnit even while global refresh
    -- is held. Only ApplyConfig can keep the native lane on its committed style.
    local laneRed=1
    local function ApplyLaneColour()
        local lane=Lane({kind="buff",rootKey="Buffs",unit="target",iconStyle={signature=tostring(laneRed)}})
        assert(NativeApply.ApplyConfig(targetFrame,{enabled=true,unit="target",lanes={buff=lane}},"AURAS3_GROWTH_SMOKE"))
        return true
    end
    local render,request=A3.RenderFrame,A3._RequestUnitNow
    A3._RequestUnitNow=ApplyLaneColour
    A3.RenderFrame=ApplyLaneColour
    ApplyLaneColour();Flush()
    local laneOwner=targetFrame.Auras.Buffs
    local laneBefore=counts.containers
    ticket=A3.BeginNativeColorInteraction()
    for i=1,20 do laneRed=i/100;assert(A3.RefreshUnit("target")) end
    Built(laneBefore,"20 per-lane iconStyle colour samples via RefreshUnit",0)
    assert(targetFrame.Auras.Buffs==laneOwner,"per-lane drag replaced its native owner")
    A3.EndNativeColorInteraction(ticket);Flush()
    Built(laneBefore,"one per-lane iconStyle colour commit",1)
    assert(targetFrame.Auras.Buffs~=laneOwner,"per-lane commit kept the old baked style")
    print("20 per-lane colour samples via RefreshUnit: +0 containers; commit: +1")
    A3.RenderFrame,A3._RequestUnitNow=render,request
    ApplyOwners();Flush()

    -- Roster churn still rebinds native owners and their captured descriptors.
    local reboundOwner=partyFrame.Auras.GroupSlots
    local playerOwner=NativeApply.ApplyLane(partyRoot,Lane({kind="custom1",rootKey="CustomAuras1",unit="player"}),partyFrame)
    local rebindBefore=counts.containers
    ticket=A3.BeginNativeColorInteraction()
    partyFrame.MSUFUnitKey="party2";ApplyParty({unit="party2",flowSize=20,spell=1})
    assert(reboundOwner:GetUnit()=="party2","colour drag suppressed native unit rebinding")
    assert(playerOwner:GetUnit()=="player","roster rebind changed an explicit source unit")
    assert(reboundOwner._msufA3NativeButtonConfigs[1].unit=="party2","private native config kept its previous unit")
    assert(partyFrame.Auras._msufA3Config.unit=="party1","unit rebinding mutated a shared compiled config")
    assert(reboundOwner._buttons[1]._bakedWith.unit=="party2","captured native lane kept its previous unit")
    partyFrame.MSUFUnitKey="party1";ApplyParty({flowSize=20,spell=1})
    A3.EndNativeColorInteraction(ticket);Flush()
    Built(rebindBefore,"unit churn during a colour interaction",0)
    -- Profile switches, resets and same-table imports invalidate configuration
    -- independently of identical immutable visuals; owners still reuse content.
    local Slice=assert(loadfile(".github/scripts/msuf_source_slice.lua"))()
    local profilePath=ADDON.."State/MSUF_ProfileRuntime.lua"
    local beforeMutation=assert(loadstring("local MSUF=...\nlocal profileGeneration=0\n"
        ..Slice.Function(Slice.Read(profilePath),"local function MSUF_ProfileIO_BeforeActiveProfileMutation",profilePath)
        .."\nreturn MSUF_ProfileIO_BeforeActiveProfileMutation"))(MSUF)
    local profileGen,visualToken=A3._runtimeConfigGen,A3.GetNativeVisualSignature()
    MSUF.MSUF_Auras3=A3
    beforeMutation()
    assert(A3._runtimeConfigGen==profileGen+1,"profile mutation kept stale aura config caches")
    assert(A3.GetNativeVisualSignature()==visualToken,"profile mutation changed immutable visual content")
    ApplyOwners()
    Built(rebindBefore,"same-content profile mutation",0)
    local savedThreshold=_G.MSUF_DB.general.aurasCooldownTextSafeSeconds
    beforeMutation()
    _G.MSUF_DB.general.aurasCooldownTextSafeSeconds=987
    assert(A3.GetNativeVisualSignature()~=visualToken,"profile mutation kept the preceding visual memo")
    beforeMutation()
    _G.MSUF_DB.general.aurasCooldownTextSafeSeconds=savedThreshold
    assert(A3.GetNativeVisualSignature()==visualToken,"profile restore lost identical visual content")
    local cfg=partyRoot._msufA3Config
    local savedUnit=cfg.unit
    cfg.unit=nil
    ticket=A3.BeginNativeColorInteraction()
    assert(NativeApply.ApplyConfig(partyFrame,cfg,"AURAS3_GROWTH_SMOKE"))
    assert(partyRoot.unit=="party1" and reboundOwner:GetUnit()=="party1","drag lost the frame unit fallback")
    cfg.unit=savedUnit
    A3.EndNativeColorInteraction(ticket);Flush()

    assert(counts.sealedWrites==0,"font edit wrote a sealed native child")
end

-- Roster size never enters global visual content. Each frozen mask follows
-- only its own frame's embedded power and forced style, even with cached cfgs.
do
    local Slice = assert(loadfile(".github/scripts/msuf_source_slice.lua"))()
    local roundedPath = ADDON .. "UnitFrames/Effects/MSUF_UF_RoundedFrames.lua"
    local prepareSource = Slice.Function(Slice.Read(roundedPath), "local function PrepareFrozenDispelOverlayMask", roundedPath)
    local kit = assert(MSUF.RoundedSurfaceKit)
    local prepare = assert(loadstring([[
        local kit = ...
        local FrameIsGroup, RoundedFrameEnabled = kit.FrameIsGroup, kit.RoundedFrameEnabled
        local RoundedPowerBarsEnabled, PowerIsEmbedded = kit.RoundedPowerBarsEnabled, kit.PowerIsEmbedded
        local SurfaceMaskPath, IsCombatLocked, DeferApply = kit.SurfaceMaskPath, kit.IsCombatLocked, kit.DeferApply
        local CanCreateRoundedRegion, UpdateRoundedMediaState = kit.CanCreateRoundedRegion, kit.UpdateRoundedMediaState
        local SE_SnapOff, ApplyRoundedMediaSlice = function() end, function() end
    ]] .. prepareSource .. "\nreturn PrepareFrozenDispelOverlayMask"))(kit)
    dependencies.DispelVisuals.PrepareDispelSensorButton = function(button, sensor, frame)
        button._bakedWith = sensor
        local region = { AddMaskTexture = function(_, mask) button._roundedMask = mask end }
        prepare(frame, region, button)
    end
    Containers = Build("Containers")
    NativeApply = Build("NativeApply")
    Containers.Bind({ RegisterNativeContainer = NativeApply.RegisterNativeContainer })
    Contract.Bind({ RefreshAppliedNativeRoot = NativeApply.RefreshAppliedNativeRoot })
    NativeApply.Initialize()
    _G.MSUF_DB = { general = {}, bars = { roundedFramesEnabled = true, roundedPowerBars = true } }
    local raid, liveCount, units = {}, 5, {}
    local configs = {}
    local function MakeFrame(unit, group)
        local frame = NewRegion("Button", nil)
        frame.MSUFUnitKey = unit
        frame.MSUFSpec = { scope = group and "group" or "unit", power = { enabled = true, embed = true } }
        if group then
            frame._msufIsGroupFrame, frame._msufGFKind = true, "raid"
            frame.health, frame.barGroup = NewRegion("StatusBar", frame), NewRegion("Frame", frame)
        else
            frame.hpBar = NewRegion("StatusBar", frame)
        end
        local sensor = Sensor(unit)
        sensor.kind, sensor.visual, sensor.mode = "dispelOverlay", "overlay", "overlay"
        sensor._msufA3StructuralSignature = Signatures.SensorStructuralSignature(sensor)
        sensor._msufA3LayoutSignature = Signatures.SensorLayoutSignature(sensor)
        local lane = Lane({ kind = "buff", rootKey = "Buffs", unit = unit })
        lane.identityCandidateMode = "assist"
        lane._msufA3StructuralSignature = Signatures.LaneStructuralSignature(lane)
        configs[frame] = { enabled = true, unit = unit, group = group,
            lanes = { buff = lane }, sensors = { dispelOverlay = sensor } }
        return frame
    end
    units[1], units[2] = MakeFrame("target", false), MakeFrame("focus", false)
    for i = 1, 5 do raid[i] = MakeFrame("raid" .. i, true) end
    MSUF.UF.ForEachFrame = function(fn) for i = 1, #units do fn(units[i]) end end
    MSUF.GF = { ForEachFrame = function(fn) for i = 1, liveCount do fn(raid[i]) end end }
    A3._runtimeFrames = { target = units[1], focus = units[2] }
    A3.RenderFrame = function(frame)
        return NativeApply.ApplyConfig(frame, configs[frame])
    end
    local function ApplyLive()
        for i = 1, #units do assert(A3.RenderFrame(units[i])) end
        for i = 1, liveCount do assert(A3.RenderFrame(raid[i])) end
        return true
    end
    A3.RefreshAll = ApplyLive
    A3.InvalidateNativeVisualInputs()
    ApplyLive()
    A3.RefreshRoundedDispelOverlayMasks()
    local token = A3.GetNativeVisualSignature()
    local expected = {}
    for frame in pairs(configs) do
        expected[frame] = { frame.Auras.Buffs, frame.Auras.DispelSensorNeutral or frame.Auras.GroupSlots }
    end
    for i = 6, 25 do raid[i] = MakeFrame("raid" .. i, true) end
    liveCount = 25
    local before = counts.containers
    A3.RefreshRoundedDispelOverlayMasks()
    assert(A3.GetNativeVisualSignature() == token, "raid growth changed the global visual token without settings changes")
    for frame, owners in pairs(expected) do
        assert(frame.Auras.Buffs == owners[1], "raid growth rebuilt an existing lane")
        assert((frame.Auras.DispelSensorNeutral or frame.Auras.GroupSlots) == owners[2], "raid growth rebuilt an existing mask")
    end
    -- New frames may build their first owners; all existing frames build zero.
    before = counts.containers
    for frame in pairs(expected) do assert(A3.RenderFrame(frame)) end
    Built(before, "raid growth: existing frames", 0)
    ApplyLive()
    before = counts.containers
    liveCount = 5
    A3.RefreshRoundedDispelOverlayMasks()
    A3.InvalidateNativeVisualInputs()
    ApplyLive()
    Built(before, "raid shrink: existing frames", 0)
    assert(A3.GetNativeVisualSignature() == token, "raid shrink changed the global visual token without settings changes")
    for frame, owners in pairs(expected) do
        assert(frame.Auras.Buffs == owners[1], "raid shrink changed an existing lane")
        assert((frame.Auras.DispelSensorNeutral or frame.Auras.GroupSlots) == owners[2], "raid shrink changed an existing mask")
    end
    local function MaskOwner(frame) return frame.Auras.DispelSensorNeutral or frame.Auras.GroupSlots end
    local function MaskAnchor(frame) return assert(MaskOwner(frame)._buttons[1]._roundedMask)._point[2] end
    local target, focus = units[1], units[2]
    local embedded, sibling = MaskOwner(target), MaskOwner(focus)
    assert(MaskAnchor(target) == target, "embedded unit mask missed its shared anchor")
    before = counts.containers
    target.MSUFSpec.power.detached = true
    A3.RefreshRoundedDispelOverlayMasks()
    Built(before, "one rounded unit detached", 1)
    assert(MaskAnchor(target) == target.hpBar, "detached unit mask kept its embedded anchor")
    assert(MaskOwner(focus) == sibling and target.Auras.Buffs == expected[target][1], "detach rebuilt unrelated owners")
    assert(A3.GetNativeVisualSignature() == token, "per-frame detach changed global visual content")
    local detached = MaskOwner(target)
    target.MSUFSpec.power.detached = false
    A3.RefreshRoundedDispelOverlayMasks()
    Built(before, "rounded unit re-embedded", 1)
    assert(MaskOwner(target) == embedded and MaskAnchor(target) == target, "re-embed did not revive the shared-anchor mask")
    target.MSUFSpec.power.embed = false
    A3.RefreshRoundedDispelOverlayMasks()
    assert(MaskOwner(target) == detached and MaskAnchor(target) == target.hpBar, "embed=false did not revive the detached mask")
    target.MSUFSpec.power.embed = true
    A3.RefreshRoundedDispelOverlayMasks()
    target._msufRUFForcedStyle = "SQUARE"
    A3.RefreshRoundedDispelOverlayMasks()
    Built(before, "one unit forced square", 2)
    assert(MaskOwner(target)._buttons[1]._roundedMask == nil, "forced square retained a rounded mask")
    target._msufRUFForcedStyle = "ROUNDED"
    A3.RefreshRoundedDispelOverlayMasks()
    assert(MaskOwner(target) == embedded, "forced rounded did not revive its mask")
    local group = raid[1]
    local groupEmbedded = MaskOwner(group)
    assert(MaskAnchor(group) == group.barGroup, "embedded group mask missed its shared bars")
    group.MSUFSpec.power.embed = false
    A3.RefreshRoundedDispelOverlayMasks()
    Built(before, "one group unit detached", 3)
    assert(MaskAnchor(group) == group.health, "detached group mask kept its shared bars")
    group.MSUFSpec.power.embed = true
    A3.RefreshRoundedDispelOverlayMasks()
    assert(MaskOwner(group) == groupEmbedded, "group re-embed did not revive its mask")
    assert(MaskOwner(focus) == sibling and A3.GetNativeVisualSignature() == token, "frame masks changed sibling/global content")
    assert(counts.sealedWrites == 0, "frame mask refresh wrote sealed native buttons")
    print("raid 5 -> 25 -> 5: global token unchanged / existing containers +0; embed/detach: only affected mask follows")
    MSUF.GF, MSUF.UF.ForEachFrame = nil, nil
end

-- Retained allocations scale with distinct lanes, never with native slot count.
do
    local priority=Lane({kind="buff",rootKey="AllocationPriority",unit="target",max=12})
    priority.customPriority=true
    priority.customPrioritySpellIDs={101,102,103,104,105,106,107,108,109,110,111,112}
    priority._msufA3StructuralSignature=Signatures.LaneStructuralSignature(priority)
    local container=NativeApply.ApplyLane(targetRoot,priority,targetFrame)
    assert(#container._msufA3NativeButtonConfigs==1,"priority slots allocated duplicate lane snapshots")
    for i=2,#container._buttons do
        assert(container._buttons[i]._bakedWith==container._buttons[1]._bakedWith,"priority slots did not share their captured lane")
    end
    local sensor=Sensor("target")
    sensor.max=12
    sensor._msufA3StructuralSignature=Signatures.SensorStructuralSignature(sensor)
    assert(NativeApply.ApplyConfig(targetFrame,{enabled=true,unit="target",sensors={dispelBorder=sensor}},"AURAS3_GROWTH_SMOKE"))
    local sensorOwner=assert(targetRoot.DispelSensorNeutral)
    assert(#sensorOwner._msufA3NativeButtonConfigs==1,"sensor indices allocated duplicate lane snapshots")
    local slotRoot=SpellRoot("target",2)
    local slots=SpellIndicators.Apply(targetRoot,slotRoot,targetFrame)
    local captured=slots._msufA3SpellIndicatorButtonSlots[1]
    local minimum=math.huge
    for pass=1,2 do
        SpellIndicators.UpdateSlots(slots,slotRoot)
        collectgarbage("collect");collectgarbage("stop")
        local before=collectgarbage("count")
        for _=1,1000 do assert(SpellIndicators.UpdateSlots(slots,slotRoot)) end
        minimum=math.min(minimum,collectgarbage("count")-before)
        collectgarbage("restart")
    end
    assert(minimum<1,"Spell Indicator reuse allocated "..minimum.." KiB of slot snapshots")
    assert(slots._msufA3SpellIndicatorButtonSlots[1]==captured,"reuse replaced the captured Spell Indicator slot")
    print(string.format("native snapshots: 1 per priority/sensor lane; 1000 slot reuses: %.3f KiB",minimum))
end

print(string.format("aura native container growth smoke passed (%d containers, %d AuraButtons built)",
    counts.containers, counts.buttons))
