-- classpower_ebon_slot_smoke.lua <repoRoot>
--
-- Ebon Might's bar and duration text are bound into a native aura slot
-- (ClassPower/MSUF_CP_EbonMight.lua). Blizzard applies the slot's access
-- restriction after initializeFrame returns
-- (Blizzard_AuraContainerFrameProviders.lua: DenyTaintedAccessWhenAurasAreSecret),
-- so restyling those regions later is legal only while they are mutable:
-- out of combat, auras not secret, and the region accessible. The other
-- native slots (MSUF_CP_NativeAuras.lua, MSUF_CP_ExtraAuras.lua) already guard
-- the same way. A denied restyle is deferred and retried at combat end.
--
-- The stub slot is strict: once sealed, every widget call on a bound region
-- raises while access is denied, as the client does.
-- Plain Lua 5.1, repo root as arg 1.

local repo = assert(arg and arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")
local Stubs = assert(loadfile(repo .. "/.github/scripts/msuf_test_stubs.lua"))()

local failures = {}
local function Check(condition, message)
    if not condition then failures[#failures + 1] = message end
end

local env = Stubs.New({ timer = "queue" })
env:InstallGlobals({ secretValue = true })
local S = { combat = false, aurasSecret = false, denied = false }
InCombatLockdown = function() return S.combat end
C_Secrets = { ShouldAurasBeSecret = function() return S.aurasSecret end }

--- Seals a bound region: every widget call raises while access is denied.
local function Seal(region)
    region.CanBeAccessedInContext = function() return not S.denied end
    for name, method in pairs(env.Methods) do
        if type(method) == "function" and name ~= "CanBeAccessedInContext" then
            region[name] = function(...)
                if S.denied then error("access to a restricted aura slot region was denied", 2) end
                return method(...)
            end
        end
    end
end

_G.MSUF_Auras3 = {
    CreateClassPowerAuraSensor = function(host, _, _, initializeFrame)
        local sensor = CreateFrame("Frame", nil, host)
        local button = CreateFrame("Frame", nil, sensor)
        button.SetDurationBar = function() end
        button.SetDurationText = function() end
        initializeFrame(button)
        Seal(button)
        return sensor
    end,
}

_G.MSUF_CP_CORE_BUILDERS = nil
local ns = { ExportPublic = function(name, value) _G[name] = value return value end }
assert(loadfile(repo .. "/tools/tests/classpower_collaborators.lua"))().Install(repo, ns)
_G.MSUF_CP_CONST = nil
assert(loadfile(repo .. "/MidnightSimpleUnitFrames/ClassPower/MSUF_CP_Constants.lua"))("MidnightSimpleUnitFrames", ns)
assert(loadfile(repo .. "/MidnightSimpleUnitFrames/ClassPower/MSUF_CP_EbonMight.lua"))("MidnightSimpleUnitFrames", ns)

local CP = {}
local host = CreateFrame("StatusBar", nil, UIParent)
local style = { barR = 1, barG = 0.5, barB = 0, barA = 1 }
local api = _G.MSUF_CP_CORE_BUILDERS.EBON_MIGHT({
    CP = CP,
    EBON = { SPELL_ID = 395296 },
    _cpDB = {},
    CreateFrame = CreateFrame,
    GetHost = function() return host end,
    GetStyle = function() return style end,
    GetTextLevel = function() return 5 end,
})
Check(api.SetActive(true) == true and CP.ebonNativeBar and CP.ebonNativeText, "the Ebon Might slot was not built")
Seal(CP.ebonNativeBar)
Seal(CP.ebonNativeText)

-- In combat while Ebon Might is secret the slot regions are off limits.
S.combat, S.aurasSecret, S.denied = true, true, true
style.barR = 0.2
local ok, err = pcall(api.RefreshStyle)
Check(ok, "restyling the sealed Ebon Might slot in combat raised: " .. tostring(err))
Check(CP.ebonStyleRetryPending == true, "a denied Ebon Might restyle was not queued for combat end")

-- Combat over: the retry applies the new colour.
S.combat, S.aurasSecret, S.denied = false, false, false
ok, err = pcall(api.RefreshStyle)
Check(ok and CP.ebonNativeBar.color and CP.ebonNativeBar.color[1] == 0.2,
    "the Ebon Might restyle did not apply out of combat: " .. tostring(err))
Check(not CP.ebonStyleRetryPending, "the Ebon Might restyle stayed queued after it applied")

if #failures > 0 then
    error("classpower_ebon_slot_smoke:\n  " .. table.concat(failures, "\n  "), 0)
end
print("classpower_ebon_slot_smoke: ok (sealed slot restyle deferred to combat end)")
