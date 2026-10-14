-- Real core + Options graph with a region fixture that keeps its own shown flag.
-- A child's own flag is what the shown caches mirror; the fixture also models a
-- hidden parent so a test can tell own visibility from inherited visibility.
local Fixture = {}

function Fixture.Boot(root, flavor)
    local World = dofile(root .. "/tools/tests/client_world.lua")
    local Secrets = dofile(root .. "/tools/tests/classpower_secrets.lua")
    local world = World.New(root, flavor)
    local calls = { SetShown = 0, Show = 0, Hide = 0, IsShown = 0, IsVisible = 0, issecretvalue = 0 }
    -- Installed before the graph loads, so every addon file captures the counted query.
    world.env.issecretvalue = function(value)
        calls.issecretvalue = calls.issecretvalue + 1
        return Secrets.IsSecret(value)
    end
    world:Boot()
    assert(not world:FirstFailure(), "real core + Options graph failed")
    assert(#world.corePaths > 0 and #world.optionsPaths > 0, "both actual graphs required")
    return world, calls, Secrets
end

function Fixture.Reset(calls)
    for key in pairs(calls) do calls[key] = 0 end
end

-- The shown-cache fields a region carries right now: every "_...Shown" key.
function Fixture.Caches(region)
    local caches = {}
    for key, value in pairs(region) do
        if type(key) == "string" and key:find("^_.*Shown") then caches[key] = value end
    end
    return caches
end

-- The cache value when the region carries exactly one shown cache, nil when it carries none.
function Fixture.CacheValue(caches)
    local count, value = 0, nil
    for _, cached in pairs(caches) do
        count = count + 1
        value = cached
    end
    assert(count <= 1, "more than one shown cache on one region")
    return value
end

-- fallback = true leaves the region without SetShown (Show/Hide only).
function Fixture.Region(world, calls, Secrets, fallback)
    local region = world.env.CreateFrame("Frame"):CreateTexture()
    region.fixtureOwnShown = true
    region.fixtureParent = { ownShown = true }
    region.fixtureTrace = false
    region.fixtureTainted = false
    region.fixtureRaise = false
    local function Observe(self, method, value)
        calls[method] = calls[method] + 1
        if self.fixtureTrace then
            self.fixtureTrace[#self.fixtureTrace + 1] = { method = method, value = value, caches = Fixture.Caches(self) }
        end
        if self.fixtureRaise then error("native mutation rejected") end
    end
    function region:SetShown(value)
        Observe(self, "SetShown", value)
        if Secrets.IsSecret(value) then
            -- AllowedWhenUntainted: a tainted sink still rejects the opaque boolean.
            if self.fixtureTainted then error("secret argument rejected by tainted sink") end
            self.fixtureSecretSink = value
            return
        end
        self.fixtureOwnShown = value and true or false
        self.fixtureSecretSink = nil
    end
    function region:Show()
        Observe(self, "Show", true)
        self.fixtureOwnShown = true
    end
    function region:Hide()
        Observe(self, "Hide", false)
        self.fixtureOwnShown = false
    end
    function region:IsShown()
        calls.IsShown = calls.IsShown + 1
        return self.fixtureOwnShown
    end
    function region:IsVisible()
        calls.IsVisible = calls.IsVisible + 1
        return self.fixtureOwnShown and self.fixtureParent.ownShown
    end
    if fallback then region.SetShown = false end
    return region
end

-- The three exported setters that remember a region's shown state.
function Fixture.APIs(world)
    return {
        Apply = assert(world.core.Apply.Shown),
        Bars = assert(world.core.UFBarTextCommon.SetShownCached),
        Visuals = assert(world.core.UFVisuals.SetShown),
    }
end

return Fixture
