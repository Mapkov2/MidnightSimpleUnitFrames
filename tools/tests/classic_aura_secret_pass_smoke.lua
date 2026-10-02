-- classic_aura_secret_pass_smoke.lua <repoRoot>
--
-- Strict secret pass over the Classic aura backend (Game/Classic/Auras). The
-- shared aura stubs model a secret as a plain table, which type() calls
-- "table" and comparisons ignore, so a guard that only checks type() or a
-- comparison of a secret never fails offline. This smoke uses the
-- client-strict helper (tools/tests/classpower_secrets.lua): type() answers
-- the secret's kind, and arithmetic, ordering, concatenation, length,
-- indexing and calls raise, while a line watcher records every executed line
-- that compares a local holding a secret or truth-tests it with `not`.
--
-- Every AuraData field the backend can read is a secret except
-- auraInstanceID, as for a restricted unit on 12.x; so are the documented
-- secret unit answers (UnitIsUnit, UnitGUID, UnitClass, UnitInRange; see
-- Blizzard_APIDocumentationGenerated/UnitDocumentation.lua, upstream/live)
-- and C_UnitAuras.GetAuraApplicationDisplayCount. The scenario renders unit,
-- group and custom-container lanes through full scans, UNIT_AURA deltas, an
-- identity change, the combat edges and the menu's apply and preview entry
-- points, once per watched file.
local root = assert(arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")
local ADDON = root .. "/MidnightSimpleUnitFrames/"
local Secrets = assert(loadfile(root .. "/tools/tests/classpower_secrets.lua"))()
--- The chunk name the manifest loader gives a file (tools/tests/client_manifest.lua
--- normalizes "." and ".." away), so the line watcher matches the loaded chunk.
local function ChunkPath(relative)
    local path = root .. "/MidnightSimpleUnitFrames/" .. relative
    local parts = {}
    for part in path:gsub("\\", "/"):gmatch("[^/]+") do
        if part == ".." then table.remove(parts) elseif part ~= "." then parts[#parts + 1] = part end
    end
    return (path:sub(1, 1) == "/" and "/" or "") .. table.concat(parts, "/")
end
local rawtype = type

-- The files the line watcher covers, each in its own run.
local WATCHED = {
    "Game/Classic/Auras/MSUF_Auras3_DataShared.lua", "Game/Classic/Auras/MSUF_Auras3_Visuals.lua",
    "Game/Classic/Auras/MSUF_Auras3_Features.lua", "Game/Classic/Auras/MSUF_Auras3_Compile.lua",
    "Game/Classic/Auras/MSUF_Auras3_Buttons.lua", "Game/Classic/Auras/MSUF_Auras3_Filters.lua",
    "Game/Classic/Auras/MSUF_Auras3_FrameVisuals.lua", "Game/Classic/Auras/MSUF_Auras3_Lanes.lua",
    "Game/Classic/Auras/MSUF_Auras3_UnitFrames.lua", "Game/Classic/Auras/MSUF_Auras3_Requests.lua",
    "Game/Classic/Auras/MSUF_Auras3_Preview.lua",
}
local CHAIN = {
    "Auras3/MSUF_Auras3_Core.lua", "Auras3/MSUF_Auras3_IconShape.lua", "Game/Classic/Auras/MSUF_Auras3_DataShared.lua",
    "Game/Vanilla/Auras/MSUF_Auras3_DotData.lua", "Game/Vanilla/Auras/MSUF_Auras3_DefensiveData.lua",
    "Game/Classic/Auras/MSUF_Auras3_Visuals.lua", "Game/Classic/Auras/MSUF_Auras3_Features.lua",
    "Game/Classic/Auras/MSUF_Auras3_Compile.lua",
    "Game/Classic/Auras/MSUF_Auras3_Buttons.lua", "Game/Classic/Auras/MSUF_Auras3_Filters.lua",
    "Game/Classic/Auras/MSUF_Auras3_FrameVisuals.lua", "Game/Classic/Auras/MSUF_Auras3_Lanes.lua",
    "Game/Classic/Auras/MSUF_Auras3_UnitFrames.lua", "Game/Classic/Auras/MSUF_Auras3_Requests.lua",
    "Game/Classic/Auras/MSUF_Auras3_Preview.lua",
}

-- Widgets. Setters are C sinks: they take secrets and keep them.
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
function Widget:GetFrameLevel() return self._frameLevel or 1 end
function Widget:SetFrameLevel(level) self._frameLevel = level end
function Widget:GetFrameStrata() return "MEDIUM" end
function Widget:SetScript(name, handler) self._scripts = self._scripts or {}; self._scripts[name] = handler end
function Widget:GetScript(name) return self._scripts and self._scripts[name] end
function Widget:HookScript(name, handler)
    self._scripts = self._scripts or {}
    local previous = self._scripts[name]
    self._scripts[name] = previous and function(...) previous(...); handler(...) end or handler
end
function Widget:GetNumRegions() return 0 end
function Widget:GetRegions() return nil end
function Widget:GetObjectType() return self._objectType or "Frame" end
function Widget:GetWidth() return 24 end
function Widget:GetHeight() return 24 end
function Widget:GetStringWidth() return 10 end
function Widget:CreateTexture() return setmetatable({ _shown = true, _parent = self }, Widget) end
Widget.CreateMaskTexture = Widget.CreateTexture
Widget.CreateFontString = Widget.CreateTexture
for _, name in ipairs({
    "RegisterEvent", "UnregisterEvent", "RegisterUnitEvent", "UnregisterAllEvents", "ClearAllPoints", "SetAllPoints",
    "SetAlpha", "EnableMouse", "SetPoint", "SetSize", "SetWidth", "SetHeight", "SetDrawSwipe", "SetDrawBling",
    "SetHideCountdownNumbers", "SetSwipeColor", "SetDrawEdge", "SetTexCoord", "SetFont", "SetTextColor",
    "SetShadowOffset", "SetShadowColor", "SetDesaturated", "SetJustifyH", "SetJustifyV", "SetBlendMode",
    "SetMinMaxValues", "SetValue", "SetStatusBarTexture", "SetStatusBarColor", "SetColorTexture", "SetReverse",
    "SetMouseClickEnabled", "SetMouseMotionEnabled", "SetCountdownMillisecondsThreshold", "SetSwipeTexture",
    "SetFrameStrata", "SetOwner", "SetCooldown", "Clear", "SetAtlas", "AddMaskTexture", "RemoveMaskTexture",
    "SetTexture", "SetText", "SetFormattedText", "SetVertexColor", "SetDrawLayer", "SetUnitAura", "AddLine",
    "SetCooldownTextColor", "SetIgnoreParentAlpha", "SetPropagateMouseClicks", "SetPropagateMouseMotion",
    "SetWordWrap", "SetNonSpaceWrap", "SetMaxLines", "SetToplevel", "SetClipsChildren", "SetScale",
    "SetTimerDuration", "SetSmoothing",
}) do Widget[name] = function() end end

-- The secret world.
local world = {}
local function AuraList(unit) world[unit] = world[unit] or {}; return world[unit] end
local function Secret(kind) return Secrets.New(kind) end
local nextID = 7000
--- An AuraData whose readable fields are all secrets except auraInstanceID.
--- `helpful` and `mine` stay plain on hidden keys for the stub's filters.
local function SecretAura(helpful, mine)
    nextID = nextID + 1
    return {
        auraInstanceID = nextID, _helpful = helpful, _mine = mine == true,
        spellId = Secret("number"), name = Secret("string"), icon = Secret("number"),
        applications = Secret("number"), duration = Secret("number"), expirationTime = Secret("number"),
        dispelName = Secret("string"), sourceUnit = Secret("string"), isFromPlayerOrPlayerPet = Secret("boolean"),
        isHelpful = Secret("boolean"), isHarmful = Secret("boolean"), isStealable = Secret("boolean"),
        canApplyAura = Secret("boolean"), isBossAura = Secret("boolean"), isRaid = Secret("boolean"),
        nameplateShowAll = Secret("boolean"), nameplateShowPersonal = Secret("boolean"),
        timeMod = Secret("number"), charges = Secret("number"), maxCharges = Secret("number"),
    }
end
local function Matches(aura, filter)
    if filter:find("HARMFUL", 1, true) then
        if aura._helpful then return false end
    elseif not aura._helpful then
        return false
    end
    if filter:find("PLAYER", 1, true) and not filter:find("DISPELLABLE", 1, true) and not aura._mine then return false end
    return true
end

local function InstallClient()
    _G.GetTime = function() return 50 end
    _G.InCombatLockdown = function() return false end
    _G.UnitExists = function() return true end
    _G.UnitIsUnit = function(a, b)
        if a == b then return true end
        return Secret("boolean")
    end
    _G.UnitGUID = function() return Secret("string") end
    _G.UnitClass = function() return Secret("string"), Secret("string"), Secret("number") end
    _G.UnitInRange = function() return Secret("boolean"), Secret("boolean") end
    _G.UnitCanAssist = function() return true end
    _G.UnitIsPlayer = function() return true end
    _G.UnitPlayerOrPetInParty = function() return false end
    _G.UnitPlayerOrPetInRaid = function() return false end
    _G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
    _G.GameTooltip = setmetatable({}, Widget)
    _G.C_Timer = { After = function(_, fn) fn() end, NewTimer = function() return { Cancel = function() end } end }
    _G.CreateFrame = function(frameType, _, parent)
        return setmetatable({ _shown = true, _parent = parent, _objectType = frameType }, Widget)
    end
    _G.UIParent = setmetatable({ _shown = true }, Widget)
    _G.DebuffTypeColor = { Magic = { r = 0.2, g = 0.6, b = 1, a = 1 }, none = { r = 0.8, g = 0, b = 0, a = 1 } }
    -- Spell queries take secret arguments (SecretArguments = AllowedWhenTainted)
    -- and answer a secret for one; a configured plain spell ID gets a plain answer.
    local function SpellAnswer(plain, kind)
        return function(spellID)
            if Secrets.IsSecret(spellID) then return Secret(kind) end
            return plain
        end
    end
    _G.C_Spell = {
        GetSpellName = SpellAnswer("Spell", "string"),
        IsSpellImportant = SpellAnswer(false, "boolean"),
        IsExternalDefensive = SpellAnswer(false, "boolean"),
    }
    _G.C_UnitAuras = {
        GetAuraSlots = function(unit, filter)
            local list, out = AuraList(unit), {}
            for i = 1, #list do if Matches(list[i], filter) then out[#out + 1] = i end end
            return nil, unpack(out)
        end,
        GetAuraDataBySlot = function(unit, slot) return AuraList(unit)[slot] end,
        GetAuraDataByAuraInstanceID = function(unit, id)
            local list = AuraList(unit)
            for i = 1, #list do if list[i].auraInstanceID == id then return list[i] end end
        end,
        GetAuraDataByIndex = function(unit, index, filter)
            local n, list = 0, AuraList(unit)
            for i = 1, #list do
                if Matches(list[i], filter) then n = n + 1; if n == index then return list[i] end end
            end
        end,
        GetUnitAuraInstanceIDs = function(unit, filter)
            local list, out = AuraList(unit), {}
            for i = 1, #list do if Matches(list[i], filter) then out[#out + 1] = list[i].auraInstanceID end end
            return out
        end,
        IsAuraFilteredOutByInstanceID = function(unit, id, filter)
            local list = AuraList(unit)
            for i = 1, #list do if list[i].auraInstanceID == id then return not Matches(list[i], filter) end end
            return true
        end,
        GetAuraApplicationDisplayCount = function() return Secret("string") end,
        GetAuraDuration = function()
            return { IsZero = function() return Secret("boolean") end }
        end,
    }
    _G.AuraUtil = {}
end

local PROFILE_LAYOUT = {
    showBuffs = true, showDebuffs = true, buffShowCooldownText = true, buffShowStackCount = true,
    debuffShowCooldownText = true, debuffShowStackCount = true, debuffTypeBorderMode = "SYMBOL",
    buffShowDurationBar = true, buffDurationBarDisplay = "OVERLAY", buffShowStealable = true,
}
local function Profile(sortMethod, onlyMine)
    local layoutShared = {}
    for key, value in pairs(PROFILE_LAYOUT) do layoutShared[key] = value end
    layoutShared.buffSortMethod, layoutShared.debuffSortMethod = sortMethod, sortMethod
    local filters = { buffs = { enabled = true, onlyMine = onlyMine == true }, debuffs = { enabled = true } }
    return {
        general = { aurasCooldownTextUseBuckets = true, aurasCooldownTextSafeSeconds = 60,
            aurasCooldownTextWarningSeconds = 15, aurasCooldownTextUrgentSeconds = 5 },
        auras3 = {
            enabled = true, showPlayer = true, showTarget = true, showFocus = true,
            shared = { appearanceIconShapes = { buff = "CIRCLE", debuff = "RECTANGLE" },
                appearanceIconStyles = { buff = { styleBorderEnabled = true, styleShadowEnabled = true } } },
            perUnit = {
                target = { layout = {}, layoutShared = layoutShared, filters = filters },
                player = { layout = {}, layoutShared = layoutShared, filters = filters },
                focus = { layout = {}, layoutShared = { showBuffs = false, showDebuffs = false }, filters = {} },
            },
            customContainers = { perUnit = {
                focus = { items = { [1] = { enabled = true, auraType = "BUFF", spellIDs = "880001 880002",
                    placed = { size = 20, max = 4, perRow = 4, sortMethod = "TIME_REMAINING" } } } },
                target = { items = { [4] = { enabled = true, targetDots = true, auraType = "DEBUFF", spellIDs = "880003",
                    customSpellIDs = { [880003] = true }, placed = { size = 22, max = 2 } } } },
                player = { items = { [4] = { enabled = true, playerDefensives = true, spellIDs = "880004",
                    placed = { size = 24, max = 2 } } } },
            } },
        },
    }
end

--- One run: load the chain with strict secrets, watch one file, play the scenario.
local function Run(watchedPath)
    for unit in pairs(world) do world[unit] = nil end
    local registered
    local namespace = {
        Client = { IsClassic = true, IsVanilla = true, Flavor = "Vanilla", DispellableDebuffFilter = "HARMFUL|RAID" },
        MSUF_Auras3 = {},
        UF = {
            RegisterElement = function(_, element) registered = element end, Config = { serial = 1 },
            frames = {}, ForEachFrame = function() end,
            ApplyElementToFrame = function(frame, _, spec)
                if spec then frame.MSUFSpec = spec end
                if registered.Enable(frame) == false then registered.Disable(frame) end
                return true
            end,
        },
        GF = {
            ForEachFrame = function() return false end, FrameForUnit = function() end,
            RefreshVisuals = function() end, RefreshPreviewLayout = function() end, CompileSpec = function(_, f) return f.MSUFSpec end,
            DIRTY_AURAS = 0x40, _previewFrames = {},
        },
        ExportPublic = function(name, value) _G[name] = value; return value end,
        MSUF_CreateCanonicalPlayerDefensiveAuraContainer = function() return { name = "Defensive Buffs", placed = {} } end,
        MSUF_CreateCanonicalUnitAuras = function() return {} end,
        MSUF_MaterializeUnitAuraLaneOwners = function() end,
        -- Castbars/MSUF_Castbars_Core.lua publishes the font settings; aura harnesses keep the defaults.
        MSUF_GetGlobalFontSettings = function() end,
        -- The load-on-demand Options addon is not loaded: optional lookups find nothing.
        Optional = function() return nil end,
    }
    _G.MSUF_NS, _G.MSUF = namespace, namespace
    _G.MSUF_DB = Profile("DEFAULT", false)
    _G.MSUF_MAX_ARENA_FRAMES = 0
    Secrets.Install()
    InstallClient()
    local manifest = assert(loadfile(root .. "/tools/tests/client_manifest.lua"))()
    manifest.LoadSelected(root, "Vanilla", namespace, CHAIN)
    local A3 = namespace.MSUF_Auras3
    assert(registered, "Classic aura element did not register")

    local stop = Secrets.Watch(ChunkPath(watchedPath))
    local failures = {}
    local function Step(label, fn, ...)
        local ok, message = pcall(fn, ...)
        if not ok then failures[#failures + 1] = label .. ": " .. tostring(message) end
    end
    local function NewFrame(unit, spec, fields)
        local frame = setmetatable({ _shown = true, MSUFUnitKey = unit, _msufActiveElements = { Auras = true },
            MSUFSpec = spec or {} }, Widget)
        for key, value in pairs(fields or {}) do frame[key] = value end
        namespace.UF.frames[unit] = frame
        Step(unit .. " create", registered.Create, frame)
        return frame
    end
    local function Event(frame, event, payload)
        Step(frame.MSUFUnitKey .. " " .. event, registered.Update, frame, event, frame.MSUFUnitKey, payload)
    end

    for _, unit in ipairs({ "target", "player", "focus", "party1" }) do
        local list = AuraList(unit)
        for i = 1, 3 do list[#list + 1] = SecretAura(true, i == 1) end
        for i = 1, 3 do list[#list + 1] = SecretAura(false, i == 1) end
        -- A readable caster with a restricted unit comparison: the Only Mine
        -- membership asks UnitIsUnit, whose answer is secret.
        local foreign = SecretAura(true, false)
        foreign.sourceUnit, foreign.isFromPlayerOrPlayerPet = "party2", false
        list[#list + 1] = foreign
    end
    local target = NewFrame("target")
    local player = NewFrame("player")
    local focus = NewFrame("focus")
    local party = NewFrame("party1", { scope = "group", auras = {
        enabled = true, showBuffs = true, maxBuffs = 4, buffFilter = "HELPFUL|RAID", buffHidePermanent = true,
        showDebuffs = true, maxDebuffs = 4, debuffFilter = "HARMFUL", debuffHidePermanent = true,
        showExternals = true, maxExternals = 2,
    } }, { _msufGFKind = "party", _msufIsGroupFrame = true })

    for _, sortMethod in ipairs({ "DEFAULT", "EXPIRATION", "DURATION", "NAME", "TIME_REMAINING" }) do
        _G.MSUF_DB = Profile(sortMethod, sortMethod == "EXPIRATION")
        Step("bump " .. sortMethod, A3.BumpRuntimeConfig)
        for _, frame in ipairs({ target, player, focus, party }) do
            Step(frame.MSUFUnitKey .. " enable " .. sortMethod, registered.Enable, frame)
            Event(frame, "UNIT_AURA", { isFullUpdate = true })
            local list = AuraList(frame.MSUFUnitKey)
            local added = SecretAura(true, true)
            list[#list + 1] = added
            Event(frame, "UNIT_AURA", { addedAuras = { added } })
            Event(frame, "UNIT_AURA", { updatedAuraInstanceIDs = { list[1].auraInstanceID, added.auraInstanceID } })
            table.remove(list, 2)
            Event(frame, "UNIT_AURA", { removedAuraInstanceIDs = { list[1].auraInstanceID - 1 + 1 } })
        end
    end
    Event(target, "MSUF_UNIT_IDENTITY_AURAS")
    Event(target, "PLAYER_TARGET_CHANGED")
    Event(party, "PLAYER_REGEN_DISABLED")
    Event(party, "PLAYER_REGEN_ENABLED")
    Event(party, "GROUP_ROSTER_UPDATE")
    Event(player, "WEAPON_ENCHANT_CHANGED")
    Event(target, "ForceUpdate")
    Step("request target", A3.RequestScope, "target", "secret-pass")
    Step("request all", A3.RequestApply)
    Step("fonts", A3.ApplyFontsFromGlobal)
    Step("preview config", A3.ResolveAuraPreviewConfig, target, "target")
    Step("preview metrics", A3.BuildAuraLaneMetrics, "target", "buff")
    Step("preview party", A3.ResolveAuraPreviewConfig, party, "party1", party.MSUFSpec)
    -- The scenario reached the renderer: every unit lane holds secret auras.
    for _, frame in ipairs({ target, player, party }) do
        local state = frame._msufA3State
        local lanes = state and state.lanes
        if not (lanes and lanes.buff and (lanes.buff.visible or 0) > 0) then
            failures[#failures + 1] = frame.MSUFUnitKey .. ": the buff lane rendered no secret aura"
        end
    end
    Step("disable", registered.Disable, target)

    local violations = stop()
    _G.type = rawtype
    return failures, violations
end

local allFailures, allViolations, seen = {}, {}, {}
for _, path in ipairs(WATCHED) do
    local failures, violations = Run(path)
    for _, failure in ipairs(failures) do
        if not seen[failure] then seen[failure] = true; allFailures[#allFailures + 1] = failure end
    end
    for _, violation in ipairs(violations) do allViolations[#allViolations + 1] = violation end
end
local report = {}
for _, failure in ipairs(allFailures) do report[#report + 1] = "raised: " .. failure end
for _, violation in ipairs(allViolations) do report[#report + 1] = "watched: " .. violation end
if #report > 0 then
    error("Classic aura backend mishandles secret aura data:\n  " .. table.concat(report, "\n  "), 0)
end
print(("classic_aura_secret_pass_smoke: ok (%d watched files)"):format(#WATCHED))
