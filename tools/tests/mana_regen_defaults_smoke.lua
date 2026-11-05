-- Forever defaults remain portable while later deliberate Off choices survive.
local root = assert(arg[1]):gsub("\\", "/")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local checked, failures = 0, {}
local function Check(ok, message)
    checked = checked + 1
    if not ok then failures[#failures + 1] = message end
end
local stamps = {
    manaRegenPause = "_msufForeverFiveSecondDefault_v1",
    manaGainPulse = "_msufForeverManaTickDefault_v1",
}
for _, flavor in ipairs({ "Forever", "Mainline", "Vanilla", "TBC", "Mists" }) do
    local world = World.New(root, flavor)
    world:Boot()
    local failure = world:FirstFailure()
    assert(not failure, failure and failure.message)
    local env, ns = world.env, world.core
    local public = ns.PublicGlobals or env
    local normalize, forever = public.MSUF_NormalizeProfileDefaults, flavor == "Forever"
    for _, old in ipairs({ "missing", "off", "on" }) do
        local profile = { bars = {} }
        for key in pairs(stamps) do
            if old ~= "missing" then profile.bars[key] = old == "on" end
        end
        normalize(profile, true)
        Check(profile.bars.manaRegenStyle == "spark" and profile.bars.manaRegenSparkWidth == 2
            and profile.bars.manaRegenSparkAlpha == .35, flavor .. ": mana style defaults missing")
        for key, stamp in pairs(stamps) do
            Check((profile.bars[key] == true) == (forever or old == "on"), flavor .. ": initial " .. old .. " " .. key)
            Check((profile[stamp] == true) == forever, flavor .. ": stamp leaked " .. key)
            profile.bars[key] = false
        end
        normalize(profile, true)
        normalize(profile, false, true)
        for key in pairs(stamps) do Check(profile.bars[key] == false, flavor .. ": deliberate Off overwritten " .. key) end
        profile.bars.manaRegenStyle, profile.bars.manaRegenSparkWidth, profile.bars.manaRegenSparkAlpha = "bars", 7, 0
        normalize(profile, true)
        Check(profile.bars.manaRegenStyle == "bars" and profile.bars.manaRegenSparkWidth == 7
            and profile.bars.manaRegenSparkAlpha == 0, flavor .. ": mana display choice overwritten")
        if forever then
            for key, stamp in pairs(stamps) do
                profile[stamp] = nil
                normalize(profile, false, true)
                Check(profile.bars[key] == true, "current cross-client profile skipped " .. key)
                profile.bars[key] = nil
                normalize(profile, false, true)
                Check(profile.bars[key] == true, "missing default not restored " .. key)
                profile.bars[key] = false
            end
        end
    end
    if forever then
        -- The old FSR migration already recorded a user's deliberate Off.
        local previous = { bars = { manaRegenPause = false, manaGainPulse = false },
            _msufForeverFiveSecondDefault_v1 = true }
        normalize(previous, true)
        Check(previous.bars.manaRegenPause == false, "the pulse update overwrote the earlier FSR choice")
        Check(previous.bars.manaGainPulse == true, "the earlier FSR stamp skipped the new pulse default")
        env.MSUF_TryDecodeCompactString = function()
            return { addon = "MSUF", fmt = 2, msuf6 = { schema = 600,
                payload = { general = {}, bars = { manaRegenPause = false, manaGainPulse = false } } } }
        end
        local factory = public.MSUF_CreateFactoryDefaultProfile()
        for key, stamp in pairs(stamps) do
            Check(factory and factory.bars[key] == true and factory[stamp] == true, "factory/reset is Off " .. key)
            if ns.Defaults then Check(ns.Defaults.Get("bars", key) == true, "per-field reset default is Off " .. key) end
        end
        Check(factory.bars.manaRegenStyle == "spark" and factory.bars.manaRegenSparkWidth == 2
            and factory.bars.manaRegenSparkAlpha == .35, "factory mana display defaults missing")
    elseif ns.Defaults then
        for key in pairs(stamps) do Check(ns.Defaults.Get("bars", key) == false, flavor .. ": changed per-field default " .. key) end
    end
    -- Exercise the real full-export projection, including compatibility-only consumers.
    public.MSUF_EnsureDB(true)
    local active = env.MSUF_DB
    for key, stamp in pairs(stamps) do active.bars[key], active[stamp] = false, true end
    local captured
    public.MSUF_EncodeCompactTableMSUF3 = function(snapshot) captured = snapshot return "fixture" end
    env.MSUF_EncodeCompactTableMSUF3 = public.MSUF_EncodeCompactTableMSUF3
    Check(type(public.MSUF_ExportSelectionToString("all")) == "string", flavor .. ": full export failed")
    if captured then
        for _, payload in ipairs({ captured.payload, captured.msuf6 and captured.msuf6.payload }) do
            for key, stamp in pairs(stamps) do
                Check(payload[stamp] == true, flavor .. ": portable stamp lost " .. key)
                local imported = ns.ProfileFields.Copy(payload)
                normalize(imported, true)
                Check(imported.bars[key] == false, flavor .. ": exported Off was reenabled " .. key)
            end
        end
    end
end
for _, failure in ipairs(failures) do print("FAIL: " .. failure) end
assert(#failures == 0, #failures .. " mana default regressions")
print("mana_regen_defaults_smoke: " .. checked .. " checks passed")
