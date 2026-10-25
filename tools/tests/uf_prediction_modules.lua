-- Explicit state-owner contracts, plus immutable plan unions for every configuration.
-- arg 1 repo root.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local base = root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/"
local ns = { UFModuleFactories = {}, UF = { Shared = { ABSORB_ANCHOR = {
    LEFT = 1, RIGHT = 2, FOLLOW_HP = 3, FOLLOW_HP_OVERFLOW = 4, REVERSE_FROM_MAX = 5,
} } } }
local function Read(path)
    local f = assert(io.open(path, "rb"), "missing state-owner module " .. path)
    local text = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    return text
end
local coordinator = Read(base .. "MSUF_UF_Elements_Prediction.lua")
assert(not coordinator:find("local predictionWriteQueue", 1, true), "queue state still shares the coordinator")
assert(not coordinator:find("local predictionPlanCache", 1, true), "plan cache still shares the coordinator")
assert(not coordinator:find("local function LayoutBar(", 1, true), "layout still shares the coordinator")
local function Load(name)
    local path = base .. "MSUF_UF_Prediction_" .. name .. ".lua"
    local body = Read(path)
    assert(not body:find("pcall", 1, true), "prediction owner added a protected runtime call")
    assert(loadfile(path))("test", ns)
end
Load("Layout")
Load("Plans")
Load("Queue")
local layout = ns.UFModuleFactories.PredictionLayout(function(f) return f end)
local plans = ns.UFModuleFactories.PredictionPlans(layout.NormalizeAnchorMode)
for configMask = 0, 7 do
    for _, follow in ipairs({ false, true }) do
        local cfg = { enabled = true, heal = configMask % 2 == 1,
            absorb = configMask % 4 >= 2, healAbsorb = configMask >= 4 }
        assert(plans.PredictionMask(cfg) == configMask)
        local events, full = plans.CompilePredictionPlans(cfg, follow)
        local repeated, repeatedFull = plans.CompilePredictionPlans(cfg, follow)
        assert(events == repeated and full == repeatedFull, "configuration did not reuse its immutable plans")
        assert(full[7] == true)
        for mask = 1, 7 do
            local expected = {}
            for index, event in ipairs({ "UNIT_HEAL_PREDICTION", "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" }) do
                local bit = 2 ^ (index - 1)
                if mask % (bit * 2) >= bit and events[event] then
                    for field = 1, 7 do expected[field] = expected[field] or events[event][field] end
                end
            end
            local union = events[mask]
            for field = 1, 7 do
                assert((union and union[field] or nil) == (expected[field] or nil), "union plan changed")
            end
            assert(events[mask] == events[plans.PREDICTION_DIRTY_PLAN_KEYS[mask]])
        end
    end
end
print("PASS uf_prediction_modules: queue/layout/plan owners; 16 plan configurations and 112 unions")
