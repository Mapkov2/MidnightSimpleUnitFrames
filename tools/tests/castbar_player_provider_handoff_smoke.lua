-- The real Player Frame switch, profile application and deferred player castbar ownership.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2])
local MenuWorld = dofile(root .. "/tools/tests/menu_core_world.lua")
local native, registrations, suppressions
local menu = MenuWorld.Open(root, flavor, {
    page = "uf_player", clientScriptBindings = true, tocMetadata = true, keepFlush = true,
    beforeCore = function(world)
        MenuWorld.InstallNativeUnitInputs(world)
        local env = world.env
        native = env.CreateFrame("StatusBar", "PlayerCastingBarFrame", env.UIParent)
        env.PlayerCastingBarFrame = native
        native.unit = "player"
        native.SetUnit = function() error("handoff must not call Blizzard SetUnit") end
        native:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
        native:Hide()
        local register, unregister = native.RegisterUnitEvent, native.UnregisterAllEvents
        registrations, suppressions = 0, 0
        function native:RegisterUnitEvent(...)
            assert(not env.InCombatLockdown(), "native castbar registered during combat")
            registrations = registrations + 1
            return register(self, ...)
        end
        function native:UnregisterAllEvents()
            assert(not env.InCombatLockdown(), "native castbar unregistered during combat")
            suppressions = suppressions + 1
            return unregister(self)
        end
    end,
    beforeOptions = function(world)
        world:LoadSavedVariables("MidnightSimpleUnitFrames", {})
        world.env.MSUF_DB.player.enabled = false
        world:FireEvent("PLAYER_LOGIN")
    end,
})
local world, env, core, M = menu.world, menu.env, menu.core, menu.M
local castbars, apply = core.Castbars, core.ApplyService
local function Settle()
    menu:RunTimers()
    apply.Flush()
    menu:RunTimers()
end
local function ReadControl(id)
    local record = assert(M.RuntimeControlCatalog.Get("menu2.uf_player.unit." .. id), id)
    return record.widget, assert(record.widget._msuf2CommandAction, id)
end
local sections = assert(M.cache.uf_player.sections)
M.Widgets.EnsureSectionContent(assert(sections.castbar))
Settle()
local _, frameSwitch = ReadControl("basics.enabled")
local provider, providerAction = ReadControl("castbar.provider")

local function ExpectBackend(expected)
    assert(castbars.Config.Read("player").backend == expected, flavor .. ": expected player backend " .. expected)
    assert((native.events.UNIT_SPELLCAST_START ~= nil) == (expected == "BLIZZARD"), "native event ownership differs")
    local player = castbars.Frames.Get("player")
    assert((player and player.events.UNIT_SPELLCAST_START ~= nil or false) == (expected == "MSUF"), "MSUF event ownership differs")
    if expected ~= "MSUF" then
        assert(not player or (not player:IsShown() and player:GetScript("OnUpdate") == nil), "MSUF left an active castbar")
    end
end
local function Choose(backend)
    castbars.Backend.Set("player", backend, env.MSUF_DB.general)
    apply.RequestCastbarUnit("player", "CASTBAR_TEST_PROVIDER")
    Settle()
    ExpectBackend(backend)
end
local function SetFrameEnabled(enabled)
    frameSwitch.set(enabled)
    Settle()
    assert((env.MSUF_DB.player.enabled ~= false) == enabled, "frame switch did not write profile")
end
ExpectBackend("BLIZZARD")
castbars.Previews.SetPlayerCastbarTestMode(false, true)
ExpectBackend("BLIZZARD")
SetFrameEnabled(true)
ExpectBackend("MSUF")

for _, preferred in ipairs({ "MSUF", "BLIZZARD", "HIDE" }) do
    Choose(preferred)
    local before, priorSuppressions = registrations, suppressions
    SetFrameEnabled(false)
    ExpectBackend("BLIZZARD")
    assert(providerAction.get() == "BLIZZARD" and not provider:IsEnabled(), "provider control did not show locked Blizzard")
    assert(env.MSUF_DB.general.castbarPlayerBackend == preferred, "forced backend overwrote preference")
    assert(env.MSUF_DB.general.enablePlayerCastbar == (preferred == "MSUF"), "forced backend overwrote legacy preference")
    providerAction.set("BLIZZARD")
    assert(env.MSUF_DB.general.castbarPlayerBackend == preferred, "disabled provider control changed preference")
    SetFrameEnabled(true)
    ExpectBackend(preferred)
    if preferred == "BLIZZARD" then
        assert(registrations == before and suppressions == priorSuppressions, "Blizzard ownership changed without a provider transition")
    else
        assert(registrations == before + 13, "Blizzard release did not restore the canonical unit events exactly once")
    end
end

Choose("MSUF")
M.ClearHistory()
assert(M.BeginHistoryTransaction("player frame", "menu", nil))
frameSwitch.set(false)
M.CommitHistoryTransaction()
Settle()
ExpectBackend("BLIZZARD")
assert(M.Undo(), "frame disable could not be undone")
Settle()
ExpectBackend("MSUF")
assert(M.Redo(), "frame disable could not be redone")
Settle()
ExpectBackend("BLIZZARD")
SetFrameEnabled(true)

-- Direct requests exercise the combat queue. Opening or editing the menu is
-- separately locked in combat, but imports and deferred requests can arrive.
world:EnterCombat()
local before = registrations
for _, enabled in ipairs({ false, true, false }) do
    env.MSUF_DB.player.enabled = enabled
    assert(apply.RequestUnitDomains("player", "CASTBAR_TEST_FRAME"))
    assert(apply.Flush(), "setting was not queued during combat")
    ExpectBackend("MSUF")
    assert(registrations == before, "native bar released before combat ended")
end
world:LeaveCombat()
Settle()
ExpectBackend("BLIZZARD")
assert(registrations == before + 13, "combat queue applied more than its final switch")
SetFrameEnabled(true)
ExpectBackend("MSUF")

-- The original backend remains live if changes in the queue cancel out.
world:EnterCombat()
before = registrations
env.MSUF_DB.player.enabled = false
apply.RequestUnitDomains("player", "CASTBAR_TEST_FRAME")
env.MSUF_DB.player.enabled = true
apply.RequestUnitDomains("player", "CASTBAR_TEST_FRAME")
world:LeaveCombat()
Settle()
ExpectBackend("MSUF")
assert(registrations == before, "net-zero change released the native castbar")

-- A deferred native apply must retire its combat-end listener after one drain.
local nativeApply, nativeApplies = castbars.NativeOwner.Apply, 0
function castbars.NativeOwner:Apply()
    nativeApplies = nativeApplies + 1
    return nativeApply(self)
end
world:EnterCombat()
castbars.NativeOwner:Apply()
world:LeaveCombat()
assert(nativeApplies == 2, "native ownership did not drain once")
world:EnterCombat()
world:LeaveCombat()
assert(nativeApplies == 2, "native ownership stayed subscribed to combat end")
castbars.NativeOwner.Apply = nativeApply

-- Bind an older profile whose player frame was already disabled.
local profiles = core.PublicGlobals
local original = env.MSUF_ActiveProfile
assert(original and env.MSUF_GlobalDB.profiles[original] == env.MSUF_DB, "no active login profile")
local saved = env.CopyTable(env.MSUF_DB)
env.MSUF_GlobalDB.profiles["Disabled player"] = saved
saved.player.enabled = false
saved.general.castbarPlayerBackend = nil
saved.general.enablePlayerCastbar = true
assert(profiles.MSUF_SwitchProfile("Disabled player"))
Settle()
ExpectBackend("BLIZZARD")
assert(env.MSUF_DB.general.castbarPlayerBackend == "MSUF", "legacy preference was not retained")
SetFrameEnabled(true)
ExpectBackend("MSUF")
SetFrameEnabled(false)
assert(profiles.MSUF_SwitchProfile(original))
Settle()
ExpectBackend("MSUF")
print("PASS player castbar provider handoff: " .. flavor)
