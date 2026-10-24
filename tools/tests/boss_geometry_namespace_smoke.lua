-- <root> <flavor> [original-consumers-root|-] [--missing-owner]
-- Real client graph and Factory geometry; widget anchors are the native-boundary evidence.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2])
local original = arg[3] and arg[3] ~= "-" and arg[3]:gsub("\\", "/"):gsub("/$", "") or nil
local missing = arg[4] == "--missing-owner"
assert(arg[4] == nil or missing, "unknown causal mode")
assert(not (original and missing), "causal modes must be separate")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local OWNER, SYMBOL = "ApplyBossPhysicalBarGeometry", "MSUF_ApplyBossPhysicalBarGeometry"
local contexts = {
    ["Shell/EditMode/MSUF_EditMode_Layout.lua"] = true,
    ["UnitFrames/Engine/Elements/MSUF_UF_Elements_Health.lua"] = true,
    ["UnitFrames/Engine/Elements/MSUF_UF_Elements_Power.lua"] = true,
    ["UnitFrames/Engine/Elements/MSUF_UF_Elements_Borders.lua"] = true,
}
local function Near(actual, expected, label)
    assert(type(actual) == "number" and math.abs(actual - expected) < .000001, label .. " mismatch")
end
local function Boot()
    local w = World.New(root, flavor)
    -- Deterministic native screen metadata, before Util captures the API. Pixel size is one.
    w.env.GetPhysicalScreenSize = function() return 1280, 768 end
    local load, loads, replacements = w.LoadFile, {}, 0
    w.LoadFile = function(self, path, addon, ns)
        local relative = path:gsub("\\", "/"):sub(#root + 2)
        local context = relative:match("^MidnightSimpleUnitFrames/(.*)$")
        local input = path
        if contexts[context] then
            loads[context] = (loads[context] or 0) + 1
            if original then input = original .. "/" .. relative replacements = replacements + 1 end
        end
        return load(self, input, addon, ns)
    end
    w:Boot()
    local failure = w:FirstFailure()
    assert(not failure, "boss geometry graph boot failed: " .. tostring(failure and failure.file)
        .. ": " .. tostring(failure and failure.message))
    for context in pairs(contexts) do assert(loads[context] == 1, "consumer did not load once: " .. context) end
    assert(not original or replacements == 4, "original control did not replace exactly four consumer chunks")
    w.env.UIParent:SetScale(1)
    return w
end
local function Frame(w, token, scale)
    local env = w.env
    local f = env.CreateFrame("Frame", nil, env.UIParent)
    f.MSUFUnitKey, f.MSUFSpec = token, { power = { enabled = false, height = 6.2 } }
    f:SetScale(scale or .8)
    f:SetSize(100, 40)
    f.left, f.bottom = 10.25, 20.25
    f.hpBar = env.CreateFrame("StatusBar", nil, f)
    f.healthBackgroundBar = f:CreateTexture()
    f.targetPowerBar = env.CreateFrame("StatusBar", nil, f)
    f.targetPowerBar:SetHeight(6.2)
    for _, r in ipairs({ f.hpBar, f.healthBackgroundBar, f.targetPowerBar }) do
        r:SetPoint("CENTER", f, "CENTER", 3, 4)
    end
    return f
end
local function Regions(f) return { f.hpBar, f.healthBackgroundBar, f.targetPowerBar } end
local function Points(regions)
    local out = {}
    for i, r in ipairs(regions) do
        out[i] = {}
        for j = 1, r:GetNumPoints() do out[i][j] = { r:GetPoint(j) } end
    end
    return out
end
local function SamePoints(actual, expected, label)
    assert(#actual == #expected, label .. " region count changed")
    for i, row in ipairs(expected) do
        assert(#actual[i] == #row, label .. " point count changed")
        for j, point in ipairs(row) do
            for k = 1, 5 do assert(actual[i][j][k] == point[k], label .. " anchor changed") end
        end
    end
end
local function Rect(region, owner, left, bottom, right, top, label)
    assert(region:GetNumPoints() == 2, label .. " did not use two physical anchors")
    local p, relative, rp, x, y = region:GetPoint(1)
    assert(p == "BOTTOMLEFT" and relative == owner and rp == "BOTTOMLEFT", label .. " first anchor identity")
    local ownerScale, scale = owner:GetEffectiveScale(), region:GetEffectiveScale()
    Near(owner.left * ownerScale + x * scale, left, label .. " left")
    Near(owner.bottom * ownerScale + y * scale, bottom, label .. " bottom")
    p, relative, rp, x, y = region:GetPoint(2)
    assert(p == "TOPRIGHT" and relative == owner and rp == "BOTTOMLEFT", label .. " second anchor identity")
    Near(owner.left * ownerScale + x * scale, right, label .. " right")
    Near(owner.bottom * ownerScale + y * scale, top, label .. " top")
end
local function Writes(regions)
    local count = 0
    for _, r in ipairs(regions) do
        for _, key in ipairs({ "ClearAllPoints", "SetPoint", "SetSize", "SetWidth", "SetHeight", "SetAllPoints" }) do
            local native = assert(r[key], "unmodeled widget mutation: " .. key)
            r[key] = function(self, ...) count = count + 1 return native(self, ...) end
        end
    end
    return function() return count end
end
local function Geometry(w, geometry)
    -- Factory's pure token primitive is shared even on clients that cannot spawn a boss/arena unit.
    for _, token in ipairs({ "boss1", "arena2" }) do
        for _, mode in ipairs({ "disabled", "embedded", "inline", "detached" }) do
            local f = Frame(w, token)
            local power = f.MSUFSpec.power
            power.enabled, power.embed, power.detached = mode ~= "disabled", mode ~= "inline", mode == "detached"
            local oldPower = Points({ f.targetPowerBar })
            local writes = Writes(Regions(f))
            assert(geometry(f) == true and writes() > 0, "real Factory geometry did no work: " .. token .. ":" .. mode)
            local hpBottom = mode == "embedded" and 21 or 16
            Rect(f.hpBar, f, 8, hpBottom, 88, 48, token .. ":" .. mode .. ":health")
            Rect(f.healthBackgroundBar, f, 8, hpBottom, 88, 48, token .. ":" .. mode .. ":background")
            if mode == "embedded" then Rect(f.targetPowerBar, f, 8, 16, 88, 21, token .. ":power")
            elseif mode == "inline" then Rect(f.targetPowerBar, f, 8, 10, 88, 15, token .. ":inline")
            else SamePoints(Points({ f.targetPowerBar }), oldPower, token .. ":untouched power") end
            assert(f._msufBossPhysicalGeometryApplied == true, "geometry cache was not published")
            Near(f._msufBossPhysicalLeft, 8, "cached left")
            Near(f._msufBossPhysicalBottom, 16, "cached bottom")
            Near(f._msufBossPhysicalRight, 88, "cached right")
            Near(f._msufBossPhysicalTop, 48, "cached top")
            Near(f._msufBossPhysicalPixel, 1, "cached pixel")
        end
    end
    local f = Frame(w, "boss2", 1.25)
    f.MSUFSpec.power.enabled = true
    assert(geometry(f) == true, "fractional scale geometry refused")
    Rect(f.hpBar, f, 13, 33, 138, 75, "larger-scale health")
    Rect(f.targetPowerBar, f, 13, 25, 138, 33, "larger-scale power")
    f = Frame(w, "boss3")
    f.MSUFSpec.power.enabled, f.MSUFSpec.power.height = true, 100
    assert(geometry(f) == true, "clipped power geometry refused")
    Rect(f.hpBar, f, 8, 47, 88, 48, "minimum-pixel health")
    Rect(f.targetPowerBar, f, 8, 16, 88, 47, "clipped power")
    f = Frame(w, nil)
    f._msufSceneUnit = "boss4"
    local before = Points({ f.healthBackgroundBar })
    f._msufHealthBackgroundFillMissing = true
    assert(geometry(f) == true, "scene-token geometry refused")
    Rect(f.hpBar, f, 8, 16, 88, 48, "scene health")
    SamePoints(Points({ f.healthBackgroundBar }), before, "fill-missing background")
    f._msufBorderLayoutReady = "unchanged-geometry"
    assert(geometry(f) == true and f._msufBorderLayoutReady == "unchanged-geometry", "same rectangle invalidated border")
    f.left = f.left + 1.25
    assert(geometry(f) == true and f._msufBorderLayoutReady == nil, "changed rectangle kept stale border")
    Rect(f.hpBar, f, 9, 16, 89, 48, "moved scene health")
end
local function Refusals(w, geometry)
    assert(geometry(nil) == false, "nil frame was accepted")
    local f = Frame(w, "target")
    local regions, before = Regions(f), Points(Regions(f))
    local writes = Writes(regions)
    assert(geometry(f) == false and writes() == 0, "nonstacked unit geometry mutated")
    SamePoints(Points(regions), before, "nonstacked unit")
    f.MSUFUnitKey = "boss1"
    local hp = f.hpBar
    f.hpBar = nil
    assert(geometry(f) == false and writes() == 0, "missing health bar was accepted")
    f.hpBar = hp
    local env, getRect = w.env, w.env.MSUF_GetPhysicalScreenRect
    env.MSUF_GetPhysicalScreenRect = nil
    assert(geometry(f) == false and writes() == 0, "absent physical provider was accepted")
    env.MSUF_GetPhysicalScreenRect = getRect
    -- Factory's existing policy is native lockdown, not an event-edge refusal policy.
    w.widgets:SetCombat(true)
    assert(env.InCombatLockdown() == true, "lockdown fixture was not active")
    assert(geometry(f) == false and writes() == 0, "locked geometry made a native mutation")
    SamePoints(Points(regions), before, "locked geometry")
    assert(f._msufBossPhysicalGeometryApplied == nil and f._msufBossPhysicalLeft == nil, "locked geometry changed cache")
    w.widgets:SetCombat(false)
    assert(geometry(f) == true and writes() > 0, "unlocked geometry did not recover")
end
local function Consumer(w, geometry)
    local ns, env, factory = w.core, w.env, w.core.UF.Factory
    local borders = assert(ns.UF.elements.Borders, "real Borders element missing")
    local frame = Frame(w, "boss1")
    local spec = { key = "boss", border = { enabled = false, thickness = 1 } }
    local calls, trap = 0, 0
    rawset(env, SYMBOL, function() trap = trap + 1 error("boss geometry legacy global trap reached", 2) end)
    assert(ns.Public[OWNER] == geometry and ns.PublicGlobals[SYMBOL] == geometry, "fallback control lost real registry")
    if missing then
        factory[OWNER] = nil
        borders.Apply(frame, spec)
        error("missing owner causal control unexpectedly returned")
    end
    factory[OWNER] = function(actual)
        assert(actual == frame, "Borders passed another frame")
        calls = calls + 1
        return geometry(actual)
    end
    borders.Apply(frame, spec)
    assert(calls == 1 and trap == 0, "Borders did not resolve its current namespace owner")
    factory[OWNER] = function(actual) calls = calls + 10 return geometry(actual) end
    borders.Apply(frame, spec)
    assert(calls == 11 and trap == 0, "Borders cached the namespace function")
    for _, value in ipairs({ false, 0, "wrong" }) do
        factory[OWNER] = value
        local ok, message = pcall(borders.Apply, frame, spec)
        assert(not ok and tostring(message):find("missing required dependency '" .. OWNER .. "'", 1, true),
            "wrong-type owner escaped fail-closed dependency")
        assert(tostring(message):find("MSUF_UF_Elements_Borders.lua", 1, true), "missing dependency lost caller context")
    end
    factory[OWNER] = nil
    local ok, message = pcall(borders.Apply, frame, spec)
    assert(not ok and tostring(message):find("missing required dependency '" .. OWNER .. "'", 1, true),
        "absent owner used a global or registry fallback")
    assert(calls == 11 and trap == 0, "failed owner reached a fallback")
    factory[OWNER] = geometry
    rawset(env, SYMBOL, nil)
    assert(not original, "original consumer causal control unexpectedly returned")
end
local w = Boot()
local ns, env = w.core, w.env
local factory = assert(ns.UF.Factory, "real Factory missing")
local geometry = assert(factory[OWNER], "real Factory geometry missing")
assert(type(geometry) == "function", "real owner is not callable")
assert(rawget(env, SYMBOL) == nil and ns.Compat.LegacyGlobals[SYMBOL] == nil, "legacy geometry alias is still published")
assert(ns.Public[OWNER] == geometry and ns.PublicGlobals[SYMBOL] == geometry, "public identity changed")
assert(ns.Require(SYMBOL, "compatible registry identity") == geometry, "compatible resolver lost namespace-only publication")
assert(env.MSUF_RefreshBossPhysicalGeometry == factory.RefreshBossPhysicalGeometry, "separate refresh publication changed")
Geometry(w, geometry)
Refusals(w, geometry)
Consumer(w, geometry)
assert(factory[OWNER] == geometry and rawget(env, SYMBOL) == nil, "fixture did not restore provider identity")
print("boss_geometry_namespace_smoke: ok (" .. flavor .. ": real Factory rectangles/refusals and Borders late owner)")
