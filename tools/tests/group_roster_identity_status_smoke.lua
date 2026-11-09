-- group_roster_identity_status_smoke.lua <root> <flavor> [raid|mythicraid]
-- Actual header attribute hooks, compiler and painters; no UNIT_NAME_UPDATE is
-- synthesized for a roster-only occupant change. The secure click unit and the
-- name/class-color sinks must agree after Blizzard rewrites the same raid token.
local root, flavor = assert(arg[1]), arg[2] or "Mainline"
local kind = arg[3] or "raid"
local Secrets = dofile(root .. "/tools/tests/classpower_secrets.lua")
Secrets.Install()
local secretGUID = Secrets.New("string")
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")
local members = { raid1 = { "Mage", "MAGE" }, raid2 = { "Warrior", "WARRIOR" } }
local colors = { MAGE = { r = .1, g = .6, b = 1 }, WARRIOR = { r = .8, g = .5, b = .2 } }
local guidReads, nameReads = 0, 0
local rosterGuidReads, elementGuidReads = 0, 0
local secret = false
local helpfulAuras, consumptionReads = {}, 0
local EMPTY_AURAS = {}
-- members[unit][3] == false marks that occupant offline; transientOffline models
-- UnitIsConnected answering false for every token while the roster is in flux.
local transientOffline = false
local instanceType, runtimeZoneReads = "raid", 0
local h = Harness.New(root, flavor, { beforeBoot = function(h)
    h.env.type, h.env.issecretvalue = type, issecretvalue
    h.env.GetNumClasses = function() return 13 end
    h.env.C_UnitAuras.GetUnitAuras = function(unit, filter)
        local source = debug.getinfo(2, "S").source
        if source:find("MSUF_UF_Status_Indicators.lua", 1, true) then
            assert(filter == "HELPFUL", "unexpected consumption aura filter")
            consumptionReads = consumptionReads + 1
            return helpfulAuras[unit] or EMPTY_AURAS
        end
        return EMPTY_AURAS
    end
    h.env.IsInInstance = function()
        local caller = debug.getinfo(2, "S")
        if caller and caller.source:find("MSUF_UF_Group_Runtime.lua", 1, true) then
            runtimeZoneReads = runtimeZoneReads + 1
        end
        return instanceType ~= "none", instanceType
    end
    h.env.GetRaidDifficultyID = function() return kind == "mythicraid" and 16 or 14 end
    h.env.UnitName = function(unit)
        nameReads = nameReads + 1
        return members[unit] and members[unit][1] or "Player"
    end
    h.env.UnitGUID = function(unit)
        guidReads = guidReads + 1
        -- Classify by the nearest group caller; shared helpers sit in between.
        for level = 2, 4 do
            local info = debug.getinfo(level, "S")
            local source = info and info.source or ""
            if source:find("MSUF_UF_Group_Runtime.lua", 1, true) or source:find("MSUF_UF_Group_Adapter.lua", 1, true) then
                rosterGuidReads = rosterGuidReads + 1
                break
            elseif source:find("MSUF_UF_Group_RangeFade.lua", 1, true) or source:find("MSUF_UF_Group_Visuals.lua", 1, true) then
                -- The identity reseed of the range self-check and the target/focus
                -- indicator bucket, the same reads every token change makes.
                elementGuidReads = elementGuidReads + 1
                break
            end
        end
        if secret then return secretGUID end
        return "Player-" .. (members[unit] and members[unit][1] or unit)
    end
    h.env.UnitClass = function(unit)
        local class = members[unit] and members[unit][2] or "WARRIOR"
        return class, class, 1
    end
    h.env.UnitIsPlayer = function() return true end
    h.env.UnitIsConnected = function(unit)
        local member = members[unit]
        return member ~= nil and member[3] ~= false and not transientOffline
    end
    h.env.RAID_CLASS_COLORS = colors
    h.env.GetRaidRosterInfo = function(index)
        local member = members[h.units[index]]
        if member then return member[1], 0, index, 90, member[2], member[2], nil, true end
    end
end })
local GF = h.GF
GF.EnsureDB()
local conf = GF.GetConf(kind)
conf.enabled, conf.showName, conf.gfBarMode = true, true, "class"
conf.preserveRaidGroups = false
for _, key in ipairs({ "healthFadeEnabled", "targetIndicator", "focusIndicator", "deadBgEnabled", "debuffStripeEnabled", "nameBarEnabled" }) do
    conf[key] = false
end
h.env.MSUF_DB.general.barBgColorMode = "class"
GF.InvalidateCompiledSpecs(kind)
GF.RefreshHeaderLayout()
h:SetRaid(2)
h:Event("GROUP_ROSTER_UPDATE")
h:RunTimers()
local children = h:Children(GF.headers.raid)
assert(#children == 2, "two real raid children required")
assert(children[1]._msufGFKind == kind, "wrong raid scope")
assert(children[1].MSUFSpec.health.backgroundColorMode == "class", "class background fixture not active")
local function Check(label)
    local failures = {}
    for _, frame in ipairs(children) do
        local unit = frame:GetAttribute("unit")
        local member = assert(members[unit])
        local color = colors[member[2]]
        local r, g, b = frame.hpBar:GetStatusBarColor()
        local br, bg, bb = frame.bg:GetVertexColor()
        if frame.nameText:GetText() ~= member[1] then failures[#failures + 1] = unit .. " stale name" end
        if r ~= color.r or g ~= color.g or b ~= color.b then failures[#failures + 1] = unit .. " stale class color" end
        if br ~= color.r or bg ~= color.g or bb ~= color.b then failures[#failures + 1] = unit .. " stale background class color" end
        assert(frame.MSUFUnitKey == unit and GF.FrameForUnit(unit) == frame, "secure/visual/index unit mismatch")
    end
    assert(#failures == 0, label .. ": " .. table.concat(failures, ", "))
    assert(#h.violations == 0, "protected write: " .. tostring(h.violations[1]))
    assert(#h.callMethodErrors == 0, "child initialization error")
end
local function Roster()
    h:Event("GROUP_ROSTER_UPDATE")
    h:RunTimers()
end
local function Swap()
    members.raid1, members.raid2 = members.raid2, members.raid1
end
Check("initial")

local function CheckConsumption(scope, unit)
    local frame = assert(GF.FrameForUnit(unit))
    local settings = GF.GetConf(scope)
    local oldToggle = settings.statusConsumptionText
    local fullUpdate = { isFullUpdate = true }
    local function Apply(enabled)
        settings.statusConsumptionText = enabled
        GF.InvalidateCompiledSpecs(scope)
        assert(GF.ApplyButton(frame, scope, "MSUF_GF_APPLY_CONSUMPTION_TEST"))
    end
    local function HasAuraRoute()
        for _, event in ipairs(frame.MSUFSpec.status.groupRuntimeEvents or {}) do
            if event == "UNIT_AURA" then return true end
        end
        return false
    end
    local function CheckText(expected)
        assert(frame._msufStatusTextValue == expected,
            unit .. " must render " .. tostring(expected) .. ", got " .. tostring(frame._msufStatusTextValue))
        local text = frame.statusIndicatorText
        assert(text and text:IsShown() == (expected ~= nil), unit .. " consumption text visibility")
        if expected then
            assert(text:GetText() == h.core.Translate(expected), unit .. " translation did not reach the font string")
        end
    end

    local before = consumptionReads
    helpfulAuras[unit] = { { spellId = 433 } }
    Apply(nil)
    assert(not HasAuraRoute(), unit .. " consumption event is registered by default")
    h:Event("UNIT_AURA", unit, fullUpdate)
    CheckText(nil)
    assert(consumptionReads == before, unit .. " default-off consumption read helpful auras")

    Apply(true)
    local forever = flavor == "Forever"
    assert(HasAuraRoute() == forever, unit .. " must gate its consumption aura route on Forever")
    if forever then
        CheckText("EATING")
        helpfulAuras[unit] = { { spellId = 430 } }
        h:Event("UNIT_AURA", unit, fullUpdate)
        CheckText("DRINKING")
        before = consumptionReads
        h.UF.elements.GroupStatusRuntime.UpdateState(frame, "UNIT_HEALTH", unit, 100)
        assert(consumptionReads == before, unit .. " health event read helpful auras")
        CheckText("DRINKING")

        h:EnterCombat()
        local protectedWrites = #h.violations
        helpfulAuras[unit] = { { spellId = Secrets.New("number") } }
        local renderer = root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Status_Indicators.lua"
        local stopWatch = Secrets.Watch(renderer, { strict = true })
        h:Event("UNIT_AURA", unit, fullUpdate)
        local violations = stopWatch()
        assert(#violations == 0, unit .. " touched restricted aura data: " .. table.concat(violations, ", "))
        CheckText(nil)
        assert(#h.violations == protectedWrites, unit .. " consumption aura update touched protected state")
        h:LeaveCombat()
        h:RunTimers()

        before = consumptionReads
        local otherAura = { spellId = 6673, auraInstanceID = 12 }
        helpfulAuras[unit] = { otherAura }
        h:Event("UNIT_AURA", unit, { isFullUpdate = false, addedAuras = { otherAura } })
        CheckText(nil)
        assert(consumptionReads == before, unit .. " unrelated aura delta read the aura list")

        local drink = { spellId = 430, auraInstanceID = 13 }
        helpfulAuras[unit] = { drink }
        h:Event("UNIT_AURA", unit, { isFullUpdate = false, addedAuras = { drink } })
        CheckText("DRINKING")
        assert(consumptionReads == before, unit .. " new drink delta read the aura list")
        Apply(false)
        assert(not HasAuraRoute(), unit .. " disabling consumption did not remove its event")
        CheckText(nil)
    else
        CheckText(nil)
        assert(consumptionReads == before, unit .. " non-Forever consumption read helpful auras")
    end
    helpfulAuras[unit] = nil
    Apply(oldToggle)
end

CheckConsumption(kind, "raid1")
secret = true
-- Moving subgroup rows can rewrite different tokens; this existing path is green.
h.units[1], h.units[2] = h.units[2], h.units[1]
Roster()
Check("changed tokens")
-- Native roster indices can instead retain their token while acquiring another
-- occupant. This is red on 6.501 for BOTH text and class-colored health bars.
Swap()
Roster()
Check("same tokens, different occupants")
h:EnterCombat()
assert(h.env.InCombatLockdown() == true, "combat fixture must actually be locked down")
-- Prove the harness catches each protected operation used by the roster path.
-- Native header writes remain secure; only insecure addon writes are violations.
for _, method in ipairs({ "Show", "Hide", "SetPoint", "SetAttribute" }) do
    local child, before = children[1], #h.violations
    if method == "SetPoint" then child:SetPoint("CENTER", h.widgets.UIParent, "CENTER", 0, 0)
    elseif method == "SetAttribute" then child:SetAttribute("unit", child:GetAttribute("unit"))
    else child[method](child) end
    assert(#h.violations > before, "protected-call sentinel missed " .. method)
    for i = #h.violations, before + 1, -1 do h.violations[i] = nil end
end
h.RunSecure(children[1].Show, children[1])
Swap()
Roster()
assert(h.env.InCombatLockdown() == true and #h.violations == 0, "combat settle wrote protected state")
Check("combat occupant change")
-- GetTime is constant in this fixture: two distinct identities in one rendered
-- frame must both refresh, unlike repeated writes for the same identity.
Swap()
Roster()
Check("second change in same frame")
local refreshes = 0
local refresh = h.UF.RefreshGroupFrameState
h.UF.RefreshGroupFrameState = function(...)
    refreshes = refreshes + 1
    return refresh(...)
end
guidReads, nameReads = 0, 0
for _ = 1, 100 do
    for _, frame in ipairs(children) do
        h.RunSecure(frame.SetAttribute, frame, "unit", frame:GetAttribute("unit"))
    end
end
assert(refreshes == 0 and nameReads == 0, "unchanged identities repainted")
assert(guidReads == 0, "raid attribute hook still reads GUID")
-- Measure the actual insecure hook alone, excluding the emulator's secure-call
-- tables. A warmed, unchanged raid member must allocate nothing.
local frame = children[1]
local hook = frame:GetScript("OnAttributeChanged")
local function Measure()
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    for _ = 1, 1000 do hook(frame, "unit", frame:GetAttribute("unit")) end
    local kb = collectgarbage("count") - before
    collectgarbage("restart")
    return kb
end
assert(math.min(Measure(), Measure()) <= .1, "unchanged raid identities allocate memory")
guidReads = 0
for _ = 1, 100 do frame:GetScript("OnEvent")(frame, "UNIT_HEALTH", frame.MSUFUnitKey) end
assert(guidReads == 0, "identity detection leaked onto health ticks")
-- Roster bursts paint the final occupant once after the native headers finish.
refreshes, guidReads, elementGuidReads = 0, 0, 0
local registrations, auraRebinds = 0, 0
for _, child in ipairs(children) do
    local register = child.RegisterUnitEvent
    child.RegisterUnitEvent = function(...) registrations = registrations + 1; return register(...) end
end
local aura = h.core.MSUF_Auras3
local rebindAura = aura.OnFrameUnitChanged
aura.OnFrameUnitChanged = function(...) auraRebinds = auraRebinds + 1; return rebindAura(...) end
for _ = 1, 19 do Swap(); h:Event("GROUP_ROSTER_UPDATE") end
assert(refreshes == 0, "roster refresh ran before native event dispatch settled")
local queued = 0
for _, entry in ipairs(h.widgets.timers) do
    if debug.getinfo(entry.callback, "S").source:find("MSUF_UF_Group_Runtime.lua", 1, true) then queued = queued + 1 end
end
assert(queued == 1, "roster burst queued more than one settle callback")
h:RunTimers()
assert(refreshes == #children, "roster burst must refresh each live frame once")
assert(registrations == 0 and auraRebinds == 0, "same-token roster repaint rebound event or aura ownership")
assert(rosterGuidReads == 0, "roster repaint depends on GUID")
-- The settle is an identity pass: only the range self-check and the target/focus
-- indicator bucket reseed from the GUID, once each per frame, as on a token change.
if flavor == "Mainline" or flavor == "Forever" then
    assert(guidReads == elementGuidReads and elementGuidReads <= 2 * #children, "Retail roster pass read GUID")
end
Check("burst final occupant")
-- Cover the opposite native/addon event registration order as well.
local frames, runtimeIndex, headerIndex = h.widgets.frames
for i, candidate in ipairs(frames) do
    local handler = candidate.scripts and candidate.scripts.OnEvent
    local source = handler and debug.getinfo(handler, "S").source or ""
    if source:find("MSUF_UF_Group_Runtime.lua", 1, true) then runtimeIndex = i end
    if candidate == GF.headers.raid then headerIndex = i end
end
assert(runtimeIndex and headerIndex, "real runtime/header handlers required")
frames[runtimeIndex], frames[headerIndex] = frames[headerIndex], frames[runtimeIndex]
Swap(); Roster(); Check("opposite event order")
frames[runtimeIndex], frames[headerIndex] = frames[headerIndex], frames[runtimeIndex]
-- Entering combat between scheduling and flushing must not lose visual work.
h:LeaveCombat(); h:RunTimers()
Swap(); h:Event("GROUP_ROSTER_UPDATE"); h:EnterCombat(); h:RunTimers()
Check("combat starts before flush")
-- A second burst within the same GetTime value must not be suppressed.
Swap(); Roster(); Check("second completed flush in same frame")
-- Health/power and role-only notifications must not become full roster paints.
refreshes = 0
for _ = 1, 100 do
    frame:GetScript("OnEvent")(frame, "UNIT_HEALTH", frame.MSUFUnitKey)
    frame:GetScript("OnEvent")(frame, "UNIT_POWER_UPDATE", frame.MSUFUnitKey, "MANA")
end
assert(refreshes == 0, "roster repaint leaked onto health/power ticks")
h:LeaveCombat(); h:RunTimers()
refreshes = 0
h:Event("PLAYER_ROLES_ASSIGNED"); h:RunTimers()
assert(refreshes == 0, "role event caused a full roster repaint")
-- Preview/hidden frames do not consume the live roster pass.
local hidden, preview = children[1], children[2]
h:EnterCombat()
h:Event("GROUP_ROSTER_UPDATE")
h.RunSecure(hidden.Hide, hidden)
preview._msufGFIsPreviewFrame = true
refreshes = 0
h:RunTimers()
assert(refreshes == 0, "hidden/preview frame consumed live roster refresh")
preview._msufGFIsPreviewFrame = nil
h.RunSecure(hidden.Show, hidden)
Roster(); Check("visible after hidden/preview")
-- No secret GUID may reach an identity comparison anywhere in the changed files.
local stopRuntime = Secrets.Watch(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Runtime.lua", { strict = true })
local stopAdapter = Secrets.Watch(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Adapter.lua", { strict = true })
Swap(); Roster()
assert(#stopRuntime() == 0 and #stopAdapter() == 0, "secret identity operation")
Check("secret GUID independent refresh")
-- Exercise the roster callback's optional identity-painter boundary after a
-- successful compiled refresh. Missing element state must not raise here.
local iterate, rosterCallback = GF.ForEachFrame
GF.ForEachFrame = function(callback, hiddenFrames, reason)
    if reason == "MSUF_GF_UNIT_IDENTITY" then rosterCallback = callback end
    return iterate(callback, hiddenFrames, reason)
end
Roster()
GF.ForEachFrame = iterate
assert(rosterCallback, "real roster callback was not exercised")
local originalRefresh, elements = h.UF.RefreshGroupFrameState, h.UF.elements
h.UF.RefreshGroupFrameState = function() return true end
assert(rosterCallback({}, nil, kind, "GROUP_ROSTER_UPDATE"), "missing active elements refused refresh")
h.UF.elements = nil
assert(rosterCallback({ _msufActiveElements = { Health = true } }, nil, kind, "GROUP_ROSTER_UPDATE"),
    "missing element registry refused refresh")
h.UF.elements, h.UF.RefreshGroupFrameState = elements, originalRefresh
-- Native recycling detaches the old unit before reusing the same child.
local unit = frame:GetAttribute("unit")
h.RunSecure(frame.SetAttribute, frame, "unit", nil)
h.RunSecure(frame.SetAttribute, frame, "unit", unit)
Check("recycled child")
h:LeaveCombat()
h:RunTimers()
Check("after combat")
-- Out of combat the settle must reseed status from the current occupant too:
-- a same-token shift may not keep the previous occupant's OFFLINE label, and a
-- disconnected answer read mid-roster may not outlive the settled roster.
conf.statusText = true
GF.InvalidateCompiledSpecs(kind)
GF.RefreshHeaderLayout()
Roster()
local function FrameOf(name)
    for _, child in ipairs(children) do
        local member = members[child:GetAttribute("unit")]
        if member and member[1] == name then return child end
    end
end
local function CheckStatus(label)
    for _, child in ipairs(children) do
        local member = assert(members[child:GetAttribute("unit")])
        local shown = child._msufStatusTextValue == "OFFLINE"
        assert(shown == (member[3] == false), label .. ": " .. member[1] .. (shown and " shows" or " lacks") .. " OFFLINE")
    end
end
CheckStatus("status fixture")
local mage = FrameOf("Mage")
members[mage:GetAttribute("unit")][3] = false
mage:GetScript("OnEvent")(mage, "UNIT_CONNECTION", mage.MSUFUnitKey, false)
assert(mage._msufStatusTextValue == "OFFLINE", "status fixture did not paint OFFLINE")
CheckStatus("occupant disconnected")
Swap(); Roster(); CheckStatus("same tokens, offline occupant moved")
h.units[1], h.units[2] = h.units[2], h.units[1]
transientOffline = true
h:Event("GROUP_ROSTER_UPDATE")
transientOffline = false
h:RunTimers()
CheckStatus("disconnected read during the roster update")
-- A new slot must be born in the same native dispatch in the open world.
-- The addon must still defer its protected layout pass until regen.
local liveOpenWorld = flavor == "Mainline" or flavor == "Forever"
local function EnterZone(location, event)
    instanceType = location
    h:Event(event or "ZONE_CHANGED_NEW_AREA")
    h:RunTimers()
end
-- Reproduce the visible native button whose cached OnShow state is still false
-- when the cold live structure attaches in combat.
local attach = h.UF.AttachFrame
h.UF.AttachFrame = function(frame, options)
    local result = attach(frame, options)
    if instanceType == "none" and h.env.InCombatLockdown() and frame.MSUFUnitKey and options and options.scope == "group" then
        frame._msufCoreVisible = false
        frame._msufCoreEventsSuspended = true
    end
    return result
end
local function AssertCombatPaint(unit, memberName)
    local child = assert(GF.FrameForUnit(unit), "combat join was not bound")
    assert(child:GetAttribute("unit") == unit and child.MSUFUnitKey == unit, "visual/click unit mismatch")
    assert(child:IsVisible() and child._msufCoreVisible == true and not child._msufCoreEventsSuspended,
        "visible combat slot kept stale show state")
    assert(child.hpBar, "new combat slot has no health bar")
    assert(child.nameText and child.nameText:GetText() == memberName,
        flavor .. ": new combat slot has no painted name")
    if memberName ~= "Joiner" then
        local hp = child.hpTextLeft or child.hpTextCenter or child.hpTextRight
        assert(hp and type(hp:GetText()) == "string" and hp:GetText() ~= "", "new Party slot has no painted HP text")
    end
    assert(h.env.InCombatLockdown() == true and #h.violations == 0, "combat join wrote protected state")
    return child
end
members.raid3 = { "Joiner", "MAGE", false }
conf.sortMode, conf.showPlayer = "INDEX", true
for _, location in ipairs({ "none", "raid", "party", "pvp", "arena", "scenario", "none" }) do
    EnterZone(location, location == "raid" and "PLAYER_ENTERING_WORLD" or nil)
    h:SetRaid(2)
    Roster()
    local beforePull = runtimeZoneReads
    h:EnterCombat(function()
        assert(GF._raidRosterCombatActive, "pre-lockdown layout guard was not armed")
    end)
    local immediate = liveOpenWorld and location == "none"
    assert(runtimeZoneReads == beforePull + (immediate and 1 or 0), flavor .. "/" .. location .. ": wrong zone reads at pull")
    local reused = assert(GF.FrameForUnit("raid1"))
    if immediate then
        reused._msufCoreVisible = false
        reused._msufCoreEventsSuspended = true
    end
    local beforeZoneReads = runtimeZoneReads
    h:SetRaid(3)
    h:Event("GROUP_ROSTER_UPDATE")
    local child = GF.headers.raid:GetAttribute("child3")
    assert((child ~= nil and child:GetAttribute("unit") == "raid3") == immediate,
        flavor .. "/" .. location .. ": wrong secure Raid join timing")
    h:RunTimers()
    if immediate then
        local frame = AssertCombatPaint("raid3", "Joiner")
        assert(frame._msufStatusTextValue == "OFFLINE", "combat join did not paint status text")
        assert(reused._msufCoreVisible == true and not reused._msufCoreEventsSuspended,
            "already bound slot did not recover after native show")
    else
        assert(runtimeZoneReads == beforeZoneReads, "instance or Classic roster polled the zone")
        assert(GF.FrameForUnit("raid3") == nil, "instance or Classic raid updated before regen")
    end
    assert(#h.violations == 0, "join wrote protected state: " .. tostring(h.violations[1]))
    h:LeaveCombat()
    h:RunTimers()
    assert(GF.FrameForUnit("raid3"), "regen failed to catch up the raid roster")
end

-- Raid-wide roles can assign a player from subgroup 2 to block 1. Switching
-- to native subgroup membership here would remove an existing member.
instanceType = "none"
conf.preserveRaidGroups, conf.sortRolesAcrossRaid, conf.maxColumns = true, true, 1
conf.sortMode = "ROLE"
h:SetRaid(2)
Roster()
local roleBlock = assert(GF.headers.raid)
local roleList = assert(roleBlock:GetAttribute("nameList"), "raid-wide roles need a name list")
h:EnterCombat()
assert(roleBlock:GetAttribute("nameList") == roleList, "combat changed raid-wide role block membership")
h:LeaveCombat()
h:RunTimers()

-- Party normally has no secure header while solo. Prepare one before
-- lockdown only outdoors, and keep the existing instance behavior.
local party = GF.GetConf("party")
party.enabled, party.showSolo, party.showPlayer = true, false, false
party.sortMode = "INDEX"
members.party1, members.party2 = { "PartyOne", "MAGE" }, { "PartyTwo", "WARRIOR" }
for _, location in ipairs({ "none", "party" }) do
    EnterZone(location)
    h:SetRoster({ "player" })
    Roster()
    assert(GF.headers.party == nil, "solo should not start with a Party header")
    h:EnterCombat()
    local immediate = liveOpenWorld and location == "none"
    assert((GF.headers.party ~= nil) == immediate, "wrong Party standby scope")
    assert(GF.FrameForUnit("player") == nil, "standby displayed the solo player")
    if immediate then
        h:LeaveCombat()
        h:RunTimers()
        assert(GF.headers.party == nil, "unused Party standby survived combat")
        h:EnterCombat()
    end
    -- With Show Player off, the first join fills the header's hidden standby slot.
    local standby = immediate and GF.headers.party:GetAttribute("child1")
    if immediate then assert(standby and not standby:IsShown(), "standby slot should begin hidden") end
    h:SetRoster({ "player", "party1" })
    h:Event("GROUP_ROSTER_UPDATE")
    if immediate then
        h:SetRoster({ "player" })
        h:Event("GROUP_ROSTER_UPDATE")
        h:RunTimers()
        assert(not GF.FrameForUnit("party1"), "left member was bound from a pending slot")
        h:SetRoster({ "player", "party1" })
        h:Event("GROUP_ROSTER_UPDATE")
    end
    h:RunTimers()
    if immediate then
        assert(AssertCombatPaint("party1", "PartyOne") == standby, "first join did not reuse the hidden standby slot")
    else
        assert(GF.FrameForUnit("party1") == nil, "wrong first Party join timing")
    end
    h:LeaveCombat()
    h:RunTimers()
    assert(GF.FrameForUnit("party1"), "regen failed to catch up the Party roster")
end

CheckConsumption("party", "party1")

-- The ordinary Party event already works with a native sort. A custom order
-- using a static name filter needs a live sort in combat and restoration
-- after regen, including a fight with no roster changes.
EnterZone("none")
party.sortMode, party.playerFirstInRole = "ROLE", true
Roster()
local partyHeader = assert(GF.headers.party)
assert(partyHeader:GetAttribute("nameList"), "Party name-list fixture missing")
h:EnterCombat()
assert((partyHeader:GetAttribute("nameList") == nil) == liveOpenWorld, "wrong Party live sort scope")
h:LeaveCombat()
h:RunTimers()
assert(partyHeader:GetAttribute("nameList"), "regen did not restore Party sort")
h:EnterCombat()
h:SetRoster({ "player", "party1", "party2" })
h:Event("GROUP_ROSTER_UPDATE")
h:RunTimers()
if liveOpenWorld then
    AssertCombatPaint("party2", "PartyTwo")
else
    assert(GF.FrameForUnit("party2") == nil, "wrong custom Party join timing")
end
h:LeaveCombat()
h:RunTimers()
assert(GF.FrameForUnit("party2") and partyHeader:GetAttribute("nameList"), "Party sort or roster not restored")
assert(#h.violations == 0, "join wrote protected state: " .. tostring(h.violations[1]))

if liveOpenWorld then
    -- An already active instance Party keeps its existing roster route.
    EnterZone("party")
    party.sortMode, party.playerFirstInRole = "INDEX", false
    Roster()
    h:EnterCombat()
    local instanced = assert(GF.FrameForUnit("party1"))
    instanced._msufCoreVisible = false
    local before = runtimeZoneReads
    Roster()
    assert(instanced._msufCoreVisible == false, "open-world reconciliation ran in an instance")
    assert(runtimeZoneReads == before, "instance Party polled the zone")
    h:LeaveCombat()
    h:RunTimers()

    -- A loading screen invalidates the open-world selection before entry.
    EnterZone("none")
    h:Event("PLAYER_LEAVING_WORLD")
    instanceType = "party"
    local beforePull = runtimeZoneReads
    h:EnterCombat()
    assert(runtimeZoneReads == beforePull and not GF._openWorldCombatRoster, "loading transition retained the world handler")
    h:LeaveCombat()
    h:RunTimers()

    -- A stale world selection may check the location, but must freeze as usual.
    EnterZone("none")
    instanceType = "party"
    beforePull = runtimeZoneReads
    h:EnterCombat()
    assert(runtimeZoneReads == beforePull + 1 and not GF._openWorldCombatRoster, "stale world handler did not fall back")
    h:LeaveCombat()
    h:RunTimers()

    -- A queued world binding cannot drain after an instance transition.
    EnterZone("none")
    members.party3 = { "LateJoin", "MAGE" }
    h:EnterCombat()
    h:SetRoster({ "player", "party1", "party2", "party3" })
    h:Event("GROUP_ROSTER_UPDATE")
    assert(not GF.FrameForUnit("party3"), "new unit should still be queued before settle")
    instanceType = "party"
    h:RunTimers()
    assert(not GF.FrameForUnit("party3") and not GF._openWorldCombatRoster, "world queue leaked into an instance")
    h:LeaveCombat()
    h:RunTimers()
end

print("group_roster_identity_status_smoke: PASS (" .. flavor .. "/" .. kind .. ": names/bar/background colors, OFFLINE status, roster ordering, coalesced bursts, combat, GUID-free roster path, hidden/preview, recycle)")
