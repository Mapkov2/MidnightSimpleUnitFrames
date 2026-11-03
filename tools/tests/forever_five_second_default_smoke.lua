local root = assert(arg[1]):gsub("\\", "/")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local count = 0
local function Check(value, message)
    count = count + 1
    assert(value, message)
end
for _, flavor in ipairs({ "Forever", "Mainline", "Vanilla", "TBC", "Mists" }) do
    local world = World.New(root, flavor)
    world:Boot()
    Check(not world:FirstFailure(), flavor .. ": boot failure")
    local env = world.env
    local normalize = env.MSUF_NormalizeProfileDefaults
    local forever = flavor == "Forever"
    -- Fresh defaults and old profiles, including an explicit old Off.
    for _, old in ipairs({ "missing", "off", "on" }) do
        local profile = { bars = {} }
        if old ~= "missing" then profile.bars.manaRegenPause = old == "on" end
        normalize(profile, true)
        Check(profile.bars.manaRegenPause == (forever or old == "on")
            or not forever and old == "missing" and profile.bars.manaRegenPause == nil,
            flavor .. ": wrong initial value for " .. old)
        Check((profile._msufForeverFiveSecondDefault_v1 == true) == forever, flavor .. ": migration marker leaked")
        -- After migration an intentional Off survives repeat normalization.
        profile.bars.manaRegenPause = false
        normalize(profile, true)
        normalize(profile, false, true)
        Check(profile.bars.manaRegenPause == false, flavor .. ": intentional Off was overwritten")
        if forever then
            -- A profile already current on another client must still migrate.
            profile._msufForeverFiveSecondDefault_v1 = nil
            normalize(profile, false, true)
            Check(profile.bars.manaRegenPause == true, "current cross-client profile skipped Forever migration")
            profile.bars.manaRegenPause = nil
            normalize(profile, false, true)
            Check(profile.bars.manaRegenPause == true, "missing default was not restored")
        end
    end
    -- The raw factory result also feeds per-field reset and preview defaults.
    if forever then
        env.MSUF_TryDecodeCompactString = function()
            return { addon = "MSUF", fmt = 2, msuf6 = { schema = 600,
                payload = { general = {}, bars = { manaRegenPause = false } } } }
        end
        local factory = env.MSUF_CreateFactoryDefaultProfile()
        Check(type(factory) == "table" and factory.bars.manaRegenPause == true, "Forever factory reset is Off")
    end
end
print("forever_five_second_default_smoke: " .. count .. " checks passed")
