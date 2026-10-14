-- Count the complete exported Update path, including the stripe phase dispatch.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local harness = (arg[2] or root):gsub("\\", "/"):gsub("/$", "")
local Loader = assert(loadfile(harness .. "/.github/scripts/auras3_test_loader.lua"))()
Loader.Install()
local saved = arg
arg = { harness, root, "fixture" }
local Fixture, SECRET = assert(loadfile(harness .. "/.github/scripts/prediction_data_writer_parity_smoke.lua"))()
arg = saved
-- Exact 9c29 exported-path VM and native counts per 100 calls, not aggregate compensation.
local caps = {
    [0] = { 29800, 29800, 29000, 29000, 500 },
    [4] = { 54300, 53600, 39700, 39700, 600 },
    [8] = { 54400, 55200, 38500, 38500, 600 },
    [12] = { 53500, 53700, 51000, 51000, 600 },
}
local errors = {}
for _, flags in ipairs({ 0, 4, 8, 12 }) do
    for _, protected in ipairs({ false, true }) do
        for _, full in ipairs({ false, true }) do
            local x = Fixture(root)
            local s = x.sim
            s.hp = protected and SECRET or (full and 1000 or 600)
            s.max, s.absorb = protected and SECRET or 1000, protected and SECRET or 350
            local f = x:Frame(2, 2, flags)
            x.prediction.Update(f, "MSUF_UNIT_IDENTITY", f.MSUFUnitKey)
            local m = x:Measure(f, 2, "MSUF_FORCE_UPDATE")
            local label = flags .. ":" .. tostring(protected) .. ":" .. tostring(full)
            print(label, m.work, m.native, m.allocated)
            local cap = caps[flags][(protected and 2 or 0) + (full and 2 or 1)]
            if m.work > cap or m.allocated > 0 then errors[#errors + 1] = label .. ": " .. m.work .. " VM" end
            assert(m.native == (flags == 12 and protected and 700 or caps[flags][5]), "complete-path native count changed: " .. label)
        end
    end
end
assert(#errors == 0, "exported prediction regression:\n" .. table.concat(errors, "\n"))
print("prediction_force_update_cost_smoke: ok (plain/protected, full/partial, stripe and overlay off/on)")
