-- Configuration work comparison; no game rendering or CPU/FPS claims.
local root = assert(arg[1], "candidate root required"):gsub("\\", "/")
local baseline = arg[2] and arg[2]:gsub("\\", "/")
local loader = assert(loadfile(root .. "/.github/scripts/auras3_test_loader.lua"))()
local checks = 0
local function Check(value, message)
    checks = checks + 1
    assert(value, message)
end
local function Equal(a, b, path)
    Check(type(a) == type(b), path .. ": type changed")
    if type(a) ~= "table" then Check(a == b, path .. ": value changed"); return end
    for key, value in pairs(a) do Equal(value, b[key], path .. "." .. tostring(key)) end
    for key in pairs(b) do Check(a[key] ~= nil, path .. ": added " .. tostring(key)) end
end

local function LoadRuntime(sourceRoot)
    local db = { enabled = true, showTarget = true, showFocus = true,
        shared = { showBuffs = true, showDebuffs = true }, perUnit = {} }
    _G.MSUF_DB = { auras3 = db, general = {} }
    _G.InCombatLockdown = function() return false end
    _G.C_AddOns = { IsAddOnLoaded = function() return true end }
    _G.C_Timer = { After = function() end }
    _G.CreateFrame = function() error("config-only test created a frame") end
    _G.issecretvalue = function() return false end
    local a3 = {
        _runtimeConfigGen = 1,
        EnsureDB = function() return db, db.shared end,
        SpellIndicators = {
            Install = function() end,
            CompileSlots = function() return nil end,
            PartitionUnitRoot = function(value) return value end,
        },
    }
    function a3.BumpRuntimeConfig()
        a3._runtimeConfigGen = a3._runtimeConfigGen + 1
        return a3._runtimeConfigGen
    end
    local ns = { MSUF_Auras3 = a3, UF = { RegisterElement = function() end, frames = {}, Config = {} } }
    local files = assert(loader.Group(sourceRoot .. "/MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_UnitFrames.lua"))
    for i = 1, #files - 1 do assert(loadfile(files[i]))("MidnightSimpleUnitFrames", ns) end
    local counts = { unit = 0, group = 0 }
    -- Count real compiler work at the factory seam, before production captures
    -- the functions locally. Both old symbol maps and new owner maps are tested.
    for _, entry in ipairs({ { "UnitConfig", "CompileUnitLane", "unit" }, { "GroupConfig", "CompileGroupLane", "group" } }) do
        local factory = ns.Auras3RuntimeFactories[entry[1]]
        ns.Auras3RuntimeFactories[entry[1]] = function(name, moduleNS, api, uf, export, dependencies)
            local owner = dependencies.LaneConfig or dependencies
            local compile = owner[entry[2]]
            owner[entry[2]] = function(...)
                counts[entry[3]] = counts[entry[3]] + 1
                return compile(...)
            end
            return factory(name, moduleNS, api, uf, export, dependencies)
        end
    end
    assert(loadfile(files[#files]))("MidnightSimpleUnitFrames", ns)
    -- Exercise invalidation without constructing native owners: the retained
    -- native fixture separately checks exact per-owner API operation sequences.
    local requests = {}
    a3.RequestUnit = function(scope) requests[#requests + 1] = scope; return true end
    return a3, ns, db, counts, requests
end

local function GroupFrame(kind, unit, source)
    return { _msufIsGroupFrame = true, _msufGFKind = kind, MSUFUnitKey = unit,
        MSUFSpec = { auras = source or { enabled = true, maxBuffs = 3, maxDebuffs = 2 } } }
end
local function Projection(a3, cfg)
    local result = { enabled = cfg.enabled, groupAssistGate = cfg.groupAssistGate }
    for _, kind in ipairs({ "buff", "trackedBuff", "debuff", "external" }) do
        local lane = cfg.lanes[kind]
        if lane then
            result[kind] = { filter = lane.nativeFilter, candidates = lane.candidateFilters,
                signature = lane.candidateFilterSignature, metrics = a3.BuildAuraLaneMetrics(cfg, kind) }
        end
    end
    return result
end

local function Exercise(sourceRoot, optimized)
    local a3, ns, db, counts, requests = LoadRuntime(sourceRoot)
    local frames = {
        GroupFrame("party", "party1"), GroupFrame("raid", "raid1"), GroupFrame("mythicraid", "raid1"),
        GroupFrame(nil, "party2"), -- Legacy/synthetic frame without kind.
    }
    local unitSpec = { border = {} }
    ns.UF.frames.target = { MSUFUnitKey = "target", MSUFSpec = unitSpec }
    local cfgs, projections = {}, {}
    local function Resolve()
        for i, frame in ipairs(frames) do cfgs[i] = a3.ResolveAuraPreviewConfig(frame) end
        cfgs.target = a3.ResolveUnitFrameConfig("target", unitSpec)
        cfgs.focus = a3.ResolveUnitFrameConfig("focus")
        cfgs.style = a3.IconStylePreviewForKind("buff")
    end
    Resolve()
    local warmedGroupCompiles = counts.group
    collectgarbage("collect")
    collectgarbage("stop")
    local beforeHits = collectgarbage("count")
    for _ = 1, 10000 do
        Check(a3.ResolveAuraPreviewConfig(frames[1]) == cfgs[1], "unchanged frame missed its config cache")
    end
    local hitAllocation = collectgarbage("count") - beforeHits
    collectgarbage("restart")
    Check(counts.group == warmedGroupCompiles, "cache hits entered lane compilation")
    Check(hitAllocation < 1, "cache hits allocated recurring tables")
    local actions = {
        { "party", true, false, false }, { "gf_party", true, false, false }, { "party2", true, false, false },
        { "raid", false, true, true }, { "gf_raid", false, true, true }, { "raid3", false, true, true },
        { "mythicraid", false, false, true }, { "gf_mythicraid", false, false, true },
        { "group", true, true, true }, { "groups", true, true, true },
    }
    for _, action in ipairs(actions) do
        local previous = cfgs
        cfgs = {}
        for i = 1, 3 do
            if action[i + 1] then frames[i].MSUFSpec.auras.buffIconSize = 30 + #projections end
        end
        local gen = a3._runtimeConfigGen
        Check(a3.RefreshUnit(action[1]) == true, "request return changed")
        Check(requests[#requests] == action[1], "request scope changed")
        Resolve()
        if optimized then
            Check(a3._runtimeConfigGen == gen, "group request evicted global Appearance generation")
            Check(cfgs.target == previous.target and cfgs.focus == previous.focus, "group request rebuilt unrelated unit configs")
            Check(cfgs.style == previous.style, "group request rebuilt global style")
            for i = 1, 3 do
                Check((cfgs[i] ~= previous[i]) == action[i + 1], "wrong group cache invalidation: " .. action[1] .. "/" .. tostring(i))
            end
        end
        Check(cfgs[4] ~= previous[4], "unclassified group config stayed stale")
        for i = 1, 3 do
            if action[i + 1] then Check(cfgs[i].lanes.buff.size == 30 + #projections, "in-place layout edit stayed stale") end
        end
        local projected = {}
        for i = 1, 4 do projected[i] = Projection(a3, cfgs[i]) end
        projections[#projections + 1] = projected
        if #projections == 4 then
            local oldConfig = cfgs[1]
            a3.BumpRuntimeConfig()
            Resolve()
            Check(cfgs[1] ~= oldConfig, "interleaved global invalidation collided with a scope revision")
        end
    end

    -- Shared compiled specs reuse one immutable config for identical previews.
    local preview1, preview2 = GroupFrame("party", "player"), GroupFrame("party", "player")
    preview1._msufGFIsPreviewFrame, preview2._msufGFIsPreviewFrame = true, true
    preview2.MSUFSpec = preview1.MSUFSpec
    local first = a3.ResolveAuraPreviewConfig(preview1)
    Check(a3.ResolveAuraPreviewConfig(preview2) == first, "identical preview configs did not share")
    a3.RefreshUnit("party")
    local nextConfig = a3.ResolveAuraPreviewConfig(preview1)
    Check(nextConfig ~= first and a3.ResolveAuraPreviewConfig(preview2) == nextConfig, "preview shared cache kept old revision")

    -- Global/profile and native visual invalidations must still reach every scope.
    for _, key in ipairs({ "global", "visual" }) do
        local previous = cfgs
        cfgs = {}
        if key == "global" then
            db.shared.appearanceIconStyles = { buff = { styleBorderEnabled = true } }
            a3.BumpRuntimeConfig()
        else a3._nativeVisualGen = (a3._nativeVisualGen or 0) + 1 end
        Resolve()
        for i = 1, 4 do Check(cfgs[i] ~= previous[i], key .. " invalidation missed a group") end
        Check(cfgs.target ~= previous.target and cfgs.focus ~= previous.focus, key .. " invalidation missed a unit")
        if key == "global" then Check(cfgs.style.borderEnabled == true, "global appearance stayed stale") end
    end
    -- Unit writes still invalidate both cached forms independently of global gen.
    local oldTarget, oldFocus = cfgs.target, cfgs.focus
    a3.RefreshUnit("target")
    Check(a3.ResolveUnitFrameConfig("target", unitSpec) ~= oldTarget, "target edit ignored frame-spec cache")
    Check(a3.ResolveUnitFrameConfig("focus") == oldFocus, "target edit invalidated focus")
    if optimized then
        Check(a3.InvalidateGroupRuntimeConfig("target") == false and a3.InvalidateGroupRuntimeConfig(nil) == false,
            "non-group input accepted by group invalidator")
    end
    return projections, counts
end

-- Start with equal revision numbers to exercise a real cross-kind collision.
do
    local a3 = LoadRuntime(root)
    local other = GroupFrame("party", "player")
    local old = a3.ResolveAuraPreviewConfig(other)
    other._msufGFKind = "raid"
    Check(a3.ResolveAuraPreviewConfig(other) ~= old, "pooled frame reused another kind's config")
end
local old, oldCounts
if baseline then old, oldCounts = Exercise(baseline, false) end
local new, newCounts = Exercise(root, true)
if baseline then
    Equal(old, new, "render configuration")
    Check(newCounts.unit < oldCounts.unit, "scoping did not eliminate any unit compilation")
    Check(newCounts.group < oldCounts.group, "scoping did not eliminate any group compilation")
    print("PASS scoped cache: " .. checks .. " checks; unit lane compiles " .. oldCounts.unit .. " -> " .. newCounts.unit
        .. ", group lane compiles " .. oldCounts.group .. " -> " .. newCounts.group
        .. "; identical projected configs, aliases, preview reuse and global/visual invalidation")
else
    print("PASS scoped cache: " .. checks .. " semantic checks; scopes, aliases, preview reuse, global/visual invalidation")
end
