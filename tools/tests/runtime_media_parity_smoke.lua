-- Run against a real shipped graph. Optional argument 3 is the frozen old tree.
-- The same probes run in isolated client worlds; no removed provider is stubbed.
local root, flavor, oracle = assert(arg[1]), assert(arg[2]), arg[3]
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local function Probe(repo, locale)
    local world = World.New(repo, flavor, { locale = locale })
    world.env.xpcall = function(fn, handler, ...)
        local args, count = { ... }, select("#", ...)
        return xpcall(function() return fn(unpack(args, 1, count)) end, handler)
    end
    world.env.LOCALE_koKR, world.env.LOCALE_ruRU = locale == "koKR", locale == "ruRU"
    world.env.LOCALE_zhCN, world.env.LOCALE_zhTW = locale == "zhCN", locale == "zhTW"
    -- Existing validator override is an input, never a replacement media/font provider.
    world.env.MSUF_IsKnownFileAsset = function(path)
        return not path:find("Invalid", 1, true)
    end
    world:Boot()
    local failure = world:FirstFailure()
    assert(not failure, failure and (failure.file .. ": " .. failure.message))
    local env, ns = world.env, world.core
    env.MSUF_EnsureDB()
    local general = env.MSUF_DB.general
    local out = {}
    local function Record(...)
        local values = {}
        for index = 1, select("#", ...) do values[index] = tostring(select(index, ...)) end
        out[#out + 1] = table.concat(values, "|")
    end
    local default = "Fonts\\FRIZQT___CYR.TTF"
    local keys = { "", "FRIZQT", "Arial Narrow", "MORPHEUS", "SKURRI", "EXPRESSWAY", "EXPRESSWAY_BOLD",
        "EXPRESSWAY_SEMIBOLD", "EXPRESSWAY_EXTRABOLD", "EXPRESSWAY_CONDENSED_LIGHT", "SOUNDSCAPE",
        "Expressway (MSUF)", "Fritz Soundscape", "Missing font", "Interface/AddOns/Missing/Face.ttf",
        "Interface/AddOns/MidnightSimpleUnitFrames/Media/Fonts/Expressway.ttf" }
    for _, key in ipairs(keys) do
        general.fontKey = key
        Record(key, env.MSUF_ResolveFontKeyPath(key), env.MSUF_GetInternalFontPathByKey(key),
            env.MSUF_GetFontPathForKey(key), env.MSUF_GetFontPath())
    end
    for bits = 0, 15 do
        general.noOutline = bits % 2 == 1
        general.boldText = math.floor(bits / 2) % 2 == 1
        general.fontMonochrome = math.floor(bits / 4) % 2 == 1
        general.fontSlug = math.floor(bits / 8) % 2 == 1
        Record(bits, env.MSUF_GetFontFlags())
    end
    for _, flags in ipairs({ "NONE", " OUTLINE , MONOCHROME ,", ",,SLUG,,", "" }) do
        Record(flags, env.MSUF_NormalizeFontFlags(flags))
    end
    local lsm = ns.LSM
    local customFont = "Interface\\AddOns\\Example\\Custom.ttf"
    assert(lsm:Register("font", "Parity custom", customFont, 255))
    assert(lsm:HashTable("font")["Parity custom"] == customFont, "custom registration missing from real LSM")
    assert(env.MSUF_LSM_CallbacksRegistered == true, "LSM bootstrap callback was not initialized")
    general.fontKey = "Parity custom"
    assert(env.MSUF_GetFontPath() == customFont, "registered custom face changed: " .. tostring(env.MSUF_GetFontPath())
        .. " key=" .. tostring(env.MSUF_DB.general.fontKey) .. " registered=" .. tostring(env.MSUF_IsRegisteredLSMFontPath(customFont)))
    Record(env.MSUF_GetFontPath(), env.MSUF_ResolveFontKeyPath("Parity custom"))
    local missing = "Interface\\AddOns\\Example\\Late.ttf"
    assert(env.MSUF_ResolveFontKeyPath(missing) == nil)
    Record(env.MSUF_ResolveFontPath(missing, 14, ""))
    assert(lsm:Register("font", "Parity late", missing, 255))
    assert(env.MSUF_ResolveFontKeyPath(missing) == missing, "late registration remained unavailable")
    Record(env.MSUF_ResolveFontKeyPath(missing))
    local calls, ready, notifications = 0, false, 0
    env.MSUF_OnFontApplyFailed = function() notifications = notifications + 1 end
    local fs = {
        SetFont = function(self, path, size, flags)
            calls = calls + 1
            self.path, self.size, self.flags = path, size, flags
            return ready
        end,
        GetFont = function(self)
            if ready then return self.path, self.size, self.flags end
            return "Fonts\\ARIALN.TTF", 9, ""
        end,
    }
    local applied, requested, source = env.MSUF_ApplyResolvedFont(fs, missing, 14, "OUTLINE,SLUG")
    assert(not applied and source == "pending" and not fs._msufFontRequestPath)
    Record(applied, requested, source, notifications)
    ready = true
    assert(env.MSUF_ApplyResolvedFont(fs, missing, 14, "OUTLINE,SLUG"))
    local before = calls
    assert(env.MSUF_ApplyResolvedFont(fs, missing, 14, "OUTLINE,SLUG"))
    assert(calls == before)
    env.MSUF_FontApplyEpoch = env.MSUF_FontApplyEpoch + 1
    assert(env.MSUF_ApplyResolvedFont(fs, missing, 14, "OUTLINE,SLUG"))
    assert(calls == before + 1)
    Record(calls, fs.path, fs.flags)
    local builtins = env.MSUF_BUILTIN_BAR_TEXTURES
    local names = {}
    for key in pairs(builtins) do names[#names + 1] = key end
    table.sort(names)
    for _, key in ipairs(names) do
        general.barTexture, general.castbarTexture = key, key
        assert(env.MSUF_ResolveStatusbarTextureKey(key) == builtins[key])
        Record(key, env.MSUF_GetBarTexture(), env.MSUF_GetCastbarTexture())
    end
    for _, key in ipairs({ "", "Missing texture", "MSUF Smooth", "Interface/Buttons/WHITE8x8" }) do
        general.barTexture, general.castbarTexture = key, key
        Record(key, env.MSUF_ResolveStatusbarTextureKey(key), env.MSUF_GetBarTexture(), env.MSUF_GetCastbarTexture())
    end
    local texture = "Interface\\AddOns\\Example\\Custom.tga"
    Record(env.MSUF_ResolveStatusbarTextureKey("Parity texture"))
    local invalid = "Interface\\AddOns\\Example\\Invalid.tga"
    assert(lsm:Register("statusbar", "Parity invalid", invalid))
    assert(env.MSUF_ResolveStatusbarTextureKey("Parity invalid") == "Interface\\TargetingFrame\\UI-StatusBar")
    Record(env.MSUF_ResolveStatusbarTextureKey(invalid), env.MSUF_ResolveStatusbarTextureKey("Parity invalid"))
    lsm:Register("statusbar", "Parity invalid", texture)
    Record(env.MSUF_ResolveStatusbarTextureKey("Parity invalid"))
    lsm:Register("statusbar", "Parity texture", texture)
    assert(env.MSUF_ResolveStatusbarTextureKey("Parity texture") == texture)
    Record(env.MSUF_ResolveStatusbarTextureKey("Parity texture"))
    env.MSUF_ClearResolvedStatusbarTextureCache()
    local oldDB = env.MSUF_DB
    env.MSUF_DB = { general = { fontKey = "ARIALN", barTexture = "Flat" } }
    assert(env.MSUF_GetFontPath() == "Fonts\\ARIALN.TTF")
    assert(env.MSUF_GetBarTexture() == builtins.Flat)
    Record(env.MSUF_GetGlobalFontSettings())
    env.MSUF_DB = oldDB
    for _, key in ipairs({ "white", "gold", "PINK", "missing" }) do
        general.fontColor, general.useCustomFontColor = key, false
        Record(env.MSUF_GetConfiguredFontColor())
    end
    general.useCustomFontColor = true
    general.fontColorCustomR, general.fontColorCustomG, general.fontColorCustomB = 0, 0.4, 0.9
    Record(env.MSUF_GetConfiguredFontColor())
    assert(env.MSUF_ResolveFontPath(nil, 14, "", "Missing face") == default)
    env.MSUF_DB = { general = {} }
    env.MSUF_GetConfiguredFontColor, ns.MSUF_GetConfiguredFontColor = nil, nil
    local path, flags, r, g, b, size, shadow = env.MSUF_GetGlobalFontSettings()
    assert(path == default and flags == "OUTLINE" and r == 1 and g == 1 and b == 1 and size == 14 and shadow == true)
    Record(path, flags, r, g, b, size, shadow)
    return table.concat(out, "\n")
end
for _, locale in ipairs({ "enUS", "ruRU", "koKR", "zhCN", "zhTW" }) do
    local actual = Probe(root, locale)
    if oracle then assert(actual == Probe(oracle, locale), flavor .. "/" .. locale .. ": old media oracle diverged") end
end
print("runtime_media_parity_smoke: OK " .. flavor .. (oracle and " old-oracle identical" or ""))
