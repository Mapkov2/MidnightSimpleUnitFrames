-- group_preview_scene_lifecycle_smoke.lua <repoRoot> [flavor]
--
-- The preview scene root is a preview kit host (MSUF_UF_PreviewKit.lua). Pins that a root
--   * shows and listens to nothing until Activate, and nothing again after Deactivate;
--   * subscribes CONFIG_APPLIED and PLAYER_REGEN_ENABLED only while active;
--   * answers a burst of signals with one coalesced repaint, and defers it through combat;
--   * brings its groups back after combat, and forgets a group the owner hid on purpose;
--   * shows its static sample state, whatever the shared preview animation does;
--   * paints static sample data: not one unit, roster or aura-of-a-unit API is called.
-- Every unit-facing API the harness models is wrapped before boot, so a captured local is counted too.
-- Boots the real group runtime through group_header_world.lua. Plain Lua 5.1.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")

local function Check(condition, message)
    if not condition then error("group_preview_scene_lifecycle_smoke " .. flavor .. ": " .. message, 2) end
end

---------------------------------------------------------------------------
-- The unit-API spy, installed before the addon loads.
---------------------------------------------------------------------------
local WATCHED = { "^Unit", "^GetUnit", "^GetNumGroupMembers$", "^GetNumSubgroupMembers$", "^IsInGroup$", "^IsInRaid$",
    "^GetRaidRosterInfo$", "^GetSpecialization", "^C_UnitAuras$" }
local function Watched(name)
    if type(name) ~= "string" then return false end
    for _, pattern in ipairs(WATCHED) do if name:find(pattern) then return true end end
    return false
end
-- A call counts when the preview code is on the stack: the live group runtime reacts to the same events
-- (a config signal, combat) with unit queries of its own, and those are not the scene's. Spec compilation is the
-- one exception that stays on the list of calls to ignore: it is the settings pass every live group frame shares
-- (the player's class selects the spell-indicator specs), runs once per configuration revision and paints nothing.
-- `direct` counts every call: the test is calling an engine entry point itself, so the preview code is not on the stack.
local armed, direct, seen, detail = false, false, {}, {}
local function Record(name)
    if not (armed or direct) then return end
    local trace = debug.traceback("", 3)
    if direct or ((trace:find("MSUF_UF_Group_Preview", 1, true) or trace:find("MSUF_UF_PreviewKit", 1, true))
        and not (trace:find("'CompileSpecUncached'", 1, true) or trace:find("'CompileGroupLane'", 1, true))) then
        seen[#seen + 1] = name
        -- The nearest frames name the caller: the engine function that asked, then the preview function behind it.
        local frames = {}
        for line in trace:gmatch("[^\n]+") do
            local where = line:match("in function '([^']+)'") or line:match("in function <([^>]+)>")
            if where then frames[#frames + 1] = where end
            if #frames == 5 then break end
        end
        detail[#detail + 1] = name .. " < " .. table.concat(frames, " < ")
    end
end

local now = 0
local h = Harness.New(root, flavor, { beforeBoot = function(world)
    local env = world.env
    env.MAX_BOSS_FRAMES = 5
    -- One distinct colour per class (the sandbox answers every class with the same stub).
    -- The class icon table the portrait media catalogue reads at load is Blizzard's; the sandbox has none.
    env.RAID_CLASS_COLORS, env.CLASS_ICON_TCOORDS = {}, {}
    for index, class in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN", "MAGE",
        "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER" }) do
        env.RAID_CLASS_COLORS[class] = { r = index / 20, g = 1 - index / 20, b = 0.5 }
        env.CLASS_ICON_TCOORDS[class] = { (index - 1) / 13, index / 13, 0, 1 }
    end
    local wrapped = 0
    for name, value in pairs(env) do
        if Watched(name) and type(value) == "function" then
            env[name] = function(...) Record(name) return value(...) end
            wrapped = wrapped + 1
        end
    end
    Check(wrapped >= 8, "the spy wrapped too few unit APIs (" .. wrapped .. "); the harness stubs moved")
    -- Every other unit-facing API the addon references: the sandbox answers those with a callable stub, which a
    -- file captures as a local at load. Define a counting function in its place (only where the client has the API).
    local meta = getmetatable(env)
    for name in ([[UnitHealth UnitHealthMax UnitHealthPercent UnitHealthMissing UnitPower UnitPowerMax UnitPowerPercent
        UnitPowerType UnitPowerDisplayMod UnitIsDeadOrGhost UnitIsDead UnitIsGhost UnitIsUnconscious UnitIsVisible
        UnitInRange UnitIsPlayer UnitIsUnit UnitIsFriend UnitIsEnemy UnitIsTapDenied UnitIsAFK UnitIsDND UnitIsPVP
        UnitIsPVPFreeForAll UnitIsGroupLeader UnitIsGroupAssistant UnitIsMercenary UnitInRaid UnitInOtherParty
        UnitHasVehicleUI UnitHasIncomingResurrection UnitCanAssist UnitCanAttack UnitReaction UnitThreatSituation
        UnitDetailedThreatSituation UnitGetTotalAbsorbs UnitGetTotalHealAbsorbs UnitGetIncomingHeals
        UnitGetDetailedHealPrediction UnitPhaseReason UnitChannelInfo UnitCastingInfo UnitCastingDuration
        UnitChannelDuration UnitClassification UnitFullName UnitSelectionColor UnitSelectionType UnitFactionGroup
        UnitRace UnitEffectiveLevel UnitPlayerControlled UnitPlayerOrPetInRaid UnitPlayerOrPetInParty UnitPosition
        GetRaidTargetIndex GetReadyCheckStatus GetSpecializationInfo GetUnitSpeed GetUnitChargedPowerPoints
        SetPortraitTexture]]):gmatch("%S+") do
        if rawget(env, name) == nil then
            local original = meta.__index(env, name)
            if original ~= nil then
                env[name] = function(...) Record(name) return original(...) end
                wrapped = wrapped + 1
            end
        end
    end
    local auras = env.C_UnitAuras
    env.C_UnitAuras = setmetatable({}, { __index = function(_, key)
        local value = auras[key]
        if type(value) ~= "function" then return value end
        return function(...) Record("C_UnitAuras." .. key) return value(...) end
    end })
    -- A global read at call time ("_G.UnitLevel") reaches the sandbox fallback: count the lookup.
    local meta = getmetatable(env)
    local fallback = meta.__index
    meta.__index = function(table_, key)
        if Watched(key) then Record("lookup:" .. key) end
        return fallback(table_, key)
    end
end })
local GF, env = h.GF, h.env
env.GetTime = function() return now end
GF.EnsureDB()
env.MSUF2_GFPagePreviewActive = true

local party, raid = GF.GetConf("party"), GF.GetConf("raid")
party.enabled, raid.enabled = true, true
-- Every runtime that reads a unit when it is on: the status icons and texts, the level, the group number.
for _, key in ipairs({ "levelText", "roleIcon", "raidMarker", "leaderIcon", "assistIcon", "readyCheckIcon", "summonIcon",
    "resurrectIcon", "pvpIcon", "phaseIcon", "statusText", "statusGhostText", "statusAFKText", "statusAFKTimerText",
    "statusDNDText", "showGroupNumber" }) do
    party[key] = true
end
raid.levelText, raid.roleIcon, raid.showGroupNumber = true, true, true
-- Health text coloured by health reads the unit's health through a colour curve on a live frame.
env.MSUF_DB.general.colorHealthTextByHealth = true
-- Class and NPC name colours read the unit's identity on a live frame.
env.MSUF_DB.general.nameClassColor, env.MSUF_DB.general.npcNameRed, env.MSUF_DB.general.nameNpcClassColor = true, true, true
-- The features that are off by default and read the unit on a live frame.
for _, key in ipairs({ "tempMaxHealthEnabled", "dispelOverlayEnabled", "healthFadeEnabled", "offlineFadeEnabled", "deadBgEnabled",
    "nameBarEnabled", "hpAbsorbIcon", "focusIndicator" }) do
    party[key], raid[key] = true, true
end
party.portraitMode, party.portraitRender = "LEFT", "CLASS"
party.auras = party.auras or {}
party.auras.enabled, party.auras.renderer = true, "CUSTOM"
GF.InvalidateCompiledSpecs("party")
GF.InvalidateCompiledSpecs("raid")

local MSUF = assert(env.MSUF, "no MSUF namespace in the sandbox")
local Bus = assert(MSUF.EventBus, "no event bus")
local timers = h.widgets.timers

local function Queued()
    local count = 0
    for _, entry in ipairs(timers) do if not entry.cancelled then count = count + 1 end end
    return count
end
local function Subscribed(event, key)
    local ev = Bus.handlers[event]
    return ev ~= nil and ev.index[key] ~= nil
end
local function HpOf(frame)
    local bar = frame.hpBar or frame.Health or frame.health
    return bar and bar.value
end
local function Shown(group)
    local n = 0
    for _, frame in ipairs(group:Frames() or {}) do if frame:IsShown() then n = n + 1 end end
    return n
end
local function CountPaints(rootObject)
    local paints = { reasons = {} }
    local opts = rootObject.host.opts
    local original = opts.paint
    opts.paint = function(host, reason)
        paints[#paints + 1] = reason
        return original(host, reason)
    end
    return paints
end

h:RunTimers()
Check(Queued() == 0, "the timer queue was not idle before the test")

---------------------------------------------------------------------------
-- 1. A control for the spy: the on-screen dummies do ask the client who the player is.
---------------------------------------------------------------------------
armed = true
GF.ShowPreview("party", 3, { immediate = true })
h:RunTimers()
armed = false
local controlNames = {}
for _, name in ipairs(seen) do controlNames[name] = true end
Check(controlNames.UnitName == true and controlNames.UnitExists == true, "the spy missed the on-screen dummy's unit calls; it is blind")
Check(controlNames.UnitLevel == true, "the spy missed the on-screen dummy's level lookup; it is blind")
GF.HidePreview("party")
h:RunTimers()
seen, detail = {}, {}

---------------------------------------------------------------------------
-- 2. Inactive: nothing shows or listens.
---------------------------------------------------------------------------
armed = true
local host = env.CreateFrame("Frame", nil, env.UIParent)
host:SetSize(400, 300)
local rootA = GF.NewPreviewScene(host)
local key = rootA.eventKey
local groupA = rootA:Group("party", 4)
local groupRaid = rootA:Group("raid", 12)
Check(groupA and groupRaid and not rootA:IsActive(), "a new root is active")
Check(Shown(groupA) == 0 and not groupA:IsActive() and not groupRaid:IsActive(), "an inactive root showed a group")
Check(not Subscribed("CONFIG_APPLIED", key) and not Subscribed("PLAYER_REGEN_ENABLED", key), "an inactive root subscribed")
Check(rootA:Request("test") == false and Queued() == 0, "an inactive root queued a repaint")
Bus:Publish("CONFIG_APPLIED", "MSUF_Test")
Check(Queued() == 0, "a config signal reached an inactive root")

---------------------------------------------------------------------------
-- 3. Activate: groups show, signals are subscribed, one repaint per burst.
---------------------------------------------------------------------------
local paints = CountPaints(rootA)
Check(rootA:Activate() == true and rootA:IsActive(), "activate failed")
Check(rootA:Activate() == false, "a second activate did something")
h:RunTimers()
Check(groupA:IsActive() and Shown(groupA) == 4 and groupRaid:IsActive() and Shown(groupRaid) == 12, "activate did not show the wanted groups")
Check(#paints == 1 and paints[1] == "activate", "activate painted " .. #paints .. " times")
Check(Subscribed("CONFIG_APPLIED", key) and Subscribed("PLAYER_REGEN_ENABLED", key), "an active root did not subscribe")
-- Health text coloured by health follows each row's sample hp, never a unit.
do
    local colours, distinct = {}, 0
    for _, frame in ipairs(groupA:Frames()) do
        local key = tostring(frame._msufHealthTextR) .. "," .. tostring(frame._msufHealthTextG) .. "," .. tostring(frame._msufHealthTextB)
        if not colours[key] then colours[key] = true distinct = distinct + 1 end
    end
    Check(distinct >= 2, "health text coloured by health painted one colour for rows of different sample hp")
end
for _ = 1, 6 do Bus:Publish("CONFIG_APPLIED", "MSUF_Test") end
Check(Queued() == 1, "six config signals queued " .. Queued() .. " repaints, not one")
Check(#paints == 1, "a config signal painted before the next frame")
h:RunTimers()
Check(#paints == 2 and paints[2] == "config", "the coalesced repaint did not run once with its reason")
Check(Shown(groupA) == 4 and Shown(groupRaid) == 12, "the repaint changed what is shown")

---------------------------------------------------------------------------
-- 4. Combat: groups are hidden, the repaint waits, regen brings the wanted groups back.
---------------------------------------------------------------------------
-- The group runtime's PLAYER_REGEN_DISABLED handler calls GF.HidePreviewsForCombat; this world has no live header.
h:EnterCombat()
GF.HidePreviewsForCombat()
Check(not groupA:IsActive() and not groupRaid:IsActive(), "combat left a group active")
Check(rootA.host.active == true and groupA.want == 4 and groupRaid.want == 12, "combat made the root forget its groups")
local before = #paints
Bus:Publish("CONFIG_APPLIED", "MSUF_Test")
h:RunTimers()
Check(#paints == before and not groupA:IsActive(), "a repaint ran during combat")
h:LeaveCombat()
h:RunTimers()
Check(#paints == before + 1 and paints[#paints] == "regen", "combat end did not request one repaint")
Check(groupA:IsActive() and Shown(groupA) == 4 and groupRaid:IsActive() and Shown(groupRaid) == 12, "combat end did not bring the groups back")
-- A group the owner hid on purpose stays hidden through combat.
groupRaid:Hide()
Check(groupRaid.want == nil, "an explicit hide kept the wanted count")
h:EnterCombat()
GF.HidePreviewsForCombat()
h:LeaveCombat()
h:RunTimers()
Check(groupA:IsActive() and not groupRaid:IsActive(), "combat end showed a group the owner had hidden")
rootA:Group("raid", 12)
h:RunTimers()
Check(groupRaid:IsActive(), "asking for a group on an active root did not show it")
-- A count the owner sets on the group itself is the count combat brings back.
Check(groupRaid:Show(10, { immediate = true }) and Shown(groupRaid) == 10, "showing a group directly failed")
h:EnterCombat()
GF.HidePreviewsForCombat()
h:LeaveCombat()
h:RunTimers()
Check(groupRaid:IsActive() and Shown(groupRaid) == 10, "combat end did not bring back the count the owner showed last (" .. Shown(groupRaid) .. ")")

---------------------------------------------------------------------------
-- 5. A scene shows its static sample state, whatever the shared preview animation does.
---------------------------------------------------------------------------
local rootB = GF.NewPreviewScene(host)
local groupB = rootB:Group("party", 4)
rootB:Activate()
h:RunTimers()
local function StaticHp(index)
    return math.floor(math.min(0.95, 0.34 + (((index * 13) % 55) * 0.01)) * 100 + 0.5)
end
for index, frame in ipairs(groupA:Frames()) do Check(HpOf(frame) == StaticHp(index), "a scene does not show the static sample hp") end
Check(Queued() == 0, "an active root keeps a timer")
do
    local PA = assert(MSUF.PreviewAnimation, "no shared preview animation")
    local isEnabled, sampler, asked = PA.IsEnabled, env.MSUF_GetPreviewAnimationFrameState, 0
    PA.IsEnabled = function() return true end
    env.MSUF_GetPreviewAnimationFrameState = function(_, _, _, state)
        asked = asked + 1
        state.hpPct, state.powerPct = 0.5, 0.5
        return state
    end
    groupA:RefreshData()
    groupB:RefreshData()
    Check(asked == 0, "a scene followed the shared preview animation")
    for index, frame in ipairs(groupA:Frames()) do Check(HpOf(frame) == StaticHp(index), "a scene moved with the shared preview animation") end
    -- Control: the on-screen dummy does ask for the animation state (and, unlike a scene, the client: not spied here).
    armed = false
    GF.ShowPreview("party", 2, { immediate = true })
    h:RunTimers()
    GF.HidePreview("party")
    armed = true
    Check(asked > 0, "the on-screen dummy never asked the shared animation; the control is blind")
    PA.IsEnabled, env.MSUF_GetPreviewAnimationFrameState = isEnabled, sampler
end
rootA:Deactivate()
h:RunTimers()
Check(Queued() == 0, "a deactivated root keeps a timer")

---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- 6. Deactivate: hidden, unsubscribed, silent.
---------------------------------------------------------------------------
Check(not rootA:IsActive() and not groupA:IsActive() and not groupRaid:IsActive(), "deactivate left a group active")
Check(Shown(groupA) == 0 and Shown(groupRaid) == 0, "deactivate left a frame shown")
Check(not Subscribed("CONFIG_APPLIED", key) and not Subscribed("PLAYER_REGEN_ENABLED", key), "deactivate kept a subscription")
Check(groupA.want == 4, "deactivate forgot the wanted count")
local quiet = #paints
Bus:Publish("CONFIG_APPLIED", "MSUF_Test")
h:EnterCombat()
h:LeaveCombat()
h:RunTimers()
Check(#paints == quiet and Queued() == 0, "a deactivated root repainted")
Check(rootB:IsActive() and groupB:IsActive(), "deactivating one root touched another")
-- Activate again: the wanted groups return.
rootA:Activate()
h:RunTimers()
Check(groupA:IsActive() and Shown(groupA) == 4, "re-activate did not bring the groups back")

---------------------------------------------------------------------------
-- 7. Layers, auras and spell indicators on a scene, then release: still no unit API.
---------------------------------------------------------------------------
groupA:SetLayerFilter({ status = false }, nil)
groupA:RefreshAuras()
groupA:RefreshSpellIndicators()
groupA:Refresh({ immediate = true })
rootA:Group("mythicraid", 20)
h:RunTimers()

-- The sample name takes its colour from the row's sample class (class name colour on), the custom colour, or the
-- frame's text colour, and asks the client nothing: called on its own, not one unit API is touched.
do
    local general = env.MSUF_DB.general
    local PaintName = assert(MSUF.UFText and MSUF.UFText.PaintSampleName, "no sample name painter")
    local function ClassRGB(class)
        local fast = env.MSUF_UFCore_GetClassBarColorFast
        if type(fast) == "function" then
            local r, g, b = fast(class)
            if type(r) == "number" then return r, g, b end
        end
        local c = assert(env.RAID_CLASS_COLORS[class], "no colour for " .. tostring(class))
        return c.r, c.g, c.b
    end
    local function Painted(frame, label)
        -- The paint skips a colour it already holds; the preview paint sets the text colour behind that cache.
        frame._msufNameTextR = nil
        direct = true
        PaintName(frame, "Sample")
        direct = false
        local color = assert(frame.nameText.textColor, label .. ": the sample name has no colour")
        return color[1], color[2], color[3]
    end
    local function EveryFrame(expected, label)
        local mismatch = nil
        for index, frame in ipairs(groupA:Frames()) do
            local er, eg, eb = expected(frame)
            local r, g, b = Painted(frame, label)
            if r ~= er or g ~= eg or b ~= eb then mismatch = mismatch or (label .. ": row " .. index .. " is " .. tostring(r) .. "," .. tostring(g) .. "," .. tostring(b)) end
        end
        Check(mismatch == nil, mismatch or "")
    end
    local priorSeen, priorDetail = seen, detail
    seen, detail = {}, {}
    local distinct, firstKey = false, nil
    EveryFrame(function(frame)
        Check(type(frame._msufPortraitSampleClass) == "string", "a scene frame holds no sample class")
        local r, g, b = ClassRGB(frame._msufPortraitSampleClass)
        local key = r .. "," .. g .. "," .. b
        firstKey = firstKey or key
        if key ~= firstKey then distinct = true end
        return r, g, b
    end, "class name colour")
    Check(distinct, "class name colour painted one colour for rows of different sample class")
    -- Class colour off: the frame's text colour.
    general.nameClassColor, general.npcNameRed, general.nameNpcClassColor = false, false, false
    GF.InvalidateCompiledSpecs("party")
    groupA:Refresh({ immediate = true })
    h:RunTimers()
    EveryFrame(function(frame)
        local c = frame.MSUFSpec.textColor
        return c and c.r or 1, c and c.g or 1, c and c.b or 1
    end, "default name colour")
    -- A custom name colour wins over the sample class.
    general.nameClassColor, general.nameColorMode, general.nameColorR, general.nameColorG, general.nameColorB = true, "CUSTOM", 0.25, 0.5, 0.75
    GF.InvalidateCompiledSpecs("party")
    groupA:Refresh({ immediate = true })
    h:RunTimers()
    EveryFrame(function() return 0.25, 0.5, 0.75 end, "custom name colour")
    Check(#seen == 0, "painting a sample name called a unit API: " .. table.concat(detail, " | ", 1, math.min(#detail, 4)))
    general.nameColorMode = nil
    general.nameClassColor, general.npcNameRed, general.nameNpcClassColor = true, true, true
    GF.InvalidateCompiledSpecs("party")
    seen, detail = priorSeen, priorDetail
end

-- A portrait on a scene draws the row's sample class and takes its border colour from it: 2D render (the party
-- default) and class render, every border style. The client's portrait renderer and class and reaction lookups stay
-- unasked (the spy covers the whole apply and paint).
do
    local priorSeen, priorDetail = seen, detail
    local ART_FIELDS = { "atlas", "texture" }
    local function Art(texture)
        for _, field in ipairs(ART_FIELDS) do if rawget(texture, field) ~= nil then return tostring(rawget(texture, field)) end end
        return "none"
    end
    local function Edge(frame)
        local edge = frame.MSUFPortraitHolder.edges[1]
        local color = rawget(edge, "vertexColor") or {}
        return rawget(edge, "shown") == true, color[1], color[2], color[3]
    end
    for _, render in ipairs({ "2D", "CLASS" }) do
        for _, style in ipairs({ "NONE", "SOLID", "CLASS_COLOR", "REACTION", "CUSTOM" }) do
            local label = render .. " render, " .. style .. " border"
            party.portraitMode, party.portraitRender, party.portraitShape, party.portraitBorderStyle = "LEFT", render, "SQUARE", style
            party.portraitBorderColorR, party.portraitBorderColorG, party.portraitBorderColorB = 0.3, 0.6, 0.9
            GF.InvalidateCompiledSpecs("party")
            seen, detail = {}, {}
            groupA:Refresh({ immediate = true })
            h:RunTimers()
            Check(#seen == 0, label .. ": the portrait called a client API: " .. table.concat(detail, " | ", 1, math.min(#detail, 4)))
            local arts = {}
            for index, frame in ipairs(groupA:Frames()) do
                local texture = frame.portrait
                Check(texture and frame.MSUFPortraitHolder, label .. ": row " .. index .. " has no portrait")
                Check(texture._msufPortraitClassToken == frame._msufPortraitSampleClass and type(frame._msufPortraitSampleClass) == "string",
                    label .. ": row " .. index .. " does not draw its sample class")
                arts[Art(texture)] = true
                local shown, r, g, b = Edge(frame)
                local class = frame._msufPortraitSampleClass
                if style == "NONE" then
                    Check(not shown, label .. ": row " .. index .. " drew a border")
                elseif style == "CLASS_COLOR" then
                    local c = env.RAID_CLASS_COLORS[class]
                    Check(shown and r == c.r and g == c.g and b == c.b, label .. ": row " .. index .. " border is not its class colour")
                elseif style == "REACTION" then
                    Check(shown and r == 0 and g == 1 and b == 0, label .. ": row " .. index .. " border is not the friendly colour")
                else
                    Check(shown and r == 0.3 and g == 0.6 and b == 0.9, label .. ": row " .. index .. " border is not the configured colour")
                end
            end
            local distinct = 0
            for _ in pairs(arts) do distinct = distinct + 1 end
            Check(distinct >= 2, label .. ": rows of different sample class drew one portrait image")
        end
    end
    party.portraitMode, party.portraitRender, party.portraitBorderStyle = "LEFT", "CLASS", "NONE"
    GF.InvalidateCompiledSpecs("party")
    seen, detail = priorSeen, priorDetail
end
rootA:Release()
rootB:Release()
h:RunTimers()
Check(Queued() == 0, "a released root keeps a timer")
Check(not Subscribed("CONFIG_APPLIED", rootB.eventKey), "a released root kept a subscription")

---------------------------------------------------------------------------
-- 8. The spy saw nothing.
---------------------------------------------------------------------------
armed = false
Check(#seen == 0, "a preview scene called a unit API: " .. table.concat(detail, " | ", 1, math.min(#detail, 4)))

print("group_preview_scene_lifecycle_smoke: PASS (" .. flavor .. ")")
