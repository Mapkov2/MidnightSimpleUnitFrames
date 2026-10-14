-- Real core graphs, with an optional immutable old tree as argument 3.
-- Palette inputs are external state; all getters below are shipped owners.
local root, flavor, oracle = assert(arg[1]), assert(arg[2]), arg[3]
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local function Tuple(...)
    local out = {}
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        out[i] = type(value) .. ":" .. tostring(value)
    end
    return table.concat(out, "|")
end
local function Probe(repo, preexisting)
    local world = World.New(repo, flavor)
    local palette
    if preexisting then palette = { white = { .2, .3, .4 }, gold = { .1, .2, .3 } } end
    world.env.MSUF_FONT_COLORS = palette
    world:Boot()
    local failure = world:FirstFailure()
    assert(not failure, failure and (failure.file .. ": " .. failure.message))
    local env, ns = world.env, world.core
    env.MSUF_EnsureDB()
    if preexisting then assert(env.MSUF_FONT_COLORS == palette, "public palette replaced at load") end
    local originalPublic, defaults = env.MSUF_FONT_COLORS, ns.MSUF_FONT_COLORS
    assert(defaults.gold[1] == 1 and defaults.gold[2] == .85 and defaults.gold[3] == .1)
    local out, createCalls = {}, 0
    local createColor = env.CreateColor
    env.CreateColor = function(...)
        createCalls = createCalls + 1
        return createColor(...)
    end
    local function Record(label, fn, ...)
        local function Pack(...) return { n = select("#", ...), ... } end
        local result = Pack(pcall(fn, ...))
        if result[1] then
            out[#out + 1] = label .. "=" .. Tuple(unpack(result, 2, result.n))
        else
            local message = tostring(result[2]):match(":%d+: (.*)") or tostring(result[2])
            out[#out + 1] = label .. "=error:" .. message
        end
    end
    local function Capture(label)
        for _, container in ipairs({ { "Public.Colors", ns.Public.Colors }, { "_colorsAPI", ns._colorsAPI } }) do
            local names = {}
            for name, value in pairs(container[2]) do
                if name:match("^Get") and type(value) == "function" then names[#names + 1] = name end
            end
            table.sort(names)
            for _, name in ipairs(names) do
                local a, b
                if name == "GetClassColor" then a = "MAGE"
                elseif name == "GetNPCColor" then a = "enemy"
                elseif name == "GetNPCTypePerUnit" then a = "npcTypeTarget"
                elseif name == "GetCastbarDetailTextColor" then a, b = "player", "Spell" end
                Record(label .. "/" .. container[1] .. "." .. name, container[2][name], a, b)
            end
        end
        for _, name in ipairs({ "MSUF_GetConfiguredFontColor", "MSUF_GetClassBarColor",
            "MSUF_GetNPCReactionColor", "MSUF_GetResolvedPowerColor", "MSUF_GetPowerBarColor",
            "MSUF_GetCastbarTextColor", "MSUF_GetCastbarTargetNameColor", "MSUF_GetCastbarDetailTextColor",
            "MSUF_GetInterruptibleCastColor", "MSUF_GetNonInterruptibleCastColor",
            "MSUF_GetInterruptFeedbackCastColor", "MSUF_GetInterruptUnavailableCastColor" }) do
            local a, b
            if name == "MSUF_GetClassBarColor" then a = "MAGE"
            elseif name == "MSUF_GetNPCReactionColor" then a = "enemy"
            elseif name:find("Power", 1, true) then a, b = 0, "MANA"
            elseif name == "MSUF_GetCastbarDetailTextColor" then a, b = "player", "Spell" end
            if env[name] then Record(label .. "/global." .. name, env[name], a, b)
            else out[#out + 1] = label .. "/global." .. name .. "=absent" end
            if ns[name] then Record(label .. "/namespace." .. name, ns[name], a, b) end
            local publicKey = name:sub(6)
            if ns.Public[publicKey] then Record(label .. "/Public." .. publicKey, ns.Public[publicKey], a, b) end
            if ns.PublicGlobals[name] then Record(label .. "/PublicGlobals." .. name, ns.PublicGlobals[name], a, b) end
        end
        for _, key in ipairs({ "gold", "GOLD", "white", "unknown", "", false, 7 }) do
            for _, container in ipairs({ { "global", env }, { "namespace", ns } }) do
                Record(label .. "/" .. container[1] .. ".RGB." .. tostring(key), container[2].MSUF_GetColorRGBFromKey, key)
                local function Object(fallback)
                    return container[2].MSUF_GetColorFromKey(key, fallback):GetRGBA()
                end
                Record(label .. "/" .. container[1] .. ".object." .. tostring(key), Object)
                Record(label .. "/" .. container[1] .. ".fallback." .. tostring(key), Object, createColor(.7, .6, .5, .4))
            end
        end
        local function FontSettings()
            local _, _, r, g, b = env.MSUF_GetGlobalFontSettings()
            return r, g, b
        end
        Record(label .. "/global.fontSettings", FontSettings)
    end
    local function Profile()
        env.MSUF_DB = { general = {}, classColors = { MAGE = "gold" } }
        env.MSUF_EnsureDB()
        local g = env.MSUF_DB.general
        g.fontColor, g.useCustomFontColor = "gold", false
        g.castbarFontR, g.castbarFontG, g.castbarFontB = nil, nil, nil
        for _, prefix in ipairs({ "castbarInterruptible", "castbarNonInterruptible",
            "castbarInterruptFeedback", "castbarInterruptUnavailable" }) do
            g[prefix .. "R"], g[prefix .. "G"], g[prefix .. "B"] = nil, nil, nil
            g[prefix .. "Color"] = "gold"
        end
        return g
    end
    local g = Profile()
    local function CheckPublic(r, green, b)
        assert(Tuple(ns.Public.Colors.GetGlobalFontColor()) == Tuple(r, green, b), "public global palette color diverged")
        assert(Tuple(ns.Public.Colors.GetCastbarTextColor()) == Tuple(r, green, b), "public castbar palette color diverged")
    end
    CheckPublic(preexisting and .1 or 1, preexisting and .2 or .85, preexisting and .3 or .1)
    Capture("loaded")
    originalPublic.gold[1], originalPublic.gold[2], originalPublic.gold[3] = .31, .42, .53
    CheckPublic(.31, .42, .53)
    Capture("same-table mutation")
    env.MSUF_FONT_COLORS = { white = { .9, .8, .7 }, gold = { .61, .72, .83 } }
    CheckPublic(.61, .72, .83)
    Capture("public replacement")
    assert(ns.MSUF_FONT_COLORS == defaults, "namespace default palette replaced")
    for _, key in ipairs({ "GOLD", "white", "unknown", "", false, 17 }) do
        g.fontColor = key
        Capture("font key " .. tostring(key))
    end
    g.fontColor = "gold"
    for index, entry in ipairs({ {}, { .25 }, false, 17, "invalid" }) do
        env.MSUF_FONT_COLORS.gold = entry
        Capture("invalid entry " .. index .. " " .. type(entry))
    end
    env.MSUF_FONT_COLORS.gold = nil
    CheckPublic(1, 1, 1)
    Capture("missing entry")
    env.MSUF_FONT_COLORS = nil
    CheckPublic(1, 1, 1)
    Capture("missing public table")
    env.MSUF_FONT_COLORS = { gold = { .61, .72, .83 } }
    g.useCustomFontColor = true
    g.fontColorCustomR, g.fontColorCustomG, g.fontColorCustomB = 0, .4, .9
    CheckPublic(0, .4, .9)
    Capture("general custom wins")
    g.castbarFontR, g.castbarFontG, g.castbarFontB = .12, 0, .34
    assert(Tuple(ns.Public.Colors.GetCastbarTextColor()) == Tuple(.12, 0, .34))
    for _, prefix in ipairs({ "castbarInterruptible", "castbarNonInterruptible",
        "castbarInterruptFeedback", "castbarInterruptUnavailable" }) do
        g[prefix .. "R"], g[prefix .. "G"], g[prefix .. "B"] = 0, .25, .75
    end
    env.MSUF_DB.classColors.MAGE = { r = .35, g = .45, b = .55 }
    Capture("castbar custom wins")
    g.castbarFontB, g.fontColorCustomB = nil, nil
    CheckPublic(.61, .72, .83)
    Capture("partial custom falls through")
    env.MSUF_DB.general = { fontColor = "gold", useCustomFontColor = false }
    CheckPublic(.61, .72, .83)
    Capture("same root general replacement")
    g = Profile()
    CheckPublic(.61, .72, .83)
    Capture("profile root replacement")
    defaults.gold[1], defaults.gold[2], defaults.gold[3] = .11, .22, .33
    assert(Tuple(env.MSUF_GetConfiguredFontColor()) == Tuple(.11, .22, .33))
    CheckPublic(.61, .72, .83)
    Capture("default palette mutation")
    ns.MSUF_FONT_COLORS = { gold = { .99, .88, .77 } }
    assert(Tuple(env.MSUF_GetConfiguredFontColor()) == Tuple(.11, .22, .33))
    Capture("namespace palette replacement")
    for index, entry in ipairs({ {}, { .25 }, false, 17, "invalid" }) do
        defaults.gold = entry
        Capture("invalid default entry " .. index)
    end
    defaults.gold = nil
    Capture("missing default entry")
    defaults.gold = { .11, .22, .33 }
    Capture("restored default entry")
    local before = createCalls
    for i = 1, 40 do Capture("warm") end
    assert(createCalls == before, "warm getters made new native color objects")
    out[#out + 1] = "native CreateColor calls=" .. createCalls
    return out
end
for _, preexisting in ipairs({ true, false }) do
    local actual = Probe(root, preexisting)
    if oracle then
        local expected = Probe(oracle, preexisting)
        assert(#actual == #expected, "color accessor count differs from immutable oracle")
        for i = 1, #actual do
            assert(actual[i] == expected[i], flavor .. ": immutable old color owner differs at " .. i
                .. "\nold: " .. tostring(expected[i]) .. "\nnew: " .. tostring(actual[i]))
        end
    end
end
print("color_palette_lifecycle_smoke: OK " .. flavor .. (oracle and " immutable old-owner parity" or ""))
