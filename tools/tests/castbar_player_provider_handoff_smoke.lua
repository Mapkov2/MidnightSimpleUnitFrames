-- The real Player Frame switch, profile application and deferred player castbar ownership.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2])
local MenuWorld = dofile(root .. "/tools/tests/menu_core_world.lua")
local native, registrations, suppressions
local menu = MenuWorld.Open(root, flavor, {
    page = "uf_player", clientScriptBindings = true, tocMetadata = true, keepFlush = true, locale = arg[3],
    beforeCore = function(world)
        MenuWorld.InstallNativeUnitInputs(world)
        local env = world.env
        native = env.CreateFrame("StatusBar", "PlayerCastingBarFrame", env.UIParent)
        env.PlayerCastingBarFrame = native
        native.unit = "player"
        native.SetUnit = function() error("handoff must not call Blizzard SetUnit") end
        native:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
        native:Hide()
        local register, unregister, unregisterEvent = native.RegisterUnitEvent, native.UnregisterAllEvents, native.UnregisterEvent
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
        function native:UnregisterEvent(event)
            assert(not env.InCombatLockdown(), "native castbar event unregistered during combat")
            return unregisterEvent(self, event)
        end
    end,
    beforeOptions = function(world)
        world:LoadSavedVariables("MidnightSimpleUnitFrames", {
            MSUF_GlobalDB = {
                profiles = { ["Force Off at login"] = {
                    _msufProfileSchema = world.core.ProfilePolicy.CurrentSchema,
                    player = { enabled = false },
                    general = { castbarPlayerBackend = "FORCE_OFF", enablePlayerCastbar = false },
                } },
                char = { ["Tester-Realm"] = { activeProfile = "Force Off at login" } },
            },
        })
        assert(world.env.MSUF_DB.player.enabled == false, "fixture did not bind the saved disabled player frame")
        world:FireEvent("PLAYER_LOGIN")
        assert(world.core.Castbars.Config.Read("player").backend == "HIDE", "saved Force Off lost at login")
        assert(native.events.UNIT_SPELLCAST_START == nil, "startup re-enabled the forced-off Blizzard castbar")
    end,
})
local world, env, core, M = menu.world, menu.env, menu.core, menu.M
local castbars, apply = core.Castbars, core.ApplyService
local function Settle()
    menu:RunTimers()
    apply.Flush()
    menu:RunTimers()
end
M.GetContentMetrics = function() return 720, 700 end
M.InvalidatePage("uf_player")
assert(M.SelectPage("uf_player"), "player page did not reopen at the narrow fixture width")
local function ReadControl(id)
    local record = assert(M.RuntimeControlCatalog.Get("menu2.uf_player.unit." .. id), id)
    return record.widget, assert(record.widget._msuf2CommandAction, id)
end
local section, castbarEntry, frameSwitch, provider, providerAction
local function BindCastbarControls()
    section = assert(M.cache.uf_player.sections.castbar)
    castbarEntry = assert(section._msuf2CollapsibleEntry)
    M.Widgets.EnsureSectionContent(section)
    Settle()
    local _
    _, frameSwitch = ReadControl("basics.enabled")
    provider, providerAction = ReadControl("castbar.provider")
end
BindCastbarControls()

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
    M.Refresh()
    ExpectBackend(backend)
end
local function SetFrameEnabled(enabled)
    frameSwitch.set(enabled)
    Settle()
    assert((env.MSUF_DB.player.enabled ~= false) == enabled, "frame switch did not write profile")
end
local function SelectProvider(value, disabled)
    castbarEntry.SetOpenImmediate(true)
    Settle()
    assert(provider:IsEnabled(), "player cannot reach the provider selector")
    provider:Click()
    for _, row in ipairs(world.widgets.frames) do
        if row:IsShown() and row._msuf2Owner == provider and row._msuf2Value == value then
            assert(not not row._msuf2DropdownDisabled == not not disabled, "provider option has wrong availability: " .. value)
            row:Click()
            M.Widgets.CloseDropdown({ immediate = true })
            Settle()
            return
        end
    end
    error("provider item missing: " .. value)
end
local function FindText(parent, key)
    local text = M.Tr(key)
    for _, region in ipairs({ parent:GetRegions() }) do
        if region.GetText and region:GetText() == text then return region end
    end
end
local function ExpectForceOff()
    ExpectBackend("HIDE")
    assert(providerAction.get() == "FORCE_OFF" and provider:IsEnabled(), "provider lost the selected Force Off value")
    assert(env.MSUF_DB.general.castbarPlayerBackend == "FORCE_OFF", "Force Off was not preserved in the profile")
    assert(env.MSUF_DB.general.enablePlayerCastbar == false, "Force Off left the legacy MSUF castbar enabled")
    local tone = assert(castbarEntry._msuf2HeaderBaseColor, "Force Off has no accordion background")
    assert(tone[1] > tone[2] and tone[1] > tone[3], "Force Off accordion background is not red")
    local status = assert(FindText(castbarEntry.header, "FORCE OFF"), "Force Off header has no status text")
    assert(status:IsShown(), "Force Off is not shown on the accordion header")
    local font = assert(status:GetFont(), "Force Off status must use the bundled bold font")
    assert(font:lower():find("bold.ttf", 1, true), "Force Off header status is not bold")
    assert(status:GetStringWidth() <= status:GetWidth(), "Force Off header status overflows")
    assert(castbarEntry.header:GetAlpha() == 1 and not castbarEntry.openHighlightEnabled,
        "the standard gate or open highlight masks the red Force Off background")
end
local function CheckWarningBounds()
    local card = provider:GetParent()
    local warning = "Blizzard castbar is forced off. Without another castbar addon, you may have no player castbar."
    local notice, message
    for _, child in ipairs({ card:GetChildren() }) do
        message = FindText(child, warning)
        if message then
            notice = child
            break
        end
    end
    assert(notice and message.wordWrap, "Force Off warning is missing its text or wrapping")
    assert(notice:IsShown(), "Force Off warning missing in General")
    local _, _, _, left, top = notice:GetPointByName("TOPLEFT")
    local _, _, _, right = notice:GetPointByName("TOPRIGHT")
    local _, _, _, textLeft = message:GetPointByName("LEFT")
    local _, _, _, textRight = message:GetPointByName("RIGHT")
    assert(left >= 0 and right <= 0 and -top + notice:GetHeight() <= card:GetHeight(),
        "Force Off warning overflows the provider card")
    local warningWidth = card:GetWidth() + right - left + textRight - textLeft
    local lines = math.ceil(message:GetStringWidth() / warningWidth)
    assert(warningWidth > 0 and lines <= message.maxLines and lines * message:GetStringHeight() <= notice:GetHeight(),
        "Force Off warning text cannot fit the reserved area at a narrow menu width")
    local _, _, _, x, y = provider:GetPoint()
    assert(x >= 0 and x + provider:GetWidth() <= card:GetWidth() and y - provider:GetHeight() >= top,
        "Force Off warning overlaps the provider selector or the selector overflows")
    return notice
end
ExpectForceOff()
local warningNotice = CheckWarningBounds()
SelectProvider("MSUF", true)
ExpectForceOff()
SelectProvider("BLIZZARD")
ExpectBackend("BLIZZARD")
assert(not castbarEntry._msuf2HeaderBaseColor and not assert(FindText(castbarEntry.header, "FORCE OFF")):IsShown(),
    "returning to Blizzard kept the red Force Off warning")
assert(not warningNotice:IsShown(), "returning to Blizzard kept the Force Off body warning")
castbars.Previews.SetPlayerCastbarTestMode(false, true)
ExpectBackend("BLIZZARD")
SetFrameEnabled(true)
SelectProvider("MSUF")
ExpectBackend("MSUF")

for _, preferred in ipairs({ "MSUF", "BLIZZARD", "HIDE" }) do
    Choose(preferred)
    local before, priorSuppressions = registrations, suppressions
    SetFrameEnabled(false)
    ExpectBackend("BLIZZARD")
    assert(providerAction.get() == "BLIZZARD" and provider:IsEnabled(), "provider must display the Blizzard fallback and allow Force Off")
    assert(env.MSUF_DB.general.castbarPlayerBackend == preferred, "forced backend overwrote preference")
    assert(env.MSUF_DB.general.enablePlayerCastbar == (preferred == "MSUF"), "forced backend overwrote legacy preference")
    providerAction.set("MSUF")
    assert(env.MSUF_DB.general.castbarPlayerBackend == preferred, "disabled Player frame accepted the MSUF provider")
    SetFrameEnabled(true)
    ExpectBackend(preferred)
    if preferred == "BLIZZARD" then
        assert(registrations == before and suppressions == priorSuppressions, "Blizzard ownership changed without a provider transition")
    else
        assert(registrations == before + 13, "Blizzard release did not restore the canonical unit events exactly once")
    end
end

Choose("MSUF")
SelectProvider("FORCE_OFF")
ExpectForceOff()
local castbarSwitch, castbarToggle = ReadControl("castbar.enabled")
assert(not castbarSwitch:IsEnabled(), "ordinary Enable Castbar switch can bypass Force Off")
castbarToggle.set(true)
Settle()
ExpectForceOff()
castbarEntry.SetOpenImmediate(false)
Settle()
assert(not castbarEntry.open, "castbar accordion fixture did not collapse")
ExpectForceOff()
SetFrameEnabled(false)
ExpectForceOff()
SelectProvider("BLIZZARD")
ExpectBackend("BLIZZARD")
SelectProvider("FORCE_OFF")
ExpectForceOff()
SetFrameEnabled(true)
ExpectForceOff()
SelectProvider("MSUF")
ExpectBackend("MSUF")

-- Force Off must leave an already externally suppressed Blizzard castbar muted
-- when the user switches back to the Blizzard provider.
Choose("BLIZZARD")
native:UnregisterAllEvents()
local beforeRelease = registrations
SelectProvider("FORCE_OFF")
ExpectForceOff()
SelectProvider("BLIZZARD")
assert(native.events.UNIT_SPELLCAST_START == nil and registrations == beforeRelease,
    "leaving Force Off undid another addon's native castbar suppression")
native:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")

Choose("HIDE")
SetFrameEnabled(false)
M.ClearHistory()
SelectProvider("FORCE_OFF")
ExpectForceOff()
assert(M.Undo(), "provider change to Force Off cannot be undone")
Settle()
BindCastbarControls()
ExpectBackend("BLIZZARD")
assert(env.MSUF_DB.general.castbarPlayerBackend == "HIDE", "Force Off Undo lost the ordinary hidden preference")
assert(M.Redo(), "provider change to Force Off cannot be redone")
Settle()
BindCastbarControls()
ExpectForceOff()
SetFrameEnabled(true)
SelectProvider("MSUF")
ExpectBackend("MSUF")
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

Choose("BLIZZARD")
world:EnterCombat()
for _, backend in ipairs({ "FORCE_OFF", "BLIZZARD", "FORCE_OFF" }) do
    castbars.Backend.Set("player", backend, env.MSUF_DB.general)
    assert(apply.RequestCastbarUnit("player", "CASTBAR_TEST_FORCE_OFF"))
    assert(apply.Flush(), "Force Off was not queued during combat")
    assert(native.events.UNIT_SPELLCAST_START, "Force Off changed native event ownership before combat ended")
end
world:LeaveCombat()
Settle()
ExpectBackend("HIDE")
Choose("MSUF")

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
saved.general.castbarPlayerBackend = "FORCE_OFF"
saved.general.enablePlayerCastbar = false
saved.player.enabled = false
assert(profiles.MSUF_SwitchProfile("Disabled player"))
Settle()
BindCastbarControls()
ExpectForceOff()
assert(profiles.MSUF_SwitchProfile(original))
Settle()
ExpectBackend("MSUF")
print("PASS player castbar provider handoff: " .. flavor)
