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
env.MSUF_DB.general.tempMaxHealthEnabled = true
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
-- 7b. An embedded scene (the Options preview): the owner sets zoom, frame level, role and one sample, and gets the
-- frame body only. Still no unit API.
---------------------------------------------------------------------------
do
    local embedHost = env.CreateFrame("Frame", nil, env.UIParent)
    embedHost:SetSize(400, 300)
    local embedRoot = GF.NewPreviewScene(embedHost)
    embedRoot:Activate()
    local cell = embedRoot:Group("party")
    local sample = { name = "Sample", class = "MAGE", hpPct = 0.5, powerPct = 0.25, hpMax = 1000000, powerMax = 100,
        healPct = 0.2, absorbPct = 0.1, healAbsorbPct = 0.05, tempMaxPct = 0.25, powerColor = { 0.1, 0.2, 0.3 } }
    cell:Configure({ scale = 1.5, level = 40, role = "HEALER", sample = sample, bodyOnly = true })
    cell:Show(1, { immediate = true })
    h:RunTimers()
    local frame = cell:Frames()[1]
    Check(frame and #cell:Frames() == 1, "the embedded scene did not show one row")
    Check(cell:Container():GetScale() == 1.5, "the embedded scene is not zoomed as a whole")
    Check(cell:Container():GetFrameLevel() == 40 and frame:GetFrameLevel() == 40, "the embedded scene is not seated at its owner's level")
    local bar = frame.hpBar or frame.Health or frame.health
    Check(bar and bar.value == 500000 and bar.maximum == 1000000, "the sample hp did not reach the health bar")
    Check(frame.powerBar and frame.powerBar.value == 25 and frame.powerBar.maximum == 100, "the sample power did not reach the power bar")
    Check(frame.nameText and frame.nameText.text == "Sample", "the sample name did not reach the name text")
    Check(frame.MSUFUnitKey == nil, "an embedded scene frame holds a unit")
    -- The reduced-max-health sample is painted where the client has the API the live bar uses.
    local reduced = frame.tempMaxHealthBar
    Check(reduced and reduced.value == 0.25, "the sample reduced max health did not reach its bar")
    -- A second sample repaints without a unit query; a clock animates the groups and nil returns them to the sample.
    sample.hpPct = 0.8
    cell:SetSample(sample)
    h:RunTimers()
    Check(bar.value == 800000, "a new sample did not repaint the row")
    embedRoot:SetClock(2.5, true)
    cell:Refresh({ immediate = true })
    Check(bar.value ~= 800000, "a handed clock did not animate the row")
    embedRoot:SetClock(nil, true)
    cell:Refresh({ immediate = true })
    Check(bar.value == 800000, "a cleared clock did not return the sample")
    cell:SetBodyOnly(false)
    h:RunTimers()
    embedRoot:Release()
    h:RunTimers()
end

---------------------------------------------------------------------------
-- 7c. The clock an owner hands over (the Options "Animate" chip drives its own ticker): the scene follows that elapsed
-- time exactly as the animation state builder computes it, another root and the shared animation clock stay put, and
-- nil returns the static sample.
---------------------------------------------------------------------------
do
    local clockHost = env.CreateFrame("Frame", nil, env.UIParent)
    clockHost:SetSize(400, 300)
    local clockedRoot, stillRoot = GF.NewPreviewScene(clockHost), GF.NewPreviewScene(clockHost)
    local clocked, still = clockedRoot:Group("party", 3), stillRoot:Group("party", 3)
    clockedRoot:Activate()
    stillRoot:Activate()
    h:RunTimers()
    local function StaticAt(index) return math.floor(math.min(0.95, 0.34 + (((index * 13) % 55) * 0.01)) * 100 + 0.5) end
    local function ExpectedHp(frame, index, elapsed)
        local state = env.MSUF_BuildPreviewAnimationFrameState(frame, index, "party", {}, elapsed)
        return math.floor(math.min(0.98, math.max(0.02, state.hpPct)) * 100 + 0.5)
    end
    local sharedElapsed = MSUF.PreviewAnimation and MSUF.PreviewAnimation.elapsed
    for index, frame in ipairs(clocked:Frames()) do Check(HpOf(frame) == StaticAt(index), "a root without a clock left its static sample") end
    -- A clock repaints the active groups (no noRefresh) and the picture follows the builder at that time.
    for _, elapsed in ipairs({ 0.9, 2.5, 7.25 }) do
        clockedRoot:SetClock(elapsed)
        h:RunTimers()
        local moved = false
        for index, frame in ipairs(clocked:Frames()) do
            Check(HpOf(frame) == ExpectedHp(frame, index, elapsed), "clock " .. elapsed .. ": row " .. index .. " does not follow the handed clock")
            if HpOf(frame) ~= StaticAt(index) then moved = true end
        end
        Check(moved, "clock " .. elapsed .. ": the animated scene never left its static sample")
        for index, frame in ipairs(still:Frames()) do
            Check(HpOf(frame) == StaticAt(index), "another root's scene moved with this root's clock")
        end
        Check(MSUF.PreviewAnimation == nil or MSUF.PreviewAnimation.elapsed == sharedElapsed, "a handed clock advanced the shared preview animation clock")
    end
    -- noRefresh: the owner paints next itself, so the clock alone repaints nothing.
    local held = HpOf(clocked:Frames()[1])
    clockedRoot:SetClock(11, true)
    Check(HpOf(clocked:Frames()[1]) == held, "a clock handed with noRefresh repainted the group")
    clocked:Refresh({ immediate = true })
    h:RunTimers()
    Check(HpOf(clocked:Frames()[1]) == ExpectedHp(clocked:Frames()[1], 1, 11), "the owner's refresh did not use the clock it handed over")
    clockedRoot:SetClock(nil)
    h:RunTimers()
    for index, frame in ipairs(clocked:Frames()) do Check(HpOf(frame) == StaticAt(index), "clearing the clock left row " .. index .. " animated") end
    clockedRoot:Release()
    stillRoot:Release()
    h:RunTimers()
end

---------------------------------------------------------------------------
-- 7d. A pinned sample class is the class of the row: its portrait art and its class name colour follow the sample,
-- not the member the slot holds.
---------------------------------------------------------------------------
do
    local pinHost = env.CreateFrame("Frame", nil, env.UIParent)
    pinHost:SetSize(400, 300)
    local pinRoot = GF.NewPreviewScene(pinHost)
    pinRoot:Activate()
    local cell = pinRoot:Group("party")
    party.portraitMode, party.portraitRender, party.portraitBorderStyle = "LEFT", "CLASS", "NONE"
    GF.InvalidateCompiledSpecs("party")
    local function NameRGB(class)
        local fast = env.MSUF_UFCore_GetClassBarColorFast
        if type(fast) == "function" then
            local r, g, b = fast(class)
            if type(r) == "number" then return r, g, b end
        end
        local c = env.RAID_CLASS_COLORS[class]
        return c.r, c.g, c.b
    end
    for _, class in ipairs({ "MAGE", "DRUID", "MAGE" }) do
        cell:Configure({ sample = { name = "Pinned", class = class } })
        cell:Show(1, { immediate = true })
        h:RunTimers()
        local frame = cell:Frames()[1]
        Check(frame._msufPortraitSampleClass == class, class .. ": the frame kept the class of its slot (" .. tostring(frame._msufPortraitSampleClass) .. ")")
        Check(frame.portrait and frame.portrait._msufPortraitClassToken == class, class .. ": the portrait does not draw the pinned class")
        local er, eg, eb = NameRGB(class)
        local color = frame.nameText.textColor or {}
        Check(color[1] == er and color[2] == eg and color[3] == eb, class .. ": the name is not in the pinned class colour")
    end
    pinRoot:Release()
    h:RunTimers()
end

---------------------------------------------------------------------------
-- 7e. The out-of-combat fade: an owner whose window is always open out of combat asks its scene to ignore it. Every
-- other alpha setting stays live, the shared compiled spec keeps the fade, and a scene or an on-screen dummy that does
-- not ask still fades like a live frame.
---------------------------------------------------------------------------
do
    local function Fills(frame)
        local bar = frame.hpBar or frame.Health or frame.health
        local texture = bar and bar.GetStatusBarTexture and bar:GetStatusBarTexture()
        return texture and texture.GetAlpha and texture:GetAlpha()
    end
    local savedHp = party.hpBarAlpha
    party.oocFadeEnabled, party.oocFadeAlpha, party.hpBarAlpha = true, 0.4, 0.6
    GF.InvalidateCompiledSpecs("party")
    local shared = GF.CompileSpec("party")
    Check(shared.alpha.oocFade == true and shared.alpha.active == true, "harness: the party spec carries no out-of-combat fade")
    local fadeHost = env.CreateFrame("Frame", nil, env.UIParent)
    fadeHost:SetSize(400, 300)
    local fadeRoot = GF.NewPreviewScene(fadeHost)
    fadeRoot:Activate()
    local cell = fadeRoot:Group("party")
    -- Control: a scene that does not ask fades like a live frame, and so does the on-screen dummy.
    cell:Show(2, { immediate = true })
    h:RunTimers()
    local frame = cell:Frames()[1]
    Check(frame:GetAlpha() == 0.4, "a plain scene does not fade out of combat (" .. tostring(frame:GetAlpha()) .. "); the control is blind")
    armed = false
    GF.ShowPreview("party", 2, { immediate = true })
    h:RunTimers()
    local dummy = GF._previewFrames.party and GF._previewFrames.party[1]
    Check(dummy and dummy:GetAlpha() == 0.4, "the on-screen dummy does not fade out of combat; the live control is blind")
    GF.HidePreview("party")
    armed = true
    -- The request: the frame is at full alpha, with the health bar opacity and the shared spec untouched.
    cell:Configure({ ignoreOocFade = true })
    cell:Show(2, { immediate = true })
    h:RunTimers()
    for index, f in ipairs(cell:Frames()) do
        Check(f:GetAlpha() == 1, "row " .. index .. " faded out of combat although the scene ignores it (" .. tostring(f:GetAlpha()) .. ")")
        Check(f.MSUFSpec.alpha.oocFade == false and f.MSUFSpec.alpha.active == true and f.MSUFSpec.alpha.hpAlpha == 0.6,
            "row " .. index .. ": the scene alpha lane lost another alpha setting")
        Check(Fills(f) == 0.6 and f.nameText:GetAlpha() == 0.6, "row " .. index .. ": the health bar opacity is no longer live (fill "
            .. tostring(Fills(f)) .. ", name " .. tostring(f.nameText:GetAlpha()) .. ")")
    end
    Check(GF.CompileSpec("party").alpha.oocFade == true, "the scene changed the shared compiled spec")
    Check(frame.MSUFSpec.alpha ~= shared.alpha and getmetatable(frame.MSUFSpec.alpha).__index == shared.alpha, "the scene alpha lane is not an overlay of the compiled one")
    -- Flipping the request repaints: back to the fade, then to full alpha again.
    cell:Configure({ ignoreOocFade = false })
    cell:Show(2, { immediate = true })
    h:RunTimers()
    Check(frame:GetAlpha() == 0.4 and frame.MSUFSpec.alpha == shared.alpha, "withdrawing the request did not bring the fade back")
    cell:Configure({ ignoreOocFade = true })
    cell:Show(2, { immediate = true })
    h:RunTimers()
    Check(frame:GetAlpha() == 1, "asking again did not remove the fade")
    -- No health bar opacity: the fade is the only alpha setting, so the scene has no alpha element to run and the
    -- frame returns to full alpha when the request comes and to the fade when it goes.
    party.hpBarAlpha = 1
    GF.InvalidateCompiledSpecs("party")
    cell:Configure({ ignoreOocFade = false })
    cell:Show(2, { immediate = true })
    h:RunTimers()
    Check(frame:GetAlpha() == 0.4, "without a health bar opacity the plain scene does not fade")
    cell:Configure({ ignoreOocFade = true })
    cell:Show(2, { immediate = true })
    h:RunTimers()
    Check(frame:GetAlpha() == 1 and frame.MSUFSpec.alpha.oocFade == false, "without a health bar opacity the request did not remove the fade")
    -- The fade switched off: the overlay is gone and the compiled lane is used as it is.
    party.oocFadeEnabled = false
    GF.InvalidateCompiledSpecs("party")
    cell:Show(2, { immediate = true })
    h:RunTimers()
    Check(frame:GetAlpha() == 1 and frame.MSUFSpec.alpha == GF.CompileSpec("party").alpha, "a profile without the fade kept a scene alpha overlay")
    party.oocFadeEnabled, party.oocFadeAlpha, party.hpBarAlpha = nil, nil, savedHp
    GF.InvalidateCompiledSpecs("party")
    fadeRoot:Release()
    h:RunTimers()
end

---------------------------------------------------------------------------
-- 7f. A sample absorb amount reaches the absorb text and the combined health text of the scene frame (the live frame
-- asks the unit for it); a sample without one leaves none behind.
---------------------------------------------------------------------------
do
    local absorbHost = env.CreateFrame("Frame", nil, env.UIParent)
    absorbHost:SetSize(400, 300)
    local absorbRoot = GF.NewPreviewScene(absorbHost)
    absorbRoot:Activate()
    local cell = absorbRoot:Group("party")
    local savedText = { party.textLeft, party.textCenter, party.textRight }
    party.textLeft, party.textCenter, party.textRight = "ABSORB", "NONE", "CURRENT"
    GF.InvalidateCompiledSpecs("party")
    cell:Configure({ sample = { name = "Absorb", class = "MAGE", hpPct = 0.5, hpMax = 1000000, absorb = 77000 }, bodyOnly = true })
    cell:Show(1, { immediate = true })
    h:RunTimers()
    local frame = cell:Frames()[1]
    local text = MSUF.UFText
    local plain = text.UpdateTextSlots
    local seen = {}
    text.UpdateTextSlots = function(slots, count, current, max, ...)
        local rt = frame._msufTextRuntime
        if slots == rt.healthAbsorbSlots then seen.absorbSlots = rt.healthAbsorb end
        if slots == rt.healthSlots then seen.health, seen.healthAbsorb = current, rt.healthAbsorb end
        return plain(slots, count, current, max, ...)
    end
    cell:Refresh({ immediate = true })
    h:RunTimers()
    Check(seen.health == 500000 and seen.healthAbsorb == 77000, "the combined health text did not get the sample absorb (" .. tostring(seen.healthAbsorb) .. ")")
    Check(seen.absorbSlots == 77000, "the absorb text did not get the sample absorb (" .. tostring(seen.absorbSlots) .. ")")
    seen = {}
    cell:SetSample({ name = "Absorb", class = "MAGE", hpPct = 0.5, hpMax = 1000000 })
    h:RunTimers()
    Check(frame._msufTextRuntime.healthAbsorb == nil and seen.absorbSlots == nil, "a sample without an absorb kept the previous one")
    text.UpdateTextSlots = plain
    party.textLeft, party.textCenter, party.textRight = savedText[1], savedText[2], savedText[3]
    GF.InvalidateCompiledSpecs("party")
    absorbRoot:Release()
    h:RunTimers()
end

---------------------------------------------------------------------------
-- 7g. A raid layout that keeps the groups apart lays one frame out in a whole group column; an owner that shows one
-- frame and centres the container itself asks it to fit: the container is then the frame.
---------------------------------------------------------------------------
do
    local fitHost = env.CreateFrame("Frame", nil, env.UIParent)
    fitHost:SetSize(400, 300)
    local fitRoot = GF.NewPreviewScene(fitHost)
    fitRoot:Activate()
    local savedPreserve = raid.preserveRaidGroups
    for _, kind in ipairs({ "raid", "mythicraid" }) do
        local conf = GF.GetConf(kind)
        local saved = conf.preserveRaidGroups
        conf.preserveRaidGroups = true
        GF.InvalidateCompiledSpecs(kind)
        local group = fitRoot:Group(kind)
        group:Show(1, { immediate = true })
        h:RunTimers()
        local frame = group:Frames()[1]
        local container = group:Container()
        Check(container:GetHeight() > frame:GetHeight(), kind .. ": harness: the grouped layout is not a whole column (" .. container:GetHeight() .. " vs " .. frame:GetHeight() .. ")")
        group:Configure({ fit = true })
        group:Show(1, { immediate = true })
        h:RunTimers()
        Check(container:GetWidth() == frame:GetWidth() and container:GetHeight() == frame:GetHeight(),
            kind .. ": a fitted container is not the size of its frame (" .. container:GetWidth() .. "x" .. container:GetHeight() .. ")")
        local layout = group:Layout()
        Check(layout:GetWidth() == frame:GetWidth() and layout:GetHeight() == frame:GetHeight(), kind .. ": a fitted layout is not the size of its frame")
        group:Configure({ fit = false })
        group:Show(1, { immediate = true })
        h:RunTimers()
        Check(container:GetHeight() > frame:GetHeight(), kind .. ": withdrawing fit did not bring the grid footprint back")
        group:Hide()
        conf.preserveRaidGroups = saved
        GF.InvalidateCompiledSpecs(kind)
    end
    raid.preserveRaidGroups = savedPreserve
    fitRoot:Release()
    h:RunTimers()
end

---------------------------------------------------------------------------
-- 8. The spy saw nothing.
---------------------------------------------------------------------------
armed = false
Check(#seen == 0, "a preview scene called a unit API: " .. table.concat(detail, " | ", 1, math.min(#detail, 4)))

print("group_preview_scene_lifecycle_smoke: PASS (" .. flavor .. ")")
