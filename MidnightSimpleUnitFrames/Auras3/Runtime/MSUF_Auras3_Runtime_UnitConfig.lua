-- Auras3 runtime: UnitConfig.
-- Unit configuration cache, explicit invalidation and diagnostic projection. Cache identity and generation checks must remain equivalent for live and preview consumers.
-- The factory runs once at addon load; dependency bindings are local upvalues on live paths.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
MSUF.Auras3RuntimeFactories = MSUF.Auras3RuntimeFactories or {}
MSUF.Auras3RuntimeFactories.UnitConfig = function(addonName, MSUF, A3, UF, ExportPublic, dependencies)
local SpellIndicatorsRuntime = A3.SpellIndicators
local pairs = pairs
local tonumber = tonumber
local tostring = tostring
local type = type
local CandidateFiltersFromBlacklist = dependencies.ConfigValues.CandidateFiltersFromBlacklist
local CompileDispelSensor = dependencies.DispelConfig.CompileDispelSensor
local CompileUnitCustomContainers = dependencies.CustomConfig.CompileUnitCustomContainers
local CompileUnitCustomDisplays = dependencies.CustomConfig.CompileUnitCustomDisplays
local CompileUnitLane = dependencies.LaneConfig.CompileUnitLane
local CompileUnitLaneEffects = dependencies.CustomConfig.CompileUnitLaneEffects
local EffectiveUnitBlacklist = dependencies.ConfigValues.EffectiveUnitBlacklist
local EffectiveUnitCustomContainers = dependencies.CustomConfig.EffectiveUnitCustomContainers
local EffectiveUnitTables = dependencies.ConfigValues.EffectiveUnitTables
local EmptyUnitFrameConfig = dependencies.CustomConfig.EmptyUnitFrameConfig
local EnsureDB = dependencies.ConfigValues.EnsureDB
local NormalizeRuntimeUnit = dependencies.ConfigValues.NormalizeRuntimeUnit
local ReadNumber = dependencies.ConfigValues.ReadNumber
local ReadRaw = dependencies.ConfigValues.ReadRaw
local UnitSupportsTargetDots = dependencies.CustomConfig.UnitSupportsTargetDots
local UnitAuraIconsEnabled = dependencies.ConfigValues.UnitAuraIconsEnabled

local function InvalidateUnitRuntimeConfig(unit)
    unit = NormalizeRuntimeUnit(unit)
    if not unit then return nil end
    local runtimeCache = A3._runtimeConfigCache
    if runtimeCache then runtimeCache[unit] = nil end
    local frame = (A3._runtimeFrames and A3._runtimeFrames[unit])
        or (UF and UF.GetFrame and UF.GetFrame(unit))
        or (UF and UF.frames and UF.frames[unit])
        or _G["MSUF_" .. unit]
    if frame then
        if frame.MSUFSpec then frame.MSUFSpec._msufA3UnitAuraConfigCache = nil end
        if frame.Auras then frame.Auras.needFullUpdate = true end
    end
    return unit
end

--- Menu writes land in the Auras3 saved model without touching UF.Config, so
--- neither _runtimeConfigGen nor UF.Config.serial moves. Callers that refresh
--- a unit through the UF element path must drop this cache first or both the
--- live lane and the menu preview keep reading the pre-write layout.
function A3.InvalidateUnitRuntimeConfig(unit)
    if unit == "boss" then
        for i = 1, 5 do InvalidateUnitRuntimeConfig("boss" .. i) end
        return "boss"
    end
    return InvalidateUnitRuntimeConfig(unit)
end
local function BuildUnitFrameConfig(unit, frameSpec)
    unit = NormalizeRuntimeUnit(unit)
    if not unit then return nil end
    local auras = EnsureDB()
    local iconsEnabled = UnitAuraIconsEnabled(auras, unit)
    local customLanes, customEffects, targetDotEffects = CompileUnitCustomContainers(auras, unit, frameSpec)
    local hasCustomContainers = false
    if customLanes then
        for _, lane in pairs(customLanes) do
            if lane and lane.enabled == true then hasCustomContainers = true; break end
        end
    end
    local legacyCustomDisplays = not EffectiveUnitCustomContainers(auras, unit) and CompileUnitCustomDisplays(auras, unit) or nil
    local dispelBorder = iconsEnabled and CompileDispelSensor(unit, frameSpec, false, "border") or nil
    -- Purge is a standalone one-slot native sensor. It must keep working when
    -- the ordinary visible aura lanes are disabled.
    local purgeBorder = CompileDispelSensor(unit, frameSpec, false, "purge")
    local dispelOverlay = iconsEnabled and CompileDispelSensor(unit, frameSpec, false, "overlay") or nil
    local dispelSymbol = iconsEnabled and CompileDispelSensor(unit, frameSpec, false, "symbol") or nil
    local buff, debuff, laneEffects
    if iconsEnabled then
        local layout, laneLayout, filtersRoot = EffectiveUnitTables(auras, unit)
        local blacklist = EffectiveUnitBlacklist(auras, unit)
        local buffBlacklist = type(blacklist) == "table" and type(blacklist.buffs) == "table" and blacklist.buffs or blacklist
        local debuffBlacklist = type(blacklist) == "table" and type(blacklist.debuffs) == "table" and blacklist.debuffs or blacklist
        local buffCandidates, buffCandidateSignature = CandidateFiltersFromBlacklist(buffBlacklist)
        local debuffCandidates, debuffCandidateSignature = CandidateFiltersFromBlacklist(debuffBlacklist)
        if unit == "player" then
            local customContainers = EffectiveUnitCustomContainers(auras, unit)
            local defensiveLane = customLanes and (customLanes.custom4 or customLanes.defensivePortrait)
            local tracked = defensiveLane and defensiveLane.candidateFilters
                and defensiveLane.candidateFilters.includeSpellIDs
            buffCandidates, buffCandidateSignature = A3._AddPlayerDefensiveAutoBlacklist(
                buffCandidates, buffCandidateSignature,
                type(customContainers) == "table" and customContainers[4] or nil, tracked)
        elseif UnitSupportsTargetDots(unit) then
            -- Each UnitFrame resolves its own saved Target/Focus/Boss/Arena scope.
            -- Reuse the already compiled player-owned DoT IDs; no extra aura
            -- query or runtime filtering is introduced by this convenience.
            local customContainers = EffectiveUnitCustomContainers(auras, unit)
            local targetDotLane = customLanes and (customLanes.custom4 or customLanes.targetDotPortrait)
            local tracked = targetDotLane and targetDotLane.candidateFilters
                and targetDotLane.candidateFilters.includeSpellIDs
            debuffCandidates, debuffCandidateSignature = A3._AddTargetDotAutoBlacklist(
                debuffCandidates, debuffCandidateSignature,
                type(customContainers) == "table" and customContainers[4] or nil, tracked)
        end
        local portraitShape = frameSpec and frameSpec.portrait and frameSpec.portrait.shape
        buff = CompileUnitLane(unit, laneLayout, layout, filtersRoot, "buff", buffCandidates, buffCandidateSignature, portraitShape, auras.shared)
        debuff = CompileUnitLane(unit, laneLayout, layout, filtersRoot, "debuff", debuffCandidates, debuffCandidateSignature, portraitShape, auras.shared)
        laneEffects = CompileUnitLaneEffects(unit, laneLayout, buff, debuff)
    end
    local spellIndicators = customEffects or legacyCustomDisplays
    local spellIndicatorsAssist, spellIndicatorsHostile
    spellIndicators, spellIndicatorsAssist, spellIndicatorsHostile =
        SpellIndicatorsRuntime.PartitionUnitRoot(spellIndicators)
    local laneEffectsAssist, laneEffectsHostile
    laneEffects, laneEffectsAssist, laneEffectsHostile =
        SpellIndicatorsRuntime.PartitionUnitRoot(laneEffects)
    local targetDotEffectsAssist, targetDotEffectsHostile
    targetDotEffects, targetDotEffectsAssist, targetDotEffectsHostile =
        SpellIndicatorsRuntime.PartitionUnitRoot(targetDotEffects)
    local hasNativeAuraWork = (buff and buff.enabled == true) or (debuff and debuff.enabled == true)
        or (dispelBorder and dispelBorder.enabled == true) or (purgeBorder and purgeBorder.enabled == true)
        or (dispelOverlay and dispelOverlay.enabled == true) or (dispelSymbol and dispelSymbol.enabled == true)
    if not hasNativeAuraWork and not hasCustomContainers
        and not customEffects and not targetDotEffects and not laneEffects and not legacyCustomDisplays then
        -- The Aura owner may deliberately stay enabled with every icon cap at
        -- 0 so Dispel can be turned on later.  That idle state must still
        -- compile to the empty config: no native container and no event owner.
        return EmptyUnitFrameConfig(unit)
    end
    local lanes = { buff = buff, debuff = debuff }
    if customLanes then
        for key, lane in pairs(customLanes) do lanes[key] = lane end
    end
    return {
        unit = unit,
        enabled = (buff and buff.enabled == true) or (debuff and debuff.enabled == true)
            or (dispelBorder and dispelBorder.enabled == true) or (dispelOverlay and dispelOverlay.enabled == true)
            or (purgeBorder and purgeBorder.enabled == true)
            or (dispelSymbol and dispelSymbol.enabled == true)
            or hasCustomContainers or (customEffects and customEffects.enabled == true)
            or (targetDotEffects and targetDotEffects.enabled == true) or (laneEffects and laneEffects.enabled == true)
            or (legacyCustomDisplays and legacyCustomDisplays.enabled == true),
        lanes = lanes,
        sensors = { dispelBorder = dispelBorder, purgeBorder = purgeBorder,
            dispelOverlay = dispelOverlay, dispelSymbol = dispelSymbol },
        spellIndicators = spellIndicators,
        spellIndicatorsAssist = spellIndicatorsAssist,
        spellIndicatorsHostile = spellIndicatorsHostile,
        laneEffects = laneEffects,
        laneEffectsAssist = laneEffectsAssist,
        laneEffectsHostile = laneEffectsHostile,
        targetDotEffects = targetDotEffects,
        targetDotEffectsAssist = targetDotEffectsAssist,
        targetDotEffectsHostile = targetDotEffectsHostile,
        group = false,
        _msufA3ConfigGen = A3._runtimeConfigGen or 1,
        _msufA3VisualGen = A3._nativeVisualGen or 0,
    }
end

function A3.ResolveUnitFrameConfig(unit, frameSpec)
    unit = NormalizeRuntimeUnit(unit)
    if not unit then return nil end
    local gen = A3._runtimeConfigGen or 1
    local visualGen = A3._nativeVisualGen or 0
    if frameSpec ~= nil then
        -- Frame-spec configs also consume UnitFrame border/overlay settings.
        -- Cache them on the compiled spec so runtime events do not re-walk DB
        -- and do not accidentally push ApplyConfig/AddAuraGroup into hot paths.
        local specSerial = (UF and UF.Config and UF.Config.serial) or 0
        local cached = frameSpec._msufA3UnitAuraConfigCache
        if cached
            and cached.unit == unit
            and cached.gen == gen
            and cached.visualGen == visualGen
            and cached.specSerial == specSerial
        then
            return cached.config
        end
        local cfg = BuildUnitFrameConfig(unit, frameSpec)
        frameSpec._msufA3UnitAuraConfigCache = {
            unit = unit,
            gen = gen,
            visualGen = visualGen,
            specSerial = specSerial,
            config = cfg,
        }
        return cfg
    end
    A3._runtimeConfigCache = A3._runtimeConfigCache or {}
    local cached = A3._runtimeConfigCache[unit]
    if cached and cached.gen == gen and cached.visualGen == visualGen then return cached.config end
    local cfg = BuildUnitFrameConfig(unit, nil)
    A3._runtimeConfigCache[unit] = { gen = gen, visualGen = visualGen, config = cfg }
    return cfg
end

--- Cold-path diagnostics for Assistant/support surfaces.  Blizzard owns the
--- native AuraSlot assignment and may keep its visibility secret, so this API
--- reports the effective configured owners without querying AuraButton state.
--- It creates no frame, event, timer, or OnUpdate.
function A3.GetUnitFrameEffectDiagnostics(unit, frame)
    unit = NormalizeRuntimeUnit(unit or (frame and frame.MSUFUnitKey))
    if not unit then return nil end

    frame = frame
        or (A3._runtimeFrames and A3._runtimeFrames[unit])
        or (UF and UF.GetFrame and UF.GetFrame(unit))
        or (UF and UF.frames and UF.frames[unit])
        or _G["MSUF_" .. unit]
    local root = frame and frame.Auras
    local appliedConfig = root and type(root._msufA3Config) == "table" and root._msufA3Config or nil
    local cfg = appliedConfig or A3.ResolveUnitFrameConfig(unit, frame and frame.MSUFSpec)
    local installed = root ~= nil and root._msufA3Applied == true and appliedConfig == cfg

    local auras = EnsureDB()
    local _, effectiveShared = EffectiveUnitTables(auras, unit)
    local localShared = effectiveShared
    local laneEffectRoots = cfg and {
        cfg.laneEffects, cfg.laneEffectsAssist, cfg.laneEffectsHostile,
    } or nil

    local function CopyColor(color)
        color = type(color) == "table" and color or nil
        return {
            tonumber(color and color[1]) or 0.69,
            tonumber(color and color[2]) or 0.50,
            tonumber(color and color[3]) or 0.88,
            tonumber(color and color[4]) or 0.80,
        }
    end

    local function FindLaneSlot(kind)
        if not laneEffectRoots then return nil end
        local itemKey = "uflane_effect:" .. kind
        for rootIndex = 1, 3 do
            local laneRoot = laneEffectRoots[rootIndex]
            local laneSlots = laneRoot and laneRoot.enabled == true
                and type(laneRoot.slots) == "table" and laneRoot.slots or nil
            for i = 1, #(laneSlots or {}) do
                local slot = laneSlots[i]
                if type(slot) == "table" and slot.itemKey == itemKey then return slot end
            end
        end
        return nil
    end

    local function LaneSnapshot(kind)
        local prefix = kind == "buff" and "buff" or "debuff"
        local keyPrefix = prefix .. "FrameEffect"
        local slot = FindLaneSlot(kind)
        local effect = slot and type(slot.frameEffect) == "table" and slot.frameEffect or nil
        local configuredType = tostring(ReadRaw(effectiveShared, nil, keyPrefix .. "Type") or "none"):lower()
        local color = effect and effect.color or ReadRaw(effectiveShared, nil, keyPrefix .. "Color")
        local function FieldSource(suffix)
            return localShared and localShared[keyPrefix .. suffix] ~= nil and "unit" or "default"
        end
        return {
            ownerKind = "lane",
            lane = kind,
            display = kind == "buff" and "Buffs" or "Debuffs",
            configuredType = configuredType,
            renderedType = effect and tostring(effect.type or configuredType):lower() or nil,
            armed = slot ~= nil,
            installed = installed and slot ~= nil,
            visibility = "native-opaque",
            color = CopyColor(color),
            priority = tonumber(effect and effect.priority)
                or ReadNumber(effectiveShared, nil, keyPrefix .. "Priority", 5, 1, 10),
            thickness = tonumber(effect and effect.thickness)
                or ReadNumber(effectiveShared, nil, keyPrefix .. "Thickness", 2, 1, 16),
            layer = tonumber(effect and effect.layer)
                or ReadNumber(effectiveShared, nil, keyPrefix .. "Layer", 0, 0, 30),
            strata = tostring((effect and effect.strata)
                or ReadRaw(effectiveShared, nil, keyPrefix .. "Strata") or "AUTO"),
            nativeFilter = slot and slot.nativeFilter or nil,
            candidateFilterSignature = slot and slot.candidateFilterSignature or nil,
            source = FieldSource("Type"),
            colorSource = FieldSource("Color"),
            thicknessSource = FieldSource("Thickness"),
            prioritySource = FieldSource("Priority"),
            layerSource = FieldSource("Layer"),
            strataSource = FieldSource("Strata"),
        }
    end

    local snapshot = {
        unit = unit,
        applied = installed,
        configSource = appliedConfig and "applied" or "resolved",
        visibility = "native-opaque",
        lanes = {
            buff = LaneSnapshot("buff"),
            debuff = LaneSnapshot("debuff"),
        },
        custom = {},
    }

    -- Custom Aura and Target-DoT Full-Frame effects share the same renderer.
    -- Expose their compiled owners too, while still leaving visibility opaque.
    for _, rootKey in ipairs({
        "spellIndicators", "spellIndicatorsAssist", "spellIndicatorsHostile",
        "targetDotEffects", "targetDotEffectsAssist", "targetDotEffectsHostile",
    }) do
        local effectRoot = cfg and cfg[rootKey]
        local slots = effectRoot and effectRoot.enabled == true and type(effectRoot.slots) == "table" and effectRoot.slots or nil
        for i = 1, #(slots or {}) do
            local slot = slots[i]
            local effect = type(slot) == "table" and type(slot.frameEffect) == "table" and slot.frameEffect or nil
            if effect and tostring(effect.type or "none"):lower() ~= "none" then
                snapshot.custom[#snapshot.custom + 1] = {
                    ownerKind = rootKey:find("targetDotEffects", 1, true) and "targetDots" or "custom",
                    itemKey = slot.itemKey,
                    display = slot.display,
                    configuredType = tostring(effect.type):lower(),
                    renderedType = tostring(effect.type):lower(),
                    armed = true,
                    installed = installed,
                    visibility = "native-opaque",
                    color = CopyColor(effect.color),
                    priority = tonumber(effect.priority) or 5,
                    thickness = tonumber(effect.thickness) or 2,
                    layer = tonumber(effect.layer) or 0,
                    strata = tostring(effect.strata or "AUTO"),
                    nativeFilter = slot.nativeFilter,
                    candidateFilterSignature = slot.candidateFilterSignature,
                }
            end
        end
    end
    return snapshot
end

return {
    InvalidateUnitRuntimeConfig = InvalidateUnitRuntimeConfig,
}
end
