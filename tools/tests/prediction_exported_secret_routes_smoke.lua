-- Real boot and strict secret watching on exported prediction updates and reapply.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2])
local World = dofile(root .. "/tools/tests/health_tick_world.lua")
local w = World.New(root, flavor)
local prediction = assert(w.UF.elements.Prediction, "real Prediction element missing")
assert(prediction and prediction.Update and prediction.Apply, "real Prediction element missing")
local engine = root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/"
local paths = { engine .. "MSUF_UF_Elements_Prediction.lua", engine .. "MSUF_UF_Prediction_Glow.lua" }
local stop = w.Secrets.Watch(paths, { strict = true })
local cases = 0
for _, protected in ipairs({ false, true }) do
    for _, stripe in ipairs({ false, true }) do
        for _, overlay in ipairs({ false, true }) do
            for _, fraction in ipairs({ 0.6, 1 }) do
                w.S.secret, w.S.pct, w.S.absorb = protected, fraction, 0.35
                for _, frame in ipairs({ w.single, w.group }) do
                    local spec = frame.MSUFSpec
                    spec.prediction.enabled, spec.prediction.absorb = true, true
                    spec.prediction.fullHealthAbsorbStripe, spec.prediction.overAbsorbOverlay = stripe, overlay
                    prediction.Apply(frame, spec)
                    prediction.Update(frame, "MSUF_UNIT_IDENTITY", frame.MSUFUnitKey)
                    for i = 1, 3 do prediction.Update(frame, "MSUF_FORCE_UPDATE", frame.MSUFUnitKey) end
                    prediction.Disable(frame)
                    prediction.Apply(frame, spec)
                    prediction.Update(frame, "MSUF_FORCE_UPDATE", frame.MSUFUnitKey)
                    assert(frame.absorbBar ~= nil, "reapply lost the absorb bar")
                    cases = cases + 1
                end
            end
        end
    end
end
local violations = stop()
assert(#violations == 0, table.concat(violations, "\n"))
print("prediction_exported_secret_routes_smoke: ok (" .. flavor .. ": " .. cases .. " real single/group routes, strict Watch)")
