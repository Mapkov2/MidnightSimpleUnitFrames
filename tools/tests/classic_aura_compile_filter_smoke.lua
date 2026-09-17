-- Classic aura filter compiler: compile-and-match contract.
--
-- Game/Classic/Auras/MSUF_Auras3_Compile.lua turns the Aura settings into
-- lane configs. Their filter strings are what reaches C_UnitAuras, and the
-- Classic runtime decides visibility and the dispel border from them. The
-- other Classic aura smokes exercise rendering and menus with permissive
-- stubs, so a wrong filter string or a lost Only mine flag passed all of them.
--
-- This smoke loads the real Classic Features, Compile and UnitFrames files and
-- answers C_UnitAuras with a stub whose filter tokens behave like the client's
-- (PLAYER = cast by the player, pet or vehicle; HARMFUL|RAID = a debuff that
-- has a dispel type; RAID_PLAYER_DISPELLABLE = a dispel type this player's
-- class removes). It asserts only observable results: compiled filter
-- strings, the filters handed to the API, and which aura instance IDs end up
-- visible or light the dispel border.
--
-- Run from the repository root:
--   lua .github/scripts/auras3_test_driver.lua tools/tests/classic_aura_compile_filter_smoke.lua <repoRoot>

local root = assert(arg and arg[1], "repository root argument missing")
local unpack = unpack or table.unpack

local function Check(value, message)
    if not value then error(message or "check failed", 2) end
    return value
end

-- Aura world ----------------------------------------------------------------

local PLAYER_SOURCES = { player = true, pet = true, vehicle = true }
local World = {
    units = {},
    removable = {},
    slotCalls = {},
    indexFilters = {},
    unknownFilters = {},
    nextID = 5000,
}

--- One aura record. `source` is the caster token; `fromPlayer` is the native
--- PLAYER filter membership and defaults to the client's player/pet/vehicle
--- rule; `legacyFlag` is AuraData.isFromPlayerOrPlayerPet, which Classic
--- clients populate unreliably and so defaults to nil.
function World.Aura(fields)
    World.nextID = World.nextID + 1
    fields.id = World.nextID
    fields.duration = fields.duration or 30
    if fields.fromPlayer == nil then
        fields.fromPlayer = PLAYER_SOURCES[fields.source] == true
    end
    return fields
end

function World.Set(unit, records)
    World.units[unit] = records
    World.slotCalls = {}
    World.indexFilters = {}
end

function World.Matches(record, filter)
    local helpful, harmful = false, false
    for token in string.gmatch(filter, "[^|]+") do
        if token == "HELPFUL" then
            helpful = true
        elseif token == "HARMFUL" then
            harmful = true
        elseif token == "PLAYER" then
            if record.fromPlayer ~= true then return false end
        elseif token == "RAID" then
            if World.era then
                -- Classic Era: HARMFUL|RAID returns the debuffs this player can cure.
                if not (record.harmful and record.dispel and World.removable[record.dispel]) then
                    return false
                end
            elseif not (record.harmful and record.dispel) then
                return false
            end
        elseif token == "RAID_PLAYER_DISPELLABLE" then
            -- Classic Era does not honour this token: its scans come back empty.
            if World.era then return false end
            if not (record.harmful and record.dispel and World.removable[record.dispel]) then
                return false
            end
        else
            World.unknownFilters[#World.unknownFilters + 1] = filter
            return false
        end
    end
    if helpful == harmful then
        World.unknownFilters[#World.unknownFilters + 1] = filter
        return false
    end
    return harmful == (record.harmful == true)
end

function World.Data(record)
    return {
        auraInstanceID = record.id,
        spellId = record.id + 800000,
        name = "Aura " .. record.id,
        icon = 134400,
        applications = 1,
        duration = record.duration,
        expirationTime = record.duration > 0 and (100 + record.duration) or 0,
        isHelpful = record.harmful ~= true,
        isHarmful = record.harmful == true,
        dispelName = record.dispel,
        sourceUnit = record.source,
        isFromPlayerOrPlayerPet = record.legacyFlag,
    }
end

function World.SlotFilters(unit)
    local seen = {}
    for i = 1, #World.slotCalls do
        local call = World.slotCalls[i]
        if call.unit == unit then seen[call.filter] = call.maxCount or true end
    end
    return seen
end

_G.C_UnitAuras = {
    GetAuraSlots = function(unit, filter, maxCount, continuation)
        World.slotCalls[#World.slotCalls + 1] = { unit = unit, filter = filter, maxCount = maxCount }
        local list, out = World.units[unit] or {}, {}
        for i = tonumber(continuation) or 1, #list do
            if World.Matches(list[i], filter) then
                if maxCount and #out >= maxCount then return i, unpack(out) end
                out[#out + 1] = i
            end
        end
        return nil, unpack(out)
    end,
    GetAuraDataBySlot = function(unit, slot)
        local record = (World.units[unit] or {})[slot]
        return record and World.Data(record) or nil
    end,
    GetAuraDataByIndex = function(unit, index, filter)
        World.indexFilters[#World.indexFilters + 1] = filter
        local matched = 0
        for _, record in ipairs(World.units[unit] or {}) do
            if World.Matches(record, filter) then
                matched = matched + 1
                if matched == index then return World.Data(record) end
            end
        end
        return nil
    end,
}
_G.AuraUtil = {}
_G.C_Timer = {}
_G.GameTooltip = nil
_G.UnitExists = function() return true end
_G.UnitIsUnit = function(left, right) return left == right end
_G.GetTime = function() return 100 end
_G.InCombatLockdown = function() return false end
_G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"

-- Widgets -------------------------------------------------------------------

local Widget = {}
Widget.__index = Widget
for _, name in ipairs({
    "ClearAllPoints", "SetAllPoints", "SetAlpha", "EnableMouse", "SetDrawSwipe",
    "SetHideCountdownNumbers", "SetSwipeColor", "SetDrawEdge", "SetTexCoord", "SetFont",
    "SetTextColor", "SetShadowOffset", "SetDesaturated", "SetJustifyH", "SetJustifyV",
    "SetBlendMode", "SetPoint", "SetSize", "SetWidth", "SetHeight", "SetTexture", "SetText",
    "SetCooldown", "SetCooldownFromDurationObject", "Clear", "SetMinMaxValues", "SetValue",
    "SetStatusBarTexture", "SetStatusBarColor", "SetColorTexture", "SetReverse",
    "SetMouseClickEnabled", "SetMouseMotionEnabled", "SetCountdownMillisecondsThreshold",
    "SetAtlas", "SetVertexColor", "RegisterEvent", "UnregisterEvent", "SetFrameStrata",
}) do
    Widget[name] = function() end
end
function Widget:Show() self._shown = true end
function Widget:Hide() self._shown = false end
function Widget:SetShown(shown) self._shown = shown == true end
function Widget:IsShown() return self._shown == true end
function Widget:IsVisible() return self._shown == true end
function Widget:IsForbidden() return false end
function Widget:SetParent(parent) self._parent = parent end
function Widget:GetParent() return self._parent end
function Widget:GetFrameLevel() return self._frameLevel or 1 end
function Widget:SetFrameLevel(level) self._frameLevel = level end
function Widget:SetScript(name, handler) self._scripts = self._scripts or {}; self._scripts[name] = handler end
function Widget:HookScript(name, handler) self:SetScript(name, handler) end
function Widget:CreateTexture() return setmetatable({ _shown = true, _parent = self }, Widget) end
function Widget:CreateMaskTexture() return self:CreateTexture() end
function Widget:CreateFontString() return setmetatable({ _shown = true, _parent = self }, Widget) end
function Widget:GetObjectType() return self._objectType or "Frame" end
_G.CreateFrame = function(frameType, _, parent)
    return setmetatable({ _shown = true, _parent = parent, _objectType = frameType }, Widget)
end

-- Boot ----------------------------------------------------------------------

--- Load the real Classic aura chain into a fresh namespace. The shared Auras3
--- core is replaced by the two helpers the runtime needs from it; neither
--- takes part in filtering.
local function Boot(withFeatures, client)
    local element
    local namespace = {
        Client = client or { IsClassic = true },
        MSUF_Auras3 = {},
        UF = {
            elements = {},
            RegisterElement = function(name, registered)
                assert(name == "Auras", "unexpected element registration: " .. tostring(name))
                element = registered
            end,
        },
        ExportPublic = function(name, value)
            _G[name] = value
            return value
        end,
    }
    local A3 = namespace.MSUF_Auras3
    A3._unitFrameOwners = {}
    A3.BumpRuntimeConfig = function()
        A3._runtimeConfigGen = (A3._runtimeConfigGen or 1) + 1
        return A3._runtimeConfigGen
    end
    A3.SetUnitFrameOwner = function(unit, frame, owns)
        A3._unitFrameOwners[unit] = owns and frame or nil
    end
    _G.MSUF_NS, _G.MSUF = namespace, namespace
    local base = root .. "/MidnightSimpleUnitFrames/Game/Classic/Auras/"
    if withFeatures then
        assert(loadfile(base .. "MSUF_Auras3_Features.lua"))("MidnightSimpleUnitFrames", namespace)
    end
    assert(loadfile(base .. "MSUF_Auras3_Compile.lua"))("MidnightSimpleUnitFrames", namespace)
    assert(loadfile(base .. "MSUF_Auras3_UnitFrames.lua"))("MidnightSimpleUnitFrames", namespace)
    Check(element, "Classic aura element did not register")
    Check(type(A3._ClassicCompile) == "table", "Classic compile exports missing")
    Check((A3.ClassicFeatures ~= nil) == (withFeatures == true), "Classic feature compiler presence mismatch")
    return A3, element
end

--- Target-unit Aura profile. `icons = false` turns the aura icons off, so a
--- dispel border alone decides whether the frame scans.
local function SetTargetDB(options)
    _G.MSUF_DB = {
        auras3 = {
            enabled = true,
            showPlayer = false,
            showTarget = options.icons ~= false,
            shared = {},
            perUnit = {
                target = {
                    layout = {},
                    layoutShared = {
                        showBuffs = true,
                        showDebuffs = true,
                        buffSortMethod = options.buffSort,
                        debuffSortMethod = options.debuffSort,
                    },
                    filters = {
                        buffs = options.buffFilters or {},
                        debuffs = options.debuffFilters or {},
                    },
                },
            },
        },
    }
end

local function NewFrame(unit, spec)
    return setmetatable({
        _shown = true,
        MSUFUnitKey = unit,
        MSUFSpec = spec or {},
        _msufActiveElements = { Auras = true },
    }, Widget)
end

local function EnableFrame(element, frame)
    element.Create(frame)
    Check(element.Enable(frame) == true, "Classic aura element did not enable for " .. tostring(frame.MSUFUnitKey))
    return frame
end

local function IDs(...)
    local list = { ... }
    table.sort(list)
    return table.concat(list, ",")
end

local function ActiveIDs(frame, kind)
    local lane = frame._msufA3State and frame._msufA3State.lanes[kind]
    local list = {}
    for id, active in pairs(lane and lane.active or {}) do
        if active == true then list[#list + 1] = id end
    end
    table.sort(list)
    return table.concat(list, ","), lane
end

local function ExpectVisible(frame, kind, expected, label)
    local actual, lane = ActiveIDs(frame, kind)
    Check(actual == expected, label .. ": " .. kind .. " lane showed {" .. actual .. "}, expected {" .. expected .. "}")
    local count = expected == "" and 0 or select(2, expected:gsub(",", ",")) + 1
    Check(lane and lane.visible == count,
        label .. ": " .. kind .. " lane rendered " .. tostring(lane and lane.visible) .. " buttons, expected " .. count)
end

local function ExpectBorder(frame, active, token, label)
    Check(frame._msufA3DispelActive == active,
        label .. ": dispel border active=" .. tostring(frame._msufA3DispelActive) .. ", expected " .. tostring(active))
    if active then
        Check(frame._msufA3DispelToken == token,
            label .. ": dispel border lit for aura " .. tostring(frame._msufA3DispelToken) .. ", expected " .. tostring(token))
    end
end

local function ExpectNoUnknownFilters(label)
    Check(#World.unknownFilters == 0,
        label .. ": the compiler handed C_UnitAuras an unsupported filter: " .. tostring(World.unknownFilters[1]))
end

local CLASSES = {
    { name = "PRIEST", removable = { Magic = true, Disease = true } },
    { name = "MAGE", removable = { Curse = true } },
    { name = "DRUID", removable = { Curse = true, Poison = true } },
    { name = "PALADIN", removable = { Magic = true, Poison = true, Disease = true } },
    { name = "SHAMAN", removable = { Poison = true, Disease = true } },
    { name = "WARRIOR", removable = {} },
}
local DISPEL_TYPES = { "Magic", "Curse", "Poison", "Disease" }

local A3, element = Boot(true)
local Compile = A3._ClassicCompile

-- 1. Dispel trigger normalisation and the direct-visual filter strings -------
do
    local direct = Compile.DirectVisualFilterForTrigger
    Check(direct("PLAYER_CAST") == "HARMFUL|PLAYER", "PLAYER_CAST no longer queries the player's own debuffs")
    Check(direct("BY_ME") == "HARMFUL|RAID_PLAYER_DISPELLABLE", "BY_ME no longer queries debuffs this player can dispel")
    Check(direct("DISPEL_TYPE") == "HARMFUL|RAID", "DISPEL_TYPE no longer queries typed debuffs")
    Check(direct("ANY_DEBUFF") == nil and direct("BORDER") == nil and direct(nil) == nil,
        "a trigger without a native filter was given a direct-visual query")

    local aliases = {
        PLAYER_CAST = { "PLAYER_CAST", "CAST_BY_ME", "MY_DEBUFF", "player_cast" },
        BY_ME = { "BY_ME", "PLAYER", "DISPELLABLE_BY_ME", "unknown-trigger" },
        DISPEL_TYPE = { "DISPEL_TYPE", "TYPE", "ANY_DISPEL_TYPE" },
        ANY_DEBUFF = { "ANY_DEBUFF", "DEBUFF", "ANY", "ALL_DEBUFFS" },
    }
    for expected, names in pairs(aliases) do
        for _, name in ipairs(names) do
            local visual = Check(Compile.CompileFrameAuraVisual({ border = { dispel = true, dispelTrigger = name } }),
                "dispel border visual did not compile for trigger " .. name)
            Check(visual.borderTrigger == expected,
                "trigger " .. name .. " compiled to " .. tostring(visual.borderTrigger) .. ", expected " .. expected)
            Check(visual.directVisualEligible == (expected ~= "ANY_DEBUFF"),
                "trigger " .. name .. " has the wrong direct-visual eligibility")
            Check(visual.needsPlayerFlag == (expected == "PLAYER_CAST"),
                "trigger " .. name .. " has the wrong player-ownership requirement")
        end
    end
    Check(Compile.CompileFrameAuraVisual({ border = { dispel = true } }).borderTrigger == "BY_ME",
        "a missing dispel trigger no longer defaults to BY_ME")
    local inherited = Compile.CompileFrameAuraVisual({
        border = { dispel = true, dispelTrigger = "PLAYER_CAST" },
        dispelOverlay = { enabled = true, trigger = "BORDER" },
    })
    Check(inherited.overlayTrigger == "PLAYER_CAST", "the dispel overlay no longer inherits the border trigger")
    Check(Compile.CompileFrameAuraVisual({ border = { dispel = false } }) == nil,
        "a disabled dispel border still compiled a scan")
end

-- 2. Unit lane compilation: Only mine, Hide permanent, buff vs debuff -------
do
    local BASE = { buff = "HELPFUL", debuff = "HARMFUL" }
    for _, onlyMine in ipairs({ false, true }) do
        for _, hidePermanent in ipairs({ false, true }) do
            SetTargetDB({
                buffFilters = { onlyMine = onlyMine, hidePermanent = hidePermanent },
                debuffFilters = { onlyMine = onlyMine, hidePermanent = hidePermanent },
                buffSort = "INSTANCE_ID", debuffSort = "INSTANCE_ID",
            })
            local cfg = Check(A3.ResolveUnitFrameConfig("target", {}), "target aura config missing")
            for kind, base in pairs(BASE) do
                local label = kind .. " lane (onlyMine=" .. tostring(onlyMine) .. ", hidePermanent=" .. tostring(hidePermanent) .. ")"
                local lane = Check(cfg.lanes[kind], label .. " did not compile")
                Check(lane.harmful == (kind == "debuff"), label .. " has the wrong helpful/harmful side")
                Check(lane.filter == (onlyMine and (base .. "|PLAYER") or base),
                    label .. " scans with " .. tostring(lane.filter))
                Check(lane.playerFilter == base .. "|PLAYER", label .. " has the wrong ownership membership filter")
                Check(lane.dispellableFilter == "HARMFUL|RAID_PLAYER_DISPELLABLE",
                    label .. " has the wrong dispellable membership filter: " .. tostring(lane.dispellableFilter))
                Check(lane.onlyMine == onlyMine, label .. " lost its Only mine flag")
                Check(lane.nativePlayerFilter == onlyMine, label .. " has the wrong native PLAYER scan flag")
                Check((lane.filterRequirements and lane.filterRequirements.player == true or false) == onlyMine,
                    label .. " has the wrong ownership requirement")
                Check(lane.hasInclusive == onlyMine, label .. " has the wrong inclusive-filter flag")
                Check(lane.hidePermanent == hidePermanent, label .. " lost its Hide permanent flag")
                Check(lane.hasFilterWork == (onlyMine or hidePermanent), label .. " has the wrong filter-work flag")
                Check(lane.needsPlayerFlag == onlyMine, label .. " has the wrong ownership-resolution flag")
                Check(lane.naturalOrder == not onlyMine and lane.visibleOnlyScan == not onlyMine,
                    label .. " has the wrong scan ordering")
                Check(lane.cappedFilterScan == (hidePermanent and not onlyMine),
                    label .. " has the wrong capped-scan decision")
                Check(lane.exclusiveImportant == false and lane.onlyImportant == false and lane.raid == false
                    and lane.includeStealable == false and lane.boss == false and lane.raidInCombat == false
                    and lane.maxDuration == 0 and lane.needsCombatRefresh == false,
                    label .. " enabled a Retail-only filter Classic does not offer")
            end
        end
    end

    -- A disabled filter block keeps its stored Only mine value but applies none.
    SetTargetDB({
        buffFilters = { enabled = false, onlyMine = true, hidePermanent = false },
        debuffFilters = { enabled = false, onlyMine = true },
    })
    local cfg = A3.ResolveUnitFrameConfig("target", {})
    for kind, base in pairs(BASE) do
        local lane = cfg.lanes[kind]
        Check(lane.filter == base and lane.onlyMine == false and lane.hasInclusive == false
            and lane.hasFilterWork == false and lane.filterRequirements == nil,
            kind .. " lane applied Only mine from a disabled filter block")
    end
end

-- 3. Unit lane visibility with the feature compiler (native PLAYER scans) ---
do
    local own = World.Aura({ source = "player" })
    local pet = World.Aura({ source = "pet" })
    local vehicle = World.Aura({ source = "vehicle" })
    local foreign = World.Aura({ source = "party2", legacyFlag = false })
    local unknown = World.Aura({})
    local ownPermanent = World.Aura({ source = "player", duration = 0 })
    local debuffOwn = World.Aura({ harmful = true, source = "player" })
    local debuffPet = World.Aura({ harmful = true, source = "pet" })
    local debuffForeign = World.Aura({ harmful = true, source = "party2", dispel = "Magic" })
    local debuffForeignPermanent = World.Aura({ harmful = true, source = "party2", duration = 0 })
    local records = { own, debuffOwn, pet, foreign, debuffPet, vehicle, debuffForeign, unknown,
        ownPermanent, debuffForeignPermanent }

    local cases = {
        { onlyMine = false, hidePermanent = false,
          buff = IDs(own.id, pet.id, vehicle.id, foreign.id, unknown.id, ownPermanent.id),
          debuff = IDs(debuffOwn.id, debuffPet.id, debuffForeign.id, debuffForeignPermanent.id) },
        { onlyMine = true, hidePermanent = false,
          buff = IDs(own.id, pet.id, vehicle.id, ownPermanent.id),
          debuff = IDs(debuffOwn.id, debuffPet.id) },
        { onlyMine = false, hidePermanent = true,
          buff = IDs(own.id, pet.id, vehicle.id, foreign.id, unknown.id),
          debuff = IDs(debuffOwn.id, debuffPet.id, debuffForeign.id) },
        { onlyMine = true, hidePermanent = true,
          buff = IDs(own.id, pet.id, vehicle.id),
          debuff = IDs(debuffOwn.id, debuffPet.id) },
    }
    for _, case in ipairs(cases) do
        local label = "unit target (onlyMine=" .. tostring(case.onlyMine) .. ", hidePermanent=" .. tostring(case.hidePermanent) .. ")"
        SetTargetDB({
            buffFilters = { onlyMine = case.onlyMine, hidePermanent = case.hidePermanent },
            debuffFilters = { onlyMine = case.onlyMine, hidePermanent = case.hidePermanent },
        })
        World.Set("target", records)
        local frame = EnableFrame(element, NewFrame("target"))
        ExpectVisible(frame, "buff", case.buff, label)
        ExpectVisible(frame, "debuff", case.debuff, label)
        local filters = World.SlotFilters("target")
        if case.onlyMine then
            Check(filters["HELPFUL|PLAYER"] and filters["HARMFUL|PLAYER"],
                label .. ": Only mine lanes did not scan with the native PLAYER filter")
            Check(not filters.HELPFUL and not filters.HARMFUL,
                label .. ": an Only mine lane still scanned every aura")
        else
            -- A PLAYER query may still appear here: the default player-first
            -- order resolves ownership of an aura without a public caster
            -- through that membership filter. The lane scan itself is plain.
            Check(filters.HELPFUL and filters.HARMFUL,
                label .. ": an unfiltered lane did not scan with its plain base filter")
        end
        ExpectNoUnknownFilters(label)
    end

    -- UNIT_AURA additions are not pre-filtered by the client. Only mine must test
    -- their PLAYER membership instead of trusting the payload.
    SetTargetDB({ buffFilters = { onlyMine = true }, debuffFilters = { onlyMine = true } })
    World.Set("target", records)
    local frame = EnableFrame(element, NewFrame("target"))
    local lateForeign = World.Aura({ source = "party3", legacyFlag = true, fromPlayer = false })
    local lateOwn = World.Aura({ legacyFlag = false, fromPlayer = true })
    records[#records + 1] = lateForeign
    records[#records + 1] = lateOwn
    element.Update(frame, "UNIT_AURA", "target", { addedAuras = { World.Data(lateForeign), World.Data(lateOwn) } })
    ExpectVisible(frame, "buff", IDs(own.id, pet.id, vehicle.id, ownPermanent.id, lateOwn.id),
        "unit target Only mine delta")
    records[#records] = nil
    records[#records] = nil
end

-- 4. Only mine without the feature compiler (ownership resolved per aura) ---
do
    local fallbackA3, fallbackElement = Boot(false)
    local own = World.Aura({ source = "player" })
    local pet = World.Aura({ source = "pet" })
    local vehicle = World.Aura({ source = "vehicle" })
    local foreign = World.Aura({ source = "party2", legacyFlag = false })
    local unknown = World.Aura({})
    local legacyOwn = World.Aura({ legacyFlag = true })
    local ownPermanent = World.Aura({ source = "player", duration = 0 })
    local debuffOwn = World.Aura({ harmful = true, source = "player" })
    local debuffForeign = World.Aura({ harmful = true, source = "party2" })
    local records = { foreign, own, debuffForeign, pet, unknown, debuffOwn, vehicle, legacyOwn, ownPermanent }

    -- The default player-first sort resolves ownership on its own, which would
    -- mask a lane that lost Only mine's ownership request. The ID sort does
    -- not, so there Only mine alone must make the runtime resolve each caster.
    local cases = {
        { onlyMine = false }, { onlyMine = true },
        { onlyMine = false, sort = "INSTANCE_ID" }, { onlyMine = true, sort = "INSTANCE_ID" },
    }
    for _, case in ipairs(cases) do
        local onlyMine = case.onlyMine
        local label = "fallback target (onlyMine=" .. tostring(onlyMine) .. ", sort=" .. (case.sort or "default") .. ")"
        SetTargetDB({
            buffFilters = { onlyMine = onlyMine }, debuffFilters = { onlyMine = onlyMine },
            buffSort = case.sort, debuffSort = case.sort,
        })
        World.Set("target", records)
        local cfg = fallbackA3.ResolveUnitFrameConfig("target", {})
        Check(cfg.lanes.buff.filter == "HELPFUL" and cfg.lanes.debuff.filter == "HARMFUL",
            label .. ": lanes without the feature compiler must scan with the base filter")
        Check(cfg.lanes.buff.onlyMine == onlyMine and cfg.lanes.buff.hasInclusive == onlyMine
            and cfg.lanes.debuff.hasInclusive == onlyMine,
            label .. ": Only mine did not compile into an inclusive lane")
        if case.sort then
            Check(cfg.lanes.buff.needsPlayerFlag == onlyMine and cfg.lanes.debuff.needsPlayerFlag == onlyMine,
                label .. ": Only mine did not request per-aura ownership resolution")
        end
        local frame = EnableFrame(fallbackElement, NewFrame("target"))
        if onlyMine then
            ExpectVisible(frame, "buff", IDs(own.id, pet.id, vehicle.id, legacyOwn.id, ownPermanent.id), label)
            ExpectVisible(frame, "debuff", IDs(debuffOwn.id), label)
        else
            ExpectVisible(frame, "buff",
                IDs(own.id, pet.id, vehicle.id, foreign.id, unknown.id, legacyOwn.id, ownPermanent.id), label)
            ExpectVisible(frame, "debuff", IDs(debuffOwn.id, debuffForeign.id), label)
        end
        ExpectNoUnknownFilters(label)
    end
end

-- 5. Dispel border with aura icons off (direct visual queries) --------------
do
    local helpfulOwn = World.Aura({ source = "player" })
    local untypedForeign = World.Aura({ harmful = true, source = "party2" })
    local magicForeign = World.Aura({ harmful = true, source = "party2", dispel = "Magic" })
    local debuffOwn = World.Aura({ harmful = true, source = "player" })
    local curse = World.Aura({ harmful = true, source = "party2", dispel = "Curse" })
    local poison = World.Aura({ harmful = true, source = "party2", dispel = "Poison" })
    local disease = World.Aura({ harmful = true, source = "party2", dispel = "Disease" })
    local byType = { Magic = magicForeign, Curse = curse, Poison = poison, Disease = disease }
    local ordered = { helpfulOwn, untypedForeign, magicForeign, debuffOwn, curse, poison, disease }

    local function DirectFrame(border, overlay)
        SetTargetDB({ icons = false })
        local frame = NewFrame("target", { border = border, dispelOverlay = overlay })
        local cfg = A3.ResolveUnitFrameConfig("target", frame.MSUFSpec)
        Check(cfg.visualDirect == true, "an icon-less " .. tostring(border.dispelTrigger)
            .. " border did not compile to a direct visual query")
        return EnableFrame(element, frame)
    end

    local function ExpectOnlyIndexFilter(filter, label)
        Check(#World.indexFilters > 0, label .. ": the direct visual never queried C_UnitAuras")
        for i = 1, #World.indexFilters do
            Check(World.indexFilters[i] == filter,
                label .. ": direct visual queried " .. tostring(World.indexFilters[i]) .. ", expected " .. filter)
        end
        Check(#World.slotCalls == 0, label .. ": a direct-visual frame still ran a lane scan")
    end

    World.removable = CLASSES[1].removable
    World.Set("target", ordered)
    local frame = DirectFrame({ dispel = true, dispelTrigger = "PLAYER_CAST" })
    ExpectBorder(frame, true, debuffOwn.id, "direct PLAYER_CAST")
    ExpectOnlyIndexFilter("HARMFUL|PLAYER", "direct PLAYER_CAST")

    World.Set("target", { helpfulOwn, untypedForeign, magicForeign, curse })
    frame = DirectFrame({ dispel = true, dispelTrigger = "PLAYER_CAST" })
    ExpectBorder(frame, false, nil, "direct PLAYER_CAST without an own debuff")

    World.Set("target", ordered)
    frame = DirectFrame({ dispel = true, dispelTrigger = "DISPEL_TYPE" })
    ExpectBorder(frame, true, magicForeign.id, "direct DISPEL_TYPE")
    ExpectOnlyIndexFilter("HARMFUL|RAID", "direct DISPEL_TYPE")

    World.Set("target", { helpfulOwn, untypedForeign, debuffOwn })
    frame = DirectFrame({ dispel = true, dispelTrigger = "DISPEL_TYPE" })
    ExpectBorder(frame, false, nil, "direct DISPEL_TYPE without a typed debuff")

    for _, class in ipairs(CLASSES) do
        World.removable = class.removable
        local expected
        for i = 1, #ordered do
            local record = ordered[i]
            if not expected and record.harmful and record.dispel and class.removable[record.dispel] then
                expected = record
            end
        end
        World.Set("target", ordered)
        frame = DirectFrame({ dispel = true, dispelTrigger = "BY_ME" })
        ExpectBorder(frame, expected ~= nil, expected and expected.id, "direct BY_ME for " .. class.name)
        ExpectOnlyIndexFilter("HARMFUL|RAID_PLAYER_DISPELLABLE", "direct BY_ME for " .. class.name)
        for _, dispelType in ipairs(DISPEL_TYPES) do
            local label = "direct BY_ME " .. dispelType .. " debuff for " .. class.name
            World.Set("target", { helpfulOwn, untypedForeign, byType[dispelType] })
            frame = DirectFrame({ dispel = true, dispelTrigger = "BY_ME" })
            ExpectBorder(frame, class.removable[dispelType] == true, byType[dispelType].id, label)
        end
    end

    -- Border and overlay with different triggers query separately.
    World.removable = CLASSES[1].removable
    World.Set("target", ordered)
    frame = DirectFrame({ dispel = true, dispelTrigger = "PLAYER_CAST" }, { enabled = true, trigger = "BY_ME" })
    ExpectBorder(frame, true, debuffOwn.id, "direct border PLAYER_CAST with BY_ME overlay")
    Check(frame._msufA3DispelOverlayActive == true and frame._msufA3DispelOverlayToken == magicForeign.id,
        "direct BY_ME overlay did not light for the dispellable debuff")

    -- ANY_DEBUFF has no native query: an icon-less border scans the debuff lane.
    World.Set("target", ordered)
    SetTargetDB({ icons = false })
    frame = NewFrame("target", { border = { dispel = true, dispelTrigger = "ANY_DEBUFF" } })
    Check(A3.ResolveUnitFrameConfig("target", frame.MSUFSpec).visualDirect ~= true,
        "an ANY_DEBUFF border compiled to a direct query it cannot express")
    EnableFrame(element, frame)
    ExpectBorder(frame, true, untypedForeign.id, "icon-less ANY_DEBUFF border")
    Check(World.SlotFilters("target").HARMFUL, "icon-less ANY_DEBUFF border did not scan harmful auras")
    World.Set("target", { helpfulOwn })
    frame = EnableFrame(element, NewFrame("target", { border = { dispel = true, dispelTrigger = "ANY_DEBUFF" } }))
    ExpectBorder(frame, false, nil, "icon-less ANY_DEBUFF border without debuffs")
    ExpectNoUnknownFilters("direct dispel visuals")
end

-- 6. Dispel border evaluated over a filtered debuff lane --------------------
do
    local untypedForeign = World.Aura({ harmful = true, source = "party2" })
    local debuffOwn = World.Aura({ harmful = true, source = "player" })
    local debuffPet = World.Aura({ harmful = true, source = "pet" })
    local byType, permanentByType = {}, {}
    for _, dispelType in ipairs(DISPEL_TYPES) do
        byType[dispelType] = World.Aura({ harmful = true, source = "party2", dispel = dispelType })
        permanentByType[dispelType] = World.Aura({ harmful = true, source = "party2", dispel = dispelType, duration = 0 })
    end

    local function LaneFrame(trigger)
        -- Hide permanent is filter work, so the border is resolved from the
        -- lane's visible debuffs instead of a direct query. Instance-ID order
        -- leaves the trigger as the only reason to resolve aura ownership.
        SetTargetDB({ debuffFilters = { hidePermanent = true }, debuffSort = "INSTANCE_ID", buffSort = "INSTANCE_ID" })
        local frame = NewFrame("target", { border = { dispel = true, dispelTrigger = trigger } })
        local lane = A3.ResolveUnitFrameConfig("target", frame.MSUFSpec).lanes.debuff
        Check(lane.visualDirect == false, trigger .. " border over a filtered lane compiled to a direct query")
        Check(lane.needsPlayerFlag == (trigger == "PLAYER_CAST"),
            trigger .. " border over a filtered lane has the wrong ownership-resolution flag")
        return EnableFrame(element, frame)
    end

    for _, class in ipairs(CLASSES) do
        World.removable = class.removable
        for _, dispelType in ipairs(DISPEL_TYPES) do
            local label = "lane BY_ME " .. dispelType .. " debuff for " .. class.name
            World.Set("target", { untypedForeign, byType[dispelType] })
            local frame = LaneFrame("BY_ME")
            ExpectVisible(frame, "debuff", IDs(untypedForeign.id, byType[dispelType].id), label)
            ExpectBorder(frame, class.removable[dispelType] == true, byType[dispelType].id, label)
            Check(World.SlotFilters("target")["HARMFUL|RAID_PLAYER_DISPELLABLE"],
                label .. ": dispellable membership was not queried with the player-dispellable filter")

            label = "lane BY_ME hidden permanent " .. dispelType .. " debuff for " .. class.name
            World.Set("target", { untypedForeign, permanentByType[dispelType] })
            frame = LaneFrame("BY_ME")
            ExpectVisible(frame, "debuff", IDs(untypedForeign.id), label)
            ExpectBorder(frame, false, nil, label)
        end
    end

    World.removable = CLASSES[1].removable
    World.Set("target", { untypedForeign, byType.Magic, debuffOwn })
    local frame = LaneFrame("PLAYER_CAST")
    ExpectBorder(frame, true, debuffOwn.id, "lane PLAYER_CAST")
    World.Set("target", { untypedForeign, debuffPet })
    frame = LaneFrame("PLAYER_CAST")
    ExpectBorder(frame, true, debuffPet.id, "lane PLAYER_CAST from the player's pet")
    World.Set("target", { untypedForeign, byType.Magic })
    frame = LaneFrame("PLAYER_CAST")
    ExpectBorder(frame, false, nil, "lane PLAYER_CAST without an own debuff")

    World.Set("target", { untypedForeign, byType.Curse })
    frame = LaneFrame("DISPEL_TYPE")
    ExpectBorder(frame, true, byType.Curse.id, "lane DISPEL_TYPE")
    World.Set("target", { untypedForeign, debuffOwn })
    frame = LaneFrame("DISPEL_TYPE")
    ExpectBorder(frame, false, nil, "lane DISPEL_TYPE without a typed debuff")

    World.Set("target", { untypedForeign })
    frame = LaneFrame("ANY_DEBUFF")
    ExpectBorder(frame, true, untypedForeign.id, "lane ANY_DEBUFF")
    World.Set("target", { permanentByType.Magic })
    frame = LaneFrame("ANY_DEBUFF")
    ExpectBorder(frame, false, nil, "lane ANY_DEBUFF with only a hidden permanent debuff")
    ExpectNoUnknownFilters("lane dispel visuals")
end

-- 7. Group lanes: stored filter tokens, hide permanent, dispellable border --
do
    local buffOwn = World.Aura({ source = "player" })
    local buffPet = World.Aura({ source = "pet" })
    local buffForeign = World.Aura({ source = "party2", legacyFlag = false })
    local untypedForeign = World.Aura({ harmful = true, source = "party2" })
    local curse = World.Aura({ harmful = true, source = "party2", dispel = "Curse" })
    local magicPermanent = World.Aura({ harmful = true, source = "party2", dispel = "Magic", duration = 0 })
    local records = { buffForeign, untypedForeign, buffOwn, magicPermanent, buffPet, curse }

    local function GroupFrame()
        return NewFrame("party1", {
            scope = "group",
            border = { dispel = true, dispelTrigger = "BY_ME" },
            auras = {
                enabled = true,
                showBuffs = true, maxBuffs = 6, buffFilter = "HELPFUL|RAID|PLAYER",
                showDebuffs = true, maxDebuffs = 6, debuffFilter = "HARMFUL",
                debuffHidePermanent = true,
            },
        })
    end

    for _, class in ipairs(CLASSES) do
        World.removable = class.removable
        World.Set("party1", records)
        local frame = EnableFrame(element, GroupFrame())
        local cfg = Check(frame._msufA3GroupConfig, "group aura config missing")
        local buff, debuff = cfg.lanes.buff, cfg.lanes.debuff
        Check(buff.filter == "HELPFUL|PLAYER" and buff.nativePlayerFilter == true,
            "group buff lane did not reduce HELPFUL|RAID|PLAYER to a native PLAYER scan: " .. tostring(buff.filter))
        Check(debuff.filter == "HARMFUL" and debuff.hidePermanent == true and debuff.visualDirect == false,
            "group debuff lane lost its filter or Hide permanent setting")
        Check(buff.dispellableFilter == "HARMFUL|RAID_PLAYER_DISPELLABLE"
            and debuff.dispellableFilter == "HARMFUL|RAID_PLAYER_DISPELLABLE",
            "group lanes have the wrong dispellable membership filter: " .. tostring(debuff.dispellableFilter))
        local label = "group party1 for " .. class.name
        ExpectVisible(frame, "buff", IDs(buffOwn.id, buffPet.id), label)
        ExpectVisible(frame, "debuff", IDs(untypedForeign.id, curse.id), label)
        ExpectBorder(frame, class.removable.Curse == true, curse.id, label)
        ExpectNoUnknownFilters(label)
    end
end

-- 8. Classic Era: the dispellable filter follows MSUF.Client -----------------
-- Era keeps the original meaning of HARMFUL|RAID (debuffs this player can cure)
-- and does not honour RAID_PLAYER_DISPELLABLE, so a BY_ME border, overlay or
-- symbol compiled to the newer token stayed dark there for every class.
do
    local eraA3, eraElement = Boot(true, {
        IsClassic = true, IsVanilla = true, DispellableDebuffFilter = "HARMFUL|RAID",
    })
    World.era = true
    Check(eraA3._ClassicCompile.DirectVisualFilterForTrigger("BY_ME") == "HARMFUL|RAID",
        "Era BY_ME does not query HARMFUL|RAID")

    -- A stored "Dispellable by Group" debuff token matches through the Era filter.
    local plan = eraA3.ClassicFeatures.CompileRawFilter("HARMFUL|RAID_PLAYER_DISPELLABLE", false)
    local asked = {}
    eraA3.ClassicFeatures.MatchFilterRequirements(plan, "party1", { auraInstanceID = 1 }, function(_, _, filter)
        asked[#asked + 1] = filter
        return true
    end)
    Check(#asked == 1 and asked[1] == "HARMFUL|RAID",
        "Era Dispellable by Group token queried " .. tostring(asked[1]) .. " instead of HARMFUL|RAID")

    local untypedForeign = World.Aura({ harmful = true, source = "party2" })
    local curse = World.Aura({ harmful = true, source = "party2", dispel = "Curse" })
    local magic = World.Aura({ harmful = true, source = "party2", dispel = "Magic" })
    local records = { untypedForeign, curse, magic }
    for _, class in ipairs(CLASSES) do
        World.removable = class.removable
        local expected = class.removable.Curse and curse or (class.removable.Magic and magic) or nil

        World.Set("party1", records)
        local groupLabel = "Era group party1 for " .. class.name
        local group = EnableFrame(eraElement, NewFrame("party1", {
            scope = "group",
            border = { dispel = true, dispelTrigger = "BY_ME" },
            auras = { enabled = true, showBuffs = false, showDebuffs = true, maxDebuffs = 6, debuffFilter = "HARMFUL" },
        }))
        local cfg = Check(group._msufA3GroupConfig, groupLabel .. ": group aura config missing")
        Check(cfg.lanes.debuff.dispellableFilter == "HARMFUL|RAID",
            groupLabel .. ": debuff lane uses " .. tostring(cfg.lanes.debuff.dispellableFilter))
        ExpectBorder(group, expected ~= nil, expected and expected.id, groupLabel)
        ExpectNoUnknownFilters(groupLabel)

        World.Set("target", records)
        local directLabel = "Era direct BY_ME for " .. class.name
        SetTargetDB({ icons = false })
        local direct = NewFrame("target", { border = { dispel = true, dispelTrigger = "BY_ME" } })
        Check(eraA3.ResolveUnitFrameConfig("target", direct.MSUFSpec).visualDirect == true,
            directLabel .. ": an icon-less border did not compile to a direct visual query")
        EnableFrame(eraElement, direct)
        ExpectBorder(direct, expected ~= nil, expected and expected.id, directLabel)
        for i = 1, #World.indexFilters do
            Check(World.indexFilters[i] == "HARMFUL|RAID",
                directLabel .. ": queried " .. tostring(World.indexFilters[i]) .. ", expected HARMFUL|RAID")
        end
        ExpectNoUnknownFilters(directLabel)
    end
    World.era = nil
end

print("classic_aura_compile_filter_smoke: ok")
