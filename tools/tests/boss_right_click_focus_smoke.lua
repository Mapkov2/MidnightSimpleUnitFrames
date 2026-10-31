-- Native boss/arena right-click actions, profile lifecycle and menu integration.
-- The client sandbox models state-driver writes as secure and rejects addon
-- attribute writes in lockdown. Rendering and real client taint need a live test.
local root, flavor = assert(arg[1]), assert(arg[2])
local scope = arg[3] or "boss"
assert(scope == "boss" or scope == "arena")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local world = World.New(root, flavor)
local env = world.env
local combat, secure = false, false
local drivers, registrations, removals = {}, 0, 0
env.InCombatLockdown = function() return combat end
local function Resolve(frame, attribute, expression)
    local yes, no = expression:match("^%[combat%] ([^;]+); (.+)$")
    assert(yes and no, "unexpected native combat expression")
    secure = true
    frame:SetAttribute(attribute, combat and yes or no)
    secure = false
end
env.RegisterAttributeDriver = function(frame, attribute, expression)
    assert(not combat, "registered driver in lockdown")
    drivers[frame] = drivers[frame] or {}
    drivers[frame][attribute] = expression
    registrations = registrations + 1
    Resolve(frame, attribute, expression)
end
env.UnregisterAttributeDriver = function(frame, attribute)
    assert(not combat, "removed driver in lockdown")
    if drivers[frame] then drivers[frame][attribute] = nil end
    removals = removals + 1
end
world:Boot()
local failure = world:FirstFailure()
assert(not failure, failure and failure.message)
local UF = world.core.UF
env.MSUF_EnsureDB(true)
local db = UF.Config.GetDB()
assert(db[scope].rightClickFocusInCombat == false, "fresh profiles must opt in")
local originalSet = world.widgets.Methods.SetAttribute
world.widgets.Methods.SetAttribute = function(frame, key, value)
    assert(not combat or secure, "insecure protected write in combat: " .. key)
    return originalSet(frame, key, value)
end
-- The real Factory configures clicks; unrelated health rendering needs live data.
UF.ApplySpec = function() return true end
local function Apply()
    UF.Config.Refresh()
    return UF.Factory.Apply(scope)
end
local function Combat(value)
    combat = value
    for frame, attrs in pairs(drivers) do
        for attribute, expression in pairs(attrs) do Resolve(frame, attribute, expression) end
    end
end
local supported = world.core.Client.SupportsUnit(scope .. "1")
local count = scope == "arena" and world.core.Client.MaxArenaOpponents or 5
if supported then
    -- Precreate the native buttons: unknown global frame names deliberately
    -- resolve to permissive sentinels in client_world's load-only harness.
    local units = { "target" }
    for i = 1, count do units[#units + 1] = scope .. i end
    local other = scope == "boss" and "arena" or "boss"
    if world.core.Client.SupportsUnit(other .. "1") then
        local otherCount = other == "arena" and world.core.Client.MaxArenaOpponents or 5
        for i = 1, otherCount do units[#units + 1] = other .. i end
    end
    for _, unit in ipairs(units) do
        local frame = env.CreateFrame("Button", nil, env.UIParent)
        frame.MSUFUnitKey = unit
        UF.frames[unit] = frame
    end
    Apply()
    for i = 1, count do
        local f = assert(UF.frames[scope .. i], "missing boss button")
        assert(f:GetAttribute("*type2") == "togglemenu", "opt-out lost context menu")
        assert(f:GetAttribute("*type1") == "target", "left click changed")
    end
    assert(registrations == 0, "opt-out registered drivers")
    db[scope].rightClickFocusInCombat = true
    Apply()
    assert(registrations == count, "each boss needs exactly one driver: " .. registrations
        .. " current=" .. tostring(env.MSUF_DB[scope].rightClickFocusInCombat)
        .. " original=" .. tostring(db[scope].rightClickFocusInCombat))
    Apply()
    assert(registrations == count, "reapply registered duplicate drivers")
    UF.Factory.Apply("target")
    assert(not drivers[UF.frames.target], "non-boss frame got a focus driver")
    if UF.frames[other .. "1"] then
        UF.Factory.Apply(other)
        assert(not drivers[UF.frames[other .. "1"]], "boss and arena settings are coupled")
    end
    for round = 1, 2 do
        Combat(true)
        for i = 1, count do
            local f = UF.frames[scope .. i]
            assert(f:GetAttribute("*type2") == "focus", "combat click opens menu")
            assert(f:GetAttribute("unit") == scope .. i, "focus uses wrong boss")
            assert(f:GetAttribute("*type1") == "target", "combat changed left click")
        end
        Combat(false)
        assert(UF.frames[scope .. "1"]:GetAttribute("*type2") == "togglemenu", "combat exit lost menu")
    end
    -- A profile/setting change in combat is deferred by the existing Factory.
    Combat(true)
    db[scope].rightClickFocusInCombat = false
    Apply()
    assert(removals == 0 and UF.frames[scope .. "1"]:GetAttribute("*type2") == "focus", "combat apply mutated clicks")
    Combat(false)
    Apply()
    assert(removals == count, "disabling did not remove every boss driver")
    Combat(true)
    assert(UF.frames[scope .. "1"]:GetAttribute("*type2") == "togglemenu", "disabled driver still runs")
    Combat(false)
    -- Exact modifier click-cast actions keep priority; reapply must preserve them.
    UF.frames[scope .. "1"]:SetAttribute("shift-type2", "spell")
    db[scope].rightClickFocusInCombat = true
    Apply()
    assert(UF.frames[scope .. "1"]:GetAttribute("shift-type2") == "spell", "modifier binding overwritten")
    -- Replacing the profile table must use its setting on the next apply.
    local replacement = {}
    for key, value in pairs(db) do replacement[key] = value end
    replacement[scope] = {}
    for key, value in pairs(db[scope]) do replacement[scope][key] = value end
    replacement[scope].rightClickFocusInCombat = false
    env.MSUF_DB = replacement
    Apply()
    assert(removals == count * 2, "profile replacement did not disable focus")
end

-- Build actual General/Basics controls and invoke the bound setting command.
local fixture = assert(loadfile(root .. "/tools/tests/bh3_menu_page_fixture.lua"))()
fixture.BuildPage("uf_target")
assert(not fixture.registered.uf_target["target.rightClickFocusInCombat"], "toggle leaks onto target page")
if supported then
    local entry = fixture.BuildPage("uf_" .. scope)
    local control = assert(fixture.registered["uf_" .. scope][scope .. ".rightClickFocusInCombat"], "boss toggle not registered")
    assert(control.command and control.command.set, "boss toggle has no setter")
    control.command.set(true)
    assert(fixture.env.MSUF_DB[scope].rightClickFocusInCombat == true, "menu did not save opt-in")
    control.command.set(false)
    assert(fixture.env.MSUF_DB[scope].rightClickFocusInCombat == false, "menu did not save opt-out")
    control.command.set(true)
    fixture.RunRefreshers(entry)
    -- The offline client has no native CBOR decoder for the factory export.
    -- Supply the default already verified through the real defaults stage above.
    fixture.M.UnitSectionsShared.FactoryProfile = function()
        return { [scope] = { rightClickFocusInCombat = false } }
    end
    local section = assert(entry.sections.frame_basics)
    local more = assert(section._msuf2CollapsibleEntry._msuf2SectionActions)
    more:GetScript("OnClick")(more)
    assert(more._msuf2GetSectionPopup()._msuf2ResetSection(), "boss Basics reset refused")
    assert(fixture.env.MSUF_DB[scope].rightClickFocusInCombat ~= true, "boss Basics reset left focus enabled")
end
print(scope .. " right-click focus: PASS (" .. flavor .. ")")
