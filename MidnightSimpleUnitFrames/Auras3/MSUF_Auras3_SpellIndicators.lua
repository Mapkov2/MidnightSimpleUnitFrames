--- Auras3/MSUF_Auras3_SpellIndicators.lua
--- Group-frame spell indicators on WoW 12.1 CustomAuraContainer aura slots.
local addonName, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}

local A3 = MSUF.MSUF_Auras3
if type(A3) ~= "table" then
    A3 = {}
    MSUF.MSUF_Auras3 = A3
end

local Runtime = A3.SpellIndicators or {}
A3.SpellIndicators = Runtime

local type, tostring, tonumber, pairs = type, tostring, tonumber, pairs
local FrameLayers = MSUF.UF and MSUF.UF.Layers or {}
local issecretvalue = _G.issecretvalue

-- Config, effects and reminders are initialized once. The native owner below
-- keeps direct local calls; module boundaries add no per-aura dispatch layer.
local modules = assert(A3.SpellIndicatorModules, "Auras3 spell-indicator modules not loaded")
local config = modules.Config()
local effects = modules.Effects(config)
local reminders = modules.Reminders(config, effects)
effects.BindReminderCleanup(reminders.ForgetReminderEnchantPlaceholder)
A3.SpellIndicatorModules = nil
local ResolveFrameStrata = config.ResolveFrameStrata
local SyncFrameStrata = config.SyncFrameStrata
local SpellIconBaseOffset = config.SpellIconBaseOffset
local SlotLayoutSignature = config.SlotLayoutSignature
local ApplyButtonIconEffect = effects.ApplyButtonIconEffect
local ApplyAlwaysButtonFrameEffect = effects.ApplyAlwaysButtonFrameEffect
local SyncMissingFrame = reminders.SyncMissingFrame

function Runtime.Install(deps)
    Runtime._deps = deps
    effects.Install(deps.SetAssistAlpha)
    reminders.Install(deps.SetAssistAlpha)
end

local function D()
    return Runtime._deps
end

local function SyncButtonGeometry(button, slot, parentFrame, forceGeometry)
    if not (button and slot and parentFrame) then return false end
    local width, height = slot.width or slot.size or 1, slot.height or slot.size or 1
    local anchor, x, y = slot.anchor or "TOPLEFT", slot.x or 0, slot.y or 0
    if forceGeometry == true
        or button._msufA3GeomParent ~= parentFrame or button._msufA3GeomAnchor ~= anchor
        or button._msufA3GeomX ~= x or button._msufA3GeomY ~= y
        or button._msufA3GeomWidth ~= width or button._msufA3GeomHeight ~= height then
        button._msufA3GeomParent, button._msufA3GeomAnchor = parentFrame, anchor
        button._msufA3GeomX, button._msufA3GeomY = x, y
        button._msufA3GeomWidth, button._msufA3GeomHeight = width, height
        button:ClearAllPoints()
        button:SetSize(width, height)
        button:SetPoint(anchor, parentFrame, anchor, x, y)
    end
    SyncFrameStrata(button, ResolveFrameStrata(parentFrame, slot.strata))
    -- The native AuraSlot is only the lowest-level secret-visibility owner.
    -- Its independently levelled icon host and frame-effect root carry the two
    -- user Layers, so one assignment can render both in either order.
    local level
    if slot.frameEffect then
        level = (tonumber(FrameLayers.ELEMENT_LEVEL_BASE)
            or (FrameLayers.ElementLevel and FrameLayers.ElementLevel(0, 0, 0))
            or ((parentFrame:GetFrameLevel() or 0) + 1)) - 1
    else
        level = FrameLayers.ElementLevel and FrameLayers.ElementLevel(slot.layer, 9, 1)
            or ((parentFrame:GetFrameLevel() or 0) + SpellIconBaseOffset(parentFrame) + (slot.layer or 9))
    end
    if button.SetFrameLevel and button._msufA3GeomLevel ~= level then
        button._msufA3GeomLevel = level
        button:SetFrameLevel(level)
    end
    return true
end

local function ApplyVisual(button, slot)
    if not (button and slot) then return end
    local icon = button.Icon
    -- Display-as-Bar has no icon surface. Avoid allocating one after the native
    -- duration StatusBar has already been installed in initializeFrame.
    if not icon and slot.visual ~= "bar" then
        icon = button:CreateTexture(nil, "ARTWORK")
        button.Icon = icon
    end
    if slot.hiddenVisual == true then
        -- AuraSlot visibility is secret-backed. Effect-only slots therefore
        -- keep alpha at one and hide only their icon regions; the descendant
        -- frame-effect root inherits the native visibility directly.
        button:SetAlpha(1)
        button:ClearIcon()
        button:ClearApplicationCount()
        button:ClearDurationCooldown()
        button:ClearDurationText()
        button:ClearDurationBar()
        button:ClearDispelTypeTextures()
        button:ClearDispelTypeText()
        if icon then icon:Hide() end
        if button._msufA3SpellIndicatorSwatch then button._msufA3SpellIndicatorSwatch:Hide() end
        return
    end
    local visualOwner = button._msufA3SpellIndicatorVisualHost or button
    if visualOwner ~= button then
        button:SetAlpha(1)
        visualOwner:SetAlpha(slot.alpha or 1)
    else
        button:SetAlpha(slot.alpha or 1)
    end
    if slot.visual == "square" then
        icon:SetAlpha(0)
        local swatch = button._msufA3SpellIndicatorSwatch
        if not swatch then
            swatch = visualOwner:CreateTexture(nil, "OVERLAY")
            button._msufA3SpellIndicatorSwatch = swatch
        end
        swatch:SetTexture("Interface\\Buttons\\WHITE8X8")
        swatch:SetTexCoord(0, 1, 0, 1)
        swatch:SetVertexColor(slot.color[1] or 1, slot.color[2] or 1, slot.color[3] or 1, slot.color[4] or 1)
        swatch:ClearAllPoints()
        swatch:SetAllPoints(visualOwner)
        swatch:Show()
    elseif slot.visual == "bar" then
        -- PrepareAuraButton owns the C-side duration StatusBar. Never cover it
        -- with the legacy static swatch used by Square indicators.
        if button._msufA3SpellIndicatorSwatch then button._msufA3SpellIndicatorSwatch:Hide() end
        if icon then icon:Hide() end
    elseif slot.visual == "number" then
        if button._msufA3SpellIndicatorSwatch then button._msufA3SpellIndicatorSwatch:Hide() end
        icon:Hide()
    elseif slot.visual == "icon" then
        if button._msufA3SpellIndicatorSwatch then button._msufA3SpellIndicatorSwatch:Hide() end
        icon:SetVertexColor(1, 1, 1, 1)
        icon:SetAlpha(1)
    else
        if button._msufA3SpellIndicatorSwatch then button._msufA3SpellIndicatorSwatch:Hide() end
        icon:Hide()
    end
end

local function PrepareButton(button, slot, parentFrame, forceGeometry)
    local deps = D()
    if not (button and slot and parentFrame and deps.PrepareAuraButton and deps.ValidateAuraButton) then return false end
    deps.ValidateAuraButton(button)
    button._msufA3ManagedAuraButton = true
    button._msufA3NativeButton = true
    button._msufA3LaneKind = "spellIndicator"
    button._msufA3SpellIndicatorSlot = slot
    button._msufA3SpellIndicatorParentFrame = parentFrame
    button._msufA3ParentFrame = parentFrame
    local prepareSignature = slot._msufA3LayoutSignature or SlotLayoutSignature(slot)
    local needsFullPrepare = button._msufA3SpellIndicatorPrepareSignature ~= prepareSignature
    if needsFullPrepare then
        -- The shared preparer creates MSUF-owned duration/text child surfaces
        -- from the button's current frame level. Put the AuraSlot on its final
        -- universal Layer first so those children stay inside the same 0..30
        -- slot instead of retaining the assignment container's birth level.
        SyncButtonGeometry(button, slot, parentFrame, true)
        -- The shared aura preparer finishes with the normal aura-grid layout,
        -- which temporarily anchors this manually placed slot to its container.
        -- Re-running it for an unchanged slot used to leave the button there:
        -- SyncButtonGeometry's desired-value cache then (correctly but
        -- misleadingly) skipped the saved anchor. Prepare only when visual
        -- configuration changed, and force our manual anchor after that pass.
        deps.PrepareAuraButton(button, slot, 1)
        button._msufA3SpellIndicatorPrepareSignature = prepareSignature
    end
    SyncButtonGeometry(button, slot, parentFrame, forceGeometry == true or needsFullPrepare)
    ApplyVisual(button, slot)
    ApplyButtonIconEffect(button, slot, parentFrame)
    ApplyAlwaysButtonFrameEffect(button, slot, parentFrame)
    SyncMissingFrame(parentFrame, slot, button, button._msufA3SpellIndicatorContainer)
    -- The shared AuraButton preparer permanently disables click input for
    -- every Unit/Group aura. Only tooltip motion remains lane-selectable here.
    button:SetMouseMotionEnabled(slot.showTooltip ~= false)
    return true
end

local function SlotOptions(container, slot, buttonIndex)
    return {
        maxFrameCount = 1,
        candidateFilters = slot.candidateFilters,
        initializeFrame = function(button)
            container[buttonIndex] = button
            button._msufA3SpellIndicatorContainer = container
            -- This closure lives for the container's whole lifetime, but the
            -- native container re-runs it every time it recreates the slot's
            -- button (every aura reapplication). Config edits replace the slot
            -- tables in _msufA3SpellIndicatorButtonSlots; re-installing the
            -- table captured at creation resurrected pre-edit geometry, so
            -- always prepare with the container's current slot instead.
            local slots = container._msufA3SpellIndicatorButtonSlots
            local currentSlot = (slots and slots[buttonIndex]) or slot
            if slots then slots[buttonIndex] = currentSlot end
            PrepareButton(button, currentSlot, container._msufA3ParentFrame)
        end,
    }
end

local function HasLiveNativeButton(container)
    local slots = container and container._msufA3SpellIndicatorButtonSlots
    if type(slots) ~= "table" then return false end
    for i = 1, #slots do
        if slots[i] and container[i] then return true end
    end
    return false
end

--- The container level is a birth property once native AuraButtons exist below
--- it: moving it moves every one of them plus their effect surfaces, and a
--- sealed AuraButton descendant cannot be written back afterwards. So the
--- fixed-slot base is written only while the container is still empty. A real
--- change reaches the frames through the recreate path, which builds fresh
--- buttons under the new level.
---
--- `sharedLevelOwner` is set by the group-slot owner when a flowing AuraGroup
--- shares this container. That lane is the container's layering authority --
--- its buttons spawn at container + 1 and follow it -- so writing the
--- fixed-slot base here as well moved the container twice per sync, down to the
--- frame base and straight back up, dragging every already levelled AuraButton
--- and effect surface along.
function Runtime.SyncGeometry(container, slotRoot, parentFrame, forceGeometry, sharedLevelOwner)
    if not (container and Runtime.IsRoot(slotRoot)) then return false end
    parentFrame = parentFrame or container._msufA3ParentFrame or container:GetParent()
    if not parentFrame then return false end
    forceGeometry = forceGeometry == true or container._msufA3ForceSpellIndicatorGeometry == true
    container._msufA3NativeLaneConfig = slotRoot
    container._msufA3ParentFrame = parentFrame
    local root = container:GetParent()
    if root then
        container:ClearAllPoints()
        container:SetAllPoints(root)
    end
    SyncFrameStrata(container, ResolveFrameStrata(parentFrame, slotRoot.strata))
    if container.SetFrameLevel and sharedLevelOwner ~= true then
        local level = parentFrame:GetFrameLevel() or 0
        local current = container.GetFrameLevel and container:GetFrameLevel()
        if issecretvalue(current) == true then current = nil end
        if current ~= level and not HasLiveNativeButton(container) then
            container:SetFrameLevel(level)
        end
    end
    local slots = container._msufA3SpellIndicatorButtonSlots
    -- Initialized AuraButtons can be forbidden while aura data is secret. This
    -- path updates only addon-owned geometry; a force request with live native
    -- buttons remains pending until Runtime.Recreate replaces the container.
    local requiresRecreate = false
    if slots then
        for i = 1, #slots do
            local slot = slots[i]
            if slot then
                if container[i] then
                    requiresRecreate = forceGeometry == true or requiresRecreate
                    -- Reminder placeholders are MSUF-owned frames and stay
                    -- writable while the slot's AuraButton is access
                    -- restricted, so keep them on the current geometry
                    -- instead of waiting for the deferred recreate.
                    if slot.showWhenMissing == true then
                        SyncMissingFrame(parentFrame, slot, container[i], container)
                    end
                else
                    SyncMissingFrame(parentFrame, slot, nil, container)
                end
            end
        end
    end
    if type(slotRoot.slots) == "table" then
        for i = 1, #slotRoot.slots do
            local slot = slotRoot.slots[i]
            if not (slots and slots[i]) then SyncMissingFrame(parentFrame, slot, nil, container) end
        end
    end
    -- Click-to-cast is protected-frame work on a strictly cold path. When
    -- combat blocks it the signature stays unwritten, so the next apply --
    -- which the Aura runtime queues for PLAYER_REGEN_ENABLED -- redoes it.
    if Runtime.SyncReminderCastButtons(parentFrame, slotRoot) == true
        and type(A3._QueueDeferredAuraRuntime) == "function"
    then
        A3._QueueDeferredAuraRuntime(slotRoot.unit, "AURAS3_REMINDER_CLICK_CAST")
    end
    -- With a shared owner the container level is written after this call, so
    -- re-stamping here would be undone again; that owner runs the refresh last.
    if sharedLevelOwner ~= true then Runtime.RefreshFrameEffects(parentFrame) end
    if forceGeometry == true and not requiresRecreate then container._msufA3ForceSpellIndicatorGeometry = nil end
    return true
end

-- Slot-family bridge for the group-frame runtime. Spell Indicators and the
-- dispel sensors are both fixed-position AddAuraSlot consumers, so they can
-- share one native AuraContainer without changing either initializer. Keep
-- Spell Indicator slots first: their logical slot index then remains identical
-- to the native button index used by SyncGeometry and the forbidden-button
-- recreation path.
function Runtime.AttachSlots(container, slotRoot)
    if not (container and Runtime.IsRoot(slotRoot)) then return nil end
    container._msufA3ManagedAuraSlots = true
    container._msufA3SpellIndicatorRoot = true
    container._msufA3SpellIndicatorButtonSlots = {}
    container._msufA3SpellIndicatorSlotFilterStrings = {}
    container._msufA3SpellIndicatorSlotCandidateFilterSignatures = {}
    for i = 1, #slotRoot.slots do
        local slot = slotRoot.slots[i]
        -- The index mapping stays dense either way: container[i] simply
        -- remains nil for an enchant slot, which is exactly what makes the
        -- geometry pass treat it as a placeholder-only surface.
        container._msufA3SpellIndicatorButtonSlots[i] = slot
        if not slot.enchantSlot then
            container:AddAuraSlot(slot.slotKey, slot.nativeFilter, SlotOptions(container, slot, i))
            container._msufA3SpellIndicatorSlotFilterStrings[slot.slotKey] = slot.nativeFilter
            container._msufA3SpellIndicatorSlotCandidateFilterSignatures[slot.slotKey] = slot.candidateFilterSignature
        end
    end
    return #slotRoot.slots
end

local function CreateSlots(root, slotRoot, parentFrame)
    local deps = D()
    if not deps.EnsureLoaded() then
        A3.nativeAuraRuntimeAvailable = false
        A3._RecordNativeAuraRuntimeError((deps.addonName or "Blizzard_AuraContainer") .. " is not loaded: " .. tostring(A3.nativeAuraRuntimeLoadError or "unknown"))
        return nil
    end
    local container = deps.CreateContainer(root)
    if not container then return nil end
    A3.nativeAuraRuntimeAvailable = true
    container._msufA3NativeLane = slotRoot.kind
    container._msufA3NativeRegistered = nil
    container._msufA3NativeRegistrationPending = nil
    container.unit = slotRoot.unit
    container.createdButtons = slotRoot.max or 0
    deps.ConfigureContainer(container, slotRoot.unit)
    Runtime.SyncGeometry(container, slotRoot, parentFrame)
    Runtime.AttachSlots(container, slotRoot)
    if not deps.RegisterContainer(container) then
        if container.Hide then container:Hide() end
        return nil
    end
    container:Show()
    A3.nativeAuraRuntimeError = nil
    return container
end

local function UpdateSlots(container, slotRoot)
    if not (container and Runtime.IsRoot(slotRoot)) then return false end
    container._msufA3SpellIndicatorButtonSlots = container._msufA3SpellIndicatorButtonSlots or {}
    container._msufA3SpellIndicatorSlotFilterStrings = container._msufA3SpellIndicatorSlotFilterStrings or {}
    container._msufA3SpellIndicatorSlotCandidateFilterSignatures = container._msufA3SpellIndicatorSlotCandidateFilterSignatures or {}
    for i = 1, #slotRoot.slots do
        local slot = slotRoot.slots[i]
        container._msufA3SpellIndicatorButtonSlots[i] = slot
        -- Nothing native backs an enchant slot, so neither setter may be
        -- reached with its key: Blizzard asserts on an unknown aura slot.
        -- Its placeholder is the whole surface and the geometry pass owns it.
        if not slot.enchantSlot then
            if container._msufA3SpellIndicatorSlotFilterStrings[slot.slotKey] ~= slot.nativeFilter then
                container:SetAuraSlotFilterString(slot.slotKey, slot.nativeFilter)
                container._msufA3SpellIndicatorSlotFilterStrings[slot.slotKey] = slot.nativeFilter
            end
            if container._msufA3SpellIndicatorSlotCandidateFilterSignatures[slot.slotKey] ~= slot.candidateFilterSignature then
                container:SetAuraSlotCandidateFilters(slot.slotKey, slot.candidateFilters)
                container._msufA3SpellIndicatorSlotCandidateFilterSignatures[slot.slotKey] = slot.candidateFilterSignature
            end
        end
        -- Runtime.SyncGeometry performs the single visual/geometry pass after
        -- every slot has been rebound. Doing it here as well configured each
        -- button twice per refresh and repeated expensive region setters.
    end
    return true
end

function Runtime.Apply(root, slotRoot, parentFrame, forceRecreate)
    if not (root and Runtime.IsRoot(slotRoot)) then return nil end
    local deps = D()
    local key = slotRoot.rootKey or "SpellIndicators"
    local structuralSignature = slotRoot._msufA3StructuralSignature
    local layoutSignature = slotRoot._msufA3LayoutSignature
    local current = root[key]
    if forceRecreate ~= true and current and current._msufA3StructuralSignature == structuralSignature then
        deps.RebindUnit(current, slotRoot.unit)
        current._msufA3NativeLaneConfig = slotRoot
        UpdateSlots(current, slotRoot)
        Runtime.SyncGeometry(current, slotRoot, parentFrame)
        current:Show()
        if not deps.RegisterContainer(current) then return nil end
        current._msufA3StructuralSignature = structuralSignature
        current._msufA3LayoutSignature = layoutSignature
        return current
    end
    Runtime.ReleaseContainerEffects(current, parentFrame)
    deps.HideContainer(current)
    root[key] = nil
    current = CreateSlots(root, slotRoot, parentFrame)
    if current then
        current._msufA3StructuralSignature = structuralSignature
        current._msufA3LayoutSignature = layoutSignature
        root[key] = current
    end
    return current
end

Runtime.UpdateSlots = UpdateSlots

function Runtime.Recreate(container)
    if not (container and container._msufA3SpellIndicatorRoot == true) then return nil end
    if container._msufA3GroupSlotsRoot == true then
        return D().RecreateGroupSlots(container)
    end
    local slotRoot = container._msufA3NativeLaneConfig
    local parentFrame = container._msufA3ParentFrame
    local root = container.GetParent and container:GetParent() or nil
    if not (root and Runtime.IsRoot(slotRoot) and parentFrame) then return nil end
    local replacement = Runtime.Apply(root, slotRoot, parentFrame, true)
    if replacement then replacement._msufA3ForceSpellIndicatorGeometry = nil end
    return replacement
end
