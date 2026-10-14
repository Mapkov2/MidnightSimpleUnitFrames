-- One shown cache per region, whichever UF module drives it.
--
--   lua tools/tests/region_visibility_cache_smoke.lua <repo root> <flavor>
--
-- Boots the real core + Options graph and drives actual owners against one region:
-- the three exported setters (Apply.Shown, UFBarTextCommon.SetShownCached,
-- UFVisuals.SetShown), the status runtime, and the element modules that used to keep
-- a private shown flag (pet happiness, group corner indicators, group visuals,
-- prediction over-absorb glow). A second owner that shows or hides the same
-- native region must never leave the first owner believing its old state, because
-- a stale cache suppresses the next native call and the region stays wrong.
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "flavor required")
local Fixture = dofile(root .. "/tools/tests/region_visibility_world.lua")
local world, calls, Secrets = Fixture.Boot(root, flavor)
local APIs = Fixture.APIs(world)
local core = world.core
local failures = 0

local function Case(label, fn)
    local ok, problem = pcall(fn)
    print((ok and "PASS " or "RED ") .. flavor .. " " .. label .. (ok and "" or ": " .. tostring(problem)))
    if not ok then failures = failures + 1 end
end

local function New(fallback)
    return Fixture.Region(world, calls, Secrets, fallback)
end

---------------------------------------------------------------------------
-- 1. The three exported setters keep their input and native-order contracts
---------------------------------------------------------------------------
for _, name in ipairs({ "Apply", "Bars", "Visuals" }) do
    local setter = APIs[name]
    Case(name .. " input handling and native order", function()
        local region = New()
        region.fixtureTrace = {}
        local truthy = {}
        setter(region, nil)
        if name == "Bars" then
            assert(#region.fixtureTrace == 0 and region:IsShown(), "cold raw nil must stay a no-op")
        else
            assert(not region:IsShown(), "nil must hide")
        end
        setter(region, false)
        assert(not region:IsShown(), "false must hide")
        setter(region, true)
        assert(region:IsShown(), "true must show")
        setter(region, truthy)
        assert(region:IsShown() == (name ~= "Visuals"), "plain truthy contract changed")
        local native = region.fixtureTrace[#region.fixtureTrace]
        local cached = Fixture.CacheValue(native.caches)
        if name == "Apply" then
            assert(native.value == true and cached == false, "Apply must write the cache after the native call")
        elseif name == "Bars" then
            assert(rawequal(native.value, truthy) and cached == true, "Bars must forward the raw value first")
        else
            assert(native.value == false and cached == false, "Visuals must write the cache before the native call")
        end
        setter(region, nil)
        assert(not region:IsShown(), "warm nil must hide")
        local before = #region.fixtureTrace
        setter(region, nil)
        assert(#region.fixtureTrace == before, "repeated nil must be a no-op")
        assert(select("#", setter(nil, true)) == 0, "nil region return arity changed")
    end)
    Case(name .. " native errors and a region without SetShown", function()
        local region = New()
        region.fixtureRaise = true
        assert(not pcall(setter, region, false), "native error swallowed")
        local cached = Fixture.CacheValue(Fixture.Caches(region))
        if name == "Visuals" then
            assert(cached == false, "Visuals must write before the native error")
        else
            assert(cached == nil, "cache written despite a native error")
        end
        region = New(true)
        local ok = pcall(setter, region, false)
        if name == "Visuals" then
            assert(ok and not region:IsShown(), "a missing SetShown must hide through Hide")
            setter(region, true)
            assert(region:IsShown(), "a missing SetShown must show through Show")
        else
            assert(not ok, "the missing SetShown error changed")
        end
    end)
    Case(name .. " caches the child's own flag beneath a hidden parent", function()
        local region = New()
        region.fixtureParent.ownShown = false
        setter(region, false)
        setter(region, true)
        assert(region:IsShown() and not region:IsVisible(), "fixture must separate own and inherited visibility")
        local before = calls.SetShown
        setter(region, true)
        assert(calls.SetShown == before, "a hidden parent forced a child repaint")
        region.fixtureParent.ownShown = true
        assert(region:IsVisible(), "parent restore lost the child's own flag")
    end)
end

---------------------------------------------------------------------------
-- 2. Two exported setters on one region share one cache
---------------------------------------------------------------------------
for _, commonName in ipairs({ "Bars", "Visuals" }) do
    local common = APIs[commonName]
    Case(commonName .. " -> Apply -> " .. commonName, function()
        local region = New()
        common(region, true)
        APIs.Apply(region, false)
        assert(not region:IsShown(), "Apply hide failed")
        common(region, true)
        assert(region:IsShown(), "a stale cache suppressed the native show")
    end)
    Case("Apply -> " .. commonName .. " -> Apply", function()
        local region = New()
        APIs.Apply(region, true)
        common(region, false)
        APIs.Apply(region, true)
        assert(region:IsShown(), "a stale Apply cache suppressed the native show")
    end)
    Case(commonName .. " after Apply.Invalidate", function()
        local region = New()
        common(region, true)
        region:Hide()
        core.Apply.Invalidate(region)
        common(region, true)
        assert(region:IsShown(), "invalidation did not force a repaint")
    end)
end
Case("Apply.Invalidate forces the next Apply.Shown to repaint", function()
    local region = New()
    APIs.Apply(region, true)
    region:Hide()
    core.Apply.Invalidate(region)
    APIs.Apply(region, true)
    assert(region:IsShown(), "invalidation did not force a repaint")
end)

---------------------------------------------------------------------------
-- 3. Secret visibility reaches the native sink and is never cached
---------------------------------------------------------------------------
Case("Apply.Shown forwards a secret boolean and forgets the cache", function()
    local region = New()
    APIs.Apply(region, true)
    local secret = Secrets.New("boolean")
    local stop = Secrets.Watch(root .. "/MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Apply.lua", { strict = true })
    APIs.Apply(region, secret)
    local violations = stop()
    assert(#violations == 0, "Apply used an opaque secret before its guard: " .. table.concat(violations, "; "))
    assert(rawequal(region.fixtureSecretSink, secret), "the native sink did not receive the original opaque boolean")
    assert(Fixture.CacheValue(Fixture.Caches(region)) == nil, "a secret visibility was cached")
    APIs.Apply(region, true)
    assert(region:IsShown() and region.fixtureSecretSink == nil, "a plain write after a secret must repaint")
    region.fixtureTainted = true
    assert(not pcall(APIs.Apply, region, secret), "a tainted sink rejection was swallowed")
    assert(Fixture.CacheValue(Fixture.Caches(region)) == true, "a rejected secret write changed the cache")
end)

---------------------------------------------------------------------------
-- 4. The status runtime and Apply share one cache (actual Forever level badge)
---------------------------------------------------------------------------
Case("status show -> Apply hide -> status show", function()
    local runtime = assert(core.UFStatusRuntime)
    local badge, ring = New(), New()
    local frame = { levelBackdrop = badge, levelBackdropRing = ring }
    runtime.SetForeverLevelBadgeShown(frame, true)
    assert(badge:IsShown() and ring:IsShown(), "status failed its first show")
    APIs.Apply(badge, false)
    APIs.Apply(ring, false)
    assert(not badge:IsShown() and not ring:IsShown(), "Apply failed to hide")
    runtime.SetForeverLevelBadgeShown(frame, true)
    assert(badge:IsShown() and ring:IsShown(), "the status cache stayed stale after Apply hid the regions")
end)
Case("Apply show -> status hide -> Apply show", function()
    local runtime = assert(core.UFStatusRuntime)
    local badge = New()
    local frame = { levelBackdrop = badge }
    APIs.Apply(badge, true)
    runtime.SetForeverLevelBadgeShown(frame, false)
    assert(not badge:IsShown(), "status failed to hide a region Apply showed")
    APIs.Apply(badge, true)
    assert(badge:IsShown(), "the Apply cache stayed stale after status hid the region")
end)
Case("status repeats write nothing", function()
    local runtime = assert(core.UFStatusRuntime)
    local badge = New()
    local frame = { levelBackdrop = badge }
    Fixture.Reset(calls)
    runtime.SetForeverLevelBadgeShown(frame, true)
    runtime.SetForeverLevelBadgeShown(frame, true)
    runtime.SetForeverLevelBadgeShown(frame, false)
    runtime.SetForeverLevelBadgeShown(frame, false)
    assert(calls.SetShown == 2, "a repeated status write reached the native region")
end)
Case("status and the shared setters leave exactly one shown cache on the region", function()
    local runtime = assert(core.UFStatusRuntime)
    local badge = New()
    local frame = { levelBackdrop = badge }
    runtime.SetForeverLevelBadgeShown(frame, true)
    APIs.Apply(badge, false)
    APIs.Visuals(badge, true)
    APIs.Bars(badge, false)
    local keys = {}
    for key in pairs(Fixture.Caches(badge)) do keys[#keys + 1] = key end
    assert(#keys == 1 and keys[1] == "_msufShown", "shown cache fields on one region: " .. table.concat(keys, ","))
end)

---------------------------------------------------------------------------
-- 5. Element modules that kept a private flag follow the same cache
---------------------------------------------------------------------------
-- hide(region) is the module's own hide entry. The module hides once, a second
-- owner shows the native region through Apply, and the module hides again.
local function ForeignShowSurvivesModuleHide(label, region, hide)
    Case(label .. ": the module's hide reaches a region another owner showed", function()
        hide(region)
        assert(not region:IsShown(), label .. " failed its own hide")
        APIs.Apply(region, true)
        assert(region:IsShown(), "Apply failed to show")
        hide(region)
        assert(not region:IsShown(), label .. " kept a stale cache and left the region shown")
    end)
end

local elements = assert(core.UF and core.UF.elements, "unit-frame element registry missing")
local ran = {}
if elements.PetHappinessIndicator then
    ran[#ran + 1] = "happiness"
    local frame = { petHappinessIndicatorIcon = New() }
    ForeignShowSurvivesModuleHide("pet happiness", frame.petHappinessIndicatorIcon, function()
        elements.PetHappinessIndicator.Disable(frame)
    end)
end
do
    ran[#ran + 1] = "corners"
    local frame = { MSUFGFCornerIndicators = { topleft = New() } }
    ForeignShowSurvivesModuleHide("group corner indicators", frame.MSUFGFCornerIndicators.topleft, function()
        elements.GroupCornerIndicators.Disable(frame)
    end)
end
do
    ran[#ran + 1] = "visuals"
    local frame = { MSUFGFDispelOverlay = New() }
    ForeignShowSurvivesModuleHide("group visuals", frame.MSUFGFDispelOverlay, function()
        elements.GroupVisuals.Disable(frame)
    end)
end
do
    ran[#ran + 1] = "prediction"
    local frame = { overAbsorbGlowBar = New() }
    ForeignShowSurvivesModuleHide("prediction over-absorb glow", frame.overAbsorbGlowBar, function()
        frame._msufPredictionDisabled = nil
        elements.Prediction.Disable(frame)
    end)
end

-- The threat text keeps its own flag on purpose: the background plate follows that flag, so it is the
-- state of the text and plate pair. Another owner hiding the text must not leave the plate behind.
if elements.ThreatIndicator then
    ran[#ran + 1] = "threat"
    Case("threat text and its plate stay paired when another owner hides the text", function()
        local frame = world.env.CreateFrame("Frame")
        frame.MSUFUnitKey = "target"
        local spec = { scope = "unit", status = { alpha = 1, testMode = true,
            threat = { enabled = true, background = true, layer = 7, size = 11, anchor = "BOTTOMLEFT", x = 6, y = 2 } } }
        frame.MSUFSpec = spec
        elements.ThreatIndicator.Apply(frame, spec)
        elements.ThreatIndicator.Update(frame, "MSUF_APPLY")
        local text, plate = frame.threatIndicatorText, frame.threatIndicatorPlate
        assert(text and plate and text:IsShown() and plate:IsShown(), "the real element failed to show its text and plate")
        APIs.Apply(text, false)
        assert(not text:IsShown(), "Apply failed to hide the text")
        elements.ThreatIndicator.Disable(frame)
        assert(not text:IsShown() and not plate:IsShown(), "the plate stayed behind its hidden text")
    end)
end
print("modules exercised: " .. table.concat(ran, ", "))

---------------------------------------------------------------------------
-- 6. No module keeps a private shown flag of its own again
---------------------------------------------------------------------------
Case("the loaded graph holds no retired shown-cache field", function()
    local retired = { "_aShown", "_msufStatusShown", "_msufLoadShown", "_msufOverAbsorbShown", "_msufGFShown",
        "_msufGFVisualShown", "_msufHappinessShown" }
    local found = {}
    for _, paths in ipairs({ world.corePaths, world.optionsPaths }) do
        for _, path in ipairs(paths) do
            local handle = assert(io.open(path, "rb"), "cannot read " .. path)
            local source = handle:read("*a")
            handle:close()
            for _, name in ipairs(retired) do
                if source:find(name, 1, true) then found[#found + 1] = name .. " in " .. path end
            end
        end
    end
    assert(#found == 0, table.concat(found, "; "))
end)

assert(failures == 0, tostring(failures) .. " region visibility cache contracts failed on " .. flavor)
print("region visibility cache: GREEN " .. flavor)
