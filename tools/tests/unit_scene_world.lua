-- unit_scene_world.lua -- a booted client with the unit-API spy and every unit-frame feature a scene could ask the client about.
--
-- Shared by the unit preview scene smokes. Boots one flavor's whole core load graph through
-- tools/tests/group_header_world.lua (the real group runtime on a SecureGroupHeader emulator) with:
--   * every unit-facing API the addon references wrapped before the addon loads, so a captured local is counted too;
--   * the class tables the portrait media catalogue reads at load (the sandbox has none);
--   * World:Enable(): every status, text, portrait, border and prediction feature that reads a unit on a live frame.
-- Every call counts while the spy is armed, except UnitClass("player") under the four named settings reads below. The
-- live runtime reacts to the same events with unit queries of its own, so a test arms the spy only around the scene's
-- own calls. Any other API, any other argument and any other caller counts.
--
-- Usage:
--   local World = dofile(root .. "/tools/tests/unit_scene_world.lua")
--   local w = World.New(root, flavor)   -- booted, logged in
--   w:Enable()                           -- features on, specs recompiled
--   w:Arm(); ...scene calls...; w:Disarm(); w:Violations()
--
-- Plain Lua 5.1.

local World = {}
local Methods = {}
Methods.__index = Methods

local WATCHED = { "^Unit", "^GetUnit", "^GetNumGroupMembers$", "^GetNumSubgroupMembers$", "^IsInGroup$", "^IsInRaid$",
    "^GetRaidRosterInfo$", "^GetSpecialization", "^C_UnitAuras$", "^GetRaidTargetIndex$", "^IsResting$",
    "^SetPortraitTexture$", "^GetReadyCheckStatus$", "^C_PlayerInfo$" }
local function Watched(name)
    if type(name) ~= "string" then return false end
    for _, pattern in ipairs(WATCHED) do if name:find(pattern) then return true end end
    return false
end

-- Every other unit-facing API the addon references: the sandbox answers those with a callable stub, which a file
-- captures as a local at load. A counting function takes its place (only where the client has the API).
local EXTRA_APIS = [[UnitHealth UnitHealthMax UnitHealthPercent UnitHealthMissing UnitPower UnitPowerMax UnitPowerPercent
    UnitPowerType UnitPowerDisplayMod UnitIsDeadOrGhost UnitIsDead UnitIsGhost UnitIsUnconscious UnitIsVisible
    UnitInRange UnitIsPlayer UnitIsUnit UnitIsFriend UnitIsEnemy UnitIsTapDenied UnitIsAFK UnitIsDND UnitIsPVP
    UnitIsPVPFreeForAll UnitIsGroupLeader UnitIsGroupAssistant UnitIsMercenary UnitInRaid UnitInOtherParty
    UnitHasVehicleUI UnitHasIncomingResurrection UnitCanAssist UnitCanAttack UnitReaction UnitThreatSituation
    UnitDetailedThreatSituation UnitGetTotalAbsorbs UnitGetTotalHealAbsorbs UnitGetIncomingHeals
    UnitGetDetailedHealPrediction UnitPhaseReason UnitChannelInfo UnitCastingInfo UnitCastingDuration
    UnitChannelDuration UnitClassification UnitFullName UnitSelectionColor UnitSelectionType UnitFactionGroup
    UnitRace UnitEffectiveLevel UnitPlayerControlled UnitPlayerOrPetInRaid UnitPlayerOrPetInParty UnitPosition
    UnitName UnitExists UnitLevel UnitClass UnitGUID UnitIsConnected UnitAffectingCombat UnitIsBossMob UnitIsLieutenant
    UnitHasPowerType UnitCreatureType UnitGroupRolesAssigned UnitHasLootRollPending UnitInPartyIsAI
    GetUnitTotalModifiedMaxHealthPercent GetPetHappiness HasPetUI GetPetExperience UnitThreatSituation
    GetRaidTargetIndex GetReadyCheckStatus GetSpecializationInfo GetUnitSpeed GetUnitChargedPowerPoints IsResting
    SetPortraitTexture]]

-- The reads of the local player's own class that are settings, not paint: the pet colour of the unit health compile, the
-- defensive spell hash of the Classic aura compile, the custom aura container compile and the class background's
-- once-per-session fallback token. Only UnitClass("player") under one of them is let through; `Direct` counts every call.
local SETTINGS_READS = { "'PlayerClassToken'", "'PlayerDefensiveHash'", "'CompileUnitCustomContainers'",
    "'_MSUF_GetPlayerClassToken'" }

-- A function, or a table the sandbox made callable (its stand-in for an API it does not model).
local function Callable(value)
    if type(value) == "function" then return true end
    local meta = type(value) == "table" and getmetatable(value)
    return type(meta) == "table" and meta.__call ~= nil
end
local NAMESPACES = { C_UnitAuras = true, C_PlayerInfo = true }

function World.New(root, flavor, options)
    options = options or {}
    local Harness = dofile(root .. "/tools/tests/group_header_world.lua")
    local w = setmetatable({ root = root, flavor = flavor, seen = {}, detail = {}, armed = false, direct = false,
        override = {} }, Methods)
    local function Record(name, first)
        if not (w.armed or w.direct) then return end
        local trace = debug.traceback("", 3)
        if not w.direct and name == "UnitClass" and first == "player" then
            for index = 1, #SETTINGS_READS do
                if trace:find(SETTINGS_READS[index], 1, true) then return end
            end
        end
        w.seen[#w.seen + 1] = name
        local frames = {}
        for line in trace:gmatch("[^\n]+") do
            local where = line:match("in function '([^']+)'") or line:match("in function <([^>]+)>")
            local ln = line:match("([%w_]+%.lua):(%d+):")
            if where then frames[#frames + 1] = where .. "@" .. (line:match("([%w_]+%.lua:%d+):") or "?") end
            if #frames == 5 then break end
        end
        w.detail[#w.detail + 1] = name .. " < " .. table.concat(frames, " < ")
    end
    w.Record = Record
    w.h = Harness.New(root, flavor, { beforeBoot = function(world)
        local env = world.env
        env.MAX_BOSS_FRAMES = 5
        -- One distinct colour and icon cell per class (the sandbox answers every class with the same stub).
        env.RAID_CLASS_COLORS, env.CLASS_ICON_TCOORDS = {}, {}
        for index, class in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN", "MAGE",
            "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER" }) do
            env.RAID_CLASS_COLORS[class] = { r = index / 20, g = 1 - index / 20, b = 0.5 }
            env.CLASS_ICON_TCOORDS[class] = { (index - 1) / 13, index / 13, 0, 1 }
        end
        -- The sandbox answers a number formatter with a stub table; the slot writers need strings.
        env.BreakUpLargeNumbers = function(value) return string.format("%d", math.floor(tonumber(value) or 0)) end
        local function Abbreviate(value)
            value = tonumber(value) or 0
            if value >= 1000000 then return string.format("%.1fM", value / 1000000) end
            if value >= 1000 then return string.format("%.1fK", value / 1000) end
            return string.format("%d", value)
        end
        env.AbbreviateNumbers, env.AbbreviateLargeNumbers = Abbreviate, Abbreviate
        -- The sandbox answers every curve constant with the same stub; the percent APIs tell the two apart.
        env.CurveConstants = { ScaleTo100 = { curve = "scale" }, ReverseTo100 = { curve = "reverse" } }
        -- WoW Forever reads the pet happiness from C_PetInfo; Classic from the global of the same name.
        env.C_PetInfo = { GetPetHappiness = function(...)
            Record("C_PetInfo.GetPetHappiness", ...)
            local replaced = w.override.GetPetHappiness
            if replaced then return replaced(...) end
        end }
        local wrapped, done = 0, {}
        for name, value in pairs(env) do
            if Watched(name) and type(value) == "function" then
                done[name] = true
                env[name] = function(...)
                    Record(name, ...)
                    local replaced = w.override[name]
                    if replaced then return replaced(...) end
                    return value(...)
                end
                wrapped = wrapped + 1
            end
        end
        local meta = getmetatable(env)
        for name in EXTRA_APIS:gmatch("%S+") do
            local current = rawget(env, name)
            local original = not done[name] and (type(current) == "function" and current or current == nil and meta.__index(env, name)) or nil
            if original ~= nil then
                env[name] = function(...)
                    Record(name, ...)
                    local replaced = w.override[name]
                    if replaced then return replaced(...) end
                    return original(...)
                end
                wrapped = wrapped + 1
            end
        end
        assert(wrapped >= 20, "the spy wrapped too few unit APIs (" .. wrapped .. "); the harness stubs moved")
        -- The two namespaces: every function they hold counts, the sandbox's stand-ins included.
        local fallback = meta.__index
        for namespace in pairs(NAMESPACES) do
            local target = rawget(env, namespace)
            if target == nil then target = fallback(env, namespace) end
            if target ~= nil then
                local counted = {}
                env[namespace] = setmetatable({}, { __index = function(_, key)
                    local value = target[key]
                    if not Callable(value) then return value end
                    local wrapper = counted[key]
                    if not wrapper then
                        wrapper = function(...) Record(namespace .. "." .. key, ...) return value(...) end
                        counted[key] = wrapper
                    end
                    return wrapper
                end })
            end
        end
        -- Any other unit API the sandbox has no entry for (UnitSex, UnitAura, a name nobody listed) answers through its
        -- fallback with one shared stand-in; a file that caches it as a local at load, or a call through _G, gets a
        -- counting function for that name instead.
        local lookups = {}
        meta.__index = function(table_, key)
            local value = fallback(table_, key)
            if value == nil or NAMESPACES[key] or not Watched(key) or not Callable(value) then return value end
            local wrapper = lookups[key]
            if not wrapper then
                wrapper = function(...)
                    Record(key, ...)
                    local replaced = w.override[key]
                    if replaced then return replaced(...) end
                    return value(...)
                end
                lookups[key] = wrapper
            end
            return wrapper
        end
        if options.beforeBoot then options.beforeBoot(world) end
    end })
    w.env, w.UF, w.GF = w.h.env, w.h.core.UF, w.h.GF
    return w
end

--- Every feature a unit scene paints turned on in the saved settings, then the live specs recompiled.
function Methods:Enable()
    local env, UF = self.env, self.UF
    self.GF.EnsureDB()
    local db = env.MSUF_DB
    local general = db.general
    general.nameClassColor, general.npcNameRed, general.nameNpcClassColor = true, true, true
    general.npcClassColorBar, general.colorHealthTextByHealth = true, true
    general.tempMaxHealthEnabled, general.overAbsorbOverlay = true, true
    general.stateIconsTestMode = false
    for _, key in ipairs({ "player", "target", "focus", "targettarget", "focustarget", "pet", "pettarget", "boss", "arena" }) do
        local conf = db[key]
        if type(conf) ~= "table" then conf = {} db[key] = conf end
        conf.enabled = true
        conf.showName, conf.showHP, conf.showPower, conf.showPowerBar, conf.showPowerText = true, true, true, true, true
        conf.textLeft, conf.textCenter, conf.textRight = "PERCENT", "CURRENT", "CURPERCENT"
        conf.powerTextLeft, conf.powerTextRight = "CURRENT", "PERCENT"
        for _, flag in ipairs({ "showLevelIndicator", "showRaceIndicator", "showClassTextIndicator", "showRaidGroupInName",
            "showEliteIcon", "showCombatStateIndicator", "showRestingIndicator", "showPvpIndicator", "showBossNumberIndicator",
            "showStanceIndicator", "showIncomingResIndicator", "showLeaderIcon", "showRaidMarker", "showPetHappinessIndicator",
            "showThreatIndicator" }) do
            conf[flag] = true
        end
        conf.portraitMode = "LEFT"
        conf.portraitRender = "2D"
        conf.portraitBorderStyle = "CLASS_COLOR"
        conf.statusDeadTextEnabled, conf.statusGhostTextEnabled = true, true
        -- Unified opacity with the out-of-combat fade on: the fade registry and its combat driver are live state.
        conf.hpBarAlpha, conf.oocFadeEnabled, conf.oocFadeAlpha = 0.6, true, 0.5
    end
    -- The aura lanes of every unit (the player and the focus are off by default).
    local auras = env.MSUF.MSUF_Auras3.EnsureDB()
    auras.enabled = true
    for _, flag in ipairs({ "showPlayer", "showTarget", "showFocus", "showPet", "showBoss", "showArena" }) do auras[flag] = true end
    env.MSUF.MSUF_Auras3.InvalidateUnitRuntimeConfig(nil)
    -- The target frame's inline target-of-target name, in the frame's own colour.
    local tot = db.targettarget
    tot.showToTInTargetName, tot.totInlineColorMode = true, "DEFAULT"
    UF.Config.Refresh()
end

--- The client answers for `unit` from a sample (the same table a scene paints): every unit API the live paint reaches.
--- Returns nothing; `Methods:Unmodel()` removes the answers.
function Methods:Model(unit, sample, hpMax)
    local o = self.override
    hpMax = hpMax or self.UF.UnitScene.HEALTH_MAX
    local reaction = ({ friendly = 5, neutral = 4, enemy = 2 })[sample.reaction or "friendly"]
    -- A dependent unit (target of target, pet target) exists only while its parent does.
    local parent = self.UF.ParentUnitForDependentUnit and self.UF.ParentUnitForDependentUnit(unit)
    local function Is(u) return u == unit end
    local hp = math.floor(hpMax * sample.hp + 0.5)
    local powerMax = sample.powerMax or 100
    local power = math.floor(powerMax * sample.power + 0.5)
    -- The target frame also names its target's target inline.
    local inline = unit == "target" and sample.inline and "targettarget" or nil
    o.UnitExists = function(u) return Is(u) or u == parent or u == inline end
    o.UnitIsConnected = function() return true end
    o.UnitIsDeadOrGhost = function() return false end
    o.UnitIsDead = function() return false end
    o.UnitIsGhost = function() return false end
    o.UnitName = function(u)
        if Is(u) then return sample.name end
        if u == inline then return sample.inline end
    end
    o.UnitClass = function(u) if Is(u) then return sample.class, sample.class, 1 end end
    o.UnitIsPlayer = function(u) return Is(u) and sample.player == true end
    o.UnitLevel = function(u) if Is(u) then return sample.level end end
    o.UnitEffectiveLevel = o.UnitLevel
    o.UnitReaction = function() return reaction end
    o.UnitHealth = function() return hp end
    o.UnitHealthMax = function() return hpMax end
    o.UnitHealthPercent = function(_, _, curve)
        local pct = hp * 100 / hpMax
        local reverse = self.env.CurveConstants and self.env.CurveConstants.ReverseTo100
        if curve ~= nil and curve == reverse then return 100 - pct end
        if curve == nil then return pct / 100 end
        return pct
    end
    o.UnitPower = function() return power end
    o.UnitPowerMax = function() return powerMax end
    o.UnitPowerType = function() return sample.powerType, sample.powerToken end
    o.UnitPowerPercent = function(_, _, _, curve)
        if curve == nil then return power / powerMax end
        return power * 100 / powerMax
    end
    o.UnitClassification = function() return sample.classification or "normal" end
    o.GetRaidTargetIndex = function() return sample.raidTarget end
    o.UnitInRaid = function(u) if Is(u) and sample.raidGroup then return 1 end end
    o.GetRaidRosterInfo = function() return sample.name, 0, sample.raidGroup end
    o.UnitIsGroupLeader = function() return sample.leader == true end
    o.UnitIsGroupAssistant = function() return false end
    o.UnitAffectingCombat = function() return sample.combat == true end
    o.IsResting = function() return sample.resting == true end
    o.UnitIsPVP = function() return sample.pvp ~= nil end
    o.UnitIsPVPFreeForAll = function() return sample.pvp == "FFA" end
    o.UnitFactionGroup = function() if sample.pvp == "Alliance" or sample.pvp == "Horde" then return sample.pvp end end
    o.UnitRace = function() return sample.race, sample.race end
    o.UnitGUID = function(u) if Is(u) then return "Creature-0-" .. unit end end
    o.UnitGetTotalAbsorbs = function() return math.floor(hpMax * (sample.absorb or 0) + 0.5) end
    o.UnitGetIncomingHeals = function() return math.floor(hpMax * (sample.incoming or 0) + 0.5) end
    o.UnitGetTotalHealAbsorbs = function() return math.floor(hpMax * (sample.healAbsorb or 0) + 0.5) end
    o.UnitCanAttack = function() return sample.reaction == "enemy" end
    o.UnitCanAssist = function() return sample.reaction ~= "enemy" end
    o.UnitSelectionColor = function() return 1, 1, 0 end
    o.UnitPlayerControlled = function() return sample.player == true end
    o.UnitIsTapDenied = function() return false end
    o.GetUnitTotalModifiedMaxHealthPercent = function() return sample.reducedMax or 0 end
    -- The sample modes of the Classic and Forever extras: what the engine shows in its own test mode.
    o.UnitDetailedThreatSituation = function() return true, 3, 85, 85, 1000 end
    o.GetPetHappiness = function() return 3 end
    o.HasPetUI = function() return true, true end
    o.GetPetExperience = function() return 68, 100 end
end

function Methods:Unmodel()
    for key in pairs(self.override) do self.override[key] = nil end
end

--- A live unit frame of `unit` built the way the factory builds one (attach, apply the compiled spec, runtime update),
--- over the client model of `sample`, applying the elements a scene paints. The sandbox spawns no real unit frame.
function Methods:LiveFrame(unit, sample, name, register)
    local env, UF = self.env, self.UF
    self:Model(unit, sample)
    local live = env.CreateFrame("Button", name or ("MSUF_Live_" .. unit), env.UIParent)
    if register then UF.frames[unit] = live end
    live.MSUFUnitKey = unit
    UF.Config.Refresh()
    UF.AttachFrame(live, { scope = "single" })
    if UF.EnsureHealthVisualRoot then UF.EnsureHealthVisualRoot(live) end
    local spec = UF.Config.GetSpec(unit)
    live:SetSize(spec.width, spec.height)
    local mask = {}
    for _, element in ipairs(UF.UnitScene.ELEMENTS) do mask[element] = true end
    UF.ApplySpec(live, spec, "MSUF_APPLY", mask)
    UF.FrameRuntimeUpdate(live, "MSUF_FORCE_UPDATE")
    env.MSUF.UFStatusRuntime.UpdateBossNumber(live, spec.status)
    -- Later-registered elements (the Classic threat text) build regions after the first opacity pass; the next opacity
    -- update of a live frame settles them, so the twin starts from the settled state.
    UF.elements.Alpha.Update(live, "MSUF_ALPHA")
    return live
end

function Methods:Arm() self.armed = true end
function Methods:Disarm() self.armed = false end
--- Count every call, whatever is on the stack: the test is calling an engine entry point itself.
function Methods:Direct(on) self.direct = on and true or false end

function Methods:Reset()
    self.seen, self.detail = {}, {}
end

--- The unit APIs called since the last Reset: nil when there were none, else a short description.
function Methods:Violations()
    if #self.seen == 0 then return nil end
    local counts, order = {}, {}
    for _, line in ipairs(self.detail) do
        if not counts[line] then counts[line] = 0 order[#order + 1] = line end
        counts[line] = counts[line] + 1
    end
    local out = {}
    for index = 1, math.min(#order, 6) do out[#out + 1] = counts[order[index]] .. "x " .. order[index] end
    return table.concat(out, " | ")
end

--- Who holds a scene frame. Walks everything reachable from the sandbox (globals, tables, metatables, functions through
--- their upvalues, widgets through their children and regions) and returns the first path to any object in `targets`
--- that does not pass through an object in `allowed` (the scene itself, its root and the pools it owns). nil: nothing
--- outside the scene knows the targets, so no registry, route, timer, driver or cache of the engine holds them.
function Methods:Holders(targets, allowed)
    local seen, queue, head = {}, {}, 1
    -- The sandbox's own bookkeeping lists every widget it ever made; that is not addon state.
    allowed[self.h.widgets.frames], allowed[self.h.widgets.frameMeta] = true, true
    local function Visit(value, path)
        local kind = type(value)
        if kind ~= "table" and kind ~= "function" and kind ~= "userdata" then return end
        if seen[value] or allowed[value] then return end
        seen[value] = true
        queue[#queue + 1] = { value, path }
    end
    Visit(self.env, "env")
    Visit(self.h.world, "world")
    local found
    while head <= #queue do
        local item = table.remove(queue, 1)
        local value, path = item[1], item[2]
        if targets[value] then return path .. "  [reached " .. tostring(value) .. "]" end
        if type(value) == "table" then
            local meta = getmetatable(value)
            if type(meta) == "table" then Visit(meta, path .. ".<meta>") end
            for key, child in next, value do
                if type(key) == "table" or type(key) == "function" then
                    if targets[key] then return path .. ".<key>  [reached a target as a key]" end
                    Visit(key, path .. ".<key>")
                end
                local label = type(key) == "string" and key or type(key) == "number" and ("[" .. key .. "]") or "?"
                Visit(child, path .. "." .. label)
            end
        elseif type(value) == "function" then
            local index = 1
            while true do
                local name, upvalue = debug.getupvalue(value, index)
                if not name then break end
                Visit(upvalue, path .. ".<up:" .. name .. ">")
                index = index + 1
            end
            local environment = getfenv and getfenv(value)
            if environment then Visit(environment, path .. ".<fenv>") end
        end
    end
    return found
end

-- What a region draws; bookkeeping (dispatch tokens, caches, serials) is not part of it.
local VISUAL_FIELDS = { "objectType", "shown", "alpha", "width", "height", "scale", "frameLevel", "frameStrata", "drawLayer",
    "text", "texture", "atlas", "value", "minimum", "maximum", "justifyH", "blendMode", "fontSize", "fontPath" }
local VISUAL_TUPLES = { "color", "vertexColor", "textColor", "texCoord", "colorTexture", "shadowColor" }

--- Everything a frame and its regions currently draw, as one string: two digests are equal exactly when the frame looks
--- the same.
function World.Digest(frame)
    local parts = {}
    local function Visit(region, path)
        for _, key in ipairs(VISUAL_FIELDS) do
            local value = rawget(region, key)
            if value ~= nil then parts[#parts + 1] = path .. "." .. key .. "=" .. tostring(value) end
        end
        for _, key in ipairs(VISUAL_TUPLES) do
            local tuple = rawget(region, key)
            if type(tuple) == "table" then
                parts[#parts + 1] = path .. "." .. key .. "=" .. tostring(tuple[1]) .. "," .. tostring(tuple[2]) .. ","
                    .. tostring(tuple[3]) .. "," .. tostring(tuple[4])
            end
        end
        local points = rawget(region, "points")
        if type(points) == "table" then
            for index, point in ipairs(points) do
                parts[#parts + 1] = path .. ".pt" .. index .. "=" .. tostring(point.point) .. tostring(point.relativePoint)
                    .. tostring(point.x) .. "," .. tostring(point.y)
            end
        end
        for index, child in ipairs(region.children or {}) do Visit(child, path .. "/c" .. index) end
        for index, sub in ipairs(region.regions or {}) do Visit(sub, path .. "/r" .. index) end
    end
    Visit(frame, "frame")
    return table.concat(parts, string.char(10))
end

return World
