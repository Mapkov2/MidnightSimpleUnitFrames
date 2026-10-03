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
    self._buttons = self._buttons or {}
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
local A3 = { _nativeVisualGen = 0 }
local MSUF = { MSUF_Auras3 = A3, UF = {}, Auras3RuntimeFactories = {} }
_G.MSUF_NS, _G.MSUF = MSUF, MSUF
assert(loadfile(ADDON .. "Libs/MSUFUnitFrames/MSUF_UF_Layers.lua"))("MidnightSimpleUnitFrames", MSUF)
assert(loadfile(ADDON .. "Auras3/MSUF_Auras3_SpellIndicators.lua"))("MidnightSimpleUnitFrames", MSUF)
local SpellIndicators = assert(A3.SpellIndicators, "Spell Indicator runtime did not load")
for _, name in ipairs({ "Signatures", "OwnerConfig", "NativeContract", "ButtonVisuals", "Containers", "NativeApply" }) do
    assert(loadfile(ADDON .. "Auras3/Runtime/MSUF_Auras3_Runtime_" .. name .. ".lua"))("MidnightSimpleUnitFrames", MSUF)
end
local Factories = MSUF.Auras3RuntimeFactories

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
    Schema = { DEFAULT_SHARED = { iconSize = 20, spacing = 2 }, COLD_APPLY_REASONS = {}, IDENTITY_AURA_REFRESH_REASONS = {} },
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
Build("OwnerConfig")
local Contract = Build("NativeContract")
local Visuals = Build("ButtonVisuals")
-- Buttons record the lane they were styled for; geometry is the real cold path.
dependencies.ButtonVisuals = {
    PrepareAuraButton = function(button, lane) button._bakedWith = lane end,
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
        nativeFilter = o.filter or "HELPFUL", candidateFilterSignature = "none", showCooldownSwipe = true,
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
    local cfg = { enabled = true, unit = "party1", group = true, lanes = {
        buff = Lane({ kind = "buff", rootKey = "Buffs", unit = "party1", max = 1, x = o.slotX }),
        debuff = Lane({ kind = "debuff", rootKey = "Debuffs", unit = "party1", max = 3, filter = "HARMFUL",
            x = o.flowX, size = o.flowSize, alpha = o.flowAlpha, enabled = o.flow ~= false }),
    }, sensors = o.sensor ~= false and { dispelBorder = Sensor("party1", o.sensorSize) } or nil,
        spellIndicators = SpellRoot("party1", o.spell) }
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

print(string.format("aura native container growth smoke passed (%d containers, %d AuraButtons built)",
    counts.containers, counts.buttons))
