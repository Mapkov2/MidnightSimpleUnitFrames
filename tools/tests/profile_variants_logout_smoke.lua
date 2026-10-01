-- Logout never saves a variant overlay or an unsaved recording as the base
-- profile (review F6). The logout steps that run provider (Suite) code come
-- after the MSUF settings are back to their base, so a provider error in the
-- sync flush or in the recording restore cannot persist the overlay.
-- Usage: lua tools/tests/profile_variants_logout_smoke.lua <repoRoot>
local root = assert(arg[1], "repo root required")
local NS = { Client = { SupportsEvent = function() return true end } }
function InCombatLockdown() return false end
function IsInInstance() return false, "none" end
function IsInGroup() return false end
function MSUF_GetPlayerSpecID() return 63 end
local frames = {}
function CreateFrame()
    local f = { events = {} }
    function f:SetScript(_, fn) self.event = fn end
    function f:RegisterEvent(e) self.events[e] = true end
    function f:UnregisterAllEvents() self.events = {} end
    frames[#frames + 1] = f
    return f
end
for _, file in ipairs({ "MSUF_ProfileFields", "MSUF_ProfileExternal", "MSUF_ProfileVariants", "MSUF_ProfileSync",
    "MSUF_ProfileVariantEditor", "MSUF_ProfileVariantsRuntime" }) do
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/State/" .. file .. ".lua"))("MSUF", NS)
end
local V, S, F = NS.ProfileVariants, NS.ProfileSync, NS.ProfileFields
NS.ProfileRuntime = { Apply = function() if not V.IsRecording() then V.ResolveCurrent() end end }
local store, raiseSnapshot, raiseRestore = {}, false, false
F.RegisterExternal("suiteModules", {
    Resolve = function(name, create)
        if create and store[name] == nil then store[name] = {} end
        return store[name]
    end,
    Snapshot = function(source)
        if raiseSnapshot then error("provider snapshot failed") end
        return source, true
    end,
    Restore = function(target, copy)
        if raiseRestore then error("provider restore failed") end
        for k in pairs(target) do target[k] = nil end
        for k, v in pairs(copy) do target[k] = v end
        return true
    end,
})
local base = { general = {}, player = { width = 120 } }
local other = { general = {}, player = { width = 120 } }
MSUF_GlobalDB = { profiles = { A = base, B = other }, global = {} }
MSUF_ActiveProfile, MSUF_DB = "A", base
assert(S.Replace({ { name = "G", members = { A = true, B = true }, modules = { unitframes = true } } }))
local framesBefore = #frames
assert(V.Replace(base, { version = 1, entries = {
    { name = "Always", patch = { { path = { "player", "width" }, value = 200 } } },
    { name = "Edit", conditions = { manual = true }, patch = { { path = { "player", "height" }, value = 30 } } },
} }))
assert(base.player.width == 200, "the variant overlay is not active")
-- The variants driver is the frame the first variant created.
local driver = frames[framesBefore + 1]
assert(driver and driver.events.PLAYER_LOGOUT and driver.event, "no variants logout handler")

-- (1) Overlay active, the sync flush raises inside provider code.
raiseSnapshot = true
pcall(driver.event, driver, "PLAYER_LOGOUT")
raiseSnapshot = false
assert(base.player.width == 120, "a provider error at logout saved the variant overlay as the base")

-- (2) Unsaved recording, the provider restore raises.
V.ResolveCurrent()
assert(V.BeginRecording("Edit"), "recording did not start")
base.player.width = 999
raiseRestore = true
pcall(driver.event, driver, "PLAYER_LOGOUT")
raiseRestore = false
assert(base.player.width == 120, "a provider error at logout saved the recording as the base")
assert(not V.IsRecording(), "logout left the recording open")
print("profile_variants_logout_smoke: OK")
